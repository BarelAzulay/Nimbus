# Battle feel: melee dashes, centre aim, weighty specials

Date: 2026-11-10. Status: Claude's picks, built in sleep mode behind Config knobs (the owner did not answer the pitch
page https://claude.ai/artifact/TUTFKZTAsqMggwQp2imrqF; source `.superpowers/battle-feel/pitch/page.html`, ledger
`.superpowers/battle-feel/LEDGER.md`). Every decision below is one knob in `Config.Battle.Feel`, so the owner can
change or switch any of them off in the morning without a code change. Builds on
`docs/superpowers/specs/2026-11-01-attack-fx-design.md` and `2026-10-23-pet-attack-vfx-design.md`, whose readability,
budget and art rules still hold.

## Why

The owner's words (2026-11-09, verbatim): "i want the melee pets to work in a way that they attack from range and each
attack they engage, hit the enemy and get back again, the reason is for making also the melee short range pet's attacks
and abilities be visible and easy to catch and watch for the player. and another thing, make the attacks aim for the
center of the enemy for example if a player fight in raid boss the boss is big so make the attacks and abilities hit at
the center of the boss and not the ground for better visualise.. and also i want to make the special attacks slower for
best enjoy from the quality of them, (a bit longer charge, slower ability move, and longer effect duration)".

## What the code does today (read on the battle-feel tree, frost-wyrm 38cadc6)

| Thing | Today | Where |
|---|---|---|
| Melee pets | `Attack = "Melee"` profiles have Range 4-5. An NPC walks to an orbit at `reach - 0.5` (about 2 studs of gap) and stays; the engaged player fighter stops at the same `reach - 0.5`. The hit is the `Strike` leap pose, front edge to near edge, 0.45-0.9 s, with a 0.05 s freeze at the impact. Nothing moves the model but the pose. | `BattleCatalog` 185-202; `BattleSim` 3506-3537, 3665-3685; `AttackFx` 3041-3103 |
| When a hit lands | The server applies damage at its 0.1 s tick and sends `Hit`; the client draws 0.12 s behind and starts the effect on arrival with the impact due when the event plays. NPC basics send `Windup` (`at` = the hit's sim time, 0.45 s ahead); the player's own fighter has no wind-up. A ranged shot's number may be held up to `FX_LATE_MAX` 0.3 s for its flight. | `BattleSim` 3533-3537; `BattleController` 249, 296, 3466-3497, 4868-4874, 9451-9496 |
| Aim point | Every burst, swipe, beam end and projectile end goes to the target model's **pivot** (`pointOf`). A pet's pivot is its body middle; a boss's pivot is `Root`, a 1-stud part **at its feet**, so shots end on the floor inside a 22-27 stud boss, and ground rings are drawn `Drop` (about 1.6 studs) **under** that: `groundOf` subtracts the caster's drop from the hit point. | `AttackFx` 653-674, 745-787, 3716-3722; `BossBuilder` 45-46 |
| Specials | Charge 0.4-0.6 s (+0.05 per band, cap `SpecialChargeMax` 0.8), travel by distance at 60 studs/s (cap `TravelMax` 0.5), impact 0.15, afterglow 0.8 / 1.2 / 1.6 / 2.0 by band, callout 1.2 s. The server applies every effect at once in `castSpecial` and blocks the caster `CastSeconds` 0.5. A Special nobody pressed gives back up to `LATE_MAX` 0.35 s of charge by holding the victims' events. | `AttackFxCatalog` 649-663, 2041-2071, 2182; `BattleSim` 2378-2437; `BattleController` 275-276, 3580-3660, 4491 |
| Balance harness | `tools/sim_battle.lua` runs the real engine, 64 of 64 targets. Raid cells near the 240 s edge: Frost Wyrm M5 235 s, Lava Golem M5 231 s. | `.superpowers/attack-fx-pitch/sim-final.txt` |

## Decisions (Claude's pick / Gemini's pick; no disagreement)

| # | Decision | Pick | Knob |
|---|---|---|---|
| 1 | Melee attack shape: a straight dash in, a bite, a hop back to the rest spot, with a low hop in the last quarter of the run so the bite reads as a bite. Dash 0.30 s, bite 0.08 s (today's 0.05 s freeze kept), hold 0.12 s, hop back 0.40 s. | B / B | `Feel.Melee.Dash`, `In`, `Bite`, `Hold`, `Back`, `Hop` |
| 2 | Standoff: melee units rest 8 studs farther from the target than today (orbit stop at `reach + 8 - 0.5`). The attack and hit tests grow by the same 8 studs, so damage and tempo do not change. | 8 / not asked | `Feel.Melee.Standoff` |
| 3 | Fast tempo: when the unit's attack interval is under 0.75 s it stays at the edge and bites in place (a short lunge), stepping back once a gap of 0.75 s or more opens. | B / not asked | `Feel.Melee.FlurryBelow`, `Lunge` |
| 4 | Aim: ranged shots, beams and specials aim at the target's body centre: an `AimPoint` attachment when the model has one, else the bounding-box centre, else the pivot. Bites hit the nearest body point at the caster's height. Ground layers (rings, cracks, glow) sit on the real floor under the target, never under the boss's feet root. Pets look exactly as today (their pivot is their centre). | B / B | `Feel.Aim.Mode` ("Centre" or "Pivot"), `FloorRay` |
| 5 | Specials "Weighty" x1.4: charge x1.4 with the cap 0.8 -> 1.1 s; the orb and the beam at 0.7 of their speed (travel cap 0.5 -> 0.7 s); impact 0.15 -> 0.25 s with a 0.08 s hit freeze on the caster's Cast pose and the victims' Hurt pose; afterglow x1.5 (1.2 / 1.8 / 2.4 / 3.0 by band); the name callout 1.2 -> 1.6 s. Low graphics keeps the beats and the freeze, drops the afterglow and the streak as today. | A / A | `Feel.Special.Weighty`, `Tempo`, `ChargeMax`, `Speed`, `TravelMax`, `Impact`, `HitStop`, `Afterglow`, `Callout` |
| 6 | Sync: a real cast time on the server. The caster is Casting for `Cast[kind]` seconds, a `Cast` event goes out at the start (with `at` = the sim time the cast ends), the effects (damage, stun, zone, buff, heal) land at `at` through the delayed-hit queue, the `Special` event goes out then with today's fields plus `at` (its start). A dash during the charge dodges (i-frames at the landing, and the aim is fixed at the start so a sidestep out of the area dodges too). A stun or a KO cancels the cast, keeps the meter and sends `CastBreak`. The client's travel hold stays <= 0.3 s. | B / B | `Feel.Special.RealCast`, `Cast` |

Cast seconds by kind: Blast 0.9, Beam 0.8, Storm 0.95, Freeze 0.7, Pounce 0.6, Heal 0.55, Shield 0.5, Rally 0.55, Haste 0.5.
They are the client's authored Weighty charge at the Legendary band plus the release, minus the travel the hold covers,
rounded: a Legendary Blast charges 0.87 s on the client and the server fires at 0.9. With the 0.12 s render delay the
charge of a Special nobody here pressed loses up to about 0.2 s; the owner's own press starts 0.1-0.15 s earlier and
shows the whole charge.

## The knob

```lua
-- src/shared/Config.lua, in Config.Battle (after ZeroTrophyShare)
Feel = {
	Melee = { Dash = true, Standoff = 8, In = 0.30, Bite = 0.08, Hold = 0.12, Back = 0.40, Hop = 0.5, Lunge = 0.6,
		FlurryBelow = 0.75, MinGap = 3, Streak = true, StreakMax = 4 },
	Aim = { Mode = "Centre", FloorRay = true },
	Special = { Weighty = true, Tempo = 1.4, ChargeMax = 1.1, Speed = 0.7, TravelMax = 0.7, Impact = 0.25, HitStop = 0.08,
		Afterglow = 1.5, Callout = 1.6, TravelHold = 0.3,
		RealCast = true, Cast = { Blast = 0.9, Beam = 0.8, Storm = 0.95, Freeze = 0.7, Pounce = 0.6, Heal = 0.55, Shield = 0.5, Rally = 0.55, Haste = 0.5 } },
}
```

Off switches and what they restore: `Melee.Dash = false` = today's Strike leap; `Melee.Standoff = 0` = today's orbit;
`Aim.Mode = "Pivot"` = today's aim (the floor fix stays: rings never sink); `Special.Weighty = false` = today's beats;
`Special.RealCast = false` = today's instant special with `CastSeconds` 0.5 and the client's `LATE_MAX` hold. The server
reads only `Melee.Standoff` and `Special.RealCast` / `Cast`, through `BattleCatalog.Damage.Standoff` and
`BattleCatalog.Damage.SpecialCast` (BattleCatalog requires Config; the sim mounts Config, so `sim_battle.lua` sees the
same numbers). Everything else is drawing.

## Rules that hold

- **Y2, the server owns reach and damage.** The dash is a pose: a dashing pet's real position is its rest spot. The
  standoff moves the rest spot and the attack test by the same studs. The client's aim, dash and beats never change what
  is hit or how hard. Reach, i-frames, stuns and areas are the server's; the sim is deterministic with the same seed.
- **Balance bands hold.** `SIM_BATTLE=full` keeps every target. The real cast costs 0 to 0.45 s of attacks per special
  (Cast[kind] minus today's 0.5 s block); if a raid cell crosses 240 s that boss's `HpTier` for that fight tier is
  nudged on purpose (as a4a9078 did for the Frost Wyrm's Starter tier), logged in the ledger and listed in "Questions for
  the morning". Nothing is loosened in `sim_battle.lua`.
- **Phones and Low graphics.** The dash is one pose on one model, as cheap as today's Strike; the speed streak is a
  pooled Trail kit on at most `StreakMax` 4 units at once (the owner's pet first), High only; no new Instance per frame;
  segment tables are made once per attack, not per frame. Afterglow stays 0 on Low. Eight pets dashing at a boss make
  no more Instances than eight Strikes do today plus 4 trails.
- **No new models.** The aim point is read from the model; no boss or pet model changes (an `AimPoint` attachment is an
  option for later, nothing today has one).
- **Pets unchanged.** A pet's bounding-box centre sits within 1 stud of its pivot, so `Aim.Mode = "Centre"` aims at the
  pivot for pets (the offset is used only when it is larger than `AIM_MIN` 1 stud).

## What each side does

**Server (`BattleCatalog`, `BattleSim`)**
- `Damage.Standoff` (8): `standoffOf(D, u)` = the number for a melee, non-boss unit, 0 for a ranged unit or a boss.
  Added to: the NPC orbit stop and move test, the NPC engage test, the wind-up hit test, the engaged fighter's melee
  stop, the fighter's auto-attack slack, the Attack command's `OutOfReach` test and the harness fighter's approach.
  Not added to the Dash sidestep's threat reach (the sidestep's escape is its i-frames).
- `Damage.SpecialCast` (the Cast table, nil when RealCast is off): `castSpecial` becomes `beginCast` (checks, target,
  the aim point fixed, `u.castUntil = t + Cast[kind]`, state Casting, the `Cast` event, a queue entry `{ at, from, cast
  = kind, target, x, z }`) and `fireCast` (today's body: meter to 0, the areas, the hits, the zones, the buffs, the heals,
  the `Special` event with `at`); `resolveDelayed` fires cast entries like twists; `onFloor` drops a fallen caster's
  entry (its meter stays). A stun drops the entry, ends the Casting state and sends `CastBreak { unit, kind }`. A target
  in i-frames at the fire is a miss (today's `missEvent`, `special = kind`). Pounce moves the pet and reads its target's
  live position at the fire. Supports act on the live allies at the fire.
- Events: `Cast { type, unit, kind, name, at, target?, tx?, tz?, form? }`, `Special` + `at` (the start),
  `CastBreak { unit, kind }`. `BattleSim.Events` gains `Cast` and `CastBreak`.

**Client (`AttackFx`, `BattleController`, `PetPoses`, `AttackFxCatalog`)**
- Aim: `aimOf(side)` per frame (attachment, else pivot + a cached offset, else the last point); bites use
  `AttackFx.BitePoint(src, tgt)` (the near edge on the flat line at the caster's height); `eff.FloorY` once per effect
  from `ctx.Ground` with one downward raycast refinement; `groundOf` uses it.
- Dash: poses `DashIn` (run + hop + bite, holds at the edge) and `DashBack` (hop back); `AttackFx.Dash(unit, src, tgt,
  landAt, now, opts)` schedules them from an NPC's `Windup` (lands on `at`) or from the fighter's `Hit` (the hit held
  `In` 0.3 s through today's `fxLate` path); `AttackFx.Pose` returns `Forward` (the held edge offset) so a flurry's
  Strike lunges from the edge; the measured tempo decides the flurry.
- Weighty: `AttackFxCatalog.Beats` reads the Special knob (`SpecialTempo`, `SpecialChargeMax`, `SpecialSpeed`,
  `SpecialTravelMax`, `SpecialImpact`, `SpecialAfterglow`); `Resolve` applies them to specials only; `AttackFx` freezes
  the caster's Cast and the victims' Hurt for `SPECIAL_HIT_STOP` at the impact; the callout 1.6 s.
- Sync: `Cast` -> `AttackFx.Precharge` for any unit (the charge starts for everyone, due at `at` on the render clock);
  `Special` -> the hand-over (`Precharged`) with the travel given back up to `TravelHold` 0.3 s of lateness;
  `CastBreak` / a KO / `at + CAST_WAIT` without the event -> `AttackFx.Shatter`. The owner's own press keeps today's
  prediction; its `PRESS_WAIT` is extended to the cast's end when its `Cast` arrives. Old recordings without `Cast` / `at`
  play exactly as today (`LATE_MAX`).

## Tests

`tools/smoke_feel_aim.lua` (client world), `tools/smoke_feel_dash.lua` (both worlds), `tools/smoke_feel_tempo.lua` (both
worlds), registered in `tools/smoke.py`; the plan names every scenario and its assertions. Then the regression lists the
plan names, `SIM_BATTLE=full`, `node tools/check.mjs` 0 errors, and the owner's Studio checks (8 pets dashing at a
boss, a phone layout, Low graphics) with screenshots in `.superpowers/battle-feel/evidence/`.

## Questions for the morning

1. The six picks above: any to change (each is one knob).
2. A boss HP nudge, if the full sim needed one (the ledger says which cell and the number).
3. The cast seconds per kind (0.5-0.95): keep, or one number for all.
4. An `AimPoint` attachment per boss (decision 4's option C) for the Hydra's heads: a later Blender task if wanted.
