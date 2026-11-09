#!/usr/bin/env python3
"""Offline tests of tools/mesh_keys.py (lobby-shop Task 29, spec 8: every Mesh.tag key in src has a manifest, every
key this build made is named in src).

Everything runs on strings or in temp folders (fake game roots with src/ and src/shared/MeshManifests/); the real
src/ is never read here (the real `mesh_keys.py --check` is a gate step). Exit code 0 = all passed.

    py -3.12 tools/test_mesh_keys.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import mesh_keys as MK  # noqa: E402

FAILS = []


def check(cond, label, detail=""):
    if cond:
        print("PASS", label)
    else:
        print("FAIL", label, detail)
        FAILS.append(label)


def keys_of(text):
    return [k for k, _line in MK.tag_keys(text)]


# ---------------------------------------------------------------------------------------------- (a) the tag scan
def test_plain_tags():
    text = 'Mesh.tag(m, "prop_banner", cf, { Primary = color })\n\tH.Mesh.tag(model, "prop_board_lb", cf, nil, { "Face" })\n'
    check(keys_of(text) == ["prop_banner", "prop_board_lb"], "plain literal keys, H.Mesh.tag included", keys_of(text))
    check([ln for _k, ln in MK.tag_keys(text)] == [1, 2], "each tag site keeps its line number", MK.tag_keys(text))


def test_nested_target():
    text = ('Mesh.tag(Art.tag(place(planter(), pcf, m, "Planter"), "Detail"), "arena_planter", pcf)\n'
            'Mesh.tag(Art.hedgeBox(m, hcf, 5, i * 7 + sx), "arena_hedge", hcf)\n')
    check(keys_of(text) == ["arena_planter", "arena_hedge"], "a target with nested calls and strings: the second argument is the key", keys_of(text))


def test_skips_non_literals():
    text = "\n".join([
        'Mesh.tag(m, "arena_ring_" .. index, cf)',                 # a prefix followed by ..
        'Mesh.tag(rock, "dungeon_rock_"..shape, cf)',              # ... with no spaces
        'Mesh.tag(m, key, cf, look)',                              # a variable
        'Mesh.tag(parent, Mesh.key("dungeon_torch"), cf)',         # a call
        'Mesh.tag(m, (name == "EventBoard") and "a" or "b", cf)',  # an expression
        'function Mesh.tag(target, key, origin, look, keep)',      # the definition
        'Mesh.tag(target, t[2], A, nil, t[3])',                    # an index
    ])
    check(keys_of(text) == [], "prefixes, variables, calls, expressions and the definition are not literal keys", keys_of(text))


def test_comments_and_strings():
    text = "\n".join([
        '-- Mesh.tag(model, "commented_key", cf)',
        '--[[ Mesh.tag(m, "block_key", cf) ]]',
        '--[==[ Mesh.tag(m, "level_key", cf) ]] still a comment ]==]',
        'local s = "a -- b"; Mesh.tag(m, \'single_key\', cf) -- trailing',
        'local t = [[ Mesh.tag(m, "long_string_key", cf) ]]',
        'Mesh.tag(m, "last_key")',
    ])
    check(keys_of(text) == ["single_key", "last_key"], "comments and long strings hide tags; -- inside a string is no comment; single quotes count", keys_of(text))


def test_string_literals():
    text = 'local EGG = { Common = "egg_common" } -- "egg_rare" in a comment\nlocal x = \'gem_world\' .. "_suffix"\n'
    lits = MK.string_literals(text)
    check("egg_common" in lits and "gem_world" in lits and "_suffix" in lits, "string literals in code are collected", sorted(lits))
    check("egg_rare" not in lits, "a key named only in a comment is not a literal", sorted(lits))


# ---------------------------------------------------------------------------------------------- the check on a fake root
def fake_root(files):
    root = tempfile.mkdtemp(prefix="mesh_keys_")
    for rel, body in files.items():
        p = os.path.join(root, *rel.split("/"))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(body)
    return root


def test_check_problems():
    root = fake_root({
        "src/server/A.lua": 'Mesh.tag(m, "has_man", cf)\nMesh.tag(m, "no_man", cf)\nMesh.tag(n, "no_man", cf)\n',
        "src/client/B.lua": 'local K = "built_named"\n-- "built_comment"\n',
        "src/shared/MeshManifests/has_man.lua": 'return { Key = "has_man" }\n',
        "src/shared/MeshManifests/built_unnamed.lua": 'return { Key = "built_unnamed" }\n',
    })
    try:
        probs = MK.check(root, build_keys=("built_named", "built_comment", "built_unnamed", "built_reserved"),
                         reserved=("built_reserved",))
    finally:
        shutil.rmtree(root, ignore_errors=True)
    tagged = [p for p in probs if "no_man" in p]
    check(len(tagged) == 1 and "src/server/A.lua:2" in tagged[0] and "2 sites" in tagged[0],
          "(a) a key tagged twice with no manifest is ONE problem, naming its first site and the count", probs)
    check(not any("has_man" in p for p in probs), "(a) a tagged key with a manifest passes", probs)
    named = sorted(p.split()[1] for p in probs if p.startswith("(b)"))
    check(named == ["built_comment", "built_unnamed"],
          "(b) a build key named only in a comment or only in its own manifest is a problem; a named key and a reserved one pass", probs)
    check(len(probs) == 3, "exactly three problems on the fake root", probs)


def test_cli_exit_codes():
    good = fake_root({"src/A.lua": 'Mesh.tag(m, "k1", cf)\nlocal B = { "b1" }\n',
                      "src/shared/MeshManifests/k1.lua": "return {}\n"})
    bad = fake_root({"src/A.lua": 'Mesh.tag(m, "k2", cf)\n'})
    try:
        cmd = [sys.executable, os.path.join(HERE, "mesh_keys.py"), "--check", "--build-keys", "b1", "--root"]
        g = subprocess.run(cmd + [good], capture_output=True, text=True)
        b = subprocess.run(cmd + [bad], capture_output=True, text=True)
    finally:
        shutil.rmtree(good, ignore_errors=True)
        shutil.rmtree(bad, ignore_errors=True)
    check(g.returncode == 0 and "0 problems" in g.stdout, "--check exits 0 with no problems", g.stdout + g.stderr)
    blines = [ln for ln in b.stdout.splitlines() if ln.startswith("FAIL")]
    check(b.returncode == 1 and len(blines) == 2, "--check exits 1 and prints each problem on its own line", b.stdout + b.stderr)


def test_constants():
    rar = ["common", "uncommon", "rare", "epic", "legendary", "mythic", "secret"]
    want = ["egg_" + r for r in rar] + ["gem_world", "portal_ring", "portal_altar_ring", "prop_board_lb"]
    # (egg-3d) the 14 halves of the hatch cutscene's crack (catalog hatch: GUI-only, named by client/UI/Egg3D)
    want += ["egg_%s_%s" % (r, h) for r in rar for h in ("top", "bot")]
    # (shop-area 16.17.1) the Gumball Globe roulette machine (named by server/Services/LobbyMachineBuilder)
    want += ["prop_roulette_globe"]
    # (shop-area polish) the globe pile's seven low-poly eggs (named by server/Services/LobbyMachineBuilder PILE_KEYS);
    # review round 2: "_pile", not "_low": MeshLibrary.LowKey reads "<key>_low" as that key's LOD twin
    want += ["egg_%s_pile" % r for r in rar]
    check(list(MK.BUILD_KEYS) == want, "BUILD_KEYS are the plan's eleven keys + egg-3d's fourteen halves + the shop-area globe + its seven pile eggs", MK.BUILD_KEYS)
    check(list(MK.RESERVED) == ["gem_world_low"], "RESERVED is gem_world_low", MK.RESERVED)


def test_no_false_lod_twin():
    # MeshLibrary.LowKey(key) / dump_model / mesh_budget --lod read "<key>_low" as key's LOD twin (SetLod "Low" rebuilds
    # the target from it): a build key of another layout must not take that name (review round 2: the pile eggs)
    keys = set(MK.BUILD_KEYS)
    twins = sorted(k for k in keys if k.endswith("_low") and k[:-4] in keys)
    check(not twins, "no build key is named <another build key>_low (that is the LOD-twin name)", twins)


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
            except Exception as exc:  # a crash is a failure of that test
                print("FAIL", name, "raised", repr(exc))
                FAILS.append(name)
    print("test_mesh_keys: %d failed" % len(FAILS))
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
