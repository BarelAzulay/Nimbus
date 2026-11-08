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
--         "Claim"   (Line1 "CLAIM!") | "Repair" ("Repair streak (no gift)")
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
--   * TextButton "GiftsButton": round, x = NimbusHud.TopRightLeft - 8 - size, y = 6 (gui px); 56 px at 1080p (x the screen
--     factor), 44 px on a phone; hidden with the strips (InMatch / InBattle, or no top-right strips); re-laid out on the HUD's
--     TopRightLeft / TopRightBottom signals. Children: the Gifts glyph, Frame "Pip" (a 10 px Neon.Red dot: an unlocked
--     claim (ClaimView "Claim" / "Repair") or a ready play tier, >= Config.Daily.PipDelaySeconds after the last
--     CharacterAdded, the tutorial at its spin step or later), a 0.4 s shake when a play tier becomes Ready in a payload
--     that is not the first after a join / Loading one. Frame "Ring" (around the button, attribute Fill = Play.Seconds /
--     the next tier's seconds): two half arcs (RingRight / RingLeft, each a clipped circle whose UIStroke carries a stepped
--     UIGradient), Neon.Gold, 40 % transparent while Play.Active == false. The button, the pip and the ring stay where they
--     were before the window redo.
--   * The window: Frame "DailyHolder" (UIScale "Fit") centred in its NeonKit.BigRect box (RECT 820 x 330 at 390 px high ->
--     1180 x 720 at 1080 px; MARGIN 12, PHONE_W 900, SHORT 560, PC_MIN_H 600, PC_MAX_W 0.76: an 820 x 330 box at 12,59 on a
--     844 x 390 phone, "Phone" at scale 1; "PC" at the screen factor; a phone box taller than wide is "Portrait"). The PC
--     layout is computed in the design box (box px / scale) with card A's 1080p numbers as its largest form. Inside:
--     "DailyWindow" (navy, gold edge, UIScale "Pop" for the 0.22 s Back-Out open) > "TitleBar" (gold: Tab_Daily "Daily",
--     Tab_Play "Play time", the red CloseButton: 56 px PC / 44 px phone, header 76 / 50) and "Body" > DailyPage, PlayPage,
--     Fx. While open on a phone (or a touch-only device) Roblox's stick and jump are hidden (MenuController.
--     SetTouchHidden("Daily", on)), the menu tiles step aside (MenuController.SetColumnCovered(windowLeft, "Daily")) and
--     the HUD's vitals card hides (HudController.SetVitalsHidden("Daily", on): the window's edge would cut it on PC).
--   * DailyPage (card A): Header "Day 3 of 7 . Week 2" (the middle dot), StreakChip "Streak: 9 days" (phone "Streak: 9";
--     hidden at 0), VipChip "VIP x2" (VIP only); Cells > Cell1..7 glossy tiles (NeonKit cards, DAY_COLORS; Day "Day n" or
--     "TODAY" while today's gift is due, Art (glyph or the Week Wisp's PetViewport), Amount, Dim, Check: a big tick on a
--     claimed tile; attributes Claimed / Today / Pulsing). Day 7 is twice a tile plus the gap; today is raised 8 px (same
--     bottom), Neon.Gold, its border pulsing; a Repair payload's today tile reads "Repair" with the Repair glyph. WispText
--     "Week Wisp in N more days" (N = 7 - Cell; "in 1 more day"; Cell 7: "Week Wisp today!") over WispBar (Seg1..7,
--     attribute State = "Claimed" | "Today" | "Open"). ClaimButton (PC 360 x 88 centred, phone 230 x 64 at the right,
--     portrait centred): "CLAIM!", or "Repair streak (no gift)" on the wider repair button; locked: greyed out, disabled,
--     its Line1 / Line2 labels say why (ClaimView). Countdown takes its place while waiting ("Next gift in ...", "Getting
--     your gifts ready..."). Keep "Come back tomorrow to keep your streak!" under it (not while loading / stale).
--     WeekBanner "WEEK DONE! Week Wisp is yours!" takes the Wisp line's place for 4.5 s. Portrait: four tiles a row (Day 7
--     the double tile of row 2), the chips under the header, the claim and the keep line stacked.
--   * PlayPage (card B, gui-redo Task 10, spec 5.4): PlayHeader "47 min played today . Resets in 5h" (phone / portrait "47
--     min today . Resets in 5h"; the minutes are live: Play.Seconds + the time since ServerNow while Active), or Neon.Gold
--     "Paused: move around to keep counting!" while Play.Active == false (a touch-only device: "Paused: close this and
--     move around!", the stick is hidden while the window is open). ClaimAll "CLAIM ALL (n)" (n = the Ready tiers that
--     pay something now: a full Berry Basket, Amount 0, is left to its own box, which reads "Basket is full"; PC
--     252 x 60, phone 166 x 44 at the top right, portrait centred under the header): DailyRequest("ClaimPlayAll"), greyed
--     out at 0 in the same place. Tiers > Tier1..7 gift boxes (NeonKit cards in TIER_COLORS; attributes State = "Ready" |
--     "Claimed" | "Locked", Pulsing): Time "10 min" on top, Gift (an Orb in the tier's colour under the "Gifts" icon;
--     attribute Bobbing: a Ready box's gift bobs and its border pulses on the 1 s tick), Reward (the resolved amount; on a
--     box narrower inside than WRAP_BELOW it takes two lines: "+150" / "Tokens", "Berry" / "Basket"), and one slot: Claim
--     (green "CLAIM": DailyRequest("ClaimPlay", i)), Clock (+ ClockGlyph when it fits: TierCountdown, on the 1 s tick) or
--     Check (claimed: a big tick over the Dim). PC: 260 x 250 boxes at 1080p, four on top and three under, both rows
--     centred (the rows slide from PlayCompact to PlayFull with the body); phone: seven 104 x 204 boxes in one row; portrait:
--     four a row, row 2 centred. Fx: the week's Rainbow Sweep and 24 Confetti frames (both skipped on Low).
--   * A grown claimed set pops the cell or box (1.15 -> 1, 0.25 s) with SoundFx "Reward" (once per payload: CLAIM ALL
--     pops every box it claimed with one sound); a paid week (Weeks rose with the Streak
--     onto a multiple of 7; a repair claim back onto day 7 leaves Weeks alone and celebrates nothing): the sweep, the
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
	PIP = 10,
	RING_PAD = 4, -- the ring sits this far outside the button
	RING_STROKE = 3,
	RING_DIM = 0.4, -- the ring's transparency while the play clock is paused
	SHAKE = { 4, -4, 3, -3, 2, -2, 1, 0 }, -- px offsets, one per SHAKE_STEP (0.4 s)
	SHAKE_STEP = 0.05,
	CLAIM_GAP = 1, -- seconds between two sends of one action
	POP = 1.15,
	POP_TIME = 0.25,
	WEEK_SECONDS = 4.5, -- the week banner stays this long
	CONFETTI = 24,
	CONFETTI_TIME = 1.6,
	PULSE = 0.55, -- today's border fades to this and back, once a second
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
	-- design px per layout. PC: card A at 1080p (body 1180 x 644) is the largest form; the vertical parts slide from Full
	-- (a 644 body) to Compact (a 485 body, the shortest PC box) and the tiles take the rest. Phone: card A on a 844 x 390
	-- phone (body 820 x 280). Portrait: one column, four tiles a row.
	PC = {
		Header = 76, HeadPad = 24, TabY = 12, TabH = 52, TabW = { 170, 200 }, TabGap = 10, TabText = 26, Close = 56, CloseY = 10,
		Side = 28, HeaderY = 18, HeaderH = 44, HeaderText = 34, ChipY = 20, ChipH = 44, ChipText = 22, ChipPad = 18,
		StreakW = 220, VipW = 150, ChipGap = 16, LongStreak = true,
		TileSide = 22, TileGap = 16, TileW = 128, TileMaxH = 260, Raise = 8, PadTop = 12, PadBottom = 14, DayText = 22,
		AmountText = 30, IconPx = 76, PetPx = 150, CheckText = 60,
		WispW = 700, WispText = 24, BannerW = 900, BannerText = 28, SegGap = 6, ClaimW = 360, RepairW = 440, ClaimText = 40,
		RepairText = 32, Line1 = 24, Line2 = 22, CountText = 28, KeepW = 800, KeepText = 22,
		FullBody = 644, CompactBody = 485,
		Full = { TilesY = 96, AfterTiles = 36, WispH = 32, WispGap = 6, BarH = 30, BarGap = 34, ClaimH = 88, ClaimGap = 16, KeepH = 32, Bottom = 14 },
		Compact = { TilesY = 76, AfterTiles = 16, WispH = 30, WispGap = 4, BarH = 20, BarGap = 16, ClaimH = 72, ClaimGap = 8, KeepH = 30, Bottom = 10 },
		-- the Play page (card B at 1080p: body 1180 x 644; the rows slide from PlayCompact to PlayFull like the Daily page)
		PlaySide = 28, PlayY = 18, PlayH = 44, PlayText = 32, PausedText = 26, AllW = 252, AllH = 60, AllY = 12, AllText = 24,
		AllGap = 16, BoxSide = 28, BoxW = 260, BoxMaxH = 250, BoxCols = 4, BoxGap = 28, BoxPadTop = 12, BoxPadBottom = 14,
		TimeText = 24, GiftPx = 110, RewardText = 24, SlotH = 56, TierBtnW = 200, TierBtnText = 24, ClockText = 26, TickText = 40,
		BoxMinGap = 6,
		PlayFull = { BoxRowsY = 92, BoxRowGap = 30, BoxBottom = 22 }, PlayCompact = { BoxRowsY = 80, BoxRowGap = 14, BoxBottom = 10 },
	},
	PHONE = {
		Header = 50, HeadPad = 10, TabY = 3, TabH = 44, TabW = { 110, 140 }, TabGap = 6, TabText = 17, Close = 44, CloseY = 3,
		Side = 14, HeaderY = 6, HeaderH = 30, HeaderText = 18, ChipY = 6, ChipH = 30, ChipText = 15, ChipPad = 10,
		StreakW = 118, VipW = 84, ChipGap = 8,
		TileSide = 14, TileGap = 8, TileW = 92, TileMaxH = 122, TileMinH = 80, Raise = 8, PadTop = 6, PadBottom = 8, DayText = 15,
		AmountText = 17, IconPx = 40, PetPx = 60, CheckText = 36,
		TilesY = 48, AfterTiles = 12, WispH = 22, WispText = 15, WispGap = 4, BarH = 16, BarGap = 8, SegGap = 4, KeepH = 40,
		KeepText = 15, Bottom = 8, ColGap = 16, BannerText = 15, ClaimW = 230, RepairW = 300, ClaimH = 64, ClaimText = 26,
		RepairText = 22, Line1 = 15, Line2 = 15, CountText = 17,
		-- the Play page (card B on a 844 x 390 phone: body 820 x 280, seven boxes in one row)
		PlaySide = 14, PlayY = 2, PlayH = 44, PlayText = 17, PausedText = 15, AllW = 166, AllH = 44, AllY = 2, AllText = 15,
		AllGap = 12, BoxSide = 10, BoxW = 104, BoxMaxH = 204, BoxCols = 7, BoxGap = 12, BoxRowsY = 58, BoxRowGap = 0,
		BoxBottom = 6, BoxPadTop = 6, BoxPadBottom = 6, TimeText = 15, GiftPx = 52, RewardText = 15, SlotH = 44, TierBtnW = 92,
		TierBtnText = 16, ClockText = 16, TickText = 28, BoxMinGap = 4,
	},
	PORTRAIT = {
		Header = 50, HeadPad = 10, TabY = 3, TabH = 44, TabW = { 110, 140 }, TabGap = 6, TabText = 17, Close = 44, CloseY = 3,
		Side = 10, HeaderY = 4, HeaderH = 26, HeaderText = 18, ChipY = 34, ChipH = 28, ChipText = 15, ChipPad = 10,
		StreakW = 104, VipW = 84, ChipGap = 8,
		TileGap = 8, TileW = 92, TileMaxH = 122, TileMinH = 64, Raise = 8, PadTop = 3, PadBottom = 4, DayText = 15,
		AmountText = 15, IconPx = 28, PetPx = 44, CheckText = 28,
		TilesY = 72, RowGap = 12, AfterTiles = 12, WispH = 22, WispText = 15, WispGap = 4, BarH = 14, BarGap = 10, SegGap = 4,
		ClaimH = 64, ClaimGap = 8, KeepH = 40, KeepText = 15, Bottom = 6, BannerText = 15, ClaimW = 230, RepairW = 300,
		ClaimText = 26, RepairText = 22, Line1 = 15, Line2 = 15, CountText = 17,
		-- the Play page: the header on two lines, CLAIM ALL centred under it, four boxes a row
		PlaySide = 10, PlayY = 4, PlayH = 40, PlayText = 17, PausedText = 15, AllW = 166, AllH = 44, AllY = 48, AllText = 15,
		AllGap = 0, BoxSide = 8, BoxW = 104, BoxMaxH = 204, BoxCols = 4, BoxGap = 6, BoxRowsY = 100, BoxRowGap = 10,
		BoxBottom = 6, BoxPadTop = 4, BoxPadBottom = 4, TimeText = 15, GiftPx = 52, RewardText = 15, SlotH = 44, TierBtnW = 92,
		TierBtnText = 15, ClockText = 15, TickText = 28, BoxMinGap = 4,
	},
}
DailyController.K = K

-- the window's words (spec 5.3)
local TEXT = {
	Claim = "CLAIM!",
	Getting = "Getting your gifts ready...",
	Keep = "Come back tomorrow to keep your streak!",
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
	ClaimAll = "CLAIM ALL (%d)",
	ClockGlyph = "\226\143\176", -- alarm clock
}

-- the owner's colourful cells (kept here, not in Theme): one saturated colour per day (today is Neon.Gold) and per tier
local DAY_COLORS = {
	Color3.fromRGB(72, 224, 120), -- green
	Color3.fromRGB(64, 226, 236), -- cyan
	Color3.fromRGB(64, 150, 255), -- blue
	Color3.fromRGB(176, 104, 255), -- purple
	Color3.fromRGB(255, 92, 200), -- pink
	Color3.fromRGB(255, 140, 40), -- orange
	Color3.fromRGB(255, 76, 100), -- red (the Week Wisp)
}
local TIER_COLORS = {
	Color3.fromRGB(64, 226, 236), -- 10 min: cyan
	Color3.fromRGB(72, 224, 120), -- green
	Color3.fromRGB(64, 150, 255), -- blue
	Color3.fromRGB(176, 104, 255), -- purple
	Color3.fromRGB(255, 92, 200), -- pink
	Color3.fromRGB(255, 140, 40), -- orange
	Color3.fromRGB(255, 200, 50), -- 3 h: gold
}
DailyController.DayColors = DAY_COLORS
DailyController.TierColors = TIER_COLORS
-- a cell's fill gradient (top, bottom: Theme.Darken amounts) and outline transparency per state
local CELL_LOOK = {
	Today = { 0.25, 0.7, 0 },
	Open = { 0.4, 0.8, 0 },
	Ready = { 0.2, 0.62, 0 },
	Locked = { 0.45, 0.8, 0.35 },
	Claimed = { 0.45, 0.8, 0.5 },
}

local DOT = "\194\183"
local CHECK = "\226\156\148"
local WHITE = Theme.Colors.White
local GOLD = Theme.Neon.Gold
local INK = Theme.Colors.PanelInk or Color3.fromRGB(8, 10, 28)
local MUTED = Theme.Colors.Muted or Color3.fromRGB(212, 224, 246)
local NAVY = Color3.fromRGB(11, 16, 48)
local SEG_OFF = Color3.fromRGB(30, 38, 86)

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
	TouchOff = false,
	VitalsOff = false, -- the HUD's vitals card is hidden for this window (H.coverColumn)
}
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

local function commas(n)
	return Util.Commas(math.floor(tonumber(n) or 0))
end

local function label(name, text, role, size, parent, props)
	local l = Theme.Label(text or "", role, { Size = size, Stroke = 0.5, Outline = 1.5 })
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
	return Theme.ShortNumber(math.floor(tonumber(n) or 0), 1000)
end

-- a pet's name and its last word ("Week Wisp", "Wisp")
local function petNames(petId)
	local name = petName(petId)
	return { name, string.match(name, "(%S+)%s*$") or name }
end

-- the short amount of a cell, the longest form first ("$1,450", "50", "Week Wisp" / "Wisp", "$1,234,567" / "$1.2M")
local function cellAmounts(entry)
	local kind = entry.Kind
	if kind == "Cash" then
		return { "$" .. commas(entry.Amount), "$" .. short(entry.Amount) }
	elseif kind == "Pet" then
		return petNames(entry.PetId)
	elseif kind == "Berries" then
		return { "Berries" }
	end
	return { commas(entry.Amount), short(entry.Amount) }
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

-- the words of a play tier's reward, the longest form first ("+$200", "+40 Tokens", "Full Berry Basket" / "Berry Basket"
-- / "Full Basket"; a full Basket, Amount 0: "Basket is full" / "Basket full")
local function tierRewards(tier)
	local kind = tier.Kind
	if kind == "Cash" then
		return { "+$" .. commas(tier.Amount), "+$" .. short(tier.Amount) }
	elseif kind == "Tokens" or kind == "Gems" then
		return { "+" .. commas(tier.Amount) .. " " .. kind, "+" .. short(tier.Amount) .. " " .. kind, "+" .. short(tier.Amount) }
	elseif kind == "Berries" and paysNothing(tier) then
		return { "Basket is full", "Basket full" }
	elseif kind == "Berries" then
		return { "Full Berry Basket", "Berry Basket", "Full Basket" }
	elseif kind == "Pet" then
		return petNames(tier.PetId)
	end
	return { "+" .. commas(tier.Amount), "+" .. short(tier.Amount) }
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

-- the first of `texts` that fits the label's box (its design width less FIT_SLACK) at its size and font, measured by
-- TextService (the real font: a cell's text is never cut to "Week W..."); the last one when none does
function H.fitText(lbl, texts)
	local width = lbl.Size.X.Offset - K.FIT_SLACK
	for i = 1, #texts - 1 do
		local ok, size = pcall(function()
			return TextService:GetTextSize(texts[i], lbl.TextSize, lbl.Font, Vector2.new(4096, 1024))
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
		return TextService:GetTextSize(text, size, font, Vector2.new(4096, 1024))
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
		if H.rows(texts[i], lbl.TextSize, lbl.Font, width) <= lines then
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

function H.buildButton()
	local size = H.buttonSize()
	local card = NeonKit.Card({
		Name = "GiftsButton", Class = "TextButton", Color = "Gold", Size = size, Corner = math.floor(size / 2),
		Floor = false, Sheen = false, ZIndex = 2, Parent = U.Gui,
	})
	U.Button = card.Root
	U.ButtonCard = card
	U.Icon = NeonKit.Icon(card.Body, "Gifts", math.floor(size * 0.5))
	U.Icon.Size = UDim2.fromScale(0.9, 0.9)
	U.Icon.TextScaled = true
	U.Icon.ZIndex = 3
	-- the ring: two clipped halves of one circle, each stroke under a stepped gradient (spec 8: "fills toward the next tier")
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 3
	ring.Parent = U.Gui
	U.Ring = ring
	U.Arcs = {}
	for i, side in ipairs({ "RingRight", "RingLeft" }) do
		local half = Instance.new("Frame")
		half.Name = side
		half.BackgroundTransparency = 1
		half.BorderSizePixel = 0
		half.ClipsDescendants = true
		half.Size = UDim2.fromScale(0.5, 1)
		half.Position = UDim2.fromScale(i == 1 and 0.5 or 0, 0)
		half.ZIndex = 3
		half.Parent = ring
		local arc = Instance.new("Frame")
		arc.Name = "Arc"
		arc.BackgroundTransparency = 1
		arc.BorderSizePixel = 0
		arc.Size = UDim2.fromScale(2, 1)
		arc.Position = UDim2.fromScale(i == 1 and -1 or 0, 0)
		arc.ZIndex = 3
		arc.Parent = half
		Theme.Corner(arc, UDim.new(0.5, 0))
		local stroke = Instance.new("UIStroke")
		stroke.Name = "RingStroke"
		stroke.Color = GOLD
		stroke.Thickness = K.RING_STROKE
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = arc
		local grad = Instance.new("UIGradient")
		grad.Name = "Step"
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1), NumberSequenceKeypoint.new(1, 1),
		})
		grad.Parent = stroke
		U.Arcs[i] = { Stroke = stroke, Gradient = grad }
	end
	local pip = Instance.new("Frame")
	pip.Name = "Pip"
	pip.BackgroundColor3 = Theme.Neon.Red
	pip.BorderSizePixel = 0
	pip.AnchorPoint = Vector2.new(0.5, 0.5)
	pip.Position = UDim2.new(1, -4, 0, 4)
	pip.Size = UDim2.fromOffset(K.PIP, K.PIP)
	pip.ZIndex = 5
	pip.Visible = false
	Theme.Corner(pip, UDim.new(0.5, 0))
	pip.Parent = U.Button
	U.Pip = pip
	U.Button.Activated:Connect(function()
		if S.Open then
			DailyController.Close()
		else
			DailyController.Open()
		end
	end)
end

function H.paintRing()
	if not U.Ring then
		return
	end
	local st = S.State
	local fill = ringFill(st)
	U.Ring:SetAttribute("Fill", fill)
	local right = math.min(fill, 0.5) * 360
	local left = 180 + math.max(0, math.min(fill - 0.5, 0.5)) * 360
	local paused = type(st) == "table" and st.Loading ~= true and play(st).Active == false
	for i, arc in ipairs(U.Arcs) do
		arc.Gradient.Rotation = i == 1 and right or left
		arc.Stroke.Transparency = paused and K.RING_DIM or 0
	end
	U.Ring.Visible = not S.Hidden and type(st) == "table" and st.Loading ~= true and #tiers(st) > 0
end

-- (lobby-shop review round 1) the Shop window (NimbusShop, the same DisplayOrder 19, Shop A's wide rect) covers the
-- button's corner: the button, its ring and its pip hide while the Shop is open (ShopController.Toggled re-lays it out)
function H.shopUp()
	local shop = controller("ShopController")
	if type(shop) ~= "table" or type(shop.IsOpen) ~= "function" then
		return false
	end
	local ok, open = pcall(shop.IsOpen)
	return ok and open == true
end

function H.layoutButton()
	if not U.Button then
		return
	end
	local size = H.buttonSize()
	local hud = H.hud()
	local left = tonumber(hud and hud:GetAttribute("TopRightLeft")) or 0
	S.Hidden = left <= 0 or hiddenByPlay() or H.shopUp()
	local x = math.floor(left - K.GAP - size + 0.5)
	U.Button.Size = UDim2.fromOffset(size, size)
	U.Button.Position = UDim2.fromOffset(x + S.ShakeX, K.TOP)
	U.ButtonCard.Root:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, math.floor(size / 2))
	U.Button.Visible = not S.Hidden
	local r = size + 2 * K.RING_PAD
	U.Ring.Size = UDim2.fromOffset(r, r)
	U.Ring.Position = UDim2.fromOffset(x + S.ShakeX - K.RING_PAD, K.TOP - K.RING_PAD)
	H.paintRing()
	if S.Hidden then
		U.Ring.Visible = false
	end
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
-- a tab: its fill is a sibling frame under the (transparent) button, so the fill's gradient never tints the text
function H.tabButton(name, text)
	local fill = Instance.new("Frame")
	fill.Name = name .. "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = WHITE
	fill.ZIndex = 5
	Theme.Corner(fill, UDim.new(0, 12))
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TabStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = WHITE
	stroke.Parent = fill
	local grad = Instance.new("UIGradient")
	grad.Name = "TabFill"
	grad.Rotation = 90
	grad.Parent = fill
	fill.Parent = U.Bar
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundTransparency = 1
	b.Text = text
	b.ZIndex = 6
	Theme.Style(b, "Button", { Size = 17, Stroke = 0.6, Outline = 1.5 })
	b.Parent = U.Bar
	return b
end

-- a dark pill with a light edge (the streak and VIP chips)
function H.chip(name, color, parent)
	local c = label(name, "", "Heading", 15, parent, {
		TextColor3 = color, BackgroundTransparency = 0.35, BackgroundColor3 = INK, TextWrapped = false, ZIndex = 5,
	})
	Theme.Corner(c, UDim.new(0.5, 0))
	Theme.Stroke(c, WHITE, 2, 0.75)
	return c
end

function H.newCell(i, parent)
	local c = NeonKit.Card({ Name = "Cell" .. i, Color = DAY_COLORS[i], Size = UDim2.fromOffset(92, 122), Floor = true, Corner = 12, ZIndex = 4, Parent = parent })
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = c.Root
	local day = label("Day", "Day " .. i, "Label", 15, c.Body, { TextWrapped = false, ZIndex = 5 })
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.ZIndex = 5
	art.Parent = c.Body
	local amount = label("Amount", "", "Display", 17, c.Body, { TextWrapped = false, ZIndex = 5 })
	amount.TextTruncate = Enum.TextTruncate.AtEnd
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = INK
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 6
	dim.Visible = false
	Theme.Corner(dim, UDim.new(0, 12))
	dim.Parent = c.Body
	local check = label("Check", CHECK, "Title", 36, c.Body, { TextColor3 = Theme.Neon.Green, ZIndex = 7, Visible = false, TextWrapped = false })
	U.Cells[i] = { Card = c, Root = c.Root, Pop = pop, Day = day, Art = art, Amount = amount, Dim = dim, Check = check, ArtKey = nil, LookKey = nil }
end

-- a play-time gift box (card B): the minutes, the gift, the reward and one slot (CLAIM, the clock or the tick)
function H.newTier(i, parent)
	local c = NeonKit.Card({ Name = "Tier" .. i, Color = TIER_COLORS[i], Size = UDim2.fromOffset(104, 204), Floor = true, Corner = 12, ZIndex = 4, Parent = parent })
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = c.Root
	local timeLabel = label("Time", "", "Heading", 15, c.Body, { TextWrapped = false, ZIndex = 5 })
	local gift = Util.Create("Frame", { Name = "Gift", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5, Parent = c.Body })
	gift:SetAttribute("Bobbing", false)
	local reward = label("Reward", "", "Display", 15, c.Body, { TextWrapped = false, ZIndex = 5 })
	reward.TextTruncate = Enum.TextTruncate.AtEnd
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = INK
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 6
	dim.Visible = false
	Theme.Corner(dim, UDim.new(0, 12))
	dim.Parent = c.Body
	local clock = label("Clock", "", "Display", 16, c.Body, { TextColor3 = WHITE, TextWrapped = false, ZIndex = 5, Visible = false })
	local glyph = label("ClockGlyph", TEXT.ClockGlyph, "Display", 16, c.Body, { TextWrapped = false, ZIndex = 5, Visible = false })
	local check = label("Check", CHECK, "Title", 28, c.Body, { TextColor3 = Theme.Neon.Green, ZIndex = 7, TextWrapped = false, Visible = false })
	local claim = NeonKit.Button({ Name = "Claim", Text = "CLAIM", Color = "Green", Size = UDim2.fromOffset(92, 44), TextSize = 16,
		Parent = c.Body, Callback = function()
			H.send("ClaimPlay", i)
		end })
	claim.ZIndex = 8
	U.Tiers[i] = { Card = c, Root = c.Root, Pop = pop, Time = timeLabel, Gift = gift, Reward = reward, Dim = dim, Clock = clock,
		Glyph = glyph, Check = check, Claim = claim, GiftKey = nil, ClockKey = nil, LookKey = nil }
end

function H.ensureWindow()
	if U.Holder then
		return
	end
	U.Cells, U.Tiers, U.Segs = {}, {}, {}
	local holder = Util.Create("Frame", { Name = "DailyHolder", BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 4, Parent = U.Gui })
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	local win = Util.Create("Frame", {
		Name = "DailyWindow", BackgroundColor3 = NAVY, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = holder,
	})
	Theme.Corner(win, UDim.new(0, 18))
	Theme.Stroke(win, GOLD, 3, 0)
	U.Window = win
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = win })
	-- the gold title bar (square at the bottom)
	local bar = Util.Create("Frame", { Name = "TitleBar", BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 5, Parent = win })
	Theme.Corner(bar, UDim.new(0, 18))
	Theme.Gradient(bar, Theme.Lighten(GOLD, 0.12), Theme.Darken(GOLD, 0.3), 90)
	U.Bar = bar
	U.BarFoot = Util.Create("Frame", { Name = "TitleFoot", BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 5, Parent = bar })
	Theme.Gradient(U.BarFoot, Theme.Lighten(GOLD, 0.12):Lerp(Theme.Darken(GOLD, 0.3), 0.76), Theme.Darken(GOLD, 0.3), 90)
	U.TabDaily = H.tabButton("Tab_Daily", "Daily")
	U.TabPlay = H.tabButton("Tab_Play", "Play time")
	U.TabDaily.Activated:Connect(function()
		H.setTab("Daily")
	end)
	U.TabPlay.Activated:Connect(function()
		H.setTab("Play")
	end)
	U.Close = NeonKit.Button({ Name = "CloseButton", Text = NeonKit.Glyphs.Close, Color = "Red", Size = 44, TextSize = 22, Parent = bar, Callback = function()
		DailyController.Close()
	end })
	U.Close.ZIndex = 7
	U.Body = Util.Create("Frame", { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 4, Parent = win })

	-- the Daily page (card A)
	local daily = Util.Create("Frame", { Name = "DailyPage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = U.Body })
	U.DailyPage = daily
	U.DailyHeader = label("Header", "", "Title", 18, daily, { TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, ZIndex = 5 })
	U.StreakChip = H.chip("StreakChip", WHITE, daily)
	U.VipChip = H.chip("VipChip", GOLD, daily)
	U.VipChip.Text = "VIP x2"
	U.CellsFrame = Util.Create("Frame", { Name = "Cells", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = daily })
	for i = 1, 7 do
		H.newCell(i, U.CellsFrame)
	end
	U.WispText = label("WispText", "", "Heading", 15, daily, { TextWrapped = false, ZIndex = 5 })
	U.WispBar = Util.Create("Frame", { Name = "WispBar", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5, Parent = daily })
	for i = 1, 7 do
		local seg = Util.Create("Frame", { Name = "Seg" .. i, BackgroundColor3 = SEG_OFF, BorderSizePixel = 0, ZIndex = 6, Parent = U.WispBar })
		Theme.Corner(seg, UDim.new(0, 6))
		Theme.Stroke(seg, INK, 2, 0)
		seg:SetAttribute("State", "Open")
		U.Segs[i] = seg
	end
	U.Claim = NeonKit.Button({ Name = "ClaimButton", Text = TEXT.Claim, Color = "Green", Size = UDim2.fromOffset(360, 88), TextSize = 40, ZIndex = 6, Parent = daily,
		Callback = function()
			H.onClaim()
		end })
	U.Line1 = label("Line1", "", "Body", 15, U.Claim, { TextWrapped = false, Visible = false, ZIndex = 9 })
	U.Line2 = label("Line2", "", "Body", 15, U.Claim, { TextWrapped = false, Visible = false, ZIndex = 9, TextColor3 = MUTED })
	U.Countdown = label("Countdown", "", "Heading", 17, daily, { ZIndex = 5 })
	U.Keep = label("Keep", TEXT.Keep, "Body", 15, daily, { TextColor3 = MUTED, ZIndex = 5, TextYAlignment = Enum.TextYAlignment.Top })
	U.Banner = label("WeekBanner", TEXT.Week, "Title", 15, daily, { TextColor3 = GOLD, Visible = false, ZIndex = 5 })

	-- the Play page (card B: the header line, CLAIM ALL, seven gift boxes)
	local playPage = Util.Create("Frame", { Name = "PlayPage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 4, Parent = U.Body })
	U.PlayPage = playPage
	U.PlayHeader = label("PlayHeader", "", "Heading", 17, playPage, { TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, ZIndex = 5 })
	U.ClaimAll = NeonKit.Button({ Name = "ClaimAll", Text = string.format(TEXT.ClaimAll, 0), Color = "Green", Size = UDim2.fromOffset(166, 44), TextSize = 15,
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

-- the box (NeonKit.BigRect) -> the holder at its place and scale, then every part in the design box
function H.layout()
	if not U.Holder then
		return
	end
	local r = NeonKit.BigRect(K)
	local mode = r.mode
	if mode == "Phone" and r.portrait then
		mode = "Portrait"
	end
	S.Rect, S.Mode, S.Scale = r, mode, r.scale
	local W = math.floor(r.w / r.scale + 0.5)
	local Hh = math.floor(r.h / r.scale + 0.5)
	-- (NimbusDaily keeps the gui inset: its area starts under the top bar)
	place(U.Holder, r.x, r.y - H.inset(), W, Hh)
	U.Fit.Scale = r.scale
	S.WindowX = math.floor(r.x + 0.5)
	local M = H.metrics()
	place(U.Bar, 0, 0, W, M.Header)
	place(U.BarFoot, 0, M.Header - 18, W, 18)
	for i, tab in ipairs({ U.TabDaily, U.TabPlay }) do
		local x = M.HeadPad + (i == 2 and (M.TabW[1] + M.TabGap) or 0)
		place(tab, x, M.TabY, M.TabW[i], M.TabH)
		place(U.Bar:FindFirstChild(tab.Name .. "Fill"), x, M.TabY, M.TabW[i], M.TabH)
	end
	U.TabDaily.TextSize, U.TabPlay.TextSize = M.TabText, M.TabText
	place(U.Close, W - M.HeadPad - M.Close, M.CloseY, M.Close, M.Close)
	U.Close.TextSize = math.floor(M.Close * 0.5)
	local B = Hh - M.Header
	place(U.Body, 0, M.Header, W, B)
	H.layoutDaily(M, W, B)
	H.layoutPlay(M, W, B)
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
	local spots = {}
	local tw, th, x0, gap, tilesY
	if S.Mode == "Portrait" then
		gap = M.TileGap
		tw = math.min(M.TileW, math.floor((W - 2 * M.Side - 3 * gap) / 4))
		local after = M.AfterTiles + M.WispH + M.WispGap + M.BarH + M.BarGap + M.ClaimH + M.ClaimGap + M.KeepH + M.Bottom
		th = math.max(M.TileMinH, math.min(M.TileMaxH, math.floor((B - M.TilesY - M.RowGap - after) / 2)))
		local extra = math.max(0, B - (M.TilesY + 2 * th + M.RowGap + after))
		tilesY = M.TilesY + math.floor(extra / 2)
		x0 = math.floor((W - (4 * tw + 3 * gap)) / 2)
		for i = 1, 7 do
			local row = i <= 4 and 0 or 1
			local col = i <= 4 and (i - 1) or (i - 5)
			spots[i] = { x = col * (tw + gap), y = M.Raise + row * (th + M.RowGap), w = i == 7 and (2 * tw + gap) or tw, h = th }
		end
		place(U.CellsFrame, x0, tilesY - M.Raise, 4 * tw + 3 * gap, 2 * th + M.RowGap + M.Raise)
		G.Y0 = tilesY + 2 * th + M.RowGap + M.AfterTiles
		G.ClaimY = G.Y0 + M.WispH + M.WispGap + M.BarH + M.BarGap
		G.KeepY = G.ClaimY + M.ClaimH + M.ClaimGap
		G.ClaimH, G.KeepH = M.ClaimH, M.KeepH
	else
		gap = M.TileGap
		tw = math.min(M.TileW, math.floor((W - 2 * M.TileSide - 7 * gap) / 8))
		local P = {}
		if S.Mode == "PC" then
			-- the vertical parts slide from Compact to Full with the body; the tiles take the rest
			local k = math.max(0, math.min(1, (B - M.CompactBody) / (M.FullBody - M.CompactBody)))
			for name, full in pairs(M.Full) do
				P[name] = math.floor(M.Compact[name] + (full - M.Compact[name]) * k + 0.5)
			end
		else
			for _, name in ipairs({ "TilesY", "AfterTiles", "WispH", "WispGap", "BarH", "BarGap", "ClaimH", "KeepH", "Bottom" }) do
				P[name] = M[name]
			end
			P.ClaimGap = 0
		end
		local fixed
		if S.Mode == "PC" then
			fixed = P.TilesY + P.AfterTiles + P.WispH + P.WispGap + P.BarH + P.BarGap + P.ClaimH + P.ClaimGap + P.KeepH + P.Bottom
		else
			-- phone: the claim sits beside the Wisp line, the bar and the keep line
			fixed = P.TilesY + P.AfterTiles + P.WispH + P.WispGap + P.BarH + P.BarGap + P.KeepH + P.Bottom
		end
		th = math.max(M.TileMinH or 0, math.min(M.TileMaxH, B - fixed))
		local extra = math.max(0, B - fixed - th)
		tilesY = P.TilesY + math.floor(extra / 2)
		x0 = math.floor((W - (8 * tw + 7 * gap)) / 2)
		for i = 1, 7 do
			spots[i] = { x = (i - 1) * (tw + gap), y = M.Raise, w = i == 7 and (2 * tw + gap) or tw, h = th }
		end
		place(U.CellsFrame, x0, tilesY - M.Raise, 8 * tw + 7 * gap, th + M.Raise)
		G.Y0 = tilesY + th + P.AfterTiles
		G.WispH, G.WispGap, G.BarH, G.BarGap = P.WispH, P.WispGap, P.BarH, P.BarGap
		G.ClaimH, G.KeepH = P.ClaimH, P.KeepH
		G.ClaimY = G.Y0 + P.WispH + P.WispGap + P.BarH + P.BarGap
		G.KeepY = G.ClaimY + P.ClaimH + P.ClaimGap
		if S.Mode ~= "PC" then
			-- (phone: the keep line under the bar; the claim slot beside the three, from the Wisp line's top)
			G.KeepY = G.ClaimY
			G.ClaimY = G.Y0 + 2
			if B < G.KeepY + M.KeepH + 2 then
				G.KeepH = math.max(M.KeepText + 6, B - G.KeepY - 2)
			end
		end
	end
	G.WispH = G.WispH or M.WispH
	G.WispGap = G.WispGap or M.WispGap
	G.BarH = G.BarH or M.BarH
	G.BarGap = G.BarGap or M.BarGap
	G.TileW = tw
	for i, cell in ipairs(U.Cells) do
		cell.Spot = spots[i]
		cell.PlaceKey = nil
	end
end

-- a tile at its spot (today: raised by M.Raise, the bottom kept), its insides fitted to its size
function H.placeTile(cell, M, today, wide)
	local s = cell.Spot
	if not s then
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
	local check = math.max(15, math.min(M.CheckText, math.floor(math.min(w, h) * 0.5)))
	cell.Check.TextSize = check
	place(cell.Check, (w - check - 8) / 2, (h - check - 8) / 2, check + 8, check + 8)
	cell.ArtPx = math.max(12, math.min(wide and M.PetPx or M.IconPx, artH, w - 8))
end

-- the streak / VIP chips and the header's width (they follow the payload)
function H.placeChips(M, showStreak, showVip)
	local G = S.G
	local key = table.concat({ tostring(S.Mode), G.W, tostring(showStreak), tostring(showVip), U.StreakChip.Text }, ",")
	if S.ChipKey == key then
		return
	end
	S.ChipKey = key
	local streakW = math.max(M.StreakW, math.ceil(H.width(U.StreakChip.Text, M.ChipText, U.StreakChip.Font)) + 2 * M.ChipPad)
	local vipW = math.max(M.VipW, math.ceil(H.width(U.VipChip.Text, M.ChipText, U.VipChip.Font)) + 2 * M.ChipPad)
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
	local right = G.W - M.Side
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

-- the Wisp line, the bar, the claim slot (`slotW` wide: the repair and the waiting texts take the wider one) and the
-- keep line
function H.placeBottom(M, slotW)
	local G = S.G
	local key = table.concat({ tostring(S.Mode), G.W, G.B, slotW }, ",")
	if S.BottomKey == key then
		return
	end
	S.BottomKey = key
	local W = G.W
	local wispX, wispW, claimX, keepX, keepW
	if S.Mode == "PC" then
		wispW = math.min(M.WispW, W - 2 * M.Side)
		wispX = (W - wispW) / 2
		claimX = (W - slotW) / 2
		keepW = math.min(M.KeepW, W - 2 * M.Side)
		keepX = (W - keepW) / 2
		local bannerW = math.min(M.BannerW, W - 2 * M.Side)
		place(U.Banner, (W - bannerW) / 2, G.Y0, bannerW, G.WispH)
		U.WispText.TextXAlignment = Enum.TextXAlignment.Center
		U.Keep.TextXAlignment = Enum.TextXAlignment.Center
	elseif S.Mode == "Portrait" then
		slotW = math.min(slotW, W - 2 * M.Side)
		wispX, wispW = M.Side, W - 2 * M.Side
		claimX = (W - slotW) / 2
		keepX, keepW = M.Side, W - 2 * M.Side
		place(U.Banner, wispX, G.Y0, wispW, G.WispH)
		U.WispText.TextXAlignment = Enum.TextXAlignment.Center
		U.Keep.TextXAlignment = Enum.TextXAlignment.Center
	else
		claimX = W - M.Side - slotW
		wispX = M.Side
		wispW = math.max(60, claimX - M.ColGap - M.Side)
		keepX, keepW = wispX, wispW
		place(U.Banner, wispX, G.Y0, wispW, G.WispH)
		U.WispText.TextXAlignment = Enum.TextXAlignment.Left
		U.Keep.TextXAlignment = Enum.TextXAlignment.Left
	end
	place(U.WispText, wispX, G.Y0, wispW, G.WispH)
	place(U.WispBar, wispX, G.Y0 + G.WispH + G.WispGap, wispW, G.BarH)
	local g = M.SegGap
	local segW = (wispW - 6 * g) / 7
	for i, seg in ipairs(U.Segs) do
		place(seg, (i - 1) * (segW + g), 0, segW, G.BarH)
	end
	place(U.Claim, claimX, G.ClaimY, slotW, G.ClaimH)
	place(U.Countdown, claimX, G.ClaimY, slotW, G.ClaimH)
	place(U.Keep, keepX, G.KeepY, keepW, G.KeepH)
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
	if portrait then
		place(U.PlayHeader, M.PlaySide, M.PlayY, W - 2 * M.PlaySide, M.PlayH)
		place(U.ClaimAll, (W - M.AllW) / 2, M.AllY, M.AllW, M.AllH)
	else
		place(U.ClaimAll, W - M.PlaySide - M.AllW, M.AllY, M.AllW, M.AllH)
		place(U.PlayHeader, M.PlaySide, M.PlayY, math.max(40, W - 2 * M.PlaySide - M.AllW - M.AllGap), M.PlayH)
	end
	U.PlayHeader.TextWrapped = portrait
	U.ClaimAll.TextSize = M.AllText
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
	y = y + px + gap
	place(cell.Reward, 4, y, inner, rewardH)
	cell.Reward.TextSize = M.RewardText
	cell.Reward.TextWrapped = lines > 1
	cell.Lines = lines
	local slotY = bh - M.BoxPadBottom - M.SlotH
	cell.SlotY, cell.SlotH, cell.Inner = slotY, M.SlotH, inner
	local btnW = math.min(M.TierBtnW, inner)
	place(cell.Claim, (bw - btnW) / 2, slotY, btnW, M.SlotH)
	cell.Claim.TextSize = M.TierBtnText
	local pad = cell.Claim:FindFirstChildOfClass("UIPadding")
	if pad then
		-- (a narrow box's CLAIM keeps its word: NeonKit's 10 px sides would cut it)
		local side = btnW < 80 and 4 or 10
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, side), UDim.new(0, side)
	end
	cell.Clock.TextSize, cell.Glyph.TextSize = M.ClockText, M.ClockText
	local tick = M.TickText
	cell.Check.TextSize = tick
	place(cell.Check, (bw - tick - 8) / 2, slotY + (M.SlotH - tick - 8) / 2, tick + 8, tick + 8)
	cell.GiftKey, cell.ClockKey = nil, nil
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
	H.render()
end

-- selected: light gold (the mock's #fff3c4 -> #ffc93c) under white outlined text; else dark glass under muted text
function H.paintTab(button, selected)
	button.TextColor3 = selected and WHITE or MUTED
	button:SetAttribute("Selected", selected)
	local fill = U.Bar:FindFirstChild(button.Name .. "Fill")
	if not fill then
		return
	end
	fill.BackgroundColor3 = selected and WHITE or INK
	fill.BackgroundTransparency = selected and 0 or 0.55
	local grad = fill:FindFirstChild("TabFill")
	if grad then
		grad.Color = selected and ColorSequence.new(Theme.Lighten(GOLD, 0.7), GOLD) or ColorSequence.new(WHITE, WHITE)
	end
	local stroke = fill:FindFirstChild("TabStroke")
	if stroke then
		stroke.Color = selected and INK or WHITE
		stroke.Transparency = selected and 0 or 0.8
	end
end

function H.paintArt(cell, entry)
	local px = cell.ArtPx or 28
	local key = tostring(entry.Kind) .. ":" .. tostring(entry.PetId) .. ":" .. px
	if cell.ArtKey == key then
		return
	end
	cell.ArtKey = key
	for _, child in ipairs(cell.Art:GetChildren()) do
		child:Destroy()
	end
	if entry.Kind == "Pet" and type(entry.PetId) == "string" then
		local ok = pcall(function()
			local vp = CloudUI.PetViewport(cell.Art, entry.PetId, px, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Spin = "sway" })
			vp.Name = "PetViewport"
			vp.ZIndex = 5
		end)
		if ok then
			return
		end
	end
	local icon = NeonKit.Icon(cell.Art, (entry.Kind == "Pet" and "Gifts") or (entry.Kind == "Berries" and "Berries") or tostring(entry.Kind or "Gifts"), px)
	icon.ZIndex = 5
end

-- a cell's colour, its saturated fill gradient and its glow for a CELL_LOOK state (painted only when it changes)
function H.paintLook(cell, color, look)
	local key = tostring(color) .. "|" .. look
	if cell.LookKey == key then
		return
	end
	cell.LookKey = key
	local L = CELL_LOOK[look] or CELL_LOOK.Open
	cell.Card.SetColor(color)
	cell.Card.SetFill(Theme.Darken(color, L[1]), Theme.Darken(color, L[2]))
	cell.Card.SetGlow(look ~= "Claimed" and look ~= "Locked")
	cell.Card.Floor.Visible = look ~= "Claimed"
end

-- a box's gift: the "Gifts" icon on an orb of the tier's colour (the tint: an emoji glyph takes no colour), redrawn only
-- when its size or colour changes
function H.paintGift(cell, color)
	local px = cell.GiftPx or 0
	local key = tostring(color) .. ":" .. px
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
	local orb = NeonKit.Orb(cell.Gift, Theme.Lighten(color, 0.1), px)
	orb.ZIndex = 5
	local icon = NeonKit.Icon(cell.Gift, "Gifts", math.max(14, math.floor(px * 0.6)))
	icon.ZIndex = 6
end

-- the clock slot: the countdown centred with the clock glyph before it, or alone when both would not fit the box
function H.placeClock(cell, text)
	local key = text .. "|" .. tostring(cell.SlotY) .. "|" .. tostring(cell.Inner) .. "|" .. cell.Clock.TextSize
	if cell.ClockKey == key then
		return
	end
	cell.ClockKey = key
	local inner, slotY, slotH = cell.Inner or 0, cell.SlotY or 0, cell.SlotH or 44
	local size = cell.Clock.TextSize
	local textW = H.width(text, size, cell.Clock.Font)
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

-- "Week Wisp in 4 more days" / "in 1 more day" / "Week Wisp today!"
function H.wispText(cell)
	local left = 7 - cell
	if left <= 0 then
		return "Week Wisp today!"
	elseif left == 1 then
		return "Week Wisp in 1 more day"
	end
	return "Week Wisp in " .. left .. " more days"
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
		cell.Day.Text = (today and due) and "TODAY" or ("Day " .. i)
		cell.Dim.Visible = claimed
		cell.Check.Visible = claimed
		H.paintLook(cell, today and GOLD or DAY_COLORS[i], today and "Today" or (claimed and "Claimed" or "Open"))
		if not today then
			cell.Card.Stroke.Transparency = claimed and CELL_LOOK.Claimed[3] or 0
		end
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
		seg:SetAttribute("State", state)
		seg.BackgroundColor3 = (state == "Claimed" and Theme.Neon.Green) or (state == "Today" and GOLD) or SEG_OFF
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
	U.PlayHeader.Font = paused and Theme.Fonts.Body or Theme.Fonts.Heading
	U.PlayHeader.TextColor3 = paused and GOLD or WHITE
	U.PlayHeader.TextSize = paused and M.PausedText or M.PlayText
	U.PlayHeader.Text = H.fitLines(U.PlayHeader, texts, S.Mode == "Portrait" and 2 or 1)
	-- CLAIM ALL: the ready count; greyed out at 0, in the same place
	local readyCount = H.readyCount(st)
	U.ClaimAll.Text = string.format(TEXT.ClaimAll, readyCount)
	U.ClaimAll:SetAttribute("Disabled", readyCount == 0)
	local list = tiers(st)
	for i, cell in ipairs(U.Tiers) do
		local t = list[i]
		cell.Root.Visible = type(t) == "table"
		if type(t) == "table" then
			local color = TIER_COLORS[i] or GOLD
			cell.Time.Text = tostring(tonumber(t.Min) or 0) .. " min"
			cell.Reward.Text = H.fitLines(cell.Reward, tierRewards(t), cell.Lines)
			H.paintGift(cell, color)
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
			local countdown = state == "Locked" and DailyController.TierCountdown(i, st, at) or ""
			cell.Clock.Text = countdown
			cell.Clock.Visible = countdown ~= ""
			H.placeClock(cell, countdown)
			H.paintLook(cell, color, state)
			if not ready then
				cell.Card.Stroke.Transparency = CELL_LOOK[state][3]
			elseif cell.State ~= "Ready" then
				cell.Card.Stroke.Transparency = CELL_LOOK.Ready[3] -- (just ready: bright at once; the tick then pulses it)
			end
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
	if S.Tab == "Play" then
		-- a ready gift box: its border pulses and its gift bobs
		for _, cell in ipairs(U.Tiers) do
			if cell.Root:GetAttribute("Pulsing") == true then
				Util.Tween(cell.Card.Stroke, 0.9, { Transparency = S.Pulse and K.PULSE or 0 })
			end
			if cell.Gift:GetAttribute("Bobbing") == true and cell.GiftY then
				Util.Tween(cell.Gift, 0.9, { Position = UDim2.fromOffset(cell.GiftX, cell.GiftY - (S.Pulse and K.BOB or 0)) },
					Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			end
		end
		return
	end
	for _, cell in ipairs(U.Cells) do
		if cell.Root:GetAttribute("Pulsing") == true then
			Util.Tween(cell.Card.Stroke, 0.9, { Transparency = S.Pulse and K.PULSE or 0 })
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
		return -- the sweep and the confetti are High only (the banner and the sound stay)
	end
	local fx = U.Fx
	local sweep = Instance.new("Frame")
	sweep.Name = "Sweep"
	sweep.BorderSizePixel = 0
	sweep.BackgroundColor3 = WHITE
	sweep.BackgroundTransparency = 0.45
	sweep.Size = UDim2.fromScale(0.35, 1)
	sweep.Position = UDim2.fromScale(-0.4, 0)
	sweep.ZIndex = 8
	local rainbow = Theme.Colors.Rainbow
	local keys = {}
	for i, c in ipairs(rainbow) do
		keys[#keys + 1] = ColorSequenceKeypoint.new((i - 1) / math.max(1, #rainbow - 1), c)
	end
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(keys)
	grad.Parent = sweep
	sweep.Parent = fx
	Util.Tween(sweep, 0.8, { Position = UDim2.fromScale(1.05, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(0.9, function()
		sweep:Destroy()
	end)
	for i = 1, K.CONFETTI do
		local bit = Instance.new("Frame")
		bit.Name = "Confetti"
		bit.BorderSizePixel = 0
		bit.BackgroundColor3 = rainbow[(i - 1) % #rainbow + 1]
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
	H.layoutButton()
	H.ensureWindow()
	H.layout()
	U.Holder.Visible = true
	H.render()
	H.syncBack()
	if not wasOpen then
		U.Pop.Scale = K.OPEN_FROM
		Util.Tween(U.Pop, K.OPEN_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local menu = controller("MenuController")
		if menu and menu.WindowOpened then
			menu.WindowOpened:Fire("Daily")
		end
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
end

function DailyController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	U.Gui = CloudUI.NewScreenGui("NimbusDaily", K.DISPLAY_ORDER)
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
			if id ~= "Daily" and S.Open then
				DailyController.Close()
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
	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui")
		local hud = pg:WaitForChild("NimbusHud", 30)
		if hud then
			for _, name in ipairs({ "TopRightLeft", "TopRightBottom" }) do
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
