# Fight feel check page + readability pitch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One phone-friendly artifact page: Part 1 shows LIVE vs KIT-B for four hit moments (moving pictures), Part 2 pitches 4 readability problems x 3 drawn options; the owner's picks save to the page.

**Architecture:** Pictures are made offline by the PITCH 2 pipeline (Blender voxel scenes `motion_pitch.py` / `scene.py` / `rm_lib.py`, HUD mock-ups `kit.py` with Theme.Sign tokens and `tools/render_model.py` cut-outs) into a work folder outside git; the page is one HTML artifact with its images in the artifact's asset store and an artifact database collection `choices`.

**Tech Stack:** bpy 5.2.2 (venv `%LOCALAPPDATA%/NimbusClimb/bpyenv`), Python 3.12 + Pillow/numpy, Artifact tool (`db` + `assets` capabilities), Playwright for the page check.

**Spec:** `docs/superpowers/specs/2026-11-23-fight-read-design.md`

## Global Constraints
- No game code, no balance numbers, no uploads to Roblox, no merges. Never touch `.worktrees/qw-step1-gate` or `.worktrees/kitb-p2-fix6` (a run is live there).
- Every option is a picture (owner rule); motion moments are GIFs.
- 3D only from Blender with the game's real voxel pets (owner rule); UI in kit B tokens (`Theme.Sign`) at true pixel scale.
- Work folder: `.superpowers/fight-read/` (not in git). Pipeline sources read from `.superpowers/slop-audit/round3/build/PITCH2/` (copy, never edit in place).
- "LIVE" = the fight as published before attack-fx / battle-feel / kit-b motion: model it on main's attack-fx merge parent (`git log --merges --first-parent main` -> the parent before attack-fx). Any LIVE picture rebuilt in Blender is labelled "re-created".
- Mark Claude's pick and Gemini's pick on each Part 2 item; Gemini via gemini.google.com in Claude in Chrome (API is 402); if not reachable, the page says "Gemini: not reached".
- Phone first: 390 px wide page, 16 px gutter, no horizontal scroll; each GIF <= 4 MB and <= 6 s loop.

## Review Focus
1. Owner opens on a phone over mobile data: GIFs must load lazily and the page must be usable before they finish (lazy `loading`, poster PNG first). Pinned in Task 4 check.
2. A pick tapped twice / changed: the `choices` doc for that item is overwritten, not duplicated. Pinned in Task 4 check.
3. Page opened before any pick exists or with the db empty: every item shows "not picked yet", no errors. Pinned in Task 4 check.
4. Dark mode on the phone: images on a neutral card, labels readable. Pinned in Task 4 check.
5. Options that look alike: each Part 2 option sheet differs at a glance (checked by eye on the contact sheet in Task 2).

---

### Task 1: Part 1 moving pictures (LIVE vs KIT-B)

**Files:**
- Create: `.superpowers/fight-read/part1/` (scripts copied from PITCH2 `E_motion_models/`: `scene.py`, `rm_lib.py`, `kit.py`, `motion_pitch.py` -> `p1_moments.py`, `gif_contact.py`)
- Output: `part1/m1_melee.gif`, `m2_special.gif`, `m3_crit.gif`, `m4_bosshit.gif`, each + `_poster.png`; `part1/sheet.png`; `part1/check.json`

**Interfaces:**
- Produces: `part1/manifest.json` = `[{ "id": "m1".."m4", "title": str, "gif": path, "poster": path, "live_label": str, "built_label": str, "built_from": "branch@sha" }]`

- [ ] **Step 1:** m1 melee: reuse `05_melee_motion_before.gif` (LIVE) and `05_melee_motion_optA.gif` (built Bounce-in A) as one side-by-side GIF, labels "LIVE" / "KIT-B", downscaled to fit <= 4 MB.
- [ ] **Step 2:** m2 special, m3 crit, m4 boss hit: render side-by-side in Blender with the same scene kit. Values from code, not memory: LIVE from the main attack-fx merge parent; KIT-B from origin/kit-b (`AttackFxCatalog` impact package, `Config.Battle.Feel` RealCast / hit stop 0.05 / wind-up 0.25, victim knock-back + rock). Record each value used and its file:line in `manifest.json` `notes`.
- [ ] **Step 3: Check** — run `py -3.12 part1/check.py`: asserts 4 GIFs, each <= 4,000,000 bytes, duration <= 6.0 s, both labels drawn (label strings present in manifest), poster exists. Expected: `PART1 OK 4/4`.
- [ ] **Step 4:** Build `sheet.png` (one frame per 0.5 s per moment) and look at it: LIVE and KIT-B visibly differ at the hit frame; no floating pets, no sinking paws. Fix and re-render if not.

### Task 2: Part 2 readability mock-ups

**Files:**
- Create: `.superpowers/fight-read/part2/p2_read.py` (uses copied `A_battle_hud/kit.py` + `D_world/kitb_world.py`)
- Output: `part2/<item>_opt{A,B,C}_844x390.png` and `_1920.png`, `part2/<item>_sheet.png`, `part2/manifest.json`

**Interfaces:**
- Produces: `part2/manifest.json` = `[{ "item": "target"|"danger"|"noise"|"numbers", "question": str, "options": [{ "key": "A"|"B"|"C", "name": str, "line": str (what it trades off), "phone": path, "pc": path }], "claude_pick": "A"|"B"|"C", "claude_why": str }]`

One raid scene (boss + my 3 pets + two other players' teams + their effects), the kit-b HUD over it; per item only the readability layer changes. Starting option sets (the pitch agent may replace one with a better, clearly different idea and says why):
- [ ] **Step 1: target** — A ground ring under my pet's target in my colour; B a small chevron above the target's head; C a thin tether from my fighting pet to its target.
- [ ] **Step 2: danger** — A boss zone fills red over its wind-up (fill = time left); B outline + a ring shrinking to the hit moment; C boss glow + zone + a "!" over each threatened pet of mine.
- [ ] **Step 3: noise** — A other players' effects at 40 % and no camera kick from them; B others' effects as outlines only; C others' numbers hidden, effects full.
- [ ] **Step 4: numbers** — A size by damage, colour by element, crits gold and bigger; B my numbers big, others small grey; C one rolling total per target.
- [ ] **Step 5: Check** — `py -3.12 part2/check.py`: 4 items x 3 options x 2 sizes = 24 PNGs at exact sizes 844x390 / 1920x1080, manifest valid, each option `line` non-empty. Expected `PART2 OK 24/24`. Then look at each `_sheet.png`: options differ at a glance and the layer never hides the hit effects (spec anti-goal). Fix if not.

### Task 3: Gemini pick

- [ ] **Step 1:** In Claude in Chrome, open gemini.google.com, paste the 4 Part 2 sheets + the question per item, ask for its pick and one reason each. Save the reply to `part2/gemini.md` and set `gemini_pick` / `gemini_why` per item in `manifest.json`.
- [ ] **Step 2:** If Chrome is not connected or Gemini cannot be reached: `gemini_pick: null`, note "Gemini: not reached" (no guessing).

### Task 4: The page

**Files:**
- Create: `.superpowers/fight-read/page.html`, `.superpowers/fight-read/page_check.mjs`

**Interfaces:**
- Consumes: `part1/manifest.json`, `part2/manifest.json`
- Produces: the artifact URL; db collection `choices`, one doc per item id (`m1`..`m4`, `target`, `danger`, `noise`, `numbers`): `{ verdict?: "right"|"weak", pick?: "A"|"B"|"C"|"skip", note: str, at: iso }`.

- [ ] **Step 1:** Load skills `artifact-design` and `artifact-capabilities`; quickstart intent `other`.
- [ ] **Step 2:** Upload all images to the artifact's asset store (`asset: true`, batches of <= 25); reference them by returned url. Page: Part 1 cards (poster first, GIF lazily, "Feels right" / "Still weak" + note); Part 2 cards (options swipeable at phone width, PC picture behind a tap, Claude / Gemini pick badges, disagreement line, A / B / C / Skip + note); a summary at the top of what is picked so far.
- [ ] **Step 3: Check** — `node page_check.mjs` with Playwright at 390x844 light + dark: no horizontal scroll (`scrollWidth <= 390`), every poster loaded, GIFs have `loading="lazy"`, empty db shows "not picked yet" for all 8 items with no console errors, picking `target` A then B leaves exactly one `target` doc with `pick: "B"`. Expected: `PAGE OK`.
- [ ] **Step 4:** Publish; send the link to the owner (phone).

### Task 5: Ledger and commit

- [ ] **Step 1:** Add a "fight-read" entry to `.superpowers/PENDING.md` and a new `.superpowers/fight-read/LEDGER.md`: URL, what is on the page, my picks, Gemini's (or "not reached"), cost if wrong, next step (read `choices` back before any build; Studio fight on kit-b with the owner).
- [ ] **Step 2:** Commit this plan's progress note to `fight-read` and push.
