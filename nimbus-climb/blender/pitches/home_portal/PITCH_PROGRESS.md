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

## Update 2026-10-27 (hand-over to the main game session; these files are left UNCOMMITTED on purpose)
- The renders were fixed and redone at full resolution (`--res 100 --samples 32`):
  - the swirl is a real spiral (atan2 + radius sine in the shader);
  - the sky is a lavender-to-periwinkle gradient;
  - the plaza floor is bigger, so the lineup never sees its edge;
  - the console prints UTF-8, because the Hebrew path crashed `print`.
  `option_a/b/c.png`, `lineup.png` and `draft_grid.png` in this folder are the current set. `today.png` is the bug
  screenshot. The `.jpg` copies are the files uploaded to the board.
- **The pitch board is live:** https://claude.ai/artifact/AJfbKLZLDciJeThjRDktgw ("Nimbus Design Pitches").
  - Source: `../board/index.html`.
  - Capabilities: `db` (rule: `pitches` read view / write admin), `user`, `assets`.
  - `pitches/<id>`: `{order, kind, source, title, brief, today, lineup, agreement, options: [{id, name, picks:
    ["gemini"|"claude"], img, story, palette: [[r, g, b]], details: []}]}`. The images are asset URLs
    (`/_blob/<id>`).
  - `decisions/<pitchId>`: `{choice, verdict: approve|change|skip, note, at, by}`, written by the player on the
    page.
  - Read the player's choice back with ArtifactData `list` on `decisions` before building anything.
  - To add a pitch: upload the renders with Artifact `publish` + `url` + `asset: true` (copy them to a scratchpad
    first, because the OneDrive path needs per-file approval), then ArtifactData `set` on
    `pitches/<new-id>` with the next `order`.
- **The home portal pitch is seeded** (`pitches/home-portal`) and is waiting for the player's decision. No direction
  has been chosen yet. Gemini picks A (Trellis) and Claude picks B (Cloud-Potter's Gate); the board states the
  disagreement.

## Next (for the main session)
1. Read `decisions/home-portal`. Then build the chosen direction properly in `blender/kit/props/gates.py`
   (`gate_home`; budget 8,000 tris and about 20 parts; the swirl stays a Neon part), and check it in Studio.
2. Later pitches on the same board: the waterfall, the ground (grass and flowers), the dungeon rooms, the storm
   altar to lobby portal and the benches.
3. Blender: this work used the standalone `bpy` module (`%USERPROFILE%\.bpyenv`), not the Blender app or MCP, so
   nothing holds Blender open.
