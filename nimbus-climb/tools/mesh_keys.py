#!/usr/bin/env python3
"""Do the game's Mesh.tag keys and the Blender manifests line up?  (lobby-shop Task 29, spec 8)

    py -3.12 tools/mesh_keys.py              list the literal Mesh.tag keys and whether each has a manifest
    py -3.12 tools/mesh_keys.py --check      exit 1 on any problem, each printed on its own line:
      (a) every complete literal key in `Mesh.tag(<target>, "<key>"` across src/**/*.lua has
          src/shared/MeshManifests/<key>.lua.  Complete = the second argument is one string literal followed by `,` or
          `)`; a prefix joined with `..` ("arena_ring_" .. index), a variable, a call or an expression is not checked.
          Calls are found as tokens (H.Mesh.tag and Mesh.tag both count; `function Mesh.tag(` has no literal), the
          target may hold nested calls and strings, and comments / long strings hide what is inside them.
      (b) every key in BUILD_KEYS (the keys this build made) appears as a string literal in some src Lua file, the
          generated manifests left out (each names its own key); keys in RESERVED are skipped.
    --root <dir>         another game root (tests); --build-keys k ...   other build keys (tests)

Tested by tools/test_mesh_keys.py.
"""
import argparse
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAN_REL = os.path.join("src", "shared", "MeshManifests")
BUILD_KEYS = ("egg_common", "egg_uncommon", "egg_rare", "egg_epic", "egg_legendary", "egg_mythic", "egg_secret",
              "gem_world", "portal_ring", "portal_altar_ring", "prop_board_lb",
              # (egg-3d) the hatch cutscene's egg halves (catalog hatch; named by src/client/UI/Egg3D.lua)
              "egg_common_top", "egg_common_bot", "egg_uncommon_top", "egg_uncommon_bot", "egg_rare_top", "egg_rare_bot",
              "egg_epic_top", "egg_epic_bot", "egg_legendary_top", "egg_legendary_bot", "egg_mythic_top", "egg_mythic_bot",
              "egg_secret_top", "egg_secret_bot")
RESERVED = ("gem_world_low",)  # made with gem_world for small gem drops; nothing tags it yet

_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_LONG_OPEN = re.compile(r"\[(=*)\[")


def lex(text):
    """Lua tokens (kind, value, pos): kind "str" (value = the raw text between the quotes / brackets), "name", "num",
    "op" ("..", "...", "." or one character).  Comments and whitespace are dropped."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n\f\v":
            i += 1
        elif text.startswith("--", i):
            m = _LONG_OPEN.match(text, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                j = text.find(close, m.end())
                i = n if j < 0 else j + len(close)
            else:
                j = text.find("\n", i)
                i = n if j < 0 else j + 1
        elif c == "[" and _LONG_OPEN.match(text, i):
            m = _LONG_OPEN.match(text, i)
            close = "]" + m.group(1) + "]"
            j = text.find(close, m.end())
            end = n if j < 0 else j
            out.append(("str", text[m.end():end], i))
            i = n if j < 0 else j + len(close)
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(("str", text[i + 1:min(j, n)], i))
            i = j + 1
        elif c.isalpha() or c == "_":
            m = _NAME.match(text, i)
            out.append(("name", m.group(0), i))
            i = m.end()
        elif c.isdigit():
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] in "._") and not text.startswith("..", j):
                j += 1
            out.append(("num", text[i:j], i))
            i = j
        elif c == ".":
            k = 3 if text.startswith("...", i) else (2 if text.startswith("..", i) else 1)
            out.append(("op", text[i:i + k], i))
            i += k
        else:
            out.append(("op", c, i))
            i += 1
    return out


def tag_keys(text):
    """[(key, line)] of every complete literal key in a Mesh.tag call, in file order"""
    toks = lex(text)
    found = []
    for t in range(len(toks) - 3):
        if (toks[t][:2] != ("name", "Mesh") or toks[t + 1][:2] != ("op", ".") or toks[t + 2][:2] != ("name", "tag")
                or toks[t + 3][:2] != ("op", "(")):
            continue
        # skip the first argument (the target): to the first comma at depth 1
        depth, j = 1, t + 4
        while j < len(toks) and depth > 0:
            kind, val, _ = toks[j]
            if kind == "op" and val in "([{":
                depth += 1
            elif kind == "op" and val in ")]}":
                depth -= 1
            elif kind == "op" and val == "," and depth == 1:
                break
            j += 1
        if depth != 1 or j + 2 >= len(toks):
            continue
        key, after = toks[j + 1], toks[j + 2]
        if key[0] == "str" and after[0] == "op" and after[1] in (",", ")"):
            found.append((key[1], text.count("\n", 0, key[2]) + 1))
    return found


def string_literals(text):
    """every string literal in the code (comments left out)"""
    return {v for kind, v, _ in lex(text) if kind == "str"}


def _src_files(root):
    files = glob.glob(os.path.join(root, "src", "**", "*.lua"), recursive=True)
    files += glob.glob(os.path.join(root, "src", "**", "*.luau"), recursive=True)
    return sorted(f for f in files if os.sep + MAN_REL + os.sep not in f)


def _read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def scan(root=ROOT):
    """(sites, literals): sites = {key: [(rel path, line)]} of the literal Mesh.tag keys; literals = every src string"""
    sites, literals = {}, set()
    for f in _src_files(root):
        text = _read(f)
        rel = os.path.relpath(f, root).replace(os.sep, "/")
        for key, line in tag_keys(text):
            sites.setdefault(key, []).append((rel, line))
        literals |= string_literals(text)
    return sites, literals


def has_manifest(root, key):
    return os.path.isfile(os.path.join(root, MAN_REL, key + ".lua"))


def check(root=ROOT, build_keys=BUILD_KEYS, reserved=RESERVED):
    """the problems, one line each (empty = ok)"""
    sites, literals = scan(root)
    probs = []
    for key in sorted(sites):
        if not has_manifest(root, key):
            rel, line = sites[key][0]
            count = len(sites[key])
            probs.append("(a) %s tagged at %s:%d (%d site%s) has no src/shared/MeshManifests/%s.lua"
                         % (key, rel, line, count, "" if count == 1 else "s", key))
    for key in build_keys:
        if key in reserved:
            continue
        if key not in literals:
            probs.append("(b) %s (a key this build made) is not named by any src Lua file" % key)
    return probs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--build-keys", nargs="+", default=None)
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    build = tuple(a.build_keys) if a.build_keys is not None else BUILD_KEYS
    sites, _literals = scan(root)
    if not a.check:
        for key in sorted(sites):
            rel, line = sites[key][0]
            print("%-28s %-8s %s:%d%s" % (key, "ok" if has_manifest(root, key) else "MISSING", rel, line,
                                          " (+%d)" % (len(sites[key]) - 1) if len(sites[key]) > 1 else ""))
        return
    probs = check(root, build, RESERVED)
    for p in probs:
        print("FAIL", p)
    print("mesh_keys: %d literal tag keys at %d sites, %d build keys checked (reserved, skipped: %s), %d problems"
          % (len(sites), sum(len(v) for v in sites.values()), len([k for k in build if k not in RESERVED]),
             ", ".join(RESERVED), len(probs)))
    sys.exit(1 if probs else 0)


if __name__ == "__main__":
    main()
