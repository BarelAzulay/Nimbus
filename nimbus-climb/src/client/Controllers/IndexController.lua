-- IndexController (client, v3): the Pet Index window (ARCHITECTURE_V3.md section 3, 10 and 11).
--
--   IndexController.Init()
--   IndexController.Open(groupId|nil)    -- groupId = a rarity id ("Common" .. "Secret"); nil = last / best group
--   IndexController.Close()
--   Extras: IndexController.IsOpen() -> bool, IndexController.ClaimableCount() -> n,
--           IndexController.Opened (Util.Signal, Fire(groupId) when the window opens),
--           IndexController.Closed (Util.Signal, Fire() when it closes),
--           IndexController.Metrics (the K table; MEASURE: a tab-name width hook for the offline renderer and tests)
--
-- MenuController opens it from the menu "Index" tile and from OpenPanel("Index"), and relays Opened as
-- MenuController.WindowOpened("Index") (the tutorial listens there). This module never requires
-- MenuController at load (no require cycle; it looks it up at open / close time for SetTouchHidden, and at click time
-- for the Home window). Open("Fusions") opens the Fusions tab.
--
-- kit-b U8: the window is a kit B sign (CloudUI.Panel Skin "Signboard", the book on its header): stone wells with brown
-- ink, no glow, gloss or neon border. The rarity groups are signboard tabs (a stone tab with the rarity on its lip, the
-- selected one gold-faced; in the tall layout's strip a whole number of tabs fills the strip, so none shows cut, and the
-- names sit at a fixed size that fits left of the badge corner, the count on the bar row under them). A pet tile is the Pets window's card: a stone tile, the pet in its light well, the
-- rarity on its lip (attribute Rarity), the element as a chip with its drawn icon. On a touch phone Roblox's thumbstick
-- and jump button go while the window is open (MenuController.SetTouchHidden("Index"), as Pets, Shop and Gifts do): the
-- jump button sat on CLAIM at 844x390.
--
-- Phase 2 (ARCHITECTURE_V3.md section 11 + "Phase 2 build contract"): a "Fusions" tile under the rarity groups
-- lists every fused pet the player owns: hybrids (mixed at the Fusion Machine, one of a kind) and Golden / Rainbow
-- copies, each with its look (PetKeys.DefOf: merged hybrid looks, tier finishes), a tier / hybrid badge and its
-- level. Fusions are not part of the group rewards: the rewards box explains how to fuse instead (and opens the
-- Fusion Machine window once the player has one). The detail card shows the tier, the parents of a hybrid, both
-- elements, and the stats at the pet's level x its tier.
--
-- Layout (cloud-styled through CloudUI, like the reference "Pet Index" window):
--   title bar "Pet Index" + red X
--   left    vertical group list: one rarity tab per rarity group with "3/6" progress,
--           a check when its reward is claimed and a red "!" when it can be claimed; an "Elements" card button
--   centre  group header with an x/N progress bar, a grid of pet tiles (ViewportFrame of the pet; pets not
--           discovered yet are black silhouettes via ViewportFrame.ImageColor3 = (0, 0, 0) with a "???"
--           caption), and the rewards box ("Rewards:" + the token amount) with a CLAIM button (green when
--           claimable, grey otherwise, "Claimed" when done) -> Remotes.IndexClaim(groupId)
--   right   detail card: big viewport, name or "???", rarity, element badge with "Strong vs / Weak vs",
--           Role, stats and the special attack once discovered (Stormfang also shows its 2D art banner)
--   footer  "Unlocked: x/N" over every pet in the catalog
-- The window is designed in 1080p pixels (readability rule: body 19, captions >= 18, buttons 22+, titles
-- 28-34) under ONE UIScale = min(screen factor, fit); its size adapts between 900x420 and 1240x760 design
-- pixels so phones keep a readable scale, every column scrolls when space is short.
-- Pet viewports are built under a per-frame time budget (only for the shown group), silhouettes never animate,
-- and every viewport runs on CloudUI's one shared update loop. Esc / gamepad B / the X / a click outside closes it.
--
-- Remotes: IndexClaim (out, rate-limited here and validated + rate-limited by the server).
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7a) the reward's Cloud Token coin
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local State = require(Client:WaitForChild("State"))

local function safeRequire(name)
	local ok, result = pcall(function()
		return require(Shared:WaitForChild(name, 10))
	end)
	if ok and type(result) == "table" then
		return result
	end
	warn("[IndexController] " .. name .. " is unavailable: " .. tostring(result))
	return nil
end

local PetCatalog = safeRequire("PetCatalog") or { Pets = {}, Get = function() return nil end }
local BattleCatalog = safeRequire("BattleCatalog")

local IndexController = {}
IndexController.Opened = Util.Signal()
IndexController.Closed = Util.Signal()

----------------------------------------------------------------------
-- Tunables (design pixels of a 1080p screen)
----------------------------------------------------------------------
local K = {
	PREF_W = 860, -- Phase 5 (6.6): docked right / a bottom sheet (NeonKit.Dock), 860 x 900 design px
	PREF_H = 900,
	MIN_W = 800,
	MIN_H = 380,
	MARGIN = 12, -- screen px kept free around the window
	NARROW = 1100, -- below this design width the side columns get narrower
	SHORT = 560, -- below this design height the compact layout is used (landscape phones)
	GROUP_W = 236,
	GROUP_W_NARROW = 184,
	DETAIL_W = 336,
	DETAIL_W_NARROW = 264,
	GAP = 12,
	TILE_W = 126,
	TILE_H = 154,
	TILE_W_NARROW = 114,
	TILE_H_NARROW = 142,
	TILE_H_SHORT = 132,
	TILE_GAP = 10,
	HEADER_H = 58,
	HEADER_H_SHORT = 48,
	REWARD_H = 96,
	REWARD_H_SHORT = 62,
	FOOTER_H = 46,
	VIEW_H = 180,
	VIEW_H_SHORT = 140,
	GROUP_TILE_H = 60, -- 7 rarity groups + the Fusions tile fit a 1080p window without scrolling
	GROUP_TILE_H_SHORT = 56,
	-- portrait screens (a phone held upright): the window may get as narrow as TALL_MIN_W and as tall as TALL_MAX_H
	-- design px, and below TALL design px wide it stacks: a strip of group tiles, the grid, the detail card
	TALL_MIN_W = 420,
	TALL_MAX_H = 1100,
	TALL = 760,
	STRIP_H = 64, -- the group strip of the tall layout (tiles + room for its scroll bar)
	STRIP_TILE_W = 150,
	-- (kit-b U8 review) a tab's name row: the name from TAB_NAME_X to the badge corner (the badge is 28 px centred 8 px in
	-- from the right edge, so the name stops TAB_BADGE_W short of it), sized down from 24 (column) / 20 (strip) to NAME_MIN
	-- until it fits with NAME_SPARE px to spare; the count sits on the bar row under it
	TAB_NAME_X = 12,
	TAB_BADGE_W = 22,
	NAME_MIN = 18,
	NAME_SPARE = 2,
	STRIP_TILE_MIN_W = 134, -- (kit-b U8) the narrowest strip tab: "Uncommon" (96.4 px of FredokaOne at 18) and its badge corner
	-- (U8 review) a tab name's width in px: nil = Theme.MeasureLabel (TextService knows FredokaOne in Roblox); the offline
	-- renderer and the tests put real font metrics here (the mock's TextService is a flat 0.5 em). (text, size, font) -> px
	MEASURE = nil,
	STRIP_PAD_L = 4, -- the strip's left padding and the gap between two tabs
	STRIP_GAP = 6,
	PANEL_INSET_W = 24, -- the Neon panel's content inset (left + right, design px)
	REWARD_ROOMY_W = 480, -- a reward box narrower than this (design px) gets the 150 x 52 CLAIM button
	REWARD_LABEL_W = 112, -- "Rewards:" (Heading 22) and its gap
	REWARD_AMOUNT_W = 140, -- the widest amount (the Secret group's "<coin> 10,000" in Display 30)
	REWARD_SUB_MIN_W = 150, -- narrower than this, the line under the amount is left out (no 4-line wrap)
	ELEMENTS_STRIP_W = 132,
	ELEMENTS_BTN_H = 52,
	ELEMENTS_BTN_H_SHORT = 44,
	-- pet viewports are attached under a per-frame TIME budget: the first of a frame always, more only while the
	-- frame has spent < TILE_BUDGET s and at most TILES_MAX (a first-time High sculpt of ~350 parts costs tens of
	-- ms, a cached clone a few: a fixed count hitched on fresh clients)
	TILE_BUDGET = 0.004,
	TILES_MAX = 3,
	TILE_LIP = 6, -- (kit-b U8) px of a pet tile's rarity lip (the Pets cards' CARD_LIP)
	CLAIM_GAP = 0.6, -- seconds between two IndexClaim sends
	CLAIM_TIMEOUT = 5, -- seconds the CLAIM button waits for the server before it resets
	BACK_ACTION = "NimbusIndexBack",
	DISPLAY_ORDER = 21, -- above NimbusMenu (20): on small screens the window may cover the menu column
}
IndexController.Metrics = K

local Colors = Theme.Colors
-- (kit-b U8) the Signboard palette: brown ink on stone and in the wells, wood edges
local SIGN = Theme.Sign
local INK = SIGN.Text
local MUTED = SIGN.TextMuted
local GOLD = SIGN.Gold
local SILHOUETTE = Color3.new(0, 0, 0)
local ROLE_COLORS = { Economy = Color3.fromRGB(96, 196, 108), Combat = Color3.fromRGB(228, 104, 96) }
-- (kit-b U7b) the window's marks are PixelIcons, not emoji (the title says "Pet Index" in words: the menu tile has the book)
local ICON = { Check = "check", Star = "star", Arrow = "play", Swap = "swap", Sparkle = "sparkle" }

----------------------------------------------------------------------
-- Module state
----------------------------------------------------------------------
local initialized = false
local LocalPlayer = nil
local U = {} -- UI references
local S = {
	Built = false,
	Open = false,
	Token = 0, -- bumps on every open / close (cancels stale delays)
	GroupId = nil, -- selected group
	PetId = nil, -- selected pet
	Groups = {}, -- PetCatalog.IndexGroups() result
	GroupById = {},
	GroupTiles = {}, -- groupId -> tile widgets
	Tiles = {}, -- petId -> tile widgets of the shown group
	TileOrder = {},
	Filling = false,
	DetailKey = nil, -- "<petId>|<discovered>" of the detail viewport
	DetailViewport = nil,
	DetailPills = {},
	PillKey = nil,
	Narrow = false,
	ClaimPending = nil, -- groupId while a claim waits for the server
	ClaimToken = 0,
	LastClaim = 0,
	BackBound = false,
	ElementsShown = false,
	StatMax = nil,
	FusionTile = nil, -- the "Fusions" group tile
	FusionSig = nil, -- the fusion keys shown in the grid (rebuilt when they change)
}
local FUSIONS = "Fusions" -- the Fusions tab's group id
local warned = {}
local claimRemote = nil

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function warnOnce(key, err)
	if not warned[key] then
		warned[key] = true
		warn("[IndexController] " .. tostring(key) .. ": " .. tostring(err))
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

-- Theme-styled TextLabel. kit-b U6: every Index text sits on the window or a card, so it reads by contrast and has no
-- outline (was a 0.25 classic stroke under a 1.5 px glyph outline).
local function makeText(parent, name, text, role, size, color, props)
	local p = { Name = name }
	if props then
		for key, value in pairs(props) do
			p[key] = value
		end
	end
	local label = Theme.Label(tostring(text), role, {
		Size = size,
		Color = color or INK,
		Props = p,
	})
	label.Parent = parent
	return label
end

-- radius: a Theme.Radius token ("S", "M"; kit-b U6), "M" by default
local function corner(parent, radius)
	return Theme.Corner(parent, radius or "M")
end

local function stroke(parent, color, thickness, transparency)
	return Theme.Stroke(parent, color or SIGN.Wood, thickness or 3, transparency or 0)
end

-- (kit-b U8) a square edge with mitred corners (kit B has no rounded blocks)
local function edge(parent, color, thickness)
	local s = stroke(parent, color, thickness, 0)
	s.LineJoinMode = Enum.LineJoinMode.Miter
	return s
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

-- (kit-b U8) a sunk stone well (the pitch's .wl): flat, its own darker edge
local function inset(parent, name, props)
	local p = props or {}
	p.BackgroundColor3 = SIGN.Well
	p.BackgroundTransparency = 0
	local frame = makeFrame(parent, name, p)
	edge(frame, SIGN.WellEdge, 2)
	return frame
end

-- a small square tag (the pitch's .chp): the colour, the ink that reads on it, a wood edge (a mid-tone that no ink reads
-- 4.5:1 on is lightened until brown does)
local function signPill(text, color, parent)
	for _ = 1, 6 do
		if Theme.Contrast(Theme.TextOn(color), color) >= 4.6 then
			break
		end
		color = Theme.Lighten(color, 0.08)
	end
	local pill = Theme.Label(tostring(text or ""), "Heading", {
		Size = 18,
		Color = Theme.TextOn(color),
		Props = {
			Name = "Pill",
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 28),
			TextXAlignment = Enum.TextXAlignment.Center,
		},
	})
	edge(pill, SIGN.Wood, 2)
	pad(pill, 9, 0, 9, 0)
	Util.Create("UISizeConstraint", { MinSize = Vector2.new(34, 28), Parent = pill })
	pill.Parent = parent
	return pill
end

local function rarityColor(rarityId)
	return CloudUI.RarityColor(rarityId)
end

-- A rarity colour that still reads as a colour on dark panels (the Secret rarity is near-black).
local function rarityAccent(rarityId)
	local color = rarityColor(rarityId)
	if rarityId == "Secret" then
		return Color3.fromRGB(150, 110, 232)
	end
	return color
end

local function commas(n)
	return Util.Commas(tonumber(n) or 0)
end

----------------------------------------------------------------------
-- Data helpers
----------------------------------------------------------------------
local function loadGroups()
	local groups = {}
	if type(PetCatalog.IndexGroups) == "function" then
		local ok, result = pcall(PetCatalog.IndexGroups)
		if ok and type(result) == "table" then
			groups = result
		end
	end
	if #groups == 0 then
		-- older catalog: one group per rarity from the pet list
		local byRarity = {}
		for _, def in ipairs(PetCatalog.Pets or {}) do
			local id = def.Rarity
			if type(id) == "string" then
				if not byRarity[id] then
					local rewards = Config.Index and Config.Index.Rewards or {}
					byRarity[id] = { Id = id, Rarity = id, Pets = {}, Reward = rewards[id] or { Tokens = 0 } }
				end
				table.insert(byRarity[id].Pets, def)
			end
		end
		for _, r in ipairs(Config.Rarities) do
			if byRarity[r.Id] then
				table.insert(groups, byRarity[r.Id])
			end
		end
	end
	local clean = {}
	for _, group in ipairs(groups) do
		if type(group) == "table" and type(group.Id) == "string" and type(group.Pets) == "table" and #group.Pets > 0 then
			table.insert(clean, group)
		end
	end
	S.Groups = clean
	S.GroupById = {}
	for _, group in ipairs(clean) do
		S.GroupById[group.Id] = group
	end
end

local function totalPets()
	if type(PetCatalog.TotalCount) == "function" then
		local ok, n = pcall(PetCatalog.TotalCount)
		if ok and type(n) == "number" then
			return n
		end
	end
	return #(PetCatalog.Pets or {})
end

local function unlockedCount()
	local n = 0
	for _, def in ipairs(PetCatalog.Pets or {}) do
		if State.IsDiscovered(def.Id) then
			n = n + 1
		end
	end
	return n
end

-- found, total, complete, claimed, claimable
local function groupStatus(group)
	local found = 0
	for _, def in ipairs(group.Pets) do
		if State.IsDiscovered(def.Id) then
			found = found + 1
		end
	end
	local total = #group.Pets
	local complete = total > 0 and found >= total
	local claimed = State.IsClaimed(group.Id)
	return found, total, complete, claimed, complete and not claimed
end

local function rewardTokens(group)
	local reward = group and group.Reward
	if type(reward) ~= "table" then
		local rewards = Config.Index and Config.Index.Rewards
		reward = rewards and group and rewards[group.Id]
	end
	if type(reward) == "table" and type(reward.Tokens) == "number" then
		return reward.Tokens
	end
	return 0
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

local function elementColor(element)
	local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[element]
	return info and info.Color or Colors.PanelLight
end

-- "Strong vs Flame  /  Weak vs Storm" for one element.
local function matchupText(element)
	local strongMap = Config.Elements and Config.Elements.Strong
	if type(strongMap) ~= "table" then
		return ""
	end
	local strong = {}
	for _, e in ipairs(strongMap[element] or {}) do
		table.insert(strong, e)
	end
	local weak = {}
	for attacker, list in pairs(strongMap) do
		for _, e in ipairs(list) do
			if e == element then
				table.insert(weak, attacker)
			end
		end
	end
	table.sort(weak)
	local parts = {}
	if #strong > 0 then
		table.insert(parts, "Strong vs " .. table.concat(strong, ", "))
	end
	if #weak > 0 then
		table.insert(parts, "Weak vs " .. table.concat(weak, ", "))
	end
	return table.concat(parts, "   " .. "/" .. "   ")
end

-- Power and Health are battle numbers (BattleCatalog.BattleStatsOf, so one window never shows two answers); Coins and Speed
-- stay the garden's. Writes into `stats`, a fresh table from PetCatalog.GetStats / StatsOf.
local function withBattleStats(stats, subject, level)
	if type(stats) == "table" and BattleCatalog and type(BattleCatalog.BattleStatsOf) == "function" then
		local ok, battle = pcall(BattleCatalog.BattleStatsOf, subject, level)
		if ok and type(battle) == "table" then
			stats.Power, stats.Health = battle.Power, battle.Health
		end
	end
	return stats
end

-- The highest shown stat of the catalog per key at level 1 (bar lengths are relative to it).
local function statMax()
	if S.StatMax then
		return S.StatMax
	end
	local out = {}
	local keys = PetCatalog.StatOrder or { "Income", "Power", "Health", "Speed" }
	for _, key in ipairs(keys) do
		out[key] = 1
	end
	if type(PetCatalog.GetStats) == "function" then
		for _, def in ipairs(PetCatalog.Pets or {}) do
			local ok, stats = pcall(PetCatalog.GetStats, def.Id, 1)
			if ok and type(stats) == "table" then
				withBattleStats(stats, def.Id, 1)
				for _, key in ipairs(keys) do
					local v = stats[key]
					if type(v) == "number" and v > out[key] then
						out[key] = v
					end
				end
			end
		end
	end
	S.StatMax = out
	return out
end

-- Where a pet can be found ("Cloud Roulette, Storm Roulette"), or nil.
local function sourcesText(def)
	if type(PetCatalog.PossiblePets) ~= "function" then
		return nil
	end
	local names = {}
	for _, roulette in ipairs(Config.Roulettes or {}) do
		local ok, list = pcall(PetCatalog.PossiblePets, roulette.Id)
		if ok and type(list) == "table" then
			for _, entry in ipairs(list) do
				if entry == def or (type(entry) == "table" and entry.Id == def.Id) then
					table.insert(names, roulette.DisplayName or roulette.Id)
					break
				end
			end
		end
	end
	if #names == 0 then
		return nil
	end
	return table.concat(names, ", ")
end

local function getClaimRemote()
	if claimRemote then
		return claimRemote
	end
	local ok, remote = pcall(Remotes.Get, "IndexClaim")
	if ok and remote then
		claimRemote = remote
	end
	return claimRemote
end

----------------------------------------------------------------------
-- Phase 2: fused pets (pet copy keys, shared/PetKeys through State)
----------------------------------------------------------------------
local FUSION_COLOR = Color3.fromRGB(150, 110, 232)
local TIER_COLORS = { Golden = Color3.fromRGB(246, 196, 64), Rainbow = Color3.fromRGB(226, 110, 214) }
local TIER_RANK = { Normal = 1, Golden = 2, Rainbow = 3 }

-- a catalog def, or the def of a pet copy key ("cat@Golden", "hyb:<uid>": tier finish / merged hybrid look)
local function defOf(id)
	if type(id) ~= "string" then
		return nil
	end
	local def = PetCatalog.Get(id)
	if def then
		return def
	end
	if type(State.DefOf) == "function" then
		local ok, derived = pcall(State.DefOf, id)
		if ok and type(derived) == "table" then
			return derived
		end
	end
	return nil
end

local function isHybridKey(key, def)
	if type(def) == "table" and def.IsHybrid == true then
		return true
	end
	return type(key) == "string" and key:sub(1, 4) == "hyb:"
end

local function tierOfKey(key, def)
	local t = type(def) == "table" and def.Tier or nil
	if t == "Golden" or t == "Rainbow" then
		return t
	end
	local suffix = type(key) == "string" and key:match("@(%a+)$") or nil
	if suffix == "Golden" or suffix == "Rainbow" then
		return suffix
	end
	return "Normal"
end

local function rarityRank(rarityId)
	for _, r in ipairs(Config.Rarities) do
		if r.Id == rarityId then
			return r.Order or 0
		end
	end
	return 0
end

-- the player's fused pets: hybrids first, then Rainbow and Golden copies, rarest first
local function fusionKeys()
	local keys = {}
	if type(State.Keys) == "function" then
		local ok, list = pcall(State.Keys)
		if ok and type(list) == "table" then
			keys = list
		end
	end
	local out, info = {}, {}
	for i, key in ipairs(keys) do
		if type(key) == "string" and not info[key] and (isHybridKey(key) or key:find("@", 1, true)) and State.OwnedCount(key) > 0 then
			local def = defOf(key)
			if def then
				info[key] = {
					Hybrid = isHybridKey(key, def) and 1 or 0,
					Tier = TIER_RANK[tierOfKey(key, def)] or 1,
					Rarity = rarityRank(def.Rarity),
					Index = i,
				}
				out[#out + 1] = key
			end
		end
	end
	table.sort(out, function(a, b)
		local x, y = info[a], info[b]
		if x.Hybrid ~= y.Hybrid then
			return x.Hybrid > y.Hybrid
		end
		if x.Tier ~= y.Tier then
			return x.Tier > y.Tier
		end
		if x.Rarity ~= y.Rarity then
			return x.Rarity > y.Rarity
		end
		return x.Index < y.Index
	end)
	return out
end

-- the defs of the player's fused pets (Id = the copy key) and a signature of the set (the grid is rebuilt when a
-- fusion adds or removes one while the Fusions tab is shown)
local function fusionDefs()
	local defs, ids = {}, {}
	for _, key in ipairs(fusionKeys()) do
		local def = defOf(key)
		if type(def) == "table" and type(def.Id) == "string" then
			defs[#defs + 1] = def
			ids[#ids + 1] = def.Id
		end
	end
	return defs, table.concat(ids, ",")
end

local function petLevelOf(key)
	if type(State.PetLevel) == "function" then
		local ok, level = pcall(State.PetLevel, key)
		if ok and type(level) == "number" then
			return math.max(1, math.floor(level))
		end
	end
	return 1
end

local function homeOf()
	if type(State.Home) == "function" then
		local ok, home = pcall(State.Home)
		if ok and type(home) == "table" then
			return home
		end
	end
	return { Prestige = 0, Stations = {} }
end

-- opens the Fusion Machine window (FusionController, loaded on demand: no require cycle at load time)
local function openFusionMachine()
	local module = script.Parent:FindFirstChild("FusionController")
	if not module then
		return
	end
	local ok, fusion = pcall(require, module)
	if ok and type(fusion) == "table" and type(fusion.Open) == "function" then
		IndexController.Close()
		pcall(fusion.Open, nil)
	end
end

-- true once the player owns the Fusion Machine station
local function hasFusionMachine()
	local home = homeOf()
	local stations = type(home.Stations) == "table" and home.Stations or {}
	return (tonumber(stations.FusionMachine) or 0) >= 1
end

-- the Home window (MenuController, required at click time: both modules are loaded by then, so no cycle)
local function openHomeWindow()
	local module = script.Parent:FindFirstChild("MenuController")
	if not module then
		return
	end
	local ok, menu = pcall(require, module)
	if ok and type(menu) == "table" and type(menu.Open) == "function" then
		IndexController.Close()
		pcall(menu.Open, "Home", {})
	end
end

----------------------------------------------------------------------
-- Visual helpers
----------------------------------------------------------------------
-- CloudUI.Pill with a text size that stays >= 14 px at the phone scale (0.8).
-- (kit-b U8) the kit B tag (was CloudUI.Pill's neon pill); 18 px
local function readablePill(text, kind, parent)
	return signPill(text, typeof(kind) == "Color3" and kind or SIGN.Stone, parent)
end

-- Small element chip with the element's drawn icon and its name (kit-b U8: CloudUI.ElementChip, the Pets cards' chip
-- with the name after the icon; was a rounded glossy pill).
local function elementPill(parent, element, textSize, layoutOrder)
	local chip = CloudUI.ElementChip(parent, element, (textSize or 17) + 9, {
		Label = element,
		TextSize = textSize or 17,
		Role = "Heading", -- (mixed case: "Celestial" fits a narrow tile at 18 px)
		Name = "Element_" .. element,
		LayoutOrder = layoutOrder or 0,
		ZIndex = 4,
	})
	if not chip then
		chip = signPill(element, elementColor(element), parent)
		chip.Name = "Element_" .. element
		chip.LayoutOrder = layoutOrder or 0
	end
	return chip
end

-- Confetti squares flying out of `centre` (a UDim2 inside `parent`).
local function burst(parent, color, amount, centre)
	local rng = Random.new()
	for i = 1, amount do
		local size = rng:NextInteger(8, 14)
		local pieceColor = color
		if i % 3 == 0 then
			pieceColor = GOLD
		elseif i % 3 == 1 then
			pieceColor = Theme.Lighten(color, 0.5)
		end
		local piece = makeFrame(parent, "Confetti", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = centre,
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 0,
			BackgroundColor3 = pieceColor,
			Rotation = rng:NextInteger(0, 90),
			ZIndex = 12,
		})
		corner(piece, "S")
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(60, 170)
		local target = UDim2.new(
			centre.X.Scale,
			centre.X.Offset + math.cos(angle) * distance,
			centre.Y.Scale,
			centre.Y.Offset + math.sin(angle) * distance * 0.7 - 20
		)
		local seconds = rng:NextNumber(0.6, 1.1)
		tween(piece, seconds, { Position = target, Rotation = piece.Rotation + rng:NextInteger(-200, 200) })
		tween(piece, seconds, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, seconds + 0.1)
	end
end

----------------------------------------------------------------------
-- Layout (readability rule + fit, keeps clear of the menu column)
----------------------------------------------------------------------
local function guiSize()
	local size = U.Gui and U.Gui.AbsoluteSize or Vector2.new(1280, 720)
	if size.X < 2 or size.Y < 2 then
		return Vector2.new(1280, 720)
	end
	return size
end

local function viewportHeight()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize
	if vp and vp.Y > 2 then
		return vp.Y
	end
	return guiSize().Y
end

local function renderFooter()
	local total = totalPets()
	local unlocked = unlockedCount()
	if U.FooterText then
		U.FooterText.Text = string.format("Unlocked: %d/%d", unlocked, total)
		U.FooterFill.Size = UDim2.new(total > 0 and unlocked / total or 0, 0, 1, 0)
		U.FooterPercent.Text = string.format("%d%%", total > 0 and math.floor(unlocked / total * 100) or 0)
	end
	-- the compact layout has no footer: the title carries the count
	if U.Panel then
		if S.Short then
			if S.Tall then
				U.Panel.SetTitle(string.format("Pet Index %d/%d", unlocked, total))
			else
				U.Panel.SetTitle(string.format("Pet Index   Unlocked: %d/%d", unlocked, total))
			end
		else
			U.Panel.SetTitle("Pet Index")
		end
	end
end

-- Phase 5 (6.6): the window rule. NeonKit.Dock keeps the holder docked right (landscape) / a bottom sheet (portrait)
-- and returns its design size.
local function fitWindow()
	if not U.Dock then
		U.Dock = U.Kit.Dock(U.Holder, U.Fit, K.PREF_W, K.PREF_H)
	end
	U.Dock.Refresh()
	local r = U.Dock.Rect
	return math.floor(r.designW + 0.5), math.floor(r.designH + 0.5)
end

local function relayout()
	if not S.Built then
		return
	end
	local w, h = fitWindow()

	-- narrow windows get narrower side columns, short ones the compact layout, tall ones (portrait phones) stack
	-- the group strip, the grid and the detail card
	local tall = w < K.TALL
	local narrow = w < K.NARROW
	local short = h < K.SHORT -- (Phase 5: a landscape-phone sheet is tall AND short: compact header, rewards, no footer)
	S.Narrow, S.Short, S.Tall = narrow, short, tall
	local groupW = narrow and K.GROUP_W_NARROW or K.GROUP_W
	local detailW = narrow and K.DETAIL_W_NARROW or K.DETAIL_W
	local headerH = short and K.HEADER_H_SHORT or K.HEADER_H
	local rewardH = short and K.REWARD_H_SHORT or K.REWARD_H
	local footerH = short and 0 or K.FOOTER_H
	U.Main.Size = UDim2.new(1, -20, 1, -(20 + footerH))
	U.Footer.Visible = not short
	if tall then
		-- top: a sideways strip of group tiles (+ Elements); then the centre (header, grid, rewards); the detail
		-- card fills the bottom
		local strip = K.STRIP_H
		U.Groups.Size = UDim2.new(1, 0, 0, strip)
		U.GroupLayout.FillDirection = Enum.FillDirection.Horizontal
		U.GroupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		U.GroupLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		U.GroupList.ScrollingDirection = Enum.ScrollingDirection.X
		U.GroupList.AutomaticCanvasSize = Enum.AutomaticSize.X
		U.GroupList.Size = UDim2.new(1, U.ElementsButton and -(K.ELEMENTS_STRIP_W + 8) or 0, 1, 0)
		U.GroupPad.PaddingTop = UDim.new(0, 0)
		U.GroupPad.PaddingBottom = UDim.new(0, 12)
		U.GroupPad.PaddingLeft = UDim.new(0, K.STRIP_PAD_L)
		U.GroupPad.PaddingRight = UDim.new(0, 0)
		local centreTop = strip + 8
		-- Phase 5: a docked sheet is shorter; the grid gets 2/3 of it, and a landscape-phone window (< 600 design px
		-- tall) shows the grid only (the tiles carry name, rarity and element)
		local frac = (h < 600) and 0 or 0.34
		U.Detail.Visible = frac > 0
		U.Centre.Position = UDim2.new(0, 0, 0, centreTop)
		U.Centre.Size = UDim2.new(1, 0, 1 - frac, -centreTop)
		U.Detail.AnchorPoint = Vector2.new(0, 1)
		U.Detail.Position = UDim2.new(0, 0, 1, 0)
		U.Detail.Size = UDim2.new(1, 0, frac, -8)
	else
		U.Groups.Size = UDim2.new(0, groupW, 1, 0)
		U.GroupLayout.FillDirection = Enum.FillDirection.Vertical
		U.GroupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		U.GroupLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		U.GroupList.ScrollingDirection = Enum.ScrollingDirection.Y
		U.GroupList.AutomaticCanvasSize = Enum.AutomaticSize.Y
		U.GroupPad.PaddingTop = UDim.new(0, 6)
		U.GroupPad.PaddingBottom = UDim.new(0, 6)
		U.GroupPad.PaddingLeft = UDim.new(0, 4)
		U.GroupPad.PaddingRight = UDim.new(0, 10)
		U.Detail.Visible = true
		U.Detail.AnchorPoint = Vector2.new(1, 0)
		U.Detail.Position = UDim2.new(1, 0, 0, 0)
		U.Detail.Size = UDim2.new(0, detailW, 1, 0)
		U.Centre.Position = UDim2.new(0, groupW + K.GAP, 0, 0)
		U.Centre.Size = UDim2.new(1, -(groupW + detailW + 2 * K.GAP), 1, 0)
	end
	U.Header.Size = UDim2.new(1, 0, 0, headerH)
	U.GridWell.Position = UDim2.fromOffset(0, headerH + 8)
	U.GridWell.Size = UDim2.new(1, 0, 1, -(headerH + 8 + rewardH + 8))
	U.Rewards.Size = UDim2.new(1, 0, 0, rewardH)
	U.RewardSub.Visible = not short
	U.RewardLabel.Visible = not (short and narrow)
	-- (a landscape phone's grid well only has room for the empty Fusions card's title: no sparkle, no explanation)
	for _, part in ipairs({ "Glyph", "Body" }) do
		local child = U.FusionEmpty and U.FusionEmpty:FindFirstChild(part)
		if child then
			child.Visible = not short
		end
	end
	if short then
		U.RewardLabel.AnchorPoint = Vector2.new(0, 0.5)
		U.RewardLabel.Position = UDim2.new(0, 14, 0.5, 0)
		U.RewardAmount.AnchorPoint = Vector2.new(0, 0.5)
		U.RewardAmount.Position = UDim2.new(0, narrow and 14 or 128, 0.5, 0)
		U.RewardAmount.Size = UDim2.new(1, -(narrow and 180 or 294), 0, 34)
		U.ClaimButton.Size = UDim2.fromOffset(150, 52)
	else
		-- the reward box follows the centre's own width (a docked 1920x1080 window has a narrow centre between the
		-- group column and the detail card, like a portrait phone): a narrow centre gets the smaller CLAIM button,
		-- and when "Rewards:" and the amount do not both fit left of it the amount takes the label's place
		-- (Main is the window less the panel's content inset and its own 20 px)
		local mainW = w - K.PANEL_INSET_W - 20
		local centreW = tall and mainW or (mainW - groupW - detailW - 2 * K.GAP)
		local small = tall or centreW < K.REWARD_ROOMY_W
		local buttonW, buttonH = small and 150 or 184, small and 52 or 60
		local textW = math.max(0, centreW - 16 - (buttonW + 14 + 10)) -- the room left of the button
		local withLabel = textW >= K.REWARD_LABEL_W + K.REWARD_AMOUNT_W
		U.RewardLabel.Visible = withLabel
		S.RewardLabelOk = withLabel
		U.RewardLabel.AnchorPoint = Vector2.new(0, 0)
		U.RewardLabel.Position = UDim2.fromOffset(16, 8)
		U.RewardAmount.AnchorPoint = Vector2.new(0, 0)
		U.RewardAmount.Position = UDim2.fromOffset(withLabel and (16 + K.REWARD_LABEL_W) or 16, 6)
		U.RewardAmount.Size = UDim2.new(0, math.max(0, withLabel and (textW - K.REWARD_LABEL_W) or textW), 0, 32)
		U.ClaimButton.Size = UDim2.fromOffset(buttonW, buttonH)
		S.RewardTextW = textW
	end
	if short then
		S.RewardLabelOk = not narrow
		S.RewardTextW = nil
	end
	if U.ElementsCard then
		U.ElementsCard.Size = UDim2.new(1, 0, 1, -(rewardH + 8))
	end
	U.View.Size = UDim2.new(1, 0, 0, (short or tall) and K.VIEW_H_SHORT or K.VIEW_H)
	local tileH = short and K.GROUP_TILE_H_SHORT or K.GROUP_TILE_H
	-- (kit-b U8) the strip shows a whole number of tabs: as many as fit at STRIP_TILE_MIN_W share the strip's width, so
	-- the strip's edge (and the Elements button beside it) never cuts one at rest (the owner's phone render: "UNCOMMON"
	-- half under the Elements button)
	local stripTabW = K.STRIP_TILE_W
	if tall then
		local viewW = (w - K.PANEL_INSET_W - 20) - (U.ElementsButton and (K.ELEMENTS_STRIP_W + 8) or 0)
		local room = viewW - K.STRIP_PAD_L
		local n = math.max(1, math.floor((room + K.STRIP_GAP) / (K.STRIP_TILE_MIN_W + K.STRIP_GAP)))
		stripTabW = math.floor((room - (n - 1) * K.STRIP_GAP) / n)
	end
	local tileSize = tall and UDim2.new(0, stripTabW, 1, 0) or UDim2.new(1, -10, 0, tileH)
	-- the names sit at a fixed size (never TextScaled: it shrank "Uncommon" in the strip): 20 px in the strip, 24 px in
	-- the column, stepped down to NAME_MIN for a name that does not fit its row (U8 review: "Uncommon" and "Legendary" ran
	-- past the narrow column's box, and into the count in the strip). The row is one name tall from the top, so the
	-- count on the bar row below never meets it
	local tabW = tall and stripTabW or (groupW - U.GroupPad.PaddingLeft.Offset - U.GroupPad.PaddingRight.Offset - 10)
	local nameMax = tall and 20 or 24
	local nameRoom = tabW - K.TAB_NAME_X - K.TAB_BADGE_W
	local nameSize = UDim2.new(0, nameRoom, 0, nameMax + 4)
	local function placeName(label)
		local pad = label:FindFirstChildOfClass("UIPadding") -- (the Fusions sparkle's inset)
		local inset = pad and (pad.PaddingLeft.Offset + pad.PaddingRight.Offset) or 0
		local size = nameMax
		while size > K.NAME_MIN do
			local w = K.MEASURE and K.MEASURE(label.Text, size, label.Font) or Theme.MeasureLabel(label, label.Text, size).X
			if inset + w + K.NAME_SPARE <= nameRoom then
				break
			end
			size = size - 1
		end
		label.Size = nameSize
		label.TextSize = size
	end
	for _, tile in pairs(S.GroupTiles) do
		tile.Button.Size = tileSize
		placeName(tile.Name)
	end
	if S.FusionTile then
		S.FusionTile.Button.Size = tileSize
		placeName(S.FusionTile.Name)
	end
	if U.ElementsButton then
		if tall then
			U.ElementsButton.AnchorPoint = Vector2.new(1, 0)
			U.ElementsButton.Position = UDim2.new(1, 0, 0, 0)
			U.ElementsButton.Size = UDim2.new(0, K.ELEMENTS_STRIP_W, 1, -12)
		else
			local buttonH = short and K.ELEMENTS_BTN_H_SHORT or K.ELEMENTS_BTN_H
			U.ElementsButton.AnchorPoint = Vector2.new(0.5, 1)
			U.ElementsButton.Position = UDim2.new(0.5, 0, 1, 0)
			U.ElementsButton.Size = UDim2.new(1, -10, 0, buttonH)
			U.GroupList.Size = UDim2.new(1, 0, 1, -(buttonH + 8))
		end
	end
	local petW = narrow and K.TILE_W_NARROW or K.TILE_W
	local petH = narrow and K.TILE_H_NARROW or K.TILE_H
	if short then
		petH = math.min(petH, K.TILE_H_SHORT)
	end
	U.GridLayout.CellSize = UDim2.fromOffset(petW, petH)
	renderFooter()
end

----------------------------------------------------------------------
-- Back button (gamepad B) while the window is open
----------------------------------------------------------------------
local function onBackAction(_name, inputState)
	if inputState == Enum.UserInputState.Begin and S.Open then
		IndexController.Close()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function syncBackBinding()
	if S.Open == S.BackBound then
		return
	end
	S.BackBound = S.Open
	if S.Open then
		local ok, err = pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, onBackAction, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		end)
		if not ok then
			warnOnce("bind back", err)
		end
	else
		task.defer(function()
			if not S.BackBound then
				pcall(function()
					ContextActionService:UnbindAction(K.BACK_ACTION)
				end)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Group list (left)
----------------------------------------------------------------------
local refreshAll, selectGroup, selectPet, renderDetail, showElements, revealGroupTile, H_paintTab, syncTouch

local function buildGroupTile(group, index)
	local color = rarityColor(group.Rarity)
	local accent = rarityAccent(group.Rarity)
	local tile = { Group = group, Lip = color }
	local button = Util.Create("TextButton", {
		Name = "Group_" .. group.Id,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Size = UDim2.new(1, -10, 0, K.GROUP_TILE_H),
		LayoutOrder = index,
		Parent = U.GroupList,
	})
	-- (kit-b U8) a signboard tab: a stone tab, the rarity on its lip (refreshGroupTiles gold-faces the selected one)
	CloudUI.SignBlock(button, "Stone", { Face = SIGN.Tile, LipColor = color, Pad = false })
	button:SetAttribute("Rarity", group.Rarity)
	-- name on top, then a slim progress bar with the "3/6" count at its right end (kit-b U6: a card name is a Heading, the
	-- Title face's capitals would not fit "LEGENDARY" in the narrow phone tile); U8: brown on the stone at a fixed size
	-- (relayout: 24 px in the column, 20 in the strip, smaller when a name needs it; its row stops at the badge corner)
	tile.Name = makeText(button, "GroupName", group.Rarity, "Heading", 24, INK, {
		Position = UDim2.fromOffset(K.TAB_NAME_X, 2),
		Size = UDim2.new(1, -(K.TAB_NAME_X + K.TAB_BADGE_W), 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	tile.Progress = makeText(button, "Progress", "0/0", "Heading", 19, MUTED, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -7),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
	})
	local track = makeFrame(button, "Track", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -13),
		Size = UDim2.new(1, -80, 0, 10),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Well,
		ZIndex = 2,
	})
	edge(track, SIGN.WellEdge, 2)
	tile.Fill = makeFrame(track, "Fill", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = accent,
		ZIndex = 3,
	})
	-- top-right corner: a check when claimed, a red "!" when the reward waits
	tile.Badge = makeFrame(button, "Badge", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Red,
		Visible = false,
		ZIndex = 4,
	})
	edge(tile.Badge, SIGN.Wood, 2)
	tile.BadgeText = makeText(tile.Badge, "Mark", "!", "Button", 19, INK, {
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 5,
	})
	tile.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = button })
	button.MouseEnter:Connect(function()
		tween(tile.Pop, 0.12, { Scale = 1.03 })
	end)
	button.MouseLeave:Connect(function()
		tween(tile.Pop, 0.12, { Scale = 1 })
	end)
	button.Activated:Connect(function()
		safe("select group", selectGroup, group.Id)
	end)
	tile.Button = button
	S.GroupTiles[group.Id] = tile
	return tile
end

-- The "Fusions" tile under the rarity groups (not a reward group): the player's hybrids and Golden / Rainbow copies.
local function buildFusionTile(index)
	local tile = { Lip = FUSION_COLOR }
	local button = Util.Create("TextButton", {
		Name = "Group_" .. FUSIONS,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		Size = UDim2.new(1, -10, 0, K.GROUP_TILE_H),
		LayoutOrder = index,
		Parent = U.GroupList,
	})
	-- (kit-b U8) the same signboard tab, the fusion violet on its lip and the sparkle before the name
	CloudUI.SignBlock(button, "Stone", { Face = SIGN.Tile, LipColor = FUSION_COLOR, Pad = false })
	tile.Name = makeText(button, "GroupName", "Fusions", "Heading", 24, INK, { -- (a card name, like the rarity tiles)
		Position = UDim2.fromOffset(K.TAB_NAME_X, 2),
		Size = UDim2.new(1, -(K.TAB_NAME_X + K.TAB_BADGE_W), 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	PixelIcon.Lead(tile.Name, ICON.Sparkle)
	tile.Progress = makeText(button, "Progress", "", "Heading", 19, MUTED, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -7),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	tile.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = button })
	button.MouseEnter:Connect(function()
		tween(tile.Pop, 0.12, { Scale = 1.03 })
	end)
	button.MouseLeave:Connect(function()
		tween(tile.Pop, 0.12, { Scale = 1 })
	end)
	button.Activated:Connect(function()
		safe("select group", selectGroup, FUSIONS)
	end)
	tile.Button = button
	S.FusionTile = tile
	return tile
end

-- (kit-b U8) a tab's look: stone, or gold-faced with the ink edge when it is the shown group; the lip keeps its rarity
function H_paintTab(tile, selected)
	CloudUI.SignBlock(tile.Button, "Stone", {
		Face = selected and SIGN.Selected or SIGN.Tile,
		Edge = selected and INK or nil,
		LipColor = tile.Lip,
		Pad = false,
	})
	tile.Button:SetAttribute("Selected", selected)
end

local function refreshGroupTiles()
	for _, group in ipairs(S.Groups) do
		local tile = S.GroupTiles[group.Id]
		if tile then
			local found, total, complete, claimed, claimable = groupStatus(group)
			tile.Progress.Text = string.format("%d/%d", found, total)
			tile.Fill.Size = UDim2.new(total > 0 and found / total or 0, 0, 1, 0)
			local selected = S.GroupId == group.Id
			H_paintTab(tile, selected)
			if claimable then
				tile.Badge.Visible = true
				tile.Badge.BackgroundColor3 = SIGN.Red
				PixelIcon.Set(tile.BadgeText, nil)
				tile.BadgeText.Text = "!"
			elseif claimed then
				tile.Badge.Visible = true
				tile.Badge.BackgroundColor3 = SIGN.Grass
				tile.BadgeText.Text = ""
				PixelIcon.Set(tile.BadgeText, ICON.Check) -- (kit-b U7b)
			else
				tile.Badge.Visible = false
			end
			tile.Progress.TextColor3 = complete and INK or MUTED
		end
	end
	local fusionTile = S.FusionTile
	if fusionTile then
		local n = #fusionKeys()
		fusionTile.Progress.Text = n == 1 and "1 fused pet" or (n .. " fused pets")
		H_paintTab(fusionTile, S.GroupId == FUSIONS)
	end
end

----------------------------------------------------------------------
-- Pet grid (centre)
----------------------------------------------------------------------
local function destroyTileViewport(tile)
	if tile.Viewport then
		pcall(tile.Viewport.Destroy)
		tile.Viewport = nil
	end
end

local function paintTile(tile)
	local def = tile.Def
	local discovered = State.IsDiscovered(def.Id)
	local selected = S.PetId == def.Id
	-- (kit-b U8) the Pets window's card: stone, the selected one gold-faced with the ink edge, the rarity on the lip
	CloudUI.SignBlock(tile.Button, "Stone", {
		Face = selected and SIGN.Selected or SIGN.Tile,
		Edge = selected and INK or nil,
		LipColor = rarityColor(def.Rarity),
		LipPx = K.TILE_LIP,
		Pad = false,
	})
	tile.Button:SetAttribute("Rarity", def.Rarity)
	if discovered then
		-- fused copies show the pet's own name: the chip carries the tier ("Golden Pebble Pup" needs three lines)
		if tile.FusionChip and not isHybridKey(def.Id, def) then
			tile.Caption.Text = def.Name or def.DisplayName
		else
			tile.Caption.Text = def.DisplayName or def.Name
		end
		tile.Caption.TextColor3 = INK
	else
		tile.Caption.Text = "???"
		tile.Caption.TextColor3 = MUTED
	end
	if tile.Viewport then
		local frame = tile.Viewport.Frame
		if frame then
			frame.ImageColor3 = discovered and Color3.new(1, 1, 1) or SILHOUETTE
		end
		local best = discovered and type(State.BestStage) == "function" and (tonumber(State.BestStage(def.Id)) or 0) or 0
		if tile.BuiltDiscovered ~= discovered or (tile.BuiltStage ~= nil and tile.BuiltStage ~= best) then
			-- the pet was just discovered (or evolved): rebuild with the new settings
			destroyTileViewport(tile)
		elseif discovered then
			tile.Viewport.SetAnimated(selected or tile.Hover)
		end
	end
	-- element badge, only once discovered (the tile has room for one; the detail card lists them all)
	local elements = discovered and elementsOf(def) or {}
	if #elements > 1 then
		elements = { elements[1] }
	end
	local key = table.concat(elements, ",")
	if tile.ElementKey ~= key then
		tile.ElementKey = key
		for _, child in ipairs(tile.Elements:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, element in ipairs(elements) do
			elementPill(tile.Elements, element, 18, i)
		end
	end
	-- fused pets: a tier / hybrid chip (top-right) and the copy's level
	if tile.FusionChip then
		local tier = tierOfKey(def.Id, def)
		local hybrid = isHybridKey(def.Id, def)
		tile.FusionChip.Visible = hybrid or tier ~= "Normal"
		tile.FusionChip.BackgroundColor3 = hybrid and FUSION_COLOR or (TIER_COLORS[tier] or GOLD)
		tile.FusionText.Text = hybrid and "H" or (tier == "Rainbow" and "R" or "G")
		tile.FusionText.TextColor3 = Theme.TextOn(tile.FusionChip.BackgroundColor3)
		local level = petLevelOf(def.Id)
		tile.LevelTag.Text = "Lv " .. level
		tile.LevelTag.Visible = level > 1
	end
end

local function buildTileViewport(tile)
	local def = tile.Def
	local discovered = State.IsDiscovered(def.Id)
	-- Phase 5 (3.7): the best stage over the owned copies of this pet (undiscovered: 0); evolved = Low
	local stage = discovered and type(State.BestStage) == "function" and (tonumber(State.BestStage(def.Id)) or 0) or 0
	local handle = CloudUI.PetViewport(tile.Art, def, UDim2.new(1, 0, 1, 0), {
		Animate = false,
		Spin = discovered and "sway" or "none",
		Evolved = stage >= 1 and stage or nil,
		Detail = stage >= 1 and "Low" or nil,
		ZIndex = 3,
	})
	tile.BuiltStage = stage
	if not handle then
		return
	end
	if handle.Frame then
		handle.Frame.ImageColor3 = discovered and Color3.new(1, 1, 1) or SILHOUETTE
	end
	tile.Viewport = handle
	tile.BuiltDiscovered = discovered
	if discovered and (S.PetId == def.Id or tile.Hover) then
		handle.SetAnimated(true)
	end
end

-- Attaches the missing viewports while the window is open, under the per-frame time budget (K.TILE_BUDGET).
local function fillViewports()
	if S.Filling then
		return
	end
	S.Filling = true
	task.spawn(function()
		task.wait() -- the frame that opens the window already builds it (and the detail card's pet)
		while S.Open do
			local built, start, more = 0, os.clock(), false
			for _, id in ipairs(S.TileOrder) do
				local tile = S.Tiles[id]
				if tile and not tile.Viewport and tile.Button.Parent and (built >= K.TILES_MAX or (built > 0 and os.clock() - start >= K.TILE_BUDGET)) then
					more = true
					break
				end
				if tile and not tile.Viewport and tile.Button.Parent then
					local ok, err = pcall(buildTileViewport, tile)
					if not ok or not tile.Viewport then
						-- never retry a broken build every frame: park a no-op handle
						if not ok then
							warnOnce("tile viewport", err)
						end
						tile.Viewport = { Destroy = function() end, SetAnimated = function() end }
						tile.BuiltDiscovered = State.IsDiscovered(id)
					end
					built = built + 1
				end
			end
			if not more then
				break
			end
			task.wait()
		end
		S.Filling = false
	end)
end

local function clearTiles()
	for _, tile in pairs(S.Tiles) do
		destroyTileViewport(tile)
		tile.Button:Destroy()
	end
	S.Tiles = {}
	S.TileOrder = {}
end

local function buildTile(def, index)
	local tile = { Def = def, Hover = false }
	local button = Util.Create("TextButton", {
		Name = "IndexPet_" .. def.Id,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		LayoutOrder = index,
		Parent = U.Grid,
	})
	tile.Button = button
	-- (kit-b U8) the pet stands in its light well (paintTile paints the card and its rarity lip)
	tile.Art = makeFrame(button, "Art", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(1, -8, 1, -52),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.PetWell,
		ZIndex = 2,
	})
	local band = makeFrame(button, "NameBand", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(K.TILE_LIP + 1)),
		Size = UDim2.new(1, -10, 0, 40),
		ZIndex = 3,
	})
	-- 18 design px on up to two lines: never under 14 px at the phone scale (readability rule)
	tile.Caption = makeText(band, "Caption", "???", "Heading", 18, INK, {
		Position = UDim2.fromOffset(3, 0),
		Size = UDim2.new(1, -6, 1, 0),
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LineHeight = 0.92,
		ZIndex = 4,
	})
	tile.Elements = makeFrame(button, "Elements", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 26),
		ZIndex = 4,
	})
	listLayout(tile.Elements, Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	if S.GroupId == FUSIONS then
		local chip = makeFrame(button, "FusionBadge", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -7, 0, 7),
			Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 0,
			BackgroundColor3 = FUSION_COLOR,
			ZIndex = 5,
		})
		edge(chip, SIGN.Wood, 2)
		tile.FusionChip = chip
		tile.FusionText = makeText(chip, "Mark", "", "Button", 18, INK, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 6 })
		tile.LevelTag = makeText(button, "LevelTag", "", "Heading", 18, INK, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -8, 1, -48),
			Size = UDim2.fromOffset(70, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
			Visible = false,
			ZIndex = 5,
		})
	end
	tile.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = button })
	button.MouseEnter:Connect(function()
		tile.Hover = true
		tween(tile.Pop, 0.12, { Scale = 1.03 })
		if tile.Viewport and tile.BuiltDiscovered then
			tile.Viewport.SetAnimated(true)
		end
	end)
	button.MouseLeave:Connect(function()
		tile.Hover = false
		tween(tile.Pop, 0.12, { Scale = 1 })
		if tile.Viewport and tile.BuiltDiscovered then
			tile.Viewport.SetAnimated(S.PetId == def.Id)
		end
	end)
	button.Activated:Connect(function()
		safe("select pet", selectPet, def.Id)
	end)
	S.Tiles[def.Id] = tile
	table.insert(S.TileOrder, def.Id)
	paintTile(tile)
	return tile
end

local function refreshTiles()
	for _, tile in pairs(S.Tiles) do
		paintTile(tile)
	end
	fillViewports()
end

local function renderHeader()
	if S.GroupId == FUSIONS then
		local n = #S.TileOrder
		U.GroupTitle.Text = "Fusions"
		PixelIcon.Mark(U.GroupTitle, ICON.Sparkle) -- (kit-b U7b)
		U.GroupTitle.TextColor3 = INK
		U.HeaderFill.Size = UDim2.new(n > 0 and 1 or 0, 0, 1, 0)
		U.HeaderFill.BackgroundColor3 = FUSION_COLOR
		U.HeaderCount.Text = n == 1 and "1 fused pet" or (n .. " fused pets")
		return
	end
	local group = S.GroupById[S.GroupId]
	if not group then
		return
	end
	local found, total, complete = groupStatus(group)
	local accent = rarityAccent(group.Rarity)
	U.GroupTitle.Text = group.Rarity .. " Pets"
	PixelIcon.Mark(U.GroupTitle, nil)
	U.GroupTitle.TextColor3 = INK
	U.HeaderFill.Size = UDim2.new(total > 0 and found / total or 0, 0, 1, 0)
	U.HeaderFill.BackgroundColor3 = complete and SIGN.Grass or accent
	U.HeaderCount.Text = string.format("%d/%d", found, total)
end

local function renderRewards()
	if S.GroupId == FUSIONS then
		-- fusions are not a reward group: how to fuse, and the way to the Fusion Machine (or to the Home window
		-- that builds it / shows the prestige progress)
		local home = homeOf()
		local machine = hasFusionMachine()
		local stars = tonumber(home.Prestige) or 0
		U.RewardLabel.Visible = false
		U.RewardAmount.Visible = false
		U.RewardSub.Visible = true
		local compact = S.Short or S.Tall
		U.RewardSub.Position = UDim2.fromOffset(16, compact and 4 or 8)
		U.RewardSub.Size = UDim2.new(1, -(compact and 182 or 230), 1, compact and -8 or -16)
		if S.RewardTextW and not S.Short then
			-- (the same room as the reward line: left of the button)
			U.RewardSub.Size = UDim2.new(0, S.RewardTextW, 1, compact and -8 or -16)
		end
		if machine then
			U.RewardSub.Text = "Fuse 3 copies into Golden (x1.5), 3 Golden into Rainbow (x2.5), or mix two pets into a hybrid!"
		elseif stars >= 1 then
			U.RewardSub.Text = "Build the Fusion Machine at home for Golden, Rainbow and hybrid pets!"
		else
			U.RewardSub.Text = "Reach Prestige 1 at home to unlock the Fusion Machine!"
		end
		U.RewardSub.TextColor3 = MUTED
		local button = U.ClaimButton
		button.Text = machine and "Fuse pets" or "My Home"
		CloudUI.SetStyle(button, "Green") -- (kit-b U8) the tab's one main action
		CloudUI.SetDisabled(button, false)
		return
	end
	local group = S.GroupById[S.GroupId]
	if not group then
		return
	end
	-- back from the Fusions tab: the reward box's own layout
	U.RewardAmount.Visible = true
	U.RewardLabel.Visible = S.RewardLabelOk ~= false
	-- (the line under the amount, two lines at most, only when it is wide enough to read)
	local subW = S.RewardTextW
	U.RewardSub.Visible = not S.Short and subW ~= nil and subW >= K.REWARD_SUB_MIN_W
	U.RewardSub.Position = UDim2.fromOffset(16, 44)
	U.RewardSub.Size = UDim2.new(0, subW or 0, 0, 44)
	local found, total, complete, claimed, claimable = groupStatus(group)
	U.RewardAmount.Text = commas(rewardTokens(group))
	local button = U.ClaimButton
	local pending = S.ClaimPending == group.Id and not claimed
	if claimed then
		U.RewardSub.Text = "Reward claimed. Great collecting!"
		button.Text = "Claimed"
		CloudUI.SetStyle(button, "Gray")
		CloudUI.SetDisabled(button, true)
	elseif pending then
		U.RewardSub.Text = "Claiming your reward..."
		button.Text = "..."
		CloudUI.SetStyle(button, "Green")
		CloudUI.SetDisabled(button, true)
	elseif claimable then
		U.RewardSub.Text = "Every " .. group.Rarity .. " pet found. Claim it!"
		button.Text = "Claim"
		CloudUI.SetStyle(button, "Green")
		CloudUI.SetDisabled(button, false)
	else
		U.RewardSub.Text = string.format("Discover all %d %s pets (%d to go).", total, group.Rarity, total - found)
		button.Text = "Claim"
		CloudUI.SetStyle(button, "Gray")
		CloudUI.SetDisabled(button, true)
	end
	U.RewardSub.TextColor3 = claimable and INK or MUTED
	-- (kit-b U8) no glow pulses behind the button any more: a waiting reward is the green CLAIM block and the tab's red "!"
end

----------------------------------------------------------------------
-- Detail card (right)
----------------------------------------------------------------------
local function clearDetailPills()
	for _, pill in ipairs(S.DetailPills) do
		if pill.Parent then
			pill:Destroy()
		end
	end
	S.DetailPills = {}
end

function renderDetail()
	local def = S.PetId and defOf(S.PetId) or nil
	if not def then
		U.DetailBody.Visible = false
		U.DetailEmpty.Visible = true
		if S.DetailViewport then
			pcall(S.DetailViewport.Destroy)
			S.DetailViewport = nil
			S.DetailKey = nil
		end
		return
	end
	U.DetailBody.Visible = true
	U.DetailEmpty.Visible = false
	local discovered = State.IsDiscovered(def.Id)

	-- viewport: spinning when discovered, a still black silhouette otherwise
	local best = discovered and type(State.BestStage) == "function" and (tonumber(State.BestStage(def.Id)) or 0) or 0
	local key = def.Id .. "|" .. tostring(discovered) .. "|" .. best
	if S.DetailKey ~= key then
		if S.DetailViewport then
			pcall(S.DetailViewport.Destroy)
			S.DetailViewport = nil
		end
		local ok, handle = pcall(CloudUI.PetViewport, U.ViewHolder, def, UDim2.new(1, 0, 1, 0), {
			Animate = discovered,
			Spin = discovered and "spin" or "none",
			Evolved = best >= 1 and best or nil, -- Phase 5 (3.7): your best copy's look
			Detail = best >= 1 and "Low" or nil,
			ZIndex = 4,
		})
		if ok and handle then
			S.DetailViewport = handle
			if handle.Frame then
				handle.Frame.ImageColor3 = discovered and Color3.new(1, 1, 1) or SILHOUETTE
			end
		else
			warnOnce("detail viewport", handle)
		end
		S.DetailKey = key
	end
	U.Mystery.Visible = not discovered

	-- Stormfang (the player's own creature) shows its 2D art once discovered
	local art = Config.Art and Config.Art.StormfangImage
	U.Banner.Visible = discovered and def.Id == "stormfang" and type(art) == "string" and art ~= ""
	if U.Banner.Visible then
		U.Banner.Image = art
	end

	U.Name.Text = discovered and (def.DisplayName or def.Name) or "???"
	local tier = tierOfKey(def.Id, def)
	local hybrid = isHybridKey(def.Id, def)
	local fused = hybrid or tier ~= "Normal"
	U.Name.TextColor3 = discovered and INK or MUTED

	-- meta: rarity, element and role pills (rebuilt only when they change)
	local elements = discovered and elementsOf(def) or {}
	local role = discovered and def.Role or nil
	local pillKey = tostring(def.Rarity) .. "|" .. table.concat(elements, ",") .. "|" .. tostring(role) .. "|" .. tier .. "|" .. tostring(hybrid)
	if S.PillKey ~= pillKey then
		S.PillKey = pillKey
		clearDetailPills()
		local rarityPill = readablePill(def.Rarity, rarityColor(def.Rarity), U.Meta)
		rarityPill.LayoutOrder = 1
		table.insert(S.DetailPills, rarityPill)
		if tier ~= "Normal" then
			local tierPill = readablePill(tier, TIER_COLORS[tier] or GOLD, U.Meta)
			tierPill.LayoutOrder = 2
			table.insert(S.DetailPills, tierPill)
		end
		if hybrid then
			local hybridPill = readablePill("Hybrid", FUSION_COLOR, U.Meta)
			hybridPill.LayoutOrder = 3
			table.insert(S.DetailPills, hybridPill)
		end
		for i, element in ipairs(elements) do
			table.insert(S.DetailPills, elementPill(U.Meta, element, 18, 1 + i))
		end
		if role then
			local rolePill = readablePill(role, ROLE_COLORS[role] or SIGN.Sky, U.Meta)
			rolePill.LayoutOrder = 50
			table.insert(S.DetailPills, rolePill)
		end
	end
	U.RoleBlurb.Visible = role ~= nil
	if role then
		local blurbs = PetCatalog.RoleBlurbs or {}
		U.RoleBlurb.Text = blurbs[role] or ""
	end

	-- stats: real numbers once discovered, locked "?" rows before
	local stats = nil
	if discovered and fused and type(PetCatalog.StatsOf) == "function" then
		-- a fused copy: its stats at its own level x its tier (a hybrid's merged stats)
		local level = petLevelOf(def.Id)
		local ok, result = pcall(PetCatalog.StatsOf, def, level)
		if ok and type(result) == "table" then
			stats = withBattleStats(result, def, level)
		end
	elseif discovered and type(PetCatalog.GetStats) == "function" then
		local ok, result = pcall(PetCatalog.GetStats, def.Id, 1)
		if ok and type(result) == "table" then
			stats = withBattleStats(result, def.Id, 1)
		end
	end
	local maxes = statMax()
	for statKey, row in pairs(U.StatRows) do
		local value = stats and stats[statKey]
		if type(value) == "number" then
			row.Value.Text = commas(math.floor(value + 0.5))
			row.Value.TextColor3 = INK
			row.Fill.Size = UDim2.new(Util.Clamp(value / (maxes[statKey] or 1), 0.04, 1), 0, 1, 0)
		else
			row.Value.Text = "?"
			row.Value.TextColor3 = MUTED
			row.Fill.Size = UDim2.new(0, 0, 1, 0)
		end
	end

	-- special attack
	local special = discovered and type(def.Special) == "table" and def.Special or nil
	U.Special.Visible = special ~= nil
	if special then
		U.SpecialName.Text = tostring(special.Name or "Special")
		U.SpecialKind.Text = tostring(special.Kind or "")
		U.SpecialKind.Visible = special.Kind ~= nil
	end

	-- element matchups
	local matchups = {}
	for _, element in ipairs(elements) do
		local text = matchupText(element)
		if text ~= "" then
			table.insert(matchups, element .. ": " .. text)
		end
	end
	U.Matchup.Visible = #matchups > 0
	U.Matchup.Text = table.concat(matchups, "\n")

	-- blurb or how to find it
	if discovered then
		local text = tostring(def.Blurb or "")
		if hybrid then
			-- PetKeys' hybrid blurb names both parents ("A fusion of Maple Fox and Storm Tabby.")
			text = text .. " One of a kind: its parents' average stats x1.2."
		elseif tier ~= "Normal" then
			text = "A " .. tier .. " copy: x" .. (tier == "Rainbow" and "2.5" or "1.5") .. " stats and perks. " .. text
		end
		U.Info.Text = text
		U.Info.TextColor3 = INK
		local owned = State.OwnedCount(def.Id)
		U.Owned.Visible = true
		if owned > 0 and fused then
			U.Owned.Text = "Lv " .. petLevelOf(def.Id) .. "   " .. string.char(226, 128, 162) .. "   You own x" .. owned
			U.Owned.TextColor3 = INK
		elseif owned > 0 then
			U.Owned.Text = "You own x" .. owned
			U.Owned.TextColor3 = INK
		else
			U.Owned.Text = "Discovered"
			U.Owned.TextColor3 = MUTED
		end
	else
		local where = sourcesText(def)
		if def.Rarity == "Secret" then
			U.Info.Text = "A Secret pet. Summon it at the Storm Altar, or hatch it from the Celestial Roulette."
		elseif where then
			U.Info.Text = "Not discovered yet. Found in: " .. where .. "."
		else
			U.Info.Text = "Not discovered yet."
		end
		U.Info.TextColor3 = MUTED
		U.Owned.Visible = false
	end
end

----------------------------------------------------------------------
-- Selection
----------------------------------------------------------------------
function selectPet(petId)
	S.PetId = petId
	for _, tile in pairs(S.Tiles) do
		paintTile(tile)
	end
	renderDetail()
end

-- scrolls the group list so the tile of `groupId` is in view (Open("Fusions") on a short screen)
function revealGroupTile(groupId)
	local list = U.GroupList
	local index = nil
	if groupId == FUSIONS then
		index = #S.Groups + 1
	else
		for i, group in ipairs(S.Groups) do
			if group.Id == groupId then
				index = i
			end
		end
	end
	if not list or not index then
		return
	end
	if S.Tall then
		return -- the sideways strip of the portrait layout: the player scrolls it (the header names the group)
	end
	-- CanvasPosition is in the list's own (pre-UIScale) pixels, like the tile sizes; the window's pop-in UIScale
	-- may still be running (it starts at 0.86)
	local scale = math.max(((U.Fit and U.Fit.Scale) or 1) * ((U.Pop and U.Pop.Scale) or 1), 0.01)
	local visible = list.AbsoluteSize.Y / scale
	if visible <= 1 then
		return
	end
	local tileH = S.Short and K.GROUP_TILE_H_SHORT or K.GROUP_TILE_H
	local top = 6 + (index - 1) * (tileH + 6)
	local bottom = top + tileH
	local y = list.CanvasPosition.Y
	if top < y then
		y = top - 6
	elseif bottom > y + visible then
		y = bottom - visible + 6
	end
	list.CanvasPosition = Vector2.new(0, math.max(0, y))
end

local function defaultPetOf(group)
	-- the first discovered pet, else the first one
	for _, def in ipairs(group.Pets) do
		if State.IsDiscovered(def.Id) then
			return def.Id
		end
	end
	return group.Pets[1] and group.Pets[1].Id or nil
end

function selectGroup(groupId)
	-- the Fusions tab is a pseudo group: the player's fused copies (keys), rebuilt when that set changes
	local fusions = groupId == FUSIONS
	local group = S.GroupById[groupId]
	if not fusions and not group then
		return
	end
	local pets, sig
	if fusions then
		pets, sig = fusionDefs()
	else
		pets = group.Pets
	end
	local changed = S.GroupId ~= groupId or #S.TileOrder == 0 or (fusions and S.FusionSig ~= sig)
	S.GroupId = groupId
	if S.ElementsShown then
		showElements(false)
	end
	if changed then
		clearTiles()
		S.FusionSig = sig
		for index, def in ipairs(pets) do
			buildTile(def, index)
		end
		U.Grid.CanvasPosition = Vector2.new(0, 0)
		local keep = false
		for _, def in ipairs(pets) do
			if def.Id == S.PetId then
				keep = true
			end
		end
		if not keep then
			if fusions then
				S.PetId = pets[1] and pets[1].Id or nil
			else
				S.PetId = defaultPetOf(group)
			end
		end
	end
	if U.FusionEmpty then
		U.FusionEmpty.Visible = fusions and #pets == 0
	end
	if changed then
		revealGroupTile(groupId)
	end
	refreshGroupTiles()
	renderHeader()
	renderRewards()
	selectPet(S.PetId)
	fillViewports()
end

local function defaultGroup()
	-- a reward waiting first, then the first group still missing pets, else the first group
	for _, group in ipairs(S.Groups) do
		local _, _, _, _, claimable = groupStatus(group)
		if claimable then
			return group.Id
		end
	end
	for _, group in ipairs(S.Groups) do
		local _, _, complete = groupStatus(group)
		if not complete then
			return group.Id
		end
	end
	return S.Groups[1] and S.Groups[1].Id or nil
end

function refreshAll()
	if not S.Built then
		return
	end
	if S.GroupId == FUSIONS then
		-- a fusion added / used up a copy while the tab is shown: rebuild its grid
		local _, sig = fusionDefs()
		if sig ~= S.FusionSig then
			selectGroup(FUSIONS)
		end
	end
	refreshGroupTiles()
	refreshTiles()
	renderHeader()
	renderRewards()
	renderFooter()
	renderDetail()
end

----------------------------------------------------------------------
-- Claim
----------------------------------------------------------------------
local function requestClaim()
	local group = S.GroupById[S.GroupId]
	if not group then
		return
	end
	local _, _, _, _, claimable = groupStatus(group)
	if not claimable or S.ClaimPending then
		return
	end
	local now = os.clock()
	if now - S.LastClaim < K.CLAIM_GAP then
		return
	end
	local remote = getClaimRemote()
	if not remote then
		return
	end
	S.LastClaim = now
	local ok = pcall(function()
		remote:FireServer(group.Id)
	end)
	if not ok then
		return
	end
	S.ClaimPending = group.Id
	S.ClaimToken = S.ClaimToken + 1
	local mine = S.ClaimToken
	renderRewards()
	task.delay(K.CLAIM_TIMEOUT, function()
		if S.ClaimToken == mine and S.ClaimPending then
			S.ClaimPending = nil
			if S.Built then
				renderRewards()
			end
		end
	end)
end

----------------------------------------------------------------------
-- Elements help card (the element wheel, section 11)
----------------------------------------------------------------------
local function elementCycle()
	local elements = Config.Elements
	if type(elements) ~= "table" or type(elements.Order) ~= "table" or type(elements.Strong) ~= "table" then
		return {}, {}
	end
	local cycle, inCycle = {}, {}
	local current = elements.Order[1]
	while current and not inCycle[current] and #cycle < #elements.Order do
		inCycle[current] = true
		table.insert(cycle, current)
		local nextList = elements.Strong[current]
		current = type(nextList) == "table" and nextList[1] or nil
	end
	if current ~= cycle[1] then
		-- not a closed wheel: show everything as plain pairs instead
		cycle, inCycle = {}, {}
	end
	local rest = {}
	for _, e in ipairs(elements.Order) do
		if not inCycle[e] then
			table.insert(rest, e)
		end
	end
	return cycle, rest
end

local function buildElementsCard()
	local card = makeFrame(U.Centre, "ElementsCard", {
		Size = UDim2.new(1, 0, 1, -(K.REWARD_H + 8)),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Stone,
		Visible = false,
		ZIndex = 20,
	})
	edge(card, SIGN.Wood, 3) -- (kit-b U8) a stone card in its wood edge
	U.ElementsCard = card
	local scroll = scroller(card, "Scroll", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		ZIndex = 21,
	})
	pad(scroll, 10, 8, 14, 10)
	listLayout(scroll, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center)
	Theme.StyleTitle(makeText(scroll, "Title", "Elements", "Title", 30, INK, {
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 1,
		ZIndex = 22,
	}), "Section")
	makeText(scroll, "Explain", "Every pet has an element. In battles an element deals x1.5 damage to the one its arrow points at, and only x0.75 back.", "Body", 19, MUTED, {
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 2,
		ZIndex = 22,
	})
	local cycle, rest = elementCycle()
	if #cycle >= 3 then
		local wheel = makeFrame(scroll, "Wheel", {
			Size = UDim2.new(1, 0, 0, 330),
			LayoutOrder = 3,
			ZIndex = 22,
		})
		Util.Create("UISizeConstraint", { MaxSize = Vector2.new(400, 330), Parent = wheel })
		local n = #cycle
		for i, element in ipairs(cycle) do
			local angle = math.rad(-90 + (i - 1) * 360 / n)
			local holder = makeFrame(wheel, "Slot_" .. element, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5 + math.cos(angle) * 0.35, 0, 0.5 + math.sin(angle) * 0.38, 0),
				Size = UDim2.fromOffset(100, 34),
				ZIndex = 22,
			})
			listLayout(holder, Enum.FillDirection.Horizontal, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
			elementPill(holder, element, 18, 1)
			-- arrow half way to the next element, pointing clockwise (screen y grows downwards)
			local mid = angle + math.rad(180 / n)
			local arrow = makeText(wheel, "Arrow" .. i, "", "Title", 24, SIGN.Wood, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5 + math.cos(mid) * 0.41, 0, 0.5 + math.sin(mid) * 0.43, 0),
				Size = UDim2.fromOffset(28, 28),
				Rotation = math.deg(mid) + 90,
				ZIndex = 23,
			})
			PixelIcon.Host(arrow, ICON.Arrow, 18) -- (kit-b U7b) the label's rotation turns it with the wheel
		end
		makeText(wheel, "Centre", "beats", "Script", 20, MUTED, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.fromOffset(120, 30),
			ZIndex = 22,
		})
	end
	-- the rest as mutual pairs (Celestial <-> Shadow)
	local strongMap = Config.Elements and Config.Elements.Strong or {}
	local done = {}
	local order = 4
	for _, element in ipairs(rest) do
		if not done[element] then
			done[element] = true
			local partner = type(strongMap[element]) == "table" and strongMap[element][1] or nil
			local row = makeFrame(scroll, "Pair_" .. element, {
				Size = UDim2.new(1, 0, 0, 36),
				LayoutOrder = order,
				ZIndex = 22,
			})
			order = order + 1
			listLayout(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
			elementPill(row, element, 18, 1)
			if partner and partner ~= element then
				done[partner] = true
				PixelIcon.Host(makeText(row, "Both", "", "Title", 24, SIGN.Wood, { Size = UDim2.fromOffset(34, 32), LayoutOrder = 2, ZIndex = 22 }), ICON.Swap, 18) -- (kit-b U7b)
				elementPill(row, partner, 18, 3)
			end
		end
	end
	local back = CloudUI.Button({
		Name = "CloseElements",
		Text = "Back to pets",
		Style = "Gray",
		Skin = "Sign",
		Size = UDim2.fromOffset(220, 52),
		TextSize = 22,
		LayoutOrder = 50,
		ZIndex = 22,
		Callback = function()
			showElements(false)
		end,
		Parent = scroll,
	})
	back.ZIndex = 22
end

function showElements(on)
	if not U.ElementsCard then
		if not on then
			return
		end
		buildElementsCard()
	end
	S.ElementsShown = on and true or false
	U.ElementsCard.Visible = S.ElementsShown
	if U.ElementsButton then
		U.ElementsButton.Text = S.ElementsShown and "Pets" or "Elements"
	end
end

----------------------------------------------------------------------
-- Window construction
----------------------------------------------------------------------
local function buildCentre(centre)
	-- header: group name + progress bar "x/N"
	local header = inset(centre, "GroupHeader", { Size = UDim2.new(1, 0, 0, K.HEADER_H) })
	U.Header = header
	U.GroupTitle = makeText(header, "GroupTitle", "", "Title", 28, INK, {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(0.5, -16, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
	})
	Util.Create("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 18, Parent = U.GroupTitle })
	local track = makeFrame(header, "Progress", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.new(0.46, 0, 0, 30),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Tile,
	})
	edge(track, SIGN.Wood, 2) -- (kit-b U8) a flat bar: stone track, wood edge, the rarity's fill
	U.HeaderFill = makeFrame(track, "Fill", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Grass,
	})
	U.HeaderCount = makeText(track, "Count", "0/0", "Display", 22, INK, {
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 3,
	})

	-- the pet grid
	local well = inset(centre, "GridWell", {
		Position = UDim2.fromOffset(0, K.HEADER_H + 8),
		Size = UDim2.new(1, 0, 1, -(K.HEADER_H + 8 + K.REWARD_H + 8)),
	})
	U.GridWell = well
	U.Grid = scroller(well, "PetGrid", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
	})
	pad(U.Grid, 8, 8, 12, 8)
	U.GridLayout = Util.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(K.TILE_W, K.TILE_H),
		CellPadding = UDim2.fromOffset(K.TILE_GAP, K.TILE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = U.Grid,
	})
	-- the Fusions tab without any fused pet yet
	U.FusionEmpty = makeFrame(well, "FusionEmpty", { Size = UDim2.new(1, 0, 1, 0), Visible = false, ZIndex = 5 })
	listLayout(U.FusionEmpty, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local emptyGlyph = makeText(U.FusionEmpty, "Glyph", "", "Title", 54, SIGN.VioletLip, {
		Size = UDim2.new(1, 0, 0, 60),
		LayoutOrder = 1,
		ZIndex = 5,
	})
	PixelIcon.Host(emptyGlyph, ICON.Sparkle, 54) -- (kit-b U7b)
	Theme.StyleTitle(makeText(U.FusionEmpty, "Title", "No fused pets yet", "Title", 28, INK, {
		Size = UDim2.new(1, -30, 0, 34),
		LayoutOrder = 2,
		ZIndex = 5,
	}), "Section")
	makeText(U.FusionEmpty, "Body", "Golden and Rainbow copies and the hybrids you mix at the Fusion Machine show up here.", "Body", 19, MUTED, {
		Size = UDim2.new(1, -60, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 3,
		ZIndex = 5,
	})

	-- rewards box + CLAIM
	local rewards = inset(centre, "Rewards", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, K.REWARD_H),
	})
	U.Rewards = rewards
	U.RewardLabel = makeText(rewards, "Label", "Rewards:", "Heading", 22, INK, {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(120, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	U.RewardAmount = makeText(rewards, "Amount", "", "Display", 30, INK, {
		Position = UDim2.fromOffset(140, 6),
		Size = UDim2.new(1, -350, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	PixelIcon.Lead(U.RewardAmount, Theme.Currency.Tokens.Icon) -- (kit-b U7a) the coin before the amount
	U.RewardSub = makeText(rewards, "Sub", "", "Body", 18, MUTED, {
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -230, 0, 44),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	U.ClaimButton = CloudUI.Button({
		Name = "Claim",
		Text = "Claim",
		Style = "Gray",
		Skin = "Sign", -- (kit-b U8) green only while the reward waits (renderRewards)
		Size = UDim2.fromOffset(184, 60),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		TextSize = 26,
		ZIndex = 2,
		Callback = function()
			if S.GroupId == FUSIONS then
				if hasFusionMachine() then
					safe("fusion machine", openFusionMachine)
				else
					safe("home window", openHomeWindow)
				end
			else
				safe("claim", requestClaim)
			end
		end,
		Parent = rewards,
	})
end

local function buildDetail(detail)
	U.DetailEmpty = makeText(detail, "Hint", "Pick a pet to see its card.", "Body", 19, MUTED, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -40, 0, 60),
		TextWrapped = true,
	})
	local body = scroller(detail, "DetailBody", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		Visible = false,
	})
	U.DetailBody = body
	pad(body, 10, 8, 14, 12)
	listLayout(body, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)

	-- big viewport in the square light pet well (kit-b U8: was two soft gold glow discs) and a "?" behind silhouettes
	local view = makeFrame(body, "View", { Size = UDim2.new(1, 0, 0, K.VIEW_H), LayoutOrder = 1 })
	U.View = view
	local well = makeFrame(view, "PetWell", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromScale(0.96, 0.96),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.PetWell,
	})
	Util.Create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = well })
	edge(well, SIGN.WellEdge, 2)
	U.Mystery = makeText(view, "Mystery", "?", "Title", 100, MUTED, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromScale(0.6, 0.6),
		TextTransparency = 0.6,
		TextStrokeTransparency = 1,
		ZIndex = 2,
	})
	U.ViewHolder = makeFrame(view, "ViewHolder", { Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 })

	U.Banner = Util.Create("ImageLabel", {
		Name = "ArtBanner",
		BackgroundColor3 = Color3.fromRGB(16, 22, 50),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 128),
		ScaleType = Enum.ScaleType.Crop,
		Visible = false,
		LayoutOrder = 2,
		Parent = body,
	})
	edge(U.Banner, SIGN.Wood, 3)

	U.Name = makeText(body, "Name", "", "Title", 30, INK, {
		Size = UDim2.new(1, 0, 0, 36),
		TextScaled = true,
		LayoutOrder = 3,
	})
	Util.Create("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 18, Parent = U.Name })
	-- rarity, role and element pills share one row that wraps when the card is narrow
	U.Meta = makeFrame(body, "Meta", {
		Size = UDim2.new(1, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
	})
	local metaLayout = listLayout(U.Meta, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	metaLayout.Wraps = true
	U.RoleBlurb = makeText(body, "RoleBlurb", "", "Body", 18, MUTED, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 6,
	})

	-- stats: label, bar, value
	local statsBox = inset(body, "Stats", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 7,
	})
	pad(statsBox, 10, 6, 10, 6)
	listLayout(statsBox, Enum.FillDirection.Vertical, 4)
	U.StatRows = {}
	local statKeys = PetCatalog.StatOrder or { "Income", "Power", "Health", "Speed" }
	local statNames = PetCatalog.StatNames or {}
	local statColors = {
		Income = Color3.fromRGB(112, 204, 98),
		Power = Color3.fromRGB(236, 112, 96),
		Health = Color3.fromRGB(240, 120, 150),
		Speed = Color3.fromRGB(98, 172, 232),
	}
	for i, statKey in ipairs(statKeys) do
		local row = makeFrame(statsBox, "Stat_" .. statKey, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = i })
		makeText(row, "Label", statNames[statKey] or statKey, "Heading", 18, INK, {
			Size = UDim2.new(0, 86, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local bar = makeFrame(row, "Bar", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 90, 0.5, 0),
			Size = UDim2.new(1, -150, 0, 12),
			BackgroundTransparency = 0,
			BackgroundColor3 = SIGN.Tile,
		})
		edge(bar, SIGN.WellEdge, 2)
		local fill = makeFrame(bar, "Fill", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = statColors[statKey] or GOLD,
		})
		local value = makeText(row, "Value", "?", "Heading", 18, INK, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 54, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		U.StatRows[statKey] = { Fill = fill, Value = value }
	end

	-- special attack
	local special = inset(body, "Special", {
		Size = UDim2.new(1, 0, 0, 58),
		LayoutOrder = 8,
	})
	U.Special = special
	local specialCaption = makeText(special, "Caption", "SPECIAL", "Heading", 18, INK, {
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	PixelIcon.Lead(specialCaption, ICON.Sparkle) -- (kit-b U7b)
	U.SpecialName = makeText(special, "SpecialName", "", "Title", 22, INK, {
		Position = UDim2.fromOffset(10, 26),
		Size = UDim2.new(1, -110, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
	})
	Util.Create("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 18, Parent = U.SpecialName })
	U.SpecialKind = makeText(special, "Kind", "", "Heading", 18, MUTED, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 28),
		Size = UDim2.fromOffset(90, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	U.Matchup = makeText(body, "Matchup", "", "Body", 18, INK, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 9,
	})
	U.Info = makeText(body, "Info", "", "Body", 19, INK, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 10,
	})
	U.Owned = makeText(body, "Owned", "", "Heading", 19, MUTED, {
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 11,
	})
end

local function buildWindow()
	if S.Built then
		return true
	end
	loadGroups()
	if #S.Groups == 0 then
		warnOnce("groups", "the pet catalog has no Index groups")
		return false
	end

	local holder = makeFrame(U.Gui, "Window_Index", {
		Size = UDim2.fromOffset(K.PREF_W, K.PREF_H),
		Visible = false,
		ZIndex = 3,
	})
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	local panel = CloudUI.Panel({
		Name = "IndexPanel",
		Title = "Pet Index",
		Closable = true,
		Skin = "Signboard", -- (kit-b U8) roof, navy header with the book, wood frame, stone body
		Icon = "book",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		OnClose = function()
			IndexController.Close()
		end,
		Parent = holder,
	})
	U.Panel = panel
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel.Root })
	local content = panel.Content

	local main = makeFrame(content, "Main", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 1, -(20 + K.FOOTER_H)),
	})
	U.Main = main

	-- left: group list + Elements button
	local hasElements = type(Config.Elements) == "table" and type(Config.Elements.Order) == "table"
	U.Groups = makeFrame(main, "Groups", { Size = UDim2.new(0, K.GROUP_W, 1, 0) })
	local listHeight = hasElements and -(K.ELEMENTS_BTN_H + 8) or 0
	U.GroupList = scroller(U.Groups, "GroupList", { Size = UDim2.new(1, 0, 1, listHeight) })
	U.GroupPad = pad(U.GroupList, 4, 6, 10, 6)
	U.GroupLayout = listLayout(U.GroupList, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	for index, group in ipairs(S.Groups) do
		buildGroupTile(group, index)
	end
	buildFusionTile(#S.Groups + 1)
	if hasElements then
		U.ElementsButton = CloudUI.Button({
			Name = "Elements",
			Text = "Elements",
			Style = "Gray",
			Skin = "Sign",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, -10, 0, K.ELEMENTS_BTN_H),
			TextSize = 22,
			Callback = function()
				safe("elements", showElements, not S.ElementsShown)
			end,
			Parent = U.Groups,
		})
	end

	-- centre: header, grid, rewards
	U.Centre = makeFrame(main, "Centre", {
		Position = UDim2.new(0, K.GROUP_W + K.GAP, 0, 0),
		Size = UDim2.new(1, -(K.GROUP_W + K.DETAIL_W + 2 * K.GAP), 1, 0),
	})
	buildCentre(U.Centre)

	-- right: detail card
	U.Detail = inset(main, "Detail", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, K.DETAIL_W, 1, 0),
	})
	buildDetail(U.Detail)

	-- footer: "Unlocked: x/N" over every pet
	local footer = makeFrame(content, "Footer", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -6),
		Size = UDim2.new(1, -20, 0, K.FOOTER_H - 6),
	})
	U.Footer = footer
	U.FooterText = makeText(footer, "Unlocked", "Unlocked: 0/0", "Title", 26, INK, {
		Size = UDim2.new(0, 260, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local track = makeFrame(footer, "Bar", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 270, 0.5, 0),
		Size = UDim2.new(1, -350, 0, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = SIGN.Well,
	})
	edge(track, SIGN.Wood, 2)
	U.FooterFill = makeFrame(track, "Fill", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = GOLD,
	})
	U.FooterPercent = makeText(footer, "Percent", "0%", "Display", 24, INK, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 70, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	S.Built = true
	relayout()
	return true
end

----------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------
-- (kit-b U8) on a touch screen Roblox's thumbstick and jump button go while the window is open (the jump button sat on
-- CLAIM at 844x390) and come back as they were: MenuController keeps the one owner set (required here at open / close
-- time, when both modules are loaded: no require cycle)
function syncTouch()
	local want = S.Open and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if want == (S.TouchOff == true) then
		return
	end
	S.TouchOff = want
	local module = script.Parent:FindFirstChild("MenuController")
	local ok, menu = pcall(require, module)
	if ok and type(menu) == "table" and type(menu.SetTouchHidden) == "function" then
		safe("touch", menu.SetTouchHidden, "Index", want)
	end
end

function IndexController.IsOpen()
	return S.Open
end

function IndexController.ClaimableCount()
	if #S.Groups == 0 then
		loadGroups()
	end
	local n = 0
	for _, group in ipairs(S.Groups) do
		local _, _, _, _, claimable = groupStatus(group)
		if claimable then
			n = n + 1
		end
	end
	return n
end

function IndexController.Open(groupId)
	if not initialized then
		IndexController.Init()
	end
	if not U.Gui then
		return
	end
	if not buildWindow() then
		return
	end
	local target = nil
	if type(groupId) == "string" then
		if S.GroupById[groupId] then
			target = groupId
		elseif groupId:lower() == FUSIONS:lower() or groupId:lower() == "fusion" then
			target = FUSIONS
		else
			-- accept any capitalisation ("common")
			for id in pairs(S.GroupById) do
				if id:lower() == groupId:lower() then
					target = id
				end
			end
		end
	end
	if not target and not S.Open then
		-- no group asked for: a waiting reward first, else where the player left off
		for _, group in ipairs(S.Groups) do
			local _, _, _, _, claimable = groupStatus(group)
			if claimable and not target then
				target = group.Id
			end
		end
	end
	target = target or S.GroupId or defaultGroup()
	local wasOpen = S.Open
	S.Open = true
	S.Token = S.Token + 1
	syncBackBinding()
	relayout()
	U.Holder.Visible = true
	if not wasOpen then
		U.Pop.Scale = 0.86
		tween(U.Pop, 0.22, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	safe("select", selectGroup, target)
	safe("refresh", refreshAll)
	syncTouch()
	if not wasOpen then
		IndexController.Opened:Fire(target)
	end
end

function IndexController.Close()
	if not S.Open then
		return
	end
	S.Open = false
	S.Token = S.Token + 1
	local mine = S.Token
	syncBackBinding()
	syncTouch()
	tween(U.Pop, 0.12, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.13, function()
		if S.Token == mine and not S.Open and U.Holder then
			U.Holder.Visible = false
		end
	end)
	IndexController.Closed:Fire()
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
local function onStateChanged()
	if not S.Built then
		return
	end
	local group = S.ClaimPending and S.GroupById[S.ClaimPending]
	if group and State.IsClaimed(group.Id) then
		-- the server confirmed the claim: celebrate on the rewards box
		S.ClaimPending = nil
		S.ClaimToken = S.ClaimToken + 1
		if S.Open and S.GroupId == group.Id and U.Rewards then
			burst(U.Rewards, rarityAccent(group.Rarity), 26, UDim2.new(1, -106, 0.5, 0))
		end
	end
	if S.Open then
		refreshAll()
	end
end

function IndexController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)

	local gui = CloudUI.NewScreenGui("NimbusIndex", K.DISPLAY_ORDER)
	U.Gui = gui
	U.Kit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if S.Built then
			safe("relayout", relayout)
		end
	end)
	State.Changed:Connect(function()
		safe("State.Changed", onStateChanged)
	end)
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if LocalPlayer:GetAttribute(Config.Attr.InMatch) == true then
				IndexController.Close()
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and S.Open then
			IndexController.Close()
		end
	end)
	task.spawn(getClaimRemote)
end

return IndexController
