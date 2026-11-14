-- MenuController (client, v3 + Phase 2): the left menu of icon tiles and every window the player opens.
--
--   MenuController.Init()
--   MenuController.Open(panelId, args)   -- "Pets" | "Index" | "Shop" | "Store" | "Stats" | "Home" | "Settings" (what
--                                           OpenPanel does; args: Tab, RouletteId, Currency = "Gems", Action, Key, Preset,
--                                           Pick, ReturnTo). lobby-shop Task 22: "Shop" and "Store" open ShopController's
--                                           one Shop window (ShopController.Open(args); refused while the egg stage shows).
--                                           Team balance: "Pets", "Team" and "Inventory" open PetsController's window
--                                           (args go to PetsController.Open).
--                                           Phase 4: "Pets" with Action = "Feed" | "Garden", "Feed", "Train" and "Evolve"
--                                           go to CareController (the Food Machine list, the garden picker, the Training
--                                           Place window, the EVOLVE moment); Action = "Evolve" with a Key (the floating
--                                           card's EVOLVE! pill) opens the Pets window on that pet with the EVOLVE confirm
--   MenuController.Close()               -- closes whatever window / overlay is open: the Shop first, then the egg stage
--                                           (EggStage.Close: one "You hatched: ..." toast for the pulls not shown), then
--                                           the menu window, the Pets window and the Pet Index
--   MenuController.OpenSettings()        -- HUD cleanup: MainMenuController's settings panel (the top-left pill's gear,
--                                           TopBarController; a hint until that panel exists)
--   MenuController.OpenTeam(preset)      -- the Pets window showing that team
--   MenuController.WindowOpened          -- Util.Signal, Fire(windowId) whenever a window opens:
--                                           "Pets" (fired by PetsController), "Shop" (ShopController, lobby-shop Task 22;
--                                           "Store" from an old build), "Daily" (DailyController), "Trove"
--                                           (TroveController), "Stats", "Home" or "Index" (the tutorial listens); this
--                                           controller closes its own windows, the Pet Index and the Pets window on
--                                           "Pets", "Shop", "Store", "Daily" and "Trove" (store W1: those never overlap)
--   Extra: MenuController.GetButton(id) -> the MenuButton_<id> tile (or nil; "Home" is the Spot tile)
--          MenuController.IsOpen() -> true while a menu window, the Pets window, the Shop or the egg stage is up
--          MenuController.OpenFeed(key) -> the Food Machine list (CareController) with that pet copy first
--          MenuController.Hint(text, kind) -> the side hint (CareController's local refusals use it)
--          MenuController.SetColumnHidden(hidden) -> hides / shows the menu tiles (BattleController: the team cards
--          take the left edge of a landscape phone during a battle; the column frame keeps its place)
--          MenuController.SetColumnCovered(windowLeft, who) -> a window reaches over the tiles from that screen x (nil =
--          closed): the tiles step aside while ANY window covers them. `who` names the window ("Pets" when left out:
--          PetsController; "Store", "Daily"), so one window closing never brings the tiles back over another one
--          MenuController.SetTouchHidden(who, on) -> Roblox's thumbstick and jump button go while ANY window asked for
--          it (`who` = "Pets" / "Store") and come back as they were when the last one lets go: one owner set, one
--          snapshot taken while no window held them (re-review 2: a window handing over to another never restores a
--          value the other one wrote)
--          MenuController.SetColumnCollapsed(collapsed, animate) / IsColumnCollapsed() -> folds the column against the
--          left edge like its arrow tab does (bug batch 2 #1; remembered for the session)
--
-- Screen: ScreenGui "NimbusMenu" (display order 20, IgnoreGuiInset = false).
--   * Menu column, left-centre (bug batch 2 #1, option A; HUD cleanup): ONE slim column of four square neon tiles
--     with a glyph and a bold label - Pets, Index, Home, Stats - 56 px on a 1080p desktop (Shop / Travel / Settings
--     live in TopBarController's pill in Roblox's top bar; the Items and Team tiles are gone, the battle team is in the
--     Pets window, Open("Team")). Each tile is a TextButton named MenuButton_<Id> (Ids Pets, Index, Spot, Stats: the
--     Home tile keeps the v3 id "Spot" so saved tutorial targets keep working) inside a frame Entry_<Id> of the frame
--     "MenuColumn". The open window's tile glows gold; a red "!" marks new pets and Pet Index rewards waiting to be
--     claimed. A small arrow tab (MenuColumn.Toggle) folds the column against the left edge and back (remembered for
--     the session; the tab repeats a tile's red dot while folded; a tutorial step pointing at a tile unfolds it). On
--     short screens (landscape / portrait phones) the tiles wrap into two slim columns so they stay >= 44 px.
--   * Windows (CloudUI.Panel, centred because the player asked for them, nudged right only when the menu
--     column would cover them): Stats and Home (team balance: the Pets window is PetsController's, shared bits in
--     UI/PetBits; lobby-shop Task 22: the Cloud Shop, its odds popup and its roulette stage left for ShopController's
--     Eggs tab, client/UI/ShopEggs, and client/UI/EggStage). The Pet Index is IndexController's window: the Index tile and
--     OpenPanel("Index") open it. One window at a time; Esc / gamepad B / the red X / the tile again / a click
--     outside closes it. Gamepad B is bound (ContextActionService, High priority, sunk) only while something is open,
--     so it does not also fire MovementController's dash.
--   * Home window (Phase 4, "Phase 4 build contract" 3.1-3.3 / 8.1): the house tier, Home Level and prestige stars,
--     income per second (the plot's IncomePerSecond attribute; food and the Lucky bonus under it, the prestige
--     multiplier tag), the Pet Garden card (coins waiting = the plot's CollectorCash, coins per minute, places
--     "N/12" = the plot's GardenSlots: 3 + 1 per prestige, the LegacySlots / LegacyPrices lines; no Collect: kids
--     walk over their coins), the prestige progress (Home Level x/40 and the Sky Castle) with a confirmed Prestige
--     (what starts over, what stays, the new star's coins / garden place / Gems), Go home (Phase 6: the big golden
--     hero on top, HomeAction "GoHome": the home portal; without a home the window shows "Claim a home" (GoToSpot)
--     and the three claim steps instead) and every station of TycoonCatalog grouped Pets at home (Pet Garden, Food Machine, Training Place,
--     Fusion Machine), Coin makers (the plants, Coin Magnet, Vault), House, Decor, each with its level (pips), what it
--     does now -> next ("+7 -> +9 food", "Feeds fill 30% -> 35% of a bar", "2 pets train at once"), the next price
--     and Build / Upgrade (or why it is locked: "Reach Home Level 10", "Needs the Villa", "Unlocks at Prestige 1").
--     Everything is re-checked by the server (HomeAction "Upgrade" / "Prestige" / "GoHome").
--   * v3 readability rule: everything is designed in 1080p pixels (body 18-19, captions >= 18, buttons 20+,
--     titles 28-34) under ONE UIScale per window = min(screen factor clamp(viewportY / 1080, 0.8, 1.25), fit).
--     Window sizes adapt between a minimum and a preferred design size and their columns scroll, so phones
--     keep the 0.8 scale instead of shrinking the text.
--   * Every window re-renders from State.Changed (and when the token count or the InMatch attribute
--     changes). Pet slots are kept per pet id and updated in place, so nothing is rebuilt or leaked.
--   * Touch screens: the menu column never reaches Roblox's thumbstick (bottom-left); in landscape it sits in the
--     band between the top margin and the stick (two slim columns of four on a phone, labels >= 14 px). "Touch" is a
--     touch-only device OR any screen where PlayerModule's TouchGui shows a thumbstick (Studio's device emulator and
--     touch laptops / tablets with a keyboard report KeyboardEnabled too, but still get the stick: P5.stickShown).
--     Once the stick has been seen the touch layout stays for the session (respawn, the Esc menu and a hybrid's
--     mouse / touch switches hide the stick for a moment; the column must not snap back and forth).
--
-- Remotes used: OpenPanel (in); EquipPet, UnequipPet, GoToSpot, HomeAction, PetCare (out). Each remote action is sent at most every K.FIRE_GAP seconds (the server rate-limits as well).
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7a) the Stats window's coins and stars
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local State = require(Client:WaitForChild("State"))

-- The catalogs are written by other engineers: never let a broken one take the whole menu down.
local function safeRequire(name, fallback)
	local ok, result = pcall(function()
		return require(Shared:WaitForChild(name, 10))
	end)
	if ok and type(result) == "table" then
		return result
	end
	warn("[MenuController] " .. name .. " is unavailable: " .. tostring(result))
	return fallback
end

local PetCatalog = safeRequire("PetCatalog", {
	Pets = {},
	ById = {},
	Get = function()
		return nil
	end,
	GetOdds = function()
		return {}
	end,
	PerkLabel = function(key, value)
		return tostring(key) .. " " .. tostring(value)
	end,
})

-- Phase 2 modules (written by other engineers at the same time): optional, every use is guarded.
local function optionalShared(name)
	local module = Shared:FindFirstChild(name)
	if not module then
		local ok, found = pcall(function()
			return Shared:WaitForChild(name, 3)
		end)
		module = ok and found or nil
	end
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	warn("[MenuController] " .. name .. " is unavailable: " .. tostring(result))
	return nil
end

local TycoonCatalog = optionalShared("TycoonCatalog")

local MenuController = {}
MenuController.WindowOpened = Util.Signal()

----------------------------------------------------------------------
-- Tunables (design pixels of a 1080p screen unless noted)
----------------------------------------------------------------------
local K = {
	EDGE = 12, -- screen px between the column and the left edge
	TOUCH_EDGE = 20,
	TILE = 84, -- a menu tile (square)
	ENTRY_W = 100, -- tile + room for its label
	ENTRY_H = 98,
	GAP = 6, -- between two entries
	LABEL_TEXT = 19,
	MARGIN = 12, -- screen px kept free around a window
	NARROW = 1100, -- windows narrower than this (design px) use narrower side cards
	SHORT = 560, -- windows lower than this (design px) use their compact layout
	FIRE_GAP = 0.3, -- client-side spacing between two sends of the same remote
	HINT_SECONDS = 2.8,
	-- Roblox's touch thumbstick (bottom-left), gui px above the bottom edge: classic 70 px stick at 20 px on small
	-- screens (the dynamic stick's idle ring, ThumbstickStart, reaches 93: 74 px centred 56 px up) and 120 px at
	-- 0.75 * 120 on large ones (ThumbstickStart 148 px centred 112 px up: 186)
	STICK_TOP_SMALL = 96,
	STICK_TOP_LARGE = 210,
	STICK_GAP = 10, -- the column ends >= 10 px above the ring (13 px above the real ThumbstickStart on a phone)
	STICK_BIG = 500, -- PlayerModule's DynamicThumbstick doubles its ring when its gui area's short side is > this
	-- the thumbstick frames PlayerModule puts in TouchGui.TouchControlFrame (P5.stickShown, polled 4x a second)
	STICK_FRAMES = { "DynamicThumbstickFrame", "ThumbstickFrame" },
	MIN_LABEL_PX = 14, -- smallest on-screen menu label on phones / tablets (readability rule)
	GRID_ENTRY_H = 86, -- "Grid" layout: the label sits on the tile's bottom edge, so a row is shorter ...
	GRID_LABEL_Y = -8, -- ... (label centre this far above the tile's bottom; "Column": 2 px below it)
	-- "SmallGrid": labelled 2-column grid of smaller tiles for short touch landscape screens, where the seven tiles
	-- (Phase 3 added Team) no longer fit the band above the thumbstick as a regular grid with readable labels: the
	-- labels keep >= MIN_LABEL_PX and the tiles shrink only as far as the band needs, never below SMALL_TILE_MIN
	-- design px (~44 px on screen at the smallest label scale: still a comfortable touch target)
	SMALL_TILE_MIN = 60,
	SMALL_LABEL_SPARE = 6, -- a SmallGrid row is its tile + this (the label sits on the tile's bottom edge)
	SMALL_COL_GAP = 22, -- SmallGrid: wider gap between the two columns, so neighbouring labels never run together
	BACK_ACTION = "NimbusMenuBack", -- ContextActionService action that owns gamepad B while something is closable
}

-- Preferred design sizes of each window (W x H). Phase 5 (6.6, the window rule): windows dock RIGHT on landscape
-- screens (NeonKit.SideRect, <= 0.44 W) and are a bottom sheet on portrait ones (the top 44% stays clear); no backdrop
-- dims the game. (lobby-shop Task 22: the Cloud Shop, its odds popup and its roulette stage left for ShopController,
-- client/UI/ShopEggs and client/UI/EggStage.)
K.WIN = {
	Stats = { 640, 760 },
	Home = { 820, 900 },
}
-- Portrait screens (a phone held upright): a window may get as narrow as TALL_MIN_W design px (and as tall as
-- TALL_MAX_H) so its text keeps the readability scale instead of shrinking to fit 800 px; windows narrower than
-- TALL switch to their single-column ("tall") layout.
K.TALL_MIN_W = 420
K.TALL_MAX_H = 1100
K.TALL = 760
-- Phase 2 (Home window, Gems tab)
K.HOME_LEFT_W = 350 -- the Home window's summary column
K.HOME_LEFT_W_NARROW = 300
K.STATION_ROW_H = 96
K.STATION_ROW_H_TALL = 132
K.LIVE_GAP = 0.25 -- seconds between two live refreshes of the Home window (collector / income tick every second)
K.INFO_CHARS = 34 -- a station row's "now -> next" line longer than this shows "Next: ..." only
K.CONFIRM_W = 560 -- the prestige confirmation
K.CONFIRM_H = 356

local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.Navy or Colors.Ink
local MUTED = Colors.Muted or Colors.CloudShade
local GOLD = Colors.Gold or Colors.Token
local INK = Colors.TextStroke or Colors.Ink
local GOOD = Colors.Good
local BAD = Colors.Bad
local WELL_EDGE = Colors.WellEdge or NAVY
local BUTTONS = Theme.Buttons or {}
local KINDS = Theme.Kinds or {}
local PURPLE = Color3.fromRGB(150, 122, 226)
local INSET_COLOR = Color3.fromRGB(20, 30, 70)
local CURRENCY = Theme.Currency or {}
-- Phase 2 colours (one table: the main chunk stays under Lua's 200-local limit)
local C2 = {
	Cash = Colors.Cash or Color3.fromRGB(112, 204, 98),
	Gem = Colors.Gem or Color3.fromRGB(84, 196, 246),
	Tier = { Golden = Color3.fromRGB(246, 196, 64), Rainbow = Color3.fromRGB(226, 110, 214) },
	Hybrid = Color3.fromRGB(150, 110, 232),
	Xp = Color3.fromRGB(120, 200, 255),
	Lock = Color3.fromRGB(255, 206, 120), -- amber: why something is locked (reads on the dark wells)
	Secret = Color3.fromRGB(70, 90, 200),
	Kind = {
		Plant = Color3.fromRGB(226, 96, 130), -- berries, carrots, melons, starfruit (Phase 4 kinds)
		Magnet = Color3.fromRGB(110, 170, 236),
		Garden = Color3.fromRGB(120, 196, 90),
		FoodMachine = Color3.fromRGB(240, 150, 80),
		Training = Color3.fromRGB(228, 104, 96),
		Vault = Color3.fromRGB(150, 160, 190),
		House = Color3.fromRGB(240, 186, 90),
		Fusion = Color3.fromRGB(150, 110, 232),
		Arena = Color3.fromRGB(200, 120, 90),
		Decor = Color3.fromRGB(226, 120, 170),
		Prestige = Color3.fromRGB(244, 196, 78),
	},
}

-- Text glyphs as UTF-8 byte escapes (the source stays plain ASCII). kit-b U7a: the tiles, the coins and the Stats window
-- draw PixelIcons (NeonKit.Icon, PixelIcon.Lead); the emoji that were here unused went. U7b: the Home window's marks are
-- PixelIcons too (HOME_ICON; a station's icon is its TycoonCatalog Icon, a PixelIcon name). What is left is typography
-- (the dash, the bullet, the cash sign).
local G = {
	Dash = "\226\128\148",
	Cash = (CURRENCY.Cash and CURRENCY.Cash.Glyph) or "$",
	Bullet = "\194\183", -- middle dot
}
-- (kit-b U7b) the Home window's PixelIcons
local HOME_ICON = { House = "house", Lock = "lock", Star = "star", Check = "check", Seedling = "sprout", Arrow = "play" }

----------------------------------------------------------------------
-- Module state
----------------------------------------------------------------------
local LocalPlayer = nil
local initialized = false
local gui = nil
local U = {} -- shared UI references (backdrop, column, hint ...)
local windows = {} -- id -> window table (see createWindow)
local openId = nil -- id of the window that is currently open
local Net = { Warned = {}, Cache = {}, Last = {} } -- warnOnce keys, remote cache, last send per remote
local touchDevice = false

local Badge = { LastPetTotal = nil }
local Back = { Bound = false, Busy = false, Swallowed = false } -- gamepad B binding state (see syncBackBinding)
local Index = { Module = nil, Tried = false } -- IndexController (loaded lazily, optional)
local Entries = {} -- id -> menu tile widgets
local Hint = { Frame = nil, Label = nil, Token = 0 }
-- Phase 2: the Home window's live plot watch, the Feed picker
local Home = { Folder = nil, Conns = {}, LiveAt = 0, LivePending = false }

-- Phase 5 helpers (one table: the main chunk stays under Lua's 200-local limit). Kit = NeonKit (Card, Tile, SideRect, Dock).
local P5 = { Kit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit")) }
local PetBits = require(Client:WaitForChild("UI"):WaitForChild("PetBits"))
-- forward declarations
local openWindow, closeWindow, toggleWindow, refreshOpenWindow, updateMenuActive
local showHint, handleBack
local syncBackBinding, closeIndex, relayoutMenu, refreshHomeLive

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function warnOnce(key, err)
	if not Net.Warned[key] then
		Net.Warned[key] = true
		warn("[MenuController] " .. tostring(key) .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
end

local function makeFrame(parent, name, props)
	local p = props or {}
	p.Name = name
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	p.BorderSizePixel = 0
	p.Parent = parent
	return Util.Create("Frame", p)
end

-- Theme-styled TextLabel with optional property overrides. kit-b U6: every menu text sits on its window or card, so it
-- reads by contrast and has no outline (was a 0.25 classic stroke under a 1.5 px glyph outline).
local function makeText(parent, name, text, role, size, color, props)
	local p = { Name = name }
	if props then
		for key, value in pairs(props) do
			p[key] = value
		end
	end
	local label = Theme.Label(tostring(text), role, {
		Size = size,
		Color = color or WHITE,
		Props = p,
	})
	label.Parent = parent
	return label
end

-- radius: a Theme.Radius token ("S", "M", "None"; kit-b U6), "M" by default
local function corner(parent, radius)
	return Theme.Corner(parent, radius or "M")
end

local function round(parent)
	return Theme.Corner(parent, "Round")
end

local function stroke(parent, color, thickness, transparency)
	return Theme.Stroke(parent, color or NAVY, thickness or 3, transparency or 0)
end

local function pad(parent, left, top, right, bottom)
	return Util.Create("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		Parent = parent,
	})
end

local function listLayout(parent, direction, gap, hAlign, vAlign)
	return Util.Create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or 0),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

-- Vertical ScrollingFrame with an automatic canvas.
local function scroller(parent, name, props)
	local p = props or {}
	p.Name = name
	p.BackgroundTransparency = 1
	p.BorderSizePixel = 0
	p.CanvasSize = UDim2.new(0, 0, 0, 0)
	p.AutomaticCanvasSize = Enum.AutomaticSize.Y
	p.ScrollingDirection = Enum.ScrollingDirection.Y
	p.ScrollBarThickness = 10
	p.ScrollBarImageColor3 = Colors.FrameTop or Colors.Cloud
	p.ScrollBarImageTransparency = 0.1
	p.Parent = parent
	return Util.Create("ScrollingFrame", p)
end

local function tween(inst, seconds, goal, style, direction)
	return Util.Tween(inst, seconds, goal, style, direction)
end

-- The dark inset card used inside the windows.
local function makeInset(parent, name, props)
	local p = props or {}
	p.BackgroundColor3 = INSET_COLOR
	p.BackgroundTransparency = 0.42
	local inset = makeFrame(parent, name, p)
	corner(inset, "M")
	stroke(inset, WELL_EDGE, 3, 0.15)
	return inset
end

local function commas(n)
	return Util.Commas(tonumber(n) or 0)
end


local function inMatch()
	return LocalPlayer ~= nil and LocalPlayer:GetAttribute(Config.Attr.InMatch) == true
end

-- (kit-b U7a) a difficulty rating on an empty label: `count` gold PixelIcon stars of five, the rest dim
local function starRating(label, count)
	count = Util.Clamp(math.floor(tonumber(count) or 0), 0, 5)
	label.Text = ""
	PixelIcon.Lead(label, "star", { Count = count, Of = 5, Px = 18 })
end

local function petTotals()
	local distinct, total = 0, 0
	for id, count in pairs(State.Get().Pets) do
		if PetCatalog.Get(id) then
			distinct = distinct + 1
			total = total + count
		end
	end
	return distinct, total
end

-- Catalog pets discovered (v3: every pet ever owned or rolled; owned pets always count).
local function discoveredCount()
	local n = 0
	for _, def in ipairs(PetCatalog.Pets or {}) do
		local found
		if type(State.IsDiscovered) == "function" then
			found = State.IsDiscovered(def.Id)
		else
			found = State.OwnedCount(def.Id) > 0
		end
		if found then
			n = n + 1
		end
	end
	return n
end

local function catalogTotal()
	if type(PetCatalog.TotalCount) == "function" then
		local ok, n = pcall(PetCatalog.TotalCount)
		if ok and type(n) == "number" then
			return n
		end
	end
	return #(PetCatalog.Pets or {})
end

-- A solid coloured pill (tier / hybrid badges, "MAX", locks): white text on its own colour (kit-b U6: no outline).
local function colorPill(parent, name, text, color, textSize, layoutOrder)
	local size = textSize or 18
	local pill = Theme.Label(text, "Heading", {
		Size = size,
		Color = WHITE,
		Props = {
			Name = name,
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, size + 9),
			LayoutOrder = layoutOrder or 0,
		},
	})
	round(pill)
	stroke(pill, NAVY, 2, 0)
	Theme.Gradient(pill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 206, 226), 90)
	pad(pill, 9, 0, 9, 1)
	pill.Parent = parent
	return pill
end

----------------------------------------------------------------------
-- Phase 2 data helpers: pet copy keys, levels, the home, Cash / Gems (fields of ONE local table, P2: the main chunk
-- is close to Lua's 200-local limit)
----------------------------------------------------------------------
local P2 = {}

-- what the pet windows share (team balance: UI/PetBits)
for _, name in ipairs({ "defOfKey", "petLevel", "homeData", "catalogCall", "stage", "job", "formatCash", "formatRate" }) do
	P2[name] = PetBits[name]
end

function P2.stationLevelOf(home, id)
	local stations = type(home) == "table" and home.Stations or nil
	local level = type(stations) == "table" and stations[id] or nil
	if type(level) == "number" and level == level then
		return math.max(0, math.floor(level))
	end
	return 0
end

-- true while the local player owns (claimed) a home plot this session
function P2.hasHome()
	return LocalPlayer ~= nil and type(LocalPlayer:GetAttribute(Config.Attr.SpotIndex)) == "number"
end

function P2.cashBalance()
	if type(State.Cash) == "function" then
		local ok, value = pcall(State.Cash)
		if ok and type(value) == "number" then
			return value
		end
	end
	return 0
end

function P2.stationDef(id)
	local def = P2.catalogCall("Get", id)
	if type(def) == "table" then
		return def
	end
	return nil
end

-- Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract" 3.4-3.7): CareController (the Food Machine list, the garden
-- picker, the Training Place window and the EVOLVE moment), loaded lazily; nil when the build has none.
function P2.care()
	if P2.CareTried then
		return P2.Care
	end
	P2.CareTried = true
	local module = script.Parent:FindFirstChild("CareController")
	if module then
		local ok, mod = pcall(require, module)
		if ok and type(mod) == "table" and type(mod.Open) == "function" then
			P2.Care = mod
		end
	end
	return P2.Care
end

----------------------------------------------------------------------
-- Remotes (sent at most every FIRE_GAP seconds each, the server rate-limits as well)
----------------------------------------------------------------------
local function getRemote(name)
	local cached = Net.Cache[name]
	if cached then
		return cached
	end
	local ok, remote = pcall(Remotes.Get, name)
	if ok and remote then
		Net.Cache[name] = remote
		return remote
	end
	return nil
end

-- Sends remote `name` with the given arguments unless the same `key` was sent less than K.FIRE_GAP seconds ago.
local function fireKeyed(key, name, ...)
	local now = os.clock()
	if Net.Last[key] and now - Net.Last[key] < K.FIRE_GAP then
		return false
	end
	local remote = getRemote(name)
	if not remote then
		return false
	end
	Net.Last[key] = now
	local args = { n = select("#", ...), ... }
	local ok = pcall(function()
		remote:FireServer(unpack(args, 1, args.n))
	end)
	return ok
end

local function fire(name, ...)
	return fireKeyed(name, name, ...)
end

----------------------------------------------------------------------
-- IndexController (optional module written next to this one)
----------------------------------------------------------------------
local function getIndex()
	if not Index.Tried then
		Index.Tried = true
		local moduleScript = script.Parent:FindFirstChild("IndexController")
		if moduleScript then
			local ok, result = pcall(require, moduleScript)
			if ok and type(result) == "table" then
				Index.Module = result
			else
				warnOnce("IndexController", result)
			end
		end
	end
	return Index.Module
end

local function indexOpen()
	local index = Index.Module
	if index and type(index.IsOpen) == "function" then
		local ok, open = pcall(index.IsOpen)
		return ok and open == true
	end
	return false
end

function closeIndex()
	local index = Index.Module
	if index and type(index.Close) == "function" and indexOpen() then
		safe("Index.Close", index.Close)
	end
end

----------------------------------------------------------------------
-- Screen size helpers
----------------------------------------------------------------------
local function guiSize()
	local size = gui and gui.AbsoluteSize or Vector2.new(1280, 720)
	if size.X < 2 or size.Y < 2 then
		return Vector2.new(1280, 720)
	end
	return size
end

local function screenFactor()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize
	if vp and vp.Y > 2 then
		return Theme.ScreenFactor(vp.Y)
	end
	return Theme.ScreenFactor(guiSize().Y)
end

local function screenMargin()
	if touchDevice or U.StickSeen then -- the same touch decision as P5.stickShown (the phone's margin in the emulator)
		return K.TOUCH_EDGE
	end
	return K.EDGE
end

-- Right edge (gui px) of the menu column.
local function columnRight()
	local column = U.Column
	if column and column.Visible and column.AbsoluteSize.X > 0 then
		return column.AbsolutePosition.X + column.AbsoluteSize.X
	end
	return 0
end

----------------------------------------------------------------------
-- Side hint (tiny message next to the menu column; never in the middle of the screen)
----------------------------------------------------------------------
local function buildHint()
	local frame = makeFrame(gui, "MenuHint", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 120, 0.5, 0),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 9,
	})
	corner(frame, "M")
	stroke(frame, NAVY, 3, 0)
	Theme.Gradient(frame, Colors.PanelLight, Colors.Panel, 90)
	pad(frame, 14, 8, 14, 8)
	-- the width is set per message (one line when it fits, else wrapped at Hint.MaxW); the height follows the text
	local label = makeText(frame, "Text", "", "Toast", 20, WHITE, {
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(300, 0),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 10,
	})
	Hint.MaxW = 300
	Hint.Frame = frame
	Hint.Label = label
	Hint.Scale = Util.Create("UIScale", { Name = "ReadScale", Scale = 1, Parent = frame })
end

function showHint(text, kind)
	if not Hint.Frame then
		return
	end
	Hint.Token = Hint.Token + 1
	local mine = Hint.Token
	local color = KINDS[kind or "info"] or KINDS.info or Colors.PanelLight
	Hint.Label.Text = tostring(text)
	Hint.Label.TextColor3 = Theme.Lighten(color, 0.55)
	local maxW = Hint.MaxW or 300
	local width = maxW
	local ok, bounds = pcall(function()
		return Theme.MeasureLabel(Hint.Label, Hint.Label.Text, Hint.Label.TextSize, 4000)
	end)
	if ok and typeof(bounds) == "Vector2" and bounds.X + 6 < maxW then
		width = math.ceil(bounds.X) + 6
	end
	Hint.Label.Size = UDim2.fromOffset(width, 0)
	Hint.Frame.Visible = true
	task.delay(K.HINT_SECONDS, function()
		if Hint.Token == mine and Hint.Frame then
			Hint.Frame.Visible = false
		end
	end)
end

----------------------------------------------------------------------
-- Window manager
-- window = { Id, Spec, Holder, Fit (UIScale), Pop (UIScale), Panel, Shown, Built, Dirty, Token, W, H,
--            Tab, Refresh = fn(), OnOpen = fn(args), OnClose = fn(), OnLayout = fn(w, h, narrow) }
----------------------------------------------------------------------
-- Roblox's top bar height (gui px): our ScreenGui does not ignore it, SideRect measures from the screen top
function P5.inset()
	local inset = 58
	pcall(function()
		inset = game:GetService("GuiService"):GetGuiInset().Y
	end)
	return inset
end

-- The window rule (6.6): NeonKit.Dock puts the holder on its SideRect (docked RIGHT on landscape screens, a bottom
-- sheet on portrait ones) and keeps it there when the screen changes; the window re-lays its content when its
-- design size changes.
local function layoutWindow(win)
	if not win.Dock then
		local size = K.WIN[win.Id] or { 820, 900 }
		win.Dock = P5.Kit.Dock(win.Holder, win.Fit, size[1], size[2])
	end
	win.Dock.Refresh()
	local rect = win.Dock.Rect
	if not rect then
		return
	end
	local w, h = math.floor(rect.designW + 0.5), math.floor(rect.designH + 0.5)
	local changed = win.W ~= w or win.H ~= h
	win.W, win.H = w, h
	if changed and win.Built and win.OnLayout then
		safe("layout " .. win.Id, win.OnLayout, w, h, w < K.NARROW, h < K.SHORT, w < K.TALL)
	end
end

local function createWindow(spec)
	local size = K.WIN[spec.Id] or { 820, 900 }
	local win = { Id = spec.Id, Spec = spec, Shown = false, Built = false, Dirty = true, Token = 0 }
	win.Holder = makeFrame(gui, "Window_" .. spec.Id, {
		Size = UDim2.fromOffset(size[1], size[2]),
		Visible = false,
		ZIndex = 3,
	})
	win.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = win.Holder })
	win.Panel = CloudUI.Panel({
		Name = spec.Id .. "Panel",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Title = spec.Title,
		Closable = true,
		Category = spec.Category,
		Accent = spec.Accent,
		OnClose = function()
			closeWindow(spec.Id)
		end,
		Parent = win.Holder,
	})
	win.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = win.Panel.Root })
	windows[spec.Id] = win
	return win
end

local function ensureBuilt(win)
	if win.Built then
		return
	end
	win.Built = true
	safe("build " .. win.Id, win.Spec.Build, win)
	if win.OnLayout and win.W then
		safe("layout " .. win.Id, win.OnLayout, win.W, win.H, win.W < K.NARROW, win.H < K.SHORT, win.W < K.TALL)
	end
end

local function refreshWindow(win)
	if not win or not win.Built then
		return
	end
	if win.Shown then
		win.Dirty = false
		if win.Refresh then
			safe("refresh " .. win.Id, win.Refresh)
		end
	else
		win.Dirty = true
	end
end

function refreshOpenWindow()
	if openId then
		refreshWindow(windows[openId])
	end
end

-- Team balance: the Pets window is PetsController's (required on use, it boots after this controller)
function P5.pets()
	if P5.Pets == nil then
		P5.Pets = false
		local module = script.Parent:FindFirstChild("PetsController")
		local ok, mod = pcall(function()
			return module and require(module)
		end)
		if ok and type(mod) == "table" then
			P5.Pets = mod
		end
	end
	return P5.Pets or nil
end

function P5.petsOpen()
	local pets = P5.pets()
	return pets ~= nil and pets.IsOpen() == true
end

-- something else takes over: the window goes silently (nothing it was given to go back to)
function P5.closePets()
	if P5.petsOpen() then
		safe("pets close", P5.Pets.Close, true)
	end
end

-- an optional module, required on first use (cached in P5[field]; false = unavailable): folder:FindFirstChild(name)
function P5.lazy(field, folder, name)
	if P5[field] == nil then
		P5[field] = false
		local module = folder and folder:FindFirstChild(name)
		local ok, mod = pcall(function()
			return module and require(module)
		end)
		if ok and type(mod) == "table" and type(mod.Open or mod.Request) == "function" then
			P5[field] = mod
		end
	end
	return P5[field] or nil
end

-- lobby-shop Task 22: the one Shop window (ShopController; the StoreController forwarder when a build lacks it) and the
-- egg stage (client/UI/EggStage) it plays every spin through. The ONE path of OpenPanel("Shop") / OpenPanel("Store")
-- (onOpenPanel); neither listens to OpenPanel itself.
function P5.shop()
	return P5.lazy("Shop", script.Parent, "ShopController") or P5.lazy("ShopForwarder", script.Parent, "StoreController")
end

function P5.hatch()
	return P5.lazy("Hatch", Client:FindFirstChild("UI"), "EggStage")
end

function P5.shopOpen()
	local shop = P5.shop()
	return shop ~= nil and type(shop.IsOpen) == "function" and shop.IsOpen() == true
end

function P5.hatchShowing()
	local hatch = P5.hatch()
	return hatch ~= nil and type(hatch.IsShowing) == "function" and hatch.IsShowing() == true
end

-- refused while the egg stage shows (ShopController.Open refuses it too) and in a match (the Shop's own hint)
function P5.openShop(args)
	local shop = P5.shop()
	if shop and not P5.hatchShowing() then
		safe("shop open", shop.Open, args)
	end
end
P5.openStore = P5.openShop

function P5.closeShop()
	if P5.shopOpen() then
		safe("shop close", P5.shop().Close)
	end
end

-- the stage closes from here only through closeEverything (MenuController.Close, a match start): it toasts the pulls
-- not shown yet ("You hatched: ...")
function P5.closeHatch()
	local hatch = P5.hatch()
	if hatch and type(hatch.Close) == "function" then
		safe("hatch close", hatch.Close)
	end
end

function P5.openPets(args)
	local pets = P5.pets()
	if pets and not P5.hatchShowing() then
		safe("pets open", pets.Open, args)
	end
end

function openWindow(id, args)
	local win = windows[id]
	if not win or P5.hatchShowing() then
		return
	end
	args = type(args) == "table" and args or {}
	closeIndex()
	P5.closePets()
	if openId and openId ~= id then
		closeWindow(openId, true)
	end
	local wasShown = win.Shown
	win.Shown = true
	win.Token = win.Token + 1
	openId = id
	syncBackBinding()
	layoutWindow(win)
	ensureBuilt(win)
	win.Holder.Visible = true
	if not wasShown then
		win.Pop.Scale = 0.86
		tween(win.Pop, 0.22, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	if win.OnOpen then
		safe("open " .. id, win.OnOpen, args)
	end
	refreshWindow(win)
	updateMenuActive()
	if not wasShown then
		MenuController.WindowOpened:Fire(id)
	end
end

function closeWindow(id, instant)
	local win = windows[id]
	if not win or not win.Shown then
		return
	end
	win.Shown = false
	win.Token = win.Token + 1
	local mine = win.Token
	if openId == id then
		openId = nil
	end
	syncBackBinding()
	if win.OnClose then
		safe("close " .. id, win.OnClose)
	end
	if instant then
		-- another window takes over right away
		win.Holder.Visible = false
	else
		tween(win.Pop, 0.12, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.13, function()
			if win.Token == mine and not win.Shown then
				win.Holder.Visible = false
			end
		end)
	end
	updateMenuActive()
end

-- Button behaviour: open, or close when it is already showing.
function toggleWindow(id, args)
	local win = windows[id]
	if not win then
		return
	end
	if win.Shown then
		closeWindow(id)
	else
		openWindow(id, args)
	end
end

-- MenuController.Close / a match start / Settings: the Shop first (so it never comes back over the game when the stage
-- closes), then the egg stage (one "You hatched: ..." toast for the pulls not shown), then everything else. A match
-- start (forMatch) leaves the stage to its own InMatch listener (EggStage closes with the reason "Match", same toast).
local function closeEverything(forMatch)
	P5.closeShop()
	if not forMatch then
		P5.closeHatch()
	end
	if openId then
		closeWindow(openId)
	end
	P5.closePets()
	closeIndex()
end

-- Esc / gamepad B: close the open menu window. Returns true when something was closed.
-- (The Pet Index, the Shop and the egg stage handle Esc / B themselves: the stage's one Esc path is the Shop's.)
function handleBack()
	if openId then
		closeWindow(openId)
		return true
	end
	return false
end

-- Gamepad B is also the dash button (MovementController binds "NimbusDash" at Default priority), and
-- UserInputService.InputBegan cannot stop that action. So B is owned here through ContextActionService at
-- High priority, but only while something closable is open: the press then closes it and is sunk, so
-- the character does not dash (or spend stamina / start the cooldown) on the same press. With nothing open
-- the binding is gone and B dashes as usual. Esc stays on the plain InputBegan path (onInput).
local function onBackAction(_name, inputState)
	if inputState == Enum.UserInputState.Begin then
		Back.Busy = true
		local ok, handled = pcall(handleBack)
		Back.Busy = false
		if not ok then
			warnOnce("back", handled)
			handled = false
		end
		Back.Swallowed = handled == true
		if Back.Swallowed then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
	-- release / cancel: sink it when the press was ours, so nothing below sees half a press
	local swallowed = Back.Swallowed
	Back.Swallowed = false
	if swallowed then
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

-- Binds B while a menu window is open and unbinds it when none is. Called after every change of openId.
function syncBackBinding()
	local wanted = openId ~= nil
	if wanted == Back.Bound then
		return
	end
	if wanted then
		Back.Bound = true
		local ok, err = pcall(function()
			ContextActionService:BindActionAtPriority(
				K.BACK_ACTION,
				onBackAction,
				false,
				Enum.ContextActionPriority.High.Value,
				Enum.KeyCode.ButtonB
			)
		end)
		if not ok then
			warnOnce("bind back", err)
		end
	elseif Back.Busy then
		-- the press that closed the last thing is still being dispatched: unbind right after it
		task.defer(syncBackBinding)
	else
		Back.Bound = false
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

----------------------------------------------------------------------
-- Menu tiles (left-centre column; a 2 x 3 grid on short screens)
----------------------------------------------------------------------
local function menuActionPets()
	if P5.petsOpen() then
		safe("pets close", P5.Pets.Close)
	else
		P5.openPets({})
	end
end

local function openIndex(groupId)
	local index = getIndex()
	if not index or type(index.Open) ~= "function" then
		showHint("The Pet Index is getting ready. Try again soon!", "info")
		return
	end
	if P5.hatchShowing() then
		return
	end
	if openId then
		closeWindow(openId, true)
	end
	P5.closePets()
	safe("Index.Open", index.Open, groupId)
end

local function menuActionIndex()
	if indexOpen() then
		closeIndex()
	else
		openIndex(nil)
	end
end

-- The Home tile (id "Spot"): the Home window. Phase 6: also before a home is claimed; then its Claim a home hero
-- walks the player to a free gate (Remotes.GoToSpot: the home portal toward the last plot when it is free, else the
-- nearest free one) where E claims it.
local function menuActionSpot()
	if inMatch() then
		showHint("You cannot go home during a match.", "info")
		return
	end
	toggleWindow("Home")
end

local function menuActionStats()
	toggleWindow("Stats")
end

-- Phase 5 (6.6): the Settings gear opens MainMenuController's settings panel (menu W3); a hint until it exists.
-- HUD cleanup: public (the top-left pill's gear, TopBarController; Open("Settings"))
function MenuController.OpenSettings()
	local module = script.Parent:FindFirstChild("MainMenuController")
	local ok, mod = pcall(function()
		return module and require(module)
	end)
	if ok and type(mod) == "table" then
		for _, name in ipairs({ "OpenSettings", "Settings", "ShowSettings" }) do
			if type(mod[name]) == "function" then
				closeEverything()
				safe("settings", mod[name])
				return
			end
		end
		if type(mod.Open) == "function" then
			closeEverything()
			safe("settings", mod.Open, "Settings")
			return
		end
	end
	showHint("Settings are getting ready. Try again soon!", "info")
end
P5.openSettings = MenuController.OpenSettings

-- The menu (bug batch 2 #1, option A "Split & shift"; HUD cleanup): ONE slim column of four neon tiles against the
-- left edge, vertically centred (Pets, Index, Home, Stats; Shop / Travel / Settings live in TopBarController's pill in
-- Roblox's top bar), with a small arrow tab beside its last tile that slides the column off the edge and back
-- (remembered for the session). Each tile is a NeonKit.Tile whose root is the TextButton MenuButton_<Id> inside a
-- frame Entry_<Id> of the frame "MenuColumn" (names kept: the tutorial rings them; a Gear = true entry would get a
-- Gear_<Id> frame; the tab is MenuColumn.Toggle, so everything that measures the column also keeps clear of the tab). Tiles are designed at 66 px under one UIScale: 56 px on a 1080p
-- desktop (x the screen factor), 50 px on touch screens, never below 44 px (a thumb). Where one column does not fit
-- that minimum (the band above a landscape phone's thumbstick, the strip above a portrait phone's sheet) the tiles
-- wrap into two slim columns of four (three columns on the shortest phones), still clear of the stick and never
-- reaching into the middle of the screen.
local MENU = {
	{ Id = "Pets", Label = "Pets", Icon = "Pets", Color = "Orange", Action = menuActionPets },
	{ Id = "Index", Label = "Index", Icon = "Index", Color = "Purple", Action = menuActionIndex },
	{ Id = "Spot", Label = "Home", Icon = "Home", Color = "Yellow", Action = menuActionSpot },
	{ Id = "Stats", Label = "Stats", Icon = "Stats", Color = "Cyan", Action = menuActionStats },
}
P5.TILE = 66 -- design px of a tile
P5.GAP = 6 -- between two tiles (design px)
P5.TILE_PX = 56 -- on-screen tile on a 1080p desktop (x the screen factor)
P5.TOUCH_TILE_PX = 50 -- ... on touch screens (tablets: the larger of this and TILE_PX x the factor)
P5.MIN_TILE_PX = 44 -- one column needs this much per tile, else the tiles wrap into two columns (a thumb)
P5.TAB_GAP = 4 -- design px between the tiles and the arrow tab
P5.TAB_W = 24 -- design width of the arrow tab (touch: TAB_W_TOUCH, wider for a thumb)
P5.TAB_W_TOUCH = 30
P5.MAX_COLS = 3 -- the tiles wrap into at most this many columns (the shortest landscape phones)
P5.CENTRE_TOL = 0.145 -- the column never reaches into the screen middle (|dx| < 14.5% of the width: HudController's rule)
P5.SLIDE = 0.25 -- seconds of the collapse / expand slide

-- active (its window is open): the gold glow ring + a gold label; disabled (in a match): grey. (kit-b U8) The tiles are kit B
-- stone tiles (NeonKit.Tile Skin "Sign"): active = the gold face, disabled = the sunk well; the skin paints its own label
local function paintTile(entry)
	local tile = entry.Tile
	if not tile then
		return
	end
	local color = entry.Disabled and "Grey" or entry.Color
	if entry.Painted ~= tostring(color) .. tostring(entry.Active) then
		entry.Painted = tostring(color) .. tostring(entry.Active)
		tile.SetColor(entry.Active and "Gold" or color)
		tile.Card.SetGlow(entry.Active == true)
		if tile.Label and tile.Skin ~= "Sign" then
			tile.Label.TextColor3 = entry.Active and Theme.Lighten(GOLD, 0.45) or WHITE
		end
	end
	entry.Button:SetAttribute("Disabled", entry.Disabled == true)
end

local function buildTile(column, spec, index)
	local size = P5.TILE
	local entry = { Id = spec.Id, Color = spec.Color }
	entry.Root = makeFrame(column, (spec.Gear and "Gear_" or "Entry_") .. spec.Id, {
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = index,
		ZIndex = 2,
	})
	local tile = P5.Kit.Tile({
		Name = "MenuButton_" .. spec.Id,
		Size = size,
		Color = spec.Color,
		Icon = spec.Icon,
		Label = (not spec.Gear) and spec.Label or nil, -- the gear stays icon-only
		Glow = false,
		Skin = "Sign", -- (kit-b U8) the pitch's HUD tiles
		Parent = entry.Root,
		Callback = function()
			safe("menu " .. spec.Id, spec.Action)
		end,
	})
	entry.Tile = tile
	entry.Button = tile.Root
	entry.Label = tile.Label
	-- icon-only tiles (the small row) name themselves on hover / long-press
	CloudUI.Tooltip(tile.Root, function()
		return spec.Label
	end)
	function entry.SetBadge(on)
		tile.SetBadge(on)
		P5.paintTab() -- a folded column still shows that a tile wants attention
	end
	paintTile(entry)
	Entries[spec.Id] = entry
	P5.tileVisibility(entry) -- a battle on a landscape phone (SetColumnHidden) / a collapsed column hide the tiles
	return entry
end

-- A tile shows unless a battle holds the left edge (SetColumnHidden) or the column is folded away (after its slide).
function P5.tileVisibility(entry)
	if entry and entry.Root then
		entry.Root.Visible = not U.ColumnHidden and not U.TilesFolded and not U.Covered
	end
end

-- Roblox's touch thumbstick is (or will be) on screen: a touch-only device, or a screen where PlayerModule's TouchGui
-- shows a thumbstick frame although the device also has a keyboard (Studio's device emulator, touch laptops,
-- tablets with a keyboard: TouchEnabled AND KeyboardEnabled, so `touchDevice` is false there). The column then uses
-- the touch layout: the band above the stick, thumb-sized tiles and tab. Polled by P5.watchSheets until it is true.
-- LATCHED: once seen, true for the rest of the session. PlayerModule hides the stick on respawn and while the Esc menu
-- is open (TouchGui.Enabled, not read here) and on every mouse / keyboard input of a hybrid device (the frame's
-- Visible); following those would snap the column between layouts. A keyboard-only PC never gets the stick frames.
function P5.stickShown()
	if touchDevice or U.StickSeen then
		return true
	end
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = pg and pg:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	if not (frame and frame:IsA("GuiObject") and frame.Visible) then
		return false
	end
	for _, name in ipairs(K.STICK_FRAMES) do
		local stick = frame:FindFirstChild(name)
		if stick and stick:IsA("GuiObject") and stick.Visible then
			U.StickSeen = true -- latched for the session (U lives as long as the client)
			return true
		end
	end
	return false
end

-- Design size of the column frame for `cols` tile columns: the tiles plus the arrow tab beside them.
function P5.columnSize(cols)
	local rows = math.ceil(#MENU / cols)
	local tilesW = cols * P5.TILE + (cols - 1) * P5.GAP
	local tabW = U.StickShown and P5.TAB_W_TOUCH or P5.TAB_W
	return tilesW + P5.TAB_GAP + tabW, rows * P5.TILE + (rows - 1) * P5.GAP, tilesW
end

-- Places the tiles in `cols` columns (row by row: Pets Index / Home Stats in two columns) and the tab beside
-- the last row, right after its last tile (the gear: with 3 columns that row holds only 2 tiles, and the tab must not
-- leave an empty slot before it). Sets U.ColumnW / U.ColumnH / U.TilesW / U.TabX (design px).
function P5.placeTiles(cols)
	local touch = U.StickShown == true -- the tab's width follows the touch layout
	if U.Cols == cols and U.ColsTouch == touch then
		return
	end
	U.Cols = cols
	U.ColsTouch = touch
	local w, h, tilesW = P5.columnSize(cols)
	for index, spec in ipairs(MENU) do
		local entry = Entries[spec.Id]
		if entry and entry.Root then
			local i = index - 1
			entry.Root.Position = UDim2.fromOffset((i % cols) * (P5.TILE + P5.GAP), math.floor(i / cols) * (P5.TILE + P5.GAP))
		end
	end
	local lastRow = #MENU - (math.ceil(#MENU / cols) - 1) * cols
	U.ColumnW, U.ColumnH, U.TilesW = w, h, tilesW
	U.TabX = lastRow * (P5.TILE + P5.GAP) - P5.GAP + P5.TAB_GAP
	U.Column.Size = UDim2.fromOffset(w, h)
	if U.Tab then
		U.Tab.Size = UDim2.fromOffset(w - tilesW - P5.TAB_GAP, P5.TILE)
		U.Tab.Position = UDim2.fromOffset(U.TabX, h - P5.TILE)
	end
end

-- The tab's arrow points where a click sends the column ("<" fold away, ">" bring back); while folded, a red dot
-- repeats any tile's badge (new pets, Index rewards).
function P5.paintTab()
	if not U.Tab then
		return
	end
	local arrow = U.Collapsed and ">" or "<"
	if U.TabArrow.Text ~= arrow then
		U.TabArrow.Text = arrow
	end
	local badge = false
	if U.Collapsed then
		for _, entry in pairs(Entries) do
			local dot = entry.Tile and entry.Tile.Badge
			badge = badge or (dot ~= nil and dot.Visible == true)
		end
	end
	if U.TabBadge.Visible ~= badge then
		U.TabBadge.Visible = badge
	end
	if U.Tab:GetAttribute("Collapsed") ~= (U.Collapsed == true) then
		U.Tab:SetAttribute("Collapsed", U.Collapsed == true)
	end
end

-- Folds the column away against the left edge (only the tab stays) or brings it back. Remembered for the session
-- (U.Collapsed lives as long as the client; the menu gui never resets on respawn).
function P5.setCollapsed(on, animate)
	on = on == true
	if U.Collapsed == on then
		return
	end
	U.Collapsed = on
	U.FoldSerial = (U.FoldSerial or 0) + 1
	local serial = U.FoldSerial
	if not on then
		U.TilesFolded = false
		for _, entry in pairs(Entries) do
			P5.tileVisibility(entry)
		end
	end
	P5.paintTab()
	if gui and gui:GetAttribute("MenuCollapsed") ~= on then
		gui:SetAttribute("MenuCollapsed", on)
	end
	P5.slideAnimate = animate == true
	relayoutMenu()
	P5.slideAnimate = false
	if on then
		-- the tiles hide once they are off screen: nothing measures, rings or selects a tile nobody can see
		local function fold()
			if U.Collapsed and U.FoldSerial == serial then
				U.TilesFolded = true
				for _, entry in pairs(Entries) do
					P5.tileVisibility(entry)
				end
			end
		end
		if animate then
			task.delay(P5.SLIDE + 0.05, fold)
		else
			fold()
		end
	end
end

-- The tutorial needs a tile while one of its steps points at the menu: a folded column comes back for it.
function P5.tutorialWantsMenu()
	if P5.Tutorial == nil then
		P5.Tutorial = false
		local controllers = script.Parent
		local inst = controllers and controllers:FindFirstChild("TutorialController")
		if inst then
			local ok, mod = pcall(require, inst)
			if ok and type(mod) == "table" and type(mod.GetState) == "function" then
				P5.Tutorial = mod
			end
		end
	end
	if not P5.Tutorial then
		return false
	end
	local ok, st = pcall(P5.Tutorial.GetState)
	return ok and type(st) == "table" and not st.Done and type(st.Target) == "table" and st.Target.Kind == "Menu"
end

local function buildColumn()
	local column = makeFrame(gui, "MenuColumn", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, K.EDGE, 0.5, 0),
		ZIndex = 2,
	})
	U.Column = column
	U.ColumnScale = Util.Create("UIScale", { Name = "ViewportScale", Scale = 1, Parent = column })
	for index, spec in ipairs(MENU) do
		buildTile(column, spec, index)
	end
	-- the hide / show tab: a slim navy tab with an arrow, beside the last tile (the gear), so the tutorial's pointer
	-- at Pets / Team / Index / Home never lands on it
	-- (kit-b U8) a stone tab in a wood edge like the tiles, the arrow in brown
	local tab = Util.Create("TextButton", {
		Name = "Toggle",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Sign.Tile,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = column,
	})
	U.TabStroke = stroke(tab, Theme.Sign.Wood, 3, 0)
	U.TabStroke.LineJoinMode = Enum.LineJoinMode.Miter
	U.TabArrow = makeText(tab, "Arrow", "<", "Display", 26, Theme.Sign.Text, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	U.TabBadge = makeFrame(tab, "Badge", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -2, 0, 4),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Sign.Red,
		Visible = false,
		ZIndex = 5,
	})
	stroke(U.TabBadge, Theme.Sign.Wood, 2, 0)
	U.Tab = tab
	tab.Activated:Connect(function()
		safe("menu fold", P5.setCollapsed, not U.Collapsed, true)
	end)
	CloudUI.Tooltip(tab, function()
		return U.Collapsed and "Show menu" or "Hide menu"
	end)
	P5.placeTiles(1)
	P5.paintTab()
end

-- Phase 5 (6.6): on a portrait phone a window is a bottom sheet; while ANY docked sheet is up (ours, the Care / Index /
-- Fusion windows, the dungeon or arena side panels) the tile grid steps aside so the screen stays <= 60% covered.
-- Checked 4 times a second, only on portrait screens: the ScreenGuis' window holders carry NeonKit.Dock's DockMode.
function P5.sheetUp()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for _, g in ipairs(pg and pg:GetChildren() or {}) do
		if g:IsA("ScreenGui") and g.Enabled then
			for _, holder in ipairs(g:GetChildren()) do
				if holder:IsA("GuiObject") and holder.Visible and holder:GetAttribute("DockMode") == "Sheet" then
					return true
				end
			end
		end
	end
	return false
end

-- The bottom (gui px; both guis keep Roblox's inset) of HudController's top-left panels, 0 when none is shown.
function P5.hudTopLeftBottom()
	local hud = P5.Hud
	if not (hud and hud.Parent and hud.Enabled) then
		return 0
	end
	return tonumber(hud:GetAttribute("TopLeftBottom")) or 0
end

-- relayout as soon as the HUD's top-left panels appear / go (the portrait grid steps below them)
function P5.watchHud()
	if P5.Hud and P5.Hud.Parent then
		return
	end
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("NimbusHud")
	if hud and hud:IsA("ScreenGui") then
		P5.Hud = hud
		hud:GetAttributeChangedSignal("TopLeftBottom"):Connect(function()
			safe("hud panels", relayoutMenu)
		end)
		hud:GetPropertyChangedSignal("Enabled"):Connect(function()
			safe("hud panels", relayoutMenu)
		end)
		safe("hud panels", relayoutMenu)
	end
end

function P5.watchSheets()
	task.spawn(function()
		while gui and gui.Parent do
			P5.watchHud()
			local area = guiSize()
			local hide = area.X < area.Y and P5.sheetUp()
			if U.Column and hide ~= (U.SheetHidden == true) then
				U.SheetHidden = hide
				U.Column.Visible = not hide
			end
			-- a tutorial step that points at a tile brings a folded column back (the ring needs the tile on screen)
			if U.Collapsed and P5.tutorialWantsMenu() then
				safe("menu unfold", P5.setCollapsed, false, true)
			elseif U.Collapsed then
				safe("menu tab", P5.paintTab) -- the tab's dot follows the tiles' badges
			end
			-- Roblox's thumbstick appeared (hybrid devices, the emulator): the column moves above it, for good (latched)
			if U.Column and not U.StickShown and P5.stickShown() then
				safe("menu stick", relayoutMenu)
			end
			task.wait(0.25)
		end
	end)
end

-- the column's place and scale: left-centre on desktops; on touch landscape screens (P5.stickShown: a touch device or
-- Roblox's thumbstick on screen) in the band between the top margin and the thumbstick; on portrait phones above the
-- bottom sheet's top (0.44 H). One column when it fits at P5.MIN_TILE_PX per tile, else two; folded (U.Collapsed) the
-- column sits left of the edge with only its tab showing.
function relayoutMenu()
	if not gui or not U.Column then
		return
	end
	local area = guiSize()
	local factor = screenFactor()
	local touchLayout = P5.stickShown() -- first: it latches U.StickSeen, which screenMargin reads
	U.StickShown = touchLayout
	local margin = screenMargin()
	local pref = factor * P5.TILE_PX / P5.TILE
	if touchLayout then
		pref = math.max(P5.TOUCH_TILE_PX, factor * P5.TILE_PX) / P5.TILE
	end
	local minScale = P5.MIN_TILE_PX / P5.TILE
	local first, avail -- gui px: the top of the band the column is centred in, and its height
	if area.X >= area.Y then
		local bottom = area.Y - margin
		if touchLayout then
			-- the ring's size follows TouchControlFrame's AbsoluteSize, which is this gui area (neither ignores the top
			-- bar), not the camera viewport: a 540 px tall screen (482 px area) still gets the small ring
			local big = math.min(area.X, area.Y) > K.STICK_BIG
			bottom = area.Y - (big and K.STICK_TOP_LARGE or K.STICK_TOP_SMALL) - K.STICK_GAP
		end
		first = margin
		avail = bottom - margin
	else
		local inset = P5.inset()
		local bottom = (area.Y + inset) * 0.44 - inset - margin -- the bottom sheet's top edge (0.44 of the SCREEN)
		first = margin + 80 * factor -- under the HUD's top-left corner
		local hudBottom = P5.hudTopLeftBottom()
		if hudBottom > 0 and hudBottom + margin > first then
			-- a party / match panel is up: there is no room for it beside the tiles on a phone this narrow, so the
			-- panel keeps the top-left corner and the tiles step below it (no sheet is up: the tiles hide for one)
			first = hudBottom + margin
			local _, h2 = P5.columnSize(2)
			bottom = math.max(bottom, first + h2 * pref)
		end
		avail = math.max(60, bottom - first)
	end
	-- one column when it fits with tiles >= MIN_TILE_PX, else the fewest columns that do
	local cols = 1
	while cols < P5.MAX_COLS and avail < select(2, P5.columnSize(cols)) * minScale do
		cols = cols + 1
	end
	P5.placeTiles(cols)
	local w, h = U.ColumnW, U.ColumnH
	local scale = math.min(pref, avail / h)
	-- never into the middle of the screen (a narrow portrait phone): the column's right edge stays left of it
	local camera = workspace.CurrentCamera
	local vpX = (camera and camera.ViewportSize.X > 2) and camera.ViewportSize.X or area.X
	scale = math.min(scale, math.max(minScale * 0.9, (vpX * (0.5 - P5.CENTRE_TOL) - 2 - margin) / w))
	local top = first + math.max(0, (avail - h * scale) / 2)
	U.ColumnScale.Scale = scale
	-- a squeezed column (short screens) grows its labels so they stay >= 14 screen px
	local labelPx = math.min(26, math.max(18, math.ceil(14.5 / math.max(scale, 0.3))))
	-- ... and so does the "!" of a tile's red badge (its dot grows around it)
	local markPx = math.max(14, math.ceil(14.5 / math.max(scale, 0.3)))
	for _, entry in pairs(Entries) do
		if entry.Label then
			entry.Label.TextSize = labelPx
			entry.Label.Size = UDim2.new(1, 12, 0, labelPx + 2)
		end
		local badge = entry.Tile and entry.Tile.Badge
		local mark = badge and badge:FindFirstChild("Mark")
		if mark and mark:IsA("TextLabel") then
			mark.TextSize = markPx
			badge.Size = UDim2.fromOffset(math.max(22, markPx + 4), math.max(22, markPx + 4))
		end
	end
	local left = margin
	if U.Collapsed then
		left = -math.floor(U.TabX * scale + 0.5) -- only the tab shows, flush with the edge
	end
	local goal = UDim2.new(0, left, 0, math.floor(top + 0.5))
	U.Column.AnchorPoint = Vector2.new(0, 0)
	if U.SlideTween then
		U.SlideTween:Cancel()
		U.SlideTween = nil
	end
	if P5.slideAnimate then
		U.SlideTween = tween(U.Column, P5.SLIDE, { Position = goal }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	else
		U.Column.Position = goal
	end
	if Hint.Frame then
		-- next to the column, and never wide enough to reach the middle of the screen
		local hintLeft = left + w * scale + 10
		local room = math.max(120, area.X * 0.34 - hintLeft - 28 * factor)
		Hint.Scale.Scale = factor
		Hint.Frame.Position = UDim2.new(0, hintLeft, 0, math.floor(top + h * scale / 2 + 0.5))
		Hint.MaxW = math.min(300, math.floor(room / factor))
	end
	for _, win in pairs(windows) do
		if win.Shown then
			layoutWindow(win)
		end
	end
end

local function setActive(id, on)
	local entry = Entries[id]
	if entry and entry.Active ~= (on and true or false) then
		entry.Active = on and true or false
		paintTile(entry)
	end
end

local function setDisabled(id, on)
	local entry = Entries[id]
	if entry and entry.Disabled ~= (on and true or false) then
		entry.Disabled = on and true or false
		paintTile(entry)
	end
end

function updateMenuActive()
	local petsUp = P5.petsOpen()
	setActive("Pets", petsUp)
	setActive("Index", indexOpen())
	setActive("Stats", windows.Stats ~= nil and windows.Stats.Shown)

	setActive("Spot", windows.Home ~= nil and windows.Home.Shown)
	if petsUp and Entries.Pets then
		Entries.Pets.SetBadge(false)
	end
	-- the Spot tile is greyed out in matches
	setDisabled("Spot", inMatch())
end

-- Red dot on the Index tile while a completed group's reward waits.
local function refreshIndexBadge()
	local entry = Entries.Index
	local index = Index.Module
	if not entry or not index or type(index.ClaimableCount) ~= "function" then
		return
	end
	local ok, count = pcall(index.ClaimableCount)
	entry.SetBadge(ok and type(count) == "number" and count > 0)
end

----------------------------------------------------------------------
-- Stats window
----------------------------------------------------------------------
local function buildStats(win)
	local content = win.Panel.Content
	local tiles = {} -- key -> value label
	local rows = {} -- difficulty id -> time label

	-- left: stat tiles + pet perks
	local left = scroller(content, "Left", {
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(0.55, -21, 1, -28),
	})
	pad(left, 2, 2, 12, 6)
	listLayout(left, Enum.FillDirection.Vertical, 10)
	local grid = makeFrame(left, "Tiles", {
		Size = UDim2.new(1, 0, 0, 4 * 94 + 3 * 10),
		LayoutOrder = 1,
	})
	Util.Create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 94),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local TILES = {
		{ "Matches", "Matches played", WHITE },
		{ "Wins", "Victories", Theme.Lighten(GOOD, 0.25) },
		{ "WinRate", "Win rate", WHITE },
		{ "Tokens", "Cloud tokens", Colors.Token },
		{ "Earned", "Tokens earned", Colors.Token },
		{ "Spins", "Roulette spins", WHITE },
		{ "Found", "Pets discovered", Theme.Lighten(PURPLE, 0.35) },
		{ "Owned", "Pets owned", WHITE },
	}
	for index, spec in ipairs(TILES) do
		local tile = makeInset(grid, "Tile_" .. spec[1], { LayoutOrder = index })
		local value = makeText(tile, "Value", "0", "Display", 34, spec[3], {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 42),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 18, Parent = value })
		if spec[1] == "Tokens" or spec[1] == "Earned" then
			PixelIcon.Lead(value, Theme.Currency.Tokens.Icon, { Px = 27 }) -- (kit-b U7a) the coin before the amount
		end
		makeText(tile, "Caption", spec[2], "Heading", 18, MUTED, {
			Position = UDim2.fromOffset(14, 56),
			Size = UDim2.new(1, -28, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		tiles[spec[1]] = value
	end

	local perks = makeInset(left, "Perks", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	})
	pad(perks, 14, 10, 14, 12)
	listLayout(perks, Enum.FillDirection.Vertical, 4)
	makeText(perks, "Title", "Pet perks", "Heading", 22, WHITE, {
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	local perksLabel = makeText(perks, "Lines", "", "Body", 19, Theme.Lighten(GOOD, 0.25), {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	})

	-- Phase 3: the battle record (trophies from PvP duels, the Trial ladder, raids)
	local battle = makeInset(left, "Battle", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
	})
	pad(battle, 14, 10, 14, 12)
	listLayout(battle, Enum.FillDirection.Vertical, 4)
	makeText(battle, "Title", "Pet battles", "Heading", 22, WHITE, {
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	local battleLabel = makeText(battle, "Lines", "", "Body", 19, WHITE, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	})

	-- right: best time per difficulty
	local right = makeInset(content, "BestTimes", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.new(0.45, -21, 1, -28),
	})
	local list = scroller(right, "List", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
	})
	pad(list, 8, 4, 14, 8)
	listLayout(list, Enum.FillDirection.Vertical, 8)
	Theme.StyleTitle(makeText(list, "Title", "Best times", "Title", 28, WHITE, {
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 0,
	}), "Section")
	for index, difficulty in ipairs(Config.Difficulties) do
		local row = makeFrame(list, "Row_" .. difficulty.Id, {
			Size = UDim2.new(1, 0, 0, 66),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Darken(difficulty.Color, 0.55),
			LayoutOrder = index,
		})
		corner(row, "M")
		stroke(row, NAVY, 3, 0)
		local bar = makeFrame(row, "Bar", {
			Position = UDim2.fromOffset(6, 8),
			Size = UDim2.new(0, 7, 1, -16),
			BackgroundTransparency = 0,
			BackgroundColor3 = difficulty.Color,
		})
		round(bar)
		makeText(row, "Name", difficulty.DisplayName, "Title", 24, Theme.Lighten(difficulty.Color, 0.45), {
			Position = UDim2.fromOffset(22, 5),
			Size = UDim2.new(0.55, -22, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		starRating(makeText(row, "Stars", "", "Heading", 18, GOLD, {
			Position = UDim2.fromOffset(22, 36),
			Size = UDim2.new(0.55, -22, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		}), difficulty.Stars)
		rows[difficulty.Id] = makeText(row, "Time", "--:--", "Display", 30, WHITE, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.new(0.45, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end

	win.OnLayout = function(_w, _h, _narrow, _short, tall)
		if tall then
			left.Position = UDim2.fromOffset(14, 14)
			left.Size = UDim2.new(1, -28, 0.6, -21)
			right.AnchorPoint = Vector2.new(0, 1)
			right.Position = UDim2.new(0, 14, 1, -14)
			right.Size = UDim2.new(1, -28, 0.4, -21)
		else
			left.Position = UDim2.fromOffset(14, 14)
			left.Size = UDim2.new(0.55, -21, 1, -28)
			right.AnchorPoint = Vector2.new(1, 0)
			right.Position = UDim2.new(1, -14, 0, 14)
			right.Size = UDim2.new(0.45, -21, 1, -28)
		end
	end

	win.Refresh = function()
		local snapshot = State.Get()
		local stats = snapshot.Stats
		local matches = stats.Matches or 0
		local wins = stats.Wins or 0
		tiles.Matches.Text = commas(matches)
		tiles.Wins.Text = commas(wins)
		if matches > 0 then
			tiles.WinRate.Text = string.format("%d%%", math.floor(wins / matches * 100 + 0.5))
		else
			tiles.WinRate.Text = G.Dash
		end
		tiles.Tokens.Text = commas(State.Tokens())
		tiles.Earned.Text = commas(stats.TokensEarned or 0)
		tiles.Spins.Text = commas(stats.Spins or 0)
		local _, total = petTotals()
		tiles.Found.Text = string.format("%d / %d", discoveredCount(), catalogTotal())
		tiles.Owned.Text = commas(total)

		for id, label in pairs(rows) do
			local seconds = stats.BestTimes[id]
			if type(seconds) == "number" and seconds > 0 then
				label.Text = Util.FormatTime(seconds)
				label.TextColor3 = WHITE
			else
				label.Text = "--:--"
				label.TextColor3 = MUTED
			end
		end

		local okBattle, b = pcall(State.Battle)
		b = okBattle and type(b) == "table" and b or {}
		-- Phase 5 (10.5): the Trial ladder is gone; the dungeon line takes its place
		local dungeon = type(State.Dungeon) == "function" and State.Dungeon() or nil
		dungeon = type(dungeon) == "table" and dungeon or {}
		battleLabel.Text = string.format("Trophies: %s     Dungeon: floor %d cleared, %s runs\nDuels: %s won, %s lost     Boss raids: %s",
			commas(b.Trophies or 0), math.floor(tonumber(dungeon.Best) or 0), commas(math.floor(tonumber(dungeon.Runs) or 0)),
			commas(b.PvPWins or 0), commas(b.PvPLosses or 0), commas(b.Raids or 0))

		local lines = {}
		local order = PetCatalog.PerkOrder or { "MaxHealth", "TokenBonus", "StaminaRegen", "CheckpointHeal" }
		for _, key in ipairs(order) do
			local value = snapshot.Perks[key]
			if type(value) == "number" and value > 0 then
				table.insert(lines, PetCatalog.PerkLabel(key, value))
			end
		end
		if #lines > 0 then
			perksLabel.Text = table.concat(lines, "     ")
			perksLabel.TextColor3 = Theme.Lighten(GOOD, 0.25)
		else
			perksLabel.Text = "No perks yet. Put a pet in your team!"
			perksLabel.TextColor3 = MUTED
		end
	end
end

----------------------------------------------------------------------
-- Home window (Phase 2): the house, income, the Collector, prestige, and every station with its upgrade
----------------------------------------------------------------------
-- Phase 5 (3.4): the Home window's flow strip, the first item of its list: four neon tiles that tell the home loop
-- "Berry Farm Lv 13" -> "Pets earn Cash $3,000/min" -> "Berry Basket 1,240 / 3,000" -> "Food Machine: Feed = XP".
-- (kit-b U7b) each tile's Glyph is a PixelIcon name (NeonKit.Icon draws it); the second tile was "Pets eat & poop" with
-- the pile-of-poo emoji (rejects audit 5): it says what the player gets, the Cash note icon (Config.Icons.Cash)
P5.STRIP = {
	{ Id = "Farm", Title = "Berry Farm", Glyph = "berry", Color = "Pink" },
	{ Id = "Earn", Title = "Pets earn Cash", Glyph = "note", Color = "Green" },
	{ Id = "Basket", Title = "Berry Basket", Glyph = "basket", Color = "Purple" },
	{ Id = "Machine", Title = "Food Machine", Glyph = "pot", Color = "Orange" },
}
function P5.buildStrip(H, _content)
	local strip = makeFrame(H.List, "FlowStrip", { Size = UDim2.new(1, 0, 0, 84), LayoutOrder = -1000 })
	H.Strip = strip
	H.StripTiles = {}
	H.StripArrows = {}
	for i, spec in ipairs(P5.STRIP) do
		local card = P5.Kit.Card({ Name = "Flow_" .. spec.Id, Size = UDim2.fromOffset(180, 76), Color = spec.Color, Glow = false, Parent = strip })
		local icon = P5.Kit.Icon(card.Body, spec.Glyph, 24)
		icon.Position = UDim2.fromOffset(20, 21)
		local title = makeText(card.Body, "Title", spec.Title, "Heading", 18, WHITE, {
			Position = UDim2.fromOffset(36, 6),
			Size = UDim2.new(1, -40, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 18, Parent = title })
		local value = makeText(card.Body, "Value", "", "Display", 22, Theme.Lighten(P5.Kit.ColorOf(spec.Color), 0.35), {
			Position = UDim2.fromOffset(10, 40),
			Size = UDim2.new(1, -16, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 18, Parent = value })
		H.StripTiles[i] = { Card = card, Title = title, Value = value }
		if i < #P5.STRIP then
			H.StripArrows[i] = makeText(strip, "Arrow" .. i, "", "Title", 18, GOLD, { Size = UDim2.fromOffset(20, 76) })
			PixelIcon.Host(H.StripArrows[i], HOME_ICON.Arrow, 9) -- (kit-b U7b; 9 px: the gap between two tiles' rims is ~14 px)
		end
	end
end

-- 1 x 4 on wide windows, 2 x 2 on narrow ones (each tile keeps its title on one line); returns 0 (the strip scrolls
-- with the list)
function P5.layoutStrip(H, w)
	if not H.Strip then
		return 0
	end
	local inner = w - 62
	local wide = inner >= 720
	local cols = wide and 4 or 2
	local arrowW = 22
	local tileW = math.floor((inner - (cols - 1) * arrowW) / cols)
	local tileH = 76
	for i, tile in ipairs(H.StripTiles) do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		tile.Card.Root.Position = UDim2.fromOffset(col * (tileW + arrowW), row * (tileH + 8))
		tile.Card.Root.Size = UDim2.fromOffset(tileW, tileH)
		local arrow = H.StripArrows[i]
		if arrow then
			arrow.Visible = col < cols - 1
			arrow.Position = UDim2.fromOffset(col * (tileW + arrowW) + tileW + 1, row * (tileH + 8))
		end
	end
	local rows = math.ceil(#H.StripTiles / cols)
	H.Strip.Size = UDim2.new(1, 0, 0, rows * tileH + (rows - 1) * 8 + 4)
	return 0
end

function P5.paintStrip(H, home, income, open)
	if not H.StripTiles then
		return
	end
	local farm = P2.stationLevelOf(home, "Press1")
	local tiles = H.StripTiles
	tiles[1].Value.Text = farm >= 1 and ("Lv " .. farm) or "Build it!"
	local perMin = math.floor((tonumber(income) or 0) * 60 + 0.5)
	tiles[2].Value.Text = perMin > 0 and (P2.formatCash(perMin) .. " a minute") or "Garden pets"
	local berries = type(State.Berries) == "function" and State.Berries() or 0
	local folder = H.PlotFolder and H.PlotFolder() or nil
	local cap = folder and folder:GetAttribute("BerryCap")
	if type(cap) == "number" and cap > 0 then
		tiles[3].Value.Text = commas(berries) .. " / " .. commas(math.floor(cap))
	else
		tiles[3].Value.Text = commas(berries) .. " berries"
	end
	tiles[4].Value.Text = P2.stationLevelOf(home, "Kitchen") >= 1 and "Feed = XP" or "Build it!"
	H.StripOpen = open
end

-- Phase 6 (the player asked: no Home gate in the lobby, "improve the one in the inventory"): the Home window's hero.
-- A big golden button on top of the window, fixed above the scrolling list: a glossy orb with the house, "Go home" and
-- a short line, a round arrow badge on the right; hover 1.02 / press 0.97 (NeonKit.AttachFx) and a soft light sweep
-- across it when the window opens, on hover and every K.HERO_SHINE_EVERY seconds while it is shown. Without a home the
-- same spot shows "Claim a home" (Remotes.GoToSpot: the home portal toward a free gate, the server checks everything)
-- and the three steps of claiming one replace the list.
K.HERO_H = 96 -- the hero's height (design px)
K.HERO_H_SHORT = 76 -- ... on short windows (landscape phones)
K.HERO_SHINE = 0.75 -- seconds of one light sweep
K.HERO_SHINE_EVERY = 5.5
P5.HERO = {
	-- (kit-b U7a) the orb and the badge draw PixelIcons
	GoHome = { Title = "Go home", Sub = "A magic portal for you and your pets", Short = "Hop in with your pets!", Glyph = "house", Badge = "arrow" },
	ClaimHome = { Title = "Claim a home", Sub = "Get your own sky island, free!", Short = "Your own sky island, free!", Glyph = "house", Badge = "sparkle" },
}
-- what a home gives (the claim view's "Your home" tiles)
P5.CLAIM_GETS = {
	{ Glyph = "sprout", Title = "Pet Garden", Text = "Pets roam and play", Color = "Green" },
	{ Glyph = "apple", Title = "Berry Farm", Text = "Berries feed pets", Color = "Pink" },
	{ Glyph = "note", Title = "Cloud Cash", Text = "Pets earn for you", Color = "Cyan" },
}
P5.CLAIM_STEPS = {
	{ Glyph = "sparkle", Text = "Tap Claim a home: a magic portal opens" },
	{ Glyph = "dash", Text = "Walk into it: you land at a free home" },
	{ Glyph = "key", Text = "Press E at its gate. The home is yours!" },
}

-- one hero card (a clickable NeonKit card) -> { Root, Title, Sub, Orb, Badge, Shine, Fx }
function P5.heroCard(parent, id, callback)
	local spec = P5.HERO[id]
	local gold = Theme.NeonColor("Yellow")
	local card = P5.Kit.Card({
		Name = id,
		Class = "TextButton",
		Color = gold,
		Size = UDim2.new(1, 0, 0, K.HERO_H),
		Corner = 18,
		Fill = { Theme.Darken(gold, 0.1), Theme.Darken(Theme.NeonColor("Orange"), 0.4) },
		Floor = true,
		ZIndex = 4,
		Parent = parent,
	})
	local root = card.Root
	local hero = { Root = root, Card = card, Id = id }
	-- the light sweep, clipped to the rounded card (a CanvasGroup clips to its UICorner)
	local clip = Util.Create("CanvasGroup", {
		Name = "ShineClip",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = root,
	})
	corner(clip, "M")
	local shine = makeFrame(clip, "Shine", {
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(-0.25, 0, 0.5, 0),
		Size = UDim2.new(0, 70, 2.2, 0),
		Rotation = 18,
		ZIndex = 4,
	})
	Util.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.62),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = shine,
	})
	hero.Shine = shine
	card.Body.ZIndex = 5
	-- the orb with the house
	local orb = P5.Kit.Orb(card.Body, Color3.fromRGB(255, 244, 214), 64)
	orb.AnchorPoint = Vector2.new(0, 0.5)
	orb.Position = UDim2.new(0, 16, 0.5, 0)
	orb.ZIndex = 5
	local icon = P5.Kit.Icon(orb, spec.Glyph, 34)
	icon.ZIndex = 6
	hero.Orb = orb
	hero.Title = Theme.StyleTitle(makeText(card.Body, "Title", spec.Title, "Title", 34, WHITE, {
		Position = UDim2.new(0, 96, 0.5, -2),
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, -176, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextScaled = true,
		ZIndex = 6,
	}), "Section") -- (kit-b prep) a card's heading inside the Home window: the window's bar wears the ribbon
	Util.Create("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 24, Parent = hero.Title })
	hero.Sub = makeText(card.Body, "Sub", spec.Sub, "Body", 19, Color3.fromRGB(255, 247, 222), {
		Position = UDim2.new(0, 96, 0.5, 2),
		Size = UDim2.new(1, -176, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 6,
	})
	-- the round badge on the right (an arrow: "go")
	local badge = makeFrame(card.Body, "Badge", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(255, 251, 238),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		ZIndex = 6,
	})
	round(badge)
	stroke(badge, Theme.Darken(Theme.NeonColor("Orange"), 0.35), 3, 0)
	Theme.Gradient(badge, WHITE, Color3.fromRGB(255, 226, 160), 90)
	local badgeGlyph = makeText(badge, "Glyph", "", "Title", 28, Theme.NeonColor("Orange"), { Size = UDim2.fromScale(1, 1), ZIndex = 7 })
	PixelIcon.Host(badgeGlyph, spec.Badge, 27)
	hero.Badge = badge
	-- hover / press: a gentle grow and squash, a sweep on hover
	hero.Fx = P5.Kit.AttachFx(root, function(hover, press)
		if hover and not press then
			P5.heroShine(hero)
		end
	end, 1.02, 0.97)
	root.Activated:Connect(function()
		if root:GetAttribute("Disabled") ~= true then
			callback(root)
		end
	end)
	return hero
end

-- one soft light sweep across the hero (skipped while one is running)
function P5.heroShine(hero)
	if not hero or not hero.Shine or hero.Shining then
		return
	end
	hero.Shining = true
	hero.Shine.Position = UDim2.new(-0.25, 0, 0.5, 0)
	tween(hero.Shine, K.HERO_SHINE, { Position = UDim2.new(1.25, 0, 0.5, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	task.delay(K.HERO_SHINE + 0.05, function()
		hero.Shining = false
	end)
end

-- the hero buttons + the claim steps of the Home window (H = win.HomeUi)
function P5.buildHomeHero(H, win, onGoHome, onClaim)
	local content = win.Panel.Content
	local holder = makeFrame(content, "Hero", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, K.HERO_H),
		ZIndex = 4,
	})
	H.Hero = holder
	H.GoHomeHero = P5.heroCard(holder, "GoHome", onGoHome)
	H.ClaimHero = P5.heroCard(holder, "ClaimHome", onClaim)
	H.GoHome = H.GoHomeHero.Root
	H.ClaimHome = H.ClaimHero.Root
	-- without a home: three steps (fixed under the hero; scrolls on very short windows)
	local steps = scroller(content, "ClaimSteps", {
		Position = UDim2.fromOffset(12, K.HERO_H + 24),
		Size = UDim2.new(1, -24, 1, -(K.HERO_H + 36)),
		Visible = false,
	})
	pad(steps, 2, 2, 14, 6)
	H.ClaimList = listLayout(steps, Enum.FillDirection.Vertical, 12)
	makeText(steps, "Caption", "How to get your home", "Heading", 21, MUTED, {
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
	})
	for i, step in ipairs(P5.CLAIM_STEPS) do
		local row = makeInset(steps, "Step" .. i, { Size = UDim2.new(1, 0, 0, 72), LayoutOrder = i })
		local num = makeFrame(row, "Num", {
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.NeonColor("Yellow"),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(40, 40),
		})
		round(num)
		Theme.Gradient(num, Theme.Lighten(Theme.NeonColor("Yellow"), 0.2), Theme.Darken(Theme.NeonColor("Yellow"), 0.25), 90)
		makeText(num, "N", tostring(i), "Title", 24, WHITE, { Size = UDim2.fromScale(1, 1) })
		local glyph = P5.Kit.Icon(row, step.Glyph, 28)
		glyph.AnchorPoint = Vector2.new(0, 0.5)
		glyph.Position = UDim2.new(0, 62, 0.5, 0)
		makeText(row, "Text", step.Text, "Body", 21, WHITE, {
			Position = UDim2.new(0, 104, 0, 0),
			Size = UDim2.new(1, -114, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
		})
	end
	-- what a home gives: three small neon tiles
	makeText(steps, "GetsCaption", "Your home has", "Heading", 21, MUTED, {
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 10,
	})
	local gets = makeFrame(steps, "Gets", { Size = UDim2.new(1, 0, 0, 132), LayoutOrder = 11 })
	Util.Create("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 1, 0),
		CellPadding = UDim2.new(0, 12, 0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gets,
	})
	for i, item in ipairs(P5.CLAIM_GETS) do
		local tile = P5.Kit.Card({ Name = "Get" .. i, Size = UDim2.fromOffset(160, 132), Color = item.Color, Glow = false, LayoutOrder = i, Parent = gets })
		local orb = P5.Kit.Orb(tile.Body, item.Color, 52)
		orb.Position = UDim2.new(0.5, 0, 0, 36)
		P5.Kit.Icon(orb, item.Glyph, 28)
		makeText(tile.Body, "Title", item.Title, "Heading", 20, WHITE, {
			Position = UDim2.new(0, 6, 0, 68),
			Size = UDim2.new(1, -12, 0, 24),
		})
		makeText(tile.Body, "Text", item.Text, "Body", 18, Theme.Lighten(P5.Kit.ColorOf(item.Color), 0.45), {
			Position = UDim2.new(0, 6, 0, 94),
			Size = UDim2.new(1, -12, 0, 24),
		})
	end
	H.ClaimGets = gets
	H.ClaimSteps = steps
end

-- shows the hero of the current state (home or none), its disabled look in a match, and places the list under it
function P5.paintHomeHero(H, hasHome, matchOn)
	if not H.Hero then
		return
	end
	H.GoHomeHero.Root.Visible = hasHome
	H.ClaimHero.Root.Visible = not hasHome
	H.ClaimSteps.Visible = not hasHome
	H.List.Visible = hasHome
	for _, hero in ipairs({ H.GoHomeHero, H.ClaimHero }) do
		hero.Root:SetAttribute("Disabled", matchOn and true or false)
		hero.Card.SetColor(matchOn and Theme.Neon.Grey or Theme.NeonColor("Yellow"))
		hero.Badge.Visible = not matchOn
	end
	H.HomeState = hasHome
end

-- (w: the window's design width; narrow windows get the short line under the title)
function P5.layoutHomeHero(H, short, w)
	if not H.Hero then
		return 0
	end
	local h = short and K.HERO_H_SHORT or K.HERO_H
	H.Hero.Size = UDim2.new(1, -24, 0, h)
	for _, hero in ipairs({ H.GoHomeHero, H.ClaimHero }) do
		hero.Root.Size = UDim2.new(1, 0, 0, h)
		local orb = short and 52 or 64
		hero.Orb.Size = UDim2.fromOffset(orb, orb)
		hero.Orb.Position = UDim2.new(0, short and 12 or 16, 0.5, 0)
		local x = short and 76 or 96
		hero.Title.Position = UDim2.new(0, x, 0.5, short and 0 or -2)
		hero.Title.Size = UDim2.new(1, -(x + 76), 0, short and 34 or 40)
		hero.Sub.Position = UDim2.new(0, x, 0.5, 2)
		hero.Sub.Size = UDim2.new(1, -(x + 76), 0, 26)
		local spec = P5.HERO[hero.Id]
		hero.Sub.Text = (short or (tonumber(w) or 999) < 640) and spec.Short or spec.Sub
		hero.Badge.Size = UDim2.fromOffset(short and 44 or 52, short and 44 or 52)
	end
	H.ClaimSteps.Position = UDim2.fromOffset(12, h + 22)
	H.ClaimSteps.Size = UDim2.new(1, -24, 1, -(h + 32))
	return h
end

-- the light sweep while the window is shown (one loop per opening; the token stops it)
function P5.heroLoop(H, win)
	H.ShineToken = (H.ShineToken or 0) + 1
	local mine = H.ShineToken
	task.delay(0.3, function()
		while H.ShineToken == mine and win.Shown do
			P5.heroShine(H.HomeState == false and H.ClaimHero or H.GoHomeHero)
			task.wait(K.HERO_SHINE_EVERY)
		end
	end)
end

local buildHome -- (the window's helpers live in this do-block: Lua's 200-local limit of the main chunk)
do
	local HOME_SECTIONS = {
		{ Id = "Pets", Title = "Pets at home", Kinds = { Garden = true, FoodMachine = true, Training = true, Fusion = true } },
		{ Id = "Money", Title = "Berries & Cloud Cash", Kinds = { Farm = true, Plant = true, Magnet = true, Vault = true } },
		{ Id = "House", Title = "House", Kinds = { House = true, Arena = true } },
		{ Id = "Decor", Title = "Decor", Kinds = { Decor = true } },
	}

	local function shortPercent(fraction)
		local p = (tonumber(fraction) or 0) * 100
		if math.abs(p - math.floor(p + 0.5)) < 0.05 then
			return tostring(math.floor(p + 0.5)) .. "%"
		end
		return string.format("%.1f%%", p)
	end

	local function shortNumber(n)
		n = tonumber(n) or 0
		if math.abs(n - math.floor(n + 0.5)) < 1e-6 then
			return tostring(math.floor(n + 0.5))
		end
		return (string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", ""))
	end

	-- What a station does at `level` (a short phrase), or nil.
	local function effectText(def, level)
		if type(def) ~= "table" or type(def.Effects) ~= "table" or level < 1 then
			return nil
		end
		local e = def.Effects[math.min(level, def.MaxLevel or level)]
		if type(e) ~= "table" then
			return nil
		end
		local kind = def.Kind
		if kind == "Farm" then
			return "+" .. shortNumber(e.Food) .. " food, more berries"
		elseif kind == "Plant" then
			return "+" .. shortNumber(e.Food) .. " food"
		elseif kind == "Magnet" then
			return "Scoop " .. shortNumber(e.Radius) .. " studs, piles " .. shortNumber((tonumber(e.PileSeconds) or 0) / 60) .. " min"
		elseif kind == "Garden" then
			local lucky = tonumber(e.Lucky) or 0
			if lucky <= 0 then
				return "Rainbow coins"
			end
			return shortPercent(lucky) .. " Lucky coins"
		elseif kind == "FoodMachine" then
			return "Feeds fill " .. shortPercent(e.FeedShare) .. " of a bar"
		elseif kind == "Training" then
			local slots = tonumber(e.Slots) or 0
			return slots .. (slots == 1 and " pet trains" or " pets train") .. " at once"
		elseif kind == "Vault" then
			return "Offline " .. shortPercent(e.OfflinePercent) .. " for " .. tostring(e.OfflineHours or 0) .. "h"
		elseif kind == "House" then
			return tostring(e.Name or e.Tier or "")
		elseif kind == "Fusion" then
			if (tonumber(e.TokenDiscount) or 0) > 0 then
				return "-" .. shortPercent(e.TokenDiscount) .. " fusion cost"
			end
			return "Fuse pets"
		elseif kind == "Arena" then
			return "Pet battles"
		elseif kind == "Decor" then
			return tostring(e.Style or "Decor") .. " style"
		end
		return nil
	end

	-- "Needs Cloud Press 2 Lv 2" for a station whose tree is not met yet (nil when it is)
	local function treeReason(def, home)
		if type(def) ~= "table" or type(def.Requires) ~= "table" then
			return nil
		end
		local keys = {}
		for key in pairs(def.Requires) do
			if key ~= "Prestige" and P2.stationDef(key) and key ~= "House" then
				keys[#keys + 1] = key
			end
		end
		table.sort(keys, function(a, b)
			return (P2.stationDef(a).Order or 0) < (P2.stationDef(b).Order or 0)
		end)
		for _, key in ipairs(keys) do
			local need = tonumber(def.Requires[key]) or 0
			if P2.stationLevelOf(home, key) < need then
				local other = P2.stationDef(key)
				local name = other and other.Name or key
				if need <= 1 then
					return "Needs the " .. name
				end
				return "Needs " .. name .. " Lv " .. need
			end
		end
		return nil
	end

	-- the Garden pets that eat (any role, open places, not training), as a slot -> TycoonCatalog.IncomePerSecond entry
	-- map (only places 1..GardenSlots count)
	local function gardenEntries(home)
		local entries = {}
		local slots = P2.catalogCall("GardenSlots", home) or 0
		local garden = type(home.Garden) == "table" and home.Garden or {}
		for slot = 1, slots do
			local key = garden[slot]
			if type(key) == "string" then
				local def = P2.defOfKey(key)
				if def and State.OwnedCount(key) > 0 and not P2.job(key) then
					entries[slot] = { Def = def, Level = (P2.petLevel(key)), Stage = P2.stage(key), Key = key }
				end
			end
		end
		return entries
	end

	-- cash/s, { Food, Pets, Lucky, Multiplier } computed here (the plot's IncomePerSecond attribute wins when present)
	local function homeIncome(home)
		local total, parts = P2.catalogCall("IncomePerSecond", home, gardenEntries(home))
		if type(total) ~= "number" then
			return 0, { Food = 0, Pets = 0, Lucky = 1, Multiplier = 1 }
		end
		if type(parts) ~= "table" then
			parts = { Food = 0, Pets = 0, Lucky = 1, Multiplier = 1 }
		end
		return total, parts
	end

	-- the local player's plot folder (workspace.NimbusLobby ... Spot_NN, attribute SpotIndex), or nil
	local function plotFolder()
		local index = LocalPlayer and LocalPlayer:GetAttribute(Config.Attr.SpotIndex)
		if type(index) ~= "number" then
			return nil
		end
		local folder = Home.Folder
		if folder and folder.Parent and folder:GetAttribute("SpotIndex") == index then
			return folder
		end
		folder = nil
		local lobby = workspace:FindFirstChild("NimbusLobby")
		if lobby then
			local named = lobby:FindFirstChild(string.format("Spot_%02d", index), true)
			if named and named:GetAttribute("SpotIndex") == index then
				folder = named
			end
		end
		Home.Folder = folder
		return folder
	end

	-- coins waiting on the lawn, income/s, income parts, open garden places: the plot's live attributes (CollectorCash,
	-- IncomePerSecond, GardenSlots), else computed from the synced home
	local function homeLive(home)
		local folder = plotFolder()
		local localIncome, parts = homeIncome(home)
		local income = folder and folder:GetAttribute("IncomePerSecond")
		if type(income) ~= "number" then
			income = localIncome
		end
		local cash = folder and folder:GetAttribute("CollectorCash")
		if type(cash) ~= "number" then
			cash = tonumber(home.CollectorCash) or 0
		end
		local open = folder and folder:GetAttribute("GardenSlots")
		if type(open) ~= "number" then
			open = P2.catalogCall("GardenSlots", home) or 0
		end
		return cash, income, parts, open
	end

	function buildHome(win)
		local content = win.Panel.Content
		local H = { Rows = {}, Sections = {}, Pads = {}, Tall = false, Cards = {} }
		win.HomeUi = H

		-- left: the summary column (scrolls on short screens); right: the station list
		local left = scroller(content, "Summary", {
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.new(0, K.HOME_LEFT_W, 1, -24),
		})
		pad(left, 2, 2, 12, 6)
		listLayout(left, Enum.FillDirection.Vertical, 10)
		H.Left = left
		local list = scroller(content, "Stations", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.new(1, -(K.HOME_LEFT_W + 36), 1, -24),
		})
		pad(list, 2, 2, 14, 8)
		listLayout(list, Enum.FillDirection.Vertical, 8)
		H.List = list
		-- Phase 5 (3.4): the flow strip on top (fixed, never scrolls): Berry Farm -> pets eat & poop -> Berry Basket ->
		-- Food Machine. It tells the whole home loop in four tiles.
		safe("home strip", P5.buildStrip, H, content)

		------------------------------------------------------------------
		-- summary cards
		------------------------------------------------------------------
		local function card(name, order, height)
			local c = makeInset(left, name, {
				Size = UDim2.new(1, 0, 0, height),
				LayoutOrder = order,
			})
			H.Cards[#H.Cards + 1] = c
			return c
		end

		-- house: tier, Home Level, prestige stars (top-right), the next house
		local house = card("HouseCard", 1, 116)
		local disc = makeFrame(house, "HouseDisc", {
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(64, 64),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
		})
		round(disc)
		stroke(disc, NAVY, 3, 0)
		Theme.Gradient(disc, Theme.Lighten(C2.Kind.House, 0.35), Theme.Darken(C2.Kind.House, 0.2), 90)
		H.HouseGlyph = makeText(disc, "Glyph", "", "Title", 36, WHITE, { Size = UDim2.new(1, 0, 1, 0) })
		PixelIcon.Set(H.HouseGlyph, HOME_ICON.House, 36) -- (kit-b U7b) the tier's PixelIcon (paintSummary)
		H.HouseName = makeText(house, "Tier", "Cottage", "Title", 30, Theme.Lighten(C2.Kind.House, 0.4), {
			Position = UDim2.fromOffset(88, 8),
			Size = UDim2.new(1, -170, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 20, Parent = H.HouseName })
		H.Stars = makeText(house, "Stars", "", "Title", 22, GOLD, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(78, 28),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		H.HomeLevel = makeText(house, "HomeLevel", "Home Level 0", "Heading", 21, WHITE, {
			Position = UDim2.fromOffset(88, 46),
			Size = UDim2.new(1, -100, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		H.NextHouse = makeText(house, "NextHouse", "", "Body", 18, MUTED, {
			Position = UDim2.fromOffset(14, 84),
			Size = UDim2.new(1, -28, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 18, Parent = H.NextHouse })

		-- income per second (the prestige multiplier as a gold tag beside it)
		local income = card("IncomeCard", 2, 98)
		makeText(income, "Caption", "Income", "Heading", 19, MUTED, {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		H.Income = makeText(income, "PerSecond", G.Cash .. "0/s", "Display", 36, C2.Cash, {
			Position = UDim2.fromOffset(14, 30),
			Size = UDim2.new(1, -110, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 36, MinTextSize = 22, Parent = H.Income })
		H.Multiplier = colorPill(income, "Multiplier", "x1", GOLD, 19, 0)
		H.Multiplier.AnchorPoint = Vector2.new(1, 0)
		H.Multiplier.Position = UDim2.new(1, -14, 0, 38)
		H.IncomeParts = makeText(income, "Parts", "", "Body", 18, MUTED, {
			Position = UDim2.fromOffset(14, 70),
			Size = UDim2.new(1, -28, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})

		-- the Pet Garden: coins waiting on the lawn, coins per minute, places, the legacy lines (no Collect: kids walk
		-- over their coins)
		local garden = card("GardenCard", 3, 168)
		PixelIcon.Lead(makeText(garden, "Caption", "Pet Garden", "Heading", 19, MUTED, {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(0.6, -14, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		}), HOME_ICON.Seedling) -- (kit-b U7b)
		H.Places = makeText(garden, "Places", "", "Heading", 18, Theme.Lighten(C2.Kind.Garden, 0.35), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 8),
			Size = UDim2.new(0.45, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		H.CoinsWaiting = makeText(garden, "CoinsWaiting", "", "Display", 28, C2.Cash, {
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.new(1, -28, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 20, Parent = H.CoinsWaiting })
		H.CoinsPerMin = makeText(garden, "CoinsPerMinute", "", "Heading", 18, WHITE, {
			Position = UDim2.fromOffset(14, 70),
			Size = UDim2.new(1, -28, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		H.GardenTip = makeText(garden, "Tip", "", "Body", 18, MUTED, {
			Position = UDim2.fromOffset(14, 96),
			Size = UDim2.new(1, -28, 0, 64),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})

		-- prestige: stars, Home Level progress, the requirement, the reward, the button
		local prestige = card("PrestigeCard", 4, 204)
		H.PrestigeTitle = makeText(prestige, "Caption", "Prestige", "Heading", 19, MUTED, {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		H.PrestigeBar = CloudUI.Bar({
			Name = "PrestigeBar",
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -28, 0, 30),
			Height = 30,
			TextSize = 20,
			Color = GOLD,
			Parent = prestige,
		})
		H.PrestigeNeed = makeText(prestige, "Need", "", "Heading", 18, C2.Lock, {
			Position = UDim2.fromOffset(14, 72),
			Size = UDim2.new(1, -28, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		H.PrestigeReward = makeText(prestige, "Reward", "", "Body", 18, MUTED, {
			Position = UDim2.fromOffset(14, 98),
			Size = UDim2.new(1, -28, 0, 44),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		H.PrestigeButton = CloudUI.Button({
			Name = "Prestige",
			Text = "Prestige",
			Style = "Gold",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -28, 0, 50),
			TextSize = 24,
			Callback = function()
				if H.ShowConfirm then
					H.ShowConfirm(true)
				end
			end,
			Parent = prestige,
		})

		-- Phase 6: the big golden Go home hero on top (fixed above the list, always in view); without a home the same
		-- spot offers Claim a home (Remotes.GoToSpot: the home portal toward a free gate) with the three steps
		P5.buildHomeHero(H, win, function()
			if inMatch() then
				showHint("You cannot go home during a match.", "info")
				return
			end
			if fireKeyed("HomeAction:GoHome", "HomeAction", "GoHome") then
				closeWindow("Home")
			end
		end, function()
			if inMatch() then
				showHint("You cannot go home during a match.", "info")
				return
			end
			if fire("GoToSpot") then
				closeWindow("Home")
				showHint("Press E at the gate to claim your home!", "info")
			end
		end)

		------------------------------------------------------------------
		-- station rows
		------------------------------------------------------------------
		local function requestUpgrade(row)
			local pad = H.Pads[row.Id]
			if inMatch() then
				showHint("Homes are closed during a match.", "info")
				return
			end
			if not P2.hasHome() then
				showHint("Claim a home first: press E at a free gate.", "info")
				return
			end
			if not pad then
				return
			end
			if pad.Locked then
				showHint(tostring(pad.Locked), "info")
				return
			end
			local price = tonumber(pad.Price) or 0
			local cash = P2.cashBalance()
			if cash < price then
				showHint("You need " .. P2.formatCash(price - cash) .. " more Cash.", "bad")
				return
			end
			if fireKeyed("HomeAction:Upgrade:" .. row.Id, "HomeAction", "Upgrade", row.Id) then
				row.PendingAt = os.clock()
				row.PendingLevel = P2.stationLevelOf(P2.homeData(), row.Id)
				if H.Refresh then
					H.Refresh()
				end
			end
		end

		local function buildRow(def, parent, order)
			local color = C2.Kind[def.Kind] or BUTTONS.Blue
			local row = { Id = def.Id, Def = def, Pips = {} }
			local frame = makeInset(parent, "Station_" .. def.Id, {
				Size = UDim2.new(1, 0, 0, K.STATION_ROW_H),
				LayoutOrder = order,
			})
			row.Frame = frame
			row.Disc = makeFrame(frame, "Icon", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 12, 0.5, 0),
				Size = UDim2.fromOffset(64, 64),
				BackgroundTransparency = 0,
				BackgroundColor3 = color,
			})
			corner(row.Disc, "M")
			stroke(row.Disc, NAVY, 3, 0)
			Theme.Gradient(row.Disc, Theme.Lighten(color, 0.35), Theme.Darken(color, 0.2), 90)
			-- (kit-b U7b) the station's PixelIcon (its TycoonCatalog Icon), the house for one that names none
			PixelIcon.Host(makeText(row.Disc, "Glyph", "", "Title", 34, WHITE, { Size = UDim2.new(1, 0, 1, 0) }), PixelIcon.Bitmaps[def.Icon] and def.Icon or HOME_ICON.House, 36)
			row.Name = makeText(frame, "Name", def.Name, "Title", 24, WHITE, {
				Position = UDim2.fromOffset(88, 6),
				Size = UDim2.new(1, -360, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextScaled = true,
			})
			Util.Create("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 18, Parent = row.Name })
			row.Level = makeText(frame, "Level", "Lv 0/" .. tostring(def.MaxLevel), "Heading", 19, MUTED, {
				Position = UDim2.fromOffset(88, 38),
				Size = UDim2.fromOffset(96, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			row.PipRow = makeFrame(frame, "Pips", {
				Position = UDim2.fromOffset(186, 42),
				Size = UDim2.fromOffset(170, 16),
			})
			listLayout(row.PipRow, Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
			for i = 1, math.min(def.MaxLevel or 1, 10) do
				local pip = makeFrame(row.PipRow, "Pip" .. i, {
					Size = UDim2.fromOffset(13, 13),
					BackgroundTransparency = 0,
					BackgroundColor3 = Color3.fromRGB(14, 20, 52),
					LayoutOrder = i,
				})
				corner(pip, "S")
				stroke(pip, NAVY, 1.5, 0)
				row.Pips[i] = pip
			end
			row.Info = makeText(frame, "Info", "", "Body", 18, MUTED, {
				Position = UDim2.fromOffset(88, 64),
				Size = UDim2.new(1, -360, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			-- right block: price + button, a lock reason, or MAX
			row.Right = makeFrame(frame, "Action", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(330, 76),
			})
			row.Price = makeText(row.Right, "Price", "", "Display", 26, C2.Cash, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(150, 32),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextScaled = true,
			})
			Util.Create("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 18, Parent = row.Price })
			row.Button = CloudUI.Button({
				Name = "Upgrade",
				Text = "Upgrade",
				Style = "Green",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.fromOffset(164, 54),
				TextSize = 22,
				Callback = function()
					requestUpgrade(row)
				end,
				Parent = row.Right,
			})
			row.Lock = makeText(row.Right, "Locked", "", "Heading", 18, C2.Lock, {
				Size = UDim2.new(1, 0, 1, 0),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				Visible = false,
			})
			row.Max = colorPill(row.Right, "Max", "MAX", GOLD, 20, 1)
			row.Max.AnchorPoint = Vector2.new(1, 0.5)
			row.Max.Position = UDim2.new(1, 0, 0.5, 0)
			row.Max.Visible = false
			H.Rows[def.Id] = row
			return row
		end

		local order = 0
		local stations = TycoonCatalog and TycoonCatalog.Stations or {}
		for _, section in ipairs(HOME_SECTIONS) do
			order = order + 1
			local header = makeFrame(list, "Section_" .. section.Id, {
				Size = UDim2.new(1, 0, 0, 34),
				LayoutOrder = order,
			})
			Theme.StyleTitle(makeText(header, "Title", section.Title, "Title", 24, WHITE, {
				Position = UDim2.fromOffset(6, 0),
				Size = UDim2.new(1, -12, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
			}), "Section")
			H.Sections[#H.Sections + 1] = header
			for _, def in ipairs(stations) do
				if type(def) == "table" and section.Kinds[def.Kind] then
					order = order + 1
					buildRow(def, list, order)
				end
			end
		end
		if not TycoonCatalog then
			H.Missing = makeText(list, "Missing", "Your home is getting ready. Try again in a moment!", "Body", 20, MUTED, {
				Size = UDim2.new(1, 0, 0, 60),
				TextWrapped = true,
				LayoutOrder = 1,
			})
		end

		------------------------------------------------------------------
		-- prestige confirmation (resets stations and Cash)
		------------------------------------------------------------------
		local confirm = makeFrame(content, "PrestigeConfirm", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 0.35,
			BackgroundColor3 = Color3.fromRGB(8, 12, 32),
			Visible = false,
			ZIndex = 30,
		})
		corner(confirm, "M")
		local box = makeFrame(confirm, "Box", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.fromOffset(K.CONFIRM_W, K.CONFIRM_H),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE, -- the UIGradient below multiplies this colour
			ZIndex = 31,
		})
		corner(box, "M")
		stroke(box, GOLD, 4, 0)
		Theme.Gradient(box, Colors.PanelLight, Colors.Panel, 90)
		H.ConfirmBox = box
		Theme.StyleTitle(makeText(box, "Title", "Prestige now?", "Title", 32, GOLD, {
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 40),
			ZIndex = 32,
		}), "Section") -- (kit-b prep) a dialog's title: the ribbon is for window titles only
		-- three lines: what starts over, what stays, what the new star gives
		local lines = makeFrame(box, "Lines", {
			Position = UDim2.fromOffset(16, 62),
			Size = UDim2.new(1, -32, 0, 3 * 62 + 2 * 8),
			ZIndex = 32,
		})
		listLayout(lines, Enum.FillDirection.Vertical, 8)
		H.ConfirmLines = {}
		H.ConfirmRows = {}
		H.ConfirmList = lines
		for i, spec in ipairs({
			{ "Reset", "Starts over", Theme.Lighten(BAD, 0.3) },
			{ "Keep", "You keep", Theme.Lighten(GOOD, 0.35) },
			{ "Gain", "You get", GOLD },
		}) do
			local line = makeInset(lines, "Line_" .. spec[1], { Size = UDim2.new(1, 0, 0, 62), LayoutOrder = i, ZIndex = 32 })
			H.ConfirmRows[#H.ConfirmRows + 1] = line
			makeText(line, "Label", spec[2], "Heading", 19, spec[3], {
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(0, 116, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 33,
			})
			H.ConfirmLines[spec[1]] = makeText(line, "Text", "", "Body", 19, WHITE, {
				Position = UDim2.fromOffset(132, 0),
				Size = UDim2.new(1, -144, 1, 0),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 33,
			})
		end
		local buttons = makeFrame(box, "Buttons", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -32, 0, 56),
			ZIndex = 32,
		})
		listLayout(buttons, Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		local yes = CloudUI.Button({
			Name = "ConfirmPrestige",
			Text = "Prestige!",
			Style = "Gold",
			Size = UDim2.fromOffset(220, 56),
			TextSize = 25,
			LayoutOrder = 1,
			Callback = function()
				H.ShowConfirm(false)
				if inMatch() then
					showHint("Finish your match first.", "info")
					return
				end
				fireKeyed("HomeAction:Prestige", "HomeAction", "Prestige")
			end,
			Parent = buttons,
		})
		yes.ZIndex = 33
		local no = CloudUI.Button({
			Name = "CancelPrestige",
			Text = "Not yet",
			Style = "Blue",
			Size = UDim2.fromOffset(170, 56),
			TextSize = 23,
			LayoutOrder = 2,
			Callback = function()
				H.ShowConfirm(false)
			end,
			Parent = buttons,
		})
		no.ZIndex = 33

		function H.ShowConfirm(on)
			if on then
				local home = P2.homeData()
				local ok = P2.catalogCall("CanPrestige", home)
				if not ok then
					showHint("Not ready to prestige yet.", "info")
					return
				end
				local stars = math.floor(tonumber(home.Prestige) or 0)
				local P = TycoonCatalog and TycoonCatalog.Prestige or {}
				local gems = P2.catalogCall("PrestigeGems", stars + 1) or P.GemReward or 0
				local mult = P2.catalogCall("PrestigeMultiplier", stars + 1) or ((P.IncomeMultiplier or 1.25) ^ (stars + 1))
				H.ConfirmLines.Reset.Text = "Your Cash, the Cloud Cash on your lawn and your stations (not the Garden)"
				H.ConfirmLines.Keep.Text = "Pets, levels, evolutions, training, your teams, berries, the Garden and decor"
				local places = math.min(tonumber(P.GardenSlotsMax) or 12, (tonumber(P.GardenSlotsBase) or 3) + (tonumber(P.GardenSlotsPerStar) or 1) * (stars + 1))
				local gain = "Star " .. (stars + 1) .. ": x" .. shortNumber(math.floor(mult * 100 + 0.5) / 100) .. " coins, garden place " .. places .. " and " .. commas(gems) .. " Gems"
				if stars + 1 == (tonumber(P.FusionUnlock) or 1) then
					gain = gain .. ", the Fusion Machine"
				end
				H.ConfirmLines.Gain.Text = gain
			end
			confirm.Visible = on == true
		end

		------------------------------------------------------------------
		-- refresh
		------------------------------------------------------------------
		local function paintRow(row, home, cash)
			local def = row.Def
			local level = P2.stationLevelOf(home, def.Id)
			local maxLevel = def.MaxLevel or 1
			local cap = P2.catalogCall("MaxLevelAt", def.Id, home) or maxLevel
			local pad = H.Pads[def.Id]
			local color = C2.Kind[def.Kind] or BUTTONS.Blue
			if row.PendingAt and (level ~= row.PendingLevel or os.clock() - row.PendingAt > 3) then
				row.PendingAt = nil
			end
			-- name (the House shows its tier)
			if def.Kind == "House" then
				local tier = level >= 1 and P2.catalogCall("HouseTier", level) or nil
				row.Name.Text = "House: " .. ((tier and tier.Name) or "not built")
			end
			row.Level.Text = "Lv " .. level .. "/" .. maxLevel
			row.Level.TextColor3 = level >= maxLevel and GOLD or MUTED
			for i, pip in ipairs(row.Pips) do
				if i <= level then
					pip.BackgroundColor3 = Theme.Lighten(color, 0.25)
				elseif i <= cap then
					pip.BackgroundColor3 = Color3.fromRGB(36, 50, 100)
				else
					pip.BackgroundColor3 = Color3.fromRGB(14, 20, 52)
				end
			end
			-- what it does now -> next
			local now = effectText(def, level)
			local nextText = level < maxLevel and effectText(def, level + 1) or nil
			local info
			if level < 1 then
				info = nextText and ("Build: " .. nextText) or (def.Blurb or "")
			elseif nextText and nextText ~= now and now then
				-- "+10% press Cash -> +20% press Cash" reads as "+10% -> +20% press Cash"; when both halves do not fit
				-- the row, only the next level is shown ("Next: 6 dishes, x1.5 speed")
				local a1, aRest = now:match("^(%S+)(%s.+)$")
				local b1, bRest = nextText:match("^(%S+)(%s.+)$")
				if a1 and b1 and aRest == bRest then
					info = a1 .. " -> " .. b1 .. aRest
				else
					info = now .. " -> " .. nextText
				end
				if #info > K.INFO_CHARS then
					info = "Next: " .. nextText
				end
			else
				info = now or (def.Blurb or "")
			end
			row.Info.Text = info
			row.Info.TextColor3 = MUTED
			-- right block
			local lock = nil
			if level >= maxLevel then
				row.Max.Visible = true
				row.Button.Visible = false
				row.Price.Visible = false
				row.Lock.Visible = false
				return
			end
			row.Max.Visible = false
			if pad then
				lock = pad.Locked
			else
				lock = treeReason(def, home) or "Not unlocked yet"
			end
			if lock then
				row.Button.Visible = false
				row.Price.Visible = false
				row.Lock.Visible = true
				row.Lock.Text = tostring(lock)
				PixelIcon.Mark(row.Lock, HOME_ICON.Lock) -- (kit-b U7b)
				return
			end
			row.Lock.Visible = false
			row.Button.Visible = true
			row.Price.Visible = true
			local price = tonumber(pad.Price) or 0
			row.Price.Text = price > 0 and P2.formatCash(price) or "FREE"
			local short = price > cash
			row.Price.TextColor3 = short and Theme.Lighten(BAD, 0.35) or C2.Cash
			local pending = row.PendingAt ~= nil
			row.Button.Text = pending and "..." or (level < 1 and "Build" or "Upgrade")
			CloudUI.SetStyle(row.Button, level < 1 and "Gold" or "Green")
			CloudUI.SetDisabled(row.Button, short or pending or inMatch() or not P2.hasHome())
		end

		local function paintSummary(home)
			local tierIndex, tier = P2.catalogCall("HouseTierOf", home)
			local houseLevel = P2.stationLevelOf(home, "House")
			local tiers = TycoonCatalog and TycoonCatalog.HouseTiers or {}
			local homeLevel = P2.catalogCall("HomeLevelOf", home) or tonumber(home.Level) or 0
			local stars = math.floor(tonumber(home.Prestige) or 0)
			if houseLevel < 1 then
				H.HouseName.Text = "Empty yard"
			else
				H.HouseName.Text = (type(tier) == "table" and tier.Name) or "Cottage"
			end
			local houseIcon = type(tier) == "table" and tier.Icon or nil
			PixelIcon.Set(H.HouseGlyph, PixelIcon.Bitmaps[houseIcon] and houseIcon or HOME_ICON.House, 36)
			H.HomeLevel.Text = "Home Level " .. homeLevel
			-- prestige stars in the corner (none before the first prestige)
			H.Stars.Visible = stars > 0
			-- (kit-b U7b) PixelIcon stars: one per prestige up to three, then one star and "x7"
			H.Stars.Text = stars <= 3 and "" or ("x" .. stars)
			if stars > 0 then
				local shown = stars <= 3 and stars or 1
				PixelIcon.Mark(H.Stars, HOME_ICON.Star, { Count = shown, Of = shown })
			end
			local nextTier = tiers[(houseLevel >= 1 and (tierIndex or 1) or 0) + 1]
			H.NextHouse.TextColor3 = MUTED
			if houseLevel < 1 then
				H.NextHouse.Text = "Build your Cottage on the House pad"
			elseif type(nextTier) == "table" then
				local at = tonumber(nextTier.HomeLevel) or 0
				if homeLevel >= at then
					H.NextHouse.Text = "Upgrade the House to a " .. tostring(nextTier.Name) .. "!"
					H.NextHouse.TextColor3 = Theme.Lighten(GOOD, 0.35)
				else
					H.NextHouse.Text = "Next: " .. tostring(nextTier.Name) .. " at Home Level " .. at
				end
			else
				H.NextHouse.Text = "Your " .. ((type(tier) == "table" and tier.Name) or "house") .. " is complete!"
			end
			PixelIcon.Mark(H.NextHouse, H.NextHouse.Text:sub(1, 7) == "Upgrade" and HOME_ICON.Check or nil) -- (kit-b U7b)
			-- prestige
			local P = TycoonCatalog and TycoonCatalog.Prestige or {}
			local need = tonumber(P.HomeLevel) or 40
			H.PrestigeTitle.Text = "Prestige  " .. stars .. "  ->  " .. (stars + 1) .. ((stars + 1 == 1) and " star" or " stars")
			H.PrestigeBar.SetFraction(need > 0 and math.min(1, homeLevel / need) or 0)
			H.PrestigeBar.SetText("Home Level " .. math.min(homeLevel, need) .. "/" .. need)
			local ok, reason = P2.catalogCall("CanPrestige", home)
			if ok then
				H.PrestigeNeed.Text = "Ready to prestige!"
				PixelIcon.Mark(H.PrestigeNeed, HOME_ICON.Check) -- (kit-b U7b)
				H.PrestigeNeed.TextColor3 = Theme.Lighten(GOOD, 0.35)
			else
				H.PrestigeNeed.Text = tostring(reason or "Not ready yet")
				PixelIcon.Mark(H.PrestigeNeed, HOME_ICON.Lock)
				H.PrestigeNeed.TextColor3 = C2.Lock
			end
			local gems = P2.catalogCall("PrestigeGems", stars + 1) or P.GemReward or 0
			local reward = "Reward: x" .. shortNumber(P.IncomeMultiplier or 1.25) .. " coins forever, +1 garden place, " .. commas(gems) .. " Gems"
			if stars + 1 == (tonumber(P.FusionUnlock) or 1) then
				reward = reward .. " + the Fusion Machine"
			end
			H.PrestigeReward.Text = reward
			CloudUI.SetDisabled(H.PrestigeButton, not ok or inMatch() or not P2.hasHome())
			P5.paintHomeHero(H, P2.hasHome(), inMatch())
		end

		H.PlotFolder = plotFolder
		function H.Live()
			local home = P2.homeData()
			local waiting, income, parts, open = homeLive(home)
			P5.paintStrip(H, home, income, open)
			H.Income.Text = P2.formatRate(income) .. "/s"
			local bits = {}
			local mult = 1
			if type(parts) == "table" then
				mult = tonumber(parts.Multiplier) or 1
				local food = tonumber(parts.Food) or 0
				if food > 0 then
					bits[#bits + 1] = "Food " .. shortNumber(food)
				end
				local lucky = tonumber(parts.Lucky) or 1
				if lucky > 1.0001 then
					bits[#bits + 1] = "Lucky +" .. shortPercent(lucky - 1)
				end
			end
			if P2.stationLevelOf(home, "Garden") >= 1 then
				local Pp = TycoonCatalog and TycoonCatalog.Prestige or {}
				bits[#bits + 1] = "Garden " .. math.floor(tonumber(open) or 0) .. "/" .. (tonumber(Pp.GardenSlotsMax) or 12) .. " places"
			end
			if #bits == 0 then
				bits[1] = "Put pets in your Garden to earn Cloud Cash"
			end
			H.IncomeParts.Text = table.concat(bits, "  " .. G.Bullet .. "  ")
			-- the prestige multiplier tag (stars x1.25 each)
			H.Multiplier.Visible = mult > 1.0001
			H.Multiplier.Text = "x" .. shortNumber(math.floor(mult * 100 + 0.5) / 100)
			-- the Garden card
			waiting = math.max(0, math.floor(tonumber(waiting) or 0))
			local built = P2.stationLevelOf(home, "Garden") >= 1
			local P = TycoonCatalog and TycoonCatalog.Prestige or {}
			local maxPlaces = tonumber(P.GardenSlotsMax) or 12
			H.CoinsWaiting.Text = P2.formatCash(waiting) .. " waiting"
			H.CoinsWaiting.TextColor3 = waiting > 0 and C2.Cash or MUTED
			H.CoinsPerMin.Text = "Coins " .. P2.formatCash(math.floor(income * 60 + 0.5)) .. "/min"
			H.Places.Text = built and ("Places " .. math.floor(open) .. "/" .. maxPlaces) or "Not built"
			local tips = {}
			local legacySlots = tonumber(home.LegacySlots)
			local kept = legacySlots and legacySlots > (tonumber(P.GardenSlotsBase) or 3) + math.floor(tonumber(home.Prestige) or 0)
			if not built then
				tips[1] = "Build your free Pet Garden: pets eat there and pop out rainbow coins."
			elseif kept or home.LegacyPrices == true then
				tips[1] = "Walk over your rainbow coins to scoop them!"
				if kept and home.LegacyPrices == true then
					tips[2] = "Kept from your old home: " .. math.floor(legacySlots) .. " places and old prices until your next Prestige."
				elseif kept then
					tips[2] = "Kept from your old garden: " .. math.floor(legacySlots) .. " places until your next Prestige."
				else
					tips[2] = "Old prices until your next Prestige."
				end
			else
				tips[1] = "Walk over your rainbow coins to scoop them! " .. tostring(P.GardenSlotsBase or 3) .. " places + 1 per prestige."
			end
			H.GardenTip.Text = table.concat(tips, " ")
		end

		function H.Refresh()
			local home = P2.homeData()
			local cash = P2.cashBalance()
			H.Pads = {}
			local padList = P2.catalogCall("AvailablePads", home) or {}
			for _, padInfo in ipairs(padList) do
				if type(padInfo) == "table" and type(padInfo.StationId) == "string" then
					H.Pads[padInfo.StationId] = padInfo
				end
			end
			-- Phase 5: the (at most 3) pads TycoonCatalog.SignedPads picks carry a "Next" tag, like their world signs
			local signed = P2.catalogCall("SignedPads", padList, cash)
			signed = type(signed) == "table" and signed or {}
			for _, row in pairs(H.Rows) do
				paintRow(row, home, cash)
				local show = signed[row.Id] == true and row.Button.Visible
				if show and not row.NextTag then
					row.NextTag = colorPill(row.Frame, "NextTag", "Next", GOLD, 18, 0)
					row.NextTag.AnchorPoint = Vector2.new(1, 0)
					row.NextTag.Position = UDim2.new(1, -10, 0, 6)
					row.NextTag.ZIndex = 6
				end
				if row.NextTag then
					row.NextTag.Visible = show
				end
			end
			paintSummary(home)
			H.Live()
		end

		-- Phase 5: ONE scrolling column under the flow strip (summary first, the prestige card last), every size
		function H.Layout(w, _h, narrow, short, _tall)
			local tall = true
			local leftW = narrow and K.HOME_LEFT_W_NARROW or K.HOME_LEFT_W
			if tall ~= H.Tall then
				H.Tall = tall
				for i, c in ipairs(H.Cards) do
					c.Parent = tall and list or left
					c.LayoutOrder = tall and (i - 100) or i
				end
			end
			left.Visible = not tall
			-- Phase 6: the Go home hero sits on top; the list starts under it
			local heroH = P5.layoutHomeHero(H, short, w)
			local top = heroH > 0 and (heroH + 22) or 0
			if tall then
				local stripH = P5.layoutStrip(H, w)
				list.Position = UDim2.new(1, -10, 0, stripH + top + 6)
				list.Size = UDim2.new(1, -20, 1, -(stripH + top + 16))
				for i, c in ipairs(H.Cards) do
					-- the house + income cards first, the prestige card after the stations; the old garden card is gone
					-- (Phase 5: coins roam the yard; its places live in the income card)
					c.LayoutOrder = (c.Name == "PrestigeCard") and 1000 or (i - 100)
					c.Visible = c.Name ~= "GardenCard"
				end
			else
				left.Size = UDim2.new(0, leftW, 1, -24)
				list.Position = UDim2.new(1, -12, 0, 12)
				list.Size = UDim2.new(1, -(leftW + 36), 1, -24)
			end
			-- a list column too slim for one-line rows (landscape phones and small windows) stacks the rows like portrait
			local listW = tall and (w - 44) or (w - (leftW + 36) - 24)
			local stacked = listW < 640
			H.Stacked = stacked
			local rowH = stacked and K.STATION_ROW_H_TALL or K.STATION_ROW_H
			for _, row in pairs(H.Rows) do
				row.Frame.Size = UDim2.new(1, 0, 0, rowH)
				if stacked then
					row.Disc.AnchorPoint = Vector2.new(0, 0)
					row.Disc.Position = UDim2.fromOffset(10, 10)
					row.Disc.Size = UDim2.fromOffset(56, 56)
					row.Name.Position = UDim2.fromOffset(78, 6)
					row.Name.Size = UDim2.new(1, -88, 0, 30)
					row.Level.Position = UDim2.fromOffset(78, 38)
					row.PipRow.Position = UDim2.fromOffset(176, 42)
					row.Info.Position = UDim2.fromOffset(78, 62)
					row.Info.Size = UDim2.new(1, -88, 0, 24)
					row.Right.AnchorPoint = Vector2.new(1, 1)
					row.Right.Position = UDim2.new(1, -10, 1, -6)
					row.Right.Size = UDim2.new(1, -88, 0, 40)
					row.Button.Size = UDim2.fromOffset(150, 40)
					row.Price.Size = UDim2.new(1, -160, 1, 0)
				else
					row.Disc.AnchorPoint = Vector2.new(0, 0.5)
					row.Disc.Position = UDim2.new(0, 12, 0.5, 0)
					row.Disc.Size = UDim2.fromOffset(64, 64)
					row.Name.Position = UDim2.fromOffset(88, 6)
					row.Name.Size = UDim2.new(1, -(88 + (narrow and 300 or 340)), 0, 30)
					row.Level.Position = UDim2.fromOffset(88, 38)
					row.PipRow.Position = UDim2.fromOffset(186, 42)
					row.Info.Position = UDim2.fromOffset(88, 64)
					row.Info.Size = UDim2.new(1, -(88 + (narrow and 300 or 340)), 0, 24)
					row.Right.AnchorPoint = Vector2.new(1, 0.5)
					row.Right.Position = UDim2.new(1, -12, 0.5, 0)
					row.Right.Size = UDim2.fromOffset(narrow and 290 or 330, 76)
					row.Button.Size = UDim2.fromOffset(narrow and 140 or 164, 54)
					row.Price.Size = UDim2.new(1, -((narrow and 140 or 164) + 12), 0, 32)
				end
			end
			-- short windows (landscape phones): slimmer lines so the box fits above the window's bottom edge
			local lineH = short and 50 or 62
			for _, line in ipairs(H.ConfirmRows) do
				line.Size = UDim2.new(1, 0, 0, lineH)
			end
			H.ConfirmList.Position = UDim2.fromOffset(16, short and 56 or 62)
			H.ConfirmList.Size = UDim2.new(1, -32, 0, 3 * lineH + 2 * 8)
			box.Size = UDim2.fromOffset(math.min(K.CONFIRM_W, w - 40), short and 302 or K.CONFIRM_H)
		end

		win.Refresh = H.Refresh
		win.OnLayout = function(w, h, narrow, short, tall)
			H.Layout(w, h, narrow, short, tall)
		end
		win.OnOpen = function()
			H.ShowConfirm(false)
			P5.paintHomeHero(H, P2.hasHome(), inMatch())
			P5.heroLoop(H, win)
			Home.Folder = nil
			for _, conn in ipairs(Home.Conns) do
				conn:Disconnect()
			end
			Home.Conns = {}
			local folder = plotFolder()
			if folder then
				Home.Conns[#Home.Conns + 1] = folder.AttributeChanged:Connect(function(name)
					if name == "CollectorCash" or name == "GardenSlots" or name == "IncomePerSecond" or name == "HomeLevel" or name == "Prestige" or name == "BerryCap" then
						refreshHomeLive()
					end
				end)
			end
		end
		win.OnClose = function()
			H.ShowConfirm(false)
			for _, conn in ipairs(Home.Conns) do
				conn:Disconnect()
			end
			Home.Conns = {}
		end
	end

	-- Live numbers of the open Home window (the Collector fills every second): at most every K.LIVE_GAP seconds.
	function refreshHomeLive()
		local win = windows.Home
		local H = win and win.HomeUi
		if not H or not win.Shown then
			return
		end
		local now = os.clock()
		if now - Home.LiveAt < K.LIVE_GAP then
			if not Home.LivePending then
				Home.LivePending = true
				task.delay(K.LIVE_GAP, function()
					Home.LivePending = false
					refreshHomeLive()
				end)
			end
			return
		end
		Home.LiveAt = now
		safe("home live", H.Live)
	end
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
-- OpenPanel(panelId, args): the server opens windows (roulette / item shop prompts, the tutorial).
local function onOpenPanel(panelId, args, fromRemote)
	if type(panelId) ~= "string" then
		return
	end
	args = type(args) == "table" and args or {}
	local key = panelId:lower()
	-- Phase 4: the Food Machine list, the garden picker, the Training Place and the EVOLVE moment are CareController's
	-- windows (it hears the OpenPanel remote itself; calls made on the client are forwarded)
	local careId = nil
	if key == "feed" or (key == "pets" and args.Action == "Feed") then
		careId = "Feed"
	elseif key == "pets" and args.Action == "Garden" then
		careId = "Garden"
	elseif key == "train" or key == "training" then
		careId = "Train"
	elseif key == "evolve" then
		careId = "Evolve"
	end
	if careId then
		local care = P2.care()
		if care then
			if not fromRemote then
				safe("care open", care.Open, careId, args)
			end
			return
		end
		if careId ~= "Feed" and careId ~= "Garden" then
			return
		end
		-- (no CareController in this build: the Pets window on that pet)
		args = { Key = args.Key }
		key = "pets"
	end
	if key == "shop" or key == "store" then
		P5.openShop(args) -- lobby-shop Task 22: the one Shop window (refused in a match by ShopController itself)
	elseif key == "pets" or key == "inventory" or key == "items" or key == "team" or key == "teams" then
		P5.openPets(args) -- team balance: the one Pets window (the Team and Items tabs are gone)
	elseif key == "home" or key == "spot" then
		if inMatch() then
			return
		end
		openWindow("Home", args) -- Phase 6: without a home it offers Claim a home
	elseif key == "index" then
		local groupId = args.GroupId or args.Group or args.Rarity
		openIndex(type(groupId) == "string" and groupId or nil)
	elseif key == "stats" then
		openWindow("Stats", args)
	elseif key == "settings" then
		MenuController.OpenSettings() -- HUD cleanup: the pill's gear
	elseif key == "close" then
		closeEverything()
	end
end

local function onStateChanged()
	-- red dot on the Pets tile when the collection grew while the Pets window was closed
	local _, total = petTotals()
	if Badge.LastPetTotal ~= nil and total > Badge.LastPetTotal and not P5.petsOpen() then
		if Entries.Pets then
			Entries.Pets.SetBadge(true)
		end
	end
	Badge.LastPetTotal = total
	refreshIndexBadge()

	for _, win in pairs(windows) do
		refreshWindow(win)
	end
end

local function onTokensChanged()
	refreshOpenWindow()
end

-- the claimed plot changed (claimed / released): the Home window follows (Phase 6: without a home it shows Claim a home)
local function onSpotChanged()
	Home.Folder = nil
	local win = windows.Home
	if win and win.Shown then
		if win.OnOpen then
			safe("home rebind", win.OnOpen, {})
		end
		refreshWindow(win)
	end
end

local function onMatchFlagChanged()
	if inMatch() then
		closeEverything(true)
	end
	updateMenuActive()
	refreshOpenWindow()
end

-- Escape only: gamepad B goes through the "NimbusMenuBack" action (syncBackBinding), because it must not
-- also reach MovementController's dash.
local function onInput(input)
	if input.KeyCode == Enum.KeyCode.Escape then
		handleBack()
	end
end

local function connectRemotes()
	local okOpen, openRemote = pcall(Remotes.Get, "OpenPanel")
	if okOpen and openRemote then
		openRemote.OnClientEvent:Connect(function(panelId, args)
			safe("OpenPanel", onOpenPanel, panelId, args, true)
		end)
	else
		warn("[MenuController] OpenPanel remote is unavailable: " .. tostring(openRemote))
	end
	-- (lobby-shop Task 22: RouletteResult is EggStage's; ShopController calls EggStage.Init)
end

-- The Pet Index lives in IndexController: keep one window at a time, light the Index tile and relay
-- its opening as WindowOpened("Index").
local function connectIndex()
	local index = getIndex()
	if not index then
		return
	end
	if type(index.Opened) == "table" and type(index.Opened.Connect) == "function" then
		index.Opened:Connect(function()
			if openId then
				closeWindow(openId, true)
			end
			P5.closePets()
			updateMenuActive()
			MenuController.WindowOpened:Fire("Index")
		end)
	end
	if type(index.Closed) == "table" and type(index.Closed.Connect) == "function" then
		index.Closed:Connect(function()
			updateMenuActive()
		end)
	end
	refreshIndexBadge()
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function MenuController.Open(panelId, args)
	if initialized then
		onOpenPanel(panelId, args)
	end
end

function MenuController.Close()
	if initialized then
		closeEverything()
	end
end

function MenuController.GetButton(id)
	if id == "Home" then
		id = "Spot" -- the Home tile keeps the v3 id
	end
	local entry = Entries[id]
	return entry and entry.Button or nil
end

-- Opens the Food Machine list (CareController) with that pet copy first (key; nil = the garden pets first).
function MenuController.OpenFeed(key)
	if initialized then
		onOpenPanel("Pets", { Action = "Feed", Key = key })
	end
end

-- The Pets window showing `preset` (1-3; nil = the active one).
function MenuController.OpenTeam(preset)
	if initialized then
		onOpenPanel("Team", { Preset = preset })
	end
end

-- The menu's side hint (CareController's local refusals use it too; never in the screen centre). (roll-look review round
-- 1) While this gui is off (the egg stage hides the HUD: HatchLook.HideHud) the hint could not be seen, so it goes to
-- NotifyController's toast stack (NimbusNotify stays on); the hint again when that is not there.
function MenuController.Hint(text, kind)
	if initialized and type(text) == "string" then
		if gui and gui.Enabled == false then
			local module = script.Parent:FindFirstChild("NotifyController")
			local ok, nc = pcall(require, module)
			if ok and type(nc) == "table" and type(nc.Toast) == "function" and nc.Toast(text, kind or "info") then
				return
			end
		end
		showHint(text, kind)
	end
end

-- true while a menu window, the Pets window, the Shop or the egg stage covers the screen (the tutorial folds its card
-- and hides its menu pointer meanwhile)
function MenuController.IsOpen()
	return openId ~= nil or P5.petsOpen() or P5.shopOpen() or P5.hatchShowing()
end

-- Phase 3 (BattleController): hides the menu tiles while the battle team cards use the left edge of a landscape
-- phone (nothing may sit in the screen centre there); false shows them again. The (transparent) column frame keeps
-- its place, so the HUD, the tutorial and the DEV tile that measure it do not move.
function MenuController.SetColumnHidden(hidden)
	U.ColumnHidden = hidden == true
	for _, entry in pairs(Entries) do
		P5.tileVisibility(entry)
	end
	if U.Tab then
		U.Tab.Visible = not U.ColumnHidden and not U.Covered
	end
end

-- Team balance: a window reaches over the tiles from screen x `windowLeft` (a phone, a tablet); nil = it closed. `who` is
-- the window ("Pets" by default: PetsController; the Store and the Gifts window pass "Store" / "Daily", re-review 1): the
-- tiles step aside like SetColumnHidden's (the column frame keeps its place) while any window's left edge is left of
-- the column's right edge, so the Store closing on the Gifts window's WindowOpened never brings them back over it.
function MenuController.SetColumnCovered(windowLeft, who)
	U.Covers = type(U.Covers) == "table" and U.Covers or {}
	U.Covers[type(who) == "string" and who or "Pets"] = type(windowLeft) == "number" and windowLeft or nil
	local right = columnRight()
	local covered = false
	for _, left in pairs(U.Covers) do
		if left < right then
			covered = true
		end
	end
	if covered == (U.Covered == true) then
		return
	end
	U.Covered = covered
	for _, entry in pairs(Entries) do
		P5.tileVisibility(entry)
	end
	if U.Tab then
		U.Tab.Visible = not U.ColumnHidden and not U.Covered
	end
end

-- Re-review 2: Roblox's touch controls (GuiService.TouchControlsEnabled) for the windows that fill a phone. `who` names
-- the window ("Pets" when left out), `on` = true while it wants them gone. They go when the first window asks and come
-- back as they were (the one snapshot, taken while no window held them) when the last one lets go, so the Store and
-- the Pets window opening over each other (each lays out before WindowOpened closes the other) never leave them off.
function MenuController.SetTouchHidden(who, on)
	U.TouchOwners = type(U.TouchOwners) == "table" and U.TouchOwners or {}
	local before = next(U.TouchOwners) ~= nil
	U.TouchOwners[type(who) == "string" and who or "Pets"] = (on == true) or nil
	local after = next(U.TouchOwners) ~= nil
	if before == after then
		return
	end
	pcall(function()
		local GuiService = game:GetService("GuiService")
		if after then
			U.TouchWas = GuiService.TouchControlsEnabled
			GuiService.TouchControlsEnabled = false
		else
			GuiService.TouchControlsEnabled = U.TouchWas ~= false
			U.TouchWas = nil
		end
	end)
end

-- Bug batch 2 #1: folds the menu column against the left edge (true) or brings it back (false); the arrow tab does
-- the same. IsColumnCollapsed() -> the remembered state (this session).
function MenuController.SetColumnCollapsed(collapsed, animate)
	safe("menu fold", P5.setCollapsed, collapsed == true, animate == true)
end

function MenuController.IsColumnCollapsed()
	return U.Collapsed == true
end

-- Debug helper (smoke tests): forget that Roblox's thumbstick was seen (a fresh session) and lay the column out again.
function MenuController.ResetStickSeen()
	U.StickSeen = nil
	if U.Column then
		safe("menu stick", relayoutMenu)
	end
end

function MenuController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	touchDevice = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	pcall(State.Init)

	gui = CloudUI.NewScreenGui("NimbusMenu", 20)

	buildHint()
	buildColumn()
	createWindow({ Id = "Stats", Title = "Stats", Category = "Stats", Build = buildStats, Tall = true })
	createWindow({ Id = "Home", Title = "My Home", Category = "Home", Build = buildHome, Tall = true })
	relayoutMenu()
	updateMenuActive()

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		safe("relayout", relayoutMenu)
	end)
	State.Changed:Connect(function()
		safe("State.Changed", onStateChanged)
	end)
	LocalPlayer:GetAttributeChangedSignal(Config.Attr.Tokens):Connect(function()
		safe("Tokens", onTokensChanged)
	end)
	LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
		safe("InMatch", onMatchFlagChanged)
	end)
	-- Phase 2: Cash / Gems balances (prices turn red / green), the claimed plot
	if type(State.BerriesChanged) == "table" and type(State.BerriesChanged.Connect) == "function" then
		State.BerriesChanged:Connect(function()
			safe("berries", refreshHomeLive)
		end)
	end
	for _, signalName in ipairs({ "CashChanged", "GemsChanged" }) do
		local signal = State[signalName]
		if type(signal) == "table" and type(signal.Connect) == "function" then
			signal:Connect(function()
				safe(signalName, onTokensChanged)
			end)
		end
	end
	LocalPlayer:GetAttributeChangedSignal(Config.Attr.SpotIndex):Connect(function()
		safe("SpotIndex", onSpotChanged)
	end)
	UserInputService.InputBegan:Connect(function(input)
		safe("input", onInput, input)
	end)

	-- remember the collection size so only later growth shows the "new pet" dot
	local _, total = petTotals()
	if State.IsLoaded and State.IsLoaded() then
		Badge.LastPetTotal = total
	end

	safe("connect index", connectIndex)
	-- the Pets window (PetsController) opened: one window at a time; its tile glows while it is up. Store W1 (spec 8):
	-- the Shop (lobby-shop Task 22: "Shop"; "Store" from an old build), the Gifts window and the Sky Trove close the
	-- menu's windows the same way, and the Pets window too
	MenuController.WindowOpened:Connect(function(id)
		if id == "Pets" or id == "Shop" or id == "Store" or id == "Daily" or id == "Trove" then
			if openId then
				closeWindow(openId, true)
			end
			closeIndex()
			if id ~= "Pets" then
				P5.closePets()
			end
			updateMenuActive()
		end
	end)
	local pets = P5.pets()
	if pets then
		pets.Closed:Connect(updateMenuActive)
	end
	task.spawn(connectRemotes)
	P5.watchSheets()
end

return MenuController
