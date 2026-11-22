# Evolved eyes re-bake: upload hand-over (98 evolved body meshes)

Pitch 2 item 7, option A "Trim" (spec `docs/superpowers/specs/2026-11-20-pitch2-build-design.md` item 7, plan Task 12).
Owner's decision 2026-11-20: re-bake the evolved pet meshes in Blender so the trimmed eyes show in game, and prepare
the upload (not do it). This file is the hand-over for the owner's keyed cloud session.

**Status: PREPARED, NOT UPLOADED.** Nothing was sent to Roblox from the PC. `src/shared/MeshIds.lua`,
`src/shared/MeshManifests/` and `blender/meshes.json` on this branch are unchanged, so the game keeps the live meshes
(the old 8 x 9 eyes) until the upload session lands the new manifests and the new ids together.

**This list replaces the one of `76cee35`.** Its review found two faults, both fixed and rebuilt here:

1. **The Low meshes lost their eyes.** The `_low` keys scaled the trimmed 6 x 7 High eye down to the coarse Low grid:
   the owls' pupil went from 13 x 4 to 1 x 1 (glint and lash gone, the evo2 owl had no eye at all), the dragons lost
   the glint, Stormfang's eye was a grey / white jumble. Fix `4071cbd`: every `_low` key now carves the game's own
   Low eye (`EvoLow` / `EvoFierceLow`, 4 x 4, unchanged by the approved trim, the eye the Low Part build draws) one
   voxel per pixel: lash, highlight, pupil, iris and glint in both eyes, mirrored; the owls' gold EyeRing disc is kept
   and the eye is carved into it.
2. **11 keys were re-voxelized.** The smaller eyes cut the triangle count, so the K-step budget loop stopped one step
   earlier and rebuilt the whole pet on a finer grid (`evo1_stormfang` 0.0889 -> 0.080 studs a voxel,
   `evo1_phantom_kitsune`, 9 Low keys). Fix `3a9eb85`: every key keeps the K step of the pre-trim build (25 pins,
   `blender/kit/detail/evolved_catalog.py` `K_STEP`, catalog `kStep`). Now ONLY the eyes change (proof below).

Changed against the `76cee35` list: 51 keys (all 49 `_low` + `evo1_stormfang` + `evo1_phantom_kitsune`); the other 47
High keys have the same bytes as before.

## For the owner, in short

- The 9 pets of the approved sheet were re-baked from Blender with the smaller eyes. They match column A of the sheet
  (`evo_eyes/evo1_eyes_vs_sheetA.png`).
- The far-away (`_low`) meshes now show the game's own small Low eye, the same as the Low Part build, with every
  feature (`evo_eyes/low_problem_pets_zoom.png`: owls, Stormfang, Phantom Kitsune, dragons; every Low pet:
  `evo_eyes/low_evo1_1..3.png`, `low_evo2.png`).
- All 98 evolved body meshes change: 49 High + 49 `_low`, first and second evolutions. Wings (`evowing_`) carry no
  eyes and stay as they are. Nothing but the eyes changes: same voxel grid, same body (proof below).
- Each of the 98 becomes a **new** Roblox asset with a new id, because its part structure changed (structureHash).
  Until Roblox approves a new asset, that pet shows its Part build (heavier: about 1,200 to 1,450 parts).
- Your OK is needed before the upload. Run it in the keyed cloud session, never from a PC.

## What was built on the PC (and checked)

| | |
|---|---|
| Source | branch `kitb-p2-eyes` @ `3a9eb85` (eye masks `c116b44`, Low eyes `4071cbd`, K-step pins `3a9eb85`) |
| Tool | `blender/build_all.py`, export build, Blender as a Python module: bpy 5.2.2 on Python 3.13 (`%USERPROFILE%\.bpyenv`) |
| Keys | the 98 `evo1_*` / `evo2_*` keys in `evo_eyes/keys.txt`: 98 built, 0 failed, every FBX re-import checked (3 times) |
| Size | 15,384,216 bytes in all, 257,484 bytes for the largest file |
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
The Low eye is the game's own Low mask, so a far pet looks like its Low Part build (`evo_eyes/evo1_low_eyes.png`).
On the coarse Low grid it is 1.1-1.2 x the height of the High eye in studs (before: 1.1-1.4 x); the dragons' 4 x 4
fierce Low eye is 1.6 x their 6 x 5 High eye (before: 1.2 x), and the same height as their live Low eye (narrower).

## Proof that only the eyes change (`evo_eyes/verify_diff.json`)

The same 98 keys were also built (no export) from the pre-trim commit `c733fe0` and compared with this build:

- **Voxel grid:** K and voxelStuds equal on 98 of 98 keys (the reviewed `76cee35` build: 11 keys differed).
- **Every Body voxel:** 12786 changed voxels lie in the eye area (the columns either build carved for an eye: the kit's
  lids + PetBuilder's own carve). Outside it: 343 shade-only changes (the same colour, only its _Light / _Dark / Deep
  variant: the kit shades a voxel from its neighbours and the eye is a hole one voxel deep), at most 3 voxels from the
  eye, and 4 colour changes: `evo1_blossom_bunny_low` / `evo1_honey_bunny_low` GemGlint -> GemB at (+-3, 9), the
  tiara gem's glint pixel 1 voxel above the eye, which moves because the smaller eye uncovers the gem's lower pixel.
- **Manifest part lists:** no other manifest field changes (attachments, rig, bounds, groups other than the lids).
  Eye parts (EyePupil / EyeIris / EyeShine / EyeGlint / EyeRing / Lash / EyeLid*) change on every key. Non-eye parts:
  their triangles change around the eye on every key (the face is re-meshed where the eye hole changed); a new part
  appears where the smaller eye uncovers a face feature the old eye covered whole: `evo1_aurora_fox_low` Blush, `evo1_bamboo_panda_low` Blush, `evo1_biscuit_bear_low` Nose, `evo1_cherry_panda_low` Blush, `evo1_maple_fox_low` Blush, `evo1_nebula_axolotl_low` Blush, `evo1_obsidian_phoenix_low` Beak, `evo1_pebble_pup_low` Nose, `evo1_sunbeam_bear_low` Nose, `evo2_hydralotl` Blush, `evo2_nebula_axolotl` Blush, `evo2_stormfang_low` Nose. Non-eye part boxes that
  change (Blush, Nose, Fixed, Gold ...) change only through the eye-area voxels above.

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
   git merge-base --is-ancestor 3a9eb85 HEAD && echo ok   # the trimmed eyes, the Low eyes and the K-step pins
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
   Expect `98 of 98 match`. A mismatch means PetBuilder or the kit changed after `3a9eb85`. In that case
   tell the lead, re-render the previews (`python3 tools/render_model.py meshevo:<pet>:1`) and wait for the owner
   before uploading.
4. **Offline checks** (section 2.2):
   ```bash
   python3 tools/test_upload_assets.py
   python3 tools/mesh_names.py --check blender/out/*.manifest.json
   python3 blender/kit/selftest.py --only evoeyes      # the Low eyes + the K-step pins
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
   Garden pets and other players' followers use the `_low` meshes (`evo_eyes/low_problem_pets_zoom.png`).
   Then publish (section 7).

Roll back (section 9): put the old ids back by removing the new lines. The old ids stay in `upload_state.json`
under `previousAssetIds`, and the old manifests are in git history at `3a9eb85` (unchanged since the live upload).

## Evidence (this folder)

| file | what |
|---|---|
| `evo_eyes/evo1_eyes_vs_sheetA.png` | the 9 sheet pets, front + 3/4: approved sheet column A, the Part build, the re-baked mesh |
| `evo_eyes/evo2_eyes.png` | second evolutions of the 6 sheet pets that have one: Part build vs re-baked mesh |
| `evo_eyes/evo1_low_eyes.png` | the 9 sheet pets' `_low` meshes vs the Low Part build (the same 4 x 4 Low eye) |
| `evo_eyes/low_evo1_1.png` .. `low_evo1_3.png`, `low_evo2.png` | EVERY Low key: pre-trim (live look) / reviewed `76cee35` / this build, front + 3/4 |
| `evo_eyes/low_problem_pets_zoom.png` | the review's problem pets at Low (owls, Stormfang, Phantom Kitsune, dragons), large |
| `evo_eyes/evo1_drift_keys.png` | the 4 design-drift keys (Hydralotl, Magma Cub; High + Low) |
| `evo_eyes/fbx_in_blender.png` | the exported FBX files opened in Blender 5.2.2 (parts tinted by name only; lids hidden) |
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
| 2 | `evo1_aurora_fox_low` | `blender/out/evo1_aurora_fox_low.fbx` | 125420 | `0caa6259453eb01ac4ac4e6697feec4cb64951ba5054b1a1d93a11a6bb748bc1` | 77788282454956 |
| 3 | `evo1_bamboo_panda` | `blender/out/evo1_bamboo_panda.fbx` | 177932 | `e13dc9fa8fa11afa9464f173d9a8ab1cc4b999afaa1ee519493791b7dec7def7` | 104363918642473 |
| 4 | `evo1_bamboo_panda_low` | `blender/out/evo1_bamboo_panda_low.fbx` | 101324 | `8265e17a5a29116b3ad2b4f81f23a14eba5d7844556038d8aa3000cefcedf818` | 129482935584530 |
| 5 | `evo1_biscuit_bear` | `blender/out/evo1_biscuit_bear.fbx` | 167004 | `3dba1d8732708b777d1d5cbf7428f0209be72c2d97246d23c6a42df321cb5e79` | 73735764977613 |
| 6 | `evo1_biscuit_bear_low` | `blender/out/evo1_biscuit_bear_low.fbx` | 103964 | `0cced476b07d1bd0ee557b703560f6e6cbaca6656afdbd8cb0de0edec4eed344` | 99723032833610 |
| 7 | `evo1_blossom_bunny` | `blender/out/evo1_blossom_bunny.fbx` | 183532 | `438985ad3eacde6deeb2aa8e1129b71eb98adf18eca9d07eef7951ac82678d08` | 82394928828450 |
| 8 | `evo1_blossom_bunny_low` | `blender/out/evo1_blossom_bunny_low.fbx` | 116748 | `7bc6d8a33e8a22c4190dc52f6084c74c72880b9a98360ee2ff734cff63d7bb70` | 75253507719284 |
| 9 | `evo1_bubble_axolotl` | `blender/out/evo1_bubble_axolotl.fbx` | 178972 | `45f9cf70a1d9ebbddd845e1cbb629e3e7156313012c5ff3dad3069c9be0bc3c7` | 92767577680778 |
| 10 | `evo1_bubble_axolotl_low` | `blender/out/evo1_bubble_axolotl_low.fbx` | 100796 | `f86fec78eb59aa8b5756ab8cb5ca708993bf2ceb08de4db4ace333bd6eb2cd56` | 138245964799147 |
| 11 | `evo1_candy_unicorn` | `blender/out/evo1_candy_unicorn.fbx` | 189884 | `4e15f65df68ff3ce5747da2db5f2f9dbde2cf55c60d9c12e03f365a62548de49` | 137467109507967 |
| 12 | `evo1_candy_unicorn_low` | `blender/out/evo1_candy_unicorn_low.fbx` | 123308 | `ad67dc40a3196ecb2df84f64a191c33a51089e6dae16581c64b6ed774bda7dfb` | 83858413665107 |
| 13 | `evo1_cherry_panda` | `blender/out/evo1_cherry_panda.fbx` | 184972 | `92f92f6b28c593c0342ed2684edf07e3a76061eca7653d7fdf2a8efa89ec538e` | 110836396681656 |
| 14 | `evo1_cherry_panda_low` | `blender/out/evo1_cherry_panda_low.fbx` | 104780 | `0cc2f73d06e713407f26fe12de9d93f9a692145bf72b7847e9b5dd9d2bc0877c` | 118659270989807 |
| 15 | `evo1_cloudy_dragon` | `blender/out/evo1_cloudy_dragon.fbx` | 185372 | `bb4777f79114b792811305722070efc532c676cdf11c0d92d4e4179be463d774` | 124282700617318 |
| 16 | `evo1_cloudy_dragon_low` | `blender/out/evo1_cloudy_dragon_low.fbx` | 117836 | `790056ff24bde36933fc6067ad5f357834d2114259631c9b6e896de175df1681` | 93000498845226 |
| 17 | `evo1_eclipse_dragon` | `blender/out/evo1_eclipse_dragon.fbx` | 194908 | `81ad4d7f643300c029412de5c8e9bad10420f24c390f15d286f1afe0c52869fc` | 115587997700525 |
| 18 | `evo1_eclipse_dragon_low` | `blender/out/evo1_eclipse_dragon_low.fbx` | 116764 | `b1d81c568289becc56ec3491b38f3a63894ac360a7097ced83720198526bbe40` | 120102054910553 |
| 19 | `evo1_ember_phoenix` | `blender/out/evo1_ember_phoenix.fbx` | 166828 | `b2b2ae5085ee78c040978d76c1784a285b74093897a095df984f2e55b269279f` | 85951869370892 |
| 20 | `evo1_ember_phoenix_low` | `blender/out/evo1_ember_phoenix_low.fbx` | 109564 | `671fe4b54947e603cc2d9c48621871d9f9531920475ab52d984de0f4bd285ccf` | 127384591685930 |
| 21 | `evo1_frostling_penguin` | `blender/out/evo1_frostling_penguin.fbx` | 177100 | `8c992204233c7144bd853903a924b3757c1b65c6cc5e78e23fb1765850422a15` | 87839970044677 |
| 22 | `evo1_frostling_penguin_low` | `blender/out/evo1_frostling_penguin_low.fbx` | 104492 | `dc4eca41ddd20a88f63b461d0c15447b0735f5f8e171a1ff26655a4668141aec` | 117375525292782 |
| 23 | `evo1_honey_bunny` | `blender/out/evo1_honey_bunny.fbx` | 177868 | `165948631e735c4f74db472dc840ba5e203bbb363f1d9228280c2ed6c5824cf2` | 134835417429640 |
| 24 | `evo1_honey_bunny_low` | `blender/out/evo1_honey_bunny_low.fbx` | 110956 | `2caf3f7a31ff02dcce896a0c6fb130947860ae344a8d45e7c64f60df51745f5d` | 139060124292304 |
| 25 | `evo1_hydralotl` | `blender/out/evo1_hydralotl.fbx` | 201628 | `52479cee0d43bdcf6a0654b14bd357abd3630e679aba6a67c72f853a2070bc58` | 107330994952547 |
| 26 | `evo1_hydralotl_low` | `blender/out/evo1_hydralotl_low.fbx` | 111804 | `aca6c78827a80ddb6a105e7beed6b8c044a93a6494350d367b3f3fa52fd76e79` | 75165208362476 |
| 27 | `evo1_magma_cub` | `blender/out/evo1_magma_cub.fbx` | 197164 | `22975e91ca9871a15b4737ac45887bf8fa2345457d4d30996421ec9b38a073d5` | 128171047724691 |
| 28 | `evo1_magma_cub_low` | `blender/out/evo1_magma_cub_low.fbx` | 110460 | `2616ee5bfd032b62376add0246fe74c3134be66abd82fb494d38c30cfd5a93a1` | 111156779183723 |
| 29 | `evo1_mallow_kitten` | `blender/out/evo1_mallow_kitten.fbx` | 196940 | `0d1714ebb228073845022da86272eeb9ea17839b896dacf0611aeafa781cc881` | 76487641815372 |
| 30 | `evo1_mallow_kitten_low` | `blender/out/evo1_mallow_kitten_low.fbx` | 117436 | `3bebf987a7ec043c6fa281110c00577a6acc1533f5c7524914622dee7e769794` | 108260487493804 |
| 31 | `evo1_maple_fox` | `blender/out/evo1_maple_fox.fbx` | 185180 | `af9b27b7c90eb07527e465a03e93e874a6b054ac5c26db74b863c5ed71a48fdb` | 105335734155111 |
| 32 | `evo1_maple_fox_low` | `blender/out/evo1_maple_fox_low.fbx` | 113084 | `cb10a3e5e09f2cd6305fb2cba96c546ba9d353ccfd1b43b295dabc873e3016e2` | 71314104979558 |
| 33 | `evo1_mochi_slime` | `blender/out/evo1_mochi_slime.fbx` | 134460 | `2390cd6e74a2a9ba8ba25d164c31ecab461afa8e84199bc8d7d1a734e1aa940c` | 140278769359069 |
| 34 | `evo1_mochi_slime_low` | `blender/out/evo1_mochi_slime_low.fbx` | 85772 | `586f9d42c33f0afa84b421f66518ec38ee90ba66c94ac227f57339d51a1d665c` | 121585707246125 |
| 35 | `evo1_moonlit_owl` | `blender/out/evo1_moonlit_owl.fbx` | 177004 | `eb70c86a3140a466a8195109ac9b14653e50d26308fe38b19ba55739978ea7fb` | 113642919127042 |
| 36 | `evo1_moonlit_owl_low` | `blender/out/evo1_moonlit_owl_low.fbx` | 106556 | `fd3559915a597d0c1dfede1d3c3e9acd50483bad749092ca27bbf5d8da83b001` | 87552810305165 |
| 37 | `evo1_nebula_axolotl` | `blender/out/evo1_nebula_axolotl.fbx` | 176844 | `d749d5e3ba8a5e9bfbb8689b391a83893038b518497ebcfdf5a42a794cb7d6bd` | 87331681854879 |
| 38 | `evo1_nebula_axolotl_low` | `blender/out/evo1_nebula_axolotl_low.fbx` | 113724 | `b2b1ac888eceec0fe39771383494819e2c792d8ef425c073540532c0e4adec82` | 135511552169009 |
| 39 | `evo1_obsidian_phoenix` | `blender/out/evo1_obsidian_phoenix.fbx` | 193100 | `74cc4183cec875fd9f6a0ec4abcfa253afa3e2e357adc0ffba892aa04e6dc455` | 84691219969375 |
| 40 | `evo1_obsidian_phoenix_low` | `blender/out/evo1_obsidian_phoenix_low.fbx` | 120700 | `a8df793eef48a2815d9b62b4a2a8c0d2763dd0caf4cfb8ca2cbee05d0ea14b24` | 136278315485979 |
| 41 | `evo1_pebble_pup` | `blender/out/evo1_pebble_pup.fbx` | 184860 | `6a1300bcc2c8c522292bce67ba4faafc086d84efb3c8f66106588cc5fd30596a` | 75795178584683 |
| 42 | `evo1_pebble_pup_low` | `blender/out/evo1_pebble_pup_low.fbx` | 115148 | `ae09b4f3133f07b7a95a64c6decb3fd0bc83d3723252b46fe7ffebab75018de5` | 73658366816678 |
| 43 | `evo1_phantom_kitsune` | `blender/out/evo1_phantom_kitsune.fbx` | 196012 | `3f805ef864cc383fa6e61798e10e705230aca98fd3ab0dd7db2ead4418e187a5` | 109492203546111 |
| 44 | `evo1_phantom_kitsune_low` | `blender/out/evo1_phantom_kitsune_low.fbx` | 113020 | `e669af7085f2b808ad8e485d85a159fe7d1388a998443c7ab623bdb28a4e96ea` | 73193456925742 |
| 45 | `evo1_pip_penguin` | `blender/out/evo1_pip_penguin.fbx` | 171708 | `0faaa6157f8a354e8ee16deb4d755af1c44542b5ae7b28057cb34e637e25df12` | 102583552628564 |
| 46 | `evo1_pip_penguin_low` | `blender/out/evo1_pip_penguin_low.fbx` | 102268 | `3f55bdb72a8f45947ac4f6d98c1cff575ca78d536975acea20709e5fca7ebff5` | 119159628161633 |
| 47 | `evo1_puddle_frog` | `blender/out/evo1_puddle_frog.fbx` | 165772 | `28b46fb04faa5ef15ad0f52c3f5acccc4cca90919c7537be8f87965163595fdb` | 72369315852282 |
| 48 | `evo1_puddle_frog_low` | `blender/out/evo1_puddle_frog_low.fbx` | 100620 | `594c5f404ecc802d479345c072635a5118e7b0ae1cbf9b7594c999f5f931ef6a` | 109508565800347 |
| 49 | `evo1_rime_wyrmling` | `blender/out/evo1_rime_wyrmling.fbx` | 219532 | `99321ec7b7ad7781c66e7ceb3a508be096abdb377e718e1db520c0ba21487f81` | 139595966133024 |
| 50 | `evo1_rime_wyrmling_low` | `blender/out/evo1_rime_wyrmling_low.fbx` | 134796 | `6178bc6574819279ec9a581249ebf6a114143a247b7ba7b43e10782716008419` | 97518265520464 |
| 51 | `evo1_shroomie_frog` | `blender/out/evo1_shroomie_frog.fbx` | 162988 | `7ee18447cb0c2ab9aafdc93f2209ccfeacbba02edd22e28b443c60c9ecba6fcc` | 113280357489430 |
| 52 | `evo1_shroomie_frog_low` | `blender/out/evo1_shroomie_frog_low.fbx` | 102348 | `389dd9d48647344737ccd4fa0d5905df5a99662c9fd90e40495b81b54affbeab` | 89302304972875 |
| 53 | `evo1_sleepy_owl` | `blender/out/evo1_sleepy_owl.fbx` | 172076 | `65f24ed909369542a49bf9885b06492f0ddb32608ac03802f794d239a25bc012` | 123215045455041 |
| 54 | `evo1_sleepy_owl_low` | `blender/out/evo1_sleepy_owl_low.fbx` | 104524 | `6fd99a1007577135990c0f70eeaa0810ddfb3588fc7c7d0711447896733e4057` | 104696782911723 |
| 55 | `evo1_starlight_unicorn` | `blender/out/evo1_starlight_unicorn.fbx` | 194348 | `169f7d523368c33f79a6aded3556ec61cd6090320544f0ea63f034b6363071e2` | 129258425301120 |
| 56 | `evo1_starlight_unicorn_low` | `blender/out/evo1_starlight_unicorn_low.fbx` | 124908 | `e1d9131d2205f939f018eeb07ec1857ef399eed333eed45ca47cc30c3324941d` | 113879047878339 |
| 57 | `evo1_storm_tabby` | `blender/out/evo1_storm_tabby.fbx` | 186732 | `b85e8d2ee6a9ced7d6d9143360b481ddb2a212f6dab09cf42d5b72c9a037b282` | 90763597503307 |
| 58 | `evo1_storm_tabby_low` | `blender/out/evo1_storm_tabby_low.fbx` | 111804 | `a9c93e448179395a459168e0cf77f047f76ded6edf5b881e09ff35f09208ce1a` | 72832808211675 |
| 59 | `evo1_stormfang` | `blender/out/evo1_stormfang.fbx` | 181916 | `f9f508d1f30da3c567774f78a8ab4721953ad05f30f57c088d84fc6c920cd051` | 93119026859574 |
| 60 | `evo1_stormfang_low` | `blender/out/evo1_stormfang_low.fbx` | 113772 | `6b69b794b6837690c443111c6367b5a229d6cf9ec35264d763840bfd47362b31` | 76844743783547 |
| 61 | `evo1_sunbeam_bear` | `blender/out/evo1_sunbeam_bear.fbx` | 180876 | `64dd39c91f6400acd5744f82db3d8bd73d9dd28f796045e55dce98a37053fca3` | 81137217654376 |
| 62 | `evo1_sunbeam_bear_low` | `blender/out/evo1_sunbeam_bear_low.fbx` | 111548 | `02c6f122ea74862bddfe1254ab87ca9712d0a22a1c266e6a73c25060fad46a8e` | 130314648949999 |
| 63 | `evo1_twilight_dragon` | `blender/out/evo1_twilight_dragon.fbx` | 182028 | `dc161936ee3a0afc44bc82427e0098f59996dbb21c343fb471a75903b19631c9` | 139255105971705 |
| 64 | `evo1_twilight_dragon_low` | `blender/out/evo1_twilight_dragon_low.fbx` | 110812 | `02db3bf5118b76c3b30f88ee70503bb8e08837663bed5aecc327b06d80218190` | 122058642544043 |
| 65 | `evo1_waffle_corgi` | `blender/out/evo1_waffle_corgi.fbx` | 194988 | `a43c5a19ab3a58503096aa97447f46441d228e74c60bfaafe4c2a16bcd078329` | 121575312945918 |
| 66 | `evo1_waffle_corgi_low` | `blender/out/evo1_waffle_corgi_low.fbx` | 118284 | `8c2d660d611927edf9ea473c20464ffbba798de3ab99bda0f9fd3138030766c6` | 110708334812765 |
| 67 | `evo2_aurora_fox` | `blender/out/evo2_aurora_fox.fbx` | 248556 | `2b27fc43e457a1703523731b9522a11caec48db938770d84c05be5d6b05d350a` | 96454077193072 |
| 68 | `evo2_aurora_fox_low` | `blender/out/evo2_aurora_fox_low.fbx` | 134412 | `1d193cc87595c527d2f46037c1d76b21f65f6031c2d634e29fd5a1f7e6fdfed6` | 134494158953338 |
| 69 | `evo2_candy_unicorn` | `blender/out/evo2_candy_unicorn.fbx` | 230524 | `bbf67d4cbcb258c51bf0e001f73b807b03ee696fd5e7553450235de290f8e1f2` | 73535489272058 |
| 70 | `evo2_candy_unicorn_low` | `blender/out/evo2_candy_unicorn_low.fbx` | 134220 | `47754463c9cc393c786e30a3e64a80d029c9822a3346fba5dac1238b94037da8` | 72655878660168 |
| 71 | `evo2_cloudy_dragon` | `blender/out/evo2_cloudy_dragon.fbx` | 230988 | `58a25c89dbc6d14b59296f4f3b381d3e77b5b59be3dc979c367297cca6bbddf5` | 128440516283086 |
| 72 | `evo2_cloudy_dragon_low` | `blender/out/evo2_cloudy_dragon_low.fbx` | 136140 | `9affe32b48f4fd7156c5c0e1ac9ebca5021ee5136e0a6a015a1a07a7b7f32366` | 77495727832514 |
| 73 | `evo2_eclipse_dragon` | `blender/out/evo2_eclipse_dragon.fbx` | 243004 | `486f17ce6f2b3709791a8072b8760d8c4256cc4ec5407cd72bcb25fe0cf37d54` | 103211293395087 |
| 74 | `evo2_eclipse_dragon_low` | `blender/out/evo2_eclipse_dragon_low.fbx` | 144748 | `f387fcb14d18bd9f842efb5140986c7e29b234c0fbc6f52105873919c8742d31` | 116024781080229 |
| 75 | `evo2_ember_phoenix` | `blender/out/evo2_ember_phoenix.fbx` | 217836 | `a5878897bb053fc7e3948b33a67b9a25a8bac6b68c894e42f6a9f5f19760b9d9` | 121932152716311 |
| 76 | `evo2_ember_phoenix_low` | `blender/out/evo2_ember_phoenix_low.fbx` | 111420 | `c7b2db124ae79121ef8716feef954f28e5d556a32558a9a23f5af4f1db9615ef` | 129351525313180 |
| 77 | `evo2_hydralotl` | `blender/out/evo2_hydralotl.fbx` | 234172 | `fff1bab71b6ec7178f20010dd1aa19cb2ea70b96ac0887dcceb66528b744fbf3` | 86677554729004 |
| 78 | `evo2_hydralotl_low` | `blender/out/evo2_hydralotl_low.fbx` | 129724 | `69b20bfcf44adadaea254db436eeff08284f978e3e786cbd379a9e01c03dbc17` | 108255604353600 |
| 79 | `evo2_magma_cub` | `blender/out/evo2_magma_cub.fbx` | 234924 | `31d92d3f70b45f3d981f43c3e08edf8c7940c1eeb05aacf7a103e96afacb1681` | 70908234081275 |
| 80 | `evo2_magma_cub_low` | `blender/out/evo2_magma_cub_low.fbx` | 119676 | `0ea3a0ed23afe5b5960a7c3ac18ae9e0c10db1ce40d75f3f695dd3aaa00c82ec` | 104620513801272 |
| 81 | `evo2_moonlit_owl` | `blender/out/evo2_moonlit_owl.fbx` | 186988 | `fa89dfd0ec872671b7c2c917400a7ff74e012aaf4ab22711f9a9f196aa98855e` | 74462708768922 |
| 82 | `evo2_moonlit_owl_low` | `blender/out/evo2_moonlit_owl_low.fbx` | 108684 | `5ec436e72efb62e27ef42d25566c1d1feb9751d77e8ec703d056a548e9e85460` | 127699670768610 |
| 83 | `evo2_nebula_axolotl` | `blender/out/evo2_nebula_axolotl.fbx` | 223996 | `84cdfbb4d04340274a6a7f688fd28d26b164278b2f60c7d181db337975396d52` | 133259697353190 |
| 84 | `evo2_nebula_axolotl_low` | `blender/out/evo2_nebula_axolotl_low.fbx` | 123356 | `cf2908b2e0ac02e97198ac3fe01bbba140b5c345088857a0c1e939394be1474a` | 91217054217891 |
| 85 | `evo2_obsidian_phoenix` | `blender/out/evo2_obsidian_phoenix.fbx` | 212924 | `b0ed8109402d97ca7862e8e2568459f3c2c5f3f04412858303948bd03d981201` | 115408487250352 |
| 86 | `evo2_obsidian_phoenix_low` | `blender/out/evo2_obsidian_phoenix_low.fbx` | 115708 | `a2ea1900c183930bbeaa829f2a02a8396e7c03480f432a3c7ea92d3728717f95` | 89229925420725 |
| 87 | `evo2_phantom_kitsune` | `blender/out/evo2_phantom_kitsune.fbx` | 235004 | `a29f9fde8e8beeea7a54fd572c6e5752938f3babaee53e28ef922652f28e1214` | 126683096840405 |
| 88 | `evo2_phantom_kitsune_low` | `blender/out/evo2_phantom_kitsune_low.fbx` | 125388 | `a3694a68553e9adafbb37f5e0f6d18656040c1517233f9e1b27902c0669a7d0c` | 80582703392635 |
| 89 | `evo2_rime_wyrmling` | `blender/out/evo2_rime_wyrmling.fbx` | 257484 | `fd666678242913bd3b231c2ed7d5960d5f5238aa33f95d1b3edfbe1762e0b833` | 132691578987700 |
| 90 | `evo2_rime_wyrmling_low` | `blender/out/evo2_rime_wyrmling_low.fbx` | 154716 | `7957c766fe5e218ca1cb56e3e5dfe7fa044b311185a55d619f14365bfc45b1c2` | 77245777274702 |
| 91 | `evo2_starlight_unicorn` | `blender/out/evo2_starlight_unicorn.fbx` | 210348 | `d25a42659caf83f098b5483f2ed05e9982152f6e92eecea96a78f03cfb9bab19` | 101065910710208 |
| 92 | `evo2_starlight_unicorn_low` | `blender/out/evo2_starlight_unicorn_low.fbx` | 129900 | `fc9b2130b60472b9d87e6d4411a71493f298a165957430973c160459ec87041d` | 92883425379575 |
| 93 | `evo2_stormfang` | `blender/out/evo2_stormfang.fbx` | 206236 | `7b5eb3ca12fa62e7cd208f6d9428474e36a50ba6f28684de2aac7594c9775619` | 71631158125067 |
| 94 | `evo2_stormfang_low` | `blender/out/evo2_stormfang_low.fbx` | 112748 | `5b7a302cd269a7a663d07f4ca5e23cb342d4d0f4438460437faae16d56195145` | 108154765916829 |
| 95 | `evo2_sunbeam_bear` | `blender/out/evo2_sunbeam_bear.fbx` | 218524 | `67f156adb56d8deabca0784949475faf2a208a57849eaedf4feec593c10bbbbc` | 72342085606908 |
| 96 | `evo2_sunbeam_bear_low` | `blender/out/evo2_sunbeam_bear_low.fbx` | 114028 | `74683bf43cbb3a3ad0e5cbf25a79f923e7edf3c9960da3aa3c963a59704d8793` | 87184391459429 |
| 97 | `evo2_twilight_dragon` | `blender/out/evo2_twilight_dragon.fbx` | 240540 | `26bb9b882ba4c0ae310d62b5c2d5cb585ae154894f435915e6d047776d311cbe` | 111719405674494 |
| 98 | `evo2_twilight_dragon_low` | `blender/out/evo2_twilight_dragon_low.fbx` | 137884 | `40678aa275bb8de360de43d40e9a38764fded03b96bebe7e63e156d5b2747c69` | 128380020278617 |
