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
- 2026-11-07: the lobby shop (branch `lobby-shop`, spec `docs/superpowers/specs/2026-11-07-lobby-shop-design.md` with the
  owner's pitch answers in its section 16, plan `docs/superpowers/plans/2026-11-07-lobby-shop.md`): every roulette spin
  hatches the egg of its rarity in a GUI-only cutscene (x1 / x3, Skip from the first frame, Fast hatch; the camera and
  the character are never touched); one Shop window with a tab rail (Eggs, Gems, Packs, Passes, Boosts; the Robux Store
  merged in, StoreController only forwards) opened from the pill, the walk-up Egg Guide prompt and the machines; the
  owner's gem prices (spins 20 / 40 / 60 / 180, the Secret Roulette 500 at Mythic 60 / Secret 40 with the 7th-spin pity,
  Celestial 2 % Secret); token-granting Robux products never sold to accounts restricted from paid random items; gems
  drawn as cut gems (`UI/GemIcon`); the Sky Trove at spot C; a global leaderboard (Trophies, Pets found, Ring best) and
  server-written titles (Top 10, Top 100, Creator = `DevService.IsOwner` only) with a Rank column; the altar portals lit.
  No save session lock in this build (the 15 s gem settle hold covers gems). Details in `BUILD_STATE.md`.
- 2026-11-08: the roll look (branch roll-look, spec 16.15 "Roll look A+B", plan docs/superpowers/plans/2026-11-08-roll-look.md): the owner's pick A "Showcase" + B's colour tell (Rare+), B's silhouette (Legendary+, +0.3 s), Gemini's shake tint (Rare+), clutter caps; the HUD hides during the stage; the pedestal drum stays removed (a flat lit plinth instead).
- 2026-11-09: the shop area (branch shop-area, spec 16.17, plan docs/superpowers/plans/2026-11-09-shop-area.md): the owner's picks A "Gumball Globe" (one mesh, real small eggs inside; until its upload every machine keeps today's uploaded cabinet `prop_roulette`, review round 1), the egg row under WINGED PETS (Egg Guide gone), the Secret roll only at the Storm Altar (prompt "Secret Roll", a server distance rule, the Shop card "Available at the Storm Altar" + Travel), the World gem over the side crystal (spot 2).
- 2026-11-10: the save session lock (branch session-lock, spec docs/superpowers/specs/2026-11-10-session-lock-design.md, plan docs/superpowers/plans/2026-11-10-session-lock.md; the owner's "Q2 full save session lock: YES" of 2026-11-08): one server owns a save at a time (a Lock key inside the record, claimed at load, refreshed by every save, released at leave / BindToClose, stale after 360 s); another server waits up to 12 s, then plays a stand-in save until the lock frees; the 15 s gem settle hold is retired into the lock's flag (GemsSettled = OwnsSave). No kick. Details in `BUILD_STATE.md`.
