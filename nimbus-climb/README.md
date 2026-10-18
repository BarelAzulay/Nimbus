# Nimbus Climb

> *Climb the storm. Together.*

A cosy, co-op **sky village** game for Roblox. You live in a floating cloud village, step into one of five
glowing **portals** with up to three friends, and get flown to a freshly generated **sky course** that you climb
as a team: dash over gaps, dodge spinning bars, lightning and swinging beams, share checkpoints and pick each
other back up. Along the way you collect **Cloud Tokens**, and back home you spend them on **pets** (from
roulettes) and **usable items**, fill your **Pet Index**, and build your own **tycoon home**: claim a plot at
its gate, put your pets in your **Pet Garden** where they make rainbow coins (that is your **Cash**), grow food
plants, feed your pets at the Food Machine, **EVOLVE** them, train their battle skills, fuse them and prestige.
Then send your pet team into the **Battle Arena**: Trials against NPC teams, duels against other players, Boss
Raids that the whole server fights together and the endless **Champion Ring**.

Version 3 turns Nimbus Climb into a multi-concept game: the **tycoon homes** are the main mode, **pet battles**
are the second one, and the climb (obby) stays as a side mode. This build is **v3 phase 4**: phase 1 brought the
new look, the pet collection and everything the later updates build on (see
[What's new in v3](#whats-new-in-v3-phase-1)), phase 2 added the tycoon homes, Cash, Gems, prestige and the Fusion
Machine (see [Tycoon homes](#tycoon-homes)), phase 3 added the **Battle Arena**: Trials, duels and Boss Raids with
your pet team (see [Pet battles](#pet-battles-phase-3)), and phase 4 makes your **pets make the money** (see
[What's new in phase 4](#whats-new-in-phase-4-pets-make-the-money)).

Everything is built in code from plain parts and particles (no toolbox models), and all text uses one small
`Theme` module, so the whole game shares the same chunky, friendly look. The only asset id in the code is the
owner's own Stormfang artwork (`Config.Art.StormfangImage`).

## What's new in phase 4: pets make the money

- **Your pets make the money.** Build your free **Pet Garden** and put pets in it (**3 places**, +1 every Prestige).
  They eat from their bowls and pop out **rainbow coins**. Walk over the coins to scoop them: only YOU can scoop
  yours. Economy pets make 60 % more than Combat pets; rarer, higher-level, Golden / Rainbow and evolved pets make
  more. Garden pets can still follow you and fight.
- **Your presses grew into food plants.** Berry Bush, Carrot Patch, Cloud Melons, Starfruit Tree: tastier food makes
  every coin bigger. The Collector is now a **Coin Magnet**: coins fly to you from farther away and piles hold more.
  Same pads, same levels, same Home Level: nobody loses a level.
- **Coins wait for you.** A pile holds a few minutes of coins; when it is full the pet takes a nap (Zzz) until you
  scoop. Coins left on the lawn are saved; the Vault adds offline coins; both wait in a big Welcome-back pile by
  your garden gate. Sometimes a sparkly **Lucky coin** pops out (worth 5 coins): more often with a higher Garden
  level.
- **Food Machine** (the old Kitchen): press **E**, pick a pet and press **Feed**: it costs Cash and fills a quarter
  of the pet's XP bar. Upgrade the machine for bigger meals (up to half a bar) for the same price. Leftover Snacks /
  Meals / Feasts from the old Kitchen are fed first, for free.
- **Every fight gives XP** (a win the full amount, a loss a third if your pets really fought). The Champion Ring is
  the best free XP in the game.
- **EVOLVE!** At level 20 a pet glows "Ready to evolve!": press **EVOLVE** and watch it change. Evolved pets are
  25 % stronger and richer. Epic and rarer pets evolve again at level 50 (50 % in total). Every pet can reach
  **level 100**; each level takes more XP than the one before.
- **Training Place** (the old Gym): press **E**, pick a pet and a skill (Attack Speed, Physique, Ability, Defense).
  Rank 3 takes 3 minutes. A training pet rests at home: it cannot follow you or fight until it is done, then it
  comes back by itself. **Stop** gives the Cash back.
- **Champion Ring:** the new portal on the plaza. You need a home and a pet. One champion at a time, each stronger
  than the last; every 10th is a giant boss. Every win pays Cash and XP, a new record pays triple Cash, beating a
  boss round for the first time pays 100 Tokens. Lose once and the run ends. Start from round 1 or from any boss
  round you beat.
- **Pet cards:** a small card above each of your pets shows its level and XP; in battles also health and SPECIAL.
  Your pets now follow right **behind** you.
- **Portal home:** **Go home** opens a small magic portal only you and your pets can use.
- **Safe zones:** outside the Battle Arena and the battle rings, nothing can hurt you or your pets.
- **Prestige:** Home Level 40 + Sky Castle. Stations and Cash reset (the Garden stays), +1 star: coins x1.25
  forever, +1 garden place, Gems; prices go up by half after every Prestige (x1.5, x2.25, x3.38 ...). Pets, levels,
  evolutions, training, decor and garden pets are kept. Players from before Phase 4 keep their extra garden places
  and their old prices until their next Prestige (see [Homes from before Phase 4](#homes-from-before-phase-4)).
- **And around it:** the tutorial's home chapter is rewritten for the garden and a fourth chapter teaches training,
  the ring and the portal; new NPC tips; for the owner the `/petlevel` command and the steps to publish the update
  safely (see [Publishing an update](#publishing-an-update-owner)).

## What's new in phase 3: pet battles

- **The Battle Arena.** A big colosseum on its own cloud island. Walk over the stone bridge from the village street,
  or build the **Arena Gate** at home and press **E** at it to be there at once.
- **Your battle team.** The new **Team** tile in the menu: pick up to 3 pets (a 4th slot opens at **Prestige 1**),
  save up to 3 teams and see their power and element bonuses.
- **Real-time battles.** Your pets fight on their own; you lead them with **ATTACK** (`F`), **RETREAT** (`R`) and
  one **SPECIAL** per pet (`1`-`4`), or with big touch buttons on a phone.
- **Trials 1-30.** The **Trial Portal** next to the five climb portals opens 30 levels of NPC pet teams, a
  mini-boss every 5 levels, tokens, pet XP and Gems for first clears.
- **Duels and trophies.** Challenge another player on the arena's duel rings or join the quick queue, win
  **trophies** and climb the trophy **leaderboard**. Nobody ever loses a pet.
- **Boss Raids.** About every 20 minutes a giant boss (Storm Titan, Lava Golem, Frost Wyrm or Shadow Hydra) stomps
  into the colosseum and everyone fights it together: dodge its glowing attacks, win tokens, XP, Gems and maybe one
  of the three **Boss Raid pets**. Every few hours a **Double Rewards** hour doubles the battle tokens.
- **And around it:** a third tutorial chapter, new NPC tips about battles, and for the owner the **Start Boss
  Raid** button (`/raid`) plus the evolved pet forms in the developer pet showcase (see
  [Developer tools](#developer-tools-owner-only)).

## What's new in phase 2: tycoon homes

- **Claim a home.** The 16 plots on the outer ring are classic Roblox tycoons now: walk up to a free gate and
  press **E**. Your build is saved with your profile and comes back on whichever plot you claim next time.
- **Buy pads.** Glowing pads on your yard build everything, step by step: the money makers, a **Pet Garden**, a
  **Vault**, your **House** (Cottage, Villa, Manor, Sky Castle: a new house every 10 Home Levels) and decor. (Phase 4
  turned the old Cloud Presses into food plants, the Collector into the Coin Magnet, the Kitchen into the Food
  Machine and the Gym into the Training Place.)
- **Prestige.** At Home Level 40 with the Sky Castle you can start over for a star, Gems, and from the first star
  on the **Fusion Machine** (Golden and Rainbow pets, one-of-a-kind hybrids).
- **Gems.** The premium currency: earned by prestiging and bought with Robux (once the owner has created the gem
  packs), spent on cheap roulette spins and on the gems-only **Secret Roulette** at the Storm Altar, the only way
  to get Secret pets like Stormfang.
- **And around it:** a second tutorial chapter with Nimbus, new NPC tips, a **Home** window, a Gems tab in the
  Shop, a Fusions tab in the Pet Index, Cash and Gems on the HUD, and +Cash / +Gems developer tools for testing.

## What's new in v3 (phase 1)

- **Detailed voxel art everywhere.** Every pet is sculpted in a fine "MagicaVoxel" style: rounded heads, 2-3
  shades per colour, fur patterns, claws, inner ears and eyes carved *into* the face (dark iris, white highlight,
  brows), not stuck on. Each species has its own details (cat tufts, corgi ears, fox ruffs, dragon crests ...).
  Your own pets use the full-detail model, other players' pets a lighter one, so the game stays smooth.
- **A brighter, warmer village.** Puffy sculpted voxel clouds in soft whites and blues, real moving sky clouds,
  detailed ground (stone, sand and wooden paths, lawns, flower beds), trees, lamps, benches, fences, banners and
  fountains, and a friendlier afternoon sun. Tokens are now detailed gold coins with a cloud emblem, and their
  glow moves with the coin.
- **The Sage Dragon.** A giant eastern dragon (sage-green scales, gold antlers, whiskers and a flowing mane)
  swims slow loops in the sky above the village, trailing little cloud puffs. It is only for looks.
- **Stormfang and the Storm Altar.** The owner's own creature, a storm lynx in charcoal armour with glowing blue
  eyes, neon claws and a cyan forehead gem, riding a little storm cloud, is the game's signature **Secret pet**.
  It prowls on the **Storm Altar**, a dark storm-cloud island at the edge of the village with a ring of
  glowing crystals (cross its bridge from the street and press **E** at the altar). Since phase 2 the altar is
  the gems-only **Secret Roulette** where Secret pets are summoned with Gems.
- **Pet elements.** Every pet now has one of eight elements (see [Elements](#elements)), shown as a coloured
  badge in the Pet Index, the Pets window and the roulette odds list.
- **The Pet Index.** A collection book of every pet: undiscovered pets are black `???` silhouettes; complete a
  rarity group to claim a token reward (see [Pet Index](#pet-index)).
- **A tutorial.** Nimbus, the Cloudy Dragon, guides new players step by step from a small side panel, with a
  golden arrow and a sparkle trail that lead the way (see [First steps](#first-steps-the-tutorial)).
- **NPC pets.** Six big friendly pets around the plaza share tips: walk up and press **E** to talk.
- **Bigger, clearer UI.** Larger text everywhere (it scales with your screen and never gets too small on a
  phone), a new menu of square tiles, a new health and stamina card with a token counter above it, and readable
  name tags in the world that keep the same size on screen when you zoom out.
- **Portal lock-in.** Once you step on a portal pad you stay in the party until launch; the big red **Leave**
  button is the only way out, and friends outside see the countdown right on the gate.
- **Home plots.** The 16 player spots are now big fenced home plots, which phase 2 turns into tycoon homes.
- **Developer tools for the owner** (see [Developer tools](#developer-tools-owner-only)): a DEV panel and chat
  commands to get every pet, add tokens, Cash or Gems, replay the tutorial or reset your data while testing.

## How to open the game

**Just play (nothing to install):** open `play/NimbusClimb.rbxlx` in Roblox Studio (double-click it, or
File -> Open from File) and press **Play**. It is a ready-made copy of everything in `src/`.

**One-click Rojo launchers (to edit the code with live sync):** extract the ZIP first (never run anything from
inside it), then start the Rojo server with the launcher for your computer. The first run downloads Rojo 7.7.1
(about 5 MB). Keep the window open, open a Baseplate place in Studio, click **Plugins -> Rojo -> Connect**
(install the Rojo 7.7.1 plugin once), then press **Play**.

- **Windows:** double-click `Start-Rojo-Windows.bat`. If it says the server stopped with "already in use",
  another Rojo window is still open: close it and try again.
- **Mac:** `Start-Rojo-Mac.command` is blocked the first time because it came from a download. Easiest fix
  (works on every macOS): open Terminal, type `bash ` (with a trailing space), drag the file from Finder into the
  window and press Enter. Alternatives: right-click -> **Open** (macOS 14 and earlier), or double-click once,
  then System Settings -> Privacy & Security -> **Open Anyway** (macOS 15 and later; the button stays for about an
  hour). If macOS asks about the Downloads folder, click **Allow**.

Prefer the command line? In this folder run `rojo serve` (needs Rojo 7.7.1, [Rokit](https://github.com/rojo-rbx/rokit)
or the VS Code "Rojo" extension are the easy ways to get it).

**Place settings that matter**

- **Max Players: 16 or less** (a place setting, in Studio's Game Settings or the place's settings on the Creator
  Hub). The village has exactly 16 home plots (`Config.Lobby.SpotCount`); a 17th player would still play but
  could not claim a home until a plot frees up.
- **Saving needs a published place.** Tokens, Cash, Gems, pets (with their levels, evolutions, trained skills,
  Golden / Rainbow copies and hybrids), leftover food, items, stats, your home build and the coins on your lawn,
  your battle teams, trophies, Trial progress, your Champion Ring record and Boss Raid pets, Pet Index progress and
  the tutorial step are saved in a DataStore, and DataStores only work in a place published to Roblox (File ->
  Publish to Roblox). In Studio also turn on Game Settings -> Security -> **Enable Studio Access to API Services**.
  Without these the game still runs, it just forgets everything when you stop. Saves happen on leave, every 90 s
  and at server shutdown (older v1, v2 and v3 saves are migrated automatically, see
  [Homes from before Phase 4](#homes-from-before-phase-4)).
- **After publishing an update, move the live servers to it.** Once people play the game, every time you publish
  a new version use **Migrate to Latest Update** on the Creator Hub (the steps are in
  [Publishing an update](#publishing-an-update-owner)).
- **Gem packs need Developer Products.** Until you create them (see
  [Selling Gems](#selling-gems-the-owners-setup)), the Shop's Gems tab says the packs open soon. Everything else
  works without them: players still earn Gems by prestiging.
- Leave *StreamingEnabled* off. Everything else (sky, lighting, gravity, the village) is created by the scripts,
  so an empty baseplate is all you need. To test parties and duels use Test -> Clients and Servers with 2-4
  players (see [Testing battles in Studio](#testing-battles-in-studio-owner)).
- **The Stormfang artwork** (Storm Altar poster, Stormfang's Pet Index banner) is the image id in
  `Config.Art.StormfangImage`. If it shows up blank, the image is still waiting for Roblox moderation, or the id
  needs replacing with your own upload.

## Controls

| Action | PC | Mobile | Gamepad |
|---|---|---|---|
| Move | `W` `A` `S` `D` | thumbstick | left stick |
| Jump | `Space` | jump button | `A` |
| Run (drains stamina) | hold `Shift` | **RUN** button (tap to toggle) | `L3` (toggle) |
| Dash (35 stamina, 1.6 s cooldown, works in the air) | `Q` | **DASH** button | `B` |
| Use an item | `1` `2` `3` `4` (or click / tap a slot) | tap a slot | - |
| Talk to an NPC pet, use the Storm Altar, claim a home, put a pet on a garden spot, use the Food Machine (*Feed pets*), the Training Place (*Train pets*), the Fusion Machine, the Arena Gate, the Trial Portal, the Champion Ring portal, a duel pad or the arena boards | `E` | tap the prompt | `X` |
| Buy at a home pad (hold a moment) | hold `E` | hold the prompt | hold `X` |
| Scoop your rainbow coins | walk over them | walk over them | walk over them |
| Go home through your own portal | **Home** tile -> **Go home**, then walk into the portal | the same | the same |
| Battle: **ATTACK** (your pets fight) | `F` | **ATTACK** button | `X` |
| Battle: **RETREAT** (your pets run back to you) | `R` | **RETREAT** button | `Y` |
| Battle: a pet's **SPECIAL** (when its card glows) | `1` `2` `3` `4` (or click its card) | tap its card | `LB` `RB` `LT` `RT` |
| Battle: focus one enemy | click it (or its chip at the top) | tap it | - |
| Open the Pets window on a pet that is ready to evolve | click its gold **EVOLVE!** pill | tap the pill | - |
| Close a window | `Esc` or the red X | red X | `B` |

## First steps: the tutorial

New players meet **Nimbus**, the Cloudy Dragon, in a small card on the left of the screen (never in the middle).
Nine short steps teach the basics: say hello, claim your home plot (follow the arrow to a free gate and press
**E**), find the Cloud Shop, spin your first roulette (Nimbus gives you **50 Cloud Tokens** for it), equip your
new pet (it follows right behind you), peek into the Pet Index, step into the Easy portal, play your first climb to
the end, and collect **100 Cloud Tokens** at the end. A golden arrow, a sparkle trail and a distance sign point at
places in the world; a pulsing ring points at menu tiles.

A second chapter teaches the tycoon home in five steps: *Claim Your Home* (already done if you claimed it in the
first chapter), *Your Pet Garden* (build the free Pet Garden, then press **E** on a garden spot to put a pet in it),
*Rainbow Coins!* (walk over your pet's coins to scoop them), *The Food Machine* (follow the arrow from pad to pad
until you can build it) and *Snack Time!* (press **E** at the Food Machine, pick a pet and press **Feed**). Nimbus
pays **1,000 Cash** at the end. Players who finished the phase 1 tutorial start right at this chapter.

A third chapter teaches pet battles in four steps: follow the arrow over the bridge into the Battle Arena, tap
**Team** and put your pets in your team, press **E** at the Trial Portal and win Trial level 1 (it is made so that
any single level-1 pet wins it, even without pressing SPECIAL), then join or watch a Boss Raid. Nimbus pays
**500 Cloud Tokens** at the end. Players who finished the first two chapters start right at this one.

A fourth chapter teaches the phase 4 pet care in three steps: *Training Time* (start a training at your Training
Place), *The Champion Ring* (press **E** at the Champion Ring portal on the plaza and win a round) and *Portal Home*
(tap **Home**, then **Go home**, and hop into your portal). Nimbus pays **300 Cloud Tokens** at the end. Players who
had finished the whole tutorial before phase 4 start right at this chapter.

Tap Nimbus' portrait to fold the card into a small bubble (and again to open it). The **Skip tutorial** link
ends it (it asks first). Your step is saved, so the tutorial continues where you left off.

## The village

- **The plaza** in the middle, with the five difficulty **portals** on a ring around it, and next to them the
  crimson **Trial Portal** with crossed swords (see [Trials](#trials-1-30-the-trial-portal)) and the golden
  **Champion Ring** portal (see [the Champion Ring](#the-champion-ring)).
- **The shop island** (follow the boardwalk): four roulette machines and the item counter.
- **Six NPC pets** stand along the plaza and the paths. Each one has a name tag; walk up and press **E** to
  talk. They cycle through a few tips each (Next / Close):

  | NPC | Talks about |
  |---|---|
  | **Sparky Fox**, Movement Trainer | running, dashing, dash-only gaps, items, the battle keys (ATTACK, RETREAT, SPECIAL) |
  | **Captain Penguin**, Co-op Captain | parties, reviving teammates, Phoenix Feather, Boss Raids, the safe zone outside the Battle Arena and RETREAT out of glowing circles |
  | **Granny Owl**, Pet Expert | roulettes and their chances (also with Gems), the Pet Index, the Food Machine (Feed) and the EVOLVE button |
  | **Coach Corgi**, Token Coach | keeping every token of a climb, the Trial Portal, the Training Place, the Champion Ring and beating your record, your battle Team, duels and trophies |
  | **Mayor Panda**, Village Mayor | claiming a home at a free gate (press E), the Pet Garden and its rainbow coins, the Berry Bush and the other food plants, Economy pets, Home Level, Prestige, the Home window and the home portal |
  | **Professor Axolotl**, Element Scholar | elements, elements in battles and team synergy, the Fusion Machine, Gems and the Secret pets of the Storm Altar |

- **The Storm Altar** on its dark storm cloud at the village edge, with Stormfang prowling over the portal
  disc. Press **E** at the altar to open the gems-only **Secret Roulette** (see
  [Gems](#gems-and-the-secret-roulette)).
- **The 16 home plots** on the big outer ring (see [Tycoon homes](#tycoon-homes)).
- **The Battle Arena** on its own cloud island beyond the homes, reached by a stone bridge from the village street
  (see [Pet battles](#pet-battles-phase-3)).
- **The Sage Dragon** in the sky above it all.

## The five portals

Stand on a portal pad to join its party (1-4 players). A 15 s countdown starts (4 s once the party is full),
then everyone is flown to the start platform of a new course. While the countdown runs you are **locked in**:
soft walls in the portal's colour keep you on the pad, and the only way out is the big red **Leave** button in
the party panel (top-left). Everyone else walks through those walls freely. A name tag above each gate shows
its party ("2/4 players") and status, and friends standing next to the portal see a big countdown on the gate.

Every course is generated from a seed, in one of four shapes (Straight, Zigzag, Serpent, Spiral) and mixed
from stage themes (moving clouds, spinning bars, storms, lightning, vanishing steps, cannons, wind, pendulums,
co-op plate bridges, dash-only gaps ...), and it is validated for reachability before it is built.

| Portal | Stars | Stages | Time limit | Void fall costs | Win bonus | Feel |
|---|---|---|---|---|---|---|
| **Easy** | 1 | 4 | 9 min | 10 HP | 10 tokens | Chill clouds and wide steps. |
| **Medium** | 2 | 5 | 12 min | 15 HP | 20 tokens | Moving clouds, spinning bars, your first co-op bridge. |
| **Hard** | 3 | 6 | 15 min | 22 HP | 35 tokens | Vanishing steps, lightning, swinging beams. |
| **Extreme** | 4 | 8 | 20 min | 30 HP | 60 tokens | Dash-only gaps, storms, narrow beams. Bring friends. |
| **Saint** | 5 | 10 | 25 min | 40 HP | 100 tokens | Tiny steps, relentless hazards. |

Team rules: the first player to touch a checkpoint sets it for everyone, heals the living (35 %) and revives all
downed teammates. A lethal hit does not kill you, it leaves you **downed** (1 HP, frozen) until a teammate reaches
the next checkpoint. If everybody is downed, or time runs out, the team loses; if every living player stands on the
finish pad, it wins. Falling into the void, or missing a jump onto a lower lap of a spiral, costs health and puts
you back at the team checkpoint. Golden tokens (worth 5) sit on the riskiest steps.

## Tycoon homes

The 16 home plots on the village's outer ring are classic Roblox tycoons: claim one at its gate, then build it
up pad by pad until a Sky Castle stands on it, and prestige for a star. Since phase 4 **your pets make the money**:
they eat in your Pet Garden and pop out rainbow coins. What is saved is **your home build**, not a plot number: it
is rebuilt on whichever plot you claim. All the numbers below live in `src/shared/TycoonCatalog.lua`, balanced with
the progression simulation `tools/sim_tycoon.py` (an active player buys the first paid pad within half a minute,
something new every 1-3 minutes early on, gets the Villa after about half an hour, evolves a first pet after about
1 h 20 min and reaches the first Prestige after about 2 h 25 min; the second run takes about an hour, the third a
little less).

### Claiming a home

- Walk up to a free gate (its signpost and name tag say **Free home**) and press **E** (*Claim Home*). One home
  per player, and not during a climb.
- The plot is yours until you leave the server. Then it is released: your build disappears from it (it is safe in
  your save) and the gate offers *Claim Home* to someone else.
- Coming back? If your last plot is free you get a side toast "Welcome back! Press E at your gate (#7)". Any other
  free plot works just as well: your whole build comes back on it.
- The **Home** tile of the menu opens a magic portal toward a free gate while you have no home; once you have one it
  opens the [Home window](#the-home-window), whose **Go home** button opens your own portal home. Nimbus' arrow leads
  to a free gate too.
- The name tag over the mailbox shows your avatar, your name, your **Home Level** and one star per **Prestige**,
  and the podium by the gate shows a slowly turning copy of your best pet (rarest first, Rainbow and Golden copies
  before plain ones). With a home, you respawn there instead of on the plaza.

### The home portal

**Go home** (in the Home window) opens a small glowing portal on the ground a few steps in front of you, with your
name over it. Walk into it within 10 seconds and you pop out at your home, your pets diving in after you. Only you
and your pets can use your portal; other players just see it. It does not open during a climb, a battle or a
Champion Ring run, or while you wait in a portal party.

### Buy pads and Home Level

Everything on the yard is built from a **buy pad**: a glowing pad with a floating sign (icon, name, *Build* or
*Lv 2 -> 3*, and the price in **Cash**). Stand on it and hold **E** for a moment (*Buy*). Only you see and use
your own pads (other players' prompts stay off), and the server checks the owner, the price and the requirements
of every purchase.

- A brand-new home shows exactly one pad: the **free Pet Garden**. The station pops in with a little voxel
  animation, and new pads appear as your home grows (the Berry Bush after the Garden, the Coin Magnet and the Food
  Machine after the Berry Bush, the Carrot Patch when the Berry Bush reaches level 2 ...), so the yard fills up step
  by step. The pad stays in front of a built station for its upgrades.
- A locked pad says why: *Reach Home Level 10*, *Needs the Villa*, *Unlocks at Prestige 1* (with a blue
  hologram of what is coming) or *Coming soon*.
- **Home Level** = every purchase and every upgrade you made: each one adds 1.
- The prices below are for a home without stars: after every Prestige the pads cost half as much again (see
  [Prestige](#prestige)).

### Cash: your pets make it

**Cash** is the tycoon currency (Cloud Tokens stay the climb currency). Pets in your **Pet Garden** eat and pop out
rainbow coins, and you scoop the coins by walking over them (see [the Pet Garden](#the-pet-garden-and-rainbow-coins)).
Champion Ring wins pay Cash too. The food plants make every coin bigger, the Coin Magnet and the Vault let the piles
hold more, and the Vault adds coins while you are away.

### Every station

| Station | What it does | Levels | Needs | Price (level 1 -> top) |
|---|---|---|---|---|
| **Pet Garden** | Your pets eat here and pop out rainbow coins (3 places + 1 per Prestige); Lucky coins 0 % -> 15 % | 8 | claiming | free -> 2,400,000 |
| **Berry Bush** | The first food plant: +7 -> +76 food per meal | 10 | the Pet Garden | 15 -> 270,000 |
| **Carrot Patch** | A bigger food plant: +19 -> +199 food per meal | 10 | Berry Bush Lv 2 | 420 -> 680,000 |
| **Cloud Melons** | Juicy sky melons: +49 -> +518 food per meal | 10 | the Villa + Carrot Patch Lv 3 | 18,000 -> 1,800,000 |
| **Starfruit Tree** | The best food plant: +127 -> +1,339 food per meal | 10 | the Manor + Cloud Melons Lv 3 | 160,000 -> 3,200,000 |
| **Coin Magnet** | Coins fly to you: scoops from 9 -> 26 studs, piles hold 5 -> 10 min of coins | 5 | the Berry Bush | 90 -> 1,400,000 |
| **Food Machine** | Turns Cash into pet XP: a feed fills 25 % -> 50 % of the XP bar | 5 | the Berry Bush | 240 -> 1,900,000 |
| **Training Place** | Pets learn battle skills: 1 -> 5 pets train at once | 5 | the Food Machine | 3,000 -> 2,200,000 |
| **Vault** | Bigger coin piles (piles +5 -> +30 min) and offline coins | 5 | Carrot Patch Lv 2 | 9,000 -> 2,000,000 |
| **House** | Cottage -> Villa -> Manor -> Sky Castle (see below) | 4 | the Coin Magnet | 180 -> 880,000 |
| **Fusion Machine** | Golden / Rainbow upgrades and hybrids; -10 % / -20 % token costs at Lv 2 / 3 | 3 | the Food Machine + **Prestige 1** | 25,000 -> 1,400,000 |
| **Arena Gate** | Opens the way to pet battles: press **E** at it to go straight to the Battle Arena | 1 | the Training Place | 260,000 |
| **Lanterns** | Decor along the path (wood, brass, crystal) | 3 | the Coin Magnet | 1,800 -> 360,000 |
| **Garden Fence** | Decor around the yard (picket, hedge, cloudstone) | 3 | Carrot Patch Lv 2 | 7,000 -> 490,000 |
| **Flower Beds** | Decor along the front fence (tulips, roses, starflowers) | 3 | the Pet Garden | 2,700 -> 410,000 |
| **Fountain** | Decor in the middle of the yard (basin, tiered, sky) | 3 | the Villa + the Food Machine | 45,000 -> 1,500,000 |
| **Banners** | Decor along the front fence (cloth, gold, royal) | 3 | the Vault | 12,000 -> 650,000 |
| **Pet Podium** | Dresses up the podium of your best pet by the gate | 3 | the Pet Garden | 9,000 -> 580,000 |

A pad shows up as soon as the stations it needs are built; until the rest is there too (a house tier, a Prestige
star) its sign says what is missing. Every station grows visibly with its level (a level-1 Berry Bush is a small
shrub, a level-10 one a big bush heavy with berries). Decor is cheap, counts toward your Home Level like everything
else and is **kept when you prestige**.

### The house: a new tier every 10 Home Levels

The House pad builds a **Cottage** (180 Cash). The next houses are deliberately hard to get: the **Villa** needs
Home Level 10 (24,000 Cash), the **Manor** Home Level 20 (200,000) and the **Sky Castle** Home Level 30 (880,000);
until then the House pad says *Reach Home Level N*. Every new house raises how far the other stations can level:

| Max level with the ... | Cottage | Villa | Manor | Sky Castle |
|---|---|---|---|---|
| Berry Bush and Carrot Patch | 6 | 8 | 9 | 10 |
| Cloud Melons | - | 6 | 8 | 10 |
| Starfruit Tree | - | - | 8 | 10 |
| Coin Magnet | 2 | 3 | 4 | 5 |
| Pet Garden | 2 | 4 | 6 | 8 |
| Food Machine, Training Place, Vault | 1 | 2 | 4 | 5 |
| Fusion Machine | 1 | 2 | 3 | 3 |
| Decor | 1 | 2 | 3 | 3 |
| Fountain | - | 1 | 2 | 3 |

### The Pet Garden and rainbow coins

Your pets make the money here. Build the free **Pet Garden** (the first pad of every home), then press **E** on an
empty garden spot (*Put a pet here*) and pick a pet, or open **Pets**, pick a pet and press **Garden**. The Garden
has **3 places** at first and gets **+1 every Prestige** (up to 12 places). Any pet can work there, Economy or
Combat, and garden pets can still follow you and fight at the same time. Only a pet in training cannot (see
[the Training Place](#the-training-place)).

Every pet on an open place eats from its bowl, **one meal every 8 seconds**, and pops out a **rainbow coin**. A
coin is worth the food of your home x the power of the pet x your Prestige bonus:

- **Food:** the grass of a built Garden gives 12 food, and every food plant adds its food (see the station table).
  A new Garden with a level-1 Berry Bush has 19 food, so a level-1 Common Combat pet makes **$19 every 8 seconds**.
- **The pet's power:** its rarity (Common x1 up to Secret x13) x its level (+10 % per level) x its tier (Golden
  x1.5, Rainbow x2.5) x its role: **Economy pets x1.6**, they make 60 % more than Combat pets x its evolution (+25 %
  after the first EVOLVE, +50 % after the second).
- **Prestige:** x1.25 coins per star (see [Prestige](#prestige)).
- Sometimes a sparkly **Lucky coin** pops out, worth x5. Your Garden level decides how often:

| Garden level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| Lucky coin chance | 0 % | 2 % | 4 % | 6 % | 8 % | 10 % | 12 % | 15 % |

**Scooping:** each pet's coins pile up on the walk in front of it. Walk over them and they are yours, no button
needed. **Only you can scoop your own coins**: other players see them dimmed, and the first time they come close a
hint says "Only the owner can pick these up". Without a Coin Magnet you scoop the coins within 6 studs of you; the
Magnet pulls them in from farther away (up to 26 studs at level 5).

**Piles and naps:** a pile holds a few minutes of its pet's coins: 4 minutes without a Coin Magnet, more with the
Magnet and the Vault. When a pile is full the pet lies down for a nap (a little "Zzz") and eats nothing until you
scoop it, so come back now and then. Coins left on your lawn are saved with your home and wait for you in the
**Welcome-back pile** by your garden gate. A pet on a place that is not open any more (after a Prestige ended your
old extra places, see [Homes from before Phase 4](#homes-from-before-phase-4)) sleeps on a closed bed and makes
nothing until a place opens.

### The Food Machine and pet levels

The **Food Machine** (the old Kitchen) turns Cash into XP. Press **E** at it (*Feed pets*), or press **Feed** on a
pet in the Pets window: a list of your pets opens (garden pets first, then the ones following you, then the rest).
Every row shows the pet's level, its XP bar and two buttons:

- **Feed** fills a part of the pet's XP bar: 25 % of the XP bar at Food Machine level 1, up to 50 % at level 5.
  Upgrading the machine gives bigger meals for the same price.
- **Level up** buys all the feeds the next level needs (at most 10) in one go, for one price.

A feed costs the XP the pet still needs for its next level x its rarity (Common x1 up to Secret x13) x 2 Cash,
whatever the machine level: a level-1 Common pays **$40** for **5 XP**, a level-19 Common **$4,450** for **556 XP**.
Rarer pets eat fancier food, and their coins grow just as much. A pet at the top level says *Max level*.

**Leftover food** from the old Kitchen (Snacks, Meals and Feasts) is fed first, for free: the button says for
example "Feed (free Feast, 3 left)".

| Leftover food | XP |
|---|---|
| **Snack** | 25 |
| **Meal** | 150 |
| **Feast** | 800 |

**Levels:** every pet can reach level **100**. **Every level adds 10 %** of the pet's level-1 stats (a level-50 pet
has x5.9, a level-100 pet x10.9), and each level takes more XP than the one before:

| Level up | XP needed |
|---|---|
| 1 -> 2 | 20 |
| 10 -> 11 | 795 |
| 19 -> 20 | 2,225 |
| 49 -> 50 | 10,125 |
| 99 -> 100 | 31,190 |

That is 17,375 XP in total to reach level 20, 195,880 to reach level 50 and 1,203,340 to reach level 100. A toast
tells you about every level-up (one toast, even when a big meal jumps several levels). Levels belong to the pet
(every copy of the same pet and tier shares them) and are kept through Prestige.

**Every fight gives XP** too, to every pet of your team:

| Where | XP for every team pet |
|---|---|
| A Trial win | 20 + 6 x the level (26 up to 200) |
| A lost Trial | a third of the win XP, when your pets really fought (20 seconds or more, or 20 % of the enemy team's health) |
| A duel | 60 for a win, 25 for a draw or a loss |
| A Boss Raid | 50 up to 400 by your tier (20 when the boss wins) |
| A Champion Ring round | 20 + 6 x the round (the round that ends your run pays a third) |

### Evolution: the EVOLVE button

At level **20** every pet is "Ready to evolve!": the level-up toast says so, its card gets a pulsing gold
**EVOLVE!** pill, and the Pets window and the Food Machine list show an **EVOLVE** button. Press it (and Yes): the
menu slides away, the pet charges up in a pillar of light right in front of you and bursts into its evolved form,
with confetti. An evolved pet is **+25 %** stronger in battle (power and health, so its special too) and makes 25 %
bigger coins. **Epic, Legendary, Mythic and Secret** pets evolve a second time at level **50** (+50 % in total);
Common, Uncommon and Rare pets evolve once. The bonus counts from the moment you press EVOLVE (never from the level
alone), so every pet gets its own big moment. Evolutions are kept through Prestige and fusion, and a star on the
pet's card shows them (★ / ★★). Not during a battle.

### The Training Place

The **Training Place** (the old Gym) teaches pets battle skills. Press **E** at it (*Train pets*) or press **Train**
in the Pets window, pick a pet and one of four skills:

| Skill | Each rank | At rank 10 |
|---|---|---|
| **Attack Speed** | +4% attacks per rank | +40 % |
| **Physique** | +5% max health per rank | +50 % |
| **Ability** | +4% special power and charge per rank | +40 % |
| **Defense** | -3% damage taken per rank | -30 % |

Every skill goes up to rank 10. Rank N costs **300 x N x N** Cash x the pet's rarity (a Common pays $300 for rank 1
and $30,000 for rank 10, all 40 ranks together $462,000; a Legendary x5.5) and takes N minutes: **Rank 3 takes 3
minutes**. Training prices never go up with Prestige. The Training Place level is how many pets train at once (1 to
5).

A training pet rests at home on its mat, with a purple timer on its card: it leaves the Garden and stops following
you, and it cannot follow you, fight or be fused until it is done ("Rocky is training (2:10 left)"). Then it gets
its rank and comes back by itself: to your side, or to its garden place. **Stop** ends a training early and gives
all the Cash back (no rank), but not after a Prestige: that Cash went with the old run. Training keeps going while you are away and through a Prestige: the rank is waiting
when you come back ("Training done while you were away!"). Trained skills count in every battle.

### The Vault and offline coins

The Vault makes every coin pile bigger and pays offline coins: when you come back after a while, a share of what
your pets make in that time waits in the big **Welcome-back pile** by your garden gate, together with the coins
you left on the lawn, and a side toast says "Welcome back! Your pets made $X while you were away: scoop it in your
garden!". Nothing is paid for absences under 2 minutes, and no offline coins without a Vault.

| Vault level | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Bigger piles | +5 min | +10 min | +15 min | +20 min | +30 min |
| Share of your income | 10 % | 15 % | 20 % | 25 % | 30 % |
| For up to | 1 h | 2 h | 3 h | 4 h | 4 h |

### Prestige

Prestige needs **Home Level 40 and the Sky Castle**. Once the Sky Castle stands, a star pad appears on your yard
(it says *Reach Home Level 40* until you get there). Hold **E** on it (or press Prestige in the Home window): the
Home window shows what starts over, what you keep and what you get, and nothing happens until you confirm there.
Scoop your coins first!

- **Starts over:** your Cash, the coins on your lawn and every station except the decor and the Pet Garden (it
  stays at level 1 with your pets in it, so the coins never stop).
- **You keep:** all your pets (with their levels, evolutions, trained skills, Golden / Rainbow copies and hybrids),
  your garden pets, your leftover food, your decor (it still counts toward your Home Level, so the next run starts
  ahead), trainings that are still running (they still finish for their rank; stopping one after the Prestige gives
  no Cash back), Cloud Tokens and Gems.
- **You get:** a **Prestige star** on your name tag, **x1.25 coins** per star forever (it multiplies: x1.56 at 2
  stars, x1.95 at 3 ...), **+1 garden place**, **Gems** (100 for the first prestige, 10 fewer for each later one,
  never under 25), and at Prestige 1 the **Fusion Machine** pad (and the 4th slot of your battle team).
- **Prices go up by half:** after every Prestige the stations cost half as much again: **x1.5** at 1 star, x2.25 at
  2 stars, x3.38 at 3 stars ... Feeds, training and roulettes never cost more.

### Homes from before Phase 4

Nobody loses progress. The first time an older save loads in phase 4:

- **Your presses grew into food plants** with the same levels: Cloud Press 1 is the Berry Bush, 2 the Carrot Patch,
  3 the Cloud Melons and 4 the Starfruit Tree. The Collector is now the **Coin Magnet**, the Kitchen the **Food
  Machine** and the Gym the **Training Place** (its level = training spots). Same pads, same levels, same Home Level
  and house.
- **Extra garden places:** an old Garden's level was its number of places (up to 8). If you had more than 3 + your
  stars, you keep that many places until your next Prestige. The Home window says so: "Kept from your old home: 6
  places and old prices until your next Prestige."
- **Old prices:** if you had prestiged before phase 4, you pay the old prices (no x1.5 per star) until your next
  Prestige.
- **Leftover food:** your Snacks, Meals and Feasts are fed first and for free at the Food Machine.
- **The Welcome-back pile:** the Cash that waited in your old Collector is now a coin pile by your garden gate: walk
  over it to scoop it.
- **Gym pets** are back with you (the XP they earned stays), and pets at level 20 or more are "Ready to evolve!".

On your first claim a toast says: "Welcome to the new home! Your presses grew into food plants, the Collector is now
a Coin Magnet, and your old Collector Cash waits in a coin pile by your garden. Put pets in your garden: they make
the money now!"

### The Fusion Machine (after Prestige 1)

Until your first Prestige the Fusion Machine pad is a blue hologram that says *Unlocks at Prestige 1*. Once it is
built, press **E** at the machine (*Fuse*) to open the Fusion window (only near your own machine, not during a
climb). It has two tabs:

- **UPGRADE:** 3 copies of the same pet and tier make 1 of the next tier: Normal -> **Golden** (x1.5 stats and
  perks, a gold shimmer) -> **Rainbow** (x2.5, an animated rainbow shimmer). The new copy keeps the level of its
  inputs.
- **MIX:** two different pets make a brand-new, one-of-a-kind **hybrid**: the body (species and special attack) of
  the first, the colours, wings and accessory of the second, the elements of both, the higher of the two
  rarities, stats = their average x1.2, and a blended name (Penguin + Phoenix -> "Pengnix"). Hybrids cannot be
  mixed again or upgraded.

Copies that are equipped or in the Garden are taken off first and the result takes over their place (the machine
refuses only when the inputs are your only equipped pets); a pet in training cannot be fused. Fusing keeps your
pet's evolution and training (a hybrid starts unevolved but keeps the better training of its parents). The
machine's level 2 and 3 take 10 % and 20 % off the token costs:

| Rarity | Upgrade to Golden | Golden to Rainbow | Mix |
|---|---|---|---|
| Common | 150 tokens | 450 tokens | 200 tokens |
| Uncommon | 300 | 900 | 400 |
| Rare | 750 | 2,250 | 1,000 |
| Epic | 1,800 | 5,400 | 2,500 |
| Legendary | 4,500 | 13,500 | 6,000 |
| Mythic | 10,000 | 30,000 | **60 Gems** |
| Secret | 25,000 | 75,000 | **150 Gems** |

A Mix pays for the higher rarity of its two pets. The Pet Index has a **Fusions** tile that lists your Golden,
Rainbow and hybrid pets.

### The Home window

The **Home** tile of the menu opens it (once you have a home): your house tier, Home Level and Prestige stars, the
**Pet Garden** card (coins waiting on your lawn, coins per minute, open places), the prestige progress (Home Level
x/40 and the Sky Castle) with the **Prestige** button, **Go home** (your [home portal](#the-home-portal)), and every
station with its level, what the next level does, its price and a **Build** / **Upgrade** button, or why it is still
locked. So you can upgrade from anywhere, without walking to the pad.

### Gems and the Secret Roulette

**Gems** are the premium currency (shown on the HUD next to your tokens and Cash). You get them from every
**Prestige** and by buying **Gem packs** with Robux in the Shop's **Gems** tab (once the owner has created them,
see below). You spend them on:

- **Roulette spins**, a cheaper premium way to roll, with the same odds as with tokens: Cloud 5, Storm 20,
  Sky 75 and Celestial 300 Gems a spin.
- **The Secret Roulette** at the **Storm Altar** (press **E** at the altar, or find it in the Shop's Gems tab):
  1,500 Gems a spin, **Mythic 85 %, Secret 15 %**. It is the only place the four roulette Secret pets come from
  (Stormfang, Eclipse Dragon, Obsidian Phoenix, Phantom Kitsune). The three Boss Raid Secrets (Magma Cub, Rime
  Wyrmling, Hydralotl) are in no roulette at all: they only drop in Boss Raids.
- **Fusion Mixes** with Mythic or Secret pets.

The odds of every roulette are always one tap away (the odds list). Where Roblox does not allow paid random items
for an account, the gem-priced roulettes and the Secret Roulette are hidden for that player and the altar says
it is not available on their account; Gem packs and everything else still work.

### Selling Gems: the owner's setup

The four Gem packs are **Developer Products**: one-time Robux purchases that you, the owner, create on the
Creator Hub. Until a pack has a real id it stays hidden (id `0` means "not created yet"), and with no pack
created the Gems tab says "Gem packs open soon!".

1. **Publish the game first** (File -> Publish to Roblox): developer products belong to a published experience.
2. Open the **Creator Hub** (create.roblox.com) -> **Creations** -> your experience -> **Monetization** ->
   **Developer Products**, and create a product for each pack: a name (for example "Pouch of Gems"), a
   description, an icon if you like, and the **price in Robux** you want to charge.
3. Copy each product's **ID** from the Developer Products list.
4. Paste the ids into `Config.Gems.Products` in `src/shared/Config.lua`, one per pack. `Gems` is how many Gems the
   game grants for that product (the Robux price is only set on the Creator Hub), `Name` is what the Shop shows:

   ```lua
   Config.Gems = {
       Products = {
           { Id = 1234567890, Gems = 100, Name = "Pouch of Gems" },  -- your real product ids here
           { Id = 1234567891, Gems = 550, Name = "Bag of Gems" },
           { Id = 1234567892, Gems = 1200, Name = "Chest of Gems" },
           { Id = 1234567893, Gems = 6500, Name = "Vault of Gems" },
       },
       -- (the rest of Config.Gems stays as it is)
   ```

5. Rebuild the place file (or let Rojo sync it into Studio), publish, then use **Migrate to Latest Update** so every
   server runs the new ids (see [Publishing an update](#publishing-an-update-owner)).

Good to know: use each product id for one pack only, and keep the products you sold alive on the Creator Hub.
Every purchase is granted **exactly once**: the purchase id is saved with the Gems in the player's save before
Roblox is told it went through, so a retried or repeated receipt (even after the player rejoined another server)
never pays twice, and a purchase whose save failed stays pending until Roblox asks again. Saving must work for
that (a published place, see [Place settings](#how-to-open-the-game)). In Studio, test purchases cost nothing and
grant the Gems right away. The gem prices of the roulettes (`Config.Gems.RouletteGemPrices`) and the Secret
Roulette's price and odds (`Config.Gems.SecretRoulette`) are in the same table. The game sets
`MarketplaceService.ProcessReceipt` in one place only (`GemService`): Roblox allows one per game, so do not add
another one.

## Pet battles (phase 3)

Your pets can fight. Battles happen in the **Battle Arena**, in the **Trials** and in the **Champion Ring**. The
server runs every fight and decides every hit; your pets move and attack by themselves, and you lead them with
three kinds of buttons. Nobody ever loses a pet in a battle: a knocked-out pet just sits out until the fight is
over. All the numbers below live in `src/shared/BattleCatalog.lua`, balanced with the battle simulation
`tools/sim_battle.lua` (see `tools/README.md`).

**Safe zones:** pets fight only inside battle zones: the arena floor, the duel rings, the Trial pockets and the
Champion Ring. Everywhere else (the plaza, homes, the shop, the paths, the arena's forum and stands) is a safe zone:
no fights, no damage, and nobody can pull you into a battle. A side toast tells you when you walk into the Battle
Arena ("Battle Arena: pets can battle here") and out again ("Safe zone").

### Getting to the Battle Arena

- **The bridge:** follow the village street past the five portals to the stone bridge with the **BATTLE ARENA**
  arch and walk across. The arena is a big colosseum on its own cloud island: the round **boss floor** inside, two
  **duel rings** on the square in front of it, the **event board** (next event and its countdown) and the **trophy
  leaderboard** next to the main gate.
- **The Arena Gate at home:** build the **Arena Gate** pad on your yard (after the Training Place) and press **E**
  at the gate: it takes you straight to the arena (not during a climb or a battle).
- **The Trial Portal** and the **Champion Ring** portal are not in the arena: they stand on the plaza next to the
  five climb portals.

The battle buttons only work inside a battle; everywhere else your pets just follow you as usual.

### Your battle team: the Team screen

Tap the **Team** tile in the menu. You have **3 team slots** (a **4th slot opens at Prestige 1**) and up to
**3 saved teams** (the tabs *Team 1* to *Team 3*); **Use this team** picks the one you fight with. Tap a slot, then a pet: every pet
shows its element, level and battle stats. The screen shows your **team power** (compare it with a Trial's
recommended power), the element bonuses your team gets right now and the element wheel. Garden pets can fight too
(they keep earning at home); a pet in training sits out until it is done (its tile says *Training*). Pet levels
count a lot: feed your pets at the Food Machine, evolve them and train their skills at the Training Place.

### In a battle: ATTACK, RETREAT, SPECIAL

| Button | PC | Phone | Gamepad | What it does |
|---|---|---|---|---|
| **ATTACK** | `F` | ATTACK button | `X` | Your pets go for the enemy. Click / tap an enemy first to make every pet focus it. |
| **RETREAT** | `R` | RETREAT button | `Y` | Your pets break off and run back to you. |
| **SPECIAL** | `1`-`4` (or click the pet's card) | tap the pet's card | `LB` `RB` `LT` `RT` | That pet's special attack, when its card glows gold. |

- **RETREAT** is how you dodge and rest: retreating pets take **50 % less damage** and heal **2 % of their health
  every second**. ATTACK works again after **1.5 s**. You do not have to press it: once every pet is back with you,
  they **go back to fighting by themselves after a short rest of 3 s** (the RETREAT button counts it down as
  *RESTING*). Press ATTACK any time to go back in sooner.
- **SPECIAL:** every pet has its own special attack (see the Pet Index). Its meter fills while the pet fights and
  gets hit (and slowly by itself); when it is full the card glows and you press its key or tap the card. A special
  waits while your team rests (the card says *ATTACK first*). The seven kinds: **Blast** (damage around the target),
  **Heal** (heals the whole team), **Shield** (shields the whole team for a few seconds), **Storm** (a storm cloud
  that hurts enemies under it), **Pounce** (a dash and one heavy strike), **Freeze** (enemies around the target
  cannot move or attack for a moment) and **Beam** (hits every enemy in a line).
- **The screen:** the top card shows the fight (enemies or the boss, the time left); your team's cards with health
  and special meters and the ATTACK / RETREAT buttons sit at the bottom right on a computer and at the screen edges
  on a phone. Nothing covers the middle of the screen. Above every pet in the battle floats its
  [pet card](#pet-cards-and-following): yours with level, health, the gold SPECIAL bar and XP, the enemies with
  level and health. Damage numbers pop up above the pets in the world, and the result card at the end lists
  everything you won.

### Elements and team synergy in battle

Elements work in battle exactly like the [element wheel](#elements): a pet hitting an element it is strong against
deals **x1.5** damage, a pet hitting an element that is strong against it only **x0.75**. A team also gets bonuses
for its mix of elements (the Team screen shows them live):

- **2 pets of the same element:** **+10 % Power** for those pets; **3 of one element +20 %**, **4 of one element
  +30 %**.
- **3 or more different elements:** **Balanced**, **+10 % Health** for the whole team.

### Trials 1-30: the Trial Portal

Press **E** at the **Trial Portal** on the plaza to open the Trial window: **30 levels** of NPC pet teams, each one a
little stronger, with a **mini-boss** (one big pet) on every 5th level. Pick a level and press **START**: you are
flown to a private battle arena in the sky (so many players can fight at once) and back to the portal after the
fight. Beat level N to unlock level N+1. You have **2 minutes** to win; running out of time counts as a loss.
Level 1 is a gentle start: one sleepy Pebble Pup that any single level-1 pet beats.

| Levels | Chapter | Enemy pets |
|---|---|---|
| 1-5 | Cloud Meadow | Common pets |
| 6-10 | Maple Grove | Uncommon pets |
| 11-15 | Tidewater | Rare pets (teams of four from level 12) |
| 16-20 | Thunderhead | Epic and Legendary pets |
| 21-25 | Twilight Peak | Legendary and Mythic pets |
| 26-30 | Eclipse | Mythic and Secret pets (Stormfang waits at level 30) |

**Rewards for every win:** 10 + 3 x the level Cloud Tokens (**13** at level 1 up to **100** at level 30) and
20 + 6 x the level XP for every pet of your team (**26** up to **200**). A lost Trial still pays a third of that XP
when your pets really fought. **The first clear** of a level pays a big bonus on top: 40 x the level tokens (twice
that on a mini-boss level), and Gems on the mini-boss levels:

| First clear of level | 5 | 10 | 15 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|
| Gems | 5 | 8 | 12 | 16 | 20 | 30 |

### Duels and trophies

Duel other players on the two **duel rings** in front of the colosseum. Both of you must be in the arena.

- **Challenge:** press **E** on a duel ring's pad to open the Arena panel on its **Duels** tab, and press
  **Challenge** next to a player. They get a card at the right edge of their screen with **Accept** /
  **Decline** (30 seconds). The duel starts on a free ring; you stand on its pad and watch your team fight theirs.
- **Quick queue:** press **Find a match** on the Duels tab and the game pairs you with the waiting player whose
  trophies are closest. **Leave** on the queue card at the right edge takes you out of the queue.
- A duel lasts up to **2 minutes**; then the team with more health left wins. After **75 seconds** every hit grows
  stronger (15 % more every second), so a duel never drags on; no single hit takes more than 60 % of a pet's health;
  and when both last pets fall at the same moment, the team that dealt more damage wins.
- **Trophies and rewards:**

  | Result | Trophies | Cloud Tokens | XP for every team pet |
  |---|---|---|---|
  | **Win** | +20 | 40 | 60 |
  | **Draw** | 0 | 15 | 25 |
  | **Loss** | -10 | 10 | 25 |

  Trophies never drop below 0. Leaving the arena or the game during a duel counts as a loss.
  When both players leave together, or the server shuts down, the duel does not count for anyone.
- **Fair play:** the same two players earn rewards from at most **3 duels every 30 minutes**; a win by a forfeit in
  the first **15 seconds**, or against a team that never dealt any damage, pays nothing. When one team is more than
  **3 times** stronger than the other (team power), the duel is a **practice duel**: a side toast says so, and
  nobody wins or loses trophies, tokens or XP. Practice duels are great for trying things out with a friend.
- **The leaderboard:** the trophy board by the main gate and the **Leaders** tab of the Arena panel show the top 10
  players in the server by trophies. Your trophies are saved.

### Boss Raids

About **every 20 minutes** (the first one 5 minutes after a server starts) a giant boss stomps into the colosseum.
Everyone gets a side toast **2 minutes** before, and the event board counts down. When the raid opens, go into the
arena and press **JOIN RAID** on the raid card at the right edge (or on the **Boss Raid** tab of the Arena panel): you
can join during the **first 60 seconds**. Your team runs onto the boss floor and fights together with everyone
else's. The boss has more health the more teams really fight it.

| Boss | Element | Strong pets against it | Its big attacks |
|---|---|---|---|
| **Storm Titan** | Storm | Earth | Thunder Slam (circle), Chain Lightning (line) |
| **Lava Golem** | Flame | Water | Magma Pool (circle that keeps burning), Eruption (a huge circle around the boss) |
| **Frost Wyrm** | Frost | Flame | Frost Breath (line, freezes), Blizzard (circle, freezes) |
| **Shadow Hydra** | Shadow | Celestial | Void Fangs (three lines), Shadow Pulse (circle) |

The four bosses take turns in this order. **Dodging:** before a big attack a glowing **circle or line** appears on
the floor and fills up. Press **RETREAT** before it is full (when it is full its edge flashes red: too late) and
your pets run out of it, then they go back to fighting by themselves. Each boss also calls **minion waves** and gets
**enraged** after **4 minutes** (it hits twice as hard); a raid ends when the boss is down, when every pet is knocked
out, or after **5 min 30 s**.

**Rewards** go to everyone who is still in the raid at the end, by the share of the boss's health they took off:

| Tier | Your share of the damage | Cloud Tokens | XP for every team pet | Gems | Boss Raid pet chance |
|---|---|---|---|---|---|
| **Gold** | 25 % or more | 500 | 400 | 10 (25 % chance) | 5 % |
| **Silver** | 10 % or more | 300 | 250 | 5 (15 % chance) | 3 % |
| **Bronze** | 2 % or more | 150 | 120 | 3 (8 % chance) | 1.5 % |
| **Helper** | any hit on the boss | 60 | 50 | - | 0.5 % |

If the boss wins, everyone whose pets hit it still gets **25 tokens** and **20 XP**. Only a raider whose pets never
hit the boss gets no reward.

**The three Boss Raid pets** are Secret pets that are in no roulette at all: **Magma Cub** (Flame, a little echo of
the Lava Golem), **Rime Wyrmling** (Frost, from the Frost Wyrm) and **Hydralotl** (Shadow, from the Shadow Hydra).
A raid can drop one you do not have yet; they are in the Pet Index like every other pet.

### Double Rewards

Every **3 hours** a **Double Rewards** hour starts (announced 2 minutes before, shown on the event board and on
the countdown chip at the right edge): for **1 hour** every battle pays **x2 Cloud Tokens** (Trials, first clears,
duels and Boss Raids).

### The Champion Ring

The golden **Champion Ring** portal stands on the plaza next to the Trial Portal. All you need is a home and one
pet. Press **E** at it: the ring window shows your record, the best in this server, the pets that will fight and
what the next win pays. Pick where to start (round 1, or any boss round you have beaten) and press **START**.

- **One champion at a time**, each a little stronger than the last. Rounds 1-3 are sleepy little pets that any
  single level-1 pet beats; then the champions get rarer and stronger, and **every 10th round is a giant boss**. You
  have **90 seconds** for a round; lose once (or run out of time) and the run ends. Between two rounds you get 3
  seconds and a side card ("Round 8 won! ... Round 9 in 3"). Your health comes back full every round.
  Tap LEAVE (twice) to stop a run; you come back at the Champion Ring portal.
- **Every win pays Cash and XP:** the bigger of $20 + $2 x the round and what your garden makes in 1.5 + 0.1 x the
  round seconds (at most 9 seconds), and 20 + 6 x the round XP for every pet of your team. A **new record** round
  pays **x3 Cash**, and beating a boss round for the first time pays **100 Cloud Tokens**. The round that ends your
  run pays a third of its XP when your pets really fought.
- **Who fights:** your battle team; without one, the pets following you; without those, your strongest pets. Pets in
  training stay home.
- Your record is saved, and the portal's sign shows the best players in the server ("Best in this server").

| Round | Champion | Cash per win (at least) | XP for every team pet |
|---|---|---|---|
| 1 | a sleepy Pebble Pup | $22 | 26 |
| 2 | a sleepy Pip Penguin | $24 | 32 |
| 3 | a sleepy Honey Bunny | $26 | 38 |
| 5 | a Common pet | $30 | 50 |
| 10 | **Boss:** a giant Common or Uncommon pet | $40 | 80 |
| 20 | **Boss:** a giant Uncommon or Rare pet | $60 | 140 |
| 30 | **Boss:** a giant Epic or Legendary pet | $80 | 200 |
| 40 | **Boss:** a giant Legendary or Mythic pet | $100 | 260 |
| 50 | **Boss:** a giant Mythic or Secret pet | $120 | 320 |

The ring never ends: after round 50 the bosses just keep getting stronger. When a run is over the result card
shows **RUN OVER** (or **NEW RECORD!**), the rounds you won and the Cash and XP of the whole run, and a few seconds
later you are back at the portal.

### Testing battles in Studio (owner)

- **Boss Raids:** press **Play**, then the DEV panel's **Start Boss Raid** button or type `/raid` in the chat (see
  [Developer tools](#developer-tools-owner-only)). Walk over the bridge into the arena and press **JOIN RAID**
  within 60 seconds. One player is enough.
- **Duels need two players:** on Studio's **Test** tab choose **Clients and Servers**, set **2 players** and press
  **Start**. Studio opens a server window and one window per player. In each player window give yourself pets
  (**Give all pets** in the DEV panel or `/allpets`), put pets in your team (**Team** tile) and walk into the arena.
  Then challenge the other player from a duel pad and accept in the other window, or press **Find a match** in
  both. Give
  both players similar teams: a team more than 3 times stronger makes it a practice duel without rewards.
- **Trials and the Champion Ring** work in a normal **Play** test: press **E** at the Trial Portal or the Champion
  Ring portal on the plaza (the ring needs a claimed home and a pet).

## Pets and roulettes

**33 pets** in seven rarities follow right behind their owner, and everybody sees everybody's pets: Common 6,
Uncommon 6, Rare 5, Epic 4, Legendary 3, Mythic 2 and **Secret 7** (Stormfang, Eclipse Dragon, Obsidian Phoenix,
Phantom Kitsune, and the three Boss Raid pets Magma Cub, Rime Wyrmling and Hydralotl). Visit the **shop island** or
press the **Shop** tile, pick a roulette and spin. Duplicates stack (up to 99 per pet).

| Roulette | Price | Odds per spin (pets inside a rarity are equally likely) |
|---|---|---|
| **Cloud** | 50 tokens (or 5 Gems) | Common 60 %, Uncommon 28 %, Rare 10 %, Epic 2 % |
| **Storm** | 250 tokens (or 20 Gems) | Uncommon 35 %, Rare 40 %, Epic 20 %, Legendary 5 % |
| **Sky** | 1,000 tokens (or 75 Gems) | Rare 35 %, Epic 45 %, Legendary 17 %, Mythic 3 % |
| **Celestial** | 5,000 tokens (or 300 Gems) | Epic 45 %, Legendary 40 %, Mythic 15 % |
| **Secret** (Storm Altar) | 1,500 Gems only | Mythic 85 %, Secret 15 % |

Secret pets are in none of the token roulettes: Stormfang and the other three roulette Secrets come from the
gems-only Secret Roulette at the Storm Altar (see [Gems](#gems-and-the-secret-roulette)), and the three Boss Raid
pets only drop in Boss Raids.

Equip up to **3** pets from the Pets window (a pet in training cannot be equipped). Each pet has one or two perks:
**Max Health**, **Cloud Tokens** (more tokens per pickup), **Stamina Regen** and **Checkpoint Heal**. Perks add up,
with caps (+50 % health, +100 % tokens, +60 % stamina regen, +100 % checkpoint heal). Pets never change run speed or
jump height, and your loadout is locked while a climb is running. The mascot is the Mythic **Cloudy Dragon**.

Every pet also has a **role** (Economy pets make 60 % more coins in your [Pet Garden](#the-pet-garden-and-rainbow-coins)
than Combat pets; both can work there and both can fight in [pet battles](#pet-battles-phase-3)), **stats** (Income,
Power, Health, Speed; higher rarities are much stronger, and every level a pet gains adds 10 %) and a named
**special attack** (for example Stormfang's *Storm Pounce* or the Cloudy Dragon's *Cloud Breath*). The Pet Index
shows them all; in battle each pet uses its special when you press SPECIAL. Since phase 2 a pet can also be a
**Golden** or **Rainbow** copy or a fused **hybrid** (see [the Fusion Machine](#the-fusion-machine-after-prestige-1)),
and since phase 4 it can [evolve](#evolution-the-evolve-button) and learn [battle skills](#the-training-place). The
Pets window shows each copy with its tier badge, level (*Lv 12 / 100*), XP bar and evolution stars, and the Equip,
Feed, Garden, Train and EVOLVE buttons.

### Pet cards and following

Your pets follow right behind you: one pet behind your back, two side by side, a third a little further back. A
small card floats above each of your pets: **Lv 12** in big bold numbers, a star for each evolution (★ / ★★) and a
blue XP bar. When a pet is ready to evolve, its card shows a pulsing gold **EVOLVE!** pill: click or tap it to open
the Pets window on that pet. Garden pets at home show the same card, and a training pet shows a purple timer bar
("2:10") instead. Other players' pets show just their level. In a battle the cards also show health (green for
yours, red for enemies) and your pets' gold SPECIAL bar. The cards keep the same size on screen when you zoom out.

## Elements

Every pet has one element (a fused hybrid has both of its parents'). They matter in pet battles: a strong hit deals
**x1.5** damage, a weak one **x0.75**, everything else x1, and teams get bonuses for their mix of elements (see
[Elements and team synergy](#elements-and-team-synergy-in-battle)).

- **The wheel** (each beats the next): **Water > Flame > Frost > Nature > Earth > Storm >** back to Water.
- **The pair** (each beats the other): **Celestial <-> Shadow**.

Water 4 pets, Flame 3, Frost 3, Nature 5, Earth 4, Storm 4 (Stormfang among them), Celestial 4, Shadow 3. The
Pet Index has a small **Elements** card that shows the wheel.

## Pet Index

Open it with the **Index** tile. On the left one tile per rarity group with your progress ("3/6"); in the middle
the group's pets (pets you have not found yet are black `???` silhouettes); on the right a detail card with the
pet's rarity, element (with "Strong vs / Weak vs"), role, stats and special attack, and for Stormfang the
owner's artwork as a banner. Every pet you ever win counts as discovered. The footer shows "Unlocked: x/33" (the
three Boss Raid pets are listed with the Secret pets).

Discover every pet of a group and press **CLAIM** for its reward (once per group; a red `!` on the group tile
means a reward is waiting):

| Group | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| Reward (Cloud Tokens) | 50 | 120 | 300 | 800 | 2,000 | 5,000 | 10,000 |

Under the groups, the **Fusions** tile lists your Golden, Rainbow and hybrid pets (with a hybrid's parents and
elements). Fusions are not part of the group rewards.

## Items

Bought in the shop for cloud tokens, carried up to 5 of each, used on keys `1`-`4` during a climb (they do nothing
in the lobby or during the intro countdown). Slot 4 is a locked placeholder for a future item.

| Slot | Item | Price | What it does |
|---|---|---|---|
| 1 | **Heal Cloud** | 30 | Heals 40 % of your max health. |
| 2 | **Shield Bubble** | 45 | Nothing can hurt you for 8 seconds. |
| 3 | **Phoenix Feather** | 150 | Revives the nearest downed teammate at 50 % health (only used up if someone was revived). |

## The screen

Nothing the game says appears in the middle of the screen. All text follows one readability rule: it is
designed for a 1080p screen (body text 18 px or more, buttons 20 px or more), scales with your screen height and
never drops below 14 px on a phone.

- **Left, vertically centred: the menu** of seven square tiles: Inventory, Pets, Team, Index, Shop, Home, Stats.
  Windows you open are centred on purpose (you asked for them) and close with Esc, the red X or gamepad B.
- **Top-left:** party panel in the lobby (portal, countdown, members, the **Leave** button), match panel
  (difficulty, timer, checkpoints, team) in a climb. The tutorial card sits below it.
- **Bottom-left:** your **Cloud Tokens**, **Cash** and **Gems** (big numbers with K / M), and under them the
  **health and stamina card**: a heart badge with a thick health bar (it flashes and shakes when you are hit and
  pulses when you are low), a lightning badge with the stamina bar, and the dash ring that sweeps while dash
  recharges. NPC dialogs open just above it.
- **Right: toasts** stack at the top-right (purchases, level-ups, "Welcome back! Your pets made ..." and the
  rest), and the compact result card shows up at the right edge after a climb. **Bottom-centre:** the item hotbar
  (1-4).
- On phones the HUD moves up to clear the thumbstick, and on short landscape screens the currency counters move
  to the top-right.
- **In the Battle Arena:** duel invites, the raid card and the event countdown are small cards at the right edge.
  **In a battle:** a slim card at the top centre (the enemies or the boss, the time; in the ring "CHAMPION RING -
  Round 8 - Best 12"), your team's cards and the ATTACK / RETREAT buttons at the bottom right. On a phone the team
  cards sit under the top card (on a landscape phone at the top-left, where the menu tiles step aside while you
  fight) and ATTACK / RETREAT become big buttons at the right edge.

## Developer tools (owner only)

The game's owner gets a small **DEV** tile (bottom-right corner on a PC, just above the thumb buttons on a
phone) and a few chat commands, to try everything quickly while testing. Nobody else sees the tile, and the
server checks the permission again on every single command, so other players cannot use them.

**Who counts as a developer** (`Config.Dev` in `src/shared/Config.lua`):

- the owner of the game (for a group game: the group's owner),
- the extra Roblox UserIds listed in `Config.Dev.Admins`,
- and **everyone while playing in Roblox Studio** (`Config.Dev.AllowInStudio`), so the tools work in any Studio
  test, even in a place that is not published yet.

**The DEV panel.** Click or tap the DEV tile to open the "Developer tools" panel on the right edge:

| Button | What it does |
|---|---|
| **Give all pets** | One copy of every pet you do not own yet (Secret pets too); every pet counts as discovered, so the Pet Index fills up and its rewards can be claimed. |
| **+1M tokens** | Adds `Config.Dev.GrantTokens` Cloud Tokens (1,000,000). |
| **+1M Cash** | Adds `Config.Dev.GrantCash` Cash (1,000,000), to try the home stations quickly. |
| **+1,000 Gems** | Adds `Config.Dev.GrantGems` Gems (1,000), to try the gem roulettes and Fusion Mixes. |
| **Restart tutorial** | Plays the tutorial again from step 1. Its rewards are not paid a second time. |
| **Skip tutorial** | Ends the tutorial (without its finish reward). |
| **Start Boss Raid** | Starts a Boss Raid in the arena right now (`/raid`), so you can test raids without waiting for the schedule (the next boss of the rotation; join it in the arena within 60 seconds). Not while a raid is already running. |
| **Evolve every pet** | Plays every pet's evolution animation one after another in front of you (`/evolve all`). |
| **Show all pets** / **Show evolved pets** / **Show Evolved II pets** | Lines up every pet at that stage in front of you (`/pets`, `/pets 1`, `/pets 2`). |
| **Clear pet show** | Removes the showcase pets and stops an evolution (`/clearpets`). |
| **Reset my data** | Back to a brand-new player: tokens, Cash, Gems, pets (also Golden, Rainbow and fused ones), pet levels, evolutions and training, leftover food, items, stats, your home build (stations, Garden, the coins on your lawn) and Prestige stars, your battle teams and battle record (trophies, Trial clears, raid and duel counters, Boss Raid pets, the Champion Ring record), Pet Index progress and rewards are wiped, and the tutorial starts again as for a new player. Tap once ("Are you sure?"), then tap again to confirm. Not during a climb or a battle. |

Close it with the red X, `Esc` or gamepad B. Every change answers with a "DEV: ..." toast.

**Chat commands** (type them in the game's chat while playing: click the chat bubble at the top left of the game
view or press `/`; not case-sensitive). Not in Studio's command bar at the bottom of the Studio window: that box
runs Lua code and the game never sees what you type there.

| Command | What it does |
|---|---|
| `/allpets` | Same as Give all pets. |
| `/tokens` or `/tokens 50000` | Adds tokens: 1,000,000 by default, or the amount you type (`50000`, `50,000`, `50k` and `1m` all work; at most 100,000,000 at once). |
| `/cash` or `/cash 50000` | Adds Cash the same way: 1,000,000 by default (at most 100,000,000 at once). |
| `/gems` or `/gems 500` | Adds Gems the same way: 1,000 by default. Gems added like this are only for testing: real players get Gems from prestiges and purchases. |
| `/petlevel 20` | Sets every pet you have equipped to that level (1-100; its XP starts at 0), to try EVOLVE, the Food Machine and the high levels quickly. |
| `/reset` | Same as Reset my data (no confirmation, so type it carefully). |
| `/tutorial` | Same as Restart tutorial. |
| `/skiptutorial` | Same as Skip tutorial. |
| `/raid` | Same as Start Boss Raid. |
| `/pet <name> [stage]` | Builds that pet in front of you: stage `0` normal (the default), `1` evolved, `2` second evolution (Epic pets and up). The name or a unique part of it is enough, any case: `/pet cloudy 2`, `/pet Pebble Pup`. Each new pet stands beside the last one. |
| `/pets [stage]` | Every pet lined up in rows in front of you: `/pets` (normal), `/pets 1` (all 33 evolved), `/pets 2` (the 16 second evolutions). |
| `/evolve <name> [stage]` | Plays that pet's evolution animation in front of you: with no stage its whole line (normal -> evolved, then -> second evolution for Epic pets and up), `1` only normal -> evolved, `2` only evolved -> second evolution. |
| `/evolve all [stage]` | Every pet's evolutions one after another (all 49 take about 4½ minutes; `/evolve all 2` plays just the 16 second evolutions). |
| `/clearpets` | Stops an evolution and removes the showcase pets. |
| `/devhelp` | Two toasts listing the commands. |

The pet showcase (`/pet`, `/pets`, `/evolve`, `/clearpets`) is built on your own screen only: other players do not
see it, nothing is saved and your pets are not touched. The evolution animation is
`src/client/Controllers/EvolutionFx.lua` (the pet charges up and spins in a pillar of light over a ring of runes,
bursts into a flash and the evolved pet pops out; the second evolution gets a double ring and more sparks); the
players' EVOLVE button plays the same animation, with confetti.

At most 4 commands every 2 seconds. Every command is written to the Output window as `[NimbusClimb][Dev] ...`.
Changes are saved like normal progress (a reset lasts), so use them on a test account or in Studio when you want
to keep your real progress.

**Settings** (`Config.Dev`):

| Setting | Default | Meaning |
|---|---|---|
| `Enabled` | `true` | Master switch. `false` turns the tools off for everyone, the owner included: use it to see the game exactly as a normal player does. |
| `AllowInStudio` | `true` | Everyone is a developer in Studio. With `false`, only the owner and the Admins get the tools in Studio too. |
| `Admins` | `{}` | Extra UserIds allowed in the live game, e.g. `Admins = { 12345678, 87654321 }`. |
| `StudioAutoGrant` | `false` | `true`: every Studio test starts with every pet and `GrantTokens` tokens. |
| `GrantTokens` | `1000000` | Tokens added by the button, by `/tokens` without a number and by `StudioAutoGrant`. |
| `GrantCash` | `1000000` | Cash added by the button and by `/cash` without a number. |
| `GrantGems` | `1000` | Gems added by the button and by `/gems` without a number. |
| `MaxTokensPerCommand` | `100000000` | The most one `/tokens`, `/cash` or `/gems` command can add. |

## Publishing an update (owner)

Do this every time you publish a new version, phase 4 included:

1. **Rebuild the place file** (see [Rebuilding the place file](#rebuilding-the-place-file)) or let Rojo sync the code
   into Studio, and give it a quick **Play** test.
2. **Publish:** in Studio, File -> **Publish to Roblox**.
3. **Migrate to Latest Update:** open the **Creator Hub** (create.roblox.com) -> **Creations**, open your
   experience's **...** menu (or its **Places** list, then the place's **...** menu) and choose **Migrate to Latest
   Update** (newer Creator Hub pages call it **Restart Servers for Updates**). Roblox then moves the players to new
   servers running the new version a few at a time, so nobody gets kicked out of the game. If you cannot find it,
   **Shut Down All Servers** works too: everyone is sent out and simply rejoins into the new version.

For a few minutes old and new servers run side by side. That is safe for phase 4: an old server keeps the new save
fields (evolutions, training, the ring record, the kept garden places and prices) untouched, a pet trained there
still finishes its rank later, and no level is ever lost (at worst a pet above level 50 loses the half-filled XP
toward its next level if it fights on an old server during those minutes). Players who log in on a new server for
the first time get their home moved over by itself (see [Homes from before Phase 4](#homes-from-before-phase-4)).

## Coming next

- **More arena events:** the event scheduler is ready for new kinds next to Boss Raids and Double Rewards (for
  example a King of the Ring).

## Rebuilding the place file

`play/NimbusClimb.rbxlx` is generated from `src/`; never edit it by hand. After changing code, rebuild it from this
folder with [Rojo](https://rojo.space) 7.7.1, then check it:

```bash
rojo build default.project.json -o play/NimbusClimb.rbxlx
python3 tools/verify_place.py   # every src/**/*.lua in the place, right class, identical Source
```

It contains only the three script containers below (plus the lighting technology); the village is built by the
scripts when the game starts.

| Folder | Becomes |
|---|---|
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |

## Game icon and art

The icon is the Cloudy Dragon on a sky background: `branding/icon-512.png` is the file to upload to Roblox
(`icon-1024.png` and the source `icon.svg` are there too). It is placeholder-quality vector art; see
`branding/README.md` for the upload steps, design notes and how to replace it. The Stormfang artwork the
in-game pet and the Storm Altar are based on is in `branding/stormfang-*.png` / `.webp`.

## Tests

```bash
pip install lupa            # once (also needs Python 3 and Node 18+; npm packages install on first use)
tools/run_checks.sh         # everything, about 25 minutes
tools/run_checks.sh --quick # shorter smoke test (fewer layout seeds), a little faster
tools/run_checks.sh --static   # only the fast checks
```

The script exits non-zero if anything fails and runs three steps:

1. **`tools/syntax.py`**: every `.lua` file must parse as plain Lua 5.1 (no Luau-only syntax).
2. **`tools/check.mjs`**: static analysis (undefined globals, deprecated APIs, raw fonts, bad `Instance.new`,
   missing `require`s, and the public API listed in `tools/contract.json`).
3. **`tools/smoke.py`**: loads the real modules into a Roblox mock (`tools/robloxmock.lua`) and plays the game
   (about 8,500 checks): 5 difficulties x 300 generated courses audited (reach, headroom, cannons, tokens), full
   matches (victory, defeat, timeout, leaving, concurrent slots), portal lock-in, damage and the fall rule,
   hazards, pets, elements, roulettes, items, the Pet Index, the tutorial, NPCs, the Storm Altar, the
   developer tools, saving (also during DataStore outages, two servers at once and the phase 3 -> phase 4 rollout),
   the tycoon homes (claiming, every pad and station, star prices, house tiers, prestige, exploit attempts on every
   remote, the home art and its part budget), the Pet Garden (coins, piles, naps, scooping only by the owner, the
   Welcome-back pile, offline coins), the Food Machine, EVOLVE, the Training Place, the home portal, the Fusion
   Machine, Gems (receipts granted once, the policy check, the gem and Secret roulettes), end-to-end runs of
   several players from the first claim through the garden, prestige, fusion and a rejoin, pet battles (the battle
   simulation, Trials, duels with their anti-farming rules, Boss Raids with up to 16 players, events, teams, the
   arena and its world text, the Champion Ring, the battle HUD and every battle window), the pet cards and the
   follow-behind formation, the evolved pets and the pet showcase, the whole client UI including the readability
   rule and the "nothing in the middle of the screen" rule on desktop and phone sizes, and even this README (its
   station table, garden, Food Machine, training, evolution, ring, gem, battle, NPC, developer-tool and tutorial
   numbers must match the game). Handy flags: `-v`, `--only match_victory,damage_rules`, `--list`, `--seeds N`,
   `--strict`.

`python3 tools/sim_tycoon.py` replays the tycoon economy for many simulated players and checks the pacing targets
(first purchase, purchase gaps, Villa, first EVOLVE, first and later prestiges, offline coins); the smoke test fails
when its numbers and `TycoonCatalog.lua` disagree. `tools/sim_battle.lua` does the same for battles (the Trial
curve, fair duels, elements, Boss Raids with 1 / 3 / 8 players, dodging, training, the Champion Ring ladder; see
`tools/README.md` for how to run it).

The mock is not a physics engine (characters do not walk, moving platforms are not simulated), so test the feel
in Studio too. To look at the art and the UI without Studio, `tools/render_model.py` draws any pet, the village,
a home with its garden, the Storm Altar or the sky dragon to a PNG, and `tools/render_gui.py` draws the real UI at
any screen size (see `tools/README.md`).

## Project layout

```
default.project.json   Rojo project           play/NimbusClimb.rbxlx   ready-made place file
Start-Rojo-*           one-click launchers    branding/                game icon + Stormfang art
tools/                 syntax check, static analysis, smoke test (see "Tests"), tycoon economy sim, battle sim,
                       place verifier, model and GUI renderers
ARCHITECTURE.md, ARCHITECTURE_V2.md, ARCHITECTURE_V3.md   module contracts (the newest wins where they differ)

src/shared   Config (every number)  TycoonCatalog (every tycoon number)  Theme  Util  Remotes  PetCatalog  PetKeys
             ItemCatalog  PetBuilder  Voxel (voxel sculpting kit)  TutorialSteps  NpcDialog  ObbyLevels (obby level unlocks)  UpdateNotes (menu notes + tips)
             BattleCatalog (every battle number)  BattleSim (the battle simulation)  BossBuilder
src/server   Main.server.lua; Services: Lighting, LobbyBuilder, StormAltar, Player, Data, Damage, Token, Hazard,
             Course (layout + builder), Match, Portal, Spot, Pet, Item, Index, Tutorial, Npc, Dev, Tycoon,
             HomeBuilder, PetCare, Fusion, Gem, ArenaBuilder, Battle, Event
src/client   Main.client.lua; State; UI/CloudUI; UI/PetCard (the cards above pets); Controllers: Movement, Hud,
             DamageFx, Notify, Menu, Hotbar, Pet, TokenFx, Index, Tutorial, Npc, SkyDragon, Showcase, Dev,
             DevPetShow (pet showcase), EvolutionFx (evolution animation), Care (Food Machine, Garden, training and
             EVOLVE windows), HomeFx, HomePortalFx (the home portal), Fusion, Battle, Arena
```

The **server is authoritative** (health, tokens, Cash, Gems, pets, items, checkpoints, matches, home purchases,
garden coins and scooping, feeding, training, evolution, fusion, gem receipts, every battle and its rewards, the
Pet Index, the tutorial, developer commands); clients only do input, movement feel, UI and purely visual animation
(pets, tokens, NPCs, the sky dragon, the garden pets eating, the coin piles and the stations popping in, the home
portal, the pet cards, and the battles: the server simulates every fight at 10 Hz and sends small snapshots, each
client builds and animates the battle pets and bosses itself). Behaviour is attached with `CollectionService` tags
(`Config.Tags`). Every tunable number, including roulette prices and odds, gem prices, Index rewards, elements,
difficulties and physics, lives in `src/shared/Config.lua`; the tycoon's prices, foods, coins, feeding and training
costs and fusion costs live in `src/shared/TycoonCatalog.lua`, and every battle number (Trials, bosses, rewards,
trophies, events, training skills, the Champion Ring) in `src/shared/BattleCatalog.lua`.

Have fun climbing, building and battling!
