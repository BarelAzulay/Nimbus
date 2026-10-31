-- PetBits (client UI): what the windows that show pets share about one pet copy (key = shared/PetKeys: Normal, Golden,
-- Rainbow, fused hybrids), split out of MenuController for the Pets window (team balance, Task 4). Reads State only.
--
--   Data:    parseKey, defOfKey, tierOf, isHybrid, tierMultiplier, displayName, elementsOf, rarityOrder, ownedKeys, petLevel,
--            xpToNext, levelCap, statsAt, battleStatsAt (the garden's numbers with Power / Health from the battle path, so one
--            window never shows two answers), battlePower (BattleCatalog.UnitPower of the copy, or nil), battleEntry (the entry
--            BattleCatalog reads), homeData, catalogCall (TycoonCatalog), slotsHolding, gardenCopies, isGardening,
--            firstFreeSlot, growth, stage, job, jobLeft, skillName, canEvolve, coinsPerSecond, formatCash, formatRate,
--            busyOf (nil | "Training" | "Garden": State.Busy, or the same answer from the home / the job on an old snapshot)
--   UI:      frame, text, corner, round, stroke, pad (the windows' Theme-styled building blocks)
--   PetBits.askRecall(gui, key, target, onYes, onNo, send): "This pet is gardening! Take it out of the garden and put it in
--            your team?" [Yes] [No]. Yes = ONE request (send("GardenRecall", { Key, To, Preset, Keys }), the server checks
--            everything and takes it out + stores the team); No = nothing. PetBits.closeRecall() -> true when one was up.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local UI = script.Parent
local Client = UI.Parent
local CloudUI = require(UI:WaitForChild("CloudUI"))
local State = require(Client:WaitForChild("State"))

local PetBits = {}

local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.Navy or Colors.Ink
local INK = Colors.TextStroke or Colors.Ink
local SEEDLING = "\240\159\140\177"
local CASH = (Theme.Currency and Theme.Currency.Cash and Theme.Currency.Cash.Glyph) or "$"
local GARDEN_COLOR = Color3.fromRGB(120, 196, 90)

-- The catalogs are written by other engineers: a broken one must not take the windows down.
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
	warn("[PetBits] " .. name .. " is unavailable: " .. tostring(result))
	return nil
end

local PetCatalog = optionalShared("PetCatalog") or { Pets = {}, Get = function() return nil end }
local PetKeys = optionalShared("PetKeys")
local TycoonCatalog = optionalShared("TycoonCatalog")

----------------------------------------------------------------------
-- UI building blocks
----------------------------------------------------------------------
function PetBits.frame(parent, name, props)
	local p = { Name = name }
	for key, value in pairs(props or {}) do
		p[key] = value
	end
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	p.BorderSizePixel = 0
	p.Parent = parent
	return Util.Create("Frame", p)
end

-- Theme-styled TextLabel (stroke + glyph outline, readable on any panel) with optional property overrides.
function PetBits.text(parent, name, text, role, size, color, props)
	local p = { Name = name }
	for key, value in pairs(props or {}) do
		p[key] = value
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

function PetBits.corner(parent, radius)
	return Theme.Corner(parent, UDim.new(0, radius or 12))
end

function PetBits.round(parent)
	return Theme.Corner(parent, UDim.new(0.5, 0))
end

function PetBits.stroke(parent, color, thickness, transparency)
	return Theme.Stroke(parent, color or NAVY, thickness or 3, transparency or 0)
end

function PetBits.pad(parent, left, top, right, bottom)
	return Util.Create("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		Parent = parent,
	})
end

----------------------------------------------------------------------
-- One pet copy
----------------------------------------------------------------------
function PetBits.parseKey(key)
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
function PetBits.defOfKey(key)
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

function PetBits.tierOf(key, def)
	local t = type(def) == "table" and def.Tier or nil
	if t == "Golden" or t == "Rainbow" then
		return t
	end
	local parsed = PetBits.parseKey(key)
	if parsed and (parsed.Tier == "Golden" or parsed.Tier == "Rainbow") then
		return parsed.Tier
	end
	return "Normal"
end

function PetBits.isHybrid(key, def)
	if type(def) == "table" and def.IsHybrid == true then
		return true
	end
	return type(key) == "string" and key:sub(1, 4) == "hyb:"
end

-- x1 / x1.5 / x2.5 (perks and stats of tier copies; hybrids carry their own)
function PetBits.tierMultiplier(key, def)
	if type(def) == "table" and type(def.StatMultiplier) == "number" and def.StatMultiplier > 0 then
		return def.StatMultiplier
	end
	local tier = PetBits.tierOf(key, def)
	if tier == "Rainbow" then
		return 2.5
	elseif tier == "Golden" then
		return 1.5
	end
	return 1
end

function PetBits.displayName(key, def)
	def = def or PetBits.defOfKey(key)
	if type(def) ~= "table" then
		return tostring(key)
	end
	return tostring(def.DisplayName or def.Name or key)
end

-- the elements of a def that Config.Elements knows, in order, once each
function PetBits.elementsOf(def)
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

function PetBits.rarityOrder(rarityId)
	for _, r in ipairs(Config.Rarities) do
		if r.Id == rarityId then
			return r.Order
		end
	end
	return 1
end

-- Owned pet copies: rarest first; inside a rarity the hybrids, then the catalog pets (reverse catalog order, a pet's
-- Rainbow / Golden copies right before its Normal ones).
function PetBits.ownedKeys()
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
			local def = PetBits.defOfKey(key)
			if def then
				info[key] = { Order = PetBits.rarityOrder(def.Rarity), Hybrid = PetBits.isHybrid(key, def) and 1 or 0, Index = i }
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
function PetBits.petLevel(key)
	if type(State.PetLevel) == "function" then
		local ok, level, xp = pcall(State.PetLevel, key)
		if ok and type(level) == "number" then
			return math.max(1, math.floor(level)), tonumber(xp) or 0
		end
	end
	return 1, 0
end

-- XP from `level` to the next one (math.huge at the top of the curve)
function PetBits.xpToNext(level)
	if TycoonCatalog and type(TycoonCatalog.XpToNext) == "function" then
		local ok, n = pcall(TycoonCatalog.XpToNext, level)
		if ok and type(n) == "number" and n > 0 then
			return n
		end
	end
	return math.huge
end

function PetBits.levelCap(key, def)
	if type(PetCatalog.LevelCap) == "function" then
		local ok, cap = pcall(PetCatalog.LevelCap, def or key)
		if ok and type(cap) == "number" and cap >= 1 then
			return math.floor(cap)
		end
	end
	return (TycoonCatalog and tonumber(TycoonCatalog.MaxPetLevel)) or 50
end

-- the pet's stats at its level (rarity scale x level factor x tier), or nil without a catalog that knows stats
function PetBits.statsAt(def, level)
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

function PetBits.homeData()
	if type(State.Home) == "function" then
		local ok, home = pcall(State.Home)
		if ok and type(home) == "table" then
			return home
		end
	end
	return { Level = 0, Prestige = 0, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0 }
end

function PetBits.catalogCall(fnName, ...)
	if not TycoonCatalog or type(TycoonCatalog[fnName]) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(TycoonCatalog[fnName], ...)
	if ok then
		return a, b
	end
	return nil
end

-- slots of `map` ({[slot] = key}) that hold `key`, ascending
function PetBits.slotsHolding(map, key)
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
function PetBits.gardenCopies(key)
	local home = PetBits.homeData()
	local open = PetBits.catalogCall("GardenSlots", home) or 0
	local n = 0
	for _, slot in ipairs(PetBits.slotsHolding(home.Garden, key)) do
		if open < 1 or slot <= open then
			n = n + 1
		end
	end
	return n
end

function PetBits.isGardening(key)
	local garden = PetBits.gardenCopies(key)
	return garden > 0 and State.OwnedCount(key) - garden < 1
end

function PetBits.firstFreeSlot(map, count)
	for slot = 1, count do
		if type(map) ~= "table" or map[slot] == nil then
			return slot
		end
	end
	return nil
end

-- one pet's growth { Evo, Speed, Physique, Ability, Defense, Job | nil } (State.PetGrowth; zeros when absent)
function PetBits.growth(key)
	if type(State.PetGrowth) == "function" then
		local ok, g = pcall(State.PetGrowth, key)
		if ok and type(g) == "table" then
			return g
		end
	end
	return { Evo = 0 }
end

-- Phase 5 (3.7): the stored stage the way every site draws it (State.PetStage: EvolutionStage of the stored Evo)
function PetBits.stage(key)
	if type(State.PetStage) == "function" then
		local ok, stage = pcall(State.PetStage, key)
		if ok and type(stage) == "number" then
			return math.max(0, math.floor(stage))
		end
	end
	return math.max(0, math.floor(tonumber(PetBits.growth(key).Evo) or 0))
end

-- the running training job of a key or nil
function PetBits.job(key)
	local job = PetBits.growth(key).Job
	return type(job) == "table" and job or nil
end

-- seconds left on a job ("2:10")
function PetBits.jobLeft(job)
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
function PetBits.skillName(stat)
	if stat == "Speed" then
		return "Attack Speed"
	end
	return tostring(stat or "")
end

-- the next evolution stage when the pet can EVOLVE now (PetCatalog.CanEvolve), else nil
function PetBits.canEvolve(key, def, level)
	if type(PetCatalog.CanEvolve) ~= "function" then
		return nil
	end
	local ok, nextStage = pcall(PetCatalog.CanEvolve, def or key, level, PetBits.stage(key))
	if ok and type(nextStage) == "number" and nextStage >= 1 then
		return nextStage
	end
	return nil
end

-- coins per second of a pet in this home's Garden (PetPower x food x stars / meal x the Lucky EV; the grass food
-- before the Garden is built)
function PetBits.coinsPerSecond(key, def, home)
	if not TycoonCatalog then
		return 0
	end
	local level = PetBits.petLevel(key)
	local power = PetBits.catalogCall("PetPower", { Def = def, Level = level, Stage = PetBits.stage(key), Key = key }) or 0
	local coins = TycoonCatalog.Coins or {}
	local food = PetBits.catalogCall("FoodOf", home) or 0
	if food <= 0 then
		food = tonumber(coins.GrassFood) or 12
	end
	local mult = PetBits.catalogCall("PrestigeMultiplier", math.floor(tonumber(home.Prestige) or 0)) or 1
	local lucky = PetBits.catalogCall("LuckyEV", home) or 1
	return power * food * mult * lucky / (tonumber(coins.MealSeconds) or 8)
end

-- "$950", "$12.5K" (TycoonCatalog.FormatCash, the same text as the pad signs)
function PetBits.formatCash(n)
	if TycoonCatalog and type(TycoonCatalog.FormatCash) == "function" then
		local ok, text = pcall(TycoonCatalog.FormatCash, n)
		if ok and type(text) == "string" then
			return text
		end
	end
	return CASH .. Theme.ShortNumber(tonumber(n) or 0)
end

-- cash per second: one decimal below 100 ("$7.5"), FormatCash above
function PetBits.formatRate(n)
	n = tonumber(n) or 0
	if n ~= n or n < 0 then
		n = 0
	end
	if n < 100 then
		local text = string.format("%.1f", math.floor(n * 10 + 0.5) / 10)
		text = text:gsub("%.0$", "")
		return CASH .. text
	end
	return PetBits.formatCash(n)
end

-- nil | "Training" | "Garden": such a pet keeps its team slot but neither follows nor fights (team balance, spec s.1)
function PetBits.busyOf(key)
	if type(State.Busy) == "function" then
		local ok, why = pcall(State.Busy, key)
		if ok and why then
			return why
		end
	end
	if PetBits.job(key) then
		return "Training"
	end
	if PetBits.isGardening(key) then
		return "Garden"
	end
	return nil
end

----------------------------------------------------------------------
-- Battle numbers
----------------------------------------------------------------------
function PetBits.battleCatalog()
	if PetBits.Battle == nil then
		PetBits.Battle = false
		local module = Shared:FindFirstChild("BattleCatalog")
		local ok, mod = pcall(function()
			return module and require(module)
		end)
		if ok and type(mod) == "table" and type(mod.UnitPower) == "function" then
			PetBits.Battle = mod
		end
	end
	return PetBits.Battle or nil
end

-- the detail's numbers: the garden's (statsAt) with Power and Health from the battle path (BattleCatalog.BattleStatsOf, the
-- copy's tier and stored stage), so one window never shows two answers; nil like statsAt
function PetBits.battleStatsAt(def, key, level)
	local stats = PetBits.statsAt(def, level)
	local battle = PetBits.battleCatalog()
	if type(stats) == "table" and battle and type(battle.BattleStatsOf) == "function" then
		local ok, numbers = pcall(battle.BattleStatsOf, def, level, PetBits.tierOf(key, def), PetBits.stage(key))
		if ok and type(numbers) == "table" then
			stats.Power, stats.Health = numbers.Power, numbers.Health
		end
	end
	return stats
end

-- the entry BattleCatalog.UnitPower / TeamPower read for a pet copy
function PetBits.battleEntry(key, def, level)
	local growth = PetBits.growth(key)
	local train = { Speed = growth.Speed, Physique = growth.Physique, Ability = growth.Ability, Defense = growth.Defense }
	return { Def = def, Key = key, Level = level, Tier = PetBits.tierOf(key, def), Evo = PetBits.stage(key), Train = train }
end

-- Phase 5 (m17): BattleCatalog.UnitPower of a pet copy (a Support pet with its Support role multipliers), or nil
function PetBits.battlePower(key, def, level)
	local battle = PetBits.battleCatalog()
	if not battle then
		return nil
	end
	local ok, power = pcall(battle.UnitPower, PetBits.battleEntry(key, def, level))
	if ok and type(power) == "number" then
		return math.floor(power + 0.5)
	end
	return nil
end

----------------------------------------------------------------------
-- The garden recall question
----------------------------------------------------------------------
function PetBits.closeRecall()
	local dialog = PetBits.RecallDialog
	if not dialog then
		return false
	end
	PetBits.RecallDialog = nil
	dialog:Destroy()
	return true
end

-- target = { To = "Team", Preset = n, Keys = {...} }; onYes (optional) runs after the request was sent, onNo when the
-- answer was No (Esc / gamepad B answer through closeRecall and keep what was armed)
function PetBits.askRecall(gui, key, target, onYes, onNo, send)
	PetBits.closeRecall()
	local overlay = PetBits.frame(gui, "GardenRecall", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.fromRGB(8, 12, 32),
		Active = true,
		ZIndex = 60,
	})
	PetBits.RecallDialog = overlay
	local box = PetBits.frame(overlay, "Box", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0, 210), -- phone: 92 % of the width, capped at 420 px
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		ZIndex = 61,
	})
	Util.Create("UISizeConstraint", { MaxSize = Vector2.new(420, 210), Parent = box })
	PetBits.corner(box, 16)
	PetBits.stroke(box, GARDEN_COLOR, 4, 0)
	Theme.Gradient(box, Colors.PanelLight, Colors.Panel, 90)
	PetBits.text(box, "Title", SEEDLING .. " This pet is gardening!", "Title", 28, GARDEN_COLOR, {
		Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 36), ZIndex = 62,
	})
	PetBits.text(box, "Body", "Take it out of the garden and put it in your team?", "Body", 20, WHITE, {
		Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 60), TextWrapped = true, ZIndex = 62,
	})
	local buttons = PetBits.frame(box, "Buttons", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -32, 0, 56), ZIndex = 62,
	})
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = buttons,
	})
	CloudUI.Button({
		Name = "RecallYes", Text = "Yes", Style = "Green", Size = UDim2.fromOffset(150, 56), TextSize = 24, LayoutOrder = 1, ZIndex = 63,
		Callback = function()
			PetBits.closeRecall()
			local arg = { Key = key, To = target.To, Preset = target.Preset, Keys = target.Keys }
			if send("GardenRecall", arg) and onYes then
				onYes()
			end
		end,
		Parent = buttons,
	})
	CloudUI.Button({
		Name = "RecallNo", Text = "No", Style = "Pink", Size = UDim2.fromOffset(150, 56), TextSize = 24, LayoutOrder = 2, ZIndex = 63,
		Callback = function()
			PetBits.closeRecall()
			if onNo then
				onNo()
			end
		end,
		Parent = buttons,
	})
end

return PetBits
