# Pitch 2 Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the 15 owner-approved Pitch 2 items on kit-b so every UI looks finished, sharp and well made, in 3 waves, and re-pitch the phone battle buttons.

**Architecture:** One kit-wide finish pass lands first, in the shared kit modules, because every other item builds on it. After it, independent lanes run on their own branches cut from kit-b (`kitb-p2-<lane>`, worktrees under `.worktrees/`). Lanes are cut so no two of them edit the same file in the same wave. Each lane goes build, then look review, then fix (at most 1 round), then merge into kit-b. Each wave ends with one full suite run.

**Tech Stack:** Roblox Luau via Rojo 7.7.1; the Python smoke mock (`tools/smoke.py`), `tools/render_gui.py`, `tools/render_model.py`, `tools/stroke_walk.py`; PIL for the pixel sheets.

**Spec:** `docs/superpowers/specs/2026-11-20-pitch2-build-design.md`. Each item there is the approved option: its text, numbers, mock-up path and build notes. The mock-ups are in `.superpowers/slop-audit/round3/build/PITCH2/<group>/`, and the scripts that drew them sit next to them.

## Global Constraints

- Kit B rules hold everywhere:
  - SignKit / CloudUI / PixelIcon / BlockRow, and FredokaOne through Theme.
  - The gold ribbon goes on window titles only.
  - No neon glow, no rounded corners, no gradients, no emoji.
  - One green action per window.
  - Controls stay clear of Roblox touch zones, with touch targets of at least 44 px on screen.
- Behaviour stays the same unless an item changes it. The items that change behaviour are 13 (Travel guides instead of teleporting), 12 (Elements opens a window) and 5 (melee motion).
- Testing:
  - Targeted lists only, one at a time, with `py -3.12 tools/smoke.py --quick --only <lists>`. Never use smoke_parallel.
  - The whole suite (`--quick`, then `--quick --mesh`) runs once at the end of each wave, inside the agent, which waits for the final "smoke test:" line.
  - Every changed check is red first, then green. Never weaken a check without writing the reason in the test.
- Git:
  - Work in `.worktrees/kit-b` or a lane worktree. Push only kit-b and the lane branches.
  - Never push main, quick-wins or integration. No bare `git stash`.
  - Commits end with the Co-Authored-By and Claude-Session lines.
- Never touch Roblox Studio and never upload from this PC.
- Uploads:
  - The upload sheets (icon set B, roulette machines, boss heads) go to `build/upload_sheets/` with a manifest. They are handed to the owner's keyed cloud session.
  - Until the asset ids exist, the code falls back to the current art. The fallback is tested.
- Every lane renders `render_gui.py --grid` at 1920x1080, 1280x720, 844x390 and 390x844, and compares the result with the item's mock-up before the look review.

## Review Focus

1. **Finish pass sizes:** the finish pass (shadow, inner lines, press sink) changes kit part sizes, which can push windows that fit today into clipping or overlap. Every family's `*_fits*` list and `kitb_whole_pixels` must stay green after Task 1. Task 1 runs all of them.
2. **Missing upload ids:** with no asset id configured, every icon, machine and boss head draws the fallback with no error and no empty box. A smoke check per sheet in Tasks 6 and 7 covers this.
3. **Travel guide edge cases:** the guide is started from outside the lobby, started again while it's already running, or cancelled by the player walking into a portal. It must end cleanly with no leftover beam or chip. Task 9 covers this.
4. **Long numbers and names:** 1.01B, 999.9K, and 20-character names in the result card B, the boss bar and the vitals tab must fit. Tasks 2 and 3 test the worst cases.
5. **Melee motion at fast tempo:** Thorns, DoubleStrike and flurry hits at the fast tempo must land on the server's hit time, and the pet must never end off its spot. Task 11 tests the timing against the server clock.

---

## Wave 1

### Task 1: Finish pass A (kit-wide), lands alone first
**Files:** `src/shared/Theme.lua`, `src/shared/SignKit.lua`, `src/client/UI/CloudUI.lua`, and the shared number formatter (find the existing short-number helper; if there are several, merge them into one). Tests: `tools/smoke_kitb_ui.lua`.
**Produces:** the kit rules in spec item F0 option A: lit and dark inner lines on wood edges, the offset shadow block, sunk wells, the press feel, the open tween, and one short-number formatter `Theme.Short(n) -> string` (3 significant figures with K / M / B) used by the HUD, cards, the shop and damage numbers.
- [ ] Add the failing checks `finish_pass_kit` (every SignKit frame has the inner lines and the shadow per spec) and `short_numbers` (`Theme.Short(20628)=="20.6K"`, `Theme.Short(1010000)=="1.01M"`, `Theme.Short(999)=="999"`, `Theme.Short(1234567890)=="1.23B"`).
- [ ] Run them and confirm they fail.
- [ ] Implement it in the kit modules, then route every short-number site through `Theme.Short`.
- [ ] Run every `*_fits*`, `*_signboard_skin`, `kitb_*` list, plus `stroke_walk.py --grid --neon`. All must be green.
- [ ] Render Shop / Daily / Pets / Index at 4 sizes and compare them with `F_overall_finish/F0_finish_optA*.png`.
- [ ] Commit and push kit-b.

### Task 2: Battle lane: boss bar A + result card B + vitals C (branch kitb-p2-battle)
**Files:** `src/client/Controllers/BattleController.lua` (TopCard, the result card), `HudController.lua` (the vitals card), `CloudUI.lua` only through Task 1's API. Tests: `tools/smoke_kitb_ui.lua`, plus the battle lists.
**Consumes:** Task 1's `Theme.Short`.
- [ ] Add the failing checks:
  - `battle_topcard_one_card`: mode, timer, Leave and boss HP sit inside one card; HP shows as blocks with "27.6K / 50K" inside the track; the pills are inside the card or wrap on portrait.
  - `result_card_template_b`: VICTORY / RUN OVER / THE BOSS WON / dungeon share one template; OK sits inside the card; chips are equal width; nothing sticks out at 4 sizes, with 20-character names and 1.01B.
  - `vitals_name_tab`: the name tab shows DisplayName + trophies; HP number in the bar; stamina + dash grouped; no level shown.
- [ ] Run them and confirm they fail.
- [ ] Implement it per spec items 06 A, 02 B and 08 C. The boss head portrait reads an image id from Config, and with no id the card is still complete.
- [ ] Run `battle_family_fits`, `results_card_kitb`, `client_p5result`, `client_raid_*`, `client_p5hud_*`, `vitals_*`, `hud_strips_clear_of_panel`, `kitb_windows_clear_of_hud` and the 3 new checks: all green.
- [ ] Render at 4 sizes, look review, then fix (at most 1 round).
- [ ] Merge into kit-b and push.

### Task 3: Windows lane: elements A + index badge B + daily B + tutorial dock B (branch kitb-p2-windows)
**Files:** the Index window controller (Elements section to a new centred window), the Daily window controller, `TutorialController.lua` (dock). Tests: `tools/smoke_kitb_ui.lua` and the family lists.
- [ ] Add the failing checks:
  - `elements_window`: a button opens a centred kit window with a title and X; all elements show at once; big arrows labelled x1.5 / x0.75; Esc and X close it; no scrolling at 4 sizes.
  - `index_badge_clear`: the "!" badge never overlaps a tile title; no strip label cut.
  - `daily_layout_b`: no empty band over 24 px; the Day 7 pet fills at least 60 % of its tile.
  - `tutorial_dock_b`: the minimised tutorial sits where spec 03 B says, with a tap target of at least 44 px.
- [ ] Run them and confirm they fail.
- [ ] Implement it per the spec.
- [ ] Run `index_*`, `daily_*`, `tutorial_*`, `client_daily_*`, `client_p2ui*` and the new checks: all green.
- [ ] Render, look review, then fix (at most 1 round).
- [ ] Merge into kit-b and push.

### Task 4: Re-pitch item 1, phone battle buttons (runs alongside Tasks 2-3, no code)
- [ ] Make 3 new options that cover less of the screen and are easier to read. Ideas to show: fewer visible buttons with contextual swaps, smaller ghost buttons until used, one radial / thumb arc. Draw them over a real 390x844 and 844x390 battle scene; each option must state how much of the screen it covers.
- [ ] Add them to the pitch page as a new item, with the owner's note quoted.

### Task 5: Wave 1 gate
- [ ] Run the whole suite and the mesh suite on kit-b. Both: 0 failed.
- [ ] I look at the contact sheets myself, then log in the ledger.

## Wave 2

### Task 6: Icons B: code side + upload sheet (branch kitb-p2-icons)
**Files:** `src/client/UI/PixelIcon.lua` (a sheet-backed ImageLabel path at art size; the 9x9 glyph path stays), Config (icon sheet id, default 0), `tools/` (the sheet builder script, from `C_icons_machines` scripts). Output: `build/upload_sheets/icons_b.png` + `.json` (cell rects).
- [ ] Add the failing checks: `icons_sheet_fallback` (id 0: every icon draws through the 9x9 path, no error) and `icons_sheet_rects` (with a fake id, each icon is an ImageLabel with the sheet's rect and ResampleMode Pixelated).
- [ ] Run them and confirm they fail.
- [ ] Implement it, and redraw the 9x9 glyphs in the B style per spec 9.
- [ ] Run `pixelicon_*`, `token_icon_everywhere`, `kitb_no_emoji_ui`, the shop and daily lists and the new checks: all green.
- [ ] Render, look review, then fix. Merge and push. Log the sheet path for the upload hand-over.

### Task 7: Machines A (inside the icons lane, after Task 6)
**Files:** the Shop roulette card code; Config (machine sheet id); `build/upload_sheets/machines_a.png`.
- [ ] Add the failing checks `machines_fallback` (id 0: today's machine) and `machines_sheet` (fake id: each roulette shows its own cell, the Secret one 60x68).
- [ ] Run them and confirm they fail, then implement.
- [ ] Run the shop lists: all green.
- [ ] Render, review, merge.

### Task 8: World lane: world UI B + Travel guide A (branch kitb-p2-world)
**Files:**
- NPC sign / prompt / place board / pet tag / damage number builders (the server builders and client controllers named in spec 04's build notes).
- `TutorialController.lua` GuideArrow / GuideTrail, exposed as a reusable `Guide.Start(targetName) / Guide.Stop()`.
- `ShopController.lua` Travel → "Show the way".
**Produces:** `Guide.Start(target: string): boolean`, `Guide.Stop(): ()`.
- [ ] Add the failing checks:
  - `world_signs_kit`: no navy capsule signs; the stars badge never overlaps the level tag.
  - `damage_numbers_short`: uses `Theme.Short`.
  - `travel_shows_way`: no teleport; the guide starts; the chip has an X that stops it; it ends on arrival; started outside the lobby it routes to the portal; a second start replaces the first; nothing is left behind.
- [ ] Run them and confirm they fail, then implement.
- [ ] Run `kitb_no_emoji_world`, `kitb_world_*`, `polish_worldtext`, `lobby*`, the tutorial lists and the new checks: all green.
- [ ] Render, review, then fix. Merge and push.

### Task 9: Sky lane: day fade C (branch kitb-p2-sky)
**Files:** `src/client/Controllers/SkyController.lua`, LightingService (per-phase Atmosphere values from spec F11 C).
- [ ] Add the failing check `sky_fade_clear`: at every blend step Haze ≤ the spec's cap and Density ≤ the spec's cap; the sky and light carry the tint.
- [ ] Run it and confirm it fails, then implement.
- [ ] Run `sky_*`, `client_sky_*`, `skycontroller_*`, `lightingservice_*`: all green.
- [ ] The look check is done in Studio with the owner (no 3D renderer). Merge and push.

### Task 10: Wave 2 gate
- [ ] Run the whole suite and the mesh suite: 0 failed.
- [ ] Prepare the upload hand-over list (sheets, sizes, Config keys), then log in the ledger.

## Wave 3

### Task 11: Motion lane: melee "Bounce in" A, base + evolved (branch kitb-p2-motion)
**Files:** `src/client/Controllers/AttackFx.lua`, `PetPoses` (hop poses), the BattleController melee dash. Server timing is unchanged.
- [ ] Add the failing check `melee_bounce_timing`: wind-up, hop, hop-bite, chomp and 2 hops back land on the spec's beats; the hit frame equals the server Hit time for one bite and for the fast tempo with DoubleStrike + Thorns; the pet ends exactly on its spot; there is no frame with sliding (horizontal motion while grounded).
- [ ] Run it and confirm it fails, then implement for base and evolved forms.
- [ ] Run `client_feel_*`, `client_afx_*`, `feel_*`, `client_p5battle*`, `client_evo_*`: all green.
- [ ] Render a GIF with render_model and compare it with `05_melee_motion_optA`. Review, merge.

### Task 12: Eyes lane: evolved eyes A, Trim -25 % (branch kitb-p2-eyes)
**Files:** `src/shared/PetBuilder.lua` `EYE_MASKS.Evo` / `EvoFierce` (6x7, fierce 6x5). `EVO.Face` offsets stay as they are on purpose: the new masks are padded to the shipped 8x9 / 8x7 grids (spec item 7 build notes), so the eye stays centred on today's spot with no offset change. `EvoLow` / `EvoFierceLow` (4x4) are unchanged too.
- [ ] Add the failing check `evo_eye_size`: the evolved eye masks are 6x7 and every evolved pet still has 2 eyes inside the head.
- [ ] Run it and confirm it fails, then implement.
- [ ] Run `petbuilder`, `evolved`, `p3evo_pets`, `client_p6pets`, `--mesh`: all green.
- [ ] Render the 9 pets from the sheet and compare with `07_evolved_eyes_optA`. Merge.
- [ ] Owner's call, not done from a PC: all 98 evolved body keys (`evo1_*` / `evo2_*`, High and `_low`) have MeshIds, so the arena shows the baked mesh with the old eyes until they are re-baked (export build) and uploaded in the keyed cloud session. Hand-off: `build/upload_sheets/evo_eyes_rebake.json` + `evo_eyes_rebake_preview.png`.

### Task 13: Wave 3 gate + Studio check
- [ ] Run the whole suite and the mesh suite: 0 failed.
- [ ] Build a fresh local place file. Studio check with the owner, then log in the ledger.
