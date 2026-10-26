# Home portal design pitch: progress (frozen 2026-10-26)

The player asked for an artifact page to pitch object/model designs for approval. The first pitch is the home
portal (bug: "work with gemini and blender to improve home gate"; the screenshot shows the thin blue hoop).

## Done
- Gemini (gemini-pro-latest) proposed 3 directions:
  - **A. Homestead Trellis:** stone pillars, a wooden arch, a cottage crest, a brass HOME plate, ivy and a bird.
    This is Gemini's pick: it foreshadows the cozy home plot and uses few parts.
  - **B. Cloud-Potter's Gate:** a terracotta planter, two vine columns that meet in an arch, a sunflower crest,
    spilled dirt and a trowel.
  - **C. Waypoint Mailbox:** a red letterbox frame, an envelope crest with a wax seal, a flag, rivets and letters.
- My pick (Claude) is B. Its silhouette is the most distinct at a distance within the gate family, and the current
  home crest is already a house, which makes A close to what exists today. We disagreed: Gemini picked A.
- `portal_pitch.py` builds all three mock-ups with a 5-stud player for scale and renders `option_a/b/c.png` and
  `lineup.png`:
  `%USERPROFILE%\.bpyenv\Scripts\python.exe -I portal_pitch.py <out_dir> [--res 100] [--samples 32]`
- The drafts in this folder are low-res. The latest fixes (saturated swirl, sky gradient, tidier arch, wider
  cameras) were applied, but those renders have not been looked at yet.

## Next
1. Look at the drafts, fix what's off, and render at full resolution (`--res 100 --samples 32`).
2. Build the pitch board artifact:
   - capabilities `db` + `user` + `assets`;
   - each object is a card: renders as options, Gemini's and Claude's picks marked, Approve / Change / Skip,
     a note field;
   - choices are saved in `db` so Claude can read them back.
3. Upload the renders as assets, seed the home portal pitch with ArtifactData, publish, and send the link.
4. Later pitches: the waterfall, the ground (grass and flowers), the dungeon rooms, the storm altar to lobby
   portal and the benches.
