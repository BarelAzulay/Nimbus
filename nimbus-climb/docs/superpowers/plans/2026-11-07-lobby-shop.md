# Lobby Shop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Also name and use superpowers:test-driven-development (every task is test first) and superpowers:verification-before-completion.

**Goal:** Turn every roulette spin into an egg roll (x1 / x3, Skip, Fast hatch, a Secret pity) shown as an egg-opening cutscene; put the Cloud Shop and the Robux Store into one Shop window with a tab rail (Eggs, Gems, Packs, Passes, Boosts) and a walk-up prompt; paint the eggs; set the owner's gem prices and odds; draw every gem as a cut gem; move the Sky Trove onto the plaza (spot C); add a global leaderboard with rank titles above the head; make the three altar portals stand up and light up.

**Architecture:** Server and data first (Tasks 1-9, built except Task 8): PetCatalog is the one odds source (the Secret Roulette included); PetService's money step is a batch that never refuses after the roll (x3 = one charge, engine-seeded `RollRng` / `StripRng`); the pity is a top-level profile field wired through every DataService touch point; gem-priced actions wait for a 15 s settle read; `StoreRequest("GemBuy")` sells the XP Potion; a LeaderboardService on OrderedDataStores. Then the world (Tasks 10-14, built): the trove on the plaza, LobbyBoardBuilder's Egg Guide and board, the Altar gate, the altar portals and the world gem; then `UI/GemIcon` (Task 15, built). **The rework (spec section 16, Tasks 16-31):** the owner's prices and odds as data (Celestial gets `AllowSecret`, so the existing guard needs no code change); the trove to spot C; titles inside LeaderboardService plus a TitleController; the egg stage core (`UI/EggArt`, `UI/EggStage`, the one request path); the Store moved into `ShopController` with a tab rail (a thin `StoreController` forwarder keeps every old caller); the Eggs tab and the Cloud Shop's exit from MenuController; the walk-up prompt; the board's PlayerGui SurfaceGui and one LobbyFx heartbeat; then the painted eggs with VFX and the GUI cutscene (`UI/HatchFx`), last among the client tasks; then the Blender props, docs, evidence and the gate.

**Tech Stack:** Luau in plain Lua 5.1 syntax, Rojo layout, the mock harness `py -3.12 tools/smoke.py` (lupa), `tools/dump_gui.lua` + `tools/render_gui.py`, `node tools/check.mjs`, `py -3.12 tools/count_locals.py`, `py -3.12 tools/sim_tycoon.py`, the Blender kit (`blender/build_all.py` under `%USERPROFILE%\.bpyenv\Scripts\python.exe`), `tools/render_model.py`.

**Spec:** `docs/superpowers/specs/2026-11-07-lobby-shop-design.md`. **Section 16 (the owner's pitch answers, 2026-11-07) overrides everything above it, section 15 included where they differ**; section 15 still holds for the board's Ring page, no Climb finish change and no session lock. Mock-ups: `Projects Main/Nimbus/.superpowers/lobby-shop/pitch/page.html` (functions `shopA(m, tab)`, `machCard`, `packTile`, `eggsA`, the egg pattern "A", `machSymbol`, `boardA`, `gateScene`, `chestMap`; design px at 844x390 and 1920x1080); cards `.superpowers/lobby-shop/pitch/CARDS.md`; ledger `.superpowers/lobby-shop/LEDGER.md`. Read the spec section each task names before starting it.

## How every task runs

- Worktree `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\lobby-shop\nimbus-climb`, branch `lobby-shop` (cut from bug-batch-6 09ac836). Paths have Hebrew characters: PowerShell `Set-Location -LiteralPath` / `-LiteralPath`, or `git -C`. Read `ABSOLUTE_RULES.md`, `brain.md` and the newest `BUILD_STATE.md` entry first.
- **Pre-flight (before Task 1):** the whole gui-redo branch must be merged in, its code-review round included: `git -C <worktree> merge-base --is-ancestor 486d9fc HEAD` exits 0 (gui-redo's final gate, which contains the review-fix commit 7b4e07d; the local tip 4a35b75 is that plus the bug-batch-6 merge lobby-shop already has), `git -C <worktree> merge-base --is-ancestor gui-redo HEAD` exits 0 (if gui-redo moved on after this plan, merge it again first), and `src/client/Controllers/TrainController.lua` exists. If not, stop: the build waits (spec 3.1). Every file gui-redo touched is edited (or read) in its merged form: DataService, PetService, FusionService, DailyService, Config, PetKeys, State, Main.client, FusionController, DailyController, CareController, TrainController, PetController, **HudController** (7b4e07d adds `HudController.SetVitalsHidden` and `S.vitalsOwners`; spec 3.1 wrongly lists HudController as untouched by gui-redo, this line corrects it), `UI/PetPicker`, dump_gui.lua, render_gui.py, smoke.py, contract.json, sim_tycoon.py, smoke_p5_gui / p5_looks / daily_ui / p2_visual and the `smoke_redo_*` files. This plan cites functions and anchors, not line numbers.
- **Pre-flight (before Task 16):** `git -C <worktree> merge-base --is-ancestor 1e733f7 HEAD` exits 0 (Tasks 1-7 and 9-15 built); read spec section 16 whole; the painted-egg Blender rebuild (exactly 12 files: `blender/kit/props/lobby_shop.py`, `blender/catalog/lobby.json`, `blender/meshes.json`, the seven `src/shared/MeshManifests/egg_*.lua`) has been committed **on its own by the main session** (review 2026-11-07: left in the tree it sits beside Tasks 16-27, where one broad `git add` would sweep it into an unrelated commit, and lane worktrees branched from the committed tip would not have it); then `git -C <worktree> status` is clean. If those files are still modified, stop and ask the main session (never discard or stash them).
- **Staging:** every task stages its own files by name (`git -C <worktree> add <path>...`), never `git add -A`, `git add .` or `git commit -a`.
- No Roblox Studio, no Rojo start / stop, no uploads, no merges into main, no MeshIds / TextureIds. Blender only in Tasks 28-30 (the repo kit; the `blender` MCP for inspection when it is connected). Do not touch other worktrees.
- Tests while building: `py -3.12 tools/smoke.py --quick --only <names>` with the names the task lists. Never the whole suite before Task 31 (this PC is short on memory: targeted `--only` runs only).
- Before each commit: `node tools/check.mjs` -> 0 errors, and `py -3.12 tools/count_locals.py <every Lua file the task grew>` -> under the task's cap.
- Commit message ends with exactly these two lines, then `git -C <worktree> push origin lobby-shop`:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01ACtM8qc8ts2NyGHrZh7vyT`
- After each push append one dated line to the Milestones of `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.superpowers\lobby-shop\LEDGER.md` (commit hash, what landed, the tests that passed). Evidence goes to `.superpowers\lobby-shop\evidence\` (outside the repo).
- A test a task's change breaks is rewritten to the new rule in the same task, never deleted; the commit body names each rewritten scenario and why.
- Every new smoke file is registered with one `p5(...)` line in `tools/smoke.py`, placed after the gui-redo lines (so `RedoGeom` from `smoke_redo_geom.lua` exists): server scenarios before `"shutdown"`, pure ones in `pure_scenarios` + before `"p5stats_formula"`, client ones before `"client_final"`, phone ones in `mobile_scenarios`. Later tasks extend the line their file was registered on.
- Route (`py -3.12 tools/pick_model.py --build game-feature --money --saves --many-systems`): Fable is out of credits, so every stage runs on **Opus 5.5**: build xhigh; review **max** for Tasks 2-9 and 16 (saves / money / security), Task 18 (server-written titles) and Tasks 21-22 (the shop move); xhigh elsewhere; ultracode at the gate (adversarial verification, completeness critic, loop until dry).
- Skills named in every builder prompt: superpowers:test-driven-development and superpowers:verification-before-completion; plus the task's own line.

## Global Constraints

- Section 15 (what still holds): board page 3 = Ring best (`Ring.Best`, title "TOP RING ROUND"); no Climb finish change, no `Match.MinFinishSeconds`, no `match_finish_clean`, no Wins store; no save session lock (the 15 s gem settle hold stays); gem prices unchanged by prestige. Its token packs are replaced by section 16.1 (1,500 / 7,500 / 30,000 Cloud Tokens at 49 / 149 / 399 R$).
- No change to the token prices (50 / 250 / 1,000 / 5,000), the Cloud / Storm / Sky odds, the pet pools, or free gem income (Daily, dungeons, arena, index, raids, prestige). Changed by the owner (spec 16.1, Task 16): Celestial's odds (Epic 43 / Legendary 40 / Mythic 15 / Secret 2, `AllowSecret = true`), the Secret Roulette (500 gems, Mythic 60 / Secret 40, the pity at 7 kept), every gem price, the gem and token packs, the potion (100 gems).
- No uploads: no MeshIds, TextureIds, image ids or new sounds. Every new mesh has a Part fallback; every GUI picture is frames + gradients; sounds are existing `AudioIds` keys through `SoundFx.Play`.
- Plain Lua 5.1 syntax; sources stay ASCII; non-ASCII UI text as UTF-8 byte escapes (`"\194\183"` middle dot, `"\240\159\165\154"` egg, `"\226\151\134"` is the old gem glyph that must vanish from the client UI).
- Readability (`Theme.Readability`): PC design text >= 18 px, phone text >= 15 px at scale 1, any on-screen text >= 14 px, tap targets >= 44 px, nothing under Roblox's top bar; screens 640x360 to 2560x1440 landscape and 360x640 / 390x844 portrait.
- World text >= 0.6 stud (30 px at 50 px per stud), the board's PlayerGui SurfaceGui included.
- DisplayOrders: `NimbusShop` 19 (the Store's `NimbusStore` renamed, Task 21) and new `NimbusHatch` 25 (both `IgnoreGuiInset = true`); existing Pets / Daily 19, NimbusMenu 20, Index 21, Fusion 22, Care / Arena / Train 23, PetPicker / LossScreen 24, Notify 30, Trove 18.
- Money: one non-yielding step (no `task.wait`, DataStore or remote call) from the checks to the last write; nothing refuses after the roll (one kept exception, before the charge: today's `AllowSecret` guard, a Secret pet rolled by a roulette without `AllowSecret` refuses the whole request "The roulette jammed, try again" with nothing charged; from Task 16 Celestial sets `AllowSecret`, Cloud / Storm / Sky do not); nothing that can fail runs after the charge; refresh / Sync / events / announce after it, each in pcall. No client-supplied number reaches a price, roll, count or leaderboard value.
- Saves: a new field is a new top-level field listed in `KNOWN_TOP`; a provisional (stand-in) profile never decides a one-time or money thing; `Pity` is left out while 0 / 0; `Settings.FastHatch` is stored only when true; no migration; old records load and save byte-identical until the player uses the new thing.
- Lobby light rule (`smoke_p5_world`): lamps in `Config.Sky.Lamps.Names` <= 1.2 brightness / 16 range, every other lobby light <= 1.5 / 28, no SpotLight / SurfaceLight. Storm Altar <= 500 parts (`tools/contract.json` `stormAltar`), trove <= 60 parts. The parts covered by the `prop_altar_portal` and `gate_altar` LayoutSig manifests are not changed.
- No near-miss tricks: Skip from the first frame, the strip is the server's strip, a card without odds cannot spin, odds on every card before paying.
- The gui-redo windows (Daily, Play time, Training Place, Fusion, the pet picker) are not redesigned. The server never animates.
- Top-level locals: DataService stays 160, MenuController drops under 160 (Task 22), LobbyBuilder <= 159 (154 at 1e733f7), HudController stays 161, PetService stays 80 (its cap is full: Task 23's prompt adds no top-level local), Main.server stays 58 (Task 18 adds a dep to an existing table). Per-file caps in each task.
- `check.mjs` asset-id rule: no `rbxassetid://` or `rbxthumb://` literal in `src` (headshots come from `Players:GetUserThumbnailAsync`).
- The cutscene never writes the Camera (type, subject, CFrame, FieldOfView) or the Humanoid and plays on through a death or respawn; its only world changes are one client-side `Lighting.NimbusHatchBlur` (BlurEffect) and the `LightingStack` preset `"Hatch"` (the tint; no ColorCorrectionEffect of its own, since LightingStack is the only client writer of Lighting), destroyed / popped by every exit; High graphics only (`GraphicsQuality` has Low and High, no Medium) (spec 16.4).
- Money: the Robux products that grant Tokens (`Tokens1..3`, `Pro`) are never prompted for an account whose `GemService.PolicyState` is not `"Allowed"`; a paid receipt is always granted (spec 16.1, Task 16).
- Titles: only the server writes `Title`, `TitleRank` and `leaderstats.Rank`; Creator comes only from `DevService.IsOwner` (the game's creator, or the group owner), never `Config.Dev.Admins`, Studio or a typed id (spec 16.6).
- Owner taste calls the pitch did not cover go to the ledger's "Questions for the morning" (spec 16.8 lists them). Gemini could not be asked when section 16 was written (ask-gemini answered 402: credits depleted); the main session runs the creative checks.

## Review Focus

1. The screen turning or resizing while the cutscene plays (mid-strip, mid-crack or on the reveal) or while the Shop is open (a phone rotating): everything re-lays out inside the screen and the roll still reaches its reveal -> `client_egg_stage_mobile` step "resize mid-roll" (Task 20, re-run dressed in Task 27) and `client_shop_mobile` step "resize while open" (Task 21).
2. The Shop closed (X, Esc, gamepad B, a match) while a spin request is pending, then reopened: the cards must not stay dimmed forever, the late answer still plays (or re-enables with its reason), the 7 s timeout still frees them -> `client_egg_stage_wiring` step "close while pending", run once per way of closing (Task 22).
3. The cutscene cut short (a match start, an error inside a phase, `MenuController.Close()`) or living through a respawn (the character removed: it plays on to the reveal): the Camera, the Humanoid, the cursor, the touch controls and `Lighting` (no `NimbusHatchBlur` left, no `"Hatch"` LightingStack preset), the spark Heartbeat and every tween end as they began; the Shop comes back only after DONE or an error and stays closed after a match start or `MenuController.Close()` -> `client_hatch_cutscene` step "never breaks the player" (Task 27; the plain core's version in `client_egg_stage`, Task 20).
4. The lobby rebuilt while players are in it (a dev reset or a rebuild): the board's SurfaceGui re-adorns to the new Face, the Join sign stays hidden for a player who claimed, new spin / bob targets (the shelf eggs included) move and old ones drop out, exactly one walk-up `ShopPrompt` on the new Egg Guide -> `client_leaderboard` step "lobby rebuilt" (Task 24), `client_lobby_fx` step "lobby rebuilt" (Task 25), `shop_prompt` step "lobby rebuilt" (Task 23).
5. Titles under churn: a rank moving 3 -> 12 -> out over successive reads, a player leaving mid-refresh, the owner's group check failing then answering, a respawn: no stale tag, no write without a change, no error -> `lb_titles` (Task 18) and `client_titles` steps "respawn" and "attribute cleared" (Task 19).
6. Long names and huge numbers (a 20-character display name, a 1e12 value, an 8-digit gem balance): never overflow a row or chip, never shrink text under its floor -> `client_leaderboard` step "long names" (Task 24) and `client_shop_mobile` step "big balances" (Task 21).
7. Gem icons destroyed and rebuilt in bulk (HUD relayouts, windows rebuilding cards): the shared shine driver drops dead icons, never errors and never grows -> `client_gem_icon` step "churn" (Task 15, built; re-run in Tasks 21 and 22).

## File map

| File | Tasks | Change |
|---|---|---|
| `src/shared/Config.lua` | 1-7, 9-10 built; 16, 18, 21, 26 | built: `Eggs`, `Gems.SecretRoulette.PityAt` / `SettleSeconds`, `Store.GemItems`, `Leaderboard`, the `Attr` / `Tags` keys, `LeaderboardState`; 16: Celestial odds + `AllowSecret`, gem prices, the Secret Roulette, `Gems.Products` (+ `Robux`), token packs, the potion; 18: `Attr.Title`, `Attr.TitleRank`, `Leaderboard.RankTitles`; 21: `Store.Tabs`, the token / Cash items' `Tab`; 26: `Eggs.ChatColors` |
| `src/shared/PetCatalog.lua`, `src/shared/Util.lua`, `src/server/Services/GemService.lua` | 1 built; 16 (headers) | the one odds source; no code change in the rework |
| `src/server/Services/DataService.lua`, `FusionService.lua` | 2, 3 built | the pity field, the settle read |
| `src/server/Services/PetService.lua` | 4-6 built; 16 (header), 23 | the batch; the `ShopPrompt` |
| `src/server/Services/StoreService.lua`, `src/shared/StoreCatalog.lua` | 7 built; 16, 21 | `GemBuy`; `gemItem` `Robux`; the token-grant lock in `PromptPurchase` (16); `Tab = "Gems"`, `GEM_HERO_INDEX` 3 |
| `src/shared/TycoonCatalog.lua`, `tools/sim_tycoon.py`, `README.md` | 16, 31 | Mix 40 / 100; the saved Task 8 sim patch with the owner's numbers and 7 odds columns; tables |
| `src/client/Controllers/IndexController.lua` | 16 | the Secret pet line |
| `src/server/Services/LeaderboardService.lua`, `DevService.lua`, `PlayerService.lua`, `src/server/Main.server.lua` | 9 built; 18 | titles, `IsOwner`, `leaderstats.Rank`, the `DevService` dep |
| `src/server/Services/LobbyBuilder.lua`, `LobbyBoardBuilder.lua`, `TroveService.lua` | 10-12 built; 17, 23, 25, 26 | `G.Trove` 165 / 50; `Counter`, the arch caption; the Egg Guide's `PromptPart`, `NC_Spin`, sparkles, `EggShelfGlow` |
| `src/shared/WorldStyle.lua`, `src/client/PortalVortex.lua`, `src/server/Services/StormAltar.lua` | 12-14 built | the gate, the portals, the world gem |
| `src/client/UI/GemIcon.lua`, `NeonKit`, `HudController`, `ArenaController`, `DungeonController`, `FusionController` | 15 built; 21 (`NeonKit.Glyphs.Eggs`) | gem art everywhere |
| `src/client/Controllers/TitleController.lua` (new), `VipController.lua` | 19 | the title tag, the crown height |
| `src/client/UI/EggArt.lua`, `EggStage.lua`, `HatchFx.lua` (new) | 20, 26, 27 | eggs; the stage core; the paint and VFX; the cutscene |
| `src/client/Controllers/ShopController.lua` (moved from `StoreController.lua`), `StoreController.lua` (new forwarder), `src/client/UI/ShopGems.lua`, `ShopEggs.lua` (new) | 21, 22, 26 | the Shop window A |
| `src/client/Controllers/MenuController.lua`, `src/client/MouseLock.lua` | 21 (Store forwarding), 22 (the Cloud Shop and stage leave) | |
| `src/client/Controllers/TopBarController.lua`, `PetsController.lua` | 23 | openers (`TutorialController` unchanged: spec 16.3 "Tutorial") |
| `src/client/Controllers/NotifyController.lua` | 6 built; 26 | kind `"pull"` -> system chat; Secret's colour |
| `src/client/ClientSettings.lua`, `src/client/State.lua` | 2 built | `FastHatch` |
| `src/client/Controllers/LeaderboardController.lua`, `LobbyFxController.lua` (new) | 24, 25 | board client, lobby motion |
| `src/client/Main.client.lua` | 19, 21, 24, 25 | boot lines |
| `blender/kit/props/lobby_shop.py`, `blender/catalog/lobby.json`, `src/shared/MeshManifests/*`, `blender/meshes.json`, `tools/mesh_keys.py` (new) | 28-30 | the painted eggs, `portal_altar_ring`, `prop_board_lb`, the key check |
| `tools/check.mjs` | 21 | the store card-art joiner is `ShopController.lua` |
| `tools/robloxmock.lua` | 6, 9 built; 18, 24, 27 | owner / group mocks, client thumbnails, `Lighting` effects and Camera reads |
| `tools/smoke_*.lua` (new in the rework: titles, egg_stage, shop_ui, lb_ui, lobby_fx), `tools/smoke.py`, `tools/contract.json`, `tools/dump_gui.lua`, `tools/render_gui.py` | all | tests, registration, scenes |

## Lanes (speed scout)

Tasks 1-7 and 9-15 are built on `lobby-shop` (1e733f7). The rework runs in order in one worktree; to run lanes side by side, each lane works in its own worktree `Projects Main\Nimbus\.worktrees\lobby-shop-<lane>` branched from `lobby-shop` and merges back at each join. Lane S (server): 16, 18. Lane W (world): 17, then 23 (after 22), 25. Lane C (client): 19, 20, 21, 22, 24, 26, 27. Lane B (Blender): 28, 29, 30. Files shared across lanes: `Config.lua` (16, 18, 21, 26: separate tables, merge by hand), `StoreCatalog.lua` (16 then 21), `LobbyBoardBuilder.lua` (23, then 25, then 26), `Main.client.lua` (19, 21, 24, 25: one boot line each), the registration lines in `smoke.py` / `contract.json`. Joins: 19 needs 18; 21 needs 16; 22 needs 20, 21; 23 needs 17, 22; 25 needs 23; 26 needs 22, 25 and the painted-egg rebuild committed (the Task 16 pre-flight; if it is not, Task 26 runs in the `lobby-shop` worktree itself, not in lane C: a lane branches from the committed tip and `blender/out` is git-ignored, so a lane would compare the GUI eggs with the old ones); 27 needs 26; 28 needs 26 (the paint table); 30's `--mesh` run needs 24; 31 last.

---

### Task 1: Eggs and one odds source (BUILT cbf4fe1)

> Reworked by Task 16: the Secret Roulette rows (60 / 40) and Celestial's Secret row in `egg_roll_pure`.

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

### Task 2: The pity field and the Fast hatch setting (data) (BUILT 3114a7c)

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

### Task 3: The gem settle hold (BUILT f649828)

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

### Task 4: BuyRoulette x1 / x3: one money step that never refuses after the roll (BUILT 19a047c)

> Reworked by Task 16: `egg_full_stack` at Secret 40%.

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

### Task 5: The Secret pity (BUILT c08fbe2)

> Reworked by Task 16: `secret_pity` at Mythic 60 / Secret 40.

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

### Task 6: One announcement per request, Legendary and up, as a chat line (BUILT 571ca97)

> Reworked by Task 26: Secret's chat colour (`Config.Eggs.ChatColors`).

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

### Task 7: `StoreRequest("GemBuy")`: the gem XP Potion (BUILT 78f02b4)

> Reworked by Task 16: the potion costs 100 gems.

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

### Task 8: Gem prices, gem packs and token packs (NOT BUILT: stopped at its pre-flight, replaced by Task 16)

> Do not build. Its numbers (gem prices B) were never final; the owner's prices are Task 16, which reuses this task's saved sim patch (`.superpowers/lobby-shop/evidence/task8/sim_tycoon_gems_step1.patch`).

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

### Task 9: LeaderboardService (BUILT bd9731d)

> Task 18 adds the titles to LeaderboardService.

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

### Task 10: The trove on the plaza, its Join sign, the Egg Guide (BUILT c08288c)

> Reworked by Task 17 (the trove to spot C), Task 23 (the Egg Guide's prompt), Tasks 25-26 (the shelf turntable and sparkles).

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

### Task 11: The leaderboard board in the world (BUILT 4855621)

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

### Task 12: The Storm Altar gate on the plaza (portal a) (BUILT a611b40)

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

### Task 13: The summon glow and the standing return ring (portals b and c) (BUILT 25e51c2 + 53778b9)

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

### Task 14: The world gem on the altar deck (BUILT 01cb5b3)

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

### Task 15: GemIcon and the gem glyph swap (BUILT 1e733f7)

> Task 21 moves `StoreController.lua` to `ShopController.lua` (its gem art goes with it); GemIcon is unchanged.

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

### Task 16: The owner's prices and odds (gemprice A with changes; replaces Task 8)

Spec: 16.1 (all of it); 5.2 (the pity, unchanged in code). Section 15's token packs and Task 8's numbers are void. Skills: roblox-dev:roblox-security (prices and odds are money).

**Files:**
- Modify: `src/shared/Config.lua` (`Roulettes` Celestial row: `AllowSecret = true`, `Odds = { Epic = 43, Legendary = 40, Mythic = 15, Secret = 2 }` and its comment; `Gems.RouletteGemPrices`; `Gems.SecretRoulette.GemPrice` / `Odds`; `Gems.Products` amounts + a `Robux` field; `Store.Items` Tokens1..3 `Grants.Tokens` + `Name`; `Store.GemItems[1].Gems`)
- Modify: `src/shared/TycoonCatalog.lua` (`Fusion.Mix` Mythic / Secret)
- Modify: `src/shared/StoreCatalog.lua` (`gemItem` copies `Robux`; header)
- Modify: `src/server/Services/StoreService.lua` (`PromptPurchase`: a Product whose `Grants.Tokens > 0` (`Tokens1..3`, `Pro`) is refused before the prompt unless `GemService.PolicyState(player) == "Allowed"`: "Token packs are not available on your account" when Restricted, "Checking your account, try again in a moment" otherwise (kick the policy check as `GemService.Quote` does; no GemService answer counts as unknown); `GemService` through a lazy require or an `Init` dep; the grant path untouched, so a paid receipt is always granted; header)
- Modify (headers and one string, no logic): `src/shared/PetCatalog.lua` (header, the `IsRollable` / `rarityAllowed` comments), `src/server/Services/PetService.lua` and `src/server/Services/GemService.lua` (headers: Secret pets from the Secret Roulette and Celestial's 2%), `src/client/Controllers/IndexController.lua` (the undiscovered Secret line)
- Modify: `tools/sim_tycoon.py`: first `git -C "C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\lobby-shop" apply "C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.superpowers\lobby-shop\evidence\task8\sim_tycoon_gems_step1.patch"` (checked clean on 2026-11-07; run it from the repo root, not from `nimbus-climb`), then the owner's numbers; `README.md` (the gem section, the product table, the roulette table)
- Modify: `tools/smoke_gem_prices.lua` (new scenario `gem_prices`), `tools/smoke_eggs.lua` (new scenario `celestial_secret`), `tools/smoke_store.lua` (new scenario `store_token_lock`), `tools/smoke.py` (the `smoke_eggs.lua`, `smoke_gem_prices.lua` and `smoke_store.lua` lines)
- Rewrite (keep names; built tests marked): `smoke_eggs.lua` `egg_roll_pure` (Task 1: the Secret Roulette rows 0.60 / 0.40; Celestial's rows gain Secret 0.02) and `egg_full_stack` (Task 4: natural Secret share 40% +-3, all pulls 41.2% +-3); `smoke_pity.lua` `secret_pity` (Task 5: the forced-strip filler share 40% +-3; every steering stub re-checked against 60 / 40) and `gem_settle` part 3 (Task 3: the price read from Config); `smoke_gem_prices.lua` `gem_potion_buy` (Task 7: 100 gems, "one gem short" at 99); `smoke_p2_gems.lua` `p2gems_odds` (the `def.AllowSecret == false` line becomes "equals its Config row"; the 1,500-roll leak test: no Secret from Cloud / Storm / Sky, Celestial inside 0.9-3.1%) and `p2gems_roulettes` (prices; the guard test stays on Cloud); `smoke_storm.lua` `storm_pet` ("no current roulette offers Stormfang" becomes "Celestial offers it at its Secret share and `IsRollable` is true"); `smoke_p2_flow.lua` (the `p2flow_*` price lines); `smoke_store.lua` `store_catalog` / `store_config` (token amounts and names, the gem items' `Robux`); `smoke_p4_economy.lua` `p2_economy` (the sim names; its three `for i = 1, 6` loops, the `PET_ROLLABLE` / `PET_ECON_ROLLABLE` counts and the `ODDS_<roulette>` rows, become `for i = 1, #RARITY_ORDER` (7), and the tally label reads "Common .. Secret": the 7-entry sim lists fail `listEq` against 6-entry expectations); `smoke_p2_final.lua` `p2final_docs` (README vs Config); `smoke_content.lua` `catalog` / `config_shape` (any price pin; its `AllowSecret` branch already handles Celestial)

**Interfaces:**
- Produces:
  - `Config.Gems.RouletteGemPrices = { Cloud = 20, Storm = 40, Sky = 60, Celestial = 180 }`; `SecretRoulette.GemPrice = 500`, `Odds = { Mythic = 60, Secret = 40 }`, `PityAt = 7` (kept); `Gems.Products` = `{ Id = 0, Gems = 200, Robux = 49, Name = "Pouch of Gems" }`, `{ 0, 670, 149, "Bag of Gems" }`, `{ 0, 1950, 399, "Chest of Gems" }`, `{ 0, 5300, 999, "Vault of Gems" }` (names as in Config today); Tokens1 / 2 / 3 `Grants.Tokens = 1500 / 7500 / 30000`, `Name = "1,500 Cloud Tokens" / "7,500 Cloud Tokens" / "30,000 Cloud Tokens"` (Robux 49 / 149 / 399 kept); `Store.GemItems[1].Gems = 100`; `Fusion.Mix.Mythic = { Gems = 40 }`, `Secret = { Gems = 100 }`; `StoreCatalog.List()` gem items carry `Robux`.
  - Celestial's Secret through data only: PetService's guard and GemService's quote already read the roulette's own `AllowSecret` (spec 16.1), so Cloud / Storm / Sky still refuse a rolled Secret before the charge and Celestial grants it (token and gem, x1 and x3). A Celestial Secret never touches `Pity.Secret`.
  - IndexController's line: "A Secret pet. Summon it at the Storm Altar, or hatch it from the Celestial Roulette."
  - The token-grant lock (spec 16.1, review 2026-11-07, closing 13 call 8): `StoreService.PromptPurchase` refuses `Tokens1..3` and `Pro` (every Product with `Grants.Tokens > 0`) for a not-"Allowed" account before any prompt; earned tokens still spin; paid receipts are always granted.
  - sim: `GEM_SPIN = [20, 40, 60, 180]`, `GEM_SECRET = 500`, `SECRET_PITY = 7`, `GEM_MIX = [40, 100]`, `GEM_POTION = 100`, `GEM_PACKS = [200, 670, 1950, 5300]`, `PACK_ROBUX = [49, 149, 399, 999]`, `TOKEN_PACKS = [1500, 7500, 30000]`; `ODDS_Cloud .. ODDS_Celestial`, `PET_ROLLABLE` and `PET_ECON_ROLLABLE` with 7 entries (Common .. Secret; `ODDS_Celestial = [0, 0, 0, 43, 40, 15, 2]`, `PET_ROLLABLE = [6, 6, 5, 3, 4, 2, 4]`, `PET_ECON_ROLLABLE = [3, 3, 3, 1, 2, 1, 1]`: `roll()` reads both at the same index, Phantom Kitsune is the one Economy pet among the four rollable Secret pets, and a 6-entry list raises IndexError on the first Celestial Secret), the roll over all seven, `--check` comparing all seven and every constant above with Config / TycoonCatalog (`same(...)`). `--gems` checks: gems per Secret pet = `GEM_SECRET * (1 - (1 - p)^PITY) / p` with `p` from Config = 1,215 +- 1; pack gems per Robux strictly rising; the Chest line (3 Secret + 2 Celestial spins) equals `floor(1950 / 500)` and `floor((1950 - 3 * 500) / 180)`; `PACK_ROBUX` equals the Config `Robux` fields. The patch's `GEM_SECRET_DAYS (12, 25)` check and its "399 R$ = 1 Secret + 2 Celestial" check are removed: days per spin are printed, never a stop (the owner's numbers are final).

- [ ] **Step 1: The sim.** Apply the patch, set the constants and the 7 columns, replace the two removed checks; `py -3.12 tools/sim_tycoon.py --gems` prints both players (expect about 18.2 days per Secret spin for the never-prestiging regular, 60 for the casual, 5 hours of play prestiging; paste the real lines into the ledger); `--check` lists the Config differences (Config not changed yet).
- [ ] **Step 2: Failing tests**
  - `gem_prices` (booted, settled, allowed account): every number in Interfaces read from Config / TycoonCatalog / StoreCatalog (`List()` gem items' `Gems` and `Robux`, Tokens1..3 `Grants` and `Name`); `GemService.Quote` prices 20 / 40 / 60 / 180 / 500; a Mythic Mix with gems charges 40 and a Secret Mix 100; the XP Potion 100.
  - `store_token_lock` (booted; `Id > 0` set on the items inside the test and restored): `GemService.PolicyState` stubbed `"Restricted"` -> `StoreRequest("Buy", "Tokens1" | "Tokens2" | "Tokens3" | "Pro")` each answers "Token packs are not available on your account" and calls no `PromptProductPurchase`; stubbed unknown -> "Checking your account, try again in a moment", no prompt; `"Allowed"` -> one prompt each; `Starter`, `VIP`, `XpPotion1` and the gem packs are prompted whatever the state; a paid `Tokens1` receipt for a Restricted account still grants 1,500 tokens.
  - `celestial_secret` (booted): with `RNG.Roll` steered to Celestial's Secret row, a token x1, a token x3 and a gem x1 Celestial request each grant a Secret pet (never "The roulette jammed"), charge once, leave `Pity.Secret` unchanged and send the Legendary-and-up chat line; the same steering on Cloud, Storm and Sky refuses before the charge; with all four Secret pets full the substitute pays `Config.Index.Rewards.Secret.Tokens`; 20,000 seeded `PetCatalog.RollPet("Celestial")` give Secret 2% +- 0.3 points; `PetCatalog.GetRarityOdds("Celestial")` ends with Secret 0.02 and `PossiblePets("Celestial")` lists the four rollable Secret pets.
- [ ] **Step 3: Register** `"gem_prices"` on the `smoke_gem_prices.lua` line, `"celestial_secret"` in that line's server list on the `smoke_eggs.lua` line and `"store_token_lock"` on the `smoke_store.lua` line (server scenarios, before `"shutdown"`). **Run** `--only gem_prices,celestial_secret,store_token_lock` -> FAIL.
- [ ] **Step 4: Implement** Config, TycoonCatalog, `gemItem`, the StoreService token-grant lock, the headers and the Index line.
- [ ] **Step 5: README** tables rewritten from Config until `p2final_docs` passes.
- [ ] **Step 6: Rewrite** the listed scenarios (the commit body names each and why).
- [ ] **Step 7: Run** `gem_prices,celestial_secret,store_token_lock,egg_roll_pure,egg_spin_x1,egg_spin_x3,egg_full_stack,egg_strip,egg_announce,secret_pity,secret_pity_save,gem_settle,gem_potion_buy,p2gems_roulettes,p2gems_odds,p2gems_altar,storm_pet,p2flow_arrive,p2flow_build,p2flow_fusion_gems,p2flow_prestige,p2flow_rejoin,store_catalog,store_config,store_router,p2_economy,p2final_docs,catalog,config_shape,client_store_window,client_fixr_store_art` -> PASS (if a name above does not exist, `grep` its file and run the scenario it was renamed to); `py -3.12 tools/sim_tycoon.py --check` -> ok; `--gems` -> its checks ok. PetService stays 80, GemService and PetCatalog unchanged in locals, StoreService <= 48 (47 at 1e733f7). check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(lobby-shop): the owner's prices: gem spins 20/40/60/180, Secret Roulette 500 at Mythic 60 / Secret 40, Celestial 2% Secret, Mix 40/100, potion 100, gem packs 200-5,300, token packs 1,500-30,000`

### Task 17: The Sky Trove to spot C

Spec: 16.2. Skills: roblox-dev:roblox-architecture.

**Files:**
- Modify: `src/server/Services/LobbyBuilder.lua` (`G.Trove = { Angle = 165, R = 50, Clear = 6.5 }`; nothing else: `Build` already places it once with `plazaSpot` before `buildPlaza` and faces it with `faceCentre`)
- Rewrite (keep names; built tests): `smoke_lobby_shop_world.lua` `lobby_trove_plaza` (Task 10) and `smoke_trove.lua` `trove_build` (Task 10)

**Interfaces:**
- Produces: the `SkyTrove` centre at plaza-local (-48.30, 12.94) (polar 165 degrees, r 50 from `Config.Lobby.Origin`), facing the plaza centre; sign post still at local x -6.2; Join sign, prompt, `fallbackShop` trove and `LobbyInfo.Shop.ItemShop` unchanged.

- [ ] **Step 1: Rewrite the tests first** (red): `lobby_trove_plaza` and `trove_build` expect 165 degrees, r 50 (+-0.5), facing the centre (dot > 0.99); the neighbour distances of spec 16.2 (Guide board >= 12.5, both west benches >= 10 and within 0.5 of each other, NPC spot 160 >= 11.5, flower beds >= 10.5, the west cross walk's centre line >= 11.5, the spawn court >= 42.5); the `Sign` post's footing >= 0.5 stud outside the west walk (the 180-degree cross walk, half width 5); no "plaza decor skipped" warn on the normal and the forced-fallback build.
- [ ] **Step 2: Run** `--only lobby_trove_plaza,trove_build` -> FAIL.
- [ ] **Step 3: Implement** the one line.
- [ ] **Step 4: Run** `lobby_trove_plaza,trove_build,trove_group_once,trove_stale_once,trove_provisional,trove_two_servers,trove_exploits,client_trove,client_trove_mobile,lb_world,bug2lobby_benches,polish_worldtext,p5world_lobby,bb6_lobby_lights,lobby,p6lobby_server` -> PASS. LobbyBuilder stays 154. check.mjs 0 errors.
- [ ] **Step 5: Look at it:** render the plaza from above and from the spawn (`py -3.12 tools/render_model.py` with the `lobby` target, the views it offers) into `<evidence>\t17_trove_west*.png`: the chest between the two west benches, beside the Guide board, its sign on the walk side.
- [ ] **Step 6: Commit** `feat(lobby-shop): the Sky Trove moves to spot C on the west lawn, between the benches by the Guide board`

**Only Studio can judge:** the chest seen from the spawn on PC and a phone; walking the west walk past it.

### Task 18: Titles on the server (Trophies rank, Creator, the Rank column)

Spec: 16.6 "Config", "Server", "Tests". Skills: roblox-dev:roblox-security (only the server writes a title), roblox-dev:roblox-datastores (the rank comes from the OrderedDataStore page).

**Files:**
- Modify: `src/shared/Config.lua` (`Attr.Title = "Title"`, `Attr.TitleRank = "TitleRank"`, `Leaderboard.RankTitles`)
- Modify: `src/server/Services/DevService.lua` (`isGroupOwner` answers nil on a failed call and caches only real answers; new `DevService.IsOwner(player) -> true | false | nil`; `DevService.IsAllowed` keeps answering a boolean)
- Modify: `src/server/Services/PlayerService.lua` (`leaderstats` gets `Rank`, a StringValue `""`, right after `Tokens`, synchronously in `setupPlayer`; PlayerService is the only creator of `leaderstats` and its values)
- Modify: `src/server/Services/LeaderboardService.lua` (`S.Owner`, `S.Titles`, `applyTitle`, `LeaderboardService.TitleOf`; `Init` reads `deps.DevService`; hooks on `Players.PlayerAdded`, `PlayerRemoving`, after each good Trophies read; it never creates `leaderstats` or `Rank`: while `Rank` is missing `applyTitle` sets the attributes and writes Rank from a task that waits for it (`WaitForChild`, 10 s), or at its next pass. Review 2026-11-07: `Main.server` inits LeaderboardService before PlayerService, so its `PlayerAdded` handler can run first, and creating the folder there would put Rank before Tokens)
- Modify: `src/server/Main.server.lua` (the existing `LeaderboardService.Init` table gains `DevService = DevService`: no new local)
- Modify: `tools/robloxmock.lua` (if missing: `game.CreatorType` / `game.CreatorId` settable by tests and restored; `Player:GetRankInGroup(id)` -> `Mock.GroupRanks[userId]` or 0, erroring while `Mock.GroupRankFail`)
- Modify: `tools/smoke_leaderboard.lua` (`lb_titles`), `tools/smoke.py` (its line), `tools/contract.json` (`server/Services/LeaderboardService` + `TitleOf`; `server/Services/DevService` + `IsOwner`)

**Interfaces:**
- Produces:
  - `Config.Leaderboard.RankTitles = { Stat = "Trophies", Rainbow = 10, Gold = 100, Column = "Rank", ColumnText = { Creator = "Creator", Top10 = "Top 10", Top100 = "Top 100" }, Tag = { Creator = "CREATOR", Top10 = "TOP 10", Top100 = "TOP 100" } }`.
  - Player attributes `Title` (`"Creator"` | `"Top10"` | `"Top100"` | absent) and `TitleRank` (1..100 | absent); `leaderstats.Rank.Value` = `ColumnText[kind]` or `""`. Creator wins over a rank (`TitleRank` still set). The rank is the player's index in a good `S.Pages.Trophies.Entries`; none in the "Server" scope before the first good page or with no store.
  - `LeaderboardService.TitleOf(player) -> kind | nil, rank | nil`; `DevService.IsOwner(player)`.

- [ ] **Step 1: Failing test `lb_titles`** (spec 16.6 "Tests", server half): ranks 3 / 57 / outside; the owner (User game) as Creator at rank 3 with `TitleRank` 3; an Admin who is not the owner gets no Creator; a group game: rank 255 -> Creator, `GetRankInGroup` erroring -> none, asked again at the next Trophies refresh, then Creator; the no-store "Server" scope -> no Top titles, Creator still; the next read moving rank 3 to 12 -> `Top100`; no attribute or `Rank` write without a change (count the writes); `leaderstats` children Tokens then Rank; the same when LeaderboardService's `PlayerAdded` handler is run before PlayerService's (call it first by hand on a fresh mock player): no `leaderstats` created by it, children still Tokens then Rank, and Rank holds the title's text once PlayerService made it; a player leaving mid-refresh -> no error, `S.Titles` dropped (Review Focus 5); `IsAllowed` still a boolean when the group call errors.
- [ ] **Step 2: Register** `"lb_titles"` on the `smoke_leaderboard.lua` line. **Run** `--only lb_titles` -> FAIL.
- [ ] **Step 3: Implement** (the mock first).
- [ ] **Step 4: Run** `lb_titles,lb_write,lb_read,lb_fallback,lb_world,dev_tools,boot,load_modules,mock_selftest,contract,config_shape,final_checks,shutdown` plus every scenario of `smoke_server.lua` / `smoke_economy.lua` that reads `leaderstats` (`grep -n leaderstats tools/smoke_server.lua tools/smoke_economy.lua`) -> PASS. LeaderboardService <= 55, DevService <= 146, PlayerService 34, Main.server 58. check.mjs 0 errors.
- [ ] **Step 5: Commit** `feat(lobby-shop): Trophies rank titles (Top 10 / Top 100) and the owner's Creator title on the server, with a Rank column in the player list`

**Only Studio can judge:** the Rank column in Roblox's player list; the Creator check on the published game (User or group).

### Task 19: Titles above the head (TitleController)

Spec: 16.6 "Client", "Tests". Skills: roblox-dev:roblox-ui, roblox-dev:roblox-performance (no per-frame Lua).

**Files:**
- Create: `src/client/Controllers/TitleController.lua`
- Modify: `src/client/Controllers/VipController.lua` (when the player has a `Title`: no `VipCrown` billboard of its own, `TitleController.SetCrown(player, on)` with its usual rule instead; without a `Title`: the crown as today at 2.4 studs; listens to `Title` too; no new top-level local), `src/client/Main.client.lua` (`"TitleController"` after `"VipController"`; `OPTIONAL`)
- Modify: `tools/dump_gui.lua` (scene `titles`: three dummy characters with the three tags; scenes `titles:<studs>` for 10 / 30 / 60: the name stand-in, the tag and the crown placed where they project from that distance at 70 degrees, as the `portal` scene's distance mode does), `tools/render_gui.py` (`SCENARIOS`)
- Create: `tools/smoke_titles.lua` (client world); Modify: `tools/smoke.py`, `tools/contract.json` (`client/Controllers/TitleController`: `Init`, `TagOf`, `SetCrown`)

**Interfaces:**
- Consumes: `Title`, `TitleRank` (Task 18), `InBattle`, the graphics quality read `PortalFxController` uses.
- Produces: `TitleController.Init()`, `TagOf(player) -> BillboardGui | nil`, `SetCrown(player, on)`; BillboardGui `TitleTag` > `Plate` > `Label` > `Fill` (+ `Crown` 34 x 34, 4 px above the Plate, while `SetCrown` is on: the billboard is then 240 x 74) exactly as spec 16.6: placed in pixels above Roblox's name (`StudsOffset (0, 2.0, 0)`, `SizeOffset (0, 0.5 + 26 / H)`), never by a stud gap; rainbow `Fill.Offset` tween 2.4 s Linear repeat -1 for Top10 on a `Label` twice the text width with `TextXAlignment Left` (a UIGradient does not wrap, so the text stays in the half that is one full period), static gold for Top100, static cyan -> violet for Creator; texts "TOP 10 \194\183 #N" / "TOP 100" / "CREATOR"; hidden while `InBattle` and, for the local player, while the camera is within 2 studs of the head (a 4 Hz check, local player only).

- [ ] **Step 1: Failing test `client_titles`** (spec 16.6 "Tests", client half: the Top10 `Label` 2 x the text width and left-aligned inside a text-wide Plate; `SizeOffset.Y == 0.5 + 26 / H`; a titled VIP -> `Crown` inside `TitleTag` 4 px above `Plate` and no `VipCrown` on that head, the crown follows VipController's rule (gone in `InMatch`, on Low graphics); an untitled VIP -> `VipCrown` at 2.4 studs; the title cleared on a VIP -> `VipCrown` back) plus: respawn (Review Focus 5): `CharacterAdded` -> one tag on the new head, none left on the old; the attribute cleared -> the tag removed and its tween stopped; ten Top10 players -> ten tweens, no Heartbeat added (`Mock` connection count unchanged).
- [ ] **Step 2: Register** `if p5("smoke_titles.lua"): client_files.append("smoke_titles.lua"); ins(client_scenarios, "client_final", ["client_titles"])  # [lobby-shop, Task 19] titles above the head (smoke_titles.lua)`. **Run** -> FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: dump_gui `titles`**; render at 844x390 and 1920x1080; look at the three tags (rainbow, gold, Creator) for size, contrast and the plate width; then `titles:10`, `titles:30`, `titles:60` at 844x390: the name, the tag and the crown never overlap at any distance (the review's failure: stud gaps closing on screen far away).
- [ ] **Step 5: Run** `client_titles,client_final,contract,client_gui_dump` plus the VIP crown scenarios (`grep -l VipController tools/smoke_*.lua`) -> PASS. TitleController <= 30. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): titles above the head: a rainbow TOP 10, a gold TOP 100, CREATOR for the owner`

**Only Studio can judge:** the rainbow fade on a live character at distance, beside Roblox's own name and the VIP crown; the `StudsOffset` 2.0 anchor against where Roblox really draws the name (tune the stud anchor only, never turn the pixel gap back into studs).

### Task 20: EggArt base and the egg stage core (plumbing, plain visuals)

Spec: 16.4 (phases, timings, x3, Skip, API, "Never breaks the player"), 5.5 (behaviour, copy, queue, Esc / B), 16.5 (the EggArt API only). This task builds the request path and the phase runner with final names and timings and plain visuals, so the Shop can wire to it; the painted eggs (Task 26) and the dressed cutscene (Task 27) come last among the client tasks, as the owner's order asks. Skills: roblox-dev:roblox-ui, roblox-dev:roblox-performance.

**Files:**
- Create: `src/client/UI/EggArt.lua` (the API of 16.5; every form draws the oval body, the tone gradient, the outline and the highlight; `Paint(rarity)` returns `{}` until Task 26), `src/client/UI/EggStage.lua`
- Modify: `tools/dump_gui.lua` (scenes `eggs`, `hatch:strip`, `hatch:strip3`, `hatch:crack`, `hatch:reveal`, `hatch:reveal3`, `hatch:secret`), `tools/render_gui.py` (`SCENARIOS`)
- Create: `tools/smoke_egg_stage.lua` (client worlds); Modify: `tools/smoke.py`, `tools/contract.json` (`client/UI/EggArt`: `New`, `SetRarity`, `Halves`, `Glow`, `Tones`, `Paint`; `client/UI/EggStage`: `Init`, `Show`, `Request`, `IsPending`, `IsShowing`, `Phase`, `Skip`, `Back`, `Done`, `Close`, `Timings`, `NoteText`, `Layout`, `IsPrewarmed`, `Stats`)
- Not wired yet: `EggStage.Init` (the `RouletteResult` listener) is called by ShopController in Task 22; tests drive `EggStage.Show(result)`.

**Interfaces:**
- Consumes: `ClientSettings` `FastHatch` (Task 2); `GemIcon` (Task 15); `CloudUI.PetViewport`; `SoundFx.Play`.
- Produces:
  - EggArt: `New(parent, rarity, size, opts)`, `SetRarity(egg, rarity)` (re-skins in place, no new instances), `Halves`, `Glow` (0 / 0 / 0.22 / 0.34 / 0.58 / 0.66 / 0.78), `Tones` (the rarity colour 38% toward white / 28% toward black; Secret rgb(74,68,104) / rgb(18,16,28)), outline rgb(11,16,48) at `size / 20` (>= 2 px, whole).
  - EggStage: the API and instance tree of spec 16.4; `Phase()` runs `Intro`, `Strip`, `Land`, `Rise`, `Crack`, `Burst`, `Reveal`; `Timings(false, 1)` = `{ Intro = 0.35, Strip = 3.0, Land = 0.35, Rise = 0.5, Crack = 1.2, Burst = 0.35, RevealAt = 5.75 }`, `Timings(true, 1)` = `{ 0.15, 0.8, 0.12, 0.2, 0.4, 0.25, RevealAt = 1.92 }`; x3 `Stagger = 0.6` (fast 0.25), strips land 0.25 s apart (fast 0.12), each x3 `Crack` 0.9 (fast 0.4), `RevealAt` 7.15 (fast 2.66). Strip cells: at most 12 `Cell` frames per strip, recycled with `EggArt.SetRarity` as the 40-cell strip scrolls. Plain visuals here: the `Dim` frame, the strip and `Pointer`, the hero egg growing on a plain `Pedestal1` frame, `CrackWord`, `EggArt.Halves` flying apart, the reveal columns. `Stats()` counts this module's instances, tweens and Heartbeats.
  - Gamepad B: `"NimbusHatchBack"` at `Enum.ContextActionPriority.High.Value + 1`, bound only while the stage shows, always `Sink`. Esc: **no `UserInputService` handler in EggStage** (review 2026-11-07: two InputBegan handlers run in no guaranteed order); `EggStage.Back()` (skip before the reveal, DONE on it) is Esc's one path, called by ShopController's single Esc handler from Task 22.
  - One `teardown(reason)` for every exit, then `Closed:Fire(reason)` (`"Done"` | `"Error"` | `"Match"` | `"Close"`; spec 16.4 "Never breaks the player"); no exit on the character dying or being removed (the stage plays on); no write to `Camera` or the Humanoid.
  - Skip: `Phase()` is `"Reveal"` on the next frame; the burst's 0.25 s tail plays as an overlay over the reveal's start (spec 16.4 "Skip"; the plain core shows the tail as a short fade, Task 27 dresses it with the one gold flash).

- [ ] **Step 1: Failing tests**
  - `client_egg_art`: the seven eggs build at 30 / 64 / 104 / 160 / 380 px; `Glow` and `Tones` per Interfaces; `Halves` returns two frames covering the egg's height; `SetRarity` keeps the instance count
  - `client_egg_stage` (1920x1080, the stage alone): a Cloud x1 Epic result (`IsNew`, `PoolSize = 3`): `Phase()` runs the seven phases in order, Reveal at 5.75 +- 0.1 s; `CrackWord.Text == "EPIC EGG!"`, the reveal `Word.Text == "EPIC!"`, `Note.Text == "1 of 3 Epic pets \194\183 added to your pets"`, `New` visible; not new with `Count = 2` -> `"1 of 3 Epic pets \194\183 you have 2 " .. name .. " now"`; a substitute -> `"Stack full: +800 Tokens instead"`; `Pity = true` -> ends `" \194\183 guaranteed"`; Fast hatch -> Reveal at 1.92 +- 0.1; x3 -> 7.15 +- 0.1 (fast 2.66), three strips landing 0.25 s apart, the eggs cracking in pull order 0.6 s apart; `Skip` visible on the first frame, `Skip()` at t = 0 -> `Phase() == "Reveal"` on the next frame; `Back()` during Strip skips, on Reveal is DONE (`Closed` fired with `"Done"`); an Esc `InputBegan` with only the stage alive changes nothing (EggStage has no Esc handler); the character removed mid-Strip (a new one added) -> the roll still reaches Reveal; `Mock.BoundActions.NimbusHatchBack` only while showing, above `NimbusDash`, B skips during Strip and is DONE on Reveal, returns `Sink`; an evolved key -> `EvolvedRibbon`; an old-shape result plays as one pull; a pull with no `Strip` starts at `Rise`; `SpinAgain` -> one `BuyRoulette` through `Request`; two `Request`s within 0.3 s -> one fire; a failure -> `IsPending() == false` at once, one toast, the stage not opened; a result during a roll waits for DONE; 7 s without an answer -> `IsPending() == false` and a toast, a late success still plays; the `FastHatch` toggle -> one `SettingsSet("FastHatch", true)` 0.4 s later; sounds (`SoundFx.Play` spied): Epic `SpinStart`, `SpinTick`, `SpinLand`, `Shatter`, `RevealRare` at `Scale = 0.6`, Legendary `RevealLegendary` at 1; a 40-cell strip never holds more than 12 `Cell` frames; `Stats().Instances` <= 450 (x1) / 750 (x3) at every phase; after DONE `Stats()` is all zero; Camera `CameraType` / `CameraSubject` / `FieldOfView` and the Humanoid's `WalkSpeed` / `JumpPower` equal their values before the roll (after DONE and after `Close()` mid-Crack); census: no `"\226\151\134"` in `NimbusHatch`
  - `client_egg_stage_mobile` (mobile world): x1 and x3, **during `Crack` and on the reveal**, at 640x360, 667x375, 844x390, 360x640, 390x844, 1280x720, 1366x768: `RedoGeom.check(Stage.Content, label, { MinText = 15 (phones) / 14, NoOverlap = <the phase's list>, Skip = { Rays = true, Flash = true, Vignette = true } })`. `RedoGeom`'s NoOverlap fails on a name that is not shown and checks only the first descendant of each name, so the lists are per phase (review 2026-11-07): `Crack` x1 `{ "CrackWord", "Egg1", "Pedestal1", "Skip", "FastHatch" }`, x3 `{ "CrackWord", "Egg1", "Egg2", "Egg3", "Pedestal1", "Pedestal2", "Pedestal3", "Skip", "FastHatch" }`; reveal x1 `{ "Banner", "Pedestal1", "Name", "Note", "SpinAgain", "Done", "Skip", "FastHatch" }`, x3 the bottom-bar names on `Content` plus one check per column root `Col1..3` with `{ "Banner", "Name", "Note" }` and a direct box test of `Pedestal<j>` against `Col<j>.Name`. Also: the crack egg and the pedestal shrink with the middle (at 640x360 and 844x390 the x1 crack stack, word 40 + egg + pedestal, fits between the title band and the bottom bar with the egg between 120 (0.6) and 200 px, the pedestal always 1.1 x / 0.24 x its egg), the phone reveal's pedestal is the thin lip (12 px, its bottom 8 px above the pet frame's bottom), the phone `Banner` 44 tall, the three x3 pets inside the screen, the bottom bar above the bottom inset; resize mid-roll (Review Focus 1): an x3 started at 844x390, switched to 390x844 during Strip and to 1920x1080 on Reveal -> the check passes after each switch and the roll reaches Reveal
- [ ] **Step 2: Register** `if p5("smoke_egg_stage.lua"): client_files.append("smoke_egg_stage.lua"); ins(client_scenarios, "client_final", ["client_egg_art", "client_egg_stage"]); mobile_scenarios.append("client_egg_stage_mobile")  # [lobby-shop, Tasks 20/22/26/27] the eggs, the egg stage, the cutscene (smoke_egg_stage.lua)`
- [ ] **Step 3: Run** `--only client_egg_art,client_egg_stage,client_egg_stage_mobile` -> FAIL.
- [ ] **Step 4: Implement** EggArt, then EggStage.
- [ ] **Step 5: dump_gui** the seven scenes; render each at 844x390 and 1920x1080; check layout, sizes and the inset (the looks come in Tasks 26-27).
- [ ] **Step 6: Run** the three plus `client_audio_keys,client_gui_dump,client_gem_icon,contract` -> PASS. EggStage <= 90, EggArt <= 30. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the egg stage core: one request path, seven phases with their final timings, Skip from the first frame, x3, Fast hatch (plain visuals)`

### Task 21: The Shop window A (rail, the Store merged in, the Gems tab)

Spec: 16.3 "Who owns it", "Tabs and items", "Window", "Gems tab", "Packs, Passes, Boosts", "Hooks" (the Task 21 step), 16.1 (ribbons, the Chest line). Skills: roblox-dev:roblox-ui, roblox-dev:roblox-security (the client never prompts a purchase or decides a price).

**Files:**
- Move: `git -C <worktree> mv src/client/Controllers/StoreController.lua src/client/Controllers/ShopController.lua`, then edit it into the Shop window (ScreenGui `NimbusShop`, `ShopWindow`, the rail, the header, the five pages, `K.BACK_ACTION = "NimbusShopBack"`, `MouseLock.WatchVisible("Shop", ShopWindow)`, who `"Shop"` for `SetTouchHidden` / `SetColumnCovered`)
- Create: `src/client/Controllers/StoreController.lua` (the forwarder of spec 16.3), `src/client/UI/ShopGems.lua`
- Modify: `src/shared/Config.lua` (`Store.Tabs = { "Eggs", "Gems", "Packs", "Passes", "Boosts" }`; Tokens1..3 and Cash1..3 `Tab = "Gems"`), `src/shared/StoreCatalog.lua` (gem products `Tab = "Gems"`; `GEM_HERO_INDEX = 3`; `Validate`'s Cash `Line` rule keyed on the Cash items, not the tab; header), `src/client/UI/NeonKit.lua` (`Glyphs.Eggs = "\240\159\165\154"`), `src/client/Main.client.lua` (`"ShopController"` where `"StoreController"` boots, the forwarder after it; `OPTIONAL`), `src/client/Controllers/MenuController.lua` (`P5.openStore` and `onOpenPanel` `"store"` -> `ShopController.Open(args)`; nothing else yet)
- Modify: `tools/check.mjs` (the TextureIds joiner allowance at the `isVortex` list and its header comment: `ShopController.lua` replaces `StoreController.lua`, which no longer joins)
- Modify: `tools/dump_gui.lua` (scenes `shop[:<Tab>]` = `ShopController.Open({ Tab = tab })`; `store[:<Tab>]` kept through the forwarder; the `Tab = "Currency"` call -> `"Gems"`), `tools/render_gui.py` (`shop`, `shop:Gems`, `shop:Packs`, `shop:Passes`, `shop:Boosts`)
- Create: `tools/smoke_shop_ui.lua` (client worlds); Modify: `tools/smoke.py`, `tools/contract.json` (new `client/Controllers/ShopController`: `Init`, `Open`, `Close`, `IsOpen`, `NormalizeTab`, `Tab`, `Layout`, `Portrait`, `Cards`, `Palette`, `RobuxGlyph`; new `client/UI/ShopGems`: `Build`, `Layout`, `Refresh`, `PackRibbons`, `BestValue`, `ChestLine`, `PotionState`; the `client/Controllers/StoreController` entry unchanged, the forwarder answers it)
- Rewrite (keep names): `smoke_store_ui.lua` (`client_store_window`, `client_store_states`, `client_store_shine`, `client_store_bridge`, `client_store_mobile`: `NimbusStore` -> `NimbusShop`, `StoreWindow` -> `ShopWindow`, `Tab_Currency` -> `Tab_Gems`, `Tab_Roulettes` -> `Tab_Eggs`, the content box x 262 / width 1240), `smoke_fixr_store_ui.lua` (`client_fixr_store_colors`, `client_fixr_store_loading`, `client_fixr_store_art`, `client_fixr_store_gem_thanks`, `client_fixr_store_portrait`), `smoke_store.lua` (`store_config`: the five tabs; `store_catalog`: gem items `Tab == "Gems"`, hero index 3; `client_store_bigrect`: the new `RECT`), `smoke_hud_pill.lua` (`client_hudpill`, `client_hudpill_mobile`: `NimbusShop`), `smoke_fixr_daily_ui.lua` (`client_fixr_menu_cover`, `client_fixr_touch_handoff`: `NimbusShop`, who `"Shop"`), `smoke_gem_icon.lua` (`client_gem_icon`, built in Task 15: the census opens the Shop's Gems tab instead of the Store's Currency tab); re-run and rewrite only on failure: `smoke_redo_train.lua` `client_train_wiring`, `smoke_redo_fusion_ui.lua` (their controller lists)

**Interfaces:**
- Produces: spec 16.3 "Window" (RECT `{ H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1540, Y1 = 910 }`, `PC_MAX_W 0.81`, Compact under 1,400 design px, the rail, header and page sizes), "Gems tab" (`ShopGems.PackRibbons` -> nil / "+10%" / "+20%" / "+30%" computed from the prices shown; `ShopGems.ChestLine()` -> "Chest: 1,950 gems buys 3 Secret spins + 2 Celestial spins", the "+ m Celestial spins" part dropped when m is 0 and the "n Secret spins + " part when n is 0; `PotionState()`), "Packs, Passes, Boosts" (the Store's cards, names unchanged), `ShopGems.BestValue(packs) -> index | nil` (the most gems or tokens per Robux among the prices shown, ties to the bigger pack: today pack 4 of the gems, pack 3 of the tokens; no ribbon either when a pack's gain is zero or less), the token-grant lock's client half (spec 16.1: `TokenPack_1..3` and `Card_Pro` locked with the text while `PaidRandomItemsRestricted` is not `false`, sending nothing), the phone rail and tile heights by body (spec 16.3: tabs 104 x 48 at `6 + i * 54` with a 280 body, 104 x 44 at `4 + i * 49` under 276; tiles `min(266, body - 12)`). The Task 21 step: the window fires `WindowOpened("Store")`, its first tab is Packs, and `Tab_Eggs` hops to `MenuController.Open("Shop", { Tab = "Roulettes" })` (the old Cloud Shop still lives); `NormalizeTab` as spec 16.3.

- [ ] **Step 1: Failing tests**
  - `client_shop_window` (1920x1080): `ShopWindow` 1540 x 910 (`NeonKit.BigRect`); the rail's five tabs in order at x 18, y `16 + i * 92` (+44 from `Tab_Packs`), 224 x 80, the `RobuxDivider` between Gems and Packs; header `Title` "Shop", `Balance_Gems` (a `GemIcon.Amount`), `Balance_Tokens`, `CloseButton`, no Cash pill; `NormalizeTab` for every alias of spec 16.3; `Open({ Tab = "Currency" })` -> Gems, `Open({ Tab = "Passes" })` -> Passes; the first open shows Packs, a re-open shows the last tab; Packs / Passes / Boosts hold every `StoreCatalog.List()` card of that tab with its `Card_<key>` name inside the content box (x 262, width 1240); `Tab_Packs.Dot` visible while the Starter Pack is on sale and not in `StoreBought`, hidden after; `Tab_Eggs` closes the Shop and opens MenuController's Cloud Shop; `WindowOpened` fired `"Store"` once per open; `SetTouchHidden("Shop", true)` on a touch device; the cursor free over the window with mouse lock on; Esc closes; `Mock.BoundActions.NimbusShopBack` only while open, above `NimbusDash`, B closes and returns `Sink`
  - `client_shop_gems` (1920x1080, 844x390, 390x844): packs "200" / "670" / "1,950" / "5,300" with the Config names; ribbons nil / "+10%" / "+20%" / "+30%" and "BEST VALUE" on pack 4; with `Products[4].Robux = 1999` both recomputed (not typed): ribbons nil / "+10%" / "+20%" / nil (pack 4's gain is negative) and "BEST VALUE" on the Chest (pack 3), none on pack 4; the same move when a mocked live `PriceInRobux` differs from Config; `Id 0` -> the Config `Robux` on an inactive "Coming soon" button ("PREVIEW" under `StorePreview`); `Id 123` with a mocked `PriceInRobux` 59 -> 59 and one `StoreRequest("Buy", "Gems2")` per tap; the hero `Line2` from `ChestLine()`, and with `SecretRoulette.GemPrice = 600` it reads "Chest: 1,950 gems buys 3 Secret spins"; every `PotionState` from its attributes with its label, "100" on the button, Short at 99 gems, only "Ready" sends `GemBuy`; token packs "1,500" / "7,500" / "30,000" with the computed "BEST VALUE" on pack 3 and no % ribbon; `PaidRandomItemsRestricted` true (and nil: unknown) -> `TokenPack_1..3` and the Packs tab's `Card_Pro` show the lock text on an inactive `Buy` and a tap sends no `StoreRequest`, `false` -> they buy as usual, the gem packs unaffected either way; at 1280x720 the token packs are reachable inside `Body`; phone: one sideways row of eight 166 x `min(266, body - 12)` tiles with the right `Fade` (266 at 844x390); census: no `"\226\151\134"`
  - `client_shop_sizes` (1280x720, 1366x768, 1920x1080, 2560x1440): `ShopWindow` = `NeonKit.BigRect` (design 1296 x 759, 1383 x 810, 1540 x 910, 1540 x 910 at 1.25: review 2026-11-07, the spec's 876 / 910 rows were wrong); Compact rail (112 wide, icon over label) at the first two, PC at the others; on every page (Gems, Packs, Passes, Boosts) every card is fully reachable (scroll to each and it lies inside `Body`). Task 22 adds the Eggs page here: 1920x1080 keeps the reference layout (body 834 >= 826: hero 240, cards 550, no vertical scroll); 1280x720 and 1366x768 use the shrunk layout (hero 200, cards 516) and the page scrolls vertically (`CanvasSize` taller than `Body`), every card reachable by scrolling
  - `client_shop_mobile` (844x390, 740x360, 667x375, 640x360): `ShopWindow` = `NeonKit.BigRect` (820 x 330 / 716 x 300 / 643 x 315 / 616 x 300); rail 104 wide; tabs per body (review 2026-11-07): 104 x 48 at y `6 + i * 54` at 844x390 (body 280), 104 x 44 at y `4 + i * 49` at the other three (bodies 250 / 265 / 250), `Tab_Boosts` inside the window and the screen at all four; `RedoGeom.check(ShopWindow, label, { MinText = 15, MinTarget = 44, NoOverlap = { "Tab_Eggs", "Tab_Gems", "Tab_Packs", "Tab_Passes", "Tab_Boosts", "Balance_Gems", "Balance_Tokens", "CloseButton" } })` on every tab; big balances (Review Focus 6): 12,345,678 gems and tokens -> `Theme.ShortNumber` and the check still passes; resize while open (Review Focus 1): 844x390 -> 390x844 -> 844x390 passes each time
  - `client_shop_portrait` (390x844, 360x640): two header rows, the rail as one row of five 64 x 56 tabs, a vertical list on every tab, `RedoGeom.check` passes
- [ ] **Step 2: Register** `if p5("smoke_shop_ui.lua"): client_files.append("smoke_shop_ui.lua"); ins(client_scenarios, "client_final", ["client_shop_window", "client_shop_gems", "client_shop_sizes"]); mobile_scenarios += ["client_shop_mobile", "client_shop_portrait"]  # [lobby-shop, Tasks 21-23] the Shop window A (smoke_shop_ui.lua)`
- [ ] **Step 3: Run** `--only client_shop_window,client_shop_gems,client_shop_sizes,client_shop_mobile,client_shop_portrait` -> FAIL.
- [ ] **Step 4: Implement:** the `git mv`, the forwarder, Config / StoreCatalog, ShopGems, the rail and header, check.mjs, the boot.
- [ ] **Step 5: Rewrite** the listed scenarios.
- [ ] **Step 6: dump_gui** `shop:Gems`, `shop:Packs`, `shop:Passes`, `shop:Boosts`; render at 844x390, 1920x1080, 1366x768, 390x844; look at them against `shopA("pc", "Gems")`, `shopA("phone", ...)` and `packTile`.
- [ ] **Step 7: Run** the five plus `store_config,store_catalog,store_router,client_store_bigrect,client_store_window,client_store_states,client_store_shine,client_store_bridge,client_store_mobile,client_fixr_store_colors,client_fixr_store_loading,client_fixr_store_art,client_fixr_store_gem_thanks,client_fixr_store_portrait,client_hudpill,client_hudpill_mobile,client_fixr_menu_cover,client_fixr_touch_handoff,client_gem_icon,client_train_wiring,client_gui_dump,contract` -> PASS. ShopController <= 72, ShopGems <= 45, StoreController <= 10, NeonKit <= 34, MenuController not above 164. check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(lobby-shop): one Shop window with a tab rail: the Robux Store merged in and restyled, a Gems tab with honest ribbons, token packs and the gem XP Potion`

### Task 22: The Eggs tab, and the Cloud Shop leaves MenuController

Spec: 16.3 "Eggs tab", "Hooks and every opener" (the MenuController list, `WindowOpened`, MouseLock, Esc / B), 16.4 (the stage wiring), 5.5 "Queue and waits", 3.2. Skills: roblox-dev:roblox-ui, roblox-dev:roblox-security (the client never decides a price or a roll).

**Files:**
- Create: `src/client/UI/ShopEggs.lua`
- Modify: `src/client/Controllers/ShopController.lua` (`Page_Eggs` from ShopEggs; Eggs is the first tab; `WindowOpened("Shop")`; `Init` calls `EggStage.Init()`; refused while `EggStage.IsShowing()` and in a match; the window hides while the stage shows, and `EggStage.Closed(reason)` shows it again **only when reason is `"Done"` or `"Error"`, the Shop is still open and the player is not `InMatch`** (spec 16.4; otherwise it stays hidden and a still-open Shop closes, releasing its touch hiding and cursor); the one Esc handler (connected once in `Init`, the Store's `S.Open` check widened): while `EggStage.IsShowing()` -> `EggStage.Back()` and stop, the Shop open or not; else close when open (spec 16.3 "Esc / gamepad B"); B does nothing while the stage shows (its binding at `High + 1` takes the press); the PC rail's `FastHatch` toggle on the Eggs tab)
- Modify: `src/client/Controllers/MenuController.lua` (the removal list and the `P5` additions of spec 16.3; `onOpenPanel` `"shop"` -> `ShopController.Open(args)`; `MenuController.IsOpen()`; `handleBack` loses its stage / odds branches; `closeEverything` closes the Shop first, then the stage (so the stage's `Closed` never finds an open Shop to show again); the close list gains `"Shop"`; header API)
- Modify: `src/client/MouseLock.lua` (`WATCHERS`: `NimbusHatch = watchOverlays({ "Stage" })` replaces the `NimbusMenu` stage / odds entry)
- Modify: `tools/dump_gui.lua` (`shop` = the Eggs tab, `shop:restricted`; the `menu` scene's Shop path removed), `tools/render_gui.py` (`"menu:Shop"` -> `"shop"`, `"shop:restricted"`)
- Modify: `tools/smoke_shop_ui.lua` (`client_shop_eggs`; `client_shop_window`: `WindowOpened` `"Shop"`, first tab Eggs, `Tab_Eggs` is the real page; `client_shop_sizes`: the Eggs page fit checks of Task 21's line), `tools/smoke_egg_stage.lua` (`client_egg_stage_wiring`), `tools/smoke.py` (both lines), `tools/contract.json` (`client/UI/ShopEggs`: `Build`, `Layout`, `Refresh`, `Focus`, `CardState`)
- Rewrite (keep names): `smoke_p2_ui.lua` (`client_p2ui`, `client_p2ui_mobile`: `GemRoulette_*` -> `NimbusShop` `ShopCard_*`), `smoke_p2_visual.lua` (`client_p2visual`), `smoke_release_client.lua` (`client_release_roulette`, `client_release_pets`, `client_release_touch_mobile`: `NimbusMenu.RouletteStage` -> `NimbusHatch`, `Window_Shop` -> `NimbusShop`, the Odds popup checks go, `MenuController.IsPrewarmed` -> `EggStage.IsPrewarmed`), `smoke_client.lua` (the Esc-dismiss check looks for `NimbusHatch.Stage`), `smoke_hud_items.lua` (`client_huditems_gone`), `smoke_p5_gui.lua` (`client_p5gui_cover`: the shop's COVER entry reads `NimbusShop` / `ShopWindow`), `smoke_p5_looks.lua` (`client_p5looks`: the old-shape result plays through EggStage, `EvolvedRibbon` in `NimbusHatch`), `smoke_dgfix_mouse.lua` (`client_dgfix_mouse`: rows `shop` and `hatch`), `smoke_client_v2.lua` (`client_menu`: `OpenPanel` Shop `Tab = "Roulettes"` -> Eggs), `smoke_storm.lua` (`client_storm`: the Summon opens `NimbusShop` with `ShopCard_Secret` focused; its Odds popup checks become the card's odds rows), `smoke_bug2_tutset.lua` (the watcher list: `NimbusHatch` / `Stage`), `smoke_daily_ui.lua` (`client_daily_window`: closes the Shop through `MenuController.Close()`), `smoke_audio.lua` (`client_audio_sites`: the roulette block expects `SpinStart`, `SpinTick`, `SpinLand`, `Shatter`, then the reveal by rarity), `smoke_store_ui.lua` `client_store_bridge` (the Eggs tab is the real page now), `smoke_gem_icon.lua` `client_gem_icon` (the census gains the Eggs tab and the stage)

**Interfaces:**
- Consumes: `EggStage` (Task 20); `SecretPityLeft` (Task 5), `GemsSettled` (Task 3), `PaidRandomItemsRestricted`; `PetCatalog.GetRarityOdds`; the prices of Task 16.
- Produces: spec 16.3 "Eggs tab" (`ShopCard_Secret` hero and the four `ShopCard_<Id>` cards with their sizes, states and texts; `ShopEggs.CardState(id) -> "Ready" | "Short" | "Locked" | "Loading" | "Pending" | "NoOdds"`, `ShopEggs.Focus(id)`); `ShopController.Open({ RouletteId })` focuses and outlines for 2.6 s; MenuController drops under 160 locals.

- [ ] **Step 1: Failing tests**
  - `client_shop_eggs` (1920x1080): `ShopCard_Secret` 1240 x 240 at (0, 16) of the content box, "Secret Roulette", its odds equal `GetRarityOdds("Secret")` ("60%" Mythic, "40%" Secret), `PityChip` for `SecretPityLeft` 3 / 1 / absent, `Spin` GemIcon + "500", `Hint` "Also at the Storm Altar"; the four cards at (`i * 314`, 276), 298 x 550 (+-1), their `Odds_*` rows equal `GetRarityOdds(id)` in order and value (Celestial four rows, the last Secret "2%"); `Spin` = the token price, `Spin3` = 3x, `SpinGems` = 20 / 40 / 60 / 180; `GetRarityOdds("Storm")` stubbed `{}` -> "Odds unavailable", buttons inactive; each button sends its `BuyRoulette` arguments once through `EggStage.Request`; while pending every `CardState == "Pending"`; a failure re-enables all with a toast; restricted -> `SpinGems` and the Secret card locked with today's text; no `GemsSettled` -> "Loading..."; `Open({ RouletteId = "Secret", Currency = "Gems" })` -> `ShopCard_Secret` inside the window and outlined, gone after 2.6 s; `{ Currency = "Gems" }` alone keeps the tab; every text >= 18 px; the rail `FastHatch` -> one `SettingsSet("FastHatch", true)` 0.4 s later; `MenuController.IsOpen()` true while the Shop or the stage shows; `MenuController.Close()` and `InMatch` close it; `WindowOpened` fired `"Shop"` once per open; the tutorial card folds while it is open
  - `client_shop_mobile` / `client_shop_portrait` gain the Eggs tab: the Secret card 200 wide first, then four cards 166 wide at `x = 208 + i * 174`, every card `min(266, body - 12)` tall per size (review 2026-11-07: 266 at 844x390, 253 at 667x375, 238 at 740x360 and 640x360; the card art shrinks first, every control and text still inside the card); `Spin3` reads "x3" + token icon + `Theme.ShortNumber(3 * price)` (150, 750, 3,000, 15K); every odds egg >= 30 px; portrait full-width cards with the 2 x 2 odds grid
  - `client_egg_stage_wiring` (1920x1080, the Shop and the stage live): a card tap sends `BuyRoulette`; a success `RouletteResult` plays the stage and hides `ShopWindow`; DONE brings it back; Esc (`InputBegan`) during the strip skips, Esc on the reveal is DONE and the Shop is then open and shown (exactly one Esc handler acted: the Shop's, through `EggStage.Back()`); Esc with the stage showing and the Shop closed (a late answer after closing) still skips / DONEs the stage and opens nothing; B on the reveal is DONE through `NimbusHatchBack` and the Shop stays open; a card tap and SPIN AGAIN within 0.3 s send one request; a match start during the roll closes the stage and one toast lists the pulls not yet shown, and `ShopWindow` stays hidden with `ShopController.IsOpen() == false` (not shown again over the match); `MenuController.Close()` during the roll: the same, the Shop closed; Stats, Pets, Store and Index refuse to open while the stage shows; with mouse lock on the cursor is free over the Shop and the reveal; close while pending (Review Focus 2), once per way of closing (the X, Esc, B through `NimbusShopBack`, `InMatch` set then cleared): tap Spin, close, reopen -> the cards stay Pending until the answer, a success then plays, a failure re-enables them, no answer re-enables them at 7 s
- [ ] **Step 2: Register** `"client_shop_eggs"` on the `smoke_shop_ui.lua` line (client list) and `"client_egg_stage_wiring"` on the `smoke_egg_stage.lua` line.
- [ ] **Step 3: Run** `--only client_shop_eggs,client_shop_window,client_shop_sizes,client_shop_mobile,client_shop_portrait,client_egg_stage_wiring` -> FAIL.
- [ ] **Step 4: Implement** ShopEggs, the ShopController wiring, the MenuController surgery, MouseLock.
- [ ] **Step 5: Rewrite** the listed scenarios.
- [ ] **Step 6: dump_gui** `shop` and `shop:restricted`; render at 844x390, 1920x1080, 640x360, 1280x720, 360x640, 390x844; look at them against `shopA("pc", "Eggs")` / `shopA("phone", "Eggs")`.
- [ ] **Step 7: Run** the six plus `client_shop_gems,client_egg_stage,client_gem_icon,client_p2ui,client_p2ui_mobile,client_p2visual,client_release_roulette,client_release_pets,client_release_touch_mobile,client_final,client_hudpill,client_huditems_gone,client_p5gui_cover,client_p5looks,client_dgfix_mouse,client_menu,client_pets,client_tb_pets_actions,client_store_bridge,client_storm,client_bug2tut_mouse,client_bug2tut_portrait,client_bug2tut_raidnext,client_daily_window,client_audio_sites,client_audio_keys,client_gui_dump,contract` -> PASS. MenuController < 160, ShopController <= 72, ShopEggs <= 60, MouseLock 26. check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(lobby-shop): the Shop's Eggs tab (Secret Roulette hero, four machine cards, odds on every card); the Cloud Shop and its stage leave MenuController`

**Only Studio can judge:** the Shop and a full roll on PC and a phone, Fast hatch on and off, the gold focus from the altar's Summon.

### Task 23: The walk-up Shop prompt and every opener

Spec: 16.3 "The walk-up prompt", "Openers", "Tutorial". Skills: roblox-dev:roblox-security (the prompt is rate-limited; the server only asks the client to open a window).

**Files:**
- Modify: `src/server/Services/LobbyBoardBuilder.lua` (`EggGuide` adds the invisible `PromptPart` at `cf * CFrame.new(0, 2, -5.6)` and returns it), `src/server/Services/LobbyBuilder.lua` (`buildShop` and `fallbackShop` return `Counter = { PromptPart, Center, Model }`; the arch sign's sub "pets & items" -> "eggs & gems"; no new local), `src/server/Services/PetService.lua` (`buildPrompts` adds `ShopPrompt`; no new top-level local)
- Modify: `src/client/Controllers/TopBarController.lua` (`PillButton_Shop`: the Shop on the last tab of this session, first time Eggs; a second tap closes it), `src/client/Controllers/PetsController.lua` (only if `OpenShop` does not land on Eggs through `menu.Open("Shop", {})`). `TutorialController.lua` is NOT changed (review 2026-11-07, spec 16.3 "Tutorial": `HOOK_FOR` only picks the click hook and `findMenuButton` never searches `PillButton_`, so `HOOK_FOR.ShopOpened = "Shop"` would find nothing; the shop step keeps its world arrow and completes on `WindowOpened("Shop")`)
- Modify: `tools/smoke_lobby_shop_world.lua` (`shop_prompt`), `tools/smoke_shop_ui.lua` (`client_shop_openers`), `tools/smoke.py` (both lines)
- Rewrite (keep names): `smoke_hud_items.lua` `huditems_gone` (if it counts every prompt on the island: `ShopPrompt` is new, `ItemShopPrompt` stays gone), `smoke_lobby_shop_world.lua` `lobby_trove_plaza` (Task 10: the Egg Guide's children include `PromptPart`), `smoke_polish_worldtext.lua` `polish_worldtext` (the arch caption), `smoke_hud_pill.lua` `client_hudpill` (the Shop pill toggles the Shop); the `client_bug2tut_*` scenarios that pin "ShopOpened has no button" stay as they are (still true)

**Interfaces:**
- Produces: `LobbyInfo.Shop.Counter`; `ShopPrompt` (`ActionText "Open"`, `ObjectText "Shop"`, `HoldDuration 0`, `MaxActivationDistance 10`, `RequiresLineOfSight false`) firing `OpenPanel("Shop", { Tab = "Eggs" })` after a live-player, not-`InMatch`, `rateLimited(player, "Prompt_Shop", PROMPT_COOLDOWN)` check; rebuilt with the machine prompts; a missing part warns once.

- [ ] **Step 1: Failing tests**
  - `shop_prompt` (server, booted): the Egg Guide's `PromptPart` invisible, `CanCollide false`, at `cf * (0, 2, -5.6)` (+-0.1); `LobbyInfo.Shop.Counter.PromptPart` is it; one `ShopPrompt` on it with the properties above; a trigger fires one `OpenPanel` ("Shop", `{ Tab = "Eggs" }`) to that player; a second within `PROMPT_COOLDOWN` none; `InMatch` none; the forced fallback shop (`LobbyBuilder._ForceShopFallback`) has its `Counter` and the prompt; lobby rebuilt (Review Focus 4) -> exactly one `ShopPrompt`, on the new part; the arch sign reads "eggs & gems"; the four machine prompts unchanged
  - `client_shop_openers` (client): `OpenPanel("Shop", { Tab = "Eggs" })` -> Eggs; `OpenPanel("Shop", { Tab = "Roulette", RouletteId = "Storm" })` -> `ShopCard_Storm` focused; `OpenPanel("Shop", { RouletteId = "Secret", Currency = "Gems" })` -> `ShopCard_Secret` focused; `OpenPanel("Store", { Tab = "Passes" })` -> the Shop on Passes; `PillButton_Shop`: first press -> Eggs, switch to Gems, close, press -> Gems, press again while open -> closed; PetsController's `OpenShop` -> Eggs; with the tutorial's shop step active, opening the Shop through `PillButton_Shop` (and, separately, through `OpenPanel("Shop", ...)`) completes `ShopOpened` once (`WINDOW_EVENTS`), and the step's world arrow is unchanged (no ring on the pill)
- [ ] **Step 2: Register** `"shop_prompt"` on the `smoke_lobby_shop_world.lua` line and `"client_shop_openers"` on the `smoke_shop_ui.lua` client list. **Run** -> FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Rewrite** the listed scenarios.
- [ ] **Step 5: Run** `shop_prompt,client_shop_openers,lobby_trove_plaza,huditems_gone,polish_worldtext,client_polish_worldtext,client_hudpill,client_hudpill_mobile,client_pets,client_tb_pets_actions,client_bug2tut_mouse,client_bug2tut_portrait,client_bug2tut_raidnext,client_storm,storm_altar,lobby,p6lobby_server,contract` -> PASS. PetService 80, LobbyBuilder 154, LobbyBoardBuilder <= 44. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): walk up to the shop's Egg Guide and press E to open the Shop; every opener lands on the right tab`

**Only Studio can judge:** the E prompt beside the Celestial machine (only the nearest shows), on PC and a phone.

### Task 24: The board's SurfaceGui (LeaderboardController)

Spec: 5.10 "Client" (pages per section 15). Unchanged from the first plan's Task 20. Skills: roblox-dev:roblox-ui.

**Files:**
- Create: `src/client/Controllers/LeaderboardController.lua`
- Modify: `src/client/Main.client.lua` (boot after `"ShopController"`; `OPTIONAL`)
- Modify: `tools/robloxmock.lua` (client `Players:GetUserThumbnailAsync` if missing), `tools/dump_gui.lua` (`lobbyboard[:2|:3]`), `tools/render_gui.py`
- Create: `tools/smoke_lb_ui.lua` (client world)
- Modify: `tools/smoke.py`, `tools/contract.json` (`client/Controllers/LeaderboardController`: `Init`, `Page`, `SetPage`, `State`)

**Interfaces:**
- Consumes: `LeaderboardState` and `Config.Leaderboard` (Task 9); the `LobbyLeaderboard.Face` part (Task 11).
- Produces:
  - `LeaderboardController.Init()`, `Page() -> stat`, `SetPage(stat)` (the tap path; restarts the 15 s turn), `State() -> payload | nil`.
  - SurfaceGui `LobbyLeaderboard` in PlayerGui: `Adornee` = the workspace `LobbyLeaderboard.Face` (found by name; a newly built board re-adorns it), `Face = Front`, `SizingMode = PixelsPerStud`, `PixelsPerStud = 50` (800 x 650 px), `MaxDistance = 80`, `ResetOnSpawn = false`, `LightInfluence = 0` > `Board` > `Title` (50 px, `Config.Leaderboard.Titles[stat]`), `Tabs` > `Tab_<stat>` per `Pages` (TextButtons with `Labels`), `Scope` ("All players \194\183 all time" / "This server only"), `Rows` > `Row1..10` (`Rank`, `Head` 34 px ImageLabel, `Name`, `Value`; ranks 1-3 gold, silver, bronze), `YouRow` ("You \194\183 1,240 \194\183 #37" / "You \194\183 1,240 \194\183 not in the top 100" / "You \194\183 ..."), `Footer` ("Refreshes in m:ss \194\183 tap a tab, or it turns in 0:ss" from `NextAt` with `workspace:GetServerTimeNow()`), `Status` ("Loading scores..." / "No scores yet. Be the first!"). Every text >= 30 px; values with commas, `Theme.ShortNumber` from 1e6.
  - Headshots: `Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)` in a pcall'd task, cached per user (no `rbxthumb://` literal: check.mjs's asset-id rule).

- [ ] **Step 1: Failing test `client_leaderboard`**: before any state `Status` reads "Loading scores..."; the SurfaceGui is under PlayerGui with `Adornee` = the Face; a state with ten rows and `You = { Rank = 37, Value = 1240 }` fills `Row1..10` (top three coloured) and `YouRow` "You \194\183 1,240 \194\183 #37"; `Rank = nil` -> "not in the top 100"; `Value = nil` -> "You \194\183 ..."; Scope `"Server"` -> "This server only"; three tabs; `SetPage("Pets")` -> "TOP PETS FOUND"; the page turns by itself after 15 s, and a tap at 10 s moves the turn to 25 s; `NextAt = now + 220` -> the footer starts "Refreshes in 3:40"; an empty page -> "No scores yet. Be the first!"; every text >= 30 px; long names (Review Focus 6): a 20-character name and a value of 1e12 -> the name fits its box (`TextFits` or truncated), the value reads "1T", sizes unchanged; lobby rebuilt (Review Focus 4): destroy the board model and build a new one -> `Adornee` is the new Face within 1 s and the rows still show the last state.
- [ ] **Step 2: Register** `if p5("smoke_lb_ui.lua"): client_files.append("smoke_lb_ui.lua"); ins(client_scenarios, "client_final", ["client_leaderboard"])  # [lobby-shop, Task 24] the board's SurfaceGui (smoke_lb_ui.lua)`
- [ ] **Step 3: Run** -> FAIL. **Step 4: Implement.**
- [ ] **Step 5: dump_gui** `lobbyboard`, `lobbyboard:2`, `lobbyboard:3` (the board's canvas with ten fake rows); render at 844x390 and 1920x1080; look at them against `boardA`.
- [ ] **Step 6: Run** `client_leaderboard,client_polish_worldtext,client_gui_dump,contract` -> PASS. LeaderboardController <= 50. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the lobby board shows the global top 10 with tappable pages`

**Only Studio can judge:** the board's tabs tapped in the world on a phone and on PC; reading distance.

### Task 25: Lobby motion, the Join sign per player, the shelf turntable (LobbyFxController)

Spec: 5.12, 5.9 (the billboard hidden for a player who claimed), 16.5 (the eggs tagged `NC_Spin`). The first plan's Task 21 plus the shelf eggs. Skills: roblox-dev:roblox-performance.

**Files:**
- Create: `src/client/Controllers/LobbyFxController.lua`
- Modify: `src/client/Main.client.lua` (boot; `OPTIONAL`)
- Modify: `src/server/Services/LobbyBoardBuilder.lua` (`EggGuide`: each `Egg_<Rarity>` tagged `Config.Tags.Spin` with `SpinSeconds = 14`, `BobStuds = 0.12`, `BobSeconds = 3.2`)
- Create: `tools/smoke_lobby_fx.lua` (client world)
- Modify: `tools/smoke.py`, `tools/contract.json` (`client/Controllers/LobbyFxController`: `Init`, `Step`, `Moving`)
- Rewrite (keep names): `smoke_lobby_shop_world.lua` `lobby_trove_plaza` (Task 10: the seven eggs carry the tag and the three attributes)

**Interfaces:**
- Consumes: tags `Config.Tags.Spin` / `Config.Tags.Bob` and their attributes (Tasks 10, 13, 14, this task); `Config.Attr.TroveGroupDone` (Task 10).
- Produces: `LobbyFxController.Init()`, `Step(dt)` (one frame; tests), `Moving() -> { inst... }` (the targets moved on the last step). One Heartbeat for all: `NC_Spin` turns a Model / Part about its built pivot's Y at 360 / `SpinSeconds` degrees a second and bobs it `BobStuds * sin(2 pi t / BobSeconds)` (from the built pivot, never accumulating); `NC_Bob` sets a BillboardGui's `StudsOffset.Y = base + BobStuds * sin(...)`; only targets within 150 studs of the camera; Gfx Low (the quality read `PortalFxController` uses) -> nothing moves and targets rest at their built pivot; any `JoinBillboard` gets `Enabled = false` while `LocalPlayer:GetAttribute(Config.Attr.TroveGroupDone) == true`, including one built after a rebuild.

- [ ] **Step 1: Failing test `client_lobby_fx`**: a tagged part 50 studs away turns (its Y angle changes) within 1 s and bobs within +-0.6; one 200 studs away stays put; an `Egg_Epic` part on a shelf turns once in 14 s (+-0.5 s) and bobs within +-0.12; Gfx Low -> nothing moves; a tagged BillboardGui's `StudsOffset.Y` varies within +-0.5 of its base; `TroveGroupDone` true -> `JoinBillboard.Enabled == false`, absent -> true; lobby rebuilt (Review Focus 4): destroy and re-create the trove (a new `JoinBillboard`), a spin target and the Egg Guide -> the new billboard hidden for the done player, the new targets move, the old ones leave `Moving()`, no error.
- [ ] **Step 2: Register** `if p5("smoke_lobby_fx.lua"): client_files.append("smoke_lobby_fx.lua"); ins(client_scenarios, "client_final", ["client_lobby_fx"])  # [lobby-shop, Task 25] lobby motion (smoke_lobby_fx.lua)`
- [ ] **Step 3: Run** `--only client_lobby_fx,lobby_trove_plaza` -> FAIL. **Step 4: Implement.**
- [ ] **Step 5: Run** `client_lobby_fx,lobby_trove_plaza,shop_prompt,client_trove,client_storm,contract` -> PASS. LobbyFxController <= 30, LobbyBoardBuilder <= 44. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): one client heartbeat spins the world gem, the altar ring and the shelf eggs, and bobs the Join sign`

### Task 26: Painted eggs A: the GUI paint, egg VFX, shelf sparkles, the Secret chat colour

Spec: 16.5 (all of it). Skills: roblox-dev:roblox-ui, roblox-dev:roblox-performance (instance and tween budgets).

**Files:**
- Modify: `src/client/UI/EggArt.lua` (the three forms, `Paint(rarity)` per the 16.5 table, the Epic-and-up light layer, `opts.Vfx`)
- Create: `src/client/UI/HatchFx.lua` with `Pool(parent, n)`, `Stars(parent, n)`, `Stats()` (Task 27 adds the rest)
- Modify: `src/client/UI/ShopEggs.lua` (the Secret hero egg Full with `Vfx`; the domes' slow glass sheen; a page-owned `HatchFx.Pool` of 16, stopped while the page is hidden), `src/client/UI/EggStage.lua` (strip cells Medium with a static rarity ring for Rare and up; only the landed cell gets its VFX)
- Modify: `src/server/Services/LobbyBoardBuilder.lua` (`EggGuide`: the sparkle `ParticleEmitter` on Rare-and-up eggs at their `Center`, tagged `DETAIL_TAG`; one `PointLight` `EggShelfGlow` 1.0 / 10 at the shelf centre)
- Modify: `src/shared/Config.lua` (`Eggs.ChatColors = { Secret = Color3.fromRGB(180, 150, 255) }`), `src/client/Controllers/NotifyController.lua` (the chat line's rarity word uses `ChatColors[rarity]` when set)
- Modify: `tools/dump_gui.lua` (`eggs` = the seven eggs at 30 / 64 / 104 / 160 / 380 px, Full ones with `Vfx`; `eggs:simple`), `tools/render_gui.py`, `tools/smoke_egg_stage.lua` (`client_egg_vfx`), `tools/smoke_lobby_shop_world.lua` (`egg_shelf_fx`), `tools/smoke.py` (both lines), `tools/contract.json` (`client/UI/HatchFx`: `Pool`, `Stars`, `Stats`)
- Rewrite (keep names; built tests): `smoke_egg_stage.lua` `client_egg_art` (Task 20: forms and paint), `smoke_eggs.lua` `client_notify_pull` (Task 6: Secret's word colour), `smoke_p5_world.lua` `bb6_lobby_lights` (the new light in the census)

**Interfaces:**
- Produces: EggArt forms by size (Simple < 48 px <= 8 instances; Medium 48-140 <= 14; Full > 140 <= 28); `Paint(rarity)` returns the motif list of the 16.5 table as `{ Kind = "Spots" | "Dots" | "ZigzagBand" | "Bands" | "StarBand" | "Trim" | "Stars" | "Crown" | "Gems" | "Swags" | "WaveBands" | "Ribbon" | "Swirls" | "Cracks" | "Runes" | "Shine", Count = n }` entries; a `Vfx` egg (Rare and up) adds <= 8 instances and <= 3 tweens; Low graphics: no sheen, no sparkles; `HatchFx.Pool(parent, n)` -> `pool:Burst(at, rarity, count)`, `pool:Live()`, `pool:Destroy()`, one Heartbeat while any spark lives.

- [ ] **Step 1: Failing tests**
  - `client_egg_art` (rewritten): the form chosen by size, each within its instance cap; `Paint(r)` per rarity equals the 16.5 table (kinds in order; Simple keeps the first motif only); the Epic-and-up light layer present from Epic, absent below; `SetRarity` across all seven keeps a Full egg within 28 instances and leaves no orphan
  - `client_egg_vfx`: `Vfx = true` on Common / Uncommon adds nothing; on Rare .. Secret adds <= 8 instances and <= 3 tweens (Secret's twinkles counted in its 3 + the stars pool); Low graphics -> none; the Shop page's pool never exceeds 16 live sparks and has no live Heartbeat while the page is hidden; destroying a `Vfx` egg stops its tweens and returns its sparks; census: no `"\226\151\134"`
  - `egg_shelf_fx` (server): Rare .. Secret eggs each hold one `ParticleEmitter` with Rate 1 / 2 / 3 / 4 / 5 in the rarity colour, tagged `DETAIL_TAG`; Common and Uncommon none; one `PointLight` `EggShelfGlow` 1.0 / 10; every lobby light within the light rule; the trove and the shelf part counts within their budgets
  - `client_notify_pull` (rewritten): a Secret pull's chat line colours "SECRET" rgb(180,150,255); a Legendary keeps the `Config.Rarities` colour
- [ ] **Step 2: Register** `"client_egg_vfx"` on the `smoke_egg_stage.lua` client list and `"egg_shelf_fx"` on the `smoke_lobby_shop_world.lua` line. **Run** `--only client_egg_art,client_egg_vfx,egg_shelf_fx,client_notify_pull` -> FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: dump_gui `eggs` and `eggs:simple`**; render at 844x390 and 1920x1080 and look at every egg at every size beside renders of the painted eggs from the committed manifests (`py -3.12 tools/render_model.py meshkey:egg_<rarity>`; not `blender/out`, which is git-ignored and missing in any other worktree; first check `git log -1 -- src/shared/MeshManifests/egg_secret.lua` shows the painted rebuild's commit, else stop: the Task 16 pre-flight was skipped): the same motifs, readable at 30 px, clean outlines, no stray frame.
- [ ] **Step 5: Run** the four plus `client_egg_stage,client_egg_stage_mobile,client_shop_eggs,client_shop_mobile,lobby_trove_plaza,bb6_lobby_lights,p5world_lobby,client_gui_dump,contract` -> PASS. EggArt <= 50, HatchFx <= 30, ShopEggs <= 60, EggStage <= 90, LobbyBoardBuilder <= 48. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(lobby-shop): painted eggs everywhere in the GUI with rarity VFX; shelf sparkles and glow; Secret's chat colour reads on dark chat`

**Only Studio can judge:** the shelf sparkles at night from the shop island; the eggs on a real phone at 30 px.

### Task 27: The egg-opening cutscene (storyboard A "Pedestal")

Spec: 16.4 (all of it). Build storyboard A unless the main session publishes a storyboard pitch first and the owner picks B or C (then only the `Rise` phase changes, as 16.4 describes). Skills: roblox-dev:roblox-ui, roblox-dev:roblox-performance.

**Files:**
- Modify: `src/client/UI/EggStage.lua` (the dressed phases: `Vignette`, `Title` slide, speed streaks, `Spot`, `Pedestal1..3`, `Backlight1..3`, the push-in, the banner, confetti, the Secret backdrop, the gold flash on the best pull's burst; Skip's 0.25 s burst-tail overlay over the reveal's start; the phase runner's pcall and `teardown(reason)`)
- Modify: `src/client/UI/HatchFx.lua` (`Rays`, `Shock`, `Cracks`, `Leaks`, `Dim` = `Lighting.NimbusHatchBlur` (the one new effect) + `LightingStack.Push("Hatch", { ColorCorrection = { Brightness = <current> - 0.08, Saturation = <current> - 0.25 } }, 0.35)` with the currents from `LightingStack.Value("ColorCorrection", prop, "Hatch")`, popped (`LightingStack.Pop("Hatch", 0.35)`) by teardown; High graphics only; `Pool:Confetti`; `Stats` complete). No ColorCorrectionEffect is created (review 2026-11-07: LightingStack finds its target with `FindFirstChildOfClass`, so a second one could become its target and be destroyed with its values)
- Modify: `tools/robloxmock.lua` (if missing: `BlurEffect` under `Lighting`; Camera `CameraType` / `CameraSubject` / `FieldOfView` readable; the real `LightingStack` runs on the mock's `Lighting`)
- Modify: `tools/dump_gui.lua` (scenes `hatch:<rarity>@<seconds>` = a forced pull of that rarity stepped to that time, for x1 and `hatch3:...` for x3; the old `hatch:*` names kept as aliases), `tools/render_gui.py`
- Modify: `tools/smoke_egg_stage.lua` (`client_hatch_cutscene`), `tools/smoke.py` (its line), `tools/contract.json` (`client/UI/HatchFx` complete)
- Rewrite (keep names; built in Task 20): `client_egg_stage` (the phase visuals it names), `client_egg_stage_mobile` (the dressed pedestals, lips and banners under Task 20's per-phase NoOverlap lists and fit rule; the resize also during `Crack`)

**Interfaces:**
- Produces: spec 16.4 storyboard A, x3, layouts (the fit rule: egg and pedestal shrink with the middle; the phone reveal's lip and Banner), the VFX table and its budget (x1 <= 450 instances, x3 <= 750, <= 24 live tweens plus the Secret stars, <= 1 Heartbeat, 1 Lighting effect + the `"Hatch"` LightingStack preset); spark counts Common 12, Uncommon 16, Rare 20, Epic 28, Legendary 40, Mythic 48, Secret 48, confetti 24 (Mythic, Secret), halved on Low; Low: no blur, no tint, static rays, no streaks.

- [ ] **Step 1: Failing test `client_hatch_cutscene`** (1920x1080, Gfx High unless stated):
  - per phase: `Intro`: `Dim` fades in, `Lighting.NimbusHatchBlur.Size` reaches 14, `LightingStack.Ids()` contains `"Hatch"` and `Lighting` holds exactly the ColorCorrectionEffects it held before the roll (none added), and the tint reaches Brightness / Saturation 0.08 / 0.25 under their values before (High only; on Low no blur and no `"Hatch"`); `Rise`: `Spot`, `Pedestal1`, `Backlight1` shown, `Egg1` 380 px tall; `Crack`: `CrackWord` "EPIC EGG!", `Egg1.Rotation` not 0 during the shakes, `Cracks` segments 1 -> 3 -> 5, the hero's push-in `UIScale` <= 1.06; `Burst`: `Shock` grows, `Rays` shown, 28 live sparks for Epic (14 on Low), the white micro-flash, no gold `Flash`; Legendary: the gold `Flash` once; `Reveal`: `Banner.Word` "EPIC!", the pet's `UIScale` ends at 1; Mythic and Secret: 24 confetti; Secret: 14 stars
  - budgets at every phase from `EggStage.Stats()` and `HatchFx.Stats()` within the caps; after DONE all zero, no `NimbusHatchBlur` in `Lighting`, `"Hatch"` gone from `LightingStack.Ids()` and the ColorCorrection values back to their values before the roll, no live Heartbeat
  - x3 with pulls Rare, Legendary, Common: `Egg1` bursts first, `Egg2` 0.6 s later, `Egg3` 1.2 s later (pull order, never re-sorted); the gold `Flash` once, on `Egg2`'s burst; Reveal at 7.15 +- 0.1 (fast 2.66)
  - Skip (spec 16.4 "Skip", one rule): Skip during `Intro` of a Legendary -> `Phase() == "Reveal"` on the next frame, and over the next 0.25 s the burst-tail overlay shows the gold `Flash` exactly once; the same for an Epic -> no gold `Flash` and no white micro-flash; no sound left playing
  - never breaks the player (Review Focus 3): record Camera `CameraType` / `CameraSubject` / `FieldOfView`, the Humanoid's `WalkSpeed` / `JumpPower`, the MouseLock state and `GuiService.TouchControlsEnabled`; equal after DONE, after a match start mid-`Crack`, after `EggStage._InjectPhaseError = "Crack"` (a test-only hook, nil by default, reset in every path) and after `MenuController.Close()`. `ShopWindow` (review 2026-11-07): visible again after DONE and after the injected error; after the mid-`Crack` match start and after `MenuController.Close()` hidden, `ShopController.IsOpen() == false` and `GuiService.TouchControlsEnabled == true` (on a touch device). The character removed mid-`Strip` (a new one added): the stage stays and still reaches `Reveal`; after DONE the recorded values match (the new Humanoid's `WalkSpeed` / `JumpPower`)
- [ ] **Step 2: Register** `"client_hatch_cutscene"` on the `smoke_egg_stage.lua` client list. **Run** `--only client_hatch_cutscene` -> FAIL.
- [ ] **Step 3: Implement** HatchFx, then the EggStage phases.
- [ ] **Step 4: Rewrite** `client_egg_stage`, `client_egg_stage_mobile`.
- [ ] **Step 5: Look at it** (the owner asked for "clean and astonishing"): dump and render `hatch:epic@` 0.2 / 1.5 / 3.4 / 3.9 / 4.6 / 5.3 / 5.9, the same for Legendary and Secret, and `hatch3:...` at 4.5 / 6.0 / 7.3, at 1920x1080 and 844x390; tile each set into one contact sheet in `<evidence>\t27\`; check every frame: nothing clipped by the inset, text readable, the egg centred on the pedestal, effects inside the screen, no frame where the screen goes flat white. Fix and re-render until it reads well; list the sheets in the ledger.
- [ ] **Step 6: Run** `client_hatch_cutscene,client_egg_stage,client_egg_stage_mobile,client_egg_stage_wiring,client_egg_vfx,client_shop_eggs,client_audio_sites,client_audio_keys,client_dgfix_mouse,client_release_roulette,client_gui_dump,contract` -> PASS. EggStage <= 110, HatchFx <= 60. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(lobby-shop): the egg-opening cutscene: the world dims, the egg rises onto a pedestal, glowing cracks, a burst of rays and sparks; Skip any time; the camera is never touched`

**Only Studio can judge:** the blur and tint on real devices (the tint over the day / night sky and inside a dungeon, where other LightingStack presets sit); the feel of the shakes and the burst; the sounds at 0.6 and full volume; a forced Secret with dev gems.

### Task 28: Blender: inspect and fix the painted eggs (same keys; committed before Task 16)

Spec: 16.5 "The world eggs", 11. Skills: the owner's Blender rules (`ABSOLUTE_RULES.md`, global CLAUDE.md "3D models: Blender only").

At plan time the working tree held an uncommitted painted rebuild of `lobby_egg` (`blender/kit/props/lobby_shop.py`, `blender/catalog/lobby.json`, `blender/meshes.json`, the seven `src/shared/MeshManifests/egg_*.lua`). Since the review of 2026-11-07 the main session commits it on its own before Task 16 (the Task 16 pre-flight), so Task 26 compares against it from the committed manifests and this task only inspects, fixes and commits its own fixes (staged by name). Before starting, confirm with `git -C <worktree> log -1 -- src/shared/MeshManifests/egg_secret.lua`; if it is somehow still uncommitted, ask the main session (never discard it, never stash it).

**Files:**
- Modify: `blender/kit/props/lobby_shop.py` (`@prop("lobby_egg")`: the seven painted sets of the 16.5 table, keys `egg_common` .. `egg_secret`, shape and pivot unchanged, `Glow<What>` Neon parts from Epic up; docstring), `blender/catalog/lobby.json` (descriptions)
- Generated (commit with the kit change): `src/shared/MeshManifests/egg_*.lua`, `blender/meshes.json`

- [ ] **Step 1: Build** `%USERPROFILE%\.bpyenv\Scripts\python.exe blender/build_all.py --key egg_<rarity> --preview` for each of the seven; `py -3.12 blender/kit/selftest.py` -> ok; `py -3.12 tools/mesh_budget.py` -> within budget.
- [ ] **Step 2: Inspect.** In Blender through the `blender` MCP when it is connected (import each `blender/out/egg_<rarity>.fbx`, render front, three-quarter, side and top beside a 5-stud reference); otherwise the kit previews plus `py -3.12 tools/render_model.py meshkey:egg_<rarity> -o <evidence>\blender\egg_<rarity>.png --views front,threequarter,side,top`. Check: the paint reads from the shelf distance and close up, outlines clean, no floating or buried detail, normals, the Glow parts named `Glow<What>`, the seven side by side read as a rising set; compare with the GUI eggs of Task 26 (the same motifs). Fix and rebuild until it reads. Say in the ledger which way was used.
- [ ] **Step 3: Run** `py -3.12 tools/mesh_names.py --check blender/out/egg_*.manifest.json` -> ok; `py -3.12 tools/smoke.py --quick --mesh --only lobby_trove_plaza,egg_shelf_fx` -> PASS (the dressed eggs keep the shelf layout, the emitters and the tag).
- [ ] **Step 4: Commit** (only when Steps 1-2 changed something; stage the changed kit / catalog / manifest files by name) `art(lobby-shop): the painted eggs, fixes after inspection (<what>)`

### Task 29: Blender: `portal_altar_ring`, and the mesh-key check

Spec: 5.11 (b) (the ring), 8 (`tools/mesh_keys.py`), 11 (renders before the gate). The first plan's Task 22, unchanged. Skills: the owner's Blender rules (`ABSOLUTE_RULES.md`, global CLAUDE.md "3D models: Blender only").

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

### Task 30: Blender: `prop_board_lb`

Spec: 5.10 "World" (the board prop), 11. The first plan's Task 23, unchanged. Skills: as Task 29.

**Files:**
- Modify: `blender/kit/props/lobby_shop.py` (new `@prop("lobby_board_lb")`; docstring), `blender/catalog/lobby.json` (key `prop_board_lb`, `"budget": "propBig"`; preview `lobby_prop_board_lb`)
- Generated: `src/shared/MeshManifests/prop_board_lb.lua`, `blender/meshes.json`

**Interfaces:**
- Consumes: Task 11's board layout (pivot = ground centre, front -Z; posts 1 x 17 x 1 at x +-8.9; a 0.6-stud frame around the 16 x 13 face centred 9.5 up; roof 18.6 x 0.6 x 2.4 at y 16.9 with a ridge).
- Produces: key `prop_board_lb`: two timber posts on stone footings, the frame (the face itself is NOT in the mesh: the game keeps the `Face` Part for the SurfaceGui), a small shingled roof, brass corner caps, wear on the post feet; the lobby's palette and fine-voxel family (`props/lobby.py` / `lobby_trove.py`); attachment `FaceCenter` at (0, 9.5, -0.2).

- [ ] **Step 1: Write the prop and the catalog entry.**
- [ ] **Step 2: Build** `%USERPROFILE%\.bpyenv\Scripts\python.exe blender/build_all.py --key prop_board_lb --preview`; `py -3.12 blender/kit/selftest.py` -> ok.
- [ ] **Step 3: Inspect** as Task 29 step 4 (`meshkey:prop_board_lb` and the `lobby` target: the board on the south lawn beside a 5-stud player, the face opening exactly 16 x 13).
- [ ] **Step 4: Run** `py -3.12 tools/mesh_keys.py --check` -> PASS; `py -3.12 tools/mesh_names.py --check blender/out/prop_board_lb.manifest.json` -> ok; `py -3.12 tools/mesh_budget.py` -> within budget; `py -3.12 tools/smoke.py --quick --mesh --only lb_world,client_leaderboard` -> PASS.
- [ ] **Step 5: Commit** `art(lobby-shop): the leaderboard board mesh (prop_board_lb)`

### Task 31: Docs, evidence and the gate

**Files:**
- Modify: `README.md` (the Shop with its tab rail and Eggs / Gems tabs, the walk-up prompt, egg rolls x1 / x3, the cutscene, Skip and Fast hatch, the Secret pity, Celestial's 2% Secret, the painted eggs, the gem look, the gem XP Potion, the trove at spot C, the leaderboard's three pages, the titles and the Rank column, the altar portals; the price tables are Task 16's), `BUILD_STATE.md` (one dated entry in "Player decisions" in the shape of the 2026-11-06 entries: branch, spec, plan, what landed, the calls of spec 13, section 15 and 16.8, what only Studio can judge), `brain.md` (one dated decision line)
- Evidence: `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.superpowers\lobby-shop\evidence\`

- [ ] **Step 1: Docs.** Run `--only p2final_docs` and fix what it reports.
- [ ] **Step 2: Evidence renders:** `py -3.12 tools/render_gui.py <scene> --size 844x390 -o <evidence>\<scene>_phone.png` and `--size 1920x1080 ... _pc.png` for `shop` (Eggs), `shop:Gems`, `shop:Packs`, `shop:Passes`, `shop:Boosts`, `shop:restricted`, the Task 27 cutscene frames (Epic, Legendary, Secret, x3), `eggs`, `eggs:simple`, `gems`, `titles`, `lobbyboard`, `lobbyboard:2`, `lobbyboard:3`; `shop`, `shop:Gems` and the reveal frames also at 640x360, 1280x720, 1366x768, 360x640, 390x844. Model renders (`tools/render_model.py`): `gem_world`, `portal_ring`, the seven painted `egg_<rarity>`, `portal_altar_ring`, `prop_board_lb`, several angles beside a 5-stud player; the plaza with the trove at C. Look at every image: the reports' smallest text >= 14 px, targets >= 44 px, inside the screen and under the inset, no overlaps. List them in the ledger.
- [ ] **Step 3: Fast signal** (speed scout): `py -3.12 tools/smoke_parallel.py --quick --json <scratch>\par.json`; fix any failure in its owning task's files (commit as `fix(lobby-shop): ...`).
- [ ] **Step 4: The gate** (one run each, nothing else changing meanwhile): `py -3.12 tools/smoke.py --quick --json <scratch>\gate.json` -> 0 failed; `py -3.12 tools/smoke.py --quick --mesh` -> 0 failed; `node tools/check.mjs` -> 0 errors; `py -3.12 tools/count_locals.py` -> no file at 200 (report MenuController < 160, LobbyBuilder <= 159, DataService 160, HudController 161, PetService 80, Main.server 58, ShopController, ShopEggs, ShopGems, EggStage, HatchFx, EggArt, LeaderboardService, TitleController); `py -3.12 tools/sim_tycoon.py --check` -> ok and `--gems` -> its checks ok; `py -3.12 tools/mesh_budget.py`; `py -3.12 tools/mesh_names.py --check blender/out/*.manifest.json`; `py -3.12 tools/mesh_keys.py --check`.
- [ ] **Step 5: Commit** `gate(lobby-shop): Shop A, egg cutscene, painted eggs, titles, the owner's prices, trove at C, leaderboard, altar portals; whole smoke <passed> / 0 failed, --mesh <n> / 0, check.mjs 0 errors, sim_tycoon --check and --gems ok`, push, ledger line with the numbers and the evidence list. No merge.

**Only Studio can judge (spec 10 and 16, minus the Climb timing that section 15 dropped):** the lobby from the spawn on PC and a phone emulator (the trove at C, the board, the Altar gate); walking the lawn paths; the board's tabs; the Join sign bobbing; the walk-up E prompt; the Shop and full rolls (x1, x3, Skip, Fast hatch, a Celestial Secret and a forced Secret with dev gems); the cutscene's blur and burst on real devices; titles above heads (the rainbow fade) and the Rank column in a live server; the Creator tag on the owner's account; the beam, the summon ring and the return ring at night; the Altar's vortex beside the Obby's; live leaderboard reads after publish.

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

## Rework (2026-11-07): the owner's pitch answers

After Task 15 (1e733f7) the owner answered the pitch (spec section 16). Tasks 1-15 stay as built; Task 8 never landed (it stopped at its pre-flight while the prices were open). The first plan's Tasks 16-24 are replaced by Tasks 16-31:
- old 16 (egg art and the stage) -> 20 (the core: request path, phases, timings), 26 (painted eggs and VFX), 27 (the cutscene);
- old 17 (Cloud Shop B and the move out of MenuController) -> 21 (the Store becomes the Shop window A) and 22 (the Eggs tab, the move out);
- old 18 (the Gems tab) -> 21; old 19 (the Store's Eggs tab and the pulsing Store button) -> dropped (one window, no Store button to pulse);
- old 20, 21, 22, 23, 24 -> 24, 25 (plus the shelf turntable), 29, 30, 31: the same work, renumbered;
- new: 16 (the owner's prices, replaces 8), 17 (the trove to C), 18-19 (titles), 23 (the walk-up prompt and every opener), 28 (the painted Blender eggs).

Built tests rewritten by the rework: Task 16 rewrites `egg_roll_pure`, `egg_full_stack`, `secret_pity`, `gem_settle`, `gem_potion_buy`, `p2gems_odds`, `storm_pet`; Task 17 `lobby_trove_plaza`, `trove_build`; Task 21 `client_gem_icon` and the Store suites (`smoke_store_ui`, `smoke_fixr_store_ui`, `smoke_store`, `smoke_hud_pill`, `smoke_fixr_daily_ui`); Task 22 `client_shop_window` and the old Cloud Shop suites; Tasks 23 and 25 `lobby_trove_plaza`; Task 26 `client_egg_art`, `client_notify_pull`, `bb6_lobby_lights`; Task 27 `client_egg_stage`, `client_egg_stage_mobile`.

Found while planning: the working tree holds an uncommitted painted rebuild of the seven Blender eggs (`blender/kit/props/lobby_shop.py` and its generated files); section 16.5 adopts its paint for the GUI eggs; since the review below, the main session commits it on its own before Task 16 and Task 28 inspects it. Gemini was not consulted for this rework (ask-gemini answered 402, credits depleted).

## Rework review (2026-11-07): findings on spec 16 and Tasks 16+

Sixteen findings (2 major, 14 minor). Each was checked against the code at 1e733f7 (`StoreController.lua` 1625-1634 and 1440-1487, `NeonKit.BigRect` with the new RECT, `Theme.ScreenFactor`, `LightingStack.lua` 36 / 57, `GraphicsQuality` (Low / High only), `Main.server.lua` 301 / 370 with `PlayerService.setupPlayer`, `TutorialController` 176-179 / 1907-1969, `tools/sim_tycoon.py` 146-147 / 558, `smoke_p4_economy.lua` 985 / 991 / 1006, `smoke_redo_geom.lua`'s NoOverlap rule, `VipController` K, `PetCatalog`'s Secret pets, `Config.Store.Items`, `StoreService.PromptPurchase`, `GemService.PolicyState`, `.gitignore`). All sixteen were real and all are folded into spec 16 and Tasks 16-28 above. **None was rejected.** Taken in a different form than proposed, or one of two options chosen:
- **The Shop after the cutscene (major).** As proposed, plus the mechanism: `Closed(reason)` carries `"Done"` / `"Error"` / `"Match"` / `"Close"`, ShopController shows the window only for the first two while still open and not `InMatch`, and `closeEverything` closes the Shop before the stage. "Character removal leaves the Shop closed" fell away because of the death finding (the stage now plays on through a respawn).
- **Phone fit of the crack and reveal (major).** As proposed (egg and pedestal shrink to 0.6, a lip under the phone reveal pet, a phone Banner size), generalised: a pedestal is always 1.1 x / 0.24 x its egg on every layout, which also sizes the x3 pedestals the spec never gave. The proposed single NoOverlap list `{ CrackWord, Egg1, Pedestal1, Banner, Name, Note, SpinAgain, Done, Skip, FastHatch }` was NOT used as written: `RedoGeom.check` fails on any listed name that is not shown (Banner is hidden during Crack, CrackWord on the reveal) and checks only the first descendant of a name (x3 columns), so the lists are per phase, with per-column checks for x3. The existing 1280x720 / 1366x768 sizes stay in the run.
- **Rail and card heights by body.** As proposed (44 px tabs at `4 + i * 49` under a 276 px body; cards `min(266, body - 12)`), extended to the Gems tab's phone tiles, which share the row height.
- **Titles at distance.** As proposed (the crown drawn inside the TitleTag when titled; the tag raised by a pixel `SizeOffset`); the stud anchor (2.0) is a Studio check. The proposed `dump_gui` shots became `titles:<studs>` scenes using the `portal` scene's existing distance projection.
- **Esc owner.** The first option (ShopController's handler forwards to a new `EggStage.Back()`, the stage has no Esc handler), not the consumed-flag option: one owner is simpler to test and matches `MenuController.handleBack`. The Shop's handler acts while the stage shows even with the Shop closed, since a late answer can open the stage after the Shop closed.
- **leaderstats order.** The "wait with a timeout" variant (a task with `WaitForChild`, 10 s) plus the next pass, so a title is never lost; LeaderboardService never creates the folder.
- **Restricted accounts and token packs.** The full fix (server refusal, locked cards, a test, `store_token_lock`), widened to every Robux product that grants Tokens: the code shows the Pro Pack grants 5,000 tokens, so refusing only `Tokens1..3` would leave the same hole. It is a sales rule the owner may want otherwise, so it is also back in 16.8 as call 13 and a morning question. Nothing is on sale yet (every item has `Id = 0`), so this changes nothing live.
- **Shop sizes at PC.** Threshold 826 and the two table rows recomputed as proposed; the Eggs-page fit checks move to Task 22 (the page does not exist in Task 21), Task 21's size test checks the window sizes, rail modes and reachability on its four pages.
- **LightingStack.** As proposed (the tint as the `"Hatch"` preset, the blur as the only new effect; "High only"); the tint's values are the current `LightingStack.Value`s minus the deltas, since presets set absolute values.
- **Skip.** The proposed rule (Reveal on the next frame, the burst tail as a 0.25 s overlay with one gold flash for Legendary and up), written once in 16.4 and matched in Tasks 20 and 27; no white micro-flash in the overlay.
- **Tutorial pill.** The first option (drop the "glowing pill" assertion; `TutorialController` unchanged), because a ring needs a `Menu` target, which would replace the shop step's world arrow (a step has one target).
- **Egg rebuild.** The first option (the main session commits the 12 files on their own before Task 16), with the fallback (Task 26 in the lobby-shop worktree, not a lane) written into Lanes; Task 26 compares against `render_model.py meshkey:` renders of the committed manifests, never `blender/out`. This review pass did not commit anything (the main session commits).
- **Death mid-cutscene.** The first option (no exit on death or removal; the GUI is `ResetOnSpawn = false`), not a movement-sinking CAS binding: it touches no controls, so it cannot leave input broken.
- **BEST VALUE, the sim's Economy column, `p2_economy`'s loops, the rainbow wrap:** as proposed (`ShopGems.BestValue`; `PET_ECON_ROLLABLE = [3, 3, 3, 1, 2, 1, 1]`, Phantom Kitsune checked as the one Economy Secret of the four rollable; loops over `#RARITY_ORDER`; the Label at 2 x text width, left-aligned).
