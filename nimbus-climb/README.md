# Nimbus Climb

> *Climb the storm. Together.*

A cosy, co-op **sky village** game for Roblox. You live in a floating cloud village, step into one of five
glowing **portals** with up to three friends, and get flown to a freshly generated **sky course** that you climb
as a team: dash over gaps, dodge spinning bars, lightning and swinging beams, share checkpoints and pick each
other back up. Along the way you collect **Cloud Tokens**, and back home you spend them on **pets** (from
roulettes) and **usable items**, fill your **Pet Index**, and build your own **tycoon home**: claim a plot at
its gate, build cloud presses that make **Cash**, put your pets to work, cook for them, train them, fuse them
and prestige.

Version 3 turns Nimbus Climb into a multi-concept game: the **tycoon homes** are the main mode, the climb (obby)
stays as a side mode, and **pet battles** come in the next update. This build is **v3 phase 2**: phase 1 brought
the new look, the pet collection and everything the later updates build on (see
[What's new in v3](#whats-new-in-v3-phase-1)), phase 2 adds the tycoon homes, Cash, Gems, prestige and the Fusion
Machine (see [Tycoon homes](#tycoon-homes-phase-2)).

Everything is built in code from plain parts and particles (no toolbox models), and all text uses one small
`Theme` module, so the whole game shares the same chunky, friendly look. The only asset id in the code is the
owner's own Stormfang artwork (`Config.Art.StormfangImage`).

## What's new in phase 2: tycoon homes

- **Claim a home.** The 16 plots on the outer ring are classic Roblox tycoons now: walk up to a free gate and
  press **E**. Your build is saved with your profile and comes back on whichever plot you claim next time.
- **Buy pads.** Glowing pads on your yard build everything, step by step: **Cloud Presses** that make **Cash**,
  the **Collector** that banks it, a **Pet Garden**, a **Kitchen**, a **Gym**, a **Vault**, your **House**
  (Cottage, Villa, Manor, Sky Castle: a new house every 10 Home Levels) and decor.
- **Pets at home.** Economy pets earn Cash in the Garden, Combat pets train in the Gym, and every pet levels up
  when you feed it the food you cook in the Kitchen.
- **Prestige.** At Home Level 40 with the Sky Castle you can start over for a star: x1.25 income forever, Gems,
  and from the first star on the **Fusion Machine** (Golden and Rainbow pets, one-of-a-kind hybrids).
- **Gems.** The premium currency: earned by prestiging and bought with Robux (once the owner has created the gem
  packs), spent on cheap roulette spins and on the gems-only **Secret Roulette** at the Storm Altar, the only way
  to get Secret pets like Stormfang.
- **And around it:** a second tutorial chapter with Nimbus, new NPC tips, a **Home** window, Feed / Place in
  Garden / Train in Gym in the Pets window, a Gems tab in the Shop, a Fusions tab in the Pet Index, Cash and Gems
  on the HUD, and +Cash / +Gems developer tools for testing.

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
- **Saving needs a published place.** Tokens, Cash, Gems, pets (with their levels, Golden / Rainbow copies and
  hybrids), food, items, stats, your home build, Pet Index progress and the tutorial step are saved in a
  DataStore, and DataStores only work in a place published to Roblox (File -> Publish to Roblox). In Studio also
  turn on Game Settings -> Security -> **Enable Studio Access to API Services**. Without these the game still
  runs, it just forgets everything when you stop. Saves happen on leave, every 90 s and at server shutdown (older
  v1, v2 and v3 phase 1 saves are migrated automatically).
- **After publishing an update, restart the live servers.** Once the game is published and people play it, every
  time you publish a new version open the Creator Hub -> your experience -> **Servers** and choose **Shut Down All
  Servers**. Old servers still running the previous version do not know the new save fields and could overwrite
  them (for example replaying the tutorial rewards). Players simply rejoin into the new version.
- **Gem packs need Developer Products.** Until you create them (see
  [Selling Gems](#selling-gems-the-owners-setup)), the Shop's Gems tab says the packs open soon. Everything else
  works without them: players still earn Gems by prestiging.
- Leave *StreamingEnabled* off. Everything else (sky, lighting, gravity, the village) is created by the scripts,
  so an empty baseplate is all you need. To test parties use Test -> Clients and Servers with 2-4 players.
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
| Talk to an NPC pet, use the Storm Altar, claim a home, bank the Collector, feed at the bowl, use the Fusion Machine | `E` | tap the prompt | `X` |
| Buy at a home pad (hold a moment) | hold `E` | hold the prompt | hold `X` |
| Cook a Snack / Meal / Feast at your Kitchen counter | hold `E` / `R` / `F` | hold the prompt | hold `X` / `Y` / `B` |
| Close a window | `Esc` or the red X | red X | `B` |

## First steps: the tutorial

New players meet **Nimbus**, the Cloudy Dragon, in a small card on the left of the screen (never in the middle).
Nine short steps teach the basics: say hello, claim your home plot (follow the arrow to a free gate and press
**E**), find the Cloud Shop, spin your first roulette (Nimbus gives you **50 Cloud Tokens** for it), equip your
new pet, peek into the Pet Index, step into the Easy portal, play your first climb to the end, and collect
**100 Cloud Tokens** at the end. A golden arrow, a sparkle trail and a distance sign point at places in the world;
a pulsing ring points at menu tiles.

A second chapter teaches the tycoon home in five steps: claim your home (already done if you claimed it in the
first chapter), build your first Cloud Press (free), build the Collector (free too) and step on it to bank your
Cash, follow the arrow from pad to pad until you can build the Kitchen, then cook a Snack and feed a pet. Nimbus
pays **1,000 Cash** at the end. Players who finished the phase 1 tutorial start right at this chapter.

Tap Nimbus' portrait to fold the card into a small bubble (and again to open it). The **Skip tutorial** link
ends it (it asks first). Your step is saved, so the tutorial continues where you left off.

## The village

- **The plaza** in the middle, with the five difficulty **portals** on a ring around it.
- **The shop island** (follow the boardwalk): four roulette machines and the item counter.
- **Six NPC pets** stand along the plaza and the paths. Each one has a name tag; walk up and press **E** to
  talk. They cycle through a few tips each (Next / Close):

  | NPC | Talks about |
  |---|---|
  | **Sparky Fox**, Movement Trainer | running, dashing, dash-only gaps, items |
  | **Captain Penguin**, Co-op Captain | parties, reviving teammates, Phoenix Feather, pressure plates |
  | **Granny Owl**, Pet Expert | roulettes and their chances (also with Gems), the Pet Index, cooking in the Kitchen and feeding pets |
  | **Coach Corgi**, Token Coach | earning more tokens (win bonus, golden tokens, harder portals), training Combat pets in the Gym |
  | **Mayor Panda**, Village Mayor | claiming a home, Cloud Presses and the Collector, Home Level and the house tiers, Prestige, the Garden, the Home window |
  | **Professor Axolotl**, Element Scholar | elements, the coming Pet Battles, the Fusion Machine, Gems and the Secret pets of the Storm Altar |

- **The Storm Altar** on its dark storm cloud at the village edge, with Stormfang prowling over the portal
  disc. Press **E** at the altar to open the gems-only **Secret Roulette** (see
  [Gems](#gems-and-the-secret-roulette)).
- **The 16 home plots** on the big outer ring (see [Tycoon homes](#tycoon-homes-phase-2)).
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

## Tycoon homes (phase 2)

The 16 home plots on the village's outer ring are classic Roblox tycoons: claim one at its gate, then build it
up pad by pad until a Sky Castle stands on it, and prestige for a star. What is saved is **your home build**, not a
plot number: it is rebuilt on whichever plot you claim. All the numbers below live in
`src/shared/TycoonCatalog.lua`, balanced with the progression simulation `tools/sim_tycoon.py` (an active player
makes a first purchase within seconds, buys something new every 1-2 minutes early on, gets the Villa after about
half an hour and the first Prestige after about 2.5 hours; the second run takes about 1 h 20 min, the third under
an hour).

### Claiming a home

- Walk up to a free gate (its signpost and name tag say **Free home**) and press **E** (*Claim Home*). One home
  per player, and not during a climb.
- The plot is yours until you leave the server. Then it is released: your build disappears from it (it is safe in
  your save) and the gate offers *Claim Home* to someone else.
- Coming back? If your last plot is free you get a side toast "Welcome back! Press E at your gate (#7)". Any other
  free plot works just as well: your whole build comes back on it.
- The **Home** tile of the menu takes you to your gate (or the nearest free one) while you have no home; once you
  have one it opens the [Home window](#the-home-window). Nimbus' arrow leads to a free gate too.
- The name tag over the mailbox shows your avatar, your name, your **Home Level** and one star per **Prestige**,
  and the podium by the gate shows a slowly turning copy of your best pet (rarest first, Rainbow and Golden copies
  before plain ones). With a home, you respawn there instead of on the plaza.

### Buy pads and Home Level

Everything on the yard is built from a **buy pad**: a glowing pad with a floating sign (icon, name, *Build* or
*Lv 2 -> 3*, and the price in **Cash**). Stand on it and hold **E** for a moment (*Buy*). Only you see and use
your own pads (other players' prompts stay off), and the server checks the owner, the price and the requirements
of every purchase.

- The station pops in with a little voxel animation, and new pads appear as your home grows (Cloud Press 2 after
  Cloud Press 1 reaches level 2, the Garden and the Vault after Cloud Press 2 reaches level 2, the Kitchen after
  the Garden ...), so the yard fills up step by step. The pad stays in front of a built station for its upgrades.
- A locked pad says why: *Reach Home Level 10*, *Needs the Villa*, *Unlocks at Prestige 1* (with a blue
  hologram of what is coming) or *Coming soon*.
- **Home Level** = every purchase and every upgrade you made: each one adds 1.
- Your first Cloud Press and the Collector are free, so a brand-new home makes Cash within seconds.

### Cash: Cloud Presses and the Collector

Cloud Presses puff glowing cloud blocks onto the conveyor and into the **Collector**; its screen shows the Cash
waiting inside and how much it can hold. **Step on the Collector** (or press **E** at it, or *Collect* in the Home
window) to bank it. A full Collector stops filling, so bank it now and then: Collector levels add +10 % to +40 %
to the presses' income and hold more, and the Vault makes it bigger still. The server adds your income every
second while you are in the game with your home claimed, also while you are on a climb. **Cash** is the tycoon
currency; Cloud Tokens stay the climb currency.

### Every station

| Station | What it does | Levels | Needs | Price (level 1 -> top) |
|---|---|---|---|---|
| **Cloud Press 1** | The first money machine: 5 -> 53 Cash/s | 10 | claiming | free -> 160,000 |
| **Cloud Press 2** | A bigger press: 13 -> 138 Cash/s | 10 | Cloud Press 1 Lv 2 | 700 -> 400,000 |
| **Cloud Press 3** | A storm press: 34 -> 360 Cash/s | 10 | Cloud Press 2 Lv 3 + the Villa | 18,000 -> 1,040,000 |
| **Cloud Press 4** | The great sky press: 88 -> 930 Cash/s | 10 | Cloud Press 3 Lv 3 + the Manor | 95,000 -> 1,900,000 |
| **Collector** | Banks the Cash; +0 % -> +40 % press income; holds 2,000 + 5 min of income -> 150,000 + 10 min | 5 | Cloud Press 1 | free -> 800,000 |
| **House** | Cottage -> Villa -> Manor -> Sky Castle (see below) | 4 | the Collector | 300 -> 520,000 |
| **Pet Garden** | 1 -> 8 places for Economy pets that earn Cash | 8 | Cloud Press 2 Lv 2 | 1,500 -> 1,440,000 |
| **Vault** | A bigger Collector and offline earnings | 5 | Cloud Press 2 Lv 2 | 9,000 -> 1,200,000 |
| **Kitchen** | Cooks pet food; a queue of 3 -> 10 dishes, up to 2x faster | 5 | the Pet Garden | 3,500 -> 1,100,000 |
| **Gym** | 1 -> 5 places where Combat pets train: 20 -> 80 XP a minute each | 5 | the Kitchen | 14,000 -> 1,300,000 |
| **Fusion Machine** | Golden / Rainbow upgrades and hybrids; -10 % / -20 % token costs at Lv 2 / 3 | 3 | the Kitchen + **Prestige 1** | 25,000 -> 800,000 |
| **Arena Gate** | Opens the way to Pet Battles (the sign says *Coming soon* until phase 3) | 1 | the Gym | 150,000 |
| **Lanterns** | Decor along the path (wood, brass, crystal) | 3 | the Collector | 3,000 -> 210,000 |
| **Garden Fence** | Decor around the yard (picket, hedge, cloudstone) | 3 | Cloud Press 2 Lv 2 | 7,000 -> 290,000 |
| **Flower Beds** | Decor along the front fence (tulips, roses, starflowers) | 3 | the Pet Garden | 4,500 -> 240,000 |
| **Fountain** | Decor in the middle of the yard (basin, tiered, sky) | 3 | the Kitchen + the Villa | 45,000 -> 880,000 |
| **Banners** | Decor along the front fence (cloth, gold, royal) | 3 | the Vault | 12,000 -> 380,000 |
| **Pet Podium** | Dresses up the podium of your best pet by the gate | 3 | the Pet Garden | 9,000 -> 340,000 |

A pad shows up as soon as the stations it needs are built; until the rest is there too (a house tier, a Prestige
star) its sign says what is missing. Every station grows visibly with its level (a level-1 press is small, a
level-10 press big and shiny with gold). Decor is cheap, counts toward your Home Level like everything else and is
**kept when you prestige**.

### The house: a new tier every 10 Home Levels

The House pad builds a **Cottage** (300 Cash). The next houses are deliberately hard to get: the **Villa** needs
Home Level 10 (24,000 Cash), the **Manor** Home Level 20 (115,000) and the **Sky Castle** Home Level 30 (520,000);
until then the House pad says *Reach Home Level N*. Every new house raises how far the other stations can level:

| Max level with the ... | Cottage | Villa | Manor | Sky Castle |
|---|---|---|---|---|
| Cloud Press 1 and 2 | 6 | 8 | 9 | 10 |
| Cloud Press 3 | - | 6 | 8 | 10 |
| Cloud Press 4 | - | - | 8 | 10 |
| Collector | 2 | 3 | 4 | 5 |
| Pet Garden | 2 | 4 | 6 | 8 |
| Kitchen, Gym, Vault | 1 | 2 | 4 | 5 |
| Fusion Machine | 1 | 2 | 3 | 3 |
| Decor | 1 | 2 | 3 | 3 |
| Fountain | - | 1 | 2 | 3 |

### The Pet Garden

Open **Pets**, pick an **Economy** pet and press **Place in Garden**: it moves into the next free place of your
Garden (one copy per place; places unlock with the Garden level: 1 to 8) and you can see it there. Each placed
pet adds Cash per second to the Collector: its Income stat x its rarity (Common x1 up to Secret x13) x its level
(+10 % per level) x its tier (Golden x1.5, Rainbow x2.5) x your prestige multiplier. A pet in the Garden cannot
train in the Gym at the same time.

### The Kitchen and feeding

The Kitchen cooks pet food with Cash. Stand at the counter and hold **E** (*Cook Snack*), **R** (*Cook Meal*) or
**F** (*Cook Feast*), or use the Cook buttons of the Feed picker in the Pets window. Dishes wait in a queue
(3 dishes at Kitchen level 1, up to 10) and cook one at a time, even while you are away on a climb; finished food
goes to your inventory. Better Kitchens cook faster (x1.25 at level 2 up to x2 at level 5). If you leave before a
dish is done, you get its Cash back (unless you prestiged since you ordered it).

| Food | Cost | XP | Base cook time | Needs Kitchen level |
|---|---|---|---|---|
| **Snack** | 50 Cash | 25 | 6 s | 1 |
| **Meal** | 600 Cash | 150 | 20 s | 2 |
| **Feast** | 6,000 Cash | 800 | 45 s | 4 |

**Feeding:** open **Pets**, pick a pet, press **Feed** and choose a food; or press **E** at the feeding bowl next
to the Kitchen, and every pet flying with you eats one food (the best one that does not waste XP). XP makes pets
level up (level 1 -> 2 takes 20 XP, each later level takes more), and **every level adds 10 %** to the pet's stats:
Income for Economy pets, Power / Health / Speed for Combat pets. Each pet copy has its own level, up to a cap by
rarity: Common 20, Uncommon 25, Rare 30, Epic 35, Legendary 40, Mythic 45, Secret 50. A toast shows the new
stats at every level-up.

### The Gym

Open **Pets**, pick a **Combat** pet and press **Train in Gym**. Every pet in the Gym gains XP by itself: 20 XP a
minute at Gym level 1, up to 80 at level 5, with 1 to 5 places, while you are in the game with your home claimed
(up to the pet's level cap). Get them strong for the coming Pet Battles.

### The Vault and offline earnings

The Vault makes the Collector hold more (from +5,000 and 5 more minutes of income at level 1 to +400,000 and 30
more minutes at level 5) and pays you **while you are away**: when you join again, a side toast "While you were
away: +..." pays a share of your income for the time you were gone. Nothing is paid for absences under 2 minutes,
and nothing without a Vault.

| Vault level | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Share of your income | 10 % | 15 % | 20 % | 25 % | 30 % |
| For up to | 1 h | 2 h | 3 h | 4 h | 4 h |

### Prestige

Prestige needs **Home Level 40 and the Sky Castle**. Once the Sky Castle stands, a star pad appears on your yard
(it says *Reach Home Level 40* until you get there). Hold **E** on it (or press Prestige in the Home window): the
Home window shows what starts over, what you keep and what you get, and nothing happens until you confirm there.

- **Starts over:** your Cash, every station except the decor, and the Collector's contents.
- **You keep:** all your pets (with their levels, Golden / Rainbow copies and hybrids), your food, your decor
  (it still counts toward your Home Level, so the next run starts ahead), your Garden and Gym picks (they work
  again as soon as those stations are rebuilt), Cloud Tokens and Gems.
- **You get:** a **Prestige star** on your name tag, **x1.25 income** per star forever (it multiplies: x1.56 at 2
  stars, x1.95 at 3 ...), **Gems** (100 for the first prestige, 10 fewer for each later one, never under 25), and
  at Prestige 1 the **Fusion Machine** pad (and the 4th battle-team slot for the coming Pet Battles).

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

Copies that are equipped, in the Garden or in the Gym are taken off first and the result takes over their place
(the machine refuses only when the inputs are your only equipped pets). The machine's level 2 and 3 take 10 % and
20 % off the token costs:

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

The **Home** tile of the menu opens it (once you have a home): your house tier, Home Level and Prestige stars,
your income per second (presses + Garden pets, with the prestige multiplier), the Collector's Cash with a
**Collect** button, the prestige progress (Home Level x/40 and the Sky Castle) with the **Prestige** button,
**Go home** (a teleport to your yard, not during a climb), and every station with its level, what the next level
does, its price and a **Build** / **Upgrade** button, or why it is still locked. So you can upgrade from
anywhere, without walking to the pad.

### Gems and the Secret Roulette

**Gems** are the premium currency (shown on the HUD next to your tokens and Cash). You get them from every
**Prestige** and by buying **Gem packs** with Robux in the Shop's **Gems** tab (once the owner has created them,
see below). You spend them on:

- **Roulette spins**, a cheaper premium way to roll, with the same odds as with tokens: Cloud 5, Storm 20,
  Sky 75 and Celestial 300 Gems a spin.
- **The Secret Roulette** at the **Storm Altar** (press **E** at the altar, or find it in the Shop's Gems tab):
  1,500 Gems a spin, **Mythic 85 %, Secret 15 %**. It is the only place Secret pets come from (Stormfang, Eclipse
  Dragon, Obsidian Phoenix, Phantom Kitsune).
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

5. Rebuild the place file (or let Rojo sync it into Studio), publish, and **Shut Down All Servers** so every
   server runs the new ids.

Good to know: use each product id for one pack only, and keep the products you sold alive on the Creator Hub.
Every purchase is granted **exactly once**: the purchase id is saved with the Gems in the player's save before
Roblox is told it went through, so a retried or repeated receipt (even after the player rejoined another server)
never pays twice, and a purchase whose save failed stays pending until Roblox asks again. Saving must work for
that (a published place, see [Place settings](#how-to-open-the-game)). In Studio, test purchases cost nothing and
grant the Gems right away. The gem prices of the roulettes (`Config.Gems.RouletteGemPrices`) and the Secret
Roulette's price and odds (`Config.Gems.SecretRoulette`) are in the same table. The game sets
`MarketplaceService.ProcessReceipt` in one place only (`GemService`): Roblox allows one per game, so do not add
another one.

## Pets and roulettes

**30 pets** in seven rarities fly beside their owner, and everybody sees everybody's pets: Common 6, Uncommon 6,
Rare 5, Epic 4, Legendary 3, Mythic 2 and **Secret 4** (Stormfang, Eclipse Dragon, Obsidian Phoenix, Phantom
Kitsune). Visit the **shop island** or press the **Shop** tile, pick a roulette and spin. Duplicates stack (up to
99 per pet).

| Roulette | Price | Odds per spin (pets inside a rarity are equally likely) |
|---|---|---|
| **Cloud** | 50 tokens (or 5 Gems) | Common 60 %, Uncommon 28 %, Rare 10 %, Epic 2 % |
| **Storm** | 250 tokens (or 20 Gems) | Uncommon 35 %, Rare 40 %, Epic 20 %, Legendary 5 % |
| **Sky** | 1,000 tokens (or 75 Gems) | Rare 35 %, Epic 45 %, Legendary 17 %, Mythic 3 % |
| **Celestial** | 5,000 tokens (or 300 Gems) | Epic 45 %, Legendary 40 %, Mythic 15 % |
| **Secret** (Storm Altar) | 1,500 Gems only | Mythic 85 %, Secret 15 % |

Secret pets are in none of the token roulettes: they only come from the gems-only Secret Roulette at the Storm
Altar (see [Gems](#gems-and-the-secret-roulette)).

Equip up to **3** pets from the Pets window. Each pet has one or two perks: **Max Health**, **Cloud Tokens**
(more tokens per pickup), **Stamina Regen** and **Checkpoint Heal**. Perks add up, with caps (+50 % health, +100 %
tokens, +60 % stamina regen, +100 % checkpoint heal). Pets never change run speed or jump height, and your
loadout is locked while a climb is running. The mascot is the Mythic **Cloudy Dragon**.

Every pet also has a **role** (Economy pets earn Cash in your home's Garden, Combat pets train in your Gym and
will fight in Pet Battles), **stats** (Income, Power, Health, Speed; higher rarities are much stronger, and every
level a pet gains adds 10 %) and a named **special attack** (for example Stormfang's *Storm Pounce* or the Cloudy
Dragon's *Cloud Breath*). The Pet Index shows them all; specials come into play with Pet Battles in the next
update. Since phase 2 a pet can also be a **Golden** or **Rainbow** copy or a fused **hybrid** (see
[the Fusion Machine](#the-fusion-machine-after-prestige-1)); the Pets window shows each copy with its tier badge,
level and XP bar, and the Feed, Place in Garden and Train in Gym buttons.

## Elements

Every pet has one element (a fused hybrid has both of its parents'). They matter in the coming Pet Battles: a
strong hit deals **x1.5** damage, a weak one **x0.75**, everything else x1.

- **The wheel** (each beats the next): **Water > Flame > Frost > Nature > Earth > Storm >** back to Water.
- **The pair** (each beats the other): **Celestial <-> Shadow**.

Water 4 pets, Flame 3, Frost 3, Nature 5, Earth 4, Storm 4 (Stormfang among them), Celestial 4, Shadow 3. The
Pet Index has a small **Elements** card that shows the wheel.

## Pet Index

Open it with the **Index** tile. On the left one tile per rarity group with your progress ("3/6"); in the middle
the group's pets (pets you have not found yet are black `???` silhouettes); on the right a detail card with the
pet's rarity, element (with "Strong vs / Weak vs"), role, stats and special attack, and for Stormfang the
owner's artwork as a banner. Every pet you ever win counts as discovered. The footer shows "Unlocked: x/30".

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

- **Left, vertically centred: the menu** of six square tiles: Inventory, Pets, Index, Shop, Home, Stats.
  Windows you open are centred on purpose (you asked for them) and close with Esc, the red X or gamepad B.
- **Top-left:** party panel in the lobby (portal, countdown, members, the **Leave** button), match panel
  (difficulty, timer, checkpoints, team) in a climb. The tutorial card sits below it.
- **Bottom-left:** your **Cloud Tokens**, **Cash** and **Gems** (big numbers with K / M), and under them the
  **health and stamina card**: a heart badge with a thick health bar (it flashes and shakes when you are hit and
  pulses when you are low), a lightning badge with the stamina bar, and the dash ring that sweeps while dash
  recharges. NPC dialogs open just above it.
- **Right: toasts** stack at the top-right (purchases, level-ups, "While you were away" and the rest), and the
  compact result card shows up at the right edge after a climb. **Bottom-centre:** the item hotbar (1-4).
- On phones the HUD moves up to clear the thumbstick, and on short landscape screens the currency counters move
  to the top-right.

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
| **Evolve every pet** | Plays every pet's evolution animation one after another in front of you (`/evolve all`). |
| **Show all pets** / **Show evolved pets** / **Show Evolved II pets** | Lines up every pet at that stage in front of you (`/pets`, `/pets 1`, `/pets 2`). |
| **Clear pet show** | Removes the showcase pets and stops an evolution (`/clearpets`). |
| **Reset my data** | Back to a brand-new player: tokens, Cash, Gems, pets (also Golden, Rainbow and fused ones), pet levels, food and the Kitchen queue, items, stats, your home build (stations, Garden, Gym, Collector) and Prestige stars, Pet Index progress and rewards are wiped, and the tutorial starts again as for a new player. Tap once ("Are you sure?"), then tap again to confirm. Not during a climb. |

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
| `/reset` | Same as Reset my data (no confirmation, so type it carefully). |
| `/tutorial` | Same as Restart tutorial. |
| `/skiptutorial` | Same as Skip tutorial. |
| `/pet <name> [stage]` | Builds that pet in front of you: stage `0` normal (the default), `1` evolved, `2` second evolution (Epic pets and up). The name or a unique part of it is enough, any case: `/pet cloudy 2`, `/pet Pebble Pup`. Each new pet stands beside the last one. |
| `/pets [stage]` | Every pet lined up in rows in front of you: `/pets` (normal), `/pets 1` (all 30 evolved), `/pets 2` (the 13 second evolutions). |
| `/evolve <name> [stage]` | Plays that pet's evolution animation in front of you: with no stage its whole line (normal -> evolved, then -> second evolution for Epic pets and up), `1` only normal -> evolved, `2` only evolved -> second evolution. |
| `/evolve all [stage]` | Every pet's evolutions one after another (all 43 take about 4 minutes; `/evolve all 2` plays just the 13 second evolutions). |
| `/clearpets` | Stops an evolution and removes the showcase pets. |
| `/devhelp` | Two toasts listing the commands. |

The pet showcase (`/pet`, `/pets`, `/evolve`, `/clearpets`) is built on your own screen only: other players do not
see it, nothing is saved and your pets are not touched. The evolution animation is
`src/client/Controllers/EvolutionFx.lua` (the pet charges up and spins in a pillar of light over a ring of runes,
bursts into a flash and the evolved pet pops out; the second evolution gets a double ring and more sparks), ready for
a real "evolve" button later.

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

## Coming next

- **Phase 3, pet battles:** a Battle Arena with boss raids, PvP duels, a Trial Portal with 30 levels of NPC
  teams, and on-screen Attack / Retreat / Special controls. Elements and special attacks come into play here,
  your home's **Arena Gate** opens the way, and Prestige 1 unlocks a 4th battle-team slot.

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
tools/run_checks.sh         # everything, about 10 minutes
tools/run_checks.sh --quick # shorter smoke test (fewer layout seeds), about 7 minutes
tools/run_checks.sh --static   # only the fast checks
```

The script exits non-zero if anything fails and runs three steps:

1. **`tools/syntax.py`**: every `.lua` file must parse as plain Lua 5.1 (no Luau-only syntax).
2. **`tools/check.mjs`**: static analysis (undefined globals, deprecated APIs, raw fonts, bad `Instance.new`,
   missing `require`s, and the public API listed in `tools/contract.json`).
3. **`tools/smoke.py`**: loads the real modules into a Roblox mock (`tools/robloxmock.lua`) and plays the game
   (about 5,500 checks): 5 difficulties x 300 generated courses audited (reach, headroom, cannons, tokens), full
   matches (victory, defeat, timeout, leaving, concurrent slots), portal lock-in, damage and the fall rule,
   hazards, pets, elements, roulettes, items, the Pet Index, the tutorial, NPCs, the Storm Altar, the
   developer tools, saving (also during DataStore outages), the tycoon homes (claiming, every pad and station,
   income, the Collector, offline earnings, house tiers, prestige, exploit attempts on every remote, the home art
   and its part budget), the Kitchen, feeding and the Gym, the Fusion Machine, Gems (receipts granted once, the
   policy check, the gem and Secret roulettes), an end-to-end run of three players from the first claim through
   prestige, fusion and a rejoin, the whole client UI including the readability rule and the "nothing in the
   middle of the screen" rule on desktop and phone sizes, and even this README (its tycoon, gem, developer-tool
   and tutorial numbers must match the game). Handy flags: `-v`, `--only match_victory,damage_rules`, `--list`,
   `--seeds N`, `--strict`.

`python3 tools/sim_tycoon.py` replays the tycoon economy for many simulated players and checks the pacing targets
(first purchase, purchase gaps, Villa, first and later prestiges, offline earnings); the smoke test fails when its
numbers and `TycoonCatalog.lua` disagree.

The mock is not a physics engine (characters do not walk, moving platforms are not simulated), so test the feel
in Studio too. To look at the art and the UI without Studio, `tools/render_model.py` draws any pet, the village,
the Storm Altar or the sky dragon to a PNG, and `tools/render_gui.py` draws the real UI at any screen size (see
`tools/README.md`).

## Project layout

```
default.project.json   Rojo project           play/NimbusClimb.rbxlx   ready-made place file
Start-Rojo-*           one-click launchers    branding/                game icon + Stormfang art
tools/                 syntax check, static analysis, smoke test (see "Tests"), tycoon economy sim, place verifier,
                       model and GUI renderers
ARCHITECTURE.md, ARCHITECTURE_V2.md, ARCHITECTURE_V3.md   module contracts (the newest wins where they differ)

src/shared   Config (every number)  TycoonCatalog (every tycoon number)  Theme  Util  Remotes  PetCatalog  PetKeys
             ItemCatalog  PetBuilder  Voxel (voxel sculpting kit)  TutorialSteps  NpcDialog
             BattleCatalog (every battle number)  BattleSim (the battle simulation)  BossBuilder
src/server   Main.server.lua; Services: Lighting, LobbyBuilder, StormAltar, Player, Data, Damage, Token, Hazard,
             Course (layout + builder), Match, Portal, Spot, Pet, Item, Index, Tutorial, Npc, Dev, Tycoon,
             HomeBuilder, PetCare, Fusion, Gem, ArenaBuilder, Battle, Event
src/client   Main.client.lua; State; UI/CloudUI; Controllers: Movement, Hud, DamageFx, Notify, Menu, Hotbar,
             Pet, TokenFx, Index, Tutorial, Npc, SkyDragon, Showcase, Dev, DevPetShow (pet showcase),
             EvolutionFx (evolution animation), HomeFx, Fusion, Battle, Arena
```

The **server is authoritative** (health, tokens, Cash, Gems, pets, items, checkpoints, matches, home purchases
and income, cooking, feeding, fusion, gem receipts, the Pet Index, the tutorial, developer commands); clients only
do input, movement feel, UI and purely visual animation (pets, tokens, NPCs, the sky dragon, the presses, the
conveyor and the stations popping in). Behaviour is attached with `CollectionService` tags (`Config.Tags`). Every
tunable number, including roulette prices and odds, gem prices, Index rewards, elements, difficulties and physics,
lives in `src/shared/Config.lua`; the tycoon's prices, incomes, foods and fusion costs live in
`src/shared/TycoonCatalog.lua`.

Have fun climbing, and building!
