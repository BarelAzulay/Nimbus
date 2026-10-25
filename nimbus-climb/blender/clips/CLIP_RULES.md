# Nimbus Climb cinematic clip: rules (locked 2026-10-25)

Mandatory for every clip script in `blender/clips/` and every render in `play/clips/`. Read with
`ABSOLUTE_RULES.md` and `brain.md` before clip work.

## 1. Protect existing game files (read-only core)
- Never modify anything in `src/`, `blender/build_all.py` or `tools/render_model.py`. Clip code may **import** them
  (and `blender/kit/`), never edit them.
- New animation scripts go in `blender/clips/`. Rendered previews and videos go in `play/clips/`.
- `tools/run_checks.sh` must stay 100 % green. Clip scripts must not write to `src/shared/MeshManifests/`,
  `blender/meshes.json` or `blender/out/` (so: never call `build_all.main()` or `write_index()`; call the builders
  directly and keep the results in memory).

## 2. Zero primitive placeholders (real game meshes only)
- No generic cubes, spheres or cylinders as stand-ins for pets, bosses, gates, coins or stations.
- Every subject is built through the real `blender/` builder path so every voxel and colour matches the game.
  The catalog keys are in the key map below.
- Effects (rune rings, light pillars, sparks, fog, glow) are effects, not stand-ins. They follow the shapes and
  timings of `EvolutionFx.lua` and `PortalVortex` / `PortalFx`.

## 3. Anti-robotic animation and curves
- No `LINEAR` keyframes on character or pet motion. Use `BEZIER` interpolation with `AUTO_CLAMPED` handles.
- Every move has anticipation (a crouch before a leap) and an overshoot and settle on landing. Use `PetPoses.lua` as
  the reference: Windup crouches 0.25 studs; Strike lunges 1.5 studs with out-back easing and wings at 35° that
  overshoot to ~38°, then settle.
- Every pet has continuous secondary motion on every frame:
  - a gentle sine bob,
  - pitch and roll tilted into the direction of velocity,
  - spinning `Aura` rings (stage 1) and `Aura` + `Halo` crown (stage 2) on evolved forms.
- No finger or facial acting on the Roblox Climber. Frame it from heroic back or three-quarter angles. The voxel
  pets, glowing vortexes, rune pillars and sweeping camera moves carry the close-ups.

## 4. Cinematic camera, lighting and materials ("Fugitive" style)
- Every shot uses an 85 mm lens (close-up / medium) or a 35 mm lens (wide action).
- Every camera has a `TRACK_TO` constraint to a smoothly animated `CameraTarget` Empty.
- Depth of field is on, at f/1.8 to f/2.8. Action shots get subtle procedural handheld noise (Noise F-modifier, low
  strength).
- The environment is a dark twilight built from `branding/sky/` (Skybox Bk/Dn/Ft/Lf/Rt/Up), with volumetric fog
  (Principled Volume, density 0.01 to 0.015).
- Three-point lighting: a warm lantern key light, a cool purple fill light, and a bright cyan or gold rim light.
- Stone floors have roughness 0.15, so neon portals, rune rings and crystals cast crisp reflections on the ground.

## 5. Mandatory visual self-critique loop
- Never run the full 900-frame render blind.
- Always run `--preview` first. It renders keyframe PNGs for each act to `play/clips/preview/`.
- Open every PNG with the Read tool and check it for:
  - (a) the camera clipping through walls or floors,
  - (b) a subject out of frame or facing the wrong way,
  - (c) a frame that is too dark or blown out,
  - (d) missing pet parts.
- When a frame has a flaw, fix the camera or light coordinates and render the preview again. Repeat until every
  frame looks like a polished trailer shot. Only then render the full clip.

## 6. Single continuous output
- Rigs persist across acts (one scene, the same pet and camera rigs).
- ffmpeg stitches the acts automatically, with a 0.25 s crossfade or a clean cut, into one playable MP4:
  `play/clips/nimbus_story_clip.mp4`.

---

## Builder reference (what the clip imports, found 2026-10-25)

**Python:** `%USERPROFILE%\.bpyenv\Scripts\python.exe` (Python 3.13, bpy **5.2.2 LTS**). Put `blender/` and
`blender/kit/` on `sys.path`, the way `build_all.py` does.

### The Blender path (real game meshes)
- `build_all.load_catalogs()` loads the catalog entries from `blender/catalog/<class>.json`.
- `build_all.Builder(export=False).make(entry, k)` builds one key and returns an `nvox.build.ModelSpec`. It routes by
  type:
  - `pet` / `wing` / `acc` go to `petkit.build_pet_body` / `build_pet_wing` / `build_pet_accessory`, through
    `bridge.Bridge` (the game's `PetBuilder._Blueprint` running in lupa) and `RecipeFitter` (the game's colours);
  - `boss` goes to `bosskit.build_boss_joint`;
  - `prop` goes to `props.load_all()[name](entry, props.PropKit())`.
- `Builder.build(entry, budget)` is the same, plus the budget and K steps.
- `nvox.blend.make_objects(model, look, collection, matrix, export=False)` turns a `ModelSpec` into Blender mesh
  objects, one per MeshPart, with preview materials in the look's colours. `reset_scene`, `setup_render` and
  `render_views` are helpers we can reuse or replace with the clip's own cameras.
- The registered prop builders are:
  - gates: `gate`;
  - the Storm Altar: `altar_island`, `lobby_cloud`;
  - lobby: `lobby_tree`, `lobby_lamp`, `lobby_bench`, `lobby_flowerbed`, `lobby_fountain`, `lobby_welcome_arch`,
    `lobby_obelisk`, `lobby_banner`, `lobby_board`, `lobby_roulette`, `lobby_stall`, `lobby_token_statue`,
    `lobby_shop_arch`, `lobby_pond`, `lobby_plot`, `lobby_boxes`;
  - home: `home_station`, `home_element`;
  - arena: `ad_baked`;
  - dungeon: `ad_rock`, `ad_crack`, `ad_stalagmite`;
  - creatures and tokens: `boss_joint`, `dragon_piece`, `dragon_link`, `npc_pedestal`, `token`, `fx`, `star`;
  - VFX: `vfx_cores`;
  - reference shapes: `p4_portal`, `cloud_platform`.

### `tools/render_model.py` (not Blender: a numpy and Pillow rasteriser)
- It runs `tools/dump_model.lua` in lupa: `LuaWorld(context).dump(target)` and
  `dump_target(target, box, json_out, ...)` return every BasePart (CFrame, Size, Color, Material). `merge_models` and
  `expand_mesh_parts` / `_mesh_tris` turn mesh keys into triangles. `Geometry`, `render_view` and `render_sheet`
  draw them.
- Targets include `pet:<id>`, `meshkey:<key>[:<petId>]`, `meshpet:<petId>`, `meshevo:<petId>:<1|2>`, `gates`,
  `gate:<..>`, `storm-altar`, `arena`, `home*`, `boss(es)`, `token[:golden]`, `skydragon` and `dungeon:*`.
- Clip use: reference only. Its JSON dumps give **world layout** (where the gates, altar and stations stand in the
  live build) for placing the Blender meshes. Its PNGs are a ground-truth check that our meshes match the game.

### Animation references in `src/` (read-only)
- `src/shared/PetPoses.lua`: `PetPoses.Sample(name, p, ranged)` returns `{Body, Groups{wing,cloud,tail,bob,orbit},
  Lids, Still}` for `Windup`, `Strike`, `Shoot`, `Recoil`, `Cast`, `Hurt`, `Ko`, `Victory` and `IdleBattle`.
  The easing helpers are `smooth`, `outCubic`, `outBack`, `settle` and `plateau`. The clip ports these curves into
  Bezier keys.
- `src/client/Controllers/EvolutionFx.lua`: `Play(from, to, pose, opts)` and `Arrive(pivot, opts)`. Its timings
  `K` are:
  - charge 2.0 s (stage 1) / 2.6 s (stage 2), burst 0.38 s, reveal 1.35 s, settle 0.6 s;
  - the pet rises 28 % of its height and spins up to 4.5 turns/s, then spins down through 2 reveal turns;
  - rune rings have 20 runes (stage 1) or 28 (stage 2, two counter-rotating rings); motes 18 / 28, sparks 22 / 34;
  - the light pillar is 9 / 12 pet heights, at most 60 studs;
  - 26 confetti bits in 6 colours.

### Key map for the clip subjects
| Subject | Catalog keys |
|---|---|
| Cloudy Dragon | `pets`: the body and wings for `cloudy_dragon`; `evo1_cloudy_dragon` + `evowing_cloudy_dragon_1_L/R`; `evo2_cloudy_dragon` + `evowing_cloudy_dragon_2_L/R`, `_2b_L/R` |
| Stormfang | `pet_stormfang`; `evo1_stormfang` + `evowing_stormfang_1_L/R`; `evo2_stormfang` + `evowing_stormfang_2_L/R`, `_2b_L/R` |
| Coach Corgi | `pet_dog_corgi` (the `waffle_corgi` pet); `evo1_waffle_corgi` + `evowing_waffle_corgi_1_L/R`. No stage 2: it is a Common pet |
| Shadow Hydra | the boss `boss_shadow_hydra_Body`, `_Head1`, `_Head2`, `_Head3` (one key per joint). Bosses have no evolved stages |
| Gate hoops | `gate_obby`, `gate_dungeon`, `gate_ring`, `gate_arena`, `gate_altar`, `gate_home` |
| Coins | `token_cash` (Cloud Cash), `token_goldencash` (Lucky coin), `token_cloud`, `token_golden` |
| Storm Altar | `cloud_altar`, `prop_altar_ring`, `prop_altar_portal`, `prop_altar_crystals`, `prop_altar_sign`, `floor_altar_bridge` |
| Pet Garden | `home_garden_1` .. `home_garden_8` (one key per level) |
| Food Machine | `home_foodmachine_1` .. `home_foodmachine_5` |
| Battle Arena | `arena_island`, `arena_floor`, `arena_forum`, `arena_seg_stand`, `arena_seg_gate`, `arena_seg_bossgate`, `arena_pillar`, `arena_ring_1/2`, `arena_torch`, `arena_lantern`, `arena_board_*`, `arena_bridge` ... |

### Gaps to settle before the script (open questions)
1. **Roblox Climber:** there is no avatar model in `blender/` yet. It needs a new hand-built Blender model in
   `blender/clips/` (a blocky Roblox-style climber).
2. **ffmpeg** is not installed on this PC. Options: `winget install Gyan.FFmpeg`, or `imageio-ffmpeg` in the bpy
   venv.
3. **Git:** should `play/clips/*.mp4` and the PNG previews be committed, or ignored?
