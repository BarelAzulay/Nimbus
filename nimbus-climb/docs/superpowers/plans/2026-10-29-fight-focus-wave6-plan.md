# Wave 6 Fight Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pets fight anything in the fight area and ignore the trainer's movement; Dash becomes a timed dodge / parry; the
trainer is locked and cheering on the podium in Ring / PvP and gets a "Cheer up!" boost button in Dungeon / Raid; dungeon
cameras stay inside rooms; the room walk-in plays on every floor; balance is re-measured with a skill-based dodger.

**Architecture:** The engage, dash / parry and cheer rules live in the pure `BattleSim` (server-authoritative,
deterministic, replayed by `tools/sim_battle.lua`). `BattleService` only wires the new `Cheer` command and the podium lock
(a small new server module). The client gets a small cheer-emote module, the Cheer up! button in the battle HUD, the parry
flash, a camera box clamp in `DungeonController`, and the walk-in fix.

**Tech Stack:** Roblox Lua (plain Lua 5.1 syntax: `node tools/check.mjs` rejects Luau-only syntax), Rojo, the lupa smoke
harness (`tools/smoke.py` + `tools/robloxmock.lua`), `tools/sim_battle.lua`.

**Spec:** `docs/superpowers/specs/2026-10-29-fight-focus-wave6-design.md` (approved 2026-10-29, including "Decided by the
player" and "Claude's calls"). Read it before any task.

## Global Constraints

- Work only in the worktree `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\wave6\nimbus-climb`
  (branch `wave6-fight`). Quote the Hebrew path in Bash. Never `git push`, `git checkout`, `git stash`; never open or drive
  Roblox Studio; never upload; no subagents unless the executing skill dispatches them.
- Run tests from the worktree's `nimbus-climb` folder with
  `"/c/Users/elmoz/AppData/Local/Programs/Python/Launcher/py.exe" -3.12 tools/smoke.py --quick --only <a,b,...>` (call it
  `$PY` below) and `node tools/check.mjs` (0 errors). Never bare `python`. At most ONE full `smoke.py --quick` (Task 13).
  One heavy process at a time (Studio runs on this PC).
- Plain Lua 5.1 syntax in every `src/` and `tools/*.lua` file. Comment density and naming like the surrounding code; every
  new rule gets a dated `-- wave 6:` comment where the old rule's comment was.
- Server-authoritative: the engage, dash, parry, cheer and podium rules are decided on the server; the client only draws.
  Every remote argument is validated; Cheer is rate-limited.
- No new sound playback anywhere (a separate sound wave). No new art pieces, no new asset ids (check.mjs `asset-id`: only
  `Config.Art` ids are legal, so no raw animation ids).
- Spec numbers, verbatim: `ParryWindow 0.25 s`, parry stagger `0.4 s`, parry meter `+8`, `CheerBoost 0.05`,
  `CheerSeconds 5`, `CheerCooldown 20`, "Does not stack". DashIFrames / DashCooldown / DashSeconds unchanged (0.35 / 2.5 /
  0.35). Ring / PvP auto-cheer is visual only (no boost).
- Removed: `EngageRange`, `EngageLeash`, `EngagePull`, `EngageStillSeconds`, `EngageCooldown` (catalog, sim defaults,
  Validate, tests). Chase speed stays the pet's legal run.
- "Fight area" = the BattleSim floor (the zone rectangle) in every mode: Ring 44 x 44, Duel 44 x 44, Raid 96 x 96, Dungeon
  Room 44 x 44 / Boss 56 x 72 (`BattleCatalog.Zones`, `BattleCatalog.Dungeon.Zones`). The sim already clamps every unit to
  it, so "anywhere in the fight area" = "any targetable enemy in the battle".
- Commit after every task (message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

## Builder decisions (where the spec left a choice; listed in the final report for the owner)

1. **Engage target order:** the lock (if targetable) -> the current engaged target (sticky until it dies or is
   untargetable) -> the fresh threat (hit the fighter within `ThreatSeconds`) -> the targetable enemy nearest to the
   FIGHTER (ties: lower id). `Attack()` with no id keeps a live lock anywhere on the floor, else the engaged target, else
   the nearest.
2. **What a parry catches:** only the visible, timed threats: an NPC wind-up whose `windTarget` is the fighter and a boss
   telegraph whose shape covers the fighter, landing within `(t, t + ParryWindow]` of the Dash press. A boss basic attack
   has no tell: the i-frames still dodge it, it is never a parry.
3. **Stagger:** an NPC = `applyStun(u, ParryStagger)` (it also cancels the wind-up). A boss (`applyStun` refuses bosses) =
   `boss.staggerUntil = t + ParryStagger`: no new basic attack and no new telegraph while it lasts (telegraphs already
   cast still resolve). New data `ParryBossGap = 3`: a boss is staggered at most once per 3 s (anti-goal: a 16-raid of
   parries must not perma-lock a boss). The meter and the flash still come with every parry.
4. **Sidestep direction** (set at the press, kept for `DashSeconds`, moves at legal run x the dash factor, clamped to the
   floor): the soonest parry-window threat, else the soonest pending threat aimed at / covering the fighter: a circle
   telegraph -> straight away from its centre; a line -> perpendicular to the line, to the side the fighter is on; a
   winding NPC -> straight away from it. No threat -> perpendicular to the aim (lock / engaged / nearest), on the side
   toward the floor centre. A zero vector falls back to the fighter's facing turned 90 degrees. The `Dash` event `dir` is
   this vector, `target` = the threat source's unit id or nil.
5. **The pink podium block** = the spot each mode already teleports the trainer to: Ring = the pocket's `SpawnPad`
   (`ArenaBuilder` Ring pocket, `pocket.Spawn` 7 studs in from the -Z rim, outside the 44-stud floor); PvP = the side's
   `ChallengePad` (`BattleService` `duelStand`). Their colour in the mesh bake is unconfirmed (SpawnGlow is green,
   Duel Ring 1's PadGlow is red): the lock uses the stand CFrame, not a colour; the owner confirms in Studio.
6. **Podium lock:** the server anchors the character's `HumanoidRootPart` at the stand CFrame and sets the player
   attribute `Config.Attr.OnPodium = true`; every battle tick a locked root more than 2 studs from its stand is put back.
   Released at the round's / duel's end, Leave / Forfeit, leaving the game, death / respawn and Shutdown. The Ring
   intermission is unlocked (next round re-teleports + re-locks). A one-time toast: "You're the trainer: cheer your pet
   on from the podium!".
7. **Cheer animation:** the default `Animate` script's `PlayEmote` BindableFunction with `"cheer"` (R15 and R6). No raw
   animation id (check.mjs `asset-id`). No `PlayEmote` = no animation (the boost still works); the owner is asked.
8. **Cheer input:** the Cheer up! button only (click / tap). No new keyboard / gamepad binding (spec: "No new battle
   controls beyond the Cheer up! button"); gamepad players are an owner question.
9. **Camera containment:** a client boom clamp, not invisible walls. Root cause of the zoom-out: `MeshLibrary` hides a
   dressed room's parts locally (`Transparency = 1`, `src/shared/MeshLibrary.lua:1507`) and the meshes are
   non-colliding; Roblox's Poppercam only stops at colliding parts under ~0.95 total transparency, so the collide ceiling
   (`Kit.ceiling`, bug batch 2 #19) no longer stops the camera. Every placed piece carries `CamMin` / `CamMax`
   (world Vector3 attributes); each frame after the camera scripts the boom from `Camera.Focus` is shortened to stay
   inside the union of the current room's piece boxes. Same ray, same rotation: no jitter, no clipping, works with or
   without the mesh dress, covers open Bridge rooms, corridors, the hall, the boss room and the treasure.

## Review Focus

1. **Wave arrivals:** a dungeon wave's enemies are untargetable for `ArriveSeconds` 1.2: the pet goes back to FOLLOW and
   re-engages the moment they land, with exactly one `Engage off` and one `Engage on` per gap (no per-step flapping
   storm). Test: Task 1 step 1 case (e).
2. **Never left anchored:** a podium player who dies, respawns, disconnects, forfeits, or whose ring run ends on a loss /
   timeout / Shutdown is unanchored and `OnPodium` is cleared; a fresh character is never anchored. Test: Task 6 step 1.
3. **Dash at the floor edge / with no threat:** the sidestep stays on the floor and never points at the boss; a dash in a
   corner with a telegraph centred inside the floor still leaves the circle when possible. Test: Task 2 step 1 cases (c), (d).
4. **Cheer abuse:** Cheer spam (40 remote calls in 1 s), junk args, Cheer in Ring / Duel / no battle / as a spectator /
   while the fighter is Down -> one accepted cheer at most, refusals echo once per step, the boost never stacks past 5 %.
   Test: Task 3 step 1 and Task 5 step 1.
5. **Camera at a doorway:** walking from the corridor into a room (the focus crosses from one box into the other) the
   clamped camera moves continuously (no frame-to-frame jump > the focus move + 1 stud); a first-person boom (< 1 stud)
   and a Scriptable camera (walk-in, entrance) are never touched. Test: Task 11 step 3.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `src/shared/BattleCatalog.lua` | modify | Fighter data: remove Engage*, add Parry* / Cheer*; Validate |
| `src/shared/BattleSim.lua` | modify | engage rule, dash sidestep, parry, stagger, Cheer command, events, TeamOf |
| `tools/sim_battle.lua` | modify | scripted player: still trainer, timed Dash with a skill rate, Cheer; move section |
| `src/server/Services/Podium.lua` | create | lock / release / watch of a trainer on a stand CFrame |
| `src/server/Services/BattleService.lua` | modify | Cheer in `Cmd.ACTIONS`, podium lock calls, Start payload cooldowns, header |
| `src/shared/Config.lua` | modify | `Config.Attr.OnPodium = "OnPodium"` |
| `src/client/Controllers/TrainerCheer.lua` | create | play / loop the avatar cheer emote |
| `src/client/Controllers/BattleController.lua` | modify | Cheer up! button, podium cheer loop + hint, Parry flash, Cheer event |
| `src/client/Controllers/HudController.lua` | modify | `GetLayout().Vitals` rect (the HP bar card) |
| `src/server/Services/DungeonBuilder.lua` | modify | `CamMin` / `CamMax` on every placed piece |
| `src/client/Controllers/DungeonController.lua` | modify | camera box clamp; the walk-in fix |
| `src/server/Services/DungeonService.lua` | modify only if Task 10 finds the cause there |
| `tools/smoke_wave6.lua` | create | all wave 6 scenarios (both worlds, `ARGS.context`) |
| `tools/smoke_fight.lua` | modify | `fight_engage_core` / `fight_engage_service` rewritten to the new rules |
| `tools/smoke.py` | modify | one registration line for `smoke_wave6.lua` (own line, re-read before editing) |
| `BUILD_STATE.md`, `ARCHITECTURE_V3.md` | modify | the settled wave 6 rules (Task 13) |

`smoke_wave6.lua` follows `smoke_fight.lua`'s shape: `serverScenarios()` / `clientScenarios()`, `SmokeCommon.T` /
`guarded`, and copies its pure battle helpers (`world`, `enemiesAt`, `put`, `stepAt`, `standFor`, `engaged`, `find`,
`count`, `dummy`). The `smoke.py` line (added in Task 1, extended by later tasks, same style as the `smoke_fight.lua` line):
pure + server scenarios `w6_*`, client `client_w6_*`, mobile `client_w6_*_mobile`.

---

### Task 1: The engage rule: any enemy in the fight area, owner movement ignored

**Files:**
- Modify: `src/shared/BattleCatalog.lua:31-36` (header), `:326-330` (Fighter), `:1905-1928` (Validate)
- Modify: `src/shared/BattleSim.lua:14-58` (header contract), `:257-260` (defaults), `:429-450` (team record),
  `:2850-2952` (engageTarget / engageUpdate), `:3485-3488` (Attack keep-lock)
- Modify: `tools/smoke_fight.lua:1-20, 175-470` (`fight_engage_core`)
- Create: `tools/smoke_wave6.lua` (helpers only + registration); Modify: `tools/smoke.py` (one line)

**Interfaces:**
- Produces: `team.engage = { target, unit, since } | nil` (no stand point); `TeamOf(owner).Engaged` unchanged;
  `Events.Engage` unchanged shape; `engageTarget(self, team, f) -> unit | nil` (order: Builder decision 1).
- Removes: `team.movedAt`, `team.lastWantX/Z`, `team.disengagedAt`, every `Engage*` Fighter number.

- [ ] **Step 1: Rewrite `fight_engage_core` to the new rule (failing).** Keep the scenario name. Replace cases (1)-(13):
  - (a) the constants: `F.EngageRange == nil and F.EngageLeash == nil and F.EngagePull == nil and F.EngageStillSeconds == nil
    and F.EngageCooldown == nil and BS.Events.Engage == "Engage"`.
  - (b) an enemy 30 studs from a WALKING character (Move point jittering 0.6 stud every step): the pet engages on the
    first step (`engaged(b) == e.id` within 0.15 s) with one `Engage { owner, unit, on = true, target }`; it runs at
    the honest legal run (`maxStep <= run * 0.1 + 0.02`, a full-speed step seen) and its auto-attack lands within
    `30 / run + 2` s.
  - (c) fight focus: while engaged the character walks 20 studs away (and back and forth) for 5 s: no `Engage on = false`,
    the pet stays within `reach + 0.2` of its target, `TeamOf(1).Engaged` stays the same id.
  - (d) sticky: a second enemy hits the fighter while it is engaged: the target does not change; the first target KO'd ->
    the NEAREST-to-the-fighter remaining enemy next step, no command; none left -> `Engage on = false` and the pet walks
    back toward the Move point at run x MoveSlack.
  - (e) Review Focus 1: a `SpawnEnemies` wave after the last kill: during its 1.2 s arrival exactly one `Engage off`, then
    exactly one `Engage on` within 0.15 s of the arrival end (`count(evs, "Engage") == 2` over the gap).
  - (f) a far lock (35 studs) + a near enemy: the pet engages the LOCK (order rule 1); `Attack()` keeps that lock with no
    `Order` echo; `Target(near.id)` switches the engaged target within one step.
  - (g) a ranged fighter holds at `reach - 1` of a target 40 studs away; Stunned = no move, still engaged; Swap drops it and
    the incoming pet engages after `SwapCastSeconds` (no still time).
  - (h) Validate still passes the shipped catalog; determinism: two runs with the same seed and Move script give the same
    `Snapshot()`.
- [ ] **Step 2: Run it, expect FAIL** — `$PY tools/smoke.py --quick --only fight_engage_core`: (a), (b), (c), (f) fail.
- [ ] **Step 3: Implement.** In `BattleSim.lua`: `engageTarget(self, team, f)` per decision 1 (no range: the floor is the
  bound); `engageUpdate(self, team, f, events)`: engaged -> keep while `engageTarget` returns a unit (drop + event when it
  returns nil or `e.unit ~= f.id`); not engaged -> engage at once when not arriving / Casting and a target exists. Delete
  the still detector, the pull and the leash, their team fields and defaults. `Attack()` with no id: keep the lock when
  `targetable`, else the engaged target, else `nearestTarget`. Delete the five Fighter numbers and their Validate block in
  `BattleCatalog.lua`; rewrite the header comments of both files (the old "character leads when it moves" text goes; say
  "wave 6: the pet fights any targetable enemy on the floor; the character's movement never pulls it off").
- [ ] **Step 4: Run, expect PASS** — `$PY tools/smoke.py --quick --only fight_engage_core,p5sim_fighter,p5sim_modes,p5sim_determinism`
  and `node tools/check.mjs` (0 errors). If `smoke_p5_battlecore.lua:311` lists an Engage number, drop it from that check.
- [ ] **Step 5: Commit** — `feat(battle): pets engage any enemy in the fight area, owner movement ignored (wave 6)`.

### Task 2: Dash = sidestep out of the threat, Parry inside the window

**Files:**
- Modify: `src/shared/BattleCatalog.lua` (Fighter: `ParryWindow = 0.25, ParryStagger = 0.4, ParryMeter = 8, ParryBossGap = 3`;
  Validate: `0 < ParryWindow <= DashIFrames`, `0 <= ParryStagger <= 1`, `0 <= ParryMeter <= 30`, `ParryBossGap >= ParryStagger`)
- Modify: `src/shared/BattleSim.lua` (`Events.Parry = "Parry"`, `dashDirection`, Dash command `:3530-3542`,
  `fighterStep` movement, `bossStep` stagger gate, `missEvent` extra `parry`, header Event shapes)
- Test: `tools/smoke_wave6.lua` scenario `w6_dash_parry` (pure)

**Interfaces:**
- Produces: `Events.Parry = "Parry"`, event `{ type = "Parry", unit = fighterId, from = attackerId, tele = teleId | nil }`;
  the landing hit's miss event carries `parry = true`; `Dash` event `dir` = the sidestep vector (decision 4), `target` =
  the threat source id | nil; fighter fields `dashDX, dashDZ`; boss fields `staggerUntil`, `staggerAt`.

- [ ] **Step 1: Write `w6_dash_parry` (failing)**:
  - (a) an NPC 3 studs off winds up on the fighter; Dash at `windAt - 0.15`: one `Parry { unit = f.id, from = npc.id }`,
    the fighter takes 0 damage, `npc.stunUntil >= t + 0.4 - 0.05`, `f.meter` rose by 8 (meter capped), and no
    `DODGED`-style plain miss is emitted for that wind-up (the wind-up was cancelled).
  - (b) Dash at `windAt - 0.5` (too early): no `Parry`; the hit lands (`dmg > 0`) because the i-frames ended; the dash
    cooldown is spent (`Cooldowns.Dash > 2`).
  - (c) a boss circle telegraph (r 8) centred 2 studs from the fighter, Dash at `at - 0.1`: `Parry { from = boss.id, tele
    = id }`, the telegraph's Hit on the fighter is `miss = true, parry = true`, after the dash the fighter is outside the
    circle (`dist > 8 + radius` unless clamped), its dash vector points away from the centre (dot > 0.9), the boss starts
    no basic attack and no telegraph for 0.4 s; a second parry 1 s later gives Parry + meter but no new stagger
    (`ParryBossGap`). A Line telegraph: the vector is perpendicular to the line (|dot| < 0.1) on the fighter's side.
  - (d) Review Focus 3: no threat, fighter on the -X edge with its lock straight +Z: the dash vector is perpendicular to the
    aim and points toward the centre (+X); in a corner the fighter stays on the floor (`clampToFloor`), never closer to
    the boss than before.
  - (e) engaged fighter dashing: during `DashSeconds` it moves along `dir` (not toward its target), then walks back and
    swings again; `Dash` event `dir` equals the sidestep vector within 0.01.
  - (f) Validate rejects `ParryWindow 0.5` (> DashIFrames), `ParryWindow 0`, `ParryMeter 50`.
- [ ] **Step 2: Run, expect FAIL** — `$PY tools/smoke.py --quick --only w6_dash_parry`.
- [ ] **Step 3: Implement** in `BattleSim.lua`: `findThreats(self, f) -> list of { at, kind = "Windup" | "Tele", src, tele }`
  (wind-ups with `u.windTarget == f`, telegraphs whose shape covers `f` via `inCircle` / `inLine`); in the Dash command,
  after the cooldown checks: threats with `at - t <= ParryWindow` -> parry each (meter `min(max, meter + ParryMeter)`,
  NPC `applyStun`, boss stagger if `t - (boss.staggerAt or -huge) >= ParryBossGap`), mark `f.parryUntil = latest at + 0.05`,
  emit `Parry`; set `f.dashDX/DZ` by decision 4. In `fighterStep`, while `t < f.dashUntil`, move along `dashDX/DZ` at legal
  run x `dashSpeedFactor()` (skip engageStep / follow), `clampToFloor`. In `bossStep`, return before the basic attack and
  the telegraph start while `t < (boss.staggerUntil or 0)`. In `resolveTelegraph` / the wind-up landing, a miss on a unit
  with `t <= f.parryUntil` carries `parry = true`.
- [ ] **Step 4: Run, expect PASS** — `$PY tools/smoke.py --quick --only w6_dash_parry,fight_engage_core,dgfix_core,p5sim_ai`
  (whichever scenario owns `smoke_dgfix_core.lua:439` keeps passing: i-frames and DashCooldown unchanged); `node tools/check.mjs`.
- [ ] **Step 5: Commit** — `feat(battle): Dash sidesteps out of the threat; a timed Dash parries (wave 6)`.

### Task 3: Cheer up! in the sim

**Files:**
- Modify: `src/shared/BattleCatalog.lua` (Fighter: `CheerBoost = 0.05, CheerSeconds = 5, CheerCooldown = 20`; Validate:
  `0 < CheerBoost <= 0.1`, `0 < CheerSeconds < CheerCooldown`)
- Modify: `src/shared/BattleSim.lua` (`Events.Cheer = "Cheer"`, team `cheerUntil` / `cheerReadyAt`, `doCommand` "Cheer",
  `attackMult`, `TeamOf().Cooldowns.Cheer`, header API)
- Test: `tools/smoke_wave6.lua` scenario `w6_cheer_core` (pure)

**Interfaces:**
- Produces: `battle:Command(owner, "Cheer") -> true | false, "NoCheer" | "Cooldown" (extra = seconds left) | "Down"`;
  event `{ type = "Cheer", owner, unit = fighterId, untilT }`; `TeamOf(owner).Cooldowns.Cheer` (seconds) and
  `TeamOf(owner).Cheering` (bool).

- [ ] **Step 1: Write `w6_cheer_core` (failing)**: in a Raid and a Dungeon battle, `Command(1, "Cheer")` -> true, one
  `Cheer` event, the fighter's next plain hit on a dummy is `1.05 x` the same seed's uncheered hit (compare two battles,
  `near(ratio, 1.05, 1e-6)` with crits off via the dummy's stats); `Cooldowns.Cheer` ~ 20; a second Cheer at +1 s ->
  `false, "Cooldown"`, the boost still 1.05 (never 1.1025); at +5.05 s the ratio is 1.0; at +20.05 s Cheer works again.
  Ring and Duel -> `false, "NoCheer"`; the fighter Down (lives left, KO'd) -> `false, "Down"`; an Npc team -> refused;
  Validate rejects `CheerBoost 0.2` and `CheerSeconds 20`.
- [ ] **Step 2: Run, expect FAIL** — `$PY tools/smoke.py --quick --only w6_cheer_core`.
- [ ] **Step 3: Implement**: `attackMult(self, attacker)` multiplies `1 + CheerBoost` when `attacker.team` is a player team
  with `self.t < team.cheerUntil` and `attacker == team.fighter`; the command sets (not adds) `cheerUntil` and
  `cheerReadyAt`.
- [ ] **Step 4: Run, expect PASS** — `$PY tools/smoke.py --quick --only w6_cheer_core,w6_dash_parry,p5sim_wire`; `node tools/check.mjs`.
- [ ] **Step 5: Commit** — `feat(battle): Cheer up! boost (+5% for 5 s, 20 s cooldown) in raids and dungeons (wave 6)`.

### Task 4: sim_battle player model: a standing trainer who times the Dash

**Files:**
- Modify: `tools/sim_battle.lua:1-20` (header), `:210-460` (`Player`), `:1373-1440` (`move` section)

**Interfaces:**
- Consumes: Tasks 1-3 (`Parry` / `Cheer` events, `Cooldowns.Dash` / `Cooldowns.Cheer`, `BattleCatalog.Fighter.ParryWindow`).
- Produces: `Player` opts `dodge` (kept name, now "the skill rate: how often the Dash is timed right", default 0.7),
  `mistime` (default 0.5: of the mistimed threats, the share pressed too early; the rest not pressed), `move = "stand" |
  "wander"` (default "stand"), `cheer` (default true); `p.parries` counter; `stats.parries`, `agg.parries`.

- [ ] **Step 1: Change the model.** Remove the escape run and the walk-to-target: the character stands at its start point
  (`"wander"`: a slow random walk inside the zone, used once per raid cell to prove movement changes nothing). For each
  `Windup` aimed at my fighter and each `Telegraph` covering it: with probability `dodge` press Dash at
  `at - (0.05 + 0.15 x rand)` (inside ParryWindow), else with probability `mistime` press at `at - (0.45 + 0.35 x rand)`,
  else not at all; never earlier than `t + reaction()`; the earliest pending press wins (the 2.5 s cooldown is real). Press
  Cheer whenever `Cooldowns.Cheer == 0` in Raid / Dungeon (opts.cheer). Count `Parry` events of my fighter. In the `move`
  section make the passive dummy untargetable (`u.arriveUntil = math.huge`) so the B1 FOLLOW patterns still measure the
  follow, and add one target: "an engaged pet ignores the walking character: zero Engage off while the character runs
  the random pattern next to a targetable dummy".
- [ ] **Step 2: Run the move + a quick raid check** — `SIM_BATTLE="quick only=move" $PY -3.12 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua', encoding='utf-8').read())"`:
  every `move` TARGET ok; then `only=raids seeds=2`: it runs and prints parries > 0 per raid (numbers are retuned in Task 12).
- [ ] **Step 3: Run the library users** — `$PY tools/smoke.py --quick --only p5battle_balance,p5dgn_balance`: they run
  (a balance MISS here is recorded for Task 12, not fixed now).
- [ ] **Step 4: Commit** — `test(balance): sim_battle trainer stands and times the Dash (skill rate), cheers (wave 6)`.

### Task 5: BattleService wiring: Cheer command, cooldowns in Start, engage service test

**Files:**
- Modify: `src/server/Services/BattleService.lua:118-127, 146-151` (header), `:3737` (`Cmd.ACTIONS`), the Start payload
  `Team.Cooldowns`, `:3921-3926` (leash comment)
- Modify: `tools/smoke_fight.lua:565-920` (`fight_engage_service`)
- Test: `tools/smoke_wave6.lua` scenario `w6_cheer_service` (server, booted)

**Interfaces:**
- Produces: BattleCommand `"Cheer"` (no arg); Start payload `Team.Cooldowns.Cheer`; the `Cheer` / `Parry` events reach
  clients in "Events" like every other event.

- [ ] **Step 1: Write the tests (failing).** `w6_cheer_service` (Review Focus 4): a dungeon encounter and a raid: the
  remote `BattleCommand("Cheer")` -> the sim boost (Cheering true) and the `Cheer` event to both party members;
  40 calls in 1 s -> exactly one accepted, the rest refused by the bucket / Cooldown, at most one rejected `Order` echo per
  step, one throttled "Cooldown" toast; junk args (`"Cheer", {1,2}`, a 200-char action, NaN) refused without error; a
  Ring run and a duel -> refused `NoCheer`; a spectator / a player in no battle -> refused; the Start payload carries
  `Team.Cooldowns.Cheer == 0`. Rewrite `fight_engage_service`: the pet engages an enemy 30 studs from the standing
  character; the character then walks the room for 8 s and nobody is leashed and the pet never disengages; a jump +
  run-off out of the zone removes the player by the presence check within `LeashSeconds + 3` (as before).
- [ ] **Step 2: Run, expect FAIL** — `$PY tools/smoke.py --quick --only w6_cheer_service,fight_engage_service`.
- [ ] **Step 3: Implement** `Cmd.ACTIONS.Cheer = "none"` (the existing ladder: type -> bucket -> present -> sim), add Cheer
  to the Start cooldowns, and rewrite the leash / engage comments (the sim no longer bounds an engaged pet: the floor does).
- [ ] **Step 4: Run, expect PASS** — the two scenarios + `p5svc_position_legit,p3bs_exploits`; `node tools/check.mjs`.
- [ ] **Step 5: Commit** — `feat(battle-service): Cheer command, cheer cooldown in Start (wave 6)`.

### Task 6: Find the podium and lock the trainer on it (Ring + PvP, server)

**Files:**
- Create: `src/server/Services/Podium.lua`
- Modify: `src/shared/Config.lua:65-87` (`OnPodium = "OnPodium"`), `src/server/Services/BattleService.lua` (`StartDuel`
  `:2399-2400`, `RingRun.startRound` `:3085`, `RingRun.afterBattle` `:3156`, `releaseParticipant` `:1684`, `finalize`,
  `Shutdown`, the battle tick)
- Test: `tools/smoke_wave6.lua` scenarios `w6_podium_find`, `w6_podium_lock` (server, booted)

**Interfaces:**
- Produces: `Podium.Lock(player, standCFrame) -> bool` (teleports, anchors the root, `OnPodium = true`, one toast per
  battle), `Podium.Release(player)` (idempotent), `Podium.IsLocked(player) -> bool`, `Podium.Tick()` (puts a root > 2 studs
  off back on its stand; drops locks whose character is gone), `Podium.Init(deps)` (CharacterAdded / PlayerRemoving).

- [ ] **Step 1: Write the tests (failing).** `w6_podium_find`: a Ring run's spawn stands on the pocket's `SpawnPad`
  (`SpawnPad` top within 3.5 studs under `run.Zone.Spawn`, inside its 7 x 7 footprint) and outside the 44-stud floor; each
  duellist's `duelStand` stands on a `ChallengePad` of that ring. `w6_podium_lock`: Ring round start -> root Anchored,
  `OnPodium == true`, at the SpawnPad; a scripted move of the root 6 studs away is undone within one tick; the round's End
  -> unanchored, attribute nil; the next round re-locks at the pad. A duel: both duellists locked on their pads; a forfeit
  releases both. Review Focus 2: death mid-round (Humanoid.Health 0) -> the new character is not anchored and `OnPodium` is
  nil; a disconnect clears the lock record; `BattleService.Shutdown()` releases everyone; a raid joiner and a dungeon
  member are never locked. The sim still gets the Move feed (the pet FOLLOWs to the floor edge near the pad when no enemy
  is left; no leash fires in a 90 s locked round).
- [ ] **Step 2: Run, expect FAIL** — `$PY tools/smoke.py --quick --only w6_podium_find,w6_podium_lock`.
- [ ] **Step 3: Implement** `Podium.lua` (plain Lua 5.1, same header style as the other Services), call `Lock` after the
  existing teleports in `StartDuel` and `RingRun.startRound` (teleport to `run.Zone.Spawn` first each round), `Release` in
  `RingRun.afterBattle`, `releaseParticipant`, `finalize`, `Shutdown`; `Podium.Tick()` in the battle loop; `Podium.Init`
  from `BattleService.Init`. Toast text exactly: "You're the trainer: cheer your pet on from the podium!".
- [ ] **Step 4: Run, expect PASS** — the two + `p3bs_duel,p4ring_flow` (or the scenarios that own the ring and duel flows in
  `smoke_p4_ring.lua` / `smoke_p3_battleservice.lua`); `node tools/check.mjs`.
- [ ] **Step 5: Commit** — `feat(battle): trainers stand locked on the podium in Ring and PvP (wave 6)`.

### Task 7: The avatar cheer (client): podium loop + one play per Cheer

**Files:**
- Create: `src/client/Controllers/TrainerCheer.lua`
- Modify: `src/client/Controllers/BattleController.lua` (the `Cheer` event handler next to `Handlers[EV.Dash]` `:4304`; the
  `OnPodium` attribute watch)
- Test: `tools/smoke_wave6.lua` scenario `client_w6_podium_cheer` (client)

**Interfaces:**
- Produces: `TrainerCheer.Play(character) -> bool` (invokes `Animate.PlayEmote("cheer")`; retries every 0.2 s for up to
  1 s while the pose is not standing; false when the rig has no `PlayEmote`), `TrainerCheer.StartLoop(character)` (play,
  wait 2.5-4 s, play...), `TrainerCheer.StopLoop()`.

- [ ] **Step 1: Write `client_w6_podium_cheer` (failing)** with a mock `Animate` holding a `PlayEmote` BindableFunction that
  records its calls: `OnPodium = true` on LocalPlayer -> "cheer" invoked within 0.3 s and again within 4.5 s; `OnPodium`
  nil -> no call for 6 s; a `Cheer` event whose owner is me -> exactly one call; a `Cheer` event of another owner -> none
  (each client plays only its own avatar; Roblox replicates it); no `Animate` / no `PlayEmote` -> no error, false; no Sound
  instance is created.
- [ ] **Step 2: Run, expect FAIL** — `$PY tools/smoke.py --quick --only client_w6_podium_cheer`.
- [ ] **Step 3: Implement** the module and the two hooks.
- [ ] **Step 4: Run, expect PASS** — + `client_fight_attack`; `node tools/check.mjs`.
- [ ] **Step 5: Commit** — `feat(battle-client): the trainer cheers on the podium and on Cheer up! (wave 6)`.

### Task 8: The Cheer up! button above the HP bar (PC + phone)

**Files:**
- Modify: `src/client/Controllers/HudController.lua:2932-2941` (`GetLayout().Vitals = { X, Y, W, H }`: the vitals card's
  gui-area pixel rect, nil when hidden), `src/client/Controllers/BattleController.lua` (`Hud.BuildActions` `:4902`,
  `Hud.Rebuild` `:5229`, `Hud.Update` `:5675`)
- Test: `tools/smoke_wave6.lua` scenarios `client_w6_cheer_button`, `client_w6_cheer_mobile`

**Interfaces:**
- Consumes: Task 3/5 (`Cooldowns.Cheer`, `Cheer` event, BattleCommand "Cheer"), Task 7 (`TrainerCheer.Play`).
- Produces: a battle HUD button named `Cheer` (text "Cheer up!", the battle HUD's neon button style and font sizes) shown
  only while my battle's Mode is `"Raid"` or `"Dungeon"` and I am a fighter; a cooldown sweep over `CheerCooldown`; an
  active glow for `CheerSeconds`; `BattleController.Cheer() -> bool`.

- [ ] **Step 1: Write the tests (failing).** `client_w6_cheer_button`: a Dungeon Start -> `Cheer` visible, its bottom edge
  8 px (+-2) above `HudController.GetLayout().Vitals.Y`, centred on the vitals card (+-2 px), not intersecting the vitals
  card, the hotbar or any `Hud.TouchRects` rect, fully on screen at 1920x1080 and 1366x768; a click sends exactly one
  `BattleCommand("Cheer")`, a second click during the cooldown sends nothing and shakes the button; the server's `Cheer`
  event starts the glow (5 s) and the sweep (20 s); a Ring or Duel Start -> not visible; End -> gone. `client_w6_cheer_mobile`
  (phone world): 844x390, 390x844, 749x388 with touch: same placement rules, the button at least 44 x 44 px, no overlap with
  the action cluster.
- [ ] **Step 2: Run, expect FAIL** — `$PY tools/smoke.py --quick --only client_w6_cheer_button,client_w6_cheer_mobile`.
- [ ] **Step 3: Implement** (layout in the same pass that lays out the action cluster; re-layout on the HUD's layout change
  signal or the existing `Hud.Rebuild` triggers).
- [ ] **Step 4: Run, expect PASS** — + `client_fight_dev,client_fight_dev_mobile,client_p5hud_pills`; `node tools/check.mjs`.
- [ ] **Step 5: Commit** — `feat(battle-hud): Cheer up! button above the HP bar in raids and dungeons (wave 6)`.

### Task 9: The parry flash and the sidestep draw (client)

**Files:**
- Modify: `src/client/Controllers/BattleController.lua` (the DODGED! callout `:3950`, `Handlers[EV.Dash]` `:4304`, a new
  `Handlers[EV.Parry]`)
- Test: `tools/smoke_wave6.lua` scenario `client_w6_parry_fx`

- [ ] **Step 1: Write `client_w6_parry_fx` (failing)**: a replayed `Parry` event on my fighter shows "PARRY!" (gold,
  `K.CALLOUT_PX`) once and a short ring flash on the pet; the following `Hit { miss = true, parry = true }` shows no
  "DODGED!"; a plain miss still shows "DODGED!"; the pet's dash draw follows the event's `dir` (the drawn pet moves along
  `dir`, dot > 0.9) even when `target` points elsewhere; no Sound instances; Low graphics: the callout only.
- [ ] **Step 2: Run, expect FAIL** — `$PY tools/smoke.py --quick --only client_w6_parry_fx`.
- [ ] **Step 3: Implement** (reuse `Fx.Number` and the existing flash helpers; colour `COLORS.Gold`).
- [ ] **Step 4: Run, expect PASS** — + `client_p7vfx_battle`; `node tools/check.mjs`.
- [ ] **Step 5: Commit** — `feat(battle-client): PARRY! flash, the dash draws the sidestep (wave 6)`.

### Task 10: The walk-in on every floor (root cause first)

**Files:**
- Test: `tools/smoke_wave6.lua` scenarios `w6_dgn_walkin_floors` (server, booted), `client_w6_walkin_floors` (client)
- Modify: where the evidence points (`src/client/Controllers/DungeonController.lua:3034-3046, 2170-2187, 2440-2490` and / or
  `src/server/Services/DungeonService.lua:960-995, 1137-1184`)

Read with the superpowers:systematic-debugging skill. What the code shows today: the walk-in starts only when ALL hold
(`DungeonController.lua:3043`): `S.Fade` is in `Out` / `Hold` when a `Corridor` / `Threshold` Run payload for room 1-4
arrives with a new key, and `R.walkPrepare` finds `Room_<n>` with a `Threshold` BasePart in the pocket
(`S.Pocket` or `R.findPocket()`: the nearest `Dungeons` child within 400 studs of the root). The server side
(`Dg.transit` -> `Fade`, then after `FADE.Out` `Dg.finishTransit` -> `Dg.enterRoom`: PlaceRoom, teleports, `sendRun`) has
no floor branch, and every room builder (`Hall/Cellar/Cave/Bridge/Throne`) adds a Threshold. So the tests must
discriminate these hypotheses, ranked:
- **H1 (most likely): it is "the second run of the session", not "floor 2".** The owner always plays floor 1 first.
  Per-run client state that survives `End` (`S.Pocket` + its door watches, `S.Fade` / `S.FadeSeq` / `S.PhaseKey`,
  `S.Walk` / `S.WalkSeq`, `S.Enter`, `S.Zoomed`) or a `fresh` detection that misses a new RunId can make the gate at
  `:3043` or `R.walkPrepare` fail in every later run.
- **H2: the Run payload loses the race with the client fade.** `R.fade` drops to `In` / clears on `FADE_SAFETY 3` s; if
  the server's room change (`PlaceRoom` of room + 1 in the styled tiers b / a, the teleports) takes long enough, or the
  Run payload beats the teleport so `R.findPocket()` sees the wrong place, the walk-in is skipped.
- **H3: styled rooms differ.** In styles b / a (floors 4-12) a dressed `Door_Entrance` / the room's pivot gives an
  `inward` under 0.5 stud or the Threshold under another parent.

- [ ] **Step 1: Write `w6_dgn_walkin_floors` (server)**: for floors 2, 5, 9 and 12 (and 1 as the control), a solo run
  through rooms 1-4: for each room the client receives `Fade` BEFORE the room's `Corridor` / `Threshold` Run payload, and
  that payload within `FADE.Out + FADE.Hold + 0.5` s of the Fade (mock clock and `os.clock` budget measured); the pocket
  holder is `workspace.Dungeons.Dungeon_<i>` with a child `Room_<n>` holding a `Threshold` BasePart and a `Door_Entrance`;
  `(Threshold.Position - Door_Entrance pivot)` flattened >= 0.5 stud; no member is inside the Threshold box at the payload.
  Then a SECOND run in the same server (floor 2 after a cleared floor 1) passes the same checks.
- [ ] **Step 2: Write `client_w6_walkin_floors` (client)**: with the `smoke_wave5_dungeon.lua` fixture pocket extended to
  `Room_1..4` (the real Threshold / door offsets of a 48 x 48 room and the 60 x 72 boss room), play run A (Floor 1:
  Hall -> rooms 1-4 -> End) then run B (Floor 2), C (5), D (9), E (12): every room of every run reaches
  `GetState().Walk == "Walk"` and ends Custom; plus the race cases: the Run payload 2.6 s after the Fade, and a Run
  payload that arrives before the teleport (the root still 500 studs away, teleported 0.1 s later).
- [ ] **Step 3: Run both, record which checks fail** — `$PY tools/smoke.py --quick --only w6_dgn_walkin_floors,client_w6_walkin_floors`.
  Write the confirmed root cause (the failing check, the variable / line, H1-H3 or a new one) into the commit message and
  the report. If nothing fails, add the instrumented case the evidence points at next (do not guess a fix).
- [ ] **Step 4: Fix at the source** (examples: reset the per-run walk / pocket / fade state on `End` and on a fresh run;
  have the fade wait for the room payload instead of `FADE_SAFETY` while a transit is pending; look the room up by the
  run's pocket index instead of distance). Keep `WALK_SAFETY` / `FADE_SAFETY` as the never-stuck guards.
- [ ] **Step 5: Run, expect PASS** — + `client_w5dgn_walkin,w5dgn_walkin_timeout,w5dgn_crossing,client_dgfix_flow,dgfix_flow_floor`;
  `node tools/check.mjs`.
- [ ] **Step 6: Commit** — `fix(dungeon): the room walk-in plays on every floor (<root cause>) (wave 6)`.

### Task 11: The camera never leaves the room

**Files:**
- Modify: `src/server/Services/DungeonBuilder.lua:2168-2188` (`clonePiece`: `CamMin` / `CamMax`), header `:14-35`
- Modify: `src/client/Controllers/DungeonController.lua` (`K.CAM_BIND = "NimbusDungeonCamBox"`, `K.CAM_MARGIN = 0.6`,
  `R.camBoxes()`, `R.camClamp()`, bind / unbind with the run; header "Camera")
- Test: `tools/smoke_wave6.lua` scenarios `w6_dgn_cambox` (server), `client_w6_cambox` (client)

**Interfaces:**
- Produces: every piece model placed by `clonePiece` carries `CamMin = origin + Vector3(-W/2, -2, -D/2)` and
  `CamMax = origin + Vector3(W/2, CEIL_Y, D/2)` (origin = `CFrame.new(pocket.Origin) * piece.CFrame`, pieces never rotate);
  `R.camClamp()` bound at `Enum.RenderPriority.Camera.Value + 1` while a run lasts.

- [ ] **Step 1: Write `w6_dgn_cambox` (server)**: floors 1, 2, 5, 9, 12: the hall, every corridor, rooms 1-4 and the
  treasure carry `CamMin` / `CamMax`; each box holds its piece's floor (`Base`) footprint and its `Ceiling` part's bottom
  is within 0.3 stud of `CamMax.Y`; boxes of consecutive pieces touch at the doorway (gap <= 0.1).
- [ ] **Step 2: Write `client_w6_cambox` (client)** with a fixture: a 15-deep corridor box joined to a 48 x 48 room box.
  Per frame the test sets `Camera.Focus` and `Camera.CFrame` (as the camera scripts would) before `Mock.Step`: a boom that
  leaves the room (14 studs up and back over a wall) ends inside the box minus `CAM_MARGIN`, on the SAME ray (the
  LookVector unchanged within 1e-4, the position on the focus -> camera line); a boom fully inside is untouched; over the
  ceiling: Y clamped under `CamMax.Y - 0.6`; Review Focus 5: walking the focus from the corridor into the room over 30
  frames, the camera never jumps more than the focus move + 1 stud between frames; a boom < 1 stud (first person) and a
  `Scriptable` camera (walk-in / entrance) are untouched; `End` unbinds `NimbusDungeonCamBox`.
- [ ] **Step 3: Run, expect FAIL** — `$PY tools/smoke.py --quick --only w6_dgn_cambox,client_w6_cambox`.
- [ ] **Step 4: Implement.** `R.camBoxes()` caches, per Run payload, the boxes of the pieces under `S.Pocket` (the current
  room's model children + its corridor + the hall / treasure when present). `R.camClamp()`: focus `F`, camera `C`,
  `boom = C - F`; for the box that contains `F` compute the ray's exit `t` (slab method, inset by `CAM_MARGIN`); if the
  exit point lies inside another cached box, continue from there with that box (at most 2 hops); `t = min(1, t)`;
  write `CFrame.new(F + boom * t) * (C - C.Position)` only when `t < 1`. A focus in no box (a teleport frame) = no clamp.
  `ZOOM_RUN 14` stays.
- [ ] **Step 5: Run, expect PASS** — + `client_w5dgn_camera,client_w5dgn_walkin,p5dgn_world,bug5_dungeon` (the scenario
  names in `smoke_bug5_dungeon.lua`); `node tools/check.mjs`.
- [ ] **Step 6: Commit** — `fix(dungeon-camera): the camera stays inside the room, corridor and boss room (wave 6)`.

### Task 12: Balance re-measure and retune (last code task)

**Files:**
- Modify (data only, if the numbers say so): `src/shared/BattleCatalog.lua` (boss `HpPerPlayer` / `BaselineDps`, raid
  `BossHp`, ring / duel numbers), `tools/smoke_bug2_battle.lua:404` and any balance pin that names the old EngagePull
  ruling; `tools/sim_battle.lua` comments `:995`, `:1041`
- Report: `.superpowers/bugs-2026-10-24/wave6-balance-report.md` (outside the worktree, in the main Nimbus folder)

- [ ] **Step 1: Measure** — `SIM_BATTLE="full only=raids,duels,ring,dungeon,fighter,training,move" $PY -3.12 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua', encoding='utf-8').read())"`
  (one run, save the output to the scratchpad). Read every TARGET line. The sensitive cell is the lava golem M5 8p
  (>= 60 % of seeds); bug #2 must hold: every weak solo (< half the boss's BaselineDps) LOSES.
- [ ] **Step 2: Retune with data**, smallest data changes first, one knob at a time, re-running only the affected section
  (`seeds=16` for the golem cell). Anti-goals: no boss below 100 s for 16 dodgers, no weak solo win; if pets that never
  retreat make a boss trivial, raise its `HpPerPlayer` / damage, never the parry window. Record each change with the
  before / after numbers.
- [ ] **Step 3: Pins** — update the balance pins in the smoke files to the measured values; run
  `$PY tools/smoke.py --quick --only p5battle_balance,p5dgn_balance,bug2_battle` (the scenario names in those files).
- [ ] **Step 4: Write the balance report** (table: section, target, before wave 6, after, retune) and commit —
  `balance(battle): re-measured with the timed-Dash trainer; <changes> (wave 6)`.

### Task 13: Docs, the one full smoke, the report

**Files:**
- Modify: `BUILD_STATE.md` (settled wave 6 decisions + the Builder decisions above), `ARCHITECTURE_V3.md` (the Phase 5
  fighter contract lines `:2068`, `:2109`: Engage numbers out, Parry / Cheer in)
- Report: append to `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.superpowers\bugs-2026-10-24\wave6-report.md`

- [ ] **Step 1:** `node tools/check.mjs` (0 errors), then the ONE full run `$PY tools/smoke.py --quick` (~20 min, nothing
  else heavy running). Record pass / fail counts; fix any failure with its owning task's test first.
- [ ] **Step 2:** Append to the report: what changed per task, files, tests run with counts, the confirmed walk-in root
  cause, the balance table link, Gemini's input if any was asked, and the owner's Studio checks:
  Ring + PvP: can't walk off the podium (and the podium IS the pink block: confirm or point at it), the avatar cheers,
  pets reach every enemy; dungeon floors 1, 2, 5, 9, 12: walk-in plays on each, the camera never shows outside a room
  (try the Bridge rooms and the boss room), Cheer up! sits above the HP bar, cheers, glows 5 s, 20 s cooldown; raid: pets
  keep fighting while you run, Cheer up! works, a weak solo still loses; a timed Dash shows PARRY! and staggers.
  Owner questions: R6 / custom cheer if `PlayEmote` is missing; a gamepad binding for Cheer up!; the podium colour.
- [ ] **Step 3: Commit** — `docs(wave6): build state, contract, report`.
