# Story clip: progress (2026-10-25)

## Done
- `clip_assets.py`: every clip subject is built by the REAL builders (`build_all.Builder(export=False).make`) and
  cached in `.cache/` (git-ignored). The first build takes about 70 s; after that it is cached. Nothing in src/,
  blender/out or the manifests is written.
- `render_story_clip.py`: the full scene, all 6 acts, 19 shots bound to timeline markers, the three-point light rig,
  fog boxes, the twilight sky from `branding/sky`, and Bezier/auto-clamped baking (about 110k keys).
- The hero is the player's own avatar: swoopy brown hair, purple shades, a magenta hibiscus Hawaiian shirt (a painted
  seamless tile in `.cache/hibiscus.png`), a gold striped tie, teal shorts, white sneakers, a brown leather item at the
  left hip (assumed to be a satchel, still to confirm) and the UFO hat (grey saucer, blue beam, glowing rings).
  `--avatar` renders it alone from the front, 3/4 and back.
- Every shot was checked on contact sheets (`--sheet`, 2 frames per shot) and fixed:
  - the bolt is length-scaled only (it used to be a white slab);
  - the Act 3 sprint camera is on the open side;
  - the coin swirl is above the head and filmed from the side on a 35mm;
  - the summit and Act 6 dragon offsets are wider;
  - the arena landing follows the falling hero;
  - the gem macro is a profile.
- `--preview` (frames 75, 210, 390, 525, 675, 840) passes at 1080p.

## Flags
`--preview`, `--full` (PNG frames to `play/clips/frames/`, resumable, then the MP4 via Blender's FFmpeg in a VSE scene),
`--sheet`, `--avatar`, `--frames`, `--res`, `--samples`, `--look=` (debug cameras, `;`-separated), `--probe`,
`--encode-only`, `--save-blend`, `--rebuild-assets`.

## Resume (frozen 2026-10-26, laptop battery)
- The avatar was updated to match the player's picture (spiky anime hair, puffy short sleeves, Roblox block hands)
  and checked on `--avatar` renders and a full `--sheet`. Committed.
- The full render was stopped at 98 of 900 frames. They are in `play/clips/frames/` and use the NEW avatar; the
  last, possibly partial frame was deleted. Resume (it skips the frames already on disk):
  `%USERPROFILE%\.bpyenv\Scripts\python.exe -W ignore blender/clips/render_story_clip.py --full --chunk 900`
  Speed: 15-60 s per frame in Acts 1-2. It is RAM-bound, so close Roblox Studio, Discord and browsers. Acts 3-5 are faster.
- Then check `play/clips/nimbus_story_clip.mp4` frame by frame.
- Then, as the player asked, MOVE the trailer project into `Projects Main\Nimbus trailer\`:
  - the scripts, the rules, this file, the frames, the previews and the MP4;
  - point `REPO` in both scripts at `Projects Main\Nimbus\nimbus-climb` (read-only);
  - remove `blender/clips` and `play/clips` from the game repo in one commit.

## Open questions for the player
- Is the brown item at the hip a satchel?
- Commit the MP4 and the previews, or git-ignore them?
