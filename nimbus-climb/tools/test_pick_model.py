#!/usr/bin/env python3
"""Offline tests of tools/pick_model.py (the model and effort router). Exit code 0 = all passed.

    py -3.12 tools/test_pick_model.py
"""
import itertools
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pick_model as P  # noqa: E402

SCRIPT = os.path.join(HERE, "pick_model.py")
FABLE, OPUS, SONNET, HAIKU = "Fable 5.1", "Opus 5.5", "Sonnet 5.5", "Haiku 5.5"
ALL_FLAGS = sorted(P.FLAGS)
STAGES = ("plan", "build", "review", "fix", "gate")
BUILD_KINDS = [k for k, j in P.JOBS.items() if j["level"]]


def flag_sets():
    """Every kind against no flag, each flag alone and each pair (the full power set adds nothing but minutes)."""
    return [frozenset(c) for n in (0, 1, 2) for c in itertools.combinations(ALL_FLAGS, n)]


def rank(route):
    return P.MODELS.index(route[0]), P.EFFORTS.index(route[1])


def at_least(route, floor):
    """Both dimensions: a higher model does not excuse a lower effort."""
    return rank(route)[0] >= rank(floor)[0] and rank(route)[1] >= rank(floor)[1]


def run(*args):
    return subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)


class RealValues(unittest.TestCase):
    def test_models_and_efforts_are_the_real_ones(self):
        self.assertEqual(P.MODELS, (HAIKU, SONNET, OPUS, FABLE))
        self.assertEqual(P.EFFORTS, ("low", "medium", "high", "xhigh", "max"))

    def test_every_route_is_a_real_model_and_effort(self):
        for kind in P.JOBS:
            for flags in flag_sets():
                got = P.route(kind, flags)
                for r in (got["builder"], got["reviewer"]):
                    if r is not None:
                        self.assertIn(r[0], P.MODELS, kind)
                        self.assertIn(r[1], P.EFFORTS, kind)
                if P.JOBS[kind]["level"]:
                    for stage, r in P.stages(kind, flags).items():
                        if r is not None:
                            self.assertIn(r[0], P.MODELS, (kind, stage))
                            self.assertIn(r[1], P.EFFORTS, (kind, stage))

    def test_every_job_says_why_and_how_a_mistake_is_caught(self):
        for kind, job in P.JOBS.items():
            self.assertTrue(job["why"], kind)
            self.assertTrue(job["gate"], kind)

    def test_the_spec_table_as_written(self):
        expected = {
            "game-feature": ((OPUS, "high"), (FABLE, "high")),
            "saves": ((FABLE, "high"), (FABLE, "xhigh")),
            "money": ((FABLE, "high"), (FABLE, "xhigh")),
            "security": ((FABLE, "high"), (FABLE, "xhigh")),
            "balance": ((OPUS, "medium"), (FABLE, "medium")),
            "effects-gui": ((OPUS, "high"), (FABLE, "medium")),
            "pitch": ((FABLE, "high"), None),
            "blender": ((OPUS, "high"), None),
            "plan-wave": ((FABLE, "high"), (OPUS, "medium")),
            "plan-fix": ((OPUS, "medium"), None),
            "review": ((FABLE, "xhigh"), None),
            "test-fix": ((OPUS, "medium"), None),
            "test-fix-assertion": ((OPUS, "medium"), (FABLE, "high")),
            "log-reading": ((HAIKU, "medium"), None),
            "doc-update": ((SONNET, "medium"), None),
            "ledger": ((SONNET, "low"), None),
            "merge-gate": ((FABLE, "high"), None),
            "upload": ((OPUS, "medium"), None),
            "website": ((OPUS, "medium"), None),
            "website-copy": ((SONNET, "high"), None),
            "website-orders": ((OPUS, "high"), (FABLE, "high")),
            "other": ((OPUS, "high"), (FABLE, "high")),
        }
        self.assertEqual(set(expected), set(P.JOBS))
        for kind, (builder, reviewer) in expected.items():
            got = P.route(kind, ())
            self.assertEqual((got["builder"], got["reviewer"]), (builder, reviewer), kind)


class RaisingNeverLowers(unittest.TestCase):
    def test_adding_a_flag_never_lowers_a_route(self):
        for kind in P.JOBS:
            for flags in flag_sets():
                for extra in ALL_FLAGS:
                    before, after = P.route(kind, flags), P.route(kind, flags | {extra})
                    for role in ("builder", "reviewer"):
                        if before[role] is None:
                            continue
                        self.assertIsNotNone(after[role], (kind, flags, extra, role))
                        self.assertTrue(at_least(after[role], before[role]), (kind, flags, extra, role))

    def test_adding_a_flag_never_lowers_a_build(self):
        for kind in BUILD_KINDS:
            for flags in flag_sets():
                for extra in ALL_FLAGS:
                    before, after = P.stages(kind, flags), P.stages(kind, flags | {extra})
                    for stage in STAGES:
                        if before[stage] is None:
                            continue
                        self.assertIsNotNone(after[stage], (kind, flags, extra, stage))
                        self.assertTrue(at_least(after[stage], before[stage]), (kind, flags, extra, stage))
                    self.assertGreaterEqual(
                        P.LEVELS.index(P.level(kind, flags | {extra})), P.LEVELS.index(P.level(kind, flags)),
                        (kind, flags, extra))

    def test_one_new_flag_moves_the_builder_up_a_step(self):
        for flag in ALL_FLAGS:
            self.assertEqual(P.route("game-feature", {flag})["builder"][1], "xhigh", flag)

    def test_a_flag_the_job_already_is_changes_nothing(self):
        for kind in ("saves", "money", "security"):
            self.assertEqual(P.route(kind, {kind}), P.route(kind, ()), kind)

    def test_any_up_item_ends_the_cheap_route(self):
        # spec section 2: a job on the Up list never goes down, and Sonnet / Haiku are the down routes
        for kind in P.JOBS:
            for flags in flag_sets():
                if flags:
                    self.assertIn(P.route(kind, flags)["builder"][0], (OPUS, FABLE), (kind, flags))

    def test_a_raised_job_with_no_reviewer_gets_one(self):
        for kind in ("doc-update", "log-reading", "test-fix", "website"):
            self.assertEqual(P.route(kind, {"live"})["reviewer"], (FABLE, "high"), kind)

    def test_raising_never_loses_the_gate(self):
        for kind in P.JOBS:
            for flags in flag_sets():
                self.assertEqual(P.route(kind, flags)["gate"], P.JOBS[kind]["gate"], kind)


class Floors(unittest.TestCase):
    FLOORS = {
        "saves": ((FABLE, "high"), (FABLE, "xhigh")),
        "money": ((FABLE, "high"), (FABLE, "xhigh")),
        "security": ((FABLE, "high"), (FABLE, "xhigh")),
    }

    def test_those_jobs_never_route_below_the_floor(self):
        for kind, (builder, reviewer) in self.FLOORS.items():
            for flags in flag_sets():
                got = P.route(kind, flags)
                self.assertTrue(at_least(got["builder"], builder), (kind, flags))
                self.assertTrue(at_least(got["reviewer"], reviewer), (kind, flags))

    def test_a_flag_brings_the_floor_to_any_job(self):
        for flag, (builder, reviewer) in self.FLOORS.items():
            for kind in P.JOBS:
                for flags in flag_sets():
                    got = P.route(kind, flags | {flag})
                    self.assertTrue(at_least(got["builder"], builder), (kind, flag, flags))
                    if got["reviewer"] is not None:
                        self.assertTrue(at_least(got["reviewer"], reviewer), (kind, flag, flags))

    def test_their_review_is_fable_at_every_level(self):
        for kind in self.FLOORS:
            for flags in flag_sets():
                self.assertEqual(P.route(kind, flags)["reviewer"][0], FABLE, (kind, flags))
                self.assertEqual(P.stages(kind, flags)["review"][0], FABLE, (kind, flags))
        for flag in self.FLOORS:
            for kind in BUILD_KINDS:
                self.assertEqual(P.stages(kind, {flag})["review"][0], FABLE, (kind, flag))
            self.assertEqual(P.route("review", {flag})["builder"][0], FABLE, flag)

    def test_their_build_stage_goes_to_fable(self):
        # spec section 3 and 3.1: data, security and money tasks go to Fable in a whole build
        for kind in self.FLOORS:
            self.assertEqual(P.stages(kind, ())["build"], (FABLE, "high"), kind)

    def test_a_stage_picked_with_job_matches_the_same_stage_of_a_build(self):
        for kind in self.FLOORS:
            for flags in flag_sets():
                self.assertEqual(P.route(kind, flags)["builder"][0], P.stages(kind, flags)["build"][0], (kind, flags))


class Levels(unittest.TestCase):
    def test_the_named_levels(self):
        self.assertEqual(P.level("doc-update", ()), "easy")
        self.assertEqual(P.level("balance", ()), "medium")
        self.assertEqual(P.level("game-feature", ()), "high")
        for kind in ("saves", "money", "security"):
            self.assertEqual(P.level(kind, ()), "xhigh", kind)

    def test_one_up_item_is_xhigh_and_two_are_ultracode(self):
        self.assertEqual(P.level("game-feature", {"many-systems"}), "xhigh")
        self.assertEqual(P.level("game-feature", {"many-systems", "live"}), "ultracode")
        self.assertEqual(P.level("saves", {"many-systems"}), "ultracode")
        self.assertEqual(P.level("saves", {"saves"}), "xhigh")

    def test_saves_money_security_and_live_data_are_one_up_item(self):
        # spec section 2: they are one bullet, so together they are still one item (Extra high)
        live_data = ("saves", "money", "security", "live")
        for a, b in itertools.combinations(live_data, 2):
            self.assertEqual(P.level("game-feature", {a, b}), "xhigh", (a, b))
        self.assertEqual(P.level("game-feature", set(live_data)), "xhigh")
        for kind in ("saves", "money", "security"):
            for flag in live_data:
                self.assertEqual(P.level(kind, {flag}), "xhigh", (kind, flag))

    def test_the_spec_ultracode_examples_are_still_ultracode(self):
        self.assertEqual(P.level("money", {"live", "many-systems"}), "ultracode")  # the Robux shop
        self.assertEqual(P.level("saves", {"hard-to-undo", "many-systems"}), "ultracode")  # a save-schema change
        self.assertEqual(P.level("saves", {"hard-to-undo"}), "ultracode")  # a schema change is its own Up item
        self.assertEqual(P.level("game-feature", {"hard-to-undo", "release"}), "ultracode")  # a long-lived merge

    def test_a_release_or_a_second_failure_is_ultracode_alone(self):
        self.assertEqual(P.level("game-feature", {"release"}), "ultracode")
        self.assertEqual(P.level("game-feature", {"failed-twice"}), "ultracode")

    def test_studio_only_raises_the_route_but_not_the_level(self):
        # spec section 3.1: for sky, VFX and HUD the owner's Studio check is the test; ultracode is no safer there
        self.assertEqual(P.level("effects-gui", {"many-systems"}), "xhigh")
        self.assertEqual(P.level("game-feature", {"studio-only"}), "high")
        self.assertEqual(P.route("effects-gui", {"studio-only"}), P.route("effects-gui", ()))

    def test_a_wave_gets_the_wave_review(self):
        # spec table "Reviews of a wave": --build game-feature and --job review give one answer
        self.assertEqual(P.stages("game-feature", ())["review"], P.route("review", ())["builder"])
        self.assertEqual(P.route("game-feature", ())["reviewer"], (FABLE, "high"))  # one task's review stays as the table says

    def test_a_kind_that_names_its_own_review_keeps_it(self):
        self.assertEqual(P.stages("effects-gui", ())["review"], (FABLE, "medium"))
        self.assertEqual(P.stages("balance", ())["review"], (FABLE, "medium"))
        self.assertEqual(P.stages("website-orders", ())["review"], (FABLE, "high"))
        self.assertEqual(P.stages("other", ())["review"], (FABLE, "high"))
        self.assertIsNone(P.stages("blender", ())["review"])

    def test_ultracode_stages_have_the_spec_floors(self):
        got = P.stages("saves", {"many-systems"})
        self.assertEqual(got["review"], (FABLE, "max"))
        self.assertTrue(at_least(got["plan"], (FABLE, "xhigh")))
        self.assertTrue(at_least(got["fix"], (OPUS, "high")))
        self.assertTrue(at_least(got["gate"], (FABLE, "high")))

    def test_stage_only_kinds_are_not_builds(self):
        for kind, job in P.JOBS.items():
            if not job["level"]:
                with self.assertRaises(ValueError, msg=kind):
                    P.stages(kind, ())


class CommandLine(unittest.TestCase):
    def test_list_prints_every_kind(self):
        out = run("--list")
        self.assertEqual(out.returncode, 0, out.stderr)
        for kind in P.JOBS:
            self.assertRegex(out.stdout, r"(?m)^%s\b" % kind)

    def test_job_prints_model_effort_and_reason(self):
        out = run("--job", "saves")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("model:    Fable 5.1", out.stdout)
        self.assertIn("effort:   high", out.stdout)
        self.assertIn(P.JOBS["saves"]["why"], out.stdout)

    def test_flags_reach_the_route(self):
        self.assertIn("effort:   xhigh", run("--job", "game-feature", "--many-systems").stdout)
        self.assertIn("model:    Fable 5.1", run("--job", "doc-update", "--saves").stdout)

    def test_every_flag_exists_on_the_command_line(self):
        for flag in ALL_FLAGS:
            out = run("--job", "game-feature", "--" + flag)
            self.assertEqual(out.returncode, 0, (flag, out.stderr))
            self.assertIn(flag, out.stdout)

    def test_build_prints_each_stage_and_the_ultracode_answer(self):
        out = run("--build", "game-feature", "--many-systems")
        self.assertEqual(out.returncode, 0, out.stderr)
        for stage in STAGES:
            self.assertRegex(out.stdout, r"(?m)^%s:" % stage)
        self.assertIn("ultracode: no", out.stdout)
        self.assertIn("ultracode: YES", run("--build", "saves", "--many-systems").stdout)

    def test_ultracode_prints_its_extra_stages(self):
        out = run("--build", "saves", "--many-systems").stdout
        self.assertIn("completeness critics", out)
        self.assertIn("loop until dry", out)

    def test_unknown_kind_fails_and_lists_the_kinds(self):
        for mode in ("--job", "--build"):
            out = run(mode, "not-a-kind")
            self.assertNotEqual(out.returncode, 0, mode)
            self.assertEqual(out.stdout, "", "an unknown kind must print no route")
            for kind in P.JOBS:
                self.assertIn(kind, out.stderr)

    def test_a_build_of_a_stage_only_kind_fails(self):
        self.assertNotEqual(run("--build", "review").returncode, 0)

    def test_no_abbreviated_flags(self):
        self.assertNotEqual(run("--job", "ledger", "--sav").returncode, 0)

    def test_nothing_asked_fails(self):
        self.assertNotEqual(run().returncode, 0)


if __name__ == "__main__":
    unittest.main()
