"""Shading: a vectorised port of Voxel.Shade (lighter tops, darker undersides and creases), per voxel.

Returns an int8 array S (same shape as grid.L): +1 light, 0 base, -1 dark, -2 deep crease (optional "AO" level),
only meaningful on exposed voxels.  Parameters per key (dict key -> opts) with Voxel.Shade's names:
    light_at (0.55)  dark_at (-0.35)  crease (0.22)  light/dark (True)  deep (None or an openness threshold)
Keys missing from `opts` and not in `skip` use `default`; keys in `skip` stay 0 (eyes, noses: flat accents).
The normal estimator looks `radius` voxels around each voxel (2 at the game's grain; scaled with K so a finer
grid gives the same smooth bands instead of speckle).
"""
import numpy as np

DEFAULT = dict(light_at=0.55, dark_at=-0.35, crease=0.22, light=True, dark=True, deep=None)

FACE6 = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
N26 = [(dx, dy, dz) for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1) if (dx, dy, dz) != (0, 0, 0)]


def _shift(a, o, fill):
    """b[p] = a[p + o] (out of range -> fill)."""
    b = np.full_like(a, fill)
    sl_dst, sl_src = [], []
    for d, n in zip(o, a.shape):
        if d > 0:
            sl_dst.append(slice(0, n - d)); sl_src.append(slice(d, n))
        elif d < 0:
            sl_dst.append(slice(-d, n)); sl_src.append(slice(0, n + d))
        else:
            sl_dst.append(slice(0, n)); sl_src.append(slice(0, n))
    b[tuple(sl_dst)] = a[tuple(sl_src)]
    return b


def shade(grid, opts=None, skip=(), default=None, radius=None, smooth=1, up=(0.0, 1.0, 0.0)):
    opts = opts or {}
    default = dict(DEFAULT, **(default or {}))
    L = grid.L
    S = np.zeros(L.shape, np.int8)
    b = grid.bounds()
    if not b:
        return S
    if radius is None:
        radius = int(min(4, max(2, round(2 * grid.K))))
    m = radius + 2
    h = grid.half
    x0, y0, z0 = max(b[0] + h - m, 0), max(b[1] + h - m, 0), max(b[2] + h - m, 0)
    x1, y1, z1 = min(b[3] + h + m + 1, L.shape[0]), min(b[4] + h + m + 1, L.shape[1]), min(b[5] + h + m + 1, L.shape[2])
    sub = L[x0:x1, y0:y1, z0:z1]
    occ = sub != 0
    empty = ~occ

    # per-key parameter tables
    nk = len(grid.keys)
    tab = {k: np.zeros(nk, float) for k in ("light_at", "dark_at", "crease")}
    use_l, use_d, can = np.zeros(nk, bool), np.zeros(nk, bool), np.zeros(nk, bool)
    deep = np.full(nk, -1.0)
    for i, key in enumerate(grid.keys):
        if key is None or key in skip:
            continue
        o = dict(default, **opts.get(key, {}))
        can[i] = True
        tab["light_at"][i], tab["dark_at"][i], tab["crease"][i] = o["light_at"], o["dark_at"], o["crease"]
        use_l[i], use_d[i] = o["light"], o["dark"]
        if o.get("deep") is not None:
            deep[i] = o["deep"]

    exposed = np.zeros_like(occ)
    for o in FACE6:
        exposed |= _shift(empty, o, True)
    surf = occ & exposed & can[sub]

    # normal estimate + openness over the neighbourhood
    nx = np.zeros(sub.shape); ny = np.zeros(sub.shape); nz = np.zeros(sub.shape); cnt = np.zeros(sub.shape)
    total = 0
    r2max = radius * radius + 0.1
    for dx in range(-radius, radius + 1):
        for dy in range(-radius, radius + 1):
            for dz in range(-radius, radius + 1):
                d2 = dx * dx + dy * dy + dz * dz
                if d2 == 0 or d2 > r2max:
                    continue
                total += 1
                e = _shift(empty, (dx, dy, dz), True)
                nx += e * (dx / d2); ny += e * (dy / d2); nz += e * (dz / d2)
                cnt += e
    nl = np.sqrt(nx * nx + ny * ny + nz * nz)
    upv = np.asarray(up, float) / np.linalg.norm(up)
    with np.errstate(invalid="ignore", divide="ignore"):
        d = np.where(nl > 1e-6, (nx * upv[0] + ny * upv[1] + nz * upv[2]) / np.maximum(nl, 1e-9), 0.0)
    openness = cnt / total
    sh = np.zeros(sub.shape, np.int8)
    la, da, cr = tab["light_at"][sub], tab["dark_at"][sub], tab["crease"][sub]
    sh[(d >= la) & use_l[sub]] = 1
    sh[(d <= da) & use_d[sub]] = -1
    sh[(openness <= cr) & use_d[sub]] = -1
    sh[~surf] = 0

    # smoothing (Voxel.Shade step 2): a voxel agreeing with < 2 same-key surface neighbours takes their majority
    for _ in range(smooth):
        cl = np.zeros(sub.shape, np.int16); c0 = np.zeros(sub.shape, np.int16); cd = np.zeros(sub.shape, np.int16)
        same = np.zeros(sub.shape, np.int16)
        for o in N26:
            nb_k = _shift(sub, o, 0)
            nb_s = _shift(sh, o, 0)
            nb_surf = _shift(surf, o, False)
            ok = nb_surf & (nb_k == sub)
            same += ok & (nb_s == sh)
            cl += ok & (nb_s > 0)
            c0 += ok & (nb_s == 0)
            cd += ok & (nb_s < 0)
        new = np.where(c0 >= np.maximum(cl, cd), 0, np.where(cl >= cd, 1, -1)).astype(np.int8)
        change = surf & (same < 2) & ((cl + c0 + cd) > 0)
        if not change.any():
            break
        sh = np.where(change, new, sh)

    # optional deep crease level (ambient-occlusion-like second dark shade)
    dp = deep[sub]
    sh[surf & (dp >= 0) & (openness <= dp) & (sh < 0)] = -2
    S[x0:x1, y0:y1, z0:z1] = sh
    return S
