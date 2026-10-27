"""Sky-Oasis Steps: the plaza fountain the player picked for bug #13 (option C of the waterfall pitch, 2026-10-27).

The story the shapes follow: three chunks of a broken sky-island came down by the plaza.  The first settlers propped
them on drum-stone pillars round a mossy rock pool and left the spring on the top chunk running; Nimbus nests up there.
Water drops island to island: the spring (top) -> a small fall onto the middle island -> its stream -> the big fall
into the pool, and a seep on the low island feeds a small fall on the west side.  The settlers' kids made the climb:
stepping stones out of the pool, a lashed wooden ladder (low -> middle), a knotted rope tied to a stake (middle -> top).

Keys (blender/catalog/lobby.json, pivot = the ground point under the pool centre, -Z = the front, toward the spawn):
    prop_oasis_pool      the rock pool: boulder rim with moss and tufts, pebbled floor, stepping stones, sign post
    prop_oasis_islands   the three islands, pillars, roots, tree, nest, spring rock, ladder, rope, lantern
    prop_oasis_water     the translucent water: the pool surface, the streams cut into the islands, the spring basin
    prop_oasis_boat      the paper boat (its own key: FountainFx bobs it, the mesh rides the root part, ML_Weld)
The falls themselves are Beams and the splashes ParticleEmitters (LobbyBuilder buildFountain); no mesh.

LAYOUT is mirrored by LobbyBuilder.lua (OASIS): the Part build there is the collider and the fallback.  Keep both in step
(tools/smoke_bug13_fountain.lua checks the Lua numbers against the committed manifests' bounds).
"""
import math

import numpy as np

from nvox.grid import angles
from props import prop
from props.lobby import PAL, NEON, Sculpt, finish, hsh, rgb

PAL.update({
    "Rock": (170, 170, 186), "RockDark": (140, 142, 160), "RockLight": (196, 198, 212), "RockDeep": (118, 120, 140),
    "Moss": (118, 176, 92), "MossDark": (94, 152, 80), "Tuft": (138, 206, 104),
    "Dirt": (150, 106, 72), "DirtDark": (120, 84, 58), "DirtLight": (172, 128, 88), "Root": (122, 86, 56),
    "GrassWorn": (160, 196, 104), "Twig": (156, 112, 70), "TwigDark": (118, 84, 54), "Straw": (226, 196, 128),
    "PoolFloor": (112, 132, 156), "Pebble": (150, 162, 182), "PebbleLight": (168, 178, 196),
    "Rope": (214, 192, 142), "RopeDark": (150, 118, 76), "Paper": (250, 248, 240), "PaperFold": (222, 226, 236),
    "PaperRed": (232, 104, 96),
    "SignPaint": (122, 170, 206),
    "Cut": (255, 0, 255),  # a carve marker (painted, then carved away: never meshed)
})

# ------------------------------------------------------------------------------------------------- layout (studs)
LAYOUT = {
    "poolIn": 8.6,          # inner radius of the rim wall (the water reaches it)
    "rimR": 9.55,           # boulder centre line
    "rimOut": 10.7,         # outer extent of the boulders
    "water": 1.25,          # water surface height (= the water key's top voxel face at K 2)
    "floor": 0.3,           # pool floor top
    # islands: centre x, z, grass top y, radii x / z, underside depth
    "islands": [
        {"c": (-3.8, -0.6), "top": 4.0, "r": (3.4, 3.2), "depth": 2.6},   # the chunk that fell into the pool
        {"c": (3.0, -1.0), "top": 7.4, "r": (3.4, 3.3), "depth": 2.6},
        {"c": (-0.6, 4.0), "top": 10.4, "r": (4.3, 3.4), "depth": 3.0},
    ],
    # stepping stones: x, z, top y, radius
    "stones": [(-2.3, -7.0, 2.0, 1.05), (-3.6, -5.3, 3.0, 0.95)],
    # the two climbs. Each is a Roblox TrussPart in the Part build (2 x 2 studs, invisible, reliable climbing) whose
    # top is a plank landing the settlers built out from the upper island's rim; the ladder / the knotted rope hang on
    # the truss face the player climbs (-X for the ladder, -Z for the rope). c = truss centre (x, z), y0 / y1 = ends.
    "ladder": {"c": (-1.4, -0.85), "y0": 3.55, "y1": 7.55, "face": (-1, 0), "deck": (-2.45, -0.25)},
    "rope": {"c": (2.3, 0.5), "y0": 6.6, "y1": 10.6, "face": (0, -1), "deck": (-0.55, 1.55)},
    # Nimbus's nest on island 3 (the statue sits on the nest floor, faces -Z)
    "nest": {"c": (-0.9, 4.7), "r": 2.35, "floor": 10.5},
    "spring": (2.0, 5.6),            # the spring rock on island 3
    "seep": (-5.0, 1.0),             # the seep rock on island 1
    "tree": (-6.0, -1.7),            # the young tree on island 1
    "lantern": (5.4, 0.6),           # the lantern post on island 2
    # streams (cut into the grass) and the falls they feed: lip (x, y, z), outward direction (x, z), landing y
    "streams": [
        [(2.0, 4.8), (2.7, 3.4), (3.15, 2.35)],         # island 3: spring -> right rim
        [(3.75, 1.75), (3.85, -0.8), (3.6, -4.2)],     # island 2: under the small fall -> front rim
        [(-5.0, 1.0), (-5.9, 1.1), (-6.75, 1.05)],     # island 1: seep -> west rim
    ],
    "falls": [
        {"lip": (3.25, 10.25, 2.25), "dir": (0.81, -0.59), "land": 7.5, "width": 1.0},   # top -> middle
        {"lip": (3.6, 7.25, -4.35), "dir": (0.12, -0.99), "land": 1.25, "width": 1.9},   # middle -> pool (the big one)
        {"lip": (-6.85, 3.85, 1.05), "dir": (-0.95, 0.31), "land": 1.25, "width": 1.0}, # low -> pool (west)
    ],
    "sign": {"pos": (-6.45, -9.2), "face": (-0.57, -0.82)},  # on the plaza, just outside the rim, front-left
    "boat": (0.7, -6.3),
    "lilies": [(-6.7, -3.6, 0.75, 0.6), (1.9, -7.5, 0.6, 2.2), (6.3, 3.4, 0.7, 4.0), (-5.6, 5.4, 0.6, 1.3)],
}

ROCK = ["Rock", "RockDark", "RockLight"]


def _ell_inside(x, z, c, r, pad=0.0):
    return ((x - c[0]) / (r[0] + pad)) ** 2 + ((z - c[1]) / (r[1] + pad)) ** 2 <= 1.0


def _seg_dist(x, z, pts):
    best = 1e9
    for (ax, az), (bx, bz) in zip(pts[:-1], pts[1:]):
        vx, vz = bx - ax, bz - az
        L2 = vx * vx + vz * vz
        t = max(0.0, min(1.0, ((x - ax) * vx + (z - az) * vz) / L2)) if L2 > 1e-9 else 0.0
        best = min(best, math.hypot(x - (ax + vx * t), z - (az + vz * t)))
    return best


# ------------------------------------------------------------------------------------------------- pool
def _pool(S):
    L = LAYOUT
    g = S.g
    # the rim wall the boulders sit on (keeps the water in; hidden behind / between them)
    S.cyl("RockDark", 0, 0, -0.2, 1.35, L["poolIn"] + 1.1)
    g.carve("cone", a=(0, -0.3, 0), b=(0, 1.5, 0), r=L["poolIn"], rb=L["poolIn"], only="RockDark")
    S.cyl("PoolFloor", 0, 0, -0.2, L["floor"], L["poolIn"] + 0.05)
    # boulders: 21 round the ring, sizes / heights / spacing by hash so no two neighbours match
    n = 21
    for i in range(n):
        a = (i + (hsh(i, 1, 21) - 0.5) * 0.35) / n * math.pi * 2
        rr = L["rimR"] + (hsh(i, 2, 21) - 0.5) * 0.4
        tang = 1.25 + hsh(i, 3, 21) * 0.5
        rad = 0.95 + hsh(i, 4, 21) * 0.25
        hy = 0.95 + hsh(i, 5, 21) * 0.4
        top = 1.55 + hsh(i, 6, 21) * 0.7
        key = "RockDark" if i % 4 == 1 else "Rock"
        S.ell(key, (math.cos(a) * rr, top - hy, math.sin(a) * rr), (rad, hy, tang), rot=angles(0, -a, 0))
        if hsh(i, 7, 21) < 0.55:  # a smaller stone wedged on top / beside
            a2 = a + (hsh(i, 8, 21) - 0.5) * 0.12
            S.ell("RockLight", (math.cos(a2) * (rr + 0.2), top - 0.05, math.sin(a2) * (rr + 0.2)),
                  (0.55, 0.42, 0.7), rot=angles(0, -a2, 0))
    g.carve("box", center=(0, -2.0, 0), size=(26, 3.6, 26))  # nothing under the plaza
    # weathering: light chips on the tops, dark pits on the sides, moss on the wet inside and the shady back (+Z)
    S.dots("RockLight", ["Rock", "RockDark"], 0.08, 31, cell=2)
    S.dots("RockDeep", ["Rock", "RockDark"], 0.05, 32, cell=1)

    def moss(x, y, z, cur):
        X, Y, Z = x, y, z
        r = np.sqrt(X * X + Z * Z)
        inner = r < L["rimR"] - 0.2
        back = Z > 2.0
        h = np.array([hsh(int(a * 3), int(b * 3), int(c * 3), 41) for a, b, c in zip(X, Y, Z)])
        top = Y > 1.35
        out = []
        for k in range(len(X)):
            p = 0.0
            if top[k]:
                p = 0.5 if (inner[k] or back[k]) else 0.22
            elif inner[k] and Y[k] > 0.9:
                p = 0.25
            if h[k] < p:
                out.append("MossDark" if h[k] < p * 0.3 else "Moss")
            else:
                out.append(False)
        return out
    g.shape("box", None, op="paint", only=ROCK + ["RockDeep"], center=(0, 1.5, 0), size=(24, 3.2, 24), pattern=moss)
    # grass tufts poking out of the moss (little 3-blade clumps)
    for i in range(11):
        a = (i + hsh(i, 9, 21)) / 11 * math.pi * 2
        rr = L["rimR"] + (hsh(i, 10, 21) - 0.5) * 0.9
        x, z = math.cos(a) * rr, math.sin(a) * rr
        y = 2.35
        for b in range(3):
            ox, oz = (b - 1) * 0.16, (hsh(i, b, 22) - 0.5) * 0.2
            hgt = 0.35 + hsh(i, b, 23) * 0.3
            S.box("Tuft", (x + ox, y + hgt / 2 - 0.25, z + oz), (0.12, hgt + 0.3, 0.12), keep=True)
    # pool floor: pebbles and a few flat stones (seen through the water)
    for i in range(18):  # (was 40 with 14 tufts: 2 tris under budget; now ~340 tris of headroom for later tweaks)
        a = hsh(i, 1, 51) * math.pi * 2
        rr = 1.0 + math.sqrt(hsh(i, 2, 51)) * (L["poolIn"] - 1.4)
        x, z = math.cos(a) * rr, math.sin(a) * rr
        s = 0.18 + hsh(i, 3, 51) * 0.25
        S.ell("Pebble" if i % 4 else "PebbleLight", (x, L["floor"] + 0.02, z), (s * 1.3, s * 0.6, s), keep=True)
    # stepping stones: flat-topped, worn smooth on top, moss collar at the waterline
    for i, (x, z, top, r) in enumerate(L["stones"]):
        # a rounded boulder (wider at the waterline), its top worn flat by feet, a smaller stone leaning on its side
        S.ell("RockDark", (x, top * 0.45, z), (r * 1.12, top * 0.62, r * 1.0), rot=angles(0, 0.6 * i, 0))
        S.ell("Rock", (x + 0.05, top - 0.42, z - 0.05), (r * 0.98, 0.55, r * 0.9), rot=angles(0, 0.6 * i + 0.4, 0))
        g.carve("box", center=(x, top + 0.6, z), size=(3, 1.2, 3), only=["Rock", "RockDark"])
        S.ell("RockLight", (x + r * 0.85, L["water"] + 0.1, z + r * 0.35), (0.45, 0.4, 0.5))
        S.paint("RockLight", "cone", only=["Rock"], a=(x, top - 0.05, z), b=(x, top + 0.05, z), r=r * 0.55, rb=r * 0.55)
        S.paint("Moss", "cone", only=["RockDark", "Rock"], a=(x, L["water"] - 0.1, z), b=(x, L["water"] + 0.35, z),
                r=r + 0.3, rb=r + 0.3)
    # lily pads (one in flower) in the calm corners, away from the falls, the stones and the boat's drift
    for i, (x, z, r, ang) in enumerate(L["lilies"]):
        S.cyl("LeafDark" if i % 2 else "Leaf", x, z, L["water"] - 0.2, L["water"] - 0.06, r)  # one voxel: top 1.30
        g.carve("box", center=(x + math.cos(ang) * r * 0.6, L["water"] + 0.05, z + math.sin(ang) * r * 0.6),
                size=(r * 1.2, 0.5, 0.22), rot=angles(0, -ang, 0), only=["Leaf", "LeafDark"])
        S.paint("LeafLight", "cone", only=["Leaf", "LeafDark"], a=(x, L["water"] + 0.08, z), b=(x, L["water"] + 0.2, z),
                r=r * 0.35, rb=r * 0.35)
        if i == 0:
            for k in range(6):
                a = k / 6 * math.pi * 2
                S.ell("Blossom", (x - 0.1 + math.cos(a) * 0.22, L["water"] + 0.28, z + math.sin(a) * 0.22), (0.17, 0.14, 0.17))
            S.ell("Yellow", (x - 0.1, L["water"] + 0.36, z), (0.12, 0.1, 0.12))
    # the sign: two posts, a board of three weathered planks with a faded painted water drop and an up arrow (the
    # settlers' "spring - climb up" mark; the lettering wore off long ago), a drip cap on top
    sp, sf = L["sign"]["pos"], L["sign"]["face"]
    yaw = math.atan2(-sf[0], -sf[1])  # local -Z (the board's face) toward `face`
    R = angles(0, yaw, 0)

    def at(lx, ly, lz):
        v = R @ np.array([lx, ly, lz])
        return (sp[0] + v[0], v[1], sp[1] + v[2])
    for sx in (-1.15, 1.15):
        S.box("PlankDark", at(sx, 1.4, 0.12), (0.3, 2.8, 0.3), rot=R)
        S.box("PlankDark", at(sx, 2.86, 0.12), (0.4, 0.16, 0.4), rot=R)
    for k, (y, key) in enumerate(((1.62, "Plank"), (2.02, "PlankLight"), (2.42, "Plank"))):
        S.box(key, at((k - 1) * 0.06, y, -0.06), (2.55, 0.36, 0.22), rot=R)
    S.box("PlankLight", at(0, 2.75, 0.0), (2.8, 0.18, 0.4), rot=R)  # the drip cap
    wood = ["Plank", "PlankLight"]
    S.paint("SignPaint", "ellipsoid", only=wood, center=at(-0.45, 1.98, -0.2), radius=(0.3, 0.32, 0.2), rot=R)  # the drop
    S.paint("SignPaint", "box", only=wood, center=at(-0.45, 2.38, -0.2), size=(0.3, 0.3, 0.4), rot=R)
    S.paint("SignPaint", "box", only=wood, center=at(0.55, 1.95, -0.2), size=(0.3, 0.8, 0.4), rot=R)  # the arrow
    S.paint("SignPaint", "box", only=wood, center=at(0.55, 2.42, -0.2), size=(0.9, 0.3, 0.4), rot=R)
    S.flat |= {"SignPaint"}


# ------------------------------------------------------------------------------------------------- islands
def _island(S, I, seed, grass_extra=None):
    g = S.g
    cx, cz = I["c"]
    rx, rz = I["r"]
    top, depth = I["top"], I["depth"]
    # the broken underside: a thick soil band under the grass, then a craggy inverted cone of earth and rock down to a
    # stony tip (stacked, jittered ellipses: no two layers line up)
    S.ell("Dirt", (cx, top - 0.6, cz), (rx * 0.99, 1.0, rz * 0.99))
    n = max(4, int(depth / 0.45))
    for j in range(n + 1):
        t = j / n
        y = top - 1.2 - depth * t
        f = 0.12 + 0.82 * (1 - t) ** 0.85
        jx, jz = (hsh(j, 1, seed) - 0.5) * 0.5 * f, (hsh(j, 2, seed) - 0.5) * 0.5 * f
        key = "Rock" if t > 0.8 else ("DirtDark" if j % 3 == 2 else "Dirt")
        S.ell(key, (cx + jx, y, cz + jz), (rx * f, depth / n * 0.95 + 0.2, rz * f))
    for k in range(10):
        a = hsh(k, 1, seed) * math.pi * 2
        t = 0.1 + 0.75 * hsh(k, 3, seed)
        ly = top - 1.2 - depth * t
        f = 0.12 + 0.82 * (1 - t) ** 0.85
        px, pz = cx + math.cos(a) * rx * f * 0.92, cz + math.sin(a) * rz * f * 0.92
        s = 0.4 + hsh(k, 2, seed) * 0.45
        S.ell("DirtDark" if k % 3 == 0 else ("Rock" if k % 3 == 1 else "Dirt"), (px, ly, pz), (s, s * 0.85, s))
    g.carve("box", center=(cx, top + 4.0, cz), size=(rx * 2 + 3, 8.0, rz * 2 + 3),
            only=["Dirt", "DirtDark", "Rock", "RockDark", "RockLight"])
    for dy, key, th in ((0.85, "DirtDark", 0.2), (1.45, "DirtLight", 0.3), (2.1, "DirtDark", 0.22), (2.9, "RockDark", 0.2)):
        S.paint(key, "box", only=["Dirt"], center=(cx, top - dy, cz), size=(rx * 2 + 2, th, rz * 2 + 2))
    S.dots("DirtLight", ["Dirt"], 0.06, seed + 3, cell=2)
    S.dots("RockLight", ["Rock"], 0.1, seed + 4, cell=1)
    S.dots("Pebble", ["DirtDark"], 0.08, seed + 5, cell=1)
    # the grass cap: a slab with a soft, slightly overhanging lip, and grass drips over the edge
    S.ell("Grass", (cx, top - 0.3, cz), (rx + 0.12, 0.42, rz + 0.12))
    g.carve("box", center=(cx, top + 2.0, cz), size=(rx * 2 + 3, 4.0, rz * 2 + 3), only=["Grass"])
    for k in range(int(10 + (rx + rz) * 1.5)):
        a = (k + hsh(k, 6, seed) * 0.6) / int(10 + (rx + rz) * 1.5) * math.pi * 2
        px, pz = cx + math.cos(a) * (rx + 0.02), cz + math.sin(a) * (rz + 0.02)
        L = 0.25 + hsh(k, 7, seed) * 0.45
        S.ell("GrassDark" if k % 2 else "Grass", (px, top - 0.62 - L * 0.4, pz), (0.32, L * 0.6 + 0.15, 0.32))
    S.dots("GrassLight", ["Grass"], 0.16, seed + 6, cell=2)
    # hanging roots: thin curving strands from under the lip
    for k in range(6):
        a = hsh(k, 8, seed) * math.pi * 2
        px, pz = cx + math.cos(a) * rx * 0.72, cz + math.sin(a) * rz * 0.72
        y0 = top - 1.3
        Lr = 0.9 + hsh(k, 9, seed) * 1.3
        sw = (hsh(k, 10, seed) - 0.5) * 0.5
        S.g.curve("Root", [(px, y0, pz), (px * 1.0 + sw, y0 - Lr * 0.5, pz + sw * 0.5),
                           (px + math.cos(a) * 0.35, y0 - Lr, pz + math.sin(a) * 0.35)], 0.17, 0.1)


def _flower(S, x, y, z, key):
    S.box("Leaf", (x, y + 0.18, z), (0.1, 0.36, 0.1), keep=True)
    for a in range(4):
        ang = a / 4 * math.pi * 2 + 0.4
        S.box(key, (x + math.cos(ang) * 0.17, y + 0.42, z + math.sin(ang) * 0.17), (0.2, 0.14, 0.2), keep=True)
    S.box("Yellow", (x, y + 0.45, z), (0.14, 0.16, 0.14), keep=True)


def _islands(S):
    L = LAYOUT
    g = S.g
    I1, I2, I3 = L["islands"]
    # pillars first (the islands' undersides cover their heads): drum stones, a hair off-centre each, mortar seams,
    # moss on the shady side
    # (island 1 is the chunk that came down in the pool: it needs no pillar)
    for (cx, cz), y1, r, seed in (((I2["c"][0] - 0.1, I2["c"][1] + 0.2), I2["top"] - 3.5, 0.9, 62),
                                  ((I3["c"][0] + 0.2, I3["c"][1] + 0.1), I3["top"] - 3.9, 1.0, 63)):
        y = -0.1
        k = 0
        while y < y1:
            hgt = min(1.0 + hsh(k, 1, seed) * 0.35, y1 - y + 0.4)
            ox, oz = (hsh(k, 2, seed) - 0.5) * 0.16, (hsh(k, 3, seed) - 0.5) * 0.16
            rr = r * (0.94 + hsh(k, 4, seed) * 0.1)
            S.rbox("RockLight" if k % 2 else "Rock", (cx + ox, y + hgt / 2, cz + oz), (rr * 2, hgt - 0.08, rr * 2), 0.35)
            S.cyl("RockDeep", cx + ox, cz + oz, y + hgt - 0.1, y + hgt + 0.02, rr * 0.86)  # the seam
            y += hgt
            k += 1
        # moss in uneven creeping patches on the shady (back) side, thickest where the pool splashes it, thinning up
        # the column (one solid sheet read as a green placeholder from behind: Gemini's final review)
        tall = y1 > 5
        patches = ((1.0, 0.95, 0.25), (2.1, 0.7, -0.35), (y1 * 0.62, 0.55, 0.3), (y1 - 0.5, 0.45, -0.2)) if tall else             ((0.9, 0.8, 0.3), (y1 - 0.6, 0.45, -0.3))
        for py, pr, px in patches:
            S.paint("Moss", "ellipsoid", only=["Rock", "RockLight"], center=(cx + px, py, cz + r * 0.95),
                    radius=(pr * 1.1, pr, 0.45))
        S.dots("MossDark", ["Moss"], 0.2, seed + 9, cell=1)
        # the footing: a few fallen chunks and rubble round the foot, breaking the waterline (no pole stuck in a pond)
        for j in range(5):
            a = (j / 5.0 + hsh(j, 5, seed) * 0.12) * math.tau
            d = r + 0.35 + hsh(j, 6, seed) * 0.25
            hh = 0.9 + hsh(j, 7, seed) * 0.6
            S.rbox("Rock" if j % 2 else "RockLight", (cx + math.cos(a) * d, hh / 2, cz + math.sin(a) * d),
                   (0.7 + hsh(j, 8, seed) * 0.3, hh, 0.6 + hsh(j, 9, seed) * 0.3), 0.3)
        S.paint("Moss", "box", only=["Rock", "RockLight"], center=(cx, L["water"] + 0.15, cz), size=(r * 2 + 2.2, 0.3, r * 2 + 2.2))
    # an old repair on the tall pillar: a darker replaced drum (the settlers swapped a cracked one)
    S.paint("RockDark", "box", only=["Rock", "RockLight"], center=(I3["c"][0] + 0.2, 3.6, I3["c"][1] + 0.1), size=(3, 0.9, 3))
    for i, I in enumerate((I1, I2, I3)):
        _island(S, I, 70 + i * 11)
    # island 1 sits in the pool: a wet dark band and moss at the waterline
    S.paint("RockDeep", "cone", only=["Dirt", "DirtDark", "Rock", "DirtLight", "RockLight"], a=(I1["c"][0], 0.0, I1["c"][1]),
            b=(I1["c"][0], L["water"] + 0.05, I1["c"][1]), r=4.5, rb=4.5)
    S.paint("Moss", "cone", only=["Dirt", "DirtDark", "Rock", "DirtLight", "RockLight"], a=(I1["c"][0], L["water"] + 0.05, I1["c"][1]),
            b=(I1["c"][0], L["water"] + 0.45, I1["c"][1]), r=4.5, rb=4.5)
    # worn paths where players walk: stepping stones -> ladder on island 1, ladder -> rope on island 2
    def worn(path, top, w):
        def pat(x, y, z, cur):
            out = []
            for k in range(len(x)):
                d = _seg_dist(x[k], z[k], path)
                if d < w and hsh(int(x[k] * 4), int(z[k] * 4), 77) < 0.75 - d / w * 0.5:
                    out.append("GrassWorn")
                else:
                    out.append(False)
            return out
        g.shape("box", None, op="paint", only=["Grass", "GrassLight"], center=(0, top - 0.05, 0), size=(20, 0.12, 20),
                pattern=pat)
    worn([(-3.6, -3.6), (-3.4, -2.2), (-2.8, -0.85)], I1["top"], 0.65)
    worn([(-0.3, -0.85), (1.2, -1.1), (2.3, -1.0)], I2["top"], 0.6)
    worn([(2.0, 1.6), (1.0, 2.0), (0.0, 1.8)], I3["top"], 0.5)
    # streams: shallow channels cut into the grass (the water key fills them), pebbled beds, lips notched at the rims
    tops = (I3["top"], I2["top"], I1["top"])
    for pts, top in zip(L["streams"], tops):
        def chan(x, y, z, cur, pts=pts):
            return [None if _seg_dist(x[k], z[k], pts) < 0.42 else False for k in range(len(x))]
        bx0 = min(p[0] for p in pts) - 1
        bx1 = max(p[0] for p in pts) + 1
        bz0 = min(p[1] for p in pts) - 1
        bz1 = max(p[1] for p in pts) + 1
        cxm, czm = (bx0 + bx1) / 2, (bz0 + bz1) / 2
        # carve by pattern: the kit's carve has no pattern, so paint a marker key and carve it
        g.shape("box", "Cut", op="paint", center=(cxm, top - 0.15, czm), size=(bx1 - bx0, 0.32, bz1 - bz0), pattern=chan)
        g.carve("box", only="Cut", center=(cxm, top - 0.15, czm), size=(bx1 - bx0 + 1, 1, bz1 - bz0 + 1))

        def bed(x, y, z, cur, pts=pts):
            return ["Pebble" if (_seg_dist(x[k], z[k], pts) < 0.5 and hsh(int(x[k] * 3), int(z[k] * 3), 5) < 0.45) else False
                    for k in range(len(x))]
        g.shape("box", None, op="paint", center=(cxm, top - 0.45, czm), size=(bx1 - bx0, 0.25, bz1 - bz0), pattern=bed)
    # the spring rock on island 3 (water wells out of its foot) and the seep rock on island 1, both mossy
    sx, sz = L["spring"]
    S.ell("RockLight", (sx, I3["top"] + 0.35, sz), (0.95, 0.85, 0.75), rot=angles(0, 0.5, 0))
    S.ell("Rock", (sx + 0.6, I3["top"] + 0.15, sz + 0.35), (0.6, 0.5, 0.55))
    S.paint("Moss", "box", only=["Rock", "RockLight"], center=(sx, I3["top"] + 1.0, sz + 0.2), size=(2.4, 0.5, 2.0))
    g.carve("ellipsoid", only=["RockLight", "Rock"], center=(sx, I3["top"] + 0.05, sz - 0.6),
            radius=(0.35, 0.3, 0.4))
    ex, ez = L["seep"]
    S.ell("Rock", (ex, I1["top"] + 0.2, ez), (0.7, 0.6, 0.6), rot=angles(0, 1.0, 0))
    S.paint("Moss", "box", only=["Rock"], center=(ex, I1["top"] + 0.7, ez), size=(1.8, 0.35, 1.6))
    # Nimbus's twig nest: a woven ring with stick ends poking out and a straw floor
    nc, nr, nf = L["nest"]["c"], L["nest"]["r"], L["nest"]["floor"]
    S.cyl("Straw", nc[0], nc[1], I3["top"] - 0.05, nf, nr - 0.2)
    S.g.torus("Twig", (nc[0], nf + 0.25, nc[1]), nr, 0.42)
    S.g.torus("Twig", (nc[0], nf + 0.62, nc[1]), nr - 0.12, 0.3)

    def weave(x, y, z, cur):
        out = []
        for k in range(len(x)):
            ang = math.atan2(z[k] - nc[1], x[k] - nc[0])
            band = int((ang + math.pi) / (math.pi * 2) * 28 + y[k] * 2.2) % 2
            out.append("TwigDark" if band else False)
        return out
    g.shape("box", None, op="paint", only=["Twig"], center=(nc[0], nf + 0.4, nc[1]), size=(nr * 2 + 2, 1.4, nr * 2 + 2),
            pattern=weave)
    for k in range(9):
        a = (k + hsh(k, 1, 91) * 0.5) / 9 * math.pi * 2
        p0 = (nc[0] + math.cos(a) * (nr - 0.1), nf + 0.3 + hsh(k, 2, 91) * 0.4, nc[1] + math.sin(a) * (nr - 0.1))
        p1 = (nc[0] + math.cos(a + 0.25) * (nr + 0.75), p0[1] + 0.15, nc[1] + math.sin(a + 0.25) * (nr + 0.75))
        S.g.cap("TwigDark" if k % 2 else "Twig", p0, p1, 0.09)
    # the young tree on island 1: trunk with root flares, two blocky leaf clusters with light tops, a bird box
    tx, tz = L["tree"]
    ty = I1["top"]
    S.g.curve("Bark", [(tx, ty - 0.2, tz), (tx + 0.1, ty + 1.4, tz - 0.05), (tx - 0.05, ty + 2.6, tz + 0.05)], 0.32, 0.22)
    for a in (0.3, 2.2, 4.1):
        S.g.cap("Bark", (tx, ty + 0.25, tz), (tx + math.cos(a) * 0.6, ty - 0.05, tz + math.sin(a) * 0.6), 0.16, 0.08)
    S.g.cap("Bark", (tx, ty + 1.8, tz), (tx + 0.7, ty + 2.5, tz - 0.2), 0.12, 0.08)
    for c, r in (((tx, ty + 3.3, tz), (1.35, 1.05, 1.3)), ((tx + 0.75, ty + 2.75, tz - 0.25), (0.85, 0.7, 0.85)),
                 ((tx - 0.65, ty + 2.85, tz + 0.35), (0.8, 0.7, 0.8)), ((tx + 0.15, ty + 3.95, tz + 0.1), (0.8, 0.6, 0.8))):
        S.ell("Leaf", c, r)
    S.dots("LeafLight", ["Leaf"], 0.18, 93, cell=2)
    S.dots("LeafDark", ["Leaf"], 0.1, 94, cell=2)
    S.rbox("PlankLight", (tx + 0.02, ty + 1.65, tz - 0.42), (0.42, 0.5, 0.34), 0.06)  # a bird box nailed to the trunk
    S.box("PlankDark", (tx + 0.02, ty + 1.95, tz - 0.44), (0.52, 0.08, 0.42))
    S.box("Dark", (tx + 0.02, ty + 1.7, tz - 0.6), (0.12, 0.12, 0.06))
    # flowers on every island (not on paths / streams)
    fl = 0
    for I, seed in ((I1, 101), (I2, 102), (I3, 103)):
        cx, cz = I["c"]
        rx, rz = I["r"]
        for k in range(14):
            a = hsh(k, 1, seed) * math.pi * 2
            rr = 0.35 + 0.55 * math.sqrt(hsh(k, 2, seed))
            x, z = cx + math.cos(a) * rx * rr, cz + math.sin(a) * rz * rr
            if any(_seg_dist(x, z, p) < 0.8 for p in L["streams"]):
                continue
            if I is I1 and (_seg_dist(x, z, [(-3.6, -3.6), (-3.4, -2.2), (-2.8, -0.85)]) < 0.9 or abs(x - L["ladder"]["c"][0]) < 1.3 and abs(z - L["ladder"]["c"][1]) < 1.3 or math.hypot(x - L["tree"][0], z - L["tree"][1]) < 0.9):
                continue
            if I is I2 and (_seg_dist(x, z, [(-0.3, -0.85), (1.2, -1.1), (2.3, -1.0)]) < 0.9 or abs(x - L["rope"]["c"][0]) < 1.4 and abs(z - L["rope"]["c"][1]) < 1.4 or math.hypot(x - L["lantern"][0], z - L["lantern"][1]) < 0.7):
                continue
            if I is I3 and (math.hypot(x - nc[0], z - nc[1]) < nr + 0.6 or math.hypot(x - L["spring"][0], z - L["spring"][1]) < 1.3
                            or _seg_dist(x, z, [(2.0, 1.6), (1.0, 2.0), (0.0, 1.8)]) < 0.7):
                continue
            _flower(S, x, I["top"], z, ("Blossom", "Yellow", "BlossomWhite", "Rose")[fl % 4])
            fl += 1
    # the ladder landing: planks from island 2's rim out over the truss, edge beams, two brackets under it
    lad = L["ladder"]
    lcx, lcz = lad["c"]
    dy = lad["y1"]
    x0, x1 = lad["deck"]
    for k in range(5):
        z = lcz - 0.8 + k * 0.4
        S.box("Plank" if k % 2 else "PlankLight", ((x0 + x1) / 2, dy - 0.1, z), (x1 - x0, 0.2, 0.36))
    S.box("PlankDark", ((x0 + x1) / 2, dy - 0.27, lcz - 0.95), (x1 - x0, 0.16, 0.16))
    S.box("PlankDark", ((x0 + x1) / 2, dy - 0.27, lcz + 0.95), (x1 - x0, 0.16, 0.16))
    for sz in (-0.85, 0.85):
        S.g.cap("PlankDark", (x0 + 0.25, dy - 0.3, lcz + sz), (x1 + 0.2, dy - 1.5, lcz + sz), 0.11)
    # the ladder on the truss face, built on the voxel grid so it reads as a ladder from the plaza: two dark bark
    # rails (one voxel wide, two deep), thin lighter plank rungs one voxel thick with two-voxel gaps of daylight between
    # them (0.77 stud), pale rope lashings (flush bands on the rails) at the foot rung and at the deck; the rails
    # run up past the deck as handles. (A flush 0.16-radius rung every 0.75 stud fused into a pale slab: review.)
    v = 1.0 / S.K

    def snap(a):
        return round(a * S.K) / S.K
    fx = snap(lcx - 1.0 + 0.12)
    zl, zr = snap(lcz - 0.7), snap(lcz + 0.7)
    ry0, ry1 = snap(lad["y0"] + 0.3), snap(dy + 0.75)
    for zz in (zl, zr):
        S.box("Bark", (fx + v / 2, (ry0 + ry1) / 2, zz), (v * 2 * 0.98, ry1 - ry0 + v * 0.98, v * 0.98))
        S.box("BarkDark", (fx + v / 2, ry1, zz), (v * 2 * 0.98, v * 0.98, v * 0.98))  # the worn, darker handle tops
    rungs = []
    y = snap(lad["y0"] + 0.95)
    while y < dy - 0.35:
        S.box("Plank", (fx, y, (zl + zr) / 2), (v * 0.98, v * 0.98, zr - zl - v * 1.02))
        rungs.append(y)
        y += 3 * v
    for yy in ({rungs[0], snap(dy - 0.27)} if rungs else set()):  # lashed where it stands and where it meets the deck
        for zz in (zl, zr):  # a flush band, not a peg sticking out (Gemini, fix round)
            S.paint("Rope", "box", only=["Bark"], center=(fx + v / 2, yy, zz), size=(v * 2 * 0.98, v * 0.98, v * 0.98))
    # the rope landing in front of island 3: a plank deck on brackets, the stake the rope is tied to, the knotted rope
    # down the truss face to island 2 and its loose end coiled on the grass
    rp = L["rope"]
    rcx, rcz = rp["c"]
    ry = rp["y1"]
    z0, z1 = rp["deck"]
    for k in range(5):
        x = rcx - 0.8 + k * 0.4
        S.box("Plank" if k % 2 else "PlankLight", (x, ry - 0.1, (z0 + z1) / 2), (0.36, 0.2, z1 - z0))
    for sx in (-0.95, 0.95):
        S.box("PlankDark", (rcx + sx, ry - 0.27, (z0 + z1) / 2), (0.16, 0.16, z1 - z0))
        S.g.cap("PlankDark", (rcx + sx * 0.9, ry - 0.3, z0 + 0.25), (rcx + sx * 0.9, ry - 1.4, z1 + 0.25), 0.11)
    stake = (rcx - 0.6, ry, z0 + 0.3)
    S.g.cap("PlankDark", (stake[0], ry - 0.2, stake[2]), (stake[0] + 0.04, ry + 0.85, stake[2]), 0.13, 0.11)
    S.g.torus("RopeDark", (stake[0], ry + 0.5, stake[2]), 0.19, 0.08)
    top = (rcx, ry + 0.05, rcz - 1.0 + 0.1)
    # the rope is old and dark with handling; it bellies out a little as it hangs, and its knots are tied from newer,
    # paler cord (re-tied each summer) so they pop as hand holds
    S.g.curve("RopeDark", [(stake[0], ry + 0.5, stake[2]), (rcx - 0.3, ry + 0.2, z0 + 0.15), top], 0.08)

    def sag(y):  # the hang's outward belly (studs toward -Z) at height y
        t = (ry - y) / max(0.1, ry - I2["top"])
        return 0.22 * math.sin(math.pi * min(1.0, max(0.0, t)))
    S.g.curve("RopeDark", [top, (rcx + 0.04, ry - 1.0, top[2] - sag(ry - 1.0)), (rcx + 0.04, (ry + I2["top"]) / 2, top[2] - sag((ry + I2["top"]) / 2)),
                           (rcx + 0.03, I2["top"] + 1.0, top[2] - sag(I2["top"] + 1.0)), (rcx + 0.02, I2["top"] + 0.15, top[2] - 0.02)], 0.13)
    y = ry - 0.6
    while y > I2["top"] + 0.6:
        S.ell("Rope", (rcx + 0.03, y, top[2] - 0.03 - sag(y)), (0.27, 0.14, 0.27))  # one voxel tall: dark rope between
        y -= 1.05
    S.g.curve("RopeDark", [(rcx + 0.02, I2["top"] + 0.15, top[2] - 0.02), (rcx + 0.45, I2["top"] + 0.08, top[2] - 0.35),
                           (rcx + 0.15, I2["top"] + 0.08, top[2] - 0.7), (rcx - 0.2, I2["top"] + 0.08, top[2] - 0.4)], 0.08)
    # the lantern post on island 2: a crooked wooden post, an iron bracket, a lantern with a warm Neon heart
    lx, lz = L["lantern"]
    ly = I2["top"]
    S.g.cap("PlankDark", (lx, ly - 0.3, lz), (lx + 0.08, ly + 2.5, lz - 0.05), 0.15, 0.13)
    S.g.cap("Iron", (lx + 0.06, ly + 2.45, lz - 0.05), (lx - 0.65, ly + 2.5, lz - 0.05), 0.1)  # the bracket arm
    # the lantern on the voxel grid: a tall warm glass (2 x 3 x 2 voxels) under a one-voxel iron cap on a one-voxel
    # hook; the glow dominates (a bigger navy frame and base read as a mailbox from the plaza)
    v = 1.0 / S.K

    def snap(a):
        return round(a * S.K) / S.K
    hx, hz = snap(lx - 0.65), snap(lz - 0.05)
    ycap = snap(ly + 2.1)
    S.box("Iron", (hx, ycap + v, hz), (v * 0.98, v * 0.98, v * 0.98))                           # the hook (arm row)
    S.box("Iron", (hx + v / 2, ycap, hz + v / 2), (2 * v * 0.98, v * 0.98, 2 * v * 0.98))       # the cap
    S.box("Lamp", (hx + v / 2, ycap - 2 * v, hz + v / 2), (2 * v * 0.98, 3 * v * 0.98, 2 * v * 0.98))  # the glass
    S.neon["Lamp"] = ["rgb"] + list(NEON["Lamp"])
    # tidy: nothing below the pool floor (pillar feet stop there)
    g.carve("box", center=(0, -2.0, 0), size=(30, 3.8, 30))


# ------------------------------------------------------------------------------------------------- water
def _water(S):
    L = LAYOUT
    I1, I2, I3 = L["islands"]
    S.cyl("WaterDeep", 0, 0, L["floor"] + 0.02, L["water"] - 0.35, L["poolIn"] + 0.1)
    S.cyl("Water", 0, 0, L["water"] - 0.35, L["water"], L["poolIn"] + 0.1)
    # stones and pillars stand in the water: no hidden water inside them (cleaner glass, fewer triangles)
    for (x, z, top, r) in L["stones"]:
        S.g.carve("cone", a=(x, -1, z), b=(x, 3, z), r=r - 0.1, rb=r - 0.1)
    for I in (I1, I2, I3):
        S.g.carve("cone", a=(I["c"][0], -1, I["c"][1]), b=(I["c"][0], 3, I["c"][1]), r=0.75, rb=0.75)
    # stream water: one voxel layer just under the channel lip (K 2: centres every 0.5 stud; the islands key carves
    # the channel to its own voxel, so the water shows 0.25-0.35 stud below the grass)
    K = S.K
    tops = (I3["top"], I2["top"], I1["top"])
    for pts, top in zip(L["streams"], tops):
        yc = math.floor((top - 0.1) * K) / K
        for (ax, az), (bx, bz) in zip(pts[:-1], pts[1:]):
            S.g.cap("Water", (ax, yc, az), (bx, yc, bz), 0.4)
        mx, mz = sum(p[0] for p in pts) / 3, sum(p[1] for p in pts) / 3
        S.g.carve("box", center=(mx, yc + 1.2, mz), size=(12, 2.0, 12), only="Water")
        S.g.carve("box", center=(mx, yc - 1.2, mz), size=(12, 2.0, 12), only="Water")
    # the spring basin at the rock's foot on island 3
    sx, sz = L["spring"]
    yc = math.floor((I3["top"] - 0.1) * K) / K
    S.g.ell("Water", (sx - 0.05, yc, sz - 0.75), (0.55, 0.1, 0.45))
    S.glass["Water"] = (rgb("Water"), 0.35)
    S.glass["WaterDeep"] = (rgb("WaterDeep"), 0.3)


# ------------------------------------------------------------------------------------------------- boat
def _boat(S):
    """a folded paper boat, ~1.3 studs long, floating with its waterline at y 0 (pivot = the water point under it)"""
    g = S.g
    # hull: a trapezoid prism, wider at the top, pointed ends
    for k in range(7):
        y = -0.12 + k * 0.06
        half = 0.42 + k * 0.045
        g.box("Paper", (0, y, 0), (0.42 + k * 0.03, 0.07, half * 2 - 0.3))
        g.cap("Paper", (0, y, -half + 0.1), (0, y, half - 0.1), 0.05 + k * 0.012)
    # the sail: a tall folded triangle
    for k in range(9):
        y = 0.28 + k * 0.06
        w = 0.62 - k * 0.065
        g.box("PaperFold" if k % 3 == 0 else "Paper", (0, y, 0), (0.06, 0.07, max(0.06, w)))
    g.box("PaperRed", (0, 0.15, 0), (0.44, 0.05, 0.9))  # a red stripe (it was made from a flyer)
    S.flat |= {"PaperRed"}


# ------------------------------------------------------------------------------------------------- builder
@prop("lobby_oasis")
def lobby_oasis(entry, kit):
    """Sky-Oasis Steps fountain (bug #13): `part` = pool | islands | water | boat"""
    args = entry.get("args") or {}
    part = args.get("part", "pool")
    K = float(args.get("K", {"pool": 2.7, "islands": 2.6, "water": 2.0, "boat": 12.0}[part]))
    S = Sculpt(kit, K, {"pool": 11.5, "islands": 11, "water": 11, "boat": 1.2}[part])
    if part == "pool":
        _pool(S)
        group = "Pool"
    elif part == "islands":
        _islands(S)
        group = "Islands"
    elif part == "water":
        _water(S)
        group = "Water"
    else:
        _boat(S)
        group = "Boat"
    S.flat |= {"Yellow", "Blossom", "BlossomWhite", "Rose", "Lamp", "Tuft"}
    m = kit.model(entry["key"], "prop", vs=1 / K, K=K)
    S.mesh(m, group=group)
    pivot = "the water point under the boat" if part == "boat" else "pool centre on the plaza ground, -Z toward the spawn"
    return finish(m, {"source": "Sky-Oasis Steps (bug #13, waterfall pitch option C) %s" % part, "pivot": pivot})
