-- MenuController (client, v3 + Phase 2): the left menu of icon tiles and every window the player opens.
--
--   MenuController.Init()
--   MenuController.Open(panelId, args)   -- "Inventory" | "Pets" | "Index" | "Shop" | "Stats" | "Home" | "Team" (what
--                                           OpenPanel does; args: Tab, RouletteId, Currency = "Gems", Action, Key).
--                                           Phase 4: "Pets" with Action = "Feed" | "Garden", "Feed", "Train" and "Evolve"
--                                           go to CareController (the Food Machine list, the garden picker, the Training
--                                           Place window, the EVOLVE moment); Action = "Evolve" with a Key (the floating
--                                           card's EVOLVE! pill) opens the Pets panel on that pet with the EVOLVE confirm
--   MenuController.Close()               -- closes whatever window / overlay is open
--   MenuController.WindowOpened          -- Util.Signal, Fire(windowId) whenever a window opens:
--                                           "Inventory", "Shop", "Stats", "Home", "Team" or "Index" (the tutorial listens)
--   Extra: MenuController.GetButton(id) -> the MenuButton_<id> tile (or nil; "Home" is the Spot tile)
--          MenuController.IsOpen() -> true while a window, the odds popup or the roulette stage is up
--          MenuController.IsPrewarmed(petId) -> true once that pet was pre-sculpted for the roulette strip
--          MenuController.OpenFeed(key) -> the Food Machine list (CareController) with that pet copy first
--          MenuController.Hint(text, kind) -> the side hint (CareController's local refusals use it)
--          MenuController.SetColumnHidden(hidden) -> hides / shows the menu tiles (BattleController: the team cards
--          take the left edge of a landscape phone during a battle; the column frame keeps its place)
--          MenuController.SetColumnCollapsed(collapsed, animate) / IsColumnCollapsed() -> folds the column against the
--          left edge like its arrow tab does (bug batch 2 #1; remembered for the session)
--
-- Screen: ScreenGui "NimbusMenu" (display order 20, IgnoreGuiInset = false).
--   * Menu column, left-centre (bug batch 2 #1, option A): ONE slim column of square neon tiles with a glyph and a
--     bold label - Pets, Items, Team, Index, Shop, Home, Stats and the Settings gear - 56 px on a 1080p desktop. Each
--     tile is a TextButton named MenuButton_<Id> (Ids Inventory, Pets, Index, Shop, Spot, Stats, Team, Settings: the
--     Home tile keeps the v3 id "Spot" so saved tutorial targets keep working) inside a frame Entry_<Id> of the frame
--     "MenuColumn". The open window's tile glows gold; a red "!" marks new pets and Pet Index rewards waiting to be
--     claimed. A small arrow tab (MenuColumn.Toggle) folds the column against the left edge and back (remembered for
--     the session; the tab repeats a tile's red dot while folded; a tutorial step pointing at a tile unfolds it). On
--     short screens (landscape / portrait phones) the tiles wrap into two slim columns so they stay >= 44 px.
--   * Windows (CloudUI.Panel, centred because the player asked for them, nudged right only when the menu
--     column would cover them): Inventory (tabs Pets + Items, pet detail card), Shop (tabs Roulettes + Items + Gems,
--     odds popup), Stats, Home and Team. The Pet Index is IndexController's window: the Index tile and
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
--   * Pets panel: one slot per pet COPY key (shared/PetKeys: Normal, Golden, Rainbow, fused hybrids) with tier /
--     hybrid chips, "Lv n" + evolution stars and a Garden (seedling) / training (muscle) chip; the detail card shows
--     "Lv 57 / 100" and the XP bar, the stats at its level with "Coins $x/s" (what it earns in the Garden), the
--     evolution pill, where it works or trains ("Training Physique (2:10 left)"), "Ready to evolve!", and the buttons
--     Equip / Unequip (Equip disabled while training), Feed (CareController's Food Machine list), Garden / Leave
--     Garden (HomeAction "GardenSet", ANY role), Train (CareController's Training Place window) and EVOLVE! (when
--     PetCatalog.CanEvolve: CareController's confirm -> PetCare "Evolve").
--   * Shop Gems tab: the Gem packs (developer products with an id: MarketplaceService:PromptProductPurchase; the
--     server grants them in ProcessReceipt), the gems-only Secret Roulette and every roulette with a gem price,
--     each with its odds popup (always shown); hidden with a note while the PaidRandomItemsRestricted attribute
--     is true. A gem spin sends BuyRoulette(id, "Gems").
--   * Roulette stage: a scrolling strip of pet viewports that eases to the server result (RouletteResult),
--     then a reveal card with a rarity glow, a NEW! flag and an Equip button (a landscape card on short screens).
--   * v3 readability rule: everything is designed in 1080p pixels (body 18-19, captions >= 18, buttons 20+,
--     titles 28-34) under ONE UIScale per window = min(screen factor clamp(viewportY / 1080, 0.8, 1.25), fit).
--     Window sizes adapt between a minimum and a preferred design size and their columns scroll, so phones
--     keep the 0.8 scale instead of shrinking the text.
--   * Every window re-renders from State.Changed (and when the token count or the InMatch attribute
--     changes). Pet slots are kept per pet id and updated in place, so nothing is rebuilt or leaked; the
--     pet viewports of the Inventory grid, the odds popup and the roulette strip are attached under a per-frame
--     TIME budget (K.BUILD_BUDGET, at least one per frame), so neither a big collection nor a fresh client's
--     first-time pet sculpts hitch. The strip cells and odds tiles use PetBuilder's Low detail (the reveal card
--     stays High), and the roulette pools are sculpted ahead of time (one pet per frame) when the Shop opens and
--     when a spin is requested, so the spin itself only clones.
--   * Touch screens: the menu column never reaches Roblox's thumbstick (bottom-left); in landscape it sits in the
--     band between the top margin and the stick (two slim columns of four on a phone, labels >= 14 px). "Touch" is a
--     touch-only device OR any screen where PlayerModule's TouchGui shows a thumbstick (Studio's device emulator and
--     touch laptops / tablets with a keyboard report KeyboardEnabled too, but still get the stick: P5.stickShown).
--     Once the stick has been seen the touch layout stays for the session (respawn, the Esc menu and a hybrid's
--     mouse / touch switches hide the stick for a moment; the column must not snap back and forth).
--
-- Remotes used: OpenPanel, RouletteResult (in); BuyRoulette, EquipPet, UnequipPet, BuyItem, GoToSpot, HomeAction,
-- PetCare (out). Each remote action is sent at most every K.FIRE_GAP seconds (the server rate-limits as well).
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
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
local ItemCatalog = safeRequire("ItemCatalog", {
	List = {},
	ById = {},
	Get = function()
		return nil
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

local PetKeys = optionalShared("PetKeys")
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
	DETAIL_W = 340,
	DETAIL_W_NARROW = 296,
	FIRE_GAP = 0.3, -- client-side spacing between two sends of the same remote
	HINT_SECONDS = 2.8,
	WAIT_TIMEOUT = 7, -- seconds to wait for a RouletteResult
	-- pet viewports (Inventory grid, odds popup, roulette strip) are built under a TIME budget per frame: the first
	-- build of a frame always runs, more only while the frame has spent < BUILD_BUDGET s building, at most BUILD_MAX
	-- (a first-time High sculpt costs tens of ms, a cached clone a few: a count budget hitches on fresh clients)
	BUILD_BUDGET = 0.004,
	BUILD_MAX = 3,
	STRIP_DETAIL = "Low", -- roulette strip cells: small, static, moving fast (the reveal card keeps High)
	ODDS_DETAIL = "Low", -- 88 px odds tiles
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
	CARD_H = 474, -- roulette card
	CARD_H_SHORT = 216,
	ITEM_CARD_H = 440,
	ITEM_CARD_H_SHORT = 214,
	SHOP_COMPACT = 650, -- Shop windows lower than this (design px) use the compact cards
}

-- Preferred / minimum design sizes of each window (W x H), the reveal card, the spin stage and its strip.
-- Phase 5 (6.6, the window rule): windows dock RIGHT on landscape screens (NeonKit.SideRect, <= 0.44 W) and are a
-- bottom sheet on portrait ones (the top 44% stays clear); no backdrop dims the game. Odds is a small centred confirm.
K.WIN = {
	Inventory = { 820, 900 },
	Shop = { 820, 900 },
	Stats = { 640, 760 },
	Home = { 820, 900 },
	Team = { 820, 900 }, -- Phase 3: the battle team presets (Phase 5: 3 slots, FIGHTER + 2 helpers)
	Odds = { 700, 640, 520, 380 },
}
-- Portrait screens (a phone held upright): a window may get as narrow as TALL_MIN_W design px (and as tall as
-- TALL_MAX_H) so its text keeps the readability scale instead of shrinking to fit 800 px; windows narrower than
-- TALL switch to their single-column ("tall") layout.
K.TALL_MIN_W = 420
K.TALL_MAX_H = 1100
K.TALL = 760
-- Phase 2 (Home window, Pets actions, Gems tab)
K.HOME_LEFT_W = 350 -- the Home window's summary column
K.HOME_LEFT_W_NARROW = 300
K.STATION_ROW_H = 96
K.STATION_ROW_H_TALL = 132
K.LIVE_GAP = 0.25 -- seconds between two live refreshes of the Home window (collector / income tick every second)
K.GEM_PACK_H = 248
K.GEM_ROW_H = 120
K.INFO_CHARS = 34 -- a station row's "now -> next" line longer than this shows "Next: ..." only
K.CONFIRM_W = 560 -- the prestige confirmation
K.CONFIRM_H = 356
K.RESTRICTED_ATTR = "PaidRandomItemsRestricted" -- GemService: true while gem roulettes are not allowed / unknown
K.REVEAL = { TallW = 452, TallH = 640, WideW = 790, WideH = 372 } -- TallW: a 390 px phone keeps the 0.8 scale (18 px pills stay >= 14 px)
K.STAGE = { W = 920, H = 380 }
K.STRIP = { Cell = 150, W = 860, H = 190, Target = 34, MinCells = 42, Seconds = 5.6, Curve = 2.8 }

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
local TEAL = Color3.fromRGB(70, 182, 196)
local INSET_COLOR = Color3.fromRGB(20, 30, 70)
local ROLE_COLORS = { Economy = Color3.fromRGB(96, 196, 108), Combat = Color3.fromRGB(228, 104, 96) }
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

-- Glyphs as UTF-8 byte escapes (the source stays plain ASCII).
local G = {
	Backpack = "\240\159\142\146",
	Paw = "\240\159\144\190",
	Book = "\240\159\147\150",
	Money = "\240\159\146\176",
	House = "\240\159\143\160",
	Chart = "\240\159\147\138",
	Lock = "\240\159\148\146",
	Star = "\226\152\133",
	StarOutline = "\226\152\134",
	Cloud = "\226\152\129",
	Down = "\226\150\188",
	Dash = "\226\128\148",
	Sparkle = "\226\156\166",
	Gem = (CURRENCY.Gems and CURRENCY.Gems.Glyph) or "\226\151\134", -- black diamond
	Cash = (CURRENCY.Cash and CURRENCY.Cash.Glyph) or "$",
	Bullet = "\194\183", -- middle dot
	Check = "\226\156\147",
	Snack = "\240\159\141\170", -- cookie
	Meal = "\240\159\141\178", -- pot of food
	Feast = "\240\159\165\167", -- pie
	Food = "\240\159\141\150", -- meat on bone
	Seedling = "\240\159\140\177",
	Muscle = "\240\159\146\170",
	Hybrid = "\226\156\168", -- sparkles
	Storm = "\226\154\161", -- high voltage
	Robux = "R$",
	Swords = "\226\154\148\239\184\143", -- crossed swords (emoji presentation): the Team tile
}

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

local Spin = { Waiting = false, WaitToken = 0, Queue = {}, Stage = nil, Last = nil }
-- per-frame build budget + roulette pool pre-sculpting (functions defined with the helpers below)
local Warm = { Queue = {}, Seen = {}, Done = {}, Running = false, Module = nil, Tried = false }
local Odds = { Gui = nil, Token = 0, Slots = {}, Holder = nil, Fit = nil }
local Badge = { LastPetTotal = nil }
local Back = { Bound = false, Busy = false, Swallowed = false } -- gamepad B binding state (see syncBackBinding)
local Index = { Module = nil, Tried = false } -- IndexController (loaded lazily, optional)
local Entries = {} -- id -> menu tile widgets
local Hint = { Frame = nil, Label = nil, Token = 0 }
-- Phase 2: the Home window's live plot watch, the Feed picker, the shop's Gems tab
local Home = { Folder = nil, Conns = {}, LiveAt = 0, LivePending = false }
local Gems = { Prices = {}, PriceAsked = {} }

-- Phase 3: the Team window's entry points (P3.BuildTeam(win), P3.Settle(), P3.Battle(), P3.Refresh(); set below)
local P3 = {}
-- Phase 5 helpers (one table: the main chunk stays under Lua's 200-local limit). Kit = NeonKit (Card, Tile, SideRect, Dock).
local P5 = { Kit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit")) }
-- forward declarations
local openWindow, closeWindow, toggleWindow, refreshOpenWindow, updateMenuActive
local requestSpin, closeStage, skipSpin, closeOdds, openOdds, showHint, handleBack, beginStage
local syncBackBinding, closeIndex, relayoutMenu, refreshHomeLive

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
-- (audio wave 2) client/SoundFx, lazy (the roulette strip's SpinStart / SpinTick / SpinLand and the reveal card's
-- RevealCommon / RevealRare / RevealLegendary); false = unavailable. A missing id is silent
-- (one local table: this file sits near Luau's 200-locals limit)
local Sfx = {
	Mod = nil,
	-- the reveal card's sound by the pet's rarity: Common / Uncommon -> RevealCommon, Rare / Epic -> RevealRare,
	-- Legendary / Mythic / Secret -> RevealLegendary
	Reveal = {
		Common = "RevealCommon", Uncommon = "RevealCommon", Rare = "RevealRare", Epic = "RevealRare",
		Legendary = "RevealLegendary", Mythic = "RevealLegendary", Secret = "RevealLegendary",
	},
}
function Sfx.Play(name)
	if Sfx.Mod == nil then
		local module = Client:FindFirstChild("SoundFx")
		local ok, mod = false, nil
		if module then
			ok, mod = pcall(require, module)
		end
		Sfx.Mod = (ok and type(mod) == "table" and type(mod.Play) == "function") and mod or false
	end
	if Sfx.Mod then
		pcall(Sfx.Mod.Play, name)
	end
end

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

-- Per-frame build budget for pet viewports: the first build of a frame always runs, the next ones only while the
-- frame has spent less than K.BUILD_BUDGET seconds and at most K.BUILD_MAX builds. Callers add 1 to Count per build.
function Warm.Budget()
	return { Start = os.clock(), Count = 0 }
end

function Warm.Allows(budget)
	return budget.Count < K.BUILD_MAX and (budget.Count == 0 or os.clock() - budget.Start < K.BUILD_BUDGET)
end

-- shared/PetBuilder, loaded lazily (the pre-sculpting below is optional: nil when it cannot load)
function Warm.Builder()
	if not Warm.Tried then
		Warm.Tried = true
		local ok, result = pcall(function()
			return require(Shared:WaitForChild("PetBuilder", 5))
		end)
		if ok and type(result) == "table" then
			Warm.Module = result
		end
	end
	return Warm.Module
end

-- Pre-sculpts pets at the strip's detail, a few per frame (time budget), so a roulette spin only clones cached
-- templates instead of sculpting on the frame a cell scrolls into view. `front` puts them first in the queue.
-- Paused while the roulette stage runs (its cells attach under their own budget).
function Warm.Pets(defs, front)
	if type(defs) ~= "table" or not Warm.Builder() then
		return
	end
	local fresh = {}
	for _, def in ipairs(defs) do
		local id = type(def) == "table" and def.Id or nil
		if type(id) == "string" and not Warm.Seen[id] then
			Warm.Seen[id] = true
			fresh[#fresh + 1] = def
		end
	end
	for i, def in ipairs(fresh) do
		if front then
			table.insert(Warm.Queue, i, def)
		else
			Warm.Queue[#Warm.Queue + 1] = def
		end
	end
	if Warm.Running or #Warm.Queue == 0 then
		return
	end
	Warm.Running = true
	task.spawn(function()
		task.wait() -- never in the frame that opens the Shop (it builds the window)
		while #Warm.Queue > 0 do
			if Spin.Stage then
				task.wait(0.25)
			else
				local budget = Warm.Budget()
				while #Warm.Queue > 0 and Warm.Allows(budget) do
					local def = table.remove(Warm.Queue, 1)
					local ok, model = pcall(Warm.Module.Build, def, { Detail = K.STRIP_DETAIL, Scale = 1 })
					if ok and typeof(model) == "Instance" then
						model:Destroy()
						Warm.Done[def.Id] = true
					end
					budget.Count = budget.Count + 1
				end
				task.wait()
			end
		end
		Warm.Running = false
	end)
end

-- the possible pets of one roulette (pre-sculpted when the Shop opens and when that roulette is requested)
function Warm.Roulette(rouletteId, front)
	if type(rouletteId) ~= "string" then
		return
	end
	if Warm.PossiblePets then
		-- (possiblePetsOf, set below: it also knows the gems-only Secret roulette)
		local ok, defs = pcall(Warm.PossiblePets, rouletteId)
		if ok then
			Warm.Pets(defs, front)
		end
		return
	end
	if type(PetCatalog.PossiblePets) ~= "function" then
		return
	end
	local ok, defs = pcall(PetCatalog.PossiblePets, rouletteId)
	if ok then
		Warm.Pets(defs, front)
	end
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

-- Theme-styled TextLabel (stroke + glyph outline, readable on any panel) with optional property overrides.
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
		Stroke = 0.25,
		StrokeColor = INK,
		Outline = 1.5,
		OutlineColor = INK,
		Props = p,
	})
	local faded = tonumber(p.TextTransparency)
	if faded and faded > 0 then
		local outline = label:FindFirstChild("TextOutline")
		if outline then
			outline.Transparency = math.min(1, faded + 0.2)
		end
	end
	label.Parent = parent
	return label
end

local function corner(parent, radius)
	return Theme.Corner(parent, UDim.new(0, radius or 12))
end

local function round(parent)
	return Theme.Corner(parent, UDim.new(0.5, 0))
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
	corner(inset, 12)
	stroke(inset, WELL_EDGE, 3, 0.15)
	return inset
end

local function rarityOf(def)
	return CloudUI.RarityColor(def and def.Rarity)
end

-- A rarity colour that still reads on dark panels (the Secret rarity is near-black).
local function rarityText(def)
	if def and def.Rarity == "Secret" then
		return Color3.fromRGB(196, 168, 255)
	end
	return Theme.Lighten(rarityOf(def), 0.3)
end

local function rarityOrder(rarityId)
	for _, r in ipairs(Config.Rarities) do
		if r.Id == rarityId then
			return r.Order
		end
	end
	return 1
end

local function commas(n)
	return Util.Commas(tonumber(n) or 0)
end

local function cloudAmount(n)
	return G.Cloud .. " " .. commas(n)
end

local function inMatch()
	return LocalPlayer ~= nil and LocalPlayer:GetAttribute(Config.Attr.InMatch) == true
end

-- Config.Gems.SecretRoulette (the gems-only roulette at the Storm Altar) or nil
local function secretRoulette()
	local gems = Config.Gems
	local s = type(gems) == "table" and gems.SecretRoulette or nil
	if type(s) == "table" and type(s.Id) == "string" and s.Id ~= "" then
		return s
	end
	return nil
end

-- A token roulette (Config.Roulettes) or the gems-only Secret roulette (GemsOnly = true, no token Price).
local function findRoulette(id)
	for _, r in ipairs(Config.Roulettes) do
		if r.Id == id then
			return r
		end
	end
	local s = secretRoulette()
	if s and s.Id == id then
		return {
			Id = s.Id,
			DisplayName = s.DisplayName or s.Id,
			Color = s.Color or Color3.fromRGB(70, 90, 200),
			Odds = type(s.Odds) == "table" and s.Odds or {},
			GemPrice = s.GemPrice,
			AllowSecret = s.AllowSecret == true,
			GemsOnly = true,
		}
	end
	return nil
end

-- the gem price of a roulette (Config.Gems.RouletteGemPrices, the Secret roulette's GemPrice) or nil
local function gemPriceOf(rouletteId)
	local gems = Config.Gems
	local prices = type(gems) == "table" and gems.RouletteGemPrices or nil
	local price = type(prices) == "table" and tonumber(prices[rouletteId]) or nil
	if not price then
		local s = secretRoulette()
		if s and s.Id == rouletteId then
			price = tonumber(s.GemPrice)
		end
	end
	if price and price >= 1 then
		return math.floor(price)
	end
	return nil
end

-- The rarity buckets of a gems-only roulette, the way GemService rolls them (rarity order, weight > 0, rarities
-- without pets skipped, Secret only with AllowSecret): { {Rarity, Weight, Pets} }, total weight.
local function gemsOnlyBuckets(roulette)
	local out, total = {}, 0
	if type(roulette) ~= "table" or type(roulette.Odds) ~= "table" or type(PetCatalog.ListByRarity) ~= "function" then
		return out, 0
	end
	local rarities = {}
	for _, r in ipairs(Config.Rarities) do
		rarities[#rarities + 1] = r
	end
	table.sort(rarities, function(a, b)
		return (a.Order or 0) < (b.Order or 0)
	end)
	for _, r in ipairs(rarities) do
		local w = tonumber(roulette.Odds[r.Id])
		if w and w > 0 and (r.Id ~= "Secret" or roulette.AllowSecret == true) then
			local ok, pets = pcall(PetCatalog.ListByRarity, r.Id)
			if ok and type(pets) == "table" and #pets > 0 then
				out[#out + 1] = { Rarity = r.Id, Weight = w, Pets = pets }
				total = total + w
			end
		end
	end
	return out, total
end

-- the pets a roulette can give (PetDefs)
local function possiblePetsOf(rouletteId)
	local roulette = findRoulette(rouletteId)
	if roulette and roulette.GemsOnly then
		local out = {}
		for _, bucket in ipairs((gemsOnlyBuckets(roulette))) do
			for _, def in ipairs(bucket.Pets) do
				out[#out + 1] = def
			end
		end
		return out
	end
	if type(PetCatalog.PossiblePets) == "function" then
		local ok, defs = pcall(PetCatalog.PossiblePets, rouletteId)
		if ok and type(defs) == "table" then
			return defs
		end
	end
	return {}
end

-- { {PetId, Rarity, Chance} } of a roulette (PetCatalog.GetOdds; the gems-only one mirrors GemService.GetOdds)
local function oddsOf(rouletteId)
	local roulette = findRoulette(rouletteId)
	if roulette and roulette.GemsOnly then
		local out = {}
		local buckets, total = gemsOnlyBuckets(roulette)
		if total > 0 then
			for _, bucket in ipairs(buckets) do
				local each = (bucket.Weight / total) / #bucket.Pets
				for _, def in ipairs(bucket.Pets) do
					out[#out + 1] = { PetId = def.Id, Rarity = bucket.Rarity, Chance = each }
				end
			end
		end
		return out
	end
	local ok, list = pcall(PetCatalog.GetOdds, rouletteId)
	if ok and type(list) == "table" then
		return list
	end
	return {}
end

Warm.PossiblePets = possiblePetsOf

-- "Open" (gem roulettes allowed), "Restricted" (PolicyService said no, or still checking) or "Unavailable" (no
-- gem system on this server: GemService never set the attribute)
local function gemRoulettesState()
	local value = LocalPlayer and LocalPlayer:GetAttribute(K.RESTRICTED_ATTR)
	if value == false then
		return "Open"
	elseif value == true then
		return "Restricted"
	end
	return "Unavailable"
end

local function itemList()
	return ItemCatalog.List or {}
end

-- "+12% Max Health" lines of a pet, in catalog order.
local function perkLines(def)
	local lines = {}
	if type(def) ~= "table" or type(def.Perks) ~= "table" then
		return lines
	end
	local order = PetCatalog.PerkOrder or { "MaxHealth", "TokenBonus", "StaminaRegen", "CheckpointHeal" }
	for _, key in ipairs(order) do
		local value = def.Perks[key]
		if type(value) == "number" and value ~= 0 then
			table.insert(lines, PetCatalog.PerkLabel(key, value))
		end
	end
	return lines
end

local function percentText(chance)
	local pct = (tonumber(chance) or 0) * 100
	local text
	if pct >= 10 then
		text = string.format("%.1f", pct)
	elseif pct >= 1 then
		text = string.format("%.2f", pct)
	else
		text = string.format("%.3f", pct)
	end
	if text:find(".", 1, true) then
		text = text:gsub("0+$", "")
		text = text:gsub("%.$", "")
	end
	return text .. "%"
end

local function starText(count)
	count = Util.Clamp(math.floor(tonumber(count) or 0), 0, 5)
	return string.rep(G.Star, count) .. string.rep(G.StarOutline, 5 - count)
end

-- Owned pet ids, rarest first (the catalog is sorted common -> secret).
local function ownedPetIds()
	local out = {}
	local pets = PetCatalog.Pets or {}
	for index = #pets, 1, -1 do
		local def = pets[index]
		if State.OwnedCount(def.Id) > 0 then
			table.insert(out, def.Id)
		end
	end
	return out
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

-- Element ids of a pet (v3 section 11), filtered by Config.Elements; empty while the catalog has none.
local function elementsOf(def)
	local info = Config.Elements and Config.Elements.Info
	if type(def) ~= "table" or type(info) ~= "table" then
		return {}
	end
	local raw = nil
	if type(PetCatalog.ElementsOf) == "function" then
		local ok, result = pcall(PetCatalog.ElementsOf, def)
		if ok then
			raw = result
		end
	end
	if raw == nil and type(PetCatalog.GetElements) == "function" then
		local ok, result = pcall(PetCatalog.GetElements, def.Id)
		if ok then
			raw = result
		end
	end
	if raw == nil then
		raw = def.Elements or def.Element
	end
	if type(raw) == "string" then
		raw = { raw }
	end
	local out, seen = {}, {}
	if type(raw) == "table" then
		for _, e in ipairs(raw) do
			if type(e) == "string" and info[e] and not seen[e] then
				seen[e] = true
				table.insert(out, e)
			end
		end
	end
	return out
end

-- CloudUI slots carry small count / key / marker texts (16-17 design px); at the phone scale (0.8) they
-- would render under 14 px, so the slots this menu makes get a size that stays readable.
local function readableSlot(slot)
	if not slot or not slot.Root then
		return slot
	end
	local count = slot.Root:FindFirstChild("Count", true)
	if count and count:IsA("TextLabel") and count.TextSize < 19 then
		count.TextSize = 19
		count.Size = UDim2.new(count.Size.X.Scale, count.Size.X.Offset, 0, 22)
	end
	for _, name in ipairs({ "Key", "Mark" }) do
		local label = slot.Root:FindFirstChild(name, true)
		if label and label:IsA("TextLabel") and label.TextSize < 18 then
			label.TextSize = 18
			local chip = label.Parent
			if chip and chip:IsA("GuiObject") and chip.Size.X.Offset < 28 then
				chip.Size = UDim2.fromOffset(28, 28)
			end
		end
	end
	return slot
end

-- CloudUI.Pill with a text size that stays >= 14 px at the phone scale (0.8).
local function readablePill(text, kind, parent)
	local pill = CloudUI.Pill(text, kind, parent)
	if pill then
		pill.TextSize = math.max(pill.TextSize, 18)
	end
	return pill
end

-- Coloured pill with the element name (no asset ids).
local function elementPill(parent, element, textSize, layoutOrder)
	local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[element]
	local color = info and info.Color or Colors.PanelLight
	local dark = Theme.Darken(color, 0.62)
	local size = textSize or 17
	local pill = Theme.Label(element, "Heading", {
		Size = size,
		Color = WHITE,
		Stroke = 0.1,
		StrokeColor = dark,
		Outline = 1.5,
		OutlineColor = dark,
		Props = {
			Name = "Element_" .. element,
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, size + 9),
			LayoutOrder = layoutOrder or 0,
		},
	})
	round(pill)
	stroke(pill, NAVY, 2, 0)
	Theme.Gradient(pill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 204, 226), 90)
	pad(pill, 9, 0, 9, 1)
	pill.Parent = parent
	return pill
end

-- A solid coloured pill (tier / hybrid badges, "MAX", locks): white text with a dark outline of its own colour.
local function colorPill(parent, name, text, color, textSize, layoutOrder)
	local dark = Theme.Darken(color, 0.62)
	local size = textSize or 18
	local pill = Theme.Label(text, "Heading", {
		Size = size,
		Color = WHITE,
		Stroke = 0.1,
		StrokeColor = dark,
		Outline = 1.5,
		OutlineColor = dark,
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

P2.TIER_RANK = { Normal = 1, Golden = 2, Rainbow = 3 }

function P2.parseKey(key)
	if type(key) ~= "string" then
		return nil
	end
	if PetKeys and type(PetKeys.Parse) == "function" then
		local ok, parsed = pcall(PetKeys.Parse, key)
		if ok and type(parsed) == "table" then
			return parsed
		end
	end
	local base, tier = key:match("^(.-)@(%a+)$")
	base = base or key
	tier = tier or "Normal"
	if base:sub(1, 4) == "hyb:" then
		return { Key = key, HybridId = base:sub(5), Tier = tier }
	end
	return { Key = key, PetId = base, Tier = tier }
end

-- The definition of a pet copy: the catalog def (Normal), a tier def (Look.Finish), a merged hybrid def, or nil.
function P2.defOfKey(key)
	if type(key) ~= "string" then
		return nil
	end
	if type(State.DefOf) == "function" then
		local ok, def = pcall(State.DefOf, key)
		if ok and type(def) == "table" then
			return def
		end
	end
	return PetCatalog.Get(key)
end

function P2.tierOf(key, def)
	local t = type(def) == "table" and def.Tier or nil
	if t == "Golden" or t == "Rainbow" then
		return t
	end
	local parsed = P2.parseKey(key)
	if parsed and (parsed.Tier == "Golden" or parsed.Tier == "Rainbow") then
		return parsed.Tier
	end
	return "Normal"
end

function P2.isHybrid(key, def)
	if type(def) == "table" and def.IsHybrid == true then
		return true
	end
	return type(key) == "string" and key:sub(1, 4) == "hyb:"
end

-- x1 / x1.5 / x2.5 (perks and stats of tier copies; hybrids carry their own)
function P2.tierMultiplier(key, def)
	if type(def) == "table" and type(def.StatMultiplier) == "number" and def.StatMultiplier > 0 then
		return def.StatMultiplier
	end
	local tier = P2.tierOf(key, def)
	if tier == "Rainbow" then
		return 2.5
	elseif tier == "Golden" then
		return 1.5
	end
	return 1
end

function P2.displayName(key, def)
	def = def or P2.defOfKey(key)
	if type(def) ~= "table" then
		return tostring(key)
	end
	return tostring(def.DisplayName or def.Name or key)
end

-- Owned pet copies in grid order: rarest first; inside a rarity the hybrids, then the catalog pets (reverse catalog
-- order, a pet's Rainbow / Golden copies right before its Normal ones).
function P2.ownedKeys()
	local keys = nil
	if type(State.Keys) == "function" then
		local ok, list = pcall(State.Keys)
		if ok and type(list) == "table" then
			keys = list
		end
	end
	if not keys then
		keys = {}
		for _, def in ipairs(PetCatalog.Pets or {}) do
			keys[#keys + 1] = def.Id
		end
	end
	local info, out = {}, {}
	for i, key in ipairs(keys) do
		if type(key) == "string" and not info[key] and State.OwnedCount(key) > 0 then
			local def = P2.defOfKey(key)
			if def then
				info[key] = { Order = rarityOrder(def.Rarity), Hybrid = P2.isHybrid(key, def) and 1 or 0, Index = i }
				out[#out + 1] = key
			end
		end
	end
	table.sort(out, function(a, b)
		local x, y = info[a], info[b]
		if x.Order ~= y.Order then
			return x.Order > y.Order
		end
		if x.Hybrid ~= y.Hybrid then
			return x.Hybrid > y.Hybrid
		end
		return x.Index > y.Index
	end)
	return out
end

-- level, xp of a pet copy
function P2.petLevel(key)
	if type(State.PetLevel) == "function" then
		local ok, level, xp = pcall(State.PetLevel, key)
		if ok and type(level) == "number" then
			return math.max(1, math.floor(level)), tonumber(xp) or 0
		end
	end
	return 1, 0
end

-- XP from `level` to the next one (math.huge at the top of the curve)
function P2.xpToNext(level)
	if TycoonCatalog and type(TycoonCatalog.XpToNext) == "function" then
		local ok, n = pcall(TycoonCatalog.XpToNext, level)
		if ok and type(n) == "number" and n > 0 then
			return n
		end
	end
	return math.huge
end

function P2.levelCap(key, def)
	if type(PetCatalog.LevelCap) == "function" then
		local ok, cap = pcall(PetCatalog.LevelCap, def or key)
		if ok and type(cap) == "number" and cap >= 1 then
			return math.floor(cap)
		end
	end
	return (TycoonCatalog and tonumber(TycoonCatalog.MaxPetLevel)) or 50
end

-- the pet's stats at its level (rarity scale x level factor x tier), or nil without a catalog that knows stats
function P2.statsAt(def, level)
	if type(def) ~= "table" then
		return nil
	end
	if type(PetCatalog.StatsOf) == "function" then
		local ok, stats = pcall(PetCatalog.StatsOf, def, level)
		if ok and type(stats) == "table" then
			return stats
		end
	end
	if type(PetCatalog.GetStats) == "function" and type(def.Id) == "string" then
		local ok, stats = pcall(PetCatalog.GetStats, def.Id, level)
		if ok and type(stats) == "table" then
			return stats
		end
	end
	return nil
end

function P2.homeData()
	if type(State.Home) == "function" then
		local ok, home = pcall(State.Home)
		if ok and type(home) == "table" then
			return home
		end
	end
	return { Level = 0, Prestige = 0, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0 }
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

function P2.gemBalance()
	if type(State.Gems) == "function" then
		local ok, value = pcall(State.Gems)
		if ok and type(value) == "number" then
			return value
		end
	end
	return 0
end

-- "$950", "$12.5K" (TycoonCatalog.FormatCash, the same text as the pad signs)
function P2.formatCash(n)
	if TycoonCatalog and type(TycoonCatalog.FormatCash) == "function" then
		local ok, text = pcall(TycoonCatalog.FormatCash, n)
		if ok and type(text) == "string" then
			return text
		end
	end
	return G.Cash .. Theme.ShortNumber(tonumber(n) or 0)
end

-- cash per second: one decimal below 100 ("$7.5"), FormatCash above
function P2.formatRate(n)
	n = tonumber(n) or 0
	if n ~= n or n < 0 then
		n = 0
	end
	if n < 100 then
		local text = string.format("%.1f", math.floor(n * 10 + 0.5) / 10)
		text = text:gsub("%.0$", "")
		return G.Cash .. text
	end
	return P2.formatCash(n)
end

function P2.gemAmount(n)
	return G.Gem .. " " .. commas(n)
end

function P2.foodList()
	local foods = TycoonCatalog and TycoonCatalog.Foods
	if type(foods) == "table" then
		return foods
	end
	return {}
end

function P2.foodCount(foodId)
	if type(State.FoodCount) == "function" then
		local ok, n = pcall(State.FoodCount, foodId)
		if ok and type(n) == "number" then
			return n
		end
	end
	return 0
end

function P2.foodGlyph(foodId)
	return G[foodId] or G.Food
end

-- slots of `map` ({[slot] = key}) that hold `key`, ascending
function P2.slotsHolding(map, key)
	local out = {}
	if type(map) == "table" then
		for slot, k in pairs(map) do
			if k == key and type(slot) == "number" then
				out[#out + 1] = slot
			end
		end
	end
	table.sort(out)
	return out
end

-- bug batch 2 #18: copies of a key working in the Garden, and whether it has NO copy free of it (busy gardening).
-- Only OPEN places count (DataService P3.placedCopies): a copy resting on a place a Prestige closed earns nothing and
-- is free to follow / fight (the server takes it off that bed silently).
function P2.gardenCopies(key)
	local home = P2.homeData()
	local open = P2.catalogCall("GardenSlots", home) or 0
	local n = 0
	for _, slot in ipairs(P2.slotsHolding(home.Garden, key)) do
		if open < 1 or slot <= open then
			n = n + 1
		end
	end
	return n
end
function P2.isGardening(key)
	local garden = P2.gardenCopies(key)
	return garden > 0 and State.OwnedCount(key) - garden < 1
end

function P2.firstFreeSlot(map, count)
	for slot = 1, count do
		if type(map) ~= "table" or map[slot] == nil then
			return slot
		end
	end
	return nil
end

function P2.catalogCall(fnName, ...)
	if not TycoonCatalog or type(TycoonCatalog[fnName]) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(TycoonCatalog[fnName], ...)
	if ok then
		return a, b
	end
	return nil
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

-- one pet's growth { Evo, Speed, Physique, Ability, Defense, Job | nil } (State.PetGrowth; zeros when absent)
function P2.growth(key)
	if type(State.PetGrowth) == "function" then
		local ok, g = pcall(State.PetGrowth, key)
		if ok and type(g) == "table" then
			return g
		end
	end
	return { Evo = 0 }
end

-- Phase 5 (3.7): the stored stage the way every site draws it (State.PetStage: EvolutionStage of the stored Evo)
function P2.stage(key)
	if type(State.PetStage) == "function" then
		local ok, stage = pcall(State.PetStage, key)
		if ok and type(stage) == "number" then
			return math.max(0, math.floor(stage))
		end
	end
	return math.max(0, math.floor(tonumber(P2.growth(key).Evo) or 0))
end

-- Phase 5 (m17): BattleCatalog.UnitPower of a pet copy (a Support pet with its Support role multipliers), or nil
function P5.battlePower(key, def, level)
	if P5.Battle == nil then
		P5.Battle = false
		local module = Shared:FindFirstChild("BattleCatalog")
		local ok, mod = pcall(function()
			return module and require(module)
		end)
		if ok and type(mod) == "table" and type(mod.UnitPower) == "function" then
			P5.Battle = mod
		end
	end
	if not P5.Battle then
		return nil
	end
	local growth = P2.growth(key)
	local train = { Speed = growth.Speed, Physique = growth.Physique, Ability = growth.Ability, Defense = growth.Defense }
	local entry = { Def = def, Key = key, Level = level, Tier = P2.tierOf(key, def), Evo = P2.stage(key), Train = train }
	local ok, power = pcall(P5.Battle.UnitPower, entry)
	if ok and type(power) == "number" then
		return math.floor(power + 0.5)
	end
	return nil
end

-- Phase 5 (3.7): an owned pet copy's evolved look on a CloudUI.Slot (the slot draws the plain form only): a Low-detail
-- evolved viewport over the slot ("EvolvedView", kept while the same pet + stage is shown); stage 0 removes it.
function P5.evoSlot(slot, def, stage)
	local cur = slot.P5Evo
	stage = math.floor(tonumber(stage) or 0)
	if stage < 1 or type(def) ~= "table" then
		if cur then
			pcall(cur.Handle.Destroy)
			slot.P5Evo = nil
		end
		return false
	end
	if cur and cur.Id == def.Id and cur.Stage == stage and cur.Handle.Frame.Parent then
		return true
	end
	if cur then
		pcall(cur.Handle.Destroy)
	end
	local handle = CloudUI.PetViewport(slot.Button, def, UDim2.new(1, -8, 1, -8), {
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Spin = "sway",
		Animate = false,
		Evolved = stage,
		Detail = "Low",
		ZIndex = 2,
	})
	handle.Frame.Name = "EvolvedView"
	slot.P5Evo = { Id = def.Id, Stage = stage, Handle = handle }
	return true
end

-- the running training job of a key or nil
function P2.job(key)
	local job = P2.growth(key).Job
	return type(job) == "table" and job or nil
end

-- seconds left on a job ("2:10")
function P2.jobLeft(job)
	local now = os.time()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		now = t
	end
	local left = math.max(0, math.ceil((tonumber(job and job.Ends) or 0) - now))
	return string.format("%d:%02d", math.floor(left / 60), left % 60)
end

-- "Attack Speed" for "Speed"
function P2.skillName(stat)
	if stat == "Speed" then
		return "Attack Speed"
	end
	return tostring(stat or "")
end

-- the next evolution stage when the pet can EVOLVE now (PetCatalog.CanEvolve), else nil
function P2.canEvolve(key, def, level)
	if type(PetCatalog.CanEvolve) ~= "function" then
		return nil
	end
	local ok, nextStage = pcall(PetCatalog.CanEvolve, def or key, level, P2.stage(key))
	if ok and type(nextStage) == "number" and nextStage >= 1 then
		return nextStage
	end
	return nil
end

-- coins per second of a pet in this home's Garden (PetPower x food x stars / meal x the Lucky EV; the grass food
-- before the Garden is built): the "Coins $/s" pill
function P2.coinsPerSecond(key, def, home)
	if not TycoonCatalog then
		return 0
	end
	local level = P2.petLevel(key)
	local power = P2.catalogCall("PetPower", { Def = def, Level = level, Stage = P2.stage(key), Key = key }) or 0
	local coins = TycoonCatalog.Coins or {}
	local food = P2.catalogCall("FoodOf", home) or 0
	if food <= 0 then
		food = tonumber(coins.GrassFood) or 12
	end
	local mult = P2.catalogCall("PrestigeMultiplier", math.floor(tonumber(home.Prestige) or 0)) or 1
	local lucky = P2.catalogCall("LuckyEV", home) or 1
	return power * food * mult * lucky / (tonumber(coins.MealSeconds) or 8)
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

-- "This pet is gardening! Take it out of the garden and equip it?" [Yes] [No]. Yes = ONE request (HomeAction
-- "GardenRecall"; the server checks everything and takes it out + equips / stores the team); No = nothing.
-- target = { To = "Equip" } | { To = "Team", Preset = n, Keys = {...} }; onYes (optional) runs after the request.
function P2.askRecall(key, target, onYes)
	if P2.RecallDialog then
		P2.RecallDialog:Destroy()
	end
	local overlay = makeFrame(gui, "GardenRecall", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.fromRGB(8, 12, 32),
		Active = true,
		ZIndex = 60,
	})
	P2.RecallDialog = overlay
	local box = makeFrame(overlay, "Box", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0, 210), -- phone: 92 % of the width, capped at 420 px
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		ZIndex = 61,
	})
	Util.Create("UISizeConstraint", { MaxSize = Vector2.new(420, 210), Parent = box })
	corner(box, 16)
	stroke(box, C2.Kind.Garden, 4, 0)
	Theme.Gradient(box, Colors.PanelLight, Colors.Panel, 90)
	makeText(box, "Title", G.Seedling .. " This pet is gardening!", "Title", 28, C2.Kind.Garden, {
		Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 36), ZIndex = 62,
	})
	local verb = target.To == "Team" and "put it in your team?" or "equip it?"
	makeText(box, "Body", "Take it out of the garden and " .. verb, "Body", 20, WHITE, {
		Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 60), TextWrapped = true, ZIndex = 62,
	})
	local buttons = makeFrame(box, "Buttons", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -32, 0, 56), ZIndex = 62,
	})
	listLayout(buttons, Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local function close()
		if P2.RecallDialog == overlay then
			P2.RecallDialog = nil
		end
		overlay:Destroy()
	end
	CloudUI.Button({
		Name = "RecallYes", Text = "Yes", Style = "Green", Size = UDim2.fromOffset(150, 56), TextSize = 24, LayoutOrder = 1, ZIndex = 63,
		Callback = function()
			close()
			local arg = { Key = key, To = target.To, Preset = target.Preset, Keys = target.Keys }
			if fireKeyed("HomeAction:Recall", "HomeAction", "GardenRecall", arg) and onYes then
				onYes()
			end
		end,
		Parent = buttons,
	})
	CloudUI.Button({
		Name = "RecallNo", Text = "No", Style = "Pink", Size = UDim2.fromOffset(150, 56), TextSize = 24, LayoutOrder = 2, ZIndex = 63,
		Callback = close,
		Parent = buttons,
	})
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

-- true on a portrait screen (a phone held upright): windows that support it use their single-column layout
local function portraitScreen()
	local area = guiSize()
	return area.X < area.Y
end

-- Phase 5 (6.6): a small centred confirm (the odds popup): { w, h, scale, x, y } (x, y = centre in gui px). It covers
-- at most 30% of the screen while its text keeps the 0.8 readability scale; where that cannot hold (phones) it becomes a
-- window-rule panel instead (docked right / a bottom sheet: NeonKit.SideRect). (Replaces Phase 4's fitBox.)
local function confirmBox(prefW, prefH, minW, minH)
	local area = guiSize()
	local factor = screenFactor()
	local w = Util.Clamp(math.floor((area.X * 0.7) / factor), minW, prefW)
	local h = Util.Clamp(math.floor((area.Y - 2 * K.MARGIN - 58) / factor), minH, prefH)
	local scale = math.min(factor, math.sqrt(0.3 * area.X * area.Y / (w * h)))
	if scale < 0.8 - 1e-3 then
		local r = P5.Kit.SideRect(prefW, prefH)
		return { w = math.floor(r.designW), h = math.floor(r.designH), scale = r.scale, x = math.floor(r.x + r.w / 2 + 0.5), y = math.floor(r.y + r.h / 2 - P5.inset() + 0.5) }
	end
	return { w = w, h = h, scale = scale, x = math.floor(area.X / 2 + 0.5), y = math.floor(area.Y / 2 + 0.5) }
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
	corner(frame, 12)
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
		return TextService:GetTextSize(Hint.Label.Text, Hint.Label.TextSize, Hint.Label.Font, Vector2.new(4000, 1000))
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

-- HotbarController re-centres the hotbar left of a docked window (6.6); nil when nothing is docked right
function P5.avoidRight(x)
	if P5.Hotbar == nil then
		P5.Hotbar = false
		local module = script.Parent:FindFirstChild("HotbarController")
		local ok, mod = pcall(function()
			return module and require(module)
		end)
		if ok and type(mod) == "table" and type(mod.SetAvoidRight) == "function" then
			P5.Hotbar = mod
		end
	end
	if P5.Hotbar then
		pcall(P5.Hotbar.SetAvoidRight, x)
	end
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
	if win.Shown then
		P5.avoidRight(rect.mode == "Side" and rect.x or nil)
	end
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

local function normalizeTab(windowId, tab)
	if type(tab) ~= "string" then
		return nil
	end
	local t = tab:lower()
	if t:find("roul", 1, true) then
		return "Roulettes"
	elseif t:find("item", 1, true) then
		return "Items"
	elseif t:find("gem", 1, true) then
		if windowId == "Shop" then
			return "Gems"
		end
	elseif t:find("pet", 1, true) then
		if windowId == "Inventory" then
			return "Pets"
		end
	end
	return nil
end

function openWindow(id, args)
	local win = windows[id]
	if not win or Spin.Stage then
		return
	end
	args = type(args) == "table" and args or {}
	closeIndex()
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
		if id == "Shop" then
			-- sculpt the likely roulette pools ahead of the spin (the last one spun, then the cheapest)
			if Spin.Last then
				Warm.Roulette(Spin.Last)
			end
			local first = type(Config.Roulettes) == "table" and Config.Roulettes[1] or nil
			if type(first) == "table" then
				Warm.Roulette(first.Id)
			end
		end
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
	if P2.RecallDialog then
		-- bug batch 2 #18: the garden recall question goes with its window
		P2.RecallDialog:Destroy()
		P2.RecallDialog = nil
	end
	if openId == id then
		openId = nil
	end
	syncBackBinding()
	if win.OnClose then
		safe("close " .. id, win.OnClose)
	end
	if id == "Shop" then
		closeOdds()
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
	if not openId then
		P5.avoidRight(nil)
	end
	updateMenuActive()
end

-- Button behaviour: open, or close when this exact view is already showing.
function toggleWindow(id, args)
	local win = windows[id]
	if not win then
		return
	end
	local wantTab = args and normalizeTab(id, args.Tab) or nil
	if win.Shown and (wantTab == nil or win.Tab == wantTab) then
		closeWindow(id)
	else
		openWindow(id, args)
	end
end

local function closeEverything()
	Spin.Queue = {} -- pets from queued results are already in the collection, just skip their shows
	if Spin.Stage then
		closeStage()
	end
	closeOdds()
	if openId then
		closeWindow(openId)
	end
	closeIndex()
end

-- Esc / gamepad B: close the topmost thing. Returns true when something was closed.
-- (The Pet Index handles Esc / B itself.)
function handleBack()
	if Spin.Stage then
		if Spin.Stage.Phase == "reveal" then
			closeStage()
		else
			skipSpin()
		end
		return true
	end
	if Odds.Gui then
		closeOdds()
		return true
	end
	if P2.RecallDialog then
		-- bug batch 2 #18: Esc / B answers the garden recall question "No"
		P2.RecallDialog:Destroy()
		P2.RecallDialog = nil
		return true
	end
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

-- Binds B while a window, the odds popup or the roulette stage is open and unbinds it when none is.
-- Called after every change of openId / Odds.Gui / Spin.Stage.
function syncBackBinding()
	local wanted = openId ~= nil or Odds.Gui ~= nil or Spin.Stage ~= nil
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
local function menuActionInventory()
	toggleWindow("Inventory", { Tab = "Items" })
end

local function menuActionPets()
	toggleWindow("Inventory", { Tab = "Pets" })
end

local function openIndex(groupId)
	local index = getIndex()
	if not index or type(index.Open) ~= "function" then
		showHint("The Pet Index is getting ready. Try again soon!", "info")
		return
	end
	if Spin.Stage then
		return
	end
	closeOdds()
	if openId then
		closeWindow(openId, true)
	end
	safe("Index.Open", index.Open, groupId)
end

local function menuActionIndex()
	if indexOpen() then
		closeIndex()
	else
		openIndex(nil)
	end
end

local function menuActionShop()
	if inMatch() then
		showHint("The shop is closed during a match.", "info")
		return
	end
	toggleWindow("Shop")
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

-- Phase 5 (6.6): the Settings gear opens MainMenuController's settings panel (menu W3); a hint until it exists
function P5.openSettings()
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

-- The menu (bug batch 2 #1, option A "Split & shift"): ONE slim column of eight neon tiles against the left edge,
-- vertically centred (Pets, Items, Team, Index, Shop, Home, Stats, the Settings gear), with a small arrow tab beside
-- its last tile that slides the column off the edge and back (remembered for the session). Each tile is a
-- NeonKit.Tile whose root is the TextButton MenuButton_<Id> inside a frame Entry_<Id> of the frame "MenuColumn" (names
-- kept: the tutorial rings them; the gear's frame is Gear_Settings; the tab is MenuColumn.Toggle, so everything that
-- measures the column also keeps clear of the tab). Tiles are designed at 66 px under one UIScale: 56 px on a 1080p
-- desktop (x the screen factor), 50 px on touch screens, never below 44 px (a thumb). Where one column does not fit
-- that minimum (the band above a landscape phone's thumbstick, the strip above a portrait phone's sheet) the tiles
-- wrap into two slim columns of four (three columns on the shortest phones), still clear of the stick and never
-- reaching into the middle of the screen.
local MENU = {
	{ Id = "Pets", Label = "Pets", Icon = "Pets", Color = "Orange", Action = menuActionPets },
	{ Id = "Inventory", Label = "Items", Icon = "Items", Color = "Blue", Action = menuActionInventory },
	{ Id = "Team", Label = "Team", Icon = "Team", Color = "Red", Action = function()
		toggleWindow("Team") -- Phase 3: the battle team presets
	end },
	{ Id = "Index", Label = "Index", Icon = "Index", Color = "Purple", Action = menuActionIndex },
	{ Id = "Shop", Label = "Shop", Icon = "Shop", Color = "Green", Action = menuActionShop },
	{ Id = "Spot", Label = "Home", Icon = "Home", Color = "Yellow", Action = menuActionSpot },
	{ Id = "Stats", Label = "Stats", Icon = "Stats", Color = "Cyan", Action = menuActionStats },
	{ Id = "Settings", Label = "Settings", Icon = "Settings", Color = "Grey", Gear = true, Action = function()
		P5.openSettings()
	end },
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

-- active (its window is open): the gold glow ring + a gold label; disabled (in a match): grey
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
		if tile.Label then
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
		entry.Root.Visible = not U.ColumnHidden and not U.TilesFolded
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

-- Places the tiles in `cols` columns (row by row: Pets Items / Team Index / ... in two columns) and the tab beside
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
	local tab = Util.Create("TextButton", {
		Name = "Toggle",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Colors.PanelBottom or NAVY,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = column,
	})
	corner(tab, 8)
	U.TabStroke = stroke(tab, Theme.Lighten(Colors.PanelTop or NAVY, 0.35), 2, 0.1)
	U.TabArrow = makeText(tab, "Arrow", "<", "Display", 26, WHITE, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	U.TabBadge = makeFrame(tab, "Badge", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -2, 0, 4),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Neon and Theme.Neon.Red or Colors.Bad,
		Visible = false,
		ZIndex = 5,
	})
	round(U.TabBadge)
	stroke(U.TabBadge, INK, 2, 0)
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
	if Odds.Holder and Odds.Fit then
		local box = confirmBox(K.WIN.Odds[1], K.WIN.Odds[2], K.WIN.Odds[3], K.WIN.Odds[4])
		Odds.Holder.Size = UDim2.fromOffset(box.w, box.h)
		Odds.Holder.Position = UDim2.fromOffset(box.x, box.y)
		Odds.Fit.Scale = box.scale
	end
	if Spin.Stage and Spin.Stage.Relayout then
		Spin.Stage.Relayout()
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
	local invWin = windows.Inventory
	local invTab = invWin and invWin.Shown and invWin.Tab or nil
	setActive("Inventory", invTab == "Items")
	setActive("Pets", invTab == "Pets")
	setActive("Index", indexOpen())
	setActive("Shop", windows.Shop ~= nil and windows.Shop.Shown)
	setActive("Stats", windows.Stats ~= nil and windows.Stats.Shown)

	setActive("Spot", windows.Home ~= nil and windows.Home.Shown)
	setActive("Team", windows.Team ~= nil and windows.Team.Shown)
	if invWin and invWin.Shown and Entries.Pets then
		Entries.Pets.SetBadge(false)
	end
	-- the Spot and Shop tiles are greyed out in matches
	setDisabled("Spot", inMatch())
	setDisabled("Shop", inMatch())
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

local function gotoShopItems()
	if inMatch() then
		showHint("The shop is closed during a match.", "info")
		return
	end
	openWindow("Shop", { Tab = "Items" })
end

----------------------------------------------------------------------
-- Inventory window: tabs Pets + Items. Phase 2: one slot per pet COPY key (tier / hybrid badges, levels), the detail
-- card with level + XP, scaled stats and the Feed / Place in Garden / Train in Gym actions, and the Feed picker.
----------------------------------------------------------------------
-- An empty-state block ("No pets yet!" + a line + a gold button) that fits whatever column it is in (bug batch 2 #1
-- Studio check: on a landscape phone the Pets grid is ~180 design px wide and the old fixed 220 px button stuck out of
-- it while the 56 px body box cut its text after two lines). The title and the body wrap and grow (AutomaticSize Y),
-- the button takes the column's width (minus room for its 4 px glow ring) capped at opts.ButtonW, and the block grows
-- with its content (opts.Fill: fill the parent and centre in it, else AutomaticSize Y in a list). Returns
-- { Frame, Title, Body, Button }; opts: Parent, Title, Body, ButtonText, ButtonName, ButtonW, ButtonH, Callback,
-- TitleSize, BodySize, BodyMaxW, Fill, LayoutOrder, ZIndex.
function P5.emptyState(opts)
	local out = {}
	local frame = makeFrame(opts.Parent, "Empty", {
		Size = opts.Fill and UDim2.new(1, 0, 1, 0) or UDim2.new(1, 0, 0, 0),
		AutomaticSize = (not opts.Fill) and Enum.AutomaticSize.Y or nil,
		LayoutOrder = opts.LayoutOrder or 0,
		Visible = false,
		ZIndex = opts.ZIndex or 1,
	})
	out.Frame = frame
	pad(frame, 8, 0, 8, 0)
	listLayout(frame, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, opts.Fill and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top)
	if opts.Title then
		out.Title = makeText(frame, "Title", opts.Title, "Title", opts.TitleSize or 32, WHITE, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = 1,
		})
	end
	out.Body = makeText(frame, opts.Title and "Body" or "Text", opts.Body or "", "Body", opts.BodySize or 20, MUTED, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 2,
	})
	-- (a short line on wide pages: as wide as before, 404 design px on the 1080p Pets page)
	Util.Create("UISizeConstraint", { MaxSize = Vector2.new(opts.BodyMaxW or 404, math.huge), Parent = out.Body })
	out.Button = CloudUI.Button({
		Name = opts.ButtonName or "OpenShop",
		Text = opts.ButtonText or "Open Shop",
		Style = "Gold",
		Size = UDim2.new(1, -8, 0, opts.ButtonH or 56), -- (1, -8): its glow ring reaches 4 px past each side
		TextSize = 24,
		LayoutOrder = 3,
		Callback = opts.Callback,
		Parent = frame,
	})
	Util.Create("UISizeConstraint", { MaxSize = Vector2.new(opts.ButtonW or 220, opts.ButtonH or 56), Parent = out.Button })
	return out
end

-- Phase 5 (6.6): the Pets page in its three window shapes. "Wide" (a docked 820 px window): the grid left, a 300 px card
-- right; "Tall" (720p / portrait sheets): the grid on top, the card below with the pet, its name, pills and level side
-- by side and the six buttons in 2 rows of 3; "Short" (landscape phones, ~460 x 390): a 2-column grid left and a slim
-- card right. The equipped header only shows in the wide shape (the grid's stars mark the equipped pets).
function P5.petsLayout(W, w, h, narrow, short, tall)
	if not (W.Detail and W.View) then
		return
	end
	local mode = short and "Short" or (tall and "Tall" or "Wide")
	W.Mode = mode
	local pageH = h - 150
	if W.Page and W.Page.AbsoluteSize.Y > 10 and W.Page.Parent then
		local holder = W.Page:FindFirstAncestorWhichIsA("ScreenGui")
		local sc = 1
		local node = W.Page
		while node and node ~= holder do
			local u = node:FindFirstChildWhichIsA("UIScale")
			if u then
				sc = sc * u.Scale
			end
			node = node.Parent
		end
		pageH = W.Page.AbsoluteSize.Y / math.max(sc, 0.1)
	end
	local layout = W.Grid and W.Grid:FindFirstChild("Layout")
	if layout then
		local cell = (mode == "Short") and 80 or (mode == "Tall" and 96 or 104)
		layout.CellSize = UDim2.fromOffset(cell, cell)
	end
	W.Header.Visible = mode == "Wide"
	W.GridWell.Position = UDim2.fromOffset(0, mode == "Wide" and 84 or 0)
	W.GridWell.Size = UDim2.new(1, 0, 1, mode == "Wide" and -84 or 0)
	local scroll = W.InfoScroll
	local compact = mode ~= "Wide"
	if compact then
		W.View.Parent = W.Top
		W.Name.Parent = W.Top
		W.MetaRow.Parent = W.Top
		W.LevelRow.Parent = W.Top
		W.Top.Visible = true
		W.MetaRow.AutomaticSize = Enum.AutomaticSize.None
		W.MetaRow.ClipsDescendants = true
		W.LevelText.Size = UDim2.fromOffset(100, 32)
		W.XpBar.Size = UDim2.new(1, -104, 0, 28)
	else
		W.View.Parent = scroll
		W.Name.Parent = scroll
		W.MetaRow.Parent = scroll
		W.LevelRow.Parent = scroll
		W.Top.Visible = false
		W.MetaRow.AutomaticSize = Enum.AutomaticSize.Y
		W.MetaRow.ClipsDescendants = false
		W.MetaRow.Position = UDim2.new()
		W.LevelText.Size = UDim2.fromOffset(122, 32)
		W.XpBar.Size = UDim2.new(1, -126, 0, 28)
	end
	if mode == "Wide" then
		local detailW = narrow and K.DETAIL_W_NARROW or K.DETAIL_W
		W.Detail.AnchorPoint = Vector2.new(1, 0)
		W.Detail.Position = UDim2.new(1, 0, 0, 0)
		W.Detail.Size = UDim2.new(0, detailW, 1, 0)
		W.Left.Size = UDim2.new(1, -(detailW + 12), 1, 0)
		W.View.Size = UDim2.new(1, 0, 0, 150)
		W.Glow.Size = UDim2.fromOffset(136, 136)
		W.Name.Size = UDim2.new(1, 0, 0, 36)
		W.LevelRow.Size = UDim2.new(1, 0, 0, 32)
		W.Buttons.Size = UDim2.new(1, -20, 0, 180)
		W.Buttons.Position = UDim2.new(0, 10, 1, -52)
		W.Status.Visible = true
		scroll.Visible = true
		scroll.Position = UDim2.fromOffset(4, 4)
		scroll.Size = UDim2.new(1, -8, 1, -240)
	elseif mode == "Tall" then
		local detailH = math.max(244, math.floor(pageH * 0.5))
		W.Detail.AnchorPoint = Vector2.new(0, 1)
		W.Detail.Position = UDim2.new(0, 0, 1, 0)
		W.Detail.Size = UDim2.new(1, 0, 0, detailH)
		W.Left.Size = UDim2.new(1, 0, 1, -(detailH + 8))
		W.Top.Size = UDim2.new(1, -16, 0, 104)
		W.View.Position = UDim2.fromOffset(0, 0)
		W.View.Size = UDim2.fromOffset(100, 100)
		W.Glow.Size = UDim2.fromOffset(88, 88)
		W.Name.Position = UDim2.fromOffset(110, 0)
		W.Name.Size = UDim2.new(1, -110, 0, 32)
		W.MetaRow.Position = UDim2.fromOffset(110, 34)
		W.MetaRow.Size = UDim2.new(1, -110, 0, 30)
		W.LevelRow.Position = UDim2.fromOffset(110, 68)
		W.LevelRow.Size = UDim2.new(1, -110, 0, 32)
		W.Buttons.Size = UDim2.new(1, -20, 0, 104)
		W.Buttons.Position = UDim2.new(0, 10, 1, -8)
		W.Status.Visible = false
		local room = detailH - 104 - 104 - 26
		scroll.Visible = room >= 40
		scroll.Position = UDim2.fromOffset(4, 114)
		scroll.Size = UDim2.new(1, -8, 0, math.max(0, room))
	else
		local detailW = math.max(196, math.floor(w - 2 * 80 - 10 - 48 - 52))
		W.Detail.AnchorPoint = Vector2.new(1, 0)
		W.Detail.Position = UDim2.new(1, 0, 0, 0)
		W.Detail.Size = UDim2.new(0, detailW, 1, 0)
		W.Left.Size = UDim2.new(1, -(detailW + 8), 1, 0)
		W.Top.Size = UDim2.new(1, -16, 0, 88)
		W.View.Position = UDim2.fromOffset(0, 0)
		W.View.Size = UDim2.fromOffset(54, 54)
		W.Glow.Size = UDim2.fromOffset(50, 50)
		W.Name.Position = UDim2.fromOffset(60, 0)
		W.Name.Size = UDim2.new(1, -60, 0, 28)
		W.MetaRow.Position = UDim2.fromOffset(60, 30)
		W.MetaRow.Size = UDim2.new(1, -60, 0, 26)
		W.LevelRow.Position = UDim2.fromOffset(0, 58)
		W.LevelRow.Size = UDim2.new(1, 0, 0, 30)
		W.LevelText.Size = UDim2.fromOffset(66, 32)
		W.XpBar.Size = UDim2.new(1, -70, 0, 28)
		W.Buttons.Size = UDim2.new(1, -12, 0, 114)
		W.Buttons.Position = UDim2.new(0, 6, 1, -4)
		W.Status.Visible = false
		local room = pageH - 94 - 114 - 12
		scroll.Visible = room >= 40
		scroll.Position = UDim2.fromOffset(4, 94)
		scroll.Size = UDim2.new(1, -8, 0, math.max(0, room))
	end
	-- no pets yet on a landscape phone ("Short"): the detail card has nothing to show ("Pick a pet ..."), so the empty
	-- state takes the whole page; in the grid's ~120 design px column its text and Open Shop button could not fit
	W.LastLayout = { w, h, narrow, short, tall }
	local wideEmpty = mode == "Short" and W.IsEmpty == true
	W.Detail.Visible = not wideEmpty
	if wideEmpty then
		W.Left.Size = UDim2.new(1, 0, 1, 0)
	end
	W.NameFit.MaxTextSize = compact and 24 or 30
	W.PlaceButtons()
end

local buildInventory -- (the window's helpers live in this do-block: Lua's 200-local limit of the main chunk)
do
	local RAINBOW = Colors.Rainbow or { Color3.fromRGB(232, 104, 120), Color3.fromRGB(98, 168, 232) }

	local function rainbowSequence()
		local keys = {}
		for i, c in ipairs(RAINBOW) do
			keys[#keys + 1] = ColorSequenceKeypoint.new((i - 1) / math.max(1, #RAINBOW - 1), c)
		end
		return ColorSequence.new(keys)
	end

	-- the Garden places of a pet copy (Phase 4: ANY role works there): { Place = "Garden", Slots, Placed = {slot...}, Map }
	local function workOf(key, def)
		if type(def) ~= "table" then
			return nil
		end
		local home = P2.homeData()
		local map = type(home.Garden) == "table" and home.Garden or {}
		return {
			Place = "Garden",
			Station = "Garden",
			Slots = P2.catalogCall("GardenSlots", home) or 0,
			Placed = P2.slotsHolding(map, key),
			Map = map,
		}
	end

	local function usedSlots(map, slots)
		local n = 0
		for slot = 1, slots do
			if type(map) == "table" and map[slot] ~= nil then
				n = n + 1
			end
		end
		return n
	end

	------------------------------------------------------------------
	-- the window
	------------------------------------------------------------------
	function buildInventory(win)
		local content = win.Panel.Content
		local maxEquipped = Config.Pets.MaxEquipped
		local pets = {
			Slots = {}, -- key -> CloudUI slot in the grid
			EquipSlots = {}, -- 1..MaxEquipped -> small slots in the header
			EquipIds = {}, -- key shown by each header slot
			Selected = nil, -- the selected pet copy key
			DetailPet = nil,
			DetailViewport = nil,
			Pills = {},
			PillKey = nil,
			StatKey = nil,
			Order = {}, -- owned keys in grid order (rarest first)
			Ready = {}, -- key -> true once the grid slot got its pet viewport
			Filling = false, -- true while the staggered viewport builder is running
		}
		local itemRows = {} -- itemId -> { Slot, Owned, Parts }
		local W = {} -- widgets of the pets page
		local refreshInventory

		local tabs = CloudUI.Tabs({
			Name = "InventoryTabs",
			Parent = content,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 1, -20),
			BarHeight = 50,
			TextSize = 22,
			OnSelect = function(name)
				win.Tab = name
				-- Phase 5: one window, two faces (the Pets tile / the Items tile)
				win.Panel.SetTitle(name == "Items" and "Items" or "Pets")
				win.Panel.SetAccent(name == "Items" and "Blue" or "Orange")
				updateMenuActive()
			end,
		})
		win.Tabs = tabs

		------------------------------------------------------------------
		-- Pets page
		------------------------------------------------------------------
		local function selectedWork()
			local key = pets.Selected
			local def = key and P2.defOfKey(key)
			return key, def, workOf(key, def)
		end

		local function doWork()
			local key, def, work = selectedWork()
			if not key or not def then
				return
			end
			if inMatch() then
				showHint("Pets are busy climbing during a match.", "info")
				return
			end
			if not work then
				return
			end
			if #work.Placed > 0 then
				fireKeyed("HomeAction:Garden", "HomeAction", "GardenSet", { Slot = work.Placed[#work.Placed] })
				return
			end
			if P2.job(key) then
				showHint(P2.displayName(key, def) .. " is training (" .. P2.jobLeft(P2.job(key)) .. " left).", "info")
				return
			end
			if work.Slots <= 0 then
				showHint("Build the Pet Garden at your home first.", "info")
				return
			end
			local free = P2.firstFreeSlot(work.Map, work.Slots)
			if not free then
				showHint("Your Garden is full (" .. work.Slots .. "/" .. work.Slots .. "). Prestige for one more place!", "info")
				return
			end
			fireKeyed("HomeAction:Garden", "HomeAction", "GardenSet", { Slot = free, Key = key })
		end

		-- Feed / Train / EVOLVE open CareController's windows (the Food Machine list, the Training Place, the confirm)
		local function careOpen(panelId, key)
			local care = P2.care()
			if not care then
				showHint("Pet care is getting ready. Try again in a moment!", "info")
				return
			end
			if inMatch() then
				showHint("Pets are busy climbing during a match.", "info")
				return
			end
			if panelId == "Evolve" then
				safe("evolve confirm", care.ConfirmEvolve, key)
			else
				safe("care open", care.Open, panelId, { Key = key })
			end
		end

		local function buildDetailCard(page)
			local card = makeInset(page, "Detail", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, K.DETAIL_W, 1, 0),
			})
			W.Detail = card
			W.DetailEmpty = makeText(card, "Hint", "Pick a pet to see its details.", "Body", 19, MUTED, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(1, -40, 0, 60),
				TextWrapped = true,
			})
			local body = makeFrame(card, "Body", { Size = UDim2.new(1, 0, 1, 0), Visible = false })
			W.DetailBody = body
			local scroll = scroller(body, "Info", {
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(1, -8, 1, -176),
			})
			W.InfoScroll = scroll
			-- Phase 5: compact cards (tall / short windows) move the pet, its name, pills and level into this fixed
			-- header beside each other; the wide card keeps them on top of the scrolling info (see P5.petsLayout)
			W.Top = makeFrame(body, "Top", { Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 104), Visible = false })
			pad(scroll, 10, 6, 14, 8)
			listLayout(scroll, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
			local view = makeFrame(scroll, "View", { Size = UDim2.new(1, 0, 0, 150), LayoutOrder = 1 })
			W.View = view
			W.Glow = makeFrame(view, "Glow", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.fromOffset(136, 136),
				BackgroundColor3 = GOLD,
				BackgroundTransparency = 0.78,
			})
			round(W.Glow)
			W.ViewportHolder = makeFrame(view, "ViewportHolder", { Size = UDim2.new(1, 0, 1, 0), ZIndex = 2 })
			W.Name = makeText(scroll, "Name", "", "Title", 30, WHITE, {
				Size = UDim2.new(1, 0, 0, 36),
				TextScaled = true,
				LayoutOrder = 2,
			})
			W.NameFit = Util.Create("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 18, Parent = W.Name })
			W.MetaRow = makeFrame(scroll, "Meta", {
				Size = UDim2.new(1, 0, 0, 30),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 3,
			})
			local metaLayout = listLayout(W.MetaRow, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
			metaLayout.Wraps = true
			W.OwnedLabel = makeText(scroll, "Owned", "", "Heading", 19, MUTED, {
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 4,
			})
			-- level + XP bar
			local levelRow = makeFrame(scroll, "LevelRow", { Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 5 })
			W.LevelRow = levelRow
			W.LevelText = makeText(levelRow, "Level", "Lv 1", "Heading", 20, WHITE, {
				Size = UDim2.fromOffset(122, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			W.XpBar = CloudUI.Bar({
				Name = "XpBar",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.new(1, -126, 0, 28),
				Height = 28,
				TextSize = 18,
				Color = C2.Xp,
				Parent = levelRow,
			})
			-- stats at this level
			W.StatsRow = makeFrame(scroll, "Stats", {
				Size = UDim2.new(1, 0, 0, 28),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 6,
			})
			local statsLayout = listLayout(W.StatsRow, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
			statsLayout.Wraps = true
			W.RoleRow = makeFrame(scroll, "Role", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 7 })
			listLayout(W.RoleRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
			W.Special = makeText(W.RoleRow, "Special", "", "Heading", 18, GOLD, {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 26),
				LayoutOrder = 2,
			})
			W.Work = makeText(scroll, "Work", "", "Heading", 19, Theme.Lighten(GOOD, 0.35), {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				LayoutOrder = 8,
			})
			W.Blurb = makeText(scroll, "Blurb", "", "Body", 18, WHITE, {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				LayoutOrder = 9,
			})
			W.Perks = makeText(scroll, "Perks", "", "Heading", 19, Theme.Lighten(GOOD, 0.3), {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				LayoutOrder = 10,
			})
			-- buttons pinned to the bottom of the card: Equip | Unequip, Feed | Garden, Train | EVOLVE
			local buttons = makeFrame(body, "Buttons", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 10, 1, -52),
				Size = UDim2.new(1, -20, 0, 172),
			})
			W.Buttons = buttons
			W.EquipBtn = CloudUI.Button({
				Name = "Equip",
				Text = "Equip",
				Style = "Green",
				Size = UDim2.new(0.5, -6, 1 / 3, -6),
				TextSize = 22,
				Callback = function()
					local key = pets.Selected
					if not key then
						return
					end
					if W.EquipGardening then
						-- bug batch 2 #18: every free copy is gardening: ask, then take one out and equip it (one request)
						P2.askRecall(key, { To = "Equip" })
					else
						fire("EquipPet", key)
					end
				end,
				Parent = buttons,
			})
			W.UnequipBtn = CloudUI.Button({
				Name = "Unequip",
				Text = "Unequip",
				Style = "Pink",
				Size = UDim2.new(0.5, -6, 1 / 3, -6),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				TextSize = 22,
				Callback = function()
					if pets.Selected then
						fire("UnequipPet", pets.Selected)
					end
				end,
				Parent = buttons,
			})
			W.FeedBtn = CloudUI.Button({
				Name = "FeedPet",
				Text = "Food Machine", -- Phase 5 (3.4): opens the Food Machine window on this pet (not a second feed)
				Style = "Gold",
				Size = UDim2.new(0.5, -6, 1 / 3, -6),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				TextSize = 22,
				Callback = function()
					if inMatch() then
						showHint("Pets eat at home, after the match.", "info")
						return
					end
					if pets.Selected then
						careOpen("Feed", pets.Selected)
					end
				end,
				Parent = buttons,
			})
			W.WorkBtn = CloudUI.Button({
				Name = "WorkPet",
				Text = "Garden",
				Style = "Blue",
				Size = UDim2.new(0.5, -6, 1 / 3, -6),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				TextSize = 20,
				Callback = function()
					doWork()
				end,
				Parent = buttons,
			})
			W.TrainBtn = CloudUI.Button({
				Name = "TrainPet",
				Text = "Train",
				Style = "Red",
				Size = UDim2.new(0.5, -6, 1 / 3, -6),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, 0),
				TextSize = 22,
				Callback = function()
					if pets.Selected then
						careOpen("Train", pets.Selected)
					end
				end,
				Parent = buttons,
			})
			W.EvolveBtn = CloudUI.Button({
				Name = "EvolvePet",
				Text = "EVOLVE!",
				Style = "Gold",
				Size = UDim2.new(0.5, -6, 1 / 3, -6),
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, 0, 1, 0),
				TextSize = 22,
				Callback = function()
					if pets.Selected then
						careOpen("Evolve", pets.Selected)
					end
				end,
				Parent = buttons,
			})
			-- "Food Machine" / "Leave Garden" take two lines in narrow cells (never under 18 design px)
			for _, b in ipairs({ W.WorkBtn, W.FeedBtn }) do
				b.TextWrapped = true
				b.TextTruncate = Enum.TextTruncate.None
				b.LineHeight = 0.92
			end
			-- the six buttons: 3 rows x 2 (Train takes the whole last row while there is no EVOLVE), or on short cards
			-- (landscape phones) 2 rows x 3
			function W.PlaceButtons()
				local list = { W.EquipBtn, W.UnequipBtn, W.FeedBtn, W.WorkBtn, W.TrainBtn, W.EvolveBtn }
				local cols = W.Mode == "Tall" and 3 or 2
				local rows = W.Mode == "Tall" and 2 or 3
				local size = W.Mode == "Wide" and 20 or 18 -- (18 x 0.8 >= 14 px on phones)
				for i, b in ipairs(list) do
					local col = (i - 1) % cols
					local row = math.floor((i - 1) / cols)
					b.AnchorPoint = Vector2.new(0, 0)
					b.Position = UDim2.new(col / cols, col > 0 and 3 or 0, row / rows, row > 0 and 3 or 0)
					b.Size = UDim2.new(1 / cols, -6, 1 / rows, -6)
					b.TextSize = size
				end
				if not W.Ready then
					-- no EVOLVE: Train takes the rest of its row
					local col = 4 % cols
					W.TrainBtn.Size = UDim2.new((cols - col) / cols, -6, 1 / rows, -6)
				end
			end
			W.Status = makeText(body, "Status", "", "Label", 18, MUTED, {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 10, 1, -4),
				Size = UDim2.new(1, -20, 0, 44),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Center,
			})
		end

		local function buildPetsPage(page)
			W.Page = page
			local left = makeFrame(page, "Left", { Size = UDim2.new(1, -(K.DETAIL_W + 12), 1, 0) })
			W.Left = left

			local slotSize = 64
			local equipWidth = maxEquipped * slotSize + (maxEquipped - 1) * 8
			local header = makeFrame(left, "Header", { Size = UDim2.new(1, 0, 0, 76) })
			W.Header = header
			W.EquippedLabel = makeText(header, "EquippedLabel", "Equipped", "Heading", 24, WHITE, {
				Position = UDim2.fromOffset(4, 0),
				Size = UDim2.new(1, -(equipWidth + 12), 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			W.PerksLabel = makeText(header, "TeamPerks", "", "Body", 18, MUTED, {
				Position = UDim2.fromOffset(4, 32),
				Size = UDim2.new(1, -(equipWidth + 12), 0, 44),
				TextWrapped = true,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			})
			Util.Create("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 18, Parent = W.PerksLabel })
			local equipRow = makeFrame(header, "EquippedSlots", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 2),
				Size = UDim2.fromOffset(equipWidth, slotSize + 4),
			})
			listLayout(equipRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
			for i = 1, maxEquipped do
				pets.EquipSlots[i] = readableSlot(CloudUI.Slot({
					Name = "Equipped" .. i,
					Size = UDim2.fromOffset(slotSize, slotSize),
					LayoutOrder = i,
					Parent = equipRow,
					Callback = function()
						local id = pets.EquipIds[i]
						if id then
							pets.Selected = id
							refreshInventory()
						end
					end,
				}))
			end

			local well = makeInset(left, "GridWell", {
				Position = UDim2.fromOffset(0, 84),
				Size = UDim2.new(1, 0, 1, -84),
			})
			W.GridWell = well
			W.Grid = CloudUI.Grid(well, UDim2.fromOffset(104, 104), 10)

			-- the empty state fits the grid's column in every shape (P5.emptyState: wrapped text, a capped button)
			local empty = P5.emptyState({
				Parent = well,
				Fill = true,
				ZIndex = 5,
				Title = "No pets yet!",
				Body = "Spin a roulette in the Shop to hatch your first winged friend.",
				ButtonName = "OpenShop",
				Callback = function()
					menuActionShop()
				end,
			})
			W.Empty, W.EmptyTitle, W.EmptyBody, W.EmptyButton = empty.Frame, empty.Title, empty.Body, empty.Button

			buildDetailCard(page)
		end

		-- the tier / hybrid chip (top-left) and the level tag (bottom-left) of a grid slot
		local function paintSlotBadges(slot, key, def)
			if not slot.TierChip then
				local chip = makeFrame(slot.Button, "TierBadge", {
					Position = UDim2.fromOffset(4, 4),
					Size = UDim2.fromOffset(30, 30),
					BackgroundTransparency = 0,
					BackgroundColor3 = WHITE,
					Visible = false,
					ZIndex = 8,
				})
				round(chip)
				stroke(chip, NAVY, 2.5, 0)
				slot.TierGradient = Util.Create("UIGradient", { Rotation = 45, Parent = chip })
				slot.TierText = makeText(chip, "Mark", "", "Button", 18, WHITE, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 9 })
				slot.TierChip = chip
				slot.LevelTag = makeText(slot.Button, "LevelTag", "", "Heading", 18, WHITE, {
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 6, 1, -2),
					Size = UDim2.fromOffset(60, 22),
					TextXAlignment = Enum.TextXAlignment.Left,
					Visible = false,
					ZIndex = 8,
				})
			end
			local tier = P2.tierOf(key, def)
			local hybrid = P2.isHybrid(key, def)
			if hybrid then
				slot.TierChip.Visible = true
				slot.TierGradient.Color = ColorSequence.new(Theme.Lighten(C2.Hybrid, 0.3), Theme.Darken(C2.Hybrid, 0.2))
				slot.TierText.Text = "H"
			elseif tier == "Rainbow" then
				slot.TierChip.Visible = true
				slot.TierGradient.Color = rainbowSequence()
				slot.TierText.Text = "R"
			elseif tier == "Golden" then
				slot.TierChip.Visible = true
				slot.TierGradient.Color = ColorSequence.new(Theme.Lighten(C2.Tier.Golden, 0.3), Theme.Darken(C2.Tier.Golden, 0.15))
				slot.TierText.Text = "G"
			else
				slot.TierChip.Visible = false
			end
			local level = P2.petLevel(key)
			local stage = P2.stage(key)
			slot.LevelTag.Visible = level > 1
			slot.LevelTag.Text = "Lv " .. level
			slot.LevelTag.Size = UDim2.fromOffset(60, 22)
			-- Phase 5: the evolution stars sit on the slot's top edge (the bottom row keeps "Lv n" and the count apart)
			if stage > 0 and not slot.EvoTag then
				slot.EvoTag = makeText(slot.Button, "EvoTag", "", "Title", 18, GOLD, {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 2),
					Size = UDim2.fromOffset(40, 22),
					ZIndex = 8,
				})
			end
			if slot.EvoTag then
				slot.EvoTag.Visible = stage > 0
				slot.EvoTag.Text = string.rep(G.Star, math.min(2, stage))
			end
			-- a pet working at home: a seedling (Garden) or muscle (training) chip beside the tier chip
			local home = P2.homeData()
			local where = nil
			if P2.job(key) then
				where = "Gym"
			elseif #P2.slotsHolding(home.Garden, key) > 0 then
				where = "Garden"
			end
			if where and not slot.WorkChip then
				local chip = makeFrame(slot.Button, "WorkBadge", {
					Size = UDim2.fromOffset(30, 30),
					BackgroundTransparency = 0,
					BackgroundColor3 = WHITE,
					ZIndex = 8,
				})
				round(chip)
				stroke(chip, NAVY, 2.5, 0)
				slot.WorkGradient = Util.Create("UIGradient", { Rotation = 90, Parent = chip })
				slot.WorkText = makeText(chip, "Mark", "", "Title", 18, WHITE, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 9 })
				slot.WorkChip = chip
			end
			if slot.WorkChip then
				slot.WorkChip.Visible = where ~= nil
				if where then
					local color = where == "Garden" and C2.Kind.Garden or PURPLE
					slot.WorkGradient.Color = ColorSequence.new(Theme.Lighten(color, 0.3), Theme.Darken(color, 0.15))
					slot.WorkText.Text = where == "Garden" and G.Seedling or G.Muscle
					slot.WorkChip.Position = UDim2.fromOffset(slot.TierChip.Visible and 36 or 4, 4)
				end
			end
			-- bug batch 2 #18: a pet with no copy free of the Garden is busy gardening: its card is dimmed under the same
			-- seedling "Gardening" badge as its Team tile (Equip then asks to take it out). Two lines: the 104 px card is
			-- too narrow for "seedling Gardening" on one line at 18 px.
			local gardening = P2.isGardening(key)
			if gardening and not slot.GardenTag then
				local tag = makeFrame(slot.Button, "GardenTag", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.52),
					Size = UDim2.new(1, -10, 0, 50),
					BackgroundTransparency = 0,
					BackgroundColor3 = Theme.Darken(C2.Kind.Garden, 0.25),
					ZIndex = 9,
				})
				corner(tag, 12)
				stroke(tag, NAVY, 2.5, 0)
				slot.GardenText = makeText(tag, "Busy", G.Seedling .. "\nGardening", "Body", 18, WHITE, {
					Size = UDim2.new(1, 0, 1, 0),
					ZIndex = 10,
				})
				slot.GardenTag = tag
			end
			if slot.GardenTag then
				slot.GardenTag.Visible = gardening
			end
			slot.SetDimmed(gardening)
		end

		local function setPills(def, key, color, elements)
			for _, pill in ipairs(pets.Pills) do
				pill:Destroy()
			end
			pets.Pills = {}
			local rarityPill = readablePill(def.Rarity, color, W.MetaRow)
			rarityPill.LayoutOrder = 1
			table.insert(pets.Pills, rarityPill)
			local tier = P2.tierOf(key, def)
			if tier ~= "Normal" then
				table.insert(pets.Pills, colorPill(W.MetaRow, "Tier_" .. tier, tier, C2.Tier[tier] or GOLD, 18, 2))
			end
			if P2.isHybrid(key, def) then
				table.insert(pets.Pills, colorPill(W.MetaRow, "Hybrid", "Hybrid", C2.Hybrid, 18, 3))
			end
			for i, element in ipairs(elements) do
				table.insert(pets.Pills, elementPill(W.MetaRow, element, 18, 3 + i))
			end
			if type(def.Role) == "string" then
				local rolePill = readablePill(def.Role, ROLE_COLORS[def.Role] or BUTTONS.Blue, W.RoleRow)
				rolePill.LayoutOrder = 1
				table.insert(pets.Pills, rolePill)
			end
		end

		-- stat chips at the pet's level: the role's own stats bright, the others dimmer
		local function setStats(def, level, petKey)
			local stats = P2.statsAt(def, level)
			local coins = P2.coinsPerSecond(petKey, def, P2.homeData())
			local key = tostring(petKey) .. "|" .. level .. "|" .. P2.formatRate(coins)
			if pets.StatKey == key then
				return
			end
			pets.StatKey = key
			for _, child in ipairs(W.StatsRow:GetChildren()) do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			W.StatsRow.Visible = stats ~= nil
			if not stats then
				return
			end
			local economy = def.Role == "Economy"
			local order = { "Income", "Power", "Health", "Speed" }
			local colors = {
				Income = C2.Cash,
				Power = Color3.fromRGB(236, 112, 96),
				Health = Color3.fromRGB(240, 120, 150),
				Speed = Color3.fromRGB(98, 172, 232),
			}
			for i, statKey in ipairs(order) do
				local value = tonumber(stats[statKey]) or 0
				local text
				if statKey == "Income" then
					text = "Coins " .. P2.formatRate(coins) .. "/s"
				elseif statKey == "Power" then
					-- Phase 5 (m17): what the pet really brings to a battle (BattleCatalog.UnitPower: its role, level,
					-- tier, evolution and training), never the raw Power 2-4 of an Economy pet
					text = "Battle power " .. commas(P5.battlePower(petKey, def, level) or math.floor(value + 0.5))
				else
					text = statKey .. " " .. commas(math.floor(value + 0.5))
				end
				local main = (statKey == "Income") == economy
				local color = main and colors[statKey] or Color3.fromRGB(88, 104, 150)
				colorPill(W.StatsRow, "Stat_" .. statKey, text, color, 18, i)
			end
		end

		local function renderDetail()
			local key = pets.Selected
			local def = key and P2.defOfKey(key) or nil
			local owned = def and State.OwnedCount(key) or 0
			if not def or owned <= 0 then
				W.DetailBody.Visible = false
				W.DetailEmpty.Visible = true
				if pets.DetailViewport then
					pets.DetailViewport.Destroy()
					pets.DetailViewport = nil
					pets.DetailPet = nil
				end
				return
			end
			W.DetailBody.Visible = true
			W.DetailEmpty.Visible = false

			local color = rarityOf(def)
			local shownStage = P2.stage(key)
			if pets.DetailPet ~= key or pets.DetailStage ~= shownStage then
				if pets.DetailViewport then
					pets.DetailViewport.Destroy()
				end
				-- (an evolved pet shows its evolved form: Low detail keeps the big Evolved II models cheap)
				pets.DetailViewport = CloudUI.PetViewport(W.ViewportHolder, def, UDim2.new(1, 0, 1, 0), {
					Spin = "spin",
					ZIndex = 2,
					Evolved = shownStage > 0 and shownStage or nil,
					Detail = shownStage > 0 and "Low" or nil,
				})
				pets.DetailPet = key
				pets.DetailStage = shownStage
				pets.StatKey = nil
			end
			local tier = P2.tierOf(key, def)
			W.Glow.BackgroundColor3 = (tier ~= "Normal" and C2.Tier[tier]) or color
			W.Name.Text = P2.displayName(key, def)
			W.Name.TextColor3 = rarityText(def)

			-- rarity, tier, hybrid, element and role pills (rebuilt only when they change)
			local elements = elementsOf(def)
			local pillKey = tostring(key) .. "|" .. tostring(def.Rarity) .. "|" .. table.concat(elements, ",") .. "|" .. tostring(def.Role)
			if pets.PillKey ~= pillKey then
				setPills(def, key, color, elements)
				pets.PillKey = pillKey
			end
			local special = type(def.Special) == "table" and def.Special or nil
			W.Special.Text = special and (G.Sparkle .. " " .. tostring(special.Name or "Special")) or ""
			W.Special.Visible = special ~= nil
			W.RoleRow.Visible = special ~= nil or type(def.Role) == "string"

			local equipped = State.EquippedCount(key)
			local text = "Owned x" .. owned
			if equipped > 0 then
				text = text .. "   " .. G.Star .. " " .. equipped .. " equipped"
			end
			W.OwnedLabel.Text = text

			-- level + XP
			local level, xp = P2.petLevel(key)
			local cap = P2.levelCap(key, def)
			local need = P2.xpToNext(level)
			W.LevelText.Text = (W.Mode == "Short") and ("Lv " .. level) or ("Lv " .. level .. " / " .. cap)
			if level >= cap then
				W.XpBar.SetFraction(1)
				W.XpBar.SetText("MAX LEVEL")
				W.XpBar.SetColor(GOLD)
			else
				W.XpBar.SetFraction(need > 0 and need < math.huge and math.min(1, xp / need) or 0)
				W.XpBar.SetText(commas(math.floor(xp)) .. " / " .. commas(need) .. " XP")
				W.XpBar.SetColor(C2.Xp)
			end
			setStats(def, level, key)

			-- where it works / trains, and its evolution
			local work = workOf(key, def)
			local job = P2.job(key)
			local stage = P2.stage(key)
			local ready = P2.canEvolve(key, def, level)
			local workText, workColor = "", Theme.Lighten(GOOD, 0.35)
			if job then
				workText = G.Muscle .. " Training " .. P2.skillName(job.Stat) .. " (" .. P2.jobLeft(job) .. " left)"
				workColor = Theme.Lighten(PURPLE, 0.35)
			elseif work and #work.Placed > 0 then
				workText = G.Seedling .. " Working in your Garden"
			end
			if ready then
				workText = (workText ~= "" and (workText .. "\n") or "") .. G.Sparkle .. " Ready to evolve!"
			end
			W.Work.Text = workText
			W.Work.TextColor3 = workColor
			W.Work.Visible = workText ~= ""

			W.Blurb.Text = def.Blurb or ""
			local mult = P2.tierMultiplier(key, def)
			local lines = {}
			if type(def.Perks) == "table" then
				local perkOrder = PetCatalog.PerkOrder or { "MaxHealth", "TokenBonus", "StaminaRegen", "CheckpointHeal" }
				for _, perkKey in ipairs(perkOrder) do
					local value = def.Perks[perkKey]
					if type(value) == "number" and value ~= 0 then
						table.insert(lines, PetCatalog.PerkLabel(perkKey, value * mult))
					end
				end
			end
			if #lines > 0 then
				W.Perks.Text = table.concat(lines, "\n")
			else
				W.Perks.Text = "No perks"
			end

			-- the evolution pill (star badge) beside the rarity
			if W.EvoPill then
				W.EvoPill:Destroy()
				W.EvoPill = nil
			end
			if stage > 0 then
				W.EvoPill = colorPill(W.MetaRow, "Evolution", string.rep(G.Star, math.min(2, stage)) .. (stage >= 2 and " Evolved II" or " Evolved"), GOLD, 18, 50)
			end

			-- buttons
			local totalEquipped = #State.Get().Equipped
			local canEquip = equipped < owned and totalEquipped < maxEquipped and job == nil
			CloudUI.SetDisabled(W.EquipBtn, not canEquip)
			-- bug batch 2 #18: every free copy is gardening -> the press asks to take one out of the garden
			W.EquipGardening = canEquip and equipped >= owned - P2.gardenCopies(key)
			CloudUI.SetDisabled(W.UnequipBtn, equipped <= 0)
			CloudUI.SetDisabled(W.FeedBtn, inMatch())
			CloudUI.SetDisabled(W.TrainBtn, inMatch())
			W.TrainBtn.Text = job and "Training" or "Train"
			W.EvolveBtn.Visible = ready ~= nil
			CloudUI.SetDisabled(W.EvolveBtn, inMatch())
			-- no EVOLVE: Train takes the whole bottom row
			W.Ready = ready ~= nil
			W.PlaceButtons()
			if work then
				local placed = #work.Placed > 0
				W.WorkBtn.Text = placed and "Leave Garden" or "Garden"
				CloudUI.SetStyle(W.WorkBtn, placed and "Pink" or "Blue")
				local full = not placed and work.Slots > 0 and P2.firstFreeSlot(work.Map, work.Slots) == nil
				CloudUI.SetDisabled(W.WorkBtn, inMatch() or (not placed and (work.Slots <= 0 or full or job ~= nil)))
				W.WorkBtn.Visible = true
			else
				W.WorkBtn.Visible = false
			end
			local status = ""
			if inMatch() then
				status = "Pets are locked during a match."
			elseif job then
				status = P2.displayName(key, def) .. " is training: it can't follow you until it's done."
			elseif work and #work.Placed == 0 and work.Slots <= 0 then
				status = "Build the Pet Garden at home to put it to work."
			elseif work and #work.Placed == 0 and P2.firstFreeSlot(work.Map, work.Slots) == nil then
				status = "Your Garden is full (" .. usedSlots(work.Map, work.Slots) .. "/" .. work.Slots .. ")."
			elseif equipped >= owned then
				status = "All your copies are equipped."
			elseif totalEquipped >= maxEquipped then
				status = "Your team is full. Unequip a pet first."
			end
			W.Status.Text = status
		end

		-- Content of a grid slot. The pet viewport (a PetBuilder model, a ViewportFrame and a Camera) is
		-- attached by fillPetSlots, a few per frame, so a big collection never builds ~30 models in the frame
		-- the Inventory opens (same idea as the odds popup). Until then a slot is its rarity tile.
		local function gridInfo(key, def, withPet)
			local info = {
				RarityColor = rarityOf(def),
				Name = P2.displayName(key, def) .. " (" .. tostring(def.Rarity) .. ")",
				Blurb = def.Blurb,
			}
			-- (an evolved copy draws its evolved form through P5.evoSlot instead of the slot's plain model)
			if withPet and P2.stage(key) < 1 then
				info.Pet = def
			end
			return info
		end

		local function fillPetSlots()
			if pets.Filling then
				return
			end
			-- one frame's share (time budget); returns true when slots are still waiting for their pet
			local function buildBatch()
				local budget = Warm.Budget()
				for _, key in ipairs(pets.Order) do
					local slot = pets.Slots[key]
					local def = P2.defOfKey(key)
					if slot and def and not pets.Ready[key] then
						if not Warm.Allows(budget) then
							return true
						end
						pets.Ready[key] = true
						slot.SetContent(gridInfo(key, def, true))
						local evolved = P5.evoSlot(slot, def, P2.stage(key))
						local n = State.OwnedCount(key)
						-- pet slots hide "x1" (needs the Pet content; an evolved slot draws its own model: hide it here)
						if evolved and n <= 1 then
							slot.SetCount(nil)
						else
							slot.SetCount(n)
						end
						budget.Count = budget.Count + 1
					end
				end
				return false
			end
			pets.Filling = true
			task.spawn(function()
				-- the frame that opens the window already builds it (and the detail card's pet): start on the next one.
				-- Stops when the window closes; the next open refreshes it and resumes with what is still missing.
				task.wait()
				while win.Shown do
					local ok, more = pcall(buildBatch)
					if not ok then
						warnOnce("fill pets", more)
						break
					end
					if not more then
						break
					end
					task.wait()
				end
				pets.Filling = false
			end)
		end

		local function refreshPetsPage()
			local keys = P2.ownedKeys()
			local ownedSet = {}
			for _, key in ipairs(keys) do
				ownedSet[key] = true
			end
			local snapshot = State.Get()

			-- keep the selection valid: prefer an equipped pet, else the rarest one
			if not (pets.Selected and ownedSet[pets.Selected]) then
				pets.Selected = nil
				for _, key in ipairs(snapshot.Equipped) do
					if ownedSet[key] then
						pets.Selected = key
						break
					end
				end
				if not pets.Selected then
					pets.Selected = keys[1]
				end
			end

			-- drop slots of pets that are gone, add slots for new ones, update the rest in place
			for key, slot in pairs(pets.Slots) do
				if not ownedSet[key] then
					slot.Destroy()
					pets.Slots[key] = nil
					pets.Ready[key] = nil
				end
			end
			pets.Order = keys
			for index, key in ipairs(keys) do
				local def = P2.defOfKey(key)
				local slot = pets.Slots[key]
				if not slot then
					slot = readableSlot(CloudUI.Slot({
						Name = "Pet_" .. key,
						Size = UDim2.fromOffset(104, 104),
						Parent = W.Grid,
						Callback = function()
							pets.Selected = key
							refreshInventory()
						end,
					}))
					pets.Slots[key] = slot
				end
				slot.Root.LayoutOrder = index
				local ready = pets.Ready[key] == true
				local owned = State.OwnedCount(key)
				slot.SetContent(gridInfo(key, def, ready))
				local evolved = P5.evoSlot(slot, def, ready and P2.stage(key) or 0)
				if owned > 1 or (ready and not evolved) then
					slot.SetCount(owned)
				else
					slot.SetCount(nil) -- a tile without its pet yet would show "x1"
				end
				if State.IsEquipped(key) then
					slot.SetMarker(G.Star, GOLD)
				else
					slot.SetMarker(nil)
				end
				slot.SetSelected(key == pets.Selected)
				paintSlotBadges(slot, key, def)
			end
			W.Grid.Visible = #keys > 0
			W.Empty.Visible = #keys == 0
			if W.IsEmpty ~= (#keys == 0) then
				-- the empty state came / went: on a landscape phone it takes / gives back the detail card's room
				W.IsEmpty = #keys == 0
				local L = W.LastLayout
				if L then
					safe("pets layout", P5.petsLayout, W, L[1], L[2], L[3], L[4], L[5])
				end
			end
			if #keys == 0 then
				local loaded = (State.IsLoaded == nil) or State.IsLoaded()
				if loaded then
					W.EmptyTitle.Text = "No pets yet!"
					W.EmptyBody.Text = "Spin a roulette in the Shop to hatch your first winged friend."
				else
					W.EmptyTitle.Text = "Loading..."
					W.EmptyBody.Text = "Fetching your pets from the clouds."
				end
				W.EmptyButton.Visible = loaded
			end

			-- header: equipped count, team perks, equipped mini slots
			local equipped = snapshot.Equipped
			W.EquippedLabel.Text = string.format("Equipped %d/%d", #equipped, maxEquipped)
			for i = 1, maxEquipped do
				local slot = pets.EquipSlots[i]
				local key = equipped[i]
				local def = key and P2.defOfKey(key) or nil
				if slot then
					if def then
						pets.EquipIds[i] = key
						slot.SetContent({ Pet = def, RarityColor = rarityOf(def), Name = P2.displayName(key, def), Blurb = def.Blurb })
						slot.SetSelected(key == pets.Selected)
					else
						pets.EquipIds[i] = nil
						slot.SetContent(nil)
						slot.SetSelected(false)
					end
				end
			end
			-- short perk names keep the line readable (18 design px) beside the equipped slots
			local perkParts = {}
			local order = PetCatalog.PerkOrder or { "MaxHealth", "TokenBonus", "StaminaRegen", "CheckpointHeal" }
			local short = { MaxHealth = "Health", TokenBonus = "Tokens", StaminaRegen = "Stamina", CheckpointHeal = "Heal" }
			for _, perkKey in ipairs(order) do
				local value = snapshot.Perks[perkKey]
				if type(value) == "number" and value > 0 then
					local label = PetCatalog.PerkLabel(perkKey, value)
					local name = PetCatalog.PerkNames and PetCatalog.PerkNames[perkKey]
					if name and short[perkKey] then
						label = label:gsub(name:gsub("%p", "%%%0"), short[perkKey])
					end
					table.insert(perkParts, label)
				end
			end
			if #perkParts > 0 then
				W.PerksLabel.Text = "Team: " .. table.concat(perkParts, "  " .. G.Bullet .. "  ")
			else
				W.PerksLabel.Text = "Equip pets to gain perks."
			end

			fillPetSlots() -- last: the first batch of grid viewports is built right here, the rest follow per frame
		end

		------------------------------------------------------------------
		-- Items page
		------------------------------------------------------------------
		local function buildItemsPage(page)
			local list = scroller(page, "ItemList", { Size = UDim2.new(1, 0, 1, 0) })
			pad(list, 2, 2, 14, 8)
			listLayout(list, Enum.FillDirection.Vertical, 10)
			for index, def in ipairs(itemList()) do
				local row = makeInset(list, "Row_" .. def.Id, {
					Size = UDim2.new(1, 0, 0, 124),
					LayoutOrder = index,
				})
				local slot = readableSlot(CloudUI.Slot({
					Name = "Item_" .. def.Id,
					Size = UDim2.fromOffset(96, 96),
					Position = UDim2.fromOffset(14, 14),
					Hotkey = tostring(index),
					Parent = row,
				}))
				slot.SetContent({
					Glyph = def.Glyph,
					Color = def.Color,
					RarityColor = CloudUI.RarityColor(def.Rarity),
					Name = def.Name,
					Blurb = def.Blurb,
				})
				local nameLabel = makeText(row, "Name", def.Name, "Title", 26, Theme.Lighten(def.Color, 0.35), {
					Position = UDim2.fromOffset(126, 10),
					Size = UDim2.new(1, -350, 0, 32),
					TextXAlignment = Enum.TextXAlignment.Left,
				})
				local price = makeText(row, "Price", cloudAmount(def.Price) .. " each", "Heading", 20, Colors.Token, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -206, 0, 12),
					Size = UDim2.fromOffset(150, 28),
					TextXAlignment = Enum.TextXAlignment.Right,
				})
				local owned = makeText(row, "Owned", "", "Heading", 19, WHITE, {
					Position = UDim2.fromOffset(126, 44),
					Size = UDim2.new(1, -330, 0, 24),
					TextXAlignment = Enum.TextXAlignment.Left,
				})
				local blurb = makeText(row, "Blurb", def.Blurb or "", "Body", 18, MUTED, {
					Position = UDim2.fromOffset(126, 70),
					Size = UDim2.new(1, -330, 0, 48),
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				})
				local more = CloudUI.Button({
					Name = "GetMore",
					Text = "Get more",
					Style = "Blue",
					Size = UDim2.fromOffset(176, 56),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -14, 0.5, 0),
					TextSize = 22,
					Callback = gotoShopItems,
					Parent = row,
				})
				itemRows[def.Id] = {
					Slot = slot,
					Owned = owned,
					Def = def,
					Parts = { Row = row, Name = nameLabel, Price = price, Owned = owned, Blurb = blurb, More = more },
				}
			end

			-- the fourth hotbar key is reserved for later
			local locked = makeInset(list, "LockedRow", {
				Size = UDim2.new(1, 0, 0, 58),
				LayoutOrder = 50,
			})
			makeText(locked, "Text", G.Lock .. "  Slot " .. (#itemList() + 1) .. "   More items are coming soon.", "Heading", 19, MUTED, {
				Position = UDim2.fromOffset(16, 0),
				Size = UDim2.new(1, -32, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
			})
			makeText(list, "Tip", "Items only work during a match: press 1-" .. #itemList() .. " or tap the hotbar.", "Body", 18, MUTED, {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				LayoutOrder = 60,
			})
		end

		local function refreshItemsPage()
			local maxCarry = Config.Items.MaxCarry
			for id, row in pairs(itemRows) do
				local count = State.ItemCount(id)
				row.Slot.SetCount(count)
				row.Slot.SetDimmed(count <= 0)
				row.Owned.Text = string.format("In bag: %d / %d", count, maxCarry)
			end
		end

		function refreshInventory()
			refreshPetsPage()
			renderDetail()
			refreshItemsPage()
		end

		tabs.Add("Pets", buildPetsPage)
		tabs.Add("Items", buildItemsPage)

		win.Refresh = refreshInventory
		win.OnOpen = function(args)
			local tab = normalizeTab("Inventory", args.Tab)
			if tab then
				tabs.Select(tab)
			end
			if type(args.Key) == "string" and State.OwnedCount(args.Key) > 0 then
				pets.Selected = args.Key
			end
			if args.Action == "Evolve" and type(args.Key) == "string" then
				-- the floating card's EVOLVE! pill: the Pets panel on that pet, with the EVOLVE confirm on top
				tabs.Select("Pets")
				local key = args.Key
				task.defer(function()
					if win.Shown and State.OwnedCount(key) > 0 then
						refreshInventory()
						careOpen("Evolve", key)
					end
				end)
			end
		end

		win.OnLayout = function(w, h, narrow, short, tall)
			safe("pets layout", P5.petsLayout, W, w, h, narrow, short, tall)
			-- item rows: narrow (portrait) rows stack the text and put the button under it
			for _, row in pairs(itemRows) do
				local P = row.Parts
				if tall then
					P.Row.Size = UDim2.new(1, 0, 0, 188)
					P.Name.Size = UDim2.new(1, -140, 0, 32)
					P.Price.Visible = false
					P.Owned.Size = UDim2.new(1, -140, 0, 24)
					P.Blurb.Size = UDim2.new(1, -140, 0, 64)
					P.More.AnchorPoint = Vector2.new(1, 1)
					P.More.Position = UDim2.new(1, -14, 1, -12)
				else
					P.Row.Size = UDim2.new(1, 0, 0, 124)
					P.Name.Size = UDim2.new(1, -350, 0, 32)
					P.Price.Visible = true
					P.Owned.Size = UDim2.new(1, -330, 0, 24)
					P.Blurb.Size = UDim2.new(1, -330, 0, 48)
					P.More.AnchorPoint = Vector2.new(1, 0.5)
					P.More.Position = UDim2.new(1, -14, 0.5, 0)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Odds popup (opened from a roulette card; pets grouped by rarity with their exact chances)
----------------------------------------------------------------------
function closeOdds()
	Odds.Token = Odds.Token + 1
	for _, slot in ipairs(Odds.Slots) do
		pcall(slot.Destroy)
	end
	Odds.Slots = {}
	if Odds.Gui then
		Odds.Gui:Destroy()
		Odds.Gui = nil
	end
	Odds.Holder = nil
	Odds.Fit = nil
	syncBackBinding()
end

function openOdds(rouletteId)
	local roulette = findRoulette(rouletteId)
	if not roulette or not gui then
		return
	end
	closeOdds()
	Odds.Token = Odds.Token + 1
	local mine = Odds.Token

	local root = makeFrame(gui, "OddsPopup", { Size = UDim2.new(1, 0, 1, 0), ZIndex = 8 })
	Odds.Gui = root
	syncBackBinding()
	-- (Phase 5: no dimming backdrop; the X, Esc / B or another window close it)
	local box = confirmBox(K.WIN.Odds[1], K.WIN.Odds[2], K.WIN.Odds[3], K.WIN.Odds[4])
	local holder = makeFrame(root, "Holder", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(box.x, box.y),
		Size = UDim2.fromOffset(box.w, box.h),
		ZIndex = 2,
	})
	Odds.Holder = holder
	Odds.Fit = Util.Create("UIScale", { Name = "Fit", Scale = box.scale, Parent = holder })
	local panel = CloudUI.Panel({
		Name = "OddsPanel",
		Title = roulette.DisplayName .. " Odds",
		Closable = true,
		Accent = roulette.Color,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		OnClose = function()
			closeOdds()
		end,
		Parent = holder,
	})
	local pop = Util.Create("UIScale", { Name = "Pop", Scale = 0.88, Parent = panel.Root })
	tween(pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local scroll = scroller(panel.Content, "OddsList", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
	})
	pad(scroll, 6, 4, 14, 8)
	listLayout(scroll, Enum.FillDirection.Vertical, 10)
	makeText(scroll, "Note", "Chance per spin. Pets of the same rarity share that rarity's chance equally.", "Body", 18, MUTED, {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 0,
	})

	-- group the exact odds by rarity
	local groups = {}
	local byRarity = {}
	for _, entry in ipairs(oddsOf(rouletteId)) do
		local group = byRarity[entry.Rarity]
		if not group then
			group = { Rarity = entry.Rarity, Total = 0, Entries = {} }
			byRarity[entry.Rarity] = group
			table.insert(groups, group)
		end
		group.Total = group.Total + entry.Chance
		table.insert(group.Entries, entry)
	end
	table.sort(groups, function(a, b)
		return rarityOrder(a.Rarity) > rarityOrder(b.Rarity)
	end)
	local hasElements = false
	for _, def in ipairs(PetCatalog.Pets or {}) do
		if #elementsOf(def) > 0 then
			hasElements = true
			break
		end
	end
	local cellH = hasElements and 156 or 128

	-- built under the per-frame time budget (Low detail tiles) so opening the popup never hitches
	task.spawn(function()
		local budget = Warm.Budget()
		for index, group in ipairs(groups) do
			if Odds.Token ~= mine then
				return
			end
			local color = CloudUI.RarityColor(group.Rarity)
			local header = makeFrame(scroll, "Header_" .. group.Rarity, {
				Size = UDim2.new(1, -8, 0, 44),
				BackgroundTransparency = 0,
				BackgroundColor3 = Theme.Darken(color, 0.35),
				LayoutOrder = index * 2 - 1,
			})
			corner(header, 10)
			stroke(header, NAVY, 3, 0)
			makeText(header, "Rarity", group.Rarity, "Title", 24, rarityText({ Rarity = group.Rarity }), {
				Position = UDim2.fromOffset(14, 0),
				Size = UDim2.new(0.5, 0, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			makeText(header, "Chance", percentText(group.Total) .. "  total", "Heading", 19, WHITE, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -14, 0, 0),
				Size = UDim2.new(0.5, 0, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
			})

			local cells = makeFrame(scroll, "Cells_" .. group.Rarity, {
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = index * 2,
			})
			Util.Create("UIGridLayout", {
				CellSize = UDim2.fromOffset(110, cellH),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = cells,
			})
			for cellIndex, entry in ipairs(group.Entries) do
				if Odds.Token ~= mine then
					return
				end
				if not Warm.Allows(budget) then
					task.wait()
					if Odds.Token ~= mine then
						return
					end
					budget = Warm.Budget()
				end
				local def = PetCatalog.Get(entry.PetId)
				local cell = makeFrame(cells, "Cell_" .. tostring(entry.PetId), { LayoutOrder = cellIndex })
				if def then
					local slot = readableSlot(CloudUI.Slot({
						Name = "OddsPet",
						Size = UDim2.fromOffset(88, 88),
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 2),
						Parent = cell,
					}))
					slot.SetContent({ Pet = def, Detail = K.ODDS_DETAIL, RarityColor = color, Name = def.Name, Blurb = def.Blurb })
					table.insert(Odds.Slots, slot)
					local elements = elementsOf(def)
					if #elements > 0 then
						local row = makeFrame(cell, "Elements", {
							AnchorPoint = Vector2.new(0.5, 1),
							Position = UDim2.new(0.5, 0, 1, -30),
							Size = UDim2.new(1, 0, 0, 24),
						})
						listLayout(row, Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
						for i, element in ipairs(elements) do
							elementPill(row, element, 18, i)
						end
					end
				end
				makeText(cell, "Percent", percentText(entry.Chance), "Heading", 19, WHITE, {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -2),
					Size = UDim2.new(1, 0, 0, 24),
				})
				budget.Count = budget.Count + 1
			end
		end
	end)
end

----------------------------------------------------------------------
-- Shop window: tabs Roulettes + Items
----------------------------------------------------------------------
local function bestRarityOf(roulette)
	local bestId, bestOrder = nil, 0
	for _, r in ipairs(Config.Rarities) do
		local weight = roulette.Odds[r.Id]
		if type(weight) == "number" and weight > 0 and r.Order > bestOrder then
			bestId, bestOrder = r.Id, r.Order
		end
	end
	return bestId
end

local function buildRouletteCard(shop, parent, roulette, index)
	local color = roulette.Color
	local card = makeFrame(parent, "Roulette_" .. roulette.Id, {
		Size = UDim2.new(0.25, -9, 1, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		LayoutOrder = index,
	})
	corner(card, 16)
	local cardStroke = stroke(card, NAVY, 4, 0)
	Theme.Gradient(card, Theme.Darken(color, 0.28), Theme.Darken(color, 0.7), 90)

	-- name banner
	local banner = makeFrame(card, "Banner", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, -18, 0, 54),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Lighten(color, 0.1),
	})
	corner(banner, 12)
	stroke(banner, NAVY, 3, 0)
	local bannerText = makeText(banner, "Name", roulette.DisplayName, "Title", 24, WHITE, {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, 0),
		TextScaled = true,
		TextWrapped = true,
		TextStrokeColor3 = Theme.Darken(color, 0.65),
	})
	Util.Create("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 18, Parent = bannerText })

	-- the roulette "machine": glossy dome on a base
	local base = makeFrame(card, "Base", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 176),
		Size = UDim2.fromOffset(150, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Darken(color, 0.55),
	})
	corner(base, 9)
	stroke(base, NAVY, 3, 0)
	local dome = makeFrame(card, "Dome", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(120, 120),
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
	})
	round(dome)
	stroke(dome, NAVY, 4, 0)
	Theme.Gradient(dome, Theme.Lighten(color, 0.5), Theme.Darken(color, 0.08), 90)
	local shine = makeFrame(dome, "Shine", {
		Position = UDim2.fromScale(0.16, 0.1),
		Size = UDim2.fromScale(0.36, 0.2),
		BackgroundTransparency = 0.6,
		BackgroundColor3 = WHITE,
		Rotation = -28,
	})
	round(shine)
	local mark = makeText(dome, "Mark", "?", "Title", 64, WHITE, {
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 3,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Theme.Darken(color, 0.65),
	})
	table.insert(
		shop.Bobs,
		TweenService:Create(
			mark,
			TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.new(0, 0, 0, -7) }
		)
	)

	local price = makeText(card, "Price", cloudAmount(roulette.Price), "Display", 34, Colors.Token, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.new(1, -12, 0, 40),
	})
	local best = bestRarityOf(roulette)
	local bestLabel = nil
	if best then
		bestLabel = makeText(card, "Best", "Up to " .. best, "Heading", 19, rarityText({ Rarity = best }), {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 242),
			Size = UDim2.new(1, -12, 0, 24),
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 19, MinTextSize = 18, Parent = bestLabel })
	end
	local dots = makeFrame(card, "RarityDots", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 272),
		Size = UDim2.new(1, -12, 0, 18),
	})
	listLayout(dots, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for _, r in ipairs(Config.Rarities) do
		local weight = roulette.Odds[r.Id]
		if type(weight) == "number" and weight > 0 then
			local dot = makeFrame(dots, "Dot_" .. r.Id, {
				Size = UDim2.fromOffset(16, 16),
				BackgroundTransparency = 0,
				BackgroundColor3 = r.Color,
				LayoutOrder = r.Order,
			})
			round(dot)
			stroke(dot, NAVY, 2, 0)
		end
	end

	local oddsButton = CloudUI.Button({
		Name = "Odds",
		Text = "Odds",
		Style = "Blue",
		Size = UDim2.fromOffset(136, 46),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 298),
		TextSize = 21,
		Callback = function()
			openOdds(roulette.Id)
		end,
		Parent = card,
	})
	local spinButton = CloudUI.Button({
		Name = "Spin",
		Text = "Spin",
		Style = "Green",
		Size = UDim2.new(1, -36, 0, 62),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 352),
		TextSize = 30,
		Callback = function()
			requestSpin(roulette.Id)
		end,
		Parent = card,
	})
	Util.Create("UISizeConstraint", { MaxSize = Vector2.new(190, 62), Parent = spinButton })
	local hint = makeText(card, "Hint", "", "Heading", 18, MUTED, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 420),
		Size = UDim2.new(1, -20, 0, 48),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	Util.Create("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 18, Parent = hint })
	return {
		Roulette = roulette,
		Root = card,
		Stroke = cardStroke,
		Spin = spinButton,
		Hint = hint,
		Parts = {
			Banner = banner,
			Base = base,
			Dome = dome,
			Mark = mark,
			Price = price,
			Best = bestLabel,
			Dots = dots,
			Odds = oddsButton,
			Spin = spinButton,
			Hint = hint,
		},
	}
end

-- Sets AnchorPoint / Position / Size (and the optional text alignment) of one card part.
local function place(inst, anchorX, anchorY, position, size, align)
	if not inst then
		return
	end
	inst.AnchorPoint = Vector2.new(anchorX, anchorY)
	inst.Position = position
	inst.Size = size
	if align and (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
		inst.TextXAlignment = align
	end
end

-- Roulette card: the tall machine card, or a compact one (short windows: landscape phones) that keeps the
-- Spin button in view without scrolling.
local function layoutRouletteCard(card, compact)
	local P = card.Parts
	local left, centre = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center
	if compact then
		place(P.Banner, 0.5, 0, UDim2.new(0.5, 0, 0, 8), UDim2.new(1, -16, 0, 42))
		place(P.Dome, 0, 0, UDim2.fromOffset(12, 54), UDim2.fromOffset(66, 66))
		place(P.Base, 0, 0, UDim2.fromOffset(6, 110), UDim2.fromOffset(78, 12))
		place(P.Price, 0, 0, UDim2.fromOffset(88, 56), UDim2.new(1, -96, 0, 36), left)
		place(P.Best, 0, 0, UDim2.fromOffset(88, 94), UDim2.new(1, -96, 0, 22), left)
		place(P.Odds, 0, 0, UDim2.fromOffset(10, 130), UDim2.fromOffset(92, 48))
		place(P.Spin, 1, 0, UDim2.new(1, -10, 0, 130), UDim2.new(1, -122, 0, 48))
		place(P.Hint, 0.5, 0, UDim2.new(0.5, 0, 0, 182), UDim2.new(1, -16, 0, 30))
		P.Hint.TextScaled = true -- one or two short lines must fit the compact card
		P.Mark.TextSize = 40
		-- the narrow compact card names the best rarity alone ("Legendary"), readable at 18 design px
		local best = card.Roulette and bestRarityOf(card.Roulette)
		if P.Best and best then
			P.Best.Text = best
		end
	else
		place(P.Banner, 0.5, 0, UDim2.new(0.5, 0, 0, 10), UDim2.new(1, -18, 0, 54))
		place(P.Dome, 0.5, 0, UDim2.new(0.5, 0, 0, 72), UDim2.fromOffset(120, 120))
		place(P.Base, 0.5, 0, UDim2.new(0.5, 0, 0, 176), UDim2.fromOffset(150, 18))
		place(P.Price, 0.5, 0, UDim2.new(0.5, 0, 0, 200), UDim2.new(1, -12, 0, 40), centre)
		place(P.Best, 0.5, 0, UDim2.new(0.5, 0, 0, 242), UDim2.new(1, -12, 0, 24), centre)
		place(P.Odds, 0.5, 0, UDim2.new(0.5, 0, 0, 298), UDim2.fromOffset(136, 46))
		place(P.Spin, 0.5, 0, UDim2.new(0.5, 0, 0, 352), UDim2.new(1, -36, 0, 62))
		place(P.Hint, 0.5, 0, UDim2.new(0.5, 0, 0, 420), UDim2.new(1, -20, 0, 48))
		P.Hint.TextScaled = false
		P.Mark.TextSize = 64
		local best = card.Roulette and bestRarityOf(card.Roulette)
		if P.Best and best then
			P.Best.Text = "Up to " .. best
		end
	end
	P.Dots.Visible = not compact
end

local function buildItemCard(parent, def, index, count)
	local card = makeFrame(parent, "Item_" .. def.Id, {
		Size = UDim2.new(1 / count, -8, 1, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		LayoutOrder = index,
	})
	corner(card, 16)
	stroke(card, NAVY, 4, 0)
	Theme.Gradient(card, Theme.Darken(def.Color, 0.28), Theme.Darken(def.Color, 0.7), 90)

	local slot = readableSlot(CloudUI.Slot({
		Name = "ItemSlot",
		Size = UDim2.fromOffset(104, 104),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Hotkey = tostring(index),
		Parent = card,
	}))
	slot.SetContent({
		Glyph = def.Glyph,
		Color = def.Color,
		RarityColor = CloudUI.RarityColor(def.Rarity),
		Name = def.Name,
		Blurb = def.Blurb,
	})
	local nameLabel = makeText(card, "Name", def.Name, "Title", 26, Theme.Lighten(def.Color, 0.4), {
		Position = UDim2.fromOffset(0, 128),
		Size = UDim2.new(1, 0, 0, 32),
	})
	local blurb = makeText(card, "Blurb", def.Blurb or "", "Body", 18, WHITE, {
		Position = UDim2.fromOffset(16, 164),
		Size = UDim2.new(1, -32, 0, 70),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local owned = makeText(card, "Owned", "", "Heading", 19, MUTED, {
		Position = UDim2.fromOffset(0, 238),
		Size = UDim2.new(1, 0, 0, 24),
	})
	local price = makeText(card, "Price", cloudAmount(def.Price), "Display", 32, Colors.Token, {
		Position = UDim2.fromOffset(0, 264),
		Size = UDim2.new(1, 0, 0, 38),
	})
	local buy = CloudUI.Button({
		Name = "Buy",
		Text = "Buy +1",
		Style = "Green",
		Size = UDim2.new(1, -40, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 310),
		TextSize = 26,
		Callback = function()
			if inMatch() then
				showHint("The shop is closed during a match.", "info")
				return
			end
			fire("BuyItem", def.Id, 1)
		end,
		Parent = card,
	})
	Util.Create("UISizeConstraint", { MaxSize = Vector2.new(210, 58), Parent = buy })
	local hint = makeText(card, "Hint", "", "Heading", 18, MUTED, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 376),
		Size = UDim2.new(1, -20, 0, 48),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	return {
		Def = def,
		Root = card,
		Slot = slot,
		Owned = owned,
		Buy = buy,
		Hint = hint,
		Parts = { Slot = slot.Root, Name = nameLabel, Blurb = blurb, Owned = owned, Price = price, Buy = buy, Hint = hint },
	}
end

-- Item card: tall, or compact for short windows (the Buy button stays in view).
local function layoutItemCard(card, compact)
	local P = card.Parts
	local left, centre = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center
	if compact then
		place(P.Slot, 0, 0, UDim2.fromOffset(12, 12), UDim2.fromOffset(78, 78))
		place(P.Name, 0, 0, UDim2.fromOffset(100, 10), UDim2.new(1, -108, 0, 30), left)
		place(P.Owned, 0, 0, UDim2.fromOffset(100, 42), UDim2.new(1, -108, 0, 22), left)
		place(P.Price, 0, 0, UDim2.fromOffset(100, 64), UDim2.new(1, -108, 0, 30), left)
		place(P.Buy, 0.5, 0, UDim2.new(0.5, 0, 0, 102), UDim2.new(1, -24, 0, 50))
		place(P.Hint, 0.5, 0, UDim2.new(0.5, 0, 0, 158), UDim2.new(1, -16, 0, 48))
	else
		place(P.Slot, 0.5, 0, UDim2.new(0.5, 0, 0, 16), UDim2.fromOffset(104, 104))
		place(P.Name, 0, 0, UDim2.fromOffset(0, 128), UDim2.new(1, 0, 0, 32), centre)
		place(P.Owned, 0, 0, UDim2.fromOffset(0, 238), UDim2.new(1, 0, 0, 24), centre)
		place(P.Price, 0, 0, UDim2.fromOffset(0, 264), UDim2.new(1, 0, 0, 38), centre)
		place(P.Buy, 0.5, 0, UDim2.new(0.5, 0, 0, 310), UDim2.new(1, -40, 0, 58))
		place(P.Hint, 0.5, 0, UDim2.new(0.5, 0, 0, 376), UDim2.new(1, -20, 0, 48))
	end
	P.Blurb.Visible = not compact
end

local function buildShop(win)
	local content = win.Panel.Content
	local shop = { Cards = {}, ItemCards = {}, Bobs = {} }
	local W = {}

	local tabs = CloudUI.Tabs({
		Name = "ShopTabs",
		Parent = content,
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 1, -20),
		BarHeight = 50,
		TextSize = 22,
		OnSelect = function(name)
			win.Tab = name
			updateMenuActive()
			if win.Refresh and win.Built then
				safe("shop tab", win.Refresh)
			end
		end,
	})
	win.Tabs = tabs

	-- token balance (Gems on the Gems tab), right of the tab strip
	local balance = makeFrame(content, "Balance", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(230, 44),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.05,
		ZIndex = 8,
	})
	round(balance)
	stroke(balance, NAVY, 3, 0)
	W.Balance = makeText(balance, "Amount", "", "Display", 26, Colors.Token, {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, 0),
		TextScaled = true,
		ZIndex = 9,
	})
	Util.Create("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 18, Parent = W.Balance })

	local function buildRoulettePage(page)
		local scroll = scroller(page, "Cards", { Size = UDim2.new(1, 0, 1, 0) })
		pad(scroll, 2, 2, 12, 6)
		local row = makeFrame(scroll, "Row", { Size = UDim2.new(1, 0, 0, K.CARD_H) })
		W.RouletteRow = row
		W.RouletteLayout = listLayout(row, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
		for index, roulette in ipairs(Config.Roulettes) do
			shop.Cards[roulette.Id] = buildRouletteCard(shop, row, roulette, index)
		end
	end

	local function refreshRouletteCards()
		local tokens = State.Tokens()
		local match = inMatch()
		for _, card in pairs(shop.Cards) do
			local short = card.Roulette.Price - tokens
			local label, hint, disabled = "Spin", "Hatches a random winged pet.", false
			local hintColor = MUTED
			if match then
				disabled = true
				hint = "The shop is closed during matches."
			elseif Spin.Waiting then
				disabled = true
				label = "..."
				hint = "Spinning up..."
			elseif Spin.Stage then
				disabled = true
				hint = ""
			elseif short > 0 then
				disabled = true
				hint = "Need " .. commas(short) .. " " .. G.Cloud .. " more"
				hintColor = Theme.Lighten(BAD, 0.35)
			end
			card.Spin.Text = label
			CloudUI.SetDisabled(card.Spin, disabled)
			card.Hint.Text = hint
			card.Hint.TextColor3 = hintColor
		end
	end

	local function buildItemsPage(page)
		local scroll = scroller(page, "Cards", { Size = UDim2.new(1, 0, 1, 0) })
		pad(scroll, 2, 2, 12, 6)
		listLayout(scroll, Enum.FillDirection.Vertical, 10)
		local list = itemList()
		local row = makeFrame(scroll, "Row", { Size = UDim2.new(1, 0, 0, K.ITEM_CARD_H), LayoutOrder = 1 })
		W.ItemRow = row
		W.ItemLayout = listLayout(row, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
		for index, def in ipairs(list) do
			shop.ItemCards[def.Id] = buildItemCard(row, def, index, math.max(3, #list))
		end
		makeText(scroll, "Tip", "Items only work during a match. Use them from the hotbar with keys 1-" .. #list .. " or by tapping.", "Body", 18, MUTED, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = 2,
		})
	end

	local function refreshItemCards()
		local tokens = State.Tokens()
		local match = inMatch()
		local maxCarry = Config.Items.MaxCarry
		for id, card in pairs(shop.ItemCards) do
			local count = State.ItemCount(id)
			card.Owned.Text = string.format("In bag: %d / %d", count, maxCarry)
			card.Slot.SetCount(count)
			card.Slot.SetDimmed(count <= 0)
			local label, hint, disabled = "Buy +1", "", false
			local hintColor = MUTED
			if match then
				disabled = true
				hint = "The shop is closed during matches."
			elseif count >= maxCarry then
				disabled = true
				label = "Full"
				hint = "You carry the maximum already."
			elseif tokens < card.Def.Price then
				disabled = true
				hint = "Need " .. commas(card.Def.Price - tokens) .. " " .. G.Cloud .. " more"
				hintColor = Theme.Lighten(BAD, 0.35)
			end
			card.Buy.Text = label
			CloudUI.SetDisabled(card.Buy, disabled)
			card.Hint.Text = hint
			card.Hint.TextColor3 = hintColor
		end
	end

	------------------------------------------------------------------
	-- Gems page (Phase 2): gem packs (developer products), the Secret roulette, roulettes priced in Gems
	------------------------------------------------------------------
	shop.GemCards = {} -- rouletteId -> { Roulette, Root, Stroke, Spin, Odds, Hint, Price, Parts }
	shop.Packs = {} -- { Product, Root, Price, Buy }
	local G2 = {} -- widgets of the Gems page

	local function createdProducts()
		local out = {}
		local gems = Config.Gems
		for index, product in ipairs(type(gems) == "table" and gems.Products or {}) do
			local id = type(product) == "table" and tonumber(product.Id) or nil
			if id and id > 0 and tonumber(product.Gems) then
				out[#out + 1] = { Index = index, Id = math.floor(id), Gems = math.floor(product.Gems), Name = tostring(product.Name or "Gems") }
			end
		end
		return out
	end

	-- the Robux price of a developer product (MarketplaceService:GetProductInfo, asked once, in the background)
	local function askPrice(productId)
		if Gems.PriceAsked[productId] then
			return
		end
		Gems.PriceAsked[productId] = true
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and tonumber(info.PriceInRobux) then
				Gems.Prices[productId] = math.floor(tonumber(info.PriceInRobux))
				refreshWindow(windows.Shop)
			end
		end)
	end

	local function buyPack(product)
		if inMatch() then
			showHint("The shop is closed during a match.", "info")
			return
		end
		local now = os.clock()
		if Gems.LastPrompt and now - Gems.LastPrompt < 1 then
			return
		end
		Gems.LastPrompt = now
		local ok = pcall(function()
			MarketplaceService:PromptProductPurchase(LocalPlayer, product.Id)
		end)
		if not ok then
			showHint("The Robux store did not open. Try again in a moment.", "bad")
		end
	end

	local function sectionTitle(parent, name, text, order)
		local header = makeFrame(parent, name, {
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = order,
		})
		makeText(header, "Title", text, "Title", 26, WHITE, {
			Position = UDim2.fromOffset(4, 0),
			Size = UDim2.new(1, -8, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		return header
	end

	local function gemDome(parent, color, size)
		local dome = makeFrame(parent, "Dome", {
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
		})
		round(dome)
		stroke(dome, NAVY, 3, 0)
		Theme.Gradient(dome, Theme.Lighten(color, 0.5), Theme.Darken(color, 0.1), 90)
		local shine = makeFrame(dome, "Shine", {
			Position = UDim2.fromScale(0.16, 0.1),
			Size = UDim2.fromScale(0.36, 0.2),
			BackgroundTransparency = 0.6,
			BackgroundColor3 = WHITE,
			Rotation = -28,
		})
		round(shine)
		return dome
	end

	-- a roulette priced in Gems: the Secret one (big storm card) or a token roulette (row)
	local function buildGemRoulette(parent, roulette, order, big)
		local color = roulette.Color or C2.Secret
		local card = makeFrame(parent, "GemRoulette_" .. roulette.Id, {
			Size = UDim2.new(1, 0, 0, big and 214 or K.GEM_ROW_H),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0,
			LayoutOrder = order,
		})
		corner(card, 16)
		local cardStroke = stroke(card, big and Color3.fromRGB(63, 200, 255) or NAVY, big and 4 or 3, 0)
		if big then
			Theme.Gradient(card, Color3.fromRGB(58, 70, 140), Color3.fromRGB(20, 24, 56), 90)
		else
			Theme.Gradient(card, Theme.Darken(color, 0.3), Theme.Darken(color, 0.68), 90)
		end
		local P = {}
		local domeSize = big and 116 or 80
		P.Dome = gemDome(card, color, domeSize)
		P.Dome.AnchorPoint = Vector2.new(0, 0.5)
		P.Dome.Position = UDim2.new(0, 14, 0.5, 0)
		P.Mark = makeText(P.Dome, "Mark", big and G.Storm or "?", "Title", big and 56 or 40, WHITE, {
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 3,
		})
		local textX = domeSize + 30
		P.Name = makeText(card, "Name", roulette.DisplayName or roulette.Id, "Title", big and 30 or 24, WHITE, {
			Position = UDim2.fromOffset(textX, big and 12 or 10),
			Size = UDim2.new(1, -(textX + 330), 0, big and 38 or 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = big and 30 or 24, MinTextSize = 18, Parent = P.Name })
		local blurbText
		if big then
			blurbText = "The only way to summon Secret pets like Stormfang!"
		else
			local best = bestRarityOf(roulette)
			blurbText = best and ("Up to " .. best .. ", the same odds as with Cloud Tokens") or "The same odds as with Cloud Tokens"
		end
		P.Blurb = makeText(card, "Blurb", blurbText, "Body", 19, MUTED, {
			Position = UDim2.fromOffset(textX, big and 52 or 42),
			Size = UDim2.new(1, -(textX + 330), 0, big and 50 or 26),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		-- the rarity chances (always shown), as coloured chips
		P.Chances = makeFrame(card, "Chances", {
			Position = UDim2.fromOffset(textX, big and 106 or 72),
			Size = UDim2.new(1, -(textX + 330), 0, 30),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
		local chanceLayout = listLayout(P.Chances, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		chanceLayout.Wraps = true
		local total = 0
		for _, w in pairs(roulette.Odds or {}) do
			total = total + (tonumber(w) or 0)
		end
		local chipOrder = 0
		for _, r in ipairs(Config.Rarities) do
			local w = tonumber((roulette.Odds or {})[r.Id])
			if w and w > 0 and total > 0 and (big or rarityOrder(r.Id) >= 3) then
				chipOrder = chipOrder + 1
				local chipColor = r.Id == "Secret" and C2.Hybrid or r.Color
				colorPill(P.Chances, "Chance_" .. r.Id, r.Id .. " " .. percentText(w / total), chipColor, 18, chipOrder)
			end
		end
		-- price + buttons (right)
		P.Right = makeFrame(card, "Buy", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(310, big and 170 or 96),
		})
		P.Price = makeText(P.Right, "Price", P2.gemAmount(gemPriceOf(roulette.Id) or 0), "Display", big and 32 or 28, Theme.Lighten(C2.Gem, 0.2), {
			Size = UDim2.new(1, 0, 0, big and 40 or 34),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local buttons = makeFrame(P.Right, "Buttons", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, big and 48 or 40),
			Size = UDim2.new(1, 0, 0, 54),
		})
		listLayout(buttons, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
		P.Odds = CloudUI.Button({
			Name = "Odds",
			Text = "Odds",
			Style = "Blue",
			Size = UDim2.fromOffset(112, 48),
			TextSize = 21,
			LayoutOrder = 1,
			Callback = function()
				openOdds(roulette.Id)
			end,
			Parent = buttons,
		})
		P.Spin = CloudUI.Button({
			Name = "Spin",
			Text = "Spin",
			Style = big and "Gold" or "Green",
			Size = UDim2.fromOffset(big and 170 or 150, 54),
			TextSize = 26,
			LayoutOrder = 2,
			Callback = function()
				requestSpin(roulette.Id, "Gems")
			end,
			Parent = buttons,
		})
		P.Buttons = buttons
		P.Hint = makeText(P.Right, "Hint", "", "Heading", 18, MUTED, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, big and 56 or 0),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			Visible = big,
		})
		local entry = { Roulette = roulette, Root = card, Stroke = cardStroke, Spin = P.Spin, Hint = P.Hint, Price = P.Price, Parts = P, Big = big }
		shop.GemCards[roulette.Id] = entry
		return entry
	end

	-- every pack looks a step richer than the one before: a bigger disc, a bigger pile of gems, a warmer colour
	-- (the biggest pack gold with a sparkle)
	local PACK_LOOKS = {
		{ Disc = 60, Pile = G.Gem, Size = 38 },
		{ Disc = 64, Pile = G.Gem .. G.Gem, Size = 28, Color = Color3.fromRGB(92, 214, 230) },
		{ Disc = 68, Pile = G.Gem .. "\n" .. G.Gem .. G.Gem, Size = 24, Color = Color3.fromRGB(150, 122, 240) },
		{ Disc = 72, Pile = G.Gem .. "\n" .. G.Gem .. G.Gem, Size = 26, Color = Color3.fromRGB(246, 192, 70), Sparkle = true },
	}

	local function buildPack(parent, product, order)
		local look = PACK_LOOKS[math.min(#PACK_LOOKS, math.max(1, product.Index))]
		local tint = look.Color or C2.Gem
		local card = makeFrame(parent, "Pack_" .. product.Index, {
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0,
			LayoutOrder = order,
		})
		corner(card, 16)
		stroke(card, look.Sparkle and Theme.Darken(tint, 0.35) or NAVY, 4, 0)
		Theme.Gradient(card, Theme.Darken(tint, 0.25), Theme.Darken(tint, 0.68), 90)
		local disc = makeFrame(card, "Disc", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 48),
			Size = UDim2.fromOffset(look.Disc, look.Disc),
			BackgroundTransparency = 0,
			BackgroundColor3 = tint,
		})
		round(disc)
		stroke(disc, NAVY, 3, 0)
		Theme.Gradient(disc, Theme.Lighten(tint, 0.5), Theme.Darken(tint, 0.15), 90)
		local pile = makeText(disc, "Glyph", look.Pile, "Title", look.Size, WHITE, { Size = UDim2.new(1, 0, 1, 0) })
		pile.LineHeight = 0.8
		if look.Sparkle then
			for i, spot in ipairs({ { 0.06, 0.02 }, { 0.84, 0.14 }, { 0.78, 0.74 } }) do
				makeText(disc, "Sparkle" .. i, G.Sparkle, "Title", 22, Color3.fromRGB(255, 246, 200), {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(spot[1], spot[2]),
					Size = UDim2.fromOffset(20, 20),
					ZIndex = 3,
				})
			end
		end
		local name = makeText(card, "Name", product.Name, "Title", 22, WHITE, {
			Position = UDim2.fromOffset(8, 88),
			Size = UDim2.new(1, -16, 0, 28),
			TextScaled = true,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 18, Parent = name })
		makeText(card, "Amount", P2.gemAmount(product.Gems), "Display", 30, Theme.Lighten(C2.Gem, 0.25), {
			Position = UDim2.fromOffset(0, 116),
			Size = UDim2.new(1, 0, 0, 36),
		})
		local price = makeText(card, "Robux", "", "Heading", 19, MUTED, {
			Position = UDim2.fromOffset(0, 154),
			Size = UDim2.new(1, 0, 0, 24),
		})
		local buy = CloudUI.Button({
			Name = "Buy",
			Text = "Buy",
			Style = "Green",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -28, 0, 48),
			TextSize = 22,
			Callback = function()
				buyPack(product)
			end,
			Parent = card,
		})
		Util.Create("UISizeConstraint", { MaxSize = Vector2.new(180, 48), Parent = buy })
		local entry = { Product = product, Root = card, Price = price, Buy = buy }
		shop.Packs[#shop.Packs + 1] = entry
		askPrice(product.Id)
		return entry
	end

	local function buildGemsPage(page)
		local scroll = scroller(page, "Gems", { Size = UDim2.new(1, 0, 1, 0) })
		pad(scroll, 2, 2, 14, 8)
		listLayout(scroll, Enum.FillDirection.Vertical, 10)
		G2.Scroll = scroll

		-- gem packs
		sectionTitle(scroll, "PacksTitle", G.Gem .. " Gem packs", 1)
		local products = createdProducts()
		if #products > 0 then
			local packs = makeFrame(scroll, "Packs", {
				Size = UDim2.new(1, 0, 0, K.GEM_PACK_H),
				LayoutOrder = 2,
			})
			G2.PacksLayout = Util.Create("UIGridLayout", {
				CellSize = UDim2.new(0.25, -8, 0, K.GEM_PACK_H),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Parent = packs,
			})
			G2.Packs = packs
			for i, product in ipairs(products) do
				buildPack(packs, product, i)
			end
		else
			local soon = makeInset(scroll, "PacksSoon", { Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 2 })
			makeText(soon, "Text", G.Gem .. "  Gem packs open soon! You can still earn Gems by prestiging your home.", "Heading", 19, MUTED, {
				Position = UDim2.fromOffset(16, 0),
				Size = UDim2.new(1, -32, 1, 0),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end

		-- the Secret roulette (gems only) and the token roulettes priced in Gems
		G2.Roulettes = {}
		local secret = secretRoulette() and findRoulette(secretRoulette().Id) or nil
		local order = 3
		G2.SecretTitle = sectionTitle(scroll, "SecretTitle", G.Storm .. " Storm Altar", order)
		G2.Roulettes[#G2.Roulettes + 1] = G2.SecretTitle
		if secret and gemPriceOf(secret.Id) then
			order = order + 1
			G2.Roulettes[#G2.Roulettes + 1] = buildGemRoulette(scroll, secret, order, true).Root
		end
		order = order + 1
		local rouletteTitle = sectionTitle(scroll, "GemRoulettesTitle", "Roulettes for Gems", order)
		G2.Roulettes[#G2.Roulettes + 1] = rouletteTitle
		for _, roulette in ipairs(Config.Roulettes) do
			if gemPriceOf(roulette.Id) then
				order = order + 1
				G2.Roulettes[#G2.Roulettes + 1] = buildGemRoulette(scroll, roulette, order, false).Root
			end
		end
		-- the policy notice (shown instead of the roulettes while they are not allowed)
		G2.Notice = makeInset(scroll, "GemNotice", { Size = UDim2.new(1, 0, 0, 84), LayoutOrder = 4, Visible = false })
		G2.NoticeText = makeText(G2.Notice, "Text", "", "Heading", 19, C2.Lock, {
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -32, 1, 0),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		makeText(scroll, "Tip", "Every roulette shows its exact odds (Odds button). Gems are bought with Robux and never expire.", "Body", 18, MUTED, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = 100,
		})
	end

	local function refreshGemsPage()
		local gems = P2.gemBalance()
		local state = gemRoulettesState()
		local match = inMatch()
		for _, packEntry in ipairs(shop.Packs) do
			local robux = Gems.Prices[packEntry.Product.Id]
			packEntry.Price.Text = robux and (G.Robux .. " " .. commas(robux)) or "for Robux"
			CloudUI.SetDisabled(packEntry.Buy, match)
		end
		local open = state == "Open"
		for _, inst in ipairs(G2.Roulettes or {}) do
			inst.Visible = open
		end
		if G2.Notice then
			G2.Notice.Visible = not open
			if state == "Restricted" then
				G2.NoticeText.Text = G.Lock .. "  Gem roulettes are not available on this account right now. Gem packs and Cloud Token roulettes still work."
			else
				G2.NoticeText.Text = G.Storm .. "  Gem roulettes and the Secret Roulette open soon at the Storm Altar!"
			end
		end
		for _, card in pairs(shop.GemCards) do
			local price = gemPriceOf(card.Roulette.Id) or 0
			card.Price.Text = P2.gemAmount(price)
			local label, hint, disabled = "Spin", "", false
			local hintColor = MUTED
			if match then
				disabled = true
				hint = "The shop is closed during matches."
			elseif Spin.Waiting then
				disabled = true
				label = "..."
				hint = "Spinning up..."
			elseif Spin.Stage then
				disabled = true
			elseif gems < price then
				disabled = true
				hint = "Need " .. P2.gemAmount(price - gems) .. " more"
				hintColor = Theme.Lighten(BAD, 0.35)
			elseif card.Big then
				hint = "Every spin: Mythic or Secret!"
			end
			card.Spin.Text = label
			CloudUI.SetDisabled(card.Spin, disabled or not open)
			card.Hint.Text = hint
			card.Hint.TextColor3 = hintColor
			card.Price.TextColor3 = gems < price and Theme.Lighten(BAD, 0.35) or Theme.Lighten(C2.Gem, 0.2)
		end
	end

	-- wide: 4 packs per row, the roulette text left of the buttons; tall (portrait): 2 packs per row, the price
	-- and buttons under the text
	local function layoutGemsPage(_w, tall)
		if G2.Packs then
			local rows = math.ceil(#shop.Packs / (tall and 2 or 4))
			G2.PacksLayout.CellSize = UDim2.new(tall and 0.5 or 0.25, -8, 0, K.GEM_PACK_H)
			G2.Packs.Size = UDim2.new(1, 0, 0, rows * K.GEM_PACK_H + math.max(0, rows - 1) * 10)
		end
		for _, card in pairs(shop.GemCards) do
			local P = card.Parts
			local big = card.Big
			local domeSize = big and 116 or 80
			if tall then
				local textX = (big and 96 or 74) + 22
				P.Dome.Size = UDim2.fromOffset(big and 96 or 74, big and 96 or 74)
				P.Dome.AnchorPoint = Vector2.new(0, 0)
				P.Dome.Position = UDim2.fromOffset(12, 12)
				P.Name.Position = UDim2.fromOffset(textX, 12)
				P.Name.Size = UDim2.new(1, -(textX + 12), 0, 32)
				P.Blurb.Position = UDim2.fromOffset(textX, 46)
				P.Blurb.Size = UDim2.new(1, -(textX + 12), 0, big and 50 or 48)
				P.Chances.Position = UDim2.fromOffset(12, big and 120 or 128)
				P.Chances.Size = UDim2.new(1, -24, 0, 30)
				P.Right.AnchorPoint = Vector2.new(0.5, 1)
				P.Right.Position = UDim2.new(0.5, 0, 1, -10)
				P.Right.Size = UDim2.new(1, -24, 0, big and 156 or 96)
				P.Hint.Size = UDim2.new(1, 0, 0, big and 48 or 0)
				card.Root.Size = UDim2.new(1, 0, 0, big and 350 or 270)
			else
				local textX = domeSize + 30
				P.Dome.Size = UDim2.fromOffset(domeSize, domeSize)
				P.Dome.AnchorPoint = Vector2.new(0, 0.5)
				P.Dome.Position = UDim2.new(0, 14, 0.5, 0)
				P.Name.Position = UDim2.fromOffset(textX, big and 12 or 10)
				P.Name.Size = UDim2.new(1, -(textX + 330), 0, big and 38 or 30)
				P.Blurb.Position = UDim2.fromOffset(textX, big and 52 or 42)
				P.Blurb.Size = UDim2.new(1, -(textX + 330), 0, big and 50 or 26)
				P.Chances.Position = UDim2.fromOffset(textX, big and 106 or 72)
				P.Chances.Size = UDim2.new(1, -(textX + 330), 0, 30)
				P.Right.AnchorPoint = Vector2.new(1, 0.5)
				P.Right.Position = UDim2.new(1, -14, 0.5, 0)
				P.Right.Size = UDim2.fromOffset(310, big and 170 or 96)
				P.Hint.Size = UDim2.new(1, 0, 0, big and 56 or 0)
				card.Root.Size = UDim2.new(1, 0, 0, big and 214 or K.GEM_ROW_H)
			end
		end
	end

	tabs.Add("Roulettes", buildRoulettePage)
	tabs.Add("Items", buildItemsPage)
	tabs.Add("Gems", buildGemsPage)

	-- gold outline on the roulette the player walked up to (OpenPanel passes RouletteId)
	local function focusCard(rouletteId)
		local card = shop.Cards[rouletteId] or shop.GemCards[rouletteId]
		if not card then
			return
		end
		card.Stroke.Color = GOLD
		card.Stroke.Thickness = 7
		task.delay(2.6, function()
			if card.Root.Parent then
				card.Stroke.Color = NAVY
				card.Stroke.Thickness = 4
			end
		end)
	end

	win.Refresh = function()
		if win.Tab == "Gems" then
			W.Balance.Text = P2.gemAmount(P2.gemBalance())
			W.Balance.TextColor3 = Theme.Lighten(C2.Gem, 0.2)
		else
			W.Balance.Text = cloudAmount(State.Tokens())
			W.Balance.TextColor3 = Colors.Token
		end
		refreshRouletteCards()
		refreshItemCards()
		refreshGemsPage()
	end
	-- compact cards when the tall ones would not fit the page (landscape phones); one card per row on portrait
	-- screens (the tall layout), with the balance pill above the tabs
	win.OnLayout = function(w, h, _narrow, _short, tall)
		local compact = h < K.SHOP_COMPACT or tall == true
		for _, card in pairs(shop.Cards) do
			layoutRouletteCard(card, compact)
		end
		for _, card in pairs(shop.ItemCards) do
			layoutItemCard(card, compact)
		end
		local function stack(row, layout, cards, cardH, count, wideSize)
			if not row or not layout then
				return
			end
			if tall then
				layout.FillDirection = Enum.FillDirection.Vertical
				for _, card in pairs(cards) do
					card.Root.Size = UDim2.new(1, 0, 0, cardH)
				end
				row.Size = UDim2.new(1, 0, 0, count * cardH + math.max(0, count - 1) * 12)
			else
				layout.FillDirection = Enum.FillDirection.Horizontal
				for _, card in pairs(cards) do
					card.Root.Size = wideSize
				end
				row.Size = UDim2.new(1, 0, 0, cardH)
			end
		end
		local roulettes, items = 0, 0
		for _ in pairs(shop.Cards) do
			roulettes = roulettes + 1
		end
		for _ in pairs(shop.ItemCards) do
			items = items + 1
		end
		stack(W.RouletteRow, W.RouletteLayout, shop.Cards, compact and K.CARD_H_SHORT or K.CARD_H, roulettes, UDim2.new(0.25, -9, 1, 0))
		stack(W.ItemRow, W.ItemLayout, shop.ItemCards, compact and K.ITEM_CARD_H_SHORT or K.ITEM_CARD_H, items, UDim2.new(1 / math.max(3, items), -8, 1, 0))
		tabs.Root.Position = UDim2.fromOffset(12, tall and 62 or 10)
		tabs.Root.Size = UDim2.new(1, -24, 1, tall and -72 or -20)
		layoutGemsPage(w, tall == true)
	end
	win.OnOpen = function(args)
		local tab = normalizeTab("Shop", args.Tab)
		local target = type(args.RouletteId) == "string" and findRoulette(args.RouletteId) or nil
		if not tab and (args.Currency == "Gems" or (target and target.GemsOnly)) then
			tab = "Gems"
		end
		if not tab and type(args.RouletteId) == "string" then
			tab = "Roulettes"
		end
		if tab then
			tabs.Select(tab)
		end
		if type(args.RouletteId) == "string" then
			focusCard(args.RouletteId)
		end
		for _, bob in ipairs(shop.Bobs) do
			bob:Play()
		end
	end
	win.OnClose = function()
		for _, bob in ipairs(shop.Bobs) do
			bob:Cancel()
		end
	end
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
	makeText(list, "Title", "Best times", "Title", 28, WHITE, {
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 0,
	})
	for index, difficulty in ipairs(Config.Difficulties) do
		local row = makeFrame(list, "Row_" .. difficulty.Id, {
			Size = UDim2.new(1, 0, 0, 66),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Darken(difficulty.Color, 0.55),
			LayoutOrder = index,
		})
		corner(row, 12)
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
		makeText(row, "Stars", starText(difficulty.Stars), "Heading", 18, GOLD, {
			Position = UDim2.fromOffset(22, 36),
			Size = UDim2.new(0.55, -22, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
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
		tiles.Tokens.Text = cloudAmount(State.Tokens())
		tiles.Earned.Text = cloudAmount(stats.TokensEarned or 0)
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

		local b = P3.Battle and P3.Battle() or {}
		-- Phase 5 (10.5): the Trial ladder is gone; the dungeon line takes its place
		local dungeon = type(State.Dungeon) == "function" and State.Dungeon() or nil
		dungeon = type(dungeon) == "table" and dungeon or {}
		battleLabel.Text = string.format("\240\159\143\134 %s trophies     Dungeon: floor %d cleared, %s runs\nDuels: %s won, %s lost     Boss raids: %s",
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
			perksLabel.Text = "No perks yet. Equip a pet in your inventory!"
			perksLabel.TextColor3 = MUTED
		end
	end
end

----------------------------------------------------------------------
-- Home window (Phase 2): the house, income, the Collector, prestige, and every station with its upgrade
----------------------------------------------------------------------
-- Phase 5 (3.4): the Home window's flow strip, the first item of its list: four neon tiles that tell the home loop
-- "Berry Farm Lv 13" -> "Pets eat & poop $3,000/min" -> "Berry Basket 1,240 / 3,000" -> "Food Machine: Feed = XP".
P5.STRIP = {
	{ Id = "Farm", Title = "Berry Farm", Glyph = "\240\159\141\147", Color = "Pink" },
	{ Id = "Poop", Title = "Pets eat & poop", Glyph = "\240\159\146\169", Color = "Green" },
	{ Id = "Basket", Title = "Berry Basket", Glyph = "\240\159\167\186", Color = "Purple" },
	{ Id = "Machine", Title = "Food Machine", Glyph = "\240\159\141\178", Color = "Orange" },
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
			H.StripArrows[i] = makeText(strip, "Arrow" .. i, "\226\150\182", "Title", 18, GOLD, { Size = UDim2.fromOffset(20, 76) })
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
	GoHome = { Title = "Go home", Sub = "A magic portal for you and your pets", Short = "Hop in with your pets!", Glyph = "\240\159\143\160", Badge = "\226\158\156" },
	ClaimHome = { Title = "Claim a home", Sub = "Get your own sky island, free!", Short = "Your own sky island, free!", Glyph = "\240\159\143\161", Badge = "\226\156\168" },
}
-- what a home gives (the claim view's "Your home" tiles)
P5.CLAIM_GETS = {
	{ Glyph = "\240\159\140\177", Title = "Pet Garden", Text = "Pets roam and play", Color = "Green" },
	{ Glyph = "\240\159\141\147", Title = "Berry Farm", Text = "Berries feed pets", Color = "Pink" },
	{ Glyph = "\226\152\129", Title = "Cloud Cash", Text = "Pets earn for you", Color = "Cyan" },
}
P5.CLAIM_STEPS = {
	{ Glyph = "\240\159\140\128", Text = "Tap Claim a home: a magic portal opens" },
	{ Glyph = "\240\159\143\131", Text = "Walk into it: you land at a free home" },
	{ Glyph = "\240\159\148\145", Text = "Press E at its gate. The home is yours!" },
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
	corner(clip, 18)
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
	hero.Title = makeText(card.Body, "Title", spec.Title, "Title", 34, WHITE, {
		Position = UDim2.new(0, 96, 0.5, -2),
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, -176, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextScaled = true,
		ZIndex = 6,
	})
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
	makeText(badge, "Glyph", spec.Badge, "Title", 28, Theme.NeonColor("Orange"), { Size = UDim2.fromScale(1, 1), ZIndex = 7 })
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
		H.HouseGlyph = makeText(disc, "Glyph", G.House, "Title", 36, WHITE, { Size = UDim2.new(1, 0, 1, 0) })
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
		makeText(garden, "Caption", G.Seedling .. " Pet Garden", "Heading", 19, MUTED, {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(0.6, -14, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
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
			Text = G.Star .. " Prestige",
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
			corner(row.Disc, 16)
			stroke(row.Disc, NAVY, 3, 0)
			Theme.Gradient(row.Disc, Theme.Lighten(color, 0.35), Theme.Darken(color, 0.2), 90)
			makeText(row.Disc, "Glyph", tostring(def.Icon or G.House), "Title", 34, WHITE, { Size = UDim2.new(1, 0, 1, 0) })
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
				corner(pip, 3)
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
			makeText(header, "Title", section.Title, "Title", 24, WHITE, {
				Position = UDim2.fromOffset(6, 0),
				Size = UDim2.new(1, -12, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
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
		corner(confirm, 14)
		local box = makeFrame(confirm, "Box", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.fromOffset(K.CONFIRM_W, K.CONFIRM_H),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE, -- the UIGradient below multiplies this colour
			ZIndex = 31,
		})
		corner(box, 16)
		stroke(box, GOLD, 4, 0)
		Theme.Gradient(box, Colors.PanelLight, Colors.Panel, 90)
		H.ConfirmBox = box
		makeText(box, "Title", G.Star .. " Prestige now?", "Title", 32, GOLD, {
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 40),
			ZIndex = 32,
		})
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
			Text = G.Star .. " Prestige!",
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
				row.Lock.Text = G.Lock .. " " .. tostring(lock)
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
			H.HouseGlyph.Text = (type(tier) == "table" and tier.Icon) or G.House
			H.HomeLevel.Text = "Home Level " .. homeLevel
			-- prestige stars in the corner (none before the first prestige)
			H.Stars.Visible = stars > 0
			H.Stars.Text = stars <= 3 and string.rep(G.Star, stars) or (G.Star .. " x" .. stars)
			local nextTier = tiers[(houseLevel >= 1 and (tierIndex or 1) or 0) + 1]
			H.NextHouse.TextColor3 = MUTED
			if houseLevel < 1 then
				H.NextHouse.Text = "Build your Cottage on the House pad"
			elseif type(nextTier) == "table" then
				local at = tonumber(nextTier.HomeLevel) or 0
				if homeLevel >= at then
					H.NextHouse.Text = G.Check .. " Upgrade the House to a " .. tostring(nextTier.Name) .. "!"
					H.NextHouse.TextColor3 = Theme.Lighten(GOOD, 0.35)
				else
					H.NextHouse.Text = "Next: " .. tostring(nextTier.Name) .. " at Home Level " .. at
				end
			else
				H.NextHouse.Text = "Your " .. ((type(tier) == "table" and tier.Name) or "house") .. " is complete!"
			end
			-- prestige
			local P = TycoonCatalog and TycoonCatalog.Prestige or {}
			local need = tonumber(P.HomeLevel) or 40
			H.PrestigeTitle.Text = "Prestige  " .. G.Star .. " " .. stars .. "  ->  " .. (stars + 1)
			H.PrestigeBar.SetFraction(need > 0 and math.min(1, homeLevel / need) or 0)
			H.PrestigeBar.SetText("Home Level " .. math.min(homeLevel, need) .. "/" .. need)
			local ok, reason = P2.catalogCall("CanPrestige", home)
			if ok then
				H.PrestigeNeed.Text = G.Check .. " Ready to prestige!"
				H.PrestigeNeed.TextColor3 = Theme.Lighten(GOOD, 0.35)
			else
				H.PrestigeNeed.Text = G.Lock .. " " .. tostring(reason or "Not ready yet")
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
-- Team window (Phase 3; Phase 5: 3 slots = FIGHTER + 2 HELPERs, "Set as fighter"): three battle-team presets, the pet picker with element
-- badges, levels and battle stats, live synergy (BattleCatalog.SynergyBonus), the element wheel and the team power.
-- Edits show at once (a local draft) and are sent as BattleRequest("TeamSet", preset, keys) after a short pause; the
-- server validates everything (owned, unique, not in training, slot 4 rule) and ProfileSync brings the
-- saved presets back. "Use this team" sends BattleRequest("TeamSelect", preset).
----------------------------------------------------------------------
-- (defined inside a function, not a do-block: the main chunk is at Lua's 200-local limit)
P3.Define = function()
	local PRESETS = 3
	local MAX_SLOTS = 3 -- Phase 5 (4.8): teams of 3, a FIGHTER and two HELPERs (no 4th slot)
	local SEND_DELAY = 0.45 -- seconds of quiet before an edited preset is sent
	local DRAFT_HOLD = 4 -- seconds a local edit wins over the synced presets (then the server's answer does)
	local CARD_GAP = 10
	local CARD_H, CARD_H_SHORT = 146, 112 -- a team slot card (viewport on the left, the pet's details on the right)
	local TILE_W, TILE_H = 140, 184
	local TILE_W_SHORT, TILE_H_SHORT = 134, 166
	local WHEEL_W, WHEEL_H = 300, 252
	local INSET_X, INSET_Y = 24, 82 -- the panel's frame around Panel.Content (CloudUI.ContentInset)
	local TEAM_ACCENT = Color3.fromRGB(214, 92, 96)
	local POWER_GOLD = Color3.fromRGB(255, 214, 110)
	local GOOD_TEXT = Color3.fromRGB(150, 236, 170)
	local WARN_TEXT = Color3.fromRGB(255, 186, 150)
	local GL = {
		Trophy = "\240\159\143\134",
		Swords = "\226\154\148",
		Heart = "\226\157\164",
		Bolt = "\226\154\161",
		Plus = "+",
		Arrow = "\226\158\156", -- heavy round-tipped rightwards arrow
		Both = "\226\135\132", -- rightwards arrow over leftwards arrow
		Close = "\195\151", -- multiplication sign
	}

	local T = {
		Edit = nil, -- the preset shown (1..3)
		Draft = {}, -- [preset] = { key... } edited locally, not confirmed yet
		DraftAt = {},
		SendToken = {},
		Selected = nil, -- a team slot picked for a swap
		ActivePending = nil,
		ActiveAt = 0,
		Catalog = nil,
		PowerCache = {},
	}

	local function battleCatalog()
		if T.Catalog then
			return T.Catalog
		end
		local module = Shared:FindFirstChild("BattleCatalog")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				T.Catalog = result
			end
		end
		return T.Catalog
	end

	local function copyList(list)
		local out = {}
		if type(list) == "table" then
			for i, v in ipairs(list) do
				out[i] = v
			end
		end
		return out
	end

	local function sameList(a, b)
		if #a ~= #b then
			return false
		end
		for i = 1, #a do
			if a[i] ~= b[i] then
				return false
			end
		end
		return true
	end

	local function teamsData()
		if type(State.Teams) == "function" then
			local ok, teams = pcall(State.Teams)
			if ok and type(teams) == "table" and type(teams.Presets) == "table" then
				return teams
			end
		end
		return { Presets = { {}, {}, {} }, Active = 1, Slots = 3 }
	end

	local function battleData()
		if type(State.Battle) == "function" then
			local ok, battle = pcall(State.Battle)
			if ok and type(battle) == "table" then
				return battle
			end
		end
		return { Trophies = 0, TrialBest = 0, TrialCleared = {}, PvPWins = 0, PvPLosses = 0, Raids = 0 }
	end

	local function slotCount()
		return MAX_SLOTS
	end

	local function serverKeys(preset)
		return copyList(teamsData().Presets[preset])
	end

	-- the keys shown for a preset: the local draft while it is fresh, else the synced preset
	local function keysOf(preset)
		local draft = T.Draft[preset]
		if draft then
			if os.clock() - (T.DraftAt[preset] or 0) < DRAFT_HOLD then
				return draft
			end
			T.Draft[preset] = nil
		end
		return serverKeys(preset)
	end

	local function activePreset()
		if T.ActivePending then
			if os.clock() - T.ActiveAt < DRAFT_HOLD and T.ActivePending ~= teamsData().Active then
				return T.ActivePending
			end
			T.ActivePending = nil
		end
		local a = math.floor(tonumber(teamsData().Active) or 1)
		if a < 1 or a > PRESETS then
			a = 1
		end
		return a
	end

	-- bug batch 2 #18: a copy working in the Garden is busy gardening (it cannot fight; its tile says "Gardening" and a
	-- tap asks to take it out); a pet in training stays in its preset but sits out the fights until it is done (the
	-- server skips it at read time), so its tile says "Training"
	local function freeCopies(key)
		return State.OwnedCount(key) - P2.gardenCopies(key)
	end

	local function entryOf(key)
		local def = P2.defOfKey(key)
		if not def then
			return nil
		end
		local level = P2.petLevel(key)
		return { Def = def, Level = level, Key = key }
	end

	local function catalogCall(fnName, ...)
		local BC = battleCatalog()
		if not BC or type(BC[fnName]) ~= "function" then
			return nil
		end
		local ok, result = pcall(BC[fnName], ...)
		if ok then
			return result
		end
		warnOnce("BattleCatalog." .. fnName, result)
		return nil
	end

	local function unitPower(entry)
		if not entry then
			return 0
		end
		local cacheKey = tostring(entry.Key) .. "#" .. tostring(entry.Level)
		local cached = T.PowerCache[cacheKey]
		if cached then
			return cached
		end
		local p = tonumber(catalogCall("UnitPower", entry)) or 0
		T.PowerCache[cacheKey] = p
		return p
	end

	local function specialLine(def)
		local special = type(def) == "table" and def.Special
		if type(special) ~= "table" then
			return nil
		end
		local name = tostring(special.Name or special.Kind or "Special")
		local BC = battleCatalog()
		local info = BC and type(BC.Specials) == "table" and BC.Specials[special.Kind]
		if type(info) == "table" and info.Role then
			return name .. " (" .. tostring(info.Role) .. ")", info.Text
		end
		return name, nil
	end

	-- the element wheel from Config.Elements.Strong: { "Water", "Flame", ... } + rival pairs { {"Celestial", "Shadow"} }
	local function wheelOrder()
		local E = Config.Elements or {}
		local strong = E.Strong or {}
		local order = E.Order or {}
		local wheel, seen = {}, {}
		local start = order[1]
		local cur = start
		for _ = 1, #order do
			local beats = type(strong[cur]) == "table" and strong[cur][1]
			if not cur or seen[cur] or not beats then
				break
			end
			seen[cur] = true
			wheel[#wheel + 1] = cur
			cur = beats
			if cur == start then
				break
			end
		end
		local rivals = {}
		for _, id in ipairs(order) do
			local beats = type(strong[id]) == "table" and strong[id][1]
			if beats and not seen[id] and not seen[beats] then
				seen[id] = true
				seen[beats] = true
				rivals[#rivals + 1] = { id, beats }
			end
		end
		return wheel, rivals
	end

	local function elementColor(element)
		local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[element]
		return info and info.Color or Colors.PanelLight
	end

	----------------------------------------------------------------------
	-- Editing (optimistic draft + debounced TeamSet)
	----------------------------------------------------------------------
	local refreshTeam

	local function sendPreset(preset)
		T.SendToken[preset] = (T.SendToken[preset] or 0) + 1
		local mine = T.SendToken[preset]
		task.delay(SEND_DELAY, function()
			if T.SendToken[preset] ~= mine then
				return
			end
			local list = T.Draft[preset]
			if not list then
				return
			end
			T.DraftAt[preset] = os.clock() -- the server's answer (ProfileSync) is due from now
			local remote = getRemote("BattleRequest")
			if remote then
				local ok, err = pcall(function()
					remote:FireServer("TeamSet", preset, copyList(list))
				end)
				if not ok then
					warnOnce("TeamSet", err)
				end
			end
			-- a refused edit (busy pet, slot 4 ...) brings no ProfileSync: show the saved preset again once the draft expires
			task.delay(DRAFT_HOLD + 0.1, function()
				refreshTeam()
			end)
		end)
	end

	local function setDraft(preset, list)
		T.Draft[preset] = list
		T.DraftAt[preset] = os.clock()
		sendPreset(preset)
		refreshTeam()
	end

	local function addKey(key)
		local preset = T.Edit or activePreset()
		local list = copyList(keysOf(preset))
		for i, k in ipairs(list) do
			if k == key then
				-- tapping a pet that is already in the team takes it out again
				table.remove(list, i)
				T.Selected = nil
				setDraft(preset, list)
				return
			end
		end
		local slots = slotCount()
		local function placed()
			if T.Selected and T.Selected <= slots then
				if T.Selected <= #list then
					list[T.Selected] = key
				else
					list[#list + 1] = key
				end
				return true
			elseif #list < slots then
				list[#list + 1] = key
				return true
			end
			return false
		end
		if freeCopies(key) < 1 then
			if P2.gardenCopies(key) > 0 and State.OwnedCount(key) > 0 then
				-- bug batch 2 #18: it is gardening: ask, then ONE request takes it out and stores this team
				if not placed() then
					showHint("Your team is full. Tap a team slot, then a pet to swap it.", "info")
					return
				end
				T.Selected = nil
				P2.askRecall(key, { To = "Team", Preset = preset, Keys = copyList(list) }, function()
					-- the server stores the team itself (no TeamSet): show it at once, the next sync confirms it
					T.Draft[preset] = list
					T.DraftAt[preset] = os.clock()
					refreshTeam()
				end)
				return
			end
			showHint("You have no free copy of that pet.", "info")
			return
		end
		if not placed() then
			showHint("Your team is full. Tap a team slot, then a pet to swap it.", "info")
			return
		end
		T.Selected = nil
		setDraft(preset, list)
	end

	-- Phase 5 (4.8): "Set as fighter" rotates the preset so this slot's pet leads ({a, b, c}, slot 3 -> {c, a, b})
	local function setFighter(index)
		local preset = T.Edit or activePreset()
		local list = copyList(keysOf(preset))
		if index <= 1 or not list[index] then
			return
		end
		local rotated = {}
		for i = 0, #list - 1 do
			rotated[#rotated + 1] = list[((index - 1 + i) % #list) + 1]
		end
		T.Selected = nil
		setDraft(preset, rotated)
		showHint(P2.displayName(rotated[1], P2.defOfKey(rotated[1])) .. " is your fighter now!", "good")
	end
	P3.SetFighter = setFighter

	local function removeSlot(index)
		local preset = T.Edit or activePreset()
		local list = copyList(keysOf(preset))
		if list[index] then
			table.remove(list, index)
			T.Selected = nil
			setDraft(preset, list)
		end
	end

	local function clearPreset()
		local preset = T.Edit or activePreset()
		if #keysOf(preset) > 0 then
			T.Selected = nil
			setDraft(preset, {})
		end
	end

	local function selectPreset()
		local preset = T.Edit or activePreset()
		if preset == activePreset() then
			return
		end
		T.ActivePending = preset
		T.ActiveAt = os.clock()
		fireKeyed("TeamSelect", "BattleRequest", "TeamSelect", preset)
		refreshTeam()
	end

	-- the synced presets arrived: drop drafts the server now agrees with
	local function settleDrafts()
		for preset, draft in pairs(T.Draft) do
			if sameList(draft, serverKeys(preset)) and os.clock() - (T.DraftAt[preset] or 0) > SEND_DELAY then
				T.Draft[preset] = nil
			end
		end
		T.PowerCache = {} -- levels may have changed
	end

	----------------------------------------------------------------------
	-- Widgets
	----------------------------------------------------------------------
	local function chip(parent, name, order)
		local frame = makeFrame(parent, name, {
			BackgroundTransparency = 0,
			BackgroundColor3 = INSET_COLOR,
			Size = UDim2.fromOffset(0, 48),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = order or 0,
		})
		corner(frame, 12)
		stroke(frame, NAVY, 3, 0)
		pad(frame, 12, 0, 14, 0)
		listLayout(frame, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		return frame
	end

	local function autoText(parent, name, text, role, size, color, order)
		return makeText(parent, name, text, role, size, color, {
			Size = UDim2.fromOffset(0, size + 8),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = order or 0,
		})
	end

	-- a team slot card
	local function buildCard(ui, parent, index)
		local card = { Index = index }
		card.Button = Util.Create("TextButton", {
			Name = "Slot" .. index,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Text = "",
			BackgroundColor3 = WHITE,
			LayoutOrder = index,
			Parent = parent,
		})
		corner(card.Button, 14)
		card.Stroke = stroke(card.Button, NAVY, 3, 0)
		card.Gradient = Util.Create("UIGradient", { Rotation = 90, Parent = card.Button })
		-- Phase 5 (4.8): the slot's job: FIGHTER (slot 1, you control it) or HELPER (slots 2-3, their buff buttons)
		local fighter = index == 1
		card.Number = makeFrame(card.Button, "Role", {
			BackgroundTransparency = 0,
			BackgroundColor3 = fighter and Theme.Neon.Red or Theme.Neon.Blue,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(fighter and 92 or 82, 26),
			ZIndex = 4,
		})
		corner(card.Number, 8)
		stroke(card.Number, NAVY, 2, 0)
		card.RoleText = makeText(card.Number, "Text", fighter and "FIGHTER" or "HELPER", "Button", 18, WHITE, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })
		if not fighter then
			card.SetFighter = CloudUI.Button({
				Name = "SetFighter",
				Text = "Set as fighter",
				Style = "Red",
				Size = UDim2.fromOffset(150, 34),
				TextSize = 18,
				ZIndex = 6,
				Callback = function()
					safe("team fighter", setFighter, index)
				end,
				Parent = card.Button,
			})
		end
		card.Remove = Util.Create("TextButton", {
			Name = "Remove",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Text = "",
			BackgroundColor3 = BUTTONS.Red or BAD,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(34, 34),
			ZIndex = 6,
			Parent = card.Button,
		})
		round(card.Remove)
		stroke(card.Remove, NAVY, 2.5, 0)
		makeText(card.Remove, "X", GL.Close, "Button", 24, WHITE, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 7 })
		card.Remove.Activated:Connect(function()
			safe("team remove", removeSlot, index)
		end)
		card.View = makeFrame(card.Button, "ViewHolder", {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(120, 120),
			ZIndex = 2,
		})
		local function line(name, text, role, size, color)
			return makeText(card.Button, name, text, role, size, color, {
				Size = UDim2.new(1, -150, 0, size + 6),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 3,
			})
		end
		card.Name = line("PetName", "", "Title", 23, WHITE)
		card.Info = line("Info", "", "Body", 19, MUTED)
		card.Elements = makeFrame(card.Button, "Elements", { Size = UDim2.new(1, -150, 0, 28), ZIndex = 3 })
		listLayout(card.Elements, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		card.Stats = line("Stats", "", "Heading", 20, POWER_GOLD)
		card.Special = line("Special", "", "Body", 18, Theme.Lighten(PURPLE, 0.5))
		-- empty / locked face
		card.Empty = makeFrame(card.Button, "EmptyFace", { Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 })
		card.EmptyGlyph = makeText(card.Empty, "Glyph", GL.Plus, "Title", 52, Theme.Lighten(MUTED, 0.2), {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0.5, 6),
			Size = UDim2.fromOffset(90, 60),
			ZIndex = 4,
		})
		card.EmptyText = makeText(card.Empty, "Caption", "Pick a pet", "Heading", 20, MUTED, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.5, 8),
			Size = UDim2.new(1, -24, 0, 50),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 4,
		})
		card.Button.Activated:Connect(function()
			safe("team slot", function()
				if T.Selected == index then
					T.Selected = nil
				else
					T.Selected = index
				end
				refreshTeam()
			end)
		end)
		CloudUI.Tooltip(card.Button, function()
			return card.Tip
		end)
		ui.Cards[index] = card
		return card
	end

	-- places a card's parts for its size: the viewport square on the left, the details beside it
	local function layoutCard(card, h)
		local view = math.min(h - 16, 104)
		card.View.Position = UDim2.fromOffset(8, math.floor((h - view) / 2))
		card.View.Size = UDim2.fromOffset(view, view)
		local x = view + 16
		local y = h >= CARD_H and 6 or 3
		local function put(inst, height)
			inst.Position = UDim2.fromOffset(x, y)
			inst.Size = UDim2.new(1, -(x + 8), 0, height)
			y = y + height + 1
		end
		put(card.Name, 28)
		put(card.Info, 23)
		put(card.Elements, 28)
		y = y + 1
		put(card.Stats, 25)
		card.ShowSpecial = y + 23 <= h - 3
		if card.ShowSpecial then
			put(card.Special, 23)
		end
		-- the role sits on the viewport's top-left corner, the remove button on its bottom-right one, "Set as fighter"
		-- on the card's bottom-right corner (helpers only)
		card.Number.Position = UDim2.fromOffset(4, 4)
		card.Remove.AnchorPoint = Vector2.new(1, 1)
		card.Remove.Position = UDim2.new(0, 8 + view + 4, 1, -4)
		if card.SetFighter then
			-- beside the "Lv 57 - Epic" line (that line gives it room), never over the stats
			local bw = 146
			card.SetFighter.AnchorPoint = Vector2.new(1, 0)
			card.SetFighter.Position = UDim2.new(1, -6, 0, card.Info.Position.Y.Offset - 2)
			card.SetFighter.Size = UDim2.fromOffset(bw, 30)
			card.Info.Size = UDim2.new(1, -(x + 14 + bw), 0, 23)
		end
	end

	local function paintCard(card, key, entry, locked, selected)
		local def = entry and entry.Def or nil
		card.Locked = locked
		card.Key = key
		local filled = def ~= nil and not locked
		local tint = filled and rarityOf(def) or Color3.fromRGB(70, 92, 150)
		if locked then
			tint = Color3.fromRGB(70, 78, 104)
		end
		card.Gradient.Color = ColorSequence.new(Theme.Lighten(INSET_COLOR, 0.28):Lerp(tint, 0.35), Theme.Darken(INSET_COLOR, 0.1):Lerp(tint, 0.18))
		card.Button.BackgroundColor3 = WHITE
		card.Stroke.Color = selected and GOLD or (filled and Theme.Lighten(tint, 0.15) or NAVY)
		card.Stroke.Thickness = selected and 4 or 3
		card.Remove.Visible = filled
		card.Empty.Visible = not filled
		for _, name in ipairs({ "Name", "Info", "Elements", "Stats", "Special" }) do
			card[name].Visible = filled
		end
		card.View.Visible = filled
		if card.SetFighter then
			card.SetFighter.Visible = filled
		end
		if not filled then
			card.EmptyGlyph.Text = GL.Plus
			card.EmptyText.Text = selected and "Now tap a pet" or "Pick a pet"
			card.EmptyText.TextColor3 = selected and GOLD or MUTED
			card.Tip = nil
		end
		if not filled then
			if card.Viewport then
				card.Viewport.Destroy()
				card.Viewport = nil
				card.ViewKey = nil
			end
			return
		end
		-- Phase 5 (3.7): the copy's stored stage; an evolved model is built at Low
		local stage = P2.stage(key)
		if card.ViewKey ~= key .. "|" .. stage then
			if card.Viewport then
				card.Viewport.Destroy()
				card.Viewport = nil
			end
			card.ViewKey = key .. "|" .. stage
			local ok, handle = pcall(CloudUI.PetViewport, card.View, def, UDim2.new(1, 0, 1, 0), {
				Spin = "sway",
				Animate = true,
				Detail = stage >= 1 and "Low" or "High",
				Evolved = stage >= 1 and stage or nil,
				ZIndex = 2,
			})
			if ok then
				card.Viewport = handle
			end
		end
		card.Name.Text = P2.displayName(key, def)
		card.Name.TextColor3 = rarityText(def)
		local tier = P2.tierOf(key, def)
		local tierText = tier ~= "Normal" and (" " .. G.Bullet .. " " .. tier) or ""
		card.Info.Text = "Lv " .. tostring(entry.Level) .. " " .. G.Bullet .. " " .. tostring(def.Rarity) .. tierText
		for _, child in ipairs(card.Elements:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, element in ipairs(elementsOf(def)) do
			elementPill(card.Elements, element, 18, i)
		end
		local stats = catalogCall("UnitStats", entry)
		local power = unitPower(entry)
		if type(stats) == "table" then
			card.Stats.Text = GL.Swords .. " " .. commas(power) .. "  " .. GL.Heart .. " " .. commas(math.floor((stats.MaxHp or 0) + 0.5))
		else
			card.Stats.Text = GL.Swords .. " " .. commas(power)
		end
		local special, specialText = specialLine(def)
		local specialName = type(def.Special) == "table" and def.Special.Name or nil
		card.Special.Text = specialName and (G.Sparkle .. " " .. tostring(specialName)) or ""
		local tip = P2.displayName(key, def) .. " (Lv " .. tostring(entry.Level) .. ")"
		if type(stats) == "table" then
			tip = tip .. "\nPower " .. commas(power) .. ", Health " .. commas(math.floor((stats.MaxHp or 0) + 0.5))
				.. ", " .. string.format("%.1f", stats.Dps or 0) .. " damage per second, " .. ((stats.Ranged and "ranged") or "melee")
		end
		if special then
			tip = tip .. "\nSpecial: " .. special .. (specialText and (". " .. specialText) or "")
		end
		card.Tip = tip
	end

	-- a picker tile (one per owned pet copy)
	local function buildTile(ui, key)
		local tile = { Key = key }
		tile.Button = Util.Create("TextButton", {
			Name = "Pick_" .. key,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Text = "",
			BackgroundColor3 = WHITE,
			Parent = ui.Grid,
		})
		corner(tile.Button, 12)
		tile.Stroke = stroke(tile.Button, NAVY, 3, 0)
		tile.Gradient = Util.Create("UIGradient", { Rotation = 90, Parent = tile.Button })
		tile.View = makeFrame(tile.Button, "ViewHolder", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.new(1, -12, 0, 78),
			ZIndex = 2,
		})
		-- names wrap onto a second line instead of being cut ("Ember Phoenix", "Starlight Unicorn")
		tile.Name = makeText(tile.Button, "PetName", "", "Body", 18, WHITE, {
			Position = UDim2.fromOffset(4, 82),
			Size = UDim2.new(1, -8, 0, 42),
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		})
		tile.Row = makeFrame(tile.Button, "Row", {
			Position = UDim2.fromOffset(6, 126),
			Size = UDim2.new(1, -12, 0, 28),
			ZIndex = 3,
		})
		listLayout(tile.Row, Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		tile.Power = makeText(tile.Button, "Power", "", "Heading", 19, POWER_GOLD, {
			Position = UDim2.fromOffset(6, 155),
			Size = UDim2.new(1, -12, 0, 26),
			ZIndex = 3,
		})
		tile.Mark = makeFrame(tile.Button, "InTeam", {
			BackgroundTransparency = 0,
			BackgroundColor3 = GOOD,
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(32, 32),
			Visible = false,
			ZIndex = 6,
		})
		round(tile.Mark)
		stroke(tile.Mark, NAVY, 2.5, 0)
		tile.MarkText = makeText(tile.Mark, "Text", "1", "Button", 20, WHITE, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 7 })
		tile.Dim = makeFrame(tile.Button, "Dim", {
			BackgroundTransparency = 0.45,
			BackgroundColor3 = Color3.fromRGB(12, 16, 36),
			Size = UDim2.new(1, 0, 1, 0),
			Visible = false,
			ZIndex = 8,
		})
		corner(tile.Dim, 12)
		tile.Busy = makeText(tile.Dim, "Busy", "Busy", "Heading", 19, C2.Lock, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.36, 0),
			Size = UDim2.new(1, -8, 0, 48),
			TextWrapped = true,
			ZIndex = 9,
		})
		tile.Button.Activated:Connect(function()
			safe("team pick", addKey, key)
		end)
		CloudUI.Tooltip(tile.Button, function()
			return tile.Tip
		end)
		ui.Tiles[key] = tile
		return tile
	end

	local function paintTile(tile, entry, inTeamSlot, busyText)
		local def = entry.Def
		local tint = rarityOf(def)
		tile.Gradient.Color = ColorSequence.new(Theme.Lighten(INSET_COLOR, 0.3):Lerp(tint, 0.38), Theme.Darken(INSET_COLOR, 0.05):Lerp(tint, 0.2))
		tile.Stroke.Color = inTeamSlot and GOOD or Theme.Lighten(tint, 0.1)
		tile.Stroke.Thickness = inTeamSlot and 4 or 3
		tile.Name.Text = P2.displayName(entry.Key, def)
		-- white on the rarity-tinted card (a rarity-coloured name on a card of the same hue lost its contrast);
		-- the card's tint and border already say the rarity, like the Pets panel
		tile.Name.TextColor3 = WHITE
		local sig = table.concat(elementsOf(def), ",") .. "|" .. tostring(entry.Level)
		if tile.RowSig ~= sig then
			tile.RowSig = sig
			for _, child in ipairs(tile.Row:GetChildren()) do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			autoText(tile.Row, "Level", "Lv " .. tostring(entry.Level), "Heading", 18, WHITE, 0)
			for i, element in ipairs(elementsOf(def)) do
				elementPill(tile.Row, element, 18, i)
			end
		end
		local power = unitPower(entry)
		tile.Power.Text = GL.Swords .. " " .. commas(power)
		tile.Mark.Visible = inTeamSlot ~= nil
		if inTeamSlot then
			tile.MarkText.Text = tostring(inTeamSlot)
		end
		tile.Dim.Visible = busyText ~= nil and not inTeamSlot
		tile.Busy.Text = busyText or ""
		local special = specialLine(def)
		tile.Tip = P2.displayName(entry.Key, def) .. " (Lv " .. tostring(entry.Level) .. ", Power " .. commas(power) .. ")"
			.. (special and ("\nSpecial: " .. special) or "")
			.. (inTeamSlot and "\nIn this team: tap to take it out" or "\nTap to add it to the team")
	end

	local function borderStroke(inst)
		for _, child in ipairs(inst:GetChildren()) do
			if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
				return child
			end
		end
		return nil
	end

	-- the element wheel (Config.Elements): six elements on a ring, arrows to the one each beats, the rivals below
	local function buildWheel(parent)
		local wheel = makeInset(parent, "ElementWheel", { Size = UDim2.fromOffset(WHEEL_W, WHEEL_H) })
		makeText(wheel, "Title", "Element wheel", "Heading", 20, WHITE, {
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 26),
		})
		local nodes = {}
		local order, rivals = wheelOrder()
		local n = #order
		local cx, cy, r = WHEEL_W / 2, 32 + 74 + 16, 74
		local rx = 96 -- an ellipse: the pills need the width more than the height
		local atan2 = math.atan2 or function(y, x)
			return math.atan(y, x)
		end
		makeText(wheel, "Centre", "Each beats\nthe next", "Body", 18, MUTED, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(110, 48),
		})
		for i, element in ipairs(order) do
			local a = math.rad(-90 + (i - 1) * 360 / math.max(n, 1))
			local holder = makeFrame(wheel, "Node_" .. element, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(math.floor(cx + rx * math.cos(a) + 0.5), math.floor(cy + r * math.sin(a) + 0.5)),
				Size = UDim2.fromOffset(96, 30),
				ZIndex = 3,
			})
			listLayout(holder, Enum.FillDirection.Horizontal, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
			local pill = elementPill(holder, element, 18, 1)
			pill.ZIndex = 3
			nodes[element] = { Pill = pill, Stroke = borderStroke(pill) }
			local mid = math.rad(-90 + (i - 0.5) * 360 / math.max(n, 1))
			makeText(wheel, "Arrow" .. i, GL.Arrow, "Heading", 20, Theme.Lighten(GOLD, 0.2), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(math.floor(cx + (rx - 4) * math.cos(mid) + 0.5), math.floor(cy + (r - 4) * math.sin(mid) + 0.5)),
				Size = UDim2.fromOffset(26, 26),
				Rotation = math.deg(atan2(r * math.cos(mid), -rx * math.sin(mid))),
				ZIndex = 2,
			})
		end
		local row = makeFrame(wheel, "Rivals", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 32),
		})
		listLayout(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		for i, pair in ipairs(rivals) do
			local a = elementPill(row, pair[1], 18, i * 3)
			autoText(row, "Both" .. i, GL.Both, "Heading", 22, Theme.Lighten(GOLD, 0.2), i * 3 + 1)
			local b = elementPill(row, pair[2], 18, i * 3 + 2)
			nodes[pair[1]] = { Pill = a, Stroke = borderStroke(a) }
			nodes[pair[2]] = { Pill = b, Stroke = borderStroke(b) }
		end
		return wheel, nodes
	end

	local function clearChildren(frame)
		for _, child in ipairs(frame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- one synergy / matchup row: pills + a text
	local function synergyRow(parent, order, pills, text, color)
		local row = makeFrame(parent, "Row" .. order, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
		})
		listLayout(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		for i, p in ipairs(pills) do
			if p.Element then
				elementPill(row, p.Element, 18, i)
			else
				colorPill(row, "Tag" .. i, p.Text, p.Color, 18, i)
			end
		end
		if text and text ~= "" then
			makeText(row, "Text", text, "Body", 19, color or WHITE, {
				Size = UDim2.new(1, -(#pills * 110), 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 50,
			})
		end
		return row
	end

	-- the Team window's layout for a window size (design px); split out of P3.BuildTeam: Lua's 60-upvalue limit
	local function layoutTeam(ui, w, h, narrow, short, tall)
		ui.Tall = tall
		local cw = w - INSET_X -- Panel.Content
		local cardH = short and CARD_H_SHORT or CARD_H
		local topH = tall and 108 or 50
		ui.Top.Size = UDim2.new(1, -28, 0, topH)
		if tall then
			ui.TabRow.Size = UDim2.new(1, 0, 0, 48)
			ui.Chips.AnchorPoint = Vector2.new(0, 0)
			ui.Chips.Position = UDim2.fromOffset(0, 58)
			local tabW = math.floor((cw - 28 - 2 * 8) / 3)
			for i = 1, PRESETS do
				ui.Tabs[i].Size = UDim2.fromOffset(math.min(152, tabW), 46)
			end
		else
			ui.TabRow.Size = UDim2.new(0, 3 * 160, 1, 0)
			ui.Chips.AnchorPoint = Vector2.new(1, 0.5)
			ui.Chips.Position = UDim2.new(1, 0, 0.5, 0)
			for i = 1, PRESETS do
				ui.Tabs[i].Size = UDim2.fromOffset(narrow and 128 or 152, 46)
			end
		end
		ui.PowerCaption.Text = (tall or narrow) and "Power" or "Team Power"
		local bodyTop = 10 + topH + 10
		local colW
		if tall then
			-- one scrolling column: slots, actions, synergy, wheel, then the picker
			ui.Left.Position = UDim2.fromOffset(14, bodyTop)
			ui.Left.Size = UDim2.new(1, -28, 1, -(bodyTop + 8))
			ui.Right.Visible = false
			ui.PickerHead.Parent = ui.Left
			ui.PickerHead.LayoutOrder = 4
			ui.Grid.Parent = ui.Left
			ui.Grid.LayoutOrder = 5
			ui.Empty.Parent = ui.Left
			ui.Empty.LayoutOrder = 6
			colW = cw - 28 - 14
			ui.SlotGrid.CellSize = UDim2.fromOffset(colW, cardH)
			ui.Slots.Size = UDim2.new(1, 0, 0, 4 * cardH + 3 * CARD_GAP)
			ui.Actions.Size = UDim2.new(1, 0, 0, 108)
			ui.HelpText.Position = UDim2.fromOffset(0, 58)
			ui.HelpText.Size = UDim2.new(1, 0, 0, 48)
			ui.HelpText.Visible = true
			local synH = 200
			ui.Row.Size = UDim2.new(1, 0, 0, synH + 12 + WHEEL_H)
			ui.Synergy.Size = UDim2.new(1, 0, 0, synH)
			ui.Wheel.AnchorPoint = Vector2.new(0.5, 0)
			ui.Wheel.Position = UDim2.new(0.5, 0, 0, synH + 12)
			local cols = math.max(2, math.floor((colW + 10) / (TILE_W + 10)))
			local tileW = math.min(TILE_W + 20, math.floor((colW - (cols - 1) * 10) / cols))
			ui.GridLayout.CellSize = UDim2.fromOffset(tileW, TILE_H)
		else
			ui.Right.Visible = true
			ui.PickerHead.Parent = ui.RightScroll
			ui.PickerHead.LayoutOrder = 1
			ui.Grid.Parent = ui.RightScroll
			ui.Grid.LayoutOrder = 2
			ui.Empty.Parent = ui.RightScroll
			ui.Empty.LayoutOrder = 3
			local tileW = short and TILE_W_SHORT or TILE_W
			-- the picker holds 3 tiles a row (2 on narrow windows); the team column gets the rest
			local cols = narrow and 2 or 3
			local pickerW = cols * tileW + (cols - 1) * 10 + 12 + 22 + 12
			ui.Right.AnchorPoint = Vector2.new(1, 0)
			ui.Right.Position = UDim2.new(1, -14, 0, bodyTop)
			ui.Right.Size = UDim2.new(0, pickerW, 1, -(bodyTop + 12))
			ui.Left.Position = UDim2.fromOffset(14, bodyTop)
			ui.Left.Size = UDim2.new(1, -(pickerW + 40), 1, -(bodyTop + 12))
			colW = cw - pickerW - 40 - 14
			local twoCols = colW >= 2 * 300 + CARD_GAP
			local cardW = twoCols and math.floor((colW - CARD_GAP) / 2) or colW
			ui.SlotGrid.CellSize = UDim2.fromOffset(cardW, cardH)
			local rows = twoCols and 2 or 4
			ui.Slots.Size = UDim2.new(1, 0, 0, rows * cardH + (rows - 1) * CARD_GAP)
			ui.Actions.Size = UDim2.new(1, 0, 0, 52)
			ui.HelpText.Position = UDim2.fromOffset(250, 0)
			ui.HelpText.Size = UDim2.new(1, -384, 1, 0)
			ui.HelpText.Visible = colW >= 560
			local sideBySide = colW >= WHEEL_W + 12 + 280
			if sideBySide then
				ui.Row.Size = UDim2.new(1, 0, 0, WHEEL_H)
				ui.Synergy.Size = UDim2.new(1, -(WHEEL_W + 12), 1, 0)
				ui.Wheel.AnchorPoint = Vector2.new(1, 0)
				ui.Wheel.Position = UDim2.new(1, 0, 0, 0)
			else
				ui.Row.Size = UDim2.new(1, 0, 0, 200 + 12 + WHEEL_H)
				ui.Synergy.Size = UDim2.new(1, 0, 0, 200)
				ui.Wheel.AnchorPoint = Vector2.new(0.5, 0)
				ui.Wheel.Position = UDim2.new(0.5, 0, 0, 212)
			end
			ui.GridLayout.CellSize = UDim2.fromOffset(tileW, short and TILE_H_SHORT or TILE_H)
		end
		ui.UseButton.Position = UDim2.fromOffset(0, 0)
		ui.ActiveLabel.Position = UDim2.fromOffset(4, 0)
		ui.ClearButton.Position = UDim2.new(1, 0, 0, 0)
		for _, card in ipairs(ui.Cards) do
			layoutCard(card, cardH)
		end
	end

	-- the Team window's contents from State (split out of P3.BuildTeam: Lua's 60-upvalue limit)
	local function refreshTeamUi(ui, fillTiles)
		local preset = T.Edit or activePreset()
		T.Edit = preset
		local active = activePreset()
		local keys = keysOf(preset)
		local slots = slotCount()
		-- preset tabs
		for i = 1, PRESETS do
			local tab = ui.Tabs[i]
			tab.Text = (i == active and (G.Star .. " ") or "") .. "Team " .. i
			CloudUI.SetStyle(tab, i == preset and "Blue" or "Gray")
		end
		-- slot cards
		local entries = {}
		local slotOf = {}
		for i, key in ipairs(keys) do
			slotOf[key] = i
			local entry = entryOf(key)
			if entry then
				entries[#entries + 1] = entry
			end
		end
		for i = 1, MAX_SLOTS do
			local card = ui.Cards[i]
			local key = keys[i]
			local entry = key and entryOf(key) or nil
			paintCard(card, key, entry, i > slots, T.Selected == i)
			card.Special.Visible = card.Special.Visible and card.ShowSpecial == true
		end
		-- power, trophies
		local power = tonumber(catalogCall("TeamPower", entries)) or 0
		ui.PowerText.Text = GL.Swords .. " " .. commas(power)
		ui.TrophyText.Text = GL.Trophy .. " " .. commas(battleData().Trophies or 0)
		-- actions
		local isActive = preset == active
		ui.UseButton.Visible = not isActive
		ui.UseButton.Text = "Use Team " .. preset
		CloudUI.SetDisabled(ui.UseButton, #keys == 0)
		ui.ActiveLabel.Visible = isActive
		CloudUI.SetDisabled(ui.ClearButton, #keys == 0)
		if #keys == 0 then
			ui.HelpText.Text = "Tap pets to build this team: the FIGHTER battles, two HELPERS back it up."
		elseif T.Selected then
			ui.HelpText.Text = "Now tap a pet to put it in slot " .. T.Selected .. "."
		else
			ui.HelpText.Text = "Tap a pet to add it. Tap a slot, then a pet, to swap."
		end

		-- synergy (live) + matchups
		clearChildren(ui.SynergyList)
		makeText(ui.SynergyList, "Title", "Synergy", "Heading", 22, WHITE, {
			Size = UDim2.new(1, 0, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 0,
		})
		local bonus = catalogCall("SynergyBonus", entries)
		local list = type(bonus) == "table" and bonus.Entries or {}
		local order = 1
		for _, s in ipairs(list) do
			local pills = {}
			if s.Element then
				pills[1] = { Element = s.Element }
			else
				pills[1] = { Text = tostring(s.Name or "Bonus"), Color = TEAL }
			end
			synergyRow(ui.SynergyList, order, pills, tostring(s.Text or ""), GOOD_TEXT)
			order = order + 1
		end
		if #list == 0 then
			local text = #entries == 0 and "Add pets to see their bonuses." or "No bonus yet: mix in a pet of the same element!"
			local label = makeText(ui.SynergyList, "None", text, "Body", 19, MUTED, {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = order,
			})
			label.Name = "None"
			order = order + 1
		end
		-- the team's matchups: which elements it hits hard, which hit it hard
		local teamElements, seen = {}, {}
		for _, entry in ipairs(entries) do
			for _, e in ipairs(elementsOf(entry.Def)) do
				if not seen[e] then
					seen[e] = true
					teamElements[#teamElements + 1] = e
				end
			end
		end
		if #teamElements > 0 then
			local strong, weak, sSeen, wSeen = {}, {}, {}, {}
			local S = (Config.Elements and Config.Elements.Strong) or {}
			for _, e in ipairs(teamElements) do
				for _, target in ipairs(S[e] or {}) do
					if not sSeen[target] then
						sSeen[target] = true
						strong[#strong + 1] = { Element = target }
					end
				end
			end
			for _, attacker in ipairs((Config.Elements and Config.Elements.Order) or {}) do
				for _, target in ipairs(S[attacker] or {}) do
					if seen[target] and not wSeen[attacker] then
						wSeen[attacker] = true
						weak[#weak + 1] = { Element = attacker }
					end
				end
			end
			if #strong > 0 then
				makeText(ui.SynergyList, "StrongTitle", "Hits hard against", "Heading", 19, GOOD_TEXT, {
					Size = UDim2.new(1, 0, 0, 26),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 20,
				})
				synergyRow(ui.SynergyList, 21, strong, nil)
			end
			if #weak > 0 then
				makeText(ui.SynergyList, "WeakTitle", "Watch out for", "Heading", 19, WARN_TEXT, {
					Size = UDim2.new(1, 0, 0, 26),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 22,
				})
				synergyRow(ui.SynergyList, 23, weak, nil)
			end
		end
		-- the rules, always at the bottom (BattleCatalog.SynergyRules)
		local BC = battleCatalog()
		local rules = BC and type(BC.SynergyRules) == "table" and BC.SynergyRules or nil
		if rules and type(rules.SameElement) == "table" then
			local function pct(v)
				return tostring(math.floor((tonumber(v) or 0) * 100 + 0.5)) .. "%"
			end
			local same = rules.SameElement
			makeText(ui.SynergyList, "Rules", "Same element: 2 pets +" .. pct(same[2]) .. ", 3 +" .. pct(same[3])
				.. " Power. " .. tostring(rules.BalancedElements or 3) .. "+ elements: +" .. pct(rules.BalancedHealth) .. " Health.", "Body", 18, MUTED, {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 40,
			})
		end
		-- wheel: the team's elements glow gold
		for element, node in pairs(ui.WheelNodes) do
			if node.Stroke then
				node.Stroke.Color = seen[element] and GOLD or NAVY
				node.Stroke.Thickness = seen[element] and 3.5 or 2
			end
			node.Pill.BackgroundTransparency = seen[element] and 0 or 0.25
		end

		-- picker: every owned copy, strongest first
		local owned = P2.ownedKeys()
		local rows = {}
		local ownedSet = {}
		for _, key in ipairs(owned) do
			local entry = entryOf(key)
			if entry then
				ownedSet[key] = true
				rows[#rows + 1] = { Key = key, Entry = entry, Power = unitPower(entry), Name = P2.displayName(key, entry.Def) }
			end
		end
		table.sort(rows, function(a, b)
			if a.Power ~= b.Power then
				return a.Power > b.Power
			end
			return a.Name < b.Name
		end)
		for key, tile in pairs(ui.Tiles) do
			if not ownedSet[key] then
				if tile.Viewport then
					tile.Viewport.Destroy()
				end
				tile.Button:Destroy()
				ui.Tiles[key] = nil
				ui.Ready[key] = nil
			end
		end
		ui.Order = {}
		for index, row in ipairs(rows) do
			local tile = ui.Tiles[row.Key] or buildTile(ui, row.Key)
			if tile.Viewport and tile.ViewStage ~= P2.stage(row.Key) then
				tile.Viewport.Destroy()
				tile.Viewport = nil
				ui.Ready[row.Key] = nil
			end
			tile.Button.LayoutOrder = index
			ui.Order[index] = row.Key
			local busy = nil
			if P2.job(row.Key) then
				busy = "Training"
			elseif P2.isGardening(row.Key) then
				busy = G.Seedling .. " Gardening" -- bug batch 2 #18: a tap asks to take it out of the garden
			end
			paintTile(tile, row.Entry, slotOf[row.Key], busy)
		end
		ui.Grid.Visible = #rows > 0
		ui.Empty.Visible = #rows == 0
		fillTiles()
	end

	----------------------------------------------------------------------
	-- The window
	----------------------------------------------------------------------
	function P3.BuildTeam(win)
		local content = win.Panel.Content
		local ui = { Cards = {}, Tiles = {}, Ready = {}, Order = {} }
		win.TeamUi = ui

		-- top bar: the three presets (left), team power + trophies (right)
		ui.Top = makeFrame(content, "TopBar", { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 50) })
		ui.TabRow = makeFrame(ui.Top, "Presets", { Size = UDim2.new(0, 3 * 160, 1, 0) })
		listLayout(ui.TabRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		ui.Tabs = {}
		for i = 1, PRESETS do
			ui.Tabs[i] = CloudUI.Button({
				Name = "Preset" .. i,
				Text = "Team " .. i,
				Size = UDim2.fromOffset(152, 46),
				Style = "Gray",
				TextSize = 22,
				LayoutOrder = i,
				Parent = ui.TabRow,
				Callback = function()
					T.Edit = i
					T.Selected = nil
					refreshTeam()
				end,
			})
		end
		ui.Chips = makeFrame(ui.Top, "Chips", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(0, 48),
			AutomaticSize = Enum.AutomaticSize.X,
		})
		listLayout(ui.Chips, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
		local powerChip = chip(ui.Chips, "PowerChip", 1)
		ui.PowerCaption = autoText(powerChip, "Caption", "Team Power", "Heading", 19, MUTED, 1)
		ui.PowerText = autoText(powerChip, "Value", GL.Swords .. " 0", "Display", 28, POWER_GOLD, 2)
		local trophyChip = chip(ui.Chips, "TrophyChip", 2)
		ui.TrophyText = autoText(trophyChip, "Value", GL.Trophy .. " 0", "Display", 28, WHITE, 1)
		CloudUI.Tooltip(trophyChip, function()
			local b = battleData()
			return "Trophies: win duels in the Battle Arena (" .. commas(b.PvPWins or 0) .. " won, " .. commas(b.PvPLosses or 0) .. " lost)"
		end)

		-- sections (placed by OnLayout: two columns, or one scrolling column on portrait phones)
		ui.Left = scroller(content, "Left", {})
		pad(ui.Left, 2, 4, 12, 8)
		listLayout(ui.Left, Enum.FillDirection.Vertical, 12)
		ui.Right = makeInset(content, "Right", {})
		ui.RightScroll = scroller(ui.Right, "PickerScroll", { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12) })
		pad(ui.RightScroll, 8, 6, 14, 10)
		listLayout(ui.RightScroll, Enum.FillDirection.Vertical, 8)

		ui.Slots = makeFrame(ui.Left, "Slots", { Size = UDim2.new(1, 0, 0, 262), LayoutOrder = 1 })
		ui.SlotGrid = Util.Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(160, 262),
			CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			Parent = ui.Slots,
		})
		for i = 1, MAX_SLOTS do
			buildCard(ui, ui.Slots, i)
		end

		ui.Actions = makeFrame(ui.Left, "Actions", { Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 2 })
		ui.UseButton = CloudUI.Button({
			Name = "UseTeam",
			Text = "Use this team",
			Size = UDim2.fromOffset(236, 50),
			Style = "Green",
			TextSize = 22,
			Parent = ui.Actions,
			Callback = function()
				safe("team select", selectPreset)
			end,
		})
		ui.ActiveLabel = makeText(ui.Actions, "ActiveLabel", G.Star .. " Your battle team", "Title", 24, GOLD, {
			Size = UDim2.fromOffset(260, 50),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		ui.ClearButton = CloudUI.Button({
			Name = "ClearTeam",
			Text = "Clear",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(120, 50),
			Style = "Red",
			TextSize = 22,
			Parent = ui.Actions,
			Callback = function()
				safe("team clear", clearPreset)
			end,
		})
		ui.HelpText = makeText(ui.Actions, "Help", "Tap a pet to add it. Tap a slot, then a pet, to swap.", "Body", 18, MUTED, {
			Position = UDim2.fromOffset(250, 0),
			Size = UDim2.new(1, -380, 1, 0),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		ui.Row = makeFrame(ui.Left, "SynergyRow", { Size = UDim2.new(1, 0, 0, WHEEL_H), LayoutOrder = 3 })
		ui.Synergy = makeInset(ui.Row, "Synergy", { Size = UDim2.new(1, -(WHEEL_W + 12), 1, 0) })
		ui.SynergyList = scroller(ui.Synergy, "List", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) })
		pad(ui.SynergyList, 10, 6, 12, 8)
		listLayout(ui.SynergyList, Enum.FillDirection.Vertical, 8)
		ui.Wheel, ui.WheelNodes = buildWheel(ui.Row)
		ui.Wheel.AnchorPoint = Vector2.new(1, 0)
		ui.Wheel.Position = UDim2.new(1, 0, 0, 0)

		-- picker
		ui.PickerHead = makeFrame(ui.RightScroll, "PickerHead", { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1 })
		makeText(ui.PickerHead, "Title", "Your pets", "Title", 26, WHITE, {
			Size = UDim2.new(0.5, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		makeText(ui.PickerHead, "Sort", "Strongest first", "Heading", 18, MUTED, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		ui.Grid = makeFrame(ui.RightScroll, "PickerGrid", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
		})
		ui.GridLayout = Util.Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(TILE_W, TILE_H),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = ui.Grid,
		})
		-- (P5.emptyState, like the Pets page: wrapped text that grows, a button capped at the column's width)
		ui.Empty = P5.emptyState({
			Parent = ui.RightScroll,
			LayoutOrder = 3,
			Body = "No pets yet! Spin a roulette in the Shop to hatch a battle buddy.",
			BodySize = 19,
			ButtonName = "GoShop",
			ButtonW = 200,
			ButtonH = 50,
			Callback = function()
				safe("team shop", openWindow, "Shop", {})
			end,
		}).Frame

		-- viewports of the picker tiles: a few per frame (time budget), Low detail
		local function fillTiles()
			if ui.Filling then
				return
			end
			ui.Filling = true
			task.spawn(function()
				task.wait()
				while win.Shown do
					local more = false
					local budget = Warm.Budget()
					for _, key in ipairs(ui.Order) do
						local tile = ui.Tiles[key]
						if tile and not ui.Ready[key] then
							if not Warm.Allows(budget) then
								more = true
								break
							end
							ui.Ready[key] = true
							local def = P2.defOfKey(key)
							if def then
								local stage = P2.stage(key)
								local ok, handle = pcall(CloudUI.PetViewport, tile.View, def, UDim2.new(1, 0, 1, 0), {
									Spin = "sway",
									Animate = false,
									Detail = "Low",
									Evolved = stage >= 1 and stage or nil, -- Phase 5 (3.7)
									ZIndex = 2,
								})
								if ok then
									tile.Viewport = handle
									tile.ViewStage = stage
								end
							end
							budget.Count = budget.Count + 1
						end
					end
					if not more then
						break
					end
					task.wait()
				end
				ui.Filling = false
			end)
		end

		win.OnOpen = function(args)
			settleDrafts()
			local preset = args and tonumber(args.Preset)
			if preset and preset >= 1 and preset <= PRESETS then
				T.Edit = math.floor(preset)
			else
				T.Edit = activePreset()
			end
			T.Selected = nil
		end

		win.OnLayout = function(w, h, narrow, short, tall)
			layoutTeam(ui, w, h, narrow, short, tall)
		end

		win.Refresh = function()
			refreshTeamUi(ui, fillTiles)
		end
	end

	function refreshTeam()
		local win = windows.Team
		if win then
			refreshWindow(win)
		end
	end

	-- State.Changed: drafts the server confirmed are dropped before the windows refresh
	P3.Settle = settleDrafts
	P3.Battle = battleData
	P3.Refresh = function()
		refreshTeam()
	end
end
P3.Define()

----------------------------------------------------------------------
-- Roulette flow: BuyRoulette -> RouletteResult -> scrolling strip -> reveal card
----------------------------------------------------------------------
local function refreshShopWindow()
	refreshWindow(windows.Shop)
end

-- currency: nil / "Tokens" (the roulette's Cloud Token price) or "Gems" (Config.Gems; the gems-only Secret roulette
-- is always paid in Gems). The server checks the price, the balance and the paid-random-items policy again.
function requestSpin(rouletteId, currency)
	if Spin.Waiting or Spin.Stage then
		return
	end
	local roulette = findRoulette(rouletteId)
	if not roulette then
		return
	end
	if inMatch() then
		showHint("The shop is closed during a match.", "info")
		return
	end
	if roulette.GemsOnly then
		currency = "Gems"
	end
	if currency == "Gems" then
		local price = gemPriceOf(rouletteId)
		if not price then
			return
		end
		if gemRoulettesState() ~= "Open" then
			showHint("Gem roulettes are not available on this account right now.", "info")
			return
		end
		if P2.gemBalance() < price then
			showHint("You need " .. P2.gemAmount(price) .. " Gems for that roulette.", "bad")
			return
		end
		if not fire("BuyRoulette", rouletteId, "Gems") then
			return
		end
	else
		currency = "Tokens"
		if State.Tokens() < roulette.Price then
			showHint("You need " .. cloudAmount(roulette.Price) .. " for that roulette.", "bad")
			return
		end
		if not fire("BuyRoulette", rouletteId) then
			return
		end
	end
	-- the answer takes a round trip: use it to sculpt this pool first
	Spin.Last = rouletteId
	Spin.LastCurrency = currency
	Warm.Roulette(rouletteId, true)
	Spin.Waiting = true
	Spin.WaitToken = Spin.WaitToken + 1
	local mine = Spin.WaitToken
	refreshShopWindow()
	task.delay(K.WAIT_TIMEOUT, function()
		if Spin.Waiting and Spin.WaitToken == mine then
			Spin.Waiting = false
			refreshShopWindow()
			showHint("The roulette did not answer. Try again.", "bad")
		end
	end)
end

-- Confetti squares flying out of `centre` (a UDim2 inside `parent`).
local function burst(parent, color, amount, centre)
	local rng = Random.new()
	for i = 1, amount do
		local size = rng:NextInteger(8, 15)
		local pick = i % 3
		local pieceColor = Theme.Lighten(color, 0.5)
		if pick == 0 then
			pieceColor = GOLD
		elseif pick == 1 then
			pieceColor = color
		end
		local piece = makeFrame(parent, "Confetti", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = centre,
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 0,
			BackgroundColor3 = pieceColor,
			Rotation = rng:NextInteger(0, 90),
			ZIndex = 10,
		})
		if i % 2 == 0 then
			round(piece)
		else
			corner(piece, 2)
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(80, 230)
		local target = UDim2.new(
			centre.X.Scale,
			centre.X.Offset + math.cos(angle) * distance,
			centre.Y.Scale,
			centre.Y.Offset + math.sin(angle) * distance * 0.8 - 24
		)
		local seconds = rng:NextNumber(0.7, 1.2)
		tween(piece, seconds, { Position = target, Rotation = piece.Rotation + rng:NextInteger(-220, 220) })
		tween(piece, seconds, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, seconds + 0.1)
	end
end

-- Closes the stage (strip or reveal card) and starts the next queued result, if any.
function closeStage()
	local stage = Spin.Stage
	if not stage then
		return
	end
	Spin.Stage = nil
	syncBackBinding()
	stage.Phase = "closed"
	if stage.Conn then
		stage.Conn:Disconnect()
		stage.Conn = nil
	end
	for _, cell in pairs(stage.Cells) do
		if cell.Viewport then
			pcall(cell.Viewport.Destroy)
		end
	end
	stage.Cells = {}
	if stage.RevealViewport then
		pcall(stage.RevealViewport.Destroy)
		stage.RevealViewport = nil
	end
	if stage.Root then
		stage.Root:Destroy()
		stage.Root = nil
	end
	refreshShopWindow()
	local nextResult = table.remove(Spin.Queue, 1)
	if nextResult then
		task.delay(0.15, function()
			if not Spin.Stage then
				beginStage(nextResult)
			end
		end)
	end
end

function skipSpin()
	local stage = Spin.Stage
	if stage and stage.Phase ~= "reveal" then
		stage.Skip = true
	end
end

-- Reveal card layout: tall (portrait card) when the screen has the height, else a landscape card.
local function revealLayout()
	local factor = screenFactor()
	local area = guiSize()
	local tall = (area.Y - 2 * K.MARGIN) / factor >= K.REVEAL.TallH + 28
	if tall then
		return {
			Wide = false,
			W = K.REVEAL.TallW,
			H = K.REVEAL.TallH,
			View = UDim2.new(0.5, 0, 0, 150),
			ViewSize = 260,
			Name = { UDim2.fromOffset(0, 292), UDim2.new(1, 0, 0, 40), Enum.TextXAlignment.Center },
			Meta = { UDim2.fromOffset(0, 338), UDim2.new(1, 0, 0, 30), Enum.HorizontalAlignment.Center },
			Perks = { UDim2.fromOffset(16, 378), UDim2.new(1, -32, 0, 72), Enum.TextXAlignment.Center },
			Buttons = { UDim2.fromOffset(0, 462), UDim2.new(1, 0, 0, 60), Enum.HorizontalAlignment.Center },
		}
	end
	return {
		Wide = true,
		W = K.REVEAL.WideW,
		H = K.REVEAL.WideH,
		View = UDim2.new(0, 170, 0.5, 0),
		ViewSize = 240,
		Name = { UDim2.fromOffset(340, 14), UDim2.new(1, -356, 0, 42), Enum.TextXAlignment.Left },
		Meta = { UDim2.fromOffset(340, 62), UDim2.new(1, -356, 0, 30), Enum.HorizontalAlignment.Left },
		Perks = { UDim2.fromOffset(340, 100), UDim2.new(1, -356, 0, 84), Enum.TextXAlignment.Left },
		Buttons = { UDim2.fromOffset(340, 196), UDim2.new(1, -356, 0, 60), Enum.HorizontalAlignment.Left },
	}
end

local function fitStage(w, h)
	local area = guiSize()
	local factor = screenFactor()
	return Util.Clamp(math.min(factor, (area.X - 2 * K.MARGIN) / w, (area.Y - 2 * K.MARGIN) / h), 0.3, 1.25)
end

function beginStage(result)
	local def = PetCatalog.Get(result.PetId)
	if not def or not gui then
		showHint("A new pet joined your collection!", "good")
		return
	end
	local roulette = findRoulette(result.RouletteId)
	local rarityColor = rarityOf(def)
	local accent = roulette and roulette.Color or rarityColor
	local stage = { Phase = "spin", Def = def, Result = result, Cells = {}, Elapsed = 0, X = 0, Tick = 0 }
	-- what paid this spin (RouletteResult.Currency; a gems-only roulette is always Gems)
	stage.Currency = (result.Currency == "Gems" or (roulette and roulette.GemsOnly)) and "Gems" or "Tokens"
	Spin.Stage = stage
	syncBackBinding()
	closeOdds()
	closeIndex()
	refreshShopWindow()

	local root = makeFrame(gui, "RouletteStage", { Size = UDim2.new(1, 0, 1, 0), ZIndex = 20 })
	stage.Root = root
	local dim = Util.Create("TextButton", {
		Name = "Dim",
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(8, 12, 32),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = root,
	})
	tween(dim, 0.25, { BackgroundTransparency = 0.3 })

	stage.Relayout = function()
		if stage.StripFit then
			stage.StripFit.Scale = fitStage(K.STAGE.W, K.STAGE.H)
		end
		if stage.RevealFit and stage.RevealSize then
			stage.RevealFit.Scale = fitStage(stage.RevealSize[1], stage.RevealSize[2])
		end
	end

	------------------------------------------------------------------
	-- the strip: server-provided list, repaired where it is invalid, with the winner at K.STRIP.Target
	------------------------------------------------------------------
	local pool = {}
	if roulette then
		pool = possiblePetsOf(roulette.Id)
	end
	if #pool == 0 then
		pool = PetCatalog.Pets or {}
	end
	local rng = Random.new()
	local function randomPetId()
		if #pool == 0 then
			return def.Id
		end
		return pool[rng:NextInteger(1, #pool)].Id
	end
	local raw = type(result.Strip) == "table" and result.Strip or {}
	local strip = {}
	for i = 1, math.max(#raw, K.STRIP.MinCells) do
		local id = raw[i]
		if type(id) ~= "string" or not PetCatalog.Get(id) then
			id = randomPetId()
		end
		strip[i] = id
	end
	local target = K.STRIP.Target
	strip[target] = def.Id
	local cellW = K.STRIP.Cell
	local startX = 0
	local endX = (target - 1) * cellW + cellW / 2 - K.STRIP.W / 2 + rng:NextNumber(-cellW * 0.26, cellW * 0.26)

	local stripHolder = makeFrame(root, "StripHolder", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.fromOffset(K.STAGE.W, K.STAGE.H),
		ZIndex = 2,
	})
	stage.StripFit = Util.Create("UIScale", { Name = "Fit", Scale = fitStage(K.STAGE.W, K.STAGE.H), Parent = stripHolder })
	local stripPanel = CloudUI.Panel({
		Name = "StripPanel",
		Title = roulette and roulette.DisplayName or "Roulette",
		Closable = false,
		Accent = accent,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = stripHolder,
	})
	local stripPop = Util.Create("UIScale", { Name = "Pop", Scale = 0.8, Parent = stripPanel.Root })
	tween(stripPop, 0.32, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local sc = stripPanel.Content

	local pointer = makeText(sc, "Pointer", G.Down, "Title", 36, GOLD, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(50, 40),
		ZIndex = 7,
	})
	local clip = makeFrame(sc, "StripClip", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(K.STRIP.W, K.STRIP.H),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.fromRGB(14, 22, 58),
		ClipsDescendants = true,
		ZIndex = 2,
	})
	corner(clip, 14)
	stroke(clip, WELL_EDGE, 3, 0)
	local band = makeFrame(clip, "Band", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(cellW, K.STRIP.H - 6),
		BackgroundTransparency = 0.88,
		BackgroundColor3 = GOLD,
		ZIndex = 5,
	})
	corner(band, 14)
	stroke(band, GOLD, 3, 0)
	for i = 1, 2 do
		local name = "FadeRight"
		local sequence = NumberSequence.new(1, 0)
		if i == 1 then
			name = "FadeLeft"
			sequence = NumberSequence.new(0, 1)
		end
		local fade = makeFrame(clip, name, {
			AnchorPoint = Vector2.new(i - 1, 0),
			Position = UDim2.new(i - 1, 0, 0, 0),
			Size = UDim2.new(0, 110, 1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(14, 22, 58),
			ZIndex = 6,
		})
		Util.Create("UIGradient", { Transparency = sequence, Parent = fade })
	end
	local status = makeText(sc, "Status", "Spinning...", "Heading", 22, MUTED, {
		Position = UDim2.fromOffset(18, 242),
		Size = UDim2.new(1, -170, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	CloudUI.Button({
		Name = "Skip",
		Text = "Skip",
		Style = "Blue",
		Size = UDim2.fromOffset(126, 46),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 240),
		TextSize = 21,
		Callback = function()
			skipSpin()
		end,
		Parent = sc,
	})

	-- cells are created only while they are near the window (one viewport per visible pet). A cell's frame
	-- (rarity colours) appears at once; its pet viewport (PetBuilder Low: small, static, moving fast) is attached
	-- under the per-frame time budget, so a pet that was never sculpted on this client cannot stall the strip.
	local cells = stage.Cells
	local function destroyCell(index)
		local cell = cells[index]
		if cell then
			cells[index] = nil
			if cell.Viewport then
				pcall(cell.Viewport.Destroy)
			end
			cell.Frame:Destroy()
		end
	end
	local function attachViewport(cell)
		if cell.Viewport then
			return
		end
		cell.Viewport = CloudUI.PetViewport(cell.Frame, cell.Def, UDim2.new(1, -8, 1, -24), {
			Position = UDim2.new(0.5, 0, 0, 4),
			AnchorPoint = Vector2.new(0.5, 0),
			Animate = false,
			Spin = "sway",
			Detail = K.STRIP_DETAIL,
			ZIndex = 2,
		})
	end
	local function makeCell(index)
		local cellDef = PetCatalog.Get(strip[index])
		local color = rarityOf(cellDef)
		local frame = makeFrame(clip, "Cell" .. index, {
			Size = UDim2.fromOffset(cellW - 10, K.STRIP.H - 18),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			ZIndex = 2,
		})
		corner(frame, 14)
		local frameStroke = stroke(frame, color, 3, 0)
		Theme.Gradient(frame, Colors.Mist, Colors.MistDeep:Lerp(color, 0.5), 90)
		local tag = makeFrame(frame, "RarityBar", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -24, 0, 10),
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
		})
		round(tag)
		local cell = { Frame = frame, Viewport = nil, Stroke = frameStroke, Def = cellDef }
		cells[index] = cell
		return cell
	end
	local function layoutCells(x)
		local first = math.max(1, math.floor(x / cellW))
		local last = math.min(#strip, math.floor((x + K.STRIP.W) / cellW) + 2)
		for index = first, last do
			local cell = cells[index] or makeCell(index)
			cell.Frame.Position = UDim2.fromOffset(math.floor((index - 1) * cellW - x + 5 + 0.5), 9)
		end
		for index in pairs(cells) do
			if index < first or index > last then
				destroyCell(index)
			end
		end
		-- pet viewports, nearest to the pointer first, under the frame's build budget
		local budget = Warm.Budget()
		local centre = (x + K.STRIP.W / 2) / cellW + 0.5
		while Warm.Allows(budget) do
			local best, bestD = nil, math.huge
			for index, cell in pairs(cells) do
				if not cell.Viewport then
					local d = math.abs(index - centre)
					if d < bestD then
						best, bestD = cell, d
					end
				end
			end
			if not best then
				break
			end
			attachViewport(best)
			budget.Count = budget.Count + 1
		end
	end
	layoutCells(startX)

	------------------------------------------------------------------
	-- reveal card
	------------------------------------------------------------------
	local function updateReveal()
		if stage.Phase ~= "reveal" or not stage.EquipBtn then
			return
		end
		local equipped = State.EquippedCount(def.Id)
		local owned = State.OwnedCount(def.Id)
		local total = #State.Get().Equipped
		if equipped > 0 and equipped >= owned then
			stage.EquipBtn.Text = "Equipped"
			CloudUI.SetDisabled(stage.EquipBtn, true)
		elseif total >= Config.Pets.MaxEquipped then
			stage.EquipBtn.Text = "Team full"
			CloudUI.SetDisabled(stage.EquipBtn, true)
		else
			stage.EquipBtn.Text = "Equip"
			CloudUI.SetDisabled(stage.EquipBtn, false)
		end
		if stage.AgainBtn and roulette then
			if stage.Currency == "Gems" then
				local price = gemPriceOf(roulette.Id) or 0
				stage.AgainBtn.Text = "Again " .. P2.gemAmount(price)
				CloudUI.SetDisabled(stage.AgainBtn, P2.gemBalance() < price or inMatch() or gemRoulettesState() ~= "Open")
			else
				stage.AgainBtn.Text = "Again " .. cloudAmount(roulette.Price)
				CloudUI.SetDisabled(stage.AgainBtn, State.Tokens() < roulette.Price or inMatch())
			end
		end
	end
	stage.UpdateReveal = updateReveal

	local function showReveal()
		stage.Phase = "reveal"
		Sfx.Play(Sfx.Reveal[tostring(def.Rarity)] or "RevealCommon")
		for index in pairs(cells) do
			destroyCell(index)
		end
		stripHolder:Destroy()
		stage.StripFit = nil

		local flash = makeFrame(root, "Flash", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 0.45,
			BackgroundColor3 = Theme.Lighten(rarityColor, 0.6),
			ZIndex = 9,
		})
		tween(flash, 0.55, { BackgroundTransparency = 1 })
		Debris:AddItem(flash, 0.7)

		local L = revealLayout()
		stage.RevealSize = { L.W, L.H }
		local holder = makeFrame(root, "RevealHolder", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 6),
			Size = UDim2.fromOffset(L.W, L.H),
			ZIndex = 2,
		})
		stage.RevealFit = Util.Create("UIScale", { Name = "Fit", Scale = fitStage(L.W, L.H), Parent = holder })
		local panel = CloudUI.Panel({
			Name = "RevealPanel",
			Title = string.upper(def.Rarity),
			Closable = true,
			Accent = def.Rarity == "Secret" and PURPLE or rarityColor,
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			OnClose = function()
				closeStage()
			end,
			Parent = holder,
		})
		local pop = Util.Create("UIScale", { Name = "Pop", Scale = 0.5, Parent = panel.Root })
		tween(pop, 0.5, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local c = panel.Content
		local order = rarityOrder(def.Rarity)
		local glowColor = def.Rarity == "Secret" and PURPLE or rarityColor

		-- slowly turning rays + soft glow discs behind the pet (stronger for rarer pets), clipped to the card
		local fxLayer = makeFrame(c, "RevealFx", {
			Size = UDim2.new(1, 0, 1, 0),
			ClipsDescendants = true,
			ZIndex = 1,
		})
		local raySize = L.ViewSize + 80
		local rays = makeFrame(fxLayer, "Rays", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = L.View,
			Size = UDim2.fromOffset(raySize, raySize),
			ZIndex = 1,
		})
		stage.Rays = rays
		local rayCount = 3 + order
		for i = 1, rayCount do
			local ray = makeFrame(rays, "Ray" .. i, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(0, 22, 1, 0),
				Rotation = (i - 1) * 180 / rayCount,
				BackgroundTransparency = 0.78 - order * 0.015,
				BackgroundColor3 = Theme.Lighten(glowColor, 0.4),
				ZIndex = 1,
			})
			Util.Create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = ray,
			})
		end
		for i, disc in ipairs({ { 1.0, 0.86 }, { 0.78, 0.8 }, { 0.58, 0.72 } }) do
			local glow = makeFrame(fxLayer, "Glow" .. i, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = L.View,
				Size = UDim2.fromOffset(L.ViewSize * disc[1], L.ViewSize * disc[1]),
				BackgroundTransparency = disc[2],
				BackgroundColor3 = Theme.Lighten(glowColor, 0.3),
				ZIndex = 1,
			})
			round(glow)
		end

		-- Phase 5 (3.7): a new copy shares its key's stored stage: an evolved key reveals its evolved form (Low) and a
		-- gold "Evolved" ribbon
		local rolledKey = (type(result.Key) == "string" and result.Key) or def.Id
		local evoStage = P2.stage(rolledKey)
		stage.RevealViewport = CloudUI.PetViewport(c, def, UDim2.fromOffset(L.ViewSize, L.ViewSize), {
			Position = L.View,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Spin = "spin",
			Excited = 1,
			Flap = 1.5,
			ZIndex = 3,
			Evolved = evoStage >= 1 and evoStage or nil,
			Detail = evoStage >= 1 and "Low" or nil,
		})
		if evoStage >= 1 then
			local ribbon = makeFrame(c, "EvolvedRibbon", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 14),
				Size = UDim2.fromOffset(evoStage >= 2 and 150 or 120, 36),
				Rotation = 8,
				BackgroundTransparency = 0,
				BackgroundColor3 = GOLD,
				ZIndex = 6,
			})
			corner(ribbon, 10)
			stroke(ribbon, NAVY, 3, 0)
			Theme.Gradient(ribbon, Theme.Lighten(GOLD, 0.3), Theme.Darken(GOLD, 0.12), 90)
			makeText(ribbon, "Text", string.rep(G.Star, math.min(2, evoStage)) .. (evoStage >= 2 and " Evolved II" or " Evolved"), "Button", 20, WHITE, {
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 7,
			})
		end

		-- NEW! flag (or the stack size for a duplicate)
		local isNew = result.IsNew == true
		local flag = makeFrame(c, "Flag", {
			Position = UDim2.fromOffset(10, 14),
			Size = UDim2.fromOffset(104, 40),
			Rotation = -10,
			BackgroundTransparency = 0,
			BackgroundColor3 = isNew and GOLD or BUTTONS.Blue,
			ZIndex = 6,
		})
		corner(flag, 10)
		stroke(flag, NAVY, 3, 0)
		local flagText = "NEW!"
		if not isNew then
			flagText = "x" .. tostring(math.floor(tonumber(result.Count) or State.OwnedCount(def.Id)))
		end
		makeText(flag, "Text", flagText, "Accent", 26, WHITE, {
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 7,
			TextStrokeColor3 = Theme.Darken(isNew and GOLD or BUTTONS.Blue, 0.65),
		})

		local nameLabel = makeText(c, "Name", def.Name, "Title", 34, rarityText(def), {
			Position = L.Name[1],
			Size = L.Name[2],
			TextXAlignment = L.Name[3],
			TextScaled = true,
			ZIndex = 4,
		})
		Util.Create("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 20, Parent = nameLabel })
		local meta = makeFrame(c, "Meta", { Position = L.Meta[1], Size = L.Meta[2], ZIndex = 4 })
		listLayout(meta, Enum.FillDirection.Horizontal, 8, L.Meta[3], Enum.VerticalAlignment.Center)
		local pill = readablePill(def.Rarity, rarityColor, meta)
		pill.LayoutOrder = 1
		for i, element in ipairs(elementsOf(def)) do
			elementPill(meta, element, 18, 1 + i)
		end
		makeText(meta, "Owned", "You own x" .. tostring(math.floor(tonumber(result.Count) or State.OwnedCount(def.Id))), "Heading", 19, MUTED, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 26),
			LayoutOrder = 10,
			ZIndex = 4,
		})
		local lines = perkLines(def)
		local perkText = "No perks"
		if #lines > 0 then
			perkText = table.concat(lines, "\n")
		end
		makeText(c, "Perks", perkText, "Heading", 19, Theme.Lighten(GOOD, 0.3), {
			Position = L.Perks[1],
			Size = L.Perks[2],
			TextXAlignment = L.Perks[3],
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 4,
		})

		local buttons = makeFrame(c, "Buttons", { Position = L.Buttons[1], Size = L.Buttons[2], ZIndex = 4 })
		listLayout(buttons, Enum.FillDirection.Horizontal, 12, L.Buttons[3], Enum.VerticalAlignment.Center)
		stage.EquipBtn = CloudUI.Button({
			Name = "Equip",
			Text = "Equip",
			Style = "Green",
			Size = UDim2.fromOffset(172, 58),
			TextSize = 26,
			LayoutOrder = 1,
			Callback = function()
				fire("EquipPet", def.Id)
			end,
			Parent = buttons,
		})
		if roulette then
			stage.AgainBtn = CloudUI.Button({
				Name = "Again",
				Text = "Again",
				Style = "Gold",
				Size = UDim2.fromOffset(204, 58),
				TextSize = 22,
				LayoutOrder = 2,
				Callback = function()
					local rouletteId = roulette.Id
					local currency = stage.Currency
					closeStage()
					task.defer(requestSpin, rouletteId, currency)
				end,
				Parent = buttons,
			})
		end
		updateReveal()

		-- confetti: more for rarer pets
		local amounts = { 10, 14, 20, 28, 36, 46, 56 }
		local amount = amounts[Util.Clamp(order, 1, #amounts)]
		task.delay(0.2, function()
			if Spin.Stage == stage and stage.Phase == "reveal" then
				burst(c, glowColor, amount, L.View)
			end
		end)
		if order >= 5 then
			task.delay(0.65, function()
				if Spin.Stage == stage and stage.Phase == "reveal" then
					burst(c, glowColor, amount, L.View)
				end
			end)
		end
	end

	------------------------------------------------------------------
	-- animation loop (client-only UI motion)
	------------------------------------------------------------------
	local function land()
		stage.Phase = "land"
		stage.LandedAt = os.clock()
		Sfx.Play("SpinLand")
		local winner = cells[target]
		if winner then
			attachViewport(winner) -- (normally attached long before it lands)
			winner.Stroke.Color = GOLD
			winner.Stroke.Thickness = 5
			winner.Frame.ZIndex = 4
			local grow = Util.Create("UIScale", { Scale = 1, Parent = winner.Frame })
			tween(grow, 0.35, { Scale = 1.1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if winner.Viewport then
				winner.Viewport.SetAnimated(true)
				winner.Viewport.SetExcited(1)
			end
		end
		status.Text = def.Rarity .. "!"
		status.TextColor3 = rarityText(def)
		band.BackgroundTransparency = 0.7
		pointer.Rotation = 0
	end

	local function step(dt)
		if stage.Phase == "spin" then
			if stage.Skip then
				stage.Elapsed = K.STRIP.Seconds
			end
			stage.Elapsed = stage.Elapsed + dt
			local t = Util.Clamp(stage.Elapsed / K.STRIP.Seconds, 0, 1)
			local p = 1 - (1 - t) ^ K.STRIP.Curve
			stage.X = startX + (endX - startX) * p
			layoutCells(stage.X)
			local tick = math.floor((stage.X + K.STRIP.W / 2) / cellW)
			if tick ~= stage.Tick then
				if stage.Tick ~= nil and not stage.Skip then
					Sfx.Play("SpinTick") -- a cell passes the pointer (a skip's jump stays silent: SpinLand follows)
				end
				stage.Tick = tick
				pointer.Rotation = 16
			end
			pointer.Rotation = pointer.Rotation * math.max(0, 1 - dt * 11)
			if t >= 1 then
				land()
			end
		elseif stage.Phase == "land" then
			if stage.Skip or os.clock() - stage.LandedAt > 0.95 then
				showReveal()
			end
		elseif stage.Phase == "reveal" then
			if stage.Rays then
				stage.Rays.Rotation = (stage.Rays.Rotation + dt * 22) % 360
			end
		end
	end

	Sfx.Play("SpinStart")
	stage.Conn = RunService.RenderStepped:Connect(function(dt)
		if Spin.Stage ~= stage then
			return
		end
		local ok, err = pcall(step, dt)
		if not ok then
			warnOnce("stage", err)
			if stage.Phase == "reveal" or stage.Failed then
				closeStage()
			else
				stage.Failed = true
				if not pcall(showReveal) then
					closeStage()
				end
			end
		end
	end)
end

local function onRouletteResult(result)
	Spin.Waiting = false
	Spin.WaitToken = Spin.WaitToken + 1
	if type(result) ~= "table" then
		refreshShopWindow()
		return
	end
	if result.Ok == false or type(result.PetId) ~= "string" then
		local reason = "The spin failed."
		if type(result.Reason) == "string" and result.Reason ~= "" then
			reason = result.Reason
		end
		showHint(reason, "bad")
		refreshShopWindow()
		return
	end
	if Spin.Stage then
		table.insert(Spin.Queue, result)
	else
		beginStage(result)
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
		-- (no CareController in this build: the Pets panel on that pet)
		args = { Tab = "Pets", Key = args.Key }
		key = "pets"
	end
	if key == "shop" then
		if inMatch() then
			return
		end
		openWindow("Shop", args)
	elseif key == "inventory" or key == "items" then
		openWindow("Inventory", args)
	elseif key == "pets" then
		openWindow("Inventory", { Tab = "Pets", Action = args.Action, Key = args.Key })
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
	elseif key == "team" or key == "teams" then
		openWindow("Team", args)
	elseif key == "close" then
		closeEverything()
	end
end

local function onStateChanged()
	-- red dot on the Pets tile when the collection grew while the inventory was closed
	local _, total = petTotals()
	local inventory = windows.Inventory
	if Badge.LastPetTotal ~= nil and total > Badge.LastPetTotal and not (inventory and inventory.Shown) then
		if Entries.Pets then
			Entries.Pets.SetBadge(true)
		end
	end
	Badge.LastPetTotal = total
	refreshIndexBadge()
	if P3.Settle then
		safe("team settle", P3.Settle)
	end

	for _, win in pairs(windows) do
		refreshWindow(win)
	end
	if Spin.Stage and Spin.Stage.UpdateReveal then
		safe("reveal", Spin.Stage.UpdateReveal)
	end
end

local function onTokensChanged()
	refreshOpenWindow()
	if Spin.Stage and Spin.Stage.UpdateReveal then
		safe("reveal", Spin.Stage.UpdateReveal)
	end
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
		closeEverything()
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
	local okSpin, spinRemote = pcall(Remotes.Get, "RouletteResult")
	if okSpin and spinRemote then
		spinRemote.OnClientEvent:Connect(function(result)
			safe("RouletteResult", onRouletteResult, result)
		end)
	else
		warn("[MenuController] RouletteResult remote is unavailable: " .. tostring(spinRemote))
	end
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
					closeOdds()
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

-- The menu's side hint (CareController's local refusals use it too; never in the screen centre).
function MenuController.Hint(text, kind)
	if initialized and type(text) == "string" then
		showHint(text, kind)
	end
end

-- true while a window, the odds popup or the roulette stage covers the screen (the tutorial folds its card and
-- hides its menu pointer meanwhile)
function MenuController.IsOpen()
	return openId ~= nil or Odds.Gui ~= nil or Spin.Stage ~= nil
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
		U.Tab.Visible = not U.ColumnHidden
	end
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

-- Debug helper (smoke tests): true once `petId` was pre-sculpted at the roulette strip's detail.
function MenuController.IsPrewarmed(petId)
	return Warm.Done[petId] == true
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
	createWindow({ Id = "Inventory", Title = "Pets", Category = "Pets", Build = buildInventory, Tall = true })
	createWindow({ Id = "Shop", Title = "Cloud Shop", Category = "Shop", Build = buildShop, Tall = true })
	createWindow({ Id = "Stats", Title = "Stats", Category = "Stats", Build = buildStats, Tall = true })
	createWindow({ Id = "Home", Title = "My Home", Category = "Home", Build = buildHome, Tall = true })
	createWindow({ Id = "Team", Title = "Battle Team", Category = "Team", Build = P3.BuildTeam, Tall = true })
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
	-- Phase 2: Cash / Gems balances (prices turn red / green), the gem roulette policy, the claimed plot
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
	LocalPlayer:GetAttributeChangedSignal(K.RESTRICTED_ATTR):Connect(function()
		safe("policy", refreshShopWindow)
	end)
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
	task.spawn(connectRemotes)
	P5.watchSheets()
end

return MenuController
