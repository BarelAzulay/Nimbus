# Evolved forms, Switch Target and Retreat

Date: 2026-11-01. Status: all 14 cards approved by the owner on the pitch page, with notes
(https://claude.ai/artifact/TFVXosvvZdydi8fSmUmRfB). Builds on `2026-11-01-attack-fx-design.md` and `2026-11-01-raid-boss-design.md`.

## Why

The owner's words: "evolution grants a better ability, for example. stormfang's special is now pounce, evolved makes it shadow storm wolfs charge at
the enemy, last evolve makes them even cooler with lightning". And: "the F button in fights will change from 'basic attack' (because its automatical)
to 'switch target'. And an R button only in boss raids for 'retreat'".

## Owner's decisions

| Item | Decision |
|---|---|
| What an evolution gives | **A.** A new name, a new look and a real new effect. Tables below. |
| Looks | **A.** Epic and up get unique forms. Common to Rare share one look per kind, in their own colour, with the pet's flavour where it's cheap. |
| Stormfang | **A.** Start: a plain storm pounce, losing today's lightning wolf. First: three shadow wolves. Last: five lightning wolves. The other signature pets keep today's look as their start. **Owner's note:** Stormfang is melee, so the wolves spawn from behind and charge, so the player can see the ability. |
| Beams | **Owner's note:** today's beams look boring. Beam pets get effects and a cooler look at every stage, start included. |
| Rally | **Owner's note:** makes the pet bigger with an aura for its duration. |
| Haste | **Owner's note:** adds a cool aura for its duration. |
| Normal abilities | By element. **Owner's note:** a circle must fit ranged pets, who hit from a distance so a circle round them misses. For ranged pets it applies on the enemy's area. |
| Rarity moves | **Owner's notes:** Candy Unicorn Epic to Legendary. Magma Cub Secret to Mythic. Hydralotl Secret to Mythic. |
| F button | **A.** Tap = next enemy, and the pet goes after it. Hold = back to automatic. Tapping an enemy still picks it. With one enemy it says so and does nothing. Every battle mode. Special gets the biggest button, Target a smaller one. **Owner's note:** the normal and special buttons show the attack's name, no longer "special". |
| R button | **A.** Boss raids only. The pet runs back to the player and the boss picks someone else. While back: no attacks, no meter, no free healing, helper buttons still work. Press again to return, then a 10 s wait before retreating again. If nobody else is fighting, the boss comes anyway. **Owner's note:** while retreated the button says "Engage". |

## Claude's calls (the owner can overrule them; report them)

- **Every shape, not just circles.** The owner's note names circles, but cones are 14 long while ranged pets stand 12-18 away, so check what really lands for each ranged species. Make every normal ability reach from where the pet really stands. Whatever the rule, the drawn area is the real area.
- **Wolves' path is real.** Stormfang's charge line starts behind the pet, as drawn, and the real hit line matches it. A melee pet standing beside its target still gets a visible charge. Damage still lands at the leap's existing moment.
- **Rally and Haste auras at every stage**, growing with evolution. Rally's bigger pet is a look only: hit radius, range and hitboxes don't change. Both end exactly when the buff ends. Simple on Graphics Low.
- **Rarity moves keep what players own.** Pets keep their ids, so saves are safe. Magma Cub and Hydralotl keep their stats, as we never take power from a pet someone owns. Candy Unicorn's stats rise only if it would otherwise fall below other Legendaries. Report: stats before and after, hatch odds before and after, income, and every place rarity shows (index, signature catalog, tests). Magma Cub and Hydralotl stay event pets. Lower rarity also shrinks their effect size by the rarity table, so check they still look right.
- **Retreat rules from Gemini:** a short dodge as the pet starts running, as the lethal attack would otherwise catch it; the boss re-aims at once. A retreated pet is still caught by the lethal attack if it stands in the area. The 10 s wait stops players taking turns to reset the boss. The boss's attacks must not stall when everyone is back.
- **Long names on buttons** must fit a 844x390 phone, at least 44 px targets, in one or two lines, for the longest name ("Wish Upon the Stars", "Marshmallow Pounce"). The tutorial, key chips and help text change with the buttons.
- **The twist effects are also fair in duels.** No target in `tools/sim_battle.lua` gets loosened. New pins: each form's effect, stage 0 unchanged, stage 2 keeps stage 1, and no existing duration changed. Report before and after tables for every mode, and against a lone boss.
- **Hybrids** use the tables by their special's kind and normal's element, in their own colours, with a generic name per kind.
- **Budgets:** ghost copies, wolves and bolts stay under the attack effects budget, on a phone and with several raiders. Other players' forms use `OthersDensity`.

## Non-goals

- A form for the automatic attack. It only gets the approved bigger hits.
- Normal abilities per pet.
- New textures or meshes, as the wolves reuse the game's storm wolf, recoloured. Anything new would be made in Blender and uploaded by the keyed session.

## Must keep

- Server authoritative: forms read the stored stage, Retreat and target switching are validated on the server; junk or spammed requests change nothing.
- Only real Studio can judge the look, so the final report lists what the owner must check.

## Specials: what each kind gains

Stage 2 keeps stage 1's effect. Values are starting values for the simulation to tune.

| Kind | Today | First evolution | Last evolution |
|---|---|---|---|
| Pounce | Dashes to the target for one heavy strike. | Charge: also hits every enemy on the way, at half power. | Landing burst: also explodes where it lands, 50% power. |
| Blast | Explodes on the target and nearby enemies. | Aftershock: a second blast 0.6 s later, 30% power. | Burning ground: leaves a patch that hurts for 3 s. Step out. |
| Storm | A cloud rains damage on an area for 4 s. | Dragging winds: enemies inside move 30% slower. | Last strike: a huge bolt at the end, 40% power, on all still inside. |
| Beam | A beam hits every enemy in its line. | Mark: enemies hit take 15% more damage for 4 s. | Twin: a second beam 0.5 s later, 50% power. |
| Freeze | Freezes enemies around the target. Same 0.8 s stun. | Chill: 40% slower for 3 s after thawing. | Shatter: the ice bursts on thawing, 60% power nearby. |
| Heal | Restores a big chunk of health. | Lingering: 30% more healing over the next 4 s. | Overflow: extra healing turns into a shield. |
| Shield | A shield soaks damage for 6 s. | Thorns: hits back 20% of the damage it blocks. | Burst: explodes when it breaks or ends, 60% power. |
| Rally | +35% damage for 8 s. | War pace: also +15% speed. | Fired up: also fills 20 of the Special meter. |
| Haste | +35% attack and move speed for 8 s. | Quick hands: normal ability and dash recharge 25% faster during it. | Double strike: attacks have a 20% chance to hit twice during it. |

## Normal abilities (the E button), by element

Pets of one element share them, in the pet's colour. Stage 2 keeps stage 1's effect.

| Element | Today | First evolution | Last evolution |
|---|---|---|---|
| Water | Tide Burst: Cone, pushes back | Riptide: Also slows 20% for 2 s | Maelstrom: The wave comes back at 50% power |
| Flame | Flare: Cone, burns for 3 s | Wildfire: Burn is stronger: 35% instead of 25% | Inferno: Leaves burning ground for 2 s |
| Frost | Frostbite: Cone, slows for 4 s | Deep Frost: Slows more: 50% instead of 40% | Ice Snare: Slowed enemies also take 10% more damage |
| Nature | Thorn Lash: Cone, heals you 30% of the damage | Bramble Lash: Heals 40% of the damage | Worldroot: Also roots enemies for 0.4 s |
| Earth | Quake: Circle, stuns 0.5 s | Fissure: A crack erupts again, 40% power | Rockspire: Rock spikes ring the area, 40% power |
| Storm | Bolt: Long line | Forked Bolt: Jumps to one more enemy, or strikes a lone enemy again, 40% power | Thunder Lance: Jumps twice and adds 5 Special meter |
| Celestial | Radiance: Circle, fills 15 Special meter | Halo: Fills 20 Special meter | Starfall: Also heals your pet 8% of its health |
| Shadow | Void Rend: Cone, enemies deal 15% less for 5 s | Hollow Rend: Enemies deal 20% less | Soul Rend: Also heals you 15% of the damage |

## Every pet's forms (after the rarity moves)

Name and intended look. The look's effect rule comes from its kind above. Common to Rare are shared looks per kind in the pet's colour, with the pet's flavour where it's cheap.

### Common

| Pet | Element | Special today (kind) | First evolution | Last evolution |
|---|---|---|---|---|
| Pebble Pup | Earth | Fetch Dash (Haste) | Boulder Fetch: Runs with a trail of dust and tumbling pebbles | none, evolves once |
| Mallow Kitten | Celestial | Marshmallow Pounce (Pounce) | Marshmallow Stampede: Three puffy ghost kittens charge ahead of it | none, evolves once |
| Puddle Frog | Water | Puddle Splash (Blast) | Puddle Geyser: The splash shoots back up as a geyser | none, evolves once |
| Honey Bunny | Nature | Honey Hug (Heal) | Honey Rain: Golden drops keep falling and healing | none, evolves once |
| Biscuit Bear | Earth | Cosy Guard (Shield) | Crumble Guard: Attackers get hit by flying biscuit crumbs | none, evolves once |
| Pip Penguin | Frost | Snow Wall (Shield) | Snowspike Wall: The wall grows spikes that hit back | none, evolves once |

### Uncommon

| Pet | Element | Special today (kind) | First evolution | Last evolution |
|---|---|---|---|---|
| Maple Fox | Flame | Leaf Pounce (Pounce) | Burning Leaf Rush: Ghost foxes trailing burning leaves charge through | none, evolves once |
| Bamboo Panda | Nature | Bamboo Bash (Blast) | Bamboo Quake: Bamboo shoots burst up, then a second wave | none, evolves once |
| Mochi Slime | Water | Sticky Bounce (Shield) | Sticky Rebound: Attacks bounce back as sticky blobs | none, evolves once |
| Sleepy Owl | Storm | Drowsy Lullaby (Heal) | Dream Lullaby: Floating notes keep healing | none, evolves once |
| Waffle Corgi | Earth | Sunny Bark (Rally) | Golden Howl: A golden sound ring and speed lines | none, evolves once |
| Bubble Axolotl | Water | Bubble Barrier (Shield) | Popping Barrier: Bubbles pop back at attackers | none, evolves once |

### Rare

| Pet | Element | Special today (kind) | First evolution | Last evolution |
|---|---|---|---|---|
| Blossom Bunny | Nature | Petal Breeze (Heal) | Petal Gale: A swirl of petals keeps healing | none, evolves once |
| Shroomie Frog | Nature | Spore Cloud (Rally) | Spore Surge: A rising spore cloud and speed lines | none, evolves once |
| Frostling Penguin | Frost | Snow Burst (Freeze) | Blizzard Burst: Snow keeps swirling around chilled enemies | none, evolves once |
| Storm Tabby | Storm | Static Storm (Storm) | Static Snare: Crackling ground drags at enemies inside | none, evolves once |
| Cherry Panda | Nature | Blossom Rain (Heal) | Cherry Downpour: Heavier blossoms keep falling and healing | none, evolves once |

### Epic

| Pet | Element | Special today (kind) | First evolution | Last evolution |
|---|---|---|---|---|
| Aurora Fox | Frost | Aurora Beam (Beam) | Aurora Mark: A wider ribbon that leaves a glowing mark | Twin Aurora: Two ribbons of light, one after the other |
| Moonlit Owl | Celestial | Moonlight Ward (Shield) | Crescent Ward: A crescent moon shield throws light back | Full Moon Ward: A full moon that bursts when it breaks |
| Nebula Axolotl | Water | Stardust Swirl (Haste) | Nebula Swirl: A bigger cloud of stars around it | Supernova Swirl: Stars flash on each double hit |

### Legendary

| Pet | Element | Special today (kind) | First evolution | Last evolution |
|---|---|---|---|---|
| Ember Phoenix | Flame | Phoenix Flare (Blast) | Phoenix Burst: A second fire-bird shape bursts after the first | Phoenix Rebirth: A fire bird rises out of the burning ground |
| Sunbeam Bear | Earth | Golden Aegis (Shield) | Solar Aegis: The sun disc fires rays back at attackers | Sunburst Aegis: The sun disc explodes when it breaks |
| Twilight Dragon | Shadow | Dusk Storm (Storm) | Nightfall Storm: A bigger moon and dark winds drag at enemies | Dusk's End: The moon drops onto the storm at the end |
| Candy Unicorn | Celestial | Sugar Rush (Haste) | Candy Rush: A rainbow candy trail | Sugar Frenzy: Candy bursts on each double hit |

### Mythic

| Pet | Element | Special today (kind) | First evolution | Last evolution |
|---|---|---|---|---|
| Cloudy Dragon | Storm | Cloud Breath (Beam) | Thunderhead Breath: The cloud dragon's breath crackles and marks | Twin Storm Breath: A second cloud dragon breathes after the first |
| Starlight Unicorn | Celestial | Wishing Star (Heal) | Falling Wishes: The star keeps showering healing stars | Wish Upon the Stars: Extra stars turn into a shining shield |
| Magma Cub | Flame | Lava Slam (Blast) | Magma Rift: The ground cracks and erupts again | Volcano Slam: A lava field stays where it hit |
| Hydralotl | Shadow | Void Fangs (Rally) | Void Chorus: The serpent heads roar and speed lines stream | Hydra's Hunger: The heads feed the Special meter |

### Secret

| Pet | Element | Special today (kind) | First evolution | Last evolution |
|---|---|---|---|---|
| Stormfang | Storm | Storm Pounce (Pounce) | Shadow Pack: Three shadow storm wolves charge at the enemy | Thunder Pack: Five wolves wrapped in lightning, bolts strike where they land |
| Eclipse Dragon | Shadow | Eclipse Nova (Blast) | Black Sun Nova: A second black ring bursts after the first | Total Eclipse: The black sun leaves a dark burning crater |
| Obsidian Phoenix | Flame | Shadowflame Storm (Storm) | Cinder Wings: Black-flame wings drag at enemies inside | Obsidian Rain: The phoenix dives into the storm at the end |
| Phantom Kitsune | Shadow | Foxfire Ward (Shield) | Nine-Tail Ward: Fox-fire orbs fly back at attackers | Phantom Foxfire: All nine orbs explode when it breaks |
| Rime Wyrmling | Frost | Glacier Breath (Freeze) | Ice Prison: Glacier walls stay and chill enemies | Glacier Shatter: The whole glacier shatters outward |
