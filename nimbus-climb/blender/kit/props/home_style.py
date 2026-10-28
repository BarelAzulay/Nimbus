"""The home bake (art-home): a Part build's boxes -> a fine-voxel mesh in the cute P4 look, with the detail the Part
build cannot afford.  Used by props/home.py (stations at every level + the Garden's bed pieces).

    bake(model, boxes, vs, budget, opts) -> stats

1. Raster: every visible box (props.home.parse_boxes) becomes voxels of `vs` studs (cell centres inside the box; a
   box thinner than a voxel still gets one layer), the biggest first so small trim paints over the walls it sits on.
   Some names get softer SHAPES (bushes, tree crowns, berries, cloud puffs: rounded blobs; basins, bowls, barrels,
   glass pods: rounded footprints) - only ever inside the Part's own box, so nothing pokes through a neighbour.
2. Detail (by part name -> family, on the visible skin only): brick courses + staggered joints on walls, plank seams
   on wood, shingle rows on roofs, tile seams on stone floors, leaf clusters on greenery, grass tufts on lawns,
   soil crumbs, a highlight cell on berries, a soft seam on cushions, ripples on water.
3. Shade like Voxel.Shade: light top skin (Voxel.Lighten), dark underside (Voxel.Darken), deep creases.
4. Mesh: colours baked as vertex colours (greedy, same colours merge).  One opaque part (`Fixed`, or the element's
   name), one part per glass transparency (`Glass`, `Glass2`...).  Over the triangle budget the bake drops detail
   in steps (tufts, joints, speckles, clusters) until it fits.
Deterministic: every random pick comes from a hash of the cell / part (no RNG state).
"""
import math
import re

import numpy as np

from nvox import colors as C
from nvox.mesher import greedy_mesh

DARK = C.shade_dark_factor()

# ------------------------------------------------------------------------------------------------ families
FAMILIES = [
    ("leaf", r"^(Bush|Crown|Vine|Foliage|Garland|FlowerStrip|Hedge|Leaf|Leaves|Canopy|Topiary|Shrub)\d*$"),
    ("berry", r"^(Berry|GoldBerry|BowlBerry|Starberry|Bloom|Blooms|Flowers?|Bud|Fruit)\d*$"),
    ("pile", r"^(BowlBerries|CrateBerries|HopperBerries|TrayBerries|BasketBerries|Coins)\d*$"),
    ("puff", r"^(Puff|CloudPuff)\d*$"),
    ("roof", r"^(Roof|Spire|BarnRoof|BayRoof|PorchRoof|BedRoof|RoofRidge|BarnRoofRidge|Lid|ChimneyCap)\d*$"),
    ("boards", r"^(Barn|ShieldWall)\d*$"),
    ("brick", r"^(Keep|Tower|CornerTower|Walls|Upper|Bay|Wall|Vault|Chimney|Cabinet|ShieldWall)\d*$"),
    ("stone", r"^(Plinth|BarnPlinth|TowerBase|WallBase|WallCap|Lintel|Column|Pillar|Pedestal|Kerb|Stage|Step|Steps|"
              r"Threshold|Porch|Walk|FoodBowl|Basin|BasinFoot|Course|Cornice|Capital|PlinthBand|Keystone|Merlon|"
              r"Pilaster|ChamberBase|ChamberCrown|CaseBase|TrophyStand|Rib|Base|Deck|Sill|RoseFrame)\d*$"),
    ("wood", r"^(Frame|FrameEnd|Crate|Door|BarnDoor|LoftDoor|Rail|Arch|Post|EntrancePost|Shelf|BackRail|TrellisPost|"
             r"TrellisRail|Trunk|Pickets|Planter|FlowerBox|BoardPost|Bed|Headboard|Basket|PressBarrel|"
             r"ShieldWallCap|PorchPost|CornerPost|LanternPost|Crossbar|Pole|DoorBrace|Board|Hurdle|HurdleLeg)\d*$"),
    ("grass", r"^(Grass|Lawn|Mound|Turf)\d*$"),
    ("soil", r"^(Soil|SoilBed)\d*$"),
    ("fabric", r"^(Cushion|Banner|Cloth|Pennant|Carpet|Bunting|Mat|MatIn)\d*$"),
    ("water", r"^(Water|BowlWater)\d*$"),
]
_FAM_RE = [(f, re.compile(p)) for f, p in FAMILIES]

# rounded shapes: name -> ("blob", exponent, grow) 3D super-ellipsoid inside the box (grow = scale of the radii,
# clipped to the box), or ("disc", exponent) rounded footprint in x/z
SHAPES = {
    "Bush": ("blob", 2.4, 1.0, 2), "Crown": ("blob", 2.4, 1.0, 2), "Vine": ("bevel", 1), "Berry": ("blob", 2.0, 1.0),
    "GoldBerry": ("blob", 2.0, 1.0), "BowlBerry": ("blob", 2.0, 1.0), "Puff": ("blob", 2.6, 1.0),
    "Bell": ("blob", 2.4, 1.0), "OutputDome": ("blob", 2.4, 1.0), "Pod": ("disc", 2.6), "Chamber": ("disc", 3.0),
    "Basin": ("disc", 6.0), "BasinFoot": ("disc", 6.0), "Water": ("disc", 6.0), "Bowl": ("disc", 3.0),
    "BowlWater": ("disc", 3.0), "FoodBowl": ("disc", 3.0), "BowlRim": ("disc", 3.0), "BowlBerries": ("disc", 3.0),
    "PressBarrel": ("disc", 2.6), "Hopper": ("disc", 3.5), "Funnel": ("disc", 3.0), "PodBase": ("disc", 3.0),
    "PodLid": ("disc", 3.0), "Hoop": ("disc", 3.0), "Mound": ("disc", 2.6), "Trim": ("disc", 3.0),
}


# extra shape kinds / families registered by a style module (props/home_allotment.py): kind -> fn
EXTRA_SHAPES = {}
EXTRA_FAMILIES = {}


def family(name):
    for f, rx in _FAM_RE:
        if rx.match(name):
            return f
    return "plain"


def _hash(*v):
    """deterministic 0..1 from ints"""
    h = 2166136261
    for x in v:
        h = ((h ^ (int(x) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return h / 4294967295.0


def _hash_arr(*arrs):
    """vectorised _hash over int arrays"""
    h = np.full(np.broadcast(*arrs).shape, 2166136261, np.uint64)
    for a in arrs:
        h = ((h ^ (np.asarray(a).astype(np.int64).astype(np.uint64) & np.uint64(0xFFFFFFFF))) * np.uint64(16777619)) \
            & np.uint64(0xFFFFFFFF)
    h ^= h >> np.uint64(13)
    h = (h * np.uint64(0x5BD1E995)) & np.uint64(0xFFFFFFFF)
    h ^= h >> np.uint64(15)
    return h.astype(np.float64) / 4294967295.0


# ------------------------------------------------------------------------------------------------ raster
class Raster:
    def __init__(self, boxes, vs, pad=2, align=True):
        self.vs = vs
        self.boxes = boxes
        lo = np.full(3, np.inf)
        hi = np.full(3, -np.inf)
        for b in boxes:
            h = b["size"] / 2
            ext = np.abs(b["R"]) @ h
            lo = np.minimum(lo, b["pos"] - ext)
            hi = np.maximum(hi, b["pos"] + ext)
        if not boxes:
            lo, hi = np.zeros(3), np.zeros(3)
        self.off = self._align(boxes, vs) if align else np.zeros(3)
        # grid index i covers [off + i*vs, off + (i+1)*vs); keep lo / hi inside with a margin
        i0 = np.floor((lo - self.off) / vs).astype(int) - pad
        i1 = np.ceil((hi - self.off) / vs).astype(int) + pad
        self.i0 = i0
        self.shape = tuple(int(x) for x in (i1 - i0))
        self.col = np.zeros(self.shape, np.int64)      # packed rgb + 1 (0 = empty)
        self.pid = np.full(self.shape, -1, np.int32)   # owning box index
        self.glass = np.zeros(self.shape, np.int16)    # glass transparency * 100 (0 = not glass)

    @staticmethod
    def _align(boxes, vs):
        """grid offset (x / z) that puts the big boxes' faces on voxel boundaries; y keeps the ground at 0"""
        off = np.zeros(3)
        for ax in (0, 2):
            best, best_err = 0.0, None
            for k in range(8):
                o = vs * k / 8.0
                err = 0.0
                for b in boxes:
                    if not _axis_aligned(b["R"]):
                        continue
                    ext = (np.abs(b["R"]) @ (b["size"] / 2))[ax]
                    w = float(np.prod(b["size"])) ** (2.0 / 3.0)
                    for f in (b["pos"][ax] - ext, b["pos"][ax] + ext):
                        r = ((f - o) / vs) % 1.0
                        err += w * min(r, 1 - r)
                if best_err is None or err < best_err - 1e-9:
                    best, best_err = o, err
            off[ax] = best
        return off

    def centers(self, sl):
        """cell centres (studs) of a slice tuple"""
        axes = []
        for a in range(3):
            idx = np.arange(sl[a].start, sl[a].stop)
            axes.append(self.off[a] + (idx + self.i0[a] + 0.5) * self.vs)
        return np.meshgrid(axes[0], axes[1], axes[2], indexing="ij")

    def box_slice(self, b, grow=0.0):
        h = b["size"] / 2 + grow
        ext = np.abs(b["R"]) @ h + self.vs
        lo = np.floor((b["pos"] - ext - self.off) / self.vs).astype(int) - self.i0
        hi = np.ceil((b["pos"] + ext - self.off) / self.vs).astype(int) - self.i0 + 1
        lo = np.maximum(lo, 0)
        hi = np.minimum(hi, self.shape)
        return tuple(slice(int(a), int(c)) for a, c in zip(lo, hi))

    def local(self, b, X, Y, Z):
        d = np.stack([X - b["pos"][0], Y - b["pos"][1], Z - b["pos"][2]], -1)
        return d @ b["R"]  # (R^T d) per cell: columns of R are the part axes

    def inside(self, b, L):
        """mask of cells whose centre is inside the box (thin dimensions get one layer) + its shape"""
        # a thin part still gets one voxel layer; a thin part at an odd angle (crossed swords, braces) a bit more,
        # so its diagonal stays one connected line
        h = np.maximum(b["size"] / 2, self.vs * (0.5 if _axis_aligned(b["R"]) else 0.72))
        m = (np.abs(L[..., 0]) <= h[0] + 1e-6) & (np.abs(L[..., 1]) <= h[1] + 1e-6) & (np.abs(L[..., 2]) <= h[2] + 1e-6)
        shp = b.get("shp") or SHAPES.get(b["name"])  # a style's box may carry its own shape
        if shp is None:
            return m
        if shp[0] in EXTRA_SHAPES:
            return m & EXTRA_SHAPES[shp[0]](self, b, L, h, shp)
        q = np.maximum(h, self.vs)
        if shp[0] == "blob":
            p = shp[1]
            Lc = L
            if len(shp) > 3 and shp[3] > 1:
                # coarse blob: the round outline is decided on blocks of shp[3] voxels (chunkier steps, fewer faces)
                g = self.vs * shp[3]
                Lc = (np.floor((L + q) / g) + 0.5) * g - q
            r = (np.abs(Lc[..., 0]) / q[0]) ** p + (np.abs(Lc[..., 1]) / q[1]) ** p + (np.abs(Lc[..., 2]) / q[2]) ** p
            return m & (r <= 1.0 + 1e-6)
        if shp[0] == "bevel":
            n = shp[1]
            hh = np.maximum(b["size"] / 2, self.vs * 0.5)
            e = np.zeros(L.shape[:-1])
            for a in range(3):
                if b["size"][a] >= (2 * n + 2) * self.vs:
                    d = np.floor((hh[a] - np.abs(L[..., a])) / self.vs + 1e-6)
                    e = e + np.maximum(0, n - d)
            return m & (e <= n)
        if shp[0] == "disc":
            p = shp[1]
            r = (np.abs(L[..., 0]) / q[0]) ** p + (np.abs(L[..., 2]) / q[2]) ** p
            return m & (r <= 1.0 + 1e-6)
        return m

    def paint(self):
        order = sorted(range(len(self.boxes)), key=lambda i: (-float(np.prod(self.boxes[i]["size"])), i))
        for i in order:
            b = self.boxes[i]
            sl = self.box_slice(b)
            if any(s.stop <= s.start for s in sl):
                continue
            X, Y, Z = self.centers(sl)
            L = self.local(b, X, Y, Z)
            m = self.inside(b, L)
            if not m.any():
                # tiny part: at least its centre cell
                ci = tuple(int(np.floor((b["pos"][a] - self.off[a]) / self.vs)) - self.i0[a] for a in range(3))
                if all(0 <= ci[a] < self.shape[a] for a in range(3)):
                    self._set(ci, i, b)
                continue
            r, g, bb = b["rgb"]
            packed = ((r << 16) | (g << 8) | bb) + 1
            sub_c = self.col[sl]
            sub_p = self.pid[sl]
            sub_g = self.glass[sl]
            sub_c[m] = packed
            sub_p[m] = i
            sub_g[m] = int(round(b["tr"] * 100)) if b["mat"] == "Glass" else 0

    def _set(self, ci, i, b):
        r, g, bb = b["rgb"]
        self.col[ci] = ((r << 16) | (g << 8) | bb) + 1
        self.pid[ci] = i
        self.glass[ci] = int(round(b["tr"] * 100)) if b["mat"] == "Glass" else 0


def _axis_aligned(R):
    return bool(np.all(np.isclose(np.abs(R), np.round(np.abs(R)), atol=1e-4)))


# ------------------------------------------------------------------------------------------------ detail
def _neighbours_empty(occ):
    """6 bool arrays: the neighbour in -x, +x, -y, +y, -z, +z is empty"""
    pad = np.pad(occ, 1)
    n = occ.shape
    out = []
    for a in range(3):
        for s in (-1, 1):
            sl = [slice(1, 1 + n[0]), slice(1, 1 + n[1]), slice(1, 1 + n[2])]
            sl[a] = slice(1 + s, 1 + s + n[a])
            out.append(~pad[tuple(sl)])
    return out


class Detail:
    """colour factors per cell (multiplied into the base colour), extra cells (tufts), per-family rules"""

    def __init__(self, R, level):
        self.R = R
        self.level = level  # 3 = everything, 0 = shading only
        occ = R.col != 0
        self.occ = occ
        self.opaque = occ & (R.glass == 0)
        self.nb = _neighbours_empty(occ)
        self.skin = occ & np.logical_or.reduce(self.nb)
        self.fac = np.ones(R.shape, np.float64)
        self.mix = np.zeros(R.shape + (4,), np.float64)  # rgb target + weight (lerp toward)
        self.extra = {}  # (i, j, k) -> packed colour (new cells: tufts)
        self.stats = {}

    def run(self):
        R = self.R
        fams = [b.get("fam") or family(b["name"]) for b in R.boxes]  # a style's box may carry its own family
        idx = np.argwhere(self.skin)
        if len(idx) == 0:
            return
        pids = R.pid[idx[:, 0], idx[:, 1], idx[:, 2]]
        by = {}
        for f in set(fams):
            by[f] = []
        order = np.argsort(pids, kind="stable")
        idx, pids = idx[order], pids[order]
        cuts = np.nonzero(np.diff(pids))[0] + 1
        for grp in np.split(np.arange(len(pids)), cuts):
            if len(grp) == 0:
                continue
            pi = int(pids[grp[0]])
            if pi < 0:
                continue
            fn = getattr(self, "fam_" + fams[pi], None)
            if fn:
                fn(R.boxes[pi], pi, idx[grp])
            elif fams[pi] in EXTRA_FAMILIES:
                EXTRA_FAMILIES[fams[pi]](self, R.boxes[pi], pi, idx[grp])
        self.stats["level"] = self.level

    # local integer coordinates (cells) of skin cells in a part's frame + which faces are open
    def _local(self, b, cells):
        R = self.R
        c = R.off + (cells + R.i0 + 0.5) * R.vs
        L = (c - b["pos"]) @ b["R"]
        h = b["size"] / 2
        q = np.floor((L + h) / R.vs + 1e-6).astype(int)
        return L, q

    def _faces(self, cells):
        nb = self.nb
        i, j, k = cells[:, 0], cells[:, 1], cells[:, 2]
        top = nb[3][i, j, k]
        bottom = nb[2][i, j, k]
        sx = nb[0][i, j, k] | nb[1][i, j, k]
        sz = nb[4][i, j, k] | nb[5][i, j, k]
        return top, bottom, sx, sz

    def _scale(self, cells, f):
        self.fac[cells[:, 0], cells[:, 1], cells[:, 2]] *= f

    def _toward(self, cells, rgb, w):
        m = self.mix[cells[:, 0], cells[:, 1], cells[:, 2]]
        m[:, :3] = rgb
        m[:, 3] = w
        self.mix[cells[:, 0], cells[:, 1], cells[:, 2]] = m

    # ------------------------------------------------------------------ families
    def fam_brick(self, b, pi, cells):
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        side = (sx | sz) & ~top
        course = 2 if b["size"][1] < 6 else 3                  # brick height in cells
        md = min(b["size"][0], b["size"][2])
        brick = 4 if md < 3 else (6 if md < 6 else 8)
        row = q[:, 1] // course
        mortar_h = (q[:, 1] % course == 0) & (q[:, 1] > 0)
        f = np.ones(len(cells))
        f[side & mortar_h] = 0.94
        if self.level >= 2:
            u = np.where(sz, q[:, 0], q[:, 2])
            stagger = (row % 2) * (brick // 2)
            joint = ((u + stagger) % brick == 0) & ~mortar_h
            f[side & joint] = 0.95
            # a few bricks a touch lighter / warmer (hand-made look)
            pick = _hash_arr(row, (u + stagger) // brick, pi) < 0.12
            f[side & ~mortar_h & ~joint & pick] = 1.03
        # quoins: the vertical corners of a wall, every other course a lighter stone
        corner = sx & sz & ~top
        f[corner & (row % 2 == 0)] = 1.05
        self._scale(cells, f)

    def fam_boards(self, b, pi, cells):
        """vertical boards (the red barn): a darker seam every 3 cells + a lighter top rail"""
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        u = np.where(sz, q[:, 0], q[:, 2])
        f = np.ones(len(cells))
        f[(sx | sz) & ~top & (u % 3 == 0)] = 0.9
        n = int(round(b["size"][1] / self.R.vs))
        f[(sx | sz) & ~top & (q[:, 1] >= n - 2)] *= 1.06
        self._scale(cells, f)

    def fam_stone(self, b, pi, cells):
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        f = np.ones(len(cells))
        big = b["size"][0] >= 3 and b["size"][2] >= 3
        if big:
            tile = 4 if max(b["size"][0], b["size"][2]) < 12 else 8
            seam = (q[:, 0] % tile == 0) | (q[:, 2] % tile == 0)
            f[top & seam] = 0.95
            if self.level >= 2:
                pick = _hash_arr(q[:, 0] // tile, q[:, 2] // tile, pi) < 0.25
                f[top & ~seam & pick] = 1.025
        if b["size"][1] >= 1.0:
            mid = (q[:, 1] % 4 == 0) & (q[:, 1] > 0)
            f[(sx | sz) & ~top & mid] = 0.95
        self._scale(cells, f)

    def fam_wood(self, b, pi, cells):
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        s = b["size"]
        ax = int(np.argmax(s))  # planks run along the longest axis
        others = [a for a in range(3) if a != ax]
        f = np.ones(len(cells))
        for a in others:
            if s[a] >= 4 * self.R.vs:
                stripe = (q[:, a] // 2) % 2 == 1
                f[stripe] *= 0.94
        if self.level >= 2 and s[ax] >= 6 * self.R.vs:
            knot = _hash_arr(q[:, 0], q[:, 1], q[:, 2], pi) < 0.03
            f[knot] *= 0.9
        self._scale(cells, f)

    def fam_roof(self, b, pi, cells):
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        f = np.ones(len(cells))
        if b["name"] != "Spire":  # the stepped spires are detail enough (their tiers already read as rows)
            row = (q[:, 1] % 2 == 0)
            f[(sx | sz) & ~top & row] = 0.93
        if self.level >= 2 and b["name"] != "Spire" and min(b["size"][0], b["size"][2]) >= 3:
            # shingle tabs on the top faces: a checker of 2-cell tabs, every other row offset
            r = q[:, 2] // 2
            tab = ((q[:, 0] + (r % 2) * 1) // 2) % 2 == 0
            f[top & tab] = 0.96
        self._scale(cells, f)

    def fam_leaf(self, b, pi, cells):
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        f = np.ones(len(cells))
        if self.level >= 1:
            cl = 3 if b["name"] not in ("Crown",) else 2
            n = _hash_arr(q[:, 0] // cl, q[:, 1] // cl, q[:, 2] // cl, pi)
            f[n < 0.25] = 0.88
            if self.level >= 2:
                f[n > 0.85] = 1.08
        self._scale(cells, f)
        if self.level >= 2 and b["name"] in ("Bush", "Crown"):
            # a few lighter leaf tips on the upper half
            up = L[:, 1] > b["size"][1] * 0.1
            tip = _hash_arr(q[:, 0], q[:, 1], q[:, 2], pi + 7) < 0.10
            sel = cells[up & tip & top]
            self._toward(sel, (0.72, 0.92, 0.48), 0.35)

    def fam_berry(self, b, pi, cells):
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        # one bright shine on the upper front-left
        h = b["size"] / 2
        score = L[:, 1] / max(h[1], 1e-6) - L[:, 2] / max(h[2], 1e-6) * 0.6 - L[:, 0] / max(h[0], 1e-6) * 0.4
        if len(score):
            k = int(np.argmax(score))
            self._toward(cells[k:k + 1], (1.0, 1.0, 1.0), 0.55)

    def fam_pile(self, b, pi, cells):
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        n = _hash_arr(q[:, 0], q[:, 2], pi)
        f = np.where(n < 0.3, 0.86, np.where(n > 0.85, 1.12, 1.0))
        self._scale(cells, f)

    def fam_puff(self, b, pi, cells):
        pass

    def fam_grass(self, b, pi, cells):
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        f = np.ones(len(cells))
        if self.level >= 2:
            n = _hash_arr(q[:, 0] // 3, q[:, 2] // 3, pi)
            f[top & (n < 0.12)] = 0.93
            f[top & (n > 0.92)] = 1.05
        self._scale(cells, f)
        if self.level >= 3:
            # tufts: single blades one cell above the lawn (sparse; never on a wide walk-through lawn centre)
            R = self.R
            t = cells[top]
            qt = q[top]
            pick = _hash_arr(qt[:, 0], qt[:, 2], pi + 3) < 0.022
            r, g, bb = b["rgb"]
            tuft = (min(255, int(r * 0.92)), min(255, int(g * 1.06)), min(255, int(bb * 0.9)))
            packed = ((tuft[0] << 16) | (tuft[1] << 8) | tuft[2]) + 1
            for c in t[pick]:
                up = (int(c[0]), int(c[1]) + 1, int(c[2]))
                if up[1] < R.shape[1] and R.col[up] == 0:
                    self.extra[up] = packed
            self.stats["tufts"] = self.stats.get("tufts", 0) + int(pick.sum())

    def fam_soil(self, b, pi, cells):
        if self.level < 2:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        n = _hash_arr(q[:, 0], q[:, 2], pi)
        f = np.ones(len(cells))
        f[top & (n < 0.12)] = 0.8
        f[top & (n > 0.94)] = 1.15
        self._scale(cells, f)

    def fam_fabric(self, b, pi, cells):
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        h = b["size"]
        n = np.round(h / self.R.vs).astype(int)
        edge = (q[:, 0] <= 0) | (q[:, 0] >= n[0] - 1) | (q[:, 2] <= 0) | (q[:, 2] >= n[2] - 1)
        f = np.ones(len(cells))
        f[top & edge] = 0.93
        if self.level >= 2 and b["name"] in ("Banner", "Cloth", "Pennant", "Carpet", "Mat"):
            ax = 0 if h[0] >= h[2] else 2
            stripe = (q[:, 1] // 2) % 3 == 0 if b["name"] in ("Banner", "Cloth", "Pennant") else (q[:, ax] // 2) % 3 == 0
            f[stripe & ~top] *= 0.92
        self._scale(cells, f)

    def fam_water(self, b, pi, cells):
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        ring = ((np.hypot(L[:, 0], L[:, 2]) / (self.R.vs * 3)).astype(int) % 2) == 0
        f = np.where(top & ring, 1.06, 1.0)
        self._scale(cells, f)

    def fam_plain(self, b, pi, cells):
        pass


# ------------------------------------------------------------------------------------------------ shade + mesh
def _unpack(col):
    v = col - 1
    return np.stack([(v >> 16) & 255, (v >> 8) & 255, v & 255], -1).astype(np.float64) / 255.0


def shade_and_colors(R, D):
    """final 0..1 colours of every occupied cell (incl. extra cells), Voxel.Shade-like skins"""
    col = R.col.copy()
    for (i, j, k), packed in D.extra.items():
        col[i, j, k] = packed
    occ = col != 0
    rgb = _unpack(np.where(occ, col, 1))
    rgb *= D.fac[..., None]
    w = D.mix[..., 3:4]
    rgb = rgb * (1 - w) + D.mix[..., :3] * w
    nb = _neighbours_empty(occ)
    top = nb[3] & occ
    bottom = nb[2] & occ & ~top
    light = np.array(C.shade_light((0.0, 0.0, 0.0)))  # lerp target part: shade_light(c) = c + (1 - c) * t
    t = light.max() if light.max() > 0 else 0.15
    # catalog args "topLight" (default 1): a coarse LOD bake whose parts are one cell thick (the farm _low keys, 0.5
    # studs) shows the lightened top cell on every side, so it scales the top skin down to keep the High key's colours
    t *= float(getattr(R, "top_light", 1.0))
    rgb[top] = rgb[top] + (1.0 - rgb[top]) * t
    rgb[bottom] = rgb[bottom] * np.array(DARK)
    # deep creases: occupied cells under an overhang (empty below, occupied 1-2 cells beside below) - cheap AO
    rgb = np.clip(rgb, 0, 1)
    return col, occ, rgb


def _quantise(rgb):
    q = np.round(rgb * 255).astype(np.int64)
    return (q[..., 0] << 16) | (q[..., 1] << 8) | q[..., 2]


def _emit(m, name, mask, rgbq, R, material="SmoothPlastic", transparency=0.0, group=None):
    """greedy-mesh the cells of `mask` (each a closed set on its own) into object `name`"""
    if not mask.any():
        return None
    labels, inv = np.unique(rgbq[mask], return_inverse=True)
    F = np.zeros(mask.shape, np.int32)
    F[mask] = inv.reshape(-1) + 1
    quads = greedy_mesh(F, mask, 0)
    o = m.obj(name, group=group or name, region="Fixed", shade="fixed", recipe=None, material=material, baked=True)
    if transparency:
        o.transparency = transparency
    o.key = name
    o.keys.add(name)
    base = R.off + (R.i0 + 0.5) * R.vs
    for lab, qs in quads.items():
        v = int(labels[lab - 1])
        c = (((v >> 16) & 255) / 255.0, ((v >> 8) & 255) / 255.0, (v & 255) / 255.0)
        for corners, a, sign in qs:
            o.quads.append((np.asarray(corners, float) * R.vs + base, c))
    return o


def _split_x(mask, parts):
    """split a mask into `parts` slabs along its longest horizontal axis (by occupied-cell count)"""
    ax = 0 if mask.shape[0] >= mask.shape[2] else 2
    counts = mask.sum(axis=(1, 2) if ax == 0 else (0, 1))
    cum = np.cumsum(counts)
    cuts = [int(np.searchsorted(cum, cum[-1] * k / parts)) for k in range(1, parts)]
    out = []
    lo = 0
    for c in cuts + [mask.shape[ax]]:
        mm = np.zeros_like(mask)
        if ax == 0:
            mm[lo:c] = mask[lo:c]
        else:
            mm[:, :, lo:c] = mask[:, :, lo:c]
        out.append(mm)
        lo = c
    return out


def mesh_all(m, R, D, solid_name="Fixed", part_limit=9000):
    col, occ, rgb = shade_and_colors(R, D)
    rgbq = _quantise(rgb)
    glass = R.glass.copy()
    for k in D.extra:
        glass[k] = 0
    solid = occ & (glass == 0)
    made = []
    o = _emit(m, solid_name, solid, rgbq, R)
    if o is not None and o.tris() > part_limit:
        del m.objects[solid_name]
        n = int(math.ceil(o.tris() / float(part_limit))) + 1
        for i, sub in enumerate(_split_x(solid, n)):
            nm = solid_name if i == 0 else "%s%d" % (solid_name, i + 1)
            oo = _emit(m, nm, sub, rgbq, R)
            if oo is not None:
                made.append(oo)
    elif o is not None:
        made.append(o)
    trs = sorted(set(int(x) for x in np.unique(glass[occ]) if x > 0))
    # glass groups: transparency rounded to 0.1 (Pod 0.55 / Chamber 0.6 share a part)
    groups = {}
    for t in trs:
        groups.setdefault(int(round(t / 10.0)), []).append(t)
    for gi, (tt, members) in enumerate(sorted(groups.items())):
        mask = occ & np.isin(glass, members)
        nm = "Glass" if gi == 0 else "Glass%d" % (gi + 1)
        oo = _emit(m, nm, mask, rgbq, R, material="Glass", transparency=round(tt / 10.0, 2))
        if oo is not None:
            made.append(oo)
    return made


def bake(m, boxes, vs, budget=4000, opts=None):
    """boxes -> m's objects; returns stats.  Steps the detail level down until the triangles fit `budget`."""
    opts = opts or {}
    R = Raster(boxes, vs, align=opts.get("align", True))
    R.top_light = float(opts.get("topLight", 1.0))
    R.paint()
    name = opts.get("name") or "Fixed"
    tries = []
    import os
    # HOME_DETAIL (scratch runs) wins; else the catalog's args.detail (the *_low plot LOD keys); else step down
    force = os.environ.get("HOME_DETAIL") or (opts.get("detail") is not None and str(opts["detail"])) or None
    levels = (int(force),) if force else (3, 2, 1, 0)
    if opts.get("tint"):
        # tinted per instance (the Garden's cushions come in 5 colours): white voxels, so the vertex colours carry
        # only the shading; MeshPart.Color = the ML_Primary look (HomeBuilder tags the part with its own Color)
        occ = R.col != 0
        R.col[occ] = ((255 << 16) | (255 << 8) | 255) + 1
    for level in levels:
        m.objects.clear()
        D = Detail(R, level)
        D.run()
        mesh_all(m, R, D, solid_name=name)
        if opts.get("tint"):
            for o in m.objects.values():
                if o.material == "SmoothPlastic":
                    o.baked, o.shade, o.recipe = False, "base", ["Primary"]
        t = m.tris()
        tries.append((level, t))
        if t <= budget:
            break
    return {"vs": vs, "cells": int((R.col != 0).sum()), "level": tries[-1][0], "tries": tries,
            "shape": list(R.shape)}
