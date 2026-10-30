# Living Sky Cycle + Raid Skies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One server-synced 20-minute sky loop (Dawn 2, Day 6, Sunset 9, Night 3 min) with the player's painted skyboxes, plus a server-wide event sky while each raid boss is up, all applied on the client as the moving base of LightingStack.

**Architecture:** A pure shared module (`SkyCycle`) turns server time into a phase, a blend and a full lighting preset. The server only publishes four Workspace attributes (epoch, speed, offset, event). A client `SkyController` re-applies every 2 s through a new `LightingStack.SetBase`, so the Dungeon / GfxLow / AttackFxDim presets keep winning on top. Skybox faces come from `TextureIds` keys `sky_<theme>_<Face>`; until the owner's keyed session uploads them, a missing theme keeps today's look (Fallback sky, cycle light only).

**Tech Stack:** Luau (plain Lua 5.1-compatible syntax), Rojo, tools/smoke.py + tools/robloxmock.lua smoke scenarios, node tools/check.mjs, Blender 5.2 (faces only, already rendered).

**Spec:** `nimbus-climb/docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md` (read it whole; "Builder check: settled" and "The player's sky picks" are binding).

## Global Constraints

- Plain Lua 5.1-compatible syntax; the project's module layout (server Services, client Controllers, shared modules).
- The server writes Lighting only at boot (LightingService). Every later change is client side through LightingStack.
- No per-frame code for the sky: a 2 s refresh with a ~2 s tween. No remote traffic for the clock (attributes only).
- Lengths: Dawn 120 s, Day 360 s, Sunset 540 s, Night 180 s (loop 1200 s); each phase blends into the next over its last 75 s.
- Themes: Day `day_vivid`, Dawn + Sunset `dusk_amber`, Night `night_aurora`; raids `storm_titan` -> `storm_teal`, `lava_golem` -> `lava_obsidian`, `frost_wyrm` -> `frost_glacial`, `shadow_hydra` -> `shadow_eclipse` (check the four boss ids against `BattleCatalog.Bosses`).
- Raid sky: server-wide, blends in over 3 s on raid start, back to the cycle over 3 s on raid end.
- ClockTime never tweens across 24 -> 0; Sunset ClockTime stays in 16-17; StarCount and other integers are set at once.
- Colour by world light, not screen tint: ColorCorrection TintColor stays within ~8 of white per channel in every phase (Amber Burn shows 11 of 20 minutes).
- Readability floor: in every phase and event, Brightness >= 1.0 and every channel of OutdoorAmbient >= 70 (night is indigo, never black).
- Fireflies off on Low graphics. Every new tunable lives in `Config.Sky`.
- Commit after every task; push the branch `sky-skies` at the end of each task.

## Review Focus

1. A late joiner or a player who rejoins mid-blend: the first apply is instant and lands on the same values a long-running client shows (Task 1 test `sky_join_matches`).
2. Entering / leaving a dungeon while a cycle refresh runs: no visible restart of the Dungeon fade, and leaving at night restores NIGHT values, not boot values (Task 2 tests `stack_setbase_under_preset`, `stack_busy_skips`).
3. Faces half-uploaded (some of a theme's six keys in TextureIds, some not): that theme counts as missing, no grey face ever shows (Task 3 test `skyfaces_partial`).
4. A raid that ends by Wipe / Error / server shutdown, or two raids back to back: SkyEvent always clears; a stale event never sticks (Task 4 test `skysvc_raid_end_reasons`).
5. Dev `/sky speed 0` or a negative / huge speed and junk phase names: refused or clamped, never NaN in Lighting (Task 1 `sky_bad_inputs`, Task 4 `skysvc_dev_refuses`).

---

### Task 1: SkyCycle, the pure phase math and looks

**Files:**
- Create: `src/shared/SkyCycle.lua`
- Modify: `src/shared/Config.lua` (`Config.Sky`, keep `Faces`)
- Create: `tools/smoke_sky.lua`; register in `tools/smoke.py` the same way `smoke_wave6.lua` is (pure scenarios, server + client files)

**Interfaces:**
- Produces:
  - `Config.Sky.Cycle = { Order = {"Dawn","Day","Sunset","Night"}, Seconds = {Dawn=120,Day=360,Sunset=540,Night=180}, Blend = 75, Refresh = 2, Tween = 2, EventBlend = 3 }`
  - `Config.Sky.Themes = { Dawn="dusk_amber", Day="day_vivid", Sunset="dusk_amber", Night="night_aurora" }`, `Config.Sky.RaidThemes = { storm_titan="storm_teal", ... }`
  - `Config.Sky.Looks[phaseOrBossId] = { Lighting={...}, Atmosphere={...}, Clouds={...}, ColorCorrection={...}, Sky={StarCount=...} , Clock = {from, to} }` (Clock = the ClockTime range walked through during the phase; event looks have a fixed Clock)
  - `Config.Sky.Floor = { Brightness = 1.0, OutdoorAmbientMin = 70 }`
  - `SkyCycle.At(serverNow, epoch, speed, offset) -> { Phase, Next, T (0..1 through the phase), Blend (0..1 toward Next), LoopT }`
  - `SkyCycle.Preset(at, eventId, eventBlend) -> preset` (LightingStack groups; Sky group carries `StarCount` and the six `Skybox*` strings when faces are known: see Task 3's `SkyFaces.For`, passed in as `facesFor` param) — exact signature: `SkyCycle.Preset(at, eventId, eventBlend, facesFor) -> preset, themeId`
  - `SkyCycle.Floor(preset) -> preset` (clamps to the readability floor; Preset already calls it)

- [ ] **Step 1: Write the failing tests** in `tools/smoke_sky.lua`:
  - `sky_phase_math`: with epoch 0, speed 1, offset 0: t=0 -> Dawn T=0; t=119 -> Dawn, Blend > 0.95; t=120 -> Day; t=1199 -> Night; t=1200 -> Dawn (wrap); t=-5 (clock skew) -> Night near its end, no error.
  - `sky_blend_window`: Blend is 0 until 75 s before a phase ends, then rises monotonically to 1.
  - `sky_clock_no_wrap`: sample every 1 s over a loop: within one phase ClockTime is monotonic and never crosses 24 -> 0; Sunset ClockTime stays in [16, 17].
  - `sky_floor`: every phase and every raid look after Preset: Brightness >= 1.0, each OutdoorAmbient channel >= 70/255; TintColor within 8/255 of white.
  - `sky_join_matches`: Preset at t computed fresh equals Preset at t computed after walking 0..t in 2 s steps (no hidden state).
  - `sky_bad_inputs`: speed 0 / negative / NaN / 1e9 and a nil epoch give a valid phase (speed clamped to [0.1, 120], nil epoch = 0), no NaN anywhere in the preset.
  - `sky_event_blend`: eventBlend 1 returns the raid look's values; 0.5 is the midpoint for numbers and Color3; the returned themeId switches to the raid theme exactly when eventBlend >= 0.5 (skybox swap at mid-blend).
- [ ] **Step 2: Run** `py -3.12 tools/smoke.py --only sky_phase_math,sky_blend_window,sky_clock_no_wrap,sky_floor,sky_join_matches,sky_bad_inputs,sky_event_blend` -> FAIL (module missing).
- [ ] **Step 3: Implement** `SkyCycle` and the Config tables. Looks: start from LightingService `p4Light()` / Custom look for Day; Dawn pastel; Sunset amber via ColorShift_Top/Ambient/Atmosphere Color+Decay and cloud colour (sun height from the 16-17 ClockTime); Night indigo ambient, StarCount 3000, Clouds Cover low and thin violet. Raid looks: teal storm, dark soot + orange decay, icy cyan, violet-grey eclipse; all passed through Floor. Numbers interpolate (lerp numbers, Color3:Lerp); strings / integers / booleans switch at Blend >= 0.5. The skybox theme for a phase = `Config.Sky.Themes[phase]`, for an event = `RaidThemes[eventId]`; the swap happens at Blend 0.5 of every phase change whose theme differs (Dawn->Day, Day->Sunset, Sunset->Night, Night->Dawn; Sunset and Dawn share dusk_amber).
- [ ] **Step 4: Run** the same command -> all PASS. Also `node tools/check.mjs` -> no new findings.
- [ ] **Step 5: Commit** `feat(sky): SkyCycle phase math, looks and readability floor` and push.

### Task 2: LightingStack moving base

**Files:**
- Modify: `src/client/LightingStack.lua` (header comment: the base now moves; SkyController is the only base writer)
- Test: `tools/smoke_sky.lua`

**Interfaces:**
- Produces: `LightingStack.SetBase(preset, seconds)` (overwrites base values for every group.prop it names, snapshotting unseen props first, then re-applies; presets above keep winning), `LightingStack.Busy() -> boolean` (a tween started by Push / Pop is still running).

- [ ] **Step 1: Failing tests:**
  - `stack_setbase_under_preset`: Push("Dungeon", {Lighting={Brightness=0.5}}); SetBase({Lighting={Brightness=1.4, ClockTime=21}}); Brightness stays 0.5, ClockTime becomes 21; Pop("Dungeon") -> Brightness 1.4 (not the boot value).
  - `stack_setbase_value`: `LightingStack.Value("Lighting","Brightness","Dungeon")` returns the new base after SetBase.
  - `stack_busy_skips`: after Push with seconds 1.5, Busy() is true until the tween completes (mock TweenService completion), then false; SetBase never cancels that running tween while Busy (it only updates base values; the next apply after the fade uses them).
- [ ] **Step 2: Run** `py -3.12 tools/smoke.py --only stack_setbase_under_preset,stack_setbase_value,stack_busy_skips` -> FAIL.
- [ ] **Step 3: Implement.** Track which tweens came from Push / Pop for Busy(). SetBase while Busy: store values, defer apply (the 2 s refresh will retry).
- [ ] **Step 4: Run** the three plus every existing LightingStack / dungeon / gfx scenario (`py -3.12 tools/smoke.py --only <names grep'd from smoke.py for LightingStack, Dungeon mood, GfxLow, AttackFxDim>`) -> PASS.
- [ ] **Step 5: Commit** `feat(sky): LightingStack.SetBase moving base + Busy` and push.

### Task 3: Sky faces (stub until upload) and the texture manifest

**Files:**
- Create: `src/shared/SkyFaces.lua`
- Create: `blender/sky/build_sky_manifest.py` (copies `.superpowers/sky-final/<theme>/Skybox*.png` to `blender/textures/sky/<theme>/` and adds keys `sky_<theme>_<Face>` to `blender/textures/textures.json`, keeping the file's existing format, CRLF / indent as it is)
- Test: `tools/smoke_sky.lua`

**Interfaces:**
- Produces: `SkyFaces.For(themeId) -> { SkyboxBk="rbxassetid://n", ... six } | nil` (nil unless all six `TextureIds["sky_"..theme.."_"..Face]` are numbers); `SkyFaces.Keys(themeId) -> { "sky_<theme>_Bk", ... }`.

- [ ] **Step 1: Failing tests:** `skyfaces_none` (empty TextureIds -> nil for all 7 themes), `skyfaces_full` (six ids -> six `rbxassetid://` strings), `skyfaces_partial` (five of six -> nil), `skyfaces_preset_fallback` (SkyCycle.Preset with a facesFor returning nil carries no Skybox* keys, so the Sky keeps whatever LightingService set at boot).
- [ ] **Step 2: Run** `py -3.12 tools/smoke.py --only skyfaces_none,skyfaces_full,skyfaces_partial,skyfaces_preset_fallback` -> FAIL.
- [ ] **Step 3: Implement** SkyFaces; run `py -3.12 blender/sky/build_sky_manifest.py` after the 1024 renders exist (7 themes x 6 faces = 42 keys, displayName "NC sky <theme> <Face>").
- [ ] **Step 4: Run** the tests -> PASS; `py -3.12 tools/upload_assets.py --textures --dry-run --only sky_day_vivid_Bk` (or the uploader's real path) prints one Decal request, no network.
- [ ] **Step 5: Commit** `feat(sky): SkyFaces + 42 sky face textures for the keyed upload` (PNGs included) and push.

### Task 4: Server clock + raid event + dev command

**Files:**
- Modify: `src/server/Services/LightingService.lua` (publish attributes at Init) — or create `src/server/Services/SkyService.lua` if the service init order makes EventService / BattleService hooks cleaner; register it like the other services.
- Modify: `src/server/Services/DevService.lua` (`/sky`)
- Test: `tools/smoke_sky.lua`

**Interfaces:**
- Produces Workspace attributes: `SkyEpoch` (number, `Workspace:GetServerTimeNow()` at boot), `SkySpeed` (number, default 1), `SkyOffset` (number seconds, default 0), `SkyEvent` (string boss id or ""), `SkyEventAt` (server time of the last change, for the 3 s blend).
- `/sky dawn|day|sunset|night` (sets SkyOffset so the phase starts now), `/sky speed <x>` (clamped 0.1..120), `/sky raid <bossId>` / `/sky clear` (dev-only event preview), `/sky` alone prints the phase. Add to `/devhelp`.

- [ ] **Step 1: Failing tests:** `skysvc_attrs` (Init sets the four attributes once; Init twice keeps the epoch), `skysvc_raid_start_end` (EventService.EventStarted BossRaid storm_titan -> SkyEvent "storm_titan"; BattleEnded Mode "Raid" -> ""), `skysvc_raid_end_reasons` (Reason BossDown / Wipe / Error all clear; a second raid start replaces the first; a non-Raid BattleEnded never clears), `skysvc_dev_refuses` (`/sky speed 0` -> 0.1, `/sky speed abc` refused with a message, `/sky noon` refused, non-dev player refused).
- [ ] **Step 2: Run** `py -3.12 tools/smoke.py --only skysvc_attrs,skysvc_raid_start_end,skysvc_raid_end_reasons,skysvc_dev_refuses` -> FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** -> PASS, plus the existing raid / dev scenarios (`--only` the raid and dev names from smoke.py) -> PASS.
- [ ] **Step 5: Commit** `feat(sky): server sky clock, raid event sky, /sky dev command` and push.

### Task 5: Client SkyController (cycle, event, battle lift, lamps, fireflies)

**Files:**
- Create: `src/client/Controllers/SkyController.lua`; start it where the other controllers start
- Modify: `src/client/GraphicsQuality.lua` (Clouds Density = min(0.4, `LightingStack.Value("Clouds","Density","GfxLow")`), recomputed on each Low re-push)
- Modify: `src/client/Controllers/DungeonController.lua` (`R.preset`: read `LightingStack.Value("Atmosphere","Density","Dungeon")` instead of caching `R.BaseDensity`)
- Test: `tools/smoke_sky.lua`

**Interfaces:**
- Consumes: `SkyCycle.At/Preset`, `SkyFaces.For`, `LightingStack.SetBase/Busy/Push/Pop/Value`, the Task 4 attributes, `Config.Attr.InBattle`.
- Produces: `SkyController.Start()`, `SkyController.Refresh(now)` (one step; tests drive it), `SkyController.State() -> { Phase, Event, Lift, Lamps, Fireflies }`.

- [ ] **Step 1: Failing tests (client world):**
  - `client_sky_first_instant`: Start() applies with seconds 0 (values equal the Preset at once).
  - `client_sky_refresh`: Refresh every 2 s calls SetBase with Tween 2; skips while `Busy()`; one SkyController loop only (no RenderStepped / Heartbeat connection).
  - `client_sky_event`: SkyEvent set -> event blend reaches 1 after 3 s (SkyEventAt-based, so a late joiner during a raid lands fully on the raid sky); cleared -> back to the cycle over 3 s.
  - `client_sky_battle_lift`: InBattle "B12" at Night -> Push("SkyLift", twilight values, 1.5); InBattle "D3" -> no lift; InBattle cleared -> Pop over 1.5 s.
  - `client_sky_lamps`: parts named LampGlass / LanternLight / StallLight / DomeGlow with a PointLight get Brightness x1.6 at Night and their original value otherwise; written on phase change only.
  - `client_sky_fireflies`: Night + High graphics -> one capped emitter group near meadow trees enabled; Low -> none.
  - `client_gfx_cloud_cap` and `client_dungeon_density_follows`: GfxLow density = min(0.4, cycle value); the dungeon's density adds to the CURRENT cycle density.
- [ ] **Step 2: Run** `py -3.12 tools/smoke.py --only client_sky_first_instant,client_sky_refresh,client_sky_event,client_sky_battle_lift,client_sky_lamps,client_sky_fireflies,client_gfx_cloud_cap,client_dungeon_density_follows` -> FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** -> PASS; then the full quick suite in chunks (`py -3.12 tools/smoke.py --quick`, one heavy job at a time) and `node tools/check.mjs`. Known pre-existing: `p3fixsrv_net16` (6044 vs 6000 B/s) and the final_checks DashFx chunking artifact; anything else failing is this branch's.
- [ ] **Step 5: Commit** `feat(sky): SkyController living cycle, raid skies, battle lift, lamps, fireflies` and push.

### Task 6: Docs + Studio check list

**Files:** `blender/sky/README.md` (final themes, manifest script), `BUILD_STATE.md` (sky decision), `docs/phase6/OWNER_UPLOAD.md` (the 42 sky faces: Decal id -> Image id step applies)

- [ ] **Step 1:** Update the three docs. **Step 2:** Commit `docs(sky): living sky + raid skies` and push.
- [ ] **Step 3 (needs the owner's OK to use Studio):** the spec's "Studio checks after the build" with `/sky speed 20`, a night duel and ring round, a dungeon in and out at sunset and night, `/sky raid <each boss>`, two clients on one phase, and the HUD / rarity colours against Amber Burn. Screenshots to `.superpowers/sky-final/studio/`.
