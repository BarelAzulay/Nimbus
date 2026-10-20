"""Manifest JSON per model (the contract between the Blender kit, the uploader and the Lua loader).

Everything is in ROBLOX space: +X right, +Y up, -Z forward, studs, relative to the model PIVOT (a pet's pivot is
PetBuilder's root "Body" = design (0, 0, 0); a wing's pivot is its hinge; an accessory's is its attach point).
Per part: the bounding-box centre and size, because Roblox's importer recentres every MeshPart on its own bounds:
the loader places a part at  pivotCFrame * CFrame.new(center)  (and may set Size = size to undo any import scale).
"""
import json
import os

import numpy as np

from . import colors as C
from .build import bounds_of, region_table

KIT_VERSION = 1


def _r(v, n=4):
    return [round(float(x), n) for x in v]


def cf_json(R, p):
    return {"pos": _r(p), "rot": [_r(row, 6) for row in np.asarray(R, float)]}


def write_manifest(model, look, path, fbx_name, verify=None, extra=None):
    lo, hi = bounds_of(model)
    parts = []
    for o in model.objects.values():
        a = np.concatenate([q[0] for q in o.quads])
        plo, phi = a.min(0), a.max(0)
        part = {
            "name": o.name, "group": o.group, "region": o.region, "shade": o.shade,
            "center": _r((plo + phi) / 2), "size": _r(phi - plo), "tris": o.tris(),
            "material": o.material, "vertexColors": True,
        }
        if o.baked:
            part["color"] = "vertex"  # MeshPart.Color = white, the colours are baked in
        elif o.shade == "light":
            part["color"] = ["shadeLight", o.recipe]  # Voxel.Lighten(recipe colour)
        else:
            part["color"] = o.recipe
        if getattr(o, "transparency", None) is not None:
            part["transparency"] = o.transparency
        parts.append(part)
    parts.sort(key=lambda p: (p["group"], p["name"]))
    regions = region_table(model, look)
    data = {
        "kitVersion": KIT_VERSION,
        "model": model.name,
        "kind": model.kind,
        "fbx": fbx_name,
        "space": "roblox: +X right, +Y up, -Z forward; studs; relative to the model pivot",
        "voxelStuds": round(model.voxel_studs, 6),
        "K": model.K,
        "shading": {
            "base": "vertex colour white; MeshPart.Color = region colour",
            "dark": _r(C.shade_dark_factor(), 4),
            "deep": _r([f * f for f in C.shade_dark_factor()], 4),
            "light": "separate <Region>_Light part, Color = Voxel.Lighten(region colour, 0.15)",
        },
        "bounds": {"min": _r(lo), "max": _r(hi), "size": _r(hi - lo)},
        "tris": {"total": model.tris(), "parts": len(parts), "maxPerPart": max(p["tris"] for p in parts)},
        "parts": parts,
        "regions": {k: {kk: vv for kk, vv in v.items()} for k, v in regions.items()},
        "attachments": model.attachments,
        "groups": model.groups,
        "stats": model.stats,
        "meta": model.meta,
    }
    if verify is not None:
        data["verify"] = verify
    if extra:
        data.update(extra)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=1)
    return data
