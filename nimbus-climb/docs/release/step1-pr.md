# Release step 1: quick-wins to live, Store off, save gates passed

**Base:** `main` (`ac552d0`). **Head:** `qw-step1-gate-b` = `quick-wins` (`cfa377c`) plus the gate commits
(`qw-step1-gate`, `756d0d1`) plus the follow-up of 2026-11-23 (section "Follow-up" below).
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
| Token spins | Open for every account, as on main (owner's pick, 2026-11-23). The PolicyService lock on token spins belongs to a Store that sells Tokens, so it applies only while the switch is on. Gem spins and the Secret Roulette keep main's own PolicyService lock in both states. |
| On | Unchanged. All older Store lists run with the switch on and pass. |

**What main sells today:** nothing for Robux. Main has four gem packs in `Config.Gems.Products`, all with product id 0,
so none is shown and none can be bought. Main does spend gems: roulette spins and the Secret Roulette. Those work
the same with the switch off. If a gem pack gets a product id later, it is shown and sold with the switch off too
(the Gems tab then appears with the gem packs only).

Tests, red first then green:

| List | Result |
|---|---|
| `store_switch_shipped,store_switch_spins_off,store_switch_spins_on,store_switch_off,store_switch_on` (server; the two `spins` lists are new in the follow-up) | gate: red 13 failed, green 193 passed. Follow-up: red 27 failed, green **266 passed, 0 failed** |
| `client_store_switch,client_store_switch_mobile` (client + phone) | gate: red 44 failed, green 590 passed. Follow-up: red 8 failed, green **609 passed, 0 failed** |
| `store_doubles … store_token_lock` (10 lists), `fixr_store_*`, `gem_settle`, `gem_potion_buy`, `gem_prices` | 672 passed, 0 failed (follow-up head) |
| `p2gems_*` (6), the egg and gem lists, `contract`, `config_shape`, `altar_gate`, the shop prompt / globe / egg row lists | 1282 passed, 0 failed (follow-up head) |
| `trove_*`, `lobby_trove_plaza`, `shop_prompt`, `shop_globe`, `shop_egg_row` | 455 passed, 0 failed |
| `client_store_*` (6) | 593 passed, 0 failed |
| `client_fixr_store_*`, `client_fixr_boost_*`, `client_daily_vip` | 485 passed, 0 failed |
| `client_shop_*` (8) | 1174 passed, 0 failed |
| `client_trove`, `client_trove_mobile`, `client_gem_icon` | 654 passed, 0 failed |

Counts are the totals of each run (boot checks included). Looked at: `render_gui.py shop:off` at 1920x1080, 844x390
and 390x844, and `shop:offgems` at 1920x1080.

## Gate 2: the save round trip

`py -3.12 tools/save_roundtrip.py`: **356 checks, 0 failed** (260 at the gate, 96 added in the follow-up). Main's real
code (`ac552d0`, read from git) and this branch run as separate servers on one fake DataStore. No real store, no key.

| Phase | Checks | What it proves |
|---|---|---|
| build | 9 | Main's own save code wrote the fake saves: a new player, a maxed player (892 stored values, 33 pets at 99, 12 hybrids, 100 receipts, Cash 9.8e14), two saves with missing fields, two v1 saves, one empty. |
| load | 59 | Each save loads here as a real, owned save. Main's reading and this branch's reading are compared field by field. The record this branch stores equals the record main stores after the same session. |
| rollback | 205 | Main reads what this branch wrote, at once, with no error and no warning, with every main field and the progress made here. Main's save carries the new fields through. This branch reads it again with everything there. Follow-up: every player also gets two Week Wisps at level 7 (a pet main's catalog does not know). Main keeps the pet, its count and its level in the save. |
| crash | 39 | New in the follow-up. A branch server dies 5 seconds after a join, before the first full save, and the next server is main. A v1-only player (a table save and a bare number) still has all v1 Tokens on main; a brand-new player is brand-new. The branch then reads main's save (nothing doubled), and reads the dead server's own record when the next server is the branch. |
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
| v1 legacy saves | old store | Read the same way as main. The old store is left as main leaves it. Follow-up: the load's first write holds the lock **and** the v1 Tokens, so main never skips its v1 migration (see "Follow-up", item 3). |

### Rollback cost (found, not changed here)

After a rollback, a player who plays on main gets these four quick-wins fields back at their defaults, because main
rebuilds `Battle` and `Settings` from the keys it knows:

- `Battle.RaidRewardAt`, `Battle.RaidLossAt`: the raid clocks restart (one raid reward may come early).
- `Battle.Duels`: the recent duel notes are forgotten.
- `Settings.FastHatch`: back to off.

No main field is affected. I did not change the save format for this inside the release gate: the fix touches the
delta-merge code and the cost is small and only after a rollback. Possible later fix: keep these four in a top-level
key, which main carries through.

One more, found in the follow-up: **a pet main does not know (the Week Wisp, day 7 of the daily streak) is not on the
team while main is live.** Main's team reading drops it. The save keeps the pet, its count, its level and its team
slot: when quick-wins returns, it is back on the team. It only matters for a rollback 6 or more days after release.

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

## Follow-up (owner picks of 2026-11-23, branch `qw-step1-gate-b`)

Each item was red first, then green, and has its own commit.

| # | What | Result |
|---|---|---|
| 1 | **Token spins while the Store is off.** The PolicyService lock on token-paid spins applies only while `Config.Store.Enabled` is true. Off: a restricted account, a failing PolicyService and an account with no answer yet all spin with Tokens, as on main. Server (`PetService`, `GemService`) and client (`EggStage`, `ShopEggs`). | `a291cf9`. New lists `store_switch_spins_off` / `store_switch_spins_on`, both switch states. |
| 2 | **Pass purchases.** `PromptGamePassPurchaseFinished(true)` alone no longer marks a pass Owned, writes the ledger or thanks. The server asks `UserOwnsGamePassAsync` (now, then after 2 / 5 / 15 / 45 s) and grants on the first true answer. Never confirmed: nothing is granted, the next join's normal check decides. | `b1f9203`. The test that pinned the unsafe behaviour is replaced: 21 forged signals grant nothing and cost 5 lookups. |
| 3 | **v1-only rollback gap.** The load's claim no longer writes a lock-only record before the v1 read. It reads v1 first, then writes the lock and the v1 Tokens in one write. Main still finds the Tokens when a quick-wins server dies before the first full save. | `adde3f3`. Round trip phase `crash`: red, main had 0 Tokens instead of 5555 / 888; green. |
| 4 | **A pet main does not know.** The round trip's rollback gives every player two Week Wisps. Main keeps them. | `423024c`. No game code changed. One rollback cost found (above). |
| 5 | **Rollback page.** How to tell an empty stand-in after a crash from real save loss. | `6f88b01`. |
| 6 | **Shipped-value run.** | Section below. |
| 7 | **The place file** is rebuilt from the follow-up head and verified. | `37fcbc6`. `verify_place`: all 1166 scripts match. See "Before merge". |
| 8 | **AFK play-time gifts.** | "Known, for later" below. |

Two notes for step 2 (turning the Store on), from items 1 and 2:

- **Paste a token pack's product id only together with turning the switch on.** While the switch is off the token-spin
  lock is off too. A token pack with an id but the switch off could be bought by a client that opens the prompt
  itself (a paid receipt is always granted), also on a restricted account.
- **Check the pass ownership cache on real Roblox.** `UserOwnsGamePassAsync` can keep answering "not owned" for a
  while after a purchase made inside the game. The server retries for 67 seconds. If Roblox takes longer, a buyer gets
  the pass at the next join; lengthen `PASS_CONFIRM` in `StoreService` then. This cannot be tested in the mock.

### Shipped-value run (`NC_STORE_SHIPPED=1`)

The test harness turns the Store on for every list, so until now nothing but the five switch lists ran with the value
that ships (`Config.Store.Enabled = false`). This run keeps the shipped value for the core lists: boot, join, saves,
the session lock, daily gifts, eggs and gems, the Sky Trove, leaderboards, matches, the home, the play flows, the
tutorial, the HUD, the menus, the loading screen. Five runs, one at a time.

Left out, because they test the Store **on**: `store_doubles … store_token_lock` (10), `fixr_store_*` (3),
`gem_potion_buy`, `store_switch_on`, `store_switch_spins_on`, `client_store_*` (6), `client_fixr_store_*` (5),
`client_fixr_boost_*` (2), `client_daily_vip`, `client_shop_gems`, and the seven Shop window layout lists
`client_shop_window / _eggs / _sizes / _openers / _secret_lock / _mobile / _portrait` (written for the five-tab
window; the one-tab window is tested by `client_store_switch` and `client_store_switch_mobile`).

| Run | Lists | Result | The failures |
|---|---|---|---|
| Server 1: boot, players, saves, lock | 51 | **2209 passed, 0 failed** | none |
| Server 2: daily, eggs, gems, Trove, leaderboards, altar | 61 | 1742 passed, 10 failed | **All by design.** 6: `p2gems_policy` and `egg_spin_x3` expect the token-spin lock, which is off with the Store (item 1). 4: `gem_settle` and `gem_prices` buy the gem XP Potion, which is not sold while the Store is off. |
| Server 3: matches, home, flows, tutorial, HUD tools | 74 | 2961 passed, 1 failed | **Not the switch.** `hudpill_travel` "QuickTravel('Plaza') opens the portal". It passes alone with the shipped value (149 passed), and it fails the same way in this order with the Store on and on the untouched gate commit `756d0d1`. A test order coupling (the test's own comment names it: random spawn offsets). |
| Client 1: load, HUD, menu, loading, daily, Trove, titles, the switch lists | 69 | 3513 passed, 23 failed | 1 **by design**: `OpenPanel('Shop', { Tab = 'Gems' })` opens Eggs. 22 **not the switch**: `client_hudtools_stamina` and `client_hudtools_speed` fail when the main menu lists (`client_p5menu_tiles`, `client_p5loading`, `client_p5menu`, `client_p5settings`) ran before them without the lists that run in between in a whole run. Alone with the shipped value: 615 passed, 0 failed. Same 22 with the Store on and on `756d0d1`. A test order coupling. |
| Client 2: eggs, hatch, roll look, pickers, training, fusion | 34 | 3444 passed, 4 failed | **All by design.** 3: `client_egg_stage` expects the token-spin lock (item 1). 1: `client_egg_vfx` switches to the Gems tab, which is hidden. |

Total: 289 lists, 13,869 checks passed. 15 failures by design, 23 from two test order couplings that are not from this
branch and not from the switch. **Nothing to fix in game code was found.** One test fix was made on the way:
`client_store_switch` used gem pack ids that the shop lists also use, and the client asks each price once per session,
so the list failed whenever those lists ran before it (as they do in a whole run). It uses its own ids now.

### Known, for later

- **Play-time gifts can be farmed while AFK** (review minor). `DailyService` counts any fire of `HomeAction`,
  `PetCare`, `BattleRequest`, `BattleCommand`, `DungeonRequest`, `BuyRoulette` or `Dash` as activity for 180 seconds,
  so a macro or an exploit client keeps the play clock running without playing. It is bounded: the gifts are the fixed
  daily tiers and at most 10 hours count per play-day (`MaxDaySeconds`). No one-line fix is safe (it needs a rule for
  what counts as real play), so it is left for a later build.
- The two test order couplings above, and `tut_starter_more` (open risk 5).

## Gate 3: papers

- `docs/release/step1-rollback.md`: triggers, what to check first, the Creator Hub steps, what a rollback costs, what
  to tell players.
- `docs/release/step1-test-checklist.md`: about 40 minutes for the owner and one alt in a separate "nimbus TEST"
  experience.

## Open risks

1. **The whole suite has not run on this head yet.** Only the lists above ran (one at a time, as told). The plan's
   gate 4 is the full `--quick` and `--mesh` run plus a Fable review. A whole run of `qw-step1-gate` at `756d0d1`
   does not cover the follow-up: gate 4 has to run on `qw-step1-gate-b`.
2. **The rollback cost** above (four small fields, and a Week Wisp off the team while main is live).
3. **After a server crash** a player can be on a stand-in for up to about 6 minutes on the next server. Progress made
   there is kept. `step1-rollback.md` now says how to tell this from real save loss (the toast, wait 8 minutes,
   rejoin).
4. **The owner's real test** (the checklist) is still to do. It also makes real old saves in TEST and practises the
   rollback.
5. **Test order notes, not from this branch:** `tut_starter_more` fails when it runs right after the egg lists in one
   `--only` run. It passes alone, and it fails the same way on `quick-wins` at `cfa377c`. `hudpill_travel` and the two
   `client_hudtools_*` lists have the same kind of coupling (see the shipped-value run).
6. **Roblox DataStores are not in the mock.** Throttling and real outages are covered by the older lists with fake
   failures, not by this gate.

## Before merge

- [x] The place file is rebuilt and verified: `play/NimbusClimb.rbxlx`, commit **`37fcbc6`** (Rojo 7.7.1,
      `rojo build default.project.json -o play/NimbusClimb.rbxlx` from `8d52bcf`; `py -3.12 tools/verify_place.py`:
      OK, all 1166 scripts match). Only docs changed after it.
- [ ] **Rebuild + verify_place again if `src/` changes before the merge**: run the two commands above, commit the
      file, and put the new commit id here and in `step1-test-checklist.md` B0. The file the owner tests must be the
      file that is published.
- [ ] Full suite `--quick` and `--mesh`, and the Fable review (gate 4).
- [ ] The owner's test checklist passed (gate 5).
- [ ] The owner says yes in chat.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
