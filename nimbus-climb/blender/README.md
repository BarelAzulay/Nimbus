# blender/ - the mesh kit of Nimbus Climb (Phase 6)

Every model the player sees becomes a Blender mesh in the cute fine-voxel style (ARCHITECTURE_V3.md "## Phase 6",
technical contract = docs/phase6/recipe.md section 4).  This folder builds them: FBX for the uploader, a manifest per
key for the game's `MeshLibrary`, and preview renders for the art review.  Nothing here is uploaded; uploads happen
later with `tools/upload_assets.py` in a session that has the Open Cloud key (checklist:
`docs/phase6/OWNER_UPLOAD.md`).  Until then `src/shared/MeshIds.lua` is empty and the game shows the Part builds.

## Setup (once)

```
python3 -m venv /tmp/claude-0/bpyenv
/tmp/claude-0/bpyenv/bin/pip install bpy==5.2.2 numpy lupa pillow  # bpy 5.2.2 (pinned: the FBX bytes hold the version)
```
`python3` with `lupa` + `numpy` is enough for everything except FBX export and Cycles previews (`--no-export`).

### Windows

bpy 5.2.2 has no wheel for Python 3.12 (`pip download bpy==5.2.2` finds none); it needs Python 3.13:
```
winget install -e --id Python.Python.3.13
py -3.13 -m venv %USERPROFILE%\.bpyenv
%USERPROFILE%\.bpyenv\Scripts\python.exe -m pip install bpy==5.2.2 numpy lupa pillow
%USERPROFILE%\.bpyenv\Scripts\python.exe blender/build_all.py --class vfx --preview      # export builds + previews
py -3.12 blender/kit/selftest.py                                                         # no bpy needed (lupa + numpy)
```
Use that venv's python wherever this file says `/tmp/claude-0/bpyenv/bin/python`.  `build_all.py` re-runs itself
with `PYTHONHASHSEED=0` through a child process on Windows (no `exec` there) and locks `meshes.json` with
`msvcrt` instead of `fcntl`.  Installing 3.13 makes it the `py` launcher's default: name the version (`py -3.12`).

## Build

```
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class pets            # one catalog (--class is repeatable)
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --key pet_dog --key acc_crown
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --all --preview          # + Cycles sheets of the catalogs' previews
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --class gates --preview  # only that class's preview sheets
/tmp/claude-0/bpyenv/bin/python blender/build_all.py --list
python3 blender/kit/selftest.py                                              # hooks, recipes, determinism, manifests
```
Classes (one catalog each, `blender/catalog/<class>.json`): `calibration` (cal_axes + the test key
prop_portal_reference), `pets` (94 keys), `evolved` (354), `creatures` (60), `gates` (6), `lobby` (63), `home` (168),
`arenadungeon` (52), `vfx` (22, the pet attack effect cores): 820 uploadable keys (W3 added `prop_plot_low` and the 80 home plot `_low` keys
`home_<stem>_<level>_low`).  `blender/out/previews/<name>.png` holds the preview sheets; a catalog preview with
`"sheet": [keys]` renders a labelled contact sheet of single-part keys instead (front / three-quarter / side / top,
tinted with `"tint"`) to `blender/<out>` (vfx: `blender/vfx/out/cores_preview.png`).
Per key: `blender/out/<key>.fbx`, `.manifest.json`, `.tris.json.gz` (not committed, rebuilt from here) and the
committed `src/shared/MeshManifests/<key>.lua` + `blender/meshes.json` (uploader index: fbx, displayName, hashes,
`fbxSha256` = the sha256 of the FBX exported and verified for this contentHash).
Same input = same bytes (FBX timestamps zeroed, hash seed fixed) and the same `contentHash`.  Commit the generated
`.lua` files and `meshes.json` together with the catalog / kit change that made them.

Check a build: `python3 tools/render_model.py meshkey:pet_dog:pebble_pup -o x.png` (one key, coloured for a pet's
Look), `meshpet:pebble_pup[:Low]` (body + wings + accessory at the body's attachments; the accessory at its manifest
Meta.attach), `meshevo:<petId>:<1|2>[:Low]` (evolved body + its evowing_ pairs); `python3 tools/mesh_budget.py`
(key table + the busiest phone view: pet sets only, plus 4 max-tier home plots); `python3 tools/mesh_names.py --check blender/out/*.manifest.json`.

## How a key is made

| type | source | builder | pivot |
|---|---|---|---|
| `pet` | the game's PetBuilder sculpt via the **bridge** (`kit/bridge.py`: `PetBuilder._Blueprint(def, detail, k)` in the lupa mock) | `kit/petkit.py build_pet_body` | PetBuilder's root `Body` |
| `wing` | the same blueprint's `WingL` group (R = exact mirror) | `build_pet_wing` | the wing hinge (body attachment `WingL` / `WingR`) |
| `acc` | voxels the accessory adds (pet with it minus pet without it) | `build_pet_accessory` | body attachment `Hat` (or `attach`) |
| `boss` | `BossBuilder._Blueprint(id, k)`, one key per joint | `kit/bosskit.py` | the joint pivot |
| `prop` | Python designs registered in `kit/props/*.py` (gates, lobby, home, arena, dungeon, sky dragon, pedestal, tokens, vfx cores) | `props.REGISTRY[name](entry, kit)` | builder origin |
| `cal` | `kit/calib.py` (cal_axes, the first upload) | | origin |

Steps for bridge keys: shaded grids from Lua (Voxel.Shade's `_Light` / `_Dark`) -> the face pass
(`kit/detail/faces.py`: puts the carved Lua eyes back, redraws mouth / blush / teeth as design cells at the mesh K,
carves procedural eyes that scale with K - pixel eyes on coarse Low grids - and makes the blink lids) -> wave-2
detail passes (`"passes": ["module:function"]`, functions `fn(bp, body_cells, entry)` in `kit/detail/`; they also run
with `"face": {"eyes": "lua"}`, which keeps PetBuilder's own carved eyes and lids) ->
`nvox/parts.py` (name contract, deep crease shade, greedy mesher) -> colour recipes fitted from the game's own
palette code (`nvox/recipes.py`: 40+ probe Looks per pet, ops of `nvox/colors.py`, the same ops as
`MeshLibrary.EvalColor`) -> budgets -> FBX + 3 re-import checks -> manifest.

Special pet-type keys (wave 2 / 2.5):

* **Evolved bodies** `evo1_<petId>` / `evo2_<petId>` (+ `_low`): `"stage": 1|2` and the passes `evolved:body`,
  `evolved:aura`.  There are no separate `aura_<kind>` keys: every evolved body carries its own `Aura` group (kind
  orbit, Spec `Aura:orbit:1:0.8:0`), and second evolutions a `Halo` group (kind bob, a crown of light) when the pet
  has no halo of its own.  Wings: `evowing_<petId>_<stage>_<L|R>[_low]` (`"group": "Wing"` or `"Wing2"`).
* **Hybrids** `hyb_<species>` (15) and `hyb_same`: High only (no `_low`; Low hybrids use the High key).  A pet entry
  with a hybrid `look` and the pass `pets_hyb:isolate`: the key holds only what the hybrid ADDS to the reference body
  (pebble_pup; hyb_dog uses mallow_kitten), with painted keys raised one fine voxel off the surface so they never
  z-fight.  `"raiseAll": false` raises only the `Hy*` keys (hyb_penguin: its raised feet went over the 2000-triangle
  budget).  `hyb_dog_ears` / `hyb_bear_ears` are built on puddle_frog (an earless body); PetBuilder picks them for a
  dog / bear hybrid on an earless species.
* **Gates**: 6 keys `gate_<obby|ring|arena|dungeon|home|altar>`, one per crest (`WorldStyle.GateMeshKey(shape,
  glyph)`); every `BuildGate` gate with that crest shares it (arena gates, the dungeon portal, the arena's Return
  gate wears `gate_home`).  Neon parts stay Roblox parts (keep lists).
* **World keys** (lobby, home, arena, dungeon) bake today's Part build; a `LayoutSig` in the manifest must match the
  live build, otherwise that piece stays on its Parts until it is rebuilt.

Geometry check (build_all `check_geometry`): every part's quads must have area and every group must be closed,
except see-through parts (Glass / ForceField / Transparency > 0), which by design emit faces only towards empty space
(`nvox/mesher.py`); their opaque neighbours are still checked.

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
{"key": "evo1_pebble_pup", "type": "pet", "pet": "pebble_pup", "stage": 1, "k": 1.25, "budget": "evo1Body", "passes": ["evolved:body", "evolved:aura"]}
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
catalog `sets` (body + wings + accessory) are summed after the run, over EVERY catalog (another class's set over budget
also makes `build_all` exit 1).  The numbers live in each catalog's `budgets` (triangles / MeshParts); today:

| catalog | budgets (tris / parts) |
|---|---|
| pets | pet 4750 / 26, petLow 2150 / 22, wing 700 / 8, wingLow 320 / 5, acc 1000 / 6, accLow 400 / 6, hyb 2000 / 10, wingStorm 3000 / 8; sets setHigh 6500 / 40, setLow 3000 / 32 |
| evolved | evo1Body 11500 / **44**, evo1BodyLow 3700 / 36, evo1Wing 1750 / 12, evo2Body 14800 / 50, evo2BodyLow 4500 / 40; sets evo1 15000 / 64, evo1Low 4500 / 52, evo2 20000 / 110, evo2Low 6000 / 84 (the auras count inside) |
| creatures | boss 15000 / 48 (joint 10000 / 16), skydragon 12000 / 110, npc 4000 / 20, token 2000 / 8, fx 1200 / 6, star 300 / 3 |
| gates | gate 8000 / 20 |
| lobby | prop 2000 / 8, propBig 4000 / 8, plot 9000 / 8, cloud 3500 / 2, island 14000 / 3, floor 10000 / 8, centrepiece 7500 / 8 |
| home | station 4000 / 8, stationBig 8000 / 8, decor 2000 / 8, house 10000 / 8, element 600 / 2 |
| arenadungeon | tiny 900 / 4 ... island 36000 / 8 |
| vfx | core 2000 / 1, coreBig 4000 / 1 (shell, cage), sig 6000 / 1 (one MeshPart `Core` per key) |

evo1Body went from 40 to 44 parts in wave 2.5: keys that tests look up by name (Spark, EyeIris, EyeGlint, EyeRing,
Basalt, HydraHead ...) may no longer be baked into `Fixed`, so a few bodies have more parts.  Any new by-name lookup
in the game or a test (`tools/mesh_names.py` lists them) can unbake a key: rebuild pets and evolved afterwards.
The whole scene: `python3 tools/mesh_budget.py` (the busiest phone view, 300k triangles / 400 parts; `--check`).

W1 golden path, for scale:

| key | K | tris | parts |
|---|---|---|---|
| pet_dog / _low | 1.38 / 0.86 | 4516 / 1982 | 22 / 19 |
| set dog + feather + crown | | 6258 / 6500 (Low 2820 / 3000) | 39 / 40 (Low 30 / 32) |

Low sets keep ~30 MeshParts (one per palette key, the name contract) instead of the recipe's 14; identical meshes
are instanced by Roblox, so draw calls grow with distinct keys, not with copies.  Review sheets:
`docs/phase6/review/<class>/`.

## Gotchas

* `--no-export` (plain `python3`, no bpy) still rewrites `src/shared/MeshManifests/` and `meshes.json`: finish with an
  export build before committing. meshes.json then has "fbxSha256": null for every key whose contentHash changed, and
  tools/upload_assets.py refuses that key until an export build with /tmp/claude-0/bpyenv/bin/python (a key whose
  contentHash did not change keeps its sha: that FBX still matches).
* Upload a class with `python3 tools/upload_assets.py --class <class>` (dry run; `--upload` only with the owner's OK,
  `docs/phase6/OWNER_UPLOAD.md` section 5): it takes the catalog's upload keys, `_low` keys included.
* After any build, `git status`: changed manifests + `meshes.json` go into the same commit as the catalog / kit
  change.  A changed `structureHash` means the next upload makes a NEW asset id (see `docs/phase6/OWNER_UPLOAD.md`).
* Waiting on a background build: never `pgrep -f "build_all.py --class ..."` (it matches its own shell).

## Textures

`blender/textures/build_vortex.py` (numpy + Pillow, seeded) writes the 10 white + alpha PNG layers of the gate vortex
to `blender/textures/vortex/` and the uploader index `blender/textures/textures.json`; uploaded with
`python3 tools/upload_assets.py --textures` (dry run by default) into `src/shared/TextureIds.lua`.  It has no `--help`:
running it builds at once (same bytes every time).
