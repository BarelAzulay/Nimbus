"""Keyed voxel cells -> MeshParts per the runtime name contract (ARCHITECTURE_V3 6.1 / recipe 4.3 + 4.4).

One MeshPart per (group, palette key, shade class):
  * base + dark + deep shades share ONE part, told apart by vertex colours: base WHITE, dark = Voxel.Darken's
    multiply (0.8425, 0.85, 0.8875), deep = that squared.  The loader sets Color = recipe(Look).
  * the light shade is its own part `<Key>Light` (Voxel.Lighten is a lerp, not a multiply): Color =
    Voxel.Lighten(recipe) - High only.  Low ("headroom" mode, recipe decision 11): no light parts; vertex colours
    light 1.0, base 0.87, dark 0.87 x dark factor; the loader sets Color = min(1, recipe / 0.87).
  * a palette entry that sets <Key>_Dark explicitly (not the Darken multiply) gets its own `<Key>Dark` part.
  * `Fixed`: constant-colour keys that tools/mesh_names.py finds unreferenced, colours baked (Color = white).
Naming: "key" naming (pet Body, bosses' joints, world pieces) -> the part is named after its key (`Fur`,
`FurLight`); "group" naming (Tail, WingL, Halo, Aura, EyeLid ...) -> the group name, numbered like PetBuilder's
uniqueName (`WingL`, `WingL2`, ...) in a stable order; every part records its palette key (MK_Key) and shade.
"""
import numpy as np

from . import colors as C
from .build import ModelSpec, ObjectSpec  # noqa: F401  (re-exported for callers)
from .mesher import greedy_mesh

DARK = C.shade_dark_factor()
DEEP = tuple(f * f for f in DARK)
HEADROOM = 0.87
NON_OPAQUE = {"Glass", "ForceField"}


def base_key(key):
    if key.endswith("_Light"):
        return key[:-6], 1
    if key.endswith("_Dark"):
        return key[:-5], -1
    return key, 0


def deep_mask(occ, dark, threshold=7):
    """dark voxels sitting in a tight crease (<= threshold empty cells in their 26-neighbourhood) -> deep"""
    pad = np.pad(occ, 1)
    empty = np.zeros(occ.shape, np.int16)
    n = occ.shape
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                if dx == dy == dz == 0:
                    continue
                empty += ~pad[1 + dx:1 + dx + n[0], 1 + dy:1 + dy + n[1], 1 + dz:1 + dz + n[2]]
    return dark & (empty <= threshold) & (empty > 0)


class Styles:
    """palette access: colour (0..1), material and transparency per key (variants resolve like Voxel.lua)."""

    def __init__(self, palette, recipes=None):
        self.palette = palette or {}
        self.recipes = recipes or {}

    def color(self, key):
        e = self.palette.get(key)
        if e is not None:
            return tuple(float(x) for x in e[:3])
        b, v = base_key(key)
        if v == 0:
            return (200 / 255, 200 / 255, 205 / 255)
        c = self.color(b)
        return C.shade_light(c) if v > 0 else C.shade_dark(c)

    def style(self, key):
        e = self.palette.get(key)
        if e is None:
            b, v = base_key(key)
            return self.style(b) if v != 0 else ("SmoothPlastic", 0.0)
        return (str(e[3]), float(e[4]))

    def explicit_dark(self, key):
        """True when <key>_Dark is its own palette colour (not the Darken multiply of <key>)"""
        e = self.palette.get(key + "_Dark")
        if e is None:
            return False
        want = C.shade_dark(self.color(key))
        return max(abs(a - b) for a, b in zip(e[:3], want)) > 1.5 / 255

    def explicit_light(self, key):
        e = self.palette.get(key + "_Light")
        if e is None:
            return False
        want = C.shade_light(self.color(key))
        return max(abs(a - b) for a, b in zip(e[:3], want)) > 1.5 / 255

    def recipe(self, key):
        r = self.recipes.get(key)
        if isinstance(r, dict):
            r = r.get("recipe")
        if r is None:
            r = ["rgb"] + C.to255(self.color(key))
        return r


def _q(c):
    return tuple(round(x * 255) / 255 for x in c)


def add_cells(model, cells, styles, group="Body", naming="key", vs=0.1, rot=None, offset=(0, 0, 0), headroom=False,
              fixed_keys=(), deep=True, used=None, part_prefix=None):
    """Mesh one group's keyed cells into `model` (an nvox.build.ModelSpec).

    cells   dict (x, y, z) int -> palette key (with _Light / _Dark variants)
    vs      studs per voxel;  rot (3x3) + offset (studs): voxel space -> model space (rest pose)
    used    shared uniqueName counter dict of the model (group naming)
    Returns the list of ObjectSpecs made (in name order)."""
    if not cells:
        return []
    xyz = np.array(list(cells.keys()), np.int64)
    keys = list(cells.values())
    half = int(np.abs(xyz).max()) + 3
    n = 2 * half + 1
    occ = np.zeros((n, n, n), bool)
    idx = xyz + half
    occ[idx[:, 0], idx[:, 1], idx[:, 2]] = True
    dark_m = np.zeros_like(occ)
    shades = []
    for k in keys:
        shades.append(base_key(k)[1])
    shades = np.array(shades, np.int8)
    dm = shades < 0
    dark_m[idx[dm, 0], idx[dm, 1], idx[dm, 2]] = True
    deep_m = deep_mask(occ, dark_m) if deep else np.zeros_like(occ)

    labels = {}
    info = [None]
    F = np.zeros((n, n, n), np.int32)
    opaque = np.zeros((n, n, n), bool)
    for i, key in enumerate(keys):
        base, sh = base_key(key)
        mat, tr = styles.style(key)
        if sh < 0 and deep_m[idx[i, 0], idx[i, 1], idx[i, 2]]:
            sh = -2
        is_fixed = base in fixed_keys and mat == "SmoothPlastic" and tr == 0
        if is_fixed:
            col = styles.color(key) if sh > -2 else tuple(c * f for c, f in zip(styles.color(base + "_Dark"), DARK))
            pclass, vcol = "fixed", _q(col)
        elif sh > 0 and styles.explicit_light(base) and not headroom:
            pclass, vcol = "lightx", (1.0, 1.0, 1.0)
        elif sh > 0:
            if headroom:
                pclass, vcol = "main", (1.0, 1.0, 1.0)
            else:
                pclass, vcol = "light", (1.0, 1.0, 1.0)
        elif sh < 0 and styles.explicit_dark(base):
            pclass, vcol = "darkx", _q((1.0, 1.0, 1.0) if sh == -1 else DARK)
        else:
            f = {0: (1.0, 1.0, 1.0), -1: DARK, -2: DEEP}[sh]
            if headroom:
                f = tuple(x * HEADROOM for x in f)
            pclass, vcol = "main", _q(f)
        pk = ("Fixed", "fixed") if is_fixed else (base, pclass)
        lk = (pk, vcol)
        if lk not in labels:
            labels[lk] = len(info)
            info.append((pk, vcol, mat, tr))
        F[idx[i, 0], idx[i, 1], idx[i, 2]] = labels[lk]
        opaque[idx[i, 0], idx[i, 1], idx[i, 2]] = (tr == 0 and mat not in NON_OPAQUE)
    quads = greedy_mesh(F, opaque, half)
    R = np.eye(3) if rot is None else np.asarray(rot, float)
    off = np.asarray(offset, float)
    # group the quads per part key
    per_part = {}
    for lab, qs in quads.items():
        pk, vcol, mat, tr = info[lab]
        e = per_part.setdefault(pk, {"quads": [], "mat": mat, "tr": tr})
        for corners, a, sign in qs:
            cs = (np.asarray(corners, float) * vs) @ R.T + off
            e["quads"].append((cs, vcol))
    order = {"main": 0, "darkx": 1, "light": 2, "lightx": 3, "fixed": 4}
    made = []
    for pk in sorted(per_part, key=lambda p: (order[p[1]], p[0])):
        e = per_part[pk]
        base, pclass = pk
        if naming == "key":
            name = {"main": base, "light": base + "Light", "lightx": base + "Light", "darkx": base + "Dark",
                    "fixed": "Fixed"}[pclass]
            if part_prefix:
                name = part_prefix + name
            if used is not None:
                c = used.get(name, 0) + 1
                used[name] = c
                if c > 1:
                    name = name + str(c)
        else:
            nm = part_prefix or group
            c = (used.get(nm, 0) if used is not None else 0) + 1
            if used is not None:
                used[nm] = c
            name = nm if c == 1 else nm + str(c)
        if pclass == "fixed":
            recipe, shade = None, "fixed"
        elif pclass == "light":
            recipe, shade = ["shadeLight", styles.recipe(base)], "light"
        elif pclass == "lightx":
            recipe, shade = styles.recipe(base + "_Light"), "light"
        elif pclass == "darkx":
            recipe, shade = styles.recipe(base + "_Dark"), "dark"
        else:
            recipe, shade = styles.recipe(base), "base"
            if headroom:
                recipe, shade = ["headroom", recipe], "headroom"
        o = model.obj(name, group=group, region=base if pclass != "fixed" else "Fixed", shade=shade, recipe=recipe,
                      material=e["mat"], baked=(pclass == "fixed"))
        if e["tr"]:
            o.transparency = e["tr"]
        o.key = base if pclass != "fixed" else "Fixed"
        o.keys.add(base if pclass != "fixed" else "Fixed")
        if pclass == "fixed":
            o.fixed_keys = sorted({k2 for k2 in (base_key(k)[0] for k in keys) if k2 in fixed_keys})
        o.quads.extend(e["quads"])
        made.append(o)
    model.stats.setdefault("grids", []).append({"group": group, "voxels": len(keys),
                                                "quads": int(sum(len(q) for q in quads.values()))})
    return made


def add_baked(model, cells, name, group=None, vs=0.25, rot=None, offset=(0, 0, 0), material="SmoothPlastic", key=None):
    """One part with every colour BAKED into its vertex colours (MeshPart.Color = white): cells (x, y, z) -> (r, g, b)
    0..1.  For calibration / props whose colours never change at run time (clouds, rocks)."""
    if not cells:
        return None
    xyz = np.array(list(cells.keys()), np.int64)
    half = int(np.abs(xyz).max()) + 3
    n = 2 * half + 1
    F = np.zeros((n, n, n), np.int32)
    labels = {}
    for (x, y, z), c in cells.items():
        q = _q(c)
        lab = labels.setdefault(q, len(labels) + 1)
        F[x + half, y + half, z + half] = lab
    inv = {v: k for k, v in labels.items()}
    quads = greedy_mesh(F, F != 0, half)
    R = np.eye(3) if rot is None else np.asarray(rot, float)
    off = np.asarray(offset, float)
    o = model.obj(name, group=group or name, region="Fixed", shade="fixed", recipe=None, material=material, baked=True)
    o.key = key or name
    o.keys.add(o.key)
    for lab, qs in quads.items():
        for corners, a, sign in qs:
            o.quads.append(((np.asarray(corners, float) * vs) @ R.T + off, inv[lab]))
    return o
