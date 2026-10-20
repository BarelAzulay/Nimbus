#!/usr/bin/env python3
"""Offline test of upload_assets.py against a LOCAL fake of the Open Cloud Assets API (127.0.0.1).

Nothing here talks to Roblox: the fake server only mirrors the documented request / response shapes
(POST /assets/v1/assets, PATCH /assets/v1/assets/{id}, GET /assets/v1/operations/{id}, GET /assets/v1/assets/{id})
so the uploader's create / skip / update / resume / 429 paths can be exercised without the real key.

    python3 test_upload_assets.py
"""
import json
import os
import shutil
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import upload_assets  # noqa: E402

STATE = {"next_id": 9000000001, "ops": {}, "assets": {}, "log": [], "throttle_once": False, "never_done": False}


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
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n)

    def check_key(self):
        if self.headers.get("x-api-key") != "test-key-not-real":
            self.reply(401, {"code": "UNAUTHENTICATED"})
            return False
        return True

    def upload(self, asset_id):
        parts = parse_multipart(self.body(), self.headers["Content-Type"])
        req = json.loads(parts["request"][0].decode())
        data, ct, head = parts["fileContent"]
        assert ct == "model/fbx", ct
        assert 'filename="' in head
        assert req["assetType"] == "Model"
        assert "userId" in req["creationContext"]["creator"]
        if asset_id is None:
            assert req["displayName"] and req["description"]
            asset_id = STATE["next_id"]
            STATE["next_id"] += 1
            STATE["assets"][asset_id] = {"rev": 0}
        else:
            assert str(req["assetId"]) == str(asset_id), req
        STATE["assets"][asset_id]["rev"] += 1
        op = "op-%d-%d" % (asset_id, STATE["assets"][asset_id]["rev"])
        STATE["ops"][op] = {"asset": asset_id, "polls": 0, "rev": STATE["assets"][asset_id]["rev"]}
        STATE["log"].append((self.command, self.path, len(data)))
        self.reply(200, {"path": "operations/" + op, "done": False})

    def do_POST(self):
        if not self.check_key():
            return
        if self.path == "/assets/v1/assets":
            if STATE["throttle_once"]:
                STATE["throttle_once"] = False
                self.body()
                STATE["log"].append(("429", self.path, 0))
                return self.reply(429, {"code": "RESOURCE_EXHAUSTED"}, {"retry-after": "0.2"})
            return self.upload(None)
        self.reply(404, {})

    def do_PATCH(self):
        if not self.check_key():
            return
        asset_id = int(self.path.rsplit("/", 1)[1])
        if asset_id not in STATE["assets"]:
            return self.reply(404, {"code": "NOT_FOUND"})
        return self.upload(asset_id)

    def do_GET(self):
        if not self.check_key():
            return
        STATE["log"].append(("GET", self.path, 0))
        if self.path.startswith("/assets/v1/operations/"):
            op = STATE["ops"][self.path.rsplit("/", 1)[1]]
            op["polls"] += 1
            if op["polls"] < 2 or STATE["never_done"]:
                return self.reply(200, {"path": "operations/x", "done": False})
            a = op["asset"]
            return self.reply(200, {"path": "operations/x", "done": True, "response": {
                "@type": "type.googleapis.com/roblox.open_cloud.assets.v1.Asset", "path": "assets/%d" % a,
                "assetId": str(a), "revisionId": str(op["rev"]), "revisionCreateTime": "2026-10-20T00:00:00Z",
                "assetType": "ASSET_TYPE_MODEL", "displayName": "x",
                "moderationResult": {"moderationState": "MODERATION_STATE_REVIEWING" if op["rev"] == 1 else "MODERATION_STATE_APPROVED"}}})
        if self.path.startswith("/assets/v1/assets/"):
            a = int(self.path.rsplit("/", 1)[1])
            return self.reply(200, {"assetId": str(a), "revisionId": str(STATE["assets"][a]["rev"]),
                                    "moderationResult": {"moderationState": "MODERATION_STATE_APPROVED"}})
        self.reply(404, {})


def run(root, base, *extra):
    upload_assets.Throttle.wait = lambda self: None  # no sleeping in tests
    return upload_assets.main(["--root", root, "--base-url", base, "--poll-timeout", "5",
                               "--emit-lua", "src/shared/MeshIds.lua"] + list(extra))


def main():
    import time
    time.sleep = (lambda real: (lambda s: real(min(s, 0.01))))(time.sleep)
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % srv.server_address[1]
    tmp = tempfile.mkdtemp(prefix="upl_")
    root = os.path.join(tmp, "repo")
    shutil.copytree(os.path.join(HERE, "sample", "blender"), os.path.join(root, "blender"))
    os.environ["ROBLOX_API_KEY"] = "test-key-not-real"
    os.environ["ROBLOX_CREATOR_ID"] = "123456"
    os.environ.pop("ROBLOX_CREATOR_TYPE", None)
    ids_path = os.path.join(root, "blender", "mesh_ids.json")
    results = []

    def check(name, cond, detail=""):
        results.append(cond)
        print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + detail))

    # 1) first run: one 429 then two creates, polled to done
    STATE["throttle_once"] = True
    rc = run(root, base)
    table = json.load(open(ids_path))
    ids = {n: r.get("assetId") for n, r in table["assets"].items()}
    check("first run exit 0", rc == 0)
    check("two assets created", len([x for x in STATE["log"] if x[0] == "POST"]) == 2, str(STATE["log"]))
    check("429 was retried", any(x[0] == "429" for x in STATE["log"]))
    check("ids recorded", all(isinstance(v, int) for v in ids.values()), str(ids))
    check("moderation recorded", table["assets"]["PebblePup"]["moderationState"] == "MODERATION_STATE_REVIEWING")
    lua = open(os.path.join(root, "src", "shared", "MeshIds.lua")).read()
    check("lua id module emitted", "PebblePup = %d" % ids["PebblePup"] in lua and "rbxassetid" not in lua, lua)

    # 2) second run: nothing changed -> no upload requests
    n_before = len(STATE["log"])
    rc = run(root, base)
    check("unchanged run sends nothing", rc == 0 and len(STATE["log"]) == n_before, str(STATE["log"][n_before:]))

    # 3) change PebblePup -> PATCH same id, revision 2
    with open(os.path.join(root, "blender", "out", "PebblePup.fbx"), "ab") as f:
        f.write(b"\0changed")
    rc = run(root, base)
    table = json.load(open(ids_path))
    patches = [x for x in STATE["log"] if x[0] == "PATCH"]
    check("changed file -> PATCH new version", rc == 0 and len(patches) == 1 and str(ids["PebblePup"]) in patches[0][1], str(patches))
    check("id stable, revision 2", table["assets"]["PebblePup"]["assetId"] == ids["PebblePup"]
          and table["assets"]["PebblePup"]["revisionId"] == "2", json.dumps(table["assets"]["PebblePup"]))

    # 4) interrupted poll -> pendingOperation saved, next run resumes without uploading again
    with open(os.path.join(root, "blender", "out", "LobbyCloudPuff.fbx"), "ab") as f:
        f.write(b"\0changed")
    STATE["never_done"] = True
    run(root, base, "--only", "LobbyCloudPuff", "--poll-timeout", "0")
    table = json.load(open(ids_path))
    check("pending operation saved", bool(table["assets"]["LobbyCloudPuff"].get("pendingOperation")))
    STATE["never_done"] = False
    n_up = len([x for x in STATE["log"] if x[0] in ("POST", "PATCH")])
    rc = run(root, base, "--only", "LobbyCloudPuff")
    table = json.load(open(ids_path))
    check("resume finishes without a new upload", rc == 0 and n_up == len([x for x in STATE["log"] if x[0] in ("POST", "PATCH")])
          and not table["assets"]["LobbyCloudPuff"].get("pendingOperation")
          and table["assets"]["LobbyCloudPuff"]["revisionId"] == "2", json.dumps(table["assets"]["LobbyCloudPuff"]))
    n_up2 = len(STATE["log"])
    run(root, base, "--only", "LobbyCloudPuff")
    check("after resume the file counts as uploaded", len(STATE["log"]) == n_up2)

    # 5) refresh reads moderation state
    rc = run(root, base, "--refresh")
    table = json.load(open(ids_path))
    check("refresh updates moderation", table["assets"]["PebblePup"]["moderationState"] == "MODERATION_STATE_APPROVED")

    # 6) a different creator is refused
    os.environ["ROBLOX_CREATOR_ID"] = "999"
    try:
        run(root, base)
        check("other creator refused", False, "no exit")
    except SystemExit as e:
        check("other creator refused", "creator" in str(e), str(e))

    srv.shutdown()
    shutil.rmtree(tmp, ignore_errors=True)
    print("%d/%d passed" % (sum(results), len(results)))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
