# Phase 6 style reference: BEFORE (Phase 4, 7aa0df2) vs NOW (Phase 5, v3-phase5 HEAD c68175f)

Folder: `/tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad/p6design/style-ref/`

Paths below: P5 is `/home/user/roblox/nimbus-climb/...` at HEAD. P4 is the same path at commit `7aa0df2`. Read P4 files with
`git -C /home/user/roblox show 7aa0df2:nimbus-climb/<path>`; the worktree was removed after the renders.

## 0. The comparison sheets (BEFORE on top in green, NOW below in red)

| File | What it shows |
|---|---|
| `compare_portals_lineup.png` | **Every lobby portal / gate**, 3/4 view. Each one is cut out of the lobby dump, turned to face the camera and set in a row (`scripts/lineup.py`) |
| `compare_portals_front.png` | The same rows, straight front view |
| `compare_portal_closeup.png` | P4 `Portal_Hard` (lobby crop) vs P5 `Portal_Obby` (`gate:Obby`) |
| `compare_portals_wide.png` | P4 portal fan on the stone promenade vs the P5 Gate Court |
| `compare_lobby_centre.png` | The spawn area, the same world box in both trees |
| `compare_lobby_whole.png` | The whole lobby |
| `compare_homeplot.png` | `homeplot:SkyCastle:pads` |
| `compare_pets.png` | `pet:cloudy_dragon`, `pet:stormfang`. They are the same in both trees (PetBuilder only gained 38 lines). They are the style reference |
| `compare_arena_entrance.png` / `compare_arena.png` | Colosseum gate + forum where the bridge lands / the whole island |
| `compare_homeportal.png`, `compare_altar.png` | Unchanged (home portal) / almost unchanged (the altar's clouds turned lavender) |
| `compare_materials.png` | **Material map**: what the plain renders hide (see the caveat below) |
| `material_stats.txt`, `palette_top.txt` | Numbers behind the sheets |
| `raw/` | Every single render, the JSON dumps and the two lineup dumps |
| `scripts/` | `lineup.py`, `autocrop.py`, `matstats.py`, `compose.py`: they rebuild the sheets |

**Caveat.** `tools/render_model.py` shades everything with flat Lambert. It draws Slate, Cobblestone, Grass, Brick, Marble
and the other materials as flat colour and has no Future lighting or atmosphere. So the plain sheets UNDER-state how
realistic P5 looks in Roblox. `compare_materials.png` paints each material in a code colour to show where real textures
sit. In P5 almost every walkable or built surface of the plaza and the plot is a textured material. In P4 everything is
SmoothPlastic.

## 1. What I see (looked at every sheet)

* **Portals.** P4 had **round voxel hoop gates**: a chunky pixel ring in the difficulty colour around a white cloud
  frame, a translucent glowing swirl, stone pillars with coloured caps, a gold star crest (1-5 lit stars) and a tiled
  voxel pad with a glowing plus. They were cute, toy-like and colourful, and each portal had its own bright colour. P5
  has **classical arches**: round Marble columns on Slate plinths, a dark Slate lintel with a thin neon line, a dark
  box holding a 6x6 neon glyph, a flat neon disc and a grey slab pad. These read as grey "monuments" with a little
  neon, and their stepped voxel silhouettes are gone.
* **Ground.** P4 had lime grass (108,186,86; saturation 0.54) and cream stone paths (208,202,190) with darker borders.
  P5 has olive grass (112,152,100; saturation 0.34) with the Grass texture, dark blue-grey Slate courts (84..130),
  grey Cobblestone and Brick kerbs, and a brown WoodPlanks avenue. The world got darker and greyer.
* **Clouds.** P4 had white / very light blue (232,238,249 / 194,211,240). P5 has lavender-pink (240,232,248 /
  206,193,232 / 186,172,222) to match the pink sky.
* **Home plot.** The P4 Sky Castle is a white voxel keep with blue stepped voxel roofs, gold trim and coloured station
  roofs. In P5 it became grey Slate cylinder towers with brown cone roofs (Cylinder parts, ClayRoofTiles) and muted
  stations.
* **Arena.** P4 was already partly textured (Slate 42% and Sand 39% of the top area, from Phase 3). P5 adds red Brick
  walls, a Cobblestone / Grass forum, Marble trims and a column-arch Return portal.
* **Pets / altar / home portal / tokens.** Unchanged, still the fine-voxel look the player likes.

Numbers (`material_stats.txt`, top-face area, clouds excluded):

| | P4 lobby | P5 lobby | P4 plot | P5 plot |
|---|---|---|---|---|
| SmoothPlastic | 99.9% | 63.8% | 99.7% | 68.8% |
| Grass / Slate / Cobblestone / Wood / Brick / Marble | 0 | 23 / 3.1 / 3.5 / 2.6 / 1.3 / 0.5 % | 0 | 14 / 6.8 / 4.8 / 0.8 / - / 2.2 % |
| area-weighted saturation | **0.39** | 0.22 | 0.25 | 0.19 |

## 2. What exactly made Phase 5 look realistic (with file:line)

1. **Lighting technology.** `default.project.json:27` `"Technology": "Future"` (P4: `"ShadowMap"`). Future adds
   per-pixel PBR, specular and shiny material response. That is what makes Slate / Marble / Metal read "real".
2. **LightingService look** (`src/server/Services/LightingService.lua:29-113`, P4 `LOOK` at
   `LightingService.lua:30-97` in 7aa0df2):
   * ColorCorrection Saturation **0.14 -> 0.06** (`:30`), Contrast 0.10 -> 0.12, tint (255,250,242) -> (255,246,252).
   * `Look.Fallback` is what the game uses today, because `Config.Sky.Faces` is all `""` (`src/shared/Config.lua:494-496`).
     It sets ClockTime **14.5 -> 16.6** (golden hour, `:78`), Brightness 2.0 -> 2.6, Exposure -0.15 -> +0.1, lavender
     Ambient (118,104,140) / OutdoorAmbient (160,140,180), Atmosphere Density 0.28 -> 0.36, **Haze 1.0 -> 2.0**,
     Glare 0.25 -> 0.4, pink Color (220,176,232), violet Decay (126,104,214) (P4: light sky-blue (178,198,228) with a
     peach horizon (238,200,170)). The result is a purple, hazy, low-contrast dusk.
   * `Look.Custom`: EnvironmentSpecularScale 0.35 -> **0.45** and EnvironmentDiffuseScale 0.6 -> 0.7 (`:49-50`), so
     the sky tints the shade.
   * Bloom 0.16 / 18 / 1.6 -> **0.25 / 24 / 1.35** (`:29`): a softer, glowier, "cinematic" image.
3. **LightingStack** (`src/client/LightingStack.lua`, new in P5). It only layers presets: `DungeonController.lua:138`
   (darker dungeon) and `GraphicsQuality.lua:4` (GfxLow). Neutral, keep it.
4. **WorldStyle art kit** (`src/shared/WorldStyle.lua`, new). Its header `:2` says it outright: *"Less cute, crafted, still
   bright": real Roblox materials...*.
   * `WorldStyle.Materials` `:52-70`: Slate, Cobblestone, Brick, Marble, WoodPlanks, Wood, Grass, LeafyGrass, Sand,
     ClayRoofTiles, RoofShingles, Metal, Glass, Fabric, ForceField. SmoothPlastic is allowed only for parts <= 2 studs.
   * `WorldStyle.Palette` `:84-119`: muted surfaces such as Slate (108,112,130), Cobble (152,146,156), Grass
     (112,152,100), Brick (156,106,96) and Wood (116,88,70). Lavender cloud colours `:103-105`.
   * `WorldStyle.BuildGate` `:434-600`: the column / lintel gate. The round Marble `Cylinder` shafts are at `:458`,
     plus a Slate lintel, a neon inlay, a disc + ForceField and a glyph medallion.
5. **The art rules** of the contract: ARCHITECTURE_V3.md 6.4 (line ~2440), from the player's P5 request row 6, *"less
   cute, more high-quality, serious-game looking"* (ARCHITECTURE_V3.md:1775). The rules: real materials only, big-face
   saturation <= 0.45 and value 0.35..0.9, saturated colour only on pieces <= 8 stud^3 or neon <= 0.5 thick, one
   accent hue per structure, plinth + body + cap, chamfers, 4-6 stud tiles with +-6 RGB jitter. **The player has now
   withdrawn that request.**
6. **The builders applied them:**
   * LobbyBuilder palette `C` at `src/server/Services/LobbyBuilder.lua:178-230` (comment `:178` "less cute"). Compare
     P4 `LobbyBuilder.lua:164-210`: Grass (108,186,86), Stone (208,202,190), Plank (196,146,98), Gold (244,198,84),
     Water (92,178,236). The colour-key -> material table `MATS` is at `:233-244`. `box()` turns every big part into a
     WorldStyle material at `:429-432`, with a Marble fallback. The Gate Court / spawn court is at `:1722`.
   * HomeBuilder P5 art kit `src/server/Services/HomeBuilder.lua:75-80, 481-500` (materials table `M`), with
     Ball / Cylinder helpers at `:576-615` (the round tower castle). P4 palette: `HomeBuilder.lua:151-191`.
   * ArenaBuilder art pass `src/server/Services/ArenaBuilder.lua:79, 943-990` (`Art.P` muted palette), Cylinder columns
     at `:1056-1059`, Brick walls / Slate plinth at `:1650`.
   * DungeonBuilder (new, `:36, :57`): WorldStyle materials, Cylinder / Ball props `:318-531`.
7. **Shapes.** P5 introduced round primitives (`Enum.PartType.Cylinder` / `Ball`) for columns, towers, barrels and
   medallions. P4's world was blocky voxels and boxes only. The round, smooth shapes plus PBR textures are the
   "realistic" signal.
8. **Portal design.** The five difficulty portals plus the Trial and Ring portals became ONE gate kit (above). The fun
   per-gate shapes were lost (round hoop, crown arch, sword crest, star crest).
9. **Tests that pin the P5 look** (change them together with the revert): `tools/smoke_p5_world.lua:60` (art-rule audit:
   materials + saturation), `:203` `p5world_lighting` (Look numbers), `:353` `p5world_style`;
   `tools/smoke_p2_final.lua:1767, 1866` (the `"Technology": "Future"` line).
10. Out of scope here but part of the same "less cute" pass: `src/shared/Theme.lua` v5 fonts (Title / Button / Toast
    FredokaOne / LuckiestGuy -> GothamBlack) and the NeonKit UI. The player asked for that UI in P5 row 7 (21.png),
    so leave it unless they say otherwise.

**Keep from P5:** the skybox (the player asked for it, P5 row 12: "a sky like 23.png"; `blender/sky/render_sky.py`), the
Gate Court LAYOUT (six gates for six modes, one Obby portal with a level picker: P5 rows 4-5, gameplay), and the
bigger lobby (row 14). Only the LOOK goes back.

## 3. The Phase 4 portals (rebuild these as detailed voxel Blender models)

Source at 7aa0df2: `src/server/Services/LobbyBuilder.lua:2036-2245` (difficulty portals) and
`src/server/Services/ArenaBuilder.lua:2174-2430` (Trial + Ring portals). One voxel = **1 stud**. Grid frame: x across,
y up, -z = the front facing the plaza. After the shape is built, `Voxel.Shade(g, {Skip = {Glow, Swirl, Gem}, Smooth = 1,
Seed = 8})` adds `_Light` tops and `_Dark` undersides / creases (about 15% lighter / darker, shadows a little cool,
highlights a little warm: P4 `Voxel.lua:38-39, 749-751`).

### 3a. The round hoop gate (`gateBoxes`, LobbyBuilder.lua:2057-2105; the identical `gateHoop` ArenaBuilder.lua:2250-2283)
* Base: RoundRect 22 x 5 (r 1.5) at y 0 in `StoneDark`, then 20 x 4 (r 1.2) at y 1 in `Stone`.
* Pillars at x = +-9: RoundRect 3 x 3.4 from y 2..10 in `Stone`, a 4 x 4.2 `Trim` cap at y 11, a `Glow` (neon) dot at
  y 12-13, a `Trim` stud on the front at y 3, z -2.
* Ring: Torus centre (0,11,0), R 7.6, thickness 1.6, rotated upright, key `Frame`. Its **outer band** (r >= 8.6) is
  repainted `Trim` (the difficulty colour), so you get the stepped coloured pixel edge. The inner neon ring is Torus
  R 5.9, thickness 0.5, `Glow`. The swirl is an Ellipsoid of radius 5.3 x 5.3 x 0.2, `Swirl`.
* Keystone: RoundRect 4 x 3 at y 19-20 in `Trim`, with two `Gem` voxels on the front (y 19, 20; z -2).
* Footprint about 22 wide x 21 tall x 5 deep. LOD MaxParts 105 (about 141 parts per portal with pad, lanterns and
  stars).
* Palette (`gatePalette`, :2043): Stone = StoneLight (226,221,209); StoneDark = Stone (208,202,190); Frame = CloudLight
  (244,247,252); Puff = Cloud (232,238,249); Trim = difficulty colour; Glow = colour, **Neon**; Swirl = colour lerped
  35% to white, **Neon, Transparency 0.62**; Gem = Gold (244,198,84), **Neon**.
* Difficulty colours (P4 `Config.lua:193-267`, mirrored in `Theme.World.Trim`):
  * Easy (96,190,140)
  * Medium (96,160,224)
  * Hard (226,150,74)
  * Extreme (214,92,104)
  * Saint (150,110,220)
  * Trial red (222,74,80) (ArenaBuilder.lua:2174)

### 3b. Pad, lanterns, crest, effects (buildPortal, LobbyBuilder.lua:2130-2245)
* Ready pad: a 14 x 14 voxel tile plate 0.3 above the ground. Outer ring `Trim`, next ring StoneLight, the rest Stone
  (208,202,190), and a neon diamond / plus in the middle (|i|+|k| <= 2.5) in the difficulty colour. The Trial pad has
  a neon X instead (ArenaBuilder.lua:2331-2356).
* Two lanterns on the front pad corners: a 0.7 x 3.2 Iron post (64,70,92), a 1.1 x 0.3 cap and a 0.9 neon cube in the
  colour.
* Star crest above the keystone: a GoldDark (206,154,62) post 0.8 x 1.3 and a bar, then 5 gems of 1.5 x 1.5 x 0.8
  turned 45 degrees, 2.6 apart at y 23.6. Lit stars are Gold Neon; unlit ones are StarOff (96,104,136) SmoothPlastic.
* Effects (keep as Roblox instances, NOT mesh): an invisible `SwirlCore` 9 x 9 x 0.4 at y 11.5 with a PointLight
  (colour, 1.3, range 28) and a sparkle ParticleEmitter (Rate 12, life 1.4-2.2, speed 1.5-3.5, front, 30 degree
  spread). There is also a pixel BillboardGui tag (title, stars + players, status pill).

### 3c. Champion Ring gate (`Ring.gateVoxels`, ArenaBuilder.lua:2211-2248)
A square stone arch instead of the hoop. Pillar blocks x 7..9 per side (y 2-16) with `Trim` gold bands at y 2 and 15.
Violet `Gem` studs run up the pillar fronts (y 6, 9, 12). There is a neon `Glow` frame and a `Swirl` panel of
11 x 13. The lintel has a Trim course at y 17 and Stone at y 18. On top sits a **big gold crown**: a band (y 19-20)
with 3 gems, three points (middle tallest at y 23) and two small ones, a gem on every tip.
Colours: Gold (250,190,56), accent violet (156,96,238). The pad is plain plates with a neon crown inlay.

### 3d. Trial gate crest (ArenaBuilder.lua:2408-2419)
The hoop gate in Trial red with a **crossed-swords + shield crest** instead of stars: a shield 2.4 x 2.6 with a Gold
rim, two steel blades turned +-42 degrees, gold guards and grips.

### 3e. Mapping to the six P6 gates (suggestion for the lead; the Gate Court layout and prompts stay)
* **Obby**: the round hoop + the 5-star crest. Show stars = levels unlocked, or a static 5.
* **Ring**: the 3c crowned square arch.
* **Arena**: the hoop + the 3d sword crest.
* **Dungeon**: the hoop in purple with a torch / skull crest.
* **Home**: the hoop in yellow with a house crest.
* **Altar**: the hoop in cyan with a bolt crest. the P4 Storm Altar entrance gate is `StormAltarSign` in StormAltar.lua:32.

Same silhouette family, each with its own colour and crest. "More detailed" means:
* voxels at 0.5 stud: the same 22 x 21 stud gate becomes a 44 x 42 grid;
* a beveled stepped ring;
* 2-3 shades per colour, pixel brick seams on the pillars and small cloud puffs at the base;
* a gem keystone with a highlight voxel;
* a 2-tone tiled pad with a pixel border pattern.

The neon parts must stay separate Neon parts (not mesh): the inner glow ring, the swirl disc and the gems.

## 4. Style rules for every Phase 6 Blender model

**Look.** MagicaVoxel-style detailed voxels: bright, cute, colourful, crisp cube edges, no round primitives, no bevels,
no smooth shading. Silhouettes are stepped. Curves come only from small voxels.

**Shading is painted, not lit.** Give each colour region 2-3 shades, like P4 `Voxel.Shade`:
* `_Light` = base x 1.15, slightly warm, on voxels whose up-normal >= 0.55;
* `_Dark` = base x 0.85, slightly cool (R x 0.84, G x 0.85, B x 0.89), on undersides (normal <= -0.35) and creases
  (exposed voxels whose 2-voxel neighbourhood is <= 22% empty);
* plus deterministic +-1 shade "noise" on big flat areas (Smooth = 1), so walls and grass are never one flat colour.

**Patterns.** Add pixel patterns everywhere: brick seams, plank lines, grass tufts in 2 greens, stone tile checker,
fur stripes / spots / bellies. Eyes are carved sockets with a dark iris, one white highlight voxel and a darker lid
row.

**Palette (big surfaces bright and saturated; the P4 numbers are the reference):**
* grass (108,186,86) / light (132,202,98) / dark (86,160,76); hedge (74,146,72)
* path stone (208,202,190) / (226,221,209) / edge (146,138,132)
* sand (236,214,166); planks (196,146,98) / (214,166,114) / (152,108,72); bark (132,92,62)
* gold (244,198,84) / (206,154,62); iron (64,70,92); water (92,178,236) / (62,136,212)
* blossom (246,174,204); white-blue clouds CloudLight (244,247,252) / Cloud (232,238,249) / CloudShade (212,222,241) /
  Mist (194,211,240) / MistDark (170,190,228)
* roof accents blue (88,136,226)
* the mode / difficulty colours from 3a
* Targets: area-weighted saturation of a scene about 0.35-0.45 (P4 lobby 0.39, P5 0.22). Big faces may reach
  saturation 0.55. Never pure white; cloud tops < 249.

**Clouds.** The P5 lavender cloud palette (WorldStyle.lua:103-105, LobbyBuilder.lua:182-186) only fits the pink sky.
P4 used white / light blue. Ask the lead which way to go: P4 clouds fit "back to P4", lavender fits the kept skybox.
Either is fine as voxels.

**Voxel size per model class.** P4 values first, then the P6 target ("more pixels"):
* Pets / evolved forms / accessories / wings / NPC pets: 0.1 stud, grid 30 -> **0.07-0.08 stud (grid about 40)**,
  High <= 4k tris, Low <= 1.5k.
* Tokens / Cloud Cash: 0.1 -> **0.06-0.08**.
* Stormfang, wild / enemy pets: same as pets.
* Bosses: 0.5 -> **0.25-0.33** (22-27 studs tall), <= 10k tris.
* Sky dragon: 1.0 -> **0.5**.
* Portals / gates / Storm Altar shrine: 1.0 -> **0.5**, <= 6k tris each.
* Lobby props (lamps, benches, signs, fountain, trees, shop machines): 1.0-1.4 -> **0.5** (trees 0.5-0.7).
* Home stations / house tiers / decor: 0.5 -> **0.25-0.33**.
* Arena / dungeon rooms and props: 1.0 -> **0.5**. Walls / floors as 1-stud brick / tile cells with 2-3 shades.
* Floors / plaza ground / plot yards: tile cells of **2 studs** (4-6 in P5) with shade checker and pixel borders, one
  merged mesh per area.
* Voxel clouds / islands: 2-3 -> **1-1.5**.

**Mesh export.** Use only the outer faces and greedy-merge coplanar same-colour faces into quads. Respect the Roblox
per-MeshPart limit (about 20k tris; `blender/pebble_pup.py:20`). Split big scenes into several MeshParts by area for
streaming / LOD.

**Colours on MeshParts.** Use one small **palette texture** (for example 256 x 256 px, each shade a 4 x 4 texel cell,
UVs on the cell centres so mips do not bleed) on `MeshPart.TextureID`, with the MeshPart `Color` white. Do not bake
1024 px textures per model as pebble_pup does: one shared palette atlas means one upload for everything. Do not rely
on vertex colours.

**Roblox materials.**
* All MeshParts: `SmoothPlastic`, `Reflectance 0`, no SurfaceAppearance PBR.
* Never Slate / Cobblestone / Brick / Marble / Grass / WoodPlanks / Metal / ClayRoofTiles / Fabric textures.
* Glow (portal rings, swirls, gems, lanterns, star crests, neon inlays) stays as separate `Neon` Parts (portal swirls
  Transparency about 0.62), so the glow survives.
* Water: SmoothPlastic or Glass Parts, translucent blue blocks.
* `CastShadow` false for small meshes.
* Collision: `CollisionFidelity = Box` or invisible box Parts for walkable floors and gates. Keep the existing zone /
  pad / prompt Parts, which are gameplay, not models.

**Lighting to revert** (one change in `LightingService.lua` + `default.project.json` + the two pinned tests):
* `Technology` -> **ShadowMap** (`default.project.json:27`).
* Use the P4 `LOOK` values for the world light: ClockTime 14.5, latitude 34, Brightness 2.0, Ambient (98,106,132),
  OutdoorAmbient (132,138,160), ColorShift_Top (66,50,26), _Bottom (14,20,40), EnvironmentDiffuse 0.6, Specular
  0.35, Exposure -0.15, ShadowSoftness 0.3.
* ColorCorrection Saturation **0.14**, Contrast 0.1, Tint (255,250,242).
* Bloom 0.16 / 18 / **1.6**; SunRays 0.06.
* Atmosphere Density 0.28, Offset 0.25, Haze 1.0, Glare 0.25. Colour: the P4 sky-blue (178,198,228) / peach
  (238,200,170), or a lighter pink if the lead keeps the pink skybox.
* Do not use the golden-hour Fallback (16.6, Haze 2.0).
* Keep the Blender skybox path (`Config.Sky.Faces`) and LightingStack as they are.

**Fallback.** For a model with no asset id, keep today's Part build. For the world builders, the better fallback is the
**P4 builder look** (bright SmoothPlastic voxels), not the P5 WorldStyle look, so the game matches the target style
even before the uploads.
