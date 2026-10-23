# Pet attack animations and VFX: design

Date: 2026-10-23. Status: design approved in chat section by section; this spec awaits the player's review.

## Goal

Every pet attack in every battle mode (Duel, Raid, Ring, Dungeon) gets a polished animation and element VFX at the
quality of the player's reference (Hovl Studio "Fire arrow effect": textured flipbook fire, crescent slash arcs,
sparks with bloom, a shaped projectile, ground glow, a clear charge -> release -> travel -> impact -> linger rhythm).

Player requirements, in their words: special attacks "should have a cool visible animation and effects", normal
attacks "should also look more aesthetic and worked on", "fire attack fire and for storm a storm and so on depends on
the element and the pet", and "higher rarity with a better attack have a better animation (cooler) with bigger
effect seen visually". Plus: "an improved animation for all pets".

## Decisions (player-approved)

| Question | Choice |
|---|---|
| Style | **A. Stylized at reference quality**: the reference's layering, timing and textures, with cleaner cartoon shapes and bright colours that match the voxel pets and stay readable for kids in 4-player raids |
| Uniqueness | **A. Shared base + top-tier signatures**: every special kind has one great animation that changes per element; rarity adds layers; the 12 Legendary / Mythic / Secret pets each get a signature version of their special |
| Build approach | **1. New `AttackFx` module + data recipes**, plugged into the existing battle client; today's voxel-cube effects stay as the Low-graphics fallback |
| Textures | Rendered in **Blender** (the project's Blender-only art rule) as flipbook sprite sheets, uploaded through Studio as **Image** ids |

## Scope

In: the visuals of pet basic attacks (melee and ranged), the 9 special kinds, the 8 element attacks, hit reactions,
KO, victory and in-battle idle, for player pets and wild / champion pets (they share the path). Signature specials
for the 12 top pets.

Out: any change to battle rules, damage, timing, balance or the server (`BattleSim`, `BattleService`); boss attack
visuals (bosses keep theirs); sounds (possible follow-up); follower-pet animation outside battles.

## Architecture

All battle visuals run through one path today: `BattleController` `Handlers` played on the delayed render clock
(`Net.PlayDue`), drawing pooled Neon cubes (`Fx.*`). The new pieces plug into that path; the server is untouched.

### New units

- **`src/shared/AttackFxCatalog.lua`**: pure data, no Instances. For each element, its palette (core / mid / edge
  colours), its textures (keys into `TextureIds`), the melee swipe, the ranged projectile, and the impact recipe.
  For each special kind, its timeline (beats and layers). For each rarity tier, its knobs (see "Rarity ladder").
  `Signatures[petId]` holds overrides for the 12 top pets. It also has a `Recipe(attack)` resolver that returns one
  flat recipe from (element, kind or "Basic", melee / ranged, rarity, stage, signature).
- **`src/client/Controllers/AttackFx.lua`**: plays a resolved recipe at world points. It owns pooled kits
  (Attachments + ParticleEmitters with flipbook textures, Beams for arcs / lightning / beams, Trails, PointLights),
  the budget, the quality switch, and the fallback. API: `AttackFx.Basic(ctx)`, `Special(ctx)`, `Element(ctx)`,
  `Hurt(ctx)`, `Ko(ctx)`, `Victory(ctx)`, `Stats()`, `SetQuality(q)`. `ctx` = attacker / target units (models,
  positions), element, rarity, stage, pet id, flags (crit, strong, miss), and `mine` (my own team).
- **Pet poses**: an extension of the existing weld-free rig (`PetBuilder.Animate`, groups `WingL/R`, `Wing2L/R`,
  `Tail`, `Halo`, `Aura`, `EyeLid`, plus a whole-body offset). New pose curves: `Windup`, `Strike`, `Recoil`,
  `Cast`, `Hurt`, `Ko`, `Victory`, `IdleBattle`. They live in a small `src/shared/PetPoses.lua` (pure curves) so the
  same poses serve battle units and could later serve followers.
- **`src/shared/TextureIds.lua`**: today `{}`; becomes the texture key -> `rbxassetid` map. **Image ids only, never
  Decal ids** (an ImageLabel / emitter cannot load a Decal id: the Storm Altar bug of 2026-10-23).
- **`blender/vfx/`**: the Blender scripts that render every sprite sheet, plus a manifest (key, frames, layout,
  size). Uploads go through Roblox Studio (`upload_image`, Studio's own sign-in); the returned ids are written to
  `TextureIds.lua`.

### Changes to existing code

- `BattleController`: each attack handler (`EV.Hit`, `EV.Special`, `EV.Element`, KO, victory, swap, buff) calls
  `AttackFx` first and keeps its current `Fx.*` call as the fallback (Low quality, budget overflow, missing texture,
  or `AttackFx` error caught by pcall). The damage numbers, flashes, callouts and the lunge bookkeeping stay as they
  are; the old lunge offset is replaced by the `Strike` pose when `AttackFx` is active.
- `GraphicsQuality.Effective()` ("Low" / "High") drives `AttackFx.SetQuality`.

## The 5 beats of every attack

1. **Charge**: wind-up pose + a gathering glow at the mouth / paws in the element's colour.
2. **Release**: a flash, the element's crescent slash arc (melee) or muzzle burst (ranged).
3. **Travel**: the projectile with its trail (ranged), or the swipe's arc sweeping through the target (melee).
4. **Impact**: element burst, shockwave ring, sparks, ground glow, a 0.05 s hit-stop on the victim's pose.
5. **Linger**: embers / mist / leaves / dust / sparkles fading for 0.4-1.0 s.

### Timing without server changes

Events play `INTERP_DELAY` (0.12 s; spectators 0.25 s) after they arrive, so the client sees each Hit slightly
early. On top of that, a unit's attack tempo is known (`Interval`), so the charge beat starts from the predicted
next attack and is simply relaxed if no Hit comes. Specials charge visibly as the unit's meter nears full (the
meter is in the snapshots). If a Hit arrives with no charge shown, the charge beat is shortened to fit; impact is
never delayed past the event time, so damage numbers stay in sync.

## Rarity ladder

Each tier keeps everything below it and adds a visible layer. Size is a multiplier on the whole effect.

| Tier | Adds | Size |
|---|---|---|
| Common | core projectile / swipe + impact burst | 1.0x |
| Uncommon | + element trail | 1.1x |
| Rare | + crescent slash arc + ground glow | 1.2x |
| Epic | + shockwave ring + light flash | 1.35x |
| Legendary | + afterimages + bloom pulse + small camera punch (own pet only) | 1.5x |
| Mythic | + double arcs + a lingering element field | 1.65x |
| Secret | + a colour-shifting signature layer + a screen-edge glow on hit (own pet only) | 1.8x |

Evolution adds size on top: Evolved +10%, Evolved II +20%. Wild / champion pets use their own rarity.

## Elements: normal attacks

| Element | Melee swipe | Ranged projectile + trail | Impact | Textures (sprite sheets) |
|---|---|---|---|---|
| Flame | crescent of fire | flame spear, ember trail | fire burst + embers + scorch glow | flame, embers, smoke |
| Water | water-whip arc | spinning water orb, droplet trail | splash crown + ripple ring | splash, droplets, ripple |
| Frost | ice-shard slash | ice lance, snow trail | crystal shatter + frost ring on the ground | ice shards, snowflakes, frost mist |
| Nature | vine whip with leaves | spinning leaf-blade swarm | leaf + petal burst + vines sprouting | leaves, petals, vine streak |
| Earth | ground slam, rock spikes | boulder, dust trail | rock debris + dust cloud + ground crack | rock chunks, dust, crack |
| Storm | electric claw, crackling arcs | jagged lightning bolt | electric burst + zig-zag sparks | lightning strip, sparks, storm cloud |
| Celestial | golden starlight slash | shooting star, sparkle tail | star burst + light rays | stars, light rays, sparkle |
| Shadow | dark claw, purple wisps | shadow orb pulling wisps | void implosion, then a smoke pop | wisps, void ring, dark sparks |

Shared textures: crescent slash arc, shockwave ring, soft glow, spark streak, speed lines, hexagon shield.
About 30 sprite sheets in all.

The 8 element attacks (Cone / Circle / Line in `BattleCatalog.ElementAttacks`) reuse the element's textures in
their shape: a Cone becomes a fanned blast of the element, a Circle a ground nova, a Line a long sweeping strike.

## Specials (the 9 kinds, recoloured and retextured per element)

| Kind | Animation + effect |
|---|---|
| Blast | an orb grows above the pet, fires, and explodes into a dome + shockwave |
| Beam | charge glow at the mouth, then a thick beam wrapped in spiral arcs; impact flare at the end |
| Pounce | crouch, a leap with afterimages, a slam landing that cracks the ground |
| Storm | a cloud gathers over the target and rains the element (fire rain, hail, lightning, falling stars...) |
| Freeze | a crystal cage in the element's colour locks the target |
| Heal | spirals of glowing petals rise around allies, plus-shaped sparkles |
| Shield | a hexagon bubble around each ally, rippling when hit |
| Rally | the pet roars; rings pulse outward; allies light up |
| Haste | wind-streak trails and speed lines on allies |

## Signature specials (12 pets)

| Pet | Rarity | Element | Special (kind) | Signature twist |
|---|---|---|---|---|
| Ember Phoenix | Legendary | Flame | Phoenix Flare (Blast) | spreads blazing wings, the orb is a phoenix-shaped fireball |
| Sunbeam Bear | Legendary | Earth | Golden Aegis (Shield) | a golden sun-disc shield with rays |
| Twilight Dragon | Legendary | Shadow | Dusk Storm (Storm) | a dusk-purple storm with falling shadow stars |
| Cloudy Dragon | Mythic | Storm | Cloud Breath (Beam) | a cloud dragon spirals up, then breathes the beam on the dive |
| Starlight Unicorn | Mythic | Celestial | Wishing Star (Heal) | a giant wishing star rises and showers allies |
| Stormfang | Secret | Storm | Storm Pounce (Pounce) | a lightning storm-wolf charges through the target |
| Eclipse Dragon | Secret | Shadow | Eclipse Nova (Blast) | the battle dims for a moment; a black-sun ring bursts |
| Obsidian Phoenix | Secret | Flame | Shadowflame Storm (Storm) | black-flame wings sweep the field; dark fire rains |
| Phantom Kitsune | Secret | Shadow | Foxfire Ward (Shield) | nine ghost fox-fire orbs circle each ally |
| Magma Cub | Secret | Flame | Lava Slam (Blast) | erupts from a lava crack; magma spikes ring the target |
| Rime Wyrmling | Secret | Frost | Glacier Breath (Freeze) | breathes a glacier that rises around the target |
| Hydralotl | Secret | Shadow | Void Fangs (Rally) | void serpent heads rise behind the pet and roar |

## Pet body animation

Poses on the existing rig, for every pet:

- Melee: crouch -> stretch-lunge, wings snap open -> settle.
- Ranged: rear back -> recoil, muzzle flash.
- Special: rise, wings spread wide, glow gathers -> release.
- Hurt: quick squash + flinch, eyes squeeze shut (EyeLid group).
- KO: tumble + element-coloured poof.
- Victory: hop-spin + sparkle burst.
- Battle idle: breathing, ear twitches, glances between hits.

## Budgets, quality, readability

- My own team: full density. Other players' and wild pets' effects: about 60% density, no camera punch, no screen glow.
- Concurrent effect budget: a fixed number of full effects at once; extras step down a tier, then fall back to the
  cube effects. Particle caps per effect scale with tier and quality.
- Low graphics (`GraphicsQuality.Effective() == "Low"`) or phones on Low: lighter kits (fewer emitters, no bloom, no
  trails), or the cube effects.
- Existing caps stay: `MAX_FX_PARTS 260`, `MAX_NUMBERS 26`, `MAX_FLASHES 8` (tests check them).
- Never hide the fight: effects stay out of the camera's near plane, and the screen glow is edge-only.

## Testing and verification

Automated (the project's smoke harness, `tools/run_checks.sh` / `node tools/check.mjs`):

- Catalog completeness: every element x {Basic melee, Basic ranged, 9 special kinds, element attack} x 7 rarities
  x 3 stages resolves to a recipe; all 12 signatures resolve.
- Every texture key used by a recipe exists in `TextureIds` and is an Image id (a check script with Studio verifies
  `AssetTypeId == 1` and `PreloadAsync == Success`).
- Budget under stress: a 16-fighter raid run keeps `AttackFx.Stats()` within caps; Low quality uses the light path.
- Existing battle tests keep passing (`smoke_p3_battleclient`, `smoke_p3_visual`, `smoke_dgfix_client`,
  `smoke_p5_battleclient`, `smoke_p6_evofx`), including "no predicted lunge on a press" and "DODGED! on a miss".

Visual:

- Dev command `/fx <element> <attack> <rarity> [stage]` plays any combination in front of the developer.
- Each wave is checked in Studio with screenshots from several angles before it counts as done; Gemini reviews the
  screenshots as creative judge when it is available.

## Build order (waves, with player check-ins)

1. **Textures**: Blender render scripts + all sprite sheets; upload through Studio; `TextureIds`. Check-in: the
   player sees the texture sheet.
2. **Engine**: `AttackFxCatalog`, `AttackFx`, `PetPoses`, budget, quality, fallback, `/fx` command, tests.
3. **Flame end to end**: melee, ranged, element attack, Blast / Pounce / Storm. Check-in: the player reviews it in
   Studio before the rest.
4. **The other 7 elements** (normal + element attacks).
5. **The 9 special kinds** for every element.
6. **Signatures** for the 12 top pets.
7. **Tuning, performance, full gate**; rebuild `play/NimbusClimb.rbxlx`; commit and push.

Per the project rules: brainstorm done (this spec), then a multi-agent workflow per wave (Opus builds, Fable reviews
and verifies), commit and push after every milestone.

## Risks

- Roblox has no heat distortion or custom shaders: "close to the reference", not identical.
- Texture moderation can delay new uploads; until an id loads, that recipe uses the cube fallback.
- Many textured emitters can cost frames on phones: the budget, density rules and Low path are there for that,
  and the stress test checks them.
- Gemini was unavailable (Google 503 overload) during this design; its review happens on this spec once it is back.
