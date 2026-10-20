#!/usr/bin/env python3
"""Upload the Blender-made FBX models of Nimbus Climb to Roblox with the Open Cloud Assets API (PROTOTYPE).

    python3 tools/upload_assets.py --dry-run                 # print the exact requests, touch nothing
    python3 tools/upload_assets.py                           # upload new / changed FBX files, keep ids stable
    python3 tools/upload_assets.py --only PebblePup          # one model (repeatable)
    python3 tools/upload_assets.py --refresh                 # re-read moderation state of every known asset
    python3 tools/upload_assets.py --emit-lua src/shared/MeshIds.lua   # also write the Luau id table

Environment (never stored, never printed):
    ROBLOX_API_KEY       Open Cloud API key with the "assets" API: Read + Write (create.roblox.com/credentials)
    ROBLOX_CREATOR_ID    the user id (or group id) that owns the game; assets must have the same owner, else
                         InsertService:LoadAsset refuses them at runtime
    ROBLOX_CREATOR_TYPE  "user" (default) or "group"

What it does, per entry of the manifest (default blender/meshes.json):
  * sha256 of the FBX (+ the upload-relevant manifest fields). Unchanged since the last successful upload -> skip.
  * no asset id yet -> POST https://apis.roblox.com/assets/v1/assets (multipart: request JSON + fileContent,
    assetType "Model", content type model/fbx) -> a NEW Model asset (Roblox stores it as a package).
  * asset id known and the file changed -> PATCH https://apis.roblox.com/assets/v1/assets/{assetId}: a NEW VERSION
    of the same asset, so the id in the game never changes (content updates are FBX-only, see the docs).
  * polls GET https://apis.roblox.com/assets/v1/operations/{operationId} until done; records assetId, revisionId and
    moderationResult.moderationState. A poll that times out is saved as "pendingOperation" and resumed by the next
    run instead of uploading again (no duplicate assets after a crash or Ctrl-C).
  * writes the id table (default blender/mesh_ids.json) atomically after every asset.
  * client-side throttle under the documented limits (120 create/update per minute per key owner, 300 operation reads
    per minute), honours HTTP 429 retry-after, retries 5xx with exponential backoff.

Docs: create.roblox.com/docs/cloud/guides/usage-assets, /docs/reference/cloud/assets/v1 (rate limits in the
x-roblox-rate-limits of each endpoint), /docs/cloud/reference/rate-limits, /docs/cloud/reference/patterns.
Python 3 standard library only.
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
# In the repo this file lives in tools/ (ROOT = repo root). The prototype accepts --root to point anywhere.
DEFAULT_ROOT = os.path.dirname(HERE)

BASE_URL = "https://apis.roblox.com"
CREATE_PATH = "/assets/v1/assets"
UPDATE_PATH = "/assets/v1/assets/{assetId}"
GET_ASSET_PATH = "/assets/v1/assets/{assetId}"
OPERATION_PATH = "/assets/v1/operations/{operationId}"

MAX_FILE_BYTES = 20 * 1024 * 1024        # "file size up to 20 MB" per create/update call
MAX_DESCRIPTION = 1000                   # Asset.description: "Limit to 1000 characters"
MAX_TRIANGLES_PER_MESH = 20000           # art/modeling/specifications: "Individual meshes can not exceed 20,000 triangles"
WRITE_PER_MINUTE = 100                   # documented 120/min for POST + PATCH (per API key owner); keep headroom
READ_PER_MINUTE = 250                    # documented 300/min for GET operations
CONTENT_TYPES = {".fbx": "model/fbx", ".gltf": "model/gltf+json", ".glb": "model/gltf-binary"}
TABLE_VERSION = 1


class UploadError(Exception):
    pass


# ---------------------------------------------------------------------------------------------- small helpers
def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fingerprint(entry, file_hash):
    """What decides "changed": the file bytes plus the manifest fields that go into the upload."""
    relevant = {"file": file_hash, "displayName": entry.get("displayName"), "description": entry.get("description")}
    return hashlib.sha256(json.dumps(relevant, sort_keys=True).encode("utf-8")).hexdigest()


def atomic_write_json(path, data):
    tmp = path + ".tmp"
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def mask(secret):
    if not secret or secret.startswith("<"):
        return secret
    return secret[:4] + "..." + "(%d chars)" % len(secret)


def safe_name(name):
    """Plain names only: a moderated (filtered) display name fails the whole upload with HTTP 400."""
    cleaned = "".join(c for c in name if c.isalnum() or c in " _-").strip()
    return cleaned[:50] or "NimbusModel"


class Throttle:
    """At most `per_minute` calls in any 60 s window (sliding window)."""

    def __init__(self, per_minute):
        self.per_minute = per_minute
        self.stamps = []

    def wait(self):
        now = time.monotonic()
        self.stamps = [t for t in self.stamps if now - t < 60.0]
        if len(self.stamps) >= self.per_minute:
            time.sleep(60.0 - (now - self.stamps[0]) + 0.05)
        self.stamps.append(time.monotonic())


# ---------------------------------------------------------------------------------------------- HTTP
def encode_multipart(fields, files):
    """fields: [(name, text)], files: [(name, filename, content_type, bytes)] -> (body bytes, content-type header).
    Same shape as curl --form 'request=...' --form 'fileContent=@file;type=model/fbx'."""
    boundary = "----NimbusClimb" + uuid.uuid4().hex
    out = []
    for name, value in fields:
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n" % (boundary, name)).encode("utf-8"))
        out.append(value.encode("utf-8"))
        out.append(b"\r\n")
    for name, filename, ctype, data in files:
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
                    % (boundary, name, filename, ctype)).encode("utf-8"))
        out.append(data)
        out.append(b"\r\n")
    out.append(("--%s--\r\n" % boundary).encode("utf-8"))
    return b"".join(out), "multipart/form-data; boundary=" + boundary


class Client:
    def __init__(self, base_url, api_key, dry_run, log):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.dry_run = dry_run
        self.log = log
        self.writes = Throttle(WRITE_PER_MINUTE)
        self.reads = Throttle(READ_PER_MINUTE)
        host = urllib.parse.urlparse(self.base_url).hostname or ""
        if host in ("127.0.0.1", "localhost"):
            # local test server (tools test only): no proxy
            self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        else:
            self.opener = urllib.request.build_opener()  # honours HTTPS_PROXY / system CA settings

    def request(self, method, path, body=None, content_type=None, describe=None, write=False):
        url = self.base_url + path
        headers = {"x-api-key": self.api_key, "Accept": "application/json"}
        if content_type:
            headers["Content-Type"] = content_type
        if self.dry_run:
            self.print_request(method, url, headers, describe)
            return None
        delay = 2.0
        for attempt in range(1, 7):
            (self.writes if write else self.reads).wait()
            req = urllib.request.Request(url, data=body, method=method, headers=headers)
            try:
                with self.opener.open(req, timeout=120) as resp:
                    raw = resp.read()
                    return json.loads(raw.decode("utf-8")) if raw else {}
            except urllib.error.HTTPError as e:
                text = e.read().decode("utf-8", "replace")
                if e.code == 429 or 500 <= e.code < 600:
                    retry_after = e.headers.get("retry-after")
                    wait = float(retry_after) if retry_after and retry_after.replace(".", "", 1).isdigit() else delay
                    self.log("  HTTP %d on %s %s, retry %d in %.1f s" % (e.code, method, path, attempt, wait))
                    time.sleep(wait)
                    delay = min(delay * 2, 60.0)
                    continue
                raise UploadError("HTTP %d on %s %s: %s" % (e.code, method, path, text[:500]))
            except urllib.error.URLError as e:
                self.log("  network error on %s %s (%s), retry %d in %.1f s" % (method, path, e.reason, attempt, delay))
                time.sleep(delay)
                delay = min(delay * 2, 60.0)
        raise UploadError("gave up on %s %s after retries" % (method, path))

    def print_request(self, method, url, headers, describe):
        shown = dict(headers)
        shown["x-api-key"] = mask(shown["x-api-key"])
        print("    %s %s" % (method, url))
        for k in sorted(shown):
            print("      %s: %s" % (k, shown[k]))
        if describe:
            for line in describe:
                print("      " + line)


# ---------------------------------------------------------------------------------------------- the work
def creator_block(creator_type, creator_id):
    key = "groupId" if creator_type == "group" else "userId"
    return {key: str(creator_id)}


def build_request_json(entry, name, creator, asset_id=None):
    req = {"assetType": "Model", "creationContext": {"creator": creator}}
    if asset_id is None:
        req["displayName"] = safe_name(entry.get("displayName") or "NC " + name)
        req["description"] = (entry.get("description") or "Nimbus Climb model " + name)[:MAX_DESCRIPTION]
    else:
        # content update: the asset id identifies the asset, the upload becomes its next version
        req["assetId"] = str(asset_id)
    return req


def upload_one(client, name, entry, record, creator, root, args, log):
    path = os.path.join(root, entry["fbx"])
    if not os.path.isfile(path):
        raise UploadError("missing file %s (build it with Blender first)" % path)
    ext = os.path.splitext(path)[1].lower()
    if ext not in CONTENT_TYPES:
        raise UploadError("%s: only .fbx / .gltf / .glb upload as Model assets" % path)
    size = os.path.getsize(path)
    if size > MAX_FILE_BYTES:
        raise UploadError("%s is %.1f MB; the API takes up to 20 MB per call" % (path, size / 1048576.0))
    tris = entry.get("maxTrianglesPerMesh")
    if tris is not None and int(tris) > MAX_TRIANGLES_PER_MESH:
        raise UploadError("%s: a mesh has %s triangles (limit %d per mesh)" % (name, tris, MAX_TRIANGLES_PER_MESH))
    file_hash = sha256_file(path)
    fp = fingerprint(entry, file_hash)
    asset_id = record.get("assetId")

    # 1) an operation left over from an interrupted run: finish it instead of uploading again
    if record.get("pendingOperation") and not args.dry_run:
        log("  resuming operation %s" % record["pendingOperation"])
        return finish(client, name, record, record["pendingOperation"], record.get("pendingFingerprint"), args, log)

    # 2) unchanged since the last successful upload
    if asset_id and record.get("fingerprint") == fp and not args.force:
        log("  unchanged (asset %s, revision %s) - skipped" % (asset_id, record.get("revisionId")))
        return record

    if asset_id and ext != ".fbx":
        raise UploadError("%s: content updates are FBX-only (usage-assets: 'you can only update the asset content "
                          "for .fbx files'); export FBX" % name)

    request_json = build_request_json(entry, name, creator, asset_id)
    with open(path, "rb") as f:
        data = f.read()
    body, ctype = encode_multipart([("request", json.dumps(request_json))],
                                   [("fileContent", os.path.basename(path), CONTENT_TYPES[ext], data)])
    if asset_id:
        method, api_path, what = "PATCH", UPDATE_PATH.format(assetId=asset_id), "update -> new version of %s" % asset_id
    else:
        method, api_path, what = "POST", CREATE_PATH, "create new Model asset"
    log("  %s (%s, %d bytes, sha256 %s...)" % (what, os.path.basename(path), size, file_hash[:12]))
    describe = [
        "body: multipart/form-data (%d bytes)" % len(body),
        "  part 'request' (text): %s" % json.dumps(request_json),
        "  part 'fileContent': filename=%s; Content-Type: %s; %d bytes; sha256=%s"
        % (os.path.basename(path), CONTENT_TYPES[ext], size, file_hash),
        "curl equivalent:",
        "  curl -X %s '%s%s' -H 'x-api-key: $ROBLOX_API_KEY' \\" % (method, client.base_url, api_path),
        "    --form 'request=%s' \\" % json.dumps(request_json),
        "    --form 'fileContent=@\"%s\";type=%s'" % (path, CONTENT_TYPES[ext]),
        "then: GET %s%s every 2-10 s until done=true -> response.assetId / revisionId / moderationResult"
        % (client.base_url, OPERATION_PATH),
    ]
    op = client.request(method, api_path, body=body, content_type=ctype, describe=describe, write=True)
    if args.dry_run:
        return record
    op_path = (op or {}).get("path") or ""
    if not op_path.startswith("operations/"):
        raise UploadError("unexpected response (no operation path): %s" % json.dumps(op)[:300])
    op_id = op_path.split("/", 1)[1]
    record["pendingOperation"] = op_id
    record["pendingFingerprint"] = fp
    record["pendingFileSha256"] = file_hash
    return finish(client, name, record, op_id, fp, args, log)


def finish(client, name, record, op_id, fp, args, log):
    """Poll the operation until done (docs: cloud/reference/patterns 'long-running operations')."""
    deadline = time.monotonic() + args.poll_timeout
    delay = 2.0
    while True:
        op = client.request("GET", OPERATION_PATH.format(operationId=op_id))
        if op.get("done"):
            break
        if time.monotonic() > deadline:
            log("  operation %s still running after %d s; saved, the next run resumes it" % (op_id, args.poll_timeout))
            return record
        time.sleep(delay)
        delay = min(delay * 1.5, 10.0)
    record.pop("pendingOperation", None)
    pending_fp = record.pop("pendingFingerprint", None)
    pending_sha = record.pop("pendingFileSha256", None)
    if op.get("error"):
        err = op["error"]
        record["lastError"] = "%s: %s" % (err.get("code"), err.get("message"))
        raise UploadError("operation %s failed: %s" % (op_id, record["lastError"]))
    resp = op.get("response") or {}
    new_id = resp.get("assetId") or (resp.get("path") or "").replace("assets/", "")
    if not new_id:
        raise UploadError("operation %s done without an asset id: %s" % (op_id, json.dumps(op)[:300]))
    if record.get("assetId") and str(record["assetId"]) != str(new_id):
        raise UploadError("asset id changed from %s to %s - refusing to overwrite" % (record["assetId"], new_id))
    record["assetId"] = int(new_id)
    record["revisionId"] = resp.get("revisionId")
    record["revisionCreateTime"] = resp.get("revisionCreateTime")
    record["moderationState"] = (resp.get("moderationResult") or {}).get("moderationState")
    record["fingerprint"] = fp or pending_fp
    record["fileSha256"] = pending_sha or record.get("fileSha256")
    record["uploadedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    record.pop("lastError", None)
    log("  done: asset %s revision %s moderation %s" % (record["assetId"], record["revisionId"], record["moderationState"]))
    return record


def refresh(client, name, record, log):
    """GET /assets/v1/assets/{id}: the current revision and moderation state (e.g. Reviewing -> Approved)."""
    if not record.get("assetId"):
        return record
    data = client.request("GET", GET_ASSET_PATH.format(assetId=record["assetId"]))
    if data is None:
        return record
    record["revisionId"] = data.get("revisionId", record.get("revisionId"))
    record["moderationState"] = (data.get("moderationResult") or {}).get("moderationState", record.get("moderationState"))
    log("  %s: asset %s revision %s moderation %s" % (name, record["assetId"], record["revisionId"], record["moderationState"]))
    return record


def emit_lua(path, table):
    """The Luau id table the game reads (numbers only: tools/check.mjs forbids rbxassetid:// strings in src/)."""
    lines = [
        "-- GENERATED by tools/upload_assets.py from blender/mesh_ids.json - do not edit by hand.",
        "-- Model asset ids of the Blender meshes (Open Cloud uploads, owned by the game's owner). A missing or 0 id",
        "-- means: not uploaded yet, MeshLibrary falls back to the Part builders.",
        "local MeshIds = {",
    ]
    for name in sorted(table["assets"]):
        rec = table["assets"][name]
        state = rec.get("moderationState") or ""
        if rec.get("assetId") and "REJECTED" not in state.upper():
            lines.append("\t%s = %d, -- revision %s %s" % (name, int(rec["assetId"]), rec.get("revisionId"), state))
    lines += ["}", "", "return MeshIds", ""]
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=DEFAULT_ROOT, help="base folder of the relative paths (default: repo root)")
    ap.add_argument("--manifest", default="blender/meshes.json")
    ap.add_argument("--ids", default="blender/mesh_ids.json", help="the id table (read + written)")
    ap.add_argument("--emit-lua", default=None, help="also write the Luau id module (e.g. src/shared/MeshIds.lua)")
    ap.add_argument("--only", action="append", default=[], help="upload only these names (repeatable)")
    ap.add_argument("--dry-run", action="store_true", help="print the exact requests; no network, no writes")
    ap.add_argument("--force", action="store_true", help="upload even when unchanged (makes a new version)")
    ap.add_argument("--refresh", action="store_true", help="only re-read revision + moderation of known assets")
    ap.add_argument("--poll-timeout", type=int, default=300)
    ap.add_argument("--base-url", default=BASE_URL, help=argparse.SUPPRESS)  # tests point this at a local server
    args = ap.parse_args(argv)

    root = os.path.abspath(args.root)
    manifest_path = os.path.join(root, args.manifest)
    ids_path = os.path.join(root, args.ids)
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)
    assets = manifest.get("assets") or {}
    try:
        with open(ids_path, encoding="utf-8") as f:
            table = json.load(f)
    except FileNotFoundError:
        table = {"version": TABLE_VERSION, "assets": {}}
    table.setdefault("assets", {})

    api_key = os.environ.get("ROBLOX_API_KEY", "")
    creator_id = os.environ.get("ROBLOX_CREATOR_ID", "")
    creator_type = (os.environ.get("ROBLOX_CREATOR_TYPE") or "user").lower()
    if creator_type not in ("user", "group"):
        sys.exit("ROBLOX_CREATOR_TYPE must be 'user' or 'group'")
    if not args.dry_run and (not api_key or not creator_id.isdigit()):
        sys.exit("set ROBLOX_API_KEY and ROBLOX_CREATOR_ID (numbers only) first, or use --dry-run")
    if args.dry_run:
        api_key = api_key or "<ROBLOX_API_KEY>"
        creator_id = creator_id or "<ROBLOX_CREATOR_ID>"
    creator = creator_block(creator_type, creator_id)
    stored_creator = table.get("creator")
    if stored_creator and stored_creator != creator and not args.dry_run:
        sys.exit("the id table was made for creator %s, not %s: a different owner cannot update these assets "
                 "(and the game could not load them)" % (stored_creator, creator))

    def log(msg):
        print(msg, flush=True)

    client = Client(args.base_url, api_key, args.dry_run, log)
    names = [n for n in sorted(assets) if not args.only or n in args.only]
    unknown = [n for n in args.only if n not in assets]
    if unknown:
        sys.exit("not in the manifest: " + ", ".join(unknown))
    print("%s %d model(s) as %s %s%s" % ("DRY RUN:" if args.dry_run else "Uploading", len(names), creator_type,
                                         creator_id, " (refresh only)" if args.refresh else ""))
    failures = 0
    for name in names:
        print("- " + name)
        record = dict(table["assets"].get(name) or {})
        try:
            if args.refresh:
                record = refresh(client, name, record, log)
            else:
                record = upload_one(client, name, assets[name], record, creator, root, args, log)
        except UploadError as e:
            failures += 1
            record["lastError"] = str(e)
            log("  FAILED: %s" % e)
        except KeyboardInterrupt:
            if not args.dry_run:
                table["assets"][name] = record
                atomic_write_json(ids_path, table)
            raise
        if not args.dry_run:
            table["assets"][name] = record
            table["creator"] = creator
            table["version"] = TABLE_VERSION
            atomic_write_json(ids_path, table)  # after every asset: an interrupted run loses nothing
    if not args.dry_run and args.emit_lua:
        emit_lua(os.path.join(root, args.emit_lua), table)
        print("wrote " + os.path.join(root, args.emit_lua))
    if args.dry_run:
        print("dry run: nothing was sent and nothing was written")
    print("%d failed" % failures if failures else "ok")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
