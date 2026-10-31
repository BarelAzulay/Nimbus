# Team flow, battle balance and the Pets window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A player's battle team is the three pets following them (A / B / C presets, one active), every battle panel shows those three faces with Edit team and never auto-fills, a battle-only stat path makes level beat rarity, the Ring / Dungeon / raids are re-tuned to the owner's wall (3 L1 Commons win about 3 Ring rounds, Ring 10 in about 30 minutes), one big Pets window replaces the Pets and Team tabs, and a loss shows the levels gained with Fight again.

**Architecture:** Six tasks on branch `team-balance` (worktree `Projects Main\Nimbus\.worktrees\team-balance\nimbus-climb`), in order, each with its own `tools/smoke_tb_*.lua` file registered in `tools/smoke.py`. Tasks 1-2 are shared-catalog and simulator work (`BattleCatalog`, `tools/sim_battle.lua`); Task 3 is server data (`DataService`, `PetService`, `BattleService`, `PetCareService`) plus `State`; Tasks 4-6 are client UI in NEW focused modules (`PetsController`, `TeamFaces`, `LossScreen`), with `MenuController` only losing code. Every check runs through `py -3.12 tools/smoke.py` (lupa + `tools/robloxmock.lua`), `tools/sim_battle.lua`, `tools/sim_tycoon.py --check` and `node tools/check.mjs`.

**Tech Stack:** Roblox Luau written as plain Lua 5.1 (the repo rule), Rojo layout under `src/`, Python 3.12 + lupa for the mock world, `tools/contract.json` + `tools/check.mjs` for the module API contract.

**Spec:** `docs/superpowers/specs/2026-10-31-team-balance-design.md` (sections 1-7 are cited below as "spec s.N").

## Global Constraints

- Work only in this worktree on branch `team-balance`; never touch other worktrees or `main`; no merge, no upload, no Roblox Studio, no Rojo, no Blender (the owner is playtesting from another worktree). Python is `py -3.12` (`python` is a Store stub). Git: use absolute paths or `git -C <worktree>`.
- Every Lua file: plain Lua 5.1-compatible syntax (no `continue`, no `+=`, no type annotations); client text through `Theme` roles; UI on `CloudUI` / `NeonKit`; no new asset ids, sounds, textures or models (spec non-goals).
- Every commit message ends with exactly these two lines: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01ACtM8qc8ts2NyGHrZh7vyT`; push after every task (`git push origin team-balance`).
- `node tools/check.mjs` stays at 0 errors; every public member added or removed goes into `tools/contract.json`; every new `tools/smoke_*.lua` is registered in `tools/smoke.py` (`server_files` / `client_files` + the scenario lists); `p3fixsrv_net16` (about 6004 B/s against 6000) is a known failure that predates this work and must get no worse.
- Garden income, coins, speed, feeding, training prices and everything non-battle keep `Config.PetStats.RarityScale` and `PetCatalog.LevelFactor` exactly; `py -3.12 tools/sim_tycoon.py --check` prints "the catalog matches the sim constants" after every task (spec s.5). `PetCatalog.GetStats` / `StatsOf` are never patched at runtime.
- Battle numbers (spec s.5, tunable but pinned by tests): battle rarity scale Common 1, Uncommon 1.25, Rare 1.6, Epic 2.1, Legendary 2.8, Mythic 3.7, Secret 5; battle level factor `1 + (0.12x + 0.0035x^2 + 0.0002x^3) * EvolutionBonus[stage]`, x = level - 1.
- Team rules (spec s.1): `Config.Pets.MaxEquipped` stays 3; the invariant `Equipped == active preset's keys minus busy keys (training, or every copy in the Garden), in order` holds after every write; a busy pet KEEPS its slot; no pet, preset or Token is ever lost by the migration (marker `Migrations.B4TeamFollow`).
- Never auto-fill silently (spec s.2): the server refuses an empty or all-busy team with a reason; the client opens the Pets window instead.
- Tutorial step texts stay 97-125 bytes of plain text once placeholders are filled; NPC lines <= 125 bytes, 3-5 per NPC (`p5ui_content`); `README.md` tables are read by `smoke_p2_final` (`p2_final`), so every number or control name the plan changes is also changed in `README.md`.
- Phone (844x390 touch): every interactive target in the new window and the new panels is >= 44 px high; nothing sits over Roblox's top bar (`GuiService:GetGuiInset()`) or its buttons; no nested scrolling.
- Report failures honestly: never claim a scenario or a sim target passes without having run it in this worktree.

## Review Focus

1. Migration: a save whose `Equipped` holds the same keys as a non-active preset in a DIFFERENT order must make that preset active and `Equipped` must follow the preset's order (one team, no duplicate) — test `tb_team_migrate` case "same keys, other order" in Task 3.
2. The slot-1 pet starts training while the player stands in the lobby: the followers change at once (no 2nd pet walks off), `ActiveTeamKeys` starts with slot 2, and the Ring fighter is that pet — test `tb_team_busy` in Task 3.
3. A refused pick (a gardening pet dropped on a slot) must leave the slot as it was, show the toast and keep pick mode armed on the same slot; nothing reverts silently a second later — test `client_tb_pets_pick` in Task 4.
4. Edit team from a Ring window opened at a boss start (Start = 20) must come back to the Ring window at Start = 20, not round 1, and the Dungeon window must come back on the same floor — test `client_tb_faces_return` in Task 5.
5. Fight again pressed while `InBattle` is still set (the 4 s return delay) must wait and start once, never be refused with "Finish your battle first" and never double-start on a second press — test `client_tb_loss_fight_again` in Task 6.

---

### Task 1: Battle stat path (level beats rarity, battles only)

**Files:**
- Modify: `src/shared/BattleCatalog.lua` (header comment near line 1-85; a new block after `BattleCatalog.StatsOf` at line 432; `BattleCatalog.UnitStats` lines 598-609 where `pc.GetStats` is called)
- Modify: `src/client/Controllers/MenuController.lua:1135-1153` (`P2.statsAt`) and its row writer near line 3448 (the detail's Power / Health values)
- Modify: `src/client/Controllers/IndexController.lua:490-514` (`statMax`), `:1717-1725` (the group row stats), `:2350-2385` (the stat rows)
- Modify: `tools/sim_battle.lua` (new section `levels` after `support`, line 786; `order` list)
- Modify: `tools/smoke_p5_battlecore.lua:190-220` (`p5stats_formula`: the UnitStats half)
- Modify: `tools/contract.json` (`shared/BattleCatalog` functions + fields)
- Modify: `README.md` (the battle section: one paragraph on the battle-only scale)
- Create: `tools/smoke_tb_stats.lua`; Modify: `tools/smoke.py` (register it)

**Interfaces:**
- Consumes: `PetCatalog.EvolutionBonusOf(stage)`, `PetCatalog.EvolutionStage(def, level, stored)`, `PetCatalog.MaxPetLevel()`, `PetCatalog.TierMultiplier(tier | def)`, `BattleCatalog.StatsOf(entry)` (the def resolver), `PetKeys.DefOf(key, profile)`.
- Produces:
  - `BattleCatalog.BattleStats = { RarityScale = { Common = 1, Uncommon = 1.25, Rare = 1.6, Epic = 2.1, Legendary = 2.8, Mythic = 3.7, Secret = 5 }, Level = { Linear = 0.12, Quadratic = 0.0035, Cubic = 0.0002 } }` (the ONLY tunables of the battle path).
  - `BattleCatalog.BattleLevelFactor(level, stage) -> number`: level clamped 1..`MaxPetLevel()`, stage cleaned like `P4.extras` (junk / nil -> 0).
  - `BattleCatalog.BattleStatsOf(subject, level, tier, stage) -> { Power, Health, Speed } | nil`: subject = def table | pet id | key (resolved like `StatsOf`); tier nil = the key's / def's own tier; `Power` and `Health` = `def.Stats.X * BattleStats.RarityScale[def.Rarity] * BattleLevelFactor(level, EvolutionStage(def, level, stage)) * TierMultiplier`; `Speed` = `def.Stats.Speed` (unscaled, as `UnitStats` reads it); no `Income` key.
  - `BattleCatalog.UnitStats` reads `BattleStatsOf` instead of `PetCatalog.GetStats`, so player pets, champions (`ChampionTeam`), dungeon enemies (`DungeonWave` via `P4.solveEntry`), bosses (`BaselineDps` / `BossHp` via `ExpectedDps`), duels, `UnitPower` and `TeamPower` all move together.
  - `tools/sim_battle.lua` section `levels` (3 targets, see Step 5) and `SIM.Commons = { "mallow_kitten", "puddle_frog", "biscuit_bear", "pebble_pup", "pip_penguin", "honey_bunny" }`, `SIM.Secrets = { "stormfang", "eclipse_dragon", "obsidian_phoenix", "phantom_kitsune" }` for later tasks.

- [ ] **Step 1: Write the failing smoke file `tools/smoke_tb_stats.lua`** (server world, pure, no boot; the `smoke_p5_battlecore.lua` shape). Scenario `tb_stats_formula`:

```lua
local BC, PC, Config = req("shared/BattleCatalog"), req("shared/PetCatalog"), req("shared/Config")
T.check(type(BC.BattleLevelFactor) == "function" and type(BC.BattleStatsOf) == "function" and type(BC.BattleStats) == "table", "tb stats: BattleLevelFactor / BattleStatsOf / BattleStats exist")
T.check(near(BC.BattleLevelFactor(1), 1, 1e-9) and near(BC.BattleLevelFactor(30), 1 + 0.12 * 29 + 0.0035 * 29 ^ 2 + 0.0002 * 29 ^ 3, 1e-9), "tb stats: L1 = 1, L30 = 1 + 0.12x + 0.0035x^2 + 0.0002x^3 (x = 29)")
T.check(near(BC.BattleLevelFactor(100, 2), 1 + (0.12 * 99 + 0.0035 * 99 ^ 2 + 0.0002 * 99 ^ 3) * PC.EvolutionBonusOf(2), 1e-9), "tb stats: the evolution bonus multiplies the level part")
T.check(near(BC.BattleLevelFactor(0), 1, 1e-9) and near(BC.BattleLevelFactor(1e9), BC.BattleLevelFactor(PC.MaxPetLevel()), 1e-9) and near(BC.BattleLevelFactor(5, "junk"), BC.BattleLevelFactor(5, 0), 1e-9), "tb stats: level clamped 1..MaxPetLevel, junk stage = 0")
local s = BC.BattleStatsOf("stormfang", 1)
local def = PC.Get("stormfang")
T.check(s and near(s.Power, def.Stats.Power * 5, 1e-9) and near(s.Health, def.Stats.Health * 5, 1e-9) and s.Income == nil and s.Speed == def.Stats.Speed, "tb stats: a L1 Secret = base x 5 (battle scale), no Income, Speed unscaled")
T.check(near(BC.BattleStatsOf("mallow_kitten@Golden", 1).Power, PC.Get("mallow_kitten").Stats.Power * 1.5, 1e-9), "tb stats: the key's tier multiplier applies")
-- garden numbers untouched
T.check(near(PC.GetStats("stormfang", 10).Income, def.Stats.Income * Config.PetStats.RarityScale.Secret * PC.LevelFactor(10), 1e-9), "tb stats: PetCatalog.GetStats still uses RarityScale x LevelFactor (garden)")
T.check(near(PC.LevelFactor(20, 1), 3.85, 1e-9) and Config.PetStats.RarityScale.Secret == 13, "tb stats: LevelFactor and Config.PetStats.RarityScale unchanged")
-- UnitStats takes the battle path
local us = BC.UnitStats("mallow_kitten", 30)
T.check(near(us.MaxHp, BC.BattleStatsOf("mallow_kitten", 30).Health * BC.Damage.HpScale, 1e-6), "tb stats: UnitStats MaxHp = BattleStatsOf Health x HpScale")
T.check(BC.UnitPower("mallow_kitten", 30) > BC.UnitPower("stormfang", 1), "tb stats: a L30 Common out-powers a L1 Secret")
T.check(BC.UnitPower({ PetId = "mallow_kitten", Key = "mallow_kitten", Level = 100, Evo = 1 }) > BC.UnitPower("stormfang", 50), "tb stats: a L100 evolved Common out-powers an unevolved L50 Secret")
for _, l in ipairs({ 1, 20, 50, 100 }) do
	for _, c in ipairs(SIM_COMMONS) do for _, sId in ipairs(SIM_SECRETS) do
		T.check(BC.UnitPower({ PetId = sId, Key = sId, Level = l, Evo = 2 }) > BC.UnitPower({ PetId = c, Key = c, Level = l, Evo = 2 }), "tb stats: a Secret stays stronger at equal level and stage (" .. sId .. " vs " .. c .. " L" .. l .. ")")
	end end
end
local champ = BC.ChampionTeam(20, 1).Pets[1]
T.check(near(BC.UnitStats(champ).MaxHp, BC.BattleStatsOf(champ.PetId, champ.Level, champ.Tier, champ.Evo).Health * BC.Damage.HpScale, 1e-6), "tb stats: champions use the same path (a level means the same on both sides)")
```

Scenario `client_tb_stats_rows` (client world, a synced profile with `stormfang` L10 and `mallow_kitten` L1 — reuse `smoke_p4_careui.lua`'s profile helper): open the Index on the Secret group and the Pets detail (through `MenuController.Open("Pets", { Key = "stormfang" })` until Task 4 replaces it, then through `PetsController`):

```lua
T.check(indexRow("stormfang", "Power").Value.Text == commas(floor(BC.BattleStatsOf("stormfang", 1).Power + 0.5)), "tb stats: the Index Power row shows the battle number")
T.check(indexRow("stormfang", "Income").Value.Text == commas(floor(PC.GetStats("stormfang", 1).Income + 0.5)), "tb stats: the Index Coins row keeps the garden number")
T.check(detailRow("Power").Text:find(commas(floor(BC.BattleStatsOf("stormfang", 10).Power + 0.5)), 1, true) and detailRow("Health").Text:find(commas(floor(BC.BattleStatsOf("stormfang", 10).Health + 0.5)), 1, true), "tb stats: the pet detail's Power / Health rows show the battle numbers")
T.check(detailRow("Income").Text:find(commas(floor(PC.GetStats("stormfang", 10).Income + 0.5)), 1, true), "tb stats: ...Coins keeps the garden number")
```

Register in `tools/smoke.py`: `server_files.append("smoke_tb_stats.lua"); client_files.append("smoke_tb_stats.lua"); pure_scenarios += ["tb_stats_formula"]; ins(server_scenarios, "p5stats_formula", ["tb_stats_formula"]); ins(client_scenarios, "client_final", ["client_tb_stats_rows"])`.

- [ ] **Step 2: Run it to verify it fails**

Run: `py -3.12 tools/smoke.py --quick --only tb_stats_formula,client_tb_stats_rows`
Expected: FAIL at "BattleLevelFactor / BattleStatsOf / BattleStats exist".

- [ ] **Step 3: Implement `BattleCatalog.BattleStats`, `BattleLevelFactor(level, stage)`, `BattleStatsOf(subject, level, tier, stage)` in `src/shared/BattleCatalog.lua`** right after `BattleCatalog.StatsOf`; then in `UnitStats` replace the `pc.GetStats(def, level, tier, evo > 0 and evo or nil)` call with `BattleCatalog.BattleStatsOf(def, level, tier, evo > 0 and evo or nil)` (the raw fallback below it stays). Update the file header's formula note (line 884-894 "champions are built with the PLAYER pet formula" now names `BattleStatsOf`).

- [ ] **Step 4: Switch the two client displays to the battle numbers**: in `MenuController` `P2.statsAt(def, level)` returns the garden table with `Power` / `Health` overwritten by `BattleCatalog.BattleStatsOf(def, level, tier, stage)` (tier from `P2.tierOf`, stage from `P2.stage`) — one helper `P2.battleStatsAt(def, key, level)`; in `IndexController` `statMax()` and the row writers (lines 501 and 1718) take `Power` / `Health` from `BattleStatsOf(def.Id, 1)` and `Income` / `Speed` from `GetStats(def.Id, 1)`.

- [ ] **Step 5: Add the sim section `levels` to `tools/sim_battle.lua`** (after `support`; `opts.quick` 8 seeds, full 24): scripted players on both sides, single pets, every Common of `SIM.Commons` against every Secret of `SIM.Secrets`:

```lua
target("level beats rarity: a L30 Common beats a L1 Secret (mean win rate >= 90% over the 24 pairs)", mean30 >= 90, fmt("%.0f%%", mean30))
target("a L100 evolved (stage 1) Common beats an unevolved L50 Secret (mean >= 75%)", mean100 >= 75, fmt("%.0f%%", mean100))
target("a Secret stays the stronger pet at equal level and stage (UnitPower, L1 / L20 e1 / L50 e2 / L100 e2, every pair)", allPairs)
```

Run: `set SIM_BATTLE=quick only=levels && py -3.12 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"` (in PowerShell: `$env:SIM_BATTLE='quick only=levels'; py -3.12 -c "..."`)
Expected: `SUMMARY: 3 of 3 targets met`. Record the two means in the commit message.

- [ ] **Step 6: Rewrite the pinned checks in `tools/smoke_p5_battlecore.lua` `p5stats_formula`** (lines 205-217): the `UnitStats` Evo-2 ratio becomes `BC.BattleLevelFactor(50, 2) / BC.BattleLevelFactor(50, 0)`, and "level 50 without a stored stage" becomes `BC.UnitStats("mallow_kitten", 1).MaxHp * BC.BattleLevelFactor(50, 0)`; the `PetCatalog.LevelFactor` checks (lines 195-204) stay as they are (garden). Add `BattleLevelFactor`, `BattleStatsOf` to `functions` and `BattleStats` to `fields` of `shared/BattleCatalog` in `tools/contract.json`. Add the README paragraph ("In battle a pet's Power and Health use the battle scale: rarity x1 / 1.25 / 1.6 / 2.1 / 2.8 / 3.7 / 5 and a level curve that grows faster than the garden's, so a L30 Common beats a L1 Secret").

- [ ] **Step 7: Run the gate**

Run: `py -3.12 tools/smoke.py --quick --only tb_stats_formula,client_tb_stats_rows,p5stats_formula,p2care_stats,p2_economy,p2_final,client_index` then `py -3.12 tools/sim_tycoon.py --check` then `node tools/check.mjs`
Expected: every listed scenario passes; `--check` prints "the catalog matches the sim constants"; 0 errors. NOTE: `p5battle_balance`, `p5dgn_balance`, `ringnh_catalog` and the sim's `ring` / `dungeon` / `raids` / `training` targets are EXPECTED to miss after this task (the numbers moved); Task 2 rewrites them. Say so in the commit message; do not touch their targets here.

- [ ] **Step 8: Commit and push**

```bash
git -C "<worktree>" add src/shared/BattleCatalog.lua src/client/Controllers/MenuController.lua src/client/Controllers/IndexController.lua tools/sim_battle.lua tools/smoke_p5_battlecore.lua tools/smoke_tb_stats.lua tools/smoke.py tools/contract.json README.md
git -C "<worktree>" commit -m "feat(battle): a battle-only stat path (BattleStatsOf): level beats rarity, the garden untouched" (+ the two attribution lines)
git -C "<worktree>" push origin team-balance
```

---

### Task 2: Balance tuning (the owner's wall, Ring 10 in about 30 minutes)

**Files:**
- Modify: `src/shared/BattleCatalog.lua:901-939` (`BattleCatalog.Ring`: `LevelAnchors`, `Bands`, `OpeningRounds`, `XpPerRound` and the header comment 881-900), `:1506-1525` (`BossRules.Baseline`), `:1535-1611` (`Bosses[*].HpPerPlayer`), `:1770-1821` (`Dungeon`: `Floor1Power`, `Floor1Waves`, `FirstPower`, `Growth`, new `EasedRoomMult`), `:1946-1995` (`DungeonWave` gains `opts`)
- Modify: `tools/sim_battle.lua` (`SIM.Stages` kept; `SIM.RingMedians` replaced by `SIM.Teams` + `SIM.Targets`; `ringRun` gains XP and player opts; sections `ring`, `dungeon`, `raids`, `training` rewritten; new section `progress`)
- Modify: `tools/smoke_p5_battlecore.lua:1640-1660` (`p5battle_balance`), `tools/smoke_p5_dungeon.lua` (`p5dgn_balance`; `p5dgn_run` and the other floor-1 runs that field ONE level-1 pet), `tools/smoke_ring_noheal.lua:95-160` (`ringnh_catalog`), `tools/smoke_p4_ring.lua` (any check that counts rounds won by a weak team)
- Modify: `README.md` (the Champion Ring / Dungeon / Boss Raid tables `p2_final` reads: XP rule, floor-1 words, the baseline fighter)
- Modify: `tools/contract.json` only if a public member is added (none expected)

**Interfaces:**
- Consumes: Task 1's `BattleStatsOf` path (every number below is measured on it), `BattleCatalog.LossXp`, `TycoonCatalog.XpToNext`, `SIM.run(setup, policies, playerOpts)`, `SIM.dungeonRoom`, `SIM.series`, `BattleCatalog.ChampionTeam / ChampionLevel / RingPower / RingRewards`, `BattleCatalog.BossHp / BaselineDps`.
- Produces:
  - `BattleCatalog.Dungeon.EasedRoomMult` (a number in (0, 1), start 0.35) and `BattleCatalog.DungeonWave(floorIndex, room, wave, partySize, seed, opts)` with `opts = { Eased = bool } | nil`: `Eased` multiplies that wave's `goalEach` by `EasedRoomMult` (Task 6 sets it for floor 1 room 1 of a solo tutorial run). Without `opts` the result is byte-identical to before.
  - `SIM.Idle = { dodge = 0, element = false, specials = false, buffs = false, swap = false, attack = false, cheer = false }` (the Idle trainer: stands, presses nothing); the Default trainer = `SIM.Player`'s defaults (dodge 0.7, mistime 0.5, every button).
  - `SIM.Teams = { S1 = { 3 L1 Commons mallow_kitten / puddle_frog / pebble_pup }, One = { mallow_kitten L1 }, L7 = { the same three at L7 }, Leg = { ember_phoenix / twilight_dragon / sunbeam_bear L1 }, Owner = { stormfang L10, obsidian_phoenix L11, phantom_kitsune L11 }, L50 = { the three Legendaries L50 Evo 2 }, Max = SIM.Maxed }`.
  - `SIM.ringRun(pets, runSeed, maxRound, opts) -> record, durations, total, lost, levels` with `opts = { Xp = bool, Player = playerOpts }`: `Xp` pays `Ring.XpBase + XpPerRound * r` per fielded pet after a won round and `BattleCatalog.LossXp(winXp, duration, dealtShare)` on the losing round, levelling the pets (`TycoonCatalog.XpToNext`), auto-evolving at level 20 (stage 1) and 50 (stage 2 when `PetCatalog.EvolveTwice[rarity]`); the pets passed in are mutated (Level / Xp) so a progression loop can chain runs.
  - `SIM.Targets` (the spec's table as bands; every band is inclusive):
    `Ring = { S1 = { Default = { 2, 4 }, Idle = { 1, 2 }, Reach5 = 10, Win1 = 95 }, One = { Default = { 1, 2 }, Idle = { 1, 1 } }, Leg = { Default = { 6, 10 }, Idle = { 3, 5 } }, Owner = { Default = { 16, 22 }, Idle = { 9, 13 } }, L50 = { Default = { 35, 43 }, Idle = { 27, 35 } }, Max = { Default = { 60, 95 } } }`,
    `Dungeon = { S1 = { Room1 = 90, Room2 = { 40, 60 }, Clear = 15 }, L7 = { Clear = 80 }, Leg = { Floor = { 1, 3 } }, Owner = { Floor = { 3, 5 } }, L50 = { Floor = { 6, 8 } }, Max = { Floor = { 12, 12 } } }`,
    `Progress = { Ring5 = { 4, 9 }, F1 = { 4, 10 }, Ring10 = { 20, 45 } }` (minutes, medians over 24 players),
    `Raid = { OwnerSoloWins = 0, Group = { 100, 240 } }`.

- [ ] **Step 1: Add `EasedRoomMult` and the `opts` argument to `DungeonWave`** (`goalEach = goalEach * EasedRoomMult` when `opts.Eased == true`); add to `tools/smoke_p5_dungeon.lua` `p5dgn_balance`:

```lua
local plain, eased = BC.DungeonWave(1, 1, 1, 1, 7), BC.DungeonWave(1, 1, 1, 1, 7, { Eased = true })
T.check(eased.Power < plain.Power and eased.Count == plain.Count and eased.Pets[1].PetId == plain.Pets[1].PetId, "tb balance: an eased wave aims at EasedRoomMult x the goal with the same species and count")
T.check(BC.DungeonWave(1, 1, 1, 1, 7, nil).Power == plain.Power, "tb balance: opts nil = the plain wave")
```

Run: `py -3.12 tools/smoke.py --quick --only p5dgn_balance` — Expected: these two checks pass (the ladder checks of that scenario are rewritten in Step 4).

- [ ] **Step 2: Rewrite the simulator's harness** in `tools/sim_battle.lua`: `SIM.Idle`, `SIM.Teams`, `SIM.Targets`, `ringRun` with `opts` (port the XP / auto-evolve logic of `Projects Main/Nimbus/.superpowers/team-balance-pitch/balance/options.lua` lines 94-177, which was measured against the real `BattleService` flow), a `ringSummary(pets, playerOpts, seeds) -> { med, lo, hi, reach5, win1, sec }` (reach5 = record >= 4, win1 = record >= 1), a `floorSummary(pets, f, playerOpts, seeds) -> roomPct[1..4]` that pays room XP between rooms like `DungeonService` (options.lua lines 201-221) and `ladder(pets, playerOpts, seeds)` (the highest floor cleared in >= 50% of the seeds). Delete `SIM.RingMedians`.

- [ ] **Step 3: Rewrite the `ring`, `dungeon`, `raids` sections and add `progress`** so their `target(...)` lines are exactly the spec's (quick = 16 seeds for S1 / One, 8 for the others; full = 64 / 24):

```lua
-- ring
target("3 L1 Commons: Default median 2-4, Idle 1-2 (the owner's wall)", inBand(S1.d.med, T.S1.Default) and inBand(S1.i.med, T.S1.Idle), detail)
target("3 L1 Commons reach round 5 in <= 10% of seeds and win round 1 in >= 95%", S1.d.reach5 <= 10 and S1.d.win1 >= 95, detail)
target("1 L1 Common: Default 1-2, Idle 1", ...)
target("3 L1 Legendaries: Default 6-10, Idle 3-5", ...)
target("the owner's L10/11/11 Secrets: Default 16-22, Idle 9-13", ...)
target("3 L50 Legendaries evo 2: Default 35-43, Idle 27-35", ...)
target("3 L100 maxed: Default 60-95", ...)
target("round 1 is an easy Common: every single L1 rollable Common / Uncommon wins it >= 95% (a first win always exists)", worst1 >= 95, ...)
target("shown level and shown power never drop from one round to the next (rounds 1-120, 40 seeds)", levelMono and powerMono, monoBad)
target("the record never falls with the team (S1 <= Leg <= Owner <= L50 <= Max, Default)", monotonic)
-- (info) the owner's team from an unlocked boss start: rounds won from round 10 and from round 20 (a veteran's view; records are kept, not reset)
-- dungeon
target("3 L1 Commons: room 1 >= 90%, room 2 40-60%, floor 1 full clear < 15% (Default)", ...)
target("3 L6-7 Commons clear floor 1 >= 80%", L7clear >= 80, ...)
target("best floor (>= 50% of seeds): Legendaries L1 1-3, the owner's Secrets 3-5, L50 Legendaries 6-8, maxed 12", ...)
target("the eased room: floor 1 room 1 with EasedRoomMult is won >= 95% by EVERY single L1 rollable Common / Uncommon (the tutorial)", worstEased >= 95, ...)
target("the ladder never falls with the team", ...)
-- raids
target("BossRules.Baseline is a L35 evolved Legendary and the owner's L10/11/11 Secrets win 0 of 8 solo raids on every boss", baseline.Level == 35 and ownerWins == 0, ...)
target("4 and 8 owner-teams finish storm_titan and shadow_hydra in 100-240 s", ...)
-- (keep) "dodging fighters win nearly every raid (M5 / M8, 1/4/8/16 players, >= 90% of combos)", "a solo under half the boss's BaselineDps loses", "won raids last 100-240 s", "no boss hit > 80%"
-- progress (24 players, Default trainer, 3 L1 Commons, run XP + loss XP, AUTO_EVOLVE, OVERHEAD = RETURN_DELAY 4 s + 10 s walk; "reach Ring N" = record >= N - 1; "F1" = floor-1 clear >= 80% at the pets' levels)
target("a new player reaches Ring 5 in 4-9 minutes (median)", ...)
target("...clears floor 1 in 4-10 minutes", ...)
target("...reaches Ring 10 in 20-45 minutes (target 30)", ...)
-- (info) seconds per S1 run (fight + intermissions + overhead): the retry loop, spec s.7 wants it under 2 minutes
```

`training`: re-measure its pinned ratios on the new path and rewrite the bands to the measured values +-10% (the section's purpose, not its numbers, is the contract).

- [ ] **Step 4: Tune the numbers** in `BattleCatalog` until `SIM_BATTLE="quick"` meets every target, starting from option A of `balance/options_config.lua` (`OpeningRounds = 1`, `Bands` A, `XpPerRound = 12`, `Dungeon { Floor1Power = 17, Floor1Waves = { 1, 2, 3 }, FirstPower = 29, Growth = 2 }`, `Baseline { ember_phoenix, 35, Evo 1 }`) with these two corrections the spec requires: `LevelAnchors` must be NON-DECREASING in level (option A's `{ 4, 17 }, { 5, 15 }` zigzag is not allowed; start from `{ 1, 1 }, { 2, 4 }, { 3, 8 }, { 4, 15 }, { 10, 18 }, { 15, 26 }, { 20, 29 }, { 30, 39 }, { 40, 42 }, { 49, 58 }, { 60, 80 }, { 70, 100 }` and ease rounds 5-15 down until Ring 10 lands in 20-45 minutes, 30 the aim), and the last anchor stays `{ 70, 100 }` (`ringnh_catalog` pins round 1 / level 1 and the top at `MaxPetLevel`). Raids: move `Bosses[*].HpPerPlayer` (start 100 / 90 / 100 / 100) or `BossRules.MinHp` so the 4 / 8 owner-team cells land in 100-240 s while solo wins stay 0 of 8. Then run `SIM_BATTLE="full"` once (about 10 minutes) and paste the final table (every team's Default / Idle medians, the dungeon rooms and floors, the raid cells, the three progress minutes) into the `BattleCatalog.Ring` header comment (replacing the 2026-10-30 tuning note) and into the commit message.

Run: `$env:SIM_BATTLE='full'; py -3.12 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"`
Expected: `SUMMARY: N of N targets met` (every section; `levels` from Task 1 included).

- [ ] **Step 5: Rewrite the smoke checks that pinned the old numbers**: `p5battle_balance` (`smoke_p5_battlecore.lua:1652`) checks `SIM.Targets.Ring.S1` / `Owner` bands instead of `SIM.RingMedians`; `p5dgn_balance` keeps "the ladder never falls" and checks `SIM.Targets.Dungeon.S1.Room1` on a 3-Common team instead of "floor 1 cleared by every single L1 pet"; `ringnh_catalog` keeps its anchor checks (they still hold); every floor-1 flow scenario that fielded ONE level-1 pet to CLEAR a floor (`p5dgn_run`, `p5dgn_loot`, the `smoke_p5_flow.lua` new-player run, `p5dgn_tutorial`) fields a L7 Common trio or uses the test's held-attack helpers, as each scenario's comment allows; `README.md`: the Ring XP rule (`XpBase + XpPerRound x the round`), "floor 1 ... any single level-1 pet wins" wording, the raid baseline ("a level-35 evolved Legendary"). Report the economy effect: `py -3.12 tools/sim_tycoon.py --ring 0.08 --dungeon 0.1 --quiet` must still print `ALL TARGETS MET` (its inputs are unchanged; say so in the report).

- [ ] **Step 6: Run the gate**

Run: `py -3.12 tools/smoke.py --quick --only p5battle_balance,p5dgn_balance,ringnh_catalog,ringnh_sim_hp,p4ring_start,p5dgn_run,p5dgn_loot,p5dgn_tutorial,p2_final,tb_stats_formula` then `py -3.12 tools/sim_tycoon.py --check` then `node tools/check.mjs`
Expected: all pass; the report lists the final measured table including minutes to Ring 5, floor 1 and Ring 10.

- [ ] **Step 7: Commit and push** (`feat(balance): the owner's wall: 3 L1 Commons win 3 Ring rounds, Ring 10 in ~30 min, bosses from a L35 baseline` + the attribution lines; the measured table in the body).

---

### Task 3: Team model (Equipped == the active preset minus busy pets)

**Files:**
- Modify: `src/server/Services/DataService.lua` (header lines 1-330 API notes; `normalizeEquipped` 1339-1356; `P3.prune` 1594-1616; `P3.teamsSnapshot` 3323-3327; `pruneLive` 3061-3070; the two migration call sites 3594-3605 and 3970-3986; `SetTeam` / `SelectTeam` 4767-4820; `ActiveTeamKeys` 4902-4916; `GardenBusyKeys` 4867-4881; a new `P3.teamMigrate` next to `P6.itemsRefund` 5436)
- Modify: `src/server/Services/PetService.lua` (header; `validateEquipped` 475-502; `CanEquip` / `Equip` / `Unequip` / `UnequipKey` / `Refresh` 593-729; `rollAndGrant` 822-823)
- Modify: `src/server/Services/BattleService.lua` (header 92-97 and 739-761 `teamOf`; `RingRun.fighters` 2804-2874; `StartRing` step 3 at 3453-3457; `TeamSpec` 4258-4265)
- Modify: `src/server/Services/PetCareService.lua:1182-1221` (`Care.removePet`, `Care.returnPet`)
- Modify: `src/server/Services/DevService.lua:684-685` (the reset) and `cmdMaxPets` / `cmdPetLevel` refresh calls
- Modify: `src/server/Services/TutorialService.lua:1585-1650` (`TeamSet` reads `ActiveTeamKeys`'s first return only)
- Modify: `src/client/State.lua` (`cleanTeams` 460-490, new `State.Busy`, `State.ActiveTeam`)
- Modify: `tools/smoke_p4_ring.lua` (`p4ring_start`, the fallback block near 705), `tools/smoke_hud_team.lua:29` (`REFUSAL` text), `tools/smoke_p5_data.lua` (`p5data_team3`: a stored 4-key preset still loads with 3), `tools/contract.json`
- Create: `tools/smoke_tb_team.lua`; Modify: `tools/smoke.py`

**Interfaces:**
- Consumes: `DataService.GetProfile / MarkDirty / Sync / SyncSoon / TeamsChanged / TrainingKeys / GetGrowth / GetPetLevel`, `P3.placedCopies(profile)`, `P4.trainingSet(profile.PetGrowth)`, `ownedCount(profile, key)`, `P3.cleanPreset`, `P3.encodeTeams`, `PetKeys.List`, `BattleCatalog.UnitPower`.
- Produces (server):
  - `DataService.BusyKeys(player) -> { [key] = "Training" | "Garden" }` ({} until loaded / provisional): training keys, plus every owned key with NO copy free of the Garden / Gym (the old `GardenBusyKeys`, which stays as an alias).
  - `DataService.ActiveTeamKeys(player) -> keys, why`: the active preset minus busy keys, in order; `why` = `nil` when at least one key, `"Empty"` when the preset is empty, `"Busy"` when it has pets but all are busy. Equals `profile.Equipped` at all times.
  - `DataService.SyncEquipped(player) -> changed`: rewrites `profile.Equipped` from the invariant (MarkDirty + SyncSoon when changed; never fires TeamsChanged). Internal `P3.syncEquipped(profile)` is called at the end of `normalizeProfile` (replacing `normalizeEquipped`), `applyDelta` (the merge, after `P3.prune`), `pruneLive`, `SetTeam`, `SelectTeam`, `MutateHome`'s prune, and by `PetService.Refresh`.
  - `P3.prune(profile, teams)` keeps a key whose copies are ALL in the Garden / Gym or in training (busy keys keep their slot, spec s.1); it still drops keys not owned at all and keys past the 3 slots.
  - `DataService.SetTeam(player, preset, keys)` / `CheckTeam` keep today's refusals for a DIRECT pick of a gardening pet ("That pet is gardening! Take it out of the garden first", the client's recall prompt stays) and of a training pet (new: "<Pet> is training (2:10 left)"); a pet already in the team that becomes busy later stays.
  - `P3.teamMigrate(entry) -> info | nil` under `Migrations.B4TeamFollow`, run right after `P6.itemsRefund` in BOTH load paths (`announceRebase` and the loaded-profile step; a provisional profile waits for its recovery): with `Equipped` empty -> `Equipped = active preset minus busy`; else, in this order: a preset holding exactly the same key SET becomes active (Equipped takes ITS order); else the first empty preset takes `Equipped` and becomes active; else the highest-numbered non-active preset takes `Equipped` and becomes active. `info = { Preset = n, Case = "Empty" | "Same" | "Free" | "Replaced" }` in `entry.MigratedNow.B4TeamFollow`; no toast, no signal beyond `TeamsChanged`.
  - `P3.teamsSnapshot(profile)` adds `Busy = { [key] = "Training" | "Garden" }` (the ProfileSync `Teams` table and `GetTeams(player)` carry it).
  - `PetService.Equip(player, key) -> ok, reason`: puts the key in the active preset's first empty slot through `DataService.SetTeam` (refusals: "Your team is full (3 pets)", "That pet is already in your team", the gardening / training texts above); `PetService.Unequip(player, key)`: removes the key from the active preset (`SetTeam` with the slot emptied); `PetService.UnequipKey` is REMOVED (its one caller moves to `Refresh`); `PetService.Refresh(player)` = `DataService.SyncEquipped` + republish; `rollAndGrant`'s first-pet auto-equip writes the active preset's slot 1 through `SetTeam` when that preset is empty.
  - `BattleService.TEAM_REFUSALS = { Empty = "Your team is empty: open Pets and put a pet in it", Busy = "Your whole team is busy: training or gardening" }`; `teamOf` / `TeamSpec(player)` return `nil, TEAM_REFUSALS[why]` (the HUD-cleanup text "Pick your battle team first..." is gone); `RingRun.fighters(player) -> keys, why` has NO equipped / strongest fallback (the `owned` argument goes; `StartRing` step 3 refuses with `TEAM_REFUSALS[why]`).
  - `PetCareService`: a training pet keeps its slot: `Care.removePet` calls `PetService.Refresh` instead of `UnequipKey`; `Care.returnPet(from == "Follow")` calls `PetService.Refresh` (the pet is back by itself, the slot was never freed).
  - `DevService` reset: `teams.Presets = { {}, {}, {} }; teams.Active = 1` then `DataService.SyncEquipped`; `/maxpets`, `/petlevel`, `/levelall` keep calling `PetService.Refresh`.
- Produces (client): `State.Busy(key) -> nil | "Training" | "Garden"` (from `Teams.Busy`), `State.ActiveTeam() -> { key... }` (= the snapshot's `Equipped`; `State.EquippedList` stays an alias), `State.Teams().Busy` cleaned like `Presets`.
- Remotes: none added; `EquipPet` / `UnequipPet` / `BattleRequest("TeamSet" | "TeamSelect")` keep their shapes.

- [ ] **Step 1: Write the failing smoke file `tools/smoke_tb_team.lua`** (server world, booted, `K.freshPlayers`; the `smoke_hud_team.lua` server-half shape). Scenarios and assertions (`eq(a, b)` = same list; `inv(p)` = `DS.GetProfile(p).Equipped` equals `DS.ActiveTeamKeys(p)`):

```lua
-- tb_team_invariant
DS.SetTeam(a, 1, { K1, K2, K3 }); T.check(inv(a) and eq(prof.Equipped, { K1, K2, K3 }), "tb team: SetTeam on the active preset = the followers")
DS.SetTeam(a, 2, { K4 }); T.check(eq(prof.Equipped, { K1, K2, K3 }), "tb team: editing another preset changes no follower")
DS.SelectTeam(a, 2); T.check(eq(prof.Equipped, { K4 }) and a:GetAttribute("EquippedPets") == K4, "tb team: selecting B swaps all followers at once (attribute too)")
DS.SetTeam(a, 3, {}); DS.SelectTeam(a, 3); T.check(#prof.Equipped == 0 and a:GetAttribute("EquippedPets") == "", "tb team: an empty active team = no followers")
DS.SelectTeam(a, 1); T.eq(select(1, PS.Equip(a, K4)), false, "tb team: Equip refuses a full team"); T.check(select(2, PS.Equip(a, K4)) == "Your team is full (3 pets)", "...with the team wording")
T.check(PS.Unequip(a, K2) == true and eq(prof.Teams.Presets[1], { K1, K3 }) and eq(prof.Equipped, { K1, K3 }), "tb team: Unequip removes the key from the active preset")
T.check(PS.Equip(a, K4) == true and eq(prof.Teams.Presets[1], { K1, K3, K4 }), "tb team: Equip fills the first empty slot of the active preset")
-- a merge (two-server): the delta of a session that selected B, applied on a store where A changed: Equipped follows the merged active preset (use the DataService merge helpers smoke_p5_data.lua uses)
-- tb_team_busy
startTraining(a, K1) -- PetCareService.Train
T.check(eq(prof.Teams.Presets[1], { K1, K3, K4 }) and eq(prof.Equipped, { K3, K4 }) and DS.BusyKeys(a)[K1] == "Training", "tb team: a training pet keeps its slot and leaves the followers (Review Focus 2)")
local keys, why = DS.ActiveTeamKeys(a); T.check(keys[1] == K3 and why == nil, "tb team: the next free pet is the fighter")
toRing(a); local okR = BS.StartRing(a); T.check(okR == true and BS.KeysInBattle(a)[K3] and not BS.KeysInBattle(a)[K1], "tb team: the Ring fields slot 2 as the fighter while slot 1 trains")
finishTraining(a, K1); T.check(eq(prof.Equipped, { K1, K3, K4 }), "tb team: the job ends: the pet is back by itself (no Job.From Follow)")
gardenAll(a, K3); T.check(DS.BusyKeys(a)[K3] == "Garden" and eq(prof.Equipped, { K1, K4 }) and eq(prof.Teams.Presets[1], { K1, K3, K4 }), "tb team: every copy in the Garden = busy, slot kept")
startTraining(a, K1); gardenAll(a, K4); local k2, why2 = DS.ActiveTeamKeys(a); T.check(#k2 == 0 and why2 == "Busy", "tb team: all busy = Busy")
T.check(select(2, BS.TeamSpec(a)) == BS.TEAM_REFUSALS.Busy and select(2, BS.StartRing(a)) == BS.TEAM_REFUSALS.Busy, "tb team: a battle is refused and says why")
T.check(select(2, DS.SetTeam(a, 1, { K3 })) == "That pet is gardening! Take it out of the garden first", "tb team: a DIRECT pick of a gardening pet still asks for the recall")
-- tb_team_refusal
DS.SetTeam(b, 1, {}); T.check(select(2, DS.ActiveTeamKeys(b)) == "Empty" and select(2, BS.TeamSpec(b)) == BS.TEAM_REFUSALS.Empty and select(2, DGS.StartSolo(b, 1)) == BS.TEAM_REFUSALS.Empty, "tb team: an empty team is refused everywhere with the Empty text")
-- b owns 3 pets and has them equipped nowhere: StartRing must NOT field them
T.check(select(2, BS.StartRing(b)) == BS.TEAM_REFUSALS.Empty and BS.IsInBattle(b) == false, "tb team: no 'else strongest' fallback")
-- tb_team_migrate (profiles written straight into the store fixture, then loaded; Migrations.B4TeamFollow absent)
-- case Empty: Equipped {}, Presets { {K1,K2}, {}, {} } Active 1 -> Equipped {K1,K2}
-- case Same: Equipped {K2,K1}, Presets { {K3}, {K1,K2}, {} } Active 1 -> Active 2, Equipped {K1,K2} (the preset's order; Review Focus 1)
-- case Free: Equipped {K1}, Presets { {K3}, {}, {K2} } Active 1 -> Presets[2] = {K1}, Active 2
-- case Replaced: Equipped {K1}, Presets { {K2}, {K3}, {K4} } Active 2 -> Presets[3] = {K1}, Active 3, Presets[1] and [2] untouched
-- every case: Migrations.B4TeamFollow == true, MigratedNow.B4TeamFollow.Case == the name, every Pets count and Tokens unchanged, a second load changes nothing, a provisional load migrates after its recovery (the B3ItemsRefund pattern)
-- tb_team_rollout: the frozen tools/fixtures/DataService_phase4.lua profile (used by p5home_rollout) loads with the invariant and no lost key
```

Register: `server_files.append("smoke_tb_team.lua"); ins(server_scenarios, "p4ring_start", ["tb_team_invariant", "tb_team_busy", "tb_team_refusal", "tb_team_migrate", "tb_team_rollout"])`.

- [ ] **Step 2: Run it to verify it fails**

Run: `py -3.12 tools/smoke.py --quick --only tb_team_invariant,tb_team_busy,tb_team_refusal,tb_team_migrate,tb_team_rollout`
Expected: FAIL at "SetTeam on the active preset = the followers" (today `Equipped` does not follow the preset).

- [ ] **Step 3: Implement the DataService half**: `P3.busyOf(profile) -> {[key] = "Training" | "Garden"}`, `P3.syncEquipped(profile)`, the `P3.prune` rule, `teamsSnapshot.Busy`, `DataService.BusyKeys / ActiveTeamKeys (keys, why) / SyncEquipped`, `P3.teamMigrate(entry)` + `P3.MARK_TEAM = "B4TeamFollow"` at both call sites, the `SetTeam` training refusal, and the header notes (lines 203-228 and the migration list at 276-290).

- [ ] **Step 4: Implement the PetService, BattleService, PetCareService, DevService, TutorialService and State halves** per the Interfaces block (`Equip` / `Unequip` through `SetTeam`; `UnequipKey` deleted and removed from `tools/contract.json`; `RingRun.fighters(player)` without fallbacks; `TEAM_REFUSALS`; `Care.removePet` / `returnPet`; the dev reset; `TutorialService`'s `TeamSet` check uses the first return of `ActiveTeamKeys`; `State.Busy` / `State.ActiveTeam`). Update the `BattleService` header (lines 33-35, 92-97) and `PetService` header.

- [ ] **Step 5: Rewrite the pinned tests**: `p4ring_start` (the fallback block near `smoke_p4_ring.lua:705` becomes "no team = refused with TEAM_REFUSALS.Empty; the equipped-only legacy save migrated into preset 1 fields its pets"), `smoke_hud_team.lua` `REFUSAL` = `TEAM_REFUSALS.Empty` (the rest of that file is replaced in Task 5), `p5data_team3` (a stored 4-key preset still loads with 3; Equipped = those 3), any `smoke_p2_*` / `smoke_p3_*` / `smoke_p4_*` check that asserted `Equipped` and `Teams.Presets` independently (grep `Presets\[` and `Equipped` in `tools/smoke_*.lua`; rewrite each to the invariant). Add `BusyKeys`, `SyncEquipped` to `server/Services/DataService` and `TEAM_REFUSALS` to `server/Services/BattleService` fields in `tools/contract.json`.

- [ ] **Step 6: Run the gate**

Run: `py -3.12 tools/smoke.py --quick --only tb_team_invariant,tb_team_busy,tb_team_refusal,tb_team_migrate,tb_team_rollout,p4ring_start,hudteam_refusal,p5data_team3,p3data_teams,p4data_training,p4care_train,p4garden_place,p2fusion_mix,dev_tools,p5dgn_party,p5flow_newplayer,p4flow_home,ringnh_service` (use `--list` to confirm the exact names of the p2-p5 scenarios named here) then the full `py -3.12 tools/smoke.py --quick` (20-30 minutes) then `node tools/check.mjs`
Expected: everything passes except `p3fixsrv_net16` (known); 0 errors.

- [ ] **Step 7: Commit and push** (`feat(team): the followers are the active preset minus busy pets; A/B/C select; the B4TeamFollow migration; no strongest fallback` + attribution).

---

### Task 4: The Pets window (one big window, slots pinned on top)

**Files:**
- Create: `src/client/Controllers/PetsController.lua`
- Modify: `src/client/Controllers/MenuController.lua` (header 1-95; `MENU` tile action `menuActionPets` 2037 and 2123; `onOpenPanel` 8750-8768 routes; `OpenTeam` 8908-8913; `createWindow Inventory` 8977 removed; DELETE `buildInventory` / `buildPetsPage` / the Team tab hooks 2857-3850 and `P3.Define` 6508-7900; keep `P2.askRecall`, `P2.statsAt`, `P5.battlePower`, `P5.evoSlot` by moving them into `PetsController` or a shared `src/client/UI/PetBits.lua` if `MenuController` no longer uses them)
- Modify: `src/client/Main.client.lua:13-55` (boot list + `OPTIONAL`: `PetsController` after `MenuController`)
- Modify: `src/client/Controllers/CareController.lua` only if `Open("Feed" | "Garden" | "Train" | "Evolve", { Key })` needs a `ReturnTo` (it does: on close it calls `PetsController.Open(args.ReturnTo)` when given)
- Modify: `tools/dump_gui.lua` (scenarios `pets[:phone|:pick|:sheet|:<key>]` replacing `team` / `menu:Pets`), `tools/smoke_p5_gui.lua` (the `dock:Pets` COVER entry replaced by the real window; the cover scenario honours `MaxCover` / `Centered`), `tools/render_gui.py --list`, `tools/contract.json` (`client/Controllers/PetsController`, the removed `MenuController` members), `README.md` (the Pets window section, the "Equip" words)
- Modify / delete the client tests of the old tabs: `tools/smoke_hud_team.lua` (`client_hudteam_tab` removed), `tools/smoke_p4_careui.lua` (the Pets panel checks), `tools/smoke_p5_looks.lua` (Pets / Team sites), `tools/smoke_client.lua` / `smoke_client_v2.lua` (Window_Inventory checks), `tools/smoke_bug2_gui.lua:101`, `tools/smoke_p3_ui.lua:583-590`, `tools/smoke_p5_menu.lua` (the Pets tile)
- Create: `tools/smoke_tb_pets.lua`; Modify: `tools/smoke.py`

**Interfaces:**
- Consumes: `State.Get / Keys / DefOf / PetLevel / PetGrowth / PetStage / Teams / ActiveTeam / Busy / IsTraining / OwnedCount / Changed`, `BattleCatalog.UnitPower / TeamPower / SynergyBonus / BattleStatsOf`, `PetCatalog.StatsOf / GetRarity / ElementsOf`, `Config.Elements.Info[element].Color`, `CloudUI.NewScreenGui / Panel / Slot / Button / Grid / SetDisabled`, `NeonKit`, `Theme.Colors / ScaledSize / ScreenFactor`, `SoundFx.Play(name)`, `Remotes` (`BattleRequest "TeamSet" / "TeamSelect"`, `EquipPet` is no longer used by this window), `MenuController.WindowOpened` (a Util.Signal), `MenuController.Hint(text, kind)`, `CareController.Open(panelId, { Key, ReturnTo })`, `P2.askRecall`'s logic (the gardening recall prompt: `HomeAction "GardenRecall" { Key, To = "Team", Preset, Keys }`), `GuiService:GetGuiInset()`.
- Produces:
  - `PetsController.Init()`, `PetsController.Open(args)` with `args = { Key = string | nil (select this pet), Pick = 1..3 | nil (open in pick mode on that slot), Preset = 1..3 | nil (show that team), ReturnTo = table | nil (handed back on close, see below) }`, `PetsController.Close()`, `PetsController.IsOpen() -> bool`, `PetsController.Opened` / `PetsController.Closed` (Util.Signals; `Closed:Fire(returnTo | nil)`), `PetsController.SetSort("Strongest" | "Rarest" | "Level")` and `PetsController.Sort() -> mode`, `PetsController.Layout() -> "PC" | "Phone"`.
  - ScreenGui `NimbusPets` (`DisplayOrder` 20, `IgnoreGuiInset = true`), Frame `PetsWindow` (a `CloudUI.Panel`, title "Pets", `Closable`, accent Orange): PC 1920x1080 -> 1260x900 centred; phone 844x390 -> 820x330 under the top-bar inset; other viewports scale between; the layout is `"Phone"` when the window's width is under 760 design px.
  - Widget names (tests and `render_gui` read them): `Slot1..Slot3` (each with `Face` viewport, `Tag` "FIGHTER" | "HELPER", `Level`, `Power`, `Busy` mark, `Glow` while in pick mode; an empty slot shows `Empty` "Empty"), `PresetA` / `PresetB` / `PresetC` (TextButtons, the active one lit), `TeamPower` ("Team power 918") and `TeamBreakdown` ("Fighter 358 + helpers 281, 279 + team bonus"), `AutoFill` ("Auto-fill best"), `ClearTeam` ("Clear", second tap confirms within 3 s, label "Tap again to clear"), `SortButton` ("Strongest" / "Rarest" / "Level", one control for the whole window), `Grid` (the ONLY ScrollingFrame), `Card_<key>` (ImageButton / TextButton per owned copy: `Picture` viewport, `Level` "L12", `Element` icon tinted `Config.Elements.Info[e].Color`, `Power`, a `Rarity` border stroke, `Number` badge 1-3 when on the active team, `Busy` mark, the tier / stars from `PetCard` rules, `Name` on PC cards), `Detail` (PC: the selected pet's `Name`, rarity, stat rows `Row_Income` "Coins", `Row_Power` "Battle power", `Row_Health` "Health", `Row_Speed` "Speed" (values from Task 1's split), `Perks`) and `Sheet` (phone: over the grid, never over the slots column, big actions at the bottom edge, `SheetClose`), actions `ActPut` ("Put in team"), `ActFighter` ("Make fighter"), `ActRemove` ("Remove"), `ActFeed`, `ActTrain`, `ActGarden`, `ActEvolve` (each >= 44 px high on a phone; `CloseButton` and the sort / preset chips too), `PickBanner` ("Pick a helper for slot 2" / "Pick your fighter"; `PickCancel` X).
  - Behaviour: pick mode (tap a slot -> banner + glow; tap a pet -> `BattleRequest("TeamSet", active, newKeys)` at once, the slot shows the pet at once with a pop tween and `SoundFx.Play("SpinLand")` (the roulette's landing thud, an approved id; `"Confirm"` when it has no id); a pet already in another slot swaps positions; the slot's own pet offers Remove; tapping the slot again or X cancels); outside pick mode `ActPut` fills the first empty slot or enters pick mode on slot 1 when full; a team pet offers `ActFighter` (swap with slot 1) and `ActRemove`; `AutoFill` writes `Best(3)` (the 3 strongest fieldable keys by `UnitPower`, busy pets excluded) to the ACTIVE preset only and shows a hint "Team filled" with an `Undo` button for 6 s that sends the previous keys; `PresetX` -> `BattleRequest("TeamSelect", n)`; a server refusal (the next ProfileSync does not show the keys, or a `Notify` kind "bad" arrives within 2.5 s) shows the refusal in a toast (`MenuController.Hint(text, "bad")`) AT ONCE and leaves the slot as it was (no silent revert); a gardening pet dropped on a slot goes through the recall prompt (`askRecall` with `To = "Team"`) first; Feed / Train / Garden / Evolve open `CareController.Open(panel, { Key, ReturnTo = { Window = "Pets", Key } })` with today's rules and the EVOLVE confirm; `TeamPower` counts busy pets out; the window fires `MenuController.WindowOpened:Fire("Pets")` once per opening (the tutorial's "Equipped" hook) and never says "Equip" / "Equipped" anywhere.
  - Return: `PetsController.Close()` fires `Closed(args.ReturnTo)`; Task 5 routes `ReturnTo` tables.
  - `tools/smoke_p5_gui.lua` COVER entries gain two optional fields the cover scenario honours: `MaxCover = <percent>` (default 60) and `Centered = true` (skips the "window right of the middle / bottom sheet" rule); the Pets window registers `{ Scene = "pets", MaxCover = 85, Centered = true }` (the spec's approved sizes: 54.7% on 1080p, 82% on 844x390); the >= 14 / 15 px text floor still applies.
  - `MenuController.Open("Pets" | "Team" | "Inventory", args)` and `MenuController.OpenTeam(preset)` delegate to `PetsController.Open` (`Team` -> `{ Preset = args.Preset }`); the `Pets` tile opens it; `Window_Inventory` no longer exists.

- [ ] **Step 1: Write the failing smoke file `tools/smoke_tb_pets.lua`** (client world 1920x1080 + phone world 844x390 touch; a synced profile with 8 pets incl. one training, one fully gardening, one Golden tier, one evolved; the `smoke_hud_team.lua` client-half shape):

```lua
-- client_tb_pets_pc
PC.Open({}); advance(0.5)
local win = pg():FindFirstChild("NimbusPets"):FindFirstChild("PetsWindow", true)
T.check(shown(win) and PC.Layout() == "PC" and math.abs(win.AbsoluteSize.X - 1260) <= 2 and math.abs(win.AbsoluteSize.Y - 900) <= 2 and math.abs(win.AbsolutePosition.X + win.AbsoluteSize.X / 2 - 960) <= 2, "tb pets: 1260x900 centred at 1080p")
T.check(menu():FindFirstChild("Window_Inventory") == nil, "tb pets: no Window_Inventory any more")
T.check(opened[#opened] == "Pets", "tb pets: WindowOpened('Pets') fired once")
for i = 1, 3 do T.check(win:FindFirstChild("Slot" .. i, true) ~= nil, "tb pets: Slot" .. i) end
T.check(win.Slot1.Tag.Text == "FIGHTER" and win.Slot2.Tag.Text == "HELPER", "tb pets: FIGHTER / HELPER tags")
T.check(#scrollingFrames(win) == 1 and scrollingFrames(win)[1].Name == "Grid", "tb pets: the grid is the only scroller (no nested scrolling)")
T.check(cardOrder()[1] == strongestKey and PC.Sort() == "Strongest", "tb pets: sorted Strongest by default")
click(win.SortButton); T.check(PC.Sort() == "Rarest" and cardOrder()[1] == rarestKey, "tb pets: one sort control; Rarest")
T.check(card(trainingKey).Busy.Visible and card(gardenKey).Busy.Visible and card(K1).Number.Text == "1", "tb pets: busy marks and the team number badge")
T.check(win.TeamPower.Text:find(tostring(expectedPower), 1, true) and win.TeamBreakdown.Text:find("^Fighter %d+ %+ helpers"), "tb pets: team power with the one-line breakdown (busy pets left out)")
T.check(noText(win, "Equip") and noText(win, "Equipped"), "tb pets: the Equip words are gone")
click(win.PresetB); T.check(lastRequest("BattleRequest").args[1] == "TeamSelect" and lastRequest("BattleRequest").args[2] == 2, "tb pets: B sends TeamSelect(2)")
-- client_tb_pets_pick
click(win.Slot2); T.check(win.PickBanner.Visible and win.PickBanner.Text == "Pick a helper for slot 2" and win.Slot2.Glow.Visible, "tb pets: pick mode on slot 2")
click(card(K5)); T.check(teamSetArgs()[2][2] == K5 and win.Slot2.Level.Text == "L" .. level(K5), "tb pets: one tap drops the pet in slot 2 at once (TeamSet) with the pop")
T.check(sounds()[#sounds()] == "SpinLand", "tb pets: the heavy sound is an approved id")
click(win.Slot3); click(card(K1)); T.check(teamSetArgs()[2][1] == K5 or teamSetArgs()[2][3] == K1, "tb pets: a pet already in another slot swaps positions")
click(win.Slot1); click(card(gardenKey)); T.check(recallPromptShown() and win.Slot1.Level.Text == "L" .. level(teamNow[1]), "tb pets: a gardening pet asks for the recall, the slot stays (Review Focus 3)")
cancelRecall(); T.check(win.PickBanner.Visible and win.Slot1.Glow.Visible, "tb pets: ...and pick mode stays armed on the same slot")
KC.toClient("Notify", "That pet is training (2:10 left)", "bad", 3); T.check(hintText():find("training", 1, true), "tb pets: a server refusal shows in the toast at once")
click(win.PickCancel); T.check(not win.PickBanner.Visible, "tb pets: X cancels")
click(win.AutoFill); T.check(eq(teamSetArgs()[2], best3) and hintText():find("Team filled") and undoButton().Visible, "tb pets: Auto-fill best writes the active team and offers Undo")
click(undoButton()); T.check(eq(teamSetArgs()[2], previousKeys), "tb pets: Undo sends the previous keys")
click(win.ClearTeam); T.check(#teamSetCalls() == before and win.ClearTeam.Text == "Tap again to clear", "tb pets: Clear asks for a second tap"); click(win.ClearTeam); T.check(#teamSetArgs()[2] == 0, "tb pets: ...the second tap clears")
-- client_tb_pets_actions
click(card(K2)); T.check(win.Detail.Name.Text == name(K2) and win.Detail.Row_Power.Label.Text == "Battle power", "tb pets: selecting shows the detail with the Battle power row")
click(win.ActPut); T.check(teamSetArgs()[2][1] == K2, "tb pets: Put in team fills the first empty slot")
click(card(K2)); click(win.ActFighter); T.check(teamSetArgs()[2][1] == K2, "tb pets: Make fighter swaps with slot 1")
click(win.ActFeed); T.check(CareController.IsOpen() and CareController.Mode() == "Feed", "tb pets: Feed opens the Food Machine list"); CareController.Close(); T.check(PC.IsOpen(), "tb pets: ...and comes back to the window")
click(win.ActEvolve); T.check(CareController.IsOpen() and CareController.Mode() == "Evolve", "tb pets: Evolve keeps its confirm")
-- client_tb_pets_phone (phone world 844x390 touch)
PC.Open({}); advance(0.5)
T.check(PC.Layout() == "Phone" and math.abs(win.AbsoluteSize.X - 820) <= 2 and math.abs(win.AbsoluteSize.Y - 330) <= 2 and win.AbsolutePosition.Y >= GuiService:GetGuiInset().Y - 0.5, "tb pets: 820x330 under the top bar")
T.check(win.Slot1.AbsolutePosition.X < win.Grid.AbsolutePosition.X and shown(win.Slot3), "tb pets: the slots in a column on the left, always visible")
T.check(math.abs(card(K1).AbsoluteSize.X - 104) <= 2 and math.abs(card(K1).AbsoluteSize.Y - 130) <= 2, "tb pets: 104 x 130 cards")
for _, b in ipairs(targets(win)) do T.check(b.AbsoluteSize.Y >= 44, "tb pets: " .. b.Name .. " >= 44 px") end
click(card(K2)); T.check(win.Sheet.Visible and win.Sheet.AbsolutePosition.X >= win.Slot1.AbsolutePosition.X + win.Slot1.AbsoluteSize.X - 0.5 and win.Sheet.ActPut.AbsolutePosition.Y + win.Sheet.ActPut.AbsoluteSize.Y >= win.AbsolutePosition.Y + win.AbsoluteSize.Y - 60, "tb pets: the sheet opens over the grid, not the slots, big actions at the bottom edge")
T.check(win.Sheet.Name.Text == name(K2), "tb pets: the name shows in the phone sheet")
```

Register: `client_files.append("smoke_tb_pets.lua"); ins(client_scenarios, "client_final", ["client_tb_pets_pc", "client_tb_pets_pick", "client_tb_pets_actions"]); mobile_scenarios.append("client_tb_pets_phone")`.

- [ ] **Step 2: Run it to verify it fails**

Run: `py -3.12 tools/smoke.py --quick --only client_tb_pets_pc,client_tb_pets_pick,client_tb_pets_actions,client_tb_pets_phone`
Expected: FAIL at the first `NimbusPets` lookup (no such ScreenGui).

- [ ] **Step 3: Implement `src/client/Controllers/PetsController.lua`** per the Interfaces block, following the pitch's mock-ups (`Projects Main/Nimbus/.superpowers/team-balance-pitch/page.html` rows "petswindow" PC / phone). Keep it under about 2,500 lines by splitting the card builder into `src/client/UI/PetTile.lua` (`PetTile.New(parent, entry, opts) -> { Root, Set(entry), Destroy }`) if it grows past that. Move `P2.askRecall`, `P2.statsAt` / `battleStatsAt`, `P5.battlePower`, `P5.evoSlot` out of `MenuController` into `src/client/UI/PetBits.lua` and require it from both.

- [ ] **Step 4: Remove the old tabs from `MenuController`** (`buildInventory` with the Pets page and the Team tab hooks, `P3.Define`, the `Inventory` `createWindow`, the `Window_Inventory` references in `relayoutMenu` / `updateMenuActive` / `onStateChanged`'s badge), route `Open("Pets" | "Team" | "Inventory")` and `OpenTeam` to `PetsController`, keep `WindowOpened` and `Hint`, and add `PetsController` to `Main.client.lua`. `MenuController` must end SMALLER than 9,031 lines (say the count in the commit message) and under the 60-upvalue limit (`py -3.12 tools/count_locals.py` if it reports upvalues; else the smoke boot fails loudly).

- [ ] **Step 5: Rewrite the dependent tests and tools**: `tools/dump_gui.lua` scenarios `pets` (PC), `pets:phone`, `pets:pick`, `pets:sheet`, `pets:<key>`; `render_gui.py --list`; the `tools/smoke_p5_gui.lua` cover entry (`MaxCover` / `Centered` support in `client_p5gui_cover`); the old-tab checks listed under Files (each rewritten to the new names or removed when it tested a removed widget: say which in the commit message); `tools/contract.json`: add `client/Controllers/PetsController` (`Init`, `Open`, `Close`, `IsOpen`, `SetSort`, `Sort`, `Layout`; signals `Opened`, `Closed`), remove `MenuController` members that no longer exist; `README.md`: the Pets window section (slots on top, A / B / C, Auto-fill best, Clear, sort; no "Equip").

- [ ] **Step 6: Run the gate**

Run: `py -3.12 tools/smoke.py --quick --only client_tb_pets_pc,client_tb_pets_pick,client_tb_pets_actions,client_tb_pets_phone,client_p5gui_cover,client_gui_dump,client_p4careui,client_p5looks,client_tb_stats_rows,client_p5menu,client_tutorial,p2_final` (confirm names with `--list`), then `py -3.12 tools/render_gui.py pets --grid -o <scratchpad>/pets.png` and look at the four sizes, then `node tools/check.mjs`
Expected: all pass; the render shows the slots pinned on top (PC) / left column (phone) and no text under the floor; 0 errors.

- [ ] **Step 7: Commit and push** (`feat(pets): the Pets window: slots on top, A/B/C, pick mode, sort, phone sheet; the Pets and Team tabs removed from MenuController` + attribution).

---

### Task 5: Battle panels (faces + Edit team; TeamPick gone)

**Files:**
- Create: `src/client/UI/TeamFaces.lua`
- Modify: `src/client/Controllers/ArenaController.lua` (`teamPick` / `withTeam` / `teamStrip` / `openTeamWindow` 614-668; the Ring window's fighters section `Ring.build` 1188-1300, `Ring.layout` 1320-1345, `Ring.refresh` 1432-1460 and `Ring.fighters` 918-946; the Duels / Raid pages where `teamStrip(...)` is called; header 21-39)
- Modify: `src/client/Controllers/DungeonController.lua` (`teamPick` 289-320, the strip 1137-1160, `H.teamPowerNow` 628-665 (no fallbacks), header 24-26)
- Modify: `src/client/Controllers/PetsController.lua` (the `ReturnTo` router in `Close`)
- Delete: `src/client/TeamPick.lua`
- Modify: `src/shared/TutorialSteps.lua:288-298` (the "team" step), `src/shared/NpcDialog.lua:427-434` (Coach Corgi), `src/client/Controllers/TutorialController.lua:174-184` (`HOOK_FOR` / the Pets hint), `src/server/Services/TutorialService.lua` only if a hint text lives there
- Modify: `tools/contract.json` (`client/TeamPick` removed; `client/UI/TeamFaces` added), `README.md` (portal panels: "the three faces + Edit team"; the tutorial step text), `tools/dump_gui.lua` (`ring`, `arena:*`, `dungeon` scenes still render), `tools/smoke_p5_gui.lua` (the Ring / Arena / Dungeon cover entries unchanged in name)
- Delete: `tools/smoke_hud_team.lua` (+ its line in `tools/smoke.py`); Modify: `tools/smoke_p4_ui.lua`, `tools/smoke_p3_ui.lua`, `tools/smoke_p5_tutorial.lua` (`p5ui_content` needles for the team step), `tools/smoke_ring_noheal_client.lua` if it reads "Your fighters"
- Create: `tools/smoke_tb_panels.lua`; Modify: `tools/smoke.py`

**Interfaces:**
- Consumes: `State.ActiveTeam / Busy / Teams / Keys / DefOf / PetLevel / PetGrowth / PetStage / Changed`, `BattleCatalog.UnitPower / TeamPower`, `PetsController.Open(args) / Closed`, `ArenaController.OpenRing(start, portal) / OpenArena(tab) / Close()`, `DungeonController.Open(floorIndex, portal) / Close()`, `MenuController.Hint`, `CloudUI`, `NeonKit`, `PetCard`'s level / star rules, `Theme`.
- Produces:
  - `TeamFaces.New(parent, props) -> { Root, Refresh = fn, Destroy = fn }` with `props = { LayoutOrder, Compact = bool, Column = bool (phone: a vertical column), ReturnTo = table (what Edit team hands to PetsController) }`: Frame `TeamFaces` holding `Face1..Face3` (each: `Picture` viewport, `Tag` "FIGHTER" | "HELPER", `Level` "L12", `Power`, `Busy` mark; an empty face shows `Empty` "Empty"), `TeamPower` and TextButton `EditTeam` ("Edit team", >= 44 px on a phone). Refreshes on `State.Changed` (one shared connection; destroyed rows drop out). `TeamFaces.Entries() -> { { Key, Def, Level, Tier, Power, Busy }... }` of `State.ActiveTeam()` (busy pets are NOT in it: they do not fight); `TeamFaces.Power() -> number` (`TeamPower` of the entries, 0 when empty).
  - `TeamFaces.Ensure(continueFn, returnTo) -> bool`: `continueFn()` at once when `State.ActiveTeam()` is not empty; with 0 owned pets the hint "You need a pet: spin a roulette in the Cloud Shop." and nothing else; otherwise `PetsController.Open({ Pick = 1, ReturnTo = returnTo })` and NO automatic continue (the player presses the panel's button again after editing: never a silent auto-fill).
  - `ReturnTo` tables: `{ Window = "Ring", Start = n }`, `{ Window = "Dungeon", Floor = f }`, `{ Window = "Arena", Tab = "Duels" | "Raid" }`, `{ Window = "Loss" }` (Task 6); `PetsController.Close()` routes them: Ring -> `ArenaController.OpenRing(Start)`, Dungeon -> `DungeonController.Open(Floor)`, Arena -> `ArenaController.OpenArena(Tab)`, Loss -> `LossScreen.Reopen()` (Task 6).
  - Ring window: `Ring.fighters()` returns `TeamFaces.Entries()` only (no equipped / strongest sources; the three titles at line 1451 go); the fighters section is a `TeamFaces` row placed ABOVE the footer buttons on every screen size (landscape phone: the right column, as the pitch's mock-up); START / CONTINUE go straight in (`BattleRequest("Ring", start)`) when the team is not empty, else `TeamFaces.Ensure`; the window's own `EditButton` is replaced by the row's `EditTeam` (ReturnTo Start = the picked tile, boss starts included).
  - Dungeon panel: the party box's first row is `TeamFaces` (Compact on short screens); SOLO / PARTY / JOIN / READY / START use `TeamFaces.Ensure`; `H.teamPowerNow()` = `TeamFaces.Power()`.
  - Arena Duels / Raid pages: `teamStrip(parent)` -> `TeamFaces.New(parent, { LayoutOrder = 0, ReturnTo = { Window = "Arena", Tab } })`; Find a match / JOIN RAID / Challenge / Accept use `TeamFaces.Ensure`.
  - Texts: `TutorialSteps` "team" step `Text = "Battles need 3 pets: a fighter and 2 helpers! Open Pets, tap a slot and pick a pet, or tap Auto-fill best!"`, `Hint = "Open Pets: put 3 pets in your team"` (97-125 bytes once filled; check with `#text`); Coach Corgi's line 429 says "Open Pets" instead of "Tap Team" (<= 125 bytes); `TutorialController`'s Pets hint "Tap the glowing Pets button" stays.

- [ ] **Step 1: Write the failing smoke file `tools/smoke_tb_panels.lua`** (server half for texts, client + phone halves; port the still-valid parts of `smoke_hud_team.lua`'s `client_hudteam_portal` / `client_hudteam_mobile`):

```lua
-- tb_panels_text (server, pure)
T.check(#stepText("team") >= 97 and #stepText("team") <= 125 and stepText("team"):find("Auto%-fill best") and not stepText("team"):find("Team tab"), "tb panels: the team step names the new controls, 97-125 bytes")
T.check(not anyNpcLine():find("Tap Team") and corgiLine():find("Open Pets"), "tb panels: Coach Corgi points at Pets")
T.check(Client:FindFirstChild("TeamPick") == nil, "tb panels: client/TeamPick is gone")
-- client_tb_faces_ring (1920x1080; a profile with a 3-pet team, one of them training; Ring.Best = 20)
AC.OpenRing(20); advance(0.5)
local row = ringWin():FindFirstChild("TeamFaces", true)
T.check(row and row.Face1.Tag.Text == "FIGHTER" and row.Face2.Level.Text == "L" .. level(K2) and row.Face3.Empty.Visible, "tb panels: three faces; the training pet is not fielded (its face is Empty)")
T.check(row.AbsolutePosition.Y + row.AbsoluteSize.Y <= ringFooter().AbsolutePosition.Y + 0.5 and inside(row, ringWin()), "tb panels: the row sits above the buttons, never clipped")
T.check(ringWin():FindFirstChild("FightersTitle", true) == nil and noText(ringWin(), "your strongest pets") and noText(ringWin(), "equipped"), "tb panels: no fallback titles")
click(ringWin().Start); T.check(lastRequest("BattleRequest").args[1] == "Ring" and lastRequest("BattleRequest").args[2] == 20, "tb panels: CONTINUE goes straight in with that team")
-- client_tb_faces_return
click(row.EditTeam); T.check(PetsController.IsOpen() and not AC.IsOpen(), "tb panels: Edit team opens the Pets window")
PetsController.Close(); advance(0.3); T.check(AC.State().Window == "Ring" and AC.State().RingStart == 20, "tb panels: ...and returns to the Ring window at Start 20 (Review Focus 4)")
DC.Open(3); click(dungeonRow().EditTeam); PetsController.Close(); advance(0.3); T.check(DC.IsOpen() and DC.GetState().Floor == 3, "tb panels: the Dungeon window returns on floor 3")
AC.OpenArena("Raid"); click(arenaRow().EditTeam); PetsController.Close(); advance(0.3); T.check(AC.State().Window == "Arena" and AC.State().Tab == "Raid", "tb panels: the Arena returns on the same tab")
-- client_tb_faces_empty (a profile with 3 owned pets and an EMPTY active team)
DC.Open(1); click(dungeonSolo()); T.check(PetsController.IsOpen() and petsWin().PickBanner.Visible and petsWin().Slot1.Glow.Visible and #callsAfter("DungeonRequest", n0) == 0, "tb panels: SOLO with an empty team opens the Pets window in pick mode on slot 1 and sends nothing")
PetsController.Close(); T.check(DC.IsOpen() and #callsAfter("DungeonRequest", n0) == 0, "tb panels: closing without a team does not enter (no silent auto-fill)")
T.check(pg():FindFirstChild("NimbusTeamPick") == nil, "tb panels: no popup")
-- 0 pets: the hint
syncProfile(noPets); click(dungeonSolo()); T.check(hintText():find("You need a pet") and not PetsController.IsOpen(), "tb panels: 0 pets = the hint, no window")
-- client_tb_faces_phone (844x390 touch)
AC.OpenRing(1); T.check(inside(row, ringWin()) and row.AbsolutePosition.X >= ringWin().AbsolutePosition.X + ringWin().AbsoluteSize.X / 2 - 0.5 and row.EditTeam.AbsoluteSize.Y >= 44, "tb panels: phone: the row in the right column, Edit >= 44 px")
DC.Open(1); T.check(inside(dungeonRow(), dungeonWin()) and dungeonRow().EditTeam.AbsoluteSize.Y >= 44, "tb panels: phone: the Dungeon row inside the window")
```

Register: `server_files.append("smoke_tb_panels.lua"); client_files.append("smoke_tb_panels.lua"); pure_scenarios += ["tb_panels_text"]; ins(server_scenarios, "p5ui_content", ["tb_panels_text"]); ins(client_scenarios, "client_final", ["client_tb_faces_ring", "client_tb_faces_return", "client_tb_faces_empty"]); mobile_scenarios.append("client_tb_faces_phone")`; remove the `smoke_hud_team.lua` line.

- [ ] **Step 2: Run it to verify it fails**

Run: `py -3.12 tools/smoke.py --quick --only tb_panels_text,client_tb_faces_ring,client_tb_faces_return,client_tb_faces_empty,client_tb_faces_phone`
Expected: FAIL at "client/TeamPick is gone" and at the first `TeamFaces` lookup.

- [ ] **Step 3: Implement `src/client/UI/TeamFaces.lua`** per the Interfaces block (port the face card drawing from `ArenaController`'s `Ring.fighterCard` 1031-1078 and the strip's slot drawing from `TeamPick.Strip`, then delete `TeamPick.lua`).

- [ ] **Step 4: Wire the four panels and the return router**: `ArenaController` (Ring window layout per the pitch: the row above the footer; landscape phone right column; Duels / Raid pages), `DungeonController` (party box, `teamPowerNow`), `PetsController.Close` routing, the `Ensure` flow on every entry button; the tutorial / NPC texts; `README.md`.

- [ ] **Step 5: Rewrite dependent tests**: delete `tools/smoke_hud_team.lua`; `smoke_p4_ui.lua` / `smoke_p3_ui.lua` checks of "Your fighters (...)" titles and of `EditTeam` in the footer; `p5ui_content` needles ("Team tab" -> "Auto-fill best" / "tap a slot"); `tools/contract.json` (`client/TeamPick` out, `client/UI/TeamFaces` in with `New`, `Entries`, `Power`, `Ensure`).

- [ ] **Step 6: Run the gate**

Run: `py -3.12 tools/smoke.py --quick --only tb_panels_text,client_tb_faces_ring,client_tb_faces_return,client_tb_faces_empty,client_tb_faces_phone,p5ui_content,client_p4ui_ring,client_p5gui_cover,client_p5dgn_window,client_ringnh_card,client_tb_pets_pc,p2_final` (confirm names with `--list`), `py -3.12 tools/render_gui.py ring --grid -o <scratchpad>/ring.png` and `arena:raid --grid`, `dungeon --grid` (look at them), `node tools/check.mjs`
Expected: all pass; the renders show the faces row inside each window at every size; 0 errors.

- [ ] **Step 7: Commit and push** (`feat(panels): three faces + Edit team on Ring, Dungeon, raids and duels; TeamPick removed; tutorial and NPC text moved` + attribution).

---

### Task 6: Loss screen, Fight again and the tutorial's first room

**Files:**
- Modify: `src/server/Services/BattleService.lua` (`StartRing` run record 3514-3541: `StartLevels`; `RingRun.pay` 3082-3099 and `RingRun.finalRewards` 2962-2972: `Rewards.Pets`; header 116-118)
- Modify: `src/server/Services/DungeonService.lua` (`newMember` 752: `StartLevels`; `endPayload` 640-654: `Pets`, `Solo`; `Dg.onRoomEnd` 1549-1560: `RoomCleared`; `Dg.begin` 771-895: `run.Eased`; `Dg.spawnWave` near 1180-1210: the `opts`; header 17-18 signals)
- Modify: `src/server/Services/TutorialService.lua` (new event `DungeonRoom`, `IsOnStep`, the `DungeonService.RoomCleared` connection next to 2196-2205; header 47-60)
- Modify: `src/shared/TutorialSteps.lua:301-311` (the "dungeon" step)
- Modify: `src/server/Main.server.lua` only if `TutorialService` must be handed to `DungeonService` (`deps.TutorialService`)
- Create: `src/client/Controllers/LossScreen.lua`
- Modify: `src/client/Controllers/BattleController.lua` (`Hud.ShowResult` 6116-6220 and `Ring.FinalAfterWin` 7223-7230, `Net.End` 8588-8610: the Ring loss goes to `LossScreen`), `src/client/Controllers/DungeonController.lua` (`R.fillEnd` 1920-1975 / the `End` handler 3359-3374: Wipe / Timeout go to `LossScreen`), `src/client/Controllers/PetsController.lua` (`ReturnTo { Window = "Loss" }`), `src/client/Main.client.lua` (boot `LossScreen` before `BattleController`)
- Modify: `tools/contract.json`, `README.md` (the tutorial table: step 17 "clear the first room"; the loss screen), `tools/dump_gui.lua` (scenario `loss[:ring|:dungeon|:phone]`), `tools/smoke_p5_gui.lua` (COVER entry `loss`)
- Modify: `tools/smoke_p5_tutorial.lua` (`p5dgn_tutorial`: room 1, not floor 1; `p5ui_content` needles), `tools/smoke_p4_ui.lua` / `smoke_p3_ui.lua` (tutorial step 17 text), `tools/smoke_p5_dungeon.lua` (`p5dgn_run`: `End` payload shape), `tools/smoke_ring_noheal_client.lua` (the Fainted card now a loss screen line)
- Create: `tools/smoke_tb_loss.lua`; Modify: `tools/smoke.py`

**Interfaces:**
- Consumes: `DataService.GetPetLevel(player, key) -> level, xp`, `TycoonCatalog.XpToNext(level)`, `PetCareService.GrantXp`, `BattleService.BattleEnded`, `DungeonService.FloorCleared`, `TutorialService.GetState(player)` / the step tracker, `BattleCatalog.DungeonWave(..., opts)` (Task 2), `TeamFaces` (the faces), `PetsController.Open`, `SoundFx.Play("Reward")`, `NeonKit.Card`, `Remotes` (`BattleRequest("Ring", start)`, `DungeonRequest("Solo", floor)`), `Config.Attr.InBattle`, `ArenaController.OpenRing`.
- Produces (server):
  - Ring: `run.StartLevels = { [key] = level }` captured in `StartRing`; the final `End` of a LOST run (Reason "Loss" / "Timeout" / "Fainted", never Forfeit / Left / Shutdown / Error) carries `Rewards.Pets = { { Key, PetId, Before = StartLevels[key], After = level now, XpFrac = xp / XpToNext(level) (0..1, 1 at the cap), XpBefore = the fraction at the run's start }... }` in team order, computed on the server AFTER the loss XP was granted (the client never computes levels), plus `Rewards.Start = run.Start`.
  - Dungeon: `member.StartLevels` captured in `newMember`; `endPayload` adds `Pets` (the same shape, from `StartLevels` to now) and `Solo = true` when the run's party had one member, for Reason "Wipe" | "Timeout" only; `DungeonService.RoomCleared` (Util.Signal) `Fire(player, floor, room)` for every live member when a room's result is "Cleared" (before `FloorCleared` on room 4).
  - Tutorial: `TutorialSteps` "dungeon" step: `CompleteOn = "DungeonRoom"`, `Text = "Press E at the Dungeon portal and start Floor 1, the " .. FLOOR_ONE .. ": beat the first room to win!"`, `Hint = "Clear the first room of Dungeon floor 1"` (97-125 bytes filled); `TutorialService` event `DungeonRoom` = `RoomCleared(player, 1, >= 1)` or the saved `Dungeon.Best >= 1` / `Cleared[1]` / a legacy Trial 1 clear (old saves past the step are unaffected: the `DungeonWon` satisfied set stays a superset); `TutorialService.IsOnStep(player, stepId) -> bool` (false when the tutorial is finished / skipped / unknown).
  - Eased room: `Dg.begin` sets `run.Eased = (#run.Order == 1) and IsOnStep(leader, "dungeon")`; `Dg.spawnWave` passes `{ Eased = run.Eased and run.Floor == 1 and room == 1 }` to `BattleCatalog.DungeonWave`; the room pays `DungeonRewards` normally; `Best`, `Cleared` and the first clear are written only by `Dg.clearFloor` (room 4) as today; a party (2+ members) never gets the flag, nor a run on another floor or step.
- Produces (client):
  - `LossScreen.Show(payload)` with `payload = { Mode = "Ring" | "Dungeon", Title (e.g. "RUN OVER" / "KNOCKED OUT"), Sub, Pets = Rewards.Pets, Lines = { { text, color }... } (the run's Cash / XP / Tokens lines), Start = round | floor, OnFightAgain = fn | nil, OnEditTeam = fn, OnClose = fn }`, `LossScreen.Reopen()` (the last payload again, after Edit team), `LossScreen.Hide()`, `LossScreen.IsOpen()`. ScreenGui `NimbusLoss` (`DisplayOrder` 24, above the battle HUD's result card, below Notify 30), card `LossCard` (`NeonKit.Card`, centred; phone: within 16 px gutters, buttons >= 44 px): `Title`, `Sub`, `PetRow1..3` (each: `Face` viewport, `Name`, `Levels` text "L1 -> L3" for a pet that gained levels with a scale-pop tween and `SoundFx.Play("Reward")` 0.3 s after the card shows (the loud level-up moment; one sound for the whole card), or "L1" + `XpBar` tweened from `XpBefore` to `XpFrac` for a pet that gained none), the `Lines`, TextButtons `FightAgain` ("Fight again", hidden when `OnFightAgain` is nil), `EditTeam` ("Edit team"), `CloseButton`.
  - BattleController: a Ring `End` with `Rewards.Final` and `Won == false` and Reason in { Loss, Timeout, Fainted } shows `LossScreen` instead of `Hud.ShowResult` (wins and Left / Forfeit / Void keep today's card); `OnFightAgain`: waits until `LocalPlayer:GetAttribute(Config.Attr.InBattle) == nil` (polls every 0.2 s, up to `RETURN_DELAY + 3` s; the button shows "Returning..." meanwhile and ignores further taps), then fires `BattleRequest("Ring", Rewards.Start)` ONCE; if the server refuses (a "bad" Notify), the screen stays with the hint; `OnEditTeam` -> `PetsController.Open({ ReturnTo = { Window = "Loss" } })` and `LossScreen.Reopen()` on return.
  - DungeonController: an `End` with Reason "Wipe" | "Timeout" shows `LossScreen` (Mode "Dungeon", `Start = Floor`, `OnFightAgain` only when `payload.Solo == true`: waits for the run attribute to clear the same way, then `DungeonRequest("Solo", Floor)` once; a party member gets no Fight again, only Edit team and Close); Cleared / Left / Quit / Shutdown keep today's end card.

- [ ] **Step 1: Write the failing smoke file `tools/smoke_tb_loss.lua`** (server world booted + client + phone):

```lua
-- tb_loss_levels_ring (server): K1..K3 at L1 with 0 XP, a run that loses round 2 after a real loss (>= 20 s)
local e = lastSent(a, "End")
T.check(e.Rewards.Final == true and type(e.Rewards.Pets) == "table" and #e.Rewards.Pets == 3 and e.Rewards.Start == 1, "tb loss: the final End carries Pets and Start")
T.check(e.Rewards.Pets[1].Key == K1 and e.Rewards.Pets[1].Before == 1 and e.Rewards.Pets[1].After == select(1, DS.GetPetLevel(a, K1)) and e.Rewards.Pets[1].After >= 2, "tb loss: Before = the run's start level, After = the level after the loss XP (server-computed)")
T.check(e.Rewards.Pets[3].XpFrac >= 0 and e.Rewards.Pets[3].XpFrac < 1 and e.Rewards.Pets[3].XpBefore == 0, "tb loss: the XP fraction rides for a pet without a level-up")
-- a forfeit: no Pets table
T.check(forfeitEnd.Rewards.Pets == nil, "tb loss: a forfeit carries no Pets (it is not a loss screen)")
-- tb_loss_levels_dungeon (server): a solo wipe in room 2 of floor 1
T.check(endD.Reason == "Wipe" and endD.Solo == true and #endD.Pets == 3 and endD.Pets[1].Before == 1 and endD.Pets[1].After == select(1, DS.GetPetLevel(a, K1)), "tb loss: the dungeon End carries Pets and Solo")
T.check(partyEnd.Solo == nil, "tb loss: a party member's End has no Solo flag")
-- tb_loss_tutorial_room (server): a player on the "dungeon" step
T.check(TS.IsOnStep(p, "dungeon") == true and TS.IsOnStep(p, "ring") == false, "tb loss: IsOnStep")
local fired = {}; DGS.RoomCleared:Connect(function(pl, f, r) fired[#fired + 1] = { pl, f, r } end)
-- clear room 1 (held attacks + a scripted win like p5dgn_run)
T.check(#fired == 1 and fired[1][3] == 1 and stepId(p) == "raid", "tb loss: RoomCleared(p, 1, 1) completes 'Into the Dungeon!' on the first room")
T.check(DS.GetDungeon(p).Best == 0 and DS.GetDungeon(p).Cleared[1] == nil, "tb loss: Best and the first clear are untouched until the floor is really cleared")
T.check(stepId(veteranPastStep) == veteranStepBefore, "tb loss: an old save past the step is unaffected")
-- tb_loss_eased (server): the wave spawned in room 1 of a SOLO run by a player on the step is the eased one
T.check(run.Eased == true and spawned.Power == BC.DungeonWave(1, 1, 1, 1, run.Seed, { Eased = true }).Power, "tb loss: the solo tutorial run eases room 1")
T.check(spawnedRoom2.Power == BC.DungeonWave(1, 2, 1, 1, run.Seed).Power, "tb loss: room 2 is normal")
T.check(partyRun.Eased ~= true and partyWave.Power == BC.DungeonWave(1, 1, 1, 2, partyRun.Seed).Power, "tb loss: a party never gets the eased room (no farming)")
T.check(roomReward.Xp == BC.DungeonRewards(1, 1, 1, 0, false).Xp, "tb loss: the eased room pays the normal room reward")
-- client_tb_loss_screen (client): feed a Ring End with Pets {{Before 1, After 3}, {Before 1, After 1, XpBefore 0.2, XpFrac 0.6}, ...}
T.check(LS.IsOpen() and lossCard().PetRow1.Levels.Text == "L1 -> L3" and lossCard().PetRow2.XpBar.Visible, "tb loss: L1 -> L3 and the XP bar for a pet without a level-up")
advance(0.5); T.check(sounds()[#sounds()] == "Reward", "tb loss: the level-up moment plays once")
T.check(lossCard().FightAgain.Visible and lossCard().EditTeam.Visible and not hud():FindFirstChild("ResultCard", true).Visible, "tb loss: Fight again + Edit team; the plain card is not shown")
-- a win keeps the old card
T.check(not LS.IsOpen() and hud().ResultCard.Visible, "tb loss: a won run keeps today's result card")
click(lossCard().EditTeam); T.check(PetsController.IsOpen() and not LS.IsOpen(), "tb loss: Edit team opens the Pets window"); PetsController.Close(); advance(0.3); T.check(LS.IsOpen() and lossCard().PetRow1.Levels.Text == "L1 -> L3", "tb loss: ...and returns here")
-- client_tb_loss_fight_again
LocalPlayer:SetAttribute(Config.Attr.InBattle, "R7"); click(lossCard().FightAgain); click(lossCard().FightAgain); advance(1)
T.check(#callsAfter("BattleRequest", n0) == 0 and lossCard().FightAgain.Text == "Returning...", "tb loss: Fight again waits while InBattle is set (Review Focus 5)")
LocalPlayer:SetAttribute(Config.Attr.InBattle, nil); advance(0.5)
local calls = callsAfter("BattleRequest", n0); T.check(#calls == 1 and calls[1].args[1] == "Ring" and calls[1].args[2] == 20, "tb loss: ...then fires Ring(Start) exactly once (a boss start kept)")
-- dungeon: a solo wipe End -> Fight again -> DungeonRequest("Solo", 3) once the run attribute clears; a party wipe shows no Fight again
-- client_tb_loss_phone (844x390 touch): the card within 16 px gutters, FightAgain / EditTeam / CloseButton >= 44 px, nothing under the top bar
```

Register: `server_files.append("smoke_tb_loss.lua"); client_files.append("smoke_tb_loss.lua"); ins(server_scenarios, "shutdown", ["tb_loss_levels_ring", "tb_loss_levels_dungeon", "tb_loss_tutorial_room", "tb_loss_eased"]); ins(client_scenarios, "client_final", ["client_tb_loss_screen", "client_tb_loss_fight_again"]); mobile_scenarios.append("client_tb_loss_phone")`.

- [ ] **Step 2: Run it to verify it fails**

Run: `py -3.12 tools/smoke.py --quick --only tb_loss_levels_ring,tb_loss_levels_dungeon,tb_loss_tutorial_room,tb_loss_eased,client_tb_loss_screen,client_tb_loss_fight_again,client_tb_loss_phone`
Expected: FAIL at "the final End carries Pets and Start" and at the first `NimbusLoss` lookup.

- [ ] **Step 3: Implement the server half** (`StartLevels`, `Rewards.Pets` / `Start` in `RingRun.pay` + `finalRewards`, `endPayload.Pets` / `Solo`, `DungeonService.RoomCleared`, `run.Eased` + the `spawnWave` opts, `TutorialService.IsOnStep` + the `DungeonRoom` event + the `RoomCleared` connection, the `TutorialSteps` step; `Main.server.lua` hands `TutorialService` to `DungeonService.Init` deps if it is not already reachable there).

- [ ] **Step 4: Implement `src/client/Controllers/LossScreen.lua`** and wire `BattleController` / `DungeonController` / `PetsController` (`ReturnTo Loss`) / `Main.client.lua` per the Interfaces block; `dump_gui.lua` scenario `loss`; the COVER entry.

- [ ] **Step 5: Rewrite dependent tests and docs**: `p5dgn_tutorial` (completes on room 1; the floor no longer needed), `p5ui_content` and the `smoke_p3_ui` / `smoke_p4_ui` step-17 text needles, `p5dgn_run` (the End payload gains fields; nothing removed), `client_ringnh_card` (the Fainted loss now shows the loss screen with "your whole team fainted after round N" as `Sub`), `README.md` (tutorial table + the loss screen paragraph), `tools/contract.json` (`client/Controllers/LossScreen`: `Show`, `Reopen`, `Hide`, `IsOpen`; `server/Services/DungeonService` signal `RoomCleared`; `server/Services/TutorialService` function `IsOnStep`).

- [ ] **Step 6: Run the gate**

Run: `py -3.12 tools/smoke.py --quick --only tb_loss_levels_ring,tb_loss_levels_dungeon,tb_loss_tutorial_room,tb_loss_eased,client_tb_loss_screen,client_tb_loss_fight_again,client_tb_loss_phone,p5dgn_tutorial,p5ui_content,p5dgn_run,client_ringnh_card,client_p5gui_cover,p2_final,ringnh_service`, then the FULL `py -3.12 tools/smoke.py --quick` (the branch gate: only `p3fixsrv_net16` may fail, no worse than 6004 B/s), `py -3.12 tools/smoke.py --quick --mesh`, `py -3.12 tools/sim_tycoon.py --check`, `$env:SIM_BATTLE='quick'; py -3.12 -c "..."` (every target met), `node tools/check.mjs`
Expected: all green except the known net16 line; the retry loop (info line of the sim's `progress` section) under 120 s for S1.

- [ ] **Step 7: Commit and push** (`feat(loss): the loss screen with server levels, Fight again, Edit team; the tutorial's first room, eased for a solo new player` + attribution). Append to `Projects Main/Nimbus/.superpowers/team-balance-pitch/LEDGER.md`: the six commits, the final measured balance table, the full-run result, and what a veteran now sees in the Ring (from the sim's info line).

---

## Self-review notes (done while writing)

- Spec coverage: s.1 -> Task 3 (+ the A / B / C control in Task 4); s.2 -> Task 5; s.3 -> Task 4; s.4 and s.6 -> Task 2 (targets as sim bands, the measured table reported); s.5 -> Task 1; s.7 -> Task 6. Non-goals: no new remotes, ids, items or windows beyond the three new client modules; fusion untouched; `main` untouched. "Left to the builder" items are decided above: Fight again re-enters through `BattleRequest("Ring", Start)` / `DungeonRequest("Solo", Floor)` after the return teleport; the snap sound is `SpinLand`; records and boss starts are kept (Task 2 reports the veteran's view); the test rewrites are listed per task.
- Names used across tasks: `BattleStatsOf` / `BattleLevelFactor` (1 -> 2, 4), `DungeonWave(..., opts)` + `EasedRoomMult` (2 -> 6), `DataService.ActiveTeamKeys -> keys, why` / `BusyKeys` / `SyncEquipped` / `BattleService.TEAM_REFUSALS` (3 -> 5, 6), `State.ActiveTeam` / `State.Busy` (3 -> 4, 5), `PetsController.Open({ Key, Pick, Preset, ReturnTo })` / `Closed(returnTo)` (4 -> 5, 6), `TeamFaces.New / Entries / Power / Ensure` and the `ReturnTo` shapes (5 -> 6), `LossScreen.Show / Reopen` (6).
- Proportion: the plan decides files, names, signatures, texts, numbers and tests; bodies are left to the builders except the migration order and the refusal / tutorial texts the spec fixes.
