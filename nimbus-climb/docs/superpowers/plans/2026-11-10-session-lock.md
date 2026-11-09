# Save Session Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Also name and use superpowers:test-driven-development (every task writes its failing scenarios first and runs them RED before any game code), superpowers:verification-before-completion (run the commands, read the output, before any "done"), roblox-dev:roblox-datastores (session locking, UpdateAsync purity, retry / backoff, BindToClose, migration) and roblox-dev:roblox-security (the lock is a money guard: never trust a stale server).

**Goal:** A player's save is owned by one server at a time: a lock record inside the save, claimed by one `UpdateAsync` at load, refreshed by every save and by a heartbeat, honoured by every write (a stale server cannot save), released by the leave save and BindToClose, expiring after a crash; the gem settle hold retires into the lock's flag; receipts, the duel / trophy records and the TutorialStarter twin rule keep working; old saves need no migration.

**Architecture:** Everything lives in `DataService.lua` behind a new helper table `P8` (the `P3 .. P7` pattern): `fetchProfile` gains a claim mode (one `UpdateAsync` whose pure callback takes or refuses the lock), `loadEntry` runs a bounded wait loop (attempts at 0 / 3 / 6 / 9 / 12 s) and falls back to today's provisional path whose recovery claims, `writeEntry` guards every write and stamps or clears the lock, the leave save and BindToClose write releases. The existing two-server smoke scenarios keep working untouched because every DataService copy in the mock shares `game.JobId = "mock-job"` (one server, two caches); the new scenarios give server B its own id with `_SetServerIdForTest`.

**Tech Stack:** Luau in plain Lua 5.1 syntax, Rojo layout, the mock harness `py -3.12 tools/smoke.py --quick --only <names>` (lupa; `tools/robloxmock.lua`), `node tools/check.mjs`, `py -3.12 tools/count_locals.py`.

**Spec:** `docs/superpowers/specs/2026-11-10-session-lock-design.md` (sections are cited as "spec N" below). Every line number is as of 80cd184.

## How every task runs

- Worktree `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\session-lock\nimbus-climb`, branch `session-lock` (cut from integration 80cd184). The path has Hebrew characters: in PowerShell `Set-Location -LiteralPath "<worktree>"` first, then relative paths; or `git -C "<worktree>" ...`. Read `ABSOLUTE_RULES.md` and `brain.md` first, then the spec whole. `tools\node_modules` is installed; if it goes missing run `npm install` in `tools` once.
- **Memory is LOW on this PC (about 3 GB) and another test run may be going:** only targeted smoke lists (`py -3.12 tools/smoke.py --quick --only a,b,c`), one run at a time, never the whole suite, never `client_replay`, never two smoke processes side by side.
- Route (`py -3.12 tools/pick_model.py --build game-feature --saves --money`): plan / build / review / fix / gate Fable 5.1 xhigh (Opus 5.5 at the same effort while Fable is out of credits); "full gate twice" means: the lists below after each task, and the whole suite once on a free machine before any merge (not here).
- Tests first: each task writes its failing scenario(s), runs them RED, builds, runs them GREEN, then the regression lists it names, one list at a time. A test a task's change breaks is rewritten to the new rule in the same task, never deleted; the commit body names each rewritten assertion and why.
- Before each commit: `node tools/check.mjs` -> 0 errors (the 5 old many-locals warnings may stay); `py -3.12 tools/count_locals.py src/server/Services/DataService.lua src/server/Services/PlayerService.lua src/server/Main.server.lua src/first/LoadingScreen.client.lua` -> DataService <= 165 (today 160), PlayerService <= 34, Main.server <= 60, LoadingScreen <= 26.
- Staging by name (`git add <path>...`), never `git add -A` / `.` / `-a`. Commit with a message file: `git commit -F "<scratchpad>\msg.txt"`, every message ending with exactly these two lines, then `git push origin session-lock`:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01ACtM8qc8ts2NyGHrZh7vyT`
- After each push append one dated line under a `## session-lock` heading in `C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.superpowers\lobby-shop\LEDGER.md` (hash, what landed, the lists that passed with their counts, every rewritten assertion, deviations).
- No uploads, no merges, no force-push, no Studio, no Rojo start / stop, no touching other worktrees.

## Global Constraints

- The lock is ONE optional top-level key `Lock = { Id, Job, Place, At }` of the save record, in `KNOWN_TOP`, never in a profile / `Base` / delta / snapshot; `Version` stays 2; no new DataStore key (spec 3, 14).
- `Config.Save = { LockSeconds = 360, HeartbeatSeconds = 120, ClaimWaitSeconds = 12, ClaimRetrySeconds = 3 }`; `Config.Attr.SaveWaiting = "SaveWaiting"`; `Config.Gems.SettleSeconds` removed in Task 2 (spec 5, 12).
- The server id `P8.Id = (game.JobId ~= "" and game.JobId) or ("studio-" .. HttpService:GenerateGUID(false))`; `_SetServerIdForTest` works only where `RunService:IsStudio()` (spec 4).
- Every `UpdateAsync` callback is pure and non-yielding; outcomes travel through upvalues, never through UpdateAsync's return value for a cancelled write (spec 6.1, 8).
- A load never waits more than `ClaimWaitSeconds + RETRY_DELAY` (13.5 s); the normal case (free or stale lock) is one round trip (spec 6.2, 6.4).
- A write for a player who is not in this server, or who is leaving, is a release (`Lock = nil`); a release with an empty delta still writes while the entry holds the lock (spec 9).
- A stale server never writes: a tripped guard drops an orphan's entry, or (player present) lets the store win and goes provisional (spec 8).
- No kick anywhere (spec 2). Player texts exactly as spec 18.
- Sources ASCII; plain Lua 5.1 syntax; `warn` texts start with `[DataService]` (the smoke warning filters allow that prefix).
- Scenario names, file names and the `smoke.py` registration lines exactly as written below (`smoke.py` reports an unlisted scenario or file as a failure, `tools/smoke.py:31-33`).

## Review Focus

1. A brand-new player who hops within the first minute (no record before this build): both servers must not grant the tutorial gift / starter twice -> `lock_rejoin_migrate` step "new player: the lock-only record makes B wait" (Task 1).
2. The leave save of a DIRTY session lands at the same moment the new server's claim runs: whichever UpdateAsync is second must see the first (the claim waits on a fresh lock; the save is refused by a foreign lock) -> `lock_two_servers` steps "B waits while A's leave save is in flight (Latency)" and "A's late write is refused" (Task 1).
3. A failing Set/Update budget or a throttled heartbeat must not spam writes nor lose the lock within the TTL -> `lock_claim_release` steps "a low UpdateAsync budget skips the heartbeat" and "two sweeps later the lock is fresh again" (Task 1).
4. A receipt that arrives while the save is held elsewhere must be `NotProcessedYet`, then granted exactly once -> `lock_receipts_cross` step "receipt while held" (Task 2).
5. The settle hold's 60+ test call sites and the client's `GemsSettled` attribute must keep their meaning after the retirement (true = gem actions allowed; absent while provisional / held) -> `lock_settle_flag` and the rewritten `gem_settle` (Task 2).

## File map

| File | Task | Change |
|---|---|---|
| `src/shared/Config.lua` | 1, 2 | `Config.Save`, `Config.Attr.SaveWaiting` (1); `Config.Gems.SettleSeconds` removed (2) |
| `src/server/Services/DataService.lua` | 1, 2 | `KNOWN_TOP.Lock`, `P8`, claim mode, wait loop, guard, heartbeat, release, `OwnsSave`, `_SetServerIdForTest`, header comment (1); the settle hold retired into the flag, `Settled` timing (2) |
| `src/server/Services/PlayerService.lua` | 1 | the leave `Save` call removed (lines 575-577) |
| `src/server/Main.server.lua` | 2 | the two `SaveWaiting` toasts |
| `src/first/LoadingScreen.client.lua` | 2 | the caption while `SaveWaiting` |
| `tools/smoke_session_lock.lua` (new), `tools/smoke.py` | 1, 2 | `lock_claim_release`, `lock_two_servers`, `lock_rejoin_migrate` (1); `lock_receipts_cross`, `lock_settle_flag`, `client_lock_loading` (2) |
| `tools/smoke_pity.lua` | 2 | `gem_settle` rewritten to the lock rule |
| `tools/contract.json` | 1 | `OwnsSave`, `_SetServerIdForTest` in DataService's list (next to `GemsSettled`, line 236) |
| `README.md`, `BUILD_STATE.md`, `brain.md`, `ARCHITECTURE_V3.md` | 2 | docs |

---

### Task 1: The lock core: claim, wait, guard, heartbeat, release, migration

Spec: 3, 4, 5, 6, 7, 8, 9, 10, 14, 15, 16, 17. Skills: roblox-dev:roblox-datastores, roblox-dev:roblox-security, superpowers:test-driven-development, superpowers:verification-before-completion.

**Files:**
- Create: `tools/smoke_session_lock.lua`
- Modify: `tools/smoke.py` (one registration line after line 528), `src/shared/Config.lua:419-427` (`Config.Save` after `Config.Tokens`) and `:71-102` (`Config.Attr.SaveWaiting`), `src/server/Services/DataService.lua` (header 175-257 and 387-450, `KNOWN_TOP` 516-525, the cache-entry comment 534-551, locals 552-564, `P7` 888-904 -> a `P8` table after it, `fetchProfile` 4514-4548, `waitForLoad` 4576, `loadEntry` 4598-4637, `recover` 4818-4834, `writeEntry` 4870-4935, `saveEntry` 4937 / `safeSave` 4961 / `Save` 4973, `entryIsClean` 4982, `onPlayerRemoving` 5062-5078, `Load` 5151-5205, `BindToClose` 7641-7667), `src/server/Services/PlayerService.lua:575-577`, `tools/contract.json:236`
- Test: `tools/smoke_session_lock.lua` (server world, booted; the `smoke_pity.lua` file shape: lines 1-66 boilerplate, `secondServer` at 195-230)

**Interfaces:**
- Consumes: `Mock.DataStore` (`Data`, `Fail`, `FailOnly`, `FailCount`, `Latency`, `Budget`, `Calls`, `Writes`; `robloxmock.lua:6337`), `Mock.Shutdown(30)` (5673), `Mock.AddPlayer / RemovePlayer`, `K.advance / config / mod / moduleInstance / waitFor / needBoot / flushErrors / flushWarnings / remotesFor / logSize` (`tools/smoke_common.lua`), `Mock.Output` (warn texts, the `data_orphans` shape at `smoke_server.lua:3468-3474`).
- Produces (Task 2 relies on these exact names):
  - `DataService.OwnsSave(player) -> boolean` (loaded, not provisional, `entry.LockHeld == true`; or no usable store).
  - `DataService._SetServerIdForTest(id: string) -> string | false` (sets `P8.Id` for this module copy; false outside Studio / the mock).
  - `fetchProfile(userId, attempts, claim) -> fetched, profile, migrated, trimmed, moved, held` (`held = { Id, At }` when a live lock refused the claim).
  - `saveEntry(userId, mode) -> boolean`, `safeSave(userId, mode)`; `mode == "release"` clears the lock.
  - `P8.Id`, `P8.lockOf(raw) -> { Id, At } | nil`, `P8.stale(lock, now) -> boolean`, `P8.lockRecord(now) -> { Id, Job, Place, At }`, `P8.claimLoop(entry, userId) -> the fetchProfile tuple`, `P8.writeBudgetLow() -> boolean`.
  - Entry fields: `LockHeld`, `LockAt`, `HeldBy`, `Leaving`.
  - `Config.Save.*`, `Config.Attr.SaveWaiting`; the attribute `SaveWaiting = true` while waiting / provisional-held, nil after the claim lands.

- [ ] **Step 1: Write the failing scenarios** in `tools/smoke_session_lock.lua`. Header comment in the repo's style (what each scenario proves, "White-box: ... Plain Lua 5.1 syntax only."). Boilerplate from `tools/smoke_pity.lua:1-66` (`SmokeCommon.T`, `guarded`, `CONTEXT`, `serverScenarios()` with `K = _G.K`, `DS()`, `newUserId` from 987600, `join(prefix, uid)` = `Mock.AddPlayer` + `advance(1.2)`, `leave(p)`, `storeKey(uid)`, `stored(uid)`, `oldRecord(extra)`) and `secondServer(name)` from `smoke_pity.lua:195-230` (clone the module, keep the connection marks, `release()`), plus `local function serverB(name, id) local B, clone, rel = secondServer(name); if B then B._SetServerIdForTest(id) end; return B, clone, rel end`. Export `return { server = serverScenarios }` the way `smoke_pity.lua` ends its server half (copy its tail). Three scenarios:

  `S.lock_claim_release = guarded("lock_claim_release", function() if not K.needBoot() then return end ...`:
  - config: `T.eq(Config.Save.LockSeconds, 360)`, `HeartbeatSeconds 120`, `ClaimWaitSeconds 12`, `ClaimRetrySeconds 3`, `T.eq(Config.Attr.SaveWaiting, "SaveWaiting")`; `T.check(type(D.OwnsSave) == "function" and type(D._SetServerIdForTest) == "function")`.
  - claim at load: `DSt.Data[storeKey(uid)] = oldRecord({ Gems = 40 })`; `local calls = DSt.Calls; p = join("LockClaim", uid)`; `T.check(DSt.Calls == calls + 1, "one UpdateAsync claims (no extra GetAsync)")`; `local lock = stored(uid).Lock`; `T.check(type(lock) == "table" and lock.Id == "mock-job" and lock.Job == "mock-job" and lock.Place == 1 and lock.At == os.time())`; `T.eq(D.OwnsSave(p), true)`; `T.eq(D.GetGems(p), 40, "the claim's record is the profile")`; `T.check(stored(uid).Version == 2 and stored(uid).Gems == 40, "the claim changed only Lock")`; `T.eq(p:GetAttribute("SaveWaiting"), nil)`.
  - heartbeat: nothing dirty; `local at0 = stored(uid).Lock.At; advance(95)` (one sweep) `T.eq(stored(uid).Lock.At, at0, "age 95 < 120: no heartbeat write")`; `advance(90)` -> `T.check(stored(uid).Lock.At >= at0 + 180 - 2 and DSt.Data[storeKey(uid)].Gems == 40, "the 180 s sweep refreshed the lock, nothing else changed")`.
  - a low UpdateAsync budget skips the heartbeat: `DSt.Budget.UpdateAsync = 5; local at1 = stored(uid).Lock.At; advance(180)`; `T.eq(stored(uid).Lock.At, at1)`; `DSt.Budget.UpdateAsync = nil; advance(180)`; `T.check(stored(uid).Lock.At > at1, "two sweeps later the lock is fresh again")`.
  - a dirty save refreshes: `D.AddGems(p, 1); advance(92)`; `T.check(stored(uid).Gems == 41 and stored(uid).Lock.At >= os.time() - 92)`.
  - release at leave: `local writes = DSt.Writes; leave(p)`; `T.check(DSt.Writes == writes + 1, "one release write at leave (PlayerService no longer saves twice)")`; `T.eq(stored(uid).Lock, nil, "the leave save released the lock")`; `T.check(stored(uid).Gems == 41)`; the entry is gone (the `data_orphans` C proof, `smoke_server.lua:3451-3453`): `DSt.Data[storeKey(uid)].Gems = 7`, rejoin, `T.eq(D.GetGems(p2), 7, "the entry was dropped after the release (the rejoin reads the store)")`, leave.
  - a failed release keeps the orphan and retries it: join, `D.AddGems(p, 2)`, `DSt.FailOnly = "UpdateAsync"; DSt.Fail = true; leave(p)`; `T.check(stored(uid).Lock ~= nil, "the lock is still in the record")`; `DSt.Fail = false; DSt.FailOnly = nil; advance(12)` (the first orphan retry at 10 s) -> `T.eq(stored(uid).Lock, nil)` and `Gems == 9`.
  - a clean-but-locked orphan is not dropped before its release lands: join, no change, `DSt.Fail = true; leave(p)`; `advance(1)`; rejoin -> `T.eq(D.OwnsSave(p3), true, "the quick rejoin finds the cached entry (LockHeld) with no store call")` (`DSt.Calls` unchanged across the rejoin); `DSt.Fail = false; leave(p3); advance(1)`; `T.eq(stored(uid).Lock, nil)`.
  - BindToClose releases everyone: two players joined, one dirty; `local finished = Mock.Shutdown(30)`; `T.check(finished)`; both records `Lock == nil`, the dirty one saved. (Reset: `Mock.CloseCallbacks` is consumed by the real `shutdown` scenario later in the run; after this step re-arm nothing: `Mock.Shutdown` only runs the callbacks and `shuttingDown` becomes true in DataService. **So this step must run LAST in the file's server half and the file must be registered right before `"shutdown"`.** If `shuttingDown` would break later scenarios in the same run, move this check into `smoke_server.lua`'s `shutdown` scenario instead (add `T.eq(stored.Lock, nil)` there) and say so in the commit body.)
  - Studio / no store: `local D2, clone2, release2 = secondServer("DataServiceLockNoApi")`; `DSt.Unavailable = true` -> `D2.Load(q)` -> `T.eq(D2.OwnsSave(q), true, "no usable store: nothing to own, OwnsSave true")`; `DSt.Unavailable = false; release2()`.
  - `K.flushErrors("lock_claim_release"); K.flushWarnings("lock_claim_release", { "[DataService]" })`.

  `S.lock_two_servers = guarded("lock_two_servers", ...)`. **How "server A" is modelled in the mock:** the mock has ONE Players list and the booted DataService (id `"mock-job"`) loads every added player, so the booted server plays B (the server the player arrives at) and server A is a lock record seeded BY HAND before the join: `DSt.Data[k] = oldRecord({ Gems = 500, Lock = { Id = "server-A", Job = "mock-job", Place = 1, At = os.time() } })`. A's leave save landing is modelled by hand too (what spec 9's release write does): `DSt.Data[k].Gems = <A's final value>; DSt.Data[k].Lock = nil`. A clone with its own id (`serverB(name, "server-A")`) is used only where a REAL second module copy must act (the guard trip from the other side); `scheduleRecovery` stops when the player leaves Players (`DataService.lua:4850`), so the player stays in the mock's Players for every recovery check.
  - B waits while A holds: seed as above; `local calls = DSt.Calls; p = Mock.AddPlayer("LockHop" .. uid % 1000, uid); advance(1)`; `T.eq(p:GetAttribute("SaveWaiting"), true, "the SaveWaiting attribute is set at the first held attempt")`; `T.eq(D.GetProfile(p), nil, "no profile while the load waits")`; `advance(10)`; `T.check(DSt.Calls - calls == 4, "attempts at 0, 3, 6, 9 s so far (one UpdateAsync each)")`; `advance(2.6)`; `T.check(DSt.Calls - calls == 5 and D.IsProvisional(p) == true and D.GetProfile(p) ~= nil, "after the 5th attempt at 12 s the load gives up: provisional")`; `T.eq(p:GetAttribute(Config.Attr.ProfileLoaded), true)`; `T.check(stored(uid).Lock.Id == "server-A", "A still owns the record")`; `T.check(D.GetGems(p) == 0 and D.SpendGems(p, 1) == false and D.GetPity(p) == nil, "a stand-in: 0 gems, nothing to spend, no pity")`.
  - A's release lets B's recovery claim: `DSt.Data[k].Gems = 0; DSt.Data[k].Lock = nil` (A's leave save landed with the 500 spent); a `ProfileRebased` counter (`countUid`, `smoke_pity.lua:613-620`); `advance(20)` (the first recovery, 20 s after the give-up); `T.check(D.IsProvisional(p) == false and D.OwnsSave(p) == true and stored(uid).Lock.Id == "mock-job", "the recovery claimed")`; `T.eq(D.GetGems(p), 0, "this server shows A's spend, not the stale 500")`; `T.eq(p:GetAttribute("SaveWaiting"), nil)`; `T.eq(rebased.n, 1)`.
  - the stale steal: a new uid; seed `Lock = { Id = "server-C", Job = "x", Place = 1, At = os.time() - 360 }`; `Mock.AddPlayer` + `advance(1.2)`; `T.check(D.OwnsSave(p) == true and stored(uid).Lock.Id == "mock-job" and p:GetAttribute("SaveWaiting") == nil, "a lock aged LockSeconds is taken at once")`; a lock aged 359 is waited on (seed `At = os.time() - 359`, add, `advance(1)`, `SaveWaiting == true`; then `advance(2.5)`: the second attempt at 3 s finds it aged 362 -> claimed, `SaveWaiting nil`, `OwnsSave true`).
  - junk locks are free: seed `Lock = { Id = 5, At = "x" }` -> claimed at once; seed `Lock = { Id = "server-D", At = os.time() + 400 }` (far future) -> claimed at once.
  - the Studio rule: seed `Lock = { Id = "studio-abc", At = os.time() }` -> claimed at once (the mock is Studio); seed `Lock = { Id = "mock-job2", At = os.time() }` -> waited on.
  - a second module copy with its own id waits too: `local A, cloneA, releaseA = serverB("DataServiceLockA", "server-A")`; fresh uid, `oldRecord({ Gems = 500 })`; `p = Mock.AddPlayer(...)`, `advance(1.2)` (the booted server claims and owns the record); `task.spawn(A.Load, p); advance(13)` -> `T.check(A.IsProvisional(p) == true and stored(uid).Lock.Id == "mock-job", "a real second copy waits on this server's fresh lock and goes provisional")`; `releaseA()`.
  - the guard with the player present (the store wins): same player; `DSt.Data[k].Lock = { Id = "server-A", Job = "a", Place = 1, At = os.time() }` (another live server took the record by hand); `D.AddGems(p, 1)`; `local writes = DSt.Writes; advance(92)` (the autosave) -> `T.check(DSt.Writes == writes and stored(uid).Gems == 500, "the write is refused: the record holds another live lock")`; a warn in `Mock.Output` contains `"another server owns the save"`; `T.check(D.IsProvisional(p) == true and D.GetGems(p) == 500, "the player is here: the store wins, provisional until the lock frees")`; `DSt.Data[k].Lock = nil; advance(92)` -> `T.eq(D.OwnsSave(p), true)`.
  - the guard on an orphan (the ledger's case: A's late write): `D.AddGems(p, 3)`; `DSt.FailOnly = "UpdateAsync"; DSt.Fail = true; Mock.RemovePlayer(p); advance(1)` (the leave save fails: an orphan holding +3); `DSt.Fail = false; DSt.FailOnly = nil; DSt.Data[k].Lock = { Id = "server-A", Job = "a", Place = 1, At = os.time() }` (the player's new server took the record meanwhile); `advance(12)` (the orphan retry at 10 s) -> `T.check(stored(uid).Gems == 500 and stored(uid).Lock.Id == "server-A", "the orphan's late write is refused: a stale server never saves")`; `DSt.Data[k].Lock = nil; DSt.Data[k].Gems = 9`; rejoin -> `T.eq(D.GetGems(p2), 9, "the stale entry was dropped: the rejoin reads the store")`.
  - B waits while A's leave save is in flight (Latency): `DSt.Latency = 2`; A clone holds p's record (seed A's fresh lock); `Mock.AddPlayer` (B's claim is refused at 0 s); at 1 s model A's release landing: `DSt.Data[k].Lock = nil`; `advance(2.5)` -> B's 3 s attempt claims: `OwnsSave true`, `SaveWaiting nil`; `DSt.Latency = 0`.
  - `flushErrors`, `flushWarnings` with `{ "[DataService]" }`.

  `S.lock_rejoin_migrate = guarded("lock_rejoin_migrate", ...)`:
  - new player: the lock-only record: fresh uid, no record; `Mock.AddPlayer` + `advance(1.2)`; `local rec = stored(uid)`; `T.check(type(rec) == "table" and rec.Version == nil and rec.Tokens == nil and type(rec.Lock) == "table" and rec.Lock.Id == "mock-job", "a brand-new player's claim writes a lock-only record")`; `T.eq(D.GetTokens(p), 0)`; a clone `B = serverB("DataServiceLockNewB", "server-B")`: `task.spawn(B.Load, p); advance(1)` -> `B.GetProfile(p) == nil` and `SaveWaiting == true` ("the lock-only record makes B wait"); `advance(13)` -> `B.IsProvisional(p) == true`; `B.GetTutorial(p) == nil` and `B.MarkTrove(p, "TutorialStarter", nil) == false` ("no gift decided on the stand-in"); release B's clone.
  - leave with nothing earned writes a full default record without a lock: `leave(p)`; `rec = stored(uid)`; `T.check(rec.Version == 2 and rec.Tokens == 0 and rec.Lock == nil)`.
  - the v1 migration still works through a lock-only record: fresh uid; `DSt.Data[Config.Tokens.LegacyDataStoreName .. "/u_" .. uid] = { Tokens = 33 }`; join -> `T.eq(D.GetTokens(p), 33)`; `T.check(stored(uid).Lock ~= nil and stored(uid).Tokens == nil, "the lock-only record exists, the tokens are not written yet")`; `D.AddTokens(p, 1); advance(92)` -> `stored(uid).Tokens == 34`; leave; `T.check(DSt.Data[legacyKey] ~= nil and DSt.Data[legacyKey].Tokens == 33, "the legacy store is never written")`.
  - an old record (no Lock) loads without migration and is written back with Version 2 and the lock: `DSt.Data[k] = oldRecord({ Gems = 5 })`; join; `T.check(stored(uid).Version == 2 and stored(uid).Gems == 5 and stored(uid).Lock.Id == "mock-job")`; leave -> `Lock == nil`, `Gems == 5`.
  - a forward-compatible record keeps a newer field across the claim and the release: `DSt.Data[k] = oldRecord({ Future = { x = 1 }, Version = 3 })`; join; `T.check(stored(uid).Future.x == 1 and stored(uid).Version == 3)`; `D.AddGems(p, 1); advance(92)`; `T.check(stored(uid).Future.x == 1 and stored(uid).Version == 3 and stored(uid).Lock ~= nil)`; leave -> `Future.x == 1`, `Lock == nil`.
  - the quick rejoin while the release is pending: join, `D.AddGems(p, 2)`, `DSt.FailOnly = "UpdateAsync"; DSt.Fail = true; Mock.RemovePlayer(p); advance(0.5)`; `local calls = DSt.Calls; p2 = Mock.AddPlayer(same uid); advance(1.2)`; `T.check(DSt.Calls == calls and D.GetGems(p2) == 2 and D.OwnsSave(p2) == true, "the cached entry still holds the lock: no store call, the gems are there")`; `DSt.Fail = false; DSt.FailOnly = nil; leave(p2)`.
  - `waitForLoad`'s new bound: a Save during a held load answers false and writes nothing: seed a fresh foreign lock, `Mock.AddPlayer`, `advance(0.5)`, `T.eq(D.Save(p), false)`; `DSt.Data[k].Lock = nil`; `advance(3)` -> `OwnsSave true`.
  - `flushErrors`, `flushWarnings`.

- [ ] **Step 2: Register** in `tools/smoke.py` after line 528:
  `if p5("smoke_session_lock.lua"): server_files.append("smoke_session_lock.lua"); ins(server_scenarios, "shutdown", ["lock_claim_release", "lock_two_servers", "lock_rejoin_migrate"])  # [session-lock T1] the save session lock: claim at load, wait / provisional, guard, heartbeat, release, migration (smoke_session_lock.lua: server world, booted)`
  (Task 2 grows this line.) Add `"OwnsSave", "_SetServerIdForTest"` after `"_SettleForTest"` in `tools/contract.json:237`.

- [ ] **Step 3: Run the new scenarios RED**

Run: `py -3.12 tools/smoke.py --quick --only lock_claim_release,lock_two_servers,lock_rejoin_migrate`
Expected: FAIL at the first checks (`Config.Save` nil, `OwnsSave` missing, the record has no `Lock`); the contract check reports the two missing names only when `contract` is in the list (it is not here; Step 6 runs it).

- [ ] **Step 4: Build the lock core in `DataService.lua`** (spec 3-10, 14-17; signatures from the Interfaces block):
  - `Config.lua`: `Config.Save` block after `Config.Tokens` (spec 5, with the spec's comments), `Config.Attr.SaveWaiting = "SaveWaiting"` after `GemsSettled` (line 102).
  - `KNOWN_TOP.Lock = true` with a one-line comment (spec 3); `local HttpService = game:GetService("HttpService")` next to the other services (454-457); the cache-entry comment gains `LockHeld`, `LockAt`, `HeldBy`, `Leaving`.
  - `local P8 = { Id = ..., }` after `P7` (888-904): `P8.Id` per spec 4; `P8.lockOf(raw)` (a table `raw.Lock` with a string `Id` and a finite `At` -> `{ Id, At = sanitizeTime(At) }`, else nil), `P8.stale(lock, now)` (spec 10 rules in that order, the Studio rule last), `P8.lockRecord(now)` (`{ Id = P8.Id, Job = game.JobId, Place = game.PlaceId, At = now }`), `P8.writeBudgetLow()` (`GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 10`, pcall; an unanswered call counts as enough), `P8.claim(dataStore, key)` (one `UpdateAsync` with the spec 6.1 callback; returns `ok, seenRaw, held`), `P8.claimLoop(entry, userId)` (spec 6.2 table exactly; sets `entry.HeldBy` and the `SaveWaiting` attribute on the first held attempt; returns `fetchProfile`'s tuple).
  - `fetchProfile(userId, attempts, claim)`: with `claim`, `P8.claim` replaces `readKey` for the v2 read; a record with `Version == nil and Tokens == nil` counts as nothing stored (the legacy lookup runs); the sixth return `held`.
  - `loadEntry`: `P8.claimLoop` replaces the `pcall(fetchProfile, userId)`; on `fetched` set `entry.LockHeld = true, entry.LockAt = os.time(), entry.HeldBy = nil`; on held / failed `entry.LoadFailed = true` (today's branch). The quick-rejoin rule of spec 6.5 (`entry.Loaded and not entry.LockHeld and not entry.LoadFailed` -> the claim loop, then rebase when the record differs from `Base`). `Load` resets `entry.Leaving = false`.
  - `waitForLoad`: bound `Config.Save.ClaimWaitSeconds + RETRY_DELAY + 4`; `saveEntry` returns false while `entry.Loading`.
  - `recover`: `fetchProfile(userId, 1, true)`; held -> false; on success `LockHeld = true, LockAt = now, HeldBy = nil`, the attribute removed (`SetAttribute(attr, nil)` under pcall), then the rebase / announce as today.
  - `writeEntry(entry, userId, mode)`: `release = mode == "release" or entry.Leaving == true or Players:GetPlayerByUserId(userId) == nil`; the heartbeat rule (spec 7) before the empty-delta early return; a release with an empty delta and `not entry.LockHeld` returns true without a write; the spec 8 callback with `tripped` / `seen` upvalues; after a trip the spec 8 handling (warn text exactly `"[DataService] another server owns the save of user %s (lock %s, %d s old): this server's unsaved changes are dropped"`), return false; after a successful write `entry.LockHeld = not release; entry.LockAt = now`.
  - `saveEntry(userId, mode)` / `safeSave(userId, mode)` pass the mode; `DataService.Save(player)` passes `"release"` when `player.Parent == nil`.
  - `entryIsClean`: `and entry.LockHeld ~= true`.
  - `onPlayerRemoving`: `local entry = cache[player.UserId]; if entry then entry.Leaving = true end` first, then the deferred `safeSave(player.UserId, "release")` + `DataService.Release(player)`.
  - `BindToClose`: `pcall(saveEntry, userId, "release")`.
  - `DataService.OwnsSave(player)`, `DataService._SetServerIdForTest(id)` (IS_STUDIO only) next to `IsProvisional` (5316).
  - The header: a new design note "Session lock" under "Design notes" (what the lock is, the numbers, the guard, the release, the Studio rule, the mock's shared id) and the two new API lines under "Extras".
  - `PlayerService.lua:575-577`: remove `pcall(DataService.Save, player)`; the comment becomes "Saving and freeing the profile cache entry are DataService's: its own PlayerRemoving handler saves (a release write, deferred after every other handler) and releases."

- [ ] **Step 5: Run the new scenarios GREEN**

Run: `py -3.12 tools/smoke.py --quick --only lock_claim_release,lock_two_servers,lock_rejoin_migrate`
Expected: all checks pass, 0 failed; warnings only `[DataService]` ones the scenarios allow.

- [ ] **Step 6: Regression lists, one run at a time** (each: 0 failed, or the assertion is rewritten to the new rule and named in the commit body; known new-rule effects to expect: a joined player always leaves a v2 record; one write per leave; heartbeat writes in long idle runs; a `Lock` key on the record of an online player):

Run A: `py -3.12 tools/smoke.py --quick --only boot,players,persistence,data_orphans,fixleave_ring,fixleave_rejoin,economy,contract,config_shape,shutdown`
Run B: `py -3.12 tools/smoke.py --quick --only p7data_fields,p7data_store_merge,p7data_daily_merge,p7data_trove_merge,p7data_provisional,p7data_reset,trove_two_servers,trove_provisional,trove_stale_once,tut_starter_restricted,tut_starter_more,tut_starter_two_servers,daily_two_servers`
Run C: `py -3.12 tools/smoke.py --quick --only p2data_profile,p2data_save,p2data_keys,p3data_teams,p3data_battle,p3data_save,p4data_save,p4data_migrate,p4data_rollout,p4data_dev,p4data_growth,p5data_berries,p5data_berries_merge,p5data_settings,p5data_team3,p5data_evo_untouched,polish_data_outage,polish_data_dev_reset,polish_data_fwdcompat`
Run D: `py -3.12 tools/smoke.py --quick --only secret_pity_save,gem_settle,secret_pity,p2gems_receipts,fixsrv_receipt_merge,fixsrv_prestige_merge,p2flow_arrive,p2flow_build,p2flow_prestige,p2flow_fusion_gems,p2flow_rejoin,p5flow_new,p5flow_merge,p5flow_migrate,p5flow_rejoin,raid_flow_hop,raid_flow_oldsave,fixr_data_wrongclock_day,fixr_data_daily_stamp,fixr_data_clamp_twin,fixr_data_revert_twin,fixr_data_prestige_cash,fixr_data_petlevel`
Expected: each run 0 failed. `gem_settle` still passes in Task 1 (the hold is untouched here; its settle read stays a GetAsync).

- [ ] **Step 7: Mutation checks** (each turns at least one new scenario red, then is reverted): (1) the guard removed from the save callback; (2) `KNOWN_TOP.Lock` removed; (3) the release never clears `Lock`; (4) the heartbeat rule removed; (5) `P8.stale` always false. Note the result in the commit body.

- [ ] **Step 8: Checks and commit**

Run: `node tools/check.mjs` -> 0 errors; `py -3.12 tools/count_locals.py src/server/Services/DataService.lua src/server/Services/PlayerService.lua` -> DataService <= 165, PlayerService <= 34.

```bash
git add tools/smoke_session_lock.lua tools/smoke.py tools/contract.json src/shared/Config.lua src/server/Services/DataService.lua src/server/Services/PlayerService.lua
git commit -F "<scratchpad>\msg.txt"   # "feat(session-lock): save session lock core: claim at load, bounded wait, write guard, heartbeat, release at leave / BindToClose, lock-only record for new players" + tests, lists, rewrites, mutations, deviations, the two trailer lines
git push origin session-lock
```
Then the ledger line (`## session-lock` in the lobby-shop LEDGER).

---

### Task 2: Receipts, the settle hold retired, cross-server pieces, player messaging, docs

Spec: 11, 12, 13, 18, 19, 20. Skills: roblox-dev:roblox-datastores, roblox-dev:roblox-security, superpowers:test-driven-development, superpowers:verification-before-completion, roblox-dev:roblox-ui (the caption and the toasts).

**Files:**
- Modify: `tools/smoke_session_lock.lua` (two server scenarios + a client half), `tools/smoke.py` (the Task 1 line grows), `tools/smoke_pity.lua` (`gem_settle`, lines 560-1000 region: rewritten), `src/server/Services/DataService.lua` (4664-4814 removed; `GemsSettled` 6821, `_SettleForTest` 6829, `Load` 5151-5205, `recover` 4818, `P7.SETTLE_*` 898-904, header 428-450), `src/shared/Config.lua:610-612`, `src/server/Main.server.lua:313-322` (a new step after it), `src/first/LoadingScreen.client.lua:439-441`, `README.md` (the DataService / saving paragraph), `BUILD_STATE.md` (one dated entry), `brain.md` (one dated decision line), `ARCHITECTURE_V3.md:3024` (the m8 note)
- Test: `tools/smoke_session_lock.lua`

**Interfaces:**
- Consumes (Task 1): `OwnsSave`, `_SetServerIdForTest`, `Config.Save`, `Config.Attr.SaveWaiting`, the entry fields `LockHeld / LoadFailed / HeldBy`, the recovery's claim.
- Produces: `DataService.GemsSettled(player) == DataService.OwnsSave(player)`; `DataService._SettleForTest(player)` returns `OwnsSave(player)` (IS_STUDIO only, no read); `DataService.Settled` fires once per load right after `ProfileLoaded` when `OwnsSave` is true, else right after the `ProfileRebased` of the recovery that claimed; the `GemsSettled` attribute written true at those moments; `Config.Gems.SettleSeconds` gone; the attribute `SaveWaiting` drives the loading caption and two toasts.

- [ ] **Step 1: Write the failing scenarios**

  Server half, `S.lock_receipts_cross = guarded("lock_receipts_cross", ...)` (booted; `GemService = mod("GemService")`, `TutorialService`, `BattleService` through `K.moduleInstance` + `require` as `smoke_pity.lua:651-660` does):
  - receipt while held: seed a record with a fresh foreign lock (`Id = "server-A"`); `p = Mock.AddPlayer(...)`; `advance(0.5)`; `task.spawn` `GemService.ProcessReceipt({ PlayerId = uid, PurchaseId = "lock-r1", ProductId = <the first gem pack's id from Config.Gems.Products>, CurrencySpent = 1, PlaceIdWherePurchased = 1 })` capturing the decision; `advance(12.6)` -> `T.eq(decision, Enum.ProductPurchaseDecision.NotProcessedYet, "a receipt while the save is held elsewhere is NotProcessedYet")`; `T.eq(D.GetGems(p), 0)`; model A's release (`Lock = nil`); `advance(20)` (the recovery claims); call `ProcessReceipt` again with the same receipt -> `PurchaseGranted`, gems = the pack's amount, `stored(uid).GemReceipts["lock-r1"] ~= nil`; a third call -> `PurchaseGranted` and the gems unchanged ("granted once").
  - a receipt A already stored is not granted again on B: seed `oldRecord({ Gems = 300, GemReceipts = { ["lock-r2"] = os.time() } })` (free lock); join; `ProcessReceipt("lock-r2")` -> `PurchaseGranted`, `GetGems == 300`.
  - TutorialStarter across the hop (the `tut_starter_two_servers` premise under the lock; server A is a hand-seeded record as in Task 1's `lock_two_servers`): take the policy install, `onSpinStep`, `petCount`, `hasAsk`, `PET` / `ASK` helpers from `smoke_tutorial_starter.lua:440-548`; seed `oldRecord({ Trove = { [ASK] = true }, Pets = { [PET] = 1 }, Lock = { Id = "server-A", Job = "a", Place = 1, At = os.time() } })` (A granted the starter and still holds the record; its write has not released yet); join with the restricted policy on; `advance(12.6)` -> `D.IsProvisional(p) == true`; `onSpinStep(p)` -> `T.check(petCount(p, PET) == 0 and D.MarkTrove(p, ASK, nil) == false, "the stand-in grants nothing: no ask decided before A's write is read")`; release A by hand (`Lock = nil`); `advance(20)` -> `T.check(D.GetTrove(p)[ASK] == true and petCount(p, PET) == 1, "A's grant arrived with the claim")`; `onSpinStep(p)` again -> `petCount(p, PET) == 1` ("ONE starter").
  - duels and trophies across the hop: seed `Battle = { Trophies = 10, Duels = { { U = 555, T = os.time() - 60 } } }` with a fresh foreign lock; join; `advance(12.6)` (provisional) -> `D.DuelsWith(p, 555, os.time() - 3600) == 0` ("the stand-in knows no duels yet"), `D.RecordDuel(p, 777, os.time()) == true` and `D.AddTrophies(p, 5)` -> `true, 5` ("allowed while provisional: a union / a delta"); release by hand; `advance(20)` -> `D.DuelsWith(p, 555, os.time() - 3600) == 1 and D.DuelsWith(p, 777, os.time() - 3600) == 1` ("the merge kept both") and `select(2, D.AddTrophies(p, 0)) == 15` ("10 + 5").
  - `flushErrors`, `flushWarnings` (`{ "[DataService]", "[GemService]" }`).

  `S.lock_settle_flag = guarded("lock_settle_flag", ...)`:
  - `T.eq(Config.Gems.SettleSeconds, nil, "Config.Gems.SettleSeconds is gone")`; `T.check(type(D.GemsSettled) == "function" and type(D._SettleForTest) == "function" and type(D.Settled) == "table")`.
  - a normal load is settled at once: `countUid(D.Settled, uid)` counter; join -> `D.GemsSettled(p) == true and p:GetAttribute("GemsSettled") == true and fires == 1 and DSt.Calls == calls + 1` ("no settle read: one UpdateAsync for the whole load"); `advance(30)` -> `fires == 1` ("never twice"); `D._SettleForTest(p) == true`.
  - a held load is not settled: fresh foreign lock, add, `advance(12.6)` -> `GemsSettled false`, attribute nil, `fires == 0`, `D._SettleForTest(p) == false`; a gem Mix (the `smoke_pity.lua:650-687` setup) is refused `"Your data is still loading"`; `PetService.BuyRoulette(p, <a gem roulette>, "Gems")` refused the same; release by hand; `advance(20)` -> `GemsSettled true`, attribute true, `fires == 1`, and a `ProfileRebased` probe recorded `GemsSettled == true` at fire time (the hold is gone: spec 12).
  - no store: a clone with `DSt.Unavailable = true` -> `GemsSettled(q) == true` at once.
  - `flushErrors`, `flushWarnings`.

  Client half (`CONTEXT == "client"`), `S.client_lock_loading = guarded("client_lock_loading", ...)`: the `client_p5loading` shape (`smoke_p5_menu.lua:223-258`: run `src/first/LoadingScreen.client.lua` with `Mock.RunScript`, find `Caption`): with `LocalPlayer:SetAttribute("SaveWaiting", true)` and `ProfileLoaded` nil the caption reads exactly `"Another server is still saving your progress..."`; `SetAttribute("SaveWaiting", nil)` -> within 0.5 s the caption is back to `"Loading the sky... N%"`; then `ProfileLoaded = true` -> the screen reaches `Done` as today. Also (server world is not available here) the toasts are checked in `lock_settle_flag`: `K.remotesFor("Notify", uid, mark)` holds, in order, the "still being saved" text (kind "info", 6) when the provisional-held play began and `"Your progress is back!"` (kind "good", 4) after the claim; no toast at all for a normal join.

- [ ] **Step 2: Register**: the Task 1 line in `tools/smoke.py` becomes
  `if p5("smoke_session_lock.lua"): server_files.append("smoke_session_lock.lua"); client_files.append("smoke_session_lock.lua"); ins(server_scenarios, "shutdown", ["lock_claim_release", "lock_two_servers", "lock_rejoin_migrate", "lock_receipts_cross", "lock_settle_flag"]); ins(client_scenarios, "client_final", ["client_lock_loading"])  # [session-lock T1/T2] the save session lock: claim, wait / provisional, guard, heartbeat, release, migration, receipts, the cross-server pieces, the settle flag, the loading caption (smoke_session_lock.lua: both worlds)`

- [ ] **Step 3: Run RED**

Run: `py -3.12 tools/smoke.py --quick --only lock_receipts_cross,lock_settle_flag,client_lock_loading`
Expected: FAIL (`SettleSeconds` still 15, `GemsSettled` false right after a load, no toasts, the caption unchanged).

- [ ] **Step 4: Build**
  - `DataService.lua`: delete `P7.settleSeconds .. P7.recovered` (4672-4814) and `P7.SETTLE_*`; `GemsSettled(player)` returns `DataService.OwnsSave(player)`; `_SettleForTest(player)` returns `IS_STUDIO and DataService.OwnsSave(player) or false`; a helper `P8.settled(entry, player)` writes the `GemsSettled` attribute true and fires `Settled` once per load (`entry.SettledFired`, reset in `Load` on every (re)join) when `OwnsSave`; `Load` calls it after `ProfileLoaded:Fire` (and the announcements), `recover` after `announceRebase`; the two `P7.newSettle` calls in `Load` (5164, 5175) and `P7.recovered` in `recover` (4832) go; the header's `GemsSettled / _SettleForTest / Settled` text (428-450) rewritten to the flag.
  - `Config.lua`: remove `SettleSeconds` and its comment (610-612).
  - `Main.server.lua`: a step `"Save wait toasts"` after the items-refund toast (322): for every player (PlayerAdded + the current list) `player:GetAttributeChangedSignal(Config.Attr.SaveWaiting):Connect(...)`: value `true` after the profile is loaded (`player:GetAttribute(Config.Attr.ProfileLoaded) == true`) -> Notify `"Your progress is still being saved by another server. Your pets and gems will show up in a moment."`, `"info"`, 6; `nil` after a true -> `"Your progress is back!"`, `"good"`, 4 (the `Remotes.Get("Notify"):FireClient` call under pcall as at 319-321; track "was true" per player, cleared on PlayerRemoving). While the attribute is true but the profile is not loaded yet (the 12 s wait) no toast: the caption covers it.
  - `LoadingScreen.client.lua:439-441`: `ui.Caption.Text = LocalPlayer:GetAttribute("SaveWaiting") == true and "Another server is still saving your progress..." or ("Loading the sky... " .. percent .. "%")` (the attribute name through `St.Config.Attr.SaveWaiting` when Config is there, `"SaveWaiting"` otherwise, the `ProfileLoaded` pattern at 417); the poll (545) already re-runs `showProgress`: make the caption refresh when the attribute changes even if the progress value did not (`force`).
  - `tools/smoke_pity.lua` `gem_settle`: rewrite to the lock rule, keeping its four parts' intent: (1) settled at once after a load, no read, `Settled` once, the attribute; the quiet-read checks become "no extra ProfileSync / ProfileRebased / TeamsChanged after a load" over 20 s; (2) a gem x1 / x3 spin and a token spin: a held load (foreign fresh lock by hand) refuses gem spins `"Your data is still loading"` and charges nothing, a token spin on the stand-in is `"Not enough Tokens"` (0 balance) or works once tokens are added (a delta); (3) the hop with the pity: the old server's record (`Gems 0`, `Pity.Secret = { Spins = 7, Hit = 7 }`) is what this server reads once the lock frees, never the stale Since 6: seed the stale state with a fresh foreign lock, add the player, release by hand with the new state, `advance(20)`, `SecretPityLeft == 7`, the next spin not forced; (4) `GemBuy` while held toasts `"Your data is still loading"`, sells after the claim. Delete the backoff / budget / 15 s parts (they test code that no longer exists) and say so in the commit body with the old assertion names.
  - Docs: `README.md`'s saving paragraph (one sentence: "one server owns a save at a time: a lock inside the record, claimed at load, refreshed by every save, released at leave; another server waits up to 12 s, then plays a stand-in save until the lock frees"); `BUILD_STATE.md` a dated `2026-11-10 (session lock, branch session-lock ...)` entry in the file's shape (what changed, the calls made = spec 20, the lists run with counts, what is not looked at in Studio); `brain.md` one dated decision line pointing at the spec and plan; `ARCHITECTURE_V3.md:3024` m8: append "(2026-11-10: the session lock landed, spec docs/superpowers/specs/2026-11-10-session-lock-design.md)".

- [ ] **Step 5: Run GREEN**

Run: `py -3.12 tools/smoke.py --quick --only lock_receipts_cross,lock_settle_flag,client_lock_loading,gem_settle`
Expected: 0 failed.

- [ ] **Step 6: Regression lists, one at a time** (0 failed each, or rewritten to the new rule and named):

Run E (gems / pity / store): `py -3.12 tools/smoke.py --quick --only secret_pity_save,gem_settle,secret_pity,p2gems_receipts,p2gems_policy,p2gems_roulettes,p2gems_altar,p2gems_secret_altar,fixsrv_receipt_merge,gem_potion_buy,gem_prices,store_remote,store_router,store_passes,store_grantpet,egg_spin_x1,egg_spin_x3,egg_full_stack,egg_roll_pure`
Run F (the two-server and twin-rule scenarios that call `_SettleForTest`): `py -3.12 tools/smoke.py --quick --only p2fusion_upgrade,p2fusion_mix,p2fusion_exploits,evo_rarity_saves,daily_two_servers,p7data_daily_merge,fixr_data_wrongclock_day,fixr_data_daily_stamp,tut_starter_restricted,tut_starter_more,tut_starter_two_servers,trove_two_servers,p3data_battle,raid_flow_hop,p2flow_arrive,p2flow_build,p2flow_prestige,p2flow_fusion_gems`
Run G (docs, contract, boot, the loading screen and HUD clients): `py -3.12 tools/smoke.py --quick --only boot,contract,config_shape,p2final_docs,evo_docs,client_p5loading,client_notify,client_hud,client_shop_eggs,client_shop_gems,client_fasthatch_setting,lock_claim_release,lock_two_servers,lock_rejoin_migrate`
Expected: each run 0 failed.

- [ ] **Step 7: Mutation checks** (each turns a scenario red, then reverted): (1) `GemsSettled` returns true for a provisional entry; (2) `Settled` fires twice; (3) the "back" toast removed; (4) the caption ignores the attribute. Note the result.

- [ ] **Step 8: Checks and commit**

Run: `node tools/check.mjs` -> 0 errors; `py -3.12 tools/count_locals.py src/server/Services/DataService.lua src/server/Main.server.lua src/first/LoadingScreen.client.lua` -> DataService <= 165 (the settle code removed should bring it down), Main.server <= 60, LoadingScreen <= 26.

```bash
git add tools/smoke_session_lock.lua tools/smoke.py tools/smoke_pity.lua src/shared/Config.lua src/server/Services/DataService.lua src/server/Main.server.lua src/first/LoadingScreen.client.lua README.md BUILD_STATE.md brain.md ARCHITECTURE_V3.md
git commit -F "<scratchpad>\msg.txt"   # "feat(session-lock): receipts and the cross-server pieces under the lock, the gem settle hold retired into OwnsSave, the save-wait caption and toasts, docs" + the lists, the gem_settle rewrite (old assertion names), mutations, deviations, the trailer lines
git push origin session-lock
```
Then the ledger line, and under the LEDGER's "Questions for the morning": spec 20's question (LockSeconds 360 vs 1800) with my pick 360.

---

## Self-review notes (done while writing)

- Spec coverage: 3 (Task 1 Steps 1 "claim at load", 4), 4 (Task 1: `_SetServerIdForTest`, `serverB`), 5 (Task 1 config checks), 6 (Task 1 `lock_two_servers` wait / provisional / recovery), 7 (heartbeat steps), 8 (guard steps: player present, orphan), 9 (release at leave / failed release / BindToClose / PlayerService), 10 (stale / junk / future / Studio rule), 11 and 13 (Task 2 `lock_receipts_cross`), 12 (Task 2 `lock_settle_flag`, `gem_settle`), 14 (`lock_rejoin_migrate`: old record, forward field, v1), 15 (no-store steps), 16 (the hooks), 17 (the call counts in the claim and heartbeat steps), 18 (Task 2 caption + toasts), 19 (file map), 20 (the ledger question).
- Names used across tasks: `OwnsSave`, `_SetServerIdForTest`, `Config.Save.*`, `Config.Attr.SaveWaiting`, `saveEntry(userId, mode)`, `P8.*`, `entry.LockHeld / LockAt / HeldBy / Leaving / SettledFired`: the same in both tasks.
- Proportion: the plan decides the mock modelling of "server A" (a pre-seeded foreign lock, released by hand, because the mock's one Players list cannot hold the same account on two live module copies with different ids without the booted server reclaiming it); the implementer writes the bodies.
