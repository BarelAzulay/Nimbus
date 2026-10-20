"""Grids -> mesh objects (no bpy here): shading, region objects, vertex colours, greedy quads, the manifest data.

Region objects (runtime recolour; decision in DESIGN.md):
  * every recolourable palette key ("region") becomes ONE MeshPart named after the region (Fur -> "Primary",
    Accent -> "Secondary", EyeIris -> "Eye", ...).  Its base shade has vertex colour WHITE, its dark shade the exact
    Voxel.Darken multiply (0.8425, 0.85, 0.8875), the deep-crease shade that factor squared.  Roblox multiplies the
    vertex colour with MeshPart.Color, so the loader sets Color = the region colour from the pet's Look and gets
    today's base + dark shades exactly.
  * the light shade (Voxel.Lighten is NOT a multiply) is a second MeshPart "<Region>_Light", tinted with
    shade_light(region colour).
  * constant-colour keys (eye whites, claws, tongue, the dog's nose, crown gold, gems...) share one MeshPart "Fixed"
    with their real colours baked into the vertex colours (MeshPart.Color stays white).
Group prefixes: body parts have no prefix, tail parts "Tail_", the wings "WingL_" / "WingR_".
"""
import numpy as np

from . import colors as C
from .mesher import greedy_mesh, count_faces
from .shade import shade as shade_grid

DARK = C.shade_dark_factor()
DEEP = tuple(f * f for f in DARK)
WHITE = (1.0, 1.0, 1.0)

REGION_NAME = {"Fur": "Primary", "Accent": "Secondary", "EyeIris": "Eye", "EyeShine": "EyeWhite", "EyePupil": "Pupil"}


def region_name(key):
    return REGION_NAME.get(key, key)


def is_constant(rec):
    return rec[0] == "rgb"


class ObjectSpec:
    def __init__(self, name, group, region, shade, recipe, material="SmoothPlastic", baked=False):
        self.name, self.group, self.region, self.shade = name, group, region, shade
        self.recipe, self.material, self.baked = recipe, material, baked
        self.quads = []      # list of (corners studs (4x3), vcolor (r, g, b) 0..1)
        self.keys = set()

    def tris(self):
        return 2 * len(self.quads)


class ModelSpec:
    def __init__(self, name, kind, voxel_studs, K):
        self.name, self.kind, self.voxel_studs, self.K = name, kind, voxel_studs, K
        self.objects = {}
        self.attachments = {}
        self.groups = {}
        self.meta = {}
        self.stats = {}

    def obj(self, name, **kw):
        o = self.objects.get(name)
        if o is None:
            o = ObjectSpec(name, **kw)
            self.objects[name] = o
        return o

    def tris(self):
        return sum(o.tris() for o in self.objects.values())


def add_grid(model, grid, recipes, look, group="Body", prefix="", offset=(0.0, 0.0, 0.0), shade_opts=None,
             flat=(), shade_default=None, glow_keys=(), neon_keys=(), translucent=None, mirror_x=False,
             fixed=True, shade=True, shade_rgb=None, up=(0.0, 1.0, 0.0)):
    """Shade one grid, split its voxels into region objects and greedy-mesh them into `model`."""
    vs = model.voxel_studs
    S = shade_grid(grid, shade_opts or {}, skip=set(flat), default=shade_default, up=up) if shade else np.zeros(grid.L.shape, np.int8)
    shade_rgb = shade_rgb or {}
    L = grid.L
    labels = {}
    label_info = [None]
    F = np.zeros(L.shape, np.int32)
    opaque = np.zeros(L.shape, bool)
    translucent = translucent or {}
    for kid, key in enumerate(grid.keys):
        if key is None:
            continue
        m = L == kid
        if not m.any():
            continue
        rec = recipes.get(key)
        if rec is None:
            raise KeyError("no colour recipe for palette key %r (%s)" % (key, model.name))
        material = "Neon" if key in neon_keys else "SmoothPlastic"
        transp = translucent.get(key)
        opaque |= m if transp is None else np.zeros_like(m)
        for sh in (-2, -1, 0, 1):
            ms = m & (S == sh)
            if not ms.any():
                continue
            const = fixed and is_constant(rec) and material == "SmoothPlastic" and transp is None
            if const:
                base = C.eval_recipe(rec, look)
                col = C.shade_light(base) if sh == 1 else (base if sh == 0 else tuple(base[i] * (DARK if sh == -1 else DEEP)[i] for i in range(3)))
                if sh in shade_rgb.get(key, {}):
                    col = C.rgb(*shade_rgb[key][sh])
                oname, region, oshade, orec, baked = prefix + "Fixed", "Fixed", "baked", None, True
            else:
                region = region_name(key)
                if sh == 1:
                    oname, oshade, col = prefix + region + "_Light", "light", WHITE
                else:
                    oname, oshade, col = prefix + region, "base", (WHITE if sh == 0 else (DARK if sh == -1 else DEEP))
                orec, baked = rec, False
            col = tuple(round(c * 255) / 255 for c in col)  # bytes, like the FBX colour layer
            lk = (oname, col)
            if lk not in labels:
                labels[lk] = len(label_info)
                label_info.append((oname, col, region, oshade, orec, material, baked, key, transp))
            F[ms] = labels[lk]
    quads = greedy_mesh(F, opaque, grid.half)
    off = np.asarray(offset, float)
    for lab, qs in quads.items():
        oname, col, region, oshade, orec, material, baked, key, transp = label_info[lab]
        o = model.obj(oname, group=group, region=region, shade=oshade, recipe=orec, material=material, baked=baked)
        if transp is not None:
            o.transparency = transp
        o.keys.add(key)
        for corners, a, sign in qs:
            cs = np.asarray(corners, float) * vs
            if mirror_x:
                cs[:, 0] *= -1
                cs = cs[::-1]
            o.quads.append((cs + off, col))
    model.stats.setdefault("grids", []).append({
        "grid": grid.name, "group": group, "voxels": grid.count(), "unit_faces": count_faces(F, opaque),
        "quads": sum(len(q) for q in quads.values()),
    })
    return S


def bounds_of(model, objects=None):
    pts = [q[0] for o in (objects or model.objects.values()) for q in o.quads]
    if not pts:
        return None
    a = np.concatenate(pts)
    return a.min(0), a.max(0)


def region_table(model, look):
    """region -> {recipe, preview colour, parts} for the manifest."""
    out = {}
    for o in model.objects.values():
        r = out.setdefault(o.region, {"recipe": o.recipe, "parts": [], "keys": set()})
        r["parts"].append(o.name)
        r["keys"] |= o.keys
    for name, r in out.items():
        r["keys"] = sorted(r["keys"])
        if r["recipe"] is not None:
            r["previewColor"] = C.to255(C.eval_recipe(r["recipe"], look))
    return out
