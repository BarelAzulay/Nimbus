# Phase 6 inventory (inv-lobby): lobby, WorldStyle kit, Storm Altar (non-creature), portals/gates, obby course, runtime parts

Repo read: /home/user/roblox/nimbus-climb (branch v3-phase5), read-only. All file:line refs are to that tree.
Part counts are MEASURED: LobbyBuilder.Build() + StormAltar.Build() and 15 CourseBuilder builds (5 difficulties x 3 seeds)
inside the repo's own mock (tools/render_model.py LuaWorld). Raw output: `work/counts.txt`, `work/course.txt`
(scripts `work/count.py`, `work/count.lua`, `work/course.lua` in this folder).

Totals today
* `workspace.NimbusLobby` after LobbyBuilder + StormAltar: **8161 BaseParts** (lobby 7369 + StormAltar 792, of which the
  Stormfang showcase pet is 343). Ring / Arena / Dungeon gates are added later by ArenaBuilder / DungeonBuilder (not counted).
  Breakdown: Gates 136, Spots 1776 (16 x 111), Shop 818, Plaza 3461, Roads 472, Gardens 544, Sky 162.
* One obby course (CourseBuilder.Build): Easy 754-840, Medium 1047-1171, Hard 1319-1429, Extreme 1797-1965,
  Saint 2295-2462 parts (tokens = 179-706 of those; tokens belong to the TokenLook inventory).

Scope notes
* GateService: builds NO geometry (only ProximityPrompts on `LobbyInfo.Gates.<Id>.PromptPart`). Integration surface only.
* LightingService / client LightingStack: NO geometry (Sky faces = images already rendered by blender/sky/render_sky.py,
  Terrain.Clouds is an engine object). Nothing to convert.
* ObbyLevels.lua: pure data. The obby geometry is CourseBuilder.lua (+ CourseLayout data, + HazardService runtime fx).
* SpotService / ItemService / PortalService / HazardService / TutorialController: only runtime parts (anchors, VFX, lock
  walls, guide arrow) - listed in section F.
* Out of my scope but touching these models: NimbusStatue on the fountain (PetBuilder pet), StormfangShowcase (pet),
  tokens (TokenService/TokenLook), Ring/Arena/Dungeon gate extras (ArenaBuilder/DungeonBuilder), HomeBuilder's `Home`
  folder inside each Spot_NN.

Legend for "Runtime needs": **C** = CanCollide walking/blocking surface, **Q** = CanQuery (raycasts), **N** = name looked
up by other code/tests, **A** = attributes, **T** = CollectionService tag, **P** = ProximityPrompt host,
**G** = Billboard/SurfaceGui host, **L** = light/emitter host, **M** = moved / tweened / faded at runtime,
**R** = recoloured at runtime / per instance. "Fixed" colours come from the module palette (LobbyBuilder `C` :174-229,
WorldStyle.Palette :88-120, StormAltar `C` :127-160, CourseBuilder `C`/THEME_LOOK :74-149).

---------------------------------------------------------------------------------------------------------------------

## A. Shared art kit - src/shared/WorldStyle.lua (used by Lobby, Arena, Dungeon, Home builders)

| Id | Builder | What | Variants | Colour regions | Size (studs) | Runtime needs | Parts |
|---|---|---|---|---|---|---|---|
| **GateArch** | `WorldStyle.BuildGate` WorldStyle.lua:434-598; called by LobbyBuilder `Gates.BuildOne` :2291 (Home/Obby/Altar), ArenaBuilder :2601 (Ring/Arena), DungeonBuilder :1147 (Dungeon) | The Gate Court portal gate: 2 round Marble columns on Slate plinths, collars, capitals, Slate lintel + cornice + soffit, chamfered keystone medallion with KeystoneCap, EmblemPanel, 2 WedgePart corbels, Neon inlay ring (L/R/Top/Lintel/Sill), Slate sill | 6 gates (Home, Obby, Dungeon, Ring, Arena, Altar); Pad vs Step; glyph (see GateGlyph) | **R: accent** (Neon inlays, PortalDisc, PortalShimmer tint, Emblem, PadGlyph, GateLight, sparkles, tag border) from spec.Color = WorldStyle.Palette.Accent (Yellow/Blue/Purple/Gold/Red/Cyan) or Theme.Neon; fixed Marble/MarbleShade/Slate/SlateDark/Metal | 22 x 26 x 8 (WorldStyle.GateSize) | Model `Portal_<Id>` (**N** everywhere), attrs GateId, Glyph (**A**); PrimaryPart = `Lintel` (BillboardGui `GateTag` adornee, **G**: Plate/Title/Info/Pill/Label written by PortalService :683, DungeonService, ArenaBuilder); `PromptAnchor` invisible 2x2x1 at (0,3,-2.2) (**P**: GateService / PortalService / DungeonService / Arena prompts); `PortalDisc` Neon cylinder Transparency 0.35 hosts PointLight `GateLight` + ParticleEmitter `Sparkles` (**L**); `PortalShimmer` ForceField cylinder; columns/plinths/lintel/sill **C+Q** (solidProps :145); PortalService writes attrs PartyCount/PartyMax/Countdown on the model and parents LockWalls/CountdownFace/BillboardAnchor into it | 43 (Step) / 50 (Pad); +1 Zone_Obby; ArenaBuilder adds <= 30 (crown) |
| **GateGlyph** (x6) | `glyphTemplate` :265 / `placeGlyph` :294; glyphs :218-225 | 6x6 pixel glyph as greedy-merged Neon cells: `Emblem` (vertical, cell 1, 0.2 deep, on the keystone) and `PadGlyph` (flat, cell 1.4, 0.08 thick, on the pad) | house, cloud, torch, crown, swords, bolt; vertical / flat | **R: accent** (all cells) | 6 x 6 x 0.2 / 8.4 x 0.08 x 8.4 | Model names `Emblem` / `PadGlyph` (**N** tests); cells non-colliding | 4-6 cells each |
| **GatePad** / **GateStep** | BuildGate :572-582 | Pad = 14 x 0.6 x 14 Slate slab 14 studs in front + 4 Marble `PadBorder1..4` + flat PadGlyph; Step = 10 x 0.3 x 6 Slate | Pad (Obby, Dungeon, Ring) / Step (Home, Arena, Altar) | fixed Slate/Marble; glyph = accent | 14 x 0.95 x 14 / 10 x 0.3 x 6 | Part named exactly `Pad` / `Step` returned as `pad` (**N**, LobbyInfo.Gates.<Id>.Pad, PortalService zone sits on the pad top), **C+Q** | 1+4+glyph / 1 |
| **StylePlinth** | `WorldStyle.Plinth` :153 | Base block + 0.2 Marble band overhang | any size (param) | colour param (default SlateDark); band MarbleShade fixed | param | **C+Q**; names Plinth/PlinthBand | 2 |
| **StyleKerb** | `WorldStyle.Kerb` :167 | Brick kerb 0.4 x 0.8 + Slate lip under the edge | length param | colour/material params | L x 0.7 x 1.0 | kerb **C+Q**, lip deco | 2 |
| **StyleChamferPillar** | `WorldStyle.Chamfer` :189 | Box with 4 chamfered vertical corners (cross of 2 boxes + 4 turned posts) | size + cut params | colour param (Marble) | param | **C+Q**; returns `body, parts` - callers rename parts[1] (`Keystone`) | 6 |
| (WorldStyleSample) | `WorldStyle.Sample` :601 | render/test reference court with the 6 gates; NOT in game | - | - | 180 x 40 | test target `module:shared/WorldStyle:Sample` | ~300 |

Gate fallback (already the Part fallback path): `Gates.Fallback` LobbyBuilder.lua:2265 (columns, lintel, disc, pad/step,
PromptAnchor, GateTag; same names), used when WorldStyle/BuildGate fails (:2313, :3641).

## B. Lobby - src/server/Services/LobbyBuilder.lua (`LobbyBuilder.Build` :3610 -> LobbyInfo)

### B1. Reusable prop templates (built once by `template(name, make)` :877, cloned by `place(tpl, cf, parent, name)` :860)

| Id | Builder | What | Variants | Colour regions | Size | Runtime needs | Parts (each) / copies |
|---|---|---|---|---|---|---|---|
| **LampPost** | `Props.Lamp` :1046 | Slate foot + Marble band, iron post, collar, glass cage (Glass T0.45), Neon `LampGlass`, roof, gold tip | - | fixed (Lamp neon 255,214,170) | 2 x 10.4 x 2 | `LampGlass` found by name (:1898,:1931,:2051,:2162,:2858) to parent a PointLight (**N,L**); base+pole **C** | 8 / 30 (WalkLamp 10, ExitLamp 8, AvenueLamp 6, CourtLamp 2, ShopLamp 4) |
| **Bench** | `Props.Bench` :1064 | 2 seat planks, 2 back planks, 2 iron frames (NO Seat instance on purpose) | - | fixed Plank/PlankLight/Iron | 5.6 x 3.7 x 2.2 | seat+frames **C** | 6 / 8 (plaza 4, gardens 4) |
| **FlowerBed** | `Props.FlowerBed(v)` :1079 (voxel 1 stud) | raised wooden bed, soil, flower + leaf pixels | v = 1..6 (FLOWERS palette :258) | flower colour per variant (bake 6 variants or one recolourable "Flowers" region); frame fixed | 6 x 2 x 4 | **C** (whole voxel model collides) | 10-11 / 10 |
| **TreeRound / TreeBlossom / TreePine** | `Props.Tree(kind)` :991 (voxel ~1.1) | bent trunk with roots + branch stubs; round canopy (red fruit) / pink blossom (white petals) / 3 pine cones | 3 kinds; yaw per placement | fixed (Leaf/Blossom/Pine/Bark, shaded) | ~12 x 18 x 12 | **C** - every canopy voxel collides today (collision could become trunk-only hull) | 81 / 71 / 40; 4+2+2 plaza, 1+1 gardens |
| **CloudPuffS / CloudPuffM** | `Props.Puff(size)` :1101 -> `VX.CloudModel` :966 | small cumulus puff under bridges / the shop neck | S, M (x1.35) | fixed cloud shading bands | ~22 x 10 x 22 / ~30 x 13 x 30 | non-colliding; tag NC_StyleExempt (**T**) | 14 / 6 spoke + neck 1 |
| **Bunting** | `bunting(parent,a,b,colors,sag)` :1120 | 3-piece sagging rope + 2-part stepped pennants every ~4 studs | length, colours | **R** pennant colours (param) | span x ~3 | non-colliding | 11 (shop) |
| **BannerPole** | `bannerPole(parent,cf,color)` :1159 | iron pole, gold finial, bar, cloth + cloth tip | - | **R cloth** = gate accent (12 poles, 6 colours) | 3 x 11.6 x 0.5 | pole **C** | 5 / 12 |
| **NoticeBoard** | `noticeBoard(parent,cf,w,h,name)` :1170 | 2 posts + stone feet, plank frame, Navy `Face`, roof + Rose roof top | 11x8 (HowToBoard, GuideBoard :2060) and 14x9 (RarityBoard :2632) | fixed | 14 x 12.4 x 2.4 / 17 x 13.4 x 2.4 | `Face` part hosts SurfaceGui `SignGui` (**G**, 50 px/stud; worldtext test counts SignGui); posts/frame **C** | 8 / 3 |
| **SkyCumulusBig / SkyCumulusSmall** | `cumulus(kind)` :3539, `buildSky` :3562 | distant cumulus (voxel 6) | Big 96, Small 60 | fixed (Mist tier) | 96 x ~40 x 53 / 60 x 25 x 33 | non-colliding; NC_StyleExempt | 44 / 4 (SkyCloud x3 + CloudSea) |

### B2. Plaza (layout-baked: geometry is computed from Config.Lobby + gate angles + spokes, `computeLayout` :1188)

| Id | Builder | What | Variants | Colour regions | Size | Runtime needs | Parts |
|---|---|---|---|---|---|---|---|
| **PlazaGround** | `buildPlazaGround` :1479 (+ `plazaCell` :1341, `courtInlay` :1406) | 5 stacked one-cell layers on 2-stud cells: `Lawn` (Grass), `LawnPatches` (dark/light grass + flower pixels), `PathBorders` (Brick/SlateDark/PlankDark), `Paths` (cobbles 2 shades, boardwalk planks), `Inlays` (1-stud spawn medallion: Metal sun, Marble ring, 6 Neon gate arrows thinned to 0.3) | one (deterministic) | Inlays arrows = **R? no**: Gate1..6 accent colours baked; rest fixed | 312 dia, tops at TOP-0.4..+0.1 | **C+Q** on 4 layers (walk surface = Config.Lobby.Origin.Y); Inlays non-colliding; materials must stay Grass/LeafyGrass on lawn (NPC spot test smoke_p5_world :846-857 and NpcService :192 raycast hit.Material); smoke_p5_world :796 probes ground at r 148 in 12 directions | 91+415+229+202+87 = 1024 |
| **SpawnCourt** + **GateCourtFloor** | `Court.Tiles` :1756 via `Court.Arc` :1729 (Model `Courts`) | spawn court: Slate tile rings r 4.6-32 + Marble ring 32-34.4; Gate Court sector r 96-146: tiles, Marble rim, terrace step, raised terrace (+0.3), 2 Marble side kerbs | one | tiles jittered +-6 RGB (Court.Jitter :1748), fixed | spawn 69 dia; sector r 96..146 over ~84 deg | **C+Q** everywhere (court must also hold the Dungeon site free: smoke_p5_world :776 raycast) | 423 |
| **CircleWalk** | `Court.RingRoad` :1804 | cobbled ring walk r 100 (8 wide) with Brick borders, arc segments, open at the Gate Court | one | fixed (jittered) | r 94-106 ring | **C+Q** | 156 |
| **PlazaEdgeKerb** + **WalkHedges** | `Court.Edges` :1875 | Brick kerb arcs around the plaza edge (open at exits); clipped hedge arcs inside the circle walk (+6 WalkLamp) | one | fixed | ring r 151-153 / r 91-93 | kerb **C**; hedges **C** + tag NC_Detail (Low graphics removes them client-side, **T**) | 56 + 28 (+48 lamps) |
| **PlazaCloud** | `buildPlazaBody` :1543 -> `VX.CloudModel` | tiered cumulus island body under the plaza, side puffs, soft rim of puffs, carved exits for spokes / shop boardwalk | one | 5 cloud shade bands (TIER_KEYS :311) | ~318 dia x ~40 deep | **C** (Collide true; rim puffs rise ~5 studs above the lawn), NC_StyleExempt | 514 |
| **Fountain** | `buildFountain` :1633 | stone basin (Slate/Marble, 2 bowls, gold rim studs), translucent water (Glass T0.35 + falling water), `Spray` anchor | one | fixed | 20 dia x 10 (statue to ~16) | `Basin` **C**, `Water` non-colliding; `Spray` anchor (**L** emitter + light); NimbusStatue = PetBuilder (other inventory) | 105 + 26 + 1 (+114 statue) |
| **GateCourtPlanters** | `Court.Decor` :2023 | Brick planter arcs + hedge arcs along the terrace back | one | fixed | sector r 142.6-145.6 | **C**; model `GateCourtDecor` tagged NC_Detail | 21 + 21 |
| **Obelisk** | `Court.Obelisk` :1992 | Slate plinth, chamfered Marble shaft, Neon band, cap, 2 gold WedgePart tips | x2 | band **R** = param (Gold accent) | 5 x 17.9 x 5 | plinth/shaft **C** | 12 / 2 |
| **WelcomeArch** | `Court.WelcomeArch` :1945 | 2 chamfered Marble piers on Slate plinths, caps, Slate/Marble beam + cornice + soffit, gold Neon inlay, sign frame + cap, `WelcomeSign` board | one | fixed (inlay Gold accent) | ~30 x 35.5 x 4.4 | `WelcomeSign` hosts 2 SurfaceGuis (front/back, **G**); piers + beam **C** | 25 |
| **AvenueKerb** | `Court.Avenue` :1909 (WorldStyle.Kerb x2, 6 AvenueLamp) | Brick kerbs along the 20-wide avenue | one | fixed | 2 x ~60 long | **C** | 4 (+48 lamps) |
| **PlazaFallback** (keep) | Build :3681 | plain floor + neck floor when the plaza fails | - | - | - | - | 2 |

### B3. Shop island (`buildShop` :2700; last-resort `fallbackShop` :2885)

| Id | Builder | What | Variants | Colour regions | Size | Runtime needs | Parts |
|---|---|---|---|---|---|---|---|
| **ShopIslandGround** | buildShop :2715-2757 (Ground1..5) | lawn, patches + flowers, Brick borders, stone court r 19 + entrance path, inlay rings | one | fixed | 68 dia | **C+Q** | 92 |
| **ShopCloud** + **ShopNeck** | buildShop :2760-2796 | cloud body (Rim/Puffs), stone neck slab to the plaza, NeckPuff | one | cloud bands; neck Stone | ~74 dia x ~20; neck 13.7 x 1.2 x ~10 | cloud **C**, NC_StyleExempt; neck **C** | 108 + 1 + 14 |
| **RouletteMachine** (x4) | `buildMachine` :2489, sculpt `machineBoxes` :2422 (0.5-stud cabinet + 1-stud glass dome), palette `machinePalette` :2394; fallback `fallbackMachine` :2532 | gacha cabinet: iron base, gold trims, body, 8-segment prize wheel with rim/hub/red knob, chute, marquee bulbs, side lever, glass dome full of eggs | Cloud, Storm, Sky, Celestial (Config.Roulettes) | **R per roulette** (keys = part names after Voxel merge): `Body` = muted(roulette.Color), `Seg1` = muted lighter, `Knob` = Neon roulette.Color, `Egg1..4` = muted rarity colours of that roulette's Odds; fixed Base/Trim/Rim/Hub/Dark/Glass(T0.55)/Bulb/Iron/Seg2 | ~10.5 x 14 x 7.5 | Model `Roulette_<Id>` (**N**: TutorialController :2319 bounds, tests smoke_server/p2_ui/p2_visual/storm/client_v2/release_client); PrimaryPart = biggest `Body` part (:2501); **C+Q** (all machine voxels); `PromptPart` invisible 5x4x3 at (0,2,-5.4) (**P** PetService); `PriceAnchor` (**G** BillboardGui `PriceBillboard`, worldtext census); `DomeGlow` (**L**); LobbyInfo.Shop.Roulettes[id] = {Id, PromptPart, Center, Model} | 101 + 3 / 4 |
| **ItemStall** | `buildItemStall` :2547 (voxel 1); fallback :2619 | striped Rose/Cream fabric stall: counter, shelf, posts, sloped striped awning with fringe, goods (heal cloud, shield bubble, feather, coins) | one | fixed (Fabric stripes are saturated but small) | 15 x 12 x 9 | Model `ItemShop` (**N** ItemService, tests smoke_server/economy/worldtext); PrimaryPart = Stall.PrimaryPart; `Stall` **C**; `PromptPart` (**P** ItemService); `SignAnchor` (**G** `ItemShopBillboard`); `StallLight` (**L**) | 69 + 3 |
| **RarityBoard** | `buildRarityBoard` :2632 | NoticeBoard 14 x 9 with the roulette/rarity SurfaceGui | - | fixed | 17 x 13.4 x 2.4 | **G** on `Face` | 8 |
| **TokenStatue** | `buildTokenStatue` :2667 (voxel 1) | big gold coin with a glowing cloud emblem on a stone pedestal (decor, NOT a collectible) | - | fixed (Gold, GoldGlow neon) | 6 x 12 x 6 | `Coin` **C**; `CoinSparkle` (**L**) | 30 + 1 |
| **ShopArch** | inline buildShop :2833-2853 | stone pillars (dark foot + light shaft), Rose caps, Neon lamps, plank beam, `ShopSign`, Rose sign roof | - | fixed | ~18 x 14.8 x 2.6 | pillars **C**; `ShopSign` 2 SurfaceGuis (**G**) | 11 |
| (+ ShopLamp x4, Bunting, FlowerBed x2, Fireflies anchor) | :2854-2876 | reuse B1 props | | | | | |

### B4. Home plots (x16, `plotTemplate` :2917 cloned by `buildSpot` :3176; fallback `fallbackSpot` :3234)

| Id | Builder | What | Variants | Colour regions | Size | Runtime needs | Parts (per plot) |
|---|---|---|---|---|---|---|---|
| **HomePlotIsland** | plotTemplate :2927-2969 (`VX.CloudModel`, V=6) | puffy cloud cushion under the yard: side billows, back billows, hanging cumulus, rim puffs; carved so nothing rises over yard/verge/street | one (seeded) | cloud bands | ~88 x ~25 x ~100 | **C**, NC_StyleExempt | 56 |
| **HomePlotGround** | plotTemplate :2971-3000 | 6 mowed lawn stripes (72x72 yard), 3 dark margins, verge, 3 stepping stones, 4 street slabs + 2 curbs (ring street piece), low hedge + hedge top | one | fixed | 88 x 1 x ~100 | **C+Q** (walk surface at TOP; yard = TycoonCatalog PlotSize 72, HomeBuilder builds on it) | 21 |
| **PlotFence** | plotTemplate :3002-3023 | 10 fence posts + 5 rails around the yard, open 16 studs at the gate | kit: post, rail (lengths 72 / 28) | fixed | 72 x 3 x 72 | **C** | 15 |
| **PlotGate** | plotTemplate :3025-3032 + `buildSpot` :3200-3206 | 2 stone bases, pillars, caps, Neon lanterns, plank beam; per plot: 2 `GateBanner` + `NumberSign` | one | **R GateBanner** = plot accent (ACCENTS :268, 8 cycled); rest fixed | 17 x 8.4 x 2.6 | pillars **C**; `NumberSign` (Plank board) hosts 2 SurfaceGuis "No. N" (**G,N**: smoke_polish_worldtext :491) | 9 + 3 |
| **Mailbox** | plotTemplate :3034-3037 + buildSpot :3203 (`MailFlag`) | post + iron box + accent flag | - | **R MailFlag** = accent | 1.4 x 4.7 x 2.2 | post **C**; `NameplateAnchor` invisible above it (**G** `Nameplate` with Avatar/Headshot/Silhouette/FreeIcon/NumberBadge, attrs OwnedColor/FreeColor, NameLabel/SubLabel driven by SpotService :216-262) | 2 + 1 |
| **PetPodium** | plotTemplate :3039-3046; recolour buildSpot :3189-3196 | stepped stone podium: base, `Accent` band, top | - | **R `Accent`** = muted(plot accent) (found by name under `Podium`) | 6 x 3 x 6 | Model `Podium` + part `Accent` (**N,R**); **C**; top = SpotInfo.PodiumCFrame (computed from PLOT_POS, not from parts); HomeBuilder `Art.Podium` (:2013) dresses it | 3 |

Spot runtime contract (keep): Folder `Spot_NN` attr `SpotIndex` (**N,A**: Tutorial :2258, MenuController :5180, Care/Arena/Battle
controllers, HomeBuilder :2297, many tests); Model `Plot` (Tutorial :2288 uses its pivot); SpotInfo CFrames (PlotCFrame,
GateCFrame, PodiumCFrame, SpawnCFrame) are computed from constants -> a mesh swap does not move them.

### B5. Roads and gardens

| Id | Builder | What | Variants | Colour regions | Size | Runtime needs | Parts |
|---|---|---|---|---|---|---|---|
| **RopeRail** | `rail(parent,a,b,h)` :3266 | plank posts every <= 30 studs + one straight rope | length | fixed | L x 2.8 | **C** (posts + rope) | 3-6 |
| **RingStreetJunction** (x16) | `buildRoads` :3323-3382 | plank deck between two plots (2 halves x 5 planks, alternating shades, 0.1 offset) + outer/inner rope rails; rails open for spoke/garden/altar/arena docks | open/closed sides (Spoke, Garden, Altar, Arena) | fixed | ~30 x 1 x 14 | **C+Q**; Model `Junction_NN`; StormAltar.findDock raycasts the street :409 | 16-22 |
| **WoodBridge** (Spoke x6, GardenBridge x2) | `woodBridge` :3286; spokes :3385-3392; garden :3533 | longitudinal planks over the sky, edge rope rails, CloudPuffS underneath (spokes) | width 10 (spoke) / 8 (garden); length ~130 / ~45 | fixed | 10 x 3 x 130 | **C+Q** deck (TOP-0.2) | 31 / 10 |
| **GardenIsland** (Blossom, Pond) | `buildGarden` :3444, `layeredGround` :3400 | cloud island (V3), lawn + sand ring path + flowers, BlossomTree or RoundTree, FlowerBed, 2 benches, NameTag anchor, bridge | Blossom Garden / Lily Pond | fixed | ~50 dia | ground **C+Q**; cloud **C**; `NameTag` anchor (**G**); smoke_p5_world :812 centroid r test | 232 / 312 |
| **LilyPond** | `buildPond` :3425 | stone ring, deep + translucent water, lily pads, 2 blossoms, `PondSparkle` | - | fixed | 14 dia x 2 | `PondStone` **C**; water non-colliding; **L** | 44 + 1 |

## C. Storm Altar (non-creature) - src/server/Services/StormAltar.lua (`StormAltar.Build` :1293)

Model `StormAltar` (attr Phase), PrimaryPart `AltarCore` (invisible, = altar CFrame A), parented into NimbusLobby.
Site from LobbyInfo.AltarSite / AltarDock (else `fallbackSite` :341 / `findDock` :409 raycasts).

| Id | Builder | What | Variants | Colour regions | Size | Runtime needs | Parts |
|---|---|---|---|---|---|---|---|
| **StormAltarIsland** | `buildIsland` :548 (`polygon16` :438, `sculptRim` :453, `sculptBelly` :502, `collideTops` :535) | storm-blue 16-gon walking top, dark floor inside the ring, 3-row billow rim (2-stud voxels) open toward the bridge (GAP_HALF 26 deg around gapDeg), pale crowns, 3-stud voxel hanging belly | gap angle = dock bearing (data-driven, fixed for a given Config) | fixed storm navy/blue/grey bands | ~52 dia x ~20 | `WalkTop`/`Floor` **C**; rim voxels whose top reaches the deck **C+Q** (collideTops); walk test smoke_storm :571-616 needs floors within 1.6 step | 4+4+146+59 = 213 |
| **AltarStoneRing** | `buildRing` :632 | 22 charcoal stones (heights by hash) with bevel caps, stacked mounts under crystals, off-centre stacks, 3 rubble | one | fixed (3 stone greys + bevel) | 28 dia x ~3.5 | **C** stones/caps/mounts; returns `tops[]` heights the crystals stand on | 70 |
| **AltarCrystal** kit | `crystal` :592, `crystalBlock` :584, `buildCrystals` :688 | stepped diamond prisms turned 45 deg: pale Glass shell (T0.25) + Neon core; head (W3.6, with 2 side shards), medium x2, small x2, set gem (setting/rim/core) | head / medium / small / shard / gem | fixed CrystalGlass + CrystalCore neon (2 materials -> 2 MeshParts per crystal) | head 3.6 x ~11 | non-colliding; Neon names `Crystal*`/`Gem*` | 7 x 8 + 3 = 59 |
| **AltarPortalDisc** | `buildPortal` :719 | 14 rim segments + light tops, 16-gon navy disc + heart, 9 dim Neon runes | one | fixed | 15.4 dia x 1.3 | rim + `Disc` **C** | 45 |
| **AltarBridge** | `buildBridge` :795 (`lantern` :784) | stone deck slabs: level part, ramp down to the street, lip over the junction; dark beams; low parapets + caps; 2 crystal lanterns; StormPuff under the ramp | length/slope = island edge -> AltarDock (data-driven) | fixed | 8 wide x ~20-30 long | `Deck` slabs **C** (smoke_storm :888 finds parts named `Deck` and toggles one to self-test the walk); parapets **C**; model `Bridge` (**N**) | 37 |
| **StormPuff** | `stormPuff` :746 / `placePuff` :769 | small storm cloud (1.4 voxels) | - | fixed | ~9 x 4 x 6 | non-colliding | 8 |
| **AltarEntranceGate** | `buildGate` :1029 inside `buildSign` :1068 (Model `StormAltarSign`) | 2 charcoal pillars on plinths, low walls + caps, crystal tips with PointLights, light-stone lintel + poster frame + back, diamond emblems, `GatePanel` poster board | one | fixed | ~13 x 16.7 x 2 | pillars/walls/lintel **C**; `GatePanel` hosts SurfaceGui `PosterGui` with ImageLabel `StormfangArt` = Config.Art.StormfangImage (**G,N**: smoke_storm :738-750, worldtext exempts `StormAltarSign`); `TitleAnchor` invisible (**G** BillboardGui `TitleTag`) | 20 + 1 |
| (functional, keep as invisible Parts) | :1251 `AltarPrompt` (ProximityPrompt `StormAltarPrompt`, light, Attachment `PortalSparkles`), :1370 `CrystalGlow`, :1164 `ShowcaseCollider` (invisible collider cylinder around the pet), `AltarCore` | | | | | **P,L,C** | 4 |

Budget: smoke_storm checks <= 450 parts without the showcase; StormAltar.MAX_PARTS 500 :106.

## D. Obby course - src/server/Services/CourseBuilder.lua (`CourseBuilder.Build` :1993)

Course folder `Course_<Seed>` (attrs DifficultyId, Archetype) with sub-folders `Platforms`, `Hazards`, `Decor`, `Signs`,
`Tokens`, `Scenery`. All parts come from ONE factory `mk()` :186 (blk :232, ball :237 incl. SpecialMesh Sphere for
ellipsoids, cyl :253, rod :259). Decor on moving roots is welded (`ctx.Attach` "weld" -> `applyWelds` :311) or parented
under the root ("child": fades/swings with it). PART_LIMIT 2450 :44 incl. tokens; smoke_course budget
CONTRACT.v2.partBudget.course. Step geometry (Pos/Size/Yaw) comes from CourseLayout; walk tops are exact (smoke_course
:1490-1505 raycasts each step top, tolerance -0.6..+1.0).

Colour: step look = `lookFor` :480: stage theme (THEME_LOOK :125) x stage tint (STAGE_TINTS :106, 8) x difficulty trim
(Theme.World.Trim / diff.Color, 5) -> **every platform is recoloured per instance** (Top, Side, Trim, Tint) and materials
vary by theme (SmoothPlastic, WoodPlanks, Slate, Concrete). Note: SmoothPlastic / Concrete are NOT WorldStyle materials
(the course is not under the 6.4 style audit today).

| Id | Builder | What | Variants | Colour regions (R) | Size | Runtime needs | Parts |
|---|---|---|---|---|---|---|---|
| **CloudPlatform** kit | `buildBase` :617 + `addTrim` :540 + `underside` :553 + `addProp` :665 | walkable slab (main), TopPlate, 4 (or 2) trim strips, underside variant: 1 under-balls x3, 2 stalactite x3, 3 rim puffs x4-6, 4 belly x2, 5 big belly + stalactite, 0 lite; corner prop (FlowerLamp, MiniCrystal x2, MiniFlag) | any Size (layout, ~4-30 x 1-3 x 4-30); 6 underside variants; 3 props | **R** Side (slab), Top (plate), Trim, Tint (prop) | step.Size | main part named `Cloud_N`/`Step_N`/`<Kind>_N`, attrs StepIndex/Stage/StepKind (**A,N**), **C+Q**; decor non-colliding, CanQuery false | 1 + 1 + 4 + 1..7 (+0-2) |
| **BalanceBeam** | `KB.Beam` :703 | beam slab + plank seams + keel + 2 end puffs + 2 lantern posts | length | R | ~2-3 x 1 x 12-30 | main **C** | ~16 |
| **MovingCloud** | `KB.Moving` :728 | platform (lite) + 2 slide chevrons (welded) + Neon rail + 2 stops | EndOffset | R | step | main tag NC_MovingCloud, attrs EndOffset/Period (**T,A,M**: HazardService moves `part.CFrame` :630, decor welded) | ~13 |
| **VanishCloud** | `KB.Vanishing` :758 | translucent slab (T0.2) + trims + 3 cracks (children) + sparkles | - | R ghost colour | step | tag NC_VanishCloud, attrs VanishDelay/ReturnDelay; HazardService fades root + every BasePart child (`collectFadeSet` :292: an invisible root (T>0.95) is restored as T=0!) (**T,A,M**) | ~8 |
| **BouncePad** | `KB.Bounce` :783 | platform + iron skirt + tagged cylinder pad + glow disc + `PadGlyph` (SurfaceGui "▲") | pad size | R pad colour (PAD_COLORS 3) | pad 4 dia | pad tag NC_BouncePad, attrs Power/LaunchSpeed, Size tweened x1.14 on bounce (:1767) (**T,A,M,G**) | ~12 |
| **SpinBarRig** | `KB.SpinBarPlatform` :805 | platform + danger ring/floor + iron hub + 1-2 bars with Neon caps + gold stripes (welded) | count 1-2, length | fixed hazard colours | len ~6-10 | bar tag NC_SpinBar, attrs Speed/Damage, rotated by CFrame :580 (**T,A,M**), **C** | ~15-20 |
| **StormCloudRig** | `KB.StormPlatform` :832 | Slate platform + translucent damage volume (T0.8) + 4-8 dark puffs | box size | fixed | box | volume tag NC_StormCloud attr DPS, Trigger (CanTouch) (**T,A**); HazardService adds `StormRain` | ~15-20 |
| **LightningRig** | `KB.LightningPlatform` :857 | platform + per zone: invisible zone disc, Neon strike ring, scorch; 2 lightning rods (pole, base, Neon tip); 3 thunder puffs | zones 1-3 | fixed | step | zone tag NC_LightningZone attrs Damage/Interval/Warning/Radius (**T,A**) | ~20-25 |
| **PendulumRig** | `KB.PendulumPlatform` :891 | platform + swinging beam (tagged) with 3 gold stripes + weight (children) + axle, caps, 2 posts | beam size | fixed | ~8 x 6-10 | beam tag NC_Pendulum, attrs Hinge/Axis/Period/Arc/Damage; anchored children are swung by HazardService (:1063) (**T,A,M**) | ~18 |
| **WindRig** | `KB.WindPlatform` :930 | platform + invisible gust volume + 1-4 Neon wind chevrons + flag pole, flag, gold top | zone size, direction | R flag = tint | zone | volume tag NC_WindGust attrs Force/Direction/Interval/Warning (**T,A**); HazardService pools 10 `WindStreak` parts | ~15 |
| **CloudCannon** | `KB.CannonPad` :977 | iron pad (tagged) + brass disc, glow ring, core, 2 launch chevrons; barrel, breech, muzzle ring + hole, 2 bands, fuse + spark, carriage, 2 wheels + hubs; 4-7 Neon arc dots; HintTag | aim + elevation (computed per layout) | fixed | ~8 x 7 x 8 | pad tag NC_CloudCannon attrs Target/FlightTime; pad Size tweened (squash :1535) (**T,A,M,G**) | ~35 |
| **PlateBridgeRig** | `KB.PlateBridge` :1076 | landing platform + retractable span (tagged, T0.1) + Neon edges + arrow (children) + ghost rails + 2 PlateIsland platforms with PressurePlate (light, sparkles, SurfaceGui HOLD, HintTag) | span length; BridgeNumber colour | **R** BRIDGE_COLORS (4) | span ~15-19 long | span tag NC_PlateBridge, plates NC_PressurePlate attr BridgeId; plate Color restored / pressed (:1876), span faded (**T,A,M,G**) | ~40 |
| **CourseStart** | `KB.Start` :1169 + `buildBoard` :1149 | big platform, Neon start ring, START arch (2 pillars, bases, Neon caps, beam `StartBeam`, glow, 6 rainbow bunting balls), 2 InfoBoards with legs | difficulty trim | R trim | 26 x 17 x 26 | `StartBeam` + `InfoBoard` host SurfaceGuis (**G**) | ~30 |
| **CourseCheckpoint** | `KB.Checkpoint` :1204 | big platform, Neon ring + inner, 2 flag poles, Neon orb tops (lights), 2 `FlagBanner` with number SurfaceGuis, banner trims, HintTag | stage index | R tint/trim | step + 10 tall | main tag NC_Checkpoint attr CheckpointIndex (**T,A,N**: CourseInfo.Checkpoints[i].Part) | ~20 |
| **CourseFinish** | `KB.Finish` :1246 | big platform, 6 rainbow goal rings, Neon GoalOrb (light + confetti), rainbow arch 12 drums, `FinishBeam`, glow, HintTag | - | fixed rainbow | 30 x 18 x 30 | main tag NC_FinishPad (**T**) | ~30 |
| **DashHint** | `buildDashHint` :1291 | 3 Neon chevrons + shadows, brass pole, Neon beacon with HintTag | - | fixed | ~5 x 5 | non-colliding (**G**) | ~10 |
| **Landmark kit** (15 + 2) | `LM.*` :1453-1931, `buildScenery` :1933 | floating stage landmarks: CloudWindmill (~18 parts), CrystalSpires (~19), SkyBalloon (~18), RainbowArc (~100), GiantRing (~45), StormTower (~18), LightningRods (~32), LanternCluster (~38), CloudFortress (~38), KiteFlock (~41), BellTower (~18), RuneObelisk (~15), SkyGate (~27), FloatingVolcano (~14), CentralPillar (~16, Spiral only), Puff (far clouds, ~3 balls each, ~25-35 per course) | Radius/Height/Seed/Tint per item; `lite` variant past LiteCap | **R** tint (sceneryPalette :1441) | Radius 8-40, Height 20-90 (CentralPillar = course height + 56) | non-colliding, CanQuery false | 135-392 per course |
| `fallbackToken` :1330 | (tokens: TokenLook inventory) | | | | | | |

## E. Runtime / functional parts in the listed services (not "models"; keep as invisible Parts or optional meshes)

| Id | Where | What | Recommendation |
|---|---|---|---|
| PortalLockWalls | PortalService :415-450 | 5 invisible ForceField walls (collision group NC_PortalWall), shimmer when a party is on the pad | keep (invisible functional geometry) |
| PortalBillboardAnchor / CountdownFace | PortalService :669, :815 | invisible Parts carrying a BillboardGui / SurfaceGui (positions relative to Zone_Obby) | keep |
| Zone_Obby | LobbyBuilder `Gates.ObbyPortal` :2321 | invisible 14x6x14 zone part (attr PortalId) | keep |
| HazardFx | HazardService `makePart` :174 users :1128 StormRain, :1183 StrikeWarning(+Fill), :1230 BoltGlow/BoltCore (8 segments), :1253 StrikeFlash, :1265 StrikeImpact, :1454 WindDrift, :1489 WindStreak x10 | short-lived Neon VFX, tweened Size/Transparency | optional meshes later (LightningBolt, WarningRing, WindStreak); low priority |
| ShieldBubble | ItemService :158 | 8-stud ForceField ball welded to the character root, faded out | optional sphere mesh; keep primitive is acceptable VFX |
| PhoenixBurst | ItemService :229 | invisible emitter anchor | keep |
| ShowcaseAnchor | SpotService :348 | invisible anchor for the podium pet tag | keep |
| **GuideArrow** | TutorialController `buildArrowModel` :2012 (client, voxel 0.36, MaxParts 110; stepped-block fallback :2042) | golden bouncing/spinning arrow over world targets; parts[1] hosts PointLight `Glow`; per frame each part CFrame = base * offset (:2389) | **mesh** (1-2 MeshParts: Gold body + Rim); all parts must stay Anchored + CanCollide/CanTouch/CanQuery false (smoke_client :693-701) |
| GuideSparkles | TutorialController :2094 | 10 Neon 0.6 cubes floating on a ring | optional tiny gem mesh |
| TrailEnd / SignAnchor | TutorialController :2105, :2135 | invisible Beam/Billboard anchors | keep |

## F. Integration surface (who reads these models; a mesh swap must keep all of it)

Names / paths
* `workspace.NimbusLobby` + attr `PartCount` (Main.server.lua :129-142 counts BaseParts after the last gate; LoadingScreen.client.lua :409-415 progress = replicated BaseParts / PartCount).
* `NimbusLobby.Gates` / `Portal_<Id>` (+attrs GateId, Glyph, PartyCount/PartyMax/Countdown): PortalService (via LobbyInfo.Portals.Obby), ObbyController `H.portal` :234, TutorialController :2311, DungeonController, ArenaController, DungeonBuilder :1197, BattleService :2709, dump_model :1287/:1434, tests smoke_p5_world :740-748, smoke_polish_portals, smoke_polish_worldtext :722, smoke_p3_ui/visual/arenaworld, smoke_p4_*.
* Gate internals: `Lintel` (PrimaryPart, GateTag adornee), `GateTag` BillboardGui -> `Plate`/`Title`/`Info`/`Pill`/`Label`; `PromptAnchor`; `Pad`/`Step`; `PortalDisc` (light+sparkles; test: Neon, T0.35); `PortalShimmer` (ForceField); `Emblem` (test: #cells == glyph rects, all Neon in the disc colour); `PadGlyph`, `PadBorder1..4` (test: 4 Marble + >= 3 Neon); gate <= 120 parts (smoke_p5_world :690).
* `Roulette_<Id>` (+ PromptPart, PriceAnchor/PriceBillboard): PetService prompts, TutorialController :2319 (bounding box incl. the invisible PriceAnchor), tests.
* `ItemShop` (+ PromptPart, ItemShopBillboard): ItemService, tests.
* `Spot_NN` (attr SpotIndex), `Plot`, `Podium`/`Accent`, `NumberSign`, `NameplateAnchor`/`Nameplate` (Avatar, Headshot, Silhouette, FreeIcon, NumberBadge; attrs OwnedColor/FreeColor): SpotService :216-262, HomeBuilder :2294-2297, Tutorial, Menu/Care/Arena/Battle controllers, tests (worldtext :491, p5_world spot ring).
* `LampGlass` (PointLight host, internal), `Fountain`/`Spray`, `Gardens/Garden_*`, `Courts`/`GateCourtDecor` (dump_model :1261-1264 crop).
* StormAltar: model `StormAltar`, `StormAltarSign` (poster image + text test), `Bridge` + `Deck` slabs (walk self-test), `StormfangShowcase`, `AltarPrompt`/`StormAltarPrompt`, StormAltar.GetCFrame/GetLanding (GateService teleports).
* Course: folder sub-groups, main step part names + attrs StepIndex/Stage/StepKind, Config.Tags on hazards with their attributes (Config.lua :45-62), CourseInfo.Checkpoints[i].Part / Finish / StartCFrame; HazardService `Attach` (GetTagged under the container :1949).

Behaviour the meshes must preserve
* Walkable surfaces: exact top heights (lobby walk height = Config.Lobby.Origin.Y; layers -0.4..+0.1), CanCollide + CanQuery, and the right Material on lawn (NPC spots test).
* Raycasters: NpcService :192 (NPC pedestal heights), StormAltar `groundAt`/`findDock` :395-436, smoke_p5_world `groundAt`, smoke_storm walk (RespectCanCollide), smoke_course step tops, StormAltar `obstacleBoxes` :304 (bounding boxes of visible lobby parts).
* Tags: NC_Detail (GraphicsQuality.lua :28 moves tagged models out on Low), NC_StyleExempt (clouds, pets; style audit skip), Config.Tags on course parts.
* Style audit (smoke_p5_world `styleAudit` :64): every visible non-exempt part uses a WorldStyle material, no SmoothPlastic > 2 studs, saturation/value limits on faces > 16 studs^2, parts < 4 studs cast no shadow, <= 12 shadow lights, lobby <= 8000 parts.

---------------------------------------------------------------------------------------------------------------------

## G. Integration note: the seam for `MeshLibrary.Get(id)`

### Proposed module (new, shared): `src/shared/MeshLibrary.lua`
```
MeshLibrary.Get(id) -> Model | nil        -- a FRESH CLONE of the mesh template built at the origin (pivot = the same
                                           -- origin the Part builder uses), or nil when Config.Meshes[id] is unset,
                                           -- the asset failed to load, or the layout signature does not match
MeshLibrary.Place(id, cf, parent, name) -> Model | nil   -- Get + PivotTo(cf) + Parent (the place() contract)
MeshLibrary.Preload(ids)                  -- server, once in Main before LobbyBuilder.Build: loads every set id
MeshLibrary.Has(id) -> bool
MeshLibrary._SetTemplate(id, model)       -- test hook: smoke tests inject a fake MeshPart model to exercise the mesh path
Config.Meshes = { [id] = { Asset = 123, Signature = "lobby:<hash>" | nil } }   -- "Mesh asset ids live in Config" (ART RULE)
```
Loading: an FBX uploaded through Open Cloud (Assets API, assetType Model) becomes a Model asset whose children are
MeshParts; `InsertService:LoadAsset(id)` on the server (assets owned by ROBLOX_CREATOR_ID = the experience owner) gives
fully cooked MeshParts (render + collision data). Scripts CANNOT set `MeshPart.MeshId` at runtime, so "Instance.new
MeshPart + MeshId" is not an option (the mock allows it, real Roblox does not); `AssetService:CreateMeshPartAsync` is
the alternative for single meshes (needs a Mesh asset id, works on the client too). LoadAsset yields: do all loads in
`Preload` with a timeout before the world builders run; anything that is not ready -> nil -> today's Part build.

### Where it plugs in (smallest seams, each already wrapped in pcall + fallback)
1. **LobbyBuilder `template(name, make)` :877** - ONE line covers every cloned prop: Tree<Kind>, Lamp, Bench,
   FlowerBed<v>, Puff<S|M>, Plot, Sky<Big|Small>. `local mesh = MeshLibrary.Get(name); if mesh then templates[name] =
   mesh ... else make()`. `place()` :860 already transforms every BasePart by `cf * d.CFrame`, so a MeshPart template
   built at the origin works unchanged. The mesh model must keep the child names others use (`LampGlass`, `Podium` +
   `Accent`) and the template's pivot conventions (Lamp/Tree at ground, Plot in plot-local space, Puff at its top).
2. **Per-object builders that already have a Part fallback**: `Gates.BuildOne` :2291 (or inside
   `WorldStyle.BuildGate` :434 so Arena/Dungeon gates follow), `buildMachine` :2489 (recolour mesh parts by name with
   `machinePalette(roulette)`), `buildItemStall` :2547, `buildSpot` :3176 (Plot via template), `buildShop` :2700.
   Pattern: `local m = MeshLibrary.Place(id, cf, parent, "Roulette_" .. id)`; then the SAME code that today adds the
   invisible functional parts (PromptPart, PriceAnchor, DomeGlow, SignAnchor, PromptAnchor, Zone_Obby, NameplateAnchor)
   and GUIs runs on top of the mesh model. These functional parts are not art and stay plain invisible Parts.
3. **One-off decor**: `buildFountain` :1633, `buildTokenStatue` :2667, `Court.WelcomeArch` :1945, `Court.Obelisk` :1992,
   `noticeBoard` :1170 (keep `Face` as a flat SurfaceGui carrier: either a named MeshPart face plate or an invisible
   Part in front of the mesh), `bannerPole` :1159, shop arch :2835, `buildPond` :3425: each gets a 3-line
   `MeshLibrary.Place(...) or <old code>` guard.
4. **Layout-baked ground** (PlazaGround, Courts, CircleWalk, PlazaEdges, PlazaCloud, ShopIsland ground/cloud, garden
   islands, roads, plot islands): seam = the existing `section()`/pcall calls in `buildPlaza` :2212, `buildShop`,
   `buildRoads` :3323, `buildGarden` :3444. The geometry is a pure function of Config.Lobby -> the Blender job should
   be fed by `tools/dump_model.lua lobby` JSON (every Part's CFrame/Size/Material/Color) so meshes match today's walk
   heights and collision exactly. Store a layout signature (hash of Config.Lobby + GATE_SPECS + SpotCount) in
   Config.Meshes[id].Signature; `Get` returns nil on mismatch so a Config change never shows a stale mesh.
5. **StormAltar**: each piece is already a `section(name, fn)` :1336-1374 -> guard `buildIsland` :548, `buildRing` :632,
   `buildPortal` :719, `buildCrystals` :688, `buildGate` :1029; the bridge :795 is data-driven (length/slope) -> kit
   meshes (DeckSlab, Parapet, Lantern, StormPuff) placed by the existing code; keep the `Deck` name per slab.
6. **CourseBuilder**: the factory `mk()` :186 is the wrong level (it would only reproduce primitives). Seams:
   `buildBase` :617 (CloudPlatform kit: one MeshPart slab with Box collision sized to step.Size + separate
   decor meshes), each `KB.<Kind>` (hazard rigs: the tagged moving/faded part must remain THE main/tagged part with
   its attributes; decor meshes welded/childed with the same ctx.Attach rules), `LM.<Type>` :1453+ (landmarks: one
   mesh per type, scaled by Radius/Height, tinted per stage).
7. **TutorialController `buildArrowModel` :2012**: client side; `AssetService:CreateMeshPartAsync` or a mesh template
   replicated in ReplicatedStorage by the server's Preload (client cannot LoadAsset).

### Colour strategy that keeps runtime recolours and the style tests working
* Split every mesh by colour/material REGION into separate untextured MeshParts named by region (`Body`, `Seg1`,
  `Knob`, `Egg1..4`, `Accent`, `Cloth`, `Glass`, `Trim`...), then set `.Color`/`.Material` from the existing Lua
  palettes after cloning. MeshPart.Color is ignored once a TextureID / SurfaceAppearance is applied, so recolourable
  regions must stay untextured (or use SurfaceAppearance AlphaMode Overlay). World props then still pass the 6.4
  material/saturation audit unchanged, and the per-roulette / per-plot / per-gate / per-stage recolours stay one loop.
* Baked textures only for organic fixed-colour things (clouds, trees) - and tag them NC_StyleExempt (the audit reads
  `.Color`, which a texture ignores).

### Risks
1. **Tests pin the Part build**: smoke_p5_world gate checks (Emblem cell count == glyph rects, 4 Marble PadBorders,
   Pad 14x0.6x14 Slate, PortalDisc Neon T0.35, PortalShimmer ForceField, <= 120 parts), smoke_storm `Deck` slabs and
   the walk self-test, smoke_course step-top raycasts, worldtext SurfaceGui census (SignGui x5, NumberSign faces).
   With no ids set, `Get` returns nil -> fallback -> green; but the mock cannot LoadAsset, so the mesh path is never
   exercised unless tests inject templates through a hook and the assertions learn a mesh branch.
2. **Mock vs real**: robloxmock treats MeshPart as a box (raycasts, bounds) and lets scripts set MeshId; real Roblox
   forbids runtime MeshId and raycasts hit the cooked collision mesh. A cloud island whose box top is above the walk
   surface passes in the mock and fails (or vice versa) in the real game. CollisionFidelity cannot be changed from a
   script either: walk surfaces need Box/PreciseConvexDecomposition chosen at import (or invisible box collider
   Parts, see 4).
3. **render_model.py cannot draw meshes** (it rasterises Part boxes/wedges/cylinders): the visual review loop needs a
   mesh-aware renderer (load the FBX/OBJ the id came from) before the art passes can continue.
4. **VanishCloud restore bug**: HazardService `collectFadeSet` :292 turns an invisible root (T > 0.95) into T = 0 after
   a vanish cycle; if a course step uses an invisible collider + visual mesh, the collider becomes a visible grey box.
   Keep the visible mesh as the tagged root (Box collision) or teach collectFadeSet about colliders.
5. **Moving/tweened hazards**: SpinBar / Pendulum / MovingCloud move by CFrame and BouncePad / CloudCannon tween
   `Size` (a MeshPart scales its mesh: OK), PressurePlate sets `.Color` (needs untextured MeshPart). Pendulum children
   must stay Anchored children (HazardService swings anchored descendants), MovingCloud/SpinBar decor stays welded.
6. **Data-driven geometry**: course steps have arbitrary Size (non-uniform scaling distorts puffy edges: use slabs that
   tolerate stretching or size buckets); bridges/rails/junction rails have computed lengths; the altar rim gap angle
   and the bridge ramp depend on AltarDock; lobby ground depends on Config.Lobby. Either bake per layout with a
   signature check or keep code-placed kit pieces.
7. **Triangle / size limits**: 20k triangles and 2048 studs per mesh; the 312-stud plaza ground + 318-stud cloud need
   splitting into sectors/material layers; precise collision on big meshes is costly -> per-sector meshes.
8. **Load timing**: LoadAsset yields; Main builds the lobby at boot and NimbusLobby.PartCount drives the client loading
   bar by BaseParts only (mesh geometry streams later): add ContentProvider:PreloadAsync on the mesh ids in the
   LoadingScreen, and a server Preload timeout so a slow asset never blocks spawning (fallback Parts instead).
9. **Ownership / permissions**: LoadAsset only works for assets owned by the experience's creator (user or group =
   ROBLOX_CREATOR_ID); a moderated/pending asset returns an error -> must fall back silently per id.
10. **NC_Detail / Low graphics**: mesh models must carry the same tags at the same level (WalkHedges, GateCourtDecor,
   LawnDecor) or Low graphics stops hiding them; hedges in NC_Detail are collidable today (client-only removal).
