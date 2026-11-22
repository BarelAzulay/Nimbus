#!/usr/bin/env python3
"""look_pins: every major the kit-b Pitch 2 look reviews found, pinned as an automated check (fix6).

    py -3.12 tools/look_pins.py [--pin ID[,ID...]] [--size WxH[,WxH...]] [-v] [--json FILE] [--list]

Each pin dumps the REAL client through tools/render_gui.py (tools/dump_gui.lua in the Roblox mock, the real font
metrics; a touch device when the screen's short side is <= 500 px, as the reviews rendered it) and measures what the
reviewer saw, at the eleven gate sizes (SIZES) plus the sizes the review named. The world guide's pins (the walk and the
slow pan) live in tools/smoke_kitb_world.lua's `guide_pins` (smoke list), which shares travel_guide_walk's camera walk.

Pins (the review, its major; RED until fixed, then GREEN for good):
  K1  keys pol1 #1  640 x 360 raid / raid:full / raid:ready: the boss name cut to 'Storm T...' (46fe5ef's wider gapL
                    sent BattleController's timer loop through with the 22 px timer). Rule: the top card's boss name is
                    the boss's whole name (no '...' the game wrote, no ellipsis the renderer draws, no line past its box)
  K2  keys pol1 #2  1280 x 720 dungeon:run: the run card lost its party row (ab11837's taller list tripped R.fitCard).
                    Rule: wherever the run CARD shows (not the chip), its party row (Members) shows
  I1  icons pol1 #1 landscape phones 720-960 wide: the roulette machines drawn at 1 px cells (the stage of a narrow phone
                    card too small for the 2 px drawing); the x3 coin over its number. Rule: every machine's art at >= 2
                    screen px a cell (a whole number); the x3 / gem planks' icon ink off their words' boxes
  I2  icons pol1 #2 tablets 1024 x 768 (touch and desktop), 1180 x 820, 1366 x 1024: the Secret hero's title, odds,
                    altar / pity chip and hint cut, an odds entry under the button, the padlock outside its chip. Rule:
                    every text of the hero whole, the odds and chips clear of the button, the chip's padlock inside it
  H1  icons fin1    390 x 844 sheets: the hero hint cut ('Travel flies you to the St...', 'Secret rolls happen at th...').
                    Rule: the hero's hint whole in each state (away, in the lobby, at the altar, restricted) on a phone
  C1  keys fin1 c01 phones, evolved fighter: heart 1's tip on the element badge's frame. Rule: battle_hud_no_overlap's
                    fighter-part rule (PART_GAP of ink between the card's own parts)
  C2  keys fin1 c02 dungeon:run, landscape phones: the Leave chip glued to the enemy list (the bracket on its frame), the
                    LeaveHit pad in the bracket. Rule: the run chip's ink RUNCHIP_GAP off every enemy row and '+n more',
                    its LeaveHit pad on no part
  C5  keys fin1 c05 360 x 640: the currency strip's border on helper 2's Lv tag, the chip under the strip, the bracket on
                    the Swaps, the top card's shadow on the fighter card and the strip. Rule: battle_hud_no_overlap's ink
                    gap (MIN_GAP, the run chip RUNCHIP_GAP) between the top card, the enemy rows, the fighter card, the
                    helpers, the run chip and the currency strips
Exit 0 when every pin passes. --list prints the pins and what they check.
"""
import argparse
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

SIZES = [(360, 640), (640, 360), (667, 375), (720, 405), (800, 450), (844, 390), (960, 540), (390, 844), (1024, 768),
         (1280, 720), (1920, 1080)]
# the sizes the reviews named beyond the eleven (I1: the common Android class, iPhone X / 11 Pro, the Pro Max; I2: the
# iPad Air and the iPad Pro, and 1024 x 768 with touch as an iPad renders it)
I1_EXTRA = [(800, 360), (812, 375), (932, 430)]
I2_EXTRA = [(1024, 768, True), (1180, 820, None), (1366, 1024, None)]

PINS = ["K1", "K2", "I1", "I2", "H1", "C1", "C2", "C5"]
NEW = {"K1", "K2", "I1", "I2"}  # (the 6 open majors at kit-b 1a55f73; W1 / W2 are guide_pins' in the smoke)

SHOP = "NimbusShop.ShopWindow.Body.Page_Eggs.Scroll."
HERO = SHOP + "ShopCard_Secret"
# the hero's states: the plain shop (away from the altar), in the lobby, at the altar, a restricted account
HERO_STATES = ["shop", "shop_secret_locked:lobby", "shop_secret_altar", "shop:restricted"]


def rect(n):
    return (float(n["x"]), float(n["y"]), float(n["x"]) + float(n["w"]), float(n["y"]) + float(n["h"]))


def fmt(r):
    return "%.1f,%.1f-%.1f,%.1f" % tuple(r)


class Ctx:
    """the dumps, one per (scenario, size, touch, sheets), and the checks"""

    def __init__(self, verbose):
        os.chdir(ROOT)
        import render_gui as RG
        import battle_hud_no_overlap as BH
        self.RG, self.BH = RG, BH
        self.fonts = RG.FontBook()
        self.cache = {}
        self.verbose = verbose
        self.passed, self.failed = {}, {}

    def dump(self, scen, w, h, touch=None, sheets=False):
        t = self.RG.is_touch(w, h, touch)
        key = (scen, w, h, t, sheets)
        if key not in self.cache:
            try:
                d = self.RG.dump_scenario(scen, w, h, t, self.fonts, sheets=sheets)
            except SystemExit as exc:
                d = {"guis": [], "errors": [str(exc)]}
            self.cache[key] = d
        return self.cache[key]

    def check(self, pin, ok, what, detail=""):
        if ok:
            self.passed[pin] = self.passed.get(pin, 0) + 1
        else:
            self.failed.setdefault(pin, []).append("%s  -- %s" % (what, detail) if detail else what)
        return ok

    def nodes(self, d):
        return self.BH.nodes_of(d)

    def whole(self, n):
        """(whole?, how it is drawn): the label's text as the renderer lays it out in its box: no ellipsis it draws, no
        '...' the game wrote, no line wider than the box (a label that does not truncate runs past it), no line past the
        box's foot"""
        t = n.get("text")
        if not isinstance(t, dict) or not str(t.get("text", "")).strip():
            return True, ""
        label = str(t["text"])
        pl, pr, pt, pb = (n.get("pad") or [0, 0, 0, 0])[:4]
        aw, ah = float(n["w"]) - pl - pr, float(n["h"]) - pt - pb
        size, lines = self.RG.layout_text(self.fonts, t, aw, ah)
        drawn = ["".join(c for c, _ in line) for line in lines]
        font = t.get("font", "SourceSans")
        wide = max([self.fonts.width(font, d, size) for d in drawn] or [0])
        cut = any("…" in d for d in drawn) and "…" not in label
        dots = label.rstrip().endswith("...")
        over = wide > aw + 0.6
        tall = len(lines) * size * float(t.get("lineHeight", 1) or 1) > ah + 1.0
        ok = not (cut or dots or over or tall)
        return ok, "'%s' drawn %s in %.1f x %.1f at %.1f px%s%s%s%s" % (
            label.replace("\n", " / "), " / ".join(repr(d) for d in drawn), aw, ah, size,
            " (ellipsis)" if cut else "", " (the game cut it: '...')" if dots else "",
            " (%.1f px past the box)" % (wide - aw) if over else "", " (past the foot)" if tall else "")


# ---------------------------------------------------------------------------------------------------------------- K1
def pin_K1(c, sizes):
    B = "NimbusBattle.Root.TopCard."
    for scen in ("battle:raid", "battle:raid:full", "battle:raid:ready"):
        for (w, h) in sizes:
            d = c.dump(scen, w, h)
            nodes = c.nodes(d)
            names = [(p, n) for p, n in nodes.items() if p.startswith(B) and p.endswith("BossName")]
            if not c.check("K1", bool(names), "K1 %s %dx%d: the top card shows the boss name" % (scen, w, h)):
                continue
            for p, n in names:
                ok, how = c.whole(n)
                c.check("K1", ok, "K1 %s %dx%d: the boss name is whole" % (scen, w, h), how)


# ---------------------------------------------------------------------------------------------------------------- K2
def pin_K2(c, sizes):
    R = "NimbusDungeonRun.RunCard"
    for (w, h) in sizes:
        d = c.dump("dungeon:run", w, h)
        nodes = c.nodes(d)
        if R not in nodes:
            c.check("K2", True, "K2 dungeon:run %dx%d: (the chip form, no card)" % (w, h))
            continue
        lines = [p.split(".")[-1] for p in nodes if p.startswith(R + ".Body.List.") and p.count(".") == 4]
        c.check("K2", R + ".Body.List.Members" in nodes, "K2 dungeon:run %dx%d: the run card keeps its party row" % (w, h),
                "the card shows %s; card %s, keys from y %s" % (", ".join(lines), fmt(rect(nodes[R])),
                                                               "%.0f" % rect(nodes["NimbusBattle.Root.Commands"])[1] if "NimbusBattle.Root.Commands" in nodes else "?"))


# ---------------------------------------------------------------------------------------------------------------- I1
def cell_widths():
    with open(os.path.join(ROOT, "build", "upload_sheets", "machines_a.json"), encoding="utf-8") as fh:
        m = json.load(fh)
    return {k: (v["w"], v["h"]) for k, v in m["cells"].items()}


def pin_I1(c, sizes):
    cells = cell_widths()
    for (w, h) in sizes + I1_EXTRA:
        d = c.dump("shop_secret_locked:lobby", w, h, sheets=True)
        nodes = c.nodes(d)
        arts = [(p, n) for p, n in nodes.items() if re.search(r"ShopCard_(\w+)\.Body\.Machine\.Art$", p)]
        if not c.check("I1", bool(arts), "I1 %dx%d: the Eggs page draws its machines" % (w, h)):
            continue
        small = []
        for p, n in arts:
            mid = re.search(r"ShopCard_(\w+)\.Body\.Machine\.Art$", p).group(1)
            cw, ch = cells.get(mid, (None, None))
            if not cw:
                continue
            px = float(n["w"]) / cw
            if px < 2 - 0.01 or abs(px - round(px)) > 0.02:
                small.append("%s %.0f x %.0f = %.2f px a cell" % (mid, float(n["w"]), float(n["h"]), px))
        c.check("I1", not small, "I1 %dx%d: every machine at 2 screen px a cell or more (whole)" % (w, h), "; ".join(small))
        # the x3 / gem planks: the coin's / gem's ink 1 px clear of the words beside it (932 x 430: 'x3 coin 750')
        for p, n in nodes.items():
            m = re.search(r"\.Body\.(Spin3|SpinGems|Spin)$", p)
            if not m:
                continue
            icons = [q for q in nodes if q.startswith(p + ".") and re.search(r"\.(TokenIcon|GemIcon|Icon)$", q) and q.count(".") == p.count(".") + 1]
            words = [q for q in nodes if q.startswith(p + ".") and q.count(".") == p.count(".") + 1 and nodes[q].get("text") and str(nodes[q]["text"].get("text", "")).strip()]
            for ip in icons:
                ink = c.BH.ink_of(nodes[ip], None, None)
                if not ink:
                    continue
                for wp in words:
                    ti = c.BH.text_ink(nodes[wp], c.RG, c.fonts)
                    if not ti:
                        continue
                    # (the word's block is its advance box: the glyphs' side bearings lie inside it, so a box the icon
                    # touches leaves the letters apart; 844 x 390, the review's "ok" frame, keeps 0.2 px; 932 x 430's
                    # coin lay 0.8 px into 'x3')
                    gap = min(c.BH.gap(r, ti) for r in ink)
                    c.check("I1", gap >= -0.05, "I1 %dx%d: %s's icon stays off its '%s'" % (w, h, p.replace(SHOP, ""), nodes[wp]["text"]["text"]),
                            "icon ink %s, text %s: %.1f px" % (fmt(c.BH.union(ink)), fmt(ti), gap))


# ---------------------------------------------------------------------------------------------------------------- I2 / H1
def hero_texts(nodes):
    out = []
    for p, n in nodes.items():
        if p.startswith(HERO + ".") and isinstance(n.get("text"), dict) and str(n["text"].get("text", "")).strip():
            if float(n["text"].get("t", 0)) >= 0.99:
                continue
            out.append((p, n))
    return out


def pin_I2(c, sizes):
    runs = [(w, h, None) for (w, h) in sizes] + I2_EXTRA
    for scen in HERO_STATES:
        for sheets in (True, False):
            for (w, h, touch) in runs:
                d = c.dump(scen, w, h, touch, sheets)
                nodes = c.nodes(d)
                tag = "I2 %s %s %dx%d%s" % (scen, "sheets" if sheets else "fallback", w, h, " touch" if touch else "")
                if not c.check("I2", HERO in nodes, tag + ": the Secret hero shows"):
                    continue
                for p, n in hero_texts(nodes):
                    ok, how = c.whole(n)
                    c.check("I2", ok, tag + ": %s is whole" % p.replace(SHOP, ""), how)
                # the odds rows and the chips clear of the button (its holder)
                hold = nodes.get(HERO + ".Body.SpinHolder")
                if hold:
                    hr = rect(hold)
                    for p, n in nodes.items():
                        if re.match(re.escape(HERO) + r"\.Body\.(OddsLine\.Odds_\w+|AltarChip|Pity|Lock|Title|GemsOnly)$", p):
                            ink = c.BH.ink_of(n, c.RG, c.fonts)
                            if not ink:
                                continue
                            g = min(c.BH.gap(r, hr) for r in ink)
                            c.check("I2", g >= 0, tag + ": %s keeps off the button" % p.replace(SHOP, ""), "%s vs %s: %.1f px" % (fmt(c.BH.union(ink)), fmt(hr), g))
                # a chip's padlock / lead icon inside its chip
                for chip in ("AltarChip", "Pity", "Lock"):
                    cn = nodes.get(HERO + ".Body." + chip)
                    ic = nodes.get(HERO + ".Body." + chip + ".LeadIcon")
                    if cn and ic:
                        a, b = rect(cn), rect(ic)
                        inside = b[0] >= a[0] - 0.5 and b[2] <= a[2] + 0.5 and b[1] >= a[1] - 0.5 and b[3] <= a[3] + 0.5
                        c.check("I2", inside, tag + ": the %s's icon sits inside it" % chip, "icon %s, chip %s" % (fmt(b), fmt(a)))


def pin_H1(c, sizes):
    phones = [(w, h) for (w, h) in sizes if min(w, h) <= 500]
    for scen in HERO_STATES:
        for (w, h) in phones:
            d = c.dump(scen, w, h, None, True)
            nodes = c.nodes(d)
            hint = nodes.get(HERO + ".Body.Hint")
            if not hint:
                c.check("H1", True, "H1 %s %dx%d: (no hint on this card)" % (scen, w, h))
                continue
            ok, how = c.whole(hint)
            c.check("H1", ok, "H1 %s sheets %dx%d: the hero's hint is whole" % (scen, w, h), how)


# ---------------------------------------------------------------------------------------------------------------- C1 / C2 / C5
class Collect:
    """battle_hud_no_overlap's Checker, its failures kept for the pin to sort"""

    def __init__(self, c):
        self.c = c
        self.ck = c.BH.Checker(c.RG, c.fonts)

    def run(self, scen, w, h, d):
        self.ck.passed, self.ck.failed = 0, []
        self.ck.run(scen, w, h, d)
        return self.ck.passed, list(self.ck.failed)


def pin_C1(c, sizes):
    col = Collect(c)
    for scen in ("battle:raid", "battle:dungeon", "battle:duel", "dungeon:run"):
        for (w, h) in sizes:
            d = c.dump(scen, w, h)
            col.ck.passed, col.ck.failed = 0, []
            col.ck.fighter("%s %dx%d: " % (scen, w, h), c.nodes(d))
            c.passed["C1"] = c.passed.get("C1", 0) + col.ck.passed
            for f in col.ck.failed:
                c.check("C1", False, "C1 " + f)


C2_PAT = re.compile(r"(RunChip\S* and \S*Enemies|Enemies\S* and \S*RunChip|run chip's LeaveHit stays off)")
C5_GROUPS = ("TopCard", "LeaveButton", "Enemies", "Team.Fighter", "Team.Helpers", "RunChip", "Currency")


def pin_C2(c, sizes):
    col = Collect(c)
    for (w, h) in sizes:
        d = c.dump("dungeon:run", w, h)
        n, fails = col.run("dungeon:run", w, h, d)
        mine = [f for f in fails if C2_PAT.search(f)]
        c.check("C2", not mine, "C2 dungeon:run %dx%d: the run chip keeps 6 px off the enemy list, its LeaveHit on no part" % (w, h), " | ".join(mine[:3]))


def pin_C5(c, sizes):
    col = Collect(c)
    pat = re.compile(r"^(\S+) %dx%d: (\S+) and (\S+) keep (\d+) px apart")
    for scen in ("battle:raid", "battle:raid:full", "battle:dungeon", "dungeon:run"):
        for (w, h) in sizes:
            d = c.dump(scen, w, h)
            n, fails = col.run(scen, w, h, d)
            mine = []
            for f in fails:
                m = re.match(r"^\S+ \d+x\d+: (\S+) and (\S+) keep [\d.]+ px apart", f)
                if m and all(any(g in p for g in C5_GROUPS) for p in (m.group(1), m.group(2))):
                    mine.append(f)
            c.check("C5", not mine, "C5 %s %dx%d: the cards, rows, helpers, run chip and currency strips keep their ink gap" % (scen, w, h), " | ".join(mine[:3]))


RUN = {"K1": pin_K1, "K2": pin_K2, "I1": pin_I1, "I2": pin_I2, "H1": pin_H1, "C1": pin_C1, "C2": pin_C2, "C5": pin_C5}


def parse_sizes(text):
    return [tuple(int(v) for v in part.lower().split("x")) for part in text.split(",")]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--pin", help="ID[,ID...] (default: all)")
    ap.add_argument("--size", help="WxH[,WxH...] (default: the eleven gate sizes)")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--json", help="write {pin: [failures]} as JSON")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        print(__doc__)
        return 0
    pins = args.pin.split(",") if args.pin else PINS
    sizes = parse_sizes(args.size) if args.size else SIZES
    c = Ctx(args.verbose)
    t0 = time.time()
    for p in pins:
        t1 = time.time()
        RUN[p](c, sizes)
        nf = len(c.failed.get(p, []))
        print("pin %-3s %-6s %5d passed, %4d failed  (%.0fs)" % (p, "RED" if nf else "GREEN", c.passed.get(p, 0), nf, time.time() - t1), flush=True)
        for f in c.failed.get(p, [])[: (10_000 if args.verbose else 12)]:
            print("    FAIL  " + f)
        if nf > 12 and not args.verbose:
            print("    ... %d more (-v)" % (nf - 12))
        if p != "I2":  # (H1 reads I2's sheets dumps; the rest are let go: a dump is a few MB)
            c.cache.clear()
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump({"passed": c.passed, "failed": c.failed}, fh, indent=1)
    red = [p for p in pins if c.failed.get(p)]
    print("look_pins: %d pins, %d green, %d red%s  (%.0fs)" % (len(pins), len(pins) - len(red), len(red), (" (" + ", ".join(red) + ")") if red else "", time.time() - t0))
    return 1 if red else 0


if __name__ == "__main__":
    sys.exit(main())
