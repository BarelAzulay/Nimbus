-- Multipliers (store 2026-11-04; docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.4 / 7 Z5): the paid
-- multipliers at the five earning sites, and the three attributes the client reads. Reached through Init deps only
-- (TycoonService's scoop, BattleService's Ring Cash, DungeonService's room and chest Cash, PetCareService's grantXp):
-- never inside DataService.AddCash / AddPetXp, so refunds, the tutorial's gifts, prestige Gems, Double Rewards
-- (Tokens) and the bank itself stay base (Z5).
--
--   Cash(player, amount, source)  amount x 2 with the Cash2x pass (Config.Store.Perks.CashX2.Cash), else x 1
--   PetXp(player, xp, source)     xp x max(pass PetXp2x -> 2, a running XP potion -> 2) (never x4)
--                                 x 1.5 with Store.Bought.Pro on a PvE source only (Dungeon / Raid; never Ring, Duel, Feed)
--   State(player) -> { Cash = 1 | 2, PetXp = 1 | 2, PvE = 1 | 1.5, PotionEnds, Passes = {[key] = true}, Bought = {[key] = true} }
--   Refresh(player)               writes OwnedPasses (csv, Config.Store.Items order), StoreBought (csv), XpBoostEnds
--                                 (unix or 0) on the Player, only on change; connected to StoreService.Changed and to
--                                 DataService.ProfileLoaded / ProfileRebased (the load, a provisional profile's recovery)
--   StoreBought comes ONLY from a real record: while DataService.GetStore answers nil (loading or provisional) the
--   attribute is absent (nil; cleared if it was set), never "" (the client reads absent as "not known yet", "" as
--   "nothing bought"); once GetStore answers it is the csv ("" for nothing bought).
--   Init(deps)                    deps = { StoreService, DataService }; without StoreService every factor is 1
-- A junk amount (nil, NaN) passes through unchanged; the sites floor as they do today.
--
-- Plain Lua 5.1-compatible syntax only. Nothing here yields.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Multipliers = {}

local POTION_ID = "XpPotion"
local PASS_CASH = "Cash2x"
local PASS_XP = "PetXp2x"
local PACK_PRO = "Pro"
local PVE = { Dungeon = true, Raid = true }

local S = {
	Store = nil,
	DS = nil,
	Last = {}, -- [player] = { Passes = csv, Bought = csv | nil (absent), Ends = n } the attributes as last written
	Started = false,
}
Multipliers._S = S

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function perk(name, field, default)
	local perks = type(Config.Store) == "table" and type(Config.Store.Perks) == "table" and Config.Store.Perks[name] or nil
	local v = type(perks) == "table" and tonumber(perks[field]) or nil
	if v and v >= 1 then
		return v
	end
	return default
end

local function items()
	return type(Config.Store) == "table" and type(Config.Store.Items) == "table" and Config.Store.Items or {}
end

local function owns(player, key)
	local store = S.Store
	return store ~= nil and type(store.Owns) == "function" and store.Owns(player, key) == true
end

-- the stored Store record (a copy) or nil while loading / provisional (then nothing bought counts)
local function recordOf(player)
	local DS = S.DS
	if not DS or type(DS.GetStore) ~= "function" then
		return nil
	end
	local ok, store = pcall(DS.GetStore, player)
	if ok and type(store) == "table" then
		return store
	end
	return nil
end

local function bought(player, key)
	local store = recordOf(player)
	return store ~= nil and type(store.Bought) == "table" and store.Bought[key] ~= nil
end

local function potionEnds(player)
	local store = S.Store
	if not store or type(store.BoostEnds) ~= "function" then
		return 0
	end
	local ends = store.BoostEnds(player, POTION_ID)
	return isFinite(ends) and ends or 0
end

function Multipliers.Cash(player, amount, source)
	if not isFinite(amount) or not isPlayer(player) then
		return amount
	end
	if owns(player, PASS_CASH) then
		return amount * perk("CashX2", "Cash", 2)
	end
	return amount
end

function Multipliers.PetXp(player, xp, source)
	if not isFinite(xp) or not isPlayer(player) then
		return xp
	end
	local m = 1
	if owns(player, PASS_XP) or potionEnds(player) > os.time() then
		m = perk("XpX2", "PetXp", 2) -- the pass or the potion: the same x2, never stacked
	end
	if PVE[source] and bought(player, PACK_PRO) then
		m = m * perk("ProXp", "PetXpPvE", 1.5)
	end
	return xp * m
end

function Multipliers.State(player)
	local state = { Cash = 1, PetXp = 1, PvE = 1, PotionEnds = 0, Passes = {}, Bought = {} }
	if not isPlayer(player) then
		return state
	end
	local store = recordOf(player)
	for _, item in ipairs(items()) do
		if type(item) == "table" and type(item.Key) == "string" then
			if item.Kind == "Pass" and owns(player, item.Key) then
				state.Passes[item.Key] = true
			elseif item.Once and store and type(store.Bought) == "table" and store.Bought[item.Key] ~= nil then
				state.Bought[item.Key] = true
			end
		end
	end
	state.PotionEnds = potionEnds(player)
	if state.Passes[PASS_CASH] then
		state.Cash = perk("CashX2", "Cash", 2)
	end
	if state.Passes[PASS_XP] or state.PotionEnds > os.time() then
		state.PetXp = perk("XpX2", "PetXp", 2)
	end
	if state.Bought[PACK_PRO] then
		state.PvE = perk("ProXp", "PetXpPvE", 1.5)
	end
	return state
end

local function csvOf(set)
	local out = {}
	for _, item in ipairs(items()) do
		if type(item) == "table" and set[item.Key] then
			out[#out + 1] = item.Key
		end
	end
	return table.concat(out, ",")
end

local function attrName(key)
	local name = Config.Attr and Config.Attr[key]
	return type(name) == "string" and name or nil
end

function Multipliers.Refresh(player)
	if not isPlayer(player) then
		return
	end
	local state = Multipliers.State(player)
	-- no record (loading / provisional) = StoreBought absent: undecidable, not "nothing bought"
	local bought = recordOf(player) ~= nil and csvOf(state.Bought) or nil
	local now = { Passes = csvOf(state.Passes), Bought = bought, Ends = state.PotionEnds }
	local last = S.Last[player] or {}
	S.Last[player] = now
	local passesAttr, boughtAttr, endsAttr = attrName("OwnedPasses"), attrName("StoreBought"), attrName("XpBoostEnds")
	if passesAttr and last.Passes ~= now.Passes then
		player:SetAttribute(passesAttr, now.Passes)
	end
	if boughtAttr and last.Bought ~= now.Bought then
		player:SetAttribute(boughtAttr, now.Bought)
	end
	if endsAttr and last.Ends ~= now.Ends then
		player:SetAttribute(endsAttr, now.Ends)
	end
end

function Multipliers.Init(deps)
	deps = type(deps) == "table" and deps or {}
	S.Store = deps.StoreService or S.Store
	S.DS = deps.DataService or S.DS
	if S.Started then
		return
	end
	S.Started = true
	local store = S.Store
	if store and type(store.Changed) == "table" and type(store.Changed.Connect) == "function" then
		store.Changed:Connect(Multipliers.Refresh)
	else
		warn("[Multipliers] StoreService is missing: every multiplier is x1")
	end
	-- the Bought csv needs the loaded profile: refresh when it lands and after a rebase (ProfileRebased also fires when
	-- a provisional profile recovers: DataService's recover -> announceRebase)
	local DS = S.DS
	for _, name in ipairs({ "ProfileLoaded", "ProfileRebased" }) do
		local signal = DS and DS[name]
		if type(signal) == "table" and type(signal.Connect) == "function" then
			signal:Connect(function(player)
				Multipliers.Refresh(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		Multipliers.Refresh(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		S.Last[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		Multipliers.Refresh(player)
	end
end

return Multipliers
