# Champion Ring emblem + crowd pitch (bug #11): progress (2026-10-27)

Player's words: "ground logo bugged&looks bad, croud needs animation and sound". The screenshot (`today.png`) shows the
Champion Ring pocket. In the centre is a violet disc with a gold "crown" that reads as a giant letter E, with a jagged
edge and white squares at the prong tips. Seven static cloud puffs sit on the stone bleacher, and there is no sound.

## Bugs found (these ship regardless of the vote)
1. **The logo is an E by construction.** The emblem is 4 `EmblemCrown` boxes, a 9 x 1.8 bar plus three prongs
   (`src/server/Services/ArenaBuilder.lua:3015-3019`). Seen from anywhere except the champion's side, that is a letter E.
2. **The jagged disc comes from the bake.** The emblem is baked into the single `arena_pocket` mesh at 0.5-stud voxels
   (`blender/catalog/arenadungeon.json`, `arena_pocket` args `vs 0.5`; tagged at `ArenaBuilder.lua:3090`).
   - The 16-gon `EmblemDisc` is 8 rotated 3.18 x 15 slabs (`:3014` via `disc16` at `:1802`), and they rasterise into a
     stair-stepped edge.
   - The pocket bake is over its 24,000-tri "big" budget and falls to detail level 0. The kit run here logged
     36,592 -> 17,676 tris.
   - `today_render.png` is the kit's real bake, and it reproduces the screenshot.
   - Fix: move the emblem parts out of the pocket's tagged model into a sibling `RingEmblem` with its own key,
     `arena_emblem`, at 0.25-stud voxels. Mesh.tag targets cannot nest, so it has to be a sibling.
3. **The gems are buried.** `EmblemGem` is a Keep part (`Mesh.Keep.Pocket`, `:565`) with its top at 0.20 studs. The
   bake's `align_y` offset is 0.3125, which puts the baked floor surface at y = 0.3125. That leaves the gems 0.11 studs
   under the mesh, so at best they peek through as the stray white squares. Fix: drop them (no option uses Neon).
4. **The Part fallback z-fights.** This shows whenever the mesh is not dressed.
   - `RingCanvas` (`:3009`) has slab tops at 0.040-0.068. `EmblemDisc` (`:3014`) has tops at 0.060-0.088, because
     `disc16` lifts each slab by 0.004.
   - Canvas slab 5 is level with disc slab 0, and canvas slab 7 (0.068) sits above disc slabs 0-1 near the rim, so sand
     shows through the violet edge.
   - Fix: put the emblem's lowest top above 0.068.
5. **The crowd cannot move.**
   - The puffs are baked into the static `arena_pocket` mesh (catalog: "cloud-puff crowd"; `arena_style` "puff" family).
   - All 7 puffs' 56 parts share one `CrowdPuffs` model (`ArenaBuilder.lua:2932-2948`), so there is no single spectator
     to tween.
   - Fix: give each spectator its own Model (PrimaryPart = the body) outside the pocket's tagged subtree, with its own
     mesh key(s). The steps stay in the pocket bake.
6. **There is no crowd code and no sound.**
   - Nothing in `src/client` mentions the crowd.
   - `SoundFx` knows only the UI names (`src/client/SoundFx.lua:27`).
   - Every id in `Config.Audio` is empty (`src/shared/Config.lua:502-505`), so the whole game is silent.
   - Fix: a client `RingCrowdFx`, active only in the player's own pocket. It runs the idle loop and reacts to a big hit
     / KO, a round won and a boss round from the Ring battle flow (the Ring result card is at
     `src/client/Controllers/BattleController.lua:4603`, `Ring.ResultLines` at `:5570`).
   - The sounds are 3D Sounds on the stand, with each spectator's PlaybackSpeed jittered 0.9-1.2 (Gemini's trick). The
     owner supplies the audio ids.
7. **Side finding.** The same offset leaves the baked ring floor 0.28 studs above the Part floor players stand on, so
   feet sink slightly into the visual floor. Check it when the pocket is re-baked.

## Directions (Gemini, gemini-pro-latest, then pushback)
- **Gemini's first answer was generic.** It suggested a sine-wave bob, gibberish "yays", wind chimes and a flush
  "cloud + crown" logo, and it assumed the logo was a decal. Claude pushed back.
- **Gemini's second answer was off-brief.** It built a lore around keeping the E (an "Escalation Engine") and left out
  the crowd. Claude rejected it.
- **The third answer gave one usable idea:** the Star-Paw emblem (a paw print whose main pad is a 5-point star),
  plus the per-spectator random PlaybackSpeed trick. Both were taken.
- **Claude drafted three directions and asked Gemini to judge them.** Gemini's critique:
  - A felt like "another game" (sailors wrestling). Taken: A's story is now the ships' pets sparring.
  - B risked looking like a messy backyard. Gemini suggested glowing runes and a glowing trough; rejected as generic
    magic glow, and Neon stays rare. B keeps a plain brass bowl and a tidy worn paw trail.
  - C felt low-stakes. Taken: the rosette became heavy forged gold.
- **The final three:**
  - **A. Sky-Sailors' Ring.** A compass star with a brass rim and a rope border, and a riveted steel repair plate on one
    point. The crowd is retired weather clouds in sailor caps: rain, a thunder captain, sun, snow (scarf) and fog
    (spyglass). Props: a ship's bell and a life ring on the flag mast, signal flags, a rope coil.
  - **B. Grandpaws' Ring.** A star-paw emblem on violet with a cream rim, plus claw scratches. The crowd is pet families
    (cat, pup, bunny, duckling, hamster) with a bedsheet banner, foam paws and a drummer pup. Props: a brass water bowl,
    a worn paw-print trail.
  - **C. Cloud Fair Ring.** A forged rosette: a scalloped gold ring, a violet centre, a chunky star and ribbon tails. The
    crowd is cloud parents with kids on their shoulders, holding pennants and popcorn, plus a hand bell. Props: striped
    fair poles with bunting, a chalk scoreboard.
- **Picks: Gemini B, Claude A. We disagree.**
  - Gemini: B ties the arena to the pets, the core of the game.
  - Claude: the fighters and the champion are already pets, so pet spectators compete with the fight from the high
    camera and can be mistaken for opponents. Weather clouds belong to the Nimbus sky, and their reactions (thunder
    flash, drizzle, rain-patter applause) are unique to this game. The compass star looks the same from every side, so
    it can never read as a letter.
  - After Claude's argument, Gemini said it agreed with A. It conceded very quickly, so its independent pick, B, is the
    one on record.

## Renders (this folder)
- `ring_pitch.py` builds everything:
  `%USERPROFILE%\.bpyenv\Scripts\python.exe -I ring_pitch.py <out_dir> [--res 100] [--samples 32] [--only today,a,b,c,lineup,motion,bake]`
  - It uses EEVEE with the Standard view transform, 32 samples, in one process; the full set takes about 50 s.
  - 1 unit = 1 stud. Roblox -> Blender uses the kit's PM, so the champion's side is +Y.
  - The player is R15-proportioned and 5.3 studs tall, standing on the baked floor surface (0.3125).
- `today.png` is the bug screenshot.
- `today_render.png` is the kit's real `arena_pocket` bake. `props/arena.py` runs ArenaBuilder in the mock world, then
  `arena_style.bake` at 0.5. The Keep parts are drawn as boxes. The sheet shows a 3/4 view, the crowd and the baked "E".
- `option_a/b/c.png` are each a sheet with three views:
  - the 3/4 view at the screenshot's angle;
  - the crowd close-up;
  - the emblem from the top.
  - The ring underneath is the same pocket re-baked without the `Emblem*` and `Puff*` boxes.
  - The emblems are 0.25-stud voxel inlays, 0.1 / 0.2 studs proud, the size an `arena_emblem` key would be.
- `lineup.png` shows TODAY, A, B and C from the same camera.
- `motion_a/b/c.png` are 4-frame crowd strips: idle, big hit, round won and boss round. Each frame is the tween pose,
  labelled with the sound cue.
- `bake_check.png` shows the three emblems voxelised at the game's 0.5 bake. A loses its fine compass detail (the
  points become a cross) and needs the 0.25 key; B and C survive.
- All renders were checked by eye:
  - The emblems sit on the floor surface, not under it (the first pass was buried at z = 0, which led to the 0.3125
    finding).
  - The spectators sit on the step tops.
  - The bell was moved from a post at the far edge onto the flag mast, so it shows in the motion strip.
  - The kids in C hide fully behind their parents on a big hit.
  - B's paw prints were enlarged so they read as prints.

## Budgets (arenadungeon catalog: small 1,800 / piece 4,000 / big 24,000 tris)
- These tri counts are estimates and were not measured with the kit mesher.
- `arena_emblem`: one key at 0.25 voxels, about 3-4k tris after greedy meshing ("piece"). Pulling the emblem and the
  puffs out of `arena_pocket` also gives that bake room back under its 24k budget.
- Crowd:
  - A: 7 clouds at about 600-1,200 tris each.
  - B: 7 pets at about 800-1,500 tris each.
  - C: 12 movers (7 parents + 5 kids) at about 500-1,000 tris each.
  - In all three, the body, arms and hat are rigid MeshParts tweened by the client (no rigs), and the props are one
    small key per option.

## Next
- The controller uploads the renders to the pitch board and commits.
- After the vote:
  1. Split the emblem and crowd out of the pocket model (the fixes above).
  2. Build `arena_emblem` and the crowd keys in the kit.
  3. Write `RingCrowdFx` and the audio hooks.
  4. Do a Studio check in a live Ring run (scale next to the pets, the camera from the fighter's pad, sound falloff).
