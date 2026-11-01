#!/usr/bin/env python3
"""Offline tests of tools/smoke_parallel.py: the split, the merge and the comparison, on small made-up results.

Nothing boots a Lua world here. Exit code 0 = all passed.

    py -3.12 tools/test_smoke_parallel.py
"""
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import smoke_parallel as P  # noqa: E402

LISTS = {
    "server": ["mock_selftest", "load_modules", "catalog", "boot", "lobby", "hazards", "shutdown", "final_checks"],
    "pure": ["catalog"],
    "client": ["client_load", "client_hud", "client_replay", "client_menu", "client_p3flow", "client_final"],
    "mobile": ["client_mobile", "client_p2ui_mobile"],
}
failures = []


def check(ok, name):
    print(("  ok    " if ok else "  FAIL  ") + name)
    if not ok:
        failures.append(name)


def rec(status, section, name):
    return {"status": status, "section": section, "name": name, "detail": ""}


class FakePart:
    def __init__(self, workdir, name, records):
        self.json = os.path.join(workdir, name + ".json")
        with open(self.json, "w", encoding="utf-8") as fh:
            json.dump(records, fh)


def quiet_compare(merged, base):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        same = P.compare(merged, base)
    return same, out.getvalue()


def main():
    groups, before = P.plan(LISTS)
    everything = LISTS["server"] + LISTS["client"] + LISTS["mobile"]
    check(all(any(n in g for g in groups.values()) for n in everything), "every listed scenario is in a part")
    check(groups["server"] == ["mock_selftest", "load_modules", "boot", "lobby", "shutdown", "final_checks"], "the server part keeps its order and loses only pure + hazards")
    check(groups["pure"] == ["catalog", "final_checks"] and groups["hazards"] == ["hazards", "final_checks"], "the pure and hazards parts close with the whole-run checks")
    check(groups["replay"] == ["client_load", "client_hud", "client_replay", "client_p3flow", "client_final"], "the replay part builds what came before client_replay, in order")
    check("client_replay" not in groups["client"] and "client_p3flow" not in groups["client"], "the client part has no replication reader")
    check(before == {"client_load", "client_hud"}, "the scenarios before client_replay count as repeated")
    check(set(P.REPLICATION_READERS) & set(groups["phone"]) == set(), "the phone part has no replication reader")

    workdir = tempfile.mkdtemp(prefix="test_smoke_parallel_")
    try:
        parts = [
            FakePart(workdir, "server", [rec("ok", "boot", "booted"), rec("ok", "final_checks", "the run exercised the Notify remote"), rec("warn", "final_checks", "mock: x (x3, first at a)")]),
            FakePart(workdir, "hazards", [
                rec("ok", "boot", "booted"),
                rec("fail", "boot", "boot broke only here"),
                rec("ok", "hazards", "swings"),
                rec("ok", "final_checks", "no leaks"),
                rec("fail", "final_checks", "the run exercised the MatchState remote"),
                rec("fail", "final_checks", "script error in the moved scenario"),
                rec("warn", "final_checks", "mock: x (x9, first at b)"),
                rec("warn", "final_checks", "mock: y (x1, first at c)"),
            ]),
        ]
        merged = P.merge(parts, P.REPEATED)
        names = [r["name"] for r in merged]
        check(names.count("booted") == 1, "a repeated scenario's pass counts once")
        check("boot broke only here" in names, "a failure in a repeated scenario of a later part is kept")
        check("script error in the moved scenario" in names, "the closing checks of a moved scenario's part report its script errors")
        check("the run exercised the MatchState remote" not in names, "the whole-run question counts only in the full server part")
        check("no leaks" not in names, "a later part's closing passes are not counted again")
        check("swings" in names, "the moved scenario's own checks count")
        check(sum(n.startswith("mock: x") for n in names) == 1 and "mock: y (x1, first at c)" in names, "a warning counts once, whatever its repeat count; a new one is kept")

        check(len(P.replication_skips([rec("warn", "client_new", "no server replication log: run the server scenarios first"), rec("warn", "a", "other")])) == 1, "a scenario that skipped for lack of the replication log is a problem")

        part = P.Part("phone", ["client_mobile"], workdir, [])
        part.exit = 1
        with open(part.log, "w", encoding="utf-8") as fh:
            fh.write("== client_mobile ==\nsmoke test: 1 passed, 1 failed, 0 warnings  (1.0s)\n")
        check(any("no results file" in p for p in P.part_problems(part)), "a part that wrote no results file is a problem")
        with open(part.json, "w", encoding="utf-8") as fh:
            json.dump([], fh)
        check(P.part_problems(part) == [], "a part with a summary, its results and every scenario has no problem")
        part.exit = 3
        check(any("exit 3" in p for p in P.part_problems(part)), "a part that ended with an unexpected exit code is a problem")
        part.exit = 1
        part.names = ["client_mobile", "client_other"]
        check(any("client_other did not run" in p for p in P.part_problems(part)), "a scenario with no line in the log is a problem")
        with open(part.log, "w", encoding="utf-8") as fh:
            fh.write("== client_mobile ==\n")
        check(any("without a summary" in p for p in P.part_problems(part)), "a part that died without a summary is a problem")

        single = os.path.join(workdir, "single.json")
        with open(single, "w", encoding="utf-8") as fh:
            json.dump([rec("ok", "a", "plot of his own (#3) 0x01a"), rec("ok", "a", "Easy: set (Serpent)"), rec("ok", "b", "gone"), rec("warn", "b", "w"), rec("info", "b", "i")], fh)
        same, _ = quiet_compare([rec("ok", "a", "plot of his own (#7) 0x02f"), rec("ok", "a", "Easy: set (Zigzag)"), rec("ok", "b", "gone")], single)
        check(same, "measured numbers, addresses and a picked word do not count as a difference")
        check(P.comparable("at its Speed (-12 deg/s)") == P.comparable("at its Speed (30.5 deg/s)"), "a measured number's sign does not count as a difference")
        check(P.comparable("shows '*' (a=1:2*;b=3:4)") == P.comparable("shows '*' (a=1:2;b=3:4*)"), "a random payload in the closing bracket does not count as a difference")
        check(P.comparable("check one (x)") != P.comparable("check two (x)"), "the words outside the bracket still count")
        same, text = quiet_compare([rec("ok", "a", "plot of his own (#3) 0x01a"), rec("ok", "a", "Easy: set (Serpent)")], single)
        check(not same and "gone" in text, "a check missing from the parallel run is a difference, and is named")
        same, text = quiet_compare([rec("ok", "a", "plot of his own (#3) 0x01a"), rec("ok", "a", "Easy: set (Serpent)"), rec("fail", "b", "gone")], single)
        check(not same, "the same check with another status is a difference")
        same, _ = quiet_compare([rec("ok", "a", "plot of his own (#3) 0x01a"), rec("ok", "a", "Easy: set (Serpent)"), rec("ok", "b", "gone"), rec("ok", "b", "gone")], single)
        check(not same, "a check run twice is a difference")
        same, _ = quiet_compare([rec("ok", "a", "plot of his own (#3) 0x01a"), rec("ok", "a", "Easy: set (Serpent)"), rec("ok", "c", "gone")], single)
        check(not same, "the same check in another scenario is a difference")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print("\n%d failed" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
