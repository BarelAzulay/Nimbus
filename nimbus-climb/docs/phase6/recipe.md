# Phase 6 judge: verified findings and the corrected end-to-end recipe

Judge folder: `/tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad/p6design/judge/`

- `fbxparse.py` is an independent binary FBX reader. It does not use Blender.
- `bridge/bridge_probe.py` and `bridge/out_*.json` contain the lupa-bridge probe.

The repo was only read. `git status` is clean, and nothing was uploaded.

## 0. Verdict in one paragraph

Both scouts are mostly right. The kit's export is correct: it writes studs, with Roblox space baked into the raw coordinates. The research's upload and loading facts hold up against the saved docs. Seven things need correcting before this goes into the contract:

1. **Part names.** The kit renames regions (`Primary`, `Eye`, `Lid_*`, `Tail_*`). That breaks every name-based contract that PetBuilder callers and tests use: `Fur`, `EyeIris`, `EyeShine`, `EyeLid`, `Tail`, `WingL`, `^Horn`, `^Nostril`. The kit also bakes named regions into `Fixed`.
2. **Two loaders.** The prototypes give two half loaders. `MeshKit` has the recipes and the placement, but it blocks: LoadAsset runs inside Build, and the client waits on `WaitForChild(…, 10)`. `MeshLibrary` is robust, but it has no recipes, no manifest, no rig and no per-instance look. They must become one module.
3. **Re-upload churn.** The uploader fingerprints the FBX bytes. Every Blender export carries a wall-clock `CreationTimeStamp`, which I verified in the file. So every rebuild would PATCH a new version of all ~200 assets.
4. **Hand-ported shapes do not scale.** The Python port of pet shapes covers 3 of 15 species and 0 of 49 evolved forms. My lupa-bridge probe sculpts any pet from the real `PetBuilder.lua` at any K in about 1 s, with exact groups and hinges. The bridge must be the shape source.
5. **Budgets ignore evolved forms.** At the proposed grain, an evolved pet is 27–43k triangles, and one body part is 20–25k, which is over the 20k per-mesh limit. The grain must be set per class.
6. **Style-ref vs. research.** `style-ref` says "palette texture, no vertex colours" and "glow = Neon *Parts*". Both are overruled: use vertex colours, and make glow Neon *MeshParts*.
7. **Facing is unverified.** Facing after an Open Cloud upload cannot be known yet: the Roblox docs say Forward = Z, Roblox's own add-on uses −Z. The loader must detect it from the asset itself instead of trusting it.

## 1. What I checked myself

| Claim | Check | Result |
|---|---|---|
| FBX raw coordinates are Roblox studs, +Y up, −Z front | Parsed all 5 final FBX with my own reader (no Blender) and compared each geometry's bbox centre and size with the manifest | Max error 5e-5 studs on every part. Dog `Eye` z = −0.69 (front), `Tail` z = +0.6..1.05 (back), up = +Y. **Holds.** |
| "Roblox doc settings" | Header: UnitScaleFactor 100, UpAxis Y, FrontAxis Z sign −1, CoordAxis X sign −1. No per-object transforms; vertices are baked in model space. | This is exactly what the doc's recommended "Apply Scalings = FBX Unit Scale, Forward Z, Up Y" produces. The doc says this "imports into Studio at the same scale". Roblox's own add-on instead uses `global_scale 0.01`, `axis_forward −Z`, which differs by a 180° yaw. **Unverifiable until the first upload.** The kit's `verify_fbx` used `use_manual_orientation=True` in both passes, so it never tested a header-honouring importer. |
| Vertex colours present | Every geometry has a `LayerElementColor` | **Holds.** |
| Tail/lid seams | `add_grid` meshes each group's grid on its own, so no faces are culled between body, tail and lids | **Holds.** A wagging tail shows no holes. |
| Uploader | `research/test_upload_assets.py` | 14/14 pass. Fingerprint = sha256 of the FBX bytes, and the FBX has `CreationTimeStamp` 2026-10-20 10:44:40.762. **Bug: every rebuild looks "changed".** |
| MeshLibrary in the repo mock | `research/test_meshlibrary.py` | 23/23 pass. |
| LoadAssetAsync ownership | Saved `AssetService.yaml` | Same owner rule as LoadAsset unless "Allow Loading Third Party Assets" is on. The returned Model is `Sandboxed` (scripts only). **Holds.** |
| MeshId / RenderFidelity / CollisionFidelity | Saved `MeshPart.yaml` / `TriangleMeshPart.yaml` | `MeshId` write NotAccessibleSecurity. `RenderFidelity` is writable but **NotReplicated**: set it on the client. `CollisionFidelity` cannot be changed at runtime. **Holds.** |
| Lupa bridge | `bridge/bridge_probe.py`: patches `PetBuilder.lua` **in memory** (K multiplier, unlimited part budget, `_Blueprint` accessor), runs it in `tools/robloxmock.lua`, rasterises the blueprint boxes and meshes them with the kit's `greedy_mesh` | **Works, about 1 s per pet.** See the table below. |

Bridge probe results (High; triangles after greedy meshing; part-name groups come straight from PetBuilder):

| Pet / stage | Mesh K | Groups (voxels, tris) | Total tris |
|---|---|---|---|
| pebble_pup base | 1.0 (today) | Body 3055 vox / 2432, WingL/R 216 each, Tail 190, EyeLid 2 × 28 | 3,110 |
| pebble_pup base | 1.38 (40 tall) | Body 4370 (kit hand-port: 4476, so the two agree), Wing 494 each, Tail 252, **EyeLid still 20 vox** | 5,668 |
| pebble_pup evolved 1 | 1.38 × the Lua 1.25 | **Body 20,440**, wings 3,042 each, Tail 978 | **27,544** |
| cloudy_dragon evolved 2 | 1.38 × 1.25 | **Body 24,944** (over 20k), Wing/Wing2/Tail/Halo/Aura 1.2–3.4k each | **42,562** |

What the probe shows:

1. The bridge reproduces the kit's hand-port within 2%, so the two are interchangeable.
2. Face masks and lids are fixed-pixel (`EyeLid` stays 20 voxels), so the kit's procedural face pass is still needed.
3. Evolved forms are already sculpted at K 1.25 in Lua. They must **not** get the extra ×1.38.

## 2. Contradictions and how they are settled

| # | Topic | Scout A | Scout B / style-ref | Decision |
|---|---|---|---|---|
| 1 | Colour source | Pipeline: vertex colours × `MeshPart.Color`, one MeshPart per region | style.md §4: one palette texture on `TextureID`, "do not rely on vertex colours" | **Vertex colours.** The research's evidence: staff article plus doc, Images cannot be PATCHed, embedded-texture behaviour in Open Cloud is unknown, and a texture kills runtime recolour (Golden, Rainbow, hybrids, Wild, difficulty tints). No textures anywhere. |
| 2 | Glow pieces | Pipeline: Neon MeshParts (`Glow`, `Swirl`, star gems) | style.md: "separate Neon *Parts*, not mesh" | **Neon MeshParts.** The player's rule is "no Roblox models". Neon works on MeshParts. Only effects stay as instances on invisible anchors (PointLight, ParticleEmitter, Billboard/SurfaceGui), along with gameplay volumes. |
| 3 | Where ids live | Pipeline: `Config.MeshAssets` | Research: generated `src/shared/MeshIds.lua` | **Both.** `MeshIds.lua` holds numbers only and is written only by the uploader. `Config.MeshAssets = require(script.Parent.MeshIds)` satisfies the contract's "ids live in Config". The check.mjs `asset-id` rule matches strings only, so numbers pass unchanged. |
| 4 | Export axes | Pipeline: doc settings (Forward Z) | Research: add-on uses −Z and 0.01 | Keep the **doc settings**, which are verified to give raw = Roblox studs. The loader **measures** the import yaw and scale per asset (§4.8 "fit"), so neither guess has to be right. |
| 5 | Loader | `MeshKit.lua`: LoadAsset inside Build (yields), client `WaitForChild(name, 10)` (stalls synchronous builders), no PackageLink strip, no retry | `MeshLibrary.lua`: background load, retry, per-device preload fallback, Tag/Dress; but no recipes, manifest, rig, or per-instance look, and it uses `ScaleTo` guesses | **One module** (`shared/MeshLibrary.lua`): MeshLibrary's lifecycle plus MeshKit's recipe engine (`EvalColor`) and manifest placement, plus the fit/validation step (§4.8). |
| 6 | Part names | Kit: `Primary`, `Secondary`, `Eye`, `Pupil`, `Lid_*`, `Tail_*`, `WingL_*`; claws/horns/eye whites baked into `Fixed` | Inventory and tests: `Fur`, `EyeIris`, `EyePupil`, `EyeShine`, `EyeLid`, `Tail`, `WingL`, `^Horn`, `^Nostril`; applyWild, Golden Metal accents and Rainbow work by name | **PetBuilder names win** (§4.3). `Fixed` may only hold regions that no code or test looks up by name. |
| 7 | Triangle budgets | Pipeline: High 6.1k / Low 2.9k (base pets only) | style.md: High ≤ 4k / Low ≤ 1.5k; research: 2–4k, evolved 6k | §4.2 table. The rule is **≤ today's Part build** (parts × 12 box tris) for Low and every evolved form, and ≤ 1.7× for base High. A new pet still costs no more GPU than today, with about 8× fewer instances. |
| 8 | Portal budget | Kit portal 7.2k | style.md ≤ 6k | ≤ 8k per gate. Only 2–3 gates are in view at once. |
| 9 | Shape source | Pipeline: hand-port each species, then evolved forms into `pets.py` | Pipeline option 2: lupa bridge | **Bridge** for every pet, evolved form, hybrid feature, boss and sky dragon. Proven by my probe. Python adds only the detail passes (faces etc.). The `pets.py` ports become golden references for 3 species. |
| 10 | Fallback look for world builders | Pipeline/research: "today's Part build" | style.md: P4 look | **P4 look.** The Part builders are restyled back to P4 (SmoothPlastic, P4 palette, P4 hoop gates) in wave A, because the player will see the fallback until the uploads happen. |
| 11 | `_Light` shade | Kit: separate `<Region>_Light` part (Voxel.Lighten is a lerp, not a multiply) | style.md: Light = base × 1.15 | High keeps the exact `_Light` parts. **Low** uses the "headroom" variant: Color = min(1, base / 0.87); vertex colours: light 1.0, base 0.87, dark 0.87 × Darken. That removes every `_Light` part, about −40% MeshParts. |

## 3. Missing pieces neither scout covered

1. **Evolved forms blow the budget and the per-mesh limit** (bridge numbers above). The grain must be per class, and the build must check budgets and step down automatically, like PetBuilder's lean levels (§4.2).
2. **Name contract and Fixed rules** (decision 6). Add `tools/mesh_names.py`. It greps `src/` and `tools/` for `FindFirstChild("…")`, `partsNamed("^…")` and `Name ==` against palette keys, and the kit refuses to bake any key that is referenced.
3. **Upload churn.** Fingerprint the kit's own `contentHash`: sha256 of the sorted part names, quads and colours, written into the manifest. Do not hash the FBX bytes. For safety, also zero `CreationTimeStamp`/`FileId` after export.
4. **Version skew between code and asset.** `LoadAssetAsync` always loads the *latest* version. A PATCH that changes structure (part names or sizes) would break servers still running the old manifest. Rule: PATCH only when the manifest's `structureHash` (names + sizes rounded to 1e-3) is unchanged. Otherwise the uploader creates a **new asset**, and the key's id changes in the same commit as the manifest. The runtime fit/validation catches anything else and falls back.
5. **Server-built pets and world models at boot.** LobbyBuilder podium/statue, NpcService, StormAltar and all world builders run before the templates load. They need `MeshLibrary.OnReady` swaps: Tag/Dress for the world, and a rebuild-in-place for pets that keeps Name, Parent, pivot, attributes and `PetParts`. Client controllers (PetController, HomeFx, CloudUI viewports, BattleController) need to rebuild visible pets once on `MeshLibrary.Changed`. `PetBuilder`'s template cache key must include the path (`mesh`/`parts`).
6. **Dress needs a per-instance look and static targets.** The `ML_Look` attributes are `ML_Primary`, `ML_Secondary` (Color3), `ML_Stars` (number) and `ML_Variant` (string), and are evaluated by the same recipe engine. Parts the server changes later (LockWalls, CountdownFace, BillboardAnchor, PromptAnchor, zones) must be in Keep or outside the dressed subtree. Otherwise a server-side Transparency change replicates over the local hide, or the mesh hides live state.
7. **Mock coverage of the mesh path.** No test runs PetBuilder or the builders *through* meshes. Add fixture templates and run the key suites in both modes (§4.9).
8. **Tooling.** `render_model.py`/`dump_model.lua` draw MeshParts as boxes. The kit must emit `blender/out/<key>.tris.json.gz` (per-part triangles plus vertex colours), and render_model must draw a MeshPart that has an `ML_Key`/`ML_Part` from it. That way visual iteration in lupa keeps working.
9. **The first real upload must be a calibration asset.** `cal_axes` is an asymmetric model: an "F" arrow towards −Z, a red bar at +X, a green bar at +Y, a 2-stud cube with a vertex-colour gradient, and a part named `Head_Att`. It answers yaw, mirror, scale, vertex colour, names, Anchored and PackageLink in one look, before any pet is uploaded.
10. **Replicated memory.** About 200 templates × 2 LODs replicate to every client. Measure the Developer Console mesh memory after the first batch. Fallback plan: keep the templates in ServerStorage and copy a key into ReplicatedStorage the first time a pet or view needs it.

## 4. The corrected recipe (contract text for the lead)

### 4.1 Pipeline layout (repo)
```
blender/kit/nvox/        grid, shade, mesher, blend, manifest, colors (from the pipeline prototype)
blender/kit/bridge.py    lupa bridge: runs src/shared/{Voxel,PetBuilder,BossBuilder,...}.lua in tools/robloxmock.lua at mesh K,
                         returns blueprint groups (boxes or grids by palette key, hinge CFrames, anchors) - NEVER edits src
blender/kit/detail/      Python detail passes keyed by blueprint anchors: procedural eyes + lids (scale with K), mouth/toe
                         snapping, nose shine; brick/plank/tile patterns for world pieces
blender/kit/props/       world pieces that are new designs (P4 hoop gate, crowned arch, crests, clouds, lobby props)
blender/build_all.py     builds every key in blender/catalog.json -> blender/out/<key>.fbx + .manifest.json + .tris.json.gz
                         + preview PNG; writes blender/meshes.json (uploader index) and src/shared/MeshManifests/<key>.lua
tools/upload_assets.py   research uploader + the fixes in 4.7
src/shared/MeshIds.lua   GENERATED by the uploader only (numbers)
src/shared/MeshLibrary.lua  the single runtime loader (4.8)
```
Shape source of truth:
- **Lua sculpt code via the bridge** for all creatures: 15 species, evolved forms 1 and 2, hybrid add-ons, Golden stars, aura bits, bosses and the sky dragon.
  - PetBuilder gets two **read-only hooks**, which change nothing in the game: `PetBuilder._Blueprint(look, detail, k)` and `bp.Anchors` (HeadTop, EyeL/R, Hat, Neck, Flower, HornBase, hybrid sockets).
  - The per-class mesh K and the budget override come from the bridge, not from a game setting.
- **Python `props/`** for world pieces. They are re-designed at the finer grain from the P4 builders. The kit's `portal` is the template for this.

### 4.2 Grain and budgets (build fails if exceeded; it steps K down by 0.9 up to 2 times, then fails)
| Class | Mesh K / voxel | High tris (model) | Low tris | MeshParts High / Low |
|---|---|---|---|---|
| Base pet (body + tail + lids) + wings + accessory | ×1.38 (40 tall, 0.0725 stud) / Low ×0.86 | ≤ 6.5k | ≤ 3k | ≤ 40 / ≤ 14 |
| Evolved 1 | ×1.0 of the Lua K (1.25) / Low 0.65 | ≤ 15k (today ~11–18k) | ≤ 4.5k | ≤ 50 / ≤ 16 |
| Evolved 2 | ×0.9 of the Lua K / Low 0.55 | ≤ 20k (today ~18–24k) | ≤ 6k | ≤ 60 / ≤ 18 |
| Boss | 0.25–0.33 stud | ≤ 15k | ≤ 6k | ≤ 40 |
| Sky dragon | 0.5 stud | ≤ 12k | n/a | segments reused (cloned) |
| Gate (each of 6) | 0.5 stud gate, 0.25 detail | ≤ 8k | n/a | ≤ 20 |
| Lobby prop / home station / decor | 0.5 / 0.25–0.33 | ≤ 2k / ≤ 4k | n/a | ≤ 8 |
| Cloud puff / island | 1–1.5 stud | ≤ 3.5k per asset, cloned | n/a | 1–2 |
| Floor / path / yard | 2-stud tile cells | ≤ 1k per 32 × 32 stud chunk | n/a | 1 per chunk |

Limits that apply everywhere:
- **Per MeshPart:** ≤ 10k triangles. The hard limit is 20k.
- **Busiest phone view** (lobby with 16 players × 3 pets): ≤ 300k triangles and ≤ 400 draw calls. Measure it in Studio with the phone emulator plus MicroProfiler, and add `tools/mesh_budget.py`, which sums manifests over builder placements.
- **RenderFidelity:** `Precise` on pets and gates (set on the client). World props and clouds stay `Automatic`.
- **Gameplay sizes are fixed:** the pet's visual height stays within PetBuilder's 2.0–3.4 studs, and world footprints are unchanged.

### 4.3 Part split and names (runtime contract)
- **One MeshPart per (group, palette key, shade class).**
  - Body parts are named with the **PetBuilder palette base key**: `Fur`, `Accent`, `Belly`, `EyeIris`, `EyePupil`, `EyeShine`, `EyeGlint`, `Horn`, `Nostril`, and so on.
  - The light shade is a separate part named `<Key>Light` (for example `FurLight`). It still matches the tests' `^Key` patterns.
- **Group parts use the group name, as `instantiate` does today:** `WingL`, `WingL2`…, `WingR…`, `Wing2L…`, `Tail…`, `Halo…`, `Aura…`, `EyeLid…`. Each carries attribute `MK_Key` = the palette key.
- **L and R are separate meshes.** Negative scale cannot mirror a MeshPart.
- **`Fixed`** (baked constant colours) only for keys that `tools/mesh_names.py` finds unreferenced. Never for `Horn`, `Claw`, `Beak`, `Hoof`, `Nostril`, `EyeShine`, Golden-Metal keys or Rainbow keys.
- **The loader writes the rig attributes** (`PB_G`, `PB_Base`, `PB_Rig`, `PB_T0` on lids, `PB_Pulse`, `PB_Scale`, `PB_Detail`, `PetId`, `PB_Seed`, `PB_Finish`, `PB_Hybrid`, `PB_Hue`, `PB_Evolved`) from the manifest groups and hinges. These come from the bridge, so they are byte-identical to `instantiate`. `Animate`, PetController, HomeFx, NpcController and EvolutionFx stay unchanged.
- **Root:** an invisible `Body` Part (0.9 × 1.1 × 0.9 × scale), the same as today. It is a root, not a model.
- **World MeshParts:** names = the P4 builder's colour keys (`Stone`, `Trim`, `Glow`, `Swirl`, `Gem`, `Star1..5`, …). Per-instance tint keys stay separate parts.
- **Collision:** visual meshes have `CanCollide`/`CanTouch`/`CanQuery` off, `CastShadow` off when under 4 studs, and `Massless`. Floors, gates and walls keep invisible box Part colliders. Zones, prompts, billboard anchors and effects stay as they are today.

### 4.4 Colour
- **Base, dark and deep shades:** vertex colours (sRGB bytes, corner domain) of 1, the Darken factor (0.8425, 0.85, 0.8875) and its square. The runtime sets `Color` = recipe(Look). Gamma commutes with a per-channel multiply, so this matches today's shades in either colour space.
- **Light:** the `<Key>Light` part with `Color = Voxel.Lighten(recipe)` on High. On Low, use the headroom variant (decision 11).
- **Export materials:** a single white material (`M_Vertex`), no textures, `path_mode STRIP`. The loader always sets `Color`, so whatever the importer does with the material colour is irrelevant.
- **Recipes** (the kit's `colors.py` and the Lua `EvalColor`) cover Look colours, finishes (Golden ramp plus `Material = Metal` on Golden keys, Rainbow keys for Animate's hue cycle), Wild (`applyWild` keeps working by name) and difficulty or mode tints.

### 4.5 Export and verification (per FBX)
- **Export:** `apply_scale_options=FBX_SCALE_UNITS`, `global_scale 1`, `axis_forward Z`, `axis_up Y`, `bake_space_transform`, `colors_type SRGB`, mesh objects only. Vertices are in model space, so the pivot is the scene origin.
- **Verify:**
  - A RAW re-import must equal the manifest (≤ 1e-3 studs), with names, triangle count and the colour layer intact.
  - A **header-honouring** import must put the front at −Y in Blender.
  - Every part must be closed (no open edges), have no zero-area quads, and stay under the budgets.
  - `contentHash` and `structureHash` are written into the manifest.

### 4.6 Manifest and index
- **`<key>.manifest.json`** (the kit's format) contains:
  - parts: `name`, `group`, `key`, `shade`, `center`, `size`, `tris`, `material`, `color` recipe, `transparency`
  - `groups` with hinge CFrames and kinds
  - `attachments`
  - `bounds`, `contentHash`, `structureHash`
- **`manifest_to_lua.py`** emits `src/shared/MeshManifests/<key>.lua`.
- **`blender/meshes.json`** has one entry per key: fbx, displayName (`NC <Key>`, plain words), description, `maxTrianglesPerMesh`, `contentHash`, `structureHash`.
- **Keys:** `pet_<species>`, `pet_<species>_low`, `evo1_<petId>[_low]`, `evo2_<petId>[_low]`, `wing_<style>[_low]`, `acc_<name>[_low]`, `hyb_<feature>`, `boss_<id>`, `gate_<kind>`, `prop_<name>`, `cloud_<size>`, `floor_<area>_<i>`, `cal_axes`.

### 4.7 Upload (tool `tools/upload_assets.py`; key arrives later; never fake)
- **Environment:** `ROBLOX_API_KEY`, `ROBLOX_CREATOR_ID`, `ROBLOX_CREATOR_TYPE` (user|group).
- **Creator must be the experience owner.** If it is not, LoadAsset is refused and everything silently stays on the Part fallback. The uploader prints the creator and refuses to switch creators once the id table records one.
- **Create:** `POST /assets/v1/assets` with assetType `Model` and Content-Type `model/fbx`, then poll `operations/{id}`.
- **Fingerprint:** `contentHash`, not the FBX bytes.
- **Update:** if `structureHash` is unchanged, PATCH (new version, same id). Otherwise create a **new** asset.
- **Retries, limits and resume:** handle 429 and 5xx, throttle below the documented 120 writes/min, and resume pending operations (as the research tool already does).
- **Moderation:** Rejected ids are left out of `MeshIds.lua`. Reviewing ids are emitted, because they simply fail to load and fall back.
- **Order:**
  1. `cal_axes` alone, inspected in Studio (see §6).
  2. One pet (`pet_dog` + `_low` + `wing_feather` + `acc_crown`), played in a live server.
  3. Batches by class.
- After each batch: commit `MeshIds.lua`, rebuild the place with Rojo, and the owner publishes.

### 4.8 Runtime: `shared/MeshLibrary.lua` (merge of both prototypes)

**Server `Start()`** reads `MeshIds`. An empty table means today's game, exactly. For each id it does the following:
1. Load in the background, at most `MaxParallel` (4) in parallel, the keys of `ML_Dress`-tagged targets first (tagged before Start or while the queue drains), then alphabetical (2026-10-24 mesh-load-priority): `AssetService:LoadAssetAsync` first, then `InsertService:LoadAsset`, both inside pcall. Retry after 2, 5 and 12 s. Do not retry "not authorized", "does not exist" or "invalid".
2. Unwrap the result, and strip PackageLink and any scripts.
3. **Fit and validate against the manifest:**
   - Every manifest part name must exist as a MeshPart (no merged meshes).
   - Solve scale ∈ {1, 100, 0.01, measured} and yaw ∈ {0, 90, 180, 270}, plus mirror, from the imported part centres relative to the model pivot versus the manifest centres (least squares).
   - Fail the key if the error is over 2% of the bounds, or if mirror is detected (the exporter must be fixed).
   - Then set every part's `Size` = manifest size and `CFrame` = manifest centre × yaw correction. The template is now canonical, at pivot = identity.
4. Set Anchored, collisions off, Massless, `Color` white and SmoothPlastic (Neon where the manifest says so).
5. Parent the template under `ReplicatedStorage.MeshLibrary.<key>` with `ML_Status` (ready or failed), `ML_Error` and `ML_LoadMs`.

**Client `Start()`:**
- `ContentProvider:PreloadAsync` per template, at most `ClientParallel` (6) at once, best first: keys of tagged targets nearest the camera, then keys something waits on (`OnReady`), then arrival order (2026-10-24 mesh-load-priority). A Failure status marks that key broken *on this device only*.
- Set `RenderFidelity` locally on the templates (Precise or Automatic per class). It does not replicate.
- Fire `MeshLibrary.Changed(key)`.

**API (synchronous, never yields):**
- `IsReady(keys…)`, `Status(key)`, `OnReady(key, fn)`, `Changed` (signal).
- `EvalColor(recipe, look)`.
- `Assemble(spec, look, opts)` → Model | nil. This is the generic manifest assembler (body + groups + child keys at attachments) and writes the rig attributes.
- `Tag(target, key, look, keep)` on the server and `Dress` on the client, carrying the per-instance `ML_*` look attributes.
- `Swap(model, buildFn)` rebuilds a server-built model in place when its keys become ready.

**Pet path.** Inside `PetBuilder.Build`, before `getBlueprint`:
- Work out the needed keys: body, stage, LOD, wing, accessory, hybrid features, finish bits.
- If **all** of them are `IsReady`, build the mesh pet with `MeshLibrary.Assemble` and then run Build's existing tail: sparkles, `PB_Evolved`, Wild.
- Otherwise build the **whole** pet from Parts. Never mix a mesh body with Part features.
- The cache key includes the path.

**World path.** Builders keep building the (P4-look) Part model, which stays the collider, keeps the test-visible names and serves as the fallback. They `Tag` the static decoration subtrees. Clients `Dress` them: parts are hidden locally, Keep parts stay visible, and the mesh is parented under the target. Streaming re-adds re-dress through the CollectionService signal.

**Legal and robust:**
- Only assets owned by the experience creator are loaded, with third-party loading left off.
- No client-side LoadAsset.
- No MeshId writes.
- Every failure (missing id, still in moderation, wrong owner, wrong structure, client fetch failure) degrades per key to the Part build.

### 4.9 Tests and tooling (all of tools/smoke.py stays green)
- **Default mode** (no ids, and the mock has no LoadAsset): every path is the Part path, as today.
- **New `tools/smoke_p6_mesh.lua`.** It installs **fixture templates** built from the committed manifests (mock MeshParts with the manifest names, sizes and positions, and one fixture with a 180° yaw and one with 100× scale) under `ReplicatedStorage.MeshLibrary`. Then it checks:
  1. The fit corrects yaw and scale, and rejects a missing part or a mirror.
  2. `PetBuilder.Build` takes the mesh path. Names match the part-name contract (§4.3), the PB_* attributes are present, `Animate` flaps with no NaN and no new instances, and Clone animates.
  3. Wild, Golden and Rainbow work.
  4. A partially ready set falls back whole.
  5. Swap and Dress work.
  6. A client-only failure keeps Parts.
  - It also ports the research's 23 MeshLibrary checks.
- **Both modes.** `smoke.py --mesh-fixtures` re-runs smoke_content (pet structure), smoke_p3_evolved, smoke_p2_fusion, smoke_p5_follow and smoke_storm in mesh mode. Asserts about voxel internals (part caps, ≥ 300 boss parts, "≥ 2 shades of one key", sky dragon ≥ 60 parts) are gated to the Part path. Mesh mode gets mesh asserts instead (tri budget from manifests, MeshPart count caps).
- **`smoke_content.lua:1243`** ("pets use no external assets") becomes: "MeshParts only from `ReplicatedStorage.MeshLibrary` templates whose key is in MeshIds; no TextureID; no SurfaceAppearance."
- **`check.mjs`:**
  - Existing rules are unchanged (MeshIds holds numbers).
  - New: `InsertService`/`AssetService:LoadAsset*` is allowed only in `MeshLibrary.lua`.
  - New: `MeshIds.lua` may only contain `[string] = number`.
- **`tools/contract.json` budgets** count MeshParts.
- **Style revert tests.** `smoke_p5_world.lua:60/203/353` and `smoke_p2_final.lua:1767/1866` change in the same commit as the P4-look and lighting revert.
- **Render tooling.** `render_model.py` draws `ML_Key`/`ML_Part` MeshParts from `blender/out/<key>.tris.json.gz`. Kit previews (Cycles) stay the art review tool. Review at least 3 rounds per class against the P4 renders in `style-ref/`.

### 4.10 Look decisions
- **Part fallback for the world = P4 look.** SmoothPlastic, the P4 palette (style.md §4 numbers), no round primitives, and the P4 hoop gate in the Gate Court layout. Map the gates as follows:

  | Gate | Shape | Colour and crest |
  |---|---|---|
  | Obby | hoop | 5-star crest |
  | Ring | crowned arch | — |
  | Arena | hoop | sword crest |
  | Dungeon | hoop | purple |
  | Home | hoop | yellow |
  | Altar | hoop | cyan |

  Keep the layout, prompts and pads.
- **Lighting:** ShadowMap plus the P4 `LOOK` values (style.md §4). Keep the skybox path. Atmosphere is P4 sky-blue and peach while `Config.Sky.Faces` is empty, and light pink once the painted sky ids are pasted.
- **Clouds:** P4 white / light blue. That matches "back to Phase 4" and the current fallback sky.
- **UI fonts / NeonKit:** unchanged; the player asked for them.

### 4.11 Build order (waves)
- **A. Look revert in Lua (no assets).** WorldStyle → P4 palette and SmoothPlastic; LobbyBuilder/HomeBuilder/ArenaBuilder/DungeonBuilder P4 look; gate kit = P4 hoop and arch plus crests; lighting; the pinned tests updated. This is what the player sees until the uploads.
- **B. Kit in the repo.** nvox plus the bridge with the PetBuilder/BossBuilder read-only hooks, detail passes, `build_all.py`, `mesh_names.py`, `mesh_budget.py`, the `.tris.json.gz` renderer path. Build every key, and do art review rounds on the previews.
- **C. Runtime.** MeshLibrary (merged), the PetBuilder mesh path, Swap/Dress in the builders, client rebuild on `Changed`, fixtures, `smoke_p6_mesh`, mesh-mode reruns, check.mjs rules. Full `tools/smoke.py` green in both modes.
- **D. Uploads (player OK plus key, new session).** Calibration (§6), then one pet, then batches. Commit `MeshIds.lua` and republish after each batch.

## 5. Risks still open
1. **Facing and scale of Open Cloud imports.** Handled by fit plus the calibration asset, but a **mirror** would force an exporter change (FBX axes).
2. **Names.** That MeshPart names equal the FBX object names, and that meshes are not merged, is INFERRED from the importer defaults. The loader validates it, and if it is wrong, every key fails into the fallback, which is safe.
3. **T-junction sparkles** from greedy quads. Check in Studio. The fix is an edge-split pass (+10–20% triangles).
4. **Client memory** with every template replicated (§3.10).
5. **Fresh meshes not drawing for some clients** (FORUM t/4730088). Covered by the per-device PreloadAsync fallback.
6. **Collision geometry memory.** MeshParts keep collision data even with CanCollide off, and fidelity is not scriptable. Measure. If it is high for big world meshes, re-make those few templates once per server with `AssetService:CreateMeshPartAsync(…, {CollisionFidelity = Box})` (about 22 ms each).

## 6. First real upload checklist (needs the player's OK and the key; never simulated)
1. The owner confirms the experience owner is a user or a group, and its id. The key is created by that owner with Assets read + write.
2. `upload_assets.py --dry-run --only cal_axes`, then the real call. Record the id.
3. In a **published** place owned by the same creator, a server script loads `cal_axes` and prints:
   - the MeshPart names and their positions relative to the pivot (yaw, mirror and scale);
   - `Size` versus the manifest;
   - whether there is a PackageLink and whether parts are Anchored;
   - whether `Head_Att` became an Attachment.

   Then **look at it**: the vertex-colour gradient should show with Color white, and the "F" arrow should point to −Z.
4. PATCH `cal_axes` once with only a colour change. The id must stay the same, and a new server must load the new colours.
5. Only then: the one-pet batch, played live (follow, flap, blink, Wild, Golden), then class batches.
