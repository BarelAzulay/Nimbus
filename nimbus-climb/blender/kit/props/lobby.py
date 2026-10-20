"""Lobby props: new fine-voxel designs of the Phase 4 lobby pieces (wave 2 art-lobby; catalog blender/catalog/lobby.json;
ARCHITECTURE_V3 6.3).  The P4 look (style.md 4): bright lime grass, cream stone, warm planks, white / light-blue clouds,
SmoothPlastic, Neon only for lamps / glows; the Lua Part builds' sizes and pivots exactly (LobbyBuilder Props.* /
buildFountain / buildMachine / ... and StormAltar), but at 4-10 voxels per stud with stone courses, plank seams, curls,
leaf clusters and flower pixels instead of 1-stud blocks.

Pivot of every key = the origin the builder tags (LobbyBuilder Mesh.tag): the ground point under the prop, -Z = the
prop's front (the Part build's own frame).  Colour: constant keys are baked into one "Fixed" part (light / dark shades
in its vertex colours); per-instance keys follow the ML_Primary / ML_Secondary look (Primary = an obelisk's band, a
banner's cloth, a flower bed's flowers, a roulette's cabinet); Neon keys (lamps, glows) are their own parts.
"""
import math

import numpy as np

from nvox.grid import angles
from props import prop

# LobbyBuilder C (the P4 palette) + a few detail shades
PAL = {
    "Grass": (108, 186, 86), "GrassLight": (132, 202, 98), "GrassDark": (86, 160, 76),
    "Hedge": (74, 146, 72), "HedgeLight": (100, 170, 84),
    "Stone": (208, 202, 190), "StoneLight": (226, 221, 209), "StoneDark": (172, 164, 154), "StoneEdge": (146, 138, 132),
    "Slate": (214, 208, 196), "SlateDark": (172, 164, 154), "Marble": (242, 237, 226), "MarbleShade": (226, 221, 209),
    "Mortar": (186, 178, 166),
    "Plank": (196, 146, 98), "PlankLight": (214, 166, 114), "PlankDark": (152, 108, 72), "Seam": (128, 90, 60),
    "Bark": (132, 92, 62), "BarkDark": (108, 74, 52),
    "Iron": (64, 70, 92), "IronLight": (96, 104, 130),
    "Gold": (244, 198, 84), "GoldDark": (206, 154, 62), "GoldLight": (255, 226, 140),
    "Leaf": (98, 178, 80), "LeafLight": (128, 198, 96), "LeafDark": (72, 150, 70),
    "Pine": (60, 138, 92), "PineLight": (84, 160, 104),
    "Blossom": (246, 174, 204), "BlossomLight": (252, 200, 222), "BlossomWhite": (250, 228, 238),
    "Fruit": (236, 92, 96), "Soil": (120, 86, 64), "SoilDark": (98, 70, 52),
    "Navy": (34, 42, 76), "Rose": (234, 120, 146), "RoseDark": (206, 96, 124), "Cream": (246, 234, 210),
    "Water": (92, 178, 236), "WaterDeep": (62, 136, 212), "Foam": (214, 238, 252),
    "Cloud": (232, 238, 249), "CloudLight": (244, 247, 252), "Mist": (194, 211, 240),
    "Dark": (42, 46, 70), "Yellow": (250, 214, 92), "White": (244, 244, 248), "Pink": (246, 150, 188),
    "Heal": (124, 214, 150), "Feather": (244, 136, 70), "Lamp": (255, 214, 140),
}
NEON = {"Lamp": (255, 214, 140), "GoldGlow": (244, 198, 84), "Bulb": (255, 214, 140), "Glow": (255, 236, 170)}


def rgb(name):
    return ["rgb"] + list(PAL[name])


def hsh(*v):
    """deterministic 0..1 hash (no RNG state: previews and FBX bytes stay the same)"""
    h = 2166136261
    for x in v:
        h = ((h ^ (int(x) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return (h & 0xFFFFFF) / float(0xFFFFFF)


class Sculpt:
    """one fine grid in studs (the key's model space) + its colour / material tables"""

    def __init__(self, kit, K, extent, name="grid"):
        self.kit = kit
        self.g = kit.grid(K=K, half=int(math.ceil(extent * K)) + 4, name=name)
        self.K = K
        self.tint = {}      # key -> recipe (runtime look)
        self.neon = {}      # key -> recipe
        self.glass = {}     # key -> (recipe, transparency)
        self.flat = set()   # unshaded keys

    def recipes(self):
        rec = {}
        for i, k in enumerate(self.g.keys):
            if k is None:
                continue
            if k in self.tint:
                rec[k] = self.tint[k]
            elif k in self.neon:
                rec[k] = self.neon[k]
            elif k in self.glass:
                rec[k] = self.glass[k][0]
            elif k in PAL:
                rec[k] = rgb(k)
            elif k in NEON:
                rec[k] = ["rgb"] + list(NEON[k])
            else:
                raise KeyError("lobby prop: no colour for key %r" % k)
        return rec

    def detach_glass(self):
        """see-through voxels never touch opaque ones (the mesher leaves such a contact open): drop the glass voxels
        that have a solid 6-neighbour"""
        g = self.g
        gids = [g.ids[k] for k in self.glass if k in g.ids]
        if not gids:
            return
        L = g.L
        isg = np.isin(L, gids)
        solid = (L != 0) & ~isg
        touch = np.zeros_like(isg)
        for ax in range(3):
            for d in (1, -1):
                touch |= np.roll(solid, d, axis=ax)
        L[isg & touch] = 0

    def mesh(self, m, group="Prop", offset=(0, 0, 0), used=None):
        self.detach_glass()
        rec = self.recipes()
        mats = {}
        for k in self.neon:
            mats[k] = ("Neon", 0.0)
        for k, (r, t) in self.glass.items():
            mats[k] = ("Glass", t)
        fixed = [k for k in rec if k not in self.tint and k not in self.neon and k not in self.glass]
        # baked keys get a lower-case prefix: the game looks up names like Stone / Gold / Cloud by name elsewhere, and
        # a baked Fixed part must never claim one of them (tools/mesh_names.py --check)
        g = self.g
        for k in fixed:
            i = g.ids.pop(k)
            g.keys[i] = "lb" + k
            g.ids["lb" + k] = i
            rec["lb" + k] = rec.pop(k)
        fixed = ["lb" + k for k in fixed]
        flat = set(self.flat) | set(self.neon) | set(self.glass)
        return self.kit.mesh(m, self.g, recipes=rec, group=group, vs=1.0 / self.K, flat=flat, materials=mats,
                             fixed_keys=fixed, offset=offset, used=used if used is not None else {})

    # shorthands (studs)
    def box(self, key, c, s, **kw):
        return self.g.box(key, c, s, **kw)

    def rbox(self, key, c, s, r, **kw):
        return self.g.rbox(key, c, s, round=r, **kw)

    def ell(self, key, c, r, **kw):
        return self.g.ell(key, c, r, **kw)

    def cyl(self, key, x, z, y0, y1, r, **kw):
        return self.g.cone(key, (x, y0, z), (x, y1, z), r, r, **kw)

    def paint(self, key, kind, only=None, **p):
        return self.g.paint(key, kind, only=only, **p)

    def dots(self, key, only, chance, seed, cell=1):
        """scatter `key` over voxels of `only` (hash per voxel / cell)"""
        g = self.g
        ids = [g.ids[k] for k in ([only] if isinstance(only, str) else only) if k in g.ids]
        if not ids:
            return
        h = g.half
        idx = np.argwhere(np.isin(g.L, ids))
        kid = g.kid(key)
        for i, j, k in idx:
            if hsh(i // cell, j // cell, k // cell, seed) < chance:
                g.L[i, j, k] = kid
        del h


def finish(m, meta, look=None):
    m.groups = {}
    m.attachments = {}
    m.meta = dict(meta)
    if look:
        m.meta["previewLook"] = {k: list(v) for k, v in look.items()}
    return m


# ---------------------------------------------------------------------------------------------- trees
@prop("lobby_tree")
def lobby_tree(entry, kit):
    """Props.Tree(kind) at 0.5-stud voxels (Lua: 1.08): the same trunk / roots / canopy layout (design unit = 1.4
    studs), lumpier leaf clusters, two-tone leaves, red fruit / white petals / pine tiers with snowy-light tips"""
    args = entry.get("args") or {}
    kind = args.get("kind", "Round")
    K = float(args.get("K", 2.0))
    U = 1.4
    S = Sculpt(kit, K, 14 * U)

    def v(x, y, z):
        return (x * U, y * U, z * U)
    g = S.g
    g.curve("Bark", [v(0, 0, 0), v(0.3, 2.4, 0), v(-0.2, 4.6, 0.2), v(0, 6.4, 0)], 1.05 * U, 0.6 * U)
    for b in ((1.5, 0, 0.5), (-1.1, 0, -1.1), (-0.4, 0, 1.4), (1.0, 0, -1.2)):
        g.cap("Bark", v(0, 0.35, 0), v(*b), 0.55 * U, 0.22 * U)
    # bark grain: darker vertical streaks
    S.dots("BarkDark", "Bark", 0.12, 3, cell=2)
    leaf, light, dark = ("Blossom", "BlossomLight", "Blossom") if kind == "Blossom" else (
        ("Pine", "PineLight", "Pine") if kind == "Pine" else ("Leaf", "LeafLight", "LeafDark"))
    if kind == "Pine":
        for a, b, r0, r1 in ((3.2, 8.6, 4.6, 1.2), (6.6, 11.4, 3.7, 0.8), (9.6, 14.2, 2.6, 0.0)):
            g.cone(leaf, v(0, a, 0), v(0, b, 0), r0 * U, r1 * U)
            # a scalloped skirt: small bulges round the tier's lower rim
            n = 9
            for i in range(n):
                ang = i / n * math.pi * 2 + a
                rr = (r0 - 0.35) * U
                g.ell(leaf, (math.cos(ang) * rr, a * U + 0.35 * U, math.sin(ang) * rr), (0.75 * U, 0.45 * U, 0.75 * U))
        g.ell("Gold", v(0, 14.35, 0), (0.42 * U, 0.42 * U, 0.42 * U))  # a little star bead on the tip
        S.dots(light, leaf, 0.12, 7, cell=2)
    else:
        g.curve("Bark", [v(0, 5.4, 0), v(1.8, 7, 0.6)], 0.45 * U)
        g.curve("Bark", [v(0, 5.8, 0), v(-1.6, 7.2, -0.8)], 0.45 * U)
        blobs = [((0, 8.3, 0), (3.8, 3.0, 3.8)), ((2.3, 7.1, 1.1), (2.4, 2.1, 2.4)), ((-2.1, 7.3, -1.4), (2.5, 2.1, 2.5)),
                 ((-0.8, 7.0, 2.3), (2.2, 2.0, 2.2)), ((0.4, 10.6, -0.4), (2.3, 1.8, 2.3)), ((1.6, 9.4, -1.9), (1.7, 1.5, 1.7)),
                 ((-2.3, 9.5, 0.9), (1.6, 1.4, 1.6))]
        for c, r in blobs:
            g.ell(leaf, v(*c), tuple(x * U for x in r))
        # leaf clusters: small bumps over the canopy surface (a lumpy, hand-made silhouette)
        for i in range(26):
            th = hsh(i, 1, 11) * math.pi * 2
            ph = (hsh(i, 2, 11) * 0.8 + 0.1) * math.pi
            c = np.array([0, 8.4, 0]) + np.array([math.cos(th) * math.sin(ph) * 3.9, math.cos(ph) * 3.1, math.sin(th) * math.sin(ph) * 3.9])
            rr = 0.7 + hsh(i, 3, 11) * 0.5
            g.ell(leaf, tuple(c * U), (rr * U, rr * 0.8 * U, rr * U))
        S.dots(dark if kind != "Blossom" else "BlossomLight", leaf, 0.1, 5, cell=2)
        if kind != "Blossom":
            S.dots(light, leaf, 0.08, 6, cell=2)
        if kind == "Blossom":
            S.dots("BlossomWhite", ["Blossom", "BlossomLight"], 0.08, 9, cell=1)
        else:
            # round red apples proud of the canopy (on the lit, outer side)
            for i in range(14):
                th = hsh(i, 4, 17) * math.pi * 2
                ph = (hsh(i, 5, 17) * 0.55 + 0.3) * math.pi
                c = np.array([0, 8.4, 0]) + np.array([math.cos(th) * math.sin(ph) * 4.25, math.cos(ph) * 3.4, math.sin(th) * math.sin(ph) * 4.25])
                g.ell("Fruit", tuple(c * U), (0.36, 0.38, 0.36))
                g.box("Bark", tuple(c * U + np.array([0, 0.5, 0])), (0.12, 0.2, 0.12))
    g.carve("box", center=(0, -5, 0), size=(40, 9.6, 40))  # nothing under the lawn
    S.flat |= {"Fruit", "BlossomWhite", "Gold"}
    m = kit.model(entry["key"], "prop", vs=1.0 / K, K=K)
    S.mesh(m, group="Tree")
    return finish(m, {"source": "LobbyBuilder Props.Tree(%s) re-sculpted at %.2f studs" % (kind, 1 / K),
                      "pivot": "trunk base on the ground"})


# ---------------------------------------------------------------------------------------------- lamp post
@prop("lobby_lamp")
def lobby_lamp(entry, kit):
    """Props.Lamp: slate foot + marble band, iron post with rings, a glass lantern round a warm Neon heart, a stepped
    iron roof and a gold finial (2 x 10.4 x 2 studs, pivot = ground centre)"""
    K = 6.0
    S = Sculpt(kit, K, 11)
    S.rbox("Slate", (0, 0.55, 0), (1.8, 1.1, 1.8), 0.15)
    S.rbox("StoneDark", (0, 0.08, 0), (2.0, 0.16, 2.0), 0.1)
    for y in (0.4, 0.75):  # stone courses on the foot
        S.paint("Mortar", "box", only="Slate", center=(0, y, 0), size=(2.2, 0.06, 2.2))
    S.rbox("MarbleShade", (0, 1.25, 0), (2.0, 0.24, 2.0), 0.08)
    S.cyl("Iron", 0, 0, 1.3, 7.9, 0.25)
    for y in (1.6, 4.6, 7.4):
        S.cyl("IronLight", 0, 0, y - 0.08, y + 0.08, 0.34)
    S.rbox("IronLight", (0, 8.0, 0), (1.2, 0.3, 1.2), 0.1)
    # lantern: glass panes, iron corner posts, the glowing heart
    S.box("Glass", (0, 8.85, 0), (1.25, 1.35, 1.25))
    S.g.carve("box", center=(0, 8.85, 0), size=(0.9, 1.0, 0.9))
    S.box("Lamp", (0, 8.85, 0), (0.62, 0.95, 0.62))
    for sx in (-1, 1):
        for sz in (-1, 1):
            S.box("Iron", (sx * 0.6, 8.85, sz * 0.6), (0.14, 1.4, 0.14))
    S.rbox("Iron", (0, 9.65, 0), (1.8, 0.22, 1.8), 0.06)
    S.rbox("Iron", (0, 9.85, 0), (1.3, 0.2, 1.3), 0.06)
    S.rbox("IronLight", (0, 10.02, 0), (0.8, 0.16, 0.8), 0.05)
    S.cyl("GoldDark", 0, 0, 10.05, 10.2, 0.16)
    S.ell("Gold", (0, 10.3, 0), (0.2, 0.2, 0.2))
    S.neon["Lamp"] = ["rgb"] + list(NEON["Lamp"])
    S.glass["Glass"] = (["rgb", 255, 236, 196], 0.45)
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Lamp")
    return finish(m, {"source": "LobbyBuilder Props.Lamp", "pivot": "ground centre"})


# ---------------------------------------------------------------------------------------------- bench
@prop("lobby_bench")
def lobby_bench(entry, kit):
    """Props.Bench: two seat planks + two back planks with seams and rounded ends on curly iron frames (faces -Z)"""
    K = 8.0
    S = Sculpt(kit, K, 4)
    for z, key in ((-0.45, "PlankLight"), (0.55, "Plank")):
        S.rbox(key, (0, 1.55, z), (5.6, 0.36, 0.92), 0.12)
    for y, key in ((2.55, "PlankLight"), (3.35, "Plank")):
        S.rbox(key, (0, y, 1.05), (5.6, 0.62, 0.26), 0.1)
    for x in (-1.4, 0, 1.4):  # plank seams (board joints)
        S.paint("Seam", "box", only=["Plank", "PlankLight"], center=(x, 2.0, 0.3), size=(0.07, 4.0, 3.0))
    for sx in (-2.4, 2.4):
        # leg + armrest frame: front leg, back leg up into the back rest, an arm with a curl
        S.box("Iron", (sx, 0.7, -0.75), (0.26, 1.4, 0.26))
        S.box("Iron", (sx, 1.85, 1.05), (0.26, 3.7, 0.26))
        S.box("Iron", (sx, 1.3, 0.15), (0.26, 0.22, 2.0))
        S.box("Iron", (sx, 2.35, -0.25), (0.26, 0.2, 2.6))
        S.g.torus("Iron", (sx, 2.05, -1.45), 0.3, 0.11, rot=angles(0, 0, math.pi / 2))
        S.box("IronLight", (sx, 0.08, -0.75), (0.4, 0.16, 0.5))
        S.box("IronLight", (sx, 0.08, 1.05), (0.4, 0.16, 0.5))
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Bench")
    return finish(m, {"source": "LobbyBuilder Props.Bench", "pivot": "ground centre, faces -Z"})


# ---------------------------------------------------------------------------------------------- flower bed
@prop("lobby_flowerbed")
def lobby_flowerbed(entry, kit):
    """Props.FlowerBed: a raised plank box (6 x 4), dark soil, leafy tufts and pixel flowers in the bed's two colours
    (Primary / Secondary = FLOWERS[v], FLOWERS[v % 6 + 1]) with yellow hearts"""
    K = 5.0
    S = Sculpt(kit, K, 4)
    S.box("PlankDark", (0, 0.5, 0), (5.9, 1.0, 3.9))
    S.box("Plank", (0, 0.92, 0), (6.05, 0.18, 4.05))
    S.g.carve("box", center=(0, 1.0, 0), size=(5.2, 0.3, 3.2))
    for x in (-1.5, 0, 1.5):
        S.paint("Seam", "box", only="PlankDark", center=(x, 0.5, 0), size=(0.1, 1.2, 4.4))
    S.box("Soil", (0, 0.86, 0), (5.2, 0.12, 3.2))
    S.dots("SoilDark", "Soil", 0.25, 2, cell=2)
    n = 0
    for ix in range(-2, 3):
        for iz in range(-1, 2):
            x, z = ix * 1.0 + (hsh(ix, iz, 4) - 0.5) * 0.3, iz * 0.95 + (hsh(ix, iz, 5) - 0.5) * 0.3
            S.ell("Leaf", (x, 1.05, z), (0.45, 0.32, 0.45))
            S.ell("LeafLight", (x + 0.12, 1.2, z - 0.1), (0.22, 0.16, 0.22), keep=True)
            n += 1
            if hsh(ix, iz, 6) < 0.85:
                key = "FlowerA" if (ix + iz) % 2 == 0 else "FlowerB"
                fy = 1.4 + hsh(ix, iz, 7) * 0.25
                for a in range(5):  # five petals round a yellow heart
                    ang = a / 5 * math.pi * 2
                    S.box(key, (x + math.cos(ang) * 0.27, fy, z + math.sin(ang) * 0.27), (0.3, 0.2, 0.3))
                S.box("Yellow", (x, fy + 0.05, z), (0.22, 0.2, 0.22))
                S.box("Leaf", (x, fy - 0.2, z), (0.1, 0.35, 0.1))
    S.tint["FlowerA"] = ["Primary"]
    S.tint["FlowerB"] = ["Secondary"]
    S.flat |= {"FlowerA", "FlowerB", "Yellow"}
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Bed")
    return finish(m, {"source": "LobbyBuilder Props.FlowerBed", "pivot": "ground centre"},
                  look={"Primary": [246, 150, 188], "Secondary": [250, 214, 92]})


# ---------------------------------------------------------------------------------------------- fountain
def _ring(S, key, r0, r1, y0, y1, **kw):
    S.cyl(key, 0, 0, y0, y1, r1, **kw)
    if r0 > 0:
        S.g.carve("cone", a=(0, y0 - 0.01, 0), b=(0, y1 + 0.01, 0), r=r0, rb=r0, only=key)


@prop("lobby_fountain")
def lobby_fountain(entry, kit):
    """buildFountain's basin (1-stud voxels in Lua; 0.25 here): a brick-coursed outer ring with a marble lip and gold
    studs, a fluted column, two scalloped bowls; `water` = the translucent water + falling streams (its own key)"""
    water = (entry.get("args") or {}).get("water", False)
    K = float((entry.get("args") or {}).get("K", 3.0))
    S = Sculpt(kit, K, 11)
    if not water:
        _ring(S, "Slate", 7.6, 9.6, 0, 2)
        for i in range(16):  # brick joints, staggered in two courses
            for row, y in enumerate((0.5, 1.5)):
                a = (i + 0.5 * row) / 16 * math.pi * 2
                S.paint("Mortar", "box", only="Slate", center=(math.cos(a) * 9.6, y, math.sin(a) * 9.6),
                        size=(0.7, 0.9, 0.18), rot=angles(0, -a, 0))
        S.paint("Mortar", "cone", only=["Slate", "StoneLight"], a=(0, 0.97, 0), b=(0, 1.03, 0), r=10, rb=10)
        _ring(S, "MarbleShade", 7.2, 10.1, 2, 2.6)
        S.cyl("Marble", 0, 0, 2.45, 2.6, 10.1)
        S.g.carve("cone", a=(0, 2.4, 0), b=(0, 2.7, 0), r=7.3, rb=7.3, only="Marble")
        for i in range(8):
            a = i / 8 * math.pi * 2
            S.ell("Gold", (math.cos(a) * 8.65, 2.75, math.sin(a) * 8.65), (0.32, 0.25, 0.32))
        S.cyl("Slate", 0, 0, 0.9, 1.0, 7.6)  # the pool floor
        # centre column (fluted) and the lower bowl
        S.cyl("Slate", 0, 0, 1, 4.2, 1.6)
        for i in range(10):
            a = i / 10 * math.pi * 2
            S.paint("StoneDark", "box", only="Slate", center=(math.cos(a) * 1.6, 2.6, math.sin(a) * 1.6),
                    size=(0.3, 2.8, 0.3), rot=angles(0, -a, 0))
        S.g.cone("MarbleShade", (0, 3.8, 0), (0, 4.6, 0), 2.2, 4.3)
        _ring(S, "MarbleShade", 3.5, 4.4, 4.6, 5.4)
        for i in range(12):  # scalloped bowl lip
            a = (i + 0.5) / 12 * math.pi * 2
            S.ell("Marble", (math.cos(a) * 4.15, 5.35, math.sin(a) * 4.15), (0.55, 0.22, 0.55))
        S.cyl("Slate", 0, 0, 5.2, 8.2, 1.05)
        S.cyl("GoldDark", 0, 0, 6.3, 6.5, 1.2)
        S.g.cone("MarbleShade", (0, 7.8, 0), (0, 8.6, 0), 1.2, 2.55)
        _ring(S, "MarbleShade", 1.75, 2.55, 8.6, 9.5)
        for i in range(8):
            a = (i + 0.5) / 8 * math.pi * 2
            S.ell("Marble", (math.cos(a) * 2.35, 9.45, math.sin(a) * 2.35), (0.4, 0.18, 0.4))
        S.cyl("Gold", 0, 0, 9.0, 9.9, 0.32)  # the spout
        S.ell("GoldLight", (0, 10.0, 0), (0.36, 0.3, 0.36))
        S.flat |= {"Gold", "GoldLight"}
        group = "Basin"
    else:
        S.cyl("WaterDeep", 0, 0, 1.0, 1.5, 7.5)
        S.cyl("Water", 0, 0, 1.5, 1.9, 7.5)
        S.cyl("Water", 0, 0, 4.65, 5.15, 3.45)
        S.cyl("Water", 0, 0, 8.65, 9.3, 1.7)
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1), (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7), (-0.7, -0.7)):
            S.box("Water", (d[0] * 4.6, 3.2, d[1] * 4.6), (0.5, 3.2, 0.5))
            S.box("Water", (d[0] * 2.75, 7.0, d[1] * 2.75), (0.4, 2.6, 0.4))
        S.glass["Water"] = (rgb("Water"), 0.35)
        S.glass["WaterDeep"] = (rgb("WaterDeep"), 0.3)
        group = "Water"
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group=group)
    return finish(m, {"source": "LobbyBuilder buildFountain (%s)" % group, "pivot": "basin centre on the plaza ground"})


# ---------------------------------------------------------------------------------------------- welcome arch
@prop("lobby_welcome_arch")
def lobby_welcome_arch(entry, kit):
    """Court.WelcomeArch: two fluted marble piers on coursed plinths with cloud puffs at their feet, a beam with a
    gold Neon inlay, cornice and soffit, the sign frame + cap (the WelcomeSign board itself stays a Part)"""
    K = 4.0
    S = Sculpt(kit, K, 39)
    px, pierH = 12.4, 24.0
    beamY = 1.4 + pierH + 0.7 + 1.1
    for s in (-1, 1):
        x = s * px
        S.rbox("Slate", (x, 0.7, 0), (4.4, 1.4, 4.4), 0.2)
        S.paint("Mortar", "box", only="Slate", center=(x, 0.7, 0), size=(5, 0.1, 5))
        S.rbox("MarbleShade", (x, 1.5, 0), (3.8, 0.3, 3.8), 0.1)
        S.rbox("Marble", (x, 1.4 + pierH / 2, 0), (3.2, pierH, 3.2), 0.5)
        for k in range(3):  # flutes on every face
            off = (k - 1) * 0.9
            for fx, fz, sx, sz in ((off, -1.6, 0.3, 0.3), (off, 1.6, 0.3, 0.3), (-1.6, off, 0.3, 0.3), (1.6, off, 0.3, 0.3)):
                S.paint("MarbleShade", "box", only="Marble", center=(x + fx, 1.4 + pierH / 2, fz), size=(sx, pierH - 3, sz))
        S.rbox("MarbleShade", (x, 1.4 + pierH + 0.35, 0), (4.0, 0.7, 4.0), 0.15)
        S.rbox("Marble", (x, 1.4 + pierH - 0.5, 0), (3.6, 0.5, 3.6), 0.15)
        for dx, dz, r in ((-1.9, -1.6, 1.2), (1.8, -1.9, 1.0), (0.3, -2.4, 0.9), (-2.0, 1.4, 0.9), (2.1, 1.3, 1.0)):
            S.ell("Cloud", (x + dx, 1.3, dz), (r * 1.3, r * 0.85, r))
    S.rbox("MarbleShade", (0, beamY, 0), (px * 2 + 4, 2.2, 3), 0.25)
    S.rbox("Marble", (0, beamY + 1.3, 0), (px * 2 + 4.8, 0.4, 3.6), 0.1)
    S.box("SlateDark", (0, beamY - 1.25, 0), (px * 2 + 2.6, 0.3, 3.3))
    S.box("GoldGlow", (0, beamY - 0.3, -1.55), (px * 2, 0.25, 0.2))
    S.box("GoldGlow", (0, beamY - 0.3, 1.55), (px * 2, 0.25, 0.2))
    for i in range(-5, 6):  # gold studs along the beam
        S.ell("Gold", (i * 2.3, beamY + 0.5, -1.55), (0.22, 0.22, 0.12))
    sy = beamY + 1.5 + 3.4
    S.box("SlateDark", (0, sy, 0), (19.4, 6.4, 0.8))
    S.g.carve("box", center=(0, sy, 0), size=(18.4, 5.4, 1.2))  # the Part board fills the frame
    S.rbox("MarbleShade", (0, sy + 3.45, 0), (20.2, 0.5, 1.2), 0.1)
    for s in (-1, 1):
        S.ell("Gold", (s * 9.9, sy + 3.85, 0), (0.35, 0.35, 0.35))
    S.neon["GoldGlow"] = ["rgb"] + list(NEON["GoldGlow"])
    S.flat |= {"Gold"}
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Arch")
    return finish(m, {"source": "LobbyBuilder Court.WelcomeArch", "pivot": "ground centre between the piers, -Z up the avenue"})


# ---------------------------------------------------------------------------------------------- obelisk
@prop("lobby_obelisk")
def lobby_obelisk(entry, kit):
    """Court.Obelisk: a coursed plinth, a chamfered marble shaft with carved panels, a Neon band in the look's Primary,
    a cap and a gold pyramid tip"""
    K = 5.0
    S = Sculpt(kit, K, 19)
    S.rbox("Slate", (0, 0.8, 0), (5, 1.6, 5), 0.2)
    S.paint("Mortar", "box", only="Slate", center=(0, 0.8, 0), size=(6, 0.1, 6))
    S.rbox("MarbleShade", (0, 1.7, 0), (4.0, 0.3, 4.0), 0.1)
    S.rbox("Marble", (0, 1.6 + 7, 0), (3, 14, 3), 0.5)
    for fx, fz in ((0, -1.5), (0, 1.5), (-1.5, 0), (1.5, 0)):
        S.paint("MarbleShade", "box", only="Marble", center=(fx, 7.0, fz), size=(0.3 if fx else 1.4, 8.5, 1.4 if fx else 0.3))
    S.box("Band", (0, 13, 0), (3.15, 0.3, 3.15))
    S.rbox("MarbleShade", (0, 15.95, 0), (3.4, 0.7, 3.4), 0.15)
    for i in range(6):  # stepped gold pyramid
        w = 2.2 - i * 0.36
        S.box("Gold", (0, 16.4 + i * 0.27, 0), (w, 0.27, w))
    S.ell("GoldLight", (0, 18.2, 0), (0.22, 0.22, 0.22))
    S.neon["Band"] = ["Primary"]
    S.flat |= {"GoldLight"}
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Obelisk")
    return finish(m, {"source": "LobbyBuilder Court.Obelisk", "pivot": "ground centre"}, look={"Primary": [244, 198, 84]})


# ---------------------------------------------------------------------------------------------- banner
@prop("lobby_banner")
def lobby_banner(entry, kit):
    """bannerPole: an iron pole with rings, a gold finial, a bar and a swallow-tail cloth in the look's Primary with
    a pale star (cloth + star follow the gate colour)"""
    K = 6.0
    S = Sculpt(kit, K, 12)
    S.cyl("Iron", 0, 0, 0, 11, 0.25)
    S.rbox("IronLight", (0, 0.15, 0), (0.9, 0.3, 0.9), 0.08)
    for y in (3.0, 6.0, 9.5):
        S.cyl("IronLight", 0, 0, y - 0.07, y + 0.07, 0.33)
    S.ell("Gold", (0, 11.35, 0), (0.42, 0.45, 0.42))
    S.ell("GoldLight", (0, 11.85, 0), (0.18, 0.2, 0.18))
    S.box("Iron", (0.9, 10.5, 0), (2.4, 0.26, 0.26))
    S.ell("Gold", (2.15, 10.5, 0), (0.2, 0.2, 0.2))
    # cloth: 2 x 4.2 from y 6.1 to 10.3, a swallow tail cut below
    for yy in np.arange(5.35, 10.31, 1 / K):
        if yy >= 6.1:
            S.box("Cloth", (1.2, yy, 0), (2.0, 1 / K, 0.16))
        else:
            notch = (6.1 - yy) / 0.75  # 0..1 down the tail
            w = 1.0 - notch * 0.5
            S.box("Cloth", (1.2 - 0.5 - w * 0.5 + 0.5, yy, 0), (w, 1 / K, 0.16))
            S.g.carve("box", center=(1.2, yy, 0), size=(notch * 0.9, 1 / K, 0.3), only="Cloth")
    # a five-point star on both faces
    for i in range(10):
        a = i / 10 * math.pi * 2 + math.pi / 2
        r = 0.62 if i % 2 == 0 else 0.26
        S.g.cap("Star", (1.2, 8.35, -0.1), (1.2 + math.cos(a) * r, 8.35 + math.sin(a) * r, -0.1), 0.09, 0.05)
        S.g.cap("Star", (1.2, 8.35, 0.1), (1.2 + math.cos(a) * r, 8.35 + math.sin(a) * r, 0.1), 0.09, 0.05)
    S.paint("ClothDark", "box", only="Cloth", center=(1.2, 10.15, 0), size=(2.2, 0.25, 0.4))
    S.tint["Cloth"] = ["Primary"]
    S.tint["ClothDark"] = ["darken", ["Primary"], 0.2]
    S.tint["Star"] = ["lighten", ["Primary"], 0.65]
    S.flat |= {"Star", "ClothDark", "GoldLight"}
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Banner")
    return finish(m, {"source": "LobbyBuilder bannerPole", "pivot": "pole foot"}, look={"Primary": [90, 160, 240]})


# ---------------------------------------------------------------------------------------------- notice boards
@prop("lobby_board")
def lobby_board(entry, kit):
    """noticeBoard(width, height): posts on stone feet, a plank frame (the navy Face stays a Part for its SurfaceGui),
    a shingled roof with a rose ridge and two little lanterns"""
    a = entry.get("args") or {}
    w, h = float(a.get("w", 11)), float(a.get("h", 8))
    K = 5.0
    S = Sculpt(kit, K, max(w / 2 + 3, h + 5.5))
    postH = h + 3.4
    for s in (-1, 1):
        x = s * (w / 2 + 0.5)
        S.box("PlankDark", (x, postH / 2, 0), (1.0, postH, 1.0))
        S.paint("Seam", "box", only="PlankDark", center=(x, postH / 2, 0), size=(0.12, postH + 1, 1.2))
        S.rbox("StoneDark", (x, 0.4, 0), (1.6, 0.8, 1.6), 0.15)
        S.rbox("Stone", (x, 0.86, 0), (1.3, 0.14, 1.3), 0.05)
        S.ell("Lamp", (x, postH - 0.9, -0.62), (0.22, 0.28, 0.22))
        S.box("Iron", (x, postH - 0.5, -0.62), (0.3, 0.12, 0.3))
    S.box("Plank", (0, 2.4 + h / 2, 0.15), (w + 0.6, h + 0.6, 0.6))
    S.g.carve("box", center=(0, 2.4 + h / 2, -0.2), size=(w, h, 0.4))  # where the Face board sits
    for i in range(int(w) + 1):
        S.paint("PlankLight", "box", only="Plank", center=(-w / 2 + i, 2.4 + h / 2, 0.15), size=(0.5, h + 0.8, 0.8))
    rw = w + 3
    for j, yy in enumerate((postH + 0.1, postH + 0.35)):
        S.box("RoseDark" if j == 0 else "Rose", (0, yy, 0), (rw - j * 0.5, 0.25, 2.4 - j * 0.45))
    for i in range(int(rw / 0.8)):  # shingle notches along the eaves
        S.g.carve("box", center=(-rw / 2 + 0.4 + i * 0.8, postH, -1.2), size=(0.12, 0.3, 0.16))
    S.box("Rose", (0, postH + 0.75, 0), (w + 1.6, 0.5, 1.4))
    S.box("RoseDark", (0, postH + 1.02, 0), (w + 1.0, 0.1, 0.5))
    S.neon["Lamp"] = ["rgb"] + list(NEON["Lamp"])
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Board")
    return finish(m, {"source": "LobbyBuilder noticeBoard(%g, %g)" % (w, h), "pivot": "ground centre, faces -Z"})


# ---------------------------------------------------------------------------------------------- roulette machine
@prop("lobby_roulette")
def lobby_roulette(entry, kit):
    """buildMachine: the gacha cabinet (Lua 0.5-stud voxels, here 0.2) in the roulette colour (Primary) with gold
    trims, an eight-segment wheel, marquee bulbs, a lever, and a glass dome full of eggs in its top rarity colour
    (Secondary); front = -Z, pivot = ground centre"""
    K = 3.0
    S = Sculpt(kit, K, 14)
    S.rbox("Iron", (0, 0.5, 0), (9, 1.0, 7), 1.5)
    S.rbox("GoldDark", (0, 1.04, 0), (7.6, 0.12, 5.6), 1.0)
    S.rbox("Gold", (0, 1.25, 0), (7.5, 0.5, 5.5), 1.0)
    S.rbox("Body", (0, 3.5, 0), (7, 4.0, 5), 1.0)
    S.rbox("Gold", (0, 5.75, 0), (7.5, 0.5, 5.5), 1.0)
    S.rbox("Body", (0, 6.5, 0), (4, 1.0, 4), 0.8)
    S.rbox("Gold", (0, 7.1, 0), (4.3, 0.3, 4.3), 0.8)
    for x in (-3.0, -1.0, 1.0, 3.0):  # marquee bulbs on the top band
        S.ell("Bulb", (x, 5.75, -2.8), (0.28, 0.28, 0.2))
    # the prize wheel (on the front face, z = -2.5)
    wy = 3.75
    for i in range(16):
        a0 = i / 16 * math.pi * 2
        key = "Seg1" if i % 2 == 0 else "Seg2"
        S.g.cone(key, (0, wy, -2.55), (0, wy, -2.75), 1.45, 1.45,
                 pattern=lambda x, y, z, cur, a0=a0: [False if not ((math.atan2(yy - wy, xx) - a0) % (2 * math.pi) < math.pi / 8 + 1e-6) else None for xx, yy in zip(x, y)])
    S.g.torus("GoldDark", (0, wy, -2.65), 1.6, 0.18, rot=angles(math.pi / 2, 0, 0))
    S.g.cone("Gold", (0, wy, -2.6), (0, wy, -2.95), 0.4, 0.3)
    S.ell("Knob", (0, wy + 1.85, -2.8), (0.3, 0.38, 0.25))
    # chute + tray
    S.box("Dark", (0, 1.75, -2.55), (2.4, 0.6, 0.25))
    S.rbox("Gold", (0, 1.45, -2.85), (2.6, 0.2, 0.7), 0.1)
    # lever on the right side with a ball knob
    S.g.cap("IronLight", (3.6, 3.0, 0), (4.4, 6.0, 0), 0.22)
    S.ell("Knob", (4.5, 6.6, 0), (0.6, 0.6, 0.6))
    # the dome (its own coarser grid, like the Lua's 1-stud dome): a glass shell with eggs inside, a gold crown + bulb
    D = Sculpt(kit, 2.0, 14, name="Dome")
    D.ell("Glass", (0, 9.9, 0), (3.1, 2.9, 3.1))
    D.g.carve("ellipsoid", center=(0, 9.9, 0), radius=(2.7, 2.5, 2.7), only="Glass")
    eggs = [(-1.2, 8.6, -0.9), (1.2, 8.7, 0.7), (0.2, 10.3, -1.3), (-0.9, 10.5, 1.1), (1.4, 10.4, -0.2), (-0.1, 8.9, 1.6)]
    for e in eggs:
        D.ell("Egg", e, (0.62, 0.8, 0.62))
    D.rbox("Gold", (0, 12.75, 0), (1.4, 0.4, 1.4), 0.2)
    D.ell("Bulb", (0, 13.2, 0), (0.35, 0.35, 0.35))
    S.tint["Body"] = ["Primary"]
    S.tint["Seg1"] = ["mix", ["Primary"], ["rgb", 255, 255, 255], 0.45]
    S.neon["Knob"] = ["Primary"]
    S.neon["Bulb"] = ["rgb"] + list(NEON["Bulb"])
    PAL.setdefault("Seg2", PAL["Cream"])
    S.flat |= {"Seg1", "Seg2"}
    D.tint["Egg"] = ["Secondary"]
    D.neon["Bulb"] = S.neon["Bulb"]
    D.glass["Glass"] = (["rgb", 214, 236, 255], 0.55)
    D.flat |= {"Egg"}
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Machine", used={})
    D.mesh(m, group="Dome", used={})
    return finish(m, {"source": "LobbyBuilder buildMachine", "pivot": "ground centre, front -Z"},
                  look={"Primary": [120, 190, 235], "Secondary": [250, 214, 92]})


# ---------------------------------------------------------------------------------------------- item stall
@prop("lobby_stall")
def lobby_stall(entry, kit):
    """buildItemStall: a plank counter with a striped rose / cream front, a back wall and shelf, posts, a stepped
    striped awning with a scalloped fringe; on the shelf a heal cloud, a shield bubble, a phoenix feather; coins"""
    K = 4.0
    S = Sculpt(kit, K, 13)
    S.rbox("Plank", (0, 1.5, 0), (10.6, 3.0, 3.4), 0.3)
    for x in range(-5, 5):
        S.box("Rose" if x % 2 == 0 else "Cream", (x + 0.5, 1.4, -1.75), (1.0 + 1 / K, 2.6, 0.2))
    S.rbox("Cream", (0, 3.25, 0), (11.4, 0.5, 4.2), 0.2)
    S.box("PlankDark", (0, 4.5, 3.5), (11, 9, 1))
    for x in range(-5, 6):
        S.paint("Seam", "box", only="PlankDark", center=(x, 4.5, 3.0), size=(0.08, 9.2, 0.3))
    S.box("Plank", (0, 5.6, 2.6), (9, 0.3, 1.2))
    for sx in (-6, 6):
        S.box("PlankDark", (sx, 4.5, -2.6), (0.8, 9, 0.8))
        S.box("PlankDark", (sx, 5.5, 3.5), (0.8, 11, 0.8))
    for x in range(-7, 8):
        stripe = "Rose" if ((x + 7) // 2) % 2 == 0 else "Cream"
        for zi in range(9):
            z = zi - 4
            y = 9 + (z + 4) // 3
            S.box(stripe, (x, y + 0.5, z), (1.0 + 1 / K, 1.0 + 1 / K, 1.0 + 1 / K))  # (+1 voxel: no seams)
    for i in range(30):  # scalloped fringe under the front edge
        x = -7.25 + i * 0.5
        stripe = "Rose" if ((int(math.floor(x + 0.5)) + 7) // 2) % 2 == 0 else "Cream"
        S.ell(stripe, (x, 8.85, -4.3), (0.27, 0.33, 0.12))
    S.ell("Heal", (-3, 6.5, 2.4), (1.3, 0.8, 0.6))
    S.ell("Shield", (0, 6.7, 2.4), (0.9, 0.9, 0.6))
    S.g.curve("Feather", [(2.6, 6.0, 2.4), (3.2, 7.0, 2.4), (3.5, 8.1, 2.4)], 0.45, 0.2)
    for p in ((2, 3.6, 0), (3, 3.6, -1), (2.5, 3.85, -0.5), (-3, 3.6, 0)):
        S.g.cone("Gold", (p[0], p[1] - 0.1, p[2]), (p[0], p[1] + 0.12, p[2]), 0.38, 0.38)
    PAL.setdefault("Shield", (150, 204, 252))
    S.flat |= {"Rose", "Cream", "Gold"}
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Stall")
    return finish(m, {"source": "LobbyBuilder buildItemStall", "pivot": "ground centre, front -Z"})


# ---------------------------------------------------------------------------------------------- token statue
@prop("lobby_token_statue")
def lobby_token_statue(entry, kit):
    """buildTokenStatue: a big gold coin with a bevelled rim and a glowing cloud emblem on a stepped stone pedestal"""
    K = 5.0
    S = Sculpt(kit, K, 12.5)
    S.rbox("StoneLight", (0, 1.0, 0), (6, 2.0, 6), 0.6)
    S.paint("Mortar", "box", only="StoneLight", center=(0, 1.0, 0), size=(7, 0.1, 7))
    S.rbox("Stone", (0, 2.5, 0), (4.4, 1.0, 4.4), 0.4)
    S.rbox("GoldDark", (0, 3.4, 0), (1.6, 0.9, 1.0), 0.2)
    cy = 7.5
    rot = angles(math.pi / 2, 0, 0)
    S.g.cone("GoldDark", (0, cy, -0.6), (0, cy, 0.6), 4.3, 4.3)
    S.g.cone("Gold", (0, cy, -0.8), (0, cy, 0.8), 3.5, 3.5)
    S.g.torus("GoldLight", (0, cy, 0), 3.85, 0.12, rot=rot, op="paint", only=["GoldDark"])
    # cloud emblem (three puffs + a base) in Neon, proud on both faces
    for z in (-0.85, 0.85):
        for (x, y, r) in ((-1.2, -0.3, 0.9), (0.0, 0.25, 1.15), (1.2, -0.3, 0.9)):
            S.g.cone("GoldGlow", (x, cy + y, z - 0.08), (x, cy + y, z + 0.08), r, r)
        S.box("GoldGlow", (0, cy - 0.75, z), (3.2, 0.7, 0.16))
    S.neon["GoldGlow"] = ["rgb"] + list(NEON["GoldGlow"])
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Coin")
    return finish(m, {"source": "LobbyBuilder buildTokenStatue", "pivot": "pedestal centre on the ground"})


# ---------------------------------------------------------------------------------------------- shop arch
@prop("lobby_shop_arch")
def lobby_shop_arch(entry, kit):
    """the shop's entrance arch: coursed stone pillars, rose caps with scallops, lanterns, a plank beam and the sign
    roof (the ShopSign board stays a Part)"""
    K = 5.0
    S = Sculpt(kit, K, 16)
    for s in (-1, 1):
        x = s * 7.6
        S.rbox("StoneDark", (x, 0.35, 0), (2.6, 1.7, 2.6), 0.2)
        S.rbox("StoneLight", (x, 5.6, 0), (1.8, 8.8, 1.8), 0.15)
        for i, y in enumerate(np.arange(1.8, 10.0, 1.1)):
            S.paint("Mortar", "box", only="StoneLight", center=(x, y, 0), size=(2.2, 0.1, 2.2))
            off = 0.45 if i % 2 else -0.45
            S.paint("Mortar", "box", only="StoneLight", center=(x + off, y + 0.55, 0), size=(0.1, 1.0, 2.2))
        S.rbox("Rose", (x, 10.3, 0), (2.6, 0.8, 2.6), 0.2)
        for k in range(8):
            a = k / 8 * math.pi * 2
            S.ell("RoseDark", (x + math.cos(a) * 1.25, 9.95, math.sin(a) * 1.25), (0.3, 0.25, 0.3))
        S.box("Lamp", (x, 11.2, 0), (0.7, 0.8, 0.7))
        for cx in (-1, 1):
            for cz in (-1, 1):
                S.box("Iron", (x + cx * 0.42, 11.2, cz * 0.42), (0.12, 0.9, 0.12))
        S.rbox("Iron", (x, 11.7, 0), (1.1, 0.2, 1.1), 0.05)
    S.box("PlankDark", (0, 10.3, 0), (13, 0.6, 1.2))
    for i in range(-6, 7):
        S.paint("Seam", "box", only="PlankDark", center=(i, 10.3, 0), size=(0.08, 0.8, 1.4))
    S.box("Rose", (0, 14.46, 0), (14, 0.6, 1.8))
    S.box("RoseDark", (0, 14.85, 0), (13.2, 0.2, 0.8))
    for s in (-1, 1):
        S.ell("Gold", (s * 6.6, 15.1, 0), (0.3, 0.3, 0.3))
    S.neon["Lamp"] = ["rgb"] + list(NEON["Lamp"])
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group="Arch")
    return finish(m, {"source": "LobbyBuilder buildShop arch", "pivot": "arch centre on the ground (archCF)"})


# ---------------------------------------------------------------------------------------------- lily pond
@prop("lobby_pond")
def lobby_pond(entry, kit):
    """buildPond: a ring of rounded stones round the pool; lily pads with pink / white blossoms; `water` = the pool"""
    water = (entry.get("args") or {}).get("water", False)
    K = 2.5
    S = Sculpt(kit, K, 8)
    if not water:
        n = 16
        for i in range(n):
            a = i / n * math.pi * 2
            r = 6.05 + (hsh(i, 1, 3) - 0.5) * 0.3
            s = 1.2 + hsh(i, 2, 3) * 0.3
            S.ell("StoneDark" if i % 3 else "Stone", (math.cos(a) * r, 0.55, math.sin(a) * r), (s * 1.1, 0.8, s * 0.85),
                  rot=angles(0, -a, 0))
        S.cyl("StoneDark", 0, 0, -1.4, -0.6, 6.0)  # pool floor under the water
        for (x, z, f) in ((-1.5, 1.5, "Blossom"), (2.5, -1.5, None), (1.5, 3.5, "BlossomWhite"), (-2.8, -2.2, None)):
            S.cyl("Leaf", x, z, 0.38, 0.5, 0.95)
            S.g.carve("box", center=(x + 0.55, 0.45, z), size=(0.9, 0.3, 0.2), only="Leaf")
            if f:
                for k in range(6):
                    a = k / 6 * math.pi * 2
                    S.ell(f, (x + math.cos(a) * 0.28, 0.75, z + math.sin(a) * 0.28), (0.22, 0.2, 0.22))
                S.ell("Yellow", (x, 0.82, z), (0.15, 0.15, 0.15))
        S.flat |= {"Yellow", "BlossomWhite", "Blossom"}
        group = "PondStone"
    else:
        S.cyl("WaterDeep", 0, 0, -0.6, -0.1, 5.4)
        S.cyl("Water", 0, 0, -0.1, 0.35, 5.4)
        S.glass["Water"] = (rgb("Water"), 0.35)
        S.glass["WaterDeep"] = (rgb("WaterDeep"), 0.3)
        group = "PondWater"
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group=group)
    return finish(m, {"source": "LobbyBuilder buildPond", "pivot": "pond centre on the garden ground"})


# ---------------------------------------------------------------------------------------------- home plot
@prop("lobby_plot")
def lobby_plot(entry, kit):
    """plotTemplate: the plot's cloud cushion re-voxeled from the game's own spec (2-stud voxels; Lua 6) + its lawn,
    street, hedge, fence, gate and mailbox from the Part build's own boxes (exact walk heights), the fence posts and
    gate pillars re-sculpted with caps and stone courses (the podium stays a Part: HomeBuilder recolours / dresses it)"""
    from props import lobby_world as W
    args = entry.get("args") or {}
    V = float(args.get("V", 2.0))
    t = W.target(entry["key"])
    idx, rec = W.find_cloud(template="Plot")
    R0, p0 = W.cf_matrix(rec["CF"])
    m = kit.model(entry["key"], "prop", vs=0.2, K=5.0)
    W.add_cloud(m, idx, V, R0=R0, p0=p0, name="Cloud", group="Island")
    boxes = [b for b in W.parse_boxes(t["Boxes"]) if b["name"] not in ("PodiumBase", "Accent", "PodiumTop")]
    island_keys = {"Cloud", "CloudLight", "CloudShade", "Mist", "MistDark"}
    flat = [b for b in boxes if b["name"] not in island_keys and b["name"] not in ("FencePost", "GatePillar", "GateCap", "GateBase", "GateLantern", "MailBox", "MailPost")]
    W.add_boxes(m, flat, "Grounds", {})
    K = 5.0
    for b in boxes:
        n = b["name"]
        if n not in ("FencePost", "GatePillar", "GateCap", "GateBase", "GateLantern", "MailBox", "MailPost"):
            continue
        # one small grid per piece, meshed at its own centre (a plot-wide 0.2-stud grid would be ~500^3 voxels)
        ox, oy, oz = b["pos"]
        sx, sy, sz = b["size"]
        S = Sculpt(kit, K, max(sx, sy, sz) / 2 + 1.5)
        x, y, z = 0.0, 0.0, 0.0
        if n == "FencePost":
            S.rbox("PlankDark", (x, y - 0.2, z), (sx, sy - 0.4, sz), 0.1)
            S.box("Plank", (x, y + sy / 2 - 0.3, z), (sx + 0.15, 0.2, sz + 0.15))
            S.g.cone("PlankDark", (x, y + sy / 2 - 0.2, z), (x, y + sy / 2 + 0.25, z), sx * 0.55, 0.1)
        elif n == "GateBase":
            S.rbox("StoneDark", (x, y, z), (sx, sy, sz), 0.15)
        elif n == "GatePillar":
            S.rbox("StoneLight", (x, y, z), (sx, sy, sz), 0.12)
            for i, yy in enumerate(np.arange(y - sy / 2 + 0.75, y + sy / 2, 0.9)):
                S.paint("Mortar", "box", only="StoneLight", center=(x, yy, z), size=(sx + 0.3, 0.1, sz + 0.3))
                S.paint("Mortar", "box", only="StoneLight", center=(x + (0.4 if i % 2 else -0.4), yy + 0.45, z),
                        size=(0.1, 0.8, sz + 0.3))
        elif n == "GateCap":
            S.rbox("Stone", (x, y, z), (sx, sy, sz), 0.15)
            S.rbox("StoneLight", (x, y + sy / 2 + 0.1, z), (sx - 0.5, 0.2, sz - 0.5), 0.1)
        elif n == "GateLantern":
            S.box("Lamp", (x, y + 0.2, z), (sx * 0.8, sy, sz * 0.8))
            for cx in (-1, 1):
                for cz in (-1, 1):
                    S.box("Iron", (x + cx * sx * 0.45, y + 0.2, z + cz * sz * 0.45), (0.12, sy + 0.05, 0.12))
            S.rbox("Iron", (x, y + sy / 2 + 0.3, z), (sx + 0.2, 0.2, sz + 0.2), 0.05)
        elif n == "MailPost":
            S.box("PlankDark", (x, y, z), (sx, sy, sz))
        elif n == "MailBox":
            S.rbox("IronLight", (x, y - 0.15, z), (sx, sy - 0.3, sz), 0.15)
            S.g.cone("IronLight", (x, y + sy / 2 - 0.3, z - sz / 2), (x, y + sy / 2 - 0.3, z + sz / 2), sx / 2, sx / 2)
            S.box("Dark", (x, y + 0.1, z - sz / 2), (sx * 0.6, 0.12, 0.08))
        S.neon["Lamp"] = ["rgb"] + list(NEON["Lamp"])
        S.mesh(m, group="Grounds", offset=(ox, oy, oz), used={})  # (merges into the boxes' Fixed part)
    m.groups = {}
    m.attachments = {"LayoutSig": W.layout_sig(t)}
    m.meta = {"source": "LobbyBuilder plotTemplate (cloud V %.1f + boxes + sculpted fence / gate)" % V,
              "pivot": "plot centre at the walking height, -Z = the gate / street"}
    return m
