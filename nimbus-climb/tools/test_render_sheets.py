"""Pitch 2 items 9 B / 10 A: a render can preview the upload sheets before they are uploaded.

The icon sheet (build/upload_sheets/icons_b.png, Config.IconSheet.Id) and the machines sheet (machines_a.png,
Config.MachineSheet.Id) ship with Id 0, so a plain render draws the fallback (the 9x9 glyphs, today's machine).
`render_gui.py --sheets` gives both a stub id for that render only, maps the stub ids to the local sheet PNGs, and draws
each sheet ImageLabel's ImageRectOffset / ImageRectSize cut stretched with nearest-neighbour (ResampleMode Pixelated),
the way Roblox will once the owner uploads them. This test fails when:
  - a --sheets dump has a machine Art ImageLabel without its rect, or a rect that is not its roulette's Config cell;
  - the stub ids are not mapped to the two sheet PNGs;
  - the rendered machine is not the sheet's cell pixel for pixel (nearest-neighbour, whole px cells);
  - a plain dump (no --sheets) maps any sheet or draws a sheet ImageLabel (Config stays at 0).
Run: py -3.12 tools/test_render_sheets.py (boots the Lua mock twice; a few seconds)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import render_gui as RG  # noqa: E402
from PIL import Image  # noqa: E402


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


def main():
    fonts = RG.FontBook()
    bad = []
    machines = Image.open(os.path.join(ROOT, "build", "upload_sheets", "machines_a.png")).convert("RGBA")
    import json
    cells = json.load(open(os.path.join(ROOT, "build", "upload_sheets", "machines_a.json"), encoding="utf-8"))["cells"]

    plain = RG.dump_scenario("shop", 1920, 1080, False, fonts)
    if machine_arts(plain):
        bad.append("a plain render drew sheet machines (Config.MachineSheet.Id must ship 0)")
    if any("upload_sheets" in str(v) for v in (plain.get("localImages") or {}).values()):
        bad.append("a plain render mapped an upload sheet")

    dump = RG.dump_scenario("shop", 1920, 1080, False, fonts, sheets=True)
    local = dump.get("localImages") or {}
    pngs = sorted(str(v) for v in local.values() if "upload_sheets" in str(v))
    if pngs != ["build/upload_sheets/icons_b.png", "build/upload_sheets/machines_a.png"]:
        bad.append("--sheets maps the stub ids to %r" % pngs)
    arts = machine_arts(dump)
    if sorted(arts) != sorted(cells):
        bad.append("--sheets: machine Art for %s (want %s)" % (sorted(arts), sorted(cells)))
    img = RG.GuiRenderer(dump, fonts, ss=1, chrome=False, labels=False).render()
    veil = veils(dump)
    for rid, n in sorted(arts.items()):
        c = cells.get(rid)
        im = n.get("image") or {}
        rect = im.get("rect")
        if not c or rect != [c["x"], c["y"], c["w"], c["h"]]:
            bad.append("%s: rect %r, its cell %r" % (rid, rect, c))
            continue
        if im.get("pixelated") is not True:
            bad.append("%s: not marked Pixelated" % rid)
        k = n["w"] / float(c["w"])
        if k != int(k) or abs(n["h"] - k * c["h"]) > 1e-6:
            bad.append("%s: %sx%s is not whole px cells of %dx%d" % (rid, n["w"], n["h"], c["w"], c["h"]))
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
            bad.append("%s: %d of %d sampled cells are not the sheet's colour" % (rid, miss, seen))
    if bad:
        print("FAIL test_render_sheets:")
        for b in bad:
            print("  - " + b)
        return 1
    print("ok test_render_sheets: %d machines drawn from machines_a.png cell for cell; plain renders stay on the fallback" % len(arts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
