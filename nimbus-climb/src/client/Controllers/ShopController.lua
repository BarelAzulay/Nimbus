-- ShopController (client; lobby-shop Tasks 21-22, docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.3 "Who owns
-- it" / "Tabs and items" / "Window" / "Eggs tab" / "Packs, Passes, Boosts" / "Hooks"; moved with git mv from
-- StoreController, store W1 Task 7 of docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.1 / 8 / 13b): the ONE
-- Shop window. A left tab rail (Eggs, Gems, then the Robux items Packs, Passes, Boosts), the Eggs page (client/UI/ShopEggs:
-- the Secret Roulette hero and the four machine cards, every spin through client/UI/EggStage), the Gems page
-- (client/UI/ShopGems) and the Store's pack cards restyled into its content box. client/Controllers/StoreController is a
-- thin forwarder kept for old callers. (Task 22: the old Cloud Shop and its stage left MenuController.)
--
--   ShopController.Init()           also EggStage.Init() (the RouletteResult listener)
--   ShopController.Open(args)       args = { Tab = any alias NormalizeTab knows, RouletteId, Currency } | nil. Refused while
--                                   InMatch (the side hint "The Store is closed during a match.") and while the egg stage
--                                   shows -> false. No tab: the last tab of this session (the first time Eggs). RouletteId:
--                                   the Eggs tab, that card scrolled into view and outlined gold for 2.6 s
--                                   (ShopEggs.Focus); Currency alone never switches the tab. FromAltar = true (shop-area
--                                   16.17.3: the Storm Altar's prompt): the Secret card reads "at the altar" until Close
--                                   while the client has no live reading of the distance (ShopEggs.SetFromAltar; a live
--                                   reading always wins, so walking off locks the card; a later Open while open keeps it;
--                                   the server checks the distance again on every spin)
--   ShopController.Close()
--   ShopController.IsOpen() -> bool
--   ShopController.NormalizeTab(tab) -> "Eggs" | "Gems" | "Packs" | "Passes" | "Boosts" | nil   "egg*", "roul*", "Items",
--                                   "Shop" -> Eggs; "gem*", "Currency", "Tokens" -> Gems; Packs / Passes / Boosts in any case
--   ShopController.Tab() -> the tab shown (or last shown)
--   ShopController.Layout() -> "PC" | "Compact" (a PC design width under 1,400) | "Phone" | "Portrait"
--   ShopController.Portrait() -> bool
--   ShopController.Cards() -> { [key] = { State, Price, Tab } }   every card shown and every Gems-tab pack (tests)
--   ShopController.Palette(key) -> { Top, Bottom, Edge } | nil    a pack's own colours (tests, ShopGems)
--   ShopController.RobuxGlyph() -> "\238\128\130" (U+E002) or "R$" when the font lacks it
--   ShopController._S                the state table (tests: _S.Tab = nil is a fresh session)
--   signal ShopController.Toggled(open)  fired once per open (true) and per close (false); DailyController hides the
--                                    HUD Gifts button while the Shop is open (review round 1: it sat over the header)
--
-- Who opens it: the top bar's PillButton_Shop and a server OpenPanel("Shop" | "Store", args) through MenuController's
-- P5.openShop (and the forwarder). It fires MenuController.WindowOpened("Shop") on every open (spec 16.3 "WindowOpened";
-- the tutorial's ShopOpened); it closes on any other WindowOpened id, on Esc / gamepad B ("NimbusShopBack", High, bound
-- only while open, always Sink) / its X, on InMatch and on MenuController.Close(). MouseLock.WatchVisible("Shop",
-- ShopWindow) frees the cursor while it shows; on a phone or a touch-only device MenuController.SetTouchHidden("Shop",
-- true) and SetColumnCovered(windowLeft, "Shop").
-- The egg stage (Task 22): ShopWindow hides while EggStage shows (Opened) and comes back on Closed("Done" | "Error") while
-- the Shop is still open and not InMatch; any other Closed reason ("Match" | "Close") closes a still-open Shop. ONE Esc
-- handler: while the stage shows it calls EggStage.Back() (skip, then DONE) and stops there; else it closes the Shop.
-- While the stage shows B does nothing here (NimbusHatchBack, High + 1, is the stage's). The Eggs page repaints on
-- EggStage.Pending / Answered and once more WAIT_TIMEOUT after a Pending (the stage's timeout fires no signal).
-- The rail's FastHatch toggle (PC / Compact, Eggs only, under the tabs): ClientSettings.Set("FastHatch", not on).
--
-- Screen: ScreenGui "NimbusShop" (DisplayOrder 19, IgnoreGuiInset, ResetOnSpawn false) > Frame "ShopWindow" (UIScale
-- "Fit"; NeonKit.BigRect with RECT 820x330 at 390 px -> 1540x910 at 1080 px, PC_MAX_W 0.81) > Panel (the frame),
-- Header (Icon, Title "Shop", Balance_Gems (a GemIcon.Amount), Balance_Tokens, CloseButton; balances Theme.ShortNumber
-- from 1e6), Rail (Tab_Eggs, Tab_Gems, RobuxDivider, Tab_Packs, Tab_Passes, Tab_Boosts: Icon + Label, attribute Selected;
-- Tab_Packs.Dot while the Starter Pack is on sale and unbought; FastHatch) and Body (the content box) > Page_Eggs
-- (ShopEggs), Page_Gems (ShopGems), Page_Packs / Page_Passes / Page_Boosts (ScrollingFrames of Card_<key>) and Soon ("The
-- Shop opens soon!" on an empty card page).
--   PC: header 76, rail 224 at x 18 (tabs 224 x 80 at y 16 + i * 92, +44 from Packs; the divider "Robux items"), content
--     x 262, width = window - 300 (1240). Compact: the rail 112 at x 8 (icon over label), content x 128, width window - 152.
--   Phone: header 50, rail 104 at x 8 (tabs 104 x 48 at 6 + i * 54 with a 280 px body; 104 x 44 at 4 + i * 49 under 276),
--     content x 120, width window - 128. Portrait: header rows (icon, Shop, X; both balances), the rail as one row of five
--     64 x 56 tabs, the body a vertical list.
-- Items: StoreCatalog.List(). Packs / Passes / Boosts show an item when created (Id > 0) or under the StorePreview
-- attribute (an Id 0 item is a "Preview" card: PREVIEW, disabled), as the Store did; the Gems page always shows its packs.
-- Card states: Buy, Owned (a pass in OwnedPasses), Claimed (a Once key in StoreBought), Loading (a Once item while
-- StoreBought is absent), Locked (lobby-shop 16.1: a Product that grants Tokens while PaidRandomItemsRestricted is not
-- false: "Token packs are not available on your account" / "Checking your account..." on the card, Buy inactive), Active /
-- HaveIt (an XP potion), Preview. Buy -> StoreRequest:FireServer("Buy", key) (1 s client gap; the gem potion's
-- StoreRequest("GemBuy", "XpPotionGems") shares it): the client never prompts a purchase or decides a price.
-- Prices: MarketplaceService:GetProductInfo once per session per created id, in the background, one retry after
-- Config.Store.PriceRetrySeconds; "..." meanwhile (Buy never waits for it).
-- Colours (the owner's "make colors for every pack"): every pack its own PALETTE entry (a saturated Top -> Bottom gradient
-- on the card's Paint frame, an Edge colour on its neon stroke and glow); the hero runs Bottom -> Top -> a near-white
-- highlight with a thicker edge; a Have-it card goes grey; every card text keeps its dark outline.
-- Shine (GraphicsQuality High only, built on open, torn down on close): the hero's UIGradient "HeroSpin" turns every 8 s,
-- a sheen sweeps it every 6-9 s, its Buy pulses (1 -> 1.04) every 2.5 s, pet cards show a turning CloudUI.PetViewport.
-- Sounds: StorePop on a card tap (Click until AudioIds has it), StoreBuy on a purchase toast (Reward).
-- Art: the store_* render of spec 9 (TextureIds[ART_KEYS key], an ImageLabel "Image") when it has an id, else the glyph.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles; no asset ids (TextureIds numbers only).

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
local GemIcon = require(Client:WaitForChild("UI"):WaitForChild("GemIcon"))
local ShopGems = require(Client:WaitForChild("UI"):WaitForChild("ShopGems"))
local ShopEggs = require(Client:WaitForChild("UI"):WaitForChild("ShopEggs"))
local EggStage = require(Client:WaitForChild("UI"):WaitForChild("EggStage"))
local State = require(Client:WaitForChild("State"))
local SoundFx = require(Client:WaitForChild("SoundFx"))
local ClientSettings = require(Client:WaitForChild("ClientSettings"))

local ShopController = {}
ShopController.Toggled = Util.Signal()

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local K = {
	DISPLAY_ORDER = 19,
	-- the window box (NeonKit.BigRect; spec 16.3 "Window")
	RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1540, Y1 = 910 },
	MARGIN = 12,
	PHONE_W = 900,
	SHORT = 560,
	PC_MIN_H = 600,
	PC_MAX_W = 0.81,
	COMPACT_W = 1400, -- a PC design width under this is the Compact layout
	BUY_GAP = 1, -- seconds between two Buy sends
	TICK = 1, -- seconds between two refreshes while open (the potion's time left)
	BACK_ACTION = "NimbusShopBack",
	-- the rail's Fast hatch toggle (Eggs only): PC 224 x 52 ("Fast hatch" 20 px, the switch right), Compact 112 wide (the
	-- switch over the label, >= 44 px at the 0.8 scale)
	FAST = { PC = { W = 224, H = 52, Text = 20, SwitchW = 56, SwitchH = 30 }, Compact = { W = 112, H = 64, Text = 18, SwitchW = 48, SwitchH = 24 } },
	HATCH_WAIT = ((EggStage.Metrics and EggStage.Metrics.WAIT_TIMEOUT) or 7) + 0.1, -- an unanswered spin gives up: repaint
	SPIN_SECONDS = 8, -- the hero gradient's turn
	SHEEN_MIN = 6,
	SHEEN_MAX = 9,
	SHEEN_TIME = 0.9,
	PULSE_EVERY = 2.5,
	PULSE_SCALE = 1.04,
	ROBUX_GLYPH = "\238\128\130", -- U+E002
	ROBUX_FALLBACK = "R$",
	MATCH_HINT = "The Store is closed during a match.",
	SOON = "The Shop opens soon!",
	LOCK = "Token packs are not available on your account",
	CHECKING = "Checking your account...",
	SHORT_GEMS = "Not enough gems.",
	POTION_KEY = "XpPotionGems",
	RESTRICTED_ATTR = "PaidRandomItemsRestricted", -- GemService: true while restricted or unknown, false when allowed
	SCROLLBAR = 6,
	ACCENT = rgb(90, 168, 232), -- the header (the A mock)
	NAVY = rgb(11, 16, 48),
	TABS = { "Eggs", "Gems", "Packs", "Passes", "Boosts" },
	GEM_PILES = { 1, 2, 4, 6 },
	-- the window per layout (design px): header, rail, content box
	WIN = {
		PC = { Header = 76, Icon = 42, TitleText = 34, TitleW = 200, GemsW = 140, TokW = 190, PillH = 44, PillText = 22, Close = 56,
			RailX = 18, RailW = 224, TabH = 80, TabY = 16, TabStep = 92, Split = 44, TabIcon = 40, TabLabel = 26, ContentX = 262, ContentR = 38 },
		Compact = { Header = 76, Icon = 42, TitleText = 34, TitleW = 200, GemsW = 140, TokW = 190, PillH = 44, PillText = 22, Close = 56,
			RailX = 8, RailW = 112, TabH = 80, TabY = 16, TabStep = 92, Split = 44, TabIcon = 32, TabLabel = 18, ContentX = 128, ContentR = 24 },
		Phone = { Header = 50, Icon = 28, TitleText = 20, TitleW = 130, GemsW = 96, TokW = 128, PillH = 32, PillText = 15, Close = 44,
			RailX = 8, RailW = 104, TabH = 48, TabY = 6, TabStep = 54, Split = 0, TabIcon = 24, TabLabel = 15, ContentX = 120, ContentR = 8,
			ShortBody = 276, ShortTabH = 44, ShortTabY = 4, ShortTabStep = 49 },
		Portrait = { Header = 84, Row = 44, Icon = 28, TitleText = 20, PillH = 32, PillText = 15, Close = 44,
			TabW = 64, TabH = 56, TabIcon = 22, TabLabel = 15, Pad = 8 },
	},
	-- the cards of Packs / Passes / Boosts (the Store's numbers)
	PHONE = { Gap = 8, Hero = 150, Card = 108, Art = 120, Pad = 8, Name = 24, Line = 16, Status = 15, Price = 20, BuyW = 150, BuyH = 48, BuyText = 20, Soon = 20 },
	PC = { Gap = 12, Hero = 250, Card = 150, Art = 210, Pad = 14, Name = 32, Line = 22, Status = 20, Price = 28, BuyW = 220, BuyH = 60, BuyText = 26, Soon = 30 },
	PORTRAIT = {
		Gap = 8, Art = 64, HeroArt = 84, Pad = 8, Name = 20, NameRows = 2, Line = 15, LineRows = 3, Status = 15, StatusRows = 3,
		Price = 20, PriceW = 92, BuyW = 104, BuyH = 44, BuyText = 18, Soon = 20,
	},
}

local Colors = Theme.Colors
local WHITE = Colors.White
local MUTED = Colors.Muted or Colors.CloudShade
local GOLD = Theme.Neon.Gold
local TAB_COLORS = { Eggs = "Green", Gems = "Blue", Packs = "Gold", Passes = "Purple", Boosts = "Pink" }
local CLOSE_GLYPH = "\226\156\149"

-- every pack's own colours (the owner's note, 2026-11-04): Top -> Bottom is the card's gradient (saturated, the Bottom
-- dark enough for white text), Edge its neon stroke and glow. No two packs share a pair.
local PALETTE = {
	Starter = { Top = rgb(255, 150, 30), Bottom = rgb(150, 40, 10), Edge = rgb(255, 214, 90) }, -- sunrise orange
	Pro = { Top = rgb(200, 70, 255), Bottom = rgb(70, 15, 140), Edge = rgb(255, 140, 255) }, -- royal purple
	VIP = { Top = rgb(255, 196, 40), Bottom = rgb(140, 70, 0), Edge = rgb(255, 236, 150) }, -- crown gold
	Cash2x = { Top = rgb(50, 215, 100), Bottom = rgb(5, 100, 45), Edge = rgb(150, 255, 170) }, -- money green
	PetXp2x = { Top = rgb(40, 190, 255), Bottom = rgb(15, 60, 170), Edge = rgb(150, 225, 255) }, -- sky blue
	XpPotion1 = { Top = rgb(255, 80, 170), Bottom = rgb(130, 15, 90), Edge = rgb(255, 170, 220) }, -- bubblegum
	XpPotion3 = { Top = rgb(140, 90, 255), Bottom = rgb(45, 20, 150), Edge = rgb(190, 160, 255) }, -- violet brew
	Tokens1 = { Top = rgb(90, 190, 255), Bottom = rgb(20, 80, 180), Edge = rgb(150, 220, 255) }, -- cloud blue
	Tokens2 = { Top = rgb(40, 210, 215), Bottom = rgb(5, 95, 120), Edge = rgb(150, 255, 245) }, -- lagoon
	Tokens3 = { Top = rgb(90, 110, 255), Bottom = rgb(30, 25, 160), Edge = rgb(170, 185, 255) }, -- storm cobalt
	Gems1 = { Top = rgb(50, 225, 160), Bottom = rgb(5, 110, 85), Edge = rgb(165, 255, 215) }, -- emerald
	Gems2 = { Top = rgb(255, 55, 95), Bottom = rgb(140, 10, 45), Edge = rgb(255, 160, 180) }, -- ruby
	Gems3 = { Top = rgb(190, 80, 255), Bottom = rgb(85, 15, 160), Edge = rgb(220, 150, 255) }, -- amethyst
	Gems4 = { Top = rgb(255, 130, 40), Bottom = rgb(175, 25, 120), Edge = rgb(255, 215, 130) }, -- fire opal
	Cash1 = { Top = rgb(130, 220, 60), Bottom = rgb(45, 110, 15), Edge = rgb(200, 255, 150) }, -- (not on sale: 13b.1)
	Cash2 = { Top = rgb(200, 225, 50), Bottom = rgb(100, 115, 5), Edge = rgb(240, 255, 150) },
	Cash3 = { Top = rgb(60, 200, 130), Bottom = rgb(10, 95, 55), Edge = rgb(170, 255, 205) },
}
local DIM_PALETTE = { Top = rgb(120, 124, 140), Bottom = rgb(45, 48, 60), Edge = rgb(150, 155, 170) } -- a Have-it card
local HERO_LIFT = 0.7 -- the hero's highlight stop (right, behind the price and Buy): Top this far toward white
local HERO_EDGE = 4.5 -- the hero's neon stroke (a card's is NeonKit's 3)
local CARD_EDGE = 3
local CARD_CORNER = 14 -- NeonKit.Card's default corner (the Paint frame follows it)

-- the store_* render of each item (spec 9; TextureIds keys, the glyph while a key has no id)
local ART_KEYS = {
	Starter = "store_starter", Pro = "store_pro", VIP = "store_vip", Cash2x = "store_x2cash", PetXp2x = "store_x2xp",
	XpPotion1 = "store_potion_1h", XpPotion3 = "store_potion_3h",
}

local initialized = false
local LocalPlayer = nil
local U = { Tabs = {}, Pages = {}, Cards = {} } -- widgets
local S = {
	Open = false,
	Built = false,
	Token = 0,
	Tab = nil,
	Mode = "PC", -- NeonKit.BigRect's mode ("PC" | "Phone")
	Layout = "PC", -- "PC" | "Compact" | "Phone" | "Portrait"
	Scale = 1,
	Rect = nil,
	Items = {}, -- the card items shown (Packs / Passes / Boosts), in catalog order
	GemItems = {}, -- the Gems tab's items (always shown)
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
ShopController._S = S
local H = {}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[ShopController] " .. tostring(key) .. ": " .. tostring(err))
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

-- a purchase toast: the Store's "Thank you! ..." (StoreService.Thank) or a gem pack's "+550 Gems! Thank you for your
-- support!" (GemService.sendThanks)
function H.isThanks(message)
	if type(message) ~= "string" then
		return false
	end
	return message:sub(1, 9) == "Thank you" or string.match(message, "^%+[%d,]+ Gems! Thank you") ~= nil
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

-- shared/TextureIds (the upload session fills it; empty = every card keeps its glyph)
local function textureIds()
	if S.TextureIds == nil then
		local ok, ids = pcall(function()
			return require(Shared:FindFirstChild("TextureIds"))
		end)
		S.TextureIds = (ok and type(ids) == "table") and ids or {}
	end
	return S.TextureIds
end

-- the optional client/MouseLock (nil when missing)
function H.mouseLock()
	local module = Client:FindFirstChild("MouseLock")
	local ok, mod = pcall(function()
		return module and require(module)
	end)
	return (ok and type(mod) == "table" and type(mod.WatchVisible) == "function") and mod or nil
end

----------------------------------------------------------------------
-- What is shown
----------------------------------------------------------------------
function H.preview()
	return H.attr("StorePreview") == true
end

-- the card items shown (created, or every one under StorePreview) and the Gems tab's items (always); the Eggs tab has none
function H.collect()
	local preview = H.preview()
	local items, gems, byKey, sig = {}, {}, {}, { preview and "P" or "-" }
	for _, item in ipairs(StoreCatalog.List()) do
		byKey[item.Key] = item
		if item.Tab == "Gems" then
			gems[#gems + 1] = item
		elseif item.Tab ~= "Eggs" and (item.Created or preview) then
			items[#items + 1] = item
			sig[#sig + 1] = item.Key .. ":" .. tostring(item.Id)
		end
	end
	return items, gems, byKey, table.concat(sig, "|")
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

-- lobby-shop 16.1: the lock text while PaidRandomItemsRestricted is not false (true: restricted; absent: unknown), else nil
function H.lockText()
	local flag = LocalPlayer and LocalPlayer:GetAttribute(K.RESTRICTED_ATTR)
	if flag == false then
		return nil
	end
	return flag == true and K.LOCK or K.CHECKING
end

function H.timeLeft(seconds)
	local minutes = math.max(1, math.ceil(seconds / 60))
	if minutes >= 60 then
		return string.format("%d h %d m left", math.floor(minutes / 60), minutes % 60)
	end
	return string.format("%d m left", minutes)
end

-- -> state, status text (known = the StoreBought attribute exists: a real record is loaded)
function H.stateOf(item, owned, bought, xpPass, known, lock)
	if not item.Created then
		return "Preview", ""
	end
	if item.Once and not known then
		return "Loading", ""
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
	if lock and type(item.Grants) == "table" and (tonumber(item.Grants.Tokens) or 0) > 0 then
		return "Locked", lock
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

-- the StoreBought attribute exists (absent = the record is loading or provisional: no Once pack can be decided)
function H.boughtKnown()
	return type(H.attr("StoreBought")) == "string"
end

function H.windowHero()
	local bought = csvSet(H.attr("StoreBought"))
	local starter = S.ByKey.Starter
	if starter and (starter.Created or H.preview()) and H.boughtKnown() and not bought.Starter then
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
	local shown = {}
	for _, item in ipairs(H.tabItems(tab)) do
		shown[item.Key] = true
	end
	if hero and hero.Tab == tab and shown[hero.Key] then
		return hero
	end
	for _, item in ipairs(H.tabItems(tab)) do
		local st = S.States[item.Key]
		if item.Hero and not (st and (st.State == "Owned" or st.State == "Claimed" or st.State == "Loading")) then
			return item
		end
	end
	return nil
end

-- the heroes of every card tab, as a string: a change (a pack bought, the record arriving) rebuilds the pages
function H.heroSignature()
	local parts = {}
	for _, tab in ipairs({ "Packs", "Passes", "Boosts" }) do
		local hero = H.heroOf(tab)
		parts[#parts + 1] = hero and hero.Key or "-"
	end
	return table.concat(parts, "|")
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
	for _, list in ipairs({ S.Items, S.GemItems }) do
		for _, item in ipairs(list) do
			if item.Created and not S.Asked[item.Id] then
				S.Asked[item.Id] = true
				H.fetchPrice(item, false)
			end
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
	local holder = frame("ShopWindow", U.Gui, { Visible = false, Active = true })
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	-- the frame: the navy panel with the A outline
	local panel = frame("Panel", holder, { BackgroundTransparency = 0, BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1) })
	Theme.Corner(panel, UDim.new(0, 18))
	Util.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Colors.PanelTop or rgb(26, 32, 72), Colors.PanelBottom or rgb(12, 15, 38)), Parent = panel })
	Theme.Stroke(panel, K.NAVY, 3, 0)

	-- the header: the accent band, the egg, "Shop", the two balances, the X
	local header = frame("Header", holder)
	U.Header = header
	U.Band = frame("Band", header, { BackgroundTransparency = 0, BackgroundColor3 = K.ACCENT })
	Theme.Corner(U.Band, UDim.new(0, 18))
	Util.Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Theme.Lighten(K.ACCENT, 0.15), Theme.Darken(K.ACCENT, 0.45)), Parent = U.Band })
	U.Icon = label("Icon", header, NeonKit.Glyphs.Eggs, "Display", 42, { TextTruncate = Enum.TextTruncate.None })
	U.Title = label("Title", header, "Shop", "Title", 34, { TextXAlignment = Enum.TextXAlignment.Left })
	local function pill(id)
		local cur = Theme.Currency[id]
		local root = frame("Balance_" .. id, header, { BackgroundTransparency = 0.15, BackgroundColor3 = Colors.PanelInk or K.NAVY })
		Theme.Corner(root, UDim.new(0.5, 0))
		Theme.Stroke(root, cur.Color, 2, 0.1)
		return root, cur
	end
	U.GemsPill = pill("Gems")
	U.GemsAmount = GemIcon.Amount(U.GemsPill, "0", { TextSize = 22 })
	U.GemsAmount.AnchorPoint = Vector2.new(0.5, 0.5)
	U.GemsAmount.Position = UDim2.fromScale(0.5, 0.5)
	local tokPill, tokCur = pill("Tokens")
	U.TokPill = tokPill
	U.TokGlyph = label("Glyph", tokPill, tokCur.Glyph, "Display", 22, { TextColor3 = tokCur.Color, TextTruncate = Enum.TextTruncate.None })
	U.TokText = label("Text", tokPill, "0", "Display", 22, { TextXAlignment = Enum.TextXAlignment.Left })
	U.Close = CloudUI.Button({
		Name = "CloseButton",
		Text = CLOSE_GLYPH,
		Style = "Red",
		Size = UDim2.fromOffset(44, 44),
		TextSize = 22,
		Callback = function()
			ShopController.Close()
		end,
		Parent = header,
	})

	-- the rail
	local rail = frame("Rail", holder)
	U.Rail = rail
	for i, tab in ipairs(K.TABS) do
		local button = Instance.new("TextButton")
		button.Name = "Tab_" .. tab
		button.Text = ""
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.BackgroundColor3 = Theme.Darken(Theme.NeonColor(TAB_COLORS[tab]), 0.55)
		button.LayoutOrder = i
		Theme.Corner(button, UDim.new(0, 12))
		local outline = Theme.Stroke(button, Theme.NeonColor(TAB_COLORS[tab]), 2, 0.2)
		local name = label("Label", button, tab, "Button", 26, { TextXAlignment = Enum.TextXAlignment.Left })
		button.Parent = rail
		button.Activated:Connect(function()
			safe("tab", H.tapTab, tab)
		end)
		U.Tabs[tab] = { Button = button, Label = name, Stroke = outline }
	end
	U.Dot = frame("Dot", U.Tabs.Packs.Button, { BackgroundTransparency = 0, BackgroundColor3 = GOLD, Visible = false, ZIndex = 3 })
	Theme.Corner(U.Dot, UDim.new(0.5, 0))
	Theme.Stroke(U.Dot, WHITE, 2, 0) -- (a white ring: the gold dot reads on the gold Packs tab)
	U.Divider = frame("RobuxDivider", rail)
	U.DivGlyph = label("Glyph", U.Divider, robuxGlyph(), "Display", 24, { TextColor3 = rgb(120, 230, 140), TextTruncate = Enum.TextTruncate.None })
	U.DivLabel = label("Label", U.Divider, "Robux items", "Body", 18, { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MUTED })
	U.DivLine = frame("Line", U.Divider, { BackgroundTransparency = 0.4, BackgroundColor3 = MUTED })
	-- the Fast hatch toggle (Eggs only): a TextButton with its Label and a Switch (Knob); attribute On
	local fast = Instance.new("TextButton")
	fast.Name = "FastHatch"
	fast.Text = ""
	fast.AutoButtonColor = false
	fast.BorderSizePixel = 0
	fast.BackgroundColor3 = Colors.PanelInk or K.NAVY
	fast.BackgroundTransparency = 0.15
	fast.Visible = false
	Theme.Corner(fast, UDim.new(0, 12))
	Theme.Stroke(fast, Theme.NeonColor("Green"), 2, 0.3)
	U.FastLabel = label("Label", fast, "Fast hatch", "Button", 20, { TextXAlignment = Enum.TextXAlignment.Left })
	U.FastSwitch = frame("Switch", fast, { BackgroundTransparency = 0, BackgroundColor3 = MUTED })
	Theme.Corner(U.FastSwitch, UDim.new(0.5, 0))
	Theme.Stroke(U.FastSwitch, K.NAVY, 2, 0)
	U.FastKnob = frame("Knob", U.FastSwitch, { BackgroundTransparency = 0, BackgroundColor3 = WHITE })
	Theme.Corner(U.FastKnob, UDim.new(0.5, 0))
	fast.Parent = rail
	fast.Activated:Connect(function()
		safe("fast hatch", H.toggleFast)
	end)
	U.Fast = fast

	-- the body (the content box): the Eggs page, the Gems page and the card pages
	local body = frame("Body", holder, { ClipsDescendants = true })
	U.Body = body
	local eggsPage = frame("Page_Eggs", body, { Visible = false })
	U.EggsPage = eggsPage
	ShopEggs.Build(eggsPage, {
		Tap = function()
			sfx("StorePop", "Click")
		end,
		-- (shop-area 16.17.3) the Secret card's TRAVEL closes the Shop once it has asked for the trip
		Close = function()
			ShopController.Close()
		end,
	})
	local gemsPage = frame("Page_Gems", body, { Visible = false })
	U.GemsPage = gemsPage
	ShopGems.Build(gemsPage, {
		Buy = function(key)
			safe("buy", H.buy, key)
		end,
		GemBuy = function()
			safe("gem buy", H.gemBuy)
		end,
		Palette = function(key)
			return ShopController.Palette(key)
		end,
		Price = function(item)
			return item.Created and S.Prices[item.Id] or nil
		end,
		Robux = robuxGlyph,
		Preview = H.preview,
		State = function(key)
			local st = S.States[key]
			return st and st.State or "Preview"
		end,
		LockText = H.lockText,
	})
	U.Soon = label("Soon", body, K.SOON, "Heading", 30, { Visible = false, TextWrapped = true, Size = UDim2.fromScale(1, 1) })
	local ml = H.mouseLock()
	if ml then
		safe("mouse lock", ml.WatchVisible, "Shop", holder)
	end
end

-- the tab's icon through NeonKit.Icon (the only path that reads Config.Icons): rebuilt when Config.Icons[tab] or the size
-- changed
function H.syncTabIcon(tab, px)
	local t = U.Tabs[tab]
	local icons = Config.Icons
	local want = type(icons) == "table" and icons[tab] or nil
	if type(want) ~= "string" or want == "" then
		want = false
	end
	if t.Icon and t.IconImage == want and t.IconPx == px then
		return
	end
	if t.Icon then
		t.Icon:Destroy()
	end
	t.Icon = NeonKit.Icon(t.Button, tab, px)
	t.IconImage = want
	t.IconPx = px
end

-- the pack's colours (a key without an entry: its tab's neon colour)
function H.palette(item)
	local p = PALETTE[item.Key]
	if p then
		return p
	end
	local c = Theme.NeonColor(TAB_COLORS[item.Tab] or "Blue")
	return { Top = c, Bottom = Theme.Darken(c, 0.6), Edge = Theme.Lighten(c, 0.3) }
end

-- paints a card: the gradient on its Paint frame, the edge on its neon stroke and glow (the hero brighter and thicker)
function H.paint(entry, dim)
	local p = dim and DIM_PALETTE or H.palette(entry.Item)
	local keys
	local rotation = 90
	if entry.Hero and not dim then
		-- left to right: the dark stop under the art and the texts, the highlight behind the price pill and Buy
		keys = {
			ColorSequenceKeypoint.new(0, p.Bottom),
			ColorSequenceKeypoint.new(0.5, p.Top),
			ColorSequenceKeypoint.new(1, p.Top:Lerp(WHITE, HERO_LIFT)),
		}
		rotation = 12
	else
		keys = { ColorSequenceKeypoint.new(0, p.Top), ColorSequenceKeypoint.new(1, p.Bottom) }
	end
	entry.PaintGradient.Color = ColorSequence.new(keys)
	entry.PaintGradient.Rotation = rotation
	entry.Card.SetColor(p.Edge)
	entry.Card.Stroke.Thickness = entry.Hero and HERO_EDGE or CARD_EDGE
	entry.Art.BackgroundColor3 = Theme.Darken(p.Bottom, 0.35)
end

-- the art box shows the render (Image) or the glyph, unless a pet viewport covers it (High)
function H.showArt(entry, on)
	if entry.Image then
		entry.Image.Visible = on
		entry.Glyph.Visible = false
	else
		entry.Glyph.Visible = on
	end
end

function H.artKey(item)
	if ART_KEYS[item.Key] then
		return ART_KEYS[item.Key]
	end
	local kind, n = string.match(item.Key, "^(%a+)(%d+)$")
	if kind == "Gems" or kind == "Tokens" or kind == "Cash" then
		return "store_" .. string.lower(kind) .. "_" .. n
	end
	return nil
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
	-- the pack's own gradient: a Paint frame under the Body (the root is a TextButton, whose own gradient is NeonKit's)
	card.Root.BackgroundTransparency = 1
	local paint = frame("Paint", card.Root, {
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = card.Root.ZIndex - 1,
	})
	Theme.Corner(paint, UDim.new(0, CARD_CORNER))
	local paintGradient = Util.Create("UIGradient", { Name = "PaintGradient", Rotation = 90, Parent = paint })
	card.Root.Activated:Connect(function()
		sfx("StorePop", "Click")
	end)
	local b = card.Body
	local art = frame("Art", b, { BackgroundTransparency = 0.35, BackgroundColor3 = Theme.Darken(H.palette(item).Bottom, 0.35) })
	Theme.Corner(art, UDim.new(0, 12))
	local glyph = label("Glyph", art, H.artGlyph(item), "Display", 40, { Size = UDim2.fromScale(1, 1), TextTruncate = Enum.TextTruncate.None })
	local image = nil
	local artKey = H.artKey(item)
	local artId = artKey and tonumber(textureIds()[artKey]) or nil
	if artId and artId > 0 and artId == math.floor(artId) then
		image = Util.Create("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = "rbxassetid://" .. tostring(artId),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			Parent = art,
		})
		glyph.Visible = false
	end
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
		Item = item, Card = card, Root = card.Root, Art = art, Glyph = glyph, Image = image, Name = name, GetsYou = gets,
		Lines = lines, Status = status, PricePill = pricePill, Price = price, BuyHolder = buyHolder, Pulse = pulse, Buy = buy,
		Hero = isHero == true, Paint = paint, PaintGradient = paintGradient,
	}
	H.paint(entry, false)
	U.Cards[item.Key] = entry
	return entry
end

function H.artGlyph(item)
	local G = NeonKit.Glyphs
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

-- (re)builds every card page when the shown set changed
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
	for i, tab in ipairs({ "Packs", "Passes", "Boosts" }) do
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
		page.Parent = U.Body
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
	if wasShine and S.Open then
		H.shineOn()
	end
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
function H.cardMetrics()
	if S.Layout == "Portrait" then
		return K.PORTRAIT
	end
	return S.Layout == "Phone" and K.PHONE or K.PC
end

function H.layoutCard(entry, w, h, M)
	local pad = M.Pad
	place(entry.Root, entry.Root.Position.X.Offset, entry.Root.Position.Y.Offset, w, h)
	-- one line each (a portrait layout before may have wrapped them)
	entry.Name.TextWrapped = false
	entry.GetsYou.TextWrapped = false
	entry.Status.TextWrapped = false
	for _, line in ipairs(entry.Lines) do
		line.TextWrapped = false
	end
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
	-- a locked card says why first (lobby-shop 16.1), the lines that no longer fit step aside
	if statusOn and entry.StatusFirst then
		place(entry.Status, textX, y, textW, M.Status + 3)
		y = y + M.Status + 3
		getsOn = false
	end
	entry.GetsYou.Visible = getsOn
	if getsOn then
		place(entry.GetsYou, textX, y, textW, lineH)
		entry.GetsYou.TextSize = M.Line
		y = y + lineH
	end
	for _, line in ipairs(entry.Lines) do
		place(line, textX, y, textW, lineH)
		line.TextSize = M.Line
		line.Visible = not entry.StatusFirst or y + lineH <= h - pad + 2
		y = y + lineH
	end
	if not entry.StatusFirst then
		place(entry.Status, textX, y, textW, M.Status + 3)
	end
	entry.Status.TextSize = M.Status
	entry.Status.Visible = statusOn
end

-- the rows `text` wraps to at `size` in `width` px (TextService measures the real font; 1 when it cannot)
local function rowsOf(lbl, text, size, width)
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, lbl.Font, Vector2.new(width, 10000))
	end)
	if not ok or typeof(v) ~= "Vector2" or v.Y <= 0 then
		return 1
	end
	return math.max(1, math.floor(v.Y / size + 0.5))
end

-- a portrait card (w wide): the art left of the texts, each text as many rows as it needs (up to its cap), the price
-- pill and Buy on a row under both; answers the card's height
function H.layoutCardPortrait(entry, w, M)
	local pad = M.Pad
	local art = entry.Hero and M.HeroArt or M.Art
	local textX = pad + art + pad
	local textW = w - textX - pad
	local y = pad
	local function put(lbl, size, maxRows, lineH)
		lbl.TextSize = size
		local rows = math.min(maxRows, rowsOf(lbl, lbl.Text, size, textW))
		lbl.TextWrapped = rows > 1
		place(lbl, textX, y, textW, rows * lineH)
		y = y + rows * lineH
	end
	put(entry.Name, M.Name, M.NameRows, M.Name + 2)
	y = y + 2
	local statusOn = entry.Status.Text ~= ""
	entry.Status.Visible = statusOn
	if statusOn and entry.StatusFirst then
		put(entry.Status, M.Status, M.StatusRows, M.Status + 3)
	end
	entry.GetsYou.Visible = #entry.Lines > 0
	if entry.GetsYou.Visible then
		put(entry.GetsYou, M.Line, 1, M.Line + 3)
	end
	for _, line in ipairs(entry.Lines) do
		line.Visible = true
		put(line, M.Line, M.LineRows, M.Line + 3)
	end
	if statusOn and not entry.StatusFirst then
		put(entry.Status, M.Status, M.StatusRows, M.Status + 3)
	end
	place(entry.Art, pad, pad, art, art)
	entry.Glyph.TextSize = math.min(100, math.max(20, math.floor(art * 0.5)))
	local rowY = math.max(y, pad + art) + 6
	local buyX = w - pad - M.BuyW
	place(entry.BuyHolder, buyX, rowY, M.BuyW, M.BuyH)
	entry.Buy.TextSize = M.BuyText
	local pillH = M.Price + 8
	place(entry.PricePill.Root, buyX - 8 - M.PriceW, rowY + math.floor((M.BuyH - pillH) / 2), M.PriceW, pillH)
	entry.Price.TextSize = M.Price
	local h = rowY + M.BuyH + pad
	place(entry.Root, entry.Root.Position.X.Offset, entry.Root.Position.Y.Offset, w, h)
	return h
end

-- the header (W wide): the accent band, the egg, "Shop", the balances right of it, the X; portrait: two rows
function H.layoutHeader(W, R)
	local portrait = S.Layout == "Portrait"
	place(U.Header, 0, 0, W, R.Header)
	place(U.Band, 0, 0, W, portrait and R.Row or R.Header)
	local closeY = portrait and 0 or math.floor((R.Header - R.Close) / 2)
	place(U.Close, W - R.Close - (portrait and 3 or 10), closeY, R.Close, R.Close)
	U.Close.TextSize = math.floor(R.Close * 0.5)
	local rowH = portrait and R.Row or R.Header
	place(U.Icon, portrait and 8 or 14, (rowH - R.Icon) / 2, R.Icon + 4, R.Icon)
	U.Icon.TextSize = R.Icon
	U.Title.TextSize = R.TitleText
	local gw, tw, py
	if portrait then
		place(U.Title, 44, 0, W - 44 - R.Close - 8, R.Row)
		gw = math.floor((W - 2 * 8 - 8) / 2)
		tw = gw
		py = R.Row + 4
		place(U.GemsPill, 8, py, gw, R.PillH)
		place(U.TokPill, 8 + gw + 8, py, tw, R.PillH)
	else
		place(U.Title, R.Icon + 26, 0, R.TitleW, R.Header)
		gw, tw = R.GemsW, R.TokW
		py = math.floor((R.Header - R.PillH) / 2)
		local tokX = W - R.Close - 10 - 12 - tw
		place(U.TokPill, tokX, py, tw, R.PillH)
		place(U.GemsPill, tokX - 10 - gw, py, gw, R.PillH)
	end
	GemIcon.SetAmount(U.GemsAmount, nil, { TextSize = R.PillText })
	place(U.TokGlyph, 8, 0, R.PillText + 6, R.PillH)
	U.TokGlyph.TextSize = R.PillText
	place(U.TokText, R.PillText + 18, 0, tw - R.PillText - 24, R.PillH)
	U.TokText.TextSize = R.PillText
end

-- the rail: PC / Compact / Phone a column at RailX; portrait one row of five tabs; answers the rail's bottom (portrait)
function H.layoutRail(W, Hh, R)
	local layout = S.Layout
	if layout == "Portrait" then
		local pad = R.Pad
		local gap = math.max(0, (W - 2 * pad - #K.TABS * R.TabW) / (#K.TABS - 1))
		place(U.Rail, 0, R.Header + 4, W, R.TabH)
		for i, tab in ipairs(K.TABS) do
			local t = U.Tabs[tab]
			place(t.Button, pad + (i - 1) * (R.TabW + gap), 0, R.TabW, R.TabH)
			H.syncTabIcon(tab, R.TabIcon)
			place(t.Icon, 0, 3, R.TabW, R.TabIcon + 4)
			place(t.Label, 2, R.TabIcon + 8, R.TabW - 4, R.TabH - R.TabIcon - 10)
			t.Label.TextSize = R.TabLabel
			t.Label.TextXAlignment = Enum.TextXAlignment.Center
		end
		U.Divider.Visible = false
		place(U.Dot, R.TabW - 15, 3, 12, 12)
		H.layoutFast(nil)
		return R.Header + 4 + R.TabH
	end
	local bodyH = Hh - R.Header
	local tabH, tabY, step = R.TabH, R.TabY, R.TabStep
	if layout == "Phone" and bodyH < R.ShortBody then
		tabH, tabY, step = R.ShortTabH, R.ShortTabY, R.ShortTabStep
	end
	place(U.Rail, 0, R.Header, R.RailX + R.RailW + 8, bodyH)
	for i, tab in ipairs(K.TABS) do
		local t = U.Tabs[tab]
		local y = tabY + (i - 1) * step + (i >= 3 and R.Split or 0)
		place(t.Button, R.RailX, y, R.RailW, tabH)
		H.syncTabIcon(tab, R.TabIcon)
		t.Label.TextSize = R.TabLabel
		if layout == "Compact" then
			-- the icon over the label
			place(t.Icon, 0, 6, R.RailW, R.TabIcon + 8)
			place(t.Label, 2, R.TabIcon + 16, R.RailW - 4, tabH - R.TabIcon - 20)
			t.Label.TextXAlignment = Enum.TextXAlignment.Center
		else
			local ix = layout == "PC" and 16 or 8
			place(t.Icon, ix, (tabH - R.TabIcon - 4) / 2, R.TabIcon + 4, R.TabIcon + 4)
			place(t.Label, ix + R.TabIcon + 10, 0, R.RailW - ix - R.TabIcon - 14, tabH)
			t.Label.TextXAlignment = Enum.TextXAlignment.Left
		end
	end
	-- the divider between Gems and Packs: PC "Robux items", Compact / Phone a 2 px line in the gap
	U.Divider.Visible = true
	local gemsBottom = tabY + step + tabH
	local packsTop = tabY + 2 * step + R.Split
	if layout == "PC" then
		place(U.Divider, R.RailX, gemsBottom + 12, R.RailW, 40)
		place(U.DivGlyph, 8, 0, 30, 40)
		U.DivGlyph.Text = robuxGlyph()
		place(U.DivLabel, 44, 0, R.RailW - 48, 40)
		U.DivGlyph.Visible, U.DivLabel.Visible, U.DivLine.Visible = true, true, false
	else
		local mid = math.floor((gemsBottom + packsTop) / 2)
		place(U.Divider, R.RailX, mid - 1, R.RailW, 2)
		place(U.DivLine, math.floor(R.RailW * 0.1), 0, math.floor(R.RailW * 0.8), 2)
		U.DivGlyph.Visible, U.DivLabel.Visible, U.DivLine.Visible = false, false, true
	end
	place(U.Dot, R.RailW - 20, 6, 14, 14)
	H.layoutFast(layout ~= "Phone" and { R = R, BodyH = bodyH } or nil)
	return R.Header
end

-- the Fast hatch toggle at the rail's bottom (PC / Compact; nil = none on this layout); shown on the Eggs tab only
function H.layoutFast(at)
	U.FastAt = at
	if not at then
		U.Fast.Visible = false
		return
	end
	local F = K.FAST[S.Layout] or K.FAST.PC
	local R = at.R
	place(U.Fast, R.RailX, at.BodyH - F.H - 16, F.W, F.H)
	U.FastLabel.TextSize = F.Text
	if S.Layout == "Compact" then
		place(U.FastSwitch, (F.W - F.SwitchW) / 2, 6, F.SwitchW, F.SwitchH)
		place(U.FastLabel, 2, F.SwitchH + 8, F.W - 4, F.H - F.SwitchH - 10)
		U.FastLabel.TextXAlignment = Enum.TextXAlignment.Center
	else
		place(U.FastLabel, 14, 0, F.W - F.SwitchW - 28, F.H)
		place(U.FastSwitch, F.W - F.SwitchW - 12, (F.H - F.SwitchH) / 2, F.SwitchW, F.SwitchH)
		U.FastLabel.TextXAlignment = Enum.TextXAlignment.Left
	end
	H.paintFast()
end

function H.paintFast()
	local on = false
	pcall(function()
		on = ClientSettings.Get("FastHatch") == true
	end)
	U.Fast:SetAttribute("On", on)
	U.Fast.Visible = U.FastAt ~= nil and S.Tab == "Eggs"
	local F = K.FAST[S.Layout] or K.FAST.PC
	local k = F.SwitchH - 6
	place(U.FastKnob, on and (F.SwitchW - k - 3) or 3, 3, k, k)
	U.FastSwitch.BackgroundColor3 = on and Theme.NeonColor("Green") or MUTED
end

function H.toggleFast()
	sfx("StorePop", "Click")
	local on = ClientSettings.Get("FastHatch") == true
	ClientSettings.Set("FastHatch", not on) -- (one SettingsSet 0.4 s later; Changed repaints)
	H.paintFast()
end

function H.layoutCardPages(cw, ch)
	local M = H.cardMetrics()
	U.Soon.TextSize = M.Soon
	local w = cw - K.SCROLLBAR - 2
	for tab, page in pairs(U.Pages) do
		place(page, 0, 0, cw, ch)
		local list = {}
		for _, entry in pairs(U.Cards) do
			if entry.Item.Tab == tab then
				list[#list + 1] = entry
			end
		end
		table.sort(list, function(a, b)
			return (a.Order or 0) < (b.Order or 0)
		end)
		-- (a gap under the header, as the Gems page's hero at y 16; none in portrait, under the tab row)
		local top = S.Layout == "Portrait" and 0 or (S.Layout == "Phone" and 6 or 16)
		local cy = top
		for _, entry in ipairs(list) do
			entry.Root.Position = UDim2.fromOffset(0, cy)
			if S.Layout == "Portrait" then
				cy = cy + H.layoutCardPortrait(entry, w, M) + M.Gap
			else
				local h = entry.Hero and M.Hero or M.Card
				H.layoutCard(entry, w, h, M)
				cy = cy + h + M.Gap
			end
		end
		page.CanvasSize = UDim2.fromOffset(0, math.max(0, cy - M.Gap + top))
	end
end

function H.layout()
	if not S.Built then
		return
	end
	local r = NeonKit.BigRect(K)
	S.Rect = r
	S.Mode, S.Scale = r.mode, r.scale
	local W = math.floor(r.w / r.scale + 0.5)
	local Hh = math.floor(r.h / r.scale + 0.5)
	if r.mode == "Phone" then
		S.Layout = r.portrait and "Portrait" or "Phone"
	else
		S.Layout = W < K.COMPACT_W and "Compact" or "PC"
	end
	S.Portrait = S.Layout == "Portrait"
	local R = K.WIN[S.Layout]
	place(U.Holder, r.x, r.y, W, Hh)
	U.Fit.Scale = r.scale
	H.layoutHeader(W, R)
	local top = H.layoutRail(W, Hh, R)
	local bx, bw, by
	if S.Layout == "Portrait" then
		bx, bw, by = R.Pad, W - 2 * R.Pad, top + 8
	else
		bx, bw, by = R.ContentX, W - R.ContentX - R.ContentR, top
	end
	-- the body runs to the window's bottom (spec 16.3: 280 under the 50 px header at 844x390, 834 under 76 at 1920x1080)
	local bh = Hh - by - (S.Layout == "Portrait" and R.Pad or 0)
	place(U.Body, bx, by, bw, bh)
	H.layoutCardPages(bw, bh)
	safe("gems layout", ShopGems.Layout, U.GemsPage, { W = bw, H = bh }, S.Layout)
	place(U.GemsPage, 0, 0, bw, bh)
	place(U.EggsPage, 0, 0, bw, bh)
	safe("eggs layout", ShopEggs.Layout, U.EggsPage, { W = bw, H = bh }, S.Layout)
	H.coverColumn()
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
function H.computeStates()
	local owned = csvSet(H.attr("OwnedPasses"))
	local bought = csvSet(H.attr("StoreBought"))
	local known = H.boughtKnown()
	local xpPass = H.xpPassKey()
	local lock = H.lockText()
	local states = {}
	for _, list in ipairs({ S.Items, S.GemItems }) do
		for _, item in ipairs(list) do
			local st, status = H.stateOf(item, owned, bought, xpPass, known, lock)
			states[item.Key] = { State = st, Status = status }
		end
	end
	S.States = states
end

local BUY_TEXT = { Buy = "Buy", Active = "Buy", Owned = "Owned", Claimed = "Claimed!", HaveIt = "Buy", Preview = "PREVIEW", Loading = "...", Locked = "Locked" }

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
		entry.PricePill.Root.Visible = st.State ~= "Owned" and st.State ~= "Claimed" and st.State ~= "Locked"
		entry.Status.Text = st.Status
		entry.StatusFirst = st.State == "Locked"
		local dim = st.State == "HaveIt"
		H.paint(entry, dim)
		entry.Name.TextColor3 = dim and MUTED or WHITE
		for _, line in ipairs(entry.Lines) do
			line.TextColor3 = dim and MUTED or WHITE
		end
	end
	-- the balances (Theme.ShortNumber from 1e6) and the Starter dot
	local function value(id)
		local fn = State[id]
		local ok, v = pcall(fn)
		return ok and tonumber(v) or 0
	end
	GemIcon.SetAmount(U.GemsAmount, Theme.ShortNumber(value("Gems"), 1e6))
	U.TokText.Text = Theme.ShortNumber(value("Tokens"), 1e6)
	local starter = S.ByKey.Starter
	U.Dot.Visible = starter ~= nil and (starter.Created or H.preview()) and H.boughtKnown() and not csvSet(H.attr("StoreBought")).Starter
	safe("gems refresh", ShopGems.Refresh, U.GemsPage)
	safe("eggs refresh", ShopEggs.Refresh, U.EggsPage)
	H.paintFast()
end

function H.selectTab(tab)
	tab = ShopController.NormalizeTab(tab)
	if tab == nil then
		tab = S.Tab or "Eggs"
	end
	S.Tab = tab
	for name, t in pairs(U.Tabs) do
		local on = name == tab
		t.Button:SetAttribute("Selected", on)
		t.Button.BackgroundColor3 = Theme.Darken(Theme.NeonColor(TAB_COLORS[name]), on and 0.15 or 0.55)
		t.Stroke.Color = on and GOLD or Theme.NeonColor(TAB_COLORS[name])
		t.Stroke.Thickness = on and 3 or 2
	end
	for name, page in pairs(U.Pages) do
		page.Visible = name == tab
	end
	U.GemsPage.Visible = tab == "Gems"
	U.EggsPage.Visible = tab == "Eggs"
	U.Soon.Visible = tab ~= "Gems" and tab ~= "Eggs" and #H.tabItems(tab) == 0
	H.paintFast()
end

-- re-reads the shown set (rebuilds on a change), the states, the prices and the layout
function H.refresh()
	if not S.Built then
		return
	end
	local items, gems, byKey, sig = H.collect()
	S.Items, S.GemItems, S.ByKey = items, gems, byKey
	H.computeStates()
	local heroes = H.heroSignature()
	if sig ~= S.Signature or heroes ~= S.Heroes then
		S.Signature = sig
		S.Heroes = heroes
		H.rebuild()
		if S.Open then
			H.askPrices()
		end
	end
	if S.Tab then
		H.selectTab(S.Tab)
	end
	H.paintCards()
	if S.Open then
		H.askPrices()
		H.layout()
	end
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------
function H.send(action, key)
	local t = os.clock()
	if t - S.LastBuy < K.BUY_GAP then
		return
	end
	S.LastBuy = t
	local remote = H.remote("StoreRequest")
	if remote then
		safe("StoreRequest", function()
			remote:FireServer(action, key)
		end)
	end
end

function H.buy(key)
	sfx("StorePop", "Click")
	if H.inMatch() then
		H.hint(K.MATCH_HINT)
		ShopController.Close()
		return
	end
	local st = S.States[key]
	if not st or not (st.State == "Buy" or st.State == "Active") then
		return
	end
	H.send("Buy", key)
end

-- the gem XP Potion: only "Ready" sends (spec 16.3); "Short" says so
function H.gemBuy()
	sfx("StorePop", "Click")
	if H.inMatch() then
		H.hint(K.MATCH_HINT)
		ShopController.Close()
		return
	end
	local state = ShopGems.PotionState()
	if state == "Short" then
		H.hint(K.SHORT_GEMS)
		return
	end
	if state == "Ready" then
		H.send("GemBuy", K.POTION_KEY)
	end
end

function H.tapTab(tab)
	sfx("StorePop", "Click")
	H.selectTab(tab)
	H.shineOff()
	if S.Open then
		H.layout()
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

-- one 1 -> 1.04 -> 1 pulse of a UIScale (0.3 s each way)
function H.pulse(scale)
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	local ok, tween = pcall(function()
		return game:GetService("TweenService"):Create(scale, info, { Scale = K.PULSE_SCALE })
	end)
	if ok and tween then
		tween:Play()
		H.track(tween)
	end
end

-- true while the Secret card's SPIN can be tapped (ShopEggs.CardState not Locked / Altar / Loading / Pending / NoOdds;
-- shop-area 16.17.3: away from the Storm Altar SPIN is hidden under TRAVEL, so nothing pulses)
function H.eggPulseOn()
	local secret = type(Config.Gems) == "table" and type(Config.Gems.SecretRoulette) == "table" and Config.Gems.SecretRoulette.Id or "Secret"
	local ok, st = pcall(ShopEggs.CardState, secret, "Spin")
	return ok and st ~= "Locked" and st ~= "Altar" and st ~= "Loading" and st ~= "Pending" and st ~= "NoOdds"
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
				ColorSequenceKeypoint.new(0, H.palette(hero.Item).Edge),
				ColorSequenceKeypoint.new(0.5, WHITE),
				ColorSequenceKeypoint.new(1, H.palette(hero.Item).Top),
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
					H.pulse(hero.Pulse)
				end
			end)
		end
	end
	-- the Eggs tab: the Secret card's SPIN pulses the same way (spec 16.3, High only), and only while that button can be
	-- tapped (review round 1: never while it is Locked, Loading, Pending or without odds; checked on every beat, so the
	-- pulse starts by itself when the gem settle hold ends; the scale rests at 1 meanwhile)
	local eggPulse = (high and S.Tab == "Eggs") and ShopEggs.HeroPulse(U.EggsPage) or nil
	if eggPulse then
		local mine = S.Token
		task.spawn(function()
			while S.Open and S.Token == mine and S.Shine == shine do
				task.wait(K.PULSE_EVERY)
				if not (S.Open and S.Token == mine and S.Shine == shine) or eggPulse.Parent == nil then
					break
				end
				if H.eggPulseOn() then
					H.pulse(eggPulse)
				else
					eggPulse.Scale = 1
				end
			end
		end)
	end
	if high then
		-- the pet cards turn their pet (CloudUI.PetViewport) instead of the glyph
		for _, entry in pairs(U.Cards) do
			local pets = type(entry.Item.Grants) == "table" and entry.Item.Grants.Pets or nil
			if type(pets) == "table" and entry.Item.Tab == S.Tab then
				local petId = next(pets)
				local ok, view = pcall(CloudUI.PetViewport, entry.Art, petId, UDim2.fromScale(1, 1), {})
				if ok and type(view) == "table" then
					H.showArt(entry, false)
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
		H.showArt(v.Entry, true)
	end
	for _, entry in pairs(U.Cards) do
		entry.Pulse.Scale = 1
	end
	local eggPulse = ShopEggs.HeroPulse(U.EggsPage)
	if eggPulse then
		eggPulse.Scale = 1
	end
end

----------------------------------------------------------------------
-- Touch controls, the menu column, gamepad B
----------------------------------------------------------------------
-- the phone window fills the screen: Roblox's thumbstick and jump button go while it is up (the PetsController rule),
-- through MenuController's one owner set (who "Shop")
function H.syncTouch()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local want = S.Open and (S.Mode == "Phone" or touchOnly)
	if want == S.TouchOff then
		return
	end
	S.TouchOff = want
	local menu = H.controller("MenuController")
	if menu and type(menu.SetTouchHidden) == "function" then
		safe("touch", menu.SetTouchHidden, "Shop", want)
		return
	end
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
		safe("cover", menu.SetColumnCovered, (S.Open and S.Rect) and S.Rect.x or nil, "Shop")
	end
	H.syncTouch()
end

function H.syncBack()
	if S.Open and not S.BackBound then
		S.BackBound = true
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, function(_, inputState)
				-- (while the egg stage shows B is its own: NimbusHatchBack at High + 1)
				if inputState == Enum.UserInputState.Begin and not EggStage.IsShowing() then
					safe("back", ShopController.Close)
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
function ShopController.NormalizeTab(tab)
	if type(tab) ~= "string" then
		return nil
	end
	local t = tab:lower()
	if t:sub(1, 3) == "egg" or t:sub(1, 4) == "roul" or t == "items" or t == "shop" then
		return "Eggs"
	end
	if t:sub(1, 3) == "gem" or t == "currency" or t == "tokens" then
		return "Gems"
	end
	if t == "packs" then
		return "Packs"
	elseif t == "passes" then
		return "Passes"
	elseif t == "boosts" then
		return "Boosts"
	end
	return nil
end

function ShopController.IsOpen()
	return S.Open
end

function ShopController.Tab()
	return S.Tab
end

function ShopController.Layout()
	if S.Open then
		return S.Layout
	end
	local r = NeonKit.BigRect(K)
	if r.mode == "Phone" then
		return r.portrait and "Portrait" or "Phone"
	end
	return (r.w / r.scale) < K.COMPACT_W and "Compact" or "PC"
end

function ShopController.Portrait()
	return S.Portrait == true
end

function ShopController.RobuxGlyph()
	return robuxGlyph()
end

function ShopController.Cards()
	local out = {}
	for key, entry in pairs(U.Cards) do
		local st = S.States[key]
		out[key] = { State = st and st.State or "Buy", Price = entry.Price.Text, Tab = entry.Item.Tab }
	end
	for _, item in ipairs(S.GemItems) do
		local st = S.States[item.Key]
		local price = item.Created and H.priceText(item) or (item.Robux and (robuxGlyph() .. Util.Commas(item.Robux)) or "...")
		out[item.Key] = { State = st and st.State or "Preview", Price = price, Tab = item.Tab }
	end
	return out
end

function ShopController.Palette(key)
	local item = S.ByKey[key] or StoreCatalog.Item(key)
	if not item then
		return nil
	end
	local p = H.palette(item)
	return { Top = p.Top, Bottom = p.Bottom, Edge = p.Edge }
end

function ShopController.Open(args)
	if not initialized then
		ShopController.Init()
	end
	if not U.Gui then
		return false
	end
	args = type(args) == "table" and args or {}
	if H.inMatch() then
		H.hint(K.MATCH_HINT)
		return false
	end
	if EggStage.IsShowing() then
		return false -- (the stage covers the screen: DONE brings the Shop back)
	end
	local tab = ShopController.NormalizeTab(args.Tab)
	local focus = type(args.RouletteId) == "string" and args.RouletteId or nil
	if focus then
		tab = "Eggs"
	end
	H.build()
	local wasOpen = S.Open
	-- (shop-area 16.17.3) the altar prompt's open unlocks the Secret card until Close; a plain first open clears it
	if args.FromAltar == true or not wasOpen then
		safe("altar", ShopEggs.SetFromAltar, args.FromAltar == true)
	end
	S.Open = true
	if not wasOpen then
		S.Token = S.Token + 1
	end
	H.refresh()
	if tab or not wasOpen then
		H.selectTab(tab)
	end
	U.Holder.Visible = true
	H.layout()
	H.syncBack()
	if focus then
		safe("focus", ShopEggs.Focus, U.EggsPage, focus)
	end
	if not wasOpen then
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
		-- spec 16.3 "WindowOpened": "Shop" (the tutorial's ShopOpened; the menu's windows close on it)
		local menu = H.controller("MenuController")
		if menu and menu.WindowOpened then
			safe("window opened", function()
				menu.WindowOpened:Fire("Shop")
			end)
		end
		safe("toggled", function()
			ShopController.Toggled:Fire(true)
		end)
	else
		H.shineOff()
		H.shineOn()
	end
	return true
end

function ShopController.Close()
	if not S.Open then
		return
	end
	S.Open = false
	S.Token = S.Token + 1
	safe("altar", ShopEggs.SetFromAltar, false)
	H.shineOff()
	if U.Holder then
		U.Holder.Visible = false
	end
	H.syncBack()
	H.coverColumn()
	safe("toggled", function()
		ShopController.Toggled:Fire(false)
	end)
end

function ShopController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)
	robuxGlyph()
	U.Gui = CloudUI.NewScreenGui("NimbusShop", K.DISPLAY_ORDER)
	U.Gui.IgnoreGuiInset = true
	U.Gui.ResetOnSpawn = false
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
	for _, name in ipairs({ "OwnedPasses", "StoreBought", "XpBoostEnds", "StorePreview", "GemsSettled", "XpPassState", K.RESTRICTED_ATTR, "SecretPityLeft" }) do
		LocalPlayer:GetAttributeChangedSignal(Config.Attr[name] or name):Connect(function()
			if S.Open then
				safe("refresh", H.refresh)
			end
		end)
	end
	for _, name in ipairs({ "Gems", "Tokens" }) do
		LocalPlayer:GetAttributeChangedSignal(Theme.Currency[name].Attr):Connect(function()
			if S.Open then
				safe("balances", H.paintCards)
			end
		end)
	end
	LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
		if H.inMatch() then
			ShopController.Close()
		end
	end)
	-- the ONE Esc handler (EggStage has none): while the stage shows, its Back (skip, then DONE) and nothing more; else
	-- Esc closes the open Shop
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.Escape then
			return
		end
		if EggStage.IsShowing() then
			safe("hatch back", EggStage.Back)
		elseif S.Open then
			ShopController.Close()
		end
	end)
	-- one window at a time (spec 8): any other window's opening closes this one
	local menu = H.controller("MenuController")
	if menu and menu.WindowOpened then
		menu.WindowOpened:Connect(function(id)
			if id ~= "Shop" and S.Open then
				ShopController.Close()
			end
		end)
	end
	-- the egg stage (Task 22): the window steps aside while it shows and comes back after DONE (or a phase error) while
	-- the Shop is still open and not in a match; a match start or MenuController.Close() ends both
	EggStage.Init()
	EggStage.Opened:Connect(function()
		if S.Open and U.Holder then
			U.Holder.Visible = false
			H.shineOff()
			H.coverColumn()
		end
	end)
	EggStage.Closed:Connect(function(reason)
		if not S.Open then
			return
		end
		if (reason == "Done" or reason == "Error") and not H.inMatch() then
			if U.Holder then
				U.Holder.Visible = true
			end
			safe("hatch back refresh", H.refresh)
			H.shineOn()
		else
			ShopController.Close()
		end
	end)
	local function repaint()
		if S.Open then
			safe("eggs repaint", H.paintCards)
		end
	end
	EggStage.Pending:Connect(function()
		repaint()
		task.delay(K.HATCH_WAIT, repaint) -- (the stage's 7 s timeout fires no signal)
	end)
	EggStage.Answered:Connect(repaint)
	ClientSettings.Changed:Connect(function(key)
		if key == "FastHatch" and U.Fast then
			H.paintFast()
		end
	end)
	-- the server's thank-you toast for a granted purchase plays the coin clatter
	task.spawn(function()
		local remote = H.remote("Notify")
		if remote then
			remote.OnClientEvent:Connect(function(message)
				if H.isThanks(message) then
					sfx("StoreBuy", "Reward")
				end
			end)
		end
	end)
end

return ShopController
