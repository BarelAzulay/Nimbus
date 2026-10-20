#!/usr/bin/env python3
"""Offline tests of tools/upload_assets.py against a LOCAL fake of the Open Cloud Assets API (127.0.0.1 only).

Nothing here talks to Roblox: the fake mirrors the documented request / response shapes (POST /assets/v1/assets,
PATCH /assets/v1/assets/{id}, GET /assets/v1/operations/{id}, GET /assets/v1/assets/{id}) and checks every request
(x-api-key, multipart parts, assetType Model + model/fbx or Decal + image/png, the creator block; a PATCH of a Decal is
refused like Open Cloud does). It can also drop connections or answer 504 after creating, to test the no-duplicate
rules (review3 tooling-0..3). Exit code 0 = all passed.

    python3 tools/test_upload_assets.py
"""
import contextlib
import hashlib
import http.client
import io
import json
import socket
import os
import re
import shutil
import sys
import tempfile
import threading
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import upload_assets as U  # noqa: E402

KEY = "test-key-not-real-0123456789"
STATE = {}


def reset_fake():
    STATE.clear()
    STATE.update({"next_id": 9000000001, "ops": {}, "assets": {}, "log": [], "fail_next": [], "never_done": False,
                  "reject": set(), "bad": [], "post_mode": [], "drop_reads": 0, "drop_patch": 0})


def drop(handler):
    """close the connection without an answer (a proxy / load balancer reset): the client sees RemoteDisconnected"""
    handler.close_connection = True
    try:
        handler.connection.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass


def parse_multipart(body, ctype):
    boundary = ctype.split("boundary=", 1)[1].encode()
    parts = {}
    for chunk in body.split(b"--" + boundary):
        chunk = chunk.strip(b"\r\n")
        if not chunk or chunk == b"--":
            continue
        head, _, data = chunk.partition(b"\r\n\r\n")
        head = head.decode()
        name = head.split('name="', 1)[1].split('"', 1)[0]
        ct = None
        for line in head.split("\r\n"):
            if line.lower().startswith("content-type:"):
                ct = line.split(":", 1)[1].strip()
        parts[name] = (data, ct, head)
    return parts


class Fake(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, obj, headers=None):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def gate(self):
        if self.headers.get("x-api-key") != KEY:
            self.body()
            self.reply(401, {"code": "UNAUTHENTICATED"})
            return False
        if STATE["fail_next"]:
            code = STATE["fail_next"].pop(0)
            self.body()
            STATE["log"].append((str(code), self.path))
            return self.reply(code, {"code": "X"}, {"retry-after": "0.01"} if code == 429 else None) and False
        return True

    def upload(self, asset_id):
        parts = parse_multipart(self.body(), self.headers["Content-Type"])
        req = json.loads(parts["request"][0].decode())
        data, ct, head = parts["fileContent"]
        problems = []
        if (req.get("assetType"), ct) not in (("Model", "model/fbx"), ("Decal", "image/png")) or 'filename="' not in head:
            problems.append("fileContent part / assetType")
        if asset_id is not None and STATE["assets"][asset_id].get("type") == "Decal":
            STATE["log"].append(("PATCH-refused", self.path))
            return self.reply(400, {"code": "INVALID_ARGUMENT", "message": "content updates are Model-only"})
        mode = STATE["post_mode"].pop(0) if asset_id is None and STATE["post_mode"] else None
        if mode == "drop":  # read the upload, then reset: nothing created
            STATE["log"].append(("POST-dropped", self.path))
            return drop(self)
        creator = req.get("creationContext", {}).get("creator", {})
        if not (creator.get("userId") or creator.get("groupId")):
            problems.append("creator")
        if asset_id is None:
            if not req.get("displayName") or not req.get("description") or "assetId" in req:
                problems.append("create fields")
            asset_id = STATE["next_id"]
            STATE["next_id"] += 1
            STATE["assets"][asset_id] = {"rev": 0, "creator": creator, "name": req.get("displayName"), "type": req.get("assetType")}
        elif str(req.get("assetId")) != str(asset_id):
            problems.append("update assetId")
        STATE["bad"] += problems
        STATE["assets"][asset_id]["rev"] += 1
        rev = STATE["assets"][asset_id]["rev"]
        op = "op-%d-%d" % (asset_id, rev)
        STATE["ops"][op] = {"asset": asset_id, "polls": 0, "rev": rev}
        STATE["log"].append((self.command, self.path, len(data), json.dumps(creator)))
        if mode == "create_drop":  # the backend made the asset, then the connection died before the answer
            return drop(self)
        if mode == "create_504":  # the backend made the asset, then the gateway timed out
            return self.reply(504, {"code": "GATEWAY_TIMEOUT"})
        if asset_id is not None and STATE["drop_patch"]:
            STATE["drop_patch"] -= 1
            return drop(self)
        self.reply(200, {"path": "operations/" + op, "done": False})

    def do_POST(self):
        if self.gate():
            if self.path == "/assets/v1/assets":
                return self.upload(None)
            self.reply(404, {})

    def do_PATCH(self):
        if self.gate():
            asset_id = int(self.path.rsplit("/", 1)[1])
            if asset_id not in STATE["assets"]:
                self.body()
                return self.reply(404, {"code": "NOT_FOUND"})
            return self.upload(asset_id)

    def do_GET(self):
        if not self.gate():
            return
        STATE["log"].append(("GET", self.path))
        if STATE["drop_reads"]:
            STATE["drop_reads"] -= 1
            return drop(self)
        if self.path.startswith("/assets/v1/operations/"):
            op = STATE["ops"][self.path.rsplit("/", 1)[1]]
            op["polls"] += 1
            if op["polls"] < 2 or STATE["never_done"]:
                return self.reply(200, {"path": "operations/x", "done": False})
            a = op["asset"]
            mod = "MODERATION_STATE_REJECTED" if a in STATE["reject"] else ("MODERATION_STATE_REVIEWING" if op["rev"] == 1 else "MODERATION_STATE_APPROVED")
            return self.reply(200, {"path": "operations/x", "done": True, "response": {
                "path": "assets/%d" % a, "assetId": str(a), "revisionId": str(op["rev"]), "revisionCreateTime": "2026-10-20T00:00:00Z",
                "assetType": "ASSET_TYPE_MODEL", "moderationResult": {"moderationState": mod}}})
        if self.path.startswith("/assets/v1/assets/"):
            a = int(self.path.rsplit("/", 1)[1])
            mod = "MODERATION_STATE_REJECTED" if a in STATE["reject"] else "MODERATION_STATE_APPROVED"
            return self.reply(200, {"assetId": str(a), "revisionId": str(STATE["assets"][a]["rev"]), "moderationResult": {"moderationState": mod}})
        self.reply(404, {})


def make_repo(tmp):
    root = os.path.join(tmp, "repo")
    os.makedirs(os.path.join(root, "blender", "out"))
    os.makedirs(os.path.join(root, "src", "shared"))
    index = {"assets": {}}
    for key, struct in (("cal_axes", "s-cal-1"), ("pet_dog", "s-dog-1"), ("wing_feather", "s-wing-1")):
        with open(os.path.join(root, "blender", "out", key + ".fbx"), "wb") as f:
            f.write(b"Kaydara FBX Binary  \0" + key.encode() * 50)
        index["assets"][key] = {"fbx": "blender/out/%s.fbx" % key, "displayName": "NC " + key.replace("_", " ").title(),
                                "description": "Nimbus Climb " + key, "maxTrianglesPerMesh": 4000,
                                "contentHash": "c-" + key + "-1", "structureHash": struct,
                                "fbxSha256": sha_of(os.path.join(root, "blender", "out", key + ".fbx"))}
    write_index(root, index)
    return root, index


def sha_of(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def rebuild(root, index, key, extra=b"", **fields):
    """what an export build does: a new FBX + new hashes + its fbxSha256 in meshes.json"""
    path = os.path.join(root, "blender", "out", key + ".fbx")
    with open(path, "ab") as f:
        f.write(extra)
    index["assets"][key].update(fields)
    index["assets"][key]["fbxSha256"] = sha_of(path)
    write_index(root, index)


def write_index(root, index):
    """the kit's format: { "comment": ..., "keys": { key: {...} } } (make_repo's first write uses "assets")"""
    data = index if not os.path.exists(os.path.join(root, "blender", "meshes.json")) else {"comment": "kit index", "keys": index["assets"]}
    with open(os.path.join(root, "blender", "meshes.json"), "w") as f:
        json.dump(data, f, indent=1)


def run(root, base, *extra):
    """main() with stdout captured; returns (exit code, output)."""
    buf = io.StringIO()
    code = None
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        try:
            code = U.main(["--root", root, "--base-url", base, "--poll-timeout", "5"] + list(extra))
        except SystemExit as e:
            code = e.code if not isinstance(e, U.Refusal) else 2
            buf.write("refused: %s\n" % e)
    return code, buf.getvalue()


def main():
    import time
    real_sleep = time.sleep
    time.sleep = lambda s: real_sleep(min(s, 0.005))
    real_wait = U.Throttle.wait
    U.Throttle.wait = lambda self: None  # the throttle has its own unit test below
    reset_fake()
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % srv.server_address[1]
    tmp = tempfile.mkdtemp(prefix="upl_")
    root, index = make_repo(tmp)
    state_path = os.path.join(root, "blender", "upload_state.json")
    lua_path = os.path.join(root, "src", "shared", "MeshIds.lua")
    results = []

    def check(name, cond, detail=""):
        results.append(bool(cond))
        print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + str(detail)[:600]))

    def state():
        with open(state_path) as f:
            return json.load(f)

    def writes():
        return [x for x in STATE["log"] if x[0] in ("POST", "PATCH")]

    for k in ("ROBLOX_API_KEY", "ROBLOX_CREATOR_ID", "ROBLOX_CREATOR_TYPE"):
        os.environ.pop(k, None)

    # 1) dry run is the default: no env needed, nothing sent, nothing written
    code, out = run(root, base)
    check("dry run by default: exit 0, says DRY RUN", code == 0 and "DRY RUN" in out, out)
    check("dry run sends nothing and writes nothing", not STATE["log"] and not os.path.exists(state_path) and not os.path.exists(lua_path), STATE["log"])
    check("dry run shows the create requests", out.count("POST %s/assets/v1/assets" % base) == 3 and "model/fbx" in out, out)
    os.environ["ROBLOX_API_KEY"] = KEY
    os.environ["ROBLOX_CREATOR_ID"] = "123456"
    code, out = run(root, base, "--only", "pet_dog")
    check("dry run with the key set: still nothing sent, the key never printed", code == 0 and not STATE["log"] and KEY not in out and "<hidden" in out, out)

    # 2) refusals
    os.environ.pop("ROBLOX_API_KEY")
    code, out = run(root, base, "--upload")
    check("--upload without ROBLOX_API_KEY is refused (exit 2)", code == 2 and "ROBLOX_API_KEY" in out and not STATE["log"], out)
    os.environ["ROBLOX_API_KEY"] = KEY
    code, out = run(root, base, "--upload", "--only", "nope")
    check("--only with an unknown key is refused", code == 2 and "nope" in out and not STATE["log"], out)
    code, out = run(root, base, "--upload", "--dry-run")
    check("--upload together with --dry-run is refused", code == 2, out)
    os.environ["ROBLOX_CREATOR_TYPE"] = "team"
    code, out = run(root, base, "--upload")
    check("a bad ROBLOX_CREATOR_TYPE is refused", code == 2 and "user" in out, out)
    os.environ.pop("ROBLOX_CREATOR_TYPE")

    write_index(root, index)  # from here on the kit's { "comment", "keys" } format
    code, out = run(root, base)
    check("the kit's meshes.json format ({ comment, keys }) is read", code == 0 and out.count("POST") == 3, out)

    # 3) first real run (fake API): one 429, then three creates, polled to done
    STATE["fail_next"] = [429]
    code, out = run(root, base, "--upload")
    st = state()
    ids = {k: r.get("assetId") for k, r in st["assets"].items()}
    check("first upload: exit 0, three POSTs, the 429 retried", code == 0 and len([x for x in writes() if x[0] == "POST"]) == 3 and any(x[0] == "429" for x in STATE["log"]), out)
    check("the fake saw well-formed requests (multipart, Model, model/fbx, userId creator)", not STATE["bad"] and all('"userId": "123456"' in x[3] for x in writes()), STATE["bad"])
    check("ids, revisions, hashes and moderation recorded", all(isinstance(v, int) for v in ids.values()) and st["assets"]["pet_dog"]["moderationState"] == "MODERATION_STATE_REVIEWING"
          and st["assets"]["pet_dog"]["contentHash"] == "c-pet_dog-1" and st["assets"]["pet_dog"]["structureHash"] == "s-dog-1", json.dumps(st)[:400])
    check("the creator is recorded", st.get("creator") == {"type": "user", "id": "123456"}, st.get("creator"))
    lua = open(lua_path).read()
    entries = re.findall(r"^\t(\w+) = (\d+),$", lua, re.M)
    body = re.sub(r"--[^\n]*", "", lua).strip()
    check("MeshIds.lua: sorted [string] = number entries only (Reviewing ids included)", [e[0] for e in entries] == sorted(ids) and all(int(e[1]) == ids[e[0]] for e in entries)
          and re.fullmatch(r"return \{\n(\t\w+ = \d+,\n)*\}", body) is not None and "rbxassetid" not in lua, lua)
    check("the key never appears in the state or the Lua file", KEY not in json.dumps(st) and KEY not in lua and KEY not in out)

    # 4) unchanged contentHash: nothing sent, even when the FBX bytes changed
    with open(os.path.join(root, "blender", "out", "pet_dog.fbx"), "ab") as f:
        f.write(b"\0timestamp")
    n = len(STATE["log"])
    code, out = run(root, base, "--upload")
    check("unchanged contentHash: nothing sent (FBX bytes are not the fingerprint)", code == 0 and len(STATE["log"]) == n, STATE["log"][n:])

    # 5) content changed, same structure -> PATCH, same id, revision 2
    rebuild(root, index, "pet_dog", contentHash="c-pet_dog-2")
    STATE["fail_next"] = [503]
    code, out = run(root, base, "--upload", "--only", "pet_dog")
    st = state()
    patches = [x for x in writes() if x[0] == "PATCH"]
    check("content change with the same structureHash -> PATCH of the same id (a 503 retried)", code == 0 and len(patches) == 1 and str(ids["pet_dog"]) in patches[0][1], out)
    check("id stable, revision 2, new contentHash", st["assets"]["pet_dog"]["assetId"] == ids["pet_dog"] and st["assets"]["pet_dog"]["revisionId"] == "2"
          and st["assets"]["pet_dog"]["contentHash"] == "c-pet_dog-2", st["assets"]["pet_dog"])

    # 6) structure changed -> a NEW asset (POST), the old id kept in previousAssetIds
    index["assets"]["wing_feather"].update({"contentHash": "c-wing-2", "structureHash": "s-wing-2"})
    write_index(root, index)
    n_post = len([x for x in writes() if x[0] == "POST"])
    code, out = run(root, base, "--upload", "--only", "wing_feather")
    st = state()
    w = st["assets"]["wing_feather"]
    check("structure change -> POST of a new asset; the key's id changes", code == 0 and len([x for x in writes() if x[0] == "POST"]) == n_post + 1
          and w["assetId"] != ids["wing_feather"] and w["previousAssetIds"] == [ids["wing_feather"]] and w["structureHash"] == "s-wing-2", w)
    check("MeshIds.lua follows the new id", "wing_feather = %d," % w["assetId"] in open(lua_path).read())

    # 7) interrupted poll -> pending saved; the next run resumes without uploading again
    index["assets"]["cal_axes"]["contentHash"] = "c-cal-2"
    write_index(root, index)
    STATE["never_done"] = True
    run(root, base, "--upload", "--only", "cal_axes", "--poll-timeout", "0")
    st = state()
    check("a poll that times out is saved as pendingOperation", bool(st["assets"]["cal_axes"].get("pendingOperation")) and st["assets"]["cal_axes"]["contentHash"] == "c-cal_axes-1", st["assets"]["cal_axes"])
    STATE["never_done"] = False
    n_w = len(writes())
    code, out = run(root, base, "--upload", "--only", "cal_axes")
    st = state()
    check("resume: polls the saved operation, no second upload", code == 0 and len(writes()) == n_w and not st["assets"]["cal_axes"].get("pendingOperation")
          and st["assets"]["cal_axes"]["revisionId"] == "2" and st["assets"]["cal_axes"]["contentHash"] == "c-cal-2", out)
    n = len(STATE["log"])
    run(root, base, "--upload", "--only", "cal_axes")
    check("after the resume the key counts as uploaded", len(STATE["log"]) == n)

    # 8) moderation: Rejected ids leave MeshIds.lua; --refresh reads the state
    STATE["reject"].add(ids["pet_dog"])
    code, out = run(root, base, "--upload", "--refresh")
    st = state()
    lua = open(lua_path).read()
    check("--refresh reads moderation; a Rejected id is left out of MeshIds.lua", code == 0 and st["assets"]["pet_dog"]["moderationState"] == "MODERATION_STATE_REJECTED"
          and "pet_dog =" not in lua and "cal_axes =" in lua and not [x for x in STATE["log"][n:] if x[0] in ("POST", "PATCH")], lua)

    # 9) failures stay per key: a missing FBX / a too-big mesh fail, the others go on
    index["assets"]["cal_axes"].update({"contentHash": "c-cal-3", "maxTrianglesPerMesh": 25000})
    index["assets"]["wing_feather"]["contentHash"] = "c-wing-3"
    write_index(root, index)
    os.remove(os.path.join(root, "blender", "out", "pet_dog.fbx"))
    index["assets"]["pet_dog"]["contentHash"] = "c-pet_dog-3"
    write_index(root, index)
    code, out = run(root, base, "--upload")
    st = state()
    check("per-key failures (missing FBX, > 20k triangles) exit 1 and keep going", code == 1 and "missing" in st["assets"]["pet_dog"].get("lastError", "")
          and "triangles" in st["assets"]["cal_axes"].get("lastError", "") and st["assets"]["wing_feather"]["contentHash"] == "c-wing-3", out)

    # 10) a different creator is refused (dry run too), groups use groupId
    os.environ["ROBLOX_CREATOR_ID"] = "999"
    n = len(STATE["log"])
    code, out = run(root, base, "--upload")
    check("another creator is refused (exit 2), nothing sent", code == 2 and "Refusing" in out and len(STATE["log"]) == n, out)
    code, out = run(root, base)
    check("...also in a dry run", code == 2, out)
    os.environ["ROBLOX_CREATOR_ID"] = "123456"
    root2, _ = make_repo(os.path.join(tmp, "g"))
    os.environ["ROBLOX_CREATOR_TYPE"] = "group"
    code, out = run(root2, base, "--upload", "--only", "cal_axes")
    check("ROBLOX_CREATOR_TYPE=group sends a groupId creator", code == 0 and '"groupId": "123456"' in writes()[-1][3], writes()[-1])
    os.environ.pop("ROBLOX_CREATOR_TYPE")

    # 12) --textures (the Image class of the gate vortex): a dry run plans Decal / image/png uploads, writes nothing
    troot = os.path.join(tmp, "tex")
    os.makedirs(os.path.join(troot, "blender", "textures", "vortex"))
    os.makedirs(os.path.join(troot, "src", "shared"))
    tindex = {"comment": "test", "keys": {}}
    for tk in ("vortex_arms", "vortex_rim"):
        with open(os.path.join(troot, "blender", "textures", "vortex", tk + ".png"), "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n" + tk.encode())
        tindex["keys"][tk] = {"png": "blender/textures/vortex/%s.png" % tk, "displayName": "NC " + tk, "contentHash": "h-" + tk, "structureHash": "image"}
    with open(os.path.join(troot, "blender", "textures", "textures.json"), "w") as f:
        json.dump(tindex, f)
    n = len(STATE["log"])
    code, out = run(troot, base, "--textures")
    check("--textures dry run: exit 0, two Decal / image/png creates", code == 0 and "DRY RUN" in out and out.count('"assetType": "Decal"') == 2
          and "image/png" in out, out)
    check("--textures dry run sends and writes nothing", len(STATE["log"]) == n and not os.path.exists(os.path.join(troot, "src", "shared", "TextureIds.lua"))
          and not os.path.exists(os.path.join(troot, "blender", "textures", "upload_state.json")), STATE["log"][n:])
    code, out = run(troot, base, "--textures", "--only", "pet_dog")
    check("--textures --only checks the texture index", code == 2 and "textures.json" in out, out)
    U.CLASS = U.CLASSES["image"]
    lua = U.mesh_ids_lua({"assets": {"vortex_arms": {"assetId": 77}, "vortex_rim": {"assetId": 78, "moderationState": "Rejected"}}})
    U.CLASS = U.CLASSES["mesh"]
    check("TextureIds.lua: numbers only, rejected left out", "vortex_arms = 77," in lua and "vortex_rim" not in lua and "TextureIds" not in lua.split("return")[1], lua)

    # 13) review3 tooling-0: the FBX must be the one exported for this contentHash (meshes.json fbxSha256 / manifest)
    froot, findex = make_repo(os.path.join(tmp, "fresh"))
    fout = os.path.join(froot, "blender", "out")
    n_w = len(writes())
    findex["assets"]["pet_dog"].update({"contentHash": "c-pet_dog-9", "fbxSha256": None})  # a --no-export build
    write_index(froot, findex)
    code, out = run(froot, base, "--upload", "--only", "pet_dog")
    check("fbxSha256 null (a --no-export build) -> refused, nothing sent", code == 1 and "--no-export" in out and len(writes()) == n_w, out)
    with open(os.path.join(fout, "cal_axes.fbx"), "ab") as f:
        f.write(b"older bytes")
    code, out = run(froot, base, "--upload", "--only", "cal_axes")
    check("FBX bytes differ from meshes.json fbxSha256 -> refused", code == 1 and "fbxSha256" in out and len(writes()) == n_w, out)
    del findex["assets"]["wing_feather"]["fbxSha256"]  # an entry from before review3: the manifest decides
    write_index(froot, findex)
    wsha = sha_of(os.path.join(fout, "wing_feather.fbx"))
    man_path = os.path.join(fout, "wing_feather.manifest.json")
    results_fb = []
    for label, man in (("no manifest", None),
                       ("manifest verify null (--no-export)", {"contentHash": "c-wing_feather-1", "verify": None}),
                       ("manifest of another contentHash", {"contentHash": "c-old", "verify": {"ok": True}}),
                       ("manifest sha256 differs", {"contentHash": "c-wing_feather-1", "verify": {"ok": True, "sha256": "0" * 64}})):
        if man is not None:
            with open(man_path, "w") as f:
                json.dump(man, f)
        code, out = run(froot, base, "--upload", "--only", "wing_feather")
        results_fb.append((label, code == 1 and "rebuild it" in out and len(writes()) == n_w))
    check("no fbxSha256: the manifest fallback refuses a missing / unverified / other-hash / other-bytes FBX", all(r[1] for r in results_fb), results_fb)
    with open(man_path, "w") as f:
        json.dump({"contentHash": "c-wing_feather-1", "verify": {"ok": True, "sha256": wsha}}, f)
    code, out = run(froot, base, "--upload", "--only", "wing_feather")
    check("...and accepts the FBX its verified manifest describes", code == 0 and len(writes()) == n_w + 1, out)
    rebuild(froot, findex, "pet_dog", b"new", contentHash="c-pet_dog-9")
    code, out = run(froot, base, "--upload", "--only", "pet_dog")
    check("after an export build (fbxSha256 matches) the key uploads", code == 0 and len(writes()) == n_w + 2, out)

    # 14) review3 tooling-6: the hints name the Blender python, never plain python3, and warn about --no-export
    os.remove(os.path.join(fout, "cal_axes.fbx"))
    code, out = run(froot, base, "--only", "cal_axes")
    check("missing-FBX hint: the Blender python + 'not --no-export'", "bpyenv/bin/python blender/build_all.py --key cal_axes" in out
          and "not --no-export" in out and "python3 blender/build_all.py" not in out, out)
    eroot = os.path.join(tmp, "empty")
    os.makedirs(eroot)
    code, out = run(eroot, base)
    check("no-index refusal: the Blender python too", code == 2 and "bpyenv/bin/python blender/build_all.py --all" in out
          and "python3 blender/build_all.py" not in out, out)

    # 15) review3 tooling-2/3: Client.request retries reads / PATCH on raw connection errors; a POST create is retried
    #     only when Roblox cannot have made the asset (429 / 503 / never sent), else CreateUnknown after ONE attempt
    class Resp:
        def __init__(self, raw):
            self.raw = raw

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def read(self):
            return self.raw

    class Opener:
        def __init__(self, script):
            self.script = list(script)
            self.calls = 0

        def open(self, req, timeout=None):
            self.calls += 1
            step = self.script.pop(0)
            if isinstance(step, BaseException):
                raise step
            if isinstance(step, int):
                raise urllib.error.HTTPError(req.full_url, step, "x", {}, io.BytesIO(b"{}"))
            return Resp(step)

    def call(method, script, idem=True):
        c = U.Client("http://127.0.0.1:1", KEY, False, lambda m: None)
        c.opener = Opener(script)
        try:
            return c.request(method, "/x", idempotent=idem), c.opener.calls
        except Exception as e:  # noqa: BLE001
            return e, c.opener.calls

    ok = b'{"path": "operations/1"}'
    cases = [
        ("GET: RemoteDisconnected retried", "GET", [http.client.RemoteDisconnected("x"), ok], True, dict, 2),
        ("GET: socket.timeout retried", "GET", [socket.timeout("t"), ok], True, dict, 2),
        ("GET: ConnectionResetError retried", "GET", [ConnectionResetError("r"), ok], True, dict, 2),
        ("GET: IncompleteRead retried", "GET", [http.client.IncompleteRead(b"x"), ok], True, dict, 2),
        ("PATCH: 502 retried", "PATCH", [502, ok], True, dict, 2),
        ("POST: URLError (never sent) retried", "POST", [urllib.error.URLError(ConnectionRefusedError("no")), ok], False, dict, 2),
        ("POST: 429 retried", "POST", [429, ok], False, dict, 2),
        ("POST: 503 retried", "POST", [503, ok], False, dict, 2),
        ("POST: 502 -> CreateUnknown, no retry", "POST", [502, ok], False, U.CreateUnknown, 1),
        ("POST: 504 -> CreateUnknown, no retry", "POST", [504, ok], False, U.CreateUnknown, 1),
        ("POST: RemoteDisconnected -> CreateUnknown", "POST", [http.client.RemoteDisconnected("x"), ok], False, U.CreateUnknown, 1),
        ("POST: socket.timeout -> CreateUnknown", "POST", [socket.timeout("t"), ok], False, U.CreateUnknown, 1),
        ("POST: 400 -> UploadError (not unknown)", "POST", [400], False, U.UploadError, 1),
        ("GET: gives up after MAX_ATTEMPTS", "GET", [ConnectionResetError("r")] * U.MAX_ATTEMPTS, True, U.UploadError, U.MAX_ATTEMPTS),
    ]
    bad = []
    for label, method, script, idem, want, calls in cases:
        got, n_calls = call(method, script, idem)
        exact = type(got) is want if want is not U.UploadError else (type(got) is U.UploadError)
        if not (exact and n_calls == calls):
            bad.append((label, type(got).__name__, n_calls))
    check("Client.request: %d retry / no-blind-retry cases" % len(cases), not bad, bad)

    # 16) end to end against the fake: an unknown create is marked, refused, then settled with --adopt / --not-created
    uroot, uindex = make_repo(os.path.join(tmp, "unknown"))
    ustate = os.path.join(uroot, "blender", "upload_state.json")

    def ust(key):
        with open(ustate) as f:
            return json.load(f)["assets"].get(key, {})

    n_assets, n_posts = len(STATE["assets"]), len([x for x in writes() if x[0] == "POST"])
    STATE["post_mode"] = ["create_504"]
    code, out = run(uroot, base, "--upload", "--only", "cal_axes")
    made = STATE["next_id"] - 1
    rec = ust("cal_axes")
    check("504 after the backend created: no second POST, pendingCreate saved, Creator Hub hint", code == 1 and len(STATE["assets"]) == n_assets + 1
          and len([x for x in writes() if x[0] == "POST"]) == n_posts + 1 and rec.get("pendingCreate", {}).get("contentHash") == "c-cal_axes-1"
          and not rec.get("assetId") and "Creator Hub" in rec.get("lastError", "") and "--adopt cal_axes=" in out, out)
    n = len(STATE["log"])
    code, out = run(uroot, base, "--upload", "--only", "cal_axes")
    check("the next run refuses the key (nothing sent) until it is settled", code == 1 and len(STATE["log"]) == n and "--not-created cal_axes" in out, out)
    code, out = run(uroot, base, "--upload", "--adopt", "pet_dog=5")
    check("--adopt of a key with no unknown create is refused", code == 2 and "pendingCreate" in out, out)
    code, out = run(uroot, base, "--upload", "--only", "cal_axes", "--adopt", "cal_axes=%d" % made)
    rec = ust("cal_axes")
    check("--adopt KEY=ID records the asset it made (+ reads its moderation), no upload", code == 0 and rec.get("assetId") == made
          and not rec.get("pendingCreate") and rec.get("contentHash") == "c-cal_axes-1" and rec.get("moderationState")
          and not [x for x in STATE["log"][n:] if x[0] in ("POST", "PATCH")] and ("GET", "/assets/v1/assets/%d" % made) in STATE["log"][n:], out)
    n = len(STATE["log"])
    run(uroot, base, "--upload", "--only", "cal_axes")
    check("after --adopt the key counts as uploaded", len(STATE["log"]) == n, STATE["log"][n:])

    n_assets = len(STATE["assets"])
    STATE["post_mode"] = ["create_drop"]
    code, out = run(uroot, base, "--upload", "--only", "pet_dog")
    check("connection dropped after the create (RemoteDisconnected): no retry, no traceback, pendingCreate", code == 1
          and len(STATE["assets"]) == n_assets + 1 and ust("pet_dog").get("pendingCreate") and "Traceback" not in out, out)
    STATE["post_mode"] = ["drop"]
    code, out = run(uroot, base, "--upload", "--only", "wing_feather")
    check("connection dropped with nothing created: still unknown to the tool -> pendingCreate", code == 1 and len(STATE["assets"]) == n_assets + 1
          and ust("wing_feather").get("pendingCreate"), out)
    code, out = run(uroot, base, "--upload", "--only", "wing_feather,pet_dog", "--not-created", "wing_feather")
    check("--not-created KEY creates it again; the other unknown key stays refused", code == 1 and isinstance(ust("wing_feather").get("assetId"), int)
          and not ust("wing_feather").get("pendingCreate") and ust("pet_dog").get("pendingCreate") and len(STATE["assets"]) == n_assets + 2, out)

    # a 502 straight from the gateway on the create: not retried either (the fake's fail_next answers before creating)
    rebuild(uroot, uindex, "wing_feather", b"2", contentHash="c-wing-u2", structureHash="s-wing-u2")
    n_posts = len([x for x in STATE["log"] if x[0] in ("POST", "502")])
    STATE["fail_next"] = [502]
    code, out = run(uroot, base, "--upload", "--only", "wing_feather")
    check("HTTP 502 on a create (new-asset) -> one attempt, pendingCreate", code == 1 and len([x for x in STATE["log"] if x[0] in ("POST", "502")]) == n_posts + 1
          and ust("wing_feather").get("pendingCreate", {}).get("structureHash") == "s-wing-u2", out)
    STATE["fail_next"] = [503]
    code, out = run(uroot, base, "--upload", "--only", "wing_feather", "--not-created", "wing_feather")
    w = ust("wing_feather")
    check("HTTP 503 on a create is retried (rejected before acceptance) -> one new asset", code == 0 and w.get("structureHash") == "s-wing-u2"
          and len(w.get("previousAssetIds", [])) == 1 and not w.get("pendingCreate"), out)

    # a crash / Ctrl-C in the middle of the POST: the mark was saved BEFORE it
    real_request = U.Client.request

    def ctrl_c(self, method, *a, **kw):
        if method == "POST":
            raise KeyboardInterrupt
        return real_request(self, method, *a, **kw)

    U.Client.request = ctrl_c
    interrupted = False
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            U.main(["--root", uroot, "--base-url", base, "--upload", "--only", "pet_dog", "--not-created", "pet_dog"])
    except KeyboardInterrupt:
        interrupted = True
    finally:
        U.Client.request = real_request
    check("Ctrl-C mid-POST: the key stays marked pendingCreate on disk", interrupted and ust("pet_dog").get("pendingCreate", {}).get("why") == "interrupted")

    # reads and PATCHes ARE retried on dropped connections
    rebuild(uroot, uindex, "cal_axes", b"3", contentHash="c-cal-u2")
    STATE["drop_reads"], STATE["drop_patch"] = 1, 1
    code, out = run(uroot, base, "--upload", "--only", "cal_axes")
    check("dropped PATCH answer + dropped poll are retried -> exit 0", code == 0 and ust("cal_axes").get("contentHash") == "c-cal-u2"
          and ust("cal_axes").get("assetId") == made, out)

    # one key's unexpected error does not abort the batch
    uindex["assets"]["wing_feather"]["maxTrianglesPerMesh"] = "lots"
    rebuild(uroot, uindex, "wing_feather", b"4", contentHash="c-wing-u3")
    rebuild(uroot, uindex, "cal_axes", b"4", contentHash="c-cal-u3")
    code, out = run(uroot, base, "--upload", "--only", "cal_axes,wing_feather")
    check("an unexpected error in one key is recorded, the batch goes on (exit 1)", code == 1 and "ValueError" in ust("wing_feather").get("lastError", "")
          and ust("cal_axes").get("contentHash") == "c-cal-u3" and "Traceback" not in out, out)
    check("the API key never appears in any output or state", KEY not in out and KEY not in open(ustate).read())

    # 17) review3 tooling-1: images are never PATCHed; a changed PNG (same size) is a NEW asset
    tstate = os.path.join(troot, "blender", "textures", "upload_state.json")
    tlua = os.path.join(troot, "src", "shared", "TextureIds.lua")
    n_w = len(writes())
    code, out = run(troot, base, "--textures", "--upload")
    with open(tstate) as f:
        ts = json.load(f)
    tids = {k: r.get("assetId") for k, r in ts["assets"].items()}
    check("--textures --upload (fake): two Decal / image/png creates, no bad requests", code == 0 and len(writes()) == n_w + 2 and not STATE["bad"]
          and all(isinstance(v, int) for v in tids.values()), out)
    U.CLASS = U.CLASSES["image"]
    p_same = U.plan("vortex_arms", {"contentHash": "new", "structureHash": "s1"}, {"assetId": 111, "contentHash": "old", "structureHash": "s1"})
    U.CLASS = U.CLASSES["mesh"]
    check("plan(): a changed image of the same size -> new-asset (never update)", p_same[0] == "new-asset", p_same)
    with open(os.path.join(troot, "blender", "textures", "vortex", "vortex_arms.png"), "ab") as f:
        f.write(b"retuned")
    tindex["keys"]["vortex_arms"]["contentHash"] = "h-vortex_arms-2"
    ts["assets"]["vortex_arms"]["decalAssetId"] = 4242  # the OWNER_UPLOAD.md section 6 Image-id swap happened
    with open(tstate, "w") as f:
        json.dump(ts, f)
    with open(os.path.join(troot, "blender", "textures", "textures.json"), "w") as f:
        json.dump(tindex, f)
    n = len(STATE["log"])
    code, out = run(troot, base, "--textures", "--upload")
    with open(tstate) as f:
        arms = json.load(f)["assets"]["vortex_arms"]
    new_w = [x for x in STATE["log"][n:] if x[0] in ("POST", "PATCH", "PATCH-refused")]
    check("changed PNG: one POST, no PATCH; the old ids kept in previousAssetIds; TextureIds.lua follows", code == 0
          and [x[0] for x in new_w] == ["POST"] and arms["assetId"] != tids["vortex_arms"] and arms["previousAssetIds"] == [tids["vortex_arms"], 4242]
          and "decalAssetId" not in arms and "vortex_arms = %d," % arms["assetId"] in open(tlua).read() and "Image id" in out, out)
    n = len(STATE["log"])
    code, out = run(troot, base, "--textures", "--upload", "--force", "--only", "vortex_rim")
    check("--force on an uploaded, unchanged image is refused (it would only duplicate)", code == 1 and "duplicate" in out
          and not [x for x in STATE["log"][n:] if x[0] in ("POST", "PATCH")], out)

    # 18) review3 tooling-5: check.mjs lets PortalVortex.lua join "rbxassetid://" only to a TextureIds id variable
    node = shutil.which("node")
    if node:
        import subprocess
        vdir = os.path.join(tmp, "vortex", "src", "client")
        os.makedirs(vdir)
        vfile = os.path.join(vdir, "PortalVortex.lua")
        cases = [
            ("good: .. tostring(id) / .. id / .. ids[key]", 'return function(l, id, ids, key) l.Image = "rbxassetid://" .. tostring(id); '
             'l.Image = "rbxassetid://" .. id; l.Image = "rbxassetid://" .. ids[key] end', 0),
            ("PREFIX .. 1818", 'local PREFIX = "rbxassetid://"\nreturn function(l) l.Image = PREFIX .. 1818 end', 1),
            ('.. "123456789"', 'return function(l) l.Image = "rbxassetid://" .. "123456789" end', 1),
            (".. 1818", 'return function(l) l.Image = "rbxassetid://" .. 1818 end', 1),
            ("local n = 1818 .. tostring(n)", 'local n = 1818\nreturn function(l) l.Image = "rbxassetid://" .. tostring(n) end', 1),
            (".. tostring(1818)", 'return function(l) l.Image = "rbxassetid://" .. tostring(1818) end', 1),
            ("rbxassetid://123", 'return function(l) l.Image = "rbxassetid://123" end', 1),
        ]
        wrong = []
        for label, src, want in cases:
            with open(vfile, "w") as f:
                f.write(src + "\n")
            res = subprocess.run([node, os.path.join(HERE, "check.mjs"), vfile], capture_output=True, text=True)
            got = res.stdout.count("asset-id")
            if got != want:
                wrong.append((label, got, res.stdout[-300:]))
        check("check.mjs PortalVortex asset-id rule: %d cases" % len(cases), not wrong, wrong)
    else:
        print("SKIP check.mjs PortalVortex cases (no node)")

    # 11) the throttle (unit, fake clock): the 4th call in a minute waits
    clock = [0.0]
    slept = []
    th = U.Throttle(3, clock=lambda: clock[0], sleep=lambda s: (slept.append(s), clock.__setitem__(0, clock[0] + s)))
    for _ in range(4):
        real_wait(th)
    check("throttle: at most N calls per 60 s (the 4th waits ~60 s)", len(slept) == 1 and 59.9 < slept[0] < 60.2, slept)
    check("throttle constants stay under the documented limits", U.WRITE_PER_MINUTE < 120 and U.READ_PER_MINUTE < 300)

    srv.shutdown()
    shutil.rmtree(tmp, ignore_errors=True)
    for k in ("ROBLOX_API_KEY", "ROBLOX_CREATOR_ID"):
        os.environ.pop(k, None)
    print("%d/%d passed" % (sum(results), len(results)))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
