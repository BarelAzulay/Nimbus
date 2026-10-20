# blender/ - the mesh kit of Nimbus Climb (Phase 6)

Every model the player sees becomes a Blender mesh in the cute fine-voxel style (ARCHITECTURE_V3.md "## Phase 6",
technical contract = docs/phase6/recipe.md section 4).  This folder builds them: FBX for the uploader, a manifest per
key for the game's `MeshLibrary`, and preview renders for the art review.  Nothing here is uploaded; uploads happen
later with `tools/upload_assets.py` in a session that has the Open Cloud key.

## Setup (once)

```
python3 -m venv /tmp/claude-0/bpyenv
/tmp/claude-0/bpyenv/bin/pip install bpy numpy lupa pillow     # bpy 5.2 as a Python module (headless Blender)
```
`python3` with `lupa` + `numpy` is enough for everything except FBX export and Cycles previews (`--no-export`).

## Build

```
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class pets            # one catalog
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --key pet_dog --key acc_crown
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --all --preview          # + Cycles sheets of the catalogs' previews
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --list
python3 blender/kit/selftest.py                                              # hooks, recipes, determinism, manifests
```
Per key: `blender/out/<key>.fbx`, `.manifest.json`, `.tris.json.gz` (not committed, rebuilt from here) and the
committed `src/shared/MeshManifests/<key>.lua` + `blender/meshes.json` (uploader index: fbx, displayName, hashes).
Same input = same bytes (FBX timestamps zeroed, hash seed fixed) and the same `contentHash`.  Commit the generated
`.lua` files and `meshes.json` together with the catalog / kit change that made them.

Check a build: `python3 tools/render_model.py meshkey:pet_dog:pebble_pup -o x.png` (one key, coloured for a pet's
Look), `meshpet:pebble_pup[:Low]` (body + wings + accessory at the body's attachments); `python3 tools/mesh_budget.py`
(key table + the busiest phone view); `python3 tools/mesh_names.py --check blender/out/*.manifest.json`.

## How a key is made

| type | source | builder | pivot |
|---|---|---|---|
| `pet` | the game's PetBuilder sculpt via the **bridge** (`kit/bridge.py`: `PetBuilder._Blueprint(def, detail, k)` in the lupa mock) | `kit/petkit.py build_pet_body` | PetBuilder's root `Body` |
| `wing` | the same blueprint's `WingL` group (R = exact mirror) | `build_pet_wing` | the wing hinge (body attachment `WingL` / `WingR`) |
| `acc` | voxels the accessory adds (pet with it minus pet without it) | `build_pet_accessory` | body attachment `Hat` (or `attach`) |
| `boss` | `BossBuilder._Blueprint(id, k)`, one key per joint | `kit/bosskit.py` | the joint pivot |
| `prop` | Python designs registered in `kit/props/*.py` | `props.REGISTRY[name](entry, kit)` | builder origin |
| `cal` | `kit/calib.py` (cal_axes, the first upload) | | origin |

Steps for bridge keys: shaded grids from Lua (Voxel.Shade's `_Light` / `_Dark`) -> the face pass
(`kit/detail/faces.py`: puts the carved Lua eyes back, redraws mouth / blush / teeth as design cells at the mesh K,
carves procedural eyes that scale with K - pixel eyes on coarse Low grids - and makes the blink lids) -> wave-2
detail passes (`"passes": ["module:function"]`, functions `fn(bp, body_cells, entry)` in `kit/detail/`) ->
`nvox/parts.py` (name contract, deep crease shade, greedy mesher) -> colour recipes fitted from the game's own
palette code (`nvox/recipes.py`: 40+ probe Looks per pet, ops of `nvox/colors.py`, the same ops as
`MeshLibrary.EvalColor`) -> budgets -> FBX + 3 re-import checks -> manifest.

Runtime contract (recipe 4.3 / 4.4): one MeshPart per (group, palette key, shade class).  Body parts are named by
key (`Fur`, `FurLight`, `EyeIris`), group parts by group (`Tail`, `Tail2`, `WingL`..., `EyeLid`...); every part
records its `Key` (MK_Key) and `Shade`: `base` (vertex colours white / dark 0.8425,0.85,0.8875 / deep = squared;
Color = recipe), `light` (Color = `["shadeLight", recipe]`), `headroom` (Low: no light parts, vertex colours
1 / 0.87 / 0.87 x dark; Color = `["headroom", recipe]`), `fixed` (colours baked, Color white; only constant keys
that `tools/mesh_names.py` finds unreferenced, listed in `FixedKeys`).  Groups carry PetBuilder's `Spec` (PB_G) and
hinge; pet manifests carry the `Rig` string (PB_Rig at scale 1) and the attachments (WingL / WingR / Hat / Neck /
Flower / HeadCenter / Tail / EyeL / EyeR / HornBase ...).

## Add a key (wave 2)

Each art class owns ONE catalog, `blender/catalog/<class>.json` (pets, evolved, creatures, gates, lobby, home,
arenadungeon; calibration is the kit's): `{"class", "budgets": {name: {tris, parts, maxPartTris}}, "keys": [...],
"sets": [{"name", "keys", "budget"}], "previews": [{"name", "body", "attach": [keys]}]}`.  A key entry:

```
{"key": "pet_bunny", "type": "pet", "pet": "<catalog pet whose look/species it uses>", "k": 1.38,
 "strip": ["Accessory"], "budget": "pet", "description": "..."}
{"key": "pet_bunny_low", ..., "k": 0.86, "lod": "Low", "fixed": true, "budget": "petLow"}
{"key": "wing_bat_L", "type": "wing", "pet": "twilight_dragon", "side": "L", "k": 1.38, "budget": "wing"}
{"key": "acc_horns", "type": "acc", "pet": "twilight_dragon", "accessory": "Horns", "k": 1.38, "budget": "acc"}
{"key": "evo1_pebble_pup", "type": "pet", "pet": "pebble_pup", "stage": 1, "k": 1.25, "budget": "evo1"}
{"key": "boss_lava_golem_Body", "type": "boss", "boss": "lava_golem", "joint": "Body", "k": 1.5, "budget": "boss"}
{"key": "gate_obby", "type": "prop", "prop": "gate", "args": {...}, "budget": "gate"}
```
Options: `face: {eyes: "procedural"|"lua", eyeScale (1.1), features (true), featureKeys}`, `passes`, `group`
(wings: "Wing" / "Wing2"), `attach` (accessory anchor), `upload: false` (test key: blender/out only).  `k` = mesh
voxels per design unit (pets) or per boss voxel; props choose their own voxel size.

Props: `kit/props/__init__.py` documents the API (`@prop(name)`, `kit.model / kit.grid / kit.mesh`; recipes such as
`["Primary"]` stay recolourable through the ML_Primary look); `kit/props/reference.py` builds the prototype's P4
portal through it (`prop_portal_reference`, a test key).  `nvox/grid.py` is the shape kit (ell / cap / cone / box /
rbox / torus / curve / paint / carve in design units x K), `nvox/props.py` the P4 portal + cloud references,
`nvox/pets.py` the hand-ported golden references of Dog / Cat / Dragon (not used by the build).

## Budgets (recipe 4.2; the build FAILS when a key is over)

Too many triangles -> K x 0.9, up to 2 times, then fail; too many MeshParts or > 10k triangles in one part -> fail;
catalog `sets` (body + wings + accessory) are summed after the run.  Pets (W1 golden path, `catalog/pets.json`):

| key | K | tris | parts |
|---|---|---|---|
| pet_dog / _low | 1.38 / 0.86 | 4516 / 1982 | 22 / 19 |
| pet_cat / _low | 1.242 / 0.774 (stepped) | 4128 / 1796 | 22 / 19 |
| pet_dragon / _low | 1.242 (stepped) / 0.86 | 3846 / 2130 | 24 / 21 |
| wing_feather_L, _R / _low | 1.38 / 0.86 | 494 / 258 each | 7 / 4 |
| acc_crown / _low | 1.38 / 0.86 | 754 / 322 | 3 / 3 |
| set dog + feather + crown | | 6258 / 6500 (Low 2820 / 3000) | 39 / 40 (Low 30 / 32) |

Low sets keep ~30 MeshParts (one per palette key, the name contract) instead of the recipe's 14; identical meshes
are instanced by Roblox, so draw calls grow with distinct keys, not with copies.  Review sheets:
`docs/phase6/review/kit/`.
