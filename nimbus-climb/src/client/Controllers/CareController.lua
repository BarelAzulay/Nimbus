-- CareController (client, Phase 4): the pet-care windows of ARCHITECTURE_V3.md "Phase 4 build contract" 3.4-3.7.
-- gui-redo Task 7: the Training Place window lives in TrainController; this module forwards Train to it and keeps every
-- wire the Care window had (see "Train" below), so no other controller changes.
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
--       Train   (also "Training") forwards to TrainController.Open(args) and returns its answer: the Training Place
--               window (client/Controllers/TrainController.lua; args.Key / args.ReturnTo as before). While it is up,
--               Mode() is "Train" and IsOpen() is true; Opened:Fire("Train") / Closed:Fire() come from it through
--               NotifyTrain; Close() and the drop of the way back (another window, a match) close it too; opening Feed
--               or Garden closes it first.
--       Evolve  the evolution moment (the server's OpenPanel("Evolve", {Key, Stage}) after PetCare("Evolve")): every
--               window closes, PetController.PlayEvolution parks the follower of that key, EvolutionFx plays on two
--               fresh PetBuilder clones 5.5 studs in front of the player (with confetti), then the evolved clone
--               flies home as the follower (release(position)) and goes away
--       args.ReturnTo (team balance, Feed / Garden): the Pets window's own Open args; closing this window goes back
--               to it (same pet), unless another window or a match took over
--   CareController.Close()               closes the Training window (TrainController.Close), then this window and any confirm
--   CareController.CloseOwn()            closes only Feed / Garden (and the confirm), never forwards, never goes back to the
--                                        Pets window (the Training window opening calls it)
--   CareController.NotifyTrain(open)     TrainController's open / close: Opened:Fire("Train") / Closed:Fire()
--   CareController.IsOpen() -> true while a care window, a confirm or the Training window is up
--   Extras: CareController.Mode() -> "Feed" | "Garden" | "Train" | nil, CareController.ConfirmEvolve(key) (the EVOLVE
--           confirm, used by the Pets window too), CareController.FeedPlan(key, count) -> { Count, Price, Xp, Free,
--           Food, Levels } (what a request would do; the server decides), CareController.Evolving() -> plays running,
--           CareController.Opened / Closed (Util.Signal; Opened fires the mode)
--
-- How the windows open: the server's OpenPanel("Pets", {Action = "Feed"}) (FeedPrompt on the Food Machine) and
-- OpenPanel("Train") (TrainPrompt, forwarded) arrive here; MenuController forwards OpenPanel("Pets", {Action = "Feed" | "Garden"})
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
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7b) the stars, the where marks, the berry
local SignKit = require(Shared:WaitForChild("SignKit")) -- (kit-b U9-5) the docked window's title plate stays inside it
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
}
local ROLE_COLORS = { Economy = Color3.fromRGB(96, 196, 108), Combat = Color3.fromRGB(228, 104, 96) }
-- (kit-b U9-5) the Signboard palette (the pitch's kit B; one colour by role): brown ink on stone rows in the window's stone
-- body, sunk wells for the footer and the garden header, the rarity on a pet's well edge, gold for a pet ready to evolve;
-- green / violet text darkened until it reads on stone (4.5:1)
local SIGN = Theme.Sign
local INK = SIGN.Text
local SIGN_MUTED = SIGN.TextMuted
local GOOD_INK = Color3.fromRGB(46, 125, 50) -- #2E7D32: 5.1:1 on the stone tile

-- (kit-b U7b) the marks are PixelIcons, not emoji: a pet's evolution stars, where it is (training: the weight, the
-- garden: the sprout, following: the star), the berry basket
local ICON = { Star = "star", Training = "weight", Garden = "sprout", Following = "star", Berry = "berry" }

local TITLES = {
	Feed = "Food Machine",
	Garden = "Pet Garden",
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
	Mode = nil, -- "Feed" | "Garden" (the Training window is TrainController's)
	Token = 0,
	Built = false,
	Focus = nil, -- Feed: the pet to show first
	Slot = nil, -- Garden: the place the picker fills
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
local U = { Rows = {}, GardenRows = {} } -- ui references
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
		Color = color or INK, -- (kit-b U9-5) brown on stone
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
	p.ScrollBarImageColor3 = SIGN.Wood
	p.ScrollBarImageTransparency = 0.1
	p.Parent = parent
	return Util.Create("ScrollingFrame", p)
end

-- (kit-b U9-5) a square edge (a mitred border UIStroke named SignEdge)
function H.edge(parent, color, thickness)
	local s = Theme.Stroke(parent, color, thickness or 2, 0)
	s.Name = "SignEdge"
	s.LineJoinMode = Enum.LineJoinMode.Miter
	return s
end

-- (kit-b U9-5) a sunk stone well in a square edge (the footer, the garden header; was a navy inset)
function H.inset(parent, name, props)
	local p = props or {}
	p.BackgroundColor3 = SIGN.Well
	p.BackgroundTransparency = 0
	local f = H.frame(parent, name, p)
	H.edge(f, SIGN.WellEdge, 2)
	return f
end

-- (kit-b U9-5) a pet's row: a raised stone tile in a wood edge with a darker lip (gold when the pet can evolve)
function H.rowTile(parent, name, props)
	local p = props or {}
	p.BackgroundColor3 = SIGN.Tile
	p.BackgroundTransparency = 0
	local f = H.frame(parent, name, p)
	H.edge(f, SIGN.Wood, 2)
	H.frame(f, "Lip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.StoneLip,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 5),
	})
	return f
end

-- a solid coloured tag (role, status). (kit-b U9-5) square, in a wood edge, its colour nudged until its ink reads
-- (Theme.ReadableFace, 4.5:1); no gradient
function H.pill(parent, name, text, color, size, order)
	local px = size or 18
	local face, ink = Theme.ReadableFace(color, 4.5)
	local pill = Theme.Label(text, "Heading", {
		Size = px,
		Color = ink,
		Props = {
			Name = name,
			BackgroundTransparency = 0,
			BackgroundColor3 = face,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, px + 9),
			LayoutOrder = order or 0,
		},
	})
	H.edge(pill, SIGN.Wood, 2)
	H.pad(pill, 9, 0, 9, 1)
	pill.Parent = parent
	return pill
end

-- (kit-b U9-5) a kit B block (CloudUI.Button Skin "Sign": one colour by role, no glow)
function H.button(parent, name, text, style, size, textSize, callback)
	local b = CloudUI.Button({
		Name = name,
		Text = text,
		Style = style,
		Skin = "Sign",
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

-- how many evolution stars a pet shows (0-2; kit-b U7b: drawn as PixelIcons after its name)
function H.stars(stage)
	return (stage and stage > 0) and math.min(2, stage) or 0
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

-- a Color3 as RichText's "rrggbb"
function H.hex(c)
	local function byte(v)
		return math.max(0, math.min(255, math.floor(v * 255 + 0.5)))
	end
	return string.format("%02x%02x%02x", byte(c.R), byte(c.G), byte(c.B))
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

-- where a pet copy is: "Physique 2:10" (training) | "In Garden" | "Following" | nil, its colour and its PixelIcon
function H.whereText(key, home)
	local job = H.job(key)
	if job then
		local left = (tonumber(job.Ends) or 0) - H.now()
		return H.skillName(job.Stat) .. " " .. H.clock(left), SIGN.VioletLip, ICON.Training -- (kit-b U9-5) inks that read on stone
	end
	if #H.gardenSlots(home or H.home(), key) > 0 then
		return "In Garden", GOOD_INK, ICON.Garden
	end
	if H.equippedCount(key) > 0 then
		return "Following", SIGN.Wood, ICON.Following
	end
	return nil, SIGN_MUTED, nil
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

-- the small centred confirm (EVOLVE): its preferred size at the screen factor, shrunk to fit
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

-- the pet of a row: (kit-b U9-5) a square light well (the pitch's pet well) in its rarity's edge, the viewport inside
function H.petDisc(parent, def, size)
	local color = CloudUI.RarityColor(def and def.Rarity)
	local disc = H.frame(parent, "Pet", {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.PetWell,
		ZIndex = 3,
	})
	H.edge(disc, color, 3)
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
	U.Leftovers = H.text(foot, "Leftovers", "", "Heading", 18, INK, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -220, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	U.Machine = H.text(foot, "Machine", "", "Body", 19, INK, {
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -220, 0, 62),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	U.Upgrade = H.button(foot, "UpgradeMachine", "Upgrade", "Gray", UDim2.fromOffset(190, 54), 21, function()
		H.upgradeMachine()
	end)
	U.Upgrade.AnchorPoint = Vector2.new(1, 0.5)
	U.Upgrade.Position = UDim2.new(1, -12, 0.5, 0)
	U.FeedEmpty = H.text(page, "Empty", "", "Body", 20, SIGN_MUTED, {
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
	U.GardenPlace = H.text(head, "Place", "", "Title", 24, INK, {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -220, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Theme.StyleTitle(U.GardenPlace, "Section") -- (kit-b U9-5) a section head: the plain kit B title
	U.GardenNow = H.text(head, "Now", "", "Body", 18, SIGN_MUTED, {
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -220, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	U.TakeOut = H.button(head, "TakeOut", "Take out", "Red", UDim2.fromOffset(180, 50), 21, function()
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

-- the confirm (Evolve): its own holder above the window, so it also works over the Pets panel
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
	-- (kit-b U9-5) a stone notice in a wood frame; the plain kit B title (the ribbon is for window titles)
	local box = H.frame(holder, "Box", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Stone,
		ZIndex = 31,
	})
	U.ConfirmStroke = H.edge(box, SIGN.Wood, 6)
	U.ConfirmTitle = Theme.StyleTitle(H.text(box, "Title", "", "Title", 30, INK, {
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 40),
		TextScaled = true,
		ZIndex = 32,
	}), "Section")
	Util.Create("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 22, Parent = U.ConfirmTitle })
	U.ConfirmText = H.text(box, "Text", "", "Body", 20, INK, {
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
		Style = "Green", -- (kit-b U9-5) the dialog's one main action
		Skin = "Sign",
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
		Style = "Gray",
		Skin = "Sign",
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
		Skin = "Signboard", -- (kit-b U9-5) the pitch's window: awning, navy header with the berry, wood frame, stone body
		Icon = ICON.Berry,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		OnClose = function()
			CareController.Close()
		end,
		Parent = holder,
	})
	U.Panel = panel
	-- (kit-b U9-5) docked to the screen edge: no ribbon tails out over the frame (they ran off the screen)
	SignKit.HeaderOverhang(panel.TitleBar, false)
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel.Root })
	local content = panel.Content
	-- the info line + the Cash chip
	U.Top = H.frame(content, "Top", { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, K.TOP_H) })
	U.Info = H.text(U.Top, "Info", "", "Body", 19, SIGN_MUTED, {
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
		Color = SIGN.Roof,
		Skin = "Sign", -- (kit-b U9-5) a flat bar
		Parent = U.Top,
	})
	U.BasketIcon = H.text(U.Top, "BasketIcon", "", "Title", 26, SIGN.RedLip, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(30, 32),
	})
	PixelIcon.Host(U.BasketIcon, ICON.Berry, 27) -- (kit-b U7b)
	U.BasketRate = H.text(U.Top, "BasketRate", "", "Heading", 18, SIGN.RoofEdge, {
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
	row.Name = H.text(f, "Name", "", "Title", 23, INK, {
		Position = UDim2.fromOffset(K.VIEW + 22, 6),
		Size = UDim2.new(0, 300, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	row.Level = H.text(f, "Level", "", "Heading", 19, SIGN_MUTED, {
		Position = UDim2.fromOffset(K.VIEW + 22, 38),
		Size = UDim2.fromOffset(140, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	row.Where = H.text(f, "Where", "", "Heading", 18, SIGN_MUTED, {
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
	row.Name.Text = H.name(key, def)
	PixelIcon.Mark(row.Name, stars > 0 and ICON.Star or nil, { After = true, Count = stars, Of = stars, Colour = SIGN.GoldLip })
	row.Level.Text = "Lv " .. level .. " / " .. cap
	row.Level.TextColor3 = level >= cap and INK or SIGN_MUTED
	local where, color, icon = H.whereText(key, home)
	row.Where.Text = where or ""
	row.Where.TextColor3 = color
	PixelIcon.Mark(row.Where, where and icon or nil)
	return level, cap, stage
end

function H.newFeedRow(key, def)
	local row = { Key = key, Def = def }
	local f = H.rowTile(U.FeedList, "Feed_" .. key, { Size = UDim2.new(1, 0, 0, K.ROW_H) })
	row.Frame = f
	H.rowHead(f, row, def)
	row.Bar = CloudUI.Bar({
		Name = "XpBar",
		Position = UDim2.fromOffset(K.VIEW + 22, 70),
		Size = UDim2.new(0, 360, 0, 28),
		Height = 28,
		TextSize = 18,
		Color = XP,
		Skin = "Sign", -- (kit-b U9-5) a flat bar
		Parent = f,
	})
	local buttons = H.frame(f, "Buttons", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(K.BUTTONS_W, 60),
	})
	row.Buttons = buttons
	H.list(buttons, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	row.Feed = H.button(buttons, "Feed", "Feed", "Gray", UDim2.fromOffset(240, 58), 20, function()
		H.feed(key)
	end)
	row.Feed.LayoutOrder = 1
	row.Feed.RichText = true -- (a short basket shows the price in red: H.paintFeedRow)
	-- (Phase 5: no "Level up" button: ONE Feed button = one feed)
	row.Evolve = H.button(buttons, "Evolve", "EVOLVE!", "Gray", UDim2.fromOffset(122, 58), 20, function()
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
		-- (kit-b U9-5) every row's Feed is a peer: stone; H.oneGreen lights the window's one green action. A feed the basket
		-- cannot pay for shows its price in red (as Train's short TRAIN) and stays pressable, so it says why
		local price = H.commas(one.Cost) .. " berries"
		if H.berries() < one.Cost then
			price = '<font color="#' .. H.hex(SIGN.RedLip) .. '">' .. price .. "</font>"
		end
		row.Feed.Text = "Feed  " .. price .. "  (+" .. H.commas(one.Xp) .. " XP)"
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
		-- (kit-b U9-5) a pet that can evolve: the gold lip and the ink edge (the "selected" look)
		local edge = row.Frame:FindFirstChild("SignEdge")
		if edge then
			edge.Color = nextStage and INK or SIGN.Wood
		end
		local lip = row.Frame:FindFirstChild("Lip")
		if lip then
			lip.BackgroundColor3 = nextStage and SIGN.Gold or SIGN.StoneLip
		end
	end
end

function H.newGardenRow(key, def)
	local row = { Key = key, Def = def }
	local f = H.rowTile(U.GardenList, "Pick_" .. key, { Size = UDim2.new(1, 0, 0, K.ROW_H) })
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
	row.Put = H.button(f, "PutHere", "Put here", "Gray", UDim2.fromOffset(170, 56), 21, function()
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
	H.oneGreen(home)
	U.FeedEmpty.Visible = #keys == 0
	U.FeedEmpty.Text = "No pets yet! Spin a roulette in the Shop to hatch one."
	-- how it works (the kid rule, 3.4), always the same words
	U.Leftovers.Text = "Each Feed turns berries into XP. Your garden pets grow more berries!"
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
		U.Basket.SetText(H.basketText(H.commas(berries) .. " / " .. H.commas(math.floor(cap))))
	else
		U.Basket.SetFraction(berries > 0 and 1 or 0)
		U.Basket.SetText(H.basketText(H.commas(berries)))
	end
	U.BasketRate.Text = (type(income) == "number" and income > 0) and ("+" .. H.commas(math.floor(income * share * 60 + 0.5)) .. " a minute") or ""
	U.Info.Text = ""
end

-- (kit-b U9-5) one colour by role: the Food Machine's one green action is its next step, the first pet in the list that
-- can evolve (its EVOLVE), else the first one the basket holds a feed for (its Feed); every other button stays stone
function H.oneGreen(home)
	local rows = {}
	for _, row in pairs(U.Rows) do
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b)
		return a.Frame.LayoutOrder < b.Frame.LayoutOrder
	end)
	local lit = nil
	for _, row in ipairs(rows) do
		if row.Evolve.Visible and row.Evolve:GetAttribute("Disabled") ~= true then
			lit = row.Evolve
			break
		end
	end
	if not lit and H.station(home, "Kitchen") >= 1 then
		local have = H.berries()
		for _, row in ipairs(rows) do
			if row.Feed:GetAttribute("Disabled") ~= true and H.level(row.Key) < H.cap(row.Def, row.Key) and (tonumber(row.Cost) or math.huge) <= have then
				lit = row.Feed
				break
			end
		end
	end
	for _, row in ipairs(rows) do
		for _, b in ipairs({ row.Feed, row.Evolve }) do
			local style = (b == lit) and "Green" or "Gray"
			if b:GetAttribute("Style") ~= style then
				CloudUI.SetStyle(b, style)
			end
		end
	end
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
	-- (kit-b U9-5) each line with its shorter forms: H.fitGardenHead shows the longest one that fits on a phone
	if slot then
		local count = open > 0 and ("  (" .. open .. " open)") or ""
		S.GardenTexts = { "Garden place " .. slot .. count, "Place " .. slot .. count, "Place " .. slot }
	else
		S.GardenTexts = { "Pet Garden" }
	end
	if current and type(current) == "string" then
		local name = H.name(current)
		S.GardenNowTexts = { "Now here: " .. name .. ". Pick a pet to swap, or take it out.", "Now here: " .. name .. ".", name }
	elseif slot and slot > open then
		S.GardenNowTexts = { "This place opens with a Prestige.", "Opens with a Prestige." }
	else
		S.GardenNowTexts = { "Pick a pet: it eats at the Food Bowl and poops Cloud Cash.", "Pick a pet: it poops Cloud Cash.", "Pick a pet to work here." }
	end
	U.GardenPlace.Text = S.GardenTexts[1]
	U.GardenNow.Text = S.GardenNowTexts[1]
	U.TakeOut.Visible = type(current) == "string"
	H.fitGardenHead()
	CloudUI.SetDisabled(U.TakeOut, H.inMatch())
	U.Info.Text = "Every pet can work here: it eats at the Food Bowl and poops Cloud Cash!"
end

function H.refresh()
	if not S.Built then
		return
	end
	local home = H.home()
	local cash = H.cash()
	U.CashChip.Text = H.money(cash)
	U.Info.TextColor3 = SIGN_MUTED
	local feedMode = S.Mode == "Feed"
	U.CashChip.Visible = not feedMode and not S.Tall
	U.Info.Visible = not feedMode
	U.Basket.Root.Visible = feedMode
	U.BasketIcon.Visible = feedMode
	U.BasketRate.Visible = feedMode
	U.FeedPage.Visible = S.Mode == "Feed"
	U.GardenPage.Visible = S.Mode == "Garden"
	if S.Mode == "Feed" then
		H.refreshFeed(home, cash)
	elseif S.Mode == "Garden" then
		H.refreshGarden(home)
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

-- (kit-b U9-5) the garden header's two lines: the whole width when the Take out button is not beside them (portrait puts it
-- under them; an empty place has none), and on a narrow window the longest form of each line that fits its box (the
-- place line from 24 down to 18 px, the hint line from 18 down to 16; a portrait hint wraps). Widths are design px: the
-- label's share of the window times the dock's design width, so the open pop's scale does not count
function H.fitGardenHead()
	if not (U.GardenPlace and U.Panel and U.Dock) then
		return
	end
	local tall = S.Tall == true
	local wide = tall or not U.TakeOut.Visible
	U.GardenPlace.Size = UDim2.new(1, wide and -28 or -220, 0, 30)
	U.GardenNow.Size = UDim2.new(1, wide and -28 or -220, 0, tall and 48 or 26)
	local rect, root = U.Dock.Rect, U.Panel.Root
	local rootW = root and root.AbsoluteSize.X or 0
	if not rect or rootW <= 0 then
		return
	end
	local k = rect.designW / rootW
	local function fit(lbl, texts, maxSize, minSize, wrapped)
		if type(texts) ~= "table" or #texts == 0 then
			return
		end
		if wrapped then
			lbl.Text, lbl.TextSize = texts[1], maxSize
			return
		end
		local room = lbl.AbsoluteSize.X * k - 4 -- (2 px each side to spare)
		for _, t in ipairs(texts) do
			for size = maxSize, minSize, -1 do
				if Theme.MeasureLabel(lbl, t, size).X <= room then
					lbl.Text, lbl.TextSize = t, size
					return
				end
			end
		end
		lbl.Text, lbl.TextSize = texts[#texts], minSize
	end
	fit(U.GardenPlace, S.GardenTexts, 24, 18, false)
	fit(U.GardenNow, S.GardenNowTexts, 18, 16, tall)
end

-- (kit-b U9-5) "Berry Basket 1,240 / 3,000", or the numbers alone when the words do not fit the bar (a phone: the berry
-- icon beside it names it). Widths in design px, as H.fitGardenHead
function H.basketText(numbers)
	local full = "Berry Basket " .. numbers
	local label = U.Basket and U.Basket.Label
	local rect, root = U.Dock and U.Dock.Rect, U.Panel and U.Panel.Root
	local rootW = root and root.AbsoluteSize.X or 0
	if not (label and rect and rootW > 0) then
		return full
	end
	local room = label.AbsoluteSize.X * rect.designW / rootW - 8
	if room > 0 and Theme.MeasureLabel(label, full).X > room then
		return numbers
	end
	return full
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
	-- "short" (landscape phones): compact rows; "tall" (a narrow window with height): the one-column layouts
	local short = h < K.SHORT
	local tall = (not short) and w < K.TALL_W
	local stacked = tall or (w - 48) < K.WIDE
	local changed = short ~= S.Short or stacked ~= S.Stacked or tall ~= S.Tall
	S.Short, S.Stacked, S.Tall = short, stacked, tall
	-- landscape phones: no info line (the list needs the height); portrait: no Cash chip (the info line wraps)
	-- (landscape phones keep the Berry Basket bar in the Food Machine, the other windows drop their info line)
	local topH = short and ((S.Mode == "Feed") and 38 or 0) or K.TOP_H
	U.Top.Visible = topH > 0
	-- (kit-b U9-5) no roof on a phone: over the short window it covered the top bar
	if U.Panel.Roof then
		U.Panel.Roof.Visible = not (short or tall)
	end
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
	-- the garden header
	U.GardenHead.Size = UDim2.new(1, 0, 0, tall and 118 or 72)
	U.GardenList.Position = UDim2.fromOffset(0, tall and 128 or 82)
	U.GardenList.Size = UDim2.new(1, 0, 1, -(tall and 128 or 82))
	U.GardenNow.TextWrapped = tall
	H.fitGardenHead()
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
	-- (kit-b U9-5) Yes is the dialog's one green action (a red one stays red); brown title, the wood frame for every kind
	local style = spec.Style or "Green"
	CloudUI.SetStyle(U.ConfirmYes, (style == "Gold") and "Green" or style)
	U.ConfirmTitle.TextColor3 = INK
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

-- another window, a match or the evolution takes over: closing the care window does not go back to the Pets window
function H.dropReturn()
	S.ReturnTo = nil
	S.BackTo = nil
	S.EvoBack = nil
	local train = H.controller("TrainController")
	if train and type(train.DropReturn) == "function" then
		safe("training drop return", train.DropReturn)
	end
end

-- the Training window (TrainController) while it is up, else nil
function H.trainOpen()
	local train = H.controller("TrainController")
	if train and type(train.IsOpen) == "function" and train.IsOpen() then
		return train
	end
	return nil
end

-- what an Evolve's cinematic closes and brings back after it: the Pets window when a panel waits behind it (Ring, Dungeon,
-- Arena, the loss screen: its own Close then follows that chain). A window with nothing behind it stays closed.
function H.evolveBack()
	if S.EvoBack then
		return S.EvoBack
	end
	if type(S.ReturnTo) == "table" and S.ReturnTo.ReturnTo then
		return S.ReturnTo
	end
	local pets = H.controller("PetsController")
	if pets and type(pets.ReturnArgs) == "function" then
		return pets.ReturnArgs()
	end
	return nil
end

-- the last cinematic is over: back, unless another window (H.dropReturn), a match or a battle took over meanwhile
function H.evolutionOver()
	local back = S.EvoBack
	S.EvoBack = nil
	local pets = back and H.controller("PetsController")
	local battle = LocalPlayer and LocalPlayer:GetAttribute(Config.Attr.InBattle)
	if pets and not H.inMatch() and (battle == nil or battle == false or battle == "") then
		safe("back to pets", pets.Open, back)
	end
end

function H.closeAll()
	H.dropReturn()
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
	local back = H.evolveBack()
	H.closeAll()
	S.EvoBack = back
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
		H.evolutionOver()
		return false
	end
	local okA, fromModel = pcall(PetBuilder.Build, def, { Detail = K.EVO_DETAIL, Evolved = (stage - 1 > 0) and (stage - 1) or nil })
	local okB, toModel = pcall(PetBuilder.Build, def, { Detail = K.EVO_DETAIL, Evolved = stage })
	if not (okA and okB and typeof(fromModel) == "Instance" and typeof(toModel) == "Instance" and fromModel.PrimaryPart and toModel.PrimaryPart) then
		release()
		H.evolutionOver()
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
		H.evolutionOver()
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
	else
		H.evolutionOver()
	end
end

----------------------------------------------------------------------
-- open / close
----------------------------------------------------------------------
-- (kit-b U9-5) on a touch-only device Roblox's thumbstick and jump button go while Feed / Garden is up (the sheet fills the
-- bottom of a phone: its footer and its Put here buttons sat under them), as the Training Place and the Fusion Machine do
-- (MenuController.SetTouchHidden("Care")); they come back as they were on close
function H.syncTouch()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local want = S.Open and touchOnly
	if want == (S.TouchOff == true) then
		return
	end
	S.TouchOff = want
	local menu = H.controller("MenuController")
	if menu and type(menu.SetTouchHidden) == "function" then
		safe("touch", menu.SetTouchHidden, "Care", want)
	end
end

-- gamepad B closes the confirm / the window while one is up (bound only then, so it never eats the dash)
function H.syncBack()
	H.syncTouch()
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
	return S.Open or S.Confirm ~= nil or H.trainOpen() ~= nil
end

function CareController.Mode()
	if S.Open then
		return S.Mode
	end
	return H.trainOpen() and "Train" or nil
end

-- TrainController's window opened (true) / closed (false): the signals the Care window always fired for Train
function CareController.NotifyTrain(open)
	if open then
		CareController.Opened:Fire("Train")
	else
		CareController.Closed:Fire()
	end
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
	-- Phase 5 (3.1): EVOLVE multiplies the level bonus (x1.5 / x1.875), not the stat
	local bonus = tonumber(H.call(PetCatalog, "EvolutionBonusOf", nextStage)) or (nextStage == 2 and 1.875 or 1.5)
	local bonusText = string.format("%.3f", bonus):gsub("0+$", ""):gsub("%.$", "")
	H.showConfirm({
		Kind = "Evolve",
		Key = key,
		Title = "Evolve " .. name .. "?",
		Text = name .. " changes into its " .. (nextStage == 2 and "Evolved II" or "Evolved") .. " form: Level bonus x" .. bonusText
			.. " (battle power, health and coins). It keeps its level.",
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
	if id == "train" or id == "training" then
		-- the Training Place window is TrainController's (gui-redo Task 7)
		local train = H.controller("TrainController")
		if not (train and type(train.Open) == "function") then
			return false
		end
		local ok, opened = safe("open training", train.Open, args)
		return ok and opened == true
	end
	local mode = (id == "feed" and "Feed") or (id == "garden" and "Garden") or nil
	if not mode then
		return false
	end
	-- the Training window gives way (no way back to the Pets window from it: this window takes over)
	local train = H.trainOpen()
	if train then
		safe("training drop return", train.DropReturn)
		safe("close training", train.Close)
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
	end
	local wasOpen = S.Open
	if not wasOpen then
		H.closeOthers()
		S.BackTo = nil
		S.ReturnTo = type(args.ReturnTo) == "table" and args.ReturnTo or nil
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
	safe("refresh", H.refresh)
	H.syncBack()
	-- timers tick while the window is open
	local mine = S.Token
	task.spawn(function()
		while S.Open and S.Token == mine do
			task.wait(K.TICK)
			if S.Open and S.Token == mine and (S.Mode == "Feed" or S.Mode == "Garden") then
				safe("tick", H.refresh)
			end
		end
	end)
	CareController.Opened:Fire(mode)
	return true
end

-- Feed / Garden (and the confirm)
function H.closeOwn()
	if S.Confirm then
		H.closeConfirm()
	end
	if not S.Open then
		return
	end
	S.Open = false
	S.Token = S.Token + 1
	local mine = S.Token
	local back = S.ReturnTo
	S.ReturnTo = nil
	H.syncBack()
	if U.Pop then
		H.tween(U.Pop, 0.12, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(0.13, function()
		if S.Token == mine and not S.Open and U.Holder then
			U.Holder.Visible = false
		end
	end)
	CareController.Closed:Fire()
	if back then
		-- came from the Pets window: back to it next, unless what closed this one takes over (H.dropReturn)
		S.BackTo = back
		task.defer(function()
			if S.BackTo == back then
				S.BackTo = nil
				local pets = H.controller("PetsController")
				if pets and not H.inMatch() then
					safe("back to pets", pets.Open, back)
				end
			end
		end)
	end
end

function CareController.Close()
	-- the Training window first (before the "nothing open" return below): every caller that closes the Care window today
	-- (Arena, Dungeon, Obby, RaidGate, the window hooks, a match) closes Training too
	local train = H.controller("TrainController")
	if train and type(train.Close) == "function" then
		safe("close training", train.Close)
	end
	H.closeOwn()
end

-- only Feed / Garden: the Training window opening closes it this way (no forwarding, no way back to the Pets window)
function CareController.CloseOwn()
	S.ReturnTo = nil
	S.BackTo = nil
	H.closeOwn()
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
				H.dropReturn()
				CareController.Close()
			end)
		end
	end
	hook("MenuController", "WindowOpened")
	hook("IndexController", "Opened")
	hook("FusionController", "Opened")
	hook("ArenaController", "Opened")
	hook("DungeonController", "Opened")
	hook("ObbyController", "Opened")
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
				H.dropReturn()
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
