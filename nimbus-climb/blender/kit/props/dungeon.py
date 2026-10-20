"""Designed dungeon pieces (wave 2 art-arenadungeon; catalog blender/catalog/arenadungeon.json).  The baked pieces
(walls, floors, pillars, torches, chests, crates, stalagmites, door frames) come from props/arena.py ("ad_baked");
these two have no Part build worth copying:

  * "ad_rock"   dungeon_rock_<1..3>: a real voxel cave rock (the Part build is one tilted block) - a seeded cluster of
                faceted lumps, strata, a juicy moss cap, and on shapes 2 / 3 a little crystal cluster (the cute dungeon's
                lilac / cyan crystals).  Nominal size 4 studs; DungeonBuilder tags it upright at the block's foot,
                scaled by the block's volume (ML_Scale); the rock body is tinted with the block's own colour
                (ML_Primary), moss and crystals keep their colours.
  * "ad_crack"  dungeon_crack: a jagged floor crack 4 studs long (one 0.125-stud layer), scaled by the crack's length.

Pivot: the rock's foot centre (y 0 = the ground); the crack's centre.  No LayoutSig (designed pieces).
"""
import math

import numpy as np

from props import prop


def _pseudo_raster(cells, vs, names):
    """a props.arena_style.Raster filled from {(i, j, k): (name, rgb)} cells (i, j, k = cell indices, cell centre at
    (i + 0.5) * vs ...); one pseudo box per name spans the whole shape so the family detail passes work"""
    from props import arena_style as AS
    idx = np.array(list(cells.keys()), int)
    lo, hi = idx.min(0), idx.max(0) + 1
    boxes = []
    for nm in names:
        c = (lo + hi) / 2.0 * vs
        boxes.append({"cls": "Part", "shape": "Block", "pos": c, "R": np.eye(3), "size": (hi - lo) * vs,
                      "rgb": (255, 255, 255), "mat": "SmoothPlastic", "tr": 0.0, "name": nm, "parent": ""})
    R = AS.Raster(boxes, vs, align=False, offy=0.0)
    R.off = np.zeros(3)
    R.i0 = lo - 2
    R.shape = tuple(int(x) for x in (hi - lo + 4))
    R.col = np.zeros(R.shape, np.int64)
    R.pid = np.full(R.shape, -1, np.int32)
    R.glass = np.zeros(R.shape, np.int16)
    for (i, j, k), (nm, rgb) in cells.items():
        a = (i - R.i0[0], j - R.i0[1], k - R.i0[2])
        R.col[a] = ((rgb[0] << 16) | (rgb[1] << 8) | rgb[2]) + 1
        R.pid[a] = names.index(nm)
    return R


def _mesh(m, R, tints, budget):
    from props import arena_style as AS
    tries = []
    for level in (3, 2, 1, 0):
        m.objects.clear()
        D = AS.Detail(R, level)
        D.run()
        tmask = {}
        for nm, recipe in tints.items():
            ids = [i for i, b in enumerate(R.boxes) if b["name"] == nm]
            tmask[nm] = (np.isin(R.pid, ids), recipe)
        AS.mesh_all(m, R, D, solid_name="Fixed", tint_mask=tmask)
        tries.append((level, m.tris()))
        if m.tris() <= budget:
            break
    return tries


def _h(*v):
    from props.arena_style import _hash
    return _hash(*v)


@prop("ad_rock")
def ad_rock(entry, kit):
    a = entry.get("args") or {}
    shape = int(a.get("shape", 1))
    vs = float(a.get("vs", 0.25))
    m = kit.model(entry["key"], "prop", vs=vs, K=1.0)
    rad = 2.0 / vs  # nominal radius in cells (4 studs across)
    # 3-4 lumps: (cx, cy, cz, rx, ry, rz) in units of rad; seeded per shape
    lumps = [(0.0, 0.5, 0.0, 0.95, 0.62, 0.85)]
    for i in range(2 + (shape % 2)):
        ang = _h(shape, i, 1) * 2 * math.pi
        d = 0.35 + 0.25 * _h(shape, i, 2)
        lumps.append((math.cos(ang) * d, 0.35 + 0.3 * _h(shape, i, 3), math.sin(ang) * d,
                      0.45 + 0.25 * _h(shape, i, 4), 0.5 + 0.35 * _h(shape, i, 5), 0.45 + 0.25 * _h(shape, i, 6)))
    if shape == 3:
        lumps.append((0.15, 1.0, -0.1, 0.4, 0.55, 0.4))  # a taller peak
    n = int(math.ceil(rad * 1.6))
    cells = {}
    white = (255, 255, 255)
    for i in range(-n, n):
        for k in range(-n, n):
            for j in range(0, int(rad * 2.4)):
                x, y, z = (i + 0.5) / rad, (j + 0.5) / rad, (k + 0.5) / rad
                inside = False
                for (cx, cy, cz, rx, ry, rz) in lumps:
                    # faceted (p = 1.6 super-ellipsoid on 2-cell blocks): chunky, cute, still a rock
                    qx = (math.floor((x - cx) * rad / 2) * 2 + 1) / rad
                    qy = (math.floor((y - cy) * rad / 2) * 2 + 1) / rad
                    qz = (math.floor((z - cz) * rad / 2) * 2 + 1) / rad
                    if (abs(qx) / rx) ** 1.7 + (abs(qy) / ry) ** 1.7 + (abs(qz) / rz) ** 1.7 <= 1.0:
                        inside = True
                        break
                if inside:
                    cells[(i, j, k)] = ("Rock", white)
    # moss on the top skin (fixed juicy green), crystals on shapes 2 / 3
    top = {}
    for (i, j, k) in cells:
        if (i, j + 1, k) not in cells:
            top[(i, k)] = max(top.get((i, k), -1), j)
    moss = (110, 200, 120)
    for (i, k), j in top.items():
        if j >= rad * 0.55 and _h(i // 3, k // 3, shape, 9) < 0.55:
            cells[(i, j, k)] = ("Moss", moss)
            if _h(i, k, shape, 10) < 0.2:
                cells[(i, j + 1, k)] = ("Moss", (140, 222, 140))
    if shape in (2, 3):
        cols = {2: [(186, 150, 255), (230, 210, 255)], 3: [(120, 226, 240), (210, 250, 255)]}[shape]
        best = max(top.items(), key=lambda kv: (kv[1], -abs(kv[0][0]) - abs(kv[0][1])))
        (bi, bk), bj = best
        for c, (dx, dz, h) in enumerate([(0, 0, 6), (2, 1, 4), (-1, 2, 3), (1, -2, 3)]):
            for t in range(h):
                w = 1 if t < h - 1 else 0
                for ox in range(-w, w + 1):
                    for oz in range(-w, w + 1):
                        if abs(ox) + abs(oz) <= w:
                            cells[(bi + dx + ox, bj + 1 + t, bk + dz + oz)] = ("Crystal", cols[1] if t >= h - 2 else cols[0])
    R = _pseudo_raster(cells, vs, ["Rock", "Moss", "Crystal"])
    tries = _mesh(m, R, {"Rock": "Primary"}, int(a.get("budget", 1800)))
    m.groups, m.attachments = {}, {}
    m.meta = {"source": "designed voxel rock %d" % shape, "pivot": "foot centre", "tries": tries,
              "previewLook": {"Primary": [156, 146, 196]}}
    return m


@prop("ad_crack")
def ad_crack(entry, kit):
    a = entry.get("args") or {}
    vs = float(a.get("vs", 0.125))
    m = kit.model(entry["key"], "prop", vs=vs, K=1.0)
    L = int(round(4.0 / vs))
    cells = {}
    col = (122, 112, 172)
    dark = (100, 90, 150)
    z = 0
    for i in range(-L // 2, L // 2):
        # a jagged path: steps sideways every few cells, wider in the middle, two little branches
        if _h(i, 3) < 0.35:
            z += 1 if _h(i, 4) < 0.5 else -1
            z = max(-2, min(2, z))
        t = 1.0 - abs(i) / (L / 2.0)
        w = 1 if t > 0.45 else 0
        for dz in range(-w, w + 1):
            cells[(i, 0, z + dz)] = ("Crack", dark if dz == 0 else col)
        if i in (-L // 5, L // 4):
            for s in range(1, 4):
                cells[(i + s, 0, z + s * (1 if i > 0 else -1))] = ("Crack", col)
    # one layer centred on y 0 (the Part is 0.12 thick around its centre)
    shifted = {}
    for (i, j, k), v in cells.items():
        shifted[(i, j, k)] = v
    R = _pseudo_raster(shifted, vs, ["Crack"])
    R.off = np.array([0.0, -vs / 2, 0.0])
    tries = _mesh(m, R, {}, int(a.get("budget", 600)))
    m.groups, m.attachments = {}, {}
    m.meta = {"source": "designed floor crack", "pivot": "centre", "tries": tries}
    return m


@prop("ad_stalagmite")
def ad_stalagmite(entry, kit):
    """dungeon_stalagmite: a stepped voxel cone 4 studs tall (DungeonBuilder scales it by h / 4), lilac rock strata,
    a lighter tip and a few moss crumbs at its foot.  Pivot = the foot centre on the floor."""
    a = entry.get("args") or {}
    vs = float(a.get("vs", 0.25))
    m = kit.model(entry["key"], "prop", vs=vs, K=1.0)
    H = int(round(4.0 / vs))
    cells = {}
    rock, dark, light = (156, 146, 196), (124, 114, 170), (198, 190, 236)
    for j in range(H):
        t = j / float(H)
        tq = (j // 2) * 2 / float(H)  # terraces of 2 cells: tidy steps, not scales
        r = (1.35 * (1.0 - tq) ** 0.85 + 0.12) / vs
        n = int(math.ceil(r)) + 1
        for i in range(-n, n + 1):
            for k in range(-n, n + 1):
                x, z = i + 0.5, k + 0.5
                # 8-sided-ish footprint with a little wobble per layer
                wob = 0.0
                if max(abs(x), abs(z)) * 0.83 + min(abs(x), abs(z)) * 0.45 <= r + wob:
                    band = (j // 2) % 3
                    col = light if t > 0.82 else (dark if band == 0 else rock)
                    cells[(i, j, k)] = ("Stone", col)
    moss = (110, 200, 120)
    for (i, j, k), v in list(cells.items()):
        if j == 0 and (i + 1, j, k) not in cells and _h(i, k, 5) < 0.5:
            cells[(i + 1, 0, k)] = ("Moss", moss)
    R = _pseudo_raster(cells, vs, ["Stone", "Moss"])
    tries = _mesh(m, R, {}, int(a.get("budget", 1800)))
    m.groups, m.attachments = {}, {}
    m.meta = {"source": "designed voxel stalagmite", "pivot": "foot centre", "tries": tries}
    return m
