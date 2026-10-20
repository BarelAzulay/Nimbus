# Phase 6 pipeline prototype: the fine-voxel Blender kit ("nvox")

Everything here is a PROTOTYPE in the design scratchpad (`p6design/pipeline/`). The build waves move `kit/` into
`nimbus-climb/blender/kit/` (and `kit/lua/MeshKit.lua` into `src/shared/` when the loader is built). Nothing was
uploaded and nothing in the repo was touched.

## 1. What the kit does (one command per model)

```
/tmp/claude-0/bpyenv/bin/python kit/build_pet.py --pet pebble_pup --height 40 --wing Feather --acc Crown --out OUT
/tmp/claude-0/bpyenv/bin/python kit/build_pet.py --pet pebble_pup --height 25 --tag _low --out OUT     # Low LOD
/tmp/claude-0/bpyenv/bin/python kit/build_prop.py portal --K 2 --color 226,150,74 --stars 3 --out OUT
/tmp/claude-0/bpyenv/bin/python kit/build_prop.py cloud --K 1.5 --out OUT
python3 kit/build_pet.py --pet mallow_kitten --K 1.4 --out OUT --no-export     # numbers only, no bpy (0.5 s)
python3 kit/manifest_to_lua.py OUT/pet_dog.manifest.json > pet_dog.lua          # manifest -> Lua table
python3 kit/compare.py sheet.png "today" ref.png "kit" preview.png               # side-by-side sheets (Pillow)
```

Per model it writes `<model>.fbx`, `<model>.manifest.json`, an assembled preview PNG (4 views, Cycles CPU) and a
summary JSON. A pet build is three models: `pet_<species>` (body + `Tail_` + `Lid_` parts), `wing_<style>`
(`WingL_` / `WingR_` parts, hinge-local) and `acc_<name>` (pivot = the species' `Hat` attachment). ~13 s per pet
with renders, 0.5 s without.

| step | module | notes |
|---|---|---|
| sculpt | `nvox/grid.py` (VoxelGrid) | dense numpy port of `shared/Voxel.lua` shapes (Ellipsoid, Box, RoundBox, Torus, Cone, Capsule, Curve; Add / Carve / Paint, OnlyKeys, KeepExisting, Pattern, Rotation = `CFrame.Angles` maths, Pivot, Bias 0.25 voxel). Shapes are in DESIGN units scaled by `K` (voxels per design unit), exactly PetBuilder's `scaled()`. `fill_pockets` fills enclosed air and 1-voxel pits / tunnels (they render as black specks) except next to carved face features. |
| species | `nvox/pets.py` | Dog, Cat, Dragon ported line by line from PetBuilder (same design coordinates, so today's proportions), palette as RECIPES (makePalette + species overrides + cuteEyes). New: procedural eyes (lash rim, pupil, lighter iris, two highlights, glint row, carved 1 voxel deep), snapped face lines (mouth, toe gaps), nose shine, dragon smile with tongue + tooth nubs + horn rings, dog cowlick + cheek tufts, feather shafts + scalloped coverts, crown rim + studs. |
| catalog | `nvox/catalog.py` | reads every `Look` straight from `src/shared/PetCatalog.lua` (regex; 33 pets) |
| shade | `nvox/shade.py` | vectorised Voxel.Shade (normal from the empty neighbourhood, light tops / dark undersides / creases, Jacobi smoothing) + an optional 4th "deep crease" level; neighbourhood radius scales with K so finer grids keep smooth bands |
| mesh | `nvox/mesher.py` | outer faces only (faces between two different regions are culled too), greedy 2D merge per plane per (part, vertex colour) label, CCW winding, translucent voxels only emit towards empty space |
| parts | `nvox/build.py` | regions -> MeshPart objects (section 3), group prefixes, tail hinge snapped to the body lattice and the tail voxels inside the body removed (no coplanar / z-fighting faces) |
| Blender | `nvox/blend.py` | objects + CORNER byte colour layer `Col`, FBX export (Roblox doc settings), re-import check (round trip + RAW axes), Cycles preview |
| manifest | `nvox/manifest.py` | JSON per model (section 4) |
| props | `nvox/props.py`, `build_prop.py` | the Phase 4 portal (7aa0df2) and a cloud platform |

## 2. Units, axes, scale (checked, not assumed)

* Manifest numbers are ROBLOX space: +X right, +Y up, -Z forward, studs, relative to the model pivot. A pet's pivot
  is PetBuilder's invisible root `Body` = design (0,0,0); 1 design unit = 0.1 stud (PetBuilder `VOXEL`).
* In Blender the kit writes `blender = (-x, z, y)` (front = -Y, Blender's convention) and exports with Roblox's
  documented Blender settings (create.roblox.com/docs/art/blender): Unit System None, scale 1 (1 BU = 1 stud),
  Apply Scalings = FBX Unit Scale, Forward = Z, Up = Y.
* `verify_fbx` re-imports every FBX twice: a round trip (names, triangles, colour layer, positions) and a RAW read
  (Blender 5.2's importer with forward Y / up Z = no conversion) whose coordinates must equal the manifest's Roblox
  studs. All 12 FBX: max error 0.0 studs, triangle counts identical, colour layer present (`verify` block in each
  manifest).
* Blender 5.2's FBX importer is the new C++ one: no `apply_unit_scale` option; the kit uses `global_scale=1`.
* Still to confirm in Studio / Open Cloud (no key yet): that an Open Cloud "Model" upload of this FBX lands at
  1 BU = 1 stud and keeps the vertex colours. Self-healing either way: the loader sets every MeshPart's `Size` from
  the manifest (MeshParts rescale), so only a 180-degree yaw error would survive; the first real upload must be
  eyeballed (open question 1).

## 3. Runtime recolour: region parts + vertex colours (decision)

Research: Roblox renders imported FBX vertex colours and MULTIPLIES them with `MeshPart.Color` (DevForum staff
article "Vertex Colored Meshes using Blender and Studio", 2024-07; the official Blender page shows a vertex-painted
mesh in Studio). And `Voxel.Darken` is a pure per-channel multiply `(1-0.1575, 1-0.15, 1-0.1125)`.

So, per pet:
* one MeshPart per colour REGION (PetBuilder palette key; `Fur` -> `Primary`, `Accent` -> `Secondary`,
  `EyeIris` -> `Eye`, `EyePupil` -> `Pupil`, `EyeShine` -> `EyeWhite`, the rest keep their key: Belly, Muzzle, Ear,
  Stripe, Inner, Nose, Mouth, Blush, Lash, Toe, Scale, Horn, ...). Vertex colours: base shade WHITE, dark shade the
  exact Darken factor, deep crease the factor squared. Loader: `Color = recipe(Look)` -> today's base and dark
  shades exactly, for any pet of that species.
* `<Region>_Light` = a second MeshPart (Voxel.Lighten is a lerp towards warm white, NOT a multiply, so it cannot
  be a vertex colour without darkening pale pets ~12%: rejected). Loader: `Color = shadeLight(recipe(Look))`.
* constant colours (eye whites, nose shine, claws, tongue, the dog's nose, crown gold, gems) share ONE part
  `Fixed` with the real colours baked into the vertex colours (`Color` = white).
* Neon / translucent regions are their own parts (`Glow`, `Swirl`, star gems, a Glow pet's `Eye`).
* Rejected alternatives: one part per shade without vertex colours (3x the MeshParts and assets); one baked mesh
  per catalog pet (no recolour for Golden / Rainbow / hybrids / Wild, 3x the uploads); textures (no recolour,
  extra image assets).
* Result: a High pet = 20-22 body parts + 14 wing parts + 1 crown = ~37 MeshParts instead of today's ~290-340
  Parts.

## 4. Manifest (contract between kit, uploader and loader)

`<model>.manifest.json`: `model`, `kind`, `fbx`, `voxelStuds`, `K`, `shading` (dark / deep factors, light rule),
`bounds`, `tris {total, parts, maxPerPart}`, `parts[]` (`name` = the FBX object / MeshPart name, `group` (Body /
Tail / Lid / WingL / WingR / Accessory / Gate / Pad / Detail / Cloud), `region`, `shade`, `center`, `size`,
`tris`, `material`, `color` = recipe | `["shadeLight", recipe]` | `"vertex"`, `transparency`), `regions`
(recipe, parts, keys, previewColor), `attachments` (CFrames: `pos` + 3x3 `rot`; pets: WingL, WingR (with the rest
tilt / sweep), Tail, Hat, Flower, Neck, HeadCenter, EyeL, EyeR, HornBase (dragon), Ground), `groups` (Tail hinge +
wag amp, Lid = blink lids hidden by default, WingL/WingR flap, portal Stars lit / off), `stats`, `meta`,
`verify`, `previewLook`. `manifest_to_lua.py` turns it into a Lua table (checked to load under LuaJIT); asset ids
stay in `Config.MeshAssets` (ART RULE) and the loader falls back to the Part builders when an id is missing.

Colour recipes (`nvox/colors.py`, mirrored in `kit/lua/MeshKit.lua`): `["Primary"|"Secondary"|"Eye"|"WingColor"]`,
`["rgb",r,g,b]`, `["mix",A,B,t]`, `["lighten",A,t]`, `["darken",A,t]`, `["cuteIris"|"cutePupil"|"cuteLash",A]`,
`["ifLum<",A,th,THEN,ELSE]`, `["shadeLight",A]`.

## 5. Triangles and the voxel size (pets, High = body + tail + lids; wing and crown separate)

| grain (voxels tall, K) | dog body | cat body | dragon body | Feather wings (pair) | Crown | pet total (dog) |
|---|---|---|---|---|---|---|
| today's game 29 (K 1.0) | 2412 | 2688 | 2646 | 524 | 556 | 3.5k |
| 32 (K 1.10) | 2910 | 3298 | 3308 | 680 | 636 | 4.2k |
| **40 (K 1.38) - picked for High** | **4476** | **4858** | **4638** | **1036** | **632** | **6.1k** |
| 48 (K 1.66) | 6346 | 6638 | 6668 | 1670 | 1210 | 9.2k |
| **25 (K 0.86) - Low LOD** | **1958** | **2186** | **2034** | **586** | **392** | **2.9k** |

* Tris grow ~K^2 (the staircase of a voxel curve is real geometry); shading costs only 3-5% (shaded vs flat
  measured); greedy rectangles are within a few % of an optimal polygon triangulation for these shapes, so the
  only real levers are the grain and LODs. Max per MeshPart 2.7k (limit 20k).
* 32 tall meets the <= 4k aim but is barely finer than today (29) - not what the player asked for. 48 is ~9k per
  pet. 40 tall is visibly finer, eyes / mouths / toes read well, ~6k per High pet (today's Part pets are ~290-340
  parts = ~3.5-4k box triangles and 290+ instances, so the instance count drops 8x).
* Recommendation: High 40 tall for the local player's own pets, viewports, podiums / NPCs; Low 25 tall (~2.9k incl.
  wings + crown) for other players' followers and far pets (the same split PetBuilder has today). Worst case 16
  players x 3 pets: 3 High + 45 Low ~ 150k triangles. Set `RenderFidelity = Precise` (Roblox's automatic mesh LOD
  would melt the crisp voxel edges) and switch High/Low ourselves.
* Low at 25 tall loses eye detail (procedural eyes need ~6 voxels); a hand pixel-mask fallback for small K is a
  build-wave item.

## 6. Looks (>= 3 rounds, compared against `tools/render_model.py` renders of the current Part pets)

* `out/r2/cmp_dog.png`, `cmp_cat_dragon.png`, `cmp_dragon.png`: round 1 (K 1.4) vs today - shapes / colours match;
  lighting too grey, grainy.
* `out/r3/cmp_heights.png`: today vs 32 / 40 / 48 tall (calibrated light, sky background).
* `out/r4/round3_all.png`: dog, cat, dragon at 40 tall with Feather + Crown (crease / deep AO shading, snapped toe
  gaps, cowlick + cheek tufts).
* `out/r5/zoom_side.png`: black specks fixed (pits / tunnels filled; tail voxels inside the body removed).
* Final: `out/final/*_preview.png`, `out/final/lod_compare.png` (High vs Low).
* World: `out/props/cmp_portal.png` (the 7aa0df2 portal vs the kit's), `out/final/prop_portal_preview.png`
  (brick courses + mortar on the pillars, two-tone spiral swirl, gold studs on the ring, faceted keystone gem,
  crisp diamond star gems (3 lit), bevelled tiled ready pad with a glowing diamond, lanterns),
  `out/final/prop_cloud_platform_preview.png`.

## 7. Props: the portal and a cloud platform

* `prop_portal` = gate (0.5-stud voxels, was 1 stud) + `Pad_` (0.25-stud tiles, voxel boundaries on stud lines via a
  half-voxel shift) + `Detail_` (0.25 stud: lanterns, keystone gem, star crest). 7.2k tris, 18 parts. Tint per
  difficulty: `Trim` / `Glow` / `Swirl` / pad glow / lamp follow `Look.Primary` = `Config.Difficulties[i].Color`;
  `Detail_Star1..5` lit (gold Neon) or off (StarOff) per difficulty stars. Pivot = pad centre; gate 9.5 behind, as
  in buildPortal. Gameplay parts stay Parts: the invisible `Zone_<Id>`, billboard anchor, colliders.
* `prop_cloud_platform`: 24 x 20 studs at 2/3-stud voxels, lobby cloud shades baked (CloudLight / Cloud /
  CloudShade / Mist / MistDark), 3.3k tris, 1 part.
* Collision rule for the build waves: meshes are visual (`CanCollide = false`); walkable / blocking geometry keeps
  invisible Part colliders (exact, cheap, and the fallback path already has them).

## 8. Open questions / risks for the build waves

1. First real upload (needs the player's OK, `ROBLOX_API_KEY` / `ROBLOX_CREATOR_ID` in a new session): confirm an
   Open Cloud `Model` upload (FBX, arrives as a package Model of MeshParts) keeps object names, vertex colours,
   1 BU = 1 stud and the facing. Do ONE pet first and look at it in Studio before batch uploads.
2. Loading: `InsertService:LoadAsset` works only for assets the game's owner owns (creator = the experience
   owner); templates parked in ReplicatedStorage for clients (MeshKit prototype). Alternative: commit downloaded
   `.rbxm` templates through Rojo - decide in the loader design.
3. Animation: PetBuilder.Animate rebuilds poses from PB_G / PB_Base attributes; the loader must write the same
   attributes (groups Tail / WingL / WingR / Lid with hinge CFrames from the manifest) so `Animate`, PetController,
   HomeFx etc. keep working unchanged.
4. Golden / Rainbow finishes, hybrids, Wild tints: recipes cover recolour; hybrids add OTHER species' features
   (ears, tails, horns) - needs per-feature attachable meshes or stays on the Part path for now.
5. Evolved forms (EVO.*, thousands of Lua lines) and the other 12 species / 6 wing styles / 7 accessories are not
   ported. Two routes: port by hand to `nvox/pets.py` (the face detail needs it), or a lupa bridge that runs
   PetBuilder at a finer K and exports its grids (shapes 1:1, but faces are fixed-pixel masks: they shrink at
   K > 1). Recommendation: port bodies, reuse this kit's procedural faces.
6. Accessories are species-independent meshes placed at `Hat`; PetBuilder sculpted some into the head (Crown band
   fill) - check per accessory. The dragon's `Horns` accessory (twilight / cloudy dragon) is not in the prototype
   (the previews wear a Crown for the test).
7. T-junctions from greedy quads can show 1-pixel sparkles on some GPUs; if seen in Studio, add a T-junction fix
   pass (splits edges, +10-20% tris).
8. Instance count: ~37 MeshParts per High pet (14 are the two wings: Light + region parts per side). If draw calls
   matter more than exact light shades, wings could bake their colours (`Fixed`-style, 2 parts) since WingColor is
   one Look colour per pet.
