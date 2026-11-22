-- DailyController (client, store 2026-11-04; spec 5.2 / 8 "Gifts" / 13b.3-4; window redo gui-redo Task 9:
-- docs/superpowers/specs/2026-11-06-window-redo-design.md 5.1 / 5.3, plan docs/superpowers/plans/2026-11-06-window-redo.md):
-- the Gifts button, its pip and ring, and the Gifts window (the Daily page: the 7-day streak, card A; the Play time page).
--
--   DailyController.Init()
--   DailyController.Open(args)    args = { Tab = "Daily" | "Play" } (nil: Daily, or Play when only a play tier is claimable)
--   DailyController.Close()
--   DailyController.IsOpen() -> bool
--   DailyController.State() -> the last DailyState payload | nil
--   DailyController.PipShown() -> bool
--   DailyController.Layout() -> "PC" | "Phone" | "Portrait"   (the open window's layout, or the one it would open in)
--   DailyController.ClaimView(st, now, touch) -> { Mode, Line1, Line2, Repair }   pure: what the claim slot says for the
--       payload `st` at server time `now` (`touch`: a touch-only device). Mode:
--         "Claim"   (Line1 "Claim!") | "Repair" ("Repair streak (no gift)")
--         "Locked"  ready, but the 10-minute rule still holds it (Unlock.Left > 0 and Unlock.Need > 0): Line1 "Unlocks after
--                   10 min of play" (the minutes of Need), Line2 by priority: "Day resets in N min" when the live play-day
--                   ends before the unlock can come (0 < Play.DayEnds - now < the seconds left); else "Paused: move
--                   around!" (a touch device: "Paused: close this and move!": the stick is hidden while the window is
--                   open) while Play.Active == false; else "N min to go". The seconds left count down from the payload's
--                   ServerNow while Play.Active and hold at "1 min to go" until a payload says Left == 0: the client
--                   never unlocks on its own clock. Repair = true for a locked repair (it keeps the wide repair button).
--         "Wait"    not ready yet: "Next gift in 4h 12m" ("Streak repair in 4h 12m" when that claim only repairs)
--         "Stale"   past StaleAt, and "Loading" (no payload, or a Loading one): "Getting your gifts ready..."
--       A payload with no Unlock (an older server) or Need 0 (the rule off) is unlocked.
--   DailyController.TierCountdown(i, st, now) -> text   pure (gui-redo Task 10): play tier i's own countdown at server time
--       `now`: the seconds to its minute = Min x 60 - live, live = Play.Seconds + (now - ServerNow while Play.Active, else
--       0); "13:00" (m:ss) under an hour, "2h 13m" from an hour; never below "0:01" (the server's payload marks the tier
--       Ready: the client never does on its own clock); "" for a Ready / claimed / missing tier or a Loading payload.
--
-- Data: DailyState (server -> client) is the only source (DailyService builds it; nothing here decides a reward):
--   { Loading = bool (provisional: no CLAIM), Streak, Paid, Weeks, Pet, ReadyAt (unix), KeepUntil (unix), Cell (1..7: the NEXT
--     cell), Repair = bool (the next claim repairs a missed day and pays nothing), StaleAt (unix: the view changes then by
--     itself, the keep deadline or another missed day; 0 = never), Vip = bool, StepBack = n (the last claim's
--     step-back), Unlock = { Need = 600, Left = n } (gui-redo Task 4: the counted play seconds of the live play-day a
--     streak claim still needs), Days = { { Kind = "Cash" | "Tokens" | "Gems" | "Pet", Amount = n | nil, PetId =
--     "week_wisp" | nil, Claimed, Today, Repair = true | nil (today's cell of a repair) } x7 }, Play = { Seconds, DayEnds
--     (unix), Active = bool, Tiers = { { Min, Kind, Amount, PetId, Claimed, Ready } x7 } }, ServerNow (unix) }
--   Amounts are the server's resolved numbers (13b.3). Countdowns use ReadyAt / DayEnds - workspace:GetServerTimeNow().
--   A claim fires DailyRequest("Claim") / DailyRequest("ClaimPlay", tier) / DailyRequest("ClaimPlayAll") (1 s client gap per
--   action); the toast is the server's. The tutorial gate reads TutorialState (Done, or Step >= the index of the "spin" step).
--
-- Screen: ScreenGui "NimbusDaily" (DisplayOrder 19 like the Store and the Pets window: they never overlap, each Open fires
-- MenuController.WindowOpened(id) and each closes on any other id; IgnoreGuiInset = false: the HUD attributes are gui px).
--   * TextButton "GiftsButton": (kit-b U8) a small pink kit B block (the pitch's HUD stage: the pixel gift over "Gift") docked
--     under the HUD's currency strips: the square NimbusHud publishes (GiftLeft / GiftTop / GiftSize: right-aligned with
--     the strips, 8 px x the screen factor under them, 56 px at 1080p x the factor, never under 44); without those
--     attributes (no HUD) x = NimbusHud.TopRightLeft - 8 - size, y = 6 (gui px), 56 px at 1080p (x the screen
--     factor), 44 px on a phone; hidden with the strips (InMatch / InBattle, or no top-right strips) and, with its ring and
--     pip, while any window of K.WINDOWS is open (slop audit 2026-11-12, win 5: H.windowUp; back within K.WINDOW_POLL of the
--     close), and (owner 2026-11-13) while the Gifts window itself is open (back at once on Close) or an NPC talk box
--     is up (NpcController, in K.WINDOWS); re-laid out on the HUD's
--     TopRightLeft / TopRightBottom / GiftLeft / GiftTop / GiftSize signals. Children: the Gifts icon and word, Frame "Pip"
--     (a 10 px Sign red square, kit-b U8: an unlocked
--     claim (ClaimView "Claim" / "Repair") or a ready play tier, >= Config.Daily.PipDelaySeconds after the last
--     CharacterAdded, the tutorial at its spin step or later), a 0.4 s shake when a play tier becomes Ready in a payload
--     that is not the first after a join / Loading one. (U9-4 look review: the bar census) Frame "PlayBar" in the block's
--     lip (attribute Fill = Play.Seconds / the next tier's seconds, Filled, Paused): K.BAR_SEGS blocks with K.BAR_GAP px
--     of lip between them, the first floor(Fill x BAR_SEGS) gold (the gold lip while Play.Active == false, never alpha),
--     the rest the lip's pink: the kit's block bar (it replaced a gradient-swept gold outline round the block). The
--     button and the pip stay where they were before the window redo.
--   * The window: Frame "DailyHolder" (UIScale "Fit") centred in its NeonKit.BigRect box (RECT 820 x 330 at 390 px high ->
--     1180 x 720 at 1080 px; MARGIN 12, PHONE_W 900, SHORT 560, PC_MIN_H 600, PC_MAX_W 0.76: an 820 x 330 box at 12,59 on a
--     844 x 390 phone, "Phone" at scale 1; "PC" at the screen factor; a phone box taller than wide is "Portrait"). The PC
--     layout is computed in the design box (box px / scale) with card A's 1080p numbers as its largest form. Inside:
--     "DailyWindow" (kit-b U9-4, finding 15: the Signboard kit of the Shop; the wood frame round "Stone", the stone body
--     with its lip; UIScale "Pop" for the 0.22 s Back-Out open) > "TitleBar" (the navy header plank with its lip: Tab_Daily
--     "Daily", Tab_Play "Play time" as blocks on their Tab_*Fill frames, stone, the selected one gold; the red CloseButton
--     block: 56 px PC / 44 px phone, its X drawn by NeonKit.CloseMark, header 76 / 50), "Roof" (SignKit.Roof: the awning
--     at a fixed K.ROOF_W, never stretched; PC, and (U9-4 look review) the portrait window at K.ROOF_PHONE_W under clear
--     sky; a portrait window's band holds the gift, GIFTS and the close, its two tabs their own row under it) and "Body" > DailyPage, PlayPage, Fx. While open on a phone (or a touch-only device) Roblox's stick and jump are hidden (MenuController.
--     SetTouchHidden("Daily", on)), the menu tiles step aside (MenuController.SetColumnCovered(windowLeft, "Daily")) and
--     the HUD's vitals card hides (HudController.SetVitalsHidden("Daily", on): the window's edge would cut it on PC).
--   * DailyPage (card A): Header "Day 3 of 7 . Week 2" (the middle dot; a plain Section title, the owner's ruling
--     2026-11-14), StreakChip "Streak: 9 days" (phone "Streak: 9"; hidden at 0) and VipChip "VIP x2" (VIP only) as square
--     tags (stone, VIP gold); Cells > Cell1..7 kit B blocks (NeonKit.Card Skin "Sign", the day's DAY_COLORS on its lip,
--     CELL_LOOK: stone, today gold, claimed the sunk well; Day "Day n" or
--     "TODAY" while today's gift is due, Art (glyph or the Week Wisp's PetViewport), Amount, Dim, Check: a big tick on a
--     claimed tile; attributes Claimed / Today / Pulsing). (Pitch 2 item 09_daily_layout B, "Prize stand") Days 1-6 are
--     one row; Day 7 is the prize card right of it (the Week Wisp on its Plinth, its name on the Amount wood plank, Species
--     "Epic Owl . Storm", and the week's own countdown inside it); today is raised 8 px (same bottom; never the prize card),
--     gold, its ink edge pulsing; a Repair payload's today tile reads "Repair" with the Repair glyph. WispText (in the
--     card) "in N more days" (N = 7 - Cell; "in 1 more day"; Cell 7: "Yours today!") over WispBar (Seg1..7, attribute
--     State = "Claimed" | "Today" | "Open": grass, gold, the well). ClaimButton (the page's one green plank under the day
--     row: PC 400 x 96, phone 230 x 64; portrait the grid's width): "Claim!", or "Repair streak (no gift)" on the wider
--     repair button; locked: the Off block, disabled,
--     its Line1 / Line2 labels say why (ClaimView). Countdown takes its place while waiting ("Next gift in ...", "Getting
--     your gifts ready..."). Keep beside it ("Claim today's gift to keep your streak!" while the claim is due, "Come back
--     tomorrow to keep your streak!" while waiting; not while loading / stale). WeekBanner "WEEK DONE! Week Wisp is yours!"
--     (a gold block) covers the card's species and week lines for 4.5 s. Portrait: the prize card on top (the pet left),
--     Days 1-6 a 3 x 2 grid under it, the Claim the grid's width and the keep line under it, the chips under the header.
--   * PlayPage (card B, gui-redo Task 10, spec 5.4): PlayHeader "47 min played today . Resets in 5h" (phone / portrait "47
--     min today . Resets in 5h"; the minutes are live: Play.Seconds + the time since ServerNow while Active), or in red ink
--     "Paused: move around to keep counting!" while Play.Active == false (a touch-only device: "Paused: close this and
--     move around!", the stick is hidden while the window is open). ClaimAll "Claim all (n)" (the page's one green plank; n = the Ready tiers that
--     pay something now: a full Berry Basket, Amount 0, is left to its own box, which reads "Basket is full"; PC
--     252 x 60, phone 166 x 44 at the top right, portrait centred under the header): DailyRequest("ClaimPlayAll"), greyed
--     out at 0 in the same place. Tiers > Tier1..7 gift boxes (kit B blocks, TIER_COLORS on the lip; attributes State = "Ready" |
--     "Claimed" | "Locked", Pulsing): Time "10 min" on top, Gift (Block: the HUD button's pink gift block with the "Gifts" icon;
--     attribute Bobbing: a Ready box's gift bobs and its border pulses on the 1 s tick), Reward (the resolved amount; on a
--     box narrower inside than WRAP_BELOW it takes two lines: "Berry" / "Basket"; look review 2: a currency on its role's
--     tag, attribute Role, the coin / gem KindIcon before the amount), and one slot: Claim
--     (a stone "Claim" plank: DailyRequest("ClaimPlay", i)), Clock (+ ClockGlyph, a PixelIcon clock, when it fits: TierCountdown, on the 1 s tick) or
--     Check (claimed: a big tick over the Dim). PC: 260 x 250 boxes at 1080p, four on top and three under, both rows
--     centred (the rows slide from PlayCompact to PlayFull with the body); phone: seven 104 x 204 boxes in one row; portrait:
--     four a row, row 2 centred. Fx: the week's 24 Confetti frames (skipped on Low; kit-b U9-4, finding 26: flat bits in the
--     kit's colours by role, K.CONFETTI_COLORS: the prize's gold and the gift's pink with their lips; no rainbow, no sweep).
--   * A grown claimed set pops the cell or box (1.15 -> 1, 0.25 s) with SoundFx "Reward" (once per payload: Claim all
--     pops every box it claimed with one sound); a paid week (Weeks rose with the Streak
--     onto a multiple of 7; a repair claim back onto day 7 leaves Weeks alone and celebrates nothing): the
--     confetti, the banner, SoundFx "DailyWeek"; StepBack > 0: the side hint "Welcome back! You stepped back n day(s).
--     Keep going!" once per claim (MenuController.Hint: it can arrive while the window is closed).
--   * A payload past its StaleAt (re-review 2) no longer says what the claim does: no gold today tile, no claim button,
--     "Getting your gifts ready..." until DailyService's fresh payload (its tick re-sends one at StaleAt).
--   * Closes on X, Esc, gamepad B (bound only while open), InMatch / InBattle, and any other WindowOpened id. A screen
--     change while open lays the open window out again at once (it is built once and re-laid out, never rebuilt).
--   * Texts that would not fit their cell (TextService measures the real font) fall back to a shorter form: a pet's last
--     word ("Week Wisp" -> "Wisp"), "Full Berry Basket" -> "Berry Basket" -> "Full Basket", big numbers as "$1.2M".
-- Art: glyph fallbacks (NeonKit.Icon: "Gifts", "Cash", "Tokens", "Gems"); Config.Icons swaps in the uploaded images later.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles. Glyphs are UTF-8 byte escapes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TextService = game:GetService("TextService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7a) the claimed tick and the tier clock
local SignKit = require(Shared:WaitForChild("SignKit")) -- (kit-b U9-4) the awning over the window
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TutorialSteps = require(Shared:WaitForChild("TutorialSteps"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))
local SoundFx = require(Client:WaitForChild("SoundFx"))
local GraphicsQuality = require(Client:WaitForChild("GraphicsQuality"))

local DailyController = {}

local K = {
	DISPLAY_ORDER = 19,
	GAP = 8, -- the button's gap to the strips
	TOP = 6, -- the button's y (gui px)
	BTN = 56, -- the button at 1080p (x the screen factor) ...
	BTN_MIN = 44, -- ... never below this
	SMALL = 500, -- the smaller screen side at most this = a phone (the button)
	-- (slop audit 2026-11-12, win 5) the button, its ring and its pip step aside while any of these controllers answers
	-- IsOpen() == true: every window that can sit over the button's corner. Each one's IsOpen is false in ordinary play with
	-- no window up (read 2026-11-12). Owner 2026-11-13: also NpcController (an NPC talk box up: IsOpen() -> true, npcId)
	-- and the Gifts window itself (S.Open, asked in H.windowUp: never this list). Never DevController or MainMenuController
	-- (the title screen hides the whole HUD on its own; its Settings / Credits / What's new windows are asked through
	-- MainMenuController.Window() in H.windowUp instead).
	WINDOWS = {
		"MenuController", "PetsController", "ShopController", "StoreController", "TroveController", "IndexController",
		"FusionController", "CareController", "TrainController", "DungeonController", "ObbyController", "RaidGateController",
		"ArenaController", "LossScreen", "NpcController",
		"BattleController", -- (LOOK-ui2) its result card holds the top-right corner a moment (IsOpen: the card is up)
	},
	WINDOW_POLL = 0.25, -- seconds: no shared close signal exists, so a watcher re-lays the button out when that answer changes
	WINDOW_RETRY = 2, -- seconds before a K.WINDOWS module not found yet is looked up again (review round 1)
	PIP = 10,
	BAR_SEGS = 4, -- (U9-4 look review) the PlayBar's blocks in the button's lip ...
	BAR_GAP = 2, -- ... and the px of lip between two
	SHAKE = { 4, -4, 3, -3, 2, -2, 1, 0 }, -- px offsets, one per SHAKE_STEP (0.4 s)
	SHAKE_STEP = 0.05,
	CLAIM_GAP = 1, -- seconds between two sends of one action
	POP = 1.15,
	POP_TIME = 0.25,
	WEEK_SECONDS = 4.5, -- the week banner stays this long
	CONFETTI = 24,
	CONFETTI_TIME = 1.6,
	-- (kit-b U9-4) the Signboard: the wood frame's width round the stone body, the awning's fixed width (the Shop's)
	FRAME = 6,
	ROOF_W = 360,
	-- (U9-4 look review) the portrait window's awning (SignKit.Sizes.RoofPhoneW: look review 2, 240, its right end clear of
	-- the close block), wherever ROOF_CLEAR px of clear screen lie over the window's top (never at 844x390, where the
	-- window starts under Roblox's top bar)
	ROOF_PHONE_W = SignKit.Sizes.RoofPhoneW, ROOF_CLEAR = 26, -- (F0 review) the seated awning: its box 20 + bracket 2 over the top, 4 clear
	-- (U9-4 look review 2) a phone band's close: a CloseBlock px red block in the layout's Close px touch box (CloseTap
	-- under it), its 3 px stroke CLOSE_INSET - 3 px inside the band's right end
	CLOSE_INSET = 7,
	-- the window box: NeonKit.BigRect, the Pets window / Store / Training Place rule (spec 5.1)
	RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1180, Y1 = 720 },
	MARGIN = 12,
	PHONE_W = 900,
	SHORT = 560,
	PC_MIN_H = 600,
	PC_MAX_W = 0.76,
	OPEN_FROM = 0.86, -- the open tween (one per window root: the "Pop" UIScale)
	OPEN_TIME = 0.22,
	BACK_ACTION = "NimbusDailyBack",
	REPAIR_TEXT = "Repair streak (no gift)", -- the claim button of a repair claim (re-review 1)
	FIT_SLACK = 2, -- px a text keeps free in its box (the outline)
	WRAP_BELOW = 96, -- a gift box narrower inside than this gives its reward two lines
	BOB = 5, -- px a ready box's gift bobs up
	-- design px per layout. PC: the box at 1080p has a 1180 x 644 body; the Daily page's window keeps 485 of it (MaxBody,
	-- Pitch 2 09 B) and the Play page's rows slide from PlayCompact (a 485 body, the shortest PC box) to PlayFull (644).
	-- Phone: card A on a 844 x 390 phone (body 820 x 280). Portrait: one column, the days three a row.
	-- (kit-b U9-4) the header as the Shop's: Icon = the gold square's icon px (the square is 4 px more: PC 42, SignKit's
	-- IconSlot), TitleText /
	-- TitleW the window's title ("Gifts", the ribbon) before the tabs; TabY / TabH the tab blocks inside the navy band, a
	-- tab's touch box keeps TapH.
	-- (U9-4 look review: the cramped phone pages) the body's x 0 is the window's outer edge, so a tile or a gift box keeps
	-- >= 3 px of stone round its 3 px outside stroke to the 6 px frame and to the 8 px stone lip, and 4 px between two
	-- tiles' strokes: sides >= 12, gaps >= 10, BoxBottom >= 20; a box's Claim clears the box's lip and its own stroke by
	-- 4 px (LOOK-ui, kitb-look1: CloudUI.SignMetrics is SignKit's 5 px edge / 8 px lip now, was 3 / 5, so BoxPadBottom >= 15,
	-- was 12) and is 8 px narrower than the box's inside
	-- (U9-4 look review 2) today's tile, raised by Raise, keeps >= 4 px of stone between its 3 px stroke and the chips' 2 px
	-- strokes: TilesY - Raise - 3 >= ChipY + ChipH + 2 + 4 (PC Compact 82, the phone 50 with 26 px chips, the portrait 80);
	-- the Play page's Claim all keeps 5 px of stone under the band (AllY 8 on a phone). A box's gift block is the Daily
	-- chip (ChipPx: 72 / 48, its 2 px edge, GiftPx = ChipPx + 4) holding the gift at the art size
	-- (Pitch 2 item 09_daily_layout, option B "Prize stand"; the owner's shot 09: the day row floated in the body's spare
	-- height, ~75 px of nothing over the tiles and ~80 px under the Wisp bar, the Week Wisp ~50 px tall in its double tile)
	-- the Daily page: Days 1-6 one row of TileGap-spaced tiles from Side, the Claim under the row (ClaimW x ClaimH, the
	-- keep line beside it), Day 7 the prize card right of the row (HeroW, from HeroY down to the Claim's foot, ColGap
	-- from the row): the Week Wisp on its plinth as big as the card allows (PetMax), its name on a wood plank, "Epic Owl ·
	-- Storm", "in 4 more days" and its own 7-block bar. The streak / VIP chips end at the row's right end. The tiles take
	-- the height the fixed parts leave (TilesY + AfterTiles + ClaimH + Bottom), so no band of empty stone is left; on PC
	-- the window is only as tall as the page needs (MaxBody, the Play page's CompactBody: H.layout centres it in its
	-- BigRect box). Card insides: HeroPad round them, CardGap between the rows, the plinth PlinthH tall and PlinthOut
	-- wider than the pet each side, the plank PlankH tall and PlankSide in from the card's sides, the bar BarSide in
	PC = {
		Header = 76, HeadPad = 24, TabY = 12, TabH = 52, TabW = { 170, 200 }, TabGap = 10, TabText = 26, Close = 56, CloseY = 10,
		Icon = 38, TitleText = 34, TitleW = 150, TitleGap = 22, TapH = 52,
		Side = 28, HeaderY = 18, HeaderH = 44, HeaderText = 34, ChipY = 20, ChipH = 44, ChipText = 22, ChipPad = 18,
		StreakW = 190, VipW = 120, ChipGap = 14, LongStreak = true,
		TilesY = 82, TileGap = 14, TileW = 128, TileMaxH = 260, TileMinH = 120, Raise = 8, PadTop = 12, PadBottom = 14, DayText = 22,
		AmountText = 30, ChipPx = 72, PetPx = 150, RewardPx = 72,
		AfterTiles = 22, ClaimW = 400, RepairW = 440, ClaimH = 96, ClaimText = 40, RepairText = 32, Line1 = 24, Line2 = 22,
		CountText = 28, KeepText = 22, Bottom = 30, MaxBody = 485,
		HeroW = 320, HeroY = 14, ColGap = 24, HeroPad = 14, CardGap = 6, HeroDayText = 22, PetMax = 260, PlinthH = 10, PlinthOut = 14,
		PlankH = 42, PlankSide = 24, PlankText = 28, SpeciesText = 20, WispText = 22, BannerText = 22, BarH = 22, BarSide = 20, SegGap = 6,
		FullBody = 644, CompactBody = 485,
		-- the Play page (card B at 1080p: body 1180 x 644; the rows slide from PlayCompact to PlayFull like the Daily page)
		PlaySide = 28, PlayY = 18, PlayH = 44, PlayText = 32, PausedText = 26, AllW = 252, AllH = 60, AllY = 12, AllText = 24,
		AllGap = 16, BoxSide = 28, BoxW = 260, BoxMaxH = 250, BoxCols = 4, BoxGap = 28, BoxPadTop = 12, BoxPadBottom = 17,
		TimeText = 24, GiftPx = 76, RewardText = 24, SlotH = 56, TierBtnW = 200, TierBtnText = 24, ClockText = 26,
		BoxMinGap = 6, TagH = 34, TagPad = 8,
		PlayFull = { BoxRowsY = 92, BoxRowGap = 30, BoxBottom = 22 }, PlayCompact = { BoxRowsY = 80, BoxRowGap = 14, BoxBottom = 20 },
	},
	-- (U9-4 look review 2) a phone band (44 px) holds the 36 px icon square, the 36 px tab blocks and the 36 px close block
	-- (CloseBlock; Close is its touch box), each 4 px under the band's top: the Trove's phone header
	PHONE = {
		Header = 50, HeadPad = 10, TabY = 10, TabH = 36, TabW = { 110, 140 }, TabGap = 6, TabText = 17, Close = 44, CloseBlock = 36,
		CloseY = 3, Icon = 32, TitleText = 20, TitleW = 92, TitleGap = 14, TapH = 44,
		Side = 14, HeaderY = 6, HeaderH = 26, HeaderText = 18, ChipY = 6, ChipH = 26, ChipText = 15, ChipPad = 10,
		StreakW = 118, VipW = 84, ChipGap = 8,
		-- (Pitch 2 09 B) the prize stand as on PC: the row and the Claim left, the prize card right
		TilesY = 50, TileGap = 10, TileW = 92, TileMaxH = 150, TileMinH = 80, Raise = 8, PadTop = 6, PadBottom = 8, DayText = 15,
		AmountText = 17, ChipPx = 54, PetPx = 60, RewardPx = 54,
		-- (P2 icons look fin0, minor: Claim's 5 px edge met the tiles' 3 px edge, 0 px of stone) AfterTiles 12: 4 px of stone
		-- (the 4 px come off the tiles, which have the room: 138 -> 134)
		AfterTiles = 12, ClaimW = 230, RepairW = 300, ClaimH = 64, ClaimText = 26, RepairText = 22, Line1 = 15, Line2 = 15,
		CountText = 17, KeepText = 15, Bottom = 20,
		HeroW = 196, HeroY = 6, ColGap = 12, HeroPad = 6, CardGap = 2, HeroDayText = 15, PetMax = 160, PlinthH = 6, PlinthOut = 8,
		PlankH = 26, PlankSide = 12, PlankText = 17, SpeciesText = 15, WispText = 15, BannerText = 15, BarH = 14, BarSide = 10, SegGap = 4,
		-- the Play page (card B on a 844 x 390 phone: body 820 x 280, seven boxes in one row)
		-- (merge kitb-look1) AllY 9: Claim all's 5 px edge (the kit's one plank weight) keeps its 4 px of stone under the band
		PlaySide = 14, PlayY = 8, PlayH = 44, PlayText = 17, PausedText = 15, AllW = 166, AllH = 44, AllY = 9, AllText = 15,
		AllGap = 12, BoxSide = 14, BoxW = 104, BoxMaxH = 198, BoxCols = 7, BoxGap = 12, BoxRowsY = 64, BoxRowGap = 0,
		BoxBottom = 20, BoxPadTop = 6, BoxPadBottom = 15, TimeText = 15, GiftPx = 52, RewardText = 15, SlotH = 44, TierBtnW = 92,
		TierBtnText = 16, ClockText = 16, BoxMinGap = 4, TagH = 24, TagPad = 4,
	},
	PORTRAIT = {
		Header = 50, HeadPad = 10, TabY = 10, TabH = 36, TabW = { 100, 130 }, TabGap = 6, TabText = 17, Close = 44, CloseBlock = 36,
		CloseY = 3, Icon = 32, TitleText = 20, TitleW = 92, TitleGap = 14, TapH = 44,
		-- (U9-4 look review) the band holds the gift, GIFTS and the close; the two tabs get their own row under it, each
		-- half the inside wide: TabRow the row's px over the body (TabRowGap over the TabRowH blocks)
		TabRow = 50, TabRowGap = 6, TabRowH = 40, TabRowSide = 15, TabRowMid = 10,
		Side = 15, HeaderY = 4, HeaderH = 26, HeaderText = 18, ChipY = 34, ChipH = 28, ChipText = 15, ChipPad = 10,
		StreakW = 104, VipW = 84, ChipGap = 8,
		-- (Pitch 2 09 B) the prize card on top (HeroY, the grid's width; the pet left, its words right of it, PetGap
		-- between), the days a 3 x 2 grid under it (HeroGap), the Claim the grid's width under the grid and the keep line
		-- under the Claim. The card takes HeroShare of the room the fixed parts leave (HeroMinH..HeroMaxH), the tiles the
		-- rest. The window is WinH tall where the screen has the room: its top TopClear under the HUD's strips (the awning's
		-- room), TopClearTight where WinMinRoom px are not left that way, Foot px over the screen's foot. HeroY 72: the
		-- card's 3 px edge keeps 4 px of stone under the chips' 2 px edges when Day 7 is today. A short card (360 x 640)
		-- drops its species line, then its label
		-- (look review r0: the keep line touched Claim's shadow and sat on the window's foot) ClaimGap 14 (Claim's 5 px edge
		-- and 5 px shadow, then 4 px of stone) and Bottom 22; the 12 px come off the prize card (HeroMaxH 124: its rows still
		-- fit, the Wisp still over 60 % of it), not off the tiles, which were cut once already
		TileGap = 10, TileW = 112, TileMaxH = 122, TileMinH = 60, Raise = 8, PadTop = 3, PadBottom = 4, DayText = 15,
		AmountText = 15, ChipPx = 54, PetPx = 44, RewardPx = 54,
		RowGap = 10, AfterTiles = 12, ClaimH = 60, ClaimGap = 14, KeepH = 20, KeepText = 15, Bottom = 22, ClaimW = 230, RepairW = 300,
		ClaimText = 26, RepairText = 22, Line1 = 15, Line2 = 15, CountText = 17,
		WinH = 676, WinMinRoom = 600, TopClear = 32, TopClearTight = 6, Foot = 12,
		HeroY = 72, HeroGap = 10, HeroMinH = 80, HeroMaxH = 124, HeroShare = 0.38, HeroPad = 6, PetGap = 10, CardGap = 3,
		HeroDayText = 15, PlinthH = 6, PlankH = 26, PlankSide = 12, PlankText = 17, SpeciesText = 15, WispText = 15, BannerText = 15,
		BarH = 14, SegGap = 4,
		-- the Play page: the header on two lines, CLAIM ALL centred under it, four boxes a row
		PlaySide = 15, PlayY = 4, PlayH = 40, PlayText = 17, PausedText = 15, AllW = 166, AllH = 44, AllY = 48, AllText = 15,
		AllGap = 0, BoxSide = 15, BoxW = 104, BoxMaxH = 204, BoxCols = 4, BoxGap = 10, BoxRowsY = 100, BoxRowGap = 10,
		BoxBottom = 20, BoxPadTop = 4, BoxPadBottom = 15, TimeText = 15, GiftPx = 52, RewardText = 15, SlotH = 44, TierBtnW = 92,
		TierBtnText = 15, ClockText = 15, BoxMinGap = 4, TagH = 24, TagPad = 4,
	},
}
DailyController.K = K

-- the window's words (spec 5.3)
local TEXT = {
	Claim = "Claim!", -- (kit-b U9-4) buttons read in sentence case (the kit's casing rule)
	Getting = "Getting your gifts ready...",
	Keep = "Come back tomorrow to keep your streak!",
	KeepClaim = "Claim today's gift to keep your streak!", -- (Pitch 2 09 B) the line by a claim that is due
	Prize = "DAY 7 PRIZE", -- (Pitch 2 09 B) the prize card's label (TODAY when it is due); look review r0: the mock's capitals
	Week = "WEEK DONE! Week Wisp is yours!",
	Unlock = "Unlocks after %d min of play",
	Resets = "Day resets in %d min",
	PausedPC = "Paused: move around!",
	PausedTouch = "Paused: close this and move!",
	ToGo = "%d min to go",
	-- the Play page (spec 5.4)
	PlayLoading = "Play time gifts",
	PlayPausedPC = { "Paused: move around to keep counting!", "Paused: move around!" },
	PlayPausedTouch = { "Paused: close this and move around!", "Paused: close this and move!" },
	ClaimAll = "Claim all (%d)",
	TierClaim = "Claim",
	ClockIcon = "clock", -- (kit-b U7a) the PixelIcon beside a tier's countdown
}

-- the owner's colourful cells (kept here, not in Theme): one colour per day and per tier. (kit-b U9-4, findings 15 / 26:
-- colour by role) each colour lives on its block's lip, in the kit's own tones (the neon hues they were, flat and softer,
-- the same order), never on the face: the face says the state (CELL_LOOK)
local SIGN = Theme.Sign
local DAY_COLORS = {
	SIGN.Grass, -- green
	SIGN.Sky, -- sky
	SIGN.SkyLip, -- blue
	SIGN.Violet, -- violet
	SIGN.Roof, -- pink
	SIGN.GoldDeep, -- orange
	SIGN.Red, -- red (the Week Wisp)
}
local TIER_COLORS = {
	SIGN.Sky, -- 10 min: sky
	SIGN.Grass, -- green
	SIGN.SkyLip, -- blue
	SIGN.Violet, -- violet
	SIGN.Roof, -- pink
	SIGN.GoldDeep, -- orange
	SIGN.Gold, -- 3 h: gold
}
DailyController.DayColors = DAY_COLORS
DailyController.TierColors = TIER_COLORS
-- (kit-b U9-4) a block's face and its edge per state: today gold, a claimed day / box the sunk well, the rest stone.
-- (U9-4 look review) the edges are solid kit tokens, never faded by alpha: wood on an open day and a locked box (a day or
-- a gift still to come keeps its frame), the Off block's edge on a claimed one, the ink edge of the pitch's selected
-- card on today and a ready box; those two pulse as a 2-frame swap on the 1 s tick (ink <-> the gold lip, no tween)
local CELL_LOOK = {
	Today = { Face = SIGN.Gold, Edge = SIGN.Text, Pulse = true },
	Open = { Face = SIGN.Tile, Edge = SIGN.Wood },
	Ready = { Face = SIGN.Tile, Edge = SIGN.Text, Pulse = true },
	Locked = { Face = SIGN.Tile, Edge = SIGN.Wood },
	Claimed = { Face = SIGN.Well, Edge = SIGN.WellEdge },
}
DailyController.CellLook = CELL_LOOK
K.PULSE_EDGE = SIGN.GoldLip -- the pulse's second frame
-- (kit-b U9-4, finding 26) the week's confetti: the prize's gold and the gift's pink (the Gifts button's block), each with
-- its lip tone, in place of the rainbow
K.CONFETTI_COLORS = { SIGN.Gold, SIGN.Roof, SIGN.GoldLip, SIGN.RoofLip }
-- (U9-4 look review: one pixel size per screen) every pixel icon in the window draws at one of two sizes, one double the
-- other: Glyph (the header gift, the sparkles, the clock, a reward's coin) and Art (a day's reward, the ticks, a box's
-- gift): 3 / 6 px cells on PC (27 / 54 at 1080p), 2 / 4 px on a phone (18 / 36). (look review 2) the kit's one table,
-- SignKit.Sizes.Pixel, which the Trove reads too
K.PIXEL = SignKit.Sizes.Pixel
-- (U9-4 look review) a day's reward art sits on its role's chip, as the HUD's strips colour each currency: cash the
-- grass block, tokens gold, gems navy, the rest stone; Ink = the pixel art's colour on it. (look review 2) the gem is the
-- pitch's pixel gem in sky on the navy chip (the cut gem's gradient facets were the one smooth shape among the pixel art;
-- the Play page's gem is the same icon)
K.ART_CHIP = {
	Cash = { Face = SIGN.Grass, Lip = SIGN.GrassLip, Ink = SIGN.OnGrass },
	Tokens = { Face = SIGN.Gold, Lip = SIGN.GoldLip, Ink = SIGN.Text },
	Gems = { Face = SIGN.Navy, Lip = SIGN.NavyLip, Ink = SIGN.Sky },
	Other = { Face = SIGN.Tile, Lip = SIGN.StoneLip, Ink = SIGN.Text },
}
K.ART_LIP = 4
K.ART_EDGE = 2
-- (Pitch 2 09 B) the prize card's name plank: the wood block (its dark lip and edge) with cream words (5.4:1); the plinth
-- under the pet the sunk well slab in its edge colour
K.PLANK = { Face = SIGN.Wood, Lip = SIGN.WoodDark, Edge = SIGN.WoodDark, Text = SIGN.Tile }
K.PLANK_EDGE, K.PLANK_LIP = 2, 3
-- (U9-4 look review 2) a play gift's reward on its role's tag, the Trove's tag part (a kit B block in a 2 px wood edge on
-- a 3 px lip): cash the grass tag, tokens the gold tag with the coin, gems the navy tag with the gem, each icon at the
-- glyph size before the amount; any other reward (the Berry Basket, a pet) stays a plain line. Text = the words' ink
K.REWARD_TAG = {
	Cash = { Face = SIGN.Grass, Lip = SIGN.GrassLip, Text = SIGN.OnGrass },
	Tokens = { Face = SIGN.Gold, Lip = SIGN.GoldLip, Text = SIGN.Text, Icon = "token", Ink = SIGN.Text },
	Gems = { Face = SIGN.Navy, Lip = SIGN.NavyLip, Text = SIGN.Gold, Icon = "gem", Ink = SIGN.Sky },
}
K.TAG_EDGE, K.TAG_LIP, K.TAG_GAP = 2, 3, 3
-- (U9-4 look review) the next gift to open shows the minutes played toward it as the kit's block bar (SignKit.BlockRow,
-- Count blocks; look review 2: painted as the Wisp bar's SEG_LOOK by H.paintTierBar, filled gold on its lip, empty the
-- lipless well, the deep gold face while the clock is paused) over its countdown; H = the blocks' height, Gap the px
-- between them, MaxW a block's widest
K.TIER_BAR = { Count = 5, PC = { H = 16, Gap = 4, MaxW = 26 }, Phone = { H = 12, Gap = 2, MaxW = 16 } }
-- the Wisp bar's blocks per state, in the kit's block-bar language (SignKit.BlockRow, the pitch's .seg): a filled block
-- has its darker lip (a claimed day grass, the green of the claimed tick; today gold), an open one is the sunk well
-- with no lip; each in a 2 px wood edge
local SEG_LOOK = {
	Claimed = { Face = SIGN.Grass, Lip = SIGN.GrassLip, Edge = SIGN.Wood, Text = SIGN.Text, LipPx = SignKit.Sizes.BlockLip },
	Today = { Face = SIGN.Gold, Lip = SIGN.GoldLip, Edge = SIGN.Wood, Text = SIGN.Text, LipPx = SignKit.Sizes.BlockLip },
	Open = { Face = SIGN.Well, Lip = SIGN.Well, Edge = SIGN.Wood, Text = SIGN.Text, LipPx = 0 },
}
local function paintSeg(seg, state)
	local look = SEG_LOOK[state] or SEG_LOOK.Open
	CloudUI.SignBlock(seg, look, { LipPx = look.LipPx, EdgePx = SignKit.Sizes.BlockEdge })
	seg:SetAttribute("State", state)
end

local DOT = "\194\183"
local CHECK = "check" -- (kit-b U7a) the claimed tick is a PixelIcon

local LocalPlayer = nil
local initialized = false
local U = { Cells = {}, Tiers = {}, Segs = {} } -- the instances
local S = {
	Open = false,
	Tab = "Daily",
	State = nil, -- the last payload
	Last = nil, -- the last non-Loading payload since the last Loading one (the baseline of pops / shakes / the week)
	Tutorial = nil, -- the last TutorialState payload
	SpawnAt = 0, -- time() of the last CharacterAdded
	LastFire = {},
	Mode = nil, -- "PC" | "Phone" | "Portrait" of the laid-out window
	ShakeX = 0,
	ShakeToken = 0,
	StepBackKey = nil,
	BannerUntil = 0,
	Pulse = false,
	BackBound = false,
	Hidden = true,
	WindowUp = false, -- H.windowUp() at the last H.layoutButton (the K.WINDOW_POLL watcher compares against it)
	WindowMods = {}, -- (review round 1) [name] = the K.WINDOWS module once found, or the clock of its next look-up
	TouchOff = false,
	VitalsOff = false, -- the HUD's vitals card is hidden for this window (H.coverColumn)
}
DailyController._S = S -- (review round 1) tests read the state (the K.WINDOWS module cache)
local warned = {}

local function warnOnce(key, err)
	if not warned[key] then
		warned[key] = true
		warn("[DailyController] " .. key .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
end

local function controller(name)
	local inst = script.Parent:FindFirstChild(name)
	local ok, mod = pcall(function()
		return inst and require(inst)
	end)
	return ok and type(mod) == "table" and mod or nil
end

local function now()
	return workspace:GetServerTimeNow()
end

local function label(name, text, role, size, parent, props)
	local l = Theme.Label(text or "", role, { Size = size })
	l.Name = name
	l.TextWrapped = true
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function place(inst, x, y, w, h)
	inst.AnchorPoint = Vector2.new(0, 0)
	inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	inst.Size = UDim2.fromOffset(math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
end

local function viewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and vp.X >= 2 and vp.Y >= 2 then
		return vp
	end
	return Vector2.new(1920, 1080)
end

-- "4h 12m" / "12m 5s"
local function leftText(seconds)
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	if h > 0 then
		return h .. "h " .. m .. "m"
	end
	return m .. "m " .. (s % 60) .. "s"
end

-- "5h" / "40m"
local function resetText(seconds)
	local s = math.max(0, math.floor(tonumber(seconds) or 0))
	if s >= 3600 then
		return math.floor(s / 3600) .. "h"
	end
	return math.max(1, math.ceil(s / 60)) .. "m"
end

local function petName(petId)
	local ok, catalog = pcall(function()
		return require(Shared:WaitForChild("PetCatalog", 5))
	end)
	local def = ok and type(catalog) == "table" and catalog.Get and catalog.Get(petId) or nil
	return (def and def.Name) or "a pet"
end

local function short(n)
	return Theme.Short(math.floor(tonumber(n) or 0))
end

-- a pet's name and its last word ("Week Wisp", "Wisp")
local function petNames(petId)
	local name = petName(petId)
	return { name, string.match(name, "(%S+)%s*$") or name }
end

-- the short amount of a cell, the longest form first ("$1.45K", "50", "Week Wisp" / "Wisp", "$1.23M"). (Pitch 2 F0, finish
-- pass A: one number style, Theme.Short; the cells read "$1,450" beside the HUD's "48.2K")
local function cellAmounts(entry)
	local kind = entry.Kind
	if kind == "Cash" then
		return { "$" .. short(entry.Amount) }
	elseif kind == "Pet" then
		return petNames(entry.PetId)
	elseif kind == "Berries" then
		return { "Berries" }
	end
	return { short(entry.Amount) }
end

-- a play tier whose claim would pay nothing now: the server resolved it to Amount 0 (a full Berry Basket) or "None".
-- CLAIM ALL leaves it out (DailyService.ClaimPlayAll skips it too); its own box still claims it
local function paysNothing(tier)
	if tier.Kind == "None" then
		return true
	end
	local amount = tonumber(tier.Amount)
	return tier.Kind ~= "Pet" and amount ~= nil and amount < 1
end

-- the words of a play tier's reward, the longest form first ("+$200", "+40" after the token coin, "Full Berry Basket" /
-- "Berry Basket" / "Full Basket"; a full Basket, Amount 0: "Basket is full" / "Basket full"). (U9-4 look review) tokens
-- and gems read as the Trove's tags do: their pixel icon before the amount, not the word (look review 2: on their role's
-- tag, K.REWARD_TAG, H.placeReward)
local function tierRewards(tier)
	local kind = tier.Kind
	if kind == "Cash" then
		return { "+$" .. short(tier.Amount) } -- (Pitch 2 F0) one number style, Theme.Short
	elseif kind == "Tokens" or kind == "Gems" then
		return { "+" .. short(tier.Amount) }
	elseif kind == "Berries" and paysNothing(tier) then
		return { "Basket is full", "Basket full" }
	elseif kind == "Berries" then
		return { "Full Berry Basket", "Berry Basket", "Full Basket" }
	elseif kind == "Pet" then
		return petNames(tier.PetId)
	end
	return { "+" .. short(tier.Amount) }
end

local function days(st)
	return (type(st) == "table" and type(st.Days) == "table") and st.Days or {}
end

local function play(st)
	return (type(st) == "table" and type(st.Play) == "table") and st.Play or {}
end

local function tiers(st)
	local p = play(st)
	return type(p.Tiers) == "table" and p.Tiers or {}
end

local function entryAt(list, i)
	local e = list[i]
	return type(e) == "table" and e or {}
end

-- true once the payload's view went stale (StaleAt passed): the server's fresh payload is on its way (re-review 2)
local function stale(st, at)
	local staleAt = type(st) == "table" and tonumber(st.StaleAt) or nil
	return staleAt ~= nil and staleAt > 0 and (at or now()) >= staleAt
end

-- a streak claim the server will take now: ready, not stale and not held by the 10-minute rule
local function claimable(st)
	local mode = DailyController.ClaimView(st, now(), false).Mode
	return mode == "Claim" or mode == "Repair"
end

local function tierReady(st)
	if type(st) ~= "table" or st.Loading == true then
		return false
	end
	for _, t in ipairs(tiers(st)) do
		if type(t) == "table" and t.Ready == true and t.Claimed ~= true then
			return true
		end
	end
	return false
end

-- the ring's fill: Play.Seconds / the next tier's seconds (1 once every tier is behind)
local function ringFill(st)
	local seconds = tonumber(play(st).Seconds) or 0
	for _, t in ipairs(tiers(st)) do
		local goal = (tonumber(type(t) == "table" and t.Min) or 0) * 60
		if goal > seconds then
			return math.max(0, math.min(1, seconds / goal))
		end
	end
	return #tiers(st) > 0 and 1 or 0
end

local function tutorialOk()
	local t = S.Tutorial
	if type(t) ~= "table" then
		local tc = controller("TutorialController")
		if tc and type(tc.GetState) == "function" then
			local ok, state = pcall(tc.GetState)
			t = ok and state or nil
		end
	end
	if type(t) ~= "table" then
		return false
	end
	if t.Done == true then
		return true
	end
	local spin = TutorialSteps.IndexOf and TutorialSteps.IndexOf.spin or 1
	local step = tonumber(t.Step) or (type(t.Id) == "string" and TutorialSteps.IndexOf[t.Id]) or 0
	return step >= spin
end

local function hiddenByPlay()
	local p = LocalPlayer
	if not p then
		return true
	end
	return p:GetAttribute(Config.Attr.InMatch) == true or p:GetAttribute(Config.Attr.InBattle or "InBattle") ~= nil
end

local H = {}
DailyController._H = H -- (review round 2) tests stand in a step of Open (a build / layout / render that throws)

-- the first of `texts` that fits the label's box (its design width less FIT_SLACK) at its size and font, measured by
-- TextService (the real font: a cell's text is never cut to "Week W..."); the last one when none does
function H.fitText(lbl, texts)
	local width = lbl.Size.X.Offset - K.FIT_SLACK
	for i = 1, #texts - 1 do
		local ok, size = pcall(function()
			return Theme.MeasureLabel(lbl, texts[i], lbl.TextSize, 4096)
		end)
		if not ok or typeof(size) ~= "Vector2" or size.X <= width then
			return texts[i]
		end
	end
	return texts[#texts]
end

-- a text's width at a size and font (TextService; the mock's flat 0.5 em when that fails)
function H.width(text, size, font)
	local ok, v = pcall(function()
		return Theme.Measure(text, font, size, 4096)
	end)
	if ok and typeof(v) == "Vector2" then
		return v.X
	end
	return #tostring(text) * size * 0.5
end

-- the rows `text` word-wraps into at `width` px (each word measured by TextService; math.huge when one word is wider)
function H.rows(text, size, font, width)
	local rows, cur = 0, 0
	local space = H.width(" ", size, font)
	for word in string.gmatch(tostring(text), "%S+") do
		local w = H.width(word, size, font)
		if w > width then
			return math.huge
		end
		if cur > 0 and cur + space + w <= width then
			cur = cur + space + w
		else
			rows = rows + 1
			cur = w
		end
	end
	return math.max(rows, 1)
end

-- H.fitText for a label of `lines` rows: the first of `texts` that word-wraps into them (one row: H.fitText)
function H.fitLines(lbl, texts, lines)
	if (lines or 1) <= 1 then
		return H.fitText(lbl, texts)
	end
	local width = lbl.Size.X.Offset - K.FIT_SLACK
	for i = 1, #texts - 1 do
		if H.rows(texts[i], lbl.TextSize, Theme.FontOf(lbl), width) <= lines then
			return texts[i]
		end
	end
	return texts[#texts]
end

-- the played seconds at server time `at`: the payload's, plus the time since ServerNow while the server counts (Active)
function H.liveSeconds(st, at)
	local p = play(st)
	local seconds = tonumber(p.Seconds) or 0
	if p.Active == true then
		seconds = seconds + math.max(0, (tonumber(at) or now()) - (tonumber(type(st) == "table" and st.ServerNow) or at or now()))
	end
	return seconds
end

-- the play tiers a CLAIM ALL would claim now (not one that would pay nothing: the server leaves it for its own box)
function H.readyCount(st)
	if type(st) ~= "table" or st.Loading == true then
		return 0
	end
	local n = 0
	for _, t in ipairs(tiers(st)) do
		if type(t) == "table" and t.Ready == true and t.Claimed ~= true and not paysNothing(t) then
			n = n + 1
		end
	end
	return n
end

function H.touchOnly()
	return UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true
end

----------------------------------------------------------------------
-- The button, its pip and ring
----------------------------------------------------------------------
function H.hud()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	return pg and pg:FindFirstChild("NimbusHud")
end

function H.small()
	local vp = viewport()
	return math.min(vp.X, vp.Y) <= K.SMALL
end

function H.buttonSize()
	if H.small() then
		return K.BTN_MIN
	end
	return math.max(K.BTN_MIN, math.floor(K.BTN * Theme.ScreenFactor(viewport().Y)))
end

-- (kit-b U8: the pitch's HUD stage) the button is a small pink kit B block (the awning colour: face, darker lip, wood edge;
-- square) with the pixel gift over the word "Gift", both brown; H.paintButton sizes them to the block
function H.buildButton()
	local size = H.buttonSize()
	local Sign = Theme.Sign
	local button = Instance.new("TextButton")
	button.Name = "GiftsButton"
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 0
	button.BackgroundColor3 = Sign.Roof
	button.Size = UDim2.fromOffset(size, size)
	button.ZIndex = 2
	button:SetAttribute("SignLook", "Gift")
	local edge = Instance.new("UIStroke")
	edge.Name = "SignEdge"
	edge.Color = Sign.Wood
	edge.Thickness = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.LineJoinMode = Enum.LineJoinMode.Miter
	edge.Parent = button
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BorderSizePixel = 0
	lip.BackgroundColor3 = Sign.RoofLip
	lip.AnchorPoint = Vector2.new(0, 1)
	lip.Position = UDim2.new(0, 0, 1, 0)
	lip.Size = UDim2.new(1, 0, 0, 5)
	lip.ZIndex = 2
	lip.Parent = button
	button.Parent = U.Gui
	U.Button = button
	U.Icon = NeonKit.Icon(button, "Gifts", 27)
	U.Icon.TextColor3 = Sign.Text
	U.Icon.ZIndex = 3
	U.Word = Theme.Label("Gift", "Button", { Size = 15, Color = Sign.Text })
	U.Word.Name = "Word"
	U.Word.AnchorPoint = Vector2.new(0.5, 0.5)
	U.Word.TextXAlignment = Enum.TextXAlignment.Center
	U.Word.ZIndex = 3
	U.Word.Parent = button
	-- (U9-4 look review: the bar census) the play clock's progress toward the next tier (spec 8: "fills toward the next
	-- tier") in the kit's block-bar language, inside the block: Frame "PlayBar" over the block's lip, K.BAR_SEGS blocks
	-- with K.BAR_GAP px of the lip between them, filled left to right in gold (whole blocks, whole px), the gold lip while
	-- the clock is paused (never alpha); the rest stays the lip's own pink. It replaced a gold outline swept by a rotating
	-- gradient round the block (no segments, no lip, alpha-dimmed)
	local bar = Instance.new("Frame")
	bar.Name = "PlayBar"
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(1, 1)
	bar.ZIndex = 3
	bar.Parent = lip
	U.PlayBar = bar
	U.BarSegs = {}
	for i = 1, K.BAR_SEGS do
		local seg = Instance.new("Frame")
		seg.Name = "Seg" .. i
		seg.BorderSizePixel = 0
		seg.BackgroundColor3 = Sign.RoofLip
		seg.ZIndex = 3
		seg.Parent = bar
		U.BarSegs[i] = seg
	end
	local pip = Instance.new("Frame")
	pip.Name = "Pip"
	pip.BackgroundColor3 = Theme.Sign.Red -- (kit-b U8) a small red square in a wood edge
	pip.BorderSizePixel = 0
	pip.AnchorPoint = Vector2.new(0.5, 0.5)
	pip.Position = UDim2.new(1, -4, 0, 4)
	pip.Size = UDim2.fromOffset(K.PIP, K.PIP)
	pip.ZIndex = 5
	pip.Visible = false
	local pipEdge = Instance.new("UIStroke")
	pipEdge.Color = Theme.Sign.Wood
	pipEdge.Thickness = 2
	pipEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pipEdge.Parent = pip
	pip.Parent = U.Button
	U.Pip = pip
	-- (owner 2026-11-13) the button only opens: it hides while its window is open (X / Esc / gamepad B close it)
	U.Button.Activated:Connect(function()
		DailyController.Open()
	end)
end

-- the PlayBar: the segments laid out across the block's width (whole px; the last one takes the rounding), the first
-- floor(fill x K.BAR_SEGS) gold (the gold lip while paused), the rest the lip's pink; hidden with no play tiers
function H.paintRing()
	if not U.PlayBar then
		return
	end
	local st = S.State
	local fill = ringFill(st)
	local n = K.BAR_SEGS
	local k = math.max(0, math.min(n, math.floor(fill * n + 1e-6)))
	U.PlayBar:SetAttribute("Fill", fill)
	U.PlayBar:SetAttribute("Filled", k)
	local paused = type(st) == "table" and st.Loading ~= true and play(st).Active == false
	U.PlayBar:SetAttribute("Paused", paused)
	local w = U.Button and U.Button.Size.X.Offset or 0
	local segW = math.max(1, math.floor((w - (n - 1) * K.BAR_GAP) / n))
	local Sign = Theme.Sign
	for i, seg in ipairs(U.BarSegs) do
		local x = (i - 1) * (segW + K.BAR_GAP)
		seg.Position = UDim2.fromOffset(x, 0)
		seg.Size = UDim2.new(0, i == n and math.max(1, w - x) or segW, 1, 0)
		seg.BackgroundColor3 = i <= k and (paused and Sign.GoldLip or Sign.Gold) or Sign.RoofLip
		seg.BackgroundTransparency = 0
	end
	U.PlayBar.Visible = type(st) == "table" and st.Loading ~= true and #tiers(st) > 0
end

-- (lobby-shop review round 1: the Shop only; slop audit 2026-11-12, win 5: every window) a window over the button's
-- corner (the Shop's wide rect, the Pets window, the Index, the menu's windows, the Training Place ...) would sit under or
-- over it: the button, its ring and its pip hide while any controller of K.WINDOWS answers IsOpen() == true. Re-laid out by
-- MenuController.WindowOpened (another id), ShopController.Toggled and the K.WINDOW_POLL watcher (a close path with no
-- signal: an X, Esc, another window taking over, a match start). (owner 2026-11-13) The Gifts window itself hides them
-- too: S.Open, asked first (Open / Close re-lay the button out at once); an NPC talk box is NpcController in the list.
-- Nothing anchors to the button (the window is centred, the tutorial has no arrow on it, no claim flies to it), and
-- X / Esc / gamepad B still close the window while its toggle button is hidden.
-- (review round 1) the poll stays cheap: each K.WINDOWS module is looked up (FindFirstChild + require) once and kept; one
-- not found yet is looked up again at most every K.WINDOW_RETRY seconds; a tick is then only their IsOpen calls
function H.windowModule(name)
	local hit = S.WindowMods[name]
	if type(hit) == "table" then
		return hit
	end
	local t = os.clock()
	if type(hit) == "number" and t < hit then
		return nil
	end
	local mod = controller(name)
	S.WindowMods[name] = mod or (t + K.WINDOW_RETRY)
	return mod
end

function H.windowUp()
	if S.Open then
		return true
	end
	for _, name in ipairs(K.WINDOWS) do
		local mod = H.windowModule(name)
		if mod and type(mod.IsOpen) == "function" then
			local ok, open = pcall(mod.IsOpen)
			if ok and open == true then
				return true
			end
		end
	end
	-- (gate fix) the menu's own windows (Settings from the HUD pill's gear, Credits, What's new) are not the title screen,
	-- so MainMenuController.IsOpen() says false for them: ask Window() for the panel's holder instead
	local main = H.windowModule("MainMenuController")
	if main and type(main.Window) == "function" then
		local ok, holder = pcall(main.Window)
		if ok and holder ~= nil and holder.Parent ~= nil then
			return true
		end
	end
	return false
end

-- the K.WINDOW_POLL watcher's step: a layout only when the answer changed since the last one
function H.watchWindows()
	if H.windowUp() ~= S.WindowUp then
		H.layoutButton()
	end
end

function H.layoutButton()
	if not U.Button then
		return
	end
	local size = H.buttonSize()
	local hud = H.hud()
	local left = tonumber(hud and hud:GetAttribute("TopRightLeft")) or 0
	S.WindowUp = H.windowUp()
	S.Hidden = left <= 0 or hiddenByPlay() or S.WindowUp
	local x, y = math.floor(left - K.GAP - size + 0.5), K.TOP
	-- (kit-b U8) the HUD's dock under the strips (GiftLeft / GiftTop / GiftSize; a HUD without them: left of the strips as
	-- before); a dock of 0 (a result card holding the corner) hides the button
	local dock = hud and tonumber(hud:GetAttribute("GiftSize"))
	if dock ~= nil then
		size = dock
		x = tonumber(hud:GetAttribute("GiftLeft")) or x
		y = tonumber(hud:GetAttribute("GiftTop")) or y
		S.Hidden = S.Hidden or dock <= 0
	end
	U.Button.Size = UDim2.fromOffset(size, size)
	U.Button.Position = UDim2.fromOffset(x + S.ShakeX, y)
	-- (LOOK-ui) the HUD's one edge token: the block sits at scale 1, so its 3 px edge and 5 px lip follow the screen factor
	-- in whole px (3 / 5 at 1080p, 2 / 4 below), like the strips above it under their 0.8 scale
	local f = Theme.ScreenFactor(viewport().Y)
	local edge = U.Button:FindFirstChild("SignEdge")
	if edge then
		edge.Thickness = math.max(2, math.floor(3 * f + 0.5))
	end
	local lip = U.Button:FindFirstChild("Lip")
	if lip then
		lip.Size = UDim2.new(1, 0, 0, math.max(4, math.floor(5 * f + 0.5)))
	end
	-- the pixel gift over the word, sized to the block (the word never under 14 px)
	local iconPx = math.max(18, math.floor(size * 0.48 / 9) * 9)
	if U.Icon.TextSize ~= iconPx then
		U.Icon.TextSize = iconPx
	end
	U.Icon.Size = UDim2.fromOffset(iconPx, iconPx) -- (NeonKit.Icon's own box is 1.25 x: the icon fills this one)
	-- (U9-4 look review 2) both at whole-px offsets (the gift centred by scale sat at y .72 / .28: soft on a phone)
	U.Icon.AnchorPoint = Vector2.new(0, 0)
	U.Icon.Position = UDim2.fromOffset(math.floor((size - iconPx) / 2), math.floor(size * 0.38 - iconPx / 2))
	U.Word.TextSize = math.max(14, math.floor(size * 0.27 + 0.5))
	U.Word.Size = UDim2.new(1, 0, 0, U.Word.TextSize + 2)
	U.Word.AnchorPoint = Vector2.new(0, 0)
	U.Word.Position = UDim2.fromOffset(0, math.floor(size * 0.76 - (U.Word.TextSize + 2) / 2))
	U.Button.Visible = not S.Hidden
	H.paintRing() -- (the PlayBar lives in the block's lip: it hides and shakes with the block)
	H.refreshPip()
end

function H.refreshPip()
	if U.Pip then
		U.Pip.Visible = DailyController.PipShown()
	end
end

function H.shake()
	S.ShakeToken = S.ShakeToken + 1
	local mine = S.ShakeToken
	task.spawn(function()
		for _, dx in ipairs(K.SHAKE) do
			if S.ShakeToken ~= mine then
				return
			end
			S.ShakeX = dx
			safe("shake", H.layoutButton)
			task.wait(K.SHAKE_STEP)
		end
		if S.ShakeToken == mine then
			S.ShakeX = 0
			safe("shake", H.layoutButton)
		end
	end)
end

----------------------------------------------------------------------
-- The window: built once, laid out on every screen change
----------------------------------------------------------------------
-- a tab: its block is a sibling frame under the (transparent) button (kit-b U9-4: a kit B block, H.paintTab paints it
-- stone or the selected gold), so the button keeps its own text over it
function H.tabButton(name, text)
	local fill = Instance.new("Frame")
	fill.Name = name .. "Fill"
	fill.BorderSizePixel = 0
	fill.ZIndex = 5
	fill.Parent = U.Bar
	CloudUI.SignBlock(fill, "Stone", { Pad = false })
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundTransparency = 1
	b.Text = text
	b.ZIndex = 6
	Theme.Style(b, "Button", { Size = 17, Color = SIGN.Text })
	b.Parent = U.Bar
	return b
end

-- (kit-b U9-4) a square tag in its wood edge with brown words (the streak on stone, the VIP chip on gold)
function H.chip(name, look, parent)
	local c = label(name, "", "Heading", 15, parent, { TextWrapped = false, ZIndex = 5 })
	CloudUI.SignBlock(c, look, { LipPx = 0, EdgePx = 2 })
	return c
end

-- (kit-b U9-4) the sunk cover over a claimed day or box: the well, see-through enough to show what was won
function H.dim(parent)
	return Util.Create("Frame", {
		Name = "Dim", BackgroundColor3 = SIGN.Well, BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		ZIndex = 6, Visible = false, Parent = parent,
	})
end

-- (kit-b U9-4, the owner's look bar 2026-11-17: a small handmade touch on rewards) the glint of the one thing to claim:
-- Frame "Sparkles" with two pixel sparkles (PixelIcon "sparkle", SparkleA / SparkleB) that take turns on the 1 s tick (two
-- frames, no tween, no glow); hidden until H.placeSparkles shows it round a tile's art or a box's gift
function H.sparkles(parent)
	return Util.Create("Frame", { Name = "Sparkles", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		Visible = false, ZIndex = 7, Active = false, Parent = parent })
end

-- the two sparkles in `colour` at the corners of a w x h art box at (x, y): one over its top right, one over its bottom
-- left; px a multiple of 9 (PixelIcon's whole pixels), redrawn only when the size changes
function H.placeSparkles(box, x, y, w, h, px, colour)
	if box:GetAttribute("Px") ~= px then
		box:SetAttribute("Px", px)
		for _, c in ipairs(box:GetChildren()) do
			c:Destroy()
		end
		for i, name in ipairs({ "SparkleA", "SparkleB" }) do
			local icon = PixelIcon.New(box, "sparkle", px, colour)
			if icon then
				icon.Name = name
				icon.ZIndex = 7
				for _, f in ipairs(icon:GetChildren()) do
					f.ZIndex = 7
				end
				icon.Visible = i == 1
			end
		end
	end
	local a, b = box:FindFirstChild("SparkleA"), box:FindFirstChild("SparkleB")
	if a then
		a.Position = UDim2.fromOffset(math.floor(x + w - px * 0.6), math.floor(y - px * 0.2))
	end
	if b then
		b.Position = UDim2.fromOffset(math.floor(x - px * 0.4), math.floor(y + h - px * 0.8))
	end
end

-- the tick's twinkle: the lit sparkle swaps
function H.twinkle(box, flip)
	local a, b = box:FindFirstChild("SparkleA"), box:FindFirstChild("SparkleB")
	if a and b then
		a.Visible, b.Visible = not flip, flip
	end
end

-- (U9-4 look review) a pixel size of the laid-out screen (K.PIXEL): "Glyph" or "Art"
function H.px(kind)
	local set = K.PIXEL[S.Mode == "PC" and "PC" or "Phone"]
	return set[kind] or set.Glyph
end

-- the largest of the screen's two pixel sizes that fits `room` px (the glyph size when neither does)
function H.fitPx(room)
	local art = H.px("Art")
	return (tonumber(room) or 0) >= art and art or H.px("Glyph")
end

-- (P2 icons review r1, major 2: the reward art drew 54 px on PC tiles and 36 on phone tiles, the gem, the coin and the
-- bills small in big empty tiles) a day's reward art at the approved 09_daily_layout B size, M.RewardPx (72 px: 4 px
-- cells of the 18 x 18 sheet art on PC tiles; 54: 3 px cells on phone tiles; the reward is the tile's hero), where
-- `room` holds it; else the largest of the screen's two pixel sizes that does
function H.rewardPx(room, M)
	local want = M and tonumber(M.RewardPx) or 0
	if want > 0 and (tonumber(room) or 0) >= want then
		return want
	end
	return H.fitPx(room)
end

-- a sparkle's px: the screen's glyph size
local function sparklePx()
	return H.px("Glyph")
end

-- the TextSize of a label whose hosted PixelIcon (0.9 x the TextSize, snapped to 9s) must draw at `px`
local function hostSize(px)
	return math.ceil(px / 0.9)
end

-- (kit-b U9-4) a day tile: a kit B block (NeonKit.Card Skin "Sign"; H.paintLook gives it its face and edge, the day's
-- colour sits on its lip)
function H.newCell(i, parent)
	local c = NeonKit.Card({ Name = "Cell" .. i, Skin = "Sign", BodyOverLip = true, Lip = DAY_COLORS[i], Size = UDim2.fromOffset(92, 122), ZIndex = 4, Parent = parent })
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = c.Root
	local day = label("Day", "Day " .. i, "Label", 15, c.Body, { TextWrapped = false, ZIndex = 5, TextColor3 = SIGN.Text })
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.ZIndex = 5
	art.Parent = c.Body
	local amount = label("Amount", "", "Display", 17, c.Body, { TextWrapped = false, ZIndex = 5, TextColor3 = SIGN.Text })
	amount.TextTruncate = Enum.TextTruncate.AtEnd
	local dim = H.dim(c.Body)
	local check = label("Check", "", "Title", 36, c.Body, { TextColor3 = SIGN.GrassLip, ZIndex = 7, Visible = false, TextWrapped = false })
	-- (P2 icons look fin0, minor: green on Day 1's green bills) the tick in a 1-cell cream ring, the 09_daily_layout B
	-- mock-up's (PixelIcon's keyline)
	check:SetAttribute("IconKey", SIGN.Tile)
	PixelIcon.Host(check, CHECK) -- sized with the label
	U.Cells[i] = { Card = c, Root = c.Root, Pop = pop, Day = day, Art = art, Amount = amount, Dim = dim, Check = check, ArtKey = nil, LookKey = nil,
		Sparkles = H.sparkles(c.Body) }
end

-- a play-time gift box (card B): the minutes, the gift, the reward and one slot (Claim, the clock or the tick); (kit-b
-- U9-4) a kit B block like a day tile, its Claim a stone plank (Claim all is the page's one green action)
function H.newTier(i, parent)
	local c = NeonKit.Card({ Name = "Tier" .. i, Skin = "Sign", BodyOverLip = true, Lip = TIER_COLORS[i], Size = UDim2.fromOffset(104, 204), ZIndex = 4, Parent = parent })
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = c.Root
	local timeLabel = label("Time", "", "Heading", 15, c.Body, { TextWrapped = false, ZIndex = 5, TextColor3 = SIGN.Text })
	local gift = Util.Create("Frame", { Name = "Gift", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5, Parent = c.Body })
	gift:SetAttribute("Bobbing", false)
	local reward = label("Reward", "", "Display", 15, c.Body, { TextWrapped = false, ZIndex = 5, TextColor3 = SIGN.Text })
	reward.TextTruncate = Enum.TextTruncate.AtEnd
	local dim = H.dim(c.Body)
	local clock = label("Clock", "", "Display", 16, c.Body, { TextColor3 = SIGN.Text, TextWrapped = false, ZIndex = 5, Visible = false })
	local glyph = label("ClockGlyph", "", "Display", 16, c.Body, { TextColor3 = SIGN.Text, TextWrapped = false, ZIndex = 5, Visible = false })
	PixelIcon.Host(glyph, TEXT.ClockIcon) -- sized with the label
	local check = label("Check", "", "Title", 28, c.Body, { TextColor3 = SIGN.GrassLip, ZIndex = 7, TextWrapped = false, Visible = false })
	PixelIcon.Host(check, CHECK)
	local claim = CloudUI.Button({ Name = "Claim", Text = TEXT.TierClaim, Style = "Gray", Skin = "Sign", Size = UDim2.fromOffset(92, 44), TextSize = 16,
		ZIndex = 8, Parent = c.Body, Callback = function()
			H.send("ClaimPlay", i)
		end })
	U.Tiers[i] = { Card = c, Root = c.Root, Pop = pop, Time = timeLabel, Gift = gift, Reward = reward, Dim = dim, Clock = clock,
		Glyph = glyph, Check = check, Claim = claim, GiftKey = nil, ClockKey = nil, LookKey = nil, Sparkles = H.sparkles(c.Body) }
end

function H.ensureWindow()
	if U.Holder then
		return
	end
	U.Cells, U.Tiers, U.Segs = {}, {}, {}
	local holder = Util.Create("Frame", { Name = "DailyHolder", BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 4, Parent = U.Gui })
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	-- (kit-b U9-4, finding 15) the Signboard of the Shop: the wood frame round the stone body with its lip, square
	local win = Util.Create("Frame", {
		Name = "DailyWindow", BackgroundColor3 = SIGN.Wood, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = holder,
	})
	win:SetAttribute("SignKit", "Frame")
	U.Window = win
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = win })
	local stone = Util.Create("Frame", {
		Name = "Stone", BackgroundColor3 = SIGN.Stone, BorderSizePixel = 0, Position = UDim2.fromOffset(K.FRAME, K.FRAME),
		Size = UDim2.new(1, -2 * K.FRAME, 1, -2 * K.FRAME), ZIndex = 3, Parent = win,
	})
	stone:SetAttribute("SignKit", "Body")
	Util.Create("Frame", {
		Name = "Lip", BackgroundColor3 = SIGN.StoneLip, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, SignKit.Sizes.Lip), ZIndex = 3, Parent = stone,
	})
	SignKit.FinishFrame(win, { Body = stone }) -- (Pitch 2 F0) the frame's light, the window's shadow, the carved body
	-- the navy header plank with its darker lip inside the wood frame (the Shop's header): the gift on its gold square,
	-- "Gifts" as the window's ribbon title, the tabs and the close sit on it
	local bar = Util.Create("Frame", { Name = "TitleBar", BackgroundColor3 = SIGN.Navy, BorderSizePixel = 0, ZIndex = 5, Parent = win })
	Util.Create("Frame", {
		Name = "Lip", BackgroundColor3 = SIGN.NavyLip, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 4), ZIndex = 5, Parent = bar,
	})
	SignKit.BandTop(bar) -- (Pitch 2 F0) the navy band's lit top line
	U.Bar = bar
	U.GiftsIcon = label("GiftsIcon", "", "Display", 32, bar, {
		TextTruncate = Enum.TextTruncate.None, BackgroundTransparency = 0, BackgroundColor3 = SIGN.Gold, TextColor3 = SIGN.Text, ZIndex = 6,
	})
	-- (U9-4 look review) the kit's header icon square (SignKit.Header's IconSlot, the pitch's .hi): 42 px on PC, a 2 px
	-- ink edge, as every window's
	local iconEdge = Instance.new("UIStroke")
	iconEdge.Name = "SignEdge"
	iconEdge.Color = SIGN.Text
	iconEdge.Thickness = 2
	iconEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	iconEdge.LineJoinMode = Enum.LineJoinMode.Miter
	iconEdge.Parent = U.GiftsIcon
	PixelIcon.Host(U.GiftsIcon, NeonKit.IconName("Gifts")) -- the pixel gift, sized with the label
	U.Title = label("WindowTitle", "Gifts", "Title", 34, bar, { TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, ZIndex = 6 })
	U.Title:SetAttribute("RibbonBand", "NoTails") -- (as the Shop's: the band ends square on the navy plank)
	Theme.StyleTitle(U.Title)
	-- the awning: one fixed-size piece over the top rim (never stretched with the window: the sign rule); PC only
	U.Roof = SignKit.Roof(win, { Width = K.ROOF_W, Y = SignKit.RoofSeat(), ZIndex = 7 }) -- (F0 review) seated on the frame
	U.TabDaily = H.tabButton("Tab_Daily", "Daily")
	U.TabPlay = H.tabButton("Tab_Play", "Play time")
	U.TabDaily.Activated:Connect(function()
		H.setTab("Daily")
	end)
	U.TabPlay.Activated:Connect(function()
		H.setTab("Play")
	end)
	U.Close = CloudUI.Button({ Name = "CloseButton", Text = "", Style = "Red", Skin = "Sign", Size = UDim2.fromOffset(44, 44), TextSize = 22,
		ZIndex = 7, Parent = bar, Callback = function()
			DailyController.Close()
		end })
	-- slop audit 2026-11-12: a drawn X (the U+2715 glyph showed a missing-glyph box); kit B: square bars in brown ink
	NeonKit.CloseMark(U.Close, { Square = true, Ink = SIGN.RedLip, Color = SIGN.Text })
	-- (U9-4 look review 2) on a phone the red block is 36 px inside the band and this see-through 44 px touch box lies
	-- under it (a tap on the block presses the block; one on the ring round it closes too)
	U.CloseTap = Util.Create("TextButton", {
		Name = "CloseTap", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Selectable = false,
		Active = true, ZIndex = 6, Visible = false, Parent = bar,
	})
	U.CloseTap:SetAttribute("HitFor", "CloseButton") -- (F0 review, major 7) the close's 44 px thumb target
	U.CloseTap.Activated:Connect(function()
		DailyController.Close()
	end)
	U.Body =Util.Create("Frame", { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 4, Parent = win })

	-- the Daily page (card A)
	local daily = Util.Create("Frame", { Name = "DailyPage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = U.Body })
	U.DailyPage = daily
	U.DailyHeader = label("Header", "", "Title", 18, daily, { TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, ZIndex = 5, TextColor3 = SIGN.Text })
	Theme.StyleTitle(U.DailyHeader, "Section") -- (the owner's ruling 2026-11-14: the ribbon is for window titles only)
	-- (Pitch 2 F0 A: "dotted pixel rules"; look review of finish pass A, minor) the dotted rule under the heading line
	U.HeadRule = SignKit.Rule(daily, { Name = "HeadRule", ZIndex = 5 })
	U.StreakChip = H.chip("StreakChip", "Stone", daily)
	U.VipChip = H.chip("VipChip", "Selected", daily)
	U.VipChip.Text = "VIP x2"
	U.CellsFrame = Util.Create("Frame", { Name = "Cells", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = daily })
	for i = 1, 7 do
		H.newCell(i, U.CellsFrame)
	end
	-- (Pitch 2 09 B) Day 7 is the prize card: the pet on its plinth, the name on a wood plank, the species line, and the
	-- week's countdown (the line, its 7-block bar, the week banner in their place) inside the card
	local hero = U.Cells[7]
	local card = hero.Card.Body
	hero.Plinth = Util.Create("Frame", { Name = "Plinth", BorderSizePixel = 0, ZIndex = 5, Parent = card })
	CloudUI.SignBlock(hero.Plinth, "Off", { EdgePx = 2, LipPx = 0, Pad = false })
	CloudUI.SignBlock(hero.Amount, K.PLANK, { EdgePx = K.PLANK_EDGE, LipPx = K.PLANK_LIP })
	hero.Amount:SetAttribute("Plank", true)
	hero.Species = label("Species", "", "Label", 15, card, { TextWrapped = false, ZIndex = 5, TextColor3 = SIGN.TextMuted })
	U.WispText = label("WispText", "", "Heading", 15, card, { TextWrapped = false, ZIndex = 5, TextColor3 = SIGN.Text })
	U.WispBar = Util.Create("Frame", { Name = "WispBar", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5, Parent = card })
	for i = 1, 7 do
		local seg = Util.Create("Frame", { Name = "Seg" .. i, BorderSizePixel = 0, ZIndex = 6, Parent = U.WispBar })
		paintSeg(seg, "Open")
		U.Segs[i] = seg
	end
	-- the page's one green plank (kit-b U9-4: a kit B block; locked, the Off block)
	U.Claim = CloudUI.Button({ Name = "ClaimButton", Text = TEXT.Claim, Style = "Green", Skin = "Sign", Size = UDim2.fromOffset(360, 88), TextSize = 40, ZIndex = 6,
		Parent = daily, Callback = function()
			H.onClaim()
		end })
	U.Line1 = label("Line1", "", "Body", 15, U.Claim, { TextWrapped = false, Visible = false, ZIndex = 9, TextColor3 = SIGN.Text })
	U.Line2 = label("Line2", "", "Body", 15, U.Claim, { TextWrapped = false, Visible = false, ZIndex = 9, TextColor3 = SIGN.TextMuted })
	U.Countdown = label("Countdown", "", "Heading", 17, daily, { ZIndex = 5, TextColor3 = SIGN.Text })
	U.Keep = label("Keep", TEXT.Keep, "Body", 15, daily, { TextColor3 = SIGN.TextMuted, ZIndex = 5, TextYAlignment = Enum.TextYAlignment.Top })
	-- (kit-b U9-4) the week banner: a gold block with brown words in the Wisp line's place
	U.Banner = label("WeekBanner", TEXT.Week, "Title", 15, card, { Visible = false, ZIndex = 8 }) -- (over the card's cover)
	Theme.StyleTitle(U.Banner, "Section")
	CloudUI.SignBlock(U.Banner, "Selected", { LipPx = 0, EdgePx = 2 })

	-- the Play page (card B: the header line, CLAIM ALL, seven gift boxes)
	local playPage = Util.Create("Frame", { Name = "PlayPage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 4, Parent = U.Body })
	U.PlayPage = playPage
	U.PlayHeader = label("PlayHeader", "", "Heading", 17, playPage, { TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, ZIndex = 5, TextColor3 = SIGN.Text })
	-- the page's one green plank (a box's own Claim is stone)
	U.ClaimAll = CloudUI.Button({ Name = "ClaimAll", Text = string.format(TEXT.ClaimAll, 0), Style = "Green", Skin = "Sign", Size = UDim2.fromOffset(166, 44), TextSize = 15,
		ZIndex = 6, Parent = playPage, Callback = function()
			H.claimAll()
		end })
	U.TiersFrame = Util.Create("Frame", { Name = "Tiers", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = playPage })
	for i = 1, 7 do
		H.newTier(i, U.TiersFrame)
	end

	-- the week's sweep + confetti layer (inside the window only)
	U.Fx = Util.Create("Frame", { Name = "Fx", BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = U.Body })
	-- the cursor is free while the window is shown (client/MouseLock, as the Pets window and the Training Place)
	local mouseLock = Client:FindFirstChild("MouseLock")
	local okLock, lock = pcall(function()
		return mouseLock and require(mouseLock)
	end)
	if okLock and type(lock) == "table" and type(lock.WatchVisible) == "function" then
		safe("mouse lock", lock.WatchVisible, "Dock:" .. holder.Name, holder)
	end
	S.Pulse = false
end

-- the design numbers of the laid-out layout
function H.metrics()
	if S.Mode == "PC" then
		return K.PC
	elseif S.Mode == "Portrait" then
		return K.PORTRAIT
	end
	return K.PHONE
end

function H.inset()
	local inset = 58
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	return inset
end

-- (Pitch 2 09 B) the window's height follows the prize stand (screen px, in place): on PC the Daily page's window is
-- no taller than the Header + MaxBody design px, centred in its BigRect box (the box's 644 px body left ~160 px of
-- empty stone at 1080p); the Play page keeps the box's height (its two rows of gift boxes need it) under the same top,
-- so the tabs stay where they are (raised only as far as the screen's foot needs). On a portrait phone the window is up
-- to WinH tall from TopClear under the HUD's strips (TopClearTight where that leaves under WinMinRoom px), Foot px over
-- the screen's foot, where that is taller than the box. A landscape phone keeps its box
function H.fitRect(r, mode)
	if mode == "PC" then
		local full = r.h
		local maxH = (K.PC.Header + K.PC.MaxBody) * r.scale
		if full > maxH + 0.5 then
			local top = math.floor(r.y + (full - maxH) / 2 + 0.5)
			if S.Tab == "Play" then
				r.y = math.max(r.y, math.min(top, math.floor(viewport().Y - K.MARGIN - full)))
			else
				r.y, r.h = top, maxH
			end
		end
	elseif mode == "Portrait" then
		local P = K.PORTRAIT
		local inset = H.inset()
		local area = viewport().Y - inset
		local strips = H.stripsBottom()
		local top = strips + P.TopClear
		if area - P.Foot - top < P.WinMinRoom then
			top = strips + P.TopClearTight
		end
		local want = math.min(P.WinH, area - P.Foot - top)
		if want > r.h then
			r.y, r.h = inset + top, want
		end
	end
end

-- the box (NeonKit.BigRect, H.fitRect) -> the holder at its place and scale, then every part in the design box
function H.layout()
	if not U.Holder then
		return
	end
	local r = NeonKit.BigRect(K)
	local mode = r.mode
	if mode == "Phone" and r.portrait then
		mode = "Portrait"
	end
	H.fitRect(r, mode)
	S.Rect, S.Mode, S.Scale = r, mode, r.scale
	local W = math.floor(r.w / r.scale + 0.5)
	local Hh = math.floor(r.h / r.scale + 0.5)
	-- (NimbusDaily keeps the gui inset: its area starts under the top bar)
	place(U.Holder, r.x, r.y - H.inset(), W, Hh)
	U.Fit.Scale = r.scale
	S.WindowX = math.floor(r.x + 0.5)
	local M = H.metrics()
	H.layoutHeader(M, W, r.y - H.inset())
	local top = M.Header + (M.TabRow or 0)
	local B = Hh - top
	place(U.Body, 0, top, W, B)
	H.layoutDaily(M, W, B)
	H.layoutPlay(M, W, B)
end

-- (kit-b U9-4) the header as the Shop's: the navy band inside the wood frame (its edge shows round the top), the gift on
-- its gold square, "Gifts" (the ribbon), the two tab blocks, the red close at the right; where the band is too short for
-- all of them (a portrait phone) the title goes first, then the square. The tab buttons keep a TapH touch box over
-- their blocks (>= 44 px on a phone). Positions are in the band's own px
-- the bottom of the HUD's currency strips in gui-area px (over the gift's square, which hides while this window is open)
function H.stripsBottom()
	local hud = H.hud()
	if not hud then
		return 0
	end
	local gift = tonumber(hud:GetAttribute("GiftSize")) or 0
	if gift > 0 then
		return tonumber(hud:GetAttribute("GiftTop")) or 0
	end
	return tonumber(hud:GetAttribute("TopRightBottom")) or 0
end

-- winTop: the window's top in gui-area px (the awning's room)
function H.layoutHeader(M, W, winTop)
	local F = K.FRAME
	local bw, bh = W - 2 * F, M.Header - F
	place(U.Bar, F, F, bw, bh)
	-- (the awning reaches 10 px over the top on PC; no roof on a landscape phone: the Shop's rule, that window starts
	-- right under Roblox's top bar. U9-4 look review: the portrait window has clear sky over it, so it keeps the awning at
	-- the phones' ROOF_PHONE_W px whenever ROOF_CLEAR px lie between the HUD's strips and its top)
	local portrait = S.Mode == "Portrait"
	U.Roof.Size = UDim2.fromOffset(portrait and K.ROOF_PHONE_W or K.ROOF_W, U.Roof.Size.Y.Offset)
	U.Roof.Visible = S.Mode == "PC" or (portrait and (tonumber(winTop) or 0) - K.ROOF_CLEAR >= H.stripsBottom())
	local closeX = bw - M.Close - (10 - F)
	-- (U9-4 look review 2) a phone band: the CloseBlock px block centred in the band, its stroke 4 px inside the band's
	-- right end, over its Close px touch box (the 44 px block filled the band and its stroke hung onto the stone)
	local block = M.CloseBlock
	-- (merge kitb-look1 x U9-4) the 36 px block keeps U9-4's 3 px edge and 5 px lip (the kit's 5 / 8 would hang out of
	-- the 44 px band)
	U.Close:SetAttribute("EdgePx", block and 3 or nil)
	U.Close:SetAttribute("LipPx", block and 5 or nil)
	if block then
		closeX = bw - K.CLOSE_INSET - block
		local by = math.floor((bh - block) / 2)
		place(U.Close, closeX, by, block, block)
		place(U.CloseTap, closeX - math.floor((M.Close - block) / 2), by - math.floor((M.Close - block) / 2), M.Close, M.Close)
	else
		place(U.Close, closeX, math.floor((M.Header - M.Close) / 2) - F, M.Close, M.Close) -- (its drawn X scales with it)
	end
	U.CloseTap.Visible = block ~= nil
	NeonKit.CloseMarkPx(U.Close, H.px("Glyph")) -- (LOOK-ui) the x at the screen's glyph size: one pixel size
	-- (portrait: the tabs have their own row, so the band only holds the gift and the title)
	local tabsW = portrait and 0 or (M.TabW[1] + M.TabGap + M.TabW[2])
	local slot = M.Icon + 4
	local x = 10
	local room = closeX - 8
	local withIcon = x + slot + 10 + tabsW <= room
	local withTitle = withIcon and x + slot + 10 + M.TitleW + M.TitleGap + tabsW <= room
	U.GiftsIcon.Visible, U.Title.Visible = withIcon, withTitle
	if withIcon then
		-- (PC: centred on the band's face over its 4 px lip; look review 2, a phone: in line with the close block)
		place(U.GiftsIcon, x, math.floor((bh - (block and 0 or 4) - slot) / 2), slot, slot)
		U.GiftsIcon.TextSize = math.max(12, M.Icon - 10)
		x = x + slot + 10
	else
		x = M.HeadPad - F
	end
	if withTitle then
		place(U.Title, x, 0, M.TitleW, bh - 4)
		U.Title.TextSize = M.TitleText
		x = x + M.TitleW + M.TitleGap -- (the ribbon's stair keeps clear of the first tab)
	end
	-- (the touch box centred on the block's face, over its lip: the word sits where the face is)
	if portrait then
		-- the tab row under the band (still the bar's children, so they move with it): two halves of the inside, each a
		-- TabRowH block with its TapH touch box
		local tw = math.floor((W - 2 * M.TabRowSide - M.TabRowMid) / 2)
		local ty = bh + M.TabRowGap
		local tapY = math.floor(ty + (M.TabRowH - CloudUI.SignMetrics.Lip) / 2 - M.TapH / 2 + 0.5)
		x = M.TabRowSide - F
		for _, tab in ipairs({ U.TabDaily, U.TabPlay }) do
			place(tab, x, tapY, tw, M.TapH)
			place(U.Bar:FindFirstChild(tab.Name .. "Fill"), x, ty, tw, M.TabRowH)
			x = x + tw + M.TabRowMid
		end
	else
		local tapY = math.floor((M.TabY - F) + (M.TabH - CloudUI.SignMetrics.Lip) / 2 - M.TapH / 2 + 0.5)
		for i, tab in ipairs({ U.TabDaily, U.TabPlay }) do
			place(tab, x, tapY, M.TabW[i], M.TapH)
			place(U.Bar:FindFirstChild(tab.Name .. "Fill"), x, M.TabY - F, M.TabW[i], M.TabH)
			x = x + M.TabW[i] + M.TabGap
		end
	end
	U.TabDaily.TextSize, U.TabPlay.TextSize = M.TabText, M.TabText
end

-- the Daily page's geometry (S.G); the chips and the claim slot follow the payload, so render places them (keyed)
function H.layoutDaily(M, W, B)
	local G = { W = W, B = B }
	S.G = G
	S.ChipKey, S.BottomKey = nil, nil
	U.DailyHeader.TextSize = M.HeaderText
	U.StreakChip.TextSize, U.VipChip.TextSize = M.ChipText, M.ChipText
	U.WispText.TextSize, U.Banner.TextSize = M.WispText, M.BannerText
	U.Countdown.TextSize, U.Keep.TextSize = M.CountText, M.KeepText
	U.Line1.TextSize, U.Line2.TextSize = M.Line1, M.Line2
	-- (Pitch 2 09 B) every spot in the page's px first; the Cells frame is the day tiles' box (the prize card sits outside
	-- it, a child all the same, so a tile's lookup in "Cells" keeps finding Day 7)
	local spots = {}
	local gap = M.TileGap
	local tw, th, box, ruleTop, ruleW
	if S.Mode == "Portrait" then
		tw = math.min(M.TileW, math.floor((W - 2 * M.Side - 2 * gap) / 3))
		local gridW = 3 * tw + 2 * gap
		local x0 = math.floor((W - gridW) / 2)
		local fixed = M.HeroY + M.HeroGap + M.Raise + M.RowGap + M.AfterTiles + M.ClaimH + M.ClaimGap + M.KeepH + M.Bottom
		local room = B - fixed
		local heroH = math.max(M.HeroMinH, math.min(M.HeroMaxH, math.floor(room * M.HeroShare)))
		th = math.max(M.TileMinH, math.min(M.TileMaxH, math.floor((room - heroH) / 2)))
		heroH = math.max(M.HeroMinH, math.min(M.HeroMaxH, room - 2 * th))
		-- (what the card and the tiles both leave at their largest goes to the three gaps round the grid)
		local spare = math.floor(math.max(0, room - heroH - 2 * th) / 3)
		spots[7] = { x = x0, y = M.HeroY, w = gridW, h = heroH, hero = true }
		local top = M.HeroY + heroH + M.HeroGap + spare -- (today's raised top)
		for i = 1, 6 do
			local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
			spots[i] = { x = x0 + col * (tw + gap), y = top + M.Raise + row * (th + M.RowGap), w = tw, h = th }
		end
		box = { x0, top, gridW, M.Raise + 2 * th + M.RowGap }
		G.ClaimX, G.ClaimW = x0, gridW
		G.ClaimY = top + M.Raise + 2 * th + M.RowGap + M.AfterTiles + spare
		G.ClaimH = M.ClaimH
		G.KeepX, G.KeepY, G.KeepW, G.KeepH = x0, G.ClaimY + M.ClaimH + M.ClaimGap, gridW, M.KeepH
		ruleTop, ruleW = M.HeroY, W - 2 * M.Side
	else
		local rowRoom = W - 2 * M.Side - M.HeroW - M.ColGap
		tw = math.min(M.TileW, math.floor((rowRoom - 5 * gap) / 6))
		local rowW = 6 * tw + 5 * gap
		local x0 = M.Side
		local fixed = M.TilesY + M.AfterTiles + M.ClaimH + M.Bottom
		th = math.max(M.TileMinH, math.min(M.TileMaxH, B - fixed))
		-- (what the tallest tile leaves goes over and under the row)
		local spare = math.max(0, B - fixed - th)
		local tilesY = M.TilesY + math.floor(spare / 2)
		for i = 1, 6 do
			spots[i] = { x = x0 + (i - 1) * (tw + gap), y = tilesY, w = tw, h = th }
		end
		box = { x0, tilesY - M.Raise, rowW, th + M.Raise }
		G.ClaimX, G.ClaimW = x0, nil
		G.ClaimY = tilesY + th + M.AfterTiles + (spare - math.floor(spare / 2))
		G.ClaimH = M.ClaimH
		G.RowRight = x0 + rowW
		G.ChipsRight = G.RowRight
		-- the prize card: ColGap right of the row to the page's side, from HeroY to the Claim's foot
		local heroX = G.RowRight + M.ColGap
		spots[7] = { x = heroX, y = M.HeroY, w = W - M.Side - heroX, h = G.ClaimY + M.ClaimH - M.HeroY, hero = true }
		ruleTop, ruleW = tilesY - M.Raise, rowW
	end
	place(U.CellsFrame, box[1], box[2], box[3], box[4])
	for i, cell in ipairs(U.Cells) do
		local s = spots[i]
		cell.Spot = { x = s.x - box[1], y = s.y - box[2], w = s.w, h = s.h, hero = s.hero }
		cell.PlaceKey = nil
	end
	G.TileW = tw
	-- (F0 review) the dotted rule halfway between the heading line (its chips) and what comes under it (today's raised
	-- tile; the prize card on a portrait phone), as wide as the day row
	local headFoot = math.max(M.HeaderY + M.HeaderH, M.ChipY + M.ChipH)
	SignKit.SetRule(U.HeadRule, ruleW)
	U.HeadRule.Position = UDim2.fromOffset(M.Side, math.floor((headFoot + ruleTop) / 2) - 1)
	U.HeadRule.Visible = ruleTop - headFoot >= 4
end

-- a tile at its spot (today: raised by M.Raise, the bottom kept), its insides fitted to its size; the prize card
-- (Pitch 2 09 B) is laid out by H.placeHero and never raised
function H.placeTile(cell, M, today, wide)
	local s = cell.Spot
	if not s then
		return
	end
	if s.hero then
		H.placeHero(cell, M)
		return
	end
	local y, h = s.y, s.h
	if today then
		y, h = s.y - M.Raise, s.h + M.Raise
	end
	local key = table.concat({ tostring(S.Mode), s.x, y, s.w, h }, ",")
	if cell.PlaceKey == key then
		return
	end
	cell.PlaceKey = key
	place(cell.Root, s.x, y, s.w, h)
	local w = s.w
	local dayH = M.DayText + 4
	place(cell.Day, 2, M.PadTop, w - 4, dayH)
	cell.Day.TextSize = M.DayText
	local amountH = M.AmountText + 6
	local amountY = h - M.PadBottom - amountH
	place(cell.Amount, 2, amountY, w - 4, amountH)
	cell.Amount.TextSize = M.AmountText
	local artY = M.PadTop + dayH + 1
	local artH = math.max(0, amountY - 1 - artY)
	place(cell.Art, 0, artY, w, artH)
	-- the reward's chip (ChipPx, or less where the tile is small) and the art on it at one of the screen's two pixel
	-- sizes
	cell.PetPx = math.max(12, math.min(M.PetPx, artH, w - 8))
	cell.ChipPx = math.max(12, math.min(M.ChipPx, artH, w - 8))
	-- (P2 icons review r1, major 2) the chip is a clear holder now (item 9 B: no block behind the art): the art takes its
	-- whole room at the 09 B size (it lost 12 px to the block's edge)
	cell.ArtPx = H.rewardPx(cell.ChipPx, M)
	-- (U9-4 look review) the tick at the screen's art size (6 px cells on PC, 4 on a phone); (P2 icons look fin0, minor:
	-- it kept the tile's centre when the art grew, 11 px low and 4 px right of it) centred on the reward's chip, as
	-- H.paintArt places it (centred with the art's drop shadow in the art box). (P2 icons look pol0, major: on the 360 x 640
	-- phone the tiles are 60 px tall, an 11 px art row, and the 36 px tick covered half of "Day 1" and "$400") the largest
	-- of the screen's two pixel sizes that fits the room from the day line's foot to the amount line's top (each line its
	-- TextSize tall, centred in its box: the art row + 2 + 1 over it, + 1 + 3 under it)
	local tick = H.fitPx(artH + 7)
	local check = hostSize(tick)
	cell.Check.TextSize = check
	local drop = math.ceil(cell.ArtPx / 9)
	local cx = math.max(0, math.floor((w - cell.ChipPx - drop) / 2)) + cell.ChipPx / 2
	local cy = artY + math.max(0, math.floor((artH - cell.ChipPx - drop) / 2)) + cell.ChipPx / 2
	local inset = math.floor((check + 8 - tick) / 2) -- where Host centres the icon in its label
	place(cell.Check, math.floor(cx - tick / 2) - inset, math.floor(cy - tick / 2) - inset, check + 8, check + 8)
	-- (kit-b U9-4) the glint round the art (a cream sparkle reads on today's gold)
	local a = wide and cell.PetPx or cell.ChipPx
	H.placeSparkles(cell.Sparkles, (w - a) / 2, artY + (artH - a) / 2, a, a, sparklePx(), SIGN.Tile)
end

-- (Pitch 2 09 B) the prize card's insides. Landscape, top to bottom: its label, the Week Wisp standing on its plinth (the
-- pet as big as the card's width and the room left allow, up to PetMax), the name plank, the species line, the week's
-- line ("in 4 more days") and its 7-block bar, the week banner over the species and the line while it is up. Portrait: the pet on its plinth
-- at the card's left, as tall as the card; the same rows in a column right of it, centred on the card's height
function H.placeHero(cell, M)
	local s = cell.Spot
	local key = table.concat({ "hero", tostring(S.Mode), s.x, s.y, s.w, s.h }, ",")
	if cell.PlaceKey == key then
		return
	end
	cell.PlaceKey = key
	place(cell.Root, s.x, s.y, s.w, s.h)
	local w, h = s.w, s.h
	local pad, g = M.HeroPad, M.CardGap
	local dayH, plankH = M.HeroDayText + 4, M.PlankH
	local speciesH, wispH = M.SpeciesText + 4, M.WispText + 4
	cell.Day.TextSize, cell.Amount.TextSize = M.HeroDayText, M.PlankText
	cell.Species.TextSize, U.WispText.TextSize = M.SpeciesText, M.WispText
	local side, artX, artY, colX, colW, rowsY
	if S.Mode == "Portrait" then
		side = math.max(12, h - 2 * pad - M.PlinthH)
		artX, artY = pad, pad
		place(cell.Plinth, artX, artY + side, side, M.PlinthH)
		colX = artX + side + M.PetGap
		colW = math.max(20, w - colX - pad)
		-- (a short card, 360 x 640: the species line goes first, then the card's label, so the rows stay inside it)
		local inner = h - 2 * pad
		local rows = plankH + wispH + M.BarH + 2 * g
		cell.SpeciesRoom = rows + speciesH + g <= inner
		rows = rows + (cell.SpeciesRoom and speciesH + g or 0)
		local withDay = rows + dayH + g <= inner
		rows = rows + (withDay and dayH + g or 0)
		cell.Day.Visible = withDay
		cell.Species.Visible = cell.SpeciesRoom and cell.Species.Text ~= ""
		rowsY = math.floor((h - rows) / 2)
		cell.Day.TextXAlignment = Enum.TextXAlignment.Left
		cell.Species.TextXAlignment = Enum.TextXAlignment.Left
		U.WispText.TextXAlignment = Enum.TextXAlignment.Left
		local y = rowsY
		if withDay then
			place(cell.Day, colX, y, colW, dayH)
			y = y + dayH + g
		end
		local nameW = math.min(colW, math.ceil(H.width(cell.Amount.Text ~= "" and cell.Amount.Text or "Week Wisp", M.PlankText, Theme.FontOf(cell.Amount))) + 2 * M.PlankSide)
		place(cell.Amount, colX, y, nameW, plankH)
		y = y + plankH + g
		if cell.SpeciesRoom then
			place(cell.Species, colX, y, colW, speciesH)
			y = y + speciesH + g
		end
		place(U.WispText, colX, y, colW, wispH)
		place(U.WispBar, colX, y + wispH + g, colW, M.BarH)
		local over = cell.SpeciesRoom and speciesH + g or 0
		place(U.Banner, colX, y - over, colW, over + wispH)
	else
		cell.SpeciesRoom = true
		cell.Day.Visible = true
		cell.Day.TextXAlignment = Enum.TextXAlignment.Center
		cell.Species.TextXAlignment = Enum.TextXAlignment.Center
		U.WispText.TextXAlignment = Enum.TextXAlignment.Center
		place(cell.Day, 2, pad, w - 4, dayH)
		-- from the foot up: the bar, the line, the species, the plank, the plinth; the pet fills what is left
		local barY = h - pad - M.BarH
		local wispY = barY - g - wispH
		local speciesY = wispY - g - speciesH
		local plankY = speciesY - g - plankH
		local plinthY = plankY - g - M.PlinthH
		local top = pad + dayH + g
		side = math.max(12, math.min(M.PetMax, w - 2 * pad, plinthY - top))
		artX, artY = math.floor((w - side) / 2), plinthY - side
		local plinthW = math.min(w - 2 * pad, side + 2 * M.PlinthOut)
		place(cell.Plinth, (w - plinthW) / 2, plinthY, plinthW, M.PlinthH)
		place(cell.Amount, M.PlankSide, plankY, w - 2 * M.PlankSide, plankH)
		place(cell.Species, 2, speciesY, w - 4, speciesH)
		place(U.WispText, M.BarSide, wispY, w - 2 * M.BarSide, wispH)
		place(U.WispBar, M.BarSide, barY, w - 2 * M.BarSide, M.BarH)
		place(U.Banner, M.BarSide, speciesY, w - 2 * M.BarSide, speciesH + g + wispH)
		colW = w - 2 * M.BarSide
	end
	place(cell.Art, artX, artY, side, side)
	local sg = M.SegGap
	local segW = (U.WispBar.Size.X.Offset - 6 * sg) / 7
	for i, seg in ipairs(U.Segs) do
		place(seg, (i - 1) * (segW + sg), 0, segW, M.BarH)
	end
	local tick = H.px("Art")
	local check = hostSize(tick)
	cell.Check.TextSize = check
	place(cell.Check, artX + (side - check - 8) / 2, artY + (side - check - 8) / 2, check + 8, check + 8)
	cell.PetPx = side
	cell.ChipPx = math.max(12, math.min(M.ChipPx, side))
	cell.ArtPx = H.rewardPx(cell.ChipPx, M)
	H.placeSparkles(cell.Sparkles, artX, artY, side, side, sparklePx(), SIGN.Tile)
end

-- the streak / VIP chips and the header's width (they follow the payload)
function H.placeChips(M, showStreak, showVip)
	local G = S.G
	local key = table.concat({ tostring(S.Mode), G.W, tostring(showStreak), tostring(showVip), U.StreakChip.Text }, ",")
	if S.ChipKey == key then
		return
	end
	S.ChipKey = key
	local streakW = math.max(M.StreakW, math.ceil(H.width(U.StreakChip.Text, M.ChipText, Theme.FontOf(U.StreakChip))) + 2 * M.ChipPad)
	local vipW = math.max(M.VipW, math.ceil(H.width(U.VipChip.Text, M.ChipText, Theme.FontOf(U.VipChip))) + 2 * M.ChipPad)
	if S.Mode == "Portrait" then
		place(U.DailyHeader, M.Side, M.HeaderY, G.W - 2 * M.Side, M.HeaderH)
		local x = M.Side
		if showStreak then
			place(U.StreakChip, x, M.ChipY, streakW, M.ChipH)
			x = x + streakW + M.ChipGap
		end
		place(U.VipChip, x, M.ChipY, vipW, M.ChipH)
		return
	end
	local right = G.ChipsRight or (G.W - M.Side) -- (Pitch 2 09 B: they end where the day row ends, left of the prize card)
	if showVip then
		right = right - vipW
		place(U.VipChip, right, M.ChipY, vipW, M.ChipH)
		right = right - M.ChipGap
	end
	if showStreak then
		right = right - streakW
		place(U.StreakChip, right, M.ChipY, streakW, M.ChipH)
		right = right - M.ChipGap
	end
	place(U.DailyHeader, M.Side, M.HeaderY, math.max(40, right - M.Side), M.HeaderH)
end

-- the claim slot (`slotW` wide: the repair and the waiting texts take the wider one; the grid's width on a portrait
-- phone) and the keep line: (Pitch 2 09 B) beside the slot on PC and a landscape phone, under it on a portrait phone.
-- The week's line, its bar and the banner sit in the prize card (H.placeHero)
function H.placeBottom(M, slotW)
	local G = S.G
	local key = table.concat({ tostring(S.Mode), G.W, G.B, slotW }, ",")
	if S.BottomKey == key then
		return
	end
	S.BottomKey = key
	slotW = G.ClaimW or slotW
	place(U.Claim, G.ClaimX, G.ClaimY, slotW, G.ClaimH)
	place(U.Countdown, G.ClaimX, G.ClaimY, slotW, G.ClaimH)
	if S.Mode == "Portrait" then
		place(U.Keep, G.KeepX, G.KeepY, G.KeepW, G.KeepH)
		U.Keep.TextXAlignment = Enum.TextXAlignment.Center
		U.Keep.TextYAlignment = Enum.TextYAlignment.Top
	else
		local x = G.ClaimX + slotW + M.ColGap
		local room = math.max(40, G.RowRight - x)
		-- (two even lines where one does not fit: "Claim today's gift to / keep your streak!", no lone last word)
		local font = Theme.FontOf(U.Keep)
		local long = math.max(H.width(TEXT.KeepClaim, M.KeepText, font), H.width(TEXT.Keep, M.KeepText, font))
		local w = long + K.FIT_SLACK <= room and room or math.min(room, math.ceil(long * 0.56))
		place(U.Keep, x, G.ClaimY, w, G.ClaimH)
		U.Keep.TextXAlignment = Enum.TextXAlignment.Left
		U.Keep.TextYAlignment = Enum.TextYAlignment.Center
	end
	-- the locked lines inside the claim button (its UIPadding keeps them off the edges)
	local block = (M.Line1 + 4) + (M.Line2 + 4)
	local top = math.floor((G.ClaimH - block) / 2)
	U.Line1.Position = UDim2.fromOffset(0, top)
	U.Line1.Size = UDim2.new(1, 0, 0, M.Line1 + 4)
	U.Line2.Position = UDim2.fromOffset(0, top + M.Line1 + 4)
	U.Line2.Size = UDim2.new(1, 0, 0, M.Line2 + 4)
end

-- the Play page (card B): the header line and CLAIM ALL on top, then the gift boxes in centred rows of BoxCols (PC: the
-- rows slide from PlayCompact to PlayFull with the body, as the Daily page's parts do)
function H.layoutPlay(M, W, B)
	local portrait = S.Mode == "Portrait"
	local P ={ BoxRowsY = M.BoxRowsY, BoxRowGap = M.BoxRowGap, BoxBottom = M.BoxBottom }
	if S.Mode == "PC" then
		local k = math.max(0, math.min(1, (B - M.CompactBody) / (M.FullBody - M.CompactBody)))
		for name, full in pairs(M.PlayFull) do
			P[name] = math.floor(M.PlayCompact[name] + (full - M.PlayCompact[name]) * k + 0.5)
		end
	end
	local cols = M.BoxCols
	local rows = math.ceil(7 / cols)
	local bw = math.min(M.BoxW, math.floor((W - 2 * M.BoxSide - (cols - 1) * M.BoxGap) / cols))
	if portrait then
		place(U.PlayHeader, M.PlaySide, M.PlayY, W - 2 * M.PlaySide, M.PlayH)
		place(U.ClaimAll, (W - M.AllW) / 2, M.AllY, M.AllW, M.AllH)
	else
		-- (U9-4 look review 2) Claim all ends where the first row of boxes ends (it stood 3 px past them on a phone)
		local rowW = cols * bw + (cols - 1) * M.BoxGap
		local right = math.floor((W - rowW) / 2) + rowW
		place(U.ClaimAll, right - M.AllW, M.AllY, M.AllW, M.AllH)
		place(U.PlayHeader, M.PlaySide, M.PlayY, math.max(40, right - M.AllW - M.AllGap - M.PlaySide), M.PlayH)
	end
	U.PlayHeader.TextWrapped = portrait
	U.ClaimAll.TextSize = M.AllText
	local bh = math.min(M.BoxMaxH, math.floor((B - P.BoxRowsY - (rows - 1) * P.BoxRowGap - P.BoxBottom) / rows))
	local gridH = rows * bh + (rows - 1) * P.BoxRowGap
	local y0 = P.BoxRowsY + math.floor(math.max(0, B - P.BoxRowsY - P.BoxBottom - gridH) / 2)
	place(U.TiersFrame, 0, y0, W, gridH)
	for i, cell in ipairs(U.Tiers) do
		local row = math.floor((i - 1) / cols)
		local inRow = math.min(cols, 7 - row * cols)
		local rowW = inRow * bw + (inRow - 1) * M.BoxGap
		local x = math.floor((W - rowW) / 2) + ((i - 1) % cols) * (bw + M.BoxGap)
		place(cell.Root, x, row * (bh + P.BoxRowGap), bw, bh)
		H.layoutTier(cell, bw, bh, M)
	end
end

-- a gift box's insides, top to bottom with even gaps (the mock's space-between column): the minutes, the gift (as big
-- as the room allows, up to GiftPx), the reward (two lines in a narrow box), the slot (CLAIM / the clock / the tick)
function H.layoutTier(cell, bw, bh, M)
	local inner = bw - 8
	local lines = inner < K.WRAP_BELOW and 2 or 1
	local timeH = M.TimeText + 4
	local rewardH = lines * M.RewardText + 6
	local free = bh - M.BoxPadTop - M.BoxPadBottom - timeH - rewardH - M.SlotH
	-- (the gift gives way first: the three gaps keep BoxMinGap, so the reward never touches the CLAIM button's glow)
	local px = math.max(0, math.min(M.GiftPx, free - 3 * M.BoxMinGap, bw - 12))
	local gap = math.max(0, (free - px) / 3)
	local y = M.BoxPadTop
	place(cell.Time, 4, y, inner, timeH)
	cell.Time.TextSize = M.TimeText
	y = y + timeH + gap
	place(cell.Gift, (bw - px) / 2, y, px, px)
	cell.GiftX, cell.GiftY, cell.GiftPx = cell.Gift.Position.X.Offset, cell.Gift.Position.Y.Offset, px
	-- (kit-b U9-4) the glint round the gift block (a deep gold sparkle reads on the stone box)
	H.placeSparkles(cell.Sparkles, cell.GiftX, cell.GiftY, px, px, sparklePx(), SIGN.GoldDeep)
	y = y + px + gap
	place(cell.Reward, 4, y, inner, rewardH)
	cell.Reward.TextSize = M.RewardText
	cell.Reward.TextWrapped = lines > 1
	cell.Lines = lines
	-- (U9-4 look review 2) the reward's slot (H.placeReward puts a currency on its role's tag in it)
	cell.RewardY, cell.RewardH, cell.RewardKey = math.floor(y + 0.5), rewardH, nil
	local slotY = bh - M.BoxPadBottom - M.SlotH
	cell.SlotY, cell.SlotH, cell.Inner = slotY, M.SlotH, inner
	local btnW = math.min(M.TierBtnW, inner - 8) -- (U9-4 look review: the plank never fills the box edge to edge)
	place(cell.Claim, (bw - btnW) / 2, slotY, btnW, M.SlotH)
	cell.Claim.TextSize = M.TierBtnText
	local pad = cell.Claim:FindFirstChildOfClass("UIPadding")
	if pad then
		-- (a narrow box's Claim keeps its word: 10 px sides would cut it)
		local side = btnW < 80 and 4 or 10
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, side), UDim.new(0, side)
	end
	cell.Clock.TextSize, cell.Glyph.TextSize = M.ClockText, M.ClockText
	-- (U9-4 look review) the tick at the screen's art size, as a day tile's
	local tick = hostSize(H.px("Art"))
	cell.Check.TextSize = tick
	place(cell.Check, (bw - tick - 8) / 2, slotY + (M.SlotH - tick - 8) / 2, tick + 8, tick + 8)
	cell.GiftKey, cell.ClockKey = nil, nil
	cell.BoxW = bw
	-- (U9-4 look review) the next gift's bar: Count blocks across the slot's middle, rebuilt when its size changes
	local TB = K.TIER_BAR[S.Mode == "PC" and "PC" or "Phone"]
	local n = K.TIER_BAR.Count
	local blockW = math.max(6, math.min(TB.MaxW, math.floor((inner - 8 - (n - 1) * TB.Gap) / n)))
	local barKey = blockW .. "x" .. TB.H .. ":" .. TB.Gap
	if not cell.Bar or cell.BarKey ~= barKey then
		if cell.Bar then
			cell.Bar:Destroy()
		end
		cell.Bar = SignKit.BlockRow(cell.Card.Body, { Count = n, BlockW = blockW, BlockH = TB.H, Gap = TB.Gap, Name = "PlayBar", ZIndex = 5, Visible = false })
		for _, d in ipairs(cell.Bar:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = 5
			end
		end
		cell.BarKey = barKey
	end
	cell.BarH = TB.H
end

-- the menu tiles (NimbusMenu draws above this window) step aside while the open window reaches over them, on a
-- phone (or a touch-only device) Roblox's stick and jump go while it is open, and the HUD's vitals card hides
function H.coverColumn()
	local menu = controller("MenuController")
	if menu and type(menu.SetColumnCovered) == "function" then
		safe("cover", menu.SetColumnCovered, (S.Open and U.Holder and S.WindowX) or nil, "Daily")
	end
	local want = S.Open and (S.Mode ~= "PC" or H.touchOnly())
	if want ~= S.TouchOff then
		S.TouchOff = want
		if menu and type(menu.SetTouchHidden) == "function" then
			safe("touch", menu.SetTouchHidden, "Daily", want)
		end
	end
	-- (review fix) the HUD's vitals card steps aside while the window is open: its bottom edge would cut the card (at
	-- 1080p the window covered its top half, at 1280x720 the card's glow showed under the edge)
	local vitalsOff = S.Open == true
	if vitalsOff ~= S.VitalsOff then
		S.VitalsOff = vitalsOff
		local hud = controller("HudController")
		if hud and type(hud.SetVitalsHidden) == "function" then
			safe("vitals", hud.SetVitalsHidden, "Daily", vitalsOff)
		end
	end
end

function H.setTab(tab)
	S.Tab = tab == "Play" and "Play" or "Daily"
	-- (Pitch 2 09 B) on PC the two pages' windows differ in height (H.fitRect): the window is laid out again
	if S.Open and U.Holder and S.Mode == "PC" then
		H.layout()
	end
	H.render()
end

-- (kit-b U9-4) the selected tab the gold block, the other the stone block; brown words on both
function H.paintTab(button, selected)
	button.TextColor3 = SIGN.Text
	button:SetAttribute("Selected", selected)
	local fill = U.Bar:FindFirstChild(button.Name .. "Fill")
	if fill then
		CloudUI.SignBlock(fill, selected and "Selected" or "Stone", { Pad = false })
	end
end

function H.paintArt(cell, entry)
	local px, chipPx = cell.ArtPx or 18, cell.ChipPx or 30
	local artW, artH = cell.Art.Size.X.Offset, cell.Art.Size.Y.Offset
	-- (P2 icons review r1, major 2) the key carries the icon sheet's id: a sheet set after the first draw (render_gui
	-- --sheets, the tests) draws the sheet's art
	local key = tostring(entry.Kind) .. ":" .. tostring(entry.PetId) .. ":" .. px .. ":" .. chipPx .. ":" .. tostring(cell.PetPx) .. ":" .. artW .. "x" .. artH
		.. ":" .. tostring(PixelIcon.SheetId and PixelIcon.SheetId() or 0)
	if cell.ArtKey == key then
		return
	end
	cell.ArtKey = key
	for _, child in ipairs(cell.Art:GetChildren()) do
		child:Destroy()
	end
	if entry.Kind == "Pet" and type(entry.PetId) == "string" then
		local ok = pcall(function()
			local vp = CloudUI.PetViewport(cell.Art, entry.PetId, cell.PetPx or px, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Spin = "sway" })
			vp.Name = "PetViewport"
			vp.ZIndex = 5
		end)
		if ok then
			return
		end
	end
	-- (U9-4 look review) the reward's art centred in the art box at the screen's art size; (look review 2) at a whole-px
	-- offset. (Pitch 2 item 9 B + 09_daily_layout B: "no slot or tile behind the art") the art stands on the tile in its own
	-- colours (the cash bills, the gold coin, the gem; the 18 x 18 art once the icon sheet is uploaded): "Chip" is a clear
	-- holder that keeps the reward's Role (it was a grass / gold / navy kit block behind a one-ink icon)
	local kind = tostring(entry.Kind or "")
	-- (P2 icons review r1, major 2) centred with the art's 1-cell drop shadow (px / 9 on the right and below: the 9 x 9
	-- glyph's cell, the larger of the two) inside the art box: at 54 px on a phone the shadow ran 1 px past it
	local drop = math.ceil(px / 9)
	local chip = Util.Create("Frame", {
		Name = "Chip", BorderSizePixel = 0, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(math.max(0, math.floor((artW - chipPx - drop) / 2)), math.max(0, math.floor((artH - chipPx - drop) / 2))),
		Size = UDim2.fromOffset(chipPx, chipPx), ZIndex = 5, Parent = cell.Art,
	})
	chip:SetAttribute("Role", K.ART_CHIP[kind] and kind or "Other")
	local x, y = math.floor((chipPx - px) / 2), math.floor((chipPx - px) / 2)
	local id = (kind == "Pet" and "Gifts") or (kind == "" and "Gifts") or (kind == "Gems" and "gem") or kind
	local name = NeonKit.IconName(id) or NeonKit.IconName("Gifts") or "gift"
	-- a reward whose icon has no colours of its own (a one-ink glyph) draws in the brown ink of the tile's text
	local icon = PixelIcon.New(chip, name, px, PixelIcon.Art[name] and PixelIcon.Own or SIGN.Text)
	if icon then
		icon.Name = "Icon"
		icon.Position = UDim2.fromOffset(x, y)
		icon.ZIndex = 6
		for _, f in ipairs(icon:GetChildren()) do
			f.ZIndex = 6
		end
	end
end

-- a cell's colour (its lip) and its CELL_LOOK state (the face and the edge), painted only when they change
function H.paintLook(cell, color, look)
	local key = tostring(color) .. "|" .. look
	if cell.LookKey == key then
		return
	end
	cell.LookKey = key
	local L = CELL_LOOK[look] or CELL_LOOK.Open
	cell.Card.SetColor(color)
	cell.Card.SetFill(L.Face)
	cell.Card.Stroke.Color = L.Edge
	cell.Card.Stroke.Transparency = 0
end

-- (U9-4 look review) the pulse of today's tile / a ready box: its edge swaps between the ink and the gold lip, one frame
-- a tick (no tween, never faded)
function H.pulseEdge(cell, lit)
	cell.Card.Stroke.Color = lit and K.PULSE_EDGE or SIGN.Text
	cell.Card.Stroke.Transparency = 0
end

-- (kit-b U9-4) a box's gift: the Gifts button's pink block (its lip, its wood edge) holding the brown pixel gift;
-- redrawn only when its size changes (the tier's own colour is the box's lip). (U9-4 look review 2) the block is the Daily
-- page's reward chip (ChipPx: 72 / 48, a 2 px wood edge, the 4 px lip) and the gift is the art size on it (54 / 36), at
-- whole px: the gift is the hero of the box (a 27 px glyph in an 86 px block read as an empty pink square)
function H.paintGift(cell)
	local px = cell.GiftPx or 0
	local M = H.metrics()
	local key = px .. ":" .. tostring(M.ChipPx)
	if cell.GiftKey == key then
		return
	end
	cell.GiftKey = key
	for _, child in ipairs(cell.Gift:GetChildren()) do
		child:Destroy()
	end
	if px < 12 then
		return
	end
	local side = math.max(12, math.min(M.ChipPx, px - 2 * K.ART_EDGE)) -- room for the 2 px wood edge round it
	local at = math.floor((px - side) / 2)
	local block = Util.Create("Frame", {
		Name = "Block", BackgroundColor3 = SIGN.Roof, BorderSizePixel = 0, Position = UDim2.fromOffset(at, at),
		Size = UDim2.fromOffset(side, side), ZIndex = 5, Parent = cell.Gift,
	})
	CloudUI.SignBlock(block, "Gift", { EdgePx = K.ART_EDGE, LipPx = K.ART_LIP })
	-- (the art size wherever 2 px of face stay over and under it and 4 px each side, else the glyph size)
	local art = (side - K.ART_LIP - H.px("Art") >= 4 and side - H.px("Art") >= 8) and H.px("Art") or H.px("Glyph")
	local icon = PixelIcon.New(block, NeonKit.IconName("Gifts") or "gift", art, SIGN.Text)
	if icon then
		icon.Position = UDim2.fromOffset(math.floor((side - art) / 2), math.floor((side - K.ART_LIP - art) / 2))
		icon.ZIndex = 6
		for _, f in ipairs(icon:GetChildren()) do
			f.ZIndex = 6
		end
	end
end

-- (U9-4 look review 2) a play gift's reward in its slot: a currency on its role's tag (K.REWARD_TAG, sized to its words,
-- centred, the coin / gem at the glyph size before the amount at whole px), any other reward the plain line (two rows in
-- a narrow box); placed again only when the words, the box or the screen change
function H.placeReward(cell, t)
	local M = H.metrics()
	local kind = tostring(t.Kind or "")
	local look = K.REWARD_TAG[kind]
	local texts = tierRewards(t)
	local lbl = cell.Reward
	local key = table.concat({ tostring(S.Mode), kind, texts[1], tostring(cell.BoxW), tostring(cell.RewardY), tostring(cell.RewardH) }, "|")
	if cell.RewardKey == key then
		return
	end
	cell.RewardKey = key
	local old = lbl:FindFirstChild("KindIcon")
	if old then
		old:Destroy()
	end
	if not look then
		for _, name in ipairs({ "SignEdge", "Lip", "LipPad" }) do
			local c = lbl:FindFirstChild(name)
			if c then
				c:Destroy()
			end
		end
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = SIGN.Text
		lbl:SetAttribute("Role", nil)
		place(lbl, 4, cell.RewardY, cell.Inner, cell.RewardH)
		lbl.TextWrapped = cell.Lines > 1
		lbl.Text = H.fitLines(lbl, texts, cell.Lines)
		return
	end
	local glyph = look.Icon and H.px("Glyph") or 0
	local lead = glyph > 0 and glyph + K.TAG_GAP or 0
	local maxW = (cell.BoxW or 0) - 2 * M.BoxMinGap
	lbl.TextSize = M.RewardText
	local text, textW = texts[#texts], 0
	for i, candidate in ipairs(texts) do
		-- (measured as the label draws it, with the Trove tags' 15 % spare: a measure that runs short on the face's wide
		-- digits never cuts the amount)
		local ok, size = pcall(function()
			return Theme.MeasureLabel(lbl, candidate, M.RewardText, 4096)
		end)
		local measured = (ok and typeof(size) == "Vector2") and size.X or H.width(candidate, M.RewardText, Theme.FontOf(lbl))
		textW = math.ceil(measured * 1.15) + K.FIT_SLACK
		if 2 * M.TagPad + lead + textW <= maxW or i == #texts then
			text = candidate
			break
		end
	end
	local w = math.min(maxW, 2 * M.TagPad + lead + textW)
	CloudUI.SignBlock(lbl, { Face = look.Face, Lip = look.Lip, Edge = SIGN.Wood, Text = look.Text }, { EdgePx = K.TAG_EDGE, LipPx = K.TAG_LIP })
	lbl:SetAttribute("Role", kind)
	local pad = lbl:FindFirstChild("LipPad")
	if pad then
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, M.TagPad + lead), UDim.new(0, M.TagPad)
	end
	place(lbl, ((cell.BoxW or 0) - w) / 2, cell.RewardY + math.floor((cell.RewardH - M.TagH) / 2), w, M.TagH)
	lbl.TextWrapped = false
	lbl.Text = text
	if look.Icon then
		-- (the label's padding insets its children too: the icon sits in the lead room left of the text area)
		local icon = PixelIcon.New(lbl, look.Icon, glyph, look.Ink)
		if icon then
			icon.Name = "KindIcon"
			icon.Position = UDim2.fromOffset(-lead, math.floor((M.TagH - K.TAG_LIP - glyph) / 2))
			icon.ZIndex = lbl.ZIndex
			for _, f in ipairs(icon:GetChildren()) do
				f.ZIndex = lbl.ZIndex
			end
		end
	end
end

-- (U9-4 look review 2) the next gift's block bar in the Wisp bar's language (SEG_LOOK, the pitch's .seg): a filled block
-- is the gold face on its gold lip, an empty one the sunk well with no lip; while the clock holds the filled blocks keep
-- their lip under the deep gold face (the stone blocks with a lip used to look more raised than the lipless full ones)
function H.paintTierBar(bar, k, paused)
	k = SignKit.FillBlocks(bar, k)
	for i = 1, bar:GetAttribute("Count") or 0 do
		local face = bar:FindFirstChild("Block" .. i)
		face = face and face:FindFirstChild("Face")
		local lip = face and face:FindFirstChild("Lip")
		if face then
			local on = i <= k
			face.BackgroundColor3 = on and (paused and SIGN.GoldDeep or SIGN.Gold) or SIGN.Well
			if lip then
				lip.BackgroundColor3 = SIGN.GoldLip
				lip.Visible = on
			end
		end
	end
	bar:SetAttribute("Paused", paused)
	return k
end

-- the clock slot: the countdown centred with the clock glyph before it, or alone when both would not fit the box
function H.placeClock(cell, text)
	local barOn = cell.Bar ~= nil and cell.Bar.Visible
	local key = text .. "|" .. tostring(cell.SlotY) .. "|" .. tostring(cell.Inner) .. "|" .. cell.Clock.TextSize .. "|" .. tostring(barOn)
	if cell.ClockKey == key then
		return
	end
	cell.ClockKey = key
	local inner, slotY, slotH = cell.Inner or 0, cell.SlotY or 0, cell.SlotH or 44
	if barOn then
		-- (U9-4 look review) the next gift: its block bar on top of the slot, the countdown under it
		local bar = cell.Bar
		local barW = bar.Size.X.Offset
		place(bar, ((cell.BoxW or inner + 8) - barW) / 2, slotY, barW, cell.BarH or 12)
		local gap = 2
		slotY = slotY + (cell.BarH or 12) + gap
		slotH = slotH - (cell.BarH or 12) - gap
	end
	local size = cell.Clock.TextSize
	local textW = H.width(text, size, Theme.FontOf(cell.Clock))
	local room = size + 8 -- the glyph's box (size + 4) and a 4 px gap
	local withGlyph = text ~= "" and textW + room <= inner - K.FIT_SLACK
	cell.Glyph.Visible = withGlyph
	if withGlyph then
		-- the label is shifted right by the glyph's room, so the glyph + the centred text sit centred together
		place(cell.Clock, 4 + room, slotY, inner - room, slotH)
		place(cell.Glyph, 4 + (inner - textW) / 2 - room / 2, slotY + (slotH - size - 4) / 2, size + 4, size + 4)
	else
		place(cell.Clock, 4, slotY, inner, slotH)
	end
end

-- (Pitch 2 09 B: the line sits in the prize card, under the "Week Wisp" plank) "in 4 more days" / "in 1 more day" /
-- "Yours today!"
function H.wispText(cell)
	local left = 7 - cell
	if left <= 0 then
		return "Yours today!"
	elseif left == 1 then
		return "in 1 more day"
	end
	return "in " .. left .. " more days"
end

-- (Pitch 2 09 B) the prize card's species line: "Epic Owl · Storm" (the catalog's rarity, the look's species, the
-- element; "" for a pet the catalog does not know)
function H.speciesLine(petId)
	local ok, catalog = pcall(function()
		return require(Shared:WaitForChild("PetCatalog", 5))
	end)
	local def = ok and type(catalog) == "table" and catalog.Get and catalog.Get(petId) or nil
	if type(def) ~= "table" then
		return ""
	end
	local look = type(def.Look) == "table" and def.Look.Species or nil
	local head = table.concat({ tostring(def.Rarity or ""), look and tostring(look) or "" }, " "):gsub("^%s+", ""):gsub("%s+$", "")
	if def.Element then
		return head ~= "" and (head .. " " .. DOT .. " " .. tostring(def.Element)) or tostring(def.Element)
	end
	return head
end

function H.renderDaily(st, M)
	local view = DailyController.ClaimView(st, now(), H.touchOnly())
	S.View = view
	local loading = view.Mode == "Loading"
	-- a stale payload (StaleAt passed) promises nothing: no gold today tile, no claim, until the fresh one arrives
	local waiting = loading or view.Mode == "Stale"
	local due = view.Mode == "Claim" or view.Mode == "Repair" or view.Mode == "Locked"
	local cellNo = tonumber(type(st) == "table" and st.Cell) or 1
	if loading then
		U.DailyHeader.Text = "Daily gifts"
	else
		U.DailyHeader.Text = "Day " .. tostring(cellNo) .. " of 7 " .. DOT .. " Week " .. tostring((tonumber(st.Weeks) or 0) + 1)
	end
	local streak = (not loading) and math.floor(tonumber(st.Streak) or 0) or 0
	if S.Mode == "PC" then
		U.StreakChip.Text = "Streak: " .. streak .. (streak == 1 and " day" or " days")
	else
		U.StreakChip.Text = "Streak: " .. streak
	end
	local showVip = not loading and st.Vip == true
	U.StreakChip.Visible = streak > 0
	U.VipChip.Visible = showVip
	H.placeChips(M, streak > 0, showVip)
	-- the tiles
	local list = days(st)
	for i, cell in ipairs(U.Cells) do
		local e = entryAt(list, i)
		local claimed = e.Claimed == true
		local today = e.Today == true and not claimed and not waiting
		H.placeTile(cell, M, today, i == 7)
		cell.Root:SetAttribute("Claimed", claimed)
		cell.Root:SetAttribute("Today", today)
		cell.Root:SetAttribute("Pulsing", today)
		cell.Day.Text = (today and due) and "TODAY" or (i == 7 and TEXT.Prize or ("Day " .. i))
		cell.Dim.Visible = claimed
		cell.Check.Visible = claimed
		-- (F0 review, minor: the mock keeps a claimed day's name and amount brown) the cover dims the art only: the texts
		-- sit over it in the muted ink
		cell.Day.ZIndex = claimed and cell.Dim.ZIndex + 1 or 5
		cell.Amount.ZIndex = claimed and cell.Dim.ZIndex + 1 or 5
		-- (look review r0) the prize card's label in the muted caption ink, as the mock's (TODAY keeps the full ink)
		local prizeLabel = i == 7 and not (today and due)
		cell.Day.TextColor3 = (claimed or prizeLabel) and SIGN.TextMuted or SIGN.Text
		cell.Amount.TextColor3 = claimed and SIGN.TextMuted or SIGN.Text
		if cell.Species then
			-- (Pitch 2 09 B) the prize card: the plank keeps its cream words and its lip rides with it over the cover; the
			-- species line under it
			cell.Amount.TextColor3 = K.PLANK.Text
			local lip = cell.Amount:FindFirstChild("Lip")
			if lip then
				lip.ZIndex = cell.Amount.ZIndex
			end
			cell.Species.ZIndex = cell.Amount.ZIndex
			cell.Species.Text = e.Kind == "Pet" and H.speciesLine(e.PetId) or ""
			cell.Species.Visible = cell.Species.Text ~= "" and cell.SpeciesRoom ~= false
		end
		-- (kit-b U9-4) only a gift the claim takes now glints (a held one, Locked, waits)
		cell.Sparkles.Visible = today and (view.Mode == "Claim" or view.Mode == "Repair")
		H.paintLook(cell, DAY_COLORS[i], today and "Today" or (claimed and "Claimed" or "Open"))
		if today and e.Repair == true then
			-- the claim re-earns this day and pays nothing: no amount, no gift art (re-review 1)
			cell.Amount.Text = "Repair"
			H.paintArt(cell, { Kind = "Repair" })
		elseif e.Kind ~= nil then
			cell.Amount.Text = H.fitText(cell.Amount, cellAmounts(e))
			H.paintArt(cell, e)
		else
			cell.Amount.Text = ""
		end
	end
	-- the Week Wisp line and its bar (the banner takes the line's place while it is up)
	local banner = time() < S.BannerUntil
	U.Banner.Visible = banner
	U.WispText.Text = loading and "" or H.wispText(cellNo)
	U.WispText.Visible = not banner and not loading
	for i, seg in ipairs(U.Segs) do
		local e = entryAt(list, i)
		local state = (e.Claimed == true and "Claimed") or ((e.Today == true and not waiting) and "Today") or "Open"
		if seg:GetAttribute("State") ~= state then
			paintSeg(seg, state)
		end
	end
	-- the claim slot
	local wide = view.Repair == true or view.Mode == "Repair" or waiting
	H.placeBottom(M, wide and M.RepairW or M.ClaimW)
	U.Claim.Visible = due
	U.Countdown.Visible = not due
	U.Claim:SetAttribute("Mode", view.Mode)
	if view.Mode == "Locked" then
		U.Claim.Text = ""
		U.Claim:SetAttribute("Disabled", true)
		U.Line1.Text, U.Line2.Text = view.Line1 or "", view.Line2 or ""
		U.Line1.Visible, U.Line2.Visible = true, true
	else
		U.Claim.Text = (view.Mode == "Repair") and K.REPAIR_TEXT or TEXT.Claim
		U.Claim.TextSize = (view.Mode == "Repair") and M.RepairText or M.ClaimText
		U.Claim:SetAttribute("Disabled", false)
		U.Line1.Visible, U.Line2.Visible = false, false
	end
	U.Countdown.Text = due and "" or (view.Line1 or "")
	U.Keep.Text = due and TEXT.KeepClaim or TEXT.Keep -- (Pitch 2 09 B: by a due claim it says to claim today's gift)
	U.Keep.Visible = not waiting
end

-- the Play page (card B): the header line, CLAIM ALL (n) and the seven gift boxes
function H.renderPlay(st, M)
	local p = play(st)
	local loading = type(st) ~= "table" or st.Loading == true
	local at = now()
	local texts
	if loading then
		texts = { TEXT.PlayLoading }
	elseif p.Active == false then
		-- (on a touch device the stick is hidden while this window is open: only closing it lets the player move)
		texts = H.touchOnly() and TEXT.PlayPausedTouch or TEXT.PlayPausedPC
	else
		local mins = math.floor(H.liveSeconds(st, at) / 60)
		local reset = " " .. DOT .. " Resets in " .. resetText((tonumber(p.DayEnds) or 0) - at)
		texts = { mins .. " min today" .. reset }
		if S.Mode == "PC" then
			texts = { mins .. " min played today" .. reset, texts[1] }
		end
	end
	local paused = not loading and p.Active == false
	Theme.SetRole(U.PlayHeader, paused and "Body" or "Heading") -- (kit-b U6) SetRole keeps Body's Nunito face
	U.PlayHeader.TextColor3 = paused and SIGN.RedLip or SIGN.Text -- (kit-b U9-4) the paused line in the kit's red ink
	U.PlayHeader.TextSize = paused and M.PausedText or M.PlayText
	U.PlayHeader.Text = H.fitLines(U.PlayHeader, texts, S.Mode == "Portrait" and 2 or 1)
	-- CLAIM ALL: the ready count; greyed out at 0, in the same place
	local readyCount = H.readyCount(st)
	U.ClaimAll.Text = string.format(TEXT.ClaimAll, readyCount)
	U.ClaimAll:SetAttribute("Disabled", readyCount == 0)
	local list = tiers(st)
	-- (U9-4 look review) the next gift to open: the first one still locked; its bar fills with the minutes played toward it
	local nextTier = nil
	for i, t in ipairs(list) do
		if nextTier == nil and type(t) == "table" and t.Claimed ~= true and t.Ready ~= true then
			nextTier = i
		end
	end
	local live = H.liveSeconds(st, at)
	for i, cell in ipairs(U.Tiers) do
		local t = list[i]
		cell.Root.Visible = type(t) == "table"
		if type(t) == "table" then
			local color = TIER_COLORS[i] or SIGN.Gold
			cell.Time.Text = tostring(tonumber(t.Min) or 0) .. " min"
			H.placeReward(cell, t)
			H.paintGift(cell)
			local claimed = t.Claimed == true
			local ready = not claimed and t.Ready == true and not loading
			local state = claimed and "Claimed" or (ready and "Ready" or "Locked")
			cell.Root:SetAttribute("State", state)
			cell.Root:SetAttribute("Pulsing", ready)
			cell.Gift:SetAttribute("Bobbing", ready)
			if not ready and cell.GiftY and cell.Gift.Position.Y.Offset ~= cell.GiftY then
				cell.Gift.Position = UDim2.fromOffset(cell.GiftX, cell.GiftY)
			end
			cell.Check.Visible = claimed
			cell.Dim.Visible = claimed
			cell.Claim.Visible = ready
			cell.Sparkles.Visible = ready -- (kit-b U9-4) the ready box glints
			local countdown = state == "Locked" and DailyController.TierCountdown(i, st, at) or ""
			cell.Clock.Text = countdown
			cell.Clock.Visible = countdown ~= ""
			if cell.Bar then
				local on = i == nextTier and countdown ~= "" and not loading
				cell.Bar.Visible = on
				if on then
					local need = math.max(1, (tonumber(t.Min) or 1) * 60)
					H.paintTierBar(cell.Bar, math.floor(K.TIER_BAR.Count * math.min(1, live / need) + 1e-6), paused)
				end
			end
			H.placeClock(cell, countdown)
			H.paintLook(cell, color, state) -- (just ready: the ink edge at once; the tick then swaps it)
			cell.State = state
		end
	end
end

function H.render()
	if not U.Holder or not S.G then
		return
	end
	local M = H.metrics()
	local st = S.State
	H.paintTab(U.TabDaily, S.Tab == "Daily")
	H.paintTab(U.TabPlay, S.Tab == "Play")
	U.DailyPage.Visible = S.Tab == "Daily"
	U.PlayPage.Visible = S.Tab == "Play"
	H.renderDaily(st, M)
	H.renderPlay(st, M)
end

-- 1 s: countdowns, today's pulse, the pip
function H.tick()
	H.refreshPip()
	if not S.Open or not U.Holder then
		return
	end
	H.render()
	S.Pulse = not S.Pulse
	-- (kit-b U9-4) the glints swap their lit sparkle
	for _, list in ipairs({ U.Cells, U.Tiers }) do
		for _, cell in ipairs(list) do
			if cell.Sparkles.Visible then
				H.twinkle(cell.Sparkles, S.Pulse)
			end
		end
	end
	if S.Tab == "Play" then
		-- a ready gift box: its edge pulses (two frames) and its gift bobs
		for _, cell in ipairs(U.Tiers) do
			if cell.Root:GetAttribute("Pulsing") == true then
				H.pulseEdge(cell, S.Pulse)
			end
			if cell.Gift:GetAttribute("Bobbing") == true and cell.GiftY then
				-- (U9-4 look review 2) a two-frame hop on the tick, as the pulse: a tween slid the pixel gift across half pixels
				cell.Gift.Position = UDim2.fromOffset(cell.GiftX, cell.GiftY - (S.Pulse and K.BOB or 0))
			end
		end
		return
	end
	for _, cell in ipairs(U.Cells) do
		if cell.Root:GetAttribute("Pulsing") == true then
			H.pulseEdge(cell, S.Pulse)
		end
	end
end

----------------------------------------------------------------------
-- Moments
----------------------------------------------------------------------
function H.pop(scaleObj)
	if scaleObj then
		scaleObj.Scale = K.POP
		Util.Tween(scaleObj, K.POP_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
end

function H.week()
	S.BannerUntil = time() + K.WEEK_SECONDS
	pcall(SoundFx.Play, "DailyWeek")
	if not (S.Open and U.Fx) or GraphicsQuality.Effective() == "Low" then
		return -- the confetti is High only (the banner and the sound stay)
	end
	-- (kit-b U9-4, finding 26) flat bits in the kit's gold and pink (K.CONFETTI_COLORS); the rainbow sweep band went (a
	-- sheen sweep: kit B has none)
	local fx = U.Fx
	local colors = K.CONFETTI_COLORS
	for i = 1, K.CONFETTI do
		local bit = Instance.new("Frame")
		bit.Name = "Confetti"
		bit.BorderSizePixel = 0
		bit.BackgroundColor3 = colors[(i - 1) % #colors + 1]
		bit.Size = UDim2.fromOffset(8, 12)
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		local x = (i - 0.5) / K.CONFETTI + (math.random() - 0.5) * 0.03
		bit.Position = UDim2.new(x, 0, 0, -8)
		bit.ZIndex = 9
		bit.Parent = fx
		local fall = K.CONFETTI_TIME * (0.7 + 0.3 * math.random())
		Util.Tween(bit, fall, { Position = UDim2.new(x + (math.random() - 0.5) * 0.08, 0, 1, 12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(fall + 0.05, function()
			bit:Destroy()
		end)
	end
end

function H.onState(payload)
	if type(payload) ~= "table" then
		return
	end
	S.State = payload
	if payload.Loading == true then
		S.Last = nil -- a (re)load: the next real payload is a join, it never pops, shakes or celebrates
		H.paintRing()
		H.refreshPip()
		H.render()
		return
	end
	local prev = S.Last
	if prev then
		local popped = false
		local before, after = days(prev), days(payload)
		for i = 1, 7 do
			if entryAt(after, i).Claimed == true and entryAt(before, i).Claimed ~= true then
				popped = true
				if U.Cells[i] then
					H.pop(U.Cells[i].Pop)
				end
			end
		end
		local tb, ta = tiers(prev), tiers(payload)
		local newlyReady = false
		for i = 1, #ta do
			local a, b = entryAt(ta, i), entryAt(tb, i)
			if a.Claimed == true and b.Claimed ~= true then
				popped = true
				if U.Tiers[i] then
					H.pop(U.Tiers[i].Pop)
				end
			end
			if a.Ready == true and a.Claimed ~= true and b.Ready ~= true then
				newlyReady = true
			end
		end
		if popped then
			pcall(SoundFx.Play, "Reward")
		end
		-- the week moment only for a PAID week: DailyService raises Weeks (= floor(Paid / 7)) only when a claim pays a day
		-- 7; a repair claim that climbs back onto a multiple of 7 ("Streak repaired! Day 7 of 7") leaves Weeks alone
		local streak, was = tonumber(payload.Streak) or 0, tonumber(prev.Streak) or 0
		local weeks, wasWeeks = tonumber(payload.Weeks) or 0, tonumber(prev.Weeks) or 0
		if streak > was and weeks > wasWeeks and streak > 0 and streak % 7 == 0 then
			H.week()
		end
		if newlyReady then
			H.shake()
		end
	end
	local back = tonumber(payload.StepBack) or 0
	if back > 0 then
		local key = tostring(back) .. "|" .. tostring(payload.Streak) .. "|" .. tostring(payload.ReadyAt)
		if key ~= S.StepBackKey then
			S.StepBackKey = key
			local menu = controller("MenuController")
			if menu and type(menu.Hint) == "function" then
				local n = math.floor(back)
				pcall(menu.Hint, "Welcome back! You stepped back " .. n .. (n == 1 and " day" or " days") .. ". Keep going!", "info")
			end
		end
	end
	S.Last = payload
	H.paintRing()
	H.refreshPip()
	H.render()
end

function H.send(action, tier)
	local key = action .. tostring(tier or "")
	local t = os.clock()
	if S.LastFire[key] and t - S.LastFire[key] < K.CLAIM_GAP then
		return false
	end
	local ok, remote = pcall(Remotes.Get, "DailyRequest")
	if not ok or not remote then
		return false
	end
	S.LastFire[key] = t
	if tier ~= nil then
		remote:FireServer(action, tier)
	else
		remote:FireServer(action)
	end
	return true
end

-- the claim button: only what the view promises (a stale, waiting or locked view never claims; the server decides anyway)
function H.onClaim()
	if claimable(S.State) then
		H.send("Claim")
	end
end

-- CLAIM ALL: one request for every ready play gift (the server claims each through ClaimPlay's step, one toast)
function H.claimAll()
	if H.readyCount(S.State) > 0 then
		H.send("ClaimPlayAll")
	end
end

function H.syncBack()
	if S.Open and not S.BackBound then
		S.BackBound = true
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					DailyController.Close()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		end)
	elseif not S.Open and S.BackBound then
		S.BackBound = false
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

function H.relayout()
	H.layoutButton()
	if S.Open and U.Holder then
		H.layout()
		U.Holder.Visible = true
		H.render()
		H.coverColumn()
	end
end

function H.onPlayState()
	if S.Open and hiddenByPlay() then
		DailyController.Close()
	end
	H.layoutButton()
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function DailyController.State()
	return S.State
end

function DailyController.IsOpen()
	return S.Open
end

function DailyController.Layout()
	if S.Open and S.Mode then
		return S.Mode
	end
	local r = NeonKit.BigRect(K)
	if r.mode == "Phone" and r.portrait then
		return "Portrait"
	end
	return r.mode
end

-- what the claim slot says (see the header): pure over its arguments
function DailyController.ClaimView(st, at, touch)
	at = tonumber(at) or now()
	if type(st) ~= "table" or st.Loading == true then
		return { Mode = "Loading", Line1 = TEXT.Getting }
	end
	if stale(st, at) then
		return { Mode = "Stale", Line1 = TEXT.Getting }
	end
	local repair = st.Repair == true
	local readyAt = tonumber(st.ReadyAt)
	if readyAt == nil or at < readyAt then
		-- the wait before a claim that only repairs (Repair, re-review 3) never names a gift
		return { Mode = "Wait", Line1 = (repair and "Streak repair in " or "Next gift in ") .. leftText((readyAt or at) - at), Repair = repair or nil }
	end
	local unlock = type(st.Unlock) == "table" and st.Unlock or nil
	local need = unlock and tonumber(unlock.Need) or 0
	local left = unlock and tonumber(unlock.Left) or 0
	if need > 0 and left > 0 then
		local p = play(st)
		-- the seconds left, counted down on the client only while the server counts (Active), from its ServerNow
		local live = left
		if p.Active == true then
			live = left - math.max(0, at - (tonumber(st.ServerNow) or at))
		end
		local dayLeft = (tonumber(p.DayEnds) or 0) - at
		local line2
		if dayLeft > 0 and dayLeft < live then
			line2 = string.format(TEXT.Resets, math.max(1, math.ceil(dayLeft / 60)))
		elseif p.Active == false then
			line2 = touch and TEXT.PausedTouch or TEXT.PausedPC
		else
			line2 = string.format(TEXT.ToGo, math.max(1, math.ceil(live / 60)))
		end
		return { Mode = "Locked", Line1 = string.format(TEXT.Unlock, math.ceil(need / 60)), Line2 = line2, Repair = repair or nil }
	end
	if repair then
		return { Mode = "Repair", Line1 = K.REPAIR_TEXT, Repair = true }
	end
	return { Mode = "Claim", Line1 = TEXT.Claim }
end

-- play tier i's own countdown (see the header): pure over its arguments
function DailyController.TierCountdown(i, st, at)
	if type(st) ~= "table" or st.Loading == true then
		return ""
	end
	local t = tiers(st)[i]
	if type(t) ~= "table" or t.Claimed == true or t.Ready == true then
		return ""
	end
	at = tonumber(at) or now()
	local left = math.max(1, math.ceil((tonumber(t.Min) or 0) * 60 - H.liveSeconds(st, at)))
	if left >= 3600 then
		return math.floor(left / 3600) .. "h " .. math.floor((left % 3600) / 60) .. "m"
	end
	return math.floor(left / 60) .. ":" .. string.format("%02d", left % 60)
end

function DailyController.PipShown()
	local st = S.State
	if type(st) ~= "table" or st.Loading == true or S.Hidden then
		return false
	end
	if not (claimable(st) or tierReady(st)) then
		return false
	end
	if time() - S.SpawnAt < (Config.Daily and Config.Daily.PipDelaySeconds or 20) then
		return false
	end
	return tutorialOk()
end

function DailyController.Open(args)
	if not initialized then
		DailyController.Init()
	end
	if not U.Gui or hiddenByPlay() then
		return false
	end
	args = type(args) == "table" and args or {}
	local wasOpen = S.Open
	if args.Tab == "Play" or args.Tab == "Daily" then
		S.Tab = args.Tab
	elseif not wasOpen then
		S.Tab = (not claimable(S.State) and tierReady(S.State)) and "Play" or "Daily"
	end
	S.Open = true
	-- (review round 2) S.Open hides the button first; a build / layout / render that throws is undone (the window shut,
	-- S.Open false, the button back at once: a phone has no Esc to get out of a half-built window with no button)
	local built = safe("open", function()
		H.layoutButton()
		H.ensureWindow()
		H.layout()
		U.Holder.Visible = true
		H.render()
	end)
	if not built then
		S.Open = false
		if U.Holder then
			U.Holder.Visible = false
		end
		H.syncBack()
		safe("cover", H.coverColumn)
		safe("layout", H.layoutButton)
		return false
	end
	H.syncBack()
	if not wasOpen then
		-- (Pitch 2 F0, finish pass A) the kit's open: the window rises 12 px in 3 hard steps (no scale bounce)
		U.Pop.Scale = 1
		SignKit.Rise(U.Window)
		local menu = controller("MenuController")
		if menu and menu.WindowOpened then
			menu.WindowOpened:Fire("Daily")
		end
		safe("layout", H.layoutButton) -- (win 5) after the windows WindowOpened just closed (owner 2026-11-13: S.Open keeps it hidden)
	end
	H.coverColumn() -- after WindowOpened: the window it closed clears only its own cover
	return true
end

function DailyController.Close()
	if not S.Open then
		return
	end
	S.Open = false
	if U.Holder then
		U.Holder.Visible = false
	end
	H.syncBack()
	H.coverColumn()
	safe("layout", H.layoutButton) -- (owner 2026-11-13) the button, its ring and its pip are back at once
end

function DailyController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	U.Gui = CloudUI.NewScreenGui("NimbusDaily", K.DISPLAY_ORDER)
	-- (LOOK-ui) every kit edge and lip in it, now and later, on whole screen px
	PixelIcon.WholeTree(U.Gui)
	U.Gui.IgnoreGuiInset = false
	H.buildButton()
	S.SpawnAt = time()
	LocalPlayer.CharacterAdded:Connect(function()
		S.SpawnAt = time()
		H.refreshPip()
	end)
	local attr = Config.Attr
	LocalPlayer:GetAttributeChangedSignal(attr.InMatch):Connect(function()
		safe("match", H.onPlayState)
	end)
	LocalPlayer:GetAttributeChangedSignal(attr.InBattle or "InBattle"):Connect(function()
		safe("battle", H.onPlayState)
	end)
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		safe("relayout", H.relayout)
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and S.Open then
			DailyController.Close()
		end
	end)
	local menu = controller("MenuController")
	if menu and menu.WindowOpened then
		menu.WindowOpened:Connect(function(id)
			if id ~= "Daily" then
				if S.Open then
					DailyController.Close()
				end
				-- (win 5) the button steps aside behind the window that opened (deferred: it finishes opening first)
				task.defer(function()
					safe("windows", H.layoutButton)
				end)
			end
		end)
	end
	-- the Shop's open / close (review round 1): the button steps aside while the Shop is up
	local shop = controller("ShopController")
	if type(shop) == "table" and type(shop.Toggled) == "table" and type(shop.Toggled.Connect) == "function" then
		shop.Toggled:Connect(function()
			safe("shop", H.layoutButton)
		end)
	end
	safe("layout", H.layoutButton)
	-- (win 5) no window fires a shared close signal (an X, Esc, another window taking over, a match start): the watcher
	-- re-lays the button out only when the K.WINDOWS answer changes
	task.spawn(function()
		while true do
			task.wait(K.WINDOW_POLL)
			safe("windows", H.watchWindows)
		end
	end)
	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui")
		local hud = pg:WaitForChild("NimbusHud", 30)
		if hud then
			for _, name in ipairs({ "TopRightLeft", "TopRightBottom", "GiftLeft", "GiftTop", "GiftSize" }) do
				hud:GetAttributeChangedSignal(name):Connect(function()
					safe("relayout", H.relayout)
				end)
			end
			safe("relayout", H.relayout)
		end
	end)
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, "DailyState")
		if ok and remote then
			remote.OnClientEvent:Connect(function(payload)
				safe("state", H.onState, payload)
			end)
		end
	end)
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, "TutorialState")
		if ok and remote then
			remote.OnClientEvent:Connect(function(payload)
				if type(payload) == "table" then
					S.Tutorial = payload
					H.refreshPip()
				end
			end)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			safe("tick", H.tick)
		end
	end)
end

return DailyController
