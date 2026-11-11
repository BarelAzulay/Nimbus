# Feel Balance Implementation Plan (Standoff 8 and the real cast ON, sim back to 67 of 67)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Also name and use superpowers:test-driven-development (every task writes its failing scenario first), superpowers:verification-before-completion (run the commands, read the counts) and roblox-dev:roblox-security (the server alone decides what is hit).

**Goal:** Ship `Config.Battle.Feel.Melee.Standoff = 8` and `Special.RealCast = true` with `SIM_BATTLE=full` at 67 of 67 targets, by fixing the two causes the sim measured (the server ignores the dash; the cast freezes the meter) before touching any boss number.

**Architecture:** One server rule in `BattleSim`: a melee unit has a *body point* that follows the same dash timeline the client already draws (at the bite point while it strikes or flurries, at the rest spot otherwise). Every area test, the boss's "nearest" pick and a melee caster's ELEMENT origin use the body point; single-target reach tests stay as they are (DPS unchanged). One meter rule: what the meter gains during a real cast is carried into the next cycle. Then a measured fit with tier knobs, at 48 seeds.

**Tech Stack:** Luau in plain Lua 5.1 syntax (Rojo); `py -3.12 tools/smoke.py --quick --only a,b,c` (lupa); `SIM_BATTLE="full"` or `"quick only=raids seeds=48"` with `py -3.12 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"` from the repo root; the new instrument `py -3.12 tools/sim_measure.py "raid <boss> <tier> <players> <seeds> <standoff> <on|off>;..."`; `node tools/check.mjs`; `py -3.12 tools/count_locals.py`.

**Spec:** `docs/superpowers/specs/2026-11-10-battle-feel-design.md` (the feel), the owner's pick "Balance pass" (2026-11-10 morning), and the section "What the sim measured" below (the cause; this plan argues from it). Ledger: `.superpowers/battle-feel/LEDGER.md`; evidence: `.superpowers/battle-feel/evidence/`.

## Global Constraints

- Work only in `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\feel-balance\nimbus-climb`, branch `feel-balance` (battle-feel 163a2f4). PowerShell: `Set-Location -LiteralPath` first. Files UTF-8 without BOM. Stage by name, commit with `git commit -F <file>`, push `feel-balance`. Never merge into main or lobby-shop, no uploads, no deleting folders, no force-push, never print API keys.
- Route (`py -3.12 tools/pick_model.py --build balance`, raised one level for Tasks 1-2 because they change a server rule): Tasks 1-2 build Opus 5.5 high, review Fable 5.1 high; Tasks 3-4 build Opus 5.5 medium, review Fable 5.1 medium; gate Fable 5.1 high.
- Y2: the server owns reach, hits, damage and the body point; the client only draws. Nothing a client sends moves a body point.
- Duels stay fair: the body point, the ELEMENT origin and the meter carry are the same rule for every unit on both sides (`p5svc_duel_fair` green; mirror duels 40-60% overall, 30-70% per stage).
- Off switches restore 163a2f4 exactly: at `Melee.Standoff = 0` no unit has a body point (a seeded fight's event log is identical); at `Special.RealCast = false` no carry.
- Memory: about 4.7 GB free, the whole smoke peaks near 3.5 GB. Before the WHOLE suite or a full sim: `(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*smoke.py*' -or $_.CommandLine -like '*sim_battle*' -or $_.CommandLine -like '*sim_measure*' }).Count` is 0 and free memory >= 4 GB; otherwise wait (check every 5 minutes, up to 40). Sims one at a time.
- Before each commit: `node tools/check.mjs` shows 0 errors; `py -3.12 tools/count_locals.py src/shared/BattleSim.lua` shows none at 200 (group the new helpers in one table `Strike` if it nears 190).
- Every changed number gets one line in the ledger: old -> new, the cell that asked for it, the 48-seed reading before and after.

## What the sim measured (2026-11-10, `tools/sim_measure.py`, branch at 163a2f4)

The instrument reproduces the gate file (lava_golem Max solo 0/12 at 107 s; storm_titan Starter 3 teams 3/12 at 238 s).

**The task's guess "melee DPS lost to travel" is not the cause.** The server models no travel: at Standoff 8 it grows the rest spot and every hit test alike. Melee plain hits per second are unchanged (lava Max 1.87 -> 1.90, storm Starter 1.08 -> 1.09) and damage dealt per floor-second moves under 2%.

**Cause S1 (raids easier): the hitbox stays at the rest spot while the pet is drawn biting.** The melee pet's server position moves 7-8 studs out (lava Max 14.0 -> 21.9 studs from the boss centre, the ranged ring is at 21.7; storm Starter 10.4 -> 18.1; hydra Mid 12.2 -> 19.3). The client draws it at the bite point for 0.9 s of every attack (In 0.30, Bite 0.08, Hold 0.12, Back 0.40) and all the time under `FlurryBelow` 0.75 s, but the server tests boss areas at the rest spot:

| cell (cast off) | seeds | win at Standoff 0 | win at Standoff 8 | boss area damage on melee per floor-s | notes |
|---|---|---|---|---|---|
| lava_golem Max solo | 36 | 6/36 (17%) | 17/36 (47%) | 15777 -> 6700 (-58%) | eruption 0.38 -> 0.04 hits per telegraph, zones -63% |
| lava_golem Max 3 teams | 36 | 15/36 (42%) | 20/36 (56%) | 15700 -> 7602 (-52%) | eruption 0.90 -> 0.09 |
| storm_titan Starter 3 teams | 36 | 11/36 (31%) | 21/36 (58%) | 6 -> 5 (small numbers, coarse) | chain 0.47 -> 0.40, melee KOs 2.39 -> 1.83, all player KOs 7.3 -> 5.8 |
| shadow_hydra Mid 3 teams | 48 | 16/48 (33%) | 39/48 (81%) | 290 -> 225 (-22%) | boss basic on melee -13% (the melee pet stops being the nearest) |
| shadow_hydra Max 3 teams | 36 | 11/36 (31%) | 33/36 (92%) | 17049 -> 12233 (-28%) | fangs 0.25 -> 0.18, pulse 0.52 -> 0.38, minion damage -45% |
| frost_wyrm Max 3 teams | 36 | 20/36 (56%) | 27/36 (75%) | 15998 -> 11556 (-28%) | blizzard 0.57 -> 0.41 |

Fight lengths barely move (lava Max 3 teams 197.6 -> 190.8 s): the pets do not hit harder, they are hit less.

**Cause S2 (dungeons and duels harder): a melee caster's ELEMENT is measured from the rest spot.** `castElement` centres a Circle (Quake, Radiance, radius 8) on a melee caster; from 7.5 studs past the old spot it reaches nothing. ELEMENT is 9-25% of a fighter's damage (plus Quake's stun and Radiance's meter). Evidence `t2-sim-full-standoff8.txt`: S1 room 2 55 -> 30%, eased room pebble_pup 83%, mirror duels worst stage 72%, Earth form damage 34657 -> 24918.

**Cause C1 (raids longer): the real cast freezes the meter.** While casting, the meter stays full and gains nothing, then drops to 0. Specials per fighter-minute fall 10.51 -> 9.97 (storm Max 8 teams, 12 seeds, -5.1%) and 6.06 -> 5.67 (frost High 3 teams, 36 seeds, -6.4%); damage out -4.0%; the storm Max 8-team fight runs 237.0 -> 245.2 s (over the 240 s cap). Stuns broke 21 of 1160 casts (1.8%).

**Noise:** the official 12-seed cells carry about +-14 points. Baseline cells already sit near an edge at more seeds (lava Max solo 0/12 but 6/48 = 12.5%; frost Max 3 teams 42% at 12 seeds, 56% at 36). The earlier "non-monotonic HP tries" were this noise. The fit below reads 48 seeds.

## The decisions (each with its reason)

1. **The strike is real on the server (body point).** Reason: it removes S1 at the source and makes the picture true (a pet drawn inside the eruption is hit, a pet drawn hopping back is safe). Gemini (gemini.google.com, the API key returned 402) picked the same option over a per-tier refit or a client-only standoff, and named the risk: a 10 Hz tick can miss a short window. Answer: the window is at least 0.55 s (5 ticks), and `Validate` rejects a shorter one.
2. **A melee caster's ELEMENT grows from its bite point.** Reason: removes S2; at Standoff 0 the bite point is the rest spot, so nothing changes there.
3. **The meter carries its gain through a real cast; attack time is NOT refunded.** Reason: the carry is invisible and stops a long cast from being taxed twice (late special and a starved next one). I first wanted to refund the lost attack time with quicker next strikes; Gemini argued a dodgeable cast should cost something and sped-up strikes look jittery, and proposed trimming boss HP 4%. Kept from Gemini: no attack refund. Kept from me: the carry, and the trim only where the 48-seed reading asks for it (Task 3), never a flat 4%.
4. **Shadow Hydra gets no rest rule of its own.** Reason: its cells moved because of S1 (area and minion hits), not because of the necks; at Standoff 8 the rest spot sits 8 studs outside the old one, so the generic `MinGap` 1.5 test decides the dash. Task 2 adds a client check; if the gap is still under 1.5 the bite stays today's Strike and the server body point applies all the same.
5. **No per-boss HP nudge until Tasks 1-2 are measured**, and then at most 4 cells (the stop rule in Task 3).

## Review Focus

1. Two melee units striking each other (every duel): the body points must not cross; each advances at most half the free gap; a Circle ELEMENT still lands in a melee mirror at Standoff 8.
2. The strike target dies, benches or swaps mid-window: the body point returns to the rest spot on that tick.
3. Dash, stun, cast or knock during a window: the body point is the real position at once; today's i-frames unchanged.
4. `BattleCatalog.Damage.Standoff` changed at run time (the sim and the tests set it to 0 / 8 after load): the strike rule reads it live; at 0 the event log is identical to 163a2f4.
5. A slowed attacker crossing `FlurryBelow` (interval / slow): it stops flurrying and gets per-attack windows, no window left open forever.

---

### Task 1: The body point (server) and the scripted player that reads it

**Files:**
- Modify: `src/shared/BattleCatalog.lua` (Damage block near line 242, `Validate` near 2573)
- Modify: `src/shared/BattleSim.lua` (helpers 436-455, `nearestEnemy` 2028, `standoffOf` 3518, `npcStep` wind-up 3666-3672, the fighter's auto-attack in `fighterStep` 3855, the Dash command, `Snapshot` 1566)
- Modify: `tools/sim_battle.lua` (the scripted `Player`: its "covers my fighter" tests and `castCovers`)
- Test: `tools/smoke_feel_dash.lua`, `tools/smoke.py` line 538 (add the new names to the `feel_standoff_*` list)

**Interfaces:**
- Produces: `BattleCatalog.Damage.Strike = { In = 0.30, Bite = 0.08, Hold = 0.12, Back = 0.40, FlurryBelow = 0.75, Out = 0.5 }`, read from `Config.Battle.Feel.Melee` (`Out` is new: the share of `In` and of `Back` that counts as "in"; reason: half-way through the dash the pet is drawn nearer the bite point than the rest spot).
- Produces: per-unit fields `u.bx`, `u.bz` (the body point, equal to `u.x`, `u.z` when out), refreshed once per step before any unit acts; `Snapshot` units carry `bx`, `bz` (rounded like `x`, `z`) only while they differ from `x`, `z`.
- Produces: `strikeOpen(self, u, target, biteAt)` and `strikeAdvance(D, u, target) -> number` (local functions in one `Strike` table).

Rules the tests pin:
- Only a unit with `standoffOf(D, u) > 0` has windows. A window runs from `biteAt - In * Out` to `biteAt + Bite + Hold + Back * Out` (0.15 s before to 0.40 s after the drawn bite).
- `biteAt` is `u.windAt` for an NPC wind-up, and `t + Strike.In` for a fighter's plain hit (the client holds that Hit `Melee.In`, `BattleController` line 309).
- Flurry: when `u.interval / slow < FlurryBelow` and the unit is attacking a target in reach, the window stays open until the unit stops attacking.
- `strikeAdvance` = `min(standoff, gap)` where `gap = dist(rest, target rest) - (u.range + target.radius - 0.5)`, never negative; halved (`gap * 0.5`) when the target also has a standoff.
- In a window the body point is the rest spot moved `strikeAdvance` toward the target's rest spot. Out of a window, or stunned, dashing, casting, benched, down, or the target gone: the rest spot.
- `inCircle`, `inLine`, `inCone` test `u.bx, u.bz`; `nearestEnemy` measures to `bx, bz`. Reach tests for single-target hits keep `u.x, u.z` and the standoff (scenario `feel_standoff_dps` stays green untouched).

- [ ] **Step 1: Write the failing scenarios** in `tools/smoke_feel_dash.lua`, with `BattleCatalog.Damage.Standoff = 8` set inside each and restored after:
  - `feel_strike_body`: an NPC melee unit (range 3.5) winding up at a boss of radius 6. 0.2 s before `windAt`: `bx == x`. From `windAt - 0.15` to `windAt + 0.40`: the body is 8.0 +- 0.1 studs nearer the boss centre than the rest spot. At `windAt + 0.5`: `bx == x` again.
  - `feel_strike_area`: a boss `Self` circle of radius 15 resolved while the melee pet is in a window hits it (1 Hit event with `tele`); the same telegraph resolved 0.3 s after the window closed hits nothing; a ranged pet at 21.7 studs is not hit in either case.
  - `feel_strike_flurry`: interval 0.53 s: `bx ~= x` on every one of 50 consecutive steps while attacking; with `slowMult` making interval / slow 0.9 the body returns to rest between attacks.
  - `feel_strike_fighter`: a team fighter's plain Hit at time h: body in from `h + 0.15` to `h + 0.70`.
  - `feel_strike_gone`: the target is KO'd mid-window: on the next step `bx == x`, `bz == z`.
  - `feel_strike_dash`: a legal Dash command mid-window: the same step `bx == x`; the i-frames end at the same time as with Standoff 0.
  - `feel_strike_mirror`: two melee units striking each other, rest spots 13 studs apart: both in a window, their body points are 5.0 +- 0.6 apart and have not crossed (the dot product of body-to-body and rest-to-rest is positive).
  - `feel_strike_nearest`: a boss with a melee pet resting at 21.9 studs and a ranged pet at 21.7: while the melee pet is in a window the boss's basic picks the melee pet.
  - `feel_strike_off`: with Standoff 0, a 60 s seeded raid (storm_titan Starter, 3 teams, seed 7) produces an event log whose hash equals the one recorded from 163a2f4 (record it in this step, before any code change), and no snapshot unit has `bx`.
  - `feel_strike_wire`: `Snapshot` carries `bx`, `bz` for a unit in a window and omits them otherwise.
  - Rewrite `feel_standoff_zone` to the new rule (a zone under the bite point ticks a striking pet, not a resting one); name the rewritten assertions in the commit body.
- [ ] **Step 2: Run them RED:** `py -3.12 tools/smoke.py --quick --only feel_strike_body,feel_strike_area,feel_strike_flurry,feel_strike_fighter,feel_strike_gone,feel_strike_dash,feel_strike_mirror,feel_strike_nearest,feel_strike_off,feel_strike_wire,feel_standoff_zone`. Expected: all fail except `feel_strike_off`.
- [ ] **Step 3: Build** `Damage.Strike` and its `Validate` lines (`In`, `Bite`, `Hold`, `Back` in 0..2, `FlurryBelow` 0..3, `Out` 0.25..1, and `In * Out + Bite + Hold + Back * Out >= 0.3`: Gemini's tick-aliasing risk), the `Strike` helpers, the per-step refresh of `bx`, `bz`, the two `strikeOpen` call sites, the three area helpers, `nearestEnemy`, `Snapshot`. No RNG call in any of it.
- [ ] **Step 4: Teach the scripted player** in `tools/sim_battle.lua`: wherever it tests a telegraph, a lethal area or `castCovers` against its fighter, use `bx, bz` when the snapshot carries them (a person sees the pet inside the ring).
- [ ] **Step 5: Run GREEN** the Step 2 list, then the regression lists one at a time: `feel_standoff_rest,feel_standoff_dps,feel_standoff_wire`; `feel_cast_queue,feel_cast_dodge,feel_cast_break,feel_cast_wire,feel_cast_simdodge,feel_cast_determinism`; `p5svc_commands,p5svc_position,p5svc_position_legit,p5svc_duel_fair,p5svc_raid,p5svc_ring,p5svc_encounter`. Expected: 0 failed in each.
- [ ] **Step 6: Measure** (one run): `py -3.12 tools/sim_measure.py "raid lava_golem Max 1 48 8 off;raid lava_golem Max 3 36 8 off;raid storm_titan Starter 3 36 8 off;raid shadow_hydra Mid 3 48 8 off;raid shadow_hydra Max 3 36 8 off;raid frost_wyrm Max 3 36 8 off"`. Expected: see "Expected cells". Paste the six win lines into the ledger.
- [ ] **Step 7: Commit and push** (`node tools/check.mjs` 0 errors first).

### Task 2: ELEMENT from the bite point, the meter carry, the knobs ON

**Files:**
- Modify: `src/shared/BattleSim.lua` (`castElement` 2852-2986; `castSpecial` / `fireCast` / `cancelCast` 2696-2825; the meter gains in `applyDamage` 1852 and the per-step meter lines)
- Modify: `src/shared/Config.lua` line 558-563 (`Melee.Standoff = 8`, `Melee.Out = 0.5`, `Special.RealCast = true`, `Special.Carry = true`) and the comment block 546-556
- Modify: `src/shared/BattleCatalog.lua` (`Damage.SpecialCarry` from `Special.Carry`, `Validate`)
- Modify: `src/client/Controllers/BattleController.lua` (a melee unit's `Element` event plays the same dash-in as a bite when the gap >= `MinGap`)
- Test: `tools/smoke_feel_dash.lua`, `tools/smoke_feel_tempo.lua`, `tools/smoke.py` lines 538-539

**Interfaces:**
- Consumes: `Strike.strikeAdvance(D, u, target)` and `strikeOpen` from Task 1.
- Produces: `BattleCatalog.Damage.SpecialCarry` (boolean); field `u.meterCarry` (number, 0 outside a cast).

Rules the tests pin:
- `castElement` by a unit with a standoff: the origin of Cone, Line and Circle is the caster's bite point (rest moved `strikeAdvance` toward the aim target), targets are tested at their body points, and the cast opens a window (`biteAt = t`).
- While `S_CASTING` with `SpecialCarry`, every meter gain (passive, on hurt) goes to `u.meterCarry`; `fireCast` sets `u.meter = min(MeterMax, u.meterCarry)` and clears the carry; `cancelCast` clears the carry (the meter is still full).

- [ ] **Step 1: Write the failing scenarios:**
  - `feel_element_origin` (Standoff 8): a melee caster with Quake (Circle, radius 8) resting at reach from one enemy: the cast hits it (today: 0 Hit events). A melee Cone caster facing three enemies in a fixed layout hits the same unit ids as the same layout at Standoff 0.
  - `feel_element_mirror` (Standoff 8): two melee Circle casters in a duel at rest reach: each cast hits the other.
  - `feel_cast_carry`: Blast (0.9 s) with no damage taken: the meter right after the fire is 5.4 +- 0.1 (6 per second x 0.9); with one hit taken during the cast 7.4 +- 0.1; a stun during the cast: `CastBreak`, meter 100, carry 0; with `SpecialCarry = false` the meter after the fire is 0.
  - `client_feel_dash_element`: a melee unit's `Element` event at Standoff 8 schedules one DashIn / DashBack; at Standoff 0 with a gap under 1.5 none.
  - `client_feel_dash_hydra`: at Standoff 8 the gap from a melee pet's rest spot to the Shadow Hydra's box is >= 1.5 (the dash plays). If it is not, change this scenario to assert today's Strike and note it in the ledger (decision 4).
- [ ] **Step 2: Run them RED**, build, run them GREEN, then the Task 1 lists again (the Config flip to 8 / true must not break any: tests that assumed the shipped 0 / false set their own value).
- [ ] **Step 3: Measure the cast:** `py -3.12 tools/sim_measure.py "raid storm_titan Max 8 12 8 on;raid frost_wyrm High 3 36 8 on"`. Expected: specials per fighter-minute within 2% of 10.51 and 6.06; storm Max 8 teams under 242 s.
- [ ] **Step 4: Commit and push** (check.mjs 0 errors; ledger line with the numbers).

### Task 3: The fit (measured, 48 seeds, tier knobs only)

**Files:**
- Modify: `src/shared/BattleCatalog.lua` (RaidTiers 1948-1951, bosses 1866-1900) only as the procedure allows
- Evidence: `.superpowers/battle-feel/evidence/fb-*.txt` (every run's output)

Procedure, one sim at a time:

- [ ] **Step 1: Read the whole board.** `SIM_BATTLE="full"` -> `fb-full-1.txt`. Then `SIM_BATTLE="quick only=raids seeds=48"` -> `fb-raids48-1.txt`.
- [ ] **Step 2: Judge each raid cell on its 48-seed rate**, not the 12-seed one. A cell asks for a change only when the 48-seed rate is outside the widened band (solo > 20%, 3 teams outside 20-60%, 8 teams < 65%) or the official 12-seed target fails twice in a row. Reason for the 5-point widening: baseline cells already read 12.5-17% and 56% at 36-48 seeds while passing at 12.
- [ ] **Step 3: Knobs in this order**, one change per round, then re-read only the touched cells at 48 seeds:
  1. `Damage.Strike.Out` (0.5; allowed 0.35-0.75; step 0.1). Use when the melee-fighter cells of two or more bosses are off in the same direction. Reason: it is the one number that says how long a dashing pet counts as "in".
  2. `RaidTiers[tier].SoloHit` (1.45 / 1.17 / 1.14 / 1.08; step 0.03, at most +-0.09). Use when only the solo cells of a tier are high.
  3. `RaidTiers[tier].HpSeconds` (120 / 98 / 112 / 127; step 3%, at most +-6%). Use when a tier's group fights leave 100-240 s or its trained 8-team fight passes 240 s (the real cast's remaining cost: about 0.4 s of plain attacks per special).
  4. A boss's `HpTier[i]` (step 3%, at most +-6%). Last, and at most 4 cells in the whole fit.
- [ ] **Step 4: The monotonic check.** After a change, the touched cell's 48-seed rate must move the expected way (more HP or more hit: the win rate does not rise by more than 7 points, one standard error). If it does, revert the change, re-read that cell at 96 seeds and decide from that.
- [ ] **Step 5: The other boards** (after the raids hold): `only=duels`, the dungeon rows and `only=progress` at their own seed counts. Expected to pass from Tasks 1-2 alone. If one target fails, change one number in its own block of `BattleCatalog` (name it and the reason in the ledger); never a pet stat, never a duel-only rule.
- [ ] **Step 6: Stop rule.** Done when `SIM_BATTLE="full"` reads 67 of 67 twice in a row with no change between (`fb-full-final-a.txt`, `-b.txt`) and every raid cell's 48-seed rate is inside the widened band. Stop and report instead (no more nudges) when: 3 rounds on one cell did not bring it in, or a fifth `HpTier` cell would be needed, or a target outside raids needs a second number. That means a cause is still open; write what the instrument shows for that cell.
- [ ] **Step 7: Commit and push** each round that changes a number (check.mjs 0 errors; the ledger line per number).

### Task 4: The gate

- [ ] **Step 1:** `node tools/check.mjs` 0 errors; `py -3.12 tools/count_locals.py src/shared/BattleSim.lua src/client/Controllers/BattleController.lua` none at 200.
- [ ] **Step 2:** the WHOLE smoke (memory rule first): `py -3.12 tools/smoke.py`. Expected: 0 failed; the check count is 27,878 plus the new scenarios' checks.
- [ ] **Step 3:** `SIM_BATTLE="full"`: 67 of 67; no raid fight over 240 s; no timeouts. Save as `gate-sim-full-feel-balance.txt`.
- [ ] **Step 4:** update the `Config.Battle.Feel` comment block, `brain.md` (one paragraph: the body point, the carry) and the ledger; commit and push. The owner's Studio check (a melee pet biting inside a Lava Golem eruption is hit; one hopping back is not; a Quake cast lands) stays for the main session.

## Expected cells

After Tasks 1-2, before any number changes. Exposure = share of time a melee attacker counts as "in": 100% under `FlurryBelow` (stormfang, 1.9 hits per second), about 59% for a slow attacker (aurora_fox, 0.55 s of every 0.93 s). Each cell should land between its two measured ends, near the Standoff 0 end for flurry fighters.

| cell (48 or 36 seeds) | Standoff 0 | Standoff 8 today | expected after Task 1 |
|---|---|---|---|
| lava_golem Max solo | 12.5% (6/48) | 47% | 12-20% |
| lava_golem Max 3 teams | 42% | 56% | 40-50% |
| shadow_hydra Max 3 teams | 31% | 92% | 30-45% |
| frost_wyrm Max 3 teams | 56% | 75% | 50-60% (a baseline edge cell: the likely first `HpTier` nudge) |
| storm_titan Starter 3 teams | 31% | 58% | 35-48% (slow attacker, 59% exposed) |
| shadow_hydra Mid 3 teams | 33% | 81% | 35-55% (ranged fighter; the melee pet fights only after a swap) |
| S1 room 2, eased room, mirror duel stages | 55%, >= 95%, 30-70% | 30%, 83%, 72% | back in band (ELEMENT lands again) |
| storm_titan Max 8 teams, real cast | 237.0 s | 245.2 s (cast on, measured at Standoff 0) | 238-242 s; `HpSeconds` Max -3% if over 240 |
| Ring 5 (band 4-9 min) | 4.3 | 4.9 (Standoff), 4.0 (cast) | 4.2-4.8 |

These are estimates from the two measured ends, not readings. Task 1 Step 6 and Task 2 Step 3 replace them with readings.

## Open questions for the owner (the build does not wait for them)

1. At Standoff 8 a melee pet rests on the same ring as a ranged one (Lava Golem: 21.9 and 21.7 studs). With the body point it is in danger only while it strikes. Is that the feel you want, or should melee rest closer (Standoff 5-6)? My pick: keep 8, see it in Studio.
2. The real cast keeps a small cost (about 0.4 s of plain attacks per special). Gemini wants the cost kept; I agree. Say so if specials should instead be fully free.

## Self-review

- Spec coverage: both knobs ON (Task 2), the cause before numbers (Tasks 1-2 before 3), seeds 48 and a stop rule (Task 3), the hydra rest rule (decision 4, Task 2), raid fights under 240 s (Task 3 knob 3, Task 4), duels fair (Review Focus 1, `feel_strike_mirror`, `feel_element_mirror`, `p5svc_duel_fair`), a reason per number (Global Constraints).
- Review Focus: 1 -> `feel_strike_mirror`, `feel_element_mirror`; 2 -> `feel_strike_gone`; 3 -> `feel_strike_dash`; 4 -> `feel_strike_off`; 5 -> `feel_strike_flurry`.
- Names: `Damage.Strike`, `Strike.Out`, `strikeOpen`, `strikeAdvance`, `bx` / `bz`, `Damage.SpecialCarry`, `u.meterCarry` are used the same way in every task.
- Not measured here: the body point itself (no prototype was built; the expected cells are brackets), and dungeon or duel cells with the instrument (it has a raid mode only).
