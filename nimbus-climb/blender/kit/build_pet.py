"""Build one pet SPECIES mesh set (body + tail + lids), its wing style and an accessory, from a catalog Look.

    /tmp/claude-0/bpyenv/bin/python build_pet.py --pet pebble_pup --height 40 --out OUT
    /tmp/claude-0/bpyenv/bin/python build_pet.py --species Cat --K 1.4 --out OUT --no-render

Writes per model:  <model>.fbx  <model>.manifest.json  and one assembled preview <pet>_preview.png
Models:  pet_<species>  (Body + Tail_ + Lid_ parts),  wing_<style> (WingL_ / WingR_ parts),  acc_<name>.
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402

from nvox import colors as C  # noqa: E402
from nvox.build import ModelSpec, add_grid, bounds_of  # noqa: E402
from nvox.catalog import parse_catalog, sample_look  # noqa: E402
from nvox.grid import VoxelGrid, angles  # noqa: E402
from nvox.manifest import cf_json, write_manifest  # noqa: E402
from nvox.pets import ACCESSORIES, FLAT_KEYS, WINGS, build_species  # noqa: E402

REPO = "/home/user/roblox/nimbus-climb"
DESIGN_STUDS = 0.1
DESIGN_HEIGHT = 29.0  # today's pets: about 29 design units from the paws to the ear tips


def mirror_R(R):
    M = np.diag([-1.0, 1.0, 1.0])
    return M @ R @ M


def build_models(look, K, wing_style=None, accessory=None):
    ctx = build_species(look, K)
    vs = DESIGN_STUDS / K
    sp = look["Species"]
    body = ModelSpec("pet_" + sp.lower(), "species", vs, K)
    shade_default = dict(light_at=0.6, dark_at=-0.4, crease=0.18)
    add_grid(body, ctx.body, ctx.rec, look, group="Body", shade_opts=ctx.shade_opts, flat=FLAT_KEYS,
             shade_default=shade_default)
    # snap the tail hinge to the body's voxel lattice, then drop the tail voxels that sit inside the body: no
    # coincident / near-coincident faces between the two meshes (z-fighting, dark slits); the tail root hides in
    # the body when it wags
    hv = [int(round(v * K)) for v in ctx.tail_hinge]
    ctx.tail_hinge = [v / K for v in hv]
    th = np.asarray(ctx.tail_hinge, float) * DESIGN_STUDS
    if ctx.tail is not None:
        t, b = ctx.tail, ctx.body
        for (i, j, k) in np.argwhere(t.L != 0):
            x, y, z = i - t.half + hv[0], j - t.half + hv[1], k - t.half + hv[2]
            if b.get(x, y, z) is not None:
                t.L[i, j, k] = 0
        add_grid(body, ctx.tail, ctx.rec, look, group="Tail", prefix="Tail_", offset=th, shade_opts=ctx.shade_opts,
                 flat=FLAT_KEYS, shade_default=shade_default)
        body.groups["Tail"] = {"kind": "tail", "hinge": [round(float(v), 4) for v in th], "amp": ctx.tail_wag,
                               "parts": sorted(n for n in body.objects if n.startswith("Tail_"))}
    # blink lids: the voxels the eye carving removed (hidden in game except during a blink)
    lid = VoxelGrid(K, half=ctx.body.half, name="Lids")
    for cells in ctx.lid_cells:
        for (x, y, z, was) in cells:
            lid.set(x, y, z, was or "Fur")
    add_grid(body, lid, ctx.rec, look, group="Lid", prefix="Lid_", shade=False, fixed=False)
    body.groups["Lid"] = {"kind": "blink", "hiddenByDefault": True,
                          "parts": sorted(n for n in body.objects if n.startswith("Lid_"))}
    # attachments (roblox studs, relative to the pivot = design origin)
    wh = np.asarray(ctx.wing_hinge, float)
    R_R = angles(0, -ctx.wing_sweep, 0) @ angles(0, 0, ctx.wing_tilt)
    body.attachments = {
        "WingR": cf_json(R_R, wh * DESIGN_STUDS),
        "WingL": cf_json(mirror_R(R_R), np.array([-wh[0], wh[1], wh[2]]) * DESIGN_STUDS),
        "Tail": cf_json(np.eye(3), th),
        "Hat": cf_json(np.eye(3), np.array([0, ctx.head_top, ctx.head_c[2]]) * DESIGN_STUDS),
        "Flower": cf_json(np.eye(3), np.asarray(ctx.flower_at) * DESIGN_STUDS),
        "Neck": cf_json(np.eye(3), np.array([0, ctx.neck_y, ctx.neck_z]) * DESIGN_STUDS),
        "HeadCenter": cf_json(np.eye(3), np.asarray(ctx.head_c) * DESIGN_STUDS),
    }
    for i, (cx, cy, rx, ry, kind) in enumerate(ctx.eyes):
        for s, nm in ((1, "EyeR"), (-1, "EyeL")):
            z = ctx.body.front_z(ctx.body.vx(cx * s), ctx.body.vx(cy))
            body.attachments[nm] = cf_json(np.eye(3), np.array([cx * s, cy, (z if z is not None else 0) / K]) * DESIGN_STUDS)
    if ctx.horn_base:
        body.attachments["HornBase"] = cf_json(np.eye(3), np.asarray(ctx.horn_base) * DESIGN_STUDS)
    lo, hi = bounds_of(body)
    body.attachments["Ground"] = cf_json(np.eye(3), np.array([0.0, lo[1], 0.0]))
    body.meta = {"species": sp, "lookFrom": look.get("Id"), "wingTilt": ctx.wing_tilt, "wingSweep": ctx.wing_sweep,
                 "voxelsTall": round(float(hi[1] - lo[1]) / vs, 1)}

    models = [body]
    # wing style: the LEFT wing from the grid (reaches -X), the right one its mirror image
    wing_style = wing_style or look.get("WingStyle") or "Feather"
    if wing_style in WINGS:
        WINGS[wing_style](ctx, ctx.wing)
        wing = ModelSpec("wing_" + wing_style.lower(), "wing", vs, K)
        wopts = {k: dict(light_at=0.5) for k in ctx.wing.keys if k}
        add_grid(wing, ctx.wing, ctx.rec, look, group="WingL", prefix="WingL_", shade_opts=wopts, flat=FLAT_KEYS,
                 shade_default=dict(light_at=0.5))
        add_grid(wing, ctx.wing.mirror_x(), ctx.rec, look, group="WingR", prefix="WingR_", shade_opts=wopts,
                 flat=FLAT_KEYS, shade_default=dict(light_at=0.5))
        wing.groups = {"WingL": {"kind": "flap", "attach": "WingL", "parts": sorted(n for n in wing.objects if n.startswith("WingL_"))},
                       "WingR": {"kind": "flap", "attach": "WingR", "parts": sorted(n for n in wing.objects if n.startswith("WingR_"))}}
        wing.meta = {"style": wing_style, "pivot": "each half's hinge (the species' WingL / WingR attachment)"}
        models.append(wing)
    if accessory and accessory in ACCESSORIES:
        g, rec = ACCESSORIES[accessory](K)
        acc = ModelSpec("acc_" + accessory.lower(), "accessory", vs, K)
        add_grid(acc, g, rec, look, group="Accessory", shade_opts={"Gold": dict(light_at=0.5, crease=0.2)},
                 flat=("Gem", "GemB", "Spark"), shade_default=dict(light_at=0.5))
        acc.meta = {"accessory": accessory, "attach": "Hat", "pivot": "base centre of the band (= the Hat attachment)"}
        models.append(acc)
    return ctx, models


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pet", help="catalog id (its Look)")
    ap.add_argument("--species", help="species with the neutral sample look")
    ap.add_argument("--K", type=float, help="voxels per design unit (1 = today's game grain)")
    ap.add_argument("--height", type=float, help="target voxels tall (sets K = height / 29)")
    ap.add_argument("--wing", default=None)
    ap.add_argument("--acc", default="Crown")
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", default="")
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--no-export", action="store_true")
    ap.add_argument("--res", type=int, default=480)
    a = ap.parse_args()
    if a.pet:
        look = parse_catalog(os.path.join(REPO, "src/shared/PetCatalog.lua"))[a.pet]["Look"]
    else:
        look = sample_look(a.species)
    K = a.K or (a.height / DESIGN_HEIGHT if a.height else 1.4)
    t0 = time.time()
    ctx, models = build_models(look, K, a.wing, a.acc)
    t_build = time.time() - t0
    os.makedirs(a.out, exist_ok=True)
    summary = {"pet": a.pet or a.species, "K": K, "buildSeconds": round(t_build, 2), "models": {}}
    for m in models:
        summary["models"][m.name] = {"tris": m.tris(), "parts": len(m.objects), "stats": m.stats.get("grids")}
    if a.no_export:
        print(json.dumps(summary, indent=1))
        return

    from nvox import blend as B  # bpy only from here on
    tag = a.tag
    for m in models:
        B.reset_scene()
        objs = B.make_objects(m, look)
        fbx = os.path.join(a.out, m.name + tag + ".fbx")
        size = B.export_fbx(objs, fbx)
        ver = B.verify_fbx(fbx, m)
        ver["bytes"] = size
        write_manifest(m, look, os.path.join(a.out, m.name + tag + ".manifest.json"), os.path.basename(fbx), ver,
                       extra={"previewLook": {k: (C.to255(v) if isinstance(v, tuple) else v) for k, v in look.items()}})
        summary["models"][m.name]["verify"] = ver
    if not a.no_render:
        B.reset_scene()
        B.setup_render(a.res)
        body = models[0]
        made = B.make_objects(body, look)
        att = body.attachments
        for m in models[1:]:
            if m.kind == "wing":
                for side in ("WingL", "WingR"):
                    sub = type(m)(m.name, m.kind, m.voxel_studs, m.K)
                    sub.objects = {k: v for k, v in m.objects.items() if k.startswith(side + "_")}
                    a_ = att[side]
                    made += B.make_objects(sub, look, matrix=B.cf_to_bl(a_["rot"], a_["pos"]))
            else:
                a_ = att["Hat"]
                made += B.make_objects(m, look, matrix=B.cf_to_bl(a_["rot"], a_["pos"]))
        for ob in made:
            if ob.name.startswith("Lid_"):
                ob.hide_render = True
        pts = np.array([list(ob.matrix_world @ v.co) for ob in made if not ob.hide_render for v in ob.data.vertices])
        lo_bl, hi_bl = pts.min(0), pts.max(0)
        # back to roblox for the helper
        lo_r, hi_r = B.PM @ lo_bl, B.PM @ hi_bl
        png = os.path.join(a.out, (a.pet or a.species.lower()) + tag + "_preview.png")
        B.render_views((np.minimum(lo_r, hi_r), np.maximum(lo_r, hi_r)), png, res=a.res)
        summary["preview"] = png
    summary["seconds"] = round(time.time() - t0, 1)
    with open(os.path.join(a.out, (a.pet or a.species.lower()) + tag + "_summary.json"), "w") as f:
        json.dump(summary, f, indent=1)
    print(json.dumps({k: v for k, v in summary.items() if k != "models"}, indent=1))
    for n, m in summary["models"].items():
        print(n, "tris", m["tris"], "parts", m["parts"], "verify", m.get("verify", {}).get("ok"), m.get("verify", {}).get("problems"))


if __name__ == "__main__":
    main()
