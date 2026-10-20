# Phase 6 inventory: creatures and creature-adjacent models (inv-creatures)

Scope: everything built from Parts in `src/shared/PetBuilder.lua`, `src/shared/Voxel.lua`, `src/shared/PetCatalog.lua`
(looks), `src/shared/BossBuilder.lua`, `src/client/Controllers/SkyDragonController.lua`, `src/server/Services/NpcService.lua`,
`src/shared/TokenLook.lua`, plus the places where those models are used (EvolutionFx, PetController, HomeFx, BattleController,
dungeon wild pets, the StormAltar Stormfang showcase, the lobby statue, SpotService podium, UI viewports).
Repo: `/home/user/roblox/nimbus-climb` (branch v3-phase5). It was read only; nothing in it was edited.

Part counts were measured with the repo's own renderer (`tools/render_model.py <target> --json ... --dump-only`, which runs the
real Lua modules in the lupa mock). The raw dumps are in `dumps/*.json`. The per-pet tables (every catalog pet at every stage
and detail, with group sizes and colour keys) are in `pet_groups.txt`. The counting script is `count.py`.

The ART RULE that is already in the contract, at `ARCHITECTURE_V3.md:30-34`, says: "every new or reworked model ... is made in
Blender ... used in game as a MeshPart", and "Mesh asset ids live in Config".

---------------------------------------------------------------------------------------------------------------------------

## 0. Summary

| Group | Mesh assets to make (ids below) | Part builds today | Measured parts |
|---|---|---|---|
| Pets, base stage (33 catalog pets; 15 species) | 15 bodies + 13 tails + 7 wing styles (L and R) + 8 accessories + lids + 15 hybrid add-ons + golden star + aura bits | `PetBuilder.Build(def)` | High 247-343, Low 69-118 |
| Pets, first evolution (33 forms, one design per pet) | 33 bodies (each with its tail) + 5-6 evolved wing kinds | `PetBuilder.Build(def, {Evolved=1})` | High 913-1489, Low 195-377 |
| Pets, second evolution (16 forms, Epic and up) | 16 bodies + angel wings (2 pairs) + crests + 14 aura-bit kinds | `PetBuilder.Build(def, {Evolved=2})` | High 1472-1982, Low 413-517 |
| Raid bosses (4) | 4 rigs, 4-5 joint meshes each (19 in all) | `BossBuilder.Build(id)` | High 872-960, Low 588-754 |
| Sky dragon (Sage Dragon) | head, jaw, 9 segment variants, leg, tail tuft, puff, chain link | `SkyDragonController` build() | 294 |
| NPC pedestals (6) | 1 pedestal kit (rug recoloured per NPC, moss/flower placement seeded) | `NpcService.buildPedestal` | ~100-107 each |
| Cloud token / Cloud Cash coin | coin rim, face (round / octagon), emblem, halo | `TokenLook.Build` | 6-8 |
| Battle props (shield, ice, focus arrow) | 3 small meshes | BattleController | 1 / 5 / 3 |
| FX (evolution, battle, home): small blocks | optional FX kit (see section 9) | EvolutionFx, BattleController Fx, HomeFx | pooled |
| Re-uses of pet meshes, no new asset | NPC pets, Stormfang showcase, Nimbus statue, podium, battle units, wild and boss pets in the dungeon, home pets, viewports | PetBuilder callers | - |

The one change that covers about 90% of the creature surface is the single call `PetBuilder.Build` at
`src/shared/PetBuilder.lua:6772`. About 20 callers go through it, and every runtime contract they depend on (the names
`Body`/`WingL`/`WingR`/`Tail`/`Halo`/`Aura`/`EyeLid`, and the attributes `PB_G`/`PB_Base`/`PB_Rig`) is created in
`instantiate` (`:6297`). See section 10.

---------------------------------------------------------------------------------------------------------------------------

## 1. Pets: how PetBuilder makes one today (the contract a mesh build must reproduce)

Pipeline: `readLook` (`PetBuilder.lua:449`) -> `getBlueprint` (`:6228`; sculpts per look+detail, cached) -> `buildBlueprint`
(`:6052`) -> `instantiate` (`:6297`) -> `getTemplate` (`:6630`; up to 40 cached templates, and Build hands out `:Clone()`s)
-> `PetBuilder.Build` (`:6772`) adds the sparkle emitters, `PB_Evolved`, and the optional Wild tint.

### 1.1 Model layout (every pet, every stage)
* `Model "Pet_<Id>"`. `PrimaryPart = "Body"` is an invisible Part of 0.9 x 1.1 x 0.9 studs (x scale) at the pet's centre. The
  pet faces -Z, up is +Y, its right is +X.
* Every part is Anchored, with CanCollide, CanTouch and CanQuery false, Massless, and CastShadow false (`flagPart :6253`).
  Names are unique: the first part of a key gets the bare name ("Fur") and later ones get "Fur2", "Fur3" and so on.
* Body parts are named by palette key (Fur, Belly, Muzzle, EyeIris, EyePupil, EyeShine, EyeGlint, EyeRing, Lash, Nose, Mouth,
  Blush, Horn, Gold, Gem, Plate, Mask, NeonBlue, ...). The group parts are named after their group:
  * `WingL` / `WingR` (kind `wing`, or `cloud` for Stormfang's StormCloud ride). The right wing is the exact mirror of the left
    (`Voxel.MirrorBoxes`).
  * `Wing2L` / `Wing2R` (second evolution only, kind `wing`).
  * `Tail` (kind `tail`, Amp = per-species wag). Frog and Slime have no tail.
  * `Halo` (kind `bob`: the Halo accessory, plus evolved and ascended halos).
  * `Aura` (kind `orbit`: the Secret rarity's ring of voxels, or the second evolution's element aura).
  * `EyeLid` (kind `lid`: flat lids, 6 per pet at High (upper lid, lash line, lower lid per eye) and 2 at Low. They stay at
    Transparency 1 until a blink).
* Part attributes: `PB_G` = "Name:Kind:Side:Amp:Index", `PB_Base` = the rest CFrame in the hinge frame (as a string), `PB_T0`
  (the lids' visible transparency), `PB_Pulse` (Stormfang's neon parts pulse their transparency), `PB_Hue` (Rainbow finish:
  the at most 10 (High) / 4 (Low) biggest accent parts cycle their hue).
* Model attributes: `PB_Rig` (the hinge CFrame of each group), `PB_Scale`, `PB_Detail`, `PetId`, `PB_Seed`, `PB_Finish`,
  `PB_Hybrid`, `PB_Evolved` (0/1/2), `PB_Wild`.
* Children of Body: ParticleEmitter `RaritySparkles` (Legendary/Mythic/Secret) and `FinishSparkles` (Golden/Rainbow).
* Animate (`:6833`) uses no welds and no Motor6D. Every call it re-poses the parts of each moving group from the root's
  CURRENT CFrame (`base * hinge * motion * PB_Base`), toggles lid transparency (blink), pulses `PB_Pulse` and cycles `PB_Hue`.
  Clones rebuild their rig from the attributes (`buildRig :6419`).

### 1.2 Variants (what changes the geometry)
| Axis | Values | Where |
|---|---|---|
| Species | Cat, Dog, Fox, Bunny, Bear, Panda, Dragon, Owl, Slime, Unicorn, Phoenix, Frog, Penguin, Axolotl, Stormfang (15) | `SPECIES.*` `:954-1749` |
| WingStyle | Feather, Bat, Fairy, Cloud, Crystal, Flame, StormCloud (7) | `WINGS.*` `:1967-2092` |
| Accessory | Horns, Crown, Halo, Leaf, Mushroom, Scarf, Antlers, Flower (8) + none. All but Halo are sculpted INTO the body grid; Halo is its own bobbing group | `ACCESSORIES.*` `:2177-2299` |
| Detail | High (0.1 stud voxels) / Low (half resolution; Low is a separate merge, not just fewer parts) | `buildBlueprint :6052` |
| Evolved = 1 | one design per pet: a species base `EVO.Species.*` (`:3548-4207`) + a per-pet extra `EVO.Pets.<id>` (`:3693-4530`, `:5710-5905`) + a wing kind `EVO.WingKind :4597` (Fan `:3341`, Bat `:3394`, Flame `:3476`, Storm/Ice shard `:4250`, Rime `:5796`); colours `EVO.Look`/`EVO.Colours` | `EVO.Sculpt :4567` |
| Evolved = 2 | 16 pets (Epic+): `ASC.Pets.<id>` (`:5116-5993`), 1.2x bigger (`ASC.Grow`), two wing pairs (`ASC.SculptWings :4827`, AngelWing `:4776`), armour (Pauldrons/Greaves/ChestPlate `:4706-4747`), crest (SunDisc/SunMane/Eclipse/Crescent/PointHalo `:4979-5055`), element aura (`ASC.Aura :4959` with bits Crystal/Star/Flame/Bubble/Heart/Sun/Orb/Cloud/Bolt/Shard/Wisp/Magma/Snow) | `ASC.*` |
| Finish | Golden: gold palette ramp + Metal accents + glowing sparkle stars on head/cheek/chest/wing tips (`goldSparkles :2969`, extra geometry). Rainbow: pearly body, rainbow wings/accents by position, hue cycling | `applyFinishPalette :3016` |
| Hybrid | Body parent's species + the Style parent's signature feature (fox tail and ruffs, cat bands, axolotl gills, unicorn horn and mane, phoenix crest/plumes, panda patches, dragon crest/horns/spade, owl tufts, bunny ears, frog spots, penguin tuxedo ...), placed by scanning the body surface; Seed jitters colours and placement | `HYBRID.* :2411-2781`, `applyHybrid :2793` |
| Wild | applied to the clone only: body HSV x0.75 brightness, -20% saturation, lerp 25% toward Tint; Eye parts turn Neon in the Eyes colour; KEEP list for shine/glint/spark/aura/halo | `applyWild :6747` |
| Lean rebuild | a heavy combination is re-sculpted without small details to fit the part cap | `getBlueprint :6228` |

Catalog (33 pets, `PetCatalog.lua:158+`): species / wing / accessory per pet are listed in `pet_groups.txt`
(first table). Event-only (Secret): phantom_kitsune, magma_cub, rime_wyrmling, hydralotl. Glow (Neon irises): aurora_fox,
moonlit_owl, nebula_axolotl, ember_phoenix, sunbeam_bear, twilight_dragon, starlight_unicorn, stormfang, eclipse_dragon,
obsidian_phoenix and the 4 event pets.

### 1.3 Colour regions (what must stay recolourable at runtime)
Palette: `makePalette :520`. P = Look.Primary, S = Secondary, E = Eye, W = WingColor (PetCatalog).
* Derived from P: Fur, Muzzle (P+cream), Stripe, Patch, Inner (pink+P), Nose, Mouth, Blush, Lash, Hoof, Nostril, Lid, LidLine.
* Derived from S: Accent, AccentDark, Belly (S+cream), EyeRing (gold+S).
* Derived from E: EyeIris (Neon when Glow), EyePupil, EyeGlint (Neon when Glow).
* Derived from W: Wing, WingTrim, WingEdge (Neon when Glow), WingVein.
* Fixed: Claw, Horn, HornRing, Gold, GoldDeep, Beak, Feet, Tongue, Tooth, Gem, GemB, Spark, Leaf, LeafDeep, Stem, Cap, CapSpot,
  Scarf, ScarfStripe, Antler, AntlerTip, Petal, PetalDeep, Pollen, Cloud, EyeShine (white), HaloGlow (Neon gold).
* Evolved and ascended: per-pet fixed accents from `EVO.Look` (Gem/GemB/Wing/Tip) and `ASC.Look` (Glow/GlowB Neon). Stormfang
  has fixed Plate/Mask/Base/Bevel/NeonBlue/NeonViolet/GemCore/GemRim (Glass).
* Hybrid add-ons: HyA/HyB/HyTip/HyHorn/HyGlow come from the Style parent's Primary, plus seed jitter.
* Every key also has auto `_Light` / `_Dark` shading (Voxel.Shade). A mesh has to bake this (geometry, vertex colours or a
  greyscale texture), because a single MeshPart.Color is flat.
* Runtime recolour cases a mesh build must support:
  1. The catalog colours: the same species body is shared by several pets (Dog: pebble_pup and waffle_corgi; Bunny: honey and
     blossom; Panda x2, Frog x2, Penguin x2, Cat x2, Fox x3, Bear x3, Owl x2, Axolotl x3, Dragon x4, Unicorn x2, Phoenix x2).
  2. The Golden / Rainbow tier copies of every pet (PetKeys `<id>@Golden`).
  3. Hybrids (any Body x any Style).
  4. Wild (a per-part HSV transform; eye parts are found by name prefix).
  5. `PB_Hue` cycling on the biggest accent parts.
  6. `PB_Pulse` transparency on Stormfang's neon parts.
  7. EvolutionFx Highlight plus scaling of every part's Size.
  So each colour class should be its own MeshPart (whose Color is set from the palette). Baking one texture per pet does
  not cover Golden, Rainbow, Wild or Hybrid.

### 1.4 Sizes (Scale 1; see `pet_groups.txt` for every pet)
Base 2.6-3.8 x 2.2-3.2 x 1.6-3.1 studs (height about 2.8; `GetHeight` default 2.8). Evolved 1: 2.8-6.2 x 3.8-5.1 x 2.5-5.7.
Evolved 2: 4.6-8.1 per axis. Scales in use: followers 1 (PetController `:229`), home pets 0.85 (`HomeFx.lua:153`), battle 1.3
x unit scale (`BattleController.lua:171`; dungeon boss pets bigger through `info.scale`), podium 1.4 (`SpotService.lua:73`),
NPC 2.2 (`NpcDialog.lua:81`), Nimbus statue 2.6 (`LobbyBuilder.lua:1690`), Stormfang showcase 3 (`StormAltar.lua:1132`);
`opts.Scale` is clamped to 0.05-40.

### 1.5 Pet models (ids)

| id | builder (file:line) | what | variants | recolour regions | size (studs, scale 1) | runtime needs | parts today |
|---|---|---|---|---|---|---|---|
| `PetBody_<Species>` x15 | `SPECIES.<S>` PetBuilder.lua:954 Cat, 1018 Dog, 1070 Fox, 1117 Bunny, 1179 Bear, 1195 Panda, 1221 Dragon, 1328 Owl, 1391 Slime, 1425 Unicorn, 1479 Phoenix, 1528 Frog, 1576 Penguin, 1619 Axolotl, 1749 Stormfang | base-stage torso, head, ears, legs, carved face (eye sockets with iris/pupil/shine/glint, nose, mouth, blush) | High / Low; catalog colours; finishes; Wild; hybrid; accessory sockets | P / S / E classes + fixed (1.3); eyes must stay separate parts whose names start with "Eye" (Wild, `CloudUI.lua:1401` detectSide, tests) | 2.6-3.4 x 2.2-3.2 x 1.6-2.5 | invisible root `Body` (PrimaryPart, 0.9x1.1x0.9); static parts get welded to the root by the consumers; hinge anchors per species: WingHinge, TailHinge, HeadC/HeadR, HeadTop, EarX, NeckY/NeckR/NeckZ, FlowerAt, HornBase (newContext `:591`) | body 165-263 (High), about 50-80 (Low) |
| `PetTail_<Species>` x13 | `newTail :884` from each SPECIES fn | tail; wags about its hinge | per species; hybrid tails (fox/cat/dragon/phoenix styles add tails) | mostly P (+ tip/stripe keys) | about 1 | parts named `Tail`, `PB_G` kind `tail`, Amp = ctx.TailWag; hinge ctx.TailHinge | 5-40 |
| `PetWing_<Style>_L` / `_R` x7 styles | `WINGS.Feather :1967`, Bat `:1985`, Fairy `:2013`, Cloud `:2031`, Crystal `:2049`, Flame `:2066`, StormCloud `:2092` (feather helper `:1954`) | wing pair (mirror images; StormCloud = the two halves of Stormfang's riding cloud) | 7 styles; W colour, Glow -> Neon edge | W classes (Wing, WingTrim, WingEdge, WingVein), Flame/Cloud fixed keys | about 1-1.5 span each | names `WingL`/`WingR`; `PB_G` kind `wing` (flap +-35 degrees at 2 Hz; PetController depends on PB_FLAP_HZ = 2.0, `PetController.lua:225`) or `cloud`; hinge ctx.WingHinge/WingSweep/WingTilt per species; L = mirrorCF(R) | 20-43 per side |
| `PetAcc_Horns/Crown/Leaf/Mushroom/Scarf/Antlers/Flower` | `ACCESSORIES.* :2177-2299` | head and neck accessories, sculpted into the body today | fit per species (anchors above); Crown also comes from `Ring.Crowned` (BattleController.lua:4838) on ANY pet | fixed keys (Gold, Gem, Leaf, Cap, Scarf, Antler, Petal...); AntlerTip Neon for Glow pets | 0.3-1 | static; merged into the body (named by key) | 5-30 |
| `PetHalo` | `ACCESSORIES.Halo :2208` (also evolved halos) | floating Neon gold ring | - | fixed Neon | 0.9 diameter | group `Halo`, kind `bob` | 4-16 |
| `PetEyeLid` (kit) | `lidBoxes :6181` | flat blink lids in front of each eye | High 3 per eye / Low 1 | Lid = P, LidLine dark | 0.2-0.4 | group `EyeLid` kind `lid`; `PB_T0`; Transparency 1 at rest; consumers EXCLUDE lids from the "animated" set and weld them | 6 (High) / 2 (Low) |
| `PetHybrid_<StyleSpecies>` x15 | `HYBRID.* :2411-2781`, placed by `applyHybrid :2793` (topAt/backAt/frontAt/sideAt surface scans) | add-on feature of the Style parent | any Body species x Style species x Seed | HyA/HyB/HyTip/HyHorn/HyGlow = Style Primary + jitter | small | static (hybrid tails replace or extend `Tail`) | in body |
| `PetGoldStar` | `goldSparkles :2969`, `sparkleStar :2957` | glowing star sparkles of a Golden copy | 4-6 placements (head, cheek, chest, wing tips) | fixed gold Neon | 0.2 | static (wing-tip stars are in wing groups) | ~6-20 |
| `PetAura_Secret` | `auraGrid :6023` | Secret rarity ring of glowing voxels | per pet colours (Secondary hue) | S-derived AuraA/B/C | about 3 ring | group `Aura` kind `orbit` | 10 |
| `PetAuraBit_<Kind>` x13 | `ASC.AuraBits :4892-4952, :5918-5923`, `ASC.Aura :4959` | second-evolution element aura pieces | Crystal, Star, Flame, Bubble, Heart, Sun, Orb, Cloud, Bolt, Shard, Wisp, Magma, Snow | Glow/GlowB per pet (`ASC.Look :4644`) | 0.3-0.6 | group `Aura` kind `orbit` (tests: `keyed(m,"Aura") >= 4`, smoke_p3_evolved.lua:168) | up to 90 |
| `PetEvolved_<petId>` x33 | `EVO.Sculpt :4567` = `EVO.Species.<S>` + `EVO.Pets.<id>` | bespoke first evolution: bigger, four-legged, gold jewellery (Necklace/Tiara/Crown/Anklets/ChestPlate `:3212-3310`), tail | High / Low; finishes; Wild (hybrids use their species design, no per-pet extra) | per pet; P/S/E + EVO.Look Gem/Wing/Tip | 2.8-6.2 x 3.8-5.1 x 2.5-5.7 | same groups (WingL/R, Tail, Halo, EyeLid) | High 913-1489, Low 195-377 |
| `PetEvoWing_<Kind>` (Fan, Bat, Flame, Shard, Ice, Rime) L/R | `EVO.Fan :3341`, `EVO.BatWing :3394`, `EVO.FlameWing :3476`, `EVO.ShardWing :4250`, `EVO.RimeWings :5796` | evolved wings | per pet colours (`ctx.WingPaint`) | W + per-pet tips | 1.5-3 span | `WingL`/`WingR` | up to 190 per side |
| `PetAscended_<petId>` x16 | `ASC.Pets.<id> :5116-5993` | second evolution: armour, crest, signature (nine tails, candy horn ...) | High / Low; finishes | per pet Glow/GlowB Neon + gold | 4.6-8.1 | groups WingL/R + Wing2L/R (not phantom_kitsune), Tail, Halo, Aura, EyeLid; Grow 1.2 | High 1472-1982, Low 413-517 |

---------------------------------------------------------------------------------------------------------------------------

## 2. Where the pet models are used (the integration surface of a pet mesh)

| Caller (file:line) | Build opts | What it relies on |
|---|---|---|
| PetController.lua:499 (followers) | Scale 1, own High / others Low, Evolved | `PrimaryPart`; `GetExtentsSize` (height/width -> slots); welds every static part to the root (`weldParts :472`, `isAnimatedPart :461` = PB_G + PB_Base, not `lid`); attributes PC_Key/PC_Stage; Animate per frame; PivotOffset |
| BattleController.lua:1356 (units) / :3084 (HUD portrait viewport) | Scale 1.3 x unit scale; Low for helpers and evolved; `Ring.Crowned :4838` adds the Crown accessory | `PrimaryPart` or `Body`; `GetExtentsSize`; `weldStatic :1148`; ShieldCube / Ice parented INTO the model (`:1629`); Highlight flash; model renamed `Unit_<id>`; GetBoundingBox for the portrait camera |
| HomeFx.lua:1410 (`buildPet :1394`, home roaming pets) | Low, Scale 0.85, Evolved | renamed `HomePet`; every BasePart's Position/Size/Transparency used to find the lowest point and the "lying" extent; `G.weld :1460` (PB_G/PB_Base, not lid); part count cached `petParts` |
| NpcService.lua:552 (NPC pets) | High, Scale 2.2 | renamed `Pet`; `extents` from parts; attribute `PetParts` = part count; NpcController.lua:414-445 waits until `countParts(pet) >= PetParts`, finds `Pet` and `Body`, welds static parts (PB_G) |
| StormAltar.lua:1132 (`buildShowcase :1126`) | High, Scale 3 | renamed `StormfangShowcase`; every part set Anchored / no collide; `PetParts`, `HoverAmp`, `Ready`; tag `NC_Showcase`; ShowcaseController welds and Animates when `PB_Rig` is present, `PB_Pulse` |
| LobbyBuilder.lua:1690 (`NimbusStatue` in `buildFountain :1633`) | cloudy_dragon Low, Scale 2.6 | GetBoundingBox, PivotTo, flags, tag EXEMPT (skipped by the material audit) |
| SpotService.lua:490 (podium) | High Scale 1.4; evolved -> Low | flags; visual only |
| CloudUI.lua:1374 (all pet viewports) | Detail/Evolved per call | ViewportFrame; `detectSide :1398` finds the face by parts whose name contains "eye"; Animate |
| MenuController.lua:420 (pre-sculpt warm-up), CareController.lua:2222-2223 (EVOLVE from/to) + EvolutionFx, DevPetShow.lua:192, TutorialController.lua:1448 (portrait) | various | EvolutionFx moves and RESIZES every part from rest offsets (`poseRig :158`, `part.Size = rest * s`) and adds a Highlight; PetBuilder.EvolutionColors |
| Dungeon wild pets and the dungeon "boss" pets | battle units (BattleController) | the server marks them `Wild = true` (BattleCatalog.lua:1707, BattleService.lua:4109), but BattleController only prints "Wild <name>" (`:3288`) and never passes `opts.Wild`. The Wild tint (`applyWild`) is used only by tests today |

Tests that read pet structure (these decide what a mesh template must look like, or must be gated to the voxel path):
* smoke_content.lua:1133-1700: WingL/WingR present and exact mirror images (:1296-1330); eye parts (`partsNamed "^Eye"` >= 4,
  shine >= 2, Glow -> Neon iris) (:1203-1213); Cloudy Dragon: 2 `^Horn` gold parts, exactly 2 `^Nostril`, >= 6 `^Eye`,
  >= 3 `Tail`, >= 6 `^Wing[LR]`, cream `^Belly` (:1429-1443); Animate flaps, mirror, no NaN, no new instances, Clone animates;
  per-pet distinct part-name+colour signatures; **"pets use no external assets": a MeshPart with MeshId/TextureID fails
  (:1243-1246)**; part caps (High 350, Low 120, evolved 1560/380, ascended 2000/520); heights 2.0-3.4.
* smoke_p3_evolved.lua: WingL/R + Wing2L/R per stage (:164), `Aura` >= 4 (:168), Magma/Basalt keys (:278, :796), caps.
* smoke_p2_fusion.lua: PB_Finish, PB_Hue, PB_Hybrid, PB_Pulse, the EyeLid name (:232).
* smoke_p5_follow.lua / smoke_p5_looks.lua / smoke_p5_home.lua / smoke_release_client.lua / smoke_p4_pets_client.lua /
  smoke_client_v2.lua: PB_Evolved, PB_Wild, PB_Detail, PB_G/PB_Base, `WingL` (:465, :1906).
* smoke_storm.lua:343 (Stormfang WingL/WingR), smoke_economy.lua:698 (podium has WingL), smoke_p2_data.lua:353 (WingL +
  <= 350 parts).
* tools/contract.json `v3.partBudget`: petHigh 350, petLow 120, petEvoLow 380, petEvo2Low 520, showcasePet 350, npcs 2600.

---------------------------------------------------------------------------------------------------------------------------

## 3. Raid bosses (BossBuilder)

Build: `BossBuilder.Build :910` -> `buildTemplate :775` (one Voxel grid per joint, `Voxel.Build` per joint into a sub-Model)
-> clone -> `registerRig :874`. 0.5 stud voxels (`VOXEL`), scale `BattleCatalog.Bosses[id].Scale`. Built on the client only
(BattleController.lua:1331 `buildUnit :1322`); `Preload` during the announcement.

Layout contract (`BossBuilder.lua:31-41`): `Model "Boss_<id>"`, `PrimaryPart = Root` (an invisible 1-stud Part at the feet, the
pivot). The joint Models are named by `Rigs[id].Order`, each with attributes `Pivot` (Vector3 studs) and `JointParent`. Parts
are named by palette key. Glow parts are found by EXACT name in `GLOW_KEYS` (Rune, Bolt, Eye, Magma, MagmaHot, Glow) and
recoloured by `SetEnraged :1310`. Effect points are Attachments `Fx_<name>` inside the nearest part of their joint (FxPoint
`:974`). There is a PointLight `BossLight` on the Fx_Core host. Model attributes: BossId, Element, Height, Radius, Detail, Scale.
Animate (`:1262`) does one BulkMoveTo of all parts from the per-joint World CFrames (rest offsets captured at build time).

| id | rig joints (`Rigs :215-262`) | sculpt | size | parts High / Low | palette (fixed; glow keys enrage-tinted) |
|---|---|---|---|---|---|
| `BossStormTitan` | Base (spinning vortex), Body, Head (child of Body), ArmL, ArmR; Fx Core/Mouth/Crown/HandL/HandR | `sculptStormTitan :323` | 22.4 x 24.5 x 10.5 | 960 / 754 | Cloud, CloudDark, Mist, Storm, Stone, Metal; Neon Rune, Bolt, Eye |
| `BossLavaGolem` | Body, Head, ArmL, ArmR; Fx Core/Mouth/Crown/HandL/HandR | `sculptLavaGolem :430` | 22.2 x 19.1 x 11.3 | 880 / 588 | Rock, RockDark, Ash, Crust; Neon Magma, MagmaHot, Eye |
| `BossFrostWyrm` | Body, WingL, WingR, Head, Jaw (child of Head); Fx Mouth/Core/Crown/Tail | `sculptFrostWyrm :516` | 20.3 x 23.0 x 12.1 | 872 / 751 | Scale, ScaleDark, Belly, Frost, Bone, Tooth; Ice Crystal, Ice Membrane (T 0.15); Neon Eye, Glow |
| `BossShadowHydra` | Body, Head1, Head2, Head3 (`hydraHead :621`); Fx Core/Head1-3/Mouth/Tail | `sculptShadowHydra :655` | 17.6 x 19.8 x 24.3 | 937 / 660 | Hide, HideDark, Belly, Spike, Fang, Claw; Neon Glow, Eye |

Variants: Detail High/Low, scale, enrage colour (runtime), poses (Idle/Windup/Attack/Basic/Enrage/Hurt/Down, per-boss
pose functions `:1013-1246`).
Tests: smoke_p3_events.lua:240-332 (every joint is a Model with Pivot/JointParent; **High 300-1000 parts**, Low < High and
<= 760; height 17-32, width <= 52; all Fx points resolve; SetEnraged recolours a Neon glow part and restores it);
smoke_p3_visual.lua:300-345 (**torso keeps >= 2 shades of a key**, the torso and the Low torso keep the `mustKeep` colour-key
part names); smoke_p3_battleclient.lua; dump_model `boss:` targets.

---------------------------------------------------------------------------------------------------------------------------

## 4. Sky dragon (Sage Dragon, client only)

`SkyDragonController.lua`: build() `:985` -> buildHead `:836`, buildBody `:849`, buildChains `:884`, buildPuffs `:914`; every
voxel piece goes through `buildPiece(grid, name, maxParts) :450` (Voxel.Build at 1 stud voxels). The model `SkyDragon` sits in
`workspace.ClientFx`. 294 parts; the dump's 509-stud height is the flight-path layout, not the size of one piece.

| id | sculpt (file:line) | instances | per piece parts | notes |
|---|---|---|---|---|
| `SkyDragonHead` | `sculptHead :284` | 1 (`Head`) | 73-80 | eyes (Eye/Pupil/Shine), horns, mane, ridge, teeth |
| `SkyDragonJaw` | `sculptJaw :332` | 1 (`Jaw`), hinged at JAW_HINGE, opens and closes | 14 | |
| `SkyDragonSegment_<R>[F]` | `sculptSegment(r, withFin) :350` | 14 (`Segment01..14`), 9 unique sculpts: R 3.0, 3.5 without fin; 4.0F, 4.5F, 3.5F, 3.0F, 2.5F, 2.0F, 1.5F | 7-13 | Scale (3 shades), Belly, BellyLine, Ridge, Fin |
| `SkyDragonLeg` | `sculptLeg :412` | 4 (`Leg1..4`, clones) | 6 | paddles |
| `SkyDragonTail` | `sculptTail :425` | 1 (`Tail`) | 11 | cloud tuft |
| `SkyDragonPuff` | `sculptPuff :443` | pool of 5 (`Puffs/Puff1..5`) | 2 | **Size rescaled and Transparency faded every frame** (`posePuffs :685`) |
| `SkyDragonChainLink` | `buildChains :884` (`Voxel.Box`) | 20 single blocks (2 Whisker chains x 4, 3 Mane chains x 4) | 1 | per-link thickness taper, alternate shade |

Runtime: one RenderStepped; `parts`/`cfs` arrays and one `workspace:BulkMoveTo` (`FireCFrameChanged`); no instances created
while flying; every part Anchored with CanCollide, CanTouch, CanQuery and CastShadow off. Colours are fixed (`makePalette :174`).
Tests: smoke_client_v2.lua:1722-1780 (**60 <= parts <= contract skyDragon 300**, flags, flies, BulkMoveTo used, no new
instances, frozen when far).

---------------------------------------------------------------------------------------------------------------------------

## 5. NPCs (NpcService)

`buildNpc :532` builds `Model "Npc_<Id>"` in `workspace.NimbusNpcs`, tagged `NC_Npc`, with attributes NpcId, NpcName, Title,
Accent, PetId, PetParts and Ready. Children:

| id | builder | what | variants | colours | size | runtime needs | parts |
|---|---|---|---|---|---|---|---|
| `NpcPedestal` | `sculptPedestal(seed) :291`, `buildPedestal :370` (Voxel.Build at PV 0.4; it already has a plain-Part fallback branch when Voxel is missing) | stepped stone plinth, tile band, gold rivets, gold plaque, moss clumps, patterned rug cushion, tassels, flowers | 6 (seed = moss/flower placement, accent colour) | Rug/RugTop/RugTrim/RugCenter from the NPC Accent (`pedestalPalette :267`); stone/gold/moss/petal fixed | about 8.5 diameter x 2.8 tall | static, CanCollide false (the Collider handles collision); `PEDESTAL_TOP` defines where the pet hovers | 100-107 |
| NPC pet | PetBuilder (reuses `PetBody_*`) | aurora_fox, frostling_penguin, sleepy_owl, waffle_corgi, bamboo_panda, nebula_axolotl (`NpcDialog.lua:393-484`) | Scale 2.2, High | catalog | about 6-7 tall | renamed `Pet`; `PetParts`; welded and idled by NpcController | 285-342 |
| `Collider` (keep as an invisible Part) | `:584` | invisible collidable cylinder | - | - | - | CanCollide true | 1 |
| `PromptPart` (keep) | `:599` | invisible anchor: BillboardGui `Nameplate`, PointLight `Glow`, Attachments `PromptAnchor` (ProximityPrompt `TalkPrompt`, attribute NpcId) and `RugSparkles` | - | - | - | NpcController finds `PromptPart`, `TalkPrompt`, `Nameplate`, `Badge` | 1 |

Total `npcs` dump: 2502 parts (contract npcs 2600).

---------------------------------------------------------------------------------------------------------------------------

## 6. Stormfang (StormAltar showcase)

`StormAltar.buildShowcase :1126` = `PetBuilder.Build(stormfang, High, Scale 3)` (343 parts) -> `StormfangShowcase` with
PetParts, HoverAmp, Ready and tag `NC_Showcase`, plus a separate invisible `ShowcaseCollider` cylinder. It reuses
`PetBody_Stormfang` + `PetWing_StormCloud_L/R` (cloud halves, kind `cloud`) + `PetTail_Stormfang` + lids. The neon
parts carry `PB_Pulse`. Fixed colours: charcoal plates in 3-4 greys, white mask, Neon blue stripes and claws, Neon violet,
cyan diamond gems with a Glass rim, dark navy cloud. smoke_content.lua:1490-1530 checks these by colour and name, and
smoke_storm.lua checks the rest. The altar island, ring, portal, crystals and bridge belong to the world inventory, not here.

---------------------------------------------------------------------------------------------------------------------------

## 7. Tokens (TokenLook)

`TokenLook.Build(opts) :198`. The root Part IS the coin: its name is the palette Name (`CloudToken`, `GoldenCloudToken`,
`CashCoin`, `GoldenCashCoin`). It is the 9x9 core block, Neon rim, **CanTouch = true** (TokenService pickup through `Touched`
at `TokenService.lua:452`, plus a radius poll as backup). The other children are welded with WeldConstraint (`addPiece :158`):
RimWide, RimTall, Face (or FaceWide + FaceTall for the Golden octagon), CloudBase and CloudPuff. `Halo` is an ANCHORED,
UNWELDED Ball that TokenFx finds by name and bobs (`TokenFx.lua:52`, smoke_hazards.lua:714). Also PointLight `TokenLight` and
ParticleEmitter `Sparkles`.

| id | variants | colours (fixed per palette) | size | parts |
|---|---|---|---|---|
| `TokenCoin` (rim + face + emblem; Golden octagon face) | palettes Cloud (scale 1), Golden (1.5, octagon), Cash (1), GoldenCash (1.15); opts.Scale; Phase | Rim Neon, Face SmoothPlastic, Cloud emblem (`Palettes :71-154`) | 3.5 studs across x 0.96 thick at scale 1 (voxel 0.32) | 5-6 |
| `TokenHalo` | HaloScale 1 / 1.2 | Glow Neon, T 0.82-0.86 | 5.4 diameter | 1 |

Users: TokenService.MakeTokenPart `:207` (tags CloudToken/GoldenToken, attributes Value/Golden/Collected; the collect effect
tweens Transparency and CFrame of every descendant `:334-354`). HomeFx.lua:2632 Cloud Cash coins (pooled, dimmed copies,
CanTouch false, Halo off). CourseBuilder.lua:1333 still has its own Neon `CloudToken` Part (course item, other inventory).

---------------------------------------------------------------------------------------------------------------------------

## 8. Battle props (BattleController, client)

| id | file:line | what | runtime | parts |
|---|---|---|---|---|
| `BattleShieldCube` | `Units.UpdateStatus :1629` | ForceField-material block around a shielded unit, spins | parented INTO the unit model (weld-free, CFrame per frame); size h*1.25 | 1 |
| `BattleIceCrystal` | `:1654-1675` | 5 Glass crystals around a stunned unit (`Ice` Model, attribute Angle) | per frame CFrame | 5 |
| `BattleFocusArrow` | `:6419-6435` | 3 stacked Neon gold slabs over the locked target (attribute Y) | per frame CFrame | 3 |
| Battle FX pool | `Fx.Part :467` (`BattleFx`, max K.MAX_FX_PARTS) | telegraph fills, hit sparks: pooled Neon blocks, recoloured and resized | FX, not models | pooled |
| units | `buildUnit :1322` | pets (PetBuilder) and the raid boss (BossBuilder) | see sections 2 and 3 | - |

---------------------------------------------------------------------------------------------------------------------------

## 9. FX and small client-built bits found while tracing (low priority; another inventory may own them)

* EvolutionFx.lua `buildEffects :209` via `effectPart :117`: EvolveRune (ground ring blocks), EvolveMote, EvolvePillar
  (Cylinder), EvolveFlash (Ball), EvolveShock, EvolveSpark, EvolveConfetti; Highlight `EvolveGlow`, light, sparkles. All are
  resized and recoloured per frame. Candidate `EvoFxKit` (rune, spark cube, confetti) or keep as FX.
* HomeFx: `WelcomeHeap` (`G.buildHeap :1914`, core + 46 coins, <= 48 parts), FlyingCoin (`:1850`), Zzz (`:1993`), HomeBit
  puffs (`:2773`), Train rows (`:3193`), ScoopRing (`:3324`), plus the invisible ScoopLabel anchor.
* TutorialController `buildArrowModel :2013`: golden `GuideArrow` (Voxel.Build, MaxParts 110, with a plain-Part fallback)
  -> candidate `TutorialGuideArrow`.
* FusionController.lua:1597/1613: fusion FX parts.

---------------------------------------------------------------------------------------------------------------------------

## 10. Integration note: the smallest seams for `MeshLibrary.Get(id)`

### 10.1 Pets: one seam in PetBuilder.Build (covers about 20 callers)
`PetBuilder.Build :6772-6806` today does:
```lua
local bp, bpKey = getBlueprint(look, detail)   -- sculpt (cached)
local tpl = getTemplate(bp, bpKey, scale)      -- instantiate (cached)
local model = tpl:Clone()
```
Replace it with "try the mesh template first; otherwise use the voxel template":
```lua
local tpl = MeshPets and MeshPets.Template(look, detail, scale)   -- nil when any needed asset id is unset / not loaded
if not tpl then local bp, bpKey = getBlueprint(look, detail); tpl = getTemplate(bp, bpKey, scale) end
local model = tpl:Clone()
```
Everything after that stays shared: sparkles, `PB_Evolved`, `applyWild`. The mesh template has to emit the SAME contract as
`instantiate :6297`:
* an invisible root `Body` (PrimaryPart);
* parts named `WingL`/`WingR`/`Wing2L`/`Wing2R`/`Tail`/`Halo`/`Aura`/`EyeLid` with `PB_G` + `PB_Base`, and `PB_T0` on the lids;
* the model attributes `PB_Rig`, `PB_Scale`, `PB_Detail`, `PetId`, `PB_Seed`, `PB_Finish`, `PB_Hybrid`;
* eye parts whose names start with `Eye` (EyeIris/EyePupil/EyeRing for Wild, EyeShine/EyeGlint kept);
* `PB_Pulse` / `PB_Hue` on the right parts;
* the flags of `flagPart`.

If it does, Animate, every consumer weld routine, EvolutionFx, viewports, NPC readiness (`PetParts` is computed) and the Wild
tint all work unchanged. The hinge CFrames (WingHinge/Sweep/Tilt, TailHinge, HaloAt, AuraAt, Wing2Hinge) are computed today
inside the SPECIES/EVO/ASC sculpt functions. They should be exported once (a small Lua -> JSON dump per look, through
`dump_model.lua`) into the Blender scripts and the mesh manifest, so meshes and hinges agree. Cache keys must include "mesh vs
voxel", so a template built before the meshes arrived is not reused afterwards.
`GetHeight :6878` builds through Build, so it follows automatically.

### 10.2 Bosses: `buildTemplate :775`
Keep `Build`/`registerRig`/`Animate`/`SetEnraged`/`FxPoint` as they are. A mesh `buildTemplate` returns the same tree: `Root` +
joint Models named per `Rigs[id].Order`, with `Pivot`/`JointParent`, MeshParts named by colour key (glow parts named exactly
Eye/Glow/Bolt/Rune/Magma/MagmaHot so `GLOW_KEYS` matches), `Fx_*` Attachments placed from the same `Rigs.Fx` voxel coordinates
(`vec3(fx[2], vs)`) under the nearest part of the joint, `BossLight`, and the model attributes. Rig pivots are in voxels x 0.5 x
scale; the Blender export must use the same origin (feet centre, facing -Z).

### 10.3 Sky dragon: `buildPiece :450`
It returns (Model, parts) per piece. A mesh version returns MeshPart pieces with the same local pivot convention; `addParts`,
the trail posing and BulkMoveTo are untouched. Chain links (`Voxel.Box :1372` calls in `buildChains`) -> clone one link mesh.
Puffs are resized every frame, which MeshParts allow.

### 10.4 NPC pedestal: `buildPedestal :370`
It already branches (`if not Voxel then` plain plinth). Add a branch that clones `NpcPedestal` (setting the rug region's
Color from the accent) and returns `Model "Pedestal"`. `PEDESTAL_TOP` must match the mesh's top surface.

### 10.5 Tokens: `TokenLook.Build :198`
Clone a `TokenCoin` template whose ROOT is a MeshPart with the palette Name, CanTouch true and the same size class (the
Touched hitbox), Neon rim region recoloured per palette; the face/emblem are welded children; a `Halo` child stays an
anchored, unwelded ball named `Halo`. TokenService / TokenFx / HomeFx do not change.

### 10.6 MeshLibrary itself (suggested shape)
* `Config.Meshes[id] = ""` (empty = not uploaded: fall back). Ids written by the upload tool, following the ART RULE "Mesh asset
  ids live in Config".
* Server boot: for every non-empty id, `InsertService:LoadAsset(id)` (needs the asset to be owned by the place's creator) ->
  put the template under `ReplicatedStorage.MeshLibrary/<id>`. `Get(id)` = `FindFirstChild(id)` + `:Clone()`, or nil. It must
  NEVER yield inside PetBuilder.Build, which is synchronous and runs in RenderStepped-adjacent code and in viewports.
* In the smoke mock there is no LoadAsset and no ids are set, so every builder takes today's voxel path and all current tests
  stay green with no change.

---------------------------------------------------------------------------------------------------------------------------

## 11. Risks (ordered)

1. **MeshId cannot be set from a script at runtime.** Templates have to come in as assets: InsertService:LoadAsset on the
   server, for Model assets owned by the experience creator; or AssetService:CreateMeshPartAsync (check that it is available
   and what permissions it needs); or MeshParts saved into the place file. MeshParts produced by Rojo from only a MeshId may
   lack the physics and InitialSize data (check this). Client-only builders (PetController, CloudUI, HomeFx, BattleController,
   SkyDragon) need the templates already replicated in ReplicatedStorage; before that they must fall back without
   flickering. Possibly add a rebuild when the library becomes ready.
2. **Recolouring and shading.** A single baked texture per pet (the `blender/pebble_pup.py` approach: one mesh plus a colour
   texture) cannot do the catalog colour sharing per species, Golden, Rainbow (with hue cycling), Wild, Hybrid seeds or the
   `_Light`/`_Dark` shading. Each colour class needs its own MeshPart (Color set at runtime), with shading baked into geometry
   or a greyscale map. Check how SurfaceAppearance and vertex colours interact with MeshPart.Color in Roblox before choosing.
3. **Animation needs separate pieces.** Wings L and R are mirror images: Roblox cannot mirror a MeshPart with negative scale, so
   L and R are two assets each. The same goes for tail, halo, aura bits, wing pair 2 and lids. The hinge offsets must match
   the Lua rig. The one-piece pup in `blender/pebble_pup.py` has no separate wings, so it would not flap.
4. **Tests that will fail on the mesh path** (they pass while no ids are set):
   * smoke_content.lua:1243 forbids MeshPart/SpecialMesh asset ids in pets.
   * smoke_content.lua: Cloudy Dragon counts by part name (2 `^Horn`, exactly 2 `^Nostril`, >= 6 `^Eye`, >= 3 `Tail`,
     >= 6 `^Wing[LR]`), and eyes >= 4 with shine >= 2.
   * smoke_p3_events.lua:268 requires boss High >= 300 parts.
   * smoke_p3_visual.lua:323 requires the boss torso to have >= 2 shades of one key.
   * smoke_client_v2.lua:1745 requires sky dragon >= 60 parts.
   * tools/contract.json part budgets.
   * **tools/check.mjs `asset-id` rule** (`:24`, `:138`, `:466-470`): any `rbxassetid://` string outside Config is an error,
     and inside Config only `Config.Art.StormfangImage` is allowed. A `Config.Meshes` table, or the upload tool's output, breaks
     the static check until the rule is widened.
   * `tools/dump_model.lua:225-250` / render_model.py draw only Part, Wedge and Ball shapes. MeshParts would render as boxes,
     so the visual tooling needs a mesh-aware path (for example reading the source FBX/OBJ from `blender/`).
   * The mock's MeshPart (`robloxmock.lua:3798`) has no LoadAsset or CreateMeshPartAsync. Testing the mesh path needs a
     test-only fixture template, not a fake upload.
5. **Volume of art.** 15 species bodies, 13 tails, 14 wing meshes, 8 accessories, 15 hybrid add-ons, 33 bespoke evolved forms
   (+ about 12 evolved wing meshes), 16 bespoke second evolutions (+ wing pairs, crests, 13 aura-bit kinds), 4 bosses (19 joint
   meshes), sky dragon (about 15), pedestal, token: roughly 200+ mesh assets, each with High and maybe Low LODs. Roblox
   RenderFidelity/LOD may replace the Low builds. Upload quotas and moderation delays apply, and each mesh is limited to
   20k triangles (pebble_pup targets 15k). The fallback is per model and must stay (the rule allows mixing while ids arrive).
6. **Accessories and hybrids are placed by sculpt-time anchors and surface scans** (HeadTop, EarX, NeckR, FlowerAt, HornBase;
   `topAt`/`backAt`/`sideAt` in applyHybrid). Meshes need per-species attachment points (for example Attachments named
   `Acc_Head`, `Acc_Neck`, `Acc_Flower`, `Hy_Tail`, `Hy_Cheek`...) in each body mesh. `Ring.Crowned` puts the Crown on ANY
   species.
7. **Part-count driven code still works but its meaning changes.** NPC `PetParts` readiness and HomeFx `petParts` are computed
   from the build, so they stay consistent. EvolutionFx resizes parts (works for MeshParts). HomeFx's "lying" extent uses part
   boxes: MeshPart boxes are looser, so pets might float or sink slightly.
8. **Wild is unused at runtime.** The dungeon's Wild flag never reaches PetBuilder (BattleController only renames the HUD
   label). Decide whether the mesh path implements Wild (an easy per-region recolour) or the gap is fixed first.
9. **Character of the eyes.** The voxel eyes are carved one voxel deep with highlight voxels, and blink lids sit exactly over
   them. Mesh eyes need separate eye pieces (for Glow Neon irises, the Wild recolour, the name-based tests and CloudUI face
   detection) plus lid meshes that fit them.
10. **Collision and touch semantics** that must survive the swap: the token root's CanTouch hitbox; the NPC Collider and the
    ShowcaseCollider are invisible Parts (keep them as Parts: they are not visible models); everything else in creatures is
    non-collidable. The boss test requires `not CanCollide and not CanQuery`.
