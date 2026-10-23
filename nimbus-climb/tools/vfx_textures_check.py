#!/usr/bin/env python3
"""Checks the pet attack VFX flipbook sheets (blender/vfx/textures.json + blender/vfx/out/<key>.png).

    py -3.12 tools/vfx_textures_check.py            # every manifest key
    py -3.12 tools/vfx_textures_check.py --key fx_flame
    py -3.12 tools/vfx_textures_check.py --sheet    # + blender/vfx/out/contact_sheet.png (only when all pass)

Per key: the manifest entry is well formed (grid 4, size 1024, mode OneShot|Loop, fps, known elements, tint
runtime|baked), the key matches ^fx_[a-z]+$ and is unique, the PNG exists and is 1024x1024 RGBA, the four corner
pixels are fully transparent, every one of the 16 grid cells has at least 2% of its pixels with alpha > 32 (no empty
frames), and every fully transparent pixel has RGB (30, 38, 72) - never a gray / white checkerboard or fringe (the
Storm Altar lesson: Roblox shows the RGB of transparent pixels at mip edges).
Exit 0 and "N/N textures OK" when all pass.
"""
import json
import os
import re
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "blender", "vfx", "textures.json")
OUT = os.path.join(ROOT, "blender", "vfx", "out")

KEY_RE = re.compile(r"^fx_[a-z]+$")
ELEMENTS = {"Water", "Flame", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow"}
DARK_TINT = (30, 38, 72)
SIZE = 1024
GRID = 4
MIN_COVER = 0.02  # share of a cell's pixels with alpha > 32
EXPECTED_KEYS = [
    "fx_flame", "fx_embers", "fx_smoke", "fx_splash", "fx_droplets", "fx_ripple", "fx_iceshards", "fx_snow",
    "fx_frostmist", "fx_petals", "fx_leaves", "fx_thorn", "fx_rock", "fx_dust", "fx_crack", "fx_lightning",
    "fx_sparks", "fx_stormcloud", "fx_stars", "fx_rays", "fx_sparkle", "fx_wisps", "fx_voidring", "fx_darkglass",
    "fx_slash", "fx_shock", "fx_glow", "fx_streak", "fx_speedlines", "fx_hexshield",
]


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def check_entry(e):
    errs = []
    if not isinstance(e, dict):
        return ["entry is not an object"]
    key = e.get("key")
    if not isinstance(key, str) or not KEY_RE.match(key):
        errs.append("bad key %r (must match ^fx_[a-z]+$)" % (key,))
    if e.get("grid") != GRID:
        errs.append("%s: grid must be %d" % (key, GRID))
    if e.get("size") != SIZE:
        errs.append("%s: size must be %d" % (key, SIZE))
    if e.get("mode") not in ("OneShot", "Loop"):
        errs.append("%s: mode must be OneShot or Loop" % key)
    fps = e.get("fps")
    if not isinstance(fps, int) or isinstance(fps, bool) or fps <= 0:
        errs.append("%s: fps must be a positive int" % key)
    els = e.get("elements")
    if not isinstance(els, list) or not els or not all(x in ELEMENTS for x in els):
        errs.append("%s: elements must be a non-empty list of %s" % (key, sorted(ELEMENTS)))
    if e.get("tint") not in ("runtime", "baked"):
        errs.append("%s: tint must be runtime or baked" % key)
    return errs


def check_png(key):
    path = os.path.join(OUT, key + ".png")
    if not os.path.isfile(path):
        return ["missing %s" % rel(path)]
    with open(path, "rb") as f:
        im = Image.open(f)
        im.load()
    if im.size != (SIZE, SIZE):
        return ["%s: size %dx%d, want %dx%d" % (key, im.size[0], im.size[1], SIZE, SIZE)]
    if im.mode != "RGBA":
        return ["%s: mode %s, want RGBA" % (key, im.mode)]
    a = np.asarray(im)
    errs = []
    alpha = a[..., 3]
    for (y, x) in ((0, 0), (0, SIZE - 1), (SIZE - 1, 0), (SIZE - 1, SIZE - 1)):
        if alpha[y, x] != 0:
            errs.append("%s: corner (%d,%d) alpha %d, want 0" % (key, x, y, alpha[y, x]))
    cell = SIZE // GRID
    for i in range(GRID * GRID):
        r, c = divmod(i, GRID)
        sub = alpha[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell]
        cover = float((sub > 32).mean())
        if cover < MIN_COVER:
            errs.append("%s: frame %d (row %d col %d) cover %.2f%% < %.0f%%" % (key, i + 1, r, c, cover * 100, MIN_COVER * 100))
    clear = alpha == 0
    bad = clear & np.any(a[..., :3] != np.array(DARK_TINT, np.uint8), axis=-1)
    nbad = int(bad.sum())
    if nbad:
        ys, xs = np.nonzero(bad)
        errs.append("%s: %d transparent pixels are not RGB %s (first at %d,%d = %s)" % (
            key, nbad, DARK_TINT, xs[0], ys[0], tuple(int(v) for v in a[ys[0], xs[0], :3])))
    return errs


def write_sheet(entries, path):
    """every key: first and middle frame on the sky's dark blue and on grass green, with a label"""
    from PIL import ImageDraw
    th, gap, cols, label = 160, 4, 3, 20
    bgs = ((30, 38, 72), (86, 160, 70))
    bw = 4 * th + 3 * gap
    rows = (len(entries) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * bw + (cols + 1) * 16, rows * (th + label + 14) + 10), (14, 16, 24))
    draw = ImageDraw.Draw(sheet)
    cell = SIZE // GRID
    for n, e in enumerate(entries):
        with open(os.path.join(OUT, e["key"] + ".png"), "rb") as f:
            im = Image.open(f)
            im.load()
        im = im.convert("RGBA")
        x0 = 16 + (n % cols) * (bw + 16)
        y0 = 8 + (n // cols) * (th + label + 14)
        draw.text((x0, y0 + 3), "%s  %s %dfps  tint %s" % (e["key"], e["mode"], e["fps"], e["tint"]), fill=(230, 232, 240))
        k = 0
        for bg in bgs:
            for fr in (0, (GRID * GRID) // 2):
                r, c = divmod(fr, GRID)
                fr_im = im.crop((c * cell, r * cell, (c + 1) * cell, (r + 1) * cell))
                base = Image.new("RGBA", fr_im.size, bg + (255,))
                base.alpha_composite(fr_im)
                sheet.paste(base.convert("RGB").resize((th, th), Image.LANCZOS), (x0 + k * (th + gap), y0 + label))
                k += 1
    with open(path, "wb") as f:
        sheet.save(f, "PNG")
    print("wrote %s" % rel(path))


def main(argv):
    only = None
    if "--key" in argv:
        only = argv[argv.index("--key") + 1]
    if not os.path.isfile(MANIFEST):
        print("FAIL: missing %s" % rel(MANIFEST))
        return 1
    with open(MANIFEST, "rb") as f:
        man = json.loads(f.read().decode("utf-8"))
    entries = man.get("textures") if isinstance(man, dict) else None
    if not isinstance(entries, list):
        print("FAIL: %s needs a 'textures' list" % rel(MANIFEST))
        return 1
    errs = []
    keys = [e.get("key") if isinstance(e, dict) else None for e in entries]
    dup = sorted({k for k in keys if keys.count(k) > 1 and k is not None})
    if dup:
        errs.append("duplicate keys: %s" % ", ".join(dup))
    missing = [k for k in EXPECTED_KEYS if k not in keys]
    extra = [k for k in keys if k not in EXPECTED_KEYS]
    if missing:
        errs.append("manifest lacks keys: %s" % ", ".join(missing))
    if extra:
        errs.append("manifest has unexpected keys: %s" % ", ".join(str(k) for k in extra))
    ok = 0
    total = 0
    for e in entries:
        if only and isinstance(e, dict) and e.get("key") != only:
            continue
        total += 1
        ee = check_entry(e)
        if not ee:
            ee = check_png(e["key"])
        if ee:
            errs.extend(ee)
        else:
            ok += 1
    if errs:
        for m in errs:
            print("FAIL: " + m)
        print("%d/%d textures OK" % (ok, total))
        return 1
    print("%d/%d textures OK" % (ok, total))
    if "--sheet" in argv:
        write_sheet(entries, os.path.join(OUT, "contact_sheet.png"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
