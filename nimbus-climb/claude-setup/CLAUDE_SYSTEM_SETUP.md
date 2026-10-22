# Make your Claude Code work like mine (the system, not a project)

Everything below is what my Claude Code has that a fresh install doesn't. You already have PowerShell, Blender and the Roblox Studio MCP connected, so do the rest in order. It takes about 15 minutes.

---

## 1. Plan and models
- You need a **Max** (or Team/Enterprise) plan that includes **Claude Opus 5.5** and **Claude Fable 5.1**.
- In Claude Code, run `/model` and pick **Opus 5.5** as the main model.
- The trick is **mixing them**: Opus 5.5 does the building and coding, and Fable 5.1 does the hardest thinking (design, reviews, checking work). The standing rules in step 4 tell Claude to do this by itself.

## 2. The Superpowers plugin (the "discipline" upgrade)
In Claude Code:
```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```
It gives Claude skills it uses on its own:
- `brainstorming`: thinks the idea through before building.
- `writing-plans` / `executing-plans`.
- `systematic-debugging`: finds the root cause instead of guessing.
- `test-driven-development`.
- `verification-before-completion`: proves something works before saying "done".
- `requesting-code-review`.
- `dispatching-parallel-agents`.

Restart Claude Code afterwards.

## 3. The extra skill pack (caveman and friends)
My extra skills are in the zip you already have: `claude-skills-for-friend.zip`, 60 files. Unzip its `skills` folder into your Claude skills folder:
```powershell
Expand-Archive "<path>\claude-skills-for-friend.zip" "$env:TEMP\cskills" -Force
Copy-Item "$env:TEMP\cskills\skills\*" "$env:USERPROFILE\.claude\skills\" -Recurse -Force
```
That adds:
- `brainstorming` (a standalone copy);
- the caveman family: `caveman`, `cavecrew`, `caveman-review`, `caveman-commit` and more (short answers, cheaper context);
- `ultracave`, `megacave`;
- `lean-build`, `surgical-patch`, `safe-refactor`, `investigate-first`, `migration`, `verify-and-stop`.

Check with `/skills`: they should all be listed.

## 4. Standing rules (the "brain" of how it behaves everywhere)
My Claude remembers these rules in its memory. For your friend, the simplest equivalent is a **user-level CLAUDE.md**, which Claude Code reads in every project. Create `%USERPROFILE%\.claude\CLAUDE.md`:
```powershell
notepad "$env:USERPROFILE\.claude\CLAUDE.md"
```
Paste this in, then edit it to your taste:
```markdown
# My standing rules (apply to every project)

## Absolute laws
- Every substantive task: think it through with the brainstorming skill first, then run it as a multi-agent Workflow (standing opt-in: I always want workflows).
- Mix models per stage: Opus 5.5 builds and implements; Fable 5.1 does the hardest design, review, judging and adversarial verification.
- Work autonomously: take the recommended option, say it in one line, keep going. Collect questions and ask them at the END, never mid-build. Only stop for destructive actions.
- Never claim something works without evidence (tests, checks, screenshots). Report failures honestly.
- Commit and push after every milestone.
- Each project is isolated: never touch another project's folder.

## Game projects (Roblox + Blender)
- Every visible model is hand-made in Blender. No Toolbox, no AI-generated meshes, no Roblox textured "marble" materials (SmoothPlastic + baked shading).
- Use exactly ONE Roblox Studio window per game. Never open extra baseplates or scratch places.
- Every project keeps a brain.md (source of truth + dated decisions) and an ABSOLUTE_RULES.md. Read both before working.
- Bug inbox: screenshots in the project's bugs/ folder (file name = the bug). Fix those first, then move them to bugs/fixed/ with a note.

## Communication
- Send me a short progress update at every check-in: what finished, what's running, rough %.
- When I'm away, keep working; schedule check-ins so work resumes by itself after usage limits.
```

## 5. Settings (`/config`)
- **Auto mode: ON.** Claude runs safe commands without asking every time, and still blocks risky ones.
- **Dynamic workflow size:** raise it if you want bigger multi-agent workflows.
- **Enable Remote Control for all sessions: ON.** Every session is reachable from your phone (claude.ai/code or the Claude app). In an already-running session, type `/rc`.
- **Push notifications for agents: ON.** Your phone pings you when background work finishes.
- **Auto-updates channel: latest.**
- Optional: in `%USERPROFILE%\.claude\settings.json`, add `"skipWorkflowUsageWarning": true` so big workflows don't ask for confirmation every time.

## 6. Dev tools on PATH (for Roblox projects)
```powershell
winget install Git.Git GitHub.cli astral-sh.uv
gh auth login
```
- **Rojo 7.7.1:** download `rojo-7.7.1-windows-x86_64.zip` from github.com/rojo-rbx/rojo/releases, put `rojo.exe` in `%USERPROFILE%\.local\bin` (on PATH), then run `rojo plugin install`.
- **luau-lsp** (lets Claude type-check Roblox code before Studio):
  ```powershell
  gh release download --repo JohnnyMorganz/luau-lsp --pattern 'luau-lsp-win64.zip' --dir $env:TEMP
  Expand-Archive $env:TEMP\luau-lsp-win64.zip "$env:USERPROFILE\.local\bin" -Force
  ```
- Tip: luau-lsp can't open folders with non-English names (like Hebrew Desktop paths). Make an English shortcut:
  ```powershell
  New-Item -ItemType Junction "$env:USERPROFILE\PROJ" -Target "<your project folder>"
  ```

## 7. Blender + Studio extras
- **Blender MCP:** turn on "auto start server" in the add-on, so it connects whenever Blender opens.
- Claude can also run Blender **headless** (`blender.exe -b --python script.py`) to build several models in parallel. No setup needed; just tell it to.
- **One Rojo port per game.** The default port is 34872. A second game should use another port (`rojo serve --port 34873`), so one game never syncs into another game's Studio window.

## 8. Habits that make it "perfect"
- **Start Claude inside the project folder.** It then auto-reads that project's `CLAUDE.md`, and the project's `CLAUDE.md` should point to `brain.md` and `ABSOLUTE_RULES.md`.
- **Give big specs in one go.** Claude splits them into phases: design, then code, art and animation in parallel, then review, then playtest.
- **Put bug screenshots in `bugs/`** with the bug as the file name. Prefer real images over Discord links, which expire.
- **When you leave, say "work autonomously and send updates."** Claude sets recurring check-ins that resume work and report progress.

## 9. Check it worked
```
claude mcp list        # blender + roblox-studio: Connected
/skills                # superpowers + caveman skills listed
/model                 # Opus 5.5
```
Then ask: *"What are your standing rules?"* It should repeat the rules from step 4.
