# Lobby ground / lawn pitch (bug #12): progress (2026-10-27)

The player's words: "improve ground (grass,flowers etc) design with blender and gemini".

The screenshot (`today.png`) shows the plaza lawn:
- a flat lime plane;
- the "flowers" are flat 2 x 2-stud coloured squares, 0.1 stud tall (pink, yellow, white, violet, red, blue);
- one square sticks out under a tree's roots;
- there are no tufts and no height.

## What exists today
- The flower squares are `Flower<n>` cells of the lawn-patch layer in `LobbyBuilder.plazaCell`
  (`src/server/Services/LobbyBuilder.lua:1711-1717`).
  - They are built on a 2-stud grid in `buildPlazaGround` (`:1797-1855`) at the -0.3 layer, 0.1 above the lawn (-0.4).
  - They are baked into the `floor_plaza_lawnpatches` mesh (`Mesh.tag` `:1853`;
    `src/shared/MeshManifests/floor_plaza_lawnpatches.lua`, 4,700 tris, LayoutSig).
- The same squares are also made on the shop lawn (`:3085-3086`) and on the garden islands (`:3871-3873`).
- Palette: `FLOWERS` `:257-264`. Their material is `LeafyGrass`, which `materialOf` resolves to SmoothPlastic.
- `Props.FlowerBed` (`:1387`) is the only 3D flower anywhere. In Blender it is `lobby_flowerbed` in
  `blender/kit/props/lobby.py:297`.

## Bugs found (these ship regardless of the vote)
1. **Flower squares under props.**
   - Cause: `buildPlaza` runs `buildPlazaGround` first (`:2565`). Only afterwards does `buildPlazaDecor` reserve the
     tree, lamp and bench spots (`:2462-2506`, `reserve` `:1781`), and `plazaCell` never checks those reserves.
   - Effect: a square can sit under a tree's roots. Both the screenshot and `today_render.png` show it.
   - Fix: scatter the new dressing after the decor, and skip any spot `plazaFree` (`:1765`) marks as taken.
2. **Removing the squares changes a baked floor.**
   - Drop the `Flower` cells in all three places above.
   - In the same change, re-bake `floor_plaza_lawnpatches` with `lobby_boxes` (`blender/kit/props/lobby_world.py`).
     Otherwise its LayoutSig check fails and the lawn patches fall back to plain Parts.
3. **Shipping rules for the new dressing.**
   - It is non-colliding and carries the `NC_Detail` tag (`:101`), so the Low graphics setting hides it.
   - It is baked into chunk keys instead of separate Parts, so the lobby stays within its 8,000-part budget.

## Directions (Gemini, gemini-pro-latest, then pushback)
- Gemini's first answer was one combined plan instead of three directions. It contained:
  - rolling grass terraces;
  - 3D tufts clustered at the props;
  - 3D flowers with 2-3 stud blooms;
  - a "Cloudling" caretaker NPC in a sun hat;
  - pollen and firefly particles.
- Claude rejected four parts of it:
  - the hills, because the walk rule keeps every walking surface flat (layers differ by 0.3 stud at most);
  - the NPC and the particles, as out of scope;
  - the 3-stud blooms, which are the wrong scale next to a 5.3-stud player.
- Claude then proposed three seeds and asked Gemini to critique them.
- Gemini's critique:
  - A: drop the push-mower clutter.
  - B: keep tufts under 1 stud and thin them near paths so pets stay visible.
  - C: make the stone rings and stepping stones flush decals.
- Claude's second pushback:
  - Flat painted stones repeat exactly what the player complained about, so they are real stones, 0.15-0.3 stud
    proud, which the step rule allows.
  - Each direction keeps ONE small human-touch prop, because the brief asks who tends the lawn.
  - Gemini's "invisible caretaker" is too vague, so each direction gets a named keeper: the lamp-lighter (A), nobody
    and the wind (B), the settlers' families (C).
- Gemini agreed to all four points.
- Gemini's added details (kept):
  - A: the clippings pile at the lamp;
  - B: seeds flying mid-air downwind;
  - C: the crooked lupin doodle on the plant marker.
- The final three:
  - **A. The Groundskeeper's Lawn.**
    - Mown stripes in two greens.
    - Long tufts only where the mower can't reach: the trunk, the lamp foot, the bench legs and the bed's planks.
    - A clover and daisy fringe along the paths.
    - A worn dirt shortcut across the corner, with a crooked "keep off the grass" sign.
    - A rake leaning on the tree, and a clippings pile at the lamp.
  - **B. Wind-Sown Sky Meadow.**
    - Clumpy tufts that all lean downwind and sway in rolling gusts.
    - The grass thins out near the paths.
    - A torn seed sack by the flower bed, with a comet-shaped trail of the bed's own colours streaming downwind.
    - Dandelions and clocks with flying seeds, and blue cornflowers.
  - **C. Settlers' Cottage Garden.**
    - Single-species clumps in raised stone rings: red tulips with one stray yellow, and mixed lupins with a child's
      painted marker.
    - Forget-me-nots round the tree inside a stone ring.
    - Stepping stones to the bench, and a low 0.8-stud box hedge along the walk.
    - A watering can, and a few daisies left alone. The rest is open, short lawn.
- **Picks: Gemini first picked C, Claude picked B, and Gemini switched to B. Both now pick B.**
  - Gemini on C: the tight clumps leave wide open lawn, so pets stay readable.
  - Claude on B: the player's words lead with *grass*, and B is the only option where the grass itself gets height,
    motion and a reason (the wind). It is also the biggest visible change from today.
  - Gemini accepted that argument. It had predicted Claude would pick A.
  - Note: B is a persuaded agreement, not two independent picks. C was Gemini's own first choice.

## Renders (this folder)
- `ground_pitch.py` builds everything:
  `%USERPROFILE%\.bpyenv\Scripts\python.exe -I ground_pitch.py <out_dir> [--res 100] [--samples 32] [--only today,a,b,c,lineup,motion]`
  - It uses EEVEE, Standard view transform, 1280 x 960 and 32 samples, in one process. The full set takes about 15 s.
  - 1 unit = 1 stud.
- Every image is the same 56 x 56-stud lawn corner:
  - an L of cobble walks at the game's layer heights (path 0, border -0.1, lawn -0.4);
  - the kit's real `prop_tree_round`, `prop_lamp`, `prop_bench` and `prop_flowerbed`, built in memory with
    `props.load_all()` + `nvox.blend.make_objects` (nothing is exported and nothing in the repo changes);
  - a 5.3-stud R15-proportioned player and a 2.5-stud fox-cub pet stand-in.
- Only the ground dressing differs between images. The camera is the screenshot's high 3rd-person angle.
- Each image has a close-up inset in its bottom-right corner:
  - TODAY: the square under the roots;
  - A: the shortcut and the clippings at the lamp;
  - B: the sack and the drift;
  - C: the lupins, the plant marker and the stepping stones.
- `today_render.png` is today's lawn rebuilt with the same layout, flat squares and all.
- `lineup.png` is a 2 x 2 grid (TODAY, A, B, C), all with the same camera and scale.
- `motion_b.png` is a 4-frame contact sheet of B's gust sway (t = 0, 1, 2, 3 s of a 4 s loop), shot side-on to the
  wind.
- All renders were checked by eye:
  - The props, the player, the pet, the sack, the can, the rake and the sign stand on the lawn.
  - The stones sink 0.1 stud into it.
  - Nothing grows through the trunk, the lamp, the bench, the bed or the paths.
  - The pet and the tulip clump were moved out from under the inset, and the B and C close-ups were re-aimed at their
    story details.
  - The only things off the ground are B's flying dandelion seeds, on purpose.

## Budgets (catalog `floor` = 10,000 tris and 8 parts per key; lobby <= 8,000 parts)
Dressing triangles as rendered, per patch (2,401 sq studs of lawn):

| Option | Tris per patch | Tris per 100 sq studs | Plaza estimate (~25,000 sq studs of lawn, a guess) |
|--------|---------------:|----------------------:|----------------------------------------------------:|
| TODAY (squares) | 370 | 15 | |
| A | 13,400 | 558 | ~140k |
| B | 32,830 | 1,367 | ~340k |
| C | 8,660 | 361 | ~90k, but C costs ~2k per clump, not per area |

Target for the game: ≤ 8 non-colliding `floor_plaza_meadow_<n>` chunk keys at ≤ 10k tris each (≤ 80k tris, 8
parts), Detail-tagged.
- A needs its edge fringe thinned by about half.
- B goes only on the outer lawn ring, at about 1/4 of this density.
- C needs about 10-12 clumps plaza-wide.

Blades are tapered leaning prisms (10 tris each, no bottom face). Flowers are 5-9 small boxes each.

## Gemini tooling notes (for the next pitch)
- `brainstorm` returned only a generic greeting.
- `ask-gemini` dropped any prompt that had lines starting with "-" (it answered "your message was cut off"). Send a
  single paragraph.
- Gemini is stateless between calls: repeat the full context every time.

## Next
- The controller uploads the renders to the pitch board (`pitches/ground`) and commits.
- After the player's vote:
  1. Build the chosen tuft and flower set in `blender/kit/props/lobby.py` (new meadow chunk builder).
  2. Remove the `Flower` cells.
  3. Re-bake `floor_plaza_lawnpatches`.
  4. Scatter after the decor, respecting `plazaFree`.
  5. For B, add the client sway.
  6. Check it in Studio at High and Low graphics.
