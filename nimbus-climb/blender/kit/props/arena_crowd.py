"""Sky-Sailors' Ring: the Champion Ring's floor emblem and its crowd (bug #11 "ground logo bugged & looks bad, crowd
needs animation and sound"; the player's pick: option A of the plaza-logo-crowd pitch, with the note "option a but add
a drummer like in option b", 2026-10-27).

The story the shapes follow: the sky-ship crews built this ring so their ships' pets could spar between voyages, and
set a ship's compass star into the floor (north points at the champion).  The old weather clouds that once pushed
those ships now sit in the stands in sailor caps: a drippy Rain cloud, a grumpy Thunder-cloud Captain, a Sun puff, a
Snow puff in a striped scarf, Breeze (whistling), Fog (the lookout, dozing behind his brass spyglass) and Drizzle, the
smallest, who is the ship's drummer boy: real navies had boy drummers who "beat to quarters".  He sits in the middle
of the back row (where option B had its drummer pup) with a navy rope-tensioned side drum.  Two flag masts carry a
line of signal flags that spells NIMBUS twice in the international code (N blue/white checks, I yellow with a black
disc, M blue with a white saltire, B a red swallowtail, U red/white quarters, S white with a blue square), the west
mast carries the ship's bell and a red/white life ring, and a rope coil lies on the front step.

Keys (blender/catalog/arenadungeon.json; ArenaBuilder.lua Ring.CAST / Ring.RIG mirror the numbers below):
    arena_emblem            the compass star inlay (0.25-stud voxels, its own key: the 0.5 pocket bake made it an "E")
                            pivot = the pocket floor centre, +Z = north = the champion's side
    arena_crowd_<name>      one cloud body per spectator (rain, captain, sun, snow, breeze, fog, drizzle):
                            pivot = the seat point under the body (bottom centre), -Z = the face
    arena_crowd_arm         a stubby cloud arm (tinted per spectator, ML_Primary), pivot = the shoulder, hangs to -Y
    arena_crowd_stick       Drizzle's arm with a drumstick (pivot = the shoulder; the stick points to -Z)
    arena_crowd_spyglass    Fog's arm holding the spyglass (pivot = the shoulder)
    arena_crowd_cap         the sailor cap (white crown, navy band and ribbons, red pompom), pivot = its bottom centre
    arena_crowd_captaincap  the captain's cap (navy crown, gold band, black visor, gold badge)
    arena_crowd_rig         the two flag masts, the bell bracket, the life ring, the rope coil (stand-local pivot)
    arena_crowd_flags       the signal-flag line between the mast tops (pivot = the line's mid point between the tops)
    arena_crowd_bell        the ship's bell with its lanyard (pivot = the hang point)
    arena_crowd_drum        Drizzle's side drum (pivot = its centre; it rides his body, body-local frame DRUM)
Every moving piece is its own key on its own root Part (ML_Weld): the client RingCrowdFx moves the roots.

Coordinates: studs, Roblox axes (+X right, +Y up, -Z front).  Stand-local = Ring.crowdStand's frame (its origin on
the deck under the stand's front edge, the steps' tops at y 1.75 / 3.75).
"""
import math

import numpy as np

from nvox.grid import angles
from props import prop
from props.lobby import PAL, Sculpt, finish, hsh

PAL.update({
    # emblem
    "CsViolet": (156, 96, 238), "CsVioletDark": (128, 74, 206), "CsBrass": (206, 160, 80), "CsBrassDark": (168, 124, 58),
    "CsGold": (250, 190, 56), "CsGoldDark": (206, 132, 34), "CsCream": (252, 240, 210), "CsCreamDark": (214, 192, 150),
    "CsRope": (214, 180, 120), "CsRopeDark": (170, 134, 84), "CsSteel": (150, 154, 168), "CsRivet": (88, 92, 108),
    "CsNorth": (226, 74, 70),
    # faces
    "CsInk": (42, 46, 70), "CsGlint": (250, 252, 255), "CsMouth": (196, 70, 104), "CsTongue": (246, 132, 150),
    "CsBlush": (250, 160, 170), "CsBrow": (70, 74, 96),
    # caps
    "CsCapWhite": (246, 248, 252), "CsCapNavy": (40, 54, 110), "CsPom": (222, 58, 70), "CsVisor": (30, 32, 44),
    # extras
    "CsRay": (248, 146, 52), "CsRayTip": (255, 196, 84), "CsScarf": (226, 64, 70), "CsScarfStripe": (250, 246, 240),
    "CsDrop": (126, 186, 242), "CsDrumShell": (44, 60, 122), "CsDrumRim": (214, 62, 66), "CsDrumHead": (246, 240, 226),
    "CsDrumRope": (236, 220, 184), "CsStrap": (244, 244, 248), "CsStick": (150, 98, 58), "CsStickTip": (240, 214, 170),
    "CsLeather": (120, 76, 48), "CsMedal": (240, 196, 70),
    # rig
    "CsMast": (150, 104, 66), "CsMastDark": (118, 80, 52), "CsMastFoot": (176, 172, 184), "CsMastCap": (232, 186, 82),
    "CsLifeRed": (232, 70, 66), "CsLifeWhite": (248, 248, 248), "CsLine": (96, 74, 52), "CsIron": (70, 74, 92),
    "CsBell": (226, 178, 76), "CsBellDark": (176, 128, 52), "CsClapper": (88, 68, 52),
    # signal flags
    "CsFlagRed": (226, 62, 62), "CsFlagWhite": (248, 248, 250), "CsFlagBlue": (40, 86, 190),
    "CsFlagYellow": (250, 204, 56), "CsFlagBlack": (34, 36, 46),
})

# ------------------------------------------------------------------------------------------------- the cast
# name: seat (stand-local x, seat y, z), body (w, h, d), tint, mood, cap ("sailor" | "captain" | None), cap tilt
# (radians about Z), arm keys (L, R), shoulder height factor.  Mirrored by ArenaBuilder.lua Ring.CAST.
CAST = {
    "rain": {"seat": (-12.0, 1.75, 1.9), "body": (3.2, 2.8, 2.4), "tint": (176, 196, 222), "mood": "smile",
             "cap": "sailor", "tilt": -0.14, "arms": ("arm", "arm"), "seed": 3},
    "captain": {"seat": (-4.0, 1.75, 1.9), "body": (3.8, 3.2, 2.6), "tint": (118, 124, 150), "mood": "grump",
                "cap": "captain", "tilt": -0.06, "arms": ("arm", "arm"), "seed": 10},
    "sun": {"seat": (4.0, 1.75, 1.9), "body": (3.2, 2.8, 2.4), "tint": (255, 228, 150), "mood": "beam",
            "cap": "sailor", "tilt": 0.14, "arms": ("arm", "arm"), "seed": 17},
    "snow": {"seat": (12.0, 1.75, 1.9), "body": (3.0, 2.7, 2.3), "tint": (246, 250, 255), "mood": "smile",
             "cap": "sailor", "tilt": 0.12, "arms": ("arm", "arm"), "seed": 24},
    "breeze": {"seat": (-8.0, 3.75, 5.7), "body": (3.0, 2.7, 2.3), "tint": (204, 244, 216), "mood": "whistle",
               "cap": "sailor", "tilt": 0.16, "arms": ("arm", "arm"), "seed": 31},
    "drizzle": {"seat": (0.0, 3.75, 5.7), "body": (2.8, 2.5, 2.2), "tint": (196, 222, 246), "mood": "focus",
                "cap": "sailor", "tilt": -0.1, "arms": ("stick", "stick"), "seed": 38},
    "fog": {"seat": (8.0, 3.75, 5.7), "body": (3.4, 2.9, 2.4), "tint": (226, 216, 246), "mood": "sleepy",
            "cap": None, "tilt": 0.0, "arms": ("arm", "spyglass"), "seed": 45},
}


def body_frame(name):
    """(cap point, cap tilt, shoulder L, shoulder R) in the body's own frame (pivot = seat point)"""
    c = CAST[name]
    w, h, d = c["body"]
    cap = (0.05, round(h * 0.96, 3), 0.0)
    sh = h * (0.57 if name == "drizzle" else 0.5)
    inset = 0.1
    return cap, c["tilt"], (round(-w / 2 + inset, 3), round(sh, 3), -0.05), (round(w / 2 - inset, 3), round(sh, 3), -0.05)


# ------------------------------------------------------------------------------------------------- helpers
def _sculpt(kit, K, extent):
    S = Sculpt(kit, K, extent)
    return S


def _feet(S):
    """voxel row 0 is centred on y 0: the mesh offset (0, half a voxel, 0) puts the bottom face on the pivot plane"""
    return (0.0, 0.5 / S.K, 0.0)


def _vox_paint(S, key, only, x, y, z, w=1, h=1, depth=2.0):
    """paint a w x h block of voxels (in voxel units, lower-left at the voxel holding (x, y)) on the surface facing -Z"""
    v = 1.0 / S.K
    cx = (math.floor(x * S.K) + (w - 1) / 2.0) * v
    cy = (math.floor(y * S.K) + (h - 1) / 2.0) * v
    S.g.paint(key, "box", only=only, center=(cx, cy, z), size=(w * v * 0.98, h * v * 0.98, depth))


# ------------------------------------------------------------------------------------------------- the emblem
def _emblem(S):
    """the ship's compass star on a violet disc in a brass rim with a rope coil border; one short point carries a newer
    riveted steel repair plate; a gold hub with a violet pin. North (the champion, +Z) is the same gold point as the
    other three, as in the approved option_a.png (round 1 gave it a red needle tip that ran over the
    rope coil: not in the approved picture, dropped in fix round part 2 on Gemini's check)"""
    g = S.g
    v = 1.0 / S.K
    L0, L1, L2 = 0.0, v, 2 * v  # voxel rows (centres)
    R_RIM, R_ROPE, R_DISC = 7.5, 6.75, 5.9
    # radii and the exponents measured off option_a.png's top view (gold ~0.9 wide at mid-length, cream ~1.6 at the root)
    STAR_HUB, STAR_LONG, STAR_NORTH, STAR_SHORT, P_LONG, P_SHORT = 1.25, 5.85, 5.85, 4.4, 4.2, 2.4  # north = the others (option A)
    n = int(math.ceil(R_RIM * S.K)) + 1
    TAU = 2 * math.pi
    c45 = math.sqrt(0.5)
    cells = {}
    for i in range(-n, n + 1):
        for k in range(-n, n + 1):
            x, z = i * v, k * v
            r = math.hypot(x, z)
            if r > R_RIM:
                continue
            ang = math.atan2(x, z)  # 0 = north (+Z), clockwise seen from above (+X = east)
            if r > R_ROPE:
                # brass rim: a raised outer lip (row 1) on a flat band (row 0), a darker worn inner edge
                cells[(i, 0, k)] = "CsBrassDark" if r < R_ROPE + 0.3 else "CsBrass"
                if r > R_RIM - 0.45:
                    cells[(i, 1, k)] = "CsBrass"
                continue
            if r > R_DISC:
                # the rope coil: diagonal strands (alternating light / dark), one row, the coil laid round the disc
                s = int(math.floor(ang * R_ROPE / 0.42 + r / 0.3))
                cells[(i, 0, k)] = "CsRope" if s % 2 == 0 else "CsRopeDark"
                continue
            cells[(i, 0, k)] = "CsViolet"
            # the star (the approved option A shape, ring_pitch.py emblem_a): two 4-point stars in polar form, a point's
            # radius r <= rhub + (rtip - rhub) * a ** p (a = 1 on the point's axis, 0 half way to the next point), so
            # every point is a broad concave wedge. 4 long cardinal points (gold) and 4 short diagonal points (cream),
            # BOTH inlaid proud (rows 0 + 1); each point is split down its axis into a light and a dark facet (the
            # compass-rose bevel). The long star wins where they overlap (round the hub).
            q = int(((ang + TAU / 8) % TAU) // (TAU / 4)) % 4   # nearest cardinal: 0 N, 1 E, 2 S, 3 W
            dl = (ang - q * TAU / 4 + math.pi) % TAU - math.pi    # signed angle from its axis (+ = clockwise side)
            al = 1.0 - abs(dl) / (TAU / 8)
            if r <= STAR_HUB + ((STAR_NORTH if q == 0 else STAR_LONG) - STAR_HUB) * al ** P_LONG:
                key = "CsGold" if dl >= 0 else "CsGoldDark"
                cells[(i, 1, k)] = key
                cells[(i, 0, k)] = key
                continue
            ds = ang % (TAU / 4) - TAU / 8                        # signed angle from the nearest diagonal
            if r <= STAR_HUB + (STAR_SHORT - STAR_HUB) * (1.0 - abs(ds) / (TAU / 8)) ** P_SHORT:
                key = "CsCream" if ds >= 0 else "CsCreamDark"
                cells[(i, 1, k)] = key
                cells[(i, 0, k)] = key
    # the hub: a gold boss (rows 1) with a violet pin (row 2)
    for i in range(-8, 9):
        for k in range(-8, 9):
            r = math.hypot(i * v, k * v)
            if r <= 1.15:
                cells[(i, 1, k)] = "CsGoldDark" if r > 0.95 else "CsGold"
                cells[(i, 0, k)] = "CsGold"
            if r <= 0.4:
                cells[(i, 2, k)] = "CsVioletDark"
    # the repair plate: a square steel plate bolted over one short point (front left seen from the spawn), its edges
    # square to that point's axis (a diamond seen from the north, as in option A); four rivet heads stand proud (row 2)
    pc = (2.35, -2.35)  # (x, z): where option A drew it
    for i in range(-n, n + 1):
        for k in range(-n, n + 1):
            dx, dz = i * v - pc[0], k * v - pc[1]
            if max(abs((dx + dz) * c45), abs((dz - dx) * c45)) <= 0.9:
                cells[(i, 1, k)] = "CsSteel"
                if cells.get((i, 0, k)) in (None, "CsViolet"):
                    cells[(i, 0, k)] = "CsSteel"
    for (u, w) in ((-0.58, -0.58), (0.58, -0.58), (-0.58, 0.58), (0.58, 0.58)):
        i, k = int(round((pc[0] + (u - w) * c45) / v)), int(round((pc[1] + (u + w) * c45) / v))
        cells[(i, 1, k)] = "CsRivet"
        cells[(i, 2, k)] = "CsRivet"
    for (i, j, k), key in cells.items():
        g.L[i + g.half, j + g.half, k + g.half] = g.kid(key)
    S.flat |= {"CsRivet"}


# ------------------------------------------------------------------------------------------------- bodies
def _cloud(S, name):
    """one weather cloud: a fat base, three bumps on top, a crown puff; flat bottom on the seat (y 0)"""
    c = CAST[name]
    w, h, d = c["body"]
    seed = c["seed"]
    g = S.g
    S.tint["Cloud"] = ["Primary"]
    S.tint["CloudLow"] = ["darken", ["Primary"], 0.12]
    g.ell("Cloud", (0, h * 0.36, 0), (w / 2, h * 0.38, d / 2))
    for k in range(3):
        bx = (k - 1) * (w / 3) * 0.9 + (hsh(seed, k, 1) - 0.5) * 0.4
        r = (0.72 + hsh(seed, k, 2) * 0.22) * w / 3.2
        g.ell("Cloud", (bx, h * 0.6 + hsh(seed, k, 3) * 0.3 * h / 2.8, (hsh(seed, k, 4) - 0.5) * 0.3), (r, r * 0.95, r * 0.9))
    g.ell("Cloud", (0.1 * (hsh(seed, 9, 1) - 0.5), h * 0.78, 0), (w * 0.27, h * 0.24, d * 0.3))
    # side puffs low down so it sits like a cloud, not a ball
    for sx in (-1, 1):
        g.ell("Cloud", (sx * w * 0.38, h * 0.2, 0.1), (w * 0.2, h * 0.2, d * 0.36))
    g.carve("box", center=(0, -2.0, 0), size=(w + 4, 4.0, d + 4))
    # a darker, heavier belly (clouds are darker underneath)
    S.paint("CloudLow", "box", only=["Cloud"], center=(0, h * 0.06, 0), size=(w + 2, h * 0.16, d + 2))
    return w, h, d


def _face(S, name, w, h, d):
    """eyes (2 x 3 voxels with a glint), a mouth per mood, blush; painted on the front surface"""
    mood = CAST[name]["mood"]
    v = 1.0 / S.K
    fz = -d / 2
    ey = h * {"drizzle": 0.5, "snow": 0.55}.get(name, 0.45)
    ex = 0.42 * w / 3.2 + 0.12
    only = ["Cloud"]
    for sx in (-1, 1):
        x0 = sx * ex - v
        if mood == "sleepy":
            _vox_paint(S, "CsInk", only, x0, ey, fz, 2, 1)
            _vox_paint(S, "CsInk", only, x0 + (v if sx < 0 else 0), ey - v, fz, 1, 1)  # droopy lid corner
        elif mood == "focus":
            # the drummer: round 2 x 2 eyes with a glint, fixed on his drum (his tongue pokes out as he counts). The first
            # build's 2 x 3 eyes read as tall bars on his small face; a brow does not fit (his face lobe ends one voxel
            # above the eyes, and a brow painted higher lands on the bump behind and floats)
            _vox_paint(S, "CsInk", only, x0, ey - v, fz, 2, 2, depth=1.2)
            _vox_paint(S, "CsGlint", ["CsInk"], x0 + (0 if sx < 0 else v), ey, fz, 1, 1, depth=1.2)
        else:
            _vox_paint(S, "CsInk", only, x0, ey - v, fz, 2, 3)
            _vox_paint(S, "CsGlint", ["CsInk"], x0 + (0 if sx < 0 else v), ey + v, fz, 1, 1)
        if mood == "grump":  # bushy storm brows slanting down to the nose
            for k in range(3):
                _vox_paint(S, "CsBrow", only, sx * (ex + v) - (k * sx) * v - v / 2, ey + 3 * v - k * v * 0.5 + v * 0.5, fz, 1, 1)
        if mood in ("beam", "focus", "smile", "whistle"):
            _vox_paint(S, "CsBlush", only, sx * (ex + 2 * v) - v, ey - 3 * v, fz, 2, 1)
    my = ey - 3 * v
    if mood in ("smile", "beam"):
        _vox_paint(S, "CsMouth", only, -v, my - v, fz, 2, 1)
        _vox_paint(S, "CsMouth", only, -2 * v, my, fz, 1, 1)
        _vox_paint(S, "CsMouth", only, v, my, fz, 1, 1)
        if mood == "beam":
            _vox_paint(S, "CsMouth", only, -v, my - 2 * v, fz, 2, 1)
    elif mood == "grump":
        _vox_paint(S, "CsInk", only, -2 * v, my - v, fz, 4, 1)
        _vox_paint(S, "CsInk", only, -3 * v, my - 2 * v, fz, 1, 1)
        _vox_paint(S, "CsInk", only, 2 * v, my - 2 * v, fz, 1, 1)
    elif mood == "whistle":
        _vox_paint(S, "CsMouth", only, 0, my - v, fz, 1, 2)
    elif mood == "focus":  # concentrating drummer: a little tongue out of the corner of the mouth
        _vox_paint(S, "CsMouth", only, -v, my, fz, 2, 1)
        _vox_paint(S, "CsTongue", only, 0, my - v, fz, 1, 1)
    elif mood == "sleepy":
        _vox_paint(S, "CsMouth", only, 0, my, fz, 1, 1)
    S.flat |= {"CsInk", "CsGlint", "CsMouth", "CsTongue", "CsBlush", "CsBrow"}


def _extras(S, name, w, h, d):
    g = S.g
    TAU = 2 * math.pi
    if name == "rain":
        # dew beads on the belly front and a few hanging drops at the lip (the falling drips are a ParticleEmitter)
        for k, (x, y) in enumerate(((-0.8, 0.45), (0.2, 0.32), (0.95, 0.5))):
            g.ell("CsDrop", (x, y, -d / 2 + 0.05), (0.13, 0.18, 0.13))
    elif name == "sun":
        # seven rays round the upper half, set a little behind the face
        for k in range(7):
            a = math.pi * (k / 6.0)
            cx, cy = math.cos(a), math.sin(a)
            base = (cx * w * 0.38, h * 0.5 + cy * h * 0.42, 0.25)
            tip = (cx * (w * 0.5 + 0.6), h * 0.5 + cy * (h * 0.5 + 0.55), 0.25)
            g.cone("CsRay", base, tip, 0.3, 0.1)
        S.paint("CsRayTip", "ellipsoid", only=["CsRay"], center=(0, h * 0.5, 0.25), radius=(w * 0.5 + 0.55, h * 0.5 + 0.5, 2),
                pattern=lambda X, Y, Z, cur: ["CsRayTip" if ((X / (w * 0.5 + 0.55)) ** 2 + ((Y - h * 0.5) / (h * 0.5 + 0.5)) ** 2) > 0.62
                                              else False for X, Y in zip(X, Y)])
    elif name == "snow":
        # a muffler: a red scarf with white knitted (diagonal) stripes wound round him under the eyes, white across the
        # middle of the face and knotted at his right side with the two tails hanging there. (The first build ran
        # red / white stripes straight under the eyes and over their lower half, where they read as a red mouth full of
        # teeth; his eyes now sit higher and clear of it.)
        band_lo, band_hi = h * 0.15, h * 0.31
        g.ell("CsScarf", (0, h * 0.36, 0), (w / 2 + 0.34, h * 0.38 + 0.12, d / 2 + 0.16), keep=True)
        g.carve("box", only="CsScarf", center=(0, band_hi + 2.0, 0), size=(w + 4, 4.0, d + 4))
        g.carve("box", only="CsScarf", center=(0, band_lo - 2.0, 0), size=(w + 4, 4.0, d + 4))
        kx = 0.95  # the knot, at the front of his right side
        g.ell("CsScarf", (kx, (band_lo + band_hi) / 2, -d / 2 + 0.12), (0.3, 0.26, 0.24))
        g.cap("CsScarf", (kx + 0.06, band_lo, -d / 2 + 0.05), (kx + 0.24, 0.16, -d / 2 - 0.02), 0.17, 0.15)
        g.cap("CsScarf", (kx - 0.12, band_lo, -d / 2 + 0.05), (kx - 0.16, 0.26, -d / 2 - 0.04), 0.15, 0.13)

        def stripes(X, Y, Z, cur):
            ang = np.arctan2(X, -Z)
            band = np.floor((ang + math.pi) / (TAU / 20) + Y * S.K * 0.5).astype(int)  # knitted diagonal stripes
            out = []
            for k in range(len(X)):
                if Y[k] < band_lo - 0.02:  # the tails: crosswise stripes
                    out.append("CsScarfStripe" if int(round(Y[k] * S.K)) % 3 == 0 else False)
                elif Z[k] < 0 and abs(X[k]) < 0.6:  # white across the middle of his face
                    out.append("CsScarfStripe")
                else:
                    out.append("CsScarfStripe" if band[k] % 3 == 0 else False)
            return out
        g.shape("box", None, op="paint", only=["CsScarf"], center=(0, h * 0.3, 0), size=(w + 2, h, d + 2), pattern=stripes)
        # frost: a few icy-white sparkles on the body
        S.dots("CsGlint", ["Cloud"], 0.035, 61, cell=1)
    elif name == "breeze":
        # a swirl of lighter air on the right cheek / side (painted)
        for k in range(10):
            a = k * 0.62
            rr = 0.15 + k * 0.05
            S.paint("CsGlint", "ellipsoid", only=["Cloud"], center=(w * 0.38 + math.cos(a) * rr, h * 0.45 + math.sin(a) * rr, -0.2),
                    radius=(0.09, 0.09, 1.2))
    elif name == "fog":
        # fog trails: two flat wisps drifting off the sides at the bottom
        for sx in (-1, 1):
            g.ell("Cloud", (sx * (w / 2 + 0.2), 0.18, 0.25), (0.75, 0.2, 0.55))
            g.ell("Cloud", (sx * (w / 2 + 0.75), 0.12, 0.45), (0.45, 0.14, 0.35))
        g.carve("box", center=(0, -2.0, 0), size=(w + 6, 4.0, d + 4))
    elif name == "captain":
        # a brass medal (the old storm-fleet star) on his chest, left side
        g.box("CsMedal", (-0.95, h * 0.2, -d / 2 + 0.12), (0.3, 0.3, 0.25))
        g.box("CsPom", (-0.95, h * 0.2 + 0.25, -d / 2 + 0.12), (0.3, 0.2, 0.25))  # its red ribbon
    elif name == "drizzle":
        # the drum's white sling: from the drum's left hoop over the left shoulder (the drum is its own key)
        S.paint("CsStrap", "capsule", only=["Cloud"], a=(-0.62, h * 0.12, -d / 2), b=(-w * 0.47, h * 0.7, -d * 0.1), r=0.13)


# the drum hangs at the drummer's belly, tilted toward him (its head faces up and out): body-local frame
DRUM = {"at": (0.0, 0.44, -1.41), "tilt": -0.35, "R": 0.72, "H": 0.64}


def _drum(S):
    """the ship's side drum (pivot = its centre, axis = local Y): navy shell, red hoops, a cream calfskin head, cream
    zig-zag tension ropes with leather ears, the ship's gold star on the front"""
    g = S.g
    TAU = 2 * math.pi
    R, H = DRUM["R"], DRUM["H"]
    g.cone("CsDrumShell", (0, -H / 2, 0), (0, H / 2, 0), R, R)
    for y0 in (-H / 2, H / 2 - 0.14):
        g.cone("CsDrumRim", (0, y0, 0), (0, y0 + 0.14, 0), R + 0.06, R + 0.06)
    # the hoops are rings: the batter head sits a little below the top hoop's rim (the stick hits it there)
    g.carve("cone", a=(0, H / 2 - 0.07, 0), b=(0, H / 2 + 0.2, 0), r=R - 0.1, rb=R - 0.1)
    g.cone("CsDrumHead", (0, H / 2 - 0.13, 0), (0, H / 2 - 0.06, 0), R - 0.1, R - 0.1)

    def ropes(X, Y, Z, cur):
        ang = np.arctan2(X, Z)
        t = (Y - (-H / 2 + 0.12)) / (H - 0.24)
        u = (ang / TAU * 8.0) % 1.0
        tri = np.abs(u - 0.5) * 2
        on = (t > -0.1) & (t < 1.1) & (np.abs(tri - t) < 0.22)
        return ["CsDrumRope" if o else False for o in on]
    g.shape("box", None, op="paint", only=["CsDrumShell"], center=(0, 0, 0), size=(2 * R + 0.4, H, 2 * R + 0.4), pattern=ropes)
    # leather tuning ears on the ropes (mid height, 8 round the shell)
    for k in range(8):
        a = (k + 0.5) / 8 * TAU
        g.box("CsLeather", (math.sin(a) * (R + 0.02), -0.04, math.cos(a) * (R + 0.02)), (0.12, 0.12, 0.12), rot=angles(0, a, 0))
    # the ship's star on the front (-Z), between two ropes
    v = 1.0 / S.K
    for (dx, dy) in ((0, 0), (-1, 0), (1, 0), (0, 1), (0, -1)):
        S.paint("CsMedal", "box", only=["CsDrumShell", "CsDrumRope"], center=(dx * v, dy * v - 0.02, -R), size=(v * 0.98, v * 0.98, 0.3))
    S.flat |= {"CsDrumRope", "CsMedal"}


def _body(S, name):
    w, h, d = _cloud(S, name)
    _extras(S, name, w, h, d)
    _face(S, name, w, h, d)


# ------------------------------------------------------------------------------------------------- arms
STICK_YAW = 0.74   # each stick arm turns this far in toward the drum (L: -STICK_YAW, R: +STICK_YAW about Y)
SPYGLASS = {"eye": (-1.0, 0.02, -1.0), "end": (-1.0, 0.24, -2.35)}   # in the right shoulder's frame


def _arm(S, kind):
    g = S.g
    S.tint["Cloud"] = ["Primary"]
    if kind == "arm":
        g.cap("Cloud", (0, 0, 0), (0, -0.58, 0), 0.3, 0.27)
        g.ell("Cloud", (0, -0.74, -0.03), (0.34, 0.31, 0.34))
        g.ell("Cloud", (0.0, -0.72, -0.28), (0.15, 0.13, 0.15))  # a little thumb puff
    elif kind == "stick":
        # the stick tip rests on the drum head with the arm at its rest yaw (+-STICK_YAW)
        g.cap("Cloud", (0, 0, 0), (0, -0.3, -0.45), 0.27, 0.24)
        g.ell("Cloud", (0, -0.36, -0.55), (0.3, 0.28, 0.3))
        g.cap("CsStick", (0, -0.36, -0.62), (0, -0.72, -1.55), 0.09, 0.075)
        g.ell("CsStickTip", (0, -0.75, -1.6), (0.13, 0.13, 0.13))
        S.flat |= {"CsStickTip"}
    elif kind == "spyglass":
        # Fog's right arm holding the lookout's spyglass to his right eye (no rest yaw): the arm reaches in front of
        # him, the eyepiece at his eye, the tube pointing out over the ring; RingCrowdFx lets it droop as he dozes
        g.cap("Cloud", (0, 0, 0), (-0.45, -0.05, -1.0), 0.27, 0.25)
        g.ell("Cloud", (-0.55, -0.02, -1.2), (0.3, 0.28, 0.3))
        a, b = np.array(SPYGLASS["eye"]), np.array(SPYGLASS["end"])
        segs = [(0.0, 0.3, 0.12, "CsBrass"), (0.3, 0.62, 0.15, "CsLeather"), (0.62, 1.0, 0.18, "CsBrass")]
        for t0, t1, r, key in segs:
            g.cap(key, tuple(a + (b - a) * t0), tuple(a + (b - a) * t1), r)
        for t in (0.3, 0.62, 0.97):
            p = a + (b - a) * t
            g.cone("CsBrassDark", tuple(p - (b - a) * 0.025), tuple(p + (b - a) * 0.025), r + 0.06, r + 0.06)
        g.cap("CsGlint", tuple(b + (b - a) * 0.0), tuple(b + (b - a) * 0.015), 0.11)
        S.flat |= {"CsGlint"}


# ------------------------------------------------------------------------------------------------- caps
def _cap(S, kind):
    g = S.g
    if kind == "sailor":
        # French sailor bachi: navy band, flat white crown, red pompom, two navy ribbon tails at the back
        g.cone("CsCapNavy", (0, 0, 0), (0, 0.2, 0), 0.66, 0.68)
        g.cone("CsCapWhite", (0, 0.18, 0), (0, 0.42, 0), 0.72, 0.8)
        g.cone("CsCapWhite", (0, 0.42, 0), (0, 0.5, 0), 0.8, 0.7)
        g.ell("CsPom", (0, 0.62, 0), (0.2, 0.17, 0.2))
        for sx in (-1, 1):
            g.box("CsCapNavy", (sx * 0.14, -0.2, 0.68), (0.18, 0.5, 0.08), rot=angles(0.0, 0.0, sx * 0.18))
    else:
        # the captain's cap: navy crown (wider on top), gold band, black visor tilted down, gold badge (an anchor)
        g.cone("CsCapNavy", (0, 0, 0), (0, 0.3, 0), 0.8, 0.82)
        g.cone("CsGold", (0, 0.06, 0), (0, 0.22, 0), 0.84, 0.84)
        g.cone("CsCapNavy", (0, 0.3, 0), (0, 0.66, 0), 0.82, 1.02)
        g.cone("CsCapNavy", (0, 0.66, 0), (0, 0.74, 0), 1.02, 0.96)
        g.ell("CsVisor", (0, 0.04, -0.72), (0.66, 0.06, 0.42), rot=angles(-0.22, 0, 0))
        g.carve("box", only="CsVisor", center=(0, 0, 0.5), size=(3, 2, 1.5))
        # badge: an anchor in gold on the crown front
        v = 1.0 / S.K
        fz = -0.9
        for (dx, dy) in ((0, 0), (0, 1), (0, 2), (-1, 2), (1, 2), (-1, 0), (1, 0), (0, 3)):
            S.paint("CsMedal", "box", only=["CsCapNavy"], center=(dx * v, 0.36 + dy * v, fz), size=(v * 0.98, v * 0.98, 0.6))
        S.flat |= {"CsMedal"}


# ------------------------------------------------------------------------------------------------- rigging
RIG = {
    "mastX": 15.0, "mastZ": 5.0, "mastTop": 11.0,       # the two masts (x = +-mastX), beside the back step, on the deck
    "bellAt": (-15.0, 6.8, 3.65),                       # the bell's hang point (bracket end, west mast)
    "lifeAt": (-15.0, 4.1, 4.5),                        # the life ring centre (hung on the west mast's front)
    "coilAt": (15.4, 1.75, 1.7),                        # the rope coil on the front step's east end
    "lineSag": 1.6,
}


def _line_y(x):
    """the flag line's height at stand x (a sagging rope between the mast tops), relative to the mast top"""
    s = (x + RIG["mastX"]) / (2 * RIG["mastX"])
    return -0.25 - RIG["lineSag"] * math.sin(math.pi * s)


def _rig(S):
    g = S.g
    mx, mz, top = RIG["mastX"], RIG["mastZ"], RIG["mastTop"]
    for sx in (-1, 1):
        x = sx * mx
        g.box("CsMastFoot", (x, 0.35, mz), (1.1, 0.7, 1.1))                    # a stone step for the mast
        g.box("CsIron", (x, 0.74, mz), (0.8, 0.08, 0.8))                       # iron collar plate
        g.cap("CsMast", (x, 0.4, mz), (x, top, mz), 0.26, 0.2)
        S.dots("CsMastDark", "CsMast", 0.12, 7 + sx, cell=2)
        g.ell("CsMastCap", (x, top + 0.18, mz), (0.3, 0.26, 0.3))             # the truck (gilt ball)
        g.box("CsIron", (x, top - 0.3, mz), (0.7, 0.12, 0.12))                 # the halyard cleat bar
        for y in (2.2, 2.6):                                                    # belaying cleat low on the mast
            g.box("CsMastDark", (x, y, mz - 0.25), (0.5, 0.1, 0.12))
    # the bell bracket: an iron arm from the west mast toward the ring (-Z) with a hook
    bx, by, bz = RIG["bellAt"]
    g.box("CsIron", (bx, by + 0.12, (bz + mz) / 2 - 0.05), (0.14, 0.14, mz - bz + 0.25))
    g.cap("CsIron", (bx, by + 0.12, mz - 0.1), (bx, by - 0.45, mz - 0.25), 0.06)  # the brace
    # the life ring on the west mast's front: red / white quarters (8 segments), a rope grab-line
    lx, ly, lz = RIG["lifeAt"]
    g.torus("CsLifeWhite", (lx, ly, lz), 0.62, 0.22, rot=angles(math.pi / 2, 0, 0))

    def quarters(X, Y, Z, cur):
        a = np.arctan2(Y - ly, X - lx)
        q = np.floor((a + math.pi) / (math.pi / 4)).astype(int)
        return ["CsLifeRed" if k % 2 == 0 else False for k in q]
    g.shape("box", None, op="paint", only=["CsLifeWhite"], center=(lx, ly, lz), size=(2, 2, 1), pattern=quarters)
    g.box("CsLine", (lx, ly + 0.78, lz + 0.18), (0.08, 0.3, 0.08))  # its lashing to the mast
    # the rope coil on the front step's east end: two flat turns and the loose end
    cx, cy, cz = RIG["coilAt"]
    g.torus("CsRope", (cx, cy + 0.12, cz), 0.6, 0.14)
    g.torus("CsRope", (cx + 0.05, cy + 0.36, cz - 0.03), 0.45, 0.13)
    g.curve("CsRopeDark", [(cx - 0.45, cy + 0.36, cz), (cx - 0.9, cy + 0.15, cz - 0.4), (cx - 1.5, cy + 0.12, cz - 0.6)], 0.12)
    S.flat |= {"CsLine"}


FLAGS = "NIMBUSNIMBUS"


def _flags(S):
    """the signal-flag line, pivot = (0, mast top, mast z): a sagging rope with 12 code flags hanging under it"""
    g = S.g
    mx = RIG["mastX"]
    v = 1.0 / S.K
    pts = []
    for k in range(17):
        x = -mx + 2 * mx * k / 16
        pts.append((x, _line_y(x), 0.0))
    g.curve("CsLine", pts, 0.06, steps=4)
    n = len(FLAGS)
    size = 1.5
    for i, ch in enumerate(FLAGS):
        # seen from the ring (looking +Z) +X is on the viewer's left: flag 0 at the east (+X) end reads first
        x = mx - 2 * mx * (i + 1) / (n + 1)
        x = round(x * S.K) / S.K
        ytop = math.floor((_line_y(x) - 0.12) * S.K) / S.K
        x0 = x - size / 2
        cells = {}
        m = int(round(size * S.K))  # 6 x 6 voxels
        for a in range(m):
            for b in range(m):
                col = None
                if ch == "N":
                    col = "CsFlagBlue" if ((a // 2) + (b // 2)) % 2 == 0 else "CsFlagWhite"
                elif ch == "I":
                    col = "CsFlagBlack" if 2 <= a <= 3 and 2 <= b <= 3 else "CsFlagYellow"
                elif ch == "M":
                    col = "CsFlagWhite" if (a == b or a == m - 1 - b) else "CsFlagBlue"
                elif ch == "B":
                    col = "CsFlagRed"
                    if a >= m - 2 and 2 <= b <= 3:  # the swallowtail notch
                        col = None
                elif ch == "U":
                    col = "CsFlagRed" if (a < m // 2) == (b < m // 2) else "CsFlagWhite"
                elif ch == "S":
                    col = "CsFlagBlue" if 2 <= a <= 3 and 2 <= b <= 3 else "CsFlagWhite"
                if col:
                    cells[(a, b)] = col
        for (a, b), col in cells.items():  # a = 0 is the hoist (the viewer's left = +X side)
            g.box(col, (x0 + (m - 1 - a) * v, ytop - b * v, 0.0), (v * 0.98, v * 0.98, v * 0.98))
        # the toggle: a short line from the rope to the flag's corners
        g.box("CsLine", (x0, ytop + v, 0.0), (v * 0.98, v * 0.98, v * 0.98))
        g.box("CsLine", (x0 + (m - 1) * v, ytop + v, 0.0), (v * 0.98, v * 0.98, v * 0.98))
    S.flat |= {"CsFlagRed", "CsFlagWhite", "CsFlagBlue", "CsFlagYellow", "CsFlagBlack", "CsLine"}


def _bell(S):
    """the ship's bell: a crown loop, a tall brass body flaring to a thick lip (darker bands), the clapper ball under
    the lip and a short tan lanyard with a knot"""
    g = S.g
    g.torus("CsBellDark", (0, -0.14, 0), 0.12, 0.05, rot=angles(math.pi / 2, 0, 0))     # the crown loop
    g.cone("CsBell", (0, -0.24, 0), (0, -0.34, 0), 0.22, 0.34)                         # the shoulder
    g.cone("CsBell", (0, -0.34, 0), (0, -0.9, 0), 0.36, 0.42)                          # the waist
    g.cone("CsBell", (0, -0.9, 0), (0, -1.1, 0), 0.42, 0.56)                           # the flare
    g.cone("CsBell", (0, -1.1, 0), (0, -1.18, 0), 0.56, 0.56)                          # the lip
    g.carve("cone", a=(0, -1.19, 0), b=(0, -0.8, 0), r=0.44, rb=0.28, only="CsBell")    # hollow mouth
    S.paint("CsBellDark", "cone", only=["CsBell"], a=(0, -1.18, 0), b=(0, -1.08, 0), r=0.7, rb=0.7)
    S.paint("CsBellDark", "cone", only=["CsBell"], a=(0, -0.46, 0), b=(0, -0.4, 0), r=0.6, rb=0.6)
    g.cap("CsClapper", (0, -0.6, 0), (0, -1.12, 0), 0.05)
    g.ell("CsClapper", (0, -1.2, 0), (0.12, 0.12, 0.12))
    g.curve("CsRope", [(0, -1.3, 0), (0.03, -1.55, -0.02), (0.0, -1.78, 0.02)], 0.055)  # the lanyard
    g.ell("CsRopeDark", (0.0, -1.84, 0.02), (0.1, 0.11, 0.1))                           # its knot


# ------------------------------------------------------------------------------------------------- builder
PARTS = {
    "emblem": (4.0, 8.0), "arm": (4.0, 1.6), "stick": (4.0, 2.0), "spyglass": (6.0, 2.8), "drum": (8.0, 1.0),
    "cap": (4.0, 1.4), "captaincap": (4.0, 1.4), "rig": (4.0, 17.0), "flags": (4.0, 17.0), "bell": (6.0, 2.4),
}


@prop("arena_crowd")
def arena_crowd(entry, kit):
    """Sky-Sailors' Ring (bug #11): args.part = emblem | body | arm | stick | spyglass | cap | captaincap | rig |
    flags | bell (body: args.name = one of CAST)"""
    args = entry.get("args") or {}
    part = args.get("part", "body")
    name = args.get("name")
    if part == "body":
        K = float(args.get("K", 4.0))
        S = _sculpt(kit, K, 4.6)
        _body(S, name)
        offset = _feet(S)
        cap, tilt, shL, shR = body_frame(name)
        group = "Body"
        look = {"Primary": list(CAST[name]["tint"])}
    else:
        K0, ext = PARTS[part]
        K = float(args.get("K", K0))
        S = _sculpt(kit, K, ext)
        group = {"emblem": "Emblem", "rig": "Rig", "flags": "Flags", "bell": "Bell", "drum": "Drum"}.get(part, "Piece")
        offset = (0.0, 0.0, 0.0)
        look = None
        if part == "emblem":
            _emblem(S)
            offset = (0.0, 0.5 / S.K - 0.0625, 0.0)  # row 0 spans -0.06..0.19 (0.12 proud of the baked floor)
        elif part in ("arm", "stick", "spyglass"):
            _arm(S, part)
            look = {"Primary": [204, 214, 236]}
        elif part in ("cap", "captaincap"):
            _cap(S, "sailor" if part == "cap" else "captain")
            offset = _feet(S)
        elif part == "rig":
            _rig(S)  # no feet offset: the bracket must meet the bell key's hang point exactly
        elif part == "flags":
            _flags(S)
        elif part == "bell":
            _bell(S)
        elif part == "drum":
            _drum(S)
    m = kit.model(entry["key"], "prop", vs=1.0 / K, K=K)
    S.mesh(m, group=group, offset=offset)
    meta = {"source": "Sky-Sailors' Ring (bug #11, plaza-logo-crowd pitch option A + the drummer) %s%s"
            % (part, (":" + name) if name else ""),
            "pivot": {"emblem": "the pocket floor centre, +Z = north (the champion)",
                      "body": "the seat point under the body, -Z = the face",
                      "arm": "the shoulder", "stick": "the shoulder", "spyglass": "the shoulder",
                      "cap": "the cap's bottom centre", "captaincap": "the cap's bottom centre",
                      "rig": "the stand's origin (deck under its front edge)",
                      "flags": "the flag line's mid point between the mast tops (stand-local (0, mastTop, mastZ))",
                      "bell": "the bell's hang point", "drum": "the drum's centre (axis = local Y)"}[part]}
    finish(m, meta, look)
    if part == "body":
        m.attachments = {"Cap": {"pos": list(cap), "rot": np.eye(3).tolist()},
                         "ShoulderL": {"pos": list(shL), "rot": np.eye(3).tolist()},
                         "ShoulderR": {"pos": list(shR), "rot": np.eye(3).tolist()}}
    return m
