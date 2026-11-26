-- ShopEggs (client UI; lobby-shop Task 22, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.3 "Eggs tab", 16.5
-- "Fixes"): the Shop's Eggs page. ShopController builds it into its Page_Eggs frame, lays it out on every resize and
-- repaints it on every refresh. It never decides a price or a roll: every button goes through EggStage.Request (the one
-- BuyRoulette sender: the FIRE_GAP, the pending flag, the "You need ..." and policy toasts); the server checks again.
--
--   ShopEggs.Build(page, ctx)        page = the Page_Eggs Frame. In it: a ScrollingFrame "Scroll" holding ShopCard_Secret
--                                    (the hero, attribute Hero = true) and the ScrollingFrame "Cards" (ShopCard_Cloud /
--                                    _Storm / _Sky / _Celestial), and the phone's right "Fade" (48 px while more of the
--                                    row is to the right). ctx = { Tap() (the click sound), Close() (shop-area: TRAVEL
--                                    closes the Shop) } | nil
--   ShopEggs.Layout(page, box, mode) box = { W, H } (the content box, design px); mode:
--                                    "PC" / "Compact": the hero 240 tall at (0, 16) (the machine 190 x 218 at (26, 10),
--                                      "Secret Roulette" 46 px at (240, 22), the odds line at (240, 84), the PityChip
--                                      400 x 48 at (240, 132), Spin 290 x 100 at (w - 320, 66), the hint under it), the
--                                      card row at y 276: four cards (w - 48) / 4 wide (sideways under 250), 550 tall
--                                      (NamePlate, the machine 130 x 150 at y 76, Odds_* rows 40 tall from y 234, Spin
--                                      64 at y 400, Spin3 / SpinGems at y 476 half width, the hint). A body under 826 px
--                                      shrinks it (the hero 200 with a 160 machine, the cards 516 at y 236 with a 100
--                                      machine) and the page scrolls; (kit-b U9-2) a body under 760 takes TIGHT (the hero
--                                      180, the cards from y 208 to the body's bottom: every button row inside it at
--                                      1280x720); Compact / shrunk second-row buttons are 56 tall
--                                      (>= 44 px at the 0.8 scale)
--                                    (shop-area: the hint on one line from w - 380 (8 px clear of the chips) to w - 10)
--                                    "Phone": one sideways row: the Secret card 200 wide, then the four cards 166 wide at
--                                      x = 208 + i * 174, every card min(266, H - 12) tall (the art shrinks first)
--                                    "Portrait": a vertical list of full-width cards (Secret 200 tall, the machines 250;
--                                      the odds a 2 x 2 grid of egg 30 + % 15; the PityChip's long line while it
--                                      fits, else "Secret in N")
--   ShopEggs.Refresh(page)           the odds rows (rebuilt when PetCatalog.GetRarityOdds changes), the prices, the
--                                    states, the PityChip, the lock texts
--   ShopEggs.Focus(page, rouletteId) -> bool   scrolls that card into view (centred when its row scrolls) and outlines
--                                    it gold for 2.6 s (attribute Focused)
--   ShopEggs.CardState(rouletteId, button) -> "NoOdds" | "Pending" | "Locked" | "Altar" | "Loading" | "Short" | "Ready"
--                                    button = "Spin" (default) | "Spin3" | "SpinGems". In that order: no odds; a request
--                                    pending (EggStage.IsPending: every button); every button while
--                                    PaidRandomItemsRestricted is not false (Locked; token spins too since lobby-shop
--                                    16.12, but only while the Store is on: StoreCatalog.Enabled(), release step 1);
--                                    the Secret card away from the Storm Altar (Altar, shop-area 16.17.3:
--                                    ShopEggs.AtAltar() false); a gem button (SpinGems, every Secret button) before
--                                    GemsSettled (Loading); the balance under the price (Short: the price kept, drawn
--                                    red, the button still taps and EggStage toasts); else Ready
--   ShopEggs.AtAltar() -> bool       (shop-area 16.17.3) the Secret roll can be bought from here: ShopEggs._AtAltar when a
--                                    test set it (true / false); else Config.AtAltar(the character's HumanoidRootPart,
--                                    no slack: the server allows AltarRangeSlack more) whenever there is a root and the
--                                    replicated AltarIslandAt; only without that live reading the Shop opened by the
--                                    altar's prompt counts (SetFromAltar, until Close). Away from it the Secret card greys
--                                    under "Dim" (the navy lip at K.DIM), the "AltarChip" ("Available at the Storm Altar";
--                                    phone / portrait "At the Storm Altar") takes the PityChip's box and a green "Travel"
--                                    (the arrow glyph + "Show the way") takes SPIN's: (Pitch 2 item 13 A; it teleported) a
--                                    tap starts TutorialController.Guide.Start("StormAltar") at most once per K.TRAVEL_GAP
--                                    (no QuickTravel) and closes the Shop (ctx.Close); away from the lobby the guide routes
--                                    home first; greyed only while a match / battle / run holds the player ("Finish the
--                                    match first"). A restricted account keeps the
--                                    Locked card (no chip, no TRAVEL); the page repaints on the Shop's 1 s tick
--   ShopEggs.SetFromAltar(on)        ShopController.Open's FromAltar (the altar prompt), cleared by Close; read by AtAltar()
--                                    only while there is no live reading
--   ShopEggs.HeroPulse(page) -> the UIScale "Pulse" of the hero's Spin (ShopController's shine pulses it, High only)
--   ShopEggs.Fx(page) -> { Pool, Egg }   (Task 26, spec 16.5 "Where the VFX show") the page's HatchFx pool (16 sparks,
--                                    in the hero card) and the Secret hero's big "HeroEgg" (EggArt Full, built Still). On
--                                    PC / Compact the egg stands between the machine and the texts (150 tall at x 198,
--                                    the texts from x 360; shrunk: 124 at x 170, the texts from x 305); a phone or
--                                    portrait card has no room for it (hidden). While the page shows on High graphics the
--                                    egg wears its VFX, the pool keeps its 2 orbiting star sparks and every machine's
--                                    Glass sweeps a slow sheen (its UIGradient "GlassSheen"); hidden (another tab, the
--                                    Shop closed, the egg stage over it), on Low or on a phone everything stops: no
--                                    tween, no Heartbeat. It follows the page's and its ancestors' Visible, the
--                                    ScreenGui's Enabled and the Gfx setting. (egg-3d, spec 16.14) While it shows,
--                                    egg_secret's id is usable here and High: the real Blender egg turns slowly in a
--                                    ViewportFrame "Egg3D" inside HeroEgg (client/UI/Egg3D; the 2D paint hides, its
--                                    sparks and Aura stay); hidden it is destroyed and the 2D egg painted again
--                                    (ShopEggs.Fx(page).Egg3D = the view or nil)
--   ShopEggs.Metrics                 the K table (sizes, texts; MEASURE: a text-width hook for the offline renderer)
-- Buttons: Spin = EggStage.Request(id, "Tokens", 1), Spin3 = (id, "Tokens", 3), SpinGems = (id, "Gems", 1), the Secret
-- card's Spin = ("Secret", "Gems", 1). A spin button holds Word ("Spin" / "x3", or the state: "Locked", "Loading..."),
-- the currency icon (TokenIcon: the Cloud Token glyph; GemPixel: item 9 B's pixel gem) and Price (Theme.Short(n): "3K", "250";
-- Pitch 2 F0, one number style). The machines are frames placed
-- by scale (the pitch's 200 x 230 drawing: base, panel, neck, the glass dome with seven EggArt eggs, the cap).
-- Every PC text >= 18 px, every phone text >= 15 px. Plain Lua 5.1-compatible syntax only; no asset ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local PetCatalog = require(Shared:WaitForChild("PetCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoreCatalog = require(Shared:WaitForChild("StoreCatalog"))

local UI = script.Parent
local NeonKit = require(UI:WaitForChild("NeonKit"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7a) the token coin, the gem, TRAVEL's arrow
local SignKit = require(Shared:WaitForChild("SignKit")) -- (LOOK-ui) the kit's one scroll bar
local CloudUI = require(UI:WaitForChild("CloudUI"))
local EggArt = require(UI:WaitForChild("EggArt"))
local Egg3D = require(UI:WaitForChild("Egg3D"))
local EggStage = require(UI:WaitForChild("EggStage"))
local HatchFx = require(UI:WaitForChild("HatchFx"))
local TweenService = game:GetService("TweenService")
local State = require(UI.Parent:WaitForChild("State"))

local ShopEggs = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local SECRET_DEF = type(Config.Gems) == "table" and Config.Gems.SecretRoulette or nil
local K = {
	SECRET = (type(SECRET_DEF) == "table" and SECRET_DEF.Id) or "Secret",
	MACHINES = { "Cloud", "Storm", "Sky", "Celestial" },
	-- the hero's big egg (Task 26): its height and x by plan, where the texts start, and the page's spark pool
	HERO_EGG = { Ref = { 150, 198, 360 }, Shrunk = { 124, 170, 305 }, Sparks = 16, Spin3D = 16, View3D = 1.15 }, -- (egg-3d: the 3D egg turns once in 16 s in a frame 1.15 egg heights tall)
	-- each machine dome's glass sheen (High, while the page shows): a lighter band sweeping across every ~6 s
	GLASS_SHEEN = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 4.4),
	HERO = rgb(138, 92, 255),
	HERO_MACHINE = rgb(90, 75, 208),
	CHIP = rgb(59, 42, 138),
	RED = rgb(255, 92, 92),
	GOLD = rgb(255, 211, 77),
	LINE = rgb(255, 243, 176),
	NAVY = rgb(11, 16, 48),
	SECRET_TEXT = rgb(180, 150, 255), -- Secret's own colour is near black: the readable violet
	FOCUS_SECONDS = 2.6,
	FOCUS_STROKE = 6,
	TILE = 166, -- the phone row
	STEP = 174,
	TILE_MAX = 266,
	HERO_PHONE = 200,
	FADE = 48,
	TILE_WIDE = 240, -- (fix round B) the widest a phone card grows to fill its viewport with whole cards
	-- (fix6, P2 icons look pol1 #1) the narrowest phone card that draws the sheet's machines at 2 px cells: the card's stage
	-- (w - 102, L.cardSheetPhone) holds the 53-cell drawing and its 2 px rim (106 + 4), the hero's column (w - 90,
	-- L.heroPhone) the vault's 61 cells (122)
	TILE_SHEET = 212,
	-- (fix6) and the widest it grows to fill the row: two 2 px cards on an 800 wide phone left 120 px of bare page
	TILE_WIDE_SHEET = 300,
	MORE_GUTTER = 40, -- (fix round B) the More arrow's column right of the phone row's viewport (its block is 30 wide, 4 in)
	SNAP_DELAY = 0.25, -- (fix round B) s a drag rests before the phone row snaps to a whole card
	SCROLLBAR = SignKit.Sizes.ScrollBar, -- (LOOK-ui) the kit's one bar (was 6, black, round ends)
	FIT_H = 834, -- a PC / Compact body under this shrinks the page (REF's CardsY + Card + BODY_FOOT)
	-- (Pitch 2 F0 review, major 6: the cards' bottom edge ran under the window's frame and the stone's lip, and the hint
	-- touched the card's colour lip) the page keeps the card row BODY_FOOT px over the body's bottom (the frame 6 and the
	-- stone's 8 px lip lie over it, the card's 3 px edge outside it), and a card's hint ends CARD_FOOT px over the card's
	-- bottom (its 5 px colour lip and a gap)
	BODY_FOOT = 18,
	CARD_FOOT = 8,
	-- (same review) a card's wood edge (NeonKit's 3 px SignEdge stroke) and its finish shadow (Theme.Finish.Card) lie
	-- outside its box: the card row (a ScrollingFrame, it clips) and the page give them room, so the cards and the hero
	-- show their edge on every side (it was cut off on the left, top and bottom)
	CARD_EDGE = 3,
	PORTRAIT_CARD = 250,
	PORTRAIT_HERO = 200,
	-- (Pitch 2 item 10 A; P2 icons review r1) with the machines sheet: the portrait cards grow for the 2 px machines
	-- (128 x 136 stages), and a PC card's Spin rows and hint sit LIFT px higher (the hint clears the card's colour lip)
	PORTRAIT_CARD_SHEET = 292,
	PORTRAIT_HERO_SHEET = 254, -- (P2 icons look pol0, minor: 248 left the hint's second row on the button's wood edge)
	HINT_SPARE = 1.02, -- (P2 icons look fin1) H.heroHintRows: the Body face's width over its Enum fallback's, rounded up
	LIFT = 12,
	TEXT = {
		Lock = "Gem roulettes are not available on this account right now.",
		Checking = "Checking your account...",
		LockShort = "Locked on this account",
		CheckingShort = "Checking...",
		Loading = "Loading...",
		LoadingShort = "Loading",
		Locked = "Locked",
		NoOdds = "Odds unavailable",
		Hint = "Gems: same odds",
		-- shop-area (spec 16.17.3): the Secret roll happens at the Storm Altar only (was "Also at the Storm Altar"). Polish:
		-- the hero's hint follows its state: Locked keeps this rule line, Altar says what TRAVEL does, at the altar where
		-- you are (ShopEggs.Refresh)
		HeroHint = "Secret rolls happen at the Storm Altar",
		-- (Pitch 2 item 13_travel_guide A, the owner's pick: no teleport) the button starts a walking guide; it was "Travel
		-- flies you to the Storm Altar"
		HeroHintTravel = "A gold arrow leads you to the Storm Altar",
		HeroHintHere = "You are at the Storm Altar",
		-- away from the lobby the guide routes home first (it greyed out: "Go to the lobby to travel to the Storm Altar")
		HeroHintLobby = "From here: Home first, then the arrow",
		HeroHintLobbyShort = "Home first, then the arrow", -- phone / portrait
		-- a match / battle / dungeon run holds the player: the one state that greys the button
		HeroHintLocked = "Finish the match first",
		AltarLock = "Available at the Storm Altar",
		AltarLockShort = "At the Storm Altar",
		-- (P2 icons look pol0, major: the 360-wide portrait hero's chip, 132 px of room after the padlock, cut the short line
		-- to "At the Storm Al.") the line a chip too narrow for the short one reads: it still names the Storm Altar
		AltarLockTiny = "Storm Altar only",
		Travel = "Show the way", -- (kit-b U9-2: buttons read in sentence case; Pitch 2 item 13 A: was "Travel")
		GemsOnly = "gems only",
	},
	-- shop-area (spec 16.17.3): the Altar state. "Show the way" starts the guide (Pitch 2 item 13 A; it fired
	-- QuickTravel("Altar")) at most once per TRAVEL_GAP; the Dim
	-- (the navy lip at DIM) greys the hero over its art and the page's sparks (HatchFx.Pool's holder, ZIndex 20) and under the
	-- chips, the spin holder and the hint (Z_OVER)
	TRAVEL_GAP = 0.4,
	DIM = 0.35,
	Z_DIM = 21,
	Z_OVER = 22,
	-- the PC plans (REF while the body holds FIT_H, SHRUNK under it)
	REF = { Ref = true, Hero = 240, HeroArt = 190, CardsY = 276, Card = 540, Art = 130, RowsY = 232, RowsH = 152, SpinY = 388, Row2Y = 460 },
	SHRUNK = { Ref = false, Hero = 200, HeroArt = 160, CardsY = 236, Card = 516, Art = 100, RowsY = 198, RowsH = 152, SpinY = 354, Row2Y = 426 },
	-- (kit-b U9-2; the render gate: the x3 / gem row ran under the window's bottom edge at 1280x720) a body under SHRUNK's
	-- CardsY + Card + 8 takes TIGHT, sized from the body (L.plan): the hero 180 with a 150 machine, the cards from y 208
	-- down to the body's bottom (MinCard at least, then the page scrolls), the machine 84, the odds rows share what is left
	-- over the two button rows
	-- (fix6, P2 icons look pol1 #1's class at 960 x 540: MinCard 440 left the sheet's stage 146 tall, the machines at 1 px
	-- cells) MinCard 457: the stage (Card - 282 - LIFT, L.cardSheetPC) keeps the 163 its 2 px cells need under the 0.8 Fit
	TIGHT = { Hero = 180, HeroArt = 150, CardsY = 208, Art = 84, RowsY = 182, HintH = 20, MinCard = 457 },
	-- the machine: the pitch's 200 x 230 drawing; its dome eggs (the pitch's lists) at the pitch's spots pulled 30% toward
	-- the dome's centre (100, 76), so every egg stays inside the round glass (a plain Frame clips square)
	BOX = { 0, 0, 200, 230 },
	DOME = { 36, 12, 128, 128 },
	SPOTS = { { 60, 112 }, { 92, 118 }, { 122, 114 }, { 148, 104 }, { 74, 88 }, { 106, 92 }, { 134, 82 } },
	PULL = 0.7,
	DOME_EGG = 34,
	-- K.MEASURE(text, size, font) -> width replaces TextService:GetTextSize when set (tools/dump_gui.lua's shop scene hands
	-- in the renderer's font metrics: the mock's GetTextSize is a flat 0.5 em per character)
	MEASURE = nil,
	EGGS = {
		Cloud = { "Common", "Uncommon", "Common", "Rare", "Common", "Uncommon", "Common" },
		Storm = { "Rare", "Uncommon", "Rare", "Epic", "Uncommon", "Rare", "Legendary" },
		Sky = { "Epic", "Rare", "Epic", "Legendary", "Rare", "Epic", "Mythic" },
		Celestial = { "Legendary", "Epic", "Legendary", "Mythic", "Epic", "Legendary", "Epic" },
		Secret = { "Mythic", "Mythic", "Secret", "Mythic", "Mythic", "Secret", "Mythic" },
	},
}
ShopEggs.Metrics = K
local WHITE = Color3.new(1, 1, 1)
local MUTED = Theme.Colors.Muted or rgb(176, 184, 206)
-- (kit-b U9-2, finding 15) the Signboard palette: the machine cards are stone blocks (brown ink) with the roulette's own
-- colour on the lip and the name plate; the Secret hero is the navy plank (white / gold ink); a short balance reads in
-- SHORT, a dark red that holds 4.5:1 on stone, the sunk well and the green plank alike
local SIGN = Theme.Sign
local SHORT = rgb(140, 24, 48)
local LEFT, RIGHT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right, Enum.TextXAlignment.Center
local PAGES = setmetatable({}, { __mode = "k" }) -- page -> its widgets
local CUR = setmetatable({}, { __mode = "v" }) -- CUR.Page: the page built last (Focus without a page)
local H = {} -- helpers
local L = {} -- layouts
-- shop-area (spec 16.17.3): From = the Shop was opened by the Storm Altar's prompt (ShopController.Open's FromAltar, cleared
-- on Close); LastTravel = os.clock() of the last "Show the way" tap taken (Pitch 2 item 13 A)
local ALTAR = { From = false, LastTravel = -math.huge }
ShopEggs._AtAltar = nil -- tests: true / false overrides ShopEggs.AtAltar(); nil = the real reading

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function place(inst, x, y, w, h)
	inst.AnchorPoint = Vector2.new(0, 0)
	inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	inst.Size = UDim2.fromOffset(math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
end

local function frame(name, parent, props)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function label(name, parent, text, role, size, props)
	local l = Theme.Label(text or "", role, { Size = size })
	l.Name = name
	l.BackgroundTransparency = 1
	l.TextWrapped = false
	l.TextTruncate = Enum.TextTruncate.AtEnd
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function scroller(name, parent, direction)
	local s = Instance.new("ScrollingFrame")
	s.Name = name
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	SignKit.Scroll(s, K.SCROLLBAR)
	s.ScrollingDirection = direction
	s.CanvasSize = UDim2.new()
	s.Parent = parent
	return s
end

-- (a false attribute stays false: PaidRandomItemsRestricted = false is "allowed")
local function attr(name)
	local player = Players.LocalPlayer
	if not player then
		return nil
	end
	return player:GetAttribute(Config.Attr[name] or name)
end

function H.textW(text, size, font)
	local ok, v = pcall(function()
		if type(K.MEASURE) == "function" then
			return Vector2.new(K.MEASURE(text, size, font), size)
		end
		return Theme.Measure(text, font, size, 10000)
	end)
	if ok and typeof(v) == "Vector2" and v.X > 0 then
		return v.X
	end
	return #tostring(text) * size * 0.55
end

-- (P2 icons look fin1, major: the portrait hero's hint was cut at 390 and 360 wide) the rows the longest line any hero
-- state can show takes, word-wrapped at `size` in a box `width` wide. Measured as the Body face: TextService knows only
-- its Enum fallback (Builder Sans Bold), and Nunito ExtraBold runs about 1.015 x that in render_gui's real font, so
-- K.HINT_SPARE rounds it up to 1.02 (Theme.MeasureSpare's 1.06 would add a row the face never needs)
function H.heroHintRows(width, size, font)
	local function w(s)
		return H.textW(s, size, font) * K.HINT_SPARE
	end
	local most = 1
	for _, text in ipairs({ K.TEXT.HeroHint, K.TEXT.HeroHintLocked, K.TEXT.HeroHintLobbyShort, K.TEXT.HeroHintTravel, K.TEXT.HeroHintHere }) do
		local rows, line = 0, nil
		for word in tostring(text):gmatch("%S+") do
			local try = line and (line .. " " .. word) or word
			if line and w(try) > width then
				rows, line = rows + 1, word
			else
				line = try
			end
		end
		most = math.max(most, rows + (line and 1 or 0))
	end
	return most
end

function H.roulette(id)
	for _, r in ipairs(Config.Roulettes or {}) do
		if r.Id == id then
			return r
		end
	end
	if type(SECRET_DEF) == "table" and SECRET_DEF.Id == id then
		return SECRET_DEF
	end
	return nil
end

-- one spin's price in that currency (Config; the server checks it again)
function H.price(id, currency)
	local r = H.roulette(id)
	if not r then
		return 0
	end
	if currency == "Gems" then
		local prices = type(Config.Gems) == "table" and Config.Gems.RouletteGemPrices or {}
		return math.floor(tonumber(prices[id]) or tonumber(r.GemPrice) or 0)
	end
	return math.floor(tonumber(r.Price) or 0)
end

function H.balance(currency)
	local fn = currency == "Gems" and State.Gems or State.Tokens
	local ok, n = pcall(fn)
	return (ok and type(n) == "number") and n or 0
end

function H.odds(id)
	local ok, list = pcall(PetCatalog.GetRarityOdds, id)
	return (ok and type(list) == "table") and list or {}
end

function H.rarityText(rarity)
	if rarity == "Secret" then
		return K.SECRET_TEXT
	end
	for _, r in ipairs(Config.Rarities or {}) do
		if r.Id == rarity then
			return Theme.Lighten(r.Color, 0.2)
		end
	end
	return WHITE
end

-- "60%": the whole percent, else one decimal
function H.pct(chance)
	local v = (tonumber(chance) or 0) * 100
	if math.abs(v - math.floor(v + 0.5)) < 1e-6 then
		return tostring(math.floor(v + 0.5)) .. "%"
	end
	return string.format("%.1f%%", v)
end

function H.sizeEgg(egg, px)
	px = math.max(8, math.floor(px + 0.5))
	local w = math.floor(((EggArt.Metrics and EggArt.Metrics.WIDTH) or 0.8) * px + 0.5)
	egg.Size = UDim2.fromOffset(w, px)
	local outline = egg:FindFirstChild("Outline")
	if outline then
		outline.Thickness = math.max(2, math.floor(px / 20 + 0.5))
	end
	egg:SetAttribute("Size", px)
	return w
end

-- (P2 icons review r1, major 1: under the 3 px pixel machines the odds chips drew this module's smooth vector EggArt) an
-- odds chip's hand-pixelled egg, "PixelEgg" (the mock-up's, 10_optA): cut from the machines sheet's egg row
-- (Config.MachineSheet.Eggs) while that sheet has an id, else the same drawing as the 9 x 9 PixelIcon glyph
-- "egg_<rarity>" in Frames. Drawn again only when px changes; nil for a rarity with neither (the vector egg stays)
local function eggSheet(rarity)
	local ms = Config.MachineSheet
	local id = type(ms) == "table" and tonumber(ms.Id) or 0
	local cell = type(ms) == "table" and type(ms.Eggs) == "table" and ms.Eggs[rarity] or nil
	return (id and id > 0 and cell) and id or nil, cell
end

-- whether a chip of rarity row.Rarity has a pixel egg to draw (its sheet cell or its glyph)
function H.canPixelEgg(row)
	return eggSheet(row.Rarity) ~= nil or PixelIcon.Art["egg_" .. string.lower(tostring(row.Rarity))] ~= nil
end

function H.pixelEgg(row, px)
	local old = row.PixelEgg
	if old and old.Parent and old:GetAttribute("Px") == px then
		return old
	end
	if old then
		old:Destroy()
	end
	local name = "egg_" .. string.lower(tostring(row.Rarity))
	local id, cell = eggSheet(row.Rarity)
	local icon = (id and PixelIcon.FromSheet(row.Root, name, px, id, cell)) or PixelIcon.New(row.Root, name, px, PixelIcon.Own)
	if icon then
		icon.Name = "PixelEgg"
		icon:SetAttribute("Px", px)
		local z = row.Pct.ZIndex
		icon.ZIndex = z
		for _, d in ipairs(icon:GetChildren()) do
			if d:IsA("GuiObject") then
				d.ZIndex = z
			end
		end
	end
	row.PixelEgg = icon
	return icon
end

function H.call(P, name, ...)
	local fn = P.Ctx[name]
	if type(fn) == "function" then
		pcall(fn, ...)
	end
end

----------------------------------------------------------------------
-- the machine (frames placed by scale in the pitch's 200 x 230 box)
----------------------------------------------------------------------
-- (kit-b U9-2) a square wood edge (mitred) on a kit B tag
function H.edge(obj, px)
	local s = Util.Create("UIStroke", {
		Name = "SignEdge", Color = SIGN.Wood, Thickness = px or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter, Parent = obj,
	})
	-- (Pitch 2 F0, finish pass A) the light on the wood edge and the tag's lit top band (no shadow on a tag in a card)
	SignKit.FinishBlock(obj, { Out = px or 3, Shadow = false })
	return s
end

function H.part(m, parent, box, name
, x, y, w, h, color, radius, strokeW, props)
	local f = frame(name, parent, {
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Position = UDim2.fromScale((x - box[1]) / box[3], (y - box[2]) / box[4]),
		Size = UDim2.fromScale(w / box[3], h / box[4]),
	})
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	if radius then
		Util.Create("UICorner", { CornerRadius = UDim.new(radius, 0), Parent = f })
	end
	if strokeW then
		local s = Util.Create("UIStroke", { Color = K.NAVY, Thickness = strokeW, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
		m.Strokes[#m.Strokes + 1] = { Stroke = s, W = strokeW }
	end
	return f
end

-- (Pitch 2 item 10 A) the uploaded machines sheet: its image id and roulette `id`'s cell { x, y, w, h }, or nil while
-- Config.MachineSheet.Id is 0 (nothing uploaded: today's drawn machine)
function H.machineSheet(id)
	local ms = Config.MachineSheet
	local sheetId = type(ms) == "table" and tonumber(ms.Id) or 0
	local cell = type(ms) == "table" and type(ms.Cells) == "table" and ms.Cells[id] or nil
	if not (sheetId and sheetId > 0 and sheetId == math.floor(sheetId) and type(cell) == "table") then
		return nil
	end
	return sheetId, cell
end

-- (Pitch 2 item 10 A "Workshop machines") roulette `id`'s own pixel machine, cut from the sheet (one ImageLabel "Art",
-- ResampleMode Pixelated), standing on its "Stage": a Well sunk into the card in a pale wash of the roulette's colour with
-- a PetWell floor, its line and a stepped pixel ground shadow. (P2 icons review r1, major 3: the vault sat in a visible dark
-- box, dimmed, next to the big egg) the hero's vault has no box: it stands on the card's own navy, on a NavyLip slab with
-- its NavyTop line (the mock-up's), no ground shadow. Today's drawn machine stays under it in "Drawn" for a box too small
-- for one screen px a cell (H.layoutSheetMachine shows one or the other: never a blurry shrink, never art over the card's
-- rows)
function H.addSheet(m, color, secret, sheetId, cell)
	m.Sheet, m.Cell, m.Secret = true, cell, secret
	local root = m.Root
	root:SetAttribute("Sheet", true)
	local face = secret and SIGN.Navy or color:Lerp(SIGN.Tile, 0.74)
	m.Stage = frame("Stage", root, { BackgroundTransparency = secret and 1 or 0, BackgroundColor3 = secret and SIGN.NavyLip or SIGN.WellEdge, Size = UDim2.fromScale(1, 1) })
	m.Face = frame("Face", m.Stage, { BackgroundTransparency = secret and 1 or 0, BackgroundColor3 = face })
	m.Lid = frame("Lid", m.Face, { BackgroundTransparency = 0, BackgroundColor3 = face:Lerp(SIGN.WellEdge, 0.45), Visible = not secret })
	m.Floor = frame("Floor", m.Face, { BackgroundTransparency = 0, BackgroundColor3 = secret and SIGN.NavyLip or SIGN.PetWell })
	m.FloorLine = frame("FloorLine", m.Floor, { BackgroundTransparency = 0, BackgroundColor3 = secret and SIGN.NavyTop or SIGN.WellEdge })
	local shade = SIGN.PetWell:Lerp(SIGN.WellEdge, 0.55)
	m.Shadow = {}
	for i = 1, 3 do
		m.Shadow[i] = frame("Shadow" .. i, m.Face, { BackgroundTransparency = 0, BackgroundColor3 = shade, Visible = not secret })
	end
	m.Art = Util.Create("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = Config.Art.Image(sheetId) or "", -- (P2 icons look fin1) the URL from Config.Art
		ImageRectOffset = Vector2.new(cell[1], cell[2]),
		ImageRectSize = Vector2.new(cell[3], cell[4]),
		ResampleMode = Enum.ResamplerMode.Pixelated,
		ScaleType = Enum.ScaleType.Stretch,
		Parent = root,
	})
end

-- the page's sheet machines (m.Group, ShopEggs.Build) show only when every one of them fits its box (m.Fits): a page never
-- mixes the new machines with today's. (P2 icons review r1, major 1) every layout's boxes are sized for whole px cells
-- (L.*Sheet below), so the phones show them too. The hero's Dim (away from the altar) veils today's drawn machine only:
-- the vault stays bright (the mock-up's; the altar chip's padlock says why)
function H.showSheets(m)
	local all = m.Fits == true
	for _, o in ipairs(m.Group or {}) do
		all = all and o.Fits == true
	end
	for _, o in ipairs(m.Group or { m }) do
		o.Drawn.Visible = not all
		o.Stage.Visible = all
		o.Art.Visible = all
		o.Root:SetAttribute("SheetShown", all)
		if o.HeroCard then
			o.HeroCard.Dim.Visible = o.HeroCard.Away == true and not all
		end
	end
end

-- whether the page shows the sheet machines (the hero's look follows it: no big egg, no Dim)
function H.sheetShown(t)
	return t.Machine.Sheet == true and t.Machine.Root:GetAttribute("SheetShown") == true
end

-- the sheet machine in its box at rest scale s: the largest whole number of screen px a cell that fits, centred (m.AlignX),
-- on whole screen px. A card's machine stands 4 cells into an 8-cell floor where the stage is tall enough (the drawing and
-- 1 cell of floor under its drop shadow must fit, inside the well's 2 px rim: P2 icons look pol0, the 640 x 360 phone's
-- 129 px stage holds the 2 px cells so; it asked for 2 cells); the hero's vault stands on the box's foot over its 3-cell
-- slab (no rim: the drawing must fit). A box too small for 1 px a cell can't: then the page shows today's drawn machines
-- (H.showSheets)
function H.layoutSheetMachine(m, s)
	s = (s and s > 0) and s or 1
	local W, Hh = m.Root.Size.X.Offset, m.Root.Size.Y.Offset
	local cw, ch = m.Cell[3], m.Cell[4]
	local edge = m.Secret and 0 or PixelIcon.Px(2, s)
	local px = math.floor(math.min((W - 2 * edge) * s / cw, (Hh - 2 * edge) * s / (ch + (m.Secret and 0 or 1))))
	m.Fits = px >= 1
	H.showSheets(m)
	if not m.Fits then
		m.Root:SetAttribute("CellPx", nil)
		return
	end
	local dc = px / s
	local aw, ah = cw * dc, ch * dc
	local ax = edge + math.floor((W - 2 * edge - aw) * (m.AlignX or 0.5) * s) / s
	m.Face.Position = UDim2.fromOffset(edge, edge)
	m.Face.Size = UDim2.fromOffset(W - 2 * edge, Hh - 2 * edge)
	if m.Secret then
		-- the vault's foot on the box's foot; the slab 3 cells tall under its last cells, 2 cells in from its sides
		local ay = math.floor((Hh - ah) * s) / s
		m.Art.Position = UDim2.fromOffset(ax, ay)
		m.Art.Size = UDim2.fromOffset(aw, ah)
		local slab = 3 * dc
		m.Floor.Position = UDim2.fromOffset(ax + 2 * dc, Hh - slab)
		m.Floor.Size = UDim2.fromOffset(math.max(0, aw - 4 * dc), slab)
		m.FloorLine.Size = UDim2.fromOffset(math.max(0, aw - 4 * dc), PixelIcon.Px(2, s))
		m.Root:SetAttribute("CellPx", px)
		return
	end
	local floorH = math.min(Hh - 2 * edge, 8 * dc)
	local feet = Hh - edge - math.max(3 * dc, floorH - 4 * dc) -- the feet 4 cells into an 8-cell floor
	local ay = math.max(edge, math.floor((feet - ah) * s) / s)
	m.Art.Position = UDim2.fromOffset(ax, ay)
	m.Art.Size = UDim2.fromOffset(aw, ah)
	m.Lid.Size = UDim2.fromOffset(W - 2 * edge, PixelIcon.Px(3, s))
	m.Floor.Position = UDim2.fromOffset(0, Hh - 2 * edge - floorH)
	m.Floor.Size = UDim2.fromOffset(W - 2 * edge, floorH)
	m.FloorLine.Size = UDim2.fromOffset(W - 2 * edge, edge)
	-- the ground shadow: three stepped rows a cell tall under the feet, the middle one widest (no blur), centred under the
	-- drawing (the rows sit in the Face, `edge` in from the root). The feet as drawn: a stage shorter than the 8-cell floor
	-- wants (the phones) holds the drawing from its top, lower than `feet`, and the rows hid behind it
	local mid = math.floor((ay + ah - edge) * s) / s - dc
	local rx = math.floor(aw * 0.42 / dc) * dc
	for i, row in ipairs({ { -1, 0.6 }, { 0, 1 }, { 1, 0.6 } }) do
		local w = math.floor(2 * rx * row[2] / dc) * dc
		local f = m.Shadow[i]
		f.Position = UDim2.fromOffset(math.floor((ax - edge + (aw - w) / 2) * s) / s, mid + row[1] * dc)
		f.Size = UDim2.fromOffset(w, dc)
	end
	m.Root:SetAttribute("CellPx", px)
end

function H.machine(parent, id, color, secret)
	local m = { Strokes = {} }
	local root = frame("Machine", parent)
	root:SetAttribute("Art", "Machine") -- (kit-b U9-2) an illustration: its round glass and sheen are the drawing, not a panel
	m.Root = root
	-- (Pitch 2 item 10 A) with the machines sheet uploaded, today's drawing goes into "Drawn" (the whole box: its parts are
	-- placed by scale, so they draw the same) under the sheet's art (H.addSheet below)
	local sheetId, cell = H.machineSheet(id)
	if sheetId then
		m.Drawn = frame("Drawn", root, { Size = UDim2.fromScale(1, 1) })
		root = m.Drawn
	end
	local B, D = K.BOX, K.DOME
	H.part(m, root, B, "Base", 26, 146, 148, 76, Theme.Darken(color, 0.32), 0.18, 5)
	H.part(m, root, B, "BaseShine", 36, 152, 128, 16, Theme.Lighten(color, 0.2), 0.5, nil, { BackgroundTransparency = 0.55 })
	H.part(m, root, B, "Panel", 64, 176, 72, 34, Theme.Darken(color, 0.55), 0.25, 4)
	H.part(m, root, B, "Slot", 80, 186, 40, 16, K.NAVY, 0.25)
	H.part(m, root, B, "Knob", 143, 181, 22, 22, WHITE, 0.5, 4)
	H.part(m, root, B, "Neck", 54, 130, 92, 22, Theme.Lighten(color, 0.08), 0.3, 5)
	local dome = H.part(m, root, B, "Dome", D[1], D[2], D[3], D[4], secret and rgb(29, 26, 52) or rgb(233, 246, 255), 0.5, nil, { ClipsDescendants = true })
	local eggs = K.EGGS[id] or K.EGGS.Cloud
	local eh = K.DOME_EGG
	local ew = eh * ((EggArt.Metrics and EggArt.Metrics.WIDTH) or 0.8)
	for i, spot in ipairs(K.SPOTS) do
		local cx = 100 + K.PULL * (spot[1] - 100)
		local cy = 76 + K.PULL * (spot[2] - 76)
		local egg = EggArt.New(dome, eggs[i] or "Common", eh, { Name = "DomeEgg" .. i })
		egg.Position = UDim2.fromScale((cx - ew / 2 - D[1]) / D[3], (cy - eh / 2 - D[2]) / D[4])
		egg.Size = UDim2.fromScale(ew / D[3], eh / D[4])
	end
	local glass = H.part(m, root, B, "Glass", D[1], D[2], D[3], D[4], secret and K.HERO or rgb(191, 230, 255), 0.5, 5, { BackgroundTransparency = 0 })
	-- (Task 26) the glass's see-through 0.84 lives in its gradient, with a lighter band parked off the glass (Offset -1):
	-- the page sweeps it across while it shows on High
	m.Sheen = Util.Create("UIGradient", {
		Name = "GlassSheen",
		Rotation = 30,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.84),
			NumberSequenceKeypoint.new(0.4, 0.84),
			NumberSequenceKeypoint.new(0.5, 0.5),
			NumberSequenceKeypoint.new(0.6, 0.84),
			NumberSequenceKeypoint.new(1, 0.84),
		}),
		Parent = glass,
	})
	H.part(m, root, B, "Shine", 54, 28, 44, 9, WHITE, 0.5, nil, { BackgroundTransparency = 0.25, Rotation = -32 })
	H.part(m, root, B, "Cap", 82, 2, 36, 18, Theme.Lighten(color, 0.2), 0.35, 4)
	if sheetId then
		H.addSheet(m, color, secret, sheetId, cell)
	end
	return m
end

-- the machine `px` wide (its strokes follow the size; a sheet machine is laid out on whole screen px, again whenever the
-- window's rest scale changes)
function H.sizeMachine(m, px)
	if m.Sheet then
		-- today's drawing under the sheet keeps its own 200 x 230 shape at `px` wide, at the foot of the (wider, taller)
		-- stage, centred: never stretched to the stage (P2 icons review r1: the stages follow the mock-up's card)
		m.Drawn.AnchorPoint = Vector2.new(0.5, 1)
		m.Drawn.Position = UDim2.fromScale(0.5, 1)
		m.Drawn.Size = UDim2.fromOffset(px, math.floor(px * 1.15 + 0.5))
		PixelIcon.Whole(m.Art, function(s)
			H.layoutSheetMachine(m, s)
		end)
	end
	if m.Px == px then
		return
	end
	m.Px = px
	for _, s in ipairs(m.Strokes) do
		s.Stroke.Thickness = math.max(1, math.floor(s.W * px / 200 + 0.5))
	end
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
-- a spin button: a CloudUI.Button with no text of its own holding Word, the currency icon and Price in one row
function H.spinButton(P, parent, name, style, word, currency, id, spins)
	-- (kit-b U9-2) a kit B plank: green for the hero's SPIN (the page's one main action), stone for the machines' spins
	local p = { Currency = currency, BaseWord = word or "", Ink = style == "Green" and SIGN.OnGrass or SIGN.Text }
	p.Button = CloudUI.Button({
		Name = name,
		Text = "",
		Style = style,
		Skin = "Sign",
		Size = UDim2.fromOffset(200, 60),
		TextSize = 22,
		Callback = function()
			H.tap(P, id, currency, spins)
		end,
		Parent = parent,
	})
	p.Word = label("Word", p.Button, p.BaseWord, "Button", 22, { TextTruncate = Enum.TextTruncate.None, TextColor3 = p.Ink })
	if currency == "Tokens" then
		local cur = Theme.Currency.Tokens
		p.Icon = label("TokenIcon", p.Button, "", "Display", 22, { TextColor3 = SIGN.GoldLip, TextTruncate = Enum.TextTruncate.None })
		PixelIcon.Host(p.Icon, cur.Icon) -- (kit-b U7a) the Cloud Token coin, sized with the label (the deep gold reads on stone)
	else
		-- (P2 icons look fin0, major 2: the cut GemIcon, a smooth square turned 45 degrees, sat beside the pixel coins) item
		-- 9 B's pixel gem in its own colours, sized with the label as the coin (10_optA's gem planks)
		p.Icon = label("GemPixel", p.Button, "", "Display", 22, { TextColor3 = SIGN.Text, TextTruncate = Enum.TextTruncate.None })
		PixelIcon.Host(p.Icon, "gem")
	end
	p.Price = label("Price", p.Button, "", "Button", 22, { TextTruncate = Enum.TextTruncate.None, TextColor3 = p.Ink })
	return p
end

-- the row inside a spin button (w x h, text `size`, icon `iconPx`; nil = the last layout's numbers)
function H.arrange(p, w, h, size, iconPx)
	if w then
		p.W, p.H, p.Size, p.IconPx = w, h, size, iconPx
	end
	if not p.W then
		return
	end
	w, h, size, iconPx = p.W, p.H, p.Size, p.IconPx
	p.Icon.TextSize = iconPx
	p.Word.TextSize = size
	p.Price.TextSize = size
	if p.PriceFull then
		p.Price.Text = p.PriceFull
	end
	local stateOnly = p.StateText ~= nil
	p.Word.Visible = p.Word.Text ~= ""
	p.Icon.Visible = not stateOnly
	p.Price.Visible = not stateOnly
	local items = {}
	local priceItem = nil
	if p.Word.Visible then
		items[#items + 1] = { p.Word, H.textW(p.Word.Text, size, Theme.FontOf(p.Word)), true }
	end
	if not stateOnly then
		items[#items + 1] = { p.Icon, iconPx, false }
		priceItem = { p.Price, H.textW(p.Price.Text, size, Theme.FontOf(p.Price)), true }
		items[#items + 1] = priceItem
	end
	local function rowW(gap)
		local total = 0
		for _, it in ipairs(items) do
			total = total + it[2]
		end
		return total + gap * (#items - 1)
	end
	-- (review round 3) a row wider than its button even at the 2 px gap takes the short price from 1,000 up ("3K"): Roblox draws
	-- GothamBlack as the wide Montserrat Black, and the row would run past the button onto its neighbour (the size never steps
	-- under the 15 px phone floor)
	if priceItem and p.PriceShort and p.Price.Text ~= p.PriceShort and rowW(2) > w - 4 then
		p.Price.Text = p.PriceShort
		priceItem[2] = H.textW(p.PriceShort, size, Theme.FontOf(p.Price))
	end
	local gap = math.max(3, math.floor(size * 0.3))
	if rowW(gap) > w - 8 then
		gap = 2
	end
	local total = rowW(gap)
	local x = math.max(2, (w - total) / 2)
	for _, it in ipairs(items) do
		if it[3] then
			place(it[1], x, 0, it[2] + 2, h)
		else
			place(it[1], x, (h - iconPx) / 2, iconPx, iconPx)
		end
		x = x + it[2] + gap
	end
end

-- (kit-b U9-2) a card is a kit B block (NeonKit.Card Skin "Sign"): `face` (stone, or the hero's navy plank), the wood
-- edge (`edge`: the hero's is the gold lip), the roulette's own colour on its lip
function H.card(P, parent, id, color, face, size, edge)
	local c = NeonKit.Card({ Name = "ShopCard_" .. id, Skin = "Sign", BodyOverLip = true, Face = face, Lip = color, Edge = edge, Size = size, Parent = parent })
	local t = { Id = id, Root = c.Root, Card = c, Color = color, Edge = c.Stroke.Color, Thick = c.Stroke.Thickness, Rows = {} }
	local r = H.roulette(id)
	t.Name = (r and r.DisplayName) or (id .. " Roulette")
	return t, c.Body
end

function H.buildHero(P, parent)
	local t, b = H.card(P, parent, K.SECRET, K.HERO, SIGN.Navy, UDim2.fromOffset(1240, 240), SIGN.GoldLip)
	t.Hero = true
	t.Root:SetAttribute("Hero", true)
	t.Machine = H.machine(b, K.SECRET, K.HERO_MACHINE, true)
	t.Machine.HeroCard = t -- (P2 icons review r1) H.showSheets keeps the Dim off the vault
	t.Title = Theme.StyleTitle(label("Title", b, t.Name, "Title", 46, { TextXAlignment = LEFT, TextColor3 = SIGN.Gold }), "Section") -- a card's heading: the Shop's header title wears the ribbon
	t.Odds = frame("OddsLine", b)
	t.GemsOnly = label("GemsOnly", t.Odds, K.TEXT.GemsOnly, "Body", 24, { TextXAlignment = LEFT, TextColor3 = MUTED })
	t.NoOdds = label("NoOdds", b, K.TEXT.NoOdds, "Body", 22, { Visible = false, TextColor3 = MUTED, TextXAlignment = LEFT })
	-- (kit-b U9-2) the pity promise: a gold tag in its wood edge (brown ink)
	t.Pity = label("PityChip", b, "", "Heading", 22, { BackgroundTransparency = 0, BackgroundColor3 = SIGN.Gold, TextColor3 = SIGN.Text })
	H.edge(t.Pity)
	t.Lock = label("Lock", b, "", "Body", 20, {
		Visible = false, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextColor3 = K.LINE, TextXAlignment = LEFT,
	})
	t.Holder = frame("SpinHolder", b, { ZIndex = K.Z_OVER })
	t.Pulse = Util.Create("UIScale", { Name = "Pulse", Scale = 1, Parent = t.Holder })
	t.Spin = H.spinButton(P, t.Holder, "Spin", "Green", "Spin", "Gems", K.SECRET, 1) -- (kit-b U9-2) the page's one green plank
	t.Hint = label("Hint", b, K.TEXT.HeroHint, "Body", 18, { TextColor3 = K.LINE, ZIndex = K.Z_OVER })
	-- (Task 26) the big Secret egg in front of the machine's right side, still until the page shows (ShopEggs.Fx)
	t.Egg = EggArt.New(b, "Secret", K.HERO_EGG.Ref[1], { Name = "HeroEgg", Form = "Full", Still = true, ZIndex = 3 })
	-- shop-area (spec 16.17.3): away from the Storm Altar the card greys under Dim (over the art, the egg and its sparks),
	-- AltarChip takes the PityChip's box and TRAVEL takes SPIN's in the same holder (over the Dim with the hint)
	-- (LOOK-ui, kitb-look1: the veil over the whole card greyed the title and the odds below the contrast rule) the Dim
	-- veils the art column only (the layouts place it); the texts stay whole and the chip's padlock says why
	-- (Pitch 2 fix round B r1, look review minor: at 844x390 the veil read as "a visible darker navy rectangle, an unblended
	-- picture box") the veil is the card's own navy face (H.card above): the art fades into the card, no box edge shows
	t.Dim = frame("Dim", b, { BackgroundTransparency = K.DIM, BackgroundColor3 = SIGN.Navy, Size = UDim2.fromScale(1, 1), ZIndex = K.Z_DIM, Visible = false })
	-- (kit-b U9-2) the altar note: a stone tag in its wood edge (brown ink)
	t.AltarChip = label("AltarChip", b, K.TEXT.AltarLock, "Heading", 22, {
		BackgroundTransparency = 0, BackgroundColor3 = SIGN.Tile, TextColor3 = SIGN.Text, ZIndex = K.Z_OVER, Visible = false,
	})
	H.edge(t.AltarChip)
	PixelIcon.Lead(t.AltarChip, "lock", { Px = 18, Gap = 8 }) -- (LOOK-ui, kitb-look1) the padlock before "Available at the Storm Altar"
	t.Travel = H.travelButton(P, t.Holder)
	return t
end

-- the hero's TRAVEL: a CloudUI.Button holding the compass glyph ("Icon") and "TRAVEL" ("Word"); no price: the trip is
-- free. (kit-b U9-2) the green plank: away from the altar it is the page's one main action, in SPIN's place
function H.travelButton(P, parent)
	local tr = {}
	tr.Button = CloudUI.Button({
		Name = "Travel",
		Text = "",
		Style = "Green",
		Skin = "Sign",
		Size = UDim2.fromOffset(290, 100),
		TextSize = 22,
		Callback = function()
			H.travel(P)
		end,
		Parent = parent,
	})
	CloudUI.SetStyle(tr.Button, "Green")
	tr.Button.Visible = false
	tr.Icon = label("Icon", tr.Button, "", "Display", 44, { TextTruncate = Enum.TextTruncate.None, TextColor3 = SIGN.OnGrass })
	PixelIcon.Host(tr.Icon, NeonKit.IconName("Travel")) -- (kit-b U7a) the arrow, sized with the label
	tr.Word = label("Word", tr.Button, K.TEXT.Travel, "Button", 34, { TextTruncate = Enum.TextTruncate.None, TextXAlignment = LEFT, TextColor3 = SIGN.OnGrass })
	return tr
end

-- TRAVEL's row (w x h, text `size`, glyph `iconPx`), centred by the measured width; the word's box runs to the button's
-- edge, so a face wider than the measure never clips it
function H.arrangeTravel(tr, w, h, size, iconPx)
	place(tr.Button, 0, 0, w, h)
	tr.Icon.TextSize = iconPx
	tr.Word.TextSize = size
	local gap = math.max(3, math.floor(size * 0.3))
	local ww = H.textW(tr.Word.Text, size, Theme.FontOf(tr.Word)) + 2
	local x = math.max(4, math.floor((w - (iconPx + gap + ww)) / 2))
	place(tr.Icon, x, (h - iconPx) / 2, iconPx, iconPx)
	local wx = x + iconPx + gap
	place(tr.Word, wx, 0, math.max(0, w - 4 - wx), h)
end

-- (Pitch 2 item 13 A) a match, a battle, a dungeon run or the Ring holds the player: the guide cannot start
function H.tripLocked()
	return attr("InMatch") == true or attr("InBattle") ~= nil
end

-- the travel guide (TutorialController.Guide), looked up when first needed (the Shop loads before the controllers)
function H.guide()
	local ok, guide = pcall(function()
		local folder = UI.Parent:FindFirstChild("Controllers")
		local mod = folder and folder:FindFirstChild("TutorialController")
		local TC = mod and require(mod)
		return type(TC) == "table" and TC.Guide or nil
	end)
	return ok and type(guide) == "table" and type(guide.Start) == "function" and guide or nil
end

-- a "Show the way" tap (Pitch 2 item 13 A: it sent QuickTravel("Altar"), a teleport): only while the page shows and no
-- match / run holds the player, at most once per K.TRAVEL_GAP; the walking guide starts (routing home first when away
-- from the lobby), then the Shop closes. No remote: nothing moves the player.
function H.travel(P)
	if not H.shown(P.Page) or H.tripLocked() or os.clock() - ALTAR.LastTravel < K.TRAVEL_GAP then
		return
	end
	local guide = H.guide()
	if not guide then
		return
	end
	ALTAR.LastTravel = os.clock()
	H.call(P, "Tap")
	local ok, started = pcall(guide.Start, "StormAltar")
	if ok and started == true then
		H.call(P, "Close")
	end
end

function H.buildCard(P, parent, id)
	local r = H.roulette(id)
	local color = (r and typeof(r.Color) == "Color3") and r.Color or rgb(120, 190, 235)
	local t, b = H.card(P, parent, id, color, SIGN.Tile, UDim2.fromOffset(298, 550))
	-- (kit-b U9-2) the name plate: a block in the roulette's own colour in its wood edge, the face nudged until its ink
	-- reads 4.5:1 (Theme.ReadableFace; the phone's plate text is 17 px)
	local plateFace, plateInk = Theme.ReadableFace(color, 4.5)
	t.Plate = label("NamePlate", b, t.Name, "Heading", 24, { BackgroundTransparency = 0, BackgroundColor3 = plateFace, TextColor3 = plateInk })
	H.edge(t.Plate)
	t.Machine = H.machine(b, id, color, false)
	t.Odds = frame("Odds", b)
	t.NoOdds = label("NoOdds", b, K.TEXT.NoOdds, "Body", 20, { Visible = false, TextColor3 = SIGN.TextMuted, TextWrapped = true, TextTruncate = Enum.TextTruncate.None })
	-- (kit-b U9-2) one colour by role: the machines' spins are stone planks (the green plank is the hero's)
	t.Spin = H.spinButton(P, b, "Spin", "Blue", "Spin", "Tokens", id, 1)
	t.Spin3 = H.spinButton(P, b, "Spin3", "Blue", "x3", "Tokens", id, 3)
	t.SpinGems = H.spinButton(P, b, "SpinGems", "Blue", nil, "Gems", id, 1)
	t.Hint = label("Hint", b, K.TEXT.Hint, "Body", 18, { TextColor3 = SIGN.TextMuted })
	return t
end

-- (re)builds a card's Odds_<Rarity> rows when GetRarityOdds(id) changed -> true when rebuilt
function H.syncRows(t)
	local odds = H.odds(t.Id)
	local parts = {}
	for i, e in ipairs(odds) do
		parts[i] = tostring(e.Rarity) .. "=" .. tostring(e.Chance)
	end
	local sig = table.concat(parts, ",")
	if sig == t.Sig then
		return false
	end
	t.Sig = sig
	for _, row in ipairs(t.Rows) do
		row.Root:Destroy()
	end
	t.Rows = {}
	for i, e in ipairs(odds) do
		local row = { Rarity = e.Rarity }
		row.Root = frame("Odds_" .. tostring(e.Rarity), t.Odds, { LayoutOrder = i })
		row.Egg = EggArt.New(row.Root, e.Rarity, 28, { Name = "Egg" })
		-- (kit-b U9-2) on the navy hero the rarity's own light colour; on a stone card brown (the egg names the rarity)
		row.Word = label("Word", row.Root, tostring(e.Rarity), "Heading", 20, { TextColor3 = t.Hero and H.rarityText(e.Rarity) or SIGN.Text, TextXAlignment = LEFT })
		row.Pct = label("Pct", row.Root, H.pct(e.Chance), "Heading", 22, { TextXAlignment = RIGHT, TextColor3 = t.Hero and WHITE or SIGN.Text })
		if t.Machine.Sheet and not t.Hero then
			-- (Pitch 2 item 10 A: "the odds become egg chips"; P2 icons review r1, major 2) with the sheet machines each odds
			-- row is a chip: a stone block in its wood edge with a StoneLip foot, the egg and its percent (no rarity word:
			-- the egg's colour names it, as on the phone). The layouts place the egg and the percent
			row.Root.BackgroundTransparency = 0
			row.Root.BackgroundColor3 = SIGN.Tile
			H.edge(row.Root, 2)
			frame("Lip", row.Root, {
				BackgroundTransparency = 0, BackgroundColor3 = SIGN.StoneLip or SIGN.WellEdge, AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3),
			})
			row.Chip = true
		end
		t.Rows[i] = row
	end
	t.HasOdds = #odds > 0
	return true
end

function H.all(P)
	local out = { P.Hero }
	for _, t in ipairs(P.Cards) do
		out[#out + 1] = t
	end
	return out
end

function H.tap(P, id, currency, spins)
	-- (shop-area 16.17.3) the Secret SPIN sends nothing away from the Storm Altar (it is hidden there; the server refuses too)
	if id == K.SECRET and not ShopEggs.AtAltar() then
		ShopEggs.Refresh(P.Page)
		return
	end
	H.call(P, "Tap")
	EggStage.Request(id, currency, spins)
	ShopEggs.Refresh(P.Page)
end

function ShopEggs.Build(page, ctx)
	local P = { Page = page, Ctx = type(ctx) == "table" and ctx or {}, Cards = {}, Mode = "PC", Box = { W = 1240, H = 834 } }
	PAGES[page] = P
	CUR.Page = page
	P.Scroll = scroller("Scroll", page, Enum.ScrollingDirection.Y)
	P.Scroll.Size = UDim2.fromScale(1, 1)
	-- (kit-b U9-2) the row's right edge while more is that way; (LOOK-ui, kitb-look1: no gradient in a pixel screen) a stone
	-- block with the pixel arrow there, not the stone fading in
	P.Fade = frame("Fade", page, { BackgroundTransparency = 1, Visible = false, ZIndex = 6 })
	CloudUI.MoreMark(P.Fade, 6)
	P.Hero = H.buildHero(P, P.Scroll)
	P.Row = scroller("Cards", P.Scroll, Enum.ScrollingDirection.X)
	for i, id in ipairs(K.MACHINES) do
		P.Cards[i] = H.buildCard(P, P.Row, id)
	end
	-- (Pitch 2 item 10 A) the page's sheet machines show together or not at all (H.showSheets)
	local group = {}
	for _, t in ipairs(H.all(P)) do
		if t.Machine.Sheet then
			group[#group + 1] = t.Machine
			t.Machine.Group = group
		end
	end
	P.Scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		ShopEggs._SyncFade(page)
		H.queueSnap(P)
	end)
	-- (Task 26) the page-owned spark pool in the hero card: the big egg's orbiting star sparks, stopped while hidden
	P.Pool = HatchFx.Pool(P.Hero.Card.Body, K.HERO_EGG.Sparks)
	P.Pool:SetRunning(false)
	P.Pool:Ambient(P.Hero.Egg, "Secret")
	P.FxConns = {}
	H.wireFx(P)
	page.AncestryChanged:Connect(function()
		H.wireFx(P)
		H.syncFx(P)
	end)
	local settings = UI.Parent:FindFirstChild("ClientSettings")
	local okCS, CS = false, nil
	if settings and settings:IsA("ModuleScript") then
		okCS, CS = pcall(require, settings)
	end
	if okCS and type(CS) == "table" and CS.Changed then
		CS.Changed:Connect(function(key)
			if key == "Gfx" then
				task.defer(H.syncFx, P) -- (after GraphicsQuality has applied the new setting)
			end
		end)
	end
	-- (egg-3d) the hero's real egg appears once egg_secret has loaded on this device, also with the page already open
	P.MeshConn = Egg3D.Watch(function(key)
		if key == Egg3D.KEYS.Secret.Whole then
			task.defer(H.syncFx, P)
		end
	end)
	ShopEggs.Refresh(page)
	H.syncFx(P)
	return P
end

----------------------------------------------------------------------
-- the page's VFX (Task 26)
----------------------------------------------------------------------
-- the graphics setting (client/GraphicsQuality's Effective(), asked on every call); High when the module is not there
function H.high()
	if H.GQ == nil then
		H.GQ = false
		local module = UI.Parent:FindFirstChild("GraphicsQuality")
		if module and module:IsA("ModuleScript") then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				H.GQ = mod
			end
		end
	end
	if not H.GQ then
		return true
	end
	local ok, mode = pcall(H.GQ.Effective)
	return not ok or mode ~= "Low"
end

-- the page shows: it and every GuiObject above it Visible, its ScreenGui Enabled, in a PlayerGui
function H.shown(page)
	local cur = page
	while cur do
		if cur:IsA("GuiObject") then
			if not cur.Visible then
				return false
			end
		elseif cur:IsA("LayerCollector") then
			if not cur.Enabled then
				return false
			end
		elseif cur:IsA("PlayerGui") then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- (re)connects the Visible / Enabled listeners on the page and its ancestors
function H.wireFx(P)
	for _, c in ipairs(P.FxConns) do
		c:Disconnect()
	end
	P.FxConns = {}
	local cur = P.Page
	while cur and cur ~= game do
		local prop = (cur:IsA("GuiObject") and "Visible") or (cur:IsA("LayerCollector") and "Enabled") or nil
		if prop then
			P.FxConns[#P.FxConns + 1] = cur:GetPropertyChangedSignal(prop):Connect(function()
				H.syncFx(P)
			end)
		end
		cur = cur.Parent
	end
end

function H.syncFx(P)
	local egg = P.Hero.Egg
	local on = H.shown(P.Page) and egg.Visible and H.high()
	EggArt.SetVfx(egg, on)
	H.sync3d(P, on)
	P.Pool:SetRunning(on)
	for _, t in ipairs(H.all(P)) do
		local sheen = t.Machine.Sheen
		if on and not t.GlassTween then
			sheen.Offset = Vector2.new(-1, 0)
			t.GlassTween = TweenService:Create(sheen, K.GLASS_SHEEN, { Offset = Vector2.new(1, 0) })
			t.GlassTween:Play()
		elseif not on and t.GlassTween then
			t.GlassTween:Cancel()
			t.GlassTween = nil
			sheen.Offset = Vector2.new(-1, 0)
		end
	end
end

-- (egg-3d) the hero's real egg: made while the page shows (Egg3D decides: the id, High, the phone limit), destroyed when
-- it hides, so nothing turns behind a closed Shop or the egg stage
function H.sync3d(P, on)
	local egg = P.Hero.Egg
	if P.Egg3 and P.Egg3.Dead then
		P.Egg3 = nil
		EggArt.SetPaintShown(egg, true)
	end
	if on and not P.Egg3 then
		local view = Egg3D.New(egg, "Secret", { Phone = P.Mode ~= "PC", ZIndex = egg.ZIndex + 2, Spin = K.HERO_EGG.Spin3D, Turn = -20, View = K.HERO_EGG.View3D })
		if view then
			P.Egg3 = view
			EggArt.SetPaintShown(egg, false)
		end
	elseif not on and P.Egg3 then
		P.Egg3:Destroy()
		P.Egg3 = nil
		EggArt.SetPaintShown(egg, true)
	end
end

function ShopEggs.Fx(page)
	local P = PAGES[page or CUR.Page]
	return P and { Pool = P.Pool, Egg = P.Hero.Egg, Egg3D = (P.Egg3 and not P.Egg3.Dead) and P.Egg3 or nil } or nil
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
-- the hero's odds line on PC: each row Egg 40 + the rarity + the percent (24 px), then "gems only"
function L.heroOddsPC(t, w)
	-- (Task 26: the big egg moved the texts right) the gap between the rows narrows from 24 to 12 before "gems only"
	-- is left out for want of room. (kit-b P2 fix6, icons look pol1 #2: at 1024 x 768 "Secret 40%" ran under the button)
	-- then the words step down from 24 px to 22 and 20 before the rows run past their column
	local widths, total, size = {}, 0, 24
	for _, sz in ipairs({ 24, 22, 20 }) do
		widths, total, size = {}, 0, sz
		for i, row in ipairs(t.Rows) do
			local ww = H.textW(row.Word.Text, sz, Theme.FontOf(row.Word)) + 2
			local pw = H.textW(row.Pct.Text, sz, Theme.FontOf(row.Pct)) + 2
			widths[i] = { ww, pw }
			total = total + math.floor(EggArt.Metrics.WIDTH * 40 + 0.5) + 8 + ww + 8 + pw
		end
		if total + 12 * (#t.Rows - 1) <= w then
			break
		end
	end
	t.GemsOnly.TextSize = size
	local gw = H.textW(t.GemsOnly.Text, size, Theme.FontOf(t.GemsOnly)) + 2
	local gap = (total + 24 * #t.Rows + gw <= w) and 24 or 12
	local x = 0
	for i, row in ipairs(t.Rows) do
		local ew = H.sizeEgg(row.Egg, 40)
		place(row.Egg, 0, 0, ew, 40)
		row.Word.Visible = true
		row.Word.TextSize = size
		row.Pct.TextSize = size
		local ww, pw = widths[i][1], widths[i][2]
		place(row.Word, ew + 8, 0, ww, 40)
		place(row.Pct, ew + 8 + ww + 8, 0, pw, 40)
		row.Pct.TextXAlignment = LEFT
		local rw = ew + 8 + ww + 8 + pw
		place(row.Root, x, 0, rw, 40)
		x = x + rw + gap
	end
	t.GemsOnly.Visible = gw <= w - x
	place(t.GemsOnly, x, 0, math.max(0, w - x), 40)
end

function L.heroPC(t, w, M)
	local ref = M.Ref
	local art = M.HeroArt
	local artH = math.floor(art * 1.15)
	local ep = ref and K.HERO_EGG.Ref or K.HERO_EGG.Shrunk
	local vaultH = M.Hero - (M.Ref and 16 or 6)
	-- (kit-b P2 fix6, icons look pol1 #2: a tablet's card, 864 wide at 1024 x 768, left the texts w - 305 - 340 = 219 px:
	-- "SECRET...", the odds under the button, "Available at the...", its padlock outside the chip) the texts start at
	-- ep[3] while the title has its 46 px there; a narrower card's art column gives up the room it holds empty: down to
	-- the vault's own width (its cells come from the column's height, so a column cw / ch of that height draws the same
	-- cells) or to the drawn machine's box (the big egg goes)
	-- (the title reads in capitals: its role's; "Secret Roulette" measured 8 % short)
	local caps = Theme.Caps(t.Name)
	local want = H.textW(caps, 46, Theme.FontOf(t.Title)) + 2
	local x = ep[3]
	if w - x - 340 < want then
		local c = t.Machine.Sheet and t.Machine.Cell
		local least = c and (12 + math.ceil(vaultH * c[3] / c[4])) or (26 + art + 12)
		x = math.min(x, math.max(least, math.floor(w - 340 - want)))
	end
	local roomy = x >= ep[3]
	-- (Pitch 2 item 10 A) the sheet's vault stands on its own stage left of the big egg (Task 26), not under it; today's
	-- drawn machine keeps its whole box (the egg overlaps its edge, as before)
	if t.Machine.Sheet then
		-- (P2 icons review r1, major 3) the vault alone, as tall as the card allows (3 px cells at 1920), centred in the art
		-- column left of the texts: the big egg goes (two hero objects fought there)
		-- (its foot 14 px over the card's foot on REF, clear of the colour lip; 4 px on the shorter plans, so 1280 keeps 2 px)
		L.heroSheetArt(t, 4, 2, x - 12, vaultH)
	else
		place(t.Machine.Root, 26, ref and 10 or 8, art, artH)
		t.Machine.AlignX = 0
		H.sizeMachine(t.Machine, art)
		-- (Task 26) the big egg between the machine and the texts, centred in the card's height
		local ew = math.floor(EggArt.Metrics.WIDTH * ep[1] + 0.5)
		EggArt.Resize(t.Egg, ep[1])
		place(t.Egg, ep[2], (M.Hero - ep[1]) / 2, ew, ep[1])
		t.Egg.Visible = roomy
	end
	local tw = w - x - 340
	t.Title.Text = t.Name
	-- (fix6) the title steps down from 46 px while it is wider than its column (36 at 1024 x 768)
	local ts = 46
	while ts > 28 and H.textW(caps, ts, Theme.FontOf(t.Title)) + 2 > tw do
		ts = ts - 1
	end
	t.Title.TextSize = ts
	place(t.Title, x, ref and 22 or 12, tw, 56)
	local oy = ref and 84 or 76
	place(t.Odds, x, oy, tw, 40)
	L.heroOddsPC(t, tw)
	place(t.NoOdds, x, oy, tw, 40)
	t.NoOdds.TextSize = 22
	local cy = ref and 132 or 124
	-- (fix6) on a narrow card the chips end 8 px short of the hint's line (w - 380: its longest line, 358 px, whole) and
	-- take the line that fits them (ShopEggs.Refresh: "At the Storm Altar", "Secret in N")
	local chipMax = roomy and tw or math.max(0, math.min(tw, w - 388 - x))
	place(t.Pity, x, cy, math.min(400, chipMax), 48)
	t.Pity.TextSize = 22
	-- (shop-area) the altar chip in the pity chip's place, as wide as its long line needs (400 at least)
	t.AltarChip.TextSize = 22
	local chipW = math.min(chipMax, math.max(400, H.textW(K.TEXT.AltarLock, 22, Theme.FontOf(t.AltarChip)) + 32 + 26)) -- (+ the padlock and its gap)
	place(t.AltarChip, x, cy, chipW, 48)
	t.Dim.Position = UDim2.fromOffset(0, 0)
	t.Dim.Size = UDim2.new(0, x - 8, 1, 0) -- the machine and the big egg; the texts from x stay clear
	place(t.Lock, x, cy, tw, 48)
	t.Lock.TextSize = 20
	-- (Pitch 2 look review r0, crop 06: on the tight 180 px hero the line sat 4 px over the card's foot) the hint's box ends
	-- CARD_FOOT over the card's bottom: 22 px tall under the button on a tight hero. (P2 icons look pol0, minor: there, at
	-- 1280, the line's text met the button's 5 px wood edge and its descenders the purple lip) on a hero too short for the
	-- 28 px box the button rises so a 24 px box fits 2 px under its wood edge
	local holderY = ref and 66 or 46
	local hy, hh = ref and 172 or 152, 28
	if hy + hh > M.Hero - K.CARD_FOOT then
		hh = 24
		hy = M.Hero - K.CARD_FOOT - hh
		holderY = math.min(holderY, hy - 2 - 5 - 100)
	end
	place(t.Holder, w - 320, holderY, 290, 100)
	place(t.Spin.Button, 0, 0, 290, 100)
	H.arrange(t.Spin, 290, 100, 34, 44)
	-- (P2 icons look fin0, minor) the signpost 27 px, 3 px cells (the screen's glyph cell, the mock-up's): 44 drew it 36
	-- px, the sheet's art at 2 px cells (4 px as the glyph)
	-- (Pitch 2 item 13 A) "Show the way" is twice "Travel"'s length: 30 px keeps it inside the 290 px plank in FredokaOne
	-- (kit-b merge, icons 9 B x world 13 A) both kept: the world lane's 30 px word, the icons lane's 30 px signpost box
	H.arrangeTravel(t.Travel, 290, 100, 30, 30)
	t.Hint.Visible = true
	t.Hint.TextSize = 18
	t.Hint.TextWrapped = false -- (the phone card wraps its line; a turn back to the PC plan takes the one line again)
	-- (shop-area) the long hints, "Secret rolls happen at the Storm Altar" and (Pitch 2 item 13 A) "A gold arrow leads you
	-- to the Storm Altar", run ~322-350 px at 18 ("You are at the Storm Altar" is shorter; the shop tests measure them in
	-- the real face): one line from
	-- w - 380 to 10 px short of the card's edge, starting 8 px clear of the chips when they reach that far
	local hintL = math.max(w - 380, x + chipW + 8)
	place(t.Hint, hintL, hy, w - 10 - hintL, hh)
end

function L.cardPC(t, w, M, tall)
	if t.Machine.Sheet then
		return L.cardSheetPC(t, w, M, tall)
	end
	local row2H = tall and 56 or 48
	t.Plate.Text = t.Name
	t.Plate.TextSize = 24
	place(t.Plate, 12, 12, w - 24, 54)
	local artH = math.floor(M.Art * 1.15 + 0.5)
	place(t.Machine.Root, (w - M.Art) / 2, 76, M.Art, artH)
	H.sizeMachine(t.Machine, M.Art)
	local rowsH = M.RowsH or 160
	place(t.Odds, 16, M.RowsY, w - 32, rowsH)
	local n = #t.Rows
	local rh = n > 4 and math.floor(rowsH / n) or math.min(40, math.floor(rowsH / math.max(1, n)))
	local iw = w - 32
	for i, row in ipairs(t.Rows) do
		place(row.Root, 0, (i - 1) * rh, iw, rh)
		local px = math.min(28, rh - 8)
		local ew = H.sizeEgg(row.Egg, px)
		place(row.Egg, 4, (rh - px) / 2, ew, px)
		row.Word.Visible = true
		row.Word.TextSize = 20
		place(row.Word, 36, 0, iw - 36 - 72, rh)
		row.Pct.TextSize = 22
		row.Pct.TextXAlignment = RIGHT
		place(row.Pct, iw - 72, 0, 72, rh)
	end
	t.NoOdds.TextSize = 20
	place(t.NoOdds, 16, M.RowsY, w - 32, rowsH)
	local spinH = M.Tight and 56 or 64 -- (P2 icons look pol0, minor: L.plan's TIGHT)
	place(t.Spin.Button, 14, M.SpinY, w - 28, spinH)
	H.arrange(t.Spin, w - 28, spinH, 23, 26)
	local half = math.floor((w - 38) / 2)
	place(t.Spin3.Button, 14, M.Row2Y, half, row2H)
	H.arrange(t.Spin3, half, row2H, 18, 20)
	place(t.SpinGems.Button, w - 14 - half, M.Row2Y, half, row2H)
	H.arrange(t.SpinGems, half, row2H, 18, 22)
	t.Hint.Visible = true
	t.Hint.TextSize = 18
	if M.Tight then
		-- the line's own height, 2 px under the planks' 5 px edge and 5 px shadow (L.plan)
		place(t.Hint, 8, M.Row2Y + row2H + 12, w - 16, 18)
	else
		local hy = M.Row2Y + row2H + 2
		place(t.Hint, 8, hy, w - 16, math.max(16, M.Card - K.CARD_FOOT - hy))
	end
end

-- the PC / Compact plan for a body Hh tall: REF, SHRUNK, or TIGHT worked out from Hh (the two button rows 64 + 56 and
-- the hint at the card's foot, the odds rows above them)
function L.plan(Hh)
	if Hh >= K.FIT_H then
		return K.REF
	end
	local S = K.SHRUNK
	if Hh >= S.CardsY + S.Card + K.BODY_FOOT then
		return S
	end
	local T = K.TIGHT
	local card = math.max(T.MinCard, Hh - T.CardsY - K.BODY_FOOT)
	-- (P2 icons look pol0, minor: today's machines at 1280, the shipping look: "Gems: same odds" started 2 px under the
	-- x3 / gem planks' box, under their 5 px wood edge and 5 px shadow, its tops cut) the line (18 tall) ends 2 px over the
	-- card's 5 px colour lip and starts 2 px under the planks' shadow; the Spin plank gives the 8 px back (56: 44.8 screen
	-- px under the 0.8 Fit, still a touch target; L.cardPC), so the odds rows keep their room
	local row2Y = card - 5 - 2 - 18 - 12 - 56
	local spinY = row2Y - 8 - 56
	return {
		Ref = false, Tight = true, Hero = T.Hero, HeroArt = T.HeroArt, CardsY = T.CardsY, Card = card, Art = T.Art, RowsY = T.RowsY,
		RowsH = math.max(96, spinY - 6 - T.RowsY), SpinY = spinY, Row2Y = row2Y,
	}
end

function L.pc(P, W, Hh)
	local M = L.plan(Hh)

	local tall = P.Mode == "Compact" or not M.Ref
	local s = P.Scroll
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	-- the card row: (w - 48) / 4 each; under 250 it scrolls sideways (with room for its bar)
	local E, D = K.CARD_EDGE, (Theme.Finish and Theme.Finish.Card) or 5
	local function plan(cw)
		local cardW = math.floor((cw - 48 - 2 * E - D) / 4)
		local sideways = cardW < 250
		if sideways then
			cardW = 250
		end
		local bar = sideways and (K.SCROLLBAR + 4) or 0
		return cardW, sideways, M.Card + 2 * E + D + bar, M.CardsY + M.Card + bar + K.BODY_FOOT
	end
	local cw = W
	local cardW, sideways, rowH, contentH = plan(cw)
	if contentH > Hh + 0.5 then
		-- the page scrolls: the content stops short of its bar
		cw = W - K.SCROLLBAR - 2
		cardW, sideways, rowH, contentH = plan(cw)
	end
	s.CanvasSize = UDim2.fromOffset(0, contentH)
	P.Hero.Title.TextXAlignment = LEFT
	place(P.Hero.Root, E, 16, cw - 2 * E - D, M.Hero)
	L.heroPC(P.Hero, cw - 2 * E - D, M)
	place(P.Row, 0, M.CardsY - E, cw, rowH)
	P.Row.ScrollingDirection = Enum.ScrollingDirection.X
	local rowW = #P.Cards * (cardW + 16) - 16 + 2 * E + D
	P.Row.CanvasSize = UDim2.fromOffset(sideways and rowW or cw, 0)
	for i, t in ipairs(P.Cards) do
		place(t.Root, E + (i - 1) * (cardW + 16), E, cardW, M.Card)
		L.cardPC(t, cardW, M, tall)
	end
	P.CanvasW = 0
end

-- the phone's padding over a card's bottom rows (6 at 238 tall, 22 at 266)
local function phonePad(th)
	return math.max(6, 6 + math.floor((th - 238) * 16 / 28))
end

-- a phone odds row: one column per rarity, the egg 30 over its percent (15 px)
function L.phoneOdds(t, x, y, w)
	place(t.Odds, x, y, w, 50)
	local n = math.max(1, #t.Rows)
	local cw = w / n
	for i, row in ipairs(t.Rows) do
		place(row.Root, (i - 1) * cw, 0, cw, 50)
		local ew = H.sizeEgg(row.Egg, 30)
		place(row.Egg, (cw - ew) / 2, 0, ew, 30)
		row.Word.Visible = false
		row.Pct.TextSize = 15
		row.Pct.TextXAlignment = CENTER
		place(row.Pct, 0, 32, cw, 18)
	end
	t.NoOdds.TextSize = 15
	place(t.NoOdds, x, y, w, 50)
end

----------------------------------------------------------------------
-- (Pitch 2 item 10 A "Workshop machines": the mock-ups 10_optA.png / 10_optA_phone.png; P2 icons review r1, majors 1 - 3)
-- the layouts once the machines sheet has an id (t.Machine.Sheet). Each box is sized so its machine draws whole px cells:
-- 3 at 1920, 2 at 1280 (the window's 0.8) and on a phone. Without an id every layout above stays today's
----------------------------------------------------------------------
-- (P2 icons review r1, major 1 + the 1280 minor: the vector egg sat 1.6 px from the wood, "60%" 0.4 px from it) a chip's
-- pixel egg and its percent, laid out again whenever the rest scale above changes: the egg at eggPx (a multiple of 9: 3
-- screen px cells at 1920, 2 under the 1280 window's 0.8 and on a phone) over the percent when the face holds both, else
-- beside it; where neither fits, one cell size down (18 px). What is fitted is the egg as drawn: its 9 cells on whole
-- screen px and its 1-cell drop shadow (PixelIcon.BoxPx), the percent's text 2 px or more clear of the chip's sides
function L.chipEgg(row, cw, face, eggPx, size)
	PixelIcon.Whole(row.Root, function(s)
		local tw = H.textW(row.Pct.Text, size, Theme.FontOf(row.Pct)) + 2
		local px = math.max(9, 9 * math.floor(eggPx / 9))
		-- (P2 icons look fin0, major 1) the egg a screen px under the chip's top, the percent's box its text's height: the
		-- 1280 chip holds the 18 px percent (14.4 screen px, the readability floor) over its egg again
		local lid = 1 / s
		local side, drawn, over
		while true do
			side = PixelIcon.BoxPx(px, 0, s) -- the 9 cells, whole screen px, in design px
			drawn = side * 10 / 9 -- + the drop shadow's cell
			over = face >= lid + drawn + 1 + size and cw >= math.max(drawn, tw) + 4
			if over or (face >= drawn and cw >= drawn + 4 + tw + 4) or px <= 18 then
				break
			end
			px = math.max(18, px - 9)
		end
		local icon = H.pixelEgg(row, px)
		if not icon then
			return
		end
		-- New / FromSheet centre the cells in the px box (pad, on a whole screen px): undo it so the cells start at ex, ey
		local sc = side * s / 9
		local pad = math.floor((px * s - 9 * sc) / 2) / s
		local function at(ex, ey)
			icon.Position = UDim2.fromOffset(math.floor(ex * s) / s - pad, math.floor(ey * s) / s - pad)
		end
		if over then
			-- the room left split over and under, in whole screen px (a floor in design px left the 1280 egg on the wood)
			local top = math.max(lid, math.floor((face - (drawn + 1 + size)) * s / 2 + 0.5) / s)
			at((cw - side) / 2, top)
			row.Pct.TextXAlignment = CENTER
			place(row.Pct, 0, top + drawn + 1, cw, size)
		else
			local x0 = math.max(2, math.floor((cw - (drawn + 4 + tw)) / 2))
			at(x0, math.max(0, (face - drawn) / 2))
			row.Pct.TextXAlignment = LEFT
			place(row.Pct, x0 + drawn + 4, 0, math.max(0, cw - x0 - drawn - 4), face)
		end
	end)
end

-- the odds rows as egg chips (H.syncRows gave them their stone block) in a grid of `cols` columns in x, y, w x h: the egg
-- over its percent when the chip is tall enough, else beside it
function L.chips(t, x, y, w, h, cols, eggPx, size, gap)
	place(t.Odds, x, y, w, h)
	t.NoOdds.TextSize = size
	place(t.NoOdds, x, y, w, h)
	local n = math.max(1, #t.Rows)
	cols = math.max(1, math.min(cols, n))
	local rows = math.ceil(n / cols)
	local cw = math.floor((w - gap * (cols - 1)) / cols)
	local chH = math.floor((h - gap * (rows - 1)) / rows)
	local face = chH - 3 -- over the chip's 3 px lip
	for i, row in ipairs(t.Rows) do
		local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
		place(row.Root, col * (cw + gap), line * (chH + gap), cw, chH)
		row.Word.Visible = false
		row.Pct.TextSize = size
		if row.Chip and H.canPixelEgg(row) then
			-- (P2 icons review r1, major 1) a card's chip: the hand-pixelled egg, not the vector one
			row.Egg.Visible = false
			L.chipEgg(row, cw, face, eggPx, size)
		elseif face >= eggPx + size + 8 then
			local ew = H.sizeEgg(row.Egg, eggPx)
			local top = math.floor((face - eggPx - size - 2) / 2)
			place(row.Egg, math.floor((cw - ew) / 2), top, ew, eggPx)
			row.Pct.TextXAlignment = CENTER
			place(row.Pct, 0, top + eggPx + 1, cw, size + 2)
		else
			local px = math.min(eggPx, face - 4)
			local ew = H.sizeEgg(row.Egg, px)
			local tw = H.textW(row.Pct.Text, size, Theme.FontOf(row.Pct)) + 2
			local x0 = math.max(2, math.floor((cw - (ew + 4 + tw)) / 2))
			place(row.Egg, x0, math.floor((face - px) / 2), ew, px)
			row.Pct.TextXAlignment = LEFT
			place(row.Pct, x0 + ew + 4, 0, math.max(0, cw - x0 - ew - 4), face)
		end
	end
end

-- a PC card: the name plate, the machine on a stage as wide as the plate, one row of egg chips, Spin, x3 + gems, and the
-- hint; the Spin rows and the hint K.LIFT px higher than before (the line clears the card's colour lip). TIGHT (1280 x 720)
-- takes a shorter plate and chips so the stage still holds 2 screen px cells
function L.cardSheetPC(t, w, M, tall)
	local tight = M.Tight == true
	local row2H = tall and 56 or 48
	local plateH = tight and 44 or 54
	t.Plate.Text = t.Name
	t.Plate.TextSize = 24
	place(t.Plate, 12, 12, w - 24, plateH)
	local hintY = M.Card - K.CARD_FOOT - K.LIFT - 20
	-- the hint clear of the x3 / gem planks' 5 px drop shadow (TIGHT: 6, so its 2 px stage keeps its height)
	local row2Y = hintY - (tight and 6 or 8) - row2H
	-- (P2 icons review r1, major 1 + the 1280 minor) TIGHT: the pixel egg (2 screen px cells: 22.5 design px under the
	-- 0.8 Fit, + its drop shadow) over an 18 px percent (14.4 screen px: P2 icons look fin0, major 1), a screen px under
	-- the chip's top, fits a 49 px chip; the 10 px come off the Spin plank (56: 44.8 screen px, still a 44 px touch target)
	local spinH = tight and 56 or 64
	local spinY = row2Y - 8 - spinH
	local chipH = tight and 49 or (M.Ref and 60 or 56)
	-- (P2 icons look fin0, minor: the chips sat fused to the Spin plank) the chips' wood edge 6 px over the plank's at
	-- 1920 (the mock-up's gap: 13 less the two edges, 2 + 5), 3.2 screen px at 1280 (11 under the 0.8 Fit); TIGHT takes
	-- the 5 px from the chip (50 -> 49) and the stage's two gaps (8 -> 6): the stage keeps its 163 (2 px cells need 162.5)
	local chipsY = spinY - (tight and 11 or 13) - chipH
	local stageY = 12 + plateH + (tight and 6 or 8)
	place(t.Machine.Root, 12, stageY, w - 24, math.max(40, chipsY - (tight and 6 or 8) - stageY))
	t.Machine.AlignX = 0.5
	H.sizeMachine(t.Machine, M.Art)
	-- (P2 icons look pol0, minor: the chips 6 apart left 2 px of cream between their 2 px edges at 1920, ~1.6 at 1280; the
	-- 10_optA mock-up has 6) 10 apart: 6 px of cream at 1920, 4.8 at 1280 (chips 60 / 54 wide still hold "60%" over the egg)
	L.chips(t, 12, chipsY, w - 24, chipH, #t.Rows, tight and 18 or 27, 18, 10)
	place(t.Spin.Button, 14, spinY, w - 28, spinH)
	H.arrange(t.Spin, w - 28, spinH, 23, 26)
	local half = math.floor((w - 38) / 2)
	place(t.Spin3.Button, 14, row2Y, half, row2H)
	H.arrange(t.Spin3, half, row2H, 18, 20)
	place(t.SpinGems.Button, w - 14 - half, row2Y, half, row2H)
	H.arrange(t.SpinGems, half, row2H, 18, 22)
	t.Hint.Visible = true
	t.Hint.TextSize = 18
	place(t.Hint, 8, hintY, w - 16, 20)
end

-- the hero's vault alone in the art column left of the texts (x0 .. textX - 8), as tall as the card allows; no big egg
function L.heroSheetArt(t, x0, y0, w, h)
	place(t.Machine.Root, x0, y0, w, h)
	t.Machine.AlignX = 0.5
	H.sizeMachine(t.Machine, K.REF.HeroArt)
	t.Egg.Visible = false
end

-- a landscape phone card: the machine's stage on the left (2 px cells from a 212 px tile), the plate and a column of egg
-- chips right of it, Spin and x3 + gems full width under them (as today)
function L.cardSheetPhone(t, w, th)
	local pad = phonePad(th)
	local row2Y = th - pad - 44
	local spinY = row2Y - 50
	-- (P2 icons look fin1, minor) the chip column 84 wide (was 80) for the chips' 8 px gap below: the stage gives up 4 px
	-- (112 still holds a 53-cell drawing at 2 px cells)
	local sw = math.max(60, math.min(112, w - 6 - 6 - 6 - 84))
	local rx = 6 + sw + 6
	local rw = w - rx - 6
	-- (P2 icons look fin0, minor: the chips' edge lay 1 px under the Spin plank's) the stage and the chips end 12 px over
	-- the plank: the chips' wood edge 5 px clear of its edge. (P2 icons look pol0, majors: at 640 x 360 / 667 x 375 the
	-- stage, 120 / 127 tall, was too short for the 2 px drawing (it fell to 1 px, a small machine in an empty stage), and
	-- the chips, 37 tall at 640, put each percent beside its egg, cut to "...") the upper band runs from 2 px under the
	-- card's top (under its 2 px finish shine: the plate's wood edge's top) to 3 px of cream over the plank's 5 px wood
	-- edge: the stage 2 .. spinY - 8 (its rim is inside its box), the plate 26 tall, the chips 3 px of cream under its
	-- edge down to the same line (their 2 px edges outside the box): 640's chips 40 tall hold the 15 px percent over its
	-- egg; its stage (128) holds the 2 px cells over one cell of floor (H.layoutSheetMachine)
	place(t.Machine.Root, 6, 2, sw, spinY - 10)
	t.Machine.AlignX = 0.5
	H.sizeMachine(t.Machine, 45)
	t.Plate.Text = t.Id
	t.Plate.TextSize = rw < 90 and 15 or 17
	place(t.Plate, rx, 5, rw, 26)
	-- (P2 icons review r1, major 1) two columns of tall chips, the pixel egg (2 px cells) over its percent as on PC: in one
	-- column the chips were 20 px faces, the egg and its drop shadow flush on the wood. (P2 icons look fin1, minor: the
	-- chips' 2 px wood edges met in a 4 px gap, fused into one line, and the plate's edge touched the grid) 8 px apart:
	-- 4 px of cream between the edges (chips 38 wide: the real "60%", ~30 px, stays over its egg)
	L.chips(t, rx, 39, rw, spinY - 10 - 39, 2, 20, 15, 8)
	place(t.Spin.Button, 6, spinY, w - 12, 44)
	H.arrange(t.Spin, w - 12, 44, 16, 18)
	local half = math.floor((w - 18) / 2)
	place(t.Spin3.Button, 6, row2Y, half, 44)
	H.arrange(t.Spin3, half, 44, 15, 15)
	place(t.SpinGems.Button, w - 6 - half, row2Y, half, 44)
	H.arrange(t.SpinGems, half, 44, 15, 16)
	t.Hint.Visible = false
end

-- a portrait card (the phone mock-up): the plate, the stage on the left (2 px cells), a 2 x 2 grid of egg chips and the
-- hint right of it, Spin and x3 + gems full width under them
function L.cardSheetPortrait(t, w, h)
	t.Plate.Text = t.Name
	t.Plate.TextSize = 20
	place(t.Plate, 8, 8, w - 16, 34)
	place(t.Machine.Root, 8, 48, 128, h - 104 - 8 - 48)
	t.Machine.AlignX = 0.5
	H.sizeMachine(t.Machine, 64)
	local rx = 144
	local rw = w - rx - 8
	-- (P2 icons look pol0, minor: 2 px of cream between the chips' edges, the phone mock-up has about 7) 10 apart: 6 px
	L.chips(t, rx, 52, rw, 82, 2, 22, 15, 10)
	t.Hint.Visible = true
	t.Hint.TextSize = 15
	place(t.Hint, rx, 140, rw, 20)
	place(t.Spin.Button, 8, h - 104, w - 16, 46)
	H.arrange(t.Spin, w - 16, 46, 18, 20)
	local half = math.floor((w - 24) / 2)
	place(t.Spin3.Button, 8, h - 52, half, 44)
	H.arrange(t.Spin3, half, 44, 15, 16)
	place(t.SpinGems.Button, w - 8 - half, h - 52, half, 44)
	H.arrange(t.SpinGems, half, 44, 15, 16)
end

function L.heroPhone(t, w, th)
	local pad = phonePad(th)
	-- (P2 icons look pol0, major: at 640 x 360 / 667 x 375 the vault's column, 126 / 133 tall, was short of the 2 px
	-- drawing's 138, so it drew at 1 px a cell, half size) where the card is that short, the altar / pity / lock chip (a
	-- label, not a touch target) gives up to 12 px (44 -> 32: its 15 px line still fits) so the vault keeps 2 px cells
	local chipH = 44
	if t.Machine.Sheet and t.Machine.Cell then
		local short = 2 * t.Machine.Cell[4] - (th - pad - 94 - 12)
		if short > 0 then
			chipH = math.max(32, 44 - short)
		end
	end
	local chipY = th - pad - 50 - chipH
	t.Title.Text = "Secret"
	t.Title.TextSize = 17
	t.Title.TextXAlignment = CENTER
	t.GemsOnly.Visible = false
	if t.Machine.Sheet then
		-- (P2 icons review r1, major 1) the vault at 2 px cells on the left over the chip, the title and the odds right of it
		local vw = math.max(64, math.min(122, w - 6 - 6 - 6 - 72))
		local rx = 6 + vw + 6
		local rw = w - rx - 6
		L.heroSheetArt(t, 6, 6, vw, chipY - 12)
		place(t.Dim, 0, 0, rx - 3, chipY - 3)
		t.Title.TextSize = rw < 80 and 15 or 17
		place(t.Title, rx, 6, rw, 30)
		-- the two odds one over the other (the egg beside its percent), as on the portrait phone
		L.chips(t, rx, 40, rw, 72, 1, 26, 15, 4)
	else
		place(t.Title, 6, 6, w - 12, 30)
		place(t.Machine.Root, 8, 40, 64, 74)
		H.sizeMachine(t.Machine, 64)
		place(t.Dim, 0, 36, 76, 82) -- the machine only
		t.Egg.Visible = false -- (Task 26: no room on the phone card)
		L.phoneOdds(t, 80, 40, w - 88)
	end
	place(t.Pity, 6, chipY, w - 12, chipH)
	t.Pity.TextSize = 15
	place(t.AltarChip, 6, chipY, w - 12, chipH)
	t.AltarChip.TextSize = 15
	place(t.Lock, 6, chipY, w - 12, chipH)
	t.Lock.TextSize = 15
	place(t.Holder, 6, th - pad - 44, w - 12, 44)
	place(t.Spin.Button, 0, 0, w - 12, 44)
	H.arrange(t.Spin, w - 12, 44, 16, 18)
	H.arrangeTravel(t.Travel, w - 12, 44, 16, 18)
	-- (Pitch 2 look review r0, minor 5: a landscape phone away from the lobby had no "Home first" line before the tap) the
	-- short away / match line in the band between the machine and the altar chip, wrapped; only while that band holds
	-- one 15 px row (H.paint shows it away from the lobby or held by a match, never in the plain lobby state)
	t.Hint.TextSize = 15
	t.Hint.TextWrapped = true
	-- (kit-b wave-2 merge, icons item 10 A x world item 13 A) with the vault drawn (P2 icons r1) the left column down to the
	-- chip is the vault's, so the line takes the odds column beside it (under the odds' 112 px foot); today's drawn
	-- machine ends at 114, so there the line keeps the full width. It shows only where its wrapped rows fit (H.paint)
	local hx, hw = 6, w - 12
	if t.Machine.Sheet then
		hx = 6 + math.max(64, math.min(122, w - 6 - 6 - 6 - 72)) + 6
		hw = w - hx - 6
	end
	local hh = chipY - 2 - 116
	place(t.Hint, hx, 116, hw, hh)
	local rows = 1
	for _, s in ipairs({ K.TEXT.HeroHintLobbyShort, K.TEXT.HeroHintLocked }) do
		rows = math.max(rows, math.ceil((H.textW(s, 15, Theme.FontOf(t.Hint)) + 2) / math.max(1, hw)))
	end
	t.PhoneHintRoom = hh >= rows * 15 + 2
	t.Hint.Visible = false
end

function L.cardPhone(t, w, th)
	if t.Machine.Sheet then
		return L.cardSheetPhone(t, w, th)
	end
	local pad = phonePad(th)
	t.Plate.Text = t.Id
	t.Plate.TextSize = 17
	place(t.Plate, 6, 6, w - 12, 30)
	local row2Y = th - pad - 44
	local spinY = row2Y - 50
	local oddsY = spinY - 54
	local artH = math.max(24, oddsY - 4 - 40)
	local artW = math.floor(artH * 200 / 230 + 0.5)
	place(t.Machine.Root, (w - artW) / 2, 40, artW, artH)
	H.sizeMachine(t.Machine, artW)
	L.phoneOdds(t, 6, oddsY, w - 12)
	place(t.Spin.Button, 6, spinY, w - 12, 44)
	H.arrange(t.Spin, w - 12, 44, 16, 18)
	local half = math.floor((w - 18) / 2)
	place(t.Spin3.Button, 6, row2Y, half, 44)
	H.arrange(t.Spin3, half, 44, 15, 15)
	place(t.SpinGems.Button, w - 6 - half, row2Y, half, 44)
	H.arrange(t.SpinGems, half, 44, 15, 16)
	t.Hint.Visible = false
end

-- (Pitch 2 fix round B, T1 look leftover 5: at 844x390 the More arrow sat on the Sky card's odds and the next card's gem
-- price '60' read '6') the Secret card and the four cards share one width (at least K.TILE), sized so the row's viewport
-- holds n WHOLE cards; the viewport ends there and the More arrow sits in the gutter right of it (K.MORE_GUTTER at least),
-- on no card. A drag that stops between two cards snaps to the nearest whole card (H.queueSnap)
function L.phone(P, W, Hh)
	local s = P.Scroll
	s.ScrollingDirection = Enum.ScrollingDirection.X
	local th = math.min(K.TILE_MAX, Hh - 12)
	local y = math.floor((Hh - th) / 2)
	local gap = K.STEP - K.TILE
	local items = 1 + #P.Cards
	-- (fix6, P2 icons look pol1 #1: from 720 to 960 wide the row fitted 3-4 cards of 166-199, whose stages held the sheet's
	-- machines at 1 px cells only, half size in an empty stage, the x3 plank's coin on its words) with the sheet's
	-- machines a card is never narrower than K.TILE_SHEET: fewer whole cards, each drawn at 2 px cells
	local minTile = (P.Hero and P.Hero.Machine and P.Hero.Machine.Sheet) and K.TILE_SHEET or K.TILE
	local n = math.max(1, math.min(items, math.floor((W - K.MORE_GUTTER + gap) / (minTile + gap))))
	local room = n < items and (W - K.MORE_GUTTER) or W
	local tile = math.min(minTile == K.TILE_SHEET and K.TILE_WIDE_SHEET or K.TILE_WIDE, math.max(minTile, math.floor((room - (n - 1) * gap) / n)))
	local pitch = tile + gap
	local viewW = math.min(W, n * pitch - gap)
	place(s, 0, 0, viewW, Hh)
	place(P.Fade, viewW, 0, W - viewW, Hh)
	place(P.Hero.Root, 0, y, tile, th)
	L.heroPhone(P.Hero, tile, th)
	local rowW = #P.Cards * pitch - gap
	place(P.Row, pitch, y, rowW, th)
	P.Row.CanvasSize = UDim2.fromOffset(rowW, 0) -- (no scroll of its own: the page's row scrolls)
	for i, t in ipairs(P.Cards) do
		place(t.Root, (i - 1) * pitch, 0, tile, th)
		L.cardPhone(t, tile, th)
	end
	P.CanvasW = pitch + rowW
	P.ViewW, P.Pitch = viewW, pitch
	s.CanvasSize = UDim2.fromOffset(P.CanvasW, 0)
end

-- (fix round B) the phone row snaps to a whole card once a drag or its glide has rested K.SNAP_DELAY s
function H.snap(P)
	local s = P.Scroll
	if P.Mode ~= "Phone" or not (P.Pitch and P.ViewW) or not s then
		return
	end
	local k = s.AbsoluteSize.X / math.max(1, P.ViewW) -- screen px per layout px
	local pitch = P.Pitch * k
	if pitch <= 0 then
		return
	end
	local maxX = math.max(0, P.CanvasW * k - s.AbsoluteSize.X)
	local x = s.CanvasPosition.X
	local want = math.min(maxX, math.floor(x / pitch + 0.5) * pitch)
	if math.abs(want - x) > 0.5 then
		s.CanvasPosition = Vector2.new(want, s.CanvasPosition.Y)
	end
end

function H.queueSnap(P)
	if P.Mode ~= "Phone" or not P.Pitch then
		return
	end
	P.SnapToken = (P.SnapToken or 0) + 1
	local mine = P.SnapToken
	task.delay(K.SNAP_DELAY, function()
		if P.SnapToken == mine then
			pcall(H.snap, P)
		end
	end)
end

-- a portrait odds grid (spec 16.3): two columns, each cell the egg 30 and the percent 15 beside it (no rarity word: at
-- 15 px "Legendary" + the percent does not fit a half-width cell; the egg's colour names the rarity, as on the phone)
function L.portraitOdds(t, x, y, w)
	place(t.Odds, x, y, w, 68)
	local gw = w / 2
	for i, row in ipairs(t.Rows) do
		local col = (i - 1) % 2
		local line = math.floor((i - 1) / 2)
		place(row.Root, col * gw, line * 36, gw, 32)
		local ew = H.sizeEgg(row.Egg, 30)
		place(row.Egg, 2, 1, ew, 30)
		row.Word.Visible = false
		row.Pct.TextSize = 15
		row.Pct.TextXAlignment = LEFT
		place(row.Pct, ew + 8, 0, math.max(0, gw - ew - 10), 32)
	end
	t.NoOdds.TextSize = 15
	place(t.NoOdds, x, y, w, 68)
end

function L.heroPortrait(t, w, h)
	t.Title.Text = t.Name
	t.Title.TextSize = 20
	t.Title.TextXAlignment = LEFT
	place(t.Title, 8, 8, w - 16, 30)
	t.GemsOnly.Visible = false
	if t.Machine.Sheet then
		-- (P2 icons review r1, major 1; the phone mock-up) the vault at 2 px cells on the left, the odds, the chip and the
		-- hint right of it, the button full width under them
		L.heroSheetArt(t, 8, 42, 128, h - 52 - 8 - 42)
		place(t.Dim, 0, 38, 140, h - 52 - 38)
		local rx, rw = 144, w - 152
		-- (P2 icons review r1, minor: a band of about 30 px of empty navy under the hint, beside the vault) the mock-up's
		-- column: the two odds one over the other (egg 30 beside its percent), the altar chip, the hint, down the vault's
		-- height. More than two odds keep the two-column grid
		local cy = 86
		if #t.Rows == 2 then
			place(t.Odds, rx, 46, rw, 68)
			for i, row in ipairs(t.Rows) do
				place(row.Root, 0, (i - 1) * 36, rw, 32)
				local ew = H.sizeEgg(row.Egg, 30)
				place(row.Egg, 2, 1, ew, 30)
				row.Word.Visible = false
				row.Pct.TextSize = 15
				row.Pct.TextXAlignment = LEFT
				place(row.Pct, ew + 8, 0, math.max(0, rw - ew - 10), 32)
			end
			t.NoOdds.TextSize = 15
			place(t.NoOdds, rx, 46, rw, 68)
			cy = 120
		else
			L.portraitOdds(t, rx, 46, rw)
		end
		place(t.Pity, rx, cy, rw, 36)
		t.Pity.TextSize = 15
		place(t.AltarChip, rx, cy, rw, 36)
		t.AltarChip.TextSize = 15
		place(t.Lock, rx, cy - 4, rw, 44)
		t.Lock.TextSize = 15
		-- (P2 icons look fin1, major: this was a one-line 188 x 20 box at 390 wide, so "A gold arrow leads you to the St..."
		-- and "Secret rolls happen at th..." were cut) the hint wraps at 15 px (the phone floor) in the band from the chip /
		-- lock line down to 2 px over the button: two rows hold every state's line at 390 wide; L.portrait makes the hero
		-- taller where the longest needs more (a 360-wide phone). The box starts 4 px left of the column (still 4 px clear
		-- of the vault's 136 px box) so "Home first, then the arrow" (~191 px in Nunito) keeps one row at 390 instead of
		-- leaving "arrow" alone on the second
		t.Hint.Visible = true
		t.Hint.TextSize = 15
		t.Hint.TextWrapped = true
		-- (P2 icons look pol0, minor: the box ran to 2 px over the button's box, under its 5 px wood edge, so the second
		-- row's 'y' touched the wood) the box ends 3 px over that edge; K.PORTRAIT_HERO_SHEET grew the 6 px it costs
		local hy = cy + 40
		place(t.Hint, rx - 4, hy, rw + 4, h - 52 - 8 - hy)
		place(t.Holder, 8, h - 52, w - 16, 44)
		place(t.Spin.Button, 0, 0, w - 16, 44)
		H.arrange(t.Spin, w - 16, 44, 18, 20)
		H.arrangeTravel(t.Travel, w - 16, 44, 18, 20)
		return
	end
	place(t.Machine.Root, 8, 44, 64, 74)
	H.sizeMachine(t.Machine, 64)
	place(t.Dim, 0, 40, 76, 82) -- the machine only
	t.Egg.Visible = false -- (Task 26: no room on the portrait card)
	L.portraitOdds(t, 80, 46, w - 88)
	place(t.Pity, 80, 84, w - 88, 32)
	t.Pity.TextSize = 15
	place(t.AltarChip, 80, 84, w - 88, 32)
	t.AltarChip.TextSize = 15
	place(t.Lock, 80, 80, w - 88, 40)
	t.Lock.TextSize = 15
	t.Hint.Visible = true
	t.Hint.TextSize = 15
	-- (P2 icons look fin1, major) one 20 px row at 390 wide; on a 360-wide phone "A gold arrow leads you to the Storm
	-- Altar" (~298 px in Nunito) ran past the 294 px box, so it wraps and L.portrait makes the hero a row taller
	t.Hint.TextWrapped = true
	place(t.Hint, 8, 122, w - 16, h - 52 - 6 - 122)
	place(t.Holder, 8, h - 52, w - 16, 44)
	place(t.Spin.Button, 0, 0, w - 16, 44)
	H.arrange(t.Spin, w - 16, 44, 18, 20)
	H.arrangeTravel(t.Travel, w - 16, 44, 18, 20)
end

function L.cardPortrait(t, w, h)
	if t.Machine.Sheet then
		return L.cardSheetPortrait(t, w, h)
	end
	t.Plate.Text = t.Name
	t.Plate.TextSize = 20
	place(t.Plate, 8, 8, w - 16, 34)
	place(t.Machine.Root, 8, 50, 64, 74)
	H.sizeMachine(t.Machine, 64)
	L.portraitOdds(t, 80, 50, w - 88)
	t.Hint.Visible = true
	t.Hint.TextSize = 15
	place(t.Hint, 80, 122, w - 88, 20)
	place(t.Spin.Button, 8, h - 104, w - 16, 46)
	H.arrange(t.Spin, w - 16, 46, 18, 20)
	local half = math.floor((w - 24) / 2)
	place(t.Spin3.Button, 8, h - 52, half, 44)
	H.arrange(t.Spin3, half, 44, 15, 16)
	place(t.SpinGems.Button, w - 8 - half, h - 52, half, 44)
	H.arrange(t.SpinGems, half, 44, 15, 16)
end

function L.portrait(P, W, Hh)
	local s = P.Scroll
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	local w = W - K.SCROLLBAR - 2
	local sheet = P.Hero.Machine.Sheet == true
	local heroH = sheet and K.PORTRAIT_HERO_SHEET or K.PORTRAIT_HERO
	-- (P2 icons look fin1, major) the hero's hint stays 15 px (the phone floor) and whole: its band holds two rows beside
	-- the vault (one under today's drawn machine); a 15 px row more of hero for each row its longest line needs beyond
	-- that (a 360-wide phone)
	local band = sheet and 2 or 1
	local hintW = sheet and (w - 148) or (w - 16)
	heroH = heroH + math.max(0, H.heroHintRows(hintW, 15, Theme.FontOf(P.Hero.Hint)) - band) * 15
	local cardH = sheet and K.PORTRAIT_CARD_SHEET or K.PORTRAIT_CARD
	place(P.Hero.Root, 0, 0, w, heroH)
	L.heroPortrait(P.Hero, w, heroH)
	local step = cardH + 8
	local rowH = #P.Cards * step - 8
	place(P.Row, 0, heroH + 8, w, rowH)
	P.Row.CanvasSize = UDim2.fromOffset(0, rowH) -- (no scroll of its own: the page scrolls)
	for i, t in ipairs(P.Cards) do
		place(t.Root, 0, (i - 1) * step, w, cardH)
		L.cardPortrait(t, w, cardH)
	end
	P.CanvasW = 0
	s.CanvasSize = UDim2.fromOffset(0, heroH + 8 + rowH + 8)
end

-- the phone's right fade: shown while more of the sideways row is to the right
function ShopEggs._SyncFade(page)
	local P = PAGES[page]
	if not P then
		return
	end
	local on = false
	if P.Mode == "Phone" then
		local s = P.Scroll
		local k = 1
		pcall(function()
			k = s.AbsoluteSize.X / math.max(1, P.ViewW or P.Box.W) -- (fix round B) the viewport ends before the More gutter
		end)
		local canvas = (P.CanvasW or 0) * k
		on = canvas > s.AbsoluteSize.X + 1 and s.CanvasPosition.X < canvas - s.AbsoluteSize.X - 1
	end
	P.Fade.Visible = on
end

function ShopEggs.Layout(page, box, mode)
	local P = PAGES[page]
	if not P then
		return
	end
	box = type(box) == "table" and box or P.Box
	local key = tostring(box.W) .. "x" .. tostring(box.H) .. tostring(mode or P.Mode)
	P.Box = { W = math.floor(tonumber(box.W) or 1240), H = math.floor(tonumber(box.H) or 834) }
	P.Mode = mode or P.Mode or "PC"
	P.Laid = true
	if key ~= P.LaidKey then
		-- a new size or layout: the old scroll offsets mean nothing there; start at the top-left
		P.LaidKey = key
		P.Scroll.CanvasPosition = Vector2.new(0, 0)
		P.Row.CanvasPosition = Vector2.new(0, 0)
	end
	local W, Hh = P.Box.W, P.Box.H
	place(P.Scroll, 0, 0, W, Hh)
	place(P.Fade, W - K.FADE, 0, K.FADE, Hh)
	P.ViewW, P.Pitch = nil, nil -- (fix round B) L.phone sets them
	if P.Mode == "Phone" then
		L.phone(P, W, Hh)
	elseif P.Mode == "Portrait" then
		L.portrait(P, W, Hh)
	else
		L.pc(P, W, Hh)
	end
	-- (a layout can change the short texts: the states and the chip follow it)
	ShopEggs.Refresh(page, true)
	ShopEggs._SyncFade(page)
	H.syncFx(P)
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
-- shop-area (spec 16.17.3): the Secret roll is bought at the Storm Altar only (PetService.BuyRoulette checks the distance;
-- this only picks the card's look). The live reading (the character's HumanoidRootPart against the replicated altar
-- site) wins whenever it exists; FromAltar (the altar prompt's open) only stands in while there is none (no root, no
-- AltarIslandAt yet). Review round 1: FromAltar used to win until Close, so a player who opened the Shop at the altar
-- and walked off kept a live SPIN the server refused.
function ShopEggs.AtAltar()
	if ShopEggs._AtAltar ~= nil then
		return ShopEggs._AtAltar == true
	end
	local ok, at = pcall(function()
		local player = Players.LocalPlayer
		local char = player and player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not (root ~= nil and root:IsA("BasePart")) or typeof(workspace:GetAttribute(Config.Lobby.ZoneAltarAttr)) ~= "Vector3" then
			return nil -- no live reading
		end
		return Config.AtAltar(root.Position, 0) == true
	end)
	if ok and at ~= nil then
		return at
	end
	return ALTAR.From == true
end

-- TRAVEL's look: true while the character stands in the lobby (Config.InLobbyZone, the server's rule for the trip);
-- with no live reading (no root) it stays true and the server decides. Tests: ShopEggs._InLobby (nil = live).
function ShopEggs.InLobby()
	if ShopEggs._InLobby ~= nil then
		return ShopEggs._InLobby == true
	end
	local ok, inLobby = pcall(function()
		local player = Players.LocalPlayer
		local char = player and player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not (root ~= nil and root:IsA("BasePart")) then
			return nil
		end
		return Config.InLobbyZone(root.Position) == true
	end)
	if ok and inLobby ~= nil then
		return inLobby
	end
	return true
end

function ShopEggs.SetFromAltar(on)
	ALTAR.From = on == true
end

function ShopEggs.CardState(id, button)
	button = button or "Spin"
	if #H.odds(id) == 0 then
		return "NoOdds"
	end
	if EggStage.IsPending() then
		return "Pending"
	end
	local gems = id == K.SECRET or button == "SpinGems"
	-- (lobby-shop 16.12, the owner's pick A: the token spins lock too, as the server refuses them while not "Allowed".
	-- Release step 1, the owner's pick 2026-11-23: only while the Store is on; with the Store off a token button is
	-- never Locked, as on main. The gem buttons and the Secret card keep the lock in both states.)
	if attr("PaidRandomItemsRestricted") ~= false and (gems or StoreCatalog.Enabled()) then
		return "Locked"
	end
	if id == K.SECRET and not ShopEggs.AtAltar() then
		return "Altar"
	end
	if gems and attr("GemsSettled") ~= true then
		return "Loading"
	end
	local currency = gems and "Gems" or "Tokens"
	local price = H.price(id, currency) * ((button == "Spin3" and not gems) and 3 or 1)
	if H.balance(currency) < price then
		return "Short"
	end
	return "Ready"
end

-- amount: the price as a number, always in the game's one number style, Theme.Short ("3K", "15K", "250"). (Pitch 2 F0,
-- the owner's pick A: the prices read as the HUD's balances do; was "3,000" with separators, short only on the phone's x3
-- or when the row did not fit.) compact is kept for the callers (the phone's x3): the same short form
function H.paintButton(p, id, name, amount, short, compact)
	local st = ShopEggs.CardState(id, name)
	amount = tonumber(amount) or 0
	p.PriceShort = Theme.Short(amount)
	p.PriceFull = p.PriceShort
	p.Price.Text = p.PriceFull
	p.Price.TextColor3 = st == "Short" and SHORT or p.Ink
	local stateText = nil
	if st == "Locked" then
		stateText = K.TEXT.Locked
	elseif st == "Loading" then
		stateText = short and K.TEXT.LoadingShort or K.TEXT.Loading
	end
	p.StateText = stateText
	p.Word.Text = stateText or p.BaseWord
	local off = st == "NoOdds" or st == "Pending" or st == "Locked" or st == "Altar" or st == "Loading"
	if (p.Button:GetAttribute("Disabled") == true) ~= off then
		CloudUI.SetDisabled(p.Button, off) -- (only on a change: a repaint tweens the face)
	end
	H.arrange(p)
	return st
end

function H.pityText(short)
	local left = tonumber(attr("SecretPityLeft"))
	if attr("GemsSettled") ~= true or left == nil then
		return K.TEXT.Loading
	end
	left = math.max(1, math.floor(left))
	if short then
		return left <= 1 and "Secret next spin" or ("Secret in " .. left)
	end
	if left <= 1 then
		return "Secret for sure on the next spin"
	end
	return "Secret for sure in " .. left .. " more spins"
end

function ShopEggs.Refresh(page, fromLayout)
	local P = PAGES[page]
	if not P then
		return
	end
	local rebuilt = false
	for _, t in ipairs(H.all(P)) do
		if H.syncRows(t) then
			rebuilt = true
		end
	end
	if rebuilt and P.Laid and not fromLayout then
		ShopEggs.Layout(page, P.Box, P.Mode) -- (it repaints)
		return
	end
	local short = P.Mode == "Phone"
	for _, t in ipairs(P.Cards) do
		t.Odds.Visible = t.HasOdds == true
		t.NoOdds.Visible = t.HasOdds ~= true
		local unit = H.price(t.Id, "Tokens")
		H.paintButton(t.Spin, t.Id, "Spin", unit, short)
		-- (review round 3) the phone's 74 px x3 button: the short total from 1,000 up ("3K"; "3,000" ran onto the gem button)
		H.paintButton(t.Spin3, t.Id, "Spin3", 3 * unit, short, short)
		H.paintButton(t.SpinGems, t.Id, "SpinGems", H.price(t.Id, "Gems"), short)
	end
	local h = P.Hero
	h.Odds.Visible = h.HasOdds == true
	h.NoOdds.Visible = h.HasOdds ~= true
	H.paintButton(h.Spin, K.SECRET, "Spin", H.price(K.SECRET, "Gems"), short)
	local restricted = attr("PaidRandomItemsRestricted")
	local locked = restricted ~= false
	local brief = P.Mode == "Phone" or P.Mode == "Portrait"
	-- (shop-area 16.17.3) away from the Storm Altar: the Dim, the altar chip and TRAVEL (Locked keeps its own card)
	local altar = not locked and not ShopEggs.AtAltar()
	h.Lock.Visible = locked
	h.Pity.Visible = not locked and not altar
	-- (P2 icons review r1, major 3) the vault stays bright (the altar chip's padlock says why): the Dim veils today's drawn
	-- machine only (H.showSheets keeps it so when the page's look changes)
	h.Away = altar
	h.Dim.Visible = altar and not H.sheetShown(h)
	h.AltarChip.Visible = altar
	-- (P2 icons look pol0, major) the phone line while it fits the chip's room beside its padlock (the chip less its
	-- UIPadding, 2 px spare), else the tiny one: never a cut "At the Storm Al." (kit-b P2 fix6, icons look pol1 #2) the
	-- PC chip the same way from its long line: a tablet's narrow chip (L.heroPC) reads the phone's
	local chipText = brief and K.TEXT.AltarLockShort or K.TEXT.AltarLock
	local pad = h.AltarChip:FindFirstChildOfClass("UIPadding")
	local room = h.AltarChip.Size.X.Offset - (pad and (pad.PaddingLeft.Offset + pad.PaddingRight.Offset) or 0)
	local function fits(line)
		return H.textW(line, h.AltarChip.TextSize, Theme.FontOf(h.AltarChip)) + 2 <= room
	end
	if brief then
		if not fits(chipText) then
			chipText = K.TEXT.AltarLockTiny
		end
	elseif h.AltarChip.Size.X.Offset > 0 and not fits(chipText) then
		-- (laid out: before its first layout it keeps the long line)
		chipText = fits(K.TEXT.AltarLockShort) and K.TEXT.AltarLockShort or K.TEXT.AltarLockTiny
	end
	h.AltarChip.Text = chipText
	h.Travel.Button.Visible = altar
	h.Spin.Button.Visible = not altar
	-- (Pitch 2 item 13 A) away from the lobby the guide routes home first, so the button stays live and the hint says so;
	-- it greys only while a match / battle / run holds the player (it greyed whenever away: the teleport needed the lobby)
	local held = altar and H.tripLocked()
	local away = altar and not held and not ShopEggs.InLobby()
	if (h.Travel.Button:GetAttribute("Disabled") == true) ~= held then
		CloudUI.SetDisabled(h.Travel.Button, held)
	end
	local lobbyHint = brief and K.TEXT.HeroHintLobbyShort or K.TEXT.HeroHintLobby
	h.Hint.Text = (locked and K.TEXT.HeroHint) or (held and K.TEXT.HeroHintLocked) or (away and lobbyHint)
		or (altar and K.TEXT.HeroHintTravel) or K.TEXT.HeroHintHere
	if P.Mode == "Phone" then
		-- (Pitch 2 look review r0, minor 5) the phone card says why the button routes home / is greyed, before the tap
		h.Hint.Visible = (away or held) and h.PhoneHintRoom == true
	end
	if altar then
		h.Pulse.Scale = 1
	end
	if locked then
		if restricted == true then
			h.Lock.Text = brief and K.TEXT.LockShort or K.TEXT.Lock
		else
			h.Lock.Text = brief and K.TEXT.CheckingShort or K.TEXT.Checking
		end
	else
		-- (Portrait: the long line while it fits the chip, else the phone's "Secret in N"; kit-b P2 fix6: on PC too, the
		-- tablet's narrow chip)
		local text = H.pityText(short)
		if not short and (P.Mode == "Portrait" or h.Pity.Size.X.Offset > 0)
			and H.textW(text, h.Pity.TextSize, Theme.FontOf(h.Pity)) + 16 > h.Pity.Size.X.Offset then
			text = H.pityText(true)
		end
		h.Pity.Text = text
	end
end

----------------------------------------------------------------------
-- Focus
----------------------------------------------------------------------
function H.setFocus(t, on)
	t.Root:SetAttribute("Focused", on == true)
	t.Card.Stroke.Color = on and K.GOLD or t.Edge -- (kit-b U9-2: back to its wood / gold-lip edge)
	t.Card.Stroke.Thickness = on and K.FOCUS_STROKE or t.Thick
end

-- centres `obj` in the ScrollingFrame `sc` as far as its canvas allows (CanvasPosition in screen px, as G.reach reads it)
function H.centre(sc, obj)
	local sx = sc.Size.X.Offset > 0 and sc.AbsoluteSize.X / sc.Size.X.Offset or 1
	local sy = sc.Size.Y.Offset > 0 and sc.AbsoluteSize.Y / sc.Size.Y.Offset or 1
	local maxX = math.max(0, sc.CanvasSize.X.Offset * sx - sc.AbsoluteSize.X)
	local maxY = math.max(0, sc.CanvasSize.Y.Offset * sy - sc.AbsoluteSize.Y)
	local cp = sc.CanvasPosition
	local x = cp.X + (obj.AbsolutePosition.X - sc.AbsolutePosition.X) + (obj.AbsoluteSize.X - sc.AbsoluteSize.X) / 2
	local y = cp.Y + (obj.AbsolutePosition.Y - sc.AbsolutePosition.Y) + (obj.AbsoluteSize.Y - sc.AbsoluteSize.Y) / 2
	sc.CanvasPosition = Vector2.new(math.max(0, math.min(maxX, x)), math.max(0, math.min(maxY, y)))
end

function H.scrollTo(P, t)
	pcall(H.centre, P.Row, t.Root)
	pcall(H.centre, P.Scroll, t.Root)
end

function ShopEggs.Focus(page, rouletteId)
	local P = PAGES[page or CUR.Page]
	if not P then
		return false
	end
	local target = nil
	for _, t in ipairs(H.all(P)) do
		H.setFocus(t, false)
		if t.Id == rouletteId then
			target = t
		end
	end
	if not target then
		return false
	end
	P.FocusToken = (P.FocusToken or 0) + 1
	local mine = P.FocusToken
	H.setFocus(target, true)
	H.scrollTo(P, target)
	task.defer(function()
		if P.FocusToken == mine then
			H.scrollTo(P, target) -- (again once the engine has laid the page out)
		end
	end)
	task.delay(K.FOCUS_SECONDS, function()
		if P.FocusToken == mine then
			H.setFocus(target, false)
		end
	end)
	return true
end

function ShopEggs.HeroPulse(page)
	local P = PAGES[page or CUR.Page]
	return P and P.Hero.Pulse or nil
end

return ShopEggs
