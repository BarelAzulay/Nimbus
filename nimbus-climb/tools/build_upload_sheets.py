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


def lua_block():
    """the PixelIcon generated block (between its BEGIN / END lines, those lines included)"""
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    lines = [
        "-- BEGIN GENERATED icons_b (tools/build_upload_sheets.py; do not edit by hand: change tools/pixelart/icons_b.py and",
        "-- run the script). Pitch 2 item 9 B \"Carved soft\": every redrawn icon's 9 x 9 glyph in its own colours, 10 x 10",
        "-- rows (the glyph + its 1-cell drop shadow on the right and bottom); one letter a colour of P (\"~\": the drop",
        "-- shadow, Text at 30 %), \".\" empty",
        "PixelIcon.Art = {",
    ]
    for name in drawing_names():
        cols = glyph_cols(name)
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
        lines.append("\t%s = { R = \"%s\", P = { %s } }, -- %s" % (I.GAME[name], "/".join(rows), ptxt, name))
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
        print("upload sheets and the PixelIcon block are up to date")


if __name__ == "__main__":
    main()
