# Robux Store, daily gifts and the Sky Trove (design)

Date: 2026-11-04. Judge: Fable 5.1 over four lens designs, revised against the Opus builder's read. Briefs: the shop roadmap
(`2026-10-31-shop-roadmap.md`), the code map, the research brief, Gemini's notes. The contract a builder plans from. Prices and reward sizes are STARTING PROPOSALS (*): the balance gate (10) and the owner's answers (13) may change the
numbers, never the rules around them.

## 1. Intent and why

The owner (roadmap) wants a shop that looks "really good ... colorful and shiny" so players "want to really buy ... for robux": passes,
starter and pro packs, later skins, pet equipment, a mount pass, paid XP/Tokens/Cash, "Pets stats boosts". The build brief adds a
lobby chest paying "a lot of money" for joining the group, liking the game and joining Discord, a daily streak and play-time gifts at
10/20/30/60/90/120/180 minutes. Nothing tracks time, streaks or purchases yet; this build lays the money path once.

## 2. Goals, non-goals, anti-goals

Goals: a colourful, shiny Store with a clear hero; Starter, Pro, VIP, x2 Cash, x2 Pet XP, XP potions, Tokens/Cash/Gems packs; a
7-day streak with a weekly rhythm; per-day play-time gifts; a lobby chest with one verified ask; every grant server-side, idempotent,
surviving failed saves and server hops; ALL TARGETS MET with every paid multiplier on; all of it visible in Studio before any id exists.

Non-goals (later waves): house skins, pet equipment, Pet Mount, Auto-roll (paid random items), stat boosts (Q16),
Server Luck, subscriptions, a Sale state, a cosmetic system, Index listing of exclusive pets.

Anti-goals: anything announced in the screen centre or auto-opened on join; fake urgency (timers, "only N left", "BEST VALUE"); a Discord
word anywhere; a reward the client decides; a pack that skips the first day; a Robux purchase eaten by a bug; a new column-0 local in
MenuController, or more than the budgeted `P7` in DataService.

## 3. Constraints (hard facts; sources in the code map and the research brief)

- **C1** `ProcessReceipt` is set once (GemService:994); Roblox retries until PurchaseGranted; `GemReceipts` (trimmed to 100) cannot prove ownership
- **C2** Version 2 never changes; additive TOP-LEVEL fields, `keepForeign`, out of `OVERWRITABLE`, one-time grants refused while provisional
- **C3** DataService 160 column-0 locals (budget 158+1), MenuController 152: helper tables/new modules
- **C4** Window id `Shop` = the Cloud Shop, depended on by the tutorial (`ShopOpened`), PetService, StormAltar, PetsController, the pill
- **C5** Left column fixed; pill = Shop/Travel/Settings; nothing in the screen centre; phone texts >= 15, buttons >= 44
- **C6** No multiplier hook; `AddCash` also carries refunds (PetCareService:336, TycoonService:1761, DevService:605)
- **C7** `UserOwnsGamePassAsync` and `Player:IsInGroupAsync` are cached per server; a `GroupService:PromptJoinAsync` join (client-only, answers `Enum.GroupMembershipStatus`) clears only the CLIENT's cache; nothing clears a server's
- **C8** Likes have no API; Discord links/handles are prohibited in experiences since 2026-02-23; fixed packs are not paid random items
- **C9** Blender-only art; no asset ids in code: `TextureIds`/`AudioIds`/`MeshIds` keys only
- **C10** The sim targets (sim_tycoon.py 201-214; section 10 lists them) have no multiplier knob
- **C11** "Gift", "Chest", "BuyGems" are taken names; `Store`/`Daily`/`Trove`/`Multipliers` are free

## 4. Approaches considered

Cloud Shop tabs (a ~370 px phone side rect, MenuController out of locals) lost to **a new full-size `Store` window** bridged by a
Roulettes tab. Play time per session (restarts on every crash, rewards app-cycling) lost to **per day**, active seconds only. A streak
reset with a paid Streak Saver (what 2026 regulators cite) and a freeze lost to **a step back one day per missed day** (Gemini:
homework rules cost a day, not a week), re-earned, not re-paid (5.2). Chest asks: the group is verifiable: **paid**; a Like has no API and
an honor button pays for a tap on an under-13 game: **a line, no reward**; Discord is prohibited: **no reward, the word never appears**,
a "Community" row replaces it. Per-site multipliers spread "pass or potion, never x4" over five files and double refunds inside `AddCash`
(C6): **one module at the five EARNING sites** (four Cash, one XP). Receipts: **one path**, `ProcessReceipt` -> `StoreCatalog.ProductById`
-> `StoreService.ApplyGrant`; `smoke_p2_gems` stays green.

## 5. The design

### 5.1 The Store (shop lens)

Window id **`Store`**, controller `StoreController` (ScreenGui `NimbusStore`, DisplayOrder 19, IgnoreGuiInset), sized and opened like the
Pets window (`NeonKit.BigRect(K)`, a copy of PetsController's `H.rect`; closes the other windows, hides touch controls, fires
`MenuController.WindowOpened("Store")`); `Theme.Category.Store = "Gold"`; refused `InMatch`. Entry points: the pill's `PillButton_Shop` ->
`StoreController.Open()` (TopBarController edit); MenuController's `shop` key stays for PetService, StormAltar and PetsController; the
last tab **Roulettes** closes the Store and calls `MenuController.Open("Shop")`; the Cloud Shop's Gems tab loses its pack cards (section
12) for one **Get Gems** button -> `StoreController.Open({ Tab = "Currency" })`; `OpenPanel("Store", args)` is read by StoreController. The
tutorial step `shop` keeps `ShopOpened` from the Cloud Shop; its text drops "The Shop button works too!"; the file-local `HOOK_FOR`
(TutorialController 178) loses `ShopOpened`; `WINDOW_EVENTS` (176) keeps `Shop`, never `Store`. No HUD spawn button.

Tabs: Packs, Passes, Boosts, Currency, Roulettes. Hero: the **Starter Pack while unbought and created**, then **VIP**. An empty tab is
hidden; with nothing created (and no preview) the window shows "The Store opens soon!". Card states: Owned, Claimed!, Active ("58 m
left"), Have-it (an XP potion while x2 Pet XP is owned or the potion bank is full: dimmed, "You already have x2 Pet XP forever!"/"Your
potion is full!"), Preview. Prices: `GetProductInfo` once per session in the background, one retry after 10 s, "..." meanwhile, Buy never
blocked; Robux glyph `\u{E002}` with "R$" fallback. Every Buy goes through `StoreRequest("Buy", key)`; the client never prompts.

**Studio preview**: StoreService writes the attribute `StorePreview = true` (`Config.Attr`)
when `RunService:IsStudio()` or `DevService.IsAllowed(player)` (optional dep; may yield once: task.spawn on join). With it every item
renders, Id 0 included (art key or glyph), its Buy reads PREVIEW, disabled, prompting nothing; the server still refuses `Buy` on Id 0.
Without it Id 0 hides as before. The Trove follows the flag (5.3); the Daily window needs none (no ids; the pet cell shows a glyph until
its art exists).

`Config.Store.Items` (Id 0 = hidden outside preview; `Robux` = the suggested Creator Hub price for the owner and the sims, never shown):

| Key | Kind | Tab | Robux* | Grants (exactly) |
|---|---|---|---|---|
| Starter | Product, Once, Hero | Packs | 99 | `Pets={storm_tabby={Count=1,Level=5}}, Cash=1000, Boost={XpPotion=3600}` |
| Pro | Product, Once | Packs | 799 | `Pets={crown_phoenix={Count=1,Level=10}}, Tokens=5000, Perks={"ProXp"}` |
| VIP | Pass, Hero after Starter | Passes | 399 | `Perks={"Vip"}` |
| Cash2x/PetXp2x | Pass | Passes | 399/450 | `Perks={"CashX2"}`/`{"XpX2"}` |
| XpPotion1/XpPotion3 | Product | Boosts | 49/99 | `Boost={XpPotion=3600/10800}` |
| Tokens1..3 | Product | Currency | 49/149/399 | 500/2,500/10,000 Tokens (two Storm spins/ten/two Celestial; Storm = 250, Config 399) |
| Cash1..3 | Product | Currency | 49/149/399 | 20 min/1 h/3 h of the median minute-60 income from `sim_tycoon.py --quiet`, rounded |
| Gems 1..4 | Product | Currency | owner | `Config.Gems.Products` by reference; the Bag is the tab's hero, no ribbons |

Cash cards say "Cash resets when you Prestige, so spend it!"; a pack above 3 h of income would skip the first day (Q5).

Perks (`Config.Store.Perks`): `CashX2 = { Cash = 2 }`, `XpX2 = { PetXp = 2 }`, `ProXp = { PetXpPvE = 1.5 }` (read from `Store.Bought.Pro`;
Dungeon and raid XP only, by the `source` argument of `grantXp`; never duels, the Ring or feeding), `Vip = { DailyMult = 2 }` (Cash and
Tokens streak cells only, never Gems, the pet or play tiers: Claude's call, Q9). VIP extras (Claude's call, Q18): gold `[VIP]` prefix and
name through the client's `TextChatService.OnIncomingMessage` (`PrefixText` with a font colour tag; no new system); the name plate IS the
lobby crown billboard (High only, hidden InBattle/InMatch; a new client `VipController` reads `OwnedPasses`). Rule: `Cash = CashX2 ? 2 :
1`; `PetXp = max(XpX2 ? 2 : 1, potion ? 2 : 1) x (ProXp and PvE ? 1.5 : 1)`: pass and potion never multiply each other. Potions stack in
TIME (`max(now, ends) + seconds`, cap 7 days).

Exclusive pets: `PetCatalog` gets an optional `ExclusiveTo = "Store" | "Daily"` and `IsExclusive(id)`. ONE site: the fill of
`byRarity` (671) skips an `ExclusiveTo` pet, so the pools (680), `ListByRarity(r, true)` (712), the odds (777), `buildGroup` (1300-1312,
which ADDS EventOnly pets) and Validate's event loop (1663) never see it; `IsRollable` (871) answers false on it; `Get`/`ById`/`Pets`
still list it; `BattleCatalog.EventPets` reads `EventOnly` only. Validate: `ExclusiveTo` is one of the two strings, never with
`EventOnly`; a "every pet is in a group" census skips `IsExclusive`. So: no roulette, no event-pet list, NO Index group. `crown_phoenix`
("Crown Phoenix", Legendary, Species "Phoenix", gold/white + crown, `ExclusiveTo = "Store"`): outside preview the Pro card hides until
its Id exists (the entry is W0's).

Shine (High only, built on open, torn down on close): hero `UIGradient.Rotation` 0 -> 360 over 8 s, a sheen every 6-9 s, a Buy pulse every
2.5 s, pet cards a turning `CloudUI.PetViewport`. Low: static gradient, the `store_*` render, no tweens. Sounds `StorePop` (card tap),
`StoreBuy` (coin clatter), falling back to `Click`/`Reward`.

### 5.2 Daily gifts: streak and play time (retention lens)

Naming: `Config.Daily`, `DailyService`, `DailyController`, remotes `DailyRequest`/`DailyState`, window id `Daily`, field `Daily`. The Store
has NO Rewards tab (judge's call): a free gift must not require opening the Robux store; the Gifts button is the ONE pip in the HUD;
`DailyState` is the client's only source.

Rules: ready **20 h** after the last claim on the server clock, kept if claimed within **48 h**. `Streak` = kept days, cumulative; a claim
makes it `Streak + 1` and pays cell `((Streak - 1) % 7) + 1` of the NEW value (claim 8 = cell 1 of week 2); `Weeks = max(Weeks,
floor(Streak/7))` (the "Week 3" badge, never drops); no growing multiplier. A miss steps back one day per missed day at the next claim
(`Streak = max(0, Streak - 1 - floor((gap - 48 h)/86400))`); VIP never steps back (pass still Checking with a step-back due: the claim
waits, "Checking your VIP pass, one moment"; Claude's call). CHANGED, re-earned, not re-paid: `Paid` = the highest Streak ever
paid; a claim pays only when the new Streak > Paid, else nothing ("Streak repaired! Day 7 of 7"): day 7 returns only after seven more kept
days, a miss costs one gift per missed day, never the week; a step-back from cell 1 lands on the previous cell 7. Day 7 of the FIRST kept
week (`Pet` false) grants `week_wisp` ("Week Wisp", Epic, Species "Owl", gold/white, `ExclusiveTo = "Daily"`) through
`PetService.GrantPet` (W0; stack room checked BEFORE the claim, `Pet = true` in the same step; CHANGED from the raid path's random-pick
local); later day 7s pay `Else`. Play time: per day on the same rolling clock
(`PlayStart`; a new play-day on the first tick >= 20 h after it; unclaimed tiers are lost, Q17); a 10 s tick counts only when the root
moved > 2 studs since the last sample OR a `Play.ActiveRemotes` remote fired within 180 s (DailyService adds its own `OnServerEvent`
listener to each); cap 10 h; NO tick while provisional (a stand-in's `PlayStart = now` would win the Play group and wipe the stored
seconds). Cash gifts are income-minutes (the Ring/Dungeon chest pattern), floored; `Berries = "Basket"` fills the Berry Basket to
`TycoonCatalog.BasketCap` (Claude's call: no Config count exists).

```lua
Config.Daily = {
  ReadySeconds = 20*3600, KeepSeconds = 48*3600, PipDelaySeconds = 20, FutureClockSlack = 300,
  Days = { {Cash={Minutes=2,Min=400}}, {Tokens=50}, {Gems=10}, {Cash={Minutes=5,Min=1000}}, {Tokens=250}, {Gems=25},
           {Pet="week_wisp", Else={Gems=40}} },   -- * (Else only when the stack is full: 13b.2)
  Play = { DaySeconds = 20*3600, TickSeconds = 10, ActiveWindow = 180, MoveStuds = 2, MaxDaySeconds = 36000,
    ActiveRemotes = { "HomeAction", "PetCare", "BattleRequest", "BattleCommand", "DungeonRequest", "BuyRoulette", "Dash" },
    Tiers = { {Min=10,Cash={Minutes=1,Min=200}}, {Min=20,Tokens=40}, {Min=30,Cash={Minutes=3,Min=600}}, {Min=60,Gems=10},
              {Min=90,Tokens=150}, {Min=120,Berries="Basket"}, {Min=180,Gems=25} } },  -- *
}
```

Sizing*: a full day adds 6-9 income-minutes to a 60-min session (the sim gate decides); a kept week = 35 Gems, far under prestige's 135/h.

### 5.3 The Sky Trove (chest lens)

`Config.Trove`, `TroveService`, `TroveController` (ScreenGui `NimbusTrove`, DisplayOrder 18), field `Trove`, remotes `TroveRequest` /
`TroveState`, mesh keys `prop_trove_*`. It REPLACES the boarded-up Item Shop stall at shop-island local `(-21, -8)` (LobbyBuilder 3666; part
budget moves by 0 or less); `LobbyInfo.Shop.ItemShop` keeps its shape pointing at the Trove. Found by walking: no arrow, tutorial step or
HUD entry. Grant*: **$2,000 Cash + 200 Cloud Tokens** once per account (no Gems: no restricted-account substitute; ~3 income-minutes by
minute 10).

```lua
Config.Trove = { GroupId = 0, PromptRange = 10, Slack = 6, Cooldown = 5,   -- GroupId 0: "Coming soon", no button; in preview (5.1) the row renders, its button reads PREVIEW
  Asks = { {Id="Group", Reward={Cash=2000,Tokens=200}}, {Id="Like"}, {Id="Community"} } }
```

Flow: ProximityPrompt ("Sky Trove"/"Open", 10 studs) -> server checks live player, not InMatch/InBattle, root within 16 studs, 1 s
cooldown -> `OpenPanel("Trove")` + `TroveState`. JOIN: client `pcall(GroupService:PromptJoinAsync(GroupId))`; `Joined`/`AlreadyMember` ->
`TroveRequest("Joined")`; `JoinRequestPending` -> "Your request is waiting for the group. Come back later!" (README: the group must be
open-join); `None`/error -> "Not joined yet. Join from the game page, then come back in a new server." Server: `Player:IsInGroupAsync`
ONCE per server visit, ONLY inside Joined, in pcall, never on join/spawn/open; true -> grant in one step, DONE; false -> `Checked`
("Roblox says not joined yet. Joined for real? Hop to a new server and open the Trove again!"; no button until a rejoin; a second Joined
is refused without a call); error -> `Unavailable` ("Roblox is busy, try again in a bit"), not counted as the visit's check. CHANGED:
no VERIFY, Pending or I JOINED: by C7 a server cannot refresh a false answer.

### 5.4 The money path (money lens)

`shared/StoreCatalog.lua` (pure): `ProductById(id)` over `Config.Store.Items` AND `Config.Gems.Products`, `PassById`, `Item(key)`, `List()`,
`Validate()` (unique ids, whole numbers, caps, pet keys, levels, perks). `server/Services/StoreService.lua`: `Init(deps)`,
`ApplyGrant(player, item, purchaseId) -> ok, granted` (non-yielding, CHECK then WRITE; the ONLY check that answers false is "loaded and not
provisional" (NotProcessedYet, Roblox retries): a PAID receipt never pends for a full stack or potion bank. Substitutes (Z7):
a pet at `MaxPerStack` (99) pays its rarity's `Config.Index.Rewards[r].Tokens` instead (Storm Tabby 300, Crown Phoenix 2,000; toast "Stack
full: +2,000 Tokens instead"); a potion extends past the 7-day cap (the cap only dims the card); `granted` = what was
really given (the toast). WRITE: AddCash/AddTokens/AddGems,
`PetService.GrantPet(player, petId, { Count, Level })` (W0 public wrapping the roll's own add at PetService:760-772 without `Stats.Spins`,
MarkDiscovered, the first-pet auto-equip, `SetPetLevel(max(existing, Level))`), `DataService.AddBoost`, `MarkBought` for Once),
`PromptPurchase(player, key)`, `Owns(player, key)`, `PassState`, `Purchased` signal (once, after the save that lands; in Studio also after a
failed save, as GemService 872-874 grants). Passes: on PlayerAdded per pass with Id > 0 `pcall(UserOwnsGamePassAsync)`, failure
retried 5/15/45/120 s then every 300 s; `PromptGamePassPurchaseFinished(player, id, true)` marks Owned at once; fail closed;
`Config.Store.TrustLedgerAfter = 0` (seconds of failure after which the session trusts `Store.Passes`; 0 = never). GemService edits:
`productById` -> `StoreCatalog.ProductById`, the one-step grant -> `StoreService.ApplyGrant` (absent StoreService: gem products only),
`MarkReceipt(player, id, grant)` with the grant table; nothing else.

`server/Services/Multipliers.lua`: `Init({ StoreService, DataService })`, `Cash(player, amount, source)`, `PetXp(player, xp, source)`,
`State(player)` (passes through `StoreService.Owns`, ProXp through `GetStore(player).Bought.Pro`, the potion through `Store.Boosts`);
attributes `OwnedPasses` (csv), `StoreBought` (csv), `XpBoostEnds` (unix, 0 none), server written. Hook sites (five: four Cash, one XP):
TycoonService:1214 scoop (bank, piles and berries stay base; offline coins are paid at scoop); BattleService:3153 Ring Cash;
DungeonService:1432 and 1778; PetCareService:785, first line of the internal `grantXp` (covers `GrantXp` and the Food Machine). NOT
multiplied: TutorialService:1365, refunds, BattleService:1304's fallback, prestige Gems, Double Rewards.

## 6. Data

New top-level fields (Version 2, additive, `keepForeign`, in `KNOWN_TOP`, NOT in `OVERWRITABLE`, left out while empty; all new DataService
code in a helper table `P7`, declared beside `P6` (734) as the budgeted +1 of C3 and the only new column-0 local; ~0.3 KB):

| Field | Shape | Default | Cross-server merge | Provisional | Dev reset |
|---|---|---|---|---|---|
| `Store` (NEW top) | `{ Bought = {[key]=unix}, Passes = {[key]=unix}, Boosts = {[id]=endsUnix} }` | `{}` | Bought/Passes union; Boosts max per id MINUS the session's own seconds for a receipt the store already holds (twin rule, before the max); `P7.cleanStore` | `MarkBought`/`AddBoost` refused (`MarkReceipt` nil -> NotProcessedYet); `MarkPassSeen` allowed | kept (Robux) |
| `Daily` (NEW top) | `{ Streak, Paid, LastClaimAt, Weeks, Pet, PlayStart, PlaySec, PlayClaimed }` (Unix s clocks, 0 never; PlayClaimed = `{[tier]=true}`, stored as a dense boolean array like TrialCleared: check.mjs forbids bitwise operators) | all zero | the pair (LastClaimAt, Streak) travels together; twin rule: a session claim (`DailyClaims`) less than `ReadySeconds` after the STORED LastClaimAt was paid elsewhere: the stored pair stays and `P7.dropGrant` takes its grant off the deltas; else the higher LastClaimAt wins the pair and the grant stays (a day-old session may undercount Streak by one: accepted); Paid/Weeks max; Pet monotone; the higher PlayStart wins the whole Play group; at equal PlayStart PlaySec +delta, PlayClaimed union, a play claim whose (PlayStart, tier) the store holds drops its grant; a stand-in delta (`opts.StandIn`) never touches the Play group; `P7.cleanDaily` | `Claim`/`ClaimPlay` refused; no tick | wiped |
| `Trove` (NEW top) | `{ [askId] = true }` | `{}` | union; twin rule: an ask the store already holds drops the session's grant from the deltas | refused | wiped |
| cache annotation `ReceiptGrants` (replaces `ReceiptGems`, never stored) | `{[purchaseId] = grant}`; a number still means `{ Gems = n }` | | a receipt the store ALREADY holds: `P7.dropGrant(d, grant)` (Cash/Tokens/Gems/Berries off the deltas, pet counts off `d.Pets` clamped at 0, potion seconds before the max); the same helper serves `DailyClaims` and the Trove | | |

Every claim and its grant are written in ONE non-yielding step and ride one UpdateAsync. API: `MarkReceipt(player, id, grant)` (grant table),
`MarkBought`, `GetStore`, `MarkPassSeen`, `AddBoost(player, id, seconds)`, `GetDaily`, `MutateDaily(player, fn, grant)` (fn edits the live
Daily and returns true to commit; `grant` = `{ Kind = "Day" | "Play", Tier, Cash, Tokens, Gems, Berries, Pets = {[id]=n} }`, stamped `At =
os.time()` and `PlayStart`, kept in the cache annotation `DailyClaims` like `ReceiptGrants`; DailyService adds the currency and calls
`GrantPet` right after, nothing yields between), `GetTrove`, `MarkTrove(player, askId, grant)`. DevService `/reset` wipes `Daily` and
`Trove`, keeps `Store`. ProfileSync: nothing new. Config (lead, W0): `Config.Store` (Items, `Potion = { CapSeconds = 7*86400, WarnSeconds =
300 }`, Perks, TrustLedgerAfter, PriceRetrySeconds), `Config.Daily`, `Config.Trove`; the five remotes; `Config.Attr` + `OwnedPasses`,
`StoreBought`, `XpBoostEnds`, `StorePreview`; the four audio keys; `Theme.Category` Store/Daily = "Gold", Trove = "Green"; `Config.Icons`
keys for the tabs and `Gifts`.

## 7. Server rules and security (continuing ARCHITECTURE_V3 10.4)

- **Z1** Grant from a remote: `StoreRequest` only PROMPTS; grants come from `ProcessReceipt` or a server-decided claim
- **Z2** Replay a receipt (retry, rejoin, two servers): `GemReceipts` key + the `ReceiptGrants` twin rule: one purchase id, one grant
- **Z3** Spoof a pass: the server reads only its own cache from the two engine APIs; attributes are written, never read
- **Z4** Forge a potion end/clock: server `os.time()`; only `ApplyGrant` and DevService write `Store.Boosts`
- **Z5** Double a refund or the tutorial gift: the hook sits at the five earning sites, never inside `AddCash`/`AddPetXp`
- **Z6** A once-pack twice across servers: `Bought` union + the receipt grant subtraction; a bought item is never prompted
- **Z7** A client prompts a bought Once pack; a receipt on a full stack or potion bank: granted again with a warn; the 5.4 substitutes: Robux is never eaten, a paid receipt never pends for a cap
- **Z8** Claim the daily early/twice/on two servers; a future clock: `ReadySeconds` on server time; a second request finds `LastClaimAt = now`; the section 6 merge; `FutureClockSlack` clamps
- **Z9** Farm play time idle, app-cycle, forge ticks; a tier twice/on two servers: server-side movement/remote sampling, 10 h cap, per-day on the server clock; tier flag + grant in one step; the section 6 merge
- **Z10** Trove: forged prompt from afar, in a match, no join, cache poisoned on join: distance + `InMatch`/`InBattle` + cooldown; `IsInGroupAsync` only inside Joined, once per visit; a set ask refuses silently
- **Z11** Trove twice across servers: union + twin rule; a failed save keeps grant and bit for the orphan retry
- **Z12** Junk on the five new remotes; buy in a match or an Id 0 item: type/NaN/whole/whitelist checks, 1 req/s + the burst pattern; `StoreRequest` refused `InMatch` (a late receipt is still granted) and on Id 0, preview or not
- **Z13** A one-time grant from a provisional profile: refused everywhere; `MarkReceipt` nil -> NotProcessedYet, Roblox retries
- **Z14** A purchase lost on a failed save/leave: the grant sits in the live profile, the orphan retry saves it, PurchaseGranted only after a save

A test greps `src/` for `/discord/i` and expects 0.

## 8. Client

**Store** (`NimbusStore`, DisplayOrder 19). Phone 844x390: 820x330 at scale 1, texts >= 15. Title bar 44 ("Store", Title 24; three balance
pills 72x28 right; X 44x44). Tab column x 10, y 52, 92 wide: 5 buttons 92x42 (icon 20 + Label 15). Scroller x 110, y 52, 700x270, gap 8; hero
700x150, card 700x108. Card: Art 120 px square | Name (Title 24) + "Gets you:" one line per grant with the currency glyph (Body 16) | price
pill (Display 20) over Buy (CloudUI.Button Green 150x48). 1080p: 1260x900 x ScreenFactor, title 60, tabs 180x72, scroller 1040, hero
1040x250, card 1040x150, Art 210, Buy 220x60. Copy is literal ("Gets you: 1x Storm Tabby (Lv 5), $1,000 Cash, 1 h x2 Pet XP"), never a ribbon.

**Gifts** (`NimbusDaily`, DisplayOrder 19; Store, Gifts and Pets share 19 and never overlap: each Open fires
`MenuController.WindowOpened(id)`, each closes on any other id, as PetsController does). One round button left of the HUD currency strips:
x = `TopRightLeft - 8 - size`, y = 6 gui px; 44x44 on 844x390, 56x56 at 1080p; hides with the strips (InMatch/InBattle), so it never
meets the pill or the TopBand. Pip: Neon.Red 10 px dot, shown >= 20 s after spawn and never before
the tutorial's first roulette step; a 0.4 s shake when a tier is crossed (not on join); a Neon.Gold radial ring fills toward the next
tier. Window (NeonKit.Card): phone 560x300 under the button, right edge aligned; PC 760x420 design px. Tabs **Daily**/**Play time**.
Daily: "Day 3 of 7 · Week 2"; 7 cells 64x92 (phone)/92x132 (PC): "Day n", glyph or pet, amount; claimed = dim + check, today = pulsing
Gold border; CLAIM! (green 200x48/260x56) or "Next gift in 4h 12m" + "Come back tomorrow to keep your streak!"; a "VIP x2" chip when
owned. Play: "47 min played today · Resets in 5h"; 7 rows "10 min · +$200" with CLAIM/"13 min to go"/a check. Claim: the cell pops,
`Reward`, the right-edge toast. Day 7: Rainbow sweep, confetti inside the window only (skipped on Low), "WEEK DONE! Week Wisp is yours!",
`DailyWeek`. After a step-back, once: "Welcome back! You stepped back 1 day. Keep going!". Countdowns use `ReadyAt - GetServerTimeNow()`.

**Boost chips** (new `BoostBadgeController`, no HudController edit): under the strips, right-aligned at y = `TopRightBottom + 4`: "x2 Cash"
(Neon Green) and "x2 XP · 58m" (Neon Purple), 34x18 text 15 on phone, 46x24 at 1080p; toast on potion start and at 5 min left.

**Sky Trove** (`NimbusTrove`, DisplayOrder 18): docked right (`NeonKit.SideRect`, <= 0.44 W) so the chest stays in view; touch controls stay.
Phone: 352x296 at a 12 px right margin, top = inset + 8; title bar 44 ("SKY TROVE", Title 22, X 36x36); subtitle Body 16 "Help Nimbus grow
and the Trove pays you!"; three rows 66: orb 40, label Body 16, reward chips 15, button 100x44 (JOIN/DONE/PREVIEW; none after a false
check); the Like row "Enjoying it? A thumbs up on our game page helps a lot!" and the Community row have no button; footer 15 "Prizes go
straight to you. Once per player." 1080p: 520x460 x ScreenFactor, rows 88, buttons 150x52, title 32. Claim (High): the lid tweens 18 -> 70
degrees (0.35 s, Back), 18 pooled client-only coins arc into the player, `TroveOpen`, the toast, DONE. Low: lid tween, sound, toast; the
`NC_Detail` bits hidden. No camera move.

## 9. Art list (Blender, keyed session; glyph fallbacks until each key exists)

Renders (512 px PNG, `TextureIds`): `store_starter`, `store_pro`, `store_vip`, `store_x2cash`, `store_x2xp`, `store_potion_1h`,
`store_potion_3h`, `store_gems_1..4`, `store_tokens_1..3`, `store_cash_1..3` (growing piles), `daily_gift_closed`, `daily_gift_open`,
`daily_week_badge`, `trove_card`. Icons (`Config.Icons`): the five tabs, Gifts, VipCrown. Models (`MeshIds`, each with a `_low` twin):
`prop_trove_body`, `prop_trove_lid` (its own tagged model: it tweens), `prop_trove_sign`, `prop_gem_bit` (tokens reuse `token_cloud`); Part
fallback <= 60 parts (9x6x6 studs, lid open 18 degrees, planks and brass, a PointLight and a sparkle emitter in the gap, a "SKY TROVE" lid
plate in Theme fonts). Pets: `week_wisp` (Owl rig), `crown_phoenix` (Phoenix rig + crown), new palettes. Deferred: the VIP mailbox crown,
mount rigs. Audio (original): `StorePop`, `StoreBuy`, `TroveOpen`, `DailyWeek`.

## 10. Balance gate

`tools/sim_tycoon.py` gets `--cash-mult` and `--xp-mult` (floats, default 1; cash-mult scales ONLY the wallet credit at scoop and Ring /
Dungeon Cash; xp-mult scales feed and battle XP), `--daily` (the ladders of 5.2), `--vip` (x2 on the Cash/Tokens cells) and `--grant
CASH@MIN,TOKENS` (the Trove at minute 3 plus four `(3, "Cloud")` entries in `ROLLS`). Pacing targets stay fixed; speed targets get a paid
band `TARGETS_PAID(m)`: villa (25/m, 40), p1 (120/m, 180), evolve_min (40/m, 100), gems_per_hour 135 x m, widened only by the multiplier
itself. `run_checks.sh` gets a "Balance matrix" step (it runs no sim today), every line ALL TARGETS MET: free `--daily --grant 2000@3,200`;
`--daily --vip`; `--cash-mult 2`; `--xp-mult 2`; both; worst `--cash-mult 2 --xp-mult 3 --dungeon 0.1 --daily --grant 2000@3,200`. Knob
order on a failure: ProXp 1.5 -> 1.25 -> a non-XP perk; the daily Cash minutes; the Trove Cash; the Cash packs; LAST the pass multiplier
(x1.5 renames the pass). `tools/sim_battle.lua` takes `xpmult=N` in its `SIM_BATTLE` option string (env only, parsed by `SIM.main`); the
matrix runs `SIM_BATTLE="quick xpmult=2"` and expects no MISS line.

## 11. Tests

Every new `smoke_*.lua` is registered in `tools/smoke.py` (`server_files`/`client_files` + the scenario lists, like the storm line at
363). `tools/smoke_store.lua` (doubles like smoke_p2_gems 104-131): store_catalog (Validate,
Id 0 hidden both sides, a gem pack resolves); store_router (Cash pack, potion, Starter in one save; second call, two at once, rejoin,
unknown id, not-here buyer, provisional then granted after recovery, failed save then granted once, Studio rule with `Purchased` on the
failed save, Once re-receipt granted again, stack at 99 -> Tokens substitute and PurchaseGranted, potion past the cap -> extended);
store_pack_merge (the fixsrv_receipt_merge shape: ONE pet copy, +1000 Cash once, one potion hour, Bought once); store_passes (owned on
join; error, retried, then owned; Finished flips at once; a client attribute ignored); store_mult (scoop/Ring/Dungeon Cash doubled,
gift and refunds not; feed and battle XP doubled; pass + potion = 2; ProXp only on PvE sources; potion extends in time, 7-day cap;
`/reset` keeps Store); store_remote (junk, cooldown, InMatch, hidden item, owned pass, bought Once: no prompt); store_window (the pill
opens Store, the Cloud Shop entries still open Shop, ShopOpened only there, card count = created items, every item under `StorePreview`
with inert PREVIEW buttons, "..." until the price, the five states, no tweens on Low, the phone sizes).
`smoke_p2_gems` and `smoke_fix_server` stay green.

`tools/smoke_daily.lua`: daily_pure, daily_claim (19 h 59 m refused, 20 h day 2, Cash = max(Min, income x minutes)), daily_week (pet once,
Weeks 1, day 8 = cell 1, the 14th pays Else), daily_miss (47 h 59 m kept; 49 h one step, the repair claim pays nothing, Streak back to 7,
20 h later cell 1 pays; 10 days -> 0), daily_provisional (ticks and claims add nothing; a stand-in save keeps the stored Play group),
daily_two_servers (B loaded before A's save: B's claim 1 h after A's pays nothing and keeps A's pair, 21 h after it pays; a play tier on
both at one PlayStart: once), daily_future_clock, daily_rejoin (PlaySec survives; claim 10 twice -> once), daily_idle (<= 180 s added),
daily_playday (zeroed after 20 h), daily_remote (junk, rate, InMatch, PassId 0 -> x1, mocked VIP -> x2 on Cash/Tokens cells only, no
step back, the claim waits while the pass is Checking with a step-back due), daily_quiet_join (no Notify on load; pip after 20 s),
daily_exclusive (week_wisp in no pool, not in `ListByRarity(r, true)`, no Index group, not in `BattleCatalog.EventPets()`, `Get` works).
`tools/smoke_trove.lua` (W0 mock doubles: `Player.IsInGroupAsync` beside `IsInGroup` 5236, `GroupService.PromptJoinAsync`, a closed
`Enum.GroupMembershipStatus` None/Joined/JoinRequestPending/AlreadyMember, default `MarketplaceService` pass functions): build (stall gone, shapes, prompt attributes, part count, world-text census), group_once (exact grant once;
`IsInGroupAsync` 0 calls before Joined, 1 per visit), stale_once (the double answers false then true: a second Joined on the same server
makes NO call and is refused, a rejoin grants; the mock never caches, so the test pins the call count), provisional, two_servers,
no_discord (grep 0, no button on the Community row), exploits (far, match, battle, junk, spam), client (both sizes, docked right, Low
shows no bits, GroupId 0 "Coming soon", PREVIEW under the flag). Gate: `check.mjs` and the sim matrix.

## 12. Build order

W0 (lead; shared files): Config, PetCatalog (`ExclusiveTo`, the two entries, `IsExclusive`, Validate), `PetService.GrantPet` (the one
pet-grant path both W2 waves call), `StoreCatalog.lua`, Theme, contract.json groups, `NeonKit.BigRect`, robloxmock doubles, sim knobs,
Main.server.lua wiring of the three services as optional, Main.client.lua names (OPTIONAL).

W1 (side by side, no shared files): **W1-data** DataService `P7`, DevService, the data scenarios (`fixsrv_receipt_merge` extended,
store_pack_merge, daily_two_servers, trove two_servers). **W1-lobby** LobbyBuilder Trove model, TroveService, TroveController, smoke_trove
(server scenarios green at the W2 gate). **W1-store-ui** StoreController, TopBarController, MenuController (delete the Gems-page helpers
2605-2660 AND the pack cards: `buildPack` 2822, the loop 2912, the price refresh 2964; `Gems.Prices`/`askPrice` with them once no other
user remains; add Get Gems), TutorialSteps, TutorialController, store_window. **W1-daily-ui** DailyController, BoostBadgeController,
VipController.

W2 (after W1-data; side by side): **W2-money** GemService generalisation, StoreService, Multipliers, the five call sites, smoke_store
server scenarios. **W2-daily** DailyService, smoke_daily.

W3 (gate): every smoke, check.mjs, the `run_checks.sh` matrix step, README ("Selling Gems" becomes "The Store: the owner's setup"),
ARCHITECTURE_V3 (the Z list, the 9.1 rows), BUILD_STATE. Art and ids: the keyed session, any time after W0.

## 13. Open questions for the owner (Claude's pick first; each changes what gets built)

1. The pill opens the new Store, or the Cloud Shop with a Store button. **Pick: the Store.**
2. Gem packs move to the Store's Currency tab; the Gems tab keeps a Get Gems button. **Pick: yes.**
3. Starter pet = Storm Tabby (Rare) level 5; Pro pet = a NEW exclusive Crown Phoenix. **Pick: as written.**
4. Pro perk = x1.5 Pet XP in Dungeons and raids forever. **Pick: yes.**
5. Cash packs although Cash resets on Prestige, at 20 min/1 h/3 h of income. **Pick: keep.**
6. A miss steps the streak back one day, never resets; VIP never steps back. **Pick: yes.**
7. Day 7 = a NEW streak-only pet (Week Wisp), later weeks 40 Gems; or Gems only. **Pick: the pet.**
8. Play time counts ACTIVE minutes only, or idle too (Gemini). **Pick: active only.**
9. VIP's daily reward = x2 Cash/Tokens on the same CLAIM, no VIP chest. **Pick: yes.**
10. Gifts = its own HUD button and small window, not a Store tab. **Pick: own button.**
11. Like: a plain line, or an honor button paying $500 + 50 Tokens. **Pick: the line.**
12. The Trove pays Cash + Tokens only (no Gems). **Pick: yes.**
13. Trove spot = the boarded-up Item Shop stall, or the fountain boardwalk. **Pick: the stall.**
14. Pass outage: fail closed with retries (`TrustLedgerAfter 0`) or trust the "seen owned" ledger after 120 s. **Pick: 0.**
15. Pet Mount and Auto-roll deferred. **Pick: defer.**
16. Pet stat boosts (the owner's list) as a paid line now. **Pick: no** (the roadmap's cautions: paid power in a children's game; the sim
and battle targets have no knob for it; XP is sold, strength is earned).
17. Play-time gifts per rolling 20 h play-day, unclaimed tiers LOST at the reset, or kept. **Pick: lost** (kept tiers make the window a
bank and the pip would nag for days; the rolling day already survives crashes and dinners).
18. VIP extras: gold `[VIP]` chat prefix and name colour through TextChatService; name plate = the lobby crown billboard. **Pick: yes.**
19. Studio preview: in Studio and for the dev role every Id 0 item and the GroupId 0 Trove render with PREVIEW buttons. **Pick: yes.**

Deviations from the owner's words: Discord is neither linked nor rewarded and a "get verified on Discord" step is dropped (C8; the
Community row replaces it); the chest's THREE asks became ONE paid ask, the group (Like has no API, Discord cannot appear); "a lot of
money" is gone by minute 30; the 120/180 min tiers are smaller than the 10-60 ones; no starter countdown or HUD shop button on spawn;
stat boosts (Q16), mounts, auto-roll, skins and equipment wait. Changed by the blockers: exclusive pets leave `byRarity` at the fill
(5.1); week_wisp through `PetService.GrantPet` in W0 (5.2, 12); re-earned, not re-paid (`Paid`, 5.2); no Trove VERIFY (5.3); the daily
twin rule keys on claim time against the stored `LastClaimAt`, play claims on (PlayStart, tier) (6); no play tick while provisional
(5.2); a paid receipt never pends for a full stack or bank (5.4, Z7).

### 13b. Gemini's check of the pitch (2026-11-04 03:40, web Pro) and what it changed

Gemini read the twelve cards and answered with nine points. Four were wrong or already covered and are NOT taken: the Roulettes tab
"hops to a 3D shop" (the Cloud Shop is a window opened by the same pill; the hop is a window switch, and the Cloud Shop's Get Gems
button is the way back, relabelled **Robux Store**); the 20 h rolling clock "drifts into bedtime" (ready = claim + 20 h is always
4 h BEFORE the same time next day, so a daily player never drifts; only an ever-earlier player could, and the 48 h keep covers it);
pass + potion "misread as x4" (5.1's Have-it state already dims the potion card with "You already have x2 Pet XP forever!");
the Crown Phoenix "looks like a hack" outside the Index (an Index silhouette row with a Shop Exclusive tag that counts toward no
completion is a good later idea; parked in section 14, not built now). Five points hold and OVERRIDE the earlier text where they differ:

1. **Cash packs (5.1, Q5): Claude's pick becomes NO Cash packs now** (Tokens, Gems and potions only). Gemini: a kid buys 3 h of Cash,
   Prestiges five minutes later, loses it, the parent reports the game. If the owner picks Cash packs anyway (Q5 = keep), the Prestige
   confirm must name the Cash lost and the card keeps its line; `Config.Store.Items` keeps the three Cash entries with `Id = 0` and
   `Enabled = false` so the data is ready either way.
2. **Day 7 every kept week = another `week_wisp` (5.2, Q7)**, never "later weeks 40 Gems" (an anticlimax). Duplicate copies fuse
   into Golden / Rainbow like any pet (the existing fusion path by `StatRarity or Rarity`), so no new art. `Config.Daily.Days[7] =
   { Pet = "week_wisp" }` with `Else` only when the stack is full (`MaxPerStack`): then 40 Gems. The `Paid` rule (re-earned, never
   re-paid) is unchanged.
3. **Amounts are numbers on the client, never "minutes of income" (5.2, 8).** `DailyState` carries each cell's and tier's RESOLVED
   amount (the server computes `max(Min, income x Minutes)` from the player's current income at state time and again at the claim;
   the claim pays the claim-time value). Copy: "Gets you: $1,450". The pitch's "2 min of income" wording is for the owner only.
4. **The play clock shows its paused state (5.2, 8).** When no activity was seen for `ActiveWindow` (180 s) the Gifts button's ring dims
   and the Play tab's header reads "Paused: move around to keep counting!" (Body 15, Neon.Gold). `DailyState.PlayActive = bool`, sent
   on each change (not per tick). Never a flashing banner, nothing in the screen centre.
5. **Trove copy (5.3):** the false answer reads "Roblox says you're not in the group yet. Joined for real? Rejoin the game and open the
   Trove again!" (no "hop to a new server"). The Community ROW is cut (wasted space for a kid with no button); the footer line becomes
   "Community links are on our game page. Prizes go straight to you. Once per player." `Config.Trove.Asks` = Group and Like only; the
   no_discord grep stays. The panel is two rows (Group with JOIN / DONE; the Like line) + footer: phone 352x236, 1080p 520x380.

## 14. Left to the builder

Exact gradients and icons, the sheen timing, the coin arc, the chat colour tag, the crown billboard size,
the Trove Part-build details, the portrait-phone Gifts button, the `P7` helper layout, the rounded Cash pack numbers from the sim, and
which `source` strings count as PvE for ProXp (read from the Dungeon/raid callers of `GrantXp`).
