# Wave 6: fight focus, podium + cheering, solid dungeon rooms (design)

Date: 2026-10-29. Source: the player's play-test after the art wave (main 5d9392a) and a brainstorm in chat.

## Why

The player wants pet fights to feel like *coaching*: the trainer stands and cheers, the pets commit to the fight. Today
pets only engage enemies within 14 studs of where the player stands, come back when the player walks 7 studs
(EngagePull 7), and the player can wander around the Champion Ring. The dungeon camera can zoom out over the room,
which breaks the "inside a dungeon" feel, and the room walk-in only plays on floor 1.

## Goals (the player's words in quotes)

1. **Send pets from anywhere, every battle mode.** "A player should be able to send his pet into a battle from the
   whole champion ring range / dungeon room", and "also for all other battle modes, boss raid, pvp". Any enemy inside
   the current fight area (ring pocket, PvP arena, raid zone, dungeon room) is reachable: no 14-stud engage radius around
   the standing player.
2. **Fight focus.** "When a player moves, his fighting pet ignores its owner and keeps attacking the enemy." The
   EngagePull "come back" rule goes. A pet that is fighting stays on its target until the target dies, then takes the
   next enemy in the fight area. It returns to its owner only when no enemy is left (the fight ends). Pets reach their
   targets from further away ("the pets should have bigger range"): a bigger engage / chase reach so they close in on
   any enemy in the area.
3. **Podium lock: Champion Ring and PvP only.** In those two modes the player cannot walk off the pink podium block
   during a fight. Not in the dungeon, not in boss raids (the player moves freely there).
4. **Cheering avatar.**
   - Ring and PvP: while locked on the podium the player's own avatar plays a cheering animation (on its own).
   - Dungeon and boss raids: a **"Cheer up!"** button appears just above the player's HP bar during a fight; pressing it
     plays the same cheer animation and gives a **really small boost** to the player's pets.
5. **Solid dungeon rooms.** "Make the rooms solid blocks so the player won't be able to scroll (zoom out) the room": the
   camera can never show the outside of a dungeon room (walls and ceiling block it; zooming out stops at them).
6. **Bug: the room walk-in works only on floor 1.** It must play on every floor (1-12), every room.

## Non-goals

- No change to the podium in the lobby, the dungeon's own entrance, or the raid arena's podium wall (ArenaBuilder's
  "Podium" is the raid stands' wall, not the pink block).
- No new battle controls beyond the Cheer up! button; F stays "attack" (bug #16).
- No new art pieces (the cheer is an animation; the button follows the existing battle HUD style).

## Anti-goals (a failure even if it technically works)

- Pets zipping across the arena so fast that fights look like teleports; a long chase must still read as running.
- The podium lock feeling like the controls broke (it must be clear why you can't move: you're the trainer).
- The cheer boost becoming a must-spam meta. It is a "really small" bonus with a cooldown.
- Bosses becoming trivial because pets never retreat. Balance is re-measured and retuned (see Constraints).
- A dungeon room you can see out of, or a camera that clips into walls / jitters at the ceiling.

## Constraints

- Server-authoritative: the cheer boost, podium lock and engage rules are enforced on the server (BattleSim /
  BattleService / DungeonService), never trusted from the client. The Cheer remote is rate-limited and validated (the
  player is in a fight in a mode that has the button, off cooldown).
- Phone: the Cheer up! button is a normal-sized battle tap target above the HP bar, not covering the hotbar or the HP.
- The bug #2 rule still holds: a weak solo cannot solo a raid boss. After this change, re-run the balance lane
  (tools/sim_battle.lua raids + duels; the lava golem M5 8p cell is the sensitive one) and retune with data if needed.
- Existing smoke tests for EngagePull 7 / EngageRange 14 change with the rules: replace them with tests of the new rules.
- Sound: no new sounds here (the sound effects are a separate pitch). Tag/hook points only if cheap.

## Decided by the player

- Send-from-anywhere: all battle modes (dungeon, Champion Ring, boss raid, PvP).
- Fight focus: pets ignore owner movement while fighting.
- Podium lock: Champion Ring and PvP only.
- Cheering = the player's own avatar. Auto on the podium (Ring, PvP); a "Cheer up!" button above the HP bar in the
  other modes (dungeon, raid).
- Cheer up! gives a "really small boost".
- Dungeon rooms: camera cannot zoom out of / see out of the room.
- The walk-in must work on every floor.
- **Dodging is skill-based, through the pet's Dash.** Pets do NOT dodge by themselves. When the player presses Dash
  mid-fight, the engaged pet dodges / parries (the player's timing is the skill). The owner's movement no longer
  steers an engaged pet.
- **Engaging (builder check, Claude's pick approved):** a pet attacks automatically as soon as any targetable enemy is
  anywhere in the fight area, whatever the owner is doing (the stand-still trigger and EngageCooldown go). F / Tab /
  click still choose the target.
- **Re-targeting (Claude's pick approved):** the player can still switch an engaged pet's target (F, Tab / RT, click).
  Fight focus only means owner movement never pulls the pet off.
- **Open rooms (Claude's pick approved):** no new walls on rooms open to the chasm (Rooms.Bridge keeps its look);
  invisible camera blockers keep the camera from rising above the room or swinging out over the chasm.

## Claude's calls (the player can override)

- **Dash = dodge or parry by timing:** Dash makes the engaged pet sidestep OUT of the threat (away from the telegraph /
  the attacker, never into the boss as today's lock-facing dash does) with the existing DashIFrames. Pressed inside a
  short window before an incoming hit lands (ParryWindow 0.25 s, data) it is a **Parry**: the hit does no damage, the
  attacker is briefly staggered (0.4 s) and the pet gains a little special meter (+8); a parry shows a distinct flash.
  DashCooldown stays. Works in every mode, including Ring / PvP where the player is on the podium.
- **Balance harness:** tools/sim_battle.lua's scripted player dodges by pressing Dash at telegraphs (with a skill
  level: how often it times it right) instead of running the pet out; the raid targets are re-measured with that model.

- **Boost size:** the cheering player's pets deal +5% damage for 5 s; Cheer up! cooldown 20 s. Data in BattleCatalog
  (CheerBoost 0.05, CheerSeconds 5, CheerCooldown 20). Does not stack.
- **Ring / PvP auto-cheer is visual only** (no boost): it is always on there, and in PvP both trainers would have it.
- **Cheer animation:** the avatar's built-in /cheer emote (R15 "Cheer") looped with small pauses on the podium; one play
  per button press elsewhere. A custom animation only if the emote is unavailable for the rig.
- **Podium lock behaviour:** the character is anchored in place on the podium (or WalkSpeed/JumpPower 0) from the
  fight start to the fight end; turning the camera still works. Leaving the fight (Leave button) releases it.
- **After the target dies:** the pet takes the nearest remaining enemy in the fight area; it returns to the owner when
  none is left.
- **Engage reach:** the fight area's bounds (ring pocket / PvP arena / raid zone / dungeon room) replace EngageRange 14
  and EngageLeash 18; EngagePull is removed. Chase speed stays the pet's run speed.

## Left to the builder

- Identify the "pink podium block" in the Champion Ring pocket and the PvP arena (the player's spot during a fight) and
  lock the player there. If PvP has no such block, use the PvP player's start spot and say so.
- Find why the walk-in only plays on floor 1 (DungeonController / DungeonService wave 5 code) and fix it with a test
  that runs floors 2, 5, 9 and 12.
- How to make the camera stay inside rooms (ceilings that block the camera, camera collision/occlusion settings, a zoom
  cap per room size): pick the cheapest robust way; check corridors and the boss room too.
- The HUD placement of Cheer up! (above the HP bar) on PC and phone layouts.
- Smoke tests for every rule above; the balance lane re-run with a short report.

## Studio checks after the build

- Ring and PvP: you can't walk off the podium, your avatar cheers, your pets reach every enemy in the ring.
- Dungeon floors 1, 2, 5, 9, 12: walk-in plays on each; the camera never shows outside the room; Cheer up! shows above
  HP, plays the cheer, the boost lasts 5 s, the 20 s cooldown shows.
- Raid: pets keep fighting while you run around; Cheer up! works there too; a weak solo still loses.
