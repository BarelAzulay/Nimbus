"""World kit pieces -> FBX + manifest + preview (same pipeline as the pets).

    /tmp/claude-0/bpyenv/bin/python build_prop.py portal --color 226,150,74 --stars 3 --K 2 --out OUT
    /tmp/claude-0/bpyenv/bin/python build_prop.py cloud --K 1.5 --out OUT
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
from nvox.manifest import cf_json, write_manifest  # noqa: E402
from nvox.props import P4, PAD_SHIFT, cloud_platform, portal  # noqa: E402


def build(kind, K, color):
    look = {"Primary": C.rgb(*color), "Id": kind}
    if kind == "portal":
        gate, pad, lan, rec, transl, neon = portal(K)
        m = ModelSpec("prop_portal", "prop", 1.0 / K, K)
        flat = set(neon) | {"Trim"}
        add_grid(m, gate, rec, look, group="Gate", prefix="Gate_", flat=flat, translucent=transl, neon_keys=neon,
                 shade_default=dict(light_at=0.55, dark_at=-0.35, crease=0.2))
        m.voxel_studs = 1.0 / pad.K
        add_grid(m, pad, rec, look, group="Pad", prefix="Pad_", flat=flat, neon_keys=neon, offset=PAD_SHIFT,
                 shade_default=dict(light_at=0.9, crease=0.0, dark=False, light=False))
        m.voxel_studs = 1.0 / lan.K
        add_grid(m, lan, rec, look, group="Detail", prefix="Detail_", flat=flat, neon_keys=neon,
                 shade_default=dict(light_at=0.6))
        m.voxel_studs = 1.0 / K
        m.attachments = {
            "Zone": cf_json(np.eye(3), [0, 3.3, 0]),
            "SwirlCore": cf_json(np.eye(3), [0, 11.5, 9.5]),
            "Billboard": cf_json(np.eye(3), [0, 25.2 + 7.5, 9.5]),
        }
        m.groups = {
            "Gate": {"collide": "use invisible Part colliders (pillars, base, ring)", "parts": sorted(n for n in m.objects if n.startswith("Gate_"))},
            "Pad": {"collide": "invisible 14 x 0.3 x 14 Part", "parts": sorted(n for n in m.objects if n.startswith("Pad_"))},
            "Detail": {"parts": sorted(n for n in m.objects if n.startswith("Detail_"))},
            "Stars": {"kind": "stars", "lit": {"Color": list(P4["Gold"]), "Material": "Neon"},
                      "off": {"Color": list(P4["StarOff"]), "Material": "SmoothPlastic"},
                      "parts": ["Detail_Star%d" % i for i in range(1, 6)]},
        }
        m.meta = {"source": "LobbyBuilder gateBoxes / buildPortal at git 7aa0df2 (Phase 4 release)",
                  "pivot": "pad centre on the promenade; the gate stands 9.5 studs behind (+Z), facing -Z",
                  "tint": "Look.Primary = Config.Difficulties[i].Color"}
        return m, look
    if kind == "cloud":
        g, rec, shade_rgb = cloud_platform(K)
        m = ModelSpec("prop_cloud_platform", "prop", 1.0 / K, K)
        add_grid(m, g, rec, look, group="Cloud", shade_rgb=shade_rgb,
                 shade_default=dict(light_at=0.5, dark_at=-0.3, crease=0.24, deep=0.14))
        m.attachments = {"Top": cf_json(np.eye(3), [0, 0, 0])}
        m.meta = {"pivot": "top centre (the walking surface)", "collide": "an invisible Part slab at the top"}
        return m, look
    raise SystemExit("unknown prop " + kind)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["portal", "cloud"])
    ap.add_argument("--K", type=float, default=2.0, help="voxels per stud")
    ap.add_argument("--color", default="226,150,74", help="tint (portal: the difficulty colour)")
    ap.add_argument("--stars", type=int, default=3)
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", default="")
    ap.add_argument("--res", type=int, default=520)
    a = ap.parse_args()
    t0 = time.time()
    color = [int(v) for v in a.color.split(",")]
    m, look = build(a.kind, a.K, color)
    from nvox import blend as B
    B.reset_scene()
    objs = B.make_objects(m, look)
    fbx = os.path.join(a.out, m.name + a.tag + ".fbx")
    size = B.export_fbx(objs, fbx)
    ver = B.verify_fbx(fbx, m)
    ver["bytes"] = size
    write_manifest(m, look, os.path.join(a.out, m.name + a.tag + ".manifest.json"), os.path.basename(fbx), ver,
                   extra={"previewLook": {"Primary": color, "stars": a.stars}})
    B.reset_scene()
    B.setup_render(a.res)
    made = B.make_objects(m, look)
    # preview: light the first <stars> star gems, dim the rest (what the loader does)
    for ob in made:
        if ob.name.startswith("Detail_Star") and int(ob.name[-1]) > a.stars:
            ob.data.materials[0] = B._material("M_staroff", C.rgb(*P4["StarOff"]))
        if ob.name in ("Gate_Swirl", "Gate_SwirlB"):
            mat = ob.data.materials[0]
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            bsdf.inputs["Alpha"].default_value = 0.45
    lo, hi = bounds_of(m)
    png = os.path.join(a.out, m.name + a.tag + "_preview.png")
    B.render_views((lo, hi), png, views=("front", "threequarter", "side", "back") if a.kind == "portal" else ("hero", "front", "side", "back"), res=a.res)
    print(json.dumps({"model": m.name, "tris": m.tris(), "parts": len(m.objects), "verify": ver["ok"], "problems": ver["problems"],
                      "maxPerPart": max(o.tris() for o in m.objects.values()), "stats": m.stats["grids"],
                      "seconds": round(time.time() - t0, 1), "preview": png}, indent=1))


if __name__ == "__main__":
    main()
