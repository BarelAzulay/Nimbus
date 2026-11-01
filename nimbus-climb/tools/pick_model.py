#!/usr/bin/env python3
"""The model and effort router: which model and effort for which job, and when a whole build runs as ultracode.

The table of docs/superpowers/specs/2026-11-01-model-effort-router.md as data. There is no flag that lowers a route, and an
unknown kind fails: it never guesses low. It picks the route only; the speed scout then changes order and parallelism.

    py -3.12 tools/pick_model.py --list
    py -3.12 tools/pick_model.py --job saves
    py -3.12 tools/pick_model.py --job game-feature --money --live
    py -3.12 tools/pick_model.py --build game-feature --many-systems
"""
import argparse
import sys

HAIKU, SONNET, OPUS, FABLE = "Haiku 5.5", "Sonnet 5.5", "Opus 5.5", "Fable 5.1"
MODELS = (HAIKU, SONNET, OPUS, FABLE)  # cheapest first
EFFORTS = ("low", "medium", "high", "xhigh", "max")  # the owner's "easy" = low, "extra high" = xhigh
LEVELS = ("easy", "medium", "high", "xhigh", "ultracode")  # whole-job levels; ultracode is a way to run a job, not an effort
LEVEL_NAMES = {"easy": "Easy", "medium": "Medium", "high": "High", "xhigh": "Extra high", "ultracode": "Ultracode"}

STAGES = ("plan", "build", "review", "fix", "gate")
NEVER_DROPPED = "never dropped: tests, reviews, pitch, evidence, the owner's Studio check; in doubt the route goes up"


def _job(builder, reviewer, level, gate, why, up=()):
    """level None = one stage of a build, not a build of its own. up = the Up items this route already includes."""
    return {"builder": builder, "reviewer": reviewer, "level": level, "gate": gate, "why": why, "up": frozenset(up)}


# Spec section 1. Builder, reviewer (None = the gate is the review), whole-job level, gate, reason.
JOBS = {
    "game-feature": _job(
        (OPUS, "high"), (FABLE, "high"), "high", "smoke suite (targeted, then full)",
        "Game code, server authoritative: the standing law; Fable catches the trust mistakes the suite cannot."),
    "saves": _job(
        (FABLE, "high"), (FABLE, "xhigh"), "xhigh", "frozen-fixture rollout tests",
        "Saves and player data: a bad save is live data and hard to undo; fixtures only hold the cases someone thought of.",
        up=["saves"]),
    "money": _job(
        (OPUS, "high"), (FABLE, "xhigh"), "xhigh", "sim_tycoon.py ALL TARGETS MET",
        "Money and rewards: a double payout is live, visible and cannot be undone; Fable gates the once-per-member rules.",
        up=["money"]),
    "security": _job(
        (OPUS, "high"), (FABLE, "xhigh"), "xhigh", "the adversarial review itself: it plays the exploiter",
        "Security of remotes: no test plays an exploiter, so the reviewer must.",
        up=["security"]),
    "balance": _job(
        (OPUS, "medium"), (FABLE, "medium"), "medium", "tools/sim_battle.lua (full, seeds as the plan says)",
        "Balance tuning: the sim catches a wrong number; the review reads whether a target was bent, not the code."),
    "effects-gui": _job(
        (OPUS, "high"), (FABLE, "medium"), "high", "render_gui / render_model sheets + the owner's Studio check",
        "Effects and GUI only Studio can judge: the mock passed and Studio still showed a cube sky; the owner's look is the gate.",
        up=["studio-only"]),
    "pitch": _job(
        (FABLE, "high"), None, None, "the owner, item by item (+ Gemini as the creative check)",
        "Design pitches: the hardest thinking; Gemini checks it, the owner decides."),
    "blender": _job(
        (OPUS, "high"), None, "high", "the owner on renders (Fable judge only for a wave's style recipe)",
        "Blender art: many render-inspect-fix loops at modest reasoning each; taste is the owner's."),
    "plan-wave": _job(
        (FABLE, "high"), (OPUS, "medium"), None, "a builder's read of the plan, flagging gaps",
        "Plan for a multi-system wave: a plan mistake costs a whole wave."),
    "plan-fix": _job(
        (OPUS, "medium"), None, None, "the fix's own review",
        "Plan for a one-file fix: cheap to redo."),
    "review": _job(
        (FABLE, "xhigh"), None, None, "confirmed findings only, each with a failing check",
        "Reviews of a wave (3-lens, release): the law."),
    "test-fix": _job(
        (OPUS, "medium"), None, "medium", "the suite re-checks it",
        "Test fix, only a fixture or a timing: everything else the suite re-checks."),
    "test-fix-assertion": _job(
        (OPUS, "medium"), (FABLE, "high"), "medium", "the suite + the review of the assertion",
        "Test fix that changes an assertion: weakening one is the one way a test fix lowers quality."),
    "log-reading": _job(
        (HAIKU, "medium"), None, None, "re-reading the log; Opus medium if a cause is asked",
        "Log reading: a mechanical first pass that names the failing scenarios and the first error line."),
    "doc-update": _job(
        (SONNET, "medium"), None, "easy", "p2final_docs",
        "Doc updates a test reads: the test catches a wrong number."),
    "ledger": _job(
        (SONNET, "low"), None, "easy", "the next reader",
        "Ledger, brain, BUILD_STATE, bug-inbox notes: a wrong line misleads one session, not a player."),
    "merge-gate": _job(
        (FABLE, "high"), None, None, "full run_checks.sh, rbxlx + verify_place.py",
        "Merge gates: judging; reads only the failure summary and decides merge or no merge.",
        up=["hard-to-undo"]),
    "upload": _job(
        (OPUS, "medium"), None, None, "the owner's OK first, the dry run, the tool's own checks",
        "Uploads: the tool does the work; it is irreversible, so the OK and the dry run stay, not the model.",
        up=["hard-to-undo"]),
    "website": _job(
        (OPUS, "medium"), None, "medium", "Chrome screenshots at phone + desktop width",
        "Website work on Bosco: a mistake shows in the browser and there is no live data."),
    "website-copy": _job(
        (SONNET, "high"), None, "easy", "Chrome screenshots at phone + desktop width",
        "Bosco copy or CSS-only tweaks: a mistake shows in the browser."),
    "website-orders": _job(
        (OPUS, "high"), (FABLE, "high"), "high", "Chrome screenshots at phone + desktop width",
        "Bosco, anything that takes an order, a booking or a payment: real customers and real money."),
    "other": _job(
        (OPUS, "high"), (FABLE, "high"), "high", "a test written first",
        "A job the table does not name: the law's default, then add the flags that apply."),
}

_UP_BUILDER, _UP_REVIEWER = (OPUS, "medium"), (FABLE, "high")  # any Up item ends the cheap route (spec section 2)
_REVIEW_XHIGH = (FABLE, "xhigh")


def _flag(help_text, builder=_UP_BUILDER, reviewer=_UP_REVIEWER, counts=True, forces_ultracode=False):
    return {"help": help_text, "builder": builder, "reviewer": reviewer, "counts": counts, "forces": forces_ultracode}


# Spec section 2: the Up items. counts = it moves the whole-job level, not only the route.
FLAGS = {
    "saves": _flag("touches saves or player data", (FABLE, "high"), _REVIEW_XHIGH),
    "money": _flag("touches money or rewards", (OPUS, "high"), _REVIEW_XHIGH),
    "security": _flag("touches remote security", (OPUS, "high"), _REVIEW_XHIGH),
    "live": _flag("touches live data"),
    "hard-to-undo": _flag("hard to undo: uploads, merges to main, schema changes, anything players keep"),
    "many-systems": _flag("many systems at once: a wave with 4+ owners"),
    "failed-before": _flag("a past failure in this area"),
    "studio-only": _flag("the mock cannot see the mistake", counts=False),
    "release": _flag("a release to main with players on it", forces_ultracode=True),
    "failed-twice": _flag("a second failure in the same area", forces_ultracode=True),
}


def _join(route, floor):
    """The higher of the two on both model and effort, so nothing ever comes down on either. None = not there yet."""
    if route is None or floor is None:
        return route or floor
    return (MODELS[max(MODELS.index(route[0]), MODELS.index(floor[0]))],
            EFFORTS[max(EFFORTS.index(route[1]), EFFORTS.index(floor[1]))])


def _step(route):
    return (route[0], EFFORTS[min(EFFORTS.index(route[1]) + 1, len(EFFORTS) - 1)])


def _new_flags(kind, flags):
    """Flags the table's route does not already include. Unknown flags raise a KeyError."""
    return [FLAGS[f] for f in sorted(frozenset(flags) - JOBS[kind]["up"])]


def route(kind, flags=()):
    """The job's route. Any new Up item: one effort step up, then the floor of every flag given (spec section 2)."""
    job = JOBS[kind]
    builder, reviewer = job["builder"], job["reviewer"]
    new = _new_flags(kind, flags)
    if new:
        builder = _step(builder)
        reviewer = _step(reviewer) if reviewer else None
        judges_itself = kind in ("review", "merge-gate")
        for flag in new:
            builder = _join(builder, flag["builder"])
            if not judges_itself:
                reviewer = _join(reviewer, flag["reviewer"])
    return {"builder": builder, "reviewer": reviewer, "gate": job["gate"], "why": job["why"]}


def level(kind, flags=()):
    """The whole-job level (spec section 3), or None for a kind that is one stage of a build."""
    base = JOBS[kind]["level"]
    if not base:
        return None
    items = frozenset(flags) | JOBS[kind]["up"]
    if any(FLAGS[f]["forces"] for f in items):
        return "ultracode"
    count = sum(1 for f in items if FLAGS[f]["counts"])
    if count >= 2:
        return "ultracode"
    return "xhigh" if count == 1 else base


def stages(kind, flags=()):
    """The route of each stage of a whole build (spec sections 3 and 3.1). None for review = the gate is the review."""
    lvl = level(kind, flags)
    if not lvl:
        raise ValueError("%s is one stage of a build, not a build" % kind)
    got = route(kind, flags)
    raised = bool(_new_flags(kind, flags))
    up = _step if raised else (lambda r: r)
    plan = {"easy": None, "medium": (OPUS, "medium")}.get(lvl, (FABLE, "high"))
    plan = _join(up(plan), _REVIEW_XHIGH if lvl in ("xhigh", "ultracode") else None) if plan else got["builder"]
    build = got["builder"]
    if (frozenset(flags) | JOBS[kind]["up"]) & {"saves", "money", "security"}:
        build = _join(build, (FABLE, "high"))  # "data, security and money tasks go to Fable"
    if lvl == "ultracode":
        build = _join(build, (OPUS, "high"))
    review = _join(got["reviewer"], {"xhigh": _REVIEW_XHIGH, "ultracode": (FABLE, "max")}.get(lvl))
    gate = up((FABLE, "high")) if lvl != "easy" else got["builder"]
    return {"plan": plan, "build": build, "review": review, "fix": build, "gate": gate}


def _show(r):
    return "%s %s" % r if r else "none, the gate is the review"


def _fail_unknown(kind):
    print("unknown job kind: %s" % kind, file=sys.stderr)
    print("kinds: %s" % ", ".join(JOBS), file=sys.stderr)
    print("a job the table does not name is 'other' (Opus high, Fable high review); this tool never guesses low", file=sys.stderr)
    return 2


def print_list():
    for kind, job in JOBS.items():
        print("%-19s %-16s review: %-28s %s" % (
            kind, "%s %s" % job["builder"], _show(job["reviewer"]), LEVEL_NAMES.get(job["level"], "one stage")))


def print_job(kind, flags):
    got = route(kind, flags)
    lvl = level(kind, flags)
    print("job:      %s" % kind)
    print("model:    %s" % got["builder"][0])
    print("effort:   %s" % got["builder"][1])
    print("reviewer: %s" % _show(got["reviewer"]))
    print("gate:     %s" % got["gate"])
    print("reason:   %s" % got["why"])
    if flags:
        print("flags:    %s" % ", ".join(sorted(flags)))
    if lvl:
        print("level:    %s; ultracode: %s" % (LEVEL_NAMES[lvl], "YES" if lvl == "ultracode" else "no"))
    print(NEVER_DROPPED)


def print_build(kind, flags):
    got = stages(kind, flags)
    lvl = level(kind, flags)
    print("build of: %s%s" % (kind, " (%s)" % ", ".join(sorted(flags)) if flags else ""))
    for stage in STAGES:
        print("%-7s %s" % (stage + ":", _show(got[stage])))
    print("gate is: %s" % JOBS[kind]["gate"])
    print("level: %s" % LEVEL_NAMES[lvl])
    print("ultracode: %s" % ("YES" if lvl == "ultracode" else "no"))
    if lvl == "xhigh":
        print("also: Fable xhigh design review of the spec before the plan; full gate twice (before and after the fix round)")
    if lvl == "ultracode":
        print("also: several workflows in sequence, each with a cache; adversarial reviewers play the exploiter and the unlucky player")
        print("also: completeness critics, Fable xhigh: the contract against the diff, a list only, no fixing")
        print("also: loop until dry: fix -> Fable high re-review to zero confirmed findings, cap 3 loops (spec section 3.1)")
    print(NEVER_DROPPED)


def main():
    parser = argparse.ArgumentParser(description="Which model and effort for which job.", allow_abbrev=False)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--list", action="store_true", help="print every job kind")
    mode.add_argument("--job", metavar="KIND", help="print the model, effort and reason for one job")
    mode.add_argument("--build", metavar="KIND", help="print each stage of a whole build and whether it runs as ultracode")
    for name, flag in FLAGS.items():
        parser.add_argument("--" + name, dest="flags", action="append_const", const=name, help=flag["help"])
    args = parser.parse_args()
    flags = frozenset(args.flags or ())
    if args.list:
        print_list()
        return 0
    kind = args.job or args.build
    if kind not in JOBS:
        return _fail_unknown(kind)
    if args.build and not JOBS[kind]["level"]:
        print("%s is one stage of a build, not a build: use --job %s" % (kind, kind), file=sys.stderr)
        return 2
    (print_job if args.job else print_build)(kind, flags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
