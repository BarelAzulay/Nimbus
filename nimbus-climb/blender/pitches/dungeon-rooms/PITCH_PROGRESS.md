# Dungeon rooms pitch (bug #5): progress (2026-10-27)

The player's words: "all dungeon rooms need a blender big improve by texture, estetic and quality, use gemini
creativity". The screenshot (`today.png`) is the Throne boss room on floor 1 (Mossy Cellar). It shows:
- flat lilac brick walls;
- plain sandstone pillars and arches with two diagonal "ArchStone" blocks;
- a magenta carpet with lime Neon edge lines;
- green banners, one with a torch flame poking through it;
- a sandstone floor with twig-like cracks;
- the far arch reading navy-black.

## What exists today (why every room looks the same)
- All rooms are built by `src/server/Services/DungeonBuilder.lua`:
  - `Rooms.Hall` :868, `Cellar` :935, `Cave` :991, `Bridge` :1066, `Throne` :1125, `Entrance` :1197,
    `Corridor` :1232, `Treasure` :1282;
  - one palette `C` (:118-140): lilac stone, sandstone flagstones, magenta carpet.
- The 12 floors (`BattleCatalog.DungeonFloors`, `src/shared/BattleCatalog.lua:1607-1620`) only change:
  - which room kind is used;
  - the colour of the `Accent` parts (banners, runes, rug inlay, shield crest), through `elementColor` :1501 and
    `recolourAccents` :1592.
  So "Frozen Crypt" and "Mossy Cellar" share the same walls and floor.
- Blender keys exist only for walls, floors, pillars, the torch, the door frame, the crate, the chest, rocks, cracks and
  stalagmites (`blender/catalog/arenadungeon.json`, `blender/kit/props/arena.py` re-voxels the Part build). Every
  other visible piece is still a plain Part (throne, dais, arches, statues, braziers, banners, carpet, barrels, tables,
  hay, cauldron, chandelier, hearth).
- The "texture" ask fits the SmoothPlastic rule (ABSOLUTE_RULES: no Roblox textured materials). The texture is baked
  per-voxel colour inside the meshes: mortar gaps, chips, moss, soot and frost. No new rule decision is needed.

## Bugs found (these ship regardless of the vote; no vote needed)
1. **A banner hangs over a torch in the boss room.**
   - Banners sit at z -10 and 6 (`DungeonBuilder.lua:1169-1170`).
   - `roomShell` puts 4 side torches on a 72-deep room at z -27, -9, 9 and 27 (:847-851).
   - So the torch at z -9 sits inside the banner's span (z -11.8 to -8.2). The screenshot shows the flame on the
     green cloth, and the close-up in `today_render.png` shows it too.
   - Fix: hang the banners at z 0 and 18 (between torches).
2. **Wall props float off the walls.**
   - Callers mount them 0.5-0.6 stud in front of the wall face:
     - Hall banners :885-886 and shield :888 at z 23.4 (face at 24);
     - Throne banners at x 29.4 (face at 30) and shield :1165;
     - torches :850-854 at `hw - 0.5`.
   - `Kit.banner` (:581-584) adds -0.45/-0.5 more, so the cloth hangs about 0.93 stud off the wall with no bracket.
     `Kit.shield` (:685-690) hangs about 0.75 off.
   - Fix: mount on the face (cloth and pole about 0.3 out, clear of the 0.11-stud Course strips) and model a bracket.
     The torch mesh moves with its mount, so it needs no re-bake.
3. **Art-rule gap.** These are still plain Parts:
   - the throne, dais and stairs (:1143-1154);
   - `Kit.arch` lintel, ArchStones and keystone (:591-598);
   - the statue (:694-702) and brazier (:609-622);
   - the banner, shield, carpet, barrel, table, hay, cauldron, wine rack, chandelier and hearth.

   Each one gets a key in the chosen style, with the Part build kept as the collider and fallback, as the walls
   already are.
4. **Cellar clutter in the boss room.** The hay, barrel, crate, table, puddles and moss square (:1174-1182) go. Each
   option replaces them with throne-room props.

## Directions (Gemini, gemini-pro-latest, then pushback)
- Note: the `brainstorm` tool returned an empty greeting. Both rounds went through `ask-gemini` with the brief in a
  file (`@file`).
- Round 1, Gemini's three directions:
  - the Aviator's Archive: weather machinery, copper and brass, an astrolabe throne;
  - the Star-Seed Nursery: overgrown celestial plants, a stump throne;
  - the Ballast Prisons: a crashed sky prison with inmate factions.
  - Gemini's first pick was the Nursery, and it predicted Claude would pick the Archive.
- Round 2, Claude's pushback:
  - Dropped the prison: a shank, "dried blood red" and tribal inmates are too grim for a cute pet game, and its
    palette was the muddiest.
  - Added **A, a castle done properly**: the player may like the castle and only dislike how cheap it looks.
  - Made the Archive concrete as **B**: no guano, no wall of gears.
  - Made the Nursery concrete as **C**: built masonry that roots are taking over, with plants on walls only, because
    "planted, not built" cannot make a wall kit.
  - Gemini agreed with all of this and added the "do nots": A must not have perfect 90-degree blocks; B must not
    cover walls in spinning gears; C needs volume vines, not flat decals.
- Gemini's small details, kept:
  - A: the toy sword, and the crooked banner nails;
  - B: the clipboard on a pipe, the wrench by the valve, and the sooty handprints;
  - C: the shears in a hedge knight, the cracked spilled pot, and the patched watering can.
- Gemini's palettes were adjusted by Claude: grey floors and pure Neon cyan would read black or harsh under the
  dungeon's violet ambient. Final palettes are in `pitch.json`.
- **Picks:**
  - Gemini's final pick is **B** (the most original, the most "sky world"). Gemini also said the player will
    "likely prefer A".
  - Claude picks **A**. Claude leaned B during the discussion, then switched after the renders and the code check:
    - A fixes exactly what the player named (texture, look, quality);
    - it fits all 5 existing room kinds and the floor names (Cellar, Crypt, Halls, Keep, Throne) with no new gameplay
      props;
    - it is the lightest of the three (mock-up 86k tris vs 126k for B and 222k for C).
  - B would turn Cave and Bridge rooms into machine rooms, which is a bigger rebuild.

## Files
- Run: `%USERPROFILE%\.bpyenv\Scripts\python.exe -I dungeon_pitch.py <out_dir> [--res 100] [--samples 32]
  [--only today,a,b,c] [--shots main,close,themes] [--no-composite]`. One process, about 40 s at full size, EEVEE,
  32 samples.
- Everything is written in Roblox coordinates and mapped to Blender. All four styles build the same Throne layout
  (Lua positions); the ceiling is left off so the camera can look in.
- `today.png`: the bug screenshot.
- `today_render.png`: today's Throne rebuilt from the Lua numbers at Part level, with a lilac brick pass standing in
  for the baked wall mesh. Its close-up shows bug 1.
- `option_a/b/c.png`: each image has three parts:
  - the boss room from above the entrance arch (1280 x 800);
  - a wall close-up with the 5.3-stud R15 player;
  - one wall module dressed for Mossy Cellar, Frozen Crypt and Ember Forge.
- `lineup.png`: today, A, B and C from the same camera.
- Checked in the renders:
  - no floating banners (all on brackets);
  - bulbs hang from roots, rib tips or the arch on cords that reach;
  - the theme rows are in label order (+X is screen-left for a camera looking +Z);
  - the player stands about 5.3 studs tall next to 8-stud doors and 15-stud walls.
- Not modelled: the A "Flooded Vaults" water lines (described only). The B astrolabe rings are static in the render
  (they would turn slowly in game).
- Housekeeping: the first test run wrote renders to `C:\t1` (a relative render path, fixed with `abspath`).
  Deleting that folder was blocked by the safety check, so the user needs to remove it.

## Next (after the player's choice)
1. Ship fixes 1, 2 and 4 in `DungeonBuilder.lua` (positions only), with a Studio check of Hall_1-3 and Throne_1.
2. For the chosen look:
   - re-bake the wall, floor, pillar and door keys in `blender/kit/props/arena_style.py` with the new palette and
     detail pass;
   - add the prop keys (throne, arch, statue, brazier, banner, carpet, window/astrolabe/stump) to `arenadungeon.json`;
   - add a per-floor "weathering" variant (moss / frost / ember / water) as a tint or detail set chosen from
     `floorDef(...).Element`.
3. Upload the keys (keyed cloud session), then check each room template in Studio: scale, collisions, lighting, and
   the fight floor kept clear.
