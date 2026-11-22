"""Pixel art kit for the upload sheets (Pitch 2 items 9 B and 10 A; tools/build_upload_sheets.py).

Ported from the approved mock-up scripts (.superpowers/slop-audit/round3/build/PITCH2/C_icons_machines/pixkit.py), so the
game's icons and machines are the drawings the owner picked, cell for cell:
  - the real kit B tokens (src/shared/Theme.lua Theme.Sign) and the icon material ramps built from them
  - a cell grid (Grid) that the icons and machines are drawn into: material letters per cell, optional forced tones
  - the shading rules, applied by code so every icon follows the same light (top-left):
      A "Chunky stamp" (kept for the machines' shared helpers)
      B "Carved soft" (item 9's pick): a selective outline (dark on the shadow side, a mid shade on the lit side), 2
        tones (base + shadow band) with a 1-cell rim light inside the lit edge, + one hard 1-cell drop shadow (Text at 30%)

The output of the grid is plain data (one colour per cell): tools/build_upload_sheets.py bakes it into the PNG sheets and
into the 9 x 9 glyph data of src/shared/PixelIcon.lua (its generated block).
"""
import math

from PIL import Image, ImageDraw

S = {  # Theme.Sign (src/shared/Theme.lua 382-430)
    "Stone": (255, 247, 230), "StoneLip": (220, 201, 160), "Wood": (140, 90, 46), "Navy": (35, 42, 110),
    "Gold": (255, 210, 74), "Roof": (238, 111, 166), "Grass": (111, 207, 106), "Red": (238, 106, 127),
    "Text": (59, 36, 18), "TextMuted": (118, 84, 54), "RoofEdge": (122, 42, 82), "RoofLip": (196, 74, 130),
    "GoldLip": (201, 154, 30), "NavyLip": (23, 28, 79), "GrassLip": (63, 154, 69), "OnGrass": (22, 50, 26),
    "RedLip": (184, 54, 79), "Tile": (255, 253, 246), "Well": (243, 230, 200), "WellEdge": (201, 168, 119),
    "Post": (196, 138, 78), "Selected": (255, 233, 168), "PetWell": (235, 221, 185), "Sky": (108, 196, 245),
    "SkyLip": (58, 143, 203), "Violet": (169, 139, 234), "VioletLip": (115, 84, 196), "WoodLight": (181, 118, 60),
    "WoodDark": (94, 58, 27), "NavyLight": (46, 58, 122), "NavyTop": (59, 74, 154), "GoldLight": (255, 229, 138),
    "GoldDeep": (242, 169, 59), "Brass": (233, 180, 76), "Iron": (154, 163, 173), "IronDark": (93, 102, 112),
    "Canvas": (243, 230, 200), "CloudShade": (221, 230, 247), "CloudSide": (201, 214, 238), "Good": (46, 125, 50),
    "White": (255, 255, 255),
}

RARITY = {  # Config.Rarities
    "Common": (168, 178, 194), "Uncommon": (104, 196, 128), "Rare": (88, 158, 232), "Epic": (176, 108, 232),
    "Legendary": (242, 182, 68), "Mythic": (238, 98, 140), "Secret": (40, 40, 52),
}
ELEMENT = {  # Config.Elements.Info
    "Water": (64, 148, 236), "Flame": (240, 108, 56), "Frost": (150, 222, 248), "Nature": (104, 190, 86),
    "Earth": (178, 128, 80), "Storm": (110, 128, 255), "Celestial": (255, 212, 104), "Shadow": (128, 72, 178),
}
ROULETTE = {  # Config.Roulettes colours + the Secret's
    "Cloud": (120, 190, 235), "Storm": (128, 120, 214), "Sky": (240, 180, 90), "Celestial": (236, 120, 170),
    "Secret": (70, 90, 200),
}


def lerp(a, b, k):
    return tuple(int(round(x + (y - x) * k)) for x, y in zip(a, b))


def ramp_from(c, dark=(26, 16, 34)):
    """dark, shadow, base, light, spec from one colour (for rarity / element / roulette colours)"""
    return (lerp(c, dark, 0.62), lerp(c, dark, 0.28), c, lerp(c, (255, 255, 255), 0.42), lerp(c, (255, 255, 255), 0.86))


# the icon materials: (dark outline, shadow, base, light, spec) - kit tokens wherever the kit has the tone
PAL = {
    "y": ((112, 66, 14), S["GoldDeep"], S["Gold"], S["GoldLight"], (255, 252, 236)),  # gold: coins, stars, ribbon
    "o": ((112, 66, 14), (196, 124, 26), S["GoldDeep"], S["Gold"], (255, 246, 214)),  # deep gold: a coin's rim
    "g": ((24, 74, 38), S["GrassLip"], S["Grass"], (172, 234, 152), (240, 255, 236)),  # cash green
    "h": ((20, 62, 32), (44, 118, 54), (78, 168, 80), (128, 206, 116), (226, 255, 222)),  # leaf / back-bill green
    "b": ((24, 58, 126), S["SkyLip"], S["Sky"], (190, 234, 255), (255, 255, 255)),  # gem / sky blue
    "k": ((70, 108, 150), (156, 200, 228), (206, 233, 248), (236, 248, 255), (255, 255, 255)),  # glass
    "r": ((112, 24, 46), S["RedLip"], S["Red"], (250, 166, 178), (255, 242, 244)),  # red
    "q": ((112, 24, 46), (204, 70, 96), (246, 128, 146), (252, 182, 192), (255, 244, 246)),  # red, a lid's lighter red
    "d": ((80, 18, 34), (140, 36, 58), (186, 58, 84), (222, 110, 128), (250, 220, 226)),  # dark red (spines)
    "w": ((58, 34, 14), S["WoodDark"], S["Wood"], S["WoodLight"], (232, 184, 128)),  # wood
    "l": ((70, 40, 14), S["Wood"], S["WoodLight"], (214, 156, 92), (246, 214, 160)),  # light wood (planks, boards)
    "t": ((92, 58, 22), (178, 126, 66), (216, 166, 102), (240, 204, 146), (255, 242, 214)),  # cardboard
    "c": ((116, 86, 50), S["StoneLip"], S["Stone"], S["Tile"], (255, 255, 255)),  # cream / stone / shell / paper
    "v": ((56, 34, 118), S["VioletLip"], S["Violet"], (208, 190, 248), (250, 246, 255)),  # violet
    "p": (S["RoofEdge"], S["RoofLip"], S["Roof"], (248, 172, 208), (255, 240, 248)),  # roof pink
    "i": ((44, 50, 58), S["IronDark"], S["Iron"], (206, 213, 220), (255, 255, 255)),  # iron
    "n": ((12, 16, 50), S["NavyLip"], S["Navy"], S["NavyTop"], (132, 150, 230)),  # navy
    "s": ((12, 14, 40), (22, 24, 58), (34, 36, 80), (70, 72, 130), (190, 180, 255)),  # secret night
    "u": ((86, 52, 16), (170, 110, 30), S["Brass"], (248, 214, 130), (255, 246, 214)),  # brass
    "e": ((104, 74, 46), (222, 196, 154), (250, 236, 206), (255, 250, 238), (255, 255, 255)),  # egg shell
    "m": ((90, 40, 18), (168, 84, 36), (206, 118, 58), (236, 162, 104), (255, 226, 196)),  # copper
}
INK = S["Text"]
SPARK = (255, 255, 255)


def pal_with(extra):
    p = dict(PAL)
    p.update(extra)
    return p


class Grid:
    """a w x h grid of cells: mat[y][x] = a material letter (or "+" for ink) or None; force[y][x] = a forced tone 0-4"""

    def __init__(self, w, h=None):
        self.w, self.h = w, (h or w)
        self.mat = [[None] * self.w for _ in range(self.h)]
        self.force = [[None] * self.w for _ in range(self.h)]

    @staticmethod
    def parse(rows, main=None):
        rows = rows.split("/") if isinstance(rows, str) else rows
        g = Grid(max(len(r) for r in rows), len(rows))
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in ". ":
                    continue
                if ch == "+":
                    g.mat[y][x] = "+"
                elif ch == "*":
                    g.mat[y][x] = "*"
                elif ch == "-":
                    g.mat[y][x] = "?"
                    g.force[y][x] = 0
                elif ch.isdigit():
                    g.mat[y][x] = main
                    g.force[y][x] = int(ch)
                elif ch.isupper():
                    g.mat[y][x] = ch.lower()
                    g.force[y][x] = 4
                else:
                    g.mat[y][x] = ch
        g.resolve()
        return g

    def resolve(self):
        for y in range(self.h):
            for x in range(self.w):
                if self.mat[y][x] == "?":
                    counts = {}
                    for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)):
                        m = self.get(x + dx, y + dy)
                        if m and m not in "?+*":
                            counts[m] = counts.get(m, 0) + (2 if dx == 0 or dy == 0 else 1)
                    self.mat[y][x] = max(counts, key=counts.get) if counts else "c"

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.mat[y][x]
        return None

    def put(self, x, y, m, f=None):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.mat[y][x] = m
            self.force[y][x] = f

    def clear(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.mat[y][x] = None
            self.force[y][x] = None

    def tone(self, x, y, f):
        if self.get(x, y) is not None:
            self.force[y][x] = f

    # shapes: a cell is in when its centre (x + .5, y + .5) is
    def fill(self, test, m=None, f=None, only=None, erase=False, tone=None):
        for y in range(self.h):
            for x in range(self.w):
                if test(x + 0.5, y + 0.5):
                    if only is not None and self.mat[y][x] not in only:
                        continue
                    if erase:
                        self.clear(x, y)
                    elif tone is not None:
                        self.tone(x, y, tone)
                    else:
                        self.put(x, y, m, f)

    def rect(self, x0, y0, x1, y1, m=None, **kw):  # cells x0..x1, y0..y1 inclusive
        self.fill(lambda X, Y: x0 <= X - 0.5 <= x1 and y0 <= Y - 0.5 <= y1, m, **kw)

    def circle(self, cx, cy, r, m=None, **kw):
        self.fill(lambda X, Y: (X - cx) ** 2 + (Y - cy) ** 2 <= r * r, m, **kw)

    def ellipse(self, cx, cy, rx, ry, m=None, **kw):
        self.fill(lambda X, Y: ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2 <= 1.0, m, **kw)

    def poly(self, pts, m=None, **kw):
        def inside(X, Y):
            c = False
            n = len(pts)
            for i in range(n):
                x1, y1 = pts[i]
                x2, y2 = pts[(i + 1) % n]
                if (y1 > Y) != (y2 > Y):
                    xi = x1 + (Y - y1) * (x2 - x1) / (y2 - y1)
                    if X < xi:
                        c = not c
            return c
        self.fill(inside, m, **kw)

    def star(self, cx, cy, r_out, r_in, m=None, points=5, rot=-90, **kw):
        pts = []
        for i in range(points * 2):
            r = r_out if i % 2 == 0 else r_in
            a = math.radians(rot + i * 180 / points)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        self.poly(pts, m, **kw)

    def line(self, x0, y0, x1, y1, m=None, f=None, tone=None):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n):
            t = i / max(1, n - 1)
            x, y = int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t))
            if tone is not None:
                self.tone(x, y, tone)
            else:
                self.put(x, y, m, f)

    def stamp(self, rows, x0, y0, main=None):
        g = Grid.parse(rows, main)
        for y in range(g.h):
            for x in range(g.w):
                if g.mat[y][x] is not None:
                    self.put(x0 + x, y0 + y, g.mat[y][x], g.force[y][x])

    def ascii(self):
        rows = []
        for y in range(self.h):
            rows.append("".join(("." if m is None else (m if self.force[y][x] is None else (m.upper() if self.force[y][x] == 4 else str(self.force[y][x])))) for x, m in enumerate(self.mat[y])))
        return "/".join(rows)


def shade(g, style, pal=None, z="", lb=1, sb=1, drop=None):
    """the colour of every cell (None = empty) under rule A or B; drop = the drop shadow's RGBA (B) or None"""
    pal = pal or PAL
    W, H = g.w, g.h

    def filled(x, y):
        return 0 <= x < W and 0 <= y < H and g.mat[y][x] is not None

    def blocked(x, y, nx, ny):
        if not filled(nx, ny):
            return True
        m, n = g.mat[y][x], g.mat[ny][nx]
        if m in "+*" or n in "+*":
            return False
        return m != n and m in z and n in z and z.index(n) > z.index(m)

    info = {}
    for y in range(H):
        for x in range(W):
            if filled(x, y):
                bu, bd, bl, br = blocked(x, y, x, y - 1), blocked(x, y, x, y + 1), blocked(x, y, x - 1, y), blocked(x, y, x + 1, y)
                info[(x, y)] = (bu, bd, bl, br, bu or bd or bl or br)

    def dist(x, y, dx, dy):
        k = 0
        cx, cy = x, y
        while True:
            cx, cy = cx + dx, cy + dy
            k += 1
            if not filled(cx, cy) or info[(cx, cy)][4] or blocked(cx - dx, cy - dy, cx, cy):
                return k
            if k > 40:
                return k

    out = [[None] * (W + 1) for _ in range(H + 1)]
    for (x, y), (bu, bd, bl, br, edge) in info.items():
        m = g.mat[y][x]
        if m == "+":
            out[y][x] = INK
            continue
        if m == "*":
            out[y][x] = SPARK
            continue
        rp = pal[m]
        f = g.force[y][x]
        if f is not None and not (f == 0 and edge and style == "B"):
            out[y][x] = rp[f]
            continue
        if edge:
            if style == "A":
                out[y][x] = rp[0]
            else:
                nx = (1 if br else 0) - (1 if bl else 0)
                ny = (1 if bd else 0) - (1 if bu else 0)
                dot = -(nx + ny)
                out[y][x] = rp[1] if dot > 0 else (rp[0] if dot < 0 else lerp(rp[0], rp[1], 0.45))
            continue
        du, dl, dd, dr = dist(x, y, 0, -1), dist(x, y, -1, 0), dist(x, y, 0, 1), dist(x, y, 1, 0)
        lit_d, shd_d = min(du, dl), min(dd, dr)
        if style == "A":
            lit, shd = lit_d <= lb, shd_d <= sb
            if lit and shd:
                out[y][x] = rp[3] if lit_d < shd_d else (rp[1] if shd_d < lit_d else rp[2])
            elif lit:
                out[y][x] = rp[3]
            elif shd:
                out[y][x] = rp[1]
            else:
                out[y][x] = rp[2]
        else:
            # the rim: the first cell inside a lit (up / left facing) edge
            rim = False
            if du == 1 and filled(x, y - 1) and info[(x, y - 1)][4]:
                rim = True
            if dl == 1 and filled(x - 1, y) and info[(x - 1, y)][4]:
                rim = True
            if shd_d <= sb:
                out[y][x] = rp[1]
            elif rim:
                out[y][x] = rp[3]
            else:
                out[y][x] = rp[2]
    if drop:
        for y in range(H + 1):
            for x in range(W + 1):
                if out[y][x] is None and (x - 1 >= 0 and y - 1 >= 0 and filled(x - 1, y - 1)) and not filled(x, y):
                    out[y][x] = drop
    return out


def cells_image(cols, cell, w=None, h=None):
    """the shaded cells as an RGBA image, cell px a cell; w x h cells (default: all, drop shadow row included)"""
    H = h or len(cols)
    W = w or len(cols[0])
    im = Image.new("RGBA", (W * cell, H * cell), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for y in range(H):
        for x in range(W):
            c = cols[y][x]
            if c is not None:
                d.rectangle([x * cell, y * cell, (x + 1) * cell - 1, (y + 1) * cell - 1], fill=c if len(c) == 4 else c + (255,))
    return im


def count_runs(cols):
    """the game's Frame count for an icon drawn by Frames: PixelIcon's merged runs, per colour"""
    n = 0
    H = len(cols)
    for colour in set(c for row in cols for c in row if c is not None):
        open_ = {}
        for y in range(H):
            row = cols[y]
            nxt = {}
            x = 0
            while x < len(row):
                if row[x] == colour:
                    s = x
                    while x < len(row) and row[x] == colour:
                        x += 1
                    key = (s, x - s)
                    if key not in open_:
                        n += 1
                    nxt[key] = True
                else:
                    x += 1
            open_ = nxt
    return n

