"""Wind-Sown Sky Meadow: the lobby lawn's grass and wildflowers (bug #12, option B, the player's pick 2026-10-27, note:
"make sure the grass/flowers quality is high and the animation is smooth").

The story the shapes follow: up here the wind never stops and nobody mows the outer lawns any more.  The grass grows
in tufts that all lean downwind, some gone to seed with straw-coloured heads; dandelions and blue cornflowers rode in
on the same wind.  On the inner lawns the settlers still mow, so only short tufts, clover and daisies come back
between cuts.  Someone left a sack of flower seed against a flower bed; the wind tore it open and a trail of the
bed's own two colours streams downwind across the lawn.

Keys (blender/catalog/lobby.json, budget "meadow" / "prop"):
    meadow_tuft_tall   lush tuft: 8 blades 0.55-1.0 stud, the tallest ones curved in two segments, two straw tips
    meadow_tuft_short  low wide tuft: 9 blades 0.3-0.55 stud
    meadow_tuft_seed   wild grass gone to seed: 5 blades + 3 thin stalks with nodding straw seed heads
    meadow_sprig       a few short blades (the thin edge near the paths, the mown inner lawns)
    meadow_flowers     three five-petal wildflowers on curved stems, basal leaves, two fallen petals; the petals are
                       ONE tinted part "Petal" (ML_Primary: pink / yellow / white daisy / the flower bed's colours)
    meadow_cornflower  three blue cornflowers (fringed ray florets, violet hearts), thin grey-green leaves
    meadow_dandelion   a rosette of saw-toothed leaves, two yellow heads and one seed clock with a bite blown out of
                       its downwind side
    meadow_clover      a low clover patch: trefoils, one four-leaf clover, a pink-white clover head
    prop_seedsack      the torn seed sack (a static prop: Mesh.tag on its Part build in LobbyBuilder)

Clump frame: pivot = the ground point under the clump (the lawn top), +X = DOWNWIND (every blade leans that way; the
client yaws the clump so +X follows Config.Lobby.Meadow.Wind), -Z = front.  Every clump is ONE baked MeshPart "Fixed"
(+ "Petal" for meadow_flowers), never colliding.  The client (MeadowFx) tilts each clump about its pivot for the
wind, so nothing here is rigged.

Geometry: grass blades and stems are closed tapered prisms (bottom ring, one or two side segments, a tiny top), not
voxels: a voxel blade would be a staircase of boxes at 4x the triangles.  Their horizontal cross-sections stay
parallel, so every side face is a planar trapezoid (build_all's closure check uses the exact quad area).  Flower
heads, leaves, clover and the sack are fine voxels (the kit's look: 0.05-0.1 stud pixels).  Colours are baked: a
blade is darker at its foot than at its tip (two segments = two shades), side faces a step darker than the broad
faces, so the tufts read with depth even without shadows (the client turns CastShadow off for cost).
"""
import math

import numpy as np

from props import prop
from props.lobby import PAL, Sculpt, finish, hsh

PAL.update({
    # meadow greens (the pitch palette: deep 72,140,62 / light 148,208,100 / straw 196,204,120)
    "BladeDeep": (64, 128, 58), "Blade": (92, 164, 72), "BladeMid": (112, 182, 82), "BladeLight": (148, 208, 100),
    "BladeYoung": (166, 216, 112), "Straw": (204, 196, 124), "StrawLight": (226, 214, 146), "StrawDark": (170, 156, 96),
    "Stem": (84, 150, 68), "StemDark": (66, 124, 56), "LeafMeadow": (96, 168, 74), "LeafMeadowDark": (74, 140, 62),
    "Heart": (250, 196, 70), "HeartDeep": (232, 150, 52), "PetalBrown": (196, 150, 120),
    "Corn": (96, 140, 236), "CornLight": (132, 170, 246), "CornDark": (72, 104, 206), "CornHeart": (96, 70, 150),
    "CornLeaf": (120, 160, 112),
    "Dandy": (250, 214, 92), "DandyDeep": (240, 176, 60), "DandyLeaf": (88, 158, 70), "DandyLeafDark": (70, 134, 60),
    "Clock": (246, 246, 240), "ClockShade": (222, 224, 220), "ClockCore": (190, 176, 130),
    "Clover": (104, 176, 82), "CloverLight": (132, 196, 100), "CloverMark": (176, 214, 150),
    "CloverFlower": (246, 222, 232), "CloverPink": (236, 180, 204),
    # the seed sack
    "Burlap": (216, 184, 128), "BurlapDark": (192, 160, 108), "BurlapLight": (232, 206, 156),
    "Twine": (160, 122, 78), "Seed": (232, 214, 160), "SeedDark": (196, 168, 112), "Stamp": (110, 150, 196),
    "ScoopWood": (186, 136, 88), "ScoopDark": (146, 102, 64), "Sprout": (140, 206, 96), "Ladybug": (220, 56, 52),
    "Spot": (40, 36, 44), "SoilSpill": (132, 96, 70),
})

GRASS_RAMP = [("BladeDeep", "Blade"), ("Blade", "BladeMid"), ("Blade", "BladeLight"), ("BladeMid", "BladeYoung")]


def _c(name, f=1.0):
    r, g, b = PAL[name]
    return (min(1.0, r / 255.0 * f), min(1.0, g / 255.0 * f), min(1.0, b / 255.0 * f))


def _q(c):
    return tuple(round(x * 255) / 255 for x in c)


class Prisms:
    """closed tapered prisms (blades, stems) as quads with baked colours, appended to the key's Fixed part"""

    def __init__(self):
        self.quads = []

    def _face(self, pts, col, ref):
        pts = [np.asarray(p, float) for p in pts]
        n = 0.5 * np.cross(pts[2] - pts[0], pts[3] - pts[1])
        mid = sum(pts) / 4.0
        if np.dot(n, mid - ref) < 0:
            pts = pts[::-1]
        self.quads.append((np.array(pts), _q(col)))

    def column(self, rings, cols, side=0.84, top=None, bottom=None):
        """rings: [(centre (x, y, z), half width along u, half thickness along v)] bottom -> tip, all sharing the
        frame (u, v) given by self.u / self.v; cols: one colour per segment (len(rings) - 1)"""
        u, v = self.u, self.v
        corners = []
        for c, hw, ht in rings:
            c = np.asarray(c, float)
            corners.append([c - u * hw - v * ht, c + u * hw - v * ht, c + u * hw + v * ht, c - u * hw + v * ht])
        for s in range(len(rings) - 1):
            a, b = corners[s], corners[s + 1]
            ref = (sum(a) + sum(b)) / 8.0
            col = cols[s]
            for i in range(4):
                j = (i + 1) % 4
                # faces 0-1 and 2-3 run along u (the broad faces), 1-2 and 3-0 are the thin edges
                f = 1.0 if i in (0, 2) else side
                self._face([a[i], a[j], b[j], b[i]], tuple(x * f for x in col), ref)
        ref0 = (sum(corners[0]) + sum(corners[1])) / 8.0
        self._face(corners[0], bottom or tuple(x * 0.7 for x in cols[0]), ref0)
        refn = (sum(corners[-1]) + sum(corners[-2])) / 8.0
        self._face(corners[-1], top or cols[-1], refn)

    def blade(self, base, yaw, h, w, lean, segs=1, bend=0.0, ramp=("Blade", "BladeLight"), t=0.05, tip=0.012,
              sink=0.06, tint=1.0):
        """one grass blade: foot at base (x, z) on the ground, broad face across `yaw` (radians: the u axis),
        leaning by the vector lean (dx, dz) studs at the tip; bend = extra tip lean for a two-segment blade"""
        x, z = base
        self.u = np.array([math.cos(yaw), 0.0, math.sin(yaw)])
        self.v = np.array([-math.sin(yaw), 0.0, math.cos(yaw)])
        lx, lz = lean
        c0 = (x, -sink, z)
        lo, hi = _c(ramp[0], tint), _c(ramp[1], tint)
        if segs == 1:
            rings = [(c0, w / 2, t / 2), ((x + lx, h, z + lz), tip, tip * 0.6)]
            self.column(rings, [lo], top=hi)
        else:
            k = 1.0 + bend
            mid = (x + lx * 0.38, h * 0.55, z + lz * 0.38)
            top = (x + lx * k, h * (1.0 - 0.12 * bend), z + lz * k)
            rings = [(c0, w / 2, t / 2), (mid, w * 0.34, t * 0.36), (top, tip, tip * 0.6)]
            self.column(rings, [lo, hi], top=hi)

    def stem(self, a, b, r=0.03, col="Stem", mid=None, col2=None):
        """a thin square stem from a (x, y, z) to b, optionally through mid (a kink)"""
        self.u = np.array([1.0, 0.0, 0.0])
        self.v = np.array([0.0, 0.0, 1.0])
        pts = [a, mid, b] if mid is not None else [a, b]
        rings = [(p, r, r) for p in pts]
        rings[-1] = (pts[-1], r * 0.8, r * 0.8)
        cols = [_c(col)] + ([_c(col2 or col)] if mid is not None else [])
        self.column(rings, cols, side=0.86, top=_c(col2 or col, 1.05))

    def attach(self, m, group="Meadow"):
        o = m.objects.get("Fixed")
        if o is None:
            o = m.obj("Fixed", group=group, region="Fixed", shade="fixed", recipe=None, material="SmoothPlastic",
                      baked=True)
            o.key = "Fixed"
            o.keys.add("Fixed")
            o.fixed_keys = []
        o.quads.extend(self.quads)
        o.fixed_keys = sorted(set(getattr(o, "fixed_keys", []) or []) | {"lbMeadowBlade"})
        return o


def _tuft(P, seed, n, hmin, hmax, spread, lean, out, two_seg_over=0.7, straw=0, wmin=0.15, wmax=0.24):
    """n blades from a small foot (radius `spread`), all leaning downwind (+X) by `lean` x height, fanned outwards by
    `out` x height; blades taller than two_seg_over are curved (two segments); the `straw` tallest get straw tips"""
    blades = []
    for i in range(n):
        a = (i + hsh(seed, i, 1) * 0.6) / n * math.pi * 2
        r = spread * (0.35 + 0.65 * hsh(seed, i, 2))
        h = hmin + (hmax - hmin) * hsh(seed, i, 3)
        blades.append((h, a, r, i))
    blades.sort(reverse=True)
    for rank, (h, a, r, i) in enumerate(blades):
        x, z = math.cos(a) * r, math.sin(a) * r
        # downwind lean grows with height; outward fan; a little random sideways wander
        side = (hsh(seed, i, 4) - 0.5) * 0.35
        lx = h * lean + math.cos(a) * h * out
        lz = math.sin(a) * h * out + side * h
        yaw = a + math.pi / 2 + (hsh(seed, i, 5) - 0.5) * 0.8  # the broad face roughly faces outwards
        w = wmin + (wmax - wmin) * hsh(seed, i, 6)
        ramp = GRASS_RAMP[int(hsh(seed, i, 7) * len(GRASS_RAMP)) % len(GRASS_RAMP)]
        tint = 0.94 + 0.12 * hsh(seed, i, 8)
        if rank < straw:
            ramp = ("Blade", "Straw")
        segs = 2 if h > two_seg_over else 1
        P.blade((x, z), yaw, h, w, (lx, lz), segs=segs, bend=0.35 + 0.3 * hsh(seed, i, 9), ramp=ramp, tint=tint)


def _model(kit, entry, K):
    return kit.model(entry["key"], "prop", vs=1 / K, K=K)


def _petal_flower(S, x, y, z, seed, r=2):
    """a pixel five-petal flower head at (x, y, z) studs on S's grid (K = 20: 0.05-stud voxels): a round disc of
    petals with the four diagonal notches cut (reads as five / six petals from above), a raised two-tone heart"""
    K = S.K
    v = 1.0 / K
    for i in range(-r - 1, r + 2):
        for k in range(-r - 1, r + 2):
            d2 = i * i + k * k
            if d2 > (r + 0.6) ** 2:
                continue
            # notches between petals: drop the voxels on the diagonals at the rim
            if d2 >= r * r and abs(abs(i) - abs(k)) <= 0 and (i != 0 or k != 0):
                continue
            if d2 >= (r + 0.2) ** 2 and hsh(seed, i, k) < 0.3:
                continue
            S.box("Petal", (x + i * v, y, z + k * v), (v, v, v))
            if d2 >= (r - 0.4) ** 2 and d2 < (r + 0.6) ** 2 and hsh(seed, i, k, 3) < 0.55:
                # petal tips curl up a little
                S.box("Petal", (x + i * v, y + v, z + k * v), (v, v, v))
    S.box("HeartDeep", (x, y + v, z), (v * 2.2, v, v * 2.2))
    S.box("Heart", (x, y + 2 * v, z), (v * 1.2, v, v * 1.2))


# ------------------------------------------------------------------------------------------------- grass tufts
@prop("meadow_tuft")
def meadow_tuft(entry, kit):
    kind = (entry.get("args") or {}).get("kind", "tall")
    P = Prisms()
    if kind == "tall":
        # a lush clump: many narrow blades, the tallest curved over downwind, two gone straw at the tip
        _tuft(P, 11, 13, 0.5, 1.0, 0.24, 0.3, 0.1, two_seg_over=0.8, straw=2, wmin=0.11, wmax=0.18)
    elif kind == "short":
        _tuft(P, 23, 12, 0.28, 0.55, 0.32, 0.22, 0.2, two_seg_over=9, wmin=0.12, wmax=0.2)
    elif kind == "seed":
        _tuft(P, 37, 8, 0.38, 0.72, 0.18, 0.28, 0.13, two_seg_over=0.66, straw=1, wmin=0.1, wmax=0.15)
        # three thin stalks gone to seed, each topped by a slender straw spike nodding downwind (timothy grass)
        for i, (a, h) in enumerate(((0.4, 1.12), (2.5, 1.3), (4.3, 1.0))):
            x, z = math.cos(a) * 0.07, math.sin(a) * 0.07
            dz = (hsh(i, 2, 37) - 0.5) * 0.12
            mid = (x + 0.05 * h, h * 0.55, z + dz * 0.4)
            top = (x + 0.17 * h, h, z + dz)
            P.stem((x, -0.05, z), top, r=0.016, col="StemDark", mid=mid, col2="StrawDark")
            d = np.array(top) - np.array(mid)
            d = d / np.linalg.norm(d)
            d = d + np.array([0.35, -0.1, 0.0])  # the spike nods further over than the stalk
            d = d / np.linalg.norm(d)
            t0 = np.array(top) - d * 0.02
            P.u = np.array([0.0, 0.0, 1.0])
            P.v = np.array([1.0, 0.0, 0.0])
            P.column([(t0, 0.022, 0.022), (t0 + d * 0.13, 0.042, 0.042), (t0 + d * 0.3, 0.012, 0.012)],
                     [_c("Straw"), _c("StrawLight")], side=0.9, top=_c("StrawLight"))
    elif kind == "sprig":
        _tuft(P, 53, 6, 0.2, 0.4, 0.18, 0.22, 0.2, two_seg_over=9, wmin=0.11, wmax=0.16)
    else:
        raise ValueError("meadow_tuft kind " + kind)
    m = _model(kit, entry, 20)
    P.attach(m)
    return finish(m, {"source": "LobbyBuilder Meadow (bug #12, client MeadowFx)", "pivot": "ground under the tuft, +X downwind",
                      "kind": kind})


# ------------------------------------------------------------------------------------------------- flowers
@prop("meadow_flowers")
def meadow_flowers(entry, kit):
    """three wildflowers: petals tinted per instance (ML_Primary), stems / leaves / hearts baked"""
    K = 20.0
    S = Sculpt(kit, K, 1.5)
    P = Prisms()
    heads = [(-0.12, 0.92, 0.04, 0), (0.22, 0.68, -0.18, 1), (0.02, 0.5, 0.24, 2)]
    for hx, hy, hz, i in heads:
        fx, fz = hx - 0.18 * hy, hz * 0.5  # the stem's foot sits upwind of the head (the stem leans downwind)
        mid = (fx + (hx - fx) * 0.35, hy * 0.55, fz + (hz - fz) * 0.4)
        P.stem((fx, -0.05, fz), (hx, hy - 0.04, hz), r=0.028, mid=mid, col="StemDark", col2="Stem")
        _petal_flower(S, hx, hy + 0.025, hz, 7 + i, r=3 if i == 0 else 2)
        # a leaf half way up, angled out
        P.u = np.array([0.0, 0.0, 1.0])
        P.v = np.array([1.0, 0.0, 0.0])
        ly = hy * 0.32
        sx = 1 if i % 2 == 0 else -1
        bx, bz = mid[0] * 0.6 + fx * 0.4, mid[2] * 0.6 + fz * 0.4
        P.column([((bx, ly, bz), 0.035, 0.02), ((bx + 0.12 * sx, ly + 0.07, bz + 0.05), 0.07, 0.02),
                  ((bx + 0.24 * sx, ly + 0.1, bz + 0.1), 0.012, 0.01)], [_c("LeafMeadowDark"), _c("LeafMeadow")])
    # basal leaves: a few broad low blades round the foot
    for j, a in enumerate((0.3, 1.9, 3.4, 4.9)):
        P.blade((math.cos(a) * 0.06, math.sin(a) * 0.06), a + math.pi / 2, 0.22 + 0.06 * hsh(j, 61), 0.14,
                (math.cos(a) * 0.2 + 0.06, math.sin(a) * 0.2), ramp=("LeafMeadowDark", "LeafMeadow"), t=0.04)
    # two fallen petals on the ground downwind (they browned a little at the edges)
    v = 1.0 / K
    for (px, pz) in ((0.42, 0.1), (0.55, -0.22)):
        S.box("Petal", (px, v / 2, pz), (v * 2, v, v))
        S.box("PetalBrown", (px + v * 1.5, v / 2, pz), (v, v, v))
    S.tint["Petal"] = ["Primary"]
    S.flat |= {"Petal"}
    m = _model(kit, entry, K)
    S.mesh(m, group="Meadow")
    P.attach(m)
    return finish(m, {"source": "LobbyBuilder Meadow (bug #12, client MeadowFx)", "pivot": "ground, +X downwind"},
                  look={"Primary": [246, 150, 188]})


@prop("meadow_cornflower")
def meadow_cornflower(entry, kit):
    K = 20.0
    S = Sculpt(kit, K, 1.5)
    P = Prisms()
    v = 1.0 / K
    for i, (hx, hy, hz) in enumerate(((0.05, 0.86, -0.06), (-0.2, 0.66, 0.16), (0.24, 0.58, 0.2))):
        fx, fz = hx - 0.16 * hy, hz * 0.6
        P.stem((fx, -0.05, fz), (hx, hy - 0.05, hz), r=0.022, mid=(fx + (hx - fx) * 0.4, hy * 0.5, fz),
               col="CornLeaf", col2="CornLeaf")
        # ray florets: a ring of 8 single voxels splayed out and tipped up, fringed by a lighter tip voxel
        # the head: a dark-blue cushion with four fringed rays and four lifted pale tips between them (a star of
        # florets, the cornflower's ragged look at 0.05-stud pixels)
        S.box("CornDark", (hx, hy, hz), (v * 3, v, v * 3))
        for (dx, dz) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            S.box("Corn", (hx + dx * 2.5 * v, hy, hz + dz * 2.5 * v), (v * (2 if dx else 1), v, v * (2 if dz else 1)))
        for (dx, dz) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            S.box("CornLight", (hx + dx * 2 * v, hy + v, hz + dz * 2 * v), (v, v, v))
        S.box("CornHeart", (hx, hy + v, hz), (v * 2, v, v * 2))
    # narrow grey-green leaves
    for j, a in enumerate((0.8, 2.6, 4.4)):
        P.blade((math.cos(a) * 0.05, math.sin(a) * 0.05), a + math.pi / 2, 0.38, 0.06,
                (math.cos(a) * 0.12 + 0.1, math.sin(a) * 0.12), ramp=("CornLeaf", "CornLeaf"), t=0.03)
    S.flat |= {"lb" + k for k in S.g.keys if k}  # tiny pixel heads: no light / dark split (Sculpt.mesh's lb names)
    m = _model(kit, entry, K)
    S.mesh(m, group="Meadow")
    P.attach(m)
    return finish(m, {"source": "LobbyBuilder Meadow (bug #12, client MeadowFx)", "pivot": "ground, +X downwind"})


@prop("meadow_dandelion")
def meadow_dandelion(entry, kit):
    K = 20.0
    S = Sculpt(kit, K, 1.6)
    P = Prisms()
    v = 1.0 / K
    # the rosette: five long leaves lying low round the foot (flat straps that curl up at the tip), toothed by two
    # pale-green notches each (dandelion = lion's tooth)
    for j in range(5):
        a = j / 5 * math.pi * 2 + 0.3
        ca, sa = math.cos(a), math.sin(a)
        ln = 0.4 + 0.12 * hsh(j, 71)
        P.u = np.array([-sa, 0.0, ca])
        P.v = np.array([ca, 0.0, sa])
        P.column([((ca * 0.03, 0.0, sa * 0.03), 0.04, 0.03), ((ca * ln * 0.6, 0.035, sa * ln * 0.6), 0.075, 0.03),
                  ((ca * ln, 0.1, sa * ln), 0.015, 0.012)], [_c("DandyLeafDark"), _c("DandyLeaf")])
    # two yellow heads on short hollow stems
    for i, (hx, hy, hz) in enumerate(((0.12, 0.48, -0.1), (-0.14, 0.36, 0.14))):
        P.stem((hx * 0.3, -0.03, hz * 0.3), (hx, hy - 0.04, hz), r=0.026, col="StemDark", col2="Stem")
        S.box("StemDark", (hx, hy - 0.02, hz), (v * 3, v, v * 3))
        for a in range(-3, 4):
            for b in range(-3, 4):
                d2 = a * a + b * b
                if d2 > 6 or (d2 > 4 and hsh(i, a, b, 5) < 0.35):
                    continue
                key = "DandyDeep" if d2 <= 2 else "Dandy"
                y = hy + (v if d2 <= 2 else 0)
                S.box(key, (hx + a * v, y, hz + b * v), (v, v, v))
    # the seed clock on a tall stem: a white puff with a bite blown out of its downwind side
    cx, cy, cz = 0.06, 0.92, 0.04
    P.stem((-0.02, -0.03, 0.0), (cx, cy - 0.12, cz), r=0.022, mid=(0.0, 0.5, 0.02), col="StemDark", col2="Stem")
    S.ell("Clock", (cx, cy, cz), (0.135, 0.13, 0.135))
    # a bite on the downwind side where the wind already took the seeds (the brown seed base shows there)
    S.g.carve("ellipsoid", center=(cx + 0.15, cy + 0.05, cz - 0.02), radius=(0.075, 0.07, 0.07))
    S.ell("ClockCore", (cx + 0.035, cy + 0.015, cz - 0.01), (0.06, 0.06, 0.06), keep=True)
    S.paint("ClockShade", "ellipsoid", only="Clock", center=(cx, cy - 0.1, cz), radius=(0.16, 0.06, 0.16))
    S.flat |= {"lb" + k for k in S.g.keys if k}  # tiny pixel heads: no light / dark split (Sculpt.mesh's lb names)
    m = _model(kit, entry, K)
    S.mesh(m, group="Meadow")
    P.attach(m)
    return finish(m, {"source": "LobbyBuilder Meadow (bug #12, client MeadowFx)", "pivot": "ground, +X downwind"})


@prop("meadow_clover")
def meadow_clover(entry, kit):
    """the mown inner lawn's weeds: trefoils on short stalks (one four-leaf), a pink-white clover head"""
    K = 20.0
    S = Sculpt(kit, K, 1.2)
    P = Prisms()
    spots = [(-0.26, 0.12, -0.04, 3), (0.14, 0.15, -0.2, 3), (-0.02, 0.19, 0.22, 4)]
    for i, (x, y, z, nleaf) in enumerate(spots):
        P.stem((x * 0.6, -0.03, z * 0.6), (x, y - 0.015, z), r=0.014, col="StemDark", col2="Stem")
        for l in range(nleaf):
            a = l / nleaf * math.pi * 2 + i * 0.7
            ca, sa = math.cos(a), math.sin(a)
            # a round leaflet (0.15 across) with a pale chevron near its base, tipped up at the rim
            S.g.ell("Clover" if (l + i) % 3 else "CloverLight", (x + ca * 0.08, y, z + sa * 0.08), (0.075, 0.025, 0.075))
    # the clover flower: a small pink-white ball on a taller stalk
    P.stem((0.08, -0.03, 0.02), (0.12, 0.27, 0.04), r=0.014, col="StemDark", col2="Stem")
    S.ell("CloverFlower", (0.12, 0.32, 0.04), (0.055, 0.055, 0.055))
    S.paint("CloverPink", "ellipsoid", only="CloverFlower", center=(0.12, 0.28, 0.04), radius=(0.07, 0.025, 0.07))
    S.flat |= {"lb" + k for k in S.g.keys if k}  # tiny pixel heads: no light / dark split (Sculpt.mesh's lb names)
    m = _model(kit, entry, K)
    S.mesh(m, group="Meadow")
    P.attach(m)
    return finish(m, {"source": "LobbyBuilder Meadow (bug #12, client MeadowFx)", "pivot": "ground, +X downwind"})


# ------------------------------------------------------------------------------------------------- the seed sack
SACK = {"w": 1.15, "d": 0.85, "h": 1.35, "lean": 0.22}  # LobbyBuilder Meadow.sack mirrors these (the Part build)


@prop("lobby_seedsack")
def lobby_seedsack(entry, kit):
    """the torn sack of flower seed slumped against a flower bed (LobbyBuilder Meadow.sack: the Part build's frame).
    Pivot = the ground under the sack's foot; -Z = the bed it leans on; +X = downwind (the tear and the spill).
    A burlap sack (horizontal weave lines, a side seam), its neck bunched and tied with twine, the gathered top flopped
    over, a stamped blue cloud of the seed nursery on its face, split open low on the downwind side with seed pouring
    out onto a mound; a wooden scoop stuck in the mound, three seedlings already up in the spill, and a ladybug."""
    K = 14.0
    S = Sculpt(kit, K, 2.4)
    lean = SACK["lean"]
    R = __import__("nvox.grid", fromlist=["angles"]).angles(-lean, 0, 0)  # top tipped back towards the bed (-Z)
    piv = (0, 0, 0)
    w, d, h = SACK["w"], SACK["d"], SACK["h"]
    # the body: a rounded box, the bottom bulging under the seed's weight
    S.rbox("Burlap", (0, h / 2, 0), (w, h, d), 0.32, rot=R, pivot=piv)
    S.ell("Burlap", (0, 0.32, 0.04), (w * 0.56, 0.34, d * 0.56), rot=R, pivot=piv)
    # neck, twine, the gathered top flopping forward-left
    S.cyl("Burlap", 0, 0, h - 0.05, h + 0.18, 0.24, rot=R, pivot=piv)
    S.cyl("Twine", 0, 0, h + 0.05, h + 0.14, 0.27, rot=R, pivot=piv)
    S.ell("BurlapLight", (-0.08, h + 0.3, 0.05), (0.3, 0.16, 0.22), rot=R, pivot=piv)
    S.ell("BurlapLight", (0.12, h + 0.36, 0.12), (0.16, 0.1, 0.14), rot=R, pivot=piv)
    S.box("Twine", (0.28, h - 0.02, 0.1), (0.08, 0.26, 0.08), rot=R, pivot=piv)  # the loose twine end
    S.g.carve("box", center=(0, -0.3, 0), size=(4, 0.6, 4))
    # a side seam (the weave itself is too fine to show at this size: the cloth stays one soft colour)
    S.paint("BurlapDark", "box", only=["Burlap"], center=(-w / 2, h / 2, 0), size=(0.1, h + 0.4, 0.1), rot=R, pivot=piv)
    # the stamp on the face (+Z, away from the bed): a blue cloud and a little sprout over it
    for (sx, sy, r) in ((-0.17, 0.62, 0.13), (0.02, 0.69, 0.17), (0.2, 0.6, 0.12)):
        S.paint("Stamp", "ellipsoid", only=["Burlap", "BurlapDark"], center=(sx, sy, d / 2 + 0.05),
                radius=(r, r * 0.75, 0.25), rot=R, pivot=piv)
    S.paint("Stamp", "box", only=["Burlap", "BurlapDark"], center=(0.02, 0.92, d / 2 + 0.05), size=(0.08, 0.2, 0.4),
            rot=R, pivot=piv)
    # the tear: a ragged split low on the downwind (+X) side, seed pouring out of it onto a mound
    S.g.carve("ellipsoid", center=(w / 2 + 0.02, 0.42, 0.12), radius=(0.14, 0.2, 0.17))
    S.ell("BurlapDark", (w / 2 - 0.04, 0.42, 0.12), (0.06, 0.23, 0.2), only=None, keep=True)
    S.ell("Seed", (w / 2 - 0.02, 0.38, 0.12), (0.1, 0.16, 0.13), keep=True)
    S.g.cap("Seed", (w / 2 + 0.06, 0.32, 0.12), (w / 2 + 0.36, 0.1, 0.18), 0.1, keep=True)
    S.ell("Seed", (w / 2 + 0.5, 0.06, 0.2), (0.48, 0.13, 0.42), keep=True)
    S.ell("SoilSpill", (w / 2 + 0.7, 0.02, 0.25), (0.62, 0.05, 0.52), keep=True)
    S.paint("SeedDark", "box", only="Seed", center=(w / 2 + 0.4, 0.2, 0.2), size=(1.6, 0.8, 1.2),
            pattern=lambda X, Y, Z, cur: ["SeedDark" if hsh(int(round(X * K)), int(round(Y * K)), int(round(Z * K)), 9) < 0.28
                                          else False for X, Y, Z in zip(X, Y, Z)])
    # scattered seeds blown downwind of the mound
    for i in range(12):
        dd = 1.25 + hsh(i, 81) * 1.4
        S.box("Seed", (w / 2 + dd, 0.05, 0.2 + (hsh(i, 82) - 0.5) * (0.4 + dd * 0.5)), (0.1, 0.1, 0.1))
    # the scoop stuck in the mound, handle up toward the sack
    S.g.cap("ScoopWood", (w / 2 + 0.62, 0.14, 0.32), (w / 2 + 0.38, 0.62, 0.5), 0.05)
    S.ell("ScoopDark", (w / 2 + 0.66, 0.1, 0.3), (0.13, 0.08, 0.11))
    # three seedlings already up in the spill
    for i, (x, z) in enumerate(((w / 2 + 0.95, 0.55), (w / 2 + 1.12, 0.0), (w / 2 + 0.78, -0.2))):
        S.box("Sprout", (x, 0.12, z), (0.1, 0.22, 0.1))
        S.box("Sprout", (x - 0.07, 0.25, z), (0.14, 0.08, 0.1))
        S.box("Sprout", (x + 0.07, 0.27, z), (0.14, 0.08, 0.1))
    # a ladybug on the sack's shoulder
    S.ell("Ladybug", (-0.3, 1.0, d / 2 + 0.03), (0.07, 0.05, 0.08), rot=R, pivot=piv)
    S.box("Spot", (-0.3, 1.04, d / 2 + 0.07), (0.1, 0.05, 0.05), rot=R, pivot=piv)
    # cloth is soft: no voxel light / dark steps on the bag (they read as rock), Roblox's own lighting shades it
    # (Sculpt.mesh renames baked keys to "lb<key>" before it reads `flat`, so name them that way)
    S.flat |= {"lbBurlap", "lbBurlapDark", "lbBurlapLight", "lbStamp"}
    m = _model(kit, entry, K)
    S.mesh(m, group="Sack")
    return finish(m, {"source": "LobbyBuilder Meadow.sack (bug #12)", "pivot": "ground under the sack, -Z = the bed, +X = downwind"})
