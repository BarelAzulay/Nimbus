"""Pitch 2 items 9 B / 10 A: a render draws the upload sheets cell for cell, and can still show the fallback.

The icon sheet (build/upload_sheets/icons_b.png, Config.IconSheet.Id) and the machines sheet (machines_a.png,
Config.MachineSheet.Id) were uploaded on 2026-11-27 (I1 / I2): Config ships their ids (TextureIds icons_b /
machines_a), and tools/dump_gui.lua maps those shipped ids to the local sheet PNGs, so a plain render draws each sheet
ImageLabel's ImageRectOffset / ImageRectSize cut stretched with nearest-neighbour (ResampleMode Pixelated), the way Roblox
does. `render_gui.py --sheets` swaps in stub ids mapped to the same PNGs (a rebuilt sheet previews before it is uploaded
again); `render_gui.py --fallback` forces both ids to 0 for that render (the 9x9 glyphs, the drawn machine). This test
fails when:
  - a plain or --sheets dump has a machine Art ImageLabel without its rect, or a rect that is not its roulette's Config cell;
  - a plain dump does not map the shipped ids, or a --sheets dump the stub ids, to the two sheet PNGs;
  - the rendered machine is not the sheet's cell pixel for pixel (nearest-neighbour, whole px cells);
  - a --fallback dump (Id 0) maps any sheet or draws a sheet ImageLabel.
Run: py -3.12 tools/test_render_sheets.py (boots the Lua mock three times; a few seconds)."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import render_gui as RG  # noqa: E402
from PIL import Image  # noqa: E402

SHEETS = ["build/upload_sheets/icons_b.png", "build/upload_sheets/machines_a.png"]


def walk(nodes, out):
    for n in nodes or []:
        out.append(n)
        walk(n.get("children"), out)
    return out


def machine_arts(dump):
    out = {}
    for g in dump.get("guis", []):
        for n in walk(g.get("nodes"), []):
            p = str(n.get("path", ""))
            if n.get("name") == "Art" and n.get("class") == "ImageLabel" and ".Machine.Art" in p:
                rid = p.split(".Machine.Art")[0].rsplit("ShopCard_", 1)[-1].split(".")[0]
                out[rid] = n
    return out


def veils(dump):
    """roulette id -> (colour, opacity) of the card's Dim (the Secret hero away from the Storm Altar wears a navy veil)"""
    out = {}
    for g in dump.get("guis", []):
        for n in walk(g.get("nodes"), []):
            p = str(n.get("path", ""))
            if n.get("name") == "Dim" and "ShopCard_" in p and float(n.get("bgT", 1)) < 1:
                rid = p.rsplit("ShopCard_", 1)[-1].split(".")[0]
                out[rid] = (n.get("bg", [0, 0, 0]), 1.0 - float(n.get("bgT", 1)))
    return out


def shipped_ids():
    """TextureIds icons_b / machines_a, read from src/shared/TextureIds.lua (the ids Config ships)"""
    src = open(os.path.join(ROOT, "src", "shared", "TextureIds.lua"), encoding="utf-8").read()
    out = {}
    for key in ("icons_b", "machines_a"):
        m = re.search(r"\b%s\s*=\s*(\d+)" % key, src)
        out[key] = int(m.group(1)) if m else 0
    return out


def check_drawn(tag, dump, fonts, machines, cells, bad):
    """every machine Art of `dump` is its Config cell, drawn from machines_a.png cell for cell; -> the count drawn"""
    arts = machine_arts(dump)
    if sorted(arts) != sorted(cells):
        bad.append("%s: machine Art for %s (want %s)" % (tag, sorted(arts), sorted(cells)))
    local = dump.get("localImages") or {}
    img = RG.GuiRenderer(dump, fonts, ss=1, chrome=False, labels=False).render()
    veil = veils(dump)
    for rid, n in sorted(arts.items()):
        c = cells.get(rid)
        im = n.get("image") or {}
        rect = im.get("rect")
        if not c or rect != [c["x"], c["y"], c["w"], c["h"]]:
            bad.append("%s %s: rect %r, its cell %r" % (tag, rid, rect, c))
            continue
        if local.get(str(im.get("image", ""))) != SHEETS[1]:
            bad.append("%s %s: its image %r is not mapped to %s" % (tag, rid, im.get("image"), SHEETS[1]))
        if im.get("pixelated") is not True:
            bad.append("%s %s: not marked Pixelated" % (tag, rid))
        k = n["w"] / float(c["w"])
        if k != int(k) or abs(n["h"] - k * c["h"]) > 1e-6:
            bad.append("%s %s: %sx%s is not whole px cells of %dx%d" % (tag, rid, n["w"], n["h"], c["w"], c["h"]))
            continue
        k = int(k)
        # every opaque cell of the drawing lands as that colour in the middle of its k x k block
        miss = 0
        seen = 0
        for gy in range(0, c["h"], 3):
            for gx in range(0, c["w"], 3):
                src = machines.getpixel((c["x"] + gx, c["y"] + gy))
                if src[3] < 255:
                    continue
                seen += 1
                want = src[:3]
                if rid in veil:  # under the card's Dim: the sheet's colour through that veil
                    vc, va = veil[rid]
                    want = [src[i] * (1 - va) + vc[i] * va for i in range(3)]
                got = img.getpixel((int(n["x"] + gx * k + k // 2), int(n["y"] + gy * k + k // 2)))
                if max(abs(got[i] - want[i]) for i in range(3)) > 3:
                    miss += 1
        if seen == 0 or miss > 0:
            bad.append("%s %s: %d of %d sampled cells are not the sheet's colour" % (tag, rid, miss, seen))
    return len(arts)


def main():
    fonts = RG.FontBook()
    bad = []
    machines = Image.open(os.path.join(ROOT, "build", "upload_sheets", "machines_a.png")).convert("RGBA")
    cells = json.load(open(os.path.join(ROOT, "build", "upload_sheets", "machines_a.json"), encoding="utf-8"))["cells"]
    ids = shipped_ids()
    if not (ids["icons_b"] > 0 and ids["machines_a"] > 0):
        bad.append("TextureIds ships icons_b %r / machines_a %r (both uploaded: want ids > 0)" % (ids["icons_b"], ids["machines_a"]))

    # a plain render: the shipped ids, mapped to the local sheets and drawn cell for cell
    plain = RG.dump_scenario("shop", 1920, 1080, False, fonts)
    local = plain.get("localImages") or {}
    for key, png in (("icons_b", SHEETS[0]), ("machines_a", SHEETS[1])):
        uri = "rbxassetid://%d" % ids[key]
        if local.get(uri) != png:
            bad.append("plain: the shipped %s id %s maps to %r (want %s)" % (key, uri, local.get(uri), png))
    plainDrawn = check_drawn("plain", plain, fonts, machines, cells, bad)

    # --fallback (Id 0 forced): the drawn machines, no sheet mapped or cut
    fb = RG.dump_scenario("shop", 1920, 1080, False, fonts, fallback=True)
    if machine_arts(fb):
        bad.append("--fallback drew sheet machines (Config.MachineSheet.Id forced 0)")
    if any("upload_sheets" in str(v) for v in (fb.get("localImages") or {}).values()):
        bad.append("--fallback mapped an upload sheet")

    # --sheets: stub ids in place of the shipped ones, mapped to the same PNGs
    dump = RG.dump_scenario("shop", 1920, 1080, False, fonts, sheets=True)
    local = dump.get("localImages") or {}
    pngs = sorted(str(v) for v in local.values() if "upload_sheets" in str(v))
    if pngs != SHEETS:
        bad.append("--sheets maps the stub ids to %r" % pngs)
    sheetsDrawn = check_drawn("--sheets", dump, fonts, machines, cells, bad)
    if bad:
        print("FAIL test_render_sheets:")
        for b in bad:
            print("  - " + b)
        return 1
    print("ok test_render_sheets: %d machines (plain, shipped ids) and %d (--sheets) drawn from machines_a.png cell for cell;"
          " --fallback stays on the drawn machines" % (plainDrawn, sheetsDrawn))
    return 0


if __name__ == "__main__":
    sys.exit(main())
