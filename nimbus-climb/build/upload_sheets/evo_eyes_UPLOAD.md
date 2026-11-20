# Evolved eyes re-bake: upload hand-over (98 evolved body meshes)

Pitch 2 item 7, option A "Trim" (spec `docs/superpowers/specs/2026-11-20-pitch2-build-design.md` item 7, plan Task 12).
Owner's decision 2026-11-20: re-bake the evolved pet meshes in Blender so the trimmed eyes show in game, and prepare
the upload (not do it). This file is the hand-over for the owner's keyed cloud session.

**Status: PREPARED, NOT UPLOADED.** Nothing was sent to Roblox from the PC. `src/shared/MeshIds.lua`,
`src/shared/MeshManifests/` and `blender/meshes.json` on this branch are unchanged, so the game keeps the live meshes
(the old 8 x 9 eyes) until the upload session lands the new manifests and the new ids together.

## For the owner, in short

- The 9 pets of the approved sheet were re-baked from Blender with the smaller eyes. They match column A of the sheet
  (`evo_eyes/evo1_eyes_vs_sheetA.png`).
- All 98 evolved body meshes change: 49 High + 49 `_low`, first and second evolutions. Wings (`evowing_`) carry no
  eyes and stay as they are.
- Each of the 98 becomes a **new** Roblox asset with a new id, because its part structure changed (structureHash). Until Roblox approves
  a new asset, that pet shows its Part build (heavier: about 1,200 to 1,450 parts for an evolved pet).
- Your OK is needed before the upload. Run it in the keyed cloud session, never from a PC.

## What was built on the PC (and checked)

| | |
|---|---|
| Source | branch `kitb-p2-eyes` @ `3708fbc` (PetBuilder `EYE_MASKS.Evo` 6 x 7, `EvoFierce` 6 x 5, commit `c116b44`) |
| Tool | `blender/build_all.py`, export build, Blender as a Python module: bpy 5.2.2 on Python 3.13 (`%USERPROFILE%\.bpyenv`) |
| Keys | the 98 `evo1_*` / `evo2_*` keys in `evo_eyes/keys.txt`: 98 built, 0 failed, every FBX re-import checked (3 times) |
| Size | 15,357,000 bytes in all, 257,484 bytes for the largest file |
| Index | `blender/meshes.json` changed for exactly these 98 keys and no other key: contentHash, structureHash, fbxSha256 and tris for all 98, parts for 71. The contentHash of every key equals the dry bake recorded in `evo_eyes_rebake.json`. |
| Uploader | every structureHash differs from `blender/upload_state.json`, so expect **98 new-asset** (new ids). All 98 have an id in `MeshIds.lua` today. |
| Same bytes in the cloud | rebuilt on the PC, `evowing_pebble_pup_1_L` (unchanged) gave fbxSha256 `d615511a...58ea`, the same bytes as the committed value from the Linux cloud build. A second full PC build of the 98 gave the same sha256 for each. The cloud rebuild must give the sha256 values in the table below. |
| Eyes, measured | Box of the baked eye parts, live vs re-baked manifest. High eyes are 0.72 -> 0.56 studs tall (7/9), fierce ones x 5/7. The eye box is narrower on all 98 keys. Exceptions: the owls keep their painted EyeRing disc, and the pandas keep a tall Glint / Lash patch. Both still get narrower. Full numbers: `evo_eyes/evo_eyes_fbx.json` `eyeMeasure` and per key `eyeBox`. |
| The FBX itself | the 9 sheet pets' `evo1_*.fbx` were opened in Blender 5.2.2. The eye objects' height equals the re-baked manifest, not the live one (`evo_eyes/evo1_fbx_raw.png`). |
| Budgets | every key within its catalog budget. All 98 evolved sets (re-baked body + committed wings) are within budget; the fullest is `evo1_phantom_kitsune` (14,794 / 15,000 tris). `tools/mesh_budget.py`'s worst real view is unchanged at 1,789 parts. Its "every pet a second evolution" figure goes 3,064 -> 3,097, and that figure was already over the proposed 3,000 before. `mesh_budget.py --check` was OVER before this change too. |
| Uploader dry run on the PC | with the re-baked index in place, base URL pointed at `127.0.0.1:9` and no key: `98 key(s)`, 98 `new-asset`, 0 `FAILED`, "nothing was sent and nothing was written" (`upload_state.json` / `MeshIds.lua` unchanged) |
| Smoke (mesh mode, re-baked manifests in place) | `--quick --mesh --only` petbuilder 585 / evolved 548 / p3evo_pets 675 / client_p6pets 545 passed, 0 failed |

**Why the re-baked manifests are not committed from the PC.** `MeshLibrary` fits the downloaded asset to the
committed manifest. A re-baked manifest with the OLD id would refuse the key ("missing part" -> the Part build), or,
where names still line up, put old geometry into the new part boxes. `node tools/check.mjs` rule `mesh-ids-stale`
stops it as well: on the PC, with the re-baked manifests in place, it reported **98 errors** (one per key, "the re-upload
is a NEW asset"); on the branch as committed it reports none. `docs/phase6/OWNER_UPLOAD.md` 8e: the new manifest and
the new id go into the **same commit**. So the upload session rebuilds (it has to anyway: `blender/out/` is not
committed), checks the bytes against this list, uploads, and commits manifests + `meshes.json` + `upload_state.json`
+ `MeshIds.lua` together.

**Older drift that ships with this re-bake.** `evo1_hydralotl`, `evo1_hydralotl_low`, `evo1_magma_cub` and
`evo1_magma_cub_low` were already behind today's design before the eye change. Their re-bake also brings that design
up to date. `evo_eyes/evo1_drift_keys.png` shows the re-baked meshes next to today's Part build. The Low meshes are
coarse by design (K 0.585 / 0.65, seen from a distance).

## Steps for the keyed cloud session (from `docs/phase6/OWNER_UPLOAD.md`)

Rules of OWNER_UPLOAD.md hold: never print the key, no real upload without the owner's OK in the chat, never fake an
id, never go around moderation.

0. **OWNER**: say go in the chat. This is an upload, so it is the owner's call.
1. **CLAUDE, prepare** (section 2):
   ```bash
   cd /home/user/roblox/nimbus-climb
   git fetch origin && git checkout kit-b && git pull     # kit-b once kitb-p2-eyes is merged; before that: kitb-p2-eyes
   git merge-base --is-ancestor c116b44 HEAD && echo ok   # the eye masks (c116b44) must be in this branch
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
   Expect `98 of 98 match`. A mismatch means PetBuilder or the kit changed after `3708fbc`. In that case
   tell the lead, re-render the previews (`python3 tools/render_model.py meshevo:<pet>:1`) and wait for the owner
   before uploading.
4. **Offline checks** (section 2.2):
   ```bash
   python3 tools/test_upload_assets.py
   python3 tools/mesh_names.py --check blender/out/*.manifest.json
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
   Garden pets and other players' followers use the `_low` meshes. Then publish (section 7).

Roll back (section 9): put the old ids back by removing the new lines. The old ids stay in `upload_state.json`
under `previousAssetIds`, and the old manifests are in git history at `3708fbc`.

## Evidence (this folder)

| file | what |
|---|---|
| `evo_eyes/evo1_eyes_vs_sheetA.png` | the 9 sheet pets, front + 3/4: approved sheet column A, the Part build at `3708fbc`, the re-baked mesh |
| `evo_eyes/evo2_eyes.png` | second evolutions of the 6 sheet pets that have one: Part build vs re-baked mesh |
| `evo_eyes/evo1_low_eyes.png` | the 9 sheet pets' `_low` meshes vs the Low Part build (the Low Part build uses its own 4 x 4 mask) |
| `evo_eyes/evo1_drift_keys.png` | the 4 drift keys (Hydralotl, Magma Cub; High + Low) |
| `evo_eyes/evo1_fbx_raw.png` | the exported FBX files opened in Blender 5.2.2. The parts are tinted by name only, with the blink lids hidden. |
| `evo_eyes/evo_eyes_fbx.json` | every key: fbx, bytes, sha256, contentHash, structureHash, tris, parts, the live id / hashes, the eye box |
| `evo_eyes/keys.txt` | the 98 keys, one per line |
| `evo_eyes_rebake.json`, `evo_eyes_rebake_preview.png` | the earlier dry bake (`3708fbc`): live mesh vs re-bake |

## The 98 FBX files

Path = `blender/out/<key>.fbx` (git-ignored, rebuilt in step 2). sha256 = the PC build, which the cloud build must reproduce.
Live id = today's `MeshIds.lua` id, which is replaced by the new asset's id.

| # | key | path | bytes | sha256 | live id |
|---|---|---|---|---|---|
| 1 | `evo1_aurora_fox` | `blender/out/evo1_aurora_fox.fbx` | 199548 | `2214b71cef7bc1f8bcc9e9ca727bf3aa974fc80cfaa2c482ed25f9493b8fbaf9` | 87772383693151 |
| 2 | `evo1_aurora_fox_low` | `blender/out/evo1_aurora_fox_low.fbx` | 122652 | `9fe99b523bd91a64dc0ced5d654861f6ee4ae2a05bea982b9d3ea21fe21ad5d0` | 77788282454956 |
| 3 | `evo1_bamboo_panda` | `blender/out/evo1_bamboo_panda.fbx` | 177932 | `e13dc9fa8fa11afa9464f173d9a8ab1cc4b999afaa1ee519493791b7dec7def7` | 104363918642473 |
| 4 | `evo1_bamboo_panda_low` | `blender/out/evo1_bamboo_panda_low.fbx` | 106972 | `7871ea24cee54d7613fc7ea83afaaa21faa8046d6d4f15d9ed1e37cb430287bc` | 129482935584530 |
| 5 | `evo1_biscuit_bear` | `blender/out/evo1_biscuit_bear.fbx` | 167004 | `3dba1d8732708b777d1d5cbf7428f0209be72c2d97246d23c6a42df321cb5e79` | 73735764977613 |
| 6 | `evo1_biscuit_bear_low` | `blender/out/evo1_biscuit_bear_low.fbx` | 104460 | `3364a63ae51fb2a5dd21fd56f4bca5512b50a0b26ec664dd50b011fafaeb071e` | 99723032833610 |
| 7 | `evo1_blossom_bunny` | `blender/out/evo1_blossom_bunny.fbx` | 183532 | `438985ad3eacde6deeb2aa8e1129b71eb98adf18eca9d07eef7951ac82678d08` | 82394928828450 |
| 8 | `evo1_blossom_bunny_low` | `blender/out/evo1_blossom_bunny_low.fbx` | 117276 | `a1cbbb5e8e49d61c5b9282d95504e153eef364f93544ec59c3468367fe6bb166` | 75253507719284 |
| 9 | `evo1_bubble_axolotl` | `blender/out/evo1_bubble_axolotl.fbx` | 178972 | `45f9cf70a1d9ebbddd845e1cbb629e3e7156313012c5ff3dad3069c9be0bc3c7` | 92767577680778 |
| 10 | `evo1_bubble_axolotl_low` | `blender/out/evo1_bubble_axolotl_low.fbx` | 112828 | `65ea50e16539a55368edc10a5d38cb4ed30de5c3bf4644a2b9038b1cb69f08c8` | 138245964799147 |
| 11 | `evo1_candy_unicorn` | `blender/out/evo1_candy_unicorn.fbx` | 189884 | `4e15f65df68ff3ce5747da2db5f2f9dbde2cf55c60d9c12e03f365a62548de49` | 137467109507967 |
| 12 | `evo1_candy_unicorn_low` | `blender/out/evo1_candy_unicorn_low.fbx` | 126396 | `9a31192147d4c29a5ccad59c97a81efa50943738505ec5550e63a283db98b7fe` | 83858413665107 |
| 13 | `evo1_cherry_panda` | `blender/out/evo1_cherry_panda.fbx` | 184972 | `92f92f6b28c593c0342ed2684edf07e3a76061eca7653d7fdf2a8efa89ec538e` | 110836396681656 |
| 14 | `evo1_cherry_panda_low` | `blender/out/evo1_cherry_panda_low.fbx` | 112284 | `c7b85b0df80e4a30f058be983b44e823f64e1d2324a7356b1cc11d21cd70d6e0` | 118659270989807 |
| 15 | `evo1_cloudy_dragon` | `blender/out/evo1_cloudy_dragon.fbx` | 185372 | `bb4777f79114b792811305722070efc532c676cdf11c0d92d4e4179be463d774` | 124282700617318 |
| 16 | `evo1_cloudy_dragon_low` | `blender/out/evo1_cloudy_dragon_low.fbx` | 117836 | `8d4464b3a57729c9c5938d47f3a4f48268e75ee0caa024cd5d911577aace3409` | 93000498845226 |
| 17 | `evo1_eclipse_dragon` | `blender/out/evo1_eclipse_dragon.fbx` | 194908 | `81ad4d7f643300c029412de5c8e9bad10420f24c390f15d286f1afe0c52869fc` | 115587997700525 |
| 18 | `evo1_eclipse_dragon_low` | `blender/out/evo1_eclipse_dragon_low.fbx` | 116556 | `0241bef2238f8ca344a9660a8ab30d6f81f4da8311cb845dc44f17783328b740` | 120102054910553 |
| 19 | `evo1_ember_phoenix` | `blender/out/evo1_ember_phoenix.fbx` | 166828 | `b2b2ae5085ee78c040978d76c1784a285b74093897a095df984f2e55b269279f` | 85951869370892 |
| 20 | `evo1_ember_phoenix_low` | `blender/out/evo1_ember_phoenix_low.fbx` | 109612 | `28b7cf6974e78bc485d107d9dedd58562b8e45117325641dd7c66c3b18915db5` | 127384591685930 |
| 21 | `evo1_frostling_penguin` | `blender/out/evo1_frostling_penguin.fbx` | 177100 | `8c992204233c7144bd853903a924b3757c1b65c6cc5e78e23fb1765850422a15` | 87839970044677 |
| 22 | `evo1_frostling_penguin_low` | `blender/out/evo1_frostling_penguin_low.fbx` | 104268 | `cc0757beadb7786389454184961385df35250c2cfc77b0fcb4736419ad025e32` | 117375525292782 |
| 23 | `evo1_honey_bunny` | `blender/out/evo1_honey_bunny.fbx` | 177868 | `165948631e735c4f74db472dc840ba5e203bbb363f1d9228280c2ed6c5824cf2` | 134835417429640 |
| 24 | `evo1_honey_bunny_low` | `blender/out/evo1_honey_bunny_low.fbx` | 111548 | `40a2df22b8ef84efe7cba14e74e4a80aed40c52de9fa355672b6828debb776f8` | 139060124292304 |
| 25 | `evo1_hydralotl` | `blender/out/evo1_hydralotl.fbx` | 201628 | `52479cee0d43bdcf6a0654b14bd357abd3630e679aba6a67c72f853a2070bc58` | 107330994952547 |
| 26 | `evo1_hydralotl_low` | `blender/out/evo1_hydralotl_low.fbx` | 112044 | `50570cb83536ffff0fac74483bf4d6266b87a46e375d8696b022579586a257e2` | 75165208362476 |
| 27 | `evo1_magma_cub` | `blender/out/evo1_magma_cub.fbx` | 197164 | `22975e91ca9871a15b4737ac45887bf8fa2345457d4d30996421ec9b38a073d5` | 128171047724691 |
| 28 | `evo1_magma_cub_low` | `blender/out/evo1_magma_cub_low.fbx` | 117292 | `49f0e2df8d15e39f4269a76c327d435f0057ade067e1a745c6c0e9909419b09b` | 111156779183723 |
| 29 | `evo1_mallow_kitten` | `blender/out/evo1_mallow_kitten.fbx` | 196940 | `0d1714ebb228073845022da86272eeb9ea17839b896dacf0611aeafa781cc881` | 76487641815372 |
| 30 | `evo1_mallow_kitten_low` | `blender/out/evo1_mallow_kitten_low.fbx` | 117244 | `a6b785576e075ab4efbe0e68046a68062934adebdc5836ca1b18a20c8abe1ee1` | 108260487493804 |
| 31 | `evo1_maple_fox` | `blender/out/evo1_maple_fox.fbx` | 185180 | `af9b27b7c90eb07527e465a03e93e874a6b054ac5c26db74b863c5ed71a48fdb` | 105335734155111 |
| 32 | `evo1_maple_fox_low` | `blender/out/evo1_maple_fox_low.fbx` | 110316 | `01efc96f169c5533dd576fd596b64b2b0e9403fe0de8925e3113663abdfd92eb` | 71314104979558 |
| 33 | `evo1_mochi_slime` | `blender/out/evo1_mochi_slime.fbx` | 134460 | `2390cd6e74a2a9ba8ba25d164c31ecab461afa8e84199bc8d7d1a734e1aa940c` | 140278769359069 |
| 34 | `evo1_mochi_slime_low` | `blender/out/evo1_mochi_slime_low.fbx` | 85788 | `7a117ca7f37a7c1ba8ffa8977d19f6667cc1202f0b532ca85321222bf246be3f` | 121585707246125 |
| 35 | `evo1_moonlit_owl` | `blender/out/evo1_moonlit_owl.fbx` | 177004 | `eb70c86a3140a466a8195109ac9b14653e50d26308fe38b19ba55739978ea7fb` | 113642919127042 |
| 36 | `evo1_moonlit_owl_low` | `blender/out/evo1_moonlit_owl_low.fbx` | 94268 | `3d9be6dadce2156cfb6b64fb4230f93a119fdb3ee213c20350c90bc507de3575` | 87552810305165 |
| 37 | `evo1_nebula_axolotl` | `blender/out/evo1_nebula_axolotl.fbx` | 176844 | `d749d5e3ba8a5e9bfbb8689b391a83893038b518497ebcfdf5a42a794cb7d6bd` | 87331681854879 |
| 38 | `evo1_nebula_axolotl_low` | `blender/out/evo1_nebula_axolotl_low.fbx` | 112700 | `6f46e99806df69a0e690aa0e2905feacb93bd9c8b4e12462de1099e0d3cbe862` | 135511552169009 |
| 39 | `evo1_obsidian_phoenix` | `blender/out/evo1_obsidian_phoenix.fbx` | 193100 | `74cc4183cec875fd9f6a0ec4abcfa253afa3e2e357adc0ffba892aa04e6dc455` | 84691219969375 |
| 40 | `evo1_obsidian_phoenix_low` | `blender/out/evo1_obsidian_phoenix_low.fbx` | 126700 | `414e4aa570690e6a24c944932f36d468ac1a4225f2b75e858e25d00906de3529` | 136278315485979 |
| 41 | `evo1_pebble_pup` | `blender/out/evo1_pebble_pup.fbx` | 184860 | `6a1300bcc2c8c522292bce67ba4faafc086d84efb3c8f66106588cc5fd30596a` | 75795178584683 |
| 42 | `evo1_pebble_pup_low` | `blender/out/evo1_pebble_pup_low.fbx` | 114524 | `682bee7dfac950a4907bab690eae392f8fea1307a02e6892f4404f5f9169be7f` | 73658366816678 |
| 43 | `evo1_phantom_kitsune` | `blender/out/evo1_phantom_kitsune.fbx` | 204972 | `d1cc9902e2d61fbc5420b7a6317e70c1e1d54d1c0272ee992f498e343b381065` | 109492203546111 |
| 44 | `evo1_phantom_kitsune_low` | `blender/out/evo1_phantom_kitsune_low.fbx` | 124668 | `6d4b7de7ce215332445aa515fefc4895c80ca7bc4aaea8dbb4a20530d65515c9` | 73193456925742 |
| 45 | `evo1_pip_penguin` | `blender/out/evo1_pip_penguin.fbx` | 171708 | `0faaa6157f8a354e8ee16deb4d755af1c44542b5ae7b28057cb34e637e25df12` | 102583552628564 |
| 46 | `evo1_pip_penguin_low` | `blender/out/evo1_pip_penguin_low.fbx` | 101948 | `f4b43da8b94c111bba22b1a2463956f6253fb7e2f76dc5e1fc5d584505281a5e` | 119159628161633 |
| 47 | `evo1_puddle_frog` | `blender/out/evo1_puddle_frog.fbx` | 165772 | `28b46fb04faa5ef15ad0f52c3f5acccc4cca90919c7537be8f87965163595fdb` | 72369315852282 |
| 48 | `evo1_puddle_frog_low` | `blender/out/evo1_puddle_frog_low.fbx` | 101532 | `2c8c3a72f386156ae2563100e252ad1cdb8f39f5d2cbea14b9b46744cf8d96ac` | 109508565800347 |
| 49 | `evo1_rime_wyrmling` | `blender/out/evo1_rime_wyrmling.fbx` | 219532 | `99321ec7b7ad7781c66e7ceb3a508be096abdb377e718e1db520c0ba21487f81` | 139595966133024 |
| 50 | `evo1_rime_wyrmling_low` | `blender/out/evo1_rime_wyrmling_low.fbx` | 134588 | `f5233ea29639ac9cc2d5b36a041b1cfe71dc49ed4e5f29d66f5f61e58b622cdf` | 97518265520464 |
| 51 | `evo1_shroomie_frog` | `blender/out/evo1_shroomie_frog.fbx` | 162988 | `7ee18447cb0c2ab9aafdc93f2209ccfeacbba02edd22e28b443c60c9ecba6fcc` | 113280357489430 |
| 52 | `evo1_shroomie_frog_low` | `blender/out/evo1_shroomie_frog_low.fbx` | 103292 | `6467b99b49ba8f1ff7dc70a8858aeb6b76bd9de9d687252325f506379ad6230e` | 89302304972875 |
| 53 | `evo1_sleepy_owl` | `blender/out/evo1_sleepy_owl.fbx` | 172076 | `65f24ed909369542a49bf9885b06492f0ddb32608ac03802f794d239a25bc012` | 123215045455041 |
| 54 | `evo1_sleepy_owl_low` | `blender/out/evo1_sleepy_owl_low.fbx` | 92284 | `34a94cec7f17262ae9a6107fa23b60ddec2b3afa4244464ad05f8ac705674863` | 104696782911723 |
| 55 | `evo1_starlight_unicorn` | `blender/out/evo1_starlight_unicorn.fbx` | 194348 | `169f7d523368c33f79a6aded3556ec61cd6090320544f0ea63f034b6363071e2` | 129258425301120 |
| 56 | `evo1_starlight_unicorn_low` | `blender/out/evo1_starlight_unicorn_low.fbx` | 119548 | `9c52501e398edb58f0cfc0b34110fcf15ce6f6d61884919450ecd876bceef337` | 113879047878339 |
| 57 | `evo1_storm_tabby` | `blender/out/evo1_storm_tabby.fbx` | 186732 | `b85e8d2ee6a9ced7d6d9143360b481ddb2a212f6dab09cf42d5b72c9a037b282` | 90763597503307 |
| 58 | `evo1_storm_tabby_low` | `blender/out/evo1_storm_tabby_low.fbx` | 111676 | `3bc4f694b7fa066432f775afbb09a13dadf8550e9cbb2e08c0f4f1bb2e0edf45` | 72832808211675 |
| 59 | `evo1_stormfang` | `blender/out/evo1_stormfang.fbx` | 198188 | `918211f795f55f15730b6362e547b35f4eb1be92d527794628a6f277b04c87f5` | 93119026859574 |
| 60 | `evo1_stormfang_low` | `blender/out/evo1_stormfang_low.fbx` | 108380 | `02d1fd8a73a24ac1ca4e7eb17c7bfbb26a40d1b5e6d2f7c28bcd39552eb10848` | 76844743783547 |
| 61 | `evo1_sunbeam_bear` | `blender/out/evo1_sunbeam_bear.fbx` | 180876 | `64dd39c91f6400acd5744f82db3d8bd73d9dd28f796045e55dce98a37053fca3` | 81137217654376 |
| 62 | `evo1_sunbeam_bear_low` | `blender/out/evo1_sunbeam_bear_low.fbx` | 112076 | `54c19ca41f8c84fcb013ec3217053504214b85785cd4160b46a31818d974eaf6` | 130314648949999 |
| 63 | `evo1_twilight_dragon` | `blender/out/evo1_twilight_dragon.fbx` | 182028 | `dc161936ee3a0afc44bc82427e0098f59996dbb21c343fb471a75903b19631c9` | 139255105971705 |
| 64 | `evo1_twilight_dragon_low` | `blender/out/evo1_twilight_dragon_low.fbx` | 110604 | `79a7eb37122082e33e43122a5afa8c7888bbbb9393260c908fa123b0e7db957e` | 122058642544043 |
| 65 | `evo1_waffle_corgi` | `blender/out/evo1_waffle_corgi.fbx` | 194988 | `a43c5a19ab3a58503096aa97447f46441d228e74c60bfaafe4c2a16bcd078329` | 121575312945918 |
| 66 | `evo1_waffle_corgi_low` | `blender/out/evo1_waffle_corgi_low.fbx` | 122748 | `82f019decf456452fb629ae5cbf47a6a2764423f99725640c6e85879c1a00246` | 110708334812765 |
| 67 | `evo2_aurora_fox` | `blender/out/evo2_aurora_fox.fbx` | 248556 | `2b27fc43e457a1703523731b9522a11caec48db938770d84c05be5d6b05d350a` | 96454077193072 |
| 68 | `evo2_aurora_fox_low` | `blender/out/evo2_aurora_fox_low.fbx` | 132076 | `6205cf33168b2b6630c6455565ebc32e688ed7a8b2a23980a29585295d92e5b9` | 134494158953338 |
| 69 | `evo2_candy_unicorn` | `blender/out/evo2_candy_unicorn.fbx` | 230524 | `bbf67d4cbcb258c51bf0e001f73b807b03ee696fd5e7553450235de290f8e1f2` | 73535489272058 |
| 70 | `evo2_candy_unicorn_low` | `blender/out/evo2_candy_unicorn_low.fbx` | 130428 | `808c92ed41bf20bc7aa6fd77608e574567d0b514da73abc94bd4e7fe17cb6845` | 72655878660168 |
| 71 | `evo2_cloudy_dragon` | `blender/out/evo2_cloudy_dragon.fbx` | 230988 | `58a25c89dbc6d14b59296f4f3b381d3e77b5b59be3dc979c367297cca6bbddf5` | 128440516283086 |
| 72 | `evo2_cloudy_dragon_low` | `blender/out/evo2_cloudy_dragon_low.fbx` | 134988 | `433a577e86580ab11521f23942ab1929541b9a7824ce56ac4dbcd1aad86e05ad` | 77495727832514 |
| 73 | `evo2_eclipse_dragon` | `blender/out/evo2_eclipse_dragon.fbx` | 243004 | `486f17ce6f2b3709791a8072b8760d8c4256cc4ec5407cd72bcb25fe0cf37d54` | 103211293395087 |
| 74 | `evo2_eclipse_dragon_low` | `blender/out/evo2_eclipse_dragon_low.fbx` | 144012 | `26e8c2eab865b407b71ebbcdf31e584eda52c8a3ff8c99da5e25b982a730e793` | 116024781080229 |
| 75 | `evo2_ember_phoenix` | `blender/out/evo2_ember_phoenix.fbx` | 217836 | `a5878897bb053fc7e3948b33a67b9a25a8bac6b68c894e42f6a9f5f19760b9d9` | 121932152716311 |
| 76 | `evo2_ember_phoenix_low` | `blender/out/evo2_ember_phoenix_low.fbx` | 107628 | `4ba24c9607586eaa7842548dde9de8b15c0bc4602b980b372c22c2c4fe47e83c` | 129351525313180 |
| 77 | `evo2_hydralotl` | `blender/out/evo2_hydralotl.fbx` | 234172 | `fff1bab71b6ec7178f20010dd1aa19cb2ea70b96ac0887dcceb66528b744fbf3` | 86677554729004 |
| 78 | `evo2_hydralotl_low` | `blender/out/evo2_hydralotl_low.fbx` | 123996 | `032def1c16ff932b6910fe50f75b1e386876c49d0d35d28018a7611461cf2a60` | 108255604353600 |
| 79 | `evo2_magma_cub` | `blender/out/evo2_magma_cub.fbx` | 234924 | `31d92d3f70b45f3d981f43c3e08edf8c7940c1eeb05aacf7a103e96afacb1681` | 70908234081275 |
| 80 | `evo2_magma_cub_low` | `blender/out/evo2_magma_cub_low.fbx` | 113996 | `f1fc54d6c204a2fc5ac8ee5adb938a2fb033e938b9ef2abaf26fc861e9aad935` | 104620513801272 |
| 81 | `evo2_moonlit_owl` | `blender/out/evo2_moonlit_owl.fbx` | 186988 | `fa89dfd0ec872671b7c2c917400a7ff74e012aaf4ab22711f9a9f196aa98855e` | 74462708768922 |
| 82 | `evo2_moonlit_owl_low` | `blender/out/evo2_moonlit_owl_low.fbx` | 85292 | `fc515f3c546328a780298c0b0a3cdf6f2bc1a34564d38204f7f0f947abad4f34` | 127699670768610 |
| 83 | `evo2_nebula_axolotl` | `blender/out/evo2_nebula_axolotl.fbx` | 223996 | `84cdfbb4d04340274a6a7f688fd28d26b164278b2f60c7d181db337975396d52` | 133259697353190 |
| 84 | `evo2_nebula_axolotl_low` | `blender/out/evo2_nebula_axolotl_low.fbx` | 117628 | `7fa8ffec9745780d6f0c3fabf960cae3e6efbf5fcf5daad3d01b07fda60ffdd1` | 91217054217891 |
| 85 | `evo2_obsidian_phoenix` | `blender/out/evo2_obsidian_phoenix.fbx` | 212924 | `b0ed8109402d97ca7862e8e2568459f3c2c5f3f04412858303948bd03d981201` | 115408487250352 |
| 86 | `evo2_obsidian_phoenix_low` | `blender/out/evo2_obsidian_phoenix_low.fbx` | 112028 | `1a0a796bafb6d7a2e44c8156af02d8b1bd1e2762f50e1ebde1a5a18bb4a49549` | 89229925420725 |
| 87 | `evo2_phantom_kitsune` | `blender/out/evo2_phantom_kitsune.fbx` | 235004 | `a29f9fde8e8beeea7a54fd572c6e5752938f3babaee53e28ef922652f28e1214` | 126683096840405 |
| 88 | `evo2_phantom_kitsune_low` | `blender/out/evo2_phantom_kitsune_low.fbx` | 123004 | `4624a8d6427f6d3bfade3b30f5fcb5118ba149ae21fa29f1349e952381f3e7c9` | 80582703392635 |
| 89 | `evo2_rime_wyrmling` | `blender/out/evo2_rime_wyrmling.fbx` | 257484 | `fd666678242913bd3b231c2ed7d5960d5f5238aa33f95d1b3edfbe1762e0b833` | 132691578987700 |
| 90 | `evo2_rime_wyrmling_low` | `blender/out/evo2_rime_wyrmling_low.fbx` | 154028 | `b867700c6908e763f46e381e8797bd16c965ed1b9dbae9e47ceff389af11cf3a` | 77245777274702 |
| 91 | `evo2_starlight_unicorn` | `blender/out/evo2_starlight_unicorn.fbx` | 210348 | `d25a42659caf83f098b5483f2ed05e9982152f6e92eecea96a78f03cfb9bab19` | 101065910710208 |
| 92 | `evo2_starlight_unicorn_low` | `blender/out/evo2_starlight_unicorn_low.fbx` | 126028 | `3d0109a6fae257769928975aeeeb41246cb3a74b54c922f9feb96dfc1369e9a7` | 92883425379575 |
| 93 | `evo2_stormfang` | `blender/out/evo2_stormfang.fbx` | 206236 | `7b5eb3ca12fa62e7cd208f6d9428474e36a50ba6f28684de2aac7594c9775619` | 71631158125067 |
| 94 | `evo2_stormfang_low` | `blender/out/evo2_stormfang_low.fbx` | 112092 | `a4f854657b8a972aa264e4d3f836115a84a7782075cebd8f990f3f2bef5a2497` | 108154765916829 |
| 95 | `evo2_sunbeam_bear` | `blender/out/evo2_sunbeam_bear.fbx` | 218524 | `67f156adb56d8deabca0784949475faf2a208a57849eaedf4feec593c10bbbbc` | 72342085606908 |
| 96 | `evo2_sunbeam_bear_low` | `blender/out/evo2_sunbeam_bear_low.fbx` | 108364 | `659072a17d83fb03474d367d4fd7884085c6f7665f7ccb678668659732cf97f6` | 87184391459429 |
| 97 | `evo2_twilight_dragon` | `blender/out/evo2_twilight_dragon.fbx` | 240540 | `26bb9b882ba4c0ae310d62b5c2d5cb585ae154894f435915e6d047776d311cbe` | 111719405674494 |
| 98 | `evo2_twilight_dragon_low` | `blender/out/evo2_twilight_dragon_low.fbx` | 137148 | `772e3fa077bd5acb14487e130954ab5723179474c6145237994e1aa83569e949` | 128380020278617 |
