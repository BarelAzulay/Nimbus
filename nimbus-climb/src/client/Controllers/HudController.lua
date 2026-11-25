-- HudController: the Nimbus Climb heads-up display (v3).
--
--   HudController.Init()
--   HudController.GetLayout() -> { TopLeftRight, TopLeftBottom, TopRightBottom, BottomLeftTop, Scale, CurrencyMode,
--                                  Vitals = { X, Y, W, H } | nil,   (wave 6: the vitals card's gui-area rect while it shows)
--                                  VitalsSlot = { X, Y, W, H } | nil }   (quick wins: the same rect shown or hidden; nil only
--                                  with no card. A fighter's pet battle hides the card and the battle HUD's Cheer up! /
--                                  Retreat buttons take its slot)
--   HudController.SetVitalsHidden(who, on)   (gui-redo) a window that would cover only part of the vitals card hides it
--                                  while open (the Gifts window, `who` = "Daily"; BattleController's fighter, `who` =
--                                  "Battle"); back when the last one lets go
--   HudController.SetCurrencyHidden(who, on)   (kit-b U9-2) a window that shows the balances itself steps the currency
--                                  strips aside while open (the Shop, `who` = "Shop": its header has Gems and Tokens, and
--                                  its X sat over the strips at 1280x720); back when the last one lets go
--
-- One ScreenGui "NimbusHud" (display order 10, IgnoreGuiInset = false, built by CloudUI.NewScreenGui).
-- Nothing the game announces is ever drawn in the middle of the screen. The layout map:
--
--   top-left      Match panel (difficulty, timer, checkpoint bar, team chips, Leave button) with the
--                 pre-match countdown numerals shown INSIDE it; the lobby Party panel takes the same
--                 slot (portal name + a big red Leave button, the only way out of a locked portal; the
--                 countdown; the members; "Locked until launch" + the head count); the small title card
--                 slides in there at join and leaves after four seconds
--   top-right     (bug batch 2 #1, option A "Split & shift") the currencies as thin strips stacked under
--                 Roblox's top bar, right-aligned: Cash, Gems, Cloud Tokens (coin + abbreviated number, "+n"
--                 chip on the token strip while in a match; Cash and Gems appear by themselves once those
--                 player attributes exist, and hide in a match). The toast stack (NotifyController) starts
--                 below them (TopRightBottom). A portrait screen lines them up in ONE row there (a stack would
--                 eat the toasts' room); a phone in a battle / dungeon run moves them into Roblox's top band
--                 when they fit there in one row (the battle HUD owns the top corners); a phone's dungeon End
--                 card starts below them (DungeonController reads TopRightBottom); one that still covers the
--                 corner (no room above the jump button) hides them meanwhile.
--   bottom-centre The vitals card, where it sat above the old item hotbar (HUD cleanup: the hotbar is gone, the card
--                 keeps its spot, K.HOTBAR_FALLBACK above the bottom edge, centred): heart badge +
--                 thick HP tube (white damage trail, hit flash + shake, low-health pulse, DOWNED state),
--                 lightning badge + stamina tube (dims when run dry) and the dash ring (cooldown sweep). Short touch
--                 screens get the flatter compact card (VG.Compact); it never shares rows with Roblox's
--                 thumbstick / jump button or the RUN / DASH buttons (it steps up above them where it must).
--   left-centre   MenuController's slim tile column (not ours; measured).
--
-- Sizes follow the v3 readability rule: every panel is designed in 1080p pixels (body text >= 18, numbers
-- 30+, titles 26-34) and carries a UIScale of Theme.ScreenFactor() = clamp(viewportY / 1080, 0.8, 1.25), so
-- the smallest text is 14.4 px on a phone. The UIScale sits on the panel, the margins on full-screen holder
-- frames, so scaling never moves a panel away from its corner.
--
-- Neighbours are MEASURED, not guessed: the menu column (NimbusMenu.MenuColumn, left-centre, drawn above us) and
-- the touch RUN / DASH buttons (MobileControls; HUD cleanup: the item hotbar is gone). Whatever of ours would
-- run into the column steps aside to its right; the vitals never reach under the touch buttons. The geometry is
-- re-checked twice a second and on every viewport change, and published as attributes on the NimbusHud
-- gui (TopLeftRight, TopLeftBottom, TopRightLeft, TopRightBottom, BottomLeftTop = the top of the bottom block (the
-- vitals card), BottomCentreTop / Left / Right = the vitals card, HudScale100; gui-area pixels) so the toasts,
-- dialogs and side panels can keep clear of the HUD. (kit-b U8) GiftLeft / GiftTop / GiftSize: the gift's dock under the
-- strips in the lobby (0 = none); DailyController puts its Gifts button there and TopRightBottom includes it.
-- kit-b U8 (the pitch's HUD stage, kit B): the strips are stone blocks with a coloured coin square, the vitals card a stone
-- card in a wood edge; no neon border, glow or gloss.
--
-- Data: Humanoid health, player attributes (CloudTokens, MatchTokens, InMatch, Downed, Stamina, Cash, Gems)
-- and the MatchState / PartyState remotes. Everything is nil-safe: no humanoid, no match, no party, a
-- missing menu and a missing MovementController all leave the HUD in a sensible idle state.
-- Plain Lua 5.1-compatible syntax only. All fonts come from Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7a) the coins' and the chips' icons
local SignKit = require(Shared:WaitForChild("SignKit")) -- (kit-b gate U9 r4) the vitals blocks' weight (Sizes.Bar)

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local okState, State = pcall(function()
	return require(Client:WaitForChild("State"))
end)
if not okState or type(State) ~= "table" then
	State = nil
end

local HudController = {}

----------------------------------------------------------------------
-- Tunables (design pixels of a 1080p screen unless noted)
----------------------------------------------------------------------
-- K: layout + timing constants (one table keeps the module well under Lua's 200-locals limit)
local K = {
	EDGE = 12, -- margin to the screen edge
	TOUCH_EDGE = 20, -- larger side margin on touch devices (notches, rounded corners)
	SMALL_PHONE = 500, -- Roblox's own touch controls shrink when the smaller screen side is at most this

	VITALS_W = 430, -- (Pitch 2 item 08 C: the pitch's 430; was 300, bug batch 2 #1's compact card)
	VITALS_H = 128, -- the vitals slot: the name tab's 32 above the card + the 96 card (see VG; U9-8 look's card was 100)
	VITALS_MIN_W = 236, -- narrowest the vitals get squeezed on a small phone
	VITALS_EDGE = 2, -- (kit-b P2 fix6b) the card's wood edge, drawn outside its box (screen px)
	HOTBAR_GAP = 8, -- screen px between the old hotbar's top and the vitals card
	HOTBAR_FALLBACK = 78, -- gui px the old item hotbar reached above the bottom edge (14 + 64): the card keeps that spot
	OBSTACLE_GAP = 8, -- kept between the vitals and the column / the touch buttons / Roblox's stick and jump button
	-- (look:fix6b2 N2) the least air the card keeps where OBSTACLE_GAP would cut the player's name: the ink rule's 4 px
	-- (battle_hud_no_overlap MIN_GAP) and 1 px to spare
	OBSTACLE_TIGHT = 5,
	-- Roblox's own touch controls (gui px; small = the smaller screen side <= SMALL_PHONE): the thumbstick's zone at
	-- the bottom-left (width, height above the bottom edge: the dynamic stick's idle ring reaches ~93 px on phones)
	-- and the jump button (J x J square, left edge 1.5 J + 10 and right edge 0.5 J + 10 px from the right edge, bottom
	-- 20 px (small) or 0.75 J above the bottom edge)
	STICK_W_SMALL = 110,
	STICK_H_SMALL = 96,
	STICK_H_PORTRAIT = 150, -- a portrait phone's thumb roams higher: the card keeps the old raise there
	STICK_W_LARGE = 190,
	STICK_H_LARGE = 210,
	JUMP_SMALL = 70,
	JUMP_LARGE = 120,

	-- bug batch 2 #1 (option A): the currencies are thin strips stacked in the top-right corner, right-aligned
	STRIP_W = 168, -- one strip (design px); in a match the token strip grows by its "+n" chip
	STRIP_H = 32,
	STRIP_GAP = 6,
	STRIP_COIN = 24, -- the coin at the strip's left end (kit-b U8: a square inside the block, clear of its lip)
	STRIP_TEXT = 24, -- the number (shrinks to STRIP_TEXT_MIN for long numbers; >= 14 px on a phone)
	STRIP_TEXT_MIN = 18,
	STRIP_CHIP_W = 56, -- the "+n" match chip on the token strip
	-- (kit-b U8: the pitch's HUD stage) the gift docks under the strips in the lobby, right-aligned: this square (design px,
	-- x the screen factor, never under GIFT_MIN gui px: a thumb), GIFT_GAP under the last strip
	GIFT = 56,
	GIFT_MIN = 44,
	GIFT_GAP = 8,
	STRIP_CHIP_H = 24,
	-- ... except in a battle / dungeon run on a landscape phone, where the battle HUD needs the right edge: there the
	-- strips sit in ONE row inside Roblox's top band (the v5 place the battle HUD is laid out around)
	BAND_LEFT = 150, -- the row starts right of Roblox's top-bar buttons (screen px; HUD cleanup: right of
	-- TopBarController's pill, its NimbusTopBar PillRight + STRIP_GAP, this at least) ...
	BAND_RIGHT = 72, -- ... and ends left of its "..." button
	BAND_INSET = 58, -- the top bar's height when the gui inset cannot be measured
	BAND_MIN_W = 100, -- a strip in the band is squeezed to this at most (HUD cleanup: was 120; right of the pill three
	-- strips still fit one row down to a 640x360 phone, else they fell back to the stack under the battle HUD's LEAVE)
	-- ... and on a portrait screen the strips sit side by side in ONE row at the top right (a stack would eat the
	-- room the toasts below it need there), each this wide at most / at least
	ROW_MAX_W = 140,
	ROW_MIN_W = 104,

	COIN = 54, -- the v5 pill geometry (setRowGeometry false / true): the round coin badge of a full pill ...
	CHIP_W = 76, -- ... the "+n" match chip on it ...
	COIN_COMPACT = 42, -- ... and the coin of a compact pill

	-- (kit-b U9-8 A, the owner's pick "Stone signboard") the match + party cards: the pitch's 540 where the screen has the
	-- room (20-character names whole, two to a row) ...
	PANEL_W = 540,
	-- ... squeezed this far on short screens (keeps their text out of the screen middle) and on a portrait screen: the
	-- pitch's phone card, the narrowest where SAINT, its five stars and Leave share the top row (a name cuts to ~12 letters)
	PANEL_MIN_W = 372,
	CENTRE_TOL = 0.145, -- the screen middle: |dx| < 14.5% of the width and |dy| < 14.5% of the height
	TITLE_W = 300,
	TITLE_H = 78,

	-- Menu column fallback (only while MenuController's column cannot be measured)
	MENU_FALLBACK_W = 82, -- bug batch 2 #1: one column of eight 56 px tiles + its arrow tab
	MENU_FALLBACK_ENTRY = 56,
	MENU_FALLBACK_GAP = 5,
	MENU_FALLBACK_COUNT = 8,
	MENU_CLEARANCE = 8, -- empty strip kept between the column and whatever steps aside for it
	SPAN_MARGIN = 4, -- two vertical spans closer than this count as touching

	LOW_HEALTH = 0.3, -- below this the heart beats and the card pulses red
	TRAIL_HOLD = 0.45, -- seconds the white damage trail waits before it catches up
	TRAIL_SPEED = 0.6, -- ... then drains this much of the bar per second
	HIT_SECONDS = 0.32, -- damage flash + card shake
	SHAKE_PX = 5,
	STAMINA_RECOVER = 15, -- after running dry the stamina row stays dimmed up to this (MovementController's resume point)
	TITLE_CARD_SECONDS = 4,
	LEAVE_CONFIRM_SECONDS = 3,
	GO_SECONDS = 1.0, -- how long "GO!" replaces the timer
	STAR_PX = 18, -- (kit-b U7a) a difficulty star (PixelIcon) after the match / party level name
	LAYOUT_POLL = 0.5, -- seconds between two geometry checks
}

-- VG: geometry of the vitals card in design px (1080p), width 236-300 (the bars stretch with it; the badges
-- and the dash key keep their size). H = the layout slot, CARD_H = the card drawn in it (from the top).
-- Left column: the heart badge over the lightning badge. (render gate, the pitch's .vit) both the same size, centred on
-- one column INSIDE the card (they overhung its left edge, the bolt below its bottom), each on its bar's row; the bars
-- start on one line right of them. Regular (desktops): the dash key ends the stamina row. Compact (short touch screens,
-- landscape phones): a flatter card that leaves a gap at the bottom of its slot, with a bigger dash key at the right end
-- spanning both rows. (kit-b U9-8) BADGE_ICON / KEY_ICON: the pixel icons on the badges and the key (18 / 27 px: whole
-- 2 / 3 px cells); KEY_STEP: the key's charge rises in steps of the icon's cell.
-- (U9-8 look) the HP bar is a row of HP_BLOCKS kit B blocks like the stamina (HP_H tall), its number right of them in a
-- box NUM_GAP away (the pitch's .vr: icon, bar, number); the regular card is 100 tall so 5 px of stone shows under the bolt
-- badge and the key above the lip (at 93 they sat on it). The compact card (landscape phones, always the 0.8 scale) is
-- 76 tall in its 80 slot and draws the heart and the bolt as bare pixel icons in their role's lip colour, as the pitch
-- does (BARE): at 0.8 an 18 px icon draws 18 screen px, which filled a 26 px tile edge to edge and fused the two tiles.
-- Every size here is design px; Vitals.Layout puts them on whole screen px under the card's scale.
-- (Pitch 2 item 08, option C "Name tab + stamp": .superpowers/slop-audit/round3/build/PITCH2/A_battle_hud/08_vitals_optC.png,
-- pitch_battle_hud.py vitals_C) the slot is the tab's TAB_UP above the card + the card. The wood tab (TAB_X in, TAB_H tall,
-- its foot behind the card's top edge) carries the stamp (STAMP square), the name (NAME_TEXT) and the trophies tag
-- (TROPHY_H, TROPHY_TEXT). The card: the bare heart (HEART_X) left of the HP track (TRACK_X .. W - PAD_R, HP_Y / HP_H from
-- the card's top: the blocks, a 2 px divider and the number at HP_TEXT in ONE sunk track) and under it the stamina group
-- (ST_Y / ST_H: the bare bolt, the stamina blocks ST_BLOCK wide, the dash state, the dash key KEY square at its right end
-- in ONE sunk well). Both geometries draw the badges bare; the compact card (landscape phones, always the 0.8 scale) is the
-- same card (its dash key is gone on a touch screen anyway)
local VG = {
	Regular = {
		Name = "Regular", H = K.VITALS_H, TAB_UP = 32, CARD_H = 96, CARD_X = 0, CARD_CORNER = 0, -- (kit-b U8: square)
		TAB_X = 14, TAB_H = 44, STAMP = 30, STAMP_TEXT = 26, NAME_TEXT = 20, NAME_MIN = 16, TROPHY_H = 26, TROPHY_TEXT = 18,
		HEART_X = 13, HEART = 24, HEART_TEXT = 22, BOLT = 24, BADGE_ICON = 18, BADGE_LIP = 0, BARE = true,
		TRACK_X = 39, HP_Y = 12, HP_H = 30, HP_TEXT = 18, PAD_R = 13,
		ST_Y = 48, ST_H = 30, ST_BLOCK = 28, ST_TEXT = 18,
		KEY = 26, KEY_ICON = 18, KEY_STEP = 2,
	},
	Compact = {
		Name = "Compact", H = K.VITALS_H, TAB_UP = 32, CARD_H = 96, CARD_X = 0, CARD_CORNER = 0,
		TAB_X = 14, TAB_H = 44, STAMP = 30, STAMP_TEXT = 26, NAME_TEXT = 20, NAME_MIN = 18, TROPHY_H = 26, TROPHY_TEXT = 18,
		HEART_X = 13, HEART = 24, HEART_TEXT = 22, BOLT = 24, BADGE_ICON = 18, BADGE_LIP = 0, BARE = true,
		TRACK_X = 39, HP_Y = 12, HP_H = 30, HP_TEXT = 18, PAD_R = 13,
		ST_Y = 48, ST_H = 30, ST_BLOCK = 28, ST_TEXT = 18,
		KEY = 26, KEY_ICON = 18, KEY_STEP = 2,
	},
	TRACK_EDGE = 2, TRACK_PAD = 3, DIVIDER = 2, -- the sunk track's / well's edge, its inside padding, the HP number's divider
	-- the dash's state in the stamina group (each state's longest form that fits whole: Vitals.Layout)
	DASH_WORDS = { ready = "Dash ready", cool = "Recharging", off = "Out of stamina" },
	-- (look review round 1: a phone's well kept its right half empty) the sets for a well too short for "Out of stamina"
	DASH_WORDS_SHORT = { ready = "Dash ready", cool = "Charging", off = "No stamina" },
	DASH_WORDS_TINY = { ready = "Ready", cool = "Wait", off = "Empty" },
	-- the stamp's five kit colours (UserId % 5 + 1) and their lips
	STAMPS = { { "Sky", "SkyLip" }, { "Grass", "GrassLip" }, { "Gold", "GoldLip" }, { "Red", "RedLip" }, { "Violet", "VioletLip" } },
	HP_BLOCKS = 5, -- (U9-8 look) the HP bar's blocks, a fifth of the health each
	-- (kit-b gate U9 r4: one bar language) the blocks: the kit's Bar weight (SignKit.Sizes.Bar: edge 2, lip 3, gap 3, as the
	-- Loss, Train and battle bars; were lip 4 / gap 4)
	BLOCK_EDGE = SignKit.Sizes.Bar.Edge, BLOCK_LIP = SignKit.Sizes.Bar.Lip, BLOCK_GAP = SignKit.Sizes.Bar.GapMax,
	CARD_EDGE = 3, CARD_LIP = 5, BADGE_EDGE = 2, KEY_EDGE = 2, -- (U9-8 look) the card's, a badge's and the key's wood / lip
	KEY_LIP = 4, KEY_SINK = 3, -- the key's lip at rest, and how far its face drops onto it while it cools down (the lip 4 -> 1)
}

local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.Navy or Colors.Ink
local INK = Colors.TextStroke or Colors.Ink
-- VS: the vitals card's colours
local VS = {
	PanelTop = Colors.PanelTop or Colors.PanelLight, -- v5: the Neon card fill (top -> bottom) and its darkest ink
	PanelBottom = Colors.PanelBottom or Colors.Panel,
	PanelInk = Colors.PanelInk or Colors.Ink,
	-- (render gate, the pitch's .vit) colour by role: the HP bar red, the stamina gold (bar, bolt badge, dash face)
	Hp = Theme.Sign.Red,
	HpDown = Theme.Sign.RedLip,
	Stamina = Theme.Sign.Gold,
	BoltInk = Theme.Sign.Text,
	Edge = Theme.Darken(NAVY, 0.3), -- outline of the tubes
	TrackTop = Color3.fromRGB(12, 16, 40), -- the dark inset track of the tubes
	TrackBottom = Color3.fromRGB(40, 52, 104),
	-- (kit-b U9-8) a stamina row you cannot dash on dims toward the stone's tan (no grey in kit B); the dash key's charge
	-- is the sky (the dash's colour: the battle HUD's DASH, the touch DASH key)
	Dim = Theme.Sign.StoneLip,
	DimLip = Theme.Sign.WellEdge,
	Charge = Theme.Sign.Sky,
}
local Vitals = {} -- builders and painters of the vitals card (one table keeps the chunk's locals down)

-- (U9-7 look) the docked side windows on screen (NeonKit.OpenDocks: Arena, Ring, Dungeon, the dare panel, Home, the Food
-- Machine...) in gui-area px; a portrait sheet covers the whole bottom and is left out. The vitals card keeps clear of them
function Vitals.DockRects(inset)
	local ok, docks = pcall(function()
		return require(Client:WaitForChild("UI"):WaitForChild("NeonKit")).OpenDocks()
	end)
	local out = {}
	for _, r in ipairs((ok and type(docks) == "table") and docks or {}) do
		if r.mode ~= "Sheet" then
			out[#out + 1] = { x0 = r.x0, y0 = r.y0 - inset, x1 = r.x1, y1 = r.y1 - inset }
		end
	end
	return out
end
local CUR = Theme.Currency or {}

-- Currency rows, top to bottom. Tokens is always shown (and sits right above the HP bar); the others appear
-- once their player attribute exists (phase 2 sets them).
-- v5: Neon = the pill's neon border (contract 6.6: Cash green, Tokens gold, Gems cyan).
local CURRENCY_ORDER = {
	{ Id = "Cash", Attr = Config.Attr.Cash, Def = CUR.Cash, Neon = "Green" },
	{ Id = "Gems", Attr = Config.Attr.Gems, Def = CUR.Gems, Neon = "Cyan" },
	{ Id = "Tokens", Attr = Config.Attr.Tokens, Def = CUR.Tokens, Always = true, Run = true, Neon = "Gold" },
}

----------------------------------------------------------------------
-- Module state
----------------------------------------------------------------------
local player = nil
local initialized = false
local startedAt = 0
local connections = {}
local warned = {}
local remoteCache = {}
local scalers = {} -- UIScale objects driven by the screen factor
local pads = {} -- UIPadding objects of the corner holders
local padTweens = {} -- running PaddingLeft tween per holder
local padGoals = {} -- last PaddingLeft requested per holder
local M = nil -- layout metrics of the match / party panels, see panelMetrics()
local movementModule = nil
local movementNextTry = 0
local layoutKey = nil
local layoutPoll = 0
local published = {} -- the geometry attributes on the gui
local vitalsRect = nil -- wave 6: the vitals card's last laid-out rect (gui-area px: X, Y = top-left, W, H); GetLayout().Vitals

local UI = {} -- instance references
local Items = {} -- sliding panels, see present()
local Cur = {} -- currency rows by id: { Def, Attr, Row, Amount, AmountScale, CoinScale, Target, Display, Shown, Seen, Visible }

local S = {
	match = nil, party = nil, downed = false, currencyMode = "TopRight", panelW = K.PANEL_W,
	yieldToResult = false, -- a narrow screen with the result card open: the match panel steps away
	vitalsOwners = {}, -- [window name] = true while that window wants the vitals card hidden (SetVitalsHidden)
	currencyOwners = {}, -- (kit-b U9-2) [window name] = true while that window wants the currency strips hidden (SetCurrencyHidden)
	topReserve = {}, -- (P2 fix A) [owner] = gui-area px of the top band a card spans (SetTopReserve): the strips start under it
}
local H = { -- health
	Char = nil, Humanoid = nil, Conns = {},
	Cur = 100, Max = 100, Target = 1, Fill = 1, Trail = 1,
	HoldUntil = 0, ColorKey = nil, Text = nil, Low = false,
	HitAt = -10, HitFx = false, -- last damage (flash + shake running while HitFx)
}
-- stamina + dash ring: Dim 0 = bright .. 1 = empty (eased), Charge = drawn cooldown sweep 0..1
local St = { Frac = 1, Dim = 0, DimDrawn = -1, Drained = false, Charge = -1, Ready = nil, Afford = nil }
local Tk = { RunSeen = 0 } -- the "+n" match chip
local Mt = { -- match panel bookkeeping
	Base = 0, At = 0, Phase = nil, Last = nil, GoUntil = 0, Rows = 1, Chips = {}, Count = 0,
}
local Pt = { -- party panel bookkeeping (Fit*: what the text sizes were last fitted for)
	Base = nil, At = 0, Rows = 1, Chips = {}, Count = 0, LastText = nil, LeaveLockUntil = 0,
	HintLong = "Locked until launch", HintShort = "Locked in", FitW = nil, FitTitle = nil, FitStatus = nil, FitHint = nil,
}
local LM = { ArmedUntil = 0, LockedUntil = 0 } -- leave-match confirmation
local TC = { Serial = 0, Shown = false } -- title card

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local tween = Util.Tween

local function track(conn)
	if conn then
		table.insert(connections, conn)
	end
	return conn
end

local function warnOnce(key, err)
	if not warned[key] then
		warned[key] = true
		warn("[HudController] " .. tostring(key) .. ": " .. tostring(err))
	end
end

-- pcall wrapper that reports each distinct failure once instead of spamming every frame.
local function guard(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
end

local function isTouchDevice()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function viewportSize()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if vp.X < 2 or vp.Y < 2 then
		return Vector2.new(1920, 1080)
	end
	return vp
end

-- The readability factor: clamp(viewportY / 1080, 0.8, 1.25).
local function currentScale()
	return Theme.ScreenFactor(viewportSize().Y)
end

local function topInset()
	local inset = 0
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	return inset
end

local function fireRemote(name)
	local remote = remoteCache[name]
	if not remote then
		local ok, found = pcall(Remotes.Get, name)
		if ok and found then
			remote = found
			remoteCache[name] = found
		end
	end
	if remote then
		remote:FireServer()
	end
end

----------------------------------------------------------------------
-- UI builders
----------------------------------------------------------------------
local function newFrame(parent, name, props)
	local p = { Name = name, BackgroundTransparency = 1, BorderSizePixel = 0 }
	if props then
		for key, value in pairs(props) do
			p[key] = value
		end
	end
	p.Parent = parent
	return Util.Create("Frame", p)
end

-- Themed TextLabel. props may include Outline = "World" (text floating over the 3D world with no plate: ONE outline,
-- Theme's world rule) with OutlineColor / OutlineThickness, plus any label property. kit-b U6: every other HUD text sits
-- on its card, chip or coin and reads by contrast, so it gets no outline and no classic stroke.
local function newText(parent, name, text, role, size, color, props)
	local extra = {
		Name = name,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	local outline, outlineColor, thickness = nil, nil, nil
	if props then
		for key, value in pairs(props) do
			if key == "Outline" then
				outline = value
			elseif key == "OutlineColor" then
				outlineColor = value
			elseif key == "OutlineThickness" then
				thickness = value
			else
				extra[key] = value
			end
		end
	end
	local label = Theme.Label(text, role, {
		Size = size,
		Color = color,
		Outline = outline,
		OutlineThickness = thickness,
		OutlineColor = outlineColor or INK,
		Props = extra,
	})
	label.Parent = parent
	return label
end

local function round(inst)
	return Theme.Corner(inst, "Round")
end

local function newScale(parent, value)
	local s = Instance.new("UIScale")
	s.Scale = value or 1
	s.Parent = parent
	return s
end

-- A UIScale driven by the screen factor (grows around the object's anchor point).
local function addViewportScale(root)
	local s = newScale(root, currentScale())
	s.Name = "ViewportScale"
	table.insert(scalers, s)
	return s
end

-- Springy "pop": jump a UIScale to `peak`, then ease back to 1.
local function pop(scaleObj, peak, seconds)
	if not scaleObj then
		return
	end
	scaleObj.Scale = peak
	tween(scaleObj, seconds or 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Face of a badge (kit-b U8: the kit B block): the flat colour, then a hard darker lip along the bottom. `glow` is kept for
-- the callers and no longer lightens the top (no gloss).
local function badgeSequence(color, glow)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.8, color),
		ColorSequenceKeypoint.new(0.82, Theme.Darken(color, 0.28)),
		ColorSequenceKeypoint.new(1, Theme.Darken(color, 0.28)),
	})
end

-- A square kit B badge (kit-b U8: was a glossy round one): the flat face with its lip (a UIGradient named "Lip" with a hard
-- step), a wood edge. Returns the badge, its UIGradient and its UIStroke.
local function newBadge(parent, name, size, color, glow)
	local badge = newFrame(parent, name, {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
	})
	local stroke = Theme.Stroke(badge, Theme.Sign.Wood, 3, 0)
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	local g = Instance.new("UIGradient")
	g.Name = "Lip"
	g.Rotation = 90
	g.Color = badgeSequence(color, glow)
	g.Parent = badge
	return badge, g, stroke
end

-- Glossy coin badge: newBadge plus a glyph (kit B, no outline: in the ink that reads on the coin's gradient).
-- (kit-b U7a) `glyph` may be a PixelIcon name ("token", "note"): the coin's Glyph label is then empty and hosts that icon
-- at about glyphSize px (setCoinIcon redraws it at a new size)
local function setCoinIcon(label, name, px)
	local old = label:FindFirstChild("Icon")
	if old and old:GetAttribute("PixelIcon") == name and old.Size.X.Offset == PixelIcon.Snap(px * 0.8) then
		return -- the layout poll re-applies the geometry every 0.5 s: nothing to redraw
	end
	label:SetAttribute("PixelIcon", name)
	PixelIcon.Host(label, name, px * 0.8)
end

-- (kit-b U8) a square kit B block in `color` with a wood edge (the currency strip's coin square, the vitals' badges)
function Vitals.SignSquare(parent, name, size, color)
	local sq = newFrame(parent, name, {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
	})
	local edge = Theme.Stroke(sq, Theme.Sign.Wood, 2, 0)
	edge.Name = "SignEdge"
	edge.LineJoinMode = Enum.LineJoinMode.Miter
	return sq
end

local function newCoin(parent, name, size, color, glow, glyph, glyphSize)
	local coin = newBadge(parent, name, size, color, glow)
	local icon = PixelIcon.Bitmaps[glyph] and glyph or nil
	local label = newText(coin, "Glyph", icon and "" or glyph, "Display", glyphSize, Theme.TextOn(badgeSequence(color, glow)), {
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0, -1),
		ZIndex = 2,
	})
	if icon then
		setCoinIcon(label, icon, glyphSize)
	end
	return coin
end

-- Slide a panel in/out between item.Rest and item.Hidden (both UDim2).
local function present(item, show)
	if not item or not item.Root or item.Shown == show then
		return
	end
	item.Shown = show
	local root = item.Root
	if show then
		root.Position = item.Hidden
		root.Visible = true
		tween(root, 0.4, { Position = item.Rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		tween(root, 0.22, { Position = item.Hidden }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.28, function()
			if not item.Shown and root.Parent then
				root.Visible = false
			end
		end)
	end
end

local function newItem(root, hidden)
	root.Visible = false
	return { Root = root, Shown = false, Rest = root.Position, Hidden = hidden }
end

-- A transparent full-screen frame whose UIPadding is the screen margin of one corner.
local function newHolder(gui, name)
	local holder = newFrame(gui, name, { Size = UDim2.fromScale(1, 1) })
	local pad = Instance.new("UIPadding")
	pad.Parent = holder
	pads[name] = pad
	return holder
end

-- The area GUIs with IgnoreGuiInset = false are laid out in (below the top bar).
local function guiAreaSize()
	local size = UI.Gui and UI.Gui.AbsoluteSize
	if size and size.X >= 2 and size.Y >= 2 then
		return size
	end
	local vp = viewportSize()
	return Vector2.new(vp.X, math.max(2, vp.Y - topInset()))
end

----------------------------------------------------------------------
-- Neighbour geometry (measured)
----------------------------------------------------------------------
local function playerGui()
	return player and player:FindFirstChildOfClass("PlayerGui")
end

-- y offset that converts a gui's AbsolutePosition into our gui-area coordinates
local function insetShift(gui)
	if gui and gui:IsA("ScreenGui") and gui.IgnoreGuiInset then
		return -topInset()
	end
	return 0
end

local function rectOf(inst, dy)
	local p, s = inst.AbsolutePosition, inst.AbsoluteSize
	return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
end

local function shownIn(inst, root)
	local node = inst
	while node and node ~= root do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

-- MenuController's left-centre column in our coordinates (nil when there is none to avoid).
local function menuRect(area)
	local pg = playerGui()
	local menuGui = pg and pg:FindFirstChild("NimbusMenu")
	if menuGui and menuGui:IsA("ScreenGui") then
		if not menuGui.Enabled then
			return nil
		end
		local dy = insetShift(menuGui)
		local column = menuGui:FindFirstChild("MenuColumn") or menuGui:FindFirstChild("MenuColumn", true)
		if column and column:IsA("GuiObject") and shownIn(column, menuGui) and column.AbsoluteSize.X > 0 then
			return rectOf(column, dy)
		end
		-- no column frame: the union of the menu buttons
		local box = nil
		for _, d in ipairs(menuGui:GetDescendants()) do
			if d:IsA("GuiObject") and string.sub(d.Name, 1, 11) == "MenuButton_" and d.AbsoluteSize.X > 0 and shownIn(d, menuGui) then
				local r = rectOf(d, dy)
				if box then
					box.x0, box.y0 = math.min(box.x0, r.x0), math.min(box.y0, r.y0)
					box.x1, box.y1 = math.max(box.x1, r.x1), math.max(box.y1, r.y1)
				else
					box = r
				end
			end
		end
		if box then
			return box
		end
		-- (kit-b backlog 5, new3_look: with a window open on a portrait phone - the Arena, the Ring, the Food Machine, the
		-- dungeon and obby pickers - MenuController hides the column; the estimate below then put a 62 x 347 phantom column on
		-- the left edge, the card found no room left of RUN and DASH and lay on both, 'SkyCli...') a column that is built
		-- but hidden is none to avoid
		if column then
			return nil
		end
	end
	-- not built yet: a generous estimate of the v3 column (vertically centred against the left edge)
	local s = Util.Clamp(math.min(area.X / 1280, area.Y / 720), 0.72, 1.2)
	local height = (K.MENU_FALLBACK_COUNT * K.MENU_FALLBACK_ENTRY + (K.MENU_FALLBACK_COUNT - 1) * K.MENU_FALLBACK_GAP) * s
	return { x0 = 0, y0 = (area.Y - height) / 2, x1 = (K.MENU_FALLBACK_W + K.MENU_FALLBACK_GAP) * s, y1 = (area.Y + height) / 2 }
end

-- The touch RUN / DASH buttons (MovementController) in our coordinates.
local function mobileRects()
	local out = {}
	local pg = playerGui()
	local mobile = pg and pg:FindFirstChild("MobileControls")
	if not (mobile and mobile:IsA("ScreenGui") and mobile.Enabled) then
		return out
	end
	local dy = insetShift(mobile)
	for _, d in ipairs(mobile:GetDescendants()) do
		if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.AbsoluteSize.X > 0 and shownIn(d, mobile) then
			-- (LOOK-ui) a kit tile's wood edge is a Border stroke drawn outside its box: it counts. (kit-b P2 fix6b, look1 O3:
			-- RUN / DASH draw theirs on the key's Block, so it was missed and the vitals card's ink came 3 px off RUN's)
			local r = rectOf(d, dy)
			local block = d:FindFirstChild("Block")
			local edge = d:FindFirstChild("SignEdge") or (block and block:FindFirstChild("SignEdge"))
			local e = (edge and edge:IsA("UIStroke")) and edge.Thickness or 0
			r.x0, r.y0, r.x1, r.y1 = r.x0 - e, r.y0 - e, r.x1 + e, r.y1 + e
			table.insert(out, r)
		end
	end
	return out
end

local function rectKey(r)
	if not r then
		return "-"
	end
	return string.format("%d,%d,%d,%d", math.floor(r.x0), math.floor(r.y0), math.floor(r.x1), math.floor(r.y1))
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
-- What currently occupies the top-left slot: a match / party panel, the title card, and the design height
-- (0 while nothing does).
local function topLeftState()
	local hasPanel, hasTitle, h = false, false, 0
	if Items.Match and Items.Match.Shown and UI.Match then
		hasPanel = true
		h = math.max(h, UI.Match.Root.Size.Y.Offset)
	end
	if Items.Party and Items.Party.Shown and UI.Party then
		hasPanel = true
		h = math.max(h, UI.Party.Root.Size.Y.Offset)
	end
	if Items.Title and Items.Title.Shown then
		hasTitle = true
		h = math.max(h, K.TITLE_H)
	end
	return hasPanel, hasTitle, h
end

-- The currencies shown right now, top to bottom. In a match only Cloud Tokens count (and the stack stays
-- small next to the match panel); in the lobby every currency the player has.
local function visibleCurrencies()
	local list = {}
	local inMatch = S.match ~= nil or (player and player:GetAttribute(Config.Attr.InMatch) == true)
	for _, entry in ipairs(CURRENCY_ORDER) do
		local c = Cur[entry.Id]
		if c and c.Available and (c.Always or not inMatch) then
			table.insert(list, c)
		end
	end
	return list
end

-- Sets one corner holder's margins. The left margin eases to its new value when `animate` is set (a panel that
-- is showing grows a row and must not hop sideways); everything else snaps.
local function setPadding(name, left, top, right, bottom, animate)
	local pad = pads[name]
	if not pad then
		return
	end
	pad.PaddingTop = UDim.new(0, top)
	pad.PaddingRight = UDim.new(0, right)
	pad.PaddingBottom = UDim.new(0, bottom)
	if padGoals[name] == left then
		return -- already there, or already easing there
	end
	padGoals[name] = left
	local running = padTweens[name]
	if running then
		running:Cancel()
		padTweens[name] = nil
	end
	local goal = UDim.new(0, left)
	if animate and math.abs(pad.PaddingLeft.Offset - left) > 0.5 then
		padTweens[name] = tween(pad, 0.25, { PaddingLeft = goal })
	else
		pad.PaddingLeft = goal
	end
end

local function publish(name, value)
	value = math.floor((tonumber(value) or 0) + 0.5)
	if published[name] ~= value and UI.Gui then
		published[name] = value
		UI.Gui:SetAttribute(name, value)
	end
end

local layoutCurrencyRows -- (style, width) -> places the rows; defined with the currency code below
local setPanelWidth -- (designWidth) -> resizes the match / party panels; defined with the panels below
local setVitalsGeometry -- (VG.Regular | VG.Compact) -> places the vitals card's parts; defined with the card

-- Cards that own the top-right corner for a moment (in our coordinates, nil when none is up): the currency strips
-- step out of their way. Today: DungeonController's End card (NimbusDungeonRun.EndCard), which phones draw under the
-- strips while a run's result shows (and in the corner itself only when that leaves no room above the jump button).
local function cornerCardRect()
	local pg = playerGui()
	local run = pg and pg:FindFirstChild("NimbusDungeonRun")
	if not (run and run:IsA("ScreenGui") and run.Enabled) then
		return nil
	end
	local card = run:FindFirstChild("EndCard")
	if card and card:IsA("GuiObject") and card.AbsoluteSize.X > 0 and shownIn(card, run) then
		return rectOf(card, insetShift(run))
	end
	return nil
end

-- Roblox's own touch controls (thumbstick zone bottom-left, jump button bottom-right) in our coordinates.
local function robloxTouchRects(area, vp)
	local small = math.min(vp.X, vp.Y) <= K.SMALL_PHONE
	local j = small and K.JUMP_SMALL or K.JUMP_LARGE
	local jumpBottom = small and 20 or j * 0.75
	local stickW = small and K.STICK_W_SMALL or K.STICK_W_LARGE
	local stickH = small and K.STICK_H_SMALL or K.STICK_H_LARGE
	if small and vp.Y > vp.X then
		stickH = K.STICK_H_PORTRAIT
	end
	return {
		{ x0 = 0, y0 = area.Y - stickH, x1 = stickW, y1 = area.Y, soft = true }, -- (the zone the thumb roams: placeVitals)
		{ x0 = area.X - (1.5 * j + 10), y0 = area.Y - jumpBottom - j, x1 = area.X - (0.5 * j + 10), y1 = area.Y - jumpBottom },
	}
end

-- (kit-b backlog 5 / 20 / 30) the menu tiles step aside (MenuController.SetColumnCovered, owner "Vitals") while a short
-- phone's match / party panel and the vitals card have no room beside them (applyMargins); back when they have
function Vitals.SetColumnAside(on)
	on = on == true
	if (S.columnAside == true) == on then
		return
	end
	local module = script.Parent:FindFirstChild("MenuController")
	local ok, menu = pcall(function()
		return module and require(module)
	end)
	if ok and type(menu) == "table" and type(menu.SetColumnCovered) == "function" and pcall(menu.SetColumnCovered, on and 0 or nil, "Vitals") then
		S.columnAside = on
	elseif not on then
		S.columnAside = false
	end
end

-- (kit-b backlog 5 / 20 / 30: on landscape phones 640 - 720 wide in a match, on the pad and in the countdown no row under
-- the middle of the screen had the card's room between the match panel and RUN / DASH, so it squeezed onto both keys,
-- 'SkyCli...', at 640 x 360 20 px off the right edge) the card's slot where it has its room: the lowest bottom from its own
-- spot up to room.top, at its own spot and just above or below each obstacle, whose rows leave a span at least minW wide
-- clear of every drawn obstacle (the keys, Roblox's jump button, the panels, the strips, the docks; the stick's zone
-- may be shared, as above) and, once the card rises above its spot, of the middle of the screen (room.band); the span
-- nearest the centre, the card at most w wide. -> left (gui px), width (design px), bottom (gui px), or nil
function Vitals.Sweep(area, k, w, minW, h, bottom0, cx, obstacles, side, gap, room)
	-- a span as wide as the player's whole name first (room.nameW, screen px), then any span the card fits in
	if room.nameW and room.nameW > minW * k and not room.any then
		room.any = true
		local l, wd, b = Vitals.Sweep(area, k, w, math.ceil(room.nameW / k - 1e-6), h, bottom0, cx, obstacles, side, gap, room)
		room.any = nil
		if l then
			return l, wd, b
		end
	end
	local hk = h * k
	local band, topY = room.band, room.top or K.EDGE
	local tries = { bottom0 }
	for _, r in ipairs(obstacles) do
		if not r.soft then
			tries[#tries + 1] = r.y0 - gap
			tries[#tries + 1] = r.y1 + gap + hk
		end
	end
	table.sort(tries, function(a, b)
		return a > b
	end)
	for _, b in ipairs(tries) do
		local top = b - hk
		if b <= bottom0 + 0.01 and top >= topY - 0.01 then
			local spans = { { side, area.X - side } }
			local function cut(x0, x1)
				local out = {}
				for _, s in ipairs(spans) do
					if x1 <= s[1] or x0 >= s[2] then
						out[#out + 1] = s
					else
						if x0 > s[1] then
							out[#out + 1] = { s[1], x0 }
						end
						if x1 < s[2] then
							out[#out + 1] = { x1, s[2] }
						end
					end
				end
				spans = out
			end
			for _, r in ipairs(obstacles) do
				if not r.soft and top < r.y1 + gap and b > r.y0 - gap then
					cut(r.x0 - gap, r.x1 + gap)
				end
			end
			if band and b < bottom0 - 0.01 and top < band.y1 and b > band.y0 then
				cut(band.x0, band.x1)
			end
			local best, bestD = nil, math.huge
			for _, s in ipairs(spans) do
				if s[2] - s[1] >= minW * k then
					local width = math.floor(math.min((s[2] - s[1]) / k, w))
					local half = width * k / 2
					local x = Util.Clamp(cx, s[1] + half, s[2] - half)
					if math.abs(x - cx) < bestD then
						best, bestD = { x - half, width }, math.abs(x - cx)
					end
				end
			end
			if best then
				return best[1], best[2], b
			end
		end
	end
	return nil
end

-- Where the vitals card goes (bug batch 2 #1): bottom centre, its bottom at `bottom` (gui px, where the old hotbar's
-- top was) and centred on `cx`, as wide as `w` design px (>= minW). Whatever shares its rows - the menu
-- column, the touch RUN / DASH buttons, Roblox's stick and jump button - limits it from the side it is on; when the
-- room left is narrower than minW the card steps up just above the lowest of those and tries again, but never with
-- its top above `ceiling` (the middle of the screen): there it keeps the last rows, squeezed to minW.
-- Returns left (gui px), width (design px), bottom (gui px), and whether the card has its room (false: squeezed).
-- `air`: the air kept off them (default OBSTACLE_GAP). `room` ({ band, top }, optional): where no row has the room, the
-- card first looks for a slot clear of every drawn obstacle (Vitals.Sweep) before it squeezes.
local function placeVitals(area, k, w, minW, h, bottom, cx, obstacles, side, ceiling, air, room)
	-- (kit-b P2 fix6b, look1 O3) the card's own wood edge is drawn outside its box: the gap is kept from it
	local gap = (air or K.OBSTACLE_GAP) + K.VITALS_EDGE
	local bottom0 = bottom
	for _ = 1, 6 do
		local top = bottom - h * k
		local left, right = side, area.X - side
		local hardLeft, hardRight = side, area.X - side
		local step = nil
		for _, r in ipairs(obstacles) do
			if top < r.y1 + gap and bottom > r.y0 - gap then
				if (r.x0 + r.x1) / 2 < cx then
					left = math.max(left, r.x1 + gap)
					hardLeft = r.soft and hardLeft or math.max(hardLeft, r.x1 + gap)
				else
					right = math.min(right, r.x0 - gap)
					hardRight = r.soft and hardRight or math.min(hardRight, r.x0 - gap)
				end
				step = math.max(step or -math.huge, r.y0 - gap)
			end
		end
		if right - left < minW * k and step and step - h * k < ceiling and hardRight - hardLeft >= minW * k then
			-- (kit-b P2 fix6b, look1 O3: at 360 x 640 and 375 x 667 the card, squeezed at the middle's edge between the
			-- stick's zone and RUN / DASH, lay on both keys and cut the name to 'SkyCli...') at the last rows it may reach,
			-- the card gives way to the drawn keys and buttons only: it may share rows with the zone the stick's thumb roams
			-- (nothing is drawn there; its ring sits under the card)
			left, right = hardLeft, hardRight
		end
		if right - left >= minW * k or not step or step - h * k < ceiling then
			if right - left < minW * k and room then
				-- (kit-b backlog 5 / 20 / 30) no row here: the card looks for a slot clear of everything before it squeezes
				local sl, sw, sb = Vitals.Sweep(area, k, w, minW, h, bottom0, cx, obstacles, side, gap, room)
				if sl then
					return sl, sw, sb, true
				end
			end
			local width = math.floor(Util.Clamp((right - left) / k, minW, w))
			local half = width * k / 2
			local x = Util.Clamp(cx, left + half, math.max(left + half, right - half))
			return x - half, width, bottom, right - left >= minW * k
		end
		bottom = step
	end
	return cx - minW * k / 2, minW, bottom, false
end

-- Lays out the HUD (bug batch 2 #1, option A "Split & shift"). Inputs are measured every time; when nothing changed
-- since the last call the work is skipped (it runs twice a second). `animate` eases the top-left shift; `force`
-- skips the check.
--   * currencies: thin strips stacked in the top-right corner (right-aligned, below Roblox's top bar), every device;
--   * vitals: bottom centre, in the old item hotbar's spot (HUD cleanup: the hotbar is gone; K.HOTBAR_FALLBACK),
--     compact width; on touch screens it never shares rows with Roblox's stick / jump button
--     or the RUN / DASH buttons (it steps up above them on a portrait phone);
--   * the match / party panels and the title card keep the top-left corner (right of the menu column when they would
--     reach it).
-- HUD cleanup: TopBarController's pill (ScreenGui NimbusTopBar) sits in Roblox's top band right of its buttons; a
-- phone battle's TopBand currency row starts right of it (the PillRight attribute, screen px), K.BAND_LEFT at least.
local function topBarGui()
	local pg = playerGui()
	local bar = pg and pg:FindFirstChild("NimbusTopBar")
	return (bar and bar:IsA("ScreenGui")) and bar or nil
end

local function bandLeft()
	local right = 0
	pcall(function()
		local bar = topBarGui()
		right = (bar and bar.Enabled and tonumber(bar:GetAttribute("PillRight"))) or 0
	end)
	if right > 0 then
		return math.max(K.BAND_LEFT, right + K.STRIP_GAP)
	end
	return K.BAND_LEFT
end

local function applyMargins(animate, force)
	if not UI.Gui or not M then
		return
	end
	-- the pill moves (Travel hides in a battle, a resize): the band row follows it
	local topBar = topBarGui()
	if topBar and S.topBar ~= topBar then
		S.topBar = topBar
		track(topBar:GetAttributeChangedSignal("PillRight"):Connect(function()
			guard("top bar", applyMargins, false, true)
		end))
		track(topBar:GetPropertyChangedSignal("Enabled"):Connect(function()
			guard("top bar", applyMargins, false, true)
		end))
	end
	local bandX = bandLeft()
	local touch = isTouchDevice()
	local side = touch and K.TOUCH_EDGE or K.EDGE
	local vp = viewportSize()
	local k = currentScale()
	local area = guiAreaSize()
	local inset = math.max(0, vp.Y - area.Y)
	local column = menuRect(area)
	local buttons = touch and mobileRects() or {}
	local cornerCard = cornerCardRect()
	local docks = Vitals.DockRects(inset)
	local hasPanel, hasTitle, topH = topLeftState()
	local currencies = visibleCurrencies()
	local inMatch = S.match ~= nil or (player and player:GetAttribute(Config.Attr.InMatch) == true)
	local inBattle = player ~= nil and player:GetAttribute(Config.Attr.InBattle or "InBattle") ~= nil
	-- a phone in a battle / dungeon run: the strips go into Roblox's top band when they fit there in one row (the
	-- battle HUD owns the top corners; a landscape phone always has the room, a portrait one for a single strip),
	-- else (a portrait phone with Cash / Gems) they keep the narrow stack and the battle HUD's fighter card narrows
	local nCur = math.max(1, #currencies)
	local topBand = touch and inBattle and math.min(vp.X, vp.Y) <= K.SMALL_PHONE
		and nCur * K.BAND_MIN_W * k + (nCur - 1) * K.STRIP_GAP * k <= vp.X - bandX - K.BAND_RIGHT

	local parts = { area.X, area.Y, vp.X, vp.Y, k, touch and 1 or 0, hasPanel and 1 or 0, hasTitle and 1 or 0, topH,
		rectKey(column), rectKey(cornerCard), inMatch and 1 or 0, topBand and 1 or 0, inBattle and 1 or 0, bandX }
	for _, c in ipairs(currencies) do
		table.insert(parts, c.Id)
	end
	table.insert(parts, Vitals.FullName() .. "|" .. Vitals.TrophyText()) -- (look:fix6b2 N2: the name's room sets the card's air)
	for _, r in ipairs(buttons) do
		table.insert(parts, rectKey(r))
	end
	for _, r in ipairs(docks) do
		table.insert(parts, "d" .. rectKey(r))
	end
	local key = table.concat(parts, "|")
	if not force and key == layoutKey and not animate then
		return
	end
	layoutKey = key

	local function clearOfColumn(col, top, bottom)
		if col and top < col.y1 + K.SPAN_MARGIN and bottom > col.y0 - K.SPAN_MARGIN then
			return math.max(side, col.x1 + K.MENU_CLEARANCE)
		end
		return side
	end
	-- the middle of the screen the game must never write into (the layout rule), in gui-area pixels
	local band = {
		x0 = vp.X * (0.5 - K.CENTRE_TOL), x1 = vp.X * (0.5 + K.CENTRE_TOL),
		y0 = vp.Y * (0.5 - K.CENTRE_TOL) - inset, y1 = vp.Y * (0.5 + K.CENTRE_TOL) - inset,
	}

	-- top-left panels: right of the menu column `col` when they would reach it, and on short screens no wider than
	-- what keeps their text out of the middle of the screen -> left (gui px), width (design px)
	local function topLeftFor(col, aside)
		local tl, pw = side, K.PANEL_W
		if topH > 0 then
			tl = clearOfColumn(col, K.EDGE, K.EDGE + topH * k)
			if tl > side and tl + K.PANEL_MIN_W * k > area.X - side then
				-- a narrow portrait phone has no room beside the tile column (the panel would run off the right edge): the
				-- panel keeps the corner and MenuController moves the tiles below it (our TopLeftBottom)
				tl = side
			end
			if aside then
				-- (kit-b backlog 5) the tiles stepped aside on a short phone (applyMargins tries it there only): a panel that
				-- reaches the rows of Roblox's thumbstick keeps the tile column's clearance off its ring (a small phone's:
				-- K.JUMP_SMALL wide, from half of it less 10 in from the left edge, 20 over the foot)
				local j = K.JUMP_SMALL
				if K.EDGE + topH * k + K.MENU_CLEARANCE > area.Y - 20 - j then
					tl = math.max(tl, j / 2 - 10 + j + K.MENU_CLEARANCE)
				end
			end
			if K.EDGE + topH * k > band.y0 then
				pw = math.floor(Util.Clamp((band.x0 - tl - 4) / k, K.PANEL_MIN_W, K.PANEL_W))
			end
		end
		-- (kit-b U9-8 A) a portrait screen takes the narrow card (the pitch's phone card), and no card runs off the screen
		if vp.X < vp.Y then
			pw = math.min(pw, K.PANEL_MIN_W)
		end
		return tl, math.max(1, math.min(pw, math.floor((area.X - tl - side) / k)))
	end

	-- currencies: thin strips stacked top-right, right-aligned (the token strip carries the "+n" chip in a match)
	local n = math.max(1, #currencies)
	local stripW = K.STRIP_W
	for _, c in ipairs(currencies) do
		if c.Chip and inMatch then
			stripW = math.max(stripW, K.STRIP_W + K.STRIP_CHIP_W + 6)
		end
	end
	local stackH = n * K.STRIP_H + (n - 1) * K.STRIP_GAP
	-- (kit-b backlog 5) where the strips and the gift go beside top-left panels at tl, pw wide (laid out below; the vitals
	-- card keeps clear of them when it rises beside them): { blockW, blockH, rowW, left, top, bottom, overPanel, shown,
	-- giftLeft, giftTop, giftSize }; nil in the top band
	local function stripsAt(tl, pw, aside)
		if topBand or not UI.Currency then
			return nil
		end
		local s = { blockW = stripW, blockH = stackH, giftLeft = 0, giftTop = 0, giftSize = 0 }
		if vp.X < vp.Y and n > 1 and not inBattle then
			-- portrait: one row, right-aligned (in a battle the narrow stack: the fighter card narrows beside it)
			s.rowW = math.floor(Util.Clamp((area.X - 2 * side - (n - 1) * K.STRIP_GAP * k) / n / k, K.ROW_MIN_W, math.min(K.ROW_MAX_W, stripW)))
			s.blockW, s.blockH = n * s.rowW + (n - 1) * K.STRIP_GAP, K.STRIP_H
		end
		s.left = area.X - side - s.blockW * k
		-- (kit-b gate U9 r4: on a portrait phone the strips lay over the match / party panel's Leave button) where the
		-- strips would reach over the top-left panel: in the lobby (a party) they sit under it, right-aligned as before; in
		-- a match they step aside while the panel shows (it counts the run's tokens itself; under it they pushed the
		-- result card into the middle of the screen)
		local stripTop = K.EDGE
		s.overPanel = hasPanel and s.left < tl + pw * k + K.STRIP_GAP * k
		if s.overPanel and not inMatch then
			stripTop = math.floor(K.EDGE + topH * k + K.GIFT_GAP * k + 0.5)
		end
		-- (P2 fix A, item 06 A) a card spanning a portrait phone's top band (the battle's boss strip, SetTopReserve): the
		-- strips start GIFT_GAP under it (the pitch's portrait: the strip under the boss card, beside the fighter card)
		local reserve = 0
		for _, px in pairs(S.topReserve) do
			reserve = math.max(reserve, px)
		end
		if reserve > 0 then
			stripTop = math.max(stripTop, math.floor(reserve + K.GIFT_GAP * k + 0.5))
		end
		s.top, s.bottom = stripTop, stripTop + s.blockH * k
		-- a card that takes the corner for a moment (a dungeon run's result on a phone) hides the strips meanwhile
		local yield = cornerCard ~= nil and cornerCard.x0 < area.X - side and s.left < cornerCard.x1
			and cornerCard.y0 < s.bottom and s.top < cornerCard.y1
		-- (kit-b backlog 5) in a match the panel counts the run's tokens: the strips also step aside with the tiles (aside)
		s.shown = not yield and not ((s.overPanel or aside) and inMatch) and next(S.currencyOwners) == nil
		-- (kit-b U8) the gift's dock under the strips, in the lobby only (DailyController hides its button in a match or a
		-- battle anyway): DailyController puts its button on this square (GiftLeft / GiftTop / GiftSize), and the toasts,
		-- side panels and the tutorial start under it (TopRightBottom). While a corner card is up (a phone's dungeon End
		-- card) the gift steps aside, so the card starts right under the strips
		if not inMatch and not inBattle and cornerCard == nil then
			s.giftSize = math.max(K.GIFT_MIN, math.floor(K.GIFT * k)) -- (44 on a 844x390 phone, as the button was)
			s.giftTop = math.floor(s.bottom + K.GIFT_GAP * k + 0.5)
			s.giftLeft = math.floor(area.X - side - s.giftSize + 0.5)
		end
		return s
	end

	-- vitals: the regular card, the flatter compact card on short touch screens (landscape phones: the bottom band
	-- between the stick and the jump button is busy there)
	local geometry = (touch and vp.Y <= K.SMALL_PHONE) and VG.Compact or VG.Regular
	if setVitalsGeometry then
		setVitalsGeometry(geometry)
	end
	-- (U9-8 look) the card's height and width whole screen px, so its top corner (it hangs from a whole-px bottom) is too
	local vitalsH = math.floor(geometry.H * k + 0.5) / k
	-- (HUD cleanup: no hotbar to measure any more; the card keeps the bottom-centre spot it had above it)
	local bottom0 = area.Y - K.HOTBAR_FALLBACK * k - K.HOTBAR_GAP
	local cx = area.X / 2
	-- what the card keeps clear of with the column `col` and the top-left panels at tl, pw wide (strips: stripsAt's)
	local function obstaclesFor(col, tl, pw, strips)
		local obstacles = {}
		if col then
			table.insert(obstacles, col)
		end
		if topH > 0 then
			-- the match / party panel (a 4-player party on a landscape phone reaches the bottom band)
			local w = math.max(hasPanel and pw or 0, hasTitle and K.TITLE_W or 0)
			table.insert(obstacles, { x0 = tl, y0 = K.EDGE, x1 = tl + w * k, y1 = K.EDGE + topH * k })
		end
		for _, r in ipairs(buttons) do
			table.insert(obstacles, r)
		end
		if touch then
			for _, r in ipairs(robloxTouchRects(area, vp)) do
				table.insert(obstacles, r)
			end
		end
		-- (U9-7 look) an open side dock: the card slides left until its right edge is OBSTACLE_GAP px from the dock's frame
		-- (its wood edge covered the HP bar's right end and the dash chip at 844x390 and touched the card at 1280x720)
		for _, r in ipairs(docks) do
			table.insert(obstacles, r)
		end
		-- (kit-b backlog 5) the strips and the gift in the top-right corner: the card's slot may rise beside them now
		if strips and strips.shown then
			table.insert(obstacles, { x0 = strips.left, y0 = strips.top, x1 = area.X - side, y1 = strips.bottom })
		end
		if strips and strips.giftSize > 0 then
			table.insert(obstacles, { x0 = strips.giftLeft, y0 = strips.giftTop, x1 = strips.giftLeft + strips.giftSize, y1 = strips.giftTop + strips.giftSize })
		end
		return obstacles
	end
	local nameW = Vitals.WholeNameW(geometry, k)
	local room = { band = band, top = K.EDGE, nameW = nameW }
	-- -> left, width, bottom, and how well it sits: 2 its room (no squeeze) + 1 the whole name
	local function placeAmong(obstacles)
		local l, w, b, fits = placeVitals(area, k, K.VITALS_W, K.VITALS_MIN_W, vitalsH, bottom0, cx, obstacles, side, band.y1, nil, room)
		-- (look:fix6b2 N2) a card too narrow for the player's whole name keeps only OBSTACLE_TIGHT of air where that gives the
		-- name its room (at 800 x 450 in a match / countdown it sat in the 211 px between the match panel and RUN's block
		-- edge, O3's 8 px of air + its 2 px edge on each side left it 190 px, under the 196 'SkyClimber' needs at its 14.4 px
		-- floor: 'SkyCli...', whole at e272588). Where even that leaves no room the card stays as it was
		if math.floor(w * k) < nameW then
			local l2, w2, b2, f2 = placeVitals(area, k, K.VITALS_W, K.VITALS_MIN_W, vitalsH, bottom0, cx, obstacles, side, band.y1, K.OBSTACLE_TIGHT, room)
			if math.floor(w2 * k) >= nameW and (f2 or not fits) then
				l, w, b, fits = l2, w2, b2, f2
			end
		end
		return l, w, b, (fits and 2 or 0) + ((math.floor(w * k) >= nameW) and 1 or 0)
	end
	local topLeft, panelW = topLeftFor(column)
	local strips = stripsAt(topLeft, panelW)
	local vitalsLeft, vitalsW, vitalsBottom, sits = placeAmong(obstaclesFor(column, topLeft, panelW, strips))
	-- (kit-b backlog 5 / 20 / 30: at 640 x 360 and 667 x 375 the two-wide tile column puts the match / party panel 165 px in,
	-- and right of the panel 144 / 171 px stay for a card at least 189 wide: no slot anywhere) on a short landscape phone,
	-- while a panel shows, the tiles step aside where the card then has all its room (as a battle's HUD sends them aside
	-- on a phone; in a match the strips with them: the panel counts the run's tokens): the panel takes the corner and the
	-- card its slot beside it. The column's frame keeps its place, so this weighs the same every layout
	local aside = false
	local shortPhone = touch and vp.X > vp.Y and math.min(vp.X, vp.Y) <= K.SMALL_PHONE
	if sits < 3 and column and hasPanel and topLeft > side and shortPhone then
		local tl2, pw2 = topLeftFor(nil, true)
		local strips2 = stripsAt(tl2, pw2, true)
		local l2, w2, b2, sits2 = placeAmong(obstaclesFor(nil, tl2, pw2, strips2))
		if sits2 >= 2 and sits2 > sits then
			aside = true
			topLeft, panelW, strips, sits = tl2, pw2, strips2, sits2
			vitalsLeft, vitalsW, vitalsBottom = l2, w2, b2
		end
	end
	Vitals.SetColumnAside(aside)
	-- ... and on the party pad, where even then the card has no slot (beside the strips and the gift right of the middle
	-- 175 px stay at 700 x 394, under the 189 the card needs; under them DASH), it steps aside while the party panel
	-- shows, as under a dock: never on the keys nor off the screen (no damage comes on the pad; in a match it stays)
	local noRoom = sits < 2 and hasPanel and shortPhone and not inMatch and not inBattle
	if (S.vitalsOwners.Room == true) ~= noRoom then
		S.vitalsOwners.Room = noRoom or nil
		if UI.Vitals then
			UI.Vitals.Visible = next(S.vitalsOwners) == nil
		end
	end
	if setPanelWidth then
		setPanelWidth(panelW)
	end
	vitalsW = math.floor(vitalsW * k) / k
	local vitalsTop = vitalsBottom - vitalsH * k
	-- ... and where no row beside the dock is wide enough the card steps aside while the dock is open (never half under it)
	local underDock = false
	for _, r in ipairs(docks) do
		if vitalsLeft < r.x1 and vitalsLeft + vitalsW * k > r.x0 and vitalsTop < r.y1 and vitalsBottom > r.y0 then
			underDock = true
		end
	end
	if (S.vitalsOwners.Dock == true) ~= underDock then
		S.vitalsOwners.Dock = underDock or nil
		if UI.Vitals then
			UI.Vitals.Visible = next(S.vitalsOwners) == nil
		end
	end
	if UI.Vitals then
		UI.Vitals.AnchorPoint = Vector2.new(0, 1)
		UI.Vitals.Size = UDim2.fromOffset(vitalsW, vitalsH)
		UI.VitalsW = vitalsW
		Vitals.Layout()
		UI.Vitals.Position = UDim2.new(0, math.floor(vitalsLeft + 0.5), 0, math.floor(vitalsBottom + 0.5))
	end
	vitalsRect = { X = math.floor(vitalsLeft + 0.5), Y = math.floor(vitalsBottom + 0.5) - vitalsH * k, W = vitalsW * k, H = vitalsH * k,
		TabUp = math.floor(geometry.TAB_UP * k + 0.5) } -- (P2 fix A) the name tab's band over the card's own top (Vitals.Layout's cardY)

	-- currencies: thin strips stacked top-right, right-aligned (the token strip carries the "+n" chip in a match), where
	-- stripsAt put them above
	local topRightBottom, topRightLeft = 0, 0
	local giftLeft, giftTop, giftSize = 0, 0, 0
	local mode = "TopRight"
	if UI.Currency and topBand then
		-- one row in the top band (above the gui area: the gui starts below Roblox's top bar)
		mode = "TopBand"
		local bandW = math.floor(Util.Clamp((vp.X - bandX - K.BAND_RIGHT - (n - 1) * K.STRIP_GAP * k) / n / k, K.BAND_MIN_W, stripW))
		if layoutCurrencyRows then
			layoutCurrencyRows(currencies, "Band", bandW)
		end
		UI.Currency.Parent = UI.TopRight
		UI.Currency.AnchorPoint = Vector2.new(0, 0.5)
		UI.Currency.Size = UDim2.fromOffset(n * bandW + (n - 1) * K.STRIP_GAP, K.STRIP_H)
		UI.Currency.Position = UDim2.new(0, bandX, 0, -math.max(inset, K.BAND_INSET) / 2)
		local want = next(S.currencyOwners) == nil -- (kit-b U9-2: a window with its own balances steps them aside)
		if UI.Currency.Visible ~= want then
			UI.Currency.Visible = want
		end
	elseif UI.Currency and strips then
		if strips.rowW then
			if layoutCurrencyRows then
				layoutCurrencyRows(currencies, "Band", strips.rowW)
			end
		elseif layoutCurrencyRows then
			layoutCurrencyRows(currencies, "Strips", stripW)
		end
		UI.Currency.Parent = UI.TopRight
		UI.Currency.AnchorPoint = Vector2.new(1, 0)
		UI.Currency.Size = UDim2.fromOffset(strips.blockW, strips.blockH)
		topRightLeft = strips.left
		UI.Currency.Position = UDim2.new(1, -side, 0, strips.top)
		topRightBottom = strips.bottom
		if UI.Currency.Visible ~= strips.shown then
			UI.Currency.Visible = strips.shown
		end
		if strips.giftSize > 0 then
			giftSize, giftTop, giftLeft = strips.giftSize, strips.giftTop, strips.giftLeft
			topRightBottom = giftTop + giftSize
		end
	end
	S.currencyMode = mode

	setPadding("TopLeft", topLeft, K.EDGE, 0, 0, animate)
	setPadding("TopRight", 0, 0, 0, 0)
	setPadding("BottomLeft", 0, 0, 0, 0)

	-- tell the neighbours (toasts, side panels, NPC dialogs, the tutorial) where the HUD is, in gui-area pixels.
	-- BottomLeftTop keeps its name for them: the top of the HUD's bottom block, now the centred vitals card
	-- (BottomCentreTop / BottomCentreLeft / BottomCentreRight give the card's extent).
	local topW = 0
	if hasPanel then
		topW = panelW
	end
	if hasTitle then
		topW = math.max(topW, K.TITLE_W)
	end
	publish("HudScale100", k * 100)
	publish("TopLeftRight", topH > 0 and (topLeft + topW * k) or 0)
	publish("TopLeftBottom", topH > 0 and (K.EDGE + topH * k) or 0)
	publish("TopRightBottom", topRightBottom)
	publish("TopRightLeft", topRightLeft)
	publish("GiftLeft", giftLeft)
	publish("GiftTop", giftTop)
	publish("GiftSize", giftSize)
	publish("BottomLeftTop", vitalsTop)
	publish("BottomCentreTop", vitalsTop)
	-- (P2 fix A) the card's own top edge under its name tab (Vitals.Layout's cardY): what docks beside the card lines up
	-- with it (the mouse-lock plank), BottomCentreTop being the tab's top
	publish("BottomCentreCardTop", vitalsTop + math.floor(geometry.TAB_UP * k + 0.5))
	publish("BottomCentreLeft", vitalsLeft)
	publish("BottomCentreRight", vitalsLeft + vitalsW * k)
	if UI.Gui:GetAttribute("CurrencyMode") ~= mode then
		UI.Gui:SetAttribute("CurrencyMode", mode)
	end
end

local function relayout()
	local k = currentScale()
	for i = #scalers, 1, -1 do
		local s = scalers[i]
		if s.Parent then
			s.Scale = k
		else
			table.remove(scalers, i)
		end
	end
	applyMargins(false, true)
end

-- Layout numbers of the match / party panels (design px, 1080p). (kit-b U9-8 A, the owner's pick "Stone signboard":
-- .superpowers/slop-audit/round3/build/U9-8/pitch_match_party.py, its numbers) a stone card in the vitals card's tier (a
-- 3 px wood edge, a 5 px lip), 10 px inside the edge, the rows 6 px apart and 8 px above the lip; the small blocks (the
-- level badge, the chips, the tokens tile, Leave, Change) a 2 px wood edge on a 4 px lip. A block's size here is its whole
-- visible box, the wood included. Text is 18+ everywhere, so it stays >= 14 px on a phone. One Leave plank for both cards
-- (kit-b U9-8 minors): on a PC the match card's 84x34; touch devices get a thumb target for Leave and for the leader's
-- Change (56 tall: >= 44 px on screen at the 0.8 phone scale; the party's Leave is a locked portal's only way out)
local function panelMetrics(touch)
	local m = {
		Edge = 3, Lip = 5, Pad = 10, Below = 8, -- the card
		BlockEdge = 2, BlockLip = 4, -- a small block
		Badge = 34, BadgeText = 20, NameGap = 8, NameText = 22, -- the level badge, then the name and its stars in ink
		RowGap = 6,
		-- the match card. Row A: the badge, the level, Leave. Row B: the clock, (wide) the checkpoints, the tokens tile.
		-- (narrow) row C: the checkpoints. Then the members, 8 px under the rows
		LeaveW = 84, LeaveH = 34, LeaveText = 18,
		TimerH = 34, TimerText = 32, CountText = 42,
		TokensH = 34, TokensText = 20, TokensPad = 10,
		CpX = 96, CpH = 22, CpText = 18, CpBlockW = 26, CpBlockGap = 4, CpBlockLip = 3,
		TeamGap = 8, ChipH = 48, ChipGap = 6, ChipText = 18, StateText = 18, HpH = 10,
		Wide = 480, -- a card this wide or wider puts the checkpoints in row B (the pitch's 1920 card)
		-- the party card. Row A: the obby's gold icon square, the title, the big red Leave. Row B: the countdown after the
		-- clock, the head count after the people. The members. Row D: the level badge, its name and stars, the leader's
		-- Change (a sky plank); an older portal's party: the lock hint
		IconText = 18, TitleText = 24,
		PartyLeaveW = 84, PartyLeaveH = 34, PartyLeaveText = 18, -- (the match card's Leave)
		StatusH = 26, StatusText = 20, CountW = 80, PartyChipH = 36,
		LevelRowH = 34, HintText = 18, ChangeW = 96, ChangeH = 34, ChangeText = 18,
	}
	if touch then
		-- a thumb target (44.8 px tall on screen at the 0.8 phone scale), one plank for both cards
		m.LeaveW, m.LeaveH, m.LeaveText = 100, 56, 24
		m.PartyLeaveW, m.PartyLeaveH, m.PartyLeaveText = m.LeaveW, m.LeaveH, m.LeaveText
		m.ChangeW, m.ChangeH, m.ChangeText = 100, 56, 22 -- the leader's Change (34 was 27 px on a phone)
	end
	-- (a CloudUI plank's size is its frame, the frame the tests measure; its wood edge draws outside it)
	m.Inset = m.Edge + m.Pad -- the rows' frame inside the card ...
	m.Bottom = m.Below + m.Lip + m.Edge -- ... and what the card keeps under them
	m.RowA = math.max(m.Badge, m.LeaveH + 2 * m.BlockEdge)
	m.TimerY = m.RowA + m.RowGap
	m.PartyRowA = math.max(m.Badge, m.PartyLeaveH + 2 * m.BlockEdge)
	m.StatusY = m.PartyRowA + m.RowGap
	m.PlayersY = m.StatusY + m.StatusH + m.RowGap
	m.LevelRowH = math.max(m.LevelRowH, m.ChangeH + 2 * m.BlockEdge)
	return m
end

----------------------------------------------------------------------
-- Default CoreGui (the health bar)
----------------------------------------------------------------------
-- (lobby-shop review round 3) Roblox's player list stays on: spec 16.6, the owner's "make it be seen also in the players
-- server list", is its Rank column (leaderstats.Rank: Top 10 / Top 100 / Creator). It was hidden since 2026-10-08 because the
-- Tokens column sat over our top-right token strip; the strips stay where they are (an open owner question, spec 16.11).
local HIDDEN_CORE = { Enum.CoreGuiType.Health }

-- Separate pcalls so a failure on one does not skip the other.
local function hideDefaultCoreGui()
	local allOk = true
	for _, coreType in ipairs(HIDDEN_CORE) do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(coreType, false)
		end)
		allOk = allOk and ok
	end
	return allOk
end

local function disableDefaultHealth()
	task.spawn(function()
		for _ = 1, 60 do
			if hideDefaultCoreGui() then
				task.wait(3) -- the core scripts may re-enable them while loading: apply once more
				hideDefaultCoreGui()
				return
			end
			task.wait(0.5)
		end
	end)
	pcall(function()
		track(StarterGui.CoreGuiChangedSignal:Connect(function(coreType, enabled)
			if enabled and coreType == Enum.CoreGuiType.Health then
				pcall(function()
					StarterGui:SetCoreGuiEnabled(coreType, false)
				end)
			end
		end))
	end)
end

----------------------------------------------------------------------
-- Build: vitals card (bottom-left)
----------------------------------------------------------------------
-- One card (kit-b U8: the pitch's .vit, a stone card in a wood edge on its lip): the heart badge beside the HP bar and its
-- number ("117 / 117"; white damage trail, hit flash + card shake, low-health pulse); the lightning badge beside the
-- stamina bar (eases on drain / refill, dims when run dry); the dash key (pressed with a rising charge while the dash
-- recharges). (U9-8 look) Both bars are rows of kit B blocks (Vitals.NewBlocks) and every part sits on whole screen px
-- (Vitals.Layout). Shapes are Frames (no font glyphs, no images); the geometry is VG.Regular / VG.Compact.

-- (U9-8 look) n design px as whole SCREEN px under the scale k: round(n x k), never under 1 px for a part that has a size
-- (the rule PixelIcon uses for its cells). The card lives under the HUD's UIScale (0.8 on phones and on a 1280x720
-- window): a 2 px block edge placed in design px drew 1.6 px there, soft in a render and 1 or 2 px in Roblox by where it
-- fell. Vitals.Layout works in screen px and hands Roblox each value divided by k
function Vitals.Px(n, k)
	if n <= 0 then
		return 0
	end
	return math.max(1, math.floor(n * k + 0.5))
end

-- (U9-8 look) where a PixelIcon goes (design px, its parent's coordinates) so its drawn cells sit centred on whole screen
-- px in a box of w x h screen px under the scale k (PixelIcon draws whole-px cells centred on its own box, which is not
-- whole under 0.8: an 18 px icon's box is 14.4 px and its cells 18)
function Vitals.IconAt(icon, w, h, k)
	local px = icon.Size.X.Offset
	local cell = math.floor(px / 9)
	local screenCell = tonumber(icon:GetAttribute("CellPx")) or math.max(1, math.min(cell, 2), math.floor(cell * k + 0.5))
	local drawn = 9 * screenCell
	local pad = math.floor((px * k - drawn) / 2)
	return UDim2.fromOffset((math.floor((w - drawn) / 2) - pad) / k, (math.floor((h - drawn) / 2) - pad) / k)
end

-- (kit-b U9-8; U9-8 look: the owner's look bar, every bar in the BlockRow language) a bar of opts.Count equal kit B blocks
-- built like SignKit.BlockRow: a wood block, its face (the stone well) inset by the edge, the lit part from the left in
-- whole px in the role's colour on its darker lip (a Frame, no gradient), the pitch's .seg / .seg.off. Each block is a
-- 1 / Count share of the bar. opts: Count, Face / Lip (the lit colours), Trail (a white Trail under the lit part: the HP's
-- damage trail on the blocks that just went out), Flash (a white Flash over the lit part: the hit and the low-health
-- breath). bar.Layout(w, h, k) places the blocks for a row w x h SCREEN px under the scale k (equal blocks, whole px);
-- bar.SetFraction(f) lights f of the bar, bar.SetTrail(f) the trail, bar.SetFlash(t) the flash's transparency,
-- bar.SetColor(face, lip) the lit colours
function Vitals.NewBlocks(parent, name, opts)
	local n = math.max(1, math.floor(tonumber(opts.Count) or 4))
	local root = newFrame(parent, name, { ZIndex = 2 })
	local bar = { Root = root, Blocks = {}, Count = n, Shown = -1, ShownTrail = -1, K = 1, Flashed = -1 }
	for i = 1, n do
		local block = newFrame(root, "Block" .. i, { BackgroundTransparency = 0, BackgroundColor3 = Theme.Sign.Wood, ZIndex = 2 })
		local face = newFrame(block, "Face", { BackgroundTransparency = 0, BackgroundColor3 = Theme.Sign.Well, ZIndex = 2 })
		local trail = nil
		if opts.Trail then
			trail = newFrame(face, "Trail", {
				BackgroundTransparency = 0.04,
				BackgroundColor3 = WHITE,
				Size = UDim2.new(0, 0, 1, 0),
				Visible = false,
				ZIndex = 3,
			})
		end
		local lit = newFrame(face, "Lit", {
			BackgroundTransparency = 0,
			BackgroundColor3 = opts.Face,
			Size = UDim2.new(0, 0, 1, 0),
			Visible = false,
			ZIndex = 4,
		})
		local lip = newFrame(lit, "Lip", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = opts.Lip,
			ZIndex = 4,
		})
		local flash = nil
		if opts.Flash then
			flash = newFrame(lit, "Flash", {
				BackgroundTransparency = 1,
				BackgroundColor3 = WHITE,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 5,
			})
		end
		bar.Blocks[i] = { Block = block, Face = face, Lit = lit, Lip = lip, Trail = trail, Flash = flash, FaceW = 0 }
	end
	-- n equal blocks across w screen px (what does not divide by n is left at the row's right end, under n px)
	function bar.Layout(w, h, k)
		local e, lipPx, gap = Vitals.Px(VG.BLOCK_EDGE, k), Vitals.Px(VG.BLOCK_LIP, k), Vitals.Px(VG.BLOCK_GAP, k)
		local bw = math.max(2 * e + 1, math.floor((w - (n - 1) * gap) / n))
		for i, b in ipairs(bar.Blocks) do
			b.Block.Position = UDim2.fromOffset((i - 1) * (bw + gap) / k, 0)
			b.Block.Size = UDim2.fromOffset(bw / k, h / k)
			b.Face.Position = UDim2.fromOffset(e / k, e / k)
			b.Face.Size = UDim2.new(1, -2 * e / k, 1, -2 * e / k)
			b.Lip.Size = UDim2.new(1, 0, 0, math.min(lipPx, h - 2 * e - 1) / k)
			b.FaceW = bw - 2 * e
		end
		bar.K = k
		bar.Shown, bar.ShownTrail = -1, -1
	end
	-- each block lit by its share of `value`, from its left in whole screen px
	local function light(value, field)
		for i, b in ipairs(bar.Blocks) do
			local part = b[field]
			if part then
				local px = math.floor(Util.Clamp(value * n - (i - 1), 0, 1) * b.FaceW + 0.5)
				part.Visible = px > 0
				part.Size = UDim2.new(0, px / bar.K, 1, 0)
			end
		end
	end
	function bar.SetFraction(value)
		value = Util.Clamp(tonumber(value) or 0, 0, 1)
		if value ~= bar.Shown then
			bar.Shown = value
			light(value, "Lit")
		end
	end
	function bar.SetTrail(value)
		value = Util.Clamp(tonumber(value) or 0, 0, 1)
		if value ~= bar.ShownTrail then
			bar.ShownTrail = value
			light(value, "Trail")
		end
	end
	function bar.SetFlash(transparency)
		if transparency ~= bar.Flashed then
			bar.Flashed = transparency
			for _, b in ipairs(bar.Blocks) do
				if b.Flash then
					b.Flash.BackgroundTransparency = transparency
				end
			end
		end
	end
	function bar.SetColor(face, lip)
		for _, b in ipairs(bar.Blocks) do
			b.Lit.BackgroundColor3 = face
			b.Lip.BackgroundColor3 = lip
		end
	end
	function bar.Invalidate()
		bar.Shown, bar.ShownTrail = -1, -1
	end
	return bar
end

-- (U9-8 look) the HP number's box (design px at `size`): the widest the number gets for this max health (its digits as
-- 0s, the widest digit, over the max), so the blocks keep their width while the number changes. (DOWNED takes the
-- whole row: Vitals.Layout)
function Vitals.NumberW(size)
	local max = tostring(math.max(1, math.ceil((H.Max or 100) - 0.001)))
	local ok, m = pcall(Theme.Measure, string.rep("0", #max) .. " / " .. max, "Display", size)
	return (ok and m and m.X > 0) and m.X or size * 4.2
end

-- (U9-8 look) a badge on whole screen px: `size` design px square, centred on (BADGE_X, cy); its edge, lip and icon by
-- Vitals.FitBadge
-- (Pitch 2 item 08 C) cx / cy: the badge's centre in SCREEN px of its parent
function Vitals.PlaceBadge(badge, size, cx, cy, g, k)
	local s = Vitals.Px(size, k)
	local x = math.floor(cx - s / 2 + 0.5)
	local y = math.floor(cy - s / 2 + 0.5)
	badge.Position = UDim2.fromOffset((x + s / 2) / k, (y + s / 2) / k) -- (anchored at its centre: the heart beats there)
	badge.Size = UDim2.fromOffset(s / k, s / k)
	Vitals.FitBadge(badge, g, s, k)
end

-- (Pitch 2 item 08 C) the player's first letter (one UTF-8 character, capital) and the stamp's kit colour (UserId % 5)
function Vitals.StampOf()
	local name = (player and (player.DisplayName ~= "" and player.DisplayName or player.Name)) or "?"
	local letter = string.match(tostring(name), "^[%z\1-\127\194-\244][\128-\191]*") or "?"
	local pick = VG.STAMPS[((player and tonumber(player.UserId) or 0) % 5) + 1]
	return letter:upper(), Theme.Sign[pick[1]], Theme.Sign[pick[2]]
end

-- (Pitch 2 item 08 C) the trophies the tag shows: Theme.Short of Battle.Trophies (State), "0" before the first sync
function Vitals.TrophyText()
	local n = 0
	if State and type(State.Battle) == "function" then
		local ok, b = pcall(State.Battle)
		if ok and type(b) == "table" then
			n = tonumber(b.Trophies) or 0
		end
	end
	return Theme.Short(math.max(0, math.floor(n)))
end

-- (Pitch 2 item 08 C) a text's width in screen px at `size` design px under the scale k
local function measureAt(text, role, size, k)
	local ok, m = pcall(Theme.Measure, text, role, size)
	-- (never under FredokaOne's ~0.56 em a letter: a flat measure runs short of the drawn face; then 4% to spare, the
	-- render's overflow report)
	local w = math.max((ok and m and m.X > 0) and m.X or 0, #tostring(text) * size * 0.56)
	return math.ceil(w * 1.04 * k)
end

-- the name the vitals card's tab shows (the display name, else the user name)
function Vitals.FullName()
	return (player and (player.DisplayName ~= "" and player.DisplayName or player.Name)) or ""
end

-- (look:fix6b2 N2) the tab's parts beside the name, in screen px under the scale k: fixed (the stamp, the gaps, the
-- trophies tag), the tag's width, its number's width, and the name's floor size (design px). LayoutTab lays them out;
-- WholeNameW asks how wide the card must be for the whole name
function Vitals.TabParts(g, k)
	local function px(n)
		return Vitals.Px(n, k)
	end
	local numW = measureAt(Vitals.TrophyText(), "Display", g.TROPHY_TEXT, k)
	local trW = px(8) + px(18) + px(5) + numW + px(9)
	local fixed = px(5) + px(g.STAMP) + px(8) + px(10) + trW + px(6)
	return fixed, trW, numW, math.max(g.NAME_MIN, math.ceil(14 / k - 1e-6))
end

-- (look:fix6b2 N2) the card's width (screen px) that shows the player's name whole at its floor size: LayoutTab cuts it
-- when the tab's room (the card less TAB_X a side, less the fixed parts) is narrower than the name there
function Vitals.WholeNameW(g, k)
	local fixed, _, _, minSize = Vitals.TabParts(g, k)
	return 2 * Vitals.Px(g.TAB_X, k) + fixed + measureAt(Vitals.FullName(), "Heading", minSize, k)
end

-- (Pitch 2 item 08 C) the wood name tab over the card's top edge: the stamp, the name (its design size steps down to the
-- floor, then the name is cut with "..." so it always fits whole), the trophies tag at the tab's right end; the tab as wide
-- as its contents, never wider than the card less TAB_X on each side. W: the slot's width in screen px
function Vitals.LayoutTab(g, k, W)
	local T = UI.Tab
	if not T then
		return
	end
	local function px(n)
		return Vitals.Px(n, k)
	end
	local letter, face, lip = Vitals.StampOf()
	T.Letter.Text = letter
	T.Stamp.BackgroundColor3 = face
	T.StampLip.BackgroundColor3 = lip
	T.Letter.TextColor3 = select(2, Theme.ReadableFace(face, 4.5))
	local tabX, tabH = px(g.TAB_X), px(g.TAB_H)
	local up = px(g.TAB_UP)
	local stampS = px(g.STAMP)
	local edge2 = px(2)
	-- the trophies tag: [8][icon 18][5][number][9]
	T.Value.Text = Vitals.TrophyText()
	T.Value.TextSize = g.TROPHY_TEXT
	local iconS = px(18)
	local fixed, trW, numW, minSize = Vitals.TabParts(g, k)
	local trH = px(g.TROPHY_H)
	-- the name: as wide as it needs, in the room the tab leaves
	local maxTab = W - 2 * tabX
	local room = maxTab - fixed
	local full = Vitals.FullName()
	local size, text = g.NAME_TEXT, full
	while size > minSize and measureAt(text, "Heading", size, k) > room do
		size = size - 2
	end
	size = math.max(size, minSize)
	if measureAt(text, "Heading", size, k) > room then
		local cut = full
		while #cut > 1 and measureAt(cut .. "...", "Heading", size, k) > room do
			cut = cut:sub(1, -2)
			-- (never end on half a UTF-8 character)
			while #cut > 1 and string.byte(cut, #cut) >= 128 and string.byte(cut, #cut) < 192 do
				cut = cut:sub(1, -2)
			end
		end
		text = cut .. "..."
	end
	T.Name.Text = text
	T.Name.TextSize = size
	local nameW = math.min(room, measureAt(text, "Heading", size, k) + px(2))
	local tabW = math.min(maxTab, fixed + nameW)
	T.Root.Position = UDim2.fromOffset(tabX / k, 0)
	T.Root.Size = UDim2.fromOffset(tabW / k, tabH / k)
	T.Edge.Thickness = edge2 / k
	T.Light.Position = UDim2.fromOffset(0, 0)
	T.Light.Size = UDim2.new(1, 0, 0, 1 / k)
	-- the stamp: 5 in, 4 down; its lip 3, its edge 2
	T.Stamp.Position = UDim2.fromOffset(px(5) / k, px(4) / k)
	T.Stamp.Size = UDim2.fromOffset(stampS / k, stampS / k)
	T.StampEdge.Thickness = edge2 / k
	T.StampLip.Size = UDim2.new(1, 0, 0, px(3) / k)
	T.Letter.Size = UDim2.new(1, 0, 1, -px(3) / k)
	T.Letter.TextSize = g.STAMP_TEXT
	-- the name, centred on the tab's shown height (above the card's top)
	local nameX = px(5) + stampS + px(8)
	T.Name.Position = UDim2.fromOffset(nameX / k, 0)
	T.Name.Size = UDim2.fromOffset(nameW / k, (up - px(2)) / k)
	-- the trophies tag at the tab's right end, 6 down
	local trX = tabW - px(6) - trW
	T.Trophies.Position = UDim2.fromOffset(trX / k, px(6) / k)
	T.Trophies.Size = UDim2.fromOffset(trW / k, trH / k)
	T.TrophyEdge.Thickness = edge2 / k
	T.TrophyLip.Size = UDim2.new(1, 0, 0, px(3) / k)
	local ip = Vitals.IconAt(T.Icon, iconS, trH - px(3), k)
	T.Icon.Position = UDim2.fromOffset(ip.X.Offset + px(8) / k, ip.Y.Offset)
	T.Value.Position = UDim2.fromOffset((px(8) + iconS + px(5)) / k, 0)
	T.Value.Size = UDim2.fromOffset((numW + px(4)) / k, (trH - px(3)) / k)
	UI.TabSig = text .. "|" .. T.Value.Text .. "|" .. letter
end

-- (kit-b U9-8; U9-8 look) places every part of the vitals card on whole screen px for its geometry (UI.VitalsGeometry),
-- its width (UI.VitalsW, design px) and its scale; a no-op when none of them changed (force: always). The card's own
-- size is snapped by the layout (applyMargins), so its corner is a whole screen px and every part here is a whole number
-- of screen px from it: the card's edge and lip, the HP blocks and the number's box, the stamina blocks ending KEY_GAP
-- before the dash key, the key, the two badges
function Vitals.Layout(force)
	local g = UI.VitalsGeometry
	if not g or not UI.HpBar or not UI.StBar or not UI.Key or not UI.Card or not UI.HpTrack then
		return
	end
	local k = (UI.VitalsScale and UI.VitalsScale.Scale) or 1
	if k <= 0 then
		k = 1
	end
	local function px(n)
		return Vitals.Px(n, k)
	end
	local function at(v)
		return math.floor(v * k + 0.5)
	end
	local W = px(UI.VitalsW or K.VITALS_W)
	-- (the number's box: its widest for this max health, centred behind the divider, the pitch's 16 px of air)
	-- (the pitch's 18 px, never under 18 screen px: 23 design px under a 0.8 scale, the phone's readability rule)
	local hpText = math.max(g.HP_TEXT, math.ceil(18 / k - 1e-6))
	local numW = math.ceil((Vitals.NumberW(hpText) + 16) * k)
	-- (kit-b gate U9 r4) on a touch screen the dash key is gone: the touch DASH button is the dash there, and the '>>' key
	-- at the stamina row's end read as a second button; the stamina blocks show the charges
	local keyOn = not isTouchDevice()
	local tabSig = (player and player.DisplayName or "") .. "|" .. Vitals.TrophyText()
	local sig = g.Name .. ":" .. W .. ":" .. k .. ":" .. numW .. ":" .. tostring(S.downed) .. ":" .. tostring(keyOn) .. ":" .. tabSig
	if UI.LayoutSig == sig and not force then
		return
	end
	UI.LayoutSig = sig
	-- (Pitch 2 item 08 C) the tab over the card's top edge, then the card under it: its height, its wood edge and its lip
	local cardY = at(g.TAB_UP)
	Vitals.LayoutTab(g, k, W)
	UI.Card.Position = UDim2.fromOffset(0, cardY / k)
	UI.Card.Size = UDim2.new(1, 0, 0, px(g.CARD_H) / k)
	UI.CardStroke.Thickness = px(VG.CARD_EDGE) / k
	UI.CardLip.Size = UDim2.new(1, 0, 0, px(VG.CARD_LIP) / k)
	local e, pad, gapPx = px(VG.TRACK_EDGE), px(VG.TRACK_PAD), Vitals.Px(VG.BLOCK_GAP, k)
	local trackX = at(g.TRACK_X)
	local trackW = W - px(g.PAD_R) - trackX
	-- the HP track: one sunk well in its wood edge; the blocks, the 2 px divider and the number on the same face
	local hpY, hpH = cardY + at(g.HP_Y), px(g.HP_H)
	UI.HpTrack.Position = UDim2.fromOffset(trackX / k, hpY / k)
	UI.HpTrack.Size = UDim2.fromOffset(trackW / k, hpH / k)
	UI.HpFace.Position = UDim2.fromOffset(e / k, e / k)
	UI.HpFace.Size = UDim2.fromOffset((trackW - 2 * e) / k, (hpH - 2 * e) / k)
	local innerL, innerR = e + pad, trackW - e - pad
	local numX = innerR - numW
	local divX = numX - pad - px(VG.DIVIDER)
	UI.HpDivider.Position = UDim2.fromOffset(divX / k, e / k)
	UI.HpDivider.Size = UDim2.fromOffset(px(VG.DIVIDER) / k, (hpH - 2 * e) / k)
	UI.HpDivider.Visible = not S.downed
	local nH = #UI.HpBar.Blocks
	local bh = hpH - 2 * (e + pad)
	local cellW = math.max(2 * Vitals.Px(VG.BLOCK_EDGE, k) + 1, math.floor((divX - pad - innerL - (nH - 1) * gapPx) / nH))
	local hpW = nH * cellW + (nH - 1) * gapPx
	UI.VitalsCell = cellW
	UI.HpBar.Root.Position = UDim2.fromOffset(innerL / k, (e + pad) / k)
	UI.HpBar.Root.Size = UDim2.fromOffset(hpW / k, bh / k)
	UI.HpBar.Layout(hpW, bh, k)
	UI.HpBar.Root.Visible = not S.downed
	-- (downed: DOWNED takes the whole track, beside the heart's "!")
	local numL = S.downed and innerL or numX
	UI.HpNum.Position = UDim2.fromOffset(numL / k, e / k)
	UI.HpNum.Size = UDim2.fromOffset((innerR - numL) / k, (hpH - 2 * e) / k)
	UI.HpNum.TextXAlignment = S.downed and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
	UI.HpNum.TextSize = hpText
	-- the stamina group: one sunk well (the well edge) with the bolt, the blocks, the dash state and the dash key
	local stY, stH = cardY + at(g.ST_Y), px(g.ST_H)
	UI.StGroup.Position = UDim2.fromOffset(trackX / k, stY / k)
	UI.StGroup.Size = UDim2.fromOffset(trackW / k, stH / k)
	UI.StFace.Position = UDim2.fromOffset(e / k, e / k)
	UI.StFace.Size = UDim2.fromOffset((trackW - 2 * e) / k, (stH - 2 * e) / k)
	local key = UI.Key
	local keyS = math.min(px(g.KEY), stH - 2 * e)
	local keyX = trackW - e - keyS
	key.Root.Position = UDim2.fromOffset(keyX / k, e / k)
	key.Root.Size = UDim2.fromOffset(keyS / k, keyS / k)
	key.Edge.Thickness = px(VG.KEY_EDGE) / k
	local lip = px(VG.KEY_LIP)
	key.Px = { K = k, Size = keyS, Lip = lip, Sink = math.min(px(VG.KEY_SINK), lip - 1), Step = (key.Icon and tonumber(key.Icon:GetAttribute("CellPx"))) or px(g.KEY_STEP) }
	key.Root.Visible = keyOn and not S.downed
	local nS = #UI.StBar.Blocks
	local stX = innerL + px(g.BADGE_ICON) + px(6)
	local sh = stH - 2 * (e + pad)
	local right = keyOn and (keyX - px(4)) or (trackW - e - pad)
	local stCell = math.max(2 * Vitals.Px(VG.BLOCK_EDGE, k) + 1, px(g.ST_BLOCK))
	local stW = math.min(right - stX, nS * stCell + (nS - 1) * gapPx)
	UI.StBar.Root.Position = UDim2.fromOffset(stX / k, (e + pad) / k)
	UI.StBar.Root.Size = UDim2.fromOffset(stW / k, sh / k)
	UI.StBar.Layout(stW, sh, k)
	-- the dash's state after the blocks, where it fits whole
	local lx = stX + stW + px(8)
	-- (each state's longest word that fits whole: the full set, then the short, then the tiny one; the label is left-aligned
	-- after the blocks, so a shorter word moves nothing. None fits even the tiny set: no words)
	local words = {}
	for _, state in ipairs({ "ready", "cool", "off" }) do
		for _, set in ipairs({ VG.DASH_WORDS, VG.DASH_WORDS_SHORT, VG.DASH_WORDS_TINY }) do
			if not words[state] and right - lx >= measureAt(set[state], "Heading", g.ST_TEXT, k) + px(2) then
				words[state] = set[state]
			end
		end
	end
	if not (words.ready and words.cool and words.off) then
		words = nil
	end
	UI.DashWords = words or VG.DASH_WORDS
	UI.DashText.TextSize = g.ST_TEXT
	UI.DashText.Position = UDim2.fromOffset(lx / k, e / k)
	UI.DashText.Size = UDim2.fromOffset(math.max(0, right - lx) / k, (stH - 2 * e) / k)
	UI.DashText.Visible = not S.downed and words ~= nil
	local shownWord = UI.DashWords[UI.Key.State or "ready"]
	if shownWord and UI.DashText.Text ~= shownWord then
		UI.DashText.Text = shownWord
	end
	-- the badges: the bare heart left of the HP track, the bare bolt at the group's left end; then the key's look again
	Vitals.PlaceBadge(UI.Heart, g.HEART, at(g.HEART_X) + px(g.BADGE_ICON) / 2, hpY + hpH / 2, g, k)
	Vitals.PlaceBadge(UI.Bolt.Badge, g.BOLT, innerL + px(g.BADGE_ICON) / 2, stH / 2, g, k)
	Vitals.PaintKey(key.State or "ready", St.Charge)
	St.DimDrawn = -1
end

-- the vitals card's edge (kit-b U8: the wood edge of kit B; the HP fill already shows green / amber / red): wood, the sign
-- red while low or downed
function Vitals.BorderColor()
	if S.downed or H.Target <= K.LOW_HEALTH then
		return Theme.Sign.Red
	end
	return Theme.Sign.Wood
end

function Vitals.PaintBorder()
	if UI.CardStroke then
		local c = Vitals.BorderColor()
		UI.CardStroke.Color = c
		UI.CardGlow.Color = c
	end
end

function Vitals.SetShapeTransparency(box, transparency)
	for _, part in ipairs(box:GetChildren()) do
		if part:IsA("GuiObject") then
			part.BackgroundTransparency = transparency
		end
	end
end

-- (kit-b U9-8) the dash key (was the sky sweep ring around a gold face): a kit B keycap with the pixel dash, the pitch's
-- .key. Block (the tile face in its wood edge), its Lip along the bottom, the Charge (the sky rising from the bottom of the
-- face while the dash cools down) and the Icon (drawn by setVitalsGeometry at the geometry's KEY_ICON). Vitals.PaintKey
-- sets its state; (U9-8 look) Vitals.Layout its sizes in whole screen px (key.Px)
function Vitals.NewDashKey(parent)
	local key = newFrame(parent, "DashKey", { ZIndex = 3 })
	local block = newFrame(key, "Block", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Sign.Tile,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	})
	local edge = Theme.Stroke(block, Theme.Sign.Wood, 2, 0)
	edge.Name = "SignEdge"
	edge.LineJoinMode = Enum.LineJoinMode.Miter
	local lip = newFrame(block, "Lip", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, VG.KEY_LIP),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Sign.StoneLip,
		ZIndex = 3,
	})
	local charge = newFrame(block, "Charge", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = VS.Charge,
		Visible = false,
		ZIndex = 3,
	})
	return { Root = key, Block = block, Edge = edge, Lip = lip, Charge = charge, Icon = nil, IconPx = 0, State = nil }
end

-- the key's look: "ready" raised on its lip, the tile face, the brown icon; "cool" pressed onto its lip (the face drops
-- KEY_SINK px, the lip thins to what is left, the bottom stays), the well face, the sky charge `charge` (0..1) of the
-- face high from its bottom in whole steps of the icon's cell, the icon muted; "off" (no dash to pay for) pressed, the
-- Off block (well face and lip), the icon muted and faded, no charge. (U9-8 look) every size in whole screen px (key.Px)
function Vitals.PaintKey(state, charge)
	local key = UI.Key
	local m = key and key.Px
	if not m then
		return
	end
	local Sign = Theme.Sign
	local k = m.K
	local sink = (state == "ready") and 0 or m.Sink
	local lipPx = m.Lip - sink
	key.Block.Position = UDim2.fromOffset(0, sink / k)
	key.Block.Size = UDim2.new(1, 0, 1, -sink / k)
	key.Lip.Size = UDim2.new(1, 0, 0, lipPx / k)
	key.Block.BackgroundColor3 = (state == "ready") and Sign.Tile or Sign.Well
	key.Lip.BackgroundColor3 = (state == "ready") and Sign.StoneLip or ((state == "off") and Sign.Well or Sign.WellEdge)
	local faceH = m.Size - sink - lipPx
	local step = math.max(1, m.Step)
	local px = (state == "cool") and math.floor(Util.Clamp(charge or 0, 0, 1) * faceH / step) * step or 0
	key.Charge.Visible = px > 0
	key.Charge.Position = UDim2.new(0, 0, 1, -lipPx / k)
	key.Charge.Size = UDim2.new(1, 0, 0, px / k)
	if key.Icon then
		key.Icon.Position = Vitals.IconAt(key.Icon, m.Size, faceH, k)
		local ink = (state == "ready") and Sign.Text or Sign.TextMuted
		local fade = (state == "off") and 0.35 or 0
		for _, cell in ipairs(key.Icon:GetChildren()) do
			if cell:IsA("GuiObject") then
				cell.BackgroundColor3 = ink
				cell.BackgroundTransparency = fade
			end
		end
	end
	key.State = state
end

-- (kit-b U9-8) a vitals badge (was a glossy square with a rotated-part shape): a kit B square in its role's colour, its
-- darker lip along the bottom, the pixel icon (attribute Icon, in attribute Ink) centred on the face above the lip.
-- (U9-8 look) attribute BareInk: the icon's colour when the geometry draws it bare (VG BARE: no square, no lip)
function Vitals.NewBadge(parent, name, color, lipColor, icon, bareInk)
	local badge = Vitals.SignSquare(parent, name, VG.Regular.BOLT, color)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	local lip = newFrame(badge, "Lip", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = lipColor,
	})
	badge:SetAttribute("Icon", icon)
	badge:SetAttribute("BareInk", bareInk)
	return badge, lip
end

-- dresses a badge for geometry g at s x s screen px under the scale k: the square, its edge and lip in whole px (or bare:
-- the icon alone), the icon (re)drawn at g's BADGE_ICON in its ink, its cells centred on whole px above the lip
function Vitals.FitBadge(badge, g, s, k)
	local bare = g.BARE == true
	local lipS = bare and 0 or Vitals.Px(g.BADGE_LIP, k)
	badge.BackgroundTransparency = bare and 1 or 0
	local edge = badge:FindFirstChild("SignEdge")
	if edge then
		edge.Enabled = not bare
		edge.Thickness = Vitals.Px(VG.BADGE_EDGE, k) / k
	end
	local lip = badge:FindFirstChild("Lip")
	if lip then
		lip.Visible = not bare
		lip.Size = UDim2.new(1, 0, 0, lipS / k)
	end
	local ink = (bare and badge:GetAttribute("BareInk")) or badge:GetAttribute("Ink") or Theme.Sign.Text
	local icon = badge:FindFirstChild("Icon")
	if not icon or icon.Size.X.Offset ~= g.BADGE_ICON then
		if icon then
			icon:Destroy()
		end
		icon = PixelIcon.New(badge, badge:GetAttribute("Icon"), g.BADGE_ICON, ink)
		icon.ZIndex = badge.ZIndex
	end
	for _, cell in ipairs(icon:GetChildren()) do
		if cell:IsA("GuiObject") then
			cell.BackgroundColor3 = ink
		end
	end
	icon.Position = Vitals.IconAt(icon, s, s - lipS, k)
	icon.Visible = not (badge == UI.Heart and S.downed)
	if badge == UI.Heart then
		UI.HeartIcon = icon
		if UI.HeartGlyph then
			UI.HeartGlyph.TextColor3 = bare and Theme.Sign.RedLip or WHITE -- (the "!" while downed: white on the red square)
		end
	elseif UI.Bolt and badge == UI.Bolt.Badge then
		UI.Bolt.Icon = icon
		St.DimDrawn = -1 -- (a redrawn bolt repaints its dim)
	end
end

-- Puts the card on one geometry (VG.Regular or VG.Compact) and places its parts (Vitals.Layout); a no-op when unchanged.
setVitalsGeometry = function(g)
	if UI.VitalsGeometry == g or not UI.HpBar then
		return
	end
	UI.VitalsGeometry = g
	UI.CardCorner.CornerRadius = UDim.new(0, g.CARD_CORNER)
	UI.RimCorner.CornerRadius = UDim.new(0, math.max(0, g.CARD_CORNER - 2))
	UI.GlowCorner.CornerRadius = UDim.new(0, g.CARD_CORNER + 3)
	local key = UI.Key
	if key.IconPx ~= g.KEY_ICON then
		if key.Icon then
			key.Icon:Destroy()
		end
		key.Icon = PixelIcon.New(key.Block, "dash", g.KEY_ICON, Theme.Sign.Text)
		key.Icon.ZIndex = 4
		key.IconPx = g.KEY_ICON
	end
	UI.HeartGlyph.TextSize = g.HEART_TEXT
	-- (Pitch 2 item 08 C) the notice takes the stamina group's place
	UI.DownedNotice.Position = UDim2.fromOffset(g.TRACK_X, g.TAB_UP + g.ST_Y)
	UI.DownedNotice.Size = UDim2.new(1, -(g.TRACK_X + g.PAD_R), 0, g.ST_H)
	Vitals.Layout(true)
end

-- (Pitch 2 item 08 C) a kit B block (Frame) with its 2 px edge and its lip along the bottom: { Root, Edge, Lip }
local function tabBlock(parent, name, face, lip, edge, zindex)
	local root = newFrame(parent, name, { BackgroundTransparency = 0, BackgroundColor3 = face, ZIndex = zindex })
	local stroke = Theme.Stroke(root, edge, 2, 0)
	stroke.Name = "SignEdge"
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	local l = newFrame(root, "Lip", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundTransparency = 0,
		BackgroundColor3 = lip,
		ZIndex = zindex,
	})
	return root, stroke, l
end

-- (Pitch 2 item 08 C) the wood name tab (drawn behind the card: ZIndex 0 under the card's 1): its lit top line, the stamp
-- (the letter on its kit-colour block), the name in the stone colour, the trophies tag (the pixel trophy, the number)
local function buildNameTab(body)
	local T = {}
	local tab = newFrame(body, "NameTab", { BackgroundTransparency = 0, BackgroundColor3 = Theme.Sign.Wood, ZIndex = 0 })
	T.Root = tab
	T.Edge = Theme.Stroke(tab, Theme.Sign.WoodDark, 2, 0)
	T.Edge.Name = "SignEdge"
	T.Edge.LineJoinMode = Enum.LineJoinMode.Miter
	T.Light = newFrame(tab, "Light", { BackgroundTransparency = 0, BackgroundColor3 = Theme.Sign.WoodLight, ZIndex = 0 })
	T.Stamp, T.StampEdge, T.StampLip = tabBlock(tab, "Stamp", Theme.Sign.Sky, Theme.Sign.SkyLip, Theme.Sign.WoodDark, 0)
	T.Letter = newText(T.Stamp, "Letter", "?", "Display", 26, Theme.Sign.Text, { TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 0 })
	T.Name = newText(tab, "PlayerName", "", "Heading", 20, Theme.Sign.Stone, { ZIndex = 0 })
	T.Trophies, T.TrophyEdge, T.TrophyLip = tabBlock(tab, "Trophies", Theme.Sign.Tile, Theme.Sign.StoneLip, Theme.Sign.WoodDark, 0)
	T.Icon = PixelIcon.New(T.Trophies, "trophy", 18, Theme.Sign.GoldLip)
	T.Icon.ZIndex = 0
	T.Value = newText(T.Trophies, "Value", "0", "Display", 18, Theme.Sign.Text, { ZIndex = 0 })
	UI.Tab = T
	return T
end

local function buildVitals(holder)
	local root = newFrame(holder, "Vitals", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, K.EDGE, 1, -K.EDGE),
		Size = UDim2.fromOffset(K.VITALS_W, K.VITALS_H),
	})
	UI.VitalsScale = addViewportScale(root) -- (U9-8 look) Vitals.Layout reads it: the card is laid out in its screen px
	root.Visible = next(S.vitalsOwners) == nil -- (a window that asked it to step aside: HudController.SetVitalsHidden)
	UI.Vitals = root
	-- the layout owns the root's position; the damage shake nudges this full-size body instead
	local body = newFrame(root, "Body", { Size = UDim2.fromScale(1, 1) })
	UI.VitalsBody = body

	-- (kit-b U8: the pitch's .vit) the stone card in a wood edge, square, its darker lip along the bottom; the old glow ring
	-- and rim stay as hidden frames (the layout still sizes their corners)
	local card = newFrame(body, "Card", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Sign.Stone,
	})
	UI.Card = card
	UI.CardCorner = Theme.Corner(card, "None")
	UI.CardStroke = Theme.Stroke(card, Theme.Sign.Wood, VG.CARD_EDGE, 0)
	UI.CardStroke.LineJoinMode = Enum.LineJoinMode.Miter
	UI.CardLip = newFrame(card, "Lip", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, VG.CARD_LIP),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Sign.StoneLip,
	})
	local glow = newFrame(card, "Glow", {
		Position = UDim2.fromOffset(-3, -3),
		Size = UDim2.new(1, 6, 1, 6),
		Visible = false,
	})
	UI.GlowCorner = Theme.Corner(glow, "None")
	UI.CardGlow = Theme.Stroke(glow, Theme.Sign.Wood, 5, 1)
	local rim = newFrame(card, "Rim", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		Visible = false,
	})
	UI.RimCorner = Theme.Corner(rim, "None")

	-- (U9-8 look) the HP bar: kit B blocks in the sign red on its RedLip lip (was a tube with a gradient lip and the number
	-- drawn three times over it), the white damage trail and the hit flash on the blocks; the number right of them on the
	-- stone. Then (kit-b U9-8) the stamina blocks, one per dash from full (MaxStamina / DashStaminaCost, rounded down; each
	-- an equal share of MaxStamina: U9-8 look, the narrow fifth block for the rest is gone), ending left of the dash key
	-- (Pitch 2 item 08 C) the name tab behind the card's top edge; the HP track (a wood-edged sunk well: the blocks, the
	-- divider and the number on one face) and the stamina group (a sunk well in the well edge: the bolt, the blocks, the
	-- dash's state and the dash key)
	buildNameTab(body)
	UI.HpTrack = newFrame(body, "HpTrack", { BackgroundTransparency = 0, BackgroundColor3 = Theme.Sign.Wood, ZIndex = 2 })
	UI.HpFace = newFrame(UI.HpTrack, "Face", { BackgroundTransparency = 0, BackgroundColor3 = Theme.Sign.Well, ZIndex = 2 })
	UI.HpDivider = newFrame(UI.HpTrack, "Divider", { BackgroundTransparency = 0, BackgroundColor3 = Theme.Sign.WellEdge, ZIndex = 3 })
	UI.StGroup = newFrame(body, "StaminaGroup", { BackgroundTransparency = 0, BackgroundColor3 = Theme.Sign.WellEdge, ZIndex = 2 })
	UI.StFace = newFrame(UI.StGroup, "Face", { BackgroundTransparency = 0, BackgroundColor3 = Theme.Sign.Well, ZIndex = 2 })
	UI.HpBar = Vitals.NewBlocks(UI.HpTrack, "HealthBar", { Count = VG.HP_BLOCKS, Face = VS.Hp, Lip = Theme.Sign.RedLip, Trail = true, Flash = true })
	UI.HpBar.Root.ZIndex = 3
	UI.HpNum = newText(UI.HpTrack, "HealthNumber", "100 / 100", "Display", VG.Regular.HP_TEXT, Theme.TextOn("Stone"), {
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
	local physics = Config.Physics or {}
	local dashes = math.floor((tonumber(physics.MaxStamina) or 150) / math.max(1, tonumber(physics.DashStaminaCost) or 35))
	UI.StBar = Vitals.NewBlocks(UI.StGroup, "StaminaBar", { Count = math.max(1, dashes), Face = VS.Stamina, Lip = Theme.Sign.GoldLip })
	UI.StBar.Root.ZIndex = 3
	UI.Key = Vitals.NewDashKey(UI.StGroup)
	UI.DashText = newText(UI.StGroup, "DashState", "Dash ready", "Heading", 18, Theme.Sign.TextMuted, { ZIndex = 3 })

	-- lightning badge (in the stamina group), then the heart badge (left of the HP track); (Pitch 2 item 08 C) both bare
	-- pixel icons in their role's lip colour, as the pitch draws them
	local bolt, boltLip = Vitals.NewBadge(UI.StGroup, "StaminaBadge", VS.Stamina, Theme.Sign.GoldLip, "bolt", Theme.Sign.GoldLip)
	bolt:SetAttribute("Ink", VS.BoltInk)
	bolt.ZIndex = 5
	boltLip.ZIndex = 5
	UI.Bolt = { Badge = bolt, Lip = boltLip }

	local heart, heartLip = Vitals.NewBadge(body, "Heart", Theme.Sign.Red, Theme.Sign.RedLip, "heart", Theme.Sign.RedLip)
	heart:SetAttribute("Ink", WHITE)
	heart.ZIndex = 6
	heartLip.ZIndex = 6
	UI.HeartScale = newScale(heart, 1)
	UI.HeartScale.Name = "Pulse" -- (a beat, not a layout scale: PixelIcon keeps the icon's cells as they are)
	UI.Heart = heart
	UI.HeartGlyph = newText(heart, "Glyph", "!", "Display", 34, WHITE, {
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 4,
	})

	-- "Wait for a teammate!" replaces the stamina row while downed (no running or dashing then anyway)
	UI.DownedNotice = newText(body, "DownedNotice", "Wait for a teammate!", "Display", 21, Colors.Bad, {
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		Visible = false,
		ZIndex = 5,
	})
	Util.Create("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 18, Parent = UI.DownedNotice })
	setVitalsGeometry(VG.Regular)
end

----------------------------------------------------------------------
-- Build: currency stack (bottom-left above the vitals, or top-right on short screens)
----------------------------------------------------------------------
local function buildCurrencyRow(parent, entry)
	local def = entry.Def or {}
	local color = def.Color or Colors.Token
	local row = newFrame(parent, "Currency_" .. entry.Id, {
		Size = UDim2.fromOffset(K.STRIP_W, K.STRIP_H),
		Visible = false,
	})

	-- (kit-b U8: the pitch's .cs) one stone block: the tile face, a wood edge, its darker lip along the bottom; the coin is a
	-- square in the currency's colour inside its left end (.ci), the amount in brown. No neon, no sheen, no corner
	local neon = Theme.NeonColor(entry.Neon or "Gold")
	local body = newFrame(row, "Body", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Sign.Tile,
		Size = UDim2.fromScale(1, 1),
	})
	local bodyStroke = Theme.Stroke(body, Theme.Sign.Wood, 2, 0)
	bodyStroke.Name = "SignEdge"
	bodyStroke.LineJoinMode = Enum.LineJoinMode.Miter
	local lip = newFrame(body, "Lip", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Sign.StoneLip,
	})

	local coin, setGem
	if entry.Id == "Gems" then
		-- lobby-shop Task 15 (spec 5.7): the drawn cut gem (client/UI/GemIcon) at coin size; (kit-b U8) on a square of sign
		-- navy, so the cyan gem never sits on a cyan block; setRowGeometry rebuilds the gem whenever the coin changes size
		coin = Vitals.SignSquare(row, "Coin", K.COIN, Theme.Sign.Navy)
		setGem = function(px)
			local old = coin:FindFirstChild("GemIcon")
			if old then
				old:Destroy()
			end
			local gem = require(Client:WaitForChild("UI"):WaitForChild("GemIcon")).New(coin, px, { ZIndex = 2 })
			gem.AnchorPoint = Vector2.new(0.5, 0.5)
			gem.Position = UDim2.fromScale(0.5, 0.5)
		end
		setGem(K.COIN)
	else
		-- the coin square in the currency's own colour (Cash the grass green, Tokens gold), its PixelIcon in the ink that reads
		coin = Vitals.SignSquare(row, "Coin", K.COIN, color)
		local glyph = def.Icon or def.Glyph or "?"
		local icon = PixelIcon.Bitmaps[glyph] and glyph or nil
		local label = newText(coin, "Glyph", icon and "" or glyph, "Display", 30, Theme.TextOn(color), {
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
		if icon then
			setCoinIcon(label, icon, 30)
		end
	end
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 4, 0.5, -2)
	coin.ZIndex = 3

	local amount = newText(row, "Amount", "0", "Display", 32, Theme.Sign.Text, {
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 3,
	})

	local c = {
		Id = entry.Id, Def = def, Attr = entry.Attr, Always = entry.Always == true,
		Row = row, Body = body, Lip = lip, Coin = coin, CoinGlyph = coin:FindFirstChild("Glyph"), SetGem = setGem,
		Neon = neon, Stroke = bodyStroke,
		Amount = amount, AmountScale = newScale(amount, 1), CoinScale = newScale(coin, 1),
		Target = 0, Display = 0, Shown = nil, Seen = false, Available = false, ChipShown = false,
		Width = K.STRIP_W, Compact = nil,
	}

	if entry.Run then
		-- (kit-b U8) the "+n" match chip: a small gold block with brown text in a wood edge
		local chip = newFrame(row, "RunChip", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -7, 0.5, 0),
			Size = UDim2.fromOffset(K.CHIP_W, 32),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Sign.Gold,
			Visible = false,
			ZIndex = 4,
		})
		local chipEdge = Theme.Stroke(chip, Theme.Sign.Wood, 2, 0)
		chipEdge.LineJoinMode = Enum.LineJoinMode.Miter
		c.Chip = chip
		c.RunLabel = newText(chip, "Run", "+0", "Accent", 21, Theme.Sign.Text, {
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 5,
		})
		c.RunScale = newScale(c.RunLabel, 1)
	end
	return c
end

-- Coin size of a row for its geometry: a full pill has the big coin, a compact (paired / top band) one a smaller
-- coin, a strip (bug batch 2 #1: the thin top-right strips) the smallest.
local function coinSizeOf(c)
	if c.Compact == "Strip" then
		return K.STRIP_COIN
	end
	return c.Compact and K.COIN_COMPACT or K.COIN
end

-- Inner geometry of one pill (`compact`: false = full pill, true = compact pill, "Strip" = thin strip).
local function setRowGeometry(c, compact)
	if c.Compact == compact then
		return
	end
	c.Compact = compact
	local strip = compact == "Strip"
	local coinSize = coinSizeOf(c)
	c.Coin.Size = UDim2.fromOffset(coinSize, coinSize)
	if c.CoinGlyph then
		c.CoinGlyph.TextSize = strip and 19 or (compact and 24 or 30)
		local icon = c.CoinGlyph:GetAttribute("PixelIcon")
		if icon then
			setCoinIcon(c.CoinGlyph, icon, c.CoinGlyph.TextSize)
		end
	end
	if c.SetGem then
		c.SetGem(coinSize)
	end
	if c.Chip then
		c.Chip.Size = strip and UDim2.fromOffset(K.STRIP_CHIP_W, K.STRIP_CHIP_H) or UDim2.fromOffset(K.CHIP_W, 32)
		c.Chip.Position = UDim2.new(1, strip and -4 or -7, 0.5, 0)
		c.RunLabel.TextSize = strip and 18 or 21
	end
	-- (kit-b U8) the block spans the row; the coin square sits inside its left end, the amount after it. (LOOK-ui) The HUD's
	-- one edge token: a 3 px wood edge and a 5 px lip at 1080p, whole screen px below it (2 and 4 at 720p), as the vitals card
	-- and the Gift tile: the strip's 1.6 px edge sat right on the Gift's 3 px one
	c.Lip.Size = UDim2.new(1, 0, 0, 5)
	PixelIcon.WholeHeight(c.Lip, 5)
	c.Amount.Position = UDim2.new(0, 4 + coinSize + (strip and 6 or 8), 0.5, -2)
	if c.Stroke then
		PixelIcon.WholeStroke(c.Stroke, 3)
	end
end

local function buildCurrency(holder)
	local root = newFrame(holder, "Currency", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -K.EDGE, 0, K.EDGE),
		Size = UDim2.fromOffset(K.STRIP_W, K.STRIP_H),
	})
	addViewportScale(root)
	UI.Currency = root
	for _, entry in ipairs(CURRENCY_ORDER) do
		if entry.Attr ~= nil or entry.Always then
			Cur[entry.Id] = buildCurrencyRow(root, entry)
		end
	end
end

----------------------------------------------------------------------
-- Build: the match / party cards' parts (kit-b U9-8 A, the owner's pick "Stone signboard")
----------------------------------------------------------------------
-- PK: the cards' kit B parts and their layout (one table keeps the chunk's locals down). A small block is a Frame painted
-- by CloudUI.SignBlock (face, a mitred wood edge drawn outside it, a lip along its bottom; whole screen px): PK.Place puts
-- its visible box, the edge included, at x, y, w, h (the pitch's numbers)
local PK = {}
local SIGN = Theme.Sign

function PK.Paint(f, face, lip, edge, ink)
	CloudUI.SignBlock(f, { Face = face, Lip = lip, Edge = edge, Text = ink or SIGN.Text }, { EdgePx = M.BlockEdge, LipPx = M.BlockLip, Pad = false })
end

function PK.Block(parent, name, face, lip, edge)
	local f = newFrame(parent, name, { BackgroundTransparency = 0, BackgroundColor3 = face })
	PK.Paint(f, face, lip, edge)
	return f
end

-- (the edge as drawn: whole screen px under the card's scale)
function PK.EdgeW()
	return SignKit.Px(M.BlockEdge, currentScale())
end

function PK.Place(f, x, y, w, h)
	local e = PK.EdgeW()
	f.Position = UDim2.fromOffset(x + e, y + e)
	f.Size = UDim2.fromOffset(math.max(1, w - 2 * e), math.max(1, h - 2 * e))
end

-- the card: the wood frame, the stone body inset by the edge with its StoneLip lip (SignKit Frame + Body: whole screen
-- px), the rows' frame (Content.Inner) over it. Returns { Root, Content, Inner }. Its screen-factor UIScale comes first, so
-- every edge and lip under it is fitted to whole px from the start
function PK.Card(holder, name)
	local root = newFrame(holder, name, { Size = UDim2.fromOffset(S.panelW, 200) })
	addViewportScale(root)
	local wood = SignKit.Frame(root, {})
	wood.Active = false -- the HUD never swallows camera drags
	SignKit.Body(wood, { Inset = M.Edge, Lip = M.Lip })
	local content = newFrame(root, "Content", { Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	local inner = newFrame(content, "Inner", {
		Position = UDim2.fromOffset(M.Inset, M.Inset),
		Size = UDim2.new(1, -2 * M.Inset, 1, -(M.Inset + M.Bottom)),
	})
	return { Root = root, Content = content, Inner = inner }
end

-- a kit B plank (CloudUI's Sign skin: its .Text and its Callback stay the button's own) at the panels' 2 / 4 weight
function PK.Plank(parent, name, text, style, w, h, size, callback)
	local b = CloudUI.Button({
		Name = name,
		Text = text,
		Style = style,
		Skin = "Sign",
		TextSize = size,
		Size = UDim2.fromOffset(w, h),
		AnchorPoint = Vector2.new(1, 0.5),
		Callback = callback,
		Parent = parent,
	})
	b:SetAttribute("EdgePx", M.BlockEdge)
	b:SetAttribute("LipPx", M.BlockLip)
	return b
end

-- a level's colour as the picker paints its numbered tile: lightened until its ink reads 4.6:1 (ObbyController's H.readable)
function PK.Readable(color)
	for _ = 1, 6 do
		if Theme.Contrast(Theme.TextOn(color), color) >= 4.6 then
			break
		end
		color = Theme.Lighten(color, 0.08)
	end
	return color
end

-- a level's number: its place in the Sky Obby's list (the picker's tiles), else in Config.Difficulties
function PK.LevelNumber(id)
	local mod = Shared:FindFirstChild("ObbyLevels")
	if mod then
		local ok, OL = pcall(require, mod)
		if ok and type(OL) == "table" and type(OL.IndexOf) == "function" then
			local okI, i = pcall(OL.IndexOf, id)
			if okI and type(i) == "number" then
				return i
			end
		end
	end
	for i, d in ipairs(Config.Difficulties or {}) do
		if d.Id == id then
			return i
		end
	end
	return nil
end

-- the one level badge (the picker's numbered square in the level's colour, a 2 px wood edge, its lip)
function PK.Badge(parent)
	local b = PK.Block(parent, "Badge", SIGN.Sky, SIGN.SkyLip, SIGN.Wood)
	newText(b, "Num", "", "Title", M.BadgeText, SIGN.Text, {
		Size = UDim2.new(1, 0, 1, -M.BlockLip),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	return b
end

function PK.PaintBadge(b, number, color)
	local face = PK.Readable(typeof(color) == "Color3" and color or SIGN.Sky)
	local ink = Theme.TextOn(face)
	PK.Paint(b, face, Theme.Darken(face, 0.22), SIGN.Wood, ink)
	b.Num.Text = number and tostring(number) or "?"
	b.Num.TextColor3 = ink
end

-- the level's name in ink with its gold-lip stars after it (PixelIcon.Lead, the room kept inside the label)
function PK.Stars(label, n)
	n = math.max(0, math.min(5, math.floor(tonumber(n) or 0)))
	if label:GetAttribute("Stars") == n then
		return
	end
	label:SetAttribute("Stars", n)
	local old = label:FindFirstChild("TrailIcon")
	if old then
		old:Destroy()
	end
	if n > 0 then
		PixelIcon.Lead(label, "star", { After = true, Count = n, Px = K.STAR_PX, Gap = M.NameGap, Room = true, Colour = SIGN.GoldLip })
	end
end

-- the design px the stars take after a name's text: their drawn box (a phone's 0.8 keeps 2 px cells, so an 18 px star
-- takes 22.5 design px there) and the gap
function PK.StarsW(label)
	local trail = label:FindFirstChild("TrailIcon")
	return trail and (trail.Size.X.Offset + M.NameGap) or 0
end

-- the level's name at the largest of 22 / 20 / 18 px that fits beside its stars in `room` design px (it cuts with "..."
-- below that)
function PK.FitName(label, room)
	-- (the engine's laid-out width over the measure at the current size: a face that runs wider than Theme.Measure says
	-- is fitted by what it draws)
	local m0 = PK.TextW(label.Text, "Heading", label.TextSize)
	local factor = (m0 > 0) and math.max(1, PK.LabelW(label, "Heading") / m0) or 1
	local size = M.NameText
	for _, s in ipairs({ M.NameText, 20, 18 }) do
		size = s
		if PK.TextW(label.Text, "Heading", s) * factor + 4 <= room - PK.StarsW(label) then
			break
		end
	end
	if label.TextSize ~= size then
		label.TextSize = size
		-- the stars placed anew after the smaller name (not where the cut one ended)
		local n = label:GetAttribute("Stars")
		label:SetAttribute("Stars", nil)
		PK.Stars(label, n or 0)
	end
end

-- the match card's name room: between the badge and Leave (design px)
function PK.MatchNameW()
	return (S.panelW - 2 * M.Inset) - (M.Badge + M.NameGap + M.LeaveW + 2 * PK.EdgeW() + 8) -- (innerWidth is declared below)
end

-- the countdown's pop (1.12x from its left edge) stops short of the head count: the status box is that much narrower
PK.STATUS_POP = 1.12
function PK.StatusW()
	return math.floor(((S.panelW - 2 * M.Inset) - (M.CountW + 8)) / PK.STATUS_POP)
end

-- the party card's level room: between the badge and Change (the leader's) or the card's edge
function PK.LevelRoom()
	return (S.panelW - 2 * M.Inset) - (M.Badge + M.NameGap) - (Pt.Leader and (M.ChangeW + 2 * PK.EdgeW() + 8) or 0)
end

-- a level name re-fits once the engine has laid it out (its TextBounds): the stars stay after the whole name
function PK.RefitOnLayout(label, room)
	local last = nil
	track(label:GetPropertyChangedSignal("TextBounds"):Connect(function()
		local w = label.TextBounds.X
		if w ~= last then
			last = w
			guard("level name fit", function()
				PK.FitName(label, room())
			end)
		end
	end))
end

function PK.Wide()
	return S.panelW >= M.Wide
end

function PK.TextW(text, role, size)
	local ok, m = pcall(Theme.Measure, tostring(text or ""), role, size)
	return (ok and typeof(m) == "Vector2") and math.ceil(m.X) or math.ceil(#tostring(text or "") * size * 0.6)
end

-- a label's text width in its own design px: the wider of Theme.Measure and what the engine laid out (TextBounds: screen
-- px under every UIScale above it, a pop included), so a box sized from it never cuts the text
function PK.LabelW(label, role)
	local w = PK.TextW(label.Text, role, label.TextSize)
	local s, cur = 1, label
	while cur and not cur:IsA("LayerCollector") do
		for _, c in ipairs(cur:GetChildren()) do
			if c:IsA("UIScale") and c.Scale > 0 then
				s = s * c.Scale
			end
		end
		cur = cur.Parent
	end
	local b = label.TextBounds.X
	if b > 0 and s > 0 then
		w = math.max(w, math.ceil(b / s))
	end
	return w
end

----------------------------------------------------------------------
-- Build: team / party chips (shared by the match and party panels)
----------------------------------------------------------------------
-- A member's chip (a small stone block, 2 px wood edge, 4 px lip): the name in ink, cut with "..." where it is long; in a
-- match a state mark (a pixel tick when finished, a pixel x when fallen) and the health: a one-block bar (a well in its
-- wood edge, the red lit part on its RedLip lip, whole px: Vitals.NewBlocks). PK.PaintChip gives it its look: my own chip
-- gold, a fallen one faded (the well, muted ink)
local function newChip(parent, index, withHealth)
	local frame = PK.Block(parent, "Chip" .. tostring(index), SIGN.Tile, SIGN.StoneLip, SIGN.Wood)
	frame.LayoutOrder = index
	frame.Visible = false
	local name = newText(frame, "Name", "", "Heading", M.ChipText, SIGN.Text, {
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local state = newText(frame, "State", "", "Heading", M.StateText, SIGN.RedLip, {
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = withHealth == true,
	})
	local hp = nil
	if withHealth then
		hp = Vitals.NewBlocks(frame, "Health", { Count = 1, Face = SIGN.Red, Lip = SIGN.RedLip })
	end
	return { Frame = frame, Name = name, State = state, Hp = hp, Health = withHealth == true, Frac = 1 }
end

function PK.PaintChip(chip, isMe, down)
	local face, lip, edge = SIGN.Tile, SIGN.StoneLip, SIGN.Wood
	if down then
		face, lip, edge = SIGN.Well, SIGN.Well, SIGN.WellEdge
	elseif isMe then
		face, lip = SIGN.Gold, SIGN.GoldLip
	end
	local key = tostring(isMe) .. tostring(down)
	if chip.Look ~= key then
		chip.Look = key
		PK.Paint(chip.Frame, face, lip, edge)
	end
	chip.Name.TextColor3 = down and SIGN.TextMuted or SIGN.Text
end

-- the parts inside a chip w x h design px (its visible box), on whole screen px under the panel's scale
function PK.LayChip(chip, w, h)
	local e, lip = PK.EdgeW(), M.BlockLip
	local fw, fh = w - 2 * e, h - 2 * e -- the frame's own px (the wood is drawn outside it)
	-- (the name gets the mark's room too while there is no mark)
	local mark = (chip.Health and chip.State:GetAttribute("PixelIcon") ~= nil) and (M.StateText + 8) or 0
	if chip.Health then
		chip.Name.Position = UDim2.fromOffset(8, 0)
		chip.Name.Size = UDim2.new(1, -(16 + mark), 0, 26)
		chip.State.Position = UDim2.new(1, -6, 0, 0)
		chip.State.Size = UDim2.fromOffset(M.StateText + 4, 26)
		local k = currentScale()
		local tw = fw - 12
		chip.Hp.Root.Position = UDim2.fromOffset(6, 26)
		chip.Hp.Root.Size = UDim2.fromOffset(tw, M.HpH)
		chip.Hp.Layout(Vitals.Px(tw, k), Vitals.Px(M.HpH, k), k)
		chip.Hp.SetFraction(chip.Frac or 0)
	else
		chip.Name.Position = UDim2.fromOffset(8, 0)
		chip.Name.Size = UDim2.new(1, -16, 1, -lip)
	end
	chip.Frame.Size = UDim2.fromOffset(fw, fh)
end

-- Lays out `count` chips two to a row (one when alone) inside a holder `width` wide, `h` tall each, 6 px apart. Returns
-- the row count.
local function layoutChips(chips, count, width, h)
	local cols = (count >= 2) and 2 or 1
	local gap = M.ChipGap
	local cellW = math.floor((width - gap * (cols - 1)) / cols)
	local rows = math.max(1, math.ceil(count / cols))
	for i, chip in ipairs(chips) do
		if i <= count then
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			PK.Place(chip.Frame, col * (cellW + gap), row * (h + gap), cellW, h)
			PK.LayChip(chip, cellW, h)
			chip.Frame.Visible = true
		else
			chip.Frame.Visible = false
		end
	end
	return rows
end

-- inner width of the match / party panels (the card less its edge and padding on both sides)
local function innerWidth()
	return S.panelW - 2 * M.Inset
end

----------------------------------------------------------------------
-- Build: match panel (top-left)
----------------------------------------------------------------------
local function buildMatch(holder)
	local panel = PK.Card(holder, "MatchPanel")
	UI.Match = panel
	Items.Match = newItem(panel.Root, UDim2.new(-1.5, 0, 0, 0))
	local inner = panel.Inner
	UI.MatchInner = inner

	-- row A: the level badge, the level's name and stars, Leave
	UI.MatchBadge = PK.Badge(inner)
	UI.MatchTitle = newText(inner, "Difficulty", "", "Heading", M.NameText, SIGN.Text, {
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	PK.RefitOnLayout(UI.MatchTitle, PK.MatchNameW)
	UI.LeaveBtn = PK.Plank(inner, "LeaveMatch", "Leave", "Pink", M.LeaveW, M.LeaveH, M.LeaveText, function(button)
		HudController._onLeaveMatch(button)
	end)

	-- row B: the clock / countdown numerals (left), the run's tokens on a stone tile (right)
	UI.Timer = newText(inner, "Timer", "0:00", "Display", M.TimerText, SIGN.Text, {
		AnchorPoint = Vector2.new(0, 0.5),
	})
	UI.TimerScale = newScale(UI.Timer, 1)
	UI.TimerScale.Name = "Pop" -- (a pop, not a layout scale)
	UI.MatchTokens = newText(inner, "Tokens", "", "Display", M.TokensText, SIGN.Text, {
		AnchorPoint = Vector2.new(1, 0.5),
	})
	CloudUI.SignBlock(UI.MatchTokens, { Face = SIGN.Tile, Lip = SIGN.StoneLip, Edge = SIGN.Wood, Text = SIGN.Text }, { EdgePx = M.BlockEdge, LipPx = M.BlockLip })
	local pad = UI.MatchTokens:FindFirstChild("LipPad")
	if pad then
		pad.PaddingLeft = UDim.new(0, M.TokensPad - M.BlockEdge)
		pad.PaddingRight = UDim.new(0, M.TokensPad - M.BlockEdge)
	end
	UI.TokensScale = newScale(UI.MatchTokens, 1)
	UI.TokensScale.Name = "Pop"
	PixelIcon.Mark(UI.MatchTokens, Theme.Currency.Tokens.Icon, { Colour = SIGN.GoldLip }) -- (kit-b U7a) the coin before the count

	-- the checkpoints: "Checkpoint 2/4" and a row of sky blocks (row B on a wide card, row C on a narrow one)
	UI.CpBar = newFrame(inner, "CheckpointBar", {})
	UI.CpLabel = newText(UI.CpBar, "Label", "Checkpoint 0/0", "Heading", M.CpText, SIGN.TextMuted, {})

	-- the members
	UI.Team = newFrame(inner, "Team", {})
	-- a face that finishes loading lays its text out anew: the tile and the blocks follow it
	local lastTile, lastCp = -1, -1
	track(UI.MatchTokens:GetPropertyChangedSignal("TextBounds"):Connect(function()
		local w = PK.LabelW(UI.MatchTokens, "Display")
		if w ~= lastTile then
			lastTile = w
			guard("match layout", PK.LayoutMatch)
		end
	end))
	track(UI.CpLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
		local w = PK.LabelW(UI.CpLabel, "Heading")
		if w ~= lastCp then
			lastCp = w
			guard("checkpoints", PK.LayCheckpoints)
		end
	end))
end

-- the checkpoints' blocks: `total` sky blocks, `cp` of them lit, the widest that fit `room` design px (26 at most)
function PK.SetCheckpoints(cp, total)
	UI.CpLabel.Text = string.format("Checkpoint %d/%d", cp, total)
	Mt.Cp, Mt.CpTotal = cp, total
	PK.LayCheckpoints()
end

function PK.LayCheckpoints()
	local bar = UI.CpBar
	local total = Mt.CpTotal or 4
	local labelW = PK.LabelW(UI.CpLabel, "Heading") + 2
	local room = bar.Size.X.Offset > 0 and bar.Size.X.Offset or (innerWidth() - labelW - 10)
	local wide = PK.Wide()
	local avail = math.max(10, (wide and (room - labelW - 10) or (room - labelW - 10)))
	local bw = math.max(10, math.min(M.CpBlockW, math.floor((avail - (total - 1) * M.CpBlockGap) / total)))
	local row = bar:FindFirstChild("BlockRow")
	if not row or row:GetAttribute("Count") ~= total or row:GetAttribute("BlockW") ~= bw then
		if row then
			row:Destroy()
		end
		row = SignKit.BlockRow(bar, {
			Count = total, BlockW = bw, BlockH = M.CpH, Gap = M.CpBlockGap, EdgePx = M.BlockEdge, LipPx = M.CpBlockLip,
			Fill = SIGN.Sky, FillLip = SIGN.SkyLip,
		})
		row:SetAttribute("BlockW", bw)
	end
	UI.CpLabel.AnchorPoint = Vector2.new(0, 0.5)
	UI.CpLabel.Position = UDim2.new(0, 0, 0.5, 0)
	UI.CpLabel.Size = UDim2.new(0, labelW, 1, 0)
	if wide then
		row.AnchorPoint = Vector2.new(0, 0.5)
		row.Position = UDim2.new(0, labelW + 10, 0.5, 0)
	else
		row.AnchorPoint = Vector2.new(1, 0.5)
		row.Position = UDim2.new(1, 0, 0.5, 0)
	end
	SignKit.FillBlocks(row, Mt.Cp or 0)
end

-- the tokens tile as wide as its coin and text (the pitch: 10 px, the coin, 6 px, the count, 10 px)
function PK.FitTokens()
	local t = UI.MatchTokens
	local pad = t:FindFirstChild("LipPad") or t:FindFirstChildOfClass("UIPadding")
	local left = pad and pad.PaddingLeft.Offset or 0
	local right = pad and pad.PaddingRight.Offset or 0
	local w = math.ceil(left + PK.LabelW(t, "Display") + right)
	local e = PK.EdgeW()
	t.Size = UDim2.fromOffset(w, M.TokensH - 2 * e)
	t.Position = UDim2.new(1, -e, 0, M.TimerY + M.TimerH / 2)
	return w + 2 * e
end

-- the match card's rows for its width (wide: the checkpoints in row B) and member count; sizes the card
function PK.LayoutMatch()
	if not UI.Match then
		return
	end
	local cw = innerWidth()
	local wide = PK.Wide()
	local e = PK.EdgeW()
	-- row A
	PK.Place(UI.MatchBadge, 0, math.floor((M.RowA - M.Badge) / 2), M.Badge, M.Badge)
	local nameX = M.Badge + M.NameGap
	UI.MatchTitle.Position = UDim2.fromOffset(nameX, 0)
	UI.MatchTitle.Size = UDim2.new(1, -(nameX + M.LeaveW + 2 * e + 8), 0, M.RowA)
	PK.FitName(UI.MatchTitle, PK.MatchNameW())
	UI.LeaveBtn.Position = UDim2.new(1, -e, 0, M.RowA / 2)
	-- row B
	local tileW = PK.FitTokens()
	UI.Timer.Position = UDim2.new(0, 0, 0, M.TimerY + M.TimerH / 2)
	-- (centred on row B, as tall as the countdown's numeral: it overflowed the 34 px row's box)
	UI.Timer.Size = UDim2.new(0, wide and (M.CpX - 8) or math.floor(cw / 2), 0, math.max(M.TimerH, M.CountText))
	local teamY
	if wide then
		local x = math.max(M.CpX, Mt.TimerTextW and (Mt.TimerTextW + 12) or 0)
		UI.CpBar.Position = UDim2.fromOffset(x, M.TimerY + math.floor((M.TimerH - M.CpH) / 2))
		UI.CpBar.Size = UDim2.fromOffset(math.max(10, cw - tileW - 8 - x), M.CpH)
		teamY = M.TimerY + M.TimerH + M.TeamGap
	else
		UI.CpBar.Position = UDim2.fromOffset(0, M.TimerY + M.TimerH + M.RowGap)
		UI.CpBar.Size = UDim2.fromOffset(cw, M.CpH)
		teamY = M.TimerY + M.TimerH + M.RowGap + M.CpH + M.TeamGap
	end
	PK.LayCheckpoints()
	-- the members
	local rows = layoutChips(Mt.Chips, Mt.Count, cw, M.ChipH)
	Mt.Rows = rows
	local teamH = rows * M.ChipH + (rows - 1) * M.ChipGap
	UI.Team.Position = UDim2.fromOffset(0, teamY)
	UI.Team.Size = UDim2.new(1, 0, 0, teamH)
	UI.Match.Root.Size = UDim2.fromOffset(S.panelW, M.Inset + teamY + teamH + M.Bottom)
end

----------------------------------------------------------------------
-- Build: party panel (top-left, lobby only)
----------------------------------------------------------------------
local function buildParty(holder)
	local panel = PK.Card(holder, "PartyPanel")
	UI.Party = panel
	Items.Party = newItem(panel.Root, UDim2.new(-1.5, 0, 0, 0))
	local inner = panel.Inner
	UI.PartyInner = inner

	-- row A: the obby's gold icon square, the portal's name (the plain Section title: the ribbon is for window titles only)
	-- and the big red Leave (the only way out of a locked portal)
	UI.PartyIcon = PK.Block(inner, "Icon", SIGN.Gold, SIGN.GoldLip, SIGN.Wood)
	UI.PartyIconArt = PixelIcon.New(UI.PartyIcon, "mountain", M.IconText, SIGN.Text)
	UI.PartyTitle = Theme.StyleTitle(newText(inner, "Title", "Party", "Title", M.TitleText, SIGN.Text, {
		TextTruncate = Enum.TextTruncate.AtEnd,
	}), "Section") -- (kit-b prep) a HUD panel, not a window: no ribbon
	UI.PartyLeave = PK.Plank(inner, "LeaveParty", "Leave", "Red", M.PartyLeaveW, M.PartyLeaveH, M.PartyLeaveText, function()
		-- one request per press (the server rate-limits too)
		local now = os.clock()
		if now >= Pt.LeaveLockUntil then
			Pt.LeaveLockUntil = now + 0.8
			fireRemote("LeaveParty")
		end
	end)
	-- row B: the countdown after the clock (so "Full! Starting in 3s" fits on a phone too), the head count after the people
	UI.PartyStatus = newText(inner, "Status", "Waiting for players...", "Display", M.StatusText, SIGN.Text, {
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	UI.PartyStatusScale = newScale(UI.PartyStatus, 1)
	UI.PartyStatusScale.Name = "Pop"
	PixelIcon.Lead(UI.PartyStatus, "clock", { Px = K.STAR_PX, Gap = M.NameGap, Colour = SIGN.TextMuted })
	UI.PartyCount = newText(inner, "Count", "0 / 4", "Display", M.StatusText, SIGN.Text, {
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	PixelIcon.Lead(UI.PartyCount, "people", { Px = K.STAR_PX, Gap = M.NameGap, Colour = SIGN.TextMuted })
	-- the members
	UI.PartyTeam = newFrame(inner, "Players", {})
	-- row D: why the pad holds you (the walls) on an older portal's party ...
	UI.PartyHint = newText(inner, "Hint", "Locked until launch", "Label", M.HintText, SIGN.TextMuted, {
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- ... and on the obby's (v5, 6.3): the level badge, the level and its stars; the party leader gets Change, a sky plank
	-- (it opens the level picker)
	UI.PartyBadge = PK.Badge(inner)
	UI.PartyLevel = newText(inner, "Level", "", "Heading", M.NameText, SIGN.Text, {
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
	})
	UI.PartyChange = PK.Plank(inner, "ChangeLevel", "Change", "Sky", M.ChangeW, M.ChangeH, M.ChangeText, function()
		HudController._onChangeLevel()
	end)
	UI.PartyChange.Visible = false
	PK.RefitOnLayout(UI.PartyLevel, PK.LevelRoom)
end

-- the party card's rows for its width and member count; sizes the card
function PK.LayoutParty()
	if not UI.Party then
		return
	end
	local cw = innerWidth()
	local e = PK.EdgeW()
	local k = currentScale()
	-- row A
	PK.Place(UI.PartyIcon, 0, math.floor((M.PartyRowA - M.Badge) / 2), M.Badge, M.Badge)
	local face = M.Badge - 2 * e
	UI.PartyIconArt.Position = Vitals.IconAt(UI.PartyIconArt, Vitals.Px(face, k), Vitals.Px(face - M.BlockLip, k), k)
	local titleX = M.Badge + 10
	UI.PartyTitle.Position = UDim2.fromOffset(titleX, 0)
	UI.PartyTitle.Size = UDim2.new(1, -(titleX + M.PartyLeaveW + 2 * e + 8), 0, M.PartyRowA)
	UI.PartyLeave.Position = UDim2.new(1, -e, 0, M.PartyRowA / 2)
	-- row B
	UI.PartyStatus.Position = UDim2.fromOffset(0, M.StatusY)
	UI.PartyStatus.Size = UDim2.fromOffset(PK.StatusW(), M.StatusH)
	UI.PartyCount.Position = UDim2.new(1, 0, 0, M.StatusY)
	UI.PartyCount.Size = UDim2.fromOffset(M.CountW, M.StatusH)
	-- the members
	local rows = layoutChips(Pt.Chips, Pt.Count, cw, M.PartyChipH)
	Pt.Rows = rows
	local teamH = rows * M.PartyChipH + (rows - 1) * M.ChipGap
	UI.PartyTeam.Position = UDim2.fromOffset(0, M.PlayersY)
	UI.PartyTeam.Size = UDim2.new(1, 0, 0, teamH)
	-- row D
	local y = M.PlayersY + teamH + M.RowGap
	PK.Place(UI.PartyBadge, 0, y + math.floor((M.LevelRowH - M.Badge) / 2), M.Badge, M.Badge)
	local nameX = M.Badge + M.NameGap
	UI.PartyLevel.Position = UDim2.fromOffset(nameX, y)
	UI.PartyLevel.Size = UDim2.new(1, -(nameX + (Pt.Leader and (M.ChangeW + 2 * e + 8) or 0)), 0, M.LevelRowH)
	UI.PartyChange.Position = UDim2.new(1, -e, 0, y + M.LevelRowH / 2)
	UI.PartyHint.Position = UDim2.fromOffset(0, y)
	UI.PartyHint.Size = UDim2.new(1, 0, 0, M.LevelRowH)
	UI.Party.Root.Size = UDim2.fromOffset(S.panelW, M.Inset + y + M.LevelRowH + M.Bottom)
end

----------------------------------------------------------------------
-- Build: title card (top-left, small)
----------------------------------------------------------------------
local function buildTitleCard(holder)
	-- (kit-b U9 completeness gate) a kit B stone block (flat face, wood edge, lip; square), not the old neon card (gold neon
	-- ring, panel gradient, gloss strip). Its title is the plain Section title: the gold ribbon is for window titles only
	local card = newFrame(holder, "TitleCard", {
		Size = UDim2.fromOffset(K.TITLE_W, K.TITLE_H),
		Visible = false,
	})
	CloudUI.SignBlock(card, "Stone", { Pad = false })
	addViewportScale(card)
	UI.TitleCard = card
	Items.Title = newItem(card, UDim2.new(-1.5, 0, 0, 0))

	-- a gold cloud coin at the left
	local coin = newCoin(card, "Coin", 54, Colors.Token, Colors.TokenGlow, Theme.Currency.Tokens.Icon, 30)
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 11, 0.5, 0)

	Theme.StyleTitle(newText(card, "Title", string.upper(tostring(Config.GameName)), "Title", 26, Theme.Sign.Text, {
		-- (kit-b U9) 26 / 16 px: the name and the tagline whole in the card (32 / 19 cut both to "...")
		Position = UDim2.new(0, 74, 0, 10),
		Size = UDim2.new(1, -84, 0, 32),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}), "Section")
	newText(card, "Tagline", tostring(Config.Tagline), "Script", 16, Theme.Sign.Text, {
		Position = UDim2.new(0, 74, 0, 44),
		Size = UDim2.new(1, -84, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

local function hideTitleCard()
	if TC.Shown then
		TC.Shown = false
		TC.Serial = TC.Serial + 1
		present(Items.Title, false)
		applyMargins(true)
	end
end

local function playTitleCard()
	task.wait(1.5)
	if not Items.Title or S.match ~= nil or S.party ~= nil then
		return
	end
	TC.Serial = TC.Serial + 1
	local serial = TC.Serial
	TC.Shown = true
	present(Items.Title, true)
	applyMargins(true)
	task.wait(K.TITLE_CARD_SECONDS)
	if TC.Serial == serial and TC.Shown then
		TC.Shown = false
		present(Items.Title, false)
		applyMargins(true)
	end
end

----------------------------------------------------------------------
-- Health
----------------------------------------------------------------------
local function refreshHealthText()
	local text
	if S.downed then
		text = "DOWNED"
	else
		text = string.format("%d / %d", math.ceil(H.Cur - 0.001), math.ceil(H.Max - 0.001))
	end
	if text ~= H.Text and UI.HpBar then
		H.Text = text
		UI.HpNum.Text = text
		Vitals.Layout() -- (U9-8 look) a max with more digits widens the number's box (a no-op otherwise)
	end
end

local function onHealth(health, snap)
	local humanoid = H.Humanoid
	local max = (humanoid and humanoid.MaxHealth) or H.Max
	if type(max) ~= "number" or max < 1 then
		max = 1
	end
	local cur = Util.Clamp(tonumber(health) or 0, 0, max)
	local frac = cur / max
	if snap then
		H.Fill = frac
		H.Trail = frac
	elseif frac < H.Target - 0.0005 then
		-- took damage: the white trail holds a moment, the bar flashes, the card shakes, the heart pops
		local now = os.clock()
		H.HoldUntil = now + K.TRAIL_HOLD
		H.HitAt = now
		if not H.Low then
			pop(UI.HeartScale, 1.25, 0.35)
		end
	end
	H.Target = frac
	H.Cur = cur
	H.Max = max
	if frac > H.Trail then
		H.Trail = frac
	end
	refreshHealthText()
end

local function setDowned(downed)
	if S.downed == downed then
		return
	end
	S.downed = downed
	if UI.DownedNotice then
		UI.DownedNotice.Visible = downed
	end
	-- the stamina row (blocks, badge, dash key) makes room for the notice
	if UI.StBar then
		UI.StBar.Root.Visible = not downed
	end
	if UI.Key then
		UI.Key.Root.Visible = not downed and not isTouchDevice() -- (kit-b gate U9 r4: a touch screen has the DASH button)
	end
	if UI.Bolt then
		UI.Bolt.Badge.Visible = not downed
	end
	if UI.HeartGlyph then
		if UI.HeartIcon then
			UI.HeartIcon.Visible = not downed
		end
		UI.HeartGlyph.Visible = downed
	end
	Vitals.PaintBorder()
	H.ColorKey = nil -- repaint the bar
	refreshHealthText()
	Vitals.Layout() -- (U9-8 look) DOWNED takes the HP row
end

local function updateHealth(dt, now)
	if not UI.HpBar then
		return
	end
	-- the fill chases the target quickly, the trail waits and then catches up
	local diff = H.Target - H.Fill
	if math.abs(diff) > 0.0005 then
		H.Fill = H.Fill + diff * (1 - math.exp(-dt * 14))
	else
		H.Fill = H.Target
	end
	UI.HpBar.SetFraction(H.Fill)
	if H.Trail > H.Fill then
		if now >= H.HoldUntil then
			H.Trail = math.max(H.Fill, H.Trail - dt * K.TRAIL_SPEED)
		end
	else
		H.Trail = H.Fill
	end
	UI.HpBar.SetTrail(H.Trail)

	-- colour (render gate, the pitch's .vit): the HP bar is red at every level (low health shows on the card's red edge),
	-- the darker red while downed
	local key = "ok"
	local color = VS.Hp
	if S.downed then
		key = "down"
		color = VS.HpDown
	elseif H.Target <= K.LOW_HEALTH then
		key = "low"
	elseif H.Target <= 0.6 then
		key = "mid"
	end
	if key ~= H.ColorKey then
		H.ColorKey = key
		-- (U9-8 look) the lit face and its lip Frame: Sign.Red on Sign.RedLip; downed the RedLip on a darker lip
		UI.HpBar.SetColor(color, (color == VS.Hp) and Theme.Sign.RedLip or Theme.Darken(color, 0.22))
		if not H.Low then
			Vitals.PaintBorder()
		end
	end

	-- a hit: a white flash on the lit blocks and a short shake of the card, both fading out (U9-8 look: the shake moves the
	-- card by whole screen px, so its pixel edges stay crisp while it shakes)
	local bar = UI.HpBar
	local since = now - H.HitAt
	if since >= 0 and since < K.HIT_SECONDS then
		local k = 1 - since / K.HIT_SECONDS
		bar.SetFlash(1 - 0.85 * k)
		local amp = K.SHAKE_PX * k
		local s = (UI.VitalsScale and UI.VitalsScale.Scale) or 1
		local function whole(v)
			return math.floor(v * s + 0.5) / s
		end
		UI.VitalsBody.Position = UDim2.fromOffset(whole(math.sin(since * 70) * amp), whole(math.cos(since * 52) * amp * 0.5))
		H.HitFx = true
	elseif H.HitFx then
		H.HitFx = false
		bar.SetFlash(1)
		UI.VitalsBody.Position = UDim2.fromOffset(0, 0)
	end

	-- low health: the heart beats, the lit blocks breathe and the card's outline glows red with the beat (U9-8 look: the
	-- heart no longer rocks; a turned pixel heart is not on the pixel grid)
	local low = (H.Target <= K.LOW_HEALTH) and not S.downed
	if low then
		local beat = math.max(0, math.sin(now * 7.5))
		beat = beat * beat
		UI.HeartScale.Scale = 1 + 0.16 * beat
		UI.CardStroke.Color = Theme.Sign.RedLip:Lerp(Theme.Sign.Red, 0.25 + 0.75 * beat)
		UI.CardGlow.Transparency = 0.85 - 0.4 * beat
		if not H.HitFx then
			bar.SetFlash(1 - 0.3 * beat)
		end
		H.Low = true
	elseif H.Low then
		H.Low = false
		UI.Heart.Rotation = 0
		UI.HeartScale.Scale = 1
		Vitals.PaintBorder()
		if not H.HitFx then
			bar.SetFlash(1)
		end
	end
	if S.downed then
		UI.DownedNotice.TextTransparency = 0.05 + 0.2 * (0.5 + 0.5 * math.sin(now * 5))
	end
end

local function unbindHumanoid()
	for _, conn in ipairs(H.Conns) do
		conn:Disconnect()
	end
	H.Conns = {}
	H.Humanoid = nil
end

local function bindCharacter(char)
	unbindHumanoid()
	H.Char = char
	local humanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if not humanoid or H.Char ~= char then
		return
	end
	H.Humanoid = humanoid
	table.insert(H.Conns, humanoid.HealthChanged:Connect(function(health)
		guard("health", onHealth, health, false)
	end))
	table.insert(H.Conns, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		guard("max health", onHealth, humanoid.Health, true)
	end))
	guard("health", onHealth, humanoid.Health, true)
end

----------------------------------------------------------------------
-- Stamina + dash key
----------------------------------------------------------------------
local function dashCooldownFraction(now)
	if not movementModule then
		if now < movementNextTry then
			return 0
		end
		movementNextTry = now + 2
		local controllers = script.Parent
		local mod = controllers and controllers:FindFirstChild("MovementController")
		if mod then
			local ok, result = pcall(require, mod)
			if ok and type(result) == "table" then
				movementModule = result
			end
		end
		if not movementModule then
			return 0
		end
	end
	local fn = movementModule.GetDashCooldownFraction
	if type(fn) ~= "function" then
		return 0
	end
	local ok, value = pcall(fn)
	if ok and type(value) == "number" then
		return Util.Clamp(value, 0, 1)
	end
	return 0
end

-- dim 0 = bright .. 1 = empty (kit-b U9-8): the lit blocks and the bolt badge dim toward the stone's tan (no grey in
-- kit B), the bolt fades
function Vitals.PaintStaminaDim(dim)
	local k = 0.8 * dim
	local face = VS.Stamina:Lerp(VS.Dim, k)
	local lip = Theme.Sign.GoldLip:Lerp(VS.DimLip, k)
	UI.Bolt.Badge.BackgroundColor3 = face
	UI.Bolt.Lip.BackgroundColor3 = lip
	if UI.Bolt.Icon then
		Vitals.SetShapeTransparency(UI.Bolt.Icon, 0.5 * dim)
	end
	UI.StBar.SetColor(face, lip)
end

local function updateStamina(dt, now)
	if not UI.StBar or not UI.Key then
		return
	end
	local physics = Config.Physics or {}
	local maxSt = physics.MaxStamina or 100
	local value = player:GetAttribute(Config.Attr.Stamina)
	if type(value) ~= "number" then
		value = maxSt
	end
	local target = Util.Clamp(value / maxSt, 0, 1)
	St.Frac = St.Frac + (target - St.Frac) * (1 - math.exp(-dt * 18))
	if math.abs(target - St.Frac) < 0.002 then
		St.Frac = target
	end
	UI.StBar.SetFraction(St.Frac)

	-- dim: a little below one dash's cost, fully once run dry until running is possible again (eased,
	-- repainted on change only)
	local cost = physics.DashStaminaCost or 35
	if value <= 0.5 then
		St.Drained = true
	elseif value >= K.STAMINA_RECOVER then
		St.Drained = false
	end
	local dimGoal = 0
	if St.Drained then
		dimGoal = 1
	elseif value < cost then
		dimGoal = 0.35
	end
	St.Dim = St.Dim + (dimGoal - St.Dim) * (1 - math.exp(-dt * 10))
	if math.abs(dimGoal - St.Dim) < 0.01 then
		St.Dim = dimGoal
	end
	if math.abs(St.Dim - St.DimDrawn) > 0.02 or (St.Dim == dimGoal and St.DimDrawn ~= dimGoal) then
		St.DimDrawn = St.Dim
		Vitals.PaintStaminaDim(St.Dim)
	end

	-- (kit-b U9-8) the dash key: pressed while the dash cools down, its sky charge rising as the cooldown runs out; the Off
	-- key while there is no dash to pay for; raised again once a dash is possible (no pop: it rises back onto its lip)
	local cd = dashCooldownFraction(now)
	local charge = 1 - cd
	local afford = value >= cost
	local state = (not afford) and "off" or ((cd > 0.001) and "cool" or "ready")
	if state ~= UI.Key.State or (state == "cool" and math.abs(charge - St.Charge) > 0.004) then
		St.Charge = charge
		Vitals.PaintKey(state, charge)
	end
	-- (Pitch 2 item 08 C) the dash's state in words beside the blocks (the stamina group)
	local words = (UI.DashWords or VG.DASH_WORDS)[state]
	if UI.DashText and words and UI.DashText.Text ~= words then
		UI.DashText.Text = words
	end
	St.Ready = state == "ready"
	St.Afford = afford
end

----------------------------------------------------------------------
-- Currencies
----------------------------------------------------------------------
local function readCurrency(c)
	local value = nil
	if c.Id == "Tokens" and State and type(State.Tokens) == "function" then
		local ok, result = pcall(State.Tokens)
		if ok then
			value = result
		end
	end
	if type(value) ~= "number" and c.Attr then
		value = tonumber(player:GetAttribute(c.Attr))
	end
	if type(value) ~= "number" or value ~= value then
		value = 0
	end
	return math.max(0, math.floor(value))
end

local function matchTokensNow()
	return math.max(0, math.floor(tonumber(player:GetAttribute(Config.Attr.MatchTokens)) or 0))
end

local function inMatchNow()
	return S.match ~= nil or player:GetAttribute(Config.Attr.InMatch) == true
end

-- The number shrinks to fit the room left beside the coin and the optional "+n" chip.
local function setAmountText(c, n)
	local text = Theme.Short(n)
	local strip = c.Compact == "Strip"
	local coinSize = coinSizeOf(c)
	local chip = c.ChipShown and ((strip and K.STRIP_CHIP_W or K.CHIP_W) + 6) or 0
	local lead = 4 + coinSize + (strip and 6 or 8) -- (kit-b U8) the coin square sits 4 px inside the block
	local avail = c.Width - lead - 10 - chip
	local size = Util.Clamp(math.floor(avail / (math.max(1, #text) * 0.6)), strip and K.STRIP_TEXT_MIN or 18, strip and K.STRIP_TEXT or 32)
	c.Amount.Text = text
	c.Amount.TextSize = size
	c.Amount.Size = UDim2.new(1, -lead - 10 - chip, 1, -2)
end

-- Places the rows of `list` (top to bottom) in a stack `width` design px wide (bug batch 2 #1: style "Strips", one
-- thin strip per row, right-aligned; in a match the token strip is wider by its "+n" chip, so the chip never covers
-- the number), or (style "Band") side by side, each `width` wide (a landscape phone's top band in a battle). Other
-- rows are hidden.
layoutCurrencyRows = function(list, style, width)
	local shown = {}
	for _, c in ipairs(list) do
		shown[c] = true
	end
	for _, entry in ipairs(CURRENCY_ORDER) do
		local c = Cur[entry.Id]
		if c and not shown[c] then
			c.Row.Visible = false
		end
	end
	for j, c in ipairs(list) do
		local w = K.STRIP_W
		if c.Chip and inMatchNow() then
			w = K.STRIP_W + K.STRIP_CHIP_W + 6
		end
		if style == "Band" then
			w = width
			c.Row.Position = UDim2.fromOffset((j - 1) * (width + K.STRIP_GAP), 0)
		else
			c.Row.Position = UDim2.fromOffset(width - w, (j - 1) * (K.STRIP_H + K.STRIP_GAP))
		end
		c.Row.Size = UDim2.fromOffset(w, K.STRIP_H)
		c.Row.Visible = true
		local resized = c.Width ~= w
		c.Width = w
		setRowGeometry(c, "Strip")
		if resized or c.Shown == nil then
			setAmountText(c, c.Shown or c.Display)
		end
	end
end

-- Cash / Gems become available once their attribute exists (Tokens always is).
local function refreshCurrencyVisibility()
	local changed = false
	for _, entry in ipairs(CURRENCY_ORDER) do
		local c = Cur[entry.Id]
		if c then
			local available = c.Always or (c.Attr ~= nil and type(player:GetAttribute(c.Attr)) == "number")
			if available ~= c.Available then
				c.Available = available
				changed = true
				if available then
					c.Seen = false
					c.Shown = nil
					pop(c.CoinScale, 1.35, 0.45)
				end
			end
		end
	end
	if changed then
		applyMargins(false, true)
	end
end

local function onCurrencyChanged(c)
	if not c.Available then
		return
	end
	local v = readCurrency(c)
	local early = (os.clock() - startedAt) < 4 -- the saved totals arrive right after joining: no fanfare
	if not c.Seen or early or v < c.Target then
		c.Seen = true
		c.Target = v
		c.Display = v
		return
	end
	if v > c.Target then
		c.Target = v
		pop(c.CoinScale, 1.3, 0.4)
		pop(c.AmountScale, 1.2, 0.4)
	end
end

local function refreshRunChip()
	local c = Cur.Tokens
	if not c or not c.Chip then
		return
	end
	local inMatch = inMatchNow()
	if inMatch ~= c.ChipShown then
		c.ChipShown = inMatch
		c.Chip.Visible = inMatch
		setAmountText(c, c.Shown or c.Display)
	end
	local count = matchTokensNow()
	if count ~= Tk.RunSeen then
		local grew = count > Tk.RunSeen
		Tk.RunSeen = count
		c.RunLabel.Text = "+" .. Theme.Short(count)
		if grew then
			pop(c.RunScale, 1.3, 0.35)
		end
	end
end

local function updateCurrencies(dt)
	for _, entry in ipairs(CURRENCY_ORDER) do
		local c = Cur[entry.Id]
		if c and c.Available then
			local diff = c.Target - c.Display
			if diff ~= 0 then
				c.Display = c.Display + diff * (1 - math.exp(-dt * 7))
				if math.abs(c.Target - c.Display) < 0.5 then
					c.Display = c.Target
				end
			end
			local shown = math.floor(c.Display + 0.5)
			if shown ~= c.Shown then
				c.Shown = shown
				setAmountText(c, shown)
			end
		end
	end
end

----------------------------------------------------------------------
-- Match panel
----------------------------------------------------------------------
local function ensureChips(list, parent, count, withHealth)
	for i = #list + 1, count do
		list[i] = newChip(parent, i, withHealth)
	end
end

-- Short screens squeeze the match / party panels (applyMargins decides); a new width or a new scale lays both cards out
-- again (a wide card puts the checkpoints in its clock row; the chips' health bars sit on whole screen px)
setPanelWidth = function(width)
	local k = currentScale()
	if width == S.panelW and k == S.panelK then
		return
	end
	S.panelW, S.panelK = width, k
	PK.LayoutMatch()
	PK.LayoutParty()
end

-- a card that grew or shrank (a row of chips more or less) may now reach the menu column (or no longer does)
local function resizePanel(panel, layout)
	local before = panel.Root.Size.Y.Offset
	layout()
	if panel.Root.Size.Y.Offset ~= before then
		applyMargins(true)
	end
end

local function updateTeam(members)
	local count = math.min(#members, 4)
	ensureChips(Mt.Chips, UI.Team, count, true)
	local localId = player.UserId
	for i = 1, count do
		local m = type(members[i]) == "table" and members[i] or {}
		local chip = Mt.Chips[i]
		local isMe = (m.UserId == localId)
		chip.Name.Text = tostring(m.Name or "?")
		PK.PaintChip(chip, isMe, m.Downed == true)
		chip.Frac = Util.Clamp(tonumber(m.Health) or 0, 0, 1)
		if m.Downed then
			chip.Frac = 0
		end
		chip.Hp.SetFraction(chip.Frac)
		-- (kit-b U7a) the state is a PixelIcon on the empty State label: a tick when finished, an x when downed
		local mark = m.Finished and "check" or (m.Downed and "x" or nil)
		if chip.State:GetAttribute("PixelIcon") ~= mark then
			local old = chip.State:FindFirstChild("Icon")
			if old then
				old:Destroy()
			end
			chip.State:SetAttribute("PixelIcon", mark)
			if mark then
				PixelIcon.Host(chip.State, mark, chip.State.TextSize)
			end
			chip.Name.Size = UDim2.new(1, -(16 + (mark and (M.StateText + 8) or 0)), 0, 26) -- (PK.LayChip's rule)
		end
		chip.State.Text = ""
		chip.State.TextColor3 = m.Finished and SIGN.Good or SIGN.RedLip
	end
	if count ~= Mt.Count then
		Mt.Count = count
		resizePanel(UI.Match, PK.LayoutMatch)
	end
end

-- (kit-b U9-8 A) "7 / 24" after the coin on the stone tile (the vitals card's "52 / 117"); "Get ready!" alone before the
-- run, the coin taken off
local function setTokensText(text, coin)
	PixelIcon.Mark(UI.MatchTokens, coin and Theme.Currency.Tokens.Icon or nil, { Colour = SIGN.GoldLip })
	if UI.MatchTokens.Text ~= text then
		UI.MatchTokens.Text = text
	end
	local before = UI.MatchTokens.Size.X.Offset
	PK.FitTokens()
	if PK.Wide() and UI.MatchTokens.Size.X.Offset ~= before then
		PK.LayoutMatch() -- (the checkpoints end left of the tile)
	end
end

local function updateTokensLine(state)
	local collected = math.floor(tonumber(state.TokensCollected) or 0)
	local text = tostring(collected) .. " / " .. tostring(math.floor(tonumber(state.TotalTokens) or 0))
	local grew = UI.MatchTokens.Text ~= text and Mt.TokensSeen ~= nil and collected > Mt.TokensSeen
	Mt.TokensSeen = collected
	setTokensText(text, true)
	if grew then
		pop(UI.TokensScale, 1.2, 0.3)
	end
end

-- Timer / countdown numerals. Runs every frame for the interpolated clock. (kit-b U9-8 A) inks that read on the stone:
-- 3 red, 2 wood, 1 sky, GO! the gain green, the clock brown (red from a minute left, pulsing from 30 s)
local function numeralColor(n)
	if n == 3 then
		return SIGN.RedLip
	elseif n == 2 then
		return SIGN.Wood
	elseif n == 1 then
		return SIGN.SkyLip
	end
	return SIGN.Text
end

local function setTimerText(text, color, size)
	if UI.Timer.Text ~= text or UI.Timer.TextSize ~= size then
		UI.Timer.Text = text
		UI.Timer.TextSize = size
		-- a long line ("Match over") pushes a wide card's checkpoints right
		local w = PK.TextW(text, "Display", size)
		local over = (w > M.CpX - 8) and w or nil
		if over ~= Mt.TimerTextW then
			Mt.TimerTextW = over
			if PK.Wide() then
				PK.LayoutMatch()
			end
		end
	end
	UI.Timer.TextColor3 = color
end

local function updateMatchClock(now)
	local state = S.match
	if not state or not UI.Timer then
		return
	end
	local phase = state.Phase
	local remaining = math.max(0, Mt.Base - (now - Mt.At))
	if phase == "Countdown" then
		local n = math.max(1, math.ceil(remaining - 0.05))
		if n ~= Mt.Last then
			Mt.Last = n
			setTokensText("Get ready!", false)
			pop(UI.TimerScale, 1.7, 0.5)
		end
		setTimerText(tostring(n), numeralColor(n), M.CountText)
	elseif phase == "Playing" then
		if now < Mt.GoUntil then
			setTimerText("GO!", SIGN.Good, M.CountText)
			return
		end
		local color = SIGN.Text
		if remaining <= 30 then
			color = SIGN.RedLip:Lerp(SIGN.Red, 0.5 + 0.5 * math.sin(now * 6))
		elseif remaining <= 60 then
			color = SIGN.RedLip
		end
		setTimerText(Util.FormatTime(remaining), color, M.TimerText)
	else
		setTimerText("Match over", SIGN.TextMuted, 26)
	end
end

local function disarmLeave()
	LM.ArmedUntil = 0
	if UI.LeaveBtn then
		UI.LeaveBtn.Text = "Leave"
		CloudUI.SetStyle(UI.LeaveBtn, "Pink")
	end
end

-- "Leave" in the match panel needs two presses within a few seconds.
-- v5 (6.3): the party leader's CHANGE chip. Opens the obby level picker (ObbyController.Open, dungeonclient W4)
-- when it exists; until then it asks the server for the next unlocked level (ObbyPick, validated server-side;
-- wraps back to the first level).
function HudController._onChangeLevel()
	if not Pt.Leader then
		return
	end
	local now = os.clock()
	if now < (Pt.ChangeLockUntil or 0) then
		return
	end
	Pt.ChangeLockUntil = now + 0.6
	local controllers = script.Parent
	local obby = controllers and controllers:FindFirstChild("ObbyController")
	if obby then
		local ok, mod = pcall(require, obby)
		if ok and type(mod) == "table" and type(mod.Open) == "function" then
			local opened = pcall(mod.Open)
			if opened then
				return
			end
		end
	end
	local levels = Shared:FindFirstChild("ObbyLevels")
	local okLevels, ObbyLevels = false, nil
	if levels then
		okLevels, ObbyLevels = pcall(require, levels)
	end
	local nextId = nil
	if okLevels and type(ObbyLevels) == "table" and type(ObbyLevels.List) == "function" then
		local bestTimes = nil
		if State and type(State.Get) == "function" then
			local okGet, snap = pcall(State.Get)
			if okGet and type(snap) == "table" and type(snap.Stats) == "table" then
				bestTimes = snap.Stats.BestTimes
			end
		end
		local list = ObbyLevels.List()
		local start = (ObbyLevels.IndexOf and ObbyLevels.IndexOf(Pt.Level)) or 1
		for step = 1, #list do
			local id = list[((start - 1 + step) % #list) + 1]
			if bestTimes == nil or ObbyLevels.IsUnlocked(bestTimes, id) then
				nextId = id
				break
			end
		end
	end
	if nextId and nextId ~= Pt.Level then
		local remote = remoteCache.ObbyPick
		if not remote then
			local ok, found = pcall(Remotes.Get, "ObbyPick")
			remote = ok and found or nil
			remoteCache.ObbyPick = remote
		end
		if remote then
			remote:FireServer(nextId)
		end
	end
end

function HudController._onLeaveMatch(button)
	local now = os.clock()
	if now < LM.LockedUntil then
		return
	end
	if now < LM.ArmedUntil then
		LM.LockedUntil = now + 1
		disarmLeave()
		fireRemote("LeaveMatch")
		return
	end
	LM.ArmedUntil = now + K.LEAVE_CONFIRM_SECONDS
	button.Text = "Sure?"
	CloudUI.SetStyle(button, "Red")
	task.delay(K.LEAVE_CONFIRM_SECONDS + 0.05, function()
		if LM.ArmedUntil > 0 and os.clock() >= LM.ArmedUntil then
			disarmLeave()
		end
	end)
end

local function refreshVisibility()
	local hasMatch = S.match ~= nil
	local showParty = S.party ~= nil and not hasMatch and player:GetAttribute(Config.Attr.InMatch) ~= true
	present(Items.Match, hasMatch and not S.yieldToResult)
	present(Items.Party, showParty)
	if hasMatch or showParty then
		hideTitleCard()
	end
	applyMargins(true) -- the top-left slot is taken or free: step aside for the menu column only when needed
	refreshRunChip()
end

local function clearMatch()
	S.match = nil
	Mt.Phase = nil
	Mt.Last = nil
	Mt.GoUntil = 0
	Mt.TokensSeen = nil
	disarmLeave()
	refreshVisibility()
end

local function applyMatchState(state)
	if type(state) ~= "table" then
		clearMatch()
		return
	end
	local now = os.clock()
	local prevPhase = Mt.Phase
	local phase = state.Phase
	S.match = state
	Mt.Phase = phase
	Mt.Base = tonumber(state.Seconds) or 0
	Mt.At = now
	if phase == "Playing" and prevPhase == "Countdown" then
		Mt.GoUntil = now + K.GO_SECONDS
		Mt.Last = nil
		UI.TimerScale.Scale = 1.7
		tween(UI.TimerScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	if phase ~= "Countdown" then
		Mt.Last = nil
	end

	local color = state.Color
	if typeof(color) ~= "Color3" then
		color = Colors.Stamina
	end
	local diff = Config.GetDifficulty and Config.GetDifficulty(state.DifficultyId) or nil
	-- (kit-b U9-8 A) the one level badge (the picker's numbered tile in the level's colour), then the level's name in ink
	-- and its stars (kit-b U7a: PixelIcons, in the gold's lip on the stone)
	PK.PaintBadge(UI.MatchBadge, PK.LevelNumber(state.DifficultyId), color)
	UI.MatchTitle.Text = tostring(state.DifficultyName or state.DifficultyId or "Match")
	PK.Stars(UI.MatchTitle, diff and diff.Stars or 0)
	PK.FitName(UI.MatchTitle, PK.MatchNameW())

	-- the checkpoints: sky blocks (green stays the one main action's, gold the stars' and the tokens')
	local total = math.max(1, math.floor(tonumber(state.TotalCheckpoints) or 1))
	local cp = Util.Clamp(math.floor(tonumber(state.Checkpoint) or 0), 0, total)
	PK.SetCheckpoints(cp, total)

	if phase ~= "Countdown" then
		updateTokensLine(state)
	end
	UI.LeaveBtn.Visible = (phase ~= "Ended")

	if type(state.Members) == "table" then
		updateTeam(state.Members)
	end
	refreshVisibility()
	updateMatchClock(now)
end

----------------------------------------------------------------------
-- Party panel
----------------------------------------------------------------------
local function partyStatusText(now)
	local party = S.party
	if not party then
		return ""
	end
	local count = type(party.Players) == "table" and #party.Players or 0
	local max = tonumber(party.Max) or Config.Match.MaxPlayers
	if party.Countdown ~= nil and Pt.Base ~= nil then
		local left = math.ceil(Pt.Base - (now - Pt.At) - 0.001)
		if left < 1 then
			return "Launching..." -- the server hands the party to the match any moment now
		end
		if count >= max then
			return "Full! Starting in " .. tostring(left) .. "s"
		end
		return "Starting in " .. tostring(left) .. "s"
	elseif count >= max then
		return "Party full!"
	end
	return "Waiting for players..."
end

-- Does `text` fit `width` design px at `size` in `font`? (Theme.Measure, which knows the Nunito faces; +5 px of spare)
local function textFits(text, font, size, width)
	local ok, bounds = pcall(function()
		return Theme.Measure(text, font, size, 4000)
	end)
	return not ok or typeof(bounds) ~= "Vector2" or bounds.X + 5 <= width
end

-- The largest of `sizes` (design px, largest first) at which `text` fits; the smallest one otherwise.
local function fittingSize(text, font, sizes, width)
	for _, size in ipairs(sizes) do
		if textFits(text, font, size, width) then
			return size
		end
	end
	return sizes[#sizes]
end

-- A squeezed panel (short screens, beside the menu column) shrinks the title / countdown a little and shortens
-- the hint instead of cutting "Medium" down to "Medi...". Runs only when a text or the panel width changed.
local function fitPartyTexts()
	local title, status = UI.PartyTitle.Text, UI.PartyStatus.Text
	if Pt.FitW == S.panelW and Pt.FitTitle == title and Pt.FitStatus == status and Pt.FitHint == Pt.HintLong
		and Pt.FitLevel == Pt.LevelPlain and Pt.FitLeader == Pt.Leader then
		return
	end
	Pt.FitW, Pt.FitTitle, Pt.FitStatus, Pt.FitHint, Pt.FitLevel, Pt.FitLeader = S.panelW, title, status, Pt.HintLong, Pt.LevelPlain, Pt.Leader
	local inner = innerWidth()
	local e = PK.EdgeW()
	local titleRoom = inner - (M.Badge + 10) - (M.PartyLeaveW + 2 * e + 8)
	-- v5: the one obby portal is "Sky Obby", or just "Obby" where that does not fit beside Leave (the Title role reads the
	-- text in capitals)
	local upper = string.upper(title)
	if (upper == "SKY OBBY" or upper == "OBBY") and Pt.LevelPlain then
		local wide = textFits("SKY OBBY", Theme.FontOf(UI.PartyTitle), M.TitleText - 4, titleRoom)
		title = wide and "Sky Obby" or "Obby"
		UI.PartyTitle.Text = title
		Pt.FitTitle = UI.PartyTitle.Text
	end
	UI.PartyTitle.TextSize = fittingSize(UI.PartyTitle.Text, Theme.FontOf(UI.PartyTitle), { M.TitleText, 22, 20 }, titleRoom)
	if Pt.LevelPlain then
		PK.FitName(UI.PartyLevel, PK.LevelRoom())
	end
	-- the countdown beside the head count, after the clock
	local statusRoom = PK.StatusW() - (K.STAR_PX + M.NameGap)
	UI.PartyStatus.TextSize = fittingSize(status, Theme.FontOf(UI.PartyStatus), { M.StatusText, 19, 18 }, statusRoom)
	if textFits(Pt.HintLong, Theme.FontOf(UI.PartyHint), M.HintText, inner) then
		UI.PartyHint.Text = Pt.HintLong
	else
		UI.PartyHint.Text = Pt.HintShort
	end
end

local function updatePartyClock(now)
	if not S.party or not UI.PartyStatus then
		return
	end
	local text = partyStatusText(now)
	if text ~= Pt.LastText then
		Pt.LastText = text
		UI.PartyStatus.Text = text
		if string.find(text, "Starting in", 1, true) then
			pop(UI.PartyStatusScale, PK.STATUS_POP, 0.25)
		end
	end
	fitPartyTexts()
end

local function applyPartyState(state)
	if type(state) ~= "table" then
		S.party = nil
		Pt.Base = nil
		Pt.LastText = nil
		refreshVisibility()
		return
	end
	local now = os.clock()
	S.party = state
	if state.Countdown ~= nil then
		Pt.Base = tonumber(state.Countdown) or 0
		Pt.At = now
	else
		Pt.Base = nil
	end

	local color = state.Color
	if typeof(color) ~= "Color3" then
		color = Colors.Good
	end
	-- v5 (6.3): one obby portal: the title names it, the level row shows the picked level's badge + name + stars; the
	-- leader may change the level (Change). An older payload (one portal per level) keeps its level as the title and the
	-- lock hint in the bottom row
	local levelId = state.Level or state.PortalId
	local diff = Config.GetDifficulty and Config.GetDifficulty(levelId) or nil
	local levelName = tostring((diff and diff.DisplayName) or state.DifficultyName or levelId or "?")
	local starCount = tonumber(state.Stars) or (diff and diff.Stars) or 0
	local obby = state.Level ~= nil
	if obby then
		UI.PartyTitle.Text = "Sky Obby"
	else
		UI.PartyTitle.Text = tostring(state.DifficultyName or "?")
	end
	UI.PartyTitle.TextColor3 = SIGN.Text
	-- (kit-b U9-8 A) the level badge (the picker's numbered tile in the level's colour), the name in ink, its stars after it
	starCount = math.max(0, math.min(5, math.floor(starCount)))
	UI.PartyLevel.Text = levelName
	PK.Stars(UI.PartyLevel, starCount)
	PK.PaintBadge(UI.PartyBadge, PK.LevelNumber(levelId), color)
	Pt.LevelPlain = obby and levelName or nil
	local leader = obby and state.LeaderUserId ~= nil and state.LeaderUserId == player.UserId
	local leaderChanged = leader ~= (Pt.Leader == true)
	Pt.Leader = leader
	Pt.Level = levelId
	UI.PartyLevel.Visible = obby
	UI.PartyBadge.Visible = obby
	UI.PartyHint.Visible = not obby
	UI.PartyChange.Visible = Pt.Leader == true
	-- members are held on the pad by the portal walls until launch (PortalService); Leave is the way out
	if state.Locked == false then
		Pt.HintLong, Pt.HintShort = "In the portal party", "In a party"
	else
		Pt.HintLong, Pt.HintShort = "Locked until launch", "Locked in"
	end
	UI.PartyHint.Text = Pt.HintLong
	Pt.FitHint = nil -- fitPartyTexts (via updatePartyClock below) picks the long or short hint

	local list = type(state.Players) == "table" and state.Players or {}
	local count = math.min(#list, 4)
	ensureChips(Pt.Chips, UI.PartyTeam, count, false)
	for i = 1, count do
		local entry = type(list[i]) == "table" and list[i] or {}
		local chip = Pt.Chips[i]
		chip.Name.Text = tostring(entry.Name or "?")
		PK.PaintChip(chip, entry.UserId == player.UserId, false)
	end
	if count ~= Pt.Count or leaderChanged then
		Pt.Count = count
		resizePanel(UI.Party, PK.LayoutParty)
	end
	UI.PartyCount.Text = string.format("%d / %d", #list, tonumber(state.Max) or Config.Match.MaxPlayers)
	Pt.LastText = nil
	updatePartyClock(now)
	refreshVisibility()
end

-- NotifyController publishes the left edge of its open result card; where it would cover the match panel
-- (portrait phones) the panel slides away until the card closes.
local function checkResultCard()
	local pg = playerGui()
	local notifyGui = pg and pg:FindFirstChild("NimbusNotify")
	local left = notifyGui and notifyGui:GetAttribute("ResultCardLeft")
	if type(left) ~= "number" then
		left = 0
	end
	local right = (padGoals.TopLeft or K.EDGE) + S.panelW * currentScale()
	local yield = left > 0 and right > left - 8
	if yield ~= S.yieldToResult then
		S.yieldToResult = yield
		refreshVisibility()
	end
end

----------------------------------------------------------------------
-- Frame loop
----------------------------------------------------------------------
local function onRender(dt)
	local now = os.clock()
	guard("health", updateHealth, dt, now)
	guard("stamina", updateStamina, dt, now)
	guard("currencies", updateCurrencies, dt)
	guard("match clock", updateMatchClock, now)
	guard("party clock", updatePartyClock, now)
	layoutPoll = layoutPoll + dt
	if layoutPoll >= K.LAYOUT_POLL then
		layoutPoll = 0
		guard("layout", applyMargins, false, false) -- neighbours (menu column, touch buttons) may have moved
		guard("result card", checkResultCard)
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
-- gui-redo review fix: a window that reaches over the vitals card without covering all of it (the Gifts window on PC: its
-- bottom edge cut the card in half at 1080p) hides the card while it is open. `who` names the window, `on` = true while
-- it wants the card gone; the card comes back when the last window lets go. The layout and its published edges stay as
-- they are (nothing else moves).
function HudController.SetVitalsHidden(who, on)
	S.vitalsOwners[type(who) == "string" and who or "?"] = (on == true) or nil
	if UI.Vitals then
		UI.Vitals.Visible = next(S.vitalsOwners) == nil
	end
end

-- (kit-b U9-2) a window that shows the balances itself (the Shop's Gems and Tokens tags) steps the currency strips aside
-- while it is open: `who` names the window, `on` = true while it wants them gone; they come back when the last window
-- lets go. The layout re-runs, so the gift's dock and the published edges follow (nothing else moves).
function HudController.SetCurrencyHidden(who, on)
	S.currencyOwners[type(who) == "string" and who or "?"] = (on == true) or nil
	if UI.Currency then
		relayout()
	end
end

-- (P2 fix A, item 06 A) a card that spans the top band of a portrait phone (BattleController's boss strip) keeps the band
-- down to `bottom` (gui-area px) for itself: the currency strips start under it. `who` names the card; nil / 0 lets go. The
-- layout re-runs only when the reserve changes
function HudController.SetTopReserve(who, bottom)
	who = type(who) == "string" and who or "?"
	local v = (type(bottom) == "number" and bottom > 0) and math.floor(bottom + 0.5) or nil
	if S.topReserve[who] == v then
		return
	end
	S.topReserve[who] = v
	if UI.Currency then
		relayout()
	end
end

-- (LOOK-ui, kitb-look1: the Index and Home windows lay over the vitals card and the strips) which HUD parts a docked
-- window lies over by more than a shared edge (4 px): `rect` its box in screen px (NeonKit.SideRect: x, y, w, h, the top
-- bar included), `above` px of awning over its top. Returns vitals, strips (booleans). The strips' box is the one the
-- layout publishes (TopRightLeft .. the screen's right, the top .. the gift's dock), whether they show or not
function HudController.Overlaps(rect, above)
	if type(rect) ~= "table" or not (tonumber(rect.x) and tonumber(rect.y) and tonumber(rect.w) and tonumber(rect.h)) then
		return false, false
	end
	local inset = 0
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	local x0, x1 = rect.x, rect.x + rect.w
	local y0, y1 = rect.y - inset - (tonumber(above) or 0), rect.y - inset + rect.h
	local function over(ax0, ay0, ax1, ay1)
		return math.min(x1, ax1) - math.max(x0, ax0) > 4 and math.min(y1, ay1) - math.max(y0, ay0) > 4
	end
	local vitals = vitalsRect ~= nil and over(vitalsRect.X, vitalsRect.Y, vitalsRect.X + vitalsRect.W, vitalsRect.Y + vitalsRect.H)
	local strips = false
	local left = published.TopRightLeft
	if left and left > 0 then
		local bottom = (published.GiftSize or 0) > 0 and published.GiftTop or published.TopRightBottom or 0
		strips = over(left, 0, math.huge, bottom)
	end
	return vitals, strips
end

-- Where the HUD currently is (gui-area pixels of an IgnoreGuiInset = false ScreenGui; 0 = nothing there).
function HudController.GetLayout()
	return {
		TopLeftRight = published.TopLeftRight or 0,
		TopLeftBottom = published.TopLeftBottom or 0,
		TopRightBottom = published.TopRightBottom or 0,
		BottomLeftTop = published.BottomLeftTop or 0,
		Scale = currentScale(),
		CurrencyMode = S.currencyMode,
		Vitals = (vitalsRect and UI.Vitals and UI.Vitals.Visible and UI.Gui and UI.Gui.Enabled)
			and { X = vitalsRect.X, Y = vitalsRect.Y, W = vitalsRect.W, H = vitalsRect.H, TabUp = vitalsRect.TabUp } or nil,
		-- quick wins (win 4): the card's rect whether it is shown or hidden (nil only with no card): a fighter's pet battle
		-- hides the card (SetVitalsHidden("Battle", true)) and BattleController puts Cheer up! / Retreat in its slot
		VitalsSlot = (vitalsRect and UI.Vitals) and { X = vitalsRect.X, Y = vitalsRect.Y, W = vitalsRect.W, H = vitalsRect.H, TabUp = vitalsRect.TabUp } or nil,
	}
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local function buildGui()
	M = panelMetrics(isTouchDevice())
	local gui = CloudUI.NewScreenGui("NimbusHud", 10)
	-- (LOOK-ui) every kit edge and lip in it, now and later, on whole screen px
	PixelIcon.WholeTree(gui)
	UI.Gui = gui

	local topLeft = newHolder(gui, "TopLeft")
	local topRight = newHolder(gui, "TopRight")
	local bottomLeft = newHolder(gui, "BottomLeft")
	UI.TopRight = topRight
	UI.BottomLeft = bottomLeft

	buildVitals(bottomLeft) -- (the holder keeps its v3 name; the layout centres the card above the hotbar)
	buildCurrency(topRight)
	buildMatch(topLeft)
	buildParty(topLeft)
	buildTitleCard(topLeft)
	refreshCurrencyVisibility()
	applyMargins(false, true)
end

local function hookRemote(name, handler)
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, name)
		if not ok or not remote then
			warnOnce("remote " .. name, remote)
			return
		end
		remoteCache[name] = remote
		if handler then
			track(remote.OnClientEvent:Connect(handler))
		end
	end)
end

local function hookCamera()
	local cameraConn = nil
	local function bind()
		if cameraConn then
			cameraConn:Disconnect()
			cameraConn = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				guard("relayout", relayout)
				-- the menu and the touch controls lay themselves out on the same signal: measure them again
				task.delay(0.1, function()
					guard("relayout", relayout)
				end)
			end)
		end
		guard("relayout", relayout)
	end
	track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bind))
	bind()
	if UI.Gui then
		track(UI.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			guard("relayout", relayout)
		end))
	end
	-- the viewport can still be 1x1 right at startup: re-check shortly afterwards
	task.delay(0.5, function()
		guard("relayout", relayout)
	end)
	task.delay(2, function()
		guard("relayout", relayout)
	end)
end

local function hookCurrencies()
	for _, entry in ipairs(CURRENCY_ORDER) do
		local c = Cur[entry.Id]
		if c and c.Attr then
			track(player:GetAttributeChangedSignal(c.Attr):Connect(function()
				guard("currency visibility", refreshCurrencyVisibility)
				guard("currency " .. c.Id, onCurrencyChanged, c)
			end))
		end
	end
	if State and State.TokensChanged and Cur.Tokens then
		pcall(function()
			track(State.TokensChanged:Connect(function()
				guard("currency Tokens", onCurrencyChanged, Cur.Tokens)
			end))
		end)
	end
	-- (Pitch 2 item 08 C) the vitals tab's trophies (a sync) and name (a display name change) follow (a no-op unless one moved)
	if State and State.Changed then
		pcall(function()
			track(State.Changed:Connect(function()
				guard("vitals tab", Vitals.Layout)
			end))
		end)
	end
	pcall(function()
		track(player:GetPropertyChangedSignal("DisplayName"):Connect(function()
			guard("vitals tab", Vitals.Layout)
		end))
	end)
	-- snap every counter to its current value (or 0)
	for _, entry in ipairs(CURRENCY_ORDER) do
		local c = Cur[entry.Id]
		if c then
			guard("currency " .. c.Id, onCurrencyChanged, c)
			-- no attribute yet: snap to the saved total when it lands
			c.Seen = c.Attr ~= nil and player:GetAttribute(c.Attr) ~= nil
			c.Shown = nil
		end
	end
end

function HudController.Init()
	if initialized then
		return
	end
	player = Players.LocalPlayer
	if not player then
		return
	end
	initialized = true
	startedAt = os.clock()

	disableDefaultHealth()
	buildGui()
	hookCamera()

	-- player attributes
	local attr = Config.Attr
	hookCurrencies()
	track(player:GetAttributeChangedSignal(attr.MatchTokens):Connect(function()
		guard("run chip", refreshRunChip)
	end))
	track(player:GetAttributeChangedSignal(attr.InMatch):Connect(function()
		if player:GetAttribute(attr.InMatch) ~= true and S.match ~= nil then
			guard("in match", clearMatch) -- back in the lobby: drop a stale match view
		else
			guard("in match", refreshVisibility)
		end
	end))
	track(player:GetAttributeChangedSignal(attr.Downed):Connect(function()
		guard("downed", setDowned, player:GetAttribute(attr.Downed) == true)
	end))
	-- a battle / dungeon run starts or ends: a landscape phone's strips move at once (the battle HUD lays out around them)
	track(player:GetAttributeChangedSignal(attr.InBattle or "InBattle"):Connect(function()
		guard("in battle", applyMargins, false, true)
	end))
	refreshRunChip()
	if player:GetAttribute(attr.Downed) == true then
		setDowned(true)
	end

	-- character / humanoid (respawn safe)
	track(player.CharacterAdded:Connect(function(char)
		task.spawn(bindCharacter, char)
	end))
	track(player.CharacterRemoving:Connect(function(char)
		if H.Char == char then
			unbindHumanoid()
			H.Char = nil
		end
	end))
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	-- server state
	hookRemote("MatchState", function(state)
		guard("match state", applyMatchState, state)
	end)
	hookRemote("PartyState", function(state)
		guard("party state", applyPartyState, state)
	end)
	hookRemote("LeaveParty", nil)
	hookRemote("LeaveMatch", nil)

	track(RunService.RenderStepped:Connect(onRender))
	task.spawn(function()
		guard("title card", playTitleCard)
	end)
end

return HudController
