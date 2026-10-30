# Nimbus Climb brain (source of truth)

Read with [`ABSOLUTE_RULES.md`](ABSOLUTE_RULES.md) before working.

## Where the truth lives
- Current build state and settled player decisions: [`BUILD_STATE.md`](BUILD_STATE.md).
- Design and build contracts: [`ARCHITECTURE_V3.md`](ARCHITECTURE_V3.md) (V1/V2 are history).
- Player and editor guide: [`README.md`](README.md). Checks: [`tools/README.md`](tools/README.md) (`tools/run_checks.sh`).
- Claude setup and skill pack: [`claude-setup/`](claude-setup/); skills are unpacked in `.claude/skills/`.

## Decisions (dated)
- 2026-10-20: ART RULE, Blender models only (see ARCHITECTURE_V3 "ART RULE").
- 2026-10-22: `claude-setup/CLAUDE_SYSTEM_SETUP.md` adopted as the standing rules for this project ("the bible").
  Its step-4 rules live in `ABSOLUTE_RULES.md`; its skill pack is unpacked into `.claude/skills/`.
- 2026-10-30: Gemini fallback (owner's rule). If the Gemini API key fails (e.g. 402 "prepayment credits are depleted"),
  use Gemini through the owner's Google account (AI Pro plan): gemini-cli "Login with Google" (the owner signs in once,
  interactively). Model stays "gemini-pro-latest", prompts on one line. Never open the Gemini desktop app from an agent.
