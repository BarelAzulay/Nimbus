#!/usr/bin/env python3
"""Which palette keys / part names does the game (or a test) look up BY NAME?  (Phase 6, recipe 4.3 / decision 6)

The Blender kit may bake a constant-colour key into a shared `Fixed` MeshPart only when nothing looks that key up by
name: once baked, the part named after the key no longer exists.  This tool collects the referenced names from
  * src/**/*.lua and tools/*.lua:  FindFirstChild("X"), WaitForChild("X"), Name == "X", "X" == ...Name,
    :match("^X") / string.match(n, "^X") / find("^X"), partsNamed("^X"), Voxel.BaseKey lookups in tables,
    keyed(model, "X") and the tests' key-count tables { { "X", "Y" }, n, ... } / ipairs({ "X", ... }) ... keyed(
  * PetBuilder's by-name tables: GOLD_METAL, RAINBOW_KEYS, WILD_EYES, WILD_KEEP
  * the contract's never-bake list (Horn, Claw, Beak, Hoof, Nostril, EyeShine; recipe 4.3)

    python3 tools/mesh_names.py                    list the referenced names
    python3 tools/mesh_names.py --json             ... as JSON
    python3 tools/mesh_names.py --check blender/out/*.manifest.json
                                                   fail when a Fixed part bakes a referenced key (exit 1)
Imported by blender/kit (referenced_names()).
"""
import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NEVER_BAKE = {"Horn", "Claw", "Beak", "Hoof", "Nostril", "EyeShine"}
# (FINISH_KEEP is not a lookup: it lists keys a finish never recolours, which a baked Fixed part honours anyway)
NAME_TABLES = ("GOLD_METAL", "RAINBOW_KEYS", "WILD_EYES", "WILD_KEEP")
IDENT = r"([A-Z][A-Za-z0-9_]*)"
PATTERNS = [
    re.compile(r"(?:FindFirstChild|WaitForChild|FindFirstChildOfClass)\(\s*[\"']" + IDENT + r"[\"']"),
    re.compile(r"Name\s*[~=]=\s*[\"']" + IDENT + r"[\"']"),
    re.compile(r"[\"']" + IDENT + r"[\"']\s*[~=]=\s*[A-Za-z_.:]*Name\b"),
    re.compile(r"(?:match|find|gmatch|partsNamed|named)\(\s*(?:[A-Za-z_.]+\s*,\s*)?[\"']\^" + IDENT),
    re.compile(r":(?:match|find)\(\s*[\"']\^" + IDENT),
    re.compile(r"\bkeyed\(\s*[A-Za-z_.]+\s*,\s*[\"']" + IDENT + r"[\"']"),
]
_STRS = r"((?:[\"'][A-Z][A-Za-z0-9_]*[\"']\s*,?\s*)+)"
# lists of key names (every string in group 1 is a name): smoke_p3_evolved's SIGNS { { "Basalt" }, 2, "..." } and
# its leak loop `for _, key in ipairs({ "Magma", "Basalt", ... }) do ... keyed(m, key)` (by-name part counts)
LIST_PATTERNS = [
    re.compile(r"\{\s*\{\s*" + _STRS + r"\}\s*,\s*\d+"),
    re.compile(r"ipairs\(\{\s*" + _STRS + r"\}\)\s*do[^\n]*\n[^\n]*\bkeyed\("),
]


def _lua_files():
    files = glob.glob(os.path.join(ROOT, "src", "**", "*.lua"), recursive=True)
    files += glob.glob(os.path.join(ROOT, "tools", "*.lua"))
    # generated manifests only describe parts, they do not look anything up
    return sorted(f for f in files if os.sep + "MeshManifests" + os.sep not in f)


def _table_keys(text, name):
    m = re.search(r"local\s+" + name + r"\s*=\s*\{(.*?)\n\}", text, re.S)
    if not m:
        return set()
    body = m.group(1)
    return set(re.findall(r"\b" + IDENT + r"\s*=\s*true", body)) | set(re.findall(r"[\"']" + IDENT + r"[\"']", body))


def referenced_names(root=ROOT):
    found = set(NEVER_BAKE)
    where = {}
    for f in _lua_files():
        try:
            text = open(f, encoding="utf-8").read()
        except OSError:
            continue
        rel = os.path.relpath(f, root)
        for pat in PATTERNS:
            for m in pat.finditer(text):
                n = m.group(1)
                found.add(n)
                where.setdefault(n, rel)
        for pat in LIST_PATTERNS:
            for m in pat.finditer(text):
                for n in re.findall(r"[\"']" + IDENT + r"[\"']", m.group(1)):
                    found.add(n)
                    where.setdefault(n, rel)
        if rel.replace(os.sep, "/") == "src/shared/PetBuilder.lua":
            for t in NAME_TABLES:
                for n in _table_keys(text, t):
                    found.add(n)
                    where.setdefault(n, rel + ":" + t)
    return found, where


def check_manifests(paths, names):
    bad = []
    for p in paths:
        m = json.load(open(p))
        for part in m.get("parts", []):
            if part.get("color") == "vertex":
                for k in part.get("fixedKeys", []):
                    if k in names:
                        bad.append("%s: Fixed part %s bakes referenced key %s" % (os.path.basename(p), part["name"], k))
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--check", nargs="*")
    a = ap.parse_args()
    names, where = referenced_names()
    if a.check is not None:
        paths = []
        for p in a.check:
            paths += glob.glob(p)
        bad = check_manifests(paths, names)
        for b in bad:
            print("FAIL", b)
        print("mesh_names: %d manifests, %d referenced names, %d problems" % (len(paths), len(names), len(bad)))
        sys.exit(1 if bad else 0)
    if a.json:
        print(json.dumps({"names": sorted(names), "where": where}, indent=1, sort_keys=True))
    else:
        for n in sorted(names):
            print("%-22s %s" % (n, where.get(n, "contract (never bake)")))


if __name__ == "__main__":
    main()
