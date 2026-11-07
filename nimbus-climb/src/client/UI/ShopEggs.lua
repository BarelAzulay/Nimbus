-- ShopEggs (client UI; lobby-shop Task 22, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.3 "Eggs tab", 16.5
-- "Fixes"): the Shop's Eggs page. ShopController builds it into its Page_Eggs frame, lays it out on every resize and
-- repaints it on every refresh. It never decides a price or a roll: every button goes through EggStage.Request (the one
-- BuyRoulette sender: the FIRE_GAP, the pending flag, the "You need ..." and policy toasts); the server checks again.
--
--   ShopEggs.Build(page, ctx)        page = the Page_Eggs Frame. In it: a ScrollingFrame "Scroll" holding ShopCard_Secret
--                                    (the hero, attribute Hero = true) and the ScrollingFrame "Cards" (ShopCard_Cloud /
--                                    _Storm / _Sky / _Celestial), and the phone's right "Fade" (48 px while more of the
--                                    row is to the right). ctx = { Tap() } (the click sound) | nil
--   ShopEggs.Layout(page, box, mode) box = { W, H } (the content box, design px); mode:
--                                    "PC" / "Compact": the hero 240 tall at (0, 16) (the machine 190 x 218 at (26, 10),
--                                      "Secret Roulette" 46 px at (240, 22), the odds line at (240, 84), the PityChip
--                                      400 x 48 at (240, 132), Spin 290 x 100 at (w - 320, 66), the hint under it), the
--                                      card row at y 276: four cards (w - 48) / 4 wide (sideways under 250), 550 tall
--                                      (NamePlate, the machine 130 x 150 at y 76, Odds_* rows 40 tall from y 234, Spin
--                                      64 at y 400, Spin3 / SpinGems at y 476 half width, the hint). A body under 826 px
--                                      shrinks it (the hero 200 with a 160 machine, the cards 516 at y 236 with a 100
--                                      machine) and the page scrolls; Compact / shrunk second-row buttons are 56 tall
--                                      (>= 44 px at the 0.8 scale)
--                                    "Phone": one sideways row: the Secret card 200 wide, then the four cards 166 wide at
--                                      x = 208 + i * 174, every card min(266, H - 12) tall (the art shrinks first)
--                                    "Portrait": a vertical list of full-width cards (Secret 200 tall, the machines 250;
--                                      the odds a 2 x 2 grid of egg 30 + % 15; the PityChip's long line while it
--                                      fits, else "Secret in N")
--   ShopEggs.Refresh(page)           the odds rows (rebuilt when PetCatalog.GetRarityOdds changes), the prices, the
--                                    states, the PityChip, the lock texts
--   ShopEggs.Focus(page, rouletteId) -> bool   scrolls that card into view (centred when its row scrolls) and outlines
--                                    it gold for 2.6 s (attribute Focused)
--   ShopEggs.CardState(rouletteId, button) -> "NoOdds" | "Pending" | "Locked" | "Loading" | "Short" | "Ready"
--                                    button = "Spin" (default) | "Spin3" | "SpinGems". In that order: no odds; a request
--                                    pending (EggStage.IsPending: every button); a gem button (SpinGems, every Secret
--                                    button) while PaidRandomItemsRestricted is not false (Locked) or before GemsSettled
--                                    (Loading); the balance under the price (Short: the price kept, drawn red, the
--                                    button still taps and EggStage toasts); else Ready
--   ShopEggs.HeroPulse(page) -> the UIScale "Pulse" of the hero's Spin (ShopController's shine pulses it, High only)
--   ShopEggs.Metrics                 the K table (sizes, texts; MEASURE: a text-width hook for the offline renderer)
-- Buttons: Spin = EggStage.Request(id, "Tokens", 1), Spin3 = (id, "Tokens", 3), SpinGems = (id, "Gems", 1), the Secret
-- card's Spin = ("Secret", "Gems", 1). A spin button holds Word ("SPIN" / "x3", or the state: "Locked", "Loading..."),
-- the currency icon (TokenIcon: the Cloud Token glyph; GemIcon: the drawn gem) and Price. The machines are frames placed
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

local UI = script.Parent
local NeonKit = require(UI:WaitForChild("NeonKit"))
local GemIcon = require(UI:WaitForChild("GemIcon"))
local CloudUI = require(UI:WaitForChild("CloudUI"))
local EggArt = require(UI:WaitForChild("EggArt"))
local EggStage = require(UI:WaitForChild("EggStage"))
local State = require(UI.Parent:WaitForChild("State"))

local ShopEggs = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local SECRET_DEF = type(Config.Gems) == "table" and Config.Gems.SecretRoulette or nil
local K = {
	SECRET = (type(SECRET_DEF) == "table" and SECRET_DEF.Id) or "Secret",
	MACHINES = { "Cloud", "Storm", "Sky", "Celestial" },
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
	SCROLLBAR = 6,
	FIT_H = 826, -- a PC / Compact body under this shrinks the page
	PORTRAIT_CARD = 250,
	PORTRAIT_HERO = 200,
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
		HeroHint = "Also at the Storm Altar",
		GemsOnly = "gems only",
	},
	-- the PC plans (REF while the body holds FIT_H, SHRUNK under it)
	REF = { Ref = true, Hero = 240, HeroArt = 190, CardsY = 276, Card = 550, Art = 130, RowsY = 234, SpinY = 400, Row2Y = 476 },
	SHRUNK = { Ref = false, Hero = 200, HeroArt = 160, CardsY = 236, Card = 516, Art = 100, RowsY = 198, SpinY = 362, Row2Y = 436 },
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
local LEFT, RIGHT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right, Enum.TextXAlignment.Center
local PAGES = setmetatable({}, { __mode = "k" }) -- page -> its widgets
local CUR = setmetatable({}, { __mode = "v" }) -- CUR.Page: the page built last (Focus without a page)
local H = {} -- helpers
local L = {} -- layouts

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
	local l = Theme.Label(text or "", role, { Size = size, Stroke = 1, Outline = 2 })
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
	s.ScrollBarThickness = K.SCROLLBAR
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
		return TextService:GetTextSize(text, size, font, Vector2.new(10000, 1000))
	end)
	if ok and typeof(v) == "Vector2" and v.X > 0 then
		return v.X
	end
	return #tostring(text) * size * 0.55
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

function H.call(P, name, ...)
	local fn = P.Ctx[name]
	if type(fn) == "function" then
		pcall(fn, ...)
	end
end

----------------------------------------------------------------------
-- the machine (frames placed by scale in the pitch's 200 x 230 box)
----------------------------------------------------------------------
function H.part(m, parent, box, name, x, y, w, h, color, radius, strokeW, props)
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

function H.machine(parent, id, color, secret)
	local m = { Strokes = {} }
	local root = frame("Machine", parent)
	m.Root = root
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
	H.part(m, root, B, "Glass", D[1], D[2], D[3], D[4], secret and K.HERO or rgb(191, 230, 255), 0.5, 5, { BackgroundTransparency = 0.84 })
	H.part(m, root, B, "Shine", 54, 28, 44, 9, WHITE, 0.5, nil, { BackgroundTransparency = 0.25, Rotation = -32 })
	H.part(m, root, B, "Cap", 82, 2, 36, 18, Theme.Lighten(color, 0.2), 0.35, 4)
	return m
end

-- the machine `px` wide (its strokes follow the size)
function H.sizeMachine(m, px)
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
	local p = { Currency = currency, BaseWord = word or "" }
	p.Button = CloudUI.Button({
		Name = name,
		Text = "",
		Style = style,
		Size = UDim2.fromOffset(200, 60),
		TextSize = 22,
		Callback = function()
			H.tap(P, id, currency, spins)
		end,
		Parent = parent,
	})
	p.Word = label("Word", p.Button, p.BaseWord, "Button", 22, { TextTruncate = Enum.TextTruncate.None })
	if currency == "Tokens" then
		local cur = Theme.Currency.Tokens
		p.Icon = label("TokenIcon", p.Button, cur.Glyph, "Display", 22, { TextColor3 = cur.Color, TextTruncate = Enum.TextTruncate.None })
	end
	p.Price = label("Price", p.Button, "", "Button", 22, { TextTruncate = Enum.TextTruncate.None })
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
	if p.Currency == "Gems" and p.GemPx ~= iconPx then
		if p.Icon then
			p.Icon:Destroy()
		end
		p.Icon = GemIcon.New(p.Button, iconPx, { Name = "GemIcon" })
		p.GemPx = iconPx
	elseif p.Currency ~= "Gems" then
		p.Icon.TextSize = iconPx
	end
	p.Word.TextSize = size
	p.Price.TextSize = size
	local stateOnly = p.StateText ~= nil
	p.Word.Visible = p.Word.Text ~= ""
	p.Icon.Visible = not stateOnly
	p.Price.Visible = not stateOnly
	local items = {}
	if p.Word.Visible then
		items[#items + 1] = { p.Word, H.textW(p.Word.Text, size, p.Word.Font), true }
	end
	if not stateOnly then
		items[#items + 1] = { p.Icon, iconPx, false }
		items[#items + 1] = { p.Price, H.textW(p.Price.Text, size, p.Price.Font), true }
	end
	local gap = math.max(3, math.floor(size * 0.3))
	local total = 0
	for _, it in ipairs(items) do
		total = total + it[2]
	end
	if total + gap * (#items - 1) > w - 8 then
		gap = 2
	end
	total = total + gap * (#items - 1)
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

function H.card(P, parent, id, color, fill, size)
	local c = NeonKit.Card({ Name = "ShopCard_" .. id, Color = color, Fill = fill, Floor = false, Size = size, Parent = parent })
	local t = { Id = id, Root = c.Root, Card = c, Color = color, Thick = c.Stroke.Thickness, Rows = {} }
	local r = H.roulette(id)
	t.Name = (r and r.DisplayName) or (id .. " Roulette")
	return t, c.Body
end

function H.buildHero(P, parent)
	local t, b = H.card(P, parent, K.SECRET, K.HERO, { rgb(52, 34, 112), rgb(16, 12, 40) }, UDim2.fromOffset(1240, 240))
	t.Hero = true
	t.Root:SetAttribute("Hero", true)
	t.Machine = H.machine(b, K.SECRET, K.HERO_MACHINE, true)
	t.Title = label("Title", b, t.Name, "Title", 46, { TextXAlignment = LEFT })
	t.Odds = frame("OddsLine", b)
	t.GemsOnly = label("GemsOnly", t.Odds, K.TEXT.GemsOnly, "Body", 24, { TextXAlignment = LEFT, TextColor3 = MUTED })
	t.NoOdds = label("NoOdds", b, K.TEXT.NoOdds, "Body", 22, { Visible = false, TextColor3 = MUTED, TextXAlignment = LEFT })
	t.Pity = label("PityChip", b, "", "Heading", 22, { BackgroundTransparency = 0, BackgroundColor3 = K.CHIP })
	Theme.Corner(t.Pity, UDim.new(0, 12))
	Theme.Stroke(t.Pity, K.HERO, 2, 0.2)
	t.Lock = label("Lock", b, "", "Body", 20, {
		Visible = false, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextColor3 = K.LINE, TextXAlignment = LEFT,
	})
	t.Holder = frame("SpinHolder", b)
	t.Pulse = Util.Create("UIScale", { Name = "Pulse", Scale = 1, Parent = t.Holder })
	t.Spin = H.spinButton(P, t.Holder, "Spin", "Pink", "SPIN", "Gems", K.SECRET, 1)
	t.Hint = label("Hint", b, K.TEXT.HeroHint, "Body", 18, { TextColor3 = K.LINE })
	return t
end

function H.buildCard(P, parent, id)
	local r = H.roulette(id)
	local color = (r and typeof(r.Color) == "Color3") and r.Color or rgb(120, 190, 235)
	local t, b = H.card(P, parent, id, color, { Theme.Darken(color, 0.45), Theme.Darken(color, 0.82) }, UDim2.fromOffset(298, 550))
	t.Plate = label("NamePlate", b, t.Name, "Heading", 24, { BackgroundTransparency = 0, BackgroundColor3 = Theme.Darken(color, 0.3) })
	Theme.Corner(t.Plate, UDim.new(0, 14))
	Theme.Stroke(t.Plate, K.NAVY, 3, 0)
	t.Machine = H.machine(b, id, color, false)
	t.Odds = frame("Odds", b)
	t.NoOdds = label("NoOdds", b, K.TEXT.NoOdds, "Body", 20, { Visible = false, TextColor3 = MUTED, TextWrapped = true, TextTruncate = Enum.TextTruncate.None })
	t.Spin = H.spinButton(P, b, "Spin", "Green", "SPIN", "Tokens", id, 1)
	t.Spin3 = H.spinButton(P, b, "Spin3", "Gold", "x3", "Tokens", id, 3)
	t.SpinGems = H.spinButton(P, b, "SpinGems", "Blue", nil, "Gems", id, 1)
	t.Hint = label("Hint", b, K.TEXT.Hint, "Body", 18, { TextColor3 = K.LINE })
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
		row.Word = label("Word", row.Root, tostring(e.Rarity), "Heading", 20, { TextColor3 = H.rarityText(e.Rarity), TextXAlignment = LEFT })
		row.Pct = label("Pct", row.Root, H.pct(e.Chance), "Heading", 22, { TextXAlignment = RIGHT })
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
	P.Fade = frame("Fade", page, { BackgroundTransparency = 0, BackgroundColor3 = Theme.Colors.PanelBottom or rgb(12, 15, 38), Visible = false, ZIndex = 6 })
	Util.Create("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.08) }),
		Parent = P.Fade,
	})
	P.Hero = H.buildHero(P, P.Scroll)
	P.Row = scroller("Cards", P.Scroll, Enum.ScrollingDirection.X)
	for i, id in ipairs(K.MACHINES) do
		P.Cards[i] = H.buildCard(P, P.Row, id)
	end
	P.Scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		ShopEggs._SyncFade(page)
	end)
	ShopEggs.Refresh(page)
	return P
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
-- the hero's odds line on PC: each row Egg 40 + the rarity + the percent (24 px), then "gems only"
function L.heroOddsPC(t, w)
	local x = 0
	for _, row in ipairs(t.Rows) do
		local ew = H.sizeEgg(row.Egg, 40)
		place(row.Egg, 0, 0, ew, 40)
		row.Word.Visible = true
		row.Word.TextSize = 24
		row.Pct.TextSize = 24
		local ww = H.textW(row.Word.Text, 24, row.Word.Font) + 2
		local pw = H.textW(row.Pct.Text, 24, row.Pct.Font) + 2
		place(row.Word, ew + 8, 0, ww, 40)
		place(row.Pct, ew + 8 + ww + 8, 0, pw, 40)
		row.Pct.TextXAlignment = LEFT
		local rw = ew + 8 + ww + 8 + pw
		place(row.Root, x, 0, rw, 40)
		x = x + rw + 24
	end
	t.GemsOnly.Visible = true
	t.GemsOnly.TextSize = 24
	place(t.GemsOnly, x, 0, math.max(0, w - x), 40)
end

function L.heroPC(t, w, M)
	local ref = M.Ref
	local art = M.HeroArt
	local artH = math.floor(art * 1.15)
	place(t.Machine.Root, 26, ref and 10 or 8, art, artH)
	H.sizeMachine(t.Machine, art)
	local x = art + 50
	local tw = w - x - 340
	t.Title.Text = t.Name
	t.Title.TextSize = 46
	place(t.Title, x, ref and 22 or 12, tw, 56)
	local oy = ref and 84 or 76
	place(t.Odds, x, oy, tw, 40)
	L.heroOddsPC(t, tw)
	place(t.NoOdds, x, oy, tw, 40)
	t.NoOdds.TextSize = 22
	local cy = ref and 132 or 124
	place(t.Pity, x, cy, math.min(400, tw), 48)
	t.Pity.TextSize = 22
	place(t.Lock, x, cy, tw, 48)
	t.Lock.TextSize = 20
	place(t.Holder, w - 320, ref and 66 or 46, 290, 100)
	place(t.Spin.Button, 0, 0, 290, 100)
	H.arrange(t.Spin, 290, 100, 34, 44)
	t.Hint.Visible = true
	t.Hint.TextSize = 18
	place(t.Hint, w - 320, ref and 172 or 152, 290, 28)
end

function L.cardPC(t, w, M, tall)
	local row2H = tall and 56 or 48
	t.Plate.Text = t.Name
	t.Plate.TextSize = 24
	place(t.Plate, 12, 12, w - 24, 54)
	local artH = math.floor(M.Art * 1.15 + 0.5)
	place(t.Machine.Root, (w - M.Art) / 2, 76, M.Art, artH)
	H.sizeMachine(t.Machine, M.Art)
	place(t.Odds, 16, M.RowsY, w - 32, 160)
	local n = #t.Rows
	local rh = n > 4 and math.floor(160 / n) or 40
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
	place(t.NoOdds, 16, M.RowsY, w - 32, 160)
	place(t.Spin.Button, 14, M.SpinY, w - 28, 64)
	H.arrange(t.Spin, w - 28, 64, 23, 26)
	local half = math.floor((w - 38) / 2)
	place(t.Spin3.Button, 14, M.Row2Y, half, row2H)
	H.arrange(t.Spin3, half, row2H, 18, 20)
	place(t.SpinGems.Button, w - 14 - half, M.Row2Y, half, row2H)
	H.arrange(t.SpinGems, half, row2H, 18, 22)
	local hy = M.Row2Y + row2H + 2
	t.Hint.Visible = true
	t.Hint.TextSize = 18
	place(t.Hint, 8, hy, w - 16, math.max(16, M.Card - hy))
end

function L.pc(P, W, Hh)
	local M = Hh >= K.FIT_H and K.REF or K.SHRUNK
	local tall = P.Mode == "Compact" or not M.Ref
	local s = P.Scroll
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	-- the card row: (w - 48) / 4 each; under 250 it scrolls sideways (with room for its bar)
	local function plan(cw)
		local cardW = math.floor((cw - 48) / 4)
		local sideways = cardW < 250
		if sideways then
			cardW = 250
		end
		local rowH = M.Card + (sideways and (K.SCROLLBAR + 4) or 0)
		return cardW, sideways, rowH, M.CardsY + rowH + 8
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
	place(P.Hero.Root, 0, 16, cw, M.Hero)
	L.heroPC(P.Hero, cw, M)
	place(P.Row, 0, M.CardsY, cw, rowH)
	P.Row.ScrollingDirection = Enum.ScrollingDirection.X
	local rowW = #P.Cards * (cardW + 16) - 16
	P.Row.CanvasSize = UDim2.fromOffset(sideways and rowW or cw, 0)
	for i, t in ipairs(P.Cards) do
		place(t.Root, (i - 1) * (cardW + 16), 0, cardW, M.Card)
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

function L.heroPhone(t, w, th)
	local pad = phonePad(th)
	t.Title.Text = "Secret"
	t.Title.TextSize = 17
	t.Title.TextXAlignment = CENTER
	place(t.Title, 6, 6, w - 12, 30)
	place(t.Machine.Root, 8, 40, 64, 74)
	H.sizeMachine(t.Machine, 64)
	t.GemsOnly.Visible = false
	L.phoneOdds(t, 80, 40, w - 88)
	local chipY = th - pad - 94
	place(t.Pity, 6, chipY, w - 12, 44)
	t.Pity.TextSize = 15
	place(t.Lock, 6, chipY, w - 12, 44)
	t.Lock.TextSize = 15
	place(t.Holder, 6, th - pad - 44, w - 12, 44)
	place(t.Spin.Button, 0, 0, w - 12, 44)
	H.arrange(t.Spin, w - 12, 44, 16, 18)
	t.Hint.Visible = false
end

function L.cardPhone(t, w, th)
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

function L.phone(P, W, Hh)
	local s = P.Scroll
	s.ScrollingDirection = Enum.ScrollingDirection.X
	local th = math.min(K.TILE_MAX, Hh - 12)
	local y = math.floor((Hh - th) / 2)
	place(P.Hero.Root, 0, y, K.HERO_PHONE, th)
	L.heroPhone(P.Hero, K.HERO_PHONE, th)
	local rowW = #P.Cards * K.STEP - (K.STEP - K.TILE)
	place(P.Row, K.HERO_PHONE + 8, y, rowW, th)
	P.Row.CanvasSize = UDim2.fromOffset(rowW, 0) -- (no scroll of its own: the page's row scrolls)
	for i, t in ipairs(P.Cards) do
		place(t.Root, (i - 1) * K.STEP, 0, K.TILE, th)
		L.cardPhone(t, K.TILE, th)
	end
	P.CanvasW = K.HERO_PHONE + 8 + rowW
	s.CanvasSize = UDim2.fromOffset(P.CanvasW, 0)
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
	place(t.Machine.Root, 8, 44, 64, 74)
	H.sizeMachine(t.Machine, 64)
	t.GemsOnly.Visible = false
	L.portraitOdds(t, 80, 46, w - 88)
	place(t.Pity, 80, 84, w - 88, 32)
	t.Pity.TextSize = 15
	place(t.Lock, 80, 80, w - 88, 40)
	t.Lock.TextSize = 15
	t.Hint.Visible = true
	t.Hint.TextSize = 15
	place(t.Hint, 8, 122, w - 16, 20)
	place(t.Holder, 8, h - 52, w - 16, 44)
	place(t.Spin.Button, 0, 0, w - 16, 44)
	H.arrange(t.Spin, w - 16, 44, 18, 20)
end

function L.cardPortrait(t, w, h)
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
	place(P.Hero.Root, 0, 0, w, K.PORTRAIT_HERO)
	L.heroPortrait(P.Hero, w, K.PORTRAIT_HERO)
	local step = K.PORTRAIT_CARD + 8
	local rowH = #P.Cards * step - 8
	place(P.Row, 0, K.PORTRAIT_HERO + 8, w, rowH)
	P.Row.CanvasSize = UDim2.fromOffset(0, rowH) -- (no scroll of its own: the page scrolls)
	for i, t in ipairs(P.Cards) do
		place(t.Root, 0, (i - 1) * step, w, K.PORTRAIT_CARD)
		L.cardPortrait(t, w, K.PORTRAIT_CARD)
	end
	P.CanvasW = 0
	s.CanvasSize = UDim2.fromOffset(0, K.PORTRAIT_HERO + 8 + rowH + 8)
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
			k = s.AbsoluteSize.X / math.max(1, P.Box.W)
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
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
function ShopEggs.CardState(id, button)
	button = button or "Spin"
	if #H.odds(id) == 0 then
		return "NoOdds"
	end
	if EggStage.IsPending() then
		return "Pending"
	end
	local gems = id == K.SECRET or button == "SpinGems"
	if gems then
		if attr("PaidRandomItemsRestricted") ~= false then
			return "Locked"
		end
		if attr("GemsSettled") ~= true then
			return "Loading"
		end
	end
	local currency = gems and "Gems" or "Tokens"
	local price = H.price(id, currency) * ((button == "Spin3" and not gems) and 3 or 1)
	if H.balance(currency) < price then
		return "Short"
	end
	return "Ready"
end

function H.paintButton(p, id, name, priceText, short)
	local st = ShopEggs.CardState(id, name)
	p.Price.Text = priceText
	p.Price.TextColor3 = st == "Short" and K.RED or WHITE
	local stateText = nil
	if st == "Locked" then
		stateText = K.TEXT.Locked
	elseif st == "Loading" then
		stateText = short and K.TEXT.LoadingShort or K.TEXT.Loading
	end
	p.StateText = stateText
	p.Word.Text = stateText or p.BaseWord
	local off = st == "NoOdds" or st == "Pending" or st == "Locked" or st == "Loading"
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
		H.paintButton(t.Spin, t.Id, "Spin", Util.Commas(unit), short)
		H.paintButton(t.Spin3, t.Id, "Spin3", short and Theme.ShortNumber(3 * unit) or Util.Commas(3 * unit), short)
		H.paintButton(t.SpinGems, t.Id, "SpinGems", Util.Commas(H.price(t.Id, "Gems")), short)
	end
	local h = P.Hero
	h.Odds.Visible = h.HasOdds == true
	h.NoOdds.Visible = h.HasOdds ~= true
	H.paintButton(h.Spin, K.SECRET, "Spin", Util.Commas(H.price(K.SECRET, "Gems")), short)
	local restricted = attr("PaidRandomItemsRestricted")
	local locked = restricted ~= false
	local brief = P.Mode == "Phone" or P.Mode == "Portrait"
	h.Lock.Visible = locked
	h.Pity.Visible = not locked
	if locked then
		if restricted == true then
			h.Lock.Text = brief and K.TEXT.LockShort or K.TEXT.Lock
		else
			h.Lock.Text = brief and K.TEXT.CheckingShort or K.TEXT.Checking
		end
	else
		-- (Portrait: the long line while it fits the chip, else the phone's "Secret in N")
		local text = H.pityText(short)
		if P.Mode == "Portrait" and H.textW(text, h.Pity.TextSize, h.Pity.Font) + 16 > h.Pity.Size.X.Offset then
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
	t.Card.Stroke.Color = on and K.GOLD or t.Color
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
