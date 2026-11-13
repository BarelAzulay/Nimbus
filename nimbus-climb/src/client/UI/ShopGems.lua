-- ShopGems (client UI; lobby-shop Task 21, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.3 "Gems tab" and 16.1
-- "The packs, honest and computed"): the Shop's Gems page. ShopController builds it into its Page_Gems frame and lays it
-- out on every resize; this module never prompts a purchase or decides a price (every buy goes through ctx.Buy /
-- ctx.GemBuy, which fire StoreRequest; the server prompts).
--
--   ShopGems.Build(page, ctx)        page = the Page_Gems Frame. In it: a ScrollingFrame "Scroll" (GemHero, GemPack_1..4,
--                                    GemPotion, TokensTitle, TokenPack_1..3) and the phone's right "Fade" (48 px, shown while
--                                    more of the row is to the right). ctx (ShopController's): { Buy(key), GemBuy(),
--                                    Palette(key) -> { Top, Bottom, Edge }, Price(item) -> whole Robux | nil (the live
--                                    PriceInRobux of a created item), Robux() -> the Robux glyph, Preview() -> bool,
--                                    State(key) -> "Buy" | "Preview" | "Locked" | ..., LockText() -> string }
--   ShopGems.Layout(page, box, mode) box = { W, H } (the content box, design px); mode "PC" | "Compact" (the vertical page:
--                                    the hero 240, four packs 380 tall at (i * (w + 16), 276), the potion 130 at 676, "Cloud
--                                    Tokens" at 826 and three token packs 220 tall at 870) | "Phone" (one sideways row of eight
--                                    166 x min(266, H - 12) tiles every 174 px: the packs, the potion, the token packs; no
--                                    hero) | "Portrait" (the vertical list of full-width rows, the hero on top)
--   ShopGems.Refresh(page)           repaints the amounts, the prices, the ribbons, BEST VALUE, the hero's line, the potion
--                                    and the locks
--   ShopGems.PackRibbons(packs)      packs = { { Amount, Robux }... } (the prices SHOWN; Gems / Tokens are read when Amount is
--                                    missing) -> { [i] = "+N%" }: the whole percent of amount per Robux gained over the first
--                                    pack, rounded half up; none for the first pack, a pack without a shown price, or a gain
--                                    of zero or less
--   ShopGems.BestValue(packs)        -> the index with the most per Robux among the shown prices (ties: the bigger pack), nil
--                                    when that pack gains nothing over the first
--   ShopGems.ChestLine()             -> "Chest: 1,950 gems buys 3 Secret spins + 2 Celestial spins": n = floor(Chest / the
--                                    Secret Roulette's price), m = floor((Chest - n * Secret) / Celestial's gem price); the
--                                    "+ m ..." part dropped at m = 0 and the "n ... + " part at n = 0 (the hero pack's name
--                                    word, "Chest" from "Chest of Gems")
--   ShopGems.PotionState()           -> state, label: "Loading" "Loading..." (no GemsSettled), "Owned" "You have x2 Pet XP"
--                                    (XpPassState Owned), "Checking" "Checking your passes..." (any other state but NotOwned /
--                                    Unavailable), "Full" "Potion time is full" (XpBoostEnds plus the potion past
--                                    Config.Store.Potion.CapSeconds), "Short" (gems under the price: the price, drawn red),
--                                    "Ready" (the price). Only "Ready" may send StoreRequest("GemBuy", "XpPotionGems").
-- The tiles are NeonKit cards painted with each pack's own colours (ctx.Palette); gems are GemIcon piles, the tokens the
-- Cloud Token glyph. Every PC text >= 18 px, every phone text >= 15 px. Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local StoreCatalog = require(Shared:WaitForChild("StoreCatalog"))

local UI = script.Parent
local NeonKit = require(UI:WaitForChild("NeonKit"))
local GemIcon = require(UI:WaitForChild("GemIcon"))
local CloudUI = require(UI:WaitForChild("CloudUI"))

local ShopGems = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local K = {
	POTION_KEY = "XpPotionGems",
	HERO_INDEX = 3, -- the Chest (StoreCatalog's GEM_HERO_INDEX)
	PILES = { 1, 2, 4, 6 },
	TOKEN_ART = { 1, 3, 6 },
	TEAL = rgb(64, 200, 190),
	POTION = rgb(176, 108, 232),
	LINE = rgb(255, 243, 176),
	RED = rgb(255, 92, 92),
	GOLD = rgb(255, 211, 77),
	RIBBON = rgb(230, 60, 90),
	TILE = 166, -- the phone row
	STEP = 174,
	TILE_MAX = 266,
	FADE = 48,
	SCROLLBAR = 6,
	-- the pitch's PILE shares (GemIcon's), reused for the token art
	SPOTS = {
		[1] = { { 0.5, 0.55, 0.8 } },
		[3] = { { 0.3, 0.64, 0.6 }, { 0.7, 0.64, 0.6 }, { 0.5, 0.4, 0.7 } },
		[6] = { { 0.2, 0.72, 0.46 }, { 0.5, 0.74, 0.5 }, { 0.8, 0.72, 0.46 }, { 0.34, 0.5, 0.5 }, { 0.66, 0.5, 0.5 }, { 0.5, 0.27, 0.56 } },
	},
}
local WHITE = Color3.new(1, 1, 1)
local PAGES = setmetatable({}, { __mode = "k" }) -- page -> its widgets and ctx

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

-- the largest size from `max` down to `min` at which `text` fits `width` px on one line (TextService measures the font)
local function fitSize(lbl, max, min, width)
	for size = max, min, -1 do
		local ok, v = pcall(function()
			return Theme.MeasureLabel(lbl, lbl.Text, size, 10000)
		end)
		if not ok or typeof(v) ~= "Vector2" or v.X <= width then
			return size
		end
	end
	return min
end

local function attr(name)
	local player = Players.LocalPlayer
	return player and player:GetAttribute(Config.Attr[name] or name) or nil
end

local function now()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return (ok and type(t) == "number") and t or os.time()
end

-- a GemIcon pile (count) or the Cloud Token glyphs (tokens) in `host`, rebuilt only when its size changes
local function drawArt(host, px, count, tokens)
	px = math.max(16, math.floor(px + 0.5))
	if host:GetAttribute("ArtPx") == px then
		return
	end
	host:SetAttribute("ArtPx", px)
	for _, child in ipairs(host:GetChildren()) do
		child:Destroy()
	end
	if not tokens then
		local pile = GemIcon.Pile(host, px, count)
		pile.AnchorPoint = Vector2.new(0.5, 0.5)
		pile.Position = UDim2.fromScale(0.5, 0.5)
		return
	end
	local box = frame("TokenPile", host, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(px, px) })
	local cur = Theme.Currency.Tokens
	for i, spot in ipairs(K.SPOTS[count] or K.SPOTS[1]) do
		local s = math.floor(spot[3] * px)
		local g = label("Token" .. i, box, cur.Glyph, "Display", math.max(15, math.floor(s * 0.82)), {
			TextColor3 = cur.Color, TextTruncate = Enum.TextTruncate.None,
		})
		place(g, spot[1] * px - s / 2, spot[2] * px - s / 2, s, s)
	end
end

local function itemsByKey()
	local out = {}
	for _, item in ipairs(StoreCatalog.List()) do
		out[item.Key] = item
	end
	return out
end

local function amountOf(p)
	return tonumber(p.Amount) or tonumber(p.Gems) or tonumber(p.Tokens) or (type(p.Grants) == "table" and (tonumber(p.Grants.Gems) or tonumber(p.Grants.Tokens))) or nil
end

local function ratios(packs)
	local out = {}
	for i, p in ipairs(packs or {}) do
		local amount, robux = amountOf(p), tonumber(p.Robux)
		if amount and robux and robux > 0 then
			out[i] = amount / robux
		end
	end
	return out
end

----------------------------------------------------------------------
-- pure answers
----------------------------------------------------------------------
function ShopGems.PackRibbons(packs)
	local out = {}
	local r = ratios(packs)
	local base = r[1]
	if not base then
		return out
	end
	for i = 2, #(packs or {}) do
		if r[i] then
			local pct = math.floor((r[i] / base - 1) * 100 + 0.5)
			if pct > 0 then
				out[i] = "+" .. tostring(pct) .. "%"
			end
		end
	end
	return out
end

function ShopGems.BestValue(packs)
	local r = ratios(packs)
	local best = nil
	for i = 1, #(packs or {}) do
		if r[i] and (best == nil or r[i] > r[best] + 1e-9 or (math.abs(r[i] - r[best]) <= 1e-9 and (amountOf(packs[i]) or 0) >= (amountOf(packs[best]) or 0))) then
			best = i
		end
	end
	if best == nil or best == 1 or not r[1] or r[best] <= r[1] + 1e-9 then
		return nil
	end
	return best
end

function ShopGems.ChestLine()
	local products = type(Config.Gems) == "table" and Config.Gems.Products or {}
	local chest = products[K.HERO_INDEX] or {}
	local gems = tonumber(chest.Gems) or 0
	local secret = tonumber(Config.Gems.SecretRoulette and Config.Gems.SecretRoulette.GemPrice) or 0
	local celestial = tonumber(Config.Gems.RouletteGemPrices and Config.Gems.RouletteGemPrices.Celestial) or 0
	local word = type(chest.Name) == "string" and (chest.Name:match("^(%S+) of ") or chest.Name) or "Chest"
	local n = secret > 0 and math.floor(gems / secret) or 0
	local m = celestial > 0 and math.floor((gems - n * secret) / celestial) or 0
	local parts = {}
	if n > 0 then
		parts[#parts + 1] = n .. (n == 1 and " Secret spin" or " Secret spins")
	end
	if m > 0 then
		parts[#parts + 1] = m .. (m == 1 and " Celestial spin" or " Celestial spins")
	end
	local line = word .. ": " .. Util.Commas(gems) .. " gems"
	if #parts > 0 then
		line = line .. " buys " .. table.concat(parts, " + ")
	end
	return line
end

function ShopGems.PotionState()
	local item = StoreCatalog.GemItem(K.POTION_KEY)
	local price = item and tonumber(item.Gems) or 0
	local priceText = Util.Commas(price)
	if attr("GemsSettled") ~= true then
		return "Loading", "Loading..."
	end
	local pass = attr("XpPassState")
	if pass == "Owned" then
		return "Owned", "You have x2 Pet XP"
	end
	if pass ~= "NotOwned" and pass ~= "Unavailable" then
		return "Checking", "Checking your passes..."
	end
	local boost = item and type(item.Grants) == "table" and type(item.Grants.Boost) == "table" and tonumber(item.Grants.Boost.XpPotion) or 1800
	local potion = type(Config.Store) == "table" and Config.Store.Potion or nil
	local cap = (type(potion) == "table" and tonumber(potion.CapSeconds)) or 7 * 86400
	local left = math.max(0, (tonumber(attr("XpBoostEnds")) or 0) - now())
	if left + boost > cap then
		return "Full", "Potion time is full"
	end
	local gems = tonumber(attr("Gems")) or 0
	if gems < price then
		return "Short", priceText
	end
	return "Ready", priceText
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
local function call(P, name, ...)
	local fn = P.Ctx[name]
	if type(fn) == "function" then
		local ok, a = pcall(fn, ...)
		if ok then
			return a
		end
	end
	return nil
end

local function newButton(P, parent, onTap, style)
	return CloudUI.Button({
		Name = "Buy",
		Text = "",
		Style = style or "Green",
		Size = UDim2.fromOffset(200, 60),
		TextSize = 24,
		Callback = function()
			onTap()
		end,
		Parent = parent,
	})
end

local function card(name, parent, color, fill)
	local c = NeonKit.Card({ Name = name, Color = color, Fill = fill, Floor = false, Size = UDim2.fromOffset(298, 380), Parent = parent })
	return c
end

-- a pack tile (gems or tokens): Art, Amount, Name, Ribbon (gems only), Best, Note, Buy
local function buildTile(P, kind, i)
	local key = (kind == "Gem" and "Gems" or "Tokens") .. i
	local pal = call(P, "Palette", key) or { Top = K.TEAL, Bottom = Theme.Darken(K.TEAL, 0.6), Edge = Theme.Lighten(K.TEAL, 0.3) }
	local c = card((kind == "Gem" and "GemPack_" or "TokenPack_") .. i, P.Scroll, pal.Edge, { pal.Top, pal.Bottom })
	local b = c.Body
	local t = { Kind = kind, Index = i, Key = key, Root = c.Root, Card = c }
	t.Art = frame("Art", b)
	t.Amount = label("Amount", b, "", "Display", 44)
	t.Name = label("Name", b, "", "Body", 21)
	t.Ribbon = label("Ribbon", b, "", "Body", 20, { BackgroundTransparency = 0, BackgroundColor3 = K.RIBBON, Visible = false })
	Theme.Corner(t.Ribbon, UDim.new(0, 8))
	t.Best = label("Best", b, "BEST VALUE", "Body", 18, { BackgroundTransparency = 0, BackgroundColor3 = Theme.Darken(K.GOLD, 0.25), Visible = false })
	Theme.Corner(t.Best, UDim.new(0, 8))
	Theme.Stroke(t.Best, K.GOLD, 2, 0)
	t.Note = label("Note", b, "", "Body", 18, { TextColor3 = K.LINE, Visible = false, TextWrapped = true, TextTruncate = Enum.TextTruncate.None })
	t.Buy = newButton(P, b, function()
		call(P, "Buy", key)
	end)
	return t
end

local function buildHero(P)
	local c = card("GemHero", P.Scroll, K.TEAL, { Theme.Darken(K.TEAL, 0.35), Theme.Darken(K.TEAL, 0.75) })
	local b = c.Body
	local h = { Root = c.Root, Card = c, Key = "Gems" .. K.HERO_INDEX }
	h.Pile = frame("Pile", b)
	h.Title = label("Title", b, "Gems", "Title", 46, { TextXAlignment = Enum.TextXAlignment.Left })
	h.Line1 = label("Line1", b, "Spin the Secret Roulette and every machine with gems.", "Body", 24, { TextXAlignment = Enum.TextXAlignment.Left })
	h.Line2 = label("Line2", b, "", "Heading", 24, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = K.LINE })
	h.Note = label("Note", b, "", "Body", 18, { TextColor3 = K.LINE, Visible = false })
	h.Buy = newButton(P, b, function()
		call(P, "Buy", h.Key)
	end)
	return h
end

local function buildPotion(P)
	local c = card("GemPotion", P.Scroll, K.POTION, { Theme.Darken(K.POTION, 0.35), Theme.Darken(K.POTION, 0.75) })
	local b = c.Body
	local p = { Root = c.Root, Card = c }
	p.Icon = label("Icon", b, NeonKit.Glyphs.Boosts, "Display", 64, { TextTruncate = Enum.TextTruncate.None })
	p.Title = label("Title", b, "XP Potion \194\183 30 minutes", "Title", 32, { TextXAlignment = Enum.TextXAlignment.Left })
	p.Text = label("Text", b, "Your team earns double pet XP. Not random, so every account can buy it.", "Body", 22,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextColor3 = Theme.Colors.Muted or WHITE })
	p.Buy = newButton(P, b, function()
		call(P, "GemBuy")
	end, "Blue")
	p.Buy.TextWrapped = true
	p.Amount = GemIcon.Amount(p.Buy, "0", { TextSize = 30 })
	p.Amount.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Amount.Position = UDim2.fromScale(0.5, 0.5)
	return p
end

function ShopGems.Build(page, ctx)
	local P = { Ctx = type(ctx) == "table" and ctx or {}, Packs = {}, Tokens = {}, Mode = "PC", Box = { W = 1240, H = 834 } }
	PAGES[page] = P
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = K.SCROLLBAR
	scroll.CanvasSize = UDim2.new()
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.Parent = page
	P.Scroll = scroll
	local fade = frame("Fade", page, { BackgroundTransparency = 0, BackgroundColor3 = Theme.Colors.PanelBottom or rgb(12, 15, 38), Visible = false, ZIndex = 6 })
	Util.Create("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.08) }),
		Parent = fade,
	})
	P.Fade = fade
	P.Hero = buildHero(P)
	for i = 1, #(Config.Gems.Products or {}) do
		P.Packs[i] = buildTile(P, "Gem", i)
	end
	P.Potion = buildPotion(P)
	P.TokensTitle = label("TokensTitle", scroll, "Cloud Tokens", "Heading", 26, { TextXAlignment = Enum.TextXAlignment.Left })
	for i = 1, 3 do
		P.Tokens[i] = buildTile(P, "Token", i)
	end
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		ShopGems._SyncFade(page)
	end)
	ShopGems.Refresh(page)
	return P
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
-- one tile on the PC / Compact page (w x h)
local function layoutTilePC(t, w, h)
	if t.Kind == "Gem" then
		place(t.Best, 12, 10, 140, 38)
		t.Best.TextSize = 18
		place(t.Ribbon, w - 92, 10, 80, 38)
		t.Ribbon.TextSize = 20
		place(t.Art, (w - 140) / 2, 50, 140, 140)
		drawArt(t.Art, 140, K.PILES[t.Index] or 6, false)
		place(t.Amount, 0, 192, w, 46)
		t.Amount.TextSize = 44
		place(t.Name, 8, 236, w - 16, 26)
		t.Name.TextSize = 21
		place(t.Note, 8, 262, w - 16, 26)
		t.Note.TextSize = 18
		place(t.Buy, 20, h - 88, w - 40, 68)
		t.Buy.TextSize = 30
	else
		local col = 148
		place(t.Best, 12, 10, 140, 34)
		t.Best.TextSize = 18
		place(t.Art, 16, 52, 120, 120)
		drawArt(t.Art, 120, K.TOKEN_ART[t.Index] or 6, true)
		place(t.Amount, col, 10, w - col - 12, 46)
		t.Amount.TextSize = 40
		place(t.Name, col, 56, w - col - 12, 26)
		t.Name.TextSize = 20
		place(t.Note, col, 84, w - col - 12, 58)
		t.Note.TextSize = 18
		place(t.Buy, col, h - 72, w - col - 16, 64)
		t.Buy.TextSize = 26
	end
	t.Amount.TextXAlignment = t.Kind == "Gem" and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
	t.Name.TextXAlignment = t.Amount.TextXAlignment
	t.Note.TextXAlignment = t.Amount.TextXAlignment
end

-- a phone tile (166 x h): the badges on top, the art, the amount, the name, the note, the Buy at the bottom
local function layoutTilePhone(t, w, h)
	place(t.Best, 6, 6, 100, 26)
	t.Best.TextSize = 15
	place(t.Ribbon, w - 58, 6, 52, 26)
	t.Ribbon.TextSize = 15
	local artTop, artBottom = 34, h - 152
	local art = math.max(40, math.min(72, artBottom - artTop - 4))
	place(t.Art, (w - art) / 2, artTop + math.max(0, (artBottom - artTop - art) / 2), art, art)
	drawArt(t.Art, art, t.Kind == "Gem" and (K.PILES[t.Index] or 6) or (K.TOKEN_ART[t.Index] or 6), t.Kind ~= "Gem")
	place(t.Amount, 0, h - 150, w, 30)
	t.Amount.TextSize = 26
	place(t.Name, 4, h - 120, w - 8, 20)
	t.Name.TextSize = 15
	place(t.Note, 4, h - 99, w - 8, 48)
	t.Note.TextSize = 15
	place(t.Buy, 8, h - 50, w - 16, 44)
	t.Buy.TextSize = 18
	for _, l in ipairs({ t.Amount, t.Name, t.Note }) do
		l.TextXAlignment = Enum.TextXAlignment.Center
	end
end

-- a portrait row (w x h): the art left, the amount and name beside it, the badges under them, the Buy top right, the note
-- across the bottom
local function layoutTilePortrait(t, w, h)
	place(t.Art, 8, 8, 64, 64)
	drawArt(t.Art, 64, t.Kind == "Gem" and (K.PILES[t.Index] or 6) or (K.TOKEN_ART[t.Index] or 6), t.Kind ~= "Gem")
	local tw = w - 80 - 120
	place(t.Amount, 80, 6, tw, 30)
	t.Amount.TextSize = 24
	place(t.Name, 80, 36, tw, 20)
	t.Name.TextSize = 15
	place(t.Ribbon, 80, 60, 52, 24)
	t.Ribbon.TextSize = 15
	place(t.Best, t.Ribbon.Visible and 138 or 80, 60, 100, 24)
	t.Best.TextSize = 15
	place(t.Buy, w - 112, 8, 104, 44)
	t.Buy.TextSize = 18
	place(t.Note, 8, 88, w - 16, h - 92)
	t.Note.TextSize = 15
	for _, l in ipairs({ t.Amount, t.Name, t.Note }) do
		l.TextXAlignment = Enum.TextXAlignment.Left
	end
end

local function layoutHero(h, w, mode)
	if mode == "Portrait" then
		place(h.Root, 0, 0, w, 150)
		place(h.Pile, 8, 8, 80, 80)
		drawArt(h.Pile, 80, 6, false)
		place(h.Title, 100, 6, w - 108, 30)
		h.Title.TextSize = 24
		h.Line1.Visible = false
		place(h.Line2, 100, 38, w - 108, 52)
		h.Line2.TextSize = 15
		h.Line2.TextWrapped = true
		place(h.Buy, w - 158, 98, 150, 44)
		h.Buy.TextSize = 18
		place(h.Note, 8, 104, w - 182, 34)
		h.Note.TextSize = 15
		return 150
	end
	place(h.Root, 0, 16, w, 240)
	place(h.Pile, 30, 20, 200, 200)
	drawArt(h.Pile, 200, 6, false)
	local tw = w - 250 - 340
	place(h.Title, 250, 22, tw, 56)
	h.Title.TextSize = 46
	h.Line1.Visible = true
	place(h.Line1, 250, 84, tw, 34)
	h.Line1.TextSize = fitSize(h.Line1, 24, 18, tw)
	place(h.Line2, 250, 128, tw, 40)
	h.Line2.TextWrapped = false
	h.Line2.TextSize = fitSize(h.Line2, 24, 18, tw)
	place(h.Buy, w - 320, 66, 290, 100)
	h.Buy.TextSize = 36
	place(h.Note, w - 320, 172, 290, 30)
	h.Note.TextSize = 18
	return 256
end

local function layoutPotion(p, w, h, mode)
	local amountSize
	if mode == "PC" or mode == "Compact" then
		place(p.Icon, 24, 17, 96, 96)
		p.Icon.TextSize = 64
		local tw = w - 140 - 320
		place(p.Title, 140, 18, tw, 44)
		p.Title.Text = "XP Potion \194\183 30 minutes"
		p.Title.TextSize = 32
		place(p.Text, 140, 64, tw, 52)
		p.Text.Text = "Your team earns double pet XP. Not random, so every account can buy it."
		p.Text.TextSize = 22
		place(p.Buy, w - 300, 26, 270, 78)
		p.Buy.TextSize = 22
		amountSize = 30
	elseif mode == "Phone" then
		local artBottom = h - 152
		local art = math.max(40, math.min(72, artBottom - 34 - 4))
		place(p.Icon, (w - art) / 2, 34 + math.max(0, (artBottom - 34 - art) / 2), art, art)
		p.Icon.TextSize = math.floor(art * 0.8)
		place(p.Title, 4, h - 150, w - 8, 30)
		p.Title.Text = "XP Potion"
		p.Title.TextSize = 17
		place(p.Text, 4, h - 118, w - 8, 40)
		p.Text.Text = "30 min \194\183 x2 pet XP"
		p.Text.TextSize = 15
		place(p.Buy, 8, h - 50, w - 16, 44)
		p.Buy.TextSize = 15
		amountSize = 18
	else
		place(p.Icon, 8, 8, 64, 64)
		p.Icon.TextSize = 48
		local tw = w - 80 - 120
		place(p.Title, 80, 6, tw, 26)
		p.Title.Text = "XP Potion"
		p.Title.TextSize = 17
		place(p.Text, 80, 34, tw, 40)
		p.Text.Text = "30 min \194\183 x2 pet XP"
		p.Text.TextSize = 15
		place(p.Buy, w - 112, 8, 104, 44)
		p.Buy.TextSize = 15
		amountSize = 18
	end
	local centred = mode == "Phone"
	p.Title.TextXAlignment = centred and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
	p.Text.TextXAlignment = p.Title.TextXAlignment
	GemIcon.SetAmount(p.Amount, nil, { TextSize = amountSize })
end

-- the phone's right fade: shown while more of the sideways row is to the right
function ShopGems._SyncFade(page)
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

function ShopGems.Layout(page, box, mode)
	local P = PAGES[page]
	if not P then
		return
	end
	box = type(box) == "table" and box or P.Box
	P.Box = { W = math.floor(tonumber(box.W) or 1240), H = math.floor(tonumber(box.H) or 834) }
	P.Mode = mode or "PC"
	local W, Hh = P.Box.W, P.Box.H
	local s = P.Scroll
	place(s, 0, 0, W, Hh)
	place(P.Fade, W - K.FADE, 0, K.FADE, Hh)
	local hero = P.Hero
	if P.Mode == "Phone" then
		s.ScrollingDirection = Enum.ScrollingDirection.X
		hero.Root.Visible = false
		P.TokensTitle.Visible = false
		local th = math.min(K.TILE_MAX, Hh - 12)
		local y = math.floor((Hh - th) / 2)
		local row = {}
		for _, t in ipairs(P.Packs) do
			row[#row + 1] = t
		end
		row[#row + 1] = P.Potion
		for _, t in ipairs(P.Tokens) do
			row[#row + 1] = t
		end
		local x = 0
		for _, t in ipairs(row) do
			if t.Root.Visible then
				place(t.Root, x, y, K.TILE, th)
				if t == P.Potion then
					layoutPotion(t, K.TILE, th, "Phone")
				else
					layoutTilePhone(t, K.TILE, th)
				end
				x = x + K.STEP
			end
		end
		P.CanvasW = math.max(0, x - (K.STEP - K.TILE))
		s.CanvasSize = UDim2.fromOffset(P.CanvasW, 0)
	elseif P.Mode == "Portrait" then
		s.ScrollingDirection = Enum.ScrollingDirection.Y
		hero.Root.Visible = true
		P.TokensTitle.Visible = true
		local w = W - K.SCROLLBAR - 2
		local y = layoutHero(hero, w, "Portrait") + 8
		for _, t in ipairs(P.Packs) do
			if t.Root.Visible then
				place(t.Root, 0, y, w, 124)
				layoutTilePortrait(t, w, 124)
				y = y + 132
			end
		end
		place(P.Potion.Root, 0, y, w, 96)
		layoutPotion(P.Potion, w, 96, "Portrait")
		y = y + 104
		place(P.TokensTitle, 4, y, w - 8, 30)
		P.TokensTitle.TextSize = 20
		y = y + 34
		for _, t in ipairs(P.Tokens) do
			if t.Root.Visible then
				place(t.Root, 0, y, w, 124)
				layoutTilePortrait(t, w, 124)
				y = y + 132
			end
		end
		P.CanvasW = 0
		s.CanvasSize = UDim2.fromOffset(0, y)
	else
		s.ScrollingDirection = Enum.ScrollingDirection.Y
		hero.Root.Visible = true
		P.TokensTitle.Visible = true
		-- (the content stops short of the scroll bar, as on the card pages: the bar never covers the last tile's edge)
		local cw = W - K.SCROLLBAR - 2
		layoutHero(hero, cw, P.Mode)
		local pw = math.floor((cw - 48) / 4)
		for i, t in ipairs(P.Packs) do
			place(t.Root, (i - 1) * (pw + 16), 276, pw, 380)
			layoutTilePC(t, pw, 380)
		end
		place(P.Potion.Root, 0, 676, cw, 130)
		layoutPotion(P.Potion, cw, 130, P.Mode)
		place(P.TokensTitle, 4, 826, cw - 8, 34)
		P.TokensTitle.TextSize = 26
		local tw = math.floor((cw - 16) / 3)
		for i, t in ipairs(P.Tokens) do
			place(t.Root, (i - 1) * (tw + 8), 870, tw, 220)
			layoutTilePC(t, tw, 220)
		end
		P.CanvasW = 0
		s.CanvasSize = UDim2.fromOffset(0, 870 + 220 + 16)
	end
	ShopGems._SyncFade(page)
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
-- the price SHOWN for an item: the live PriceInRobux once created (nil while it loads), else the Config Robux
local function shownPrice(P, item)
	if not item then
		return nil
	end
	if item.Created then
		return call(P, "Price", item)
	end
	return tonumber(item.Robux)
end

local function paintTile(P, t, item, best)
	t.Root.Visible = item ~= nil
	if not item then
		return
	end
	local amount = amountOf(item) or 0
	t.Amount.Text = Util.Commas(amount)
	t.Name.Text = tostring(item.Name or item.Key)
	local price = shownPrice(P, item)
	t.Buy.Text = price and ((call(P, "Robux") or "R$") .. Util.Commas(price)) or "..."
	local state = call(P, "State", t.Key) or "Preview"
	local note = ""
	if state == "Preview" then
		note = call(P, "Preview") and "PREVIEW" or "Coming soon"
	elseif state == "Locked" then
		note = tostring(call(P, "LockText") or "")
	end
	t.Note.Text = note
	t.Note.Visible = note ~= ""
	local off = state ~= "Buy"
	if (t.Buy:GetAttribute("Disabled") == true) ~= off then
		CloudUI.SetDisabled(t.Buy, off)
	end
	t.Best.Visible = best == t.Index
end

function ShopGems.Refresh(page)
	local P = PAGES[page]
	if not P then
		return
	end
	local items = itemsByKey()
	-- the gem packs: the shown prices -> the ribbons and BEST VALUE
	local shown = {}
	for i = 1, #P.Packs do
		local item = items["Gems" .. i]
		shown[i] = { Amount = item and amountOf(item) or 0, Robux = shownPrice(P, item) }
	end
	local ribbons = ShopGems.PackRibbons(shown)
	local best = ShopGems.BestValue(shown)
	for i, t in ipairs(P.Packs) do
		paintTile(P, t, items[t.Key], best)
		t.Ribbon.Text = ribbons[i] or ""
		t.Ribbon.Visible = ribbons[i] ~= nil
	end
	-- the token packs: BEST VALUE only (no % ribbon: spec 16.1)
	local tshown = {}
	for i = 1, #P.Tokens do
		local item = items["Tokens" .. i]
		tshown[i] = { Amount = item and amountOf(item) or 0, Robux = shownPrice(P, item) }
	end
	local tbest = ShopGems.BestValue(tshown)
	for _, t in ipairs(P.Tokens) do
		paintTile(P, t, items[t.Key], tbest)
		t.Ribbon.Visible = false
	end
	-- the hero: the Chest's line and buy
	local hero = P.Hero
	local chestTile = P.Packs[K.HERO_INDEX]
	hero.Line2.Text = ShopGems.ChestLine()
	if chestTile then
		hero.Buy.Text = chestTile.Buy.Text
		hero.Note.Text = chestTile.Note.Text
		hero.Note.Visible = chestTile.Note.Visible
		local off = chestTile.Buy:GetAttribute("Disabled") == true
		if (hero.Buy:GetAttribute("Disabled") == true) ~= off then
			CloudUI.SetDisabled(hero.Buy, off)
		end
	end
	-- the potion
	local p = P.Potion
	local state, text = ShopGems.PotionState()
	local priced = state == "Ready" or state == "Short"
	p.Amount.Visible = priced
	if priced then
		p.Buy.Text = ""
		GemIcon.SetAmount(p.Amount, text, { Color = state == "Short" and K.RED or WHITE })
	else
		p.Buy.Text = text
	end
	local off = not priced
	if (p.Buy:GetAttribute("Disabled") == true) ~= off then
		CloudUI.SetDisabled(p.Buy, off)
	end
end

return ShopGems
