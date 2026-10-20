"""Greedy surface mesher: only the OUTER faces of a voxel grid, coplanar same-label faces merged into big quads.

Input  F  int32 array (same shape / indexing as VoxelGrid.L): the FACE LABEL of each voxel (0 = no voxel).  A label
          stands for one (output object, vertex colour) pair, so faces only merge when they would look identical.
       opaque  bool array: voxels that hide their neighbours' faces (translucent voxels emit faces only towards empty
          space and hide nothing).
Output dict label -> list of quads; a quad = (4 corners in VOXEL coordinates (x, y, z), axis, sign), corners in
       counter-clockwise order seen from outside (right-hand rule: the normal points out of the model).
"""
import numpy as np


def _greedy2d(M):
    """Greedy rectangles over a 2D int array (0 = nothing). Yields (label, u0, v0, u1, v1) inclusive."""
    M = M.copy()
    H, W = M.shape
    rows = np.nonzero(M.any(axis=1))[0]
    for i in rows:
        row = M[i]
        j = 0
        while True:
            nzj = np.nonzero(row[j:])[0]
            if len(nzj) == 0:
                break
            j += int(nzj[0])
            lab = row[j]
            diff = np.nonzero(row[j:] != lab)[0]
            w = int(diff[0]) if len(diff) else W - j
            k = 1
            while i + k < H and np.all(M[i + k, j:j + w] == lab):
                k += 1
            M[i:i + k, j:j + w] = 0
            yield int(lab), i, j, i + k - 1, j + w - 1
            j += w
            if j >= W:
                break


def greedy_mesh(F, opaque, half):
    F = np.asarray(F)
    occ = F != 0
    nzs = np.nonzero(occ)
    out = {}
    if len(nzs[0]) == 0:
        return out
    lo = [int(a.min()) for a in nzs]
    hi = [int(a.max()) + 1 for a in nzs]
    # crop with a 1-voxel empty margin
    sl = tuple(slice(max(l - 1, 0), min(h + 1, n)) for l, h, n in zip(lo, hi, F.shape))
    base = [s.start for s in sl]
    Fc = F[sl]
    Oc = opaque[sl]
    Occ = Fc != 0
    for a in range(3):
        u, v = (a + 1) % 3, (a + 2) % 3
        for sign in (1, -1):
            # neighbour in direction sign along axis a
            nb_op = np.zeros_like(Oc)
            nb_occ = np.zeros_like(Occ)
            src = [slice(None)] * 3
            dst = [slice(None)] * 3
            n = Fc.shape[a]
            if sign > 0:
                dst[a], src[a] = slice(0, n - 1), slice(1, n)
            else:
                dst[a], src[a] = slice(1, n), slice(0, n - 1)
            nb_op[tuple(dst)] = Oc[tuple(src)]
            nb_occ[tuple(dst)] = Occ[tuple(src)]
            # a face shows where this voxel exists and the neighbour does not hide it; translucent voxels
            # (not opaque) only show towards empty space
            vis = Occ & ~nb_op & (Oc | ~nb_occ)
            lab = np.where(vis, Fc, 0)
            for s in range(lab.shape[a]):
                if a == 0:
                    M = lab[s, :, :]          # (y, z): u = y, v = z
                elif a == 1:
                    M = lab[:, s, :].T        # (z, x): u = z, v = x
                else:
                    M = lab[:, :, s]          # (x, y): u = x, v = y
                if not M.any():
                    continue
                for L, u0, v0, u1, v1 in _greedy2d(M):
                    pa = s + base[a] - half + 0.5 * sign
                    U0, U1 = u0 + base[u] - half - 0.5, u1 + base[u] - half + 0.5
                    V0, V1 = v0 + base[v] - half - 0.5, v1 + base[v] - half + 0.5
                    corners = []
                    for cu, cv in ((U0, V0), (U1, V0), (U1, V1), (U0, V1)):
                        p = [0.0, 0.0, 0.0]
                        p[a], p[u], p[v] = pa, cu, cv
                        corners.append(tuple(p))
                    if sign < 0:
                        corners.reverse()
                    out.setdefault(L, []).append((corners, a, sign))
    return out


def count_faces(F, opaque):
    """number of unit voxel faces that would be drawn without merging (for the report)."""
    occ = F != 0
    total = 0
    for a in range(3):
        for sign in (1, -1):
            nb = np.roll(opaque, -sign, axis=a)
            nbo = np.roll(occ, -sign, axis=a)
            total += int((occ & ~nb & (opaque | ~nbo)).sum())
    return total
