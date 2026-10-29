"""The dungeon's three looks (bug #5, the player's pick B "The Weatherworks" + the note "every dungeon level needs a
different design ... the higher level of the dungeon the more serious it looks"; DungeonBuilder.StyleTiers):

    c  The Root Conservatory   floors 1-3   a seed vault taken over by the island's roots (the softest)
    b  The Weatherworks        floors 4-8   the Cloud-Smiths' machine halls (the approved look)
    a  The Cloudkeep Undercroft floors 9-12  the old castle under everything (the most serious)

"ds_baked" bakes one tagged shell piece of a style (dungeon_<s>_wall_* / floor_* / pillar_* / door_8 / dais / carpet)
from its OWN Part build (the colliders, LayoutSig = the Part build's signature, exactly like props/arena.py "ad_baked")
and then dresses it in the style with voxel work the Part build cannot afford:

  wall    b: white dressed panels (seams, a brass rivet at every panel corner), a storm-blue riveted plinth with a brass
             rail, an iron girder cap; the plain side walls carry a verdigris copper pipe run on stand-off brackets with
             brass flanges, element-coloured sight glasses (Secondary) and two drops with pressure gauges
          a: dark grey-blue granite ashlar (rows 1.5 tall, blocks of mixed lengths, the bed joints REALLY recessed, the
             head joints dark, a few blocks set proud, an odd warm stone), moss in the low joints, a slate plinth, the
             cornice on corbels
          c: 2 x 1 terracotta bricks with dark mortar over a rough soil-stone base, white glasshouse ribs at both ends,
             thick roots breaking in under the cap with leaves and a star-bulb (Secondary) on a cord
  floor   b: slate-blue plates with seams and brass-framed grates whose slots glow dim in the element colour
          a: big worn flagstones in two sizes, cracked stones, one stone patched with planks
          c: a random ashlar path of grey flagstones (uneven rows and lengths) with moss in the joints
  pillar  b: white riveted panels, brass bands, a storm-blue base and cap; a: octagonal granite drums; c: brick with a
          root winding up it
  door    b: a riveted storm-blue girder frame with brass gussets, a plaque and two sooty handprints; a: a pointed arch
          of granite voussoirs over quoined jambs; c: a timber frame on brick jambs with ivy
  dais / carpet: the boss room's platform, stairs and runner in the style

Pivot = the Tag origin.  The tinted parts (Wall / Floor / Pillar: ML_Primary per room, darker per floor; Element:
ML_Secondary = the floor's element) are painted in grey: their vertex colours carry the texture, the Color the tint.
Deterministic: every pick is a hash of the cell / the piece.
"""
import math

import numpy as np

from props import prop
from props import arena_style as AS

WHITE = (255, 255, 255)
_hash = AS._hash


def _hv(*arrs):
    return AS._hash_arr(*arrs)


def pseudo_box(name):
    return {"cls": "Part", "shape": "Block", "pos": np.zeros(3), "R": np.eye(3), "size": np.ones(3), "rgb": WHITE,
            "mat": "SmoothPlastic", "tr": 0.0, "name": name, "parent": "style"}


def grey(f):
    v = int(max(0, min(255, round(255 * f))))
    return (v, v, v)


# ------------------------------------------------------------------------------------------------ the canvas
class Canvas:
    """a voxel canvas (arena_style.Raster arrays) in pivot space (studs): the Part build painted first (optional),
    then the style's ops.  Ops: box / cyl / ell / seg / torus / fill (mask), mode "all" | "over" (only occupied
    cells) | "empty"; name None clears.  rgb: a tuple, or fn(X, Y, Z) -> (N, 3) for the selected cells."""

    def __init__(self, vs, boxes=None, offy=None, align=True, pad=1.5):
        boxes = list(boxes or [])
        if boxes:
            R = AS.Raster(boxes, vs, pad=2 + int(math.ceil(pad / vs)), align=align, offy=offy)
            R.paint()
        else:
            R = AS.Raster([pseudo_box("__origin")], vs, pad=2, align=False, offy=0.0)
            R.boxes = []
            R.off = np.zeros(3)
        self.R = R
        self.vs = vs
        self.pseudo = {}
        self.fam = {}

    # grid growth (ops outside the Part build's box)
    def ensure(self, lo, hi):
        R = self.R
        vs = R.vs
        a = np.floor((np.asarray(lo, float) - R.off) / vs).astype(int) - 1
        b = np.ceil((np.asarray(hi, float) - R.off) / vs).astype(int) + 1
        cur1 = R.i0 + np.array(R.shape)
        i0 = np.minimum(R.i0, a)
        i1 = np.maximum(cur1, b)
        if np.all(i0 == R.i0) and np.all(i1 == cur1):
            return
        shape = tuple(int(x) for x in (i1 - i0))
        d = R.i0 - i0
        sl = tuple(slice(int(d[k]), int(d[k] + R.shape[k])) for k in range(3))
        for nm, dt, fillv in (("col", np.int64, 0), ("pid", np.int32, -1), ("glass", np.int16, 0)):
            new = np.full(shape, fillv, dt)
            new[sl] = getattr(R, nm)
            setattr(R, nm, new)
        R.i0 = i0
        R.shape = shape

    def region(self, lo, hi):
        self.ensure(lo, hi)
        R = self.R
        vs = R.vs
        a = np.floor((np.asarray(lo, float) - R.off) / vs).astype(int) - R.i0
        b = np.ceil((np.asarray(hi, float) - R.off) / vs).astype(int) - R.i0 + 1
        a = np.clip(a, 0, np.array(R.shape))
        b = np.clip(b, 0, np.array(R.shape))
        sl = tuple(slice(int(a[k]), int(b[k])) for k in range(3))
        X, Y, Z = R.centers(sl)
        return sl, X, Y, Z

    def everything(self):
        R = self.R
        sl = tuple(slice(0, n) for n in R.shape)
        X, Y, Z = R.centers(sl)
        return sl, X, Y, Z

    def pid(self, name):
        i = self.pseudo.get(name)
        if i is None:
            self.R.boxes.append(pseudo_box(name))
            i = len(self.R.boxes) - 1
            self.pseudo[name] = i
        return i

    def ids(self, *names):
        return [i for i, b in enumerate(self.R.boxes) if b["name"] in names]

    def put(self, sl, mask, X, Y, Z, name, rgb, mode="all", glass=0, only=None):
        R = self.R
        col = R.col[sl]
        if mode == "over":
            mask = mask & (col != 0)
        elif mode == "empty":
            mask = mask & (col == 0)
        if only is not None:
            mask = mask & np.isin(R.pid[sl], only)
        if not mask.any():
            return 0
        pid = R.pid[sl]
        gl = R.glass[sl]
        if name is None:
            col[mask] = 0
            pid[mask] = -1
            gl[mask] = 0
            return int(mask.sum())
        if callable(rgb):
            c = np.asarray(rgb(X[mask], Y[mask], Z[mask]), float)
            c = np.clip(np.round(c), 0, 255).astype(np.int64)
            col[mask] = ((c[:, 0] << 16) | (c[:, 1] << 8) | c[:, 2]) + 1
        else:
            col[mask] = ((int(rgb[0]) << 16) | (int(rgb[1]) << 8) | int(rgb[2])) + 1
        pid[mask] = self.pid(name) if isinstance(name, str) else int(name)
        gl[mask] = int(glass)
        return int(mask.sum())

    # shapes ------------------------------------------------------------------------------------
    def _thin(self, v):
        """a radius never below ~half a cell (thinner shapes hit no cell centre and vanish or break up)"""
        return max(float(v), self.vs * 0.56)

    def box(self, name, rgb, lo, hi, **kw):
        e = 1e-6
        lo, hi = list(map(float, lo)), list(map(float, hi))
        for k in range(3):  # a box thinner than a cell still gets its middle layer
            if hi[k] - lo[k] < self.vs:
                m = (hi[k] + lo[k]) / 2
                lo[k], hi[k] = m - self.vs * 0.51, m + self.vs * 0.51
        sl, X, Y, Z = self.region(lo, hi)
        m = (X >= lo[0] - e) & (X <= hi[0] + e) & (Y >= lo[1] - e) & (Y <= hi[1] + e) & (Z >= lo[2] - e) & (Z <= hi[2] + e)
        return self.put(sl, m, X, Y, Z, name, rgb, **kw)

    def cyl(self, name, rgb, c, r, a0, a1, axis=1, r0=0.0, **kw):
        """a cylinder (or a tube with r0 > 0) around the axis line through c, from a0 to a1 along `axis`"""
        r = self._thin(r)
        lo, hi = [c[0] - r, c[1] - r, c[2] - r], [c[0] + r, c[1] + r, c[2] + r]
        lo[axis], hi[axis] = a0, a1
        sl, X, Y, Z = self.region(lo, hi)
        P = (X, Y, Z)
        o = [k for k in range(3) if k != axis]
        d2 = (P[o[0]] - c[o[0]]) ** 2 + (P[o[1]] - c[o[1]]) ** 2
        m = (d2 <= r * r + 1e-6) & (d2 >= r0 * r0 - 1e-6) & (P[axis] >= a0) & (P[axis] <= a1)
        return self.put(sl, m, X, Y, Z, name, rgb, **kw)

    def ell(self, name, rgb, c, rad, p=2.0, **kw):
        rad = [self._thin(v) for v in rad]
        lo = [c[k] - rad[k] for k in range(3)]
        hi = [c[k] + rad[k] for k in range(3)]
        sl, X, Y, Z = self.region(lo, hi)
        m = (np.abs(X - c[0]) / rad[0]) ** p + (np.abs(Y - c[1]) / rad[1]) ** p + (np.abs(Z - c[2]) / rad[2]) ** p <= 1.0
        return self.put(sl, m, X, Y, Z, name, rgb, **kw)

    def seg(self, name, rgb, p0, p1, r, r1=None, **kw):
        """a capsule from p0 to p1 (radius r, tapering to r1)"""
        r1 = r if r1 is None else r1
        r, r1 = self._thin(r), self._thin(r1)
        rr = max(r, r1)
        p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
        lo, hi = np.minimum(p0, p1) - rr, np.maximum(p0, p1) + rr
        sl, X, Y, Z = self.region(lo, hi)
        d = p1 - p0
        L2 = max(float(d @ d), 1e-9)
        t = np.clip(((X - p0[0]) * d[0] + (Y - p0[1]) * d[1] + (Z - p0[2]) * d[2]) / L2, 0, 1)
        dx, dy, dz = X - (p0[0] + t * d[0]), Y - (p0[1] + t * d[1]), Z - (p0[2] + t * d[2])
        rad = r + (r1 - r) * t
        m = dx * dx + dy * dy + dz * dz <= rad * rad + 1e-6
        return self.put(sl, m, X, Y, Z, name, rgb, **kw)

    def path(self, name, rgb, pts, r, r1=None, **kw):
        n = len(pts) - 1
        r1 = r if r1 is None else r1
        for i in range(n):
            a = r + (r1 - r) * i / n
            b = r + (r1 - r) * (i + 1) / n
            self.seg(name, rgb, pts[i], pts[i + 1], a, b, **kw)

    def torus(self, name, rgb, c, R_, r, axis=2, **kw):
        """a ring of radius R_ (tube r) in the plane normal to `axis`"""
        r = self._thin(r)
        lo = [c[k] - R_ - r for k in range(3)]
        hi = [c[k] + R_ + r for k in range(3)]
        lo[axis], hi[axis] = c[axis] - r, c[axis] + r
        sl, X, Y, Z = self.region(lo, hi)
        P = (X - c[0], Y - c[1], Z - c[2])
        o = [k for k in range(3) if k != axis]
        q = np.sqrt(P[o[0]] ** 2 + P[o[1]] ** 2) - R_
        m = q * q + P[axis] ** 2 <= r * r + 1e-6
        return self.put(sl, m, X, Y, Z, name, rgb, **kw)

    def where(self, name, rgb, fn, lo=None, hi=None, **kw):
        """cells where fn(X, Y, Z) is True (inside lo..hi, or the whole canvas)"""
        if lo is None:
            sl, X, Y, Z = self.everything()
        else:
            sl, X, Y, Z = self.region(lo, hi)
        m = fn(X, Y, Z)
        return self.put(sl, m, X, Y, Z, name, rgb, **kw)

    # queries -----------------------------------------------------------------------------------
    def occ(self):
        return self.R.col != 0

    def cells_of(self, *names):
        return np.isin(self.R.pid, self.ids(*names)) & (self.R.col != 0)

    def skin_top(self, mask):
        """cells of mask whose upper neighbour is empty"""
        occ = self.occ()
        up = np.zeros_like(occ)
        up[:, :-1, :] = occ[:, 1:, :]
        return mask & ~up

    def recolor(self, mask, fn):
        """recolour the cells of a full-grid mask: fn(X, Y, Z) -> (N, 3)"""
        R = self.R
        idx = np.argwhere(mask)
        if len(idx) == 0:
            return 0
        P = R.off + (idx + R.i0 + 0.5) * R.vs
        c = np.clip(np.round(np.asarray(fn(P[:, 0], P[:, 1], P[:, 2]), float)), 0, 255).astype(np.int64)
        R.col[idx[:, 0], idx[:, 1], idx[:, 2]] = ((c[:, 0] << 16) | (c[:, 1] << 8) | c[:, 2]) + 1
        return len(idx)

    def rename(self, mask, name):
        R = self.R
        R.pid[mask & (R.col != 0)] = self.pid(name)

    def clear(self, mask):
        R = self.R
        R.col[mask] = 0
        R.pid[mask] = -1
        R.glass[mask] = 0

    def pos(self):
        """X, Y, Z of every cell centre (full grid)"""
        return self.everything()[1:]


class StyleDetail(AS.Detail):
    """arena_style's detail, with the canvas's family overrides; painted pseudo parts get a soft speckle"""

    def __init__(self, R, level, fam):
        super().__init__(R, level)
        self.famover = fam

    def run(self):
        R = self.R
        idx = np.argwhere(self.skin)
        if len(idx) == 0:
            return
        pids = R.pid[idx[:, 0], idx[:, 1], idx[:, 2]]
        order = np.argsort(pids, kind="stable")
        idx, pids = idx[order], pids[order]
        cuts = np.nonzero(np.diff(pids))[0] + 1
        for grp in np.split(np.arange(len(pids)), cuts):
            if len(grp) == 0:
                continue
            pi = int(pids[grp[0]])
            if pi < 0:
                continue
            b = R.boxes[pi]
            fam = self.famover.get(b["name"])
            if fam is None:
                fam = "speckle" if b.get("parent") == "style" else AS.family(b["name"])
            fn = getattr(self, "fam_" + fam, None)
            if fn:
                fn(b, pi, idx[grp])
        self.stats["level"] = self.level

    def fam_speckle(self, b, pi, cells):
        if self.level < 2:
            return
        g = cells + self.R.i0
        n = self._hash(g[:, 0], g[:, 1], g[:, 2], pi + 31)
        f = np.ones(len(cells))
        f[n < 0.06] = 0.95
        f[n > 0.95] = 1.04
        self._scale(cells, f)

    def fam_flat(self, b, pi, cells):
        pass


def finish(m, cv, tints, budget, levels=(3, 2, 1, 0)):
    """shade + mesh the canvas into m (tints: {part name: recipe}); steps the detail down to fit the budget"""
    R = cv.R
    tries = []
    for level in levels:
        m.objects.clear()
        D = StyleDetail(R, level, cv.fam)
        D.run()
        tmask = {}
        for nm, recipe in tints.items():
            ids = [i for i, b in enumerate(R.boxes) if b["name"] == nm]
            if ids:
                mk = np.isin(R.pid, ids) & (R.col != 0)
                if mk.any():
                    tmask[nm] = (mk, recipe)
        AS.mesh_all(m, R, D, solid_name="Fixed", tint_mask=tmask)
        tries.append((level, m.tris()))
        if m.tris() <= budget:
            break
    return tries


# ------------------------------------------------------------------------------------------------ palettes
BRASS = (222, 172, 72)
BRASS_D = (176, 128, 52)
COPPER = (70, 168, 140)  # verdigris
COPPER_D = (48, 128, 106)
IRON = (58, 66, 88)
STORM = (62, 76, 108)
STORM_L = (88, 104, 140)
SLOT = (34, 40, 58)
RED = (196, 44, 44)
SLATE_A = (70, 82, 110)
MOSS = (96, 156, 78)
MOSS_L = (130, 186, 96)
LEAF = (88, 164, 82)
LEAF_L = (128, 196, 96)
BARK = (104, 74, 52)
BARK_L = (134, 98, 68)
RIB = (236, 238, 232)
SOIL = [(112, 90, 70), (98, 80, 64), (128, 104, 80), (90, 74, 60)]
WOOD = (150, 104, 68)
WOOD_D = (116, 80, 52)
TERRA = (198, 118, 84)


def _rgb_choice(palette, key):
    pal = np.asarray(palette, float)
    return pal[(np.asarray(key) * len(palette)).astype(int) % len(palette)]


# ------------------------------------------------------------------------------------------------ the shell pieces
def wall_info(boxes):
    pl = [b for b in boxes if b["name"] == "Plinth"]
    L = float(pl[0]["size"][0]) if pl else float(max(b["size"][0] for b in boxes))
    walls = [b for b in boxes if b["name"] == "Wall"]
    low = sorted((float(b["pos"][0] - b["size"][0] / 2), float(b["pos"][0] + b["size"][0] / 2)) for b in walls
                 if b["pos"][1] < 7.6)
    gaps = []
    x = -L / 2
    for a, c in low:
        if a > x + 0.25:
            gaps.append((x, a))
        x = max(x, c)
    if x < L / 2 - 0.25:
        gaps.append((x, L / 2))
    return {"L": L, "doors": gaps}


def _in_door(info, X, Y, margin=0.0):
    m = np.zeros(np.shape(X), bool)
    for a, b in info["doors"]:
        m |= (X > a - margin) & (X < b + margin) & (Y < 8.0 + margin)
    return m


def wall_b(cv, info, key):
    """The Weatherworks: white riveted panels, storm-blue plinth + brass rail, iron girder cap, a copper pipe run"""
    vs = cv.vs
    L = info["L"]
    X, Y, Z = cv.pos()
    cv.clear(cv.cells_of("Course", "Dado"))
    wall = cv.cells_of("Wall") & (Z < 0)  # the room side only (the back is never seen; budget)
    # panels 3 x 4 studs; seams 1 cell; a per-panel shade; the top-left edge a little lighter
    px = (X + L / 2) / 3.0
    py = Y / 4.0
    seam = (np.abs(px - np.round(px)) * 3.0 < vs * 0.55) | (np.abs(py - np.round(py)) * 4.0 < vs * 0.55)
    pnl = _hv(np.floor(px).astype(int), np.floor(py).astype(int), 7)
    f = 0.95 + 0.05 * pnl
    f = np.where(seam, 0.74, f)
    edge = ((px - np.floor(px)) * 3.0 < vs * 1.5) & ~seam
    f = np.where(edge, np.minimum(1.0, f + 0.03), f)
    cv.recolor(wall, lambda x, y, z: np.repeat(np.clip(255 * _lookup(f, cv, x, y, z), 0, 255)[:, None], 3, 1)
               * np.array([0.98, 0.99, 1.0]))
    # rivets: one brass cell in front of the face at every panel corner (0.375 in)
    face = -0.5
    for i in range(int(L // 3) + 1):
        x0 = -L / 2 + i * 3.0
        for xx in (x0 + 0.375,):
            if xx < -L / 2 + 0.3 or xx > L / 2 - 0.3:
                continue
            for j in range(4):
                for yy in (j * 4.0 + 0.375, j * 4.0 + 4.0 - 0.375):
                    if yy < 1.4 or yy > 14.7:
                        continue
                    if any(a - 0.2 < xx < b + 0.2 and yy < 8.2 for a, b in info["doors"]):
                        continue
                    cv.box("Rivet", BRASS, (xx - vs / 2, yy - vs / 2, face - vs), (xx + vs / 2, yy + vs / 2, face), mode="empty")
    # plinth: storm blue with light rivet dots; a brass rail along its top front edge
    pl = cv.cells_of("Plinth")
    cv.recolor(pl, lambda x, y, z: np.where(((np.abs(((x + L / 2) / 1.5) % 1.0 - 0.5) < 0.09) & (np.abs(y - 0.6) < 0.15))[:, None],
                                             np.array(STORM_L, float), np.array(STORM, float)))
    cv.box("Brass", BRASS, (-L / 2, 1.2, -1.2), (L / 2, 1.2 + vs, -1.2 + vs * 1.5))
    # the cap: an iron girder (a brass lip under its front, rivets along its face)
    cap = cv.cells_of("Cap")
    cv.recolor(cap, lambda x, y, z: np.where(((np.abs(((x + L / 2) / 1.5) % 1.0 - 0.5) < 0.09) & (np.abs(y - 15.4) < 0.15))[:, None],
                                              np.array(BRASS, float), np.array(IRON, float)))
    cv.box("Brass", BRASS, (-L / 2, 15.0 - vs, -1.1), (L / 2, 15.0, -1.1 + vs), mode="empty")
    # the copper pipe run on the plain walls (side walls / corridors): over everything the rooms hang on their walls
    if not info["doors"] and L >= 9:
        pipe_run(cv, L, key, drops=(L >= 20 and not key.endswith("_lite")))


def _lookup(f, cv, x, y, z):
    """the value of a full-grid array f at the cell centres x, y, z"""
    R = cv.R
    i = np.floor((x - R.off[0]) / R.vs).astype(int) - R.i0[0]
    j = np.floor((y - R.off[1]) / R.vs).astype(int) - R.i0[1]
    k = np.floor((z - R.off[2]) / R.vs).astype(int) - R.i0[2]
    return f[i, j, k]


def pipe_run(cv, L, key, drops=True):
    vs = cv.vs
    y, zc, r = 13.4, -1.1, 0.32

    def copper(x, yy, z):
        n = _hv(np.floor(x / 0.75).astype(int), np.floor(yy / 0.75).astype(int), 3)
        top = yy > y + 0.12
        c = np.where((n < 0.22)[:, None], np.array(COPPER_D, float), np.array(COPPER, float))
        return np.where(top[:, None], np.minimum(255, c * 1.12), c)

    x0, x1 = -L / 2 + 1.6, L / 2 - 1.6
    cv.cyl("Pipe", copper, (0, y, zc), r, x0, x1, axis=0)
    cv.ell("Pipe", copper, (x0, y, zc), (r, r, r))
    cv.ell("Pipe", copper, (x1, y, zc), (r, r, r))
    # stand-off brackets every 6 studs, flanges every 8, a sight glass (the element colour) every 12
    for x in np.arange(-L / 2 + 3.0, L / 2 - 2.0, 6.0):
        cv.box("Iron", IRON, (x - vs / 2, y - 0.45, -0.5 - vs * 2), (x + vs / 2, y + 0.45, -0.5))
        cv.box("Iron", IRON, (x - vs / 2, y + r - 0.05, zc - 0.1), (x + vs / 2, y + r + vs, -0.5))
    for x in np.arange(-L / 2 + 5.0, L / 2 - 2.0, 8.0):
        cv.cyl("Brass", BRASS, (x, y, zc), r + 0.14, x - 0.13, x + 0.13, axis=0)
    if L >= 20:
        for x in np.arange(-L / 2 + 9.0, L / 2 - 4.0, 12.0):
            cv.cyl("Element", grey(0.92), (x, y, zc), r + 0.02, x - 0.4, x + 0.4, axis=0)
            cv.cyl("Brass", BRASS, (x, y, zc), r + 0.1, x - 0.55, x - 0.42, axis=0)
            cv.cyl("Brass", BRASS, (x, y, zc), r + 0.1, x + 0.42, x + 0.55, axis=0)
    # two drops near the ends of a long wall, each with a pressure gauge and a small valve
    if drops:
        for s in (-1, 1):
            x = s * (L / 2 - 3.5)
            cv.cyl("Pipe", copper, (x, 0, zc), r, 1.6, y, axis=1)
            cv.ell("Pipe", copper, (x, y, zc), (r + 0.05, r + 0.05, r + 0.05))
            cv.cyl("Brass", BRASS, (x, 0, zc), r + 0.14, 1.2, 1.6, axis=1)
            for yy in (3.0, 10.4):
                cv.box("Iron", IRON, (x - 0.45, yy - vs / 2, -0.5 - vs * 2), (x + 0.45, yy + vs / 2, -0.5))
            gauge(cv, (x, 5.4, zc - r - 0.02), 0.62, key, s)
            cv.ell("Brass", BRASS, (x, 8.2, zc), (0.45, 0.4, 0.45))
            cv.box("Brass", BRASS_D, (x - 0.5, 8.05, zc - 0.7), (x + 0.5, 8.3, zc - 0.4))


def gauge(cv, c, rad, key, seed):
    """a round pressure gauge facing -z: brass rim, cream face, ticks, a red needle (pitched by a hash)"""
    vs = cv.vs
    x, y, z = c
    cv.cyl("Brass", BRASS, (x, y, z), rad, z - vs * 2, z, axis=2)
    cv.cyl("Dial", (240, 236, 222), (x, y, z), rad - vs, z - vs * 2 - 0.01, z - vs * 0.5, axis=2)
    ang = -0.6 + 1.6 * _hash(len(key), seed, 9)
    for t in np.linspace(0.08, rad - vs * 1.2, 4):
        cv.box("Needle", (190, 40, 40), (x + math.cos(ang) * t - vs / 2, y + math.sin(ang) * t - vs / 2, z - vs * 2 - 0.02),
               (x + math.cos(ang) * t + vs / 2, y + math.sin(ang) * t + vs / 2, z - vs * 1.2), mode="over")


def wall_a(cv, info, key):
    """The Cloudkeep Undercroft: granite ashlar with recessed mortar, proud blocks, moss low, a corbelled cornice"""
    vs = cv.vs
    L = info["L"]
    X, Y, Z = cv.pos()
    cv.clear(cv.cells_of("Course", "Dado"))
    wall = cv.cells_of("Wall") & (Z < 0)  # the room side only (the back is never seen; budget)
    row_h = 1.5  # (1.25 rows with every bed joint cut back cost 10k triangles on a 72 run)
    y0 = 1.2
    row = np.floor((Y - y0) / row_h).astype(int)
    fy = (Y - y0) / row_h - row
    # block joints per row: lengths 1.5 / 2 / 2.5 / 3 picked by a hash, staggered per row
    seed = int(L * 10)
    edges = {}
    for r in range(-2, 13):
        xs = [-L / 2 - 3 * _hash(r, seed, 1)]
        while xs[-1] < L / 2 + 3:
            xs.append(xs[-1] + (2.0, 2.5, 3.0, 3.5, 2.5)[int(_hash(r, len(xs), seed) * 5) % 5])
        edges[r] = np.array(xs)
    bid = np.zeros(X.shape, np.int64)
    jx = np.zeros(X.shape, bool)
    for r, xs in edges.items():
        sel = row == r
        if not sel.any():
            continue
        k = np.searchsorted(xs, X[sel]) - 1
        bid[sel] = r * 1000 + k
        d = np.minimum(np.abs(X[sel] - xs[np.clip(k, 0, len(xs) - 1)]), np.abs(xs[np.clip(k + 1, 0, len(xs) - 1)] - X[sel]))
        jx[sel] = d < vs * 0.55
    jy = (fy * row_h < vs) & (Y > y0)  # (one cell: the rows are 5 cells, so a half-cell test never hit a centre)
    joint = (jx | jy) & (Y > y0 - 0.01)
    front = wall & (Z < -0.5 + vs)  # the first cell layer on the room face
    second = wall & (Z >= -0.5 + vs) & (Z < -0.5 + 2 * vs)
    # moss in the low joints, the rest of the joints recessed one cell
    low = joint & front & (Y < 2.9)
    mossy = low & (_hv(np.floor(X / 0.5).astype(int), np.floor(Y / 0.5).astype(int), 5) < 0.45)
    cv.recolor(mossy, lambda x, y, z: np.where((_hv(np.floor(x * 4).astype(int), 3) < 0.4)[:, None],
                                                np.array(MOSS_L, float), np.array(MOSS, float)))
    cv.rename(mossy, "Moss")
    # the bed joints are cut back one cell (the depth read); the head joints are only darker (their recess cost half
    # the wall's triangles: every block's two end faces)
    cv.clear(jy & front & ~mossy & (Y > y0 - 0.01))
    # block shades (granite: grey-blue, a few warmer stones), mortar in the second layer
    n = np.floor(_hv(bid, 11) * 3) / 2.0  # three block shades (neighbours merge)
    f = 0.86 + 0.13 * n
    warm = _hv(bid, 13) < 0.07
    cv.recolor(wall & ~(joint & second), lambda x, y, z: (
        np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1)
        * np.where(_lookup(warm, cv, x, y, z)[:, None], np.array([1.0, 0.94, 0.9]), np.array([1.0, 1.0, 1.0]))))
    # the recessed mortar reads DARK (a light groove read as white stripes in the renders)
    cv.recolor(wall & joint & second, lambda x, y, z: np.repeat(np.full(len(x), 118.0)[:, None], 3, 1))
    cv.recolor(wall & jx & ~jy & front & ~mossy, lambda x, y, z: np.repeat(np.full(len(x), 132.0)[:, None], 3, 1))
    # a few blocks set proud by one cell (old settling), never in the lowest row, never by a doorway
    proud = wall & front & ~joint & (_hv(bid, 17) < 0.06) & (row >= 1) & ~_in_door(info, X, Y, 1.0)
    idx = np.argwhere(proud)
    R = cv.R
    for i, j, k in idx:
        if k - 1 >= 0 and R.col[i, j, k - 1] == 0:
            R.col[i, j, k - 1] = R.col[i, j, k]
            R.pid[i, j, k - 1] = R.pid[i, j, k]
    # soot darkening near the top (the old torch smoke gathers under the cornice)
    top = wall & (Y > 12.6) & ~joint
    cv.recolor(top, lambda x, y, z: np.repeat((255 * _lookup(f, cv, x, y, z) * (1.0 - 0.12 * (y - 12.6) / 2.4))[:, None], 3, 1))
    # the plinth: slate, a chamfered top front edge
    pl = cv.cells_of("Plinth")
    cham = pl & (Y > 1.2 - vs) & (Z < -1.2 + vs)
    cv.clear(cham)
    # the cornice: slate cap with corbels under it every 3 studs
    for x in np.arange(-L / 2 + 1.5, L / 2 - 0.5, 3.0):
        cv.box("Corbel", SLATE_A, (x - 0.375, 14.5, -1.0), (x + 0.375, 15.0, -0.5), mode="empty")
        cv.box("Corbel", SLATE_A, (x - 0.25, 14.25, -0.75), (x + 0.25, 14.5, -0.5), mode="empty")


def wall_reserved(key):
    """what the rooms stand or hang in front of this wall key's room face, as boxes (x0, x1, y0, y1) in the key's pivot
    space: every tagged target (torches, banners, shields, racks, hearths, wine racks, pillars, arches, chains...)
    in a template that uses the key, all styles (the layouts are shared), within z -2.8 .. -0.2 of the face. Plus the
    element weathering's high spots (placed per run under the cornice of the entrance / exit walls at x +-11)."""
    if key in _RES:
        return _RES[key]
    from props import arena as AR
    pl = AR.places()

    def cf(t):
        v = [float(x) for x in t.split()]
        return np.array(v[:3]), np.array(v[3:12]).reshape(3, 3)

    def tpl(p):
        parts = p["Path"].split(".")
        return ".".join(parts[:3]) if p["Path"].startswith("ServerStorage.DungeonTemplates.") else None

    groups = {}
    for p in pl:
        t = tpl(p)
        if t:
            groups.setdefault(t, []).append(p)
    local = {}

    def boxes_of(k):
        if k not in local:
            try:
                t = AR.target(k)
            except KeyError:
                local[k] = []
                return local[k]
            sc = float(t.get("Scale") or 1)
            out = []
            for b in AR.parse_boxes(t["Boxes"], sc):
                hh = np.abs(b["R"]) @ (b["size"] / 2)
                out.append((b["pos"] - hh, b["pos"] + hh))
            local[k] = out
        return local[k]

    res = []
    for p in pl:
        if p["Key"] != key or not tpl(p):
            continue
        P, R = cf(p["Origin"])
        for q in groups[tpl(p)]:
            k = q["Key"]
            # (the cave rocks lean on the wall below and in front: a root behind one reads as grown over by it; their
            # tilted-box bounds would also blank out whole cave walls)
            if q is p or "_wall_" in k or "_floor_" in k or k.endswith("ceiling") or k.startswith("dungeon_rock"):
                continue
            Q, RQ = cf(q["Origin"])
            sc = float(q.get("Scale") or 1)
            for lo, hi in boxes_of(k):
                c = (lo + hi) / 2 * sc
                e = (hi - lo) / 2 * sc
                wc = Q + RQ @ c
                we = np.abs(RQ) @ e
                lc = R.T @ (wc - P)
                le = np.abs(R.T) @ we
                if lc[2] - le[2] < -0.2 and lc[2] + le[2] > -2.8:
                    res.append((float(lc[0] - le[0]), float(lc[0] + le[0]), float(lc[1] - le[1]), float(lc[1] + le[1])))
    if "_door" in key:
        for sx in (-1, 1):
            res.append((sx * 11.0 - 2.6, sx * 11.0 + 2.6, 11.4, 15.2))
    _RES[key] = res
    return res


_RES = {}
VQ = 0.25  # the shell canvas' voxel (root blocks snap to it: no half cells, no stray faces)


def _free(res, info, x0, x1, y0, y1, margin=0.35, door=1.0):
    for a, b, c, d in res:
        if x0 - margin < b and a < x1 + margin and y0 < d and c < y1:
            return False
    for a, b in info["doors"]:
        if x0 < b + door and a - door < x1 and y0 < 9.2:
            return False
    L = info["L"]
    return x0 > -L / 2 + 0.3 and x1 < L / 2 - 0.3


def wall_c(cv, info, key):
    """The Root Conservatory: small terracotta bricks over soil-stone, glasshouse ribs with star-bulbs, roots breaking in,
    grass in the plinth joints"""
    vs = cv.vs
    L = info["L"]
    X, Y, Z = cv.pos()
    cv.clear(cv.cells_of("Course", "Dado"))
    wall = cv.cells_of("Wall") & (Z < 0)  # the room side only (the back is never seen; budget)
    ch, bl = 1.0, 2.0  # bricks 2 x 1 (0.75 x 1.5 cost 10k triangles on a 72 wall)
    row = np.floor(Y / ch).astype(int)
    u = X + L / 2 + (row % 2) * (bl / 2)
    col = np.floor(u / bl).astype(int)
    mortar = ((Y - row * ch) < vs * 0.55) | ((u - col * bl) < vs * 0.55)
    n = np.floor(_hv(row, col, 21) * 3) / 2.0  # three brick shades (budget: neighbouring bricks merge)
    f = np.where(mortar, 0.76, 0.88 + 0.1 * n)  # (Gemini: 0.66 mortar made a loud grid that fought the roots)
    f = np.where(~mortar & (_hv(row, col, 23) < 0.05), 0.74, f)  # an over-fired brick here and there
    cv.recolor(wall, lambda x, y, z: np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1))
    # the soil-stone base: rough stones up to ~2.2 studs (fixed earthy colours)
    base = wall & (Y < 2.0 + 0.4 * _hv(np.floor(X / 1.2).astype(int), 4))
    # (stones 1.8 x 0.9: smaller ones cost ~1k triangles a long wall)
    sid = _hv(np.floor((X + 0.6 * np.floor(Y / 0.9)) / 1.8).astype(int), np.floor(Y / 0.9).astype(int), 31)
    sj = (((Y / 0.9) % 1.0) < vs / 0.9 * 0.6) | ((((X + 0.6 * np.floor(Y / 0.9)) / 1.8) % 1.0) < vs / 1.8 * 0.6)
    cv.recolor(base, lambda x, y, z: np.where(_lookup(sj, cv, x, y, z)[:, None], np.array((70, 58, 48), float),
                                               _rgb_choice(SOIL, _lookup(sid, cv, x, y, z))))
    cv.rename(base, "Soil")
    # plinth: dark soil-stone with moss on its top
    pl = cv.cells_of("Plinth")
    # (one course of 1.6-stud stones; moss in 1.5-stud patches: per-cell colours cost a quad each)
    cv.recolor(pl, lambda x, y, z: _rgb_choice(SOIL[1:], _hv(np.floor(x / 1.6).astype(int), 2)))
    ptop = cv.skin_top(pl) & (_hv(np.floor(X / 1.5).astype(int), np.floor(Z / 0.85).astype(int), 41) < 0.5)
    cv.recolor(ptop, lambda x, y, z: np.where((_hv(np.floor(x / 1.5).astype(int), 7) < 0.5)[:, None],
                                               np.array(MOSS, float), np.array(MOSS_L, float)))
    cv.rename(ptop, "Moss")
    # the cap: weathered timber (the glasshouse sill)
    cap = cv.cells_of("Cap")
    cv.recolor(cap, lambda x, y, z: np.where((((x + L / 2) % 2.0) < vs)[:, None], np.array((92, 66, 48), float),
                                              np.array((120, 88, 62), float)))
    # (fix round: the first build had ribs at the two ends only and one root sprig per wall, plain brick between: far
    # from the pitched C. Now, as the pitch: a leafy root run every ~12 studs from the cornice to mid-height, glasshouse
    # ribs every ~9 studs with star-bulbs on cords at their tips, grass in the plinth joints. Everything is placed around
    # what the rooms hang / stand on this run (wall_reserved: the torches, banners, shields, racks, hearths, pillars of
    # every template that uses the key, and the weathering's cornice spots), so nothing runs through them.)
    res = wall_reserved(key)
    roots = []
    nr = max(1, int(round(L / 13.0))) if L >= 9 else 0
    for i in range(nr):
        xc = -L / 2 + (i + 0.5) * L / nr
        for dx in (0.0, 1.0, -1.0, 2.0, -2.0, 3.0, -3.0):
            x = xc + dx
            if _free(res, info, x - 1.9, x + 1.9, 7.6, 15.2) and all(abs(x - r) > 5.0 for r in roots):
                roots.append(x)
                break
    ribs = []
    for x in ((-L / 2 + 1.0, L / 2 - 1.0) if L >= 9 else ()):
        if not any(a - 1.0 < x < b + 1.0 for a, b in info["doors"]):
            ribs.append(x)
    if L >= 14:
        nb = int(L // 10.5)
        for i in range(1, nb):
            xc = -L / 2 + i * L / nb
            for dx in (0.0, 1.0, -1.0, 2.0, -2.0):
                x = xc + dx
                if (_free(res, info, x - 0.4, x + 0.4, 1.2, 15.2) and all(abs(x - r) > 2.6 for r in roots)
                        and all(abs(x - r) > 3.0 for r in ribs)):
                    ribs.append(x)
                    break
    for x in sorted(ribs):
        cv.box("Rib", RIB, (x - 0.25, 1.2, -1.0), (x + 0.25, 14.4, -0.5))
        cv.box("Rib", RIB, (x - 0.25, 14.0, -1.25), (x + 0.25, 15.0, -0.75))
        cv.box("Rib", (206, 210, 204), (x - 0.25, 1.2, -1.25), (x + 0.25, 1.7, -0.5))
        # star-bulbs on cords off the rib tip (1 or 2: the glasshouse's old string lights)
        hx = int(round(x * 4)) + 400
        want = (-1, 1) if _hash(hx, len(key), 13) < 0.3 else ((1,) if _hash(hx, 3) < 0.5 else (-1,))
        sides = [s for s in want
                 if _free(res, info, min(x, x + s * 1.1) - 0.3, max(x, x + s * 1.1) + 0.3, 11.8, 14.6, margin=0.2)
                 and -L / 2 + 0.6 < x + s * 0.8 < L / 2 - 0.6]
        for j, s in enumerate(sides):
            drop = 0.75 + 0.5 * _hash(hx, j, 17)
            bulb(cv, (x + s * 0.875, 14.125, -0.875), drop, arm_from=x)
    for i, x in enumerate(roots):
        root(cv, x, key, i)
    # grass in the plinth joints (tufts of 2-3 blades on the plinth top, a few at its foot), never in a doorway or behind
    # a prop that stands at the wall
    for j in range(int(math.floor(-L / 2 / 1.6)), int(math.ceil(L / 2 / 1.6)) + 1):
        x = j * 1.6
        hh = _hash(j, len(key), 29)
        if hh > 0.22 or not _free(res, info, x - 0.5, x + 0.5, 0.0, 2.2, margin=0.1, door=0.3):
            continue
        foot = hh < 0.06
        yb, zz = (0.0, -1.375) if foot else (1.25, -0.875)
        for b, (bx, bh) in enumerate(((-0.25, 0.5), (0.0, 0.75), (0.25, 0.5))[: 2 + (hh < 0.15)]):
            c = (LEAF_L if (b + j) % 2 else MOSS_L) if not foot else (LEAF if b % 2 else MOSS)
            cv.box("Grass", c, (x + bx - 0.12, yb, zz - 0.12), (x + bx + 0.12, yb + bh, zz + 0.12), mode="empty")


def bulb(cv, top, drop, arm_from=None):
    """a star-bulb on a cord: a short iron arm from the rib, the cord, a pale bulb (Element: the floor's colour) with three
    star points and a leaf cap"""
    x, y, z = top
    if arm_from is not None:
        cv.box("Cord", (60, 54, 46), (min(arm_from, x) - 0.12, y - 0.12, z - 0.12), (max(arm_from, x) + 0.12, y + 0.12, z + 0.12),
               mode="empty")
    cv.box("Cord", (60, 54, 46), (x - 0.12, y - drop, z - 0.12), (x + 0.12, y, z + 0.12), mode="empty")
    cy = y - drop - 0.375
    cv.box("Leaf", LEAF_L, (x - 0.25, cy + 0.25, z - 0.25), (x + 0.25, cy + 0.5, z + 0.25), mode="empty")
    # (fix round: the bulb itself stays a pale warm glass; only its star points take the floor's colour: a whole bulb in
    # the Earth brown read as an acorn, not a light)
    cv.box("Bulb", (250, 244, 222), (x - 0.25, cy - 0.375, z - 0.25), (x + 0.25, cy + 0.25, z + 0.25), mode="empty")
    for dx, dy in ((-0.375, 0), (0.375, 0), (0, -0.5)):
        cv.box("Element", grey(0.95), (x + dx - 0.12, cy + dy - 0.12, z - 0.12), (x + dx + 0.12, cy + dy + 0.12, z + 0.12), mode="empty")


def root(cv, x0, key, i):
    """a thick root breaking in under the cap and crawling down the wall to mid-height: tapering bark blocks stepping
    sideways (volume blocks, as the pitch), leaf clusters along it, a side shoot; every other one ends in a star-bulb"""
    hs = int(round(x0 * 4)) + 300
    h = _hash(len(key), i, hs, 5)
    y_end = 8.0 + 1.6 * h
    th = 1.0
    x, y = round(x0 / VQ) * VQ, 15.0
    k = 0
    tip = (x, y)

    # (one bark shade per block, alternating like the pitch's jittered boxes: a per-cell bark noise split every block face
    # into small quads and put the boss room over its 90k triangles)
    while y > y_end:
        bark = BARK_L if (k + i) % 2 else BARK
        seg = round((1.0 + 0.75 * _hash(i, k, hs, 7)) / VQ) * VQ
        dx = round(((_hash(i, k, hs, 11) - 0.5) * 1.1) / VQ) * VQ
        w = max(0.5, round(th / VQ) * VQ)
        d = max(0.5, round(0.8 * th / VQ) * VQ)
        cv.box("Root", bark, (x - w / 2, y - seg, -0.5 - d), (x + w / 2, y + 0.125, -0.5), mode="empty")
        # leaves: a cluster of 2-3 flat leaves on one side (against the wall) and now and then one over the root's front
        if _hash(i, k, hs, 19) < 0.8:
            side = 1 if (k + i) % 2 else -1
            lx = x + side * (w / 2 + 0.375)
            ly = y - seg * 0.5
            shapes = ((0.0, 0.0, 0.75, 0.5), (side * 0.375, -0.5, 0.5, 0.75), (side * 0.25, 0.5, 0.5, 0.5))
            for m, (ox, oy, sx, sy) in enumerate(shapes[: 1 + (_hash(i, k, hs, 23) < 0.6) + (_hash(i, k, hs, 23) < 0.15)]):
                c = (LEAF, LEAF_L, (70, 136, 66))[(m + k) % 3]
                cv.box("Leaf", c, (lx + ox - sx / 2, ly + oy - sy / 2, -0.875), (lx + ox + sx / 2, ly + oy + sy / 2, -0.5), mode="empty")
            if _hash(i, k, hs, 29) < 0.35:
                cv.box("Leaf", LEAF_L, (x - 0.375, y - seg * 0.3 - 0.25, -0.5 - d - 0.25), (x + 0.375, y - seg * 0.3 + 0.25, -0.5 - d),
                       mode="empty")
        # a side shoot from the second block
        if k == 1:
            s = 1 if h > 0.5 else -1
            sy = y - 0.5
            cv.box("Root", bark, (min(x, x + s * 1.75) - 0.25, sy - 0.25, -1.0), (max(x, x + s * 1.75) + 0.25, sy + 0.25, -0.5), mode="empty")
            cv.box("Root", bark, (x + s * 1.75 - 0.25, sy - 1.25, -0.875), (x + s * 1.75 + 0.25, sy, -0.5), mode="empty")
            cv.box("Leaf", LEAF, (x + s * 1.75 - 0.375, sy - 1.75, -0.875), (x + s * 1.75 + 0.375, sy - 1.25, -0.625), mode="empty")
        x += dx
        y -= seg
        th = max(0.5, th * 0.86)
        k += 1
        tip = (x, y)
    # the tip: a thin last block reaching down
    cv.box("Root", BARK, (tip[0] - 0.25, tip[1] - 0.75, -0.875), (tip[0] + 0.25, tip[1] + 0.125, -0.5), mode="empty")
    if i % 2 == 0:
        bulb(cv, (tip[0] + 0.625, tip[1] - 0.125, -0.875), 0.5, arm_from=tip[0])


def floor_piece(cv, style, key):
    """the floor tiles' top layer in the style (Floor = tint Primary, the room's own colour)"""
    vs = cv.vs
    fl = cv.cells_of("Floor")
    top = cv.skin_top(fl)
    X, Y, Z = cv.pos()
    cv.fam["Floor"] = "flat"
    # every cell's own tile (the Floor box it was painted from): tile index, position inside it, tile size
    R = cv.R
    bx = R.boxes
    nb = len(bx)
    minx = np.array([b["pos"][0] - b["size"][0] / 2 for b in bx] + [0.0])
    minz = np.array([b["pos"][2] - b["size"][2] / 2 for b in bx] + [0.0])
    sxa = np.array([b["size"][0] for b in bx] + [6.0])
    sza = np.array([b["size"][2] for b in bx] + [6.0])
    pid = np.where(R.pid >= 0, R.pid, nb)
    tx = np.round(minx[pid] / 0.5).astype(int) + 1000
    tz = np.round(minz[pid] / 0.5).astype(int) + 1000
    ux, uz = X - minx[pid], Z - minz[pid]
    tsx, tsz = sxa[pid], sza[pid]
    border = (ux < vs * 0.6) | (uz < vs * 0.6)
    if style == "b":
        plate = (np.abs(ux - tsx / 2) < vs * 0.5) | (np.abs(uz - tsz / 2) < vs * 0.5)
        n = _hv(tx, tz, 3)
        f = np.where(border, 0.72, np.where(plate, 0.86, 0.94 + 0.06 * n))
        cv.recolor(top, lambda x, y, z: np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1))
        # brass-framed grates (4 x 2 studs) on every other tile, the slots glowing dim in the element colour
        grate = _hv(tx, tz, 77) < 0.34
        gx, gz = np.abs(ux - tsx / 2), np.abs(uz - tsz / 2)
        rot = (_hv(tx, tz, 5) < 0.5)
        ax, az = np.where(rot, gz, gx), np.where(rot, gx, gz)
        inside = grate & (ax < 2.0) & (az < 1.0)
        frame = inside & ((ax > 2.0 - vs * 0.99) | (az > 1.0 - vs * 0.99))
        slot = inside & ~frame
        along = np.where(rot, Z, X)
        lit = slot & ((np.floor(along / vs).astype(int) % 2) == 0)
        cv.recolor(top & frame, lambda x, y, z: np.repeat(np.array([BRASS], float), len(x), 0))
        cv.rename(top & frame, "Brass")
        cv.recolor(top & slot & ~lit, lambda x, y, z: np.repeat(np.array([SLOT], float), len(x), 0))
        cv.rename(top & slot & ~lit, "Slot")
        cv.recolor(top & lit, lambda x, y, z: np.repeat(np.array([grey(0.5)], float), len(x), 0))
        cv.rename(top & lit, "Element")
    elif style == "a":
        # each tile: two or three stones (a seam across the middle, one half split again), worn, a few cracked
        cut = _hv(tx, tz, 7) < 0.5
        a1 = np.where(cut, ux, uz)
        a2 = np.where(cut, uz, ux)
        h1 = np.where(cut, tsx, tsz) / 2
        h2 = np.where(cut, tsz, tsx) / 2
        seam1 = np.abs(a1 - h1) < vs * 0.5
        split = (_hv(tx, tz, 9) < 0.6) & (a1 > h1) & (np.abs(a2 - h2) < vs * 0.5)
        sid = tx * 7 + tz * 13 + (a1 > h1) * 3 + ((a1 > h1) & (a2 > h2) & (_hv(tx, tz, 9) < 0.6)) * 5
        n = _hv(sid, 11)
        f = np.where(border | seam1 | split, 0.66, 0.8 + 0.18 * np.floor(n * 4) / 3.0)  # (Gemini: too clean; more spread)
        # a worn, paler middle on each stone
        wear = (np.abs(a2 - h2) < 1.6) & (np.abs(a1 - np.where(a1 > h1, h1 * 1.5, h1 * 0.5)) < 0.7)
        f = np.where(wear & ~(border | seam1 | split), np.minimum(1.0, f + 0.05), f)
        # cracks: a zig-zag on a few stones
        crk = (_hv(sid, 19) < 0.24) & (np.abs((a2 - h2) - 0.6 * np.sin(a1 * 2.1 + _hv(sid, 2) * 6)) < vs * 0.5) & ~border
        f = np.where(crk, 0.62, f)
        cv.recolor(top, lambda x, y, z: np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1))
        # one stone patched with planks (on the big floors only)
        big = ("48x48" in key) or ("60x72" in key)
        planks = top & big & (np.abs(X - 9.0) < 1.25) & (np.abs(Z + 4.5) < 1.25) & ~border
        cv.recolor(planks, lambda x, y, z: np.where(((np.floor(x / 0.5).astype(int) % 2) == 0)[:, None],
                                                    np.array(WOOD, float), np.array(WOOD_D, float)))
        cv.rename(planks, "Wood")
    else:
        # a random ashlar path: rows of uneven depth (1.5 / 2 / 2.5), stones of uneven length in each row, moss and
        # grass in the joints (rectilinear on purpose: the old Voronoi stones cost 20-38k triangles a floor)
        G = 3.0
        rz = np.floor(Z / 0.5).astype(int)
        # row edges: a row every 3 or 4 or 5 half-studs, from a hash walk (vectorised by a cumulative table)
        lo_z = int(np.floor(Z.min() / 0.5)) - 6 if Z.size else 0
        hi_z = int(np.ceil(Z.max() / 0.5)) + 6 if Z.size else 0
        edges, zz, k = [], lo_z, 0
        while zz <= hi_z:
            edges.append(zz)
            zz += 4 + int(_hash(k, 61) * 3)
            k += 1
        edges = np.array(edges)
        row = np.searchsorted(edges, rz, side="right") - 1
        rj = (rz == edges[np.clip(row, 0, len(edges) - 1)])
        # stones along each row: lengths 2..4 studs, offset per row
        off = _hv(row, 63) * 4.0
        u = X + off
        ln = 3.0 + np.floor(_hv(row, 65) * 3)
        sc = np.floor(u / ln).astype(int)
        sj = (u - sc * ln) < vs * 0.99
        joint = rj | sj
        bid = row * 1000 + sc
        n = np.floor(_hv(bid, 3) * 4) / 3.0  # four stone shades
        f = 0.84 + 0.14 * n
        cv.recolor(top & ~joint, lambda x, y, z: np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1))
        # the joints and a few mossy stones stay IN the tinted floor (a part of their own would add the side faces of
        # every stone along every joint: 15-28k triangles a floor); their colours are pre-divided by the C floor tint
        # (Flag 148, 154, 126) so they read moss green after it (x the tint: about 110, 153, 98 / 87, 138, 83)
        mossy = top & ~joint & (_hv(bid, 71) < 0.08)
        cv.recolor(mossy, lambda x, y, z: np.repeat(np.array([(230, 255, 210)], float), len(x), 0))
        mj = top & joint
        # (the moss shade changes in 3-stud patches, not per cell: per-cell colours cost 4x the triangles)
        cv.recolor(mj, lambda x, y, z: np.where((_hv(np.floor(x / G).astype(int), np.floor(z / G).astype(int), 4) < 0.5)[:, None],
                                                np.array((190, 255, 200), float), np.array((150, 230, 170), float)))
        # (no grass tufts: single raised cells read as loose green cubes in the renders)


def pillar_piece(cv, style, key):
    vs = cv.vs
    X, Y, Z = cv.pos()
    sh = cv.cells_of("Pillar")
    base = cv.cells_of("PillarBase")
    cap = cv.cells_of("PillarCap")
    h = float(max(b["pos"][1] + b["size"][1] / 2 for b in cv.R.boxes if b["name"] == "Pillar"))
    cv.fam["Pillar"] = "flat"
    if style == "a":
        # octagonal drums: chamfer the corners, a joint every 2 studs, each drum its own shade; a moulded base
        cv.clear(sh & (np.abs(X) + np.abs(Z) > 1.42))
        cv.clear((base | cap) & (np.abs(X) + np.abs(Z) > 1.86))
        drum = np.floor((Y - 1.0) / 2.0).astype(int)
        jt = (((Y - 1.0) / 2.0) % 1.0) * 2.0 < vs * 0.55
        n = np.floor(_hv(drum, int(h * 10), 3) * 3) / 2.0  # three drum shades
        f = np.where(jt, 0.7, 0.86 + 0.13 * n)
        cv.recolor(cv.cells_of("Pillar"), lambda x, y, z: np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1))
        cv.where("Moulding", SLATE_A, lambda x, y, z: (np.abs(x) + np.abs(z) <= 1.62) & (y > 1.0) & (y < 1.25), (-1.3, 1.0, -1.3), (1.3, 1.25, 1.3), mode="empty")
        cv.where("Moulding", SLATE_A, lambda x, y, z: (np.abs(x) + np.abs(z) <= 1.62) & (y > h - 1.05) & (y < h - 0.8), (-1.3, h - 1.05, -1.3), (1.3, h - 0.8, 1.3), mode="empty")
    elif style == "b":
        seam = (((Y - 1.0) / 3.0) % 1.0) * 3.0 < vs * 0.55
        f = np.where(seam, 0.76, 0.97)
        edge = (np.abs(np.abs(X) - 1.0) < vs * 0.6) & (np.abs(np.abs(Z) - 1.0) < vs * 0.6)
        f = np.where(edge, 0.9, f)
        cv.recolor(sh, lambda x, y, z: np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1))
        cv.recolor(base | cap, lambda x, y, z: np.repeat(np.array([STORM], float), len(x), 0))
        cv.rename(base | cap, "Girder")
        for yy in (2.4, h - 2.2):
            cv.box("Brass", BRASS, (-1.25, yy, -1.25), (1.25, yy + 0.25, 1.25), mode="all")
        # rivets on each face at the panel corners, only on the lowest and highest panel rows next to the brass bands
        # (Gemini's final review: a rivet pair every 3 studs read as noise on SmoothPlastic)
        rows = list(np.arange(1.0 + 0.375, h - 1.0, 3.0))
        for yy in sorted(set([rows[0], rows[-1]])):
            for s in (-1, 1):
                for t in (-0.6, 0.6):
                    cv.box("Rivet", BRASS, (t - vs / 2, yy - vs / 2, s * 1.0 - (vs if s < 0 else 0)), (t + vs / 2, yy + vs / 2, s * 1.0 + (vs if s > 0 else 0)), mode="empty")
                    cv.box("Rivet", BRASS, (s * 1.0 - (vs if s < 0 else 0), yy - vs / 2, t - vs / 2), (s * 1.0 + (vs if s > 0 else 0), yy + vs / 2, t + vs / 2), mode="empty")
        cv.box("Brass", BRASS, (-1.3, h, -1.3), (1.3, h + vs, 1.3), mode="empty")
    else:
        # brick pillar: courses 1.0 with staggered joints on each face (the wall's 2 x 1 bricks; three shades)
        row = np.floor(Y / 1.0).astype(int)
        u = np.where(np.abs(Z) >= np.abs(X), X, Z) + 1.0 + (row % 2) * 1.0
        mortar = ((Y - row * 1.0) < vs * 0.55) | ((u % 2.0) < vs * 0.55)
        f = np.where(mortar, 0.76, 0.88 + 0.05 * np.floor(_hv(row, np.floor(u / 2.0).astype(int), 5) * 3))
        cv.recolor(sh, lambda x, y, z: np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1))
        cv.recolor(base | cap, lambda x, y, z: _rgb_choice(SOIL, _hv(np.floor(x / 0.6).astype(int), np.floor(z / 0.6).astype(int), np.floor(y).astype(int))))
        # a root winding up it with leaves (1.25 turns), starting at the base
        pts = []
        ph = _hash(int(h * 10), 3)
        for t in np.linspace(0, 1, 10):
            a = ph * 6.28 + t * 7.9
            pts.append((math.cos(a) * 1.18, 1.0 + t * (h - 2.4), math.sin(a) * 1.18))
        cv.path("Root", BARK, pts, 0.26, 0.16, mode="empty")  # (over the tinted bricks it would carve holes: faces)
        for k in range(1, 9, 2):
            p = pts[k]
            cv.ell("Leaf", LEAF if k % 4 == 1 else LEAF_L, (p[0] * 1.25, p[1] + 0.15, p[2] * 1.25), (0.32, 0.16, 0.32))


def door_piece(cv, style, key):
    vs = cv.vs
    X, Y, Z = cv.pos()
    jamb = cv.cells_of("Jamb")
    lint = cv.cells_of("Lintel")
    if style == "a":
        # quoined jambs (alternating long / short blocks), a pointed arch of voussoirs springing from y 8
        blk = np.floor(Y / 1.0).astype(int)
        jt = ((Y % 1.0) < vs * 0.55)
        f = np.where(jt, 0.68, 0.84 + 0.14 * _hv(blk, np.sign(X).astype(int), 3))
        cv.recolor(jamb, lambda x, y, z: (np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1) / 255.0) * np.array((154, 160, 178), float))
        for s in (-1, 1):
            for yy in range(0, 8, 2):
                cv.box("Quoin", (146, 152, 170), ((5.0 if s > 0 else -5.6), yy + 0.0, -0.8), ((5.6 if s > 0 else -5.0), yy + 1.0 - vs * 0.5, 0.8), mode="empty")
        cv.clear(lint)
        # the arch: two arcs of radius 6 / 7 about (+-1.5, 8): the inner edge springs at x -+4.5 (over the jambs,
        # outside the 8-stud opening), the apex stays under the cornice (inner 13.8, outer 14.8)
        def arch_mask(x, y, z):
            left = x <= 0
            cx = np.where(left, 1.5, -1.5)
            d = np.sqrt((x - cx) ** 2 + (y - 8.0) ** 2)
            return (y >= 8.0) & (d >= 6.0) & (d <= 7.0) & (np.abs(z) <= 0.8)

        def arch_col(x, y, z):
            left = x <= 0
            cx = np.where(left, 1.5, -1.5)
            ang = np.arctan2(y - 8.0, np.abs(x - cx))
            k = np.floor(ang / 0.16).astype(int)
            jn = ((ang / 0.16) % 1.0) < 0.12
            base = 0.84 + 0.14 * _hv(k, np.sign(x).astype(int) + 3, 7)
            f2 = np.where(jn, 0.66, base)
            return np.repeat((f2 * 255)[:, None], 3, 1) / 255.0 * np.array((160, 166, 184), float)

        cv.where("Voussoir", arch_col, arch_mask, (-6.0, 7.9, -0.8), (6.0, 15.0, 0.8))
        cv.box("Keystone", (182, 188, 204), (-0.5, 13.5, -0.9), (0.5, 14.85, 0.9), mode="all")
        # imposts: a slate block on each jamb top where the arch springs
        for s in (-1, 1):
            cv.box("Impost", SLATE_A, (s * 4.5 - 0.75, 7.6, -0.95), (s * 4.5 + 0.75, 8.1, 0.95), mode="all")
    elif style == "b":
        # storm-blue girders: flanges lighter, web darker, rivet columns; brass gussets in the top inner corners
        fl = np.abs(Z) > 0.55
        cv.recolor(jamb | lint, lambda x, y, z: np.where(_lookup(fl, cv, x, y, z)[:, None], np.array(STORM_L, float), np.array(STORM, float)))
        for s in (-1, 1):
            for yy in np.arange(0.6, 8.0, 0.9):
                cv.box("Rivet", BRASS, (s * 4.5 - vs / 2, yy - vs / 2, -0.8 - vs), (s * 4.5 + vs / 2, yy + vs / 2, -0.8), mode="empty")
            # a brass corner plate on the jamb front at the top (outside the opening: the doorway stays 8 clear)
            cv.box("Brass", BRASS, ((4.0 if s > 0 else -5.0), 7.2, -0.8 - vs), ((5.0 if s > 0 else -4.0), 8.0, -0.8), mode="empty")
        for xx in np.arange(-4.5, 4.6, 0.9):
            cv.box("Rivet", BRASS, (xx - vs / 2, 8.5 - vs / 2, -0.8 - vs), (xx + vs / 2, 8.5 + vs / 2, -0.8), mode="empty")
        # a brass plaque over the lintel and two sooty handprints on the left jamb (the mechanics' own touch)
        cv.box("Brass", BRASS, (-0.9, 9.0, -0.6), (0.9, 9.6, -0.35), mode="all")
        cv.box("Brass", BRASS_D, (-0.65, 9.15, -0.62), (0.65, 9.45, -0.6), mode="all")
        for (hx, hy) in ((-4.4, 4.2), (-4.6, 5.0)):
            cv.where("Soot", (36, 40, 52), lambda x, y, z: (((x - hx) / 0.3) ** 2 + ((y - hy) / 0.38) ** 2 <= 1.0) & (z < -0.55),
                     (hx - 0.4, hy - 0.5, -0.81), (hx + 0.4, hy + 0.5, -0.5), mode="over")
    else:
        # brick jambs (C's terracotta) with a timber frame and a log lintel, ivy along the jambs
        row = np.floor(Y / 0.75).astype(int)
        mortar = ((Y - row * 0.75) < vs * 0.55) | (((Z + 0.8 + (row % 2) * 0.5) % 1.0) < vs * 0.55)
        f = np.where(mortar, 0.66, 0.9 + 0.1 * _hv(row, np.floor(Z).astype(int), 3))
        cv.recolor(jamb, lambda x, y, z: (np.repeat((255 * _lookup(f, cv, x, y, z))[:, None], 3, 1) / 255.0) * np.array(TERRA, float))
        for s in (-1, 1):
            cv.box("Wood", WOOD, ((4.0 if s > 0 else -4.25), 0, -0.8), ((4.25 if s > 0 else -4.0), 8.0, 0.8), mode="over")
        cv.recolor(lint, lambda x, y, z: np.where((np.abs(np.abs(z) - 0.8) < vs * 0.6)[:, None] | (((x + 5) % 1.7) < vs)[:, None],
                                                  np.array(BARK, float), np.array(BARK_L, float)))
        for s in (-1, 1):
            pts = [(s * 4.75 + 0.2 * math.sin(t * 5), 8.8 - t * 5.0, -0.9) for t in np.linspace(0, 1, 7)]
            cv.path("Vine", (70, 120, 60), pts, 0.12)
            for k, p in enumerate(pts[1:]):
                cv.ell("Leaf", LEAF if k % 2 else LEAF_L, (p[0] + 0.25 * (1 if k % 2 else -1), p[1], p[2] - 0.12), (0.28, 0.14, 0.2))
        cv.ell("Moss", MOSS, (0, 9.05, 0), (5.2, 0.12, 0.7))


def dais_piece(cv, style, key):
    vs = cv.vs
    X, Y, Z = cv.pos()
    dais = cv.cells_of("Dais")
    steps = cv.cells_of("Step")
    kerb = cv.cells_of("DaisKerb")
    rug = cv.cells_of("DaisCarpet")
    top = cv.skin_top(dais)
    side = dais & ~top
    if style == "a":
        row = np.floor(Y / 0.8).astype(int)
        u = X + (row % 2) * 1.0 + Z
        jt = ((Y % 0.8) < vs * 0.55) | ((u % 2.0) < vs * 0.55)
        cv.recolor(side, lambda x, y, z: np.where(_lookup(jt, cv, x, y, z)[:, None], np.array((110, 116, 134), float),
                                                    np.array((150, 156, 174), float) * (0.9 + 0.1 * _hv(np.floor(y / 0.8).astype(int), np.floor((x + z) / 2).astype(int), 3))[:, None]))
        fl = ((np.abs(X) % 2.0) < vs * 0.55) | ((np.abs(Z) % 2.0) < vs * 0.55)
        cv.recolor(top, lambda x, y, z: np.where(_lookup(fl, cv, x, y, z)[:, None], np.array((120, 124, 140), float), np.array((164, 168, 184), float)))
        rim = top & ((np.abs(X) > 11.6) | (np.abs(Z) > 6.6))
        cv.recolor(rim, lambda x, y, z: np.repeat(np.array([(214, 170, 80)], float), len(x), 0))
        cv.rename(rim, "Gold")
        cv.recolor(rug, lambda x, y, z: np.where((np.abs(x) > 2.5)[:, None] | (np.abs(z) > 4.5)[:, None], np.array((214, 170, 80), float), np.array((150, 34, 48), float)))
        cv.recolor(kerb, lambda x, y, z: np.repeat(np.array([SLATE_A], float), len(x), 0))
        cv.recolor(steps, lambda x, y, z: np.repeat(np.array([(150, 154, 170)], float), len(x), 0))
        # candle wax run down the front of the dais from the candles' corners
        for xx in (-10.5, -7.5, 7.0, 10.0):
            ln = 0.6 + 1.0 * _hash(int(xx * 10), 5)
            cv.box("Wax", (238, 232, 214), (xx - 0.2, 2.4 - ln, -7.0 - vs), (xx + 0.2, 2.4, -7.0), mode="empty")
    elif style == "b":
        n = (((X + 12) / 3.0) % 1.0) * 3.0 < vs * 0.55
        cv.recolor(side, lambda x, y, z: np.where(_lookup(n, cv, x, y, z)[:, None] | (np.abs(y - 1.2) < 0.1)[:, None], np.array((150, 160, 184), float), np.array((226, 230, 240), float)))
        tp = ((np.abs(X) % 3.0) < vs * 0.55) | ((np.abs(Z) % 3.0) < vs * 0.55)
        cv.recolor(top, lambda x, y, z: np.where(_lookup(tp, cv, x, y, z)[:, None], np.array((168, 176, 198), float), np.array((232, 236, 244), float)))
        rim = top & ((np.abs(X) > 11.6) | (np.abs(Z) > 6.6))
        cv.recolor(rim, lambda x, y, z: np.repeat(np.array([BRASS], float), len(x), 0))
        cv.rename(rim, "Brass")
        cv.recolor(rug, lambda x, y, z: np.where((np.abs(x) > 2.6)[:, None], np.array(BRASS, float), np.array((58, 74, 132), float)))
        cv.recolor(kerb, lambda x, y, z: np.repeat(np.array([BRASS], float), len(x), 0))
        glow = kerb & (Z < -7.2 - 0.1) & (np.abs(Y - 2.6) < 0.12)
        cv.recolor(glow, lambda x, y, z: np.repeat(np.array([grey(0.8)], float), len(x), 0))
        cv.rename(glow, "Element")
        st_top = cv.skin_top(steps)
        cv.recolor(steps, lambda x, y, z: np.repeat(np.array([(104, 118, 150)], float), len(x), 0))
        nose = st_top & (((Z + 100) % 1.6) < vs * 1.1)
        cv.recolor(nose, lambda x, y, z: np.repeat(np.array([BRASS], float), len(x), 0))
        for xx in np.arange(-11.4, 11.6, 1.5):
            cv.box("Rivet", BRASS, (xx - vs / 2, 1.6 - vs / 2, -7.0 - vs), (xx + vs / 2, 1.6 + vs / 2, -7.0), mode="empty")
    else:
        sid = _hv(np.floor((X + 0.4 * np.floor(Y / 0.6)) / 0.9).astype(int), np.floor(Y / 0.6).astype(int), np.floor(Z / 0.9).astype(int))
        cv.recolor(side, lambda x, y, z: _rgb_choice(SOIL, _lookup(sid, cv, x, y, z)))
        cv.recolor(top, lambda x, y, z: np.where((_hv(np.floor(x / 1.5).astype(int), np.floor(z / 1.5).astype(int), 2) < 0.45)[:, None],
                                                 np.array(MOSS_L, float), np.array(MOSS, float)))
        cv.rename(top, "Moss")
        cv.recolor(rug, lambda x, y, z: np.where((((np.floor(x / 0.6) + np.floor(z / 1.2)) % 2) == 0)[:, None], np.array((204, 126, 88), float), np.array((176, 104, 74), float)))
        cv.recolor(kerb, lambda x, y, z: np.repeat(np.array([BARK], float), len(x), 0))
        cv.recolor(steps, lambda x, y, z: np.repeat(np.array([(150, 150, 132)], float), len(x), 0))
        st_top = cv.skin_top(steps)
        cv.recolor(st_top & (np.abs(X) > 4.0), lambda x, y, z: np.repeat(np.array([MOSS], float), len(x), 0))
        # (no single-cell tufts: they read as loose green cubes)
        # roots creeping over the front edge of the dais
        for xx in (-9.5, 8.0):
            pts = [(xx - 1.5, 2.45, -5.5), (xx - 0.8, 2.5, -6.6), (xx, 2.3, -7.1), (xx + 0.3, 1.4, -7.15), (xx + 0.1, 0.4, -7.1)]
            cv.path("Root", BARK, pts, 0.24, 0.12)


def carpet_piece(cv, style, key):
    vs = cv.vs
    X, Y, Z = cv.pos()
    cp = cv.skin_top(cv.cells_of("Carpet"))  # the walked face only (the underside keeps the Part colour; budget)
    hw = 4.0
    edge = np.abs(X) > hw - 0.5
    if style == "a":
        stripe = (np.abs(X) > hw - 0.75) & ~edge
        # a lozenge down the middle every 3 studs (dark red, a gold heart)
        dz = np.abs(((Z + 100.5) % 3.0) - 1.5)
        diamond = (dz / 1.1 + np.abs(X) / 0.9) < 1.0
        heart = (dz / 1.1 + np.abs(X) / 0.9) < 0.3
        cv.recolor(cp, lambda x, y, z: np.where(_lookup(edge, cv, x, y, z)[:, None], np.array((214, 170, 80), float),
                                                np.where(_lookup(heart, cv, x, y, z)[:, None], np.array((214, 170, 80), float),
                                                         np.where(_lookup(diamond, cv, x, y, z)[:, None], np.array((116, 24, 38), float), np.array((150, 34, 48), float)))))
        cv.recolor(cp & stripe, lambda x, y, z: np.repeat(np.array([grey(0.92)], float), len(x), 0))
        cv.rename(cp & stripe, "Element")
    elif style == "b":
        brass = np.abs(X) > hw - 0.25
        u = (Z + 100) % 6.0
        chev = (np.abs(u - (3.0 - np.abs(X) * 0.5)) < vs * 0.55) & (np.abs(X) < 1.6)
        cv.recolor(cp, lambda x, y, z: np.where(_lookup(brass, cv, x, y, z)[:, None], np.array(BRASS, float),
                                                np.where(_lookup(chev, cv, x, y, z)[:, None], np.array((226, 232, 244), float), np.array((58, 74, 132), float))))
        lamp = (np.abs(np.abs(X) - (hw - 0.6)) < vs * 0.5) & ((((Z + 100) % 3.0)) < vs)
        cv.recolor(cp & lamp, lambda x, y, z: np.repeat(np.array([grey(0.95)], float), len(x), 0))
        cv.rename(cp & lamp, "Element")
    else:
        # basket-weave terracotta: pairs of 2 x 1 pavers turning by the 2-stud square
        cx, cz = np.floor(X / 2.0).astype(int), np.floor((Z + 100) / 2.0).astype(int)
        horiz = ((cx + cz) % 2) == 0
        ux, uz = X - cx * 2.0, (Z + 100) - cz * 2.0
        mort = (ux < vs * 0.55) | (uz < vs * 0.55) | np.where(horiz, np.abs(uz - 1.0) < vs * 0.5, np.abs(ux - 1.0) < vs * 0.5)
        moss = edge & (_hv(np.floor(Z / 1.5).astype(int), np.sign(X).astype(int), 3) < 0.6)
        cv.recolor(cp, lambda x, y, z: np.where(_lookup(moss, cv, x, y, z)[:, None], np.array(MOSS, float),
                                                np.where(_lookup(mort, cv, x, y, z)[:, None], np.array((146, 90, 66), float),
                                                         np.array((204, 126, 88), float))))
        flower = edge & (_hv(np.floor(Z / 0.5).astype(int), np.sign(X).astype(int), 9) < 0.08)
        R = cv.R
        idx = np.argwhere(cp & flower)
        for (i, j, k) in idx:
            if j + 1 < R.shape[1] and R.col[i, j + 1, k] == 0:
                c = grey(0.95)
                R.col[i, j + 1, k] = ((c[0] << 16) | (c[1] << 8) | c[2]) + 1
                R.pid[i, j + 1, k] = cv.pid("Element")


PIECES = {"wall": None, "floor": floor_piece, "pillar": pillar_piece, "door": door_piece, "dais": dais_piece,
          "carpet": carpet_piece}
WALLS = {"a": wall_a, "b": wall_b, "c": wall_c}


@prop("ds_baked")
def ds_baked(entry, kit):
    """one styled shell piece: its Part build (the recorded Mesh.tag target) + the style's voxel work"""
    from props import arena as AR
    a = entry.get("args") or {}
    style, piece = a["style"], a["piece"]
    t = AR.target(entry["key"])
    scale = float(t.get("Scale") or 1)
    keep = set(x for x in (t.get("Keep") or "").split(",") if x)
    bx = [b for b in AR.parse_boxes(t["Boxes"], scale) if b["name"] not in keep and b["name"] not in AR.SKIP]
    tints = dict(a.get("tints") or {})
    for b in bx:
        if b["name"] in tints:
            b["rgb"] = WHITE
    vs = float(a.get("vs", 0.25))
    offy = AS.align_y(bx, vs) if a.get("aligny") else None
    cv = Canvas(vs, bx, offy=offy, pad=float(a.get("pad", 1.5)))
    # the style paints its own texture on the shells and the trims (no arena brick / flute lines; a per-cell speckle on
    # the cap and plinth runs cost ~4k triangles a wall)
    for nm in ("Wall", "Floor", "Pillar", "Plinth", "Cap", "PillarBase", "PillarCap", "Jamb", "Lintel", "Dais", "DaisKerb",
               "DaisCarpet", "Step", "Carpet"):
        cv.fam[nm] = "flat"
    if piece == "wall":
        WALLS[style](cv, wall_info(bx), entry["key"])
    else:
        PIECES[piece](cv, style, entry["key"])
    tints.setdefault("Element", "Secondary")
    m = kit.model(entry["key"], "prop", vs=vs, K=1.0)
    # (detail levels 1 / 0 only: the level 2-3 speckle on the moss, roots, soil and ribs costs 10-20% more triangles on
    # every shell piece, and the room budget (90k a template) is the binding one; the designed props keep it)
    tries = finish(m, cv, tints, AR.budget_tris(entry, 8000), levels=(1, 0))
    m.groups = {}
    m.attachments = {}
    bad = [x for x in AR.world()["BadList"] if x.startswith(entry["key"] + ":")]
    if bad:
        raise RuntimeError("%s: tagged targets differ from the baked one: %s" % (entry["key"], bad[:3]))
    m.attachments["LayoutSig"] = AR.layout_sig(t["Sig"])
    look = t.get("Look") or {}
    m.meta = {"source": "%s %s (Mesh.tag target) + style %s %s" % (t["Class"], t["Name"], style, piece),
              "pivot": "the Tag origin", "keep": sorted(keep), "tints": tints, "tries": tries,
              "previewLook": {k: [round(float(x) * 255) for x in v[:3]] for k, v in look.items()}}
    return m
