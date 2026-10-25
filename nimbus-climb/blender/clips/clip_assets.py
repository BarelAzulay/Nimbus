"""Clip assets: every pet, boss, coin, gate and station of the story clip, built by the game's REAL Blender builders.

    from clip_assets import load_specs, spawn
    specs = load_specs()                      # {asset: [(ModelSpec, attach-name-or-None), ...]}, cached in .cache/
    root = spawn("dragon2", specs, collection) # an Empty with the asset's mesh objects parented under it

Read-only use of the game: `build_all.Builder(export=False).make(entry, k)` (pets / wings / bosses / props, through
kit/bridge.py and the props registry) and `nvox.blend.make_objects`.  Nothing is written to blender/out, the
MeshManifests or meshes.json (CLIP_RULES.md rule 1); the built ModelSpecs are pickled to blender/clips/.cache/.
"""
import hashlib
import json
import os
import pickle
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER_DIR = os.path.dirname(HERE)
REPO = os.path.dirname(BLENDER_DIR)
CACHE = os.path.join(HERE, ".cache")
for p in (os.path.join(BLENDER_DIR, "kit"), os.path.join(REPO, "tools"), BLENDER_DIR):
    if p not in sys.path:
        sys.path.insert(0, p)
sys.dont_write_bytecode = True


def _catalog():
    import build_all
    out = {}
    for cat in build_all.load_catalogs().values():
        for e in cat["keys"]:
            e = dict(e)
            e["_class"] = cat.get("class")
            out[e["key"]] = e
    return out


def _pet(key, pet, k, **kw):
    e = {"key": key, "type": "pet", "pet": pet, "k": k, "passes": ["pets:cute"]}
    e.update(kw)
    return e


def _wing(key, pet, side, k, **kw):
    e = {"key": key, "type": "wing", "pet": pet, "side": side, "k": k}
    e.update(kw)
    return e


# asset -> [(catalog key or a full entry dict, attachment on the first spec or None)]
# The stage-0 pets keep their accessory (no "strip"): the same look the game shows for that pet.
ASSETS = {
    "dragon0": [(_pet("clip_cloudy_dragon", "cloudy_dragon", 1.38), None),
                (_wing("clip_cloudy_wing_L", "cloudy_dragon", "L", 1.38), "WingL"),
                (_wing("clip_cloudy_wing_R", "cloudy_dragon", "R", 1.38), "WingR")],
    "dragon2": [("evo2_cloudy_dragon", None),
                ("evowing_cloudy_dragon_2_L", "WingL"), ("evowing_cloudy_dragon_2_R", "WingR"),
                ("evowing_cloudy_dragon_2b_L", "Wing2L"), ("evowing_cloudy_dragon_2b_R", "Wing2R")],
    "stormfang": [(_pet("clip_stormfang", "stormfang", 1.38), None),
                  ("wing_stormcloud_L", "WingL"), ("wing_stormcloud_R", "WingR")],
    "hydra": [("boss_shadow_hydra_Body", None), ("boss_shadow_hydra_Head1", "joint"),
              ("boss_shadow_hydra_Head2", "joint"), ("boss_shadow_hydra_Head3", "joint")],
    "cash": [("token_cash", None)],
    "lucky": [("token_goldencash", None)],
    "altar": [("cloud_altar", None), ("prop_altar_ring", None), ("prop_altar_portal", None),
              ("prop_altar_crystals", None), ("prop_altar_sign", None), ("floor_altar_bridge", None),
              ("floor_junction_altar", None)],
    "gate_altar": [("gate_altar", None)],
    "garden": [("home_garden_4", None)],
    "foodmachine": [("home_foodmachine_3", None)],
    "arena": [("arena_floor", None), ("arena_seg_stand", None), ("arena_seg_gate", None),
              ("arena_seg_bossgate", None), ("arena_pillar", None), ("arena_torch", None)],
    "cloud_step": [("cloud_platform_ref", None)],
    "plot": [("prop_plot", None)],
    "star": [("star_gold", None)],
}


def _entry(ref, cat):
    if isinstance(ref, dict):
        return ref
    if ref == "cloud_platform_ref":  # the obby's cloud step (props/reference.py, the game's cloud platform)
        return {"key": "clip_cloud_step", "type": "prop", "prop": "cloud_platform", "args": {"K": 1.5}}
    return cat[ref]


def _kit_stamp():
    """cache key: the kit + src sources the builders read (any edit there rebuilds the cache)"""
    h = hashlib.sha1()
    for base in (os.path.join(BLENDER_DIR, "kit"), os.path.join(BLENDER_DIR, "catalog"), os.path.join(REPO, "src", "shared")):
        for root, _, files in os.walk(base):
            for f in sorted(files):
                if f.endswith((".py", ".lua", ".json")):
                    st = os.stat(os.path.join(root, f))
                    h.update(("%s%d%d" % (f, st.st_size, int(st.st_mtime))).encode())
    return h.hexdigest()[:12]


def load_specs(names=None, rebuild=False, verbose=True):
    os.makedirs(CACHE, exist_ok=True)
    stamp = _kit_stamp()
    path = os.path.join(CACHE, "specs_%s.pkl" % stamp)
    have = {}
    if os.path.exists(path) and not rebuild:
        with open(path, "rb") as fh:
            have = pickle.load(fh)
    want = names or list(ASSETS)
    missing = [n for n in want if n not in have]
    if missing:
        import build_all
        cat = _catalog()
        b = build_all.Builder(export=False, verbose=False)
        for n in missing:
            t0 = time.time()
            parts = []
            for ref, att in ASSETS[n]:
                e = _entry(ref, cat)
                parts.append((b.make(e, float(e.get("k", 1.0))), att))
            have[n] = parts
            if verbose:
                print("[clip_assets] built %-12s %5.1fs  %d tris" % (n, time.time() - t0, sum(m.tris() for m, _ in parts)))
        with open(path, "wb") as fh:
            pickle.dump(have, fh)
    return {n: have[n] for n in want}


def look_of(spec):
    from nvox import colors as C
    look = {a: C.rgb(*v) for a, v in (spec.meta.get("previewLook") or {}).items()}
    if "WingColor" not in look and "Primary" in look:
        look["WingColor"] = C.lighten(look["Primary"], 0.4)
    return look


def spawn(name, specs, collection, prefix=None):
    """Build Blender objects for an asset. Returns (root Empty, {group name: [objects]}, {attachment: Matrix}).
    Group objects (Tail, Aura, Halo, wings, boss heads) are parented to their own pivot Empties so they can be
    animated about their hinge."""
    import bpy
    from mathutils import Matrix
    from nvox import blend as B
    prefix = prefix or name
    root = bpy.data.objects.new(prefix, None)
    root.empty_display_size = 1
    collection.objects.link(root)
    groups = {}
    parts = specs[name]
    body = parts[0][0]
    look = look_of(body)
    atts = {}
    for nm, a in (getattr(body, "attachments", None) or {}).items():
        atts[nm] = Matrix(B.cf_to_bl(a["rot"], a["pos"]).tolist())
    for spec, att in parts:
        if att == "joint":
            mat = Matrix.Translation(B.to_bl(spec.meta["pivotStuds"]).tolist())
        elif att:
            mat = atts.get(att)
            if mat is None:
                continue
        else:
            mat = None
        pivot = bpy.data.objects.new("%s_%s" % (prefix, spec.name), None)
        pivot.empty_display_size = 0.3
        collection.objects.link(pivot)
        pivot.parent = root
        if mat is not None:
            pivot.matrix_parent_inverse = Matrix.Identity(4)
            pivot.matrix_basis = mat
        made = B.make_objects(spec, look_of(spec) if spec.meta.get("previewLook") else look, collection=collection)
        for ob, g in zip(made, spec.objects.values()):  # make_objects keeps the spec order
            ob.name = "%s_%s_%s" % (prefix, spec.name, g.name)
            ob["clip_material"] = g.material
            ob["clip_region"] = g.region or ""
            ob.parent = pivot
            gname = g.group
            if att and att != "joint":
                gname = att
            elif att == "joint":
                gname = spec.meta.get("joint", spec.name)
            groups.setdefault(gname, []).append(ob)
        groups.setdefault("_pivot_" + (att or spec.name), []).append(pivot)
    # hinge pivots for the body's animated groups (Tail wag, Aura orbit, Halo bob), so they turn about their hinge
    for gname, g in (getattr(body, "groups", None) or {}).items():
        h = g.get("hinge") if isinstance(g, dict) else None
        obs = groups.get(gname)
        if not h or not obs or gname in ("Body",) or gname.startswith("EyeLid"):
            continue
        hm = Matrix(B.cf_to_bl(h["rot"], h["pos"]).tolist())
        hp = bpy.data.objects.new("%s_hinge_%s" % (prefix, gname), None)
        hp.empty_display_size = 0.3
        collection.objects.link(hp)
        hp.parent = obs[0].parent
        hp.matrix_basis = hm
        for ob in obs:
            ob.parent = hp
            ob.matrix_parent_inverse = hm.inverted()
        groups["_hinge_" + gname] = [hp]
    return root, groups, atts


if __name__ == "__main__":
    t = time.time()
    s = load_specs(rebuild="--rebuild" in sys.argv)
    for n, parts in s.items():
        for m, att in parts:
            print("%-12s %-30s %-7s tris %6d parts %3d groups %s" % (n, m.name, att, m.tris(), len(m.objects),
                                                                   sorted({o.group for o in m.objects.values()})))
    print("total %.1fs" % (time.time() - t))
