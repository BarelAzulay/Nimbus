"""shop-area T1 (spec 16.17.1): the Gumball Globe prop_roulette_globe with its in-globe eggs.

    <python> blender/pitches/shop_area_globe.py --check
        numbers (parts, tris <= 4000, bounds, top <= 14.4, the build's geometry check, ONE 6-connected piece: no
        floating cell, the glass counted at the fine grid) and the egg spots (EGG_SPOTS in
        blender/kit/props/lobby_machine.py): every scaled egg inside the glass (no point in a glass cell or outside the
        globe), on the floor or resting on the eggs below (gap), no egg sunk into another by more than a sliver
        (depth), off the seat ring, the chase egg's face visible from the front (>= CHASE_FLOOR), how full the globe
        reads (>= FILL_FLOOR eggs + cloud bed, >= EGG_FILL_FLOOR eggs alone). No bpy.
    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe blender/pitches/shop_area_globe.py --render <out_dir>
        [--shots hero,row,detail,plaza,side] [--scale 100]
        EEVEE renders (rcommon.py, the pitch's rig): the four roulettes built through the kit (props.REGISTRY
        "lobby_roulette_globe" with each roulette's look), the REAL painted lobby_egg models placed at the manifest's
        Egg<i> attachments at Meta.eggScale / chaseScale in LobbyMachineBuilder's rarity order (shop-area polish: the
        chase egg on the full egg_<rarity> key, K 10, the pile on egg_<rarity>_pile, K 4), a 5-stud player for scale,
        the glass at the game's Transparency 0.80 in GLASS_RGB.
    <python> blender/pitches/shop_area_globe.py --settle N --scale s --chase c
        drops N eggs into the globe (the same solid / graze rules as --check) and prints EGG_SPOTS rows.

Coordinates: machine studs, +Y up, front -Z, +X = the viewer's left (the kit's / Roblox space).
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.join(os.path.dirname(HERE), "kit")
sys.path.insert(0, os.path.dirname(HERE))   # blender/ (build_all's geometry check)
sys.path.insert(0, KIT)
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # the project path has Hebrew letters
except Exception:
    pass

import props  # noqa: E402
from props import lobby_machine as LM  # noqa: E402
from props import lobby_shop  # noqa: E402,F401  (registers lobby_egg)
from props.lobby_shop import egg_r, EGG_H  # noqa: E402

KITOBJ = props.PropKit()

# Config.Rarities / Config.Roulettes (src/shared/Config.lua), Config.Eggs.ChatColors.Secret
RARITY_ORDER = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
RARITY_RGB = {"Common": (168, 178, 194), "Uncommon": (104, 196, 128), "Rare": (88, 158, 232), "Epic": (176, 108, 232),
              "Legendary": (242, 182, 68), "Mythic": (238, 98, 140), "Secret": (40, 40, 52)}
SECRET_EMBLEM = (255, 240, 200)   # polish 2026-11-09: white-gold (the chat violet 180,150,255 twinned Cloud's Epic)
ROULETTES = [
    {"Id": "Cloud", "Color": (120, 190, 235), "Odds": {"Common": 60, "Uncommon": 28, "Rare": 10, "Epic": 2}},
    {"Id": "Storm", "Color": (128, 120, 214), "Odds": {"Uncommon": 35, "Rare": 40, "Epic": 20, "Legendary": 5}},
    {"Id": "Sky", "Color": (240, 180, 90), "Odds": {"Rare": 35, "Epic": 45, "Legendary": 17, "Mythic": 3}},
    {"Id": "Celestial", "Color": (236, 120, 170), "Odds": {"Epic": 43, "Legendary": 40, "Mythic": 15, "Secret": 2}},
]


def rarities(odds, n):
    """LobbyMachineBuilder.Rarities (the same rule): [0] = the top rarity, then the pile of the lower ones by weight"""
    have = [r for r in RARITY_ORDER if odds.get(r, 0) > 0]
    if not have:
        return []
    top, lower = have[-1], have[:-1]
    if not lower:
        return [top] * n
    m = n - 1
    tot = float(sum(odds[r] for r in lower))
    counts = [max(1, int(math.floor(m * odds[r] / tot + 0.5))) for r in lower]
    while sum(counts) > m:
        counts[counts.index(max(counts))] -= 1
    while sum(counts) < m:
        counts[0] += 1
    out, left = [top], list(counts)
    while sum(left) > 0:
        for i, r in enumerate(lower):
            if left[i] > 0:
                out.append(r)
                left[i] -= 1
    return out


def emblem_rgb(odds):
    top = [r for r in RARITY_ORDER if odds.get(r, 0) > 0][-1]
    return SECRET_EMBLEM if top == "Secret" else RARITY_RGB[top]


def build_machine(roulette=None):
    if roulette is not None:
        KITOBJ.look = look_of(roulette)
    return props.REGISTRY["lobby_roulette_globe"]({"key": "prop_roulette_globe"}, KITOBJ)


def look_of(r):
    return {"Primary": tuple(c / 255 for c in r["Color"]), "Secondary": tuple(c / 255 for c in emblem_rgb(r["Odds"])),
            "Eye": (0.2, 0.2, 0.3), "WingColor": (1.0, 1.0, 1.0)}


# ---------------------------------------------------------------------------------------------- the egg checks
def egg_points(n_phi=40, n_y=36):
    """the egg's surface (2.2 x 3 x 2.2, pivot = bottom centre) sampled: (N, 3) in egg units"""
    ys = np.linspace(0.02, EGG_H - 0.02, n_y)
    ph = np.linspace(0, 2 * math.pi, n_phi, endpoint=False)
    Y, P = np.meshgrid(ys, ph, indexing="ij")
    R = egg_r(Y)
    return np.stack([R * np.sin(P), Y, -R * np.cos(P)], -1).reshape(-1, 3)


def spot_frames():
    out = []
    for pos, yaw, tx, tz, s in LM.EGG_SPOTS:
        out.append((np.asarray(pos, float), LM.spot_rot(yaw, tx, tz), float(s)))
    return out


def depth_in(points, frame):
    """how deep each world point lies inside the egg at frame (studs; > 0 inside)"""
    p, R, s = frame
    q = (points - p) @ R / s            # R^T (P - p) / s  (rows of `points` @ R = R^T applied)
    y = q[:, 1]
    r = np.hypot(q[:, 0], q[:, 2])
    inside_y = (y > 0) & (y < EGG_H)
    d = np.where(inside_y, egg_r(np.clip(y, 0, EGG_H)) - r, -np.minimum(np.abs(y), np.abs(y - EGG_H)) - r)
    return d * s


def glass_cells():
    """the glass cell centres (the 0.5-stud grid round lobby_machine.ORIGIN), as a set of integer keys"""
    vs = 1.0 / LM.GK
    ox, oy, oz = LM.ORIGIN
    cx, cy, cz = LM.GLOBE_C
    ro, ri = LM.GLOBE_R
    out = set()
    n = 12
    for i in range(-n, n):
        for j in range(-n, n + 4):
            for k in range(-n, n):
                x, y, z = ox + (i + 0.5) * vs, oy + (j + 0.5) * vs, oz + (k + 0.5) * vs
                d2 = (x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2
                if ri * ri <= d2 <= ro * ro and LM.GLOBE_Y[0] < y < LM.GLOBE_Y[1]:
                    out.add((i, j, k))
    return out, vs


class Solid:
    """the machine without its eggs as occupancy grids: the 0.25 machine grid (floor, collar, the cloud bed, the glint)
    and the 0.5 glass grid; hit(W) -> per point True when it lies in an occupied cell"""

    def __init__(self):
        S = LM.MachineSculpt(KITOBJ, LM.K, LM.EXTENT, origin=LM.ORIGIN, name="Globe")
        G = LM.MachineSculpt(KITOBJ, LM.GK, LM.EXTENT, origin=LM.ORIGIN, name="GlobeGlass")
        LM._tints(S)
        LM.design_globe(S, G)
        self.grids = [(S.g.L != 0, S.g.half, S.vs), (G.g.L != 0, G.g.half, G.vs)]
        self.origin = np.array(LM.ORIGIN, float)

    def hit(self, W):
        out = np.zeros(len(W), bool)
        for occ, h, vs in self.grids:
            idx = np.floor((W - self.origin) / vs).astype(int) + h
            ok = np.all((idx >= 0) & (idx < occ.shape[0]), axis=1)
            sub = idx[ok]
            out[np.nonzero(ok)[0]] |= occ[sub[:, 0], sub[:, 1], sub[:, 2]]
        return out


GRAZE = ((0, 0, 0), (0.04, 0, 0), (-0.04, 0, 0), (0, 0.04, 0), (0, -0.04, 0), (0, 0, 0.04), (0, 0, -0.04))


def blocked(W, solid, frames, depth=0.0):
    """the egg surface W touches the machine (any cell within 0.04: check_eggs' glass margin) or sinks into an egg of
    `frames` by more than `depth`"""
    for d in GRAZE:
        if solid.hit(W + np.array(d)).any():
            return True
    return any((depth_in(W, f) > depth).any() for f in frames)


def hash01(i, salt):
    return ((i * 2654435761 + salt * 40503) % 1000003) / 1000003.0


def settle(n_pile=16, scale=None, chase_scale=None, verbose=True):
    """pour the eggs into the globe (deterministic): each pile egg goes to the lowest resting spot over a grid of xz
    candidates (dropped from the top until it touches the floor, the cloud bed, the glass or an egg), then the chase egg
    to the lowest front spot that leaves its face >= 90 % clear from the front.  -> EGG_SPOTS rows (chase first)"""
    scale = scale or LM.EGG_SCALE
    chase_scale = chase_scale or LM.CHASE_SCALE
    solid = Solid()
    pts = egg_points()                           # (the check's own sampling: no graze the check would see)
    placed = []                                  # frames (p, R, s)

    def world(p, R, s):
        return (pts * s) @ R.T + p

    def clear(W):
        return not blocked(W, solid, placed, 0.015)

    def rest(x, z, R, s):
        """the lowest free pivot y at (x, z) dropped from above (None: no free spot)"""
        y, free_seen, last = 11.9, False, None
        while y >= LM.FLOOR_Y - 0.2:
            ok = clear(world(np.array([x, y, z]), R, s))
            if ok:
                free_seen, last = True, y
            elif free_seen:
                lo, hi = y, last                 # hi free, lo blocked
                for _ in range(7):
                    mid = 0.5 * (lo + hi)
                    if clear(world(np.array([x, mid, z]), R, s)):
                        hi = mid
                    else:
                        lo = mid
                return hi
            y -= 0.12
        return last

    cands = [(x, z) for x in np.arange(-2.4, 2.41, 0.2) for z in np.arange(-2.4, 2.41, 0.2) if x * x + z * z <= 2.45 ** 2]

    def pose(i):
        yaw = (i * 2.399963) % (2 * math.pi)
        return yaw, 0.16 * (hash01(i, 3) - 0.5), 0.16 * (hash01(i, 7) - 0.5)

    spots = []
    for k in range(n_pile):
        yaw, tx, tz = pose(k + 1)
        R = LM.spot_rot(yaw, tx, tz)
        best = None
        for x, z in cands:
            y = rest(x, z, R, scale)
            if y is not None and (best is None or y < best[0] - 1e-6):
                best = (y, x, z)
        if best is None:
            print("settle: no room for pile egg %d" % (k + 1))
            break
        y, x, z = best
        placed.append((np.array([x, y, z]), R, scale))
        spots.append(((round(float(x), 3), round(float(y), 3), round(float(z), 3)), round(yaw, 3), round(tx, 3), round(tz, 3), "EGG_SCALE"))
        if verbose:
            print("pile %2d  (%.2f, %.3f, %.2f)" % (k + 1, x, y, z), flush=True)
    # the chase egg: the front spots (z <= -0.8, |x| <= 1.0), lowest first, the first whose face is clear
    yaw, tx, tz = -0.3, -0.18, 0.0
    R = LM.spot_rot(yaw, tx, tz)
    front = []
    for x, z in cands:
        if z <= -0.8 and abs(x) <= 1.0:
            y = rest(x, z, R, chase_scale)
            if y is not None:
                front.append((y, x, z))
    front.sort()
    chase = None
    for y, x, z in front:
        f = (np.array([x, y, z]), R, chase_scale)
        if chase_visible(f, placed) >= CHASE_FLOOR:
            chase = ((round(float(x), 3), round(float(y), 3), round(float(z), 3)), yaw, tx, tz, "CHASE_SCALE")
            break
    if chase is None:
        print("settle: no clear front spot for the chase egg")
        return None
    return [chase] + spots


def chase_visible(frame, others):
    """the share of the egg's front-facing surface points with a clear line to an eye 14 studs out in front"""
    p, R, s = frame
    W = (egg_points() * s) @ R.T + p
    eye = np.array([0.0, 8.5, -14.0])
    front = W[(W[:, 2] - p[2]) < 0]
    clear = 0
    for q in front:
        ray = q + (eye - q) * np.linspace(0.02, 0.4, 24)[:, None]
        hit = any((depth_in(ray, f) > 0).any() for f in others)
        clear += 0 if hit else 1
    return clear / max(1, len(front))


def fill_report(frames, solid=None):
    """front orthographic view of the glass's inner disc above the collar's lip: the share covered by eggs, and by eggs
    or the cloud bed (what reads as "the stuff in the globe")"""
    gx, gy = np.meshgrid(np.linspace(-2.8, 2.8, 113), np.linspace(LM.FLOOR_Y, LM.GLOBE_C[1] + LM.GLOBE_R[1], 102))
    disc = (gx ** 2 + (gy - LM.GLOBE_C[1]) ** 2) <= LM.GLOBE_R[1] ** 2
    eggs = np.zeros_like(disc)
    bed = np.zeros_like(disc)
    zs = np.linspace(-2.7, 2.7, 37)
    for z in zs:
        P = np.stack([gx.ravel(), gy.ravel(), np.full(gx.size, z)], -1)
        for f in frames:
            eggs |= (depth_in(P, f) > 0).reshape(gx.shape)
        if solid is not None:
            r2 = (P[:, 0] - LM.GLOBE_C[0]) ** 2 + (P[:, 1] - LM.GLOBE_C[1]) ** 2 + (P[:, 2] - LM.GLOBE_C[2]) ** 2
            bed |= (solid.hit(P) & (r2 < (LM.GLOBE_R[1] - 0.2) ** 2) & (P[:, 1] > LM.FLOOR_Y)).reshape(gx.shape)
    d = float(disc.sum())
    return float((eggs & disc).sum()) / d, float(((eggs | bed) & disc).sum()) / d


# the pinned floors (review round 2: the measured fill was only printed, so a re-settle or a bed change could drop the
# globe back towards the ~25 % the owner saw and --check stay green). The owner asked "about 60 %" full; spec 16.17
# "Polish" measured 51 % eggs / 62 % with the cloud bed and the chase egg 90 % seen (settle() keeps it >= 90 %)
FILL_FLOOR = 0.55       # eggs + cloud bed, the front view of the glass's inner disc over the collar
EGG_FILL_FLOOR = 0.50   # eggs alone: the bed may not stand in for the eggs
CHASE_FLOOR = 0.90      # the chase egg's front-facing surface with a clear line to an eye 14 studs out


def check_eggs(verbose=True):
    pts = egg_points()
    frames = spot_frames()
    cells, vs = glass_cells()
    ox, oy, oz = LM.ORIGIN
    solid = Solid()
    report = {"problems": []}
    worlds = []
    for f in frames:
        p, R, s = f
        worlds.append((pts * s) @ R.T + p)
    n = len(frames)
    for i, W in enumerate(worlds):
        name = "Egg%d" % (i + 1)
        idx = np.floor((W - np.array([ox, oy, oz])) / vs).astype(int)
        in_glass = sum(1 for t in map(tuple, idx) if t in cells)
        # also with a 0.04 margin toward every axis (the egg must not graze a glass face)
        graze = 0
        for d in ((0.04, 0, 0), (-0.04, 0, 0), (0, 0.04, 0), (0, -0.04, 0), (0, 0, 0.04), (0, 0, -0.04)):
            idx2 = np.floor((W + np.array(d) - np.array([ox, oy, oz])) / vs).astype(int)
            graze += sum(1 for t in map(tuple, idx2) if t in cells)
        up = W[W[:, 1] > LM.GLOBE_Y[0]]          # the part of the egg inside the glass's height (below it: the seat)
        r_out = np.linalg.norm(up - np.array(LM.GLOBE_C), axis=1).max() if len(up) else 0.0
        low = W[:, 1].min()
        rad = np.hypot(W[:, 0], W[:, 2])
        seat = int(((rad > 1.95) & (W[:, 1] < 7.5)).sum())
        sunk_floor = LM.FLOOR_Y - low
        gaps, deep = [], []
        for j in range(n):
            if j == i:
                continue
            d = depth_in(W, frames[j])
            deep.append((float(d.max()), j))
            gaps.append((float(-d.max()), j))
        worst = max(deep)
        lower_gap = min(g for g, j in gaps)
        # polish: an egg rests when 0.06 lower it would touch the floor, the cloud bed, the glass or another egg
        Wd = W - np.array([0.0, 0.06, 0.0])
        rests = blocked(Wd, solid, [frames[j] for j in range(n) if j != i])
        in_solid = int(solid.hit(W).sum())
        line = "%-6s s %.2f  y %.2f..%.2f  glass hits %d (graze %d)  solid hits %d  outmost %.2f  seat %d  floor %+.3f  deepest into Egg%d %.3f  nearest gap %.3f  %s" % (
            name, frames[i][2], low, W[:, 1].max(), in_glass, graze, in_solid, r_out, seat, -sunk_floor, worst[1] + 1, worst[0], lower_gap,
            "rests" if rests else "FLOATS")
        if verbose:
            print(line)
        if in_solid:
            report["problems"].append(name + " sunk into the machine (floor / cloud bed)")
        if in_glass or graze:
            report["problems"].append(name + " touches the glass")
        if r_out > LM.GLOBE_R[0]:
            report["problems"].append(name + " pokes out of the globe")
        if seat:
            report["problems"].append(name + " in the seat ring")
        if sunk_floor > 0.06:
            report["problems"].append(name + " sunk %.2f into the floor" % sunk_floor)
        if worst[0] > 0.1:
            report["problems"].append("%s %.2f into Egg%d" % (name, worst[0], worst[1] + 1))
        if not rests:
            report["problems"].append(name + " floats")
    # the chase egg from the front: the share of its front-facing points with a clear line to an eye 14 studs out
    vis = chase_visible(frames[0], frames[1:])
    report["chaseVisible"] = vis
    # how full (polish): the front view of the glass's whole inner disc over the collar, covered by eggs / eggs + the bed
    eggs_only, with_bed = fill_report(frames, solid)
    report["fill"], report["fillBed"] = eggs_only, with_bed
    top_front = max(float(w[:, 1].max()) for w, f in zip(worlds, frames) if f[0][2] < 0.0)
    if verbose:
        print("eggs %d   chase egg front visible %.1f %% (floor %.0f)   the globe (front view) %.1f %% eggs (floor %.0f), "
              "%.1f %% eggs + cloud bed (floor %.0f)   the front half's top egg at y %.2f"
              % (n, vis * 100, CHASE_FLOOR * 100, eggs_only * 100, EGG_FILL_FLOOR * 100, with_bed * 100,
                 FILL_FLOOR * 100, top_front))
    if vis < CHASE_FLOOR:
        report["problems"].append("the chase egg is hidden from the front (%.1f %% clear; >= %.0f %% wanted)"
                                  % (vis * 100, CHASE_FLOOR * 100))
    if with_bed < FILL_FLOOR:
        report["problems"].append("the globe reads only %.1f %% full from the front (eggs + bed; >= %.0f %% wanted)"
                                  % (with_bed * 100, FILL_FLOOR * 100))
    if eggs_only < EGG_FILL_FLOOR:
        report["problems"].append("the eggs cover only %.1f %% of the globe from the front (>= %.0f %% wanted)"
                                  % (eggs_only * 100, EGG_FILL_FLOOR * 100))
    return report


def islands():
    """6-connected pieces of the whole machine: the 0.25-stud machine cells plus the 0.5-stud glass cells (each split
    into its 2 x 2 x 2 fine cells, same origin) -> [(cells, min xyz, max xyz, keys)], biggest first.  One piece = every
    cell touches the rest by a face (the lid rests on the glass, the glass on the collar); more = something floats."""
    from collections import deque
    S = LM.MachineSculpt(KITOBJ, LM.K, LM.EXTENT, origin=LM.ORIGIN, name="Globe")
    G = LM.MachineSculpt(KITOBJ, LM.GK, LM.EXTENT, origin=LM.ORIGIN, name="GlobeGlass")
    LM._tints(S)
    LM.design_globe(S, G)
    L = S.g.L
    occ = L != 0
    hs, hg = S.g.half, G.g.half
    ratio = int(round(LM.K / LM.GK))
    gi = (np.arange(occ.shape[0]) - hs) // ratio + hg            # fine index -> glass index (same origin)
    ok = (gi >= 0) & (gi < G.g.L.shape[0])
    gi = np.clip(gi, 0, G.g.L.shape[0] - 1)
    glass = (G.g.L != 0)[np.ix_(gi, gi, gi)] & ok[:, None, None] & ok[None, :, None] & ok[None, None, :]
    occ = occ | glass
    seen = np.zeros(occ.shape, bool)
    pieces = []
    for start in map(tuple, np.argwhere(occ)):
        if seen[start]:
            continue
        seen[start] = True
        q, cells = deque([start]), []
        while q:
            c = q.popleft()
            cells.append(c)
            for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                nb = (c[0] + d[0], c[1] + d[1], c[2] + d[2])
                if 0 <= nb[0] < occ.shape[0] and 0 <= nb[1] < occ.shape[1] and 0 <= nb[2] < occ.shape[2] and occ[nb] and not seen[nb]:
                    seen[nb] = True
                    q.append(nb)
        cells = np.array(cells)
        xyz = np.array(LM.ORIGIN) + (cells - hs + 0.5) * S.vs
        keys = sorted({S.g.keys[L[tuple(c)]] or "Glass" for c in cells})
        pieces.append((len(cells), xyz.min(0).round(3).tolist(), xyz.max(0).round(3).tolist(), keys))
    pieces.sort(key=lambda p: -p[0])
    return pieces


def check():
    from build_all import Builder
    m = build_machine(ROULETTES[0])
    print("parts:")
    for o in m.objects.values():
        print("  %-10s %-8s tris %5d  %-11s %s" % (o.name, o.group, o.tris(), o.material, o.recipe))
    pts = np.concatenate([np.asarray(c, float).reshape(-1, 3) for o in m.objects.values() for c, _ in o.quads])
    lo, hi = pts.min(0), pts.max(0)
    print("tris %d  parts %d  bounds min %s max %s size %s" % (m.tris(), len(m.objects), np.round(lo, 3), np.round(hi, 3), np.round(hi - lo, 3)))
    print("geometry:", Builder.check_geometry(m) or "ok")
    # review round 1: check_geometry tests closure / zero-area only, never floating cells (the wing tips hovered)
    pieces = islands()
    print("islands: %d (one = every cell touches the machine by a face)" % len(pieces))
    for p in pieces[1:]:
        print("  FLOATS: %d cells %s .. %s %s" % p)
    for r in ROULETTES:
        print("  %-9s %s" % (r["Id"], " ".join(rarities(r["Odds"], 12))))
    rep = check_eggs()
    if len(pieces) != 1:
        rep["problems"].append("%d floating pieces" % (len(pieces) - 1))
    if m.tris() > 4000:
        rep["problems"].append("%d tris over the 4000 propBig budget" % m.tris())
    if hi[1] > 14.4 + 1e-6:
        rep["problems"].append("top %.2f over 14.4" % hi[1])
    print("egg problems:", rep["problems"] or "none")
    return 0 if not rep["problems"] else 1


# ---------------------------------------------------------------------------------------------- renders (bpy)
def add_eggs(m, roulette, neon=True):
    """copy the real painted eggs into model m at the Egg<i> attachments (scaled about the pivot): the chase egg Egg1 the
    full egg_<rarity> (lobby_egg, K 10), the pile the low-poly eggs egg_<rarity>_pile (K 4, Neon baked flat) as the game
    tags them (polish 2026-11-09)"""
    seq = rarities(roulette["Odds"], len(LM.EGG_SPOTS))
    cache = {}
    for i, ((p, R, s), rar) in enumerate(zip(spot_frames(), seq)):
        low = i > 0
        key = rar.lower() + ("_pile" if low else "")
        if key not in cache:
            args = {"rarity": rar.lower(), "low": True} if low else {"rarity": rar.lower()}
            cache[key] = props.REGISTRY["lobby_egg"]({"key": "egg_" + key, "args": args}, KITOBJ)
        e = cache[key]
        for name, o in e.objects.items():
            nm = "Egg%d_%s" % (i + 1, name)
            n = m.obj(nm, group="Eggs", region=o.region, shade=o.shade, recipe=o.recipe, material=o.material if neon else "SmoothPlastic",
                      baked=o.baked)
            for corners, vc in o.quads:
                n.quads.append(((np.asarray(corners, float) * s) @ R.T + p, vc))
    return m


def render(out, shots, scale):
    import rcommon as RC
    os.makedirs(out, exist_ok=True)
    res = (1200 * scale // 100, 900 * scale // 100)
    RC.stage(res=res, samples=24)
    RC.court(36.0, ring=(12.0, 13.5))
    step = 15.0
    xs = [(-1.5 + i) * step for i in range(4)]
    for x, r in zip(xs, ROULETTES):
        m = build_machine(r)
        m.name = m.name + "_" + r["Id"]      # nvox.blend names the preview materials after the model: one set per roulette
        add_eggs(m, r)
        RC.add_model(m, look_of(r), at=(x, 0, 0), glass_alpha=1.0 - LM.GLASS_T, glass_rgb=LM.GLASS_RGB, glass_rough=0.08)
    RC.player((xs[1] + 7.5, -7.0, 0.0))
    if "row" in shots:
        RC.shoot(os.path.join(out, "t1_row.png"), (-26.0, -42.0, 14.0), (0.0, 0.0, 6.5), 40)
    if "plaza" in shots:
        # a standing player's eye: 5 studs up, 25 studs out in front of the Sky machine
        RC.shoot(os.path.join(out, "t1_plaza.png"), (xs[2], -25.0, 5.0), (xs[2], 0.0, 7.0), 40)
    if "plazacam" in shots:
        # (polish) Roblox's default third-person camera for a player standing 25 studs in front: ~12 studs behind the
        # player and ~6 over the head, so the camera is ~37 out and 11 up
        RC.player((xs[2] - 1.5, -25.0, 0.0), name="PlazaPlayer")
        RC.shoot(os.path.join(out, "t1_plazacam.png"), (xs[2] - 3.0, -37.0, 11.0), (xs[2], 0.0, 8.0), 40)
    if "hero" in shots:
        x = xs[3]
        RC.shoot(os.path.join(out, "t1_hero.png"), (x - 12.0, -18.0, 11.0), (x + 0.3, 0.0, 7.6), 40)
    if "detail" in shots:
        x = xs[2]
        RC.shoot(os.path.join(out, "t1_detail.png"), (x, -10.5, 9.4), (x, 0.0, 8.4), 55)
    if "side" in shots:
        x = xs[0]
        RC.shoot(os.path.join(out, "t1_side.png"), (x - 19.0, -12.0, 8.0), (x, 0.0, 7.0), 50)
    if "back" in shots:
        x = xs[1]
        RC.shoot(os.path.join(out, "t1_back.png"), (x + 11.0, 15.0, 9.0), (x, 0.0, 6.0), 40)
    if "top" in shots:
        x = xs[2]
        RC.shoot(os.path.join(out, "t1_top.png"), (x - 4.0, -6.0, 19.0), (x, 0.0, 10.0), 45)
    if "front" in shots:
        x = xs[1]
        RC.shoot(os.path.join(out, "t1_front.png"), (x, -22.0, 7.0), (x, 0.0, 7.0), 45)
    if "finial" in shots:
        x = xs[3]
        RC.shoot(os.path.join(out, "t1_finial.png"), (x - 3.0, -7.0, 14.5), (x, 0.0, 13.3), 50)


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--check" in a:
        sys.exit(check())
    if "--settle" in a:
        n = int(a[a.index("--settle") + 1]) if len(a) > a.index("--settle") + 1 else 16
        sc = float(a[a.index("--scale") + 1]) if "--scale" in a else None
        cs = float(a[a.index("--chase") + 1]) if "--chase" in a else None
        rows = settle(n, sc, cs)
        if rows:
            print("EGG_SPOTS = [")
            for pos, yaw, tx, tz, s in rows:
                print("    ((%r, %r, %r), %r, %r, %r, %s)," % (pos[0], pos[1], pos[2], yaw, tx, tz, s))
            print("]")
            fr = [(np.asarray(p, float), LM.spot_rot(yw, tx, tz), (sc or LM.EGG_SCALE) if s == "EGG_SCALE" else (cs or LM.CHASE_SCALE))
                  for p, yw, tx, tz, s in rows]
            e, b = fill_report(fr, Solid())
            print("fill: %.0f %% eggs, %.0f %% eggs + bed; chase visible %.0f %%" % (e * 100, b * 100, chase_visible(fr[0], fr[1:]) * 100))
        sys.exit(0 if rows else 1)
    if "--render" in a:
        out = os.path.abspath(a[a.index("--render") + 1])
        shots = a[a.index("--shots") + 1].split(",") if "--shots" in a else ["hero", "row", "detail", "plaza", "side"]
        scale = int(a[a.index("--scale") + 1]) if "--scale" in a else 100
        render(out, shots, scale)
        sys.exit(0)
    print(__doc__)
    sys.exit(2)
