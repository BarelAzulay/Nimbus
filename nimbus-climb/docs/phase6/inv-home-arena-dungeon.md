# Phase 6 inventory: homes, arena, dungeon (inv-home-arena-dungeon)

Scope: `src/server/Services/HomeBuilder.lua`, `TycoonService` / `TycoonCatalog` (stations + decor),
`src/client/Controllers/HomePortalFx.lua`, `HomeFx.lua` (non-pet parts), `FusionController.lua`,
`src/server/Services/ArenaBuilder.lua`, `src/server/Services/DungeonBuilder.lua`, `DungeonController.lua`.
Read-only survey of `/home/user/roblox/nimbus-climb` (branch v3-phase5). All paths below are repo-relative.

Part counts were measured with the real builders, not estimated:
`python3 tools/render_model.py <target> --json ... --dump-only` (dumps in `dumps/`, per-level station dumps in
`dumps/lv/`, the grouping script is `summarize.py`, all in this folder). Sizes are axis-aligned bounding boxes in
studs (W x H x D, front = -Z).

Legend for "runtime needs":
**C** = CanCollide / walkable parts, **A** = Attachments other code reads, **P** = ProximityPrompts,
**N** = names other code finds (FindFirstChild / `.Name ==`), **At** = attributes on the model / parts,
**G** = Billboard / SurfaceGuis carried by a part, **L** = lights / particles / Fire carried by a part,
**M** = moving sub-parts (client animation), **R** = runtime recolour.

Colour: unless a row says **R**, every colour is fixed at build time (stations take no player / pet colour: the
`accent` argument of `stationTemplate` is passed but no art function uses it). There are **no pet
Primary/Secondary/Eye colour regions** in this scope. The only runtime-recoloured regions are: pad state glow,
ghost hologram, home portal player colour, arena element colours (seats, banners, flames, wheel), duel ring accent,
and the dungeon floor element (`Accent`-tagged parts).

---------------------------------------------------------------------------------------------------------------------

## A. Home stations (server, `HomeBuilder.lua`)

Pipeline (the seam, see section G): `Art.<Kind>(def, level[, open])` builds a template once per server
(`stationTemplate`, HomeBuilder.lua:2077, cache key `<Id>:<level>[:<open>]`) -> `Kit.finish` (art-rule guard,
:736) -> `PrimaryPart = biggestPart` -> `placeStation` (:2591) clones it with `cloneAt` (:786) to
`PlotCFrame * def.Slot.CFrame`, names it `Station_<Id>`, writes attributes `StationId, Level, Kind, BuiltAt`, every
`tpl.Points` as a world-space Vector3 attribute and every `tpl.Info` value, then `applyOwnerAttr` (OwnerUserId on
every prompt) and `afterPlace` (Garden prompts / Training mats). Slots come from `TycoonCatalog.Stations`
(TycoonCatalog.lua:374-512). All station parts go through `Voxel.Box` / `Kit.p / ball / cyl / cylAt / wedge / gable /
window / lantern / corner(s)` (HomeBuilder.lua:563-704). Pure decor sits in sub-models tagged `NC_Detail`.

| Id | Builder (file:line) | What | Variants | Parts today | Size (studs) | Runtime needs |
|---|---|---|---|---|---|---|
| **HomeBerryFarm** (`Station_Press1`) | `Art.Farm` HomeBuilder.lua:882 (+`Farm.bush` :871, `Farm.age` :866) | terraced berry field: slate plinth, 3 soil rows in a plank frame, red-berry bushes (L1-10), blue (L11-22), golden trellis + vines + gold berries (L23-37), sapling (L30-37), glowing Starberry tree (L38-40), red barn with gable roof, door, loft door, sign board, crates | 40 levels; plants grow with `Farm.age` (bush diameter, 1-2 berries, vine height); rows switch Grass -> Soil when planted; lantern from L10; crates 1/2/3 at L1/11/23; tree 3 stages | L1 30, L10 57, L22 95, L37 139, L40 145 (budget 150) | 38.8 x 7.9 (10.9 with tree) x 7.8 | C: Plinth, Soil/Grass rows, front+back Frame, FrameEnd, Mound, BarnPlinth, Barn. G: `FarmSign` billboard on `SignBoard` (Title "Berry Farm Lv N", HomeFx/smoke_p5_home read it). At: `BerryPoint` (top planted row, HomeFx berry flights start), Info `Rows`. L: PointLight + `Sparkle` emitter on first Starberry at L40, barn lantern. N (tests smoke_p2_visual): `Berry`, `GoldBerry`, `Starberry`, `Barn` (WoodPlanks), `Crates` detail model |
| **HomePetGarden** (`Station_Garden`) | `Art.Garden` :1078 (+`Garden.bedFrame` :1042, `promptPoint` :1055, `closedSign` :1065) | fenced lawn: cobble kerb ring + rail + 7 posts, entrance posts (arch from L3), cobble walk, Food Bowl (slate basin, marble rim, berries), 12 beds: OPEN = bed + cushion (4 jittered colours) + headboard + lean-to roof; CLOSED = soil + Stem + Sprout + `ClosedSign` board | level 1-8 (flower strips L2/L5, arch+garland L3, lanterns L4/L6, bunting L7, gold rails + sparkle L8) x open beds 0..12 (`Garden:<lvl>:<open>`, open = 3 + prestige stars) | L1/3 open 74, L8/12 open 94 (budget 95) | 22.8 x 6.3 x 20.7 | C: Lawn (top y 0.2, hard-coded in HomeFx `R.ground` HomeFx.lua:2225 and HomeRoam), Kerb, Rail, Post, EntrancePost, Walk, FoodBowl, BowlRim, Bed, SoilBed. A on part `Lawn`: `Spot1..12` (attrs Slot, Open; HomeFx seats pets, tests check positions) and `PromptPoint<i>` (open beds) carrying P `GardenSpotPrompt` (attrs Slot, StationId, OwnerUserId; `Enabled` driven by `Garden.applyPrompts` :2534; CareController.lua:2518 opens on it). G: `BowlSign` on `FoodBowl`, `ClosedGui` SurfaceGui on each `ClosedSign`. At: `BowlCenter`, Info `Open` (HomeFx reads `Open`). Interior must stay clear (HomeRoam walk plan). N tests: `Cushion`, `BedRoof`, `Stem`, `Sprout`, `Spot<i>` |
| **HomeFoodMachine** (`Station_Kitchen`) | `Art.FoodMachine` :1217 | wooden cabinet with iron bands on a plinth, glass `Hopper` of berries on a copper funnel, dispenser mouth + chute + tray, red FEED button, Berry Basket; L2 lamps, L3 press barrel + pipe, L4 shelf of bowls, L5 brass trims + bell + sparkle | 5 levels (cabinet half-width 2.6..3.4, top 4.2..5.0, hopper 2.4/2.8 wide, gold at L5) | L1 28, L3 37, L5 42 (budget 55) | 6.6-10.7 x 7.9-10.2 x 6.4 | **N `Hopper`** (exactly one glass part, transparent 0.2-0.9, upper half; PetCareService.lua:1604 puts `FeedPrompt` on it via `Care.anchorOf` :1563; smoke_p2_homeworld :342 and smoke_p4_care check it; `HopperBerries` must sit inside it, smoke_p2_visual :287). G: `MachineSign` billboard on `Cabinet` with TextLabel **`BasketLine`** (HomeFx.lua:3111 rewrites it). At: `ChuteMouth`, `Tray`, `HopperTop`, `BasketTop` (HomeFx berry flight target). C: Plinth, Cabinet, Cornice, Tray, PressBarrel, Shelf. N: `Button` (Neon) |
| **HomeTrainingPlace** (`Station_Gym`) | `Art.Training` :1316 | wooden deck on a plinth with brick (gold L5) kerb and back rail, weight rack + bar, hurdles (L2), orb pedestal (L3), shield wall (L4), scoreboard + trophy (L5), pennants (L3+), up to 5 mats | 5 levels (width 9/12/15/18/18, mats = level) | L1 12, L3 30, L5 47 (budget 90) | 9-18 x 3.3-6.0 x 9 | **A `Spot1..5`** on part `Deck` (attr Slot; `Garden.applyTraining` :2557 writes Busy / Key / Stat / Ends; HomeFx poses pets + props there). **P `TrainPrompt`** is put by PetCareService on the model's *biggest part* (anchorName nil, PetCareService.lua:1605) - changes if the art becomes one mesh. C: Plinth, Deck, Kerb, BackRail, Rack, Pedestal, ShieldWall, TrophyStand |
| **HomeVault** (`Station_Vault`) | `Art.Vault` :1414 | slate strongroom with marble cornice, round iron door with gold hub + spokes; L2 pilasters + band, L3 glass gem case with neon gems, L4 coin stacks, L5 gold crown + sparkle | 5 levels | L1 21, L5 41 | 6.6 x 5.4-8.9 x 8.1 | C: Plinth, Step, Vault, Cornice. L: Sparkle emitter on Cornice (L5). No prompts / points |
| **HomeHouse** (`Station_House`) | `Art.House` :1793 -> `House.cottage` :1645, `villa` :1665, `manor` :1695, `castle` :1735 (+`House.block/windows/door/chimney` :1623-1640) | the player's house, 4 tiers | Cottage (L1), Villa (L2), Manor (L3), Sky Castle (L4) - 4 distinct meshes | 35 / 67 / 104 / 107 (budget 150) | 13.8x9.9x11.3 / 19.2x14.3x15.5 / 33.2x16.7x17.6 / 33.3x24.5x15.9 | C: plinths, walls, steps, porch. At: `RoofTop` point, Info `Tier`. L: lanterns, window glass. N tests (smoke_p2_visual :244-312): ClayRoofTiles roof, `Window` Glass, `Plinth` Slate, `Spire`, `RoseWindow`, `HouseDecor` detail |
| **HomeFusionMachine** (`Station_FusionMachine`) | `Art.Fusion` :1488 | octagonal marble deck with violet neon inlay, 2 glass input pods with neon cores + copper pipes, tall glass chamber with marble ribs and crown, crystal on top, output dome; L3 neon shards | 3 levels (gold trim L2+, golden crystal / heart L3, shards L3) | L1 32, L3 38 (budget 90) | 8.6 x 13.1 x 10.5 | **M: child Model `Swirl`** (2 cloud balls + neon `Heart`, >= 3 parts) that HomeFx spins around `SwirlCenter` (HomeFx.lua:3801; HomePortalFx unrelated). **A `PromptPoint`** on part `Deck` carries **P `FusionPrompt`** (FusionController.lua:661 reads `prompt.Parent.WorldPosition` for the burst; `FindFirstAncestor("Station_FusionMachine")` :2313). A `ChamberLight` (PointLight). At `SwirlCenter`. N tests: `Pod` x2, `Chamber`, `OutputDome`, `ChamberInlay` (Neon >= 3), `Shard` x2 at L3 |
| **HomeArenaGate** (`Station_ArenaGate`) | `Art.ArenaGate` :1569 | two marble columns on plinths with banners and braziers, slate lintel with medallion + crossed swords, red neon inlay frame, red neon `Portal` disc + ForceField `Shimmer`, threshold | 1 level | 27 | 12.5 x 11.9 x 3.2 | **A `PromptPoint`** on part `Portal` carries **P `ArenaGatePrompt`** (attr Teleport = "Arena"; ArenaBuilder teleports). C: Plinth, Column, Lintel, Threshold. L: PointLight on Fire |
| **HomeYardFence** (`Station_DecorFence`, Perimeter, plot frame) | `Art.Fence` :1887 (+`Fence.runs` :1820, `seg` :1833, `points` :1842, `flowers` :1860, `banner` :1876) | yard edge, open at the gate: L1 whitewashed pickets + rail + posts + tulip boxes; L2 brick kerb + hedge + brick pillars + cloth banners + tulips; L3 cloudstone wall (slate base, marble wall + cap), marble pillars with cloud puffs (`CloudPuffs`, NC_StyleExempt), royal banners, glowing starflowers, crystal lanterns | 3 levels; lengths from `PlotSize` (72) -> **kit** of segment pieces, not one mesh | 55 / 71 / 79 (budget 90) | 71 x 2.3-6.6 x 71 | C: Pickets, Post, Kerb, Hedge, WallBase, Wall, Pillar. Must fit inside the lobby's own fence posts (abs x/z >= 35.5) and outside the Garden (x 34) |
| **HomeFountain** (`Station_DecorFountain`) | `Art.Fountain` :1949 | marble basin on a slate plinth, water disc, 1-3 tiers, splash particles, lanterns round it (wood 4 / brass 6 / crystal 8, from `def.Effects[level]`), cloud + crystal at L3 | 3 levels | 19 / ~29 / 39 (budget 80) | 9.1 x 8.7-12.4 x 8.4 | C: Plinth, Basin, BasinFoot. L: `Splash` ParticleEmitter on an Attachment, lantern PointLights. Water: Glass, transparent 0.2 |
| **HomePetPodium** (`Station_DecorPodium`) | `Art.Podium` :2013 | slate stage + marble step ring, 4 corner posts with lanterns (L1) / marble pillars + gold caps (L2) / short pillars + crystals (L3), gold collars + carpet (L2+) | 3 levels | 17 / ~20 / 22 | 8 x 3.3-4.2 x 8.8 | C: Stage, Step |
| HomeStationFallback | `fallbackTemplate` :2051 | one slate block of the footprint when an art function errors | - | 1 | footprint | keep as Part (it is the fallback's fallback) |

### A2. Home plot pieces (server, `HomeBuilder.lua`)

| Id | Builder | What | Variants | Parts | Size | Runtime needs |
|---|---|---|---|---|---|---|
| **HomeBuyPad** (`Pads/Pad_<StationId>`) | `padTemplate(state)` :2139, placed by `updatePad` :2799 | stone base, glowing plate, 2-part neon emblem (+, arrow, padlock, star) | 4 states Build / Upgrade / Locked / Prestige (emblem shape + glow colour `PAD_COLORS` :2116) | 4 | 4 x 0.6 x 4 (`TycoonCatalog.Layout.PadSize`) | C: `Base` (walkable) carries **P `BuyPrompt`** (attrs StationId, OwnerUserId) and **G `PadSign`** billboard. **N `Glow`** (HomeFx.lua:1306 / :3813 pulses + dims its Transparency, tests :1239 / :1507). R: Glow colour per state (and HomeFx dim). At on model: StationId, OwnerUserId, NextLevel, Level, Price, Locked, Title, LevelText, Kind, BuiltAt (HomeFx listens to Price / Locked) |
| **HomeStationGhost** (`Ghost_<Id>`) | `ghostFor` :2756 | hologram of a station that unlocks later: the level-1 template, only its 12 biggest parts, recoloured `C.Ghost`, ForceField, transparency 0.3, no collisions, prompts / lights / guis removed | per station | <= 12 | as station L1 | R: whole model ForceField + ghost colour. Attr StationId. Tests: <= 12 parts, no BuyPrompt, not solid. A mesh station makes this trivially 1-3 MeshParts |
| **HomeClaimSign** (`Spot_NN/ClaimGate/ClaimSign`) | `buildClaimSign` :2223 | "FREE HOME / Press E at the gate" signpost on the verge (post + board) | - | 2 (+ optional invisible `ClaimAnchor` :2341) | 7 x 5.2 x 0.6 | G: `ClaimGui` SurfaceGui (Back face, 50 px/stud). C: Post, Board. The `ClaimPrompt` rides Attachment `ClaimPoint` on the lobby's own gate part (`GateBeam/GateBase/GatePillar`, `gateHolder` :2251) - lobby part, not ours. Test: free plot adds <= 3 parts |
| **HomeYardPaths** (`Home/Paths`) | `pathTemplate` :2366 | the yard's cobble paths: one merged voxel layer of `TycoonCatalog.Layout.Paths` + one slate border slab per path | one layout (data-driven; changes only if the catalog layout changes) | 27 | 61.4 x 1.0 x 54.3 | C + CanQuery (walkable). Built only while owned (`setPaths` :2428) |
| **HomeHouseLot** (`Home/HouseLot`) | `lotTemplate` :2446 | 4 stakes, 4 strings, 2 plank piles, 2 brick stacks where the house will stand | - | 12 | 24 x 1.6 x 14.5 | no collisions. N tests (smoke_p2_visual): `HouseLot`, `Stake`, `String` |

### A3. Not in this scope but on the home plot (for the lead)
`Plot` (island cloud 56, fence posts / rails, street, yard, gate, podium base = 106 parts), mailbox / number sign /
gate banners (5 parts) are built by `LobbyBuilder` (homeplot dump: `dumps/homeplot_SkyCastle_pads.json`, total 823
parts of which `Home` = 712). The ClaimPrompt anchors onto LobbyBuilder's `GateBeam/GateBase/GatePillar` parts by
name, so renaming those in a LobbyBuilder mesh swap breaks the claim prompt placement (falls back to an invisible
`ClaimAnchor`).

### A4. TycoonService / TycoonCatalog
* `TycoonCatalog` holds data only: station defs, `Slot.CFrame / Footprint / Pad / Beds / Bowl / Fence / Entrance /
  Spots`, `Layout.Paths`, `Layout.PadSize`, `Effects[level].Lanterns/LanternStyle` (Fountain). These numbers are the
  geometry contract the meshes must respect (footprints, bed positions, bowl radius, lawn top 0.2, pad size).
  TycoonCatalog.lua:256-512.
* `TycoonService.ensureClaimPrompt` TycoonService.lua:1399-1434 makes an invisible 1x1 `ClaimAnchor` Part only when
  HomeBuilder built no ClaimPrompt. Not visual: **keep as Part**. TycoonService otherwise only reads
  `ClaimPrompt` / `BuyPrompt` by name (:1388, :2692, :2700).

---------------------------------------------------------------------------------------------------------------------

## B. Home client effects (client-only parts, never replicated)

| Id | Builder (file:line) | What | Variants | Parts | Size | Runtime needs |
|---|---|---|---|---|---|---|
| **HomeWelcomeHeap** | `G.buildHeap` HomeFx.lua:1914 (`G.HEAP_W` :1703) | Welcome-back pile: gold core + top + 46 rainbow coins in a golden-angle dome | own / dimmed (`Wd`: grey mix 0.55 + transparency 0.3) | 48 | 2 x 1.7 x 2 | pooled clone; attrs `Lift`, `Top`; R: dim variant. Test: <= 60 parts |
| **HomeTrainProp_Speed** (treadmill) | `G.PROPS.Speed` HomeFx.lua:3149, built by `G.takeProp` :3185, animated `G.stepProp` :3225 | deck, belt, 2 stripes, 2 posts, console, neon screen | - | 8 | 1.7 x 1.5 x 2.3 | **M**: `Belt` / `Belt2` stripes scroll. Placed at the mat Attachment `Spot<i>`. Test: 3-12 parts |
| **HomeTrainProp_Physique** (dumbbell) | `G.PROPS.Physique` :3159 | bar, grip, 4 plates, rack | - | 8 | 2 x 0.7 x 1.5 | **M**: 6 parts in group `Lift` move up / down together |
| **HomeTrainProp_Ability** (orb) | `G.PROPS.Ability` :3169 | 2 neon runes, core, shell, 3 sparks | - | 7 | 2 x 0.8 x 2 | **M**: `Orb` bobs, `Shell` spins, `Spark1..3` orbit independently |
| **HomeTrainProp_Defense** (dummy) | `G.PROPS.Defense` :3177 | base, post, body, rope, head, shield, boss | - | 7 | 0.8 x 2 x 0.8 | **M**: 5 parts in group `Wobble` rock together |
| **HomeZzz** | `G.takeZzz` :1981 | two voxel "Z" letters (3 bars each) over a napping pet | - | 6 | 0.9 x 1.3 x 0.1 | **M** bob (`G.stepZzz` :2151); pooled |
| **HomeBit** (berry / puff cube) | `R.takeBit` :2767, `R.puff` :2790, berries `R.stepBerries` :3070 | one pooled 0.4 / 0.34 cube: berries flying Farm -> Bowl / Basket, 3-cube poop puffs | **R**: berry colour by farm level (`R.berryColor` :3061), puff colour, size | 1 each (<= 16 alive) | 0.4 | tweened CFrame; a generic small mesh (berry) recoloured per use, or keep as a VFX Part (see risks) |
| **HomeScoopRing** | `G.stepRing` :3302 | 16 neon dashes on the ground showing the owner's scoop radius | radius from `TycoonCatalog.ScoopRadius` (segments resized) | 16 | 2r x 0.06 x 2r | **M**: follows the player every frame; dynamic segment length -> keep as VFX Parts or one ring mesh scaled uniformly |
| (consumer) Cloud Cash coin | `R.takeCash` :2619 -> `TokenLook.Build{Palette = Cash/GoldenCash, Scale}` | the coin a pet poops; TokenLook's model (owned by the token inventory) | 4 stage scales, Lucky (gold + sparkles), dimmed | 6 | ~0.8-1.3 | bob / spin (`TokenLook.Motion`), fades every piece's Transparency, zips to player. Test: a coin = 6 TokenLook parts |
| (behaviour) station pop-in | `startPop` HomeFx.lua:1157 / `finishPop` :1199 | not a model: every visible BasePart of a new `Station_*` / `Pad_*` springs up bottom-to-top (CFrame, Size, Transparency per part), then is restored exactly | - | - | - | With meshes the pop just animates fewer, bigger pieces - works unchanged, looks coarser (a one-mesh station pops as one block) |
| **HomePortal** | `P.build` HomePortalFx.lua:166, `P.place` :266, `P.step` :404 | the player's 10 s home portal: standing ring of 20 voxel blocks, 2 crossed neon surfaces, 3 swirl arms, stone base, neon sill, sparkles, name tag "Alex's portal" | **R**: player colour from `PALETTE` (6) by UserId: ring alternates colour / lighten, every 5th block gold; surfaces darken; other players' portals faded +0.55 | 27 | 5.8 x 5.9 x 1.4 | **M**: whole portal scales 0->1 on open / 1->0 on close (`Size * s` and positions * s per part), 3 `Swirl` arms rotate every frame, Transparency fades. G: `PortalName` billboard. L: `Sparkles` emitter. No collisions. Test smoke_p4_portal counts parts (`countParts`) |
| **HomePortalArrival** | `P.arrive` HomePortalFx.lua:338, `P.stepArrival` :378 | arrival ring around the feet: 14 neon blocks + 6 sparks, widens + fades in 1.5 s | **R** player colour / gold | 20 | ~5 dia | **M** expanding ring, rising sparks |
| **FusionBurst** | `machineBurst` FusionController.lua:1588 | 10 neon cubes (`FusionSpark`) + a neon ball (`FusionFlash` + PointLight) from the machine's output point | **R** result rarity colour | 11 | 0.4 cubes, flash 1 -> 5 | tweened, Debris 0.9 s. Pure VFX: keep Parts or a spark mesh; the window's pet previews are PetBuilder ViewportFrames (pet inventory) |

---------------------------------------------------------------------------------------------------------------------

## C. Battle Arena (server, `ArenaBuilder.lua`; `workspace.BattleArena`, 2708 parts, budget 2800)

Pipeline: `ArenaBuilder.Build` :3242 runs sections (`buildCloud`, `buildGround`, `buildColosseum`, `buildGateSign`,
`makeZone`, `buildRing` x2, `buildEventBoard`, `buildLeaderboard`, `buildForumDecor`, `buildBridge`,
`Ring.buildPortal`, `Gates.buildArena`, `Gates.buildReturn`), then `Art.enforce` (:1213, attribute `ArtFixes`).
Reusable templates are cached locals reset per Build (`segTemplates`, `pillarTemplate`, `ringPostTemplate`,
`emblemTemplates`, `torchTemplate`, `planterTemplate`) and cloned by `place(tpl, cf, parent, name)` (:413);
element recolours go through `recolor(root, partName, color)` (:433). The island frame `A` is computed at runtime
from the lobby (arena ray + distance), so everything is placed relative to `A`.

| Id | Builder (file:line) | What | Variants | Parts | Size | Runtime needs |
|---|---|---|---|---|---|---|
| **ArenaIslandCloud** | `buildCloud` :1262 (`cloudGrid` :548, `Art.shadeCloud` :1194) | the island's big puffy voxel cloud under forum + colosseum | 1 (seeded) | 389 | 352 x 52 x 295 | C (Collide true, walk-under / edges); tag NC_StyleExempt; N test `IslandCloud` (smoke_p3_arenaworld :1105). Split into a few chunk meshes (one mesh this size will be over the import limits / one huge convex hull) |
| **ArenaForumGround** (kit) | `buildGround` :1354 | forum floor: mown lawn strips (`Lawn` 64), cobble promenade arc tiles (88), brick kerb + slate lip round the island edge, open at the bridge (`Kerbs` 46), cobble aprons (64), avenue: slate tiles (56), plaza tiles / ring, marble borders, fabric runner, arrival star, trophy tiles in the 8 element colours | layout from constants (ISL); kerb gap depends on Link | 367 | 324 x 1.5 x 269 | C everywhere (walkable floor). N tests: `Forum`, `Lawn`, `Kerbs`, `Kerb`, `KerbLip`, `AvenueTile` + materials (smoke_p3_arenaworld :1161-1213). R: trophy tiles element colours (fixed per index) |
| **ArenaColosseumFloor** | `buildFloor` :1734 (`disc16` :1717, `ring16` :1724, `flatPatches` :1330) | 16-gon sand floor (apothem 73), slate band, gold line, marble ring at 40, raked sand drifts, 8 element diamonds (frame, mark, gem), element wheel (8 petals, rays, rim, core) | 1 | 157 | 146 x 1.3 x 146 | C (raid stage floor; `BattleZone_Arena` sits on it, Floor CFrame = A). R: 8 element colours (fixed per section) |
| **ArenaStandSegment** (3 kinds) | `segmentTemplate(kind)` :1670 (voxel grid `segmentGrid` :1506, `bayArch` etc.) placed by `buildColosseum` :1779 | one 22.5-degree sector of the stadium: podium wall, 4 tiers with fabric seats, outer brick wall with blind arches / recesses, cornice, crenellations, banners, iron, gold | `Stand` (x12, 34 parts), `Gate` (x3 at k 0/4/12, 61 parts: passage), `BossGate` (x1 at k 8, 50 parts) | 641 total | ~40 x 24-30 x 33 each | C (walls, tiers, seats; `Recess` + `Banner` non-collide). **R**: per placement `recolor(seg, "Seat", element)` and `"Banner"` -> Seat / Banner must stay separate MeshParts. At: `Element`, `Kind`. N tests: `Wall` Brick, `Seat` Fabric, `Cornice` / `Pilaster` Marble (smoke_p3_arenaworld :1140) |
| **ArenaPillar** | `pillar()` :1697 | round marble column on a slate plinth, capital, brass abacus, iron brazier, neon flame | x16 between segments | 6 (96 total) | 4.4 x 24.7 x 4.4 | C. **R** `Flame` per element (`flameColor`). L: PointLight on every 2nd flame |
| **ArenaDuelRing** | `buildRing` :1878 | 16-gon sand ring (apothem 33) with rim, curb + coping + neon curb inlay, sand drift, 8 torch posts, crossed-swords floor emblem, 2 challenge pads | 2 rings: accent red (Ring 1) / blue (Ring 2) | 190 / 182 | 73 x 6.7 x 73 | C floor / curb / pads. **P `DuelPrompt`** on part `ChallengePad` (attrs RingIndex, PadIndex, OpenPanel = "Arena"; ArenaController.lua:2872 reads OpenPanel); **G `PadTag`** billboard on the pad; ArenaInfo.Rings[i].Pads = those parts (BattleService). **R**: accent on CurbInlay, Emblem `Accent`, `PadGlow`. At `RingIndex` on model |
| ArenaRingPost | `ringPost()` :1813 | torch post: slate base, marble post, brass cap, neon flame | x8 per ring | 4 | 2.2 x 6.2 x 2.2 | C base/post |
| ArenaSwordsEmblem | `swordsEmblem(accent)` :1827 | voxel crossed swords + accent ring on the ring floor | per accent colour | 38 | 16.4 x 1 x 16.4 | **R** `Accent` voxels (cache per colour) |
| **ArenaEventBoard** / **ArenaLeaderboard** | `boardFrame` :1969, `buildEventBoard` :1995, `buildLeaderboard` :2041 | free-standing stone frames (step, 2 posts with plinths, caps, flames, crossed swords, lintel + trim, panel) | 2 | 17 each | 6-15 x 16-19 x 17-19 | **G** `BoardGui` / `LeaderGui` SurfaceGui on the `Panel` part (ApplyArenaState :2242 writes labels; ArenaInfo.EventBoard / Leaderboard keep `Panel`, `Labels`, `Rows`). C posts |
| ArenaAvenueTorch / ArenaBridgeTorch | `torch()` :2314 | slate foot, iron pole, brass bowl, neon flame | 6 on the avenue, 12 on the bridge | 4 | 1.8 x 6.6 x 1.8 | **R** `Flame` by element; L PointLight on some; NC_Detail |
| ArenaHedgeBox | `Art.hedgeBox` :1179 | planter box + cap + hedge + flowers | x4 | 5 | 5 x 3 x 2 | NC_Detail |
| ArenaBannerPole | `bannerPole` :2368 | pole with crossbar and crimson banner | x2 | 7 | ~3 x 14 x 1 | - |
| ArenaPlanter | `planter()` :2382 | brick / marble curbed planter with soil, grass, hedge, flowers | x2 | 26 | ~10 x 3 x 30 | NC_Detail |
| ArenaTree | `Art.tree` :1152 | bed, trunk, 3 leaf blobs | x6 (scale 0.85-1.1, seed) | 5 | ~6 x 14 x 6 | NC_Detail; scale per instance (uniform scale of a mesh is fine) |
| ArenaLantern | `Art.lantern` :1166 | foot, post, neon lamp, roof | x14 (lit / unlit) | 4 | ~1 x 6.6 x 1 | L PointLight on lit ones |
| **ArenaTrophyStatue** | `buildTrophy` :2327 | marble plinth + brass trim, voxel golden trophy (101 gold voxels), star, gems | 1 | 110 | 11 x 12.6 x 11 | C plinth |
| ArenaGateSign | `buildGateSign` :2472 | "BATTLE ARENA" sign over the main gate | 1 | 2 (+1 invisible anchor) | 11.8 x 5.4 x 1 | **G** SurfaceGui on `GateSign`; invisible `GatePromptAnchor` Part carries **P `ArenaPrompt`** (OpenPanel Arena, OpenPanelTab Raid). Keep the anchor as a Part |
| **ArenaBridge** (kit) | `buildBridge` :2499 (`puffTemplate` :599) | stone bridge from the lobby's dock to the forum: cobble deck slabs, slate deck edges, carpet runner, brick parapets + marble caps, slate piers, 12 torches, entrance arch (2 marble pillars, lintel, `ArchSign` with 2 SurfaceGuis "BATTLE ARENA" / "TO THE PLAZA"), cloud puffs under it | **length depends on the lobby** (startZ..endZ computed at Build) -> must be a kit of repeatable segments (deck tile, parapet run, pier, torch, arch, puff), not one mesh; only built when Link = "Bridge" | 297 | 338 x 31 x 155 (diagonal) | C deck / parapets / arch. N test `ArenaBridge`. NC_StyleExempt on `BridgePuff` |
| ArenaBattleZones | `makeZone` :884 | invisible zone boxes tagged `NC_BattleZone` (attrs Mode, Size, ZoneId, Index) | 3 | 3 | - | **not visual: keep as Parts** |
| (gate) **Portal_Return** | `Gates.buildReturn` :2719 -> `Gates.build` :2603 -> `WorldStyle.BuildGate` (WorldStyle.lua:434) | the forum's green "To the Plaza" gate, house glyph | - | 43 | 16 x 26 x 22 | **P `ArenaReturnPrompt`** on the gate's prompt part. Shared gate kit -> coordinate with the portals inventory |
| (gate) **Portal_Arena** | `Gates.buildArena` :2696 (+`Gates.torch` :2668) | red "Battle Arena" gate in the Gate Court, swords glyph, 2 torches | - | 54 | 27 x 26 x 16 | **P `ArenaPortalPrompt`** (ArenaInfo.ArenaPortal = prompt part). Parent = LobbyInfo.GatesFolder |
| (gate) **Portal_Ring** | `Ring.buildPortal` :2772 (+`Gates.crownPedestal` :2656) | gold "Champion Ring" gate, crown glyph, pad, 2 crowned pedestals, status pill from attr `RingBoard` | - | 69 | 25 x 26 x 27 | **P `RingPrompt`** (OpenPanel Ring) on the pad; ArenaInfo.RingPortal = pad (BattleService.lua:2702 finds `Portal_Ring` by name; ArenaController.lua:773). At `RingBoard` written by BattleService on model or pad. N tests: `CrownBand`, `CrownPoint` |
| **ArenaRingPocket** (`BattlePockets/RingPocket_<i>`) | `Ring.pocketTemplate` :2873, cloned by `ArenaBuilder.BuildPocket` :2965 | private Champion Ring in the sky: voxel cloud (39), 16-gon sand floor + canvas, rim + neon rim inlay, kerb + lip, apron, 4 crowned posts (`Ring.crownPost` :2859), cloud-puff crowd on a 2-step bleacher (`Ring.crowdStand` :2826: 7 puff characters with arms, eyes, mouths), spawn pad + green glow, champion pad | 1 template, up to 64 clones (POCKET_SPACING grid) | 248 (budget 250) | 92.6 x 30 x 92.6 | C floor / kerb / posts / pads. At `PocketIndex`, `PocketKind`. Zone part added per clone. N tests: `RingRim`, `CrownGem`, `PuffBody`, `CrowdPuffs`, `Kerb` (smoke_p3_arenaworld :788, :1258) |

---------------------------------------------------------------------------------------------------------------------

## D. Dungeon (server, `DungeonBuilder.lua`; templates in `ServerStorage.DungeonTemplates`, runs in `workspace.Dungeons`)

Pipeline: `DungeonBuilder.Template(name)` :1114 builds one of 17 templates on demand (`EnsureTemplates` :1131,
spawned after boot by `Build` :1193) via `geo(...)` :1070 -> `Rooms.<Kind>(variant)`. Every template is a Model whose
PrimaryPart is an invisible 1x1 `Base` (y -1.5) carrying the layout Attachments; decor in a `Detail` sub-model
(NC_Detail). Runs: `BuildRun` :1552 clones the Entrance hall, `PlaceRoom` :1399 clones corridor + room via
`clonePiece` :1352 (moves every BasePart by one delta), recolours `Accent`-attributed parts to the floor element
(`recolourAccents` :1331, `elementColor` :1240), adds the invisible `Threshold`, the `NC_BattleZone` (`makeZone`
:1374) and two portcullis doors, assembled under ServerStorage and parented in one step. Every part is a
`Voxel.Box` through `Kit.part` :153.

| Id | Builder (file:line) | What | Variants | Parts | Size | Runtime needs |
|---|---|---|---|---|---|---|
| **DungeonHall_1..3** | `Rooms.Hall(v)` :633 | pillared hall: flagstone floor (64 tiles + cracks), 4 walls with doorways, corner pillars, 2 rows of pillars, torches, ceiling, chandelier, hearth, runes, banners, shield, rack, rug, tables / benches / crates / barrels / hay / puddle per variant | 3 (seeded props differ) | 206 / 206 / 201 (budget 320) | 50 x 17.8 x 50 | see "every template" below |
| **DungeonCellar_1..3** | `Rooms.Cellar(v)` :696 | brick cellar: barrels, crates, hay, chains, a barred cell, wine rack, bottles, bones | 3 | 191 / 196 / 197 | 50 x 17.8 x 50 | " |
| **DungeonCave_1..3** | `Rooms.Cave(v)` :750 | rock-walled cave: rocks, stalagmites (21), turquoise pool with rim, waterfall wall with neon `WaterStreak` (Accent) | 3 | 170 / 176 / 172 | 51.6 x 17.8 x 51.2 | " ; stalagmites + rocks collide |
| **DungeonBridge_1..2** | `Rooms.Bridge(v)` :806 | plank / stone bridge over a dark chasm: `Abyss` slab (transparent 0.35; made invisible on floor 1), lamp posts, kerbs | 2 | 119 / 120 | 50 x 23 x 50 | an invisible floor under the chasm; `Abyss` looked up by name in PlaceRoom |
| **DungeonThrone_1** (boss room) | `Rooms.Throne(1)` :865 | 62 x 74 hall, 120 floor tiles, pillars, stairs to a dais with plum carpet, stone throne with gold crown + cushion, braziers, candles, chains | 1 | 304 (budget 420) | 62 x 17.8 x 74 | extra A: `ZoneCenter`, `SpawnAnchor` (enemy spawn point); C: `Dais`, `ThroneSeat`, `Step` |
| **DungeonEntrance_1** (hall, room 0) | `Rooms.Entrance()` :937 | 30 x 26 entrance hall: 4 spawn pads, banners, barrel, crate | 1 | 71 (budget 140) | 30 x 17.8 x 26 | A `Spawn1..4`; DungeonController finds `Entrance_1` by name (:1777) |
| **DungeonCorridor_Straight / Left / Right** | `Rooms.Corridor(kind)` :972 | 15-long corridor, 5-stud tiles, walls, torch; Left / Right jog 15 studs sideways | 3 | 19 / 38 / 46 (budget 70) | 12-27 x 17.8 x 15 | A Entrance / Exit |
| **DungeonTreasure_1** | `Rooms.Treasure()` :1022 | 30 x 24 alcove: 4 chests, purple ForceField `ExitShimmer`, invisible `ExitPrompt` part | 1 | 61 (budget 90) | 30 x 17.8 x 24 | **N `Chest`** parts (attr ChestSlot 1-4) each with **P `ChestPrompt`** (attrs DungeonAction = "Chest", ChestSlot); **P `ExitPrompt`** on invisible part `ExitPrompt` (DungeonAction = "Exit"); A `Chest1..4`. RoomInfo.Chests / ExitPrompt are found by name in PlaceRoom :1475-1490 |
| every template | `newTemplate` :569, `roomShell` :597, `roomPoints` :622 | - | - | - | - | **PrimaryPart `Base`** (invisible) with **A `Entrance`, `Exit`** (+ `Threshold`, `Spawn1..4`, `Dais` on rooms); attrs Width, Depth, Kind, Budget; C: `Floor` tiles, `Wall`, `Plinth`, `Pillar(Base)`, props marked Collide (Barrel, Crate, TableTop, Bench, Step, Rock, Stalagmite, Cauldron, Statue, HearthSide, WineRack, Chest); `Detail` model (NC_Detail). **R**: parts with attribute `Accent` = true (Puddle, Banner, Rune, Brew, ShieldCrest, RugInlay, WaterStreak) recoloured per floor element; floor 1: PointLights +0.3, `Abyss` transparent. L: every torch flame has PointLight `TorchLight` + `Fire` `TorchFire`. Tests (smoke_p5_dungeon :1610-1641, :1749): budgets, attachments Entrance / Exit / Threshold / Dais, Accent parts exist and take the element colour, live run <= 950 parts |
| **DungeonWall** (kit) | `Kit.wall` :201 | plinth band, body (split round a doorway + lintel wall), slate cap, brick dado / courses, protruding stones | length per room (48 / 50 / 62 / 74 / 30 / 15...), with / without door, `lite` | 5-14 | len x 15.8 x 1.7 | C |
| DungeonFloorTiles (kit) | `Kit.floorTiles` :170 | 6-stud flagstones +-0.05 alternation + cracks | per room size | 20-130 | w x 1 x d | C (walkable; enemies / players stand on y 0) |
| **DungeonWallTorch** | `Kit.torch` :253 | iron sconce, bracket, stick, neon flame | used in every room and on Portal_Dungeon | 4 | 1.2 x 2.6 x 1.3 | L: PointLight `TorchLight` (Portal_Dungeon looks it up and sets Range 16), Fire `TorchFire` on `Flame` |
| **DungeonPortcullis** (`Door_Entrance` / `Door_Exit`) | `Kit.door` :278, `Kit.setDoor` :297 | 2 jambs, lintel, n iron `Bar`s | width 8 (n = 5 bars) | 8 | 10 x 9 x 1.6 | **M / toggle**: `Kit.setDoor` flips each `Bar`'s CanCollide / CanQuery / Transparency; model attr `Open`; room attrs `DoorOpen` / `EntranceOpen`; DungeonController `R.slide` (DungeonController.lua:1799) makes sinking copies of the `Bar` parts with `Instance.new("Part")` + bar.Size (a mesh bar would slide as a box: switch to `bar:Clone()`). Created at runtime, not in the template |
| Dungeon props (kit) | `Kit.barrel` :316, `crate` :323, `chain` :330, `puddle` :336, `moss` :340, `hay` :344, `table` :349, `bench` :357, `bones` :363, `banner` :369, `rune` :375, `arch` :379, `stairs` :389, `brazier` :396, `rock` :410, `stalagmite` :415, `cobweb` :423, `skulls` :429, `rubble` :435, `rack` :443, `cauldron` :452, `shield` :459, `statue` :467, `candles` :476, `chandelier` :484, `hearth` :504, `rug` :521, `wineRack` :527, `chest` :536, `pillar` :246, `ceiling` :311 | the reusable furniture of all rooms | sizes / seeds per call (crate `s`, rock `size`, stalagmite `h`, stairs steps) | 1-12 each | 1-8 studs | Accent-attributed sub-parts (see above); `chest` adds prompt; lights on brazier / candles / chandelier / hearth |
| **DungeonPortal** (`Portal_Dungeon`, Gate Court) | `DungeonBuilder.BuildPortal` :1143 -> `WorldStyle.BuildGate` (Purple, torch glyph, pad) + 2 `Kit.torch` | the purple Dungeon gate | - | 59 (budget 120) | 22 x 26 x 25 | **P `DungeonPrompt`** (OpenPanel Dungeon) on the prompt part; attr `DungeonBoard` (pill). Shared gate kit |
| DungeonRuntimeHelpers | `PlaceRoom` :1453 (`Threshold`), `makeZone` :1374 (`NC_BattleZone`) | invisible trigger / zone boxes | - | 2 per room | - | **not visual: keep as Parts** |

DungeonController (client) builds no models of its own except the temporary `BarSlide` copies (above); everything
else is GUI.

---------------------------------------------------------------------------------------------------------------------

## E. Integration surface (what a mesh swap must keep)

Names / attributes other code (src + tests) looks up. Keep these exact names on the same kind of instance (Model vs
BasePart vs Attachment), at the same local position, or the consumer breaks.

### Home
| Name / attr | Kind | Readers |
|---|---|---|
| `Spot_NN/Home` (Folder, tag `NC_Home`, attrs SpotIndex, PlotCFrame, OwnerUserId, OwnerName) | Folder | HomeFx (CollectionService), FusionController.lua:627, PetCareService.lua:840, ArenaController :944, CareController :443, many tests |
| `Station_<Id>` Model + attrs StationId, Level, Kind, BuiltAt, Points (BerryPoint, BowlCenter, ChuteMouth, Tray, HopperTop, BasketTop, SwirlCenter, RoofTop), Info (Rows, Open, Tier) | Model | HomeFx (registerStation :3775, berries :3075-3097), PetCareService `Care.stationModel` :830, FusionService.lua:1150, FusionController :628 / :2313, smoke_p2_homeworld / p2_visual / p4_care / p5_home |
| `Hopper` (BasePart, glass) | part | PetCareService.lua:1604 (FeedPrompt anchor), smoke_p2_homeworld :342 / :767, smoke_p2_visual :284, smoke_p4_care |
| `Swirl` (Model with >= 3 BaseParts) | model | HomeFx.lua:3801 (spins its parts), smoke_p2_homeworld :490 / :937 / :1459, smoke_p2_visual :225 |
| `Spot<i>` Attachments (Garden on `Lawn`, Gym on `Deck`), attrs Slot / Open / Busy / Key / Stat / Ends | Attachment | HomeFx (FindFirstChild("Spot"..slot, true) :1606), HomeBuilder applyTraining, smoke_p2_homeworld :367 / :801 / :919 / :1423, smoke_p2_fix_client |
| `PromptPoint` / `PromptPoint<i>` Attachments carrying `FusionPrompt`, `ArenaGatePrompt`, `GardenSpotPrompt` | Attachment + prompt | FusionController :661 (`prompt.Parent.WorldPosition`), CareController :2518, HomeFx prompt hiding (by OwnerUserId), smoke_p2_visual (FusionPrompt on a PromptPoint) |
| `FeedPrompt` (on Hopper), `TrainPrompt` (on biggest part) | prompt | PetCareService :1604-1626 |
| `MachineSign` / `BasketLine`, `FarmSign`, `BowlSign`, `PadSign`, `ClosedGui`, `ClaimGui` | Billboard / SurfaceGui + labels | HomeFx :3118 / :1321 / :3873, smoke_p5_home, smoke_polish_worldtext :224 |
| `Pads/Pad_<Id>`: `Base` (BuyPrompt + PadSign), `Glow` (Neon) + attrs | Model | HomeFx :1300 / :3813, TycoonService :2700, smoke_p2_homeworld :1239 / :1507 |
| `Ghost_<Id>` (attr StationId) | Model | smoke_p2_homeworld :637-685, smoke_p2_visual |
| `ClaimGate` / `ClaimSign` / `ClaimAnchor` / Attachment `ClaimPoint` / `ClaimPrompt` (attr SpotIndex) | mixed | TycoonService :1388-1424, HomeFx :468 / :4052, smoke_p2_homeworld :570, smoke_p5_world :652 / :876 |
| `Paths`, `HouseLot` | Model | HomeBuilder only; smoke_p2_visual (`HouseLot`, `Stake`, `String`) |
| art audit names in smoke_p2_visual: `Berry`, `GoldBerry`, `Starberry`, `Barn`, `Pod`, `Chamber`, `OutputDome`, `ChamberInlay`, `Shard`, `Button`, `HopperBerries`, `Window`, `Plinth`, `Spire`, `RoseWindow`, `Cushion`, `BedRoof`, `Stem`, `Sprout`, `Mat`, detail models `Crates`, `Flowers`, `Lanterns` | parts | tests only |
| `HomePets` / `ClientFx` / `HomeFx` folders, `HomePortalFx` folder, model `HomePortal` | client folders | HomeFx, HomePortalFx, smoke_p4_portal (`countParts`, part names), smoke_p2_homeworld |

### Arena
| Name / attr | Readers |
|---|---|
| `workspace.BattleArena` (attr ArtFixes), ArenaInfo (Center, Floor, Rings[i].Pads, Spawn, ReturnCFrame, RingPortal, ArenaPortal, LobbyCFrame, EventBoard{Panel, Labels}, Leaderboard{Rows}) | BattleService, EventService, TutorialService, ArenaController :537, smoke_p3_arenaworld / p3_flow / p4_ring |
| `NC_BattleZone` parts (attrs Mode, Size, ZoneId, Index) | BattleService `ZoneAt`, DungeonService, tests |
| prompts `DuelPrompt`, `ArenaPrompt`, `RingPrompt`, `ArenaPortalPrompt`, `ArenaReturnPrompt`, `ArenaGatePrompt` (attr OpenPanel / Teleport) | ArenaBuilder `connectPrompts` :3152, ArenaController :2872 |
| `Portal_Ring` (+ attr RingBoard on model or pad), `Portal_Arena`, `Portal_Return` | BattleService.lua:2702, ArenaController :773, smoke_p3_arenaworld, smoke_p5_world :787 / :1021, smoke_polish_portals :453 |
| `BattlePockets/RingPocket_<i>` (attrs PocketIndex, PocketKind) | BattleService, smoke_p4_ring |
| test-only names: `IslandCloud`, `Colosseum`, `Forum`, `Lawn`, `Kerbs`, `Kerb`, `KerbLip`, `AvenueTile`, `Wall` (Brick), `Seat` (Fabric), `Cornice` / `Pilaster` (Marble), `ArenaBridge`, `RingRim`, `CrownGem`, `CrownBand`, `CrownPoint`, `PuffBody`, `CrowdPuffs` | smoke_p3_arenaworld |
| **ban**: `smoke_p3_arenaworld.lua:229` fails on ANY `MeshPart` (also Decal / Texture / Weld) inside `BattleArena` | must be relaxed for Phase 6 |

### Dungeon
| Name / attr | Readers |
|---|---|
| `ServerStorage.DungeonTemplates/<17 names>`, attrs Kind / Budget / Width / Depth; PrimaryPart `Base` with Attachments Entrance, Exit, Threshold, Spawn1..4, Dais, ZoneCenter, SpawnAnchor, Chest1..4 | DungeonBuilder itself (`worldPoint` :1342), smoke_p5_dungeon :1610-1641 |
| `workspace.Dungeons/Dungeon_<i>` / `Room_<n>` (attrs Room, Floor, Element, DoorOpen, EntranceOpen), `Door_Entrance` / `Door_Exit` / `Bar`, `Entrance_1` | DungeonController :1770-1838, DungeonService (RoomInfo), smoke_p5_dungeon :2200-2213 |
| `Accent` attribute on parts | DungeonBuilder `recolourAccents`, smoke_p5_dungeon :1641 / :1749 |
| `Chest` (attr ChestSlot) + `ChestPrompt`, `ExitPrompt` (attr DungeonAction), `Threshold`, `Abyss` | DungeonBuilder PlaceRoom, DungeonService (Request "Chest" / "Exit") |
| `Portal_Dungeon` + `DungeonPrompt` (OpenPanel) + attr `DungeonBoard`, `TorchLight` | DungeonService, ArenaController, smoke_p5_dungeon :1805 (<= 120 parts), smoke_p5_world :771 |

### Tooling that constrains the swap
* `tools/check.mjs` rule `asset-id` (:24, :463-471): any string matching `rbxassetid://` outside `Config.lua` is an
  error, and inside Config only `Config.Art.StormfangImage` (contract.json `v3.artImage`) is allowed. Mesh ids must
  be stored as plain numbers (e.g. `Config.Meshes = { HomeKitchen_L2 = 0 }`) and the `rbxassetid://` prefix must not
  appear as a literal anywhere, or the rule must be extended (contract.json + check.mjs).
* `tools/smoke_content.lua:1243` fails pets with MeshParts carrying MeshId / TextureID (pet scope, same rule style).
* Art-rule audits (smoke_p2_homeworld :1034-1075, smoke_p2_visual :123-160, smoke_p3_arenaworld `paletteAudit`, and
  the builders' own `Kit.finish` HomeBuilder.lua:736 / `Art.enforce` ArenaBuilder.lua:1213) recolour / re-material
  any part that is big, saturated or not a WorldStyle material, unless an ancestor is tagged `NC_StyleExempt`. The
  new ART RULE (ARCHITECTURE_V3.md:30-38) wants the bright pre-Phase-5 voxel look: mesh models must be tagged
  `NC_StyleExempt` (or the guards taught to skip MeshParts) or they will be greyed / turned to Slate.
* Part budgets (Farm 150, Garden 95, ..., plot <= 950, arena <= 2800, pocket <= 250, dungeon room <= 320 / 420, run
  <= 950, gates <= 120) are upper bounds: meshes only lower them, but tests count `BasePart`s, so collision proxies
  count too.
* `tools/render_model.py` / `dump_model.lua` draw BaseParts as boxes / balls / cylinders / wedges; a MeshPart would be
  drawn as its bounding box (no mesh data offline). Renders of meshed models need a Blender-side preview instead.
* `robloxmock.lua` already defines `MeshPart` (MeshId, TextureID, CollisionFidelity, RenderFidelity) at :3798; there
  is no InsertService / AssetService mesh loading in the mock, so the mesh path is untested by default (good for
  "fallback keeps tests green", but the mesh path needs its own mock hook).

---------------------------------------------------------------------------------------------------------------------

## F. Suggested mesh grouping (what to model in Blender)

Counting one asset per row: **Home ~40** (Farm kit ~12 pieces instead of 40 baked levels, Garden kit ~10, Food
Machine 5, Training 5 (or 1 deck + 5 add-on props), Vault 5, House 4, Fusion 3 + Swirl 3, Arena Gate 1, Fence kit
~12, Fountain 3, Podium 3, Pad 4, ClaimSign 1, Paths 1, HouseLot 1), **Home client fx ~10** (heap, 4 training props
split into static + moving pieces, Zzz, bit, scoop dash, portal ring kit (ring block, surface, swirl arm, base),
arrival block), **Arena ~35** (cloud chunks ~4-6, forum ground kit ~8, colosseum floor ~3 incl. recolourable petal
/ diamond, segment Stand / Gate / BossGate each split into static + Seat + Banner meshes, pillar (+ flame), duel ring
kit (floor, rim, curb, inlay, post, emblem base + accent, pad + glow), board frame, torch, hedge box, banner pole,
planter, tree, lantern, trophy statue, gate sign, bridge kit ~8, ring pocket ~6 incl. crowd puff character),
**Dungeon ~45** (17 room shells or a wall / floor / pillar / ceiling kit + 30 props + torch + portcullis frame + bar
+ chest (body + lid + lock)). Gates (`Portal_*`) belong to the shared `WorldStyle.BuildGate` kit (portals
inventory).

Rules of thumb that fall out of the runtime needs:
1. **One MeshPart per runtime-recoloured region** (pad Glow, ghost = material swap only, portal ring blocks /
   surfaces / swirl arms, arena Seat / Banner / Flame / element petals, duel ring accent pieces, dungeon `Accent`
   parts). Fixed-colour regions can be baked into one mesh with a texture / vertex-colour atlas.
2. **One MeshPart per independently moving group** (Fusion `Swirl` parts, training props `Belt` / `Belt2` / `Lift` /
   `Orb` / `Shell` / `Spark1..3` / `Wobble`, HomePortal swirl arms, portcullis `Bar`s, heap / Zzz pooled pieces).
3. **Keep invisible collision proxies** for walkable floors, walls and stairs (Paths, Lawn, Deck, arena floors,
   forum, bridge deck, dungeon floors / walls): big concave meshes collide badly (`CollisionFidelity` hulls) and
   enemies / pets assume the old flat heights (lawn y 0.2, dungeon floor y 0, ring floor RING_Y 0.6, pad top 0.5).
4. **Keep anchor parts** that host prompts / guis / attachments (Hopper, Deck, Lawn, Portal, Base, ChallengePad,
   Panel, GateSign, ArchSign, SignBoard, Cabinet, FoodBowl, Chest, ExitPrompt) as named parts - either the named
   MeshPart itself or an invisible proxy Part with the same name, size and CFrame.
5. Variable-length builds (yard fence runs, arena bridge, dungeon walls, floor tiles) must stay **kits** of
   repeatable segments placed by the existing Lua layout code.

---------------------------------------------------------------------------------------------------------------------

## G. Integration note: the smallest seam

### Where
All three builders already go through a single "template -> clone at CFrame" step:

* **HomeBuilder**: `stationTemplate(def, level, accent, open)` HomeBuilder.lua:2077 (stations, cached per
  `Id:level[:open]`), `padTemplate(state)` :2139, `pathTemplate()` :2366, `lotTemplate()` :2446; placement in
  `cloneAt` :786 / `placeStation` :2591 / `updatePad` :2799. `BuildStationModel` :3074 (tests / renders) and
  `Points` :3093 use the same template.
* **ArenaBuilder**: the cached template functions `segmentTemplate` :1670, `pillar` :1697, `ringPost` :1813,
  `swordsEmblem` :1827, `torch` :2314, `planter` :2382, `Ring.pocketTemplate` :2873, `puffTemplate` :599, all placed
  by `place(tpl, cf, parent, name)` :413; the one-off sections (`buildCloud` :1262, `buildGround` :1354,
  `buildFloor` :1734, `buildRing` :1878, boards, trophy, bridge) are built straight into the arena model.
* **DungeonBuilder**: `DungeonBuilder.Template(name)` :1114 (17 templates in ServerStorage), cloned by `clonePiece`
  :1352; runtime pieces `Kit.door` :278 and `Kit.torch` :253.
* Client: `HomeFx` `G.takeProp` :3185, `G.takeHeap` :1952, `G.takeZzz` :1981, `R.takeBit` :2767;
  `HomePortalFx` `P.build` :166; `FusionController` `machineBurst` :1588.

### How (proposed, server side)
A shared `shared/MeshLibrary.lua` (name per the lead) with `MeshLibrary.Get(id) -> Model | nil` (a fresh clone of the
uploaded asset when `Config.Meshes[id]` is a non-zero number and it loaded, else nil) and
`MeshLibrary.Dress(partModel, meshModel, opts)` that **merges the mesh into the existing Part template instead of
replacing it**:

```
-- in stationTemplate, after result = fn(def, level...) and before Kit.finish:
local mesh = MeshLibrary.Get(MeshLibrary.StationId(def.Id, level, open))   -- e.g. "HomeKitchen_L3"
if mesh then MeshLibrary.Dress(result.Model, mesh, { Keep = KEEP_HOME }) end
```

`Dress` keeps every part of the Part build that (a) is CanCollide, (b) has children (Attachments, prompts, guis,
lights, emitters, Fire), (c) is named in the keep list (Hopper, Glow, Bar, Portal, Accent parts, Seat / Banner /
Flame, the Swirl model...), or (d) carries an attribute (Accent, ChestSlot, DungeonAction); it makes those
invisible (Transparency 1, keeps CanCollide / CanQuery) unless the mesh model provides a MeshPart of the same name
(then the MeshPart takes the old part's name, CFrame role, attributes and children and the Part is removed); it
destroys the rest and parents the mesh's MeshParts (anchored, CanCollide false unless flagged, tagged
`NC_StyleExempt`). Because the templates are cached and cloned, this runs once per (station, level) per server, and
`placeStation` / `cloneAt` / attributes / points / `afterPlace` stay untouched. The same call fits
`DungeonBuilder.Template` (after `geo.build`), each ArenaBuilder template function, and (client) `G.takeProp` /
`P.build`. With no id set (today, and in every smoke test), `Get` returns nil and the build is exactly today's.

Asset loading: Open Cloud "Model" uploads of an FBX produce a Model asset with MeshParts; on the server
`InsertService:LoadAsset(id)` (assets owned by the experience's creator) returns it - do it once per id in a
`task.spawn` preload (DungeonBuilder already builds templates after boot in a spawned task; HomeBuilder builds
templates lazily on first SetStation, which happens after a claim). `MeshPart.MeshId` is not writable by scripts
at runtime, so "Part + set MeshId" is not an option; `AssetService:CreateMeshPartAsync` is the alternative if the
upload is a Mesh asset. Client effects (HomeFx, HomePortalFx) need the meshes replicated: the server can park the
loaded models in `ReplicatedStorage.Meshes` for the client to clone.

### Risks
1. **Name contract breakage**: any consumer in section E that does `FindFirstChild(name)` / `.Name ==` on a part
   that the mesh swap deletes. Highest-impact: `Hopper` (FeedPrompt), `Swirl` (+ its parts), `Glow` on pads,
   `Spot<i>` / `PromptPoint*` Attachments on `Lawn` / `Deck` / `Portal`, `Base` + `Bar` in doors, `Chest` /
   `ExitPrompt`, `Panel` of the boards, `Seat` / `Banner` / `Flame` (recolour), `Accent` attribute parts, `Abyss`.
   `Dress` must keep them (proxy or renamed MeshPart).
2. **`biggestPart` heuristics change**: station `PrimaryPart` (HomeBuilder :2106), ghost selection (12 biggest,
   :2776), PetCareService `TrainPrompt` anchor (biggest part) and `Care.anchorOf` fallback all pick "the biggest
   BasePart"; an invisible collision proxy or a single big MeshPart becomes the winner, moving the TrainPrompt and
   the pivot. Pin them with explicit names / PrimaryPart.
3. **Style guards fight the meshes**: `Kit.finish`, `Art.enforce` and the smoke art audits clamp saturation / value,
   force WorldStyle materials and shadows. Bright pre-Phase-5 meshes must be tagged `NC_StyleExempt` (both guards and
   all audits already skip that tag) or they will be greyed / turned to Slate, and the audits will fail once ids
   exist.
4. **Tests assume Part builds**: `smoke_p3_arenaworld.lua:229` bans MeshParts in the arena outright; smoke_p2_visual,
   smoke_p2_homeworld, smoke_p3_arenaworld and smoke_p5_dungeon assert dozens of specific part names / materials
   (section E). They stay green only while the mock has no mesh ids (fallback path). Plan a `Config.Meshes` override
   in the mock + new mesh-path tests rather than editing the old ones, and relax the arena ban to "MeshParts only from
   MeshLibrary".
5. **check.mjs `asset-id` rule**: a literal `rbxassetid://` anywhere except `Config.Art.StormfangImage` is a hard
   error. Store numeric ids and build the URL without the literal, or extend contract.json / check.mjs.
6. **Collision and heights**: HomeRoam / HomeFx assume the Garden lawn top at y 0.2 and a clear interior; battle
   floors and dungeon floors at fixed heights; dungeon pocket math assumes 48 / 62 x 74 room footprints and doorway
   positions from `Entrance` / `Exit` attachments. Keep the Part collision layer (or simple box proxies) so physics
   and enemy placement do not change; meshes are visual only.
7. **Load latency / failure**: `InsertService:LoadAsset` yields and can fail (moderation, permissions, wrong
   creator, rate limits). Templates are built synchronously today (HomeBuilder on SetStation, ArenaBuilder in Build);
   a yielding load there would stall a claim or the boot. Preload asynchronously, build the Part version if the mesh
   is not ready, and optionally re-dress templates when it arrives (new clones only).
8. **Per-level explosion**: the Berry Farm has 40 levels, the Garden 8 levels x 13 open counts (104 cached
   templates). Baking one mesh per level is too many uploads; use kits (plants, beds, decor add-ons) placed by the
   existing layout code, with per-piece `MeshLibrary.Get`.
9. **Variable geometry**: yard fence runs (plot size), arena bridge length (lobby dock distance), dungeon walls,
   floor tiles, scoop ring radius, portal grow / shrink scale. These need segment meshes that tile / scale uniformly;
   non-uniform resizing of a MeshPart stretches its voxel detail.
10. **Runtime recolour vs textures**: a MeshPart with a TextureID ignores `Color` for opaque texels. Every region
    the code recolours (section F rule 1) must be its own untextured MeshPart (Color = material colour), including the
    ghost (whole-model ForceField swap works on MeshParts).
11. **Client pop-in / slide effects** (`HomeFx.startPop`, DungeonController `R.slide` building `Instance.new("Part")`
    copies of bars): still work but look different; `R.slide` should `Clone()` the bar so a mesh bar slides as a
    mesh.
12. **Offline renders**: `render_model.py` draws MeshParts as boxes, so the render-based visual iteration used so far
    no longer shows the real look; previews must come from Blender.
13. **Ownership overlap**: `Portal_Ring` / `Portal_Arena` / `Portal_Return` / `Portal_Dungeon` are
    `WorldStyle.BuildGate` gates (portals inventory) decorated by ArenaBuilder / DungeonBuilder (crown pedestals,
    torches); the home plot island / fence / gate parts are LobbyBuilder's, and the ClaimPrompt attaches to
    LobbyBuilder's `GateBeam/GateBase/GatePillar` by name; Cloud Cash coins are TokenLook's.
