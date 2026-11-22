"""Builds the Pitch 2 upload sheets and the icon data the game draws until they are uploaded.

    py -3.12 tools/build_upload_sheets.py            # everything: the sheets + the PixelIcon block
    py -3.12 tools/build_upload_sheets.py --check    # exit 1 when a sheet or the PixelIcon block is out of date

Item 9 B ("Carved soft", spec docs/superpowers/specs/2026-11-20-pitch2-build-design.md):
  build/upload_sheets/icons_b.png + icons_b.json
      the 16 art-size icons (18 x 18 cells + the 1-cell drop shadow = 19 x 19) at 1 px a cell, in 20 px cells, 8 a row;
      the same icons greyed (the disabled state) in the rows under them. The game draws one with an ImageLabel cut by
      ImageRectOffset / ImageRectSize, ResampleMode Pixelated (shared/PixelIcon, once Config.IconSheet.Id is set).
  src/shared/PixelIcon.lua, the block between "BEGIN GENERATED icons_b" and "END GENERATED icons_b"
      PixelIcon.Art: the 9 x 9 glyphs (+ their drop shadow row and column: 10 x 10) in their own colours, every one of
      the 31 (the 16 + 7 rarity dots + 8 element badges); PixelIcon.SheetCells: each icon's cell in icons_b.png.

Item 10 A ("Workshop machines"):
  build/upload_sheets/machines_a.png + machines_a.json
      the five roulette machines (52 x 60 cells, the Secret 60 x 68, each + its 1-cell drop shadow) at 1 px a cell in one
      row; under them the odds chips' eggs (9 x 9 + the drop shadow, one a rarity) in a row; the game cuts one with
      ImageRectOffset / ImageRectSize, ResampleMode Pixelated (client/UI/ShopEggs, once Config.MachineSheet.Id is set)
  src/shared/Config.lua, Config.MachineSheet.Cells / Eggs: each roulette's and each rarity egg's cell (written here, so
      the game and the sheet agree); the eggs' PixelIcon glyphs ("egg_<rarity>") go in the PixelIcon block above

Nothing is uploaded here: the sheets are handed to the owner's keyed cloud session (tools/upload_assets.py runs there).
The drawings are tools/pixelart/ (ported from the approved mock-up scripts).
"""
import argparse
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "pixelart"))

from PIL import Image  # noqa: E402

import pixkit as K  # noqa: E402
import icons_b as I  # noqa: E402

OUT = os.path.join(ROOT, "build", "upload_sheets")
PIXELICON = os.path.join(ROOT, "src", "shared", "PixelIcon.lua")

DROP = K.S["Text"] + (77,)  # the B drop shadow: Text at 30 %
GREY_TO = K.S["Well"]  # a greyed icon: its luminance, a third of the way to the Well cream
ICON_CELL = 20  # a sheet cell (19 x 19 art + a clear 1 px gutter)
ICON_ART = 19
ICON_COLS = 8


def grey(c):
    """the disabled twin of a colour (PixelIcon.Grey uses the same rule on the 9 x 9 glyphs)"""
    r, g, b = c[0], c[1], c[2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    out = tuple(int(round(lum + (t - lum) * 0.35)) for t in GREY_TO)
    return out + tuple(c[3:])


# ------------------------------------------------------------------ item 9: the glyphs and the art
def glyph_table(name):
    if name in I.NINE:
        return I.NINE
    if name in I.RARITY_DOTS:
        return I.RARITY_DOTS
    return I.ELEMENTS


def glyph_cols(name):
    """the 9 x 9 B glyph of `name` (a drawing name: Cash, Common, Flame...) shaded, 10 x 10 with its drop shadow"""
    g, z, pal = I.nine_grid(name, glyph_table(name))
    return K.shade(g, "B", pal, z=z, drop=DROP)


def art_cols(name):
    """the 18 x 18 B art of `name` shaded, 19 x 19 with its drop shadow"""
    g, z = I.B18[name]()
    return K.shade(g, "B", K.PAL, z=z, lb=1, sb=2, drop=DROP)


def drawing_names():
    return list(I.NINE) + list(I.RARITY_DOTS) + list(I.ELEMENTS)


# (P2 icons review r1, major 1) item 10's odds chip eggs (tools/pixelart/machines_a.py odds_egg): one 9 x 9 egg a rarity,
# shaded B with the icons' drop shadow. They ship in the machines sheet's egg row and, for a sheet without that row, as
# PixelIcon glyphs "egg_<rarity>" (the same drawing in Frames)
def odds_eggs():
    """[(rarity, the PixelIcon name)] in the sheet's order"""
    import machines_a as M
    return [(r, "egg_" + r.lower()) for r in M.ODDS_EGG_ORDER]


def egg_cols(rarity):
    """the odds chip egg of `rarity` shaded, 10 x 10 with its drop shadow"""
    import machines_a as M
    g, z, pal = M.odds_egg(rarity)
    return K.shade(g, "B", pal, z=z, drop=DROP)


def icons_sheet():
    """the icons_b.png image and its manifest"""
    names = list(I.B18)
    rows = (len(names) + ICON_COLS - 1) // ICON_COLS
    w, h = ICON_COLS * ICON_CELL, 2 * rows * ICON_CELL
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cells = {}
    for i, name in enumerate(names):
        cols = art_cols(name)
        x, y = (i % ICON_COLS) * ICON_CELL, (i // ICON_COLS) * ICON_CELL
        for gy, row in enumerate(cols[:ICON_ART]):
            for gx, c in enumerate(row[:ICON_ART]):
                if c is None:
                    continue
                rgba = c if len(c) == 4 else c + (255,)
                im.putpixel((x + gx, y + gy), rgba)
                im.putpixel((x + gx, y + gy + rows * ICON_CELL), grey(rgba))
        cells[I.GAME[name]] = {"drawing": name, "x": x, "y": y, "w": ICON_ART, "h": ICON_ART}
    manifest = {
        "sheet": "icons_b.png",
        "item": "Pitch 2 item 9 B (Carved soft): the art-size icons (54 px on PC, 36 on a phone)",
        "size": [w, h],
        "cell": ICON_CELL,
        "art": [ICON_ART, ICON_ART],
        "art_note": "18 x 18 cells at 1 px a cell + the 1-cell drop shadow (Text at 30 %) on the right and bottom",
        "grey_offset": [0, rows * ICON_CELL],
        "grey_note": "the greyed (disabled) twin of each icon sits grey_offset below it",
        "cells": cells,
        "config_key": "Config.IconSheet.Id",
        "upload": "ONE Image asset (not a Decal id), from the owner's keyed cloud session; then set Config.IconSheet.Id to its "
                  "image id. Until then (Id = 0) every icon draws its 9 x 9 glyph (shared/PixelIcon).",
        "draw": "ImageLabel, Image rbxassetid://<id>, ImageRectOffset (x, y), ImageRectSize (19, 19), ResampleMode Pixelated, "
                "19 cells x (icon px / 18) design px",
    }
    return im, manifest


def hexc(c):
    return "%02X%02X%02X" % (c[0], c[1], c[2])


# (P2 icons review r1, major 6: the own-colour glyphs cost 23 - 51 Frames, past the spec's cap of 40 for a code-only
# multi-colour icon) a glyph is drawn as LAYERS, painter's order: the drop shadow first (its rects never overlap each
# other, so the 30 % never doubles; they may run under the glyph, which hides them), then one colour at a time, each
# colour's rects allowed over the cells of the colours drawn after it (they paint over them). The same picture, 704
# Frames for the 31 in place of 951, at most 35 an icon
def _cover(todo, allowed, H, W, overlap):
    """rects (x, y, w, h) inside `allowed` covering every cell of `todo` (cells are (y, x)); greedy: the rect that covers
    the most cells still to do, the smaller one on a tie; overlap False: no two rects share a cell"""
    todo, out, used = set(todo), [], set()
    while todo:
        best = None
        for y0 in range(H):
            for x0 in range(W):
                if (y0, x0) not in allowed or (not overlap and (y0, x0) in used):
                    continue
                maxx = W
                for y1 in range(y0, H):
                    w = 0
                    while x0 + w < maxx and (y1, x0 + w) in allowed and (overlap or (y1, x0 + w) not in used):
                        w += 1
                    if w == 0:
                        break
                    maxx = x0 + w
                    for x1 in range(x0 + 1, maxx + 1):
                        gain = sum(1 for yy in range(y0, y1 + 1) for xx in range(x0, x1) if (yy, xx) in todo)
                        key = (gain, -(x1 - x0) * (y1 - y0 + 1), -y0, -x0)
                        if gain and (best is None or key > best[0]):
                            best = (key, x0, y0, x1 - x0, y1 - y0 + 1)
        _, x, y, w, h = best
        out.append((x, y, w, h))
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                todo.discard((yy, xx))
                used.add((yy, xx))
    return out


def layer_rects(rows):
    """the draw list of a glyph's letter rows ("~" the drop shadow, "." empty): [(x, y, w, h, letter)] bottom first. The
    colour order is the fewest rects of a greedy bottom-up pick and 40 seeded shuffles (deterministic)"""
    import random
    H, W = len(rows), max(len(r) for r in rows)
    at = {(y, x): c for y, row in enumerate(rows) for x, c in enumerate(row) if c != "."}
    out = [r + ("~",) for r in _cover([p for p, v in at.items() if v == "~"], set(at), H, W, False)]
    cols = sorted(set(v for v in at.values() if v != "~"))

    def by_order(order):
        rects = []
        for i, c in enumerate(order):
            later = set(order[i:])
            allowed = {p for p, v in at.items() if v in later}
            rects += [r + (c,) for r in _cover([p for p, v in at.items() if v == c], allowed, H, W, True)]
        return rects

    rem, greedy = list(cols), []
    while rem:
        allowed = {p for p, v in at.items() if v in rem}
        pick = min(rem, key=lambda c: (len(_cover([p for p, v in at.items() if v == c], allowed, H, W, True)), c))
        greedy.append(pick)
        rem.remove(pick)
    best = by_order(greedy)
    rnd = random.Random(7)
    for _ in range(40):
        o = cols[:]
        rnd.shuffle(o)
        rr = by_order(o)
        if len(rr) < len(best):
            best = rr
    return out + best


def b36(n):
    return "0123456789abcdefghijklmnopqrstuvwxyz"[n]


def lua_block():
    """the PixelIcon generated block (between its BEGIN / END lines, those lines included)"""
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    lines = [
        "-- BEGIN GENERATED icons_b (tools/build_upload_sheets.py; do not edit by hand: change tools/pixelart/icons_b.py and",
        "-- run the script). Pitch 2 item 9 B \"Carved soft\": every redrawn icon's 9 x 9 glyph in its own colours, 10 x 10",
        "-- rows (the glyph + its 1-cell drop shadow on the right and bottom); one letter a colour of P (\"~\": the drop",
        "-- shadow, Text at 30 %), \".\" empty. L: the Frames that draw it, bottom first, 5 characters each: x, y, w, h",
        "-- (base 36, in cells) and the letter; the shadow first, then each colour over the ones drawn after it",
        "PixelIcon.Art = {",
    ]
    glyphs = [(I.GAME[name], glyph_cols(name), name) for name in drawing_names()]
    glyphs += [(game, egg_cols(r), "odds egg " + r) for r, game in odds_eggs()]
    for game, cols, label in glyphs:
        pal, rows = {}, []
        for row in cols:
            s = ""
            for c in row:
                if c is None:
                    s += "."
                elif len(c) == 4:
                    s += "~"
                else:
                    key = hexc(c)
                    if key not in pal:
                        pal[key] = letters[len(pal)]
                    s += pal[key]
            rows.append(s)
        ptxt = ", ".join("%s = \"%s\"" % (v, k) for k, v in pal.items())
        ltxt = "".join(b36(x) + b36(y) + b36(w) + b36(h) + c for x, y, w, h, c in layer_rects(rows))
        lines.append("\t%s = { R = \"%s\", P = { %s }, L = \"%s\" }, -- %s" % (game, "/".join(rows), ptxt, ltxt, label))
    lines.append("}")
    # the mono twins of the new names (a caller that asks for one ink colour, NeonKit.IconName, the Bitmaps walks)
    for name in drawing_names():
        game = I.GAME[name]
        if game == "signpost" or game.startswith("rarity_"):
            g, _, _ = I.nine_grid(name, glyph_table(name))
            mono = "/".join("".join("#" if g.mat[y][x] is not None else "." for x in range(9)) for y in range(9))
            lines.append("PixelIcon.Bitmaps.%s = \"%s\" -- %s, one ink" % (game, mono, name))
    _, man = icons_sheet()
    lines.append("-- each art-size icon's 19 x 19 cell in build/upload_sheets/icons_b.png (x, y); GreyY: the greyed twins' offset")
    cells = ", ".join("%s = { %d, %d }" % (k, v["x"], v["y"]) for k, v in man["cells"].items())
    lines.append("PixelIcon.SheetCells = { Art = %d, GreyY = %d, %s }" % (ICON_ART, man["grey_offset"][1], cells))
    lines.append("-- END GENERATED icons_b")
    return "\n".join(lines) + "\n"


BLOCK_RE = re.compile(r"-- BEGIN GENERATED icons_b.*?-- END GENERATED icons_b\n", re.S)


# ------------------------------------------------------------------ item 10 A: the roulette machines
MACHINE_ORDER = ["Cloud", "Storm", "Sky", "Celestial", "Secret"]
MACHINE_DROP = K.S["Text"] + (70,)  # the mock-up's machine drop shadow (make_item10.py DROP)


def machine_cols(name):
    """the A drawing of roulette `name` shaded by the icon pick's rule (B), with its 1-cell drop shadow"""
    import machines_a as M
    g, z = M.A[name]()
    return K.shade(g, "B", M.MPAL, z=z, lb=1, sb=2, drop=MACHINE_DROP)


def machines_sheet():
    """the machines_a.png image and its manifest: the five drawings at 1 px a cell in one row, 1 px apart; under them,
    1 px clear, the odds chip eggs (10 x 10 each: 9 x 9 + the drop shadow) in one row, 1 px apart"""
    cols = {n: machine_cols(n) for n in MACHINE_ORDER}
    eggs = [(r, egg_cols(r)) for r, _ in odds_eggs()]
    mh = max(len(cols[n]) for n in MACHINE_ORDER)
    ew = sum(len(c[0]) for _, c in eggs) + len(eggs) - 1
    w = max(sum(len(cols[n][0]) for n in MACHINE_ORDER) + len(MACHINE_ORDER) - 1, ew)
    h = mh + 1 + max(len(c) for _, c in eggs)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    def paint(c, x0, y0):
        for gy, row in enumerate(c):
            for gx, px in enumerate(row):
                if px is not None:
                    im.putpixel((x0 + gx, y0 + gy), px if len(px) == 4 else px + (255,))

    cells, x = {}, 0
    for n in MACHINE_ORDER:
        c = cols[n]
        cw, ch = len(c[0]), len(c)
        paint(c, x, 0)
        cells[n] = {"x": x, "y": 0, "w": cw, "h": ch, "cells": [cw - 1, ch - 1]}
        x += cw + 1
    egg_cells, x = {}, 0
    for r, c in eggs:
        cw, ch = len(c[0]), len(c)
        paint(c, x, mh + 1)
        egg_cells[r] = {"x": x, "y": mh + 1, "w": cw, "h": ch, "cells": [cw - 1, ch - 1]}
        x += cw + 1
    manifest = {
        "sheet": "machines_a.png",
        "item": "Pitch 2 item 10 A (Workshop machines): one pixel capsule machine per roulette, and the odds chips' eggs",
        "size": [w, h],
        "cells": cells,
        "eggs": egg_cells,
        "egg_note": "the odds chip egg of each rarity (Config.MachineSheet.Eggs): 9 x 9 cells + its 1-cell drop shadow (Text at "
                    "30 %); 3 px a cell on PC (27 px), 2 on a phone (18). Without its cell the game draws PixelIcon "
                    "\"egg_<rarity>\", the same drawing in Frames",
        "cell_note": "w x h = the drawing (52 x 60, the Secret 60 x 68) + its 1-cell drop shadow on the right and bottom",
        "config_key": "Config.MachineSheet.Id",
        "upload": "ONE Image asset (not a Decal id), from the owner's keyed cloud session; then set Config.MachineSheet.Id to "
                  "its image id. Until then (Id = 0) every roulette keeps today's drawn machine (ShopEggs H.machine).",
        "draw": "ImageLabel, Image rbxassetid://<id>, ImageRectOffset (x, y), ImageRectSize (w, h), ResampleMode Pixelated, "
                "a whole number of screen px a cell (3 on PC for the hero's vault, 2 in a PC card, 2 or 1 on a phone)",
    }
    return im, manifest


CONFIG = os.path.join(ROOT, "src", "shared", "Config.lua")
# the table's body after its Id line (Cells, then Eggs), up to its closing brace at the line's start
CELLS_RE = re.compile(r"(Config\.MachineSheet = \{\n\tId = \d+,\n)(.*?)(\n\}\n)", re.S)


def png_bytes(im):
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def write_or_check(path, data, check, stale):
    old = None
    if os.path.isfile(path):
        with open(path, "rb") as fh:
            old = fh.read()
    if old == data:
        return
    if check:
        stale.append(os.path.relpath(path, ROOT))
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)
    print("wrote", os.path.relpath(path, ROOT))


def same_png(path, im):
    """a PNG on disk with the same pixels as im (PNG bytes differ between PIL versions; the pixels are what count)"""
    if not os.path.isfile(path):
        return False
    try:
        old = Image.open(path).convert("RGBA")
    except Exception:
        return False
    return old.size == im.size and old.tobytes() == im.convert("RGBA").tobytes()


def build(check):
    stale = []
    im, man = icons_sheet()
    png = os.path.join(OUT, "icons_b.png")
    if not same_png(png, im):
        if check:
            stale.append(os.path.relpath(png, ROOT))
        else:
            write_or_check(png, png_bytes(im), False, stale)
    write_text(os.path.join(OUT, "icons_b.json"), json.dumps(man, indent=2) + "\n", check, stale)
    with open(PIXELICON, "rb") as fh:
        src = fh.read().decode("utf-8").replace("\r\n", "\n")
    block = lua_block()
    if BLOCK_RE.search(src):
        new = BLOCK_RE.sub(lambda m: block, src, count=1)
    else:
        marker = "-- tick is the pitch's check"
        if marker not in src:
            raise SystemExit("PixelIcon.lua: no generated block and no '%s' line to put it before" % marker)
        new = src.replace(marker, block + marker, 1)
    write_text(PIXELICON, new, check, stale)
    # item 10 A: the machines sheet, its manifest, and the cells Config.MachineSheet gives the game
    im, man = machines_sheet()
    png = os.path.join(OUT, "machines_a.png")
    if not same_png(png, im):
        if check:
            stale.append(os.path.relpath(png, ROOT))
        else:
            write_or_check(png, png_bytes(im), False, stale)
    write_text(os.path.join(OUT, "machines_a.json"), json.dumps(man, indent=2) + "\n", check, stale)
    with open(CONFIG, "rb") as fh:
        cfg = fh.read().decode("utf-8").replace("\r\n", "\n")
    def rects(table):
        return "".join("\n\t\t%s = { %d, %d, %d, %d }," % (n, c["x"], c["y"], c["w"], c["h"]) for n, c in table.items())
    body = "\tCells = {" + rects(man["cells"]) + "\n\t},\n\tEggs = {" + rects(man["eggs"]) + "\n\t},"
    if not CELLS_RE.search(cfg):
        raise SystemExit("Config.lua: no Config.MachineSheet = { Id = ..., ... } table")
    write_text(CONFIG, CELLS_RE.sub(lambda m: m.group(1) + body + m.group(3), cfg, count=1), check, stale)
    return stale


def write_text(path, text, check, stale):
    """a text file compared and written with the line endings it has on disk (a Windows checkout's CRLF stays CRLF)"""
    crlf = False
    if os.path.isfile(path):
        with open(path, "rb") as fh:
            crlf = b"\r\n" in fh.read()
    write_or_check(path, (text.replace("\n", "\r\n") if crlf else text).encode("utf-8"), check, stale)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="exit 1 when a sheet or the PixelIcon block is out of date")
    args = ap.parse_args()
    stale = build(args.check)
    if args.check:
        if stale:
            print("out of date:", ", ".join(stale))
            sys.exit(1)
        print("the upload sheets, the PixelIcon block and Config.MachineSheet.Cells are up to date")


if __name__ == "__main__":
    main()
