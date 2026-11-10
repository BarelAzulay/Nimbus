# Battle Feel Implementation Plan (centre aim, melee dash + standoff, weighty specials with a real cast)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Also name and use superpowers:test-driven-development (every task writes its failing scenario first), superpowers:verification-before-completion (run the commands, read the counts, LOOK at the Studio screenshots before any "done"), **roblox-dev:roblox-architecture** (the aim, dash and beat rules live in the modules that own them: `AttackFx` draws, `AttackFxCatalog` authors beats, `PetPoses` is pure body math, `BattleSim` owns reach / cast / damage; one shared `Config.Battle.Feel` read by both sides; no new remote), **roblox-dev:roblox-performance** (no per-frame allocation: segment tables once per attack, the aim offset cached per model, one raycast per effect, pooled Trail kits capped at 4, nothing new on Low) and **roblox-dev:roblox-ui** (TweenService-free poses on the render clock, the hit freeze, the callout life, the streak transparency).

**Goal:** Melee pets rest 8 studs out and dash in, bite and hop back on every attack; every shot, beam and special lands in the target's body centre with its ground layers on the real floor; specials charge, fly and linger 1.4x longer with a real server cast time behind them, so the numbers land when the show lands.

**Architecture:** T1 is drawing only: `AttackFx` gains `aimOf` / `BitePoint` / `FloorY` and nothing on the wire moves. T2 is a pose pair in `PetPoses`, a `Dash` scheduler in `AttackFx` driven by `BattleController` from `Windup` (NPC) or `Hit` (the fighter, held 0.3 s by today's `fxLate` path), plus one server number `Damage.Standoff` that moves the rest spot and the attack tests together. T3 is `AttackFxCatalog` beats for specials, the hit freeze and callout, and the server cast: `castSpecial` split into `beginCast` / `fireCast` on the existing delayed-hit queue, three wire additions (`Cast`, `Special.at`, `CastBreak`), the client charging for every unit from `Cast` and handing over at `Special`.

**Tech Stack:** Luau in plain Lua 5.1 syntax (Rojo), the mock harness `py -3.12 tools/smoke.py --quick --only a,b,c` (lupa), `SIM_BATTLE=full py -3.12 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"` from the repo root, `node tools/check.mjs`, `py -3.12 tools/count_locals.py`, Roblox Studio for the owner's three checks at the end (the main session, never a second Studio window).

**Spec:** `docs/superpowers/specs/2026-11-10-battle-feel-design.md` (every number below comes from it). The pitch: `.superpowers/battle-feel/pitch/page.html`; the ledger: `.superpowers/battle-feel/LEDGER.md`.

## How every task runs

- Worktree `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\battle-feel\nimbus-climb`, branch `battle-feel` (frost-wyrm 38cadc6). In PowerShell `Set-Location -LiteralPath "<worktree>"` first (Hebrew path), then relative paths. Read `ABSOLUTE_RULES.md` and `brain.md`, then the spec whole. `tools\node_modules` exists (installed 2026-11-10); if missing run `npm install` in `tools` once.
- Route (`py -3.12 tools/pick_model.py --build game-feature`): plan Fable 5.1 high (this file), **build Opus 5.5 high**, review Fable 5.1 xhigh (T2 and T3 reviewed with roblox-dev:roblox-security for Y2: nothing on the client changes reach or damage), fix Opus 5.5 high, gate Fable 5.1 high.
- Tests first: write the failing scenario, run it RED, build, run it GREEN, then the regression lists named in the task, one `--only` list at a time. A test the change breaks is rewritten to the new rule in the same task (never deleted); the commit body names each rewritten assertion and why.
- **Another build may run smoke on this PC.** Before any run: `Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty FreePhysicalMemory` (KB) and `(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*smoke.py*' }).Count`. The WHOLE suite only with >= 4 GB free AND 0 other smoke processes; otherwise the broad targeted lists in the gate, and say so in the ledger.
- Before each commit: `node tools/check.mjs` -> 0 errors; `py -3.12 tools/count_locals.py src/client/Controllers/AttackFx.lua src/client/Controllers/BattleController.lua src/shared/BattleSim.lua src/shared/PetPoses.lua src/shared/AttackFxCatalog.lua` -> none at 200 (today 125 / 148 / 164 / 35 / 50; BattleSim gains at most 6 locals, group new helpers in one table if it nears 190).
- Staging by name (`git add <path>...`), never `-A` / `.`. Commit with `git commit -F "<scratchpad>\msgN.txt"` (UTF-8, no BOM), every message ending with exactly these two lines, then `git push origin battle-feel`:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01ACtM8qc8ts2NyGHrZh7vyT`
- After each push append one dated line under `## build` in `.superpowers/battle-feel/LEDGER.md` (hash, what landed, the lists that passed with their check counts, open calls for the morning).
- Sleep mode: no merges into main / lobby-shop / integration, no uploads, no deleting folders, no force-push, never print API keys, no new Studio window.

## Global Constraints

- Y2: the server owns reach, hits and damage; a dashing pet's real position is its rest spot; the client's aim, dash and beats never change what is hit.
- `Config.Battle.Feel` exactly as the spec's "The knob" block; the server reads only `Melee.Standoff` and `Special.RealCast` / `Cast` through `BattleCatalog.Damage.Standoff` / `BattleCatalog.Damage.SpecialCast`.
- Off switches restore today exactly: `Melee.Dash = false`, `Melee.Standoff = 0`, `Aim.Mode = "Pivot"` (the floor fix stays), `Special.Weighty = false`, `Special.RealCast = false`.
- `sim_battle.lua` targets: none loosened; a raid cell over 240 s = a `HpTier` nudge on purpose, logged, listed for the morning.
- Low graphics: no streak, no afterglow (0), the beats and the freeze stay. Phones: nothing new per frame; no new Instance per frame; the dash streak <= `StreakMax` 4 live trails.
- Event fields are numbers rounded with `r1` as today; `BattleSim.Events` gains `Cast` and `CastBreak`; the wire format test (`p5sim_wire` / `evo_wire`) is extended, never loosened.
- Sources ASCII; plain Lua 5.1 syntax; no model changes (Blender-only rule untouched: nothing to build).
- Every existing scenario stays green or is rewritten to the new rule in the same task.

## Review Focus

1. A boss model (pivot at the feet, no `AimPoint`) must aim at its bounding-box centre; a pet (pivot = centre) must aim within 0.2 studs of today -> `client_feel_aim_centre` + `client_feel_aim_pets` (Task 1).
2. A target model destroyed or parked mid-effect: `aimOf` falls back to the last known point, no error, the effect ends -> `client_feel_aim_centre` step "target gone" (Task 1).
3. A `Windup` whose hit never comes (the victim dodged or was KO'd first): the dash still bites and returns; no unit is left held "in" -> `client_feel_dash_npc` step "no hit" (Task 2).
4. Eight units dashing in one frame: at most 4 trails, `Stats()` shows no kit over the pool keep, no new Instance between two Updates -> `client_feel_dash_budget` (Task 2).
5. A caster KO'd or stunned mid-cast: the entry drops, no Hit events, the meter stays, `CastBreak` on a stun; the client shatters the charge -> `feel_cast_break` + `client_feel_tempo_cast` step "break" (Task 3).
6. A recording without `Cast` / `at` (an old client replay) plays exactly today's `LATE_MAX` path -> `client_feel_tempo_cast` step "old events" (Task 3).

## File map

| File | Task | Change |
|---|---|---|
| `src/shared/Config.lua` 535-540 | 1 | `Config.Battle.Feel` (the whole block; later tasks read it) |
| `src/client/Controllers/AttackFx.lua` 164-199 (K), 653-674, 745-787, 3343-3352, 3716-3738 | 1 | `K.AIM_MIN`, `K.FLOOR_RAY`, `aimCache`, `aimOf`, `BitePoint`, `eff.FloorY`, `groundOf` |
| `tools/smoke_feel_aim.lua` (new), `tools/smoke.py` after line 536, `tools/README.md` smoke table | 1 | `client_feel_aim_*` |
| `src/shared/PetPoses.lua` 9-11, 64-66, 344+ | 2 | `DashIn`, `DashBack`, `PetPoses.DASH_RUN`, `Holds.DashIn` |
| `src/client/Controllers/AttackFx.lua` 3063-3124, 3984-4026, new `AttackFx.Dash` / `DashState` | 2 | the dash scheduler, `Forward`, the streak |
| `src/client/Controllers/BattleController.lua` 245-330 (K), 1817-1824, 3466-3497, 3935-4004, 4868-4874 | 2 | `K.DASH_*`, the tempo, `Atk.Dash`, `Forward` applied, the `Windup` handler |
| `src/shared/BattleCatalog.lua` 238-239, 2640+ (Validate) | 2, 3 | `Damage.Standoff`, `Damage.SpecialCast` from Config; Validate |
| `src/shared/BattleSim.lua` 186, 311, 3465, 3506-3537, 3607, 3673, 3814, 4515 | 2 | `standoffOf`, the seven reach spots |
| `tools/smoke_feel_dash.lua` (new), `tools/smoke.py`, `tools/smoke_p7vfx.lua` 1516, `tools/smoke_fight.lua` (the `reach - 0.5` pins) | 2 | `feel_standoff_*`, `client_feel_dash_*`; rewritten pins |
| `src/shared/AttackFxCatalog.lua` 200, 649-663, 2041-2071, 2182 | 3 | the Special beats from the knob |
| `src/client/Controllers/AttackFx.lua` 152, 3090, 3106, 3117-3122, 3427-3447 | 3 | `SPECIAL_HIT_STOP`, the Cast / Hurt freeze, `fitTimes` travel give-back |
| `src/shared/BattleSim.lua` 186-187, 2262-2355, 2378-2437 (+ the kind branches to its end), 3448-3456, 3599, 3781-3784 | 3 | `beginCast` / `fireCast`, `cancelCast`, the events |
| `src/client/Controllers/BattleController.lua` 275-276, 3580-3660, 3859-3881, 4481-4491, new `Handlers[EV.Cast]` / `[EV.CastBreak]`, `Atk.Update` | 3 | `B.casts`, the hand-over, `K.SPECIAL_CALLOUT`, `K.CAST_WAIT` |
| `tools/smoke_feel_tempo.lua` (new), `tools/smoke.py`, `tools/smoke_afx_reach.lua` 116-123, `tools/smoke_evo_sim.lua`, `tools/smoke_p5_battlecore.lua`, `tools/smoke_bug2_battle.lua`, `tools/smoke_dgfix_core.lua` (specials read at the cast), `tools/smoke_p7vfx_client.lua` (`client_p7vfx_precharge`) | 3 | `feel_cast_*`, `client_feel_tempo_*`; rewritten steps |
| `brain.md`, `README.md` (the battle section: one line each) | 3 | the dated decision line |

---

### Task 1: Centre aim and the real floor (drawing only)

Spec: decision 4, "What each side does / Client / Aim", "Pets unchanged".

**Files:**
- Modify: `src/shared/Config.lua:535-540` (add `Feel` to `Config.Battle`, the spec's block verbatim)
- Modify: `src/client/Controllers/AttackFx.lua:164-199` (K), `:653-674` (`pointOf`, `groundOf`), `:745-787` (`hitOf`, `refresh`), `:3343-3352` (`sideOf`), `:3716-3738` (`Play`: `FloorY`)
- Create: `tools/smoke_feel_aim.lua`; Modify: `tools/smoke.py` (after line 536), `tools/README.md` (the smoke table: one row)

**Interfaces:**
- Consumes: `AttackFx.Play(ctx)` with `ctx.Ground` (the caster's floor Y, `BattleController.groundOf`), `ctx.To` sides `{ Unit, Model, Pos }`.
- Produces: `local function aimOf(side) -> Vector3` (the body centre), `AttackFx.BitePoint(src, tgt) -> Vector3 | nil` (the near edge on the flat line at `src.Last.Y`; nil without both points), `AttackFx.AimOf(side) -> Vector3` (public, the same as `aimOf`, for tests), `eff.FloorY` (number), `AttackFx.FLOOR_RAY_MAX = 6` (studs a raycast may differ from `ctx.Ground`), `K.AIM_MIN = 1.0`. `Config.Battle.Feel` for every later task.

- [ ] **Step 1: Write the failing scenarios in `tools/smoke_feel_aim.lua` (client world; the fake clock and fake MeshLibrary of `smoke_p7vfx_client.lua`'s `client_p7vfx_engine`; a BossBuilder voxel boss built in the test world as `smoke_raid_client.lua` does)**

```lua
-- client_feel_aim_centre: a Ranged Flame effect From a pet model To a built Boss_lava_golem (Root at the feet, Height H):
T.check(near(AF.AimOf(side).Y, bossCentreY, 0.5), "feel aim: a boss aims at its bounding-box centre (feet root ignored)")
T.check(near(eff.Hit.Y, bossCentreY, 0.5) and near(eff.Hit.X, bossX, 0.5), "feel aim: the shot's Hit is the body centre")
-- with an Attachment named AimPoint at (0, 9, 0) in Body:
T.check(near(AF.AimOf(side).Y, bossFeetY + 9, 0.1), "feel aim: an AimPoint attachment wins over the box")
-- Config.Battle.Feel.Aim.Mode = "Pivot" (restored after): AimOf == the pivot
-- "target gone": boss model destroyed mid-travel: AF.Update runs with no error, eff.T[1] == the last known point, the effect ends by its End
-- client_feel_aim_floor: the Ranged BoomRing (At = "Ground") and a Blast Blastwave on that boss: the ring's Y within 0.1 of ctx.Ground + 0.05
-- (today: ctx.Ground - 1.55); a Freeze cage (Path Ground) stands on ctx.Ground; FloorRay = false gives the same with no Raycast call
-- (the mock counts workspace.Raycast); FloorRay = true makes exactly one Raycast per Play, none per Update
-- client_feel_aim_pets: a Melee and a Ranged effect pet -> pet (PetBuilder models): eff.Hit within 0.2 of today's pivot aim
-- (record the pivot before the change: tgt:GetPivot().Position), the Melee Strike's Reach equals AF.LeapReach as today
-- client_feel_aim_bite: a Melee effect pet -> boss: eff.Hit == AF.BitePoint: its Y == the caster's centre Y, its flat distance to the
-- boss pivot == the boss's half-width along the line (spanAlong), its distance to the caster < the pivot distance
```

- [ ] **Step 2: Register and run RED**

`tools/smoke.py` after line 536: `if p5("smoke_feel_aim.lua"): client_files.append("smoke_feel_aim.lua"); ins(client_scenarios, "client_final", ["client_feel_aim_centre", "client_feel_aim_floor", "client_feel_aim_pets", "client_feel_aim_bite"])  # [battle-feel, T1] ...`
Run: `py -3.12 tools/smoke.py --quick --only client_feel_aim_centre,client_feel_aim_floor,client_feel_aim_pets,client_feel_aim_bite`
Expected: FAIL on the centre / floor / bite checks (today aims at the pivot, rings at Ground - Drop).

- [ ] **Step 3: `Config.Battle.Feel` in `src/shared/Config.lua:535-540`**

The spec's block verbatim, with one comment line naming the spec and "the owner can change any of these".

- [ ] **Step 4: `aimOf` + the cache in `AttackFx.lua`**

In K: `AIM_MIN = 1.0`, `FLOOR_RAY = 80` (ray length), `FLOOR_RAY_MAX = 6`. `St.aimCache = setmetatable({}, { __mode = "k" })` keyed by model -> `{ Att = Attachment | false, Off = Vector3 }`, filled once in `sideOf` (and when `side.Model` changes): `Att = model:FindFirstChild("AimPoint", true) or false`; `Off`: `GetBoundingBox` once, `cf:PointToObjectSpace(boxCentre)` relative to the pivot CFrame when its magnitude > `K.AIM_MIN`, else `Vector3.zero`. `aimOf(side)`: `Config.Battle.Feel.Aim.Mode ~= "Centre"` -> `pointOf(side)`; else `Att.WorldPosition` when `Att` and `Att.Parent`; else `pivotCF:PointToWorldSpace(Off)` when the model is in the game (reads the pivot through the same pcall as `pointOf`, stores `side.Last`); else `pointOf(side)`. `AttackFx.AimOf = aimOf`.

- [ ] **Step 5: `BitePoint`, `refresh`, `FloorY`, `groundOf`**

`AttackFx.BitePoint(src, tgt)`: `flat(tgt.Last - src.Last)` -> unit `u`; `spanAlong(tgt.Model, src.Last, u)` -> `t0, th`; the point `src.Last + u * ((t0 or dist) - (th or 0))` with `Y = src.Last.Y`; nil without both `Last`. In `refresh`: `eff.T[i] = eff.Bite and (AttackFx.BitePoint(eff.Src, side) or aimOf(side)) or aimOf(side)` where `eff.Bite = (r.Attack == "Melee") or (r.Attack == "Special" and r.Kind == "Pounce")` is set in `Play` (the leap's `LeapReach` keeps using `Last`). In `Play` after `drop`: `eff.FloorY = finite(ctx.Ground) and ctx.Ground or (src.Last.Y - drop)`; when `Config.Battle.Feel.Aim.FloorRay` and a target exists: one `workspace:Raycast(aim + UP * 1, DOWN * K.FLOOR_RAY, params)` with `params.FilterType = Enum.RaycastFilterType.Exclude`, `FilterDescendantsInstances = { St.folder, workspace:FindFirstChild("ClientBattle") }` (both when present), pcall'd; accept `hit.Position.Y` when `abs(hit.Position.Y - eff.FloorY) <= K.FLOOR_RAY_MAX`. `groundOf(eff, p)` -> `V3(p.X, eff.FloorY + 0.05, p.Z)`. `eff.Drop` stays for `Above` / `Behind` offsets.

- [ ] **Step 6: Run GREEN, then the regression lists**

Run: the Step 2 command -> all 4 pass (note the check count).
Then: `py -3.12 tools/smoke.py --quick --only client_p7vfx_engine,client_p7vfx_battle,client_p7vfx_storm,client_afx_reach_draw,client_afx_impact_engine,client_afx_linger,client_afx_tails,client_afx_zone_tail,client_evo_forms,client_evo_beams,client_evo_twists,client_raid_enrage` -> pass; a ring-height assertion that pinned `Ground - Drop` is rewritten to `ctx.Ground + 0.05` (name it in the commit body).
`node tools/check.mjs` -> 0 errors.

- [ ] **Step 7: Commit + push + ledger**

```bash
git add src/shared/Config.lua src/client/Controllers/AttackFx.lua tools/smoke_feel_aim.lua tools/smoke.py tools/README.md
git commit -F "<scratchpad>\msg1.txt"   # feat(battle-feel): centre aim + the real floor (Config.Battle.Feel, AttackFx aimOf / BitePoint / FloorY)
git push origin battle-feel
```

---

### Task 2: Melee dash, standoff and the flurry

Spec: decisions 1-3, "Rules that hold / Y2", "Phones and Low graphics", "What each side does / Server / Standoff" and "/ Client / Dash".

**Files:**
- Modify: `src/shared/PetPoses.lua:9-11, 64-66` (Names / Holds), `:344+` (`Sample`: two poses)
- Modify: `src/client/Controllers/AttackFx.lua:3063-3124` (`schedulePoses`), `:3984-4026` (`Pose`), new `AttackFx.Dash`, `AttackFx.DashState`
- Modify: `src/client/Controllers/BattleController.lua:245-330` (K), `:1817-1824`, `:3466-3497` (`hitPlay`), `:3935-4004` (`Atk.PoseOf`), `:4868-4874` (`Handlers[Windup]`)
- Modify: `src/shared/BattleCatalog.lua:238` (`Damage.Standoff` after `CastSeconds`), Validate (`Standoff` a number 0..20)
- Modify: `src/shared/BattleSim.lua:311` (the fallback `Standoff = 0`), `:3465`, `:3506-3537`, `:3607`, `:3673`, `:3814`, `:4515`
- Create: `tools/smoke_feel_dash.lua`; Modify: `tools/smoke.py`, `tools/smoke_p7vfx.lua:1516` (Names), `tools/smoke_fight.lua` (every `reach - 0.5` pin), `tools/README.md`

**Interfaces:**
- Consumes: `AttackFx.LeapReach(src, tgt)` (pose studs), `AttackFx.HIT_STOP`, `setPoses(unit, segs, now)`, `poseSample`, `Config.Battle.Feel.Melee`, `BattleController.Atk.Side`, `lookCtx`, `Fx` unchanged.
- Produces:
  - `PetPoses.Sample("DashIn", p, false, amp, reach)`: body `-Z` from 0 to `reach` over p 0..`PetPoses.DASH_RUN` (0.78, `smooth` easing), a hop of `Config.Battle.Feel.Melee.Hop` 0.5 studs over the last quarter of the run (p 0.585..0.78, `sin`), then at `reach` a squash 0.25 and chin down 12 deg (p 0.78..1), wings snap open 35 at p 0.78; `Holds.DashIn = true` (p = 1 is the edge). `Sample("DashBack", p, false, amp, reach)`: body from `-Z reach` (p 0) back to 0 (p 1, `smooth`), a `sin` arc 1.0 stud high, chin up at the top, landing squash 0.15 at p 0.9, settles at rest at p 1. `PetPoses.Names` = today's nine + `"DashIn", "DashBack"` (appended).
  - `AttackFx.Dash(unit, src, tgt, landAt, now, opts) -> boolean` (`opts = { Mine, Low, Tempo }`): schedules the dash so the run ends at `landAt` (`StopAt = landAt, StopDur = HIT_STOP`); `DashBack` at `landAt + Bite + Hold` when `Tempo == nil or Tempo >= FlurryBelow`, else at `landAt + FlurryBelow`; a request while `DashState == "in"` schedules a `Strike` with `Reach = Lunge` 0.6 at `landAt` on top of `Forward` and re-times `DashBack`; while `"back"` the current offset becomes `Forward` and a `DashIn` runs the rest; returns false (no dash, today's Strike) when the world gap from `LeapReach` is under `MinGap` 3 or `Melee.Dash` is false. Takes one pooled Trail kit (`fx_speedlines`, Lifetime 0.12, white, Transparency 0.3 mine / 0.6 others) for the run when `Streak` and not Low and fewer than `StreakMax` streaks live (mine first: a non-mine request at the cap gets none).
  - `AttackFx.DashState(unit) -> "out" | "in" | "back"`; `AttackFx.Pose(unit, base)` returns `out.Forward` (pose studs; 0 when none).
  - `BattleController`: `K.DASH_SEEN = 0.6` (a melee Hit within this of the unit's last `Windup` is dashed already), `u.atkAt`, `u.tempo` (the gap between the last two attack starts), `Atk.Dash(B, a, v, dueAt)`.
  - `BattleSim`: `local function standoffOf(D, u) -> number` (`D.Standoff` for a melee unit, 0 when `u.ranged` or `u.kind == "Boss"`).

- [ ] **Step 1: Write the failing scenarios in `tools/smoke_feel_dash.lua` (server half pure; client half as `client_p7vfx_battle`'s replayed Duel / Raid with a real BattleSim fed through BattleState)**

```lua
-- feel_standoff_rest (server, pure): a Duel, my Legendary melee fighter (Auto team) vs one standing bear, moveSpeed 0 on the bear:
-- after 6 s the fighter rests at dist == reach + 8 - 0.5 (+- 0.3); with Config.Battle.Feel.Melee.Standoff = 0 (BC.Damage.Standoff
-- patched, restored after) at reach - 0.5. An NPC melee pet vs my standing fighter: the same two numbers. A ranged pet: reach - 0.3 both times.
-- feel_standoff_dps (server, pure): seed 11, 30 s, the same fight at Standoff 8 and 0: the number of Hit events of the melee pet differs
-- by at most 1 and the first hit lands no later than at 0 (the walk is shorter); every Hit's `at` is within reach + 8 + EngageSlack + 1.0.
-- feel_standoff_zone (server, pure): a 44 x 44 Ring, three NPC melee pets vs my fighter at the centre: every rest spot inside the zone,
-- at least 2.4 studs apart (SeparationRadius), all three attacking by 8 s.
-- feel_standoff_wire: BC.Validate() true; Standoff = -1 / "x" / 25 -> Validate false; BS.Events unchanged by this task.
-- client_feel_dash_npc (client): a replayed Raid: on an enemy melee pet's Windup { at } the unit's pose is DashIn before the hit, its Forward
-- == LeapReach at ev.at on the render clock (+- one frame), the Hit's effect plays with NO Strike segment, Hurt on the victim at the impact,
-- DashBack starts at landAt + 0.20 and the unit is "out" by landAt + 0.60; "no hit": a Windup with no Hit after it: the same, no error,
-- DashState "out" by landAt + 0.6.
-- client_feel_dash_mine (client): my melee fighter's Hit (no Windup): ev.fxLate == 0.30, the number and the HP drop play 0.30 later,
-- the dash lands at dueAt + 0.30, the effect's impact there; Melee.Dash = false -> no DashIn, today's Strike, fxLate 0.
-- client_feel_dash_flurry (client): Hits 0.64 s apart (a Storm pet with Charge): after the second the unit stays "in" (Strike with
-- Reach 0.6 on Forward == LeapReach), DashBack only 0.75 s after the last attack start; Hits 1.1 s apart: a full round trip each time.
-- client_feel_dash_off (client): a gap under MinGap 3 (a pet already at the edge): Dash returns false, today's Strike; Low graphics:
-- DashIn runs, no Trail kit taken.
-- client_feel_dash_budget (client): eight enemy melee pets' Windups in one batch at High: exactly 4 Trail kits live (mine first when my
-- pet is among them), AF.Stats() pools at keep size after they end, the workspace descendant count equal between two Updates mid-dash.
-- p7vfx_poses (rewritten in smoke_p7vfx.lua:1516): Names = the nine + DashIn, DashBack; DashIn holds (p 1 == the edge, body.Z == -reach),
-- DashBack at rest at p 1; both finite at every p; DashIn's hop peaks between p 0.585 and 0.78.
```

- [ ] **Step 2: Register and run RED**

`tools/smoke.py`: `if p5("smoke_feel_dash.lua"): server_files.append("smoke_feel_dash.lua"); client_files.append("smoke_feel_dash.lua"); names = ["feel_standoff_rest", "feel_standoff_dps", "feel_standoff_zone", "feel_standoff_wire"]; pure_scenarios += names; ins(server_scenarios, "p5stats_formula", names); ins(client_scenarios, "client_final", ["client_feel_dash_npc", "client_feel_dash_mine", "client_feel_dash_flurry", "client_feel_dash_off", "client_feel_dash_budget"])  # [battle-feel, T2] ...`
Run: `py -3.12 tools/smoke.py --quick --only feel_standoff_rest,feel_standoff_dps,feel_standoff_zone,feel_standoff_wire,client_feel_dash_npc,client_feel_dash_mine,client_feel_dash_flurry,client_feel_dash_off,client_feel_dash_budget,p7vfx_poses`
Expected: FAIL (rest at reach - 0.5, no DashIn pose, no fxLate on a melee hit).

- [ ] **Step 3: The server standoff**

`BattleCatalog.Damage.Standoff = Config.Battle.Feel.Melee.Standoff` (line 238, with its comment); Validate: a number in 0..20. `BattleSim`: the fallback table at 311 gains `Standoff = 0`; `standoffOf(D, u)`; apply `so` at: 3465 (`reach + so + EngageSlack + 1.0`), 3506-3529 (`reach = u.range + target.radius + so`, orbit `r = reach - 0.5` unchanged in form), 3607 (`autoTarget(self, team, f, AttackSlack + standoffOf(D, f))`), 3673 (`stop = reach + so - 0.5` for melee), 3814-3815 (`reach + so - 0.5`), 4515 (`AttackSlack + so`). Line 4310 untouched.

- [ ] **Step 4: The poses in `PetPoses.lua`**

`DashIn` / `DashBack` per the Interfaces block; the constants `DASH_RUN = 0.78`, `DASH_HOP_FROM = 0.585`, `DASH_BACK_ARC = 1.0`, `DASH_SQUASH = 0.25`, `DASH_CHIN = 12`; `Holds.DashIn = true`. Header lines 9-11 and the shapes list updated.

- [ ] **Step 5: `AttackFx.Dash`, `DashState`, `Forward`, the streak**

Per the Interfaces block. `schedulePoses`: when `ctx.Dashed` and `A == "Melee"`, no `Strike` segment (the Hurt on the victim stays). `St.poses[unit]` entries gain `Forward`, `DashBackAt`, `Streak` (the kit); `Pose` writes `out.Forward = entry.Forward or 0`; when `DashIn` holds, `Forward = seg.Reach`; when `DashBack` plays, `Forward = 0` (the pose carries the offset from `reach`); `Cancel` / `ClearAll` give the streak kit back. The streak rides the root as the Pounce's Leap trail (`LEAP_TRAIL_UP`).

- [ ] **Step 6: `BattleController` wiring**

K: `DASH_SEEN = 0.6`. `Handlers[Windup]`: besides `windupUntil`, for a melee non-boss unit with a target: `u.atkAt` / `u.tempo` updated from `os.clock()`, `Atk.Dash(B, u, target, renderTimeOf(ev.at))` with `opts.Tempo = u.tempo`, `u.dashedAt = os.clock()`. `hitPlay`: a melee attacker not dashed within `DASH_SEEN` (my fighter): `u.atkAt` / `u.tempo` updated, `Atk.Dash(B, a, v, dueAt + Melee.In)` -> when true, `ctx.DueAt = dueAt + In`, `ctx.Dashed = true`, `late = In` (so `ev.fxLate = min(In, FX_LATE_MAX)`); when the unit was dashed from a Windup: `ctx.Dashed = true`, late 0. `Atk.PoseOf`: `body = CFrame.new(0, 0, -ps.Forward * pbScaleFactor) * body` where the factor is what `poseBody` applies to offsets. `renderTimeOf(simT)` = `os.clock() + (simT - B.renderT)` as `windupUntil` computes it.

- [ ] **Step 7: Run GREEN, the rewritten pins, the regression lists, the quick sim**

Run: the Step 2 command -> all pass (count).
Rewrite in `tools/smoke_fight.lua` (and any other list) every assertion pinning the melee stop at `reach - 0.5` to `reach + BC.Damage.Standoff - 0.5`; name them in the commit body.
Then: `py -3.12 tools/smoke.py --quick --only fight_engage_core,fight_engage_service,w6_dash_parry,dgfixcore_auto,dgfixcore_direct,dgfixcore_dash,dgfixcore_determinism,p5sim_determinism,p5battle_balance,bug2bat_raid_balance,raid_lethal,afx_reach_sim,afx_reach_npc,client_p7vfx_battle,client_dgfix_attack,client_fight_attack,client_w6_parry_fx,client_p3battle_raid,client_p3battle_ring,client_raid_enrage`
Then `SIM_BATTLE="quick only=raids,duels,dungeon"` (no MISS line). `node tools/check.mjs` -> 0; `count_locals` -> none at 200.

- [ ] **Step 8: Commit + push + ledger**

```bash
git add src/shared/PetPoses.lua src/client/Controllers/AttackFx.lua src/client/Controllers/BattleController.lua src/shared/BattleCatalog.lua src/shared/BattleSim.lua tools/smoke_feel_dash.lua tools/smoke.py tools/smoke_p7vfx.lua tools/smoke_fight.lua tools/README.md
git commit -F "<scratchpad>\msg2.txt"   # feat(battle-feel): melee dash + standoff 8 + flurry (PetPoses DashIn/DashBack, AttackFx.Dash, Damage.Standoff)
git push origin battle-feel
```

---

### Task 3: Weighty specials, the real server cast, the sim re-check

Spec: decisions 5-6, "Rules that hold / Balance bands hold", "What each side does / Server / SpecialCast" and "/ Client / Weighty, Sync", "Questions for the morning".

**Files:**
- Modify: `src/shared/AttackFxCatalog.lua:200` (`SpecialAfterglow`), `:649-663` (Beats from the knob), `:2041-2071` (`Resolve` beats), `:2182` (Afterglow)
- Modify: `src/client/Controllers/AttackFx.lua:152` (`SPECIAL_HIT_STOP`), `:3090, 3106, 3117-3122` (the freeze on Cast / Hurt for specials), `:3427-3447` (`fitTimes`)
- Modify: `src/shared/BattleCatalog.lua:238-239` (`Damage.SpecialCast`), Validate; `src/shared/BattleSim.lua:186-187` (Events), `:311`, `:2262-2355` (the queue), `:2378-2437+` (`beginCast` / `fireCast`), `:3448-3456`, `:3599`, `:3781-3784` (`cancelCast` on a stun)
- Modify: `src/client/Controllers/BattleController.lua:275-276` (K), `:3580-3660` (`Atk.Special`), `:3859-3881` (`Atk.Event` routes `Cast`), `:4481-4491` (callout), new `Handlers[EV.Cast]` / `Handlers[EV.CastBreak]`, `Atk.Update` (the cast wait), `Atk.PreCharge` (`untilT` extended)
- Create: `tools/smoke_feel_tempo.lua`; Modify: `tools/smoke.py`, the lists named in the file map (specials read at the cast), `tools/README.md`, `brain.md`, `README.md`

**Interfaces:**
- Consumes: Task 1's `Config.Battle.Feel.Special`; `AttackFx.Precharge(ctx)` (per-unit `St.pre[unit]`), `AttackFx.Shatter(unit, now, quiet)`, `fitTimes(b, now, dueAt, lateMax, from)`, `queueDelayed` / `resolveDelayed` / `onFloor`, `missEvent(self, u, target, events)`, `inIFrames(self, u)`.
- Produces:
  - `AttackFxCatalog.Beats.SpecialTempo` 1.4, `SpecialChargeMax` 1.1, `SpecialSpeed` 0.7, `SpecialTravelMax` 0.7, `SpecialImpact` 0.25, `AttackFxCatalog.SpecialAfterglow = { 1.2, 1.8, 2.4, 3.0 }` (= `Afterglow[band] x Feel.Special.Afterglow`); with `Weighty = false` every value equals today's (`SpecialChargeMax` 0.8, Tempo 1, Speed 1, TravelMax 0.5, Impact 0.15, Afterglow 1).
  - `AttackFx.SPECIAL_HIT_STOP = Feel.Special.HitStop` 0.08: the caster's `Cast` segment gets `StopAt = st + T.Impact, StopDur = SPECIAL_HIT_STOP`, each victim's `Hurt` segment the same, for `A == "Special"` only.
  - `fitTimes(b, now, dueAt, lateMax, from)`: with BOTH `from` and `lateMax`, the travel the fit cut is given back up to `lateMax` and the impact lands that much after `dueAt` (`late`); the charge stays backdated.
  - `BattleCatalog.Damage.SpecialCast = Feel.Special.RealCast and Feel.Special.Cast or nil`; Validate: every `SpecialKinds` entry a number 0.3..2.
  - `BattleSim.Events.Cast = "Cast"`, `Events.CastBreak = "CastBreak"`; `beginCast(self, u, events) -> ok, why` (today's refusals, then the entry `{ at = t + Cast[kind], from = u, cast = kind, target, x, z, form }`, `u.castUntil = at`, state Casting, `Cast` event `{ unit, kind, name, at = r1(at), target?, tx?, tz?, form? }`); `fireCast(self, d, events)` (today's body from `u.meter = 0`, aimed at `d.x, d.z`; Pounce at `d.target`'s live spot; supports on the live allies; a target `inIFrames` at the fire -> `missEvent` with `special = kind`; the `Special` event gains `at = r1(cast start)`); `cancelCast(self, u, events)` (the entry removed, `u.castUntil = t`, meter untouched, `CastBreak { unit, kind }`); without `SpecialCast` `castSpecial` runs exactly today's path.
  - `BattleController`: `K.CAST_WAIT = 0.5`, `K.SPECIAL_CALLOUT = Feel.Special.Callout` 1.6, `K.TRAVEL_HOLD = Feel.Special.TravelHold` 0.3; `B.casts[unitId] = { Kind, DueAt }`; `Handlers[EV.Cast]` -> `Atk.Cast(B, ev, dueAt)` (Precharge for any drawable unit; my own `St.pre.untilT = dueAt + CAST_WAIT`); `Atk.Special`: `Precharged = B.casts[u.id] ~= nil or (my press)`, `LateMax = K.TRAVEL_HOLD` for a cast-driven Special (today's `K.LATE_MAX` when the event has no `at` and no cast record); `Handlers[EV.CastBreak]` -> `Atk.Shatter` for that unit (quiet unless mine); `Atk.Update` shatters quietly a record past `DueAt + CAST_WAIT`; a KO drops the record.

- [ ] **Step 1: Write the failing scenarios in `tools/smoke_feel_tempo.lua`**

```lua
-- feel_cast_queue (server, pure): smoke_afx_reach's field + my Legendary Blast fighter at (0,0), bears at 20: Command Special ok; the step's
-- events hold a Cast { at == t0 + 0.9 (+- 0.05), target == bear 1, tx/tz == its spot } and NO Special / Hit; f.state == Casting until at;
-- f.meter == 100 until at; at `at` (Step past it): the Special event with targets == the bears inside 7 x reach and at == r1(t0),
-- one Hit per target with special == "Blast", f.meter == 0 and f.castUntil == at (no extra 0.5 s block). Every kind: Beam 0.8, Storm 0.95
-- (its zone starts at at), Freeze 0.7 (stun from at), Pounce 0.6 (the pet moves at at), Heal / Shield / Rally / Haste 0.55 / 0.5 / 0.55 / 0.5
-- (the heal / shield / buff lands at at, on the allies alive THEN). With BC.Damage.SpecialCast = nil (patched, restored): today's path,
-- the Special and its Hits in the cast's own step, castUntil == t0 + 0.5.
-- feel_cast_dodge (server, pure): an NPC Blast at my fighter (NpcSpecialDelay patched to 0): my Dash 0.1 s before at (i-frames at the fire)
-- -> a Hit event with miss == true and special == "Blast", no damage; my fighter walked 9 studs out of the circle before at -> no Hit at all.
-- feel_cast_break (server, pure): my fighter stunned (a Freeze) 0.3 s into its 0.9 s cast: the entry is gone (#b.delayed == 0), a CastBreak
-- { unit, kind } event, f.meter still 100, no Special / Hit later; my fighter KO'd mid-cast: the entry dropped, no CastBreak, no Hit; a Rally
-- caster KO'd mid-cast: no Buff event.
-- feel_cast_wire: BS.Events.Cast == "Cast", CastBreak == "CastBreak"; every Cast / Special / CastBreak field a number or string, `at`
-- rounded to 0.1; BC.Validate true; SpecialCast.Blast = 5 -> false.
-- feel_cast_determinism: two Duels, seed 23, 40 s, specials on: identical event streams (as p5sim_determinism).
-- client_feel_tempo_beats (client): AFC.Resolve for a Legendary Blast at 14 studs: Charge == min(1.1, 0.55 x 1.4 + 0.05 x 2) (+- 1e-6),
-- Travel == min(0.7, 14 / 42), Impact == 0.25, Afterglow == 2.4; a Secret Storm: Charge 1.1 (the cap), Travel min(0.7, 0.45 / 0.7);
-- Weighty = false (Config patched, Beats re-read through a `AFC.Reload()` or a fresh require as the harness allows): today's numbers;
-- a Melee / Ranged basic: unchanged at both settings.
-- client_feel_tempo_hold (client): AF.Play of a Blast whose DueAt is 0.78 s away: the charge is cut to fit, the travel kept, ImpactLate <= 0.30
-- and == min(0.30, the authored travel the fit cut); the caster's Cast pose and the victim's Hurt pose freeze 0.08 s at the impact
-- (poseSample's p flat across StopAt .. StopAt + 0.08); Low: the same beats, Afterglow 0.
-- client_feel_tempo_cast (client): a replayed Duel with Cast / Special / Hit events: on Cast an enemy pet's charge starts (AF.Precharging(unit)
-- true, the rim / inhale cues within INHALE_MAX), its Special at `at` takes it over (Precharged, the impact at dueAt + <= 0.3), its Hits play
-- with the impact (fxSpLate <= 0.3); my pressed Special: St.pre.untilT == the Cast's dueAt + 0.5, no shatter at 0.7 s, the hand-over at the
-- end; "break": a CastBreak shatters that unit's charge (shards for mine, quiet for an enemy), B.casts empty; a Cast with no Special by
-- dueAt + 0.5: a quiet shatter, no error; "old events": a recording with no Cast and a Special without `at`: today's LateMax path, the same
-- fxSpLate as before this task (the frozen number from the recording's expectation).
-- client_feel_tempo_callout (client): the Special callout's life == 1.6 (Fx.Number's last argument captured by the mock).
-- client_feel_tempo_low (client): SetQuality("Low") then a Blast: the beats as High, no afterglow, no streak, the freeze kept.
```

- [ ] **Step 2: Register and run RED**

`tools/smoke.py`: `if p5("smoke_feel_tempo.lua"): server_files.append("smoke_feel_tempo.lua"); client_files.append("smoke_feel_tempo.lua"); names = ["feel_cast_queue", "feel_cast_dodge", "feel_cast_break", "feel_cast_wire", "feel_cast_determinism"]; pure_scenarios += names; ins(server_scenarios, "p5stats_formula", names); ins(client_scenarios, "client_final", ["client_feel_tempo_beats", "client_feel_tempo_hold", "client_feel_tempo_cast", "client_feel_tempo_callout", "client_feel_tempo_low"])  # [battle-feel, T3] ...`
Run: `py -3.12 tools/smoke.py --quick --only feel_cast_queue,feel_cast_dodge,feel_cast_break,feel_cast_wire,feel_cast_determinism,client_feel_tempo_beats,client_feel_tempo_hold,client_feel_tempo_cast,client_feel_tempo_callout,client_feel_tempo_low`
Expected: FAIL (no Cast event, Hits in the cast's step, Charge 0.65, Impact 0.15, callout 1.2).

- [ ] **Step 3: The beats in `AttackFxCatalog.lua`**

`local FEEL = Config.Battle and Config.Battle.Feel and Config.Battle.Feel.Special or {}` at the top (AttackFxCatalog requires `script.Parent.Config` as the other shared modules do); Beats: `SpecialTempo = FEEL.Weighty and FEEL.Tempo or 1`, `SpecialChargeMax = FEEL.Weighty and FEEL.ChargeMax or 0.8`, `SpecialSpeed = FEEL.Weighty and FEEL.Speed or 1`, `SpecialTravelMax = FEEL.Weighty and FEEL.TravelMax or 0.5`, `SpecialImpact = FEEL.Weighty and FEEL.Impact or 0.15`; `AttackFxCatalog.SpecialAfterglow` = each `Afterglow[i] x (FEEL.Weighty and FEEL.Afterglow or 1)`. `Resolve`: for `special`: `charge = charge * B.SpecialTempo` before the band step and the cap; `core.Speed = core.Speed * B.SpecialSpeed` (and `beats.Travel / B.SpecialSpeed` when there is no Speed), the cap `B.SpecialTravelMax`; `Impact = beats.Impact or B.SpecialImpact`; at 2182 `SpecialAfterglow[band]` for a special strike.

- [ ] **Step 4: The freeze and `fitTimes` in `AttackFx.lua`**

Per the Interfaces block. The Cast segment (3106) and the Hurt segments (3117-3122) get `StopAt` / `StopDur` when `A == "Special"`; `AttackFx.SPECIAL_HIT_STOP` read from `Config.Battle.Feel.Special.HitStop` (0 when `Weighty` is false). `fitTimes`: in the `from` branch, after the `PRE_MIN_CHARGE` give-way, `if finite(lateMax) and lateMax > 0 then local back = min((b.Travel or 0) - Tr, lateMax); Tr, late = Tr + back, late + back end`.

- [ ] **Step 5: The server cast in `BattleSim.lua` + `BattleCatalog.lua`**

`Damage.SpecialCast` from Config (239) + Validate. `BattleSim`: Events 186-187; the fallback table 311 (`SpecialCast = nil`); `castSpecial` -> `beginCast` when `D.SpecialCast` and `D.SpecialCast[kind]` is a number, else today's body; `fireCast(self, d, events)` holds today's body from `u.meter = 0` with `target` = `d.target` (Pounce: its live spot; the aim `d.x, d.z` for Blast / Storm / Freeze / Beam); `resolveDelayed`: `if d.cast then fireCast(self, d, events)` (the `onFloor` drop stays first); the i-frames check inside each area loop (`inCircle` / `inLine` / the Pounce target) -> `missEvent(self, u, e, events)` with `special = kind` in its extra; `cancelCast` from the stun branches at 3448-3451 (NPC) and the fighter's stun (`f.stunUntil` set while `f.castUntil > t` and an entry exists); the Casting state lines 3453 / 3783 unchanged. `Command("Special")` while Casting stays refused as today.

- [ ] **Step 6: The client sync in `BattleController.lua`**

Per the Interfaces block: `Atk.EVENTS` gains `Cast`; `Atk.Event` routes `Cast` to `Atk.Cast`; `Handlers[EV.Cast]` (the list row's "!" as the Windup's, `B.casts[u.id]`); `Handlers[EV.CastBreak]`; the callout at 4491 uses `K.SPECIAL_CALLOUT`; `Atk.Special` sets `Precharged` / `LateMax` as above and clears `B.casts[u.id]`; `Atk.Update` walks `B.casts` once per frame (a table of at most the unit count; no allocation: reuse the record). `Net.SpecialHold` unchanged (it reads `ev.fxSpLate`).

- [ ] **Step 7: Run GREEN, rewrite the cast-time pins, the regression lists**

Run: the Step 2 command -> all pass (count).
Rewrite (same task, named in the commit body): `tools/smoke_afx_reach.lua:116-123` `special()` steps to `t0 + BC.Damage.SpecialCast[kind] + 0.05` before reading the Special event; the same pattern wherever `smoke_evo_sim.lua`, `smoke_p5_battlecore.lua`, `smoke_bug2_battle.lua`, `smoke_dgfix_core.lua` (`dgfixcore_heal`) and `smoke_p7vfx_client.lua` (`client_p7vfx_precharge`: the event now comes after the cast; PRESS_WAIT extended by the Cast) read a special's effects in the cast's own step. Any assertion on `castUntil == t + 0.5` becomes `t + SpecialCast[kind]`.
Then: `py -3.12 tools/smoke.py --quick --only afx_reach_sim,afx_reach_npc,afx_reach_timers,evo_pounce,evo_blast,evo_storm,evo_beam,evo_freeze,evo_heal,evo_shield,evo_rally,evo_haste,evo_boss_twists,evo_delayed,evo_wire,bug2bat_npc_specials,dgfixcore_heal,dgfixcore_determinism,p5sim_determinism,p5battle_balance,w6_dash_parry,raid_lethal,client_p7vfx_precharge,client_p7vfx_storm,client_p7vfx_battle,client_evo_twists,client_evo_auras,client_audio_charge,client_afx_kick,client_afx_kick_battle,client_feel_dash_npc,client_feel_dash_mine,client_feel_aim_floor`
`node tools/check.mjs` -> 0; `count_locals` -> none at 200.

- [ ] **Step 8: The full sim and the boss nudge rule**

Run from the repo root: `$env:SIM_BATTLE="full"; py -3.12 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())" > "<scratchpad>\sim-full.txt"`; copy it to `.superpowers/battle-feel/evidence/sim-full.txt`.
Expected: 64 of 64 `TARGET ok`, no `MISS`. If a raid cell's average is over 240 s: lower that boss's `HpTier[tier]` in `BattleCatalog` (lines 1846 / 1865 / 1884 / 1903) by 0.02 at a time until the cell is under 240 and its 3-team win rate stays in 25-55 %, run `SIM_BATTLE="quick only=raids"` between tries, then the full run again; write the old and new numbers in the ledger under "Questions for the morning". Never loosen a target.

- [ ] **Step 9: Docs, commit + push + ledger**

`brain.md`: one dated line (2026-11-10, the battle feel: the six picks, the knob `Config.Battle.Feel`, the spec and plan paths, any HP nudge). `README.md` battle section: one line on the dash, the centre aim and the cast. `tools/README.md`: the three smoke files.

```bash
git add src/shared/AttackFxCatalog.lua src/client/Controllers/AttackFx.lua src/shared/BattleCatalog.lua src/shared/BattleSim.lua src/client/Controllers/BattleController.lua tools/smoke_feel_tempo.lua tools/smoke.py tools/smoke_afx_reach.lua tools/smoke_evo_sim.lua tools/smoke_p5_battlecore.lua tools/smoke_bug2_battle.lua tools/smoke_dgfix_core.lua tools/smoke_p7vfx_client.lua tools/README.md brain.md README.md
git commit -F "<scratchpad>\msg3.txt"   # feat(battle-feel): weighty specials x1.4 + the real server cast (Cast / Special.at / CastBreak), sim re-check
git push origin battle-feel
```

---

## Gate (after Task 3, Fable 5.1 high)

- Memory rule: with >= 4 GB free and no other `smoke.py` process, the whole `py -3.12 tools/smoke.py --quick` (counts in the ledger); otherwise the union of the three tasks' `--only` lists plus `client_p3battle_raid,client_p3battle_trial,client_p3battle_mobile,client_raid_mobile,client_p5hud_fighter`, and say so.
- `SIM_BATTLE=full` once more on the final tree (the Step 8 file is the evidence).
- The owner's Studio checks (the main session, the one Studio window, Rojo on 34872 as today): a raid with 8 fighters' melee pets dashing at a boss (a screenshot from the shoulder camera and one from the stands), a phone layout (844x390 device emulation) mid-dash, Graphics Low with a Legendary Blast (no afterglow, the beats and the freeze seen). Save to `.superpowers/battle-feel/evidence/` and LOOK at them before any "done": floating pets, a bite that lands 8 studs away, a ring under the floor or a Blast dome at the feet are failures.
- The ledger's "Questions for the morning" filled (the spec's four, plus anything the gate found).

## Self-review notes

- Spec coverage: decision 1 -> T2 Steps 4-6; 2 -> T2 Step 3; 3 -> T2 Steps 5-6 (`Tempo`, `FlurryBelow`); 4 -> T1; 5 -> T3 Steps 3-4; 6 -> T3 Steps 5-6; balance -> T3 Step 8; phones / Low -> T2 budget scenario, T3 low scenario; off switches -> each task's "off" step; the morning questions -> T3 Step 9 + the gate.
- Names used across tasks: `Config.Battle.Feel` (T1) read by T2 / T3; `AttackFx.LeapReach` (today) by `Dash`; `fitTimes(b, now, dueAt, lateMax, from)` (today) extended in T3; `BattleCatalog.Damage.Standoff` (T2) / `SpecialCast` (T3); `B.casts` only in T3.
- Proportion: three tasks, about 50 lines of plan per 300-400 lines of change each; bodies appear only where the pose math and the fitTimes give-back are not determined by the tests.
