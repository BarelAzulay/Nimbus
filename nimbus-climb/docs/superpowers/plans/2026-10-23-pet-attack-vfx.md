# Pet Attack Animations and VFX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every pet attack (basic melee / ranged, 8 element attacks, 9 special kinds, 12 signatures) a stylized,
reference-quality animation and element VFX that grows visibly cooler by rarity band, without touching battle rules.

**Architecture:** A pure-data `AttackFxCatalog` resolves (element, attack, kind, rarity, stage, pet) into a recipe; a
client `AttackFx` engine plays recipes with pooled kits (solid Blender core meshes + sparse flipbook particles, beams,
trails, lights) under a budget and the graphics setting; `PetPoses` drives the existing pet rig. `BattleController`
handlers call `AttackFx` first and keep today's cube `Fx.*` as the fallback.

**Tech Stack:** Roblox Luau (plain Lua 5.1-compatible syntax), Rojo 7.7.1, Blender 5.2 (bpy 5.2.2 pinned), Python 3 +
lupa smoke harness (`tools/smoke.py`), Node `tools/check.mjs`, Roblox Studio MCPs (robloxstudio, Roblox_Studio).

**Spec:** `docs/superpowers/specs/2026-10-23-pet-attack-vfx-design.md` (all paths below are relative to `nimbus-climb/`).

## Global Constraints

- No change to `src/shared/BattleSim.lua`, `src/server/Services/BattleService.lua` or any damage / timing / balance number.
- Every visible model or core shape is made in Blender (no Roblox `generate_model`, Toolbox or Creator Store assets).
- `TextureIds.lua` holds **Image** ids only (`AssetTypeId == 1`), never Decal ids.
- Rarity bands: 1 = Common/Uncommon, 2 = Rare/Epic, 3 = Legendary/Mythic, 4 = Secret. Sizes: Common 1.0, Uncommon 1.05, Rare 1.1, Epic 1.15, Legendary 1.2, Mythic 1.3, Secret 1.4. Evolved +5%, Evolved II +10%; **hard cap 1.4**.
- Each band keeps every layer of the bands below it (layer sets are monotonic).
- Own team: full density. Other players' and wild pets: density 0.6, no camera punch, no screen-edge glow.
- Camera punch: Legendary and up, own pet only. Screen-edge glow: Secret, own pet only.
- Lingering fields are ground decals only and fade near boss telegraphs; telegraphs always draw on top.
- Existing caps stay and stay tested: `MAX_FX_PARTS 260`, `MAX_NUMBERS 26`, `MAX_FLASHES 8`.
- Low graphics (`GraphicsQuality.Effective() == "Low"`): light kits (no Beams, no Trails, no bloom), else the cube `Fx.*` fallback.
- Impact never plays later than the server event's due time (damage numbers stay in sync).
- Plain Lua 5.1-compatible syntax in every Luau file (no `+=`, no type annotations): the lupa harness loads them.
- Every new `tools/smoke_*.lua` is listed in `tools/smoke.py` `server_files` / `client_files` and its scenarios in the scenario lists.
- Commit and push after every task (project rule); pull --rebase first (a cloud session also pushes to main).

## Review Focus

1. **A unit with no model** (streamed out, spectator, late joiner, KO'd mid-travel): `AttackFx` must no-op or finish at the last known point, never error. Test owned by Task 6.
2. **Hybrid pets** (`hyb:` keys, two elements, rarity from the hybrid record): the recipe uses the first element and the hybrid's rarity. Test owned by Task 4.
3. **Fast attackers** (short `Interval`, Haste buff): a new attack on the same unit cancels its previous pose / charge; poses never stack. Test owned by Task 6.
4. **Battle End or Leave mid-effect**: every live effect and pose is cleaned at once, pools return to their keep size. Test owned by Task 7.
5. **Graphics switched to Low mid-battle**: live effects downgrade or end within one frame; new ones use the light kit. Test owned by Task 6.

---

### Task 0: Local toolchain and baseline

**Files:**
- Modify: `tools/README.md` (a "Windows setup" paragraph)

- [ ] **Step 1: Install Python 3.12 and the harness packages**

Run: `winget install -e --id Python.Python.3.12` then `py -3.12 -m pip install lupa numpy pillow`
Expected: `py -3.12 -c "import lupa, numpy, PIL; print('ok')"` prints `ok`.

- [ ] **Step 2: Record the baseline gate**

Run: `node tools/check.mjs` and `py -3.12 tools/smoke.py --quick`
Expected: check.mjs `0 error(s)`; smoke prints its pass/fail totals. Save both summary lines in the task notes: every later task compares against this baseline (no new failures).

- [ ] **Step 3: Document and commit**

Add the two install commands to `tools/README.md` under "Windows setup"; commit `tools: Windows setup for the smoke harness`.

---

### Task 1: Blender flipbook textures

**Files:**
- Create: `blender/vfx/textures.json` (the texture manifest)
- Create: `blender/vfx/render_textures.py` (Blender script: `blender.exe -b -P blender/vfx/render_textures.py -- --out blender/vfx/out [--key K]`)
- Create: `tools/vfx_textures_check.py`
- Modify: `.gitignore` (`blender/vfx/out/`)

**Interfaces:**
- Produces: manifest entries `{ "key": str, "grid": 4, "size": 1024, "mode": "OneShot"|"Loop", "fps": int, "elements": [str] }` and one PNG per key at `blender/vfx/out/<key>.png`.

Keys (30): `fx_flame`, `fx_embers`, `fx_smoke`, `fx_splash`, `fx_droplets`, `fx_ripple`, `fx_iceshards`, `fx_snow`, `fx_frostmist`, `fx_petals`, `fx_leaves`, `fx_thorn`, `fx_rock`, `fx_dust`, `fx_crack`, `fx_lightning`, `fx_sparks`, `fx_stormcloud`, `fx_stars`, `fx_rays`, `fx_sparkle`, `fx_wisps`, `fx_voidring`, `fx_darkglass`, `fx_slash`, `fx_shock`, `fx_glow`, `fx_streak`, `fx_speedlines`, `fx_hexshield`.

- [ ] **Step 1: Write the failing check**

`tools/vfx_textures_check.py` asserts for every manifest key: the PNG exists; it is 1024x1024 RGBA; the four corner pixels have alpha 0; each of the 16 grid cells has at least 2% pixels with alpha > 32 (no empty frames); transparent pixels' RGB is the dark tint (30, 38, 72) (no checkerboard / gray fringe; the Storm Altar lesson); key names match `^fx_[a-z]+$` and are unique.

- [ ] **Step 2: Run it to see it fail**

Run: `py -3.12 tools/vfx_textures_check.py`
Expected: FAIL, `missing blender/vfx/out/fx_flame.png` (and the others).

- [ ] **Step 3: Implement `render_textures.py`**

Stylized (spec style A): render each key's 16 frames with EEVEE, an orthographic camera, a transparent film and emission shaders in a white-hot core -> element colour -> soft edge ramp (Config.Elements colours), tiled into a 4x4 grid; before saving, set RGB of alpha-0 pixels to (30, 38, 72). Deterministic (fixed seeds).

- [ ] **Step 4: Render and check**

Run: `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P blender/vfx/render_textures.py -- --out blender/vfx/out` then `py -3.12 tools/vfx_textures_check.py`
Expected: `30/30 textures OK`.

- [ ] **Step 5: Contact sheet + commit**

Write `blender/vfx/out/contact_sheet.png` (all 30 keys, first and middle frame each, on a dark-blue and a green background). Commit the manifest and scripts (not `out/`).

---

### Task 2: Blender effect cores (solid shapes) and signature cores

**Files:**
- Create: `blender/catalog/vfx.json` (class "vfx", same schema as `blender/catalog/*.json`)
- Create: `blender/kit/props/vfx_cores.py` (the hook that builds the core shapes, following `blender/kit/props/` conventions)
- Modify: `blender/meshes.json` (the build adds the vfx keys), `src/shared/MeshManifests/` (generated by `blender/kit/manifest_to_lua.py`)

**Interfaces:**
- Produces mesh keys: `vfx_orb`, `vfx_crescent`, `vfx_spear`, `vfx_spike`, `vfx_ring`, `vfx_shell`, `vfx_beam`, `vfx_shard`, `vfx_chunk`, `vfx_star`, `vfx_root`, `vfx_cage`, plus signature cores `vfx_sig_phoenix_wing`, `vfx_sig_sun_disc`, `vfx_sig_wolf`, `vfx_sig_black_sun`, `vfx_sig_cloud_dragon`, `vfx_sig_wish_star`, `vfx_sig_fox_orb`, `vfx_sig_lava_spike`, `vfx_sig_glacier`, `vfx_sig_serpent`. Each is one MeshPart (single manifest part `Core`), white (tinted at runtime), fine-voxel styled edges.

- [ ] **Step 1: Add the keys to the catalog and run the self-test to see it fail**

Run: `py -3.12 blender/kit/selftest.py`
Expected: FAIL, `vfx: hook vfx_cores missing`.

- [ ] **Step 2: Implement the hook**

Sizes in studs at scale 1: orb 2, crescent 4 x 0.4 x 2, spear 5 long, spike 3 tall, ring 4 diameter, shell 5, beam 1 x 1 x 8 (stretched at runtime), shard 1.2, chunk 0.8, star 1.5, root 4 tall, cage 4; signature cores sized to read at the pet's scale (Phoenix wing 6 span, black sun 6, glacier 5).

- [ ] **Step 3: Build, self-test, preview**

Run: `py -3.12 blender/build_all.py --class vfx --preview` (Blender python per `blender/README.md`) then `py -3.12 blender/kit/selftest.py`
Expected: self-test passes; FBX + manifest per key; `blender/vfx/out/cores_preview.png`.

- [ ] **Step 4: PLAYER CHECK-IN 1**

Show the player `cores_preview.png` and `contact_sheet.png`. Apply their notes before Task 3.

- [ ] **Step 5: Commit**

---

### Task 3: Upload textures and cores

**Files:**
- Modify: `src/shared/TextureIds.lua` (`return { fx_flame = "rbxassetid://<n>", ... }`)
- Modify: `src/shared/MeshIds.lua`, `blender/upload_state.json` (through `tools/upload_assets.py --emit-lua`)
- Create: `tools/smoke_p7vfx.lua` (first scenario only: `p7vfx_ids`)
- Modify: `tools/smoke.py` (register the file and the scenario)

- [ ] **Step 1: Write the failing scenario `p7vfx_ids`**

Asserts: every key of `blender/vfx/textures.json` is in `TextureIds` with a value matching `^rbxassetid://%d+$`; `TextureIds` has no extra keys; every `vfx_*` key of `blender/catalog/vfx.json` is in `MeshIds`.

- [ ] **Step 2: Run to see it fail**

Run: `py -3.12 tools/smoke.py --only p7vfx_ids`
Expected: FAIL, `TextureIds missing fx_flame`.

- [ ] **Step 3: Upload textures through Studio**

Serve `blender/vfx/out/` on 127.0.0.1 (one-file server like the Stormfang upload) and call the Roblox_Studio MCP `upload_image` in batches; write `TextureIds.lua`. Then, in Studio, run the id check: each id `MarketplaceService:GetProductInfo(id).AssetTypeId == 1` and `ContentProvider:PreloadAsync` status `Success`; record the result in the task notes.

- [ ] **Step 4: Upload cores (needs `ROBLOX_API_KEY` / `ROBLOX_CREATOR_ID`: the cloud session or a local env; never print the key)**

Run: `py -3.12 tools/upload_assets.py --only <each vfx key> --emit-lua src/shared/MeshIds.lua` after a `--dry-run`; follow `docs/phase6/OWNER_UPLOAD.md` (player OK before the first real upload).
Expected: all vfx keys Approved.

- [ ] **Step 5: Run to see it pass, commit**

Run: `py -3.12 tools/smoke.py --only p7vfx_ids` -> PASS.

---

### Task 4: `AttackFxCatalog` (pure data + resolver)

**Files:**
- Create: `src/shared/AttackFxCatalog.lua`
- Modify: `tools/smoke_p7vfx.lua` (scenario `p7vfx_catalog`), `tools/smoke.py`, `tools/contract.json` (the new module's API)

**Interfaces:**
- Produces:
  - `AttackFxCatalog.BandOf(rarity) -> 1..4` (unknown rarity -> 1)
  - `AttackFxCatalog.SizeOf(rarity, stage) -> number` (constraint table, cap 1.4)
  - `AttackFxCatalog.Resolve(req) -> recipe | nil`, `req = { Element, Attack, Kind, Shape, Rarity, Stage, PetId, Mine }` with `Attack` in `"Melee" | "Ranged" | "Special" | "Element" | "Hurt" | "Ko" | "Victory"`, `Kind` one of the 9 special kinds (for `"Special"`), `Shape` `"Cone" | "Circle" | "Line"` (for `"Element"`).
  - `recipe = { Band, Size, Density, CameraPunch, ScreenGlow, Signature (petId|nil), Beats = { Charge, Release, Travel, Impact, Linger } (seconds), Core = { Key, Color, Material, Path ("Projectile"|"Swipe"|"Ground"|"Self"|"Allies"|"Area") }, Layers = { { Kind ("Emitter"|"Beam"|"Trail"|"Light"|"Ring"|"Decal"), Texture, Color, Count, ... } }, Alive = { ... } }`
  - `AttackFxCatalog.Unit(info) -> { Element, Rarity, Stage, PetId, Ranged }` from a BattleSim unitInfo (`petId`, `key`, `look`, `element`, `elements`, `evo`, `ranged`): rarity from `PetCatalog.Get(petId).Rarity`, a hybrid's from its look / record, first element when several.
  - `AttackFxCatalog.Signatures` keyed by the 12 pet ids of the spec table.

- [ ] **Step 1: Write the failing scenario `p7vfx_catalog`**

Assertions:
- For every element of `Config.Elements.Order` x Attack (`Melee`, `Ranged`, `Hurt`, `Ko`, `Victory`, each `Element` shape, each of the 9 `Special` kinds) x the 7 rarities x stages 0..2: `Resolve` returns a recipe with finite beats summing to <= 2.5 s (specials <= 3.5 s), `Size <= 1.4`, `Band == BandOf(rarity)`.
- Layer-kind sets are monotonic across bands for the same request.
- `Mine = false` -> `Density == 0.6`, `CameraPunch == false`, `ScreenGlow == false`; `Mine = true` -> `CameraPunch == (band >= 3)`, `ScreenGlow == (band == 4)`.
- Every `Texture` and `Core.Key` used exists in `blender/vfx/textures.json` / `blender/catalog/vfx.json`.
- `Signature` is set exactly for the 12 spec pets when `Attack == "Special"`.
- Review Focus 2: `Unit` on a `hyb:` unitInfo with `elements = {"Storm", "Flame"}` returns `Element = "Storm"` and the hybrid's rarity.
- Nature's ranged recipe uses the petal trail (`fx_petals`) and no green-only layer (it must read on grass).

- [ ] **Step 2: Run to see it fail**

Run: `py -3.12 tools/smoke.py --only p7vfx_catalog`
Expected: FAIL, `could not load AttackFxCatalog`.

- [ ] **Step 3: Implement the catalog**

Data straight from the spec tables (element normal attacks with their "alive" details, the 9 special kinds, the 4-band ladder, the 12 signatures). Beats: Charge 0.12-0.3 (specials up to 0.8), Release 0.05, Travel by distance (projectile speed 60 studs/s; capped so impact <= event time), Impact 0.15, Linger 0.4-1.0.

- [ ] **Step 4: Run to see it pass**

Expected: `p7vfx_catalog` all checks PASS.

- [ ] **Step 5: Commit**

---

### Task 5: `PetPoses` and the rig hook

**Files:**
- Create: `src/shared/PetPoses.lua`
- Modify: `src/shared/PetBuilder.lua` (`PetBuilder.Animate` reads `opts.Pose`)
- Modify: `tools/smoke_p7vfx.lua` (scenario `p7vfx_poses`), `tools/smoke.py`, `tools/contract.json`

**Interfaces:**
- Produces:
  - `PetPoses.Names = { "Windup", "Strike", "Recoil", "Cast", "Hurt", "Ko", "Victory", "IdleBattle" }`
  - `PetPoses.Sample(name, p, ranged) -> { Body = CFrame, Groups = { [groupKind] = CFrame }, Lids = 0..1 }` for `p` in 0..1 (`IdleBattle` loops: `p` = time)
  - `PetBuilder.Animate(model, t, { Flap, Excited, Pose = { Name, P, Ranged } })`: the pose's group offsets multiply onto `groupMotion`, `Lids` closes the eyelids; `Body` is returned by `PetBuilder.PoseBody(opts) -> CFrame` for the caller to apply to the root (BattleController writes the root).

- [ ] **Step 1: Write the failing scenario `p7vfx_poses`**

Every pose name at p = 0, 0.25, 0.5, 1 returns finite CFrames; non-looping poses are identity at p = 0 and p = 1; `Strike` moves Body forward (+Z look) and `Recoil` backward; `Hurt` sets `Lids >= 0.8` at p = 0.3; `Animate` with a `Pose` on a real `PetBuilder.Build` pet (stage 0 and 2, one winged, one tailed) changes WingL / Tail part CFrames vs. the same call without Pose, and creates no Instances.

- [ ] **Step 2: Run to see it fail**, **Step 3: Implement**, **Step 4: Run to see it pass**, **Step 5: Commit** (same command pattern: `py -3.12 tools/smoke.py --only p7vfx_poses`).

Shapes: Windup = crouch 0.25 studs, wings back 25 deg, tail up; Strike = lunge 1.5 studs (melee) / recoil 0.35 (ranged, `Ranged = true`), wings snap open 35 deg; Cast = rise 0.6, wings spread 50 deg; Hurt = squash + flinch back 0.3, lids shut; Ko = tumble 90 deg roll; Victory = hop 1.2 + 360 deg spin; IdleBattle = 0.05 breathing, ear / head glance every 2-4 s.

---

### Task 6: `AttackFx` engine (client)

**Files:**
- Create: `src/client/Controllers/AttackFx.lua`
- Create: `tools/smoke_p7vfx_client.lua` (scenario `client_p7vfx_engine`)
- Modify: `tools/smoke.py`, `tools/contract.json`

**Interfaces:**
- Consumes: `AttackFxCatalog.Resolve`, `AttackFxCatalog.Unit` (Task 4), `PetPoses` (Task 5), `TextureIds` / `MeshLibrary.IsReady` + `MeshLibrary.Assemble` (cores), `GraphicsQuality.Effective()`.
- Produces:
  - `AttackFx.Play(ctx) -> bool` (false = not played: the caller uses the cube `Fx.*`), `ctx = { Attack, Kind, Shape, From = { Unit, Model, Pos }, To = { Unit, Model, Pos } | { list }, Element, Rarity, Stage, PetId, Mine, Crit, Strong, Miss, DueAt, Angle, Radius, Length }`
  - `AttackFx.Pose(unitId) -> { Name, P, Ranged } | nil` (the pose a battle unit should show now)
  - `AttackFx.Cancel(unitId)`, `AttackFx.ClearAll()`, `AttackFx.SetQuality("Low"|"High")`, `AttackFx.Stats() -> { Live, Emitters, Beams, Trails, Lights, Cores, Pooled }`
  - Limits: `MAX_LIVE 10` full effects; over it, the effect steps down one band, then `Play` returns false; emitters per effect <= 6 (High) / 2 (Low); Low = no Beams / Trails / bloom.

- [ ] **Step 1: Write the failing scenario `client_p7vfx_engine`**

Assertions:
- For every element: `Play` Melee / Ranged / Special(Blast) / Element(Cone) returns true at High and the effect is gone after its beats.
- `Stats` never passes the limits during 40 simultaneous plays, and `Play` returns false once over.
- After 200 sequential plays, the instance count under the effects folder equals the pool keep size (no leaks).
- Review Focus 1: `From.Model = nil` and a `To` unit destroyed mid-travel -> no error, the effect ends at the last known point.
- Review Focus 3: two `Play` calls on the same unit 0.05 s apart -> `Pose(unitId)` reflects only the second.
- Review Focus 5: `SetQuality("Low")` while 5 effects are live -> within one `Update`, no live Beam / Trail remains and new plays use <= 2 emitters.
- A texture key missing from `TextureIds` -> `Play` returns false (the caller falls back).
- `Mine = false` -> no camera change.

- [ ] **Step 2: Run to see it fail**, **Step 3: Implement**, **Step 4: Run to see it pass** (`py -3.12 tools/smoke.py --only client_p7vfx_engine`), **Step 5: Commit**.

Implementation notes: pooled per-kind kits under `workspace.ClientBattle.AttackFx` (Attachments + ParticleEmitters with `FlipbookLayout = Grid4x4`, Beams, Trails, PointLights, the core MeshPart from `MeshLibrary.Assemble` tinted and tweened); one `Update(now)` called from BattleController's existing step (no new RenderStepped); camera punch through BattleController's `Me.ShakeScale` path (cap `SHAKE_MAX 0.35`).

---

### Task 7: BattleController integration and the `/fx` dev command

**Files:**
- Modify: `src/client/Controllers/BattleController.lua` (Handlers `EV.Hit` 2601, `EV.Special` 2699, `EV.Zone` 2773, `EV.KO` 2795, `EV.Element` 2880, `EV.Buff` 2919, `EV.Swap` 2934, `EV.Windup` 2950, `EV.End` 2869, `EV.Leave` 2856; the lunge in `Units.Update` 1661-1669 and `Me.Draw` 2136-2143; the root write 1700-1711; `GetStats` 6984)
- Modify: `src/server/Services/DevService.lua` (command `"fx"` in `DevService.Commands` and the handler table), `src/client/Controllers/DevPetShow.lua` (action `"Fx"`)
- Modify: `tools/smoke_p7vfx_client.lua` (scenario `client_p7vfx_battle`), `tools/smoke_dev.lua` (fx command), `tools/smoke.py`

**Interfaces:**
- Consumes: `AttackFx.*` (Task 6), `AttackFxCatalog.Unit` (Task 4).
- Produces: `/fx <element> <attack> [kind|shape] [rarity] [stage]` -> `DevPetShow("Fx", { Element, Attack, Kind, Shape, Rarity, Stage })`: the client builds a caster pet and a dummy target 10 studs apart in front of the developer and plays it (`/clearpets` removes them). `BattleController.GetStats()` gains `AttackFx = AttackFx.Stats()`.

- [ ] **Step 1: Write the failing tests**

`client_p7vfx_battle`: replay a recorded raid's event stream (the existing replay helpers of `smoke_p5_battleclient.lua`): every Hit / Special / Element / KO handler calls `AttackFx.Play` once with the unit's element and rarity; when `Play` returns false the old `Fx.*` call still runs; Review Focus 4: an `End` (and a `Leave`) event mid-effect leaves `AttackFx.Stats().Live == 0` and the pools at keep size. `smoke_dev`: `/fx Flame Ranged Epic` is allowed for developers, refused for others, and rejects an unknown element / attack with a "bad" toast.

- [ ] **Step 2: Run to see them fail**, **Step 3: Implement**, **Step 4: Run them plus the guard tests**

Run: `py -3.12 tools/smoke.py --only client_p7vfx_battle,<the scenarios of tools/smoke_dev.lua, smoke_p3_battleclient.lua, smoke_p3_visual.lua, smoke_dgfix_client.lua, smoke_p5_battleclient.lua, smoke_p6_evofx.lua>` (exact names: `py -3.12 tools/smoke.py --list`)
Expected: all PASS, including "no predicted lunge on a press", "DODGED! on a miss", `FxParts <= 260`, `Numbers <= 26`, `Flashes <= 8`.

- [ ] **Step 5: Commit**

---

### Task 8: Flame end to end (+ PLAYER CHECK-IN 2)

**Files:**
- Modify: `src/shared/AttackFxCatalog.lua` (Flame recipes tuned; the generic recipes of the other elements stay placeholders until Task 9)

- [ ] **Step 1: Studio verification**

In a playtest: `/fx Flame Melee <rarity>`, `/fx Flame Ranged <rarity>`, `/fx Flame Element Cone|Circle|Line <rarity>`, `/fx Flame Special Blast|Pounce|Storm <rarity>` for one rarity per band (Common, Rare, Legendary, Secret) and stage 0 / 2. Screenshot each from the front and the side (HUD hidden), check against the spec (the 5 beats, band look, 1.4x cap, embers swirling up), and run one real Duel and one Raid to see it in play.

- [ ] **Step 2: Gemini review**

`ask-gemini` (model `gemini-pro-latest`) with the screenshots: the spec's creative bar; adopt what holds up and note disagreements.

- [ ] **Step 3: PLAYER CHECK-IN 2**

Show the player the Flame set in Studio. Do not start Task 9 before their OK; apply their notes to the shared engine first.

- [ ] **Step 4: Commit**

---

### Task 9: The other 7 elements (normal + element attacks)

**Files:**
- Modify: `src/shared/AttackFxCatalog.lua`

- [ ] **Step 1:** One element at a time (Water, Frost, Nature, Earth, Storm, Celestial, Shadow): recipes per the spec table including its "alive" detail; `p7vfx_catalog` stays green.
- [ ] **Step 2:** Studio screenshots per element (Melee, Ranged, 3 shapes; Common and Secret); Nature checked on the green arena floor; Gemini review.
- [ ] **Step 3:** Commit per element.

---

### Task 10: The 9 special kinds for every element

**Files:**
- Modify: `src/shared/AttackFxCatalog.lua`

- [ ] **Step 1:** Blast, Beam, Pounce, Storm, Freeze, Heal, Shield, Rally, Haste per the spec table, retextured per element.
- [ ] **Step 2:** Studio check of each kind on its real catalog pets (the 33-pet table in the spec) via `/fx` and one Raid; Shield / Heal / Rally / Haste on 4 allies; Gemini review.
- [ ] **Step 3:** Commit.

---

### Task 11: The 12 signature specials

**Files:**
- Modify: `src/shared/AttackFxCatalog.lua` (`Signatures`)

- [ ] **Step 1:** Each signature per the spec table with its `vfx_sig_*` core: Ember Phoenix, Sunbeam Bear, Twilight Dragon, Cloudy Dragon, Starlight Unicorn, Stormfang, Eclipse Dragon (the brief battle dim is a local Lighting tween, own pet only), Obsidian Phoenix, Phantom Kitsune, Magma Cub, Rime Wyrmling, Hydralotl.
- [ ] **Step 2:** Studio check per pet (`/pet <name>` in a Duel, or `/fx` with the pet id); Gemini review.
- [ ] **Step 3:** Commit.

---

### Task 12: Performance, full gate, ship

**Files:**
- Modify: `BUILD_STATE.md` (a "Pet attack VFX" section), `play/NimbusClimb.rbxlx` (rebuilt)

- [ ] **Step 1: Stress test**

A 16-fighter raid in Studio (dev `/raid` with filler fighters) at High and Low, plus the device emulator at a phone preset: `BattleController.GetStats().AttackFx` within limits, frame time captured with the micro profiler; the cube fallback engages under overload.

- [ ] **Step 2: Full gate**

Run: `node tools/check.mjs` and `bash tools/run_checks.sh --quick`
Expected: 0 errors; no new smoke failures vs the Task 0 baseline.

- [ ] **Step 3: Rebuild and verify the place**

Run: `"%LOCALAPPDATA%/NimbusClimb/rojo-7.7.1/rojo.exe" build default.project.json -o play/NimbusClimb.rbxlx` then `py -3.12 tools/verify_place.py`
Expected: `verify_place` OK.

- [ ] **Step 4: Fable review of the whole change**, fix confirmed findings, then commit, push, and show the player the final set.
