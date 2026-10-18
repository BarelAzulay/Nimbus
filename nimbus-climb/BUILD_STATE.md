# Phase 4 build state (read this first, instead of the whole chat)

Updated: 2026-10-18 08:30 UTC. Branch `v3-phase4`. Plan: `ARCHITECTURE_V3.md` sections "Phase 4" + "Phase 4 build contract"
(incl. the "Player update" block: every pet levels to 100, evolutions at 20 / 50).

## Player decisions (all settled)
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
| 2 | tycoon, care, battleservice (Fable); homeworld, arenaworld, pets | tycoon + care DONE; battleservice + homeworld half done; arenaworld + pets not started. Last checkpoint 66d1187 |
| 3 | homefx, battleclient, careui, ui | not started |
| 4 | docs (README), flow tests | not started |
| 5 | review + verify + fix, full suite, place file, merge, send | not started |

## How to resume wave 2
`Workflow({scriptPath: "<scratchpad>/p4w2.js", resumeFromRunId: "wf_c2d57c0b-817"})` - tycoon + care replay from cache. Do NOT edit
p4w2.js before that (the shared preamble is part of every cache key).

## Files the lead keeps (scratchpad = /tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad)
- `p4w1.js`, `p4w2.js` (wave scripts), `p4w2_pre.txt`, `p4w2_tasks.js`.
- `p4_wave1_notes.md`: wave-1 builders' reports (exact API). Write `p4_wave2_notes.md` the same way after wave 2.
- Wave reports live in the workflow journal: `/root/.claude/projects/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/subagents/workflows/<run>/journal.jsonl`.

## Known red until later waves (gate after wave 2 must show only these)
client_p2home, client_p2ui, p2ui_tutorial, p3ui_tutorial (wave 3); p2flow_* (wave 4); p2final_docs (wave 4);
final_checks only as a cascade of those.

## Open items from wave-2 reports (fix before / during wave 3)
- p2data_save + p4data_rollout pin Home.Gym contents after a Phase 4 load (PetCareService now empties it): data tests must change.
- p4data_save two-server job checks vs the new care tick timing: settle.
- contract.json: add TycoonService.Piles.
- Contract 3.2 notes: bank stored as whole Cash; resting-key full-meal rule; portal yaw definition.

## Token-saving rules (player asked)
- After every wave: update this file + the wave notes file; read those, not old chat.
- Builders: test with `--only` while working, ONE full `--quick` run at the end; read only the contract sections they need.
- Lead gate: one full run per wave in a worktree; read only the failure summary.
- Smaller review in wave 5 (about 3 reviewers).
