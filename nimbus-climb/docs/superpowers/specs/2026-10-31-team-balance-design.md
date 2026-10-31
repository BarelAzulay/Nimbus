# Team flow, battle balance and the Pets window (design)

Date: 2026-10-31. Branch `team-balance`, from `hud-tools` (6ad77f0). Source: the owner's playtest of the HUD cleanup and the
pitch https://claude.ai/artifact/VHivxkWH6BTwecySb4GNCq (to-scale mock-ups, measured sim charts, Gemini's and Claude's picks).
All seven rows approved with no notes. The page's mock-ups are the look to follow; `.superpowers/team-balance-pitch/page.html`
is a local copy.

## The owner's words

"in the champion ring if a player clicks continue it automatically auto fill his team without letting him choose and create
it, lets make it that the team is the same pet that are aquiped on the player with an option to edit before getting into
battle games, the champion ring is still unbalanced (all battle games enemies) a new player with lvl 1 pets shouldnt be able
to reach even round 5 on the ring, and in the dungeon barely pass the first room. brainstorm the balance system. the gui's for
pets and teams are all so uncompfortable for the player, it built really bad."

## Why (measured at 4879f8c)

- Three L1 Commons win about 15 Ring rounds; the game's own sim targets (`SIM.RingMedians`) ask for this. Every team clears
  Dungeon floor 1 in every seed, even idle.
- Rarity beats level: a lone L1 Stormfang records 28 Ring rounds, a lone L100 evolved kitten 26.
- The server takes active team -> equipped -> strongest (`RingRun.fighters`), and the Ring panel's fighters row is cut off above
  its buttons, so CONTINUE looks like a silent auto-fill.
- Pets / Team UX audit, worst first: a phone Team tab with a 76 px scroll area (first pet 12 screenfuls down); blind swapping in
  one column; a popup whose slots only cycle pets; three ways to edit a team with different save rules; equipped pets labelled
  "Team"; phone targets down to 24 px; a phantom 4th slot row; no sort control.

## Decisions (approved)

### 1. One team: the pets following you, with an A / B / C swap (the owner chose Gemini's option here, not Claude's)

- A player's battle team IS the 3 pets following them. Slot 1 fights; 2 and 3 help, and all three give their follow perks.
- Three teams A / B / C (the existing `Teams.Presets[1..3]`). Exactly one is active, and the invariant is:
  `Equipped` == the active preset's keys, in order, at all times.
- A small A / B / C button group sits beside the slots. Pressing one makes that team active: all three followers change at
  once. A press on an empty team leaves no followers, and the slots show as empty.
- Migration, once per save (a marker, safe under provisional / merged saves like `B3ItemsRefund`): if `Equipped` is non-empty
  the active preset becomes `Equipped`; otherwise `Equipped` becomes the active preset. The other two presets are kept as they
  are. Nothing else is deleted.
- Every path that changes `Equipped` or a preset keeps the invariant (equip, unequip, garden, training, fusion, sell-like
  removal, recalls, Admin / dev commands, `/maxpets`). A swap to a team holding a pet now gardening or training skips that pet
  and says so in a toast; the existing garden recall prompt stays for a direct pick.
- Equipped slots stay `Config.Pets.MaxEquipped` = 3. The first pet ever still auto-equips.

### 2. Edit before a battle: faces and Edit on the panel

- Ring, Dungeon, raids and duels each show the three faces (FIGHTER / HELPER tags, level, power) plus **Edit team**. The row is
  never clipped on any screen size: on the Ring panel it sits above the buttons, on phone in the right column as in the pitch.
- CONTINUE / START / READY go straight in with that team, with no extra screen.
- **Edit team** opens the Pets window and, on close, returns to the panel it came from, on the same tab and start round.
- Never auto-fill silently. The server's "else strongest" fallback goes away: an empty team is refused. On the client an entry
  with an empty team opens the Pets window with the first slot in pick mode. **Auto-fill best** exists only as a button in the
  Pets window.
- `TeamPick`'s strips and its "Pick your battle team" popup are replaced by this one flow. A player with 0 pets still gets the
  "You need a pet" hint.

### 3. The Pets and Team window: one big window, slots pinned on top

- Replaces the Pets and Team tabs of `Window_Inventory` (`MenuController`), with no tabs. Sizes in screen pixels: PC 1920x1080
  about 1260x900, centred; phone 844x390 about 820x330, under Roblox's topbar and never over its buttons. Other viewports scale
  between these; a window under about 760 design px wide uses the phone layout. No nested scrolling: only the grid scrolls.
- PC layout: top row with the 3 slots, A / B / C, team power with a one-line breakdown ("Fighter 358 + helpers 281, 279 + team
  bonus"), Auto-fill best and Clear. Below: a sortable grid on the left, the selected pet's details and actions on the right.
- Phone layout: the 3 slots in a column on the left, always visible; A / B / C and sort on the top row; the grid on the right
  with cards about 104 x 130. Tapping a pet opens a sheet over the grid with big actions at the bottom edge.
- Pet card: picture, level, a colour-coded element icon, power, a rarity border, a number badge when on the active team, a
  busy mark when gardening or training, and the existing tier / stars. The name shows on PC cards and in the phone sheet.
- Sort: Strongest (default), Rarest, Level. One control, shared by the whole window.
- Picking: tap a slot to enter pick mode ("Pick a helper for slot 2"; the slot glows). One tap on a pet drops it in with a pop
  and a heavy sound (reuse an existing approved sound; no new upload). A pet already in another slot swaps positions; the slot's
  own pet offers Remove; tap the slot again or X to cancel. Outside pick mode, tapping a pet selects it, and "Put in team" fills
  the first empty slot or enters pick mode when the team is full; a team pet offers "Make fighter" (swaps with slot 1) and
  Remove.
- Actions keep today's behaviour and rules: Feed (Food Machine), Train, Garden, Evolve with its confirm. Every interactive
  target is at least 44 px high on a phone (close and small chips included). A refused action says why in a toast at once; no
  silent revert. Auto-fill best overwrites only the active team, followed by a toast with Undo. Clear asks for a second tap.
- Busy pets are marked and left out of the team power, which then matches what will really fight.
- Words: "team" means these three everywhere; the Equip / Equipped words go. Tutorial steps and NPC lines that point at the old
  Team tab, Equip button or `TeamPick` move to the new controls.

### 4. Balance targets: the owner's wall, eased after round 5

Measured with `tools/sim_battle.lua` plus run XP (loss XP included), Default trainer = stands, times Dash at skill 0.7, presses
every button; Idle = presses nothing.

| Team | Ring rounds won, Default (Idle) | Dungeon |
|---|---|---|
| 3 L1 Commons | 3 (1-2); reach round 5 in at most 10% of seeds; round 1 won in at least 95% | Room 1 at least 90%, room 2 about 50%, floor 1 full clear under 15% |
| 1 L1 Common | 1-2 (1) | |
| 3 L6-7 Commons | | Floor 1 clear at least 80% |
| 3 L1 Legendaries | about 8 (4) | Best floor about 2 |
| Owner's L10 / 11 / 11 Secrets | about 19 (about 11) | Best floor about 4 |
| 3 L50 Legendaries, evolved twice | about 39 (about 31) | Best floor about 7 |
| 3 L100 maxed | 60 to 95 | Best floor 12 |

New-player pace, three L1 Commons, counted from real run XP as in the prototype: reach Ring 5 in about 6 minutes, clear floor 1
in about 7, and **reach Ring 10 in about 30 minutes**. The prototype's Option A took 73 minutes to Ring 10; easing rounds 5 to
15 is required and was NOT measured in the pitch. Measure it, report the final table, and treat 30 minutes as a target with a
20 to 45 minute band.

Also required:
- Shown level and shown power never drop from one round to the next (the prototype's anchors zigzag from L17 to L15).
- A first win always exists: round 1 is an easy Common.
- The tutorial's two battle steps must always be winnable (section 7).

Starting numbers: `.superpowers/team-balance-pitch/balance/options_config.lua`, option A. They are a starting point for tuning,
not a contract. The harness and results are in the same folder.

### 5. Level beats rarity (battles only)

- A battle-only stat path: battle rarity scale Common 1, Uncommon 1.25, Rare 1.6, Epic 2.1, Legendary 2.8, Mythic 3.7, Secret 5;
  battle level factor `1 + (0.12x + 0.0035x^2 + 0.0002x^3) * evolution bonus`, x = level - 1. Same for player pets, champions,
  dungeon enemies and duels, so a level means the same on both sides. Tunable, keeping these tests:
  a L30 Common beats a L1 Secret (mean about 95% of duels), a L100 evolved Common beats an unevolved L50 Secret (about 84%),
  and a Secret stays the stronger pet at any equal level and stage.
- Garden income, coins, speed and everything non-battle keep `Config.PetStats.RarityScale` and today's `LevelFactor` unchanged.
  `PetCatalog.GetStats` stays as it is for its other readers: do it in the battle path, with no runtime patching (the prototype's
  patch is not to be copied). `tools/sim_tycoon.py --check` still passes.
- Every shown battle power (cards, slots, panels, HUD) uses the new numbers.

### 6. Boss raids: the owner's L10-11 Secrets cannot solo

- `BossRules.Baseline` starts at level 35 (prototype: 0 of 8 solo wins per boss, was 4 of 4). Solo stays possible only far
  along.
- Measure group raids against today. The prototype's 4 and 8 teams finished in 74 to 87 s, under the 100 to 240 s target in
  `tools/sim_battle.lua`. Tune `HpPerPlayer` or the floor so groups land in that band without letting the L10-11 Secrets solo.

### 7. A loss feels like progress, and the tutorial still works

- Ring run lost, or a Dungeon floor lost: a result screen in place of today's plain card. Each team pet that gained a level
  shows `L1 -> L3` with a loud level-up moment; a pet that gained none shows its XP bar moving. **Fight again** (same start round
  or floor, without walking back) and **Edit team** (returns here). Wins keep their current screens. The retry loop should be
  under 2 minutes for a new player. The server sends before / after levels; the client never computes them.
- Tutorial: "Into the Dungeon!" completes on clearing the first room rather than floor 1, and "The Champion Ring" still on one
  won round. While that dungeon step is open, room 1 of floor 1 is easy enough for any L1 team, even one pet (at least 95%). Text
  and hints follow. Old saves past these steps are unaffected.

## Non-goals

- No new shop items, pets, models, or uploads. No new sounds or textures: reuse approved ones.
- No Ring reward or economy rework beyond keeping `sim_tycoon --check` green. Report any economy effect of shorter early runs.
- No other windows restyled. Fusion stays at its machine. No sell, lock, filter or search.
- No device vibration and no double-tap to equip (rejected in the pitch).
- No merge into `main`, no publish.

## Anti-goals

- A silent auto-fill, or a battle entered with pets the player could not see.
- A player stuck at a portal with no way to set a team.
- A lost pet, preset or Token in the migration; `Equipped` and the active preset drifting apart.
- Garden income changing because of the battle rework.
- Any phone target under 44 px in the new window, or any overlap with Roblox's topbar or the jump button area.

## Left to the builder

The exact balance numbers within the targets; how Fight again re-enters each mode; the card and sheet details within the mock-ups;
which existing sound is the snap; how existing Ring records and unlocked boss starts behave under harder champions (keep them, do
not reset; report what a veteran now sees); test rewrites: about a dozen checks pin the old numbers (`sim_battle.lua` targets,
`smoke_p5_battlecore`, `smoke_ring_noheal`, `smoke_p4_ring`, `smoke_p5_dungeon`), and `TeamPick` / Team tab tests move to the new flow.
Keep `p3fixsrv_net16` no worse than today; it already fails at 6,004 B/s against 6,000.
