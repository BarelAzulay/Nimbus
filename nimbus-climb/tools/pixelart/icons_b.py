"""Pitch 2 item 9 B ("Carved soft"): the icon set as data. Ported from the approved mock-up script
(.superpowers/slop-audit/round3/build/PITCH2/C_icons_machines/iconset.py); one change: the Flame badge is the three-tongue
flame with a hollow core (spec item 12_elements A, "so it no longer reads as a second drop"), its core filled gold.

  NINE[name]  = (rows "r0/r1/.../r8", z-order, extra palette)   the 9 x 9 drawing (direction B's glyph at 27 / 18 px).
                One letter a material (pixkit.PAL), "." empty, an upper-case letter = that material's spec dot, a digit =
                a forced tone of the icon's main material, "-" = a forced outline cell, "+" = ink, "*" = a white spark.
                z = materials back to front: a back material outlines where a front one covers it.
  B18[name]() = a Grid (18 x 18): direction B's art-size drawing (54 px on PC = 3 px cells, 36 on a phone = 2 px cells:
                the same cell as the 9 x 9 glyphs at 27 / 18, so a screen has one pixel size)
  GAME[name]  = the src/shared/PixelIcon name each drawing is in the game (the icon it replaces)
"""
import math

from pixkit import Grid, ramp_from, RARITY, ELEMENT, PAL

MAIN = ["Cash", "Tokens", "Gems", "Food", "Eggs", "Shop", "Gift", "Packs", "Passes", "Boosts", "Pets", "Index", "Home",
        "Stats", "Settings", "Travel"]

NINE = {
    # a green bill with a darker one behind it, its centre seal
    "Cash": ("........./000000000/033333330/032202210/032040210/032202210/011111110/000000000/.........", "", {}, "g"),
    # the Cloud Token: a gold coin with a deep-gold rim, a cream cloud stamped in it
    "Tokens": ("..00000../.0333320./034222220/032231210/032231210/022231210/022222210/.0211110./..00000..", "", {}, "y"),
    # a cut gem: the light table, the shaded right pavilion
    "Gems": ("........./..00000../.0343320./033222210/.0222110./..02110../...010.../....0..../.........", "", {}, "b"),
    # a cream bowl heaped with berries (two red, a violet one between), a leaf on top: the cream bowl is what keeps the
    # berries apart from it at 18 px (the wooden bowl was a brown and red smudge there)
    "Food": ("....hh.../.rr.h.rr./rRrrvrRrr/rrrvVvrrr/.rrvvvrr./ccccccccc/.ccccccc./..ccccc../.........", "rvhc", {}),
    # an egg: wide at the bottom, sky spots
    "Eggs": ("...eee.../..eEeee../..eeeee../.eeee2ee./.eeeeeee./.e2eeeee./.eeee2ee./.eeeeeee./..eeeee..", "", {"e": ((104, 74, 46), (222, 196, 154), (250, 236, 206), (255, 250, 238), (255, 255, 255))}, "b"),
    # the shop stall: a roof-pink and cream striped awning, its scallops, a wooden counter
    "Shop": ("ppppppppp/pcpcpcpcp/pcpcpcpcp/p.p.p.p.p/.w.....w./.w.....w./lllllllll/lwwwwwwwl/lw.....wl", "wl", {}),
    # a red gift: the lid wider than the box, a gold ribbon and bow
    "Gift": ("..yy.yy../.y..y..y./qqqqyqqqq/qqqqyqqqq/.rrryrrr./.rrryrrr./.rrryrrr./.rrryrrr./.........", "rqy", {}),
    # a cardboard box, its flaps open, a gold star coming out
    "Packs": ("....y..../...yyy.../yyyyYyyyy/.yyyyyyy./..yy.yy../ttttttttt/tcccccccc/ttttttttt/ttttttttt", "yt", {}),
    # a violet ticket: notches, a dashed tear line, a gold star on the stub
    "Passes": ("........./........./vvvvvvvvv/vvvyvv-vv/.vyYyvvv./vvvyvv-vv/vvvvvvvvv/........./.........", "", {}),
    # a potion: cork, glass neck, pink brew with a bubble
    "Boosts": ("...www.../...kkk.../...kkk.../..kkkkk../.kKkkkkk./.ppppppp./.pPpppPp./.ppppppp./..ppppp..", "kp", {}),
    # a paw print: each 2 x 2 toe a lit bean (light, shadow, dark corner), not an all-outline chunk
    "Pets": ("..31.31../..10.10../31.....31/10.lll.10/..lllll../.lllLlll./.lllllll./..ll.ll../.........", "", {}, "w"),
    # a closed book: red cover, a gold plate, cream pages under it
    "Index": (".drrrrrr./.d32222r./.d22yy2r./.d22Yy2r./.d22222r./.d11111r./.dcccccc./.drrrrrr./.........", "", {}, "r"),
    # a house: red roof, cream walls, a wooden door, a sky window
    "Home": ("....r..../...rrr.../..rrrrr../.rrrrrrr./rrrrrrrrr/.ccccccc./.cbcwwcc./.cccwwcc./.cccwwcc.", "cr", {}),
    # a bar chart: sky, grass and violet bars on a wooden base
    "Stats": ("......vvv/......vvv/...gggvvv/...gggvvv/bbbgggvvv/bbbgggvvv/bbbgggvvv/wwwwwwwww/.........", "bgvw", {}),
    # an iron gear
    "Settings": ("...iii.../.i.iii.i./.iiiiiii./iii...iii/iii...iii/iii...iii/.iiiiiii./.i.iii.i./...iii...", "", {}),
    # a wooden signpost: an arrow board on a post
    "Travel": ("....w..../lllllll../llllllll./lllllllll/llllllll./lllllll../....w..../....w..../..hhwhh..", "whl", {}),
}

# the rarity dots: one orb, the colour from Config.Rarities; Legendary and up a 4-point spark on the orb, Secret a star
_ORB = "........./...xxx.../..xXxxx../.xXxxxxx./.xxxxxxx./.xxxxxxx./..xxxxx../...xxx.../........."
_ORB_SPARK = "........./...xxx.../..xxXxx../.xXXXxxx./.xxXxxxx./.xxxxxxx./..xxxxx../...xxx.../........."
_ORB_STAR = "........./...xxx.../..xxxxx../.xxx*xxx./.xx***xx./.xxx*xxx./..xxxxx../...xxx.../........."
RARITY_DOTS = {}
for _r, _c in RARITY.items():
    RARITY_DOTS[_r] = (_ORB_STAR if _r == "Secret" else (_ORB_SPARK if _r in ("Legendary", "Mythic") else _ORB), "", {"x": ramp_from(_c)})

# the element badges: the battle HUD's set, redrawn to read with an outline, in each element's own colour
ELEMENTS = {
    "Water": ("....x..../...xxx.../...xxx.../..xxxxx../.xXxxxxx./.xXxxxxx./.xxxxxxx./..xxxxx../.........", "", {}),
    # the three-tongue flame (spec 12_elements A / item 9: never a second drop), its hollow core gold
    "Flame": ("....x..../.x..xx.../.x..xx.x./.xx.xxxx./xxxxxxxxx/xxxxyxxxx/xxxyyyxxx/.xxyYyxx./..xxxxx..", "xy", {}),
    "Frost": ("....x..../.x.xxx.x./..xxxxx../.xxXxxxx./xxxxxxxxx/.xxxxxxx./..xxxxx../.x.xxx.x./....x....", "", {}),
    "Nature": (".....xxxx/...xxxxxx/..xxxXxxx/.xxxxxxxx/.xxxxxxx./.xxxxxx../..xxxx.../.h......./h........", "hx", {}),
    "Earth": ("...x...../..xxx..../..xxx.x../.xxXxxxx./.xxxxxxxx/xxxxxxxxx/xxxxxxxxx/xxxxxxxxx/.........", "", {}),
    "Storm": (".....xxx./....xxx../...xxx.../..xxxxxx./....xxx../...xxx.../..xxx..../.xx....../.........", "", {}),
    "Celestial": ("....x..../....x..../...xxx.../..xXxxx../xxxxxxxxx/..xxxxx../...xxx.../....x..../....x....", "", {}),
    "Shadow": ("...xxxx../..xxx..../.xxx...../.xXx...../.xxx...../.xxx...../.xxxx...x/..xxxxxx./...xxxx..", "", {}),
}
for _e in ELEMENTS:
    rows, z, extra = ELEMENTS[_e]
    extra = dict(extra)
    extra["x"] = ramp_from(ELEMENT[_e])
    ELEMENTS[_e] = (rows, z, extra)


# ------------------------------------------------------------------ direction B: the 18 x 18 art drawings
def emboss(g, shape_fn, f_hi=3, f_lo=1, only=None):
    """a raised stamp: the shape lit (tone f_hi), its offset (+1, +1) rim shaded (f_lo), on the cells already there"""
    inside = set()
    for y in range(g.h):
        for x in range(g.w):
            if shape_fn(x + 0.5, y + 0.5):
                inside.add((x, y))
    for (x, y) in inside:
        if only is None or g.get(x, y) in only:
            g.tone(x, y, f_hi)
    for (x, y) in inside:
        for (dx, dy) in ((1, 1), (1, 0), (0, 1)):
            p = (x + dx, y + dy)
            if p not in inside and (only is None or g.get(*p) in only):
                g.tone(p[0], p[1], f_lo)


def b_cash():
    # (P2 icons review r1, minor: the front bill's lit-side left column sat in the cell's first column and read as
    # clipped at the edge on cream) the pair of bills one cell in from the left (the back bill now ends in the last
    # column; its drop shadow takes the 19th)
    g = Grid(18)
    g.rect(4, 2, 17, 10, "h")                     # the back bill
    g.rect(2, 5, 15, 14, "g")                     # the front bill
    for x in range(4, 14):                        # its engraved inner frame
        g.tone(x, 7, 1)
        g.tone(x, 12, 1)
    for y in range(7, 13):
        g.tone(4, y, 1)
        g.tone(13, y, 1)
    g.circle(8.9, 9.9, 2.1, tone=0)              # the seal
    g.circle(8.9, 9.9, 1.1, tone=3)
    g.tone(3, 6, 4)
    g.tone(6, 9, 4)
    return g, "hg"


def b_tokens():
    g = Grid(18)
    g.circle(8.5, 8.5, 8.3, "y")
    for y in range(18):                           # the raised rim: lit top-left, shaded bottom-right
        for x in range(18):
            r = math.hypot(x + 0.5 - 8.5, y + 0.5 - 8.5)
            if 5.6 <= r < 7.5 and g.get(x, y) == "y":
                s_ = (x + 0.5 - 8.5) + (y + 0.5 - 8.5)
                g.tone(x, y, 3 if s_ < -2.5 else (1 if s_ > 2.5 else 2))
            elif 4.9 <= r < 5.6 and g.get(x, y) == "y":
                g.tone(x, y, 1)                   # the groove inside the rim
    cloud = lambda X, Y: ((X - 6.9) ** 2 + (Y - 9.3) ** 2 <= 1.8 ** 2) or ((X - 9.3) ** 2 + (Y - 8.0) ** 2 <= 2.2 ** 2) or ((X - 11.0) ** 2 + (Y - 9.7) ** 2 <= 1.4 ** 2) or (5.3 <= X <= 12.2 and 9.3 <= Y <= 11.0)
    emboss(g, cloud, 3, 1, only=("y",))
    g.tone(4, 4, 4)
    g.tone(5, 3, 4)
    g.tone(3, 5, 4)
    return g, ""


def b_gems():
    g = Grid(18)
    g.poly([(1, 6.5), (5, 1.5), (13, 1.5), (17, 6.5), (9, 16.6)], "b")
    g.poly([(5.5, 1.5), (12.5, 1.5), (13.5, 6.5), (4.5, 6.5)], tone=3)   # the table
    g.poly([(1, 6.5), (5.5, 1.5), (4.5, 6.5)], tone=2)
    g.poly([(9, 6.5), (17, 6.5), (9, 16.6)], tone=1)                     # the right pavilion
    g.line(4, 7, 8, 14, tone=2)
    for x in range(2, 16):
        if g.get(x, 6) == "b":
            g.tone(x, 6, 1)
    g.tone(6, 3, 4)
    g.tone(7, 3, 4)
    g.tone(6, 4, 4)
    return g, ""


def b_food():
    g = Grid(18)
    g.circle(9.0, 6.4, 3.0, "v")                 # the back berry
    g.circle(5.2, 8.4, 3.0, "r")
    g.circle(12.8, 8.4, 3.0, "r")
    g.poly([(9.5, 3.5), (12.5, 0.6), (15.4, 1.2), (13.0, 4.0)], "h")     # the leaf
    g.ellipse(8.5, 10.0, 8.4, 1.6, "c", f=3)     # the rim (lit)
    g.fill(lambda X, Y: Y >= 10.8 and ((X - 8.5) / 7.6) ** 2 + ((Y - 10.8) / 5.8) ** 2 <= 1.0, "c")   # the cream bowl
    g.rect(6, 16, 11, 16, "c")                   # its foot
    for (x, y) in ((4, 7), (12, 7), (8, 5)):
        g.tone(x, y, 4)
    for x in range(3, 15):                       # a painted sky band round the bowl
        if g.get(x, 13) == "c":
            g.put(x, 13, "b")
    return g, "vrhcb"


def b_eggs():
    g = Grid(18)

    def egg(X, Y):
        cy, ry = 9.3, 8.0
        t = (Y - cy) / ry
        if abs(t) > 1:
            return False
        hw = 6.6 * math.sqrt(1 - t * t) * (1 - 0.22 * max(0.0, -t))
        return abs(X - 8.5) <= hw
    g.fill(egg, "e")
    for (cx, cy, r) in ((11.2, 7.2, 1.5), (5.8, 10.6, 1.6), (10.0, 13.2, 1.3), (8.0, 4.2, 0.9)):
        g.circle(cx, cy, r, "b", only=("e",))
    g.tone(6, 4, 4)
    g.tone(5, 5, 4)
    g.tone(5, 6, 4)
    return g, ""


def b_shop():
    g = Grid(18)
    g.rect(0, 0, 17, 0, "w")                     # the roof beam
    for x in range(18):                          # the awning: 3-cell stripes, roof pink and cream
        m = "p" if (x // 3) % 2 == 0 else "c"
        for y in range(1, 6):
            g.put(x, y, m)
    for i in range(6):                           # a scallop under every stripe
        g.ellipse(i * 3 + 1.5, 6.0, 1.6, 1.4, "p" if i % 2 == 0 else "c")
    g.rect(2, 8, 3, 15, "w")                     # the posts
    g.rect(14, 8, 15, 15, "w")
    g.rect(0, 11, 17, 12, "l")                   # the counter top
    g.rect(1, 13, 16, 16, "w")                   # its front
    g.rect(6, 14, 11, 15, "c")                   # the price board on it
    g.put(9, 14, "y")
    g.put(10, 14, "y")
    g.put(9, 15, "y", 1)
    g.put(10, 15, "y", 1)
    return g, "wlcpy"


def b_gift():
    g = Grid(18)
    g.rect(2, 8, 15, 16, "r")
    g.rect(1, 5, 16, 8, "q")
    g.rect(8, 5, 9, 16, "y")
    g.ellipse(5.6, 2.8, 3.2, 2.3, "y")
    g.ellipse(11.4, 2.8, 3.2, 2.3, "y")
    g.ellipse(5.6, 3.0, 1.0, 0.8, erase=True)
    g.ellipse(11.4, 3.0, 1.0, 0.8, erase=True)
    g.rect(8, 3, 9, 5, "y", f=1)
    g.tone(3, 6, 4)
    return g, "rqy"


def b_packs():
    g = Grid(18)
    g.poly([(1.5, 9), (16.5, 9), (16.5, 17), (1.5, 17)], "t")           # the box
    g.poly([(1.5, 9), (-0.6, 5.2), (4.8, 4.6), (6.6, 9)], "t")          # the flaps
    g.poly([(16.5, 9), (18.6, 5.2), (13.2, 4.6), (11.4, 9)], "t")
    g.star(9.0, 6.6, 6.2, 2.7, "y")
    g.rect(2, 11, 15, 12, "c")                   # the tape
    g.tone(7, 4, 4)
    g.tone(8, 4, 4)
    return g, "ty"


def b_passes():
    g = Grid(18)
    g.rect(0, 4, 17, 13, "v")
    g.circle(0.0, 8.5, 2.0, erase=True)          # the notches
    g.circle(18.0, 8.5, 2.0, erase=True)
    for y in range(5, 13, 2):                    # the tear line
        g.tone(12, y, 0)
    g.star(6.2, 8.7, 4.3, 1.9, "y")
    g.rect(14, 7, 15, 7, "v", f=3)               # the stub's lines
    g.rect(14, 10, 15, 10, "v", f=3)
    g.tone(1, 5, 4)
    return g, "vy"


def b_boosts():
    g = Grid(18)
    g.rect(7, 0, 10, 2, "w")
    g.rect(7, 3, 10, 6, "k")
    g.circle(8.5, 11.4, 6.2, "k")
    g.fill(lambda X, Y: Y >= 10.0 and (X - 8.5) ** 2 + (Y - 11.4) ** 2 <= 5.2 ** 2, "p")
    g.rect(6, 2, 11, 3, "k")                     # the lip
    for (x, y) in ((10, 12), (6, 14), (11, 15)):
        g.tone(x, y, 4)
    for y in range(7, 13):                       # the glass's long highlight
        g.tone(4 if y > 8 else 5, y, 4)
    return g, "wkp"


def b_pets():
    g = Grid(18)
    g.ellipse(8.5, 12.4, 5.4, 4.3, "l")
    g.ellipse(8.5, 15.3, 3.4, 1.4, "l")
    for (cx, cy) in ((3.0, 7.4), (6.6, 3.6), (10.6, 3.6), (14.2, 7.4)):
        g.ellipse(cx, cy, 2.0, 2.5, "l")
    g.tone(6, 10, 4)
    for (cx, cy) in ((3.0, 7.4), (6.6, 3.6), (10.6, 3.6), (14.2, 7.4)):
        g.tone(int(cx - 1), int(cy - 1), 4)
    return g, ""


def b_index():
    g = Grid(18)
    g.rect(3, 0, 15, 13, "r")                    # the cover
    g.rect(2, 0, 4, 15, "d")                     # the spine
    g.rect(4, 14, 16, 15, "c")                   # the pages
    g.rect(3, 16, 15, 16, "r")                   # the back cover
    g.rect(7, 3, 12, 7, "y")                     # the plate
    g.rect(8, 4, 11, 6, "o", f=2)
    g.tone(9, 5, 4)
    g.rect(13, 14, 13, 17, "y")                  # the bookmark
    g.tone(5, 1, 4)
    for y in (2, 11):
        g.tone(3, y, 3)
    return g, "dcry"


def b_home():
    g = Grid(18)
    g.rect(2, 8, 15, 16, "c")
    g.rect(12, 1, 13, 5, "w")                    # the chimney
    g.poly([(-0.5, 9.0), (8.5, 0.2), (17.5, 9.0)], "r")
    g.rect(7, 11, 10, 16, "w")                   # the door
    g.tone(9, 13, 4)
    g.rect(3, 10, 5, 12, "b")
    g.rect(12, 10, 14, 12, "b")
    g.tone(3, 10, 4)
    g.tone(12, 10, 4)
    g.rect(0, 17, 17, 17, "h")                   # the grass line
    return g, "wcrbh"


def b_stats():
    g = Grid(18)
    g.rect(1, 10, 4, 15, "b")
    g.rect(7, 6, 10, 15, "g")
    g.rect(13, 2, 16, 15, "v")
    g.rect(0, 16, 17, 17, "w")
    for (x, y) in ((2, 11), (8, 7), (14, 3)):
        g.tone(x, y, 4)
    return g, "bgvw"


def b_settings():
    """an iron gear: 8 even teeth (4 on the axes, 4 on the diagonals), drawn about the grid's true centre (9.0, the
    middle of 18 cells) so every tooth rasterises the same; a hub groove round the hole"""
    g = Grid(18)
    c = 9.0

    def gear(X, Y):
        dx, dy = X - c, Y - c
        r = math.hypot(dx, dy)
        if r <= 6.3:
            return True
        if r > 8.7:
            return False
        for k in range(8):
            a = math.radians(k * 45)
            ux, uy = math.cos(a), math.sin(a)
            if dx * ux + dy * uy > 0 and abs(-dx * uy + dy * ux) <= 1.6:
                return True
        return False
    g.fill(gear, "i")
    g.circle(c, c, 2.4, erase=True)
    g.fill(lambda X, Y: 3.4 <= math.hypot(X - c, Y - c) <= 4.3, tone=1, only=("i",))
    g.tone(5, 4, 4)
    g.tone(4, 5, 4)
    return g, ""


def b_travel():
    g = Grid(18)
    g.rect(8, 1, 9, 16, "w")                     # the post
    g.poly([(1.5, 2.5), (13.5, 2.5), (17.0, 5.5), (13.5, 8.5), (1.5, 8.5)], "l")     # the right board
    g.poly([(16.0, 9.5), (4.5, 9.5), (1.0, 12.0), (4.5, 14.5), (16.0, 14.5)], "l")   # the left board
    for x in range(3, 13):
        g.tone(x, 5, 1)                          # the boards' plank lines
    for x in range(6, 15):
        g.tone(x, 12, 1)
    g.rect(6, 17, 11, 17, "h")
    g.put(7, 16, "h")
    g.put(10, 16, "h")
    g.tone(3, 3, 4)
    g.tone(15, 10, 4)
    return g, "whl"


B18 = {
    "Cash": b_cash, "Tokens": b_tokens, "Gems": b_gems, "Food": b_food, "Eggs": b_eggs, "Shop": b_shop, "Gift": b_gift,
    "Packs": b_packs, "Passes": b_passes, "Boosts": b_boosts, "Pets": b_pets, "Index": b_index, "Home": b_home,
    "Stats": b_stats, "Settings": b_settings, "Travel": b_travel,
}

def nine_grid(name, table=None):
    """the 9 x 9 drawing of `name` as (Grid, z, palette)"""
    from pixkit import pal_with
    e = (table or NINE)[name]
    rows, z, extra = e[0], e[1], e[2]
    main = e[3] if len(e) > 3 else None
    if main is None:
        main = next((ch for ch in rows if ch.islower()), "y")
    return Grid.parse(rows, main), z, pal_with(extra)


# the game's PixelIcon name of each drawing (shared/PixelIcon + Config.Icons). Travel was the plain "arrow" (a one-ink
# glyph other places use as an arrow): its signpost is a new name, "signpost", that Config.Icons.Travel names
GAME = {"Cash": "note", "Tokens": "token", "Gems": "gem", "Food": "pot", "Eggs": "egg", "Shop": "bag", "Gift": "gift",
        "Packs": "box", "Passes": "ticket", "Boosts": "potion", "Pets": "paw", "Index": "book", "Home": "house",
        "Stats": "stats", "Settings": "gear", "Travel": "signpost"}
for _r in RARITY:
    GAME[_r] = "rarity_" + _r.lower()
GAME.update({"Water": "drop", "Flame": "flame", "Frost": "flake", "Nature": "leaf", "Earth": "mountain", "Storm": "bolt",
             "Celestial": "sparkle", "Shadow": "moon"})  # Config.Elements.Info[*].Icon
