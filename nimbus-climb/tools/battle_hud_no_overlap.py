#!/usr/bin/env python3
"""battle_hud_no_overlap: the battle HUD's parts never lie on each other or off the screen (Pitch 2 item 1b option C
"Three buttons" + the battle HUD leftovers of items 06 A / 02 B / 08 C; the look reviews keys r2 and fixA r1).

    py -3.12 tools/battle_hud_no_overlap.py [--size WxH[,WxH...]] [--scenario S[,S...]] [-v] [--json FILE]

It dumps the REAL client (tools/render_gui.py's dump: tools/dump_gui.lua in the Roblox mock, the real font metrics, a
touch device when the screen's short side is <= 500 px) for every size x scenario below, the same data the look
reviews render, and fails on:
  overlap   any two of: the keys (MOVE / DASH / RUN on a phone, every Commands key on a PC), CHEER, BACK, the top card
            (with its Leave), the enemy list's rows, the fighter card, the helpers (their cells and Swap), the vitals card
            (with its name tab), the dungeon run chip, the result card (the battle's and the dungeon's End card), the
            currency strip, and on a phone Roblox's own thumbstick and jump rings;
  edge      one of them past the screen's edge;
  key       a phone key (MOVE / DASH / RUN / CHEER / BACK) under 44 px on a side; CHEER / BACK under 40 px from MOVE /
            DASH / RUN;
  cut       a name cut ("Storm Ti...") or broken mid-word: the boss name, the top card's pills, the fighter's and the
            helpers' names, the vitals name, the keys' captions;
  pills     (battle:raid:full) the boss strip's pills: one row at 844 x 390, at most two rows on a portrait phone with
            the tier beside the boss name (not a pill), no pill alone on a last row, "Enraged" as the mock-up writes it,
            and on a PC the boss portrait's slot kept;
  result    on a phone the vitals card hides while a result card is up (spec 02 B: SetVitalsHidden "Result");
  place     a portrait phone's top card spans the top above the team in every mode, the duel's as the others'.
Exit 0 when every check passes. Each failure prints its scenario, size, the two boxes and the overlap in px.
"""
import argparse
import json
import math
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

SIZES = [(360, 640), (640, 360), (667, 375), (390, 844), (844, 390), (1280, 720), (1920, 1080)]
SCENARIOS = ["battle:raid", "battle:raid:full", "battle:raid:ready", "battle:dungeon", "battle:duel", "dungeon:run",
             "dungeon:end", "dungeon:wipe"]

B = "NimbusBattle.Root."
PHONE_KEYS = ("MOVE", "DASH", "RUN")
# the cards and keys, by group: (group, path regex). A node matched by a group's regex joins that group's boxes; the
# first group that matches wins. The keys' NamePlate / HoldTag ride with their key.
GROUPS = [
    ("MOVE", r"^NimbusBattle\.Root\.Commands\.ElementButton$"),
    ("MOVE", r"^NimbusBattle\.Root\.Commands\.ElementButton\.(HoldTag|NamePlate)$"),
    ("DASH", r"^NimbusBattle\.Root\.Commands\.DashButton$"),
    ("DASH", r"^NimbusBattle\.Root\.Commands\.DashButton\.NamePlate$"),
    ("DASH", r"^MobileControls\.DashButton$"),
    ("RUN", r"^MobileControls\.RunButton$"),
    ("KEY:{1}", r"^NimbusBattle\.Root\.Commands\.(\w+Button)$"),
    ("KEY:{1}", r"^MobileControls\.(\w+Button)$"),
    ("CHEER", r"^NimbusBattle\.Root\.Cheer$"),
    ("BACK", r"^NimbusBattle\.Root\.Retreat$"),
    ("TOP", r"^NimbusBattle\.Root\.TopCard$"),
    ("TOP", r"^NimbusBattle\.Root\.LeaveButton$"),
    ("ENEMIES", r"^NimbusBattle\.Root\.Enemies\.\w+$"),
    ("FIGHTER", r"^NimbusBattle\.Root\.Team\.Fighter$"),
    ("HELPERS", r"^NimbusBattle\.Root\.Team\.Helpers\.Helper\d+$"),
    ("HELPERS", r"^NimbusBattle\.Root\.Team\.Helpers\.Helper\d+\.Swap$"),  # (its invisible 44 px SwapHit pad: not a box)
    ("VITALS", r"^NimbusHud\.\w+\.Vitals$"),
    ("VITALS", r"^NimbusHud\.\w+\.Vitals\.(NameTab|Tab|Stamp)\w*$"),
    ("RUNCHIP", r"^NimbusDungeonRun\.RunChip$"),
    ("RESULT", r"^NimbusBattle\.Root\.ResultCard$"),
    ("RESULT", r"^NimbusDungeonRun\.EndCard$"),
    ("CURRENCY", r"^NimbusHud\.\w+\.Currency\.Currency_\w+$"),
]
GROUPS = [(g, re.compile(p)) for g, p in GROUPS]
# labels that must be whole (not cut, not broken mid-word): path regex
WHOLE = [
    r"^NimbusBattle\.Root\.TopCard\..*BossName$",
    r"^NimbusBattle\.Root\.TopCard\.Pills\.\w+$",
    r"^NimbusBattle\.Root\.Team\.Fighter\..*PetName$",
    r"^NimbusBattle\.Root\.Team\.Helpers\.Helper\d+\..*(Buff|Name)\w*$",
    r"^NimbusHud\.\w+\.Vitals\..*Name\w*$",
    r"^NimbusBattle\.Root\.Commands\.\w+Button\.(Caption|NamePlate)(\.\w+)?$",
]
WHOLE = [re.compile(p) for p in WHOLE]


def rect(n):
    return (float(n["x"]), float(n["y"]), float(n["x"]) + float(n["w"]), float(n["y"]) + float(n["h"]))


def overlap(a, b):
    """(width, height) of the intersection of two boxes, 0 when they only touch or are apart"""
    ox = min(a[2], b[2]) - max(a[0], b[0])
    oy = min(a[3], b[3]) - max(a[1], b[1])
    return (ox, oy) if ox > 0.5 and oy > 0.5 else None


def gap(a, b):
    dx = max(b[0] - a[2], a[0] - b[2], 0.0)
    dy = max(b[1] - a[3], a[1] - b[3], 0.0)
    if dx == 0 and dy == 0:
        ov = overlap(a, b)
        return -min(ov) if ov else 0.0
    return math.hypot(dx, dy)


def ring_gap(r, c, rad):
    cx = min(max(c[0], r[0]), r[2])
    cy = min(max(c[1], r[1]), r[3])
    return math.hypot(cx - c[0], cy - c[1]) - rad


def rings(w, h):
    """Roblox's touch thumbstick and jump button as render_gui sketches them: {name: (centre, radius)}"""
    small = min(w, h) <= 500
    j = 70.0 if small else 120.0
    y1 = h - (20.0 if small else j * 0.75)
    jx0 = w - (j * 1.5 + 10)
    tx0 = (j / 2.0 - 10) if small else j / 2.0
    return {"Roblox jump": ((jx0 + j / 2, y1 - j / 2), j / 2), "Roblox stick": ((tx0 + j / 2, y1 - j / 2), j / 2)}


def nodes_of(dump):
    out = {}

    def walk(n):
        out.setdefault(n["path"], n)
        for c in n.get("children", []):
            walk(c)

    for g in dump["guis"]:
        if g.get("enabled", True):
            for n in g["nodes"]:
                walk(n)
    return out


def group_of(path):
    for g, pat in GROUPS:
        m = pat.match(path)
        if m:
            return g.replace("{1}", m.group(1)) if "{1}" in g else g
    return None


def collect(nodes):
    groups = {}
    for path, n in nodes.items():
        if n["w"] <= 1 or n["h"] <= 1:
            continue
        g = group_of(path)
        if g:
            groups.setdefault(g, []).append((path, rect(n)))
    # (a phone's DASH out of a battle is MovementController's; in a battle the HUD's own) one DASH box per screen
    return groups


def text_of(n):
    t = n.get("text")
    return t if isinstance(t, dict) and t.get("text") else None


class Checker:
    def __init__(self, rg, fonts, verbose=False):
        self.rg = rg
        self.fonts = fonts
        self.verbose = verbose
        self.passed = 0
        self.failed = []

    def check(self, ok, what, detail=""):
        if ok:
            self.passed += 1
        else:
            self.failed.append("%s  -- %s" % (what, detail) if detail else what)
        return ok

    def run(self, scen, w, h, dump):
        tag = "%s %dx%d: " % (scen, w, h)
        touch = bool(dump.get("touch"))
        nodes = nodes_of(dump)
        groups = collect(nodes)
        boxes = []  # (group, path, rect)
        for g, items in sorted(groups.items()):
            for path, r in items:
                boxes.append((g, path, r))
        if touch and dump.get("touchControls", True) is not False:
            for name, (c, rad) in rings(w, h).items():
                boxes.append((name, name, (c[0] - rad, c[1] - rad, c[0] + rad, c[1] + rad)))
        if self.verbose:
            for g, path, r in boxes:
                print("   %-10s %-70s %4.0f,%4.0f - %4.0f,%4.0f" % (g, path, r[0], r[1], r[2], r[3]))
        # overlap: every pair of boxes from different groups
        for i in range(len(boxes)):
            gi, pi, ri = boxes[i]
            for k in range(i + 1, len(boxes)):
                gk, pk, rk = boxes[k]
                if gi == gk:
                    continue
                ring_i, ring_k = gi.startswith("Roblox "), gk.startswith("Roblox ")
                if ring_i and ring_k:
                    continue
                if ring_i or ring_k:
                    (c, rad), r, other, op = (rings(w, h)[gi], rk, gk, pk) if ring_i else (rings(w, h)[gk], ri, gi, pi)
                    d = ring_gap(r, c, rad)
                    self.check(d >= 0, tag + "%s keeps off %s" % (op, gi if ring_i else gk), "%s %s %.1f px" % (other, fmt(r), d))
                    continue
                ov = overlap(ri, rk)
                self.check(ov is None, tag + "%s and %s do not overlap" % (pi, pk),
                           "%s vs %s: %s" % (fmt(ri), fmt(rk), "%.0f x %.0f px" % ov if ov else ""))
        # edge
        for g, path, r in boxes:
            if g.startswith("Roblox "):
                continue
            self.check(r[0] >= -0.5 and r[1] >= -0.5 and r[2] <= w + 0.5 and r[3] <= h + 0.5, tag + "%s is on the screen" % path, fmt(r))
        # keys: >= 44 px, CHEER / BACK 40 px off MOVE / DASH / RUN
        if touch:
            for g in ("MOVE", "DASH", "RUN", "CHEER", "BACK"):
                for path, r in groups.get(g, []):
                    if path.endswith(("HoldTag", "NamePlate")):
                        continue
                    self.check(min(r[2] - r[0], r[3] - r[1]) >= 44 - 0.5, tag + "%s is at least 44 px" % path, fmt(r))
            for t in ("CHEER", "BACK"):
                for tp, tr in groups.get(t, []):
                    for k in PHONE_KEYS:
                        for kp, kr in groups.get(k, []):
                            self.check(gap(tr, kr) >= 40 - 0.5, tag + "%s keeps 40 px off %s" % (tp, kp), "%.1f px" % gap(tr, kr))
        # cut: the names stay whole, laid out the way render_gui draws them (its layout_text: the real font, the wrap,
        # the truncation): no ellipsis, no word broken over two lines, no line past the box's foot
        for path, n in nodes.items():
            t = text_of(n)
            if not t or not any(p.match(path) for p in WHOLE):
                continue
            label = t["text"]
            pl, pr, pt, pb = (n.get("pad") or [0, 0, 0, 0])[:4]
            aw, ah = float(n["w"]) - pl - pr, float(n["h"]) - pt - pb
            size, lines = self.rg.layout_text(self.fonts, t, aw, ah)
            drawn = ["".join(c for c, _ in line) for line in lines]
            cut = any("…" in d for d in drawn) and "…" not in label
            words = set(x for x in re.split(r"\s+", label.replace("\n", " ")) if x)
            broken = [d for d in drawn for x in d.split() if x not in words and "…" not in x]
            tall = len(lines) * size * float(t.get("lineHeight", 1) or 1) > ah + 1.0
            self.check(not cut and not broken and not tall, tag + "%s '%s' is whole" % (path, label.replace("\n", " / ")),
                       "drawn %s in %.0f x %.0f at %.1f px" % (" / ".join(repr(d) for d in drawn), aw, ah, size))
        # result: the vitals hide on a phone while a result card is up
        if touch and groups.get("RESULT"):
            self.check(not groups.get("VITALS"), tag + "the vitals card hides while the result card is up (SetVitalsHidden 'Result')",
                       ", ".join(p for p, _ in groups.get("VITALS", [])))
        # pills (the full raid's boss strip)
        if scen == "battle:raid:full":
            self.pills(tag, w, h, nodes)
        # place: a portrait phone's top card spans the top above the team (spec 06 A's 390 x 844 frame), the duel's as
        # the raid's and the dungeon's (look fixA r1: the duel's dropped between the helpers and the list; at 360 x 640 the
        # full raid's squeezed to a ~170-211 px column under the fighter card, its pills one per line)
        if touch and h > w and scen.startswith("battle:"):
            top, fighter = groups.get("TOP"), groups.get("FIGHTER")
            card = nodes.get(B + "TopCard")
            if top and fighter and card:
                cr = rect(card)
                fy = min(r[1] for _, r in fighter)
                self.check(cr[1] < fy and cr[2] - cr[0] >= 0.85 * w, tag + "the top card spans the top of the screen, above the team",
                           "top card %s (%.0f px wide), fighter y %.0f" % (fmt(cr), cr[2] - cr[0], fy))

    def pills(self, tag, w, h, nodes):
        pre = B + "TopCard.Pills."
        pills = [(p, rect(n)) for p, n in nodes.items() if p.startswith(pre) and p.count(".") == pre.count(".") and n["w"] > 1]
        if not pills:
            self.check(False, tag + "the boss strip shows its pills")
            return
        rows = {}
        for p, r in pills:
            rows.setdefault(round(r[1] / 4.0), []).append(p)
        order = [rows[k] for k in sorted(rows)]
        names = " | ".join(" ".join(x.split(".")[-1] for x in row) for row in order)
        if (w, h) == (844, 390):
            self.check(len(order) == 1, tag + "the pills sit in one row (spec 06 A: all four in one row on the phone)", names)
        if h > w:
            self.check(len(order) <= 2, tag + "the pills take at most two rows (spec 06 A: a portrait card wraps them to a second row)", names)
            tiers = [p for p, _ in pills if p.split(".")[-1].lower().startswith("tier")]
            self.check(not tiers, tag + "the tier sits beside the boss name, not as a pill", ", ".join(tiers))
        if len(order) > 1:
            self.check(len(order[-1]) >= 2, tag + "no pill alone on the last row", names)
        enr = nodes.get(pre + "Enraged")
        t = text_of(enr) if enr else None
        if t:
            self.check(t["text"].strip() == "Enraged", tag + "the enrage pill reads 'Enraged' as the mock-up, not in capitals", repr(t["text"]))
        if w >= 1000:
            slot = [p for p in nodes if p.startswith(B + "TopCard.") and re.search(r"(BossHead|Portrait)\w*$", p)]
            self.check(bool(slot), tag + "the boss portrait's slot is kept (the head, or its fallback before the upload)")


def fmt(r):
    return "%.0f,%.0f-%.0f,%.0f" % r


def parse_sizes(text):
    out = []
    for part in text.split(","):
        a, b = part.lower().split("x")
        out.append((int(a), int(b)))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--size", help="WxH[,WxH...] (default: all seven)")
    ap.add_argument("--scenario", help="S[,S...] (default: all eight)")
    ap.add_argument("-v", "--verbose", action="store_true", help="print every box")
    ap.add_argument("--json", help="write the failures as JSON")
    args = ap.parse_args()
    os.chdir(ROOT)
    import render_gui as RG

    sizes = parse_sizes(args.size) if args.size else SIZES
    scens = args.scenario.split(",") if args.scenario else SCENARIOS
    fonts = RG.FontBook()
    ck = Checker(RG, fonts, args.verbose)
    t0 = time.time()
    for scen in scens:
        for (w, h) in sizes:
            touch = RG.is_touch(w, h, None)
            try:
                dump = RG.dump_scenario(scen, w, h, touch, fonts)
            except SystemExit as exc:
                ck.check(False, "%s %dx%d: the scenario dumps" % (scen, w, h), str(exc))
                continue
            n0 = len(ck.failed)
            ck.check(not dump.get("errors"), "%s %dx%d: no script errors" % (scen, w, h), "; ".join(e.splitlines()[0] for e in dump.get("errors", [])[:3]))
            ck.run(scen, w, h, dump)
            if args.verbose or len(ck.failed) > n0:
                print("%-18s %4dx%-4d %s" % (scen, w, h, "ok" if len(ck.failed) == n0 else "%d failed" % (len(ck.failed) - n0)))
    for f in ck.failed:
        print("  FAIL  " + f)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(ck.failed, fh, indent=1)
    print("battle_hud_no_overlap: %d passed, %d failed  (%.1fs)" % (ck.passed, len(ck.failed), time.time() - t0))
    return 1 if ck.failed else 0


if __name__ == "__main__":
    sys.exit(main())
