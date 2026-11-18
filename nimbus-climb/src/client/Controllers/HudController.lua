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

	VITALS_W = 300, -- bug batch 2 #1: a compact card, about the old hotbar's width
	VITALS_H = 100, -- the vitals card (see VG below for its inside; U9-8 look: was 93, the bolt badge and the key sat on its lip)
	VITALS_MIN_W = 236, -- narrowest the vitals get squeezed on a small phone
	HOTBAR_GAP = 8, -- screen px between the old hotbar's top and the vitals card
	HOTBAR_FALLBACK = 78, -- gui px the old item hotbar reached above the bottom edge (14 + 64): the card keeps that spot
	OBSTACLE_GAP = 8, -- kept between the vitals and the column / the touch buttons / Roblox's stick and jump button
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

	PANEL_W = 330, -- match + party panels
	PANEL_MIN_W = 272, -- ... squeezed this far on short screens (keeps their text out of the screen middle)
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
-- Every size here is design px; Vitals.Layout puts them on whole screen px under the card's scale
local VG = {
	Regular = {
		Name = "Regular", H = K.VITALS_H, CARD_H = K.VITALS_H, CARD_X = 0, CARD_CORNER = 0, -- (kit-b U8: square)
		BADGE_X = 25, HEART = 32, HEART_Y = 26, HEART_TEXT = 22, BOLT = 32, BOLT_Y = 72, BADGE_ICON = 18, BADGE_LIP = 4, BARE = false,
		HP_X = 49, HP_Y = 13, HP_H = 26, HP_TEXT = 24, NUM_GAP = 8, PAD_R = 10,
		ST_X = 49, ST_Y = 61, ST_H = 22,
		KEY = 30, KEY_TOP = 57, KEY_GAP = 8, KEY_ICON = 18, KEY_STEP = 2, KEY_SPAN = false,
	},
	Compact = {
		Name = "Compact", H = 80, CARD_H = 76, CARD_X = 0, CARD_CORNER = 0,
		BADGE_X = 19, HEART = 24, HEART_Y = 21, HEART_TEXT = 18, BOLT = 24, BOLT_Y = 52, BADGE_ICON = 18, BADGE_LIP = 0, BARE = true,
		HP_X = 38, HP_Y = 10, HP_H = 22, HP_TEXT = 23, NUM_GAP = 8, PAD_R = 9,
		ST_X = 38, ST_Y = 43, ST_H = 18,
		KEY = 45, KEY_TOP = 13, KEY_GAP = 8, KEY_ICON = 27, KEY_STEP = 3, KEY_SPAN = true,
	},
	HP_BLOCKS = 5, -- (U9-8 look) the HP bar's blocks, a fifth of the health each
	-- the blocks: SignKit.BlockRow's edge, lip and gap (SignKit.Sizes BlockEdge / BlockLip / BlockGap)
	BLOCK_EDGE = 2, BLOCK_LIP = 4, BLOCK_GAP = 4,
	CARD_EDGE = 3, CARD_LIP = 5, BADGE_EDGE = 2, KEY_EDGE = 2, -- (U9-8 look) the card's, a badge's and the key's wood / lip
	KEY_LIP = 4, KEY_SINK = 3, -- the key's lip at rest, and how far its face drops onto it while it cools down (the lip 4 -> 1)
}

local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.Navy or Colors.Ink
local MUTED = Colors.Muted or Colors.CloudShade
local GOLD = Colors.Gold or Colors.Token
local INK = Colors.TextStroke or Colors.Ink
-- v5 (Phase 5, contract 6.6): the Neon kit's colours (dark navy cards, neon borders in their own colour)
local NEON = Theme.Neon
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
			-- (LOOK-ui) a kit tile's wood edge is a Border stroke drawn outside its box: it counts
			local r = rectOf(d, dy)
			local edge = d:FindFirstChild("SignEdge")
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
		{ x0 = 0, y0 = area.Y - stickH, x1 = stickW, y1 = area.Y },
		{ x0 = area.X - (1.5 * j + 10), y0 = area.Y - jumpBottom - j, x1 = area.X - (0.5 * j + 10), y1 = area.Y - jumpBottom },
	}
end

-- Where the vitals card goes (bug batch 2 #1): bottom centre, its bottom at `bottom` (gui px, where the old hotbar's
-- top was) and centred on `cx`, as wide as `w` design px (>= minW). Whatever shares its rows - the menu
-- column, the touch RUN / DASH buttons, Roblox's stick and jump button - limits it from the side it is on; when the
-- room left is narrower than minW the card steps up just above the lowest of those and tries again, but never with
-- its top above `ceiling` (the middle of the screen): there it keeps the last rows, squeezed to minW.
-- Returns left (gui px), width (design px), bottom (gui px).
local function placeVitals(area, k, w, minW, h, bottom, cx, obstacles, side, ceiling)
	local gap = K.OBSTACLE_GAP
	for _ = 1, 6 do
		local top = bottom - h * k
		local left, right = side, area.X - side
		local step = nil
		for _, r in ipairs(obstacles) do
			if top < r.y1 + gap and bottom > r.y0 - gap then
				if (r.x0 + r.x1) / 2 < cx then
					left = math.max(left, r.x1 + gap)
				else
					right = math.min(right, r.x0 - gap)
				end
				step = math.max(step or -math.huge, r.y0 - gap)
			end
		end
		if right - left >= minW * k or not step or step - h * k < ceiling then
			local width = math.floor(Util.Clamp((right - left) / k, minW, w))
			local half = width * k / 2
			local x = Util.Clamp(cx, left + half, math.max(left + half, right - half))
			return x - half, width, bottom
		end
		bottom = step
	end
	return cx - minW * k / 2, minW, bottom
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

	local function clearOfColumn(top, bottom)
		if column and top < column.y1 + K.SPAN_MARGIN and bottom > column.y0 - K.SPAN_MARGIN then
			return math.max(side, column.x1 + K.MENU_CLEARANCE)
		end
		return side
	end
	-- the middle of the screen the game must never write into (the layout rule), in gui-area pixels
	local band = {
		x0 = vp.X * (0.5 - K.CENTRE_TOL), x1 = vp.X * (0.5 + K.CENTRE_TOL),
		y0 = vp.Y * (0.5 - K.CENTRE_TOL) - inset, y1 = vp.Y * (0.5 + K.CENTRE_TOL) - inset,
	}

	-- top-left panels: right of the menu column when they would reach it, and on short screens no wider than
	-- what keeps their text out of the middle of the screen
	local topLeft = side
	local panelW = K.PANEL_W
	if topH > 0 then
		topLeft = clearOfColumn(K.EDGE, K.EDGE + topH * k)
		if topLeft > side and topLeft + K.PANEL_MIN_W * k > area.X - side then
			-- a narrow portrait phone has no room beside the tile column (the panel would run off the right edge): the
			-- panel keeps the corner and MenuController moves the tiles below it (our TopLeftBottom)
			topLeft = side
		end
		if K.EDGE + topH * k > band.y0 then
			panelW = math.floor(Util.Clamp((band.x0 - topLeft - 4) / k, K.PANEL_MIN_W, K.PANEL_W))
		end
	end
	if setPanelWidth then
		setPanelWidth(panelW)
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
	local vitalsBottom = area.Y - K.HOTBAR_FALLBACK * k - K.HOTBAR_GAP
	local cx = area.X / 2
	local obstacles = {}
	if column then
		table.insert(obstacles, column)
	end
	if topH > 0 then
		-- the match / party panel (a 4-player party on a landscape phone reaches the bottom band)
		local w = math.max(hasPanel and panelW or 0, hasTitle and K.TITLE_W or 0)
		table.insert(obstacles, { x0 = topLeft, y0 = K.EDGE, x1 = topLeft + w * k, y1 = K.EDGE + topH * k })
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
	local vitalsLeft, vitalsW
	vitalsLeft, vitalsW, vitalsBottom = placeVitals(area, k, K.VITALS_W, K.VITALS_MIN_W, vitalsH, vitalsBottom, cx, obstacles, side, band.y1)
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
	vitalsRect = { X = math.floor(vitalsLeft + 0.5), Y = math.floor(vitalsBottom + 0.5) - vitalsH * k, W = vitalsW * k, H = vitalsH * k }

	-- currencies: thin strips stacked top-right, right-aligned (the token strip carries the "+n" chip in a match)
	local n = math.max(1, #currencies)
	local stripW = K.STRIP_W
	for _, c in ipairs(currencies) do
		if c.Chip and inMatch then
			stripW = math.max(stripW, K.STRIP_W + K.STRIP_CHIP_W + 6)
		end
	end
	local stackH = n * K.STRIP_H + (n - 1) * K.STRIP_GAP
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
	elseif UI.Currency then
		local blockW, blockH = stripW, stackH
		if vp.X < vp.Y and n > 1 and not inBattle then
			-- portrait: one row, right-aligned (in a battle the narrow stack: the fighter card narrows beside it)
			local rowW = math.floor(Util.Clamp((area.X - 2 * side - (n - 1) * K.STRIP_GAP * k) / n / k, K.ROW_MIN_W, math.min(K.ROW_MAX_W, stripW)))
			blockW, blockH = n * rowW + (n - 1) * K.STRIP_GAP, K.STRIP_H
			if layoutCurrencyRows then
				layoutCurrencyRows(currencies, "Band", rowW)
			end
		elseif layoutCurrencyRows then
			layoutCurrencyRows(currencies, "Strips", stripW)
		end
		UI.Currency.Parent = UI.TopRight
		UI.Currency.AnchorPoint = Vector2.new(1, 0)
		UI.Currency.Size = UDim2.fromOffset(blockW, blockH)
		UI.Currency.Position = UDim2.new(1, -side, 0, K.EDGE)
		topRightBottom = K.EDGE + blockH * k
		topRightLeft = area.X - side - blockW * k
		-- a card that takes the corner for a moment (a dungeon run's result on a phone) hides the strips meanwhile
		local strips = { x0 = topRightLeft, y0 = K.EDGE, x1 = area.X - side, y1 = topRightBottom }
		local yield = cornerCard ~= nil and cornerCard.x0 < strips.x1 and strips.x0 < cornerCard.x1
			and cornerCard.y0 < strips.y1 and strips.y0 < cornerCard.y1
		local want = not yield and next(S.currencyOwners) == nil
		if UI.Currency.Visible ~= want then
			UI.Currency.Visible = want
		end
		-- (kit-b U8) the gift's dock under the strips, in the lobby only (DailyController hides its button in a match or a
		-- battle anyway): DailyController puts its button on this square (GiftLeft / GiftTop / GiftSize), and the toasts,
		-- side panels and the tutorial start under it (TopRightBottom). While a corner card is up (a phone's dungeon End
		-- card) the gift steps aside, so the card starts right under the strips
		if not inMatch and not inBattle and cornerCard == nil then
			giftSize = math.max(K.GIFT_MIN, math.floor(K.GIFT * k)) -- (44 on a 844x390 phone, as the button was)
			giftTop = math.floor(topRightBottom + K.GIFT_GAP * k + 0.5)
			giftLeft = math.floor(area.X - side - giftSize + 0.5)
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

-- Layout numbers of the match / party panels (design px, 1080p). Text is 18+ everywhere, so it stays
-- >= 14 px on a phone; touch devices get a taller Leave button (it then owns the top-right corner of the
-- match panel and the token line drops under it, at the full right edge: squeezed inset left of the button,
-- it ran into the timer / countdown numeral on landscape phones).
local function panelMetrics(touch)
	local m = {
		LeaveW = 88, LeaveH = 32, LeaveText = 20,
		TitleH = 32, TitleText = 28,
		TimerY = 52, TimerH = 38, TimerText = 34, CountText = 42,
		TokensText = 22, TokensY = 52, TokensH = 38, -- the token line (centre y) shares the timer row
		CpY = 76, CpH = 24, CpText = 18,
		ChipH = 30, RowPitch = 34, NameText = 18, StateText = 18,
		-- party panel (a locked portal: Leave is the only way out, so it is big and sits beside the title),
		-- then the countdown row, the member chips and a "Locked until launch" line with the head count
		PartyLeaveW = 116, PartyLeaveNarrowW = 100, PartyLeaveH = 46, PartyLeaveText = 24, -- narrow: squeezed panels
		PartyStatusH = 30, PartyStatusText = 22, PartyHintH = 24, PartyHintText = 18, PartyCountW = 58,
		-- v5 (6.3): the bottom row of an obby party is the level row "Hard ★★★" + the leader's CHANGE chip
		PartyLevelText = 21, ChangeW = 96, ChangeH = 28, ChangeText = 18, -- the chip reaches 4 px into the gap above
	}
	if touch then
		m.LeaveW, m.LeaveH = 92, 40
		-- right under the Leave button (y 41-69): clear of it, of the checkpoint bar (76+) and of the timer text
		m.TokensY, m.TokensH = m.LeaveH + 15, 28
		m.PartyLeaveH, m.PartyLeaveText = 56, 26 -- a fat thumb target (>= 44 px on screen at the 0.8 phone scale)
	end
	m.TeamY = m.CpY + m.CpH + 8
	m.PartyTeamY = m.PartyLeaveH + 6 + m.PartyStatusH + 6
	-- panel = content inset top (cloud bumps) + bottom pad + the inner frame's 6 px top / bottom margins
	local insetTop, _, insetBottom = CloudUI.ContentInset(false, true)
	m.Frame = insetTop + insetBottom + 12
	m.MatchBaseH = m.Frame + m.TeamY - (m.RowPitch - m.ChipH) -- + RowPitch per chip row
	m.PartyBaseH = m.Frame + m.PartyTeamY - (m.RowPitch - m.ChipH) + 6 + m.PartyHintH -- + RowPitch per chip row
	m.TopReserve = math.max(m.MatchBaseH, m.PartyBaseH) + 2 * m.RowPitch -- the tallest top-left panel (4 players)
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
	local screenCell = tonumber(icon:GetAttribute("CellPx")) or math.max(1, math.min(cell, 2), math.ceil(cell * k - 0.5))
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
function Vitals.PlaceBadge(badge, size, cy, g, k)
	local s = Vitals.Px(size, k)
	local x = math.floor(g.BADGE_X * k - s / 2 + 0.5)
	local y = math.floor(cy * k - s / 2 + 0.5)
	badge.Position = UDim2.fromOffset((x + s / 2) / k, (y + s / 2) / k) -- (anchored at its centre: the heart beats there)
	badge.Size = UDim2.fromOffset(s / k, s / k)
	Vitals.FitBadge(badge, g, s, k)
end

-- (kit-b U9-8; U9-8 look) places every part of the vitals card on whole screen px for its geometry (UI.VitalsGeometry),
-- its width (UI.VitalsW, design px) and its scale; a no-op when none of them changed (force: always). The card's own
-- size is snapped by the layout (applyMargins), so its corner is a whole screen px and every part here is a whole number
-- of screen px from it: the card's edge and lip, the HP blocks and the number's box, the stamina blocks ending KEY_GAP
-- before the dash key, the key, the two badges
function Vitals.Layout(force)
	local g = UI.VitalsGeometry
	if not g or not UI.HpBar or not UI.StBar or not UI.Key or not UI.Card then
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
	local numW = math.ceil((Vitals.NumberW(g.HP_TEXT) + 4) * k)
	local sig = g.Name .. ":" .. W .. ":" .. k .. ":" .. numW .. ":" .. tostring(S.downed)
	if UI.LayoutSig == sig and not force then
		return
	end
	UI.LayoutSig = sig
	-- the card: its height, its wood edge and its lip
	UI.Card.Position = UDim2.fromOffset(0, 0)
	UI.Card.Size = UDim2.new(1, 0, 0, px(g.CARD_H) / k)
	UI.CardStroke.Thickness = px(VG.CARD_EDGE) / k
	UI.CardLip.Size = UDim2.new(1, 0, 0, px(VG.CARD_LIP) / k)
	-- the dash key ends the stamina row (or, KEY_SPAN, both rows)
	local key = UI.Key
	local keyS = px(g.KEY)
	local keyX = W - px(g.PAD_R) - keyS
	key.Root.Position = UDim2.fromOffset(keyX / k, at(g.KEY_TOP) / k)
	key.Root.Size = UDim2.fromOffset(keyS / k, keyS / k)
	key.Edge.Thickness = px(VG.KEY_EDGE) / k
	local lip = px(VG.KEY_LIP)
	key.Px = { K = k, Size = keyS, Lip = lip, Sink = math.min(px(VG.KEY_SINK), lip - 1), Step = (key.Icon and tonumber(key.Icon:GetAttribute("CellPx"))) or px(g.KEY_STEP) }
	-- the HP row: the blocks, then the number at its right end
	local right = W - px(g.PAD_R) - (g.KEY_SPAN and (keyS + px(g.KEY_GAP)) or 0)
	local hpX, hpY, hpH = at(g.HP_X), at(g.HP_Y), px(g.HP_H)
	local numX = right - numW
	local hpW = numX - px(g.NUM_GAP) - hpX
	UI.HpBar.Root.Position = UDim2.fromOffset(hpX / k, hpY / k)
	UI.HpBar.Root.Size = UDim2.fromOffset(hpW / k, hpH / k)
	UI.HpBar.Layout(hpW, hpH, k)
	UI.HpBar.Root.Visible = not S.downed
	-- (downed: DOWNED takes the row, beside the heart's "!")
	local numL = S.downed and hpX or numX
	UI.HpNum.Position = UDim2.fromOffset(numL / k, hpY / k)
	UI.HpNum.Size = UDim2.fromOffset((right - numL) / k, hpH / k)
	UI.HpNum.TextXAlignment = S.downed and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
	UI.HpNum.TextSize = g.HP_TEXT
	-- the stamina row
	local stX, stY, stH = at(g.ST_X), at(g.ST_Y), px(g.ST_H)
	local stW = keyX - px(g.KEY_GAP) - stX
	UI.StBar.Root.Position = UDim2.fromOffset(stX / k, stY / k)
	UI.StBar.Root.Size = UDim2.fromOffset(stW / k, stH / k)
	UI.StBar.Layout(stW, stH, k)
	-- the badges, then the key's look again (its sizes are new)
	Vitals.PlaceBadge(UI.Heart, g.HEART, g.HEART_Y, g, k)
	Vitals.PlaceBadge(UI.Bolt.Badge, g.BOLT, g.BOLT_Y, g, k)
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
	UI.DownedNotice.Position = UDim2.fromOffset(g.CARD_X + 12, g.ST_Y - 5)
	UI.DownedNotice.Size = UDim2.new(1, -(g.CARD_X + 12 + g.PAD_R), 0, g.ST_H + 10)
	Vitals.Layout(true)
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
	UI.HpBar = Vitals.NewBlocks(body, "HealthBar", { Count = VG.HP_BLOCKS, Face = VS.Hp, Lip = Theme.Sign.RedLip, Trail = true, Flash = true })
	UI.HpNum = newText(body, "HealthNumber", "100 / 100", "Display", VG.Regular.HP_TEXT, Theme.TextOn("Stone"), {
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
	})
	local physics = Config.Physics or {}
	local dashes = math.floor((tonumber(physics.MaxStamina) or 150) / math.max(1, tonumber(physics.DashStaminaCost) or 35))
	UI.StBar = Vitals.NewBlocks(body, "StaminaBar", { Count = math.max(1, dashes), Face = VS.Stamina, Lip = Theme.Sign.GoldLip })
	UI.Key = Vitals.NewDashKey(body)

	-- lightning badge (under the heart), then the heart badge on top (render gate: gold with a brown bolt, the stamina's
	-- colour; kit-b U9-8: kit B squares with the pixel bolt and heart; U9-8 look: bare on the compact card, in the role's
	-- lip colour, as the gold face itself and the red one read too pale on the stone)
	local bolt, boltLip = Vitals.NewBadge(body, "StaminaBadge", VS.Stamina, Theme.Sign.GoldLip, "bolt", Theme.Sign.GoldLip)
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
-- Build: team / party chips (shared by the match and party panels)
----------------------------------------------------------------------
-- A small name plate: name, optional state glyph, optional mini health bar.
local function newChip(parent, index, withHealth)
	local frame = newFrame(parent, "Chip" .. tostring(index), {
		BackgroundTransparency = 0.1,
		BackgroundColor3 = VS.PanelInk,
		Size = UDim2.fromOffset(120, M.ChipH),
		LayoutOrder = index,
		Visible = false,
	})
	Theme.Corner(frame, "M")
	local stroke = Theme.Stroke(frame, Theme.Darken(NEON.Grey, 0.3), 2, 0.1)
	local name = newText(frame, "Name", "", "Body", M.NameText, WHITE, {
		Position = UDim2.new(0, 8, 0, withHealth and -2 or 0),
		-- party chips (no health) never show a state glyph: their names get that room too
		Size = UDim2.new(1, withHealth and -34 or -16, 1, withHealth and -4 or 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local state = newText(frame, "State", "", "Heading", M.StateText, WHITE, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, withHealth and -2 or 0),
		Size = UDim2.new(0, 24, 1, withHealth and -4 or 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local fill = nil
	if withHealth then
		local track_ = newFrame(frame, "HpTrack", {
			Position = UDim2.new(0, 8, 1, -8),
			Size = UDim2.new(1, -16, 0, 5),
			BackgroundTransparency = 0.1,
			BackgroundColor3 = Colors.Panel,
		})
		round(track_)
		fill = newFrame(track_, "Fill", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0,
			BackgroundColor3 = Colors.Health,
		})
		round(fill)
	end
	return { Frame = frame, Stroke = stroke, Name = name, State = state, Fill = fill }
end

-- Lays out `count` chips in a grid of two columns inside a holder `width` wide. Returns the row count.
local function layoutChips(chips, count, width)
	local cols = (count >= 2) and 2 or 1
	local gap = 6
	local cellW = math.floor((width - gap * (cols - 1)) / cols)
	local rows = math.max(1, math.ceil(count / cols))
	for i, chip in ipairs(chips) do
		if i <= count then
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			chip.Frame.Position = UDim2.fromOffset(col * (cellW + gap), row * M.RowPitch)
			chip.Frame.Size = UDim2.fromOffset(cellW, M.ChipH)
			chip.Frame.Visible = true
		else
			chip.Frame.Visible = false
		end
	end
	return rows
end

-- inner width of the match / party panels (panel - frame pads - inner margins)
local function innerWidth()
	return S.panelW - 2 * CloudUI.Metrics.Pad - 20
end

----------------------------------------------------------------------
-- Build: match panel (top-left)
----------------------------------------------------------------------
local function buildMatch(holder)
	local panel = CloudUI.Panel({
		Name = "MatchPanel",
		Size = UDim2.fromOffset(S.panelW, M.MatchBaseH + M.RowPitch),
		Accent = Colors.Stamina,
		Parent = holder,
	})
	panel.Body.Active = false -- the HUD never swallows camera drags
	addViewportScale(panel.Root)
	UI.Match = panel
	Items.Match = newItem(panel.Root, UDim2.new(-1.5, 0, 0, 0))

	local inner = newFrame(panel.Content, "Inner", {
		Position = UDim2.new(0, 10, 0, 6),
		Size = UDim2.new(1, -20, 1, -12),
	})
	UI.MatchInner = inner

	-- row A: difficulty (+ stars) and the Leave button
	UI.MatchTitle = newText(inner, "Difficulty", "", "Title", M.TitleText, WHITE, {
		Size = UDim2.new(1, -(M.LeaveW + 8), 0, M.TitleH),
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	UI.LeaveBtn = CloudUI.Button({
		Name = "LeaveMatch",
		Text = "Leave",
		Style = "Pink",
		TextSize = M.LeaveText,
		Size = UDim2.fromOffset(M.LeaveW, M.LeaveH),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -M.LeaveW / 2, 0, M.LeaveH / 2),
		Callback = function(button)
			HudController._onLeaveMatch(button)
		end,
		Parent = inner,
	})

	-- row B: timer / countdown numerals (left), token progress (right)
	UI.Timer = newText(inner, "Timer", "0:00", "Display", M.TimerText, WHITE, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0, M.TimerY),
		Size = UDim2.new(0.5, 0, 0, M.TimerH),
	})
	UI.TimerScale = newScale(UI.Timer, 1)
	UI.MatchTokens = newText(inner, "Tokens", "", "Toast", M.TokensText, Colors.TokenGlow, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0, M.TokensY),
		Size = UDim2.new(0.55, 0, 0, M.TokensH),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	UI.MatchTokensIcon = PixelIcon.Lead(UI.MatchTokens, Theme.Currency.Tokens.Icon) -- (kit-b U7a) the coin before the count
	UI.TokensScale = newScale(UI.MatchTokens, 1)

	-- checkpoint progress
	UI.CpBar = CloudUI.Bar({
		Name = "CheckpointBar",
		Height = M.CpH,
		TextSize = M.CpText,
		Color = Colors.Stamina,
		Label = "Checkpoint 0/0",
		Position = UDim2.fromOffset(0, M.CpY),
		Size = UDim2.new(1, 0, 0, M.CpH),
		Parent = inner,
	})

	-- team chips
	UI.Team = newFrame(inner, "Team", {
		Position = UDim2.fromOffset(0, M.TeamY),
		Size = UDim2.new(1, 0, 1, -M.TeamY),
	})
end

----------------------------------------------------------------------
-- Build: party panel (top-left, lobby only)
----------------------------------------------------------------------
local function buildParty(holder)
	local panel = CloudUI.Panel({
		Name = "PartyPanel",
		Size = UDim2.fromOffset(S.panelW, M.PartyBaseH + M.RowPitch),
		Accent = Colors.Good,
		Parent = holder,
	})
	panel.Body.Active = false
	addViewportScale(panel.Root)
	UI.Party = panel
	Items.Party = newItem(panel.Root, UDim2.new(-1.5, 0, 0, 0))

	local inner = newFrame(panel.Content, "Inner", {
		Position = UDim2.new(0, 10, 0, 6),
		Size = UDim2.new(1, -20, 1, -12),
	})
	UI.PartyInner = inner

	-- row A: the portal's name and the big red Leave button (the only way out of a locked portal)
	UI.PartyTitle = Theme.StyleTitle(newText(inner, "Title", "Party", "Title", M.TitleText, WHITE, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0, M.PartyLeaveH / 2),
		Size = UDim2.new(1, -(M.PartyLeaveW + 8), 0, M.TitleH),
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}), "Section") -- (kit-b prep) a HUD panel, not a window: no ribbon
	UI.PartyLeave = CloudUI.Button({
		Name = "LeaveParty",
		Text = "Leave",
		Style = "Red",
		TextSize = M.PartyLeaveText,
		Size = UDim2.fromOffset(M.PartyLeaveW, M.PartyLeaveH),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -M.PartyLeaveW / 2, 0, M.PartyLeaveH / 2),
		Callback = function()
			-- one request per press (the server rate-limits too)
			local now = os.clock()
			if now >= Pt.LeaveLockUntil then
				Pt.LeaveLockUntil = now + 0.8
				fireRemote("LeaveParty")
			end
		end,
		Parent = inner,
	})
	-- row B: the countdown, full width so "Full! Starting in 3s" fits on a phone too
	UI.PartyStatus = newText(inner, "Status", "Waiting for players...", "Display", M.PartyStatusText, Colors.TokenGlow, {
		Position = UDim2.fromOffset(0, M.PartyLeaveH + 6),
		Size = UDim2.new(1, 0, 0, M.PartyStatusH),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	UI.PartyStatusScale = newScale(UI.PartyStatus, 1)
	-- row C: the members
	UI.PartyTeam = newFrame(inner, "Players", {
		Position = UDim2.fromOffset(0, M.PartyTeamY),
		Size = UDim2.new(1, 0, 0, M.RowPitch),
	})
	-- row D: why the pad holds you (the walls) + the head count
	UI.PartyHint = newText(inner, "Hint", "Locked until launch", "Label", M.PartyHintText, MUTED, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, -(M.PartyCountW + 6), 0, M.PartyHintH),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	UI.PartyCount = newText(inner, "Count", "0/4", "Heading", 21, WHITE, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.fromOffset(M.PartyCountW, M.PartyHintH),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	-- row D of an obby party (v5, 6.3): the level and its stars in place of the hint; the party leader gets a
	-- CHANGE chip in place of the head count (it opens the level picker)
	UI.PartyLevel = newText(inner, "Level", "", "Heading", M.PartyLevelText, WHITE, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, -(M.PartyCountW + 6), 0, M.PartyHintH),
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
	})
	UI.PartyChange = CloudUI.Button({
		Name = "ChangeLevel",
		Text = "Change",
		Style = "Blue",
		TextSize = M.ChangeText,
		Size = UDim2.fromOffset(M.ChangeW, M.ChangeH),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Callback = function()
			HudController._onChangeLevel()
		end,
		Parent = inner,
	})
	UI.PartyChange.Visible = false
end

----------------------------------------------------------------------
-- Build: title card (top-left, small)
----------------------------------------------------------------------
local function buildTitleCard(holder)
	local card = newFrame(holder, "TitleCard", {
		Size = UDim2.fromOffset(K.TITLE_W, K.TITLE_H),
		BackgroundTransparency = 0.06,
		BackgroundColor3 = WHITE, -- the gradient below supplies the colour
		Visible = false,
	})
	Theme.Corner(card, "M")
	Theme.Stroke(card, NEON.Gold, 3, 0)
	Theme.Gradient(card, VS.PanelTop, VS.PanelBottom, 90)
	addViewportScale(card)
	UI.TitleCard = card
	Items.Title = newItem(card, UDim2.new(-1.5, 0, 0, 0))

	local gloss = newFrame(card, "Gloss", {
		Position = UDim2.new(0, 10, 0, 5),
		Size = UDim2.new(1, -20, 0, 9),
		BackgroundTransparency = 0.84,
		BackgroundColor3 = WHITE,
	})
	round(gloss)

	-- a gold cloud coin at the left
	local coin = newCoin(card, "Coin", 54, Colors.Token, Colors.TokenGlow, Theme.Currency.Tokens.Icon, 30)
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 11, 0.5, 0)

	local title = Theme.StyleTitle(newText(card, "Title", string.upper(tostring(Config.GameName)), "Title", 32, WHITE, {
		Position = UDim2.new(0, 74, 0, 6),
		Size = UDim2.new(1, -84, 0, 38),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}), "OwnGradient")
	Theme.Gradient(title, Colors.Cloud, Colors.TokenGlow, 90)
	newText(card, "Tagline", tostring(Config.Tagline), "Script", 19, Colors.Muted or Colors.Cloud, {
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
		UI.Key.Root.Visible = not downed
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
	local text = Theme.ShortNumber(n)
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
		c.RunLabel.Text = "+" .. Theme.ShortNumber(count)
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

-- Short screens squeeze the match / party panels a little (applyMargins decides); the chips follow.
setPanelWidth = function(width)
	if width == S.panelW then
		return
	end
	S.panelW = width
	for _, panel in ipairs({ UI.Match, UI.Party }) do
		if panel then
			panel.Root.Size = UDim2.fromOffset(width, panel.Root.Size.Y.Offset)
		end
	end
	layoutChips(Mt.Chips, Mt.Count, innerWidth())
	layoutChips(Pt.Chips, Pt.Count, innerWidth())
end

local function resizePanel(panel, base, rows)
	local h = base + rows * M.RowPitch
	panel.Root.Size = UDim2.fromOffset(S.panelW, h)
	-- a taller panel may now reach the menu column (or a shorter one no longer does)
	applyMargins(true)
end

local function updateTeam(members)
	local count = math.min(#members, 4)
	Mt.Count = count
	ensureChips(Mt.Chips, UI.Team, count, true)
	local rows = layoutChips(Mt.Chips, count, innerWidth())
	if rows ~= Mt.Rows then
		Mt.Rows = rows
		resizePanel(UI.Match, M.MatchBaseH, rows)
	end
	local localId = player.UserId
	for i = 1, count do
		local m = type(members[i]) == "table" and members[i] or {}
		local chip = Mt.Chips[i]
		local isMe = (m.UserId == localId)
		chip.Name.Text = tostring(m.Name or "?")
		chip.Name.TextColor3 = isMe and Colors.TokenGlow or WHITE
		local frac = Util.Clamp(tonumber(m.Health) or 0, 0, 1)
		chip.Fill.Size = UDim2.fromScale(frac, 1)
		chip.Fill.BackgroundColor3 = Theme.HealthColor(frac)
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
		end
		chip.State.Text = ""
		if m.Finished then
			chip.State.TextColor3 = Colors.Good
			chip.Stroke.Color = Colors.Good
		elseif m.Downed then
			chip.State.TextColor3 = Colors.Bad
			chip.Stroke.Color = Colors.Bad
		else
			chip.Stroke.Color = isMe and NEON.Gold or Theme.Darken(NEON.Grey, 0.3)
		end
	end
end

local function updateTokensLine(state)
	local text = tostring(math.floor(tonumber(state.TokensCollected) or 0))
		.. "/" .. tostring(math.floor(tonumber(state.TotalTokens) or 0))
	UI.MatchTokensIcon.Visible = true -- (kit-b U7a) the coin leads the count ("Get ready!" hides it)
	if UI.MatchTokens.Text ~= text then
		local grew = Mt.TokensSeen ~= nil and (tonumber(state.TokensCollected) or 0) > Mt.TokensSeen
		Mt.TokensSeen = tonumber(state.TokensCollected) or 0
		UI.MatchTokens.Text = text
		if grew then
			pop(UI.TokensScale, 1.2, 0.3)
		end
	end
end

-- Timer / countdown numerals. Runs every frame for the interpolated clock.
local function numeralColor(n)
	local rainbow = Colors.Rainbow
	if n == 3 then
		return rainbow[3]
	elseif n == 2 then
		return rainbow[2]
	elseif n == 1 then
		return rainbow[1]
	end
	return rainbow[5]
end

local function setTimerText(text, color, size)
	if UI.Timer.Text ~= text then
		UI.Timer.Text = text
	end
	UI.Timer.TextColor3 = color
	if UI.Timer.TextSize ~= size then
		UI.Timer.TextSize = size
	end
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
			UI.MatchTokens.Text = "Get ready!"
			UI.MatchTokensIcon.Visible = false
			pop(UI.TimerScale, 1.7, 0.5)
		end
		setTimerText(tostring(n), numeralColor(n), M.CountText)
	elseif phase == "Playing" then
		if now < Mt.GoUntil then
			setTimerText("GO!", Colors.Good, M.CountText)
			return
		end
		local color = WHITE
		if remaining <= 30 then
			color = Colors.Bad:Lerp(WHITE, 0.5 + 0.5 * math.sin(now * 6))
		elseif remaining <= 60 then
			color = Colors.HealthMid
		end
		setTimerText(Util.FormatTime(remaining), color, M.TimerText)
	else
		setTimerText("Match over", Colors.Muted or WHITE, 26)
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
	-- (kit-b U7a) the difficulty's stars are gold PixelIcons after its name
	UI.MatchTitle.Text = tostring(state.DifficultyName or state.DifficultyId or "Match")
	local starCount = diff and math.max(0, math.min(5, math.floor(tonumber(diff.Stars) or 0))) or 0
	if UI.MatchTitle:GetAttribute("Stars") ~= starCount then
		UI.MatchTitle:SetAttribute("Stars", starCount)
		local old = UI.MatchTitle:FindFirstChild("TrailIcon")
		if old then
			old:Destroy()
		end
		if starCount > 0 then
			PixelIcon.Lead(UI.MatchTitle, "star", { After = true, Count = starCount, Px = K.STAR_PX, Colour = GOLD })
		end
	end
	UI.MatchTitle.TextColor3 = Theme.Lighten(color, 0.25)

	local total = math.max(1, math.floor(tonumber(state.TotalCheckpoints) or 1))
	local cp = Util.Clamp(math.floor(tonumber(state.Checkpoint) or 0), 0, total)
	UI.CpBar.SetColor(color)
	UI.CpBar.SetFraction(cp / total, true)
	UI.CpBar.SetText(string.format("Checkpoint %d/%d", cp, total))

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
		and Pt.FitLevel == Pt.LevelPlain then
		return
	end
	Pt.FitW, Pt.FitTitle, Pt.FitStatus, Pt.FitHint, Pt.FitLevel = S.panelW, title, status, Pt.HintLong, Pt.LevelPlain
	local inner = innerWidth()
	-- a squeezed panel gives the title a little of the Leave button's width (the button stays a big target)
	local leaveW = (inner < 260) and M.PartyLeaveNarrowW or M.PartyLeaveW
	if UI.PartyLeave.Size.X.Offset ~= leaveW then
		UI.PartyLeave.Size = UDim2.fromOffset(leaveW, M.PartyLeaveH)
		UI.PartyLeave.Position = UDim2.new(1, -leaveW / 2, 0, M.PartyLeaveH / 2)
		UI.PartyTitle.Size = UDim2.new(1, -(leaveW + 8), 0, M.TitleH)
	end
	-- v5: the one obby portal is "Sky Obby", or just "Obby" where that does not fit beside Leave
	if (title == "Sky Obby" or title == "Obby") and Pt.LevelPlain then
		local wide = inner >= 260 and textFits("Sky Obby", Theme.FontOf(UI.PartyTitle), 24, inner - leaveW - 16)
		title = wide and "Sky Obby" or "Obby"
		UI.PartyTitle.Text = title
		Pt.FitTitle = title
	end
	UI.PartyTitle.TextSize = fittingSize(title, Theme.FontOf(UI.PartyTitle), { M.TitleText, 26, 24, 22 }, inner - leaveW - 8)
	if Pt.LevelPlain then
		local room = inner - ((Pt.Leader and M.ChangeW or M.PartyCountW) + 6)
		UI.PartyLevel.TextSize = fittingSize(Pt.LevelPlain, Theme.FontOf(UI.PartyLevel), { 20, 19, 18 }, room - (Pt.StarsW or 0))
	end
	UI.PartyStatus.TextSize = fittingSize(status, Theme.FontOf(UI.PartyStatus), { M.PartyStatusText, 20, 19 }, inner)
	if textFits(Pt.HintLong, Theme.FontOf(UI.PartyHint), M.PartyHintText, inner - M.PartyCountW - 6) then
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
			pop(UI.PartyStatusScale, 1.12, 0.25)
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
	-- v5 (6.3): one obby portal: the title names it, the level row shows the picked level + stars; the leader
	-- may change the level (CHANGE). An older payload (one portal per level) keeps its level as the title.
	local levelId = state.Level or state.PortalId
	local diff = Config.GetDifficulty and Config.GetDifficulty(levelId) or nil
	local levelName = tostring((diff and diff.DisplayName) or state.DifficultyName or levelId or "?")
	local starCount = tonumber(state.Stars) or (diff and diff.Stars) or 0
	local obby = state.Level ~= nil
	if obby then
		UI.PartyTitle.Text = "Sky Obby"
		UI.PartyTitle.TextColor3 = WHITE
	else
		UI.PartyTitle.Text = tostring(state.DifficultyName or "?")
		UI.PartyTitle.TextColor3 = Theme.Lighten(color, 0.25)
	end
	-- (kit-b U7a) the level's stars are gold PixelIcons after its name; fitting leaves them their room (Pt.StarsW)
	starCount = math.max(0, math.min(5, math.floor(starCount)))
	UI.PartyLevel.Text = levelName
	if UI.PartyLevel:GetAttribute("Stars") ~= starCount then
		UI.PartyLevel:SetAttribute("Stars", starCount)
		local old = UI.PartyLevel:FindFirstChild("TrailIcon")
		if old then
			old:Destroy()
		end
		if starCount > 0 then
			PixelIcon.Lead(UI.PartyLevel, "star", { After = true, Count = starCount, Px = K.STAR_PX, Colour = NEON.Gold })
		end
	end
	Pt.StarsW = (starCount > 0) and (starCount * K.STAR_PX + (starCount - 1) * math.floor(K.STAR_PX / 9) + math.max(3, math.floor(K.STAR_PX / 4))) or 0
	Pt.LevelPlain = obby and levelName or nil
	UI.PartyLevel.TextColor3 = Theme.Lighten(color, 0.3)
	Pt.Leader = obby and state.LeaderUserId ~= nil and state.LeaderUserId == player.UserId
	Pt.Level = levelId
	UI.PartyLevel.Visible = obby
	UI.PartyHint.Visible = not obby
	UI.PartyChange.Visible = Pt.Leader == true
	UI.PartyCount.Visible = not Pt.Leader
	UI.PartyLevel.Size = UDim2.new(1, -((Pt.Leader and M.ChangeW or M.PartyCountW) + 6), 0, M.PartyHintH)
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
	Pt.Count = count
	ensureChips(Pt.Chips, UI.PartyTeam, count, false)
	local rows = layoutChips(Pt.Chips, count, innerWidth())
	if rows ~= Pt.Rows then
		Pt.Rows = rows
		UI.PartyTeam.Size = UDim2.new(1, 0, 0, rows * M.RowPitch)
		resizePanel(UI.Party, M.PartyBaseH, rows)
	end
	for i = 1, count do
		local entry = type(list[i]) == "table" and list[i] or {}
		local chip = Pt.Chips[i]
		local isMe = (entry.UserId == player.UserId)
		chip.Name.Text = tostring(entry.Name or "?")
		chip.Name.TextColor3 = isMe and Colors.TokenGlow or WHITE
		chip.Stroke.Color = isMe and NEON.Gold or Theme.Darken(NEON.Grey, 0.3)
	end
	UI.PartyCount.Text = string.format("%d/%d", #list, tonumber(state.Max) or Config.Match.MaxPlayers)
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
			and { X = vitalsRect.X, Y = vitalsRect.Y, W = vitalsRect.W, H = vitalsRect.H } or nil,
		-- quick wins (win 4): the card's rect whether it is shown or hidden (nil only with no card): a fighter's pet battle
		-- hides the card (SetVitalsHidden("Battle", true)) and BattleController puts Cheer up! / Retreat in its slot
		VitalsSlot = (vitalsRect and UI.Vitals) and { X = vitalsRect.X, Y = vitalsRect.Y, W = vitalsRect.W, H = vitalsRect.H } or nil,
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
