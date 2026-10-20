"""Kit self-test (no bpy needed: python3 + numpy + lupa).  Run after changing the kit or the sculpt code:

    python3 blender/kit/selftest.py            # ~20 s; exit 1 on any failure

Checks
  hooks       PetBuilder._Blueprint / BossBuilder._Blueprint answer (groups, grids, anchors) and change NOTHING for
              the game: PetBuilder.Build gives the same parts before and after a _Blueprint call (same mock world)
  recipes     every palette key of the golden pets fits a recipe (bridge probes)
  determinism the same key built twice gives the same contentHash, equal to the committed manifest's
  manifests   every src/shared/MeshManifests/*.lua loads in Lua and follows the name contract (recipe 4.3): Body parts
              are palette keys (+Light / Dark), group parts start with their group name, MK keys present, Fixed
              parts bake no referenced key (tools/mesh_names.py), recipes use known ops; blender/meshes.json lists
              exactly these keys with the same hashes
"""
import glob
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.dirname(HERE))
sys.dont_write_bytecode = True

RESULTS = []
OPS = {"Primary", "Secondary", "Eye", "WingColor", "rgb", "mix", "lighten", "darken", "cuteIris", "cutePupil",
       "cuteLash", "ifLum<", "shadeLight", "headroom"}


def check(cond, name, detail=""):
    RESULTS.append((bool(cond), name, detail))
    print(("ok   " if cond else "FAIL ") + name + (("  (" + str(detail) + ")") if detail else ""))


def test_hooks(br):
    rt = br.rt
    fn = rt.eval("""function()
      local Shared = game:GetService('ReplicatedStorage').Shared
      local PB = require(Shared.PetBuilder)
      local Cat = require(Shared.PetCatalog)
      local function names(m)
        local t = {}
        for _, d in ipairs(m:GetChildren()) do t[#t + 1] = d.Name .. '|' .. tostring(d.Size) .. '|' .. tostring(d.Color) end
        table.sort(t)
        return table.concat(t, ';')
      end
      local def = Cat.Get('pebble_pup')
      local a = names(PB.Build(def, { Detail = 'High' }))
      local evo = names(PB.Build(def, { Detail = 'High', Evolved = 1 }))
      PB.ClearCache()
      local bp = PB._Blueprint(def, 'High', 1.38)
      local bp2 = PB._Blueprint({ Id = def.Id, Look = def.Look, Rarity = def.Rarity, Evolved = 1 }, 'Low', 0.65)
      local b = names(PB.Build(def, { Detail = 'High' }))
      local evo2 = names(PB.Build(def, { Detail = 'High', Evolved = 1 }))
      local BB = require(Shared.BossBuilder)
      local boss = BB._Blueprint('lava_golem', 1.5)
      local nb = 0
      for _ in pairs(boss and boss.Grids or {}) do nb = nb + 1 end
      return a == b, evo == evo2, bp.K, bp.Anchors ~= nil, #bp.Groups, bp2.K, nb, boss and boss.VoxelStuds or 0
    end""")
    same, same_evo, k, anchors, ngroups, k2, nboss, bvs = fn()
    check(same, "hooks: PetBuilder.Build(pebble_pup) identical before and after _Blueprint (+ ClearCache)")
    check(same_evo, "hooks: the evolved Build identical too")
    check(abs(k - 1.38) < 1e-9 and anchors and ngroups >= 4, "hooks: _Blueprint(k = 1.38) has K, Anchors, groups", (k, ngroups))
    check(abs(k2 - 0.65) < 1e-9, "hooks: _Blueprint of an evolved form at its own k", k2)
    check(nboss >= 3 and abs(bvs - 0.5 / 1.5) < 1e-9, "hooks: BossBuilder._Blueprint grids per joint", (nboss, bvs))
    bp = br.pet("pebble_pup", k=1.38)
    names = [g.name for g in bp.groups]
    check({"Body", "WingL", "WingR", "Tail", "EyeLid"} <= set(names), "bridge: pet groups", names)
    body = bp.group("Body")
    check(len(body.keys) > 3000 and bp.anchors.get("Hat"), "bridge: body grid + Hat anchor", len(body.keys))
    wl, wr = bp.group("WingL"), bp.group("WingR")
    check(sorted(map(tuple, wl.xyz.tolist())) == sorted((-x, y, z) for x, y, z in wr.xyz.tolist()),
          "bridge: WingR is the exact mirror of WingL")


def test_recipes(br):
    from nvox.recipes import RecipeFitter
    f = RecipeFitter(br, REPO)
    for pid in ("pebble_pup", "mallow_kitten", "twilight_dragon"):
        r = f.fit(pid)
        bad = sorted(k for k, v in r.items() if not v.get("ok"))
        check(not bad, "recipes: every palette key of %s fits (%d keys)" % (pid, len(r)), bad)


def lua_table(rt, path):
    src = open(path, encoding="utf-8").read()
    rt.globals().MAN_SRC = src
    return rt.eval("function() local f, e = (loadstring or load)(MAN_SRC); if not f then error(e) end; return f() end")()


def test_determinism(br):
    import build_all
    b = build_all.Builder(export=False, verbose=False)
    b._bridge = br
    cats = build_all.load_catalogs()
    entry = dict(next(e for e in cats["pets"]["keys"] if e["key"] == "pet_dog"), _class="pets")
    budget = build_all.resolve_budget(cats["pets"], entry)
    from nvox.manifest import hashes
    h1 = hashes(b.build(entry, budget))
    h2 = hashes(b.build(entry, budget))
    check(h1 == h2, "determinism: pet_dog built twice -> same contentHash / structureHash", h1[0])
    lua = open(os.path.join(REPO, "src/shared/MeshManifests/pet_dog.lua")).read()
    m = re.search(r'ContentHash = "([0-9a-f]+)"', lua)
    check(m and m.group(1) == h1[0], "determinism: the committed pet_dog manifest is up to date (rebuild with build_all.py)",
          (m and m.group(1), h1[0]))


def walk_ops(rec, bad):
    if isinstance(rec, list) and rec and isinstance(rec[0], str):
        if rec[0] not in OPS:
            bad.add(rec[0])
        for x in rec[1:]:
            walk_ops(x, bad)


def test_manifests(br):
    import mesh_names
    from bridge import lua2py
    names = mesh_names.referenced_names(REPO)[0]
    idx = json.load(open(os.path.join(REPO, "blender/meshes.json")))["keys"]
    files = sorted(glob.glob(os.path.join(REPO, "src/shared/MeshManifests/*.lua")))
    keys = [os.path.splitext(os.path.basename(f))[0] for f in files]
    check(sorted(idx) == keys, "manifests: blender/meshes.json lists exactly the generated keys",
          sorted(set(idx) ^ set(keys)))
    for f, key in zip(files, keys):
        t = lua2py(lua_table(br.rt, f))
        probs = []
        if t.get("Key") != key:
            probs.append("Key")
        groups = t.get("Groups") or {}
        seen = set()
        for p in t.get("Parts") or []:
            n, g, k = p.get("Name"), p.get("Group"), p.get("Key")
            if n in seen:
                probs.append("dup " + n)
            seen.add(n)
            if not k:
                probs.append(n + " no Key")
            if p.get("Color") == "vertex":
                pass
            else:
                bad = set()
                walk_ops(p.get("Color"), bad)
                if bad:
                    probs.append("%s ops %s" % (n, sorted(bad)))
            if g in groups and t.get("Kind") in ("pet", "wing"):
                if not str(n).startswith(g if not g.startswith("EyeLid") else "EyeLid"):
                    probs.append("%s not named after group %s" % (n, g))
            elif t.get("Kind") == "pet" and g == "Body":
                if n != "Fixed" and not re.match("^" + re.escape(k) + "(Light|Dark)?$", n):
                    probs.append("%s is not its key %s" % (n, k))
        lua = open(f).read()
        for fk in re.findall(r'FixedKeys = \{([^}]*)\}', lua):
            for k in re.findall(r'"([^"]+)"', fk):
                if k in names:
                    probs.append("Fixed bakes referenced " + k)
        e = idx.get(key, {})
        if e.get("contentHash") != t.get("ContentHash"):
            probs.append("meshes.json hash differs")
        check(not probs, "manifests: %s (%d parts, %d tris)" % (key, len(t.get("Parts") or []), t.get("Tris") or 0),
              probs[:5])


def main():
    t0 = time.time()
    from bridge import Bridge
    br = Bridge()
    test_hooks(br)
    test_recipes(br)
    test_determinism(br)
    test_manifests(br)
    fails = [r for r in RESULTS if not r[0]]
    print("selftest: %d checks, %d failed, %.1fs" % (len(RESULTS), len(fails), time.time() - t0))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
