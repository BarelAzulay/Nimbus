# Lobby Shop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Also name and use superpowers:test-driven-development (every task is test first) and superpowers:verification-before-completion.

**Goal:** Turn every roulette spin into an egg roll (x1 / x3, Skip, Fast hatch, a Secret pity), redraw the Cloud Shop as one big card per machine with a Gems tab, re-price gems, draw every gem as a cut gem, move the Sky Trove onto the plaza, add a global leaderboard, and make the three altar portals stand up and light up.

**Architecture:** Server and data first. PetCatalog becomes the one odds source (the Secret Roulette included); PetService's money step becomes a batch that never refuses after the roll (x3 = one charge, engine-seeded `RollRng` / `StripRng`); the pity is a new top-level profile field wired through every DataService touch point; gem-priced actions wait for a 15 s settle read; `StoreRequest("GemBuy")` sells the XP Potion; new prices; a LeaderboardService on OrderedDataStores. Then the world: LobbyBuilder places the trove on the plaza and calls a new LobbyBoardBuilder for the Egg Guide and the leaderboard board; StormAltar gets the summon glow, the standing return ring and the world gem; the Altar gate gets its pad and a boosted vortex. Then the client: `UI/GemIcon` everywhere, `UI/EggArt` + `UI/EggStage` (the one request path), `ShopController` moved out of MenuController, the Store's Eggs tab, the board's PlayerGui SurfaceGui and one LobbyFx heartbeat. Last the two Blender props still missing, then docs, evidence and the gate.

**Tech Stack:** Luau in plain Lua 5.1 syntax, Rojo layout, the mock harness `py -3.12 tools/smoke.py` (lupa), `tools/dump_gui.lua` + `tools/render_gui.py`, `node tools/check.mjs`, `py -3.12 tools/count_locals.py`, `py -3.12 tools/sim_tycoon.py`, the Blender kit (`blender/build_all.py` under `%USERPROFILE%\.bpyenv\Scripts\python.exe`), `tools/render_model.py`.

**Spec:** `docs/superpowers/specs/2026-11-07-lobby-shop-design.md`. **Section 15 overrides everything above it** (Ring best instead of Climb wins, no Climb finish change, token packs 2,500 / 8,000 / 25,000, no session lock). Mock-ups: `Projects Main/Nimbus/.superpowers/lobby-shop/pitch/page.html` (functions `machCard`, `shopB`, `packTile`, `shopA(m, "Gems")`, `eggsA`, `eggSymbol("C", r)`, `machSymbol`, `boardA`, `gateScene`, `chestMap`; design px at 844x390 and 1920x1080); cards `.superpowers/lobby-shop/pitch/CARDS.md`; ledger `.superpowers/lobby-shop/LEDGER.md`. Read the spec section each task names before starting it.

## How every task runs

- Worktree `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\lobby-shop\nimbus-climb`, branch `lobby-shop` (cut from bug-batch-6 09ac836). Paths have Hebrew characters: PowerShell `Set-Location -LiteralPath` / `-LiteralPath`, or `git -C`. Read `ABSOLUTE_RULES.md`, `brain.md` and the newest `BUILD_STATE.md` entry first.
- **Pre-flight (before Task 1):** the whole gui-redo branch must be merged in, its code-review round included: `git -C <worktree> merge-base --is-ancestor 486d9fc HEAD` exits 0 (gui-redo's final gate, which contains the review-fix commit 7b4e07d; the local tip 4a35b75 is that plus the bug-batch-6 merge lobby-shop already has), `git -C <worktree> merge-base --is-ancestor gui-redo HEAD` exits 0 (if gui-redo moved on after this plan, merge it again first), and `src/client/Controllers/TrainController.lua` exists. If not, stop: the build waits (spec 3.1). Every file gui-redo touched is edited (or read) in its merged form: DataService, PetService, FusionService, DailyService, Config, PetKeys, State, Main.client, FusionController, DailyController, CareController, TrainController, PetController, **HudController** (7b4e07d adds `HudController.SetVitalsHidden` and `S.vitalsOwners`; spec 3.1 wrongly lists HudController as untouched by gui-redo, this line corrects it), `UI/PetPicker`, dump_gui.lua, render_gui.py, smoke.py, contract.json, sim_tycoon.py, smoke_p5_gui / p5_looks / daily_ui / p2_visual and the `smoke_redo_*` files. This plan cites functions and anchors, not line numbers.
- No Roblox Studio, no Rojo start / stop, no uploads, no merges into main, no MeshIds / TextureIds. Blender only in Tasks 22-23 (the repo kit). Do not touch other worktrees.
- Tests while building: `py -3.12 tools/smoke.py --quick --only <names>` with the names the task lists. Never the whole suite before Task 24.
- Before each commit: `node tools/check.mjs` -> 0 errors, and `py -3.12 tools/count_locals.py <every Lua file the task grew>` -> under the task's cap.
- Commit message ends with exactly these two lines, then `git -C <worktree> push origin lobby-shop`:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01ACtM8qc8ts2NyGHrZh7vyT`
- After each push append one dated line to the Milestones of `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.superpowers\lobby-shop\LEDGER.md` (commit hash, what landed, the tests that passed). Evidence goes to `.superpowers\lobby-shop\evidence\` (outside the repo).
- A test a task's change breaks is rewritten to the new rule in the same task, never deleted; the commit body names each rewritten scenario and why.
- Every new smoke file is registered with one `p5(...)` line in `tools/smoke.py`, placed after the gui-redo lines (so `RedoGeom` from `smoke_redo_geom.lua` exists): server scenarios before `"shutdown"`, pure ones in `pure_scenarios` + before `"p5stats_formula"`, client ones before `"client_final"`, phone ones in `mobile_scenarios`. Later tasks extend the line their file was registered on.
- Route (`py -3.12 tools/pick_model.py --build game-feature --money --saves --many-systems`): Fable is out of credits, so every stage runs on **Opus 5.5**: build xhigh; review **max** for Tasks 2-9 (saves / money / security) and Task 17 (the shop move); xhigh elsewhere; ultracode at the gate (adversarial verification, completeness critic, loop until dry).
- Skills named in every builder prompt: superpowers:test-driven-development and superpowers:verification-before-completion; plus the task's own line.

## Global Constraints

- Section 15: board page 3 = Ring best (`Ring.Best`, title "TOP RING ROUND"); no Climb finish change, no `Match.MinFinishSeconds`, no `match_finish_clean`, no Wins store; token packs 2,500 / 8,000 / 25,000 Cloud Tokens at 49 / 149 / 399 R$; no save session lock (the 15 s gem settle hold stays); gem prices B unchanged by prestige.
- No change to the token prices (50 / 250 / 1,000 / 5,000), the machines' rarity odds, the Secret Roulette's odds (Mythic 85, Secret 15), the pet pools, or free gem income (Daily, dungeons, arena, index, raids, prestige).
- No uploads: no MeshIds, TextureIds, image ids or new sounds. Every new mesh has a Part fallback; every GUI picture is frames + gradients; sounds are existing `AudioIds` keys through `SoundFx.Play`.
- Plain Lua 5.1 syntax; sources stay ASCII; non-ASCII UI text as UTF-8 byte escapes (`"\194\183"` middle dot, `"\240\159\165\154"` egg, `"\226\151\134"` is the old gem glyph that must vanish from the client UI).
- Readability (`Theme.Readability`): PC design text >= 18 px, phone text >= 15 px at scale 1, any on-screen text >= 14 px, tap targets >= 44 px, nothing under Roblox's top bar; screens 640x360 to 2560x1440 landscape and 360x640 / 390x844 portrait.
- World text >= 0.6 stud (30 px at 50 px per stud), the board's PlayerGui SurfaceGui included.
- DisplayOrders: new `NimbusShop` 19 and `NimbusHatch` 25 (both `IgnoreGuiInset = true`); existing Pets / Store / Daily 19, NimbusMenu 20, Index 21, Fusion 22, Care / Arena / Train 23, PetPicker / LossScreen 24, Notify 30, Trove 18.
- Money: one non-yielding step (no `task.wait`, DataStore or remote call) from the checks to the last write; nothing refuses after the roll (one kept exception, before the charge: today's `AllowSecret` guard, a Secret pet rolled by a roulette without `AllowSecret` refuses the whole request "The roulette jammed, try again" with nothing charged); nothing that can fail runs after the charge; refresh / Sync / events / announce after it, each in pcall. No client-supplied number reaches a price, roll, count or leaderboard value.
- Saves: a new field is a new top-level field listed in `KNOWN_TOP`; a provisional (stand-in) profile never decides a one-time or money thing; `Pity` is left out while 0 / 0; `Settings.FastHatch` is stored only when true; no migration; old records load and save byte-identical until the player uses the new thing.
- Lobby light rule (`smoke_p5_world`): lamps in `Config.Sky.Lamps.Names` <= 1.2 brightness / 16 range, every other lobby light <= 1.5 / 28, no SpotLight / SurfaceLight. Storm Altar <= 500 parts (`tools/contract.json` `stormAltar`), trove <= 60 parts. The parts covered by the `prop_altar_portal` and `gate_altar` LayoutSig manifests are not changed.
- No near-miss tricks: Skip from the first frame, the strip is the server's strip, a card without odds cannot spin, odds on every card before paying.
- The gui-redo windows (Daily, Play time, Training Place, Fusion, the pet picker) are not redesigned. The server never animates.
- Top-level locals: DataService stays 160, MenuController drops under 160 (Task 17), LobbyBuilder <= 159, HudController stays 161 (no new column-0 local). Per-file caps in each task.
- `check.mjs` asset-id rule: no `rbxassetid://` or `rbxthumb://` literal in `src` (headshots come from `Players:GetUserThumbnailAsync`).

## Review Focus

1. The screen turning or resizing while the egg stage plays (mid-strip or on the reveal) or while the shop is open (a phone rotating): everything must re-lay out inside the screen and the roll must still reach its reveal -> `client_egg_stage_mobile` step "resize mid-roll" (Task 16) and `client_shop_mobile` step "resize while open" (Task 17).
2. The shop closed (X, Esc, gamepad B, a match) while a spin request is pending, then reopened: the cards must not stay dimmed forever, the late answer still plays (or re-enables with its reason), the 7 s timeout still frees them -> `client_egg_stage_wiring` step "close while pending", run once per way of closing (Task 17).
3. The lobby rebuilt while players are in it (a dev reset or a rebuild): the board's SurfaceGui re-adorns to the new Face, the Join sign stays hidden for a player who claimed, new spin / bob targets move and old ones drop out -> `client_leaderboard` step "lobby rebuilt" (Task 20) and `client_lobby_fx` step "lobby rebuilt" (Task 21).
4. Long names and huge numbers (a 20-character display name, a 1e12 value, an 8-digit gem balance): never overflow a row or chip, never shrink text under its floor -> `client_leaderboard` step "long names" (Task 20) and `client_shop_mobile` step "big balances" (Task 17).
5. Gem icons destroyed and rebuilt in bulk (HUD relayouts on every resize, windows rebuilding cards): the shared shine driver must drop dead icons, never error and never grow -> `client_gem_icon` step "churn" (Task 15).

## File map

| File | Tasks | Change |
|---|---|---|
| `src/shared/Config.lua` | 1-5, 7-10, 19 | `Eggs`; `Gems` prices / products (+ `Robux`) / `SecretRoulette.PityAt` / `SettleSeconds`; `Store.Tabs` Eggs; token packs; `Store.GemItems`; `Leaderboard`; `Attr.SecretPityLeft`, `GemsSettled`, `TroveGroupDone`, `XpPassState`; `Tags.Spin`, `Tags.Bob`; remote `LeaderboardState`; Remotes comments |
| `src/shared/PetCatalog.lua` | 1 | `RollRarity`, `RollFromRarity`, `RarityPool`; `findRoulette` knows the Secret Roulette |
| `src/shared/Util.lua` | 1 | `NewRng()` without a seed |
| `src/server/Services/GemService.lua` | 1 | `RollPet` `opts.ForceRarity`; gems-only odds delegate to PetCatalog |
| `src/server/Services/DataService.lua` | 2, 3 | `Pity` (every touch point), `GetPity` / `SetPity`, `FastHatch`, `GemsSettled` + the settle read, `Settled` signal |
| `src/server/Services/FusionService.lua` | 3 | gem Mix waits for `GemsSettled` |
| `src/server/Services/PetService.lua` | 4-6 | the batch, x3, `RNG`, plan / write split, reply, pity, announcements |
| `src/server/Services/StoreService.lua`, `src/shared/StoreCatalog.lua` | 7, 8 | `GemBuy`, `XpPassState`; `gemItem` `Robux`, `GemItems` |
| `src/shared/TycoonCatalog.lua`, `tools/sim_tycoon.py`, `README.md` | 8 | Mix gems 50 / 125; `--gems`; price tables |
| `src/server/Services/LeaderboardService.lua`, `src/server/Main.server.lua` | 9 | new; boot |
| `src/server/Services/LobbyBuilder.lua`, `LobbyBoardBuilder.lua` (new), `TroveService.lua` | 10-12 | trove spot, Join sign, Egg Guide, board, Altar gate |
| `src/shared/WorldStyle.lua`, `src/client/PortalVortex.lua` | 12 | `VortexBoost` |
| `src/server/Services/StormAltar.lua` | 13, 14 | `PortalGlow`, the standing return ring, the world gem |
| `src/client/UI/GemIcon.lua` (new), `NeonKit`, `HudController`, `StoreController`, `ArenaController`, `DungeonController`, `FusionController` | 15, 19 | gem art everywhere; Eggs tab |
| `src/client/UI/EggArt.lua`, `src/client/UI/EggStage.lua` (new) | 16 | eggs, the stage, the one request path |
| `src/client/Controllers/ShopController.lua` (new), `MenuController`, `MouseLock`, `Main.client` | 17-19 | the Cloud Shop |
| `src/client/Controllers/NotifyController.lua` | 6 | kind `"pull"` -> system chat |
| `src/client/ClientSettings.lua`, `src/client/State.lua` | 2 | `FastHatch` |
| `src/client/Controllers/LeaderboardController.lua`, `LobbyFxController.lua` (new) | 20, 21 | board client, lobby motion |
| `blender/kit/props/lobby_shop.py`, `blender/catalog/lobby.json`, `src/shared/MeshManifests/*`, `blender/meshes.json`, `tools/mesh_keys.py` (new) | 22, 23 | `portal_altar_ring`, `prop_board_lb`, the key check |
| `tools/robloxmock.lua` | 6, 9, 20 | `TextChannels.RBXSystem`, OrderedDataStore, budgets, `UserService`, client thumbnails |
| `tools/smoke_*.lua` (new: eggs, pity, gem_prices, leaderboard, lobby_shop_world, gem_icon, egg_stage, shop_ui, lb_ui, lobby_fx), `tools/smoke.py`, `tools/contract.json`, `tools/dump_gui.lua`, `tools/render_gui.py` | all | tests, registration, scenes |

## Lanes (speed scout)

Lane S (server money) runs Tasks 1-9 in order (they share PetService / DataService / Config). Lane W (world, Tasks 10-14) and lane C (client art, Tasks 15-16, after Task 2) share no source file with lane S except `Config.lua` and the registration lines in `smoke.py` / `contract.json`. `Config.lua` is NOT disjoint: lane S Tasks 3, 5 and 7 append `GemsSettled`, `SecretPityLeft` and `XpPassState` to `Config.Attr`, and lane W Task 10 appends `TroveGroupDone` to the same table (plus `Config.Tags.Spin` / `Tags.Bob`). So, before splitting into lanes, land one small commit on `lobby-shop` that adds all four `Config.Attr` keys and both `Config.Tags` keys (strings only, nothing reads them yet; `config_shape`, `contract` and check.mjs green); the later tasks' "Attr" / "Tags" lines are then already done and the tasks only read them. When the tasks run in one worktree in order, skip that commit. If run side by side, each lane works in its own worktree `Projects Main\Nimbus\.worktrees\lobby-shop-<lane>` branched from `lobby-shop` and merges back at each join. Joins: Task 17 needs 3, 4, 5, 16; Task 18 needs 7, 8, 17; Task 19 needs 17; Task 20 needs 9, 11; Task 21 needs 10, 13, 14; Task 22 needs 13; Task 23 needs 11; Task 24 last.

---

### Task 1: Eggs and one odds source

Spec: 5.1 "Eggs", "The roll", "One source for the odds", the `ForceRarity` paragraph, "Randomness" (only the `Util.NewRng` no-seed form). Skills: roblox-dev:roblox-security (the roll is money).

**Files:**
- Modify: `src/shared/Config.lua` (new `Config.Eggs` after `Config.Index`)
- Modify: `src/shared/PetCatalog.lua` (`findRoulette`; new helpers after `oddsEntries`; `RollPet` rebuilt from them; header API)
- Modify: `src/server/Services/GemService.lua` (`RollPet`, `GetOdds`, `GetRarityOdds`, `PossiblePets`: the gems-only branches delegate; drop `oddsEntries` / `petsOfRarity` when nothing else uses them; header)
- Modify: `src/shared/Util.lua` (`NewRng`)
- Create: `tools/smoke_eggs.lua` (server world: pure + booted; `CONTEXT` picks the half like `smoke_storm.lua`)
- Modify: `tools/smoke.py`, `tools/contract.json` (`shared/PetCatalog`: `RollRarity`, `RollFromRarity`, `RarityPool`)

**Interfaces:**
- Produces:
  - `Config.Eggs = { Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }, Names = { Common = "Cloud Puff Egg", Uncommon = "Breeze Egg", Rare = "Raindrop Egg", Epic = "Thunder Egg", Legendary = "Sunburst Egg", Mythic = "Aurora Egg", Secret = "Starry Night Egg" } }`.
  - `PetCatalog.RollRarity(rouletteId, rng) -> rarityId | nil` (the one `rng:Float(0, total)` draw over `oddsEntries`; `math.random` without an rng). `PetCatalog.RollFromRarity(rouletteId, rarityId, rng) -> petId | nil` (the one `rng:Int(1, #pool)` draw; nil when that rarity is not one of the roulette's odds rows). `PetCatalog.RarityPool(rouletteId, rarityId) -> { PetDef... }` (that row's `Pets`, i.e. `poolByRarity`; `{}` when not a row). `RollPet(id, rng)` = `RollFromRarity(id, RollRarity(id, rng), rng)`: the same draws in the same order as today.
  - `findRoulette(id)` falls back to `Config.Gems.SecretRoulette` when no token roulette has that id, so every PetCatalog odds / roll function answers for `"Secret"` on server and client. `IsRollable` is unchanged (it loops `Config.Roulettes`).
  - `GemService.RollPet(rouletteId, rng, opts)`: every roulette rolls through PetCatalog; `opts.ForceRarity` draws `rng:Float(0, 1)` and throws it away, then `RollFromRarity(id, opts.ForceRarity, rng)` (the rng position matches an unforced roll). `GemService.GetOdds / GetRarityOdds / PossiblePets` return PetCatalog's tables for both kinds.
  - `Util.NewRng(seed)`: `seed == nil` -> `Random.new()` with no argument.

- [ ] **Step 1: Failing test `egg_roll_pure`** (pure, `smoke_eggs.lua`)
  - for every `Config.Roulettes` id and `"Secret"`, seeds 1..10,000: with `a, b, c = Util.NewRng(s)` x3, `PetCatalog.RollPet(id, a) == PetCatalog.RollFromRarity(id, PetCatalog.RollRarity(id, b), b)` and both equal an inline copy of today's algorithm run on `c` (Float over the rows, Int over the picked pool): today's results stay identical
  - per roulette, each rarity's frequency over the 10,000 rolls is within 1.5 points of `Odds[r] / total`
  - `RollFromRarity` returns only pets with that `Rarity`, never `ExclusiveTo` or `EventOnly`; `RarityPool(id, r)` ids equal `PetCatalog.ListByRarity(r)` ids for every row; `RarityPool("Cloud", "Mythic")` is `{}` and `RollFromRarity("Cloud", "Mythic", rng) == nil`
  - `ForceRarity`: `a, b = NewRng(9)` twice; `GemService.RollPet("Secret", a, { ForceRarity = "Secret" })` is a Secret pet; `GemService.RollPet("Secret", b)`; then `a:Float(0, 1) == b:Float(0, 1)`
  - `PetCatalog.GetRarityOdds("Secret")` equals `GemService.GetRarityOdds("Secret")` row for row (`Rarity`, `Chance`, `Count`): `Mythic 0.85`, `Secret 0.15`; `PossiblePets("Secret")` ids equal in both; every roulette (Secret included) has at least one odds row
  - `Config.Eggs.Order` equals the `Config.Rarities` ids sorted by `Order`; every `Names[r]` is a non-empty string; `Util.NewRng():Int(1, 6)` is in 1..6
- [ ] **Step 2: Register** `if p5("smoke_eggs.lua"): server_files.append("smoke_eggs.lua"); names = ["egg_roll_pure"]; pure_scenarios += names; ins(server_scenarios, "p5stats_formula", names)  # [lobby-shop, Tasks 1/4/6] eggs, the roll batch, the announcements (smoke_eggs.lua)`
- [ ] **Step 3: Run** `py -3.12 tools/smoke.py --quick --only egg_roll_pure` -> FAIL (`RollRarity` is nil; `GetRarityOdds("Secret")` is `{}`).
- [ ] **Step 4: Implement** the Interfaces. PetCatalog header lists the three helpers and the Secret fallback.
- [ ] **Step 5: Run** `py -3.12 tools/smoke.py --quick --only egg_roll_pure,catalog,config_shape,p2gems_odds,p2gems_roulettes,p2gems_altar,evo_rarity_odds,contract` -> PASS. `count_locals`: PetCatalog <= 40, GemService <= 78, Util 3. `node tools/check.mjs` -> 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): eggs are rarities; one odds source for every roulette, the Secret Roulette included`

### Task 2: The pity field and the Fast hatch setting (data)

Spec: 5.2 (the field, every DataService touch point, `GetPity` / `SetPity`, the clean rule), 5.5 "Fast hatch" (data only), 6. Skills: roblox-dev:roblox-datastores.

**Files:**
- Modify: `src/server/Services/DataService.lua` (header record shape and merge rules; `OVERWRITABLE`; `KNOWN_TOP`; `P5.SETTING_KEYS` / `SETTING_DEFAULTS` / `P5.settingValue`; pity helpers as fields of `P7` (`P7.cleanPity`, `P7.isDefaultPity`, `P7.diffPity`, `P7.applyPity`, `P7.livePity`); `newProfile`; `copyProfile`; `normalizeProfile`; `profilesEqual`; `overwriteValues`; `diffProfiles`; `isEmptyDelta`; `applyDelta` and its overwrite path; `toStored` (Pity and `Settings.FastHatch`); `replaceContents`; new `DataService.GetPity` / `SetPity` next to `GetRing` / `MutateRing`). `Ring` is the pattern at every touch point; `buildSnapshot` does not carry Pity.
- Modify: `src/client/ClientSettings.lua` (`KEYS`, `DEFAULTS`, `Clean`), `src/client/State.lua` (`SETTING_KEYS`, `SETTING_DEFAULTS`, `cleanSettings`), `src/shared/Config.lua` (Remotes comment of `SettingsSet`: `..., MouseLock / FastHatch bool, ...`)
- Create: `tools/smoke_pity.lua` (server + client worlds; helpers `join`, `leave`, `stored(uid)`, `secondServer` copied from `smoke_p7_data.lua`)
- Modify: `tools/smoke.py`, `tools/contract.json` (`DataService`: `GetPity`, `SetPity`)

**Interfaces:**
- Produces:
  - Profile field `Pity = { Secret = { Spins = n, Hit = n } }`: `Spins` merges as a delta (like `Ring.Runs`), `Hit` as the max (like `Ring.Best`); clean: whole numbers 0..1e9, `Hit <= Spins` (else `Hit = Spins`), anything else 0; stored only when not 0 / 0.
  - `DataService.GetPity(player) -> { Spins, Hit } | nil`: a copy; nil until loaded and while provisional (`P3.realEntry`).
  - `DataService.SetPity(player, spins, hit) -> boolean`: a plain write on the real entry (clean; `Hit` never below the live `Hit`; `entry.Dirty = true`; `SyncSoon`); false with no real entry or junk. No callback form.
  - Setting `FastHatch`: boolean, default false; `SetSetting(p, "FastHatch", v)` takes booleans only; the snapshot's `Settings` carries it; `toStored` writes `Settings.FastHatch` only when true.
  - `ClientSettings.KEYS` gains `"FastHatch"`, `DEFAULTS.FastHatch = false`, `Clean` accepts booleans; `State.Settings().FastHatch` follows the snapshot.
  - No new column-0 local: DataService 160, State 66, ClientSettings 13.

- [ ] **Step 1: Failing tests**
  - `secret_pity_save` (booted):
    - fresh join: `GetPity(p)` deep-equals `{ Spins = 0, Hit = 0 }`; a failed load (provisional): `GetPity == nil`, `SetPity(p, 1, 0) == false`
    - `SetPity(p, 6, 0)`, save: stored `Pity.Secret` deep-equals `{ Spins = 6, Hit = 0 }`; a fresh load shows `{ 6, 0 }`
    - `KNOWN_TOP`: same session `SetPity(6, 0)`, save, `SetPity(7, 7)`, save; a fresh load shows `{ 7, 7 }`
    - two servers on one store, both loaded at `{ 2, 0 }`: A `SetPity(4, 4)` saves, B `SetPity(3, 0)` saves -> stored `Spins == 5`, `Hit == 4` (B's save does not replace A's Spins with the stored copy)
    - a rebase (another server's save, then the recover path): live `GetPity` shows the merged numbers and `ProfileRebased` fired
    - `SetPity(p, 9, 1)` after `Hit == 4` -> `Hit` stays 4; stored junk `{ Spins = "x", Hit = 9 }` loads as `{ 0, 0 }`, `{ Spins = 3, Hit = 5 }` as `{ 3, 3 }`, `{ Spins = 2e9 }` as `{ 0, 0 }`
    - `ResetFields(p, { Pity = true })` -> no `Pity` in the stored record after the save
    - an old record without `Pity`, with default Settings, then with `Settings.Music = 2`: load, change Cash, save -> the stored record has no `Pity` key and its `Settings` has no `FastHatch` key; `SetSetting(p, "FastHatch", true)` -> stored `Settings.FastHatch == true`; back to false -> the key is gone
    - `SetSetting(p, "FastHatch", "yes")` and `(p, "FastHatch", 1)` -> false, nothing stored
    - the ProfileSync snapshot has `Settings.FastHatch == false` and no `Pity` key
  - `client_fasthatch_setting` (client): `ClientSettings.Get("FastHatch") == false`; `Set("FastHatch", true)` -> no `SettingsSet` before 0.4 s, exactly one `SettingsSet("FastHatch", true)` by 0.5 s; `Set("FastHatch", 1)` refused; a ProfileSync with `Settings.FastHatch = true` -> `State.Settings().FastHatch == true`
- [ ] **Step 2: Register** `if p5("smoke_pity.lua"): server_files.append("smoke_pity.lua"); client_files.append("smoke_pity.lua"); ins(server_scenarios, "shutdown", ["secret_pity_save"]); ins(client_scenarios, "client_final", ["client_fasthatch_setting"])  # [lobby-shop, Tasks 2/3/4/5/7] the Secret pity save, Fast hatch, the gem settle hold (smoke_pity.lua)`
- [ ] **Step 3: Run** `py -3.12 tools/smoke.py --quick --only secret_pity_save,client_fasthatch_setting` -> FAIL (`GetPity` is nil).
- [ ] **Step 4: Implement** the Interfaces, one touch point at a time in the order of spec 5.2's list (`KNOWN_TOP` first).
- [ ] **Step 5: Run** `secret_pity_save,client_fasthatch_setting,p5data_settings,p7data_fields,p7data_store_merge,p7data_reset,p4data_save,polish_data_outage,polish_data_dev_reset,polish_data_fwdcompat,persistence,data_orphans,client_state,dgfixmouse_data,contract` -> PASS. DataService 160, State 66, ClientSettings 13. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): the Secret pity record and the Fast hatch setting in the save`

### Task 3: The gem settle hold

Spec: 5.2 "The gem settle hold (server hops)", 6 (`GemsSettled`), 7. Skills: roblox-dev:roblox-datastores, roblox-dev:roblox-security.

**Files:**
- Modify: `src/shared/Config.lua` (`Gems.SettleSeconds = 15`; `Attr.GemsSettled = "GemsSettled"`)
- Modify: `src/server/Services/DataService.lua` (settle state on the cache entry; the settle loop started from `DataService.Load` for a loaded entry and after a recovered provisional load; `P7.SETTLE_RETRY = 5`; `DataService.Settled = Util.Signal()`; `DataService.GemsSettled`; `DataService._SettleForTest`; header)
- Modify: `src/server/Services/FusionService.lua` (`buildPlan`, right after `currencyOf(plan.Cost)`)
- Modify: `tools/smoke_pity.lua`, `tools/smoke.py` (its line)
- Modify (rewrite, keep names): every scenario that mixes with gems right after a join. Grep all smoke files, not a hand-picked list: `grep -ln "Fusion.Mix\|Fu.Mix\|\.Mix(\|\"Gems\"" tools/smoke_*.lua`, then read each hit (today: `smoke_p2_flow.lua`, `smoke_p2_fusion.lua`, `smoke_redo_fusion.lua`, `smoke_evo_rarity.lua` `evo_rarity_saves`, `smoke_bug2_garden.lua` `bug2garden_fusion` (token-priced pets: check, likely untouched)). Each gem Mix right after a join calls `DataService._SettleForTest(p)` first; `evo_rarity_saves` gets `DataService._SettleForTest(veteran)` before its Mythic gem `Fusion.Mix` (`K.freshPlayers(2)`, 0.3 s, then `DataS.AddGems(p, TC.FusionCost("Mix", "Mythic", nil, 1).Gems)`)

**Interfaces:**
- Produces:
  - `DataService.GemsSettled(player) -> boolean`: true only when the entry is loaded, not provisional, `Config.Gems.SettleSeconds` have passed since the load **and** one settle read returned (or `_SettleForTest` marked it, below).
  - The settle read (a field of `P7`, e.g. `P7.settleRead(entry, userId)`, under `acquire(entry)` and released with `entry.Saving = false`, the `scheduleRecovery` shape): a fresh `fetchProfile(userId)`. **Quiet case** (no other server wrote): the fetched record (normalized; `newProfile()` when nothing is stored) `profilesEqual` `entry.Base` -> nothing else happens (no `rebase`, no `announceRebase`, so no `pushAll` / migrations / `Sync` / `ProfileRebased` / `TeamsChanged`); the entry is simply marked settled. **Changed case**: what `recover` does (`rebase`, `announceRebase` -> `ProfileRebased`), then marked settled. Do not call `recover` as is: it always announces, which would re-run the six `ProfileRebased` listeners (TycoonService `onHomeLoaded` resets coins, DailyService re-sends, TutorialService re-merges, PetService, IndexService, DevService) for every player about 15 s after every join.
  - A failed read retries every `P7.SETTLE_RETRY` (5) s; `storeDisabled` or no store -> settled at `SettleSeconds` with no read.
  - A provisional load starts no settle read of its own: a successful **recovery read** (`scheduleRecovery` -> `recover`, first try at 20 s) that returns at least `SettleSeconds` after the load counts as the settle read, and the entry is marked settled right after `recover` returns; a recovery that returned sooner would leave the normal settle read to run once `SettleSeconds` have passed. "Marked settled" always happens after `recover` / `announceRebase` returned, so `ProfileRebased` listeners still see `GemsSettled == false`.
  - Once settled: player attribute `GemsSettled = true` (never written false; absent before) and `DataService.Settled:Fire(player)` once per load.
  - `DataService._SettleForTest(player) -> boolean` (Studio and the mock only, `RunService:IsStudio()`; false elsewhere): performs the settle read now (quiet or changed case as above) and marks the entry settled at once, skipping the `SettleSeconds` wait: sets the `GemsSettled` attribute, fires `Settled`, returns true (false for no entry, not loaded, provisional, or a failed read).
  - `FusionService.buildPlan`: `currency == "Gems"` and `DataService.GemsSettled` exists and answers false -> `false, "Your data is still loading"`.

- [ ] **Step 1: Failing test `gem_settle`** (booted; part 1: the data layer)
  - join: `GemsSettled(p) == false`, attribute absent; advance 14 s -> still false; past 15 s and the read -> true, attribute true, `Settled` fired once, `Mock.DataStore.Calls` grew by the read
  - quiet settle (no other server wrote): no `ProfileRebased`, no `TeamsChanged` and no extra `ProfileSync` between the join's last sync and the settle (count with listeners and the remote log); the live profile is unchanged
  - another server's save lands 8 s after the load (Gems 300 -> 100): after the settle the live Gems is 100 and `ProfileRebased` fired once
  - `Mock.DataStore.Fail` during the settle read -> still false; retried 5 s later; true once `Fail` is cleared
  - no store: on a fresh DataService clone loaded with `Mock.DataStore.Unavailable = true` already set (the `smoke_polish_data.lua` `polish_data_outage` "Studio without API access" pattern: `K.moduleInstance("server/Services/DataService"):Clone()`, require the clone, `Load`, restore `Unavailable = false` and destroy the clone in every path) -> false at 14 s, true at 15 s with no read. (Setting `Unavailable` on the booted DataService does not take the no-store path: `getStore` is resolved once and cached, so a join there becomes a provisional stand-in.)
  - a failed (provisional) load -> false after 15 s; after the recovery succeeds (its read lands at >= 20 s, so it counts as the settle read) -> true, `Settled` fired once
  - `_SettleForTest(p)` right after a join -> true, `GemsSettled(p) == true` and the attribute set at once (no 15 s wait)
  - a Mythic gem Mix (cost `TycoonCatalog.Fusion.Mix.Mythic.Gems`) before the settle -> refused "Your data is still loading", gems and pets unchanged; after `_SettleForTest(p)` it mixes; a token Mix before the settle mixes
- [ ] **Step 2: Register** `"gem_settle"` after `"secret_pity_save"` on Task 2's line.
- [ ] **Step 3: Run** `--only gem_settle` -> FAIL.
- [ ] **Step 4: Implement** the Interfaces (the flag lives on the cache entry; nothing stored; no new column-0 local).
- [ ] **Step 5: Rewrite** the gem-Mix scenarios found by the grep (settle after the join; same intent).
- [ ] **Step 6: Run** `gem_settle,secret_pity_save,p2flow_fusion_gems,p2fusion_mix,p2fusion_upgrade,p2fusion_exploits,fusion_moves,evo_rarity_saves,bug2garden_fusion,persistence,data_orphans,polish_data_outage,p7data_provisional`, plus every other scenario the Step 5 grep turned up -> PASS. DataService 160, FusionService 101. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): gem actions wait for a settle read after a join (server-hop guard)`

**Only Studio can judge:** the settle read against the live store after a real server hop.

### Task 4: BuyRoulette x1 / x3: one money step that never refuses after the roll

Spec: 5.1 "Randomness", "The request", "The reply", "Rate limits", "PolicyService"; 6 (`Stats.Spins`); 7. Skills: roblox-dev:roblox-security.

**Files:**
- Modify: `src/server/Services/PetService.lua` (header API and reply; one new table `RNG = { Roll, Strip }` filled in `PetService.Init`; `buildStrip(rouletteId, resultId, roll)` draws from `RNG.Strip`; `addCopies` split into `planCopies` + `writeCopies` (`GrantPet` calls both, then `refreshPlayer` + `Sync` as today); `rollAndGrant` replaced by the batch; `buyWithGems`; `PetService.BuyRoulette`; the remote handler in `connectRemotes`; `PetService._SetRngForTest`, `PetService._SetFaultForTest`)
- Modify: `src/shared/Config.lua` (Remotes comment: `"BuyRoulette", -- (rouletteId:string, currency:string|nil, spins:1|3|nil)`)
- Modify: `tools/smoke_eggs.lua`, `tools/smoke_pity.lua`, `tools/smoke.py`, `tools/contract.json`
- Modify (rewrite, keep names): `tools/smoke_server.lua` `V.rouletteResult` (validates every `Pulls[j]` and the mirrored top level); gem-spin scenarios that spin right after a join call `DataService._SettleForTest(p)` (`grep -n "Gems" tools/smoke_p2_gems.lua tools/smoke_p2_flow.lua tools/smoke_storm.lua tools/smoke_economy.lua`); and the two checks that pin today's full-stack refusal:
  - `tools/smoke_economy.lua` `economy`, the block after the comment "stack cap: refunded / not charged, nothing added" (a `withRoll(common)` pull with `prof.Pets[common] = Config.Pets.MaxPerStack`): now `ok == true`, tokens charged once, `Stats.Spins + 1`, `common` stays at the cap, and another Common pet (from `PetCatalog.RarityPool(cloud.Id, "Common")` minus `common`) gained one copy; a second case with every Common at the cap -> `Pulls[1].Substitute.Tokens == Config.Index.Rewards.Common.Tokens`, those tokens added after the charge, no stack grows
  - `tools/smoke_p2_gems.lua` `p2gems_roulettes`, the block "a gem pull into a full stack costs nothing" (a `Pc.RollPet` stub returning a capped Common, then `BuyRoulette(p, "Cloud", "Gems")`): now gems charged once (`gemPrice("Cloud")`), `Stats.Spins + 1`, another Common granted (or the substitute when every Common is capped); its label says "re-picks, charged" instead of "refused and costs nothing". The block above it ("a Secret result of a token roulette is refused whatever paid for it") stays unchanged: it is the `AllowSecret` guard's test

**Interfaces:**
- Consumes: `PetCatalog.RarityPool`, `GemService.RollPet(id, rng, opts)` (Task 1); `DataService.GemsSettled` (Task 3).
- Produces:
  - `PetService.BuyRoulette(player, rouletteId, currency, spins) -> ok, reply | reason`. `spins` nil -> 1; only 1 and 3; anything else, or 3 on a gems-only roulette -> `false, "Bad spins"`.
  - Step 1 checks, in order, with today's texts: live player; known roulette; `currency` through today's `parseCurrency` ("Unknown currency"); in a match ("The shop is closed during a match"); profile ("Your data is still loading"); gem-priced and `not DataService.GemsSettled(player)` -> "Your data is still loading"; `GemService.Quote` (its texts, the lock unchanged); balance against `Price = UnitPrice * spins` computed once ("Not enough cloud tokens" / "Not enough Gems").
  - Step 2 pulls from `RNG.Roll` in order: `roll(id, RNG.Roll)` where `roll` is `PetCatalog.RollPet` or the quote's `Roll`. A pull's rarity is the rolled pet's rarity. When `owned + earlier pulls of this request >= Config.Pets.MaxPerStack`, re-pick uniformly with `RNG.Roll` from `RarityPool(id, rarity)` minus the full pets (counting the request); when all are full the pull keeps its `PetId` and gets `Substitute = { Tokens = Config.Index.Rewards[rarity].Tokens }`, `Count` = the full stack.
  - Step 2 keeps today's `rollAndGrant` guard: if any pull of the request rolls a pet whose rarity is Secret on a roulette without `AllowSecret` (every token roulette; `SECRET_RARITY`), the whole request is refused "The roulette jammed, try again" with nothing charged, nothing written and no `Stats.Spins` change (an impossible roll, refused before the charge; the only refusal after the roll).
  - Step 3 (all that can fail, before the charge, inside a pcall): lookups, `IsNew` / `NewDiscovery` / `Count` / `PoolSize = #RarityPool(id, rarity)`, the strips (`buildStrip` from `RNG.Strip` with the plain `roll(id, RNG.Strip)`), the reply table. An error -> "The roulette jammed, try again", nothing charged.
  - Step 4 one charge: `SpendTokens` / `SpendGems(player, Price)`. Step 5 plain writes: `writeCopies` per pull in order, `Discovered`, `AddTokens` for substitutes, `Stats.Spins += spins`, `MarkDirty`. Step 6, each in its own pcall: `refreshPlayer`, the first pet ever into the active team (`SetTeam`), one `Sync`, `RouletteResult`, `Rolled:Fire(player, petId)` per pull, the announcement (today's rule until Task 6).
  - Reply exactly as spec 5.1: `{ Ok = true, RouletteId, Currency, Spins, UnitPrice, Price, Pulls = { { PetId, Key, Rarity, IsNew, NewDiscovery, Count, PoolSize, Strip, Pity, Substitute } }, PetId, Key, IsNew, NewDiscovery, Count, Strip (pull 1 mirrored), Tokens, Gems }`; failure `{ Ok = false, Reason, RouletteId, Currency, Spins, Tokens, Gems }`. `Strip` is 40 ids with the winner at 34.
  - `PetService._SetRngForTest(rollRng, stripRng)` (nil keeps the current one) and `PetService._SetFaultForTest(stage, fn)` (`stage` `"plan"`: called inside step 3; `"after"`: called inside the step-6 refresh pcall; nil `fn` clears): both work only under `RunService:IsStudio()` (the mock is Studio).
  - Remote `BuyRoulette(rouletteId, currency, spins)`: the 0.25 s cooldown first; `rouletteId` string <= 48; `spins` not nil / 1 / 3, or 3 on a gems-only roulette -> return silently (no answer).

- [ ] **Step 1: Failing tests** (`smoke_eggs.lua`, booted; helpers `give(p, tokens, gems)`, `fire(p, id, currency, spins)`, `results(p)` from the remote log; seeded `Util.NewRng(n)` through `_SetRngForTest`)
  - `egg_spin_x1`: Cloud with tokens -> `Ok`, `Spins == 1`, `UnitPrice == Price == Config.Roulettes[1].Price`, one pull with every field, `#Strip == 40`, `Strip[34] == PetId`, `PoolSize == #PetCatalog.RarityPool("Cloud", Rarity)`, the top level mirrors pull 1, no `SecretPity`; tokens charged once; `Stats.Spins + 1`; `Rolled` fired once; the `AllowSecret` guard: a `PetCatalog.RollPet` stub that returns a Secret pet on Cloud -> `false, "The roulette jammed, try again"`, tokens, `Pets` and `Stats.Spins` unchanged, no `Rolled`; a Cloud x3 whose stub returns a Secret pet on the second pull only -> the whole request refused the same way, nothing charged or granted
  - `egg_spin_x3` (booted; `DataService._SettleForTest(p)` after the join, so the gem cases are not held by the settle):
    - Cloud tokens x3 -> one charge of `3 * 50`, three pulls, `Stats.Spins + 3`, `Rolled` x3, `DataService.Sync` called once (count through a wrapper); Celestial tokens x3 -> one charge of `3 * Price`; Sky gems x3 -> one charge of `3 * Config.Gems.RouletteGemPrices.Sky`; with one gem less -> "Not enough Gems", Pets / Stats / Gems unchanged
    - independence: 2,000 x3 Cloud requests (direct `PetService.BuyRoulette` calls, so the remote cooldown does not stretch the run; tokens topped up, stacks reset every 200) -> requests with three identical pets < 2% (expected about 0.7%), and per pull position each rarity within about 3 sigma of its odds at n = 2,000: Common (60%) and Uncommon (28%) within 3.5 points, Rare (10%) and Epic (2%) within 2 points. (Not the 1.5 points of `egg_roll_pure`, which spec 9 names: that tolerance was sized for 10,000 rolls; at 2,000 it is about 1.4 sigma for Common, so all twelve position checks pass for only about a third of seeds and correct seeded code would fail deterministically.)
    - remote junk spins `2`, `3.5`, `"3"`, `{}`, and `3` on `"Secret"` -> no `RouletteResult`, nothing charged; `BuyRoulette(p, "Cloud", nil, 2)` -> `false, "Bad spins"`; junk currencies `"diamonds"`, `5`, `{ Currency = "x" }` -> "Unknown currency"
    - gems x3 for a restricted account (the PolicyService double of `smoke_p2_gems`) -> GemService's text, nothing charged; two fires 0.1 s apart -> one reply
    - `_SetFaultForTest("after", error)` -> the charge and all three pets landed and the reply was sent; `_SetFaultForTest("plan", error)` -> nothing charged or granted, `Reason == "The roulette jammed, try again"`
  - `egg_full_stack`: every Common at 99, 4,000 Cloud x1 spins -> each Common pull has `Substitute.Tokens == Config.Index.Rewards.Common.Tokens` and `Count == 99`, every spin charged, the Common share within 2.5 points of 60%; only one Common at 99 -> that pet is never granted and the Common share is unchanged; the Secret Roulette (settled with `_SettleForTest`) with both Mythics at 99, 2,000 spins -> Mythic pulls pay `Config.Index.Rewards.Mythic.Tokens`, and the Secret share **counted only over pulls with `Pity ~= true`** (the natural pulls) is within 3 points of 15%. (Counted over every pull it would be wrong once Task 5's pity lands: a forced Secret after every 6 dry spins lifts the long-run share to `0.15 / (1 - 0.85^7)` = 22.1%. Spec 9's "Secret stays at 15%, the pity still counts" means the natural pulls; this plan reads it that way. Before Task 5 no pull carries `Pity`, so the filter counts them all.)
  - `egg_strip`: a `RollRng` stub that always draws the same numbers -> 50 spins' strips are not all equal; the three strips of one x3 differ; every filler is a pet that roulette can roll (the forced-pull half of spec 9's `egg_strip`, "a forced pull's strip is drawn from the normal odds", needs the pity and is added to `secret_pity` in Task 5)
  - `gem_settle` part 2 (`smoke_pity.lua`): before the settle a gem x1 and a gem x3 -> "Your data is still loading", nothing charged; a token spin -> granted
- [ ] **Step 2: Register** on Task 1's line: `ins(server_scenarios, "shutdown", ["egg_spin_x1", "egg_spin_x3", "egg_full_stack", "egg_strip"])`.
- [ ] **Step 3: Run** `--only egg_spin_x1,egg_spin_x3,egg_full_stack,egg_strip,gem_settle` -> FAIL.
- [ ] **Step 4: Implement** the Interfaces.
- [ ] **Step 5: Rewrite** `V.rouletteResult`, the gem-spin scenarios found by the grep, and the two full-stack blocks in `economy` and `p2gems_roulettes` (Files above); the commit body names each.
- [ ] **Step 6: Run** the five plus `egg_roll_pure,p2gems_roulettes,p2gems_altar,p2gems_policy,p2gems_odds,p2flow_arrive,p2flow_build,economy,store_grantpet,storm_altar,boot,final_checks,client_release_roulette,client_p5looks,client_storm` -> PASS (today's MenuController still plays from the mirrored top level). PetService <= 80. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): x1 and x3 egg rolls in one charge; a full stack re-picks or pays tokens, never refuses after the roll`

### Task 5: The Secret pity

Spec: 5.2 (the spin rule, the attribute, the cases, the client numbers). Skills: roblox-dev:roblox-security, roblox-dev:roblox-datastores.

**Files:**
- Modify: `src/shared/Config.lua` (`Gems.SecretRoulette.PityAt = 7`; `Attr.SecretPityLeft = "SecretPityLeft"`)
- Modify: `src/server/Services/PetService.lua` (the pity inside the batch's steps 1 / 3 / 5; `refreshPityAttr(player)` connected to `DataService.ProfileLoaded`, `ProfileRebased`, `Settled` and called after each Secret spin; header)
- Modify: `tools/smoke_pity.lua`, `tools/smoke.py` (its line)
- Modify (extend, keep name): `tools/smoke_eggs.lua` `egg_full_stack` (the forced-pull checks below)

**Interfaces:**
- Consumes: `GetPity` / `SetPity` (Task 2); `GemsSettled`, `Settled` (Task 3); the batch, `RNG.Roll`, `GemService.RollPet(id, rng, { ForceRarity })` (Tasks 1, 4).
- Produces:
  - A Secret Roulette spin: provisional or `GetPity == nil` -> "Your data is still loading" (nothing charged). `Since = max(0, Spins - Hit)`; `forced = Since >= PityAt - 1`; the forced pull is `roll(id, RNG.Roll, { ForceRarity = "Secret" })` (a full stack re-picks inside Secret the same way); new `Spins = Spins + 1`; a Secret pull (natural, forced or substitute) -> new `Hit = new Spins`; computed in step 3, written with `SetPity` in step 5; the pull carries `Pity = true` when forced; reply `SecretPity = { Left = clamp(PityAt - newSince, 1, PityAt) }`. Token roulettes never touch it.
  - Attribute `SecretPityLeft = clamp(PityAt - Since, 1, PityAt)`; absent while loading, provisional or not settled (`GemsSettled == false`). `refreshPityAttr` runs on `ProfileLoaded`, `ProfileRebased` and `Settled` and after each Secret spin; since a recovery's `ProfileRebased` fires before the entry is marked settled (Task 3), it is the `Settled` call that first sets the attribute for a stand-in profile.

- [ ] **Step 1: Failing tests** (booted, settled with `_SettleForTest`)
  - `secret_pity`:
    - a `RollRng` stub whose Float lands in Mythic: spins 1-6 Mythic with the attribute 6, 5, 4, 3, 2, 1 after each; spin 7 is Secret with `Pulls[1].Pity == true`, `SecretPity.Left == 7`, attribute 7
    - a stub that lands in Secret on spin 3 -> `Hit == 3`, attribute 7
    - a refused spin (gems short) leaves `GetPity` unchanged; provisional -> refused, nothing charged; `GetPity` stubbed to nil -> refused, nothing charged; token spins leave `Pity` unchanged
    - a stand-in join has no attribute; inside its recovery's `ProfileRebased` the attribute is still absent (not settled yet); after the recovery and the settle (`Settled` fired: the recovery read lands at >= 20 s, so it counts as the settle read, Task 3) the attribute is set; a rebase that brings another server's +3 Spins updates it
    - `SetPity(p, 8, 0)` (a merged Since of 8) -> attribute 1, the next spin is forced
    - both Mythics at 99: substitute pulls still add to `Spins`
    - a forced pull's strip shows the normal odds (spec 9 `egg_strip`, the near-miss anti-goal "the strip is the server's strip"): `RollRng` fixed through `_SetRngForTest` (the strips must still vary: they come from `StripRng`), then N >= 200 Secret spins, each preceded by `local q = DataService.GetPity(p); DataService.SetPity(p, q.Spins + 6, q.Hit)` (Since 6, so every spin is forced; `Hit` is left at its live value because `SetPity` never lowers it) -> every pull has `Pity == true` and is a Secret, and over the 39 filler cells of every strip (index ~= 34; N * 39 >= 7,800 cells) the share of Secret pets is within 3 points of 15%, not near 100%
    - a failed save (`Mock.DataStore.Fail` for the save after a forced Secret, then the player leaves): a fresh load shows gems, the pet and `Pity` all from before the spin or all from after it, never mixed
  - `egg_full_stack` extended (its Secret Roulette part, both Mythics at 99, 2,000 spins): the natural-pull Secret share stays within 3 points of 15% (Task 4's filter, `Pity ~= true`); at least one pull has `Pity == true` and every such pull is a Secret pet (or a Secret substitute when every Secret is full); `GetPity(p).Spins` grew by exactly 2,000 (substitute pulls count); the share over all pulls is near `0.15 / (1 - 0.85^7)` = 22.1% (within 3 points), which is the pity working, not a failure
  - `gem_settle` part 3 (the hop): two caches on one store (`secondServer`); A: Since 6, a forced Secret (1,000 gems), its leave save held until 8 s after B's load; B refuses the Secret Roulette and gem spins with "Your data is still loading" until settled; after the settle B shows A's gems and attribute 7, and B's next Secret spin is not forced
- [ ] **Step 2: Register** `"secret_pity"` on Task 2's line.
- [ ] **Step 3: Run** `--only secret_pity,gem_settle` -> FAIL.
- [ ] **Step 4: Implement** the Interfaces.
- [ ] **Step 5: Run** `secret_pity,secret_pity_save,gem_settle,egg_spin_x1,egg_spin_x3,egg_full_stack,p2gems_altar,storm_altar` -> PASS. PetService <= 80. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): every 7th Secret Roulette spin without a Secret is a Secret; the count lives in the save`

### Task 6: One announcement per request, Legendary and up, as a chat line

Spec: 5.5 "Big effects only for Legendary and up" (the chat line, `ANNOUNCE_GAP`), 13 call 12. Skills: roblox-dev:roblox-security (a spam path).

**Files:**
- Modify: `src/server/Services/PetService.lua` (`ANNOUNCE_ORDER`; new `ANNOUNCE_GAP = 10`; `announcePull` becomes a per-request announcer with a per-player hold)
- Modify: `src/client/Controllers/NotifyController.lua` (kind `"pull"`)
- Modify: `tools/robloxmock.lua` (if missing: `TextChatService.TextChannels` Folder with a `TextChannel` `RBXSystem` whose `DisplaySystemMessage(text)` appends to `Mock.SystemMessages`)
- Modify: `tools/smoke_eggs.lua` (`egg_announce`, `client_notify_pull`; `egg_spin_x1` gains the Legendary-only lines), `tools/smoke.py`
- Modify (rewrite, keep names): `tools/smoke_economy.lua` `economy` (the announcement block), `tools/smoke_server.lua` (`NOTIFY_KINDS` gains `pull`)

**Interfaces:**
- Produces:
  - `ANNOUNCE_ORDER = rarityOrder.Legendary`. Per request: the best pull (highest rarity, the first on ties) named, `N` = the other Legendary-or-better pulls; text `"<DisplayName> hatched a <Rarity> <Pet name>!"` plus `" (+N more)"` when `N > 0`; others get `notify(other, text, "pull", 4)` at once, the puller after `ANNOUNCE_DELAY` 5 s. At most one line per player per `ANNOUNCE_GAP`; requests inside the gap are held and sent as one line when it ends (the best held pull named, `(+N more)` counting every other held Legendary-or-better pull).
  - NotifyController: kind `"pull"` -> `TextChatService.TextChannels.RBXSystem:DisplaySystemMessage(text)` with the rarity word wrapped in `<font color="#RRGGBB">` (its `Config.Rarities` colour); channel missing or an error -> today's toast with kind `"good"`.

- [ ] **Step 1: Failing tests**
  - `egg_announce` (booted, players `p` and `witness`, pulls steered with `_SetRngForTest` stubs): an Epic pull -> no `"pull"` Notify to anyone; a Legendary -> the witness gets one Notify kind `"pull"` with `"<p.DisplayName> hatched a Legendary <name>!"` at once, `p` gets it after 5 s and not before; an x3 Legendary + Mythic + Common -> one line naming the Mythic with `" (+1 more)"`; two Legendary requests 2 s apart -> the second is held and arrives as one line when the 10 s gap ends; five x3 Legendary requests within 10 s -> at most 2 lines reach the witness in those 10 s
  - `egg_spin_x1` gains: an Epic pull sends no `"pull"` Notify, a Legendary sends one
  - `client_notify_pull` (client): `KC.toClient("Notify", "Ann hatched a Legendary Sun Fox!", "pull", 4)` -> one `Mock.SystemMessages` entry containing `<font color="#F2B644">Legendary</font>` and no toast; with `TextChannels` removed -> one toast with the text
- [ ] **Step 2: Register** on Task 1's line: `"egg_announce"` at the end of its shutdown list; `client_files.append("smoke_eggs.lua"); ins(client_scenarios, "client_final", ["client_notify_pull"])`.
- [ ] **Step 3: Run** `--only egg_announce,egg_spin_x1,client_notify_pull` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Rewrite** `economy`'s block (spec 9: "hatched", kind `"pull"`, Legendary and up, once per request, the puller's delayed copy stays, a Rare pull is not announced) and `NOTIFY_KINDS`.
- [ ] **Step 6: Run** `egg_announce,client_notify_pull,economy,egg_spin_x1,egg_spin_x3,final_checks,client_notify` -> PASS. PetService <= 80, NotifyController <= 111. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): one chat line per request for Legendary and up, at most one per player every 10 s`

### Task 7: `StoreRequest("GemBuy")`: the gem XP Potion

Spec: 5.8 "`StoreRequest("GemBuy", key)`", 5.3 (`Store.GemItems`), 7. Skills: roblox-dev:roblox-security.

**Files:**
- Modify: `src/shared/Config.lua` (`Store.GemItems`; Remotes comment `"StoreRequest", -- (action:string, key:string)  "Buy" (a Config.Store.Items key) / "GemBuy" (a Config.Store.GemItems key)`; `Attr.XpPassState = "XpPassState"`)
- Modify: `src/shared/StoreCatalog.lua` (`GemItems`, `GemItem`; `Validate` covers them; header)
- Modify: `src/server/Services/StoreService.lua` (`onRequest`; new `BuyWithGems`; the `XpPassState` attribute written whenever `PassState(player, "PetXp2x")` changes; header)
- Create: `tools/smoke_gem_prices.lua` (server world, booted)
- Modify: `tools/smoke_pity.lua` (`gem_settle` part 4), `tools/smoke.py`, `tools/contract.json` (`StoreService.BuyWithGems`, `StoreCatalog.GemItems`, `GemItem`)
- Modify (rewrite, keep names): `tools/smoke_store.lua` `store_remote` (an unknown action is still dropped; `"GemBuy"` is now answered)

**Interfaces:**
- Produces:
  - `Config.Store.GemItems = { { Key = "XpPotionGems", Gems = 75, Name = "XP Potion (30 min)", Grants = { Boost = { XpPotion = 1800 } } } }`.
  - `StoreCatalog.GemItems() -> { { Key, Gems, Name, Grants }... }` (copies), `StoreCatalog.GemItem(key) -> item | nil`.
  - `StoreService.BuyWithGems(player, key) -> ok, reason`, checks in order: live player and `GemItem(key)` (else false, silent); in a match "The Store is closed during a match"; loading or provisional "Your save is still loading"; not `GemsSettled` "Your data is still loading"; `PassState(player, "PetXp2x")` `"Owned"` -> "You already have x2 Pet XP", `"Checking"` -> "Checking your passes..." (`"NotOwned"` / `"Unavailable"` allow); `max(BoostEnds(player, "XpPotion"), now) + 1800 - now > Config.Store.Potion.CapSeconds` -> "Your potion time is full"; gems < 75 -> "Not enough gems". Then one step: `SpendGems(75)`, `AddBoost(player, "XpPotion", 1800)` (its refusals were checked first); toast "XP Potion: +30 minutes" (good); `StoreService.Changed:Fire(player)`. Each refusal toasts (bad). Restricted accounts may buy.
  - `onRequest(player, action, key)`: action `"Buy"` or `"GemBuy"` with a string key, else dropped; both rate-limited on the one key `"StoreRequest"` (`REQUEST_GAP` 1 s).
  - Player attribute `XpPassState` = the PetXp2x `PassState` string, written on every change (the shop's potion label reads it).

- [ ] **Step 1: Failing tests**
  - `gem_potion_buy` (booted, settled): 75 gems -> `BoostEnds(p, "XpPotion")` grows by 1,800 s, one toast "XP Potion: +30 minutes", `Changed` fired once, `XpBoostEnds` updated; each refusal leaves gems and `BoostEnds` unchanged and toasts its text: in a match, provisional, not settled (no `_SettleForTest`), pass `"Owned"`, pass `"Checking"` (the StoreService pass entry set by the test), bank full (`BoostEnds = now + 7 d - 1000`), 74 gems; pass `"NotOwned"` and `"Unavailable"` buy; a restricted account buys; `"GemBuy"` then `"Buy"` 0.5 s apart -> the second is dropped, and the reverse; `("GemBuy", 5)` and `("Sell", "x")` -> dropped silently; `p:GetAttribute("XpPassState") == StoreService.PassState(p, "PetXp2x")` after each pass change
  - `gem_settle` part 4: `GemBuy` before the settle -> "Your data is still loading"
- [ ] **Step 2: Register** `if p5("smoke_gem_prices.lua"): server_files.append("smoke_gem_prices.lua"); ins(server_scenarios, "shutdown", ["gem_potion_buy"])  # [lobby-shop, Tasks 7/8] the gem XP Potion, the gem prices (smoke_gem_prices.lua)`
- [ ] **Step 3: Run** `--only gem_potion_buy,gem_settle` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Rewrite** `store_remote`.
- [ ] **Step 6: Run** `gem_potion_buy,gem_settle,store_remote,store_passes,store_router,store_catalog,store_config,fixr_store_boost_attr,client_fixr_store_gem_thanks,contract` -> PASS. StoreService <= 50, StoreCatalog <= 25. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): buy a 30-minute XP Potion with 75 gems (StoreRequest GemBuy)`

### Task 8: Gem prices, gem packs and token packs

Spec: 5.3 (all of it), 15 (token packs). Skills: roblox-dev:roblox-security (prices are money).

**Files:**
- Modify: `src/shared/Config.lua` (`Gems.RouletteGemPrices`, `Gems.SecretRoulette.GemPrice`, `Gems.Products`, `Store.Items` Tokens1 / Tokens2 / Tokens3)
- Modify: `src/shared/TycoonCatalog.lua` (`Fusion.Mix` Mythic / Secret)
- Modify: `src/shared/StoreCatalog.lua` (`gemItem` copies `Robux`)
- Modify: `tools/sim_tycoon.py` (constants block `# ==== BEGIN/END SIM CONSTANTS ====`, `run_check`, a new `--gems` report)
- Modify: `README.md` (the gem section, the product table and the roulette table, from Config)
- Modify: `tools/smoke_gem_prices.lua` (`gem_prices`), `tools/smoke.py` (its line)
- Modify (rewrite, keep names): `smoke_p2_gems.lua` `p2gems_roulettes` (prices), `smoke_p2_flow.lua` (the `p2flow_*` price lines), `smoke_store.lua` `store_catalog` / `store_config` (token amounts, the `Robux` field), `smoke_p4_economy.lua` `p2_economy` (the new sim names exist and match), `smoke_p2_final.lua` `p2final_docs` (README vs Config), `smoke_content.lua` `catalog` / `config_shape` (any line that pins a gem price, a gem product or a token pack amount; "four roulettes" stays true, the Secret Roulette lives in `Config.Gems`)

**Interfaces:**
- Produces:
  - `RouletteGemPrices = { Cloud = 4, Storm = 15, Sky = 60, Celestial = 250 }`; `SecretRoulette.GemPrice = 1000`; `Gems.Products` = `{ Id = 0, Gems = 150, Robux = 49, Name = "Pouch of Gems" }`, `{ 0, 500, 149, "Bag of Gems" }`, `{ 0, 1500, 399, "Chest of Gems" }`, `{ 0, 4000, 999, "Vault of Gems" }`; Tokens1 / 2 / 3 `Grants.Tokens = 2500 / 8000 / 25000`, `Name = "2,500 Cloud Tokens" / "8,000 Cloud Tokens" / "25,000 Cloud Tokens"` (Robux 49 / 149 / 399 kept); `Fusion.Mix.Mythic = { Gems = 50 }`, `Secret = { Gems = 125 }`; `StoreCatalog.List()` gem items carry `Robux`.
  - sim constants `GEM_SPIN = [4, 15, 60, 250]`, `GEM_SECRET = 1000`, `SECRET_PITY = 7`, `GEM_MIX = [50, 125]`, `GEM_POTION = 75`, `GEM_PACKS = [150, 500, 1500, 4000]`, `PACK_ROBUX = [49, 149, 399, 999]`, `TOKEN_PACKS = [2500, 8000, 25000]`, `GEM_DAY_CASUAL = 20`, `GEM_DAY_REGULAR = 58` (the last two marked as assumptions, not compared); `--check` compares the others with Config / TycoonCatalog (`same(...)`). `--gems` prints a non-prestiging and a prestiging player (income built from `PRESTIGE_GEMS`, the `DAILY_TIERS` gem cells and the dungeon / arena / raid / index gem rewards read from Config): days (or hours) per gem spin of each price, gems per Secret pet, the pack table with bonus %, Robux per spin for both currencies on every machine; it checks: the non-prestiging regular player's days per Secret spin in 12 .. 25; gems per Secret pet = `1000 * (1 - 0.85^7) / 0.15` = 4,529 +- 1; pack gems per Robux strictly rising; the 399 R$ pack = `GEM_SECRET + 2 * GEM_SPIN[3]`; `PACK_ROBUX` equal to the Config `Robux` fields. The prestiging player's hours per Secret spin are printed, not checked.

- [ ] **Step 1: The sim first.** Add the constants (new values), `--gems` and the checks; run `py -3.12 tools/sim_tycoon.py --gems`. The days-per-Secret-spin check must pass **before** Config changes; if it fails, stop this task and put the numbers in the ledger's "Questions for the morning" (spec 5.3).
- [ ] **Step 2: Failing test `gem_prices`** (booted, settled, allowed account): every number above read from Config / TycoonCatalog / StoreCatalog (`List()` gem items' `Gems` and `Robux`, Tokens1..3 `Grants` and `Name`); `GemService.Quote` prices 4 / 15 / 60 / 250 / 1,000; a Mythic Mix with gems charges 50 and a Secret Mix 125.
- [ ] **Step 3: Register** `"gem_prices"` on Task 7's line. **Run** `--only gem_prices` -> FAIL; `py -3.12 tools/sim_tycoon.py --check` -> problems listed.
- [ ] **Step 4: Implement** Config, TycoonCatalog and `gemItem`.
- [ ] **Step 5: README** tables rewritten from Config until `p2final_docs` passes.
- [ ] **Step 6: Rewrite** the listed scenarios.
- [ ] **Step 7: Run** `gem_prices,p2gems_roulettes,p2gems_altar,p2flow_arrive,p2flow_build,p2flow_fusion_gems,p2flow_prestige,p2flow_rejoin,store_catalog,store_config,store_router,p2_economy,p2final_docs,catalog,config_shape,client_store_window,client_fixr_store_art` -> PASS; `py -3.12 tools/sim_tycoon.py --check` -> ok; `--gems` -> its checks ok (paste both players' lines into the ledger). check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(lobby-shop): gem prices B (4/15/60/250, Secret 1,000), packs 150-4,000 with Robux suggestions, token packs 2,500-25,000`

### Task 9: LeaderboardService

Spec: 5.10 "Server" (with section 15: Ring best, no Climb wins), 7. Skills: roblox-dev:roblox-datastores, roblox-dev:roblox-security, roblox-dev:roblox-performance.

**Files:**
- Modify: `src/shared/Config.lua` (`Config.Leaderboard`; remote `"LeaderboardState", -- server -> client (state:table)` appended after `"TroveState"`)
- Create: `src/server/Services/LeaderboardService.lua`
- Modify: `src/server/Main.server.lua` (`loadOptionalService("LeaderboardService")`; `Init` after DataService's Init with `{ DataService = DataService }`)
- Modify: `tools/robloxmock.lua` (`DataStoreService:GetOrderedDataStore(name)` with `SetAsync` (whole numbers only, else error), `GetSortedAsync(ascending, pageSize)` pages (`GetCurrentPage()` -> `{ { key, value } }`, `IsFinished`), the existing `dsGate` failures; `Budget = {}` added to the `Mock.DataStore` table literal (today it has `Data`, `Fail`, `Unavailable`, `Latency`, `Calls`, `Writes` and no `Budget`, so indexing it would error); `GetRequestBudgetForRequestType(type)` -> `(Mock.DataStore.Budget or {})[type.Name] or 100`; a test that sets a budget puts `Mock.DataStore.Budget = {}` back in every path; `Enum.DataStoreRequestType` (`SetIncrementSortedAsync`, `GetSortedAsync`) if missing; `UserService:GetUserInfosByUserIdsAsync(ids)` -> `{ { Id, Username, DisplayName } }` from `Mock.Users`, erroring while `Mock.UserServiceFail`)
- Create: `tools/smoke_leaderboard.lua` (server world, booted)
- Modify: `tools/smoke.py`, `tools/contract.json` (`server/Services/LeaderboardService`: `Init`, `ValueOf`, `State`, `Scope`)

**Interfaces:**
- Produces:
  - `Config.Leaderboard = { Stores = { Trophies = "NimbusClimb_LB_Trophies_v1", Pets = "NimbusClimb_LB_Pets_v1", Ring = "NimbusClimb_LB_Ring_v1" }, Pages = { "Trophies", "Pets", "Ring" }, Labels = { Trophies = "Trophies", Pets = "Pets found", Ring = "Ring best" }, Titles = { Trophies = "TOP TROPHIES", Pets = "TOP PETS FOUND", Ring = "TOP RING ROUND" }, Top = 10, ReadSize = 100, RefreshSeconds = 240, WriteEvery = 120, SweepSeconds = 60, SeedDelay = 30, RetrySeconds = { 30, 60, 120, 240 }, BudgetFloor = { Write = 20, Read = 2 }, TurnSeconds = 15, FallbackRefresh = 30, PollSeconds = 5, MaxValue = 1e12, WriteInStudio = false }`.
  - `LeaderboardService.ValueOf(player, stat) -> whole number | nil` (nil while loading or provisional): Trophies = `Battle.Trophies`; Pets = the number of `Discovered` keys that are `PetCatalog.Get` ids; Ring = `DataService.GetRing(player).Best`; floored, clamped 0 .. `MaxValue`; key `tostring(UserId)`.
  - `LeaderboardService.State(player) -> { Stats = { [stat] = { Top = { { UserId, Name, Value }... <= 10 }, You = { Rank = n | nil, Value = n | nil } } }, Scope = "Global" | "Server", NextAt, UpdatedAt }` (times from `workspace:GetServerTimeNow()`); `LeaderboardService.Scope()`.
  - Writes, reads, names and the "Server" fallback exactly as spec 5.10 (budget floors, backoff, the 5 s own-value poll, `BindToClose` <= 5 s, no writes while `RunService:IsStudio()` and `WriteInStudio == false`). `LeaderboardState` is sent on profile load, after each refresh and when a player's own value changes. The client sends nothing.

- [ ] **Step 1: Failing tests** (`smoke_leaderboard.lua`; `Config.Leaderboard.WriteInStudio = true` inside the write cases, restored after)
  - `lb_write`: no write before `SeedDelay` after the load; none for a provisional profile; none when the value is 0 at the seed; the first write at >= 30 s; two changes 10 s apart -> one write per stat per `WriteEvery`; a leave writes what changed once; budget 19 -> no write until it is back at 20; values 1e15 -> 1e12 and 12.7 -> 12; a `Discovered` key that is not a pet id is not counted; `WriteInStudio = false` -> zero `SetAsync` calls
  - `lb_read`: the three boot reads happen at different times; before the first good page `Scope == "Server"` with live values sorted; a 100-entry mock store -> `Top` 10 with `Mock.Users` display names, `You.Rank` for a player inside the 100 and nil outside, `You.Value` nil while provisional; a failing read keeps the last page and retries after 30 / 60 / 120 / 240 s; 2 failures before any good read -> `"Server"`; `Mock.UserServiceFail` -> `GetNameFromUserIdAsync`, then `"Player"`; `NextAt` / `UpdatedAt` equal `GetServerTimeNow()`-based times; +1 trophy -> one `LeaderboardState` within 5 s, no change -> none
  - `lb_fallback`: no store, on a fresh LeaderboardService clone loaded and `Init`ed with `Mock.DataStore.Unavailable = true` already set (the `polish_data_outage` clone pattern; restore `Unavailable = false` and destroy the clone in every path; setting `Unavailable` on the booted service would only make its reads fail and keep the last good page, not the no-store path) -> `Scope == "Server"`, live sorted values, zero writes, a refresh every 30 s
- [ ] **Step 2: Register** `if p5("smoke_leaderboard.lua"): server_files.append("smoke_leaderboard.lua"); ins(server_scenarios, "shutdown", ["lb_write", "lb_read", "lb_fallback"])  # [lobby-shop, Tasks 9/11] the global leaderboard: writes, reads, fallback, the board (smoke_leaderboard.lua)`
- [ ] **Step 3: Run** `--only lb_write,lb_read,lb_fallback` -> FAIL.
- [ ] **Step 4: Implement** (the mock first, then the service).
- [ ] **Step 5: Run** `lb_write,lb_read,lb_fallback,boot,load_modules,mock_selftest,contract,final_checks,shutdown` -> PASS. LeaderboardService <= 60, Main.server <= 58. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): a global leaderboard service (Trophies, Pets found, Ring best) with a this-server fallback`

**Only Studio can judge:** live OrderedDataStore reads after publish (Studio reads need API access; it never writes there).

### Task 10: The trove on the plaza, its Join sign, the Egg Guide

Spec: 5.9 (all of it), 5.6 "The 3D eggs" (the shelf). Skills: roblox-dev:roblox-architecture (a new world module).

**Files:**
- Modify: `src/server/Services/LobbyBuilder.lua` (`Build`: `L.TroveCF` once, the `_ForceShopFallback` hook; `buildShop`: the trove at `L.TroveCF`, the Egg Guide at the old spot; `fallbackShop`: the fallback trove at `L.TroveCF`; `buildTrove`: the sign post at local x -6.2, `JoinAnchor` + `JoinBillboard`; `buildRarityBoard`: the subtitle; one new local `LobbyBoardBuilder`)
- Create: `src/server/Services/LobbyBoardBuilder.lua` (`EggGuide` now; `Leaderboard` in Task 11)
- Modify: `src/server/Services/TroveService.lua` (`TroveGroupDone`; `Init` connects `ProfileLoaded` / `ProfileRebased`; `Joined` sets it at the claim)
- Modify: `src/shared/Config.lua` (`Attr.TroveGroupDone = "TroveGroupDone"`; `Tags.Spin = "NC_Spin"`, `Tags.Bob = "NC_Bob"`)
- Create: `tools/smoke_lobby_shop_world.lua` (server world, booted)
- Modify: `tools/smoke.py`, `tools/contract.json` (`server/Services/LobbyBoardBuilder`: `EggGuide`, `Leaderboard` pending)
- Modify (rewrite, keep names): `smoke_trove.lua` `trove_build` (the plaza spot), `smoke_hud_items.lua` `huditems_gone` (count the shop prompts by name; the trove is no longer on the island), `smoke_polish_worldtext.lua` `polish_worldtext` (the Join sign and the Egg Guide in the census)

**Interfaces:**
- Produces:
  - Trove spot, worked out **once per Build**: in `Build`, right before `pcall(buildShop, root, L)`, `pos = plazaSpot(43, 56, 6.5, L)` (when nil it has warned; call again with `force = true` so there is always one trove) and `L.TroveCF = faceCentre(pos - Vector3.new(0, LAWN, 0))` (a field of the layout table, no new local; before `buildPlaza`, so its reservation comes first). `buildShop` builds `buildTrove(f, L.TroveCF)` and `fallbackShop` calls `fallbackTrove(f, L.TroveCF)`; neither calls `plazaSpot` again (a second call after `buildShop` reserved the spot and then failed would find it taken and warn "plaza decor skipped"). `LobbyInfo.Shop.ItemShop` keeps `{ PromptPart, Center, Model, Lid }`.
  - Studio-only hook `LobbyBuilder._ForceShopFallback` (a module field, nil by default; read in `Build` only under `RunService:IsStudio()`): when true, `Build` skips `buildShop` and takes the `fallbackShop` path exactly as if `buildShop` had errored. Today nothing can force the fallback (neither `smoke_trove.lua` nor LobbyBuilder has a hook; `fallbackShop` runs only after `buildShop` throws).
  - `buildTrove` additions: invisible `JoinAnchor` at `cf * CFrame.new(0, 10.5, 0)` (the trove stays <= 60 parts) with BillboardGui `JoinBillboard` (the `newTag` / `tagPlate` / `tagText` shape of `TroveBillboard`); `Config.Trove.GroupId > 0` -> "Join the group!" over "2,000 Cash + 200 Tokens" (from the Group ask's Reward, with commas); `GroupId == 0` -> one line "Group rewards coming soon!". The billboard is tagged `Config.Tags.Bob` with attributes `BobStuds = 0.5`, `BobSeconds = 2.4`.
  - `LobbyBoardBuilder.EggGuide(parent, cf, H) -> Model "EggGuide"` with `H = { noticeBoard, surfaceGui, signPanel, signText, box, Mesh, C, MAT, LAWN }` (LobbyBuilder's helpers, passed in): an 11x8 `noticeBoard` named `EggGuideBoard` (`prop_board_s`) whose SurfaceGui shows the seven `Config.Eggs.Names` in rarity colours, left to right in `Config.Eggs.Order`, and "Every egg hatches a random pet of its rarity"; a low stone shelf `EggShelf` (about 18 x 0.8 x 2.6) at `cf * CFrame.new(0, 0, -4)`; seven `Egg_<Rarity>` Ball parts 2.25 x 3 x 2.5 standing on it 2.5 studs apart in order, SmoothPlastic in the rarity colour (Secret rgb(40,40,52) with a violet tint), each `H.Mesh.tag(egg, EGG_KEYS[rarity], eggCF)` where `EGG_KEYS = { Common = "egg_common", ..., Secret = "egg_secret" }` is a literal table (Task 22's key check reads literals).
  - Rarity board `Sub` text: "Every egg hatches a pet of its rarity".
  - TroveService: player attribute `TroveGroupDone = true` for a loaded, non-provisional profile whose saved `Trove.Group == true`, on `DataService.ProfileLoaded`, `DataService.ProfileRebased` and at the claim; never cleared.

- [ ] **Step 1: Failing test `lobby_trove_plaza`** (booted)
  - the `SkyTrove` centre is at polar 43 degrees, r 56 from `Config.Lobby.Origin` (+-0.5 stud) and faces the plaza centre (dot > 0.99); <= 60 BaseParts; `Sign` post at local x -6.2 of the trove CFrame; `PromptPart` within 10 studs of the centre; `LobbyInfo.Shop.ItemShop` has `PromptPart`, `Center`, `Model`, `Lid`
  - `JoinBillboard` reads "Group rewards coming soon!" at `GroupId 0`; rebuilt with `GroupId = 123` it reads "Join the group!" and "2,000 Cash + 200 Tokens"; tagged `NC_Bob` with its two attributes
  - the forced fallback shop (`LobbyBuilder._ForceShopFallback = true`, a second `LobbyBuilder.Build()` with the booted lobby set aside and put back as `smoke_p6_lobby.lua` does, the hook reset to nil in every path) puts its trove at the same plaza spot; exactly one `SkyTrove` in the lobby either way; no "plaza decor skipped" warn on that build either
  - a stored profile with `Trove = { Group = true }` -> `TroveGroupDone == true` after the load, and after a provisional load's recovery; a claim sets it; a second player without the claim has no attribute
  - the Egg Guide stands at the old spot (`at(-21, -8)`), seven eggs in rarity order, the shelf at least 3 studs from every roulette machine's prompt part; the dress requests are read from a rebuild with `LobbyBuilder._Kit = { Targets = {}, Clouds = {} }` (reset to nil after): seven `Targets` records with `Key` `egg_common` .. `egg_secret` whose `Target` is the matching `Egg_<Rarity>` part (`Mesh.tag` records every call there before its MeshIds status check). `ML_DressKey` itself is asserted only when `MeshLibrary.Status(key) ~= "missing"` (the `--mesh` fixture run): no egg key has a `MeshIds` id, so in the default run `Mesh.tag` returns before `MeshLibrary.Tag` and the attribute is never set
  - no "plaza decor skipped" warn in the build log; every lobby light within the light rule
- [ ] **Step 2: Register** `if p5("smoke_lobby_shop_world.lua"): server_files.append("smoke_lobby_shop_world.lua"); ins(server_scenarios, "shutdown", ["lobby_trove_plaza"])  # [lobby-shop, Tasks 10/12/13/14] the trove on the plaza, the Altar gate, the altar portals, the world gem (smoke_lobby_shop_world.lua)`
- [ ] **Step 3: Run** `--only lobby_trove_plaza` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Rewrite** `trove_build`, `huditems_gone`, `polish_worldtext`.
- [ ] **Step 6: Run** `lobby_trove_plaza,trove_build,trove_group_once,trove_stale_once,trove_provisional,trove_two_servers,trove_exploits,client_trove,client_trove_mobile,huditems_gone,polish_worldtext,client_polish_worldtext,p5world_lobby,bb6_lobby_lights,lobby,p6lobby_server` -> PASS; then `py -3.12 tools/smoke.py --quick --mesh --only lobby_trove_plaza` -> PASS (the egg manifests exist, so the `ML_DressKey` checks run there). LobbyBuilder <= 155, LobbyBoardBuilder <= 40, TroveService <= 28. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the Sky Trove moves to the plaza lawn with a Join sign; an Egg Guide with the seven eggs takes its old spot`

**Only Studio can judge:** the trove seen from the spawn on PC and a phone; walking the lawn paths around it.

### Task 11: The leaderboard board in the world

Spec: 5.10 "World". Skills: roblox-dev:roblox-architecture.

**Files:**
- Modify: `src/server/Services/LobbyBoardBuilder.lua` (`Leaderboard`)
- Modify: `src/server/Services/LobbyBuilder.lua` (`buildPlazaDecor`: one more entry in its pcall list, after `"boards"`, calling `LobbyBoardBuilder.Leaderboard(f, L, H)`)
- Modify: `tools/smoke_leaderboard.lua` (`lb_world`), `tools/smoke.py` (its line)

**Interfaces:**
- Consumes: `H` (Task 10) plus `plazaSpot` and `faceCentre`.
- Produces: `LobbyBoardBuilder.Leaderboard(parent, L, H) -> Model | nil`: `pos = H.plazaSpot(295, 48, 9, L)` (nil -> nothing built; it has warned); `cf = H.faceCentre(pos - Vector3.new(0, H.LAWN, 0))`; Model `LobbyLeaderboard` with the **board layout shared with Task 23** (pivot = ground centre, front -Z toward the plaza centre): `Face` 16 x 13 x 0.4, centre `cf * CFrame.new(0, 9.5, 0)`, SmoothPlastic `C.Navy`, CanCollide false; two posts 1 x 17 x 1 at local x +-8.9 (CanCollide true); a frame 0.6 stud wide around the face; a roof 18.6 x 0.6 x 2.4 at y 16.9 with a ridge. `H.Mesh.tag(model, "prop_board_lb", cf, nil, { "Face" })` (the Face stays a Part for the SurfaceGui). No light.

- [ ] **Step 1: Failing test `lb_world`** (booted): `LobbyLeaderboard` at polar 295 degrees r 48 (+-0.5) facing the centre; `Face.Size` 16 x 13 (+-0.01); the dress request read from a rebuild with `LobbyBuilder._Kit = { Targets = {}, Clouds = {} }` (reset to nil after): one record with `Key == "prop_board_lb"`, `Target` = the `LobbyLeaderboard` model and `Keep` holding `"Face"`; `ML_DressKey == "prop_board_lb"` on the model only when `MeshLibrary.Status("prop_board_lb") ~= "missing"` (the `--mesh` run after Task 23; there is no `MeshIds` id, so the default run never sets it); no "plaza decor skipped" warn; distances: fountain centre >= 24 studs, every `LobbyInfo.NpcSpots` entry >= 14, every `Bench` >= 12.5, every `FlowerBed` >= 13, the spawn >= 30.
- [ ] **Step 2: Register** `"lb_world"` on Task 9's line.
- [ ] **Step 3: Run** `--only lb_world` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** `lb_world,lobby_trove_plaza,lobby,p5world_lobby,p6lobby_server,polish_worldtext,bug2lobby_benches` -> PASS. LobbyBuilder <= 155, LobbyBoardBuilder <= 40. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): the leaderboard board stands on the south lawn`

### Task 12: The Storm Altar gate on the plaza (portal a)

Spec: 5.11 (a). Skills: roblox-dev:roblox-ui (the vortex look).

**Files:**
- Modify: `src/server/Services/LobbyBuilder.lua` (`Gates.Info.Altar`; `Gates.BuildOne` forwards `Pill` and `VortexBoost`; `Gates.Fallback` shows the Pill text and writes the attribute; the Altar `ReturnCFrame` in `Build`'s `gateInfo` block)
- Modify: `src/shared/WorldStyle.lua` (`BuildGate` writes `VortexBoost` as a model attribute when `spec.VortexBoost` is a number)
- Modify: `src/client/PortalVortex.lua` (`Build` reads `rec.Model:GetAttribute("VortexBoost")`; `SwirlLook`)
- Modify: any reader of `LobbyInfo.Gates[*].Pad` that treats a gate's pad as a trigger (`grep -rn "\.Pad" src/server`): it skips the Altar (none may exist; say so in the commit body)
- Modify: `tools/smoke_lobby_shop_world.lua` (`altar_gate`), `tools/smoke.py` (its line)
- Modify (rewrite, keep names): `smoke_p6_gates.lua` `p6gates_server` / `client_p6gates` (the Altar spec row: Pad, Pill, VortexBoost), `smoke_p6_portalfx.lua` `client_p6portalfx` (the Altar's vortex is brighter than the Obby's at the same distance), `smoke_p5_world.lua` `p5world_gates` (the Altar pad in the pad checks), `smoke_bug2_lobby.lua` `bug2lobby_altarportal` (the two arrival checks: "3 studs over the ground" = over the pad top; the 5x5x5 "nothing solid" box sits above the pad top)

**Interfaces:**
- Produces:
  - `Gates.Info.Altar = { Title = "Storm Altar", Info = "Secret pets", Pad = true, Pill = "Secret Roulette", VortexBoost = 1.4 }`.
  - `LobbyInfo.Gates.Altar.ReturnCFrame`: 18 studs in front of the gate site (on the pad's front half), 3 studs over the pad top (the highest top of the Pad's parts), looking out along the gate's LookVector. GateService's "Travel" prompt stays the only way in.
  - PortalVortex: `v.Boost = math.max(1, attribute or 1)`; with `Boost > 1` the tint is lifted toward white by `Boost - 1` and the glow by `Boost` (Texture: `BRIGHTNESS * Boost`; Fallback: beam / streak colours lifted the same, `LightEmission` scaled and capped at 1); `SwirlLook`'s deep colour lifted the same. `Boost == 1` gives today's numbers exactly.

- [ ] **Step 1: Failing test `altar_gate`** (booted): the Altar gate has a 14x14 pad 14 studs in front with the Obby pad's inlay and lantern children (same names); its tag reads "Storm Altar" / "Secret pets" and shows the Pill "Secret Roulette"; model attribute `VortexBoost == 1.4`; the forced `Gates.Fallback` gate has the Pill text and the attribute too; `ReturnCFrame` is 14..21 studs along the LookVector from the site and 3 +- 0.1 over the pad top; standing on the pad for 3 s teleports nobody; the `gate_altar` LayoutSig target still carries its `ML_DressKey`.
- [ ] **Step 2: Register** `"altar_gate"` on Task 10's line.
- [ ] **Step 3: Run** `--only altar_gate` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Rewrite** the four listed scenarios.
- [ ] **Step 6: Run** `altar_gate,p6gates_server,client_p6gates,client_p6portalfx,p6portalfx_curves,p5world_gates,bug2lobby_altarportal,portals,hudpill_travel,polish_portals,client_polish_portals,storm_altar` -> PASS. LobbyBuilder <= 155, WorldStyle <= 50, PortalVortex <= 26. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the Storm Altar gate gets its pad, a Secret Roulette pill and a brighter vortex`

**Only Studio can judge:** the Altar's boosted vortex beside the Obby gate's, by eye, with the vortex on.

### Task 13: The summon glow and the standing return ring (portals b and c)

Spec: 5.11 (b), (c), the altar budget line. Skills: roblox-dev:roblox-performance (part budget).

**Files:**
- Modify: `src/server/Services/StormAltar.lua` (new `buildPortalGlow(parent, A)` and a `"portal glow"` section in `StormAltar.Build`; `buildReturnPortal` rebuilt; `RETURN_SIDE` 5.5 -> 9; header)
- Modify: `tools/smoke_lobby_shop_world.lua` (`altar_portal_glow`), `tools/smoke.py` (its line)
- Modify (rewrite, keep names): `smoke_bug2_lobby.lua` `bug2lobby_altarportal` (the standing green ring instead of 8 flush cyan segments, `RETURN_SIDE` 9, the footprint checks below), `smoke_storm.lua` `storm_altar` (the part budget), `smoke_p5_world.lua` `p5world_lobby` / `bb6_lobby_lights` (the new lights), `smoke_polish_worldtext.lua` (the "To the Plaza" sign)

**Interfaces:**
- Produces:
  - Model `PortalGlow` beside the untouched `Portal`: `GlowDisc` (a Neon 16-gon inside the rim, union radius <= 6.0, 0.06 above the old disc top, rgb(63,200,255)) with a lighter `GlowHeart` (rgb(186,236,255)); `GlowRing` = a Model of 16 Neon segments, **the ring layout shared with Task 22**: pivot = the disc centre on the disc top, centre radius 6.0, 0.35 above the disc top, each segment `2 * 6.0 * tan(11.25 deg) + 0.08` x 0.5 x 0.3; `Mesh.tag(GlowRing, "portal_altar_ring", pivotCF)`; tagged `Config.Tags.Spin` with `SpinSeconds = 6`; rising sparkles; a PointLight 1.5 / 24; a sky beam: an invisible anchor with attachments at 0.5 and 160 studs up, a `Beam` (`FaceCamera = true`, no texture, colour cyan -> white, transparency 0.2 -> 1 with height, width 3 -> 1).
  - `ReturnPortal`: the two flat `Pad` octagons (collidable, the only floor) and `ReturnPrompt` (2.5 up; what `GetReturnPad` returns) stay; `Ring` = a Model tagged `Mesh.tag(ring, "portal_ring", cf * CFrame.new(0, -0.85, 0), { Primary = WorldStyle.Accent.Green })` (the mesh's plinth top ends 0.05 under the octagons' top), facing the altar; its Part fallback: 13 green Neon segments on the ring about `PortalCenter` (4.5 up, radius about 3.9) and two stone feet outside the 4x6x4 box over the pad; every ring part (mesh and fallback) `CanCollide = false`, `CanTouch = false`; `ReturnGlow` removed and one PointLight 1.3 / 14 on `ReturnPrompt`; "To the Plaza" on the ring's `SignFace` (a SurfaceGui at 50 px per stud, lines >= 0.6 stud; on the Part fallback a BillboardGui); sparkles stay. Over 500 parts -> the fallback rings use 12 segments.

- [ ] **Step 1: Failing test `altar_portal_glow`** (booted): `PortalGlow` exists and `Portal`'s children (names and count) equal a build from before this task (recorded in the test as the list today's build gives), `Portal` still has `ML_DressKey == "prop_altar_portal"`; the beam's attachments are about 160 studs apart and `FaceCamera`; `GlowRing` has tag `NC_Spin` and `SpinSeconds == 6`; the dress requests are read from a rebuild with `StormAltar._Kit = { Targets = {} }` (`pcall(SA.Build, info)` as `smoke_bug2_lobby.lua` does; reset to nil after): a record `Key == "portal_altar_ring"` whose `Target` is `GlowRing` and whose `Origin` is the disc centre on the disc top (+-0.01), and a record `Key == "portal_ring"` whose `Target` is `ReturnPortal.Ring`, whose `Origin.Y` equals the Pad octagons' top - 0.05 - 1.0 (+-0.01; 1.0 = the `portal_ring` manifest's `Pad` attachment Y, so the plinth top ends 0.05 under the octagons' top) and whose `Look.Primary` equals `WorldStyle.Accent.Green` (rgb(96,190,140)). `ML_DressKey` (`"portal_altar_ring"` on `GlowRing`, `"portal_ring"` on `ReturnPortal.Ring`) is asserted only when `MeshLibrary.Status(key) ~= "missing"` (the `--mesh` run; neither key has a `MeshIds` id, so the default run shows the Part fallbacks and never sets the attribute); every `ReturnPortal` part except the two Pads has `CanCollide == false` and `CanTouch == false`; every `ReturnPortal` part (its rotated bounds) is at least **4.25** studs off the bridge's centre line (the ring faces the altar, about 27.9 degrees off the bridge line at `RETURN_AHEAD` 17 / `RETURN_SIDE` 9, so the 9 x 9.5 x 3 mesh's nearest corner sits about 4.32 studs out: still clear of the 4-stud half lane; this replaces spec 5.11 / 9's 4.5), outside the landing box and within the deck (`R_TOP`); nothing collidable but the pads in the 4x6x4 box over the pad; `GetReturnPad()` is `ReturnPrompt` with exactly one PointLight (1.3 / 14) and no `ReturnGlow`; the `PlazaGatePrompt` keeps E and range 8; every new light within the lobby rule; the altar <= 500 parts.
- [ ] **Step 2: Register** `"altar_portal_glow"` on Task 10's line.
- [ ] **Step 3: Run** `--only altar_portal_glow` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Rewrite** the listed scenarios.
- [ ] **Step 6: Run** `altar_portal_glow,storm_altar,storm_elements,storm_pet,client_storm,bug2lobby_altarportal,p5world_lobby,bb6_lobby_lights,polish_worldtext,client_polish_worldtext,client_p7vfx_storm` -> PASS; `py -3.12 tools/smoke.py --quick --mesh --only altar_portal_glow,bug2lobby_altarportal` -> PASS (the `portal_ring` mesh is dressed there, so its rotated bounds meet the clearance and footprint checks; the `portal_altar_ring` checks wait for Task 22). StormAltar <= 135. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the summon portal lights up with a ring and a sky beam; the way back is a standing green ring`

**Only Studio can judge:** the beam from the plaza, the ring against the night sky, walking past the return ring from the landing.

### Task 14: The world gem on the altar deck

Spec: 5.7 "World gem". Skills: none extra.

**Files:**
- Modify: `src/server/Services/StormAltar.lua` (new `buildWorldGem(parent, A, gapDeg)` and a `"world gem"` section)
- Modify: `tools/smoke_lobby_shop_world.lua` (`altar_world_gem`), `tools/smoke.py` (its line)

**Interfaces:**
- Produces: Model `WorldGem`, Part fallback `Gem` 4x4x4 Glass in rgb(84,196,246) turned 45 degrees on X and Z, anchored, CanCollide false, 3 studs above the deck, halfway along the walk from the landing to the summon portal and 7 studs to its side, at least 6 studs from every ProximityPrompt part (`AltarPrompt`, `ReturnPrompt`, the plaza-gate prompt anchor), outside the 8-stud bridge lane; `Mesh.tag(model, "gem_world", gemCF)`; tagged `Config.Tags.Spin` with `SpinSeconds = 8`, `BobStuds = 0.6`, `BobSeconds = 3`; a cyan PointLight 1.0 / 12.

- [ ] **Step 1: Failing test `altar_world_gem`** (booted): the model; its dress request from a `StormAltar._Kit = { Targets = {} }` rebuild (a record `Key == "gem_world"`, `Target` = `WorldGem`, `Origin` = the gem CFrame), with `ML_DressKey == "gem_world"` asserted only when `MeshLibrary.Status("gem_world") ~= "missing"` (the `--mesh` run; no `MeshIds` id today); the tag and the three attributes; 3 +- 0.2 studs over the deck top below it; the prompt distances; outside the bridge lane box; its light within the rule; the altar <= 500 parts.
- [ ] **Step 2: Register** `"altar_world_gem"` on Task 10's line.
- [ ] **Step 3: Run** -> FAIL. **Step 4: Implement.**
- [ ] **Step 5: Run** `altar_world_gem,altar_portal_glow,storm_altar,bb6_lobby_lights` -> PASS; `py -3.12 tools/smoke.py --quick --mesh --only altar_world_gem` -> PASS (the `gem_world` manifest exists). StormAltar <= 135. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): a spinning world gem marks the altar where gems are spent`

### Task 15: GemIcon and the gem glyph swap

Spec: 5.7 (`GemIcon`, "Every gem glyph swapped"). Skills: roblox-dev:roblox-ui, roblox-dev:roblox-performance (one shine driver).

**Files:**
- Create: `src/client/UI/GemIcon.lua`
- Modify: `src/client/UI/NeonKit.lua` (`NeonKit.Icon` for `"Gems"`)
- Modify: `src/client/Controllers/HudController.lua` (`newCoin` / `newBadge` for Gems; GemIcon required inside the function or through an existing table: no new column-0 local). Read the merged copy first: gui-redo's review fix 7b4e07d added `HudController.SetVitalsHidden(who, on)`, `S.vitalsOwners` and a `Visible` line in `buildVitals`; keep them as they are (the count is still 161)
- Modify: `src/client/Controllers/StoreController.lua` (the balance pills; `H.artGlyph` for gem packs -> `GemIcon.Pile` 1 / 2 / 4 / 6 by pack order)
- Modify: `src/client/Controllers/ArenaController.lua` (`G.Gem` and the `"% for " .. G.Gem` reward text -> words "gems" or `GemIcon.Amount` where the label has room), `src/client/Controllers/DungeonController.lua` (`G.Gem`, `R.lootText`, the end card's gem lines -> words)
- Modify: `src/client/Controllers/FusionController.lua` (the header `U.GemChip` -> `GemIcon.Amount`, width from icon + number)
- Modify: `tools/dump_gui.lua` (the gallery's `Pill_Gems`; new scene `gems`), `tools/render_gui.py` (`SCENARIOS` + `"gems"`)
- Create: `tools/smoke_gem_icon.lua` (client world)
- Modify: `tools/smoke.py`, `tools/contract.json` (`client/UI/GemIcon`: `New`, `Pile`, `Amount`, `SetAmount`, `Driver`)

**Interfaces:**
- Produces:
  - `GemIcon.New(parent, size, opts) -> Frame "GemIcon"` (`opts = { Shine = true, ZIndex, Name }`; attributes `Simple` (true under 28 px: silhouette, two tones, navy outline >= 2 px whole, no facet, no star) and `Shine` (registered with the driver)); the look of spec 5.7 (tones rgb(186,236,255) / rgb(84,196,246) / rgb(40,120,200), outline rgb(11,16,48) at size / 16).
  - `GemIcon.Pile(parent, size, count) -> Frame "GemPile"` (count 1, 2, 3, 4 or 6, the pitch `PILE` offsets); `GemIcon.Amount(parent, n, opts) -> Frame "GemAmount"` with children `GemIcon` and `Value` (comma number; `opts = { Size, TextSize, Color }`), `GemIcon.SetAmount(frame, n)` (re-measures the width).
  - `GemIcon.Driver() -> { Count = n }`: one Heartbeat for every shine (a sweep every ~3.5 s for 0.6 s, only at >= 20 px and Gfx High), weak-keyed, an icon out of the tree drops out.
  - `NeonKit.Icon(parent, "Gems", size)` -> TextLabel `Icon` with empty Text hosting a `GemIcon` of `size`.
  - HUD Gems coin: badge filled with the navy panel colour plus a cyan UIStroke ring (`Theme.Currency.Gems.Color`), the GemIcon at coin size; other coins unchanged.

- [ ] **Step 1: Failing test `client_gem_icon`** (client, 1920x1080)
  - sizes 16 / 20 / 24 / 32 / 96: `Simple` true for 16, 20, 24 (no facet child, the outline `UIStroke.Thickness >= 2` and whole), false for 32 and 96; `Shine` true at >= 20 with Gfx High, false at 16 and with Gfx Low
  - `Pile` with 1, 2, 3, 4, 6 -> that many `GemIcon` children; `Amount(…, 1250).Value.Text == "1,250"`
  - the HUD Gems coin holds a `GemIcon`, its badge fill is the navy panel colour and its UIStroke cyan
  - census: open the HUD, the Store (Currency tab), Daily, Arena, the Dungeon window, Pets, Index, the Care feed list, Train, the pet picker, the Trove panel and Fusion (Upgrade and Mix): no visible TextLabel / TextButton text contains `"\226\151\134"` (Tasks 16-18 add the stage and the shop)
  - churn (Review Focus 5): create and destroy 500 icons over 50 frames, then resize the viewport 5 times -> `Driver().Count` equals the live icons, `KC.flushErrors` clean
- [ ] **Step 2: Register** `if p5("smoke_gem_icon.lua"): client_files.append("smoke_gem_icon.lua"); ins(client_scenarios, "client_final", ["client_gem_icon"])  # [lobby-shop, Task 15] the drawn cut gem everywhere (smoke_gem_icon.lua)`
- [ ] **Step 3: Run** `--only client_gem_icon` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: dump_gui `gems`** (icons at 16 / 20 / 24 / 32 / 96, piles 1 / 2 / 4 / 6, the HUD coin, chips at 20 / 24 px); render at `--size 844x390` and `--size 1920x1080` into the evidence folder and look at them against the pitch's gem frames.
- [ ] **Step 6: Run** `client_gem_icon,client_gui_dump,client_hud,client_p5hud_pills,client_store_window,client_fixr_store_art,client_daily_window,client_daily_ui_a,client_fusion_ui_a,client_p2fusion,client_ui_kit,contract` -> PASS. HudController 161, NeonKit <= 34, StoreController <= 56, FusionController <= 48, GemIcon <= 30. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): gems are drawn as cut gems everywhere (GemIcon); no gem glyph text left`

**Only Studio can judge:** the shine on a real phone, the HUD coin beside the others.

### Task 16: Egg art and the egg stage

Spec: 5.5 (all of it), 5.6 (the GUI eggs). Skills: roblox-dev:roblox-ui, roblox-dev:roblox-performance.

**Files:**
- Create: `src/client/UI/EggArt.lua`, `src/client/UI/EggStage.lua`
- Modify: `tools/dump_gui.lua` (scenes `eggs`, `hatch:strip`, `hatch:strip3`, `hatch:crack`, `hatch:reveal`, `hatch:reveal3`, `hatch:secret`), `tools/render_gui.py` (`SCENARIOS`)
- Create: `tools/smoke_egg_stage.lua` (client worlds)
- Modify: `tools/smoke.py`, `tools/contract.json` (`client/UI/EggArt`, `client/UI/EggStage`)
- Not wired yet: `EggStage.Init` (the `RouletteResult` listener) is called by ShopController in Task 17, when MenuController's old stage goes; tests drive `EggStage.Show(result)`.

**Interfaces:**
- Consumes: `ClientSettings` `FastHatch` (Task 2); `GemIcon` (Task 15); `CloudUI.PetViewport`; `SoundFx.Play`.
- Produces:
  - `EggArt.New(parent, rarity, size) -> Frame "Egg_<Rarity>"` (width 0.8 x size), `EggArt.Halves(parent, rarity, size) -> top, bottom` (a zigzag edge), `EggArt.Glow(rarity) -> number` (Common 0, Uncommon 0, Rare 0.22, Epic 0.34, Legendary 0.58, Mythic 0.66, Secret 0.78), `EggArt.Tones(rarity) -> top, bottom` (the rarity colour 38% toward white / 28% toward black; Secret rgb(74,68,104) / rgb(18,16,28)); outline rgb(11,16,48); the weather mark of spec 5.6's table as a child `Mark`.
  - `EggStage.Init()`, `Show(result) -> boolean` (false for `Ok == false`: a toast with the reason, the stage stays shut), `Request(rouletteId, currency, spins) -> boolean` (the only `BuyRoulette` sender: `FIRE_GAP` 0.3 s, the pending flag, `WAIT_TIMEOUT` 7 s), `IsPending()`, `IsShowing()`, `Phase() -> "Strip" | "Land" | "Crack" | "Pop" | "Reveal" | nil`, `Skip()`, `Done()`, `Close()` (toasts the pulls not yet shown: "You hatched: a, b, c"), `Timings(fast) -> { Strip, Land, Crack, Pop }` (3.6 / 0.3 / 1.4 / 0.35, fast 1.1 / 0.15 / 0.5 / 0.25), `NoteText(pull, rarity) -> string`, `Layout() -> "PC" | "Phone" | "Portrait"`, `IsPrewarmed(petId)`; signals `Pending`, `Answered(result)`, `Opened`, `Closed`.
  - Instances: ScreenGui `NimbusHatch` (DisplayOrder 25, `IgnoreGuiInset = true`, `ResetOnSpawn = false`) > `Stage` (navy dim, full screen) > `Flash` (full screen) and `Content` (the laid-out area: full width, from under Roblox's top bar (the 58 px inset the windows use) to the bottom edge) > `Title`, `Strips` > `Strip1..3` > `Cell1..40`, `Pointer`, `Crack` > `Egg1..3`, `CrackWord`; `Reveal` > `Rays`, `Col1..3` > `Word`, `Shell`, `Pet`, `Name`, `New`, `Note`, `EvolvedRibbon`; `BottomBar` > `Skip`, `FastHatch`, `SpinAgain`, `Done`. (`Content` exists so the geometry check has one root that lies under the inset: `RedoGeom.check` includes its root and fails anything above y 58, and its `Skip` cannot exclude the root itself, so checking the full-screen `Stage` would always fail.)
  - Behaviour, copy, sizes, the layout rule (three anchors, the middle shrinks to 0.6, text never shrinks, x3 widths `canvasW - 20` / `(canvasW - 24) / 3`), the flash (rgb(242,182,68), 0.25 s in / 0.6 s out, Legendary and up), the sounds (`SpinStart`, `SpinTick`, `SpinLand`, `Shatter`, the `Reveal*` map; `Scale = 0.6` below Legendary) and Esc / gamepad B (gamepad B: `"NimbusHatchBack"` through ContextActionService at `Enum.ContextActionPriority.High.Value + 1`, above the shop's `High.Value` binding (Task 17) and the dash, bound only while the stage shows, always sinking the press; Esc: `UserInputService.InputBegan`, the pattern every window uses (MenuController, StoreController, PetsController), while the stage shows; the shop ignores Esc while `EggStage.IsShowing()`, Task 17, so one press never does both): exactly as spec 5.5.

- [ ] **Step 1: Failing tests**
  - `client_egg_art`: the seven eggs build at 30 / 104 / 160 / 380 px with a `Mark`; `Glow` and `Tones` per the Interfaces; `Halves` returns two frames covering the egg's height
  - `client_egg_stage` (1920x1080, the stage alone):
    - a Cloud x1 result (an Epic pull, `IsNew`, `PoolSize = 3`): `Phase()` goes Strip -> Land -> Crack -> Pop -> Reveal, Reveal at 5.65 +- 0.1 s; `CrackWord.Text == "EPIC EGG!"`, the reveal `Word.Text == "EPIC!"`, `Note.Text == "1 of 3 Epic pets \194\183 added to your pets"`, `New` visible
    - not new, `Count = 2` -> `"1 of 3 Epic pets \194\183 you have 2 " .. name .. " now"`; a substitute -> `"Stack full: +800 Tokens instead"`; `Pity = true` -> the note ends `" \194\183 guaranteed"`
    - Fast hatch on -> Reveal at 2.0 +- 0.1 s; `Skip` visible on the first frame; `Skip()` at t = 0 -> Reveal on the next frame; Esc during Strip skips; Esc on Reveal closes the stage; gamepad B: `Mock.BoundActions.NimbusHatchBack` exists only while the stage shows, with a priority above `Mock.BoundActions.NimbusDash`'s, and `Mock.TriggerAction("NimbusHatchBack", "Begin", Mock.NewInput("ButtonB", "Gamepad1", "Begin"))` skips during Strip, is DONE on Reveal and returns `Enum.ContextActionResult.Sink`
    - x3: three strips landing 0.25 s apart, three columns; `Flash` never visible when the best pull is Epic, visible once when it is Legendary
    - an evolved key -> `EvolvedRibbon` "Evolved" on the x1 reveal and on its x3 column; an old-shape result (no `Pulls`) plays as one pull; a pull with no `Strip` starts at Crack
    - `SpinAgain` -> one `BuyRoulette(id, currency, spins)` through `Request`; two `Request`s within 0.3 s -> one fire; a failure answer -> `IsPending() == false` at once, one toast with the reason, the stage not opened; a result arriving during a roll waits for DONE; no answer for 7 s -> `IsPending() == false` and a toast; a success after the timeout still plays
    - the `FastHatch` toggle -> one `SettingsSet("FastHatch", true)` 0.4 s later, and the next roll uses the fast timings
    - sounds (`SoundFx.Play` spied): an Epic roll plays `SpinStart`, `SpinTick`, `SpinLand`, `Shatter`, `RevealRare` with `Scale = 0.6`; a Legendary `RevealLegendary` with `Scale = 1`
    - census: no `"\226\151\134"` in `NimbusHatch`
  - `client_egg_stage_mobile` (mobile world): x1 and x3 reveals at 844x390, 640x360, 667x375, 360x640, 390x844, 1280x720, 1366x768: `RedoGeom.check(Stage.Content, label, { MinText = 15 (phones) / 14, NoOverlap = { "SpinAgain", "Done", "Skip", "FastHatch" }, Skip = { Rays = true, Flash = true } })` (the full-screen effect layers skipped; `Stage` and `Flash` themselves are not checked: they are meant to cover the whole screen), the three x3 pets inside the screen, the bottom bar above the bottom inset; resize mid-roll (Review Focus 1): an x3 started at 844x390, switched to 390x844 during Strip and to 1920x1080 on Reveal -> the check passes after each switch and the roll reaches Reveal
- [ ] **Step 2: Register** `if p5("smoke_egg_stage.lua"): client_files.append("smoke_egg_stage.lua"); ins(client_scenarios, "client_final", ["client_egg_art", "client_egg_stage"]); mobile_scenarios.append("client_egg_stage_mobile")  # [lobby-shop, Tasks 16-17] the eggs and the egg stage (smoke_egg_stage.lua)`
- [ ] **Step 3: Run** `--only client_egg_art,client_egg_stage,client_egg_stage_mobile` -> FAIL.
- [ ] **Step 4: Implement** EggArt, then EggStage.
- [ ] **Step 5: dump_gui** the seven scenes (`hatch:secret` = a forced Secret with the guaranteed note); render each at 844x390 and 1920x1080, and `hatch:reveal`, `hatch:reveal3` also at 640x360, 1280x720, 360x640, 390x844; look at them against `eggsA` / `eggSymbol("C", r)`.
- [ ] **Step 6: Run** the three plus `client_audio_keys,client_gui_dump,client_gem_icon,contract` -> PASS. EggStage <= 80, EggArt <= 30. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the egg stage: a strip of eggs, a crack and a pop; Skip from the first frame, x3, Fast hatch`

**Only Studio can judge:** the feel of the strip ease, the crack shake, the rays, the sounds at full and 0.6 volume, a forced Secret with dev gems.

### Task 17: The Cloud Shop window (Eggs tab) and the move out of MenuController

Spec: 5.4 (all but the Gems tab and the pulse), 5.5 "Queue and waits", 3.2 (MenuController's locals). Skills: roblox-dev:roblox-ui, roblox-dev:roblox-security (the client never decides a price or a roll).

**Files:**
- Create: `src/client/Controllers/ShopController.lua`
- Modify: `src/client/Controllers/MenuController.lua` (remove the shop, the stage and the odds; add the forwarder and the hooks, listed below; header API)
- Modify: `src/client/MouseLock.lua` (`WATCHERS`), `src/client/Main.client.lua` (`"ShopController"` after `"MenuController"`, and in `OPTIONAL`)
- Modify: `tools/dump_gui.lua` (scenes `shop`, `shop:restricted`; the `menu` scene's Shop path removed), `tools/render_gui.py` (`SCENARIOS`: `"menu:Shop"` -> `"shop"`, `"shop:restricted"`)
- Create: `tools/smoke_shop_ui.lua` (client worlds); Modify: `tools/smoke_egg_stage.lua` (`client_egg_stage_wiring`), `tools/smoke_gem_icon.lua` (the census gains the Eggs tab), `tools/smoke.py`, `tools/contract.json` (new entry `client/Controllers/ShopController`; the `MenuController` entry lists only `Init`, `Open`, `Close`, `OpenSettings`, `OpenTeam` and the `WindowOpened` signal, so nothing is removed there; `EggStage.IsPrewarmed` goes under the `client/UI/EggStage` entry Task 16 added, if it is not there yet)
- Modify (rewrite, keep names): `smoke_p2_ui.lua` (`client_p2ui`, `client_p2ui_mobile`: `GemRoulette_*` -> `NimbusShop` `ShopCard_*`), `smoke_p2_visual.lua` (`client_p2visual`), `smoke_release_client.lua` (`client_release_roulette`, `client_release_pets`, `client_release_touch_mobile`: `NimbusMenu.RouletteStage` -> `NimbusHatch`, `Window_Shop` -> `NimbusShop`, the Odds popup checks go, `MenuController.IsPrewarmed` -> `EggStage.IsPrewarmed` for the pulled pets), `smoke_client.lua` (the "every queued roulette result can be dismissed with Esc" check looks for `NimbusHatch.Stage`), `smoke_hud_pill.lua` (`client_hudpill`), `smoke_hud_items.lua` (`client_huditems_gone`), `smoke_p5_gui.lua` (`client_p5gui_cover`: the COVER entry for the shop reads `NimbusShop` / `Window_Shop`, `Centered = true`, `MaxCover` like `"pets"`), `smoke_p5_looks.lua` (`client_p5looks`: the old-shape result plays through EggStage, `EvolvedRibbon` looked up in `NimbusHatch`), `smoke_dgfix_mouse.lua` (`client_dgfix_mouse`: rows `shop` and `hatch` with mouse lock on), `smoke_client_v2.lua` (`client_menu`: `OpenPanel` Shop `Tab = "Roulettes"` -> the Eggs tab), `smoke_storm.lua` (`client_storm`: the Summon opens `NimbusShop` with `ShopCard_Secret` focused; its Odds popup checks become the card's odds rows), `smoke_bug2_tutset.lua` (the watcher list: `NimbusHatch` / `Stage`), `smoke_daily_ui.lua` (`client_daily_window`: closes the shop through `MenuController.Close()`), `smoke_audio.lua` (`client_audio_sites`: its old-shape `RouletteResult` now plays through EggStage, so the roulette block expects `SpinStart`, `SpinTick`, `SpinLand`, then `Shatter`, then the reveal by rarity with `Scale = 0.6` below Legendary)

**Interfaces:**
- Consumes: `EggStage` (Task 16); attributes `SecretPityLeft` (Task 5), `GemsSettled` (Task 3), `PaidRandomItemsRestricted` (today); `PetCatalog.GetRarityOdds` (Task 1); `GemIcon`, `EggArt`.
- Produces:
  - `ShopController.Init()` (calls `EggStage.Init()`; closes on `MenuController.WindowOpened` of any other id and on `InMatch`), `Open(args) -> boolean`, `Close()`, `IsOpen()`, `NormalizeTab(tab) -> "Eggs" | "Gems" | nil` (`roul*`, `egg*`, `item*` -> Eggs; `gem*` -> Gems), `Tab()`, `Layout() -> "PC" | "Phone" | "Portrait"`, `CardState(rouletteId) -> "Ready" | "Short" | "Locked" | "Loading" | "Pending" | "NoOdds"`, `Focused() -> rouletteId | nil`.
  - Open: the tab from `NormalizeTab(args.Tab)`; a `RouletteId` opens Eggs, scrolls that card fully into view (centred when the row scrolls) and outlines it gold for 2.6 s; `Currency` alone never switches tabs; refused in a match and while `EggStage.IsShowing()`; fires `MenuController.WindowOpened:Fire("Shop")`; `MenuController.SetColumnCovered(windowLeft, "Shop")`; `SetTouchHidden("Shop", on)` on a phone / touch device; `MouseLock.WatchVisible("Dock:Window_Shop", holder)`. While the stage shows the window hides; `EggStage.Closed` shows it again.
  - Esc / gamepad B / the red X close the window (spec 3.2). Today the shop is MenuController's Dock window, so `handleBack` closes it on Esc and the `"NimbusMenuBack"` action owns gamepad B; once the shop leaves MenuController (and `handleBack` loses its stage / odds branches, with no shop branch) nothing would close it and B would fall through to the dash. So ShopController owns both, in the StoreController shape (`H.syncBack` + its `InputBegan` Esc handler): `K.BACK_ACTION = "NimbusShopBack"`, bound with `ContextActionService:BindActionAtPriority(K.BACK_ACTION, fn, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)` only while the shop is open (unbound on close), its handler closing the shop on `Begin` and always returning `Sink` (so B does not dash); Esc through `UserInputService.InputBegan` while open. Both do nothing while `EggStage.IsShowing()` (the stage's own `"NimbusHatchBack"` sits at `High.Value + 1` and its Esc skips / closes the stage only, Task 16).
  - Window: ScreenGui `NimbusShop` (19, `IgnoreGuiInset = true`) > `Window_Shop` (UIScale `Fit`) > `Header` (`Title`, `Tab_Eggs`, `Tab_Gems`, `Balance_Gems` (a `GemIcon.Amount`), `Balance_Tokens`, `StoreButton`, `CloseButton`), `Body` > `EggsPage` > `Subtitle`, `FastHatch` (PC only), `Cards` (ScrollingFrame) > `ShopCard_<Id>` for Cloud, Storm, Sky, Celestial, Secret > `NamePlate`, `Machine`, `Odds` > `Odds_<Rarity>` (`Egg`, `Word`, `Pct`), `Spin`, `Spin3`, `SpinGems` (token machines) or `PityChip` (Secret), `Hint`, `NoOdds`; `Fade` (phone). `NeonKit.BigRect` with `RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1660, Y1 = 900 }`, `MARGIN = 12`, `PHONE_W = 900`, `SHORT = 560`, `PC_MIN_H = 600`, `PC_MAX_W = 0.87`; sizes, the fit rules and the portrait layout exactly as spec 5.4.
  - Buttons call `EggStage.Request`: `Spin` -> `(id, "Tokens", 1)` (Secret: `("Secret", "Gems", 1)`), `Spin3` -> `(id, "Tokens", 3)`, `SpinGems` -> `(id, "Gems", 1)`. States: Short (price kept, amount red, a tap shows today's "not enough" toast), Locked (gem button and the whole Secret card show the lock with today's texts), Loading (no `GemsSettled`: gem buttons and the Secret card read "Loading..."), Pending (`EggStage.IsPending()`: every spin button dimmed), NoOdds ("Odds unavailable", buttons inactive). `PityChip`: "Secret for sure in N" / "Secret for sure on the next spin" (N = 1) / phone "Secret in N" / "Loading..."; `Hint`: "Gems: same odds" / "Also at the Storm Altar"; `Subtitle`: "Every egg hatches a random pet of its rarity. The odds are on every machine."
  - MenuController after the change: **removed** `secretRoulette`, `findRoulette` and `possiblePetsOf` (if only the shop used them), `gemsOnlyBuckets`, `oddsOf`, `P2.gemAmount`, the Odds popup (`openOdds`, `closeOdds`, `Odds`, `K.Odds`), `buildRouletteCard`, `buildShop` and its Gems page, `focusCard`, the stage (`beginStage`, `closeStage`, `skipSpin`, `requestSpin`, `onRouletteResult`, `Spin`, its hook in `connectRemotes`), the strip pre-warm (`Warm.Roulette` and anything only it used), `MenuController.IsPrewarmed`, `K.Shop`, `createWindow({ Id = "Shop", ... })`. **Added** to `P5`: `P5.shop()` / `P5.hatch()` (lazy requires in the `P5.store` shape), `P5.openShop(args)` (refused in a match), `P5.closeShop()`, `P5.shopOpen()`, `P5.hatchShowing()`, `P5.closeHatch()`. `onOpenPanel` `"shop"` -> `P5.openShop(args)` with the whole args table; the Shop tile toggles it; `setActive("Shop", P5.shopOpen())`; `normalizeTab("Shop", t)` -> `ShopController.NormalizeTab(t)`; `closeEverything` also calls `P5.closeShop()` and `P5.closeHatch()`; `openWindow`, `P5.openPets`, `P5.openStore` and the Index open refuse while `P5.hatchShowing()`; `handleBack` loses its stage / odds branches (and gets no shop branch: the shop and the stage own their Esc / B, above); `syncBackBinding`'s `wanted` becomes `openId ~= nil` alone; `MenuController.IsOpen()` = `openId ~= nil or P5.petsOpen() or P5.shopOpen() or P5.hatchShowing()`; its own windows close on `WindowOpened("Shop")`.
  - `MouseLock` `WATCHERS`: `NimbusHatch = watchOverlays({ "Stage" })` replaces the `NimbusMenu` entry.

- [ ] **Step 1: Failing tests**
  - `client_shop_window` (1920x1080):
    - five cards in order at design x `44 + i * 318`, 300 x 736 (+-1); every card's `Odds_*` rows equal `PetCatalog.GetRarityOdds(id)` in order and value; `ShopCard_Secret` shows "85%" Mythic and "15%" Secret; `GetRarityOdds("Storm")` stubbed to `{}` and the shop reopened -> "Odds unavailable", its buttons inactive
    - prices from Config: `Spin` = the token price, `Spin3` = 3x, `SpinGems` = the gem price, the Secret `Spin` a GemIcon and the gem price; `SecretPityLeft = 3` -> "Secret for sure in 3", `1` -> "Secret for sure on the next spin", absent -> "Loading..."; restricted -> `SpinGems` and the Secret card locked with today's text; no `GemsSettled` -> "Loading..." on those
    - each button fires its `BuyRoulette` arguments once; while pending every card's `CardState == "Pending"`; a failure answer -> all re-enabled at once with a toast
    - `StoreButton` -> `StoreController.IsOpen()` and the shop closed; `WindowOpened` fired `"Shop"` once on open; `OpenPanel("Shop", { Tab = "Roulettes" })` -> Eggs; `OpenPanel("Shop", { RouletteId = "Secret", Currency = "Gems" })` -> Eggs with `ShopCard_Secret` fully inside the window and outlined, the outline gone after 2.6 s; `{ Currency = "Gems" }` alone keeps the tab
    - `MenuController.Close()` and `InMatch` close it; `MenuController.IsOpen()` is true while the shop or the stage shows; the tutorial card folds while it is open
    - Esc and gamepad B: Esc (`InputBegan` with `KeyCode.Escape`) closes the shop; `Mock.BoundActions.NimbusShopBack` exists only while the shop is open, with a priority above `Mock.BoundActions.NimbusDash`'s; `Mock.TriggerAction("NimbusShopBack", "Begin", Mock.NewInput("ButtonB", "Gamepad1", "Begin"))` closes the shop and returns `Enum.ContextActionResult.Sink` (so MovementController's dash never sees that press); after the close the action is unbound; while the stage shows, Esc and B leave the (hidden) shop open
  - `client_shop_sizes` (1280x720, 1366x768, 2560x1440): every card's odds, `Spin`, the x3 / gem row and `Hint` inside `Body`; 1280x720 scrolls sideways with 246 px cards (+-2); 1366x768 fits without scrolling
  - `client_shop_mobile` (mobile world: 844x390, 740x360, 667x375, 640x360): `Window_Shop` equals `NeonKit.BigRect` (820x330 at 844x390); `Cards` canvas 988 wide at 844x390 with `Fade` shown while more is to the right and hidden at the end; `RedoGeom.check(Window_Shop, label, { MinText = 15, MinTarget = 44, NoOverlap = { "Tab_Eggs", "Tab_Gems", "Balance_Gems", "Balance_Tokens", "StoreButton", "CloseButton" } })`; tab pills 92 x 44; `Spin3` / `SpinGems` 44 tall; every odds egg >= 30 px; `Spin3` reads "x3" + the token icon + `Theme.ShortNumber(3 * price)` (150, 750, 3,000, 15K); big balances (Review Focus 4): 12,345,678 gems and tokens -> the chips use `Theme.ShortNumber` and the check still passes; resize while open (Review Focus 1): 844x390 -> 390x844 -> 844x390 passes the check each time
  - `client_shop_portrait` (390x844, 360x640): two 50 px header rows (row 2: the tabs, both chips, the StoreButton), a vertical card list, the 2x2 odds grid with 30 px eggs, `RedoGeom.check` passes
  - `client_egg_stage_wiring` (1920x1080, the shop and the stage live): a card tap sends `BuyRoulette`; a success `RouletteResult` (`KC.toClient`) plays the stage and hides `Window_Shop`; DONE brings the shop back; Esc on the stage skips / closes it and the shop stays open; a card tap and SPIN AGAIN within 0.3 s send one request; a match start during the roll closes the stage and one toast lists the pulls not yet shown; Stats, Pets, Store and Index refuse to open while the stage shows; with mouse lock on the cursor is free over the shop and the reveal (`MouseLock` holds); close while pending (Review Focus 2), run once for each way of closing (the X, Esc, gamepad B through `NimbusShopBack`, and `InMatch` set then cleared): tap Spin, close the shop, reopen -> the cards stay Pending until the answer, a success then plays and a failure re-enables them, and with no answer they re-enable at 7 s (in the `InMatch` variant the test sends the answer after `InMatch` is cleared and the shop reopened)
- [ ] **Step 2: Register** `if p5("smoke_shop_ui.lua"): client_files.append("smoke_shop_ui.lua"); ins(client_scenarios, "client_final", ["client_shop_window", "client_shop_sizes"]); mobile_scenarios += ["client_shop_mobile", "client_shop_portrait"]  # [lobby-shop, Tasks 17-19] the Cloud Shop window (smoke_shop_ui.lua)`; add `"client_egg_stage_wiring"` to Task 16's line.
- [ ] **Step 3: Run** `--only client_shop_window,client_shop_sizes,client_shop_mobile,client_shop_portrait,client_egg_stage_wiring` -> FAIL.
- [ ] **Step 4: Implement** ShopController, then the MenuController surgery, MouseLock and the boot.
- [ ] **Step 5: Rewrite** the listed scenarios (same names, same intent).
- [ ] **Step 6: dump_gui** `shop` and `shop:restricted`; render at 844x390, 1920x1080, 640x360, 1280x720, 360x640, 390x844; look at them against `shopB("pc")` / `shopB("phone")`.
- [ ] **Step 7: Run** the five plus `client_egg_stage,client_gem_icon,client_p2ui,client_p2ui_mobile,client_p2visual,client_release_roulette,client_release_pets,client_release_touch_mobile,client_final,client_hudpill,client_huditems_gone,client_p5gui_cover,client_p5looks,client_dgfix_mouse,client_menu,client_pets,client_tb_pets_actions,client_store_bridge,client_storm,client_bug2tut_mouse,client_bug2tut_portrait,client_bug2tut_raidnext,client_daily_window,client_audio_sites,client_audio_keys,client_gui_dump,contract` -> PASS. MenuController < 160, ShopController <= 80, MouseLock 26. check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(lobby-shop): the Cloud Shop as one big card per machine with odds on every card; the shop and the stage leave MenuController`

**Only Studio can judge:** the shop and a full roll on PC and a phone, Fast hatch on and off, the gold focus from the altar's Summon.

### Task 18: The Gems tab

Spec: 5.4 "Gems tab, PC", "Gems tab, phone", 5.3 (the ribbons). Skills: roblox-dev:roblox-ui, roblox-dev:roblox-security (the client never prompts a purchase).

**Files:**
- Modify: `src/client/Controllers/ShopController.lua` (the Gems page)
- Modify: `tools/dump_gui.lua` (`shop:gems`), `tools/render_gui.py`, `tools/smoke_shop_ui.lua` (`client_shop_gems`), `tools/smoke_gem_icon.lua` (census: the Gems tab), `tools/smoke.py` (its line)

**Interfaces:**
- Consumes: `StoreRequest("Buy", "Gems" .. i)`, `StoreRequest("GemBuy", "XpPotionGems")` (Task 7); the `Robux` field and the new amounts (Task 8); attributes `XpPassState`, `XpBoostEnds`, `GemsSettled`, `StorePreview`; StoreController's product price reader (`GetProductInfo(...).PriceInRobux`).
- Produces:
  - `ShopController.PackRibbons(packs) -> { [i] = "+10%" | nil }` (pure: the gems-per-Robux bonus of each pack over pack 1, from the prices shown, whole percent; nil for pack 1 and for <= 0); `ShopController.PotionState() -> "Ready" | "Owned" | "Checking" | "Full" | "Loading" | "Short"`.
  - Instances: `GemsPage` > `GemHero` (`Pile`, `Title` "Gems", `Line1` "Spin the Secret Roulette and every machine with gems.", `Line2` "Chest: 1,500 gems = 1 Secret spin + 2 Celestial spins", `Buy`), `GemPack_1..4` (`Pile` 1 / 2 / 4 / 6, `Amount`, `Name` (the Config name as it is), `Ribbon`, `Best` "BEST VALUE" on pack 4, `Buy`), `GemPotion` (`Icon`, `Title` "XP Potion \194\183 30 minutes", `Text` "Your team earns double pet XP. Not random, so every account can buy it.", `Buy`). PC sizes from spec 5.4 (hero 1572 x 200 at (44, 12); tiles 379 x 380, gap 18; potion 1572 x 130; the body scrolls vertically when it does not fit); phone: five 188 x 262 tiles in the sideways row (phone potion "XP Potion" / "30 min \194\183 x2 pet XP"); portrait: the vertical list.
  - Pack `Buy`: product `Id > 0` -> the live `PriceInRobux`, one `StoreRequest("Buy", "Gems" .. i)` per tap; `Id == 0` -> the Config `Robux` on an inactive "Coming soon" button (with `StorePreview` it reads "PREVIEW" as the Store does). Potion `Buy`: `PotionState` "Owned" -> "You have x2 Pet XP", "Checking" -> "Checking your passes...", "Full" -> "Potion time is full" (`XpBoostEnds - now + 1800 > Config.Store.Potion.CapSeconds`), "Loading" -> "Loading...", "Short" -> GemIcon + "75" with the amount red; only "Ready" sends `GemBuy`.

- [ ] **Step 1: Failing test `client_shop_gems`** (1920x1080, then 844x390, then 390x844): four packs with the Config names and amounts "150" / "500" / "1,500" / "4,000"; ribbons nil / "+10%" / "+23%" / "+31%"; with `Products[4].Robux = 1999` the ribbon is recomputed (not typed); "BEST VALUE" on pack 4; `Id 0` -> "Coming soon" inactive; `Id 123` with a mocked `PriceInRobux` 59 -> the button shows 59 and one tap sends `StoreRequest("Buy", "Gems2")`; the hero's `Line2` text; every `PotionState` from its attributes with its label, and only "Ready" sends `GemBuy`; at 1280x720 the potion card is reachable inside `Body`; phone: five tiles, `RedoGeom.check` (text >= 15, targets >= 44); portrait: the vertical list passes the check; census: no `"\226\151\134"` on the Gems tab.
- [ ] **Step 2: Register** `"client_shop_gems"` on Task 17's line (client list).
- [ ] **Step 3: Run** `--only client_shop_gems` -> FAIL. **Step 4: Implement.**
- [ ] **Step 5: dump_gui `shop:gems`**; render at 844x390 and 1920x1080; look at it against `shopA("pc", "Gems")` and `packTile`.
- [ ] **Step 6: Run** `client_shop_gems,client_shop_window,client_shop_mobile,client_shop_portrait,client_gem_icon,client_store_window` -> PASS. ShopController <= 80. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the Cloud Shop's Gems tab: packs with honest bonus ribbons and the gem XP Potion`

### Task 19: The Store's Eggs tab and the pulsing Store button

Spec: 5.8 item 1, 5.4 "Header" (the pulse). Skills: roblox-dev:roblox-ui.

**Files:**
- Modify: `src/shared/Config.lua` (`Store.Tabs`: `"Roulettes"` -> `"Eggs"`), `src/client/UI/NeonKit.lua` (`Glyphs.Eggs = "\240\159\165\154"`), `src/client/Controllers/StoreController.lua` (`TAB_COLORS.Eggs = "Green"`; every `"Roulettes"` tab check -> `"Eggs"`; `Open` accepts `Tab = "Roulettes"` as an alias; the Eggs tab hops to `menu.Open("Shop", { Tab = "Eggs" })`; header), `src/shared/StoreCatalog.lua` (header), `src/client/Controllers/ShopController.lua` (the StoreButton pulse)
- Modify: `tools/contract.json` (the Store tabs list), `tools/dump_gui.lua` (new scene `store[:<Tab>]` = `StoreController.Open({ Tab = tab })`), `tools/render_gui.py` (`store`, `store:Eggs`, `store:Currency`), `tools/smoke_shop_ui.lua` (`client_shop_window` gains the pulse checks)
- Modify (rewrite, keep names): `smoke_store.lua` `store_config` (`Tabs[5] == "Eggs"`), `smoke_store_ui.lua` `client_store_window` (tap "Eggs"), `smoke_fixr_store_ui.lua` (the scenarios that tap the old tab)

**Interfaces:**
- Produces: `StoreController.Open({ Tab = "Roulettes" })` behaves as `Open({ Tab = "Eggs" })`; `Tab_Eggs` (the egg glyph, Green); ShopController `StoreButton` > UIScale `Pulse` tweening 1.00 <-> 1.05 over 1.2 s each way while the shop is open, stopped on close; with Gfx Low the scale stays 1 and a glow UIStroke `PulseGlow` shows instead.

- [ ] **Step 1: Failing tests** (in `client_shop_window` and the rewrites): over 2.4 s open, `Pulse.Scale` reaches >= 1.045 and <= 1.005; after Close it rests at 1 with no tween running; Gfx Low -> 1.00 throughout and `PulseGlow` visible; the Store has `Tab_Eggs` and no `Tab_Roulettes`; tapping it closes the Store and opens `NimbusShop` on Eggs; `StoreController.Open({ Tab = "Roulettes" })` does the same.
- [ ] **Step 2: Run** `--only client_shop_window,store_config,client_store_window` -> FAIL. **Step 3: Implement.** **Step 4: Rewrite** the listed scenarios.
- [ ] **Step 5: dump_gui `store`**; render `store`, `store:Eggs`, `store:Currency` at 844x390 and 1920x1080 (the gem piles and the new amounts); look at them.
- [ ] **Step 6: Run** `client_shop_window,store_config,store_catalog,client_store_window,client_store_states,client_store_bridge,client_store_mobile,client_fixr_store_colors,client_fixr_store_portrait,client_fixr_store_art,client_gui_dump,contract` -> PASS. StoreController <= 56, NeonKit <= 34. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the Store's Roulettes tab is now Eggs; the Cloud Shop's Store button pulses gently`

### Task 20: The board's SurfaceGui (LeaderboardController)

Spec: 5.10 "Client" (pages per section 15). Skills: roblox-dev:roblox-ui.

**Files:**
- Create: `src/client/Controllers/LeaderboardController.lua`
- Modify: `src/client/Main.client.lua` (boot after `"StoreController"`; `OPTIONAL`)
- Modify: `tools/robloxmock.lua` (client `Players:GetUserThumbnailAsync` if missing), `tools/dump_gui.lua` (`lobbyboard[:2|:3]`), `tools/render_gui.py`
- Create: `tools/smoke_lb_ui.lua` (client world)
- Modify: `tools/smoke.py`, `tools/contract.json` (`client/Controllers/LeaderboardController`: `Init`, `Page`, `SetPage`, `State`)

**Interfaces:**
- Consumes: `LeaderboardState` and `Config.Leaderboard` (Task 9); the `LobbyLeaderboard.Face` part (Task 11).
- Produces:
  - `LeaderboardController.Init()`, `Page() -> stat`, `SetPage(stat)` (the tap path; restarts the 15 s turn), `State() -> payload | nil`.
  - SurfaceGui `LobbyLeaderboard` in PlayerGui: `Adornee` = the workspace `LobbyLeaderboard.Face` (found by name; a newly built board re-adorns it), `Face = Front`, `SizingMode = PixelsPerStud`, `PixelsPerStud = 50` (800 x 650 px), `MaxDistance = 80`, `ResetOnSpawn = false`, `LightInfluence = 0` > `Board` > `Title` (50 px, `Config.Leaderboard.Titles[stat]`), `Tabs` > `Tab_<stat>` per `Pages` (TextButtons with `Labels`), `Scope` ("All players \194\183 all time" / "This server only"), `Rows` > `Row1..10` (`Rank`, `Head` 34 px ImageLabel, `Name`, `Value`; ranks 1-3 gold, silver, bronze), `YouRow` ("You \194\183 1,240 \194\183 #37" / "You \194\183 1,240 \194\183 not in the top 100" / "You \194\183 ..."), `Footer` ("Refreshes in m:ss \194\183 tap a tab, or it turns in 0:ss" from `NextAt` with `workspace:GetServerTimeNow()`), `Status` ("Loading scores..." / "No scores yet. Be the first!"). Every text >= 30 px; values with commas, `Theme.ShortNumber` from 1e6.
  - Headshots: `Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)` in a pcall'd task, cached per user (no `rbxthumb://` literal: check.mjs's asset-id rule).

- [ ] **Step 1: Failing test `client_leaderboard`**: before any state `Status` reads "Loading scores..."; the SurfaceGui is under PlayerGui with `Adornee` = the Face; a state with ten rows and `You = { Rank = 37, Value = 1240 }` fills `Row1..10` (top three coloured) and `YouRow` "You \194\183 1,240 \194\183 #37"; `Rank = nil` -> "not in the top 100"; `Value = nil` -> "You \194\183 ..."; Scope `"Server"` -> "This server only"; three tabs; `SetPage("Pets")` -> "TOP PETS FOUND"; the page turns by itself after 15 s, and a tap at 10 s moves the turn to 25 s; `NextAt = now + 220` -> the footer starts "Refreshes in 3:40"; an empty page -> "No scores yet. Be the first!"; every text >= 30 px; long names (Review Focus 4): a 20-character name and a value of 1e12 -> the name fits its box (`TextFits` or truncated), the value reads "1T", sizes unchanged; lobby rebuilt (Review Focus 3): destroy the board model and build a new one -> `Adornee` is the new Face within 1 s and the rows still show the last state.
- [ ] **Step 2: Register** `if p5("smoke_lb_ui.lua"): client_files.append("smoke_lb_ui.lua"); ins(client_scenarios, "client_final", ["client_leaderboard"])  # [lobby-shop, Task 20] the board's SurfaceGui (smoke_lb_ui.lua)`
- [ ] **Step 3: Run** -> FAIL. **Step 4: Implement.**
- [ ] **Step 5: dump_gui** `lobbyboard`, `lobbyboard:2`, `lobbyboard:3` (the board's canvas with ten fake rows); render at 844x390 and 1920x1080; look at them against `boardA`.
- [ ] **Step 6: Run** `client_leaderboard,client_polish_worldtext,client_gui_dump,contract` -> PASS. LeaderboardController <= 50. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the lobby board shows the global top 10 with tappable pages`

**Only Studio can judge:** the board's tabs tapped in the world on a phone and on PC; reading distance.

### Task 21: Lobby motion and the Join sign per player (LobbyFxController)

Spec: 5.12, 5.9 (the billboard hidden for a player who claimed). Skills: roblox-dev:roblox-performance.

**Files:**
- Create: `src/client/Controllers/LobbyFxController.lua`
- Modify: `src/client/Main.client.lua` (boot; `OPTIONAL`)
- Create: `tools/smoke_lobby_fx.lua` (client world)
- Modify: `tools/smoke.py`, `tools/contract.json` (`client/Controllers/LobbyFxController`: `Init`, `Step`, `Moving`)

**Interfaces:**
- Consumes: tags `Config.Tags.Spin` / `Config.Tags.Bob` and their attributes (Tasks 10, 13, 14); `Config.Attr.TroveGroupDone` (Task 10).
- Produces: `LobbyFxController.Init()`, `Step(dt)` (one frame; tests), `Moving() -> { inst... }` (the targets moved on the last step). One Heartbeat for all: `NC_Spin` turns a Model / Part about its built pivot's Y at 360 / `SpinSeconds` degrees a second and bobs it `BobStuds * sin(2 pi t / BobSeconds)` (from the built pivot, never accumulating); `NC_Bob` sets a BillboardGui's `StudsOffset.Y = base + BobStuds * sin(...)`; only targets within 150 studs of the camera; Gfx Low (the quality read `PortalFxController` uses) -> nothing moves and targets rest at their built pivot; any `JoinBillboard` gets `Enabled = false` while `LocalPlayer:GetAttribute(Config.Attr.TroveGroupDone) == true`, including one built after a rebuild.

- [ ] **Step 1: Failing test `client_lobby_fx`**: a tagged part 50 studs away turns (its Y angle changes) within 1 s and bobs within +-0.6; one 200 studs away stays put; Gfx Low -> nothing moves; a tagged BillboardGui's `StudsOffset.Y` varies within +-0.5 of its base; `TroveGroupDone` true -> `JoinBillboard.Enabled == false`, absent -> true; lobby rebuilt (Review Focus 3): destroy and re-create the trove (a new `JoinBillboard`) and a spin target -> the new billboard hidden for the done player, the new target moves, the old one leaves `Moving()`, no error.
- [ ] **Step 2: Register** `if p5("smoke_lobby_fx.lua"): client_files.append("smoke_lobby_fx.lua"); ins(client_scenarios, "client_final", ["client_lobby_fx"])  # [lobby-shop, Task 21] lobby motion (smoke_lobby_fx.lua)`
- [ ] **Step 3: Run** -> FAIL. **Step 4: Implement.**
- [ ] **Step 5: Run** `client_lobby_fx,client_trove,client_storm,contract` -> PASS. LobbyFxController <= 30. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): one client heartbeat spins the world gem and the altar ring and bobs the Join sign`

### Task 22: Blender: `portal_altar_ring`, and the mesh-key check

Spec: 5.11 (b) (the ring), 8 (`tools/mesh_keys.py`), 11 (renders before the gate). Skills: none from roblox-dev; the owner's Blender rules (`ABSOLUTE_RULES.md`, global CLAUDE.md "3D models: Blender only").

**Files:**
- Create: `tools/mesh_keys.py`
- Modify: `blender/kit/props/lobby_shop.py` (new `@prop("lobby_altar_ring")`; module docstring entry), `blender/catalog/lobby.json` (key `portal_altar_ring`, `"budget": "portal"`, a description; preview `lobby_portal_altar_ring`)
- Generated (commit with the kit change): `src/shared/MeshManifests/portal_altar_ring.lua`, `blender/meshes.json`

**Interfaces:**
- Consumes: Task 13's ring layout (pivot = the disc centre on the disc top; 16 segments at centre radius 6.0, 0.35 up, each about 2.47 x 0.5 x 0.3).
- Produces:
  - Key `portal_altar_ring`: 16 crystal-cyan Neon bars (rgb(63,200,255), the altar's `CrystalCore`) on that ring, each seated in a charcoal stone collar (the StormAltar `Stone*` palette of `SPAL`), bounds about 12.6 x 0.6 x 12.6, attachment `Center` at the pivot; Fixed parts, SmoothPlastic + baked shading, Neon only for the glow.
  - `py -3.12 tools/mesh_keys.py --check` (exit 1 on any problem): (a) every complete literal key in `Mesh.tag(<target>, "<key>"` across `src/**/*.lua` (not a prefix followed by `..`) has `src/shared/MeshManifests/<key>.lua`; (b) every key in `BUILD_KEYS` = `egg_common`, `egg_uncommon`, `egg_rare`, `egg_epic`, `egg_legendary`, `egg_mythic`, `egg_secret`, `gem_world`, `portal_ring`, `portal_altar_ring`, `prop_board_lb` appears as a string literal in some `src` Lua file; `RESERVED = { "gem_world_low" }` is skipped; each problem printed on its own line.

- [ ] **Step 1: Write `tools/mesh_keys.py`; run** `py -3.12 tools/mesh_keys.py --check` -> FAIL with exactly two problems: `portal_altar_ring` and `prop_board_lb` tagged in `src` without manifests.
- [ ] **Step 2: Write the prop and the catalog entry.**
- [ ] **Step 3: Build** `%USERPROFILE%\.bpyenv\Scripts\python.exe blender/build_all.py --key portal_altar_ring --preview` -> the manifest and `meshes.json` written, within the `portal` budget; `py -3.12 blender/kit/selftest.py` -> ok.
- [ ] **Step 4: Inspect.** In Blender through the `blender` MCP when it is connected (import `blender/out/portal_altar_ring.fbx`, render front, three-quarter, side and top beside a 5-stud reference); otherwise the kit preview plus `py -3.12 tools/render_model.py meshkey:portal_altar_ring -o <evidence>\blender\portal_altar_ring.png --views front,threequarter,side,top` and the `storm-altar` target to see it on the disc inside the rim. Check scale against the player, gaps, floating parts, normals and materials; fix and rebuild until it reads. Say in the ledger which way was used.
- [ ] **Step 5: Run** `py -3.12 tools/mesh_keys.py --check` -> FAIL with exactly one problem (`prop_board_lb`); `py -3.12 tools/mesh_names.py --check blender/out/portal_altar_ring.manifest.json` -> ok; `py -3.12 tools/mesh_budget.py` -> within budget; `py -3.12 tools/smoke.py --quick --mesh --only altar_portal_glow,storm_altar` -> PASS.
- [ ] **Step 6: Commit** `art(lobby-shop): the summon ring mesh (portal_altar_ring) and the mesh-key check`

### Task 23: Blender: `prop_board_lb`

Spec: 5.10 "World" (the board prop), 11. Skills: as Task 22.

**Files:**
- Modify: `blender/kit/props/lobby_shop.py` (new `@prop("lobby_board_lb")`; docstring), `blender/catalog/lobby.json` (key `prop_board_lb`, `"budget": "propBig"`; preview `lobby_prop_board_lb`)
- Generated: `src/shared/MeshManifests/prop_board_lb.lua`, `blender/meshes.json`

**Interfaces:**
- Consumes: Task 11's board layout (pivot = ground centre, front -Z; posts 1 x 17 x 1 at x +-8.9; a 0.6-stud frame around the 16 x 13 face centred 9.5 up; roof 18.6 x 0.6 x 2.4 at y 16.9 with a ridge).
- Produces: key `prop_board_lb`: two timber posts on stone footings, the frame (the face itself is NOT in the mesh: the game keeps the `Face` Part for the SurfaceGui), a small shingled roof, brass corner caps, wear on the post feet; the lobby's palette and fine-voxel family (`props/lobby.py` / `lobby_trove.py`); attachment `FaceCenter` at (0, 9.5, -0.2).

- [ ] **Step 1: Write the prop and the catalog entry.**
- [ ] **Step 2: Build** `%USERPROFILE%\.bpyenv\Scripts\python.exe blender/build_all.py --key prop_board_lb --preview`; `py -3.12 blender/kit/selftest.py` -> ok.
- [ ] **Step 3: Inspect** as Task 22 step 4 (`meshkey:prop_board_lb` and the `lobby` target: the board on the south lawn beside a 5-stud player, the face opening exactly 16 x 13).
- [ ] **Step 4: Run** `py -3.12 tools/mesh_keys.py --check` -> PASS; `py -3.12 tools/mesh_names.py --check blender/out/prop_board_lb.manifest.json` -> ok; `py -3.12 tools/mesh_budget.py` -> within budget; `py -3.12 tools/smoke.py --quick --mesh --only lb_world,client_leaderboard` -> PASS.
- [ ] **Step 5: Commit** `art(lobby-shop): the leaderboard board mesh (prop_board_lb)`

### Task 24: Docs, evidence and the gate

**Files:**
- Modify: `README.md` (the Cloud Shop and eggs, x3, Skip and Fast hatch, the Secret pity, the gem look, the gem XP Potion, the trove's spot, the leaderboard's three pages, the altar portals; the price tables are Task 8's), `BUILD_STATE.md` (one dated entry in "Player decisions" in the shape of the 2026-11-06 entries: branch, spec, plan, what landed, the calls of spec 13 and section 15, what only Studio can judge), `brain.md` (one dated decision line)
- Evidence: `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.superpowers\lobby-shop\evidence\`

- [ ] **Step 1: Docs.** Run `--only p2final_docs` and fix what it reports.
- [ ] **Step 2: Evidence renders:** `py -3.12 tools/render_gui.py <scene> --size 844x390 -o <evidence>\<scene>_phone.png` and `--size 1920x1080 ... _pc.png` for `shop`, `shop:gems`, `shop:restricted`, `hatch:strip`, `hatch:strip3`, `hatch:crack`, `hatch:reveal`, `hatch:reveal3`, `hatch:secret`, `store`, `store:Eggs`, `store:Currency`, `gems`, `eggs`, `lobbyboard`, `lobbyboard:2`, `lobbyboard:3`; `shop`, `hatch:reveal`, `hatch:reveal3` also at 640x360, 1280x720, 360x640, 390x844. Model renders (`tools/render_model.py`): `gem_world`, `portal_ring`, the seven `egg_<rarity>`, `portal_altar_ring`, `prop_board_lb`, several angles beside a 5-stud player. Look at every image: the reports' smallest text >= 14 px, targets >= 44 px, inside the screen and under the inset, no overlaps. List them in the ledger.
- [ ] **Step 3: Fast signal** (speed scout): `py -3.12 tools/smoke_parallel.py --quick --json <scratch>\par.json`; fix any failure in its owning task's files (commit as `fix(lobby-shop): ...`).
- [ ] **Step 4: The gate** (one run each, nothing else changing meanwhile): `py -3.12 tools/smoke.py --quick --json <scratch>\gate.json` -> 0 failed; `py -3.12 tools/smoke.py --quick --mesh` -> 0 failed; `node tools/check.mjs` -> 0 errors; `py -3.12 tools/count_locals.py` -> no file at 200 (report MenuController < 160, LobbyBuilder <= 159, DataService 160, HudController 161, PetService, ShopController, EggStage); `py -3.12 tools/sim_tycoon.py --check` -> ok and `--gems` -> its checks ok; `py -3.12 tools/mesh_budget.py`; `py -3.12 tools/mesh_names.py --check blender/out/*.manifest.json`; `py -3.12 tools/mesh_keys.py --check`.
- [ ] **Step 5: Commit** `gate(lobby-shop): eggs, Cloud Shop B, gems, trove, leaderboard, altar portals; whole smoke <passed> / 0 failed, --mesh <n> / 0, check.mjs 0 errors, sim_tycoon --check and --gems ok`, push, ledger line with the numbers and the evidence list. No merge.

**Only Studio can judge (spec 10, minus the Climb timing that section 15 dropped):** the lobby from the spawn on PC and a phone emulator (trove, board, Altar gate); walking the lawn paths; the board's tabs; the Join sign bobbing; the Cloud Shop and full rolls (x1, x3, Skip, Fast hatch, a forced Secret with dev gems); the beam, the summon ring and the return ring at night; the Altar's vortex beside the Obby's; live leaderboard reads after publish.

---

## Plan review (2026-11-07): findings applied

Twenty-two findings (several raised twice: the gui-redo pin, the full-stack rewrites, the `AllowSecret` guard, `egg_full_stack` vs the pity, the stand-in attribute). Each was checked against the code (gui-redo's copy for the shared files) and every one was real; all are folded into the tasks above. None was rejected outright. Taken in a different form than proposed, or one of two options chosen:
- **Pre-flight pin.** The findings said 7b4e07d. The check is 486d9fc (gui-redo's final gate, which contains 7b4e07d) plus `merge-base --is-ancestor gui-redo HEAD`, so a gui-redo that moves on again is caught too. Spec 3.1's HudController line is corrected in this plan's pre-flight, not in the spec (this pass edits the plan only).
- **`egg_full_stack` vs the pity.** Of the two options (count only natural pulls, or reset `Since` before each spin), the first: the natural-pull filter keeps the check exact before and after Task 5, and Task 5 adds the forced-pull checks the second option would have hidden.
- **Forced-strip check.** Its suggested setter `SetPity(p, s, s - 6)` does not work: `SetPity` never lowers `Hit`, and after a forced Secret `Hit == Spins`, so that call leaves `Since` at 0. It uses `SetPity(p, q.Spins + 6, q.Hit)` instead.
- **x3 independence.** The tolerance was widened to about 3 sigma (3.5 / 2 points). Raising the count to 10,000 requests while keeping 1.5 points was not taken: it is five times the run time for the same confidence.
- **Settle vs stand-in join.** The two findings agree that the attribute is absent right after `ProfileRebased`. Of their two endings (a further 15 s settle after the recovery, or the recovery read counting as the settle read), the second: the recovery read is already a fresh read rebased at 20 s or later, so another read would add a wait and a DataStore call for no added safety. This matches `gem_settle`'s "after the recovery succeeds -> true".
- **Return-ring clearance.** Of the three options (turn the ring along the bridge, measure from part centres, lower the minimum), the minimum was lowered to 4.25 on the rotated bounds. Turning the ring along the bridge puts its corner at exactly 4.5, a float-edge test. Measuring from centres would let a mesh reach into the lane. 4.32 still clears the 4-stud half lane.
- **Egg-stage geometry check.** Of the two options (check each container, or one `Content` frame), the `Content` frame: per-container checks fail on containers that are hidden in a phase or hold no text (`RedoGeom.check` requires the root to be shown and at least one text).
- **Lanes.** The shared `Config.Attr` hunk is removed up front by one Config commit, used only when the lanes really run in separate worktrees.
