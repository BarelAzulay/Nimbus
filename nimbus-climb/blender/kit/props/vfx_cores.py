"""Pet attack VFX cores (catalog blender/catalog/vfx.json; spec docs/superpowers/specs/2026-10-23-pet-attack-vfx-design.md,
"Budgets, quality, readability": solid cores, sparse textures).

Every key is the solid glowing BODY of an attack effect (orb, crescent, spear ...) or of a signature special (phoenix,
sun disc, storm wolf ...): the runtime tints it (MeshPart.Color = the element colour, Neon / Glass) and tweens its size
and transparency; flipbook textures are only a sparse finishing layer on top.

Contract (checked by blender/kit/selftest.py "vfx"):
  * ONE MeshPart named `Core` (group Core, key Core), Color white (["rgb", 255, 255, 255]), material Neon.  The vertex
    colours carry a two-tone accent: base white, `Core_Dark` = the kit's dark multiply (0.84; deep creases 0.71), so a
    tinted core still reads its shape (a slash's hot leading edge, a spear's head vs its shaft, a wolf's legs ...).
  * Fine-voxel style: shapes are sculpted on a voxel grid (studs per voxel `vs`, 0.075 .. 0.2) and greedy-meshed, so
    every edge is voxel-stepped, but each silhouette is one simple readable shape.
  * Pivot = the centre of the bounds; +Y up, -Z forward (projectiles point their tip / convex edge at -Z, discs and
    stars face -Z).  args.size in the catalog = the design size in studs (scale 1).
  * One connected solid (no floating voxels; the build fails otherwise).

Shapes are written as numpy masks over voxel CENTRES on a half-voxel-offset grid (`Sculpt`), so a design that is
2 studs across gives exactly 2 studs of voxels.  Sculpt(scale=S) sculpts in design units that are S studs each.
"""
import math

import numpy as np

from props import prop

CORE = [1.0, 1.0, 1.0, "Neon", 0]
TAU = 2 * math.pi


def _v(p):
    return np.asarray(p, float)


class Sculpt:
    """voxel grid in design units (studs / scale): masks of voxel centres -> keys Core / Core_Dark"""

    def __init__(self, vs, ext, scale=1.0):
        self.vs, self.S = float(vs), float(scale)
        self.half = int(math.ceil(ext / 2.0 / vs)) + 3
        n = 2 * self.half
        self.n = n
        r = (np.arange(n) - self.half + 0.5) * self.vs / self.S  # voxel centres, design units
        self.r = r
        self.L = np.zeros((n, n, n), np.int8)  # 0 empty, 1 Core, 2 Core_Dark
        self._full = (slice(0, n),) * 3

    # ---------------------------------------------------------------- regions
    def _sl(self, lo, hi):
        sl = []
        for a, b in zip(lo, hi):
            i0 = int(math.floor(a * self.S / self.vs + self.half - 0.5)) - 1
            i1 = int(math.ceil(b * self.S / self.vs + self.half - 0.5)) + 2
            sl.append(slice(max(0, i0), min(self.n, max(0, i1))))
        return tuple(sl)

    def xyz(self, sl=None):
        sl = sl or self._full
        X, Y, Z = np.meshgrid(self.r[sl[0]], self.r[sl[1]], self.r[sl[2]], indexing="ij")
        return X, Y, Z

    def region(self, lo, hi, fn):
        sl = self._sl(lo, hi)
        X, Y, Z = self.xyz(sl)
        return sl, fn(X, Y, Z)

    def full(self, fn):
        X, Y, Z = self.xyz()
        return self._full, fn(X, Y, Z)

    # ---------------------------------------------------------------- write
    def add(self, reg, dark=False, where=None):
        sl, m = reg
        if where is not None:
            m = m & where(*self.xyz(sl))
        sub = self.L[sl]
        sub[m] = 2 if dark else 1

    def cut(self, reg):
        sl, m = reg
        self.L[sl][m] = 0

    def paint(self, reg, dark=True):
        sl, m = reg
        sub = self.L[sl]
        sub[m & (sub != 0)] = 2 if dark else 1

    # ---------------------------------------------------------------- primitives (design units)
    def ell(self, c, r):
        c, r = _v(c), _v(r) * np.ones(3)
        return self.region(c - r, c + r, lambda X, Y, Z: ((X - c[0]) / r[0]) ** 2 + ((Y - c[1]) / r[1]) ** 2
                           + ((Z - c[2]) / r[2]) ** 2 <= 1.0)

    def cap(self, a, b, ra, rb=None, flat=False):
        """capsule a -> b, radius ra -> rb (flat=True: a cone frustum without the round ends)"""
        a, b = _v(a), _v(b)
        rb = ra if rb is None else rb
        ab = b - a
        l2 = float(ab @ ab)
        rm = max(ra, rb)

        def fn(X, Y, Z):
            px, py, pz = X - a[0], Y - a[1], Z - a[2]
            t = (px * ab[0] + py * ab[1] + pz * ab[2]) / max(l2, 1e-12)
            tc = np.clip(t, 0, 1)
            qx, qy, qz = px - ab[0] * tc, py - ab[1] * tc, pz - ab[2] * tc
            r = ra + (rb - ra) * tc
            m = qx * qx + qy * qy + qz * qz <= r * r
            if flat:
                m &= (t >= 0) & (t <= 1)
            return m
        return self.region(np.minimum(a, b) - rm, np.maximum(a, b) + rm, fn)

    def cone(self, a, b, ra, rb=0.0):
        return self.cap(a, b, ra, rb, flat=True)

    def curve(self, pts, radii, steps=8):
        """Catmull-Rom tube through pts (radii per point): a list of capsule regions"""
        from nvox.grid import _curve_samples
        sp, sr = _curve_samples([_v(p) for p in pts], list(radii), steps, True)
        return [self.cap(sp[i], sp[i + 1], sr[i], sr[i + 1]) for i in range(len(sp) - 1)]

    def add_all(self, regs, dark=False, where=None):
        for r in regs:
            self.add(r, dark, where)

    def paint_all(self, regs, dark=True):
        for r in regs:
            self.paint(r, dark)


def frame(d):
    """orthonormal (u, v, d) for an axis direction d"""
    d = _v(d) / np.linalg.norm(d)
    up = np.array([0.0, 1.0, 0.0]) if abs(d[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = np.cross(up, d)
    u /= np.linalg.norm(u)
    return u, np.cross(d, u), d


def hexr(a, b):
    """hexagon 'radius' (flat sides on +-b) of in-plane coordinates a, b"""
    return np.maximum(np.abs(a) * 0.866 + np.abs(b) * 0.5, np.abs(b))


def facet(a, b, n=6, phase=0.0):
    """alternate facet index (0 / 1) of the n-gon sector a point lies in"""
    return np.floor((np.arctan2(b, a) + phase) / (TAU / n)).astype(int) % 2


def star2d(x, y, R, ri, inset=0.0, points=5):
    """inside a `points`-point star (tip up) with outer radius R and inner radius ri, at least `inset` from its edge"""
    th = np.arctan2(x, y)  # 0 = up
    seg = TAU / points
    loc = np.mod(th + seg / 2, seg) - seg / 2  # -seg/2 .. seg/2 around the nearest tip
    rho = np.sqrt(x * x + y * y)
    pa, pb = rho * np.cos(loc), np.abs(rho * np.sin(loc))
    ia, ib = ri * math.cos(seg / 2), ri * math.sin(seg / 2)
    ea, eb = ia - R, ib
    side = (ea * pb - eb * (pa - R)) / math.hypot(ea, eb)  # signed distance inside the tip edge
    return side >= inset


# ==================================================================================================== base cores
def orb(sc):
    sc.add(sc.ell((0, 0, 0), 1.0))
    # the trailing cap (+Z) a shade darker: a hot front when it flies at -Z
    sc.paint(sc.full(lambda X, Y, Z: Z > 0.42))


def crescent(sc):
    def body(X, Y, Z):
        fo = np.sqrt((X / 2.0) ** 2 + ((Z - 1.0) / 2.0) ** 2)
        fi = np.sqrt((X / 1.92) ** 2 + ((Z - 1.28) / 1.6) ** 2)
        blade = (fo <= 1.0) & (fi >= 1.0) & (Z <= 1.0)
        s = (fi - 1.0) / np.maximum((fi - 1.0) + (1.0 - fo), 1e-6)  # 0 at the inner edge, 1 at the cutting edge
        thick = np.where((s > 0.22) & (s < 0.85) & (np.abs(X) < 1.55), 0.2, 0.1)
        return blade & (np.abs(Y) <= thick), s
    X, Y, Z = sc.xyz()
    m, s = body(X, Y, Z)
    sc.add((sc._full, m))
    sc.paint((sc._full, m & (s < 0.38)))


def spear(sc):
    """a leaf blade (flat in XZ: reads from above, where the battle camera looks), swept barbs, collar, a dark
    shaft with a grip band, a diamond pommel; tip at -Z"""
    def head(X, Y, Z):
        u = (Z + 2.72) / 1.87  # 0 at the tip, 1 at the socket
        w = np.where(u < 0.6, 0.62 * u / 0.6, 0.62 * (1 - (u - 0.6) / 0.4 * 0.78))
        return (u >= 0) & (u <= 1) & (np.abs(X) / np.maximum(w, 1e-6) + np.abs(Y) / np.maximum(0.62 * w, 1e-6) <= 1)
    sc.add(sc.full(head))
    for s in (1, -1):
        sc.add(sc.cone((0.1 * s, 0, -0.98), (0.62 * s, 0, -0.5), 0.15, 0.03))
    sc.add(sc.full(lambda X, Y, Z: (Z >= -0.98) & (Z <= -0.74) & (np.maximum(np.abs(X), np.abs(Y)) <= 0.24)))
    sc.add(sc.full(lambda X, Y, Z: (Z > -0.74) & (Z <= 2.2) & (X * X + Y * Y <= 0.13 ** 2)), dark=True)
    sc.add(sc.full(lambda X, Y, Z: (Z > 1.45) & (Z <= 1.65) & (np.maximum(np.abs(X), np.abs(Y)) <= 0.2)))
    sc.add(sc.full(lambda X, Y, Z: (Z > 2.2) & (Z <= 2.5) &
                   (np.abs(X) + np.abs(Y) <= 0.26 * (1 - (Z - 2.2) / 0.3) + 0.12)))


def spike(sc):
    def main(X, Y, Z):
        t = (Y + 1.5) / 3.12
        r = 0.62 * np.clip(1 - t, 0, 1) ** 0.9
        ang = t * 0.7
        a = X * np.cos(ang) - Z * np.sin(ang)
        b = X * np.sin(ang) + Z * np.cos(ang)
        return (t >= 0) & (t <= 1) & (hexr(a, b) <= r), facet(a, b, 6, 0.3)
    X, Y, Z = sc.xyz()
    m, f = main(X, Y, Z)
    sc.add((sc._full, m))
    sc.paint((sc._full, m & (f == 1)))
    sc.paint(sc.full(lambda X, Y, Z: Y < -0.75))
    sc.add(sc.cone((0.3, -1.5, 0.15), (0.95, -0.55, 0.35), 0.28, 0.0), dark=True)
    sc.add(sc.cone((-0.28, -1.5, -0.2), (-0.8, -0.75, -0.6), 0.24, 0.0), dark=True)


def ring(sc):
    def fn(X, Y, Z):
        q = np.sqrt(X * X + Z * Z) - 1.75
        return (q / 0.25) ** 2 + (Y / 0.16) ** 2 <= 1
    sc.add(sc.full(fn))
    sc.paint(sc.full(lambda X, Y, Z: np.sqrt(X * X + Z * Z) < 1.66))


def shell(sc):
    def fn(X, Y, Z):
        d = np.sqrt(X * X + Y * Y + Z * Z)
        return (d <= 2.5) & (d >= 2.0)
    sc.add(sc.full(fn))

    def lines(X, Y, Z):  # a voxel lattice of latitude / longitude panel lines (a hex-shield read when tinted)
        d = np.maximum(np.sqrt(X * X + Y * Y + Z * Z), 1e-6)
        lat = np.degrees(np.arcsin(np.clip(Y / d, -1, 1)))
        lon = np.degrees(np.arctan2(Z, X))
        c = np.cos(np.radians(lat))
        return (np.abs(np.mod(lat + 15, 30) - 15) < 3.2) | ((np.abs(np.mod(lon + 22.5, 45) - 22.5) * c < 3.4) & (np.abs(lat) < 75))
    sc.paint(sc.full(lines))


def beam(sc):
    sc.add(sc.full(lambda X, Y, Z: (np.abs(Z) <= 4.0) & (X * X + Y * Y <= 0.5 ** 2)))
    # four light channels along the beam (they survive the runtime's Z stretch)
    sc.paint(sc.full(lambda X, Y, Z: (np.abs(np.abs(X) - np.abs(Y)) < 0.13) & (X * X + Y * Y > 0.3 ** 2)))


def shard(sc):
    def fn(X, Y, Z):
        w = np.where(Z < -0.05, 0.2 * (Z + 0.8) / 0.75, 0.2 * (1 - (Z + 0.05) / 0.75 * 0.8))
        return (Z >= -0.8) & (Z <= 0.7) & (hexr(X, Y / 0.8) <= w), facet(X, Y / 0.8, 6, 0.5)
    X, Y, Z = sc.xyz()
    m, f = fn(X, Y, Z)
    sc.add((sc._full, m))
    sc.paint((sc._full, m & (f == 1)))


CHUNK_PLANES = [  # (normal, distance): a lopsided rock (fixed numbers: same bytes every build)
    ((0.0, 1.0, 0.1), 0.30), ((0.1, -1.0, 0.0), 0.33), ((1.0, 0.2, 0.1), 0.38), ((-1.0, 0.1, 0.2), 0.36),
    ((0.1, 0.0, 1.0), 0.32), ((0.0, 0.2, -1.0), 0.37), ((0.7, 0.7, 0.3), 0.33), ((-0.6, 0.7, -0.4), 0.31),
    ((0.6, -0.6, -0.6), 0.35), ((-0.7, -0.5, 0.6), 0.32), ((0.5, 0.3, -0.8), 0.36), ((-0.4, -0.3, -0.8), 0.37),
]


def chunk(sc):
    def fn(X, Y, Z):
        vals = []
        for n, d in CHUNK_PLANES:
            n = _v(n) / np.linalg.norm(n)
            vals.append(X * n[0] + Y * n[1] + Z * n[2] - d)
        V = np.stack(vals)
        return V.max(0) <= 0, V.argmax(0)
    X, Y, Z = sc.xyz()
    m, which = fn(X, Y, Z)
    sc.add((sc._full, m))
    sc.paint((sc._full, m & np.isin(which, (1, 3, 5, 8, 10))))


def star(sc):
    R, ri = 0.84, 0.38

    def fn(X, Y, Z):
        rho = np.sqrt(X * X + Y * Y) / R
        thick = 0.2 * (1 - 0.68 * np.clip(rho, 0, 1))
        return star2d(X, Y, R, ri) & (np.abs(Z) <= np.maximum(thick, 0.04))
    sc.add(sc.full(fn))
    sc.paint(sc.full(lambda X, Y, Z: ~star2d(X, Y, R, ri, inset=0.085)))


def root(sc):
    """a gnarled thorny root bursting from the ground: flared ground roots, a twisting trunk, a hooked tip"""
    trunk = [(0, -1.9, 0), (0.3, -1.1, 0.2), (-0.25, -0.2, -0.12), (0.2, 0.7, 0.1), (0.05, 1.42, -0.1),
             (-0.32, 1.84, -0.14), (-0.56, 1.62, -0.1)]
    sc.add_all(sc.curve(trunk, [0.5, 0.4, 0.31, 0.23, 0.15, 0.08, 0.03], steps=10))
    # bark: a dark spiral groove up the trunk, the growing tip stays bright
    sc.paint(sc.full(lambda X, Y, Z: (np.sin(np.arctan2(Z, X) * 2 + Y * 5.0) > 0.7) & (Y < 1.0)))
    for k in range(5):
        a = math.radians(15 + 72 * k)
        c, s = math.cos(a), math.sin(a)
        L = 1.35 if k % 2 == 0 else 1.05
        sc.add_all(sc.curve([(0.2 * c, -1.7, 0.2 * s), (0.6 * L * c, -1.86, 0.6 * L * s), (L * c, -1.94, L * s)],
                            [0.27, 0.17, 0.04], steps=6), dark=True)
    for i, (p, r) in enumerate(zip(trunk[1:5], (0.4, 0.31, 0.23, 0.15))):
        a = 0.6 + i * 2.3
        d = np.array([math.cos(a), 0.4, math.sin(a)])
        base = _v(p)
        sc.add(sc.cone(base, base + d * (r + 0.32), 0.11, 0.0))


def cage(sc):
    for i in range(8):
        a = i * TAU / 8 + TAU / 16
        c, s = math.cos(a), math.sin(a)
        pts = [(1.88 * c, -1.9, 1.88 * s), (1.88 * c, 0.1, 1.88 * s), (1.55 * c, 1.15, 1.55 * s), (0.75 * c, 1.75, 0.75 * s),
               (0.0, 1.88, 0.0)]
        sc.add_all(sc.curve(pts, [0.12] * 5, steps=6))

    def ring_at(y, rad, th, dark):
        sc.add(sc.full(lambda X, Y, Z: ((np.sqrt(X * X + Z * Z) - rad) / th) ** 2 + ((Y - y) / th) ** 2 <= 1), dark=dark)
    ring_at(-1.82, 1.84, 0.16, True)
    ring_at(0.1, 1.86, 0.12, True)
    sc.add(sc.ell((0, 1.86, 0), (0.26, 0.14, 0.26)), dark=True)


# ==================================================================================================== signatures
def sig_phoenix_wing(sc):
    """Ember / Obsidian Phoenix: the bird of fire with both wings spread wide (flame-tongue feathers), crest and a
    three-streamer tail; flat-ish in XY, facing -Z"""
    wing = lambda X, Y, Z: np.abs(Z) <= 0.16
    sc.add(sc.ell((0, 0.05, 0), (0.42, 0.78, 0.38)))
    sc.add(sc.ell((0, 1.02, -0.06), (0.31, 0.3, 0.3)))
    sc.add(sc.cone((0, 1.0, -0.3), (0, 0.88, -0.66), 0.13, 0.0), dark=True)
    for x, tip in ((0.0, (0.0, 2.05, 0.18)), (0.26, (0.5, 1.85, 0.12)), (-0.26, (-0.5, 1.85, 0.12))):
        mid = ((x + tip[0]) / 2 * 0.7, 1.55, 0.05)
        sc.add_all(sc.curve([(x * 0.5, 1.2, 0.0), mid, tip], [0.13, 0.09, 0.02], steps=6))
    for side in (1, -1):
        arm = [(0.25 * side, 0.4, 0), (1.05 * side, 0.95, 0), (1.9 * side, 1.35, 0), (2.45 * side, 1.75, 0)]
        sc.add_all(sc.curve(arm, [0.24, 0.2, 0.15, 0.09], steps=8))
        n = 7
        for i in range(n):
            t = (i + 0.5) / n
            k = min(int(t * 3), 2)
            f = t * 3 - k
            p = _v(arm[k]) * (1 - f) + _v(arm[k + 1]) * f
            ang = math.radians(-100 + 125 * t)  # inner feathers hang down, the primaries sweep up and out
            L = 0.85 + 0.55 * t
            d = np.array([math.cos(ang) * side, math.sin(ang), 0.0])
            tip = p + d * L
            bend = p + d * L * 0.55 + np.array([0.0, 0.12, 0.0])  # a flame curl towards the tip
            sc.add_all(sc.curve([p, bend, tip], [0.2, 0.15, 0.025], steps=6), dark=(i % 2 == 1), where=wing)
    for x0, x1, dark in ((0.0, 0.0, False), (0.25, 0.75, True), (-0.25, -0.75, True)):
        sc.add_all(sc.curve([(x0 * 0.5, -0.55, 0.08), (x0 + (x1 - x0) * 0.3, -1.25, 0.12), (x1, -1.85, 0.08),
                             (x1 * 1.35, -2.05, 0.02)], [0.24, 0.17, 0.1, 0.02], steps=6), dark=dark, where=wing)


def sig_sun_disc(sc):
    """Sunbeam Bear: a golden sun-disc shield (domed boss, raised rim) with sixteen rays, facing -Z"""
    def disc(X, Y, Z):
        rho = np.sqrt(X * X + Y * Y)
        return (rho <= 1.55) & (Z <= 0.12) & (Z >= -0.12 - 0.22 * (1 - (rho / 1.55) ** 2))
    sc.add(sc.full(disc), dark=True)
    sc.add(sc.full(lambda X, Y, Z: ((np.sqrt(X * X + Y * Y) - 1.5) / 0.17) ** 2 + ((Z + 0.04) / 0.2) ** 2 <= 1))
    sc.add(sc.full(lambda X, Y, Z: ((np.sqrt(X * X + Y * Y) - 0.95) / 0.08) ** 2 + ((Z + 0.22) / 0.12) ** 2 <= 1))
    sc.add(sc.ell((0, 0, -0.26), (0.5, 0.5, 0.26)))
    for k in range(16):
        th = k * TAU / 16
        R, w, dark = (2.74, 0.27, False) if k % 2 == 0 else (2.2, 0.2, True)

        def ray(X, Y, Z, th=th, R=R, w=w):
            u = X * math.sin(th) + Y * math.cos(th)
            v = X * math.cos(th) - Y * math.sin(th)
            return (u >= 1.4) & (u <= R) & (np.abs(v) <= w * (R - u) / (R - 1.4)) & (np.abs(Z + 0.02) <= 0.11)
        sc.add(sc.full(ray), dark=dark)


def sig_wolf(sc):
    """Stormfang: a lightning storm-wolf mid-pounce (forelegs reaching, hind legs kicked back), jagged mane, facing -Z"""
    sc.add(sc.ell((0, 1.35, 0.15), (0.46, 0.48, 1.0)))
    sc.add(sc.ell((0, 1.42, -0.55), (0.53, 0.58, 0.6)))
    sc.add(sc.ell((0, 1.35, 0.85), (0.44, 0.44, 0.5)))
    sc.add(sc.cap((0, 1.6, -0.8), (0, 1.88, -1.22), 0.37, 0.31))
    sc.add(sc.ell((0, 1.96, -1.43), (0.4, 0.37, 0.42)))
    sc.add(sc.cap((0, 1.88, -1.72), (0, 1.8, -2.26), 0.21, 0.13))
    sc.add(sc.cap((0, 1.62, -1.62), (0, 1.56, -2.05), 0.13, 0.08), dark=True)  # jaw (a snarl gap at the front)
    for s in (1, -1):
        sc.add(sc.cone((0.2 * s, 2.18, -1.36), (0.27 * s, 2.68, -1.18), 0.16, 0.0))
        sc.add(sc.cone((0.3 * s, 1.86, -1.28), (0.52 * s, 1.72, -0.92), 0.12, 0.0))  # cheek ruff
        sc.paint(sc.ell((0.31 * s, 2.02, -1.62), (0.09, 0.05, 0.1)))  # a narrowed eye
    # legs: one foreleg reaching, the other just behind it; both hind legs kicked back
    for s, dz in ((1, 0.0), (-1, 0.3)):
        x = 0.28 * s
        sc.add_all([sc.cap((x, 1.15, -0.72 + dz), (x * 1.2, 0.74, -1.45 + dz), 0.17, 0.13),
                    sc.cap((x * 1.2, 0.74, -1.45 + dz), (x * 1.3, 0.44, -1.95 + dz), 0.13, 0.1),
                    sc.ell((x * 1.3, 0.4, -2.05 + dz), (0.12, 0.09, 0.17))], dark=True)
    for s, dz in ((1, 0.0), (-1, -0.25)):
        x = 0.3 * s
        sc.add(sc.ell((x, 1.2, 0.95 + dz), (0.19, 0.38, 0.32)))
        sc.add_all([sc.cap((x, 1.0, 1.05 + dz), (x * 1.2, 0.74, 1.68 + dz), 0.16, 0.12),
                    sc.cap((x * 1.2, 0.74, 1.68 + dz), (x * 1.3, 0.5, 2.18 + dz), 0.11, 0.08),
                    sc.ell((x * 1.3, 0.46, 2.27 + dz), (0.1, 0.08, 0.15))], dark=True)
    sc.add_all(sc.curve([(0, 1.6, 1.25), (0, 1.88, 1.72), (0, 1.98, 2.18), (0, 1.9, 2.5)], [0.18, 0.28, 0.23, 0.05]))
    # the storm mane: a zigzag ridge of spikes down the spine, and two on the tail
    for z, h in ((-1.0, 0.5), (-0.62, 0.42), (-0.25, 0.38), (0.12, 0.32), (0.5, 0.28), (1.85, 0.3), (2.2, 0.24)):
        base_y = 1.75 if z < 1.5 else 2.05
        sc.add(sc.cone((0, base_y, z), (0, base_y + h, z + 0.32), 0.15, 0.0))
    sc.paint(sc.full(lambda X, Y, Z: (Y < 1.0) & (np.abs(Z) < 1.2)))  # belly


def sig_black_sun(sc):
    """Eclipse Dragon: the black sun - a dark eclipse disc in a bright ring, a corona of sixteen swirling flame spikes;
    facing -Z"""
    sc.add(sc.full(lambda X, Y, Z: (np.sqrt(X * X + Y * Y) <= 1.8) & (np.abs(Z) <= 0.12)), dark=True)
    sc.add(sc.full(lambda X, Y, Z: ((np.sqrt(X * X + Y * Y) - 2.04) / 0.32) ** 2 + (Z / 0.28) ** 2 <= 1))
    sc.paint(sc.full(lambda X, Y, Z: np.sqrt(X * X + Y * Y) < 1.86))
    for k in range(16):
        R, w = (3.24, 0.15) if k % 2 == 0 else (2.82, 0.12)
        th0 = k * TAU / 16

        def spike(X, Y, Z, th0=th0, R=R, w=w):
            rho = np.sqrt(X * X + Y * Y)
            u = np.clip((rho - 2.2) / (R - 2.2), 0, 1)
            phi = np.arctan2(Y, X) - th0 - 0.45 * u  # swirl
            phi = np.mod(phi + math.pi, TAU) - math.pi
            return (rho >= 2.15) & (rho <= R) & (np.abs(phi) * rho <= w * 2.2 * (1 - u) + 0.03) & \
                (np.abs(Z) <= 0.14 * (1 - u) + 0.06)
        sc.add(sc.full(spike), dark=(k % 2 == 1))


def sig_cloud_dragon(sc):
    """Cloudy Dragon: a long cloud dragon spiralling upward, a lumpy cloud-puff body, a big head with antlers and
    whiskers looking forward (-Z)"""
    turns, n = 1.15, 40
    end = -math.pi / 2  # the neck ends at the front of the spiral
    pts, rs = [], []
    for i in range(n + 1):
        t = i / n
        a = end - TAU * turns * (1 - t)
        R = 1.2 - 0.25 * t
        pts.append(np.array([R * math.cos(a), -2.3 + 3.6 * t, R * math.sin(a)]))
        rs.append(0.07 + 0.28 * math.sin(min(1.0, t * 1.25) * math.pi / 2) ** 1.5)
    for i in range(n):
        sc.add(sc.cap(pts[i], pts[i + 1], rs[i], rs[i + 1]))
    for i in range(2, n - 1, 2):  # cloud puffs: big and small in turn, on the back and the flanks
        p = pts[i]
        out = np.array([p[0], 0.0, p[2]])
        out = out / max(np.linalg.norm(out), 1e-6)
        big = (i // 2) % 2 == 0
        r = rs[i] * (1.0 if big else 0.75)
        sc.add(sc.ell(p + out * rs[i] * (0.55 if big else -0.35) + np.array([0, rs[i] * 0.5, 0]), r))
    h = 1.3  # head scale
    H = pts[-1] + np.array([0.0, 0.5, -0.3])

    def o(x, y, z):
        return H + np.array([x, y, z]) * h
    sc.add(sc.cap(pts[-1], H, rs[-1], 0.36 * h))
    sc.add(sc.ell(H, (0.42 * h, 0.38 * h, 0.48 * h)))
    sc.add(sc.cap(o(0, -0.04, -0.32), o(0, -0.12, -0.86), 0.26 * h, 0.19 * h))
    sc.add(sc.ell(o(0, -0.06, -0.88), (0.22 * h, 0.15 * h, 0.12 * h)))
    sc.add(sc.cap(o(0, -0.32, -0.3), o(0, -0.4, -0.74), 0.16 * h, 0.1 * h), dark=True)  # lower jaw
    for s in (1, -1):
        sc.add_all(sc.curve([o(0.18 * s, 0.28, 0.08), o(0.34 * s, 0.68, 0.42), o(0.28 * s, 0.95, 0.78)],
                            [0.09 * h, 0.07 * h, 0.03 * h], steps=6), dark=True)
        sc.add(sc.cone(o(0.3 * s, 0.66, 0.38), o(0.6 * s, 0.82, 0.3), 0.06 * h, 0.0), dark=True)  # antler tine
        sc.add_all(sc.curve([o(0.17 * s, -0.08, -0.8), o(0.5 * s, -0.2, -0.78), o(0.82 * s, -0.08, -0.52)],
                            [0.06 * h, 0.06 * h, 0.04 * h], steps=6))  # whisker
        sc.add(sc.ell(o(0.3 * s, 0.1, -0.12), (0.13 * h, 0.11 * h, 0.13 * h)))  # brow puff
        sc.add(sc.ell(o(0.3 * s, 0.02, 0.32), (0.22 * h, 0.22 * h, 0.22 * h)))  # cheek mane puff
    sc.add(sc.ell(o(0, 0.25, 0.42), (0.28 * h, 0.26 * h, 0.28 * h)))  # mane puff
    sc.shade_dark = True


def sig_wish_star(sc):
    """Starlight Unicorn: a giant puffy wishing star with a three-ribbon comet tail sweeping down behind it, facing
    -Z"""
    R, ri, cy = 1.25, 0.56, 1.0

    def body(X, Y, Z):
        rho = np.sqrt(X * X + (Y - cy) ** 2) / R
        th = 0.3 * (1 - 0.68 * np.clip(rho, 0, 1))
        return star2d(X, Y - cy, R, ri) & (np.abs(Z) <= np.maximum(th, 0.07))
    sc.add(sc.full(body))
    sc.paint(sc.full(lambda X, Y, Z: ~star2d(X, Y - cy, R, ri, inset=0.13)))
    tails = (([(0.0, 0.55, 0.2), (0.32, -0.45, 0.3), (0.9, -1.45, 0.32), (1.45, -2.2, 0.26)], [0.36, 0.26, 0.15, 0.04], False),
             ([(-0.35, 0.5, 0.22), (-0.2, -0.45, 0.32), (0.25, -1.3, 0.3), (0.62, -1.8, 0.24)], [0.22, 0.17, 0.09, 0.03], True),
             ([(0.4, 0.45, 0.22), (0.85, -0.25, 0.3), (1.32, -0.9, 0.3), (1.62, -1.25, 0.24)], [0.2, 0.15, 0.08, 0.03], True))
    for pts, rs, dark in tails:
        sc.add_all(sc.curve(pts, rs, steps=8), dark=dark)
    for (x, y, z), s in (((0.62, -0.95, 0.32), 0.3), ((1.2, -1.85, 0.3), 0.24)):  # little sparkle stars on the tail
        sc.add(sc.full(lambda X, Y, Z, x=x, y=y, z=z, s=s: star2d(X - x, Y - y, s, s * 0.32, points=4) &
                       (np.abs(Z - z) <= 0.08)))


def sig_fox_orb(sc):
    """Phantom Kitsune: a fox-fire orb (kitsune-bi) - a round flame with a long hooked tail and two side flicks, a
    dark swirl streak"""
    sc.add(sc.ell((0, -0.42, 0), 0.5))
    sc.add_all(sc.curve([(0, -0.42, 0), (0.1, 0.08, 0.03), (-0.14, 0.48, 0.05), (0.04, 0.82, 0.05), (0.36, 0.98, 0.04),
                         (0.52, 0.84, 0.02)], [0.42, 0.28, 0.18, 0.11, 0.06, 0.025], steps=8))
    sc.add_all(sc.curve([(0.36, -0.3, 0.0), (0.6, 0.02, 0.02), (0.55, 0.34, 0.02)], [0.17, 0.1, 0.025], steps=6))
    sc.add_all(sc.curve([(-0.34, -0.26, 0.0), (-0.56, 0.0, 0.02), (-0.5, 0.24, 0.02)], [0.15, 0.09, 0.025], steps=6))
    sc.paint(sc.full(lambda X, Y, Z: np.mod(np.arctan2(Z, X) - Y * 4.5, TAU) < 0.95))


def sig_lava_spike(sc):
    """Magma Cub: a crooked, stepped magma spike with three smaller spikes at its foot; dark crust, bright lava
    cracks"""
    axis = [(0.0, -1.75), (0.12, 0.05), (-0.06, 1.0), (0.18, 1.75)]

    def main(X, Y, Z):
        t = np.clip((Y + 1.75) / 3.5, 0, 1)
        ys = np.array([p[1] for p in axis])
        cx = np.interp(Y, ys, [p[0] for p in axis])
        r = 0.74 * (1 - t) ** 1.05 * (1 - 0.1 * (np.floor(t * 7) % 2))
        ang = 0.4 + t * 1.3
        dx, dz = X - cx, Z
        a = dx * np.cos(ang) - dz * np.sin(ang)
        b = dx * np.sin(ang) + dz * np.cos(ang)
        sq = np.maximum(np.abs(a), np.abs(b)) * 0.92 + np.minimum(np.abs(a), np.abs(b)) * 0.38
        return (Y >= -1.75) & (Y <= 1.75) & (sq <= r)
    sc.add(sc.full(main), dark=True)
    for k in range(3):
        a = math.radians(25 + 120 * k)
        c, s = math.cos(a), math.sin(a)
        sc.add(sc.cone((0.42 * c, -1.75, 0.42 * s), (0.98 * c, 0.3 - 0.45 * k, 0.98 * s), 0.38, 0.0), dark=True)

    def cracks(X, Y, Z):
        th = np.arctan2(Z, X)
        ring = np.abs(np.mod(Y * 1.9 + 0.35 * np.sin(th * 3), 1.0) - 0.5) < 0.07
        seam = np.abs(np.sin(th * 2.5 + Y * 1.3)) < 0.12
        return ring | seam | (Y > 1.25)
    sc.paint(sc.full(cracks), dark=False)


def sig_glacier(sc):
    """Rime Wyrmling: a ring of glacier crystals rising around the target (hex prisms leaning out) on an icy base"""
    specs = [(0, 1.3, 2.9, 0.48), (45, 1.42, 2.1, 0.4), (90, 1.3, 3.3, 0.5), (135, 1.42, 2.0, 0.38),
             (180, 1.3, 2.7, 0.46), (225, 1.42, 2.3, 0.4), (270, 1.3, 3.1, 0.5), (315, 1.42, 1.9, 0.38)]
    y0 = -1.7
    for i, (deg, dist, h, r) in enumerate(specs):
        a = math.radians(deg + 10)
        out = np.array([math.cos(a), 0.0, math.sin(a)])
        lean = math.radians(11 + 4 * (i % 3))
        d = np.array([0.0, math.cos(lean), 0.0]) + out * math.sin(lean)
        base = np.array([0.0, y0, 0.0]) + out * dist
        u, v, dd = frame(d)
        tip = h + r * 1.6

        def crystal(X, Y, Z, base=base, u=u, v=v, dd=dd, h=h, r=r, tip=tip):
            px, py, pz = X - base[0], Y - base[1], Z - base[2]
            a_ = px * u[0] + py * u[1] + pz * u[2]
            b_ = px * v[0] + py * v[1] + pz * v[2]
            w = px * dd[0] + py * dd[1] + pz * dd[2]
            rr = np.where(w <= h, r, r * (tip - w) / (tip - h))
            return (w >= -0.3) & (w <= tip) & (hexr(a_, b_) <= rr) & (Y >= y0 - 0.25), facet(a_, b_, 6, 0.5)
        X, Y, Z = sc.xyz()
        m, f = crystal(X, Y, Z)
        sc.add((sc._full, m & (f == 0)))
        sc.add((sc._full, m & (f == 1)), dark=True)
    sc.add(sc.full(lambda X, Y, Z: ((np.sqrt(X * X + Z * Z) - 1.35) / 0.5) ** 2 + ((Y - y0) / 0.25) ** 2 <= 1), dark=True)


def sig_serpent(sc):
    """Hydralotl: a void serpent head rearing up on an S-neck - a broad wedge head, jaws wide open with fangs,
    axolotl-gill frills and a back crest; facing -Z"""
    neck = [(0, -2.25, 0.62), (0, -1.2, 0.95), (0, -0.1, 0.35), (0, 0.85, -0.05), (0, 1.5, -0.3)]
    sc.add_all(sc.curve(neck, [0.42, 0.38, 0.32, 0.28, 0.28], steps=10))
    sc.paint(sc.full(lambda X, Y, Z: (np.sin(Y * 11.0) > 0.86) & (Y < 1.25)))  # scale bands
    sc.add(sc.ell((0, 1.78, -0.6), (0.6, 0.36, 0.72)))
    sc.add(sc.cap((0, 1.74, -0.9), (0, 1.66, -1.55), 0.38, 0.24))
    sc.add(sc.cap((0, 1.36, -0.72), (0, 0.84, -1.3), 0.3, 0.17), dark=True)  # lower jaw, dropped open
    for s in (1, -1):
        sc.add(sc.cone((0.16 * s, 1.56, -1.3), (0.17 * s, 1.06, -1.4), 0.11, 0.0))  # fangs
        sc.add(sc.ell((0.4 * s, 2.02, -0.86), (0.17, 0.13, 0.26)))  # brow ridge
        sc.paint(sc.ell((0.5 * s, 1.88, -0.95), (0.1, 0.06, 0.1)))  # eye slit
        for j, (dy, dz, L) in enumerate(((0.36, 0.25, 0.85), (0.08, 0.36, 0.95), (-0.2, 0.32, 0.8))):
            p0 = np.array([0.5 * s, 1.78 + dy * 0.3, -0.36])
            p1 = p0 + np.array([0.55 * s, dy * 1.1, dz]) * (L / 0.7)
            sc.add(sc.cone(p0, p1, 0.14, 0.0), dark=(j == 1))
    for y, z in ((1.6, -0.05), (1.1, 0.05), (0.45, 0.35), (-0.15, 0.6), (-0.75, 0.98)):
        sc.add(sc.cone((0, y, z), (0, y + 0.28, z + 0.34), 0.13, 0.0))


SHAPES = {
    "orb": (orb, 0.125, 2.2), "crescent": (crescent, 0.1, 4.2), "spear": (spear, 0.075, 5.4), "spike": (spike, 0.1, 3.6),
    "ring": (ring, 0.1, 4.2), "shell": (shell, 0.25, 5.4), "beam": (beam, 0.125, 8.4), "shard": (shard, 0.075, 1.4),
    "chunk": (chunk, 0.08, 1.0), "star": (star, 0.075, 1.8), "root": (root, 0.1, 4.6, 0.93), "cage": (cage, 0.125, 4.4),
    "sig_phoenix_wing": (sig_phoenix_wing, 0.1, 6.6, 0.86), "sig_sun_disc": (sig_sun_disc, 0.1, 5.4),
    "sig_wolf": (sig_wolf, 0.1, 5.6), "sig_black_sun": (sig_black_sun, 0.12, 6.4),
    "sig_cloud_dragon": (sig_cloud_dragon, 0.12, 5.6), "sig_wish_star": (sig_wish_star, 0.1, 5.0),
    "sig_fox_orb": (sig_fox_orb, 0.075, 2.2), "sig_lava_spike": (sig_lava_spike, 0.1, 4.0),
    "sig_glacier": (sig_glacier, 0.15, 5.8, 0.95), "sig_serpent": (sig_serpent, 0.1, 5.2),
}


STRAY_VOXELS = 6  # islands up to this size are voxel crumbs of a thin tip (removed); bigger ones fail the build


def islands(occ):
    """the 26-connected voxel islands of occ (iterative flood fill by dilation), largest first"""
    left = occ.copy()
    out = []
    while left.any() and len(out) < 200:
        seed = np.zeros_like(left)
        seed[tuple(np.argwhere(left)[0])] = True
        n = 1
        while True:
            grown = seed.copy()
            for ax in range(3):  # 26-neighbourhood = three separable 1-voxel dilations
                g = grown.copy()
                g[tuple(slice(1, None) if i == ax else slice(None) for i in range(3))] |= \
                    grown[tuple(slice(None, -1) if i == ax else slice(None) for i in range(3))]
                g[tuple(slice(None, -1) if i == ax else slice(None) for i in range(3))] |= \
                    grown[tuple(slice(1, None) if i == ax else slice(None) for i in range(3))]
                grown = g
            seed = grown & left
            m = int(seed.sum())
            if m == n:
                break
            n = m
        left &= ~seed
        out.append(seed)
    return sorted(out, key=lambda m: -int(m.sum()))


@prop("vfx_cores")
def vfx_cores(entry, kit):
    from nvox.parts import Styles, add_cells
    from nvox.shade import shade
    a = entry.get("args") or {}
    name = a["shape"]
    fn, vs, ext = SHAPES[name][:3]
    sc = Sculpt(vs, ext, SHAPES[name][3] if len(SHAPES[name]) > 3 else 1.0)
    fn(sc)
    occ = sc.L != 0
    if getattr(sc, "shade_dark", False):
        # organic signature cores: the kit's own Voxel.Shade undersides + creases (no light part: one Core only)
        g = kit.grid(K=1.0, half=sc.half)
        g.kid("Core")
        g.L = np.zeros((2 * sc.half + 1,) * 3, np.int16)
        g.L[:sc.n, :sc.n, :sc.n] = occ.astype(np.int16)
        S = shade(g, default={"light": False})[:sc.n, :sc.n, :sc.n]
        sc.L[occ & (S < 0)] = 2
    isl = islands(occ)
    stray = isl[1:]
    big = [(int(m.sum()), [round(float(sc.r[int(i)]), 2) for i in np.argwhere(m).mean(0)])
           for m in stray if m.sum() > STRAY_VOXELS]
    if big:
        raise ValueError("%s: %d separate voxel islands (voxels, design centre) %s: a core must be one solid" % (
            entry["key"], len(big), big))
    for m_ in stray:  # a few voxels a thin tip left behind on the grid: dropped
        occ &= ~m_
        sc.L[m_] = 0
    idx = np.argwhere(occ)
    cells = {}
    for (i, j, k) in idx:
        cells[(int(i), int(j), int(k))] = "Core_Dark" if sc.L[i, j, k] == 2 else "Core"
    lo, hi = idx.min(0), idx.max(0)
    off = -(lo + hi) / 2.0 * vs  # voxel (i, j, k) is centred at i * vs: centre the bounds on the pivot
    m = kit.model(entry["key"], "vfx", vs=vs, K=1.0 / vs)
    made = add_cells(m, cells, Styles({"Core": CORE}), group="Core", naming="key", vs=vs, offset=tuple(off), used={})
    if [o.name for o in made] != ["Core"]:
        raise ValueError("%s: parts %s (a core is ONE part Core)" % (entry["key"], [o.name for o in made]))
    m.groups, m.attachments = {}, {}
    m.meta = {"pivot": "bounds centre; +Y up, -Z forward; %s studs at scale 1" % "x".join(
        "%g" % round(float(s), 3) for s in (hi - lo + 1) * vs), "shape": name, "tint": "MeshPart.Color (white Neon core)"}
    return m
