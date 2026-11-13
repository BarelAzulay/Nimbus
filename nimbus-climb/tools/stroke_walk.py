#!/usr/bin/env python3
"""kit B "stroke or panel, never both" over the dumped GUI of the render scenarios (kit-b U6).

    py -3.12 tools/stroke_walk.py                      # every render scenario at 1920x1080, fails on any hit
    py -3.12 tools/stroke_walk.py lobby shop daily     # only these
    py -3.12 tools/stroke_walk.py --grid               # also 1280x720, 390x844 and 844x390
    py -3.12 tools/stroke_walk.py --warn               # report only (exit 0)

Each scenario is dumped by tools/render_gui.py's real client boot (tools/dump_gui.lua) and walked with
render_gui.stroke_rule: a text with both a classic stroke (TextStrokeTransparency < 0.95) and an outline (a Contextual
UIStroke), or an outlined text whose nearest painted background is opaque. Text over the 3D world keeps ONE outline
(Theme Outline = "World"), so it passes: floating HUD text with no plate, and the world signs mirrored into WorldMirror
(BillboardGui / SurfaceGui), which keep their one outline on their plate (ARCHITECTURE_V3's World text rule). One
scenario is dumped at a time (one lupa world, freed after).
The casing rule (fonts audit F9) runs over the same dumps: a Button-role text (Theme's FontRole stamp) with an
all-capitals word of 4+ letters, or a Tag / Title / Sign / Accent text with a lower-case letter (Theme keeps those in
capitals). --casing reports it (not a failure: the smoke scenario kitb_casing_rule fails on the swept families; U9 renames
the remaining windows' buttons).
The contrast rule (kit-b U6 review) runs over the same dumps and fails too: a text with no outline reads by its colour
against the opaque fill painted under its glyphs (a gradient read where the glyphs are, see-through plates blended in):
3:1 for 18 px and up, 4.5:1 below (render_gui.contrast_rule; the client walk kitb_text_contrast is the same rule). The
texts listed in tools/fixtures/contrast_backlog.txt are counted, not failed (the list only shrinks; --grid over every
scenario names the lines no text hits any more).
Exit status: 0 when no scenario has a stroke or contrast hit (or --warn), 1 otherwise, 2 when a dump fails.
"""
import argparse
import gc
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import render_gui as RG  # noqa: E402

# scenes with no game UI of their own (the renderer's widget galleries)
SKIP = {"gallery", "signkit", "neon", "neon:window", "neon:hud", "neon:party"}


def casing(dump):
    """[(path, text)] of Button texts in capitals and Tag texts with a lower-case letter."""
    bad = []

    def walk(n):
        tx = n.get("text")
        if tx and tx.get("role") in ("Button", "Tag", "Title", "Sign", "Accent"):
            text = re.sub(r"<[^>]*>", "", str(tx.get("text", "")))
            if tx["role"] == "Button":
                if any(len(w) >= 4 and w == w.upper() for w in re.findall(r"[A-Za-z]+", text)):
                    bad.append((n.get("path", ""), text))
            elif re.search(r"[a-z]", text):
                bad.append((n.get("path", ""), text))
        for c in n.get("children", []):
            walk(c)

    for gui in dump.get("guis", []):
        for n in gui.get("nodes", []):
            walk(n)
    return bad


def bare(dump):
    """[(path, text)] of texts with no outline and no backdrop at all (no ancestor, itself first, more than half opaque):
    text floating over the 3D world, which kit B gives ONE outline (Outline = "World"). A review aid (--bare)."""
    out = []

    def walk(n, plate):
        here = plate or float(n.get("bgT", 1)) < 0.5 or bool(n.get("image"))
        tx = n.get("text")
        if tx and str(tx.get("text", "")).strip() and float(tx.get("t", 0)) < 0.99 and not here:
            ring = any(k.get("mode", "Contextual") == "Contextual" and float(k.get("t", 0)) < 0.95 for k in (n.get("strokes") or []))
            if not ring and float(tx.get("strokeT", 1)) >= 0.95:
                out.append((n.get("path", ""), str(tx.get("text", ""))))
        for c in n.get("children", []):
            walk(c, here)

    for gui in dump.get("guis", []):
        for n in gui.get("nodes", []):
            walk(n, False)
    return out


def main():
    ap = argparse.ArgumentParser(description="kit B stroke rule over the render scenarios")
    ap.add_argument("scenarios", nargs="*", help="render scenarios (default: every one but the galleries)")
    ap.add_argument("--grid", action="store_true", help="the four grid sizes, not only 1920x1080")
    ap.add_argument("--warn", action="store_true", help="report only, exit 0")
    ap.add_argument("--casing", action="store_true", help="also report the casing rule (buttons sentence case, tags capitals)")
    ap.add_argument("--bare", action="store_true", help="also list texts with no outline and no backdrop (over the world)")
    ap.add_argument("-v", "--verbose", action="store_true", help="list every hit, not the first 6 per scenario")
    args = ap.parse_args()

    names = args.scenarios or [s for s in RG.SCENARIOS if s not in SKIP]
    sizes = RG.GRID_SIZES if args.grid else [(1920, 1080)]
    fonts = RG.FontBook()
    total_d, total_p, total_c, total_read, failed, cased, bares = 0, 0, 0, 0, [], {}, {}
    backlog = RG.contrast_backlog()
    owed, used = 0, set()
    for name in names:
        for (w, h) in sizes:
            try:
                dump = RG.dump_scenario(name, w, h, RG.is_touch(w, h, None), fonts)
            except SystemExit as exc:
                print("DUMP FAILED %s %dx%d: %s" % (name, w, h, exc))
                failed.append(name)
                continue
            doubled, panelled = RG.stroke_rule(dump)
            dim, read = RG.contrast_rule(dump)
            total_read += read
            # the backlog (tools/fixtures/contrast_backlog.txt): reported in the totals, not failed
            kept = []
            for hit in dim:
                pattern = RG.in_backlog(backlog, hit[0])
                if pattern:
                    owed += 1
                    used.add(pattern)
                else:
                    kept.append(hit)
            dim = kept
            if args.bare:
                for path, text in bare(dump):
                    bares.setdefault(path, (text, name))
            if args.casing:
                for path, text in casing(dump):
                    cased.setdefault(path, (text, name))
            del dump
            gc.collect()
            total_d += len(doubled)
            total_p += len(panelled)
            total_c += len(dim)
            if doubled or panelled or dim:
                print("%-22s %4dx%-4d %3d stroke+outline, %3d outlined on a panel, %3d below the contrast rule"
                      % (name, w, h, len(doubled), len(panelled), len(dim)))
                cap = None if args.verbose else 6
                for p in doubled[:cap]:
                    print("    both   " + p)
                for p in panelled[:cap]:
                    print("    panel  " + p)
                for (p, text, ratio, need, col, fill, back) in dim[:cap]:
                    print("    dim    %s \"%s\" #%02X%02X%02X on #%02X%02X%02X (%s) %.2f:1 < %g"
                          % (p, text[:24], col[0], col[1], col[2], fill[0], fill[1], fill[2], back, ratio, need))
    print("stroke walk: %d scenario(s) x %d size(s): %d stroke+outline, %d outlined on a panel, %d below the contrast rule"
          " (%d texts read; %d more in the backlog, %d of its %d lines seen)%s"
          % (len(names), len(sizes), total_d, total_p, total_c, total_read, owed, len(used), len(backlog),
             (", %d dump(s) failed" % len(failed)) if failed else ""))
    if args.grid and not args.scenarios:
        for pattern, _ in backlog:
            if pattern not in used:
                print("    backlog line no longer hit (remove it): " + pattern)
    if args.casing:
        for path in sorted(cased):
            print("    casing %-70s \"%s\"  (%s)" % (path, cased[path][0], cased[path][1]))
        print("casing rule: %d text(s)" % len(cased))
    if args.bare:
        for path in sorted(bares):
            print("    bare   %-70s \"%s\"  (%s)" % (path, bares[path][0][:30], bares[path][1]))
        print("bare texts over the world: %d" % len(bares))
    if failed:
        return 2
    if args.warn:
        return 0
    return 1 if (total_d or total_p or total_c) else 0


if __name__ == "__main__":
    sys.exit(main())
