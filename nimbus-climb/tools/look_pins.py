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
                    helpers, the run chip and the currency strips (fix6 look0 #2 / #3b: raid:ready and duel too; 1024 x 768
                    put the top card on the fighter card in every mode, 960 x 540 the token strip on the target row)
  Q1  fix6 look0 #3a 960 x 540: the '1' / '2' key caps on the 38 px helper tiles hid the cooldown count and 'KO'. Rule: a
                    helper's key cap keeps 1 px of ink off its count and KO text blocks
  E1  fix6 look0 #3c 960 x 540 dungeon:end / :wipe: the end card 56 px over the vitals card ('100 / 100' cut). Rule:
                    battle_hud_no_overlap's ink gap between the end card and every part it lists
  D1  fix6 look0 #6 1024 x 768 Daily: the header 88 px past its box under the Streak chip, '$1.45K' read '$1.4...', 'TODAY'
                    1.4 px past its box. Rule: the Daily page's header, chips and day tiles' names and amounts whole
  O1  fix6 look1 #4 720 x 405 / 700 x 394: helper tags 'STONE SK...', 'TIDE MEN...'. Rule: battle_hud_no_overlap's 'is
                    whole' for the helpers' tags, at the gate sizes and 700 x 394
  O2  fix6 look1 #5 2560 x 1440, 3440 x 1440, 3840 x 2160: the enemy list on the currency strips; 'TARGET' 3.4-3.9 px past
                    its box from 1920 x 1200 up. Rule: the rows keep the ink gap off the strips; the TARGET tab reads whole
  O3  fix6 look1 #6 lobby 360 x 640 / 375 x 667: the vitals card on DASH and RUN, its name 'SkyCli...'. Rule: the card's
                    ink MIN_GAP off DASH and RUN, the player's name whole. (look:fix6b2 N2: 'SkyCli...' at 800 x 450 in a
                    match / countdown) in every state the card shows in: lobby, match, the pad, the countdown (O3_BACKLOG:
                    kit-b's own cases on landscape phones, no worse than kit-b)
  T1  fix6 look1   the raid timer in three places on one phone (Shadow Hydra), no clock and larger than the name at
                    1024 x 768 raid:full. Rule: a phone's timer one place and form through raid:ready / raid / raid:full;
                    the clock at 1024 x 768 raid:full; the timer never larger than the boss name
  U1  look:fix6b #1 360 x 640 / 375 x 667 / 384 x 640 tutorial steps 1, 3, 6: the folded quest strip 58 x 22 px over RUN
                    (from O3). Rule: at every step, as the game shows it, the tutorial's ink MIN_GAP off RUN, DASH, the
                    vitals card and Roblox's thumbstick and jump rings, at the gate sizes and the phones. (look:fix6b2 N1:
                    the portrait chip under the menu's Home tile in a 3-4 player match / on a full pad) and over a match
                    (1-4 players), the party pad and the countdown: MIN_GAP off EVERY other HUD piece and the rings, plus a
                    portrait sweep 320-430 x 568 / 640 / 720 (U1_BACKLOG: kit-b's own cases, no worse than kit-b)
  U2  look:fix6b2 N3 360 x 640 step 20 'The Champion Ri...' (the title not shrunk before the ellipsis). Rule: the
                    tutorial's titles (the strip's, the card's as shown and opened) read whole at every step (U2_BACKLOG:
                    kit-b's own cuts at the 14.4 px floor). (kit-b backlog item 10) the card's objective line too: every
                    line it wraps to inside its box
  U3  kit-b backlog item 6, 360 x 640 / 384 x 640 (all 21 steps), 375 x 667 (18 of 21): a tap on the folded tutorial
                    opened no card, so its Next and Skip were out of reach. Rule: at every step the card the player opens
                    (tutorial:<n>:open) shows, its Skip link and its Next (where the step has one) whole on the screen, its
                    ink MIN_GAP off RUN, DASH and the stick and jump rings, on the short portrait phones, the portrait
                    sweep 320-430 x 568 / 640 / 720 and the tall phones that open it today
  B0-B3 the owner's pick B of 2026-11-23, the guide chip ("Top-bar plank", X on the right): over every HUD state it
                    can meet (guidechip:<state>) at sixteen sizes 320 x 568 .. 2560 x 1440: B0 its home (the top band's
                    right end beside '...', a portrait phone's vitals stack 8 px over the name plank / the quest strip),
                    wholly on the screen 8 px in from its sides, B1 its ink MIN_GAP off every other HUD piece, Roblox's
                    buttons and rings (a match: no chip; a dungeon party's chip in its spot: hidden), B2 its X
                    a 44 px hit box 16 px or more off '...', B3 its words whole, >= 14.4 px on a phone, the place and its
                    distance. (Its frame-by-frame rules - one rect on every camera move, the needle - are guide_pins')
  (K1 also walks every raid boss since look0 #1: 'Shadow H...' at 640 x 360 while the pin read Storm Titan alone)
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

PINS = ["K1", "K2", "I1", "I2", "H1", "C1", "C2", "C5", "Q1", "E1", "D1", "O1", "O2", "O3", "T1", "U1", "U2", "U3", "B0", "B1", "B2", "B3"]
NEW = {"K1", "K2", "I1", "I2"}  # (the 6 open majors at kit-b 1a55f73; W1 / W2 are guide_pins' in the smoke)

SHOP = "NimbusShop.ShopWindow.Body.Page_Eggs.Scroll."
HERO = SHOP + "ShopCard_Secret"
# the hero's states: the plain shop (away from the altar), in the lobby, at the altar, a restricted account
HERO_STATES = ["shop", "shop_secret_locked:lobby", "shop_secret_altar", "shop:restricted"]


def kitb_backlog(pin):
    """(look:fix6b2) tools/fixtures/look_pins_backlog_kitb.json's rows for a pin: {(scenario, w, h, part): kit-b's value}"""
    with open(os.path.join(HERE, "fixtures", "look_pins_backlog_kitb.json"), encoding="utf-8") as fh:
        rows = json.load(fh).get(pin, [])
    return {(r[0], int(r[1]), int(r[2]), r[3]): r[4] for r in rows}


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

    def dump(self, scen, w, h, touch=None, sheets=False, boss=None):
        t = self.RG.is_touch(w, h, touch)
        key = (scen, w, h, t, sheets, boss)
        if key not in self.cache:
            try:
                d = self.RG.dump_scenario(scen, w, h, t, self.fonts, sheets=sheets, boss=boss)
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
# (fix6 look0 #1: K1 read Storm Titan alone and stayed green while 640 x 360 cut 'Shadow H...') every raid boss, in
# BattleCatalog.BossOrder: storm_titan, lava_golem, frost_wyrm, shadow_hydra (the longest name)
K1_BOSSES = ["storm_titan", "lava_golem", "frost_wyrm", "shadow_hydra"]


def pin_K1(c, sizes):
    B = "NimbusBattle.Root.TopCard."
    for boss in K1_BOSSES:
        for scen in ("battle:raid", "battle:raid:full", "battle:raid:ready"):
            for (w, h) in sizes:
                d = c.dump(scen, w, h, boss=boss)
                nodes = c.nodes(d)
                names = [(p, n) for p, n in nodes.items() if p.startswith(B) and p.endswith("BossName")]
                if not c.check("K1", bool(names), "K1 %s %s %dx%d: the top card shows the boss name" % (boss, scen, w, h)):
                    continue
                for p, n in names:
                    ok, how = c.whole(n)
                    c.check("K1", ok, "K1 %s %s %dx%d: the boss name is whole" % (boss, scen, w, h), how)
            c.cache.clear()  # (a dump is a few MB; 132 a boss)


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


# (fix6 look0 #2: at 1024 x 768 the top card lay on the fighter card in EVERY battle mode, raid:ready and duel too, which
# C5 did not dump) the five battle modes and the run
C5_SCENES = ("battle:raid", "battle:raid:full", "battle:raid:ready", "battle:dungeon", "battle:duel", "dungeon:run")


def pin_C5(c, sizes):
    col = Collect(c)
    for scen in C5_SCENES:
        for (w, h) in sizes:
            d = c.dump(scen, w, h)
            n, fails = col.run(scen, w, h, d)
            mine = []
            for f in fails:
                m = re.match(r"^\S+ \d+x\d+: (\S+) and (\S+) keep [\d.]+ px apart", f)
                if m and all(any(g in p for g in C5_GROUPS) for p in (m.group(1), m.group(2))):
                    mine.append(f)
            c.check("C5", not mine, "C5 %s %dx%d: the cards, rows, helpers, run chip and currency strips keep their ink gap" % (scen, w, h), " | ".join(mine[:3]))


# ---------------------------------------------------------------------------------------------------------------- Q1 / E1
BH_SCENES = ("battle:raid", "battle:raid:full", "battle:raid:ready", "battle:dungeon", "battle:duel", "dungeon:run",
             "dungeon:end", "dungeon:wipe")


def pin_Q1(c, sizes):
    """fix6 look0 #3a: a helper's key cap ('1' / '2', a keyboard's) keeps 1 px of air off its tile's cooldown count and
    'KO' (their text blocks as render_gui lays them out); 960 x 540's 24 x 19 px caps hid both on the 38 px tiles"""
    for scen in BH_SCENES:
        for (w, h) in sizes:
            nodes = c.nodes(c.dump(scen, w, h))
            caps = 0
            for i in (1, 2):
                base = "NimbusBattle.Root.Team.Helpers.Helper%d" % i
                key = nodes.get(base + ".Key")
                if not key:
                    continue
                kink = c.BH.ink_of(key, c.RG, c.fonts)
                if not kink:
                    continue
                caps += 1
                for part in ("Count", "KO"):
                    tn = nodes.get(base + ".Disc.Portrait." + part)
                    ti = tn and c.BH.text_ink(tn, c.RG, c.fonts)
                    if not ti:
                        continue
                    g = min(c.BH.gap(r, ti) for r in kink)
                    c.check("Q1", g >= 1.0, "Q1 %s %dx%d: helper %d's key cap keeps off its '%s'" % (scen, w, h, i, tn["text"]["text"]),
                            "cap ink %s, text %s: %.1f px" % (fmt(c.BH.union(kink)), fmt(ti), g))
            if not caps:
                c.check("Q1", True, "Q1 %s %dx%d: (no key caps: a touch screen or no helpers)" % (scen, w, h))


def pin_E1(c, sizes):
    """fix6 look0 #3c: the dungeon's end / wipe card keeps battle_hud_no_overlap's ink gap from the vitals card and the
    currency strips (960 x 540: the end card 56 px over the vitals card, '100 / 100' cut to '100 /')"""
    col = Collect(c)
    for scen in ("dungeon:end", "dungeon:wipe"):
        for (w, h) in sizes:
            d = c.dump(scen, w, h)
            n, fails = col.run(scen, w, h, d)
            mine = [f for f in fails if "EndCard" in f and " keep " in f]
            c.check("E1", not mine, "E1 %s %dx%d: the end card keeps its ink gap" % (scen, w, h), " | ".join(mine[:3]))


# ---------------------------------------------------------------------------------------------------------------- D1
DAILY = "NimbusDaily.DailyHolder.DailyWindow.Body.DailyPage."


def pin_D1(c, sizes):
    """fix6 look0 #6: the Daily page's texts whole (1024 x 768: the header 88 px past its box under the Streak chip,
    today's '$1.45K' read '$1.4...', 'TODAY' 1.4 px past its box): the header, the chips and every day tile's name and
    amount, as render_gui lays them out (c.whole: no ellipsis, no '...', no line past its box)"""
    for scen in ("daily", "daily:week", "daily:locked"):
        for (w, h) in sizes:
            nodes = c.nodes(c.dump(scen, w, h))
            texts = [(p, n) for p, n in nodes.items()
                     if re.match(re.escape(DAILY) + r"(Header|StreakChip|VipChip|Cells\.Cell[1-6]\.Body\.(Day|Amount))$", p)
                     and isinstance(n.get("text"), dict) and str(n["text"].get("text", "")).strip()]
            if not c.check("D1", bool(texts), "D1 %s %dx%d: the Daily page shows its header and tiles" % (scen, w, h)):
                continue
            for p, n in texts:
                ok, how = c.whole(n)
                c.check("D1", ok, "D1 %s %dx%d: %s is whole" % (scen, w, h, p.replace(DAILY, "")), how)


# ---------------------------------------------------------------------------------------------------------------- O1
# (fix6b, look1 #4: 720 x 405 raid:full cut helper 1's 'STONE SKIN' to 'STONE SK...' in its 88 px plate; 700 x 394 cut
# 'STONE S...' and 'TIDE MEN...' in raid:full, 'TIDE MEN...' in dungeon:run) battle_hud_no_overlap's 'is whole' rule for
# the helpers' tags, at the gate sizes and 700 x 394
O1_SIZES = [(700, 394)]
O1_PAT = re.compile(r"Team\.Helpers\.Helper\d+\.\S+ '.*' is whole")


def pin_O1(c, sizes):
    col = Collect(c)
    for scen in ("battle:raid", "battle:raid:full", "battle:raid:ready", "battle:dungeon", "battle:duel", "dungeon:run"):
        for (w, h) in list(sizes) + [s for s in O1_SIZES if s not in sizes]:
            d = c.dump(scen, w, h)
            n, fails = col.run(scen, w, h, d)
            mine = [f for f in fails if O1_PAT.search(f)]
            c.check("O1", not mine, "O1 %s %dx%d: the helpers' tags read whole" % (scen, w, h), " | ".join(mine[:3]))


# ---------------------------------------------------------------------------------------------------------------- O2
# (fix6b, look1 #5: on screens 1440 px tall and up the enemy list lay on the currency strips - 2560 x 1440 battle:dungeon
# 33.5 px over the token strip, raid:full and duel 16.5 px, dungeon:run over all three; the 'TARGET' tab's text ran 3.4 -
# 3.9 px past its box from 1920 x 1200 up) the list's rows keep battle_hud_no_overlap's ink gap off the strips, and the
# locked row's 'TARGET' tab reads whole, at the big screens (and the gate sizes for the tab)
O2_BIG = [(1920, 1200), (2560, 1440), (3440, 1440), (3840, 2160)]
O2_SCENES = ("battle:dungeon", "battle:raid:full", "battle:duel", "dungeon:run")


def pin_O2(c, sizes):
    col = Collect(c)
    for scen in O2_SCENES:
        for (w, h) in O2_BIG + [s for s in sizes if s not in O2_BIG]:
            d = c.dump(scen, w, h)
            nodes = c.nodes(d)
            if (w, h) in O2_BIG:
                n, fails = col.run(scen, w, h, d)
                mine = []
                for f in fails:
                    m = re.match(r"^\S+ \d+x\d+: (\S+) and (\S+) keep [\d.]+ px apart", f)
                    pair = (m.group(1), m.group(2)) if m else ()
                    if any("Enemies" in p for p in pair) and any("Currency" in p for p in pair):
                        mine.append(f)
                c.check("O2", not mine, "O2 %s %dx%d: the enemy list keeps its ink gap off the currency strips" % (scen, w, h), " | ".join(mine[:3]))
            tabs = [(p, n) for p, n in nodes.items() if re.search(r"^NimbusBattle\.Root\.Enemies\.Row\d+\.Target$", p)]
            for p, n in tabs:
                ok, how = c.whole(n)
                c.check("O2", ok, "O2 %s %dx%d: %s reads whole in its box" % (scen, w, h, p.split(".")[-2] + ".Target"), how)


# ---------------------------------------------------------------------------------------------------------------- O3
# (fix6b, look1 #6, world pol1's minor: in the lobby at 360 x 640 and 375 x 667 the vitals card lay on DASH - 59 of its
# 66 px, its full height - and on RUN's foot, its name tab cut to 'SkyCli...') the vitals card (its name tab with it) keeps
# battle_hud_no_overlap's MIN_GAP of ink off the touch keys, and the player's name reads whole, at the gate sizes and
# 375 x 667
O3_SIZES = [(375, 667)]
# (look:fix6b2 N2, NEW from O3's 2947a7a: at 800 x 450 in a match and in a countdown the card's name read 'SkyCli...' -
# whole at e272588 / kit-b: the card keeps O3's 8 px of air plus its 2 px edge off the match panel and RUN's block edge,
# and the 211 px between them left it 190 px, short of the name at its 14.4 px floor. O3 read the lobby alone.) The same
# rule in every state the vitals card shows in: the lobby, a match (3 players; the long-name SAINT match), the party pad
# (2 players; its leader's full pad) and a match's countdown.
# O3_BACKLOG: what kit-b 1a55f73 already has there (the owner's rule of 2026-11-24), measured by this pin on kit-b's src: on
# landscape phones 640 - 720 wide in a match / on the pad / in the countdown the squeezed card lies on DASH and RUN and
# cuts the name (look:fix6b2's OLD major). Such a case passes while its key gap is no worse than kit-b's (a name kit-b
# cuts may stay cut there); every other case keeps MIN_GAP and the whole name.
O3_STATES = ["lobby", "match", "match:full", "party", "party:leader", "countdown"]
O3_BACKLOG = kitb_backlog("O3")


def pin_O3(c, sizes):
    for (w, h) in list(sizes) + [s for s in O3_SIZES if s not in sizes]:
        for scen in O3_STATES:
            nodes = c.nodes(c.dump(scen, w, h))
            vit = [(p, n) for p, n in nodes.items() if re.match(r"^NimbusHud\.\w+\.Vitals$", p)]
            if not c.check("O3", bool(vit), "O3 %s %dx%d: the vitals card shows" % (scen, w, h)):
                continue
            vp, vn = vit[0]
            ink = c.BH.ink_of(vn, c.RG, c.fonts)
            for key in ("DashButton", "RunButton"):
                kn = nodes.get("MobileControls." + key)
                if not kn or float(kn["w"]) <= 1:
                    continue
                kink = c.BH.ink_of(kn, c.RG, c.fonts)
                if not (ink and kink):
                    continue
                g = min(c.BH.gap(a, b) for a in ink for b in kink)
                was = O3_BACKLOG.get((scen, w, h, key))
                ok = g >= c.BH.MIN_GAP - 0.05 or (was is not None and g >= was - 0.05)
                c.check("O3", ok, "O3 %s %dx%d: the vitals card keeps %g px off %s" % (scen, w, h, c.BH.MIN_GAP, key),
                        "card ink %s, key %s: %.1f px%s" % (fmt(c.BH.union(ink)), fmt(c.BH.union(kink)), g, (" (kit-b %.1f)" % was) if was is not None else ""))
            for p, n in nodes.items():
                if p.startswith(vp + ".") and p.endswith("PlayerName"):
                    ok, how = c.whole(n)
                    c.check("O3", ok or (scen, w, h, "name") in O3_BACKLOG, "O3 %s %dx%d: the player's name reads whole on the vitals card" % (scen, w, h), how)
        c.cache.clear()


# ---------------------------------------------------------------------------------------------------------------- T1
# (fix6b, look1 minors 1 / 2 and the owner's pick of 2026-11-23: e272588 gave the raid timer three places on one phone -
# Shadow Hydra's bare at the card's foot in raid / raid:ready, inside the RAID pill in raid:full - dropped its clock at
# 1024 x 768 Hydra raid:full and drew it larger than the boss name there, as 640 / 667 / 800 drew 17.6 px timers beside
# 14.4 px names) for every raid boss: on a phone one place and one form for the whole fight (raid:ready, raid, raid:full
# the same: row 1, the pill rows or the RAID pill; clock or not); at 1024 x 768 the full raid's timer wears its clock;
# at every size the timer is never larger than the boss name
TIMER = "NimbusBattle.Root.TopCard.ModeCard.Body.Timer"
CLOCK = "NimbusBattle.Root.TopCard.ModeCard.Body.Clock"
RAIDPILL = "NimbusBattle.Root.TopCard.Pills.RaidPill"


def timer_form(nodes):
    """(where, clock, size): 'row1' (beside the boss name), 'pills' (under the track), 'pill' (the RAID pill reads the
    time) or 'none'"""
    name = next((n for p, n in nodes.items() if p.startswith("NimbusBattle.Root.TopCard.") and p.endswith("BossName")), None)
    t = nodes.get(TIMER)
    tt = t and t.get("text")
    rp = nodes.get(RAIDPILL)
    rpt = rp and rp.get("text")
    if isinstance(tt, dict) and str(tt.get("text", "")).strip():
        ny = (rect(name)[1] + rect(name)[3]) / 2 if name else None
        r = rect(t)
        where = "row1" if ny is not None and r[1] <= ny <= r[3] else "pills"
        return where, CLOCK in nodes, float(tt.get("size", 0)), name
    if isinstance(rpt, dict) and re.match(r"^\d+:\d\d$", str(rpt.get("text", "")).strip()):
        return "pill", CLOCK in nodes, float(rpt.get("size", 0)), name
    return "none", CLOCK in nodes, 0.0, name


def pin_T1(c, sizes):
    for boss in K1_BOSSES:
        for (w, h) in sizes:
            forms = {}
            for scen in ("battle:raid:ready", "battle:raid", "battle:raid:full"):
                nodes = c.nodes(c.dump(scen, w, h, boss=boss))
                where, clock, size, name = timer_form(nodes)
                forms[scen] = (where, clock)
                nt = name and name.get("text")
                if size > 0 and isinstance(nt, dict):
                    c.check("T1", size <= float(nt.get("size", 0)) + 0.05, "T1 %s %s %dx%d: the timer is never larger than the boss name" % (boss, scen, w, h),
                            "timer %.1f px (%s), name '%s' %.1f px" % (size, where, nt.get("text"), float(nt.get("size", 0))))
                if (w, h) == (1024, 768) and scen == "battle:raid:full":
                    c.check("T1", where != "none" and clock, "T1 %s %s %dx%d: the timer wears its clock" % (boss, scen, w, h), "%s, clock %s" % (where, clock))
            if c.RG.is_touch(w, h, None):
                c.check("T1", len(set(forms.values())) == 1, "T1 %s %dx%d: one place and one form for the timer the whole fight" % (boss, w, h),
                        ", ".join("%s %s%s" % (s.replace("battle:", ""), f[0], " +clock" if f[1] else "") for s, f in forms.items()))
            c.cache.clear()


# ---------------------------------------------------------------------------------------------------------------- U1
# (look:fix6b major 1, NEW from O3's 2947a7a: at 360 x 640, 375 x 667 and 384 x 640 the folded tutorial - the quest strip
# 'Hi there, climber! 1/21' - lay 58 x 22 px over RUN at steps 1, 3 and 6, hiding its icon: the vitals card moved left of
# RUN / DASH and below RUN's top, and the strip docks STRIP_DOCK_GAP over the card from its left edge to the RUN / DASH
# column's right edge, so it ran through RUN's row) at EVERY tutorial step, as the game shows it: the tutorial's ink keeps
# battle_hud_no_overlap's MIN_GAP off RUN, DASH, the vitals card and Roblox's thumbstick and jump rings, at the gate sizes
# and every phone size the reviews used.
# Not here: the card the player opens with a tap (tutorial:<n>:open; tutorial_fits_phone holds it over no thumb zone and
# no RUN / DASH at steps 1 and 5). Where it only fits at its 0.7 last resort or beside the keys, its window shadow (8
# design px past the box) comes 0 - 3 px near RUN, or over RUN's edge: 640 x 360 step 6, 667 x 375 steps 7 / 11 / 13 /
# 14 / 20 (1 px over), 700 x 394 steps 5 / 6 / 16 / 21 (4 px over RUN's corner), 375 x 667 steps 7 / 11 / 14. The same
# at 775923a (build/GATE_P2/tutfix/U1_red.txt), not from O3; reported to the look as a minor of its own
U1_EXTRA = [(320, 568), (375, 667), (384, 640), (393, 852), (412, 915), (430, 932), (568, 320), (700, 394), (740, 360),
            (800, 360), (812, 375), (932, 430)]
U1_PANEL = "NimbusTutorial.TutorialPanel"


def tutorial_total(nodes):
    """the step count the tutorial shows ('Step 1/21' on the card, '1/21' on the strip), None when it shows none"""
    for p, n in nodes.items():
        t = n.get("text")
        if p.startswith("NimbusTutorial.") and isinstance(t, dict):
            m = re.match(r"^\s*(?:Step\s+)?\d+\s*/\s*(\d+)\s*$", str(t.get("text", "")))
            if m:
                return int(m.group(1))
    return None


def pin_U1(c, sizes):
    # the step count as the PC card shows it (a phone's portrait chip shows none)
    total = tutorial_total(c.nodes(c.dump("tutorial:1", 1280, 720)))
    if not c.check("U1", total is not None and total > 1, "U1 tutorial 1280x720: the tutorial shows its step count"):
        return
    for (w, h) in list(sizes) + [s for s in U1_EXTRA if s not in sizes]:
        touch = c.RG.is_touch(w, h, None)
        for step in range(1, total + 1):
            scen = "tutorial:%d" % step
            nodes = c.nodes(c.dump(scen, w, h))
            what = "U1 %s %dx%d" % (scen, w, h)
            panel = nodes.get(U1_PANEL)
            ink = c.BH.ink_of(panel, c.RG, c.fonts) if panel else []
            if not c.check("U1", bool(ink), what + ": the tutorial shows"):
                continue
            ui = c.BH.union(ink)
            others = []
            for key in ("RunButton", "DashButton"):
                kn = nodes.get("MobileControls." + key)
                if kn and float(kn["w"]) > 1:
                    others.append((key, c.BH.ink_of(kn, c.RG, c.fonts)))
            for p, n in nodes.items():
                if re.match(r"^NimbusHud\.\w+\.Vitals$", p):
                    others.append(("the vitals card", c.BH.ink_of(n, c.RG, c.fonts)))
            for name, kink in others:
                if not kink:
                    continue
                g, a, b = c.BH.ink_gap(ink, kink, ui, c.BH.union(kink), c.BH.MIN_GAP)
                c.check("U1", g >= c.BH.MIN_GAP - 0.05, "%s: the tutorial keeps %g px off %s" % (what, c.BH.MIN_GAP, name),
                        "tutorial ink %s, %s %s: %.1f px" % (fmt(a), name, fmt(b), g))
            if touch:
                for name, (cen, rad) in c.BH.rings(w, h).items():
                    g = min(c.BH.ring_gap(r, cen, rad) for r in ink)
                    c.check("U1", g >= c.BH.MIN_GAP - 0.05, "%s: the tutorial keeps %g px off %s's ring" % (what, c.BH.MIN_GAP, name),
                            "tutorial ink %s, ring at %.0f,%.0f r %.0f: %.1f px" % (fmt(ui), cen[0], cen[1], rad, g))
        c.cache.clear()
    u1_states(c, sizes)


# (look:fix6b2 N1, NEW from c1e122e's chip fallback: in a 3 or 4 player match - tutorial step 8 - and on a full party pad -
# step 7 - the portrait chip lay under the menu column's Home tile: 360 x 640 20-23 px, 384 x 640 23.5-26.5 px, 375 x 667
# 1.9 px, at every width 320-430 on 640-tall screens and in solo matches on 568-tall: the chip's fallback dock over the
# vitals card was checked against the touch keys only. U1 read the lobby alone.) The tutorial over the other HUD states, as
# the game sets them (tools/dump_gui.lua tutorial:<step>:match / party / countdown): a match with 1 - 4 players and the
# long-name SAINT match, the party pad and its leader's full pad, a match's countdown. Rule: the tutorial's ink keeps MIN_GAP
# off EVERY other HUD piece (each ScreenGui's pieces and their parts: the menu column and its tiles, the touch keys, the
# vitals card, the match / party panel, the wallet strips, the gift ...) and off Roblox's thumbstick and jump rings, at the
# gate sizes, U1's phones and a portrait sweep (320 - 430 wide, 568 / 640 / 720 tall).
# U1_BACKLOG: where kit-b 1a55f73 already has a gap under MIN_GAP in these states (the owner's rule of 2026-11-24: what
# kit-b already has goes to the backlog), measured by this pin on kit-b's src with these tools (the tutorial chip / strip /
# card 1.6 - 2.4 px off the match / party panel on landscape phones and PC, the landscape chip on the wallet strip, the
# portrait chip on the column's fold tab at 320 - 384 wide): such a case passes while its gap is no worse than kit-b's and
# fails as soon as it gets worse; every other case keeps MIN_GAP. (kit-b backlog items 7 / 8) The fixture's U1 key is
# empty: its 142 landscape rows closed with those items, its 242 portrait rows (320 - 430 x 568 / 640 / 720) keep MIN_GAP
# on kit-b 3d165fa already (build/GATE_BL/tutorial/pins/u1_backlog_rows_kitb.txt), so every case keeps MIN_GAP.
U1_STATES = ["tutorial:8:match:1", "tutorial:8:match:2", "tutorial:8:match:3", "tutorial:8:match:4", "tutorial:8:match:full",
             "tutorial:7:party", "tutorial:7:party:leader", "tutorial:8:countdown"]
U1_SWEEP = [(w, h) for h in (568, 640, 720) for w in (320, 340, 360, 375, 384, 393, 400, 412, 430)]
U1_BACKLOG = kitb_backlog("U1")


def tutorial_gaps(c, nodes, w, h):
    """[(gap, piece path, piece ink rect)] for every other piece (depth 1 / 2 of a ScreenGui, holders skipped) and Roblox's
    rings within MIN_GAP of the tutorial's ink; None when the tutorial shows no ink"""
    panel = nodes.get(U1_PANEL)
    ink = c.BH.ink_of(panel, c.RG, c.fonts) if panel else []
    if not ink:
        return None
    ui = c.BH.union(ink)
    out = []
    for p, n in nodes.items():
        if p.startswith("NimbusTutorial") or p.count(".") not in (1, 2):
            continue
        if float(n["w"]) <= 1 or float(n["h"]) <= 1 or (float(n["w"]) > 0.9 * w and float(n["h"]) > 0.6 * h):
            continue
        kink = c.BH.ink_of(n, c.RG, c.fonts)
        if not kink:
            continue
        uk = c.BH.union(kink)
        if uk[2] - uk[0] > 0.9 * w and uk[3] - uk[1] > 0.6 * h:
            continue
        g, a, b = c.BH.ink_gap(ink, kink, ui, uk, c.BH.MIN_GAP)
        if g < c.BH.MIN_GAP - 0.05:
            out.append((round(g, 1), p, b))
    if c.RG.is_touch(w, h, None):
        for name, (cen, rad) in c.BH.rings(w, h).items():
            g = min(c.BH.ring_gap(r, cen, rad) for r in ink)
            if g < c.BH.MIN_GAP - 0.05:
                out.append((round(g, 1), name + "'s ring", None))
    return out


def u1_states(c, sizes):
    for (w, h) in list(sizes) + [s for s in U1_EXTRA + U1_SWEEP if s not in sizes]:
        for scen in U1_STATES:
            nodes = c.nodes(c.dump(scen, w, h))
            what = "U1 %s %dx%d" % (scen, w, h)
            gaps = tutorial_gaps(c, nodes, w, h)
            if not c.check("U1", gaps is not None, what + ": the tutorial shows"):
                continue
            bad = []
            for g, p, b in gaps:
                was = U1_BACKLOG.get((scen, w, h, p))
                if was is None or g < was - 0.05:
                    bad.append("%s %.1f px%s%s" % (p, g, (" at " + fmt(b)) if b else "", (" (kit-b %.1f)" % was) if was is not None else ""))
            c.check("U1", not bad, "%s: the tutorial keeps %g px of ink off every HUD piece and the rings" % (what, c.BH.MIN_GAP), "; ".join(bad[:4]))
        c.cache.clear()


# ---------------------------------------------------------------------------------------------------------------- U2
# (look:fix6b2 N3: the tutorial's titles cut with an ellipsis. NEW in fix6b: 360 x 640 step 20 'The Champion Ri...' on the
# folded strip - O3 put the strip there, where kit-b showed the portrait chip and no title. OLD (kit-b): the strip at
# 390 x 844 steps 15 / 20 and 640 x 360 steps 6 / 8 / 10 / 11, the opened card at 390 x 844 steps 16 / 20 / 21 and
# 375 x 667 step 11. The title was not shrunk first: 640 x 360 step 10 drew 'Claim Your Home' at its full 18.4 px, 7.7 px
# too wide.) Rule: wherever the tutorial shows a title - the folded strip's QuestTitle, the card's StepTitle as shown or
# opened with a tap (tutorial:<n>:open) - it reads whole (no ellipsis, no line past its box), at every step, at the gate
# sizes and the phones the looks used.
# U2_BACKLOG: (scenario, size, title) kit-b 1a55f73 cuts too, at its 14.4 px floor (the owner's rule of 2026-11-24: what
# kit-b already has goes to the backlog), measured by this pin on kit-b's src; every other title reads whole.
U2_EXTRA = [(375, 667), (384, 640), (320, 568)]
U2_BACKLOG = kitb_backlog("U2")


def pin_U2(c, sizes):
    total = tutorial_total(c.nodes(c.dump("tutorial:1", 1280, 720)))
    if not c.check("U2", total is not None and total > 1, "U2 tutorial 1280x720: the tutorial shows its step count"):
        return
    for (w, h) in list(sizes) + [s for s in U2_EXTRA if s not in sizes]:
        for step in range(1, total + 1):
            for mode in ("", ":open"):
                scen = "tutorial:%d%s" % (step, mode)
                nodes = c.nodes(c.dump(scen, w, h))
                titles = [(p, n) for p, n in nodes.items() if p.startswith(U1_PANEL + ".") and re.search(r"\.(QuestTitle|StepTitle)$", p)
                          and isinstance(n.get("text"), dict) and str(n["text"].get("text", "")).strip() and float(n["w"]) > 1]
                for p, n in titles:
                    ok, how = c.whole(n)
                    name = p.split(".")[-1]
                    c.check("U2", ok or (scen, w, h, name) in U2_BACKLOG, "U2 %s %dx%d: the tutorial's %s reads whole" % (scen, w, h, name), how)
                # (kit-b backlog item 10: 13 objective lines ran past their box - 960 x 540 steps 11 / 13 / 14 / 17 / 20,
                # 1024 x 768 steps 16 / 17 / 20, 390 x 844 opened 16 / 17 / 20 / 21: the row was one line tall where the words
                # took two) the card's objective line reads whole too: every line it wraps to inside its box
                for p, n in nodes.items():
                    if p.startswith(U1_PANEL + ".") and p.endswith(".Hint") and isinstance(n.get("text"), dict) \
                            and str(n["text"].get("text", "")).strip() and float(n["w"]) > 1:
                        ok, how = c.whole(n)
                        c.check("U2", ok, "U2 %s %dx%d: the tutorial's objective line reads whole" % (scen, w, h), how)
                if not mode and any(p.endswith(".StepTitle") for p, _ in titles):
                    break  # (the card shows already: a tap opens nothing more)
        c.cache.clear()


# ---------------------------------------------------------------------------------------------------------------- U3
# (kit-b backlog item 6, GATE_P2 tutfix_look c05: on 360 x 640 and 384 x 640 at all 21 steps, and 375 x 667 at 18 of 21, a
# tap on the folded guide opened nothing - no '+', the taps returned early - so the step's words, its Next and the Skip link
# were out of reach and the tutorial could not pass step 1 there. TutorialController's last-resort card was tried only
# beside the wallet strip and the Gift tile, too narrow there; the spot under them had 160 - 180 px above RUN.) Rule: on
# the short portrait phones and the portrait sweep, every step's card the player opens with a tap (tutorial:<n>:open)
# shows - its Skip link, and its Next where the step has one (as the same step shows it at 1280 x 720) - wholly on the
# screen, the Next and Skip words whole, the card's ink MIN_GAP off RUN, DASH and Roblox's stick and jump rings. The tall
# phones that open it today (390 x 844, 393 x 852, 412 x 915) are the control.
U3_SIZES = [(360, 640), (384, 640), (375, 667), (390, 844), (393, 852), (412, 915)]
U3_REF = (1280, 720)
# U3_NO_ROOM: the sizes where kit-b 3d165fa opens no card at any step (build/GATE_BL/tutorial/pins/red_U3_kitb.txt) and no
# spot has room for one within the card's own rule - it never covers the menu column, the touch keys or the thumbstick, and
# never shrinks below 0.7 (14 px words) or PANEL_MIN_W: a 568-tall phone has about 190 px under the menu column above the
# stick (the shortest card needs about 210 at 0.7), a 320-wide phone 172 px left of RUN / DASH (a card 182 at 0.7). Whether
# the opened card may lie over the menu column there is the owner's call. Here a tap that opens nothing passes (no worse
# than kit-b); a card that does open keeps every other rule
U3_NO_ROOM = {(320, 568), (320, 640), (320, 720)} | {(w, 568) for w in (340, 360, 375, 384, 393, 400, 412, 430)}


def pin_U3(c, sizes):
    total = tutorial_total(c.nodes(c.dump("tutorial:1", U3_REF[0], U3_REF[1])))
    if not c.check("U3", total is not None and total > 1, "U3 tutorial %dx%d: the tutorial shows its step count" % U3_REF):
        return
    has_next = {}
    for step in range(1, total + 1):
        nodes = c.nodes(c.dump("tutorial:%d:open" % step, U3_REF[0], U3_REF[1]))
        has_next[step] = any(p.startswith(U1_PANEL + ".") and p.endswith(".Footer.Next") for p in nodes)
    c.cache.clear()
    want = [s for s in U3_SIZES + U1_SWEEP if s[1] > s[0]]
    for (w, h) in [s for i, s in enumerate(want) if s not in want[:i]]:
        for step in range(1, total + 1):
            scen = "tutorial:%d:open" % step
            nodes = c.nodes(c.dump(scen, w, h))
            what = "U3 %s %dx%d" % (scen, w, h)
            panel = nodes.get(U1_PANEL)
            main = [p for p in nodes if p.startswith(U1_PANEL + ".") and p.endswith(".Main")]
            if (w, h) in U3_NO_ROOM and not (panel is not None and main):
                c.check("U3", True, what + ": no room for a card (U3_NO_ROOM, as kit-b)")
                continue
            if not c.check("U3", panel is not None and bool(main), what + ": a tap opens the card",
                           "folded: %s" % ("the quest strip" if any(p.endswith(".QuestStrip") for p in nodes) else "the portrait chip")):
                continue
            ink = c.BH.ink_of(panel, c.RG, c.fonts)
            ui = c.BH.union(ink)
            c.check("U3", ui[0] >= -0.5 and ui[1] >= -0.5 and ui[2] <= w + 0.5 and ui[3] <= h + 0.5, what + ": the card wholly on the screen", fmt(ui))
            parts = {"Skip": [p for p in nodes if p.startswith(U1_PANEL + ".") and p.endswith(".Footer.SkipLink")],
                     "Next": [p for p in nodes if p.startswith(U1_PANEL + ".") and p.endswith(".Footer.Next")]}
            for name, paths in parts.items():
                if name == "Next" and not has_next[step]:
                    continue
                if not c.check("U3", bool(paths), "%s: its %s shows" % (what, name)):
                    continue
                r = rect(nodes[paths[0]])
                c.check("U3", r[0] >= -0.5 and r[1] >= -0.5 and r[2] <= w + 0.5 and r[3] <= h + 0.5, "%s: its %s on the screen" % (what, name), fmt(r))
                for p, n in nodes.items():
                    if p == paths[0] or (p.startswith(paths[0] + ".") and isinstance(n.get("text"), dict)):
                        ok, how = c.whole(n)
                        c.check("U3", ok, "%s: its %s reads whole" % (what, name), how)
            for key in ("RunButton", "DashButton"):
                kn = nodes.get("MobileControls." + key)
                kink = c.BH.ink_of(kn, c.RG, c.fonts) if kn and float(kn["w"]) > 1 else []
                if kink:
                    g, a, b = c.BH.ink_gap(ink, kink, ui, c.BH.union(kink), c.BH.MIN_GAP)
                    c.check("U3", g >= c.BH.MIN_GAP - 0.05, "%s: the card keeps %g px off %s" % (what, c.BH.MIN_GAP, key),
                            "card ink %s, %s %s: %.1f px" % (fmt(a), key, fmt(b), g))
            for name, (cen, rad) in c.BH.rings(w, h).items():
                g = min(c.BH.ring_gap(r, cen, rad) for r in ink)
                c.check("U3", g >= c.BH.MIN_GAP - 0.05, "%s: the card keeps %g px off %s's ring" % (what, c.BH.MIN_GAP, name),
                        "card ink %s, ring at %.0f,%.0f r %.0f: %.1f px" % (fmt(ui), cen[0], cen[1], rad, g))
        c.cache.clear()


# ------------------------------------------------------------------------------------------------------------- B0-B3
# (the owner's pick B of 2026-11-23 on the guide chip pitch, "Top-bar plank", the X on the RIGHT: Gemini's left X not
# taken) the travel guide's chip is the top bar pill's twin: a cream plank docked in Roblox's top band at its right end
# beside the '...' button (the pill's height, GuiService.TopbarInset read as the pill reads it); a portrait phone, with no
# room in the band, gets the same two-line ticket on the vitals stack, flush with the card's left edge, 8 px over the name
# plank (over the tutorial's quest strip when that docks there). It never moves on a camera move (guide_pins in the smoke
# holds that frame by frame, and the needle). Here, over every HUD state the chip can meet (tools/dump_gui.lua
# guidechip:<state>), at the fifteen sizes of the pick (B_SIZES):
#   B0  its home: a landscape screen's chip wholly in the top band at its right end (its face's right edge B_DOCK px
#       left of TopbarInset's right end, the '...' room); a portrait phone's on the vitals stack (its ink's foot
#       B_STACK px over the name plank or the docked quest strip - or over a touch key in its columns: "clear of RUN" -,
#       its face's left edge the card's)
#   B1  its ink keeps battle_hud_no_overlap's MIN_GAP off every other HUD piece (the menu column, the pill, the wallet
#       strips, the gift and boosts, the toasts, the tutorial, the mouse-lock plank, the party panel, the vitals card and
#       the touch keys) and off Roblox's own top-bar buttons and touch rings; a match or its countdown ends the guide:
#       no chip
#   B2  its X: a 44 px hit box at least B_DOTS px off Roblox's '...' button
#   B3  its words: the place and its distance ('Storm Altar' / 'NN studs away', a PC's tag 'NN studs'), 'Home first' /
#       'then follow the arrow' away, "You're here" / the prompt's words at the gate; each whole (no ellipsis, no line past
#       its box), >= 14.4 px on a phone (the readability floor elsewhere: 14 px, 15 on a screen 1000 px tall or more)
# (look:chipB minor 3: the narrowest landscape phone, 568 x 320, where the pill and the chip share the band most tightly)
B_SIZES = [(320, 568), (360, 640), (375, 667), (384, 640), (390, 844), (568, 320), (640, 360), (667, 375), (720, 405),
           (800, 450), (844, 390), (960, 540), (1024, 768), (1280, 720), (1920, 1080), (2560, 1440)]
#   (look:chipB, the look review of 816badd) B0 also holds the chip wholly on the screen (minor 5: nothing did; major 3:
#       at 320 x 568 the ticket stood flush with a vitals card standing right of the menu, its right end past the screen)
#       and its face's right edge exactly B_DOCK px left of the band's right end (minor 5: was any of 24 px); B1 reads the
#       HUD three levels deep (was two) and meets the states it had not: a dungeon party's countdown (major 2: its chip
#       holds the band from the pill to '...', where the guide's yields its spot - hidden while the two would meet), the
#       arena's side card, an NPC's dialog and an open window (minor 5); B3 holds a PC's Home / Here second line as plain
#       words, no stud count's number cell (minor 4)
B_STATES = ["guidechip:lobby", "guidechip:boosts", "guidechip:toasts", "guidechip:tutorial:3", "guidechip:tutorial:3:fold",
            "guidechip:mousehint", "guidechip:party", "guidechip:party:leader", "guidechip:match:4", "guidechip:countdown",
            "guidechip:away", "guidechip:here", "guidechip:dungeon", "guidechip:arenaside", "guidechip:npc", "guidechip:window"]
B_GONE = {"guidechip:match:4", "guidechip:countdown"}
# (look:chipB) the states where a card may take the chip's spot for a while (the chip yields it: hidden, see B1); every
# other state keeps the chip on the screen. An open window too: on a portrait phone it covers the vitals stack, and at
# 960 x 540 the Shop's awning reaches into the band 1 px under the chip (3 px under the pill: the window's own seat)
B_YIELD = {"guidechip:party", "guidechip:party:leader", "guidechip:dungeon", "guidechip:arenaside", "guidechip:npc",
           "guidechip:window"}
B_CHIP = "NimbusGuide.Chip"
B_DOCK = 8
B_GUTTER = 8
B_STACK = 8
B_DOTS = 16
B_DONE = set()


def roblox_buttons(w, h, inset):
    """Roblox's own top-bar buttons as render_gui sketches them (44 px, 12 px in): the menu and chat on the left, '...' on
    the right -> {name: rect}"""
    if inset <= 0:
        return {}
    y = (inset - 44.0) / 2.0
    return {"Roblox menu": (12.0, y, 56.0, y + 44), "Roblox chat": (64.0, y, 108.0, y + 44),
            "Roblox '...'": (w - 56.0, y, w - 12.0, y + 44)}


def b_words(state, touch, texts):
    """(ok, what the chip says) for the state's phase"""
    said = " / ".join(texts)
    if state == "guidechip:away":
        ok = "Home first" in texts and any(t in ("then follow the arrow", "then the arrow") for t in texts)
    elif state == "guidechip:here":
        ok = "You're here" in texts and ("tap the button" if touch else "press E") in texts
    else:
        ok = "Storm Altar" in texts and any(re.match(r"^\d+ studs( away)?$", t) for t in texts)
    return ok, said


def pin_B(c, sizes):
    if B_DONE:
        return
    B_DONE.add(True)
    # (the pick's fifteen sizes plus 568 x 320, look:chipB minor 3; --size names others instead, while working)
    for (w, h) in (B_SIZES if sizes is SIZES else sizes):
        touch = c.RG.is_touch(w, h, None)
        for scen in B_STATES:
            if scen == "guidechip:mousehint" and touch:
                continue  # (a desktop's plank: the scenario turns touch off)
            d = c.dump(scen, w, h)
            nodes = c.nodes(d)
            what = "%s %dx%d" % (scen, w, h)
            chip = nodes.get(B_CHIP)
            ink = c.BH.ink_of(chip, c.RG, c.fonts) if chip else []
            if scen in B_GONE:
                c.check("B1", not ink, "B1 %s: a match ends the guide (no chip)" % what, fmt(c.BH.union(ink)) if ink else "")
                continue
            # (look:chipB major 2) the chip never moves for a camera, but a card that comes to stand on its spot (a dungeon
            # party's countdown in the top band, the arena's side card, an NPC's talk, a window, the party panel) takes
            # it: the chip hides while it stands there. Hidden passes only with that card's ink within MIN_GAP of the
            # chip's noted home - a chip hidden for nothing is still red
            if not ink and scen in B_YIELD:
                # (look:chipB major 2 and the new states) a card that takes the chip's spot for a while (a dungeon party's
                # countdown chip in the band, an NPC's dialog, the arena's invite card, a full portal party's panel with
                # the menu tiles it pushes down on a portrait phone): the chip yields its spot - hidden, the guide still
                # running. Held only where some shown piece meets the hidden chip's home (the scenario's note) within
                # MIN_GAP; a chip hidden with its spot free fails. (Was: B0 'the chip shows' in every state but a match)
                hm = next((re.match(r"^guidechip (\w+) home ([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)$", s) for s in d.get("notes", [])
                           if str(s).startswith("guidechip ")), None)
                hr = tuple(float(v) for v in hm.groups()[1:]) if hm else None
                who = None
                for p, n in (nodes.items() if hr else []):
                    if p.startswith("NimbusGuide") or p.count(".") not in (1, 2, 3) or float(n["w"]) <= 1 or float(n["h"]) <= 1:
                        continue
                    kink = c.BH.ink_of(n, c.RG, c.fonts)
                    if kink and min(c.BH.gap(r, hr) for r in kink) < c.BH.MIN_GAP - 0.05:
                        who = p
                        break
                c.check("B1", who is not None, "B1 %s: the chip yields its spot only to a card standing on it" % what,
                        "hidden at %s, %s" % (fmt(hr), ("taken by " + who) if who else "nothing there") if hr else "no home noted")
                continue
            if not c.check("B0", bool(ink), "B0 %s: the chip shows" % what):
                continue
            ui = c.BH.union(ink)
            inset = float(d.get("inset", 0) or 0)
            # B0 wholly on the screen, B_GUTTER px or more in from its sides (look:chipB major 3, minor 5: at 320 x 568 the
            # ticket's ink ended 3 px from the right edge, 7 px past the vitals card it stands on)
            c.check("B0", ui[0] >= B_GUTTER - 0.05 and ui[1] >= -0.05 and ui[2] <= w - B_GUTTER + 0.05 and ui[3] <= h + 0.05,
                    "B0 %s: the chip stands wholly on the screen, %d px or more in from its sides" % (what, B_GUTTER),
                    "chip ink %s on a %dx%d screen" % (fmt(ui), w, h))
            # B0 the home
            if w > h:
                limit = w - 72.0  # (TopbarInset's right end: render_gui's phone Rect(112, 0, W - 72, 58); a desktop's fallback)
                face = rect(chip)
                ok = ui[1] >= 0 and ui[3] <= inset + 0.5 and abs(face[2] - (limit - B_DOCK)) <= 0.5
                c.check("B0", ok, "B0 %s: the chip docks in the top band at its right end (the pill's twin)" % what,
                        "chip ink %s (face right %.1f), band 0..%.0f, its face's right edge due at %.0f" % (fmt(ui), face[2], inset, limit - B_DOCK))
            else:
                tab = next((n for p, n in nodes.items() if re.match(r"^NimbusHud\.\w+\.Vitals\.Body\.NameTab$", p)), None)
                card = next((n for p, n in nodes.items() if re.match(r"^NimbusHud\.\w+\.Vitals\.Body\.Card$", p)), None)
                strip = next((n for p, n in nodes.items() if p.startswith("NimbusTutorial.") and p.endswith(".QuestStrip")), None)
                sink = c.BH.ink_of(strip, c.RG, c.fonts) if strip else []
                if not c.check("B0", tab is not None and card is not None, "B0 %s: (setup) the vitals card shows" % what):
                    continue
                foot = c.BH.union(c.BH.ink_of(tab, c.RG, c.fonts) or [rect(tab)])[1]
                if sink:
                    su = c.BH.union(sink)
                    if su[3] <= foot + 0.5 and su[1] < foot:
                        foot = min(foot, su[1])
                # (the pick: "clear of RUN") a touch key in the chip's columns that reaches up into its spot: the chip
                # stands B_STACK px over the key instead (320 x 568: the vitals card stands right of the menu, under RUN)
                for p, n in nodes.items():
                    if re.match(r"^MobileControls\.\w+Button$", p) and float(n["w"]) > 1:
                        ku = c.BH.union(c.BH.ink_of(n, c.RG, c.fonts) or [rect(n)])
                        if ku[0] < ui[2] + B_STACK and ku[2] > ui[0] - B_STACK and ku[1] < foot and ku[3] > ui[1] - B_STACK:
                            foot = min(foot, ku[1])
                face = rect(chip)
                # (look:chipB major 3) flush with the card's left edge; where that would run past the screen's right
                # gutter (12 px: a vitals card standing right of the menu at 320 x 568, the wider Home ticket) the chip
                # stands pushed in from it, its ink's right edge on the gutter
                flush = abs(face[0] - rect(card)[0]) <= 1.5 or (face[0] < rect(card)[0] and abs(ui[2] - (w - 12.0)) <= 1.5)
                ok = abs((foot - B_STACK) - ui[3]) <= 1.5 and flush
                c.check("B0", ok, "B0 %s: the chip stands on the vitals stack, %d px over the name plank (or the strip), flush with the card" % (what, B_STACK),
                        "chip ink %s (face x %.1f), card x %.1f, under it at y %.1f" % (fmt(ui), face[0], rect(card)[0], foot))
            # B1 clear of every other piece
            bad = []
            # (look:chipB, the window state) a ScreenGui drawn over the chip's (a higher DisplayOrder) with a piece that
            # wholly covers the chip's ink hides it: on a portrait phone an open window covers the vitals stack, the chip
            # with it, as it covers the vitals card. Its parts are not the chip's neighbours (a part over a chip it only
            # partly covers still counts)
            orders = {g.get("name"): float(g.get("displayOrder", 0) or 0) for g in d.get("guis", [])}
            mine = orders.get(B_CHIP.split(".")[0], 0.0)
            over = set()
            for p, n in nodes.items():
                gname = p.split(".")[0]
                if orders.get(gname, 0.0) > mine and gname not in over:
                    for r in c.BH.drawn_rects(n, c.RG, c.fonts):
                        if r[0] <= ui[0] + 0.05 and r[1] <= ui[1] + 0.05 and r[2] >= ui[2] - 0.05 and r[3] >= ui[3] - 0.05:
                            over.add(gname)
                            break
            for p, n in nodes.items():
                # (minor 5: three levels deep, was two: a piece inside a card's body, a window's part)
                if p.startswith("NimbusGuide") or p.count(".") not in (1, 2, 3) or p.split(".")[0] in over:
                    continue
                if float(n["w"]) <= 1 or float(n["h"]) <= 1 or (float(n["w"]) > 0.9 * w and float(n["h"]) > 0.6 * h):
                    continue
                kink = c.BH.ink_of(n, c.RG, c.fonts)
                if not kink:
                    continue
                uk = c.BH.union(kink)
                if uk[2] - uk[0] > 0.9 * w and uk[3] - uk[1] > 0.6 * h:
                    continue
                g, a, bb = c.BH.ink_gap(ink, kink, ui, uk, c.BH.MIN_GAP)
                if g < c.BH.MIN_GAP - 0.05:
                    bad.append("%s %.1f px at %s" % (p, g, fmt(bb)))
            for name, r in roblox_buttons(w, h, inset).items():
                g = min(c.BH.gap(a, r) for a in ink)
                if g < c.BH.MIN_GAP - 0.05:
                    bad.append("%s %.1f px" % (name, g))
            if touch:
                for name, (cen, rad) in c.BH.rings(w, h).items():
                    g = min(c.BH.ring_gap(r, cen, rad) for r in ink)
                    if g < c.BH.MIN_GAP - 0.05:
                        bad.append("%s's ring %.1f px" % (name, g))
            c.check("B1", not bad, "B1 %s: the chip keeps %g px of ink off every HUD piece" % (what, c.BH.MIN_GAP), "; ".join(bad[:4]))
            # B2 the X
            close = nodes.get(B_CHIP + ".Close")
            if scen != "guidechip:here":
                if c.check("B2", close is not None and float(close["w"]) > 1, "B2 %s: the chip has its X" % what):
                    cr = rect(close)
                    dots = roblox_buttons(w, h, inset).get("Roblox '...'")
                    g = c.BH.gap(cr, dots) if dots else 999.0
                    c.check("B2", cr[2] - cr[0] >= 44 - 0.05 and cr[3] - cr[1] >= 44 - 0.05 and g >= B_DOTS - 0.05,
                            "B2 %s: the X is a 44 px hit box %d px or more off '...'" % (what, B_DOTS),
                            "hit box %s (%.1f x %.1f), %.1f px off '...'" % (fmt(cr), cr[2] - cr[0], cr[3] - cr[1], g))
            # B3 the words
            floor = 14.4 if touch else (15.0 if h >= 1000 else 14.0)
            texts = []
            for p, n in nodes.items():
                t = n.get("text")
                if p.startswith(B_CHIP + ".") and isinstance(t, dict) and str(t.get("text", "")).strip() and float(n["w"]) > 1:
                    texts.append(str(t["text"]).strip())
                    ok, how = c.whole(n)
                    size = float(t.get("size", 0))
                    c.check("B3", ok and size >= floor - 0.05, "B3 %s: '%s' reads whole at %g px or more" % (what, t["text"], floor),
                            "%s (%.1f px)" % (how, size))
            ok, said = b_words(scen, touch, texts)
            c.check("B3", ok, "B3 %s: the chip says the place and its distance (Home / here: its phase's words)" % what, said)
            if scen in ("guidechip:away", "guidechip:here"):
                # (minor 4) the stud count's number cell is the walk's alone: Home / Here say their second line in words
                tag = nodes.get(B_CHIP + ".Tag")
                tagged = tag is not None and float(tag["w"]) > 1 and bool(c.BH.ink_of(tag, c.RG, c.fonts))
                c.check("B3", not tagged, "B3 %s: its second line is plain words (no stud count's tag)" % what,
                        "a tag at %s" % fmt(rect(tag)) if tagged else "")
        c.cache.clear()


RUN = {"K1": pin_K1, "K2": pin_K2, "I1": pin_I1, "I2": pin_I2, "H1": pin_H1, "C1": pin_C1, "C2": pin_C2, "C5": pin_C5,
       "Q1": pin_Q1, "E1": pin_E1, "D1": pin_D1, "O1": pin_O1, "O2": pin_O2, "O3": pin_O3, "T1": pin_T1, "U1": pin_U1, "U2": pin_U2, "U3": pin_U3,
       "B0": pin_B, "B1": pin_B, "B2": pin_B, "B3": pin_B}


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
