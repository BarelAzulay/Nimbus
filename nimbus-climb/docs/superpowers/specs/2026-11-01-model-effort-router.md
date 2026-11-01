# Model and effort router (which model, what effort, for which job)

Date: 2026-11-01. Status: **standing rule** (owner's ask: "a program that knows when to use which model for what AND what
effort"). It refines the law in `ABSOLUTE_RULES.md` ("Opus 5.5 builds and implements; Fable 5.1 does the hardest design,
review, judging and adversarial verification"); it never replaces it. This is the routing table; `tools/pick_model.py` is the
program that holds it as data, so a change here goes there too.

## The words

- Models, costliest first: **Fable 5.1**, **Opus 5.5**, **Sonnet 5.5**, **Haiku 5.5**.
- Efforts of a workflow agent or an Agent call: **low, medium, high, xhigh, max**. The owner's "easy" = low, "extra high" = xhigh.
- **Ultracode** is not an effort. It is a way of running a whole job: several workflows in sequence, adversarial verification,
  completeness critics, loop-until-dry, and token cost is not the constraint (section 3).
- The owner's speed rule holds everywhere: never lower a build's quality or scope, never drop a test, review, pitch or evidence
  step. A cheaper route is only for work where a mistake is cheap and visible. **In doubt, the route goes up, not down.**

## 1. The table

Builder = the agent that writes; reviewer = the agent that reads the diff and tries to break it. "Gate" = the test or tool
that catches a mistake. Where no reviewer is named, the gate is the review.

| Job | Builder | Reviewer | Why |
|---|---|---|---|
| Game code, server authoritative (services, remotes handlers, sims) | Opus high | Fable high on one task; the whole wave gets the wave review below | The standing law; the smoke suite catches most slips, Fable catches the server/client trust mistakes it cannot (mesh-load review found 2 real bugs, 2026-10-24) |
| Saves and player data (DataService, migrations, folds, merges) | Fable high | Fable xhigh | Phase 5 W1 gave `data` to Fable on purpose; a bad save is live data and hard to undo; the frozen-fixture rollout tests are the gate but only for the cases someone thought of |
| Money and rewards (Cash, Gems, loot paid once, prestige, products) | Fable high | Fable xhigh + `sim_tycoon.py` ALL TARGETS MET | A double payout is a live, visible, un-undoable mistake (W4 "berries dup" happened); the sim gates pacing, Fable gates the once-per-member rules |
| Security of remotes (validation, rate limits, who may call what) | Fable high | Fable xhigh (adversarial: plays the exploiter) | No test plays an exploiter; the reviewer must |
| Balance tuning (`BattleCatalog` numbers, `tools/sim_battle.lua`) | Opus medium | the sim (full, `seeds` as the plan says) + Fable medium on the target changes | The sim catches a wrong number (lava golem 90 -> 85 was pinned at 16 seeds); the only judgment is whether a target itself was bent, so the review reads the targets, not the code |
| Effects and GUI only Studio can judge (sky, VFX, HUD layout, camera) | Opus high | Fable medium on the code + render_gui / render_model sheets + the owner's Studio check | The mock passed and Studio still showed a cube sky and a grey court; the owner's look is the real gate, so it is never skipped and the code review stays cheap |
| Design pitches (spec + artifact page with visual options) | Fable high (+ Gemini: `brainstorm` / `ask-gemini`) | the owner (item by item) | The hardest thinking; Gemini is the creative check, the owner decides |
| Blender art (models, textures, sky faces) | Opus high | the owner on renders; Fable judge only for a wave's style recipe | Many render-inspect-fix loops at modest reasoning each; taste is the owner's |
| Plans for a multi-system wave (`docs/superpowers/plans`) | Fable high | Opus medium (reads the plan as a builder would, flags gaps) | A plan mistake costs a whole wave |
| Plan for a one-file fix | Opus medium | none (the fix's review covers it) | Cheap to redo |
| Reviews of a wave (the 3-lens review, the release review) | Fable xhigh | — | The law |
| Test fixes (a flaky scenario, a fixture, a mock gap) | Opus medium | Fable high **if an assertion changes**; none if only the fixture or a timing | Weakening an assertion is the one way a "test fix" lowers quality; everything else the suite re-checks |
| Log reading (gate logs, Output, journal) to name failures | Haiku medium (names the failing scenarios and the first error line) -> Opus medium if a cause is asked | — | Mechanical first pass, checkable by re-reading the log |
| Doc updates that a test reads (`README.md` tables, `smoke_p2_final`) | Sonnet medium | `p2final_docs` | The test catches a wrong number |
| Ledger, brain, BUILD_STATE, bug-inbox notes | Sonnet low | the next reader | Cheap and visible; a wrong line misleads one session, not a player |
| Merge gates (full `run_checks.sh`, rbxlx + `verify_place.py`, read the failure summary, decide) | Fable high | — | Judging; reads only the summary, decides merge / no merge |
| Uploads (meshes, textures, audio: the keyed cloud session) | Opus medium | the owner's OK first (standing rule), then the tool's own checks | The tool does the work; it is irreversible, so the OK and the dry run stay, not the model |
| Website work on Bosco (pages, CSS, copy) | Opus medium (Sonnet high for copy / CSS-only tweaks) | Chrome screenshots at phone + desktop width | A mistake is visible in the browser; no live data there. Anything that takes an order, a booking or a payment: Opus high + Fable high review |

Default when a job is not in the table: Opus high builder, Fable high reviewer (the law), then apply section 2.

## 2. What moves a job

**Up** (one is enough; two or more = ultracode, section 3): it touches saves, money, rewards, remote security
or live data; it is hard to undo (uploads, merges to main, schema changes, anything players keep); it touches many systems at
once (a wave with 4+ owners); there was a past failure in that area (the court pivot, the sky cube, berries dup, the mesh
preload order: those files get Fable review even for small edits); the mock cannot see the mistake (Studio-only behaviour).
Up means: the builder one effort step higher, the reviewer one model or effort step higher, never fewer steps.
Each item between semicolons counts once: a job that touches money and saves and live data is one Up item, not three. A save
or Cash that players keep does not make a job "hard to undo" as well; that item is for an upload, a merge or a schema change.

**Down** (all three must hold): the work is mechanical (wiring, renames, tables, notes); it is easy to check by eye or by
re-reading; a test or tool catches a mistake (`p2final_docs`, `check.mjs`, `verify_place.py`, the sims). Down means a
cheaper model or a lower effort for the builder only. The review, the gate and the owner's check never go down. A job that
is on the Up list never goes down, whatever else is true.

## 3. Whole-job levels

| Level | When | Shape (what runs) | Examples from this game |
|---|---|---|---|
| **Easy** (low) | notes, moves, one-line text fixes with a test, log summaries | one Agent call (Sonnet / Haiku low), the test or a re-read as evidence, commit | move a bug screenshot to `bugs/fixed/` with a note; update `BUILD_STATE.md` after a wave; fix a README number `p2final_docs` flagged |
| **Medium** | one system, one owner, a test exists or is written first | brainstorm (short) -> Opus medium build with `--only` tests -> Fable medium review -> one full `--quick` run | audio wiring of 47 sounds (every key in the smoke lists); a HUD pill moved (render_gui sheet); a balance number with the sim; bug #16 "F stays attack" |
| **High** (the default build) | a wave or feature of 2-5 tasks, several files, Studio-visible parts | brainstorm -> spec -> Fable high plan -> Opus high builders in parallel where files do not overlap -> Fable xhigh wave review (a job whose row in section 1 names its own review keeps it) -> fix -> full gate -> owner Studio check | the living sky (sky-skies), wave 6 fight focus, pet attack VFX, the mesh load priority fix |
| **Extra high** (xhigh) | saves, money, security, or a cross-mode re-tune; one Up item | as High, plus: Fable xhigh design review of the spec before the plan; Fable builds the data / money task itself; Fable xhigh adversarial review; the sims as gates; full gate twice (before and after the fix round) | the Phase 4 -> 5 home fold and berries migration; a remote security pass; the Phase 5 economy re-tune (`sim_tycoon --ring --dungeon`, C10 floor 115) |
| **Ultracode** | two or more Up items at once, or a release to main with players on it, or a second failure in the same area | section 3.1 | Phase 5 W0-W5 and Phase 6 W0-W3 as whole phases; the Robux shop (money + Roblox products + live data + shine GUI + many systems); a save-schema change every service reads; a long-lived branch merged to main |

### 3.1 What ultracode really does in a script

Several workflows in sequence, each with its own cache so a crash resumes. The stages and their patterns:

1. **Design**: 2-4 Fable xhigh designers on separate lenses (data, battle, home, world) -> one Fable xhigh judge writes the
   contract -> Opus medium "builder's read" flags what a builder could not implement -> the owner approves the pitch.
2. **Contract and shared edits** (W0): Fable high lead does the shared files, fixtures and the baseline gate log, so builders
   never race on the same file.
3. **Build waves**: Opus high builders, one owner per file set, `--only` tests while working; `data`, `security` and `money`
   tasks go to Fable high. Each wave ends with a lead gate (targeted scenarios + the wave's known-red list) and a notes file.
4. **Adversarial verification**: Fable max reviewers who play the exploiter and the unlucky player: call remotes out of
   order, double-join, leave mid-payout, rejoin mid-migration, a server dying during a save. Every confirmed finding becomes
   a regression scenario first, then a fix.
5. **Completeness critics**: Fable xhigh reads the contract against the diff and lists what is missing or quietly narrowed,
   with the contract line for each. No fixing in this stage, only the list.
6. **Loop until dry**: fix (Opus high) -> re-review (Fable high) until a review returns zero confirmed findings, with a cap
   (3 loops) and a written reason when the cap is hit. Findings must be confirmed with a failing check, not opinions.
7. **Release**: full `run_checks.sh` (both modes), rbxlx rebuild + `verify_place.py`, Fable high merge gate on the failure
   summary, owner Studio check of every Studio-only item, merge, ledger.

Ultracode earns its cost when a mistake reaches players' saves or wallets, or when many systems move at once and no single
reviewer can hold the whole change. It is **not** for a feature that one gate and one Fable review already cover.

**The cost of over-using it**: tokens and hours (a full gate is 20-30 minutes per loop, several loops, several reviewers at
max); the short-memory PC cannot hold it beside two running builds; review fatigue, where later loops return nitpicks that get
"fixed" and add churn, each fix needing its own gate; and it delays the owner's Studio check, which for sky, VFX and HUD is
the only real test. A High job run as ultracode is slower and no safer.

## 4. Where it sits

The router picks the model and effort first; the speed scout then changes only order and parallelism (never the route); the
memory limit of the PC caps how many agents run at once (fewer at a time when two builds share the machine), never which model
or effort they get.
