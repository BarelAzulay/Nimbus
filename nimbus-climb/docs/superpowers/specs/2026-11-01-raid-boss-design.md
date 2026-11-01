# Boss raids: always there, hard at every level

Date: 2026-11-01. Status: approved by the owner item by item on the pitch page
(https://claude.ai/artifact/T578VHpewLQc7sm2CQXnNc, source `.superpowers/raid-pitch/page.html`).

## Why

The owner's words: "i want the raid boss to be really hard but also i want him to be spawn from the start without needing to
'join raid' but also i dont want the boss to be with the same stats for players starter level/mid/high/max".

Measured today (2026-10-31 balance): four mid-level teams win only 0-67% (0% on Lava Golem), and strong groups kill Lava Golem in
66-78 s against the 100-240 s target. This design replaces those numbers.

Today's raid: `BattleCatalog.Events` runs a BossRaid every 20 minutes with a 120 s announcement, a 60 s Join window and a 330 s fight on
the colosseum floor (`Zones.Raid`, 96 x 96). One boss per server; `BossHp` follows the joined teams.

## Owner's decisions

| Item | Decision |
|---|---|
| Where | **D. One boss at the gate.** One boss stands on the colosseum floor, visible from the lobby. Walking through the gate puts you in the fight for your tier, shared with anyone else on your tier in that server. The first fight runs on the real floor, in view of the stands; other tiers' fights run at the same moment in a side pocket. |
| When | **A. Always there.** No Join, no window, no announcement. The boss comes back 60 s after a kill. You may fight as often as you like, but rewards come once per 20 minutes per player. |
| Tier | **A. Your highest pet on the active team.** Starter L1-19, Mid L20-49, High L50-79, Max L80-100. You may dare a higher tier; you can never drop lower. |
| Looks | **A. Same boss, dressed up.** Tier colours, more size and a growing aura; Max gets a crown of spikes. No new models. |
| Hard | **A. Brutal, solo barely possible.** Targets near the top of a tier: solo 5%, 3 teams 40%, 8 teams 85%. |
| Scary | **A. Hunted, then enraged.** Outside the gate, the idle boss slowly turns its head to follow you. In the fight, the sky darkens. Below 30% health it enrages: red screen edges and a huge attack that kills if you don't run or dash. |

Also on the page and not objected to: the Join button, window and warning go; the tutorial's raid step becomes "walk through the gate";
Gold / Silver / Bronze by damage share stay; the Lava Golem health fix is part of this; all four bosses get the 100-240 s group target; the
steel colosseum floor Gemini suggested is left out.

## Starting numbers (tune them with `tools/sim_battle.lua`)

| Tier | Highest pet | Boss built for | Boss hits (share of your health) | Reward scale |
|---|---|---|---|---|
| Starter | L1-19 | L15 | x0.6 | x0.4 |
| Mid | L20-49 | L40 | x0.8 | x0.7 |
| High | L50-79 | L70 | x1 | x1 |
| Max | L80-100 | L95 | x1.3 | x1.3 |

Winning a dare pays the higher tier's rewards.

## Sim targets

Per boss and per tier, with a reference team near the top of that tier and the default trainer, with bands wide enough for the sim's noise:
solo about 5% (at most 15%), 3 teams about 40% (25-55%), 8 teams about 85% (at least 70%). Group fights last 100-240 s, Lava Golem
included. A team at the bottom of a tier losing solo is expected. The current `raids` section's targets are replaced, and none are loosened
to pass: a target that can't be met goes in the final report.

## Claude's calls (the owner can overrule them; report them)

- **Reward limit survives server hops.** The 20 minute limit is saved on the player's data (merged across servers by maximum). A win starts it.
  A loss pays the small loss reward (`LossTokens` / `LossXp`, scaled) at most once per 5 minutes and doesn't start the 20 minute limit, so a
  loss can't cost a player their win. The gate shows the time left. Without this, Gems and event pets could be farmed all day.
- **Walking through is the whole step.** No button to fight your own tier. Daring is a separate prompt on the gate's pillar that opens a small
  panel listing the higher tiers, because a dare must be a choice.
- **The floor goes to the first fight.** A fight is created when someone enters a tier with no fight. It takes the real floor if free, else a
  pocket. When the floor fight ends, the next new fight may use it. Same-tier players always join the running fight, wherever it is.
- **A running fight scales with who is in it**, through the existing join and leave scaling. Everyone leaving or dying ends it and resets the boss.
- **Per-tier return.** After a kill that tier's fight is closed for 60 s; the gate says so. The other tiers are unaffected. The idle floor boss is
  hidden only for those 60 s after a win on the floor.
- **Roster.** The boss rotates every 20 minutes (`BattleCatalog.NextBoss`) when no fight is running, otherwise right after the running fights end. All fights
  use the current boss, and a running fight keeps its own.
- **Sky.** A fight on the real floor drives the existing server-wide raid sky. Fighters in a pocket get the same dark sky locally, for them only.
- **Enrage moves from time to health.** Bosses enrage at 30% health instead of at `EnrageAt`; the 330 s time limit stays. The lethal attack gives
  at least 2.5 s of warning and is always escapable by running or by the dash's i-frames, and it needs a new telegraph shape only if an existing
  one can't cover it. Lethal means the unit it hits is knocked out.
- **Event pets and Gems** keep today's chances at High and Max; Starter and Mid get half. Double Rewards stays on its schedule.
- **Tier is read on entry**, from the server's copy of the active team, with the team refusals the Ring uses. Busy pets don't count as on the team.

## Non-goals

- New boss models, new uploads or new audio. The gate reuses what exists (the arena's boss gate piece, `arena_seg_bossgate`). Any new visible
  model is hand-made in Blender and uploaded by the keyed session, so avoid needing one. Sound slots stay silent until original audio
  (ElevenLabs / Suno) arrives.
- Cross-server matchmaking, AI companions.
- Changing the colosseum's art beyond the gate and the dressing above.

## Must keep

- Server authoritative: tier, entry, rewards and the limit are decided on the server. Junk or spammed requests change nothing.
- Up to 8 raiders per fight, under the existing network limits (`p3fixsrv_net16`, `p3fixchk_wire`). Part budgets for pockets (`<= 220` today for the Ring). Several fights may run at once: check the server's cost and report it.
- Phone first: 844x390, targets at least 44 px, under Roblox's topbar. Graphics Low keeps the fight readable: head-tracking and auras off or cut.
- A tutorial player isn't stranded: the raid step completes on walking through the gate or by Next, and a saved step from the old raid chapter still works.
- Old saves load with no raid data; a stale Join remote or client call does nothing harmful.
