"""The dungeon's designed pieces (bug #5; the looks: props/dungeon_style.py).  Their Part builds in DungeonBuilder are
the colliders and the fallback; these are what the player sees once uploaded:

  "dp_design" args {style, what}:
    throne   a carved granite throne, red cushion, cloud crest in a gold ring (a) | the guild master's iron-and-brass chair,
             buttoned navy padding, gauges on the arms, a copper lightning rod (b) | a hollow stump with a moss cushion,
             roots over the dais, a crown of leaves and a star-flower (c)
    statue   a hooded stone warden on a sword (a) | a retired weather robot: barometer face, anemometer cups (b) | a hedge
             knight in a terracotta planter (c)
    brazier  an iron tripod brazier with coals (a) | a copper condenser coil round the cyan core (b) | a glowing pitcher
             plant (c); the Neon flame / core stays a Part over it
    banner   a navy swallow-tail with the cloud crest (a) | the guild's storm poster on a brass rod (b) | a hessian seed-guild
             banner on a branch (c); the stripe = the floor's element (Secondary)
    curio    a lectern with an open journal and a half-melted candle (a) | a stand-pipe with a red valve wheel, a red wrench,
             a toolbox and a mug (b) | a cracked pot spilling soil, a patched watering can, seeds and shears (c)
    torch    an iron cage sconce with its soot mark (a) | a brass lantern on a bracket (b) | a jar lantern on a hook (c)
    arch_10 / arch_6  the arch tops: pointed granite voussoirs (a) | a riveted girder with knee braces and a brass
             weathervane (b) | two roots woven over the aisle with star-bulbs (c)
    window   (a) the round sky window behind the throne      cloud / ring (b) the astrolabe's storm cloud and its rings
    barrel / cauldron (shared) a round staved barrel; a round iron cauldron
  "dp_wx" args {element, spot}: the element weathering clusters (high = under the cornice, low = at the wall foot)

Pivots = the Tag origins in DungeonBuilder (the comments give each frame).  LayoutSig = the target's Part signature
when the bake world recorded one (args.sig false: scaled / anchor pieces).  Deterministic.
"""
import math

import numpy as np

from props import prop
from props.dungeon_style import (Canvas, finish, grey, _hv, BRASS, BRASS_D, COPPER, COPPER_D, IRON, STORM, STORM_L,
                                  RED, SLATE_A, MOSS, MOSS_L, LEAF, LEAF_L, BARK, BARK_L, SOIL, WOOD, WOOD_D, TERRA)
from props.arena_style import _hash

GRANITE = (150, 156, 174)
GRANITE_L = (178, 182, 198)
GRANITE_D = (112, 118, 136)
RED_A = (150, 34, 48)
GOLD = (214, 170, 80)
NAVY = (58, 74, 132)
CREAM = (240, 236, 222)
WHITE_C = (236, 238, 232)
COAL = (52, 44, 44)
EMBER = (236, 110, 48)
EMBER_L = (255, 176, 80)


def _steps(v, step=20.0):
    """a gradient in a few flat bands (a smooth per-cell gradient costs a quad per cell)"""
    return np.floor(v / step) * step


def granite(x, y, z):
    n = _hv(np.floor(x * 4).astype(int), np.floor(y * 4).astype(int), np.floor(z * 4).astype(int), 3)
    base = np.array(GRANITE, float)
    return np.where((n < 0.15)[:, None], base * 0.9, np.where((n > 0.9)[:, None], np.minimum(255, base * 1.08), base))


def bark(x, y, z):
    # bark grain in 0.5 x 1.0 x 0.5 blocks (axis-aligned: a diagonal pattern costs a staircase of faces)
    n = _hv(np.floor(x / 0.5).astype(int), np.floor(y / 1.0).astype(int), np.floor(z / 0.5).astype(int), 9)
    return np.where((n < 0.35)[:, None], np.array(BARK_L, float), np.array(BARK, float))


def leafy(x, y, z):
    n = _hv(np.floor(x / 0.5).astype(int), np.floor(y / 0.5).astype(int), np.floor(z / 0.5).astype(int), 4)  # (0.5 patches)
    return np.where((n < 0.3)[:, None], np.array(LEAF_L, float), np.where((n > 0.85)[:, None], np.array((70, 136, 66), float), np.array(LEAF, float)))


def dial(cv, c, rad, axis_sign=-1, ang=0.8):
    """a round gauge facing -z at c (rim brass, cream face, red needle)"""
    vs = cv.vs
    x, y, z = c
    cv.cyl("Brass", BRASS, (x, y, z), rad, z - vs * 1.5, z + vs * 0.5, axis=2)
    cv.cyl("Dial", CREAM, (x, y, z), rad - vs, z - vs * 2.0, z - vs * 0.5, axis=2)
    for t in np.linspace(0.05, rad - vs * 1.2, 5):
        cv.box("Needle", (190, 40, 40), (x + math.cos(ang) * t - vs / 2, y + math.sin(ang) * t - vs / 2, z - vs * 2.4),
               (x + math.cos(ang) * t + vs / 2, y + math.sin(ang) * t + vs / 2, z - vs * 1.6))


# ------------------------------------------------------------------------------------------------ thrones
# frame: origin on the dais top under the throne's seat centre; the throne looks -z (down the room); its back at +z
def throne_a(cv):
    vs = cv.vs
    cv.box("Stone", granite, (-1.9, 0, -1.3), (1.9, 1.8, 1.3))
    cv.box("Stone", GRANITE_D, (-2.0, 0, -1.4), (2.0, 0.3, 1.4))
    cv.box("Stone", GRANITE_L, (-1.9, 1.55, -1.4), (1.9, 1.8, 1.3))
    for s in (-1, 1):
        cv.box("Stone", granite, (s * 1.6 - 0.25, 1.8, -1.3), (s * 1.6 + 0.25, 3.3, 1.2))
        cv.box("Stone", GRANITE_L, (s * 1.6 - 0.3, 3.3, -1.4), (s * 1.6 + 0.3, 3.55, 1.25))
        cv.ell("Gold", GOLD, (s * 1.6, 3.7, -1.25), (0.22, 0.22, 0.22))
    # the back: a tall slab with a pointed top
    cv.where("Stone", granite, lambda x, y, z: (np.abs(x) <= np.minimum(1.8, (8.6 - y) * 1.3)) & (y >= 1.8) & (z >= 0.7) & (z <= 1.4),
             (-1.8, 1.8, 0.7), (1.8, 8.6, 1.4))
    cv.where("Stone", GRANITE_L, lambda x, y, z: (np.abs(x) <= np.minimum(1.95, (8.75 - y) * 1.3)) & (np.abs(x) > np.minimum(1.8, (8.6 - y) * 1.3) - vs) & (y >= 6.8) & (z >= 0.6) & (z <= 1.5),
             (-1.95, 6.8, 0.6), (1.95, 8.8, 1.5))
    # red cushion and back panel, a cloud crest in a gold ring with the element gem
    cv.box("Cloth", RED_A, (-1.45, 1.8, -1.1), (1.45, 2.2, 0.7))
    cv.box("Cloth", (124, 26, 40), (-1.45, 2.15, -1.1), (1.45, 2.25, -0.95))
    cv.box("Cloth", RED_A, (-1.2, 2.3, 0.55), (1.2, 5.0, 0.7))
    cv.torus("Gold", GOLD, (0, 6.1, 0.6), 0.85, 0.12, axis=2)
    for dx, dy, r in ((-0.35, 6.0, 0.32), (0.05, 6.2, 0.4), (0.4, 6.0, 0.3)):
        cv.ell("Crest", WHITE_C, (dx, dy, 0.62), (r, r * 0.8, 0.12))
    cv.ell("Element", grey(0.95), (0, 7.25, 0.62), (0.18, 0.18, 0.12))
    cv.ell("Gold", GOLD, (0, 8.75, 1.05), (0.25, 0.25, 0.25))


def throne_b(cv):
    vs = cv.vs
    # (Gemini: the chair read spindly for a boss seat) a riveted storm-blue pedestal with a brass lip, stout iron legs
    cv.box("Girder", STORM, (-2.1, 0, -1.7), (2.1, 0.5, 1.5))
    cv.box("Brass", BRASS, (-2.15, 0.45, -1.75), (2.15, 0.6, 1.55))
    for xx in np.arange(-1.8, 1.9, 0.6):
        cv.box("Rivet", BRASS_D, (xx - vs / 2, 0.2, -1.75 - vs), (xx + vs / 2, 0.2 + vs, -1.7), mode="empty")
    for sx in (-1.35, 1.35):
        for sz in (-1.0, 0.9):
            cv.box("Iron", IRON, (sx - 0.25, 0.6, sz - 0.25), (sx + 0.25, 1.5, sz + 0.25))
            cv.box("Brass", BRASS, (sx - 0.3, 0.6, sz - 0.3), (sx + 0.3, 0.75, sz + 0.3))
    cv.box("Iron", IRON, (-1.6, 1.4, -1.2), (1.6, 1.7, 1.2))
    cv.box("Brass", BRASS, (-1.65, 1.55, -1.25), (1.65, 1.7, -1.1))
    cv.ell("Cloth", NAVY, (0, 1.85, -0.15), (1.4, 0.4, 1.0), p=3)
    for bx in (-0.7, 0, 0.7):
        cv.box("Brass", BRASS, (bx - vs / 2, 2.15, -0.3), (bx + vs / 2, 2.3, -0.1), mode="all")
    # back: two iron posts, a buttoned navy panel, a brass top bar
    for s in (-1, 1):
        cv.box("Iron", IRON, (s * 1.55 - 0.25, 1.7, 0.8), (s * 1.55 + 0.25, 7.5, 1.25))
    cv.box("Brass", BRASS, (-1.35, 1.9, 1.15), (1.35, 7.2, 1.3))  # the brass back plate the padding sits on
    cv.ell("Cloth", NAVY, (0, 4.5, 1.0), (1.35, 2.3, 0.25), p=4)
    for by in (3.2, 4.5, 5.8):
        for bx in (-0.6, 0.6):
            cv.box("Brass", BRASS, (bx - vs / 2, by - vs / 2, 0.7), (bx + vs / 2, by + vs / 2, 0.8), mode="all")
    cv.box("Brass", BRASS, (-1.8, 7.4, 0.8), (1.8, 7.8, 1.25))
    cv.ell("Brass", BRASS, (-1.8, 7.6, 1.02), (0.25, 0.25, 0.25))
    cv.ell("Brass", BRASS, (1.8, 7.6, 1.02), (0.25, 0.25, 0.25))
    # arms: brass tubes from the back posts to front posts, a gauge on each arm end
    for s in (-1, 1):
        cv.seg("Brass", BRASS, (s * 1.5, 3.1, 1.0), (s * 1.5, 3.1, -1.1), 0.16)
        cv.box("Iron", IRON, (s * 1.5 - 0.12, 1.7, -1.2), (s * 1.5 + 0.12, 3.1, -1.0))
        dial(cv, (s * 1.5, 3.1, -1.25), 0.32, ang=0.5 + 0.9 * (s > 0))
    # the lightning rod (copper, a brass ball on the tip; the hub's cloud hangs over it) + the element lamp
    # (the rod's tip, 2.2 below the astrolabe hub, is the axle the outer ring turns on: it stays inside ring 1's tube)
    # (tip 8.3 = room y 10.7: the review lowered the hub to 12.9 for 0.4 stud under the ceiling)
    cv.seg("Copper", (196, 118, 72), (0, 7.5, 1.0), (0, 8.3, 1.0), 0.11, 0.05)
    cv.ell("Brass", BRASS, (0, 7.72, 1.0), (0.2, 0.2, 0.2))
    cv.ell("Element", grey(0.95), (0, 7.95, 0.75), (0.15, 0.15, 0.12))


def throne_c(cv):
    vs = cv.vs
    # the stump: seat height ring, the back side rising to a jagged top
    cv.cyl("Bark", bark, (0, 0, 0.2), 1.95, 0, 1.9)
    cv.where("Bark", bark, lambda x, y, z: ((x ** 2 + (z - 0.2) ** 2) <= 1.95 ** 2) & ((x ** 2 + (z - 0.2) ** 2) >= 1.3 ** 2) & (z > 0.25)
             & (y <= 7.2 + 0.6 * np.sin(x * 3.1) - 0.25 * np.abs(x)), (-1.95, 1.9, 0.2), (1.95, 8.0, 2.15))
    cv.where("Wood", (196, 160, 110), lambda x, y, z: ((x ** 2 + (z - 0.2) ** 2) <= 1.6 ** 2) & (np.abs(((x ** 2 + (z - 0.2) ** 2) ** 0.5) % 0.45) < 0.08),
             (-1.6, 1.8, -1.4), (1.6, 1.9, 1.8), mode="over")
    # the moss cushion
    cv.ell("Moss", lambda x, y, z: np.where((_hv(np.floor(x * 4).astype(int), np.floor(z * 4).astype(int), 3) < 0.4)[:, None], np.array(MOSS_L, float), np.array(MOSS, float)),
           (0, 1.95, -0.1), (1.45, 0.45, 1.3))
    # roots spreading over the dais
    for k in range(7):
        a = k / 7.0 * 6.28 + 0.4
        pts = [(math.cos(a) * 1.7, 0.5, 0.2 + math.sin(a) * 1.7), (math.cos(a + 0.2) * 2.6, 0.2, 0.2 + math.sin(a + 0.2) * 2.6),
               (math.cos(a + 0.35) * 3.4, 0.08, 0.2 + math.sin(a + 0.35) * 3.4)]
        cv.path("Bark", bark, pts, 0.35, 0.12)
    # the crown of leaves and the star-flower on top of the back
    for k in range(9):
        a = k / 9.0 * 3.14
        cv.ell("Leaf", leafy, (math.cos(a) * 1.6, 7.5 + math.sin(a) * 0.5 + 0.2 * (k % 2), 1.2), (0.55, 0.32, 0.45))
    for k in range(5):
        a = k / 5.0 * 6.28 + 1.57
        cv.ell("Element", grey(0.96), (math.cos(a) * 0.32, 8.45 + math.sin(a) * 0.32, 1.05), (0.24, 0.24, 0.1))
    cv.ell("Gold", (255, 214, 96), (0, 8.45, 1.0), (0.16, 0.16, 0.12))
    # (Gemini: a lived-in touch) shards of a dropped terracotta pot by the stump's foot
    for k, (x, z, w, d) in enumerate(((-2.6, -1.6, 0.5, 0.35), (-2.0, -2.2, 0.35, 0.3), (-3.1, -2.4, 0.3, 0.25), (-2.4, -2.8, 0.4, 0.2))):
        cv.box("Pot", (196, 116, 82) if k % 2 else (176, 100, 72), (x - w / 2, 0.2, z - d / 2), (x + w / 2, 0.4 + 0.1 * (k % 2), z + d / 2))  # (on the 0.2 dais carpet)


# ------------------------------------------------------------------------------------------------ statues (origin: floor)
def statue_a(cv):
    vs = cv.vs
    cv.box("Stone", SLATE_A, (-1.5, 0, -1.5), (1.5, 1.2, 1.5))
    cv.box("Stone", (86, 98, 128), (-1.6, 1.0, -1.6), (1.6, 1.2, 1.6))
    for sx in (-1, 1):
        for sz in (-1, 1):
            cv.ell("Moss", MOSS, (sx * 1.45, 1.15, sz * 1.45), (0.35, 0.14, 0.35))
    # the robe (tapering), hood, face shadow
    cv.where("Stone", granite, lambda x, y, z: ((np.abs(x) / (0.95 - (y - 1.2) * 0.06)) ** 2.5 + (np.abs(z) / (0.75 - (y - 1.2) * 0.03)) ** 2.5 <= 1.0),
             (-1.0, 1.2, -0.8), (1.0, 5.3, 0.8))
    cv.ell("Stone", granite, (0, 5.0, 0.0), (1.05, 0.5, 0.75))
    cv.ell("Stone", granite, (0, 5.95, 0.05), (0.62, 0.72, 0.62))
    cv.ell("Shadow", (42, 46, 60), (0, 5.85, -0.5), (0.36, 0.42, 0.2))
    for k in range(5):
        cv.box("Stone", GRANITE_D, (-0.9 + k * 0.45 - vs / 2, 1.2, -0.85), (-0.9 + k * 0.45 + vs / 2, 4.2, -0.65), mode="over")
    # hands on the pommel of a sword, point down in front
    cv.box("Iron", (160, 166, 184), (-0.12, 1.3, -1.05), (0.12, 3.9, -0.9))
    cv.box("Iron", (120, 126, 146), (-0.65, 3.8, -1.1), (0.65, 4.0, -0.85))
    cv.box("Iron", (120, 126, 146), (-0.12, 4.0, -1.05), (0.12, 4.4, -0.9))
    cv.ell("Stone", GRANITE_L, (0, 4.35, -1.0), (0.42, 0.25, 0.28))


def statue_b(cv):
    vs = cv.vs
    cv.box("Girder", STORM, (-1.5, 0, -1.5), (1.5, 1.2, 1.5))
    cv.box("Brass", BRASS, (-1.55, 1.0, -1.55), (1.55, 1.2, 1.55))
    for sx in (-1.25, 1.25):
        for sz in (-1.25, 1.25):
            cv.box("Rivet", BRASS, (sx - vs / 2, 0.5, sz - vs / 2), (sx + vs / 2, 0.75, sz + vs / 2), mode="all")
    # legs, body, the barometer face
    for s in (-1, 1):
        cv.box("Iron", IRON, (s * 0.5 - 0.25, 1.2, -0.3), (s * 0.5 + 0.25, 2.5, 0.3))
        cv.box("Iron", IRON, (s * 0.5 - 0.35, 1.2, -0.45), (s * 0.5 + 0.35, 1.45, 0.4))
    cv.box("Brass", lambda x, y, z: np.where((_hv(np.floor(x * 3).astype(int), np.floor(y * 3).astype(int), 6) < 0.12)[:, None],
                                             np.array((96, 160, 130), float), np.array(BRASS, float)), (-0.95, 2.4, -0.65), (0.95, 4.7, 0.65))
    dial(cv, (0, 3.55, -0.68), 0.55, ang=2.0)
    for yy in (2.6, 4.5):
        for xx in (-0.8, 0.8):
            cv.box("Rivet", BRASS_D, (xx - vs / 2, yy - vs / 2, -0.78), (xx + vs / 2, yy + vs / 2, -0.65), mode="all")
    for s in (-1, 1):
        cv.seg("Iron", IRON, (s * 1.05, 4.4, 0), (s * 1.25, 3.0, -0.15), 0.2)
        cv.ell("Iron", IRON, (s * 1.27, 2.85, -0.18), (0.25, 0.25, 0.25))
    # head with two lamp eyes (the element colour), the anemometer on its mast
    cv.box("Iron", (84, 96, 124), (-0.55, 4.7, -0.5), (0.55, 5.55, 0.5))
    for s in (-1, 1):
        cv.ell("Element", grey(0.95), (s * 0.25, 5.15, -0.5), (0.13, 0.13, 0.08))
    cv.cyl("Iron", IRON, (0, 0, 0), 0.12, 5.55, 6.65)
    for k in range(3):
        a = k / 3.0 * 6.28
        cv.seg("Brass", BRASS, (0, 6.65, 0), (math.cos(a) * 0.65, 6.65, math.sin(a) * 0.65), 0.09)  # (0.06: the +x spoke hit no cell centre and its cup floated)
        cv.ell("Brass", BRASS, (math.cos(a) * 0.68, 6.65, math.sin(a) * 0.68), (0.17, 0.17, 0.17))


def statue_c(cv):
    vs = cv.vs
    # the terracotta planter with a rim and soil
    cv.box("Pot", (190, 110, 80), (-1.45, 0, -1.45), (1.45, 1.1, 1.45))
    cv.box("Pot", (206, 126, 92), (-1.55, 0.95, -1.55), (1.55, 1.25, 1.55))
    cv.box("Soil", SOIL[1], (-1.3, 1.1, -1.3), (1.3, 1.3, 1.3))
    # the clipped hedge knight
    cv.ell("Leaf", leafy, (0, 2.9, 0), (0.95, 1.6, 0.75), p=2.4)
    cv.ell("Leaf", leafy, (0, 4.45, 0), (1.15, 0.45, 0.8), p=2.4)
    cv.ell("Leaf", leafy, (0, 5.35, 0), (0.6, 0.7, 0.6), p=3)
    cv.box("Leaf", (64, 128, 60), (-0.45, 5.25, -0.62), (0.45, 5.4, -0.55), mode="over")
    cv.ell("Leaf", leafy, (0, 6.15, 0.1), (0.18, 0.45, 0.55))
    cv.ell("Leaf", leafy, (-1.1, 3.5, -0.3), (0.2, 0.75, 0.6))
    cv.ell("Leaf", leafy, (1.1, 3.6, 0), (0.28, 0.85, 0.3))
    cv.seg("Bark", bark, (1.15, 3.0, -0.3), (1.15, 6.6, -0.9), 0.08)
    for k in range(6):
        a = _hash(k, 3) * 6.28
        y = 2.0 + 3.0 * _hash(k, 4)
        cv.ell("Element", grey(0.95), (math.cos(a) * 0.9, y, math.sin(a) * 0.72), (0.12, 0.12, 0.12))


# ------------------------------------------------------------------------------------------------ braziers (origin: dais top)
def brazier_a(cv):
    vs = cv.vs
    for k in range(3):
        a = k / 3.0 * 6.28 + 0.5
        cv.seg("Iron", IRON, (math.cos(a) * 1.1, 2.6, math.sin(a) * 1.1), (math.cos(a) * 1.5, 0.05, math.sin(a) * 1.5), 0.12)
        cv.box("Iron", IRON, (math.cos(a) * 1.5 - 0.2, 0, math.sin(a) * 1.5 - 0.2), (math.cos(a) * 1.5 + 0.2, 0.12, math.sin(a) * 1.5 + 0.2))
    cv.torus("Iron", IRON, (0, 1.1, 0), 1.25, 0.08, axis=1)
    cv.where("Iron", IRON, lambda x, y, z: (x ** 2 + z ** 2 + ((y - 3.5) / 1.0) ** 2 * 2.56 <= 1.6 ** 2) & (x ** 2 + z ** 2 + ((y - 3.5) / 1.0) ** 2 * 2.56 >= 1.4 ** 2) & (y <= 3.5),
             (-1.6, 2.4, -1.6), (1.6, 3.5, 1.6))
    cv.torus("Iron", (84, 90, 110), (0, 3.45, 0), 1.55, 0.1, axis=1)
    cv.where("Coal", lambda x, y, z: np.where((_hv(np.floor(x * 5).astype(int), np.floor(z * 5).astype(int), 2) < 0.35)[:, None], np.array(EMBER, float), np.array(COAL, float)),
             lambda x, y, z: (x ** 2 + z ** 2 <= 1.4 ** 2) & (y <= 3.35) & (y >= 3.0 - 0.2 * np.sqrt(x ** 2 + z ** 2)), (-1.4, 2.6, -1.4), (1.4, 3.35, 1.4))


def brazier_b(cv):
    vs = cv.vs
    cv.cyl("Brass", BRASS, (0, 0, 0), 1.45, 0, 0.35)
    cv.cyl("Iron", IRON, (0, 0, 0), 1.25, 0.35, 0.6)
    cv.cyl("Glass", (190, 230, 240), (0, 0, 0), 0.55, 0.6, 3.4, glass=55)
    turns, y0, y1, R = 5.0, 0.7, 5.3, 1.5
    pts = []
    for t in np.linspace(0, 1, 90):
        a = t * turns * 6.28
        pts.append((math.cos(a) * R, y0 + (y1 - y0) * t, math.sin(a) * R))
    cv.path("Copper", lambda x, y, z: np.where((_hv(np.floor(y * 3).astype(int), 5) < 0.2)[:, None], np.array(COPPER_D, float), np.array((196, 118, 72), float)), pts, 0.16)
    for yy in (0.6, 5.4):
        cv.torus("Brass", BRASS, (0, yy, 0), 1.5, 0.12, axis=1)
    for k in range(3):
        a = k / 3.0 * 6.28 + 0.3
        cv.box("Brass", BRASS_D, (math.cos(a) * 1.5 - 0.1, 0.6, math.sin(a) * 1.5 - 0.1), (math.cos(a) * 1.5 + 0.1, 5.4, math.sin(a) * 1.5 + 0.1))


def brazier_c(cv):
    vs = cv.vs
    for k in range(5):
        a = k / 5.0 * 6.28
        cv.ell("Leaf", leafy, (math.cos(a) * 1.1, 0.25, math.sin(a) * 1.1), (0.8, 0.18, 0.4))
    def pitcher(x, y, z):
        stripe = (np.abs(np.sin(np.arctan2(z, x) * 3)) < 0.2)  # three red veins
        return np.where(stripe[:, None], np.array((170, 60, 70), float), np.where((y > 2.6)[:, None], np.array((150, 200, 96), float), np.array((104, 168, 82), float)))
    cv.where("Plant", pitcher, lambda x, y, z: ((x ** 2 + z ** 2) <= (0.9 + 0.5 * np.sin(np.clip((y - 0.2) / 3.3, 0, 1) * 3.0)) ** 2)
             & ((x ** 2 + z ** 2) >= (0.7 + 0.5 * np.sin(np.clip((y - 0.2) / 3.3, 0, 1) * 3.0)) ** 2 * (y > 1.0)) & (y >= 0.2) & (y <= 3.45),
             (-1.5, 0.2, -1.5), (1.5, 3.45, 1.5))
    cv.torus("Plant", (176, 64, 76), (0, 3.4, 0), 1.38, 0.14, axis=1)
    cv.where("Plant", (196, 70, 84), lambda x, y, z: ((x / 1.3) ** 2 + ((z - 1.0) / 1.0) ** 2 <= 1.0) & (np.abs(y - (5.7 + (z - 1.0) * 0.5)) < 0.12),
             (-1.3, 5.0, 0.0), (1.3, 6.4, 2.0))
    # the lid's stalk: from the back of the rim up to the lid's back edge (it read as floating)
    cv.seg("Plant", (104, 168, 82), (0, 3.4, 1.38), (0, 6.15, 1.85), 0.16)


# ------------------------------------------------------------------------------------------------ banners (origin on the wall face; -z into the room)
def banner_a(cv):
    vs = cv.vs
    cv.cyl("Iron", IRON, (0, 0, -0.3), 0.12, -2.25, 2.25, axis=0)
    for s in (-1, 1):
        cv.ell("Iron", IRON, (s * 2.3, 0, -0.3), (0.16, 0.16, 0.16))
        cv.box("Iron", IRON, (s * 1.8 - 0.12, -0.12, -0.3), (s * 1.8 + 0.12, 0.12, 0))
    def cloth(x, y, z):
        edge = (np.abs(x) > 1.62)
        return np.where(edge[:, None], np.array(GOLD, float), np.array((54, 70, 140), float))
    # (Gemini: a tattered, uneven swallow-tail bottom for age)
    cv.where("Cloth", cloth, lambda x, y, z: (np.abs(x) <= 1.8) & (y <= -0.05) & (y >= -5.4 + np.maximum(0, 0.95 - np.abs(x)) * 1.0 + 0.45 * _hv(np.floor((x + 2) / 0.375).astype(int), 13) * (x > -1.0)) & (np.abs(z + 0.3) <= 0.07),
             (-1.8, -5.5, -0.4), (1.8, 0, -0.2))
    for dx, dy, r in ((-0.4, -1.9, 0.38), (0.1, -1.7, 0.48), (0.5, -1.95, 0.35)):
        cv.ell("Crest", WHITE_C, (dx, dy, -0.38), (r, r * 0.75, 0.08), mode="all")
    cv.where("Element", grey(0.95), lambda x, y, z: (np.abs(x) <= 1.6) & (y <= -3.6) & (y >= -4.0) & (np.abs(z + 0.3) <= 0.07), (-1.6, -4.0, -0.4), (1.6, -3.6, -0.2))


def banner_b(cv):
    vs = cv.vs
    cv.cyl("Brass", BRASS, (0, 0, -0.3), 0.12, -2.2, 2.2, axis=0)
    for s in (-1, 1):
        cv.ell("Brass", BRASS, (s * 2.3, 0, -0.3), (0.2, 0.2, 0.2))
        cv.box("Iron", IRON, (s * 1.8 - 0.12, -0.12, -0.3), (s * 1.8 + 0.12, 0.12, 0))
    def cloth(x, y, z):
        border = (np.abs(x) > 1.55) | (y < -4.95) | (y > -0.35)
        return np.where(border[:, None], np.array(STORM, float), np.array((232, 234, 240), float))
    cv.where("Cloth", cloth, lambda x, y, z: (np.abs(x) <= 1.75) & (y <= -0.1) & (y >= -5.2) & (np.abs(z + 0.3) <= 0.07), (-1.8, -5.3, -0.4), (1.8, 0, -0.2))
    for dx, dy, r in ((-0.45, -1.9, 0.42), (0.15, -1.7, 0.55), (0.6, -1.95, 0.38)):
        cv.ell("Emblem", (52, 70, 120), (dx, dy, -0.38), (r, r * 0.7, 0.08), mode="all")
    bolt = [(0.1, -2.2), (-0.25, -2.9), (0.15, -2.9), (-0.2, -3.7)]
    cv.path("Bolt", (250, 206, 70), [(x, y, -0.38) for x, y in bolt], 0.12)
    cv.where("Element", grey(0.95), lambda x, y, z: (np.abs(x) <= 1.55) & (y <= -4.4) & (y >= -4.8) & (np.abs(z + 0.3) <= 0.08), (-1.6, -4.8, -0.4), (1.6, -4.4, -0.2))


def banner_c(cv):
    vs = cv.vs
    pts = [(-2.3, 0.05, -0.3), (-1.0, -0.05, -0.32), (0.4, 0.06, -0.3), (2.3, -0.04, -0.3)]
    cv.path("Bark", bark, pts, 0.14, 0.1)
    for s in (-1, 1):
        cv.box("Twine", (200, 178, 120), (s * 1.8 - 0.1, -0.2, -0.45), (s * 1.8 + 0.1, 0.2, -0.15))
        cv.box("Iron", IRON, (s * 1.8 - 0.1, -0.1, -0.3), (s * 1.8 + 0.1, 0.1, 0))
    def fray(x, y):
        return -5.2 + 0.35 * _hv(np.floor(x / 0.25).astype(int), 7)
    def cloth(x, y, z):
        n = _hv(np.floor(x / 0.25).astype(int), np.floor(y / 0.25).astype(int), 2)
        return np.where((n < 0.25)[:, None], np.array((180, 154, 104), float), np.array((200, 174, 122), float))
    cv.where("Cloth", cloth, lambda x, y, z: (np.abs(x) <= 1.7) & (y <= -0.1) & (y >= fray(x, y)) & (np.abs(z + 0.3) <= 0.07), (-1.8, -5.3, -0.4), (1.8, 0, -0.2))
    cv.seg("Emblem", (84, 140, 70), (0, -3.3, -0.38), (0, -1.6, -0.38), 0.1)
    cv.ell("Emblem", LEAF, (-0.42, -2.0, -0.38), (0.45, 0.22, 0.08), mode="all")
    cv.ell("Emblem", LEAF_L, (0.42, -1.7, -0.38), (0.45, 0.22, 0.08), mode="all")
    cv.where("Element", grey(0.95), lambda x, y, z: (np.abs(x) <= 1.6) & (y <= -4.1) & (y >= -4.45) & (np.abs(z + 0.3) <= 0.08), (-1.6, -4.5, -0.4), (1.6, -4.0, -0.2))


# ------------------------------------------------------------------------------------------------ curios (origin floor; -z into the room)
def curio_a(cv):
    vs = cv.vs
    oak = (132, 92, 60)
    cv.box("Wood", oak, (-0.9, 0, -0.7), (0.9, 0.3, 0.7))
    cv.box("Wood", oak, (-0.3, 0.3, -0.3), (0.3, 2.9, 0.3))
    cv.where("Wood", (150, 106, 70), lambda x, y, z: (np.abs(x) <= 1.1) & (np.abs(y - (3.15 + (z * 0.35))) <= 0.12) & (np.abs(z) <= 0.75), (-1.1, 2.7, -0.8), (1.1, 3.6, 0.8))
    cv.box("Wood", oak, (-1.1, 2.75, -0.85), (1.1, 2.95, -0.7))
    # the open journal (cream pages with ink lines, a red ribbon)
    def page(x, y, z):
        line = ((np.floor((z + 1) / 0.125).astype(int) % 2) == 0) & (np.abs(x) > 0.15) & (np.abs(x) < 0.8)
        return np.where(line[:, None], np.array((150, 140, 128), float), np.array(CREAM, float))
    cv.where("Paper", page, lambda x, y, z: (np.abs(x) <= 0.9) & (np.abs(z) <= 0.55) & (np.abs(y - (3.32 + z * 0.35 + 0.05 * np.abs(x))) <= 0.07), (-0.9, 3.0, -0.6), (0.9, 3.6, 0.6))
    cv.box("Cloth", RED_A, (-0.05, 2.7, -0.75), (0.05, 3.25, -0.6))
    # a half-melted candle stub with its wax run, and a quill
    cv.cyl("Wax", (238, 232, 214), (0.95, 0, 0.45), 0.16, 3.25, 3.65)
    cv.ell("Wax", (238, 232, 214), (0.95, 3.27, 0.45), (0.3, 0.07, 0.28))
    cv.box("Wax", (238, 232, 214), (1.06, 2.95, 0.6), (1.14, 3.27, 0.68))
    cv.box("Wick", (60, 50, 40), (0.93, 3.65, 0.43), (0.97, 3.75, 0.47))
    cv.ell("Flame", EMBER_L, (0.95, 3.85, 0.45), (0.06, 0.1, 0.06))
    cv.seg("Quill", WHITE_C, (-0.7, 3.42, 0.1), (-0.2, 3.9, 0.45), 0.06)


def curio_b(cv):
    vs = cv.vs
    cv.box("Girder", STORM, (-1.2, 0, -0.2), (1.2, 1.6, 1.4))
    cv.box("Girder", STORM_L, (-1.25, 1.45, -0.25), (1.25, 1.6, 1.45))
    for s in (-1, 1):
        cv.box("Brass", BRASS, (s * 0.7 - 0.15, 1.1, -0.27), (s * 0.7 + 0.15, 1.45, -0.2))
    cv.cyl("Copper", COPPER, (-0.6, 0, -0.6), 0.3, 0, 4.4)
    cv.cyl("Brass", BRASS, (-0.6, 0, -0.6), 0.45, 0, 0.2)
    cv.ell("Copper", COPPER_D, (-0.6, 4.4, -0.6), (0.32, 0.25, 0.32))
    cv.cyl("Brass", BRASS, (-0.6, 3.4, -0.6), 0.4, -1.0, -0.6, axis=2)
    cv.torus("Wheel", RED, (-0.6, 3.4, -1.05), 0.8, 0.1, axis=2)
    for k in range(4):
        a = k / 4.0 * 6.28 + 0.4
        cv.seg("Wheel", RED, (-0.6, 3.4, -1.05), (-0.6 + math.cos(a) * 0.78, 3.4 + math.sin(a) * 0.78, -1.05), 0.06)
    # the chalk arrow on the pipe (turn this way), a red wrench leaning on the box, a mug
    cv.box("Chalk", (236, 236, 228), (-0.95, 2.2, -0.92), (-0.25, 2.3, -0.88))
    cv.box("Chalk", (236, 236, 228), (-0.4, 2.1, -0.92), (-0.25, 2.4, -0.88))
    cv.seg("Wrench", (200, 46, 40), (0.6, 0.05, -0.7), (0.9, 1.4, -0.3), 0.09)
    cv.box("Wrench", (170, 172, 180), (0.75, 1.35, -0.45), (1.1, 1.6, -0.15))
    cv.cyl("Mug", WHITE_C, (0.5, 0, 0.6), 0.2, 1.6, 2.0)
    cv.cyl("Coffee", (70, 44, 30), (0.5, 0, 0.6), 0.14, 1.92, 2.0)
    cv.box("Mug", WHITE_C, (0.68, 1.7, 0.55), (0.8, 1.9, 0.65))


def curio_c(cv):
    vs = cv.vs
    def pot(x, y, z):
        crack = np.abs(np.arctan2(z, x) - 2.4 - 0.15 * np.sin(y * 7)) < 0.06
        return np.where(crack[:, None], np.array((90, 50, 36), float), np.array((196, 116, 82), float))
    cv.where("Pot", pot, lambda x, y, z: ((x ** 2 + z ** 2) <= (0.75 + 0.15 * y) ** 2) & ((x ** 2 + z ** 2) >= (0.6 + 0.15 * y) ** 2 * (y > 0.15)) & (y <= 1.55)
             & ~((y > 1.0) & (x < -0.2) & (z < -0.2)), (-1.0, 0, -1.0), (1.0, 1.55, 1.0))
    cv.torus("Pot", (210, 130, 94), (0, 1.55, 0), 0.92, 0.1, axis=1)
    cv.where("Soil", SOIL[0], lambda x, y, z: ((x + 0.9) ** 2 / 1.3 + (z + 0.9) ** 2 <= 0.7) & (y <= 0.12), (-2.0, 0, -2.0), (0.0, 0.2, 0.0))
    cv.cyl("Soil", SOIL[1], (0, 0, 0), 0.75, 1.3, 1.42)
    cv.ell("Leaf", LEAF_L, (0.1, 1.6, 0.0), (0.25, 0.3, 0.2))
    # the patched watering can
    zinc = (150, 170, 186)
    cv.cyl("Can", zinc, (1.7, 0, -0.4), 0.48, 0, 1.0)
    cv.box("Can", (176, 140, 92), (1.3, 0.35, -0.86), (1.65, 0.65, -0.82), mode="all")
    cv.seg("Can", zinc, (1.35, 0.3, -0.5), (0.85, 1.1, -0.9), 0.1)
    cv.cyl("Can", (120, 140, 156), (0.82, 1.12, -0.92), 0.16, 1.05, 1.2)
    cv.torus("Can", zinc, (1.7, 1.3, -0.4), 0.38, 0.06, axis=0)
    # the seed packet and seeds; the shears lying open
    cv.box("Paper", (232, 222, 196), (-1.5, 0, -1.7), (-0.5, 0.08, -1.0))
    cv.box("Paper", (110, 170, 90), (-1.35, 0.08, -1.55), (-0.65, 0.1, -1.2), mode="all")
    for k in range(9):
        sx, sz = -0.3 + 0.9 * _hash(k, 1), -1.9 + 0.9 * _hash(k, 2)
        cv.box("Seed", (128, 96, 54), (sx - 0.06, 0, sz - 0.06), (sx + 0.06, 0.08, sz + 0.06))
    cv.seg("Shears", (180, 184, 190), (0.6, 0.06, -1.6), (1.6, 0.06, -1.3), 0.05)
    cv.seg("Shears", (180, 184, 190), (0.6, 0.06, -1.6), (1.5, 0.06, -1.9), 0.05)
    cv.seg("Shears", (196, 60, 50), (0.6, 0.06, -1.6), (0.15, 0.06, -1.75), 0.07)
    cv.seg("Shears", (196, 60, 50), (0.6, 0.06, -1.6), (0.2, 0.06, -1.4), 0.07)


# ------------------------------------------------------------------------------------------------ torches (origin on the wall face; flame Part at (0, 1.9, -1.05) +-(0.4, 0.65, 0.4))
def torch_a(cv):
    vs = cv.vs
    cv.box("Iron", IRON, (-0.3, 0.1, -0.13), (0.3, 1.5, 0))
    for yy in (0.3, 1.3):
        cv.box("Rivet", (100, 106, 126), (-0.06, yy - 0.06, -0.19), (0.06, yy + 0.06, -0.13))
    cv.path("Iron", IRON, [(0, 0.75, -0.1), (0, 0.65, -0.55), (0, 0.85, -0.95), (0, 1.0, -1.05)], 0.09)
    # the cage: a cup, four straight bars and a top ring (the boss room hangs ten of these: the room budget)
    cv.torus("Iron", IRON, (0, 1.95, -1.05), 0.6, 0.05, axis=1)
    for dx, dz in ((0.6, 0), (-0.6, 0), (0, 0.6), (0, -0.6)):
        cv.box("Iron", IRON, (dx - 0.06, 1.0, -1.05 + dz - 0.06), (dx + 0.06, 1.95, -1.05 + dz + 0.06))
    cv.cyl("Iron", IRON, (0, 0, -1.05), 0.62, 0.9, 1.05)
    # the soot mark on the stone above (a thin dark film on the face)
    # (a faint smoke stain, not a black egg: two bands, narrower and shorter)
    cv.where("Soot", lambda x, y, z: np.repeat(np.full(len(x), 88.0)[:, None], 3, 1) * np.array([1.0, 1.0, 1.08]),
             lambda x, y, z: ((x / (0.25 + 0.2 * (y - 2.3))) ** 2 + ((y - 3.2) / 1.0) ** 2 <= 1.0) & (z >= -0.125) & (z < 0), (-0.8, 2.2, -0.125), (0.8, 4.2, 0))


def torch_b(cv):
    vs = cv.vs
    cv.box("Brass", BRASS, (-0.25, 2.6, -0.125), (0.25, 3.6, 0))
    cv.seg("Iron", IRON, (0, 3.3, -0.1), (0, 3.3, -1.05), 0.08)
    cv.seg("Iron", IRON, (0, 3.3, -0.4), (0, 2.75, -0.1), 0.06)
    cv.box("Iron", IRON, (-0.04, 3.05, -1.09), (0.04, 3.3, -1.01))
    cv.box("Brass", BRASS, (-0.62, 1.05, -1.67), (0.62, 1.25, -0.43))
    for dx in (-0.55, 0.55):
        for dz in (-0.55, 0.55):
            cv.box("Brass", BRASS_D, (dx - 0.07, 1.25, -1.05 + dz - 0.07), (dx + 0.07, 2.75, -1.05 + dz + 0.07))
    cv.where("Brass", BRASS, lambda x, y, z: (np.maximum(np.abs(x), np.abs(z + 1.05)) <= 0.66 - (y - 2.75) * 1.2) & (y >= 2.75) & (y <= 3.05), (-0.7, 2.75, -1.75), (0.7, 3.05, -0.35))
    cv.torus("Brass", BRASS, (0, 3.08, -1.05), 0.12, 0.04, axis=0)
    for s in (-1, 1):
        cv.box("Glass", (220, 236, 240), (-0.5, 1.25, -1.05 + s * 0.53 - 0.03), (0.5, 2.75, -1.05 + s * 0.53 + 0.03), glass=60)
        cv.box("Glass", (220, 236, 240), (s * 0.53 - 0.03, 1.25, -1.55), (s * 0.53 + 0.03, 2.75, -0.55), glass=60)


def torch_c(cv):
    vs = cv.vs
    cv.box("Iron", IRON, (-0.2, 2.75, -0.125), (0.2, 3.55, 0))
    cv.path("Iron", IRON, [(0, 3.3, -0.1), (0, 3.35, -0.7), (0, 3.25, -1.05), (0, 3.05, -1.05)], 0.06)
    cv.path("Iron", (110, 110, 110), [(-0.7, 2.75, -1.05), (-0.35, 3.0, -1.05), (0, 3.05, -1.05), (0.35, 3.0, -1.05), (0.7, 2.75, -1.05)], 0.035)
    cv.cyl("Glass", (210, 236, 226), (0, 0, -1.05), 0.7, 1.0, 2.7, glass=55)  # solid (a hollow jar doubles its faces)
    cv.cyl("Glass", (190, 220, 210), (0, 0, -1.05), 0.7, 0.9, 1.05, glass=55)
    cv.cyl("Twine", (200, 178, 120), (0, 0, -1.05), 0.76, 2.45, 2.62)  # the twine round the neck


# ------------------------------------------------------------------------------------------------ arch tops (origin: floor centre of the arch; pillars at x +-(w/2 + 1))
def _arch_frame(w):
    hs = w / 2.0
    if w >= 10:
        return hs, 10.5, 3.9  # half-span, springing on the 10.5 pillar tops, rise (inner apex 14.4; ceiling 15.8)
    return hs, 7.0, 2.6  # the 6-wide arch on its 7-stud pillars


def arch_a(cv, w):
    vs = cv.vs
    hs, y0, rise = _arch_frame(w)
    c = max(0.0, (rise ** 2 - hs ** 2) / (2 * hs))
    rin = c + hs
    thick = 0.95 if w >= 10 else 0.8

    def mask(x, y, z):
        cx = np.where(x <= 0, c, -c)
        d = np.sqrt((x - cx) ** 2 + (y - y0) ** 2)
        return (y >= y0) & (d >= rin) & (d <= rin + thick) & (np.abs(z) <= 1.0)

    def col(x, y, z):
        cx = np.where(x <= 0, c, -c)
        ang = np.arctan2(y - y0, np.abs(x - cx))
        k = np.floor(ang / 0.13).astype(int)
        jn = ((ang / 0.13) % 1.0) < 0.14
        f = np.where(jn, 0.7, 0.86 + 0.07 * np.floor(_hv(k, np.sign(x).astype(int) + 3, 7) * 3))  # three voussoir shades
        return np.repeat(f[:, None], 3, 1) * np.array(GRANITE_L, float)

    top = y0 + math.sqrt(max(0.0, (rin + thick) ** 2 - c ** 2)) + 0.3
    cv.where("Voussoir", col, mask, (-hs - thick - 1, y0, -1.0), (hs + thick + 1, top, 1.0))
    # the slate hood mould over it and the keystone
    def hood(x, y, z):
        cx = np.where(x <= 0, c, -c)
        d = np.sqrt((x - cx) ** 2 + (y - y0) ** 2)
        return (y >= y0 + 0.5) & (d >= rin + thick) & (d <= rin + thick + 0.25) & (np.abs(z) <= 1.1)
    cv.where("Hood", SLATE_A, hood, (-hs - thick - 1.5, y0, -1.1), (hs + thick + 1.5, top + 0.3, 1.1))
    apex = y0 + math.sqrt(max(0.0, rin ** 2 - c ** 2))
    cv.box("Keystone", (190, 194, 210), (-0.45, apex - 0.2, -1.1), (0.45, apex + thick + 0.15, 1.1))
    # springers on the pillar caps
    for s in (-1, 1):
        cv.box("Voussoir", GRANITE, (s * (hs + 1) - 1.3, y0 - 0.4, -1.1), (s * (hs + 1) + 1.3, y0 + 0.2, 1.1))


def arch_b(cv, w):
    vs = cv.vs
    hs = w / 2.0
    big = w >= 10
    yb0, yb1 = (11.0, 12.4) if big else (8.4, 9.5)
    L = hs + 2.3
    cv.box("Girder", STORM, (-L, yb0, -0.45), (L, yb1, 0.45))
    for zz in (-1, 1):
        cv.box("Girder", STORM_L, (-L, yb0, zz * 0.7 - 0.25), (L, yb0 + 0.25, zz * 0.7 + 0.25))
        cv.box("Girder", STORM_L, (-L, yb1 - 0.25, zz * 0.7 - 0.25), (L, yb1, zz * 0.7 + 0.25))
    for xx in np.arange(-L + 0.4, L - 0.2, 0.8):
        for yy in (yb0 + 0.12, yb1 - 0.12):
            cv.box("Rivet", BRASS, (xx - vs / 2, yy - vs / 2, -0.95 - vs), (xx + vs / 2, yy + vs / 2, -0.95), mode="empty")
    if big:
        for s in (-1, 1):
            cv.seg("Girder", STORM, (s * (hs - 0.1), 9.2, 0), (s * (hs - 2.2), yb0, 0), 0.22)
            cv.box("Brass", BRASS, (s * (hs + 1) - 1.3, 10.5, -1.3), (s * (hs + 1) + 1.3, 10.7, 1.3))
    else:
        for s in (-1, 1):
            cv.box("Girder", STORM, (s * (hs + 1) - 0.6, 7.0, -0.45), (s * (hs + 1) + 0.6, yb0, 0.45))
    # the brass plaque with its element lamp, and the little weathervane on top
    cv.box("Brass", BRASS, (-0.8, yb0 + 0.25, -1.05), (0.8, yb1 - 0.25, -0.95))
    cv.ell("Element", grey(0.95), (0, (yb0 + yb1) / 2, -1.1), (0.18, 0.18, 0.1))
    vy = yb1 + (1.4 if big else 1.0)
    cv.cyl("Brass", BRASS_D, (0, 0, 0), 0.16, yb1, vy + 0.4)  # r >= 0.71 cell: an axis on a cell corner (r 0.08) hit no cell centre, so the vane floated
    cv.seg("Brass", BRASS, (-1.1, vy, 0), (1.0, vy, 0), 0.07)
    cv.where("Brass", BRASS, lambda x, y, z: (x >= 1.0) & (np.abs(y - vy) <= (1.4 - x) * 0.9) & (x <= 1.4) & (np.abs(z) < 0.06), (1.0, vy - 0.4, -0.1), (1.4, vy + 0.4, 0.1))
    cv.where("Brass", BRASS, lambda x, y, z: (x <= -1.0) & (x >= -1.5) & (np.abs(y - vy) <= 0.35) & (np.abs(z) < 0.06), (-1.5, vy - 0.4, -0.1), (-1.0, vy + 0.4, 0.1))
    if big:
        for k in range(3):
            a = k / 3.0 * 6.28
            cv.seg("Brass", BRASS, (0, vy + 0.45, 0), (math.cos(a) * 0.45, vy + 0.45, math.sin(a) * 0.45), 0.04)
            cv.ell("Brass", BRASS, (math.cos(a) * 0.5, vy + 0.45, math.sin(a) * 0.5), (0.12, 0.12, 0.12))


def arch_c(cv, w):
    vs = cv.vs
    hs = w / 2.0
    big = w >= 10
    x0 = hs + 1.0
    ybase, h = (10.5, 3.9) if big else (7.0, 2.6)
    # one thick root over the aisle with a thinner one twisting round it (the room budget: two full strands cost 1k more)
    for ph, r0, r1 in ((0.0, 0.42 if big else 0.34, 0.3 if big else 0.26), (math.pi, 0.2, 0.14)):
        pts = []
        for t in np.linspace(0, 1, 12):
            a = math.pi * t
            pts.append((-x0 * math.cos(a), ybase + h * math.sin(a), 0.45 * math.sin(a * 3 + ph)))
        cv.path("Bark", bark, pts, r0, r1)
    for k in range(10):
        t = 0.08 + 0.84 * k / 9.0
        a = math.pi * t
        p = (-x0 * math.cos(a), ybase + h * math.sin(a) + 0.35, 0.5 * (1 if k % 2 else -1))
        cv.ell("Leaf", leafy, p, (0.42, 0.2, 0.32))
    for k, xx in enumerate((-2.5, 0.6, 3.0) if big else (-1.6, 1.4)):
        a = math.acos(max(-1, min(1, -xx / x0)))
        yy = ybase + h * math.sin(a)
        drop = 1.4 if big else 0.6
        cv.box("Cord", (60, 54, 46), (xx - 0.06, yy - drop, -0.06), (xx + 0.06, yy, 0.06))
        cv.ell("Element", grey(0.95), (xx, yy - drop - 0.25, 0), (0.25, 0.25, 0.25))


# ------------------------------------------------------------------------------------------------ the rest
def window_a(cv):
    """the round sky window (origin on the back wall face at its centre; -z into the room)"""
    vs = cv.vs
    def sky(x, y, z):
        t = np.floor(np.clip((y + 3.0) / 6.0, 0, 0.999) * 4) / 3.0
        c = np.array((210, 230, 250), float) * (1 - t)[:, None] + np.array((150, 196, 246), float) * t[:, None]
        cloud = ((x + 1.0) ** 2 / 1.6 + (y + 1.2) ** 2 / 0.25 <= 1.0) | ((x - 1.1) ** 2 / 1.0 + (y - 0.9) ** 2 / 0.16 <= 1.0) | ((x + 0.2) ** 2 / 0.5 + (y + 0.95) ** 2 / 0.3 <= 1.0)
        return np.where(cloud[:, None], np.array((250, 250, 252), float), c)
    cv.cyl("Sky", sky, (0, 0, 0), 2.75, -0.2, -0.05, axis=2)
    def ring(x, y, z):
        ang = np.arctan2(y, x)
        k = np.floor(ang / 0.33).astype(int)
        jn = ((ang / 0.33) % 1.0) < 0.12
        f = np.where(jn, 0.7, 0.86 + 0.07 * np.floor(_hv(k, 5) * 3))
        return np.repeat(f[:, None], 3, 1) * np.array(GRANITE_L, float)
    cv.cyl("Stone", ring, (0, 0, 0), 3.55, -0.65, 0, axis=2, r0=2.7)
    cv.cyl("Hood", SLATE_A, (0, 0, 0), 3.75, -0.45, 0, axis=2, r0=3.5)
    cv.box("Iron", IRON, (-2.75, -0.1, -0.35), (2.75, 0.1, -0.2))
    cv.box("Iron", IRON, (-0.1, -2.75, -0.35), (0.1, 2.75, -0.2))
    cv.torus("Iron", IRON, (0, 0, -0.28), 1.35, 0.08, axis=2)
    cv.box("Stone", GRANITE, (-2.2, -3.75, -0.85), (2.2, -3.35, 0))


def cloud_b(cv):
    for k in range(4):
        a = k / 4.0 * 6.28 + 0.785
        cv.ell("Cloud", lambda x, y, z: np.where((y > 0.1)[:, None], np.array((250, 250, 252), float), np.array((214, 220, 236), float)),
               (math.cos(a) * 0.82, 0.05 * (k % 2), math.sin(a) * 0.82), (0.55, 0.45, 0.55))
    cv.ell("Cloud", (246, 248, 252), (0, 0.72, 0), (0.55, 0.38, 0.55))
    cv.ell("Cloud", (214, 220, 236), (0, -0.7, 0), (0.45, 0.3, 0.45))


def ring_b(cv):
    vs = cv.vs
    cv.torus("Brass", BRASS, (0, 0, 0), 2.4, 0.15, axis=2)
    for k in range(12):
        a = k / 12.0 * 6.28
        cv.ell("Brass", BRASS_D if k % 3 else (240, 200, 110), (math.cos(a) * 2.4, math.sin(a) * 2.4, 0), (0.17, 0.17, 0.22))


def barrel(cv):
    def staves(x, y, z):
        a = np.arctan2(z, x)
        k = np.floor(a / 0.35).astype(int)
        f = np.where(((a / 0.35) % 1.0) < 0.14, 0.72, 0.9 + 0.1 * _hv(k, 3))
        return np.repeat(f[:, None], 3, 1) * np.array((150, 100, 66), float)
    cv.where("Wood", staves, lambda x, y, z: (x ** 2 + z ** 2) <= (1.3 + 0.15 * np.sin(np.clip(y / 3.2, 0, 1) * math.pi)) ** 2,
             (-1.5, 0, -1.5), (1.5, 3.2, 1.5))
    for yy in (0.55, 2.65):
        cv.cyl("Iron", IRON, (0, 0, 0), 1.48, yy - 0.12, yy + 0.12)
    cv.where("Wood", lambda x, y, z: np.where(((np.floor(x / 0.45).astype(int)) % 2 == 0)[:, None], np.array(WOOD, float), np.array(WOOD_D, float)),
             lambda x, y, z: (x ** 2 + z ** 2) <= 1.18 ** 2, (-1.2, 3.05, -1.2), (1.2, 3.2, 1.2))


def cauldron(cv):
    cv.where("Iron", IRON, lambda x, y, z: ((x ** 2 + z ** 2) <= (1.95 - 0.55 * ((y - 2.2) / 1.7) ** 2) ** 2) & ((x ** 2 + z ** 2) >= (1.75 - 0.55 * ((y - 2.2) / 1.7) ** 2) ** 2 * (y > 0.9)) & (y >= 0.5) & (y <= 3.2),
             (-2.0, 0.5, -2.0), (2.0, 3.2, 2.0))
    cv.torus("Iron", (84, 92, 114), (0, 3.2, 0), 1.95, 0.14, axis=1)
    for k in range(3):
        a = k / 3.0 * 6.28 + 0.3
        cv.seg("Iron", IRON, (math.cos(a) * 1.2, 0.8, math.sin(a) * 1.2), (math.cos(a) * 1.4, 0, math.sin(a) * 1.4), 0.16)
    for s in (-1, 1):
        cv.torus("Iron", IRON, (s * 2.05, 2.9, 0), 0.32, 0.07, axis=0)


DESIGNS = {
    ("a", "throne"): throne_a, ("b", "throne"): throne_b, ("c", "throne"): throne_c,
    ("a", "statue"): statue_a, ("b", "statue"): statue_b, ("c", "statue"): statue_c,
    ("a", "brazier"): brazier_a, ("b", "brazier"): brazier_b, ("c", "brazier"): brazier_c,
    ("a", "banner"): banner_a, ("b", "banner"): banner_b, ("c", "banner"): banner_c,
    ("a", "curio"): curio_a, ("b", "curio"): curio_b, ("c", "curio"): curio_c,
    ("a", "torch"): torch_a, ("b", "torch"): torch_b, ("c", "torch"): torch_c,
    ("a", "arch_10"): lambda cv: arch_a(cv, 10), ("b", "arch_10"): lambda cv: arch_b(cv, 10), ("c", "arch_10"): lambda cv: arch_c(cv, 10),
    ("a", "arch_6"): lambda cv: arch_a(cv, 6), ("b", "arch_6"): lambda cv: arch_b(cv, 6), ("c", "arch_6"): lambda cv: arch_c(cv, 6),
    ("a", "window"): window_a, ("b", "cloud"): cloud_b, ("b", "ring"): ring_b,
    ("", "barrel"): barrel, ("", "cauldron"): cauldron,
}
VS = {"throne": 0.125, "statue": 0.125, "brazier": 0.125, "banner": 0.125, "curio": 0.1, "torch": 0.0625, "arch_10": 0.2,
      "arch_6": 0.2, "window": 0.125, "cloud": 0.16, "ring": 0.125, "barrel": 0.16, "cauldron": 0.2,
      # (the curvier designs one step coarser: the budget)
      ("c", "throne"): 0.15, ("c", "statue"): 0.14, ("b", "brazier"): 0.18, ("c", "brazier"): 0.2, ("c", "curio"): 0.16,
      ("a", "torch"): 0.125, ("c", "torch"): 0.16, ("a", "brazier"): 0.15, ("a", "banner"): 0.16}


def _sig(m, key):
    from props import arena as AR
    try:
        t = AR.target(key)
    except KeyError:
        return None
    bad = [x for x in AR.world()["BadList"] if x.startswith(key + ":")]
    if bad:
        raise RuntimeError("%s: tagged targets differ: %s" % (key, bad[:3]))
    m.attachments["LayoutSig"] = AR.layout_sig(t["Sig"])
    return t


@prop("dp_design")
def dp_design(entry, kit):
    from props import arena as AR
    a = entry.get("args") or {}
    style, what = a.get("style", ""), a["what"]
    vs = float(a.get("vs", VS.get((style, what), VS.get(what, 0.125))))
    cv = Canvas(vs)
    DESIGNS[(style, what)](cv)
    m = kit.model(entry["key"], "prop", vs=vs, K=1.0)
    tries = finish(m, cv, {"Element": "Secondary"}, AR.budget_tris(entry, 3500))
    m.groups, m.attachments = {}, {}
    t = _sig(m, entry["key"]) if a.get("sig", True) else None
    m.meta = {"source": "designed: %s %s" % (style or "shared", what), "pivot": "the Tag origin", "tries": tries,
              "target": t["Name"] if t else None}
    return m


# ------------------------------------------------------------------------------------------------ element weathering
# frames: high = on the wall face just under the cornice (y 0 = 14.8 studs), hanging down to about -3, -z into the
# room (0 .. -1.2); low = at the wall foot on the floor (z 0 = the wall face; the plinth fills z 0..-0.7 up to y 1.2),
# spreading 2.6 into the room
def _streaks(cv, rgb, n, x0, x1, ymax, ymin, seed, thick=0.125):
    for k in range(n):
        x = x0 + (x1 - x0) * _hash(seed, k, 1)
        ln = ymin + (ymax - ymin) * _hash(seed, k, 2)
        cv.box("Stain", rgb, (x - 0.1, ymax - ln, -thick), (x + 0.1, ymax, 0))


def wx(cv, element, spot):
    vs = cv.vs
    hi = spot == "high"
    if element == "nature":
        if hi:
            cv.box("Moss", MOSS, (-2.2, -0.45, -0.45), (2.2, 0, -0.05))
            for k in range(14):
                x = -2.1 + 4.2 * _hash(k, 1)
                ln = 0.5 + 2.2 * _hash(k, 2)
                cv.box("Moss", MOSS if k % 2 else MOSS_L, (x - 0.1, -0.45 - ln, -0.3), (x + 0.1, -0.45, -0.1))
                if k % 3 == 0:
                    cv.ell("Leaf", LEAF_L, (x, -0.45 - ln, -0.25), (0.2, 0.14, 0.14))
            for s in (-1, 1):
                pts = [(s * 1.2, -0.3, -0.3), (s * 1.6, -0.9, -0.7), (s * 1.9, -1.4, -0.9)]
                cv.path("Leaf", LEAF, pts, 0.1)
                for t in range(3):
                    p = pts[t]
                    cv.ell("Leaf", LEAF_L, (p[0] + 0.2, p[1] - 0.1, p[2]), (0.25, 0.08, 0.15))
        else:
            cv.ell("Moss", lambda x, y, z: np.where((_hv(np.floor(x * 4).astype(int), np.floor(z * 4).astype(int), 2) < 0.4)[:, None], np.array(MOSS_L, float), np.array(MOSS, float)),
                   (0, 0.0, -0.9), (2.2, 0.45, 1.0))
            cv.box("Moss", MOSS, (-1.6, 1.2, -0.75), (1.4, 1.35, -0.1))
            for k, (fx, fz) in enumerate(((-1.2, -1.0), (0.9, -1.2))):
                for j in range(5):
                    a = j / 5.0 * 6.28
                    tip = (fx + math.cos(a) * 1.0, 0.9 + 0.4 * _hash(k, j), fz + math.sin(a) * 0.8)
                    cv.path("Leaf", LEAF if j % 2 else LEAF_L, [(fx, 0.2, fz), ((fx + tip[0]) / 2, 0.85, (fz + tip[2]) / 2), tip], 0.09, 0.05)
            for k, (mx, mz, h) in enumerate(((0.2, -1.9, 0.5), (0.55, -1.6, 0.35), (-0.4, -2.1, 0.28))):
                cv.cyl("Shroom", (236, 226, 204), (mx, 0, mz), 0.07, 0, h)
                cv.ell("Shroom", (176, 96, 64), (mx, h, mz), (0.22, 0.1, 0.22))
    elif element == "earth":
        amber, amber_l = (214, 150, 70), (246, 200, 120)
        if hi:
            cv.ell("Rock", (120, 104, 88), (0.4, -0.5, -0.25), (1.4, 0.6, 0.3))
            for k, (x, ang, ln) in enumerate(((-0.4, -0.5, 1.4), (0.3, 0.2, 1.8), (0.9, 0.7, 1.2), (1.4, 0.4, 0.9), (-0.9, -0.9, 0.9))):
                p0 = (x, -0.6, -0.3)
                p1 = (x + math.sin(ang) * ln * 0.6, -0.6 - math.cos(ang) * ln, -0.3 - ln * 0.35)
                cv.seg("Crystal", amber if k % 2 else amber_l, p0, p1, 0.2, 0.06)
        else:
            for k in range(9):
                x, z = -1.9 + 3.8 * _hash(k, 1), -0.8 - 1.6 * _hash(k, 2)
                r = 0.2 + 0.25 * _hash(k, 3)
                cv.ell("Rock", (126, 112, 96) if k % 2 else (104, 92, 80), (x, r * 0.6, z), (r, r * 0.8, r))
            for k, (x, z, ang) in enumerate(((0.6, -1.2, 0.3), (0.9, -1.0, -0.4), (0.4, -0.9, 0.0))):
                cv.seg("Crystal", amber if k % 2 else amber_l, (x, 0.1, z), (x + math.sin(ang) * 0.5, 1.0, z - 0.2), 0.16, 0.05)
    elif element == "water":
        wet = (70, 84, 104)
        if hi:
            _streaks(cv, wet, 10, -2.1, 2.1, 0, 1.0, 3)
            cv.box("Stain", wet, (-2.2, -0.35, -0.125), (2.2, 0, 0))
            for k in range(4):
                x = -1.6 + 3.2 * _hash(k, 9)
                cv.ell("Drop", (160, 210, 240), (x, -2.4 - 0.4 * _hash(k, 4), -0.15), (0.08, 0.13, 0.08))
            cv.box("Algae", (92, 150, 110), (-1.2, -0.45, -0.125), (0.6, -0.3, 0))
        else:
            _streaks(cv, wet, 6, -1.6, 1.6, 1.2, 0.4, 5)
            cv.where("Puddle", (120, 190, 236), lambda x, y, z: ((x / 2.0) ** 2 + ((z + 1.6) / 0.9) ** 2 + 0.2 * np.sin(x * 3) <= 1.0) & (y < 0.06),
                     (-2.2, 0, -2.6), (2.2, 0.06, -0.7), glass=40)
            cv.where("Stain", wet, lambda x, y, z: ((x / 2.2) ** 2 + ((z + 1.5) / 1.1) ** 2 <= 1.0) & (y < 0.03), (-2.3, 0, -2.7), (2.3, 0.03, -0.6), mode="empty")
            cv.box("Algae", (92, 150, 110), (-1.0, 1.2, -0.75), (1.2, 1.3, -0.2))
    elif element == "frost":
        ice, ice_l, rime = (170, 214, 240), (220, 240, 252), (236, 244, 250)
        if hi:
            cv.box("Rime", rime, (-2.2, -0.4, -0.5), (2.2, 0, -0.05))
            for k in range(13):
                x = -2.05 + 4.1 * k / 12.0 + 0.1 * _hash(k, 1)
                ln = 0.5 + 2.1 * _hash(k, 2) * (1.0 - 0.5 * abs(x) / 2.2)
                cv.seg("Ice", ice if k % 2 else ice_l, (x, -0.35, -0.28), (x, -0.4 - ln, -0.3), 0.16, 0.03)
        else:
            cv.where("Rime", rime, lambda x, y, z: ((x / 2.2) ** 2 + ((z + 1.4) / 1.2) ** 2 + 0.25 * _hv(np.floor(x * 4).astype(int), np.floor(z * 4).astype(int), 6) <= 1.1) & (y < 0.07),
                     (-2.3, 0, -2.7), (2.3, 0.07, -0.5))
            cv.box("Rime", rime, (-2.0, 1.2, -0.75), (2.0, 1.32, -0.1))
            for k, (x, z, s) in enumerate(((-1.0, -1.2, 0.45), (0.5, -1.7, 0.35), (1.2, -1.0, 0.3), (-0.2, -2.0, 0.25))):
                cv.box("Ice", ice if k % 2 else ice_l, (x - s, 0, z - s), (x + s, s * 1.3, z + s))
    elif element == "flame":
        if hi:
            cv.where("Soot", lambda x, y, z: np.repeat(_steps(np.clip(48 + 40 * np.abs(x) / 2.2 - 14 * y, 40, 110))[:, None], 3, 1),
                     lambda x, y, z: ((x / (0.8 + 0.5 * (-y))) ** 2 <= 1.0) & (y >= -2.8) & (z >= -0.125), (-2.3, -2.8, -0.125), (2.3, 0, 0))
            for k in range(3):
                pts = [(-1.2 + 1.2 * k + 0.3 * _hash(k, j), -0.4 - 0.5 * j, -0.19) for j in range(5)]
                cv.path("Ember", EMBER if k % 2 else EMBER_L, pts, 0.07)
        else:
            cv.where("Ash", (92, 88, 86), lambda x, y, z: ((x / 2.2) ** 2 + ((z + 1.4) / 1.2) ** 2 <= 1.0) & (y < 0.05), (-2.3, 0, -2.7), (2.3, 0.05, -0.5))
            for k in range(4):
                pts = [(-1.8 + 3.6 * _hash(k, j, 1), 0.06, -0.8 - 1.8 * _hash(k, j, 2)) for j in range(3)]
                cv.path("Ember", EMBER_L if k % 2 else EMBER, pts, 0.07)
            for k in range(6):
                x, z = -1.6 + 3.2 * _hash(k, 5), -0.9 - 1.4 * _hash(k, 6)
                r = 0.18 + 0.15 * _hash(k, 7)
                cv.ell("Coal", COAL, (x, r * 0.6, z), (r, r * 0.7, r))
                cv.box("Ember", EMBER, (x - 0.06, r * 0.9, z - 0.06), (x + 0.06, r * 1.15, z + 0.06))
    elif element == "storm":
        if hi:
            cv.where("Scorch", lambda x, y, z: np.repeat(_steps(np.clip(40 + 50 * np.sqrt(x ** 2 + (y + 1.3) ** 2), 40, 120))[:, None], 3, 1),
                     lambda x, y, z: (np.sqrt(x ** 2 + (y + 1.3) ** 2) <= 1.2 + 0.5 * np.abs(np.sin(np.arctan2(y + 1.3, x) * 5))) & (z >= -0.125), (-2.0, -3.0, -0.125), (2.0, 0, 0))
            cv.seg("Copper", (196, 118, 72), (0, -1.3, -0.1), (0, -1.3, -0.9), 0.1)
            cv.box("Insulator", WHITE_C, (-0.2, -1.5, -0.55), (0.2, -1.1, -0.35))
            cv.ell("Spark", (210, 236, 255), (0, -1.3, -1.0), (0.18, 0.18, 0.18))
            pts = [(0.0, -1.3, -1.0), (0.4, -1.8, -0.9), (0.15, -2.1, -0.8), (0.5, -2.6, -0.6)]
            cv.path("Spark", (180, 220, 255), pts, 0.05)
        else:
            cv.where("Scorch", (54, 54, 64), lambda x, y, z: (np.sqrt((x / 1.3) ** 2 + ((z + 1.4) / 0.9) ** 2) <= 1.0 + 0.4 * np.abs(np.sin(np.arctan2(z + 1.4, x) * 6))) & (y < 0.05),
                     (-2.3, 0, -2.7), (2.3, 0.05, -0.3))
            pts = [(-1.5 + 0.6 * math.cos(t * 9), 0.1, -1.5 + 0.4 * math.sin(t * 9) - t) for t in np.linspace(0, 1, 12)]
            cv.path("Copper", (196, 118, 72), pts, 0.05)
            cv.box("Insulator", WHITE_C, (0.8, 0, -1.3), (1.2, 0.35, -0.9))
    elif element == "celestial":
        sm = (54, 64, 120)
        def starmoss(x, y, z):
            st = _hv(np.floor(x * 8).astype(int), np.floor(y * 8).astype(int), np.floor(z * 8).astype(int), 4)
            return np.where((st < 0.06)[:, None], np.array((255, 240, 170), float), np.where((st > 0.9)[:, None], np.array((236, 240, 255), float), np.array(sm, float)))
        if hi:
            cv.box("Moss", starmoss, (-2.2, -0.5, -0.45), (2.2, 0, -0.05))
            for k in range(10):
                x = -2.0 + 4.0 * _hash(k, 3)
                ln = 0.4 + 1.6 * _hash(k, 4)
                cv.box("Moss", starmoss, (x - 0.12, -0.5 - ln, -0.32), (x + 0.12, -0.5, -0.08))
            cv.box("Cord", (180, 180, 200), (0.4 - 0.03, -2.4, -0.33), (0.4 + 0.03, -0.5, -0.27))
            for k in range(5):
                a = k / 5.0 * 6.28 + 1.57
                cv.seg("Star", (255, 222, 120), (0.4, -2.65, -0.3), (0.4 + math.cos(a) * 0.32, -2.65 + math.sin(a) * 0.32, -0.3), 0.09, 0.03)
        else:
            cv.ell("Moss", starmoss, (0, 0, -1.0), (2.1, 0.4, 1.0))
            cv.box("Moss", starmoss, (-1.4, 1.2, -0.75), (1.4, 1.35, -0.1))
            for k in range(5):
                a = k / 5.0 * 6.28 + 1.57
                cv.seg("Star", (255, 222, 120), (0.7, 0.55, -1.5), (0.7 + math.cos(a) * 0.4, 0.55 + math.sin(a) * 0.4, -1.5), 0.11, 0.03)
    elif element == "shadow":
        dk, dk_l = (70, 48, 104), (130, 92, 176)
        if hi:
            cv.where("Stain", (52, 44, 70), lambda x, y, z: ((x / 2.0) ** 2 + ((y + 1.0) / 1.4) ** 2 <= 1.0) & (z >= -0.125), (-2.0, -2.5, -0.125), (2.0, 0, 0))
            for k, (x, ang, ln) in enumerate(((-0.8, -0.6, 1.3), (-0.1, 0.1, 1.9), (0.6, 0.6, 1.4), (1.2, 0.9, 0.8), (-1.4, -1.0, 0.8))):
                cv.seg("Crystal", dk if k % 2 else dk_l, (x, -0.4, -0.15), (x + math.sin(ang) * ln * 0.6, -0.4 - math.cos(ang) * ln, -0.3 - ln * 0.4), 0.22, 0.05)
        else:
            cv.where("Stain", (44, 38, 60), lambda x, y, z: ((x / 2.2) ** 2 + ((z + 1.4) / 1.2) ** 2 <= 1.0) & (y < 0.04), (-2.3, 0, -2.7), (2.3, 0.04, -0.5))
            for k, (x, z, ang, ln) in enumerate(((-0.5, -1.0, -0.3, 1.5), (0.1, -1.1, 0.2, 1.9), (0.6, -0.9, 0.6, 1.2), (-1.1, -1.4, -0.7, 0.9), (1.2, -1.5, 0.9, 0.8))):
                cv.seg("Crystal", dk if k % 2 else dk_l, (x, 0.1, z), (x + math.sin(ang) * ln * 0.5, ln, z - 0.25), 0.22, 0.05)


@prop("dp_wx")
def dp_wx(entry, kit):
    from props import arena as AR
    a = entry.get("args") or {}
    vs = float(a.get("vs", 0.15))
    cv = Canvas(vs)
    wx(cv, a["element"], a["spot"])
    m = kit.model(entry["key"], "prop", vs=vs, K=1.0)
    tries = finish(m, cv, {}, AR.budget_tris(entry, 1800))
    m.groups, m.attachments = {}, {}
    m.meta = {"source": "designed weathering %s %s" % (a["element"], a["spot"]), "pivot": "the Tag origin", "tries": tries}
    return m
