# Story clip: progress (paused 2026-10-25)

## Done
- `clip_assets.py`: every clip subject built by the REAL builders (`build_all.Builder(export=False).make`), cached in
  `.cache/` (git-ignored). The first build takes about 70 s; after that it's cached. Nothing in src/, blender/out or the
  manifests is written.
- `render_story_clip.py`: full scene, all 6 acts, 19 shots bound to timeline markers, three-point light rig, fog boxes,
  twilight sky from `branding/sky`, Bezier/auto-clamped baking (about 88k keys), `--preview`, `--full` (PNG frames,
  resumable, then MP4 via Blender's own FFmpeg in a VSE scene: no external ffmpeg needed), `--frames`, `--probe`,
  `--look` (debug camera).
- Paths follow CLIP_RULES: the script is in `blender/clips/`, outputs go to `play/clips/` (not `play/` as the script
  request said).

## First preview findings (fix next)
1. Arm/leg swing sign was inverted (the arm went backward). FIXED in `Climber.pose` (not re-rendered yet).
2. Frame 75: the 85 mm OTS camera is too close (frame height = 0.282 x distance). Move it to about 21 studs back so
   Stormfang is in frame.
3. Frame 210 (and 136-232) is black: the probe shows the hand close-up camera at (0.2, 27.6, 1.2), INSIDE the lying
   climber. The right hand is at x = -3.3 (out to -X). Put the camera on the outer side: about hand + (-3, -3, 0.7),
   looking at the hand.
4. f1: hero z = -1.7. The ground ray cast at y = 52 misses the bridge or hits below it. Clamp it, or start the walk at
   y = 45. Check with `--look`.
5. Skin reads orange: AgX plus the warm key light. Make the key less warm or the skin a paler yellow.
6. "Shadow buffer full": practicals now have use_shadow = False and shadow_pool_size is 1024 (not re-rendered yet).
7. Speed: build about 22 s, direct about 21 s, then the renders. The under-30 s preview target is not met yet. The
   director's `frame_set` calls (hand / coin / gem positions) are the slow part.

## Resume
`%USERPROFILE%\.bpyenv\Scripts\python.exe -W ignore blender/clips/render_story_clip.py --preview`
Then check frames 75, 210, 390, 525, 675 and 840 in `play/clips/preview/` with Read.
Open questions for the player: commit the MP4 / previews or ignore them?
