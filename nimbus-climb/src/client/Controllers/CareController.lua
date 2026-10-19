-- CareController (client, Phase 4): the pet-care windows of ARCHITECTURE_V3.md "Phase 4 build contract" 3.4-3.7.
--
--   CareController.Init()
--   CareController.Open(panelId, args)   panelId = "Feed" | "Garden" | "Train" | "Evolve"
--       Feed    the Food Machine window (args.Key = the pet to show first): one row per owned pet copy, garden pets
--               first, then the followers, then the rest; each row has the pet, its name and stars, "Lv 57 / 100", the
--               XP bar, "Feed $340 (+90 XP)" (or "Feed (free Feast, 3 left)" while leftovers last), "Level up $1.2K"
--               (several feeds in ONE request, TycoonCatalog.FeedPrice per feed at the level it is eaten at) and
--               EVOLVE! when PetCatalog.CanEvolve says so; the footer lists the leftover food and the machine
--               ("Food Machine Lv 2: each feed fills 30% of the bar. Upgrade to Lv 3 (35%): $320K" + Upgrade).
--               -> PetCare("Feed", key, nil | {Count = n}); HomeAction("Upgrade", "Kitchen")
--       Garden  the garden picker for one place (args.Slot): every pet copy (any role) with its coins per second;
--               "Put here" -> HomeAction("GardenSet", {Slot, Key}); "Take out" -> HomeAction("GardenSet", {Slot})
--       Train   the Training Place window (args.Key = the pet to select): the pets on the left, the four skills
--               (Attack Speed / Physique / Ability / Defense) of the selected pet on the right with a rank bar, the
--               next rank's cost and time (TycoonCatalog.TrainCost / TrainSeconds) and Train; a training pet shows
--               its timer and Stop. Train and Stop ask first. -> PetCare("Train", key, stat) / PetCare("TrainStop", key)
--       Evolve  the evolution moment (the server's OpenPanel("Evolve", {Key, Stage}) after PetCare("Evolve")): every
--               window closes, PetController.PlayEvolution parks the follower of that key, EvolutionFx plays on two
--               fresh PetBuilder clones 5.5 studs in front of the player (with confetti), then the evolved clone
--               flies home as the follower (release(position)) and goes away
--   CareController.Close()               closes the window and any confirm
--   CareController.IsOpen() -> true while a care window or a confirm is up
--   Extras: CareController.Mode() -> "Feed" | "Garden" | "Train" | nil, CareController.ConfirmEvolve(key) (the EVOLVE
--           confirm, used by the Pets panel too), CareController.FeedPlan(key, count) -> { Count, Price, Xp, Free,
--           Food, Levels } (what a request would do; the server decides), CareController.Evolving() -> plays running,
--           CareController.Opened / Closed (Util.Signal; Opened fires the mode)
--
-- How the windows open: the server's OpenPanel("Pets", {Action = "Feed"}) (FeedPrompt on the Food Machine) and
-- OpenPanel("Train") (TrainPrompt) arrive here; MenuController forwards OpenPanel("Pets", {Action = "Feed" | "Garden"})
-- calls made on the client; E on an own GardenSpotPrompt opens the picker for its Slot. One window at a time: opening
-- one closes the menu windows, the Pet Index and the Fusion Machine; those opening close it. Esc, the red X or a click
-- outside close it, so does entering a match.
-- The client never decides money, XP or ranks: every number shown comes from the catalogs and the synced profile and the
-- server checks every request again. Readability rule: 1080p design pixels (body 18-19, buttons 20, titles 28-32) under
-- ONE UIScale = min(screen factor, fit); the window keeps >= 14 px text on phones (portrait: one column, landscape:
-- the compact rows). Pet viewports use PetBuilder's Low detail and are attached under a per-frame time budget.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))
local State = require(Client:WaitForChild("State"))

local function safeRequire(name)
	local ok, result = pcall(function()
		local module = Shared:FindFirstChild(name) or Shared:WaitForChild(name, 5)
		return module and require(module) or nil
	end)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

local PetCatalog = safeRequire("PetCatalog") or { Get = function() return nil end }
local TycoonCatalog = safeRequire("TycoonCatalog")
local BattleCatalog = safeRequire("BattleCatalog")

local CareController = {}
CareController.Opened = Util.Signal()
CareController.Closed = Util.Signal()

----------------------------------------------------------------------
-- Tunables (design pixels of a 1080p screen unless noted)
----------------------------------------------------------------------
local K = {
	DISPLAY_ORDER = 23, -- above NimbusMenu (20), the Pet Index (21) and the Fusion Machine (22)
	MARGIN = 12,
	PREF_W = 600, -- Phase 5 (6.6): the Care window is docked right / a bottom sheet (NeonKit.Dock), 600 x 820 design px
	PREF_H = 820,
	SHORT = 560, -- below this design height: the compact rows (landscape phones)
	WIDE = 930, -- at least this wide: one-line rows (the buttons beside the bar)
	TALL_W = 720, -- less than this free (design px) on a portrait screen: one column
	ROW_H = 112,
	BUTTONS_W = 610, -- the one-line row's button block (Feed 276 + Level up 190 + EVOLVE 128 + gaps)
	ROW_H_STACKED = 176,
	ROW_H_SHORT = 100,
	ROW_H_SHORT_STACKED = 160,
	VIEW = 88,
	VIEW_SHORT = 72,
	TOP_H = 46,
	FOOT_H = 108,
	FOOT_H_SHORT = 74,
	TRAIN_LIST_W = 360,
	TRAIN_ROW_H = 84,
	SKILL_H = 104,
	SKILL_H_SHORT = 88,
	CONFIRM_W = 560,
	CONFIRM_H = 286,
	BUILD_BUDGET = 0.004, -- seconds of pet viewport building per frame (at least one per frame)
	FIRE_GAP = 0.3, -- client-side spacing between two sends of the same action
	TICK = 0.5, -- seconds between two timer refreshes while a window is open
	MAX_FEEDS = 10, -- "Level up": at most this many feeds in one request (the server's MAX_FEEDS)
	-- the evolution moment (contract 3.6)
	EVO_AHEAD = 5.5, -- studs in front of the player
	EVO_HOVER = 0.7, -- studs between the clone's lowest point and the ground
	EVO_REST = 1.3, -- seconds the evolved clone stays before it flies home as the follower
	EVO_DETAIL = "High",
	EVO_FOLDER = "CareEvolution",
	RAY = 60,
	BACK_ACTION = "NimbusCareBack",
}

local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.Navy or Colors.Ink
local MUTED = Colors.Muted or Colors.CloudShade
local GOLD = Colors.Gold or Colors.Token
local INK = Colors.TextStroke or Colors.Ink
local GOOD = Colors.Good
local BAD = Colors.Bad
local WELL_EDGE = Colors.WellEdge or NAVY
local INSET = Color3.fromRGB(20, 30, 70)
local CASH = Colors.Cash or Color3.fromRGB(112, 204, 98)
local XP = Color3.fromRGB(120, 200, 255)
local PURPLE = Color3.fromRGB(168, 118, 236)
local LOCK = Color3.fromRGB(255, 206, 120)
local ACCENTS = {
	Feed = Color3.fromRGB(240, 150, 80),
	Garden = Color3.fromRGB(110, 190, 90),
	Train = Color3.fromRGB(228, 104, 96),
}
local ROLE_COLORS = { Economy = Color3.fromRGB(96, 196, 108), Combat = Color3.fromRGB(228, 104, 96) }

-- glyphs as UTF-8 byte escapes (the source stays plain ASCII)
local G = {
	Star = "\226\152\133",
	Food = "\240\159\141\178", -- pot of food (the Food Machine)
	Seedling = "\240\159\140\177",
	Muscle = "\240\159\146\170",
	Lock = "\240\159\148\146",
	Bullet = "\194\183",
	Clock = "\226\143\177", -- stopwatch
	Sparkle = "\226\156\168",
	Berry = "\240\159\141\147", -- strawberry (Phase 5 berries)
}

local TITLES = {
	Feed = G.Food .. " Food Machine",
	Garden = G.Seedling .. " Pet Garden",
	Train = G.Muscle .. " Training Place",
}

local SKILLS = (BattleCatalog and type(BattleCatalog.TrainingSkills) == "table" and #BattleCatalog.TrainingSkills == 4)
		and BattleCatalog.TrainingSkills
	or {
		{ Id = "Speed", Name = "Attack Speed", Text = "+4% attacks per rank" },
		{ Id = "Physique", Name = "Physique", Text = "+5% max health per rank" },
		{ Id = "Ability", Name = "Ability", Text = "+4% special power and charge per rank" },
		{ Id = "Defense", Name = "Defense", Text = "-3% damage taken per rank" },
	}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local LocalPlayer = nil
local initialized = false
local S = {
	Open = false, -- a window is shown
	Mode = nil, -- "Feed" | "Garden" | "Train"
	Token = 0,
	Built = false,
	Focus = nil, -- Feed: the pet to show first
	Slot = nil, -- Garden: the place the picker fills
	TrainKey = nil, -- Train: the selected pet
	Short = false,
	Tall = false,
	Stacked = false,
	Confirm = nil, -- { Kind, Key, Stat, Yes = fn } while a confirm is up
	Evolving = 0,
	EvoQueue = {},
	Last = {}, -- last send per action key (os.clock)
	Filling = false,
	RefreshPending = false,
}
local U = { Rows = {}, GardenRows = {}, TrainRows = {}, Skills = {} } -- ui references
local H = {} -- helpers (one table: the module stays far below Lua's local limit)

local function warnOnce(key, err)
	S.Warned = S.Warned or {}
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[CareController] " .. tostring(key) .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok, err
end

----------------------------------------------------------------------
-- small UI helpers
----------------------------------------------------------------------
function H.frame(parent, name, props)
	local p = props or {}
	p.Name = name
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	p.BorderSizePixel = 0
	p.Parent = parent
	return Util.Create("Frame", p)
end

-- Theme-styled TextLabel (stroke + glyph outline: readable on any panel)
function H.text(parent, name, text, role, size, color, props)
	local p = { Name = name }
	if props then
		for k, v in pairs(props) do
			p[k] = v
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
	label.Parent = parent
	return label
end

function H.corner(parent, radius)
	return Theme.Corner(parent, UDim.new(0, radius or 12))
end

function H.stroke(parent, color, thickness, transparency)
	return Theme.Stroke(parent, color or NAVY, thickness or 3, transparency or 0)
end

function H.pad(parent, left, top, right, bottom)
	return Util.Create("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		Parent = parent,
	})
end

function H.list(parent, direction, gap, hAlign, vAlign)
	return Util.Create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or 0),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

function H.scroller(parent, name, props)
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

function H.inset(parent, name, props)
	local p = props or {}
	p.BackgroundColor3 = INSET
	p.BackgroundTransparency = 0.42
	local f = H.frame(parent, name, p)
	H.corner(f, 12)
	H.stroke(f, WELL_EDGE, 3, 0.15)
	return f
end

-- a solid coloured pill (role, status): white text with a dark outline of its own colour
function H.pill(parent, name, text, color, size, order)
	local dark = Theme.Darken(color, 0.62)
	local px = size or 18
	local pill = Theme.Label(text, "Heading", {
		Size = px,
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
			Size = UDim2.fromOffset(0, px + 9),
			LayoutOrder = order or 0,
		},
	})
	Theme.Corner(pill, UDim.new(0.5, 0))
	H.stroke(pill, NAVY, 2, 0)
	Theme.Gradient(pill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 206, 226), 90)
	H.pad(pill, 9, 0, 9, 1)
	pill.Parent = parent
	return pill
end

function H.button(parent, name, text, style, size, textSize, callback)
	local b = CloudUI.Button({
		Name = name,
		Text = text,
		Style = style,
		Size = size,
		TextSize = textSize or 20,
		Callback = callback,
		Parent = parent,
	})
	return b
end

-- a button whose text may take two lines (the narrow rows): slimmer top / bottom padding
function H.twoLine(button)
	button.TextWrapped = true
	local p = button:FindFirstChildOfClass("UIPadding")
	if p then
		p.PaddingTop = UDim.new(0, 3)
		p.PaddingBottom = UDim.new(0, 3)
	end
end

function H.tween(inst, seconds, goal, style, direction)
	return Util.Tween(inst, seconds, goal, style, direction)
end

----------------------------------------------------------------------
-- data helpers (the synced profile + the catalogs; display only)
----------------------------------------------------------------------
function H.call(mod, fnName, ...)
	if type(mod) ~= "table" or type(mod[fnName]) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(mod[fnName], ...)
	if ok then
		return a, b
	end
	return nil
end

function H.def(key)
	if type(key) ~= "string" then
		return nil
	end
	local ok, def = pcall(State.DefOf, key)
	if ok and type(def) == "table" then
		return def
	end
	return PetCatalog.Get and PetCatalog.Get(key) or nil
end

function H.name(key, def)
	def = def or H.def(key)
	return def and tostring(def.DisplayName or def.Name or key) or tostring(key)
end

function H.level(key)
	local ok, level, xp = pcall(State.PetLevel, key)
	if ok and type(level) == "number" then
		return math.max(1, math.floor(level)), tonumber(xp) or 0
	end
	return 1, 0
end

function H.cap(def, key)
	local cap = H.call(PetCatalog, "LevelCap", def or key)
	if type(cap) == "number" and cap >= 1 then
		return math.floor(cap)
	end
	return tonumber(PetCatalog.MaxLevel) or (TycoonCatalog and tonumber(TycoonCatalog.MaxPetLevel)) or 100
end

function H.xpToNext(level)
	local n = H.call(TycoonCatalog, "XpToNext", level)
	if type(n) == "number" and n > 0 then
		return n
	end
	return math.huge
end

function H.growth(key)
	local ok, g = pcall(State.PetGrowth, key)
	if ok and type(g) == "table" then
		return g
	end
	return { Evo = 0, Speed = 0, Physique = 0, Ability = 0, Defense = 0 }
end

-- Phase 5 (3.7): the stored stage the way every site draws it (State.PetStage)
function H.stage(key)
	if type(State.PetStage) == "function" then
		local ok, stage = pcall(State.PetStage, key)
		if ok and type(stage) == "number" then
			return math.max(0, math.floor(stage))
		end
	end
	return math.max(0, math.floor(tonumber(H.growth(key).Evo) or 0))
end

-- Phase 5 (3.4): berries in the basket (the Berries attribute / State.Berries) and the basket size (plot BerryCap)
function H.berries()
	if type(State.Berries) == "function" then
		local ok, n = pcall(State.Berries)
		if ok and type(n) == "number" then
			return math.max(0, math.floor(n))
		end
	end
	return 0
end

function H.plot()
	local index = LocalPlayer and LocalPlayer:GetAttribute(Config.Attr.SpotIndex)
	local lobby = Workspace:FindFirstChild("NimbusLobby")
	if type(index) ~= "number" or not lobby then
		return nil
	end
	local named = lobby:FindFirstChild(string.format("Spot_%02d", index), true)
	if named and named:GetAttribute("SpotIndex") == index then
		return named
	end
	return nil
end

-- one Food Machine feed of a pet copy: { Cost = berries (TycoonCatalog.FeedBerries), Xp = TycoonCatalog.FeedXp }
function H.berryFeed(key, def, level, machine)
	local cost = tonumber(H.call(TycoonCatalog, "FeedBerries", def or key, level)) or 0
	local xp = tonumber(H.call(TycoonCatalog, "FeedXp", level, math.max(1, machine))) or 0
	return { Cost = math.floor(cost), Xp = math.floor(xp) }
end

-- the next stage when the pet can EVOLVE now, else nil
function H.canEvolve(key, def, level)
	local nextStage = H.call(PetCatalog, "CanEvolve", def or key, level, H.stage(key))
	if type(nextStage) == "number" and nextStage >= 1 then
		return nextStage
	end
	return nil
end

function H.stars(stage)
	if stage and stage > 0 then
		return string.rep(G.Star, math.min(2, stage))
	end
	return ""
end

function H.home()
	local ok, home = pcall(State.Home)
	if ok and type(home) == "table" then
		return home
	end
	return { Stations = {}, Garden = {}, Prestige = 0 }
end

function H.station(home, id)
	local st = type(home) == "table" and home.Stations or nil
	local v = type(st) == "table" and st[id] or nil
	if type(v) == "number" and v == v then
		return math.max(0, math.floor(v))
	end
	return 0
end

function H.cash()
	local ok, v = pcall(State.Cash)
	if ok and type(v) == "number" then
		return v
	end
	return 0
end

function H.owned(key)
	local ok, n = pcall(State.OwnedCount, key)
	return ok and tonumber(n) or 0
end

function H.money(n)
	local text = H.call(TycoonCatalog, "FormatCash", n)
	if type(text) == "string" then
		return text
	end
	return "$" .. Util.Commas(math.floor(tonumber(n) or 0))
end

function H.rate(n)
	n = tonumber(n) or 0
	if n ~= n or n < 0 then
		n = 0
	end
	if n < 100 then
		local t = string.format("%.1f", math.floor(n * 10 + 0.5) / 10)
		return "$" .. (t:gsub("%.0$", ""))
	end
	return H.money(n)
end

function H.commas(n)
	return Util.Commas(math.floor(tonumber(n) or 0))
end

function H.inMatch()
	return LocalPlayer ~= nil and LocalPlayer:GetAttribute(Config.Attr.InMatch) == true
end

function H.hasHome()
	return LocalPlayer ~= nil and type(LocalPlayer:GetAttribute(Config.Attr.SpotIndex)) == "number"
end

function H.now()
	local ok, t = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.time()
end

function H.clock(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function H.minutes(seconds)
	local m = math.floor((tonumber(seconds) or 0) / 60 + 0.5)
	if m < 1 then
		return math.max(1, math.floor(seconds or 0)) .. " s"
	end
	return m .. " min"
end

function H.rarityOrder(rarityId)
	for _, r in ipairs(Config.Rarities or {}) do
		if r.Id == rarityId then
			return r.Order or 1
		end
	end
	return 1
end

function H.rarityText(def)
	if def and def.Rarity == "Secret" then
		return Color3.fromRGB(196, 168, 255)
	end
	return Theme.Lighten(CloudUI.RarityColor(def and def.Rarity), 0.3)
end

-- every owned pet copy, rarest first (the Pets panel's order)
function H.ownedKeys()
	local ok, keys = pcall(State.Keys)
	if not ok or type(keys) ~= "table" then
		keys = {}
	end
	local info, out = {}, {}
	for i, key in ipairs(keys) do
		if type(key) == "string" and not info[key] and H.owned(key) > 0 then
			local def = H.def(key)
			if def then
				info[key] = { Order = H.rarityOrder(def.Rarity), Index = i }
				out[#out + 1] = key
			end
		end
	end
	table.sort(out, function(a, b)
		local x, y = info[a], info[b]
		if x.Order ~= y.Order then
			return x.Order > y.Order
		end
		return x.Index > y.Index
	end)
	return out
end

-- the Garden places holding `key` (ascending)
function H.gardenSlots(home, key)
	local out = {}
	if type(home.Garden) == "table" then
		for slot, k in pairs(home.Garden) do
			if k == key and type(slot) == "number" then
				out[#out + 1] = slot
			end
		end
	end
	table.sort(out)
	return out
end

function H.equippedCount(key)
	local ok, n = pcall(State.EquippedCount, key)
	return ok and tonumber(n) or 0
end

function H.equippedList()
	local ok, snap = pcall(State.Get)
	if ok and type(snap) == "table" and type(snap.Equipped) == "table" then
		return snap.Equipped
	end
	return {}
end

-- the running training job of a key { Stat, Ends, Rank, ... } or nil
function H.job(key)
	local job = H.growth(key).Job
	if type(job) == "table" then
		return job
	end
	return nil
end

function H.skillName(stat)
	for _, s in ipairs(SKILLS) do
		if s.Id == stat then
			return s.Name
		end
	end
	return tostring(stat)
end

-- where a pet copy is: "Physique 2:10" (training) | "In Garden" | "Following" | nil, and its colour
function H.whereText(key, home)
	local job = H.job(key)
	if job then
		local left = (tonumber(job.Ends) or 0) - H.now()
		return G.Muscle .. " " .. H.skillName(job.Stat) .. " " .. H.clock(left), Theme.Lighten(PURPLE, 0.3)
	end
	if #H.gardenSlots(home or H.home(), key) > 0 then
		return G.Seedling .. " In Garden", Theme.Lighten(GOOD, 0.3)
	end
	if H.equippedCount(key) > 0 then
		return G.Star .. " Following", GOLD
	end
	return nil, MUTED
end

-- the room left below the level cap, in XP
function H.room(level, xp, cap)
	if level >= cap then
		return 0
	end
	local room = 0
	for l = level, cap - 1 do
		local need = H.xpToNext(l)
		if need == math.huge then
			break
		end
		room = room + need
		if room > 1e12 then
			break
		end
	end
	return math.max(0, room - xp)
end

-- coins per second of a pet in this home's Garden (PetPower x food x stars / meal x the Lucky EV); a home without a
-- Garden counts the grass food
function H.coinsPerSecond(key, def, home)
	if not TycoonCatalog then
		return 0
	end
	local level = H.level(key)
	local power = H.call(TycoonCatalog, "PetPower", { Def = def, Level = level, Stage = H.stage(key), Key = key }) or 0
	local food = H.call(TycoonCatalog, "FoodOf", home) or 0
	local coins = TycoonCatalog.Coins or {}
	if food <= 0 then
		food = tonumber(coins.GrassFood) or 12
	end
	local stars = math.floor(tonumber(home.Prestige) or 0)
	local mult = H.call(TycoonCatalog, "PrestigeMultiplier", stars) or 1
	local lucky = H.call(TycoonCatalog, "LuckyEV", home) or 1
	local meal = tonumber(coins.MealSeconds) or 8
	return power * food * mult * lucky / meal
end

----------------------------------------------------------------------
-- remotes (each action at most every FIRE_GAP seconds; the server rate-limits as well)
----------------------------------------------------------------------
function H.fire(gapKey, name, ...)
	local now = os.clock()
	if S.Last[gapKey] and now - S.Last[gapKey] < K.FIRE_GAP then
		return false
	end
	local ok, remote = pcall(Remotes.Get, name)
	if not ok or not remote then
		warnOnce("remote " .. name, remote)
		return false
	end
	S.Last[gapKey] = now
	local args = { ... }
	local n = select("#", ...)
	local sent = pcall(function()
		remote:FireServer(unpack(args, 1, n))
	end)
	return sent
end

function H.hint(text, kind)
	-- the server answers every request with a side toast; local refusals use the menu's side hint (never centred)
	local menu = H.controller("MenuController")
	if menu and type(menu.Hint) == "function" then
		pcall(menu.Hint, text, kind or "info")
	end
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

----------------------------------------------------------------------
-- window geometry (the FusionController pattern: one UIScale = min(screen factor, fit))
----------------------------------------------------------------------
function H.guiSize()
	local size = U.Gui and U.Gui.AbsoluteSize or Vector2.new(1280, 720)
	if size.X < 2 or size.Y < 2 then
		return Vector2.new(1280, 720)
	end
	return size
end

function H.viewportHeight()
	local camera = Workspace.CurrentCamera
	local vp = camera and camera.ViewportSize
	if vp and vp.Y > 2 then
		return vp.Y
	end
	return H.guiSize().Y
end

-- the small centred confirm (Train / Stop / EVOLVE): its preferred size at the screen factor, shrunk to fit
function H.confirmFit(prefW, prefH, minW, minH)
	local area = H.guiSize()
	local factor = Theme.ScreenFactor(H.viewportHeight())
	local freeW = area.X - 2 * K.MARGIN
	local freeH = area.Y - 2 * K.MARGIN
	local w = Util.Clamp(math.floor(freeW / factor), minW, prefW)
	local h = Util.Clamp(math.floor(freeH / factor), minH, prefH)
	local scale = Util.Clamp(math.min(factor, freeW / w, freeH / h), 0.3, 1.25)
	return w, h, scale, area.X / 2, area.Y / 2
end

----------------------------------------------------------------------
-- pet viewports (Low detail, a few per frame)
----------------------------------------------------------------------
function H.queueView(row)
	if row.ViewReady or not row.ViewHolder then
		return
	end
	U.ViewQueue = U.ViewQueue or {}
	if not row.Queued then
		row.Queued = true
		U.ViewQueue[#U.ViewQueue + 1] = row
	end
	if S.Filling then
		return
	end
	S.Filling = true
	task.spawn(function()
		task.wait()
		while S.Open and U.ViewQueue and #U.ViewQueue > 0 do
			local t0 = os.clock()
			local built = 0
			while #U.ViewQueue > 0 and (built == 0 or os.clock() - t0 < K.BUILD_BUDGET) and built < 3 do
				local r = table.remove(U.ViewQueue, 1)
				if r then
					r.Queued = false
				end
				if r and not r.ViewReady and r.ViewHolder and r.ViewHolder.Parent and r.Def then
					r.ViewReady = true
					local stage = H.stage(r.Key)
					r.ViewStage = stage
					local ok, handle = pcall(CloudUI.PetViewport, r.ViewHolder, r.Def, UDim2.new(1, 0, 1, 0), {
						Spin = "sway",
						Detail = "Low",
						Evolved = stage > 0 and stage or nil,
						ZIndex = 4,
					})
					if ok then
						r.View = handle
					end
					built = built + 1
				end
			end
			task.wait()
		end
		S.Filling = false
	end)
end

function H.dropRow(row)
	if row.View then
		pcall(row.View.Destroy)
		row.View = nil
	end
	if row.Frame then
		row.Frame:Destroy()
	end
end

-- the pet disc of a row: a rarity-tinted circle with the viewport inside
function H.petDisc(parent, def, size)
	local color = CloudUI.RarityColor(def and def.Rarity)
	local disc = H.frame(parent, "Pet", {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Darken(color, 0.35),
		ZIndex = 3,
	})
	Theme.Corner(disc, UDim.new(0, 14))
	H.stroke(disc, Theme.Lighten(color, 0.1), 3, 0)
	Theme.Gradient(disc, Theme.Lighten(color, 0.05), Theme.Darken(color, 0.45), 90)
	local holder = H.frame(disc, "ViewHolder", { Size = UDim2.new(1, 0, 1, 0), ZIndex = 4 })
	return disc, holder
end

----------------------------------------------------------------------
-- the window
----------------------------------------------------------------------
function H.buildFeedPage(body)
	local page = H.frame(body, "FeedPage", { Size = UDim2.new(1, 0, 1, 0), Visible = false })
	U.FeedPage = page
	U.FeedList = H.scroller(page, "FeedList", { Size = UDim2.new(1, 0, 1, -(K.FOOT_H + 10)) })
	H.pad(U.FeedList, 2, 2, 14, 6)
	H.list(U.FeedList, Enum.FillDirection.Vertical, 8)
	local foot = H.inset(page, "Footer", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, K.FOOT_H),
	})
	U.Foot = foot
	U.Leftovers = H.text(foot, "Leftovers", "", "Heading", 18, Color3.fromRGB(255, 226, 150), {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -220, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	U.Machine = H.text(foot, "Machine", "", "Body", 19, WHITE, {
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -220, 0, 62),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	U.Upgrade = H.button(foot, "UpgradeMachine", "Upgrade", "Gold", UDim2.fromOffset(190, 54), 21, function()
		H.upgradeMachine()
	end)
	U.Upgrade.AnchorPoint = Vector2.new(1, 0.5)
	U.Upgrade.Position = UDim2.new(1, -12, 0.5, 0)
	U.FeedEmpty = H.text(page, "Empty", "", "Body", 20, MUTED, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.new(1, -60, 0, 80),
		TextWrapped = true,
		Visible = false,
	})
end

function H.buildGardenPage(body)
	local page = H.frame(body, "GardenPage", { Size = UDim2.new(1, 0, 1, 0), Visible = false })
	U.GardenPage = page
	local head = H.inset(page, "GardenHeader", { Size = UDim2.new(1, 0, 0, 72) })
	U.GardenHead = head
	U.GardenPlace = H.text(head, "Place", "", "Title", 24, WHITE, {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -220, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	U.GardenNow = H.text(head, "Now", "", "Body", 18, MUTED, {
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -220, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	U.TakeOut = H.button(head, "TakeOut", "Take out", "Pink", UDim2.fromOffset(180, 50), 21, function()
		if S.Slot then
			H.fire("garden", "HomeAction", "GardenSet", { Slot = S.Slot })
		end
	end)
	U.TakeOut.AnchorPoint = Vector2.new(1, 0.5)
	U.TakeOut.Position = UDim2.new(1, -12, 0.5, 0)
	U.GardenList = H.scroller(page, "GardenList", { Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 1, -82) })
	H.pad(U.GardenList, 2, 2, 14, 6)
	H.list(U.GardenList, Enum.FillDirection.Vertical, 8)
end

function H.buildTrainPage(body)
	local page = H.frame(body, "TrainPage", { Size = UDim2.new(1, 0, 1, 0), Visible = false })
	U.TrainPage = page
	U.TrainList = H.scroller(page, "TrainList", { Size = UDim2.new(0, K.TRAIN_LIST_W, 1, 0) })
	H.pad(U.TrainList, 2, 2, 12, 6)
	H.list(U.TrainList, Enum.FillDirection.Vertical, 6)
	local right = H.inset(page, "Skills", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(1, -(K.TRAIN_LIST_W + 12), 1, 0),
	})
	U.TrainRight = right
	U.TrainName = H.text(right, "TrainName", "", "Title", 26, WHITE, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	U.TrainSpots = H.text(right, "Spots", "", "Heading", 18, MUTED, {
		Position = UDim2.fromOffset(14, 42),
		Size = UDim2.new(1, -28, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- the running job: a purple timer bar + Stop
	local timer = H.frame(right, "TimerRow", { Position = UDim2.fromOffset(14, 72), Size = UDim2.new(1, -28, 0, 50), Visible = false })
	U.TimerRow = timer
	U.TrainTimer = CloudUI.Bar({
		Name = "TrainTimer",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, -150, 0, 34),
		Height = 34,
		TextSize = 19,
		Color = PURPLE,
		Parent = timer,
	})
	U.StopTraining = H.button(timer, "StopTraining", "Stop", "Pink", UDim2.fromOffset(136, 48), 21, function()
		H.askStop(S.TrainKey)
	end)
	U.StopTraining.AnchorPoint = Vector2.new(1, 0.5)
	U.StopTraining.Position = UDim2.new(1, 0, 0.5, 0)
	local skills = H.scroller(right, "SkillList", { Position = UDim2.fromOffset(8, 128), Size = UDim2.new(1, -16, 1, -136) })
	U.SkillList = skills
	H.pad(skills, 4, 2, 12, 6)
	H.list(skills, Enum.FillDirection.Vertical, 8)
	for i, skill in ipairs(SKILLS) do
		local row = { Id = skill.Id, Pips = {} }
		local f = H.inset(skills, "Skill_" .. skill.Id, { Size = UDim2.new(1, 0, 0, K.SKILL_H), LayoutOrder = i })
		row.Frame = f
		row.Name = H.text(f, "Name", skill.Name, "Title", 22, WHITE, {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -250, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		row.Rank = H.text(f, "Rank", "Rank 0/10", "Heading", 19, GOLD, {
			Position = UDim2.fromOffset(12, 36),
			Size = UDim2.fromOffset(120, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local pips = H.frame(f, "RankBar", { Position = UDim2.fromOffset(136, 40), Size = UDim2.fromOffset(200, 16) })
		row.PipRow = pips
		H.list(pips, Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		for p = 1, 10 do
			local pip = H.frame(pips, "Pip" .. p, {
				Size = UDim2.fromOffset(16, 14),
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(14, 20, 52),
				LayoutOrder = p,
			})
			H.corner(pip, 3)
			H.stroke(pip, NAVY, 1.5, 0)
			row.Pips[p] = pip
		end
		row.What = H.text(f, "What", skill.Text, "Body", 18, MUTED, {
			Position = UDim2.fromOffset(12, 64),
			Size = UDim2.new(1, -250, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		row.Cost = H.text(f, "Cost", "", "Heading", 18, CASH, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 8),
			Size = UDim2.fromOffset(224, 26),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		row.Button = H.button(f, "Train", "Train", "Green", UDim2.fromOffset(150, 50), 21, function()
			H.askTrain(S.TrainKey, skill.Id)
		end)
		row.Button.AnchorPoint = Vector2.new(1, 1)
		row.Button.Position = UDim2.new(1, -12, 1, -8)
		row.Max = H.pill(f, "Max", "MAX", GOLD, 20, 1)
		row.Max.AnchorPoint = Vector2.new(1, 1)
		row.Max.Position = UDim2.new(1, -12, 1, -14)
		row.Max.Visible = false
		U.Skills[skill.Id] = row
	end
	U.TrainEmpty = H.text(right, "Empty", "", "Body", 20, MUTED, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -60, 0, 90),
		TextWrapped = true,
		Visible = false,
	})
end

-- the confirm (Evolve / Train / Stop): its own holder above the window, so it also works over the Pets panel
function H.buildConfirm()
	local holder = H.frame(U.Gui, "CareConfirm", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(K.CONFIRM_W, K.CONFIRM_H),
		Visible = false,
		ZIndex = 30,
	})
	U.Confirm = holder
	U.ConfirmFit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	local box = H.frame(holder, "Box", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE, -- the UIGradient multiplies it
		ZIndex = 31,
	})
	H.corner(box, 16)
	U.ConfirmStroke = H.stroke(box, GOLD, 4, 0)
	Theme.Gradient(box, Colors.PanelLight, Colors.Panel, 90)
	U.ConfirmTitle = H.text(box, "Title", "", "Title", 30, GOLD, {
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 40),
		TextScaled = true,
		ZIndex = 32,
	})
	Util.Create("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 22, Parent = U.ConfirmTitle })
	U.ConfirmText = H.text(box, "Text", "", "Body", 20, WHITE, {
		Position = UDim2.fromOffset(20, 60),
		Size = UDim2.new(1, -40, 1, -146),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 32,
	})
	local buttons = H.frame(box, "Buttons", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, -32, 0, 58),
		ZIndex = 32,
	})
	H.list(buttons, Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	U.ConfirmYes = CloudUI.Button({
		Name = "ConfirmYes",
		Text = "Yes",
		Style = "Gold",
		Size = UDim2.fromOffset(230, 56),
		TextSize = 23,
		LayoutOrder = 1,
		Callback = function()
			local c = S.Confirm
			H.closeConfirm()
			if c and type(c.Yes) == "function" then
				safe("confirm", c.Yes)
			end
		end,
		Parent = buttons,
	})
	U.ConfirmYes.ZIndex = 33
	U.ConfirmNo = CloudUI.Button({
		Name = "ConfirmNo",
		Text = "Not now",
		Style = "Blue",
		Size = UDim2.fromOffset(170, 56),
		TextSize = 22,
		LayoutOrder = 2,
		Callback = function()
			H.closeConfirm()
		end,
		Parent = buttons,
	})
	U.ConfirmNo.ZIndex = 33
end

function H.buildWindow()
	if S.Built then
		return true
	end
	local holder = H.frame(U.Gui, "Window_Care", {
		Size = UDim2.fromOffset(K.PREF_W, K.PREF_H),
		Visible = false,
		ZIndex = 3,
	})
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	-- Phase 5 (6.6): docked right on landscape screens, a bottom sheet on portrait ones; follows the screen
	U.Dock = NeonKit.Dock(holder, U.Fit, K.PREF_W, K.PREF_H)
	local panel = CloudUI.Panel({
		Name = "CarePanel",
		Title = TITLES.Feed,
		Closable = true,
		Category = "Care",
		Accent = ACCENTS.Feed,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		OnClose = function()
			CareController.Close()
		end,
		Parent = holder,
	})
	U.Panel = panel
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel.Root })
	local content = panel.Content
	-- the info line + the Cash chip
	U.Top = H.frame(content, "Top", { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, K.TOP_H) })
	U.Info = H.text(U.Top, "Info", "", "Body", 19, MUTED, {
		Size = UDim2.new(1, -220, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	-- Phase 5 (3.4): the Food Machine's header is the Berry Basket: a bar "1,240 / 3,000 berries" + "+578 a minute"
	U.Basket = CloudUI.Bar({
		Name = "BerryBasket",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 34, 0.5, 0),
		Size = UDim2.new(1, -180, 0, 32),
		Height = 32,
		TextSize = 19,
		Color = Color3.fromRGB(236, 84, 140),
		Parent = U.Top,
	})
	U.BasketIcon = H.text(U.Top, "BasketIcon", G.Berry, "Title", 26, WHITE, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(30, 32),
	})
	U.BasketRate = H.text(U.Top, "BasketRate", "", "Heading", 18, Color3.fromRGB(255, 196, 226), {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(140, 40),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	U.CashChip = H.pill(U.Top, "Cash", "$0", Theme.Darken(CASH, 0.15), 22, 0)
	U.CashChip.AnchorPoint = Vector2.new(1, 0.5)
	U.CashChip.Position = UDim2.new(1, 0, 0.5, 0)
	U.Body = H.frame(content, "Body", {
		Position = UDim2.fromOffset(12, K.TOP_H + 16),
		Size = UDim2.new(1, -24, 1, -(K.TOP_H + 26)),
	})
	H.buildFeedPage(U.Body)
	H.buildGardenPage(U.Body)
	H.buildTrainPage(U.Body)
	S.Built = true
	H.relayout()
	return true
end

----------------------------------------------------------------------
-- rows
----------------------------------------------------------------------
-- the left block of every row: pet disc, name (+ stars), "Lv 12 / 100", where it is
function H.rowHead(f, row, def)
	local disc, holder = H.petDisc(f, def, K.VIEW)
	disc.Position = UDim2.fromOffset(10, 10)
	row.Disc = disc
	row.ViewHolder = holder
	row.Name = H.text(f, "Name", "", "Title", 23, H.rarityText(def), {
		Position = UDim2.fromOffset(K.VIEW + 22, 6),
		Size = UDim2.new(0, 300, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	row.Level = H.text(f, "Level", "", "Heading", 19, WHITE, {
		Position = UDim2.fromOffset(K.VIEW + 22, 38),
		Size = UDim2.fromOffset(140, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	row.Where = H.text(f, "Where", "", "Heading", 18, MUTED, {
		Position = UDim2.fromOffset(K.VIEW + 166, 39),
		Size = UDim2.new(0, 260, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

function H.paintHead(row, key, def, home)
	local level = H.level(key)
	local cap = H.cap(def, key)
	local stage = H.stage(key)
	local stars = H.stars(stage)
	row.Name.Text = H.name(key, def) .. (stars ~= "" and ("  " .. stars) or "")
	row.Level.Text = "Lv " .. level .. " / " .. cap
	row.Level.TextColor3 = level >= cap and GOLD or WHITE
	local where, color = H.whereText(key, home)
	row.Where.Text = where or ""
	row.Where.TextColor3 = color
	return level, cap, stage
end

function H.newFeedRow(key, def)
	local row = { Key = key, Def = def }
	local f = H.inset(U.FeedList, "Feed_" .. key, { Size = UDim2.new(1, 0, 0, K.ROW_H) })
	row.Frame = f
	H.rowHead(f, row, def)
	row.Bar = CloudUI.Bar({
		Name = "XpBar",
		Position = UDim2.fromOffset(K.VIEW + 22, 70),
		Size = UDim2.new(0, 360, 0, 28),
		Height = 28,
		TextSize = 18,
		Color = XP,
		Parent = f,
	})
	local buttons = H.frame(f, "Buttons", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(K.BUTTONS_W, 60),
	})
	row.Buttons = buttons
	H.list(buttons, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	row.Feed = H.button(buttons, "Feed", "Feed", "Green", UDim2.fromOffset(240, 58), 20, function()
		H.feed(key)
	end)
	row.Feed.LayoutOrder = 1
	-- (Phase 5: no "Level up" button: ONE Feed button = one feed)
	row.Evolve = H.button(buttons, "Evolve", "EVOLVE!", "Gold", UDim2.fromOffset(122, 58), 20, function()
		CareController.ConfirmEvolve(key)
	end)
	row.Evolve.LayoutOrder = 3
	for _, b in ipairs({ row.Feed, row.Evolve }) do
		H.twoLine(b)
	end
	H.layoutFeedRow(row)
	return row
end

function H.layoutFeedRow(row)
	local stacked, short = S.Stacked, S.Short
	local view = short and K.VIEW_SHORT or K.VIEW
	local h
	if stacked then
		h = short and K.ROW_H_SHORT_STACKED or K.ROW_H_STACKED
		if S.Tall then
			h = h + 22
		end
	else
		h = short and K.ROW_H_SHORT or K.ROW_H
	end
	row.Frame.Size = UDim2.new(1, 0, 0, h)
	row.Disc.Size = UDim2.fromOffset(view, view)
	row.Disc.Position = UDim2.fromOffset(10, short and 8 or 10)
	local x = view + 22
	row.Name.Position = UDim2.fromOffset(x, short and 4 or 6)
	row.Level.Position = UDim2.fromOffset(x, short and 34 or 38)
	row.Where.Position = UDim2.fromOffset(x + 128, short and 35 or 39)
	local barY = short and 62 or 70
	if stacked then
		row.Name.Size = UDim2.new(1, -(x + 10), 0, 30)
		row.Where.Size = UDim2.new(1, -(x + 138), 0, 24)
		if S.Tall then
			-- portrait: "Lv 57 / 100" and where it is get a line each, the bar under them
			row.Where.Position = UDim2.fromOffset(x, 62)
			row.Where.Size = UDim2.new(1, -(x + 10), 0, 24)
			barY = 90
		end
		row.Bar.Root.Position = UDim2.fromOffset(x, barY)
		row.Bar.Root.Size = UDim2.new(1, -(x + 12), 0, 28)
		row.Buttons.AnchorPoint = Vector2.new(0.5, 1)
		row.Buttons.Position = UDim2.new(0.5, 0, 1, -8)
		row.Buttons.Size = UDim2.new(1, -20, 0, 60)
	else
		local right = K.BUTTONS_W + 20
		row.Name.Size = UDim2.new(1, -(x + right), 0, 30)
		row.Where.Size = UDim2.new(1, -(x + 138 + right), 0, 24)
		row.Bar.Root.Position = UDim2.fromOffset(x, barY)
		row.Bar.Root.Size = UDim2.new(1, -(x + right), 0, 28)
		row.Buttons.AnchorPoint = Vector2.new(1, 0.5)
		row.Buttons.Position = UDim2.new(1, -10, 0.5, 0)
		row.Buttons.Size = UDim2.fromOffset(K.BUTTONS_W, 60)
	end
	-- stacked rows: the Feed button takes the row (70% beside EVOLVE when the pet is ready)
	local bh = short and 50 or 58
	if stacked then
		row.Feed.Size = UDim2.new(row.Ready and 0.68 or 1, row.Ready and -6 or 0, 0, bh)
		row.Evolve.Size = UDim2.new(0.32, -4, 0, bh)
		row.Buttons.Size = UDim2.new(1, -20, 0, bh + 2)
	else
		row.Feed.Size = UDim2.fromOffset(row.Ready and 300 or 430, 58)
		row.Evolve.Size = UDim2.fromOffset(128, 58)
	end
end

function H.paintFeedRow(row, home, cash)
	local key, def = row.Key, row.Def
	local level, cap = H.paintHead(row, key, def, home)
	local _, xp = H.level(key)
	local need = H.xpToNext(level)
	local capped = level >= cap
	if capped then
		row.Bar.SetFraction(1)
		row.Bar.SetText("MAX LEVEL")
		row.Bar.SetColor(GOLD)
	else
		row.Bar.SetFraction(need > 0 and need < math.huge and math.min(1, xp / need) or 0)
		row.Bar.SetText(H.commas(xp) .. " / " .. H.commas(need) .. " XP")
		row.Bar.SetColor(XP)
	end
	-- Phase 5 (3.4): ONE Feed button: "Feed  340 berries  (+90 XP)"; grey (still says why when pressed) while the
	-- basket is short or the machine is not built
	local machine = H.station(home, "Kitchen")
	local busy = H.inMatch()
	local one = H.berryFeed(key, def, level, machine)
	row.Cost = one.Cost
	if capped then
		row.Feed.Text = "Max level"
		CloudUI.SetStyle(row.Feed, "Gray")
		CloudUI.SetDisabled(row.Feed, true)
	elseif machine < 1 then
		row.Feed.Text = "Feed (build the Food Machine)"
		CloudUI.SetStyle(row.Feed, "Gray")
		CloudUI.SetDisabled(row.Feed, busy)
	else
		row.Feed.Text = "Feed  " .. H.commas(one.Cost) .. " berries  (+" .. H.commas(one.Xp) .. " XP)"
		CloudUI.SetStyle(row.Feed, H.berries() >= one.Cost and "Green" or "Gray")
		CloudUI.SetDisabled(row.Feed, busy)
	end
	-- EVOLVE when ready
	local nextStage = H.canEvolve(key, def, level)
	row.Evolve.Visible = nextStage ~= nil
	row.Evolve.Text = S.Tall and "EVOLVE" or "EVOLVE!"
	if (row.Ready ~= nil) ~= (nextStage ~= nil) then
		row.Ready = nextStage
		H.layoutFeedRow(row)
	end
	row.Ready = nextStage
	CloudUI.SetDisabled(row.Evolve, busy)
	if row.Frame then
		local edge = row.Frame:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = nextStage and GOLD or WELL_EDGE
			edge.Transparency = nextStage and 0 or 0.15
		end
	end
end

function H.newGardenRow(key, def)
	local row = { Key = key, Def = def }
	local f = H.inset(U.GardenList, "Pick_" .. key, { Size = UDim2.new(1, 0, 0, K.ROW_H) })
	row.Frame = f
	H.rowHead(f, row, def)
	local info = H.frame(f, "Info", { Position = UDim2.fromOffset(K.VIEW + 22, 70), Size = UDim2.new(1, -(K.VIEW + 220), 0, 30) })
	row.Info = info
	row.InfoLayout = H.list(info, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	row.InfoLayout.Wraps = true
	local role = type(def.Role) == "string" and def.Role or "Combat"
	local mult = H.call(PetCatalog, "RoleMultiplier", def) or 1
	row.RoleText = role .. (mult > 1.001 and (" x" .. tostring(math.floor(mult * 10 + 0.5) / 10)) or "")
	row.RoleShort = role
	row.Role = H.pill(info, "Role", row.RoleText, ROLE_COLORS[role] or Theme.Buttons.Blue, 18, 1)
	row.Coins = H.pill(info, "Coins", "Coins $0/s", Theme.Darken(CASH, 0.2), 18, 2)
	row.Put = H.button(f, "PutHere", "Put here", "Green", UDim2.fromOffset(170, 56), 21, function()
		if S.Slot then
			H.fire("garden", "HomeAction", "GardenSet", { Slot = S.Slot, Key = key })
		end
	end)
	row.Put.AnchorPoint = Vector2.new(1, 0.5)
	row.Put.Position = UDim2.new(1, -12, 0.5, 0)
	H.layoutSimpleRow(row)
	return row
end

function H.layoutSimpleRow(row)
	local short = S.Short
	local view = short and K.VIEW_SHORT or K.VIEW
	local stacked = S.Tall or S.Short
	local h = short and K.ROW_H_SHORT or K.ROW_H
	if stacked then
		h = h + 52 + 34 -- the button under the pills, the pills on two lines
	end
	row.Frame.Size = UDim2.new(1, 0, 0, h)
	row.Disc.Size = UDim2.fromOffset(view, view)
	row.Disc.Position = UDim2.fromOffset(10, short and 8 or 10)
	local x = view + 22
	local right = stacked and 10 or 200
	row.Name.Position = UDim2.fromOffset(x, short and 4 or 6)
	row.Name.Size = UDim2.new(1, -(x + right), 0, 30)
	row.Level.Position = UDim2.fromOffset(x, short and 34 or 38)
	row.Where.Position = UDim2.fromOffset(x + 144, short and 35 or 39)
	row.Where.Size = UDim2.new(1, -(x + 154 + right), 0, 24)
	row.Info.Position = UDim2.fromOffset(x, short and 64 or 70)
	row.Info.Size = UDim2.new(1, -(x + right), 0, stacked and 66 or 30)
	if stacked then
		row.Put.AnchorPoint = Vector2.new(1, 1)
		row.Put.Position = UDim2.new(1, -12, 1, -8)
		row.Put.Size = UDim2.fromOffset(170, 48)
	else
		row.Put.AnchorPoint = Vector2.new(1, 0.5)
		row.Put.Position = UDim2.new(1, -12, 0.5, 0)
		row.Put.Size = UDim2.fromOffset(170, 56)
	end
end

function H.paintGardenRow(row, home)
	local key, def = row.Key, row.Def
	H.paintHead(row, key, def, home)
	row.Role.Text = S.Tall and row.RoleShort or row.RoleText
	row.Coins.Text = "Coins " .. H.rate(H.coinsPerSecond(key, def, home)) .. "/s"
	local placed = #H.gardenSlots(home, key)
	local here = S.Slot and type(home.Garden) == "table" and home.Garden[S.Slot] == key
	local free = H.owned(key) - placed
	local training = H.job(key) ~= nil
	local open = H.call(TycoonCatalog, "GardenSlots", home) or 0
	if here then
		row.Put.Text = "Here now"
	elseif training then
		row.Put.Text = "Training"
	elseif free <= 0 then
		row.Put.Text = "In Garden"
	else
		row.Put.Text = "Put here"
	end
	CloudUI.SetDisabled(row.Put, here or training or free <= 0 or H.inMatch() or not S.Slot or S.Slot > open)
	return (here or training or free <= 0) and 1 or 0
end

function H.newTrainRow(key, def)
	local row = { Key = key, Def = def }
	local f = Util.Create("TextButton", {
		Name = "Train_" .. key,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		BackgroundColor3 = INSET,
		BackgroundTransparency = 0.42,
		Size = UDim2.new(1, 0, 0, K.TRAIN_ROW_H),
		Parent = U.TrainList,
	})
	H.corner(f, 12)
	row.Edge = H.stroke(f, WELL_EDGE, 3, 0.15)
	row.Frame = f
	f.Activated:Connect(function()
		S.TrainKey = key
		H.refresh()
	end)
	local disc, holder = H.petDisc(f, def, 64)
	disc.Position = UDim2.fromOffset(8, 10)
	row.Disc = disc
	row.ViewHolder = holder
	row.Name = H.text(f, "Name", "", "Title", 21, H.rarityText(def), {
		Position = UDim2.fromOffset(82, 6),
		Size = UDim2.new(1, -90, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	row.Level = H.text(f, "Level", "", "Heading", 18, WHITE, {
		Position = UDim2.fromOffset(82, 34),
		Size = UDim2.new(1, -90, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	row.Where = H.text(f, "Where", "", "Heading", 18, MUTED, {
		Position = UDim2.fromOffset(82, 56),
		Size = UDim2.new(1, -90, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return row
end

function H.paintTrainRow(row, home)
	H.paintHead(row, row.Key, row.Def, home)
	local selected = row.Key == S.TrainKey
	row.Edge.Color = selected and GOLD or WELL_EDGE
	row.Edge.Transparency = selected and 0 or 0.15
	row.Frame.BackgroundTransparency = selected and 0.2 or 0.42
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
-- a keyed list: drop the rows of pets that are gone, add new ones, order the rest
function H.syncRows(map, keys, make)
	local want = {}
	for i, key in ipairs(keys) do
		want[key] = i
	end
	for key, row in pairs(map) do
		if not want[key] then
			H.dropRow(row)
			map[key] = nil
		end
	end
	for i, key in ipairs(keys) do
		local row = map[key]
		if not row then
			local def = H.def(key)
			if def then
				row = make(key, def)
				map[key] = row
			end
		end
		if row then
			row.Frame.LayoutOrder = i
			-- a pet that evolved meanwhile gets its new form
			if row.ViewReady and row.ViewStage ~= H.stage(key) then
				if row.View then
					pcall(row.View.Destroy)
					row.View = nil
				end
				row.ViewReady = false
			end
			H.queueView(row)
		end
	end
end

-- Feed order: garden pets (by place), then followers (equipped order), then the rest (rarest first)
function H.feedOrder(home)
	local keys = H.ownedKeys()
	local rank = {}
	local garden = type(home.Garden) == "table" and home.Garden or {}
	local slots = {}
	for slot in pairs(garden) do
		if type(slot) == "number" then
			slots[#slots + 1] = slot
		end
	end
	table.sort(slots)
	local n = 0
	for _, slot in ipairs(slots) do
		local k = garden[slot]
		if type(k) == "string" and not rank[k] then
			n = n + 1
			rank[k] = n
		end
	end
	for _, k in ipairs(H.equippedList()) do
		if type(k) == "string" and not rank[k] then
			n = n + 1
			rank[k] = n
		end
	end
	local out = {}
	for i, k in ipairs(keys) do
		out[i] = k
		if not rank[k] then
			rank[k] = 1000 + i
		end
	end
	table.sort(out, function(a, b)
		return rank[a] < rank[b]
	end)
	-- the pet the window was opened for comes first
	if S.Focus then
		for i, k in ipairs(out) do
			if k == S.Focus then
				table.remove(out, i)
				table.insert(out, 1, k)
				break
			end
		end
	end
	return out
end

function H.refreshFeed(home, cash)
	local keys = H.feedOrder(home)
	H.syncRows(U.Rows, keys, H.newFeedRow)
	for _, row in pairs(U.Rows) do
		H.paintFeedRow(row, home, cash)
	end
	U.FeedEmpty.Visible = #keys == 0
	U.FeedEmpty.Text = "No pets yet! Spin a roulette in the Shop to hatch one."
	-- how it works (the kid rule, 3.4), always the same words
	U.Leftovers.Text = G.Berry .. " Each Feed turns berries into XP. Your garden pets grow more berries!"
	local level = H.station(home, "Kitchen")
	local shares = TycoonCatalog and TycoonCatalog.FeedShare or {}
	local def = H.call(TycoonCatalog, "Get", "Kitchen")
	local maxLevel = def and def.MaxLevel or #shares
	local pad = H.kitchenPad(home)
	local pct = function(l)
		return math.floor((tonumber(shares[l]) or 0) * 100 + 0.5) .. "%"
	end
	local text
	if level < 1 then
		text = "Build the Food Machine at home first: each feed then fills " .. pct(1) .. " of a pet's XP bar."
		if pad and not pad.Locked then
			text = text .. " Build it: " .. H.money(pad.Price)
		end
	elseif level >= maxLevel then
		text = "Food Machine Lv " .. level .. " (max): each feed fills " .. pct(level) .. " of the bar."
	else
		text = "Food Machine Lv " .. level .. ": each feed fills " .. pct(level) .. " of the bar."
		if pad and not pad.Locked then
			text = text .. " Upgrade to Lv " .. (level + 1) .. " (" .. pct(level + 1) .. "): " .. H.money(pad.Price)
		elseif pad and pad.Locked then
			text = text .. " Lv " .. (level + 1) .. ": " .. tostring(pad.Locked)
		end
	end
	if S.Short then
		-- landscape phones: the short form (the footer has one line pair)
		text = level < 1 and "Build the Food Machine first" or ("Food Machine Lv " .. level .. ": feeds fill " .. pct(level))
	end
	U.Machine.Text = text
	local canBuy = pad ~= nil and not pad.Locked and level < maxLevel
	U.Upgrade.Visible = canBuy
	U.Upgrade.Text = level < 1 and "Build" or "Upgrade"
	CloudUI.SetDisabled(U.Upgrade, not canBuy or cash < (tonumber(pad and pad.Price) or 0) or not H.hasHome() or H.inMatch())
	-- the Berry Basket header: "1,240 / 3,000 berries" + "(+750 a minute)"
	local berries = H.berries()
	local plot = H.plot()
	local cap = plot and plot:GetAttribute("BerryCap")
	local income = plot and plot:GetAttribute("IncomePerSecond")
	local share = (TycoonCatalog and type(TycoonCatalog.Berries) == "table" and tonumber(TycoonCatalog.Berries.Share)) or 0.25
	if type(cap) == "number" and cap > 0 then
		U.Basket.SetFraction(math.min(1, berries / cap))
		U.Basket.SetText("Berry Basket " .. H.commas(berries) .. " / " .. H.commas(math.floor(cap)))
	else
		U.Basket.SetFraction(berries > 0 and 1 or 0)
		U.Basket.SetText("Berry Basket " .. H.commas(berries))
	end
	U.BasketRate.Text = (type(income) == "number" and income > 0) and ("+" .. H.commas(math.floor(income * share * 60 + 0.5)) .. " a minute") or ""
	U.Info.Text = ""
end

function H.kitchenPad(home)
	for _, p in ipairs(H.call(TycoonCatalog, "AvailablePads", home) or {}) do
		if type(p) == "table" and p.StationId == "Kitchen" then
			return p
		end
	end
	return nil
end

function H.upgradeMachine()
	if H.inMatch() then
		return
	end
	if not H.hasHome() then
		H.hint("Claim a home first: press E at a free gate.", "info")
		return
	end
	H.fire("upgrade", "HomeAction", "Upgrade", "Kitchen")
end

function H.refreshGarden(home)
	local open = H.call(TycoonCatalog, "GardenSlots", home) or 0
	local slot = S.Slot
	local keys = H.ownedKeys()
	H.syncRows(U.GardenRows, keys, H.newGardenRow)
	-- the pets that can go here first (then the busy ones)
	local busy = {}
	for _, row in pairs(U.GardenRows) do
		busy[row.Key] = H.paintGardenRow(row, home)
	end
	local order = {}
	for i, k in ipairs(keys) do
		order[i] = k
	end
	local index = {}
	for i, k in ipairs(keys) do
		index[k] = i
	end
	table.sort(order, function(a, b)
		local x, y = busy[a] or 0, busy[b] or 0
		if x ~= y then
			return x < y
		end
		return index[a] < index[b]
	end)
	for i, k in ipairs(order) do
		if U.GardenRows[k] then
			U.GardenRows[k].Frame.LayoutOrder = i
		end
	end
	local current = slot and type(home.Garden) == "table" and home.Garden[slot] or nil
	U.GardenPlace.Text = slot and ("Garden place " .. slot .. (open > 0 and ("  (" .. open .. " open)") or "")) or "Pet Garden"
	if current and type(current) == "string" then
		U.GardenNow.Text = "Now here: " .. H.name(current) .. ". Pick a pet to swap, or take it out."
	elseif slot and slot > open then
		U.GardenNow.Text = G.Lock .. " This place opens with a Prestige."
	else
		U.GardenNow.Text = "Pick a pet: it eats at the Food Bowl and poops Cloud Cash."
	end
	U.TakeOut.Visible = type(current) == "string"
	CloudUI.SetDisabled(U.TakeOut, H.inMatch())
	U.Info.Text = "Every pet can work here: it eats at the Food Bowl and poops Cloud Cash!"
end

function H.refreshTrain(home, cash)
	-- the pets in training first (their timers), then the followers, then the rest (rarest first)
	local keys = H.ownedKeys()
	local rank = {}
	local equipped = {}
	for _, k in ipairs(H.equippedList()) do
		equipped[k] = true
	end
	for i, k in ipairs(keys) do
		rank[k] = (H.job(k) and 0 or (equipped[k] and 1000 or 2000)) + i
	end
	table.sort(keys, function(a, b)
		return rank[a] < rank[b]
	end)
	H.syncRows(U.TrainRows, keys, H.newTrainRow)
	local valid = false
	for _, k in ipairs(keys) do
		if k == S.TrainKey then
			valid = true
		end
	end
	if not valid then
		S.TrainKey = keys[1]
		-- prefer a pet that is training (its timer), else the first follower
		for _, k in ipairs(keys) do
			if H.job(k) then
				S.TrainKey = k
				break
			end
		end
	end
	for _, row in pairs(U.TrainRows) do
		H.paintTrainRow(row, home)
	end
	local level = H.station(home, "Gym")
	local slots = H.call(TycoonCatalog, "TrainingSlots", home) or 0
	local busyCount = 0
	for _, k in ipairs(keys) do
		if H.job(k) then
			busyCount = busyCount + 1
		end
	end
	-- (a job can also belong to a pet copy no longer in the list: count the growth map)
	local okMap, map = pcall(State.PetGrowthMap)
	if okMap and type(map) == "table" then
		local n = 0
		for _, e in pairs(map) do
			if type(e) == "table" and type(e.Job) == "table" then
				n = n + 1
			end
		end
		busyCount = math.max(busyCount, n)
	end
	local key = S.TrainKey
	local def = key and H.def(key)
	local hasPet = def ~= nil
	U.TrainEmpty.Visible = not hasPet
	U.TrainEmpty.Text = "No pets yet! Spin a roulette in the Shop to hatch one."
	U.TrainName.Visible = hasPet
	U.TrainSpots.Visible = hasPet
	U.SkillList.Visible = hasPet
	if level < 1 then
		U.Info.Text = "Build the Training Place at home first. Training makes pets tougher in battles!"
	else
		U.Info.Text = "Train a skill: Rank 3 takes 3 minutes. Training pets rest at home until they're done!"
	end
	if not hasPet then
		U.TimerRow.Visible = false
		return
	end
	local stage = H.stage(key)
	local lv = H.level(key)
	U.TrainName.Text = H.name(key, def) .. "  " .. G.Bullet .. "  Lv " .. lv .. " / " .. H.cap(def, key) .. (stage > 0 and ("  " .. H.stars(stage)) or "")
	U.TrainName.TextColor3 = H.rarityText(def)
	if level < 1 then
		U.TrainSpots.Text = G.Lock .. " No Training Place yet"
	else
		U.TrainSpots.Text = "Training spots: " .. busyCount .. " / " .. slots .. " in use"
	end
	local job = H.job(key)
	U.TimerRow.Visible = job ~= nil
	local g = H.growth(key)
	if job then
		local total = tonumber(H.call(TycoonCatalog, "TrainSeconds", job.Rank)) or 60
		local left = math.max(0, (tonumber(job.Ends) or 0) - H.now())
		U.TrainTimer.SetFraction(total > 0 and math.min(1, 1 - left / total) or 1)
		if S.Tall then
			U.TrainTimer.SetText("Rank " .. tostring(job.Rank) .. ": " .. H.clock(left) .. " left")
		else
			U.TrainTimer.SetText(H.skillName(job.Stat) .. " Rank " .. tostring(job.Rank) .. ": " .. H.clock(left) .. " left")
		end
	end
	local top = S.Short and 44 or 72
	U.TimerRow.Position = UDim2.fromOffset(14, top)
	if job then
		top = top + 56
	end
	U.SkillList.Position = UDim2.fromOffset(8, top + 2)
	U.SkillList.Size = UDim2.new(1, -16, 1, -(top + 10))
	CloudUI.SetDisabled(U.StopTraining, H.inMatch())
	U.TrainSpots.Visible = not S.Short
	local maxRank = (TycoonCatalog and TycoonCatalog.Training and TycoonCatalog.Training.MaxRank) or 10
	for _, skill in ipairs(SKILLS) do
		local row = U.Skills[skill.Id]
		local rank = math.max(0, math.floor(tonumber(g[skill.Id]) or 0))
		row.Rank.Text = "Rank " .. rank .. "/" .. maxRank
		for p, pip in ipairs(row.Pips) do
			if p <= rank then
				pip.BackgroundColor3 = Theme.Lighten(ACCENTS.Train, 0.25)
			elseif job and job.Stat == skill.Id and p == rank + 1 then
				pip.BackgroundColor3 = PURPLE
			else
				pip.BackgroundColor3 = Color3.fromRGB(14, 20, 52)
			end
		end
		local maxed = rank >= maxRank
		row.Max.Visible = maxed
		row.Button.Visible = not maxed
		if maxed then
			row.Cost.Text = ""
		else
			local cost = H.call(TycoonCatalog, "TrainCost", def, rank + 1) or 0
			local seconds = H.call(TycoonCatalog, "TrainSeconds", rank + 1) or 60
			row.Cost.Text = "Rank " .. (rank + 1) .. ": " .. H.money(cost) .. ", " .. H.minutes(seconds)
			row.Cost.TextColor3 = cash < cost and Theme.Lighten(BAD, 0.35) or CASH
			row.Price = cost
			local reason = nil
			if job then
				reason = "busy"
			elseif level < 1 then
				reason = "no station"
			elseif busyCount >= slots then
				reason = "full"
			elseif cash < cost then
				reason = "cash"
			end
			row.Button.Text = (job and job.Stat == skill.Id) and "Training" or "Train"
			CloudUI.SetDisabled(row.Button, reason ~= nil or H.inMatch())
		end
	end
end

function H.refresh()
	if not S.Built then
		return
	end
	local home = H.home()
	local cash = H.cash()
	U.CashChip.Text = H.money(cash)
	U.Info.TextColor3 = MUTED
	local feedMode = S.Mode == "Feed"
	U.CashChip.Visible = not feedMode and not S.Tall
	U.Info.Visible = not feedMode
	U.Basket.Root.Visible = feedMode
	U.BasketIcon.Visible = feedMode
	U.BasketRate.Visible = feedMode
	U.FeedPage.Visible = S.Mode == "Feed"
	U.GardenPage.Visible = S.Mode == "Garden"
	U.TrainPage.Visible = S.Mode == "Train"
	if S.Mode == "Feed" then
		H.refreshFeed(home, cash)
	elseif S.Mode == "Garden" then
		H.refreshGarden(home)
	elseif S.Mode == "Train" then
		H.refreshTrain(home, cash)
	end
end

-- State.Changed can come in bursts: one refresh per frame at most
function H.refreshSoon()
	if S.RefreshPending then
		return
	end
	S.RefreshPending = true
	task.defer(function()
		S.RefreshPending = false
		if S.Open then
			safe("refresh", H.refresh)
		end
	end)
end

function H.relayout()
	if not S.Built then
		return
	end
	U.Dock.Refresh()
	local rect = U.Dock.Rect
	if not rect then
		return
	end
	local w, h = math.floor(rect.designW + 0.5), math.floor(rect.designH + 0.5)
	if S.Open then
		H.avoidRight(rect.mode == "Side" and rect.x or nil)
	end
	-- "short" (landscape phones): compact rows; "tall" (a narrow window with height): the one-column layouts
	local short = h < K.SHORT
	local tall = (not short) and w < K.TALL_W
	-- every docked Care window is narrow: the Training Place and the garden picker are one column at every size
	local oneCol = tall or short
	local stacked = tall or (w - 48) < K.WIDE
	local changed = short ~= S.Short or stacked ~= S.Stacked or tall ~= S.Tall
	S.Short, S.Stacked, S.Tall = short, stacked, tall
	-- landscape phones: no info line (the list needs the height); portrait: no Cash chip (the info line wraps)
	-- (landscape phones keep the Berry Basket bar in the Food Machine, the other windows drop their info line)
	local topH = short and ((S.Mode == "Feed") and 38 or 0) or K.TOP_H
	U.Top.Visible = topH > 0
	U.Top.Size = UDim2.new(1, -24, 0, topH)
	U.Top.Position = UDim2.fromOffset(12, 8)
	U.CashChip.Visible = not tall
	U.Info.Size = tall and UDim2.new(1, 0, 1, 0) or UDim2.new(1, -220, 1, 0)
	U.Body.Position = UDim2.fromOffset(12, topH + (short and 8 or 16))
	U.Body.Size = UDim2.new(1, -24, 1, -(topH + (short and 16 or 26)))
	-- feed footer
	local footH = short and K.FOOT_H_SHORT or K.FOOT_H
	if tall then
		footH = 150
	end
	U.Leftovers.Visible = not short
	U.Foot.Size = UDim2.new(1, 0, 0, footH)
	U.FeedList.Size = UDim2.new(1, 0, 1, -(footH + 10))
	if tall then
		U.Leftovers.Size = UDim2.new(1, -28, 0, 46)
		U.Leftovers.TextWrapped = true
		U.Leftovers.TextYAlignment = Enum.TextYAlignment.Top
		U.Machine.Size = UDim2.new(1, -28, 0, 50)
		U.Machine.Position = UDim2.fromOffset(14, 54)
		U.Upgrade.AnchorPoint = Vector2.new(1, 1)
		U.Upgrade.Position = UDim2.new(1, -12, 1, -8)
		U.Upgrade.Size = UDim2.fromOffset(170, 46)
	else
		U.Leftovers.TextWrapped = false
		U.Leftovers.Size = UDim2.new(1, -220, 0, 26)
		U.Machine.Size = UDim2.new(1, short and -170 or -220, 0, short and (footH - 12) or (footH - 44))
		U.Machine.Position = UDim2.fromOffset(14, short and 6 or 36)
		U.Upgrade.AnchorPoint = Vector2.new(1, 0.5)
		U.Upgrade.Position = UDim2.new(1, -12, 0.5, 0)
		U.Upgrade.Size = UDim2.fromOffset(short and 150 or 190, short and 48 or 54)
	end
	-- train: one column (the pets on top)
	if oneCol then
		U.TrainList.Size = UDim2.new(1, 0, 0.36, -6)
		U.TrainRight.AnchorPoint = Vector2.new(0, 1)
		U.TrainRight.Position = UDim2.new(0, 0, 1, 0)
		U.TrainRight.Size = UDim2.new(1, 0, 0.64, -6)
	else
		local listW = (w < 900) and math.min(300, math.floor(w * 0.4)) or K.TRAIN_LIST_W
		U.TrainList.Size = UDim2.new(0, listW, 1, 0)
		U.TrainRight.AnchorPoint = Vector2.new(1, 0)
		U.TrainRight.Position = UDim2.new(1, 0, 0, 0)
		U.TrainRight.Size = UDim2.new(1, -(listW + 12), 1, 0)
	end
	local skillH = short and K.SKILL_H_SHORT or K.SKILL_H
	for _, row in pairs(U.Skills) do
		row.Frame.Size = UDim2.new(1, 0, 0, tall and (skillH + 40) or skillH)
		if tall then
			row.Cost.AnchorPoint = Vector2.new(0, 1)
			row.Cost.Position = UDim2.new(0, 12, 1, -14)
			row.Cost.TextXAlignment = Enum.TextXAlignment.Left
			row.Name.Size = UDim2.new(1, -24, 0, 28)
			row.What.Size = UDim2.new(1, -24, 0, 26)
			row.Button.Size = UDim2.fromOffset(130, 46)
		else
			row.Cost.AnchorPoint = Vector2.new(1, 0)
			row.Cost.Position = UDim2.new(1, -12, 0, 8)
			row.Cost.TextXAlignment = Enum.TextXAlignment.Right
			row.Name.Size = UDim2.new(1, -250, 0, 28)
			row.What.Size = UDim2.new(1, -250, 0, 26)
			row.Button.Size = UDim2.fromOffset(150, short and 44 or 50)
		end
		row.What.Visible = not short or tall
	end
	-- the garden header
	U.GardenHead.Size = UDim2.new(1, 0, 0, tall and 118 or 72)
	U.GardenList.Position = UDim2.fromOffset(0, tall and 128 or 82)
	U.GardenList.Size = UDim2.new(1, 0, 1, -(tall and 128 or 82))
	U.GardenPlace.Size = UDim2.new(1, tall and -28 or -220, 0, 30)
	U.GardenNow.Size = UDim2.new(1, tall and -28 or -220, 0, tall and 48 or 26)
	U.GardenNow.TextWrapped = tall
	U.GardenNow.TextYAlignment = Enum.TextYAlignment.Top
	if tall then
		U.TakeOut.AnchorPoint = Vector2.new(1, 1)
		U.TakeOut.Position = UDim2.new(1, -12, 1, -8)
		U.TakeOut.Size = UDim2.fromOffset(160, 44)
	else
		U.TakeOut.AnchorPoint = Vector2.new(1, 0.5)
		U.TakeOut.Position = UDim2.new(1, -12, 0.5, 0)
		U.TakeOut.Size = UDim2.fromOffset(180, 50)
	end
	if changed then
		for _, row in pairs(U.Rows) do
			H.layoutFeedRow(row)
		end
		for _, row in pairs(U.GardenRows) do
			H.layoutSimpleRow(row)
		end
		if S.Open then
			H.refreshSoon()
		end
	end
	H.relayoutConfirm()
end

function H.relayoutConfirm()
	if not U.Confirm then
		return
	end
	local w, h, scale, x, y = H.confirmFit(K.CONFIRM_W, K.CONFIRM_H, 440, 250)
	U.Confirm.Size = UDim2.fromOffset(w, h)
	U.ConfirmFit.Scale = scale
	U.Confirm.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
end

----------------------------------------------------------------------
-- actions
----------------------------------------------------------------------
-- ONE feed (PetCare("Feed", key): the server checks everything again); a short basket or no machine says why here
function H.feed(key)
	if H.inMatch() then
		H.hint("Pets eat at home, after the match.", "info")
		return
	end
	local def = H.def(key)
	if not def then
		return
	end
	local home = H.home()
	local machine = H.station(home, "Kitchen")
	if machine < 1 then
		H.hint("Build the Food Machine at home first", "info")
		return
	end
	local level = H.level(key)
	if level >= H.cap(def, key) then
		return
	end
	local cost = H.berryFeed(key, def, level, machine).Cost
	local have = H.berries()
	if have < cost then
		H.hint("Not enough berries: a feed needs " .. H.commas(cost) .. " (you have " .. H.commas(have) .. "). Your garden pets grow more!", "bad")
		return
	end
	H.fire("feed:" .. key, "PetCare", "Feed", key)
end

function H.showConfirm(spec)
	if not U.Confirm then
		return
	end
	S.Confirm = spec
	U.ConfirmTitle.Text = spec.Title or ""
	U.ConfirmText.Text = spec.Text or ""
	U.ConfirmYes.Text = spec.Yes and (spec.YesText or "Yes") or "OK"
	CloudUI.SetStyle(U.ConfirmYes, spec.Style or "Gold")
	U.ConfirmStroke.Color = spec.Color or GOLD
	U.ConfirmTitle.TextColor3 = spec.Color or GOLD
	U.ConfirmNo.Text = spec.NoText or "Not now"
	H.relayoutConfirm()
	U.Confirm.Visible = true
	local pop = U.Confirm:FindFirstChild("Pop") or Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = U.Confirm:FindFirstChild("Box") })
	pop.Scale = 0.9
	H.tween(pop, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	H.syncBack()
end

function H.closeConfirm()
	S.Confirm = nil
	if U.Confirm then
		U.Confirm.Visible = false
	end
	H.syncBack()
end

function H.askTrain(key, stat)
	local def = key and H.def(key)
	if not def then
		return
	end
	if H.inMatch() then
		return
	end
	local g = H.growth(key)
	local rank = math.max(0, math.floor(tonumber(g[stat]) or 0)) + 1
	local cost = H.call(TycoonCatalog, "TrainCost", def, rank) or 0
	local seconds = H.call(TycoonCatalog, "TrainSeconds", rank) or 60
	local name = H.name(key, def)
	H.showConfirm({
		Kind = "Train",
		Title = G.Muscle .. " Train " .. H.skillName(stat) .. "?",
		Text = name .. " goes to Rank " .. rank .. " " .. H.skillName(stat) .. " for " .. H.money(cost) .. ". It takes "
			.. H.minutes(seconds) .. ". " .. name .. " rests at home until it's done, then comes back by itself.",
		YesText = "Train " .. H.money(cost),
		Style = "Green",
		Color = Theme.Lighten(GOOD, 0.2),
		Yes = function()
			H.fire("train", "PetCare", "Train", key, stat)
		end,
	})
end

-- the Cash a Stop gives back: the job's Paid (0 after a Prestige)
function H.paidOf(key)
	local job = H.job(key)
	return type(job) == "table" and tonumber(job.Paid) or 0
end

function H.askStop(key)
	local def = key and H.def(key)
	if not def or not H.job(key) then
		return
	end
	H.showConfirm({
		Kind = "Stop",
		Title = "Stop training?",
		Text = (H.paidOf(key) > 0 and "You get the Cash back, no rank. " or "No rank and no Cash back (it was paid before your Prestige). ")
			.. H.name(key, def) .. " comes back to you right away.",
		YesText = "Stop training",
		NoText = "Keep training",
		Style = "Pink",
		Color = Color3.fromRGB(255, 160, 200),
		Yes = function()
			H.fire("trainstop", "PetCare", "TrainStop", key)
		end,
	})
end

----------------------------------------------------------------------
-- the evolution moment (contract 3.6)
----------------------------------------------------------------------
function H.playerFrame()
	local char = LocalPlayer and LocalPlayer.Character
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	local cf
	if root and root:IsA("BasePart") then
		cf = root.CFrame
	else
		local cam = Workspace.CurrentCamera
		cf = cam and cam.CFrame or CFrame.new(0, 300, 0)
	end
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	return cf.Position, look.Unit, char
end

function H.groundAt(pos, char, fallback)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	if char then
		ignore[#ignore + 1] = char
	end
	if U.EvoFolder then
		ignore[#ignore + 1] = U.EvoFolder
	end
	params.FilterDescendantsInstances = ignore
	local ok, hit = pcall(function()
		return Workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -K.RAY, 0), params)
	end)
	if ok and hit then
		return hit.Position.Y
	end
	return fallback
end

-- lowest point of a built pet below its root
function H.bottomOf(model)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or typeof(cf) ~= "CFrame" then
		return -1.5
	end
	local root = model.PrimaryPart
	local rel = root and root.CFrame:PointToObjectSpace(cf.Position) or Vector3.new()
	return rel.Y - size.Y / 2
end

function H.evoFolder()
	if U.EvoFolder and U.EvoFolder.Parent then
		return U.EvoFolder
	end
	local f = Instance.new("Folder")
	f.Name = K.EVO_FOLDER
	f.Parent = Workspace
	U.EvoFolder = f
	return f
end

function H.closeAll()
	CareController.Close()
	for _, name in ipairs({ "MenuController", "IndexController", "FusionController" }) do
		local mod = H.controller(name)
		if mod and type(mod.Close) == "function" then
			pcall(mod.Close)
		end
	end
end

function H.playEvolution(key, stage)
	local def = H.def(key)
	local PetBuilder = safeRequire("PetBuilder")
	local Fx = H.controller("EvolutionFx")
	local PC = H.controller("PetController")
	stage = math.max(1, math.min(2, math.floor(tonumber(stage) or 1)))
	H.closeAll()
	local fxSeconds = (Fx and H.call(Fx, "Duration", stage)) or 4.6
	local release = function() end
	if PC and type(PC.PlayEvolution) == "function" then
		local ok, fn = pcall(PC.PlayEvolution, key, stage, { Seconds = fxSeconds + K.EVO_REST + 1 })
		if ok and type(fn) == "function" then
			release = fn
		end
	end
	if not (def and PetBuilder and Fx and type(Fx.Play) == "function") then
		release()
		return false
	end
	local okA, fromModel = pcall(PetBuilder.Build, def, { Detail = K.EVO_DETAIL, Evolved = (stage - 1 > 0) and (stage - 1) or nil })
	local okB, toModel = pcall(PetBuilder.Build, def, { Detail = K.EVO_DETAIL, Evolved = stage })
	if not (okA and okB and typeof(fromModel) == "Instance" and typeof(toModel) == "Instance" and fromModel.PrimaryPart and toModel.PrimaryPart) then
		release()
		return false
	end
	fromModel.Name = "Evolving_" .. tostring(def.Id)
	toModel.Name = "Evolved_" .. tostring(def.Id)
	local origin, look, char = H.playerFrame()
	local spot = Vector3.new(origin.X, 0, origin.Z) + look * K.EVO_AHEAD
	local ground = H.groundAt(Vector3.new(spot.X, origin.Y + 4, spot.Z), char, origin.Y - 3)
	local pos = Vector3.new(spot.X, ground + K.EVO_HOVER - H.bottomOf(fromModel), spot.Z)
	local pose = CFrame.lookAt(pos, pos - look) -- facing the player
	local folder = H.evoFolder()
	fromModel.Parent = folder
	local okColors, c1, c2 = pcall(PetBuilder.EvolutionColors, def, stage)
	S.Evolving = S.Evolving + 1
	local finished = false
	local function done(model)
		if finished then
			return
		end
		finished = true
		task.delay(K.EVO_REST, function()
			local at = nil
			if typeof(model) == "Instance" and model.PrimaryPart then
				at = model.PrimaryPart.Position
			end
			pcall(release, at)
			if typeof(model) == "Instance" then
				pcall(function()
					model:Destroy()
				end)
			end
			S.Evolving = math.max(0, S.Evolving - 1)
			H.nextEvolution()
		end)
	end
	local okPlay, handle = pcall(Fx.Play, fromModel, toModel, pose, {
		Parent = folder,
		Colors = okColors and { c1, c2 } or nil,
		Stage = stage,
		Ground = ground,
		Confetti = true,
		OnDone = done,
	})
	if not okPlay or type(handle) ~= "table" or handle.Done then
		pcall(function()
			fromModel:Destroy()
			toModel:Destroy()
		end)
		finished = true
		S.Evolving = math.max(0, S.Evolving - 1)
		release()
		return false
	end
	U.EvoHandle = handle
	return true
end

function H.nextEvolution()
	if S.Evolving > 0 then
		return
	end
	local nextOne = table.remove(S.EvoQueue, 1)
	if nextOne then
		safe("evolve", H.playEvolution, nextOne.Key, nextOne.Stage)
	end
end

----------------------------------------------------------------------
-- open / close
----------------------------------------------------------------------
-- HotbarController re-centres the hotbar left of the docked window (6.6); nil when nothing is docked
function H.avoidRight(x)
	local hb = H.controller("HotbarController")
	if hb and type(hb.SetAvoidRight) == "function" then
		pcall(hb.SetAvoidRight, x)
	end
end

-- gamepad B closes the confirm / the window while one is up (bound only then, so it never eats the dash)
function H.syncBack()
	local want = S.Open or S.Confirm ~= nil
	local ContextActionService = game:GetService("ContextActionService")
	if want and not S.BackBound then
		S.BackBound = true
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					if S.Confirm then
						H.closeConfirm()
					else
						CareController.Close()
					end
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.ButtonB)
		end)
	elseif not want and S.BackBound then
		S.BackBound = false
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

function H.closeOthers()
	for _, name in ipairs({ "MenuController", "IndexController", "FusionController" }) do
		local mod = H.controller(name)
		if mod and type(mod.Close) == "function" then
			pcall(mod.Close)
		end
	end
end

function CareController.IsOpen()
	return S.Open or S.Confirm ~= nil
end

function CareController.Mode()
	return S.Open and S.Mode or nil
end

function CareController.Evolving()
	return S.Evolving
end

-- the EVOLVE confirm ("Evolve Pebble Pup? +25% to everything") -> PetCare("Evolve", key)
function CareController.ConfirmEvolve(key)
	if not initialized then
		CareController.Init()
	end
	local def = H.def(key)
	if not def or not U.Gui then
		return false
	end
	if H.inMatch() then
		return false
	end
	local level = H.level(key)
	local nextStage = H.canEvolve(key, def, level)
	local name = H.name(key, def)
	if not nextStage then
		local levels = PetCatalog.EvolutionLevels or { 20, 50 }
		local stage = H.stage(key)
		local maxStage = H.call(PetCatalog, "MaxEvolution", def) or 1
		local text
		if stage >= maxStage then
			text = name .. " is fully evolved!"
		else
			text = name .. " evolves at level " .. tostring(levels[stage + 1] or 20) .. " (Lv " .. level .. " now)."
		end
		H.hint(text, "info")
		return false
	end
	local boosts = PetCatalog.EvolutionBoost or { 1.25, 1.5 }
	local pct = math.floor(((tonumber(boosts[nextStage]) or 1.25) - 1) * 100 + 0.5)
	H.showConfirm({
		Kind = "Evolve",
		Key = key,
		Title = G.Sparkle .. " Evolve " .. name .. "?",
		Text = name .. " changes into its " .. (nextStage == 2 and "Evolved II" or "Evolved") .. " form: +" .. pct
			.. "% to everything (battle power, health and coins). It keeps its level.",
		YesText = "EVOLVE!",
		Style = "Gold",
		Color = GOLD,
		Yes = function()
			H.fire("evolve", "PetCare", "Evolve", key)
		end,
	})
	return true
end

function CareController.Open(panelId, args)
	if not initialized then
		CareController.Init()
	end
	if not U.Gui then
		return false
	end
	args = type(args) == "table" and args or {}
	local id = type(panelId) == "string" and panelId:lower() or ""
	if id == "evolve" then
		if type(args.Key) ~= "string" then
			return false
		end
		if S.Evolving > 0 then
			S.EvoQueue[#S.EvoQueue + 1] = { Key = args.Key, Stage = args.Stage }
			return true
		end
		local ok, played = safe("evolve", H.playEvolution, args.Key, args.Stage)
		return ok and played == true
	end
	local mode = (id == "feed" and "Feed") or (id == "garden" and "Garden") or ((id == "train" or id == "training") and "Train") or nil
	if not mode then
		return false
	end
	if H.inMatch() then
		return false
	end
	if not H.buildWindow() then
		return false
	end
	if mode == "Feed" then
		S.Focus = type(args.Key) == "string" and args.Key or nil
	elseif mode == "Garden" then
		local slot = tonumber(args.Slot)
		S.Slot = (slot and slot == math.floor(slot) and slot >= 1) and slot or nil
		if not S.Slot then
			-- no place given: the first open empty one
			local home = H.home()
			local open = H.call(TycoonCatalog, "GardenSlots", home) or 0
			for s = 1, open do
				if type(home.Garden) ~= "table" or home.Garden[s] == nil then
					S.Slot = s
					break
				end
			end
			S.Slot = S.Slot or 1
		end
	elseif mode == "Train" then
		if type(args.Key) == "string" then
			S.TrainKey = args.Key
		end
	end
	local wasOpen = S.Open
	if not wasOpen then
		H.closeOthers()
	end
	if mode ~= S.Mode then
		-- a fresh list order for the new window (the viewports are kept per row)
		if U.FeedList then
			U.FeedList.CanvasPosition = Vector2.new(0, 0)
		end
	end
	S.Mode = mode
	S.Open = true
	S.Token = S.Token + 1
	U.Panel.SetTitle(TITLES[mode])
	if U.Panel.SetAccent then
		pcall(U.Panel.SetAccent, ACCENTS[mode])
	end
	H.relayout()
	U.Holder.Visible = true
	if not wasOpen then
		U.Pop.Scale = 0.86
		H.tween(U.Pop, 0.22, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	if U.Dock and U.Dock.Rect then
		H.avoidRight(U.Dock.Rect.mode == "Side" and U.Dock.Rect.x or nil)
	end
	safe("refresh", H.refresh)
	H.syncBack()
	-- timers tick while the window is open
	local mine = S.Token
	task.spawn(function()
		while S.Open and S.Token == mine do
			task.wait(K.TICK)
			if S.Open and S.Token == mine and (S.Mode == "Train" or S.Mode == "Feed" or S.Mode == "Garden") then
				safe("tick", H.refresh)
			end
		end
	end)
	CareController.Opened:Fire(mode)
	return true
end

function CareController.Close()
	if S.Confirm then
		H.closeConfirm()
	end
	if not S.Open then
		return
	end
	S.Open = false
	S.Token = S.Token + 1
	local mine = S.Token
	H.syncBack()
	if U.Pop then
		H.tween(U.Pop, 0.12, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(0.13, function()
		if S.Token == mine and not S.Open and U.Holder then
			U.Holder.Visible = false
		end
	end)
	H.avoidRight(nil)
	CareController.Closed:Fire()
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function H.onPrompt(prompt)
	if typeof(prompt) ~= "Instance" or prompt.Name ~= "GardenSpotPrompt" then
		return
	end
	local owner = prompt:GetAttribute("OwnerUserId")
	if owner ~= nil and LocalPlayer and owner ~= LocalPlayer.UserId then
		return -- someone else's garden (HomeFx hides those prompts anyway)
	end
	CareController.Open("Garden", { Slot = prompt:GetAttribute("Slot") })
end

function H.onOpenPanel(panelId, args)
	if type(panelId) ~= "string" then
		return
	end
	args = type(args) == "table" and args or {}
	local id = panelId:lower()
	if id == "train" or id == "training" or id == "evolve" then
		CareController.Open(panelId, args)
	elseif id == "feed" then
		CareController.Open("Feed", args)
	elseif id == "pets" and (args.Action == "Feed" or args.Action == "Garden") then
		CareController.Open(args.Action, args)
	end
end

function H.connectOthers()
	local function hook(name, signalName)
		local mod = H.controller(name)
		local signal = mod and mod[signalName]
		if type(signal) == "table" and type(signal.Connect) == "function" then
			signal:Connect(function()
				CareController.Close()
			end)
		end
	end
	hook("MenuController", "WindowOpened")
	hook("IndexController", "Opened")
	hook("FusionController", "Opened")
end

function CareController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)
	U.Gui = CloudUI.NewScreenGui("NimbusCare", K.DISPLAY_ORDER)
	H.buildConfirm()
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		safe("relayout", H.relayout)
		safe("relayout confirm", H.relayoutConfirm)
	end)
	State.Changed:Connect(function()
		if S.Open then
			H.refreshSoon()
		end
	end)
	if type(State.BerriesChanged) == "table" and type(State.BerriesChanged.Connect) == "function" then
		State.BerriesChanged:Connect(function()
			if S.Open then
				H.refreshSoon()
			end
		end)
	end
	if type(State.CashChanged) == "table" and type(State.CashChanged.Connect) == "function" then
		State.CashChanged:Connect(function()
			if S.Open then
				H.refreshSoon()
			end
		end)
	end
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if H.inMatch() then
				CareController.Close()
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			if S.Confirm then
				H.closeConfirm()
			elseif S.Open then
				CareController.Close()
			end
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		safe("prompt", H.onPrompt, prompt)
	end)
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, "OpenPanel")
		if ok and remote then
			remote.OnClientEvent:Connect(function(panelId, args)
				safe("OpenPanel", H.onOpenPanel, panelId, args)
			end)
		end
	end)
	task.defer(function()
		safe("connect", H.connectOthers)
	end)
end

return CareController
