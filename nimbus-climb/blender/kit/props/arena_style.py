"""The arena / dungeon bake (art-arenadungeon): a tagged Part build's boxes -> a fine-voxel mesh in the cute P4 look.
Started as a copy of props/home_style.py (art-home's bake: raster, families, shading, greedy mesh) so the two classes
never break each other; extended for the arena and the dungeon:

    bake(model, boxes, vs, budget, opts) -> stats      opts: tints {part name: "Primary" | "Secondary"}, solid (name
                                                        of the baked part), soften (cloud rounding, cells), aligny,
                                                        rock (seeded rock shapes for "Rock" boxes)

1. Raster: every visible box becomes voxels of `vs` studs (cell centres inside the box), the biggest first so small
   trim paints over the walls it sits on; soft SHAPES (leaves, hedges, puffs, flowers) stay inside the Part's box.
   x / z (and y with aligny) offsets put the big faces on voxel boundaries, so walk heights match the colliders.
2. Detail by part name -> family on the visible skin: stone blocks with mortar (walls, parapets: the lilac dungeon
   stone, the cream colosseum), cobbles, flagstones with seams and worn corners, marble veins, sand speckles, grass,
   leaf clusters, plank seams, fabric weave + hems (seats, banners, carpets), metal shine edges, rock strata, puffs.
3. Shade like Voxel.Shade: light top skin, dark underside.  Clouds (soften) lose their hard 4-stud corners.
4. Mesh: colours baked as vertex colours (greedy).  One opaque part (`Fixed` or opts.solid, split past 9k triangles),
   one part per tint name (white voxels: vertex colours = shading only, Color = the ML_Primary / ML_Secondary look),
   one per glass transparency.  Over the triangle budget the bake drops detail in steps until it fits.
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
    ("puff", r"^(Cloud|Puff|PuffBody|PuffTop|PuffBump|PuffArm)\d*$"),
    ("leaf", r"^(Leaves|Hedge|Bush|Crown)\d*$"),
    ("flower", r"^(Fl\d|Flower|Berry)\d*$"),
    ("brick", r"^(Wall|Parapet|PlanterBox|Kerb|Curb)\d*$"),
    ("cobble", r"^(Promenade|Apron|RingApron|PocketApron|PlazaRing|Deck)\d*$"),
    ("flag", r"^(Floor|AvenueTile|PlazaTile|TrophyTile|StandStep|Step|Podium|TierA|TierB|Passage|ArrivalStar)\d*$"),
    ("marble", r"^(Cornice|Pilaster|Pillar|Post|ArchPillar|ArchLintel|AvenueBorder|CurbTop|PlanterCap|RingLine|FloorLine|"
               r"RingRim|CurbCoping|Lintel|Plinth|Base)\d*$"),
    ("stone", r"^(Cap|Course|Dado|PillarBase|PillarCap|PostBase|PostPlinth|Back|Jamb|Pier|Underside|DeckEdge|KerbLip|"
              r"ArchPillarBase|ArchPillarBand|TorchBase|PoleBase|LanternFoot|Capital|FloorBand|ElementMark|WheelPetal|"
              r"EmblemDisc|StandNosing|Recess)\d*$"),
    ("sand", r"^(Sand|SandLight|SandDark|SandPale|RingFloor|RingCanvas|Soil)\d*$"),
    ("grass", r"^(Lawn|LawnLight|Grass|TreeBed)\d*$"),
    ("fabric", r"^(Seat|Banner|Runner|Carpet|Crest)\d*$"),
    ("wood", r"^(Crate|Slat|Chest|ChestLid|Stick|Trunk|Pole|LanternPost|CrossBar|LanternRoof)\d*$"),
    ("metal", r"^(Gold|Iron|Sconce|Bracket|Blade|Guard|Sword|ChestLock|PostCap|LintelTrim|CrestRim|WheelRay|WheelRim|"
              r"WheelCore|FloorGold|ElementFrame|ChallengePad|PadMark|SpawnPad|ChampionPad|EmblemCrown|CrownBand|"
              r"CrownPoint|TorchBowl|TorchPole|ArchCap|PoleTop|BannerTrim|BannerMark|Abacus|Brazier|ArrivalHeart|"
              r"ArchSignTrim|Accent)\d*$"),
    ("rock", r"^(Rock|Stalagmite)\d*$"),
]
_FAM_RE = [(f, re.compile(p)) for f, p in FAMILIES]

# rounded shapes: name -> ("blob", exponent, grow) 3D super-ellipsoid inside the box (grow = scale of the radii,
# clipped to the box), or ("disc", exponent) rounded footprint in x/z
SHAPES = {
    "Leaves": ("blob", 2.2, 1.0, 2), "Hedge": ("bevel", 2), "Bush": ("blob", 2.4, 1.0, 2), "Crown": ("blob", 2.4, 1.0, 2),
    "PuffBody": ("blob", 2.4, 1.0), "PuffTop": ("blob", 2.4, 1.0), "PuffBump": ("blob", 2.2, 1.0),
    "Flower": ("blob", 2.0, 1.0), "Trunk": ("bevel", 1), "PlanterCap": ("bevel", 1),
}


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
    def __init__(self, boxes, vs, pad=2, align=True, offy=None):
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
        if offy is not None:
            self.off[1] = offy
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
        shp = SHAPES.get(b["name"])
        if shp is None:
            return m
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
        # thin overlays (runners, lines, inlays, trims: < 0.6 stud thick) after the solids they lie on, then the biggest
        # first so small trim paints over the walls it sits on
        order = sorted(range(len(self.boxes)), key=lambda i: (float(np.min(self.boxes[i]["size"])) < 0.6,
                                                              -float(np.prod(self.boxes[i]["size"])), i))
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
        fams = [family(b["name"]) for b in R.boxes]
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
    def _hash(self, *a):
        return _hash_arr(*a)

    def fam_brick(self, b, pi, cells):
        """stone blocks (dungeon walls, colosseum walls, parapets, kerbs): mortar courses + staggered joints, a few
        blocks lighter / darker, rounded-looking corner quoins"""
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        vs = self.R.vs
        side = (sx | sz) & ~top
        course = max(2, int(round(1.0 / vs)))                  # ~1 stud courses
        blk = max(3, int(round(2.0 / vs)))                     # ~2 stud blocks
        if b["size"][1] < 2.0:
            course = max(2, int(round(0.5 / vs)))
            blk = max(3, int(round(1.25 / vs)))
        row = q[:, 1] // course
        mortar_h = (q[:, 1] % course == 0) & (q[:, 1] > 0)
        u = np.where(sz, q[:, 0], q[:, 2])
        stagger = (row % 2) * (blk // 2)
        joint = ((u + stagger) % blk == 0) & ~mortar_h
        f = np.ones(len(cells))
        f[side & mortar_h] = 0.88
        if self.level >= 2:
            f[side & joint] = 0.9
            n = self._hash(row, (u + stagger) // blk, pi)
            body = side & ~mortar_h & ~joint
            f[body & (n < 0.14)] = 0.95
            f[body & (n > 0.86)] = 1.05
        if self.level >= 3:
            # chipped block corners: a mortar-dark cell at some block corners
            corner = ((u + stagger) % blk == 1) & (q[:, 1] % course == 1)
            f[side & corner & (self._hash(row, u, pi + 5) < 0.18)] = 0.92
        top_m = top & ((q[:, 0] % blk == 0) | (q[:, 2] % blk == 0))
        f[top_m] *= 0.95
        self._scale(cells, f)

    def fam_cobble(self, b, pi, cells):
        """round-ish cobbles on top: offset rows of small stones, each its own tint, dark gaps"""
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        vs = self.R.vs
        st = max(3, int(round(1.0 / vs)))
        r = q[:, 2] // st
        u = q[:, 0] + (r % 2) * (st // 2)
        gap = (u % st == 0) | (q[:, 2] % st == 0)
        n = self._hash(u // st, r, pi)
        f = np.ones(len(cells))
        f[top & gap] = 0.86
        if self.level >= 2:
            f[top & ~gap] = np.where(n[top & ~gap] < 0.3, 0.95, np.where(n[top & ~gap] > 0.8, 1.05, 1.0))
        f[(sx | sz) & ~top & (q[:, 1] % 2 == 0)] *= 0.95
        self._scale(cells, f)

    def fam_flag(self, b, pi, cells):
        """flagstones / tiles / steps: a seam around every slab + worn corners, a soft per-slab tint"""
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        vs = self.R.vs
        n = np.round(b["size"] / vs).astype(int)
        big = b["size"][0] >= 4 and b["size"][2] >= 4
        f = np.ones(len(cells))
        edge = (q[:, 0] <= 0) | (q[:, 0] >= n[0] - 1) | (q[:, 2] <= 0) | (q[:, 2] >= n[2] - 1)
        f[top & edge] = 0.9
        if big:
            # sub-slabs (a big flagstone reads as 2-3 stones)
            sub = max(6, int(round(3.0 / vs)))
            seam = ((q[:, 0] % sub == 0) & (q[:, 2] % (2 * sub) < sub)) | ((q[:, 2] % sub == 0) & (q[:, 0] % (2 * sub) >= sub))
            f[top & seam & ~edge] = 0.93
        if self.level >= 2:
            sp = self._hash(q[:, 0], q[:, 2], pi + 11)
            f[top & ~edge & (sp < 0.04)] = 0.94
            f[top & ~edge & (sp > 0.975)] = 1.05
        if self.level >= 3:
            cor = ((q[:, 0] <= 1) | (q[:, 0] >= n[0] - 2)) & ((q[:, 2] <= 1) | (q[:, 2] >= n[2] - 2))
            f[top & cor] = 0.86
        f[(sx | sz) & ~top] *= 0.97
        self._scale(cells, f)

    def fam_marble(self, b, pi, cells):
        """white marble trims: a few soft veins, a bright top edge"""
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        f = np.ones(len(cells))
        if self.level >= 2:
            v = (q[:, 0] + q[:, 1] * 2 + q[:, 2]) % 11 == 0
            f[v & (self._hash(q[:, 0] // 3, q[:, 1] // 3, q[:, 2] // 3, pi) < 0.5)] = 0.95
        n = np.round(b["size"] / self.R.vs).astype(int)
        lip = (sx | sz) & (q[:, 1] >= n[1] - 1)
        f[lip] *= 1.04
        if b["size"][1] >= 3 and self.level >= 1:
            # column flutes: a darker line every few cells on tall pieces
            u = np.where(sz, q[:, 0], q[:, 2])
            f[(sx | sz) & ~top & (u % 3 == 1) & (q[:, 1] > 1) & (q[:, 1] < n[1] - 2)] *= 0.94
        self._scale(cells, f)

    def fam_stone(self, b, pi, cells):
        """trim stone (caps, plinths, bases): a groove line on tall faces, soft speckle"""
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        n = np.round(b["size"] / self.R.vs).astype(int)
        f = np.ones(len(cells))
        if n[1] >= 4:
            f[(sx | sz) & ~top & (q[:, 1] == n[1] - 2)] = 0.92
        if self.level >= 2:
            sp = self._hash(q[:, 0], q[:, 1], q[:, 2], pi)
            f[sp < 0.05] *= 0.94
            f[sp > 0.96] *= 1.05
        self._scale(cells, f)

    def fam_sand(self, b, pi, cells):
        """sand: grains (a light / dark speckle), raked lines on big floors"""
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        f = np.ones(len(cells))
        if self.level >= 1:
            sp = self._hash(q[:, 0], q[:, 2], pi)
            f[top & (sp < 0.07)] = 0.93
            f[top & (sp > 0.94)] = 1.06
        if self.level >= 2 and min(b["size"][0], b["size"][2]) >= 12:
            rake = (q[:, 2] % 6 == 0)
            f[top & rake] *= 0.97
        self._scale(cells, f)

    def fam_metal(self, b, pi, cells):
        """gold / brass / iron: a bright shine on the upper front edge, a darker lower rim"""
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        n = np.round(b["size"] / self.R.vs).astype(int)
        f = np.ones(len(cells))
        upper = q[:, 1] >= n[1] - 1
        f[(sx | sz) & upper] = 1.08
        f[(sx | sz) & (q[:, 1] == 0) & (n[1] >= 3)] = 0.9
        if self.level >= 2:
            sh = self._hash(q[:, 0], q[:, 1], q[:, 2], pi + 3) < 0.06
            sel = cells[sh & (top | upper)]
            self._toward(sel, (1.0, 1.0, 0.96), 0.4)
        self._scale(cells, f)

    def fam_rock(self, b, pi, cells):
        """rock: strata bands + speckle"""
        L, q = self._local(b, cells)
        f = np.ones(len(cells))
        band = (q[:, 1] // 2) % 3 == 0
        f[band] = 0.94
        if self.level >= 2:
            sp = self._hash(q[:, 0], q[:, 1], q[:, 2], pi)
            f[sp < 0.08] *= 0.9
            f[sp > 0.93] *= 1.07
        self._scale(cells, f)

    def fam_wood(self, b, pi, cells):
        """planks along the longest axis: a dark seam every few cells, end grain darker, rare knots"""
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        s = b["size"]
        ax = int(np.argmax(s))
        others = [a for a in range(3) if a != ax]
        f = np.ones(len(cells))
        pw = max(2, int(round(0.5 / self.R.vs)))
        for a in others:
            if s[a] >= 3 * self.R.vs:
                f[(q[:, a] % pw == 0) & (q[:, a] > 0)] *= 0.86
        n = np.round(s / self.R.vs).astype(int)
        endg = (q[:, ax] <= 0) | (q[:, ax] >= n[ax] - 1)
        f[endg] *= 0.92
        if self.level >= 2 and s[ax] >= 6 * self.R.vs:
            knot = self._hash(q[:, 0], q[:, 1], q[:, 2], pi) < 0.025
            f[knot] *= 0.85
        fr = max(1, int(round(0.25 / self.R.vs)))
        if b["name"] == "Crate" and min(n) > 4 * fr:
            # a framed crate: darker boards round every face + a diagonal brace on the sides
            rim = np.zeros(len(cells), bool)
            for ax2 in range(3):
                rim |= (q[:, ax2] < fr) | (q[:, ax2] >= n[ax2] - fr)
            ed = (rim.astype(int) + 0)
            cnt = sum(((q[:, a2] < fr) | (q[:, a2] >= n[a2] - fr)).astype(int) for a2 in range(3))
            f[cnt >= 2] *= 0.88
            top, bottom, sx, sz = self._faces(cells)
            u = np.where(sz, q[:, 0], q[:, 2])
            brace = (np.abs(u - q[:, 1] * (n[0] / max(1, n[1]))) <= fr) & (sx | sz) & ~top & (cnt < 2)
            f[brace] *= 0.9
        if b["name"] in ("Chest", "ChestLid"):
            # gold straps and gold corners (a cute treasure chest)
            gold = (0.98, 0.8, 0.3)
            strap = (np.abs(q[:, 0] + 0.5 - n[0] * 0.25) < 1) | (np.abs(q[:, 0] + 0.5 - n[0] * 0.75) < 1)
            cnt = sum(((q[:, a2] < 1) | (q[:, a2] >= n[a2] - 1)).astype(int) for a2 in range(3))
            self._toward(cells[strap | (cnt >= 2)], gold, 1.0)
        self._scale(cells, f)

    def fam_leaf(self, b, pi, cells):
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        f = np.ones(len(cells))
        if self.level >= 1:
            cl = 2
            n = self._hash(q[:, 0] // cl, q[:, 1] // cl, q[:, 2] // cl, pi)
            f[n < 0.25] = 0.86
            if self.level >= 2:
                f[n > 0.82] = 1.1
        self._scale(cells, f)
        if self.level >= 2:
            up = L[:, 1] > b["size"][1] * 0.1
            tip = self._hash(q[:, 0], q[:, 1], q[:, 2], pi + 7) < 0.08
            self._toward(cells[up & tip & top], (0.78, 0.95, 0.52), 0.35)

    def fam_flower(self, b, pi, cells):
        L, q = self._local(b, cells)
        h = b["size"] / 2
        score = L[:, 1] / max(h[1], 1e-6) - L[:, 2] / max(h[2], 1e-6) * 0.6 - L[:, 0] / max(h[0], 1e-6) * 0.4
        if len(score):
            k = int(np.argmax(score))
            self._toward(cells[k:k + 1], (1.0, 1.0, 1.0), 0.6)

    def fam_puff(self, b, pi, cells):
        pass

    def fam_grass(self, b, pi, cells):
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        f = np.ones(len(cells))
        if self.level >= 2:
            n = self._hash(q[:, 0] // 3, q[:, 2] // 3, pi)
            f[top & (n < 0.12)] = 0.93
            f[top & (n > 0.92)] = 1.05
        self._scale(cells, f)
        if self.level >= 3:
            R = self.R
            t = cells[top]
            qt = q[top]
            pick = self._hash(qt[:, 0], qt[:, 2], pi + 3) < 0.02
            r, g, bb = b["rgb"]
            tuft = (min(255, int(r * 0.9)), min(255, int(g * 1.06)), min(255, int(bb * 0.88)))
            packed = ((tuft[0] << 16) | (tuft[1] << 8) | tuft[2]) + 1
            for c in t[pick]:
                up = (int(c[0]), int(c[1]) + 1, int(c[2]))
                if up[1] < R.shape[1] and R.col[up] == 0:
                    self.extra[up] = packed
            self.stats["tufts"] = self.stats.get("tufts", 0) + int(pick.sum())

    def fam_fabric(self, b, pi, cells):
        """seats, banners, carpets: a darker hem, a woven stripe, a light trim line on banners"""
        if self.level < 1:
            return
        L, q = self._local(b, cells)
        top, bottom, sx, sz = self._faces(cells)
        h = b["size"]
        n = np.round(h / self.R.vs).astype(int)
        edge = (q[:, 0] <= 0) | (q[:, 0] >= n[0] - 1) | (q[:, 2] <= 0) | (q[:, 2] >= n[2] - 1)
        f = np.ones(len(cells))
        f[top & edge] = 0.88
        if self.level >= 2:
            if b["name"] in ("Banner",):
                f[(sx | sz) & (q[:, 1] % 4 == 0)] *= 0.92
                hem = (q[:, 1] <= 0)
                f[hem] = 0.84
            else:
                ax = 0 if h[0] >= h[2] else 2
                f[top & ((q[:, ax] // 2) % 2 == 0) & ~edge] *= 0.95
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


def mesh_all(m, R, D, solid_name="Fixed", part_limit=9000, tint_mask=None):
    """tint_mask: {part name: (bool mask, recipe)} - cells emitted into their own tinted part (not baked)"""
    col, occ, rgb = shade_and_colors(R, D)
    rgbq = _quantise(rgb)
    glass = R.glass.copy()
    for k in D.extra:
        glass[k] = 0
    solid = occ & (glass == 0)
    made = []
    taken = np.zeros_like(solid)
    for name, (mask, recipe) in sorted((tint_mask or {}).items()):
        mm = solid & mask
        if not mm.any():
            continue
        o = _emit(m, name, mm, rgbq, R)
        o.baked, o.shade, o.recipe, o.region = False, "base", [recipe], name
        made.append(o)
        taken |= mm
    solid = solid & ~taken
    # the baked part, halved along its longest horizontal axis until every piece is under part_limit triangles
    pieces = [solid]
    out = []
    while pieces:
        mk = pieces.pop(0)
        if not mk.any():
            continue
        tmp = "__probe"
        o = _emit(m, tmp, mk, rgbq, R)
        n = o.tris()
        del m.objects[tmp]
        if n > part_limit:
            pieces[0:0] = _split_x(mk, 2)
        else:
            out.append(mk)
    for i, mk in enumerate(out):
        nm = solid_name if i == 0 else "%s%d" % (solid_name, i + 1)
        oo = _emit(m, nm, mk, rgbq, R)
        if oo is not None:
            made.append(oo)
    trs = sorted(set(int(x) for x in np.unique(glass[occ]) if x > 0))
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


def soften(R, names, radius):
    """round the hard corners of the cells painted by boxes named in `names` (voxel clouds built from big blocks):
    a cell stays only when at least half of its (2r+1)^3 neighbourhood is that cloud (erosion of corners, no growth)"""
    if radius <= 0:
        return 0
    ids = [i for i, b in enumerate(R.boxes) if b["name"] in names]
    if not ids:
        return 0
    mask = np.isin(R.pid, ids) & (R.col != 0)
    occ = (R.col != 0).astype(np.float32)
    # box blur via cumulative sums (separable)
    k = 2 * radius + 1
    blur = occ
    for ax in range(3):
        pad = [(0, 0)] * 3
        pad[ax] = (radius + 1, radius)
        c = np.cumsum(np.pad(blur, pad), axis=ax)
        sl_hi = [slice(None)] * 3
        sl_lo = [slice(None)] * 3
        sl_hi[ax] = slice(k, None)
        sl_lo[ax] = slice(0, -k)
        blur = (c[tuple(sl_hi)] - c[tuple(sl_lo)]) / k
    drop = mask & (blur < 0.5)
    R.col[drop] = 0
    R.pid[drop] = -1
    return int(drop.sum())


def align_y(boxes, vs):
    """the y offset that puts the big top faces (walk surfaces) on voxel boundaries"""
    best, best_err = 0.0, None
    for k in range(8):
        o = vs * k / 8.0
        err = 0.0
        for b in boxes:
            if not _axis_aligned(b["R"]):
                continue
            ext = (np.abs(b["R"]) @ (b["size"] / 2))[1]
            area = float(b["size"][0] * b["size"][2])
            r = ((b["pos"][1] + ext - o) / vs) % 1.0
            err += area * min(r, 1 - r)
        if best_err is None or err < best_err - 1e-9:
            best, best_err = o, err
    return best


def bake(m, boxes, vs, budget=4000, opts=None):
    """boxes -> m's objects; returns stats.  Steps the detail level down until the triangles fit `budget`."""
    import os
    opts = opts or {}
    tints = opts.get("tints") or {}
    # tinted boxes are painted white: their vertex colours carry the shading only (Color = the look)
    bx = []
    for b in boxes:
        if b["name"] in tints:
            b = dict(b, rgb=(255, 255, 255))
        bx.append(b)
    R = Raster(bx, vs, align=opts.get("align", True), offy=align_y(bx, vs) if opts.get("aligny") else None)
    R.paint()
    softened = soften(R, set(opts.get("soften_names") or ("Cloud",)), int(opts.get("soften", 0)))
    name = opts.get("solid") or "Fixed"
    tries = []
    force = os.environ.get("AD_DETAIL")
    levels = (int(force),) if force else (3, 2, 1, 0)
    tint_ids = {}
    for i, b in enumerate(R.boxes):
        if b["name"] in tints:
            tint_ids.setdefault(b["name"], []).append(i)
    for level in levels:
        m.objects.clear()
        D = Detail(R, level)
        D.run()
        tmask = {nm: (np.isin(R.pid, ids), tints[nm]) for nm, ids in tint_ids.items()}
        mesh_all(m, R, D, solid_name=name, tint_mask=tmask)
        t = m.tris()
        tries.append((level, t))
        if t <= budget:
            break
    return {"vs": vs, "cells": int((R.col != 0).sum()), "level": tries[-1][0], "tries": tries,
            "shape": list(R.shape), "softened": softened}
