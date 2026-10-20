#!/usr/bin/env python3
"""Offline tests of tools/upload_assets.py against a LOCAL fake of the Open Cloud Assets API (127.0.0.1 only).

Nothing here talks to Roblox: the fake mirrors the documented request / response shapes (POST /assets/v1/assets,
PATCH /assets/v1/assets/{id}, GET /assets/v1/operations/{id}, GET /assets/v1/assets/{id}) and checks every request
(x-api-key, multipart parts, assetType Model, model/fbx, the creator block). Exit code 0 = all passed.

    python3 tools/test_upload_assets.py
"""
import contextlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import upload_assets as U  # noqa: E402

KEY = "test-key-not-real-0123456789"
STATE = {}


def reset_fake():
    STATE.clear()
    STATE.update({"next_id": 9000000001, "ops": {}, "assets": {}, "log": [], "fail_next": [], "never_done": False,
                  "reject": set(), "bad": []})


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
        if ct != "model/fbx" or 'filename="' not in head:
            problems.append("fileContent part")
        if req.get("assetType") != "Model":
            problems.append("assetType")
        creator = req.get("creationContext", {}).get("creator", {})
        if not (creator.get("userId") or creator.get("groupId")):
            problems.append("creator")
        if asset_id is None:
            if not req.get("displayName") or not req.get("description") or "assetId" in req:
                problems.append("create fields")
            asset_id = STATE["next_id"]
            STATE["next_id"] += 1
            STATE["assets"][asset_id] = {"rev": 0, "creator": creator, "name": req.get("displayName")}
        elif str(req.get("assetId")) != str(asset_id):
            problems.append("update assetId")
        STATE["bad"] += problems
        STATE["assets"][asset_id]["rev"] += 1
        rev = STATE["assets"][asset_id]["rev"]
        op = "op-%d-%d" % (asset_id, rev)
        STATE["ops"][op] = {"asset": asset_id, "polls": 0, "rev": rev}
        STATE["log"].append((self.command, self.path, len(data), json.dumps(creator)))
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
                                "contentHash": "c-" + key + "-1", "structureHash": struct}
    write_index(root, index)
    return root, index


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
    index["assets"]["pet_dog"]["contentHash"] = "c-pet_dog-2"
    write_index(root, index)
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
