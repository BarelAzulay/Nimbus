# Frozen Phase 3 copies (do not edit)

Byte copies of the Phase 3 release (main at 35800c0), frozen at the start of Phase 4 (ARCHITECTURE_V3.md
"Phase 4 build contract", section 4.4 and 8.3). They are test inputs, not game code: `tools/syntax.py`,
`tools/check.mjs` and the smoke scans never load this folder as part of the game.

* `DataService_phase3.lua`: the Phase 3 DataService. `smoke_p4_data.lua`'s `p4data_rollout` loads it as a second
  module against the same mock DataStore to prove that a Phase 3 server saving a Phase 4 profile during the rollout
  keeps every Phase 4 field.
* `sim_tycoon_phase3.py`: the Phase 3 economy sim. `python3 tools/sim_tycoon.py --migrate` compares 300 old homes
  under the old and the new economy (Home Level unchanged, no dead end, pad-time ratios).
