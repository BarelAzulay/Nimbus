#!/usr/bin/env python3
"""Upload the Blender meshes of Nimbus Climb to Roblox (Open Cloud Assets API) and write src/shared/MeshIds.lua.

Phase 6, recipe 4.7 (docs/phase6/recipe.md; ARCHITECTURE_V3.md "## Phase 6"). DRY RUN BY DEFAULT: without --upload it
only prints what it would send and writes nothing.

    python3 tools/upload_assets.py                          # dry run: the plan + the exact requests, nothing sent
    python3 tools/upload_assets.py --only cal_axes          # dry run of one key (repeatable / comma separated)
    python3 tools/upload_assets.py --upload --only cal_axes # REAL upload (needs the player's OK: see recipe section 6)
    python3 tools/upload_assets.py --upload --refresh       # re-read moderation state of every known asset
    python3 tools/upload_assets.py --textures               # dry run of the IMAGE class: the gate vortex PNG layers
    python3 tools/upload_assets.py --class pets             # dry run of one catalog class (blender/catalog/pets.json)
    python3 tools/upload_assets.py --textures --set-id vortex_arms=123   # dry run of the Decal -> Image id swap

--class CATALOG (repeatable / comma separated): the upload keys of blender/catalog/<CATALOG>.json (the entries without
"upload": false, _low keys included), added to the --only keys. Mesh class only.

--textures (Phase 6 W2b): the same rules for the Image class: index blender/textures/textures.json (written by
blender/textures/build_vortex.py: key -> png, contentHash), state blender/textures/upload_state.json, output
src/shared/TextureIds.lua (rule texture-ids: numbers only; empty = the vortex's effects-only fallback). Each PNG goes up
as assetType "Decal" with image/png. CHECK AT CALIBRATION (the first real image upload, with the player's OK): the id the
operation returns must load in an ImageLabel ("rbxassetid://<id>"); if it is the Decal wrapper and not its Image, put
the Image id in with --set-id KEY=IMAGEID (--textures --upload --set-id ...: sends nothing, records the Image id as
assetId, keeps the Decal id as decalAssetId, rewrites TextureIds.lua). Never --upload without the player's OK.
--set-id on a mesh key is refused unless --allow-mesh-set-id says it is meant (a Model id needs no swap).

Environment (never stored, never printed):
    ROBLOX_API_KEY       Open Cloud API key with the Assets API (Read + Write), made by the experience owner
    ROBLOX_CREATOR_ID    the user id or group id that OWNS THE EXPERIENCE (else LoadAsset refuses the assets at runtime
                         and every model silently stays on the Part build)
    ROBLOX_CREATOR_TYPE  "user" (default) or "group"

Inputs:  blender/meshes.json  { "keys": { key: { fbx, displayName, description, maxTrianglesPerMesh, contentHash,
                                                     structureHash, fbxSha256 } } }  ("assets" or a bare map work too)
         blender/out/<key>.fbx (or the entry's "fbx" path)
Outputs: blender/upload_state.json  (creator, per key: assetId, revisionId, moderationState, contentHash,
                                     structureHash, pending operation ...; written after every asset)
         src/shared/MeshIds.lua     (GENERATED: `return { key = 123, ... }`, sorted, numbers only; Rejected ids left
                                     out, Reviewing ids kept - they simply fail to load and fall back)

Rules (recipe 4.7):
  * fingerprint = the kit's contentHash (not the FBX bytes): unchanged -> skipped.
  * changed and the structureHash is the same as the uploaded one -> PATCH (a new version, same id: running servers
    keep their copy, new servers load the new one). Structure changed -> a NEW asset (POST), so the key's id changes in
    the same commit as its manifest and an old server never loads a mesh its manifest does not describe.
  * images (--textures) are NEVER updated in place: Open Cloud content updates are Model-only, so a changed PNG (any
    contentHash change, same size or not; the structureHash is the image's size + pixel format) is a NEW asset whose
    id replaces the old one in TextureIds.lua. --force on an unchanged, uploaded image is refused (a duplicate).
  * the FBX must be the one the kit exported for this contentHash: meshes.json "fbxSha256" (written by an export
    build, null after a --no-export build) or, for older entries, blender/out/<key>.manifest.json (verify ok + same
    contentHash). A stale FBX is refused, never uploaded under the new hashes.
  * every call returns an operation; it is polled until done. A poll that times out is saved and RESUMED by the next
    run (no duplicate assets after a crash or Ctrl-C).
  * HTTP 429 (retry-after honoured) and 5xx / network errors are retried with backoff (reads and PATCH). A CREATE
    (POST) is retried only when Roblox cannot have made the asset (429, 503, or the request never got out). After a
    500 / 502 / 504 or a dropped connection once the upload was sent, or a crash mid-POST, the key is marked
    "pendingCreate" in upload_state.json and REFUSED until the owner checked Creator Hub for it:
        --adopt KEY=ASSETID   it was created: record that id (no new upload)
        --not-created KEY     it is not there: forget the mark, the run creates it again
    (no duplicate assets in the owner's inventory).
  * a client-side throttle keeps writes under the documented 120 / minute and operation reads under 300 / minute.
  * one key's failure (any error) is recorded as its lastError and the batch goes on (exit 1 at the end).
  * the creator recorded in upload_state.json is never switched.
Python 3 standard library only.
"""
import argparse
import hashlib
import http.client
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.dirname(HERE)

BASE_URL = "https://apis.roblox.com"
CREATE_PATH = "/assets/v1/assets"
UPDATE_PATH = "/assets/v1/assets/{assetId}"
GET_ASSET_PATH = "/assets/v1/assets/{assetId}"
OPERATION_PATH = "/assets/v1/operations/{operationId}"

MAX_FILE_BYTES = 20 * 1024 * 1024        # 20 MB per create / update call
MAX_DESCRIPTION = 1000
MAX_TRIANGLES_PER_MESH = 20000           # importer hard limit per mesh
WRITE_PER_MINUTE = 100                   # documented 120 / min (POST + PATCH); headroom
READ_PER_MINUTE = 250                    # documented 300 / min (GET operations / assets)
MAX_ATTEMPTS = 6
STATE_VERSION = 1
KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class UploadError(Exception):
    pass


class CreateUnknown(UploadError):
    """a POST create whose outcome is unknown (the asset may exist): never retried blindly"""


class Refusal(SystemExit):
    """A usage refusal (exit code 2) with a message."""

    def __init__(self, msg):
        super().__init__(2)
        self.msg = msg

    def __str__(self):
        return self.msg


# ------------------------------------------------------------------------------------------------ helpers
def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def atomic_write(path, text):
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def atomic_write_json(path, data):
    atomic_write(path, json.dumps(data, indent=2, sort_keys=True) + "\n")


def mask(secret):
    if not secret or secret.startswith("<"):
        return secret
    return "<hidden, %d chars>" % len(secret)


def safe_name(name):
    """Plain words only: a filtered display name fails the whole upload with HTTP 400."""
    cleaned = "".join(c for c in name if c.isalnum() or c in " _-").strip()
    return cleaned[:50] or "Nimbus Model"


def is_rejected(state):
    return "REJECTED" in str(state or "").upper()


class Throttle:
    """At most `per_minute` calls in any 60 s window (sliding window). `clock` / `sleep` are injectable (tests)."""

    def __init__(self, per_minute, clock=time.monotonic, sleep=time.sleep):
        self.per_minute = per_minute
        self.stamps = []
        self.clock = clock
        self.sleep = sleep

    def wait(self):
        now = self.clock()
        self.stamps = [t for t in self.stamps if now - t < 60.0]
        if len(self.stamps) >= self.per_minute:
            self.sleep(60.0 - (now - self.stamps[0]) + 0.05)
        self.stamps.append(self.clock())


def encode_multipart(fields, files):
    """fields: [(name, text)], files: [(name, filename, content_type, bytes)] -> (body, content-type header)."""
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


# ------------------------------------------------------------------------------------------------ HTTP
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
            self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # the local test fake
        else:
            self.opener = urllib.request.build_opener()  # honours HTTPS_PROXY and the system CA settings

    def request(self, method, path, body=None, content_type=None, write=False, describe=None, idempotent=True):
        """One API call with retries. idempotent=False (the POST create): retried only when Roblox cannot have made the
        asset; an unknown outcome raises CreateUnknown instead of a second POST (which would duplicate the asset)."""
        url = self.base_url + path
        headers = {"x-api-key": self.api_key, "Accept": "application/json"}
        if content_type:
            headers["Content-Type"] = content_type
        if self.dry_run:
            print("    %s %s" % (method, url))
            print("      x-api-key: %s" % mask(self.api_key))
            for line in describe or []:
                print("      " + line)
            return None
        delay = 2.0
        unknown = "the upload was sent, so the asset may exist now"
        for attempt in range(1, MAX_ATTEMPTS + 1):
            (self.writes if write else self.reads).wait()
            req = urllib.request.Request(url, data=body, method=method, headers=headers)
            wait = delay
            try:
                with self.opener.open(req, timeout=120) as resp:
                    raw = resp.read()
                try:
                    return json.loads(raw.decode("utf-8")) if raw else {}
                except ValueError:
                    if not idempotent:
                        raise CreateUnknown("unreadable answer to %s %s (%s)" % (method, path, unknown))
                    self.log("  unreadable answer on %s %s, retry %d/%d in %.1f s" % (method, path, attempt, MAX_ATTEMPTS, wait))
            except urllib.error.HTTPError as e:
                try:
                    text = e.read().decode("utf-8", "replace")
                except Exception:  # noqa: BLE001 - the error body is only for the message
                    text = ""
                transient = e.code == 429 or 500 <= e.code < 600
                if not transient:
                    raise UploadError("HTTP %d on %s %s: %s" % (e.code, method, path, text[:400]))
                if not idempotent and e.code not in (429, 503):
                    # 500 / 502 / 504 can come from a gateway AFTER the backend accepted the upload
                    raise CreateUnknown("HTTP %d on %s %s (%s)" % (e.code, method, path, unknown))
                ra = e.headers.get("retry-after") if e.headers else None
                try:
                    wait = float(ra) if ra else delay
                except ValueError:
                    wait = delay
                self.log("  HTTP %d on %s %s, retry %d/%d in %.1f s" % (e.code, method, path, attempt, MAX_ATTEMPTS, wait))
            except urllib.error.URLError as e:
                # urllib wraps only the errors of connecting / SENDING the request: Roblox never got a whole request,
                # so a retry cannot duplicate anything (also for the POST create)
                self.log("  network error on %s %s (%s), retry %d/%d in %.1f s" % (method, path, e.reason, attempt, MAX_ATTEMPTS, wait))
            except (http.client.HTTPException, OSError) as e:
                # raised raw by getresponse() / read() AFTER the request went out: RemoteDisconnected,
                # ConnectionResetError, socket.timeout / TimeoutError, IncompleteRead ...
                if not idempotent:
                    raise CreateUnknown("%s on %s %s (%s)" % (type(e).__name__, method, path, unknown))
                self.log("  connection error on %s %s (%s), retry %d/%d in %.1f s" % (method, path, type(e).__name__, attempt, MAX_ATTEMPTS, wait))
            time.sleep(min(wait, 120.0))
            delay = min(delay * 2, 60.0)
        raise UploadError("gave up on %s %s after %d attempts" % (method, path, MAX_ATTEMPTS))


# ------------------------------------------------------------------------------------------------ inputs
def load_index(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    assets = None
    if isinstance(data, dict):
        for name in ("keys", "assets"):  # the kit writes { "comment": ..., "keys": { key: {...} } }
            if isinstance(data.get(name), dict):
                assets = data[name]
                break
        if assets is None:
            assets = {k: v for k, v in data.items() if isinstance(v, dict)}
    if not isinstance(assets, dict):
        raise Refusal("%s: expected { \"keys\": { key: {...} } }" % path)
    out = {}
    for key, entry in assets.items():
        if not KEY_RE.match(key) or not isinstance(entry, dict):
            raise Refusal("%s: bad entry %r (keys are plain identifiers, entries are objects)" % (path, key))
        out[key] = entry
    return out


def fbx_path(root, key, entry):
    cands = []
    if entry.get("fbx"):
        cands.append(os.path.join(root, entry["fbx"]))
        cands.append(os.path.join(root, "blender", "out", os.path.basename(entry["fbx"])))
    cands.append(os.path.join(root, "blender", "out", key + ".fbx"))
    for c in cands:
        if os.path.isfile(c):
            return c
    return cands[0]


def catalog_keys(root, name):
    """--class NAME -> the upload keys of blender/catalog/<NAME>.json (or the catalog whose "class" is NAME), in catalog
    order; entries with "upload": false (kit test keys) are left out, like blender/build_all.py does"""
    import glob
    cat_dir = os.path.join(root, "blender", "catalog")
    cats = {}
    for path in sorted(glob.glob(os.path.join(cat_dir, "*.json"))):
        try:
            with open(path, encoding="utf-8") as f:
                cat = json.load(f)
        except (OSError, ValueError) as e:
            raise Refusal("%s: unreadable catalog (%s)" % (os.path.relpath(path, root), e))
        if not isinstance(cat, dict):
            continue
        base = os.path.splitext(os.path.basename(path))[0]
        cats[base] = cat
        if isinstance(cat.get("class"), str):
            cats.setdefault(cat["class"], cat)
    if name not in cats:
        names = sorted(set(c["class"] if isinstance(c.get("class"), str) else b for b, c in cats.items()))
        raise Refusal("--class %s: no blender/catalog/%s.json (classes: %s)" % (name, name, ", ".join(names) or "none"))
    keys = []
    for e in cats[name].get("keys") or []:
        if isinstance(e, dict) and isinstance(e.get("key"), str) and e.get("upload", True) is not False and e["key"] not in keys:
            keys.append(e["key"])
    if not keys:
        raise Refusal("--class %s: the catalog has no upload keys" % name)
    return keys


def creator_block(creator_type, creator_id):
    return {("groupId" if creator_type == "group" else "userId"): str(creator_id)}


# ------------------------------------------------------------------------------------------------ the work
def plan(key, entry, record):
    """-> (action, reason): action in create | update | new-asset | skip | resume | unknown"""
    if record.get("pendingOperation"):
        return "resume", "operation %s still pending" % record["pendingOperation"]
    if record.get("pendingCreate"):
        return "unknown", "a create of %s may have reached Roblox (%s)" % (key, record["pendingCreate"].get("why") or "interrupted")
    content = entry.get("contentHash")
    struct = entry.get("structureHash")
    if not record.get("assetId"):
        return "create", "no asset yet"
    if record.get("contentHash") == content and content:
        return "skip", "unchanged (contentHash %s)" % str(content)[:12]
    if CLASS["file"] == "png":
        # Open Cloud updates the content of Models only: a changed image (same size or not) is always a new asset
        what = "same size" if struct and record.get("structureHash") == struct else "size / format changed"
        return "new-asset", "image changed (%s): images cannot be updated in place -> a NEW asset, the id changes" % what
    if struct and record.get("structureHash") == struct:
        return "update", "content changed, same structure -> new version of %s" % record["assetId"]
    return "new-asset", "structure changed (%s -> %s): a NEW asset, the id changes" % (str(record.get("structureHash"))[:12], str(struct)[:12])


# the asset classes: meshes (the default) and the Image class (--textures)
# FBX export needs bpy: the Blender python of blender/README.md, never plain python3 (no bpy) or --no-export (no FBX)
BLENDER_PY = "/tmp/claude-0/bpyenv/bin/python"
BUILD_MESH = BLENDER_PY + " blender/build_all.py --key %s  (the Blender python of blender/README.md; not --no-export: it writes no FBX)"
BUILD_ALL = BLENDER_PY + " blender/build_all.py --all  (the Blender python of blender/README.md; not --no-export: it writes no FBX)"
CLASSES = {
    "mesh": {"index": ("blender", "meshes.json"), "state": ("blender", "upload_state.json"), "lua": ("src", "shared", "MeshIds.lua"),
             "assetType": "Model", "ext": ".fbx", "mime": "model/fbx", "file": "fbx", "build": BUILD_MESH},
    "image": {"index": ("blender", "textures", "textures.json"), "state": ("blender", "textures", "upload_state.json"),
              "lua": ("src", "shared", "TextureIds.lua"), "assetType": "Decal", "ext": ".png", "mime": "image/png", "file": "png",
              "build": "python3 blender/textures/build_vortex.py  (%s)"},
}
CLASS = CLASSES["mesh"]


def png_path(root, key, entry):
    if entry.get("png"):
        p = os.path.join(root, entry["png"])
        if os.path.isfile(p):
            return p
        alt = os.path.join(root, "blender", entry["png"])
        if os.path.isfile(alt):
            return alt
        return p
    return os.path.join(root, "blender", "textures", "vortex", key + ".png")


def check_entry(root, key, entry):
    if CLASS["file"] == "png":
        path = png_path(root, key, entry)
        if not os.path.isfile(path):
            raise UploadError("missing %s (build it: %s)" % (os.path.relpath(path, root), CLASS["build"] % key))
        size = os.path.getsize(path)
        if size > MAX_FILE_BYTES:
            raise UploadError("%s is %.1f MB; the API takes up to 20 MB" % (path, size / 1048576.0))
        if not entry.get("contentHash"):
            raise UploadError("%s: textures.json has no contentHash (rebuild with build_vortex.py)" % key)
        return path, size
    path = fbx_path(root, key, entry)
    if not os.path.isfile(path):
        raise UploadError("missing %s (build it: %s)" % (os.path.relpath(path, root), CLASS["build"] % key))
    if not path.lower().endswith(".fbx"):
        raise UploadError("%s: only .fbx (content updates are FBX-only)" % path)
    size = os.path.getsize(path)
    if size > MAX_FILE_BYTES:
        raise UploadError("%s is %.1f MB; the API takes up to 20 MB" % (path, size / 1048576.0))
    tris = entry.get("maxTrianglesPerMesh")
    if tris is not None and int(tris) > MAX_TRIANGLES_PER_MESH:
        raise UploadError("a mesh of %s has %s triangles (limit %d per mesh)" % (key, tris, MAX_TRIANGLES_PER_MESH))
    if not entry.get("contentHash") or not entry.get("structureHash"):
        raise UploadError("%s: meshes.json has no contentHash / structureHash (rebuild with the kit)" % key)
    check_fbx_fresh(root, key, entry, path)
    return path, size


def check_fbx_fresh(root, key, entry, path):
    """the FBX on disk must be the one the kit exported for this contentHash (review3 tooling-0): a --no-export build
    rewrites meshes.json + the manifests but leaves an older FBX behind, which must never go up under the new hashes"""
    stale = "%s: %s was not exported from this contentHash (%s); rebuild it: %s"
    rel = os.path.relpath(path, root)
    if "fbxSha256" in entry:  # written by every build_all run since review3: the sha of the verified FBX, null = none
        want = entry.get("fbxSha256")
        if not want:
            raise UploadError(stale % (key, rel, "the last build was --no-export", CLASS["build"] % key))
        if sha256_file(path) != want:
            raise UploadError(stale % (key, rel, "its sha256 is not meshes.json fbxSha256", CLASS["build"] % key))
        return
    man_path = os.path.join(os.path.dirname(path), key + ".manifest.json")
    try:
        with open(man_path, encoding="utf-8") as f:
            man = json.load(f)
    except (OSError, ValueError):
        raise UploadError(stale % (key, rel, "no readable blender/out/%s.manifest.json" % key, CLASS["build"] % key))
    verify = man.get("verify") if isinstance(man, dict) else None
    if not isinstance(verify, dict) or not verify.get("ok"):
        raise UploadError(stale % (key, rel, "its manifest has no FBX verify: a --no-export build", CLASS["build"] % key))
    if man.get("contentHash") != entry.get("contentHash"):
        raise UploadError(stale % (key, rel, "its manifest has another contentHash", CLASS["build"] % key))
    if verify.get("sha256") and verify["sha256"] != sha256_file(path):
        raise UploadError(stale % (key, rel, "its sha256 is not the verified one", CLASS["build"] % key))


def request_json(key, entry, creator, asset_id):
    req = {"assetType": CLASS["assetType"], "creationContext": {"creator": creator}}
    if asset_id is None:
        req["displayName"] = safe_name(entry.get("displayName") or "NC " + key)
        req["description"] = (entry.get("description") or "Nimbus Climb model " + key)[:MAX_DESCRIPTION]
    else:
        req["assetId"] = str(asset_id)
    return req


def upload_one(client, key, entry, record, creator, root, args, log):
    action, reason = plan(key, entry, record)
    log("  %s: %s" % (action, reason))
    if action == "resume":
        if args.dry_run:
            log("    (dry run: the real run polls operation %s first)" % record["pendingOperation"])
            return record
        return finish(client, key, record, args, log)
    if action == "unknown":
        raise UploadError(unknown_hint(key, record["pendingCreate"]))
    if action == "skip" and not args.force:
        return record
    if action == "skip" and CLASS["file"] == "png":
        raise UploadError("--force on the uploaded image %s refused: images are never updated in place, so it would only "
                          "make a duplicate asset (change the PNG to upload a new one)" % key)
    path, size = check_entry(root, key, entry)
    asset_id = record.get("assetId") if action in ("update", "skip") else None
    req = request_json(key, entry, creator, asset_id)
    with open(path, "rb") as f:
        data = f.read()
    body, ctype = encode_multipart([("request", json.dumps(req))], [("fileContent", os.path.basename(path), CLASS["mime"], data)])
    if asset_id:
        method, api_path = "PATCH", UPDATE_PATH.format(assetId=asset_id)
    else:
        method, api_path = "POST", CREATE_PATH
    describe = [
        "Content-Type: multipart/form-data (%d bytes)" % len(body),
        "part 'request': %s" % json.dumps(req),
        "part 'fileContent': %s; %s; %d bytes; sha256 %s" % (os.path.relpath(path, root), CLASS["mime"], size, sha256_file(path)[:16]),
        "then GET %s until done -> assetId / revisionId / moderationResult" % OPERATION_PATH,
    ]
    file_sha = sha256_file(path)
    if method == "POST" and not args.dry_run:
        # written BEFORE the POST (review3 tooling-2/3): if the outcome is unknown (gateway 5xx, dropped connection,
        # crash, Ctrl-C) the next run refuses this key until the owner checked Creator Hub (--adopt / --not-created)
        record["pendingCreate"] = {"displayName": req["displayName"], "contentHash": entry.get("contentHash"),
                                   "structureHash": entry.get("structureHash"), "fileSha256": file_sha,
                                   "startedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "why": "interrupted"}
        args.save()
    try:
        op = client.request(method, api_path, body=body, content_type=ctype, write=True, describe=describe,
                            idempotent=(method != "POST"))
    except CreateUnknown as e:
        record["pendingCreate"]["why"] = str(e)
        raise UploadError(unknown_hint(key, record["pendingCreate"]))
    except UploadError:
        record.pop("pendingCreate", None)  # refused / never sent: nothing was created
        raise
    if args.dry_run:
        return record
    op_path = (op or {}).get("path") or ""
    if not op_path.startswith("operations/"):
        if method == "POST":
            record["pendingCreate"]["why"] = "answer without an operation path"
            raise UploadError(unknown_hint(key, record["pendingCreate"]) + " | answer: %s" % json.dumps(op)[:200])
        raise UploadError("unexpected response (no operation path): %s" % json.dumps(op)[:300])
    record.pop("pendingCreate", None)
    record["pendingOperation"] = op_path.split("/", 1)[1]
    record["pendingMode"] = "update" if asset_id else "create"
    record["pendingContentHash"] = entry.get("contentHash")
    record["pendingStructureHash"] = entry.get("structureHash")
    record["pendingFileSha256"] = file_sha
    if record.get("assetId") and not asset_id:
        record["pendingReplaces"] = record["assetId"]
    args.save()  # an interrupted poll is resumed, never re-uploaded
    return finish(client, key, record, args, log)


def unknown_hint(key, pc):
    return ("the create of %s may have reached Roblox (%s, started %s). Do NOT upload it again blindly: look in Creator "
            "Hub > Creations for a model/decal named \"%s\" made then. Found it: re-run with --adopt %s=<its id>. Not "
            "there: re-run with --not-created %s" % (key, pc.get("why"), pc.get("startedAt"), pc.get("displayName"), key, key))


def adopt(key, record, asset_id, log):
    """--adopt KEY=ID: the unknown create did make asset ID; record it as if its operation had finished"""
    pc = record.pop("pendingCreate")
    old = record.get("assetId")
    if old and int(old) != asset_id:
        record.setdefault("previousAssetIds", []).append(int(old))
        if record.get("decalAssetId"):
            record["previousAssetIds"].append(int(record.pop("decalAssetId")))
    record["assetId"] = asset_id
    record["contentHash"] = pc.get("contentHash")
    record["structureHash"] = pc.get("structureHash")
    record["fileSha256"] = pc.get("fileSha256")
    record["revisionId"] = None
    record["moderationState"] = None
    record["uploadedAt"] = pc.get("startedAt")
    record.pop("lastError", None)
    log("  adopted asset %d for %s (the create of %s)" % (asset_id, key, pc.get("startedAt")))


def set_id(key, record, new_id, log):
    """--set-id KEY=ID (OWNER_UPLOAD.md section 6): an uploaded image's Decal id is swapped for its Image id. Nothing is
    sent: assetId = the Image id (TextureIds.lua follows), the Decal id is kept as decalAssetId. A second --set-id on the
    same key replaces a wrong Image id (that one goes to previousAssetIds) and keeps decalAssetId. A mesh key (only with
    --allow-mesh-set-id) just records the new id; the old one goes to previousAssetIds."""
    old = int(record["assetId"])
    if CLASS["file"] == "png" and not record.get("decalAssetId"):
        record["decalAssetId"] = old
        what = "Decal id %d kept as decalAssetId" % old
    else:
        record.setdefault("previousAssetIds", []).append(old)
        what = "old id %d moved to previousAssetIds" % old
    if CLASS["file"] != "png":
        record["revisionId"] = None
        record["moderationState"] = None
    record["assetId"] = new_id
    record["idSetByHand"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    record.pop("lastError", None)
    log("  set-id: %s = %d (%s)" % (key, new_id, what))


def finish(client, key, record, args, log):
    op_id = record["pendingOperation"]
    deadline = time.monotonic() + args.poll_timeout
    delay = 2.0
    while True:
        op = client.request("GET", OPERATION_PATH.format(operationId=op_id))
        if op.get("done"):
            break
        if time.monotonic() >= deadline:
            log("  operation %s still running after %d s; saved, the next run resumes it" % (op_id, args.poll_timeout))
            return record
        time.sleep(delay)
        delay = min(delay * 1.5, 10.0)
    mode = record.pop("pendingMode", "create")
    content = record.pop("pendingContentHash", None)
    struct = record.pop("pendingStructureHash", None)
    sha = record.pop("pendingFileSha256", None)
    replaces = record.pop("pendingReplaces", None)
    record.pop("pendingOperation", None)
    if op.get("error"):
        err = op["error"]
        raise UploadError("operation %s failed: %s %s" % (op_id, err.get("code"), err.get("message")))
    resp = op.get("response") or {}
    new_id = resp.get("assetId") or (resp.get("path") or "").replace("assets/", "")
    if not str(new_id).isdigit():
        raise UploadError("operation %s done without an asset id: %s" % (op_id, json.dumps(op)[:300]))
    new_id = int(new_id)
    if mode == "update" and record.get("assetId") and int(record["assetId"]) != new_id:
        raise UploadError("a PATCH of %s answered with asset %s - refusing to record it" % (record["assetId"], new_id))
    if replaces:
        record.setdefault("previousAssetIds", []).append(int(replaces))
        if record.get("decalAssetId"):  # an image whose Image id had been swapped in by hand (OWNER_UPLOAD.md 6)
            record["previousAssetIds"].append(int(record.pop("decalAssetId")))
    if CLASS["file"] == "png" and mode == "create":
        log("  NOTE: a new image id: check it is the Image id, not the Decal id (docs/phase6/OWNER_UPLOAD.md section 6)")
    record["assetId"] = new_id
    record["revisionId"] = resp.get("revisionId")
    record["revisionCreateTime"] = resp.get("revisionCreateTime")
    record["moderationState"] = (resp.get("moderationResult") or {}).get("moderationState")
    record["contentHash"] = content
    record["structureHash"] = struct
    record["fileSha256"] = sha
    record["uploadedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    record.pop("lastError", None)
    log("  done: asset %d revision %s moderation %s" % (new_id, record["revisionId"], record["moderationState"]))
    if is_rejected(record["moderationState"]):
        log("  WARNING: %s was REJECTED by moderation; it is left out of MeshIds.lua (the Part build stays)" % key)
    return record


def refresh(client, key, record, log):
    if not record.get("assetId"):
        return record
    # an image whose Image id was set by hand (--set-id): its moderation lives on the uploaded Decal asset
    data = client.request("GET", GET_ASSET_PATH.format(assetId=record.get("decalAssetId") or record["assetId"]))
    if data is None:
        return record
    record["revisionId"] = data.get("revisionId", record.get("revisionId"))
    record["moderationState"] = (data.get("moderationResult") or {}).get("moderationState", record.get("moderationState"))
    log("  asset %s revision %s moderation %s" % (record.get("decalAssetId") or record["assetId"], record["revisionId"], record["moderationState"]))
    return record


def stale_keys(state, assets, root):
    """mesh keys whose uploaded asset no longer matches the committed build, so their id must not ship (bug #12 review,
    check.mjs mesh-ids-stale): another structureHash (the re-upload is a NEW asset) or, for a layout-matched build (its
    manifest has a LayoutSig: the floors), another contentHash - the live Part layout matches the NEW manifest, so the
    OLD mesh would be dressed over it. They come back in MeshIds.lua as soon as they are uploaded in this or a later run."""
    out = set()
    if CLASS["file"] == "png" or not assets:
        return out
    for key, rec in state.get("assets", {}).items():
        entry = assets.get(key) or {}
        if not rec.get("assetId") or not entry:
            continue
        if entry.get("structureHash") and rec.get("structureHash") and entry["structureHash"] != rec["structureHash"]:
            out.add(key)
        elif entry.get("contentHash") and rec.get("contentHash") and entry["contentHash"] != rec["contentHash"]:
            try:
                with open(os.path.join(root, "src", "shared", "MeshManifests", key + ".lua"), encoding="utf-8") as f:
                    if re.search(r"\bLayoutSig\b", f.read()):
                        out.add(key)
            except OSError:
                pass
    return out


def mesh_ids_lua(state, skip=()):
    """src/shared/MeshIds.lua (or TextureIds.lua): one sorted table of [string] = number (check.mjs mesh-ids / texture-ids).
    skip: keys left out (stale_keys: an uploaded asset that no longer matches the committed build)."""
    if CLASS["file"] == "png":
        lines = [
            "-- GENERATED by tools/upload_assets.py --textures (Phase 6) from blender/textures/upload_state.json. Do not edit.",
            "-- Texture key -> Roblox Image asset id (numbers only). Empty = the gates' vortex uses its effects-only fallback.",
            "-- Rejected assets are left out; assets still in review are listed and simply fall back until approved.",
            "return {",
        ]
    else:
        lines = [
            "-- GENERATED by tools/upload_assets.py (Phase 6) from blender/upload_state.json. Do not edit by hand.",
            "-- Mesh key -> Roblox Model asset id (numbers only). Empty = every model uses its Part build (today's game).",
            "-- Rejected assets are left out; assets still in review are listed and simply fall back until approved.",
            "return {",
        ]
    for key in sorted(state.get("assets", {})):
        rec = state["assets"][key]
        aid = rec.get("assetId")
        if isinstance(aid, int) and aid > 0 and not is_rejected(rec.get("moderationState")) and KEY_RE.match(key) and key not in skip:
            lines.append("\t%s = %d," % (key, aid))
    lines.append("}")
    return "\n".join(lines) + "\n"


def parse_args(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--upload", action="store_true", help="really send (default: dry run)")
    ap.add_argument("--dry-run", action="store_true", help="the default; kept for clarity")
    ap.add_argument("--only", action="append", default=[], help="these keys only (repeatable or comma separated)")
    ap.add_argument("--refresh", action="store_true", help="only re-read revision + moderation of known assets")
    ap.add_argument("--force", action="store_true", help="upload even when the contentHash is unchanged")
    ap.add_argument("--textures", action="store_true", help="the Image class: blender/textures/textures.json -> TextureIds.lua")
    ap.add_argument("--adopt", action="append", default=[], metavar="KEY=ASSETID",
                    help="a create whose outcome was unknown DID make this asset (seen in Creator Hub): record its id")
    ap.add_argument("--not-created", action="append", default=[], metavar="KEY",
                    help="a create whose outcome was unknown made NO asset (checked in Creator Hub): create it again")
    ap.add_argument("--class", dest="classes", action="append", default=[], metavar="CATALOG",
                    help="the upload keys of blender/catalog/<CATALOG>.json (repeatable or comma separated; adds to --only)")
    ap.add_argument("--set-id", action="append", default=[], metavar="KEY=ID",
                    help="--textures: record the Image id ID for KEY (its Decal id is kept as decalAssetId) and rewrite "
                         "TextureIds.lua; sends nothing, writes only with --upload")
    ap.add_argument("--allow-mesh-set-id", action="store_true",
                    help="--set-id on a mesh key really is meant (normally refused: a Model id needs no swap)")
    ap.add_argument("--poll-timeout", type=float, default=300)
    ap.add_argument("--root", default=DEFAULT_ROOT, help=argparse.SUPPRESS)
    ap.add_argument("--base-url", default=BASE_URL, help=argparse.SUPPRESS)  # tests: the local fake API
    args = ap.parse_args(argv)
    if args.upload and args.dry_run:
        raise Refusal("--upload and --dry-run together: pick one")
    args.dry_run = not args.upload
    args.only = [k.strip() for item in args.only for k in item.split(",") if k.strip()]
    args.not_created = [k.strip() for item in args.not_created for k in item.split(",") if k.strip()]
    adopt_ids = {}
    for item in args.adopt:
        key, _, aid = item.partition("=")
        if not KEY_RE.match(key.strip()) or not aid.strip().isdigit() or int(aid) <= 0:
            raise Refusal("--adopt takes KEY=ASSETID (the number from Creator Hub), not %r" % item)
        adopt_ids[key.strip()] = int(aid)
    args.adopt = adopt_ids
    if set(args.adopt) & set(args.not_created):
        raise Refusal("--adopt and --not-created name the same key: pick one")
    args.classes = [k.strip() for item in args.classes for k in item.split(",") if k.strip()]
    for name in args.classes:
        if not KEY_RE.match(name):
            raise Refusal("--class takes a catalog name such as pets (blender/catalog/pets.json), not %r" % name)
    set_ids = {}
    for item in [k.strip() for item in args.set_id for k in item.split(",") if k.strip()]:
        key, _, aid = item.partition("=")
        key, aid = key.strip(), aid.strip()
        if not KEY_RE.match(key) or not aid.isdigit() or int(aid) <= 0:
            raise Refusal("--set-id takes KEY=ID (ID = the number of the Image, digits only), not %r" % item)
        if key in set_ids and set_ids[key] != int(aid):
            raise Refusal("--set-id names %s twice with different ids" % key)
        set_ids[key] = int(aid)
    args.set_id = set_ids
    if args.set_id and (args.refresh or args.force or args.adopt or args.not_created or args.classes):
        raise Refusal("--set-id only records ids (nothing is sent): run it on its own, without --refresh / --force / "
                      "--adopt / --not-created / --class")
    if args.allow_mesh_set_id and not args.set_id:
        raise Refusal("--allow-mesh-set-id goes with --set-id")
    return args


def set_ids_run(args, assets, state, keys, creator, state_path, lua_path, root):
    """--set-id: validate every pair first, then record them all (no network); a dry run writes nothing"""
    if CLASS["file"] != "png" and not args.allow_mesh_set_id:
        raise Refusal("--set-id is for the textures' Decal -> Image id swap (--textures --set-id KEY=ID). A mesh is a Model "
                      "and needs no swap; a create of unknown outcome is settled with --adopt KEY=ID. If you really "
                      "mean to change a mesh key's id by hand, add --allow-mesh-set-id")
    for key in sorted(args.set_id):
        new_id = args.set_id[key]
        rec = state["assets"].get(key) or {}
        if key not in assets:
            raise Refusal("--set-id %s: not in %s" % (key, "/".join(CLASS["index"])))
        if key not in keys:
            raise Refusal("--set-id %s: not in this run's keys (add it to --only)" % key)
        if rec.get("pendingCreate") or rec.get("pendingOperation"):
            raise Refusal("--set-id %s: its upload is not finished (settle it first: a plain run / --adopt / --not-created)" % key)
        if not isinstance(rec.get("assetId"), int):
            raise Refusal("--set-id %s: no uploaded asset recorded yet (upload it first; --set-id only swaps the id of "
                          "an uploaded asset)" % key)
        if rec["assetId"] == new_id:
            raise Refusal("--set-id %s=%d: that is already its id (nothing to change)" % (key, new_id))
        if CLASS["file"] == "png" and rec.get("decalAssetId") == new_id:
            raise Refusal("--set-id %s=%d: that is its Decal id; give the Image id (OWNER_UPLOAD.md section 6)" % (key, new_id))

    print("%s --set-id for %d key(s) (nothing is sent)" % ("DRY RUN (nothing is written; add --upload to write):" if args.dry_run
                                                           else "SET-ID:", len(args.set_id)))
    for key in sorted(args.set_id):
        print("- " + key)
        set_id(key, state["assets"][key], args.set_id[key], lambda m: print(m, flush=True))
    if args.dry_run:
        print("dry run: nothing was sent and nothing was written")
    else:
        state["version"] = STATE_VERSION
        state["creator"] = creator
        atomic_write_json(state_path, state)
        atomic_write(lua_path, mesh_ids_lua(state, stale_keys(state, assets, root)))
        print("wrote %s and %s" % (os.path.relpath(state_path, root), os.path.relpath(lua_path, root)))
    print("ok")
    return 0


def main(argv=None):
    global CLASS
    args = parse_args(argv)
    CLASS = CLASSES["image" if args.textures else "mesh"]
    root = os.path.abspath(args.root)
    index_path = os.path.join(root, *CLASS["index"])
    state_path = os.path.join(root, *CLASS["state"])
    lua_path = os.path.join(root, *CLASS["lua"])
    if not os.path.isfile(index_path):
        if args.textures:
            raise Refusal("no %s yet (build the textures first: python3 blender/textures/build_vortex.py)" % os.path.relpath(index_path, root))
        raise Refusal("no %s yet (build the meshes first: %s)" % (os.path.relpath(index_path, root), BUILD_ALL))
    assets = load_index(index_path)
    try:
        with open(state_path, encoding="utf-8") as f:
            state = json.load(f)
    except FileNotFoundError:
        state = {"version": STATE_VERSION, "assets": {}}
    state.setdefault("assets", {})

    api_key = os.environ.get("ROBLOX_API_KEY", "")
    creator_id = os.environ.get("ROBLOX_CREATOR_ID", "").strip()
    creator_type = (os.environ.get("ROBLOX_CREATOR_TYPE") or "user").strip().lower()
    if creator_type not in ("user", "group"):
        raise Refusal("ROBLOX_CREATOR_TYPE must be 'user' or 'group'")
    if creator_id and not creator_id.isdigit():
        raise Refusal("ROBLOX_CREATOR_ID must be a number (the experience owner's user or group id)")
    if not args.dry_run and (not api_key or not creator_id):
        raise Refusal("--upload needs ROBLOX_API_KEY and ROBLOX_CREATOR_ID in the environment (a new session loads them)")
    creator = {"type": creator_type, "id": creator_id or "<ROBLOX_CREATOR_ID>"}
    stored = state.get("creator")
    if stored and creator_id and stored != creator:
        raise Refusal("upload_state.json belongs to %s %s, not %s %s: another owner cannot update these assets and the "
                      "game could not load them. Refusing." % (stored.get("type"), stored.get("id"), creator_type, creator_id))
    if args.classes and args.textures:
        raise Refusal("--class names a mesh catalog (blender/catalog/); the textures have none: use --only")
    for name in args.classes:
        args.only += [k for k in catalog_keys(root, name) if k not in args.only]
    unknown = [k for k in args.only if k not in assets]
    if unknown:
        hint = ""
        if args.classes:
            hint = " (build the class first: %s blender/build_all.py --class %s)" % (BLENDER_PY, " / --class ".join(args.classes))
        shown = ", ".join(unknown[:8]) + (" ... (%d more)" % (len(unknown) - 8) if len(unknown) > 8 else "")
        raise Refusal("not in %s: " % "/".join(CLASS["index"]) + shown + hint)
    keys = [k for k in sorted(assets) if not args.only or k in args.only]
    if args.set_id:
        return set_ids_run(args, assets, state, keys, creator, state_path, lua_path, root)
    for key in list(args.adopt) + args.not_created:
        if key not in assets or not (state["assets"].get(key) or {}).get("pendingCreate"):
            raise Refusal("%s has no create of unknown outcome to settle (--adopt / --not-created are only for a key the "
                          "tool marked 'pendingCreate')" % key)
        if key not in keys:
            raise Refusal("%s is not in this run's keys (add it to --only)" % key)

    def log(msg):
        print(msg, flush=True)

    def save():
        if args.dry_run:
            return
        state["version"] = STATE_VERSION
        state["creator"] = creator
        atomic_write_json(state_path, state)
        atomic_write(lua_path, mesh_ids_lua(state, stale_keys(state, assets, root)))

    args.save = save
    client = Client(args.base_url, api_key or "<ROBLOX_API_KEY>", args.dry_run, log)
    print("%s %d key(s) for %s %s%s" % ("DRY RUN (nothing is sent, nothing is written; add --upload to send):" if args.dry_run else "UPLOAD:",
                                        len(keys), creator_type, creator["id"], " - refresh only" if args.refresh else ""))
    failures = 0
    for key in keys:
        print("- " + key)
        record = state["assets"].setdefault(key, {})
        try:
            if key in args.not_created:
                log("  --not-created: forgetting the unknown create of %s (%s)" % (key, record.pop("pendingCreate").get("startedAt")))
            elif key in args.adopt:
                adopt(key, record, args.adopt[key], log)
                refresh(client, key, record, log)
            if args.refresh:
                refresh(client, key, record, log)
            else:
                upload_one(client, key, assets[key], record, creator_block(creator_type, creator["id"]), root, args, log)
        except UploadError as e:
            failures += 1
            record["lastError"] = str(e)
            log("  FAILED: %s" % e)
        except Exception as e:  # noqa: BLE001 - one key's surprise must not abort the batch (review3 tooling-2)
            failures += 1
            record["lastError"] = "%s: %s" % (type(e).__name__, e)
            log("  FAILED (unexpected %s): %s" % (type(e).__name__, e))
        finally:
            if not record:
                state["assets"].pop(key, None)
            save()  # after every asset: an interrupted run loses nothing
    if args.dry_run:
        print("dry run: nothing was sent and nothing was written")
    else:
        print("wrote %s and %s" % (os.path.relpath(state_path, root), os.path.relpath(lua_path, root)))
    print("%d failed" % failures if failures else "ok")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Refusal as r:
        print("refused: %s" % r, file=sys.stderr)
        sys.exit(2)
