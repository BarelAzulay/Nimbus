# Mesh load priority (client preload + server load order)

Date: 2026-10-24. Size: small change (one module + its smoke scenarios). Owner decision: Claude (autonomous, per ABSOLUTE_RULES).

## Why
Studio Play test on 2026-10-24 (746 shipped keys): the server had every template `ready`, but the client preloads
them ONE at a time (`startClient` in `src/shared/MeshLibrary.lua`: one `pump`, FIFO in ChildAdded / server-ready order,
which is alphabetical). Measured ~5 keys/s, so a full preload takes ~150 s. `floor_plaza_courts` (the spawn court the
player stands on) dressed only at t = 108 s; at t = 52 s just 9 of 151 tagged world targets were dressed. A new player
sees the grey Part-built lobby for well over a minute.

## Goals
- What the player sees first dresses first: keys of `ML_Dress`-tagged targets near the camera, then keys something is
  waiting on (`OnReady` waiters: pets being built, other tagged targets), then everything else.
- Total client preload time drops (several preloads in flight at once).
- Server loads keys used by tagged world targets before the rest (instead of plain alphabetical).

## Non-goals / anti-goals
- No change to what a template looks like, to failure handling (`localBroken`, `Changed`, waiter release), to the
  `generation` restart semantics, to `Dress` / `Tag` / LOD behaviour, or to the empty-ids no-op path.
- No per-frame work; no unbounded concurrency; no new remotes.
- Anti-goal: a priority scheme that can starve a key forever (every queued key must still load).

## Approaches
1. **Client priority pick + bounded parallel workers + server tag-first order (chosen).** Fixes order and speed.
2. Server order only: cheap, but the client is the bottleneck (server was done long before the client).
3. Client parallel only: faster, but the lobby still waits behind ~400 pet / evolved keys.

## Decided
- New cfg field `ClientParallel` (default 6; tests may set it) next to `MaxParallel`.
- Client: queued keys are picked best-first each time a worker frees up (queue is small: a linear scan is fine).
  Rank: (0) key of a tagged target, nearer to the camera first (distance taken when the target was seen/tagged is
  fine); (1) key with registered waiters; (2) the rest in arrival order.
- Server: queue sorted so keys referenced by `ML_DressKey` of currently tagged targets come first (stable, then
  alphabetical as today).

## Left to the builder
- Exact data structures, how distance is captured, whether `_low` keys of tagged targets get rank 0 or 1.

## Proof
- `client_p6mesh` (or a new client scenario in `tools/smoke_p6_mesh.lua`): a near tagged target's key starts preloading
  before untagged keys queued earlier; no more than `ClientParallel` preloads in flight; more than one in flight when
  there is work; a failing key still releases its waiters. Server scenario: tagged keys load first.
- Gate: `tools/smoke.py --only` on the p6 mesh / lobby / lod / pets scenarios, then `tools/run_checks.sh --quick`.
- Studio: time until `floor_plaza_courts` is dressed (baseline 108 s).
