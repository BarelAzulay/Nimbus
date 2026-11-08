# Lobby and shop: egg rolls, the Cloud Shop, gems, the trove on the plaza, a global leaderboard, the altar portals

Date: 2026-11-07. Branch `lobby-shop` (worktree `.worktrees/lobby-shop`, cut from `bug-batch-6` 09ac836; the `gui-redo` branch
merges in before any code is built, see 3.1). Status: written in sleep mode from the published pitch; my pick is set on every card,
Gemini checked them, the owner can change any card in the morning (branch only, nothing merged). Pitch page:
https://claude.ai/artifact/1pvnd9iMLwbbDvjdR2hUju (db `decisions`). The mock-ups are code: `Projects Main/Nimbus/.superpowers/lobby-shop/pitch/page.html`
(functions `machCard`, `shopB`, `packTile`, `shopA(m, "Gems")`, `eggsA`, `eggSymbol("C", r)`, `machSymbol`, `boardA`, `gateScene`,
`chestMap`; every frame is drawn in design px at 844x390 and 1920x1080, so the builder reads exact positions there). Card summary:
`.superpowers/lobby-shop/pitch/CARDS.md`. Ledger and morning questions: `.superpowers/lobby-shop/LEDGER.md`. Every stage runs on
Opus 5.5 (build xhigh, reviews max, ultracode: money, saves and many systems; Fable is out of credits).
Revised 2026-11-07 after the adversarial spec review: every finding was checked against the code (bug-batch-6 09ac836 and,
for Fusion, the gui-redo tree); the fixes are written into the sections below, and section 14 (Review notes) lists the points
taken in a different form and why.

## 1. Intent and why

The owner, going to sleep (2026-11-07): "work on the shop gui, the same way you worked on the other gui's (look into other games)
and move the reward chest in the game to the center lobby (not exactly in the center but somewhere around the benches. add a
leader board in the lobby, change the roulettes from just rolling pets to rolling eggs by rarity and from each egg the player gets
a random pet from the egg's rarity (keep the machine levels). also, change how the gems look, make it look much attractive, and
about the altar work on the balance of the gems value/price/cost for rolls/items it needs to be something worth buying but not
expensive and too much." Then: "also fix the altar portal, its not really visible too much".

Today the Cloud Shop is an 820x900 window inside `MenuController` with four small machine cards (a "?" dome, an Odds button,
Spin); a spin scrolls 150 px pet pictures for 5.6 s, one at a time, no skip, and every rarity gets the same flash. Gems are the
text glyph U+25C6 in a few places. The Sky Trove (the group-reward chest) stands on the shop island 196 studs behind the spawn,
where most players never see it. There is no lobby leaderboard. Gem spins cost 5/20/75/300 and the Secret spin 1,500 with no
pity, while a free player earns about 20 (casual) to 58 (regular) gems a day. The Storm Altar's gate on the plaza has no pad and
a faint swirl, the altar's summon disc is dark navy, and the way back is a flush 4-stud octagon.

This build:
1. Turns each roll into an **egg roll**: the machine's odds pick an egg (= a rarity), the egg hatches a random pet of that
   rarity. Same four machines, same token prices, same odds (the "machine levels"). x1 and x3, Skip from the first frame, a Fast
   hatch switch, big effects only for Legendary and up, and a pity counter on the Secret Roulette.
2. Redraws the Cloud Shop as pitch B: one big card per machine (five with the Secret Roulette), odds rows with eggs and % on
   every card before paying, SPIN, x3 and the gem price on the card, a Gems tab with packs and a gem XP Potion, and a gently
   pulsing Robux Store button. The Robux Store (approved 2026-11-04) stays as it is except for three small changes (5.8).
3. Re-prices gems (pitch gemprice B) so a gem spin is worth buying and a Secret spin is reachable.
4. Replaces every gem glyph with a drawn cut gem (`UI/GemIcon`) and adds a Blender world gem.
5. Moves the trove to the plaza lawn beside the How to play board, in view at the spawn, with a bobbing "Join the group!" sign.
6. Adds one global leaderboard on the south lawn with three tappable pages (Trophies, Pets found, Climb wins; Climb wins joins once
   the climb finish can no longer be farmed, 5.10).
7. Makes the three altar portals stand up and light up.

## 2. Goals, non-goals, anti-goals

Goals
- A player sees, on every machine, which eggs it gives and their odds before paying, and sees the egg they got crack open.
- One tap rolls one egg; x3 rolls three independent eggs in one request, all or nothing; an accepted request is never refused
  after the roll, so a full stack is never a free reroll.
- Every 7th Secret spin without a Secret is a Secret, the counter survives a rejoin, a server hop and a failed save, and the card
  says how many spins are left.
- The Cloud Shop and the egg stage look like the approved mock-ups at 844x390 and 1920x1080 and fit every screen around them:
  640x360 to 2560x1440 landscape and 360x640 / 390x844 portrait (5.4, 5.5).
- Gems look like gems everywhere a gem amount is drawn; no gem glyph text is left in the client UI.
- The trove is in view from the spawn; the leaderboard shows the real global top 10 for its stats (three once Climb wins is safe,
  5.10); the altar ways are visible from across the plaza.

Non-goals
- No change to the token prices (50 / 250 / 1,000 / 5,000), to the machines' rarity odds, to the Secret Roulette's odds
  (Mythic 85, Secret 15), to the pet pools, or to free gem income (Daily, dungeons, arena, index rewards).
- No change to the Robux Store's layout, its tabs other than the rename, its passes, boosts or packs (only the gem art, the gem
  amounts and the token amounts that come from Config).
- No uploads tonight: no MeshIds, no TextureIds, no image ids, no new sounds. Every new mesh has a Part fallback; every GUI picture
  is drawn from frames and gradients.
- No redesign of the windows `gui-redo` rewrites (Daily, Play time, Training Place, Fusion, the pet picker).
- No gameplay gem drops (the 1.5-stud drop scale of the world gem is reserved, not used).
- No machine upgrade levels (there are none in code; "machine levels" = the four tiers, see the morning question in the ledger).
- No merge into `main` / live, no Studio publish.

Anti-goals (a failure even if it works)
- A client that decides a roll, a price, a pity hit, a leaderboard value or a gem purchase.
- A near-miss trick: Skip hidden or delayed, a strip that slows over a rarer egg on purpose, a fake "almost". The strip is the
  server's strip.
- Gems or tokens charged for a roll the player does not get, or a pet given without the charge (x3 is one all-or-nothing step).
- A paid random item whose odds are not on screen before paying: every card shows its odds, and a card without odds cannot spin.
- A pity counter that can be lost while the gems spent for it are kept, or one that goes backwards.
- A leaderboard stat a client can farm (5.10).
- An old profile that loads differently, or a save that an older server would break.
- A phone shop or stage with text under 15 px, a tap target under 44 px, or anything under Roblox's top bar.
- A lobby that looks busier but harder to walk: nothing new on a path, a gate's sight line, the fountain roundabout or the spawn.

## 3. Constraints (from the code)

### 3.1 The gui-redo overlap

`gui-redo` merges into this branch before the code build starts. It rewrites `CareController`, `DailyController`,
`FusionController`, adds `TrainController` and `UI/PetPicker`, rewrites `DailyService`, and makes small changes to `DataService`,
`FusionService`, `PetService`, `Config` (`Daily.UnlockSeconds` and Remotes comments), `PetKeys`, `State` and `Main.client`. This
build does not redesign any of those windows. Where it touches the same files, the changes stay local:

| File | gui-redo touches | This build touches (local edits only) |
|---|---|---|
| `src/server/Services/PetService.lua` | `EquippedHybrids` attribute field 6 | `BuyRoulette`, `rollAndGrant`, `buyWithGems`, the BuyRoulette remote handler, `ANNOUNCE_ORDER`, `announcePull` |
| `src/shared/Config.lua` | `Daily.UnlockSeconds`, Remotes comments (incl. `DailyRequest`, next to the `StoreRequest` comment) | `Gems` (prices, products with a `Robux` field, `SecretRoulette.PityAt`, `SettleSeconds`), `Store.Tabs` / `Store.Items` token packs / new `Store.GemItems`, new `Eggs`, new `Leaderboard`, `Attr.SecretPityLeft`, `Attr.GemsSettled`, `Attr.TroveGroupDone`, `Match.MinFinishSeconds`, new remote `LeaderboardState` appended at the end of the list, Remotes comments of `BuyRoulette`, `StoreRequest`, `SettingsSet` |
| `src/server/Services/DataService.lua` | `cleanHybrid` knows `SpecialFrom` | the `FastHatch` setting key (stored only when true), the `Pity` field (every touch point listed in 5.2), `GetPity` / `SetPity`, `GemsSettled` and the settle read (5.2); zero new column-0 locals |
| `src/client/State.lua` | `cleanHybrids` keeps `SpecialFrom` | the settings cleaner keeps `FastHatch` |
| `src/client/Main.client.lua` | boots `TrainController` | boots `ShopController`, `LeaderboardController`, `LobbyFxController` |
| `src/client/Controllers/DailyController.lua` | rewritten | nothing: its gem icon comes through `NeonKit.Icon("Gems")` (5.7) |
| `src/client/Controllers/FusionController.lua` | rewritten | after the merge only: the header `GemChip` uses `GemIcon.Amount`, its width from icon + number (one local change; the Mix cost bar already uses `NeonKit.Icon(U.CostIcon, currency, ...)`, which 5.7 covers) |
| `src/server/Services/FusionService.lua` | `moves` argument | after the merge only: the gem Mix checks `DataService.GemsSettled` (one local line, 5.2); the Mix gem price comes from `TycoonCatalog` |
| `tools/sim_tycoon.py` | constants block, `run_check` (`DAILY_UNLOCK_MIN`) | new gem constants and the `--gems` report (5.3) |
| `tools/smoke.py`, `tools/contract.json` | registrations, new modules | registrations, new modules |
| `tools/dump_gui.lua`, `tools/render_gui.py` | new scenes (dump_gui +168 lines) | new scenes (section 9); the gallery's gem glyph |
| `tools/smoke_p2_visual.lua`, `smoke_p5_gui.lua`, `smoke_p5_looks.lua`, `smoke_daily_ui.lua` | edited | rewritten for the moved shop / stage (section 9) |
| `README.md`, `BUILD_STATE.md`, `brain.md` | edited | gem prices, products, roulette table, eggs, leaderboard, trove spot |

If the merge is not in when the build is due, the build waits (the ledger's order). Every file in this table is edited only after
the merge, and line numbers are taken from the merged tree (this spec's line numbers are from bug-batch-6 09ac836; gui-redo's
`dump_gui.lua` alone shifts by 168 lines). Gem prices for Mix live in `src/shared/TycoonCatalog.lua` (`Fusion.Mix`), which gui-redo
does not touch. Files this build edits that gui-redo does not touch: `MenuController`, `MouseLock`, `NeonKit`, `HudController`,
`StoreController`, `StoreService`, `ClientSettings`, `TroveService`, `MatchService`, `PortalVortex`, `LobbyBuilder`, `StormAltar`.

### 3.2 Other constraints

- Lua's 200-local limit (`tools/count_locals.py`; `node tools/check.mjs` warns at 160, errors over 200): `DataService` 160 (adds
  none), `MenuController` 164 (drops below 160 when the shop moves out), `LobbyBuilder` 153 (stays at or under 159; new world code
  goes in a new module), `PetService` 72, `GemService` 78, `StormAltar` 126, `StoreController` 53, `WorldStyle` 49, `State` 66.
- Plain Lua 5.1 syntax; the source stays ASCII; glyphs and UI strings with non-ASCII characters (the middle dot, the en dash) are
  UTF-8 byte escapes (`"\194\183"` for the middle dot).
- Windows use `NeonKit.BigRect(K)` (`K = { RECT = { H0, W0, Y0, H1, W1, Y1 }, MARGIN, PHONE_W, SHORT, PC_MIN_H, PC_MAX_W }`, the
  caller's numbers); readability (`Theme.Readability`): PC design text >= 18 px, phone text >= 15 px at scale 1, targets >= 44 px.
  One window at a time through `MenuController.WindowOpened(id)`; Esc / gamepad B / the red X close; a match closes it.
- DisplayOrders today: Pets / Store / Daily 19, NimbusMenu 20, Index 21, Fusion 22, Care / Arena / Train 23, PetPicker /
  LossScreen 24, Notify 30, Trove 18.
- Saves are delta-based (`DataService`: Base vs live, `UpdateAsync` merge with per-field rules); a new field is a new TOP-LEVEL
  profile field (older servers keep unknown top-level fields through `keepForeign`, so the field must be in `KNOWN_TOP` or this
  version copies the stored value back over every save); provisional (stand-in) profiles never decide a one-time or money thing.
  There is no session lock: a load is a plain `GetAsync` (`fetchProfile`), and the old server's leave save may land after it (5.2,
  the gem settle hold).
- Money and rolls today: `rollAndGrant` seeds a new rng per call from the clock, the user id and `Stats.Spins`, rolls, refuses a
  full stack with no charge, then charges and grants in one non-yielding step (`addCopies` refreshes and syncs inside it); the
  remote's pcall catches an error after the charge. 5.1 replaces this order: nothing refuses after the roll, and nothing that can
  fail runs after the charge. `GemService` owns the PolicyService lock (`ArePaidRandomItemsRestricted`, attribute
  `PaidRandomItemsRestricted`) for gem-priced random items and `Quote`. The lock rules stay exactly as today.
- No server-side animation: the client animates (as `ShowcaseController` and `PortalFxController` do).
- Lobby light rule (`smoke_p5_world`): lamps listed in `Config.Sky.Lamps.Names` (incl. `TroveGlow`, `LampGlass`, `DomeGlow`) at
  most 1.2 brightness / 16 range; every other lobby light at most 1.5 / 28; no SpotLight or SurfaceLight.
- Meshes: `MeshLibrary` (`MeshIds` empty = the Part build; `Mesh.tag(target, key, origin, look, keep)`; manifests in
  `src/shared/MeshManifests` from `blender/kit/manifest_to_lua.py`; LayoutSig manifests tag only while the live build matches).
  `prop_altar_portal` and `gate_altar` have uploaded ids and LayoutSig manifests: do not change the parts they cover.
- Storm Altar budget: at most 500 parts (`tools/contract.json` `stormAltar`); the trove at most 60 parts.
- `SurfaceGui` input works only from `PlayerGui` with an `Adornee`.

## 4. Decisions (the pitch cards)

| Card | Pick | What it means here | Gemini |
|---|---|---|---|
| shop | B, one big card per machine | 5.4 | agreed; "pulse the Store button" taken |
| eggs | A, a strip of eggs, crack, pop | 5.1, 5.5 | agreed; "hide Skip for 1.5 s" rejected (a near-miss trick for kids; Skip from the start) |
| egglook | C, sky-weather eggs | 5.6 | agreed; "big bright symbols" taken |
| gemlook | A, cut gem from GUI frames + shine, Blender world gem | 5.7 | agreed |
| gemprice | B | 5.3 | agreed; "show spins until a Secret" taken |
| chest | A, front lawn by the How to play board | 5.9 | agreed; "bobbing Join the group! sign" taken |
| board | A, one board, three tappable pages | 5.10 | disagreed (Gemini: three boards); A built, morning question; the Climb wins page waits for the finish fix (5.10) |
| portal | C, stand up and light up all three | 5.11 | agreed; the return way in the Arena Return-gate green (Gemini's "different colour") taken |

## 5. Design

### 5.1 Eggs and the roll

**Eggs.** `Config.Eggs` (new): the name and order of the seven eggs, one per rarity:
`{ Common = "Cloud Puff Egg", Uncommon = "Breeze Egg", Rare = "Raindrop Egg", Epic = "Thunder Egg", Legendary = "Sunburst Egg",
Mythic = "Aurora Egg", Secret = "Starry Night Egg" }` (my call on the names; they follow the egg look, 5.6). An egg is a rarity;
there is no egg item, no egg inventory and nothing to save.

**The roll.** Unchanged in math: the machine's odds pick a rarity, then a uniform pet of that rarity from the same pool
`PetCatalog.RollPet` uses today. `PetCatalog` gains pure helpers that keep `RollPet`'s exact draw order so seeded tests and
today's results stay identical:
- `PetCatalog.RollRarity(rouletteId, rng) -> rarity` (the one `rng:Float(0, total)` draw over `oddsEntries`),
- `PetCatalog.RollFromRarity(rouletteId, rarity, rng) -> petId` (the one `rng:Int(1, #pets)` draw over that rarity's pool),
- `PetCatalog.RarityPool(rouletteId, rarity) -> { PetDef... }` (the pool `RollFromRarity` draws from: `poolByRarity`, never an
  EventOnly or ExclusiveTo pet).
`RollPet(rouletteId, rng)` becomes `RollFromRarity(id, RollRarity(id, rng), rng)` (same numbers for the same seed; a test pins it).

**One source for the odds, the Secret Roulette included.** Today `PetCatalog.findRoulette` searches only `Config.Roulettes`, so
`PetCatalog.GetRarityOdds("Secret")` returns `{}`; the server keeps its own copy in `GemService` (`oddsEntries` / `petsOfRarity`)
and the client a third in `MenuController` (`secretRoulette` / `gemsOnlyBuckets` / `oddsOf`), which this build deletes with the old
shop. So `findRoulette` also returns `Config.Gems.SecretRoulette` (its `Odds`, `AllowSecret = true`), and every PetCatalog odds and
roll function (`GetRarityOdds`, `GetOdds`, `PossiblePets`, `RollRarity`, `RollFromRarity`, `RarityPool`, `RollPet`) works for it on
the server and on the client. `GemService`'s gems-only `RollPet` / `GetOdds` / `GetRarityOdds` / `PossiblePets` delegate to them
(the pools are the same lists: `ListByRarity` without events is `poolByRarity`), so the Secret card and the server read one table:
Mythic 85% / Secret 15%. Token roulettes do not change, and `PetService`'s `roulettes` table still lists only `Config.Roulettes`,
so the Secret Roulette stays gems only.

`GemService.RollPet(rouletteId, rng, opts)` gains an optional `opts.ForceRarity` (used only by the pity, 5.2): the Float draw still
happens and is thrown away, then the pet is drawn from `RarityPool(id, ForceRarity)` with the Int draw, so the rng position matches
an unforced roll.

**Randomness.** `PetService` creates two server-wide generators once at Init: `RollRng` for the pulls and `StripRng` for the
strips, each the `Util.NewRng` wrapper (`:Float` / `:Int`) around an engine-seeded `Random.new()` (`Util.NewRng` gains a no-seed
form that calls `Random.new()` with no argument). Both are seeded by the engine, never from the clock, the user id or
`Stats.Spins`, and never sent to a client. (Today's per-call seed `os.time + UserId + Stats.Spins + floor(os.clock()*1000)` would give the three pulls
of an x3 the same seed inside one step, so every x3 would be three copies of one pet; and a 40-cell strip drawn from `seed + 7919`
lets a client search offline for the server's clock term.) Pulls 1..spins of a request are drawn from `RollRng` in order, so they
are independent rolls at the shown odds. Each pull calls the roulette's roll function as `roll(id, RollRng)`, and the forced pity
pull as `roll(id, RollRng, { ForceRarity = "Secret" })`; `roll` is `PetCatalog.RollPet`, or the quote's `GemService.RollPet` for the
Secret Roulette, so the tests that replace `RollPet` still steer pulls. `buildStrip` draws its 39 filler cells from `StripRng` with
the plain call `roll(id, StripRng)` (never forced), so a strip says nothing about `RollRng` and a forced pull's strip shows the
normal odds. Seeded tests pass their own generators through `PetService._SetRngForTest(rollRng, stripRng)`, which does nothing
outside Studio and the mock.

**The request.** `BuyRoulette(rouletteId, currency, spins)` (the remote's comment in `Config.Remotes` updated):
- `rouletteId` a known roulette id string (<= `MAX_ID_LENGTH` 48). `currency` exactly as today's `parseCurrency`: nil = the
  roulette's default; "Tokens" / "Gems" in any case, "token" / "gem" / "cloudtokens" and `{ Currency = ... }` accepted; anything
  else answered "Unknown currency" (today's answer, which `smoke_p2_gems` checks). `spins` nil -> 1; only the numbers 1 and 3. The
  remote handler drops a bad `spins` (2, 3.5, "3", a table, 3 on the Secret Roulette) silently, like other junk; the public
  `PetService.BuyRoulette` answers it with false + "Bad spins", so tests can call it directly.
- The Secret Roulette is x1 only (its card has no x3; my call: it keeps the pity simple and keeps 3,000-gem taps out of reach of
  a mis-tap).
- **Never refused after the roll.** One non-yielding step (no `task.wait`, no DataStore or remote call), in this order:
  1. The checks, each answered as today: in a match ("The shop is closed during a match"), loading ("Your data is still
     loading"), the Secret Roulette while provisional ("Your data is still loading": the pity reads the profile), a gem-priced
     spin before the server has settled (5.2, the same text), the `GemService` lock and quote (unchanged), and the balance.
     `UnitPrice` comes from Config (or the quote) and `Price = UnitPrice * spins` is computed once here, for both currencies, and
     used for both the balance check and the charge (today's "not enough" texts). For the Secret Roulette `DataService.GetPity`
     must answer (nil -> "Your data is still loading").
  2. The pulls, from `RollRng` (above). A pull's rarity is the rarity of the pet the roll gave, and it never changes. If the
     player cannot hold another copy of that pet (`owned + earlier pulls of this request >= Config.Pets.MaxPerStack`, 99), the pet
     is re-picked with `RollRng`, uniformly from that rarity's pool minus the pets that are full (counting the request); the forced
     pity pull works the same way. Only when every pet of that rarity is full does the pull become a substitute: that rarity's
     `Config.Index.Rewards[rarity].Tokens` (the rule `StoreService.ApplyGrant` already uses for a full stack), shown on the reveal
     as "Stack full: +N Tokens instead". So a full stack never works as a free reroll: the shown rarity odds hold for every paid
     pull, and the pity is never skipped by rerolling.
  3. Everything else that can fail, still before the charge: the pet lookups, each pull's `IsNew` / `NewDiscovery` / `Count` /
     `PoolSize`, the strips, the new pity numbers (5.2) and the reply table. An error here answers "The roulette jammed, try again"
     with nothing charged.
  4. One charge: `SpendTokens` / `SpendGems(player, Price)` (non-yielding). A false here refuses with today's text; nothing has
     been written yet.
  5. Plain writes only: the `Pets` counts in pull order, `Discovered`, the substitute tokens (`AddTokens`), `Stats.Spins += spins`,
     the pity (`DataService.SetPity`, 5.2), `MarkDirty`. `addCopies` splits into a plan part (step 3) and this write part;
     `GrantPet` calls both in a row and behaves as today.
  6. After the step, each in its own pcall (a failure is logged and never undoes the grant): `refreshPlayer`, the first pet ever
     into the active team (`SetTeam`), one `Sync`, the `RouletteResult` reply, `PetService.Rolled:Fire` once per pull (tutorial,
     index; a substitute pull fires with the rolled pet), and the announcement (once per request, 5.5).
  Every accepted request is charged once and gets all its pulls; a refused request writes nothing. x3 costs exactly three times
  x1 (no discount; my call).

**The reply** (`RouletteResult`, a server -> client event as today):

```
{ Ok = true, RouletteId, Currency, Spins = 1 | 3,
  UnitPrice, Price = UnitPrice * Spins,
  Pulls = { { PetId, Key, Rarity, IsNew, NewDiscovery, Count, PoolSize, Strip = { petId x 40 }, Pity = true|nil,
              Substitute = { Tokens = n } | nil }, ... },
  -- pull 1 mirrored at the top level (PetId, Key, IsNew, NewDiscovery, Count, Strip) for older readers
  Tokens, Gems,                      -- balances after the charge (and the substitute tokens)
  SecretPity = { Left = 1..7 } | nil -- only for the Secret Roulette; the same clamped number as the attribute (5.2)
}
failure: { Ok = false, Reason, RouletteId, Currency, Spins, Tokens, Gems }
```

`Strip` stays a list of 40 pet ids (`STRIP_LENGTH 40`, the winner at `WIN_INDEX 34`, built by `buildStrip` per pull from
`StripRng`); the client draws each cell as the egg of that pet's rarity, so the strip shows the true odds and needs no new server
data. `PoolSize` is `#PetCatalog.RarityPool(rouletteId, rarity)` (the same pool for the Secret Roulette now; Epic 3, Legendary 4,
Mythic 2, Secret 4, ...), for the reveal's "1 of N" line. A substitute pull keeps its rolled `PetId` (the egg and the strip show
its rarity) and its `Count` is the full stack.

**Rate limits.** Unchanged: the server's `REMOTE_COOLDOWN` 0.25 s per player and the client's `FIRE_GAP` 0.3 s plus its pending
lock (`WAIT_TIMEOUT` 7 s). An x3 is one request.

**PolicyService.** Unchanged: gem-priced spins (x1 or x3, and the Secret Roulette) are locked for restricted accounts and while
the answer is unknown ("Checking your account..."); token spins stay open (today's rule; see "Calls I made"). The gem settle hold
(5.2) is a separate rule for every account.

### 5.2 The Secret pity counter

- `Config.Gems.SecretRoulette.PityAt = 7`: the 7th Secret Roulette spin in a row without a Secret gives a Secret.
- Profile: a new top-level field `Pity = { Secret = { Spins = n, Hit = n } }`, left out of the record while both are 0 (old
  profiles have none and load as 0 / 0). `Spins` = Secret Roulette spins ever (merge: delta, like `Ring.Runs`); `Hit` = the
  `Spins` value right after the last Secret from this roulette (merge: max, like `Ring.Best`). `Since = max(0, Spins - Hit)`.
- **Every DataService touch point of the new field** (the `Ring` field is the pattern; a missing one breaks the count):
  - `KNOWN_TOP`: without it `keepForeign` copies the stored `Pity` back over every save, so the stored count freezes at its first
    save (frozen at `Since = 6`, the first Secret spin of every session would be forced);
  - `OVERWRITABLE` (`ResetFields`, the dev reset, clears it);
  - the `newProfile` default, the clean / diff / apply helpers (fields of an existing table, no new column-0 local),
    `normalizeProfile`, `copyProfile`, `profilesEqual` and the overwrite branch;
  - `diffProfiles` and `isEmptyDelta` (a pity-only change must save), `applyDelta` and its overwrite path;
  - `toStored` (left out while both are 0);
  - `replaceContents` / `refill`, used by `rebase`: without it a rebase leaves the live pity stale and the server forces from old
    numbers.
  The ProfileSync snapshot does not carry it (the attribute and the reply do).
- On a Secret Roulette spin (inside the money step, 5.1): `Since` from the `GetPity` read of step 1; `forced = Since >= PityAt - 1`;
  the pull rolls with `ForceRarity = "Secret"` when forced; new `Spins = Spins + 1`; if the pull is Secret (natural or forced, a
  substitute included) new `Hit = new Spins`. The numbers are computed in step 3 and written in step 5. The pull record carries
  `Pity = true` when forced.
- Only the Secret Roulette counts (it is the only roulette with Secret pets). A refused spin does not count (it writes nothing).
- `DataService.GetPity(player) -> { Spins, Hit } | nil`: a copy, nil until loaded and while provisional (like `GetRing`).
  `DataService.SetPity(player, spins, hit) -> true`: a plain write on the real entry. The caller read `GetPity` in the same
  non-yielding step, so the entry cannot have turned provisional or unloaded, and the numbers were validated before the charge;
  `Hit` never goes down; `MarkDirty` + `SyncSoon`. There is no `MutatePity`: `MutateRing`'s callback form can refuse after the
  caller has paid (its contract, `DataService.lua` 6265-6268, says "pay only once this returned true"), and the pity must never be
  refused after the charge. Both are fields of an existing table, so the column-0 local count stays 160. Clean: both whole numbers
  in 0 .. 1e9, `Hit <= Spins` (else `Hit = Spins`), anything else dropped to 0.
- **The attribute.** One `refreshPityAttr(player)` writes `Config.Attr.SecretPityLeft = Left`, with
  `Left = clamp(PityAt - Since, 1, PityAt)`, on `DataService.ProfileLoaded`, on `DataService.ProfileRebased` (a stand-in profile
  becomes real there, and another server's spins arrive there) and after each Secret spin; it removes the attribute while the
  profile is loading or provisional. The clamp matters: the merge can push `Since` above 6 (two servers each adding spins after the
  same hit), which would read "Secret for sure in -1"; a `Since` of 8 shows 1 and forces the next spin. `RouletteResult.SecretPity.Left`
  sends the same clamped number at once. The client's chip reads the attribute.
- **The gem settle hold (server hops).** DataService has no session lock: a new server loads with a plain `GetAsync`
  (`fetchProfile`) while the old server's leave save may still be pending (the per-key write cooldown after an autosave or a
  receipt save, write throttling, or a failed save kept as an orphan and retried at 10 / 20 / 40 / 80 / 120 s), and the merge
  clamps a negative balance to 0. A player who hops right after spending gems could see the old gem balance and the old `Since` on
  the new server, and the pity would force a second Secret paid with the same gems. So every gem-priced action waits until this
  server has settled. `DataService.GemsSettled(player) -> bool` is false from the load until `Config.Gems.SettleSeconds` (15) have
  passed **and** one settle read has come back: a fresh read of the stored record, rebased onto the live profile under the entry
  lock (the `recover` read + `rebase`, which already merges another server's writes and fires `ProfileRebased`, so the gem balance
  and the pity attribute update). A failed settle read retries every 5 s; with no DataStore (Studio without API access, the store
  disabled) the server counts as settled at 15 s. While not settled, gem spins (x1 and x3), the Secret Roulette, `GemBuy` (5.8)
  and, after the gui-redo merge, the gem Mix (`FusionService`, one local check) are refused with "Your data is still loading". The
  server sets the player attribute `Config.Attr.GemsSettled = true` once settled (absent before); while it is absent the Secret
  card's chip and the gem buttons read "Loading...", and `refreshPityAttr` leaves `SecretPityLeft` absent. Token spins and
  everything else are not held. The flag lives on the cache entry (nothing stored, no new column-0 local). What it does not
  close: an old server whose leave save lands after the new server's settle read (a save that failed and is retried as an
  orphan). The full fix is a session claim on the record, which changes every load of the game; it is a morning question
  (section 13).
- Cases (each a test): a rejoin keeps the count (it is in the save); a server hop where the old server's leave save lands during
  the hold: the new server refuses gem actions until settled, then shows the old server's gems and `Since` (no second forced
  Secret, no second spend); a failed save loses the spend, the pet and the count together (one profile write), never one without
  the others; old spins before this build give no credit (no retroactive count, no migration); after a Secret the count restarts
  at 7; a merged `Since` of 8 shows 1 and forces the next spin.
- Expected cost of a Secret pet from this roulette: `1000 * (1 - 0.85^7) / 0.15 = 4,529` gems (was 10,000 with no pity at 1,500).
- Client text: the Secret card's chip "Secret for sure in N" (N = Left; N = 1 reads "Secret for sure on the next spin"); phone
  "Secret in N"; the Gems balance does not move the chip. While loading, provisional or not settled the chip reads "Loading...".
  A forced Secret's reveal note adds " \194\183 guaranteed".

### 5.3 Gem prices (pitch gemprice B)

| What | Today | New |
|---|---|---|
| Gem spin Cloud / Storm / Sky / Celestial (`Config.Gems.RouletteGemPrices`) | 5 / 20 / 75 / 300 | 4 / 15 / 60 / 250 |
| Secret Roulette (`Config.Gems.SecretRoulette.GemPrice`) | 1,500 | 1,000 (+ pity at 7) |
| Fusion Mix gems, Mythic / Secret (`TycoonCatalog.Fusion.Mix`) | 60 / 150 | 50 / 125 |
| XP Potion 30 min (new `Config.Store.GemItems`) | not sold | 75 gems |
| Gem packs Pouch / Bag / Chest / Vault (`Config.Gems.Products`) | 100 / 550 / 1,200 / 6,500 gems, no Robux field | 150 / 500 / 1,500 / 4,000 gems, new field `Robux = 49 / 149 / 399 / 999` (a suggestion; Ids stay 0) |
| Token packs (`Config.Store.Items` Tokens1/2/3, 49 / 149 / 399 R$) | 500 / 2,500 / 10,000 | 1,000 / 5,000 / 20,000 (names "1,000 Cloud Tokens" etc.; see the morning question on token value) |
| Free gem income (Daily and Play tiers, dungeons, arena, index, raids, prestige) | about 20 casual / 58 regular a day before prestige; prestige pays 100, then -10 per star, at least 25 (`TycoonCatalog.Prestige`), up to 135 gems an hour on runs 2-10 | unchanged |

- `Config.Gems.Products[i].Robux` is copied by `StoreCatalog.gemItem` (as `cleanItem` copies `Robux` for Store items). Once a
  product's Id is above 0 the shown price is the live `GetProductInfo(...).PriceInRobux`; until then the Config suggestion is shown
  with a disabled "Coming soon" button (PREVIEW under `StorePreview` in Studio, as the Store does).
- The pack bonus is honest and rises with the pack: gems per Robux 3.06 / 3.36 (+10%) / 3.76 (+23%) / 4.00 (+31%), the ribbons
  computed from the prices shown, not typed. The 399 R$ Chest = 1,500 gems = one Secret spin + two Celestial spins exactly.
- Before prestige gems, a regular free player reaches a Secret spin in about 17 days (casual about 50) and a Celestial gem spin in
  about 4 days. A player in the prestige phase earns a Secret spin in hours of play; the `--gems` report prints both (below) and the
  balance is a morning question.
- Token spins cost more Robux than gem spins on every machine at the 49 R$ packs (Cloud 2.45 vs 1.31 R$ a spin, Storm 12.3 vs 4.9,
  Sky 49 vs 19.6; the 1,000-token pack cannot buy one Celestial spin). The build keeps the pitch's token amounts, the `--gems`
  report prints Robux per spin for both currencies on every machine, and resizing the token packs is a morning question.
- `Config.Store.GemItems = { { Key = "XpPotionGems", Gems = 75, Name = "XP Potion (30 min)", Grants = { Boost = { XpPotion = 1800 } } } }`.
  Bought with `StoreRequest("GemBuy", key)` (5.8 and section 7).
- The Robux prices and product ids are the owner's (the ledger's morning question); the build writes the suggestions into Config.
- README: the gem section, the product table and the roulette table are rewritten from Config (`smoke_p2_final` compares them).

**sim_tycoon** (`tools/sim_tycoon.py`, constants block `# ==== BEGIN/END SIM CONSTANTS ====`, read by `smoke_p4_economy`):
new constants `GEM_SPIN = [4, 15, 60, 250]`, `GEM_SECRET = 1000`, `SECRET_PITY = 7`, `GEM_MIX = [50, 125]`, `GEM_POTION = 75`,
`GEM_PACKS = [150, 500, 1500, 4000]`, `PACK_ROBUX = [49, 149, 399, 999]`, `TOKEN_PACKS = [1000, 5000, 20000]`,
`GEM_DAY_CASUAL = 20`, `GEM_DAY_REGULAR = 58`. `--check` compares each with Config / TycoonCatalog (`same(...)`), except
`GEM_DAY_*`, which are marked as assumptions (no Config value to compare; they cover only the non-prestige income of a player who
does not reach the Play tiers' gem cells). A new `--gems` report builds the income from the sim's own numbers: `PRESTIGE_GEMS` with
the simulated run lengths, the `DAILY_TIERS` gem cells, and the dungeon, arena, raid and index gem rewards read from Config. It
prints two players, one who never prestiges and one in the prestige phase: days (or hours) per gem spin of each price, gems per
Secret pet (the formula above), the pack table with bonus %, and Robux per spin for both currencies on every machine (packs from
`PACK_ROBUX` and the Config `Robux` field, which it compares). Its checks: the non-prestiging regular player's days per Secret spin
in 12 .. 25 on that full income (re-run before the new prices are written; if it fails, the build stops and the numbers go to the
morning list); gems per Secret pet = 4,529 +-1; pack gems per Robux strictly rising; the 399 R$ pack = one Secret + two Celestial
spins; `PACK_ROBUX` equal to the Config `Robux` fields. The prestiging player's hours per Secret spin is printed, not checked (a
morning question). Today's gem lines ("recorded, never spent") stay; the token economy numbers do not move (no token price
changes). `smoke_p4_economy` checks the new names exist and match.

### 5.4 The Cloud Shop (pitch B)

**Where the code lives.** The Cloud Shop and its roll stage move out of `MenuController` (164 locals) into
`src/client/Controllers/ShopController.lua` (the window) and `src/client/UI/EggStage.lua` (the stage, 5.5).
`MenuController` keeps a lazy forwarder like `P5.openStore`: `onOpenPanel("shop", args)` -> `ShopController.Open(args)` with the
whole args table; `normalizeTab` maps `"roul"`, `"Roulettes"`, `"egg"` -> `"Eggs"` and `"gem"` -> `"Gems"` (so `OpenPanel { Panel =
"Shop", Tab = "Roulettes" }` still works); its own windows close on `WindowOpened("Shop")`. The old `buildShop`,
`buildRouletteCard`, `openOdds`, `beginStage`, `onRouletteResult`, the client odds copy (`secretRoulette` / `gemsOnlyBuckets` /
`oddsOf`, replaced by PetCatalog, 5.1) and their K / Spin / Odds state are removed from `MenuController` (the Odds popup is gone:
the odds are on the cards). The shop's ProximityPrompts (`PetService.buildPrompts`, "Open" on each machine) are unchanged.

**`ShopController.Open(args)`.** `args.Tab` (normalized) picks the tab. A `RouletteId` (the machine prompts send
`{ Tab = "Roulette", RouletteId = id }`; the Storm Altar's Summon sends `{ RouletteId = "Secret", Currency = "Gems" }` with no Tab)
opens the Eggs tab, scrolls the card row until that card is fully visible (centred when the row scrolls) and outlines it in gold
for 2.6 s, as today's `focusCard`. `Currency` alone never switches tabs (today's rule "Currency Gems -> Gems tab" would send the
Altar's players to the gem packs, and on a phone the Secret card starts off screen); only `Tab = "Gems"` / `"gem"` opens Gems.

**Hooks into MenuController** (today the stage and the docked Shop drive these, and they must keep working):
- `ShopController.IsOpen()` / `Close()` and `EggStage.IsShowing()` / `Close()`. `MenuController.IsOpen()` ORs them in (read by
  `TutorialController.windowCovering`, which folds its card and hides its pointer, and by `ArenaController.otherWindowOpen`).
- `closeEverything` calls both closes the way it calls `P5.closePets` / `P5.closeStore`, so `MenuController.Close()`,
  `OpenPanel "close"` and a match start (`onMatchFlagChanged`) close the shop and the stage.
- `openWindow`, `P5.openPets`, `P5.openStore` and the Index open refuse while `EggStage.IsShowing()`, as they refuse while today's
  stage shows.
- Esc / gamepad B: EggStage binds them (ContextActionService) at a higher priority than the shop, so a press on the stage skips or
  closes the stage only and never also closes the shop.

**Mouse lock.** Today's Shop is a `NeonKit.Dock` window, which frees the cursor; `BigRect` gives no Dock hold. So
`ShopController` calls `MouseLock.WatchVisible("Dock:Window_Shop", holder)` as `PetsController` does, and `MouseLock`'s
`WATCHERS` gets `NimbusHatch = watchOverlays({ "Stage" })` (the stage root), replacing today's `NimbusMenu` `RouletteStage` /
`OddsPopup` entries. Mouse lock is on by default on PC; with it on, the cursor is free over the cards and over SPIN AGAIN / DONE.

**One owner for a pending request.** `EggStage.Request(rouletteId, currency, spins)` is the only sender of `BuyRoulette`: it holds
the client's `FIRE_GAP` 0.3 s, the pending flag and `WAIT_TIMEOUT` 7 s, and fires `EggStage.Pending` / `EggStage.Answered`.
ShopController's buttons and the stage's SPIN AGAIN both call it, and the cards read `EggStage.IsPending()`. A failure answer
re-enables the cards at once and shows the reason as a toast; a success opens the stage.

**Window.** ScreenGui `NimbusShop`, DisplayOrder 19, `IgnoreGuiInset` like the Store. `NeonKit.BigRect` with
`RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1660, Y1 = 900 }`, `MARGIN 12`, `PHONE_W 900`, `SHORT 560`,
`PC_MIN_H 600`, `PC_MAX_W 0.87` (the mock's 1660x900 box at 1920x1080 needs more than the Store's 0.76; the window covers the
menu column, so it calls `MenuController.SetColumnCovered`). On a phone it hides the touch stick and jump
(`MenuController.SetTouchHidden`). Opening fires `MenuController.WindowOpened("Shop")` (the tutorial's `ShopOpened` keeps working).
What `BigRect` gives with these numbers (factor = `Theme.ScreenFactor(h)`, 0.8 .. 1.25):

| Screen | Window (px) | Mode, scale | Design box (px) | Body under the header |
|---|---|---|---|---|
| 1920x1080 | 1660x900 | PC 1 | 1660x900 | 824 |
| 1366x768 | 1188x642 | PC 0.8 | 1485x802 | 726 |
| 1280x720 | 1114x603 | PC 0.8 | 1392x753 | 677 |
| 844x390 | 820x330 | Phone 1 | 820x330 | 280 |
| 740x360 / 640x360 | 716x300 / 616x300 | Phone 1 | same | 250 |
| 360x640 (portrait) | 336x536 | Phone 1, portrait | same | 436 (two header rows) |
| 390x844 (portrait) | 366x705 | Phone 1, portrait | same | 605 |

**Fit rules** (the mocks only drew 1920x1080 and 844x390; every size in the table is a test size):
- PC: the cards take the body height (card top at y 70 under the subtitle, 12 px bottom margin). When that is under 736, the
  machine art shrinks first (230 down to 150 tall), then the odds row pitch (44 down to 38, the egg 28 -> 26 px, text sizes
  unchanged); if that is still short, the subtitle hides
  and the cards start at y 12. So at 1280x720 and 1366x768 every card still shows its odds, SPIN, x3 / gem row and hint, and the
  Gems tab's potion card stays in the body (the Gems tab body scrolls vertically when it does not fit).
- Phone, landscape: below about 760 px window width the header drops the title text (the egg icon stays); if the header still does
  not fit, the balance chips use `Theme.ShortNumber` at 80 px. With a body shorter than 280, the card height is body - 12: the
  machine art shrinks (52 down to 40) and the card's bottom padding (18 down to 6), so a 238 px card fits a 250 px body.
- Portrait (`BigRect(...).portrait`, like `StoreController`'s `K.PORTRAIT` layout): the header has two 50 px rows (row 1: egg icon,
  "Cloud Shop", the X; row 2: the two tab pills, the two balance chips, the Store mark); the body is a vertical ScrollingFrame of
  full-width cards (width - 16), 250 tall: the name plate on top, the machine art 64 px at the left, the odds as a 2x2 grid of egg
  30 px + % 15 px at the right, then SPIN (44) and the x3 / gem row (44) or the pity chip. The Gems tab is the same vertical list
  (the hero on top, the four packs, the potion).

**Header** (PC 76 px, phone 50 px): egg icon + title "Cloud Shop" (PC 340 wide, phone 200), two tab pills `Tab_Eggs` "Eggs" and
`Tab_Gems` "Gems" (PC 150x52, phone 92x44), balance chips `Balance_Gems` (GemIcon + number; PC 140 wide, phone 96) and
`Balance_Tokens` (PC 190, phone 128), the `StoreButton` (PC: Robux mark + "Robux Store", 236 wide, rgb(47,158,90); phone: the
Robux mark only, 48 wide) and the red X. The Store button pulses gently while the shop is open (a UIScale 1.00 <-> 1.05 over 1.2 s
each way; on Low graphics a steady glow stroke instead). It closes the Cloud Shop and opens the Robux Store (today's path).

**Eggs tab, PC** (design px in the 1660x900 box; the mock `shopB("pc")`):
- Subtitle at (44, 12), 1100x44, 22 px: "Every egg hatches a random pet of its rarity. The odds are on every machine."
- `FastHatch` toggle at (1330, 8), 280x52: switch + "Fast hatch" 22 px (5.5).
- Five cards `ShopCard_Cloud`, `ShopCard_Storm`, `ShopCard_Sky`, `ShopCard_Celestial`, `ShopCard_Secret`, 300x736 at
  x = 44 + i * 318, y = 70, each framed in its roulette's Config colour (the Secret frame rgb(138,92,255)):
  - name plate 12 px in, 54 tall, 26 px ("Cloud Roulette" ... "Secret Roulette");
  - the machine art at y 76, 200 x 230 (a base, a glass dome with seven eggs of that machine's mix inside, a cap; `machSymbol`;
    built from frames, the dome a CanvasGroup with a round UICorner so the eggs clip inside it);
  - odds rows `Odds_<Rarity>` from y = 76 + 230 + 8, 44 tall each (38 drawn): the egg (28 px), the rarity word in its colour 20 px,
    the % right-aligned 22 px; the rows come from `PetCatalog.GetRarityOdds(id)` (the same table the server rolls from, the
    Secret Roulette included since 5.1: Mythic 85% / Secret 15%). A card with no odds rows (a catalog fault) shows "Odds
    unavailable" and its SPIN, x3 and gem buttons are disabled: odds are shown before every paid roll, or there is no roll;
  - `Spin` (76 tall, full width): "SPIN" + token icon + price (Secret: GemIcon + "1,000"), 27 px;
  - token machines: `Spin3` "x3" + token icon + 3x price and `SpinGems` GemIcon + gem price, each half width, 60 tall;
    Secret: the `PityChip` (60 tall, rgb(59,42,138)) "Secret for sure in N";
  - hint 18 px under the buttons: "Gems: same odds" (Secret: "Also at the Storm Altar").
- Width between the two ends: the five cards share the body width (card width = (bodyW - 88 - 4 * 18) / 5); under 264 px the
  row scrolls sideways like the phone (1280x720 scrolls: 246 px cards; 1366x768 just fits at 265). Height: the PC fit rule above.

**Eggs tab, phone** (820 x 330 window at 844x390, body 280 under the 50 px header, sizes from `BigRect`; `shopB("phone")`,
with the changes below): five cards 188x262 at x = 8 + i * 196 in a horizontal ScrollingFrame (canvas 988 wide) with a 68 px
fade on the right edge while more is to the right. Card layout (y in the card): the name plate 6..36 (17 px, without "Roulette");
the machine art 40..92 (52 tall, down from the mock's 72); the odds 96..146 as one column per rarity (at most four, 44 px wide
each): the egg at 30 px (the size the approved egglook must read at, so the weather mark tells the rarities apart without colour)
over the % at 15 px; `Spin` 150..194 (44 tall, 16 px); then 200..244 the x3 + gem row (44 tall) or the pity chip "Secret in N".
The phone `Spin3` reads "x3" + token icon + the 3x price in short form (`Theme.ShortNumber`: 150, 750, 3,000, 15K) at 15 px or
more, so a tap that charges three times the price always shows the total. No subtitle and no Fast hatch toggle on the phone shop
(the toggle is on the stage). Smaller phones and portrait: the fit rules above.

**States on a card.** Not enough tokens or gems: the button keeps its price, the amount turns red, a tap shows today's "not
enough" toast. Restricted / checking (PolicyService): the gem button and the whole Secret card show the lock with today's text
(the scene `shop:restricted`). Not settled yet (5.2): the gem buttons and the Secret card read "Loading...". While a request is
pending (`EggStage.IsPending()`) all spin buttons of all cards are dimmed (one roll at a time); a failure answer re-enables them at
once.

**Gems tab, PC** (from the pitch's Gems frame, `shopA("pc", "Gems")`, fitted to the B window; my call: the B mock shows only the
Eggs body, so the Gems body reuses the approved Gems frame):
- A hero card 1572x200 at (44, 12): a pile of six gems 180 px, "Gems" 46 px, "Spin the Secret Roulette and every machine with
  gems." 24 px, "Chest: 1,500 gems = 1 Secret spin + 2 Celestial spins" 24 px in rgb(255,243,176), and the Chest's buy button.
- Four pack tiles `GemPack_1..4` (Pouch, Bag, Chest, Vault) 379x380 in a row under it (gap 18): the pile (1 / 2 / 4 / 6 gems,
  140 px), the amount 44 px, the Config `Name` as it is ("Pouch of Gems") 21 px, the bonus ribbon "+10%" / "+23%" / "+31%"
  (computed from the prices shown), "BEST VALUE" on the Vault (gold), and the Robux buy button 68 tall with the price: the live
  `PriceInRobux` once the product's Id is above 0, else the Config `Robux` suggestion (5.3) on a disabled "Coming soon" button
  (PREVIEW in Studio, as the Store). The button sends today's live path, `StoreRequest("Buy", "Gems" .. i)`: the server prompts
  the purchase, the client never does (GemService's `BuyGems` remote is not in `Config.Remotes` and stays unconnected).
- The potion card `GemPotion` 1572x130 under the packs: potion icon 96, "XP Potion \194\183 30 minutes" 32 px, "Your team earns
  double pet XP. Not random, so every account can buy it." 22 px, and `Buy` GemIcon + "75", 270x78. The button shows the reason
  instead when the server would refuse (owns x2 Pet XP: "You have x2 Pet XP"; the pass is still being checked: "Checking your
  passes..."; the potion bank is full: "Potion time is full"; not settled: "Loading...").

**Gems tab, phone:** five tiles 188x262 in the same sideways row as the Eggs tab: four packs (pile 72 px, amount 26 px, name
15 px, ribbon 15 px, buy 44 tall) and the potion tile (icon 64, "XP Potion" 17 px, "30 min \194\183 x2 pet XP" 15 px, buy 44 tall);
the same fit rule as the egg cards on shorter bodies (the pile shrinks first).

### 5.5 The egg stage

`src/client/UI/EggStage.lua`, ScreenGui `NimbusHatch`, DisplayOrder 25 (over the shop and the picker, under Notify 30),
`IgnoreGuiInset = true`, a navy dim over the whole screen, its root frame `Stage`. EggStage owns the `RouletteResult` listener,
its queue and the one request path `EggStage.Request` (5.4), so every spin (the shop's cards, SPIN AGAIN, and the Storm Altar's
Summon, which opens the shop) is sent and played here. While the stage shows, the Shop window hides and comes back on DONE.
A result in today's old shape (no `Pulls`) plays as one pull read from the top level; a pull without a `Strip` skips straight to
the crack. The strip draws eggs, so today's strip-pet pre-warm (`MenuController.IsPrewarmed`) goes; EggStage warms only the pulled
pets for the reveal viewport while the strip runs (`EggStage.IsPrewarmed(petId)`).

**Order of a roll** (times: normal about 6 s / Fast hatch about 2 s):
1. Strip (3.6 s / 1.1 s): the 40 cells scroll with today's ease (`Curve 2.8`) and stop with cell 34 under the gold pointer.
2. Land (0.3 s / 0.15 s): the pointer bounces, the landed egg glows in its rarity.
3. Crack (1.4 s / 0.5 s): the egg moves to the centre at 380 px with "EPIC EGG!" (rarity word upper case + " EGG!") at 80 px;
   it shakes twice (one shake on Fast hatch) and cracks: the top and bottom halves (`EggArt.Halves`) part along a zigzag.
4. Pop (0.35 s / 0.25 s): the pet pops out of the shell, then the reveal.
5. Reveal (stays): the rarity word "EPIC!" 84 px at y 96 with turning rays behind, the shell halves, the pet 420 px
   (`CloudUI.PetViewport`, a gentle bob), its name 54 px at y 806 with a "NEW!" chip when `IsNew`, the note 24 px "1 of 3 Epic
   pets \194\183 added to your pets" (not new: "1 of 3 Epic pets \194\183 you have 2 Aurora Fox now", naming the pet so the
   count is not read as the number of Epic pets; a substitute: "Stack full: +800 Tokens instead"), `SpinAgain` "SPIN AGAIN"
   440x92 and `Done` "DONE" 220x92 at y 930. SPIN AGAIN sends the same roulette, currency and spins through `EggStage.Request`
   (it is a new paid request; it shows the price and is disabled with the reason when it cannot be paid or is locked). An evolved
   key keeps today's reveal: the evolved PetViewport (`Evolved` stage, `Detail = "Low"`) and the gold `EvolvedRibbon` ("Evolved" /
   "Evolved II"), on the x1 reveal and on each x3 column. "Put in team" is dropped (the pitch shows SPIN AGAIN and DONE; the Pets
   window does that job).

**Skip from the start.** From the first frame a `Skip` chip ("Tap anywhere to skip", 440x60 in the bottom bar; phone "Tap to
skip" 208x44 in the bottom bar) and a tap anywhere outside the buttons jump straight to the reveal (sounds stop, the flash plays
once). Esc, gamepad B or ButtonB skip; on the reveal they are DONE (bound above the shop's priority, 5.4). No delay, no hidden
period, no slow-down over a rarer egg.

**x3.** Three strips at once (PC: y = 230 + j * 260, 230 tall, cells 190x210 step 206, egg 130; phone: 824x74 at y = 94 + j * 80,
cells 76x66, egg 48), landing 0.25 s apart; the three eggs crack together at 220 px (phone 96) side by side; the reveal shows
three columns (PC 520 wide at x 180 / 700 / 1220: word 56 px, pet 300, name 36 px, NEW!, note 20 px; phone 260 wide: word 22 px,
pet 130, name 18 px, NEW!) with one SPIN AGAIN (x3) and DONE row. The flash and sound follow the best pull.

**x1 strip sizes.** PC: title (the machine's name) 52 px at y 150, the strip at y 360, 296 tall, cells 230x250 step 246, egg 160
with its rarity word 24 px under it. Phone (my call, fitted under the 58 px top bar): title 28 px at y 64, the strip at y 110,
170 tall, cells 130x160 step 138, egg 104, word 16 px; crack egg 200 px with "EPIC EGG!" 40 px; reveal: word 40 px at y 62, pet
170 px at y 104, name 26 px at y 276 with NEW!, note 15 px at y 308, SPIN AGAIN 220x44 and DONE 120x44 at y 334.

**Other screens (a layout rule, not a fixed picture).** The positions above are the two reference screens. Sizes are design px
at the windows' factor (scale = `Theme.ScreenFactor(h)` on PC, 0.8 .. 1.25; scale 1 on phones, so phone text never drops under
15 px): the design canvas is (w / scale) x (h / scale), e.g. 1600x900 at 1280x720. The phone layout is used where `BigRect` says
Phone. Every layout is placed from three anchors: the title band from the top (under the 58 px top bar), the bottom bar from the
bottom edge (12 px margin, above the bottom inset: SPIN AGAIN / DONE, the Skip chip, the Fast hatch toggle), and the middle (the
strip, the crack egg, the reveal's word, pet, name and note) centred in the space between. The middle shrinks to fit that space:
the strip cells and the reveal pet scale together down to 0.6 of their size (phone reveal pet at least 110 px); text sizes do
not shrink. Widths: rows are centred; the x3 strips are (canvasW - 20) wide and the x3 reveal columns (canvasW - 24) / 3 each
whenever the canvas is narrower than their design width (824 / 780 on a phone), so a 640 px phone still shows all three pets.
Portrait (360x640, 390x844): the strips stacked full width under the title, the crack egg and the reveal centred, the x3 reveal as
three rows (pet 110 px at the left, name, NEW! and note at the right), the bottom bar above the bottom inset. Test sizes: 640x360,
667x375, 844x390, 360x640, 390x844, 1280x720, 1366x768, 1920x1080.

**Big effects only for Legendary and up.** Legendary, Mythic and Secret: a full-screen gold flash (rgb(242,182,68), 0.25 s in,
0.6 s out) on the crack, the reveal's rays, the land and reveal sounds at full volume. Common to Epic: no flash, only the egg's
rarity glow (5.6) and quieter sounds. A server chat line for Legendary and up only: `ANNOUNCE_ORDER` becomes
`rarityOrder.Legendary` (was Rare). The announcement is once per request, not per pull: the best pull of the request, with
" (+N more)" when several pulls are Legendary or better: "<DisplayName> hatched a <Rarity> <Pet name>!". At most one announcement
per player every `ANNOUNCE_GAP` 10 s; any that come sooner are held and sent as one line ("... (+N more)", the best of them
named) when the gap ends, so an x3 spender cannot flood the server chat. `announcePull` sends `Notify` kind `"pull"`; `NotifyController` shows kind `"pull"` as a system chat line
(`TextChatService` channel `RBXSystem`, `DisplaySystemMessage`, the rarity word coloured by `Config.Rarities`) and falls back to
today's toast when the channel is missing. Timing as today: the other players at once, the puller after `ANNOUNCE_DELAY` 5 s
(after his reveal).

**Fast hatch.** A saved setting: `Settings.FastHatch` (bool, default false) through the existing `SettingsSet` remote; it follows
the player to every device and server (my call: the profile, not the device). Server: `DataService` adds `"FastHatch"` to
`P5.SETTING_KEYS`, `false` to `SETTING_DEFAULTS` and a boolean rule to the validation, and `toStored` writes `FastHatch` only when it
is true (missing = false). Without that, every stored record that already has a non-default setting would gain
`FastHatch = false` on its next save, since `toStored` copies the whole Settings table. Client: `src/client/ClientSettings.lua`
adds `"FastHatch"` to `KEYS`, `FastHatch = false` to `DEFAULTS` and a boolean rule to `Clean` (without a DEFAULT, `Set` refuses the
key); `State.lua`'s settings cleaner keeps it. Both toggles call `ClientSettings.Set` / `Get` and listen to
`ClientSettings.Changed` (the 0.4 s debounce, the local apply). The toggle is on the PC shop body (5.4) and on the stage's bottom
bar (PC 280x52 at the right; phone 150x44 at the right, inside the screen), both bound to the same value; a change applies to the
next roll.

**Queue and waits.** Results that arrive while a roll plays wait in the queue. SPIN AGAIN keeps the reveal up until the answer;
after `WAIT_TIMEOUT` 7 s it re-enables with a toast. A failure answer never opens the stage (a toast with the reason). A success
that arrives after the timeout still plays (or, when the stage cannot open, toasts its pulls). When a match starts (or
`MenuController.Close()` runs) the stage closes and the pulls not yet shown are toasted in one line ("You hatched: Aurora Fox,
Moonlit Owl, Candy Unicorn"), so a paid x3 is never lost from view.

**Sounds.** No new sounds; the names are `AudioIds` keys played through `SoundFx.Play`: `SpinStart`, `SpinTick` and `SpinLand` for
the strip as today; the crack plays `Shatter`; the reveal keeps today's map (Common / Uncommon `RevealCommon`, Rare / Epic
`RevealRare`, Legendary / Mythic / Secret `RevealLegendary`). Common to Epic play with `opts.Scale = 0.6`, Legendary and up with
`1`. `smoke_audio` checks these names.

### 5.6 How eggs look (egglook C)

`src/client/UI/EggArt.lua` draws an egg from frames: `EggArt.New(parent, rarity, size)` and `EggArt.Halves(parent, rarity, size)
-> top, bottom`. One shape for all seven (an oval body: UICorner 0.5, width 0.8 x height), a top-to-bottom gradient (top = the
rarity colour mixed 38% toward white, bottom = mixed 28% toward black; Secret: rgb(74,68,104) to rgb(18,16,28)), a navy outline
rgb(11,16,48), a white highlight on the upper left, and the rarity's sky-weather mark, big and bright (Gemini's tweak):

| Egg | Mark |
|---|---|
| Common, Cloud Puff | three white cloud puffs across the lower half |
| Uncommon, Breeze | a curved white breeze band and a green leaf |
| Rare, Raindrop | three blue-white raindrops |
| Epic, Thunder | a gold lightning bolt (three thin rotated bars) |
| Legendary, Sunburst | a sun disc with eight short rays |
| Mythic, Aurora | two or three wavy aurora bands (green -> cyan -> pink gradients) |
| Secret, Starry Night | the dark body, five to seven star dots, a crescent moon, a violet glow rgb(138,92,255) |

Glow behind the egg (a soft disc built from stacked round frames): none for Common and Uncommon, then strength Rare 0.22, Epic
0.34, Legendary 0.58, Mythic 0.66, Secret 0.78. The exact shapes are `eggSymbol("C", r)` in the pitch page. Colours come from
`Config.Rarities`. When `TextureIds` later has `egg_<rarity>`, `egg_<rarity>_top`, `egg_<rarity>_bottom`, an ImageLabel replaces
the frames with no other change (those textures would be rendered from the 3D eggs below; not tonight).

**The 3D eggs (made tonight).** `blender/kit/props/lobby_shop.py`, prop `lobby_egg`, mesh keys `egg_common`, `egg_uncommon`,
`egg_rare`, `egg_epic`, `egg_legendary`, `egg_mythic`, `egg_secret` (catalog `blender/catalog/lobby.json`, manifests in
`src/shared/MeshManifests`): one 2.25 x 3 x 2.5-stud egg shape with seven sky-weather paint sets, pivot at the bottom centre,
attachment `Center`. They are used in the world, not the GUI: the seven eggs stand in rarity order on a low stone shelf in front
of the Egg Guide board at the trove's old spot (5.9), in the board's order, so the guide shows the real eggs. Each is tagged with
`Mesh.tag(part, "egg_<rarity>", ...)`; until ids exist each is its Part fallback (a Ball-shaped part 2.25 x 3 x 2.5 in the rarity
colour, SmoothPlastic, the Secret egg dark with its violet tint).

### 5.7 How gems look (gemlook A)

**`src/client/UI/GemIcon.lua`** (new):
- `GemIcon.New(parent, size, opts) -> Frame "GemIcon"` (square): one 45-degree diamond with its top tip cut flat by an unrotated
  clipping frame (the table, the crown and the pavilion of a cut gem), three cyan-blue tones (light `Theme.Currency.Gems.Glow`
  rgb(186,236,255), mid `Theme.Currency.Gems.Color` rgb(84,196,246), dark rgb(40,120,200)) through a UIGradient and an inner
  facet diamond, a navy outline (UIStroke rgb(11,16,48), thickness size / 16, and a navy bar on the cut), a small white
  four-point star on the upper left. `opts = { Shine = bool (default true), ZIndex, Name }`.
- Small sizes: under 28 px the icon draws a simple form: the silhouette (the cut diamond), two tones (light top, mid bottom), a
  navy outline of at least 2 px snapped to whole pixels, no inner facet and no star (at 19-24 px those blur into each other).
- Shine: a thin white bar sweeps across the gem every ~3.5 s for 0.6 s when the icon is at least 20 px (so the HUD gem shines too)
  and the graphics setting is High; all icons share one Heartbeat driver (a weak-keyed registry; an icon out of the tree drops out).
- `GemIcon.Pile(parent, size, count)` (count 1, 2, 3, 4 or 6; the pitch's `PILE` offsets) and `GemIcon.Amount(parent, n, opts)`
  (icon + the number in the Display font, for "gem + 1,000" spots).
- When `TextureIds.gem_icon` exists later, an ImageLabel replaces the frames.

**Every gem glyph swapped** (the glyph is `Theme.Currency.Gems.Glyph` = `"\226\151\134"`):
- `NeonKit.Icon("Gems")` returns a TextLabel with empty Text hosting a GemIcon (callers that set Text properties stay safe):
  this covers `DailyController` and every other `NeonKit.Icon("Gems")` caller with no change to them.
- `HudController` (the gems coin, `newCoin(def.Glyph)` through `CURRENCY_ORDER`): a GemIcon for Gems. The coin badge behind it
  changes for Gems only: today `newBadge` fills it with the gem's own cyan (`badgeSequence`), so a cyan gem on a cyan badge would
  be separated only by its thin outline. For Gems the badge is the navy panel fill with a cyan neon ring (UIStroke), and the gem
  sits on it at coin size.
- `StoreController` balance pills (line ~575) and pack art (`H.artGlyph`, line ~776): a GemIcon in the pill; a `GemIcon.Pile`
  (1 / 2 / 4 / 6 by pack order) for the gem packs.
- `ShopController` and `EggStage`: built with GemIcon from the start.
- `ArenaController` (lines ~162, ~1887, "% for <glyph> n") and `DungeonController` (lines ~209, ~1646, ~1933, ~1939,
  `R.lootText`): text-only strings use the word ("+12 gems", "for 40 gems"); labels with room use `GemIcon.Amount`.
- `FusionController` (after the merge): the header `GemChip` (gui-redo builds its text from the glyph,
  `U.GemChip.Text = GEM_INFO.Glyph .. " " .. balance`, and sizes the chip from that text) becomes a `GemIcon.Amount`, its width
  from icon + number (one local change). The Mix cost bar needs no change: gui-redo already draws it with
  `NeonKit.Icon(U.CostIcon, currency, ...)`, which the `NeonKit.Icon("Gems")` change covers.
- `tools/dump_gui.lua` gallery (`NeonKit.Pill` Glyph; line from the merged tree): the gallery shows a GemIcon.
- Server toasts and chat lines keep words, never the glyph.

**World gem** (Blender, made tonight: `blender/kit/props/lobby_shop.py`, prop `lobby_gem`, mesh key `gem_world`; manifest in
`src/shared/MeshManifests`): the same cut (an octagonal crown with its table, a pavilion in kite halves), 6 studs across the
girdle, the GUI gem's three tones, a navy girdle, a white Neon glint; `gem_world_low` (0.5-stud voxels) is made for later
1.5-stud drops and not used. Part fallback: one 4x4x4 Glass block in the gem colour turned 45 degrees on X and Z, so it still
reads as a gem. Placed on the Storm Altar's deck beside the path
from the landing to the summon portal (at least 6 studs from any prompt, off the walking line), 3 studs above the deck, tagged
`NC_Spin` (`SpinSeconds 8`, `BobStuds 0.6`, `BobSeconds 3`), a PointLight 1.0 / 12 (cyan). It marks "gems are spent here".

### 5.8 The Robux Store (unchanged except three things)

1. `Config.Store.Tabs` `"Roulettes"` -> `"Eggs"` (same tab, same content: the hop to the Cloud Shop); glyph
   `NeonKit.Glyphs.Eggs = "\240\159\165\154"` (egg); `TAB_COLORS.Eggs = "Green"`; `StoreController` accepts `"Roulettes"` as an
   alias of `"Eggs"` for old callers.
2. Gem art: the pills and the gem pack tiles use GemIcon / `GemIcon.Pile` (5.7). No ribbons here (pitch B keeps the Store as
   approved; the honest ribbons live in the Cloud Shop's Gems tab).
3. The amounts that come from Config: gem packs 150 / 500 / 1,500 / 4,000 and token packs 1,000 / 5,000 / 20,000 with their names.

**`StoreRequest("GemBuy", key)`** (new action, server `StoreService.BuyWithGems(player, key)`). Today `StoreService.onRequest`
drops every action except "Buy" before its rate limit, so it changes to accept "Buy" and "GemBuy" and rate-limits both on the one
key "StoreRequest" (`REQUEST_GAP` 1 s, shared). Checks: a live player, `key` a string in `Config.Store.GemItems`; refused in a
match ("The Store is closed during a match"), while loading or provisional ("Your save is still loading"), before the server has
settled (5.2, "Your data is still loading"), by the x2 Pet XP pass (`PetXp2x`) by its `StoreService.PassState`: "Owned" refuses
("You already have x2 Pet XP": the potion would add nothing), "Checking" refuses ("Checking your passes...": the lookup is still
running or failed, and a pass owner must not pay 75 gems for nothing), "NotOwned" and "Unavailable" allow; when the potion bank
plus 1,800 s passes `Config.Store.Potion.CapSeconds` (7 days; "Your potion time is full"), when gems are short ("Not enough
gems"). Restricted accounts may buy it (not random). One non-yielding step:
`DataService.SpendGems(75)` then `DataService.AddBoost(player, "XpPotion", 1800)` (AddBoost's own refusals are checked first,
so the second write cannot fail after the first); a toast "XP Potion: +30 minutes"; `StoreService.Changed:Fire(player)` (the
`XpBoostEnds` attribute updates). No receipt, no purchase id.

### 5.9 The trove on the plaza (pitch chest A)

- Position: polar 43 degrees, radius 56 from `Config.Lobby.Origin` (about x 40.96, z 38.19), facing the plaza centre
  (`faceCentre`): the front-left lawn as seen from the spawn (the spawn looks along +Z, so +X is the player's left; the pitch's
  "right" is the top-view map). Beside the How to play board (32 degrees, r 48) and the bench at 50 degrees, in view at the
  spawn. Radius 56, not the card's 55 (my call): at 55 the trove's clearance circle (6.5) and the board's (6) overlap by a
  fraction; at 56 the centres are 12.75 apart (12.5 needed), the bench 13.4, the Obby gate's sight line 10.45 off. Placed with
  `plazaSpot` (it warns "plaza decor skipped" when not free; a test fails on that warn).
- Which builder: the trove stays in `buildShop` (which runs before `buildPlaza`, so its `plazaSpot` reservation comes first; the
  reservations reset only at the start of `Build`), now at that plaza CFrame on the plaza lawn height instead of `at(-21, -8)`.
  `fallbackShop` builds its fallback trove at the same plaza spot (not `S + (0, 0, 12)` on the island), so there is only ever one
  trove, on the plaza.
- The body, lid, sign, glow (`TroveGlow` 1.2 / 14) and prompt stay as built by `buildTrove`; its sign post moves to the mirrored
  side (local x -6.2 instead of +6.2) so it does not stand behind the How to play board; mesh keys `prop_trove_body/lid/sign`
  unchanged.
- New: an invisible `JoinAnchor` part (+1 part, the trove stays at most 60) with a BillboardGui `JoinBillboard`: "Join the group!"
  and the reward line ("2,000 Cash + 200 Tokens") when `Config.Trove.GroupId > 0`; while `GroupId` is 0 (today) one line only,
  "Group rewards coming soon!", so no kid is asked to join a group that does not exist yet. Tagged `NC_Bob` (the client bobs it
  0.5 studs over 2.4 s).
- `Config.Attr.TroveGroupDone` (new). `TroveService` (whose `Init` today wires only the prompt, `TroveRequest` and
  `PlayerRemoving`) sets it from the saved claim (`trove.Group == true`, what `groupState` reads) on `DataService.ProfileLoaded`
  and `DataService.ProfileRebased` for a loaded, non-provisional profile, and at claim time. The client hides the billboard for
  that player only, so a player who claimed in an earlier session never sees "Join the group!" again.
- `LobbyInfo.Shop.ItemShop` keeps its shape (`{ PromptPart, Center, Model, Lid }`); `TroveController` / `TroveService` work as
  today.
- The old spot on the shop island (`at(-21, -8)`) gets an "Egg Guide" notice board (11x8, `prop_board_s`): the seven egg names in
  rarity colours, left to right in rarity order, and one line "Every egg hatches a random pet of its rarity", with the seven 3D eggs
  (5.6) in the same order on a low stone shelf (about 18 studs wide) in front of it, inside the island's free space and off the
  walking lines. The rarity board at `at(21, -8)` keeps its title, its subtitle becomes "Every egg hatches a pet of its rarity".

### 5.10 The global leaderboard (pitch board A)

**Server** `src/server/Services/LeaderboardService.lua` (new; booted in `Main.server` after DataService):

- `Config.Leaderboard = { Stores = { Trophies = "NimbusClimb_LB_Trophies_v1", Pets = "NimbusClimb_LB_Pets_v1",
  Wins = "NimbusClimb_LB_Wins_v1" }, Pages = { "Trophies", "Pets" } (+ "Wins" once measured, below), Labels = { Trophies = "Trophies",
  Pets = "Pets found", Wins = "Climb wins" }, Top = 10, ReadSize = 100, RefreshSeconds = 240, WriteEvery = 120,
  SweepSeconds = 60, SeedDelay = 30, RetrySeconds = { 30, 60, 120, 240 }, BudgetFloor = { Write = 20, Read = 2 },
  TurnSeconds = 15, FallbackRefresh = 30, MaxValue = 1e12, WriteInStudio = false }`.
- Stats: Trophies = `Battle.Trophies`; Pets = the number of valid pet ids in `Discovered`; Wins = `Stats.Wins` (obby climbs won,
  `RecordMatch`). Values are whole numbers clamped to 0 .. `MaxValue`; the key is `tostring(UserId)`.
- **Climb wins must not be farmable before they go global.** Today `MatchService` finishes a player whenever their root stands
  over the Finish pad (`processPlayerPlaying`; `markFinished` checks no checkpoint and no time), a solo match is allowed
  (`Config.Match.MinPlayers = 1`) and one finisher alone is a victory. A client that moves its own character onto the pad after
  "Go!" would win about every 30 s, each win adding `Stats.Wins`, a near-zero best time and `TokenBonusOnWin`. One local change in
  `MatchService` (not a gui-redo file): the Finish pad counts only when the team has reached the last checkpoint in order
  (`nextCheckpointIndex(match) == nil`) and at least `Config.Match.MinFinishSeconds[difficultyId]` have passed since `StartedAt`;
  otherwise the pad is ignored (a toast "Reach the last checkpoint first!" at most every 5 s), and there is no finish, no
  `RecordMatch` win and no `TokenBonusOnWin`. `MinFinishSeconds` is about 40% of the fastest clean run of each difficulty, measured
  in Studio by the main session (section 10) and written to Config with the measured runs in the ledger. Until those values are
  measured, `Config.Leaderboard.Pages` is `{ "Trophies", "Pets" }` (the Wins store name stays reserved) and the build ships the
  board with two pages; the commit that sets the measured values adds "Wins" back.
- Writes (`OrderedDataStore:SetAsync`, pcall): only for a loaded, non-provisional profile; the first write of a session at least
  `SeedDelay` 30 s after the load and only if the value is above 0; then on change, at most once per `WriteEvery` 120 s per stat
  (a sweep every 60 s writes what changed); one write of what changed when the player leaves; `BindToClose` writes for at most 5 s.
  Before a write `DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementSortedAsync)` must be at
  least 20, else it waits for the next sweep. No writes in Studio (`WriteInStudio = false`).
- Reads: at boot the stats are read once each, a few seconds apart; then every `RefreshSeconds` 240 s per stat,
  `GetSortedAsync(false, 100)` first page (budget at least 2, pcall); a failure keeps the last good page and retries after
  30 / 60 / 120 / 240 s. Names through `UserService:GetUserInfosByUserIdsAsync` (batched, cached for the server's life), falling
  back to `Players:GetNameFromUserIdAsync`, then "Player".
- Remote `LeaderboardState` (server -> client, appended to `Config.Remotes`): per player
  `{ Stats = { [stat] = { Top = { { UserId, Name, Value }, ... up to 10 }, You = { Rank = n | nil, Value | nil } } },
  Scope = "Global" | "Server", NextAt, UpdatedAt }`, sent on join (after the profile loads), after each refresh, and when the
  player's own value changes. DataService has no change signal for `Battle.Trophies`, `Discovered` or `Stats.Wins`, so a 5 s poll
  reads the in-memory values of the players in this server and sends only on change. `You.Rank` comes from the 100 read; outside
  it Rank is nil. `You.Value` is the live profile value, and nil while the profile is loading or provisional (the client shows
  "..."; a stand-in value is never shown). `NextAt` and `UpdatedAt` are `workspace:GetServerTimeNow()` times, and the client counts
  with the same clock, so the countdown is right on any device clock.
- Fallback: the scope is `"Server"` (the live values of the players in this server, sorted, refreshed every 30 s; no writes) when
  the OrderedDataStore is unavailable (Studio without API access, the mock), after 2 failures in a row before the first good read,
  and from boot until the first good global page arrives (so a fresh server never shows an empty board for 4 minutes).
- The client sends nothing; nothing a client says reaches a write.

**World** (new module `src/server/Services/LobbyBoardBuilder.lua`, called by `LobbyBuilder` with its helpers, so LobbyBuilder's
locals stay at or under 159): Model `LobbyLeaderboard` at polar 295 degrees, radius 48 (about x 20.29, z -43.50), facing the
plaza centre, placed with `plazaSpot` at clearance 9 (checked: fountain centre 30.3 away, 24 needed; the roundabout path ends at
radius 16 from the fountain, the board's circle is 21.3 out; the boardwalk edge 4.3 clear; NPC spot 305 degrees 24.2, bench 340
degrees 35.4, flower bed 290 degrees 33.4, spawn 48 away). A 16x13 stud face part `Face` (front = toward the centre), two posts,
a frame and a small roof: Blender `prop_board_lb`, a new prop `lobby_board_lb` added to `blender/kit/props/lobby_shop.py` (the
same family as the eggs, gem and ring made tonight; not made yet, so it is a build task), with the Part fallback until its
id exists; no light (none needed). (The uploaded `prop_board_l` fits only a 14x9 face, too small for ten rows at the 0.6-stud text
floor, and `arena_board_leader` is a LayoutSig manifest tied to the arena's build, so neither is reused.)

**Client** `src/client/Controllers/LeaderboardController.lua` (new): a SurfaceGui `LobbyLeaderboard` in PlayerGui, `Adornee` =
the board's `Face`, `Face = Front`, `PixelsPerStud 50` (800x650 px), `MaxDistance 80`, `ResetOnSpawn false`, re-adorned when the
lobby is rebuilt. Layout (the mock `boardA`): the title "TOP TROPHIES" / "TOP PETS FOUND" / "TOP CLIMB WINS" (50 px); one tab per
page in `Config.Leaderboard.Pages`, `Tab_Trophies` / `Tab_Pets` / `Tab_Wins` (tap to switch; the page also turns by itself every
15 s, and a tap restarts that count); the scope line "All players \194\183 all time" (Server scope: "This server only");
`Row1` .. `Row10` 38 px each (rank, a 34 px headshot `rbxthumb://type=AvatarHeadShot&id=<UserId>&w=48&h=48`, the name, the
value, text 30 - 32 px; the top three ranks in gold, silver, bronze); `YouRow` "You \194\183 1,240 \194\183 #37" or
"You \194\183 1,240 \194\183 not in the top 100"; `Footer` "Refreshes in m:ss \194\183 tap a tab, or it turns in 0:ss" counted from
`NextAt`. Every text on the board is at least 30 px (0.6 stud at 50 px per stud, the project's world-text floor). Before the first
`LeaderboardState`: "Loading scores...". Empty page: "No scores yet. Be the first!". The project's world-text census
(`smoke_polish_worldtext`) walks only workspace GUIs, so `smoke_lb_ui` applies the same 0.6-stud rule to this PlayerGui SurfaceGui.

### 5.11 The altar portals (pitch portal C)

**(a) The Storm Altar gate on the plaza.** `Gates.Info.Altar` gets `Pad = true` (the 14x14 pad 14 studs in front, its Neon inlay
and lanterns, as the Obby gate has), `Info = "Secret pets"` (the sign reads "STORM ALTAR" / "Secret pets"), a `Pill`
("Secret Roulette") and `VortexBoost = 1.4`. `Gates.BuildOne` today forwards only Id, Title, Info, Color, Glyph, Pad and Name to
`WorldStyle.BuildGate`, so it also forwards `Pill` and `VortexBoost` (and the fallback gate takes them too); `BuildGate` already
reads `spec.Pill` and writes `VortexBoost` as an attribute on the gate model.
- Why not a brighter swirl: `PortalFxController` shows a `PortalVortex` on every gate within 150 studs (the whole plaza), at every
  graphics level, and while it shows, `PortalVortex.SwirlLook` sets the swirl to Transparency 1 behind a hoop's textured disc (or
  0.3 deep tint in Fallback mode). A 0.35 built swirl would never be drawn on the plaza. So the swirl stays as built, and
  `PortalVortex.Build` / `SwirlLook` read the gate model's `VortexBoost` (default 1): above 1 it lifts the vortex tint toward
  white and its glow by that factor (the Altar reads clearly brighter than the Obby gate at the same distance).
- The `gate_altar` mesh keeps its parts; the pad parts are Part builds beside it. The return from the altar (`ReturnCFrame`) lands
  on the pad's front half, 3 studs over the pad top (about 3.7 over the ground: the pad part is 0.6 tall, its tiles up to 0.68),
  so the kept arrival checks measure from the pad top (section 9). `GateService` keeps the "Travel" prompt as the only way in; the
  builder checks that nothing treats every gate's pad as a trigger (grep the `LobbyInfo.Gates[*].Pad` readers) and makes any such
  reader skip the Altar.

**(b) The summon portal on the altar** (today a dark navy disc, light 1.3 / 14): a new sibling Model `PortalGlow` next to the
`Portal` model (the Portal model is untouched, so the `prop_altar_portal` LayoutSig still matches): a Neon disc overlay just in
front of the old disc in the crystal cyan rgb(63,200,255) with a lighter heart, a ring of ~16 Neon segments around the rim
(Blender `portal_altar_ring`, a new prop added to `blender/kit/props/lobby_shop.py`, not made yet, so a build task; the ring of
Neon Part segments is its fallback until its id exists) tagged `NC_Spin` (`SpinSeconds 6`), rising sparkles, a PointLight 1.5 / 24,
and a sky beam about 160 studs up (a Beam between two attachments, `FaceCamera`, no texture, cyan to white, transparency rising
with height) so the altar is found from the plaza.

**(c) The way back** (`ReturnPortal`, today a flush 4-stud navy octagon, light 0.8 / 7): a standing ring about 9.5 studs tall in
the Arena Return-gate green (`WorldStyle.Accent.Green` rgb(96,190,140)), the Blender mesh made tonight: `blender/kit/props/
lobby_shop.py`, prop `lobby_portal_ring`, mesh key `portal_ring` (manifest in `src/shared/MeshManifests`: bounds 9 x 9.5 x 3, a
13-stone ring on a 7 x 1 x 3 two-step plinth with buttresses, a Primary-tinted Neon rim, attachments `PortalCenter`, `SignFace`
and `Pad` on the plinth top). Placement and collision:
- `RETURN_SIDE` moves from 5.5 to 9. The ring faces the altar (as the pad does today), so it spans about 4.5 to 13.5 studs off the
  bridge's centre line: clear of the 8-stud bridge lane and 4-10 studs from the landing, inside the deck's walkable edge. At 5.5 its
  9-stud width would reach 1 stud from the centre line, inside the walking lane beside the landing.
- Every ring part (the mesh and the Part fallback) has CanCollide and CanTouch false. The mesh is one Fixed part (plinth, ring,
  keystone together), so it is set 0.85 studs lower than its pivot: the plinth top ends 0.05 under the octagons' top (no
  z-fighting) and the plinth sinks into the deck. The two flat `Pad` octagons (0.2 tall, collidable) stay as the only floor.
- `ReturnPrompt` (the invisible anchor 2.5 studs up that `GetReturnPad` returns and GateService adds the prompt to) stays as it is.
  The new PointLight 1.3 / 14 replaces `ReturnGlow` (0.8 / 7) on that anchor, so the light rule counts one light. Sparkles stay.
- A "To the Plaza" text on the ring's `SignFace` (a SurfaceGui at 50 px per stud, lines at least 0.6 stud; on the Part fallback a
  BillboardGui). The Part fallback: non-colliding Neon ring segments in the green and two stone feet outside the 4x6x4 box over the
  pad.
- The teleport, the `PlazaGatePrompt` (E, range 8) and the landing distance (4 - 10 studs) do not change.

The altar stays at most 500 parts (measured by `smoke_storm`; if over, the fallback rings use 12 segments).

### 5.12 Lobby motion

`src/client/Controllers/LobbyFxController.lua` (new): one Heartbeat for all lobby motion. `NC_Spin` (attributes `SpinSeconds`,
`BobStuds`, `BobSeconds`) turns and bobs a Model or Part around its pivot; `NC_Bob` bobs a BillboardGui through `StudsOffset`.
Only targets within 150 studs of the camera move; on Low graphics everything stays still. Users: the world gem, the summon
portal's ring, the Join billboard. The server never animates.

## 6. Data and save

| Field | Where | Default / old profiles | Merge | Notes |
|---|---|---|---|---|
| `Pity.Secret.Spins` | new top-level `Pity` | absent = 0 | delta | 5.2 |
| `Pity.Secret.Hit` | same | absent = 0 | max | `Hit <= Spins` after clean |
| `Settings.FastHatch` | existing `Settings` | absent = false | per key (as the other settings) | stored only when true (5.5) |
| `Stats.Spins` | existing | - | delta | now += spins per request (x3 adds 3) |
| (not stored) `GemsSettled` | the cache entry | false until the settle read (5.2) | - | never saved |

- No migration, no rewrite of old records, no marker. An old profile loads with no Pity (count 7 left) and Fast hatch off, and a
  load and save leaves it byte-identical until the player spins the Secret Roulette or turns Fast hatch on (Pity is left out while
  0 / 0, FastHatch while false).
- Older servers during a rollout keep `Pity` untouched (unknown top-level field, `keepForeign`); an older server that rewrites
  Settings may drop `FastHatch` (the worst case: the switch turns off once).
- `Pity` is wired through every DataService touch point listed in 5.2 (`KNOWN_TOP` first: without it this version itself would
  freeze the stored count).
- The pity count lives in the same profile write as the gem spend and the pet (`SetPity` in step 5 of the money step, one save;
  nothing in that step can refuse after the charge).
- `ResetFields` (dev) clears `Pity`. The ProfileSync snapshot carries `Settings.FastHatch`; the pity reaches the client by the
  attribute and the reply, not the snapshot.
- No session lock is added (the settle hold, 5.2, is the local guard; the session claim is a morning question).
- Leaderboard values are copies in OrderedDataStores, never read back into a profile; losing them loses nothing of the player's.
- `GemBuy` writes gems and the potion bank in one step; nothing new is stored.

## 7. Server rules and security

- `BuyRoulette`: `isLivePlayer`; `rouletteId` string <= 48 and known; `currency` through today's `parseCurrency` (junk answered
  "Unknown currency", as today); `spins` nil / 1 / 3 only, 3 never on the Secret Roulette: the remote drops anything else
  silently, the public function answers "Bad spins". The price comes from Config (`Price = UnitPrice * spins`, computed once),
  never from the client; the roll, the strip, the pity and the grant are server work; the reply is a report.
- One non-yielding step from the checks to the last write (no `task.wait`, no DataStore call, no remote call inside), and nothing
  in it refuses after the roll: a full stack re-picks inside the rarity or pays the substitute tokens. Everything that can fail runs
  before the charge; after the charge only plain writes. The refresh, the Sync, the events and the announce run after it, each in
  pcall.
- The pulls come from a server-wide engine-seeded `Random.new()`; the strips from a second one; neither seed is derived from the
  clock or sent.
- The pity is read from the saved profile only (refused while provisional); the attribute is written by the server, never read
  back. Gem-priced actions wait for the settle read after a load (5.2).
- `StoreRequest("GemBuy", key)`: the checks in 5.8, one step; `onRequest` accepts "Buy" and "GemBuy" on one shared 1 s gap.
- `MatchService`: the Finish pad counts only after the last checkpoint in order and `MinFinishSeconds` (5.10); no win, no
  `RecordMatch` win and no `TokenBonusOnWin` otherwise.
- `LeaderboardState` is server -> client only; LeaderboardService writes only from loaded, non-provisional profiles, clamps
  values, honours the request budget, and never writes in Studio.
- `SettingsSet("FastHatch", value)`: a boolean or dropped (the existing validation path).
- No client-supplied number reaches a price, a roll, a count or a leaderboard value. The PolicyService lock is unchanged.

## 8. File map

| File | Change |
|---|---|
| `src/shared/Config.lua` | `Gems` prices / products (+ `Robux`) / `SecretRoulette.PityAt` / `SettleSeconds`; `Store.Tabs` Eggs; token pack amounts and names; `Store.GemItems`; `Eggs`; `Leaderboard` (Pages without Wins until measured); `Match.MinFinishSeconds`; `Attr.SecretPityLeft`, `Attr.GemsSettled`, `Attr.TroveGroupDone`; remote `LeaderboardState`; Remotes comments (`BuyRoulette -- (rouletteId, currency, spins)`, `StoreRequest -- "Buy" / "GemBuy"`, `SettingsSet` FastHatch) |
| `src/shared/PetCatalog.lua` | `RollRarity`, `RollFromRarity`, `RarityPool`; `RollPet` built from them (same draws); `findRoulette` also knows `Config.Gems.SecretRoulette` (one odds source) |
| `src/shared/TycoonCatalog.lua` | `Fusion.Mix` gems 50 / 125 |
| `src/shared/StoreCatalog.lua` | reads the new gem amounts; `gemItem` copies `Robux`; gem items for the Gems tab |
| `src/server/Services/PetService.lua` | `BuyRoulette` spins, the never-refused-after-the-roll batch (re-pick / substitute), `RollRng` / `StripRng` and `_SetRngForTest`, `addCopies` split into plan + write, reply shape, pity, `ANNOUNCE_ORDER` Legendary, one announcement per request with `ANNOUNCE_GAP`, Notify kind "pull" |
| `src/server/Services/GemService.lua` | `RollPet` `opts.ForceRarity`; the gems-only odds functions delegate to PetCatalog; prices from Config (no hard numbers) |
| `src/server/Services/DataService.lua` | `Pity` field (every touch point in 5.2), `GetPity` / `SetPity`, `GemsSettled` + the settle read, `FastHatch` setting key (stored only when true); no new column-0 locals |
| `src/server/Services/StoreService.lua` | `onRequest` accepts "GemBuy" on the shared gap, `BuyWithGems` (PassState rule, settle hold) |
| `src/server/Services/MatchService.lua` | the Finish pad counts only after the last checkpoint and `MinFinishSeconds` (5.10) |
| `src/server/Services/FusionService.lua` | after the merge: the gem Mix checks `GemsSettled` (one line) |
| `src/server/Services/LeaderboardService.lua` | new (5.10) |
| `src/server/Services/LobbyBoardBuilder.lua` | new: the leaderboard board and the Egg Guide board |
| `src/server/Services/LobbyBuilder.lua` | trove placement 43 degrees r 56 (in `buildShop` and `fallbackShop`), sign post mirrored, `JoinAnchor` / `JoinBillboard`, calls LobbyBoardBuilder (board, Egg Guide and its egg shelf), rarity board subtitle, `Gates.Info.Altar` Pad / Info / Pill / VortexBoost, `Gates.BuildOne` forwards Pill and VortexBoost |
| `src/server/Services/TroveService.lua` | attribute `TroveGroupDone` on ProfileLoaded / ProfileRebased and at claim |
| `src/server/Services/StormAltar.lua` | `PortalGlow` model and beam; `ReturnPortal` standing ring (`RETURN_SIDE` 9, non-colliding, sunk plinth, the light replaces `ReturnGlow`); world gem placement |
| `src/shared/WorldStyle.lua` | `BuildGate` writes the `VortexBoost` attribute (no swirl change) |
| `src/client/PortalVortex.lua` | reads `VortexBoost` in `Build` / `SwirlLook` |
| `src/server/Main.server.lua` | boots LeaderboardService |
| `src/client/Controllers/ShopController.lua` | new (5.4) |
| `src/client/UI/EggStage.lua` | new (5.5) |
| `src/client/UI/EggArt.lua` | new (5.6) |
| `src/client/UI/GemIcon.lua` | new (5.7) |
| `src/client/Controllers/LeaderboardController.lua` | new (5.10) |
| `src/client/Controllers/LobbyFxController.lua` | new (5.12) |
| `src/client/Controllers/MenuController.lua` | the shop, the stage and the client odds copy removed; the "shop" forwarder with the whole args; `normalizeTab` Eggs; `IsOpen` / `closeEverything` / window opens use the ShopController and EggStage hooks |
| `src/client/MouseLock.lua` | `WATCHERS`: `NimbusHatch` replaces the `NimbusMenu` stage / odds entries |
| `src/client/ClientSettings.lua` | `FastHatch` in `KEYS`, `DEFAULTS`, `Clean` |
| `src/client/Controllers/StoreController.lua` | Eggs tab rename + alias, GemIcon pills, gem pack piles |
| `src/client/Controllers/HudController.lua` | the gems coin uses GemIcon on a navy badge with a cyan ring |
| `src/client/Controllers/NotifyController.lua` | kind "pull" -> system chat line (toast fallback) |
| `src/client/Controllers/ArenaController.lua`, `DungeonController.lua` | the gem glyph replaced (words or `GemIcon.Amount`) |
| `src/client/Controllers/FusionController.lua` | after the merge: the header `GemChip` with `GemIcon.Amount` |
| `src/client/UI/NeonKit.lua` | `Icon("Gems")` hosts a GemIcon; `Glyphs.Eggs` |
| `src/client/State.lua` | settings cleaner keeps `FastHatch` |
| `src/client/Main.client.lua` | boots ShopController, LeaderboardController, LobbyFxController |
| `src/shared/TutorialSteps.lua` / `TutorialController` | only if the spin step's target path changed: it points at `ShopCard_Cloud.Spin` |
| `src/shared/MeshManifests/*` | made tonight: `egg_common` .. `egg_secret`, `gem_world`, `gem_world_low`, `portal_ring`; to make: `portal_altar_ring`, `prop_board_lb` (from `manifest_to_lua.py`; no MeshIds) |
| `blender/kit/props/lobby_shop.py`, `blender/catalog/lobby.json` | made tonight: `lobby_egg`, `lobby_gem`, `lobby_portal_ring`; to add: `lobby_altar_ring` (`portal_altar_ring`) and `lobby_board_lb` (`prop_board_lb`) |
| `tools/mesh_names.py` (or a new `tools/mesh_keys.py`) | a check: every `Mesh.tag` key in `src` has a manifest, and every manifest added by this build is tagged somewhere (`gem_world_low` listed as reserved) |
| `tools/robloxmock.lua` | `DataStoreService:GetOrderedDataStore` (whole-number values, `GetSortedAsync` pages, the existing `dsGate` failures), `GetRequestBudgetForRequestType`, `Enum.DataStoreRequestType` if missing, `UserService:GetUserInfosByUserIdsAsync`, `TextChatService` `RBXSystem` channel with `DisplaySystemMessage` if missing |
| `tools/sim_tycoon.py` | 5.3 |
| `tools/contract.json` | the new modules and public functions; `stormAltar` budget unchanged |
| `tools/dump_gui.lua`, `tools/render_gui.py` | the new scenes (section 9) |
| `README.md`, `BUILD_STATE.md` | gem prices, products, roulette table, eggs, leaderboard, trove spot |

## 9. Tests and evidence

New scenarios (each red on today's code first; files new unless named):

Server (`smoke_eggs.lua`: the `egg_*` cases; `smoke_pity.lua`: `secret_pity`, `secret_pity_save`, `gem_settle`;
`smoke_gem_prices.lua`: `gem_prices`, `gem_potion_buy`; `smoke_leaderboard.lua`: `match_finish_clean`, the `lb_*` cases;
`smoke_lobby_shop_world.lua`: `lobby_trove_plaza`, `altar_portal_glow`, `mesh_keys`):
- `egg_roll_pure`: for 10,000 seeded rolls per machine `RollPet` = `RollFromRarity(RollRarity)` pet for pet (same seeds as
  today's); rarity frequencies within 1.5 points of the Config odds; `RollFromRarity` only returns pets of that rarity from the
  rollable pool (no ExclusiveTo, no EventOnly); `ForceRarity` keeps the rng position; `PetCatalog.GetRarityOdds("Secret")` equals
  `GemService.GetRarityOdds("Secret")` row for row (Mythic 0.85, Secret 0.15, chance and count), and every roulette has at least
  one odds row.
- `egg_spin_x1`: the reply shape (Pulls[1] fields, the mirrored top level, `PoolSize`, `Strip` 40 with the winner at 34); the
  charge; `Stats.Spins + 1`; one Rolled; Legendary+ only announced (an Epic pull sends no "pull" Notify, a Legendary does).
- `egg_spin_x3`: three pulls, one charge of 3 x price (Cloud with tokens 150, Celestial with tokens 15,000, Sky with gems 180),
  `Stats.Spins + 3`, three Rolled, one Sync; Sky with gems x3 and only 179 gems -> refused, nothing written; never refused after
  the roll: full pets of the rolled rarity are skipped (the pick comes from the others), a whole full rarity pays the substitute
  tokens, and the charge is always taken; independence: over 2,000 x3 requests with seeded generators, batches of three identical
  pets stay under 2% (independent pulls give about 0.7%) and each pull position's rarity frequencies match the Config odds within
  the `egg_roll_pure` tolerance; junk spins (2, 3.5, "3", {}, 3 on Secret) dropped by the remote with no answer, while
  `BuyRoulette` answers "Bad spins"; junk currencies still answered "Unknown currency"; gems x3 locked for a restricted account;
  the 0.25 s cooldown counts one request; an error injected into `refreshPlayer` after the charge: the charge and all three pets
  still land together; an error injected into the plan step (before the charge): nothing charged or granted.
- `egg_full_stack`: Cloud with all six Commons at 99: over many paid spins the rarity frequencies still match the Config odds,
  each Common pull pays 50 tokens instead and the spin is charged; the Secret Roulette with both Mythics at 99: Mythic pulls pay
  5,000 tokens, Secret stays at 15%, the pity still counts.
- `egg_strip`: the strips come from `StripRng`, not `RollRng` (setting a fixed `RollRng` leaves the strips free); a forced pull's
  strip is drawn from the normal odds (over many forced spins the filler cells' Secret share is about 15%, not 100%); the three
  strips of one x3 differ.
- `secret_pity`: six Secret spins with a seeded `RollRng` that gives no Secret -> the 7th is Secret with `Pity = true`; the
  attribute counts 7 -> 1 and back to 7; a natural Secret on spin 3 restarts the count; refused spins do not count;
  provisional -> refused; `GetPity` nil -> refused with nothing charged; token roulettes do not touch it; a stand-in join that
  recovers through `ProfileRebased` gets the attribute; a rebase that brings another server's spins updates it; a merged `Since`
  of 8 shows 1 and forces the next spin.
- `secret_pity_save`: the count survives clean / encode / save / load; the same session saved twice with a Secret in between,
  then a fresh load shows Since 0 (7 left) (the `KNOWN_TOP` case); a second server's save does not replace the first server's
  Spins with the stored copy; two servers (deltas) add up and the max Hit wins; a rebase updates both the live `Pity` and the
  attribute; a failed save keeps spend, pet and count together; an old profile without `Pity` loads as 7 left and is
  byte-identical after a load and save (with default and with non-default Settings: `FastHatch` stays out while false) until a
  Secret spin; junk values cleaned; ResetFields clears it.
- `gem_settle`: two DataService caches on one mock store. Server A spends 1,000 gems on a forced Secret and its leave save lands
  8 s after server B's load: B refuses gem spins, the Secret Roulette and `GemBuy` with "Your data is still loading" until
  settled; after the settle B shows A's gem balance and Since 0, so B can neither force a second Secret nor spend the same gems;
  token spins are never held; with no store B counts as settled at 15 s; a failing settle read retries every 5 s.
- `gem_prices`: every number in 5.3 read from Config / TycoonCatalog / StoreCatalog (the products' `Robux` field copied by
  `gemItem`); `GemService.Quote` gives 4 / 15 / 60 / 250 / 1,000; a Mix with gems charges 50 / 125.
- `gem_potion_buy`: 75 gems -> +1,800 s potion bank, one toast, `Changed`; each refusal in 5.8 with nothing written (PassState
  "Owned" and "Checking" refused, "NotOwned" and "Unavailable" allowed; not settled refused); a restricted account may buy;
  "GemBuy" and "Buy" share the one 1 s gap.
- `match_finish_clean` (in `smoke_leaderboard.lua`): a root moved onto the Finish pad at t = 1 s does not finish; a team that has
  not reached the last checkpoint does not finish (and gets the toast); after the last checkpoint and `MinFinishSeconds` it
  finishes as today; no `RecordMatch` win and no `TokenBonusOnWin` without a finish; `Config.Leaderboard.Pages` has no "Wins"
  while any `MinFinishSeconds` is unmeasured.
- `lb_write`: no write before `SeedDelay`, none for a provisional or loading profile, none in Studio, at most one per stat per
  `WriteEvery`, a leave write, the budget floor, values clamped and floored.
- `lb_read`: the boot read of each stat, a few seconds apart; Scope "Server" with live values until the first good page; a
  100-entry mock store -> Top 10 with names, You.Rank for a player inside, nil outside; You.Value nil while provisional; a
  failing read keeps the last page and backs off 30 / 60 / 120 / 240; 2 failures in a row before the first good read -> "Server";
  names fall back to "Player"; `NextAt` / `UpdatedAt` are `GetServerTimeNow` times; the own-value poll sends only on change.
- `lb_fallback`: no OrderedDataStore -> Scope "Server", live sorted values, no writes, refresh 30 s.
- `lb_world`: the board at 295 degrees r 48 facing the centre, the face 16x13, tagged `prop_board_lb`, no "plaza decor skipped"
  warn, clear of paths, the roundabout, NPCs, benches and beds by the clearances in 5.10.
- `lobby_trove_plaza`: the trove at 43 degrees r 56 facing the centre, at most 60 parts, `JoinBillboard` text by `GroupId` ("Group
  rewards coming soon!" at 0), the sign post on the mirrored side, the prompt within 10 studs of `PromptPart`,
  `LobbyInfo.Shop.ItemShop` shape, the fallback trove at the same plaza spot (never a second one on the island), a profile stored
  with `Trove.Group = true` loads (and rebases) with `TroveGroupDone` set and the billboard hidden for that player only, the Egg
  Guide board and its seven tagged eggs at the old spot, no "plaza decor skipped" warn, lobby lights within the rule.
- `altar_portal_glow`: the Altar gate has its pad, its Pill and `VortexBoost` 1.4 (forwarded by `Gates.BuildOne`); `PortalGlow`
  exists beside an unchanged `Portal` (the LayoutSig manifest still tags); the beam; the return ring tagged `portal_ring` in
  green; every `ReturnPortal` part at least 4.5 studs off the bridge's centre line, outside the landing box and on the deck;
  every ring part CanCollide and CanTouch false; nothing collidable in the 4x6x4 box above the pad; the plinth top 0.05 under the
  octagons' top; `GetReturnPad` returns `ReturnPrompt`; one light on it (1.3 / 14, no `ReturnGlow`); the prompt E range 8; every
  new light within the lobby rule; the altar at most 500 parts.
- `mesh_keys`: every `Mesh.tag` key in `src` has a manifest in `src/shared/MeshManifests`, and every manifest this build adds is
  tagged somewhere (`gem_world_low` listed as reserved).

Client (`smoke_shop_ui.lua`: the `client_shop_*` cases; `smoke_egg_stage.lua`; `smoke_gem_icon.lua`; `smoke_lb_ui.lua`;
`smoke_lobby_fx.lua`):
- `client_shop_window` (1920x1080): five cards in order; each card's odds rows equal `PetCatalog.GetRarityOdds(id)`, and
  `ShopCard_Secret`'s rows equal `GemService.GetRarityOdds("Secret")` row for row (Mythic 85% / Secret 15%); every card has at least
  one odds row, and a card with none disables its buttons; prices from Config, x3 / gem / pity chip, the restricted state, the
  not-settled "Loading..." state, the Gems tab (four packs with the Config names, computed ribbons, BEST VALUE, "Coming soon" while
  Id 0, the buy sending `StoreRequest("Buy", "Gems" .. i)`, the potion and its refusal labels incl. "Checking your passes..."),
  the Store button opens the Robux Store and closes the shop, `WindowOpened("Shop")`, `OpenPanel` with `"Roulettes"` opens Eggs;
  `OpenPanel("Shop", { RouletteId = "Secret", Currency = "Gems" })` opens the Eggs tab with `ShopCard_Secret` fully on screen and
  outlined (also at 844x390), and `Currency` alone never switches tabs; `MenuController.Close()` and `InMatch` close the shop;
  `MenuController.IsOpen()` is true while the shop or the stage shows; the tutorial card folds while the shop is open.
- `client_shop_mobile` (844x390, 740x360, 667x375, 640x360): the window from `BigRect` (820x330 at 844x390), the sideways scroll,
  the fade, text >= 15 px, targets >= 44 px (strict: tabs 92x44, x3 / gem 44 tall), every phone odds egg >= 30 px, `Spin3` shows
  "x3" + token icon + the 3x price, every card fits the body, nothing under the top bar.
- `client_shop_sizes` (1280x720, 1366x768, 2560x1440): every card's odds, SPIN, x3 / gem row and hint inside the body; the Gems
  tab's potion reachable.
- `client_shop_portrait` (360x640, 390x844): the two header rows, the vertical card list, the 2x2 odds grid with 30 px eggs, text
  >= 15 px, targets >= 44 px, inside the screen.
- `client_egg_stage`: a result plays strip -> land -> crack -> pop -> reveal with the timings of 5.5 (normal and Fast hatch);
  Skip at t = 0 jumps to the reveal; Esc skips, then is DONE, and never also closes the shop; x3 three strips and three columns;
  flash only for Legendary+; the note's "1 of N" from `PoolSize` and "you have 2 <Pet> now"; a substitute's note; the
  `EvolvedRibbon` and evolved viewport for an evolved key (x1 and an x3 column); an old-shape result (no `Pulls`) plays as one
  pull and a pull with no `Strip` skips to the crack; SPIN AGAIN sends (id, currency, spins) through `EggStage.Request`; a card
  tap and SPIN AGAIN within 0.3 s send one request; a failure answer re-enables the cards at once with the reason; the queue; the
  timeout; a success after the timeout still plays; a match start closes the stage and toasts the unshown pulls; other windows
  (`openWindow`, Pets, Store, Index) refuse while the stage shows; mouse lock on: the cursor is free on the shop and the reveal;
  Fast hatch: a toggle sends `SettingsSet("FastHatch", true)` once, 0.4 s later, and the next roll uses the fast timings.
- `client_egg_stage_mobile` (844x390, 640x360, 667x375, 360x640, 390x844, plus 1280x720 and 1366x768 on PC): everything inside the
  screen and above the bottom edge (SPIN AGAIN / DONE, Skip, the 150x44 toggle), text >= 15 px on phones, targets >= 44 px, all
  three x3 pets visible.
- `client_gem_icon`: GemIcon builds at 16 / 20 / 24 / 32 / 96 px, the simple form under 28 px (no facet, outline >= 2 px whole);
  the shine at >= 20 px on High only; `Pile` counts; the HUD Gems coin on its navy badge with the cyan ring; after building every
  ScreenGui the `dump_gui` scenes build (HUD, Store, Shop, Daily, Arena, Dungeon, Pets, Index, Care, Train, PetPicker, Trove and,
  after the merge, Fusion's Upgrade and Mix tabs) no visible TextLabel / TextButton contains `"\226\151\134"`.
- `client_leaderboard`: the SurfaceGui in PlayerGui adorned to `Face`; "Loading scores..." before the first state; one tab per
  page; tabs switch; the page turns after 15 s and a tap restarts the count; the You row both ways and "..." while provisional;
  the Server scope line; the footer countdown from `GetServerTimeNow`; the empty page text; every board text >= 30 px
  (0.6 stud at 50 px per stud).
- `client_lobby_fx`: NC_Spin / NC_Bob move within 150 studs, stay still beyond it and on Low graphics.

Rewritten for the new rules (never deleted), each with its new expectation:
- `smoke_hud_items`: the shop prompt count no longer includes the trove on the shop island; count by name.
- `smoke_trove` `trove_build`: the plaza spot.
- `smoke_bug2_lobby` `bug2lobby_altarportal`: the standing green ring instead of 8 flush cyan segments, `RETURN_SIDE` 9 and the
  footprint checks of `altar_portal_glow`; the two arrival checks are rewritten for the pad: "3 studs over the ground" means over
  the pad top, and the 5x5x5 "nothing solid at the arrival" box sits above the pad top; the rest kept.
- `smoke_p5_world`: the Altar gate's pad in the pad checks; the new lights in the light rule.
- `smoke_p6_gates`: Altar `Pad = true`, `Pill`, `VortexBoost` in the spec table. `smoke_p6_portalfx`: the Altar's vortex reads
  brighter than the Obby's at the same distance (the swirl's built value does not change).
- `smoke_storm`: the part budget.
- `smoke_p2_gems`, `smoke_p2_flow`: the prices (the junk-currency cases keep "Unknown currency").
- `smoke_economy` (910-929): the announcement now reads "hatched", kind "pull", Legendary and up only, once per request; the
  puller's delayed copy stays.
- `smoke_p2_final`: README vs Config.
- `smoke_p2_ui` and `smoke_p2_visual`: `GemRoulette_Secret` / `GemRoulette_Cloud` -> `NimbusShop` `ShopCard_Secret` /
  `ShopCard_Cloud`.
- `smoke_release_client` (375-420 and on): `NimbusMenu.RouletteStage` -> `NimbusHatch`, `NimbusMenu.Window_Shop` -> `NimbusShop`,
  the Odds popup checks go (the odds are on the cards). `MenuController.IsPrewarmed` (the strip pet pre-warm) goes too: the strip
  draws eggs, not pets; EggStage warms only the pulled pets for the reveal viewport (`EggStage.IsPrewarmed(petId)`), and the test
  checks that instead.
- `smoke_client` (1180-1195): "every queued result dismissed with Esc" looks for `NimbusHatch` (else it would pass vacuously).
- `smoke_hud_pill` (227): `NimbusShop` instead of `Window_Shop`.
- `smoke_p5_gui` (274): the COVER scene `menu:Shop` reads `NimbusShop`. `smoke_p5_looks` (328-340): the old-shape result now plays
  through EggStage and the `EvolvedRibbon` is looked up in `NimbusHatch`.
- `smoke_server` (1777-1811, 1846): `NOTIFY_KINDS` gains `pull`; the `RouletteResult` validator checks every `Pulls[j]` (fields,
  `Strip` of 40 with `Strip[34] == Pulls[j].PetId`) and the mirrored top level.
- `smoke_dgfix_mouse` (the window list, about 250-300): rows `shop` and `hatch` with mouse lock on.
- `smoke_client_v2` (OpenPanel Shop Tab Roulettes -> Eggs), `smoke_store` (`Tabs[5] == "Eggs"`, token amounts),
  `smoke_store_ui` and `smoke_fixr_store_ui` (tap "Eggs"), `smoke_polish_worldtext` (the new workspace world texts' sizes; the
  board's PlayerGui SurfaceGui is checked by `smoke_lb_ui`), `smoke_p4_economy`, `smoke_content`, `smoke_audio` (the names in 5.5),
  `smoke_bug2_tutset` (the spin step still completes on `Rolled`), `smoke_daily_ui` (closes the shop through
  `MenuController.Close()`, which still works through the hooks).
- `tools/render_gui.py` `SCENARIOS` `menu:Shop` (line 66) becomes `shop`.
gui-redo also edits `smoke_p5_gui`, `smoke_p5_looks`, `smoke_daily_ui`, `smoke_p2_visual`, `dump_gui.lua` and `render_gui.py`:
these are edited only after the merge. Each new file is registered in `tools/smoke.py` (server scenarios before "shutdown", client
scenarios before "client_final", the mobile ones in `mobile_scenarios`).

Evidence for the review: `tools/dump_gui.lua` / `tools/render_gui.py` scenes `shop`, `shop:gems`, `shop:restricted`,
`hatch:strip`, `hatch:strip3`, `hatch:crack`, `hatch:reveal`, `hatch:reveal3`, `hatch:secret`, `store`, `store:Eggs`,
`store:Currency`, `gems` (GemIcon sizes and piles, the HUD gem coin, the 20 / 24 px chips), `eggs` (the seven GUI eggs and their
halves), `lobbyboard`, `lobbyboard:2`, `lobbyboard:3`, each at `--size 844x390` and `--size 1920x1080`, and `shop`, `hatch:reveal`,
`hatch:reveal3` also at 640x360, 1280x720, 360x640 and 390x844, with the geometry checks (text >= 14 px, targets >= 44 px, inside
the screen and under the inset, no overlaps). `tools/render_model.py` renders of `gem_world`, `portal_ring`, the seven
`egg_<rarity>` (made tonight), and `portal_altar_ring` and `prop_board_lb` once made, from several angles beside a 5-stud player.

Gate step: the whole `python tools/smoke.py --quick`, `--mesh`, `node tools/check.mjs` 0 errors (MenuController under 160 locals,
LobbyBuilder at most 159, DataService 160), `python tools/sim_tycoon.py --check` and `--gems`, `python tools/mesh_budget.py`,
`python tools/mesh_names.py --check` and the `mesh_keys` check.

## 10. Studio only (after the gate, by the main session)

- Play the lobby: the trove, the leaderboard and the altar gate seen from the spawn on PC and on a phone emulator; walk the
  lawn paths; the board's tabs tap; the Join billboard bobs.
- The Cloud Shop and a full roll on PC and phone, Fast hatch on and off, Skip, x3, a forced Secret (dev gems).
- The altar: the beam from the plaza, the summon ring turning, the return ring (walk past it from the landing; nothing blocks the
  lane), the lights against the night sky; the Altar gate's boosted vortex beside the Obby gate's, by eye, with the vortex on.
- Climb wins: one clean run per difficulty, timed; `Config.Match.MinFinishSeconds` = about 40% of the fastest, the runs logged in
  the ledger; only then is "Wins" added to `Config.Leaderboard.Pages`.
- OrderedDataStores need API access in Studio to read (no writes there by design); the live read is checked after publish only.

## 11. Left to the builder

- The exact frame build of the eggs, the machine art and the gem (inside the shapes and colours above and the pitch page).
- Ease curves, the rays' turn speed, the shake amplitude, the sparkle counts, the beam's width curve.
- How `addCopies` splits into its plan and write parts (5.1, step 3 and step 5), and where `GetPity` / `SetPity` / `GemsSettled`
  sit inside DataService's tables (no new column-0 local).
- The Blender art still to make in `lobby_shop.py` (`portal_altar_ring`, `prop_board_lb`), inside the shapes above, rendered and
  checked from several angles before the gate.
- The Part fallback segment counts (inside the altar budget) and the posts and roof of the board.
- Text that the spec does not quote (toasts for edge cases), in the game's plain voice.
- The order of work inside the plan; the plan splits server money (PetService, GemService, DataService, StoreService) from the
  windows and the world so they run side by side.

## 12. Skills used and skipped

Used: brainstorming (the written-design shape), roblox-security and roblox-datastores (section 7, the pity save, the
leaderboard writes), roblox-ui (BigRect windows, CanvasGroup clipping, the stage), roblox-performance (one Heartbeat driver,
culling, request budgets). Skipped: new-system (the systems exist; this changes them), luau-strict-typing (the codebase is
plain Lua 5.1 syntax), migration (no migration: new fields only).

## 13. Calls I made (for the owner to check)

1. x3 costs exactly 3 x the x1 price (no bulk discount); the x3 button is offered with tokens only, as in the mock (the server
   also accepts gems x3).
2. The Secret Roulette is x1 only (no x3 on its card; the server drops spins = 3 for it).
3. The pity lives in the profile (`Pity.Secret = { Spins, Hit }`, delta / max), counts only Secret Roulette spins, starts at 0
   for everyone (no credit for spins before this build), and refuses the Secret Roulette while the save is provisional.
4. Fast hatch is saved in the profile (`Settings.FastHatch`), so it follows the player across devices; default off.
5. The Cloud Shop gets its own `PC_MAX_W 0.87` (the mock's 1660 px window at 1080p) instead of the Store's 0.76.
6. The Cloud Shop keeps two tabs, Eggs and Gems; the Gems tab body reuses the pitch's approved Gems frame (hero, four packs with
   computed ribbons, the XP Potion), fitted to the B window; on a phone it is a sideways row of five tiles.
7. Value ribbons only in the Cloud Shop's Gems tab; the Robux Store gets gem piles and the new amounts but no ribbons (pitch B
   keeps it as approved).
8. Token roulettes stay open to PolicyService-restricted accounts as today, even though tokens can be bought with Robux; worth an
   owner look before release.
9. The trove at radius 56, not 55 (clearance), with its sign post mirrored so it does not hide behind the How to play board.
10. The leaderboard never writes from Studio; with no OrderedDataStore it shows "This server only".
11. "Put in team" leaves the reveal (the pitch shows SPIN AGAIN and DONE).
12. The Legendary+ chat line goes through `Notify` kind "pull" -> a system chat message (toast fallback), with today's timing
    (others at once, the puller after 5 s).
13. The gem XP Potion is refused when the player owns x2 Pet XP (it would add nothing) and when the 7-day potion bank is full
    (the Robux potion is never refused, since a paid receipt must be granted).
14. Egg names: Cloud Puff, Breeze, Raindrop, Thunder, Sunburst, Aurora, Starry Night.
15. The Altar gate's pad is decoration and a landing spot; "Travel" stays the only way in.
16. The phone stage sizes (x1 strip, crack and reveal) and the PC x3 layout are mine; the pitch drew the PC x1 stage and the
    phone x3 strips.
17. The world gem stands on the altar deck (spinning, lit 1.0 / 12); no gameplay gem drops.
18. Gemini was not asked again in this step: the creative calls were settled at the pitch (its tweaks taken and the one
    rejection are in section 4).
19. A pull that lands on a full stack is never refused: another pet of the same rarity is picked, or, with the whole rarity
    full, that rarity's Index tokens are paid (the Store's rule). The request is always charged.
20. Gem-priced actions wait about 15 s after a join for a settle read (the guard against a server-hop double spend that the pity
    would turn into two guaranteed Secrets). Token spins are never held.
21. The leaderboard ships with two pages (Trophies, Pets found) until the Climb finish is hardened and its minimum times are
    measured in Studio; then Climb wins is added back. The finish now needs the last checkpoint and a minimum time.
22. The Altar gate gets a brighter vortex (`VortexBoost`) instead of a brighter swirl, since the vortex covers the swirl on the
    whole plaza.
23. The return ring stands 9 studs to the side of the bridge line (not 5.5) and never collides; the flat pad stays the floor.

**Questions for the morning** (the owner's call; my recommendation first):
- A full session lock for saves (a claim on the record at load, released at leave), closing the server-hop double spend for every
  currency, not only the gem window the settle hold covers. Recommended: yes, as its own build after this one (saves, ultracode).
- Prestige gems (up to 135 an hour on runs 2-10) make a 1,000-gem Secret spin reachable in hours for a prestiging player, while a
  non-prestiging regular player needs about 17 days. Recommended: keep gemprice B (the pity caps the cost, prestige is long play)
  and look at the `--gems` report's two players before release.
- Token packs give 2-3 times fewer spins per Robux than gem packs (the 49 R$ token pack cannot buy a Celestial spin).
  Recommended: resize them to about 2,500 / 8,000 / 25,000 tokens so a token spin costs about the same Robux as a gem spin.
- The Climb finish change (a team must touch the last checkpoint, and a minimum time applies) so Climb wins can go on the global
  board. Recommended: yes.

## 14. Review notes

The adversarial spec review (2026-11-07) raised 61 findings, several of them twice (the x3 seeding three times, the Secret odds,
the `KNOWN_TOP` touch points, the Open args, the vortex, the Blender keys, the Trove attribute, the Fusion chip and the pity
attribute twice each). Every one was checked against the code and every one was real; all are fixed in the sections above. These
were taken in a different form than the finding proposed, or one of two conflicting proposals was turned down:
- Server hop / session lock (5.2): taken in the finding's minimum form (the gem settle hold: about 15 s plus one settle read
  before any gem-priced action), not the full session claim. The claim changes every load of the game (a load becomes an
  `UpdateAsync`, plus release rules for leave, BindToClose and kicks) and guards every currency, so it is its own save build:
  a morning question. The settle hold covers the pity's amplification in the common late-save cases and stays local to this build.
- x3 seeding: the findings that proposed one seed per request (`Util.NewRng(seed)`, strips from `seed + 7919 * j`, "pull 1 equals
  today's x1 roll for that seed") are superseded by the strip finding's engine-seeded `RollRng` / `StripRng`, which fixes the
  identical-pulls bug and also stops a strip from revealing the roll generator. No current test depends on the clock seed: the
  tests that steer rolls replace `PetCatalog.RollPet` / `GemService.RollPet`, which each pull still calls.
- Egg stage on other screens: not `UIScale = min(w / W0, h / H0)` over a fixed canvas. On a 640x360 phone that scale is 0.76,
  which would draw the 15 px phone text at 11 px, under the readability floor. The stage instead uses the windows' factor (never
  under 0.8 on PC, 1 on phones) and lays out from the top, the bottom edge and the free middle, shrinking only the pictures.
- Phone odds: one column per rarity with a 30 px egg over the 15 px %, instead of the proposed 2x2 grid (the 2x2 grid is used in
  portrait). At most four rarities share a 188 px card, 44 px each, so the 30 px egg fits; the point of the finding (eggs that read
  at 30 px) is kept.
- The x2 Pet XP pass while its ownership is still being checked: one finding said refuse, another said allow ("the potion only
  stacks time"). Refused ("Checking your passes..."): a pass owner who buys in the first seconds would pay 75 gems for nothing,
  and the wait is short.
- Board art: the suggestion to reuse an uploaded board was turned down. `prop_board_l` dresses only a 14x9 face (too small for ten
  rows at the 0.6-stud text floor) and `arena_board_leader` is a LayoutSig manifest that tags only while the arena's own build
  matches. The board gets its own Blender prop in `lobby_shop.py`.
- Altar gate swirl: of the two options (drop the swirl change, or brighten the drawn vortex) both are taken: the swirl change is
  dropped and the vortex gets a per-gate boost, since the owner's complaint was that the portal is hard to see.
- Pity write order: of the two options (plan before the charge with a setter that cannot refuse, or write first and roll back),
  the first is taken: nothing is rolled back after a charge.
- Climb wins: of the two options (harden the finish, or ship without the Wins page), both are taken in sequence: the finish is
  hardened now, and the Wins page appears only once its minimum times are measured in Studio, so the build never ships a farmable
  global stat.

## 15 Main-session decisions after review (2026-11-07 04:50, these override anything above)
- **Third leaderboard page = Ring best (`Ring.Best`), not Climb wins.** Ring.Best is set by the server from real Ring rounds, so it is safe to go global now. The Climb finish change (last checkpoint + minimum time) is NOT part of this build: it changes core Climb gameplay the owner did not ask for. It is a morning question for a later build. Pages: Trophies / Pets found / Ring best ("TOP RING ROUND"). No page waits on Studio timing.
- **Token packs resized** to 2,500 / 8,000 / 25,000 Cloud Tokens (49 / 149 / 399 R$), so Robux buys about as many spins in tokens as in gems (the 399 R$ pack = 5 Celestial spins vs 6 by gems). Names follow the amounts. The `--gems` report still prints Robux per spin for both.
- **Session lock** for saves: not in this build (morning question). The 15 s gem settle hold stays.
- Prestige gems: unchanged; gem prices B stay; the `--gems` report is the evidence.

## 16 Owner's pitch answers (2026-11-07, these override sections 4-15 where they differ)

The owner answered the pitch (https://claude.ai/artifact/1pvnd9iMLwbbDvjdR2hUju) and a follow-up Q&A on 2026-11-07. Their words
and choices are final. This section designs every change against the code as built (lobby-shop 1e733f7: Tasks 1-7 and 9-15
committed; Task 8, the gem prices B, stopped at its pre-flight and never landed, so Config, TycoonCatalog, StoreCatalog, the sim
and README still hold the pre-build prices). Where this section and sections 4-15 disagree, this section wins.

| Card | Owner's pick | Replaces | Built and now reworked |
|---|---|---|---|
| shop | **A**: one Shop window, left tab rail Eggs / Gems / Packs / Passes / Boosts, Secret Roulette hero, the Robux Store merged in and restyled; plus "add the shop gui back to the shop in the game (the one we closed)" = a walk-up prompt at the lobby shop | 5.4, 5.8 (B and the separate Store) | nothing built yet (B's Tasks 16-19 were not started) |
| eggs | A, plus "make the eggs look cool clean with vfx and make a cutscene for the egg opening ... clean and astonishing" | 5.5 (the stage becomes a cutscene, 16.4) | nothing built |
| egglook | **A** painted, plus "more coolness and details, make the eggs look cool with vfx" | 5.6 (sky-weather C) | the seven Blender eggs (spec commit 2762949, C paint): rebuilt with the same keys |
| gemlook | A | - | GemIcon (Task 15) kept as built |
| gemprice | **A with changes** (note + Q&A) | 5.3, 15 (token packs), the 5.2 cost line | Task 7's potion price (75 -> 100) |
| chest | **C**: west lawn between the two west benches by the Guide board, 165 deg, r 50 | 5.9 position | Task 10's spot (43 deg, r 56) |
| board | A (built) + titles | 5.10 gains 16.6 | - |
| portal | C (built) | - | - |

Non-goals of section 2 that the owner overrode: the Secret Roulette's odds change (Mythic 60 / Secret 40), the Celestial
Roulette's odds change (a 2% Secret, Epic 45 -> 43), and gem prices move in both directions. Everything else in section 2 holds
(no uploads, the server decides every roll, odds before paying, Skip from the first frame, no near-miss tricks).

### 16.1 Prices and odds

**The numbers** (owner's note: "the first roulette costs 3 gems its too cheap ... lower the secret roulette to 500 gems, make it
40% secret roll and 60% mythic roll"; Q&A: gem spins 20 / 40 / 60 / 180, "add a low chance for getting secret from celestial
(2%)"; the rest is the pitch's option A):

| What | Where | Built today | New |
|---|---|---|---|
| Gem spin Cloud / Storm / Sky / Celestial | `Config.Gems.RouletteGemPrices` | 5 / 20 / 75 / 300 | **20 / 40 / 60 / 180** |
| Secret Roulette price | `Config.Gems.SecretRoulette.GemPrice` | 1,500 | **500** |
| Secret Roulette odds | `Config.Gems.SecretRoulette.Odds` | Mythic 85 / Secret 15 | **Mythic 60 / Secret 40** |
| Secret pity | `SecretRoulette.PityAt` | 7 | 7 (kept; at 40% it fires after six dry spins, 0.6^6 = 4.7% of the time) |
| Celestial odds (token AND gem rolls) | `Config.Roulettes[4]` | Epic 45 / Legendary 40 / Mythic 15 | **Epic 43 / Legendary 40 / Mythic 15 / Secret 2**, `AllowSecret = true` |
| Cloud / Storm / Sky odds, every token price | `Config.Roulettes` | - | unchanged (the "machine levels") |
| Mix Mythic / Secret (gems) | `TycoonCatalog.Fusion.Mix` | 60 / 150 | **40 / 100** |
| XP Potion 30 min (gems) | `Config.Store.GemItems[1].Gems` | 75 | **100** |
| Gem packs Pouch / Bag / Chest / Vault | `Config.Gems.Products` | 100 / 550 / 1,200 / 6,500, no Robux field | **200 / 670 / 1,950 / 5,300**, new field `Robux = 49 / 149 / 399 / 999` (suggestions; `Id` stays 0) |
| Token packs Tokens1 / 2 / 3 | `Config.Store.Items` | 500 / 2,500 / 10,000 at 49 / 149 / 399 R$ | **1,500 / 7,500 / 30,000** (x3), names "1,500 Cloud Tokens" / "7,500 Cloud Tokens" / "30,000 Cloud Tokens", Robux kept |
| Free gem income, every token amount but the packs | everywhere | - | unchanged |

**Celestial's Secret and the guard.** Today a Secret pet rolled by a roulette without `AllowSecret` refuses the request before
the charge (`PetService` pull step, `ctx.AllowSecret`, "The roulette jammed, try again"). The guard already reads the roulette's
own flag: the token path takes `AllowSecret` from the `Config.Roulettes` row (`PetService` `roulette.AllowSecret == true`) and
the gem path from `GemService.Quote` (`def.AllowSecret`, copied from the same row by `GemService.GetRoulette`). PetCatalog's
`rarityAllowed` drops a Secret row unless the roulette sets `AllowSecret`. So the whole change is data: Celestial gets
`AllowSecret = true` and `Secret = 2`, and with no code change Celestial's Secret pulls are granted (token and gem, x1 and x3)
while Cloud, Storm and Sky still refuse a Secret before the charge. Consequences, each checked by a test:
- `PetCatalog.GetRarityOdds("Celestial")` gains a Secret row (Chance 0.02); `PossiblePets("Celestial")` lists the four
  rollable Secret pets; `PetCatalog.IsRollable(secretPetId)` becomes true for them (it loops `Config.Roulettes`), so the
  PetCatalog header and any test that pins "Secret pets are never rollable" are rewritten.
- A Celestial Secret pull does not touch the Secret Roulette's pity (`Pity.Secret` counts that roulette's spins only, 5.2);
  `Stats.Spins`, the strip (drawn from `StripRng` with the same odds, so a Secret egg shows in about 2% of Celestial cells), the
  substitute (when all four Secret pets are full: `Config.Index.Rewards.Secret.Tokens` capped at half Celestial's token price,
  2,500; review round 1, 16.9) and the Legendary-and-up chat line work as for any pull.
- The PolicyService lock on spins is unchanged: Celestial's gem spin is a gem-priced random item (locked for restricted accounts),
  its token spin stays open.
- **Tokens bought with Robux (review 2026-11-07, closing 13 call 8 now that a token spin can give a Secret).** Tokens bought with
  Robux would make token spins paid random items for an account that `ArePaidRandomItemsRestricted` covers. So the Robux products
  that grant Tokens (`Tokens1..3`, and the Pro Pack, whose `Grants.Tokens` is 5,000) are not sold to an account whose
  `GemService.PolicyState(player)` is not `"Allowed"`: `StoreService.PromptPurchase` refuses them before the prompt with "Token
  packs are not available on your account" (Restricted) or "Checking your account, try again in a moment" (still unknown; it
  kicks the policy check as `GemService.Quote` does). Earned tokens still spin for everyone. A paid receipt that still arrives
  (a prompt shown before the answer) is granted as always: a paid receipt is never refused. The Shop shows those cards locked
  with the same text (the Gems tab's `TokenPack_1..3`, the Packs tab's `Card_Pro`) while `PaidRandomItemsRestricted` is not
  `false`. Gem packs, passes, potions and the other packs are unchanged. (Review round 1, 16.9: this lock covers the server's
  prompt only. A client can open the purchase prompt itself with `MarketplaceService:PromptProductPurchase`, and that paid
  receipt is granted like any other, so a restricted account can still turn Robux into token spins. Closing it needs a rule at
  the spin, the owner's call in the 16.8 morning question.)
- Texts that say "Secret pets come only from the Storm Altar": `IndexController` (the undiscovered Secret pet's line becomes
  "A Secret pet. Summon it at the Storm Altar, or hatch it from the Celestial Roulette."), the PetCatalog / PetService / GemService
  headers, README (the gem section and the roulette table). `NpcDialog`'s Stormfang line stays true (it names the altar as one
  source) and is not changed.

**The Secret Roulette at 500.** Same code as built (5.1, 5.2); only Config moves. Gems per Secret pet with the pity:
`500 * (1 - 0.6^7) / 0.4` = **1,215** (2.43 spins on average; was 4,529 under B). Long-run Secret share with the pity:
`0.4 / (1 - 0.6^7)` = **41.15%** (natural pulls 40%). The phone chip, the reply's `SecretPity.Left`, the forced pull and the
settle hold are unchanged.

**The packs, honest and computed.** Gems per Robux 4.08 / 4.50 / 4.89 / 5.31, so the ribbons (computed from the prices shown,
never typed) read **"+10%" / "+20%" / "+30%"** (whole percent of the gain over the Pouch, rounded half up; no ribbon when the
gain is zero or less). "BEST VALUE" is computed too (review 2026-11-07): the pack with the most gems per Robux among the prices
shown, ties going to the bigger pack (`ShopGems.BestValue`), today the Vault; with the Vault at 1,999 R$ (2.65 gems per R$) it
moves to the Chest (4.89) and the Vault shows neither a ribbon nor BEST VALUE. A live `PriceInRobux` that differs from Config
moves it the same way. The Gems hero's line is computed too: `n = floor(Chest / SecretPrice)`, `m = floor((Chest - n * SecretPrice) /
CelestialGemPrice)` -> **"Chest: 1,950 gems buys 3 Secret spins + 2 Celestial spins"** (the B line "1,500 = 1 Secret + 2
Celestial" is gone). Token packs get the computed "BEST VALUE" (most tokens per Robux among the prices shown: today the 30,000
pack) and no % ribbon (my call: their gain over the first pack,
+64% / +146%, would dwarf the gem ribbons and read as a trick).

**Files.** `Config.lua` (the table above; the Celestial row's comment: "AllowSecret: a 2% Secret egg, token and gem rolls";
`Gems.Products` gains `Robux`; the `Store.Tabs` change is 16.3's); `TycoonCatalog.lua` (`Fusion.Mix`); `StoreCatalog.lua`
(`gemItem` copies `Robux`, header); headers of `PetCatalog`, `PetService`, `GemService`; `IndexController` (one string);
`README.md` (the gem section, the product table, the roulette table: `smoke_p2_final` compares them with Config);
`StoreService.lua` (`PromptPurchase`: the token-grant lock above, reading `GemService.PolicyState`; at most one new top-level
local); no `PetService` / `GemService` code change. `tools/sim_tycoon.py`: the saved Task 8 Step 1 work
(`.superpowers/lobby-shop/evidence/task8/sim_tycoon_gems_step1.patch`, applies cleanly to this tree: checked 2026-11-07) with the
new numbers: `GEM_SPIN = [20, 40, 60, 180]`, `GEM_SECRET = 500`, `SECRET_PITY = 7`, `GEM_MIX = [40, 100]`, `GEM_POTION = 100`,
`GEM_PACKS = [200, 670, 1950, 5300]`, `PACK_ROBUX = [49, 149, 399, 999]`, `TOKEN_PACKS = [1500, 7500, 30000]`; the odds
columns `ODDS_Cloud .. ODDS_Celestial` and `PET_ROLLABLE` grow from 6 to 7 entries (Common .. Secret; `ODDS_Celestial = [0, 0,
0, 43, 40, 15, 2]`, `PET_ROLLABLE = [6, 6, 5, 3, 4, 2, 4]`), and so does `PET_ECON_ROLLABLE` (`roll()` reads it at the same
index: **`[3, 3, 3, 1, 2, 1, 1]`**, Phantom Kitsune being the one Economy pet among the four rollable Secret pets; left at 6 the
first Celestial Secret in the sim raises IndexError), the sim's roll uses all seven and `--check` compares all seven with
Config. `smoke_p4_economy.lua` `p2_economy` builds its expected rollable / Economy counts and its `ODDS_<roulette>` rows with
three `for i = 1, 6` loops: they become `for i = 1, #RARITY_ORDER` (7), or the 7-entry sim lists fail `listEq` (review
2026-11-07). The `--gems` checks become: gems per Secret pet = `GEM_SECRET * (1 - (1 - p)^PITY) / p` with `p` from Config (1,215 +-1);
pack gems per Robux strictly rising; the Chest line's spins (3 Secret + 2 Celestial) equal the hero's computed numbers;
`PACK_ROBUX` equals the Config `Robux` fields. The days-per-Secret-spin check (12-25 days) is **removed** (the owner's numbers are
final): the report prints it and the build never stops on it.

**Expected `--gems` numbers** (the saved report's income model: casual 8.3 gems a day, regular 27.4 a day, both never
prestiging; a prestiging regular 101 gems an hour; the build re-runs and pastes the real ones into the ledger):

| | Cloud 20 | Storm 40 | Sky 60 | Celestial 180 | Secret 500 | Potion 100 |
|---|---|---|---|---|---|---|
| regular, days | 0.7 | 1.5 | 2.2 | 6.6 | **18.2** (first one on day 12.6 with the 156 one-time dungeon gems) | 3.6 |
| casual, days | 2.4 | 4.8 | 7.2 | 21.7 | **60.2** (first on day 41.4) | 12.0 |
| prestiging, hours of play | 0.2 | 0.4 | 0.6 | 1.8 | **5.0** (every 3.3 days at 90 min a day) | 1.0 |

Robux per spin at the 49 / 149 / 399 / 999 R$ packs: Cloud gems 4.90 / 4.45 / 4.09 / 3.77 vs Tokens 1.63 / 0.99 / 0.67; Storm
9.80 / 8.90 / 8.18 / 7.54 vs 8.17 / 4.97 / 3.33; Sky 14.70 / 13.34 / 12.28 / 11.31 vs 32.67 / 19.87 / 13.30; Celestial 44.10 /
40.03 / 36.83 / 33.93 vs 163.3 / 99.3 / 66.5; Secret 122.5 / 111.2 / 102.3 / 94.2 (gems only). A Secret pet costs about 1,215
gems at the altar against about 9,000 gems (or 250,000 tokens) at Celestial's 2%, so the altar stays the gem path and Celestial
is the token player's long shot. Reported, not changed: tokens now buy Cloud and Storm spins for fewer Robux than gems do.

**Tests** (built ones rewritten under their names; nothing deleted): `gem_prices` (new, `smoke_gem_prices.lua`: every number
above read from Config / TycoonCatalog / StoreCatalog, `GemService.Quote` 20 / 40 / 60 / 180 / 500, Mix 40 / 100, the potion
100); `celestial_secret` (new, `smoke_eggs.lua`: Celestial's Secret pull granted for tokens and gems, x1 and x3, never refused;
Cloud / Storm / Sky still refuse; the pity untouched; 20,000 seeded `RollPet("Celestial")` give Secret 2% +-0.3 points);
`store_token_lock` (new, `smoke_store.lua`: with `Id > 0` set on the items in the test, a Restricted account's `StoreRequest("Buy",
...)` for `Tokens1..3` and `Pro` is refused before any prompt with its text, an unknown account gets the Checking text, an Allowed
account is prompted; gem packs, passes, potions and `Starter` are unaffected; a paid `Tokens1` receipt for a Restricted account is
still granted); rewritten:
`egg_roll_pure` (Secret Roulette rows 0.60 / 0.40, Celestial with its Secret row), `egg_full_stack` (natural Secret share 40% +-3,
all pulls 41.2% +-3), `secret_pity` (the forced-strip filler share 40% +-3; every steering stub re-checked against 60 / 40),
`gem_settle` part 3 (the price read from Config), `gem_potion_buy` (100 gems; the "one gem short" case at 99),
`p2gems_roulettes` (a token roulette's `AllowSecret` equals its Config row; the guard test stays on Cloud),
`p2gems_odds` (the leak test: no Secret from Cloud / Storm / Sky over 1,500 rolls x 2 roll functions; Celestial inside 0.9-3.1%),
`store_catalog` / `store_config` (token amounts and names, the gem items' `Robux`), `p2_economy` (the sim names, its loops over
all seven rarities),
`p2final_docs` (README), `catalog` / `config_shape` (any pin of "no Secret in token roulettes" or `IsRollable` false for Secret
pets), the `p2flow_*` price lines.

### 16.2 The Sky Trove at spot C

`LobbyBuilder`'s `G.Trove = { Angle = 43, R = 56, Clear = 6.5 }` becomes **`{ Angle = 165, R = 50, Clear = 6.5 }`** (plaza-local
x -48.30, z 12.94), still placed once per Build by `plazaSpot` before `buildPlaza` (so its reservation comes first) and faced to
the plaza centre with `faceCentre` (front toward the spawn court). Checked against the code's own placements (no adjustment
needed; the spot is the owner's exactly):

| Neighbour (code) | Where | Distance | plazaSpot needs |
|---|---|---|---|
| Guide board (`buildBoards`, `L.MidAngle + 58`) | 148 deg r 48 | 14.62 | 12.5 |
| Bench (`benchTpl` list) | 130 deg r 44 / 200 deg r 44 | 28.84 / 28.84 (it stands exactly between the two west benches) | 10 |
| NPC spot (`npcPlan`) | 160 deg r 70 | 20.66 | 11.5 |
| Flower beds | 150 / 190 deg r 81 | 35.2 / 41.5 | 10.5 |
| West walk (`L.CrossAngles`, 180 deg, half 5) | centre line | 12.94 | 11.5 |
| Spawn court (`G.CourtR` 34, reserved 36) | origin | 50 | 42.5 |
| Trees, lamps, the How to play board, gate sight lines (gates span 53.75 .. 126.25 deg) | - | > 28 | - |

The chest body's nearest corner is 2.8 studs off the west walk. The sign post stays at local x -6.2 (the walk side: open lawn; at
+6.2 it would stand 2.8 studs past the Guide board's edge, in its frame): its footing ends 1.0 stud off the walk's border. The
Join sign (`JoinAnchor` / `JoinBillboard`, `NC_Bob`, hidden for `TroveGroupDone`), the prompt, the `fallbackShop` trove (built at
the same `L.TroveCF`) and `LobbyInfo.Shop.ItemShop` are unchanged. The Egg Guide stays on the shop island. From the spawn (looking
along +Z) the chest is about 75 degrees to the right, beside the Guide board; a player turning toward the gates' right side sees
it. Tests: `lobby_trove_plaza` and `trove_build` rewritten to 165 deg r 50 (+-0.5), no "plaza decor skipped" warn, the sign post
footing >= 0.5 stud off every path cell, every neighbour distance above; the render `t17_trove_west.png` beside the Guide board
and the two benches.

### 16.3 The Shop (A): one window

**Who owns it.** `src/client/Controllers/StoreController.lua` is moved with `git mv` to
**`src/client/Controllers/ShopController.lua`** and becomes the one Shop window (it already has the left tab column, the BigRect
window, the portrait layout, the Esc / gamepad B binding, the product price reader and the pack cards). A new thin
**`StoreController.lua`** (about 40 lines, no window of its own) stays for old callers and tests: `Init` (nothing),
`Open(args)` -> `ShopController.Open(args)` (its tab mapped below), `Close`, `IsOpen`, `Layout` ("Compact" reads "PC", "Portrait"
reads "Phone"), `Portrait`, `Cards`, `Palette`, `RobuxGlyph`, all delegated. The Eggs and Gems pages are new modules so the
window file stays under its local cap: **`src/client/UI/ShopEggs.lua`** (`Build(page, ctx)`, `Layout(page, box, mode)`,
`Refresh(page)`, `Focus(rouletteId)`, `CardState(rouletteId)`) and **`src/client/UI/ShopGems.lua`** (`Build`, `Layout`,
`Refresh`, `PackRibbons(packs)`, `BestValue(packs) -> index | nil`, `ChestLine()`, `PotionState()`). Packs, Passes and Boosts keep the Store's card code as it is,
inside ShopController. The B design's separate `ShopController` / Cloud Shop window (5.4) is not built.

**Tabs and items.** `Config.Store.Tabs = { "Eggs", "Gems", "Packs", "Passes", "Boosts" }` (was Packs, Passes, Boosts, Currency,
Roulettes). The Currency tab folds into Gems: `Tokens1..3` and the disabled `Cash1..3` move to `Tab = "Gems"`; StoreCatalog's gem
products answer `Tab = "Gems"`; `GEM_HERO_INDEX` 2 -> 3 (the Chest is the Gems hero, as the A mock); `Validate`'s "the Currency
Cash packs carry Line" reads "the Cash packs". `ShopController.NormalizeTab(tab)`: `"egg*"`, `"roul*"`, `"Roulette"`,
`"Roulettes"`, `"Items"`, `"Shop"` -> Eggs; `"gem*"`, `"Currency"`, `"Tokens"` -> Gems; Packs / Passes / Boosts as they are
(any case); anything else -> nil (then the last tab of this session, first time Eggs).

**Window** (the A mock `shopA(m, tab)`; design px). ScreenGui **`NimbusShop`** (DisplayOrder 19, `IgnoreGuiInset = true`,
`ResetOnSpawn = false`) > **`ShopWindow`** (UIScale `Fit`), `NeonKit.BigRect` with `RECT = { H0 = 390, W0 = 820, Y0 = 330,
H1 = 1080, W1 = 1540, Y1 = 910 }`, `MARGIN 12`, `PHONE_W 900`, `SHORT 560`, `PC_MIN_H 600`, `PC_MAX_W 0.81`.
- `Header` (PC 76 / phone 50): `Icon` (egg glyph, PC 42 / phone 28) + `Title` "Shop" (PC 34 px, 200 wide / phone 20 px, 130
  wide), `Balance_Gems` (`GemIcon.Amount`; PC 140 wide 22 px / phone 96 wide 15 px), `Balance_Tokens` (token icon + number;
  PC 190 / phone 128), `CloseButton` (red X, PC 56 / phone 44). Balances use `Theme.ShortNumber` from 1e6. The header gradient
  is the A accent rgb(90,168,232). The Store's Cash pill goes (no Cash item is on sale).
- `Rail` (PC 224 wide at x 18; "Compact" 112 wide; phone 104 wide at x 8): `Tab_Eggs` (egg glyph `NeonKit.Glyphs.Eggs =
  "\240\159\165\154"`), `Tab_Gems` (a GemIcon), `RobuxDivider` (PC: Robux glyph 24 + "Robux items" 18 px, 224 x 40; phone and
  Compact: a 2 px divider line), `Tab_Packs`, `Tab_Passes`, `Tab_Boosts` (their Store glyphs). PC tab 224 x 80 (icon 40 +
  label 26 px) at y `16 + i * 92` (+44 from Packs on); Compact 112 x 80 (icon 32 over label 18 px); phone 104 x 48 (icon 24 +
  label 15 px) at y `6 + i * 54` (5 tabs end at 270 of the 280 body at 844x390); with a body under 276 px (667x375: 265;
  740x360 and 640x360: 250) the phone tabs are 104 x 44 at y `4 + i * 49` (they end at 244; review 2026-11-07: the 54 px
  step ran `Tab_Boosts` past the window and, at 640x360, off the screen). Selected: the bright fill and a gold stroke (attribute
  `Selected`). `Tab_Packs` shows a small gold `Dot` while the Starter Pack is on sale (created, or `StorePreview`) and not
  bought (`StoreBought` lacks it). PC rail bottom (Eggs tab only): `FastHatch` toggle 224 x 52 ("Fast hatch" 20 px,
  `ClientSettings` `FastHatch`).
- `Body` > `Page_Eggs`, `Page_Gems`, `Page_Packs`, `Page_Passes`, `Page_Boosts` (one shown). Content box: PC x 262, width 1240
  (window 1540); Compact x 128; phone x 120, width = window - 128; portrait below.

| Screen | Window | Mode | Notes |
|---|---|---|---|
| 1920x1080 | 1540x910 | PC 1 | rail 224, content 1240; body 834: the reference layout (it ends at 826) |
| 2560x1440 | 1540x910 at 1.25 | PC | |
| 1366x768 | 1383x810 design (0.8) | Compact | content 1231; body 734: hero 200 + cards 516 (fit rule), still short (752), so the page scrolls vertically |
| 1280x720 | 1296x759 design (0.8) | Compact | content 1144, cards 274 wide; body 683: shrunk and scrolls vertically |
| 844x390 | 820x330 | Phone | body 280; tabs 48 tall; cards 266 tall |
| 667x375 | 643x315 | Phone | body 265; tabs 44 tall; cards 253 tall |
| 740x360 / 640x360 | 716x300 / 616x300 | Phone | body 250; tabs 44 tall; cards 238 tall (art shrinks first) |
| 360x640 / 390x844 | 336x536 / 366x705 | Portrait | two header rows, the rail as a row |

(Review 2026-11-07: the 1366x768 and 1280x720 rows were recomputed from `NeonKit.BigRect` with this RECT, inset 58: 910 and 876
were wrong.) Fit rules: PC/Compact with a body under 826 px (the reference layout's bottom: cards at y 276 + 550; the 842 first
written here would have shrunk the 834 px body at 1920x1080): the Secret hero shrinks to 200 tall (machine art 160) and the
cards' machine art 130 -> 100 (card 550 -> 516); still short: the page scrolls vertically and every card is reachable by
scrolling. Phone: every card and tile of the sideways rows (Eggs and Gems) is `min(266, body - 12)` tall. Compact when the PC design width is under 1,400. Four
machine cards share the content width (`(contentW - 48) / 4`); under 250 px the card row scrolls sideways. Phone: the card row
always scrolls sideways (a 48 px right fade while more is to the right). Portrait: header row 1 (icon, "Shop", X) and row 2 (both
balances), the rail as one row of five 64 x 56 tabs (icon 22 over label 15 px), the body a vertical list.

**Eggs tab** (`Page_Eggs`, ShopEggs; the A mock's Eggs frame; every PC text >= 18 px, every phone text >= 15 px):
- `ShopCard_Secret` (attribute `Hero = true`), PC 1240 x 240 at (0, 16), framed rgb(138,92,255): `Machine` (the Secret dome art,
  190 x 218, its eggs Mythic and Secret), `Title` "Secret Roulette" 46 px, `OddsLine` with `Odds_Mythic` and `Odds_Secret` (each an
  `Egg` 40 px + `Pct` 24 px; values from `PetCatalog.GetRarityOdds("Secret")`, never typed) + "gems only" 24 px, `PityChip`
  400 x 48 rgb(59,42,138) "Secret for sure in N more spins" (N = `SecretPityLeft`; N = 1 "Secret for sure on the next spin";
  "Loading..." without `GemsSettled` / the attribute), `Spin` 290 x 100 ("SPIN" + GemIcon 44 + "500", 34 px; a gentle pulse,
  UIScale 1 -> 1.04 every 2.5 s, High graphics only), `Hint` 18 px "Also at the Storm Altar". Phone: the first card of the
  sideways row, 200 x 266 (name "Secret" 17 px, art 64, two odds columns of egg 30 + % 15, `Spin` 44 tall 16 px, `PityChip`
  "Secret in N" 44 tall). Portrait: full width x 200 on top.
- `Cards` (ScrollingFrame) > `ShopCard_Cloud`, `ShopCard_Storm`, `ShopCard_Sky`, `ShopCard_Celestial`, PC 298 x 550 at
  (i * 314, 276) (the mock's `machCard` with `{ art = 130, rh = 40, sb = 64, sm = 48 }`): `NamePlate` 54 tall 24 px, `Machine`
  130 x 150 at y 76 (the dome with seven eggs of that machine's mix), `Odds` > `Odds_<Rarity>` rows 40 tall from y 234 (`Egg`
  28 px, `Word` 20 px in the rarity colour, `Pct` 22 px right; Celestial now has four rows, the fourth Secret 2%), `Spin` 64 tall
  at y 400 ("SPIN" + token icon + price, 23 px), `Spin3` and `SpinGems` 48 tall at y 476 (half width: "x3" + token icon + 3x price
  18 px; GemIcon + gem price 18 px), `Hint` 18 px at y 526 "Gems: same odds", `NoOdds` "Odds unavailable" (buttons inactive) when
  `GetRarityOdds` is empty. Phone 166 x 266 at `x = 208 + i * 174` after the Secret card: name plate 6..36 (17 px, no "Roulette"),
  art 40..92, one odds column per rarity (at most four, egg 30 px over % 15 px), `Spin` 150..194 (44 tall, 16 px), `Spin3` /
  `SpinGems` 200..244 (44 tall; `Spin3` reads "x3" + token icon + `Theme.ShortNumber(3 * price)`, so a tap that charges three
  times always shows the total). Portrait: full-width cards 250 tall (art 64 left, the odds as a 2 x 2 grid of egg 30 + % 15).
- Buttons call `EggStage.Request`: `Spin` -> `(id, "Tokens", 1)` (Secret `("Secret", "Gems", 1)`), `Spin3` -> `(id, "Tokens", 3)`,
  `SpinGems` -> `(id, "Gems", 1)`. Card states exactly as 5.4 "States on a card" (Short: price kept, amount red, today's "not
  enough" toast; Locked: the gem button and the whole Secret card show the PolicyService lock with today's text; Loading: no
  `GemsSettled`; Pending: `EggStage.IsPending()` dims every spin button; NoOdds). The Secret card stays x1 only (13 call 2).
- `ShopController.Open({ RouletteId = id })` opens Eggs, scrolls that card fully into view (centred when the row scrolls) and
  outlines it gold for 2.6 s (the machine prompts and the altar's Summon); `Currency` alone never switches tabs.

**Gems tab** (`Page_Gems`, ShopGems; the A mock's Gems frame; vertical scroll on PC, sideways on phone):
- `GemHero` 1240 x 240 at (0, 16): `Pile` (6 gems, 200 px), `Title` "Gems" 46 px, `Line1` "Spin the Secret Roulette and every
  machine with gems." 24 px, `Line2` = `ShopGems.ChestLine()` 24 px rgb(255,243,176), `Buy` 290 x 100 = the Chest pack's buy.
- `GemPack_1..4` 298 x 380 at (i * 314, 276): `Pile` 1 / 2 / 4 / 6 gems (140 px), `Amount` 44 px ("200" ... "5,300"), `Name` 21 px
  (the Config name as it is), `Ribbon` ("+10%" / "+20%" / "+30%", `PackRibbons`), `Best` "BEST VALUE" (on the pack
  `BestValue` names: today pack 4), `Buy` 68 tall:
  `Id > 0` -> the live `PriceInRobux` and one `StoreRequest("Buy", "Gems" .. i)` per tap (the server prompts, never the client);
  `Id == 0` -> the Config `Robux` on an inactive "Coming soon" button ("PREVIEW" under `StorePreview`).
- `GemPotion` 1240 x 130 at (0, 676): `Icon` 96, `Title` "XP Potion \194\183 30 minutes" 32 px, `Text` "Your team earns double pet XP.
  Not random, so every account can buy it." 22 px, `Buy` 270 x 78 GemIcon + "100"; `PotionState()` labels as 5.4 (Owned "You have
  x2 Pet XP", Checking "Checking your passes...", Full "Potion time is full", Loading "Loading...", Short: the amount red); only
  "Ready" sends `StoreRequest("GemBuy", "XpPotionGems")`.
- `TokensTitle` "Cloud Tokens" 26 px at y 826 and `TokenPack_1..3` 408 x 220 at (i * 416, 870): `Art` (token icons 1 / 3 / 6),
  `Amount` 40 px, `Name` 20 px (Config), `Best` (computed the same way: today pack 3), `Buy` 64 tall (same Id / preview rules,
  `StoreRequest("Buy", "Tokens" .. i)`); while `PaidRandomItemsRestricted` is not `false` the three token packs show the lock
  of 16.1 ("Token packs are not available on your account", or "Checking your account..." while unknown) on an inactive `Buy`
  and send nothing (the Packs tab's `Card_Pro` the same).
- Phone: one sideways row of 166 x 266 tiles: the four gem packs, the potion ("XP Potion" 17 px, "30 min \194\183 x2 pet XP" 15 px),
  the three token packs; the hero is not drawn on a phone (its Chest is pack 3). Portrait: the vertical list (hero on top).

**Packs, Passes, Boosts.** The Store's pages, cards and rules move over unchanged in content and naming (`Page_<tab>`,
`Card_<key>` with `Paint`, `Art`, `Name`, `GetsYou`, `Line1..n`, `Status`, `PricePill`, `Buy`; the palettes, hero choice, card
states, price reader, shine, sounds, `StoreRequest("Buy", key)` with its 1 s gap). Restyled into the Shop: they sit in the Shop's
content box (x 262, width 1240 on PC; the hero 1240 x 250, cards 1240 x 150 rows, gap 12), under the Shop's header and rail, with
the A card frame (3 px navy outline, 14 px corners). Nothing a test reads inside a card changes name.

**Hooks and every opener.**
- `MenuController`: `P5.openStore(args)` -> `ShopController.Open(args)`; `onOpenPanel` `"shop"` -> `ShopController.Open(args)`
  (the whole args table) and `"store"` -> the same; the old Cloud Shop window, the odds popup, the roulette stage and the client
  odds copy are removed (the B plan's Task 17 removal list, which still matches the code: `secretRoulette`, `findRoulette`,
  `possiblePetsOf` if only the shop used them, `gemsOnlyBuckets`, `oddsOf`, `P2.gemAmount`, `openOdds` / `closeOdds` / `Odds` /
  `K.Odds`, `buildRouletteCard`, `buildShop` and its Gems page, `focusCard`, `beginStage` / `closeStage` / `skipSpin` /
  `requestSpin` / `onRouletteResult` / `Spin` and its `connectRemotes` hook, `Warm.Roulette`, `MenuController.IsPrewarmed`,
  `K.Shop`, `createWindow({ Id = "Shop", ... })`); added `P5.shop()` / `P5.hatch()` (lazy requires), `P5.openShop(args)`,
  `P5.closeShop()`, `P5.shopOpen()`, `P5.hatchShowing()`, `P5.closeHatch()`; `closeEverything` closes both, the Shop first, then
  the stage (16.4 "Never breaks the player"); `openWindow`,
  `P5.openPets`, the Index open refuse while `P5.hatchShowing()`; `MenuController.IsOpen()` ORs in the Shop and the stage;
  `handleBack` loses its stage / odds branches; its own windows close on `WindowOpened("Shop")` (the list `Pets` / `Store` /
  `Daily` / `Trove` gains `Shop`). MenuController drops under 160 locals.
- `WindowOpened`: the Shop fires `"Shop"` on every open (the tutorial's `ShopOpened` listens). While MenuController still owns
  the old Cloud Shop (the step between the Store merge and the Eggs tab, plan Task 21), the merged window fires `"Store"` as the
  Store does today, its first tab is Packs and its Eggs tab hops to `MenuController.Open("Shop", { Tab = "Roulettes" })`; the
  Eggs tab task (plan Task 22) switches it to `"Shop"`, the real page and Eggs as the first tab.
- Touch, column and cursor: `MenuController.SetTouchHidden("Shop", on)` and `SetColumnCovered(windowLeft, "Shop")` (were
  `"Store"`); `MouseLock.WatchVisible("Shop", ShopWindow)` frees the cursor while the window shows; `MouseLock`'s `WATCHERS`
  replaces the `NimbusMenu` stage / odds entry with `NimbusHatch = watchOverlays({ "Stage" })`.
- Esc / gamepad B: the Store's own binding moves over as `K.BACK_ACTION = "NimbusShopBack"` (`High.Value`, bound only while open,
  always `Sink`); B does nothing for the Shop while `EggStage.IsShowing()` (the stage's `"NimbusHatchBack"` sits at
  `High.Value + 1`, so ContextActionService gives it the press). **Esc has one owner** (review 2026-11-07: two
  `UserInputService.InputBegan` handlers run in no guaranteed order, so on the reveal the stage could close, show the Shop
  again, and the Shop's handler then close the Shop too): ShopController's one Esc handler (connected once in `Init`) calls
  `EggStage.Back()` while `EggStage.IsShowing()` (skip before the reveal, DONE on it; whether the Shop is open or not) and
  stops there; otherwise it closes the Shop when open. EggStage keeps no `UserInputService` Esc handler of its own (the stage
  first, as `MenuController.handleBack` does today).
- Openers: the top bar's `PillButton_Shop` (`StoreController.Open()` -> the Shop on the last tab of this session, first time
  Eggs; a second tap closes it); `PetsController`'s `OpenShop` button (`menu.Open("Shop", {})` -> Eggs); the four machine prompts
  (`OpenPanel("Shop", { Tab = "Roulette", RouletteId })` -> Eggs with that card focused); the altar's Summon (`OpenPanel("Shop",
  { RouletteId = "Secret", Currency = "Gems" })` -> Eggs with `ShopCard_Secret` focused); the new walk-up prompt (below); a
  server `OpenPanel("Store", args)` -> the Shop on the mapped tab. Daily, Trove and the HUD open nothing in the Store today (checked:
  no caller); they keep closing on any other `WindowOpened` id.
- Tutorial: `TutorialController` is unchanged. The "shop" step keeps its world arrow (the roulette machines, `Target.Kind =
  "Shop"`) and completes on `WindowOpened("Shop")` through `WINDOW_EVENTS`, whichever opener was used (the top bar's
  `PillButton_Shop` included). Review 2026-11-07: the first draft gave `HOOK_FOR` a `ShopOpened = "Shop"` entry so the pill
  would glow, but `HOOK_FOR` only picks the click hook, `findMenuButton` searches only `MenuButton_<id>` / `Menu_<id>`, and the
  ring and arrow show only for a `Menu` target, which would replace the world arrow (a step has one target). So no button map
  and no glowing pill in this build.

**The walk-up prompt** ("the one we closed"). History: the shop island's item stall had a `ProximityPrompt` "Open" / "Item Shop"
(`ItemService`, `ItemShopPrompt`, `MaxActivationDistance 12`, on the stall's `PromptPart` at `cf * CFrame.new(0, 2, -4.6)`)
until a165c65 boarded the stall up ("Closed", no prompt); 1610c40 put the Sky Trove in its place at `at(-21, -8)` and Task 10 the
Egg Guide (board, shelf, seven eggs). The prompt comes back at that same spot, now opening the Shop:
- `LobbyBoardBuilder.EggGuide` adds an invisible, non-colliding `PromptPart` (5 x 4 x 3) at `cf * CFrame.new(0, 2, -5.6)` (just in
  front of the shelf) and returns it; `buildShop` returns `Shop.Counter = { PromptPart, Center, Model }` (the Egg Guide model);
  `fallbackShop` gives its own `Counter` PromptPart beside the fallback machines. `LobbyInfo.Shop.Roulettes` and `.ItemShop`
  keep their shapes.
- `PetService.buildPrompts` (it already owns the shop's prompts) adds `ShopPrompt`: `ActionText "Open"`, `ObjectText "Shop"`,
  `HoldDuration 0`, `MaxActivationDistance 10`, `RequiresLineOfSight false` on `Shop.Counter.PromptPart`; on Triggered: a live
  player, not `InMatch`, `rateLimited(player, "Prompt_Shop", PROMPT_COOLDOWN)`, then `OpenPanel("Shop", { Tab = "Eggs" })`.
  Rebuilt with the machine prompts; a missing part warns once. No new top-level local (PetService stays 80).
- The machines' prompts stay "Open" / "<machine name>" (range 12). Roblox's default `Exclusivity` (`OnePerButton`) shows only the
  nearest E prompt, so the Celestial machine beside the Egg Guide never doubles up.
- The arch sign's caption "pets & items" (there are no items) becomes "eggs & gems".
- I did not rebuild the stall: its uploaded mesh (`prop_item_stall`) paints heal / shield / feather goods that left the game, and
  the Egg Guide (the eggs on display, the board naming them) is the honest counter for an egg shop.

### 16.4 The egg-opening cutscene

**GUI, not the world camera.** The cutscene is a full-screen ScreenGui (`NimbusHatch`, DisplayOrder 25, `IgnoreGuiInset =
true`, `ResetOnSpawn = false`). The eggs are painted GUI eggs (16.5), the pet is `CloudUI.PetViewport` (as today), the effects are
GUI frames, tweens and a pooled GUI spark system, plus a client-only `BlurEffect` (`Lighting.NimbusHatchBlur`) and a cool tint
pushed through `LightingStack` (preset `"Hatch"`, its `ColorCorrection` group; no ColorCorrectionEffect of our own) that dim the
world behind.
Why: (1) the player can open the Shop anywhere (the top bar, the altar, a home), so a world-camera shot would have no fixed set and
would fight the camera scripts, MouseLock and the dash; the cutscene never writes `Camera` (type, subject, CFrame, FieldOfView) or
the Humanoid, so nothing can be left broken after; (2) other players see nothing and nothing replicates; (3) phones: GUI frames are
cheap, `ParticleEmitter`s and `Beam`s do not render inside a `ViewportFrame` anyway, and no new texture or upload is needed; (4)
memory: a bounded instance budget (below), everything pooled and destroyed on close. The "camera move" is staged inside the GUI: a
`UIScale` push-in on the hero (1.00 -> 1.06 during the shakes, back to 1.00 on the burst).

**Storyboard A "Pedestal"** (the default; times normal / Fast hatch; Skip, from the first frame, starts the reveal on the next
frame: see Skip below):

| # | Phase (`EggStage.Phase()`) | Normal | Fast | What happens |
|---|---|---|---|---|
| 0 | `Intro` | 0.35 | 0.15 | The world dims: `Dim` (navy) 0 -> 0.55, the Lighting blur 0 -> 14 and a cool tint (Brightness -0.08, Saturation -0.25 against the current `LightingStack.Value`s, pushed as the preset `"Hatch"`; High graphics only: `GraphicsQuality` has only Low and High), four edge `Vignette` frames fade in, the machine's name slides down (`Title`), the bottom bar (Skip, Fast hatch) is there from frame 1 |
| 1 | `Strip` | 3.00 | 0.80 | The server's 40-cell strip of eggs scrolls on a glass `Track` with today's ease (`Curve 2.8`), soft speed streaks at full speed, `SpinTick` per passing cell (throttled to 12 a second), and stops with cell 34 under the gold `Pointer` |
| 2 | `Land` | 0.35 | 0.12 | The pointer bounces, the landed cell rings in its rarity colour, the other cells dim to 40%, `SpinLand` |
| 3 | `Rise` | 0.50 | 0.20 | The landed egg lifts out of the strip and grows (cell egg -> 380 px) onto a cloud-stone `Pedestal` in a `Spot` light cone; the strip slides away; the rarity `Backlight` disc fades in (its strength = the egg's glow) |
| 4 | `Crack` | 1.20 | 0.40 | "EPIC EGG!" (`CrackWord`, rarity word + " EGG!", 80 px); two shakes (rotation +-6 then +-10 degrees with a squash; one on Fast hatch); glowing `Cracks` grow at each shake (1 -> 3 -> 5 zigzag segments in the rarity colour), thin `Leaks` of light from the cracks lengthen, small sparks pop at each shake, the push-in |
| 5 | `Burst` | 0.35 | 0.25 | The halves fly apart (the top spins up-left, the bottom settles as the shell at the pedestal), a `Shock` ring expands 0 -> 900 px and fades, `Rays` (16) flash in and start turning, the rarity spark burst (counts below), a white micro-flash (Common-Epic, 0.12 s at 0.6) or the gold `Flash` (Legendary and up, rgb(242,182,68), 0.25 s in / 0.6 s out), `Shatter` |
| 6 | `Reveal` | stays | stays | The pet pops (UIScale 0 -> 1.15 -> 1, 0.35 s, Back ease) and turns gently on the pedestal (the PetViewport bob); the rarity `Banner` slides in (the word "EPIC!" 84 px on a ribbon); name 54 px + "NEW!"; the note (5.5 texts, " \194\183 guaranteed" for a pity Secret); `SpinAgain` / `Done`; Legendary and up keep slow gold rays; Mythic and Secret add falling confetti for 1.5 s; Secret a starry backdrop (14 twinkling stars) and a violet aura |

Reveal at **5.75 s** (normal) / **1.92 s** (Fast hatch) after `Show`. The chat line for Legendary and up is the server's (Task 6,
unchanged). Skip (the `Skip` chip, a tap anywhere outside the buttons, Esc, gamepad B) at any time before the reveal: sounds stop
and `Phase()` is `"Reveal"` on the next frame (the reveal starts at once); the burst's last 0.25 s (the shock ring, the rays, the
sparks, and the gold `Flash` exactly once for Legendary and up; no white micro-flash) plays as an overlay over the reveal's first
0.25 s; no delay, no hidden period. (Review 2026-11-07: this one rule replaces "the tail plays, then the reveal", which plan Tasks
20 and 27 contradicted.)

**x3.** Three strips stacked (as 5.5's x3 strips), landing 0.25 s apart (Fast 0.12 s); `Rise` brings the three landed eggs to
three pedestals (left, centre, right; 220 px each, phone 96); the eggs **crack in pull order** (1, 2, 3; the server's order, never
re-sorted), each `Crack` 0.9 s (Fast 0.4) + `Burst` 0.35 s (Fast 0.25), started 0.6 s apart (Fast 0.25); the reveal shows three
columns (5.5's sizes) with one `SpinAgain` (x3) and `Done`. Reveal at **7.15 s** normal / **2.66 s** Fast. The gold flash and the
loudest reveal sound follow the best pull, played on that pull's burst.

**Layouts.** 5.5's screen rule stands (the design canvas at the windows' factor, three anchors, the middle shrinks to 0.6, text
never shrinks, the x3 widths, portrait rows, the test sizes 640x360, 667x375, 844x390, 360x640, 390x844, 1280x720, 1366x768,
1920x1080). New sizes: PC pedestal 420 x 90 under the 380 px hero egg (egg centre y 470, pedestal top y 700), spot cone 520 wide;
phone hero egg 200 px, pedestal 220 x 48, spot 280 wide; the crack word PC 80 px / phone 40 px.

**Fit on every screen (review 2026-11-07).** 5.5's middle shrink (down to 0.6) also takes the crack egg and the pedestal, on
every layout; text never shrinks. A pedestal is always 1.1 x its egg wide and 0.24 x its egg tall (x1: PC 420 x 90, phone
220 x 48; x3: PC 242 x 53, phone 106 x 23), so it shrinks with the egg. Why: on a phone 5.5's frame leaves 242 px between the
title band (ends at y 92) and the bottom bar (starts at y 334) at 844x390, and 212 px at 640x360, while the full crack stack is
288 px (word 40 + egg 200 + pedestal 48); at 0.6 it is 189 (egg 120, pedestal 132 x 29). On the phone reveal the pet does not
stand on the full pedestal (a 48 px block under 5.5's pet at y 104-274 would cover the name at 276 and the note at 308): it
stands on a thin lip, 0.7 x the pet's width and 12 px tall, drawn behind the pet's feet with its bottom 8 px above the pet
frame's bottom, so it never reaches the name. The phone `Banner` is the reveal's title band: 44 px tall, its top 2 px under the
58 px inset, the word 40 px inside it (5.5's y 62), as wide as the word + 40 (at least 160); the x3 phone column banners are 28
px tall (word 22 px). The reveal's middle (pet, lip, name, note) is centred between the Banner's bottom and the bottom bar and
shrinks as 5.5 says (phone pet at least 110 px). On PC the full pedestal stays under the pet (top y 700) and clears the name at
y 806.

**VFX and budget** (all GUI unless named; every number a cap, checked by `EggStage.Stats()`):

| Effect | Built from | Cost |
|---|---|---|
| World dim | `Dim` Frame + 4 `Vignette` Frames with UIGradients; `Lighting.NimbusHatchBlur` (BlurEffect, Size 14: the only new Lighting instance) + the tint as `LightingStack.Push("Hatch", { ColorCorrection = { Brightness, Saturation } }, 0.35)`, popped by teardown (review 2026-11-07: LightingStack is the only client writer of Lighting and finds its target with `FindFirstChildOfClass("ColorCorrectionEffect")`, so a second ColorCorrectionEffect could become its target and be destroyed with its values) | 1 Lighting effect + 1 LightingStack preset, High only; tweened in / out |
| Strip | at most 12 recycled `Cell` frames per strip (a cell re-skins its egg with `EggArt.SetRarity` when it wraps: no instance churn), medium-form eggs | <= 12 x 3 cells, <= 14 instances per cell |
| Spot, Backlight, Pedestal | 1 Frame + UIGradient; 4 stacked round Frames; ~8 Frames (stone top, gold inlay, 3 cloud puffs) | static, tweened alpha |
| Shake, push-in | Rotation / UIScale tweens on the hero | <= 3 live tweens |
| Cracks, Leaks | <= 6 thin rotated Frames + UIGradient glow; <= 5 tapered Frames | per egg |
| Halves | `EggArt.Halves`: two CanvasGroups (rotated paint clips correctly), alive from `Crack` to `Done` | 2 per egg |
| Shock | 1 round Frame + 6 px UIStroke, one tween | 1 |
| Rays | 1 Frame of 16 thin wedges, an endless Rotation tween (12 s a turn; engine side, no Lua per frame) | 1 tween |
| Sparks / confetti | a pool of 64 small Frames (4-point stars and squares in the rarity colours); ONE Heartbeat moves the live ones (velocity, gravity, fade) and disconnects when none is live | burst counts: Common 12, Uncommon 16, Rare 20, Epic 28, Legendary 40, Mythic 48, Secret 48; confetti 24 (Mythic, Secret); Low graphics halves every count |
| Stars (Secret) | 14 star Frames, looping alpha tweens with offsets | 14 tweens |
| Flash, Banner, pet pop | 1 Frame; ribbon + word; the PetViewport's UIScale | tweens |

Totals: at most 450 GUI instances for an x1 roll and 750 for an x3, at most 24 live tweens plus the Secret stars, at most one
Heartbeat connection, one Lighting effect plus the `"Hatch"` LightingStack preset, one PetViewport per pull. Low graphics: no blur,
no tint, half the sparks, the rays static, no speed streaks.

**Never breaks the player.** The cutscene writes nothing to the Camera or the Humanoid and does not need the character: it plays
on through a death or a respawn to its reveal (the GUI is `ResetOnSpawn = false`; review 2026-11-07: on PC and gamepad the
character can still walk under the dim, and a fall off an island edge must not cut a paid reveal short). On open it calls
`MenuController.SetTouchHidden("Hatch", true)` and the cursor is freed by `MouseLock`'s `NimbusHatch` watcher; every exit (`Done`,
`Back` on the reveal, `Close`, a match start, `MenuController.Close()`, a phase error caught by the phase runner's pcall) runs one
`teardown(reason)`: the blur destroyed (only ours, by name), the `"Hatch"` LightingStack preset popped, the spark Heartbeat
disconnected, the pool and the tweens stopped and destroyed, `SetTouchHidden("Hatch", false)`, then `Closed:Fire(reason)` with
`reason` = `"Done"` (DONE, a tap, Esc or B on the reveal), `"Error"` (a caught phase error), `"Match"` or `"Close"`
(`EggStage.Close()` from anyone else, `MenuController.Close()` included). **The Shop window comes back only after `"Done"` or
`"Error"`, and only while ShopController is still open and the player is not `InMatch`** (ShopController's `Closed` handler checks
all three; review 2026-11-07). A match start or `MenuController.Close()` leaves the Shop closed: the Shop closes itself on
`InMatch` (whichever handler runs first, the `InMatch` check holds), and `closeEverything` closes the Shop first, then the
stage. So the Shop never comes back over a match, and its `SetTouchHidden("Shop", true)` never hides a phone's thumbstick in a
match. A test records Camera `CameraType` / `CameraSubject` / `FieldOfView`, the Humanoid's `WalkSpeed` / `JumpPower`, the
MouseLock state and `GuiService.TouchControlsEnabled` before a roll and checks them equal after `Done`, after a mid-roll match
start, after `MenuController.Close()` and after an injected phase error; `ShopWindow` is visible after `Done` and after the error,
and hidden with `ShopController.IsOpen() == false` after the match start and after `MenuController.Close()`; a character removed
mid-`Strip` (a new one added) still reaches the reveal.

**Sounds.** Existing `AudioIds` keys only (no uploads; new crack / whoosh sounds are later Suno / ElevenLabs work, the owner's
audio rule): `SpinStart`, `SpinTick`, `SpinLand`, `Shatter`, the `Reveal*` map; `opts.Scale = 0.6` below Legendary, 1 from
Legendary (5.5).

**Storyboard options** (only if the main session publishes a storyboard pitch before plan Task 27; every option keeps the
phases, timings, Skip, x3 order, VFX budget and reveal above; only `Rise` differs): **A "Pedestal"** (above, my pick: the
calmest read on a phone, the egg never leaves the frame); **B "Sky drop"**: the landed egg shoots up out of frame and drops back
through a cloud layer onto a cloud pedestal with a dust puff and a small screen bump (adds 0.2 s to `Rise`); **C "Machine"**: the
strip runs inside the machine's glass dome art, the machine shakes and drops the egg down a chute onto the pedestal (the dome art
at 520 px on PC; heavier on phones). Gemini could not be asked (the API answered 402, credits depleted); the main session can run
the creative check through gemini.google.com before Task 27.

**Files.** `src/client/UI/EggStage.lua` (the phases, the request path, the layout) and a new `src/client/UI/HatchFx.lua`
(the effects, so EggStage stays under its local cap and the Shop page can share the spark pool): `HatchFx.Pool(parent, n) ->
pool` (`pool:Burst(at, rarity, count)`, `pool:Confetti(n)`, `pool:Live()`, `pool:Destroy()`), `HatchFx.Rays(parent, rarity)`,
`HatchFx.Shock(parent, rarity)`, `HatchFx.Cracks(egg, rarity, step)`, `HatchFx.Leaks(egg, rarity, step)`, `HatchFx.Stars(parent,
n)`, `HatchFx.Dim(on)` (the `NimbusHatchBlur` effect, ours by name, and the `"Hatch"` LightingStack preset; High only),
`HatchFx.Stats() -> { Live, Pooled, Tweens, Heartbeats }`.

**API** (built in plan Task 20 with plain visuals, dressed in Task 27): `EggStage.Init()`, `Show(result) -> boolean`,
`Request(rouletteId, currency, spins) -> boolean` (the only `BuyRoulette` sender: `FIRE_GAP` 0.3 s, the pending flag,
`WAIT_TIMEOUT` 7 s), `IsPending()`, `IsShowing()`, `Phase() -> "Intro" | "Strip" | "Land" | "Rise" | "Crack" | "Burst" | "Reveal"
| nil`, `Skip()`, `Back()` (Esc's one path, called by ShopController: skip before the reveal, DONE on it), `Done()`, `Close()`
(toasts the pulls not shown yet), `Timings(fast, spins) -> { Intro, Strip, Land, Rise, Crack, Burst, Stagger, RevealAt }`,
`NoteText(pull, rarity)`, `Layout() -> "PC" | "Phone" | "Portrait"`, `IsPrewarmed(petId)`, `Stats() -> { Instances, Tweens,
Sparks, Effects, Heartbeats }` (`Effects` counts the blur and the `"Hatch"` preset); signals `Pending`, `Answered(result)`,
`Opened`, `Closed(reason)`.
Instances: `NimbusHatch` > `Stage` > `Dim`, `Vignette`, `Flash`, `Content` (the laid-out area under the 58 px inset) > `Title`,
`Strips` > `Strip1..3` > `Track` > `Cell1..12`, `Pointer`; `Hero` > `Spot`, `Pedestal1..3`, `Backlight1..3`, `Egg1..3`, `CrackWord`;
`Burst` > `Shock`, `Rays`, `Sparks`; `Reveal` > `Col1..3` > `Banner` (`Word`), `Shell`, `Pet`, `Name`, `New`, `Note`,
`EvolvedRibbon`; `BottomBar` > `Skip`, `FastHatch`, `SpinAgain`, `Done`. Everything else in 5.5 (the queue, waits, old-shape
results, a pull without a `Strip` starting at `Rise`, the evolved reveal, SPIN AGAIN as a new paid request, the match-start toast,
Esc / B priorities, Fast hatch as a saved setting) stands.

### 16.5 Painted eggs (egglook A, more detail, with VFX)

**One paint, world and GUI.** When this section was written, the working tree already held an uncommitted Blender rebuild of
the seven world eggs for this card (`blender/kit/props/lobby_shop.py`, prop `lobby_egg`, docstring "PAINTED (owner pick egglook
A, 'more coolness and details')", plus `blender/catalog/lobby.json`, `blender/meshes.json` and the seven `egg_*` manifests). Its
paint (below) is the design: the GUI eggs paint the same motifs, so the shelf eggs, the Shop and the cutscene show one egg per
rarity. It elaborates the pitch's `eggPattern("A")` (spots; zigzag band; white bands; a star band with gold; a cream band;
wavy bands; stars). The egg names stay (`Config.Eggs.Names`: Cloud Puff, Breeze, Raindrop, Thunder, Sunburst, Aurora, Starry
Night) so the Egg Guide board (Task 10) and every name keep working; renaming them to fit the new paint is an owner question
(16.8).

**One shape, three forms** (`src/client/UI/EggArt.lua`; API: `EggArt.New(parent, rarity, size, opts) -> Frame "Egg_<Rarity>"`
with `opts = { Form = "Auto" | "Simple" | "Medium" | "Full", Vfx = bool, ZIndex, Name }`, `EggArt.SetRarity(egg, rarity)`
(re-skins in place), `EggArt.Halves(parent, rarity, size) -> top, bottom`, `EggArt.Glow(rarity)` (5.6's numbers: 0 / 0 / 0.22 /
0.34 / 0.58 / 0.66 / 0.78), `EggArt.Tones(rarity)` (5.6's), `EggArt.Paint(rarity) -> { { Kind, ... }... }` (the motif list as
data, for tests). The oval body (UICorner 0.5, width 0.8 x height), the top-to-bottom tone gradient, the navy outline
rgb(11,16,48) at `size / 20` (at least 2 px, whole), and:
- **Simple** (under 48 px: the shop's odds rows, the machine domes, phone odds): body, outline, the glossy highlight, the
  rarity's main motif only (<= 8 instances).
- **Medium** (48-140 px: strip cells, x3 hero eggs on a phone): + a rim light (a slightly smaller oval with a transparency
  gradient), the main and second motif (<= 14 instances).
- **Full** (over 140 px: the stage's hero egg, the Secret hero card's big egg, `dump_gui eggs`): every layer below, a specular dot,
  a soft contact shadow ellipse under the egg, and a sheen band (UIGradient) that sweeps every ~4 s on High (<= 28 instances).

| Egg | Body (tones from `Config.Rarities`) | Paint at Full (Simple keeps the first motif) | VFX (`Vfx = true`, Rare and up) |
|---|---|---|---|
| Common, Cloud Puff | the Common colour | darker grey spots in three sizes, little white dots, the cartoon shine upper left | none (on the stage: a white dust puff at the burst) |
| Uncommon, Breeze | the Uncommon colour | a cream zigzag band with a dark green outline, lime spots in its bays, white dots | none; a slow sheen on Full |
| Rare, Raindrop | the Rare colour | two white bands edged in navy, ringed white dots between them, pale dots | glow 0.22; 3 drifting sparkles |
| Epic, Thunder | the Epic colour | a deep violet star band between two gold trims, white 4-point stars in it, white dots above, gold dots below | glow 0.34; the gold trims flicker every ~3 s; the stars twinkle |
| Legendary, Sunburst | the Legendary colour | a white-gold crown (band + eight points, deep amber outline) on a crimson ring, a gold trim under it with a gold ball on every point, ruby and sapphire gems in the band with amber studs between, cream swags with pearls under the cap | glow 0.58; slow-turning soft rays behind; the gems glint; 4 gold sparkles |
| Mythic, Aurora | the Mythic colour | flowing gradient bands (violet / plum foot, blush / pale cap, wavy edges), a violet wave ribbon, eight teal swirls springing off it, sparkles | glow 0.66; the ribbon's gradient drifts (an endless Offset tween); 6 pastel sparkles |
| Secret, Starry Night | rgb(74,68,104) -> rgb(18,16,28), a violet dusk at the foot | violet cracks running down from the tip into a ring of magenta runes (two lines + eight rune marks), white 4-point stars, pin-prick stars | glow 0.78 violet; the cracks and runes pulse; the stars twinkle (alpha tweens, offset); 2 orbiting star sparkles; a dark violet aura ring |

Simple keeps one motif: Common the spots, Uncommon the zigzag band, Rare the two bands, Epic the star band (no stars), Legendary
the crown band, Mythic the wave bands, Secret the stars and the rune ring's two lines. From Epic up the details the mesh makes
Neon (`Glow<What>` parts: trims, stars, crown balls, gems, the ribbon, swirls, cracks, runes) get a soft light layer in the GUI
too (a lighter copy behind them with a transparency gradient).

**Where the VFX show.** The Shop: the Secret hero's big egg (Full, Vfx) and each card's machine dome (a slow glass sheen); odds-row
and dome eggs are Simple with no VFX (20+ eggs on screen). The strip: Medium eggs with a static rarity ring for Rare and up; only
the landed cell gets its VFX. The cutscene's hero egg: Full, Vfx, plus 16.4's effects. The sparkles are GUI frames from the
stage's pool (on the Shop page: a page-owned pool of 16, stopped while the page is hidden). Budget: an egg's VFX adds at most 8
instances and 3 tweens; no Heartbeat outside the spark pool.

**The world eggs** (the Egg Guide's shelf, Task 10). Blender `blender/kit/props/lobby_shop.py` prop `lobby_egg`, the painted
rebuild above (in the working tree, uncommitted, when this was written; review 2026-11-07: the main session commits those 12
files on their own before plan Task 16, so lanes and Task 26 see them and no other commit sweeps them in; plan Task 28 inspects
and fixes): same keys
`egg_common` .. `egg_secret`, the shape and pivot unchanged (2.2 x 3 x 2.2 studs, bottom centre, attachment `Center`), 0.1-stud
cells, baked SmoothPlastic shading, Neon only in `Glow<What>` parts from Epic up; rendered beside a 5-stud player before it counts;
manifests regenerated, no ids (the Part fallback ellipsoids stay until the owner uploads). Server-side shelf VFX in
`LobbyBoardBuilder.EggGuide`, one set per egg at its `Center` (the Part fallback and a dressed mesh alike; nothing is added per
`Glow` part, so the count stays bounded): a `ParticleEmitter` sparkle on the Rare and up eggs (built-in texture; Rate
Rare 1, Epic 2, Legendary 3, Mythic 4, Secret 5; the rarity colour; LightEmission 0.5; Lifetime 1.2-2; Speed 0.3-0.8; tagged
`DETAIL_TAG` so Low graphics parks them), one `PointLight` `EggShelfGlow` 1.0 / 10 at the shelf centre (inside the lobby light
rule), and each egg tagged `NC_Spin` (`SpinSeconds 14`, `BobStuds 0.12`, `BobSeconds 3.2`: a slow display turntable; the
LobbyFx heartbeat moves it).

**Chat colour.** The Legendary-and-up chat line colours the rarity word with `Config.Rarities` (Task 6); Secret's near-black reads
badly on Roblox's dark chat (the morning question from Task 6). `Config.Eggs.ChatColors = { Secret = Color3.fromRGB(180, 150,
255) }` (the Starry Night star violet) overrides it in `NotifyController` for the chat line only; `Config.Rarities` stays.

### 16.6 Titles (the owner's board note)

"top 100 players in the game gets a golden title, top 10 gets rainbow fade title, make it be seen also in the players server list
and as the player name in the game. Creator gets a "Creator" name title in the game above the name which is only my account." Q&A:
the ranking is the **Trophies** global rank only; shown as a title above the head (gold for ranks 11-100, a rainbow colour fade for
1-10) plus a plain-text **"Rank"** column in the Roblox player list.

**Config.** `Config.Attr.Title = "Title"` (`"Creator"` | `"Top10"` | `"Top100"`, absent otherwise) and `Config.Attr.TitleRank =
"TitleRank"` (1..100, absent outside the top 100 read); `Config.Leaderboard.RankTitles = { Stat = "Trophies", Rainbow = 10, Gold =
100, Column = "Rank", ColumnText = { Creator = "Creator", Top10 = "Top 10", Top100 = "Top 100" }, Tag = { Creator = "CREATOR",
Top10 = "TOP 10", Top100 = "TOP 100" } }` (`Gold <= ReadSize` checked by `config_shape`).

**Server (inside `LeaderboardService`, which already holds the Trophies top-100 page; no new service, no `Main.server` local).**
- Rank: the player's index in `S.Pages.Trophies.Entries` while that page is good (a good Trophies page is enough; the other stats'
  pages and the board's Scope do not matter). In the "Server" scope before the first good page, or with no store (Studio without
  API access), nobody has a rank. A player outside the 100 read has no rank.
- Creator: **`DevService.IsOwner(player) -> true | false | nil`** (new public wrapper of DevService's `isOwner`: `game.CreatorType
  == User` and `UserId == game.CreatorId`, or for a group game `GetRankInGroup(CreatorId) == 255` under pcall; nil when the group
  call failed, so `isGroupOwner` returns nil instead of false on an error; `DevService.IsAllowed` keeps answering a boolean). Never
  `Config.Dev.Admins`, never Studio's `AllowInStudio`, never a hard-coded id. Asked once per join in a task (`S.Owner[player]`);
  a nil answer is asked again at the next Trophies refresh.
- Kind: Creator wins (the owner in the top 10 shows "CREATOR"; `TitleRank` is still set); else rank <= 10 -> `Top10`; rank <= 100
  -> `Top100`; else none.
- `LeaderboardService.TitleOf(player) -> kind | nil, rank | nil` (read only: for tests and later readers).
- `applyTitle(player)` writes only on change: the two attributes and `leaderstats.Rank.Value` = `ColumnText[kind]` or `""`. Called
  on `Players.PlayerAdded` (titles need no profile: the rank is the store's, the Creator the game's), after the owner answer, and
  for every player after each good Trophies read (the RefreshSeconds 240 cycle); `S.Titles[player]` dropped on leave.
- `leaderstats`: only `PlayerService` creates `leaderstats` and its values: `Rank` (a StringValue, `""`) right after `Tokens`,
  synchronously in `setupPlayer` as today, so the list shows Tokens then Rank and still sorts by Tokens. LeaderboardService never
  creates `leaderstats` or `Rank` (review 2026-11-07: its `PlayerAdded` handler is connected first, `Main.server` inits it before
  PlayerService, and handler order is not guaranteed, so creating them there could put Rank first and sort the list by it):
  while `leaderstats.Rank` is missing, `applyTitle` sets the two attributes and writes Rank from a task that waits for it
  (`WaitForChild`, 10 s), or at its next pass. Roblox's list cannot colour text: the column is plain text.
- Security: attributes and the StringValue are written by the server only; the client sends nothing; the rank comes only from the
  OrderedDataStore page the server reads.

**Client** (new `src/client/Controllers/TitleController.lua`, booted after `VipController`):
- Per player: the `Title` / `TitleRank` attributes, `CharacterAdded`, `InBattle`; a BillboardGui **`TitleTag`** on the head
  (`Adornee` = Head, `Size` 240 x 36 px offset, 240 x 74 with the crown slot below (a constant on-screen size), `MaxDistance 90`,
  `AlwaysOnTop false`, `LightInfluence 0`) > `Plate` (navy at 0.35, round corners, 2 px stroke, width from the measured text) >
  `Label` (Theme Display font, 22 px, white, a 2 px navy UIStroke) > `Fill` (UIGradient). **Its height above the name is set in
  pixels, not studs** (review 2026-11-07: the tag, the VIP crown and Roblox's own name are all constant-pixel billboards, so a
  gap in studs shrinks on screen with distance; at the default 70 degree field of view a stud is about 278 / d px on an 844x390
  phone, so a 1.1-stud gap is smaller than the plate and the crown past about 9 studs): `StudsOffset (0, 2.0, 0)` (about where
  Roblox's name is anchored above the head) and `SizeOffset (0, 0.5 + 26 / H)` (H = the billboard's px height), so the plate's
  bottom stays 26 px above that point at any distance (Roblox's name is about 20 px tall); the exact stud anchor is a Studio
  check.
  - Top10: "TOP 10 \194\183 #3" with a **rainbow fade**: `Fill.Color` = seven hues (red, orange, yellow, green, cyan, blue,
    violet) twice across 0..1, and an endless TweenService tween of `Fill.Offset` (0, 0) -> (-0.5, 0) over 2.4 s, Linear, repeat
    -1. A UIGradient does not wrap (past its last key it holds the last colour), so the `Label` is **twice the measured text
    width with `TextXAlignment Left`** (the Plate keeps the text width): the text always sits in the half that maps to one full
    period of the two-period sequence, and the half that holds the clamped violet has no text, so the loop is seamless (review
    2026-11-07: with a text-wide Label the right half went solid violet at the end of each loop, then snapped back).
    Engine-side: no Lua runs per frame; at most one tween per Top-10 tag (at most ten in any server). Low graphics: the tween is
    paused (a still rainbow).
  - Top100: "TOP 100", a static gold gradient (rgb(255,236,150) -> rgb(242,182,68) -> rgb(196,128,32), Rotation 90).
  - Creator: "CREATOR", a static cyan -> violet gradient (rgb(120,220,255) -> rgb(160,120,255)), 24 px.
- Hidden while that player is `InBattle` (the battle scene); shown in the lobby, matches and homes. The local player sees their
  own tag in third person (the pride of it) and not in first person: a 4 Hz check of the camera's distance to the head (< 2 studs
  hides it) for the local player only.
- `VipController`: when a player has a `Title`, it shows no `VipCrown` billboard of its own; it calls
  `TitleController.SetCrown(player, on)` with its usual rule (VIP, Graphics High, not InBattle / InMatch), and the TitleTag draws
  the crown glyph as `Crown` (34 x 34 px, centred, 4 px above the Plate) inside the same billboard (then 240 x 74 px), so crown
  and plate keep a 4 px gap at every distance (review 2026-11-07: replaces "the crown moves up to 3.7 studs", a stud gap that
  slid into the tag). Without a Title the crown is as today (its own billboard at 2.4 studs). It listens to `Title` too.
- Budget: one BillboardGui and five instances per titled player (six with the crown), no Heartbeat, no per-frame Lua.

**Tests.** `lb_titles` (server; a 100-entry mock Trophies store): rank 3 -> `Title "Top10"`, `TitleRank 3`, `leaderstats.Rank
"Top 10"`; rank 57 -> `Top100` / 57 / "Top 100"; outside the 100 -> none / ""; the owner (`game.CreatorType` User, `CreatorId` =
their id) -> "Creator" even at rank 3 (`TitleRank` 3 kept); an Admin who is not the owner -> no Creator; a group game with
`GetRankInGroup` 255 -> Creator, an erroring `GetRankInGroup` -> none, asked again at the next refresh, then Creator; the "Server"
scope (no store) -> no Top titles, Creator still; the next read moves rank 3 to 12 -> `Top100`; no attribute write without a
change; `leaderstats` children Tokens then Rank, also when LeaderboardService's `PlayerAdded` handler runs before
PlayerService's (Rank then gets its text once it exists). `client_titles`: the tag per kind with its text, the rainbow tween
running (`Fill.Offset` changes over 1 s) for Top10 only, the gold and Creator gradients static; the Top10 `Label` twice the text
width, left-aligned, in a Plate of the text width; the tag removed when the attribute clears; hidden while `InBattle`; the local
player's tag hidden with the camera at the head and shown at 12 studs; Low graphics -> the tween paused; `SizeOffset.Y == 0.5 +
26 / H`; a titled VIP: `Crown` inside the TitleTag 4 px above the Plate and no `VipCrown` billboard on that head; an untitled
VIP: the `VipCrown` at 2.4 studs; text >= 20 px. `dump_gui` scene `titles` (the three tags on dummy characters) at 844x390 and
1920x1080, and `titles:10`, `titles:30`, `titles:60` at 844x390 (the name stand-in, the tag and the crown placed where they
project from that many studs, 70 degree field of view, as the `portal` scene's distance mode does): no overlap at any of them.

### 16.7 Data, save and security

Nothing new is stored: the titles are attributes and a leaderstats StringValue; the prices and odds are Config; the Shop and the
cutscene are client UI; the trove moves in the world only. The money rules of section 7 hold unchanged (the Secret guard now
allows Celestial through Config); the one added sales rule is 16.1's: token-granting Robux products are not prompted for an
account that is not PolicyService-"Allowed" (paid receipts are still always granted). `DevService.IsOwner` is the only new
server entry point and is not reachable from a client.

### 16.8 Calls I made (for the owner to check)

1. Token packs live in the Gems tab (A has no Currency tab); they get "BEST VALUE" on the biggest pack but no % ribbon.
2. The top bar's Shop opens the last tab of this session, first time Eggs; the Packs tab shows a gold dot while the Starter Pack is
   on sale and unbought.
3. Creator beats a Top 10 title for the owner (one title line); the player list says "Creator".
4. Titles show everywhere but battles; the local player sees their own title in third person only.
5. A Celestial Secret does not count for (or reset) the Secret Roulette's pity.
6. The walk-up prompt is restored at the old stall spot (now the Egg Guide), range 10, "Open" / "Shop"; the stall itself stays gone.
7. The cutscene is GUI-only with a client-side world blur and a LightingStack tint; the camera and the character are never
   touched, and it plays on to the reveal through a death or a respawn (only a match start, `MenuController.Close()`, DONE or an
   error end it). The Shop comes back after it only after DONE or an error, never over a match.
8. x3 eggs crack in the server's pull order (no build-up re-sort).
9. Fast hatch sits at the rail's bottom on the PC Eggs tab and in the cutscene's bottom bar (the phone rail has no room).
10. The arch caption "pets & items" becomes "eggs & gems".
11. Secret's chat-line colour becomes the Starry Night violet (Task 6's morning question).
12. The GUI eggs paint the motifs of the painted Blender rebuild already in the working tree (16.5), not the sky-weather pictures;
    the egg names stay.
13. (Review 2026-11-07, 13 call 8 closed) The Robux products that grant Cloud Tokens (`Tokens1..3`, the Pro Pack) are not sold to
    accounts PolicyService restricts from paid random items (or while that answer is unknown), since a token spin can now give a
    Secret; earned tokens still spin for everyone; paid receipts are always granted.
14. (Review 2026-11-07) "BEST VALUE" is computed from the prices shown (most gems or tokens per Robux, ties to the bigger pack),
    like the % ribbons; the top bar's Shop pill does not glow during the tutorial's shop step (the world arrow does that job).

**Questions for the morning** (my recommendation first):
- Tokens now buy Cloud and Storm spins for fewer Robux than gems do (Cloud 1.63 vs 4.90 R$ at the 49 R$ packs), while gems win on
  Sky, Celestial and the Secret Roulette. Keep (the owner's numbers), or nudge the Cloud / Storm gem spins? Recommended: keep and
  watch the first week's purchases.
- Restricted accounts and token packs (13 call 8, back on the list with higher stakes: Celestial's 2% Secret is on token rolls).
  Keep the token-granting products (Tokens1..3, Pro Pack) off sale for restricted accounts (call 13), or sell them and lock token
  spins for those accounts instead? Recommended: keep them off sale (earned tokens keep every machine open to every account).
  Review round 1 adds: the off-sale lock covers the server's prompt only; an exploit can open the prompt from the client
  (`PromptProductPurchase` with the product id from Config) and the paid receipt is granted, so a restricted account can still
  buy token spins (and a 2% Celestial Secret). To close that: refuse token-paid spins for `PolicyState` "Restricted" accounts,
  or record Robux-granted tokens on such accounts and refuse spins that would spend them. Recommended: refuse token-paid spins
  for "Restricted" accounts only (simple, server-side; earned-token spins then close for them too, which the owner should OK).
- Trophies feed the global board and the TOP 10 / TOP 100 titles (review round 1). BattleService's anti-farm limit (3 rewarded
  duels per pair per 30 min) lives in one server's memory, and a loser at 0 trophies loses nothing, so two accounts can trade
  wins across server hops to climb the board. Make the pair limit hold across servers (a MemoryStore sorted map, or recent
  opponents in the Battle record) and pay less for beating a 0-trophy opponent, or base the titles on a stat that cannot be
  traded? Recommended: the cross-server pair limit plus no trophies for beating a 0-trophy player, as its own small build
  before the board goes live.
- A cutscene storyboard pitch (A Pedestal / B Sky drop / C Machine) before Task 27? Recommended: build A unless the owner asks.
- New crack / whoosh sounds for the cutscene from Suno / ElevenLabs (the owner's audio rule)? Recommended: yes, as a later audio pass.
- Rename the eggs to fit the painted motifs (Thunder has no lightning now, Sunburst wears a crown)? Recommended: keep the names
  for this branch; a rename is one Config table and the Egg Guide board.
- After the owner uploads the egg meshes, show the real 3D egg (a ViewportFrame) in the cutscene's Rise and Crack? Recommended:
  later; `Glow` parts read flat in a ViewportFrame, so the GUI glow layers would stay on top.

### 16.9 Review round 1 (2026-11-08, sleep mode: decided by the main session's build agent, checked against the code)

These override the text above where they differ.
- **The payback rule.** A full-stack pull pays `PetService.SubstituteTokens(roulette, rarity)`: the rarity's
  `Config.Index.Rewards` Tokens, at most `floor(token Price x Config.Eggs.SubstituteShare)` (0.5) for a token roulette, whichever
  currency paid (Cloud 25, Storm 125, Sky 500, Celestial 2,500). Before this, once a player's low stacks were full, a token spin
  paid back more than it cost (a Storm x3 returned up to 4,120 tokens for 750), an endless token source. The gems-only Secret
  Roulette has no token price and keeps the rewards (Mythic 5,000, Secret 10,000); gems cannot be bought with tokens, so that
  is no loop.
- **The roulette timeout toast** no longer asks for a retry ("Still waiting for the roulette. Your spin will hatch as soon as it
  arrives."): a request that left the client is almost always charged, and a second tap was a second paid spin. WAIT_TIMEOUT stays
  7 s (5.5); a request id the server echoes is left for later.
- **The cutscene's reveal** marks itself built last (`roll.RevealBuilt`); an error inside it toasts the pulls like any exit before
  the reveal. A pet whose prewarm build fails is not built again that session, and the pulls after it still warm.
- **The Secret SPIN's pulse** runs only while that button can be tapped (not Locked, Loading, Pending or without odds).
- **The HUD Gifts button** hides while the Shop is open (`ShopController.Toggled`): it sat over the Shop header's token balance
  and the X at 844x390 and 1366x768.
- **The gem settle read** is one GetAsync per attempt (never held across the 1.5 s retry under the lock), backs off 5, 10, 20,
  40, then 60 s, each plus up to 25% at random, and a GetAsync budget under 10 postpones it 5 s without counting a failure. The
  first read stays at 15 s (no extra jitter there: it would move the hold).
- **The dev /reset** clears `Pity` (live and written over the store).
- **Developer accounts** (`DevService.IsAllowed` in a live server) are never written to the global leaderboard stores: their tools
  grant pets and gems and whatever those buy. Their own values still show in the You row and the Server scope.
- **The board** is found by the tag `Config.Tags.LeaderboardFace` on its Face (CollectionService), not a handler on every
  instance added to the workspace.
- **GemIcon's star** is the child "Glint" (a test lookup of "Star" made the Blender kit treat that palette key as looked up by
  name and broke its selftest for six evolved-pet manifests).
- Tooling: `run_checks.sh` runs `mesh_keys.py --check`; the Task 31 gate list adds `blender/kit/selftest.py`; the contract lists
  `DataService.GemsSettled` / `_SettleForTest` / `Settled`, `PetService.SubstituteTokens`, `ShopController.Toggled`.
- Left open, with the owner: the token-pack lock covers the server's prompt only (16.1 note, 16.8 question); Trophies can be
  traded between accounts across servers (16.8 question); the save session lock (section 15) with its concrete case: a forced
  Secret spent on server A whose leave save fails and lands as an orphan after server B settled lets B sell a second forced
  Secret for the same 500 gems.

### 16.10 Review round 2 (2026-11-08, sleep mode: decided by the main session's build agent, checked against the code)

These override the text above where they differ.
- **The skip finger never buys a spin.** The roll's Skip chip sat centred in the bottom bar, and the reveal's SPIN AGAIN + DONE
  are centred on the same row, so a double tap on "Tap to skip" landed on SPIN AGAIN one frame after the reveal appeared
  (844x390: Skip 318..526, SPIN AGAIN 248..468, DONE 476..596; also 640x360, 667x375, 1280x720, 1366x768, 1920x1080 and
  360x640 portrait, where the roll bar wrapped Skip onto the reveal's button row). Mashing looped skip, SPIN AGAIN, skip: one
  paid spin about every 0.5 s.
- **Arming.** On the reveal, SPIN AGAIN, DONE and a tap's close (the Dim, "Tap to close") act only once the reveal is armed:
  `ARM_AFTER` 0.8 s after it appeared AND `ARM_QUIET` 0.5 s after the last tap on the stage (the Dim, the Skip chip, SPIN AGAIN,
  DONE); every tap restarts the wait, so a mash never arms the paid button. SPIN AGAIN and DONE show disabled until then (their
  label and price stay). This replaces the old 0.5 s tap guard. A skip before the reveal is still at once (5.5 "no delay").
- **The bar.** The roll's Skip chip and Fast hatch toggle sit exactly on the reveal's chip row ("Tap to close" and its Fast
  hatch; `EggStage` `L.rollBar`): PC 360x60 at the bottom left, phone 170x44 at the bottom left (packed narrower on 640 / 667
  px), portrait the reveal's lower row. "Tap to skip" becomes "Tap to close" in the same spot, never SPIN AGAIN or DONE. The
  reveal's centred SPIN AGAIN + DONE row (the pitch) is unchanged, and the pitch drew the roll's SKIP in a bottom corner too.
  The Skip chip is narrower than 5.5's 440x60 / 208x44 (still a 44 px target, text unchanged).
- **Not changed:** Esc and gamepad B (`EggStage.Back`) stay DONE at once on the reveal (5.5): keys never land on a paid button.
  `EggStage.Done()` / `Skip()` stay the API without a wait.

### 16.11 Review round 3 (2026-11-08, sleep mode: decided by the main session's build agent, checked against the code)

These override the text above where they differ. Measured with Roblox's real fonts (GothamBlack is drawn as Montserrat Black;
the advance table of `RedoGeom.realWidth`): the smoke mock's flat 0.5 em per character had hidden all of it.
- **Prices fit their buttons.** The phone's 74 px x3 button showed Sky's "3,000": "x3" + token + "3,000" at 15 px is 83 px, so the
  price ran about 11 px onto the gem button. The phone's x3 total is now `Theme.ShortNumber(3 x price, 1000)` (150, 750, **3K**,
  15K). Every spin button (any layout) whose row is wider than the button even at the 2 px gap takes that short form
  (`ShopEggs` `H.arrange`, measured by TextService live; a PC card at its 250 px minimum held "15,000" 2 px short). The text
  never steps under the 15 px phone floor.
- **SPIN AGAIN** measures its row (label + coin + price + the two 6 px gaps) and keeps 16 px of the button free
  (`EggStage` `K.AGAIN_SLACK`), else the price takes the short form from 1,000 up: at 640x360 "SPIN AGAIN x3" + coin + "3,000"
  (202 px) filled the 204 px button edge to edge, now "3K"; at 844x390 (220 px) "3,000" stays.
- **NEW! on an x3 phone / portrait column** is a chip on the pet frame's top-left corner (56 x 22, tilted -8 degrees, the
  EvolvedRibbon's mirror; 10 px under the ribbon when both show). Beside the 18 px name it left the name column - 24 - 64 px
  (117 at 640x360, 126 at 667x375, 172 at 844x390, 150 in 360x640 rows) and cut most Legendary to Secret names. The name now
  has the whole row (181 px or more; the longest catalog name, Frostling Penguin, is 175 px). PC keeps the pitch's row (NEW!
  beside a 36 px name, 392 px for it).
- **An x3 column's note** leaves the pet's name out for a duplicate ("1 of 4 Legendary pets · you have 12 now";
  `EggStage.NoteText(pull, rarity, true)`): the name sits right above, and the long form wrapped to three lines in the phone's
  36 px note box. The x1 note keeps the name.
- **Roblox's player list is on again.** `HudController` hid it (with the health bar) since 2026-10-08 because the `leaderstats`
  Tokens column sat over the top-right token strip; that hid the Rank column 16.6 asks for ("make it be seen also in the players
  server list"). Only the health bar is hidden now. Open, with the owner: on PC Roblox may open the list over the HUD's
  top-right currency strips and the toasts under them until the player presses Tab (a phone opens it only from the top bar);
  the strips are not moved in this round, and how the two sit together is a Studio check.
- **Tests.** `client_shop_mobile` / `client_shop_portrait` / `client_shop_sizes`: every spin button's word, icon and price
  inside it with the real widths (`ShopEggs.Metrics.MEASURE` = `RedoGeom.realWidth`); `client_egg_stage_mobile`: a Sky x3 with
  two NEW long names and a duplicate at all seven sizes, every name and note fitting, NEW! clear of the name, note, banner and
  ribbon, SPIN AGAIN's row 4 px clear each side; `client_load`: the player list enabled, a re-enabled health bar turned off.

### 16.12 The owner's answers of 2026-11-08 (token spins on restricted accounts, Trophies across servers)

These override the text above where they differ (16.1's token-pack note, 16.7, 16.8 call 13 and its two morning questions).

**Token-paid spins on restricted accounts (the owner's pick A).** The server never opens the token packs' Robux prompt for an
account PolicyService does not call "Allowed" (16.1), but a client can open it itself and a paid receipt is always granted. So
the spin is the lock now:
- `PetService.BuyRoulette` refuses a token-paid spin unless `GemService.TokenSpinLock(player)` is nil, which it is only for
  PolicyState "Allowed". "Restricted" answers "Token spins are not available on your account"; "Checking" (no answer yet, a
  failed lookup, no GemService, an error) answers "Checking your account, try again in a moment" and asks PolicyService again,
  the token lock's fail-closed rule. The check sits before the balance (nothing is charged, nothing rolled) and the remote
  answers `RouletteResult(Ok = false, Reason)` as for any refusal. Gem spins keep their own lock, unchanged.
- No new saved field: earned tokens and bought tokens are one balance, so every token spin closes for a restricted account.
  Receipts are still always granted (the tokens stay in the balance, spendable if the policy answer ever changes).
- The Shop: every token Spin / x3 button reads "Locked" (the token cards' word) and is inactive while `PaidRandomItemsRestricted`
  is not false, exactly like the gem buttons; the cutscene's SPIN AGAIN reads "Locked" for a token roll too, and
  `EggStage.Request` for tokens toasts "Token spins are not available on this account right now." and sends nothing.
- Consequence for the owner to know: a restricted account can no longer hatch from any roulette (gem spins were already
  closed), so the tutorial's "Your First Pet" step (Rolled) cannot be completed there; such a player can skip the tutorial and
  still gets pets from the daily gifts and the other free grants. Left open as a follow-up (a free, non-paid first spin, or the
  step skipped for restricted accounts) for the owner to decide. **Answered in 16.13**: the step gives a fixed starter pet.
- Tests: the smoke mock's PolicyService now answers "allowed" by default like Roblox does for an ordinary account (a double
  replaces it; nil brings it back; false = no API at all). `egg_spin_x3` (restricted: x1 / x3 / every machine refused with the
  text, nothing charged, the remote's answer; unknown: refused, then allowed once PolicyService answers), `p2gems_policy`
  (restricted and unchecked accounts refused), `client_shop_eggs` (token buttons Locked for restricted and unknown, taps send
  nothing), `client_egg_stage` (token SPIN AGAIN Locked, the toast). The Storm Altar's "awakens soon" checks join with no API.

**Trophies across servers (the owner's pick).** BattleService's pair limit (PAIR_LIMIT 3 counted duels per pair per
PAIR_WINDOW 1,800 s, any outcome, counted at the duel's start) lived in one server's memory, so two accounts could trade wins
by hopping servers, and a 0-trophy loser loses nothing. The design:
- **Where the record lives.** On BOTH duellists' saves, `Battle.Duels = { { U = the opponent's UserId, T = Unix seconds }... }`,
  newest first. Every duel start that counts for the limit (not a practice duel) writes one entry on each side
  (`DataService.RecordDuel`), also when that start is already past the limit (the in-server list does the same). Recording both
  sides (not only the winner) keeps the rule exactly the in-server one: a winner-only record would let A and B alternate
  wins for 3 + 3 rewarded duels per window.
- **How it is read.** At the start `pairAllows` takes the highest of this server's list, A's entries for B and B's entries for
  A inside the window (`DataService.DuelsWith(player, opponent, now - 1800 + 1)`); 3 or more makes the duel trophy-free,
  announced at the start as before. Either save alone holds the limit (one lost save does not reset it). The Unix clock is
  `Raid.now()` (os.time; tests replace it through `BattleService.Debug.RaidNow`).
- **Bounds.** At most 32 entries (`P3.DUELS_KEEP`; the oldest dropped), each U a whole UserId 1..1e15 and T whole Unix seconds
  > 0 (junk dropped, duplicates once): about 1 KB at most. Only the last 30 minutes matter; 32 counted duels in 30 minutes
  would need about ten other opponents in between to push a pair out, and the other side's record still holds it.
- **Save rules.** A save without the field reads `{}` (no migration). It is stored only when not empty, never sent in the
  ProfileSync snapshot (opponent ids stay on the server), merges across servers as a union of entries (then capped), and may
  change while provisional (a union merges safely). A server of the older build still running during a rollout rebuilds
  `Battle` without it, so for that window the limit counts only the newer servers' duels.
- **0 Trophies.** `b.TrophiesAtStart` keeps both totals at the start; a winner whose opponent held 0 Trophies gets no Trophies
  (`rw.NoTrophies = true`, toast "Victory! Your opponent had no trophies to win. +N tokens"); the win's tokens and XP, PvPWins
  and the loser's side are unchanged. Taken at the start so the order the two sides are paid in cannot matter.
  Consequence for the owner to know: every account starts at 0 and duels are the only source of Trophies, so two brand-new
  players never earn Trophies from each other; new Trophies enter only when someone beats a player who already has some
  (live saves from before this build seed it). Left open: a softer rule (fewer Trophies, not none) if that feels wrong.
  **Replaced by 16.13** (the owner picked the softer rule: a quarter of the win, at least 1).
- Tests: `p3bs_pair_hop` (three duels, both saves hold them, a real leave / rejoin with the server's list cleared: the 4th is
  trophy-free; one save alone holds it; 30 minutes on the Unix clock later the pair earns again; the 32-entry cap and junk) and
  `p3bs_zero_trophy` (a full win over a 0-trophy player pays tokens and XP, no Trophies). The duel tests that expected
  Trophies.Win from a brand-new opponent give both duellists trophies first.

### 16.13 The owner's follow-ups of 2026-11-08 (0-Trophy opponents, the restricted first pet)

These override 16.12 where they differ (its "0 Trophies" bullet and its tutorial consequence).

**A win over a 0-Trophy opponent pays a smaller prize, not none.** The cross-server pair limit of 16.12 stays exactly as it is.
- `BattleService.ZeroTrophyPrize(trophies, share?)` = max(1, floor(share x trophies)); share = `Config.Battle.ZeroTrophyShare`
  (0.25, the owner's quarter; a share outside (0, 1] or junk reads 0.25); a prize of 0 or less comes back unchanged. Pure.
- `payDuel`: when the loser held 0 Trophies at the start (`b.TrophiesAtStart`, as in 16.12) the winner's Trophies.Win (20)
  becomes ZeroTrophyPrize(20) = 5; tokens and XP of the win stay in full; `rw.NewOpponent = true` (replaces 16.12's
  `rw.NoTrophies`, which no client read). The toast: "Victory! Your opponent was new: smaller trophy prize. +5 trophies, +N
  tokens". Every other win, the loser's side, the pair limit, practice duels and early forfeits are unchanged.
- Consequence: two brand-new players now seed Trophies slowly (5 per win, at most 3 rewarded duels per pair per 30 minutes,
  and the loser stays at 0, so the winner keeps getting the smaller prize from that pair).
- `Config.Battle` is new (it held nothing before; BattleService's other tunables stay local constants).
- Tests: `p3bs_zero_trophy` (red on the 16.12 code first): the Config factor, the pure rule (20 -> 5, 21 -> 5, 3 -> 1, 1 -> 1,
  0 -> 0, share 0.1 / 0.01 / 1, junk shares -> 0.25), a full win over a 0-Trophy player pays 5 Trophies + the full tokens and XP
  with NewOpponent and the new toast; the same pair after the loser holds 50 Trophies pays the normal +20 and the normal toast.
  README's fair-play line says a quarter (+5 instead of +20).
- **Review fixes (2026-11-08, the main session's decisions).**
  - *Low, not only 0.* A loss never takes a player below 0, so an alt holding a few Trophies (say 5) lost only those 5 while
    feeding the full +20. The smaller prize now applies when the loser's Trophies at the start are below what a normal loss
    takes: `BattleService.LowTrophyOpponent(trophies)` = a known total < max(1, |`BattleCatalog.Trophies.Loss`|) (10 today):
    0, 5, 9 -> the smaller prize; 10, 50 -> the full win. `rw.LowTrophyOpponent = true` (replaces `rw.NewOpponent`, server
    only), toast "Victory! Low-trophy opponent: smaller trophy prize. +5 trophies, +N tokens".
  - *Unknown is not 0.* `b.TrophiesAtStart` holds nil for a record that cannot be read at the start (not loaded,
    provisional); nil is never low, so the winner is not cut for the server's blind spot.
  - *The duel record cannot be flushed.* `Battle.Duels` keeps every entry of the last 30 minutes (`P3.DUELS_WINDOW` 1,800 s
    on `os.time()`), plus at most 32 older ones (`P3.DUELS_KEEP`), never more than 64 in all (`P3.DUELS_MAX`, about 2 KB);
    before, ~30 duels with other opponents inside the window could push a pair's recent entries out of the 32.
  - Tests: `p3bs_zero_trophy` (the pure rule incl. 0 / 5 / 9 / 10 / 50 / nil / NaN / a string; full duels against 0, 5
    (smaller prize, the loser ends at 0) and 50 Trophies (full); an opponent whose record reads nil at the start while really
    holding 40: full +20) and `p3bs_pair_hop` (41 entries in the window incl. the pair's under 40 newer ones all kept + 23
    older = 64; 5 in the window + the newest 32 older; 70 in the window -> the newest 64), red on the old code first.

**Restricted accounts get a fixed starter pet at "Your First Pet".** 16.12 closed every roulette for an account PolicyService
restricts from paid random items, so the tutorial's step 4 (`spin`, CompleteOn "Rolled") could not be finished there. Now:
- The pet: `Config.Tutorial.RestrictedStarterPet = "pebble_pup"` (Pebble Pup): a Common of the Cloud Roulette, the machine
  the step points at, the first Common of the catalog and an Economy pet (a small token bonus), which suits the next
  chapter (the Pet Garden makes money). Not random: the same pet for every such account.
- `TutorialService` (`restrictedStarter`, read by the "Rolled" check that the 2 Hz poll and every nudge run): only when
  `GemService.PolicyState(player)` is "Restricted". "Allowed" spins as before (nothing changes); "Checking" (unknown) waits:
  nothing is granted and the step stays until the answer comes (GemService's own retries, or a refused spin's re-ask).
- Once per save: the grant is the save's Trove ask `TutorialStarter` (`DataService.MarkTrove` with the grant record
  `{ Pets = { pebble_pup = 1 } }`) followed, in the same non-yielding step, by `PetService.GrantPet(player, id, { Count = 1 })`
  (the Store's pet path: discovered, auto-equipped as the first pet, no spin counted, Rolled not fired). The ask and the
  pet ride one save; the Trove merge (union + the twin rule, built for the Sky Trove) keeps ONE pet in the store when two
  servers both grant. A save that already holds the ask (the step again, a rejoin, a later server) completes the step with
  nothing granted. A save not readable yet (loading, provisional) waits. A full stack of that pet marks the ask with no pet.
  No new saved field (Trove existed); `ResetFields` (the dev reset) wipes Trove with the Tutorial, so a developer replay
  can get it again.
- Nothing a client sends reaches it: the TutorialEvent remote never completes a "Rolled" step, and the grant is decided
  from the server's policy answer and the save alone.
- The client: no new UI. The step ends as a spin's would without the egg: the toast "Nimbus hatched a Pebble Pup just for
  you: your very first pet buddy!", the pet joins the team and follows, and the next TutorialState ("Pick a Buddy") is sent.
  The gift step's 50 tokens are still paid to everyone (unchanged; they stay in the balance).
- A nested nudge (GrantPet's team change fires TeamsChanged, which settles the tutorial again from inside the grant) is kept
  from completing the step twice by a busy flag on the track.
- Tests: `tut_starter_restricted` (red first): the config pet is a Cloud Common; a restricted account on the step gets
  exactly one Pebble Pup (no spin counted, discovered, in the team, one toast, the next step sent, the ask saved); the step
  again, and after a leave and rejoin: no second pet, the step completes; an allowed account gets nothing whatever
  TutorialEvent it sends and its real spin completes the step (no ask written); an unknown policy waits, then the
  "Restricted" answer grants once. `tut_starter_two_servers`: server A grants while the store fails, server B (read the
  store before A's save) grants and saves, A's orphan retry lands: the store holds one Pebble Pup and the ask.
