# Dungeon fixes (player request, after Phase 6): plan and contract

Branch `v3-dungeon-fixes` (from main). Lead plan; engineers code strictly to the names below. File:line anchors come from
the three code maps (`docs/dungeon-fixes/map-*.md` summaries are in this file).

## Root causes found (proven in the mock)

* **A. Dungeon enemies are never drawn.** `Dg.startFight` opens the encounter (BattleService `beginBattle` sends
  `BattleState "Start"` with no enemies) and only then `SpawnWave` adds them; `Sim:AddTeam` with a wave emits a `Wave`
  event carrying the enemy list (BattleSim.lua:805-814), and the client's `Handlers[EV.Wave]` (BattleController.lua:2726)
  never calls `Units.Add` (only `Spawn` :2588 and `Start` :6100 do). Every dungeon enemy, the boss and its escort are
  invisible on every client; wave 2/3 never show either. The client tests hid it by spawning before Start.
* **B. Enemies float.** `OpenEncounter` uses the `NC_BattleZone` part CFrame as the floor centre; the part sits 6 studs
  above its base (DungeonBuilder.lua:1554): enemies are drawn ~4.5 studs (boss room ~6) above the floor.

## Decisions (one per requirement)

1. **Enemies appear and can be fought.** Client `Wave` handler adds every `ev.units` entry with `Units.Add` (dedupe by id,
   the `Spawn` path). DungeonService passes the floor-level zone (`Zone = { CFrame = <zone at floor height>, Size, Part }`)
   or DungeonBuilder fixes the zone so `OpenEncounter`'s centre is the floor; `FloorY` attribute corrected. Enemies use
   the Wild look the contract asks for (`PetBuilder.Build(def, { Wild = ... })`) when cheap. New client tests in SERVER
   order (Start first, enemies in a Wave event) for every mode.
2. **Room exit + E + fade.** No room change by timer any more (`DoorTime` auto-teleport removed; hall exit and boss->treasure
   too). When a room is cleared the exit bars open; at the far end of the route (the NEXT room's `Door_Entrance`, which now
   stays closed until the group enters; the hall's exit for room 1; the boss room exit for the treasure) a ProximityPrompt
   `EnterPrompt` (E, HoldDuration 0, RequiresLineOfSight false, MaxActivationDistance 10, attribute `DungeonAction =
   "Enter"`, ActionText "Enter", ObjectText "Room 2") is enabled. Pressing it sends nothing new: the server's existing
   `onPromptTriggered` handles `DungeonAction "Enter"`: idempotent `run.Confirm[userId] = true` (own pocket, `run.State ==
   "Corridor"` (or Hall), member not Left, within 14 studs of the prompt part). The `Run` state payload gains
   `Confirmed = { userId... }` and `NeedConfirm` (count). When every member still in the run (not Left; Downed members too)
   has confirmed: `run.Transit = true` (lock; later presses ignored), `DungeonState("Fade", { Out = 0.45, Hold = 0.35,
   In = 0.45 })` to the members, after `Out` the server reveals the next room (open its Door_Entrance, teleport members to
   its Entrance, `Dg.enterRoom`), then clears `run.Confirm` / `run.Transit`. The client (DungeonController) owns one black
   full-screen fade overlay (DisplayOrder above the HUD, below Notify), tweens it in/out from the payload, never leaves it
   stuck (a 3 s safety timeout and End/leaving the pocket clears it). Side card text: "Go to the door and press E" /
   "Waiting for 1 more (Ava)". A member leaving / disconnecting re-checks the count. AFK protection stays the existing
   rules (leash, LEAVE, RunMaxSeconds watchdog); the run never moves a player without that player's E.
3. **Enemy arrival + extra waves.** Server: `Sim:SpawnEnemies` / `AddTeam` gives each new enemy `arriveUntil = now +
   BattleCatalog.Fighter.ArriveSeconds` (1.2); while arriving an enemy does not act (npcStep skip) and cannot be hit
   (i-frames); the `Wave` / `Spawn` event unit info carries `Arrive = 1.2`. Client: `EvolutionFx.Arrive(pivotCFrame, opts)`
   (new, effects only, built from the evolution animation's pieces: rune ring, light pillar, white flash, sparkle burst,
   shock ring, voxel sparks; ~1.2 s; returns { Done, Stop }; pooled/cheap; GraphicsQuality Low = flash + ring only) plays at
   each arriving enemy, and the enemy model pops in (scale 0 -> overshoot -> 1, `hopAt` style) after the flash. Extra waves
   keep the existing rule: `DungeonService.wavesOf(run, room)` from `BattleCatalog.Dungeon.Waves {2,2,3}` /
   `Floor1Waves {1,1,1}`, boss room = boss then escort at `EscortAt`; each wave arrives with the same animation, and the
   side card says "Wave 2 / 3".
4. **Normal attack through the combat pet (all modes: Duel/Practice, Ring, Raid, Dungeon).** BattleSim: a player's
   fighter AUTO-ATTACKS: every step, when it can attack (not Stunned/Casting/Dashing, cooldown ready), it hits its target =
   the lock if alive and in reach, else the nearest enemy in reach (range + radius + AttackSlack), via the existing
   `doCommand("Attack")` damage path (the attack half of `autoFighter`; it NEVER writes `team.wantX`: the character stays
   the body, B1). The `Attack` command no longer swings: it "directs" the pet: `Attack(targetId)` locks that target,
   `Attack()` with no id locks the nearest enemy (cycles to the next on repeated presses), and the pet keeps attacking it
   automatically. Out-of-reach lock: the existing throttled "Too far!" toast. Client: F / click / ATTACK button send the
   direct order once (no hold-repeat cadence); SPECIAL (Q), ELEMENT (E), helper buffs (1/2), SWAP stay manual.
5. **Shift = the pet's dash.** In battle LeftShift / RightShift (and gamepad ButtonB as today) send `BattleCommand "Dash"`
   only: the character gets NO velocity impulse and spends no stamina (MovementController battle dash keys off; a new
   `MovementController.SetPetDash(on)` or SetDashKeys({}) + BattleController binding). Server sim Dash unchanged (cooldown,
   i-frames) plus the `Dash` event; the client draws the PET dashing (a quick streak toward its target / facing and back,
   trail), never the character. RUN stays on Ctrl in battle; outside battle Shift is sprint and Q the obby dash as today.
   Every key text (HUD key chips, captions, tutorial, NPC tips, README controls table, UpdateNotes) updated consistently.
6. **Mouse lock option.** Setting `MouseLock` (bool, default false) in ClientSettings + DataService `SETTING_KEYS /
   SETTING_DEFAULTS` + the Settings window (a chip row like Shake: "Mouse lock  On / Off"). New client module
   `src/client/MouseLock.lua`: `Start()`, `SetEnabled(bool)`, `IsEnabled()`, `IsLocked()`, `Hold(reason)`, `Release(reason)`.
   While enabled and no hold: after the camera each frame `UserInputService.MouseBehavior = LockCenter` (keyboard + mouse
   devices only; touch/gamepad untouched). Any docked window (NeonKit.Dock holder Visible), the main menu / loading
   screen, the battle result card / LEAVE confirm, the notify result card, the tutorial card, and the dungeon window =
   holds: the cursor is free (MouseBehavior Default, MouseIconEnabled true). E prompts keep working. In battle, a click while
   locked targets the enemy under the screen centre.
   **E stays the interaction key:** the battle ELEMENT binding returns `Pass` while a ProximityPrompt is shown to the
   player (ProximityPromptService.PromptShown/Hidden), so E always presses a visible prompt (exit, chest).
7. **Combat healing.** No passive heal in combat: bench regen removed (`BenchRegenPerSecond` 0 / code gone), the wave gap
   counts as combat. Healing other pets in combat only by an active healing pet using its healing skill: the Heal special
   of a player's healing pet (Special.Kind "Heal": honey_bunny, sleepy_owl, blossom_bunny, cherry_panda,
   starlight_unicorn) heals the fighter AND the benched pets of that team (as NPC heals do); the Heal helper buff of a
   benched healing pet heals the fighter and the other benched pet. Element regen buffs / lifesteal stay self-or-fighter
   skills (active, not passive). Out of combat: a fresh battle per room / Ring round = full HP (unchanged). Balance:
   `tools/sim_battle.lua` targets re-checked; retune only `BattleCatalog` numbers if a target fails.

## Ownership (each engineer edits ONLY these files; others via lead requests with file:line + patch)

| Key | Files |
|---|---|
| dungeon-flow | `src/server/Services/DungeonService.lua`, `src/server/Services/DungeonBuilder.lua`, `src/client/Controllers/DungeonController.lua`, `tools/smoke_p5_dungeon*.lua`, new `tools/smoke_dgfix_flow.lua` + its smoke.py line |
| battle-core | `src/shared/BattleSim.lua`, `src/shared/BattleCatalog.lua`, `src/server/Services/BattleService.lua`, `tools/sim_battle.lua`, server battle tests (`smoke_p5_battlecore.lua`, `smoke_p5_battleservice.lua`, `smoke_p3_battlecore.lua`, `smoke_p4_ring.lua`, `smoke_p3_battleservice.lua`, `smoke_p5_flow.lua` server half), new `tools/smoke_dgfix_core.lua` + smoke.py line |
| battle-client | `src/client/Controllers/BattleController.lua`, `src/client/Controllers/MovementController.lua`, `src/client/Controllers/EvolutionFx.lua`, `src/client/Controllers/HudController.lua` (dash ring only), client battle tests (`smoke_p5_battleclient.lua`, `smoke_p3_battleclient.lua`, `smoke_p3_fix_client.lua`, client halves of flows), texts: `README.md`, `src/shared/NpcDialog.lua`, `src/shared/TutorialSteps.lua`, `src/shared/UpdateNotes.lua`, `tools/smoke_p2_final.lua` + `tools/smoke_p5_tutorial.lua` text checks, new `tools/smoke_dgfix_client.lua` + smoke.py line |
| mouse-lock | new `src/client/MouseLock.lua`, `src/client/ClientSettings.lua`, `src/server/Services/DataService.lua` (settings lines only), `src/client/Controllers/MainMenuController.lua` (settings row + menu/loading holds), `src/client/UI/NeonKit.lua` (Dock hold hook), `tools/smoke_p5_data.lua` (settings count), `tools/smoke_p5_menu.lua` (settings), new `tools/smoke_dgfix_mouse.lua` + smoke.py line |
| lead | `src/client/Main.client.lua` (start lines), `tools/contract.json`, `ARCHITECTURE_V3.md`, `BUILD_STATE.md` |

Interfaces between owners: battle-core emits `Arrive` in Wave/Spawn unit info and keeps the `Dash` event (`unit`, `dir`);
battle-client consumes them. battle-client calls `MouseLock.Hold/Release` through a pcall'd require (no hard dependency).
DungeonController owns the fade; battle-client only makes E pass through to prompts.

Rules: empty or partial MeshIds must keep working (Part builds); only Blender models for any new model (effects =
particles/lights/beams/Neon effect parts like EvolutionFx, no new props); server-authoritative; per-frame work client
only; deterministic tests; at most 200 locals per function; keep `tools/syntax.py`, `node tools/check.mjs` clean.
