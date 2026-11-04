-- StoreCatalog: the Robux Store's catalog (docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.1 / 5.4; the
-- store plan, Task 4): the ONE product / pass lookup over Config.Store.Items AND Config.Gems.Products, the "Gets you:"
-- lines of a grant, and Validate. Pure data + logic: no Instances, safe on server and client (GemService routes every
-- receipt through ProductById -> StoreService.ApplyGrant; StoreController draws List). Config.Store.Items and
-- Config.Gems.Products are read on EVERY call (the owner pastes ids; tests change them). PetCatalog is required lazily
-- (only Validate and GrantLines touch it), so List / Item / ProductById / PassById stay cheap on the client and in the
-- sims. Plain Lua 5.1-compatible syntax only.
--
-- API
--   StoreCatalog.Tabs                    a copy of Config.Store.Tabs (Packs, Passes, Boosts, Currency, Roulettes)
--   StoreCatalog.List() -> { item... }   every Config.Store.Items entry with Enabled ~= false as a cleaned copy
--                                        { Key, Kind, Tab, Id (whole, >= 0), Robux, Name, Grants (by reference), Once,
--                                        Hero, Line, Created = Id > 0 }, in Config order, then one item per
--                                        Config.Gems.Products entry: { Key = "Gems<i>", Kind = "Product", Tab = "Currency",
--                                        Id, Name, Grants = { Gems }, Gem = true, Index = i, Hero = (i == 2: the Bag is
--                                        the Currency hero), Created }
--   StoreCatalog.Item(key) -> item | nil        a List item by Key (an Enabled = false entry answers nil)
--   StoreCatalog.ProductById(id) -> item | nil  Kind "Product" with Id == id > 0, the first match; the gem packs included;
--                                        a disabled entry still resolves (a paid receipt is never eaten; it is only
--                                        never LISTED or sold: Item answers nil for it)
--   StoreCatalog.PassById(id) -> item | nil     likewise for Kind "Pass"
--   StoreCatalog.Created(item) -> bool   the item's Id is > 0 (a Config entry or a List item)
--   StoreCatalog.Perk(name) -> table | nil      Config.Store.Perks[name] ({ Cash = 2 } / { PetXp = 2 } / ...)
--   StoreCatalog.GrantLines(grants) -> { string... }   the literal "Gets you:" lines in the order Pets, Cash, Tokens,
--                                        Gems, Boost, Perks: "1x Storm Tabby (Lv 5)" (no "(Lv n)" without a Level),
--                                        "$1,000 Cash", "5,000 Cloud Tokens", "550 Gems", "1 h x2 Pet XP" (3600 -> "1 h",
--                                        10800 -> "3 h", else "<n> min"), "x2 Cash forever" / "x2 Pet XP forever" /
--                                        "x1.5 Pet XP in Dungeons and raids" / "VIP: x2 daily Cash and Tokens, [VIP] in chat"
--   StoreCatalog.Validate() -> ok, problems     keys unique and non-empty; every Id > 0 unique across the items AND the
--                                        gem products; Kind Product | Pass; Tab in Tabs; Once / Boost / Pets / Cash /
--                                        Tokens / Gems only on Products (a Pass grants Perks only); whole numbers: Cash
--                                        1..1e9, Tokens 1..1e7, Gems 1..1e7, Boost.XpPotion 60..Potion.CapSeconds; every
--                                        Pets key a PetCatalog id with Count 1..MaxPerStack and Level 1..MaxPetLevel();
--                                        every Perks name in Config.Store.Perks; Robux a whole number >= 0 when present;
--                                        at most one Hero per tab among the Config items; the Currency Cash packs carry Line

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)

local StoreCatalog = {}

local PERK_LINES = {
	CashX2 = "x2 Cash forever",
	XpX2 = "x2 Pet XP forever",
	ProXp = "x1.5 Pet XP in Dungeons and raids",
	Vip = "VIP: x2 daily Cash and Tokens, [VIP] in chat",
}
local LIMITS = { Cash = 1e9, Tokens = 1e7, Gems = 1e7 } -- the largest whole grant of each currency
local MIN_POTION_SECONDS = 60
local GRANT_KEYS = { Pets = true, Cash = true, Tokens = true, Gems = true, Boost = true, Perks = true }
local GEM_HERO_INDEX = 2 -- the Bag of Gems is the Currency tab's hero (spec 5.1)

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

-- PetCatalog, required on first use only (GemService's getCatalog shape): Validate and GrantLines need it, nothing else does
local petCatalogRef, petCatalogTried = nil, false
local function getPetCatalog()
	if not petCatalogTried then
		petCatalogTried = true
		local ok, result = pcall(function()
			return require(script.Parent.PetCatalog)
		end)
		if ok and type(result) == "table" then
			petCatalogRef = result
		end
	end
	return petCatalogRef
end

local function isWhole(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n == math.floor(n)
end

local function store()
	return type(Config.Store) == "table" and Config.Store or {}
end

local function configItems()
	local s = store()
	return type(s.Items) == "table" and s.Items or {}
end

local function gemProducts()
	local gems = Config.Gems
	return type(gems) == "table" and type(gems.Products) == "table" and gems.Products or {}
end

local function cleanId(id)
	if isWhole(id) and id >= 0 then
		return id
	end
	return 0
end

-- a Config entry as a List item (the Grants table by reference: GrantLines and the services read it as written)
local function cleanItem(entry)
	local id = cleanId(entry.Id)
	return {
		Key = entry.Key,
		Kind = entry.Kind,
		Tab = entry.Tab,
		Id = id,
		Robux = entry.Robux,
		Name = entry.Name,
		Grants = entry.Grants,
		Once = entry.Once == true or nil,
		Hero = entry.Hero == true or nil,
		Line = entry.Line,
		Created = id > 0,
	}
end

local function gemItem(index, product)
	local id = cleanId(product.Id)
	return {
		Key = "Gems" .. tostring(index),
		Kind = "Product",
		Tab = "Currency",
		Id = id,
		Name = product.Name,
		Grants = { Gems = product.Gems },
		Gem = true,
		Index = index,
		Hero = index == GEM_HERO_INDEX,
		Created = id > 0,
	}
end

-- every item of both lists, the disabled Config entries included when `all` is true (the id lookups of a paid receipt)
local function allItems(all)
	local out = {}
	for _, entry in ipairs(configItems()) do
		if type(entry) == "table" and (all or entry.Enabled ~= false) then
			out[#out + 1] = cleanItem(entry)
		end
	end
	for index, product in ipairs(gemProducts()) do
		if type(product) == "table" then
			out[#out + 1] = gemItem(index, product)
		end
	end
	return out
end

local function byId(kind, id)
	if not isWhole(id) or id <= 0 then
		return nil
	end
	for _, item in ipairs(allItems(true)) do
		if item.Kind == kind and item.Id == id then
			return item
		end
	end
	return nil
end

local function durationText(seconds)
	if seconds % 3600 == 0 then
		return string.format("%d h", seconds / 3600)
	end
	return string.format("%d min", math.floor(seconds / 60))
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

StoreCatalog.Tabs = {}
for i, tab in ipairs(store().Tabs or {}) do
	StoreCatalog.Tabs[i] = tab
end

function StoreCatalog.List()
	return allItems(false)
end

function StoreCatalog.Item(key)
	if type(key) ~= "string" then
		return nil
	end
	for _, item in ipairs(allItems(false)) do
		if item.Key == key then
			return item
		end
	end
	return nil
end

function StoreCatalog.ProductById(id)
	return byId("Product", id)
end

function StoreCatalog.PassById(id)
	return byId("Pass", id)
end

function StoreCatalog.Created(item)
	return type(item) == "table" and isWhole(item.Id) and item.Id > 0
end

function StoreCatalog.Perk(name)
	local perks = store().Perks
	if type(name) ~= "string" or type(perks) ~= "table" then
		return nil
	end
	local perk = perks[name]
	return type(perk) == "table" and perk or nil
end

function StoreCatalog.GrantLines(grants)
	local out = {}
	if type(grants) ~= "table" then
		return out
	end
	if type(grants.Pets) == "table" then
		local ids = {}
		for petId in pairs(grants.Pets) do
			ids[#ids + 1] = tostring(petId)
		end
		table.sort(ids)
		local pc = getPetCatalog()
		for _, petId in ipairs(ids) do
			local spec = grants.Pets[petId]
			local def = pc and type(pc.Get) == "function" and pc.Get(petId) or nil
			local name = (def and type(def.Name) == "string") and def.Name or petId
			local count = type(spec) == "table" and tonumber(spec.Count) or 1
			local level = type(spec) == "table" and tonumber(spec.Level) or nil
			out[#out + 1] = string.format("%dx %s", count, name) .. (level and string.format(" (Lv %d)", level) or "")
		end
	end
	if type(grants.Cash) == "number" then
		out[#out + 1] = "$" .. Util.Commas(grants.Cash) .. " Cash"
	end
	if type(grants.Tokens) == "number" then
		out[#out + 1] = Util.Commas(grants.Tokens) .. " Cloud Tokens"
	end
	if type(grants.Gems) == "number" then
		out[#out + 1] = Util.Commas(grants.Gems) .. " Gems"
	end
	if type(grants.Boost) == "table" and type(grants.Boost.XpPotion) == "number" then
		out[#out + 1] = durationText(grants.Boost.XpPotion) .. " x2 Pet XP"
	end
	if type(grants.Perks) == "table" then
		for _, name in ipairs(grants.Perks) do
			out[#out + 1] = PERK_LINES[name] or tostring(name)
		end
	end
	return out
end

function StoreCatalog.Validate()
	local problems = {}
	local function bad(msg)
		problems[#problems + 1] = msg
	end
	local s = store()
	if type(s.Items) ~= "table" then
		bad("Config.Store.Items is missing")
		return false, problems
	end
	local tabSet = {}
	for _, tab in ipairs(type(s.Tabs) == "table" and s.Tabs or {}) do
		tabSet[tab] = true
	end
	local perks = type(s.Perks) == "table" and s.Perks or {}
	local cap = (type(s.Potion) == "table" and isWhole(s.Potion.CapSeconds) and s.Potion.CapSeconds) or 7 * 86400
	local pc = getPetCatalog()
	local maxLevel = (pc and type(pc.MaxPetLevel) == "function" and pc.MaxPetLevel()) or 100
	local maxStack = (type(Config.Pets) == "table" and isWhole(Config.Pets.MaxPerStack) and Config.Pets.MaxPerStack) or 99
	local seenKeys, seenIds, heroByTab = {}, {}, {}
	local function checkId(label, id)
		if id ~= nil and (not isWhole(id) or id < 0) then
			bad(label .. ": Id must be a whole number >= 0")
		elseif isWhole(id) and id > 0 then
			if seenIds[id] then
				bad(label .. ": Id " .. tostring(id) .. " is also " .. seenIds[id] .. "'s")
			else
				seenIds[id] = label
			end
		end
	end
	for i, it in ipairs(s.Items) do
		local key = (type(it.Key) == "string" and it.Key ~= "") and it.Key or nil
		local label = key or ("item " .. tostring(i))
		if not key then
			bad(label .. ": Key must be a non-empty string")
		elseif seenKeys[key] then
			bad(label .. ": duplicate Key")
		else
			seenKeys[key] = true
		end
		if it.Kind ~= "Product" and it.Kind ~= "Pass" then
			bad(label .. ": Kind must be Product or Pass, got " .. tostring(it.Kind))
		end
		if not tabSet[it.Tab] then
			bad(label .. ": Tab " .. tostring(it.Tab) .. " is not in Config.Store.Tabs")
		end
		if type(it.Name) ~= "string" or it.Name == "" then
			bad(label .. ": Name must be a non-empty string")
		end
		checkId(label, it.Id)
		if it.Robux ~= nil and (not isWhole(it.Robux) or it.Robux < 0) then
			bad(label .. ": Robux must be a whole number >= 0")
		end
		if it.Hero == true then
			if heroByTab[it.Tab] then
				bad(label .. ": a second Hero in tab " .. tostring(it.Tab) .. " (" .. heroByTab[it.Tab] .. " is its hero)")
			else
				heroByTab[it.Tab] = label
			end
		end
		if it.Kind == "Pass" and it.Once then
			bad(label .. ": Once is for Products (a pass is owned for good anyway)")
		end
		local g = it.Grants
		if type(g) ~= "table" then
			bad(label .. ": Grants missing")
		else
			local any = false
			for k in pairs(g) do
				any = true
				if not GRANT_KEYS[k] then
					bad(label .. ": unknown grant " .. tostring(k))
				elseif it.Kind == "Pass" and k ~= "Perks" then
					bad(label .. ": a Pass grants Perks only, not " .. tostring(k))
				end
			end
			if not any then
				bad(label .. ": Grants is empty")
			end
			for _, currency in ipairs({ "Cash", "Tokens", "Gems" }) do
				local n = g[currency]
				if n ~= nil and (not isWhole(n) or n < 1 or n > LIMITS[currency]) then
					bad(label .. ": " .. currency .. " must be a whole number 1.." .. string.format("%d", LIMITS[currency]))
				end
			end
			if g.Boost ~= nil then
				if type(g.Boost) ~= "table" then
					bad(label .. ": Boost must be { XpPotion = seconds }")
				else
					local seconds = g.Boost.XpPotion
					if not isWhole(seconds) or seconds < MIN_POTION_SECONDS or seconds > cap then
						bad(label .. ": Boost.XpPotion must be whole seconds " .. MIN_POTION_SECONDS .. ".." .. tostring(cap))
					end
					for k in pairs(g.Boost) do
						if k ~= "XpPotion" then
							bad(label .. ": unknown boost " .. tostring(k))
						end
					end
				end
			end
			if g.Pets ~= nil then
				if type(g.Pets) ~= "table" then
					bad(label .. ": Pets must be { [petId] = { Count, Level } }")
				else
					for petId, spec in pairs(g.Pets) do
						local def = (pc and type(pc.Get) == "function") and pc.Get(petId) or nil
						if not def then
							bad(label .. ": unknown pet " .. tostring(petId))
						end
						if type(spec) ~= "table" then
							bad(label .. ": Pets." .. tostring(petId) .. " must be { Count, Level }")
						else
							if not isWhole(spec.Count) or spec.Count < 1 or spec.Count > maxStack then
								bad(label .. ": Pets." .. tostring(petId) .. ".Count must be 1.." .. tostring(maxStack))
							end
							if spec.Level ~= nil and (not isWhole(spec.Level) or spec.Level < 1 or spec.Level > maxLevel) then
								bad(label .. ": Pets." .. tostring(petId) .. ".Level must be 1.." .. tostring(maxLevel))
							end
						end
					end
				end
			end
			if g.Perks ~= nil then
				if type(g.Perks) ~= "table" or #g.Perks == 0 then
					bad(label .. ": Perks must be a non-empty list of Config.Store.Perks names")
				else
					for _, name in ipairs(g.Perks) do
						if type(name) ~= "string" or type(perks[name]) ~= "table" then
							bad(label .. ": perk " .. tostring(name) .. " is not in Config.Store.Perks")
						end
					end
				end
			end
			if it.Kind == "Product" and it.Tab == "Currency" and g.Cash ~= nil and type(it.Line) ~= "string" then
				bad(label .. ": a Cash pack carries its Prestige Line")
			end
		end
	end
	for index, product in ipairs(gemProducts()) do
		local label = "Gems" .. tostring(index)
		if type(product) ~= "table" then
			bad(label .. ": not a table")
		else
			checkId(label, product.Id)
			if not isWhole(product.Gems) or product.Gems < 1 or product.Gems > LIMITS.Gems then
				bad(label .. ": Gems must be a whole number 1.." .. string.format("%d", LIMITS.Gems))
			end
			if type(product.Name) ~= "string" or product.Name == "" then
				bad(label .. ": Name must be a non-empty string")
			end
		end
	end
	return #problems == 0, problems
end

return StoreCatalog
