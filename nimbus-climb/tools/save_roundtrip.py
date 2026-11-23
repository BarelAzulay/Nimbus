#!/usr/bin/env python3
"""Release step 1, gate 2: the save round trip between MAIN (the live game) and this branch.

    py -3.12 tools/save_roundtrip.py [--main-ref origin/main] [--only build,load,rollback,lock] [--json FILE]
                                     [--dump FILE] [--branch-root DIR] [-v]

What it does (no real DataStore, no network, no API key: everything runs in tools/robloxmock.lua):

  * MAIN's code is taken straight from git (`git archive <commit> src default.project.json`, the commit id is printed
    and written into the report) and booted as a real server (its own Main.server.lua, its own DataService and
    catalogs) in its own Lua world. This branch's code boots the same way in other worlds.
  * Every world reads and writes ONE fake DataStore that lives in this Python process (tools/save_roundtrip.lua puts
    a proxy in place of Mock.DataStore.Data), so a save one server writes is the save the next server reads, and two
    servers of this branch really are two servers (two Lua runtimes, two lock ids, one store).

  build     MAIN's own save code writes the fake saves: a new player, a maxed player (every field filled, big
            numbers, every pet), saves with missing fields (main's sparse new-player record, and main's maxed record
            with whole keys / inner keys removed by hand) and two v1 legacy saves (the old store).
  load      (a) each save loads in this branch with nothing lost: MAIN's own reading of the save is compared FIELD BY
            FIELD with this branch's reading, and the stored record before / after a session of this branch.
  rollback  (b) a save this branch wrote (its session lock fields, its Store / Daily / Trove / Pity fields, progress
            on main's fields) is read by MAIN's code without an error and without losing a main field; main then
            saves it and this branch reads it again (roll forward).
  lock      (c) two servers of this branch on one save: a second server while the first holds the lock, a rejoin, a
            server hop while the old server's last save is still on its way, a crash without a release (the lock
            expires): never two owners, never a lost write. And a mixed fleet (a MAIN server and a branch server on
            one save, both ways: the first hour after a publish, and after a rollback): every Token of both servers
            is in the final record.

Every difference found is printed in the "FIELD DIFFERENCES" list at the end, with the reason it is allowed; a
difference that is not in the allowed list fails the run. The lines marked ROLLBACK COST are what a player loses
when the owner restores main and the player then plays on main (docs/release/step1-rollback.md lists them).

Proof that the checks can fail: --branch-root DIR tests a copy of the branch; a copy that drops a field, reshapes a
field or shortens the lock turns the run red (see docs/release/step1-pr.md, "Mutation proof").
Exit status: 0 = every check passed, 1 = a check failed, 2 = main's code could not be read from git.
"""
import argparse
import gc
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import smoke  # noqa: E402  (tools/smoke.py: the World class, the Lua engine loader)

V2 = "NimbusClimb_v2"
V1 = "NimbusClimb_v1"


# ---------------------------------------------------------------------------------------------------
# values: Lua <-> Python, flat maps
# ---------------------------------------------------------------------------------------------------
def is_lua_table(v):
    return type(v).__name__ == "_LuaTable"


def num(v):
    if isinstance(v, float) and v.is_integer() and abs(v) < 2 ** 53:
        return int(v)
    return v


def plain(v, bad=None, path=""):
    """A stored Lua value as plain Python (list for an array 1..n, dict for a map), like JSON would hold it."""
    if is_lua_table(v):
        keys = list(v.keys())
        n = len(keys)
        if n and all(isinstance(k, (int, float)) and not isinstance(k, bool) and float(k).is_integer() for k in keys):
            if sorted(int(k) for k in keys) == list(range(1, n + 1)):
                return [plain(v[k], bad, "%s[%d]" % (path, i)) for i, k in enumerate(sorted(keys), 1)]
        out = {}
        for k in keys:
            if not isinstance(k, str):
                if bad is not None:
                    bad.append("%s holds the non-string key %r (a sparse array or a mixed table)" % (path or "<record>", k))
                out["#%s" % num(k)] = plain(v[k], bad, "%s[%s]" % (path, num(k)))
            else:
                out[k] = plain(v[k], bad, "%s.%s" % (path, k))
        return out
    return num(v)


def flat(v, path="", out=None):
    """path -> 'n:<%.17g>' | 's:<text>' | 'b:true' | '{}' (the same form as RT.flat in save_roundtrip.lua)."""
    if out is None:
        out = {}
    if isinstance(v, dict):
        if not v:
            out[path] = "{}"
        for k in v:
            flat(v[k], "%s.%s" % (path, k), out)
    elif isinstance(v, (list, tuple)):
        if not v:
            out[path] = "{}"
        for i, x in enumerate(v, 1):
            flat(x, "%s[%d]" % (path, i), out)
    elif isinstance(v, bool):
        out[path] = "b:" + ("true" if v else "false")
    elif isinstance(v, (int, float)):
        out[path] = "n:%.17g" % float(v)
    elif isinstance(v, str):
        out[path] = "s:" + v
    else:
        out[path] = "!" + type(v).__name__
    return out


def lua_flat(tbl):
    if tbl is None:
        return None
    return {str(k): str(tbl[k]) for k in tbl.keys()}


def compare(a, b):
    """-> (missing in b, different, extra in b) as sorted lists of (path, a value, b value)."""
    missing = sorted((p, a[p], None) for p in a if p not in b)
    different = sorted((p, a[p], b[p]) for p in a if p in b and a[p] != b[p])
    extra = sorted((p, None, b[p]) for p in b if p not in a)
    return missing, different, extra


# ---------------------------------------------------------------------------------------------------
# the one fake DataStore
# ---------------------------------------------------------------------------------------------------
def lock_of(record):
    lock = record.get("Lock") if isinstance(record, dict) else None
    return {"Id": lock.get("Id"), "At": lock.get("At")} if isinstance(lock, dict) else None


class Store:
    def __init__(self):
        self.data = {}
        self.writes = []  # (server label, full key)
        self.bad = []  # shapes a real DataStore could not hold

    def get(self, key):
        return self.data.get(key)

    def put(self, key, value):
        self.data[key] = json.loads(json.dumps(value))

    def snapshot(self):
        return json.loads(json.dumps(self.data))

    def restore(self, snap):
        self.data = json.loads(json.dumps(snap))

    def record(self, uid, name=V2):
        return self.data.get("%s/u_%d" % (name, uid))


# ---------------------------------------------------------------------------------------------------
# one server = one Lua world
# ---------------------------------------------------------------------------------------------------
class Server:
    def __init__(self, env, label, root, clock, server_id=None):
        self.env, self.label, self.alive, self.server_id = env, label, True, server_id
        smoke.ROOT = root
        self.world = smoke.World(env.engine, env.engine_name, "server", env.args, env.api, env.contract)
        self.world.load_scenarios([])  # smoke_common.lua only: the harness baseline (the main menu off)
        rt = self.world.rt
        src = open(os.path.join(HERE, "save_roundtrip.lua"), encoding="utf-8").read()
        g = rt.globals()
        g.RT_SRC = src
        rt.execute("local f, e = (loadstring or load)(RT_SRC, '=tools/save_roundtrip.lua'); if not f then error(e, 0) end; f()")
        self.RT = g.RT
        store = env.store

        def py_get(key):
            value = store.get(str(key))
            return smoke.to_lua(rt, value) if isinstance(value, (dict, list)) else value

        def py_set(key, value):
            key = str(key)
            old = store.data.get(key)
            new = None if value is None else plain(value, store.bad, key)
            store.writes.append({"by": label, "id": self.server_id, "key": key, "before": lock_of(old), "after": lock_of(new),
                                 "at": new.get("UpdatedAt") if isinstance(new, dict) else None, "tokens": new.get("Tokens") if isinstance(new, dict) else None})
            if new is None:
                store.data.pop(key, None)
            else:
                store.data[key] = new

        self._keep = (py_get, py_set)
        self.RT.installStore(py_get, py_set)
        # the branch ships with the Store switch off: test the save code as it ships
        rt.execute("if SmokeCommon and SmokeCommon.StoreShipped ~= nil then local C = RT.shared('Config'); if C and C.Store then C.Store.Enabled = SmokeCommon.StoreShipped end end")
        self.RT.setClock(clock)
        ok = self.RT.boot()
        ok = ok[0] if isinstance(ok, tuple) else ok
        if not ok:
            raise RuntimeError("%s: the server did not boot" % label)
        if server_id:
            self.RT.setServerId(server_id)

    def now(self):
        return float(self.RT.now())

    def advance(self, seconds):
        if seconds > 0:
            self.RT.advance(seconds)

    def join(self, uid, name=None):
        return self.RT.join(uid, name or ("P%d" % uid))

    def leave(self, uid):
        return self.RT.leave(uid)

    def status(self, uid):
        st = self.RT.status(uid)
        return {str(k): num(st[k]) for k in st.keys()}

    def profile(self, uid):
        return lua_flat(self.RT.flatProfile(uid))

    def exec(self, src, uid=None):
        return self.RT["exec"](src, uid)

    def problems(self):
        out = self.RT.problems()
        return [str(out[k]) for k in sorted(out.keys())] if out is not None else []

    def close(self, shutdown=True):
        """shutdown=True: BindToClose runs (every save released). False: the server just dies (a crash)."""
        if self.alive and shutdown:
            self.RT.shutdown(30)
        self.alive = False
        self.RT = None
        self.world = None
        gc.collect()


class Env:
    pass


class Report:
    def __init__(self, verbose):
        self.verbose, self.oks, self.fails, self.rows, self.notes = verbose, 0, 0, [], []

    def section(self, name):
        print("\n== %s ==" % name)

    def check(self, cond, name, detail=""):
        if cond:
            self.oks += 1
            if self.verbose:
                print("  ok    " + name)
        else:
            self.fails += 1
            print("  FAIL  " + name + (("  -- " + detail) if detail else ""))
        self.rows.append({"status": "ok" if cond else "fail", "name": name, "detail": detail})
        return bool(cond)

    def info(self, text):
        print("  ..    " + text)
        self.notes.append(text)


# ---------------------------------------------------------------------------------------------------
# main's code from git
# ---------------------------------------------------------------------------------------------------
def git(*args, cwd=ROOT):
    return subprocess.run(["git"] + list(args), cwd=cwd, check=True, capture_output=True).stdout


def extract_ref(ref):
    """-> (commit id, a temp dir holding that commit's src/ and default.project.json)."""
    commit = git("rev-parse", "--verify", ref + "^{commit}").decode().strip()
    top = git("rev-parse", "--show-toplevel").decode().strip()
    rel = os.path.relpath(ROOT, top).replace("\\", "/")
    prefix = "" if rel == "." else rel + "/"
    blob = git("archive", "--format=tar", commit, prefix + "src", prefix + "default.project.json", cwd=top)
    out = tempfile.mkdtemp(prefix="nimbus_main_")
    with tarfile.open(fileobj=io.BytesIO(blob)) as tar:
        try:
            tar.extractall(out, filter="data")
        except TypeError:  # Python < 3.12
            tar.extractall(out)
    return commit, os.path.join(out, prefix.rstrip("/")) if prefix else out, out


# ---------------------------------------------------------------------------------------------------
# helpers shared by the phases
# ---------------------------------------------------------------------------------------------------
def sync(servers):
    """Brings every live server to the same clock (the furthest one)."""
    live = [s for s in servers if s is not None and s.alive]
    if not live:
        return 0.0
    target = max(s.now() for s in live)
    for s in live:
        s.advance(target - s.now())
    return target


def step_all(servers, seconds, step=0.5, each=None):
    """Advances every live server together, `step` seconds at a time (so their threads interleave)."""
    done = 0.0
    while done < seconds - 1e-9:
        dt = min(step, seconds - done)
        for s in servers:
            if s is not None and s.alive:
                s.advance(dt)
        done += dt
        if each:
            each()


def wait_loaded(server, uid, others=(), seconds=30, real=True):
    """Steps until the player's profile is loaded (real=True: and not provisional). -> seconds waited or None."""
    waited = 0.0
    while waited <= seconds:
        st = server.status(uid)
        if st.get("Loaded") and (not real or not st.get("Provisional")):
            return waited
        step_all([server] + list(others), 0.5)
        waited += 0.5
    return None


def fmt_rows(rows, limit=12):
    out = []
    for path, a, b in rows[:limit]:
        out.append("%s: %s -> %s" % (path or "<root>", a, b))
    if len(rows) > limit:
        out.append("... and %d more" % (len(rows) - limit))
    return " | ".join(out)


USERS = {
    "new": 7101,  # a new player: main's own first save
    "maxed": 7102,  # every field filled, big numbers, every pet
    "nokeys": 7103,  # main's maxed record with whole top-level keys removed by hand
    "noinner": 7104,  # main's maxed record with inner keys removed by hand
    "v1table": 7105,  # a v1 legacy save: { Tokens = n } in the old store
    "v1number": 7106,  # a v1 legacy save: a bare number in the old store
    "fresh": 7107,  # nothing stored at all
}
REMOVED_KEYS = ["Version", "Home", "Stats", "Tutorial", "Discovered", "IndexClaimed", "PetLevels", "Equipped", "Teams", "Battle", "Settings",
                "Dungeon", "Migrations", "Ring", "PetGrowth", "Tiers", "Hybrids", "GemReceipts", "Items", "Berries", "Gems", "Cash", "SpotIndex", "UpdatedAt"]


def key(uid, name=V2):
    return "%s/u_%d" % (name, uid)


def phase_build(env, rep):
    """MAIN's own save code writes the fixtures."""
    rep.section("build: MAIN's own save code writes the fake saves (commit %s)" % env.commit[:12])
    store = env.store
    m = Server(env, "main-build", env.main_root, env.clock)
    boot_problems = m.problems()
    rep.check(True, "build: MAIN's server boots in the mock from git")
    # a new player: joins, earns a little, leaves
    u = USERS["new"]
    m.join(u)
    rep.check(wait_loaded(m, u) is not None, "build new: main loads a player with nothing stored")
    m.advance(20)
    m.exec("local c = ...; c.DS.AddTokens(c.player, 40)", u)
    m.advance(1)
    m.leave(u)
    m.advance(5)
    rep.check(isinstance(store.record(u), dict), "build new: main stored the new player's save")
    # the maxed player: a rich raw record -> main LOADS it -> main SAVES it (the fixture is what main wrote)
    u = USERS["maxed"]
    seed = m.RT.maxedSeed()
    seed_rec = plain(seed[0] if isinstance(seed, tuple) else seed)
    pets = int(seed[1]) if isinstance(seed, tuple) else 0
    store.put(key(u), seed_rec)
    env.seed = seed_rec
    m.join(u)
    rep.check(wait_loaded(m, u) is not None, "build maxed: main loads the rich record")
    m.exec("local c = ...; c.DS.AddTokens(c.player, 1); c.DS.AddCash(c.player, 1)", u)
    m.advance(2)
    m.leave(u)
    m.advance(5)
    rec = store.record(u)
    rep.check(isinstance(rec, dict) and "UpdatedAt" in rec, "build maxed: main wrote the record back (its own toStored)")
    rep.check(isinstance(rec, dict) and len(rec.get("Pets", {})) == pets and pets >= 20, "build maxed: every catalog pet is in main's record",
              "%d pets in the record, %d in main's catalog" % (len((rec or {}).get("Pets", {})), pets))
    want = ["Tokens", "Cash", "Gems", "Pets", "Tiers", "Hybrids", "PetLevels", "Discovered", "IndexClaimed", "Tutorial", "Home", "Stats", "Teams", "Battle",
            "PetGrowth", "Ring", "Migrations", "Dungeon", "Berries", "Settings", "GemReceipts", "Equipped"]
    absent = [k for k in want if k not in (rec or {})]
    rep.check(not absent, "build maxed: main's record holds every field of the save", "absent: " + ", ".join(absent))
    rep.info("maxed record: %d stored values, Tokens %s, Cash %s, Gems %s, %d pets, %d hybrids, %d receipts" % (
        len(flat(rec)), rec.get("Tokens"), rec.get("Cash"), rec.get("Gems"), len(rec.get("Pets", {})), len(rec.get("Hybrids", {})), len(rec.get("GemReceipts", {}))))
    # missing fields, by hand, from main's own maxed record
    stripped = json.loads(json.dumps(rec))
    for k in REMOVED_KEYS:
        stripped.pop(k, None)
    store.put(key(USERS["nokeys"]), stripped)
    inner = json.loads(json.dumps(rec))
    inner["Home"] = {"Level": inner["Home"].get("Level", 1)}
    inner["Stats"] = {"Matches": inner["Stats"].get("Matches", 0)}
    inner["Tutorial"] = {}
    inner["Battle"] = {"Trophies": inner.get("Battle", {}).get("Trophies", 0)}
    inner["Teams"] = {"Active": 2}
    inner["Dungeon"] = {"Best": inner.get("Dungeon", {}).get("Best", 0)}
    inner["Settings"] = {"Music": 3}
    inner["Ring"] = {"Best": 5}
    for k in list(inner.get("PetLevels", {}))[::2]:
        inner["PetLevels"][k] = {"Level": inner["PetLevels"][k].get("Level", 1)}
    for k in list(inner.get("PetGrowth", {}))[::2]:
        inner["PetGrowth"][k] = {"Evo": inner["PetGrowth"][k].get("Evo", 0)}
    for k in list(inner.get("Hybrids", {}))[::2]:
        inner["Hybrids"][k].pop("Name", None)
        inner["Hybrids"][k].pop("Tier", None)
    store.put(key(USERS["noinner"]), inner)
    # v1 legacy saves (the old store; main's code only ever reads these)
    store.put(key(USERS["v1table"], V1), {"Tokens": 4321})
    store.data[key(USERS["v1number"], V1)] = 777
    problems = m.problems()
    rep.check(not [p for p in problems if p.startswith("error")], "build: main raised no script error while it wrote the saves", " | ".join(problems[:4]))
    rep.check(not store.bad, "build: every value main stored is one a real DataStore can hold", " | ".join(store.bad[:3]))
    env.clock = m.now()
    m.close()
    env.fixture = store.snapshot()
    env.boot_warnings = boot_problems
    names = ", ".join("%s=%d" % (n, USERS[n]) for n in USERS)
    rep.info("fixture users: " + names)


# Differences between MAIN's reading of a save and this branch's reading that are allowed, each with its reason.
# (path prefix, kind, reason[, test(main value, branch value)]). kind: "extra" = only this branch has the field;
# "diff" = both have it, the value differs; "missing" = main has it, this branch does not. Anything else FAILS the run.
def close_stamps(a, b):
    try:
        return abs(float(a[2:]) - float(b[2:])) <= 120
    except (TypeError, ValueError):
        return False


NEW_FIELD = "a new field of this branch at its default (main never had it; nothing of main's is replaced)"
ALLOWED_PROFILE = [
    (".Store", "extra", NEW_FIELD),
    (".Daily", "extra", NEW_FIELD),
    (".Trove", "extra", NEW_FIELD),
    (".Pity", "extra", NEW_FIELD),
    (".Battle.Duels", "extra", NEW_FIELD),
    (".Battle.RaidRewardAt", "extra", NEW_FIELD),
    (".Battle.RaidLossAt", "extra", NEW_FIELD),
    (".Settings.FastHatch", "extra", NEW_FIELD),
    (".Home.LastSeen", "diff", "a clock stamp, not saved data: the save has no LastSeen, so each version writes the time of its own load (seconds apart)", close_stamps),
]
META = "record metadata, not player data"
ALLOWED_RECORD = [
    (".UpdatedAt", "diff", META + ": the time of the last write", None),
    (".UpdatedAt", "extra", META + ": the time of the last write", None),
    (".WriteId", "extra", META + ": the session lock's nonce of the last write", None),
    (".WriteId", "diff", META + ": the session lock's nonce of the last write", None),
    (".Home.LastSeen", "diff", "a clock stamp: each version stamped the time of its own session (seconds apart)", close_stamps),
]


def allowed(table, path, kind, a=None, b=None):
    for row in table:
        prefix, k, reason = row[0], row[1], row[2]
        test = row[3] if len(row) > 3 else None
        if k == kind and (path == prefix or path.startswith(prefix + ".") or path.startswith(prefix + "[")):
            if test is None or test(a, b):
                return reason
    return None


def judge(rep, env, label, rows_by_kind, table):
    """Sorts every difference into allowed (with its reason) or not allowed (a failure)."""
    bad = []
    for kind, rows in rows_by_kind.items():
        for path, a, b in rows:
            reason = allowed(table, path, kind, a, b)
            env.differences.append({"where": label, "kind": kind, "path": path, "main": a, "branch": b, "allowed": reason})
            if reason is None:
                bad.append((kind + " " + path, a, b))
    return bad


def errors_of(problems):
    return [p for p in problems if p.startswith("error")]


def phase_load(env, rep):
    """(a) each save loads in this branch with nothing lost."""
    store = env.store
    start = env.clock
    rep.section("load (a): MAIN's own reading of each save, then MAIN's own next save of it")
    store.restore(env.fixture)
    m = Server(env, "main-read", env.main_root, start)
    main_view, main_after = {}, {}
    for name, u in USERS.items():
        m.join(u)
        rep.check(wait_loaded(m, u) is not None, "main reads '%s'" % name)
        main_view[name] = m.profile(u) or {}
    for name, u in USERS.items():
        m.exec("local c = ...; c.DS.AddTokens(c.player, 1)", u)
    m.advance(3)
    for name, u in USERS.items():
        m.leave(u)
    m.advance(8)
    for name, u in USERS.items():
        main_after[name] = store.record(u)
    main_v1 = {k: v for k, v in store.data.items() if k.startswith(V1 + "/")}
    rep.check(not errors_of(m.problems()), "main reads and saves its own saves without a script error")
    env.main_view = main_view
    m.close()

    rep.section("load (a): this branch reads the same saves")
    store.restore(env.fixture)
    q = Server(env, "branch-A", env.branch_root, start, "srv-A")
    env.branch_view = {}
    for name, u in USERS.items():
        q.join(u)
        waited = wait_loaded(q, u)
        st = q.status(u)
        rep.check(waited is not None and st.get("Owns") and not st.get("Provisional"), "branch loads '%s' as a real, owned save" % name, json.dumps(st))
        view = q.profile(u) or {}
        env.branch_view[name] = view
        missing, different, extra = compare(main_view[name], view)
        bad = judge(rep, env, "profile " + name, {"missing": missing, "diff": different, "extra": extra}, ALLOWED_PROFILE)
        rep.check(not bad, "branch '%s': every field main read is there with the same value (%d fields compared)" % (name, len(main_view[name])), fmt_rows(bad))
    problems = q.problems()
    rep.check(not errors_of(problems), "branch loads main's saves without a script error", " | ".join(problems[:4]))
    warns = [p for p in problems if p.startswith("warn") and "DataService" in p]
    rep.check(not warns, "branch loads main's saves without a DataService warning", " | ".join(warns[:4]))

    # an idle session of this branch: the saves main itself wrote must come back value for value
    step_all([q], 5)
    for name, u in USERS.items():
        q.leave(u)
    step_all([q], 8)
    for name in ("new", "maxed"):
        u = USERS[name]
        before, after = env.fixture.get(key(u)), store.record(u)
        rep.check(isinstance(after, dict) and "Lock" not in after, "branch '%s': the leave released the lock (no Lock in the record)" % name, json.dumps((after or {}).get("Lock")))
        missing, different, extra = compare(flat(before), flat(after or {}))
        bad = judge(rep, env, "record-idle " + name, {"missing": missing, "diff": different, "extra": extra}, ALLOWED_RECORD)
        rep.check(not bad, "branch '%s': after an idle session the stored record holds every value main stored, unchanged (%d values)" % (name, len(flat(before))), fmt_rows(bad))

    # a rejoin on the same server, one token earned, then the record against what MAIN wrote after the same session
    for name, u in USERS.items():
        q.join(u)
        waited = wait_loaded(q, u)
        st = q.status(u)
        rep.check(waited is not None and st.get("Owns") and not st.get("Provisional"), "branch rejoin '%s': a real, owned save again" % name, json.dumps(st))
    for name, u in USERS.items():
        q.exec("local c = ...; c.DS.AddTokens(c.player, 1)", u)
    step_all([q], 3)
    for name, u in USERS.items():
        q.leave(u)
    step_all([q], 8)
    for name, u in USERS.items():
        a, b = main_after[name], store.record(u)
        rep.check(isinstance(a, dict) and isinstance(b, dict), "'%s': main and the branch both stored a v2 record after the session" % name)
        if not (isinstance(a, dict) and isinstance(b, dict)):
            continue
        rep.check("Lock" not in b, "branch '%s': released (no Lock in the record)" % name)
        missing, different, extra = compare(flat(a), flat(b))
        bad = judge(rep, env, "record " + name, {"missing": missing, "diff": different, "extra": extra}, ALLOWED_RECORD)
        rep.check(not bad, "'%s': the record this branch stores equals the record MAIN stores after the same session (%d values)" % (name, len(flat(a))), fmt_rows(bad))
    branch_v1 = {k: v for k, v in store.data.items() if k.startswith(V1 + "/")}
    rep.check(main_v1 == branch_v1, "the v1 legacy store is left exactly as main leaves it", "main %s / branch %s" % (json.dumps(main_v1), json.dumps(branch_v1)))
    rep.check(not errors_of(q.problems()), "branch sessions on main's saves raise no script error")
    rep.check(not store.bad, "load: every value this branch stored is one a real DataStore can hold", " | ".join(store.bad[:3]))
    env.after_branch = store.snapshot()
    env.clock = q.now()
    q.close()


# What a session of THIS BRANCH writes before the rollback: progress on main's own fields, and every new field of the
# branch through the branch's own DataService API (the Store ledger, a potion, the daily streak, the Trove, the Secret
# pity, a duel note, the raid clocks, Fast hatch).
PROGRESS = """
local c = ...
local D, p = c.DS, c.player
local out = {}
out.Tokens = D.AddTokens(p, 111) ~= false
out.Cash = D.AddCash(p, 222) ~= false
out.Gems = D.AddGems(p, 333) ~= false
out.Bought = D.MarkBought(p, "Starter")
out.Boost = D.AddBoost(p, "XpPotion", 3600)
out.Pass = D.MarkPassSeen(p, "VIP")
out.Trove = D.MarkTrove(p, "Group", { Cash = 0, Tokens = 0 })
out.Daily = D.MutateDaily(p, function(d)
	d.Streak = 4
	d.Paid = 4
	d.LastClaimAt = os.time() - 100
end, os.time())
out.Pity = D.SetPity(p, 5, 2)
out.Duel = D.RecordDuel(p, 4242, os.time())
out.Fast = D.SetSetting(p, "FastHatch", true)
out.Raid = D.MutateBattle(p, function(b)
	b.RaidRewardAt = os.time()
	b.RaidLossAt = os.time() - 50
end)
local prof = D.GetProfile(p)
for uid, h in pairs(prof.Hybrids or {}) do
	h.SpecialFrom = "Style"
	out.Hybrid = uid
	break
end
D.MarkDirty(p)
return out
"""
PROGRESS_KEYS = ["Tokens", "Cash", "Gems", "Bought", "Boost", "Pass", "Trove", "Daily", "Pity", "Duel", "Fast", "Raid"]
CRASHED = ("new", "noinner")  # these two never get a release: their server dies after an autosave (the Lock stays stored)
FOREIGN = ["Store", "Daily", "Trove", "Pity"]  # this branch's top-level keys: main does not know them

# What MAIN does not carry through a save of its own after a rollback: fields this branch added INSIDE tables main
# rebuilds from the keys it knows. Listed with the cost; anything else main drops FAILS the run.
def not_less(a, b):
    """main value / branch value, or before / after: the later one is never smaller."""
    try:
        return float(b[2:]) >= float(a[2:])
    except (TypeError, ValueError):
        return False


def not_more(a, b):
    return not_less(b, a)


INCOME = "home income the next session paid when the player came back (never less than before)"
STAMP = "a clock stamp: every session writes the time it saw the player"
# What a ROLLBACK COSTS a player: this branch's memory before the rollback against this branch's reading after MAIN
# played and saved the save. Fields this branch added INSIDE tables that main rebuilds from the keys it knows are reset
# by main's save. Anything else that changes FAILS the run.
ROLLBACK_COST = [
    (".Battle.RaidRewardAt", "diff", "ROLLBACK COST: a raid reward clock restarts (one raid reward may come sooner than its cooldown)"),
    (".Battle.RaidLossAt", "diff", "ROLLBACK COST: a raid loss clock restarts"),
    (".Battle.Duels", "missing", "ROLLBACK COST: the recent-duels notes are forgotten (a duel reward window of the last opponents restarts)"),
    (".Battle.Duels", "extra", "ROLLBACK COST: the recent-duels notes are forgotten (the list is empty again)"),
    (".Settings.FastHatch", "diff", "ROLLBACK COST: the Fast hatch setting goes back to off"),
    (".Tokens", "diff", "main's own session earned 5 Tokens (checked exactly above)"),
    (".Stats.TokensEarned", "diff", "main's own session earned 5 Tokens"),
    (".Home.LastSeen", "diff", STAMP),
    (".Berries", "diff", INCOME, not_less),
    (".Home.CollectorCash", "diff", INCOME, not_less),
    (".Daily.PlayStart", "diff", "the play-time clock of the new session", None),
    (".Daily.PlaySec", "diff", "the play-time clock of the new session", None),
]
# main's reading of a save this branch wrote, against what this branch had in memory (main value, branch value)
BRANCH_ONLY = "a field only this branch has: main does not read it (and carries the top-level ones through its saves untouched)"
ALLOWED_ROLLBACK_PROFILE = [(row[0], row[1], BRANCH_ONLY) + tuple(row[3:]) if row[1] == "extra" else row for row in ALLOWED_PROFILE] + [
    (".Hybrids", "extra", "a field only this branch has, inside a hybrid (SpecialFrom: which parent gives the special); main carries it"),
    (".Home.LastSeen", "diff", STAMP),
    (".Berries", "diff", INCOME, not_more),
    (".Home.CollectorCash", "diff", INCOME, not_more),
]


def phase_rollback(env, rep):
    """(b) a save this branch wrote is read by MAIN's code without error and without losing main's fields."""
    store = env.store
    rep.section("rollback (b): this branch plays on main's saves and writes them (lock fields, new fields, progress)")
    store.restore(env.fixture)
    q = Server(env, "branch-B", env.branch_root, env.clock, "srv-B")
    for name, u in USERS.items():
        q.join(u)
        rep.check(wait_loaded(q, u) is not None, "branch loads '%s'" % name)
    before = {name: q.profile(u) or {} for name, u in USERS.items()}
    for name, u in USERS.items():
        out = q.exec(PROGRESS, u)
        failed = [k for k in PROGRESS_KEYS if not out[k]]
        rep.check(not failed, "branch '%s': progress and every new field written through the branch's own API" % name, "refused: " + ", ".join(failed))
    step_all([q], 3)
    final = {name: q.profile(u) or {} for name, u in USERS.items()}
    for name, u in USERS.items():
        if name not in CRASHED:
            q.leave(u)
    step_all([q], 8)
    # the two that stay: wait for an autosave to carry their progress, then the server dies (no release)
    waited = 0
    while waited < 400:
        recs = [store.record(USERS[n]) for n in CRASHED]
        if all(isinstance(r, dict) and r.get("Tokens") == num(float(final[n][".Tokens"][2:])) and "Lock" in r for r, n in zip(recs, CRASHED)):
            break
        step_all([q], 10)
        waited += 10
    for name in CRASHED:
        r = store.record(USERS[name]) or {}
        rep.check(r.get("Tokens") == num(float(final[name][".Tokens"][2:])) and isinstance(r.get("Lock"), dict) and r["Lock"].get("Id") == "srv-B",
                  "branch '%s': an autosave stored the progress with this server's lock (then the server dies)" % name, "after %d s: Tokens %s, Lock %s" % (waited, r.get("Tokens"), json.dumps(r.get("Lock"))))
    rep.check(not errors_of(q.problems()), "branch: no script error while it wrote the saves")
    clock = q.now()
    q.close(shutdown=False)
    written = store.snapshot()
    for name, u in USERS.items():
        r = store.record(u) or {}
        if name not in CRASHED:
            rep.check("Lock" not in r, "branch '%s': a clean leave stored no Lock" % name)
        absent = [k for k in FOREIGN if k not in r]
        rep.check(not absent, "branch '%s': the record holds the branch's new fields (Store, Daily, Trove, Pity)" % name, "absent: " + ", ".join(absent))
    rep.check(not store.bad, "rollback: every value this branch stored is one a real DataStore can hold", " | ".join(store.bad[:3]))

    rep.section("rollback (b): MAIN's code reads what this branch wrote (commit %s)" % env.commit[:12])
    m = Server(env, "main-rollback", env.main_root, clock)
    main2 = {}
    for name, u in USERS.items():
        m.join(u)
        waited = wait_loaded(m, u)
        st = m.status(u)
        rep.check(waited is not None and waited <= 5 and not st.get("Provisional"), "main loads '%s' at once, as a real save%s" % (name, " (a stored Lock does not hold main up)" if name in CRASHED else ""),
                  "waited %s, %s" % (waited, json.dumps(st)))
        main2[name] = m.profile(u) or {}
    problems = m.problems()
    rep.check(not errors_of(problems), "main reads the branch's saves without a script error", " | ".join(problems[:4]))
    warns = [x for x in problems if x.startswith("warn") and "DataService" in x]
    rep.check(not warns, "main reads the branch's saves without a DataService warning", " | ".join(warns[:4]))
    for name, u in USERS.items():
        # 1. main reads exactly what the branch had, for every field main has
        missing, different, extra = compare(main2[name], final[name])
        bad = judge(rep, env, "rollback-read " + name, {"missing": missing, "diff": different, "extra": extra}, ALLOWED_ROLLBACK_PROFILE)
        rep.check(not bad, "main '%s': every field main reads has the value this branch had (%d fields)" % (name, len(main2[name])), fmt_rows(bad))
        # 2. nothing of main's was lost on the way: main's first reading + the progress = main's reading now
        base, now_ = env.main_view[name], main2[name]
        gone = sorted(p for p in base if p not in now_ and not p.startswith(".Equipped") and not p.startswith(".Teams"))
        rep.check(not gone, "main '%s': no field main read before the branch touched the save is gone" % name, ", ".join(gone[:8]))
        for field, add in ((".Tokens", 111), (".Cash", 222), (".Gems", 333)):
            a, b = float(base[field][2:]), float(now_[field][2:])
            rep.check(b == a + add, "main '%s': %s = what it was + %d earned on the branch" % (name, field[1:], add), "%.17g -> %.17g" % (a, b))
        a, b = float(base[".Stats.TokensEarned"][2:]), float(now_[".Stats.TokensEarned"][2:])
        rep.check(b == a + 111, "main '%s': Stats.TokensEarned = what it was + 111" % name, "%.17g -> %.17g" % (a, b))
        for field in (".Berries", ".Home.CollectorCash"):
            rep.check(not_less(base.get(field, "n:0"), now_.get(field, "n:0")), "main '%s': %s is not less than before (home income only adds)" % (name, field[1:]),
                      "%s -> %s" % (base.get(field), now_.get(field)))
        skip = {".Tokens", ".Cash", ".Gems", ".Stats.TokensEarned", ".Home.LastSeen", ".Home.CollectorCash", ".Berries"}
        changed = sorted((p, base[p], now_[p]) for p in base if p in now_ and base[p] != now_[p] and p not in skip)
        rep.check(not changed, "main '%s': every other field main read before is unchanged" % name, fmt_rows(changed))
    # main plays and saves: the branch's top-level fields must ride through untouched
    for name, u in USERS.items():
        m.exec("local c = ...; c.DS.AddTokens(c.player, 5)", u)
    m.advance(3)
    for name, u in USERS.items():
        m.leave(u)
    m.advance(8)
    rep.check(not errors_of(m.problems()), "main saves the branch's saves without a script error")
    for name, u in USERS.items():
        a, b = written.get(key(u)) or {}, store.record(u) or {}
        same = [k for k in FOREIGN if a.get(k) == b.get(k) and k in b]
        rep.check(len(same) == len(FOREIGN), "main '%s': its save writes Store, Daily, Trove and Pity back untouched" % name, "kept: " + ", ".join(same))
        rep.check(b.get("Tokens") == a.get("Tokens", 0) + 5, "main '%s': its own progress is stored on top (+5 Tokens)" % name, "%s -> %s" % (a.get("Tokens"), b.get("Tokens")))
        if name in CRASHED:
            rep.check(b.get("Lock") == a.get("Lock"), "main '%s': the dead server's Lock is carried as it was (main neither reads nor refreshes it)" % name,
                      "%s -> %s" % (json.dumps(a.get("Lock")), json.dumps(b.get("Lock"))))
    clock = m.now()
    m.close()
    after_main = store.snapshot()

    rep.section("roll forward: this branch reads what main wrote after the rollback (10 minutes later)")
    q2 = Server(env, "branch-C", env.branch_root, clock + 600, "srv-C")
    for name, u in USERS.items():
        q2.join(u)
        waited = wait_loaded(q2, u)
        st = q2.status(u)
        rep.check(waited is not None and waited <= 5 and st.get("Owns") and not st.get("Provisional"), "branch loads '%s' again as a real, owned save%s" % (
            name, " (the dead server's lock is stale)" if name in CRASHED else ""), "waited %s, %s" % (waited, json.dumps(st)))
        view = q2.profile(u) or {}
        want = {
            ".Store.Bought.Starter": final[name].get(".Store.Bought.Starter"),
            ".Store.Passes.VIP": final[name].get(".Store.Passes.VIP"),
            ".Store.Boosts.XpPotion": final[name].get(".Store.Boosts.XpPotion"),
            ".Daily.Streak": "n:4", ".Daily.Paid": "n:4", ".Pity.Secret.Spins": "n:5", ".Pity.Secret.Hit": "n:2", ".Trove.Group": "b:true",
        }
        wrong = ["%s: %s (want %s)" % (p_, view.get(p_), v) for p_, v in want.items() if v is None or view.get(p_) != v]
        rep.check(not wrong, "branch '%s': the Store ledger, the potion, the streak, the pity and the Trove are all still there" % name, " | ".join(wrong))
        t = float(final[name][".Tokens"][2:]) + 5
        rep.check(view.get(".Tokens") == "n:%.17g" % t, "branch '%s': Tokens = the branch's + main's 5" % name, "%s (want %.17g)" % (view.get(".Tokens"), t))
        # the whole cost of the rollback for this player: the branch's memory before it against its reading now
        missing, different, extra = compare(final[name], view)
        bad = judge(rep, env, "rollback-cost " + name, {"missing": missing, "diff": different, "extra": extra}, ROLLBACK_COST)
        rep.check(not bad, "branch '%s': main's session changed nothing but the listed rollback costs (%d fields compared)" % (name, len(final[name])), fmt_rows(bad))
    rep.check(not errors_of(q2.problems()), "branch reads main's rollback saves without a script error")
    env.clock = q2.now()
    q2.close()
    env.rollback_before = before


# (b2) players with no v2 record: a v1 legacy save (a table, a bare number) or nothing at all. (uid, v1 value, Tokens)
FIRST_SAVE = {"v1table": (7111, {"Tokens": 5555}, 5555), "v1number": (7112, 888, 888), "nothing": (7113, None, 0)}
FIRST_SAVE_BRANCH = {"v1table": (7114, {"Tokens": 5555}, 5555), "v1number": (7115, 888, 888)}


def phase_crash(env, rep):
    """(b2) a branch server dies before a player's FIRST full save; the next server is main (then the branch again)."""
    store = env.store
    rep.section("crash (b2): a branch server dies before the first full save; the next server is MAIN")
    store.restore(env.fixture)
    for name, (u, v1, _) in list(FIRST_SAVE.items()) + list(FIRST_SAVE_BRANCH.items()):
        store.data.pop(key(u), None)
        if v1 is not None:
            store.data[key(u, V1)] = json.loads(json.dumps(v1))
    v1_before = {k: json.dumps(v, sort_keys=True) for k, v in store.data.items() if k.startswith(V1 + "/")}
    q = Server(env, "branch-D", env.branch_root, env.clock, "srv-D")
    for group in (FIRST_SAVE, FIRST_SAVE_BRANCH):
        for name, (u, v1, tokens) in group.items():
            q.join(u)
            rep.check(wait_loaded(q, u) is not None, "crash '%s' (%d): the branch loads the player" % (name, u))
            st = q.status(u)
            rep.check(st.get("Tokens") == tokens and st.get("Owns"), "crash '%s' (%d): the branch plays with the v1 Tokens (%d) on a save it owns" % (name, u, tokens), json.dumps(st))
    step_all([q], 5)  # well inside the first autosave interval: no full save has been written yet
    for group in (FIRST_SAVE, FIRST_SAVE_BRANCH):
        for name, (u, v1, tokens) in group.items():
            r = store.record(u)
            rep.check(isinstance(r, dict) and (r.get("Lock") or {}).get("Id") == "srv-D" and "Version" not in r,
                      "crash '%s' (%d): 5 s in, the record is the claim's (this server's lock, no full save yet)" % (name, u), json.dumps(r))
            rep.info("crash '%s' (%d): the record the dead server leaves: %s" % (name, u, json.dumps({k: (v if k != "Lock" else "{...}") for k, v in (r or {}).items()}, sort_keys=True)))
    rep.check(not errors_of(q.problems()), "crash: the branch raised no script error")
    clock = q.now()
    q.close(shutdown=False)  # the server dies: no release, no save
    rep.check(not store.bad, "crash: every value the branch stored is one a real DataStore can hold", " | ".join(store.bad[:3]))

    m = Server(env, "main-after-crash", env.main_root, clock + 30)
    for name, (u, v1, tokens) in FIRST_SAVE.items():
        m.join(u)
        waited = wait_loaded(m, u)
        st = m.status(u)
        rep.check(waited is not None and waited <= 5 and not st.get("Provisional"), "crash '%s': main loads the player at once, as a real save" % name, "waited %s, %s" % (waited, json.dumps(st)))
        rep.check(st.get("Tokens") == tokens, "crash '%s': MAIN has the player's %d v1 Tokens (its v1 migration is not skipped, or the record carries them)" % (name, tokens),
                  "main Tokens %s (want %d)" % (st.get("Tokens"), tokens))
    problems = m.problems()
    rep.check(not errors_of(problems), "crash: main reads those records without a script error", " | ".join(problems[:4]))
    warns = [x for x in problems if x.startswith("warn") and "DataService" in x]
    rep.check(not warns, "crash: main reads those records without a DataService warning", " | ".join(warns[:4]))
    for name, (u, v1, tokens) in FIRST_SAVE.items():
        m.exec("local c = ...; c.DS.AddTokens(c.player, 5)", u)
    m.advance(3)
    for name, (u, v1, tokens) in FIRST_SAVE.items():
        m.leave(u)
    m.advance(8)
    for name, (u, v1, tokens) in FIRST_SAVE.items():
        r = store.record(u) or {}
        rep.check(r.get("Tokens") == tokens + 5 and r.get("Version") == 2, "crash '%s': main's save stores %d + 5 Tokens (Version 2)" % (name, tokens), "Tokens %s, Version %s" % (r.get("Tokens"), r.get("Version")))
    rep.check(not errors_of(m.problems()), "crash: main saves without a script error")
    clock = m.now()
    m.close()

    rep.section("crash (b2): this branch reads again (10 minutes later): after main, and straight after the crash")
    q2 = Server(env, "branch-E", env.branch_root, clock + 600, "srv-E")
    for name, (u, v1, tokens) in FIRST_SAVE.items():
        q2.join(u)
        waited = wait_loaded(q2, u)
        st = q2.status(u)
        rep.check(waited is not None and waited <= 5 and st.get("Owns") and st.get("Tokens") == tokens + 5,
                  "crash '%s': the branch loads main's save as a real, owned save with %d + 5 Tokens (not doubled)" % (name, tokens), "waited %s, %s" % (waited, json.dumps(st)))
    # the next server after the crash is this branch again: the dead server's lock is stale, the v1 Tokens count once
    for name, (u, v1, tokens) in FIRST_SAVE_BRANCH.items():
        q2.join(u)
        waited = wait_loaded(q2, u)
        st = q2.status(u)
        rep.check(waited is not None and waited <= 5 and st.get("Owns") and st.get("Tokens") == tokens,
                  "crash '%s' (branch next): the branch loads the dead server's record with the %d v1 Tokens, once" % (name, tokens), "waited %s, %s" % (waited, json.dumps(st)))
        give(q2, u, 7)
    step_all([q2], 3)
    for group in (FIRST_SAVE, FIRST_SAVE_BRANCH):
        for name, (u, v1, tokens) in group.items():
            q2.leave(u)
    step_all([q2], 8)
    for name, (u, v1, tokens) in FIRST_SAVE_BRANCH.items():
        r = store.record(u) or {}
        rep.check(r.get("Tokens") == tokens + 7 and "Lock" not in r, "crash '%s' (branch next): the final record holds %d + 7 Tokens and no lock" % (name, tokens), "Tokens %s, Lock %s" % (r.get("Tokens"), json.dumps(r.get("Lock"))))
    v1_after = {k: json.dumps(v, sort_keys=True) for k, v in store.data.items() if k.startswith(V1 + "/")}
    rep.check(v1_before == v1_after, "crash: the v1 legacy store is never written (by either build)")
    rep.check(not errors_of(q2.problems()), "crash: the branch reads and saves without a script error")
    rep.check(not store.bad, "crash: every value stored is one a real DataStore can hold", " | ".join(store.bad[:3]))
    env.clock = q2.now()
    q2.close()


LOCK_SECONDS = 360  # Config.Save.LockSeconds: a lock this old is stale
CLAIM_WAIT = 12  # Config.Save.ClaimWaitSeconds: a load waits this long for a live lock, then plays on a stand-in


def give(server, uid, n):
    server.exec("local c = ...; c.DS.AddTokens(c.player, %d)" % n, uid)


def latency(server, seconds):
    server.exec("local c = ...; c.Mock.DataStore.Latency = %s" % seconds)


class Watch:
    """Samples every step: how many servers hold the player's REAL, owned profile at once (never more than one)."""

    def __init__(self, servers, uid):
        self.servers, self.uid, self.most, self.provisional = servers, uid, 0, {}

    def __call__(self):
        owners = 0
        for sv in self.servers:
            if sv is None or not sv.alive:
                continue
            st = sv.status(self.uid)
            if st.get("Here") and st.get("Loaded") and st.get("Owns") and not st.get("Provisional"):
                owners += 1
            if st.get("Provisional"):
                self.provisional[sv.label] = True
        self.most = max(self.most, owners)


def foreign_writes(store, k, since=0):
    """Writes of a branch server into a record that held ANOTHER server's live lock (there must be none)."""
    out = []
    for w in store.writes[since:]:
        if w["key"] != k or not w["id"]:
            continue
        b = w["before"]
        # the time of this write: its own lock stamp (a claim only adds the Lock: UpdatedAt stays the old write's), else UpdatedAt
        when = max((w["after"] or {}).get("At") or 0, w.get("at") or 0)
        if b and b.get("Id") and b["Id"] != w["id"] and when and b.get("At") is not None and when - b["At"] < LOCK_SECONDS:
            out.append("%s wrote over %s's %d s old lock" % (w["by"], b["Id"], when - b["At"]))
    return out


def phase_lock(env, rep):
    """(c) the session lock, on saves main wrote: two servers, rejoin, server hop, crash; and a mixed fleet."""
    store = env.store
    store.restore(env.fixture)
    maxed = env.fixture[key(USERS["maxed"])]
    uids = {"two": 7201, "rejoin": 7202, "hop": 7203, "crash": 7204, "rollout": 7205, "rollback": 7206}
    for u in uids.values():
        store.put(key(u), maxed)
    base = maxed["Tokens"]
    rep.section("lock (c): two servers of this branch on one save main wrote")
    a = Server(env, "branch-QA", env.branch_root, env.clock, "srv-A")
    b = Server(env, "branch-QB", env.branch_root, env.clock, "srv-B")
    sync([a, b])
    both = [a, b]

    # -- two servers at once ------------------------------------------------------------------------
    u, k = uids["two"], key(uids["two"])
    mark = len(store.writes)
    watch = Watch(both, u)
    a.join(u)
    rep.check(wait_loaded(a, u, [b]) is not None and a.status(u).get("Owns"), "two servers: server A loads the save and owns it")
    rep.check((store.record(u).get("Lock") or {}).get("Id") == "srv-A", "two servers: the record holds A's lock")
    b.join(u)
    step_all(both, 6, each=watch)
    st = b.status(u)
    rep.check(not st.get("Loaded") and st.get("Waiting"), "two servers: 6 s in, server B is still waiting for the lock (not loaded, SaveWaiting)", json.dumps(st))
    step_all(both, CLAIM_WAIT - 6 + 3, each=watch)
    st = b.status(u)
    rep.check(st.get("Loaded") and st.get("Provisional") and not st.get("Owns"), "two servers: after the wait B plays on a stand-in (provisional, does not own the save)", json.dumps(st))
    rep.check((store.record(u).get("Lock") or {}).get("Id") == "srv-A" and store.record(u).get("Tokens") == base, "two servers: the stored save is untouched and still A's")
    wrote_b = [w for w in store.writes[mark:] if w["key"] == k and w["by"] == b.label]
    rep.check(not wrote_b, "two servers: B has written nothing into the save", "%d writes" % len(wrote_b))
    give(a, u, 100)
    give(b, u, 3)  # earned on the stand-in
    step_all(both, 2, each=watch)
    a.leave(u)
    step_all(both, 4, each=watch)
    rec = store.record(u)
    rep.check(rec.get("Tokens") == base + 100, "two servers: A's leave stored its 100 Tokens", "%s (want %d)" % (rec.get("Tokens"), base + 100))
    waited = 0
    while waited < 60 and not (b.status(u).get("Owns") and not b.status(u).get("Provisional")):
        step_all(both, 1, each=watch)
        waited += 1
    st = b.status(u)
    rep.check(st.get("Owns") and not st.get("Provisional"), "two servers: B takes the save over once A released it (%d s later)" % waited, json.dumps(st))
    got = st.get("Tokens")
    rep.check(got == base + 100 + 3, "two servers: B now has the real save: A's 100 Tokens and the 3 earned on the stand-in, nothing lost, nothing twice", "%s (want %d)" % (got, base + 103))
    b.leave(u)
    step_all(both, 6, each=watch)
    rec = store.record(u)
    rep.check(rec.get("Tokens") == base + 103 and "Lock" not in rec, "two servers: the final record holds every Token and no lock", "%s, Lock %s" % (rec.get("Tokens"), json.dumps(rec.get("Lock"))))
    rep.check(watch.most <= 1, "two servers: never two owners of the save at once", "most at once: %d" % watch.most)
    fw = foreign_writes(store, k, mark)
    rep.check(not fw, "two servers: no write ever landed over another server's live lock", " | ".join(fw[:3]))

    # -- rejoin on the same server --------------------------------------------------------------------
    u, k = uids["rejoin"], key(uids["rejoin"])
    watch = Watch(both, u)
    a.join(u)
    rep.check(wait_loaded(a, u, [b]) is not None, "rejoin: the save loads")
    give(a, u, 10)
    step_all(both, 1, each=watch)
    a.leave(u)
    a.join(u)  # back before the leave's save can have landed
    waited = wait_loaded(a, u, [b], 20)
    st = a.status(u)
    rep.check(waited is not None and st.get("Owns") and st.get("Tokens") == base + 10, "rejoin at once: the same server gives the save back with the 10 Tokens", "waited %s, %s" % (waited, json.dumps(st)))
    give(a, u, 5)
    step_all(both, 2, each=watch)
    a.leave(u)
    step_all(both, 6, each=watch)
    a.join(u)
    waited = wait_loaded(a, u, [b], 20)
    st = a.status(u)
    rep.check(waited is not None and st.get("Owns") and st.get("Tokens") == base + 15, "rejoin after the save landed: every Token is there", json.dumps(st))
    a.leave(u)
    step_all(both, 6, each=watch)
    rec = store.record(u)
    rep.check(rec.get("Tokens") == base + 15 and "Lock" not in rec, "rejoin: the final record holds 15 more Tokens and no lock", "%s, Lock %s" % (rec.get("Tokens"), json.dumps(rec.get("Lock"))))
    rep.check(not watch.provisional, "rejoin: the player never played on a stand-in", ", ".join(watch.provisional))

    # -- server hop while the old server's last save is still on its way -------------------------------
    u, k = uids["hop"], key(uids["hop"])
    mark = len(store.writes)
    watch = Watch(both, u)
    a.join(u)
    rep.check(wait_loaded(a, u, [b]) is not None, "server hop: the save loads on A")
    give(a, u, 50)
    step_all(both, 1, each=watch)
    latency(a, 4)  # A's DataStore is slow: its release needs 4 s
    a.leave(u)
    b.join(u)
    step_all(both, 2, each=watch)
    rec, st = store.record(u), b.status(u)
    rep.check((rec.get("Lock") or {}).get("Id") == "srv-A" and rec.get("Tokens") == base and not st.get("Loaded"),
              "server hop: 2 s after the hop A's save is still on its way and B has NOT loaded the old save", "Tokens %s, Lock %s, %s" % (rec.get("Tokens"), json.dumps(rec.get("Lock")), json.dumps(st)))
    waited = wait_loaded(b, u, [a], 30)
    latency(a, 0)
    st = b.status(u)
    rep.check(waited is not None and st.get("Owns") and st.get("Tokens") == base + 50, "server hop: B loads only after A's save landed, with the 50 Tokens", "waited %s, %s" % (waited, json.dumps(st)))
    rep.check(not watch.provisional, "server hop: no stand-in was needed (A released inside the wait)", ", ".join(watch.provisional))
    give(b, u, 7)
    step_all(both, 2, each=watch)
    b.leave(u)
    step_all(both, 6, each=watch)
    rec = store.record(u)
    rep.check(rec.get("Tokens") == base + 57 and "Lock" not in rec, "server hop: the final record holds 57 more Tokens and no lock", "%s, Lock %s" % (rec.get("Tokens"), json.dumps(rec.get("Lock"))))
    rep.check(watch.most <= 1, "server hop: never two owners of the save at once", "most at once: %d" % watch.most)
    fw = foreign_writes(store, k, mark)
    rep.check(not fw, "server hop: no write landed over another server's live lock", " | ".join(fw[:3]))

    # -- a mixed fleet in the first hour: a MAIN server and a server of this branch on one save -------------
    rep.section("lock (c): a mixed fleet (old servers still running after the publish, or after a rollback)")
    m = Server(env, "main-live", env.main_root, a.now())
    sync([a, b, m])
    fleet = [a, b, m]
    u = uids["rollout"]
    m.join(u)
    rep.check(wait_loaded(m, u, [a, b]) is not None, "rollout: the save loads on a MAIN server")
    give(m, u, 10)
    step_all(fleet, 1)
    latency(m, 4)
    m.leave(u)  # main's last save is on its way (main has no lock)
    b.join(u)
    waited = wait_loaded(b, u, [a, m], 20)
    rep.check(waited is not None and b.status(u).get("Owns"), "rollout: the branch server loads the save (main holds no lock)")
    give(b, u, 7)
    step_all(fleet, 8)
    latency(m, 0)
    rec = store.record(u)
    rep.check((rec.get("Lock") or {}).get("Id") == "srv-B", "rollout: main's late save kept the branch server's lock in the record", json.dumps(rec.get("Lock")))
    b.leave(u)
    step_all(fleet, 6)
    rec = store.record(u)
    rep.check(rec.get("Tokens") == base + 17 and "Lock" not in rec, "rollout: both servers' Tokens are in the final record (10 on main + 7 on the branch)", "%s (want %d)" % (rec.get("Tokens"), base + 17))
    u = uids["rollback"]
    b.join(u)
    rep.check(wait_loaded(b, u, [a, m]) is not None, "rollback fleet: the save loads on a branch server")
    give(b, u, 7)
    step_all(fleet, 1)
    latency(b, 4)
    b.leave(u)
    m.join(u)
    waited = wait_loaded(m, u, [a, b], 20)
    rep.check(waited is not None, "rollback fleet: a MAIN server loads the save while the branch server's release is on its way")
    give(m, u, 10)
    step_all(fleet, 8)
    latency(b, 0)
    m.leave(u)
    step_all(fleet, 6)
    rec = store.record(u)
    rep.check(rec.get("Tokens") == base + 17, "rollback fleet: both servers' Tokens are in the final record (7 on the branch + 10 on main)", "%s (want %d)" % (rec.get("Tokens"), base + 17))
    rep.check(not errors_of(m.problems()), "mixed fleet: the MAIN server raised no script error")
    m.close()

    # -- a crash: the server dies without a release, the lock has to expire ----------------------------
    rep.section("lock (c): a server crashes without releasing the save")
    u, k = uids["crash"], key(uids["crash"])
    mark = len(store.writes)
    watch = Watch(both, u)
    a.join(u)
    rep.check(wait_loaded(a, u, [b]) is not None, "crash: the save loads on A")
    give(a, u, 70)
    waited = 0
    while waited < 300 and store.record(u).get("Tokens") != base + 70:
        step_all(both, 5, each=watch)
        waited += 5
    rec = store.record(u)
    rep.check(rec.get("Tokens") == base + 70 and (rec.get("Lock") or {}).get("Id") == "srv-A", "crash: an autosave stored 70 Tokens under A's lock (%d s)" % waited, "%s, %s" % (rec.get("Tokens"), json.dumps(rec.get("Lock"))))
    give(a, u, 9)  # never saved: the server dies now
    lock_at = rec["Lock"]["At"]
    a.close(shutdown=False)
    b.join(u)
    step_all([b], CLAIM_WAIT + 3, each=watch)
    st = b.status(u)
    rep.check(st.get("Loaded") and st.get("Provisional") and not st.get("Owns"), "crash: the next server gives a stand-in while the dead server's lock is live", json.dumps(st))
    give(b, u, 3)
    step_all([b], 120, step=1.0, each=watch)
    rec, st = store.record(u), b.status(u)
    rep.check(st.get("Provisional") and (rec.get("Lock") or {}).get("Id") == "srv-A" and rec.get("Tokens") == base + 70,
              "crash: 2 minutes later the lock is still live: B has not touched the stored save", "%s / Tokens %s, Lock %s" % (json.dumps(st), rec.get("Tokens"), json.dumps(rec.get("Lock"))))
    waited = 0
    while waited < 420 and not (b.status(u).get("Owns") and not b.status(u).get("Provisional")):
        step_all([b], 2, step=1.0, each=watch)
        waited += 2
    st = b.status(u)
    took = None
    for w in store.writes[mark:]:
        if w["key"] == k and w["by"] == b.label and w["after"] and w["after"].get("Id") == "srv-B":
            took = w
            break
    rep.check(st.get("Owns") and not st.get("Provisional") and took is not None, "crash: B takes the save over when the lock expires", json.dumps(st))
    if took is not None:
        age = took["after"]["At"] - lock_at
        rep.check(LOCK_SECONDS <= age <= LOCK_SECONDS + 60, "crash: the takeover came %d s after the dead server's last write (the lock lives %d s)" % (age, LOCK_SECONDS), "age %d" % age)
    rep.check(st.get("Tokens") == base + 70 + 3, "crash: every Token that reached the store is there (70), plus the 3 earned on the stand-in; only the dead server's unsaved 9 are gone",
              "%s (want %d)" % (st.get("Tokens"), base + 73))
    b.leave(u)
    step_all([b], 6, each=watch)
    rec = store.record(u)
    rep.check(rec.get("Tokens") == base + 73 and "Lock" not in rec, "crash: the final record holds 73 more Tokens and no lock", "%s, Lock %s" % (rec.get("Tokens"), json.dumps(rec.get("Lock"))))
    rep.check(watch.most <= 1, "crash: never two owners of the save at once", "most at once: %d" % watch.most)
    fw = foreign_writes(store, k, mark)
    rep.check(not fw, "crash: no write landed over the dead server's lock while it was live", " | ".join(fw[:3]))
    problems = b.problems()
    rep.check(not errors_of(problems), "lock: the branch servers raised no script error", " | ".join(errors_of(problems)[:3]))
    rep.check(not store.bad, "lock: every value stored is one a real DataStore can hold", " | ".join(store.bad[:3]))
    env.clock = b.now()
    b.close()


def main():
    ap = argparse.ArgumentParser(description="Nimbus Climb: the save round trip between main and this branch (release step 1, gate 2)")
    ap.add_argument("--main-ref", default="origin/main", help="the git ref of the live game's code (default origin/main)")
    ap.add_argument("--only", help="comma separated phases: build,load,rollback,crash,lock (build always runs)")
    ap.add_argument("--json", metavar="FILE", help="write the checks and every field difference as JSON")
    ap.add_argument("--dump", metavar="FILE", help="write the fake saves main's code wrote (the fixture) as JSON")
    ap.add_argument("-v", "--verbose", action="store_true", help="print passing checks too")
    ap.add_argument("--engine", help="lupa engine (default luajit21)")
    ap.add_argument("--branch-root", metavar="DIR", help="test this copy of the branch (src/ + default.project.json) instead of the repo: "
                    "for proving the checks fail on a deliberately broken copy")
    a = ap.parse_args()
    phases = set(x.strip() for x in a.only.split(",")) if a.only else {"build", "load", "rollback", "crash", "lock"}

    env = Env()
    env.engine_name, env.engine = smoke.load_engine(a.engine)
    with open(os.path.join(HERE, "contract.json"), encoding="utf-8") as fh:
        env.contract = json.load(fh)
    with open(os.path.join(HERE, "roblox-api.json"), encoding="utf-8") as fh:
        env.api = json.load(fh)
    env.args = types.SimpleNamespace(strict_members=False, echo=False, no_watchdog=False, fps=30.0, slice_limit=30.0, seeds=40, verbose=False, quick=True)
    env.store = Store()
    env.clock = 1000.0
    env.differences = []
    started = time.time()
    env.branch_root = os.path.abspath(a.branch_root) if a.branch_root else ROOT
    try:
        env.commit, env.main_root, tmp = extract_ref(a.main_ref)
    except subprocess.CalledProcessError as exc:
        print("save_roundtrip.py: cannot read '%s' from git (%s). Run `git fetch origin` first, or pass --main-ref <commit>." % (
            a.main_ref, (exc.stderr or b"").decode(errors="replace").strip()))
        return 2
    head = git("rev-parse", "HEAD").decode().strip()
    print("Nimbus Climb save round trip  (main = %s at %s, branch = %s%s, Lua engine: %s)" % (
        a.main_ref, env.commit[:12], head[:12], (" [copy: %s]" % env.branch_root) if a.branch_root else "", env.engine_name))
    rep = Report(a.verbose)
    try:
        phase_build(env, rep)
        if "load" in phases:
            phase_load(env, rep)
        if "rollback" in phases:
            if not hasattr(env, "main_view"):
                phase_load(env, Report(False))  # main's first reading of the saves is the reference
            phase_rollback(env, rep)
        if "crash" in phases:
            phase_crash(env, rep)
        if "lock" in phases:
            phase_lock(env, rep)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if a.dump:
        with open(a.dump, "w", encoding="utf-8") as fh:
            json.dump({"main_commit": env.commit, "users": USERS, "seed": getattr(env, "seed", None), "saves": env.fixture}, fh, indent=1, sort_keys=True)

    # the field differences, grouped
    print("\n== FIELD DIFFERENCES (main's reading / record vs this branch's) ==")
    groups = {}
    for d in env.differences:
        top = d["path"].lstrip(".").split(".")[0].split("[")[0] or "<root>"
        k = (d["where"].split(" ")[0], d["kind"], top, d["allowed"] or "NOT ALLOWED")
        groups.setdefault(k, []).append(d)
    for k in sorted(groups):
        rows = groups[k]
        ex = rows[0]
        print("  %-7s %-7s %-14s x%-4d %s   e.g. %s (%s): %s -> %s" % (k[0], k[1], k[2], len(rows), k[3], ex["path"], ex["where"], ex["main"], ex["branch"]))
    if not groups:
        print("  none")
    print("\nsave round trip: %d passed, %d failed  (%.1fs)  main %s" % (rep.oks, rep.fails, time.time() - started, env.commit[:12]))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as fh:
            json.dump({"main_commit": env.commit, "branch_commit": head, "checks": rep.rows, "notes": rep.notes, "differences": env.differences}, fh, indent=1)
    return 1 if rep.fails else 0


if __name__ == "__main__":
    sys.exit(main())
