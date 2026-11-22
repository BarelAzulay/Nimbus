# Evolved eyes re-bake: upload hand-over (98 evolved body meshes)

Pitch 2 item 7, option A "Trim" (spec `docs/superpowers/specs/2026-11-20-pitch2-build-design.md` item 7, plan Task 12).
Owner's decision 2026-11-20: re-bake the evolved pet meshes in Blender so the trimmed eyes show in game, and prepare
the upload (not do it). This file is the hand-over for the owner's keyed cloud session.

**Status: PREPARED, NOT UPLOADED.** Nothing was sent to Roblox from the PC. `src/shared/MeshIds.lua`,
`src/shared/MeshManifests/` and `blender/meshes.json` on this branch are unchanged, so the game keeps the live meshes
(the old 8 x 9 eyes) until the upload session lands the new manifests and the new ids together.

**This list replaces the one of `5cb4b2e`.** Its look review found the Low eye in the wrong place on 20 of the 49
`_low` keys, fixed and rebuilt here:

- **Where the Low eye sits.** `faces.low_eye_specs` centred the 4 x 4 Low eye on a point that reads the 8-wide High
  mask as design units at the coarse Low grid. 16 first evolutions sat 0.9 to 1.4 Low voxels inside the High eye,
  with one voxel column between the eyes (Pebble Pup: High eye 0.36-0.84 studs from the centre line, Low eye
  0.08-0.69), so the pet read cross-eyed and the nose touched both eyes; 4 second evolutions sat 0.81 voxel outside.
  Fix `332c9d3`: the Low eye is placed against the High mesh's eye in studs (`faces.low_eye_place`). It keeps at
  least half the High eyes' spacing and, among those columns, sits nearest the High eye's centre; a column that would
  hang off the head is not used. Fix `0fee5de`, the same cause on the other axis (the review measured only across):
  26 Low eyes also sat 0.6 to 1.1 Low voxels below the High eye (the owls' eye covered the gold ring under it); the
  row is now the one nearest the High eye's centre. 43 `_low` keys change (table below); the eye pixels are the same.
- **The 4 second evolutions found 0.81 voxel outside** (Aurora Fox, Magma Cub, Phantom Kitsune, Sunbeam Bear) keep
  their column, by choice (their row moved up): one column in leaves a single gap column with the nose against both eyes (0.22 studs
  between the eyes against the High 0.53), the same fault as the 16 pinched keys (`evo_eyes/low_placement_1..3.png`).

Earlier rounds, still in this list: the Low meshes carve the game's own Low eye whole (`4071cbd`, after the `76cee35`
review: the owls' eyes had vanished, Stormfang's was a jumble) and every key keeps its pre-trim voxel grid (`3a9eb85`).

Changed against the `5cb4b2e` list: 43 keys, all `_low`: `evo1_aurora_fox_low`, `evo1_bamboo_panda_low`, `evo1_biscuit_bear_low`, `evo1_blossom_bunny_low`, `evo1_bubble_axolotl_low`, `evo1_candy_unicorn_low`, `evo1_cherry_panda_low`, `evo1_cloudy_dragon_low`, `evo1_ember_phoenix_low`, `evo1_frostling_penguin_low`, `evo1_honey_bunny_low`, `evo1_hydralotl_low`, `evo1_magma_cub_low`, `evo1_mallow_kitten_low`, `evo1_maple_fox_low`, `evo1_mochi_slime_low`, `evo1_nebula_axolotl_low`, `evo1_obsidian_phoenix_low`, `evo1_pebble_pup_low`, `evo1_phantom_kitsune_low`, `evo1_pip_penguin_low`, `evo1_puddle_frog_low`, `evo1_shroomie_frog_low`, `evo1_starlight_unicorn_low`, `evo1_storm_tabby_low`, `evo1_stormfang_low`, `evo1_sunbeam_bear_low`, `evo1_waffle_corgi_low`, `evo2_aurora_fox_low`, `evo2_candy_unicorn_low`, `evo2_cloudy_dragon_low`, `evo2_eclipse_dragon_low`, `evo2_ember_phoenix_low`, `evo2_hydralotl_low`, `evo2_magma_cub_low`, `evo2_moonlit_owl_low`, `evo2_nebula_axolotl_low`, `evo2_obsidian_phoenix_low`, `evo2_phantom_kitsune_low`, `evo2_rime_wyrmling_low`, `evo2_stormfang_low`, `evo2_sunbeam_bear_low`, `evo2_twilight_dragon_low`. The other 55 keys have the same bytes as before.

## For the owner, in short

- The 9 pets of the approved sheet were re-baked from Blender with the smaller eyes. They match column A of the sheet
  (`evo_eyes/evo1_eyes_vs_sheetA.png`).
- The `_low` meshes show the game's own small Low eye (the same pixels as the Low Part build), with every feature,
  set where the High eye is (`evo_eyes/low_placement_1..3.png`; every Low pet: `evo_eyes/low_evo1_1..3.png`,
  `low_evo2.png`). They are not only the far-away pets: every `Detail = "Low"` view uses them (the pet picker
  cards, TeamFaces, the loss screen, Training, the battle portraits, the lobby and home pets), so judge them at card
  size too, not only at a distance.
- All 98 evolved body meshes change: 49 High + 49 `_low`, first and second evolutions. Wings (`evowing_`) carry no
  eyes and stay as they are. Same voxel grid, same body; the changes are the eyes and the face right around them
  (proof below, with the few small colour changes a little further out).
- Each of the 98 becomes a **new** Roblox asset with a new id, because its part structure changed (structureHash).
  Until Roblox approves a new asset, that pet shows its Part build (heavier: about 1,200 to 1,450 parts).
- Your OK is needed before the upload. Run it in the keyed cloud session, never from a PC.

## What was built on the PC (and checked)

| | |
|---|---|
| Source | branch `kitb-p2-eyes` @ `0fee5de` (eye masks `c116b44`, Low eyes `4071cbd`, K-step pins `3a9eb85`, Low eye placement `332c9d3` + `0fee5de`) |
| Tool | `blender/build_all.py`, export build, Blender as a Python module: bpy 5.2.2 on Python 3.13 (`%USERPROFILE%\.bpyenv`) |
| Keys | the 98 `evo1_*` / `evo2_*` keys in `evo_eyes/keys.txt`: 98 built, 0 failed, every FBX re-import checked (3 times) |
| Size | 15,377,624 bytes in all, 257,484 bytes for the largest file |
| Same bytes | 98 of 98 keys: two separate PC export builds gave the same sha256. The cloud rebuild must give the sha256 values in the table below. |
| Uploader dry run (scratch copy, base URL `127.0.0.1:9`, no key) | `98 key(s)`, 98 `new-asset`, 0 `FAILED`, "nothing was sent and nothing was written" (`upload_state.json` / `MeshIds.lua` hashes unchanged) |
| Smoke, mesh mode, re-baked manifests in place (scratch copy) | `--quick --mesh --only` petbuilder 585 / evolved 548 / p3evo_pets 675 / client_p6pets 545 passed, 0 failed |
| `check.mjs`, re-baked manifests in place | 98 `mesh-ids-stale` (expected until step 7) + 1 older error not from this work (`BattleController.lua:5962` asset-id, from kit-b `b39237b`) |
| Budgets | every key within its catalog budget. `tools/mesh_budget.py`: worst real view unchanged at 1,789 parts; "every pet a second evolution" 3,064 -> 3,097 parts (it was over the proposed 3,000 before this change too). |

**Eyes, measured** (per eye, the carved columns x voxel size; `evo_eyes/evo_eyes_fbx.json` `rows[].eye`):

| | pre-trim (live look) | re-baked | height |
|---|---|---|---|
| High, evo1 | 8 x 9 voxels, 0.64-0.79 x 0.72-0.89 studs | 6 x 7, 0.48-0.59 x 0.56-0.69 | x 7/9 |
| High, fierce (dragons) | 8 x 7 | 6 x 5 | x 5/7 |
| High, evo2 | 8 x 9, 0.85 x 0.96 | 6 x 7, 0.64 x 0.75 | x 7/9 |
| Low (scaled High eye -> the game's 4 x 4 Low eye) | 5-6 x 5-6 (fierce 5 x 4-5), 0.76-1.09 studs tall | 4 x 4, 0.61-0.87 studs | x 0.67-0.8 (fierce x 0.8-1.0) |

Every one of the 98 keys shows Lash, EyeShine, EyePupil, EyeIris and EyeGlint in both eyes, and the two eyes mirror.
The Low eye is the game's own Low mask, the same pixels as the Low Part build. On the coarse Low grid it is 1.1-1.2 x
the height of the High eye in studs (before: 1.1-1.4 x); the dragons' 4 x 4 fierce Low eye is 1.6 x their 6 x 5 High
eye (before: 1.2 x), and the same height as their live Low eye (narrower).

**Where the Low eye sits** (`evo_eyes/low_placement.json`, measured on the built meshes' voxels: the eye pixels on
the front, studs from the centre line; shift = Low eye centre minus High eye centre, in Low voxels, across and
up). The Low eye is 4 coarse voxels, wider in studs than the 6-voxel High eye, so it cannot match both edges: it
keeps at least half the High eyes' spacing and sits nearest the High centre; its row is the one nearest the High
centre. `selftest --only evoeyes` checks both on every `_low` key.

| pet (`_low`) | High eye across (studs) | `5cb4b2e` across | shift | this build across | shift | gap columns | row shift `5cb4b2e` -> now |
|---|---|---|---|---|---|---|---|
| `evo1_aurora_fox` | 0.22-0.76 | 0.09-0.77 | -0.36 | **0.26-0.94** | +0.64 | 1 -> 3 | -0.70 -> +0.30 |
| `evo1_bamboo_panda` | 0.36-0.84 | 0.09-0.77 | -1.01 | **0.26-0.94** | -0.01 | 1 -> 3 | -1.12 -> -0.12 |
| `evo1_biscuit_bear` | 0.36-0.84 | 0.08-0.69 | -1.40 | **0.23-0.85** | -0.40 | 1 -> 3 | -0.74 -> +0.26 |
| `evo1_blossom_bunny` | 0.28-0.76 | 0.08-0.69 | -0.88 | **0.23-0.85** | +0.12 | 1 -> 3 | -0.22 -> -0.22 |
| `evo1_bubble_axolotl` | 0.44-0.92 | 0.26-0.94 | -0.48 | 0.26-0.94 | -0.48 | 3 -> 3 | -0.78 -> +0.22 |
| `evo1_candy_unicorn` | 0.36-0.84 | 0.09-0.77 | -1.01 | **0.26-0.94** | -0.01 | 1 -> 3 | -0.92 -> -0.92 |
| `evo1_cherry_panda` | 0.36-0.84 | 0.09-0.77 | -1.01 | **0.26-0.94** | -0.01 | 1 -> 3 | -1.12 -> -0.12 |
| `evo1_cloudy_dragon` | 0.31-0.84 | 0.09-0.77 | -0.88 | **0.26-0.94** | +0.12 | 1 -> 3 | +0.22 -> +0.22 |
| `evo1_eclipse_dragon` | 0.31-0.84 | 0.28-1.04 | +0.46 | 0.28-1.04 | +0.46 | 3 -> 3 | -0.05 -> -0.05 |
| `evo1_ember_phoenix` | 0.20-0.68 | 0.08-0.69 | -0.36 | **0.23-0.85** | +0.64 | 1 -> 3 | -0.82 -> +0.18 |
| `evo1_frostling_penguin` | 0.36-0.84 | 0.23-0.85 | -0.40 | 0.23-0.85 | -0.40 | 3 -> 3 | -0.82 -> +0.18 |
| `evo1_honey_bunny` | 0.28-0.76 | 0.08-0.69 | -0.88 | **0.23-0.85** | +0.12 | 1 -> 3 | -0.22 -> -0.22 |
| `evo1_hydralotl` | 0.44-0.92 | 0.28-1.04 | -0.08 | 0.28-1.04 | -0.08 | 3 -> 3 | -0.45 -> -0.45 |
| `evo1_magma_cub` | 0.36-0.84 | 0.09-0.77 | -1.01 | **0.26-0.94** | -0.01 | 1 -> 3 | -1.12 -> -0.12 |
| `evo1_mallow_kitten` | 0.36-0.84 | 0.08-0.69 | -1.40 | **0.23-0.85** | -0.40 | 1 -> 3 | -0.74 -> +0.26 |
| `evo1_maple_fox` | 0.22-0.76 | 0.09-0.77 | -0.36 | **0.26-0.94** | +0.64 | 1 -> 3 | -0.70 -> +0.30 |
| `evo1_mochi_slime` | 0.28-0.76 | 0.08-0.69 | -0.88 | **0.23-0.85** | +0.12 | 1 -> 3 | -0.90 -> +0.10 |
| `evo1_moonlit_owl` | 0.36-0.84 | 0.23-0.85 | -0.40 | 0.23-0.85 | -0.40 | 3 -> 3 | -0.34 -> -0.34 |
| `evo1_nebula_axolotl` | 0.44-0.92 | 0.23-0.85 | -0.92 | **0.39-1.00** | +0.08 | 3 -> 5 | -0.14 -> -0.14 |
| `evo1_obsidian_phoenix` | 0.20-0.68 | 0.09-0.77 | -0.08 | 0.09-0.77 | -0.08 | 1 -> 1 | -0.99 -> +0.01 |
| `evo1_pebble_pup` | 0.36-0.84 | 0.08-0.69 | -1.40 | **0.23-0.85** | -0.40 | 1 -> 3 | -0.22 -> -0.22 |
| `evo1_phantom_kitsune` | 0.25-0.84 | 0.10-0.85 | -0.36 | **0.28-1.04** | +0.64 | 1 -> 3 | -0.18 -> -0.18 |
| `evo1_pip_penguin` | 0.36-0.84 | 0.23-0.85 | -0.40 | 0.23-0.85 | -0.40 | 3 -> 3 | -0.82 -> +0.18 |
| `evo1_puddle_frog` | 0.36-0.84 | 0.23-0.85 | -0.40 | 0.23-0.85 | -0.40 | 3 -> 3 | -0.62 -> +0.38 |
| `evo1_rime_wyrmling` | 0.31-0.84 | 0.28-1.04 | +0.46 | 0.28-1.04 | +0.46 | 3 -> 3 | -0.05 -> -0.05 |
| `evo1_shroomie_frog` | 0.36-0.84 | 0.23-0.85 | -0.40 | 0.23-0.85 | -0.40 | 3 -> 3 | -0.62 -> +0.38 |
| `evo1_sleepy_owl` | 0.36-0.84 | 0.23-0.85 | -0.40 | 0.23-0.85 | -0.40 | 3 -> 3 | -0.34 -> -0.34 |
| `evo1_starlight_unicorn` | 0.36-0.84 | 0.09-0.77 | -1.01 | **0.26-0.94** | -0.01 | 1 -> 3 | -0.92 -> -0.92 |
| `evo1_storm_tabby` | 0.36-0.84 | 0.08-0.69 | -1.40 | **0.23-0.85** | -0.40 | 1 -> 3 | -0.74 -> +0.26 |
| `evo1_stormfang` | 0.22-0.76 | 0.09-0.77 | -0.36 | **0.26-0.94** | +0.64 | 1 -> 3 | -0.18 -> -0.18 |
| `evo1_sunbeam_bear` | 0.36-0.84 | 0.08-0.69 | -1.40 | **0.23-0.85** | -0.40 | 1 -> 3 | -0.74 -> +0.26 |
| `evo1_twilight_dragon` | 0.31-0.84 | 0.28-1.04 | +0.46 | 0.28-1.04 | +0.46 | 3 -> 3 | -0.05 -> -0.05 |
| `evo1_waffle_corgi` | 0.36-0.84 | 0.09-0.77 | -1.01 | **0.26-0.94** | -0.01 | 1 -> 3 | -0.71 -> +0.29 |
| `evo2_aurora_fox` | 0.27-0.91 | 0.33-1.20 | +0.81 | 0.33-1.20 | +0.81 | 3 -> 3 | -0.88 -> +0.12 |
| `evo2_candy_unicorn` | 0.37-1.01 | 0.33-1.20 | +0.32 | 0.33-1.20 | +0.32 | 3 -> 3 | -0.81 -> +0.19 |
| `evo2_cloudy_dragon` | 0.37-1.01 | 0.33-1.20 | +0.32 | 0.33-1.20 | +0.32 | 3 -> 3 | +0.17 -> +0.17 |
| `evo2_eclipse_dragon` | 0.37-1.01 | 0.33-1.20 | +0.32 | 0.33-1.20 | +0.32 | 3 -> 3 | +0.17 -> +0.17 |
| `evo2_ember_phoenix` | 0.16-0.80 | 0.11-0.98 | +0.30 | 0.11-0.98 | +0.30 | 1 -> 1 | -0.34 -> -0.34 |
| `evo2_hydralotl` | 0.48-1.12 | 0.33-1.20 | -0.17 | 0.33-1.20 | -0.17 | 3 -> 3 | -0.43 -> -0.43 |
| `evo2_magma_cub` | 0.27-0.91 | 0.33-1.20 | +0.81 | 0.33-1.20 | +0.81 | 3 -> 3 | -0.88 -> +0.12 |
| `evo2_moonlit_owl` | 0.37-1.01 | 0.33-1.20 | +0.32 | 0.33-1.20 | +0.32 | 3 -> 3 | -0.83 -> +0.17 |
| `evo2_nebula_axolotl` | 0.48-1.12 | 0.33-1.20 | -0.17 | 0.33-1.20 | -0.17 | 3 -> 3 | -0.43 -> -0.43 |
| `evo2_obsidian_phoenix` | 0.16-0.80 | 0.11-0.98 | +0.30 | 0.11-0.98 | +0.30 | 1 -> 1 | -0.34 -> -0.34 |
| `evo2_phantom_kitsune` | 0.27-0.91 | 0.33-1.20 | +0.81 | 0.33-1.20 | +0.81 | 3 -> 3 | -0.88 -> +0.12 |
| `evo2_rime_wyrmling` | 0.37-1.01 | 0.33-1.20 | +0.32 | 0.33-1.20 | +0.32 | 3 -> 3 | +0.17 -> +0.17 |
| `evo2_starlight_unicorn` | 0.37-1.01 | 0.33-1.20 | +0.32 | 0.33-1.20 | +0.32 | 3 -> 3 | -0.81 -> -0.81 |
| `evo2_stormfang` | 0.27-0.91 | 0.11-0.98 | -0.19 | **0.33-1.20** | +0.81 | 1 -> 3 | -0.39 -> -0.39 |
| `evo2_sunbeam_bear` | 0.27-0.91 | 0.33-1.20 | +0.81 | 0.33-1.20 | +0.81 | 3 -> 3 | -0.88 -> +0.12 |
| `evo2_twilight_dragon` | 0.37-1.01 | 0.33-1.20 | +0.32 | 0.33-1.20 | +0.32 | 3 -> 3 | +0.17 -> +0.17 |

Left as they are, with the reason: the 4 second evolutions above at +0.81 (one column in gives a single gap column
with the nose against both eyes); `evo2_ember_phoenix` / `evo2_obsidian_phoenix` keep one gap column (their High eyes
are 1.5 Low voxels apart, the beak between); `evo1_obsidian_phoenix` keeps one gap column because one column out hangs
off its 9-voxel-wide head. The owls stay inside their gold disc (-0.40): the Low Part build's eye sits one column
further out (0.38-1.00 studs), 0.60 voxel outside the High eye, with its outer column on the brown head edge. Rows:
`evo1_candy_unicorn`, `evo1_starlight_unicorn` and `evo2_starlight_unicorn` keep their row (-0.92 / -0.81): one row up
puts the eye's outer highlight pixel off the side of the head.

## Proof that only the eyes change (`evo_eyes/verify_diff.json`)

The same 98 keys were also built (no export) from the pre-trim commit `c733fe0` and compared with this build:

- **Voxel grid:** K and voxelStuds equal on 98 of 98 keys (the reviewed `76cee35` build: 11 keys differed).
- **Every Body voxel:** 12842 changed voxels lie in the eye area (the columns either build carved for an eye: the kit's
  lids + PetBuilder's own carve). Outside it: 343 shade-only changes (the same colour, only its _Light / _Dark / Deep
  variant: the kit shades a voxel from its neighbours and the eye is a hole one voxel deep), at most 3 voxels from the
  eye, and 4 colour changes on 2 keys.
- **Measured from the eye you SEE** (that eye area is wide on the `_low` keys: it includes PetBuilder's whole 8 x 9
  High-mask carve at the coarse Low K). Surface voxels whose colour changed (not only its shade), not an eye pixel of
  either build, by distance from the visible eye pixels of either build: 1 voxel away 158 voxels on 42 keys (the face
  re-drawn around the eye hole); **2 to 4 voxels away 59 voxels on 20 keys, all `_low`**; 5 or more: 0. Each is 1 to
  4 voxel faces and barely visible. They come from the Low eye path (the face is restored from PetBuilder's carve and
  the evolved passes then run on it). Per key: `evo1_aurora_fox_low` Belly>Fur_Dark, Belly>Gold; `evo1_bubble_axolotl_low` Gem>Fur_Dark, Gem>Gold, GemB>Fur_Dark, GemB>Gold, Gold>None; `evo1_candy_unicorn_low` Mouth>Muzzle, Muzzle>Fur_Dark; `evo1_frostling_penguin_low` Gem>Gold, Gold>ScarfStripe; `evo1_hydralotl_low` GemGlint>Gem; `evo1_magma_cub_low` Fur>Magma; `evo1_maple_fox_low` Belly>Fur_Dark, Belly>Gold; `evo1_moonlit_owl_low` Gold>Belly, GoldLight>None; `evo1_obsidian_phoenix_low` Gem>Gold, GemB>Gold; `evo1_sleepy_owl_low` Gold>Belly, GoldLight>None; `evo1_starlight_unicorn_low` Mouth>Muzzle, Muzzle>Fur_Dark; `evo1_stormfang_low` Plate>GoldLight; `evo2_aurora_fox_low` Belly>None; `evo2_candy_unicorn_low` Muzzle>Fur_Dark; `evo2_hydralotl_low` Gem>None, GemB>None, Gold>HydraJaw; `evo2_moonlit_owl_low` Gem>Belly, GemB>Belly; `evo2_nebula_axolotl_low` Gold>None; `evo2_phantom_kitsune_low` Belly>None; `evo2_starlight_unicorn_low` Muzzle>Fur_Dark; `evo2_sunbeam_bear_low` GemB>Gold.
- **Manifest part lists:** no other manifest field changes (attachments, rig, bounds, groups other than the lids).
  By the letter, not only the eye parts change. Eye parts (EyePupil / EyeIris / EyeShine / EyeGlint / EyeRing / Lash /
  EyeLid*) change on every key. Non-eye parts: their triangles change around the eye on every key (the face is
  re-meshed where the eye hole changed); a new part appears where the smaller eye uncovers a face feature the old eye
  covered whole: `evo1_aurora_fox_low` Blush, `evo1_bamboo_panda_low` Blush, `evo1_biscuit_bear_low` Nose, `evo1_cherry_panda_low` Blush, `evo1_maple_fox_low` Blush, `evo1_nebula_axolotl_low` Blush, `evo1_obsidian_phoenix_low` Beak, `evo1_pebble_pup_low` Nose, `evo1_sunbeam_bear_low` Nose, `evo2_hydralotl` Blush, `evo2_nebula_axolotl` Blush, `evo2_stormfang_low` Nose. A part goes away on `evo2_magma_cub_low` Blush, `evo2_sunbeam_bear_low` Blush: its 2 blush voxels lie under the restored cheek at Low K 0.55 and
  showed before only as side faces inside the old eye hole, 1 row lower (the live Low mesh shows them the same way).
  Non-eye part boxes that change (Blush, Nose, Fixed, Gold ...) change only through the voxels
  above.

**Why the re-baked manifests are not committed from the PC.** `MeshLibrary` fits the downloaded asset to the
committed manifest. A re-baked manifest with the OLD id would refuse the key ("missing part" -> the Part build), or,
where names still line up, put old geometry into the new part boxes. `node tools/check.mjs` rule `mesh-ids-stale`
stops it as well (98 errors with the re-baked manifests in place). `docs/phase6/OWNER_UPLOAD.md` 8e: the new manifest
and the new id go into the **same commit**. So the upload session rebuilds (it has to anyway: `blender/out/` is not
committed), checks the bytes against this list, uploads, and commits manifests + `meshes.json` + `upload_state.json`
+ `MeshIds.lua` together.

**Older drift that ships with this re-bake** (the live meshes vs the pre-trim build `c733fe0`, not from the eyes): 10
keys. `evo1_hydralotl`, `evo1_hydralotl_low`, `evo1_magma_cub` and `evo1_magma_cub_low` were behind today's design
(`evo_eyes/evo1_drift_keys.png`: re-baked mesh vs today's Part build). `evo1_nebula_axolotl`, `evo2_nebula_axolotl`,
`evo2_starlight_unicorn` (High + `_low` each) drop `Star` from the manifest's `FixedKeys` (same geometry, same
contentHash as live).

## Steps for the keyed cloud session (from `docs/phase6/OWNER_UPLOAD.md`)

Rules of OWNER_UPLOAD.md hold: never print the key, no real upload without the owner's OK in the chat, never fake an
id, never go around moderation.

0. **OWNER**: say go in the chat. This is an upload, so it is the owner's call.
1. **CLAUDE, prepare** (section 2):
   ```bash
   cd /home/user/roblox/nimbus-climb
   git fetch origin && git checkout kit-b && git pull     # kit-b once kitb-p2-eyes is merged; before that: kitb-p2-eyes
   git merge-base --is-ancestor 0fee5de HEAD && echo ok   # the trimmed eyes, the Low eyes, the K-step pins, the Low eye placement
   python3 -m venv /tmp/claude-0/bpyenv
   /tmp/claude-0/bpyenv/bin/pip install bpy==5.2.2 numpy lupa pillow    # pin 5.2.2: the FBX bytes hold the version
   ```
2. **Build exactly the 98 keys** (export build, about 4 minutes):
   ```bash
   /tmp/claude-0/bpyenv/bin/python blender/build_all.py $(sed 's/^/--key /' build/upload_sheets/evo_eyes/keys.txt)
   ```
   Expect `built 98 key(s)` and exit 0.
3. **Check the build against this hand-over.** Stop on any mismatch:
   ```bash
   git status --short     # only the 98 src/shared/MeshManifests/evo1_*/evo2_* files + blender/meshes.json
   python3 - <<'EOF'
   import json, hashlib
   want = {r["key"]: r for r in json.load(open("build/upload_sheets/evo_eyes/evo_eyes_fbx.json"))["rows"]}
   idx = json.load(open("blender/meshes.json", encoding="utf-8"))["keys"]
   bad = [k for k, r in want.items() if (idx[k]["contentHash"], idx[k]["structureHash"], idx[k]["fbxSha256"],
          hashlib.sha256(open(idx[k]["fbx"], "rb").read()).hexdigest()) != (r["contentHash"], r["structureHash"], r["sha256"], r["sha256"])]
   print(len(want) - len(bad), "of", len(want), "match the hand-over list", bad)
   EOF
   ```
   Expect `98 of 98 match`. A mismatch means PetBuilder or the kit changed after `0fee5de`. In that case
   tell the lead, re-render the previews (`python3 tools/render_model.py meshevo:<pet>:1`) and wait for the owner
   before uploading.
4. **Offline checks** (section 2.2):
   ```bash
   python3 tools/test_upload_assets.py
   python3 tools/mesh_names.py --check blender/out/*.manifest.json
   python3 blender/kit/selftest.py --only evoeyes      # the Low eyes, where they sit + the K-step pins
   python3 tools/syntax.py && node tools/check.mjs
   ```
   At this point `check.mjs` is expected to report 98 `mesh-ids-stale` errors: the new manifests still have the old
   ids. They clear in step 7. Stop on any other new error.
5. **Dry run** (section 3; sends nothing, writes nothing):
   ```bash
   python3 tools/upload_assets.py --only "$(paste -sd, build/upload_sheets/evo_eyes/keys.txt)"
   ```
   Check the first line: `98 key(s) for user|group <id>` must be the game's owner. Expect 98 `new-asset` lines
   ("structure changed ... a NEW asset, the id changes") and no `FAILED ... not exported from this contentHash`.
   Show the owner the summary and ask: "OK to upload the 98 evolved eye meshes (98 new assets, new ids)?"
6. **Upload**, after the owner's yes (section 5):
   ```bash
   python3 tools/upload_assets.py --upload --only "$(paste -sd, build/upload_sheets/evo_eyes/keys.txt)"
   ```
   If a key says `the create of KEY may have reached Roblox`, see section 4 / 8g: check Creator Hub, then `--adopt KEY=<id>`
   or `--not-created KEY`. Never just re-run it.
7. **One commit, everything together** (section 8e):
   ```bash
   git add src/shared/MeshManifests/evo1_*.lua src/shared/MeshManifests/evo2_*.lua blender/meshes.json \
           blender/upload_state.json src/shared/MeshIds.lua
   git commit    # "Phase 6 upload: evolved eyes re-bake (98 evo1_/evo2_ keys, Pitch 2 item 7)" + the attribution lines
   node tools/check.mjs                       # no mesh-ids-stale left
   python3 tools/smoke.py --quick --mesh      # the pet scenarios on mesh pets
   rojo build default.project.json -o play/NimbusClimb.rbxlx && python3 tools/verify_place.py
   git push
   ```
8. **Moderation** (8a): a new asset in review is already in `MeshIds.lua` and shows the Part build until it is approved.
   An hour later: `python3 tools/upload_assets.py --upload --refresh --only "$(paste -sd, build/upload_sheets/evo_eyes/keys.txt)"`,
   commit `MeshIds.lua` + `upload_state.json`. A rejected key stays on its Part build; tell the owner and do not work
   around it.
9. **OWNER Play-test** (section 5): in Studio (published game, Rojo connected, Play), run `/pets 1` and `/pets 2`. The evolved faces should
   show the smaller eyes, as in `evo_eyes/evo1_eyes_vs_sheetA.png`. In the arena (Lv 100 Phantom Kitsune and
   Stormfang, the owner's shot), no yellow `[MeshLibrary] ... stays on the Part build` line should appear in Output.
   Garden pets, other players' followers and every `Detail = "Low"` view (pet picker cards, TeamFaces, the loss
   screen, Training, battle portraits) use the `_low` meshes: open the pet picker and check the cards too
   (`evo_eyes/low_placement_1..3.png`).
   Then publish (section 7).

Roll back (section 9): put the old ids back by removing the new lines. The old ids stay in `upload_state.json`
under `previousAssetIds`, and the old manifests are in git history at `0fee5de` (unchanged since the live upload).

## Evidence (this folder)

| file | what |
|---|---|
| `evo_eyes/evo1_eyes_vs_sheetA.png` | the 9 sheet pets, front + 3/4: approved sheet column A, the Part build, the re-baked mesh |
| `evo_eyes/evo2_eyes.png` | second evolutions of the 6 sheet pets that have one: Part build vs re-baked mesh |
| `evo_eyes/low_placement_1.png` .. `low_placement_3.png` | the `_low` keys whose eye moved (and the 4 second evolutions kept across, the owls, the phoenix): High mesh / Low Part build / `5cb4b2e` / this build, front + 3/4, all on the same frame |
| `evo_eyes/low_cards.png` | the 9 sheet pets' `_low` meshes at pet-picker card size (about 90 px), High mesh / Low Part build / this build |
| `evo_eyes/evo1_low_eyes.png` | the 9 sheet pets' `_low` meshes vs the Low Part build (the same 4 x 4 Low eye) |
| `evo_eyes/low_evo1_1.png` .. `low_evo1_3.png`, `low_evo2.png` | EVERY Low key: High mesh / Low Part build / `5cb4b2e` / this build, front + 3/4 |
| `evo_eyes/evo1_drift_keys.png` | the 4 design-drift keys (Hydralotl, Magma Cub; High + Low) |
| `evo_eyes/fbx_in_blender.png` | exported FBX files of this build opened in Blender 5.2.2 (parts tinted by name only; lids hidden) |
| `evo_eyes/low_placement.json` | where the eyes sit per pet (High and `_low`, `5cb4b2e` and this build) + the surface colour changes by distance from the visible eye |
| `evo_eyes/evo_eyes_fbx.json` | every key: fbx, bytes, sha256, contentHash, structureHash, tris, parts, the live id / hashes, the eye |
| `evo_eyes/verify_diff.json` | every key vs the pre-trim build: grid, part lists, every Body voxel (the proof above) |
| `evo_eyes/keys.txt` | the 98 keys, one per line |
| `evo_eyes_rebake.json`, `evo_eyes_rebake_preview.png` | the earlier dry bake (`3708fbc`): live mesh vs re-bake |

Every High key, pre-trim vs this build (front + 3/4): `build/GATE_P2/eyes_fin_build/high_evo1_1..3.png`, `high_evo2.png`
(local gate folder, not committed).

## The 98 FBX files

Path = `blender/out/<key>.fbx` (git-ignored, rebuilt in step 2). sha256 = the PC build, which the cloud build must reproduce.
Live id = today's `MeshIds.lua` id, which is replaced by the new asset's id.

| # | key | path | bytes | sha256 | live id |
|---|---|---|---|---|---|
| 1 | `evo1_aurora_fox` | `blender/out/evo1_aurora_fox.fbx` | 199548 | `2214b71cef7bc1f8bcc9e9ca727bf3aa974fc80cfaa2c482ed25f9493b8fbaf9` | 87772383693151 |
| 2 | `evo1_aurora_fox_low` | `blender/out/evo1_aurora_fox_low.fbx` | 125692 | `2b01cec3623e6fc526c8590a0a7ab791be69b0fbc9da8a323198bf658b363f83` | 77788282454956 |
| 3 | `evo1_bamboo_panda` | `blender/out/evo1_bamboo_panda.fbx` | 177932 | `e13dc9fa8fa11afa9464f173d9a8ab1cc4b999afaa1ee519493791b7dec7def7` | 104363918642473 |
| 4 | `evo1_bamboo_panda_low` | `blender/out/evo1_bamboo_panda_low.fbx` | 101244 | `2552377c8b2d364a6066ae30658fc53bb89ad27e0c09b515ba53d3aa815a8775` | 129482935584530 |
| 5 | `evo1_biscuit_bear` | `blender/out/evo1_biscuit_bear.fbx` | 167004 | `3dba1d8732708b777d1d5cbf7428f0209be72c2d97246d23c6a42df321cb5e79` | 73735764977613 |
| 6 | `evo1_biscuit_bear_low` | `blender/out/evo1_biscuit_bear_low.fbx` | 103660 | `cc611f169d8d46928d5cfdfdc1a0f4ffe5c6a37496be7d6597248cd2e7d960af` | 99723032833610 |
| 7 | `evo1_blossom_bunny` | `blender/out/evo1_blossom_bunny.fbx` | 183532 | `438985ad3eacde6deeb2aa8e1129b71eb98adf18eca9d07eef7951ac82678d08` | 82394928828450 |
| 8 | `evo1_blossom_bunny_low` | `blender/out/evo1_blossom_bunny_low.fbx` | 117020 | `7db3f0174e009457a613a626b4d832c523b99120a458d29e50f7ae52897f1cd5` | 75253507719284 |
| 9 | `evo1_bubble_axolotl` | `blender/out/evo1_bubble_axolotl.fbx` | 178972 | `45f9cf70a1d9ebbddd845e1cbb629e3e7156313012c5ff3dad3069c9be0bc3c7` | 92767577680778 |
| 10 | `evo1_bubble_axolotl_low` | `blender/out/evo1_bubble_axolotl_low.fbx` | 100908 | `f5b8a6ea8a3ec1d0cd4475006a088ca0c95a6404d951e933d7de8b1a81339c46` | 138245964799147 |
| 11 | `evo1_candy_unicorn` | `blender/out/evo1_candy_unicorn.fbx` | 189884 | `4e15f65df68ff3ce5747da2db5f2f9dbde2cf55c60d9c12e03f365a62548de49` | 137467109507967 |
| 12 | `evo1_candy_unicorn_low` | `blender/out/evo1_candy_unicorn_low.fbx` | 124252 | `c8ddb48bc341457dcbb89ee88b91b96b263479c456959b900b8048b6972a82af` | 83858413665107 |
| 13 | `evo1_cherry_panda` | `blender/out/evo1_cherry_panda.fbx` | 184972 | `92f92f6b28c593c0342ed2684edf07e3a76061eca7653d7fdf2a8efa89ec538e` | 110836396681656 |
| 14 | `evo1_cherry_panda_low` | `blender/out/evo1_cherry_panda_low.fbx` | 104716 | `f1a19651479dce1420d80b48d5b8e162fedc934954d59f884851ef0e72e3f8d8` | 118659270989807 |
| 15 | `evo1_cloudy_dragon` | `blender/out/evo1_cloudy_dragon.fbx` | 185372 | `bb4777f79114b792811305722070efc532c676cdf11c0d92d4e4179be463d774` | 124282700617318 |
| 16 | `evo1_cloudy_dragon_low` | `blender/out/evo1_cloudy_dragon_low.fbx` | 118604 | `727173958b6545929b5d45c5054a97651ea6b67916e48131ef72f8b497e90632` | 93000498845226 |
| 17 | `evo1_eclipse_dragon` | `blender/out/evo1_eclipse_dragon.fbx` | 194908 | `81ad4d7f643300c029412de5c8e9bad10420f24c390f15d286f1afe0c52869fc` | 115587997700525 |
| 18 | `evo1_eclipse_dragon_low` | `blender/out/evo1_eclipse_dragon_low.fbx` | 116764 | `b1d81c568289becc56ec3491b38f3a63894ac360a7097ced83720198526bbe40` | 120102054910553 |
| 19 | `evo1_ember_phoenix` | `blender/out/evo1_ember_phoenix.fbx` | 166828 | `b2b2ae5085ee78c040978d76c1784a285b74093897a095df984f2e55b269279f` | 85951869370892 |
| 20 | `evo1_ember_phoenix_low` | `blender/out/evo1_ember_phoenix_low.fbx` | 108764 | `d48a110ca3d91f20c2066dd1480813f33fba58aa45e5445b61cf1835ddade12c` | 127384591685930 |
| 21 | `evo1_frostling_penguin` | `blender/out/evo1_frostling_penguin.fbx` | 177100 | `8c992204233c7144bd853903a924b3757c1b65c6cc5e78e23fb1765850422a15` | 87839970044677 |
| 22 | `evo1_frostling_penguin_low` | `blender/out/evo1_frostling_penguin_low.fbx` | 104588 | `3a53ab4576e9de988534ac7793912ba718b48ad19374501886307f45e8e9f692` | 117375525292782 |
| 23 | `evo1_honey_bunny` | `blender/out/evo1_honey_bunny.fbx` | 177868 | `165948631e735c4f74db472dc840ba5e203bbb363f1d9228280c2ed6c5824cf2` | 134835417429640 |
| 24 | `evo1_honey_bunny_low` | `blender/out/evo1_honey_bunny_low.fbx` | 111324 | `613fbb7f143e5763112e2ad9272856435fa44d48a0c38931f2872f7e7a2bc76a` | 139060124292304 |
| 25 | `evo1_hydralotl` | `blender/out/evo1_hydralotl.fbx` | 201628 | `52479cee0d43bdcf6a0654b14bd357abd3630e679aba6a67c72f853a2070bc58` | 107330994952547 |
| 26 | `evo1_hydralotl_low` | `blender/out/evo1_hydralotl_low.fbx` | 111804 | `1807f8813b3ebe6651087f593923d3c55dc82496193731ebadea8fc7cff6c205` | 75165208362476 |
| 27 | `evo1_magma_cub` | `blender/out/evo1_magma_cub.fbx` | 197164 | `22975e91ca9871a15b4737ac45887bf8fa2345457d4d30996421ec9b38a073d5` | 128171047724691 |
| 28 | `evo1_magma_cub_low` | `blender/out/evo1_magma_cub_low.fbx` | 110188 | `5b56cd32e6e05fac1f55bf6bac603fe59358b86086f149ac4c8b231032cbde69` | 111156779183723 |
| 29 | `evo1_mallow_kitten` | `blender/out/evo1_mallow_kitten.fbx` | 196940 | `0d1714ebb228073845022da86272eeb9ea17839b896dacf0611aeafa781cc881` | 76487641815372 |
| 30 | `evo1_mallow_kitten_low` | `blender/out/evo1_mallow_kitten_low.fbx` | 117852 | `22578b55da28da40723c4ccef74ce08386287dea75c6cfcac42933600c40f945` | 108260487493804 |
| 31 | `evo1_maple_fox` | `blender/out/evo1_maple_fox.fbx` | 185180 | `af9b27b7c90eb07527e465a03e93e874a6b054ac5c26db74b863c5ed71a48fdb` | 105335734155111 |
| 32 | `evo1_maple_fox_low` | `blender/out/evo1_maple_fox_low.fbx` | 113308 | `ae19bb4b6003e6ef9296f69aa3abaa8de0ee0dffd56b86b446669ca987eba712` | 71314104979558 |
| 33 | `evo1_mochi_slime` | `blender/out/evo1_mochi_slime.fbx` | 134460 | `2390cd6e74a2a9ba8ba25d164c31ecab461afa8e84199bc8d7d1a734e1aa940c` | 140278769359069 |
| 34 | `evo1_mochi_slime_low` | `blender/out/evo1_mochi_slime_low.fbx` | 86092 | `935ceaa4dfd12b27e8ee36cc492217fc0bf1fc53b4ce4a70cbf1cad01ec6b780` | 121585707246125 |
| 35 | `evo1_moonlit_owl` | `blender/out/evo1_moonlit_owl.fbx` | 177004 | `eb70c86a3140a466a8195109ac9b14653e50d26308fe38b19ba55739978ea7fb` | 113642919127042 |
| 36 | `evo1_moonlit_owl_low` | `blender/out/evo1_moonlit_owl_low.fbx` | 106556 | `fd3559915a597d0c1dfede1d3c3e9acd50483bad749092ca27bbf5d8da83b001` | 87552810305165 |
| 37 | `evo1_nebula_axolotl` | `blender/out/evo1_nebula_axolotl.fbx` | 176844 | `d749d5e3ba8a5e9bfbb8689b391a83893038b518497ebcfdf5a42a794cb7d6bd` | 87331681854879 |
| 38 | `evo1_nebula_axolotl_low` | `blender/out/evo1_nebula_axolotl_low.fbx` | 112620 | `059f9069f578ce65321a83651ab4737317f0c222f1e158882e53b65b75bea18b` | 135511552169009 |
| 39 | `evo1_obsidian_phoenix` | `blender/out/evo1_obsidian_phoenix.fbx` | 193100 | `74cc4183cec875fd9f6a0ec4abcfa253afa3e2e357adc0ffba892aa04e6dc455` | 84691219969375 |
| 40 | `evo1_obsidian_phoenix_low` | `blender/out/evo1_obsidian_phoenix_low.fbx` | 120364 | `f4984bcf33b655e98810426231e99a45af4cb922ed8c9bb01181c237c33a70af` | 136278315485979 |
| 41 | `evo1_pebble_pup` | `blender/out/evo1_pebble_pup.fbx` | 184860 | `6a1300bcc2c8c522292bce67ba4faafc086d84efb3c8f66106588cc5fd30596a` | 75795178584683 |
| 42 | `evo1_pebble_pup_low` | `blender/out/evo1_pebble_pup_low.fbx` | 115452 | `08b1f2abe6231b9bbf318cdc1fd9d33df9cba822ac4636eb387b79e55b9d4937` | 73658366816678 |
| 43 | `evo1_phantom_kitsune` | `blender/out/evo1_phantom_kitsune.fbx` | 196012 | `3f805ef864cc383fa6e61798e10e705230aca98fd3ab0dd7db2ead4418e187a5` | 109492203546111 |
| 44 | `evo1_phantom_kitsune_low` | `blender/out/evo1_phantom_kitsune_low.fbx` | 112572 | `bb76217e008e825e0441d25d70bfd3dc283ff9716ac2534e0216e9ec3c7f2998` | 73193456925742 |
| 45 | `evo1_pip_penguin` | `blender/out/evo1_pip_penguin.fbx` | 171708 | `0faaa6157f8a354e8ee16deb4d755af1c44542b5ae7b28057cb34e637e25df12` | 102583552628564 |
| 46 | `evo1_pip_penguin_low` | `blender/out/evo1_pip_penguin_low.fbx` | 102332 | `5d24951ca1ff2d62cb687831e83b1a9b3240c3918ae4ce34e7eaa313c91490a5` | 119159628161633 |
| 47 | `evo1_puddle_frog` | `blender/out/evo1_puddle_frog.fbx` | 165772 | `28b46fb04faa5ef15ad0f52c3f5acccc4cca90919c7537be8f87965163595fdb` | 72369315852282 |
| 48 | `evo1_puddle_frog_low` | `blender/out/evo1_puddle_frog_low.fbx` | 100668 | `af51a484e0c1821b4a2277aef8d2ef6c2cf4d4cea060f5da89a34b1f658e4e39` | 109508565800347 |
| 49 | `evo1_rime_wyrmling` | `blender/out/evo1_rime_wyrmling.fbx` | 219532 | `99321ec7b7ad7781c66e7ceb3a508be096abdb377e718e1db520c0ba21487f81` | 139595966133024 |
| 50 | `evo1_rime_wyrmling_low` | `blender/out/evo1_rime_wyrmling_low.fbx` | 134796 | `6178bc6574819279ec9a581249ebf6a114143a247b7ba7b43e10782716008419` | 97518265520464 |
| 51 | `evo1_shroomie_frog` | `blender/out/evo1_shroomie_frog.fbx` | 162988 | `7ee18447cb0c2ab9aafdc93f2209ccfeacbba02edd22e28b443c60c9ecba6fcc` | 113280357489430 |
| 52 | `evo1_shroomie_frog_low` | `blender/out/evo1_shroomie_frog_low.fbx` | 102252 | `e817ff6d063de05b8eb4c9b3e034cd4b19fd440a8672ad31beee3c464ef09c65` | 89302304972875 |
| 53 | `evo1_sleepy_owl` | `blender/out/evo1_sleepy_owl.fbx` | 172076 | `65f24ed909369542a49bf9885b06492f0ddb32608ac03802f794d239a25bc012` | 123215045455041 |
| 54 | `evo1_sleepy_owl_low` | `blender/out/evo1_sleepy_owl_low.fbx` | 104524 | `6fd99a1007577135990c0f70eeaa0810ddfb3588fc7c7d0711447896733e4057` | 104696782911723 |
| 55 | `evo1_starlight_unicorn` | `blender/out/evo1_starlight_unicorn.fbx` | 194348 | `169f7d523368c33f79a6aded3556ec61cd6090320544f0ea63f034b6363071e2` | 129258425301120 |
| 56 | `evo1_starlight_unicorn_low` | `blender/out/evo1_starlight_unicorn_low.fbx` | 125852 | `9fa89ffc7da2321837c9f8eb45196fe0220c101368ab31504c10d8739eb9e575` | 113879047878339 |
| 57 | `evo1_storm_tabby` | `blender/out/evo1_storm_tabby.fbx` | 186732 | `b85e8d2ee6a9ced7d6d9143360b481ddb2a212f6dab09cf42d5b72c9a037b282` | 90763597503307 |
| 58 | `evo1_storm_tabby_low` | `blender/out/evo1_storm_tabby_low.fbx` | 112060 | `70e60b87284a39585fb79b8dc1737b8d2f0e1ceef7d42ff616b0cbe95eb8e920` | 72832808211675 |
| 59 | `evo1_stormfang` | `blender/out/evo1_stormfang.fbx` | 181916 | `f9f508d1f30da3c567774f78a8ab4721953ad05f30f57c088d84fc6c920cd051` | 93119026859574 |
| 60 | `evo1_stormfang_low` | `blender/out/evo1_stormfang_low.fbx` | 113308 | `6d7fe8fd2a783c16730f33d58f2921f240964bf9f7d1c1c2549b17b2f4695b38` | 76844743783547 |
| 61 | `evo1_sunbeam_bear` | `blender/out/evo1_sunbeam_bear.fbx` | 180876 | `64dd39c91f6400acd5744f82db3d8bd73d9dd28f796045e55dce98a37053fca3` | 81137217654376 |
| 62 | `evo1_sunbeam_bear_low` | `blender/out/evo1_sunbeam_bear_low.fbx` | 111308 | `096176440112618365d44839470124aead5ab6b8b1ff709d4c2c9e606292aaf7` | 130314648949999 |
| 63 | `evo1_twilight_dragon` | `blender/out/evo1_twilight_dragon.fbx` | 182028 | `dc161936ee3a0afc44bc82427e0098f59996dbb21c343fb471a75903b19631c9` | 139255105971705 |
| 64 | `evo1_twilight_dragon_low` | `blender/out/evo1_twilight_dragon_low.fbx` | 110812 | `02db3bf5118b76c3b30f88ee70503bb8e08837663bed5aecc327b06d80218190` | 122058642544043 |
| 65 | `evo1_waffle_corgi` | `blender/out/evo1_waffle_corgi.fbx` | 194988 | `a43c5a19ab3a58503096aa97447f46441d228e74c60bfaafe4c2a16bcd078329` | 121575312945918 |
| 66 | `evo1_waffle_corgi_low` | `blender/out/evo1_waffle_corgi_low.fbx` | 118044 | `82535d448df4880e9b16077f1fa901281b4a9cf354dd929e544f40809465eb99` | 110708334812765 |
| 67 | `evo2_aurora_fox` | `blender/out/evo2_aurora_fox.fbx` | 248556 | `2b27fc43e457a1703523731b9522a11caec48db938770d84c05be5d6b05d350a` | 96454077193072 |
| 68 | `evo2_aurora_fox_low` | `blender/out/evo2_aurora_fox_low.fbx` | 134604 | `56f564b7154b6a0f3ed1cc4d716dd9bb313f0818f30c86060867760366e662f6` | 134494158953338 |
| 69 | `evo2_candy_unicorn` | `blender/out/evo2_candy_unicorn.fbx` | 230524 | `bbf67d4cbcb258c51bf0e001f73b807b03ee696fd5e7553450235de290f8e1f2` | 73535489272058 |
| 70 | `evo2_candy_unicorn_low` | `blender/out/evo2_candy_unicorn_low.fbx` | 133292 | `6b35ec63156ee2637cd4b48164152126bf62b2f333de7521c3f4afafd87e926e` | 72655878660168 |
| 71 | `evo2_cloudy_dragon` | `blender/out/evo2_cloudy_dragon.fbx` | 230988 | `58a25c89dbc6d14b59296f4f3b381d3e77b5b59be3dc979c367297cca6bbddf5` | 128440516283086 |
| 72 | `evo2_cloudy_dragon_low` | `blender/out/evo2_cloudy_dragon_low.fbx` | 136012 | `2cdceef2b24651e0a7a0fd099eb3e6accc93b1b0e6a41bf62411fb67761c1e6b` | 77495727832514 |
| 73 | `evo2_eclipse_dragon` | `blender/out/evo2_eclipse_dragon.fbx` | 243004 | `486f17ce6f2b3709791a8072b8760d8c4256cc4ec5407cd72bcb25fe0cf37d54` | 103211293395087 |
| 74 | `evo2_eclipse_dragon_low` | `blender/out/evo2_eclipse_dragon_low.fbx` | 144620 | `86fb599725f7b890cd91d22458528bb34ea6e61ccd34f77438be8197caf9c27f` | 116024781080229 |
| 75 | `evo2_ember_phoenix` | `blender/out/evo2_ember_phoenix.fbx` | 217836 | `a5878897bb053fc7e3948b33a67b9a25a8bac6b68c894e42f6a9f5f19760b9d9` | 121932152716311 |
| 76 | `evo2_ember_phoenix_low` | `blender/out/evo2_ember_phoenix_low.fbx` | 111532 | `8e82aa25d61ccd64ff9b46cf0f0c39020b503b842198077644087664edb62a4d` | 129351525313180 |
| 77 | `evo2_hydralotl` | `blender/out/evo2_hydralotl.fbx` | 234172 | `fff1bab71b6ec7178f20010dd1aa19cb2ea70b96ac0887dcceb66528b744fbf3` | 86677554729004 |
| 78 | `evo2_hydralotl_low` | `blender/out/evo2_hydralotl_low.fbx` | 129644 | `4d85a5c5acb0b6770edfd27130b5fea109a30e844018b716f712d9e99b76534e` | 108255604353600 |
| 79 | `evo2_magma_cub` | `blender/out/evo2_magma_cub.fbx` | 234924 | `31d92d3f70b45f3d981f43c3e08edf8c7940c1eeb05aacf7a103e96afacb1681` | 70908234081275 |
| 80 | `evo2_magma_cub_low` | `blender/out/evo2_magma_cub_low.fbx` | 117020 | `f5baf017ce6f17ffa1216f0c600561456c0537f3acd7538a7be8ed3faab65a84` | 104620513801272 |
| 81 | `evo2_moonlit_owl` | `blender/out/evo2_moonlit_owl.fbx` | 186988 | `fa89dfd0ec872671b7c2c917400a7ff74e012aaf4ab22711f9a9f196aa98855e` | 74462708768922 |
| 82 | `evo2_moonlit_owl_low` | `blender/out/evo2_moonlit_owl_low.fbx` | 108188 | `45648e2e72ecdad4e011580771149e1513fa0cb19e3d6d13ff6f203a2f205f3f` | 127699670768610 |
| 83 | `evo2_nebula_axolotl` | `blender/out/evo2_nebula_axolotl.fbx` | 223996 | `84cdfbb4d04340274a6a7f688fd28d26b164278b2f60c7d181db337975396d52` | 133259697353190 |
| 84 | `evo2_nebula_axolotl_low` | `blender/out/evo2_nebula_axolotl_low.fbx` | 123276 | `0c166f6921a0104e8a12df3426747dc19eafa2604a79372816a6887c6bb3e819` | 91217054217891 |
| 85 | `evo2_obsidian_phoenix` | `blender/out/evo2_obsidian_phoenix.fbx` | 212924 | `b0ed8109402d97ca7862e8e2568459f3c2c5f3f04412858303948bd03d981201` | 115408487250352 |
| 86 | `evo2_obsidian_phoenix_low` | `blender/out/evo2_obsidian_phoenix_low.fbx` | 115820 | `71f22d803df59206e6e1526839fca9517f49b79710329c2c868e197aa381f9f6` | 89229925420725 |
| 87 | `evo2_phantom_kitsune` | `blender/out/evo2_phantom_kitsune.fbx` | 235004 | `a29f9fde8e8beeea7a54fd572c6e5752938f3babaee53e28ef922652f28e1214` | 126683096840405 |
| 88 | `evo2_phantom_kitsune_low` | `blender/out/evo2_phantom_kitsune_low.fbx` | 125612 | `185499b5821b3529b868d29934baa3419f5c9e669317bb7a55b95b774d33f5f6` | 80582703392635 |
| 89 | `evo2_rime_wyrmling` | `blender/out/evo2_rime_wyrmling.fbx` | 257484 | `fd666678242913bd3b231c2ed7d5960d5f5238aa33f95d1b3edfbe1762e0b833` | 132691578987700 |
| 90 | `evo2_rime_wyrmling_low` | `blender/out/evo2_rime_wyrmling_low.fbx` | 154588 | `2fe96f6f3daf991cc7e30e00d2d2fac66c46a5e67af6831d9a486ac57c12795a` | 77245777274702 |
| 91 | `evo2_starlight_unicorn` | `blender/out/evo2_starlight_unicorn.fbx` | 210348 | `d25a42659caf83f098b5483f2ed05e9982152f6e92eecea96a78f03cfb9bab19` | 101065910710208 |
| 92 | `evo2_starlight_unicorn_low` | `blender/out/evo2_starlight_unicorn_low.fbx` | 129900 | `fc9b2130b60472b9d87e6d4411a71493f298a165957430973c160459ec87041d` | 92883425379575 |
| 93 | `evo2_stormfang` | `blender/out/evo2_stormfang.fbx` | 206236 | `7b5eb3ca12fa62e7cd208f6d9428474e36a50ba6f28684de2aac7594c9775619` | 71631158125067 |
| 94 | `evo2_stormfang_low` | `blender/out/evo2_stormfang_low.fbx` | 111996 | `953a0e54836d6c83b8c66cc49ad91042404e469c479b7e232bc8b62ecbdca330` | 108154765916829 |
| 95 | `evo2_sunbeam_bear` | `blender/out/evo2_sunbeam_bear.fbx` | 218524 | `67f156adb56d8deabca0784949475faf2a208a57849eaedf4feec593c10bbbbc` | 72342085606908 |
| 96 | `evo2_sunbeam_bear_low` | `blender/out/evo2_sunbeam_bear_low.fbx` | 111340 | `679f5cad11584b0b710b21d02b30a50f26e813502b63dc4faa8cb1fa6d9a5e74` | 87184391459429 |
| 97 | `evo2_twilight_dragon` | `blender/out/evo2_twilight_dragon.fbx` | 240540 | `26bb9b882ba4c0ae310d62b5c2d5cb585ae154894f435915e6d047776d311cbe` | 111719405674494 |
| 98 | `evo2_twilight_dragon_low` | `blender/out/evo2_twilight_dragon_low.fbx` | 137756 | `6ba569b03dc5a18995bc2c66408770614340d017a0110d04646d64d17ca23e74` | 128380020278617 |
