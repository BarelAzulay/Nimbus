"""Pitch 2 item 10 A ("Workshop machines"): the roulette machines, one hand-placed pixel drawing per roulette, as data.
Ported from the approved mock-up script (.superpowers/slop-audit/round3/build/PITCH2/C_icons_machines/machines.py; its
option B drawings, not picked, are left out).

  A "Workshop machines"  each roulette a different capsule machine (glass full of eggs, a coin slot, a crank), its
                         own silhouette: Cloud a puffy cloud dome on a wooden drum, Storm a tall coiled tube under a
                         storm cloud with a lightning rod, Sky a glass ball in a brass sunburst, Celestial an orrery
                         (a starry orb, gold rings, planets, a crescent finial), Secret a chained vault with a rune dial
Grids: 52 x 60 cells (the Secret 60 x 68): 3 px cells on PC (156 x 180), 2 px on a phone (104 x 120): the kit's pixel
sizes. tools/build_upload_sheets.py bakes them into ONE sheet (build/upload_sheets/machines_a.png) at 1 px a cell.
"""
import math

from pixkit import Grid, PAL, RARITY, ROULETTE, ramp_from, lerp, S

MPAL = dict(PAL)
for _r, _c in RARITY.items():
    MPAL["R_" + _r] = ramp_from(_c)
MPAL["R_Secret"] = ((10, 10, 20), (30, 28, 50), (46, 44, 72), (90, 84, 140), (220, 210, 255))
MPAL["cloud"] = ((104, 120, 166), S["CloudSide"], (236, 242, 252), (255, 255, 255), (255, 255, 255))
MPAL["storm"] = ((34, 28, 74), (64, 56, 128), (92, 84, 170), (128, 120, 214), (190, 186, 250))
MPAL["night"] = ((20, 14, 46), (40, 30, 86), (62, 46, 120), (98, 76, 170), (255, 255, 255))
MPAL["vault"] = ((14, 16, 30), (34, 38, 62), (52, 58, 88), (78, 86, 122), (150, 160, 200))
MPAL["door"] = ((14, 16, 30), (44, 50, 78), (64, 72, 106), (92, 102, 140), (170, 180, 220))
MPAL["stone"] = ((40, 36, 62), (86, 80, 118), (118, 112, 152), (152, 146, 186), (210, 206, 240))
MPAL["rune"] = ((70, 30, 130), (150, 90, 240), (196, 150, 255), (226, 200, 255), (255, 255, 255))
RAR = ["R_" + r for r in RARITY]

EGGS = {  # ShopEggs K.EGGS (the eggs each machine shows), longer for the bigger glass
    "Cloud": ["Common", "Uncommon", "Common", "Rare", "Common", "Uncommon", "Common", "Epic", "Uncommon", "Common", "Rare"],
    "Storm": ["Rare", "Uncommon", "Rare", "Epic", "Uncommon", "Rare", "Legendary", "Rare", "Epic", "Uncommon", "Rare", "Epic", "Rare"],
    "Sky": ["Epic", "Rare", "Epic", "Legendary", "Rare", "Epic", "Mythic", "Rare", "Epic", "Legendary"],
    "Celestial": ["Legendary", "Epic", "Legendary", "Mythic", "Epic", "Legendary", "Secret", "Epic", "Mythic"],
}

SMALL_EGG = ["..xx..", ".xxxx.", "xxxxxx", "xxxxxx", "xxxxxx", "xxxxxx", ".xxxx."]


def small_egg(g, x0, y0, rarity):
    m = "R_" + rarity
    for y, row in enumerate(SMALL_EGG):
        for x, ch in enumerate(row):
            if ch == "x":
                g.put(x0 + x, y0 + y, m)
    g.tone(x0 + 1, y0 + 2, 4)                  # the spec
    for x in range(1, 5):                      # a lighter band (the EggArt stripe)
        g.tone(x0 + x, y0 + 4, 3)
    if rarity == "Secret":
        g.put(x0 + 3, y0 + 3, "*")


def big_egg(g, cx, cy, w, h, m, band=None, spots=None, stars=False):
    def inside(X, Y):
        # an egg: the widest line at cy, a longer top half (0.56 h) than bottom half (0.44 h), both elliptical
        t = (cy - Y) / (h * 0.56) if Y < cy else (Y - cy) / (h * 0.44)
        if t > 1:
            return False
        return abs(X - cx) <= (w / 2) * math.sqrt(max(0.0, 1 - t * t))
    g.fill(inside, m)
    if band:
        by = int(cy + h * 0.06)
        for dy, f in ((0, band), (1, band)):
            for x in range(int(cx - w / 2) - 1, int(cx + w / 2) + 2):
                if g.get(x, by + dy) == m:
                    if (x + dy) % 4 in (0, 1):
                        g.tone(x, by + dy - (1 if (x // 2) % 2 else 0), f)
                    else:
                        g.tone(x, by + dy, f)
    for (sx, sy, r) in (spots or []):
        g.circle(cx + sx, cy + sy, r, "b", only=(m,))
    # the spec: a short streak top-left
    sx, sy = int(cx - w * 0.24), int(cy - h * 0.26)
    for (dx, dy) in ((0, 0), (0, 1), (1, -1), (0, 2)):
        if g.get(sx + dx, sy + dy) == m:
            g.tone(sx + dx, sy + dy, 4)
    if stars:
        for (dx, dy) in ((w * 0.18, -h * 0.1), (-w * 0.1, h * 0.18), (w * 0.05, h * 0.3), (-w * 0.28, h * 0.02)):
            g.put(int(cx + dx), int(cy + dy), "*")


def heap(g, eggs, spots, inside_fn):
    """the small eggs at their spots, kept to the cells inside the glass"""
    for (x, y), r in zip(spots, eggs):
        if inside_fn(x + 3, y + 3):
            small_egg(g, x, y, r)


def ring(g, cx, cy, rx, ry, rot, m, part, th=0.75):
    """an elliptical ring (an orbit): `part` "back" (the upper half, behind) or "front" (the lower half)"""
    ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    for i in range(720):
        t = math.radians(i / 2)
        ex, ey = rx * math.cos(t), ry * math.sin(t)
        X, Y = cx + ex * ca - ey * sa, cy + ex * sa + ey * ca
        front = math.sin(t) > 0
        if (part == "front") == front:
            g.circle(X, Y, th, m)


def highlight(g, pts, only=("k",)):
    for (x, y) in pts:
        if g.get(x, y) in only:
            g.tone(x, y, 4)


# ------------------------------------------------------------------ A: workshop machines
def a_cloud():
    g = Grid(52, 60)
    g.rect(13, 56, 17, 59, "w")
    g.rect(34, 56, 38, 59, "w")
    g.rect(9, 45, 42, 56, "w")                        # the drum
    g.rect(8, 43, 43, 46, "l")                        # its top band
    for x in range(10, 42, 6):                        # the drum's staves
        for y in range(47, 56):
            g.tone(x, y, 1)
    g.rect(17, 48, 34, 54, "c")                       # the front plate
    g.rect(21, 50, 30, 51, "+")                       # the coin slot
    g.rect(23, 53, 28, 54, "n")                       # the chute
    g.rect(43, 49, 46, 50, "u")                       # the crank
    g.circle(47.6, 49.5, 2.7, "r")
    g.rect(14, 40, 37, 43, "l")                       # the collar
    lobes = ((15.5, 30.5, 9.6), (25.5, 22.5, 12.6), (36.0, 30.5, 9.6), (25.5, 32.0, 11.0))
    dome = lambda X, Y: Y <= 41 and any((X - a) ** 2 + (Y - b) ** 2 <= r * r for a, b, r in lobes)
    g.fill(dome, "k")
    spots = [(9, 34), (15, 35), (21, 35), (27, 35), (33, 34), (38, 32), (12, 28), (18, 29), (24, 29), (30, 28), (35, 26), (21, 23)]
    heap(g, EGGS["Cloud"] + ["Common"], spots, dome)
    for (a, b, r) in ((19.5, 11.5, 5.0), (26.0, 9.0, 6.6), (33.0, 12.0, 4.6), (13.5, 15.0, 3.2)):
        g.circle(a, b, r, "cloud")                    # the cloud cap
    highlight(g, [(15, 22), (14, 23), (13, 24), (12, 26), (12, 27), (18, 18), (19, 17), (20, 16), (37, 25), (38, 26)])
    return g, ["w", "l", "c", "n", "u", "r", "k"] + RAR + ["cloud"]


def a_storm():
    g = Grid(52, 60)
    g.rect(14, 56, 18, 59, "i")
    g.rect(33, 56, 37, 59, "i")
    g.rect(11, 45, 40, 56, "i")                       # the iron base
    g.rect(10, 43, 41, 45, "u")                       # its brass band
    for (x, y) in ((13, 47), (38, 47), (13, 54), (38, 54)):
        g.put(x, y, "u")                              # rivets
    g.rect(16, 47, 35, 54, "n")                       # the panel
    g.rect(20, 49, 31, 50, "+")
    g.poly([(25.5, 51), (28.5, 51), (26.8, 53), (28.8, 53), (24.5, 56.2), (25.8, 54), (23.8, 54)], "y")   # a bolt
    tube = lambda X, Y: (16 <= X <= 36 and 14 <= Y <= 43) or ((X - 26) / 10.0) ** 2 + ((Y - 14) / 3.0) ** 2 <= 1
    g.fill(tube, "k")
    # the copper coil is a helix wound round the glass: its back turns show through the glass (shaded glass, drawn
    # before the eggs), its front turns slope up to the right over them. (Level bands + eggs in a grid read as a shelf.)
    turns = (18, 26, 34)
    for y0 in turns:
        g.line(37, y0, 15, y0 - 3, tone=1)
        g.line(37, y0 + 1, 15, y0 - 2, tone=1)
    spots = [(16, 37), (22, 36), (28, 37), (30, 31), (17, 31), (23, 30), (16, 24), (21, 25), (27, 24), (30, 19), (19, 18), (25, 16)]
    heap(g, EGGS["Storm"], spots, tube)
    for y0 in turns:
        g.line(14, y0 + 5, 37, y0, "m")
        g.line(14, y0 + 6, 37, y0 + 1, "m")
        g.tone(15, y0 + 5, 3)
    g.rect(13, 9, 38, 12, "i")                        # the cap
    for (a, b, r) in ((19.0, 6.5, 4.4), (26.0, 4.6, 5.4), (33.0, 6.8, 4.3)):
        g.circle(a, b, r, "storm")                    # the storm cloud
    g.rect(43, 16, 44, 44, "u")                       # the lightning rod
    g.rect(40, 43, 44, 44, "u")
    g.poly([(42, 2), (47, 2), (44.5, 8), (48.5, 8), (41, 17.5), (43.2, 10.5), (40, 10.5)], "y")   # its bolt
    highlight(g, [(18, 15), (18, 16), (18, 17), (35, 40), (35, 41), (35, 42)])
    return g, ["i", "u", "n", "y", "k"] + RAR + ["m", "storm"]


def a_sky():
    g = Grid(52, 60)
    g.rect(9, 57, 43, 59, "l")                        # the step
    g.poly([(15, 46), (37, 46), (41, 57), (11, 57)], "c")  # the stone pedestal
    g.rect(14, 45, 38, 46, "y")                       # its gold trim
    g.rect(20, 49, 31, 50, "+")
    g.rect(22, 53, 29, 55, "n")
    g.rect(41, 49, 44, 50, "u")
    g.circle(45.6, 49.5, 2.5, "r")
    for i in range(12):                               # the sunburst (behind the glass)
        a = math.radians(-90 + i * 30)
        if math.sin(a) > 0.55:
            continue
        tip = (26 + 23.5 * math.cos(a), 27 + 23.5 * math.sin(a))
        l = (26 + 14 * math.cos(a - 0.2), 27 + 14 * math.sin(a - 0.2))
        r = (26 + 14 * math.cos(a + 0.2), 27 + 14 * math.sin(a + 0.2))
        g.poly([l, tip, r], "y")
    g.circle(26, 27, 16.4, "o")                       # the brass ring
    g.rect(19, 41, 32, 45, "u")                       # the neck
    ball = lambda X, Y: (X - 26) ** 2 + (Y - 27) ** 2 <= 13.6 ** 2
    g.fill(ball, "k")
    spots = [(14, 30), (20, 32), (26, 32), (32, 30), (17, 24), (23, 26), (29, 25), (34, 23), (20, 18), (27, 19)]
    heap(g, EGGS["Sky"], spots, ball)
    for (x, y) in ((25.5, 27), ):
        pass
    highlight(g, [(17, 17), (16, 18), (15, 19), (15, 20), (14, 22), (20, 15), (21, 14)])
    return g, ["l", "c", "y", "n", "u", "r", "o", "k"] + RAR


def a_celestial():
    g = Grid(52, 60)
    for (x0, x1) in ((24.5, 11.0), (27.5, 41.0)):     # the tripod
        g.poly([(x0 - 1.4, 46), (x0 + 1.4, 46), (x1 + 1.4, 59.4), (x1 - 1.4, 59.4)], "u")
    g.rect(25, 46, 26, 59, "u")
    g.rect(19, 43, 32, 47, "u")                       # the hub
    g.rect(22, 47, 29, 49, "v")
    ring(g, 26, 27, 23.5, 6.2, -14, "y", "back")      # the rings, their back halves
    ring(g, 26, 27, 21.0, 5.2, 28, "o", "back")
    orb = lambda X, Y: (X - 26) ** 2 + (Y - 26) ** 2 <= 13.4 ** 2
    g.fill(orb, "night")
    spots = [(14, 29), (20, 31), (26, 31), (32, 29), (17, 23), (23, 25), (29, 24), (21, 17), (27, 18)]
    heap(g, EGGS["Celestial"], spots, orb)
    for (x, y) in ((16, 16), (31, 14), (36, 20), (14, 22), (24, 13), (37, 31), (33, 37)):
        if g.get(x, y) == "night":
            g.put(x, y, "*")
    ring(g, 26, 27, 23.5, 6.2, -14, "y", "front")
    ring(g, 26, 27, 21.0, 5.2, 28, "o", "front")
    g.circle(3.6, 32.4, 2.6, "p")                     # the planets
    g.circle(47.0, 20.6, 2.2, "b")
    g.circle(9.0, 15.0, 1.6, "v")
    g.rect(25, 9, 26, 13, "u")                        # the crescent finial
    g.circle(26, 6.2, 5.2, "y")
    g.circle(28.6, 4.8, 4.4, erase=True)
    highlight(g, [(18, 16), (17, 17), (16, 18), (16, 19)], only=("night",))
    return g, ["u", "v", "o", "y", "night"] + RAR + ["p", "b"]


def a_secret():
    g = Grid(60, 68)
    g.rect(8, 63, 13, 67, "vault")
    g.rect(46, 63, 51, 67, "vault")
    g.rect(4, 12, 55, 63, "vault")                    # the safe
    g.rect(7, 8, 52, 12, "vault")
    g.rect(23, 3, 36, 4, "u")                         # the handle
    g.rect(23, 3, 24, 8, "u")
    g.rect(35, 3, 36, 8, "u")
    g.rect(9, 16, 50, 59, "door")                     # the door
    for (x, y) in ((11, 18), (47, 18), (11, 56), (47, 56)):
        g.rect(x, y, x + 1, y + 1, "u")
    g.circle(29.5, 37.5, 13.2, "u")                   # the rune dial
    g.circle(29.5, 37.5, 10.0, "night")
    big_egg(g, 29.5, 38.0, 10.0, 13.0, "R_Secret", stars=True)
    for i in range(10):                               # the runes round the dial
        a = math.radians(i * 36 - 90)
        g.put(int(29.5 + 11.6 * math.cos(a)), int(37.5 + 11.6 * math.sin(a)), "rune")
    g.rect(52, 34, 53, 42, "u")                       # the bolt bar at the hinge side
    for cy in (22, 52):                               # the chains, wrapped round the safe
        for i, x in enumerate(range(1, 59, 4)):
            if i % 2 == 0:
                g.rect(x, cy - 1, x + 3, cy + 1, "i")
                g.clear(x + 1, cy)
                g.clear(x + 2, cy)
            else:
                g.rect(x, cy, x + 3, cy, "i")
    g.rect(27, 53, 32, 54, "i")                       # the padlock's shackle
    g.rect(27, 53, 27, 57, "i")
    g.rect(32, 53, 32, 57, "i")
    g.rect(25, 57, 34, 64, "y")                       # its body
    g.rect(29, 59, 30, 61, "+")
    return g, ["vault", "u", "door", "night", "R_Secret", "rune", "i", "y"]


A = {"Cloud": a_cloud, "Storm": a_storm, "Sky": a_sky, "Celestial": a_celestial, "Secret": a_secret}

# (P2 icons review r1, major 1: the odds chips under the pixel machines drew today's smooth vector EggArt) the odds chip's
# egg, the approved mock-up's (make_item10.py EGG9 / odds_egg): a 9 x 9 egg in its rarity's ramp, a lighter band across
# row 5, the Secret egg a white star. 27 px on PC (3 px cells), 18 on a phone (2 px cells). The game draws it from the
# machines sheet (its egg row) or, without that cell, as a 9 x 9 PixelIcon glyph ("egg_<rarity>", the same drawing)
ODDS_EGG = "...eee.../..eEeee../..eeeee../.eeeeeee./.eeeeeee./.eeeeeee./.eeeeeee./.eeeeeee./..eeeee.."
ODDS_EGG_ORDER = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]


def odds_egg(rarity):
    """the odds chip egg of `rarity` as (Grid, z, palette)"""
    g = Grid.parse(ODDS_EGG, "e")
    for x in range(2, 7):
        g.tone(x, 5, 3)
    if rarity == "Secret":
        g.put(5, 4, "*")
    pal = dict(MPAL)
    pal["e"] = MPAL["R_" + rarity]
    return g, "", pal
