# Nimbus Climb brain (source of truth)

Read with [`ABSOLUTE_RULES.md`](ABSOLUTE_RULES.md) before working.

## Where the truth lives
- Current build state and settled player decisions: [`BUILD_STATE.md`](BUILD_STATE.md).
- Design and build contracts: [`ARCHITECTURE_V3.md`](ARCHITECTURE_V3.md) (V1/V2 are history).
- Player and editor guide: [`README.md`](README.md). Checks: [`tools/README.md`](tools/README.md) (`tools/run_checks.sh`).
- Claude setup and skill pack: [`claude-setup/`](claude-setup/); skills are unpacked in `.claude/skills/`.
- Saved for a later build (Robux shop, passes, packs, skins, equipment, mounts): [`docs/superpowers/specs/2026-10-31-shop-roadmap.md`](docs/superpowers/specs/2026-10-31-shop-roadmap.md).

## Decisions (dated)
- 2026-10-20: ART RULE, Blender models only (see ARCHITECTURE_V3 "ART RULE").
- 2026-10-22: `claude-setup/CLAUDE_SYSTEM_SETUP.md` adopted as the standing rules for this project ("the bible").
  Its step-4 rules live in `ABSOLUTE_RULES.md`; its skill pack is unpacked into `.claude/skills/`.
- 2026-10-30: Gemini fallback (owner's rule). If the Gemini API key fails (e.g. 402 "prepayment credits are depleted"),
  use Gemini on the web (gemini.google.com) through Claude in Chrome, where the owner's Google account (AI Pro plan)
  is already signed in. Paste the prompt there and read the reply. Never open the Gemini desktop app from an agent.
- 2026-10-31: the speed scout (owner's rule, `ABSOLUTE_RULES.md`): always search for a way to make progress quicker without affecting the build or its quality.
  First use: the team-balance build ran its Pets window and loss screen side by side, since the two share almost no files.
- 2026-11-01: the model and effort router (owner's rule): `docs/superpowers/specs/2026-11-01-model-effort-router.md` says which
  model (Fable / Opus / Sonnet / Haiku) and effort (low .. max) each job kind gets, what moves a job up or down, and when a whole
  job runs easy / medium / high / xhigh / ultracode. Ultracode is a way of running a job (several workflows, adversarial
  verification, completeness critics, loop until dry), not an effort value; it is kept for saves / money / security / releases.
- 2026-11-01: the router is a program too (owner's rule): `tools/pick_model.py` holds that table as data and is asked before each stage of a build; `tools/test_pick_model.py` keeps its floors.
- 2026-11-07: the window redo (branch `gui-redo`, spec `docs/superpowers/specs/2026-11-06-window-redo-design.md`, the owner's approved pitch):
  Daily, Play time, Training Place and Fusion redrawn, one shared full-screen pet picker for Training and Fusion, and three
  rule changes from the owner's notes: the daily gift unlocks after 10 minutes of counted play each play-day
  (`Config.Daily.UnlockSeconds`, a hold so no streak day is lost), several pets in training shown on a mats row, and Mix lets
  the player choose which parent gives the normal attack and which the special (hybrid field `SpecialFrom`; old hybrids
  unchanged). Details in `BUILD_STATE.md`.
