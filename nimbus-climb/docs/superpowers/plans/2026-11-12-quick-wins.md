# Slop-Audit Quick Wins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the seven owner-approved quick wins from the AI-slop audit: a clean title screen, shorter world-card range, a lava-coloured Lava Golem, no player vitals card during a pet battle, a Gifts button that hides behind every window, a drawn close X, and five text fixes.

**Architecture:** Seven small, independent changes grouped into five tasks so that no file is touched by two tasks (the builders run in parallel in one worktree). Each task pins its new behaviour in smoke files it alone owns, updates the old pins that hold the old values, and runs only its own scenarios.

**Tech Stack:** Roblox (Rojo), plain Lua 5.1-compatible syntax, the mock smoke harness (`py -3.12 tools/smoke.py --only a,b,c`; `tools/README.md`).

**Spec:** `C:/Users/elmoz/OneDrive/שולחן העבודה/Projects Main/Nimbus/.superpowers/slop-audit/round2.json` (findings) plus the seven wins as the owner approved them (numbered 1 to 7 below, same numbers as the workflow task). Screenshots: `C:/Users/elmoz/AppData/Local/Temp/claude/C--Users-elmoz/f97a4752-9063-43fe-8dc2-794f5d296747/scratchpad/shots`.

## Global Constraints

- Read `ABSOLUTE_RULES.md` and `brain.md` first.
- Plain Lua 5.1-compatible syntax only (no `continue`, no `+=`, no type annotations, no string interpolation).
- Every change needs evidence: new behaviour pinned in a smoke check, old pins that assert the old values **updated, not deleted**.
- Do NOT run the whole smoke suite (another whole run is on this machine and memory is short). Run only the task's own command, one run at a time.
- No Roblox Studio, no Blender, no uploads, no git commits, no push. Work only inside `C:/Users/elmoz/OneDrive/שולחן העבודה/Projects Main/Nimbus/.worktrees/quick-wins/nimbus-climb`.
- A task edits only the files in its own list. Nobody edits `tools/smoke.py`, `tools/README.md`, `README.md`, `brain.md`, `ABSOLUTE_RULES.md`. No new smoke files (every smoke file is registered in `tools/smoke.py`): add checks to the listed files.
- `ARCHITECTURE_V3.md` is edited by Task 2 only; `src/shared/Config.lua` by Task 3 only (Task 1 only reads `Config.Tagline`). Other tasks document in their own file headers and name any stale ARCHITECTURE line in their report.
- Other builders are editing the same worktree. Keep every saved edit loadable. A failure in a scenario that lives in another task's smoke file is a regression signal: re-run it once at the end, then report it; do not edit that file.
- Out of scope: anything else from the audit, the window kit look, new art, uploads.
- Copy fixed by the owner, exact: credits `A SaintsField game` / `Created by St.Gavin`, no "Built with Claude" line; tagline `Config.Tagline` = `Climb the storm. Together.`

## Review Focus

1. A world card that appears while the menu is already up (a gate that streams in, `/menu` reopened mid-game) or one the game itself had switched off: it must be hidden during the menu and come back exactly as its owner left it. Pinned in Task 1.
2. A burst of toasts while the title is up, and an error toast during it: gameplay toasts wait (at most 4, order kept), `"bad"` shows at once, nothing is lost silently beyond the cap. Pinned in Task 1.
3. A fight that ends by any path (result, leave, cleanup, turning spectator): the vitals card always returns, and the battle never releases another owner's hide (`"Daily"`). Pinned in Task 4.
4. A window closed by a path that fires no signal (Esc, another window taking over, a match start): the Gifts button is back within 0.4 s; the Daily window itself never hides its own button. Pinned in Task 5.
5. A close button that is resized or moved after it is built (phone, portrait, `PetsController` moving `panel.CloseButton`): the X stays centred, scales with the button, and the 44 px tap size is unchanged. Pinned in Task 5.

## File ownership (no file in two tasks)

| Task | Wins | Source | Smoke (always) | Smoke (only if an existing pin breaks) |
|---|---|---|---|---|
| 1 `title-and-text` | 1, 7 | `MainMenuController`, `NotifyController`, `UpdateNotes`, `LoadingScreen.client`, `DungeonBuilder`, `DungeonController`, `BattleService` | `smoke_p5_menu`, `smoke_p5_dungeon`, `smoke_p5_battleservice` | `smoke_session_lock`, `smoke_p5_looks` |
| 2 `card-range` | 2 | `WorldStyle`, `PortalService`, `LobbyBuilder`, `ArenaBuilder`, `PetCard`, `ARCHITECTURE_V3.md` | `smoke_polish_worldtext`, `smoke_polish_portals`, `smoke_p5_world`, `smoke_p4_pets_client`, `smoke_p3_arenaworld` | none |
| 3 `boss-colours` | 3 | `BossBuilder`, `Config` | `smoke_raid_world` | `smoke_raid_client`, `smoke_sky` |
| 4 `battle-vitals` | 4 | `HudController`, `BattleController` | `smoke_wave6`, `smoke_evo_retreat`, `smoke_polish_vitals` | `smoke_p5_battleclient`, `smoke_p4_fix_client`, `smoke_p3_fix_client`, `smoke_evo_buttons`, `smoke_hud_pill`, `smoke_client` |
| 5 `windows-close` | 5, 6 | `DailyController`, `ShopController`, `NeonKit`, `CloudUI`, `PetPicker`, `FusionController`, `TrainController`, `TroveController`, `LossScreen`, `PetsController` | `smoke_client_v2`, `smoke_daily_ui`, `smoke_shop_ui` | `smoke_redo_daily_ui`, `smoke_fixr_daily_ui`, `smoke_redo_picker`, `smoke_redo_fusion_ui`, `smoke_redo_train`, `smoke_tb_loss`, `smoke_store_ui`, `smoke_fixr_store_ui`, `smoke_trove` |

---

### Task 1: title-and-text (wins 1 and 7)

**Files:**
- Modify: `src/client/Controllers/MainMenuController.lua` (K table ~80, tagline 553, `Open()` 1025-1041, `Play()` tail 1076-1083; `Gate` 208-258 is the pattern to mirror)
- Modify: `src/client/Controllers/NotifyController.lua` (`onNotify` 1300-1309, public API next to `Toast` 1366)
- Modify: `src/shared/UpdateNotes.lua:73-77`
- Modify: `src/first/LoadingScreen.client.lua:264` and `:537`
- Modify: `src/server/Services/DungeonBuilder.lua:1821`, `src/client/Controllers/DungeonController.lua:1135`
- Modify: `src/server/Services/BattleService.lua:2672, 2673, 3778`
- Test: `tools/smoke_p5_menu.lua` (`client_p5menu`, `client_p5loading`), `tools/smoke_p5_dungeon.lua` (`p5dgn_world`, `client_p5dungeon`), `tools/smoke_p5_battleservice.lua` (`p5svc_duel_fair`, `p5svc_ring`)

**Interfaces:**
- Produces: `NotifyController.SetHeld(who: string, on: boolean)` and `NotifyController.IsHeld() -> boolean` (owner-keyed, like `HudController.SetVitalsHidden`).
- Consumes: `Config.Tagline` (read only), `H.mod("NotifyController")` (MainMenuController's lazy optional lookup, 130-135).

- [ ] **Step 1: Add the failing pins.**
  - `client_p5menu` (world cards): put four BillboardGuis under `workspace` before `MMC.Open()`: `GateTag` (Enabled true), `PortalBillboard` (Enabled true), a second `GateTag` with Enabled false, and a `Nameplate` (Enabled true). Assert while the menu is open: both enabled cards are `Enabled == false`, `Nameplate` is still true. Add a fifth `GateTag` to `workspace` while the menu is open: it turns false. Set the first `GateTag.Enabled = true` while the menu is open: it goes back to false. After PLAY: first `GateTag`, `PortalBillboard` and the fifth are true, the already-disabled one is still false, `Nameplate` untouched.
  - `client_p5menu` (toasts), through `NotifyController.Toast(text, kind)` with the controller initialised the way the other client smokes do it: with the menu open `NotifyController.IsHeld() == true`; an `"info"` toast adds no toast frame to the `NimbusNotify` stack; a `"bad"` toast appears at once; six held toasts then PLAY shows exactly the last four, in the order sent; after PLAY `IsHeld() == false` and a new `"info"` toast appears at once. Also pin the owner key: `SetHeld("A", true); SetHeld("B", true); SetHeld("A", false)` leaves `IsHeld() == true`.
  - `client_p5menu` (credits and tagline): the menu's `Tagline` label text `== Config.Tagline` and `== "Climb the storm. Together."`; after `MMC.OpenCredits()` the `Credit1` / `Credit2` labels are exactly `A SaintsField game` / `Created by St.Gavin`, there is no `Credit3`, and no text in the Credits window contains "Claude".
  - `client_p5loading`: the loading `Tagline` label `== "Climb the storm. Together."`; with `math.random` stubbed to return `k`, the first tip shown (`H.find(gui, "Tip")`, line 255) is `tips[k]` for two different `k` with the same UserId; restore `math.random` afterwards (also on failure).
  - `p5dgn_world` and `client_p5dungeon`: the dungeon gate's `Info` text and the lobby window line both contain `up to 3 friends` and not `up to 4`; pin the number against the real cap (the lobby payload's `Max` minus 1; `DungeonService.MAX_PARTY = 4`, line 90).
  - `p5svc_duel_fair` and `p5svc_ring`: the controls hint sent on the Notify remote (`K.remotesFor("Notify", p.UserId, fromIndex)`, line 168) contains `F = target` and not `F = attack`.
- [ ] **Step 2: Run and see the new pins fail.** `py -3.12 tools/smoke.py --only client_p5menu,client_p5loading,p5dgn_world,client_p5dungeon,p5svc_duel_fair,p5svc_ring`. Expected: only the new pins fail.
- [ ] **Step 3: World cards (win 1).** In `MainMenuController.lua` add `K.WORLD_CARDS = { GateTag = true, PortalBillboard = true }` and a `Cards` table that mirrors `Gate`: `Cards.track(gui)`, `Cards.close()` (scan `Workspace:GetDescendants()`, connect `Workspace.DescendantAdded`), `Cards.open()` (disconnect, restore each card's remembered `Enabled`, skip destroyed cards). A card switched on by its owner while the menu is up stays off and the wish is remembered. Call `Cards.close()` right after `Gate.close()` in `Open()` and `Cards.open()` right after `Gate.open()` in `Play()`, each through `H.safe`. Client-side only; nothing on the server changes.
- [ ] **Step 4: Held toasts (win 1).** In `NotifyController.lua` add the owner table, `SetHeld`, `IsHeld`, and a held list (`{ Text, Kind, Duration }`, cap 4 = `MAX_TOASTS`, oldest dropped). `onNotify` parks every toast whose kind is not `"bad"` while any owner holds (the `"pull"` kind is parked as `"pull"`, so it still goes to chat on replay); when the last owner lets go, replay in order through `onNotify`. In `MainMenuController.Open()` call `SetHeld("MainMenu", true)`; at the end of `Play()` call `SetHeld("MainMenu", false)` (both via `H.mod("NotifyController")`, guarded for a missing module). Do NOT key the hold on `UiGate.HasPlayed()`: it is false in every client smoke except this file. `UiGate.ALLOW` is unchanged.
- [ ] **Step 5: Text fixes (win 7).**
  - `UpdateNotes.Credits = { "A SaintsField game", "Created by St.Gavin" }`; rewrite the comment on line 73 (it points at a README checklist that does not exist). `OpenCredits` needs no code change. The gold `Thanks for playing Nimbus Climb!` sign-off under the credits stays (the owner asked only for the Claude line to go); say so in the report.
  - `MainMenuController.lua:553`: the tagline text becomes `tostring(Config.Tagline or "Climb the storm. Together.")`; delete `K.DOT` if nothing else uses it.
  - `LoadingScreen.client.lua:264`: the tagline text becomes `(St.Config and type(St.Config.Tagline) == "string" and St.Config.Tagline) or "Climb the storm. Together."` (`St.Config` can be nil, 519-522; move the lookup after the load if the label is built before it).
  - `LoadingScreen.client.lua:537`: `St.TipIndex = math.random(1, #St.Tips) - 1` (`nextTip()` then shows a random first tip; guard `#St.Tips == 0` as today).
  - `DungeonBuilder.lua:1821` and `DungeonController.lua:1135`: `up to 4 friends` becomes `up to 3 friends`.
  - `BattleService.lua:2672, 2673, 3778`: `F = attack` becomes `F = target` (F switches target, `BattleController.lua:8526`).
- [ ] **Step 6: Run.** `py -3.12 tools/smoke.py --only client_p5menu,client_p5loading,client_p5settings,client_p5menu_mobile,p5menu_spawn,client_p5menu_tiles,client_lock_loading,client_notify,client_notify_pull,p5dgn_world,client_p5dungeon,client_p5dungeon_mobile,p5svc_duel_fair,p5svc_ring,p3bs_duel`. Expected: all pass.
- [ ] **Step 7: Report** (no commit): what changed, the run's tally, and the two notes for the owner (the kept "Thanks" line; `DungeonController` `G.Cross` on the party Kick button uses the same missing U+2715 glyph and was left alone).

---

### Task 2: card-range (win 2)

**Files:**
- Modify: `src/shared/WorldStyle.lua` (`buildTag` 387-394, header doc 43)
- Modify: `src/server/Services/PortalService.lua:95` (`BB.MaxDistance`)
- Modify: `src/server/Services/LobbyBuilder.lua:3157` (stand-in gate tag)
- Modify: `src/server/Services/ArenaBuilder.lua` (`Gates.build` 2756-2772, stand-in 2794, `Gates.buildReturn` 2876-2883)
- Modify: `src/client/UI/PetCard.lua:57` (and the header comments that say 90)
- Modify: `ARCHITECTURE_V3.md` lines 111, 1164, 2445, and for win 7: 2305, 2632
- Test: `tools/smoke_polish_worldtext.lua`, `tools/smoke_polish_portals.lua`, `tools/smoke_p5_world.lua`, `tools/smoke_p4_pets_client.lua`, `tools/smoke_p3_arenaworld.lua`

**Interfaces:**
- Produces: `WorldStyle.TagRange = 45` (studs) and an optional `spec.TagRange` number on `WorldStyle.BuildGate` specs.

**Values:**

| Card | Was | Now |
|---|---|---|
| `GateTag` from `WorldStyle.buildTag` | 120 | `spec.TagRange` if a number, else `WorldStyle.TagRange` (45) |
| `PortalBillboard` (`PortalService BB.MaxDistance`) | 120 | 45 |
| `LobbyBuilder:3157` stand-in `GateTag` | 120 | 45 |
| `ArenaBuilder:2794` stand-in `GateTag` | 120 | `spec.TagRange or 45` |
| Arena `Portal_Return` gate (`Gates.buildReturn`) | 120 | 110, passed as `TagRange = 110` (documented exception) |
| `PetCard` `Follower.MaxDistance` (own follower) | 90 | 15 |

The World text rule stays as it is: pixel-sized BillboardGuis, only the range shrinks. No stud-scaled text, no distance fade.

Unchanged, documented as far-read exceptions in the `WorldStyle` header and `ARCHITECTURE_V3.md:111`: Storm Altar `TitleTag` 150, downed marker 250, tutorial guide sign 4000, battle cards 140, `RaidGateTag` 120, home portal and home tags 120, home nameplates, arena boards (`TAG_RANGE = 110`). `PetCard` `Garden` 90, `Training` 90, `Other` 60 stay.

- [ ] **Step 1: Update the old pins and add the new ones.**
  - `smoke_p5_world.lua` `pixelTagCheck` (134-139): `MaxDistance == WorldStyle.TagRange` and `WorldStyle.TagRange == 45` (was 60..120); add a case in `p5world_style`: a gate built with `TagRange = 110` has a `GateTag` at 110, and a non-number `TagRange` falls back to 45.
  - `smoke_polish_portals.lua` (262-281, 462-463): `60-130` becomes exactly 45 for `PortalBillboard` and `GateTag`.
  - `smoke_polish_worldtext.lua` `auditGui` (227-233): keep the 50-150 rule and add named exceptions next to the `BowlSign` one: `GateTag` / `PortalBillboard` at exactly 45, the own-follower pet card at exactly 15; update the header text (11) and the tally texts (315, 912); in the gate count block (738-749) add "every lobby `GateTag` is at 45".
  - `smoke_p4_pets_client.lua:181`: own follower `MaxDistance == 15` (was 90); header comment 4-9; the 140 and 60 pins (222, 232, 346) stay.
  - `smoke_p3_arenaworld.lua` (517-533): keep the 40-130 audit and add exact pins: `Portal_Return`'s `GateTag` is 110, every other arena `GateTag` is 45.
- [ ] **Step 2: Run and see them fail.** `py -3.12 tools/smoke.py --only p5world_style,p5world_gates,polish_portals,polish_worldtext,client_p4pets_cards,p3arena_world`.
- [ ] **Step 3: Implement the table above.** `Gates.build` forwards `TagRange = spec.TagRange` to `WorldStyle.BuildGate`. Comment the Return exception where it is passed: the forum's lone way home stands about 100 studs from the colosseum's main gate.
- [ ] **Step 4: Docs.** `ARCHITECTURE_V3.md` 111 (gate and portal cards 45, the exception list above), 1164 (own follower 15), 2445 (gate tag 45), 2305 (`up to 3 friends`), 2632 (`{ "A SaintsField game", "Created by St.Gavin" }`); `WorldStyle.lua` header 43; `PetCard.lua` header.
- [ ] **Step 5: Run.** `py -3.12 tools/smoke.py --only polish_worldtext,client_polish_worldtext,polish_portals,client_polish_portals,client_polish_portals_mobile,p5world_style,p5world_gates,p5world_lobby,client_p4pets_cards,client_p4pets_follow,p3arena_world,p3arena_art,arena_return_side,p6gates_server,client_p6gates,storm_altar,p5dgn_world`. Expected: all pass (`p5dgn_world` lives in Task 1's file: regression only).
- [ ] **Step 6: Report** (no commit), with these notes for the owner: other players' follower tags stay at 60; at the default zoom the own follower sits about 8 to 16 studs from the camera, so its tag shows when the camera is close; the Return gate keeps 110 and can drop to 45 by deleting one field.

---

### Task 3: boss-colours (win 3)

**Files:**
- Modify: `src/shared/BossBuilder.lua` (`SetTier` 1624-1648, header doc 27-31)
- Modify: `src/shared/Config.lua:1031`
- Test: `tools/smoke_raid_world.lua` (`raid_world_bosses` 307, tint pins 336-360; `raid_world_sky` 421)

**Interfaces:** `BossBuilder.SetTier(model, tier, opts)` keeps its signature and return values.

- [ ] **Step 1: Rewrite the tint pins in `raid_world_bosses` (336-360), keep the rest.**
  - For every boss the scenario builds and every tier in `BB.TierLooks`: each glow part (`Eye`, `Glow`, `Magma`, `Rune`, and any other key in the rig) has the same Color as on the plain (no-tier) model: `dist(part.Color, plainPart.Color) < 0.001`. This replaces "the glow parts lean toward the tier colour".
  - Keep: "SetEnraged wins while enraged" (colours change under enrage), "SetTier does not take the enrage colours away", "SetTier is idempotent", "SetTier re-dresses (the crown goes)", "SetTier(nil) takes the dressing off", "an unknown tier is refused".
  - Change "the tint comes back after the enrage" to "the sculpt colours come back after the enrage", and "SetTier(nil) takes the tint off" to "SetTier(nil) changes no glow colour".
  - Add: the tier still shows without the tint: at a tier the model has `TierAura` and `TierLight`, and `TierLight.Color == BB.TierLooks[tier].Color`.
  - In `raid_world_sky`: `T.eq(K.config().Sky.Looks.lava_golem.Atmosphere.Haze, 1.2, ...)`.
- [ ] **Step 2: Run and see them fail.** `py -3.12 tools/smoke.py --only raid_world_bosses,raid_world_sky`.
- [ ] **Step 3: Implement.** In `SetTier` the glow loop sets `entry.Color = entry.Rest` for every entry (no `Lerp`), still writing `entry.Part.Color` only when not enraged. `setAura`, `setTierLight`, the crown and the top-card tier text (`BattleController.lua:6746`) are untouched. Update the header doc 27-31: the tier is shown by the aura, the tier light, Max's crown and the name plate; the boss keeps its own colours. `Config.lua:1031`: `Haze = 2.4` becomes `Haze = 1.2` (nothing else on the line).
- [ ] **Step 4: Run.** `py -3.12 tools/smoke.py --only raid_world_bosses,raid_world_sky,client_raid_gate,client_raid_enrage,client_raid_sky,sky_floor,sky_event_blend,skysvc_raid_start_end`. Expected: all pass.
- [ ] **Step 5: Report** (no commit).

---

### Task 4: battle-vitals (win 4)

**Files:**
- Modify: `src/client/Controllers/HudController.lua` (`GetLayout` 2998)
- Modify: `src/client/Controllers/BattleController.lua` (`Hud.Rebuild` 6027-6110, sites 6040, 6107, 7007, 7118, 10348; `CheerUp.Layout` 7318-7332, `CheerUp.Place` 7351-7402, `CheerUp.Update` 7404-7426, `Retreat.Place` 7458-7498)
- Test: `tools/smoke_wave6.lua` (`cheerWhy` 2003-2030, 2066, 2083-2092), `tools/smoke_evo_retreat.lua` (1515-1522, 1756-1761), `tools/smoke_polish_vitals.lua`

**Interfaces:**
- Produces: `HudController.GetLayout().VitalsSlot` = `{ X, Y, W, H }` in pixels, the card's rect whether the card is shown or hidden (nil only when the HUD has no card). `GetLayout().Vitals` keeps today's meaning (nil while hidden).
- Consumes: `HudController.SetVitalsHidden(who: string, on: boolean)` with the owner key `"Battle"`.

**Behaviour:**
- Hidden for a fighter while `isFighting or between` (the same two flags `Hud.Rebuild` already computes); shown again at every site that calls `Hud.SetMenuHidden(false)` (6040, 7007, 7118, 10348). Not gated by `m.Compact`. A spectator keeps the card.
- With the card hidden the buttons move into its slot: Cheer up! is centred on the slot with its bottom edge on the slot's bottom edge. When Retreat is allowed too, the pair is a centred row in the slot (Retreat left, Cheer up! right, `K.CHEER_GAP_PX` between) if the row fits in the slot width plus one gap each side; otherwise Cheer up! stays centred and Retreat stacks above it. Sizes are unchanged (`K.CHEER_W` x `K.CHEER_H`, touch minimums `K.CHEER_TOUCH_W_PX` x `K.CHEER_TOUCH_PX`).
- The existing fallbacks stay as the last resort, computed against the slot rect: the centre-band "beside" move, the screen-edge clamps, Retreat's "stack" and "under" paths.
- The command cluster keep-out (5990, 6006) keeps using the rect `CheerUp.Layout()` returns, so it does not move.

- [ ] **Step 1: Update the old pins and add the new ones.**
  - `smoke_wave6.lua` `cheerWhy`: read `HC.GetLayout().VitalsSlot` instead of `.Vitals`; replace "above the card, 8 px" with "inside the slot: centred on it within `K.CHEER_CENTRE_TOL`, bottom edge on the slot's bottom edge within 2 px"; keep "beside" as the allowed fallback and every on-screen / touch-size / overlap check.
  - `smoke_wave6.lua` (`client_w6_cheer_button`, `client_w6_cheer_mobile`): during the fight `HC.GetLayout().Vitals == nil`, `VitalsSlot` is a rect and `NimbusHud.BottomLeft.Vitals.Visible == false`; after the result, after a leave and after cleanup `Vitals.Visible == true`; with `HC.SetVitalsHidden("Daily", true)` set before the fight, the card is still hidden after the fight ends (the battle does not release another owner), then release "Daily" and it shows; a spectator's card stays visible.
  - `smoke_evo_retreat.lua`: Retreat and Cheer up! are both in the slot or the stacked fallback, do not overlap each other, `Hud.team` or the middle band, are on screen and at least 44 px on touch.
  - `smoke_polish_vitals.lua`: `GetLayout().VitalsSlot` equals `GetLayout().Vitals` while the card is shown, and stays the same rect after `SetVitalsHidden("X", true)`.
- [ ] **Step 2: Run and see them fail.** `py -3.12 tools/smoke.py --only client_w6_cheer_button,client_w6_cheer_mobile,client_evo_retreat,client_polish_vitals`.
- [ ] **Step 3: Implement `VitalsSlot`** in `HudController.GetLayout()`: `(vitalsRect and UI.Vitals) and { X, Y, W, H } or nil`.
- [ ] **Step 4: Implement the hide.** Add `Hud.SetVitalsHidden(on)` in `BattleController` (calls `Mods.HudCtl.SetVitalsHidden("Battle", on == true)`, guarded for a missing module). In `Hud.Rebuild` call it with `(isFighting or between)` before `CheerUp.Place`; call it with `false` at 6040, 7007, 7118, 10348. Only a fighter (`B.Fighter`) ever turns it on.
- [ ] **Step 5: Implement the placement.** `CheerUp.Layout()` returns `layout.Vitals or layout.VitalsSlot` plus a second value `hidden` (`layout.Vitals == nil and layout.VitalsSlot ~= nil`). `CheerUp.Place` and `Retreat.Place` follow the Behaviour block when `hidden`; when not hidden they behave exactly as today. `CheerUp.placed` (the re-place key) also carries the hidden flag and whether Retreat is allowed, so `CheerUp.Update` re-places on a change.
- [ ] **Step 6: Run.** `py -3.12 tools/smoke.py --only client_w6_cheer_button,client_w6_cheer_mobile,client_w6_podium_cheer,client_evo_retreat,client_evo_retreat_mobile,client_p5hud_fighter,client_p5hud_enemies,client_p5input,client_p5battle_mobile,client_p5battle_landscape,client_p4fix_leave,client_p4fix_leave_mobile,client_bb6_raid_leave,client_bb6_raid_leave_mobile,client_p3fixcli_retreat,client_p3fixcli_landscape,client_p3fixcli_mobile,client_evo_keys,client_evo_buttons_mobile,client_polish_vitals,client_polish_vitals_mobile,client_hudpill,client_hudpill_mobile,client_hud,client_final,client_mobile,client_daily_ui_a`. Expected: all pass. If an old "keep clear of the vitals card / the HP bar" pin in one of the task's conditional smoke files fails because the card is now hidden in a fight, update that pin to skip a hidden card (never delete it). `client_daily_ui_a` is Task 5's file: regression only.
- [ ] **Step 7: Report** (no commit).

---

### Task 5: windows-close (wins 5 and 6)

**Files:**
- Modify: `src/client/UI/NeonKit.lua` (new `CloseMark`; `Glyphs.Close` 95)
- Modify: `src/client/UI/CloudUI.lua:729` (Panel close)
- Modify: `src/client/Controllers/ShopController.lua` (`CLOSE_GLYPH` 173, close 641-642)
- Modify: `src/client/Controllers/DailyController.lua` (win 5: `H.shopUp` 716-723, `H.layoutButton` 725-732, Init hooks 2008-2018; win 6: close 908)
- Modify: `src/client/UI/PetPicker.lua:468`, `src/client/Controllers/FusionController.lua:979`, `src/client/Controllers/TrainController.lua:748`, `src/client/Controllers/TroveController.lua:258-266`, `src/client/Controllers/LossScreen.lua:428`, `src/client/Controllers/PetsController.lua:938-942` (`SheetClose`)
- Test: `tools/smoke_client_v2.lua:258` (`client_ui_kit`), `tools/smoke_daily_ui.lua` (`client_daily_window`), `tools/smoke_shop_ui.lua` (`client_shop_window`, `G.giftsCheck` 509-533)

**Interfaces:**
- Produces: `NeonKit.CloseMark(button: GuiButton, opts: { Color: Color3?, Ink: Color3?, Scale: number?, ZIndex: number? }?) -> Frame`. It clears the button's text (its own `Text` and any label child the kit made), then adds a non-interactive square Frame `CloseMark` centred in the button (`AnchorPoint` 0.5, 0.5; scale-sized, default `Scale = 0.6` of the button with a 1:1 aspect constraint, so it follows resizes) holding two white rounded bars `BarA` (`Rotation = 45`) and `BarB` (`Rotation = -45`), each over a slightly larger dark bar (`InkA`, `InkB`) for contrast. No font glyph, no image, no per-bar `UIStroke`. Calling it twice returns the existing mark.
- Produces (DailyController, internal): `K.WINDOWS` (list of controller names), `K.WINDOW_POLL = 0.25`, `H.windowUp() -> boolean`.

- [ ] **Step 1: Add the failing pins.**
  - `smoke_client_v2.lua:258`: replace `x.Text == "X"` with: the closable panel's `Close` is a red TextButton with empty text, a `CloseMark` Frame, `BarA.Rotation == 45`, `BarB.Rotation == -45`, both bars visible; the mark's centre is the button's centre within 1 px; after resizing the button the mark is still centred and still inside the button; no descendant of the button has text containing `X`, U+2715 or U+00D7. The existing click-closes pin stays.
  - `smoke_shop_ui.lua` (`client_shop_window`) and `smoke_daily_ui.lua` (`client_daily_window`): the same mark check on each window's `CloseButton`, plus its tap size is still at least 44 px.
  - `smoke_daily_ui.lua` (`client_daily_window`), win 5: with a window other than the Shop open (the menu's Pets window, then a second kind such as the Index), the Gifts button, its ring and its pip are not shown; within 0.4 s of that window closing (close it once through its own close button and once through `MenuController` opening and closing another id) they are back; opening the Daily window itself keeps the button shown (the own-window pin at 374 stays).
  - `G.giftsCheck` in `smoke_shop_ui.lua` stays as it is and must still pass.
- [ ] **Step 2: Run and see them fail.** `py -3.12 tools/smoke.py --only client_ui_kit,client_shop_window,client_daily_window`.
- [ ] **Step 3: Implement `NeonKit.CloseMark`** per the Interfaces block. The mark and bars are plain Frames with `Active = false`, so taps reach the button; do not put the mark under a clipping parent (rotated children do not clip).
- [ ] **Step 4: Use it at all nine sites.** `CloudUI` Panel close (covers every `Closable = true` window), Shop, Daily, PetPicker, Fusion, Train, Trove, LossScreen, Pets `SheetClose`. Button names, sizes, colours, positions and callbacks are unchanged; only the text goes. Remove `CLOSE_GLYPH`, the per-file `G.Close` entries and `NeonKit.Glyphs.Close` where nothing else reads them. Leave `PetsController.lua:1023` `PickCancel` (U+00D7 chip, a real glyph, not a window close).
- [ ] **Step 5: Gifts button (win 5).** In `DailyController` replace `H.shopUp()` with `H.windowUp()`: true when any controller in `K.WINDOWS` answers `IsOpen() == true` (each call in `pcall`, through the existing `controller(name)` lookup, 309). Start from `{ "MenuController", "PetsController", "ShopController", "StoreController", "TroveController", "IndexController", "FusionController", "CareController", "TrainController", "DungeonController", "ObbyController", "RaidGateController", "ArenaController", "LossScreen" }`; read each `IsOpen` and drop any that is true during ordinary play with no window up (that would hide the button for good). Never include `DailyController` itself, `NpcController`, `DevController` or `MainMenuController`. `S.Hidden = left <= 0 or hiddenByPlay() or H.windowUp()` (732). Re-layout on: the existing `MenuController.WindowOpened` handler for ids other than `"Daily"` (`task.defer`), the existing `ShopController.Toggled` hook, and a `K.WINDOW_POLL` watcher that calls `H.layoutButton()` only when `H.windowUp()` changes (no shared close signal exists). Update the comment at 715.
- [ ] **Step 6: Run.** `py -3.12 tools/smoke.py --only client_ui_kit,client_menu,client_pets,client_daily_window,client_daily_pip,client_daily_mobile,client_daily_ui_a,client_daily_layouts,client_daily_portrait,client_fixr_daily_phone,client_fixr_menu_cover,client_shop_window,client_shop_sizes,client_shop_mobile,client_shop_portrait,client_shop_openers,client_picker_ui,client_picker_layouts,client_fusion_ui_a,client_fusion_layouts,client_train_ui,client_train_layouts,client_tb_loss_screen,client_tb_loss_phone,client_store_window,client_trove,client_trove_mobile`. Expected: all pass. A pin in one of the task's conditional smoke files that reads the old close text (`"X"` or the glyph) is updated to the mark check, never deleted.
- [ ] **Step 7: Report** (no commit).

---

## Left alone on purpose (tell the owner)

- `DungeonController` `G.Cross` (U+2715) on the party Kick button and the "left" member mark: the same missing glyph, but not a window close, and the file belongs to Task 1. A follow-up can reuse `NeonKit.CloseMark`.
- `PetsController` `PickCancel` chip (U+00D7 renders).
- Other players' follower tags (60), garden and training pet cards (90), `RaidGateTag` (120, pinned), home portal and home tags (120).
- The gold "Thanks for playing Nimbus Climb!" line under the credits.

## Self-review

- Coverage: win 1 and 7 in Task 1 (ARCHITECTURE lines for win 7 in Task 2), win 2 in Task 2, win 3 in Task 3, win 4 in Task 4, wins 5 and 6 in Task 5.
- Names match across tasks: `NotifyController.SetHeld` / `IsHeld`, `WorldStyle.TagRange` / `spec.TagRange`, `GetLayout().VitalsSlot`, owner key `"Battle"`, `NeonKit.CloseMark`, `H.windowUp` / `K.WINDOWS` / `K.WINDOW_POLL`.
- No file is in two tasks (table above). Every Review Focus line has its pin in the owning task's Step 1.
- Line numbers were read on the `quick-wins` branch on 2026-11-12; if a line moved, find it by the quoted text.
