#!/usr/bin/env python3
"""Count the main-chunk local variables of Lua files (the Lua / Luau limit is 200 active locals per function).

Usage: python3 tools/count_locals.py [files...]       (default: every .lua under src/)
       python3 tools/count_locals.py --limit 180 ...    exit 1 when a file is at or above the limit

Counts column-0 `local a, b = ...` and `local function f` statements, like the Phase 4 design prototype did
(ARCHITECTURE_V3.md "Phase 5 build contract" 10.3: the locals row of the budgets table is baselined with this count;
tools/check.mjs's `many-locals` / `too-many-locals` rules count the ACTIVE locals per function with the real parser).
File arguments may be absolute, relative to the repo, or relative to src/ (e.g. `client/Controllers/MenuController.lua`).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "src")


def count_file(path):
    n = 0
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("local function "):
                n += 1
            elif line.startswith("local "):
                head = line[6:].split("=")[0]
                names = [x for x in head.split(",") if x.strip()]
                n += len(names)
    return n


def resolve(arg):
    for candidate in (arg, os.path.join(ROOT, arg), os.path.join(SRC, arg)):
        if os.path.isfile(candidate):
            return candidate
    return None


def all_sources():
    out = []
    for root, _, files in os.walk(SRC):
        for f in sorted(files):
            if f.endswith(".lua"):
                out.append(os.path.join(root, f))
    return sorted(out)


def main():
    args = sys.argv[1:]
    limit = None
    if "--limit" in args:
        i = args.index("--limit")
        limit = int(args[i + 1])
        del args[i:i + 2]
    files = [resolve(a) for a in args] if args else all_sources()
    missing = [a for a, f in zip(args, files) if f is None]
    for a in missing:
        print("not found: %s" % a)
    files = [f for f in files if f]
    rows = []
    for f in files:
        rows.append((count_file(f), os.path.relpath(f, SRC) if f.startswith(SRC) else f))
    rows.sort(reverse=True)
    over = 0
    for n, name in rows:
        flag = ""
        if limit is not None and n >= limit:
            flag = "  <-- at/over %d" % limit
            over += 1
        print("%4d  %s%s" % (n, name, flag))
    sys.exit(1 if (over or missing) else 0)


if __name__ == "__main__":
    main()
