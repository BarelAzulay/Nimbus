# Absolute rules (non-negotiable)

Source: [`claude-setup/CLAUDE_SYSTEM_SETUP.md`](claude-setup/CLAUDE_SYSTEM_SETUP.md), step 4. Read this file and
[`brain.md`](brain.md) before any work in this project.

## Absolute laws
- Every substantive task: think it through with the brainstorming skill first, then run it as a multi-agent Workflow (standing opt-in: always use workflows).
- Mix models per stage: **Opus 5.5** builds and implements; **Fable 5.1** does the hardest design, review, judging and adversarial verification.
- Work autonomously: take the recommended option, say it in one line, keep going. Collect questions and ask them at the END, never mid-build. Only stop for destructive actions.
- Never claim something works without evidence (tests, checks, screenshots). Report failures honestly.
- Commit and push after every milestone.
- Each project is isolated: never touch another project's folder.

## Game projects (Roblox + Blender)
- Every visible model is hand-made in Blender. No Toolbox, no AI-generated meshes, no Roblox textured "marble" materials (SmoothPlastic + baked shading).
- Use exactly ONE Roblox Studio window per game. Never open extra baseplates or scratch places.
- Every project keeps a `brain.md` (source of truth + dated decisions) and this `ABSOLUTE_RULES.md`. Read both before working.
- Bug inbox: screenshots in this project's `bugs/` folder (file name = the bug). Fix those first, then move them to `bugs/fixed/` with a note.
- One Rojo port per game. Nimbus Climb uses the default port 34872.

## Communication
- Send a short progress update at every check-in: what finished, what's running, rough %.
- When the player is away, keep working; schedule check-ins so work resumes by itself after usage limits.
- Auto-compact is always on at a 500k-token window (`autoCompactWindow: 500000`). Never ask for a manual `/compact`;
  keep progress in files (ledgers; the trailer's `Projects Main/Nimbus trailer/scripts/CLIP_PROGRESS.md`) so a compaction loses nothing. Re-read this file
  and `brain.md` after every compaction.
