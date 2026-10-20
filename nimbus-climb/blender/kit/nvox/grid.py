"""VoxelGrid: a dense numpy port of shared/Voxel.lua's sculpting (same shape semantics, same Bias rule).

Coordinates (Roblox axes): +X = the model's right, +Y = up, -Z = forward (the face).  Voxel (x, y, z) is the unit
cube CENTRED on the integer point (x, y, z) in voxel units.  Shapes are given in DESIGN units (PetBuilder's 0.1-stud
units, or any unit the caller picks) and scaled by grid.K (voxels per design unit), exactly like PetBuilder's
scaled(): a model sculpted at K = 1 matches today's game voxels one to one; K = 1.65 is the same shape with
1.65x finer voxels.  Round shapes get Bias = 0.25 VOXEL (not design unit), like Voxel.lua.

Ops: "add" (default), "carve", "paint" (+ only = key | {keys}, keep = only fill empty voxels, pattern =
fn(xd, yd, zd, curKeys) -> array of key names / None per voxel, vectorised: design coordinates).
"""
import math

import numpy as np

DEFAULT_BIAS = {"ellipsoid": 0.25, "capsule": 0.25, "cone": 0.25, "torus": 0.25, "curve": 0.25, "roundbox": 0.25, "box": 0.0}


def angles(rx=0.0, ry=0.0, rz=0.0):
    """Roblox CFrame.Angles(rx, ry, rz) rotation matrix (= Rx * Ry * Rz)."""
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rx @ Ry @ Rz


def _v3(v):
    if isinstance(v, (int, float)):
        return np.array([v, v, v], float)
    return np.array([float(v[0]), float(v[1]), float(v[2])])


class VoxelGrid:
    def __init__(self, K=1.0, half=96, name="grid"):
        self.K = float(K)
        self.half = int(half)  # voxel coords -half..half on every axis (odd size: exact X mirror)
        n = 2 * self.half + 1
        self.L = np.zeros((n, n, n), np.int16)  # key id per voxel (0 = empty), index [x+half, y+half, z+half]
        self.keys = [None]
        self.ids = {}
        self.name = name

    # ------------------------------------------------------------------ keys
    def kid(self, key):
        if key is None:
            return 0
        i = self.ids.get(key)
        if i is None:
            i = len(self.keys)
            self.keys.append(key)
            self.ids[key] = i
        return i

    def key_of(self, i):
        return self.keys[i]

    def _only_ids(self, only):
        if only is None:
            return None
        if isinstance(only, str):
            only = [only]
        return np.array([self.kid(k) for k in only], np.int16)

    # ------------------------------------------------------------------ voxel access (voxel coordinates)
    def get(self, x, y, z):
        h = self.half
        if -h <= x <= h and -h <= y <= h and -h <= z <= h:
            return self.keys[self.L[x + h, y + h, z + h]]
        return None

    def set(self, x, y, z, key):
        h = self.half
        if -h <= x <= h and -h <= y <= h and -h <= z <= h:
            self.L[x + h, y + h, z + h] = self.kid(key)

    def front_z(self, x, y):
        """z of the frontmost (most -Z) voxel of the column (x, y), or None."""
        h = self.half
        if not (-h <= x <= h and -h <= y <= h):
            return None
        col = np.nonzero(self.L[x + h, y + h, :])[0]
        return int(col[0]) - h if len(col) else None

    def count(self):
        return int(np.count_nonzero(self.L))

    def bounds(self):
        nz = np.nonzero(self.L)
        if len(nz[0]) == 0:
            return None
        h = self.half
        return (int(nz[0].min()) - h, int(nz[1].min()) - h, int(nz[2].min()) - h,
                int(nz[0].max()) - h, int(nz[1].max()) - h, int(nz[2].max()) - h)

    def vx(self, d):
        """design coordinate -> voxel index (PetBuilder vx)."""
        return int(math.floor(d * self.K + 0.5))

    def remap(self, mapping):
        for a, b in mapping.items():
            if a in self.ids:
                self.L[self.L == self.ids[a]] = self.kid(b)

    def mirror_x(self):
        """A new grid holding this grid mirrored in X (x -> -x)."""
        g = VoxelGrid(self.K, self.half, self.name + "_mirror")
        g.keys, g.ids = list(self.keys), dict(self.ids)
        g.L = self.L[::-1, :, :].copy()
        return g

    def upsample(self, f, K=None):
        """every voxel -> an f x f x f block (StormCloud-style chunky sub-grids)."""
        g = VoxelGrid(K or self.K * f, self.half * f + f, self.name)
        g.keys, g.ids = list(self.keys), dict(self.ids)
        b = self.bounds()
        if not b:
            return g
        x0, y0, z0, x1, y1, z1 = b
        h, H = self.half, g.half
        sub = self.L[x0 + h:x1 + h + 1, y0 + h:y1 + h + 1, z0 + h:z1 + h + 1]
        big = sub.repeat(f, 0).repeat(f, 1).repeat(f, 2)
        g.L[x0 * f + H:x0 * f + H + big.shape[0], y0 * f + H:y0 * f + H + big.shape[1], z0 * f + H:z0 * f + H + big.shape[2]] = big
        return g

    def fill_pockets(self, skip_near=(), pit_passes=2):
        """Fill (1) empty cells enclosed by the model (never visible, they only cost triangles) and (2) one-voxel
        pits (an empty cell with >= 5 of its 6 neighbours filled: they render as black specks), unless a neighbour is
        a flat accent key (carved eyes / mouths / nostrils are pits on purpose). Filled with the most common
        neighbour key."""
        b = self.bounds()
        if not b:
            return 0
        h = self.half
        sl = tuple(slice(max(lo + h - 1, 0), min(hi + h + 2, n)) for lo, hi, n in zip(b[:3], b[3:], self.L.shape))
        sub = self.L[sl]
        empty = sub == 0
        # flood fill the outside from the crop border (6-connected)
        out = np.zeros_like(empty)
        out[0, :, :] = empty[0, :, :]; out[-1, :, :] = empty[-1, :, :]
        out[:, 0, :] |= empty[:, 0, :]; out[:, -1, :] |= empty[:, -1, :]
        out[:, :, 0] |= empty[:, :, 0]; out[:, :, -1] |= empty[:, :, -1]
        while True:
            grow = out.copy()
            grow[1:] |= out[:-1]; grow[:-1] |= out[1:]
            grow[:, 1:] |= out[:, :-1]; grow[:, :-1] |= out[:, 1:]
            grow[:, :, 1:] |= out[:, :, :-1]; grow[:, :, :-1] |= out[:, :, 1:]
            grow &= empty
            if (grow == out).all():
                break
            out = grow
        skip_ids = [self.ids[k] for k in skip_near if k in self.ids]
        filled = 0
        targets = empty & ~out
        for p in range(pit_passes + 1):
            if p > 0:
                occ = sub != 0
                n = np.zeros(sub.shape, np.int8)
                pairs = np.zeros(sub.shape, np.int8)
                for ax in range(3):
                    a, b = np.roll(occ, 1, axis=ax), np.roll(occ, -1, axis=ax)
                    n += a.astype(np.int8) + b
                    pairs += a & b
                # a pit (>= 5 neighbours) or a tunnel (walls on both sides along 2 axes): dark specks, never wanted
                targets = (sub == 0) & ((n >= 5) | (pairs >= 2))
            idx = np.argwhere(targets)
            for (i, j, k) in idx:
                nb = []
                for di, dj, dk in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                    ii, jj, kk = i + di, j + dj, k + dk
                    if 0 <= ii < sub.shape[0] and 0 <= jj < sub.shape[1] and 0 <= kk < sub.shape[2] and sub[ii, jj, kk]:
                        nb.append(int(sub[ii, jj, kk]))
                if not nb or any(v in skip_ids for v in nb):
                    continue
                sub[i, j, k] = max(set(nb), key=nb.count)
                filled += 1
        return filled

    # ------------------------------------------------------------------ core writer
    def _write(self, box, inside_fn, key, op="add", only=None, keep=False, pattern=None):
        """box = voxel AABB (x0, y0, z0, x1, y1, z1) floats; inside_fn(X, Y, Z) -> bool array (voxel coords)."""
        h = self.half
        x0 = max(int(math.ceil(box[0] - 1e-6)), -h)
        y0 = max(int(math.ceil(box[1] - 1e-6)), -h)
        z0 = max(int(math.ceil(box[2] - 1e-6)), -h)
        x1 = min(int(math.floor(box[3] + 1e-6)), h)
        y1 = min(int(math.floor(box[4] + 1e-6)), h)
        z1 = min(int(math.floor(box[5] + 1e-6)), h)
        if x0 > x1 or y0 > y1 or z0 > z1:
            return 0
        X, Y, Z = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1), np.arange(z0, z1 + 1), indexing="ij")
        m = inside_fn(X.astype(float), Y.astype(float), Z.astype(float))
        sub = self.L[x0 + h:x1 + h + 1, y0 + h:y1 + h + 1, z0 + h:z1 + h + 1]
        only_ids = self._only_ids(only)
        if op == "carve":
            if only_ids is not None:
                m &= np.isin(sub, only_ids)
            else:
                m &= sub != 0
            sub[m] = 0
            return int(m.sum())
        if op == "paint":
            m &= sub != 0
            if only_ids is not None:
                m &= np.isin(sub, only_ids)
        elif keep:
            m &= sub == 0
        if pattern is not None:
            idx = np.nonzero(m)
            K = self.K
            cur = [self.keys[i] for i in sub[idx]]
            res = pattern(X[idx] / K, Y[idx] / K, Z[idx] / K, cur)
            keep_mask = np.array([r is not False for r in res], bool)
            vals = np.array([self.kid(key if (r is None or r is False) else r) for r in res], np.int16)
            sel = tuple(a[keep_mask] for a in idx)
            sub[sel] = vals[keep_mask]
            return int(keep_mask.sum())
        sub[m] = self.kid(key)
        return int(m.sum())

    # ------------------------------------------------------------------ shapes (design units)
    def shape(self, kind, key=None, op="add", only=None, keep=False, pattern=None, rot=None, pivot=None, bias=None, **p):
        kind = kind.lower()
        K = self.K
        b = DEFAULT_BIAS.get(kind, 0.0) if bias is None else bias
        R = None if rot is None else np.asarray(rot, float)
        if R is not None and np.allclose(R, np.eye(3)):
            R = None
        W = dict(key=key, op=op, only=only, keep=keep, pattern=pattern)

        if kind == "ellipsoid":
            c = _v3(p["center"]) * K
            r = np.maximum(_v3(p["radius"]) * K, 0.01) + b
            pv = c if pivot is None else _v3(pivot) * K
            if R is not None:
                wc = pv + R @ (c - pv)
                e = np.sqrt(((R * r[None, :]) ** 2).sum(1))
                box = (*(wc - e), *(wc + e))
            else:
                box = (*(c - r), *(c + r))
            inv = 1.0 / (r * r)

            def inside(X, Y, Z):
                if R is not None:
                    dX, dY, dZ = X - pv[0], Y - pv[1], Z - pv[2]
                    lx = pv[0] + R[0, 0] * dX + R[1, 0] * dY + R[2, 0] * dZ
                    ly = pv[1] + R[0, 1] * dX + R[1, 1] * dY + R[2, 1] * dZ
                    lz = pv[2] + R[0, 2] * dX + R[1, 2] * dY + R[2, 2] * dZ
                else:
                    lx, ly, lz = X, Y, Z
                return (lx - c[0]) ** 2 * inv[0] + (ly - c[1]) ** 2 * inv[1] + (lz - c[2]) ** 2 * inv[2] <= 1
            return self._write(box, inside, **W)

        if kind in ("box", "roundbox"):
            c = _v3(p["center"]) * K
            s = _v3(p["size"]) * K
            hs = s * 0.5
            pv = c if pivot is None else _v3(pivot) * K
            if kind == "box":
                lim = hs + b - 1e-4
                ext = lim
            else:
                rr = max(0.0, min(float(p.get("round", 1.0)) * K, *hs))
                inner = hs - rr
                ext = hs + b
            if R is not None:
                wc = pv + R @ (c - pv)
                e = np.abs(R) @ ext
                box = (*(wc - e), *(wc + e))
            else:
                box = (*(c - ext), *(c + ext))

            def inside(X, Y, Z):
                if R is not None:
                    dX, dY, dZ = X - pv[0], Y - pv[1], Z - pv[2]
                    lx = pv[0] + R[0, 0] * dX + R[1, 0] * dY + R[2, 0] * dZ
                    ly = pv[1] + R[0, 1] * dX + R[1, 1] * dY + R[2, 1] * dZ
                    lz = pv[2] + R[0, 2] * dX + R[1, 2] * dY + R[2, 2] * dZ
                else:
                    lx, ly, lz = X, Y, Z
                if kind == "box":
                    return (np.abs(lx - c[0]) <= lim[0]) & (np.abs(ly - c[1]) <= lim[1]) & (np.abs(lz - c[2]) <= lim[2])
                qx, qy, qz = np.abs(lx - c[0]) - inner[0], np.abs(ly - c[1]) - inner[1], np.abs(lz - c[2]) - inner[2]
                d = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2 + np.maximum(qz, 0) ** 2) + np.minimum(np.maximum(np.maximum(qx, qy), qz), 0)
                return d <= rr + b - 1e-4
            return self._write(box, inside, **W)

        if kind == "torus":
            c = _v3(p["center"]) * K
            ring = float(p.get("radius", 4)) * K
            th = float(p.get("thickness", 1)) * K
            thB = float(p.get("thicknessB", p.get("thickness", 1))) * K
            arc = p.get("arc")
            pv = c if pivot is None else _v3(pivot) * K
            tm = max(th, thB) + b
            ext = np.array([ring + tm, tm, ring + tm])
            if R is not None:
                wc = pv + R @ (c - pv)
                e = np.abs(R) @ ext
                box = (*(wc - e), *(wc + e))
            else:
                box = (*(c - ext), *(c + ext))

            def inside(X, Y, Z):
                if R is not None:
                    dX, dY, dZ = X - pv[0], Y - pv[1], Z - pv[2]
                    lx = pv[0] + R[0, 0] * dX + R[1, 0] * dY + R[2, 0] * dZ
                    ly = pv[1] + R[0, 1] * dX + R[1, 1] * dY + R[2, 1] * dZ
                    lz = pv[2] + R[0, 2] * dX + R[1, 2] * dY + R[2, 2] * dZ
                else:
                    lx, ly, lz = X, Y, Z
                dx, dy, dz = lx - c[0], ly - c[1], lz - c[2]
                u = 0.0
                ok = np.ones_like(dx, bool)
                if arc is not None:
                    ang = np.arctan2(dz, dx)
                    rel = np.mod(ang - arc[0], 2 * math.pi)
                    span = arc[1] - arc[0]
                    ok = rel <= span + 1e-9
                    u = rel / span if span > 1e-9 else 0.0
                q = np.sqrt(dx * dx + dz * dz) - ring
                t = th + (thB - th) * u + b
                return ok & (q * q + dy * dy <= t * t)
            return self._write(box, inside, **W)

        if kind == "cone":
            a = _v3(p["a"]) * K
            bb = _v3(p["b"]) * K
            pv = a if pivot is None else _v3(pivot) * K
            if R is not None:
                a, bb = pv + R @ (a - pv), pv + R @ (bb - pv)
            ra = float(p.get("r", 2)) * K
            rb = float(p.get("rb", 0) or 0) * K
            ab = bb - a
            l2 = float(ab @ ab)
            if l2 < 1e-9:
                return 0
            rm = max(ra, rb) + b
            box = (*(np.minimum(a, bb) - rm), *(np.maximum(a, bb) + rm))

            def inside(X, Y, Z):
                px, py, pz = X - a[0], Y - a[1], Z - a[2]
                t = (px * ab[0] + py * ab[1] + pz * ab[2]) / l2
                qx, qy, qz = px - ab[0] * t, py - ab[1] * t, pz - ab[2] * t
                r = ra + (rb - ra) * t + b
                return (t >= -1e-6) & (t <= 1 + 1e-6) & (qx * qx + qy * qy + qz * qz <= r * r)
            return self._write(box, inside, **W)

        if kind == "capsule":
            a = _v3(p["a"]) * K
            bb = _v3(p["b"]) * K
            pv = a if pivot is None else _v3(pivot) * K
            if R is not None:
                a, bb = pv + R @ (a - pv), pv + R @ (bb - pv)
            ra = float(p.get("r", 1)) * K
            rb = float(p["rb"]) * K if p.get("rb") is not None else ra
            return self._capsule(a, bb, ra, rb, b, W)

        if kind == "curve":
            pts = [_v3(q) * K for q in p["points"]]
            pv = pts[0] if pivot is None else _v3(pivot) * K
            if R is not None:
                pts = [pv + R @ (q - pv) for q in pts]
            n = len(pts)
            r0 = float(p.get("r", 1)) * K
            r1 = float(p["rb"]) * K if p.get("rb") is not None else r0
            radii = p.get("radii")
            if radii:
                rs = [float(x) * K for x in radii]
            else:
                rs = [r0 + (r1 - r0) * i / (n - 1) if n > 1 else r0 for i in range(n)]
            steps = max(1, int(p.get("steps", 6)))
            sp, sr = _curve_samples(pts, rs, steps, p.get("smooth", True))
            total = 0
            if len(sp) == 1:
                return self._capsule(sp[0], sp[0], sr[0], sr[0], b, W)
            for i in range(len(sp) - 1):
                total += self._capsule(sp[i], sp[i + 1], sr[i], sr[i + 1], b, W)
            return total
        raise ValueError("unknown shape kind " + kind)

    def _capsule(self, a, bb, ra, rb, bias, W):
        ab = bb - a
        l2 = float(ab @ ab)
        rm = max(ra, rb) + bias
        box = (*(np.minimum(a, bb) - rm), *(np.maximum(a, bb) + rm))
        dr = rb - ra

        def inside(X, Y, Z):
            px, py, pz = X - a[0], Y - a[1], Z - a[2]
            if l2 > 1e-9:
                t = np.clip((px * ab[0] + py * ab[1] + pz * ab[2]) / l2, 0, 1)
            else:
                t = np.zeros_like(px)
            qx, qy, qz = px - ab[0] * t, py - ab[1] * t, pz - ab[2] * t
            r = ra + dr * t + bias
            return qx * qx + qy * qy + qz * qz <= r * r
        return self._write(box, inside, **W)

    # PetBuilder-style shorthands ------------------------------------------------------------------------------
    def ell(self, key, c, r, **kw):
        return self.shape("ellipsoid", key, center=c, radius=r, **kw)

    def cap(self, key, a, b, r, rb=None, **kw):
        return self.shape("capsule", key, a=a, b=b, r=r, rb=rb, **kw)

    def cone(self, key, a, b, r, rb=0, **kw):
        return self.shape("cone", key, a=a, b=b, r=r, rb=rb, **kw)

    def curve(self, key, pts, r, rb=None, **kw):
        return self.shape("curve", key, points=pts, r=r, rb=rb, **kw)

    def box(self, key, c, size, **kw):
        return self.shape("box", key, center=c, size=size, **kw)

    def rbox(self, key, c, size, round=1.0, **kw):
        return self.shape("roundbox", key, center=c, size=size, round=round, **kw)

    def torus(self, key, c, radius, thickness, **kw):
        return self.shape("torus", key, center=c, radius=radius, thickness=thickness, **kw)

    def paint(self, key, kind, only=None, **p):
        return self.shape(kind, key, op="paint", only=only, **p)

    def carve(self, kind, only=None, **p):
        return self.shape(kind, None, op="carve", only=only, **p)


def _curve_samples(pts, radii, steps, smooth):
    n = len(pts)
    if n == 1 or not smooth:
        return list(pts), list(radii)
    outP, outR = [], []
    for i in range(n - 1):
        p0, p1, p2, p3 = pts[max(0, i - 1)], pts[i], pts[i + 1], pts[min(n - 1, i + 2)]
        r1, r2 = radii[i], radii[i + 1]
        for s in range(0 if i == 0 else 1, steps + 1):
            t = s / steps
            t2, t3 = t * t, t * t * t
            a = -0.5 * t3 + t2 - 0.5 * t
            b = 1.5 * t3 - 2.5 * t2 + 1
            c = -1.5 * t3 + 2 * t2 + 0.5 * t
            d = 0.5 * t3 - 0.5 * t2
            outP.append(a * p0 + b * p1 + c * p2 + d * p3)
            outR.append(r1 + (r2 - r1) * t)
    return outP, outR
