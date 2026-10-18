# Phase 4 build state (read this first, instead of the whole chat)

Updated: 2026-10-18 (after wave 2). Branch `v3-phase4`. Plan: `ARCHITECTURE_V3.md` sections "Phase 4" + "Phase 4 build contract"
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
| 2 | tycoon, care, battleservice (Fable); homeworld, arenaworld, pets | DONE (297c9ae). Reports: scratchpad/p4_wave2_notes.md. Lead after: data-test fixes, contract.json (Piles, SetGarden/SetTraining) |
| 3 | homefx, battleclient, careui, ui | DONE (70b04b6). Reports: scratchpad/p4_wave3_notes.md. Gate in worktree scratchpad/gate_w3 (log gate_w3.log) |
| 4 | flow, fixer, docs | DONE (wf_07cbfb76-a84, notes scratchpad/p4_wave4_notes.md; leads applied: /petlevel Refresh, COMPAT deleted). Gate w4 GREEN: 8916 pass, 0 fail (b9d875f). |
| 5 | review + verify + fix, full suite, place file, merge, send | RUNNING review wf_a3116583-fae (script scratchpad/p4w5.js: 3 lenses -> 3 verifiers -> fixers server/battle/client). After: notes p4_wave5_notes.md, gate, run_checks.sh, rojo build + verify_place, merge to main, send rbxlx + zip. Resume: Workflow({scriptPath: scratchpad/p4w5.js, resumeFromRunId: "wf_a3116583-fae"}) |

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
