"""shop-area T1 (spec 16.17.1): the Gumball Globe prop_roulette_globe with its in-globe eggs.

    <python> blender/pitches/shop_area_globe.py --check
        numbers (parts, tris, bounds, the build's geometry check) and the egg spots (EGG_SPOTS in
        blender/kit/props/lobby_machine.py): every scaled egg inside the glass (no point in a glass cell or outside the
        globe), on the floor or resting on the eggs below (gap), no egg sunk into another by more than a sliver
        (depth), off the seat ring, the chase egg's face visible from the front, how full the globe reads. No bpy.
    %USERPROFILE%\\.bpyenv\\Scripts\\python.exe blender/pitches/shop_area_globe.py --render <out_dir>
        [--shots hero,row,detail,plaza,side] [--scale 100]
        EEVEE renders (rcommon.py, the pitch's rig): the four roulettes built through the kit (props.REGISTRY
        "lobby_roulette_globe" with each roulette's look), the REAL painted lobby_egg models (the game's egg_<rarity>
        keys, K 10) placed at the manifest's Egg<i> attachments at Meta.eggScale / chaseScale in LobbyMachineBuilder's
        rarity order, a 5-stud player for scale, the glass at the game's Transparency 0.70.

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
SECRET_EMBLEM = (180, 150, 255)
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


def check_eggs(verbose=True):
    pts = egg_points()
    frames = spot_frames()
    cells, vs = glass_cells()
    ox, oy, oz = LM.ORIGIN
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
        rests = (abs(sunk_floor) < 0.06) or lower_gap < 0.06
        line = "%-6s s %.2f  y %.2f..%.2f  glass hits %d (graze %d)  outmost %.2f  seat %d  floor %+.3f  deepest into Egg%d %.3f  nearest gap %.3f  %s" % (
            name, frames[i][2], low, W[:, 1].max(), in_glass, graze, r_out, seat, -sunk_floor, worst[1] + 1, worst[0], lower_gap,
            "rests" if rests else "FLOATS")
        if verbose:
            print(line)
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
    W = worlds[0]
    p, R, s = frames[0]
    eye = np.array([0.0, 8.5, -14.0])
    front = W[(W[:, 2] - p[2]) < 0]
    clear = 0
    for q in front:
        ray = q + (eye - q) * np.linspace(0.02, 0.4, 24)[:, None]
        hit = any((depth_in(ray, frames[j]) > 0).any() for j in range(1, n))
        clear += 0 if hit else 1
    vis = clear / max(1, len(front))
    report["chaseVisible"] = vis
    # how full: the share of the globe's inner disc below its centre (front orthographic view) covered by eggs
    gx, gy = np.meshgrid(np.linspace(-2.8, 2.8, 113), np.linspace(LM.FLOOR_Y, LM.GLOBE_C[1], 60))
    disc = (gx ** 2 + (gy - LM.GLOBE_C[1]) ** 2) <= LM.GLOBE_R[1] ** 2
    cov = np.zeros_like(disc)
    for f in frames:
        for z in np.linspace(-2.6, 2.6, 27):
            P = np.stack([gx.ravel(), gy.ravel(), np.full(gx.size, z)], -1)
            cov |= (depth_in(P, f) > 0).reshape(gx.shape)
    report["fill"] = float((cov & disc).sum()) / float(disc.sum())
    if verbose:
        print("chase egg front visible %.0f %%   lower globe covered (front view) %.0f %%" % (vis * 100, report["fill"] * 100))
    if vis < 0.85:
        report["problems"].append("the chase egg is hidden from the front (%.0f %% clear)" % (vis * 100))
    return report


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
    for r in ROULETTES:
        print("  %-9s %s" % (r["Id"], " ".join(rarities(r["Odds"], 12))))
    rep = check_eggs()
    print("egg problems:", rep["problems"] or "none")
    return 0 if not rep["problems"] else 1


# ---------------------------------------------------------------------------------------------- renders (bpy)
def add_eggs(m, roulette, neon=True):
    """copy the real painted eggs (lobby_egg, K 10) into model m at the Egg<i> attachments (scaled about the pivot)"""
    seq = rarities(roulette["Odds"], len(LM.EGG_SPOTS))
    cache = {}
    for i, ((p, R, s), rar) in enumerate(zip(spot_frames(), seq)):
        key = rar.lower()
        if key not in cache:
            cache[key] = props.REGISTRY["lobby_egg"]({"key": "egg_" + key, "args": {"rarity": key}}, KITOBJ)
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
        RC.add_model(m, look_of(r), at=(x, 0, 0), glass_alpha=1.0 - LM.GLASS_T)
    RC.player((xs[1] + 7.5, -7.0, 0.0))
    if "row" in shots:
        RC.shoot(os.path.join(out, "t1_row.png"), (-26.0, -42.0, 14.0), (0.0, 0.0, 6.5), 40)
    if "plaza" in shots:
        # a standing player's eye: 5 studs up, 25 studs out in front of the Sky machine
        RC.shoot(os.path.join(out, "t1_plaza.png"), (xs[2], -25.0, 5.0), (xs[2], 0.0, 7.0), 40)
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
    if "--render" in a:
        out = os.path.abspath(a[a.index("--render") + 1])
        shots = a[a.index("--shots") + 1].split(",") if "--shots" in a else ["hero", "row", "detail", "plaza", "side"]
        scale = int(a[a.index("--scale") + 1]) if "--scale" in a else 100
        render(out, shots, scale)
        sys.exit(0)
    print(__doc__)
    sys.exit(2)
