# Save session lock: design

Branch `session-lock` (cut from integration 80cd184 = lobby-shop + its fixes + 3D eggs + roll look + shop area). Owner-approved
2026-11-08 (`Projects Main/Nimbus/.superpowers/lobby-shop/LEDGER.md`, "Q2 full save session lock: YES, next build"; context lines 26
and 53). Route (`py -3.12 tools/pick_model.py --build game-feature --saves --money`): plan / build / review / fix / gate all
Fable 5.1 xhigh, "Fable xhigh design review of the spec before the plan; full gate twice"; no ultracode. Skills:
roblox-dev:roblox-datastores (session locking, UpdateAsync, retry / backoff, BindToClose, schema migration),
roblox-dev:roblox-security, superpowers:test-driven-development, superpowers:verification-before-completion.

Plan: `docs/superpowers/plans/2026-11-10-session-lock.md`. Every line number below is as of 80cd184.

## 1. The hole this closes

A player's save can be written by two live servers at once. Today's protections are the DELTA merge (`DataService.lua:178-218`:
every save sends "live minus Base" into `UpdateAsync` and merges it into whatever is stored; two servers cannot clobber each
other) and, for gems only, the 15 s **gem settle hold** (`DataService.lua:4664-4814`, `GemsSettled` at 6821; spec
`2026-11-07-lobby-shop-design.md` 5.2). The hold's own header says what it does not close (`DataService.lua:445-446`): "an old
server's save that lands after the settle read (a failed save retried as an orphan); the full fix is a session claim."

The concrete case (lobby-shop review round 1, LEDGER line 58): the player spends a forced Secret (500 gems, pity at Since 6) on
server A; A's leave save fails (outage / throttle) and A keeps the entry as an orphan (`DataService.lua:5033-5056`, retries
10 / 20 / 40 ... 120 s for 30 min); the player hops to server B; B loads with a plain `GetAsync` (`fetchProfile`,
`DataService.lua:4514`) and sees the OLD save (500 gems, Since 6); B's settle read 15 s later still sees it; B sells a second
forced Secret for the same 500 gems; A's orphan write lands and merges its -500 as a delta: Gems clamp at 0, the player keeps
two Secret pets for one price. The same shape exists for every currency and every one-time grant that is not already a twin
rule: Tokens, Cash, Berries, Food, Trophies, pets rolled, the tutorial gift of a brand-new player (no record exists yet, so
both servers think the player is new), Garden / Gym placements.

## 2. Goals and non-goals

Goals (the task's words, each with its section):
- a save is owned by one server at a time (3, 4, 6);
- a server that loads a save another LIVE server holds waits and retries, bounded, and never writes over newer data (6, 8);
- a crashed server's lock expires (5, 10);
- every write is guarded so a stale server cannot save (8);
- BindToClose and leave saves release the lock (9);
- existing saves migrate with no data loss (14);
- no new player-visible wait in the normal case, one server (6.4, 17);
- the gem settle hold keeps working or is retired only because the lock fully covers it, with tests (12);
- the cross-server pieces keep working: `Battle.Duels` (`DataService.lua:6482-6510`, `BattleService.lua:2547-2572`), the
  Trophies pair limit (`BattleService.lua:1497`, 2647), the TutorialStarter `MarkTrove` twin rule (`TutorialService.lua:1605-1692`,
  `DataService.lua:6081`) (13).

Non-goals: no new DataStore key or scope (the lock lives inside the save record); no MemoryStore / MessagingService (none is
used today: `grep MessagingService src` finds nothing); no change to the merge rules of 1.; no kick (the game has a mature
"provisional" mode for a save it cannot read yet, `DataService.lua:219-234`; a kick would be worse for a kids' game); no
change to the autosave cadence (`Config.Tokens.AutosaveSeconds = 90`, `Config.lua:425`); no Trophies pair-limit redesign
(a separate owner question, LEDGER line 60).

## 3. Where the lock lives: one key inside the save record

The stored record of `Config.Tokens.DataStoreName` / `u_<UserId>` gets one new optional top-level key:

```lua
Lock = { Id = "<server id>", Job = game.JobId, Place = game.PlaceId, At = <Unix seconds, os.time()> }
```

- `Id` is what ownership compares (section 4). `Job` and `Place` are diagnostics only (the `warn` texts print them).
- `At` is the time of the last write that carried this lock (claim, autosave, heartbeat, any save). `sanitizeTime`
  (`DataService.lua:659`) cleans it; a junk `At` makes the lock stale (section 10).
- `Lock` joins `KNOWN_TOP` (`DataService.lua:516-525`). Without that, `keepForeign` (`DataService.lua:3965-3992`) would copy a
  record's old `Lock` back into every record this version writes, and a release could never clear it. Being known also means a
  release that omits the key really removes it (the record is rebuilt from `toStored`, `DataService.lua:3864`, which never
  emits `Lock`; the write callback then sets or clears it explicitly, section 8).
- `normalizeProfile` (`DataService.lua:2912-3006`) reads named fields only, so `Lock` never enters a profile, `Base`
  (`DataService.lua:536`), `profilesEqual` (3009), a delta or the ProfileSync snapshot. The lock is record metadata, like
  `UpdatedAt` (`DataService.lua:4896`).
- **A lock-only record.** A brand-new player's claim (section 6.1) writes `{ Lock = {...} }` with no `Version` and no
  `Tokens`. `fetchProfile` treats a record with `Version == nil and Tokens == nil` exactly like `nil` ("nothing stored"):
  the v1 legacy lookup (`DataService.lua:4530-4546`) still runs, the profile is the defaults, `migrated` as today. Every real
  save writes `Version = 2` and `Tokens` (`toStored`), so no older record is ever mistaken for lock-only. This closes the
  new-player double gift of section 1 (two servers both "new").
- Older server builds (a rolling deploy) have no `Lock` in their `KNOWN_TOP`, so they keep it as foreign data untouched
  (`keepForeign`) and ignore it. They do not honour locks either: the guard is enforced only by servers on this build. Rolling
  deploys last minutes; accepted (section 14).

## 4. The server id

```lua
P8.Id = (game.JobId ~= "" and game.JobId) or ("studio-" .. HttpService:GenerateGUID(false))
```

- Live servers: `game.JobId` is unique per running server instance. Studio: `game.JobId` is `""`, so each Studio session
  gets `studio-<guid>`; two Studio windows with API access on the same account are two servers.
- **The mock.** `tools/robloxmock.lua:5622` gives every DataModel `JobId = "mock-job"`, and the existing two-server scenarios
  (`secondServer` in smoke_p4_data / p5_data / p7_data / pity / trove / tutorial_starter / fixr_data / daily / redo_* /
  raid_flow, about 35 blocks) clone the DataService module against the same mock store and the same `game`. All those copies
  therefore share one id: the lock treats them as ONE server with two caches, which is exactly what they test (the merge rules
  of section 1), so none of them needs a rewrite for the lock. A scenario that wants a REAL second server gives its copy its
  own id with `DataService._SetServerIdForTest(id)` (Studio and the mock only, `RunService:IsStudio()`, like `_SettleForTest`
  at `DataService.lua:6829`), before that copy's first `Load`.
- `P8` is the lock's helper table (the `P3` .. `P7` pattern, `DataService.lua:804-900`): no column-0 local per helper. New
  column-0 locals: `P8` and `HttpService` (DataService is at 160 of the 200 cap, `tools/count_locals.py`; `check.mjs` warns
  from 160 and errors at 200; budget after this build: <= 165).

## 5. Numbers: TTL, heartbeat, wait (`Config.Save`, new; `Config.lua` next to `Config.Tokens` at 419)

```lua
Config.Save = {
	LockSeconds = 360,      -- a lock whose At is this old (or older) is stale: a crashed server's lock expires (4 autosave sweeps)
	HeartbeatSeconds = 60,  -- a save with nothing to write still refreshes a lock at least this old: every 90 s sweep (review round 1; was 120)
	ClaimWaitSeconds = 12,  -- a load waits this long for a lock another live server holds, then plays provisionally (section 6.3)
	ClaimRetrySeconds = 3,  -- between two claim attempts while held: attempts at 0, 3, 6, 9, 12 s = 5 UpdateAsync calls at most
}
Config.Attr.SaveWaiting = "SaveWaiting" -- true while the load waits for, or the session is provisional because of, another server's lock
```

Why these: the autosave sweep runs every 90 s (`DataService.lua:7600-7639`) and writes only dirty entries (`writeEntry`
returns early on an empty delta, `DataService.lua:4886-4889`), so an idle player's lock would age for ever; the heartbeat
rule (section 7) makes the 90 s sweep refresh a lock aged >= 60, i.e. at every sweep (review round 1; with 120 it was every
other sweep, up to ~180-210 s between refreshes): the maximum age between two refreshes is about 90 s plus the sweep's spread
(0.25 s per entry, `DataService.lua:7634`, plus latency), well under 360. (An online session is dirty at every sweep anyway:
TycoonService refreshes `Home.LastSeen` every 15 s.)
360 s is the trade-off between two rare bad cases: after a server CRASH the player plays provisionally (section 6.3) for up
to `LockSeconds` + one autosave (the autosave's `writeEntry -> recover` claims, section 7) ~ 7.5 min; during an outage of
the old server's writes followed by a hop, the old server's unsaved minutes are lost to the guard (section 8). **The real
window (review round 1):** `Lock.At` is the time of the last LANDED write, so the new server can take the save once the
outage has lasted `LockSeconds` minus the lock's age when it began (at most ~90 s): about 270-360 s at 360, 1710-1800 s at
1800. Past it the old server's writes are refused even after the new server released the save (section 21). Both are the standard
session-lock trade-off; the owner can move the number (section 20). 12 s of wait covers the normal hop (a leave save lands in
one or two seconds) and one orphan retry (first at 10 s, `ORPHAN_RETRY_FIRST`, `DataService.lua:491`), and stays under the
loading screen's own `Config.Loading.MaxSeconds = 25` (`Config.lua:1272-1275`), so the wait is invisible except for the caption
(section 18).

## 6. Load: the claim

### 6.1 One UpdateAsync claims (replaces the plain GetAsync of the load path)

`fetchProfile(userId, attempts, claim)` (`DataService.lua:4514`) gains a third argument. With `claim == true` the v2 read is one
`UpdateAsync` whose callback is pure (it may run more than once; the last run's outcome, kept in upvalues, is the one used; the
code never depends on UpdateAsync's return value for a cancelled write):

```
callback(old):
  seen = old
  lock = P8.lockOf(old)                      -- { Id, At } sanitised, or nil
  if lock and lock.Id ~= P8.Id and not P8.stale(lock, now) then held = lock; return nil end   -- a live server owns it: no write
  held = nil
  rec = shallow copy of old (or {} when old is nil); rec.Lock = P8.lockRecord(now); return rec
```

The claim never rebuilds the record (no `normalizeProfile` / `toStored` inside it): only `Lock` changes, so a newer or older
build's fields stay as they are. `fetchProfile` returns as today (`fetched, profile, migrated, trimmed, moved`) plus a sixth
value `held` (the other server's `{ Id, At }`) when `fetched == false` because of a live lock. The settle read (while it still
exists, section 12) and the v1 legacy read keep `GetAsync`.

### 6.2 The wait policy (`P8.claimLoop(entry, userId)`, called by `loadEntry`, `DataService.lua:4598`)

Attempts are one `UpdateAsync` each (`fetchProfile(userId, 1, true)`: the loop is the retry).

| outcome of an attempt | then |
|---|---|
| claimed | done: the profile is the record seen; `entry.LockHeld = true`, `entry.LockAt = now`, `entry.HeldBy = nil` |
| held (a live lock, another id) | first time: the player attribute `SaveWaiting = true` (section 18); if `waited >= ClaimWaitSeconds` give up as **held**; else `task.wait(ClaimRetrySeconds)`, `waited += ClaimRetrySeconds`, try again |
| the call errored or `fetched == false` with no `held` (outage, throttle, no store) | `errors += 1`; two errors give up as **failed** (today's two attempts, `readKey` at 4492); else `task.wait(RETRY_DELAY)` (1.5 s) |

So a held load makes attempts at 0, 3, 6, 9 and 12 s (five) and stops; the whole loop is bounded by 12 + 1.5 s. (Review round
1: the 12 s are measured on the clock from the first attempt, `os.clock()`, and each sleep is at most what is left, so slow
calls do not stretch the wait: with 2 s calls the attempts run at 0, 5 and 10 s and the load gives up at 12 s, not 22 s.
The loop also stops at once when the server is closing.)
`waitForLoad` (`DataService.lua:4576`, today 4 s) waits up to `ClaimWaitSeconds + RETRY_DELAY + 4` s, and `saveEntry` (4937)
answers false while an entry is still `Loading` (nothing of a loading entry may be written).

### 6.3 Held after the wait: provisional, the recovery claims

`loadEntry` marks the entry exactly like a failed read today (`entry.LoadFailed = true`, `DataService.lua:4632`) and keeps
`entry.HeldBy`; `DataService.Load` (5151) then runs its existing provisional path: `scheduleRecovery` (4837, delays 20 / 40 /
80 / 160 / 300 s) and the stand-in rules of the header (`DataService.lua:219-234`: one-time grants, Home, teams, growth, Daily,
Trove, Pity and the Secret Roulette refuse; Tokens / Cash / Gems / Trophies earned merge as deltas; spends fail on a 0 balance).
`recover` (4818) reads in claim mode: `held` -> false (the loop tries again later); claimed -> `LockHeld = true`, the rebase and
`announceRebase` as today, `SaveWaiting` removed (attribute nil), and (section 12) `Settled`. `writeEntry` already calls
`recover` first for a provisional entry (4871-4875), so the 90 s autosave is a claim attempt too.

### 6.4 The normal case costs nothing visible

One server: the record is free (released at the last leave) or stale, the first attempt claims, `Load` returns as fast as
today (one DataStore round trip instead of one). A hop whose leave save already landed: the same. A hop with the leave save
still in flight: 3 s, at most 12 s, behind the loading screen. The settle hold's 15 s gem wait goes away (section 12), so the
player sees less waiting than before.

### 6.5 A quick rejoin (the cached entry, `DataService.lua:5168-5172`)

- `entry.LockHeld == true` (the leave's release write has not landed, or the entry is an orphan whose release failed): the
  record cannot have moved (only a stale steal could, section 10), so the cached profile is current and no store call is made,
  as today. **Review round 1:** only while the lock cannot have expired (`P8.trusted`: its last landed write is less than
  `LockSeconds - 30` s old). An older one claims again: a record that still holds this server's lock was not taken (rebase,
  nothing lost); any other record was taken by another server (perhaps released since), so the store wins and the stale
  session's unsaved changes are dropped; a failed read leaves the entry as it was (strict writes, `OwnsSave` false).
- `entry.LoadFailed == true` (provisional, held or outage): the recovery loop already runs; as today.
- `entry.Loaded and not LockHeld and not LoadFailed` (released, not yet dropped: a window of one deferred step): run the claim
  loop; the record may hold another server's data, so a claim that comes back different from `Base` rebases (`rebase` +
  `announceRebase`, the `settleRead` changed-case shape at 4696-4699). Review round 1: a re-claim that another server holds
  (or that fails for a released entry) plays on a true stand-in (defaults), never on the cached profile.
`Load` resets `entry.Leaving` (section 9) on every (re)join.

## 7. The heartbeat (idle players keep their lock fresh)

In `writeEntry` (`DataService.lua:4870`), when the delta is empty and the write is not a release: if `entry.LockHeld` and
`os.time() - entry.LockAt >= Config.Save.HeartbeatSeconds` and the Set/Update request budget is not low
(`GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) >= 10`, the `P7.readBudgetLow` shape at 4703), the
write goes ahead with the empty delta (the callback rebuilds the record as every save does and stamps `Lock.At = now`);
otherwise the early return stays. A skipped heartbeat is caught by the next sweep (the 360 s TTL leaves room for one skip).
Every successful non-release write sets `entry.LockHeld = true, entry.LockAt = now`.

## 8. The write guard (every write)

The save callback (`DataService.lua:4893-4898`) becomes:

```
callback(old):
  lock = P8.lockOf(old)
  if lock and lock.Id ~= P8.Id and not P8.stale(lock, now) then tripped = lock; return nil end   -- another live server owns it
  record = keepForeign(toStored(applyDelta(normalizeProfile(old), delta)), old); record.UpdatedAt = now
  record.Lock = release and nil or P8.lockRecord(now)
  return record
```

A `nil` return cancels the write (Roblox and the mock, `robloxmock.lua:6399`). When `tripped`:
- `warn("[DataService] another server owns the save of user <id> (lock <Id>, <age> s old): this server's unsaved changes are
  dropped")`, `entry.LockHeld = false`.
- No player here (an orphan, a late leave save, BindToClose for a departed player): `cache[userId] = nil`. Its delta can never
  be written: a stale server does not save. This is the case of section 1 (A's late write is refused instead of merged).
- The player IS here (the same account in two servers at once; theoretical): the store wins. ~~`rebase(entry, copyProfile(entry.Profile),
  normalizeProfile(seen), normalizeProfile(seen))` (the live profile becomes the stored one)~~ (review round 1: the session
  becomes a true stand-in, defaults, `P8.standIn`, and the recovery's claim brings the stored record in: a provisional entry
  never shows balances the owning server may be spending), the
  grant annotations `ReceiptGrants / DailyClaims / TroveGrants` and `Overwrite` cleared, `entry.LoadFailed = true`,
  `entry.HeldBy = tripped`, `scheduleRecovery`, `announceRebase`. A receipt granted in that session and never saved answers
  `NotProcessedYet` (GemService grants only after a successful save, `GemService.lua:13`), so Roblox asks again: no paid
  purchase is lost (section 11).
`writeEntry` returns false after a trip (the caller sees a failed save; the entry is gone or provisional, so nothing retries
the stale delta).

## 9. Release: leave, BindToClose, orphans

A write is a **release** (`record.Lock = nil`) when any of: the caller says so (`saveEntry(userId, "release")`),
`entry.Leaving == true`, or the player is not in this server (`Players:GetPlayerByUserId(userId) == nil`) at write time.

- `onPlayerRemoving` (`DataService.lua:5062`) sets `entry.Leaving = true` synchronously, then its deferred step calls
  `safeSave(userId, "release")` and `Release` as today. A release with an empty delta still writes when `entry.LockHeld`
  (the lock must go); with an empty delta and no lock held it writes nothing. So a leave costs one `UpdateAsync` (it did too,
  when the session was dirty).
- `PlayerService.onPlayerRemoving` drops its own `pcall(DataService.Save, player)` (`PlayerService.lua:575-577`; the comment
  there already defers the decision to DataService, whose deferred save runs after every other PlayerRemoving handler,
  `DataService.lua:5066-5070`). One write per leave instead of a possible second write inside Roblox's 6 s same-key window.
- `BindToClose` (`DataService.lua:7641-7667`): `pcall(saveEntry, userId, "release")` for every cache entry, in parallel as today,
  25 s cap kept. Studio without API access: `getStore()` is nil, nothing to release (as today).
- `entryIsClean` (`DataService.lua:4982`) also requires `entry.LockHeld ~= true`: an entry whose release write failed stays an
  orphan (`Release`, 5033; `settleOrphan`, 4991) and the orphan loop (5006) retries it (its writes are releases: the player is
  gone). After `ORPHAN_TIMEOUT` (1800 s) it is dropped as today; the record's lock then expires by TTL (section 10).
- A successful release sets `entry.LockHeld = false`.

## 10. Steal rules: when a lock is free

`P8.stale(lock, now)` is true when: `lock` is nil or not a table, `lock.Id` is not a string, `lock.At` is not a finite number,
`now - lock.At >= Config.Save.LockSeconds`, or `lock.At - now > Config.Save.LockSeconds` (a clock far in the future is junk),
or (**Studio rule**) `RunService:IsStudio()` and `lock.Id` starts with `"studio-"`: a Studio session treats another Studio
session's lock as free, so the owner who force-closes Studio is never locked out of their own test account for six minutes;
a lock from a LIVE server is honoured in Studio. The mock's default id is `"mock-job"`, so the Studio rule fires there only
for ids a test sets.

A stale lock is claimed outright (section 6.1) and the stale owner's next write trips the guard (section 8). A claim never
waits for a stale lock. Clocks: `os.time()` is Unix time on every Roblox server (NTP-synced; the existing clock-skew rules of
the Daily record assume the same, `P7.futureSlack`, `DataService.lua:2374`); the mock's `os.time()` follows the fake clock
(`robloxmock.lua:136-141`), so `advance(seconds)` ages a lock in tests.

## 11. Receipts while the save is locked elsewhere

`GemService.ProcessReceipt` (`GemService.lua:784-870`) is unchanged and now stronger: it grants only through
`DataService.MarkReceipt` (`DataService.lua:5883`), which answers nil until the profile is loaded and not provisional; the
callback waits up to `ProfileWaitSeconds = 12` and then answers `NotProcessedYet`, and Roblox calls again later. A receipt
arriving while the load waits for another server's lock, or while the session is provisional-held, is therefore
`NotProcessedYet`; once the claim lands it is granted once. A receipt granted on server A whose save failed: the player's hop
to B waits for A's lock; A's orphan retry lands with the receipt and its grant (the twin rule, `DataService.lua:200-202`); B's
`MarkReceipt` for the same purchase id answers false (`GemReceipts` holds it) and B grants nothing. `PurchaseGranted` is still
answered only after a successful save (a guard trip is a failed save: `NotProcessedYet`).

## 12. The gem settle hold is retired; its API stays as the lock's flag

The lock covers every case the hold covered: a late write from the old server is refused (guard), a slow leave save makes the
new server wait instead of reading stale data, an autosave in flight makes it wait too, and a crashed old server's lock
expires. So the 15 s wait and the read loop go (`P7.settleSeconds .. P7.recovered`, `DataService.lua:4672-4814`; the `SettleGen /
SettleFrom / SettleLoopGen / GemsSettled` entry fields; `P7.SETTLE_*` at 898-904; `Config.Gems.SettleSeconds` at 610-612).
What stays, so no caller changes:

- `DataService.GemsSettled(player)` = `DataService.OwnsSave(player)` (new, section 16): true when the profile is loaded, not
  provisional and this server holds the lock (`entry.LockHeld`; review round 1: and it cannot have expired, `P8.trusted`;
  the next landed write trusts it again and fires `Settled` if this load had not yet), or when there is no usable store (Studio without API access:
  nothing to own). Callers unchanged: `PetService.lua:1149-1152` (gem spins), `StoreService.lua:614-619` (GemBuy),
  `FusionService.lua:774-775` (gem Mix), the clients reading the attribute (`ShopEggs.lua:1242, 1280`, `ShopGems.lua:255`,
  `ShopController.lua:1876`).
- The player attribute `Config.Attr.GemsSettled = true`, written when the flag turns true (at `Load`, and at the recovery's
  claim), never written false (as today, `DataService.lua:440-441`).
- `DataService.Settled` fires once per load, after `ProfileLoaded` (or after `ProfileRebased` when the claim came through the
  recovery). `PetService.lua:1674-1675` listens to it for the pity attribute. Order change from today: `ProfileRebased`
  listeners now see `GemsSettled == true` (the hold is gone); `gem_settle` is rewritten to that rule.
- `DataService._SettleForTest(player)` returns `OwnsSave(player)` and does nothing else (Studio and the mock only). The 60+
  test call sites keep working; the two-server scenarios that call `B._SettleForTest(p)` "so B's one read lands first and B
  stays stale" (lobby-shop Task 3 deviation 1) get exactly that: no read at all.
- `contract.json` keeps both names (`tools/contract.json:236-237`) and gains `OwnsSave`, `_SetServerIdForTest`.

## 13. Cross-server pieces that must keep working (no change in rule)

- `Battle.Duels` (`DataService.lua:6482-6510`): `RecordDuel` is allowed while provisional (a union) and `DuelsWith` counts the
  record; `BattleService.lua:2547-2572` takes the highest of this server's list and both saves. A provisional-held session sees
  only its own duels for at most the wait + one recovery (20 s): accepted, noted.
- Trophies pair limit (`BattleService.lua:1497, 2647`) and `AddTrophies` (`DataService.lua:6513`, a delta, allowed while provisional).
- TutorialStarter: `TutorialService.lua:1640-1692` grants only when `MarkTrove(player, Starter.ASK, grant)` is true;
  `MarkTrove` (`DataService.lua:6081`) refuses on a stand-in (`P3.realEntry`, 6102); the lock now also keeps B from reading
  the store before A's write (B waits, or plays provisionally until A's write lands), so the twin rule is reached only by the
  path it was built for (two deltas with the same ask: ONE grant).
- Daily / Trove / Store / Pity merges (the header rules, `DataService.lua:183-218`) are untouched: they still run for a
  provisional session's deltas and for the stale-steal path.
- `tools/fixtures/DataService_phase3.lua` / `_phase4.lua` (older builds used by `p4data_rollout`, `p5flow_migrate`): they write
  without a lock of their own and keep `Lock` as foreign; the new server's claim and guard are unaffected.

## 14. Migration of existing saves, rollback

No schema change: `Version` stays 2, `Lock` is optional and absent in every existing record (= free). A record is never
rewritten just to add a lock; the first load after the deploy claims it. Rollback (deploying the previous build): old servers
ignore `Lock`, keep it as foreign and write freely (today's behaviour); a leftover lock on a record is stale after
`LockSeconds` for any later build. No data is read, moved or dropped by this build. The v1 legacy migration keeps working
through the lock-only record rule (section 3).

## 15. Studio and no-API behaviour

- Studio without "Enable Studio Access to API Services": `storeDisabled` (`DataService.lua:4427-4436`), no claim, no lock,
  everything from memory as today; `OwnsSave` answers true for a loaded profile (nothing to own), so gem actions work at once
  (today they waited 15 s with no read).
- Studio with API access: a real lock with id `studio-<guid>`; Stop fires BindToClose, which releases; the Studio rule of
  section 10 covers a force-close. A live server's lock on the owner's own account (they just left a live server) is honoured:
  the Studio join waits like any server.

## 16. The mock and the test hooks

The mock needs no change: `UpdateAsync` runs the callback on a storable copy and cancels on `nil` (`robloxmock.lua:6395-6405`),
`os.time()` follows the fake clock, `HttpService:GenerateGUID` exists (6685), `Mock.DataStore.Fail / FailOnly / FailCount /
Latency / Budget` (6337, 6361-6376) model outages, write-only failures, a low budget and slow calls; `Mock.Shutdown` (5673)
runs BindToClose. "Server B" is the existing `secondServer(name)` clone (e.g. `tools/smoke_tutorial_starter.lua:451-490`) plus
`B._SetServerIdForTest("B")`.

New public API (DataService; `tools/contract.json`):
- `OwnsSave(player) -> bool` as in section 12.
- `_SetServerIdForTest(id) -> id` sets `P8.Id` for this module copy (Studio / mock only; false elsewhere).
Entry fields (`DataService.lua:534-551` comment): `LockHeld`, `LockAt`, `HeldBy = { Id, At } | nil`, `Leaving`.

## 17. DataStore budget

Per player: load 1 `UpdateAsync` (+ up to 4 while held; + 1 legacy `GetAsync` for a player with no v2 record); autosave 1 write
per 90 s (dirty, or the heartbeat); leave 1 (+ 1 re-take when the player rejoined while it was in flight); BindToClose 1 per
entry. The Set/Update budget is 60 + 10 x players per minute: 30 players cost about 20 writes a minute plus joins. Reads drop
by the retired settle read (one `GetAsync` per join plus retries). Review round 1: Roblox removed the old 6 s same-key write
cooldown in 2023 (DevForum "Removal of 6s Cool Down for Data Stores"; the limits page now gives per-key throughput, 4 MB a
minute of writes, and queues a throttled key's requests); a throttled release fails like any failed save and is retried by
the orphan loop.

## 18. What the player sees

- Normal case: nothing new; gem actions no longer wait 15 s after a join.
- A hop whose leave save is still landing: the loading screen stays up to 12 s longer; while the attribute `SaveWaiting` is
  true its caption (`LoadingScreen.client.lua:439-441`, "Loading the sky... N%") reads **"Another server is still saving your
  progress..."**.
- Held after the wait (provisional): the world opens with a stand-in save; one toast (Notify kind "info", 6 s, from
  `Main.server.lua` on `player:GetAttributeChangedSignal(Config.Attr.SaveWaiting)`, the `Items refund toast` step shape at
  313-322): **"Your progress is still being saved by another server. Your pets and gems will show up in a moment."**;
  every refusal meanwhile is today's "Your save is still loading" / "Your data is still loading". When the claim lands
  (`SaveWaiting` nil after true): **"Your progress is back!"** (kind "good", 4 s) and the usual `ProfileRebased` re-sync.
- A guard trip: nothing to the player (their session on that server is over, or the store won and `ProfileRebased` re-synced).

## 19. File map

| File | Change |
|---|---|
| `src/shared/Config.lua` | `Config.Save` (section 5), `Config.Attr.SaveWaiting`; `Config.Gems.SettleSeconds` removed (section 12) |
| `src/server/Services/DataService.lua` | `KNOWN_TOP.Lock`; `P8` (id, lockOf, stale, lockRecord, claim, claimLoop, writeBudgetLow); `fetchProfile(.., claim)`; `loadEntry` wait policy; quick-rejoin rule; `writeEntry` guard + heartbeat + release; `saveEntry(userId, mode)` / `safeSave`; `onPlayerRemoving` Leaving + release; `BindToClose` release; `entryIsClean`; `recover` claims; `OwnsSave`, `_SetServerIdForTest`; the settle hold retired, `GemsSettled / _SettleForTest / Settled` kept as the flag; header comment |
| `src/server/Services/PlayerService.lua` | the leave `Save` call removed (section 9) |
| `src/server/Main.server.lua` | the two `SaveWaiting` toasts (section 18) |
| `src/first/LoadingScreen.client.lua` | the caption while `SaveWaiting` (section 18) |
| `tools/smoke_session_lock.lua` (new), `tools/smoke.py` | the scenarios of the plan |
| `tools/smoke_pity.lua` | `gem_settle` rewritten to the lock rule |
| `tools/contract.json` | `OwnsSave`, `_SetServerIdForTest` |
| `README.md`, `BUILD_STATE.md`, `brain.md`, `ARCHITECTURE_V3.md` (m8 note at 3024) | docs |

## 20. Decisions and owner questions

Decisions made here (the owner can overrule each):
1. Provisional play after the 12 s wait, not a kick (section 2).
2. `LockSeconds = 360`: ProfileStore-class libraries assume a dead session only after much longer; 6 min was chosen so a crash
   locks a player out of their real save for minutes, not half an hour, at the price of losing the unsaved minutes of a
   session whose server's writes failed for 6+ minutes while the player hopped. **Question:** 360 (my pick) or 1800? (The
   real window is `LockSeconds` minus the lock's age when the outage began, at most ~90 s: section 5.)
3. The settle hold retired with its API kept (section 12), not kept beside the lock: the lock covers all of it, and keeping
   both means two waits for one risk.
4. The Studio rule (section 10): a Studio server treats another Studio lock as free.
5. The lock-only record for brand-new players (section 3) so the tutorial gift cannot double on a first-minute hop.
6. `PlayerService`'s leave save removed (section 9): one write per leave.

## 21. Review round 1 (2026-11-10)

What changed in the rules above (DataService `P8.trusted`, `P8.ours`, `P8.standIn`; tests `lock_stale_cache`):

1. **A cached lock is trusted only while it cannot have expired**: `LockSeconds - 30` s after its last landed write (`entry.LockAt`
   is now the lock's `At` as written). Past that, a rejoin claims again (6.5), `OwnsSave` / `GemsSettled` answer false (12), and
   every write is **strict**: it goes ahead only into a record that still holds THIS server's lock. Before, the guard refused only a
   record holding another server's *live* lock, so a stale orphan (writes failing 6+ min, the player hopped, the new server took
   the save, played, and released it) merged its old delta into the new server's record: the double spend of section 1 for every
   currency, and the cached profile was served to a rejoin as current.
2. **A provisional entry is always a true stand-in** (defaults): the store-wins trip (8) and a re-claim of a cached entry that
   another server holds no longer show the record seen or the cached profile, whose balances the owning server may be spending
   (Tokens / Cash spends have no provisional gate; a stand-in's 0 balance is the gate). The dropped unsaved changes are the guard's
   rule (8); a receipt grant among them answers `NotProcessedYet` and Roblox asks again.
3. **A leave during a held load still releases**: an entry still `Loading` is never clean, so `Release` keeps it as an orphan
   whose retry writes the release once the load ends (a claim that lands after the leave save gave up waiting used to stamp a
   lock nobody released for `LockSeconds`); `Load` keeps the orphan flag for a player who already left; BindToClose waits for
   such a load and releases it too.
4. **A release that lands after the player rejoined is followed by a re-take** (one guarded `UpdateAsync`, skipped like a
   heartbeat under a low budget), so the player is not left on an unlocked record with `OwnsSave` false until the next sweep; a
   non-release write fires `Settled` for a load that was not settled yet (once per load, as before).
5. **The held wait is counted on the clock** (6.2); **HeartbeatSeconds 60** (5); the real hop window is stated in 5 and 20.
6. Not taken: the review's premise of a 6 s same-key write cooldown (attempts landing at 0, 6, 12, 18, 24 s), with its
   `ClaimRetrySeconds = 6`, a mock cooldown and GetAsync polling: Roblox removed that cooldown in 2023 (section 17).
