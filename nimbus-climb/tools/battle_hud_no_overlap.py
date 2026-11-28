#!/usr/bin/env python3
"""battle_hud_no_overlap: the battle HUD's parts never lie on each other or off the screen (Pitch 2 item 1b option C
"Three buttons" + the battle HUD leftovers of items 06 A / 02 B / 08 C; the look reviews keys r2 and fixA r1).

    py -3.12 tools/battle_hud_no_overlap.py [--size WxH[,WxH...]] [--scenario S[,S...]] [-v] [--json FILE]

It dumps the REAL client (tools/render_gui.py's dump: tools/dump_gui.lua in the Roblox mock, the real font metrics, a
touch device when the screen's short side is <= 500 px) for every size x scenario below, the same data the look
reviews render, and fails on:
  overlap   any two of: the keys (MOVE / DASH / RUN on a phone, every Commands key on a PC), CHEER, BACK, the top card
            (with its Leave), the enemy list's rows, the fighter card, each helper (its cell and Swap), the vitals card
            (with its name tab), the dungeon run chip, the result card (the battle's and the dungeon's End card), the
            card between two ring rounds, the currency strip, and on a phone Roblox's own thumbstick and jump rings, closer than MIN_GAP (4) px; the run
            chip closer than RUNCHIP_GAP (6) px to any of them. Each part is measured by its INK (keys look r4), what
            render_gui paints of its subtree: backgrounds, Outer / Center UIStrokes and borders past the box (the enemy
            row's gold target bracket), children past their parent (a helper's Lv tag, the hearts' pixel art), images,
            the text block, the drawn hard shadow (FinishShadow), each cut by its clipping ancestors;
  edge      one of them past the screen's edge;
  key       a phone key (MOVE / DASH / RUN / CHEER / BACK) under 44 px on a side; CHEER / BACK / the run chip under 40 px
            from MOVE / DASH / RUN; the run chip's Leave under 44 px (its LeaveHit pad), or that pad on another part;
  gap       (phone) the enemy list under 8 px from the fighter card or the top card, shadows counted;
  fighter   the fighter card's own parts (name, Lv, element badge, evo stars, HP, ENERGY, hearts) under PART_GAP (1) px
            of each other or its lip, by their ink (a bare caption's text block may touch, not overlap);
  tags      (PC) a key's name tag not under its own key (it spans the key's centre);
  helpers   at 844 x 390 a helper without 01b C's cell (Lv / name / labelled Swap under each other); a name plate as tall
            as two lines that draws one;
  clock     the top card's timer without its clock (640 x 360's raid / dungeon card excepted: no room);
  cut       a name cut ("Storm Ti...") or broken mid-word: the boss name, the top card's pills and mode line ('Round 8'),
            the fighter's and the helpers' names, the vitals name, the keys' captions;
  pills     (battle:raid:full) the boss strip's pills: one row at 844 x 390, at most two rows on a portrait phone with
            the tier beside the boss name (not a pill), no pill alone on a row at any size, "Enraged" as the mock-up
            writes it, on a PC the boss portrait's slot kept, and a landscape phone's top card under 45 % of the height;
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
             "dungeon:end", "dungeon:wipe",
             # (kit-b backlog 9: the Champion Ring's fight and the trial's, never listed here: at 360 x 640 enemy row 1 lay
             # 15-18 px on the fighter card, 'Round 8' read 'Ro...'; 375 x 667 'Biscuit B...'; 390 x 844 the top card 37.6 px
             # on the fighter card) (playtest 2026-11-28 C62: battle:trial:ready rendered a ring round, the Trial setup is
             # gone; the ready phase is walked on the dungeon fight)
             "battle:fighter", "battle:ring:fight8", "battle:dungeon:ready",
             # (kitb-matchhud look0 N2: the card between two ring rounds, 'ROUND 8 WON! Round 9 in 3', never listed either:
             # with the ring's strip across a portrait phone's top (kit-b backlog 9) the team moved down under it and the
             # card did not - at 360 x 640 it lay 32.8 px on the helpers ('HA', 'T... ME'), at 375 x 667 19.4, at 384 x 640
             # 13.6; at 390 x 844 .. 430 x 932 it ended 2-3 px above RUN)
             "battle:ring:next8"]
# (look0 N2) the portrait phones the look rendered the card between ring rounds at, beyond SIZES (a default run only)
SCENARIO_SIZES = {"battle:ring:next8": [(375, 667), (384, 640), (393, 852), (412, 915), (430, 932)]}

B = "NimbusBattle.Root."
PHONE_KEYS = ("MOVE", "DASH", "RUN")
# (keys look r4) the air between two parts' inks, screen px: the cards and keys (the mock-ups 01b C / 06 A keep 5-6 px
# between neighbouring cards; 2 px read as glued), the run chip's from every neighbour, the fighter card's own parts
MIN_GAP = 4.0
RUNCHIP_GAP = 6.0
PART_GAP = 1.0
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
    # (a PC key's name tag hangs under its key: two keys' tags must not run into each other either; the render showed
    # SPECIAL's "MARSHMALLOW STAMPEDE" tag over TARGET's at 1280 x 720)
    ("KEY:{1}", r"^NimbusBattle\.Root\.Commands\.(\w+Button)\.NamePlate$"),
    ("KEY:{1}", r"^MobileControls\.(\w+Button)$"),
    ("CHEER", r"^NimbusBattle\.Root\.Cheer$"),
    ("BACK", r"^NimbusBattle\.Root\.Retreat$"),
    ("TOP", r"^NimbusBattle\.Root\.TopCard$"),
    ("TOP", r"^NimbusBattle\.Root\.LeaveButton$"),
    # (keys look r5 c06: with the whole list one part, the selected row's gold target bracket lay 2.4-3 px on row 2's top
    # frame and on '+3 more' at every size and the rows' frames stood 0.8 px apart, and 0 failed) each row and the
    # '+n more' tag is its own part: MIN_GAP between them, the bracket counted
    ("ENEMY:{1}", r"^NimbusBattle\.Root\.Enemies\.(\w+)$"),
    ("FIGHTER", r"^NimbusBattle\.Root\.Team\.Fighter$"),
    # (keys look r4: helper 1's Swap stood 0.8 px over helper 2's tags at 360 x 640 and 844 x 390) each helper's cell is
    # its own part, its Swap with it
    ("HELPER:{1}", r"^NimbusBattle\.Root\.Team\.Helpers\.(Helper\d+)$"),
    ("HELPER:{1}", r"^NimbusBattle\.Root\.Team\.Helpers\.(Helper\d+)\.Swap$"),  # (its invisible 44 px SwapHit pad: not a box)
    ("VITALS", r"^NimbusHud\.\w+\.Vitals$"),
    ("VITALS", r"^NimbusHud\.\w+\.Vitals\.(NameTab|Tab|Stamp)\w*$"),
    ("RUNCHIP", r"^NimbusDungeonRun\.RunChip$"),
    ("RESULT", r"^NimbusBattle\.Root\.ResultCard$"),
    ("RESULT", r"^NimbusDungeonRun\.EndCard$"),
    # (look0 N2) the card between two ring rounds (Ring.PlaceNext), its LEAVE on it
    ("NEXT", r"^NimbusBattle\.Root\.NextRoundCard$"),
    ("CURRENCY", r"^NimbusHud\.\w+\.Currency\.Currency_\w+$"),
]
GROUPS = [(g, re.compile(p)) for g, p in GROUPS]
# labels that must be whole (not cut, not broken mid-word): path regex
WHOLE = [
    r"^NimbusBattle\.Root\.TopCard\..*BossName$",
    r"^NimbusBattle\.Root\.TopCard\.Pills\.\w+$",
    # (kit-b backlog 9: the ring round's mode line 'Round 8' drawn 'Ro...' in a 40 px box at 360 x 640, 'Roun...' at
    # 375 x 667) the mode line reads whole (its shortest form at least: Hud.ModeText's shorts)
    r"^NimbusBattle\.Root\.TopCard\.ModeCard\.Body\.Mode$",
    r"^NimbusBattle\.Root\.Team\.Fighter\..*PetName$",
    r"^NimbusBattle\.Root\.Team\.Fighter\.Body\.EnergyText$",  # (keys look r3: the stars' row narrows it)
    r"^NimbusBattle\.Root\.Team\.Helpers\.Helper\d+\..*(Buff|Name)\w*$",
    r"^NimbusHud\.\w+\.Vitals\..*Name\w*$",
    r"^NimbusBattle\.Root\.Commands\.\w+Button\.(Caption|NamePlate)(\.\w+)?$",
    # (look0 N2 re-look) the next round's countdown ('Next in 3' ran past its box under LEAVE at 640 x 360)
    r"^NimbusBattle\.Root\.NextRoundCard\.Countdown$",
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


def clip_to(a, b):
    if a is None:
        return b
    if b is None:
        return a
    r = (max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]))
    return r if r[2] > r[0] and r[3] > r[1] else (r[0], r[1], r[0], r[1])


def nodes_of(dump):
    """{path: node}; each node also gets "_clip", the rect its clipping ancestors (ClipsDescendants) leave it"""
    out = {}

    def walk(n, clip):
        n["_clip"] = clip
        out.setdefault(n["path"], n)
        inner = clip_to(clip, rect(n)) if n.get("clip") else clip
        for c in n.get("children", []):
            walk(c, inner)

    for g in dump["guis"]:
        if g.get("enabled", True):
            for n in g["nodes"]:
                walk(n, None)
    return out


# --- ink: what the player sees of a part, not its layout box (keys look r4: a 16 px pixel heart in a 14.4 px Lives box
# ran 1.6 px past it onto the element badge's frame; the selected enemy row's gold target bracket, an Outer UIStroke 2 px
# round a box 3.2 px wider than the row, lay on the run chip, the Swap keys and "+3 more"; a helper's Lv tag stands above
# its cell, where the fighter card's shadow fell on it). Drawn the way tools/render_gui.py paints them.
def ring_out(n):
    """how far a node's drawn box ring reaches past its box: UIStroke Outer / Center (a text's Contextual stroke rings
    its glyphs, not the box) and Roblox's legacy border (drawn only with a visible background and no UICorner)"""
    text_node = n.get("text") is not None
    out = None
    for k in n.get("strokes") or []:
        if text_node and k.get("mode", "Contextual") == "Contextual":
            continue
        t = float(k.get("thickness", 1))
        if t <= 0 or float(k.get("t", 0)) >= 0.995:
            continue
        pos = k.get("position") or "Outer"
        o = t if pos == "Outer" else (t / 2.0 if pos == "Center" else 0.0)
        out = o if out is None else max(out, o)
    b = n.get("border")
    if b and n.get("corner") is None and float(n.get("bgT", 0)) < 0.995 and float(b.get("size", 0)) > 0:
        mode = b.get("mode", "Outline")
        t = float(b["size"])
        o = t / 2.0 if mode == "Middle" else (0.0 if mode == "Inset" else t)
        out = o if out is None else max(out, o)
    return out


def text_ink(n, rg, fonts):
    """the drawn text block of a text node (render_gui's paint_text), None when it draws no text"""
    tx = n.get("text")
    if not isinstance(tx, dict) or not str(tx.get("text", "")).strip() or float(tx.get("t", 0)) >= 0.99:
        return None
    if int(tx.get("maxGraphemes", -1)) == 0:
        return None
    pl, pr, pt, pb = (n.get("pad") or [0, 0, 0, 0])[:4]
    ax, ay = float(n["x"]) + pl, float(n["y"]) + pt
    aw, ah = max(0.0, float(n["w"]) - pl - pr), max(0.0, float(n["h"]) - pt - pb)
    size, lines = rg.layout_text(fonts, tx, aw, ah)
    if not lines:
        return None
    font = tx.get("font", "SourceSans")
    step = size * float(tx.get("lineHeight", 1) or 1)
    total = step * len(lines)
    ya, xa = tx.get("ya", "Center"), tx.get("xa", "Center")
    top = ay if ya == "Top" else (ay + ah - total if ya == "Bottom" else ay + (ah - total) / 2.0)
    x0, x1 = None, None
    for line in lines:
        lw = fonts.width(font, "".join(c for c, _ in line), size)
        lx = ax if xa == "Left" else (ax + aw - lw if xa == "Right" else ax + (aw - lw) / 2.0)
        x0 = lx if x0 is None else min(x0, lx)
        x1 = lx + lw if x1 is None else max(x1, lx + lw)
    if x1 - x0 <= 0:
        return None
    return (x0, top, x1, top + total)


def drawn_rects(n, rg, fonts):
    """the rects one node paints: its background, its ring (stroke / border, with the box inside it), its image, its
    text; each cut by its clipping ancestors"""
    out = []
    r = rect(n)
    has_box = r[2] - r[0] > 0 and r[3] - r[1] > 0
    if has_box and float(n.get("bgT", 0)) < 0.995:
        out.append(r)
    o = ring_out(n) if has_box else None
    if o is not None:
        out.append((r[0] - o, r[1] - o, r[2] + o, r[3] + o))
    img = n.get("image")
    if has_box and img and float(img.get("t", 0)) < 0.99:
        out.append(r)
    t = text_ink(n, rg, fonts) if rg is not None else None
    if t:
        out.append(t)
    clip = n.get("_clip")
    if clip is not None:
        out = [c for c in (clip_to(x, clip) for x in out) if c[2] - c[0] > 0 and c[3] - c[1] > 0]
    return out


def ink_of(n, rg, fonts):
    """every rect a node and its subtree paint (a group's part: a card with its tags, hearts, brackets and shadow)"""
    out = list(drawn_rects(n, rg, fonts))
    for c in n.get("children", []):
        out.extend(ink_of(c, rg, fonts))
    return out


def union(rs):
    return (min(r[0] for r in rs), min(r[1] for r in rs), max(r[2] for r in rs), max(r[3] for r in rs)) if rs else None


def ink_gap(la, lb, ua, ub, need):
    """(the least gap between two inks, the two rects that make it); the unions first: apart by need, done"""
    d = gap(ua, ub)
    if d >= need:
        return d, ua, ub
    best = None
    for a in la:
        if gap(a, ub) >= need:
            continue
        for b in lb:
            g = gap(a, b)
            if best is None or g < best[0]:
                best = (g, a, b)
    return best if best else (d, ua, ub)


def group_of(path):
    for g, pat in GROUPS:
        m = pat.match(path)
        if m:
            return g.replace("{1}", m.group(1)) if "{1}" in g else g
    return None


def collect(nodes, rg=None, fonts=None):
    """{group: [(path, ink union)]} and {path: [ink rects]}: each part as the player sees it (its subtree's ink), not its
    layout box"""
    groups, inks = {}, {}
    for path, n in nodes.items():
        if n["w"] <= 1 or n["h"] <= 1:
            continue
        g = group_of(path)
        # (keys look r3: the "no overlap" held for the card bodies only; at 390 x 844 the enemy list's first row lay over the
        # fighter card's hard shadow, 4 x 30 px, and at 640 x 360 the run chip's shadow on RUN) a card's drawn hard shadow
        # (its FinishShadow's FarR / FarB) is part of it: its ink, the card's subtree, holds it
        if g:
            ink = ink_of(n, rg, fonts)  # (rg None: all but the texts)
            if not ink:
                continue
            inks[path] = ink
            groups.setdefault(g, []).append((path, union(ink)))
    # (a phone's DASH out of a battle is MovementController's; in a battle the HUD's own) one DASH box per screen
    return groups, inks


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
        groups, inks = collect(nodes, self.rg, self.fonts)
        boxes = []  # (group, path, ink union)
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
                    # (keys look r5 c09 asked MIN_GAP here: 844 x 390's helpers now end 4.8 / 8 px above the stick's ring;
                    # 640 x 360 and 667 x 375 keep 1-2 px: their helper column is already at its tightest (the short
                    # cell, the names on two solid lines), and 4 px more would cut "TIDE MEND". The ring is Roblox's
                    # translucent sketch, so the rule stays: no ink on it)
                    d = min(ring_gap(x, c, rad) for x in inks.get(op, [r]))
                    self.check(d >= 0, tag + "%s keeps off %s" % (op, gi if ring_i else gk), "%s %s %.1f px" % (other, fmt(r), d))
                    continue
                # (keys look r4: "no overlap" let parts touch: at 640 x 360 the run chip's Leave hung 0.4 px under the
                # target bracket, '+3 more' 4.6 px beside it; at 360 x 640 a currency strip's border lay on helper 2's Lv
                # tag and the chip 2.2 px under the strip) every two parts keep MIN_GAP px of air between their inks, the
                # run chip RUNCHIP_GAP px from every neighbour
                need = RUNCHIP_GAP if "RUNCHIP" in (gi, gk) else MIN_GAP
                d, a, b = ink_gap(inks[pi], inks[pk], ri, rk, need)
                self.check(d >= need - 0.05, tag + "%s and %s keep %g px apart" % (pi, pk, need),
                           "ink %s vs %s: %s" % (fmt(a), fmt(b), ("%.1f px apart" % d) if d >= 0 else ("%.1f px over" % -d)))
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
            # (keys look r3: at 640 x 360 the dungeon run chip's red Leave stood 10 px above RUN, a held key, its shadow on
            # it) the run chip keeps the team orders' 40 px off the thumbs' keys too: one press arms it
            for t in ("CHEER", "BACK", "RUNCHIP"):
                for tp, tr in groups.get(t, []):
                    for k in PHONE_KEYS:
                        for kp, kr in groups.get(k, []):
                            self.check(gap(tr, kr) >= 40 - 0.5, tag + "%s keeps 40 px off %s" % (tp, kp), "%.1f px" % gap(tr, kr))
            # (keys look r3: the run chip's Leave was a 74 x 30 touch target; the top card's has its 58 x 44 LeaveHit) a
            # phone's Leave takes a thumb: its button or its hit pad at least 44 px on a side
            for lp in [p for p in nodes if re.match(r"^NimbusDungeonRun\.RunChip\.Body\.LeaveButton$", p)]:
                lr = rect(nodes[lp])
                hit = nodes.get(lp + ".LeaveHit")
                hr = rect(hit) if hit else lr
                big = max(min(lr[2] - lr[0], lr[3] - lr[1]), min(hr[2] - hr[0], hr[3] - hr[1]))
                self.check(big >= 44 - 0.5, tag + "%s takes a 44 px thumb (its hit pad)" % lp, "button %s, pad %s" % (fmt(lr), fmt(hr) if hit else "none"))
                if hit:
                    # (the pad stays off the keys and the other cards: a tap there must not leave the run)
                    for g, path, r in boxes:
                        if g in ("RUNCHIP",) or g.startswith("Roblox "):
                            continue
                        ov = overlap(hr, r)
                        self.check(ov is None, tag + "the run chip's LeaveHit stays off %s" % path, "%s vs %s" % (fmt(hr), fmt(r)))
        # (keys look r3: at 640 x 360 and 667 x 375 helper 1's 44 px Swap pad reached 6 px over the fighter card and helper
        # 2's 8 px over helper 1's buff plate) a helper's Swap pad stays off every other part: the other helper, the cards,
        # the keys
        for i in (1, 2):
            cell = B + "Team.Helpers.Helper%d" % i
            pad = nodes.get(cell + ".SwapHit")
            if not pad or pad["w"] <= 1:
                continue
            pr = rect(pad)
            for g, path, r in boxes:
                if g.startswith("Roblox ") or path == cell or path.startswith(cell + "."):
                    continue
                ov = overlap(pr, r)
                self.check(ov is None, tag + "helper %d's SwapHit stays off %s" % (i, path), "%s vs %s: %s" % (fmt(pr), fmt(r), "%.0f x %.0f px" % ov if ov else ""))
        # (keys look r3: at 390 x 844 the enemy list's first row started 0-1 px from the fighter card, over its shadow, its
        # top 0.4 px under the top card's shadow; the selected row's outline merged with both. The mock-up keeps 14-23 px)
        # on a phone the enemy list keeps 8 px off the fighter card and the top card, their shadows counted
        if touch:
            # (keys look r3: at 360 x 640 the currency strips stood 0.4 px off the fighter card's hard shadow) the strips beside
            # the fighter card keep 4 px clear of it, its shadow counted
            for cp, cr in groups.get("CURRENCY", []):
                for op, orr in groups.get("FIGHTER", []):
                    d = gap(cr, orr)
                    self.check(d >= 4 - 0.5, tag + "%s keeps 4 px off %s" % (cp, op), "%s vs %s: %.1f px" % (fmt(cr), fmt(orr), d))
            for ep, er in [x for g in sorted(groups) if g.startswith("ENEMY:") for x in groups[g]]:
                for g in ("FIGHTER", "TOP"):
                    for op, orr in groups.get(g, []):
                        d = gap(er, orr)
                        self.check(d >= 8 - 0.5, tag + "%s keeps 8 px off %s" % (ep, op), "%s vs %s: %.1f px" % (fmt(er), fmt(orr), d))
        # (keys look r3: commits 24784ca / 704fdfa put the 18 px element badge on the 14 px ENERGY caption's row: on every
        # phone it lay 18 x 4 px on the card's gold lip, the evo star on the hearts and the lip) the fighter card's own parts
        # never lie on each other nor on its lip
        self.fighter(tag, nodes)
        if not touch:
            self.key_tags(tag, nodes)
        self.helpers(tag, w, h, nodes)
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
        # clock: (keys look r3: the timer's clock came and went with the card's width alone, none at 667 x 375 in the
        # dungeon and the duel, at 844 x 390 in the duel with 70 px free, at 390 x 844 in the full raid) the top card's timer
        # wears the mock-up's clock ("clock 4:57") at every size; 640 x 360's 274 px raid / dungeon card in the gap has no room
        # for it beside the whole boss name / mode line (the duel's has)
        timer = nodes.get(B + "TopCard.ModeCard.Body.Timer")
        if timer and text_of(timer) and not ((w, h) == (640, 360) and not scen.startswith("battle:duel")):
            self.check(B + "TopCard.ModeCard.Body.Clock" in nodes, tag + "the top card's timer wears its clock")
        # (keys look r5 c07: at 640 x 360 the timer '5:21' ended 2.8 px from Leave's frame; both ride in the TOP part) the
        # timer's text keeps MIN_GAP off Leave's ink
        leave = nodes.get(B + "LeaveButton")
        if timer and leave and text_of(timer) and leave["w"] > 1 and self.rg is not None:
            ti, li = text_ink(timer, self.rg, self.fonts), ink_of(leave, None, None)
            if ti and li:
                d = ink_gap([ti], li, ti, union(li), MIN_GAP)[0]
                self.check(d >= MIN_GAP - 0.05, tag + "the top card's timer keeps %g px off Leave" % MIN_GAP,
                           "timer %s, Leave %s: %.1f px" % (fmt(ti), fmt(union(li)), d))
        # (kitb-matchhud look0 N2 re-look: the card between ring rounds, kept off the top card's shadow at 640 x 360 /
        # 667 x 375, drew 'Next in 3' 1.4 px from its inline LEAVE's frame, its stroke on it; kit-b kept 5.4) the countdown's
        # text keeps MIN_GAP off LEAVE's ink, as the top card's timer does
        count, nleave = nodes.get(B + "NextRoundCard.Countdown"), nodes.get(B + "NextRoundCard.LeaveButton")
        if count and nleave and text_of(count) and nleave["w"] > 1 and self.rg is not None:
            ci, li = text_ink(count, self.rg, self.fonts), ink_of(nleave, None, None)
            if ci and li:
                d = ink_gap([ci], li, ci, union(li), MIN_GAP)[0]
                self.check(d >= MIN_GAP - 0.05, tag + "the next round's countdown keeps %g px off its LEAVE" % MIN_GAP,
                           "countdown %s, LEAVE %s: %.1f px" % (fmt(ci), fmt(union(li)), d))
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

    def fighter(self, tag, nodes):
        pre = B + "Team.Fighter."
        names = ["Body.PetName", "Body.Level", "Body.Element", "Body.Stars.LeadIcon", "Body.Hp", "Body.HpText", "Body.Energy",
                 "Body.EnergyText", "Body.Lives", "Lip"]
        # (keys look r4: the hearts' 16 px pixel art in their 14.4 px Lives box ran onto the element badge's frame below:
        # the boxes were apart, the inks touched) each part's ink (its subtree: the hearts' cells, the badge's frame), and
        # PART_GAP px of air between any two; the lip is a box (the card's foot), the others what they paint
        # A bare caption (the name, ENERGY, the HP number) is measured by its text block, a line as tall as its size with
        # the letters inside it: that block may touch a neighbour, not lie on it
        parts = []
        for p in names:
            n = nodes.get(pre + p)
            if not n or n["w"] <= 1 or n["h"] <= 1:
                continue
            if p == "Lip":
                ink, bare = [rect(n)], False
            else:
                ink = ink_of(n, None, None)  # (what it paints but its text)
                bare = not ink
                if bare:
                    ink = ink_of(n, self.rg, self.fonts)
            if ink:
                parts.append((p, ink, union(ink), bare))
        for i in range(len(parts)):
            for k in range(i + 1, len(parts)):
                (pi, li, ui, bi), (pk, lk, uk, bk) = parts[i], parts[k]
                need = 0.0 if (bi or bk) else PART_GAP
                d, a, b = ink_gap(li, lk, ui, uk, need)
                self.check(d >= need - 0.05, tag + "the fighter card's %s and %s keep %g px apart" % (pi, pk, need),
                           "ink %s vs %s: %s" % (fmt1(a), fmt1(b), ("%.1f px apart" % d) if d >= 0 else ("%.1f px over" % -d)))

    def key_tags(self, tag, nodes):
        """(keys look r5 c05: at 1280 x 720 the one-line 'MARSHMALLOW STAMPEDE' tag pushed TARGET's tag 67 px left of its F
        key, a label for nothing, and the gap rules passed) a PC key's name tag hangs under its own key: the tag spans the
        key's centre (06 A: every tag under its key)"""
        pat = re.compile(r"^NimbusBattle\.Root\.Commands\.(\w+Button)\.NamePlate$")
        for path, n in nodes.items():
            m = pat.match(path)
            key = nodes.get(B + "Commands." + m.group(1)) if m else None
            if not key or n["w"] <= 1 or key["w"] <= 1 or float(n.get("bgT", 0)) >= 0.995:
                continue
            t, k = rect(n), rect(key)
            cx = (k[0] + k[2]) / 2.0
            self.check(t[0] - 0.5 <= cx <= t[2] + 0.5, tag + "%s hangs under its key" % path,
                       "tag x %.0f..%.0f, key x %.0f..%.0f (centre %.0f)" % (t[0], t[2], k[0], k[2], cx))

    def helpers(self, tag, w, h, nodes):
        """(keys look r5 c04: at 844 x 390, the approved 01b C's own size, the evolved fighter's card 3.2 px taller flipped both
        helpers to the short phone's cell, an arrows-only Swap beside the Lv tag, 'STONE SKIN' on one line in a two-line
        plate beside 'TIDE MEND' in a one-line one) at 844 x 390 each helper keeps 01b C's cell, evolved or not: the Lv tag,
        the name plate and the labelled Swap under each other; at every size a name plate as tall as two lines draws two"""
        for i in (1, 2):
            pre = B + "Team.Helpers.Helper%d." % i
            lv, buff, swap = nodes.get(pre + "Level"), nodes.get(pre + "Buff"), nodes.get(pre + "Swap")
            if not (lv and buff and swap) or swap["w"] <= 1 or buff["w"] <= 1:
                continue
            if (w, h) == (844, 390):
                lr, br, sr = rect(lv), rect(buff), rect(swap)
                st = text_of(swap)
                ok = bool(st and st["text"].strip()) and br[1] >= lr[3] - 0.5 and sr[1] >= br[3] - 0.5
                self.check(ok, tag + "helper %d keeps 01b C's cell: Lv, name, a labelled Swap under each other" % i,
                           "Lv %s, name %s, Swap %s '%s'" % (fmt(lr), fmt(br), fmt(sr), st["text"] if st else ""))
            t = text_of(buff)
            if t and self.rg is not None:
                pl, pr, pt, pb = (buff.get("pad") or [0, 0, 0, 0])[:4]
                aw, ah = float(buff["w"]) - pl - pr, float(buff["h"]) - pt - pb
                size, lines = self.rg.layout_text(self.fonts, t, aw, ah)
                line = size * float(t.get("lineHeight", 1) or 1)
                self.check(not (len(lines) == 1 and ah >= 2 * line - 0.5), tag + "helper %d's name plate is as tall as its lines" % i,
                           "'%s' on %d line(s) of %.1f px in a %.1f px plate" % (t["text"], len(lines), line, ah))

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
        if w >= 1000:
            self.check(len(order) == 1, tag + "the pills sit in one row beside the head's slot (spec 06 A's PC frame)", names)
        if h > w:
            self.check(len(order) <= 2, tag + "the pills take at most two rows (spec 06 A: a portrait card wraps them to a second row)", names)
        if (w, h) == (390, 844):
            # (the look's 390 x 844 rule; at 360 x 640 the strip's row 1 has no room for the RAID tag, the name, the tier, the
            # timer and Leave: its tier is the second pill row's, beside the players)
            tiers = [p for p, _ in pills if p.split(".")[-1].lower().startswith("tier")]
            self.check(not tiers, tag + "the tier sits beside the boss name, not as a pill", ", ".join(tiers))
        if len(order) > 1:
            # (keys look r3: this held only for PC, the wide phone and portrait; at 640 x 360 the full raid's card in the gap
            # took 4 rows, "Enraged" and "Starter" each alone, 219 x 188 px = 52 % of the height) every size: no pill alone on
            # a row (the pills take the order that keeps them in pairs where the plain order leaves one alone)
            lone = [" ".join(x.split(".")[-1] for x in row) for row in order if len(row) < 2]
            self.check(not lone, tag + "no pill alone on a row", names)
        card = nodes.get(B + "TopCard")
        if card and h < w and min(w, h) <= 500:
            # (keys look r3: review r2 flagged a 48 % top card at 360 wide; 640 x 360's was 52 %) a landscape phone's top card
            # stays under 45 % of the screen's height
            ch = float(card["h"])
            self.check(ch <= 0.45 * h + 0.5, tag + "the top card stays under 45 % of the screen's height", "%.0f px = %.0f %%" % (ch, 100.0 * ch / h))
        enr = nodes.get(pre + "Enraged")
        t = text_of(enr) if enr else None
        if t:
            self.check(t["text"].strip() == "Enraged", tag + "the enrage pill reads 'Enraged' as the mock-up, not in capitals", repr(t["text"]))
        if w >= 1000:
            slot = [p for p in nodes if p.startswith(B + "TopCard.") and re.search(r"(BossHead|Portrait)\w*$", p)]
            self.check(bool(slot), tag + "the boss portrait's slot is kept (the head, or its fallback before the upload)")


def fmt(r):
    return "%.0f,%.0f-%.0f,%.0f" % r


def fmt1(r):
    return "%.1f,%.1f-%.1f,%.1f" % r


def parse_sizes(text):
    out = []
    for part in text.split(","):
        a, b = part.lower().split("x")
        out.append((int(a), int(b)))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--size", help="WxH[,WxH...] (default: all seven)")
    ap.add_argument("--scenario", help="S[,S...] (default: all eleven)")
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
        extra = [] if args.size else [s for s in SCENARIO_SIZES.get(scen, []) if s not in sizes]
        for (w, h) in list(sizes) + extra:
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
