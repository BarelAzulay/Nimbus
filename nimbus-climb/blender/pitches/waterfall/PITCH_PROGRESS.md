# Lobby fountain / waterfall pitch (bug #13): progress (2026-10-27)

Player's words: "improve waterful design and fix animation to it". The screenshot (`today.png`) shows the plaza fountain:
two white marble bowls, flat blue water discs, thin blue stick "streams", and the Nimbus statue on top. Nothing moves.

## Bugs found (these ship regardless of the vote)
1. **The spray is hidden inside the statue.** `src/server/Services/LobbyBuilder.lua:1996` anchors `Spray` at
   centre + 10.6 studs. The Nimbus statue's lowest point is placed at TOP + 10.0 (`:2029` sets `topY = TOP + 9.4`, and
   `:2036` adds 0.6), so the particles spawn about 0.6 studs inside the dragon's body. That is the "faint spray".
2. **No water animation exists at all.** No client code touches the fountain (`grep Fountain src/client` finds
   nothing).
   - `prop_fountain_water` is one static Glass MeshPart (T 0.35; see `src/shared/MeshManifests/prop_fountain_water.lua`).
   - The falls are 8 + 8 solid boxes, 0.5 x 3.2 and 0.4 x 2.6 (`blender/kit/props/lobby.py:391-392`). They read as
     posts.
   - Fix: each fall becomes 2-3 layered `Beam` sheets with `TextureSpeed`, which animate with no script (Gemini's
     suggestion: a core, a faster foam layer and a slow mist layer, tapered toward the bottom, the top and bottom faded
     out). Add a splash `ParticleEmitter` at every impact, plus a small client `FountainFx` for ripple rings, bobbing
     floaters and the wheel spin (option A).
3. **The spray texture is the sparkle star.** `emitter()` defaults to `SPARKLES` (`LobbyBuilder.lua:470`), so the
   "water" reads as glitter. Fix: use a soft droplet texture with a white-to-blue ramp.

## Directions (Gemini, gemini-pro-latest, then pushback)
- Gemini's first three ideas were a Spiral Cloud Cascade, a Royal Dragon's Bath and a Shattered Sky-Oasis.
- Claude pushed back on all three:
  - The spiral (orbiting glowing stars, a water spiral, no story) is generic. Claude replaced it with **A**.
  - The gold chalice reads as shop bling, so the bath became a lived-in bath.
  - The "glowing energy beams" holding up the islands became stone pillars with roots.
- Gemini pushed back once: a sunken pool on a busy roundabout is a trap, so B is a raised, waist-high bath. Claude
  agreed.
- The final three:
  - **A. The Rain-Catcher.** The first settlers' water station: a captive rain cloud drips into a copper funnel on a
    timber frame; a pipe and chute feed a turning water wheel that splashes into an octagonal cobble trough. Details:
    brass spigot, bucket, chalk tally, toy boat, moss, maintenance ladder. Nimbus perches on the funnel rim like a
    weathervane.
  - **B. Nimbus' Bath.** A raised sandstone bath with a mosaic band, worn steps and coins on the tiled floor. Nimbus
    sits on a mossy rock and spits one long arc into the pool. Details: rubber duck, lily pads, towel rail, brush,
    soap.
  - **C. Sky-Oasis Steps.** Three broken sky-island chunks on stone pillars with hanging roots. A spring on top feeds
    three falls, island to island, ending in a big fall into a mossy rock pool. Nimbus sits in a twig nest on top.
    Details: stepping stones, a ladder and a knotted rope as a mini climb, a tree, flowers, a lantern, a sign, a paper
    boat.
- **Picks: Gemini B, Claude C. We disagree.**
  - Gemini: the spitting Nimbus is one readable animation loop that "definitively fixes" the complaint.
  - Claude: "waterful" most likely means *waterfall*. C is the only idea built around real falls, it keeps today's
    height on the skyline, and it adds a little climb to a Climb game's lobby.
  - Gemini predicted Claude would pick A.

## Renders (this folder)
- `waterfall_pitch.py` builds everything:
  `%USERPROFILE%\.bpyenv\Scripts\python.exe -I waterfall_pitch.py <out_dir> [--res 100] [--samples 32] [--only today,a,b,c,lineup,motion|motion_a..]`
  - It uses EEVEE at 1280 x 960, 32 samples, in one process; the full set takes about 30 s.
  - 1 unit = 1 stud. The player is R15-proportioned and 5.3 studs tall.
- `today.png` is the bug screenshot. `today_render.png` is today's real `prop_fountain` + `prop_fountain_water`, built
  in memory by the kit (`props.load_all()` + `nvox.blend.make_objects`). Nothing is exported and nothing in the repo
  changes. Nimbus is a voxel stand-in at LobbyBuilder's height (TOP + 10).
- `option_a/b/c.png` are 3/4 plaza views at the screenshot's angle. `lineup.png` shows TODAY, A, B and C side by side
  at the same scale, with labels.
- `motion_a/b/c.png` are 4-frame contact sheets (phase 0, 0.25, 0.5, 0.75 of one loop; labelled at 0.8 s per loop)
  showing:
  - the falling-water texture scrolling;
  - drops travelling;
  - splash and ripple rings growing;
  - the wheel turning (A);
  - floaters bobbing.
- All renders were checked by eye:
  - The posts meet the funnel wall and the wheel clears the plinth, the chute and the A-frame.
  - The rope and ladder ends land on islands, and the towel rail stands on the bath cap.
  - The boat hull now sits above the water line.

## Budgets (lobby catalog: centrepiece = 7,500 tris / 8 parts; prop = 2,000 / 8)
- A: basin + frame + funnel are about 7,000 tris. The wheel is its own key (~1,500, spun by the client). The cloud
  could reuse a sky cloud mesh.
- B: basin + rock are about 5,000. Nimbus stays the pet build and needs a "spit" pose (head up, mouth open) or a fixed
  statue key.
- C: pool + 3 islands + pillars are about 7,000. The ladder and rope are a small prop key.
- In all three, the falling water is Beams (no mesh), and the pool surface stays a translucent mesh key (~1,000).

## Next
- Upload the renders to the pitch board (`../board`, `pitches/waterfall`). The controller does this, and also commits.
- After the player's vote:
  1. Build the chosen basin in `blender/kit/props/lobby.py` (`lobby_fountain`).
  2. Replace the stick streams with Beams in `buildFountain`.
  3. Move or retexture the spray.
  4. Add `FountainFx`.
  5. Check it in Studio.
