# Window redo: Daily gifts, Play time, Training Place, Fusion Machine and one pet picker

Date: 2026-11-06. Branch `gui-redo` (worktree `.worktrees/gui-redo`, cut from `bug-batch-6` 77ca29f = `shop` a0fa4a4 + bug fixes).
Status: the owner approved all five pitch cards, three with notes. Pitch page: https://claude.ai/artifact/XxMVKJpU1pp1b6VNMCcYqS
(decisions read back into `Projects Main/Nimbus/.superpowers/gui-pitch/DECISIONS.md`). The mock-ups are code:
`Projects Main/Nimbus/.superpowers/gui-pitch/page.html` (functions `pickerC`, `dailyA`, `playB`, `trainA`, `trainC`, `fuseA`;
every frame is drawn in design px at 844x390 and 1920x1080, so the builder can read exact positions there). Card notes and the
real game data the mock-ups use: `.superpowers/gui-pitch/NOTES.md`. Every stage runs on Opus 5.5 (Fable is out of credits; the
owner's choice).

## 1. Intent and why

The owner, about today's windows: Daily "looks like shit", Play time "this too", Training Place "looks like shit and not
comfortable to pick a pet, make it bigger and much more effective and comfortable", Fusion "same with the fusion gui... it's even
worse". Today they are small docked panels (Daily 560x300 on a phone, Training a 600 px dock with an 84 px pet list, Fusion a grid
of 112x162 tiles beside a crowded preview), and Training and Fusion each have their own cramped pet list.

This build redraws the four windows from the approved mock-ups, gives Training and Fusion one shared full-screen pet picker, and
carries three rule changes the owner asked for in his notes:

1. **Daily (owner's note):** "on each new day a player cannot collect a reward before being 10 minutes minimum in the game."
2. **Training (owner's note):** "its a problem if i train multiple pets at the same time so also add the 'add a pet' slots from C."
3. **Fusion (owner's note):** "Add an option to choose the abilities from each pet, for example Normal attack Fire (ability's name),
   Special Storm (ability's name)." This also answers the parked forms question "hybrid picks" (BUILD_STATE 2026-11-02): yes.

## 2. Goals, non-goals, anti-goals

Goals
- The four windows look like the approved mock-ups on a landscape phone (844x390) and on PC (1920x1080), and scale between them.
- Picking a pet is one big, searchable, sortable sheet, the same in Training and Fusion.
- Several pets in training are visible and manageable at once (the mats row).
- The daily streak gift waits for 10 minutes of play each new day, decided on the server.
- In Mix the player picks which parent gives the hybrid's normal attack and which gives its special. Old hybrids stay exactly as they are.

Non-goals
- No reward, price, timer, odds or balance number changes (Config.Daily amounts, TrainCost / TrainSeconds, FusionCost all stay).
- No change to how training, upgrading, the streak's step-backs (except the hold in 5.3), the play-time tiers or the Trove work.
- No new 3D models, no uploads, no new sounds. Art that does not exist yet keeps its glyph fallback.
- The move choice cannot be changed after fusing. No re-roll, no "respec".
- The Pets window, the Food Machine, the Garden picker and the Evolve moment keep their current look (they are not in the pitch).
- No merge into `shop` / `main`, no Studio or Rojo work in the build stages (see the Studio-only list, section 10).

Anti-goals (a failure even if it works)
- A phone window with text under 14 px, a tap target under 44 px, or anything under Roblox's top bar.
- A client that decides anything: every claim, unlock, train, stop and fusion stays a server decision; the client only asks.
- The 10-minute rule costing a player a streak day they would have kept (see the hold, 5.3).
- An old hybrid that fights, looks or evolves differently after this build.
- Two pet pickers again (one module, two callers).

## 3. Constraints (from the code)

- Windows use `NeonKit.BigRect` like the Pets window and the Store: `RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1, Y1 }`,
  `MARGIN 12`, `PHONE_W 900`, `SHORT 560`, `PC_MIN_H 600`, `PC_MAX_W 0.76`. At 844x390 that gives an 820x330 box at y 59 (under the
  58 px top bar), scale 1, "Phone" mode. At 1920x1080 the box is at most 0.76 x 1920 = 1459 px wide, "PC" mode at the screen factor.
  Between the two the layout flows from the design box (box px / scale); the mock-ups are its two ends, not fixed sizes.
- Readability (`Theme.Readability`): PC design text >= 18 px (14.4 px at the 0.8 MinFactor floor); phone text >= 15 px at scale 1;
  targets >= 44 px. All text through Theme roles; plain Lua 5.1 syntax; glyphs as UTF-8 byte escapes (the source stays ASCII).
- One window at a time: each window fires `MenuController.WindowOpened(id)` on open and closes on any other id; Esc / gamepad B /
  the red X close it; entering a match closes it. A window that reaches over the menu tiles calls
  `MenuController.SetColumnCovered`; on a phone (or touch-only) a window hides Roblox's stick and jump through
  `MenuController.SetTouchHidden(owner, true/false)` (PetsController `H.syncTouch` is the pattern).
- Pet looks in UI use `CloudUI.PetViewport` with cached Low clones built under a per-frame time budget (FusionController and
  CareController do this today: `BUILD_BUDGET 0.004` s). Pet data comes from `UI/PetBits` and `State` (the ProfileSync snapshot).
- `DailyService` is one non-yielding step per claim (`DataService.MutateDaily(player, fn, grant, now)`); the Daily merge rules in
  `DataService` (P7.applyDaily) took three review rounds. This build adds **no new Daily save field**.
- Hybrid records (`profile.Hybrids[uid]`) are cleaned by `DataService.cleanHybrid` and `PetKeys.CleanHybrid`; both keep up to 8
  extra scalar fields (strings <= 64 chars). `main`'s `cleanHybrid` has the same extras rule (checked), so a new short string field
  survives a save by an older server during a rollout.
- Lua's 200-local limit: `DataService` sits at 160 column-0 locals, `MenuController` at 164 (`tools/count_locals.py`,
  `node tools/check.mjs` warns at 160). New client code goes in new modules, not into those two.
- Tests: targeted `py -3.12 tools/smoke.py --quick --only <scenarios>` while building; the whole suite only in the gate step;
  `node tools/check.mjs` stays at 0 errors.

## 4. What the owner decided

| Card | Choice | Owner's note |
|---|---|---|
| `picker` (shared by Training + Fusion) | **C.** One full-screen pet picker sheet: big cards (look, name, level, evolution stars, rarity), search, sort, filters; it opens by itself when no pet is picked; in Training the ‹ › arrows step to the next pet without opening it. Training context: pets in training first (with timer), then the team, then the rest. Fusion context: copies (x5), Ready (3 copies) first, hybrids hidden for Upgrade. | none |
| `daily` (7-day streak) | **A.** Big glossy tiles in a row, today raised and glowing gold, Day 7 double-wide (Week Wisp), one big CLAIM under it. Keep "Day 3 of 7 · Week 2", VIP x2 chip, claimed ticks, "Next gift in ..." / "Come back tomorrow to keep your streak!", the repair claim, the week-done banner. | "on each new day a player cannot collect a reward before being 10 minutes minimum in the game" |
| `play` (play-time gifts) | **B.** Gift boxes, each with its own countdown, and Claim All (Pet Simulator 99 Free Gifts style). Keep the paused state ("Paused: move around to keep counting!"), "47 min played today · Resets in 5h", 7 gifts at 10 / 20 / 30 / 60 / 90 / 120 / 180 min. | none (Gemini's pick; Claude had A) |
| `train` (Training Place) | **A.** Big pet on the left, four skill cards (Attack Speed, Physique, Ability, Defense) with rank bar, numbers, cost, time and TRAIN; a pet in training turns its card purple with timer and STOP. | "its a problem if i train multiple pets at the same time so also add the 'add a pet' slots from C" |
| `fusion` (Fusion Machine) | **A.** Slots, an arrow, the result big and glowing, the cost and one FUSE; tapping a slot opens the shared picker; Upgrade and Mix tabs. | "Add an option to choose the abilities from each pet for example 'Normal attack Fire (ability's name), Special Storm (ability's name)'" |

## 5. The design

### 5.1 Rules every window keeps

| Window | ScreenGui (DisplayOrder) | WindowOpened id | BigRect W1 x Y1 (1080p) | Phone box |
|---|---|---|---|---|
| Daily / Play time | `NimbusDaily` (19, unchanged) | "Daily" (unchanged) | 1180 x 720 | 820 x 330, header 50, body 280 |
| Training Place | `NimbusTrain` (23, new; Care's order) | "Train" | 1440 x 840 | same |
| Fusion Machine | existing (22) | existing | 1440 x 880 (the mock's 1520 is over PC_MAX_W) | same |
| Pet picker sheet | `NimbusPetPicker` (24, new) | none: it is part of the window that opened it | 1440 x 920 | same |

- Window chrome as in the mock-ups: a coloured header (Daily gold, Training red-orange `ACCENTS.Train`, Fusion violet) with title or
  tabs, chips, and the red X (44 px phone, 56 px PC); a navy body. Build it from `NeonKit` (Card, Button, Pill, Icon) and Theme.
- Each window centres in its BigRect (phones: the full width under the top bar). The Daily window no longer hangs under the Gifts
  button; the Gifts button, its pip and its ring stay where they are.
- Opening: a 0.2-0.25 s scale/fade in (Back Out), one tween per window root (no per-child loops). Buttons: hover 1.04, press 0.95,
  disabled = desaturated (NeonKit.Button already does this).
- While open on a phone (or a touch-only device): stick and jump hidden through `SetTouchHidden`; the menu column stepped aside
  through `SetColumnCovered` when the box covers it. This holds for the Gifts window too (it fills a phone like the others), so
  on a touch device the play clock pauses while it is open: every "Paused" text there says so ("Paused: close this and move
  around!", see 5.3 and 5.4). On PC the keyboard still moves the character under an open window, so PC keeps "move around".
- Window-local hints (a refusal the client can explain without the server, such as a locked mat) show inside the window that
  caused them: a hint line at the bottom of its body (`HintLine`, 3 s, the window's own ScreenGui), never
  `MenuController.Hint` (that draws in `NimbusMenu`, DisplayOrder 20, under these windows). Server toasts stay
  `NotifyController`'s (DisplayOrder 30, above every window).
- Portrait screens (BigRect `portrait = true`) are not in the mock-ups but must keep working, as today's windows do: the rows wrap
  (day tiles and gift boxes 4 per row, the mats row on top and the pet above the skills in one column, Fusion's slots above the
  result), every rule above still holds.
- Art: no new images. Icons use `NeonKit.Icon` ids with their glyph fallbacks ("Gifts", "Cash", "Tokens", "Gems"); pets use
  `CloudUI.PetViewport`. The Blender renders that already exist but are not uploaded (`blender/textures/store/daily_gift_closed.png`,
  `daily_gift_open.png`, `daily_week_wisp.png`) swap in later through `TextureIds` / `Config.Icons` when the keyed session uploads them.

### 5.2 The shared pet picker (one module, two callers)

**Module:** `src/client/UI/PetPicker.lua` (new). TrainController and FusionController are its only callers. It owns the sheet,
the cards, search, sort and filters; it reads `State` / `PetBits` / `PetKeys` and never sends a remote.

```
PetPicker.Open(spec) -> true | false        spec = {
    Context  = "Train" | "Upgrade" | "Mix",
    Title    = "Pick a pet to train" | "Pick a pet to upgrade" | "Pick the Body pet" | "Pick the Style pet",
    Selected = key | nil,                   -- outlined gold
    Blocked  = { [key] = "In Body" } | nil, -- dimmed with that word, not pickable
    OnPick   = function(key),               -- called once; the sheet closes first
    OnClose  = function(picked: boolean) | nil }
PetPicker.Close()                           -- closes without a pick (the opener's Close calls it too)
PetPicker.IsOpen() -> boolean
PetPicker.Entries(context) -> { entry... }  -- pure over State: { Key, Def, Name, Level, Stage, Rarity, RarityOrder, Copies,
                                            --   Team (in the active preset), Job = { Stat, Ends } | nil, Ready (Upgrade), Hybrid }
PetPicker.Sorted(context, entries, sortId, filterId, query) -> entries   -- pure; tests and the ‹ › arrows use it
PetPicker.Sorts[context], PetPicker.Filters[context]                       -- the ids and labels below
```

The sheet is a second window over its opener (the opener stays open underneath). It does not fire `WindowOpened`. Esc / B / X
close the sheet first; a second press closes the window. Entering a match closes both.

**Contexts** (who is listed, what a card shows):

| | Train | Upgrade | Mix |
|---|---|---|---|
| Listed | every owned key (hybrids too) | regular keys that can still go up a finish (no hybrids, no Rainbow) | regular keys (no hybrids) |
| Corner badge | gold star when in the team | "x5" copies; green "x3+" when Ready | "x2" copies |
| Extra row | purple "Training 3:10" chip, live countdown | none | none |
| Dimmed | never | fewer than 3 copies (still pickable: the window then says what is missing) | none |
| Blocked (not pickable) | none | a pet in training, or whose next-finish key is in training ("Training"; the server refuses both) | a pet in training ("Training"); the other slot's species, any finish ("In Body" / "In Style") |
| Default sort | "Training first": in training (soonest done first), then team (slot order), then the rest (rarity high to low, then level) | "Ready first": copies >= 3 first, then copies, then rarity, then name | "Rarity": high to low, then level |
| Other sorts | Level, Rarity, Name | Rarity, Level, Name | Level, Name, Team first |
| Filters | All, Team, Training, Rare and up, Epic and up (phone shows the first three) | All, Ready, Team | All, Team, Rare and up |

- Ready = copies >= `TycoonCatalog.Fusion.Copies` (3). Copies = `PetKeys.Count(snapshot, key)` (all copies; the Fusion window's
  notes still say which team / Garden copies are taken off first, from the server's Preview).
- Search: a TextBox ("Search pets"), case-insensitive plain substring of the display name (`string.find(..., 1, true)`). No
  results: "No pets match." and a Clear button. No pets at all: "No pets yet! Spin a roulette in the Shop to hatch one."
- The sort button cycles its context's sorts ("Sort: Ready first ▾"); the choice and the filter are kept per context for the session.
- **Cards:** the pet's look (PetViewport), name (fit with the existing fallback: the last word), "Lv 34" with one gold star per
  evolution stage, rarity as the card's frame colour (`Config.Rarities` colours) everywhere and as a word under the name where the
  card has room (PC). Phone card 124 x 100 (art 56), PC card 180 x 226; the grid fills the width (6 per row on the phone, 7 at
  1080p) and scrolls vertically. Only cards in view hold a viewport; clones are cached per key and built under the per-frame budget.
- **Layout:** phone body (280 tall): search 220 x 44, sort 170 x 44, filter chips 44 tall in one row, the grid from y 58.
  PC: search 460 x 60, sort 280 x 60, chips 50 tall, grid from y 100. See `pickerC` in the mock-up page. The mock's PC sheet is
  1640 wide; the real box is at most 1440 (BigRect W1, PC_MAX_W), where Train's five chips (760 px with gaps) do not fit beside
  search + sort (they would end at x 1562). Rule (PC, every context): the chips sit on the first row when they end at least 24 px
  before the body's right edge; otherwise they move to a second row at y 92 (50 tall) and the grid starts at y 166. At 1920x1080
  that puts Train's chips on row 2 and keeps Upgrade's and Mix's three chips on row 1. Nothing in the top rows may overlap
  another control or the window's X.
- **Opens by itself** when no pet is picked: see each window (5.5, 5.6). Nothing opens by itself when the context has no pet.

### 5.3 Daily gifts (card A) and the 10-minute rule

**Layout** (`dailyA`): header tabs "Daily" / "Play time". Body: "Day 3 of 7 · Week 2" on the left; chips "Streak: 9" and "VIP x2"
(VIP only) on the right. A row of seven glossy tiles, each in its `DAY_COLORS` colour (Day n, the reward art, the resolved amount);
Day 7 is twice as wide and shows the Week Wisp (PetViewport); claimed days dimmed with a tick; today raised 8 px, Neon gold, its
glow pulsing. Under the row: "Week Wisp in N more days" with a 7-segment bar (N = 7 - Cell; Cell 7 = "Week Wisp today!"). Then
one big CLAIM (phone 230 x 64 at the right; PC 360 x 88 centred) and the keep line.
Phone: tiles 92 x 122 (Day 7 180), 8 px gaps, from y 48; PC: tiles 128 x 260 (Day 7 264), 16 px gaps; text sizes as in `dailyA`.

Everything today's window does stays, with today's texts: the Repair look of today's tile and "Repair streak (no gift)" (the button
widens), "Next gift in 4h 12m" / "Streak repair in 4h 12m" while not ready, "Come back tomorrow to keep your streak!", the stale
payload's "Getting your gifts ready...", the week-done Rainbow Sweep + confetti + "WEEK DONE! Week Wisp is yours!", the StepBack
hint, the pop and "Reward" sound on a newly claimed tile, the Loading state.

**The 10-minute rule (server, DailyService).**

- New knob `Config.Daily.UnlockSeconds = 600`: the counted play seconds of the current play-day a streak claim needs. `0` turns
  the rule off (today's behaviour): no lock, no `Unlock.Left`, and no hold either (`keepAt = now`, the held seconds are not
  counted), so every step-back is exactly today's.
- **The counter is the existing play-time counter:** `Daily.PlaySec` on the current play-day (`Daily.PlayStart`, 20 h rolling,
  `Config.Daily.Play.DaySeconds`), the same seconds the play-time gifts count. A play-day that is over (`dayOver`) or not started
  (`PlayStart == 0`) counts as 0. Left = `max(0, UnlockSeconds - live PlaySec)`.
- **AFK:** the counter's own rule: a 10 s tick counts only when the root moved more than `MoveStuds` (2) since the last sample or
  one of `Play.ActiveRemotes` fired within `ActiveWindow` (180 s); no root, no character or a dead Humanoid counts nothing. Standing
  still shows "Paused: move around to keep counting!". A provisional profile never ticks, so it never unlocks (it cannot claim anyway).
- **Day reset:** the play-day reset (the first tick 20 h after PlayStart) restarts the count. A gift still unclaimed then needs
  10 minutes of the new play-day.
- **Why this counter matches "each new day":** a claim needs >= 600 s of its play-day, so it happens at least 10 minutes after
  that play-day started; the next gift is due `ReadySeconds` (20 h, equal to `DaySeconds`) after the claim, so by then that play-day
  has ended and the next gift's 10 minutes come from a later play-day. Accepted edge: a player who claimed late in a play-day may
  play 10 minutes on the next play-day before the next gift is due; when it is due the claim is instant. That is still 10 minutes of
  play "that day" on the game's rolling clock. Saves whose last claim came before this rule settle after one claim.
- **Every streak claim waits:** the paid claim, the Week Wisp claim, the first claim ever, a VIP's claim, and the **repair claim**
  (pays nothing but moves the streak and its 20 h clock: letting it skip the wait would let a player join, repair and leave). One
  rule, one countdown. The play-time tiers and the Sky Trove are not affected.
- **VIP:** waits like everyone (the rule is about being in the game, not the pass). VIP keeps x2 on Cash / Tokens and never steps back.
- **Server order in `Claim`:** loaded -> not ready ("Next gift in ..." / "Streak repair in ...", unchanged) -> **locked**: refused,
  nothing written, toast "Play 6 more min to unlock today's gift!" (a repair: "Play 6 more min to repair your streak!"; minutes =
  ceil(left / 60)) -> VIP "Checking" -> the step-back (with the hold below) -> commit and pay as today.
- **The hold (Claude's call; protects the streak):** without it a player who comes back at 47 h 55 m would claim at 48 h 05 m and
  lose a day the rule made him wait for. So the step-back gap is measured at `keepAt` instead of `now`. Two sources say when
  the player started playing toward this claim:
  1. `PlayStart` of the live play-day (`PlayStart > 0`, not `dayOver`). It is stored and merged across servers, so it also covers a
     hop in the middle of the 10 minutes.
  2. **This session's held seconds** (review fix: a play-day can reset while the player is still playing toward the unlock, which
     moves `PlayStart` past the deadline). In memory, per player: `holds[player] = { Last = last, Sec = n }`. Each **counting**
     tick (`on == true`) that finds a streak claim due (`last > 0`, `now >= last + ReadySeconds`) and still locked (the live
     `PlaySec < UnlockSeconds` before this tick adds its seconds), with `UnlockSeconds > 0`, adds `TickSeconds` to `Sec`. `Last`
     is the `last` the seconds were counted for: a changed stamp (a claim, a rebase, another server's claim merged in) starts
     `Sec` over at 0; leaving the server drops it. No save field.
  `from = min(PlayStart if the play-day is live, now - holds.Sec if Sec > 0 and Last == last)` (nil when neither applies);
  `keepAt = min(now, max(from, last + ReadySeconds))` when `from` exists, else `now`.
  `stepBack = 1 + floor((keepAt - last - KeepSeconds) / 86400)` when `keepAt - last > KeepSeconds`.
  In words: if you started playing before the deadline, you keep the streak for the rest of that play-day, and the minutes of
  play this session spent waiting for the unlock never count as time away, even across a play-day reset. Source 2 can never
  pay more than today's rule: it only counts ticks after the gift was due, while it was locked and while the player was moving,
  so `now - Sec` is never earlier than the moment a player of today's rule could have claimed in this session; time spent
  standing still, and time after the unlock, still count as away. `last` is the session's Z8 stamp (`lastClaimOf`) as today.
  The tick computes `last` before its `MutateDaily` step (never inside it: `lastClaimOf` may write the Z8 first sight itself).
- **`State` uses the same `keepAt`** for `missed`, `Repair`, `Cell` and `Today`, so the window never promises what the claim will
  not do. One helper computes it for both (`keepOf(player, d, last, now) -> keepAt, source`). **`StaleAt`** (same guards as
  today: not loading, not VIP, a claim exists, streak > 0): with no hold (`from` nil or `max(from, due) >= now`) today's rule on
  `now`; held by source 1 (`from` = the live `PlayStart`), the view can only change when that play-day ends:
  `StaleAt = PlayStart + DaySeconds`; held by source 2, today's rule evaluated on `keepAt` and shifted by `Sec`
  (`StaleAt = rule(keepAt) + Sec`: the moment `now - Sec` would pass the next boundary if the player stood still from now on;
  while he keeps playing toward the unlock, `Sec` grows as fast as `now`, so that moment never comes early). The tick already
  sends a payload when a play-day starts or resets.
- **Payload:** new `Unlock = { Need = UnlockSeconds, Left = seconds }` (Left 0 = unlocked; Need 0 = rule off).
- **Tick:** `tickPlayer` also sends a payload when the live `PlaySec` crosses `UnlockSeconds` (before < Need <= after), next to the
  tier-crossing check, so CLAIM appears on time.
- **Two servers / a hop:** nothing new to merge. `PlaySec` at one PlayStart adds up across servers (P7.applyDaily's Play group), so
  6 minutes on server A plus 4 on server B unlock the gift after the hop.

**The window while locked** (ready, `Unlock.Left > 0`): the CLAIM button is grey and disabled, two lines: "Unlocks after 10 min
of play" / "6 min to go". The second line, in this order of priority:
1. the live play-day ends before the unlock can come (`Play.DayEnds - now < Left`, the play-day started): "Day resets in 4 min"
   (minutes = ceil((DayEnds - now) / 60)); after the reset the server's payload restarts the count at "10 min to go";
2. `Play.Active == false`: "Paused: move around!" on PC, "Paused: close this and move!" on a touch device (the stick is hidden
   while the window is open, 5.1);
3. else "6 min to go".
Phone 230 x 64 holds both lines at 15 px. The minutes count down on the client while `Play.Active` is true, from the payload's
`ServerNow`, and hold at "1 min to go" until the server's payload says `Left = 0`: the client never shows CLAIM on its own clock.
A repair reads the same way. A payload with no `Unlock` (an older server) is unlocked. The Gifts pip shows only when a claim is
unlocked or a play tier is ready.

### 5.4 Play time gifts (card B) and Claim All

**Layout** (`playB`): header line "47 min played today · Resets in 5h" (phone: "47 min today · Resets in 5h"), or the gold
"Paused: move around to keep counting!" while `Play.Active == false` (a touch device: "Paused: close this and move around!",
5.1); CLAIM ALL (n) at the top right (phone 166 x 44, PC 252 x 60).
Seven gift boxes, each its `TIER_COLORS` colour: "10 min" on top, the gift art (tinted "Gifts" icon; bobbing when ready), the
resolved reward ("+$720", "+40 Tokens", "Berry Basket" / "Full Basket" by the existing fit fallback), and a slot: CLAIM (green,
pulsing box), a clock and its own countdown, or a tick (claimed, dimmed). Phone: 7 boxes 104 x 204 in one row (x step 116); PC:
boxes 260 x 250, four on top and three under, centred.

- Countdown per box: time to its minute = tier minutes x 60 - live seconds; "13:00" (mm:ss) under an hour, "2h 13m" from an hour.
  It ticks only while `Play.Active`, extrapolated from the payload's `Play.Seconds` and `ServerNow`, and never reaches "0:00" on its
  own: it holds at "0:01" / "Almost!" until the server's payload marks the tier Ready (the tick sends on every crossing today).
- CLAIM ALL shows the ready count; greyed out at 0 (the layout stays still).
- **Server:** new action `DailyRequest("ClaimPlayAll")` (no second argument) and `DailyService.ClaimPlayAll(player) -> ok,
  { Tiers = { tier... }, Grants = { grant... } } | reason`. It claims every Ready tier in tier order through the same path as
  `ClaimPlay` (each tier its own `MutateDaily` flag + grant, paid right after; nothing yields), quiet, then ONE toast and ONE
  `Send`. Toast: one tier = today's "+$2,160 Cash! 30 min played"; several = "+$2,160 Cash, +10 Gems: 2 gifts!", or "3 gifts
  claimed!" when the joined text would pass 60 characters. None ready: "No gifts ready yet!". Same guards as `ClaimPlay`: loaded,
  `dayOver` refused ("That play day is over!"), InMatch refused, one request per second for this action. Two servers: each tier's
  (PlayStart, tier) merge rule pays once, as today. `ClaimPlay(tier)` stays (the single box CLAIM).

### 5.5 Training Place (card A + the mats row from C)

**Module:** `src/client/Controllers/TrainController.lua` (new) owns the Training Place window. `CareController` keeps Feed,
Garden and Evolve; its `Open("Train", args)` forwards to `TrainController.Open(args)` and `CareController.Mode()` /
`IsOpen()` report the Training window while it is up, so `OpenPanel("Train")`, the TrainPrompt and the Pets window's Train button
(with `args.ReturnTo`) keep working unchanged. **No server change** for training: `PetCare("Train", key, stat)` and
`PetCare("TrainStop", key)` are unchanged (the server still picks the first free mat).

**One window at a time (review fix): the Training window keeps every wire the Care window has today**, through CareController,
so none of the other controllers change:
- `CareController.Close()` always calls `TrainController.Close()` first (before its own "nothing open" early return), and
  CareController's `H.dropReturn()` also calls `TrainController.DropReturn()`. So ArenaController, DungeonController,
  ObbyController and RaidGateController, which close other windows through `CareController.Close()`, close Training too, and
  CareController's own hooks (MenuController.WindowOpened, Index / Fusion / Arena / Dungeon / Obby Opened, InMatch) close it.
- `CareController.Opened:Fire("Train")` when the Training window opens and `CareController.Closed:Fire()` when it closes
  (TrainController fires them through `CareController.NotifyTrain(open)`), so the five controllers that hook
  `CareController.Opened` (Arena, Dungeon, RaidGate, Obby, Trove) close themselves exactly as today.
- TrainController does **not** fire `MenuController.WindowOpened` (its id would close nothing new, and CareController's own
  WindowOpened hook would close the window that fired it). On open it closes the others the way `CareController.H.closeOthers`
  does today: `MenuController.Close()` (the menu windows, the Pets window, the Store and the Index), `IndexController.Close()`,
  `FusionController.Close()`, and CareController's own Feed / Garden window (`CareController.CloseOwn()`, which never forwards);
  plus `DailyController.Close()` (the Gifts window, DisplayOrder 19, would otherwise stay open under it; the rebuilt Fusion
  window does the same). CareController's `Open("Feed" | "Garden")` calls `TrainController.Close()` first.
- `args.ReturnTo` works as in the Care window today: closing Training (X, Esc, B) reopens the Pets window on that pet, unless
  `DropReturn` ran (another window, a match or a battle took over).
- **Layers:** `NimbusTrain` has DisplayOrder 23. TrainController owns its TRAIN / STOP confirm **inside `NimbusTrain`** (a frame
  above the window's ZIndex range), so it can never draw under the window; `NimbusCare`'s confirm stays for Evolve. The picker
  sheet (`NimbusPetPicker`, 24) is never open together with the confirm (the confirm closes the sheet first).
- Its hints (the locked mat, "Pick a pet first") use its own `HintLine` (5.1).

**Layout, PC** (body 764 under a 76 px header): header "Training Place" (dumbbell icon) + chip "Training spots: 1 / 3 in use" + X.
1. **Mats row** (top, 132 tall, 5 mats ~268 wide). 
2. **Left column** (420 wide): the big pet card (rarity frame, chip "EPIC", element chip "Frost"), name 42 px, "Lv 34 / 100 ★",
   ‹ (76) "Change pet" (220) › (76), the hint "Training pets rest at home until they're done."
3. **Right:** four skill cards 2 x 2 (~466 x 292 each): icon, name, "Rank 4 / 10", a 10-segment rank bar, "Now: +16% attack
   speed", "Rank 5: +20%" (green), cost "$26,250" (green; red when short), time "5 min", TRAIN 220 x 72.

**Layout, phone** (body 280 under a 50 px header; header chip "2 / 3 spots"):
1. **Mats row** at y 4: five mats 152 x 52 (8 px gaps): a 44 px pet face and one or two 15 px lines.
2. **Left column** (200 wide, from y 64): pet card 200 x 112, name 18 px, "Lv 34 / 100 ★" 15 px, ‹ (44) "Change" › (44).
3. **Right:** four skill cards 2 x 2, each about 286 x 104: a 20 px top row (name, "4/10"), a 10 px rank bar, an 18 px line
   "+16% → +20% · 5 min", and a 44 px button ("TRAIN $26,250" / "STOP" / "Busy training" / "Spots full" / "MAX").

**The mats row** (the owner's note; maps 1:1 to "Training spots: n / slots"):
- Five mats always (Training Place levels 1..5 open 1..5 mats: `TycoonCatalog.TrainingSlots(home)`; `MAX_TRAIN_SLOTS 5`).
- Mat i shows the job whose `PetGrowth[key].Job.Slot == i`: the pet, its name, "Physique · Rank 5" (PC), a purple timer bar and
  "3:10 left". Tapping it selects that pet (its skill card turns purple with STOP).
- An open mat with no job: the first one holds the **pending** pet (selected, not training, a free mat exists): gold glow, "Pick a
  skill" (PC "Pick a skill below"); the others read "+ Add a pet" (dashed) and open the picker.
- Mats above the open count: locked, "Training Place Lv i" (phone "Lv i"); tapping one gives the hint "Upgrade your Training Place
  to Lv i to open this spot" (add the house name when the house tier caps the station).
- Display only, never sent: a job with no `Slot`, or two jobs on one slot (a two-server merge), takes the next free mat; a job on a
  mat above the open count (a Prestige closed it; running jobs survive) shows on its mat with a small lock badge.
- The chip counts jobs in the growth map (as `refreshTrain` does today) over `TrainingSlots(home)`; no Training Place:
  "No Training Place yet", all mats locked, and the body says "Build the Training Place at home first. Training makes pets tougher
  in battles!" (today's text).

**Behaviour**
- Open with `args.Key`: that pet. Without: the first pet in training (soonest done). No pet in training (and a Training Place and a
  pet exist): **the picker opens by itself** (Train context).
- **No pet selected** (the sheet closed without a pick, X or the first Esc; or the selected pet left the collection): the window
  stays open in its empty state. The big pet card reads "Pick a pet" with a "+" (tapping it opens the sheet); the name line is
  empty and "Change pet" reads "Pick a pet"; ‹ › step from the default Train order's ends (› picks its first entry, ‹ its last);
  the four skill cards are greyed, with the skill name and "Pick a pet first" on a disabled button, no rank numbers, cost or
  time; the mats row and the chip work as usual (a mat with a job still selects its pet). Nothing reads a nil key or keeps the
  last pet's numbers. No pets at all: the body says "No pets yet! Spin a roulette in the Shop to hatch one." (today's text) and the
  picker does not open by itself.
- ‹ › step to the previous / next pet in the picker's default Train order (`PetPicker.Sorted("Train", ..., "Default")`), wrapping,
  without opening the sheet. "Change pet" opens the sheet with the current pet selected. "+ Add a pet" opens it too.
- Skill card states: ready (TRAIN, cost, time); the selected pet trains this skill: purple card, "Rank 5 · 3:10 left", STOP (pink);
  it trains another skill: "Busy training" (grey); all open mats full and this pet is not training: "Spots full"; cash short: TRAIN
  disabled with the cost in red; rank 10: "MAX", no button; InMatch: disabled. Numbers from `BattleCatalog.TrainingSkills`,
  `TycoonCatalog.TrainCost(def, rank + 1)` and `TrainSeconds(rank + 1)`, as today.
- TRAIN and STOP ask first (today's confirm texts from `CareController.askTrain` / `askStop`).
- A 0.5 s refresh while open (timers); a job ending moves its mat back to "+ Add a pet" and the pet back to the list.

### 5.6 Fusion Machine (card A) and the move choice

**Module:** `FusionController` is rebuilt in place; its API stays (`Open(tab, args)`, `Close`, `IsOpen`, `Plan`,
`Select(keyA, keyB)`, `Fuse`, `Opened`, `Closed`) plus `FusionController.SetMoves(attackKey, specialKey)`. The left-hand pet grid
is gone: every pet slot opens the shared picker. The success animation and the machine's output burst stay as they are.

**Upgrade tab** (`fuseA` "up"): the copies as a fanned stack of three cards ("COPIES", the pet, "Uncommon · Flame"), "x5 owned ·
uses 3", the arrow, the result card big and glowing (Golden: gold, sparks; Rainbow: its shimmer), pills ("Uncommon", "x1.5 power" /
"x2.5 power"), the server Preview's note ("1 team copy is taken off first; the new pet takes the slot", or why it is not possible),
then the cost bar (token icon, amount, "You have 12,480 Cloud Tokens", red when short) and FUSE! (pulsing when possible). Tapping
the stack opens the picker (Upgrade). Opening the tab with no pet: **the picker opens by itself**.

**Mix tab** (`fuseA` "mix"): BODY slot, the swap button, STYLE slot, the arrow, the NEW HYBRID card (violet glow, bob, the blended
name, pills: rarity, "Flame + Storm" in the hybrid's element order, finish), the info line "Your hybrid gets its own random look.
Hybrids are one of a kind and can't be fused again." (PC; the phone has no room for it), the cost bar and FUSE!. Tapping a slot
opens the picker (Mix, `Blocked` = the other slot's species). Opening the tab with an empty slot: **the picker opens by itself**
for the first empty slot (Body first); after a pick, if the other slot is still empty, it opens once more for it; closing the sheet
without a pick ends that chain.

**The move choice** (the owner's note):
- Under each parent slot, two chips: the **normal attack** ("⚔ Flare", PC adds the element: "Flare · Flame") and the **special**
  ("★ Leaf Pounce", PC adds the kind: "Leaf Pounce · Pounce"). In each pair exactly one chip is lit (gold border, check); tapping
  the other parent's chip moves that move to it. Phone chips 130 x 44 under 130 x 148 slots; PC chips about 310 x 56.
- The normal attack is the pet's element attack (`BattleCatalog.ElementAttacks[element].Name`: Flame "Flare", Storm "Bolt", ...);
  the special is `def.Special.Name` (with `Specials[Kind]` as its kind word). Names are stage 0's (a new hybrid starts at stage 0).
- Default: both from BODY = today's rule. A player who never taps a chip gets today's hybrid.
- When both parents have the same element, both attack chips are lit and not tappable (the hybrid has one element).
- The choice follows the **pet**, not the slot: the swap button swaps the looks (Body / Style) and the chips move with their pets
  (the letters flip). Picking a new pet for either slot resets the choice to the default (Body gives both).
- The outcome in the owner's format, "Normal attack: Flame (Flare)" and "Special: Pounce (Leaf Pounce)":
  - **PC:** two lines inside the NEW HYBRID card, above its pills (the card is 480 wide; 22 px text).
  - **Phone (review fix):** the 176 px NEW card has no room for them, so they go on ONE line under the slot row, in the place the
    mock gave its info line (x 14, y 222, 792 x 40, 15 px): "Normal attack: Flame (Flare) · Special: Pounce (Leaf Pounce)". If
    the measured text is wider than the line, the kind words drop first ("Normal attack: Flare · Special: Leaf Pounce"), then it
    wraps to a second line inside the same 40 px; it is never cut.
  - Both read the same pure helper (`FusionController.MovesText(bodyKey, styleKey, moves) -> { Attack = { Element, Name },
    Special = { Kind, Name } }`), so the chips, the lines and the record agree.

**Remote and server** (FusionService):
- `Fusion("Mix", bodyKey, styleKey, moves)`: `moves` is a 2-letter string, letter 1 = the parent of the normal attack, letter 2 =
  the parent of the special, `B` = Body, `S` = Style: `"BB" | "BS" | "SB" | "SS"`. `nil` = `"BB"` (today's rule; an old client).
  Anything else: refused with "Pick the moves again" (reply `Ok = false`, `toastOnce`), nothing fused or charged. `Upgrade` ignores it.
- `FusionService.Mix(player, keyA, keyB, moves)` and `Preview(player, "Mix", a, b, moves)` take it; the plan's record carries it.
- The record: `Elements = { attackParent.Element, otherParent.Element }` (deduplicated, so equal elements give one);
  `SpecialFrom = "Style"` when letter 2 is `S`, left out otherwise. Nothing else in the record changes (Body, Style, Name, Rarity,
  Tier, Seed as today).

**Data, battle and evolution** (exact fields in section 6):
- `PetKeys.hybridDef`: `special = shallowCopy(((rec.SpecialFrom == "Style") and style or body).Special)`; `Element = elements[1]`
  and `Elements` in the record's order (already so). The def cache signature adds `tostring(rec.SpecialFrom)`.
- The battle reads only the def: `BattleSim` takes `def.Special` (kind, power, name, colour) and `def.Elements` (`elems[1]` for the
  Element button and its shape, the bench buff `BattleCatalog.BuffOf`, `FormDpsOf`, the attack effects' element). Nothing in the
  battle code changes. A hybrid's unit `petId` is its key, so `FormNameOf(hybridKey, kind, stage)` gives its chosen kind's generic
  form names; `FormOf(kind, stage)` and `ElementFormOf(Elements[1], stage)` give the chosen moves' evolved forms;
  `AttackFxCatalog.Unit` takes the first element and draws the kind's shared look (never a signature pet's).
- Evolution keeps working: `PetCareService.Evolve` reads `PetCatalog.MaxEvolution(def)` by the hybrid's Rarity (unchanged by the
  choice) and stores the stage per key in `PetGrowth[key].Evo`; forms read `FormStageOf(def, stage)` as today.
- Balance: the special and the attack each still come from one of the two parents (today a player already chooses by which pet
  goes in Body); only the pairing is new (e.g. Leaf Pounce with Bolt). Stats, rarity and cost are unchanged; no Config number moves;
  `tools/sim_battle.lua` fields no hybrids (0 matches for "hyb"), so no sim re-run is owed for balance.

## 6. Data and save (exact)

**Daily:** no new field. New Config knob `Config.Daily.UnlockSeconds = 600`. New payload field `DailyState.Unlock = { Need,
Left }`. The Daily merge, encode and clean code is untouched.

**Hybrid record** (`profile.Hybrids[uid]`), after this build:

```
{ Body = petId, Style = petId,
  Elements = { e1, e2? },      -- ORDER MATTERS: e1 = the element of the parent that gives the normal attack (old records: Body's)
  Name, Rarity, Tier, Seed,    -- unchanged
  SpecialFrom = "Style" | nil  -- NEW: the parent that gives the special; nil (left out) = Body = today's rule }
```

- **No migration step.** A missing `SpecialFrom` means Body, and every stored record already has Body's element first (FusionService
  always wrote `{ baseA.Element, baseB.Element }`), so old hybrids read exactly as today. No rewrite, no `Migrations` marker, no
  first-load toast. A record with an empty `Elements` keeps today's fallback `{ body.Element, style.Element }`.
- `DataService.cleanHybrid` and `PetKeys.CleanHybrid`: `SpecialFrom` becomes a known field, kept only when it is exactly
  `"Style"` (anything else is dropped = Body) and excluded from the extras count. `Elements` keeps its order (both cleaners already
  do). The Hybrids merge (`diffReplace` / `applyReplace` by deepEqual) and the server's ProfileSync snapshot (DataService
  `cleanHybrids`) carry it with no other change.
- **The client snapshot too (review fix):** `src/client/State.lua` `cleanHybrids` copies only Body, Style, Elements, Tier, Name,
  Rarity and Seed today, and `State.DefOf` builds every hybrid def from that cleaned record, so without a change the owner's own
  windows (the Pets window's "Special:" line, the form names at stage 1-2, the Training and Fusion cards) would show Body's
  special for a "BS" hybrid while its battles use Style's. `cleanHybrids` keeps `SpecialFrom` when it is exactly `"Style"`
  (else leaves it out), so `State.DefOf(key)` gives the same def as the server's `PetKeys.DefOf(key, profile)`.
- **Rollout:** `main`'s `cleanHybrid` keeps unknown short string fields as extras, so a record written by this build keeps its
  `SpecialFrom` through a save by an older server; an older server's client reads the record without it (Body's special) until it
  updates. Ship with or after `shop` (the Daily itself is not live yet).
- **Other players' view:** `PetService`'s `EquippedHybrids` attribute gains field 6 = the record's `Elements` joined by "+"
  (`"uid=Body/Style/Tier/Rarity/Seed/Storm+Flame"`), so other clients' stand-in defs (PetController's reader already splits any
  number of "/" fields) get the same element order for the aura. The special is not needed there (battle names come from the server).
- `Config.Remotes` comments: `Fusion -- (action, a, b, moves)`; `DailyRequest -- "Claim" / "ClaimPlay" (tier) / "ClaimPlayAll"`.
  `tools/contract.json`: `DailyService.ClaimPlayAll`, the new client modules (`UI/PetPicker`, `Controllers/TrainController`).

## 7. Server rules and security

- `DailyRequest("ClaimPlayAll")`: `isLivePlayer`, no second / third argument (else dropped), its own 1 s gap, InMatch refused with
  the toast, pcall around the call, junk dropped without an answer (Z12), as the other two actions.
- The unlock is decided only on the server, from the stored play-day; the client's countdown is a display.
- `Fusion("Mix", a, b, moves)`: `moves` is checked by type and by membership in the four strings before anything else is read;
  `nil` is today's rule; the rest of the handler (rate limit, cooldown, near the machine, keys, ownership, training lock, the
  equipped rule, the price) is unchanged. The server builds the record; the client's preview record is for display only.
- No new remote. No client-supplied number reaches a reward, a price or a timer.

## 8. Client file map

| File | Change |
|---|---|
| `src/client/UI/PetPicker.lua` | new (5.2) |
| `src/client/Controllers/TrainController.lua` | new (5.5): the Training Place window, its confirm and hint line in `NimbusTrain` |
| `src/client/Controllers/CareController.lua` | Train mode removed; `Open("Train")` forwards; `Mode` / `IsOpen` report it; `Close` and `dropReturn` forward; `Opened` / `Closed` fire for Train (`NotifyTrain`); `CloseOwn` |
| `src/client/Main.client.lua` | boots `TrainController` after `CareController` (optional, like the others) |
| `src/client/State.lua` | `cleanHybrids` keeps `SpecialFrom = "Style"` (6) |
| `src/client/Controllers/DailyController.lua` | Daily page (A), Play page (B), the locked CLAIM, Claim All, BigRect placement |
| `src/client/Controllers/FusionController.lua` | layout A, slots open the picker, the move chips, `SetMoves`, `moves` sent with Mix |
| `src/server/Services/DailyService.lua` | the unlock, the hold, `Unlock` payload, the crossing send, `ClaimPlayAll` |
| `src/server/Services/FusionService.lua` | `moves` argument, record `Elements` order + `SpecialFrom` |
| `src/shared/PetKeys.lua` | `hybridDef` special by `SpecialFrom`, cache sig, `CleanHybrid` |
| `src/server/Services/DataService.lua` | `cleanHybrid` knows `SpecialFrom` (a few lines; mind the 160 locals) |
| `src/server/Services/PetService.lua` | `EquippedHybrids` field 6 |
| `src/client/Controllers/PetController.lua` | reads field 6 into the stand-in record's `Elements` |
| `src/shared/Config.lua` | `Daily.UnlockSeconds`, Remotes comments |
| `tools/sim_tycoon.py` | `--daily`: the streak cell pays at minute 10 (`UnlockSeconds / 60`), not minute 0 |

## 9. Tests and evidence

New scenarios (each red on today's code first):
- `daily_unlock`: ready but locked -> refused with the text, nothing written; standing still adds nothing; moves and an active
  remote count; 600 s unlocks; a payload on the crossing; `Unlock` in the payload; the repair, a VIP and the first claim wait too;
  a play-day reset restarts the count; `UnlockSeconds = 0` gives today's behaviour.
- `daily_unlock_hold`: join at 47 h 55 m, 10 min of play, claim at 48 h 05 m -> kept; join at 49 h -> one step back; a play-day
  started at 30 h, back at 49 h 05 m in the same play-day -> kept; **the play-day ends at 48 h 05 m while the player is mid-unlock
  (a 1 min visit at 28 h 05 m, back at 47 h 58 m, playing without a stop) -> the claim after the new play-day's 10 minutes is
  kept**; the same player who stops moving after the unlock and claims at 50 h -> one step back (the held seconds stop at the
  unlock); a claim or a changed stamp resets the held seconds; `State` (Repair / Cell / Today) agrees with `Claim` in each case;
  `StaleAt` with a live play-day = its end, held by the session's seconds = `rule(keepAt) + Sec`; the payload's `Play.DayEnds`
  lets the window say "Day resets in N min".
- `daily_unlock_hop`: 6 min on server A, 4 on server B after the hop -> unlocked (the Play group merge).
- `daily_claim_all`: three ready tiers -> one request pays each once, one toast, one payload; again -> "No gifts ready yet!";
  junk arguments dropped; the 1 s gap; InMatch; a day that is over; two servers pay each tier once.
- `fusion_moves`: BB / BS / SB / SS give the right record; nil = BB; junk refused with nothing fused or charged; Upgrade ignores
  it; Preview carries it; equal elements give one element.
- `hybrid_moves_def` (pure): `SpecialFrom = "Style"` -> the Style's special; the record's element order -> `Element`; an old record
  -> today's def exactly; junk `SpecialFrom` -> Body; the cache keeps two records apart.
- `hybrid_moves_save`: `SpecialFrom` survives clean / encode / merge / the snapshot; junk dropped; an old record is byte-identical
  after a load and save.
- `client_hybrid_moves_state` (client world): a ProfileSync snapshot with a Body Maple Fox + Style Storm Tabby hybrid with
  `SpecialFrom = "Style"` goes through `State`: `State.Hybrids()[uid].SpecialFrom == "Style"` and
  `State.DefOf(key).Special.Name == "Static Storm"`; junk `SpecialFrom` -> `"Leaf Pounce"`; an old record -> `"Leaf Pounce"`.
- `hybrid_moves_battle`: a Body Maple Fox + Style Storm Tabby hybrid with "SS": `unitInfo.elementAttack.Name == "Bolt"`,
  `special.Name == "Static Storm"`; at stages 1 and 2 `FormOf("Storm", s)`, `ElementFormOf("Storm", s)` and the generic form names;
  `PetCareService.Evolve` on it works; `FormDpsOf` reads the chosen kind and element.
- `pet_attr_hybrid_elements`: field 6 written and read; a 5-field value still reads.
- Client: `picker_ui` (contexts, default orders, sorts, filters, search, blocked, auto-open, ‹ › order, closes with its opener,
  the PC chips row rule: Train's chips on row 2 at 1920x1080, Upgrade's on row 1), `daily_ui_a` (tiles, today, Day 7, the locked
  CLAIM's two lines in their priority order: "Day resets in N min", the paused text per device, "N min to go"; the pip only when
  unlocked; stick and jump hidden while open on touch), `play_ui_b` (boxes, countdowns freeze while paused, never reach 0 alone,
  Claim All count, the touch paused header), `train_ui` (mats per job slot, pending mat, locked mats and their hint in the
  window's own `HintLine`, the n / slots chip, purple card + STOP, Spots full, the empty state after the sheet closes without a
  pick, forwarding from `CareController`: `Close()` closes Training, `Opened` fires "Train", the Pets window and the menu windows
  close on open, `ReturnTo` reopens the Pets window, the confirm draws above the window), `fusion_ui_a` (stack and slots open the
  picker, the move chips, the swap keeps the choice with its pet, the preview's moves, the outcome lines: two lines in the card on
  PC, one line under the slots at 844x390 with the long-name fallback, the `moves` string sent).
- Geometry, every new window and the picker at 844x390 and 1920x1080 through the mock's dump (`tools/dump_gui.lua`): text >= 14 px,
  targets >= 44 px, inside the screen and under the gui inset, nothing overlapping (the picker in its Train, Upgrade and Mix
  contexts; the Fusion outcome line; the Training empty state).

Rewritten for the new rules (never deleted): the claiming scenarios of `smoke_daily.lua` and `smoke_fixr_daily.lua` (they play 10
minutes first, or set the play-day with `setDaily`; `UnlockSeconds = 0` only in the one scenario that pins the old rule),
`smoke_daily_ui.lua`, `smoke_fixr_daily_ui.lua`, the Train parts of `smoke_p4_careui.lua`, the window parts of the Fusion client
tests; `sim_tycoon.py --check` and its `--daily` lines re-run and reported (the streak cash moves to minute 10).

Evidence for the review: `tools/render_gui.py` scenarios `daily`, `daily:locked`, `daily:play`, `train`, `train:mats`,
`fusion:upgrade`, `fusion:mix`, `picker:train`, `picker:upgrade`, each rendered at `--size 844x390` and `--size 1920x1080`.
Gate step: the whole `smoke.py --quick`, `--mesh`, `node tools/check.mjs` 0 errors, `sim_tycoon.py --check`.

## 10. Studio only (the mock cannot judge these; for the owner's Studio check)

- Every window and the picker on a landscape phone (device emulator 844x390) and at 1920x1080: the look against the mock-ups,
  text readable, nothing under the top bar, stick and jump hidden while open and back after.
- Pet viewports in the picker: framing of every species (small, flying, wide), how long 30+ cards take to fill, smooth scrolling on
  a phone, dragging the grid without picking a card, the search keyboard covering the sheet.
- Gamepad and keyboard: Esc / B close the sheet first, then the window; moving through the cards with a gamepad.
- Daily: today's glow and pulse, the Week Wisp on Day 7, the locked CLAIM's two lines on a phone, the week-done banner.
- The 10-minute rule live: join, stand still (paused), move, the unlock after 10 minutes of play; a server hop keeps the count;
  the client countdown against the server's 10 s tick (drift, the hold at "1 min to go").
- Play time: the gift boxes' bob, Claim All's toast, countdowns freezing while paused.
- Training: the mats row with 1 to 5 spots, jobs ending while the window is open, several pets training at once, a job on a mat a
  Prestige closed, the STOP confirm, the ‹ › order.
- Fusion: the result glow and sparks, the move chips on a phone, the fusion animation; in a battle, a new hybrid's Element and
  Special buttons showing the chosen names (Flare or Bolt, Leaf Pounce or Static Storm), an evolved hybrid's form names, and other
  players seeing its aura by the chosen element.
- Later, by the keyed session (not this build): uploading `daily_gift_closed` / `daily_gift_open` / `daily_week_wisp` for the boxes
  and tiles.

## 11. Calls Claude made (the owner can overrule them)

1. **The 10 minutes are counted play** (the play-time clock: moving or using the game's actions), not wall time in the server.
   Standing AFK does not unlock the gift. Reason: the owner's goal is presence in the game, and the same counter and the same
   "Paused" line already exist.
2. **The repair claim waits too**, and **VIP waits too** (one rule, one countdown).
3. **The hold:** started playing before the 48 h deadline = the streak is kept for that play-day, even if the 10 minutes finish
   after it; and the minutes this session played while the gift was due but locked never count as time away, even across a
   play-day reset (review fix). Without it the rule would cost streak days.
4. **The rolling play-day is "the day"** (20 h from the first counted tick), not a calendar day; see the accepted edge in 5.3.
5. **Claim All is one server request** that claims each ready tier through the normal path, with one toast.
6. **The moves follow the pet** through the swap button; equal elements make the attack choice a no-op.
7. **The normal attack is the element attack** (the Element button: Flare, Bolt, ...), and choosing it also makes that element the
   hybrid's first element (its bench buff and aura colour), because the game has one "first element" for all of those.
8. **Training moves into its own controller** (`TrainController`), with `CareController` forwarding, to keep the big modules small.
9. Mix's picker blocks the other slot's species and training pets; Upgrade's dims (but allows) pets with fewer than 3 copies.
10. **The Gifts window hides the stick on touch like every big window** (review fix), and its paused texts say "close this and
    move" there, instead of keeping the stick over a window that fills the phone.
11. **The phone shows the Fusion outcome as one line under the slots**, the PC as two lines in the result card (review fix).

Review fixes (2026-11-06, design review of this spec): the client snapshot keeps `SpecialFrom` (6); the hold survives a play-day
reset during the 10 minutes and the locked line says when the day resets (5.3); the Training window's one-window wiring, its own
confirm layer and its empty state (5.5); window-local hints inside the window (5.1); the phone's Fusion outcome line (5.6); the
picker's PC chips row at 1440 px (5.2); the touch paused texts (5.1, 5.3, 5.4).

Code review fixes (2026-11-07, after the build's gate on 91cc9ba):
- 5.5 mats row: the free spots are `TrainingSlots(home)` minus the jobs (the server's count, a job on a closed mat included).
  Only that many open mats with no job are free (the pending pet, "+ Add a pet"); the other open mats with no job read
  "Spot in use" (phone "In use", an hourglass) and their tap says "In use by a pet on a closed spot. Free again when that pet
  is done." on the HintLine, so the row never offers more room than the chip.
- 5.5 skill cards: on the small cards (phone, tight, row) a short Cash TRAIN keeps the price inside the greyed button, in red.
- 5.6: a pick list with nothing in it (no pets; only hybrids or Rainbow pets for Upgrade; no regular pet for Mix) says why
  on the HintLine instead of doing nothing, from the slot / Stack tap and from the auto-open.
- 5.3: the HUD's vitals card hides while the Gifts window is open (`HudController.SetVitalsHidden("Daily", on)`): at 1080p
  the window's bottom edge cut the card in half.
- 5.4 Claim All skips a Ready tier that would pay nothing now (a full Berry Basket, Amount 0): it stays Ready for its own box,
  which reads "Basket is full"; CLAIM ALL's count leaves it out; only that tier Ready: "Your Berry Basket is full!".
- 5.1 Esc: Escape that only ends typing in a TextBox (the sheet's search, the chat) closes nothing in the Training and Fusion
  windows (a focused box, or one let go within 0.1 s). Not InputBegan's gameProcessed: Roblox's menu binds Escape itself, so
  a plain Escape may arrive processed too and the windows would stop closing on Esc.

Gemini was not asked: its API answered 402 (prepayment credits depleted) during this step, and the web fallback was not driven from
inside the workflow. Calls 1-3 are the ones worth a Gemini check before the build starts.

## 12. Left to the builder

- Exact pixel positions between the two mock-up frames, the flow between phone and PC design boxes, fonts per role, colours per
  tile and chip (within the mock-ups and Theme), the open/close tween details.
- The fit fallbacks for long names (pets, specials such as "Wish Upon the Stars") on cards and chips, using the existing
  TextService-measured fallback pattern.
- How `TrainController` shares the confirm dialog with `CareController` (shared helper or its own), and where the shared bits of
  the picker cards live (PetPicker or PetBits).
- The toast wording for Claim All within the 90-character toast limit; the hint texts for locked mats.
- Whether the picker remembers the scroll position per context within a session.
- Splitting the work into stages and tests per stage (the plan), keeping each module under the local-variable limit.

## Skills used and skipped

- Used: `superpowers:brainstorming` (the project copy's "The Written Design" format: intent, goals / non-goals / anti-goals,
  constraints, the owner's decisions, what is left to the builder; its builder check was done by reading the spec as the builder,
  as the skill says when no subagent tool is available), `roblox-dev:roblox-datastores` (no new Daily field, the hybrid field with
  a nil default instead of a migration, the rollout through older servers, the merge left untouched), `roblox-dev:roblox-ui`
  (BigRect scale rule, one tween per root, viewports only in view with cached clones, pressed / disabled states),
  `roblox-dev:roblox-security` (the `moves` and `ClaimPlayAll` argument checks, server-decided unlock, no new remote).
- Skipped: `superpowers:writing-plans` (the next stage, after this spec), `roblox-dev:new-system` (no new client/server system:
  existing remotes and services), `roblox-dev:roblox-performance` (only the viewport budget rule applies, taken from the existing
  windows), `roblox-dev:roblox-testing` (the test list follows the repo's own smoke harness).
