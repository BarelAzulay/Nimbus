# Window Redo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Also name and use superpowers:test-driven-development (every task is test first) and superpowers:verification-before-completion.

**Goal:** Redraw the Daily, Play time, Training Place and Fusion windows from the owner's approved mock-ups, give Training and Fusion one shared full-screen pet picker, and carry the owner's three rule changes: the 10-minute daily unlock, several pets in training on visible mats, and the Mix move choice.

**Architecture:** Server first, then UI. Hybrid records gain one optional field (`SpecialFrom`) that every reader of a hybrid def honours (PetKeys, both save cleaners, the client snapshot), then FusionService accepts a 4th `moves` argument. DailyService gains the unlock, the hold and `ClaimPlayAll` with no new save field. On the client, one new `UI/PetPicker` sheet serves two callers: a new `TrainController` (CareController forwards Train to it and keeps every one-window wire) and the rebuilt `FusionController`; `DailyController` is redrawn in place. Every window sizes itself with `NeonKit.BigRect` like the Pets window and the Store.

**Tech Stack:** Luau in plain Lua 5.1 syntax, Rojo layout, the mock harness `py -3.12 tools/smoke.py` (lupa), `tools/dump_gui.lua` + `tools/render_gui.py`, `node tools/check.mjs`, `py -3.12 tools/count_locals.py`.

**Spec:** `docs/superpowers/specs/2026-11-06-window-redo-design.md` (with its review fixes, commits 97203a8 and fd2da78). Mock-ups: `Projects Main/Nimbus/.superpowers/gui-pitch/page.html` (functions `pickerC`, `dailyA`, `playB`, `trainA`, `trainC`, `fuseA`: every frame in design px at 844x390 and 1920x1080); real game data: `.superpowers/gui-pitch/NOTES.md`; decisions: `.superpowers/gui-pitch/DECISIONS.md`. Read the spec section each task names before starting it.

## How every task runs

- Worktree `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\gui-redo\nimbus-climb`, branch `gui-redo`. Absolute paths or `git -C`. Read `ABSOLUTE_RULES.md`, `brain.md` and the newest `BUILD_STATE.md` entry first.
- No Roblox Studio, no Rojo (it serves another worktree for the owner's live test: never start or stop it), no Blender, no uploads, no merges, no new 3D models. Do not touch other worktrees or `main`.
- Tests while building: `py -3.12 tools/smoke.py --quick --only <names>` with the names the task lists. Never the whole suite before Task 13.
- Before each commit: `node tools/check.mjs` -> 0 errors, and `py -3.12 tools/count_locals.py <every Lua file the task grew>` -> under the task's cap.
- Commit message ends with exactly these two lines, then `git -C <worktree> push origin gui-redo`:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01ACtM8qc8ts2NyGHrZh7vyT`
- After each push append one dated line to `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.superpowers\gui-pitch\BUILD-LEDGER.md` (commit hash, what landed, the tests that passed).
- A test that a task's change breaks is rewritten to the new rule in the same task, never deleted; the commit body names each rewritten scenario and why.
- Route (`tools/pick_model.py`): the router puts saves / money / security on Fable 5.1; Fable is out of credits and the owner chose Opus 5.5 for every stage (DECISIONS.md: Opus 5.5 xhigh). So: every task builds on **Opus 5.5 xhigh**; reviews on Opus 5.5 xhigh, **max** for Tasks 1, 4 and 5 (saves / money: the router's raised gate). Builders run one at a time in this order.
- Skills to name in each builder's prompt: superpowers:test-driven-development and superpowers:verification-before-completion always; plus roblox-dev:roblox-datastores (Tasks 1, 4), roblox-dev:roblox-security (Tasks 2, 4, 5), roblox-dev:roblox-ui (Tasks 6-12), roblox-dev:roblox-performance (Task 6: the viewport budget).

## Global Constraints

- Screens: a landscape phone 844x390 (Roblox top bar 58 px; about 322 px of height under it) and PC 1920x1080. Both must work, and every size between (check 1280x720 and 1366x768 too).
- Window box: `NeonKit.BigRect(K)` with `K.RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = <window>, Y1 = <window> }`, `MARGIN = 12`, `PHONE_W = 900`, `SHORT = 560`, `PC_MIN_H = 600`, `PC_MAX_W = 0.76`. Per window (W1 x Y1): Daily 1180 x 720, Training 1440 x 840, Fusion 1440 x 880, picker 1440 x 920. At 844x390 that is an 820x330 box at y 59, scale 1, mode "Phone"; at 1920x1080 mode "PC" at the screen factor. The PC layout is computed from the design box (`w / scale` x `h / scale`), with the mock's 1080p numbers as its largest form, so it also fits the smaller PC boxes (1280x720 gives about 1216 x 717 design px).
- Headers: phone 50 px, PC 76 px; the red X 44 px (phone) / 56 px (PC). Body = box height - header.
- ScreenGuis (DisplayOrder): `NimbusDaily` 19 (unchanged, `IgnoreGuiInset = false`), `NimbusFusion` 22 (switches to `IgnoreGuiInset = true`), `NimbusTrain` 23 (new, `IgnoreGuiInset = true`), `NimbusPetPicker` 24 (new, `IgnoreGuiInset = true`).
- Readability: PC design text >= 18 px; phone text >= 15 px at scale 1; any on-screen text >= 14 px; tap targets >= 44 px. All text through Theme roles. Glyphs as UTF-8 byte escapes (sources stay ASCII). Plain Lua 5.1 syntax.
- Game text is plain and short; readable on a landscape phone.
- One tween per window root for the open (0.2-0.25 s scale/fade, Back Out); NeonKit.Button hover 1.04 / press 0.95 / disabled desaturated.
- On a phone or a touch-only device a big window hides the stick and jump through `MenuController.SetTouchHidden(<who>, on)` (condition as `PetsController H.syncTouch`: `S.Open and (mode == "Phone" or touchOnly)`) and steps the menu column aside through `MenuController.SetColumnCovered(windowLeft, <who>)`. `<who>`: "Daily", "Train", "Fusion".
- Window-local hints go to the window's own `HintLine` (bottom of its body, 3 s), never `MenuController.Hint`.
- No reward, price, timer, odds or balance number changes: `Config.Daily` amounts, `TycoonCatalog.TrainCost` / `TrainSeconds`, `FusionCost` stay. No new remote. Every claim, unlock, train, stop and fusion is decided by the server.
- No new Daily save field. The only new hybrid field is `SpecialFrom = "Style" | nil`.
- Top-level locals (`tools/count_locals.py`): DataService 160 and MenuController 164 get **no** new top-level local. New client code lives in new modules or in a module's `H` table. Caps per file are in each task.
- New Lua files start with the module header comment in the repo's style (purpose, public API, plain Lua 5.1 line).

## Review Focus

1. A pet that leaves the collection while the picker is open (a fusion elsewhere, a dev reset, a rebase) must disappear from the sheet and can never be picked: a stale card handed to OnPick would select a pet the server no longer has -> `client_picker_ui` step "vanished key" (Task 6).
2. Search text with Lua pattern characters (`%`, `[`, `.`, `(`) must not error or match everything: the sheet would die mid-use -> `client_picker_pure` step "pattern text" (Task 6).
3. The screen turning or resizing while a window AND its sheet are open (a phone rotating, a window resize): both must re-lay out inside the screen, nothing stranded off-screen -> `client_picker_ui` step "resize under the sheet" and `client_train_layouts` step "resize while open" (Tasks 6, 7).
4. A hybrid record whose Style (or Body) catalog id is gone, with `SpecialFrom = "Style"`: the def must still build with a special and never error in a battle -> `hybrid_moves_def` step "missing parent" (Task 1).
5. The Training Place upgraded, or a Prestige closing mats, while the Training window is open: the mats must re-render at once (a newly open mat, a running job on a now-locked mat with its lock badge) -> `client_train_mats` step "slots change while open" (Task 8).

## File map

| File | Tasks | Change |
|---|---|---|
| `src/shared/PetKeys.lua` | 1, 2 | `hybridDef` special by `SpecialFrom`, cache sig, `CleanHybrid`; `ValidMoves`, `MixMoves` |
| `src/server/Services/DataService.lua` | 1 | `cleanHybrid` keeps `SpecialFrom = "Style"` (no new top-level local) |
| `src/client/State.lua` | 1 | `cleanHybrids` keeps `SpecialFrom = "Style"` |
| `src/server/Services/FusionService.lua` | 2 | `moves` argument, record `Elements` order + `SpecialFrom`, Preview |
| `src/server/Services/PetService.lua` | 3 | `EquippedHybrids` field 6 |
| `src/client/Controllers/PetController.lua` | 3 | reads field 6; `PetController.ParseHybrids` |
| `src/shared/Config.lua` | 2, 4, 5 | `Daily.UnlockSeconds = 600`; Remotes comments |
| `src/server/Services/DailyService.lua` | 4, 5 | unlock, hold, `Unlock` payload, crossing send; `ClaimPlayAll` |
| `src/client/UI/PetPicker.lua` | 6 (new) | the shared sheet |
| `src/client/Controllers/TrainController.lua` | 7, 8 (new) | the Training Place window |
| `src/client/Controllers/CareController.lua` | 7 | Train mode removed; forwarding |
| `src/client/Main.client.lua` | 7 | boots `TrainController` |
| `src/client/Controllers/DailyController.lua` | 9, 10 | Daily page A, Play page B, locked CLAIM, Claim All |
| `src/client/Controllers/FusionController.lua` | 11, 12 | layout A, picker, move chips |
| `tools/smoke_redo_*.lua` (new: hybrid, fusion, daily, geom, picker, train, daily_ui, fusion_ui) | 1-12 | the new scenarios |
| `tools/smoke.py` | 1-12 | one registration line per new file |
| `tools/dump_gui.lua`, `tools/render_gui.py` | 6-11 | scenes for the evidence renders |
| `tools/contract.json` | 5, 6, 7 | new public functions / modules |
| `tools/sim_tycoon.py` | 4 | `--daily`: the streak cell at minute 10 |
| older smoke files named per task | 4, 7, 9-11 | rewritten where the old rule / layout is pinned |
| `README.md`, `BUILD_STATE.md`, `brain.md` | 13 | docs |

---

### Task 1: Hybrid move data: `SpecialFrom` in the def, the saves and the client snapshot

Spec: 5.6 "Data, battle and evolution", 6 (hybrid record, the client snapshot fix).

**Files:**
- Modify: `src/shared/PetKeys.lua` (`CleanHybrid` 292-318, `hybridDef` 624-717: sig at 633-634, special at 685-688)
- Modify: `src/server/Services/DataService.lua` (`cleanHybrid` 1316-1347; inside the function only)
- Modify: `src/client/State.lua` (`cleanHybrids` 411-439)
- Create: `tools/smoke_redo_hybrid.lua` (server world: pure + booted; client world)
- Modify: `tools/smoke.py` (one line, with the other `p5(...)` lines)

**Interfaces:**
- Produces: hybrid record field `SpecialFrom` (`"Style"` or absent). `PetKeys.DefOf(hybridKey, profile).Special` = a shallow copy of `style.Special` when `rec.SpecialFrom == "Style"`, else `body.Special` (with today's fallbacks `body = body or style`, `style = style or body`). The def cache signature adds `tostring(rec.SpecialFrom)`. `PetKeys.CleanHybrid`, DataService `cleanHybrid` and State `cleanHybrids` keep `SpecialFrom` only when it is exactly `"Style"`, and it does not count toward the 8 extras.
- Fixture pets used by every hybrid test in this plan: Body `maple_fox` (Uncommon, Flame, special "Leaf Pounce" kind Pounce), Style `storm_tabby` (Rare, Storm, special "Static Storm" kind Storm). Element attacks: Flame "Flare", Storm "Bolt".

- [ ] **Step 1: Failing tests in `tools/smoke_redo_hybrid.lua`** (file header lists every scenario; `CONTEXT` picks the world like `smoke_storm.lua`)
  - `hybrid_moves_def` (pure): with `prof = { Hybrids = { h1 = rec } }` and `PetKeys.DefOf("hyb:h1", prof)`:
    - rec `{ Body = "maple_fox", Style = "storm_tabby", Elements = { "Flame", "Storm" }, SpecialFrom = "Style", Rarity = "Rare", Tier = "Normal", Seed = 7 }` -> `Special.Name == "Static Storm"`, `Special.Kind == "Storm"`, `Element == "Flame"`, `Elements[2] == "Storm"`
    - rec with `Elements = { "Storm", "Flame" }` and no `SpecialFrom` -> `Special.Name == "Leaf Pounce"`, `Element == "Storm"`
    - old rec (no `SpecialFrom`, `Elements = { "Flame", "Storm" }`) -> `Special` equals `PetCatalog.Get("maple_fox").Special` field by field (Id, Name, Kind, Power, Color), `Elements` = `{ "Flame", "Storm" }`, `Name == PetKeys.BlendName("Maple Fox", "Storm Tabby")` (computed, as `p2data_keys` does; not a literal) unless the rec names one
    - `SpecialFrom` = `"style"`, `"Body"`, `5`, `true` -> `Special.Name == "Leaf Pounce"` each
    - cache: the same uid and key, first `SpecialFrom = "Style"` then absent -> two different `Special.Name`s (the second call is not the first's cached def)
    - missing parent (Review Focus 4): `Style = "no_such_pet"`, `SpecialFrom = "Style"` -> a def, `Special.Name == "Leaf Pounce"`, no error; `Body = "no_such_pet"`, `SpecialFrom = "Style"` -> `Special.Name == "Static Storm"`
    - `PetKeys.CleanHybrid`: `SpecialFrom = "Style"` kept; `"style"`, `"Body"`, `5` dropped; a raw record with 8 unknown short-string extras plus `SpecialFrom = "Style"` keeps all 8 extras and `SpecialFrom`
  - `hybrid_moves_battle` (pure; build units the way `smoke_evo_sim.lua` `field()` does: `BattleSim.new({ Mode = "Duel", Teams = ... })`, then `b:StaticUnits()`), hybrid key `"hyb:hm1"`, rec `{ Body = "maple_fox", Style = "storm_tabby", Elements = { "Storm", "Flame" }, SpecialFrom = "Style", Rarity = "Rare" }` ("SS"):
    - Evo 0, Level 30: my unit's `elementAttack.Name == "Bolt"`, `special.Name == "Static Storm"`, `element == "Storm"`
    - Evo 1 and Evo 2: `special.Name == BattleCatalog.FormNameOf("hyb:hm1", "Storm", s)`, `elementAttack.Name == BattleCatalog.ElementFormOf("Storm", s).Name`, `BattleCatalog.FormOf("Storm", s) ~= nil`
    - `BattleCatalog.FormDpsOf(def, { Evo = 1, Elements = def.Elements })` equals `FormDps[1] * (FormDps.Storm or 1) * (FormDps.Storm or 1)` (kind Storm, element Storm)
    - the old "BB" record gives `"Flare"` and `"Leaf Pounce"` at Evo 0 (regression)
  - `hybrid_moves_save` (booted; the `smoke_p7_data.lua` helpers: `join`, `leave`, `stored(uid)`, `secondServer`):
    - a stored profile with `Hybrids = { h1 = SS rec, h2 = { ..., SpecialFrom = "Body" }, h3 = old rec }` loads: `GetProfile(p).Hybrids.h1.SpecialFrom == "Style"`, `h2.SpecialFrom == nil`, `h3.SpecialFrom == nil`
    - after a save: the stored `h1.SpecialFrom == "Style"`; the stored `h3` deep-equals the record before the load and gained no key
    - the ProfileSync snapshot sent to the client has `Hybrids.h1.SpecialFrom == "Style"`
    - two servers: A adds hybrid `h4` with `SpecialFrom = "Style"` and saves; B (older base) changes Cash and saves; the stored `h4.SpecialFrom == "Style"`
  - `hybrid_moves_evolve` (booted): the SS hybrid at level 20 (`SetPetLevel`), `PetCare("Evolve", "hyb:hm1")` from the client -> `DataService.GetEvolution(p, "hyb:hm1") == 1` and `PetKeys.DefOf("hyb:hm1", GetProfile(p)).Special.Name == "Static Storm"`
  - `client_hybrid_moves_state` (client): `KC.toClient("ProfileSync", snap)` with the SS hybrid `h9` -> `State.Hybrids().h9.SpecialFrom == "Style"`, `State.DefOf("hyb:h9").Special.Name == "Static Storm"`; the same with `SpecialFrom = "style"` and with no field -> `"Leaf Pounce"`
- [ ] **Step 2: Register** in `tools/smoke.py`: `if p5("smoke_redo_hybrid.lua"): server_files.append(...); client_files.append(...); names = ["hybrid_moves_def", "hybrid_moves_battle"]; pure_scenarios += names; ins(server_scenarios, "p5stats_formula", names); ins(server_scenarios, "shutdown", ["hybrid_moves_save", "hybrid_moves_evolve"]); ins(client_scenarios, "client_final", ["client_hybrid_moves_state"])` with a trailing `# [gui-redo, Task 1] ...` comment like its neighbours.
- [ ] **Step 3: Run** `py -3.12 tools/smoke.py --quick --only hybrid_moves_def,hybrid_moves_battle,hybrid_moves_save,hybrid_moves_evolve,client_hybrid_moves_state` -> FAIL (Body's special everywhere; `SpecialFrom` dropped by the client).
- [ ] **Step 4: Implement** the Interfaces above. In DataService change only the body of `cleanHybrid` (the known-field check next to `Name` / `Rarity`); header comments of all three files mention the field.
- [ ] **Step 5: Run** the five names plus `p2data_keys,p2fusion_looks,p2fusion_mix,evo_wire,p4data_save,p7data_fields,client_state` -> PASS. `count_locals`: DataService still 160, PetKeys <= 40, State <= 70. `node tools/check.mjs` -> 0 errors.
- [ ] **Step 6: Commit** `feat(gui-redo): hybrids remember which parent gives the special (SpecialFrom), saves and the client snapshot keep it`, push, ledger line.

**Only Studio can judge:** nothing new on screen yet.

### Task 2: `Fusion("Mix", body, style, moves)` on the server

Spec: 5.6 "Remote and server", 7.

**Files:**
- Modify: `src/shared/PetKeys.lua` (add two functions near `BlendName`)
- Modify: `src/server/Services/FusionService.lua` (header 39-49; `buildPlan` 611-753 Mix branch 661-720; `Preview` 1115-1144; `run` 1146; `Mix` 1163; `onFusionRemote` 1233-1265)
- Modify: `src/shared/Config.lua` (Remotes comment line 128: `-- (action:string, a:any, b:any, moves:string|nil)  Upgrade / Mix`)
- Create: `tools/smoke_redo_fusion.lua` (server world, booted)
- Modify: `tools/smoke.py`

**Interfaces:**
- Consumes: Task 1's `SpecialFrom`.
- Produces:
  - `PetKeys.ValidMoves(moves) -> boolean`: true for `nil` and for exactly `"BB"`, `"BS"`, `"SB"`, `"SS"`; false for anything else (other strings, numbers, tables).
  - `PetKeys.MixMoves(bodyDef, styleDef, moves) -> elements: {string}, specialFrom: "Style" | nil`. Letter 1 = the parent of the normal attack, letter 2 = the parent of the special (`B` Body, `S` Style); `nil` = `"BB"`. `elements` = `{ attackParent.Element, otherParent.Element }` deduplicated (equal elements give one); `specialFrom = "Style"` when letter 2 is `S`. Server and client both build the record through it.
  - `FusionService.Mix(player, keyA, keyB, moves) -> ok, resultKey | reason`; `FusionService.Preview(player, action, a, b, moves) -> ok, plan`, where a Mix plan also carries `Elements` and `SpecialFrom`.
  - Remote `Fusion("Mix", bodyKey, styleKey, moves)`: right after the action / key type checks, `if action == "Mix" and not PetKeys.ValidMoves(moves)` -> `reply(player, { Ok = false, Action = "Mix", Reason = "Pick the moves again" })` and `toastOnce(player, "Pick the moves again", "bad")`, nothing else read, nothing fused or charged. `"Upgrade"` ignores the 4th argument.

- [ ] **Step 1: Failing test `fusion_moves`** (booted; the fixture shape of `smoke_p2_fusion.lua` `p2fusion_mix`: Prestige 1, a Fusion Machine, enough Tokens, the player at the machine; one fresh pair per case)
  - `"BB"` and `nil` -> the new record `Elements == { "Flame", "Storm" }`, no `SpecialFrom`; its def's `Special.Name == "Leaf Pounce"`
  - `"BS"` -> `{ "Flame", "Storm" }`, `SpecialFrom == "Style"`, def special `"Static Storm"`
  - `"SB"` -> `{ "Storm", "Flame" }`, no `SpecialFrom`, def `Element == "Storm"`
  - `"SS"` -> `{ "Storm", "Flame" }`, `SpecialFrom == "Style"`
  - junk `"XX"`, `"bs"`, `"BSS"`, `5`, `{}` -> reply `Ok == false`, `Reason == "Pick the moves again"`, one toast with that text, Tokens unchanged, Pets / Hybrids counts unchanged
  - `Fusion("Upgrade", key, nil, "XX")` -> upgrades as today
  - `FusionService.Preview(p, "Mix", "maple_fox", "storm_tabby", "SB")` -> ok, `plan.Elements[1] == "Storm"`, `plan.SpecialFrom == nil`; with `"SS"` -> `plan.SpecialFrom == "Style"`
  - equal elements (two Flame pets) with `"SB"` -> `Elements == { "Flame" }`, no `SpecialFrom`
  - pure part: `PetKeys.ValidMoves` true for nil and the four strings, false for `"bb"`, `""`, `"BBB"`, `1`, `{}`; `PetKeys.MixMoves` for each of the four letters on the fixture defs
- [ ] **Step 2: Register** `if p5("smoke_redo_fusion.lua"): server_files.append(...); client_files.append(...); ins(server_scenarios, "shutdown", ["fusion_moves"])` (Task 3 adds its names to this line).
- [ ] **Step 3: Run** `--only fusion_moves` -> FAIL.
- [ ] **Step 4: Implement** the Interfaces. `buildPlan(player, action, a, b, moves)` builds `plan.Record` through `PetKeys.MixMoves(baseA, baseB, moves)`; `SpecialFrom` is left out of the record when nil. Header comments of FusionService describe the 4th argument.
- [ ] **Step 5: Run** `fusion_moves,p2fusion_upgrade,p2fusion_mix,p2fusion_exploits,hybrid_moves_def,client_p2fusion` -> PASS (`client_p2fusion` proves an old client that sends three arguments still mixes). FusionService locals <= 110, PetKeys <= 40. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(gui-redo): Mix takes the move choice (BB/BS/SB/SS), the server builds the record`, push, ledger.

### Task 3: Other players see the chosen first element (`EquippedHybrids` field 6)

Spec: 6 "Other players' view".

**Files:**
- Modify: `src/server/Services/PetService.lua` (`hybridLooks` 286-306; header 67-68)
- Modify: `src/client/Controllers/PetController.lua` (`parseHybrids` 736-765; header 26)
- Modify: `tools/smoke_redo_fusion.lua`, `tools/smoke.py` (its line)

**Interfaces:**
- Produces: the attribute value `"uid=Body/Style/Tier/Rarity/Seed/Elements;..."`. Field 5 is `""` when the record has no Seed (so field 6 keeps its place); field 6 = `table.concat(rec.Elements, "+")`, left out when the record has no Elements. `PetController.ParseHybrids(text) -> { Hybrids = { [uid] = rec } }` (the local function made public for tests), with `rec.Elements` = field 6 split on `"+"` when present.

- [ ] **Step 1: Failing tests**
  - `pet_attr_hybrid_elements` (booted): equip an SB hybrid with Seed 42 -> the player's `EquippedHybrids` contains `"=maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame"`; a record with no Seed -> `"/Rare//Storm+Flame"`
  - `client_pet_attr_hybrid_elements` (client): `PetController.ParseHybrids("h1=maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame")` -> `Hybrids.h1.Elements == { "Storm", "Flame" }`, `Seed == 42`, and `PetKeys.DefOf("hyb:h1", parsed).Element == "Storm"`; the 5-field value `"h1=maple_fox/storm_tabby/Normal/Rare/42"` -> no `Elements`, `DefOf(...).Element == "Flame"` (today's fallback); `"h1=maple_fox/storm_tabby/Normal/Rare//Storm+Flame"` -> `Seed == nil`, Elements read
- [ ] **Step 2: Register** the two names on Task 2's line (`ins(server_scenarios, "shutdown", [...])`, `ins(client_scenarios, "client_final", ["client_pet_attr_hybrid_elements"])`).
- [ ] **Step 3: Run** `--only pet_attr_hybrid_elements,client_pet_attr_hybrid_elements` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** the two plus every scenario that reads `EquippedHybrids` (`grep -l EquippedHybrids tools/smoke_*.lua`, run their scenarios) -> PASS. PetController locals <= 120, PetService <= 75. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(gui-redo): EquippedHybrids carries the hybrid's element order`, push, ledger.

### Task 4: The daily 10-minute unlock and the hold (server)

Spec: 5.3 "The 10-minute rule", "The hold", `State`, "Payload", "Tick"; 6 (Daily); 9 (`daily_unlock*`); 11 calls 1-4.

**Files:**
- Modify: `src/shared/Config.lua` (`Config.Daily`, after `FutureClockSlack`: `UnlockSeconds = 600, -- a streak claim needs this many counted play seconds of the current play-day (0 = off: no lock, no hold)`)
- Modify: `src/server/Services/DailyService.lua` (header; `TEXT`; `State` 500-589; `Claim` 603-681; `tickPlayer` 730-785; `PlayerRemoving` cleanup)
- Modify: `tools/smoke_daily.lua`, `tools/smoke_fixr_daily.lua` (their `claim(p)` helpers), and any other scenario that claims a streak gift (`grep -n '"Claim"' tools/smoke_*.lua`)
- Create: `tools/smoke_redo_daily.lua` (server world, booted)
- Modify: `tools/smoke.py`, `tools/sim_tycoon.py`

**Interfaces:**
- Produces:
  - `Config.Daily.UnlockSeconds = 600`.
  - Payload field `DailyState.Unlock = { Need = UnlockSeconds, Left = max(0, Need - livePlaySec) }` (`livePlaySec` = `PlaySec` when `PlayStart > 0` and not `dayOver`, else 0; a Loading payload sends `Left = Need`; `Need = 0` -> `Left = 0`).
  - Claim refusal while ready but locked: nothing written, toast `"Play %d more min to unlock today's gift!"`, or `"Play %d more min to repair your streak!"` when that claim would be a repair (minutes = `math.ceil(left / 60)`). Order in `Claim`: loaded -> not ready (today's texts) -> locked -> VIP "Checking" -> step-back measured at `keepAt` -> commit and pay as today.
  - In memory: `holds[player] = { Last = last, Sec = n }`, cleared on `PlayerRemoving`; `DailyService._holds(player) -> holds[player]` (test-only).
  - One helper `keepOf(player, d, last, now) -> keepAt, source` (`source` = `"PlayStart"` | `"Held"` | nil) used by both `State` and `Claim`, exactly as spec 5.3 defines it (`from = min(live PlayStart, now - Sec)`, `keepAt = min(now, max(from, last + ReadySeconds))`), and `keepAt = now` when `UnlockSeconds == 0`.
  - `StaleAt` per spec 5.3: no hold -> today's rule on `now`; held by `"PlayStart"` -> `PlayStart + DaySeconds`; held by `"Held"` -> `rule(keepAt) + Sec`.
  - Tick: computes `last` (`lastClaimOf`) before its `MutateDaily` step. Inside the step it captures the `PlaySec` after any reset and before this tick's add; after the commit a counting tick with `UnlockSeconds > 0`, `last > 0`, `now >= last + ReadySeconds` and that captured `PlaySec < UnlockSeconds` adds `TickSeconds` to `holds[player].Sec` (a different `Last` starts it at 0). The tick also sends a payload when the live `PlaySec` crosses `UnlockSeconds` (before < Need <= after).

- [ ] **Step 1: Failing tests in `tools/smoke_redo_daily.lua`** (helpers copied from `smoke_daily.lua`: `join`, `claim`, `setDaily`, `elapse`, `lastState`, `moveRoot`, `alignTicks`, `tick(n)`, `toastCount`, `secondServer`)
  - `daily_unlock`:
    - a ready gift (LastClaimAt = now - 21 h, Streak 3 = Paid 3), `PlayStart = now`, `PlaySec = 0`: `claim(p)` -> `toastCount(p, "Play 10 more min to unlock today's gift!") == 1`, the stored Daily is unchanged (Streak, LastClaimAt, no grant); `lastState(p).Unlock.Need == 600`, `.Left == 600`
    - 6 still ticks -> `Left` still 600; 30 ticks with a 3-stud move each -> `Left == 300`; a `PetCare` remote fired, then 18 still ticks inside 180 s -> they count
    - the tick that reaches 600 sends exactly one payload with `Unlock.Left == 0`; `claim(p)` pays day 4
    - a repair claim (Paid 5 > Streak 3, missed) while locked -> `"Play 10 more min to repair your streak!"`
    - a VIP (the `daily_remote` StoreService double) and a first claim ever (LastClaimAt 0) are refused while locked
    - the play-day resets (PlayStart = now - DaySeconds + 5, PlaySec 590) -> after the reset tick `Left` is 600 or 590 (the new day's count)
    - `config("Daily").UnlockSeconds = 0` (restored after): a claim with `PlaySec = 0` pays; payload `Unlock.Need == 0`, `Left == 0`; LastClaimAt = now - 48 h - 1 s with a play-day started 1 h earlier -> one step back (no hold)
  - `daily_unlock_hold` (each case on a fresh player; "L" = the stored LastClaimAt, set with `setDaily` so the sim clock stays put):
    - A: L = now - 47 h 55 m, PlayStart 0; 60 counting ticks (10 min); claim at L + 48 h 05 m -> `StepBack == 0`, Streak + 1
    - B: L = now - 49 h, PlayStart 0; 10 min of play; claim -> `StepBack == 1`
    - C: L = now - 49 h 05 m, PlayStart = L + 30 h, PlaySec 0; 10 min; claim -> kept; the payload before the claim has `StaleAt == PlayStart + DaySeconds`
    - D (the review case): L = now - 47 h 58 m, PlayStart = now - (DaySeconds - 7 min) (a 1 min visit at L + 28 h 05 m), PlaySec 60; play without a stop: before the reset `lastState(p).Play.DayEnds - ServerNow < Unlock.Left`; the reset tick 7 min in; 10 more min of play; claim -> `StepBack == 0`; `DailyService._holds(p).Sec` was about 17 min just before the claim and `nil` or `Sec == 0` for the new stamp after it
    - E: as D, but after the unlock the player stands still for 3 min, then claims (now - Sec is past L + 48 h) -> `StepBack == 1`
    - in A-E the last payload before the claim agrees with the claim: kept -> `Repair == false` and `Cell == (Streak % 7) + 1`; stepped back -> `Cell` and `Repair` match the claim's `StepBack`
    - D after the reset: `StaleAt == rule(keepAt) + Sec` (compute `rule` in the test exactly as spec 5.3 says)
  - `daily_unlock_hop`: server A: L = now - 47 h 55 m, 6 min of play (PlaySec 360, PlayStart P), the player leaves and A saves; server B (`secondServer`) loads: `Unlock.Left == 240`; 4 min on B -> `Left == 0`; claim on B after L + 48 h -> kept (source "PlayStart"), paid once
- [ ] **Step 2: Rewrite the old claim helpers.** In `smoke_daily.lua` and `smoke_fixr_daily.lua` (and any other streak-claim helper found by the grep) add `unlock(p, fresh)` and call it inside `claim(p)` before the fire: `MutateDaily` that, when `fresh` or the play-day is not live, sets `PlayStart = os.time()`, `PlaySec = 0`, `PlayClaimed = {}`; then `PlaySec = max(PlaySec, UnlockSeconds)`. Streak-boundary scenarios (`daily_claim`, `daily_week`, `daily_miss`, the `fixr_daily_*` claims) pass `fresh = true` (keepAt = now exactly, so the 48 h + 1 s boundary still steps back); scenarios that also check play tiers (`daily_two_servers`, `daily_rejoin`, `daily_playday`) use `fresh = false`. One scenario keeps `UnlockSeconds = 0` to pin today's rule: `daily_unlock`'s last case above.
- [ ] **Step 3: Register** `if p5("smoke_redo_daily.lua"): server_files.append(...); ins(server_scenarios, "shutdown", ["daily_unlock", "daily_unlock_hold", "daily_unlock_hop"])` (Task 5 adds its name).
- [ ] **Step 4: Run** `--only daily_unlock,daily_unlock_hold,daily_unlock_hop` -> FAIL.
- [ ] **Step 5: Implement** the Interfaces. DailyService header: the unlock, the hold (both sources), the payload field, the toasts.
- [ ] **Step 6: `tools/sim_tycoon.py`:** next to `DAILY_STREAK` (outside the constants block) add `DAILY_UNLOCK_MIN = 10  # Config.Daily.UnlockSeconds / 60: the streak cell pays at this play minute`; `--daily` pays the streak cell at `minute == DAILY_UNLOCK_MIN` instead of 0; `--check` adds a problem line when `Config.Daily.UnlockSeconds / 60 != DAILY_UNLOCK_MIN`. Update the docstring and the `--daily` help text.
- [ ] **Step 7: Run** the three new names plus `daily_pure,daily_claim,daily_week,daily_miss,daily_provisional,daily_two_servers,daily_future_clock,daily_rejoin,daily_idle,daily_playday,daily_remote,daily_quiet_join,fixr_daily_playday_reset,fixr_daily_readyat,fixr_daily_stamp_race,fixr_daily_slow_clock,fixr_daily_repair_state,fixr_daily_clamp_rejoin,fixr_daily_clamp_frame,fixr_daily_keep_resend,fixr_data_daily_stamp,p7data_daily_merge,p2_economy` -> PASS. `py -3.12 tools/sim_tycoon.py --check` -> ok; `py -3.12 tools/sim_tycoon.py --daily` and `--daily --vip` run, and the ledger line reports their "daily gifts" lines before / after. DailyService locals <= 65. check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(gui-redo): the daily gift waits for 10 minutes of play each play-day; the hold keeps the streak`, push, ledger.

**Only Studio can judge:** the unlock live: join, stand still, move, the unlock after 10 minutes; a server hop keeping the count.

### Task 5: Claim All (server)

Spec: 5.4 "Server", 7.

**Files:**
- Modify: `src/server/Services/DailyService.lua` (`ClaimPlay` 683-725 split into a quiet internal step; new `ClaimPlayAll`; `onRequest` 813-849; header "Remote" and "Public API")
- Modify: `src/shared/Config.lua` (Remotes line 143: `-- (action:string, tier:number|nil)  "Claim" / "ClaimPlay" (tier) / "ClaimPlayAll" (DailyService)`)
- Modify: `tools/contract.json` (`server/Services/DailyService` pending functions + `"ClaimPlayAll"`)
- Modify: `tools/smoke_redo_daily.lua`, `tools/smoke.py` (its line)

**Interfaces:**
- Produces: `DailyService.ClaimPlayAll(player) -> ok, { Tiers = { tier... }, Grants = { grant... } } | reason`. Claims every Ready tier in tier order through the same internal step as `ClaimPlay` (each tier its own `MutateDaily` flag + grant, paid right after it; nothing yields), quietly, then ONE toast and ONE `Send`. Toast: one tier -> `ClaimPlay`'s text (`"%s %d min played"`); several -> each tier's pay text without its final `"!"`, joined with `", "`, then `": n gifts!"` (`"+$2,160 Cash, +10 Gems: 2 gifts!"`), or `"%d gifts claimed!"` when the joined text would pass 60 characters. None ready -> `false, "No gifts ready yet!"`. Refusals as `ClaimPlay`: not loaded, `dayOver` -> `"That play day is over!"`. `DailyService.Claimed` fires once per tier.
- Remote `DailyRequest("ClaimPlayAll")`: a second or third argument -> dropped without an answer; its own 1 s gap (`limited(player, "ClaimPlayAll")`); InMatch -> the InMatch toast; pcall around the call as the other two.

- [ ] **Step 1: Failing test `daily_claim_all`** (booted):
  - PlaySec 47 min, tiers 1-3 Ready: one `DailyRequest("ClaimPlayAll")` -> `PlayClaimed[1..3] == true`, Cash / Tokens up by exactly tiers 1-3's resolved amounts, exactly 1 toast, exactly 1 new DailyState payload, `Claimed` fired 3 times
  - again -> toast `"No gifts ready yet!"`, nothing paid
  - one Ready tier -> the toast equals `ClaimPlay`'s text for that tier
  - `("ClaimPlayAll", 1)` and `("ClaimPlayAll", nil, "x")` -> no answer, nothing paid
  - two requests 0.5 s apart -> the second dropped; InMatch -> `"Finish your match first!"`, nothing paid
  - a play-day that is over -> `"That play day is over!"`
  - two servers at one PlayStart, both ClaimPlayAll tier 1-2 -> after both saves each tier paid once (the `p7data_daily_merge` shape)
  - the toast stays <= 90 characters when all 7 tiers are claimed at once (`"7 gifts claimed!"`)
- [ ] **Step 2: Register** `daily_claim_all` on Task 4's line.
- [ ] **Step 3: Run** `--only daily_claim_all` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** `daily_claim_all,daily_remote,daily_playday,daily_two_servers,daily_rejoin,daily_unlock,contract` -> PASS. DailyService locals <= 68. check.mjs 0 errors.
- [ ] **Step 6: Commit** `feat(gui-redo): DailyRequest("ClaimPlayAll") claims every ready play gift with one toast`, push, ledger.

### Task 6: The shared pet picker sheet (`UI/PetPicker`) and the geometry helper

Spec: 5.1, 5.2 (incl. the PC chips row rule), 9 `picker_ui`.

**Files:**
- Create: `src/client/UI/PetPicker.lua`
- Create: `tools/smoke_redo_geom.lua` (client worlds; sets the global `RedoGeom`; returns an empty scenario table)
- Create: `tools/smoke_redo_picker.lua` (client worlds)
- Modify: `tools/smoke.py` (the geom file is appended to `client_files` before every other `smoke_redo_*` client file that uses it), `tools/contract.json` (`client/UI/PetPicker`, optional: `Open`, `Close`, `IsOpen`, `Entries`, `Sorted`), `tools/dump_gui.lua` (scenes `picker:train`, `picker:upgrade`, `picker:mix`), `tools/render_gui.py` (`SCENARIOS`)

**Interfaces:**
- Produces (test helper): `RedoGeom.at(w, h, touch, label, fn)` (sets `Mock.SetViewport` and the UserInputService touch / keyboard / mouse flags, `KC.advance(0.6)`, runs `fn`, restores, `KC.flushErrors(label)`; the `smoke_tb_pets.lua` `H.at` shape); `RedoGeom.check(root, label, opts) -> boolean` with `opts = { MinText = 14, MinTarget = 44, NoOverlap = { name... }, Skip = { [name] = true } }`: every visible text under `root` is at least `MinText` on screen (`TextSize` x the UIScale chain, or the box height when `TextScaled`; the `KC.smallTexts` rule), every visible active button / TextBox is at least `MinTarget` on both sides, every visible GuiObject is inside the viewport and below the gui inset (58 px) in screen px (add the inset when its ScreenGui does not ignore it), and the named descendants' boxes do not intersect each other; `RedoGeom.find(root, name)`; `RedoGeom.desc(o)`.
- Produces (`PetPicker`), as spec 5.2 plus:
  - `PetPicker.Open(spec) -> boolean` (false only without a gui or a valid `spec.Context`; an empty list still opens and shows its empty text), `Close()` (calls `OnClose(false)` when no pick happened), `IsOpen()`, `Entries(context)`, `Sorted(context, entries, sortId, filterId, query)`, `Sorts[context]`, `Filters[context]`.
  - Ids: `Sorts.Train = { Default "Training first", Level, Rarity, Name }`, `Sorts.Upgrade = { Default "Ready first", Rarity, Level, Name }`, `Sorts.Mix = { Default "Rarity", Level, Name, Team "Team first" }`; `Filters.Train = { All, Team, Training, Rare "Rare and up", Epic "Epic and up" }` (phone shows the first three), `Filters.Upgrade = { All, Ready, Team }`, `Filters.Mix = { All, Team, Rare "Rare and up" }`. Each entry `{ Id, Label }`.
  - Entry: `{ Key, Def, Name, Level, Stage, Rarity, RarityOrder, Copies, Team (slot index in the active preset) | nil, Job = { Stat, Ends, Slot } | nil, Ready (Upgrade: Copies >= TycoonCatalog.Fusion.Copies, 3), Hybrid, Blocked = "Training" | nil }`. The picker computes the training blocks of spec 5.2 itself (Upgrade: the key or its next-finish key in training; Mix: a key in training) and merges `spec.Blocked` over them.
  - Test-facing: `PetPicker.Shown() -> { key... }` (the cards in display order), `SetQuery(text)`, `SetSort(id)`, `SetFilter(id)`, `Pick(key) -> boolean` (the tap path: false when blocked or not shown), `Layout() -> "PC" | "Phone"`.
  - It binds no Esc / gamepad B. The opener's back handler calls `PetPicker.Close()` when `PetPicker.IsOpen()`, else closes itself (one press, one step). The X button closes the sheet. A pick closes the sheet first, then calls `OnPick(key)` once.
  - Instances: ScreenGui `NimbusPetPicker` > `Window_PetPicker` (UIScale `Fit`) > `Header` (`Title`, `CloseButton`), `Body` > `Search` (TextBox, placeholder "Search pets" / phone "Search"), `SortButton` (`"Sort: Ready first \226\150\190"`), `Filter_<Id>`, `Grid` (ScrollingFrame) > `Card_<key>` (attributes `Blocked`, `Selected`, `Dim`), `Empty` (`"No pets match."` + `ClearButton` / `"No pets yet! Spin a roulette in the Shop to hatch one."`), `HintLine`.
  - Sizes: BigRect `W1 = 1440`, `Y1 = 920`. Phone body: search 220 x 44, sort 170 x 44, chips 44 tall in one row, grid from y 58, cards 124 x 100 (art 56), 6 per row. PC: search 460 x 60, sort 280 x 60, chips 50 tall on row 1 when they end at least 24 px before the body's right edge, else on a row at y 92 with the grid from y 166 (grid otherwise from y 100); cards 180 x 226, as many per row as fit (7 at 1080p). Cards: rarity frame colour (`Config.Rarities`), PetViewport, the name with the last-word fallback (TextService-measured), `"Lv 34"` with one gold star per stage, the rarity word under the name on PC; corner badge per context (Train: a gold star when in the team; Upgrade: `"x5"`, green `"x3+"` style when Ready; Mix: `"x2"`); Train adds a purple `"Training 3:10"` chip with a live countdown; Upgrade dims entries with fewer than 3 copies; blocked cards are dimmed and show their word and cannot be picked.
  - Viewports: only cards that intersect the visible part of the grid hold a viewport; clones cached per key; built under `BUILD_BUDGET = 0.004` s per frame (at least one per frame), on the CloudUI update loop. Sort and filter are kept per context for the session. `State.Changed` re-lists the open sheet: a key that left the collection loses its card, is never passed to `OnPick`, and clears `Selected`.

- [ ] **Step 1: Write `tools/smoke_redo_geom.lua`** (the helper above).
- [ ] **Step 2: Failing tests in `tools/smoke_redo_picker.lua`** (fixture snapshot: about 16 pets as in the mock's `TRAIN_ORDER`, one hybrid, a Golden and a Rainbow copy, two jobs with different `Ends`, a 3-pet active team, copies 5 / 4 / 3 / 2 / 1):
  - `client_picker_pure`:
    - `Entries("Train")` lists every owned key incl. the hybrid; `Entries("Upgrade")` no hybrid, no Rainbow; `Entries("Mix")` no hybrid
    - `Sorted("Train", e, "Default", "All", "")`: the two training keys first (sooner `Ends` first), then the team in slot order, then the rest by rarity high to low, then level high to low
    - `Sorted("Upgrade", ..., "Default", ...)`: Ready (copies >= 3) first, then copies, then rarity, then name; `Sorted("Mix", ..., "Default", ...)`: rarity then level
    - filters: Train "Team" = the 3 team keys, "Training" = the 2 jobs, "Rare" / "Epic" by `RarityOrder`; Upgrade "Ready"; Mix "Rare"
    - search `"fox"` matches "Aurora Fox" and "Maple Fox", case-insensitive; pattern text (Review Focus 2) `"%"`, `"%["`, `"."`, `"(("` -> no error, and only names that really contain those characters (none here)
    - blocked: Upgrade blocks a training key and a key whose next-finish key is training (`Blocked == "Training"`); Mix blocks a training key; `spec.Blocked = { maple_fox = "In Body" }` shows on that card
  - `client_picker_ui` (inside `RedoGeom.at(1920, 1080, false, ...)`):
    - `Open({ Context = "Train", Title = "Pick a pet to train", Selected = k2, OnPick = f, OnClose = g })` -> `Window_PetPicker` shown, `Title.Text == "Pick a pet to train"`, `#Shown() == #Entries("Train")`, `Card_k2` has `Selected == true`
    - `Pick(k1)` -> `IsOpen() == false` before `f` runs, `f` called once with `k1`, `g` called with `true`
    - blocked card: `Pick(blockedKey) == false`, sheet still open
    - Upgrade: the 2-copy key's card has `Dim == true` and its badge "x2", and `Pick(it) == true` (dimmed, not blocked); the 5-copy card's badge is the green Ready style
    - typing in `Search` filters `Shown()`; a query with no match shows `Empty` "No pets match." and `ClearButton` empties the query
    - `SortButton` cycles `"Sort: Training first"` -> `"Sort: Level"` -> ...; the choice is still there after Close + Open in the same context, and Upgrade keeps its own
    - after 60 frames only cards in the grid's visible window have a `PetViewport` child; scrolling the grid to the end gives the last row viewports
    - the Train chip of a training card counts down (`advance(1)` changes its text)
    - vanished key (Review Focus 1): while open, a ProfileSync without `k3` -> no `Card_k3`, `Pick(k3) == false`, `f` not called
    - resize under the sheet (Review Focus 3): open at 1920x1080, `Mock.SetViewport(844, 390)` -> `Layout() == "Phone"` and `RedoGeom.check` passes; back to 1920x1080 -> "PC", check passes
    - X -> closed, `g(false)`
  - `client_picker_layouts`: for each context Train / Upgrade / Mix, at 844x390 (touch), 1280x720 and 1920x1080: `RedoGeom.check(window, ..., { NoOverlap = { "Search", "SortButton", "Filter_*", "CloseButton", "Grid" } })` (expand `Filter_*` to that context's chips); at 1920x1080 Train's `Filter_All` sits below `Search` (row 2) and `Grid`'s top >= the chips' bottom; Upgrade's `Filter_All` has the same `AbsolutePosition.Y` as `Search`; phone: 6 cards per row, Train shows 3 chips; 1080p: 7 per row
  - `client_picker_portrait` (mobile world, 390x844): the sheet fits, `RedoGeom.check` passes, cards wrap
- [ ] **Step 3: Register** `if p5("smoke_redo_picker.lua"): client_files.append("smoke_redo_geom.lua"); client_files.append("smoke_redo_picker.lua"); ins(client_scenarios, "client_final", ["client_picker_pure", "client_picker_ui", "client_picker_layouts"]); mobile_scenarios.append("client_picker_portrait")`.
- [ ] **Step 4: Run** `--only client_picker_pure,client_picker_ui,client_picker_layouts,client_picker_portrait` -> FAIL (no module).
- [ ] **Step 5: Implement** `src/client/UI/PetPicker.lua` (H-table style like CareController; top-level locals <= 60).
- [ ] **Step 6: dump_gui / render_gui:** scenes `picker:train` (the fixture, Train context, one job running), `picker:upgrade`, `picker:mix` (a Body picked, its species blocked); add them to `SCENARIOS`. Render each at `--size 844x390` and `--size 1920x1080` into `Projects Main\Nimbus\.superpowers\gui-pitch\evidence\` and look at them: no text under the readability floor in the report, nothing cut, matches `pickerC`.
- [ ] **Step 7: Run** the four names plus `contract,client_ui_kit,client_gui_dump` -> PASS. check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(gui-redo): one full-screen pet picker sheet (search, sort, filters, big cards)`, push, ledger.

**Only Studio can judge:** viewport framing per species, how long 30+ cards take to fill, smooth scrolling on a phone, dragging the grid without picking, the search keyboard over the sheet, gamepad focus through the cards.

### Task 7: The Training Place window (`TrainController`): wiring, pet card, skill cards, confirm, empty state

Spec: 5.5 (all but the mats row's contents), 5.1.

**Files:**
- Create: `src/client/Controllers/TrainController.lua`
- Modify: `src/client/Controllers/CareController.lua` (remove the Train page: `H.buildTrainPage` 919-1024, `H.newTrainRow` / `H.paintTrainRow` 1442-1496, `H.refreshTrain` 1705-1846, the Train branches of `H.refresh` / `H.relayout` / `Open` / the tick loop, `H.askTrain` / `H.paidOf` / `H.askStop` 2075-2126 (they move to TrainController with their texts); add the forwarding; header 4-35)
- Modify: `src/client/Main.client.lua` (`"TrainController"` after `"CareController"` in the boot list, and in `OPTIONAL`)
- Modify: `tools/contract.json` (`client/Controllers/TrainController`, optional: `Init`, `Open`, `Close`, `IsOpen`)
- Create: `tools/smoke_redo_train.lua` (client worlds)
- Modify (rewrite the Train parts, keep the scenario names): `tools/smoke_p4_careui.lua` (`client_p4careui_train`, the Train part of `client_p4careui_sizes` and `client_p4careui_mobile`), `tools/smoke_p5_gui.lua` (the `"train"` COVER entry -> `NimbusTrain` / `Window_Train`, `Centered = true`, `MaxCover = 85`, like the `"pets"` entry), `tools/smoke_p5_looks.lua` (the Train check -> the big pet card draws the selected evolved pet's stage), `tools/dump_gui.lua` (`train` scene unchanged: `OpenPanel("Train")` still opens it), `tools/smoke.py`

**Interfaces:**
- Consumes: `PetPicker` (Task 6): `PetPicker.Open({ Context = "Train", Title = "Pick a pet to train", Selected = key, OnPick = TrainController.Select, OnClose = fn })`, `PetPicker.Sorted("Train", PetPicker.Entries("Train"), "Default", "All", "")`, `PetPicker.Close()`, `PetPicker.IsOpen()`.
- Produces:
  - `TrainController.Init()`, `Open(args) -> boolean` (`args = { Key?, ReturnTo? }`), `Close()`, `IsOpen() -> boolean` (the window or its confirm), `Key() -> key | nil`, `Select(key)`, `Step(dir)` (`-1` = ‹, `1` = ›), `DropReturn()`, `Layout() -> "PC" | "Phone" | "Portrait"`, `SkillState(stat) -> "Ready" | "Training" | "Busy" | "Full" | "Short" | "Max" | "Match" | "NoPet" | "NoPlace"`.
  - CareController: `CareController.NotifyTrain(open)` (true -> `Opened:Fire("Train")`, false -> `Closed:Fire()`), `CareController.CloseOwn()` (closes Feed / Garden, never forwards), `Open("Train" | "Training", args)` -> `return TrainController.Open(args)`, `Close()` calls `TrainController.Close()` before its own early return, `H.dropReturn()` calls `TrainController.DropReturn()`, `Mode()` returns `"Train"` while `TrainController.IsOpen()`, `IsOpen()` is also true then, `Open("Feed" | "Garden")` calls `TrainController.Close()` first.
  - On open TrainController closes `MenuController.Close()`, `IndexController.Close()`, `FusionController.Close()`, `DailyController.Close()`, `CareController.CloseOwn()`; it never fires `MenuController.WindowOpened`; it closes on InMatch and on Esc / B (confirm first, then the sheet, then the window); `Close()` also closes an open sheet and the confirm; `ReturnTo` reopens `PetsController.Open(ReturnTo)` after a close unless `DropReturn` ran (the CareController `S.BackTo` shape).
  - Instances: ScreenGui `NimbusTrain` (23) > `Window_Train` (UIScale `Fit`) > `Header` (`Title` "Training Place" with the dumbbell glyph, `SpotsChip` "Training spots: 1 / 3 in use" / phone "1 / 3 spots" / "No Training Place yet", `CloseButton`), `Body` > `Mats` (the band, filled by Task 8), `PetCard` (`PickPrompt` "Pick a pet" in the empty state), `PetName`, `PetLevel` ("Lv 34 / 100" + stars), `PrevButton`, `ChangeButton` ("Change pet" / phone "Change" / "Pick a pet"), `NextButton`, `RestNote` (PC: "Training pets rest at home until they're done."), `Skills` > `Skill_<Id>` for Speed, Physique, Ability, Defense (attribute `State` = `SkillState`; children `Name`, `Rank`, `Bar`, `Now`, `Next`, `Cost`, `Time`, `Action`), `Empty` (the no-pets / no-Training-Place body text), `HintLine`; and `Confirm` (a sibling of `Window_Train` under the ScreenGui, higher ZIndex) > `Title`, `Text`, `Yes`, `No`.
  - Sizes: BigRect `W1 = 1440`, `Y1 = 840`. PC (body under the 76 header): mats band 132 tall at the top; left column 420 wide (pet card, name 42, level 26, ‹ 76 / Change pet 220 / › 76, the rest note); skill cards 2 x 2 (about 466 x 292 at 1080p) with icon, name, "Rank 4 / 10", a 10-segment bar, "Now: +16% attack speed", "Rank 5: +20%" (green), cost (green; red when short), time, TRAIN 220 x 72. Phone (body 280 under 50): mats at y 4 (52 tall), left column 200 from y 64 (card 200 x 112, name 18, level 15, ‹ 44 / Change / › 44), skill cards about 286 x 104 (20 px top row name + "4/10", 10 px bar, an 18 px line "+16% -> +20% · 5 min", a 44 px button "TRAIN $26,250" / "STOP" / "Busy training" / "Spots full" / "MAX" / "Pick a pet first" / "No Training Place").
  - Behaviour, numbers, confirm texts and the 0.5 s refresh exactly as spec 5.5 and today's `CareController.askTrain` / `askStop`; sends `PetCare("Train", key, stat)` / `PetCare("TrainStop", key)` with a 0.3 s client gap per action.

- [ ] **Step 1: Failing tests in `tools/smoke_redo_train.lua`** (fixture as `smoke_p4_careui.lua`: a home with a Training Place Lv 3, pets, one job):
  - `client_train_ui` (1920x1080): `OpenPanel("Train")` with a job running -> `Window_Train` shown in `NimbusTrain`, `TrainController.Key()` = the training pet; its skill card `State == "Training"` with "STOP" and a timer; the other three `"Busy"`; the chip reads "Training spots: 1 / 3 in use"; ‹ / › walk `PetPicker.Sorted("Train", ..., "Default", "All", "")` in order and wrap, the sheet stays closed; "Change pet" opens the sheet with `Selected` = the current pet; picking selects it; a free pet's card TRAIN -> `Confirm` visible with today's title / text, Yes -> one `PetCare("Train", key, stat)` sent, No -> none; STOP -> the stop confirm (Cash-back wording by `Job.Paid`); full spots -> `"Full"`; Cash short -> `"Short"`, the cost red, the button disabled; rank 10 -> `"Max"` with no button; InMatch -> the window closes
  - `client_train_wiring`:
    - `CareController.Close()` closes Training; `CareController.Opened` fired `"Train"` once on open and `Closed` once on close
    - opening Training closes the Pets window, the menu's Shop window, the Store, the Index, Fusion and the Gifts window
    - the Pets window's Train button -> Training opens on that pet, the Pets window closes; X -> the Pets window reopens on that pet (`ReturnTo`)
    - `MenuController.WindowOpened:Fire("Store")` while open -> Training closes and the Pets window does NOT come back
    - `CareController.Mode() == "Train"` and `IsOpen() == true` while it is up; `Open("Feed")` while it is up closes it
    - the confirm: `Confirm.Parent == Window_Train.Parent` and `Confirm.ZIndex > Window_Train.ZIndex`
    - Esc order: confirm open -> Esc closes only the confirm; sheet open -> Esc closes only the sheet; then Esc closes the window
    - closes with its opener: sheet open, then `CareController.Close()` -> `PetPicker.IsOpen() == false` and `TrainController.IsOpen() == false`
  - `client_train_empty`: no job, a Training Place, pets -> the sheet opens by itself; X on the sheet -> the window stays, `Key() == nil`, `PickPrompt` shown, every `Skill_*` has `State == "NoPet"` and an inactive "Pick a pet first" button, no cost / time text; `Step(1)` selects `Sorted(...)[1]`, `Step(-1)` from empty selects the last; a profile with no pets -> `Empty` reads "No pets yet! Spin a roulette in the Shop to hatch one." and the sheet does not open; no Training Place -> chip "No Training Place yet", body text "Build the Training Place at home first. Training makes pets tougher in battles!", skills `"NoPlace"`; `HintLine` shows "Pick a pet first" when a disabled skill button is tapped
  - `client_train_layouts`: 844x390 (touch), 1280x720, 1366x768, 1920x1080: `RedoGeom.check(Window_Train, ..., { NoOverlap = { "Mats", "PetCard", "PetName", "PetLevel", "PrevButton", "ChangeButton", "NextButton", "Skill_Speed", "Skill_Physique", "Skill_Ability", "Skill_Defense", "CloseButton", "SpotsChip" } })`; 844x390: box 820 x 330 at y 59, `Layout() == "Phone"`, the touch controls hidden while open and back after; resize while open (Review Focus 3): 1920x1080 -> 844x390 -> 1920x1080 with the window open passes the check each time; the empty state passes the check too
  - `client_train_portrait` (mobile world, 390x844): the pet above the skills in one column, the check passes
- [ ] **Step 2: Register** `if p5("smoke_redo_train.lua"): client_files.append(...); ins(client_scenarios, "client_final", ["client_train_ui", "client_train_wiring", "client_train_empty", "client_train_layouts"]); mobile_scenarios.append("client_train_portrait")` (after the picker line, so `RedoGeom` exists).
- [ ] **Step 3: Run** the five names -> FAIL.
- [ ] **Step 4: Implement** TrainController (H-table style; top-level locals <= 70) and the CareController changes (CareController locals <= 50).
- [ ] **Step 5: Rewrite** the Train parts of `smoke_p4_careui.lua`, `smoke_p5_gui.lua`, `smoke_p5_looks.lua` to the new window (same scenario names; same intent: train / stop / full / MAX / sizes / cover / evolved looks).
- [ ] **Step 6: Render** `train` at 844x390 and 1920x1080 into the evidence folder and look at them against `trainA`.
- [ ] **Step 7: Run** the five new names plus `client_p4careui_train,client_p4careui_feed,client_p4careui_garden,client_p4careui_evolve,client_p4careui_sizes,client_p4careui_mobile,client_p5gui_cover,client_p5looks,client_p2ui,client_tb_pets_actions,client_dgfix_mouse,p4care_feed,p2flow_build,contract` -> PASS (`client_p2ui` and `client_tb_pets_actions` assert `Care.Mode() == "Train"`, `Care.IsOpen()` and the way back to the Pets window, which the forwarding keeps; `p4care_feed` and `p2flow_build` pin the server's `OpenPanel("Train")` from the TrainPrompt). check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(gui-redo): Training Place window (big pet, four skill cards, its own confirm), Care forwards Train`, push, ledger.

**Only Studio can judge:** the look against the mock-up, the STOP confirm on a phone, the ‹ › feel, jobs ending while open.

### Task 8: The mats row (several pets in training)

Spec: 5.5 "The mats row".

**Files:**
- Modify: `src/client/Controllers/TrainController.lua`
- Modify: `tools/smoke_redo_train.lua`, `tools/smoke.py` (its line), `tools/dump_gui.lua` (scene `train:mats`), `tools/render_gui.py`

**Interfaces:**
- Consumes: Task 7's window and `Mats` band; `TycoonCatalog.TrainingSlots(home)`; `State.PetGrowthMap()`.
- Produces: `TrainController.Mats(home, growthMap, selectedKey) -> { [1..5] = { State = "Job" | "Pending" | "Add" | "Locked", Key = key | nil, Job = job | nil, Unlock = level | nil, LockBadge = boolean } }`, a pure function of its arguments with the display rules of spec 5.5: mat i shows the job whose `Job.Slot == i`; a job with no `Slot` or a second job on a taken slot takes the next free mat; a job on a mat above the open count stays on its mat with `LockBadge = true`; the first open mat with no job holds the selected pet when it is not training and a free mat exists (`"Pending"`); other open mats `"Add"`; mats above the open count `"Locked"` with `Unlock = i`. Five mats always (`MAX_TRAIN_SLOTS = 5`).
- Instances: `Mats` > `Mat1..Mat5` (attributes `State`, `Key`, `LockBadge`). Job mat: pet face (PetViewport Low), name, PC "Physique · Rank 5", a purple timer bar and "3:10 left"; tapping selects that pet. Pending: gold glow, "Pick a skill" (PC "Pick a skill below"). Add: dashed, "+ Add a pet", tapping opens the sheet. Locked: "Training Place Lv i" (phone "Lv i"); tapping shows in `HintLine`: "Upgrade your Training Place to Lv i to open this spot" (append the house name when the house tier caps the station, using the same TycoonCatalog cap the Home window uses for its "Needs the Villa" text). PC mats 5 x about 268 wide in a 132 band; phone mats 152 x 52, 8 px gaps, a 44 px face and one or two 15 px lines.

- [ ] **Step 1: Failing test `client_train_mats`** (1920x1080, then 844x390):
  - pure `Mats(...)`: slots 3, jobs on Slot 1 and Slot 3 -> `{ Job, Pending|Add, Job, Locked(4), Locked(5) }`; a selected free pet -> mat 2 `"Pending"`; a job with no Slot -> the first free mat; two jobs on Slot 2 -> the second on the next free mat; a job on Slot 5 with slots 3 -> mat 5 `"Job"` with `LockBadge == true`
  - UI: two jobs + one pending pet -> `Mat1.State == "Job"`, `Mat2.State == "Pending"`, `Mat3` `"Job"`... per the fixture; tapping a job mat selects that pet and its skill card turns `"Training"`; tapping `"Add"` opens the sheet; tapping a locked mat shows the HintLine text and nothing else
  - a job ending (advance past `Ends`, ProfileSync without the job) -> its mat back to `"Add"` (or `"Pending"`), the chip count drops
  - slots change while open (Review Focus 5): a ProfileSync raising the Training Place to Lv 4 -> `Mat4` turns open at once; a Prestige-like snapshot with slots 2 and a running job on Slot 3 -> `Mat3.State == "Job"` with `LockBadge == true`
  - `RedoGeom.check` at 844x390 and 1920x1080 with `NoOverlap = { "Mat1", "Mat2", "Mat3", "Mat4", "Mat5" }` and the mats band clear of `PetCard` and the skills
- [ ] **Step 2: Register** `client_train_mats` on Task 7's line.
- [ ] **Step 3: Run** `--only client_train_mats` -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: dump_gui `train:mats`** (Lv 3 place, two jobs, a pending pet, a job on a closed mat); render at both sizes, look at it against `trainC`'s mats.
- [ ] **Step 6: Run** `client_train_mats,client_train_ui,client_train_wiring,client_train_empty,client_train_layouts,client_train_portrait,client_p4careui_train,client_p5looks` -> PASS. TrainController locals <= 80. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(gui-redo): Training mats row: every pet in training on its spot, + Add a pet, locked spots`, push, ledger.

**Only Studio can judge:** the row with 1 to 5 spots, several pets training at once, a job on a mat a Prestige closed.

### Task 9: The Gifts window frame and the Daily page (card A) with the locked CLAIM

Spec: 5.1, 5.3 "Layout", "The window while locked".

**Files:**
- Modify: `src/client/Controllers/DailyController.lua` (header 1-61; `K` 84-...; `H.build` 671-871; `H.layoutWindow` 872-896; `H.renderDaily` 969-1019; `H.refreshPip` / `claimReady` 354-357; `Open` / `Close` 1307-1350)
- Modify (rewrite the window geometry assertions, keep the names): `tools/smoke_daily_ui.lua` (`client_daily_window`, `client_daily_pip`, `client_daily_mobile`), `tools/smoke_fixr_daily_ui.lua` (`client_fixr_daily_week`, `client_fixr_daily_repair`, `client_fixr_daily_fit`, `client_fixr_daily_stale`, `client_fixr_daily_repair_wait`, `client_fixr_daily_phone`, `client_fixr_daily_resize`, `client_fixr_menu_cover`, `client_fixr_touch_handoff`)
- Create: `tools/smoke_redo_daily_ui.lua` (client worlds)
- Modify: `tools/smoke.py`, `tools/dump_gui.lua` (scenes `daily`, `daily:locked`), `tools/render_gui.py`

**Interfaces:**
- Consumes: payload `Unlock = { Need, Left }` (Task 4; a payload without it is unlocked), `Play.DayEnds`, `Play.Active`, `ServerNow`, `ReadyAt`, `Repair`, `StaleAt`, `Loading`.
- Produces:
  - `DailyController.ClaimView(st, now, touch) -> { Mode = "Claim" | "Repair" | "Locked" | "Wait" | "Stale" | "Loading", Line1, Line2 }` (pure). Locked: `Line1 = "Unlocks after 10 min of play"` (the minutes from `Need`), `Line2` by spec 5.3's priority: `"Day resets in N min"` when the play-day started and `DayEnds - now < Left`; else `"Paused: move around!"` (PC) / `"Paused: close this and move!"` (touch) when `Play.Active == false`; else `"N min to go"`. N counts down from `ServerNow` while Active and holds at 1 until a payload says `Left == 0`. Wait / Stale / Loading keep today's texts ("Next gift in 4h 12m", "Streak repair in 4h 12m", "Getting your gifts ready...").
  - `DailyController.Layout() -> "PC" | "Phone" | "Portrait"`.
  - The pip shows only when a claim is unlocked (`ClaimView(...).Mode` is `"Claim"` or `"Repair"`) or a play tier is Ready.
  - Window: BigRect `W1 = 1180`, `Y1 = 720`, centred (no longer under the Gifts button; the button, pip and ring stay). `NimbusDaily` keeps `IgnoreGuiInset = false`, so the holder sits at `(r.x, r.y - GuiService:GetGuiInset().Y)`. `SetTouchHidden("Daily", ...)` and `SetColumnCovered(..., "Daily")`. The Play tab keeps today's rows inside the new body until Task 10.
  - Daily page (`dailyA`): `Header` "Day 3 of 7 · Week 2"; `StreakChip` "Streak: 9" (PC "Streak: 9 days"); `VipChip` "VIP x2" (VIP only); `Cells` > `Cell1..7` glossy tiles in `DAY_COLORS` (phone 92 x 122, Day 7 180, 8 px gaps, from y 48; PC 128 x 260, Day 7 264, 16 px gaps), Day 7 shows the Week Wisp (PetViewport), claimed dimmed with a tick, today raised 8 px, Neon gold, its glow pulsing; `WispText` "Week Wisp in N more days" (N = 7 - Cell; Cell 7 -> "Week Wisp today!") over `WispBar` (7 segments); `ClaimButton` (phone 230 x 64 at the right; PC 360 x 88 centred) with `Line1` / `Line2` labels for the locked state (grey, disabled); `Countdown`; `Keep` "Come back tomorrow to keep your streak!"; `WeekBanner`. Every other behaviour of today's window stays (the Repair look, the pop + "Reward" sound, the week sweep + confetti, the StepBack hint, the fit fallbacks).

- [ ] **Step 1: Failing tests in `tools/smoke_redo_daily_ui.lua`**:
  - `client_daily_ui_a` (1920x1080 then 844x390 touch): a ready payload -> 7 cells, `Cell3` raised 8 px over `Cell2` and gold, `Cell7` twice `Cell1`'s width (+ the gap), claimed cells show the tick; `WispText` "Week Wisp in 4 more days"; `ClaimButton` "CLAIM!" active; tapping it sends `DailyRequest("Claim")` once
  - `client_daily_locked`: `ClaimView` cases: locked + Active -> "Unlocks after 10 min of play" / "6 min to go"; locked + not Active -> "Paused: move around!" (touch false) and "Paused: close this and move!" (touch true); `DayEnds - now = 240`, `Left = 360` -> "Day resets in 4 min"; the count goes 6 -> 5 after `advance(60)` while Active, stays while not Active, never below "1 min to go" without a new payload; no `Unlock` field -> `"Claim"`; repair + locked -> locked lines on the "Repair streak (no gift)" button style; UI: the locked button is disabled and shows both lines at >= 15 px on 844x390 inside 230 x 64; the pip hidden while locked, shown after a payload with `Left == 0`; a payload arriving while the window is open switches the button without reopening
  - `client_daily_layouts`: 844x390 (touch), 1280x720, 1920x1080: `RedoGeom.check(DailyWindow, ..., { NoOverlap = { "Tab_Daily", "Tab_Play", "CloseButton", "Header", "StreakChip", "VipChip", "Cells", "WispText", "WispBar", "ClaimButton", "Keep" } })`; 844x390: the window 820 x 330 and centred; touch controls hidden while open, back after
  - `client_daily_portrait` (mobile, 390x844): the day tiles 4 per row, the check passes
- [ ] **Step 2: Register** `if p5("smoke_redo_daily_ui.lua"): client_files.append(...); ins(client_scenarios, "client_final", ["client_daily_ui_a", "client_daily_locked", "client_daily_layouts"]); mobile_scenarios.append("client_daily_portrait")` (after the picker line).
- [ ] **Step 3: Run** the four names -> FAIL.
- [ ] **Step 4: Implement** (DailyController locals <= 70; new helpers in `H`).
- [ ] **Step 5: Rewrite** the listed `smoke_daily_ui.lua` / `smoke_fixr_daily_ui.lua` geometry assertions to the BigRect window (same names, same intent: targets >= 44, texts >= 15 / 14, the cover, the touch hand-off, the resize, the stale / repair / week states).
- [ ] **Step 6: dump_gui** `daily` (ready, VIP, Week 2 Day 3) and `daily:locked` (6 min to go); render both at 844x390 and 1920x1080, look at them against `dailyA`.
- [ ] **Step 7: Run** the four new names plus `client_daily_window,client_daily_pip,client_daily_chips,client_daily_vip,client_daily_mobile,client_fixr_daily_week,client_fixr_daily_play_cells,client_fixr_boost_toast,client_fixr_daily_repair,client_fixr_boost_pass,client_fixr_daily_fit,client_fixr_daily_stale,client_fixr_daily_repair_wait,client_fixr_daily_phone,client_fixr_daily_resize,client_fixr_menu_cover,client_fixr_touch_handoff` -> PASS. check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(gui-redo): Gifts window as a big centred window; Daily page with glossy tiles and the locked CLAIM`, push, ledger.

**Only Studio can judge:** today's glow and pulse, the Week Wisp on Day 7, the locked CLAIM's two lines on a phone, the week-done banner.

### Task 10: The Play time page (card B) and Claim All on the client

Spec: 5.4.

**Files:**
- Modify: `src/client/Controllers/DailyController.lua` (`H.renderPlay` 1020-1067, the Play page in `H.build`, `H.tick`)
- Modify: `tools/smoke_fixr_daily_ui.lua` (`client_fixr_daily_play_cells` rewritten to the boxes), `tools/smoke_redo_daily_ui.lua`, `tools/smoke.py` (its line), `tools/dump_gui.lua` (scene `daily:play`), `tools/render_gui.py`

**Interfaces:**
- Consumes: `DailyRequest("ClaimPlayAll")` (Task 5); payload `Play = { Seconds, DayEnds, Active, Tiers }`, `ServerNow`.
- Produces:
  - `DailyController.TierCountdown(i, st, now) -> text` (pure): the time to the tier's minute = `Min * 60 - live` with `live = Play.Seconds + (Active and (now - ServerNow) or 0)`; `"13:00"` (mm:ss) under an hour, `"2h 13m"` from an hour; never below `"0:01"` until a payload marks the tier Ready; frozen while `Active == false`.
  - Play page (`playB`): `PlayHeader` "47 min played today · Resets in 5h" (phone "47 min today · Resets in 5h"), or gold "Paused: move around to keep counting!" (touch: "Paused: close this and move around!") while not Active; `ClaimAll` "CLAIM ALL (n)" (phone 166 x 44, PC 252 x 60), greyed at 0 with the layout still, sends `DailyRequest("ClaimPlayAll")` with the 1 s client gap; `Tiers` > `Tier1..7` gift boxes in `TIER_COLORS` (phone 104 x 204 in one row, x step 116; PC 260 x 250, four on top and three under, centred): `Time` "10 min", `Gift` (tinted Gifts icon, bobbing when Ready), `Reward` (resolved amount; "Berry Basket" / "Full Basket" fit fallback), and one of `Claim` (green "CLAIM", the box pulsing), `Clock` (clock glyph + `TierCountdown`), `Check` (claimed, dimmed). A single box CLAIM still sends `DailyRequest("ClaimPlay", i)`.

- [ ] **Step 1: Failing tests** (in `smoke_redo_daily_ui.lua`):
  - `client_play_ui_b`: 47 min played, tiers 1-2 claimed, 3 Ready -> `Tier3.Claim` visible, `Tier4.Clock` reads "13:00", `ClaimAll` "CLAIM ALL (1)"; `advance(60)` while Active -> "12:00"; Active false -> it holds, header gold paused text (touch: the close-this text); `Tier5` at 90 min reads "43:00"; a tier 2 h away reads "2h 13m"; at 1 s left without a payload it stays "0:01"; tapping `ClaimAll` sends exactly one `DailyRequest("ClaimPlayAll")`, a second tap within 1 s sends nothing; with 0 Ready `ClaimAll` is inactive and keeps its size and place
  - `client_play_layouts`: 844x390 (touch), 1280x720, 1920x1080: `RedoGeom.check` with `NoOverlap = { "Tab_Daily", "Tab_Play", "CloseButton", "PlayHeader", "ClaimAll", "Tier1", ..., "Tier7" }`; phone: 7 boxes in one row
  - `client_play_portrait` (mobile, 390x844): boxes 4 per row, the check passes
- [ ] **Step 2: Register** the three names on Task 9's line (`client_play_portrait` in `mobile_scenarios`).
- [ ] **Step 3: Run** them -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Rewrite** `client_fixr_daily_play_cells` to the gift boxes (same intent: every tier as a reward cell with its state). dump_gui `daily:play` (47 min, tier 3 ready, paused); render at both sizes, look at it against `playB`.
- [ ] **Step 6: Run** the three plus Task 9's whole list -> PASS. DailyController locals <= 72. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(gui-redo): Play time as gift boxes with their own countdowns and CLAIM ALL`, push, ledger.

**Only Studio can judge:** the boxes' bob, Claim All's toast, countdowns freezing while paused, the client countdown against the server's 10 s tick.

### Task 11: The Fusion Machine window (card A) with the picker

Spec: 5.6 (all but the move choice), 5.1.

**Files:**
- Modify: `src/client/Controllers/FusionController.lua` (header 1-37; `K` 81-125; remove the left grid: `pickerKeys` 810, `destroyTileViewport` / `buildTileViewport` / `onTileClicked` / `newTile` / `paintTile` / `refreshTiles` / `fillViewports` 836-1047, `buildPicker` 1899; rebuild `relayout` 710, `layoutPreview` 1096, `buildPreview` 1946, `buildWindow` 2137; `closeOthers` 2177 adds `DailyController`; `Init` 2314: `NimbusFusion` `IgnoreGuiInset = true`, Esc / B ask the sheet first)
- Modify (rewrite, keep names): `tools/smoke_p2_fusion.lua` (`client_p2fusion`: slots and the sheet instead of tiles), `tools/smoke_p5_gui.lua` (the `"fusion"` COVER entry: `Centered = true`, `MaxCover = 85`), `tools/smoke_p5_looks.lua` (the Fusion check: the picker's cards draw the copies' stages 1 and 2), `tools/smoke_p2_visual.lua` (its `Window_Fusion` checks), `tools/smoke_dgfix_mouse.lua` (only if it breaks: it opens `Window_Fusion`)
- Create: `tools/smoke_redo_fusion_ui.lua` (client worlds)
- Modify: `tools/smoke.py`, `tools/dump_gui.lua` (scenes `fusion` = `fusion:upgrade`, `fusion:mix`), `tools/render_gui.py`

**Interfaces:**
- Consumes: `PetPicker` (Task 6) with `Context = "Upgrade"` (Title "Pick a pet to upgrade") / `"Mix"` (Titles "Pick the Body pet" / "Pick the Style pet", `Blocked` = every owned key of the other slot's species, any finish (`maple_fox`, `maple_fox@Golden`, ...), mapped to `"In Body"` / `"In Style"`).
- Produces: the API stays: `Open(tab, args)`, `Close`, `IsOpen`, `Plan`, `Select(keyA, keyB)`, `Fuse`, `Opened`, `Closed`; plus `FusionController.Layout() -> "PC" | "Phone" | "Portrait"`. Instances: ScreenGui `NimbusFusion` (22) > `Window_Fusion` (UIScale `Fit`) > `Header` (`Tab_Upgrade` "UPGRADE", `Tab_Mix` "MIX", balance chips, `CloseButton`), `Body` > Upgrade: `Stack` (three fanned cards: "COPIES", the pet, "Uncommon · Flame"), `CopiesText` "x5 owned · uses 3", `Arrow`, `Result` (big, glowing: Golden gold + sparks, Rainbow shimmer; `Pills` with rarity and "x1.5 power" / "x2.5 power"), `Note` (the plan's notes / reason, `WARN` colour); Mix: `Slot_Body`, `SwapButton`, `Slot_Style`, `Arrow`, `Result` "NEW HYBRID" (violet glow, bob, the blended name, `Pills`: rarity, "Flame + Storm" in the record's element order, finish), `Info` (PC only: "Your hybrid gets its own random look. Hybrids are one of a kind and can't be fused again."); both: `CostBar` (`Cost` token icon + amount, `Have` "You have 12,480 Cloud Tokens", red when short), `FuseButton` "FUSE!" (pulsing when possible), `HintLine`. BigRect `W1 = 1440`, `Y1 = 880`; positions from `fuseA` (the PC mock is 1520 wide: lay it out in the real design box). `SetTouchHidden("Fusion", ...)`, `SetColumnCovered(..., "Fusion")`. Tapping the stack opens the Upgrade sheet; tapping a slot opens the Mix sheet for it. Opening the Upgrade tab with no pet, or Mix with an empty slot, opens the sheet by itself (Body first; after a pick the other empty slot's sheet opens once; closing the sheet without a pick ends that chain). The swap button swaps Body and Style. The success animation, the machine's output burst, the walk-away close and the near check stay. Closing the window closes the sheet.

- [ ] **Step 1: Failing tests in `tools/smoke_redo_fusion_ui.lua`**:
  - `client_fusion_ui_a` (1920x1080): Upgrade with `Key` = a 5-copy pet -> `Stack` shows it, `CopiesText` "x5 owned · uses 3", `Result` "Golden Maple Fox", pills "Uncommon" / "x1.5 power", the note "1 team copy is taken off first; the new pet takes the slot" when a team copy is used, `FuseButton` active; tapping `Stack` opens the sheet with `Context == "Upgrade"`; FUSE sends `Fusion("Upgrade", key)`; opening Upgrade with no pet opens the sheet by itself; Mix: both slots empty -> the Body sheet opens, a pick -> the Style sheet opens with the Body species blocked (`"In Body"`), a pick -> both slots filled, the NEW HYBRID card shows the blended name and "Flame + Storm"; closing the Style sheet without a pick leaves Style empty and opens nothing more; the swap button swaps the two pets; Esc with the sheet open closes only the sheet; Close closes the sheet too
  - `client_fusion_layouts`: Upgrade and Mix at 844x390 (touch), 1280x720, 1920x1080: `RedoGeom.check(Window_Fusion, ..., { NoOverlap = { "Stack" | "Slot_Body", "SwapButton", "Slot_Style", "Arrow", "Result", "CostBar", "FuseButton", "Note" | "Info", "Tab_Upgrade", "Tab_Mix", "CloseButton" } })`; 844x390: 820 x 330 at y 59; touch controls hidden while open
  - `client_fusion_portrait` (mobile, 390x844): the slots above the result, the check passes
- [ ] **Step 2: Register** `if p5("smoke_redo_fusion_ui.lua"): client_files.append(...); ins(client_scenarios, "client_final", ["client_fusion_ui_a", "client_fusion_layouts"]); mobile_scenarios.append("client_fusion_portrait")` (after the picker line).
- [ ] **Step 3: Run** the three -> FAIL.
- [ ] **Step 4: Implement** (FusionController top-level locals <= 130; new helpers in one `H` table).
- [ ] **Step 5: Rewrite** `client_p2fusion`, the Fusion parts of `client_p5gui_cover`, `client_p5looks`, `client_p2visual` (and `client_dgfix_mouse` if it breaks) to the new window, same intent.
- [ ] **Step 6: dump_gui** `fusion` / `fusion:upgrade` (a 5-copy pet with a team copy) and `fusion:mix` (Maple Fox + Storm Tabby); render both tabs at 844x390 and 1920x1080, look at them against `fuseA`.
- [ ] **Step 7: Run** the three plus `client_p2fusion,client_p2visual,client_p5gui_cover,client_p5looks,client_dgfix_mouse,p2fusion_upgrade,p2fusion_mix,fusion_moves` -> PASS. check.mjs 0 errors.
- [ ] **Step 8: Commit** `feat(gui-redo): Fusion Machine window: slots, arrow, the big result, one FUSE; every slot opens the picker`, push, ledger.

**Only Studio can judge:** the result glow and sparks, the fusion animation in the new layout.

### Task 12: The move chips (Mix)

Spec: 5.6 "The move choice" (incl. the phone outcome line), 11 calls 6-7.

**Files:**
- Modify: `src/client/Controllers/FusionController.lua` (`computePlan` 531-586 builds the preview record through `PetKeys.MixMoves`; `Fuse` 1721-1758 sends `moves`; the chips; the outcome lines)
- Modify: `tools/smoke_redo_fusion_ui.lua`, `tools/smoke.py` (its line)

**Interfaces:**
- Consumes: `PetKeys.ValidMoves`, `PetKeys.MixMoves` (Task 2); `BattleCatalog.ElementAttacks[e].Name`, `def.Special.Name` / `.Kind`, `BattleCatalog.Specials[Kind]`.
- Produces:
  - `FusionController.SetMoves(attackKey, specialKey)` (each must be the Body or the Style key; anything else is ignored); `FusionController.Moves() -> "BB" | "BS" | "SB" | "SS"` (letter 1 = the attack's parent, letter 2 = the special's); `FusionController.MovesText(bodyKey, styleKey, moves) -> { Attack = { Element, Name }, Special = { Kind, Name } }` (stage 0 names).
  - The choice follows the pet: the swap button keeps each move with its pet (the letters flip); picking a new pet for either slot resets to `"BB"`; equal elements: both attack chips lit and inactive.
  - `Fuse()` sends `remote:FireServer("Mix", S.MixA, S.MixB, FusionController.Moves())`.
  - Instances: `Chips_Body` and `Chips_Style` under their slots, each with `Attack` ("⚔ Flare", PC "Flare · Flame") and `Special` ("★ Leaf Pounce", PC "Leaf Pounce · Pounce"), attribute `Lit`; the lit chip has a gold border and a check. Phone chips 130 x 44 under 130 x 148 slots; PC chips about 310 x 56. Outcome: PC `OutcomeAttack` "Normal attack: Flame (Flare)" and `OutcomeSpecial` "Special: Pounce (Leaf Pounce)" inside `Result` above its pills (22 px); phone one `Outcome` line at x 14, y 222, 792 x 40, 15 px: "Normal attack: Flame (Flare) · Special: Pounce (Leaf Pounce)", falling back to "Normal attack: Flare · Special: Leaf Pounce" when the measured text is too wide, then wrapping inside the 40 px; never cut. The NEW HYBRID pills show the record's element order.

- [ ] **Step 1: Failing test `client_fusion_moves`** (1920x1080 and 844x390):
  - Body Maple Fox + Style Storm Tabby: `Moves() == "BB"`, `Chips_Body.Attack.Lit` and `Chips_Body.Special.Lit`, PC `OutcomeAttack.Text == "Normal attack: Flame (Flare)"`, `OutcomeSpecial.Text == "Special: Pounce (Leaf Pounce)"`
  - tap `Chips_Style.Special` -> `"BS"`, the special lines read Static Storm; tap `Chips_Style.Attack` -> `"SS"`, pills "Storm + Flame"; `FuseButton` -> exactly one `Fusion("Mix", maple, tabby, "SS")` sent
  - swap -> Body = Storm Tabby, `Moves() == "BB"` (the moves stayed with Storm Tabby, now Body), the chips lit under the new Body
  - picking a new Style pet -> `"BB"`
  - equal elements (two Flame pets): both `Attack` chips `Lit` and inactive; the special still choosable
  - `MovesText(maple, tabby, "SB")` -> `Attack = { Element = "Storm", Name = "Bolt" }`, `Special = { Kind = "Pounce", Name = "Leaf Pounce" }`
  - 844x390: `Outcome.Text == "Normal attack: Flame (Flare) · Special: Pounce (Leaf Pounce)"`; a pair whose special is "Wish Upon the Stars" -> the text fits its box (fallback or two lines), `TextFits` true; `RedoGeom.check` with `NoOverlap = { "Slot_Body", "Chips_Body", "SwapButton", "Slot_Style", "Chips_Style", "Result", "Outcome", "CostBar", "FuseButton" }`; at 1920x1080 the same with `OutcomeAttack` / `OutcomeSpecial` inside `Result`
- [ ] **Step 2: Register** `client_fusion_moves` on Task 11's line.
- [ ] **Step 3: Run** -> FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Render** `fusion:mix` again at both sizes with "BS" chosen; look at the chips and the outcome line.
- [ ] **Step 6: Run** `client_fusion_moves,client_fusion_ui_a,client_fusion_layouts,client_fusion_portrait,client_p2fusion,fusion_moves,hybrid_moves_def` -> PASS. FusionController locals <= 135. check.mjs 0 errors.
- [ ] **Step 7: Commit** `feat(gui-redo): Mix lets the player pick each parent's normal attack and special`, push, ledger.

**Only Studio can judge:** the chips on a phone; in a battle, a new hybrid's Element and Special buttons showing the chosen names, an evolved hybrid's form names, other players seeing its aura by the chosen element.

### Task 13: Docs, evidence and the gate

**Files:**
- Modify: `README.md` (the Gifts section: the 10-minute rule, the hold in one plain line, Claim All; the Training Place: the mats row and the picker; Fusion: the move choice), `BUILD_STATE.md` (one dated entry in "Player decisions", the shape of the 2026-11-06 bug batch entry: branch, spec, plan, what each window became, the owner's three notes, the calls of spec 11, what only Studio can judge), `brain.md` (one dated decision line: the window redo and its three rule changes)
- Evidence: `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.superpowers\gui-pitch\evidence\` (git-ignored, outside the repo)

- [ ] **Step 1: Docs.** Run `p2final_docs` (README matches the game) and fix what it reports.
- [ ] **Step 2: Evidence renders:** `py -3.12 tools/render_gui.py <scene> --size 844x390 -o <evidence>\<scene>_phone.png` and `--size 1920x1080 ... _pc.png` for `daily`, `daily:locked`, `daily:play`, `train`, `train:mats`, `fusion:upgrade`, `fusion:mix`, `picker:train`, `picker:upgrade`. Look at every image; the report's smallest text must be >= 14 px; nothing under the top bar; list them in the ledger.
- [ ] **Step 3: Fast signal** (speed scout): `py -3.12 tools/smoke_parallel.py --quick --json <scratch>\par.json`; fix any failure in its owning task's files (commit as `fix(gui-redo): ...`).
- [ ] **Step 4: The gate** (one run each, nothing else changing meanwhile): `py -3.12 tools/smoke.py --quick --json <scratch>\gate.json` -> 0 failed; `py -3.12 tools/smoke.py --quick --mesh` -> 0 failed; `node tools/check.mjs` -> 0 errors; `py -3.12 tools/sim_tycoon.py --check` -> ok; `py -3.12 tools/count_locals.py` -> no file at 200 (report DataService, MenuController, FusionController, TrainController, PetPicker, DailyController).
- [ ] **Step 5: Commit** `gate(gui-redo): window redo, whole smoke <passed> / 0 failed, --mesh <n> / 0, check.mjs 0 errors, sim_tycoon --check ok`, push, ledger line with the numbers and the evidence list. No merge.
</content>
</invoke>
