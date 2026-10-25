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

## Resume
`%USERPROFILE%\.bpyenv\Scripts\python.exe -W ignore blender/clips/render_story_clip.py --full`
(resumes from the frames already on disk). Output: `play/clips/nimbus_story_clip.mp4`.

## Open questions for the player
- Is the brown item at the hip a satchel?
- Commit the MP4 and the previews, or git-ignore them?
