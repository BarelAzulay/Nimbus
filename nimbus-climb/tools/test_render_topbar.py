"""Pitch 2 fix round B (T1 look leftover 6): a touch render draws the top bar's pill at its real size.

render_gui.py booted every touch render with GuiService.TopbarInset unset (nil), so TopBarController took its PC
fallback (the pill from x 212, the right limit 72 px off the edge): on a 390 px portrait phone the three buttons were
squeezed to 31 px. A real phone's top bar keeps Roblox's buttons on the left (about 112 px) and the "..." button on the
right (72 px) in a 58 px band, so a touch render sets that inset. This test fails when a touch render's top-bar
buttons are under 44 x 44 screen px or start under Roblox's left buttons, and when a desktop render gets a phone inset.
Run: py -3.12 tools/test_render_topbar.py (boots the Lua mock; a few seconds)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import render_gui as RG  # noqa: E402


def walk(nodes, out):
    for n in nodes or []:
        out.append(n)
        walk(n.get("children"), out)
    return out


def pill_buttons(dump):
    for g in dump.get("guis", []):
        if g.get("name") == "NimbusTopBar":
            return [n for n in walk(g.get("nodes"), []) if str(n.get("name", "")).startswith("PillButton_")]
    return []


def main():
    fonts = RG.FontBook()
    bad = []
    for (w, h) in [(390, 844), (844, 390)]:
        dump = RG.dump_scenario("lobby", w, h, True, fonts)
        buttons = pill_buttons(dump)
        if not buttons:
            bad.append("%dx%d: no PillButton_ in NimbusTopBar" % (w, h))
            continue
        for b in buttons:
            bw, bh, bx = float(b.get("w", 0)), float(b.get("h", 0)), float(b.get("x", 0))
            if bw < 44 - 0.5 or bh < 44 - 0.5:
                bad.append("%dx%d: %s %.0f x %.0f (under 44)" % (w, h, b.get("name"), bw, bh))
            if bx < 112:
                bad.append("%dx%d: %s at x %.0f, under Roblox's left buttons" % (w, h, b.get("name"), bx))
    # a desktop render keeps the PC fallback (no phone inset)
    dump = RG.dump_scenario("lobby", 1920, 1080, False, fonts)
    xs =[float(b.get("x", 0)) for b in pill_buttons(dump)]
    if not xs or min(xs) < 212 - 0.5:
        bad.append("1920x1080 desktop: the pill should start at the PC fallback x 212, got %s" % (min(xs) if xs else "none"))
    if bad:
        print("FAIL render_gui touch top bar:\n  " + "\n  ".join(bad))
        return 1
    print("ok render_gui touch top bar: real phone inset, 44 px buttons; desktop keeps the fallback")
    return 0


if __name__ == "__main__":
    sys.exit(main())
