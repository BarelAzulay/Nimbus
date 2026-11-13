"""Kit self-test (no bpy needed: python3 + numpy + lupa).  Run after changing the kit or the sculpt code:

    python3 blender/kit/selftest.py            # ~20 s; exit 1 on any failure
    python3 blender/kit/selftest.py --only obby,props   # just those checks

Checks
  hooks       PetBuilder._Blueprint / BossBuilder._Blueprint answer (groups, grids, anchors) and change NOTHING for
              the game: PetBuilder.Build gives the same parts before and after a _Blueprint call (same mock world)
  recipes     every palette key of the golden pets fits a recipe (bridge probes)
  determinism the same key built twice gives the same contentHash, equal to the committed manifest's
  wave 2.5    the tests' by-name keys stay unbaked (Basalt / HydraHead on the event pets' evolved keys), the
              translucent closure rule of build_all.check_geometry, the hybrid ear variants (hyb_dog_ears /
              hyb_bear_ears) are picked by PetBuilder for earless bodies (a LEAD REQUEST check until runtime-pets
              adds it)
  prop hooks  every catalog prop entry names a builder registered by kit/props/*.py ("<class>: hook <name> missing")
  vfx         the pet attack VFX cores (catalog vfx): one white Neon part Core per key, args.size, manifest up to date
  obby        the obby cloud set (catalog obby): one baked part per key, built twice = the committed manifest, each
              family's fit (far / sea / underside Seat and rim / storm height under the head clearance)
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


def test_wave25():
    import mesh_names
    import numpy as np
    import build_all
    from nvox.build import ModelSpec
    names = mesh_names.referenced_names(REPO)[0]
    need = ("Basalt", "MagmaHot", "HydraHead", "HydraEye", "HydraJaw", "Frost", "CrystalDeep")
    check(all(n in names for n in need), "wave 2.5: mesh_names finds the smoke_p3_evolved signature keys",
          [n for n in need if n not in names])
    for key, part in (("evo1_magma_cub", "Basalt"), ("evo2_magma_cub", "Basalt"), ("evo1_hydralotl", "HydraHead"),
                      ("evo2_hydralotl", "HydraHead")):
        f = os.path.join(REPO, "src/shared/MeshManifests/%s.lua" % key)
        lua = open(f).read() if os.path.exists(f) else ""
        check(re.search(r'Name = "%s"' % part, lua) is not None, "wave 2.5: %s has its own %s part (not baked)" % (
            key, part))
    # a glass voxel next to an opaque one: the glass part's faces are open by design, the opaque part stays closed
    m = ModelSpec("t_glass", "prop", 1.0, 1)
    cube = lambda c, skip=(): [(np.array(q, float) + c, (1, 1, 1)) for i, q in enumerate([
        [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)], [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)],
        [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)],
        [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)], [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]]) if i not in skip]
    o = m.obj("Stone", group="G", region="Stone", shade="main", recipe=None)
    o.quads = cube(np.zeros(3))
    g = m.obj("Ice", group="G", region="Ice", shade="main", recipe=None, material="Glass")
    g.quads = cube(np.array([1.0, 0, 0]), skip=(4,))  # (the face towards the opaque cube is culled)
    check(not build_all.Builder.check_geometry(m), "wave 2.5: check_geometry skips see-through parts in the closure",
          build_all.Builder.check_geometry(m))
    o.quads = o.quads[1:]
    check(build_all.Builder.check_geometry(m), "wave 2.5: check_geometry still catches an open opaque part")
    pb = open(os.path.join(REPO, "src/shared/PetBuilder.lua")).read()
    ears = [k for k in ("hyb_dog_ears", "hyb_bear_ears")
            if os.path.exists(os.path.join(REPO, "src/shared/MeshManifests/%s.lua" % k))]
    check(not ears or "_ears" in pb, "LEAD REQUEST (runtime-pets): PetBuilder picks hyb_<style>_ears for an earless body "
          "(PetBuilder.lua MESH.makePlan ~:6991, see the fix-kit wave 2.5 report)", ears)


def test_prop_hooks():
    """every prop entry of every catalog names a builder that kit/props/*.py registers"""
    import build_all
    import props
    reg = props.load_all()
    for cls, cat in build_all.load_catalogs().items():
        for name in sorted({e["prop"] for e in cat.get("keys", []) if e.get("type") == "prop"}):
            check(name in reg, "%s: hook %s %s" % (cls, name, "registered" if name in reg else "missing"))


def test_vfx(br):
    """pet attack VFX cores (catalog vfx): ONE white Neon MeshPart `Core` per key, the design size of args.size
    (per axis, 'max' = the largest axis; +-1 voxel or 4%), and the committed manifest = a fresh build"""
    import build_all
    import props
    from bridge import lua2py
    from nvox.manifest import hashes
    cats = build_all.load_catalogs()
    cat = cats.get("vfx")
    check(cat is not None, "vfx: catalog blender/catalog/vfx.json")
    if cat is None:
        return
    hooked = "vfx_cores" in props.load_all()
    b = build_all.Builder(export=False, verbose=False)
    for e in cat["keys"]:
        key = e["key"]
        f = os.path.join(REPO, "src/shared/MeshManifests/%s.lua" % key)
        if not os.path.exists(f):
            check(False, "vfx: %s manifest built" % key, "no src/shared/MeshManifests/%s.lua" % key)
            continue
        t = lua2py(lua_table(br.rt, f))
        parts = t.get("Parts") or []
        p = parts[0] if parts else {}
        check(len(parts) == 1 and p.get("Name") == "Core" and p.get("Color") == ["rgb", 255, 255, 255]
              and p.get("Material") == "Neon", "vfx: %s is one white Neon part Core" % key,
              [(q.get("Name"), q.get("Color"), q.get("Material")) for q in parts])
        size = t["Bounds"]["Size"]
        vs = float(t.get("VoxelStuds") or 0.1)
        bad = []
        for axis, want in (e.get("args") or {}).get("size", {}).items():
            got = max(size) if axis == "max" else size["xyz".index(axis)]
            if abs(got - want) > max(vs * 1.01, 0.04 * want):
                bad.append("%s %.3f != %s" % (axis, got, want))
        check(not bad, "vfx: %s size %s" % (key, "x".join("%.2f" % s for s in size)), bad)
        if hooked:
            entry = dict(e, _class="vfx")
            h = hashes(b.build(entry, build_all.resolve_budget(cat, entry)))[0]
            check(h == t.get("ContentHash"), "vfx: %s committed manifest = a fresh build" % key, (t.get("ContentHash"), h))


def obby_config():
    """the obby numbers the cloud set must fit (Config.Course): Clearance and Clouds.StormBase"""
    src = open(os.path.join(REPO, "src/shared/Config.lua"), encoding="utf-8").read()
    clear = re.search(r"^\tClearance = ([0-9.]+)", src, re.M)
    base = re.search(r"\bStormBase = ([0-9.]+)", src)
    return float(clear.group(1)) if clear else 13.0, float(base.group(1)) if base else 4.5


def test_obby(br):
    """the obby cloud set (catalog obby, kit/props/obby.py, kit-b B1): one baked SmoothPlastic part `Cloud` per key,
    the committed manifest = a fresh build (built twice: same hash), and each family fits where the OBBY lane puts it:
    far cumulus 60-120 studs wide with a flat base under the pivot; the sea flat and wide; an underside's rim one voxel
    over its Seat (the slab's underside) so at scale 1.4 it stays 0.5 under a 2-stud slab's top; the storm cloud short
    enough to sit StormBase over a step at scale 1 under the head clearance (CourseBuilder Mesh.storm)"""
    import build_all
    import props
    from bridge import lua2py
    from nvox.manifest import hashes
    cat = build_all.load_catalogs().get("obby")
    check(cat is not None, "obby: catalog blender/catalog/obby.json")
    if cat is None:
        return
    hooked = "obby_cloud" in props.load_all()
    check(hooked, "obby: prop obby_cloud registered (kit/props/obby.py)")
    clear, base = obby_config()
    b = build_all.Builder(export=False, verbose=False)
    b._bridge = br
    for e in cat["keys"]:
        key = e["key"]
        f = os.path.join(REPO, "src/shared/MeshManifests/%s.lua" % key)
        if not os.path.exists(f):
            check(False, "obby: %s manifest built" % key, "no src/shared/MeshManifests/%s.lua" % key)
            continue
        t = lua2py(lua_table(br.rt, f))
        parts = t.get("Parts") or []
        check(len(parts) == 1 and parts[0].get("Name") == "Cloud" and parts[0].get("Color") == "vertex"
              and parts[0].get("Material") == "SmoothPlastic", "obby: %s is one baked SmoothPlastic part Cloud" % key,
              [(q.get("Name"), q.get("Color"), q.get("Material")) for q in parts])
        lo, hi, size = t["Bounds"]["Min"], t["Bounds"]["Max"], t["Bounds"]["Size"]
        vs = float(t.get("VoxelStuds") or 1)
        if key.startswith("cloud_obby_far_"):
            check(60 - vs <= size[0] <= 120 + vs and lo[1] < 0 < hi[1] and size[1] < size[0],
                  "obby: %s a cumulus 60-120 wide, base under the pivot" % key, (size, lo[1], hi[1]))
        elif key.startswith("cloud_obby_sea_"):
            check(size[0] >= 100 and size[1] <= 0.3 * size[0] and 0 < hi[1] <= vs * 3.01,
                  "obby: %s a flat wide sea deck (billows at most 3 voxels over the pivot)" % key, (size, hi[1]))
        elif key.startswith("cloud_obby_under_"):
            seat = (t.get("Attachments") or {}).get("Seat")
            check(seat is not None and all(abs(v) < 1e-6 for v in seat["Pos"]), "obby: %s Seat at the pivot" % key, seat)
            check(0 < hi[1] <= vs + 1e-6 and hi[1] * 1.4 <= 2 - 0.5,
                  "obby: %s rim one voxel over the Seat, under a 2-stud slab's top at scale 1.4" % key, hi[1])
        elif key == "obby_storm_cloud":
            check(abs(lo[1]) < 1e-6 and size[1] <= clear - base - 0.4 and 12 <= size[0] <= 16,
                  "obby: %s 12-16 wide, base at the pivot, fits StormBase %.1f under Clearance %g at scale 1" % (
                      key, base, clear), size)
        if hooked:
            from props import obby
            design, V = e["args"]["design"], float(e["args"]["V"])
            raw = obby.design_cells(design, V)
            ps = obby.pieces(raw)
            # the build keeps only the biggest piece; the design itself must not lean on that (a stray voxel or two)
            check(ps and len(raw) - len(ps[0]) <= max(2, len(raw) // 200),
                  "obby: %s one solid piece (%d voxels, %d would float)" % (key, len(raw), len(raw) - len(ps[0]) if ps else 0))
            entry = dict(e, _class="obby")
            budget = build_all.resolve_budget(cat, entry)
            h1 = hashes(b.build(entry, budget))[0]
            h2 = hashes(b.build(entry, budget))[0]
            check(h1 == h2 == t.get("ContentHash"), "obby: %s built twice = the committed manifest" % key,
                  (t.get("ContentHash"), h1, h2))


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma list of checks: hooks, recipes, determinism, wave25, props, vfx, obby, manifests")
    a = ap.parse_args()
    only = set(a.only.split(",")) if a.only else None
    t0 = time.time()
    from bridge import Bridge
    br = Bridge()
    for name, fn in (("hooks", test_hooks), ("recipes", test_recipes), ("determinism", test_determinism),
                     ("wave25", lambda _: test_wave25()), ("props", lambda _: test_prop_hooks()), ("vfx", test_vfx),
                     ("obby", test_obby), ("manifests", test_manifests)):
        if only is None or name in only:
            fn(br)
    fails = [r for r in RESULTS if not r[0]]
    print("selftest: %d checks, %d failed, %.1fs" % (len(RESULTS), len(fails), time.time() - t0))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
