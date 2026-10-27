# Berry Farm pitch (bug #20): progress (2026-10-27)

The player's words: "the farm design bugs". The screenshot (`today.png`) shows the player on the Berry Farm buy pad
("Berry Farm $110K Buy"), with the farm sign reading "Berry Farm Lv 18". In it:
- the near barn is the plain Part build: flat roof slabs, a straight brace, a lantern, crates and the sign;
- next to that barn, the plinth, the soil rows, the wooden frame and the red-berry row are all missing;
- about 15 studs away stands a second, coarse barn. Its door brace is stair-stepped, which is the look of the 0.5-voxel
  `home_farm_N_low` key;
- one row of green cubes with two blue squares each (Part-build-style blue-berry bushes) runs between the two barns.

## What exists today
- Part build:
  - `Art.Farm` is in `src/server/Services/HomeBuilder.lua`: the Farm constants, `Farm.age` and `Farm.bush` at
    :828-849; the build at :851-974.
  - It has a slate plinth, 3 soil rows stepping up toward the back and a plank frame.
  - The rows: red bushes on levels 1-10, blue bushes on 11-22, a gold-vine trellis on 23-37, a sapling on 30-37 and
    the Starberry tree on 38-40.
  - A red barn with crates and the sign stands at local x -15.6.
  - Bushes are `Kit.ball`, a cube by design (P6 A1, :589-591).
- Slot: `TycoonCatalog.lua:381`, at (-26.5, 0.25) with yaw -90 and a 36 x 12 x 7 footprint. The buy pad is 7.5 studs
  in front of the field centre.
- Meshes:
  - `home_farm_1..40` plus `_low`, 80 keys in all (`blender/catalog/home.json`, `blender/kit/props/home.py` +
    `home_style.py`).
  - Each key is a fine-voxel bake of the Part build, and each is ONE part ("Fixed", 36.5 x 6.25 x 7.25).
  - Ids are in `src/shared/MeshIds.lua`.
  - Tagging: `Mesh.station` at :2680-2706 and `placeStation` at :2710-2729.
  - Client: `MeshLibrary.Dress` / `hideLocally` / `SetLod`, plus the HomeFx plot LOD at :4136-4220.

## Bug findings (they ship regardless of the vote)
1. **The bake is NOT the cause (verified).**
   - `farm_pitch.py` rebuilds `home_farm_18` and `home_farm_18_low` with the kit, in memory. The triangle counts are
     6,638 and 1,364, exactly the shipped manifests.
   - The layout signature (78 / -254.31 / 581.46) equals the live Part build's signature.
   - The renders (`today_render.png`) show every row on its soil and no bush inside the barn.
   - So the triage guess ("row-2 bushes offset, a bush baked into the barn, re-bake") is ruled out.
2. **Two farms drawn at once is a runtime dressing fault. The exact trigger is not reproduced (Studio was off-limits
   for this task).** Leads, with pointers:
   - `hideLocally` runs only once, when the mesh loads (`MeshLibrary.lua:1467`, called at :1546 from `Dress` :1493).
     Parts that are restored or that arrive later stay visible.
   - `SetLod` rebuilds the mesh as High or Low by camera distance (:1654-1685; HomeFx :4136-4220). The coarse copy in
     the screenshot has the Low look.
   - The fit cannot see a 180-degree turn on a single-part asset (`MeshLibrary.lua:656`), and every farm key is a
     single 36.5-stud part.

   Fix plan:
   - reproduce at Lv 11 / 18 / 22 while walking through the High / Low / Far tiers;
   - make the farm's facing certain (a yaw stored in the manifest, or a small second baked part);
   - re-hide the Part build after every mesh rebuild and when parts come back;
   - assert that `Station_Press1` has exactly one `ML_Mesh` and that only the `Lantern` stays visible.
3. **The fallback bushes are cubes.**
   - The farm cap is 150 parts, and Lv 40 already uses about 145, so no parts can be added.
   - Make each fallback bush a flatter box (wider than tall) seated on the soil, so the Part build reads as bushes
     when the mesh is off.

## Directions (Gemini, gemini-pro-latest, two rounds through `ask-gemini` with the brief as `@file`)
- **Round 1.** Gemini's three directions:
  - Aeronaut's Scrap-Patch: a crashed biplane, oil drums, rust, a fuselage barn;
  - Cloud-Catcher's Nursery: a glass cloche on every bush, a brass aqueduct with running water;
  - Heirloom Croft: a sagging barn, stone terraces, a picnic blanket over row 2, fireflies.
  - Gemini picked the Scrap-Patch and predicted the player would pick the Croft.
- **Round 2.** Claude's pushback:
  - Rust and gears are grimy next to the bright lobby, and a fuselage loses the barn read that carries the sign. It
    became a retired cloud-ship crew's allotment in painted wood, brass and sailcloth.
  - A cloche per bush means many see-through parts (overdraw), and the aqueduct is a separate animation system. They
    were dropped: glass only on the greenhouse, plus a cloud-catcher net and a rain barrel.
  - Fireflies would be unanchored parts. The picnic blanket breaks the progression, because row 2 is grass until
    Lv 11.
  - For all three: a bush is a rounded voxel dome with hanging berry clusters, never a cube, with one plant per level
    so the growth can be counted, at about 8k triangles per level.
- Gemini agreed with every point. There was no remaining disagreement on the content.
- Gemini's added details (kept):
  - B: the ship's bell that calls the pets to dinner, the painted anchor with a coiled rope;
  - C: the brass rain gauge, the rolled awning;
  - A: the step stool, the watering can.
- Final options:
  - **A, Heritage Sky-Croft** (Claude's pick);
  - **B, Sky-Sailor's Allotment** (Gemini's pick);
  - **C, Cloud-Catcher Glasshouse**.
- **Picks:**
  - Gemini picks B (the most "sky world") and predicts the player picks A.
  - Claude picks A:
    - it fixes exactly the complaint (the farm looks broken and blocky);
    - it stays closest to the barn and field the player knows;
    - it is the cheapest to fit into 8k triangles for all 40 levels plus the `_low` keys.
- Palettes: Claude kept Gemini's B and C palettes and swapped Gemini's slate-grey roof for slate blue in A, to keep
  today's roof colour. Final palettes are in `pitch.json`.

## Files
- Run:
  `%USERPROFILE%\.bpyenv\Scripts\python.exe -I farm_pitch.py <out_dir> [--res 100] [--samples 32] [--only today,a,b,c,lineup,growth] [--level 30]`.
  - EEVEE, one process, about 20 s for everything at 1280 px and 32 samples.
- Coordinates: the kit's mapping (roblox x -> -x, z -> y, y -> z). The shed is at +X as in the game.
- Plant positions and sizes use HomeBuilder's own formulas. The player (5.3 studs, R15 proportions) stands on the
  buy pad.
- Outputs:
  - `today.png`: the bug screenshot.
  - `today_render.png`: three panels of the game's own Lv 18 build: the Part build, the High key and the Low key
    (all baked by the kit in memory).
  - `option_a/b/c.png`: a main 3/4 view at Lv 30, a close-up of the shed and the first bushes, and a growth strip
    (Lv 5 / 18 / 30 / 40).
  - `lineup.png`: today's High key plus A, B and C at Lv 18 (the screenshot's level), from the same camera.
- Mock-up triangle counts (face by face, with no greedy merge, pad included):
  | Option | Lv 5 | Lv 18 | Lv 30 | Lv 40 |
  |---|---|---|---|---|
  | A | 44k | 49k | 54k | 59k |
  | B | 46k | 53k | 60k | 66k |
  | C | 45k | 51k | 57k | 62k |
  - The game bake merges faces and steps detail down to the 8,000-triangle stationBig budget. Today's Lv 18 is 6,638.
- Checked in the renders:
  - bushes sit on soil, with stems into the beds;
  - berries hang on stalks;
  - vines climb posts, oars or hoops;
  - the bell, cloud net and gutter all connect;
  - the gold berries sit on the vines;
  - the player's scale is right against the 3.4-stud barn walls;
  - growth reads per level (red row, then blue, then trellis, then the tree).
- Not modelled:
  - motion (B's propeller would turn slowly, A's lantern flickers);
  - the Lv 1-4 and 6-17 frames (the growth formula is the game's);
  - the `_low` LOD versions of the options.

## Next (after the player's choice)
1. Debug fix 2 in Studio first, then ship fixes 2 and 3 (`MeshLibrary.lua`, `HomeBuilder.lua` bush boxes).
2. Add the chosen style's families to `blender/kit/props/home_style.py`:
   - A: stone wall, sagging shingle roof, drooping bush;
   - B: hull trough, hull roof;
   - C: planter, glass.
3. Re-bake `home_farm_1..40` + `_low` from the (new) Part build. Check that each level fits 8k (High) and about 1.5k
   (Low).
4. Upload from the keyed cloud session. In Studio, check Lv 1 / 11 / 18 / 23 / 30 / 38 / 40 on a plot at all three
   LOD tiers.
