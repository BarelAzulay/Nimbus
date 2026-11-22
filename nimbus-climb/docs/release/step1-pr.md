# Release step 1: quick-wins to live, Store off, save gates passed

**Base:** `main` (`ac552d0`). **Head:** `qw-step1-gate` = `quick-wins` (`cfa377c`) plus the gate commits.
**Do not merge before the owner says yes in chat.**

## What this is

quick-wins goes live with its new save code (the session lock, the Store / Daily / Trove fields), the leaderboards
and the new Shop window. The Robux Store stays **off** behind one Config line.

## What players get

- The new Shop window with the **Eggs** tab only.
- Daily gifts, the Sky Trove chest, the lobby leaderboard, titles, the session lock.
- No Robux item, no gem potion, no "Coming soon" card, no purchase prompt.

## Gate 1: the Store switch

`Config.Store.Enabled = false`. Change that one line to `true` later to turn the Store on.

| While it is off | |
|---|---|
| Client | The Shop rail shows Eggs only. Packs, Passes, Boosts, the "Robux items" divider, every card, PREVIEW, "The Shop opens soon!", the gem potion and the token packs are hidden. No price lookup. A hidden tab asked by name opens Eggs. Same on PC, phone landscape and phone portrait. |
| Server | `StoreRequest` "Buy" and "GemBuy" are refused for those items: no prompt, no charge, no toast. The preview flag is false for everyone. |
| Still on | Receipts and passes. A paid receipt is granted, an owned pass counts. Tested for a token pack, a potion, the Starter Pack, a gem pack and two passes. |
| On | Unchanged. All older Store lists run with the switch on and pass. |

**What main sells today:** nothing for Robux. Main has four gem packs in `Config.Gems.Products`, all with product id 0,
so none is shown and none can be bought. Main does spend gems: roulette spins and the Secret Roulette. Those work
the same with the switch off. If a gem pack gets a product id later, it is shown and sold with the switch off too
(the Gems tab then appears with the gem packs only).

Tests, red first then green:

| List | Result |
|---|---|
| `store_switch_shipped,store_switch_off,store_switch_on` (new, server) | red: 13 failed. green: 193 passed, 0 failed |
| `client_store_switch,client_store_switch_mobile` (new, client + phone) | red: 44 failed. green: 590 passed, 0 failed |
| `store_doubles … store_token_lock` (10 lists) | 425 passed, 0 failed |
| `p2gems_*` (6) | 331 passed, 0 failed |
| `fixr_store_*`, `gem_settle`, `gem_potion_buy`, `gem_prices` | 379 passed, 0 failed |
| `trove_*`, `lobby_trove_plaza`, `shop_prompt`, `shop_globe`, `shop_egg_row` | 455 passed, 0 failed |
| `client_store_*` (6) | 593 passed, 0 failed |
| `client_fixr_store_*`, `client_fixr_boost_*`, `client_daily_vip` | 485 passed, 0 failed |
| `client_shop_*` (8) | 1174 passed, 0 failed |
| `client_trove`, `client_trove_mobile`, `client_gem_icon` | 654 passed, 0 failed |

Counts are the totals of each run (boot checks included). Looked at: `render_gui.py shop:off` at 1920x1080, 844x390
and 390x844, and `shop:offgems` at 1920x1080.

## Gate 2: the save round trip

`py -3.12 tools/save_roundtrip.py`: **260 checks, 0 failed.** Main's real code (`ac552d0`, read from git) and this
branch run as separate servers on one fake DataStore. No real store, no key.

| Phase | Checks | What it proves |
|---|---|---|
| build | 9 | Main's own save code wrote the fake saves: a new player, a maxed player (892 stored values, 33 pets at 99, 12 hybrids, 100 receipts, Cash 9.8e14), two saves with missing fields, two v1 saves, one empty. |
| load | 59 | Each save loads here as a real, owned save. Main's reading and this branch's reading are compared field by field. The record this branch stores equals the record main stores after the same session. |
| rollback | 148 | Main reads what this branch wrote, at once, with no error and no warning, with every main field and the progress made here. Main's save carries the new fields through. This branch reads it again with everything there. |
| lock | 44 | Two real servers on one save: wait, stand-in, takeover, rejoin, server hop, crash, and a main server mixed in both ways. Never two owners. No write over a live lock. Every Token in the final record. |

### Save fields, main against quick-wins

**Dropped by quick-wins: none. Renamed: none. Changed value: none.** (904 fields on the maxed save.)

| Difference | Where | Verdict |
|---|---|---|
| `Store`, `Daily`, `Trove`, `Pity` | new top-level fields | New, at their defaults. Main carries them through its own saves untouched. |
| `Battle.Duels`, `Battle.RaidRewardAt`, `Battle.RaidLossAt`, `Settings.FastHatch` | new fields inside tables main knows | New, at their defaults. See the rollback cost below. |
| `Lock`, `WriteId` | record metadata of the session lock | New. Main ignores them. A clean leave stores no `Lock`. |
| `UpdatedAt` | record metadata | Differs by the time of the write only. |
| `Home.LastSeen` | a clock stamp | Each session writes its own time. |
| Hybrid `SpecialFrom` | new field inside a hybrid | Main keeps it. |
| v1 legacy saves | old store | Read the same way as main. The old store is left as main leaves it. |

### Rollback cost (found, not changed here)

After a rollback, a player who plays on main gets these four quick-wins fields back at their defaults, because main
rebuilds `Battle` and `Settings` from the keys it knows:

- `Battle.RaidRewardAt`, `Battle.RaidLossAt`: the raid clocks restart (one raid reward may come early).
- `Battle.Duels`: the recent duel notes are forgotten.
- `Settings.FastHatch`: back to off.

No main field is affected. I did not change the save format for this inside the release gate: the fix touches the
delta-merge code and the cost is small and only after a rollback. Possible later fix: keep these four in a top-level
key, which main carries through.

### Session lock, measured

- A second server waits 12 s, then gives a stand-in and writes nothing into the save.
- Tokens earned on the stand-in are added when the real save arrives. Nothing is lost, nothing counts twice.
- A server hop behind a 4 s slow save: the new server waits and loads the finished save. No stand-in.
- A crash: the next server takes over 372 s after the dead server's last write (the lock lives 360 s). Until then
  the player has a stand-in. Only what the dead server had not saved is gone.

### Proof that the gate can fail

Three broken copies of the branch, each run with `--branch-root`:

| Break | Result |
|---|---|
| Stop storing Berries | red, 3 failed: `missing .Berries` |
| Store Gems in a new shape | red, 21 failed: `missing .Gems`, main reads 0 |
| Lock goes stale after 5 s | red, 12 failed: the second server takes a live save |

### Older save lists, run again

| List | Result |
|---|---|
| `lock_*` (7), `shutdown`, `client_lock_loading` | 782 passed, 0 failed |
| `p7data_*` (6), `fixr_data_*` (6) | 372 passed, 0 failed |
| `migration`, `polish_data_*`, `p2data_*`, `p3data_*`, `p4data_*`, `p5data_*` (20) | 894 passed, 0 failed |
| `lb_*` (5) | 335 passed, 0 failed |

## Gate 3: papers

- `docs/release/step1-rollback.md`: triggers, what to check first, the Creator Hub steps, what a rollback costs, what
  to tell players.
- `docs/release/step1-test-checklist.md`: about 40 minutes for the owner and one alt in a separate "nimbus TEST"
  experience.

## Open risks

1. **The whole suite has not run on this branch yet.** Only the lists above ran (one at a time, as told). The plan's
   gate 4 is the full `--quick` and `--mesh` run plus a Fable review.
2. **The rollback cost** above (four small fields).
3. **After a server crash** a player can be on a stand-in for up to about 6 minutes on the next server. Progress made
   there is kept.
4. **The owner's real test** (the checklist) is still to do. It also makes real old saves in TEST and practises the
   rollback.
5. **A test order note, not from this branch:** `tut_starter_more` fails when it runs right after the egg lists in one
   `--only` run. It passes alone, and it fails the same way on `quick-wins` at `cfa377c`.
6. **Roblox DataStores are not in the mock.** Throttling and real outages are covered by the older lists with fake
   failures, not by this gate.

## Before merge

- [ ] Full suite `--quick` and `--mesh`, and the Fable review (gate 4).
- [ ] The owner's test checklist passed (gate 5).
- [ ] The owner says yes in chat.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
