# HUD cleanup + Ring no-heal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Shop / Travel / Settings into a top-left pill with a server-validated Quick Travel, put battle-team editing at the portals and in the Pets window, remove the obby items (with a one-time Token refund), and make the Champion Ring a no-heal climb against champions built with the player pet stat formula.

**Architecture:** Tasks 1-3 are client/server UI and data work on branch `hud-cleanup` (worktree `Projects Main\Nimbus\.worktrees\hud`), one after another, each adding its own `tools/smoke_hud_*.lua` file. Task 4 is battle-engine and catalog work on its own branch `hud-ring` (worktree `Projects Main\Nimbus\.worktrees\ring`, cut from `hud-cleanup` at the plan commit), in parallel; it touches only `BattleCatalog.lua`, `BattleSim.lua`, `BattleService.lua`, `tools/sim_battle.lua`, the Ring lines of `ArenaController.lua` and its own smoke file, never `MenuController` / `HudController` / the other client UI files. All smoke tests run through `tools/smoke.py` (lupa + `tools/robloxmock.lua`); the ring balance through `tools/sim_battle.lua`.

**Tech Stack:** Roblox Luau (plain Lua 5.1 syntax, the repo rule), Rojo, Python 3.12 + lupa for `tools/smoke.py` and `tools/sim_battle.lua`, `tools/contract.json` + `tools/check.mjs` for the module API contract.

**Spec:** `nimbus-climb/docs/superpowers/specs/2026-10-30-hud-cleanup-design.md`

## Global Constraints

- Every Lua file: plain Lua 5.1-compatible syntax only (no `continue`, no `+=`, no type annotations); all client text goes through `Theme` roles; UI built on `CloudUI` / `NeonKit`.
- Pill position is read from `GuiService:GetGuiInset()` / `GuiService.TopbarInset` (under `pcall`), **never hard-coded**; `212` px is only the fallback when `TopbarInset` is unavailable or zero (spec decision 1).
- The pill never overlaps Roblox's top-bar buttons or the chat window on any screen size (anti-goal 1): it stays inside the top-bar band (`y` in `0 .. inset`) and left of `TopbarInset.Max.X`.
- Shop stays refused during a match ("The shop is closed during a match.", the existing `menuActionShop` rule).
- Travel is lobby only: hidden in a match (`Config.Attr.InMatch == true`), a battle / dungeon run / Ring (`Config.Attr.InBattle ~= nil`), on the Arena island (`workspace.BattleArena` bounding box) and the Altar island (`workspace` model `StormAltar` bounding box); the server validates every teleport (rate limit, lobby zones only, not `InBattle`, not in a party countdown).
- Item refund: exactly once per profile, Tokens at the catalog prices **30 / 45 / 150** per `heal_cloud` / `shield_bubble` / `phoenix_feather`, counts clamped to the old `MaxCarry` 5, then `Items` cleared, under the migration marker `Migrations.B3ItemsRefund` (anti-goal 3: never lose Tokens or pets).
- Ring: no heal between rounds; a fainted pet stays out for the run; champions use `PetCatalog.GetStats` through `BattleCatalog.UnitStats` with **no** `Boss` / `Handicap` / `Boost`; the champion level never exceeds `PetCatalog.MaxPetLevel()` (100) and the champion team never exceeds 3 pets. A Ring run must never end on rounds 1-2 for a normal team (anti-goal 4).
- Every tutorial step text stays 97-125 bytes of plain text once placeholders are filled; every NPC line <= 125 bytes, 3-5 lines per NPC (`p5ui_content` / `p3ui_content` / `p4ui_content` smoke rules).
- Every new `tools/smoke_*.lua` is registered in `tools/smoke.py` (`server_files` / `client_files` + the scenario lists) and every public member added or removed goes into `tools/contract.json`.
- Commit after every task; every commit message ends with the two attribution lines:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01Cc7CpzuTkbb2pa3VwfYzXA`.

## Review Focus

1. A phone in a battle shows the HUD's TopBand currency row starting at `K.BAND_LEFT` 150, under the new pill: the row must start right of the pill (test in Task 1, `client_hudpill_mobile`).
2. A player taps Quick Travel while standing on a portal pad in its party countdown (`PortalService.IsLocked`) or mid-dungeon-party: the server must refuse and the countdown must not be broken (test in Task 1, `hudpill_travel`).
3. A player with 1 or 2 pets (not 3) presses a team portal with an empty team: the popup must save a 1-2 pet team and continue; a player with 0 pets must see the "You need a pet" hint and no popup (test in Task 2, `client_hudteam_portal`).
4. An old save with `Items` counts above 5 or with an unknown item id: the refund clamps to 5 per item and pays 0 for unknown ids; a save touched by the refund that is merged with a provisional/recovered copy must not pay twice (test in Task 3, `huditems_refund`).
5. A Ring pet that levels up between rounds (XP from the win): its carried HP is a FRACTION, so a bigger max HP does not heal it beyond its share; a pet at exactly 0 HP after a won round (killed as the last blow lands) is fainted, not revived (test in Task 4, `ringnh_sim_hp`).

---

### Task 1: Top-left pill (Shop / Travel / Settings) + Quick Travel

**Files:**
- Create: `src/client/Controllers/TopBarController.lua`
- Modify: `src/client/Controllers/MenuController.lua:2103-2126` (MENU table + its comment), `:2083-2105` (`P5.openSettings` becomes public), `:9115-9125` (`MenuController.Open`)
- Modify: `src/client/Controllers/HudController.lua:113-116` (band constants), `:799-800`, `:903`, `:910` (the TopBand row's left edge)
- Modify: `src/client/Main.client.lua:19-20` (boot list)
- Modify: `src/shared/Config.lua:91-135` (`Config.Remotes`: add `"QuickTravel"`)
- Modify: `src/server/Services/GateService.lua` (header, `Travel`, Init remote wiring)
- Modify: `src/server/Main.server.lua:376-382` (GateService deps)
- Modify: `tools/contract.json` (`v3.menuEntries`, new module, GateService / MenuController functions)
- Modify: `tools/smoke_client.lua:1365-1410`, `tools/smoke_client_v2.lua:995-1040`, `tools/smoke_p5_looks.lua:418-445`, `tools/smoke_bug2_gui.lua:101`, `tools/smoke_p3_ui.lua:583-590`, `tools/dump_gui.lua:2281`
- Create: `tools/smoke_hud_pill.lua`; Modify: `tools/smoke.py` (register it)

**Interfaces:**
- Consumes: `MenuController.Open(panelId, args)`, `MainMenuController.OpenSettings()` (via `MenuController.OpenSettings`), `HudController.GetLayout()`, `Remotes.Get(name)`, `GateService.Teleported`, `PlayerService.GetLobbySpawnCFrame()`, `ArenaBuilder.ZoneAt(position)`, `PortalService.IsLocked(player)`, `LobbyInfo.GateSites.Ring`.
- Produces:
  - `TopBarController.Init()`, `TopBarController.GetRect() -> { X0, X1, Y0, Y1 } | nil` (screen px of the pill), `TopBarController.TravelAllowed() -> boolean`, `TopBarController.Refresh()`.
  - ScreenGui `NimbusTopBar` (`IgnoreGuiInset = true`, DisplayOrder 21) holding Frame `Pill` with TextButtons `PillButton_Shop`, `PillButton_Travel`, `PillButton_Settings`, Frame `TravelMenu` (TextButtons `TravelPortals`, `TravelLobby`), Frame `TravelFade`; attributes `PillRight` and `PillBottom` (screen px) on the ScreenGui, refreshed on every relayout (0 when the pill is hidden).
  - `MenuController.OpenSettings()` (public; the old `P5.openSettings` body).
  - Remote `QuickTravel` (client -> server, `(dest: "Court" | "Plaza")`).
  - `GateService.Travel(player, dest) -> ok, reason` (reasons: `"junk"`, `"dead"`, `"match"`, `"battle"`, `"locked"`, `"zone"`, `"cooldown"`, `"failed"`), `GateService.CourtCFrame() -> CFrame | nil`; `GateService.Teleported:Fire(player, "Court" | "Plaza")`.
  - `tools/contract.json` `v3.menuEntries = ["Pets", "Index", "Spot", "Stats"]`.

- [ ] **Step 1: Write the failing smoke file `tools/smoke_hud_pill.lua`** (both worlds, `ARGS.context` picks the half, the `smoke_bug11_ring.lua` shape). Scenarios and assertions:

```lua
-- server: hudpill_travel  (booted server, simulated players via K.addPlayer; GateService + lobby built)
T.check(type(GS.Travel) == "function" and type(GS.CourtCFrame) == "function", "GateService.Travel / CourtCFrame exist")
local court = GS.CourtCFrame()
local site = K.lobbyInfo.GateSites.Ring
T.check(typeof(court) == "CFrame" and (court.Position - (site.Position + site.LookVector * 16 + Vector3.new(0, 3, 0))).Magnitude < 0.5, "CourtCFrame = 16 studs in front of the Ring gate, 3 up")
T.check(court.LookVector:Dot((site.Position - court.Position).Unit) > 0.9, "...facing the gates")
T.eq(select(1, GS.Travel(a, "Court")), true, "Travel(Court) from the plaza works")
T.check((root(a).Position - court.Position).Magnitude < 2, "...the character stands at the court")
T.eq(select(2, GS.Travel(a, "Plaza")), "cooldown", "a second travel inside 2 s is refused (cooldown)")
advance(2.1)
T.eq(select(1, GS.Travel(a, "Plaza")), true, "Travel(Plaza) works after the cooldown")
T.check((root(a).Position - PlayerService.GetLobbySpawnCFrame().Position).Magnitude < 2, "...at the lobby spawn")
T.eq(select(2, GS.Travel(a, "Home")), "junk", "unknown destinations are junk")
T.eq(select(2, GS.Travel(a, 5)), "junk", "non-string destinations are junk")
a:SetAttribute(Config.Attr.InMatch, true); advance(2.1)
T.eq(select(2, GS.Travel(a, "Court")), "match", "refused in an obby match")
a:SetAttribute(Config.Attr.InMatch, false); a:SetAttribute(Config.Attr.InBattle, "D7"); advance(2.1)
T.eq(select(2, GS.Travel(a, "Court")), "battle", "refused in a battle / dungeon run")
a:SetAttribute(Config.Attr.InBattle, nil)
-- locked on a portal pad (PortalService: step onto the Obby pad -> IsLocked)
K.stepOnPad(a, K.lobbyInfo.Portals.Obby); advance(0.5)
T.eq(select(2, GS.Travel(a, "Court")), "locked", "refused while locked on a portal pad (party countdown)")
T.check(PortalService.IsLocked(a), "...and the countdown is untouched")
K.leavePad(a); advance(2.1)
-- outside the lobby cylinder (a dungeon run's place) / inside an arena zone
K.place(a, CFrame.new(Config.Lobby.Origin + Vector3.new(0, -300, 0))); advance(2.1)
T.eq(select(2, GS.Travel(a, "Court")), "zone", "refused outside the lobby world (Y band)")
K.place(a, ArenaInfo.Pockets[1].CFrame); advance(2.1)
T.eq(select(2, GS.Travel(a, "Court")), "zone", "refused inside an arena fight zone (ArenaBuilder.ZoneAt)")
-- the remote: garbage never errors, rate-limited
local errs = #Mock.Errors
Mock.FromClient(R.QuickTravel, b, nil)
for _, junk in ipairs({ 1, {}, "Court\0", string.rep("x", 100) }) do Mock.FromClient(R.QuickTravel, b, junk) end
T.eq(#Mock.Errors, errs, "QuickTravel with garbage raises no errors")
local fired = {}; GS.Teleported:Connect(function(p, id) fired[#fired + 1] = id end)
Mock.FromClient(R.QuickTravel, b, "Court"); Mock.FromClient(R.QuickTravel, b, "Plaza")
T.check(#fired == 1 and fired[1] == "Court", "the remote travels once per 2 s and Teleported fires (player, 'Court')")

-- client: client_hudpill  (1920x1080 desktop)
local gui = pg():FindFirstChild("NimbusTopBar")
T.check(gui and gui.IgnoreGuiInset == true and gui.DisplayOrder == 21, "NimbusTopBar ScreenGui (IgnoreGuiInset, order 21)")
local pill = gui.Pill; local inset = GuiService:GetGuiInset().Y
T.check(pill.AbsolutePosition.X >= 212 - 1, "the pill starts right of Roblox's top-bar buttons (TopbarInset.Min.X + 8, fallback 212)")
T.check(pill.AbsolutePosition.Y >= 0 and pill.AbsolutePosition.Y + pill.AbsoluteSize.Y <= inset, "...inside the top-bar band")
for _, n in ipairs({ "Shop", "Travel", "Settings" }) do T.check(pill:FindFirstChild("PillButton_" .. n, true) ~= nil, "button PillButton_" .. n) end
T.check(tonumber(gui:GetAttribute("PillRight")) == pill.AbsolutePosition.X + pill.AbsoluteSize.X, "attribute PillRight = the pill's right edge")
Mock.Click(pill.PillButton_Shop); advance(0.5)
T.check(shown(menu():FindFirstChild("Window_Shop")), "Shop opens the Cloud Shop window")
LocalPlayer:SetAttribute(Config.Attr.InMatch, true); Mock.Click(pill.PillButton_Shop); advance(0.3)
T.check(not shown(menu():FindFirstChild("Window_Shop")) and hintText():find("closed during a match"), "Shop is refused in a match with the hint")
LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
Mock.Click(pill.PillButton_Settings); advance(0.5)
T.check(settingsHolder() ~= nil, "Settings opens MainMenuController's settings panel")
T.check(pill.PillButton_Travel.Visible, "Travel shows in the lobby")
Mock.Click(pill.PillButton_Travel); advance(0.2)
local tm = gui:FindFirstChild("TravelMenu", true)
T.check(tm and tm.Visible and tm:FindFirstChild("TravelPortals", true) and tm:FindFirstChild("TravelLobby", true), "Travel opens a drop-down with Portals and Lobby")
T.check(tm.AbsolutePosition.Y >= inset - 1 and tm.AbsolutePosition.X >= pill.AbsolutePosition.X - 1, "...under the button, never over Roblox's buttons")
local n0 = #serverCalls("QuickTravel"); Mock.Click(tm.TravelPortals); advance(0.1)
local calls = callsAfter("QuickTravel", n0)
T.check(#calls == 1 and calls[1].args[1] == "Court", "Portals fires QuickTravel('Court')")
T.check(gui.TravelFade.Visible and gui.TravelFade.BackgroundTransparency < 0.5, "...and a short fade shows")
advance(1.0); T.check(not gui.TravelFade.Visible, "...gone within a second")
Mock.Click(pill.PillButton_Travel); Mock.Click(tm.TravelLobby); T.eq(callsAfter("QuickTravel", n0 + 1)[1].args[1], "Plaza", "Lobby fires QuickTravel('Plaza')")
LocalPlayer:SetAttribute(Config.Attr.InBattle, "B1"); advance(0.6)
T.check(not pill.PillButton_Travel.Visible and not tm.Visible, "Travel hides in a battle (InBattle)")
LocalPlayer:SetAttribute(Config.Attr.InBattle, nil); LocalPlayer:SetAttribute(Config.Attr.InMatch, true); advance(0.6)
T.check(not pill.PillButton_Travel.Visible, "...and in a match")
LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
K.fakeModel("BattleArena", rootCFrame(), Vector3.new(200, 60, 200)); advance(0.6)
T.check(not pill.PillButton_Travel.Visible, "...and on the Arena island (inside workspace.BattleArena's box)"); K.removeFake("BattleArena"); advance(0.6)
T.check(pill.PillButton_Travel.Visible, "...back in the lobby it shows again")
-- the column
local column = menu().MenuColumn
local ids = {}; for _, e in ipairs(column:GetChildren()) do if e.Name:find("^Entry_") then ids[#ids + 1] = e.Name end end
table.sort(ids); T.check(#ids == 4 and ids[1] == "Entry_Index" and ids[2] == "Entry_Pets" and ids[3] == "Entry_Spot" and ids[4] == "Entry_Stats", "the column keeps Pets, Index, Home, Stats only")
T.check(column:FindFirstChild("Gear_Settings") == nil and column:FindFirstChild("Entry_Team") == nil and column:FindFirstChild("Entry_Inventory") == nil, "no gear, Team or Items tile")
T.check(pill.AbsolutePosition.X + pill.AbsoluteSize.X < 1920 - 72, "the pill ends left of Roblox's right-side buttons")

-- client: client_hudpill_mobile  (844x390 touch, in a battle so the HUD's TopBand row shows)
local band = hud().TopRight.Currency  -- HudController.GetLayout().CurrencyMode == "TopBand"
T.check(HudController.GetLayout().CurrencyMode == "TopBand", "phone battle: the strips are in the top band")
T.check(band.AbsolutePosition.X >= pill.AbsolutePosition.X + pill.AbsoluteSize.X + 6 - 0.5, "the currency row starts right of the pill (not at BAND_LEFT 150)")
T.check(not overlaps(rect(pill), rect(band)), "the pill and the currency row do not overlap")
T.check(pill.AbsolutePosition.X + pill.AbsoluteSize.X <= 844 - 72, "...and the pill ends left of Roblox's right-side buttons on a phone")
T.check(pill.AbsoluteSize.Y >= 32, "the pill stays tappable (>= 32 px) in the phone band")
```

(Helper names `K.addPlayer`, `K.stepOnPad`, `K.leavePad`, `K.place`, `root`, `shown`, `hintText`, `settingsHolder`, `serverCalls`, `callsAfter`, `K.fakeModel`, `rect`, `overlaps` are the smoke_p4_ring / smoke_client_v2 / smoke_bug2_gui helpers; copy them into the file's local helpers where they are not global.)

- [ ] **Step 2: Register the file in `tools/smoke.py`** after line 472 in the established one-line style:

```python
if p5("smoke_hud_pill.lua"): server_files.append("smoke_hud_pill.lua"); client_files.append("smoke_hud_pill.lua"); ins(server_scenarios, "shutdown", ["hudpill_travel"]); ins(client_scenarios, "client_final", ["client_hudpill"]); mobile_scenarios.append("client_hudpill_mobile")  # [owner: HUD cleanup, Task 1] the top-left pill (Shop / Travel / Settings) in Roblox's top-bar band, the Quick Travel drop-down + QuickTravel remote, the four-tile column; GateService.Travel's checks (smoke_hud_pill.lua: both worlds)
```

Run: `py -3.12 tools/smoke.py --only hudpill_travel,client_hudpill,client_hudpill_mobile`
Expected: FAIL (NimbusTopBar missing, GateService.Travel nil).

- [ ] **Step 3: Add the remote and the server teleport.**
  - `src/shared/Config.lua` `Config.Remotes`, after `"MenuPlay"`: `"QuickTravel", -- (dest:string) "Court" | "Plaza"  HUD cleanup: the pill's Travel drop-down (GateService.Travel)`.
  - `src/server/Services/GateService.lua`: constants `TRAVEL_COOLDOWN = 2`, `LOBBY_Y_BAND = 80`, `LOBBY_R = Config.Lobby.SpotRingRadius + 120`, `COURT_STANDOFF = 16`, `TRAVEL_DESTS = { Court = true, Plaza = true }`; state `S.lastTravel = {}` (Player -> os.clock()).
  - `function GateService.CourtCFrame()`: `site = S.lobbyInfo.GateSites.Ring` (fallback `Dungeon`, then `nil`): `CFrame.lookAt(site.Position + site.LookVector * COURT_STANDOFF + Vector3.new(0, 3, 0), site.Position + Vector3.new(0, 3, 0))`.
  - `function GateService.Travel(player, dest)`: checks in this order, each returning `false, reason`: player valid / `TRAVEL_DESTS[dest]` (`"junk"`), `aliveRoot` (`"dead"`), `inMatch` (`"match"`), `inBattle` (`"battle"`, with the existing "Finish your battle first!" toast), `isLocked` (`"locked"`), zone (`"zone"`: horizontal distance from `Config.Lobby.Origin` > `LOBBY_R`, or `|Y - Origin.Y| > LOBBY_Y_BAND`, or `S.deps.ArenaBuilder.ZoneAt(root.Position) ~= nil`), cooldown (`"cooldown"`, 2 s via `S.lastTravel`); then `placeCharacter(player, dest == "Court" and GateService.CourtCFrame() or S.deps.PlayerService.GetLobbySpawnCFrame())` (`"failed"` when it returns false), `GateService.Teleported:Fire(player, dest)`, `return true`.
  - `GateService.Init(lobbyInfo, deps)`: keep `S.lobbyInfo = lobbyInfo`; connect `Remotes.Get("QuickTravel").OnServerEvent` -> `pcall(GateService.Travel, player, dest)` (a refused call is silent except the battle toast).
  - Header comment: document `Travel`, `CourtCFrame`, the `QuickTravel` remote and the lobby-zone rule.
  - `src/server/Main.server.lua:376`: add `PlayerService = PlayerService, ArenaBuilder = ArenaBuilder` to the GateService deps (both already loaded above that line).

- [ ] **Step 4: Build `src/client/Controllers/TopBarController.lua`.** Constants `K = { PILL_H = 40, PILL_MIN_H = 32, BTN_W = 44, LABEL_W = 70, GAP = 6, FALLBACK_LEFT = 212, BAND_INSET = 58, RIGHT_RESERVE = 72, FADE = 0.25, POLL = 0.5, MENU_W = 180, ROW_H = 44 }`. Module shape like `HotbarController` (locals, `Init` once, `safe` wrapper):
  - `leftEdge()`: `pcall(function() return GuiService.TopbarInset end)` -> a `Rect` with `Min.X > 0` gives `Min.X + 8`, else `K.FALLBACK_LEFT`; `rightLimit()`: `TopbarInset.Max.X` when valid, else `viewport.X - K.RIGHT_RESERVE`; `inset()`: `GuiService:GetGuiInset().Y`, `K.BAND_INSET` when 0.
  - `relayout()`: pill height `clamp(inset - 10, K.PILL_MIN_H, K.PILL_H)`, y centred in the band; buttons icon + label (`NeonKit.Icon` ids `"Shop"`, `"Travel"`, `"Settings"`; add `Travel = "\240\159\167\173"` (compass) to the icon table in `src/client/UI/NeonKit.lua:70-78`); when `leftEdge() + pillWidth > rightLimit()` drop the labels (icons only, `K.BTN_W` each); write attributes `PillRight` / `PillBottom` (0 when the gui is disabled).
  - `PillButton_Shop` -> `MenuController.Open("Shop")` (the in-match hint comes from MenuController's `menuActionShop` rule: call `MenuController.Open("Shop")` only when `LocalPlayer:GetAttribute(Config.Attr.InMatch) ~= true`, else `MenuController.Hint("The shop is closed during a match.", "info")`); `PillButton_Settings` -> `MenuController.OpenSettings()`; `PillButton_Travel` toggles `TravelMenu` (anchored under the button, top at `inset`, rows `TravelPortals` "Portals" and `TravelLobby` "Lobby"); a row fires `Remotes.Get("QuickTravel"):FireServer("Court" | "Plaza")`, closes the menu and shows `TravelFade` (full-screen black Frame, transparency 1 -> 0.15 over `K.FADE`, back to 1 and `Visible = false` by 0.6 s).
  - `TravelAllowed()`: `InMatch ~= true` and `InBattle == nil` and the root is not inside the bounding box (`GetBoundingBox` + 40 studs Y slack, like `ArenaController.inArena`) of `workspace:FindFirstChild("BattleArena")` nor of `workspace:FindFirstChild("StormAltar", true)`. A `task.spawn` loop every `K.POLL` seconds applies it (`PillButton_Travel.Visible`; close the menu when it hides). `GetRect()` returns the pill's absolute rect or nil when hidden.
  - `Init()`: `CloudUI.NewScreenGui("NimbusTopBar", 21)` then `gui.IgnoreGuiInset = true`; relayout on `gui:GetPropertyChangedSignal("AbsoluteSize")`, on `GuiService:GetPropertyChangedSignal("TopbarInset")` under pcall, and on the attribute changes of `InMatch` / `InBattle`.
  - `src/client/Main.client.lua`: add `"TopBarController", -- HUD cleanup: the top-left pill (Shop / Travel / Settings)` right after `"MenuController"`.

- [ ] **Step 5: Trim the menu column and expose Settings.** In `MenuController.lua`:
  - MENU (line 2115) becomes four entries in this order: `Pets`, `Index`, `Spot`, `Stats` (delete the `Inventory`, `Team`, `Shop`, `Settings` entries and `menuActionInventory`'s tile use; keep `menuActionShop` for `Open("Shop")`; keep the `Team` window and `toggleWindow("Team")` reachable through `MenuController.Open("Team")` until Task 2). Rewrite the comment block above it (lines 2103-2113: "ONE slim column of four neon tiles ... Pets, Index, Home, Stats; Shop / Travel / Settings live in TopBarController's pill").
  - `P5.openSettings` -> `function MenuController.OpenSettings()` (same body; keep a `P5.openSettings = MenuController.OpenSettings` alias for internal callers).
  - `MenuController.Open`: accept `"settings"` -> `MenuController.OpenSettings()`.
  - Header comment lines 4-33: the new column and the pill.
- [ ] **Step 6: Move the HUD's phone band right of the pill.** In `HudController.lua`: add `local function bandLeft()` returning `math.max(K.BAND_LEFT, (tonumber(pg.NimbusTopBar:GetAttribute("PillRight")) or 0) + K.STRIP_GAP)` (PlayerGui lookup under pcall; 0 when the gui is absent) and use it in place of `K.BAND_LEFT` at lines 800, 903 and 910; add `"PillRight"` to the layout key `parts` (line 802) so a pill move re-lays the row; keep `K.BAND_LEFT = 150` as the floor.
- [ ] **Step 7: Contract + existing smoke tests.**
  - `tools/contract.json`: `v3.menuEntries` -> `["Pets", "Index", "Spot", "Stats"]`; add `"client/Controllers/TopBarController": { "functions": ["Init", "GetRect", "TravelAllowed", "Refresh"] }`; `server/Services/GateService.functions` add `"Travel", "CourtCFrame"`; `client/Controllers/MenuController.functions` add `"OpenSettings"`.
  - `tools/smoke_client.lua:1365-1410`: the column is "four 66 px tiles, no gear": `count == #CONTRACT.v3.menuEntries and gearEntry == nil`, `#grid == 4`, `(columns - 1) * rows < 4`.
  - `tools/smoke_client_v2.lua:995-1040`: `gear == nil`, `#grid == #names`, the message "...with four entries".
  - `tools/smoke_p5_looks.lua:424-442`: `grid = { "Pets", "Index", "Spot" }`, `okNames and btn("Stats") and btn("Settings") == nil`, `order = { "Pets", "Index", "Spot", "Stats" }`; the 56 px check compares `btn("Stats")` instead of the gear.
  - `tools/smoke_bug2_gui.lua:101`: `H.ORDER = { "Pets", "Index", "Spot", "Stats" }` (and its header comment line 4).
  - `tools/smoke_p3_ui.lua:583-590`: open the Team window with `MC.Open("Team", {})` instead of clicking `MenuButton_Team`; drop the tile assertion (the tile is gone by design).
  - `tools/dump_gui.lua:2281`: `tiles = { { "Pets", "Pets" }, { "Index", "Index" }, { "Home", "Home" } }`.
- [ ] **Step 8: Run the smoke tests.**

Run: `py -3.12 tools/smoke.py --only hudpill_travel,client_hudpill,client_hudpill_mobile,contract,config_shape,lobby,p5world_gates,client_menu,client_p5menu_tiles,client_p3ui,client_bug2gui_layout,client_bug2gui_mobile,client_p5settings,client_final,client_mobile`
Expected: every check `ok`, exit 0. Then `node tools/check.mjs` (static contract) exits 0.
- [ ] **Step 9: Commit.**

```bash
git add src/client/Controllers/TopBarController.lua src/client/Controllers/MenuController.lua src/client/Controllers/HudController.lua src/client/UI/NeonKit.lua src/client/Main.client.lua src/shared/Config.lua src/server/Services/GateService.lua src/server/Main.server.lua tools/contract.json tools/smoke.py tools/smoke_hud_pill.lua tools/smoke_client.lua tools/smoke_client_v2.lua tools/smoke_p5_looks.lua tools/smoke_bug2_gui.lua tools/smoke_p3_ui.lua tools/dump_gui.lua
git commit -m "feat(hud): top-left pill (Shop / Travel / Settings) + Quick Travel; the column keeps Pets, Index, Home, Stats"
```

---

### Task 2: Battle team at the portal

**Files:**
- Create: `src/client/TeamPick.lua`
- Modify: `src/client/Controllers/MenuController.lua:1805-1823` (`normalizeTab`), `:2884-2905` + `:3912-3945` (Inventory tabs / OnOpen), `:7924-8140` (`P3.BuildTeam` takes a container), `:8975-9006` (`Open` keys), `:9204-9208` (`createWindow` list)
- Modify: `src/client/Controllers/DungeonController.lua:938-960` (`W.partyNone` buttons), `:1002-1070` (`W.partyMine` START / READY), `:632` (`H.request` stays)
- Modify: `src/client/Controllers/ArenaController.lua:1733-1790` (Duels page), `:1790-1850` (Raid page), `:2155-2180` (the raid refusal), the duel pad `Challenge` / `ChallengeReply` sends
- Modify: `src/server/Services/BattleService.lua:751` (refusal text) and its header line 33
- Modify: `src/shared/TutorialSteps.lua:287-297` (step 16)
- Modify: `tools/contract.json` (new module `client/TeamPick`, `MenuController.OpenTeam`)
- Modify: `tools/smoke_p4_ring.lua:819`, `tools/smoke_p3_ui.lua:583-600`, `tools/smoke_p5_gui.lua:245` (unchanged ids still open), `tools/dump_gui.lua` `menu:Team` scene
- Create: `tools/smoke_hud_team.lua`; Modify: `tools/smoke.py`

**Interfaces:**
- Consumes: `State.Teams()`, `State.Keys()`, `State.DefOf(key)`, `State.PetLevel(key)`, `State.PetGrowth(key)`, `State.IsTraining(key)`, `State.Home().Garden`, `State.Changed`, `BattleCatalog.UnitPower(def, level, tier, extras)`, `PetKeys.Parse(key)`, `Remotes.Get("BattleRequest")` (`"TeamSet", preset, keys` / `"TeamSelect", preset`), `MenuController.Open("Team", { Preset })`, `CloudUI.Panel / Button / Slot / PetViewport`, `NeonKit.Card`.
- Produces:
  - `TeamPick.ActiveKeys() -> {key...}` (the active preset minus training / gardening keys), `TeamPick.Fieldable() -> { { Key, Def, Level, Tier, Power } ... }` sorted by `Power` desc, `TeamPick.Best(n) -> {key...}`, `TeamPick.Save(keys, onDone)` (fires `TeamSet` on the active preset, resolves `onDone(true)` when `State.Teams()` shows those keys or `onDone(false)` after 2.5 s), `TeamPick.Ensure(continueFn)` (calls `continueFn()` at once when `#ActiveKeys() > 0`, opens the popup otherwise and calls `continueFn()` after a successful save; with zero fieldable pets shows `MenuController.Hint("You need a pet: spin a roulette in the Cloud Shop.", "info")` and never opens), `TeamPick.Strip(parent, props) -> { Root, Refresh }` (props `{ LayoutOrder, Compact }`; Frame `TeamStrip` with `StripSlot1..3` (pet name + "L<level>" + element pill, empty slot text "Empty"), TextButtons `StripEdit` ("Edit") and `StripAuto` ("Auto-fill best")), `TeamPick.Popup(props)` (ScreenGui `NimbusTeamPick` DisplayOrder 26, Frame `TeamPickPopup`, title "Pick your battle team", `PopSlot1..3` (tap = cycle to the next fieldable pet not already in the team), TextButtons `PopAuto` ("Auto-fill best"), `PopSave` ("Save and enter"), `PopCancel` ("Cancel"); props `{ OnSave = fn(keys), OnCancel = fn }`), `TeamPick.IsOpen()`, `TeamPick.Close()`.
  - `MenuController.OpenTeam(preset)` -> opens the Pets window (`Window_Inventory`) on tab `Team`; `MenuController.Open("Team", args)` does the same; the Inventory tabs are `Pets`, `Team` (+ `Items` until Task 3); selecting `Team` fires `MenuController.WindowOpened("Team")` once per opening and sets the title "Battle Team" / accent "Red".
  - Server refusal text: `"Pick your battle team first (at a battle portal, or Pets > Team)"`.
  - Tutorial step 16: `Text = "Battles need 3 pets (a fighter + 2 helpers)! Open Pets > Team and add them, or tap Auto-fill best at any portal!"` (112 bytes), `Target = { Kind = "Menu", Id = "Pets", Label = "Pets" }`, `Hint = "Open Pets > Team, put in 3 pets"`.

- [ ] **Step 1: Write the failing smoke file `tools/smoke_hud_team.lua`** (both worlds). Scenarios and assertions:

```lua
-- server: hudteam_refusal
local spec, why = BS.TeamSpec(a)   -- a has pets, an empty team
T.check(spec == nil and why == "Pick your battle team first (at a battle portal, or Pets > Team)", "TeamSpec's empty-team refusal names the portal and Pets > Team", why)
local ok, why2 = DungeonService.StartSolo(a, 1)
T.check(ok == false and why2 == why, "the Dungeon refuses with the same text")
local step = TutorialSteps.Steps[16]
T.check(step.Id == "team" and step.Target.Kind == "Menu" and step.Target.Id == "Pets" and step.CompleteOn == "TeamSet", "tutorial step 16 points at the Pets tile and completes on TeamSet")
T.check(#step.Text >= 97 and #step.Text <= 125 and step.Text:find("Pets > Team", 1, true) and step.Text:find("Auto%-fill best"), "...its text names Pets > Team and Auto-fill best in 97-125 bytes", #step.Text)
T.check(not TutorialSteps.Steps[16].Text:find("Tap Team", 1, true) and not step.Hint:find("Tap Team", 1, true), "...no stale 'Tap Team'")

-- client: client_hudteam_tab  (profile: 4 pets, empty team)
MC.Open("Team", {}); advance(0.6)
local inv = menu():FindFirstChild("Window_Inventory")
T.check(shown(inv) and menu():FindFirstChild("Window_Team") == nil, "Open('Team') opens the Pets window; there is no Window_Team any more")
T.check(find(inv, "Tab_Team") and find(inv, "Tab_Pets") and find(inv, "Page_Team") and find(inv, "Page_Team").Visible, "...on its Team tab")
T.check(find(inv, "Slot1") and find(inv, "UseTeam") and find(inv, "Preset1"), "...holding the P3 editor (slot cards, presets, Use this team)")
T.check(titleOf(inv) == "Battle Team", "...titled Battle Team")
T.check(T.contains(windowOpenedLog, "Team"), "...and WindowOpened('Team') fired (the tutorial listens)")
MC.Open("Pets", {}); advance(0.3)
T.check(find(inv, "Page_Pets").Visible and titleOf(inv) == "Pets", "Open('Pets') switches back to the Pets tab")
toClient("OpenPanel", "Team", { Preset = 2 }); advance(0.3)
T.check(find(inv, "Page_Team").Visible and find(inv, "Preset2"):GetAttribute("Selected") == true, "OpenPanel('Team', { Preset = 2 }) selects preset 2")

-- client: client_hudteam_portal  (DungeonController + ArenaController booted; profile: 4 pets, empty team)
local TP = require(client.TeamPick)
T.check(#TP.ActiveKeys() == 0 and #TP.Fieldable() == 4 and #TP.Best(3) == 3, "TeamPick: empty active team, 4 fieldable pets, Best(3) picks 3")
local f = TP.Fieldable(); T.check(f[1].Power >= f[2].Power and f[2].Power >= f[3].Power, "...sorted by UnitPower")
feed({ PetGrowth = { [f[1].Key] = { Job = "Train" } } }); T.check(#TP.Fieldable() == 3, "a training pet is not fieldable")
DC.Open(1); advance(0.5)
local strip = find(dungeonPanel(), "TeamStrip")
T.check(strip and find(strip, "StripSlot1").Empty.Text == "Empty" and find(strip, "StripEdit") and find(strip, "StripAuto"), "the Dungeon panel shows the team strip with Edit and Auto-fill best")
Mock.Click(find(strip, "StripAuto")); advance(0.1)
local c = callsAfter("BattleRequest", n0)
T.check(#c == 1 and c[1].args[1] == "TeamSet" and c[1].args[2] == 1 and #c[1].args[3] == 3 and c[1].args[3][1] == TP.Best(3)[1], "Auto-fill best fires BattleRequest('TeamSet', active preset, the 3 best keys)")
feed({ Teams = { Presets = { TP.Best(3), {}, {} }, Active = 1, Slots = 3 } }); advance(0.3)
T.check(find(strip, "StripSlot1").PetName.Text == PC.Get(parse(TP.Best(3)[1]).PetId).Name, "...the strip shows the saved team")
Mock.Click(find(strip, "StripEdit")); advance(0.5)
T.check(shown(menu().Window_Inventory) and find(menu().Window_Inventory, "Page_Team").Visible, "Edit opens Pets > Team")
-- the empty-team popup continues into the portal
feed({ Teams = { Presets = { {}, {}, {} }, Active = 1, Slots = 3 } }); DC.Open(1); advance(0.3)
local d0 = #serverCalls("DungeonRequest"); Mock.Click(find(dungeonPanel(), "SoloButton")); advance(0.1)
local pop = pg():FindFirstChild("NimbusTeamPick") and find(pg().NimbusTeamPick, "TeamPickPopup")
T.check(pop and pop.Visible and #callsAfter("DungeonRequest", d0) == 0, "SOLO with an empty team opens the popup and sends nothing yet")
T.check(find(pop, "PopSlot1") and find(pop, "PopAuto") and find(pop, "PopSave") and find(pop, "PopCancel") and find(pop, "Title").Text == "Pick your battle team", "...3 slots, Auto-fill best, Save and enter, Cancel")
Mock.Click(find(pop, "PopCancel")); advance(0.1)
T.check(not pop.Visible and #callsAfter("DungeonRequest", d0) == 0 and #callsAfter("BattleRequest", n1) == 0, "Cancel closes it and sends nothing")
Mock.Click(find(dungeonPanel(), "SoloButton")); Mock.Click(find(pop, "PopAuto")); Mock.Click(find(pop, "PopSave")); advance(0.1)
T.check(callsAfter("BattleRequest", n1)[1].args[1] == "TeamSet" and #callsAfter("DungeonRequest", d0) == 0, "Save and enter fires TeamSet first and waits for the sync")
feed({ Teams = { Presets = { TP.Best(3), {}, {} }, Active = 1, Slots = 3 } }); advance(0.3)
local dq = callsAfter("DungeonRequest", d0)
T.check(#dq == 1 and dq[1].args[1] == "Solo" and dq[1].args[2] == 1 and not pop.Visible, "...then continues into the portal: DungeonRequest('Solo', 1)")
-- a 2-pet player saves a 2-pet team; a 0-pet player gets the hint
feed({ Pets = twoPets, Teams = emptyTeams }); Mock.Click(find(dungeonPanel(), "SoloButton")); Mock.Click(find(pop, "PopAuto")); Mock.Click(find(pop, "PopSave"))
T.check(#callsAfter("BattleRequest", n2)[1].args[3] == 2, "two pets: Save sends a 2-key team")
feed({ Pets = {}, Teams = emptyTeams }); Mock.Click(find(dungeonPanel(), "SoloButton")); advance(0.1)
T.check(not pop.Visible and hintText():find("You need a pet"), "no pets: the hint, no popup")
-- a save that never syncs
feed(fourPets); Mock.Click(find(dungeonPanel(), "SoloButton")); Mock.Click(find(pop, "PopSave")); advance(2.6)
T.check(not pop.Visible and #callsAfter("DungeonRequest", d1) == 0 and hintText():find("could not save"), "no sync within 2.5 s: the popup closes with a hint and does not enter")
-- the Arena panel: Duels + Raid strips, JOIN RAID / Find a match go through the popup
AC.OpenArena("Duels"); advance(0.5)
T.check(find(arenaPanel(), "Page_Duels") and find(find(arenaPanel(), "Page_Duels"), "TeamStrip"), "the Arena Duels page carries the team strip")
AC.OpenArena("Raid"); T.check(find(find(arenaPanel(), "Page_Raid"), "TeamStrip"), "...and the Raid page")
toClient("ArenaState", raidJoinable); advance(0.2)
T.check(find(arenaPanel(), "JoinRaid"):GetAttribute("Disabled") ~= true and find(arenaPanel(), "JoinWhy").Text == "", "JOIN RAID is enabled with an empty team (the popup handles it)")
Mock.Click(find(arenaPanel(), "JoinRaid")); advance(0.1)
T.check(pop.Visible and #callsAfter("BattleRequest", n3) == 0, "...it opens the popup instead of sending JoinRaid")
Mock.Click(find(pop, "PopAuto")); Mock.Click(find(pop, "PopSave")); feed(teamSaved); advance(0.3)
T.check(callsAfter("BattleRequest", n3)[2].args[1] == "JoinRaid", "...and continues with JoinRaid after the save")
AC.OpenArena("Duels"); feed(emptyTeams); Mock.Click(find(arenaPanel(), "Queue")); advance(0.1)
T.check(pop.Visible, "Find a match with an empty team opens the popup too")

-- client: client_hudteam_mobile  (844x390 touch): the popup fits the screen
T.check(pop.AbsoluteSize.X <= 844 - 32 and pop.AbsoluteSize.Y <= 390 - 16, "the popup fits a landscape phone with 16 px gutters")
T.check(find(pop, "PopSave").AbsoluteSize.Y >= 44, "...its buttons stay >= 44 px")
```

(`n0..n3` / `d0..d1` are call-log lengths taken right before each click; `fourPets`, `twoPets`, `emptyTeams`, `teamSaved`, `raidJoinable` are ProfileSync / ArenaState fixtures the file defines at its top; `find`, `shown`, `feed`, `toClient`, `callsAfter`, `hintText`, `titleOf`, `dungeonPanel`, `arenaPanel` are the smoke_client_v2 / smoke_p5_dungeon helpers, copied locally where not global.)

- [ ] **Step 2: Register in `tools/smoke.py`:**

```python
if p5("smoke_hud_team.lua"): server_files.append("smoke_hud_team.lua"); client_files.append("smoke_hud_team.lua"); ins(server_scenarios, "shutdown", ["hudteam_refusal"]); ins(client_scenarios, "client_final", ["client_hudteam_tab", "client_hudteam_portal"]); mobile_scenarios.append("client_hudteam_mobile")  # [owner: HUD cleanup, Task 2] the battle team at the portal: TeamPick (strip + popup + Auto-fill best) on the Dungeon / Arena panels, the Team tab of the Pets window, the refusal text, tutorial step 16 (smoke_hud_team.lua: both worlds)
```

Run: `py -3.12 tools/smoke.py --only hudteam_refusal,client_hudteam_tab,client_hudteam_portal,client_hudteam_mobile`
Expected: FAIL (TeamPick missing, Window_Team still exists, old refusal text).

- [ ] **Step 3: Server text + tutorial step.** `BattleService.lua:751` -> the new refusal string (also the header line 33 and `smoke_p4_ring.lua:819`); `TutorialSteps.lua:287-297` -> the `Text` / `Target` / `Hint` of the Interfaces block; drop the stale comment about the Team tile (keep the bug-batch-2 #18 note: the Team tab still asks to take a gardening pet out).
- [ ] **Step 4: Write `src/client/TeamPick.lua`** with the API of the Interfaces block. Decisions the signatures leave open: `Fieldable()` skips keys with `State.IsTraining(key)` and keys present in `State.Home().Garden`; `Power` = `BattleCatalog.UnitPower(def, level, tier, { Evo = growth.Evo, Train = growth })` with `tier` from `PetKeys.Parse(key).Tier`; `Save` sends `BattleRequest("TeamSet", State.Teams().Active, keys)` once (no `TeamSelect`), then polls `State.Changed` for a preset equal to `keys` (order-insensitive), 2.5 s timeout -> `MenuController.Hint("Your team could not save. Try again!", "bad")`; `Ensure` closes the popup on `OnSave` only after `Save` resolves `true`; the popup is a `CloudUI.Panel` on a dimmed full-screen backdrop, `PopSlot<i>` = `CloudUI.Slot` showing the pet's name / level / element, prefilled with `Best(3)` when the team is empty; `Strip` re-renders on `State.Changed`.
- [ ] **Step 5: The Team tab in the Pets window** (`MenuController.lua`): change `P3.BuildTeam(win)` to `P3.BuildTeam(win, container, hooks)` where `container` replaces `win.Panel.Content` and the three closures it assigns (`win.OnOpen` at 8117, `win.OnLayout` at 8128, `win.Refresh` at 8132) are stored on `hooks` (`hooks.OnOpen / OnLayout / Refresh`) instead; in `buildInventory` add `tabs.Add("Team", function(page) P3.BuildTeam(win, page, teamHooks) end)` right after `tabs.Add("Pets", ...)`, call `teamHooks.Refresh` from `refreshInventory`, `teamHooks.OnLayout` from the Inventory `win.OnLayout`, `teamHooks.OnOpen(args)` from `win.OnOpen` when `args.Tab == "Team"`; the `OnSelect` of the Inventory tabs sets title `"Battle Team"` / accent `"Red"` for `Team` (title "Pets" / "Orange" otherwise, "Items" / "Blue" until Task 3) and fires `MenuController.WindowOpened:Fire("Team")` the first time the tab shows per opening; `normalizeTab` maps `"team"` -> `"Team"`; `Open` keys `"team" | "teams"` -> `openWindow("Inventory", { Tab = "Team", Preset = args.Preset })`; add `function MenuController.OpenTeam(preset)`; delete the `createWindow({ Id = "Team", ... })` line (9208) and `toggleWindow("Team")` callers; update the header comment (lines 4-12, 26-33).
- [ ] **Step 6: Strips and the popup on the portal panels.**
  - `DungeonController.lua` `W.partyNone`: insert `TeamPick.Strip(box, { LayoutOrder = 2, Compact = short })` between the title (1) and the buttons row (now 3; renumber the open-parties rows); wrap the SOLO / PARTY callbacks: `TeamPick.Ensure(function() if H.request("Solo", W.selected()) then ... end end)`. `W.partyMine`: the strip above the member list (`LayoutOrder` 2), READY / START wrapped the same way (the leader's START only needs the leader's own team: the server checks members).
  - `ArenaController.lua`: `TeamPick.Strip(quick, { LayoutOrder = 0 })` at the top of the Duels `Quick` inset and `TeamPick.Strip(ui.BossCard, { LayoutOrder = 0 })` on the Raid page; wrap `request("Queue")` (1766), `request("JoinRaid")` (1838), `request("Challenge", userId)` (the duel pad path ~2014) and the Accept of a challenge (`request("ChallengeReply", id, true)`) in `TeamPick.Ensure`; delete the `elseif #activeTeam() == 0 then why = "Pick your battle team first."` branch (2172-2173) so JOIN RAID stays enabled; the Ring window keeps its fallback (no strip: the server fields team -> equipped -> best).
  - `require` TeamPick in both controllers through `script.Parent.Parent:WaitForChild("TeamPick")` under `pcall` (nil-safe: without it the old direct requests run).
- [ ] **Step 7: Contract + existing tests.** `tools/contract.json`: add `"client/TeamPick": { "functions": ["ActiveKeys", "Fieldable", "Best", "Save", "Ensure", "Strip", "Popup", "IsOpen", "Close"] }`; `MenuController.functions` add `"OpenTeam"`. `tools/smoke_p3_ui.lua:588-600`: the window is `Window_Inventory` with `Page_Team` visible (slot cards found inside it). `tools/dump_gui.lua`'s `menu:Team` scene: `MC.Open("Team", {})` unchanged, its window lookup `Window_Team` -> `Window_Inventory`.
- [ ] **Step 8: Run the smoke tests.**

Run: `py -3.12 tools/smoke.py --only hudteam_refusal,client_hudteam_tab,client_hudteam_portal,client_hudteam_mobile,p4ring_start,p5dgn_party,p5ui_content,p5ui_tutorial_ch2,client_p3ui,client_p3ui_mobile,client_p5dungeon,client_p5dungeon_mobile,client_p5team3,client_p3fixcli_tutorial,client_menu,client_final,client_mobile`
Expected: all `ok`, exit 0; `node tools/check.mjs` exits 0.
- [ ] **Step 9: Commit.**

```bash
git add src/client/TeamPick.lua src/client/Controllers/MenuController.lua src/client/Controllers/DungeonController.lua src/client/Controllers/ArenaController.lua src/server/Services/BattleService.lua src/shared/TutorialSteps.lua tools/contract.json tools/smoke.py tools/smoke_hud_team.lua tools/smoke_p4_ring.lua tools/smoke_p3_ui.lua tools/dump_gui.lua
git commit -m "feat(team): battle team at the portal (strip + Auto-fill best + empty-team popup), Team tab in the Pets window"
```

---

### Task 3: Items removal + one-time Token refund + boarded-up stall

**Files:**
- Delete: `src/shared/ItemCatalog.lua`, `src/server/Services/ItemService.lua`, `src/client/Controllers/HotbarController.lua`
- Modify: `src/shared/Config.lua:91-135` (remove `"BuyItem"`, `"UseItem"`), `:487-490` (remove `Config.Items`)
- Modify: `src/server/Main.server.lua:232`, `:301-305`, `:369-371` (ItemService wiring) + the refund toast
- Modify: `src/client/Main.client.lua:20` (boot list)
- Modify: `src/server/Services/DataService.lua:2030-2038` (Items load), `:3566` + `:3941` (the load hook), `:1973` / `:3305` (ProfileSync snapshot), header lines 8, 29, 87, 278
- Modify: `src/client/State.lua:9`, `:58`, `:553`, `:589`, `:709-711`
- Modify: `src/client/Controllers/MenuController.lua:130` (ItemCatalog require), `:739`, `:2027-2029`, `:2630-2638` (`gotoShopItems`), `:3600-3760` + `:3915-3922` (Inventory Items page), `:4400-4450` + `:5072` (Shop Items page), `:1805-1823` (`normalizeTab`), `:8988-8992` (`Open` keys), header
- Modify: hotbar helper call sites: `ArenaController.lua:697-705`, `CareController.lua:2295-2300`, `DungeonController.lua:660-668`, `FusionController.lua:708-715`, `IndexController.lua:838`, `:2568`, `MainMenuController.lua:732`, `MenuController.lua:1706-1715`, `ObbyController.lua:270`; `HudController.lua:689-700` (`hotbarRect` -> always nil path), `:38`, `:88`
- Modify: `src/shared/NpcDialog.lua:30-40`, `:121-133`, `:399-425`
- Modify: `src/server/Services/LobbyBuilder.lua:3375-3449` (boarded stall), header lines 23 / 38
- Modify: `src/server/Services/DevService.lua:32`, `:112`, `:588` (comments; the wipe stays harmless)
- Modify: `tools/contract.json`, `tools/smoke.py`, `tools/smoke_content.lua:418-421`, `:778-797`, `:888-890`, `tools/smoke_economy.lua:12`, `:793`, `:1095-1110`, `:1141-1235` (scenario `items` removed; `match_locks` item parts), `tools/smoke_server.lua:1358`, `:1481-1486`, `:1670-1676`, `:3249-3250`, `tools/smoke_client.lua:350`, `:1090`, `:1344`, `:1358`, `:1435-1472`, `tools/smoke_client_v2.lua:14`, `:168`, `:539-597`, `:987`, `:1072`, `:1148-1160`, `:1311-1358`, `:1463-1480` (scenario `client_hotbar` removed), `tools/smoke_dev.lua:109`, `:440-443`, `:520`, `:1089-1090`, `tools/smoke_p2_flow.lua:679`, `:764`, `tools/smoke_p5_gui.lua:161-167`, `tools/smoke_p3_fix_client.lua:549`, `:665`, `:875`, `tools/smoke_p4_fix_client.lua:519`, `tools/smoke_bug2_gui.lua:98`, `:155`, `:199`, `:243`, `:347`, `:389`, `tools/dump_gui.lua:780`, `:2406-2408`, `README.md` (the items paragraphs)
- Create: `tools/smoke_hud_items.lua`

**Interfaces:**
- Consumes: `DataService` load path (`P3.gardenMigrate(entry)` call sites), `DataService.Migrated` signal, `Remotes.Get("Notify")`, `LobbyBuilder` `buildItemStall` (`VX.Fill`, `box`, `tagText`), `MenuController` tabs.
- Produces:
  - `DataService` migration marker `Migrations.B3ItemsRefund`; `P6.itemsRefund(entry) -> info | nil` with `info = { Tokens = n, Items = { [id] = count } }` (nil when the marker was already set); `DataService.MigratedNow(player, "B3ItemsRefund")` answers that info in the session that paid; `DataService.Migrated:Fire(player, "B3ItemsRefund", info)` when `info.Tokens > 0`; constants `P6.REFUND = { heal_cloud = 30, shield_bubble = 45, phoenix_feather = 150 }`, `P6.REFUND_MAX = 5`.
  - The ProfileSync snapshot and `State.Get()` have **no** `Items` key; `State.ItemCount` is gone.
  - Toast (Main.server.lua, on `Migrated` "B3ItemsRefund"): `"Items are gone from Nimbus: your old ones were refunded, +<n> Tokens!"`, kind `"token"`, 6 s.
  - `LobbyInfo.Shop.ItemShop = { PromptPart, Center, Model }` stays; the Model gains a child Model `Boards` (two crossed `WoodDark` planks across the counter front, outside the `prop_item_stall`-tagged `Stall` model so the Phase 6 mesh dress leaves them) and the billboard's `SubLabel` reads `"Closed"`; no `ProximityPrompt` anywhere under `ItemShop`.
  - `tools/contract.json`: modules `shared/ItemCatalog`, `server/Services/ItemService`, `client/Controllers/HotbarController` removed; `shared/Config.fields` without `"Items"`; `client/State.functions` without `"ItemCount"`; `v2.items` removed.

- [ ] **Step 1: Write the failing smoke file `tools/smoke_hud_items.lua`** (both worlds):

```lua
-- server: huditems_gone  (booted server)
T.check(K.moduleInstance("shared/ItemCatalog") == nil and K.moduleInstance("server/Services/ItemService") == nil, "ItemCatalog and ItemService are gone")
T.check(not T.contains(Config.Remotes, "BuyItem") and not T.contains(Config.Remotes, "UseItem") and Config.Items == nil, "no BuyItem / UseItem remotes, no Config.Items")
T.check(RS.Remotes:FindFirstChild("BuyItem") == nil, "Remotes.Init made no BuyItem remote")
local stall = K.lobbyInfo.Shop.ItemShop
T.check(stall.Model:FindFirstChildOfClass("ProximityPrompt", true) == nil, "the item stall has no prompt")
T.check(stall.Model:FindFirstChild("Boards") and #stall.Model.Boards:GetChildren() >= 2, "...it is boarded up (Model Boards, two planks)")
T.check(stall.Model.Boards.Parent == stall.Model and not stall.Model.Boards:IsDescendantOf(stall.Model:FindFirstChild("Stall")), "...the boards sit beside the mesh-tagged Stall, not inside it")
T.check(find(stall.Model, "SubLabel").Text == "Closed", "...its sign says Closed")
local prompts = 0; for _, d in ipairs(K.lobbyInfo.Folder:GetDescendants()) do if d:IsA("ProximityPrompt") and d:IsDescendantOf(K.shopFolder()) then prompts = prompts + 1 end end
T.eq(prompts, #Config.Roulettes, "PetService's roulette prompts are the only shop prompts")
for _, npc in ipairs(NpcDialog.Npcs) do
  for _, l in ipairs(npc.Lines) do T.check(not l:find("Heal Cloud") and not l:find("Phoenix Feather") and not l:find("hotbar") and #l <= 125, npc.Id .. ": no item lines, <= 125 bytes") end
  T.check(#npc.Lines >= 3 and #npc.Lines <= 5, npc.Id .. " keeps 3-5 lines")
  if npc.Title == "Movement Trainer" then T.check(T.contains(npc.Keywords, "checkpoint") and not T.contains(npc.Keywords, "Heal Cloud"), "the trainer's keywords name the checkpoint, not the items") end
end

-- server: huditems_refund  (DataStore mock pre-seeded with v2 profiles)
K.store(uidA, { Version = 2, Tokens = 100, Items = { heal_cloud = 2, shield_bubble = 1, phoenix_feather = 1 } })
local fired = {}; DS.Migrated:Connect(function(p, name, info) if name == "B3ItemsRefund" then fired[#fired + 1] = info end end)
local a = K.join(uidA); advance(1)
local prof = DS.GetProfile(a)
T.eq(prof.Tokens, 100 + 2 * 30 + 45 + 150, "the refund pays 30 / 45 / 150 per item (255)")
T.check(next(prof.Items) == nil and prof.Migrations.B3ItemsRefund == true, "...clears Items and sets the marker")
T.check(#fired == 1 and fired[1].Tokens == 255 and fired[1].Items.heal_cloud == 2, "...Migrated fired once with the info")
T.check(DS.MigratedNow(a, "B3ItemsRefund").Tokens == 255, "...MigratedNow answers it this session")
T.check(#K.notifies(a, "token") == 1 and K.notifies(a, "token")[1]:find("+255 Tokens", 1, true), "...one token toast names the amount")
K.leave(a); advance(1); a = K.join(uidA); advance(1)
T.eq(DS.GetProfile(a).Tokens, 355, "a second load pays nothing more")
K.store(uidB, { Version = 2, Tokens = 0, Items = { heal_cloud = 99, mystery_box = 3 } })
local b = K.join(uidB); advance(1)
T.eq(DS.GetProfile(b).Tokens, 5 * 30, "counts clamp to 5 per item and unknown ids pay 0")
K.store(uidC, { Version = 2, Tokens = 10, Items = {} }); local c = K.join(uidC); advance(1)
T.check(DS.GetProfile(c).Migrations.B3ItemsRefund == true and #K.notifies(c, "token") == 0, "an empty Items table: marker set, no toast")
-- provisional / merge: an outage load then recovery never pays twice (K.outage / K.recover from smoke_polish_data)
K.store(uidD, { Version = 2, Tokens = 0, Items = { phoenix_feather = 1 } }); K.outage(true); local d = K.join(uidD); advance(1)
T.check(DS.IsProvisional(d) == true and DS.GetProfile(d).Tokens == 0, "a provisional profile waits (no refund yet)")
K.outage(false); advance(K.RECOVERY + 1)
T.eq(DS.GetProfile(d).Tokens, 150, "...the recovered profile is paid once")
K.leave(d); advance(1); T.eq(K.stored(uidD).Tokens, 150, "...and saved once"); T.check(next(K.stored(uidD).Items or {}) == nil, "...with Items cleared in the store")
T.check(DS.Sync and K.lastSync(a).Items == nil, "ProfileSync carries no Items key")

-- client: client_huditems_gone
T.check(pg():FindFirstChild("NimbusHotbar") == nil, "no NimbusHotbar ScreenGui")
T.check(State.Get().Items == nil and State.ItemCount == nil, "State has no Items / ItemCount")
toClient("ProfileSync", snapshot({ Items = { heal_cloud = 2 } })); T.check(State.Get().Items == nil, "a stray Items key in a sync is dropped")
MC.Open("Pets", {}); T.check(find(inv, "Tab_Items") == nil and find(inv, "Tab_Team") ~= nil and find(inv, "Tab_Pets") ~= nil, "the Pets window tabs are Pets + Team")
MC.Open("Shop", {}); T.check(find(shop, "Tab_Items") == nil and find(shop, "Tab_Roulettes") and find(shop, "Tab_Gems"), "the Shop tabs are Roulettes + Gems")
toClient("OpenPanel", "Shop", { Tab = "Items" }); advance(0.3); T.check(find(shop, "Page_Roulettes").Visible, "OpenPanel('Shop', { Tab = 'Items' }) lands on Roulettes")
toClient("OpenPanel", "Inventory", { Tab = "Items" }); advance(0.3); T.check(find(inv, "Page_Pets").Visible, "OpenPanel('Inventory', { Tab = 'Items' }) lands on Pets")
local vit = hud().BottomLeft.Vitals
T.check(vit.AbsolutePosition.Y + vit.AbsoluteSize.Y <= 1080 - 78 and vit.Visible, "the HP card sits above the hotbar's old footprint (HOTBAR_FALLBACK) with nothing below it")
for i = 1, 4 do Mock.Key(Enum.KeyCode["One"], i) end; T.eq(#Mock.Errors, errs0, "keys 1-4 do nothing and raise nothing")
```

- [ ] **Step 2: Register in `tools/smoke.py`** and unregister the dead scenarios:

```python
server_scenarios.remove("items"); client_scenarios.remove("client_hotbar")  # HUD cleanup, Task 3: items and the hotbar are gone
if p5("smoke_hud_items.lua"): server_files.append("smoke_hud_items.lua"); client_files.append("smoke_hud_items.lua"); ins(server_scenarios, "shutdown", ["huditems_gone", "huditems_refund"]); ins(client_scenarios, "client_final", ["client_huditems_gone"])  # [owner: HUD cleanup, Task 3] items removed: no catalog / service / remotes / hotbar / Items tabs, the boarded-up stall, the one-time B3ItemsRefund (30 / 45 / 150, clamp 5, marker, toast, provisional merge) (smoke_hud_items.lua: both worlds)
```

Also update the docstring at the top of `smoke.py` (the `smoke_economy.lua` / `smoke_client_v2.lua` lines mention items / hotbar).

Run: `py -3.12 tools/smoke.py --only huditems_gone,huditems_refund,client_huditems_gone`
Expected: FAIL.

- [ ] **Step 3: Delete the item code.** `git rm src/shared/ItemCatalog.lua src/server/Services/ItemService.lua src/client/Controllers/HotbarController.lua`; `Config.Remotes` minus `"BuyItem"` / `"UseItem"`; delete `Config.Items`; `Main.server.lua` lines 232, 301-305, 369-371 (and the header line 8 mention); `Main.client.lua` line 20.
- [ ] **Step 4: DataService refund.** Add the `P6` block next to `P3.gardenMigrate` (~5364): `P6.MARK = "B3ItemsRefund"`, `P6.REFUND`, `P6.REFUND_MAX = 5`, `function P6.itemsRefund(entry)`: returns nil unless `entry.Loaded`, not provisional and `Migrations[P6.MARK] ~= true`; sums `min(P6.REFUND_MAX, floor(count)) * (P6.REFUND[id] or 0)` over `profile.Items`, adds it to `profile.Tokens` the way `DataService.AddTokens` does internally (same stats bookkeeping, `entry.Dirty = true`), sets `profile.Items = {}` and the marker, records `entry.MigratedNow[P6.MARK] = { Tokens = n, Items = <copy> }`, returns the info. Call it right after both `P3.gardenMigrate(entry)` calls (3566, 3941) and announce like `P5.announceMigration`: `DataService.Migrated:Fire(player, P6.MARK, deepCopy(info))` only when `info.Tokens > 0`. The raw loader (2030-2038) keeps reading `raw.Items` leniently with a local `ITEM_MAX = 5` instead of `Config.Items.MaxCarry` (also line 2705's `applyCounts(..., Config.Items.MaxCarry)`); the stored field stays (`copyMap(p.Items)` in the save record) so the merge code is untouched, but the ProfileSync snapshot (`out.Items` at 1973 / the sync at 3305) drops `Items`. Header: document `B3ItemsRefund` in the Migrations list (line 29) and the `Migrated` names (274-275); remove `Items` from the ProfileSync line (278).
- [ ] **Step 5: The toast.** `Main.server.lua`, after `DataService.Load`-style wiring: `DataService.Migrated:Connect(function(player, name, info) if name == "B3ItemsRefund" and type(info) == "table" and (tonumber(info.Tokens) or 0) > 0 then Remotes.Get("Notify"):FireClient(player, "Items are gone from Nimbus: your old ones were refunded, +" .. info.Tokens .. " Tokens!", "token", 6) end end)` under `pcall`.
- [ ] **Step 6: Client.** `State.lua`: remove `Items` from the snapshot defaults / cleaner (553, 589) and `State.ItemCount` (709-711) and the header lines 9 / 58. `MenuController.lua`: remove the `ItemCatalog` require (130) and `itemDefs()` (739), `menuActionInventory` (2027), `gotoShopItems` (2632-2638) and its callers, the Inventory Items page (`buildItemsPage`, `refreshItemsPage`, `itemRows`) and `tabs.Add("Items", ...)` (3922), the Shop Items page and `tabs.Add("Items", ...)` (5072) and the `fire("BuyItem", ...)` (4443); `normalizeTab`: `"item"` -> `nil`; `Open` keys `"inventory" | "items"` -> `openWindow("Inventory", { Tab = "Pets" })`; the `Inventory` OnSelect title rule keeps `Team` / `Pets` only; header lines 33 / 81. Delete the hotbar helpers and their calls at the nine call sites listed in **Files** (each is a guarded `FindFirstChild("HotbarController")` lookup; the docked-window layout no longer re-centres anything). `HudController.lua`: `hotbarRect()` -> delete and let the `bar == nil` branch (`K.HOTBAR_FALLBACK`) stand; fix the comments at 38 / 88 / 689.
- [ ] **Step 7: NPC lines.** `NpcDialog.lua`: remove the `ItemCatalog` lazy require (30-40) and `itemPrice` (121-133); Movement Trainer line 4 -> `"Low on health in a climb? Reach the next checkpoint: everyone still up heals " .. percent(Config.Damage.CheckpointHealFraction) .. " there."` (keywords: drop `"1 to 4"`, `"Heal Cloud"`, add `"checkpoint"`); Captain Penguin line 3 -> `"A fallen teammate comes back at the next checkpoint with half health, so keep climbing and ring it for them!"` (keywords: drop `"Phoenix Feather"`); both <= 125 bytes.
- [ ] **Step 8: The boarded stall.** `LobbyBuilder.lua` `buildItemStall`: keep the sculpt; after `Mesh.tag(stallModel, ...)` build `local boards = newModel(model, "Boards")` with two `box(boards, "Plank1" | "Plank2", cf * CFrame.new(0, 5.5, -3.4) * CFrame.Angles(0, 0, +-math.rad(28)), Vector3.new(11, 0.9, 0.35), P.PlankDark.Color, { Collide = false })` crossing the counter front; `SubLabel` text `"Closed"` in `C.Text` instead of the Heal / Shield / Revive line; comment "Phase 6 / HUD cleanup: the stall is decoration, boarded up (no prompt)". Header lines 23 / 38.
- [ ] **Step 9: Contract, tools, docs.** `tools/contract.json` per the Interfaces block. `tools/smoke_content.lua`: drop the ItemCatalog block (418-421, 778-797), `Config.Items` (888) and the two remotes from the list (890). `tools/smoke_economy.lua`: delete the `items` scenario (1141-1235) and the stall-prompt assertions (1095-1110); `match_locks` keeps only the pets-in-matches half; line 793 "no pets". `tools/smoke_server.lua`: 1358 `prompts >= #Config.Roulettes`, 1481-1486 "no prompt under ItemShop", 1670-1676 `Items` absent or empty, 3249-3250 drop `saved.Items`. `tools/smoke_client.lua`: 350 drop `NimbusHotbar`, 1090 drop `Items`, 1344 / 1358 / 1435-1472 drop the hotbar entries. `tools/smoke_client_v2.lua`: 14, 168, 539-597 (`Items` / `ItemCount` lines), 987, 1072 ("tabs Pets and Team"), 1148-1160, 1311-1358, 1463-1480 (`client_hotbar` body removed). `tools/smoke_dev.lua`: 109, 440-443, 520, 1089-1090. `tools/smoke_p2_flow.lua:679, 764`: the stored `Items = { heal_cloud = 1 }` is refunded: `cp.Tokens == 370` and `next(cp.Items) == nil`. `tools/smoke_p5_gui.lua:161-167`, `tools/smoke_p3_fix_client.lua:549, 665, 875`, `tools/smoke_p4_fix_client.lua:519`, `tools/smoke_bug2_gui.lua:98, 155, 199, 243, 347, 389`: drop the hotbar paths. `tools/dump_gui.lua:780, 2406-2408`. `README.md`: replace the items paragraphs with one line ("2026-10-30: the obby items, the item shop stall's prompt and the hotbar were removed; old items were refunded as Tokens once").
- [ ] **Step 10: Run the smoke tests.**

Run: `py -3.12 tools/smoke.py --only huditems_gone,huditems_refund,client_huditems_gone,contract,catalog,config_shape,boot,lobby,economy,match_locks,profile_sync,migration,persistence,p2flow_arrive,p2flow_rejoin,p5ui_content,p3ui_content,p4ui_content,dev_tools,client_state,client_menu,client_dev,client_p3fixcli_landscape,client_bug2gui_layout,client_bug2gui_mobile,client_final,client_mobile`
Expected: all `ok`, exit 0; `node tools/check.mjs` exits 0; then the full `tools/run_checks.sh --quick` exits 0 (items appear in many scenarios).
- [ ] **Step 11: Commit.**

```bash
git add -A src tools README.md
git commit -m "feat(items): remove the obby items, hotbar and stall prompt; refund saved items once as Tokens (B3ItemsRefund); boarded-up stall"
```

---

### Task 4: Ring: HP carried across rounds, fainted pets stay out, champions on the player formula, a new curve

Runs in parallel on branch `hud-ring` (`git worktree add "../ring" -b hud-ring` from the plan commit of `hud-cleanup`). Touches only the files below; the only client file is `ArenaController.lua` and only its Ring window text (`:1170-1175`).

**Files:**
- Modify: `src/shared/BattleCatalog.lua:876-915` (the `Ring` table + comment), `:1010-1035` (`P4.basePower` / `P4.power` stay for the Dungeon), `:1036-1051` (`RingTarget`), `:1116-1260` (`P4.solve`, `memoFor`, `saturation`, `history`, `ring`, `ChampionTeam`, `RingPower`), `:2110-2145` (`Validate` ring block), header line 59
- Modify: `src/shared/BattleSim.lua:547-660` (`unitFromDef`), `:3167-3215` (`finish`), header (the result shape)
- Modify: `src/server/Services/BattleService.lua:738-805` (`teamOf`), `:3119-3172` (`RingRun.startRound`), `:3197-3230` (`RingRun.afterBattle`), `:3232-3270` (`RingRun.endRun` reasons), `:3380-3500` (`StartRing` run record), header lines 33 / 90
- Modify: `src/client/Controllers/ArenaController.lua:1170-1175` (the "How" text only)
- Modify: `tools/sim_battle.lua:12`, `:209-210`, `:1076-1200`, `tools/smoke_p5_battlecore.lua:1636-1652`
- Create: `tools/smoke_ring_noheal.lua`; Modify: `tools/smoke.py`

**Interfaces:**
- Consumes: `PetCatalog.GetStats(def, level, tier, stage)`, `PetCatalog.EvolutionStage(def, level, stored)`, `PetCatalog.MaxPetLevel()`, `BattleCatalog.UnitStats / UnitPower / TeamPower`, `BattleSim.new(setup).Result()`, `DataService.GetPetLevel / GetGrowth`.
- Produces:
  - `BattleCatalog.Ring` gains `LevelAnchors = { { 1, 1 }, { 3, 1 }, { 10, 6 }, { 14, 9 }, { 20, 15 }, { 27, 24 }, { 33, 33 }, { 42, 46 }, { 49, 58 }, { 60, 80 }, { 70, 100 } }` (round -> level, piecewise linear, floored, the last anchor holds), `BossLevelBump = 3`, `TierFrom = { Golden = 36, Rainbow = 52 }`, `Evolve = true`, `Helpers = { { From = 56, Count = 2 }, { From = 66, Count = 3 } }`, `MaxChampions = 3`; loses `FirstPower`, `Growth`, `BossBump`, `MinHandicap`, `ChampionMaxLevel`, `EasyRounds` (rounds 1-3 are plain level-1 Commons now). `Bands`, `BossEvery`, `BossTokens`, rewards and timing fields stay. (These anchor values are the STARTING point; the sim tunes them, see Step 8.)
  - `BattleCatalog.ChampionLevel(round) -> integer` (the curve + `BossLevelBump` on `BossEvery` rounds, capped at `PetCatalog.MaxPetLevel()`), `BattleCatalog.ChampionTier(round) -> "Normal" | "Golden" | "Rainbow"`, `BattleCatalog.ChampionCount(round) -> 1..3`.
  - `BattleCatalog.ChampionTeam(round, seed)` -> `{ Owner = "npc", Side = 2, Npc = true, Name = "Champion <name>", Round, Seed, Power, Champion = { PetId, Level, Tier, Evo, Count, Boss = <bool flag, BossEvery rounds>, Name, Power }, Pets = { { PetId, Key, Level, Tier, Evo, Slot, Crowned = (i == 1) or nil, MeterStart = Damage.LateMeterStart } ... } }` with **no** `Boss` / `Handicap` / `Boost` on any pet; `Power = BattleCatalog.TeamPower(spec.Pets)`; `Power(round) >= Power(round - 1)` for every seed (the level is raised, then the tier, then a helper added until it holds). `BattleCatalog.RingPower(round, seed)` = that `Power`. `RingTarget` is removed.
  - `BattleSim`: a player pet entry may carry `HpFraction` (0 < f <= 1): the unit starts at `maxHp * f` (clamped to >= 1 HP). `Result()` gains `Units = { [owner] = { { Key, Hp, MaxHp, Alive } ... } }` for every player team (Hp = `max(0, floor(hp + 0.5))`, `Alive = u.alive and hp > 0`).
  - `BattleService`: `teamOf(player, side, fallback, hpByKey)`: skips keys with `hpByKey[key] == 0`, sets `HpFraction = hpByKey[key]` on the others; the run record gains `Hp = {}` (key -> fraction, filled after every won round from `result.Units[player.UserId]`) and `Fainted = {}` (key -> true); `RingRun.liveKeys(run) -> {key...}`; a won round that leaves no live key ends the run with reason `"Fainted"` and the toast `"Your whole team fainted: the run is over"`; `BattleService.TeamSpec(player, keys, hpByKey)` exports the 4th parameter.
  - `ArenaController` Ring "How" text appends: `" Your pets keep their HP from round to round, and a fainted pet sits out the rest of the run."`
  - `tools/sim_battle.lua`: `SIM.RingMedians = { S1 = 14, S3 = 21, S5 = 27, S7 = 33, S9 = 42, S10 = 49 }` (today's measured values, see Step 8), `SIM.ringRun(pets, runSeed, maxRound)` carries HP and drops fainted pets between rounds; `SIM.Maxed = { pet("stormfang", 100, "Rainbow", { Evo = 2, Train = max }), pet("eclipse_dragon", 100, "Rainbow", { Evo = 2, Train = max }), pet("cloudy_dragon", 100, "Rainbow", { Evo = 2, Train = max }) }`.

- [ ] **Step 1: Record the BEFORE numbers** (done while planning; keep them here as the acceptance baseline). `SIM_BATTLE="only=ring" py -3.12 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua', encoding='utf-8').read())"` on `hud-cleanup` at `9544a97`, fresh HP every round, 12 seeds per stage:

| stage | team power | record median (min-max) | avg fight |
|---|---|---|---|
| S1 Day 1 | 20 | 14 (13-15) | 14.2 s |
| S2 First week | 30 | 17 (15-19) | 14.3 s |
| S3 Early | 55 | 21 (18-24) | 12.2 s |
| S4 Early+ | 84 | 24 (23-24) | 10.5 s |
| S5 Mid | 167 | 27 (27-29) | 6.4 s |
| S6 Mid+ | 241 | 31 (29-32) | 9.1 s |
| S7 Prestige 1 | 411 | 33 (32-34) | 8.6 s |
| S8 Prestige 2 | 625 | 36 (35-37) | 10.0 s |
| S9 Endgame | 1479 | 42 (40-43) | 8.9 s |
| S10 Maxed (L45-50 Rainbow) | 5472 | 49 (49-49) | 4.0 s |

Single level-1 starters: 100 % at rounds 1-6. Today's champions: round 15 = L13 Common, round 25 = L38 Rare, round 30 = L27 Rare mini-boss, round 40 = L41 Rainbow mini-boss, round 50+ = L50 Rainbow mini-boss with Boost x3 .. x3380 (the owner's complaint: a L27 champion beats L24 pets because of the x3 HP / x1.3 power boss form). The sim's own stale table (16 / 23 / 28 / 36 / 44 / 51) already MISSES by 2-3; the table is replaced by the measured values above.

**AFTER (acceptance values, the no-heal rule in force, 12 seeds per stage, `tools/sim_battle.lua` section `ring` must print every `TARGET ok`):**
- (a) record medians within **+-3** of S1 14, S3 21, S5 27, S7 33, S9 42, S10 49; the record never falls with the stage; fights 4-40 s on average at every stage.
- (b) level gap: S7's team (L20-24) vs `ChampionTeam(10, seed)` (L9 Common, the boss round) wins >= 95 % of 24 fresh-HP fights; S9 (L35-40) vs `ChampionTeam(21, seed)` (L16) >= 95 %; S10 (L45-50 Rainbow) vs `ChampionTeam(30, seed)` (L31 Normal, the boss round) >= 95 %. (The levels quoted follow the starting anchors; after the tune the rule is "champion level <= the team's lowest level - 10".)
- (c) `SIM.Maxed` (three L100 Rainbow evo-2 fully trained pets): record median **between 60 and 95**; `ChampionTeam(100, seed)` (three L100 Rainbow pets) beats `SIM.Maxed` in >= 60 % of 24 fresh-HP fights (the top stays hard).
- rounds 1-3 are won >= 95 % by every single level-1 rollable Common / Uncommon; the single-pet average stays >= 80 % at rounds 4-5; `RingPower(r, s) >= RingPower(r - 1, s)` for r in 2..120 over 40 seeds; no pet in any `ChampionTeam(r, s)` carries `Boss` / `Handicap` / `Boost`; every level <= 100; `#Pets <= 3`; `#ChampionTeam(100, s).Pets == 3`.

- [ ] **Step 2: Write the failing smoke file `tools/smoke_ring_noheal.lua`** (server world + pure scenarios):

```lua
-- pure: ringnh_catalog
for r = 1, 120 do for s = 1, 8 do
  local spec = BC.ChampionTeam(r, s)
  t1:case(type(spec) == "table" and #spec.Pets >= 1 and #spec.Pets <= 3, r .. "/" .. s)
  for _, p in ipairs(spec.Pets) do t2:case(p.Boss == nil and p.Handicap == nil and p.Boost == nil and p.Level <= 100 and p.Level >= 1, r .. ":" .. p.PetId) end
  if r > 1 then t3:case(BC.RingPower(r, s) >= BC.RingPower(r - 1, s), r .. "/" .. s) end
  t4:case(not PC.IsEventOnly(spec.Pets[1].PetId), spec.Pets[1].PetId)
end end
t1:report(); t2:report("no Boss / Handicap / Boost, levels 1..100"); t3:report("power never drops"); t4:report()
T.check(BC.ChampionLevel(1) == 1 and BC.ChampionLevel(3) == 1 and BC.ChampionLevel(14) == 9 and BC.ChampionLevel(27) == 24 and BC.ChampionLevel(21) == 16 and BC.ChampionLevel(71) == 100 and BC.ChampionLevel(120) == 100, "ChampionLevel follows LevelAnchors (linear between anchors, floored) and holds at 100")
T.check(BC.ChampionLevel(10) == BC.Ring.LevelAnchors[3][2] + BC.Ring.BossLevelBump and BC.ChampionLevel(20) == 15 + BC.Ring.BossLevelBump, "a boss round (BossEvery) adds BossLevelBump levels")
T.check(BC.ChampionTier(10) == "Normal" and BC.ChampionTier(36) == "Golden" and BC.ChampionTier(52) == "Rainbow", "ChampionTier by TierFrom")
T.check(BC.ChampionCount(55) == 1 and BC.ChampionCount(56) == 2 and BC.ChampionCount(66) == 3 and #BC.ChampionTeam(100, 1).Pets == 3, "helpers join at Helpers.From; round 100 fields three")
local c1 = BC.ChampionTeam(1, 5).Pets[1]
T.check(c1.Level == 1 and c1.Tier == "Normal" and PC.GetRarity(c1.PetId) == "Common", "round 1 is a plain level-1 Common")
local us = BC.UnitStats(BC.ChampionTeam(40, 2).Pets[1]); local def = PC.Get(BC.ChampionTeam(40, 2).Pets[1].PetId)
local want = PC.GetStats(def, BC.ChampionLevel(40), BC.ChampionTier(40), 2)
T.check(math.abs(us.MaxHp - want.Health * BC.Roles[BC.RoleOf(def)].Health * BC.Damage.HpScale) < 1e-6, "a champion's MaxHp is the PLAYER formula (PetCatalog.GetStats x role x HpScale, evolved as its level allows)")
T.check(BC.ChampionTeam(40, 2).Pets[1].Evo == PC.EvolutionStage(def, BC.ChampionLevel(40), 2), "...and its Evo is the stage its level allows")
T.check(BC.ChampionTeam(10, 1).Champion.Boss == true and BC.ChampionTeam(11, 1).Champion.Boss == nil, "Champion.Boss stays a flag on BossEvery rounds (rewards / crowd), not a stat multiplier")
T.check(BC.RingTarget == nil and BC.Ring.FirstPower == nil and BC.Ring.Growth == nil and BC.Ring.EasyRounds == nil, "the old target solver knobs are gone")
T.check(BC.Validate() == true or #BC.Validate() == 0, "BattleCatalog.Validate passes")

-- pure: ringnh_sim_hp
local team = { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 5, nil, { HpFraction = 0.25 }), pet("puddle_frog", 5), pet("mallow_kitten", 5) } }
local b = BS.new({ Mode = "Ring", Seed = 1, Round = 1, Teams = { team, BC.ChampionTeam(1, 1) } })
local u = b:StaticUnits()
T.check(math.abs(u[1].hp / u[1].maxHp - 0.25) < 1e-6 and u[2].hp == u[2].maxHp, "HpFraction sets the starting HP; pets without it start full")
local tiny = BS.new({ Mode = "Ring", Seed = 1, Round = 1, Teams = { { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 1, nil, { HpFraction = 1e-9 }) } }, BC.ChampionTeam(1, 1) } })
T.check(tiny:StaticUnits()[1].hp >= 1, "a tiny fraction still starts with >= 1 HP (never a dead unit at the bell)")
local junk = BS.new({ Mode = "Ring", Seed = 1, Round = 1, Teams = { { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 1, nil, { HpFraction = 7 }), pet("puddle_frog", 1, nil, { HpFraction = "x" }) } }, BC.ChampionTeam(1, 1) } })
T.check(junk:StaticUnits()[1].hp == junk:StaticUnits()[1].maxHp and junk:StaticUnits()[2].hp == junk:StaticUnits()[2].maxHp, "fractions above 1 or junk mean full HP")
local res = runToEnd(b)
T.check(type(res.Units) == "table" and type(res.Units[1]) == "table" and #res.Units[1] == 3, "Result().Units lists the player team's pets")
for _, r in ipairs(res.Units[1]) do t5:case(type(r.Key) == "string" and r.Hp >= 0 and r.Hp <= r.MaxHp and (r.Alive == (r.Hp > 0)), r.Key) end; t5:report("Key / Hp / MaxHp / Alive consistent")
T.check(res.Units["npc"] == nil, "...NPC teams are not listed")
-- a pet that dies as the last blow lands is not alive
local killed = runUntilFirstKnockout(b2)  -- white-box: force u.hp = 0 on a benched pet, finish
T.check(killed.Units[1][2].Alive == false and killed.Units[1][2].Hp == 0, "0 HP = fainted, never revived by the win")
-- the fraction carries across a level-up: 40% of a L5 max becomes 40% of a L6 max
local f = 0.4; local l5 = BC.UnitStats("pebble_pup", 5).MaxHp; local l6 = BC.UnitStats("pebble_pup", 6).MaxHp
local n = BS.new({ Mode = "Ring", Seed = 1, Round = 2, Teams = { { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 6, nil, { HpFraction = f }) } }, BC.ChampionTeam(2, 1) } })
T.check(math.abs(n:StaticUnits()[1].hp - l6 * f) < 1e-6 and l6 > l5, "a level-up between rounds keeps the FRACTION (no heal beyond the share)")

-- server: ringnh_service  (booted; a player with a 3-pet team at the ring portal, the p4ring_run harness drive)
local okR, id = BS_.StartRing(a); T.check(okR, "the run starts")
K.loseHpTo(id, a, { [keys[1]] = 0.3, [keys[2]] = 0 }); K.winRound(id)   -- white-box: set the sim units' hp, then knock the champion out
advance(BC.Ring.Intermission + 0.5)
local b2 = K.battleOf(a)
local units = K.unitsOf(b2, a)
T.check(#units == 2 and units[1].key == keys[1] and math.abs(units[1].hp / units[1].maxHp - 0.3) < 0.02, "round 2 fields the two live pets; the hurt one keeps 30% HP")
T.check(units[2].key == keys[3] and units[2].hp == units[2].maxHp, "...the untouched pet is still full")
T.check(K.run(a).Fainted[keys[2]] == true and K.run(a).Hp[keys[2]] == 0, "the fainted pet is recorded")
T.check(K.startPayload(a).Units and #K.startPayload(a).Units == 2, "the client's Start payload lists 2 fighters")
K.loseHpTo(b2.Id, a, { [keys[1]] = 0, [keys[3]] = 0.05 }); K.winRound(b2.Id); advance(BC.Ring.Intermission + 0.5)
T.check(K.unitsOf(K.battleOf(a), a)[1].key == keys[3], "round 3: only the last pet")
K.loseHpTo(K.battleOf(a).Id, a, { [keys[3]] = 0 }); K.winRoundByTimeoutKillBoth(K.battleOf(a).Id)  -- champion down, last pet at 0 in the same step
advance(BC.Ring.Intermission + 0.5)
T.check(K.run(a) == nil and K.lastEnd(a).Reason == "Fainted" and K.notifies(a)[#K.notifies(a)]:find("whole team fainted"), "a win with no pet left ends the run with reason Fainted and the toast")
T.check(K.profile(a).Ring.Best == 3 and K.profile(a).Ring.Runs == 1, "...the three wins stayed paid (Best 3, Runs 1)")
-- a real loss still ends the run; a fresh run heals (new run = new Hp table)
local ok2 = BS_.StartRing(a); local u2 = K.unitsOf(K.battleOf(a), a)
T.check(ok2 and #u2 == 3 and u2[1].hp == u2[1].maxHp, "a new run starts with every pet at full HP")
T.check(BS_.TeamSpec(a, keys, { [keys[1]] = 0 }).Pets[1].Key == keys[2] and #BS_.TeamSpec(a, keys, { [keys[1]] = 0 }).Pets == 2, "TeamSpec(player, keys, hpByKey) skips 0-HP keys")
```

- [ ] **Step 3: Register in `tools/smoke.py`:**

```python
if p5("smoke_ring_noheal.lua"): server_files.append("smoke_ring_noheal.lua"); ins(server_scenarios, "p4ring_start", ["ringnh_catalog", "ringnh_sim_hp", "ringnh_service"])  # [owner: HUD cleanup, Task 4] the Champion Ring no-heal rule: HpFraction in BattleSim, Result().Units, HP carried across rounds and fainted pets out in BattleService, champions on the player stat formula (ChampionLevel / Tier / Count, no Boss / Handicap / Boost), the monotonic ladder (smoke_ring_noheal.lua: server world)
```

Run: `py -3.12 tools/smoke.py --only ringnh_catalog,ringnh_sim_hp,ringnh_service`
Expected: FAIL (`ChampionLevel` nil, `Units` nil).

- [ ] **Step 4: BattleSim.** `unitFromDef`: after `local maxHp = ...`, `local startHp = maxHp; if finite(entry.HpFraction) and entry.HpFraction > 0 and entry.HpFraction <= 1 then startHp = max(1, maxHp * entry.HpFraction) end` and `hp = startHp` in the unit table (only for `team.player` teams). `finish`: build `result.Units[team.owner] = { { Key = u.key, Hp = max(0, floor(u.hp + 0.5)), MaxHp = floor(u.maxHp + 0.5), Alive = u.alive and u.hp > 0 } ... }` over `team.units` of every `team.player` team (bench included, `Minion` kinds never appear on player teams). Header: document `HpFraction` under the team spec and `Units` under the result.
- [ ] **Step 5: BattleCatalog.** Replace the Ring comment + table (876-915) and the solver (1036-1051, 1116-1260) with: `BattleCatalog.ChampionLevel(round)`, `ChampionTier(round)`, `ChampionCount(round)`, `P4.bandRarity(r)` (the band's lower rarity in the first half of the band's rounds, the higher in the second half; the open-ended band uses its last rarity from `From + 6` on), `P4.pickSpecies(r, s, rarity)` (the existing seeded stream, one rarity), `P4.champion(r, s, prevPower)` (entry at the curve level / tier / `Evo = PetCatalog.EvolutionStage(def, level, 2)`; while `EntryPower(entries) < prevPower`: level + 1 up to 100, then the next tier, then another pet of the same species at the same level up to `MaxChampions`), the per-seed memo (`P4.memoFor` with the new knobs in its signature, `P4.history`), `ChampionTeam`, `RingPower`. Delete `RingTarget`, `P4.saturation`, `P4.solve`; keep `P4.basePower`, `P4.power`, `P4.solveEntry`, `SolveEnemy` (the Dungeon uses them). `Validate` ring block: the assertions of `ringnh_catalog` (1..120 x seeds 1..4, no Boss/Handicap/Boost, monotonic, `#Pets <= 3`, three pets by round 100, every `TierFrom` / `Helpers.From` inside 1..MaxRound, `LevelAnchors` strictly increasing in both columns ending at `MaxPetLevel()`). Header line 59.
- [ ] **Step 6: BattleService.** `teamOf(player, side, fallback, hpByKey)`; `BattleService.TeamSpec(player, keys, hpByKey)`; `StartRing` run record: `Hp = {}`, `Fainted = {}`; `RingRun.liveKeys(run)` = `run.Keys` minus `run.Fainted`; `startRound`: `local keys = RingRun.liveKeys(run); if #keys == 0 then return false, "Fainted" end; local spec, reason = teamOf(player, 1, keys, run.Hp)`; `afterBattle` on a win, before the intermission: for each `r` in `result.Units[player.UserId]`: `run.Hp[r.Key] = r.Alive and (r.Hp / r.MaxHp) or 0; if not r.Alive then run.Fainted[r.Key] = true end`; if `#RingRun.liveKeys(run) == 0` then `notify(player, "Your whole team fainted: the run is over", "bad", 5)` and `RingRun.endRun(run, b, "Fainted")` (the rewards of that last win are already paid by `pay`); `nextRound`'s failure path maps `why == "Fainted"` to the same toast + `endRun(run, nil, "Fainted")`. `KeysInBattle` keeps the whole `run.Keys` (fainted pets stay locked for the run). Header lines 33 / 90.
- [ ] **Step 7: ArenaController Ring text** (`:1170-1175`): append the sentence of the Interfaces block to the "How" `wrapText`.
- [ ] **Step 8: sim_battle.lua + tune.** Rewrite `ringRun` to carry HP (`res.Units[77]` -> `HpFraction` on the next fight's entries, dead pets dropped; when none is left the run ends); update `SIM.RingMedians` to the BEFORE table; replace the "ladder / Boost" header block with: the monotonic power target (40 seeds, 2..120), the "no Boss / Handicap / Boost" target, the (b) level-gap targets and the (c) `SIM.Maxed` targets; print the champion table `round | level | tier | count | species | power` for rounds 1, 2, 3, 5, 10, 15, 20, 25, 30, 36, 40, 50, 52, 56, 60, 66, 70, 80, 100, 120. Header line 12. Then tune `Ring.LevelAnchors`, `TierFrom`, `Helpers`, `BossLevelBump` until the section prints every `TARGET ok`:

Run: `SIM_BATTLE="only=ring" py -3.12 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua', encoding='utf-8').read())"`
Expected: `TARGET ok` on every ring line; the SUMMARY counts no MISS in the ring section. Paste the final stage table (the AFTER numbers) into the commit message body and into `BattleCatalog.Ring`'s comment ("tuned 2026-10-30: S1 .. S10 medians ...").
- [ ] **Step 9: Existing tests.** `tools/smoke_p5_battlecore.lua:1636-1652`: the medians check reads `SIM.RingMedians` (now S1 14 / S10 49) with +-3; the round-3 single-pet fights stay. `tools/smoke_p4_fix_client.lua:385` / `tools/smoke_p3_fix_client.lua:635-645` / `tools/dump_gui.lua:1187, 2549`: they read `spec.Pets[1].PetId / Level`, unchanged; check they do not read `Boss` / `Boost` (grep; fix if so). `tools/smoke_p4_ring.lua`: `p4ring_run` ("a single level-1 pet wins rounds 1-3") still holds (round 1-3 = a plain L1 Common vs the player's L1 pet: the sim's >= 95 % target covers it).

Run: `py -3.12 tools/smoke.py --only ringnh_catalog,ringnh_sim_hp,ringnh_service,catalog,p5dgn_catalog,p5sim_modes,p5sim_wire,p5sim_determinism,p5battle_balance,p4ring_start,p4ring_run,p4ring_rewards,p4ring_ends,p4ring_lossxp,p5svc_ring,fixleave_ring,p4fixbat_forfeit,p4fixbat_return,audio_ring_pocket,client_p4fix_leave,client_p3fixcli_retreat,client_p4portal_ring,client_audio_ring,client_final`
Expected: all `ok`, exit 0; `node tools/check.mjs` exits 0 (`RingTarget` leaves the contract: remove it from `shared/BattleCatalog.functions`, add `ChampionLevel`, `ChampionTier`, `ChampionCount`).
- [ ] **Step 10: Commit and push the branch.**

```bash
git add src/shared/BattleCatalog.lua src/shared/BattleSim.lua src/server/Services/BattleService.lua src/client/Controllers/ArenaController.lua tools/sim_battle.lua tools/smoke_ring_noheal.lua tools/smoke.py tools/smoke_p5_battlecore.lua tools/contract.json
git commit -m "feat(ring): no heal between rounds, fainted pets sit out, champions on the player stat formula, new level curve (sim-tuned)"
git push -u origin hud-ring
```

The merge of `hud-ring` into `hud-cleanup` (after Task 3) is a plain merge: the two branches share no files except `tools/smoke.py` (two added registration lines) and `tools/contract.json` (different modules).

---

## Self-review notes

- Spec coverage: decision 1 -> Task 1 (pill, inset rule, phone TopBand, Shop in-match refusal); decision 3 -> Task 1 (Travel: drop-down, lobby-only visibility, server validation + rate limit, fade); decision 2 -> Task 2 (strip + Edit + Auto-fill best on Dungeon / Arena queue / raid / duel, popup that continues, Team tab, tutorial retarget, refusal text); decision 4 -> Task 3 (tile, tabs, hotbar, three items, ItemService, remotes, NPC lines, refund with marker, boarded stall without prompt); decision 5 -> Task 4 (HP carried, fainted out, player formula, sim-tuned curve with the three targets). Non-goals untouched (no new items / presets, Obby and Dungeon parties unchanged). Anti-goals each have a test (pill overlap: `client_hudpill` / `_mobile`; stuck player: `client_hudteam_portal`; refund: `huditems_refund`; rounds 1-2: the sim's >= 95 % target + `p4ring_run`).
- The "panel's suggested power" of spec target (a) is `ArenaController.Ring.preview`'s `RingPower(round, 1)`, which is the stage-team medians of `sim_battle` by construction; the plan uses the stage medians as the measurable form.
