"""Manifest JSON per key (the contract between the kit, the uploader and the runtime MeshLibrary; recipe 4.6).

Everything is in ROBLOX space: +X right, +Y up, -Z forward, studs, relative to the key's PIVOT (a pet: PetBuilder's
root `Body`; a wing: its hinge; an accessory: its attach point; a prop: its builder origin).  Each part is listed
with the centre and size of its bounds (Roblox recentres every imported MeshPart on its bounds, identity rotation):
the loader places a part at pivot * CFrame.new(center) and sets Size = size.

    parts[]     name, group, key (MK_Key), shade (base | light | dark | headroom | fixed), center, size, tris,
                material, color (recipe | "vertex"), transparency
    groups      name -> kind, side, amp, index, spec (PB_G string), hinge {pos, rot} (studs), parts, ...
    attachments name -> {pos, rot}
    rig         PB_Rig string at scale 1 (pets)
    bounds, tris, contentHash (geometry + colours + names), structureHash (names + sizes, 1e-3)
"""
import gzip
import hashlib
import json
import os

import numpy as np

from . import colors as C

KIT_VERSION = 2


def _r(v, n=4):
    return [round(float(x), n) for x in v]


def cf_json(R, p):
    return {"pos": _r(p), "rot": [_r(row, 6) for row in np.asarray(R, float)]}


def part_bounds(o):
    a = np.concatenate([np.asarray(q[0], float) for q in o.quads])
    return a.min(0), a.max(0)


def bounds_of(model):
    pts = [np.asarray(q[0], float) for o in model.objects.values() for q in o.quads]
    if not pts:
        return np.zeros(3), np.zeros(3)
    a = np.concatenate(pts)
    return a.min(0), a.max(0)


def part_entry(o):
    lo, hi = part_bounds(o)
    e = {
        "name": o.name, "group": o.group, "key": getattr(o, "key", o.region), "shade": o.shade,
        "center": _r((lo + hi) / 2), "size": _r(hi - lo), "tris": o.tris(), "material": o.material,
    }
    if o.baked:
        e["color"] = "vertex"
        if getattr(o, "fixed_keys", None):
            e["fixedKeys"] = o.fixed_keys
    else:
        e["color"] = o.recipe
    tr = getattr(o, "transparency", None)
    if tr:
        e["transparency"] = round(float(tr), 4)
    return e


def hashes(model):
    """contentHash: names, groups, keys, shades, recipes, materials and every quad (corners 1e-4 studs + vertex
    colour bytes), in a canonical order.  structureHash: part names + sizes (1e-3) + groups: unchanged structure
    means the uploader may PATCH a new version of the same asset (recipe 4.7)."""
    hc = hashlib.sha256()
    hs = hashlib.sha256()
    for name in sorted(model.objects):
        o = model.objects[name]
        e = part_entry(o)
        hc.update(json.dumps([e["name"], e["group"], e["key"], e["shade"], e["material"], e.get("color"),
                              e.get("transparency", 0)], sort_keys=True).encode())
        qs = sorted((tuple(round(float(x), 4) for x in np.asarray(c, float).ravel()), tuple(int(round(v * 255)) for v in col))
                    for c, col in o.quads)
        hc.update(json.dumps(qs).encode())
        hs.update(json.dumps([e["name"], e["group"], _r(e["size"], 3)]).encode())
    hc.update(json.dumps({"groups": model.groups, "attachments": model.attachments}, sort_keys=True, default=str).encode())
    return hc.hexdigest()[:32], hs.hexdigest()[:32]


def tris_payload(model):
    """per-part triangles in PART-LOCAL studs (relative to the part centre) + per-triangle vertex colour bytes:
    blender/out/<key>.tris.json.gz, drawn by tools/render_model.py for MeshParts that carry ML_Key / ML_Part"""
    parts = {}
    for name in sorted(model.objects):
        o = model.objects[name]
        lo, hi = part_bounds(o)
        c = (lo + hi) / 2
        v, col = [], []
        for corners, vc in o.quads:
            q = np.asarray(corners, float) - c
            for tri in ((0, 1, 2), (0, 2, 3)):
                v.extend(round(float(x), 4) for i in tri for x in q[i])
                col.append([int(round(x * 255)) for x in vc])
        parts[name] = {"center": _r(c), "size": _r(hi - lo), "v": v, "c": col, "material": o.material,
                       "shade": o.shade}
    return {"key": model.name, "kitVersion": KIT_VERSION, "parts": parts}


def write_tris(model, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = json.dumps(tris_payload(model), separators=(",", ":")).encode()
    with open(path, "wb") as fh:
        # mtime 0: the same model gives the same bytes
        with gzip.GzipFile(filename="", mode="wb", fileobj=fh, mtime=0) as gz:
            gz.write(raw)
    return path


def manifest_data(model, fbx_name, verify=None, extra=None):
    lo, hi = bounds_of(model)
    parts = [part_entry(o) for o in model.objects.values()]
    parts.sort(key=lambda p: (p["group"], p["name"]))
    content, structure = hashes(model)
    data = {
        "kitVersion": KIT_VERSION,
        "key": model.name,
        "kind": model.kind,
        "fbx": fbx_name,
        "space": "roblox: +X right, +Y up, -Z forward; studs; relative to the key's pivot",
        "voxelStuds": round(float(model.voxel_studs), 6),
        "K": round(float(model.K), 5),
        "shading": {
            "base": "vertex colour white; MeshPart.Color = recipe(Look)",
            "dark": _r(C.shade_dark_factor(), 4),
            "deep": _r([f * f for f in C.shade_dark_factor()], 4),
            "light": "<Key>Light part: Color = Voxel.Lighten(recipe) (recipe [\"shadeLight\", base])",
            "headroom": "Low: [\"headroom\", base] = min(1, base / 0.87); vertex colours light 1, base 0.87",
        },
        "bounds": {"min": _r(lo), "max": _r(hi), "size": _r(hi - lo)},
        "tris": {"total": model.tris(), "parts": len(parts), "maxPerPart": max([p["tris"] for p in parts] or [0])},
        "parts": parts,
        "groups": model.groups,
        "attachments": model.attachments,
        "rig": getattr(model, "rig", "") or "",
        "contentHash": content,
        "structureHash": structure,
        "meta": model.meta,
        "stats": model.stats,
    }
    if verify is not None:
        data["verify"] = verify
    if extra:
        data.update(extra)
    return data


def write_manifest(model, path, fbx_name, verify=None, extra=None):
    data = manifest_data(model, fbx_name, verify, extra)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    return data
