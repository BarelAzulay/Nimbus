-- StoreController (client, store W1 Task 7; docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.1 / 8 / 13b): the
-- full-size Robux Store window (packs, passes, potions, Tokens and Gems).
--
--   StoreController.Init()
--   StoreController.Open(args)    args = { Tab = one of StoreCatalog.Tabs } | nil. Refused while InMatch (the side hint
--                                 "The Store is closed during a match."); Tab = "Roulettes" hops to the Cloud Shop
--   StoreController.Close()
--   StoreController.IsOpen() -> bool
--   StoreController.Layout() -> "PC" | "Phone"
--   StoreController.Cards() -> { [key] = { State, Price, Tab } }   every card shown (tests)
--   StoreController.RobuxGlyph() -> string   "\238\128\130" (U+E002, the Robux glyph) or "R$" when the font lacks it
--
-- Who opens it: the top bar pill's Shop button (TopBarController), the Cloud Shop's "Robux Store" button and a server
-- OpenPanel("Store", args): both through MenuController's P5.openStore (ONE OpenPanel listener: this controller never
-- connects OpenPanel, or the window would open twice). An opening fires MenuController.WindowOpened("Store") (the menu
-- closes its windows, the Pet Index and the Pets window on it); this window closes on any other WindowOpened id, on
-- Esc / gamepad B / its X, on InMatch and on MenuController.Close().
--
-- Screen: ScreenGui "NimbusStore" (DisplayOrder 19, IgnoreGuiInset = true), Frame "StoreWindow" sized like the Pets
-- window (NeonKit.BigRect: 1260x900 at 1080p x ScreenFactor, 820x330 at scale 1 on an 844x390 phone) with a UIScale "Fit".
--   TitleBar: Title "Store", the three balances Balance_Tokens / Balance_Cash / Balance_Gems, Close (X).
--   Tabs: Tab_<name> (Icon + Label; attribute Selected) for Packs, Passes, Boosts, Currency, Roulettes. A tab with no item
--     to show is hidden; Roulettes always shows and closes the Store for MenuController.Open("Shop").
--   Pages: Page_<tab> ScrollingFrames of Card_<key> (NeonKit.Card TextButtons: Art, Name, GetsYou, Line1..n, Status,
--     PricePill.Text, Buy). The tab's hero card (attribute Hero) comes first and is taller. "Soon" reads "The Store opens
--     soon!" when nothing is created (and no StorePreview).
-- Items: StoreCatalog.List() (Config.Store.Items + the gem packs), shown when created (Id > 0) or under the StorePreview
-- attribute (then an Id 0 item is a "Preview" card: its Buy reads PREVIEW, disabled). The window hero is the Starter Pack
-- while it is unbought and shown, else VIP; another tab's hero is its first Hero item not owned / claimed.
-- Card states: Buy, Owned (a pass key in OwnedPasses), Claimed (a Once key in StoreBought), Active (an XP potion while
-- XpBoostEnds > now: "58 m left"), HaveIt (an XP potion while the x2 Pet XP pass is owned or the potion bank is full:
-- dimmed), Preview. Buy -> StoreRequest:FireServer("Buy", key) (1 s client gap): the client never prompts a purchase.
-- Prices: MarketplaceService:GetProductInfo once per session per created id, in the background, one retry after
-- Config.Store.PriceRetrySeconds; "..." meanwhile (Buy never waits for it).
-- Shine (GraphicsQuality High only, built on open, torn down on close): the hero's UIGradient "HeroSpin" turns 360
-- degrees every 8 s (a Heartbeat step), a sheen sweeps the hero every 6-9 s, the hero's Buy pulses (1 -> 1.04) every
-- 2.5 s, pet cards show a turning CloudUI.PetViewport. Low: a static gradient and the glyph art, no tweens.
-- Sounds: StorePop on a card tap (Click until AudioIds has it), StoreBuy on the server's "Thank you..." toast (Reward).
-- Art: the glyph of each item (the store_* renders of spec 9 need a TextureIds image path this file may not build: the
-- asset-id rule of tools/check.mjs; the glyphs stay until the art lands).
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles; no asset ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoreCatalog = require(Shared:WaitForChild("StoreCatalog"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))
local State = require(Client:WaitForChild("State"))
local SoundFx = require(Client:WaitForChild("SoundFx"))

local StoreController = {}

local K = {
	DISPLAY_ORDER = 19,
	-- the window box (NeonKit.BigRect; the Pets window's numbers)
	RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1260, Y1 = 900 },
	MARGIN = 12,
	PHONE_W = 900,
	SHORT = 560,
	PC_MIN_H = 600,
	PC_MAX_W = 0.76,
	BUY_GAP = 1, -- seconds between two Buy sends
	TICK = 1, -- seconds between two refreshes while open (the potion's time left)
	BACK_ACTION = "NimbusStoreBack",
	SPIN_SECONDS = 8, -- the hero gradient's turn
	SHEEN_MIN = 6,
	SHEEN_MAX = 9,
	SHEEN_TIME = 0.9,
	PULSE_EVERY = 2.5,
	PULSE_SCALE = 1.04,
	ROBUX_GLYPH = "\238\128\130", -- U+E002
	ROBUX_FALLBACK = "R$",
	MATCH_HINT = "The Store is closed during a match.",
	SOON = "The Store opens soon!",
	SCROLLBAR = 6,
	-- design px per layout (spec 8 "Store")
	PHONE = {
		Title = 44, TitleText = 24, PillW = 72, PillH = 28, PillText = 16, Close = 44,
		TabX = 10, TabY = 52, TabW = 92, TabH = 42, TabGap = 8, TabIcon = 20, TabLabel = 15,
		ScrollX = 110, Gap = 8, Hero = 150, Card = 108, Art = 120, Pad = 8,
		Name = 24, Line = 16, Status = 15, Price = 20, BuyW = 150, BuyH = 48, BuyText = 20, Soon = 20,
	},
	PC = {
		Title = 60, TitleText = 36, PillW = 130, PillH = 40, PillText = 22, Close = 52,
		TabX = 14, TabY = 72, TabW = 180, TabH = 72, TabGap = 12, TabIcon = 30, TabLabel = 22,
		ScrollX = 210, Gap = 12, Hero = 250, Card = 150, Art = 210, Pad = 14,
		Name = 32, Line = 22, Status = 20, Price = 28, BuyW = 220, BuyH = 60, BuyText = 26, Soon = 30,
	},
}

local Colors = Theme.Colors
local WHITE = Colors.White
local MUTED = Colors.Muted or Colors.CloudShade
local GOLD = Theme.Neon.Gold
local TAB_COLORS = { Packs = "Gold", Passes = "Purple", Boosts = "Pink", Currency = "Blue", Roulettes = "Green" }
local CURRENCY_ORDER = { "Tokens", "Cash", "Gems" }
local CLOSE_GLYPH = "\226\156\149"

local initialized = false
local LocalPlayer = nil
local U = { Tabs = {}, Pages = {}, Cards = {}, Pills = {} } -- widgets
local S = {
	Open = false,
	Built = false,
	Token = 0,
	Tab = nil,
	Mode = "PC",
	Scale = 1,
	Rect = nil,
	Items = {}, -- the items shown, in catalog order
	ByKey = {},
	Signature = nil,
	States = {}, -- key -> { State, Status }
	Prices = {}, -- id -> whole Robux
	Asked = {}, -- id -> true once asked this session
	LastBuy = 0,
	Glyph = nil,
	TouchOff = false,
	BackBound = false,
	Shine = nil, -- { Tweens, Conn, Parts } while the shine runs
	Warned = {},
}
local H = {}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[StoreController] " .. tostring(key) .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		warnOnce(key, a)
	end
	return ok, a, b
end

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

local function csvSet(value)
	local out = {}
	if type(value) == "string" then
		for key in string.gmatch(value, "[^,%s]+") do
			out[key] = true
		end
	end
	return out
end

local function now()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.time()
end

function H.controller(name)
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

function H.quality()
	local module = Client:FindFirstChild("GraphicsQuality")
	local ok, mod = pcall(function()
		return module and require(module)
	end)
	if ok and type(mod) == "table" and type(mod.Effective) == "function" then
		local okQ, q = pcall(mod.Effective)
		if okQ and q == "Low" then
			return "Low"
		end
	end
	return "High"
end

function H.hint(message)
	local menu = H.controller("MenuController")
	if menu and type(menu.Hint) == "function" then
		safe("hint", menu.Hint, message, "info")
	end
end

function H.inMatch()
	return LocalPlayer ~= nil and LocalPlayer:GetAttribute(Config.Attr.InMatch) == true
end

function H.attr(name)
	return LocalPlayer and LocalPlayer:GetAttribute(Config.Attr[name] or name) or nil
end

function H.remote(name)
	local ok, remote = pcall(Remotes.Get, name)
	return ok and remote or nil
end

-- the sound of `key` when AudioIds has it, else the fallback (spec 5.1)
local function sfx(key, fallback)
	safe("sfx", function()
		SoundFx.Play(SoundFx.Id("Sfx", key) and key or fallback)
	end)
end

-- decided once on Init: the font draws the Robux glyph (wider than 2 px) or the text says "R$"
local function robuxGlyph()
	if S.Glyph then
		return S.Glyph
	end
	local ok, size = pcall(function()
		return TextService:GetTextSize(K.ROBUX_GLYPH, 20, Theme.Fonts.Display, Vector2.new(1000, 100))
	end)
	if ok and typeof(size) == "Vector2" and size.X > 2 then
		S.Glyph = K.ROBUX_GLYPH
	else
		S.Glyph = K.ROBUX_FALLBACK
	end
	return S.Glyph
end

----------------------------------------------------------------------
-- What is shown
----------------------------------------------------------------------
function H.preview()
	return H.attr("StorePreview") == true
end

-- the items shown (created, or every one under StorePreview), the Roulettes tab never has items
function H.collect()
	local preview = H.preview()
	local items, byKey, sig = {}, {}, { preview and "P" or "-" }
	for _, item in ipairs(StoreCatalog.List()) do
		if item.Tab ~= "Roulettes" and (item.Created or preview) then
			items[#items + 1] = item
			byKey[item.Key] = item
			sig[#sig + 1] = item.Key .. ":" .. tostring(item.Id)
		end
	end
	return items, byKey, table.concat(sig, "|")
end

-- the pass key that grants the x2 Pet XP perk (PetXp2x): a potion card says "you already have it" while it is owned
function H.xpPassKey()
	for _, item in ipairs(StoreCatalog.List()) do
		if item.Kind == "Pass" and type(item.Grants) == "table" and type(item.Grants.Perks) == "table" then
			for _, perk in ipairs(item.Grants.Perks) do
				if perk == "XpX2" then
					return item.Key
				end
			end
		end
	end
	return nil
end

function H.isPotion(item)
	return item.Tab == "Boosts" and not item.Once and type(item.Grants) == "table" and type(item.Grants.Boost) == "table"
		and type(item.Grants.Boost.XpPotion) == "number"
end

function H.timeLeft(seconds)
	local minutes = math.max(1, math.ceil(seconds / 60))
	if minutes >= 60 then
		return string.format("%d h %d m left", math.floor(minutes / 60), minutes % 60)
	end
	return string.format("%d m left", minutes)
end

-- -> state, status text
function H.stateOf(item, owned, bought, xpPass)
	if not item.Created then
		return "Preview", ""
	end
	if item.Kind == "Pass" then
		if owned[item.Key] then
			return "Owned", ""
		end
		return "Buy", ""
	end
	if item.Once and bought[item.Key] then
		return "Claimed", ""
	end
	if H.isPotion(item) then
		if xpPass and owned[xpPass] then
			return "HaveIt", "You already have x2 Pet XP forever!"
		end
		local ends = tonumber(H.attr("XpBoostEnds")) or 0
		local left = ends - now()
		local potion = type(Config.Store) == "table" and Config.Store.Potion or nil
		local cap = (type(potion) == "table" and tonumber(potion.CapSeconds)) or 7 * 86400
		if left >= cap then
			return "HaveIt", "Your potion is full!"
		end
		if left > 0 then
			return "Active", H.timeLeft(left)
		end
	end
	return "Buy", ""
end

function H.windowHero()
	local bought = csvSet(H.attr("StoreBought"))
	local starter = S.ByKey.Starter
	if starter and not bought.Starter then
		return starter
	end
	return S.ByKey.VIP
end

function H.tabItems(tab)
	local list = {}
	for _, item in ipairs(S.Items) do
		if item.Tab == tab then
			list[#list + 1] = item
		end
	end
	return list
end

-- the tab's hero: the window hero in its own tab, else the first Hero item not owned / claimed
function H.heroOf(tab)
	local hero = H.windowHero()
	if hero and hero.Tab == tab then
		return hero
	end
	for _, item in ipairs(H.tabItems(tab)) do
		local st = S.States[item.Key]
		if item.Hero and not (st and (st.State == "Owned" or st.State == "Claimed")) then
			return item
		end
	end
	return nil
end

function H.tabShown(tab)
	if tab == "Roulettes" then
		return true
	end
	return #H.tabItems(tab) > 0
end

function H.defaultTab()
	local hero = H.windowHero()
	if hero then
		return hero.Tab
	end
	for _, tab in ipairs(StoreCatalog.Tabs) do
		if tab ~= "Roulettes" and H.tabShown(tab) then
			return tab
		end
	end
	return nil
end

function H.priceText(item)
	local n = item.Created and S.Prices[item.Id] or nil
	if n then
		return robuxGlyph() .. Util.Commas(n)
	end
	return "..."
end

----------------------------------------------------------------------
-- Prices (background, once per session per id, one retry)
----------------------------------------------------------------------
function H.fetchPrice(item, retry)
	local id = item.Id
	local infoType = item.Kind == "Pass" and Enum.InfoType.GamePass or Enum.InfoType.Product
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		local price = ok and type(info) == "table" and tonumber(info.PriceInRobux) or nil
		if price and price > 0 then
			S.Prices[id] = math.floor(price)
			if S.Open then
				safe("prices", H.paintCards)
			end
		elseif not retry then
			local seconds = (type(Config.Store) == "table" and tonumber(Config.Store.PriceRetrySeconds)) or 10
			task.delay(seconds, function()
				if not S.Prices[id] then
					H.fetchPrice(item, true)
				end
			end)
		end
	end)
end

function H.askPrices()
	for _, item in ipairs(S.Items) do
		if item.Created and not S.Asked[item.Id] then
			S.Asked[item.Id] = true
			H.fetchPrice(item, false)
		end
	end
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
function H.build()
	if S.Built then
		return
	end
	S.Built = true
	local holder = frame("StoreWindow", U.Gui, { Visible = false, Active = true })
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	local panel = NeonKit.Card({ Name = "Panel", Color = Theme.NeonColor("Store"), Size = UDim2.fromScale(1, 1), Floor = false, Parent = holder })
	U.Panel = panel
	local body = panel.Body
	U.Body = body

	-- title bar: the name, the three balances, the X
	local bar = frame("TitleBar", body)
	U.TitleBar = bar
	U.Title = label("Title", bar, NeonKit.Glyphs.Store .. " Store", "Title", 24, { TextXAlignment = Enum.TextXAlignment.Left })
	for _, id in ipairs(CURRENCY_ORDER) do
		local cur = Theme.Currency[id]
		local pill = NeonKit.Card({ Name = "Balance_" .. id, Color = cur.Color, Corner = 12, Glow = false, Floor = false, Sheen = false, Parent = bar })
		local glyph = label("Glyph", pill.Body, cur.Glyph, "Display", 16, { TextColor3 = cur.Color })
		local value = label("Text", pill.Body, "0", "Display", 16, { TextXAlignment = Enum.TextXAlignment.Left })
		U.Pills[id] = { Root = pill.Root, Glyph = glyph, Text = value }
	end
	U.Close = CloudUI.Button({
		Name = "Close",
		Text = CLOSE_GLYPH,
		Style = "Red",
		Size = UDim2.fromOffset(44, 44),
		TextSize = 22,
		Callback = function()
			StoreController.Close()
		end,
		Parent = bar,
	})

	-- the tab column
	local tabs = frame("Tabs", body)
	U.TabColumn = tabs
	for i, tab in ipairs(StoreCatalog.Tabs) do
		local button = Instance.new("TextButton")
		button.Name = "Tab_" .. tab
		button.Text = ""
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.BackgroundColor3 = Theme.Darken(Theme.NeonColor(TAB_COLORS[tab] or "Blue"), 0.55)
		button.LayoutOrder = i
		Theme.Corner(button, UDim.new(0, 10))
		local outline = Theme.Stroke(button, Theme.NeonColor(TAB_COLORS[tab] or "Blue"), 2, 0.2)
		local icon = label("Icon", button, NeonKit.Glyphs[tab] or "", "Display", 20)
		local name = label("Label", button, tab, "Button", 15)
		button.Parent = tabs
		button.Activated:Connect(function()
			safe("tab", H.tapTab, tab)
		end)
		U.Tabs[tab] = { Button = button, Icon = icon, Label = name, Stroke = outline }
	end

	-- the pages and the empty text
	local pages = frame("Pages", body)
	U.PagesFrame = pages
	U.Soon = label("Soon", pages, K.SOON, "Heading", 20, { Visible = false, TextWrapped = true, Size = UDim2.fromScale(1, 1) })
end

-- one card: Art | Name + Gets you lines + Status | PricePill over Buy
function H.buildCard(item, page, isHero)
	local color = TAB_COLORS[item.Tab] or "Blue"
	local card = NeonKit.Card({
		Name = "Card_" .. item.Key,
		Class = "TextButton",
		Color = color,
		Size = UDim2.fromOffset(600, 108),
		Floor = false,
		ClipsDescendants = isHero == true,
		Parent = page,
	})
	card.Root:SetAttribute("Hero", isHero == true)
	card.Root:SetAttribute("Key", item.Key)
	card.Root.Activated:Connect(function()
		sfx("StorePop", "Click")
	end)
	local b = card.Body
	local art = frame("Art", b, { BackgroundTransparency = 0.35, BackgroundColor3 = Theme.Darken(Theme.NeonColor(color), 0.6) })
	Theme.Corner(art, UDim.new(0, 12))
	local glyph = label("Glyph", art, H.artGlyph(item), "Display", 40, { Size = UDim2.fromScale(1, 1), TextTruncate = Enum.TextTruncate.None })
	local name = label("Name", b, item.Name or item.Key, "Title", 24, { TextXAlignment = Enum.TextXAlignment.Left })
	local gets = label("GetsYou", b, "Gets you:", "Body", 16, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MUTED })
	local lines = {}
	local texts = StoreCatalog.GrantLines(item.Grants)
	if type(item.Line) == "string" and item.Line ~= "" then
		texts[#texts + 1] = item.Line
	end
	for i, text in ipairs(texts) do
		lines[i] = label("Line" .. i, b, text, "Body", 16, { TextXAlignment = Enum.TextXAlignment.Left })
	end
	local status = label("Status", b, "", "Body", 15, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	local pricePill = NeonKit.Card({ Name = "PricePill", Color = "Gold", Corner = 12, Glow = false, Floor = false, Sheen = false, Parent = b })
	local price = label("Text", pricePill.Body, "...", "Display", 20, { Size = UDim2.fromScale(1, 1) })
	local buyHolder = frame("BuyHolder", b)
	local pulse = Util.Create("UIScale", { Name = "Pulse", Scale = 1, Parent = buyHolder })
	local buy = CloudUI.Button({
		Name = "Buy",
		Text = "Buy",
		Style = "Green",
		Size = UDim2.fromScale(1, 1),
		TextSize = 20,
		Callback = function()
			safe("buy", H.buy, item.Key)
		end,
		Parent = buyHolder,
	})
	local entry = {
		Item = item, Card = card, Root = card.Root, Art = art, Glyph = glyph, Name = name, GetsYou = gets, Lines = lines,
		Status = status, PricePill = pricePill, Price = price, BuyHolder = buyHolder, Pulse = pulse, Buy = buy, Hero = isHero == true,
	}
	U.Cards[item.Key] = entry
	return entry
end

function H.artGlyph(item)
	local G = NeonKit.Glyphs
	if item.Gem then
		return Theme.Currency.Gems.Glyph
	end
	local g = type(item.Grants) == "table" and item.Grants or {}
	if item.Key == "VIP" then
		return G.VipCrown or G.Passes
	end
	if g.Tokens and not g.Pets then
		return Theme.Currency.Tokens.Glyph
	end
	if g.Cash and not g.Pets then
		return Theme.Currency.Cash.Glyph
	end
	return G[item.Tab] or G.Store
end

-- (re)builds every page and card when the shown set changed
function H.rebuild()
	local wasShine = S.Shine ~= nil
	H.shineOff()
	for _, page in pairs(U.Pages) do
		page:Destroy()
	end
	U.Pages = {}
	U.Cards = {}
	-- the states first: the heroes depend on them
	H.computeStates()
	for i, tab in ipairs(StoreCatalog.Tabs) do
		if tab ~= "Roulettes" then
			local page = Instance.new("ScrollingFrame")
			page.Name = "Page_" .. tab
			page.BackgroundTransparency = 1
			page.BorderSizePixel = 0
			page.ScrollBarThickness = K.SCROLLBAR
			page.ScrollingDirection = Enum.ScrollingDirection.Y
			page.CanvasSize = UDim2.new()
			page.Size = UDim2.fromScale(1, 1)
			page.Visible = false
			page.LayoutOrder = i
			page.Parent = U.PagesFrame
			U.Pages[tab] = page
			local hero = H.heroOf(tab)
			local order = 1
			if hero then
				H.buildCard(hero, page, true).Order = order
			end
			for _, item in ipairs(H.tabItems(tab)) do
				if item ~= hero then
					order = order + 1
					H.buildCard(item, page, false).Order = order
				end
			end
		end
	end
	if wasShine and S.Open then
		H.shineOn()
	end
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
function H.metrics()
	return S.Mode == "Phone" and K.PHONE or K.PC
end

function H.layoutCard(entry, w, h, M)
	local pad = M.Pad
	place(entry.Root, entry.Root.Position.X.Offset, entry.Root.Position.Y.Offset, w, h)
	local art = math.max(40, math.min(M.Art, h - 2 * pad, math.floor(w * 0.3)))
	place(entry.Art, pad, math.floor((h - art) / 2), art, art)
	entry.Glyph.TextSize = math.min(100, math.max(20, math.floor(art * 0.5))) -- Roblox caps TextSize at 100
	local buyW, buyH = math.min(M.BuyW, math.floor(w * 0.3)), M.BuyH
	local rightX = w - pad - buyW
	local buyY = h - pad - buyH
	place(entry.BuyHolder, rightX, buyY, buyW, buyH)
	entry.Buy.TextSize = M.BuyText
	local pillH = M.Price + 8
	place(entry.PricePill.Root, rightX + math.floor(buyW * 0.1), buyY - 4 - pillH, math.floor(buyW * 0.8), pillH)
	entry.Price.TextSize = M.Price
	local textX = pad + art + pad
	local textW = math.max(40, rightX - pad - textX)
	local nameH = M.Name + 4
	local lineH = M.Line + 3
	local statusOn = entry.Status.Text ~= ""
	local n = #entry.Lines + (statusOn and 1 or 0)
	local room = h - 2 * pad - nameH - 2
	local getsOn = (n + 1) * lineH <= room
	place(entry.Name, textX, pad, textW, nameH)
	entry.Name.TextSize = M.Name
	local y = pad + nameH + 2
	entry.GetsYou.Visible = getsOn
	if getsOn then
		place(entry.GetsYou, textX, y, textW, lineH)
		entry.GetsYou.TextSize = M.Line
		y = y + lineH
	end
	for _, line in ipairs(entry.Lines) do
		place(line, textX, y, textW, lineH)
		line.TextSize = M.Line
		y = y + lineH
	end
	place(entry.Status, textX, y, textW, M.Status + 3)
	entry.Status.TextSize = M.Status
	entry.Status.Visible = statusOn
end

function H.layout()
	if not S.Built then
		return
	end
	local r = NeonKit.BigRect(K)
	S.Rect = r
	S.Mode, S.Scale = r.mode, r.scale
	local M = H.metrics()
	local W = math.floor(r.w / r.scale + 0.5)
	local Hh = math.floor(r.h / r.scale + 0.5)
	place(U.Holder, r.x, r.y, W, Hh)
	U.Fit.Scale = r.scale
	-- title bar
	place(U.TitleBar, 0, 0, W, M.Title)
	place(U.Title, M.Pad + 6, 0, math.max(80, W * 0.3), M.Title)
	U.Title.TextSize = M.TitleText
	place(U.Close, W - M.Close - 4, math.floor((M.Title - M.Close) / 2), M.Close, M.Close)
	U.Close.TextSize = math.floor(M.Close * 0.5)
	local x = W - M.Close - 12
	for i = #CURRENCY_ORDER, 1, -1 do
		local pill = U.Pills[CURRENCY_ORDER[i]]
		x = x - M.PillW
		place(pill.Root, x, math.floor((M.Title - M.PillH) / 2), M.PillW, M.PillH)
		place(pill.Glyph, 4, 0, M.PillText + 4, M.PillH)
		place(pill.Text, M.PillText + 10, 0, M.PillW - M.PillText - 14, M.PillH)
		pill.Glyph.TextSize = M.PillText
		pill.Text.TextSize = M.PillText
		x = x - 6
	end
	-- tabs (hidden ones leave no hole)
	place(U.TabColumn, M.TabX, M.TabY, M.TabW, Hh - M.TabY)
	local y = 0
	for _, tab in ipairs(StoreCatalog.Tabs) do
		local t = U.Tabs[tab]
		local shown = H.tabShown(tab)
		t.Button.Visible = shown
		if shown then
			place(t.Button, 0, y, M.TabW, M.TabH)
			y = y + M.TabH + M.TabGap
			local phone = S.Mode == "Phone"
			-- phone: the icon over the label; PC: the icon left of the label
			if phone then
				place(t.Icon, 0, 1, M.TabW, M.TabIcon + 2)
				place(t.Label, 2, M.TabIcon + 2, M.TabW - 4, M.TabH - M.TabIcon - 3)
			else
				place(t.Icon, 10, 0, M.TabIcon + 12, M.TabH)
				place(t.Label, M.TabIcon + 26, 0, M.TabW - M.TabIcon - 32, M.TabH)
			end
			t.Icon.TextSize = M.TabIcon
			t.Label.TextSize = M.TabLabel
		end
	end
	-- pages
	local sw = W - M.ScrollX - 10
	local sh = Hh - M.TabY - 8
	place(U.PagesFrame, M.ScrollX, M.TabY, sw, sh)
	U.Soon.TextSize = M.Soon
	local cw = sw - K.SCROLLBAR - 2
	for tab, page in pairs(U.Pages) do
		place(page, 0, 0, sw, sh)
		local list = {}
		for _, entry in pairs(U.Cards) do
			if entry.Item.Tab == tab then
				list[#list + 1] = entry
			end
		end
		table.sort(list, function(a, b)
			return (a.Order or 0) < (b.Order or 0)
		end)
		local cy = 0
		for _, entry in ipairs(list) do
			local h = entry.Hero and M.Hero or M.Card
			entry.Root.Position = UDim2.fromOffset(0, cy)
			H.layoutCard(entry, cw, h, M)
			cy = cy + h + M.Gap
		end
		page.CanvasSize = UDim2.fromOffset(0, math.max(0, cy - M.Gap))
	end
	H.coverColumn()
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
function H.computeStates()
	local owned = csvSet(H.attr("OwnedPasses"))
	local bought = csvSet(H.attr("StoreBought"))
	local xpPass = H.xpPassKey()
	local states = {}
	for _, item in ipairs(S.Items) do
		local st, status = H.stateOf(item, owned, bought, xpPass)
		states[item.Key] = { State = st, Status = status }
	end
	S.States = states
end

local BUY_TEXT = { Buy = "Buy", Active = "Buy", Owned = "Owned", Claimed = "Claimed!", HaveIt = "Buy", Preview = "PREVIEW" }

function H.paintCards()
	local match = H.inMatch()
	for key, entry in pairs(U.Cards) do
		local st = S.States[key] or { State = "Buy", Status = "" }
		entry.Buy.Text = BUY_TEXT[st.State] or "Buy"
		local off = match or not (st.State == "Buy" or st.State == "Active")
		if (entry.Buy:GetAttribute("Disabled") == true) ~= off then
			CloudUI.SetDisabled(entry.Buy, off) -- (only on a change: a repaint tweens the face)
		end
		entry.Price.Text = H.priceText(entry.Item)
		entry.PricePill.Root.Visible = st.State ~= "Owned" and st.State ~= "Claimed"
		entry.Status.Text = st.Status
		local dim = st.State == "HaveIt"
		entry.Card.SetColor(dim and Theme.Neon.Grey or Theme.NeonColor(TAB_COLORS[entry.Item.Tab] or "Blue"))
		entry.Name.TextColor3 = dim and MUTED or WHITE
		for _, line in ipairs(entry.Lines) do
			line.TextColor3 = dim and MUTED or WHITE
		end
	end
	for _, id in ipairs(CURRENCY_ORDER) do
		local value = 0
		local fn = State[id]
		if type(fn) == "function" then
			local ok, v = pcall(fn)
			value = ok and tonumber(v) or 0
		end
		U.Pills[id].Text.Text = Theme.ShortNumber(value)
	end
end

function H.selectTab(tab)
	if tab and not H.tabShown(tab) then
		tab = nil
	end
	if tab == "Roulettes" then
		tab = nil
	end
	S.Tab = tab or H.defaultTab()
	for name, t in pairs(U.Tabs) do
		local on = name == S.Tab
		t.Button:SetAttribute("Selected", on)
		t.Button.BackgroundColor3 = Theme.Darken(Theme.NeonColor(TAB_COLORS[name] or "Blue"), on and 0.15 or 0.55)
		t.Stroke.Thickness = on and 3 or 2
	end
	for name, page in pairs(U.Pages) do
		page.Visible = name == S.Tab
	end
	U.Soon.Visible = #S.Items == 0
end

-- re-reads the shown set (rebuilds on a change), the states, the prices and the layout
function H.refresh()
	if not S.Built then
		return
	end
	local items, byKey, sig = H.collect()
	S.Items, S.ByKey = items, byKey
	if sig ~= S.Signature then
		S.Signature = sig
		H.rebuild()
		H.selectTab(S.Tab)
		if S.Open then
			H.askPrices()
		end
	else
		H.computeStates()
	end
	H.paintCards()
	if S.Open then
		H.layout()
	end
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------
function H.buy(key)
	sfx("StorePop", "Click")
	if H.inMatch() then
		H.hint(K.MATCH_HINT)
		StoreController.Close()
		return
	end
	local st = S.States[key]
	if not st or not (st.State == "Buy" or st.State == "Active") then
		return
	end
	local t = os.clock()
	if t - S.LastBuy < K.BUY_GAP then
		return
	end
	S.LastBuy = t
	local remote = H.remote("StoreRequest")
	if remote then
		safe("StoreRequest", function()
			remote:FireServer("Buy", key)
		end)
	end
end

function H.tapTab(tab)
	sfx("StorePop", "Click")
	if tab == "Roulettes" then
		StoreController.Close()
		local menu = H.controller("MenuController")
		if menu and type(menu.Open) == "function" then
			safe("roulettes", menu.Open, "Shop")
		end
		return
	end
	H.selectTab(tab)
	H.shineOff()
	if S.Open then
		H.shineOn()
	end
end

----------------------------------------------------------------------
-- Shine (High only)
----------------------------------------------------------------------
function H.track(tween)
	if S.Shine and tween then
		local list = S.Shine.Tweens
		list[#list + 1] = tween
	end
	return tween
end

function H.heroEntry()
	for _, entry in pairs(U.Cards) do
		if entry.Hero and entry.Item.Tab == S.Tab then
			return entry
		end
	end
	return nil
end

function H.shineOn()
	if S.Shine or not S.Open then
		return
	end
	local high = H.quality() == "High"
	S.Shine = { Tweens = {}, Parts = {}, Views = {}, Conn = nil, High = high }
	local shine = S.Shine
	local hero = H.heroEntry()
	if hero then
		local over = frame("HeroShine", hero.Card.Body, {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0.82,
			BackgroundColor3 = WHITE,
			ZIndex = hero.Root.ZIndex,
		})
		Theme.Corner(over, UDim.new(0, 14))
		local grad = Util.Create("UIGradient", {
			Name = "HeroSpin",
			Rotation = 35,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, GOLD),
				ColorSequenceKeypoint.new(0.5, WHITE),
				ColorSequenceKeypoint.new(1, Theme.NeonColor(TAB_COLORS[hero.Item.Tab] or "Gold")),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.5, 0.75),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
			Parent = over,
		})
		shine.Parts[#shine.Parts + 1] = over
		if high then
			local t0 = os.clock()
			shine.Conn = RunService.Heartbeat:Connect(function()
				grad.Rotation = ((os.clock() - t0) / K.SPIN_SECONDS * 360) % 360
			end)
			local sheen = frame("Sheen", hero.Card.Body, {
				Size = UDim2.new(0.12, 0, 1.6, 0),
				Position = UDim2.new(-0.3, 0, -0.3, 0),
				Rotation = 18,
				BackgroundTransparency = 0.7,
				BackgroundColor3 = WHITE,
				ZIndex = hero.Root.ZIndex,
			})
			shine.Parts[#shine.Parts + 1] = sheen
			local mine = S.Token
			task.spawn(function()
				while S.Open and S.Token == mine and S.Shine == shine do
					task.wait(K.SHEEN_MIN + math.random() * (K.SHEEN_MAX - K.SHEEN_MIN))
					if not (S.Open and S.Token == mine and S.Shine == shine) or sheen.Parent == nil then
						break
					end
					sheen.Position = UDim2.new(-0.3, 0, -0.3, 0)
					H.track(Util.Tween(sheen, K.SHEEN_TIME, { Position = UDim2.new(1.2, 0, -0.3, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
				end
			end)
			task.spawn(function()
				while S.Open and S.Token == mine and S.Shine == shine do
					task.wait(K.PULSE_EVERY)
					if not (S.Open and S.Token == mine and S.Shine == shine) or hero.Pulse.Parent == nil then
						break
					end
					local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
					local ok, tween = pcall(function()
						return game:GetService("TweenService"):Create(hero.Pulse, info, { Scale = K.PULSE_SCALE })
					end)
					if ok and tween then
						tween:Play()
						H.track(tween)
					end
				end
			end)
		end
	end
	if high then
		-- the pet cards turn their pet (CloudUI.PetViewport) instead of the glyph
		for _, entry in pairs(U.Cards) do
			local pets = type(entry.Item.Grants) == "table" and entry.Item.Grants.Pets or nil
			if type(pets) == "table" and entry.Item.Tab == S.Tab then
				local petId = next(pets)
				local ok, view = pcall(CloudUI.PetViewport, entry.Art, petId, UDim2.fromScale(1, 1), {})
				if ok and type(view) == "table" then
					entry.Glyph.Visible = false
					shine.Views[#shine.Views + 1] = { View = view, Entry = entry }
				end
			end
		end
	end
end

function H.shineOff()
	local shine = S.Shine
	if not shine then
		return
	end
	S.Shine = nil
	if shine.Conn then
		shine.Conn:Disconnect()
	end
	for _, tween in ipairs(shine.Tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	for _, part in ipairs(shine.Parts) do
		part:Destroy()
	end
	for _, v in ipairs(shine.Views) do
		pcall(function()
			if type(v.View.Destroy) == "function" then
				v.View.Destroy()
			elseif v.View.Frame then
				v.View.Frame:Destroy()
			end
		end)
		v.Entry.Glyph.Visible = true
	end
	for _, entry in pairs(U.Cards) do
		entry.Pulse.Scale = 1
	end
end

----------------------------------------------------------------------
-- Touch controls, the menu column, gamepad B
----------------------------------------------------------------------
-- the phone window fills the screen: Roblox's thumbstick and jump button go while it is up (the PetsController rule)
function H.syncTouch()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local want = S.Open and (S.Mode == "Phone" or touchOnly)
	if want == S.TouchOff then
		return
	end
	S.TouchOff = want
	pcall(function()
		if want then
			S.TouchWas = GuiService.TouchControlsEnabled
			GuiService.TouchControlsEnabled = false
		else
			GuiService.TouchControlsEnabled = S.TouchWas ~= false
		end
	end)
end

function H.coverColumn()
	local menu = H.controller("MenuController")
	if menu and type(menu.SetColumnCovered) == "function" then
		safe("cover", menu.SetColumnCovered, (S.Open and S.Rect) and S.Rect.x or nil)
	end
	H.syncTouch()
end

function H.syncBack()
	if S.Open and not S.BackBound then
		S.BackBound = true
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					safe("back", StoreController.Close)
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

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function StoreController.IsOpen()
	return S.Open
end

function StoreController.Layout()
	if S.Open then
		return S.Mode
	end
	return NeonKit.BigRect(K).mode
end

function StoreController.RobuxGlyph()
	return robuxGlyph()
end

function StoreController.Cards()
	local out = {}
	for key, entry in pairs(U.Cards) do
		local st = S.States[key]
		out[key] = { State = st and st.State or "Buy", Price = entry.Price.Text, Tab = entry.Item.Tab }
	end
	return out
end

function StoreController.Open(args)
	if not initialized then
		StoreController.Init()
	end
	if not U.Gui then
		return false
	end
	args = type(args) == "table" and args or {}
	if H.inMatch() then
		H.hint(K.MATCH_HINT)
		return false
	end
	if args.Tab == "Roulettes" then
		StoreController.Close()
		H.tapTab("Roulettes")
		return false
	end
	H.build()
	local wasOpen = S.Open
	S.Open = true
	if not wasOpen then
		S.Token = S.Token + 1
	end
	H.refresh()
	if type(args.Tab) == "string" or not wasOpen then
		H.selectTab(type(args.Tab) == "string" and args.Tab or nil)
	end
	U.Holder.Visible = true
	H.layout()
	H.syncBack()
	if not wasOpen then
		H.askPrices()
		H.shineOn()
		local mine = S.Token
		task.spawn(function()
			while S.Open and S.Token == mine do
				task.wait(K.TICK)
				if S.Open and S.Token == mine then
					safe("tick", H.refresh)
				end
			end
		end)
		local menu = H.controller("MenuController")
		if menu and menu.WindowOpened then
			safe("window opened", function()
				menu.WindowOpened:Fire("Store")
			end)
		end
	else
		H.shineOff()
		H.shineOn()
	end
	return true
end

function StoreController.Close()
	if not S.Open then
		return
	end
	S.Open = false
	S.Token = S.Token + 1
	H.shineOff()
	if U.Holder then
		U.Holder.Visible = false
	end
	H.syncBack()
	H.coverColumn()
end

function StoreController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)
	robuxGlyph()
	U.Gui = CloudUI.NewScreenGui("NimbusStore", K.DISPLAY_ORDER)
	U.Gui.IgnoreGuiInset = true
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if S.Open then
			safe("relayout", H.layout)
		end
	end)
	State.Changed:Connect(function()
		if S.Open then
			safe("balances", H.paintCards)
		end
	end)
	for _, name in ipairs({ "OwnedPasses", "StoreBought", "XpBoostEnds", "StorePreview" }) do
		LocalPlayer:GetAttributeChangedSignal(Config.Attr[name] or name):Connect(function()
			if S.Open then
				safe("refresh", H.refresh)
			end
		end)
	end
	LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
		if H.inMatch() then
			StoreController.Close()
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if S.Open and input.KeyCode == Enum.KeyCode.Escape then
			StoreController.Close()
		end
	end)
	-- one window at a time (spec 8): any other window's opening closes this one
	local menu = H.controller("MenuController")
	if menu and menu.WindowOpened then
		menu.WindowOpened:Connect(function(id)
			if id ~= "Store" and S.Open then
				StoreController.Close()
			end
		end)
	end
	-- the server's thank-you toast for a granted purchase plays the coin clatter
	task.spawn(function()
		local remote = H.remote("Notify")
		if remote then
			remote.OnClientEvent:Connect(function(message)
				if type(message) == "string" and message:sub(1, 9) == "Thank you" then
					sfx("StoreBuy", "Reward")
				end
			end)
		end
	end)
end

return StoreController
