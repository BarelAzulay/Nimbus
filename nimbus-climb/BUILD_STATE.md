# Phase 4 build state (read this first, instead of the whole chat)

Updated: 2026-10-18 (after wave 2). Branch `v3-phase4`. Plan: `ARCHITECTURE_V3.md` sections "Phase 4" + "Phase 4 build contract"
(incl. the "Player update" block: every pet levels to 100, evolutions at 20 / 50).

## Player decisions (all settled)
- **2026-10-20 ART RULE: Blender models only** (no Roblox Part-built / Toolbox models). See ARCHITECTURE_V3 "ART RULE".
- Evolve button; 2nd evolution only Epic+; level cap 100 for all pets (XP curve keeps rising).
- Presses become food plants, Collector = Coin Magnet, Kitchen = Food Machine, Gym = Training Place.
- Pet bars above each pet; Champion Ring needs a claimed home + 1 pet.
- Fable for the riskiest builders, Opus elsewhere; effort HIGH (player choice). Talk to the player in caveman mode.
- Gem product IDs: player has not made them yet (put them in Config.Gems.Products when sent).

## Waves
| Wave | Builders | State |
|---|---|---|
| 0 lead | contract, shared edits, fixtures | DONE (196da12, 7de086f, 7be2bb8 cap 100) |
| 1 | data (Fable), economy, battlecore | DONE (5a40987). Gate: 7466 pass, 102 known red |
| 2 | tycoon, care, battleservice (Fable); homeworld, arenaworld, pets | DONE (297c9ae). Reports: scratchpad/p4_wave2_notes.md. Lead after: data-test fixes, contract.json (Piles, SetGarden/SetTraining) |
| 3 | homefx, battleclient, careui, ui | DONE (70b04b6). Reports: scratchpad/p4_wave3_notes.md. Gate in worktree scratchpad/gate_w3 (log gate_w3.log) |
| 4 | flow, fixer, docs | DONE (wf_07cbfb76-a84, notes scratchpad/p4_wave4_notes.md; leads applied: /petlevel Refresh, COMPAT deleted). Gate w4 GREEN: 8916 pass, 0 fail (b9d875f). |
| 5 | review + verify + fix, full suite, place file, merge, send | DONE. run_checks.sh full: 9024/0. rbxlx rebuilt + verified. Merged to main (7aa0df2). Files sent from scratchpad/release_p4. Open: Gem product IDs -> Config.Gems.Products when the user sends them; tiny-phone (740x360) battle HUD overlaps (old). |

## How to resume a wave
`Workflow({scriptPath: "<scratchpad>/p4wN.js", resumeFromRunId: "<run id>"})` - done agents replay from cache. Do NOT edit the
script's PRE / task text before resuming (they are part of every cache key). Run ids: wave 2 wf_c2d57c0b-817 (done); wave 3 wf_c0748700-200 (done).

## Files the lead keeps (scratchpad = /tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad)
- `p4w1.js` .. `p4w4.js` (wave scripts).
- `p4_wave1_notes.md`: wave-1 builders' reports (exact API). `p4_wave2_notes.md`: wave-2 reports (same format). `p4_wave3_notes.md`: wave-3 reports.
- Wave reports live in the workflow journal: `/root/.claude/projects/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/subagents/workflows/<run>/journal.jsonl`.

## Known red until later waves (gate after wave 2 must show only these)
client_p2home, client_p2ui, p2ui_tutorial, p3ui_tutorial (wave 3); p2flow_* (wave 4); p2final_docs (wave 4);
final_checks only as a cascade of those.

## Open items
- dump_gui SetCollector + CashGui, TutorialService CollectPad, client_p2home rewrite, petcards scenario: given to wave 3 (careui / ui / homefx).
- p3flow_raid + hazards: fixed (test isolation: game clock passes Double Rewards; random strike overlap). p4garden_coins flaked once in a prefix run: watch.
- Contract 3.2 optional notes: bank stored as whole Cash; resting-key full-meal rule; portal yaw definition.

## Token-saving rules (player asked)
- After every wave: update this file + the wave notes file; read those, not old chat.
- Builders: test with `--only` while working, ONE full `--quick` run at the end; read only the contract sections they need.
- Lead gate: one full run per wave in a worktree; read only the failure summary.
- Smaller review in wave 5 (about 3 reviewers).

# PHASE 5 (branch v3-phase5, from v3-phase4)
Request + approved decisions: scratchpad/phase5_request.md (player said "go!").
| Step | What | Status |
|---|---|---|
| D | design: 4 designers (battle, dungeon Fable; home, world Opus) -> lead (Fable) contract in ARCHITECTURE_V3 "## Phase 5" -> judge (Opus) -> lead fix | DONE wf_9b76bb34-5d6: contract in ARCHITECTURE_V3 "## Phase 5" (sections 0-13; waves in 10, ownership 11, tests 12, owner checklist 10.6); designs scratchpad/p5design/design:*/ ; judge p5design/judge/review.md fixed |
| R | show scratchpad/p5design/summary_for_player.md to the player, get OK | OK given ("go") |
| W0 | lead (Fable): section 10.1 shared edits, fixtures, baseline log scratchpad/p5_w0_baseline.log | DONE wf_872fc5c9-bc1: baseline 9024/0; gate 9033/5 (known red for W1: p3battle_catalog x2 + p3fixsrv_trial1 = Rally/Haste in BattleCatalog, battlecore W1); StormAltar MAX_PARTS 500 done by lead. Notes scratchpad/p5_wave0_notes.md |
| W1 | data F, battlecore F, economy+roam O, worldstyle O | DONE wf_63badf7b-be9 (resumed after a container restart). sim_battle 36/36, sim_tycoon ALL MET (C10 floor 115 for ring+dungeon), sky in branding/sky. Notes scratchpad/p5_wave1_notes.md; carry list scratchpad/p5jobs/carry.md |
| W2 | battleservice F, tycoon+care F, worldlobby O, homeworld O, neonkit O | DONE wf_2a964f3d-aa8; lead fixes applied (PortalRingRadius gone, prestige test, storm audit, showcase exempt). Notes scratchpad/p5_wave2_notes.md; carry list scratchpad/p5jobs/carry.md |
| W3 | dungeon F, battleclient O, homefx+pets O, careui O, menu O | DONE wf_1462dd08-eb9. Notes scratchpad/p5_wave3_notes.md. W3 gate DONE: fixer 13/15 (aliases deleted, MainMenu.Enabled=true, contract pending groups flipped, CoinPoint/HeapStage gone, mock Clone font flag); full 10396/86 (W4-owned + client_mobile x2 + client_replay timeout -> side fixer) |
| W4 | dungeonclient, tutorial, docs, flow, arenaart (all O) | DONE wf_ad0c5701-086 (flow full run 11177/14). Notes scratchpad/p5_wave4_notes.md. W4 gate DONE: berries dup fixed (BerriesMigrated), flakes isolated, menu touch zones; full 11311/1 (that 1 fixed after: userId collision) |
| W5 | review (3 lenses) + fix + release gate + rbxlx + merge + send | DONE: 14 review findings fixed; release run_checks full 11372/0 (scratchpad/p5_release2.log); rbxlx rebuilt + verify_place 87/87; merged to main; sent to player (scratchpad/release_p5) |
Wave script: scratchpad/p5wave.js takes args {wave, jobs:[{key, model, files, task}], resume:{key: note}}. Notes after each wave: scratchpad/p5_wave<N>_notes.md.
Resume design: Workflow({scriptPath: scratchpad/p5design.js, resumeFromRunId: "wf_9b76bb34-5d6"})
Blender: bpy 5.2 at /tmp/claude-0/bpyenv/bin/python (re-install with pip in a venv if the container restarted). (The old smooth Pebble Pup script blender/pebble_pup.py + its preview were deleted 2026-10-21 at the player's request: old design, not used; the live pup is the fine-voxel pet_dog key.)
PLAYER IS AFK: player said "if this wave ends i allow you to continue the build without stops without asking ... until the end of the phase". So: run W0..W5 + ship with NO questions. Job args for each wave: scratchpad/p5jobs/w<N>.json (pass as Workflow args).
Preview sent to player: scratchpad/release_p5_preview (W3 gate 56c2f71 + side fixes Hud/Menu/EvolutionFx). Not merged.
W5 review script ready: scratchpad/p5review.js (launch after the W4 gate fixer; review reads v3-phase4..HEAD)

# Phase 6: Blender models only (started 2026-10-20)
- Player: "dont use any roblox models, use only blender models"; scope "Everything now"; upload via Open Cloud API key; work from the cloud session.
- Key: player added it to the environment settings, but THIS session started before -> env ROBLOX_API_KEY / ROBLOX_CREATOR_ID not visible (403 no auth). Build models now; upload in a NEW session (it loads the env). Never paste/print the key.
- STYLE: player dislikes Phase 5 realistic look; wants pre-Phase-5 (7aa0df2) voxel style, finer voxels, more detail; portals as before P5. See ARCHITECTURE_V3 "ART RULE".
- Check with the player before the FIRST real upload (uploads publish to their account).

| Step | What | State |
|---|---|---|
| D | design workflow wf_f91389a6-695 (inv-creatures, inv-lobby, inv-home-arena-dungeon, pipeline proto (fine-voxel), research, style-ref Phase4-vs-Phase5 renders, judge) -> scratchpad/p6design/ | DONE. Recipe = p6design/judge/recipe.md (waves A look revert, B kit+bridge, C runtime MeshLibrary, D uploads). Style = p6design/style-ref/style.md. Kit proto = p6design/pipeline/kit. Previews sent; player said GOOD + asked: evolved pets best with aura+effects; portals = P5 Gate Court modes in P4 hoop style |
| W0 | lead: contract ARCHITECTURE_V3 '## Phase 6', docs/phase6/*, blender/kit proto, ShadowMap, PetFx+MeshIds stubs, Config.MeshAssets | DONE 3684294 (branch v3-phase6) |
| W1 | look-lobby, look-places, kit, runtime, evofx | DONE wf_5ec0bd9e-696, gate 11536/0, commit d4615ae. Notes docs/phase6/wave1-notes.md |
| W2 | art-pets, art-evolved, art-creatures, art-gates, art-lobby, art-home, art-arenadungeon, runtime-pets | DONE wf_f8fdb7ad-c60, commit 1d57a64 (703 manifests). Notes docs/phase6/wave2-notes.md |
| W2.5 | fix-kit, fix-runtime, fix-tests (args scratchpad/p6jobs/w25.json) | DONE wf_5188b813-58e (0b315d7): results + lead patches in docs/phase6/wave2-notes.md; gate default 12175/0 (1175 s), --mesh 1003/0 |
| W2b | homeportal (one Agent) | DONE f11f620: 5-gate court, Home window hero (Go home / Claim a home), PortalFxController + smoke_p6_portalfx. AFTER W2: delete the Home entry in WorldStyle.SampleGates (~:887, art-gates owns the file now); check client_p5menu_mobile ("settings window is a bottom sheet") in the full gate (agent saw it fail in --only on clean HEAD too) |
| W2c | vortex (same agent) | DONE 627604e: PortalVortex inside every hoop (player reference: swirl + glowing rim + lightning + inward streaks). Fallback = Beams + inward particles; textured = blender/textures/vortex/*.png via upload_assets.py --textures -> TextureIds.lua. W4 UPLOAD: include textures; check the Decal-vs-Image id loads in an ImageLabel; check in Play that streaks pull INWARD. |
| W3a | perf-plots, docs (args scratchpad/p6jobs/w3a.json) + review (scratchpad/p6review.js, base 7ac803e4b8) | build RUNNING wf_de85fde5-798; review DONE wf_4d4cefcb-582: 13 confirmed -> docs/phase6/review3-findings.md |
| W3b | fix-world + fix-tools (wf_345e9868-42f) + fix-meshlib (wf_99da7d77-63a) | DONE: all 13 review findings fixed (commits up to W3b part 2) |
| W3c | lod-keys + docs-2 (wf_12f749f0-0bf) | DONE: 81 _low keys, --lod-check 291k/300k, fbxSha256 on all 798 keys, uploader --set-id/--class/--adopt/--not-created, docs |
| W3 | final gate + ship | DONE: run_checks --quick (default 12276/1 -> README layout fixed, p2final_docs 113/0; --mesh 1011/0; uploader tests 76/76); rbxlx rebuilt (Rojo 7.7.1, verify_place 892/892); merged v3-phase6 -> main (cec67a5) |
- NEXT: W4 upload ONLY after the player says OK (docs/phase6/OWNER_UPLOAD.md: dry run, cal_axes, one pet live in Studio, batches by class incl. _low keys, vortex textures + Image-id check, commit MeshIds.lua / TextureIds.lua / upload_state.json, rojo build). The env of this session has ROBLOX_API_KEY + ROBLOX_CREATOR_ID (seen by a dry run); never print the key. After the first upload check ML_Yaw (43 symmetric keys cannot reveal a baked 180 yaw).
- NOTE: the docs agent saw ROBLOX_API_KEY + ROBLOX_CREATOR_ID set in THIS environment (dry run only). Upload still needs the player OK first.
- NEXT after W3a: append results to docs/phase6/wave3-notes.md; apply lead requests (perf-plots part budget for 6.5); W3b fix wave for confirmed review findings; full gate both modes + bash tools/run_checks.sh; rbxlx rebuild (rojo build); merge v3-phase6 -> main; send player renders. W4 upload = new session with ROBLOX_API_KEY, player OK first (docs/phase6/OWNER_UPLOAD.md).
- Player wants: portal vortex like his reference (swirl, glowing rim, lightning, inward streaks) INSIDE the hoop (done, W2c).
- Player wants (2026-10-20 later): NO Home portal in the lobby; Home window Go home improved; portal animation clean + smooth.
- Player wants: caveman talk; previews before big builds (said OK to style); Blender-only models; evolved pets best (aura+fx); gates = P5 modes in P4 hoop style.

## Dungeon fixes (player request after Phase 6; branch v3-dungeon-fixes)
- Plan + contract: docs/dungeon-fixes/plan.md (root causes A: client Wave handler never draws enemies; B: zone centre 4.5-6 studs above floor; 7 decisions; ownership).
- Upload progress: cal_axes uploaded (asset 115959775479149, Approved, on main). WAITING: player's Studio check of cal_axes (ML_Status/Yaw/Scale/FitErr, colourful cube, F readable) before Pebble Pup.
- Upload progress (2026-10-21): player said OK to OWNER_UPLOAD section 4 -> Pebble Pup uploaded (8 keys, all Approved): pet_dog 134064311685185, pet_dog_low 90453620352778, wing_feather_L 109522978408114, wing_feather_R 80562218189547, wing_feather_L_low 118536422831995, wing_feather_R_low 83847180366774, acc_crown 95719441990639, acc_crown_low 131409076531825. smoke_p6_pets default checks now accept shipped pet ids that stay 'loading' in the mock. Gate run_checks --quick: default 12636/0, mesh 1023/0, uploader 76/76, check.mjs 0 errors; rbxlx rebuilt (Rojo 7.7.1, verify_place OK). Player Studio check (published game, Rojo): Output '9 mesh model(s) to load', no 'stays on the Part build' / 'could not be downloaded'; pet_dog + cal_axes ML_Status ready, ML_Yaw 0, ML_Scale 1, ML_FitErr 0, load ~1.5 s; /pet pebble = fine-voxel dog in colour matching docs/phase6/img/pebble_pup_preview.png (no mirror: the fit refuses mirrors). Player confirmed wings + flap/blink/bob, said OK -> deleted the old smooth design (blender/pebble_pup.py + preview), uploaded section 5 batch 'pets' (94 keys; 86 new; pet_owl_low + wing_fairy_R_low failed once with Roblox 'Unknown Error', retried OK): state = 95 assets, all Approved. Gate --quick all passed (default 12636/0 with 91 harmless mock 'stays on the Part build' warns = one per shipped key, mesh 1023/0); rbxlx rebuilt, verify_place OK. Player Play-tested pets (/pets: all voxel meshes, colour OK) and said OK -> uploaded batch 'evolved' (354 new; 3 failed once with Roblox 'Unknown Error', retried OK): state = 449 assets, all Approved. Gate --quick all passed (default 12636/0; 421 warns all mock 'no asset store' = one per shipped key; mesh 1023/0); rbxlx rebuilt, verify_place OK. Player Play-tested evolved and said OK -> (2026-10-23) uploaded batch 'creatures' (60 new, 0 failed): state = 509 assets, all Approved, creator user 93742920. bpy 5.2.3 (new on pip) wrote other FBX bytes (fbxSha256 changed for every key, contentHash/structureHash same); bpy 5.2.2 rebuilds meshes.json byte-exact, so OWNER_UPLOAD section 2 now pins bpy==5.2.2. smoke_p6_creatures default checks now accept shipped coin / pedestal ids (server coin + NPC pedestal tagged once the key has an id). Gate --quick all passed (default 12637/0; 481 warns all mock 'no asset store' / 'stays on the Part build' = one per shipped key; mesh 1023/0; uploader 76/76; check.mjs 0 errors); rbxlx rebuilt (Rojo 7.7.1, verify_place OK). Player Studio check: Output '[MeshLibrary] 509 mesh model(s) to load', no 'stays on the Part build'; SkyDragon ML_Mesh = true. Player said 'ok gates' -> (2026-10-23) uploaded batch 'gates' (6 new, 0 failed; build byte-exact with bpy 5.2.2): state = 515 assets, all Approved. Gate --quick all passed (default 12637/0; 487 warns all mock 'no asset store' / 'stays on the Part build'; mesh 1023/0; uploader 76/76; check.mjs 0 errors); rbxlx rebuilt (Rojo 7.7.1, verify_place OK). NEXT: player Play-test the Gate Court (walk the gates); then OK for batch 'lobby' (63 keys), then home, arenadungeon, vortex textures.
- DONE: all 7 requirements (commits up to 1ad81ed, fast-forwarded to main). Gate: default smoke 12633/3 -> p6pets fixed (431/0), mesh 1023/0. Known: sim_battle element-counter target 53% (55-90) after no-passive-heal (35/36 targets); duel idle-loser guard weaker with auto-attack. NEXT: player Studio check of cal_axes, then Pebble Pup upload.

