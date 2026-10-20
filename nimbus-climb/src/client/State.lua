-- State: the client's read-only mirror of the player's saved profile (pets, items, stats, perks, the v3
-- Pet Index + tutorial progress and the Phase 2 tycoon data).
--
--   State.Init()                 connects Remotes.ProfileSync and asks the server for a snapshot (safe to call twice)
--   State.Get() -> snapshot      never nil; the snapshot is replaced (never mutated by us) on every ProfileSync,
--                                so a table you hold stays internally consistent. Do not write to it.
--   State.Changed                Util.Signal; Fire(snapshot) after every ProfileSync
--   State.OwnedCount(key)        State.IsEquipped(key)     State.EquippedCount(key)
--   State.ItemCount(itemId)      State.Tokens()  (reads the CloudTokens attribute, falls back to the snapshot)
--   v3 (ARCHITECTURE_V3.md sections 1 + 3):
--   State.IsDiscovered(petId)    true once the pet was ever owned / rolled (an owned pet always counts; a tier key
--                                counts for its base pet, a hybrid key while it is owned)
--   State.IsClaimed(groupId)     true once that Pet Index group reward was claimed
--   Phase 2 (ARCHITECTURE_V3.md "Phase 2 build contract"; pet copies are keys, see shared/PetKeys.lua):
--   State.OwnedCount(key)        copies of a key: "petId" (Normal), "petId@Golden", "petId@Rainbow", "hyb:<uid>"
--   State.Keys() -> {key...}     every owned key in display order (PetKeys.List)
--   State.DefOf(key) -> def|nil  PetKeys.DefOf against the snapshot (tier finishes, merged hybrid looks)
--   State.PetLevel(key) -> level, xp      State.Food() -> {[foodId]=count}      State.FoodCount(foodId)
--   State.Home() -> { Level, Prestige, Stations = {[id]=level}, Garden = {[slot]=key}, Gym = {[slot]=key},
--                     CollectorCash, LegacySlots = n | nil, LegacyPrices = true | nil }
--                                (CollectorCash as of the last sync: the live amount is on the plot; the Phase 4
--                                LegacySlots / LegacyPrices are a veteran's extra garden places / old prices until
--                                their next Prestige, absent for everyone else)
--   State.Cash() / State.Gems()  read the Cash / Gems attributes, fall back to the snapshot
--   State.CashChanged / State.GemsChanged   Util.Signal, Fire(value) when the attribute changes
--
--   Phase 3 (ARCHITECTURE_V3.md "Phase 3 build contract"):
--   State.Teams() -> { Presets = { {key...}, {key...}, {key...} }, Active = 1..3, Slots = 3 | 4 }
--   State.Battle() -> { Trophies, TrialBest, TrialCleared = {[level]=true}, Raids, RaidBestDamage, PvPWins,
--                       PvPLosses, EventPets = {[petId]=true} }
--
--   Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract" section 4):
--   State.PetGrowth(key) -> { Evo = 0..2, Speed, Physique, Ability, Defense = 0..10, Job = { Stat, Ends, Rank, Slot,
--                             From, Paid } | nil }   always a table (zeros for a pet without growth; the server
--                             leaves zero numbers out of the snapshot and they are filled in here). Evo is the stored
--                             evolution stage (pressing EVOLVE), the four numbers are training ranks, Job the running
--                             training job (Ends = server os.time(); display only)
--   State.Ring() -> { Best, Runs }   the Champion Ring record (Best = the highest round won, Runs = finished runs)
--
--   Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" 9.1 / 3.7 / 4.8):
--   State.Dungeon() -> { Best = 0..100, Cleared = {[floor]=true}, Runs, Clears }   (Cleared arrives as a dense array)
--   State.Berries() -> whole berries (reads the Berries attribute, falls back to the snapshot)
--   State.Settings() -> { Music 0..10, Sfx 0..10, Gfx "Auto"|"Low"|"High", Shake, SeenNotes }  (per-key defaults)
--   State.SettingsChanged        Util.Signal; Fire(settings) after a ProfileSync that changed a setting
--   State.PetStage(key) -> 0..2  the stored evolution stage that counts (PetCatalog.EvolutionStage(def, level, Evo))
--   State.BestStage(petId) -> 0..2   the highest stage over the owned keys of that base pet (tier copies too)
--   State.Teams().Slots == 3     always (a fighter and two helpers)
--   Home gains DecorCredit = 1..18 | nil, LegacyMagnet = 1..5 | nil, LegacyMagnetStar = n | nil (the fold)
--
-- Extras (not part of the cross-module contract): State.IsLoaded(), State.Perks(), State.Stats(),
-- State.BerriesChanged (Signal, Fire(berries) when the Berries attribute changes),
-- State.EquippedList(), State.TokensChanged (Signal, Fire(tokens) when the CloudTokens attribute changes),
-- State.DiscoveredCount(petIdList|nil), State.Tutorial() -> { Step, Done, Gifted }, State.Tiers(), State.Hybrids(),
-- State.IsTraining(key) (true while the key has a training Job), State.TrainingKeys() -> {[key] = true},
-- State.PetGrowthMap() -> the whole { [key] = entry } map (read-only).
--
-- The snapshot shape (ARCHITECTURE_V2.md section 1 + ARCHITECTURE_V3.md section 1 + Phase 2):
--   { Tokens, Pets = {[petId]=count}, Equipped = {key,...}, Items = {[itemId]=count},
--     Stats = { Matches, Wins, TokensEarned, Spins, BestTimes = {[diffId]=sec} }, SpotIndex, Perks = {...},
--     Discovered = {[petId]=true}, IndexClaimed = {[groupId]=true}, Tutorial = { Step, Done, Gifted },
--     Cash, Gems, Home = {...}, Food = {[foodId]=count}, Tiers = {[petId]={Golden, Rainbow}},
--     Hybrids = {[uid]={Body, Style, Elements, Name, Rarity, Tier}}, PetLevels = {[key]={Level, Xp}},
--     Teams = {...}, Battle = {...},   (Phase 3; TrialCleared arrives as a dense array of booleans)
--     PetGrowth = {[key]={Evo?, Speed?, Physique?, Ability?, Defense?, Job?}}, Ring = { Best, Runs } }   (Phase 4)
-- Whatever arrives is sanitised here, so UI code can index it without nil/type checks. The server sends Garden /
-- Gym as arrays with "" for empty slots (remotes mangle sparse arrays); they are decoded to {[slot]=key} here.
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local State = {}

State.Changed = Util.Signal()
State.TokensChanged = Util.Signal()
State.CashChanged = Util.Signal()
State.GemsChanged = Util.Signal()
-- Phase 5
State.SettingsChanged = Util.Signal()
State.BerriesChanged = Util.Signal()

local PERK_KEYS = { "MaxHealth", "TokenBonus", "StaminaRegen", "CheckpointHeal" }
local STAT_KEYS = { "Matches", "Wins", "TokensEarned", "Spins" }
local RETRY_DELAYS = { 2, 4, 8, 15 } -- seconds between RequestProfile retries while no snapshot arrived
local MAX_ID_LENGTH = 64 -- ids longer than this are junk
local MAX_TUTORIAL_STEP = 1000
local MAX_SLOT = 64
local TIER_NAMES = { "Golden", "Rainbow" }
local VALID_TIER = { Normal = true, Golden = true, Rainbow = true }

-- shared/PetKeys (resolved on first use; State keeps working without it: keys then count as plain pet ids)
local petKeys = nil
local function getPetKeys()
	if petKeys then
		return petKeys
	end
	local module = Shared:FindFirstChild("PetKeys")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			petKeys = result
		end
	end
	return petKeys
end

local current = nil -- the live snapshot (always a table once the module is loaded)
local loaded = false -- true after the first ProfileSync
local initialised = false
local requestRemote = nil

----------------------------------------------------------------------
-- Sanitising
----------------------------------------------------------------------
local function num(value, default)
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end
	return default
end

local function validId(key)
	return type(key) == "string" and key ~= "" and #key <= MAX_ID_LENGTH
end

-- { [id] = positive integer count } from a possibly messy table.
local function countMap(raw)
	local out = {}
	if type(raw) == "table" then
		for key, value in pairs(raw) do
			if type(key) == "string" and type(value) == "number" and value >= 1 then
				out[key] = math.floor(value)
			end
		end
	end
	return out
end

-- { [id] = true } from a set ({id = true}), a count map ({id = 2}) or a plain list ({"a", "b"}).
local function idSet(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, value in pairs(raw) do
		if validId(key) and (value == true or (type(value) == "number" and value > 0)) then
			out[key] = true
		elseif type(key) == "number" and validId(value) then
			out[value] = true
		end
	end
	return out
end

local function newTutorial()
	return { Step = 1, Done = false, Gifted = false }
end

local function cleanTutorial(raw)
	local t = newTutorial()
	if type(raw) == "table" then
		local step = num(raw.Step, 1)
		if step >= 1 then
			t.Step = math.min(math.floor(step), MAX_TUTORIAL_STEP)
		end
		t.Done = raw.Done == true
		t.Gifted = raw.Gifted == true
	end
	return t
end

local function wholeNumber(value)
	local n = num(value, 0)
	if n < 0 then
		return 0
	end
	return math.floor(n)
end

-- Garden / Gym: an array with "" holes, a map with numeric-string or name keys -> { [slot] = key }
local function slotMap(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, value in pairs(raw) do
		local slot = key
		if type(key) == "string" and string.find(key, "^%d+$") then
			slot = tonumber(key)
		end
		local okSlot = (type(slot) == "number" and slot >= 1 and slot <= MAX_SLOT and slot == math.floor(slot)) or validId(slot)
		if okSlot and validId(value) then
			out[slot] = value
		end
	end
	return out
end

local function newHome()
	return {
		Level = 0, Prestige = 0, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0, LegacySlots = nil, LegacyPrices = nil,
		DecorCredit = nil, LegacyMagnet = nil, LegacyMagnetStar = nil, -- Phase 5 (the fold)
	}
end

local function cleanHome(raw)
	local h = newHome()
	if type(raw) ~= "table" then
		return h
	end
	h.Level = wholeNumber(raw.Level)
	h.Prestige = wholeNumber(raw.Prestige)
	h.Stations = countMap(raw.Stations)
	h.Garden = slotMap(raw.Garden)
	h.Gym = slotMap(raw.Gym)
	h.CollectorCash = wholeNumber(raw.CollectorCash)
	-- Phase 4 (veterans only): a whole number of garden places >= 1, or nil; true, or nil
	local legacy = wholeNumber(raw.LegacySlots)
	if legacy >= 1 then
		h.LegacySlots = math.min(legacy, MAX_SLOT)
	end
	if raw.LegacyPrices == true then
		h.LegacyPrices = true
	end
	-- Phase 5 (the fold): DecorCredit 1..18 or nil; LegacyMagnet 1..5 with the Prestige it was folded at, or nil
	local credit = wholeNumber(raw.DecorCredit)
	if credit >= 1 then
		h.DecorCredit = math.min(credit, 18)
	end
	local magnet = wholeNumber(raw.LegacyMagnet)
	if magnet >= 1 then
		h.LegacyMagnet = math.min(magnet, 5)
		h.LegacyMagnetStar = wholeNumber(raw.LegacyMagnetStar)
	end
	return h
end

-- Phase 4: pet growth per key. The server leaves zero numbers out of the snapshot: they are filled in here, so every
-- entry has Evo and the four ranks.
local GROWTH_STATS = { "Speed", "Physique", "Ability", "Defense" }
local GROWTH_STAT_SET = { Speed = true, Physique = true, Ability = true, Defense = true }
local MAX_EVO = 2
local MAX_RANK = 10

local function newGrowth()
	local e = { Evo = 0 }
	for _, stat in ipairs(GROWTH_STATS) do
		e[stat] = 0
	end
	return e
end

local function cleanJob(raw)
	if type(raw) ~= "table" or not GROWTH_STAT_SET[raw.Stat] then
		return nil
	end
	local job = { Stat = raw.Stat, Ends = wholeNumber(raw.Ends), Rank = math.min(wholeNumber(raw.Rank), MAX_RANK), Slot = wholeNumber(raw.Slot), Paid = wholeNumber(raw.Paid) }
	if type(raw.From) == "string" and raw.From ~= "" then
		job.From = raw.From
	end
	return job
end

local function cleanGrowthEntry(raw)
	local e = newGrowth()
	if type(raw) ~= "table" then
		return e
	end
	e.Evo = math.min(wholeNumber(raw.Evo), MAX_EVO)
	for _, stat in ipairs(GROWTH_STATS) do
		e[stat] = math.min(wholeNumber(raw[stat]), MAX_RANK)
	end
	e.Job = cleanJob(raw.Job)
	return e
end

local function cleanGrowth(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, entry in pairs(raw) do
		if validId(key) and type(entry) == "table" then
			out[key] = cleanGrowthEntry(entry)
		end
	end
	return out
end

local function newRing()
	return { Best = 0, Runs = 0 }
end

local function cleanRing(raw)
	local r = newRing()
	if type(raw) == "table" then
		r.Best = wholeNumber(raw.Best)
		r.Runs = wholeNumber(raw.Runs)
	end
	return r
end

-- Phase 5: the Dungeon record. Cleared arrives as a dense boolean array (or a set) -> { [floor] = true }.
local MAX_FLOOR = 100

local function newDungeon()
	return { Best = 0, Cleared = {}, Runs = 0, Clears = 0 }
end

local function cleanDungeon(raw)
	local d = newDungeon()
	if type(raw) ~= "table" then
		return d
	end
	d.Best = math.min(wholeNumber(raw.Best), MAX_FLOOR)
	d.Runs = wholeNumber(raw.Runs)
	d.Clears = wholeNumber(raw.Clears)
	if type(raw.Cleared) == "table" then
		for key, value in pairs(raw.Cleared) do
			local floor = tonumber(key)
			if value == true and floor and floor >= 1 and floor <= MAX_FLOOR and floor == math.floor(floor) then
				d.Cleared[floor] = true
				if floor > d.Best then
					d.Best = floor
				end
			end
		end
	end
	return d
end

-- Phase 5: the settings with per-key defaults (7.2); a malformed value falls back to its default.
local SETTING_KEYS = { "Music", "Sfx", "Gfx", "Shake", "SeenNotes", "MouseLock" }
local SETTING_DEFAULTS = { Music = 6, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 0, MouseLock = false }
local GFX_LEVELS = { Auto = true, Low = true, High = true }

local function newSettings()
	local s = {}
	for _, key in ipairs(SETTING_KEYS) do
		s[key] = SETTING_DEFAULTS[key]
	end
	return s
end

local function cleanSettings(raw)
	local s = newSettings()
	if type(raw) ~= "table" then
		return s
	end
	for _, key in ipairs({ "Music", "Sfx" }) do
		local v = raw[key]
		if type(v) == "number" and v == v and v >= 0 and v <= 10 and v == math.floor(v) then
			s[key] = v
		end
	end
	if type(raw.Gfx) == "string" and GFX_LEVELS[raw.Gfx] then
		s.Gfx = raw.Gfx
	end
	if type(raw.Shake) == "boolean" then
		s.Shake = raw.Shake
	end
	if type(raw.MouseLock) == "boolean" then
		s.MouseLock = raw.MouseLock
	end
	local notes = raw.SeenNotes
	if type(notes) == "number" and notes == notes and notes >= 0 and notes <= 1000 and notes == math.floor(notes) then
		s.SeenNotes = notes
	end
	return s
end

local function settingsEqual(a, b)
	for _, key in ipairs(SETTING_KEYS) do
		if a[key] ~= b[key] then
			return false
		end
	end
	return true
end

local function cleanTiers(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for petId, entry in pairs(raw) do
		if validId(petId) and type(entry) == "table" then
			local clean = nil
			for _, tier in ipairs(TIER_NAMES) do
				local n = wholeNumber(entry[tier])
				if n > 0 then
					clean = clean or {}
					clean[tier] = n
				end
			end
			if clean then
				out[petId] = clean
			end
		end
	end
	return out
end

local function cleanHybrids(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for uid, rec in pairs(raw) do
		if validId(uid) and type(rec) == "table" and validId(rec.Body) and validId(rec.Style) then
			local clean = { Body = rec.Body, Style = rec.Style, Elements = {}, Tier = VALID_TIER[rec.Tier] and rec.Tier or "Normal" }
			if type(rec.Elements) == "table" then
				for _, e in ipairs(rec.Elements) do
					if validId(e) then
						clean.Elements[#clean.Elements + 1] = e
					end
				end
			end
			if type(rec.Name) == "string" and rec.Name ~= "" then
				clean.Name = rec.Name
			end
			if validId(rec.Rarity) then
				clean.Rarity = rec.Rarity
			end
			if type(rec.Seed) == "number" and rec.Seed == rec.Seed then
				clean.Seed = rec.Seed
			end
			out[uid] = clean
		end
	end
	return out
end

local function cleanPetLevels(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, entry in pairs(raw) do
		if validId(key) then
			local level, xp = 1, 0
			if type(entry) == "table" then
				level, xp = num(entry.Level, 1), num(entry.Xp, 0)
			elseif type(entry) == "number" then
				level = num(entry, 1)
			end
			out[key] = { Level = math.max(1, math.floor(level)), Xp = math.max(0, xp) }
		end
	end
	return out
end

-- Phase 3: battle teams. Presets are dense key lists (the server compacts them); Slots is 3, or 4 after Prestige 1.
local TEAM_PRESETS = 3

local function newTeams()
	local presets = {}
	for i = 1, TEAM_PRESETS do
		presets[i] = {}
	end
	return { Presets = presets, Active = 1, Slots = 3 }
end

local function cleanTeams(raw)
	local t = newTeams()
	if type(raw) ~= "table" then
		return t
	end
	-- Phase 5 (4.8): Slots is 3 always (slot 1 = the fighter); a longer preset from an old snapshot keeps its first 3
	if type(raw.Presets) == "table" then
		for i = 1, TEAM_PRESETS do
			local list = raw.Presets[i]
			if type(list) == "table" then
				local seen = {}
				for _, key in ipairs(list) do
					if validId(key) and not seen[key] and #t.Presets[i] < t.Slots then
						seen[key] = true
						table.insert(t.Presets[i], key)
					end
				end
			end
		end
	end
	local active = num(raw.Active, 1)
	if active >= 1 and active <= TEAM_PRESETS then
		t.Active = math.floor(active)
	end
	return t
end

-- Phase 3: the battle record. TrialCleared becomes { [level] = true } (the server sends a dense boolean array).
local function newBattle()
	return {
		Trophies = 0,
		TrialBest = 0,
		TrialCleared = {},
		Raids = 0,
		RaidBestDamage = 0,
		PvPWins = 0,
		PvPLosses = 0,
		EventPets = {},
	}
end

local function cleanBattle(raw)
	local b = newBattle()
	if type(raw) ~= "table" then
		return b
	end
	b.Trophies = wholeNumber(raw.Trophies)
	b.TrialBest = wholeNumber(raw.TrialBest)
	b.Raids = wholeNumber(raw.Raids)
	b.RaidBestDamage = wholeNumber(raw.RaidBestDamage)
	b.PvPWins = wholeNumber(raw.PvPWins)
	b.PvPLosses = wholeNumber(raw.PvPLosses)
	if type(raw.TrialCleared) == "table" then
		for level, value in pairs(raw.TrialCleared) do
			local n = level
			if type(level) == "string" then
				n = tonumber(level)
			end
			if type(n) == "number" and n >= 1 and n == math.floor(n) and value == true then
				b.TrialCleared[n] = true
				if n > b.TrialBest then
					b.TrialBest = n
				end
			end
		end
	end
	b.EventPets = idSet(raw.EventPets)
	return b
end

local function newSnapshot()
	local perks = {}
	for _, key in ipairs(PERK_KEYS) do
		perks[key] = 0
	end
	local stats = { BestTimes = {} }
	for _, key in ipairs(STAT_KEYS) do
		stats[key] = 0
	end
	return {
		Tokens = 0,
		Pets = {},
		Equipped = {},
		Items = {},
		Stats = stats,
		SpotIndex = nil,
		Perks = perks,
		-- v3
		Discovered = {},
		IndexClaimed = {},
		Tutorial = newTutorial(),
		-- Phase 2
		Cash = 0,
		Gems = 0,
		Home = newHome(),
		Food = {},
		Tiers = {},
		Hybrids = {},
		PetLevels = {},
		-- Phase 3
		Teams = newTeams(),
		Battle = newBattle(),
		-- Phase 4
		PetGrowth = {},
		Ring = newRing(),
		-- Phase 5
		Dungeon = newDungeon(),
		Berries = 0,
		Settings = newSettings(),
	}
end

local function normalise(raw)
	local snap = newSnapshot()
	if type(raw) ~= "table" then
		return snap
	end
	snap.Tokens = math.max(0, math.floor(num(raw.Tokens, 0)))
	snap.Pets = countMap(raw.Pets)
	snap.Items = countMap(raw.Items)
	if type(raw.Equipped) == "table" then
		for _, id in ipairs(raw.Equipped) do
			if type(id) == "string" then
				table.insert(snap.Equipped, id)
			end
		end
	end
	if type(raw.Stats) == "table" then
		for _, key in ipairs(STAT_KEYS) do
			snap.Stats[key] = num(raw.Stats[key], 0)
		end
		if type(raw.Stats.BestTimes) == "table" then
			for id, seconds in pairs(raw.Stats.BestTimes) do
				if type(id) == "string" and type(seconds) == "number" then
					snap.Stats.BestTimes[id] = seconds
				end
			end
		end
	end
	if type(raw.Perks) == "table" then
		for _, key in ipairs(PERK_KEYS) do
			snap.Perks[key] = num(raw.Perks[key], 0)
		end
	end
	snap.SpotIndex = num(raw.SpotIndex, nil)

	-- v3: every owned pet counts as discovered, even when the server's set lags behind
	snap.Discovered = idSet(raw.Discovered)
	for id in pairs(snap.Pets) do
		if validId(id) then
			snap.Discovered[id] = true
		end
	end
	snap.IndexClaimed = idSet(raw.IndexClaimed)
	snap.Tutorial = cleanTutorial(raw.Tutorial)

	-- Phase 2
	snap.Cash = wholeNumber(raw.Cash)
	snap.Gems = wholeNumber(raw.Gems)
	snap.Home = cleanHome(raw.Home)
	snap.Food = countMap(raw.Food)
	snap.Tiers = cleanTiers(raw.Tiers)
	snap.Hybrids = cleanHybrids(raw.Hybrids)
	snap.PetLevels = cleanPetLevels(raw.PetLevels)
	-- Phase 3
	snap.Teams = cleanTeams(raw.Teams)
	snap.Battle = cleanBattle(raw.Battle)
	-- Phase 4
	snap.PetGrowth = cleanGrowth(raw.PetGrowth)
	snap.Ring = cleanRing(raw.Ring)
	-- Phase 5
	snap.Dungeon = cleanDungeon(raw.Dungeon)
	snap.Berries = wholeNumber(raw.Berries)
	snap.Settings = cleanSettings(raw.Settings)
	for id in pairs(snap.Tiers) do
		snap.Discovered[id] = true -- a tier copy counts for its base pet
	end
	return snap
end

current = newSnapshot()

----------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------
local function attributeTokens()
	local player = Players.LocalPlayer
	if not player then
		return nil
	end
	local value = player:GetAttribute(Config.Attr.Tokens)
	if type(value) == "number" then
		return value
	end
	return nil
end

function State.Get()
	-- keep the token field in step with the replicated attribute (the attribute changes before the sync)
	local tokens = attributeTokens()
	if tokens ~= nil and current.Tokens ~= tokens then
		current.Tokens = tokens
	end
	return current
end

function State.IsLoaded()
	return loaded
end

-- Copies of a key ("petId" counts the Normal copies, "petId@Golden" the Golden ones, "hyb:<uid>" 0 or 1).
function State.OwnedCount(key)
	local keys = getPetKeys()
	if keys and type(keys.Count) == "function" then
		local ok, n = pcall(keys.Count, current, key)
		if ok and type(n) == "number" then
			return n
		end
		return 0
	end
	return current.Pets[key] or 0
end

State.Count = State.OwnedCount

function State.EquippedCount(petId)
	local n = 0
	for _, id in ipairs(current.Equipped) do
		if id == petId then
			n = n + 1
		end
	end
	return n
end

function State.IsEquipped(petId)
	return State.EquippedCount(petId) > 0
end

function State.ItemCount(itemId)
	return current.Items[itemId] or 0
end

function State.Tokens()
	local tokens = attributeTokens()
	if tokens ~= nil then
		return tokens
	end
	return current.Tokens or 0
end

function State.Perks()
	return current.Perks
end

function State.Stats()
	return current.Stats
end

-- A copy, so callers may sort / edit it freely.
function State.EquippedList()
	local out = {}
	for i, id in ipairs(current.Equipped) do
		out[i] = id
	end
	return out
end

-- v3: Pet Index (base pets). A tier key counts for its base pet; a hybrid key counts while it is owned.
function State.IsDiscovered(petId)
	if type(petId) ~= "string" then
		return false
	end
	if current.Discovered[petId] == true or (current.Pets[petId] or 0) > 0 or current.Tiers[petId] ~= nil then
		return true
	end
	local keys = getPetKeys()
	local parsed = nil
	if keys and type(keys.Parse) == "function" then
		local ok, result = pcall(keys.Parse, petId)
		parsed = ok and result or nil
	end
	if not parsed or parsed.Key == nil or (parsed.PetId == petId and parsed.HybridId == nil) then
		return false
	end
	if parsed.HybridId then
		return State.OwnedCount(petId) > 0
	end
	return State.IsDiscovered(parsed.PetId)
end

function State.IsClaimed(groupId)
	if type(groupId) ~= "string" then
		return false
	end
	return current.IndexClaimed[groupId] == true
end

-- How many of `petIds` (a list of ids or of PetDefs) are discovered; without a list, every discovered id.
function State.DiscoveredCount(petIds)
	local n = 0
	if type(petIds) == "table" then
		for _, entry in ipairs(petIds) do
			local id = entry
			if type(entry) == "table" then
				id = entry.Id
			end
			if State.IsDiscovered(id) then
				n = n + 1
			end
		end
		return n
	end
	for _ in pairs(current.Discovered) do
		n = n + 1
	end
	return n
end

-- v3: tutorial progress as saved in the profile (TutorialState carries the live step text).
function State.Tutorial()
	return current.Tutorial
end

----------------------------------------------------------------------
-- Phase 2: pet keys, levels, food, home, Cash / Gems
----------------------------------------------------------------------
-- Every owned key in display order (catalog order, Normal / Golden / Rainbow, hybrids last).
function State.Keys()
	local keys = getPetKeys()
	if keys and type(keys.List) == "function" then
		local ok, list = pcall(keys.List, current)
		if ok and type(list) == "table" then
			return list
		end
	end
	local out = {}
	for id in pairs(current.Pets) do
		out[#out + 1] = id
	end
	table.sort(out)
	return out
end

-- The definition of a key (catalog def, tier def with Look.Finish, merged hybrid def), or nil. Read-only.
function State.DefOf(key)
	local keys = getPetKeys()
	if keys and type(keys.DefOf) == "function" then
		local ok, def = pcall(keys.DefOf, key, current)
		if ok then
			return def
		end
	end
	return nil
end

-- level, xp of a pet key (1, 0 when it never gained XP)
function State.PetLevel(key)
	local entry = type(key) == "string" and current.PetLevels[key]
	if entry then
		return entry.Level, entry.Xp
	end
	return 1, 0
end

function State.Food()
	return current.Food
end

function State.FoodCount(foodId)
	return current.Food[foodId] or 0
end

function State.Home()
	return current.Home
end

function State.Tiers()
	return current.Tiers
end

function State.Hybrids()
	return current.Hybrids
end

-- Phase 3
function State.Teams()
	return current.Teams
end

function State.Battle()
	return current.Battle
end

-- Phase 4: one pet's growth { Evo, Speed, Physique, Ability, Defense, Job | nil } (always a table; zeros for a pet
-- without growth). Read-only: the entry belongs to the snapshot.
function State.PetGrowth(key)
	local entry = type(key) == "string" and current.PetGrowth[key]
	if entry then
		return entry
	end
	return newGrowth()
end

-- The whole growth map { [key] = entry } (read-only).
function State.PetGrowthMap()
	return current.PetGrowth
end

-- true while that key has a running training Job (it cannot be equipped, placed, fused or fielded meanwhile).
function State.IsTraining(key)
	local entry = type(key) == "string" and current.PetGrowth[key]
	return entry ~= nil and entry.Job ~= nil
end

-- { [key] = true } of every pet in training (a fresh table).
function State.TrainingKeys()
	local out = {}
	for key, entry in pairs(current.PetGrowth) do
		if entry.Job ~= nil then
			out[key] = true
		end
	end
	return out
end

-- The Champion Ring record { Best, Runs }.
function State.Ring()
	return current.Ring
end

-- Phase 5: the Dungeon record { Best, Cleared = {[floor]=true}, Runs, Clears } (read-only).
function State.Dungeon()
	return current.Dungeon
end

-- Phase 5: the settings { Music, Sfx, Gfx, Shake, SeenNotes } (read-only; every key present).
function State.Settings()
	return current.Settings
end

-- Phase 5 (3.7): the evolution stage that counts for an owned key: PetCatalog.EvolutionStage(def, level, Evo) with
-- the stored stage (hybrids through PetKeys.DefOf). 0 for an unknown key or without the catalog.
local petCatalog = nil
local function getPetCatalog()
	if petCatalog == nil then
		petCatalog = false
		local module = Shared:FindFirstChild("PetCatalog")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				petCatalog = result
			end
		end
	end
	return petCatalog or nil
end

function State.PetStage(key)
	if type(key) ~= "string" then
		return 0
	end
	local entry = current.PetGrowth[key]
	local stored = entry and entry.Evo or 0
	if stored < 1 then
		return 0
	end
	local catalog = getPetCatalog()
	local def = State.DefOf(key)
	if catalog and type(catalog.EvolutionStage) == "function" and def then
		local level = State.PetLevel(key)
		local ok, stage = pcall(catalog.EvolutionStage, def, level, stored)
		if ok and type(stage) == "number" then
			return stage
		end
	end
	return math.min(stored, MAX_EVO)
end

-- Phase 5 (3.7): the highest stage over the owned keys of a base pet id (its Normal / Golden / Rainbow copies).
function State.BestStage(petId)
	if type(petId) ~= "string" then
		return 0
	end
	local best = 0
	for key, entry in pairs(current.PetGrowth) do
		if entry.Evo and entry.Evo > best then
			local base = string.match(key, "^(.-)@[%w]+$") or key
			if base == petId and State.OwnedCount(key) > 0 then
				local stage = State.PetStage(key)
				if stage > best then
					best = stage
				end
			end
		end
	end
	return best
end

local function attributeNumber(name)
	local player = Players.LocalPlayer
	if not player or not name then
		return nil
	end
	local value = player:GetAttribute(name)
	if type(value) == "number" then
		return value
	end
	return nil
end

function State.Cash()
	local cash = attributeNumber(Config.Attr.Cash)
	if cash ~= nil then
		return cash
	end
	return current.Cash or 0
end

function State.Gems()
	local gems = attributeNumber(Config.Attr.Gems)
	if gems ~= nil then
		return gems
	end
	return current.Gems or 0
end

-- Phase 5: whole berries (the Berries attribute is written by DataService <= 2/s; the snapshot is the fallback)
function State.Berries()
	local berries = attributeNumber(Config.Attr.Berries)
	if berries ~= nil then
		return math.max(0, math.floor(berries))
	end
	return current.Berries or 0
end

----------------------------------------------------------------------
-- Server traffic
----------------------------------------------------------------------
local function apply(raw)
	if type(raw) ~= "table" then
		return
	end
	local previous = current
	current = normalise(raw)
	loaded = true
	State.Changed:Fire(State.Get())
	-- Phase 5: a setting changed on the server (another device, a merge) -> SettingsChanged(settings)
	if not settingsEqual(previous.Settings, current.Settings) then
		State.SettingsChanged:Fire(current.Settings)
	end
end

local function request()
	if requestRemote then
		pcall(function()
			requestRemote:FireServer()
		end)
	end
end

function State.Init()
	if initialised then
		return
	end
	initialised = true

	local okSync, syncRemote = pcall(Remotes.Get, "ProfileSync")
	if okSync and syncRemote then
		syncRemote.OnClientEvent:Connect(apply)
	else
		warn("[State] ProfileSync remote is unavailable: " .. tostring(syncRemote))
	end
	local okReq, req = pcall(Remotes.Get, "RequestProfile")
	if okReq and req then
		requestRemote = req
	else
		warn("[State] RequestProfile remote is unavailable: " .. tostring(req))
	end

	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal(Config.Attr.Tokens):Connect(function()
			State.TokensChanged:Fire(State.Tokens())
		end)
		if Config.Attr.Cash then
			player:GetAttributeChangedSignal(Config.Attr.Cash):Connect(function()
				State.CashChanged:Fire(State.Cash())
			end)
		end
		if Config.Attr.Gems then
			player:GetAttributeChangedSignal(Config.Attr.Gems):Connect(function()
				State.GemsChanged:Fire(State.Gems())
			end)
		end
		if Config.Attr.Berries then
			player:GetAttributeChangedSignal(Config.Attr.Berries):Connect(function()
				State.BerriesChanged:Fire(State.Berries())
			end)
		end
	end

	request()
	-- the first sync may have been sent before we were listening: ask again until one arrives
	task.spawn(function()
		for _, seconds in ipairs(RETRY_DELAYS) do
			task.wait(seconds)
			if loaded then
				return
			end
			request()
		end
	end)
end

return State
