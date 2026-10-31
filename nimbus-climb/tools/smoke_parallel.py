#!/usr/bin/env python3
"""The smoke suite split over several processes (tools/smoke.py does the work; nothing is left out).

    py -3.12 tools/smoke_parallel.py [--quick] [--seeds N] [--jobs N] [--json FILE] [--compare BASE.json] [--keep-logs]

smoke.py runs every scenario of a world in one Lua runtime, one after the other. This tool starts one smoke.py per part:

  server   the booted server scenarios, in their order; writes the replication log for "replay"
  pure     the content scenarios that need only the loaded modules
  hazards  the one slow scenario (about a quarter of the server world), on its own booted world
  client   the client scenarios that do not read the replication log
  replay   the client scenarios that do; starts when "server" has finished
  phone    the touch world

Moving a scenario to another world changes what ran before it and the mock clock it sees, so a pass here is not the same
proof as a pass in one world. Use this while building. **The last gate before a merge stays the single `smoke.py --quick`.**
`--compare BASE.json` checks the merged results against a single run's --json (same checks, same statuses) and fails on any
difference; re-run it after moving scenarios between worlds or when a part fails here but not in a single run.

Exit status is 1 when a check fails, a part dies without its summary or a listed scenario did not run.
"""
import argparse
import collections
import ctypes
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SMOKE = os.path.join(HERE, "smoke.py")

# Scenarios more than one part runs. A part boots its world again, and it closes with its world's whole-run checks: script
# errors, mock findings, leaks and payload rules are only reported there, so a part without them would hide its problems.
REPEATED = {"mock_selftest", "load_modules", "boot", "client_load", "client_mobile", "final_checks", "client_final", "smoke.py"}
# final_checks asks that the whole run used these remotes: only the full server part can answer that
WHOLE_RUN_ONLY = "the run exercised the "
REPLICATION_READERS = ["client_replay", "client_p3flow", "client_p4flow", "client_p5flow"]
SLOW_ALONE = ["hazards"]


def ordered_unique(names):
    return list(dict.fromkeys(names))


def plan(lists):
    """Every listed scenario lands in one part; only the repeated ones land in more."""
    pure = set(lists["pure"])
    slow = set(SLOW_ALONE)
    readers = set(REPLICATION_READERS)
    # client_replay compares the GUI with what the scenarios before it built, so the replay world builds that first too
    before_replay = lists["client"][:lists["client"].index("client_replay")]
    return {
        "server": ordered_unique(n for n in lists["server"] if n not in pure and n not in slow),
        "pure": ordered_unique(n for n in lists["server"] if n in pure) + ["final_checks"],
        "hazards": ordered_unique(n for n in lists["server"] if n in slow) + ["final_checks"],
        "client": ordered_unique(n for n in lists["client"] if n not in readers),
        "replay": before_replay + ordered_unique(n for n in lists["client"] if n in readers) + ["client_final"],
        "phone": ordered_unique(lists["mobile"]),
    }, set(before_replay)


def working_set(pid):
    """Bytes of a process's working set (Windows); 0 elsewhere or when it has gone."""
    if os.name != "nt":
        return 0

    class Counters(ctypes.Structure):
        _fields_ = [("cb", ctypes.c_ulong), ("faults", ctypes.c_ulong), ("peak", ctypes.c_size_t), ("current", ctypes.c_size_t)] + [("f%d" % i, ctypes.c_size_t) for i in range(6)]

    kernel = ctypes.WinDLL("kernel32")
    psapi = ctypes.WinDLL("psapi")
    kernel.OpenProcess.restype = ctypes.c_void_p
    psapi.GetProcessMemoryInfo.argtypes = [ctypes.c_void_p, ctypes.POINTER(Counters), ctypes.c_ulong]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return 0
    info = Counters()
    info.cb = ctypes.sizeof(Counters)
    ok = psapi.GetProcessMemoryInfo(handle, ctypes.byref(info), info.cb)
    kernel.CloseHandle(handle)
    return info.current if ok else 0


class Part:
    def __init__(self, name, names, workdir, base_args, extra=None):
        self.name = name
        self.names = names
        self.log = os.path.join(workdir, name + ".txt")
        self.json = os.path.join(workdir, name + ".json")
        self.cmd = [sys.executable, SMOKE, "--only", ",".join(names), "--json", self.json] + base_args + (extra or [])
        self.proc = None
        self.handle = None
        self.started = None
        self.seconds = 0.0
        self.exit = None

    def start(self):
        env = dict(os.environ, PYTHONIOENCODING="utf-8")
        self.handle = open(self.log, "w", encoding="utf-8")
        self.started = time.time()
        self.proc = subprocess.Popen(self.cmd, stdout=self.handle, stderr=subprocess.STDOUT, env=env, cwd=os.path.dirname(HERE))

    def poll(self):
        if self.proc is None or self.exit is not None:
            return False
        code = self.proc.poll()
        if code is None:
            return False
        self.exit = code
        self.seconds = time.time() - self.started
        self.handle.close()
        return True

    def ran(self):
        out = collections.Counter()
        with open(self.log, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = re.match(r"^== (.+) ==$", line.rstrip())
                if m:
                    out[m.group(1)] += 1
        return out

    def summary(self):
        with open(self.log, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("smoke test:"):
                    return line.strip()
        return None


def merge(parts, repeated):
    """All parts' results. A repeated scenario counts once, from the first part that ran it (server, client, phone first);
    later parts add only what is wrong there: a failure (except the whole-run question) or a warning not seen yet."""
    seen = set()
    warned = set()
    merged = []
    for part in parts:
        if not os.path.exists(part.json):
            continue
        with open(part.json, encoding="utf-8") as fh:
            records = json.load(fh)
        for r in records:
            again = r["section"] in repeated and r["section"] in seen
            if r["status"] == "warn":
                key = (r["section"], re.sub(r" \(x\d+, first at .*\)$", "", r["name"]))
                if key in warned:
                    continue
                warned.add(key)
            elif again and (r["status"] != "fail" or r["name"].startswith(WHOLE_RUN_ONLY)):
                continue
            merged.append(r)
        seen |= set(r["section"] for r in records)
    return merged


def comparable(name):
    """A check's name without what changes between any two runs: measured numbers, table addresses, a randomly picked word."""
    return re.sub(r"0x[0-9a-f]+|-?\d+(\.\d+)?", "N", re.sub(r"\([A-Z][a-z]+\)$", "(word)", name))


def compare(merged, base_path):
    """Same passes and failures as the single run. Warnings are only counted: the mock's name a repeat count that splits
    over the parts, and a warning fails neither kind of run."""
    with open(base_path, encoding="utf-8") as fh:
        base = json.load(fh)
    key = lambda r: (r["status"], r["section"], comparable(r["name"]))
    keep = lambda r: r["status"] in ("ok", "fail")
    want = collections.Counter(key(r) for r in base if keep(r))
    got = collections.Counter(key(r) for r in merged if keep(r))
    missing = want - got
    extra = got - want
    print("\ncompare with %s: %d checks there, %d here, %d only there, %d only here; warnings %d there, %d here" % (
        os.path.basename(base_path), sum(want.values()), sum(got.values()), sum(missing.values()), sum(extra.values()),
        sum(r["status"] == "warn" for r in base), sum(r["status"] == "warn" for r in merged)))
    for label, table in (("only in the single run", missing), ("only in the parallel run", extra)):
        for (status, section, name), n in sorted(table.items())[:80]:
            print("  %s: x%d %s [%s] %s" % (label, n, status, section, name[:200]))
    return not missing and not extra


def main():
    ap = argparse.ArgumentParser(description="Nimbus Climb smoke suite over several processes")
    ap.add_argument("--quick", action="store_true", help="smoke.py --quick")
    ap.add_argument("--seeds", type=int, help="smoke.py --seeds")
    ap.add_argument("--jobs", type=int, default=6, help="parts running at once (default 6, all; lower it when memory is short)")
    ap.add_argument("--json", metavar="FILE", help="write the merged results as JSON")
    ap.add_argument("--compare", metavar="BASE", help="a single run's --json file: fail on any different check or status")
    ap.add_argument("--keep-logs", action="store_true", help="keep each part's log (they are kept anyway when something failed)")
    args = ap.parse_args()

    base_args = (["--quick"] if args.quick else []) + (["--seeds", str(args.seeds)] if args.seeds else [])
    listed = subprocess.run([sys.executable, SMOKE, "--list-json"], capture_output=True, text=True, encoding="utf-8", cwd=os.path.dirname(HERE))
    if listed.returncode != 0:
        sys.exit("smoke.py --list-json failed:\n" + listed.stdout + listed.stderr)
    lists = json.loads(listed.stdout.strip().splitlines()[-1])
    groups, before_replay = plan(lists)

    workdir = tempfile.mkdtemp(prefix="smoke_parallel_")
    replication = os.path.join(workdir, "replication.bin")
    parts = [
        Part("server", groups["server"], workdir, base_args, ["--replication-out", replication]),
        Part("pure", groups["pure"], workdir, base_args),
        Part("hazards", groups["hazards"], workdir, base_args),
        Part("client", groups["client"], workdir, base_args),
        Part("phone", groups["phone"], workdir, base_args),
        Part("replay", groups["replay"], workdir, base_args, ["--replication-in", replication]),
    ]
    by_name = {p.name: p for p in parts}
    print("smoke_parallel: %s" % ", ".join("%s %d" % (p.name, len(p.names)) for p in parts))
    sys.stdout.flush()

    started = time.time()
    peak = 0
    problems = []
    waiting = list(parts)
    running = []
    while waiting or running:
        for part in list(waiting):
            if len(running) >= max(1, args.jobs):
                break
            if part.name == "replay":
                server = by_name["server"]
                if server.exit is None:
                    continue
                if not os.path.exists(replication):
                    problems.append("replay did not run: the server part wrote no replication log (exit %s)" % server.exit)
                    waiting.remove(part)
                    continue
            part.start()
            waiting.remove(part)
            running.append(part)
        now = sum(working_set(p.proc.pid) for p in running)
        peak = max(peak, now)
        for part in list(running):
            if part.poll():
                running.remove(part)
                print("  %-8s %6.1f s  %s" % (part.name, part.seconds, part.summary() or "NO SUMMARY, exit %s" % part.exit))
                sys.stdout.flush()
        if running:
            time.sleep(1)
    elapsed = time.time() - started

    # nothing may go missing without saying so
    for part in parts:
        if part.proc is None:
            continue
        if part.summary() is None:
            problems.append("%s died without a summary (exit %s), see %s" % (part.name, part.exit, part.log))
        ran = part.ran()
        for name in part.names:
            if ran[name] == 0:
                problems.append("%s: scenario %s did not run" % (part.name, name))
    assigned = set(n for p in parts for n in p.names)
    for name in lists["server"] + lists["client"] + lists["mobile"]:
        if name not in assigned:
            problems.append("scenario %s is in no part" % name)

    merged = merge(parts, REPEATED | before_replay)
    counts = collections.Counter(r["status"] for r in merged)
    failed = [r for r in merged if r["status"] == "fail"]
    for r in failed:
        print("  FAIL  [%s] %s  -- %s" % (r["section"], r["name"], str(r["detail"]).replace("\n", "\n            ")))
    for line in problems:
        print("  PROBLEM  " + line)
    total_cpu = sum(p.seconds for p in parts)
    print("\nsmoke_parallel: %d passed, %d failed, %d warnings  (%.1fs; parts add up to %.1fs; peak memory %.2f GB)" % (counts["ok"], counts["fail"], counts["warn"], elapsed, total_cpu, peak / 2**30))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(merged, fh, indent=2)
    same = compare(merged, args.compare) if args.compare else True
    bad = bool(failed or problems or not same)
    if bad or args.keep_logs:
        print("part logs: " + workdir)
    else:
        shutil.rmtree(workdir, ignore_errors=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
