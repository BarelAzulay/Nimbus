# Frozen copies of older releases (do not edit)

Test inputs, not game code: `tools/syntax.py`, `tools/check.mjs` and the smoke scans never load this folder as part
of the game, and nothing here is copied into the place file. Each pair is a byte copy of a released DataService and
economy sim, frozen at the start of the next phase so the tests can prove that an OLD server saving a NEW profile
during a rollout ("Publish, then Migrate to Latest Update") loses nothing.

## Frozen Phase 3 copies

Byte copies of the Phase 3 release (main at 35800c0), frozen at the start of Phase 4 (ARCHITECTURE_V3.md
"Phase 4 build contract", section 4.4 and 8.3).

* `DataService_phase3.lua`: the Phase 3 DataService. `smoke_p4_data.lua`'s `p4data_rollout` loads it as a second
  module against the same mock DataStore to prove that a Phase 3 server saving a Phase 4 profile during the rollout
  keeps every Phase 4 field.
* `sim_tycoon_phase3.py`: the Phase 3 economy sim, kept for the record. Its user, `python3 tools/sim_tycoon.py
  --migrate` (300 Phase 3 homes under the Phase 4 economy), was replaced by `--migrate5` in Phase 5.

## Frozen Phase 4 copies

Byte copies of the Phase 4 release (v3-phase5 at ccbad89, before any Phase 5 edit), frozen by the lead in Phase 5
wave 0 (ARCHITECTURE_V3.md "Phase 5 build contract", sections 9.3 and 10.1).

* `DataService_phase4.lua`: the Phase 4 DataService. `smoke_p5_data.lua`'s `p5home_rollout` / `p5dgn_rollout` load it as
  a second module against the same mock DataStore to prove that a Phase 4 server saving a Phase 5 profile during the
  rollout keeps `Dungeon`, `Berries`, `Settings`, `Migrations.P5*` and the new Home keys (`DecorCredit`,
  `LegacyMagnet`, `LegacyMagnetStar`) untouched (the `p4data_rollout` pattern), and that the next Phase 5 load folds
  whatever the Phase 4 server changed meanwhile.
* `sim_tycoon_phase4.py`: the Phase 4 economy sim. `python3 tools/sim_tycoon.py --migrate5` imports it by path and folds
  300 Phase 4 homes (18 stations) into the Phase 5 home (11 stations): Home Level never down, no dead end, pad time
  <= 1.0 per house tier / star bucket.

To freeze the next release: copy the released `src/server/Services/DataService.lua` and `tools/sim_tycoon.py` here as
`DataService_phase<N>.lua` / `sim_tycoon_phase<N>.py` (byte copies, never edited afterwards) and add a section above.
