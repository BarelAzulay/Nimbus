"""kit-b gate U9 round 3: the completeness gate (tools/stroke_walk.py) walks every documented render scenario.

stroke_walk.py walks render_gui.SCENARIOS (minus its SKIP of widget galleries). This test fails when:
  * a form documented in tools/dump_gui.lua's header (`--   name[:a|:b]`, literal options only; `<placeholder>` options
    name a family that the explicit list below covers) is not in SCENARIOS,
  * a phase / view the header documents in prose (battle phases, ring rounds, arena views, ring views) is not in it,
  * a scenario registered in dump_gui.lua (`scenario("name", ...)`) has no form in SCENARIOS,
  * stroke_walk's SKIP holds anything but the widget galleries.
Run: py -3.12 tools/test_gate_scenarios.py (offline, no Lua)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import render_gui as RG  # noqa: E402
import stroke_walk as SW  # noqa: E402

DUMP = os.path.join(HERE, "dump_gui.lua")

# a documented option that renders the base form (its default), so the base covers it
DEFAULTS = {"loss:ring": "loss", "hatch": "hatch:reveal"}
# registered scenario() names with no form of their own: store = the Shop through the StoreController forwarder
NOT_WALKED = {"store"}
# the header's prose: battle[:<mode>[:<phase>]] phases, the ring's rounds, arena[:<view>] views, ring[:<view>] views
PROSE = [
    # (playtest 2026-11-28 C62) battle:trial:* and battle:duel:overtime are gone (BattleSim 10.5); the phases on dungeon
    "battle:dungeon:ready", "battle:dungeon:lost", "battle:dungeon:cleared",
    "battle:ring:fight8", "battle:ring:next8", "battle:ring:result8", "battle:ring:record8",
    "arena:side", "arena:team4", "arena:newteam", "arena:duels", "arena:raid", "arena:leaders",
    "ring:record", "ring:new",
]
GALLERIES = {"gallery", "signkit", "neon", "neon:window", "neon:hud", "neon:party"}


def header_forms(text):
    """[form] from the header's `--   name[...]` lines (literal options only)."""
    forms = []
    for line in text.splitlines()[1:]:
        if not line.startswith("--"):
            break
        m = re.match(r"^--   ([a-z][a-z0-9_]*)(\[[^\s]*\])?\s", line + " ")
        if not m:
            continue
        name, opts = m.group(1), m.group(2) or ""
        forms.append(name)
        inner = opts[1:-1]
        if inner.count("[") == 0:  # nested brackets are placeholder families (menu, arena, battle, portal)
            for opt in inner.split("|"):
                opt = opt.strip()
                if opt.startswith(":") and "<" not in opt:
                    forms.append(name + opt)
    return forms


def main():
    text = open(DUMP, encoding="utf-8").read()
    walked = set(RG.SCENARIOS)
    bad = []
    forms = header_forms(text)
    for f in forms + PROSE:
        if f in walked or DEFAULTS.get(f) in walked or f in GALLERIES:
            continue
        bad.append("documented form %r is not in render_gui.SCENARIOS" % f)
    bases = {s.split(":")[0] for s in walked}
    for name in sorted(set(re.findall(r'^scenario\("([^"]+)"', text, re.M))):
        if name not in bases and name not in NOT_WALKED:
            bad.append("registered scenario %r has no form in render_gui.SCENARIOS" % name)
    extra = set(SW.SKIP) - GALLERIES
    if extra:
        bad.append("stroke_walk.SKIP drops game screens: %s" % sorted(extra))
    if len(forms) < 30:
        bad.append("parsed only %d header forms (the header moved?)" % len(forms))
    for b in bad:
        print("FAIL  " + b)
    print("gate scenarios: %d header forms + %d prose forms checked, %d failed" % (len(forms), len(PROSE), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
