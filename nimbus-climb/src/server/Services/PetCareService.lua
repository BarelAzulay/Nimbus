-- PetCareService (Phase 4, care): the Food Machine, EVOLVE and the Training Place (ARCHITECTURE_V3.md "Phase 4 build
-- contract" 3.4-3.7, 5.1-5.4). The Phase 2 Kitchen (cooking queue) and Gym (passive XP) that lived in this file are
-- gone: "Cook" / "GymSet" requests answer one toast that says where the feature went.
--
-- * Food Machine (station id Kitchen): Feed(key, opts) with opts nil = one machine feed, { Food = "Snack" | "Meal" |
--   "Feast" } = one leftover from the old Kitchen (free), { Count = 1..10 } = "Level up" (several feeds in ONE
--   request; a plain string in `b` is read as Food for old clients). One machine feed gives
--   TycoonCatalog.FeedXp(level, machineLevel) XP (25-50% of the bar) for TycoonCatalog.FeedPrice(def, level) Cash; a
--   batch prices every feed at the level it is eaten at (the sum is recomputed here feed by feed, X7). Leftovers are
--   fed first and free (the biggest one that does not overshoot the cap, else the smallest), so a request only needs
--   the machine when a paid feed happens. Refusals come before any Cash moves: no Food Machine ("Build the Food
--   Machine at home first"), the cap (PetCatalog.LevelCap: 100 for every rarity), not owned, a provisional save, a
--   key in a running battle (BattleService.KeysInBattle). The foods, the Cash and the XP write are one non-yielding
--   step; everything comes back when the XP write gives 0. ONE toast per XP grant (a feed, a batch, a fight), never
--   one per level: a level-up toast shows the new stats and "Ready to evolve!" at 20 / 50 (PetCatalog.CanEvolve).
-- * EVOLVE: Evolve(key): owned, loaded and not provisional, level >= the next threshold (PetCatalog.EvolutionLevels
--   20 / 50), stage < PetCatalog.MaxEvolution(def) (Common / Uncommon / Rare once, Epic and rarer twice), not in a
--   running battle or ring run. Writes the stored stage (DataService.SetEvolution, only up), fires Evolved, toasts
--   "<Pet> evolved! +25% to everything", refreshes the EquippedInfo attribute (PetService.Refresh) and sends
--   OpenPanel("Evolve", { Key, Stage }) to that client only. Free. A training pet may evolve.
-- * Training Place (station id Gym): Train(key, stat) with stat Speed | Physique | Ability | Defense: needs the
--   station (TycoonCatalog.TrainingSlots(home) >= 1) and a free mat, an owned pet that is not training, a rank below
--   10, no running battle, TycoonCatalog.TrainCost(def, rank) Cash; rank r takes TycoonCatalog.TrainSeconds(r)
--   (r minutes). The Cash and the job (PetGrowth[key].Job = { Stat, Ends = os.time() + seconds, Rank = rank + 1, Slot =
--   mat, From, Paid }, DataService.MutateGrowth) are one step; a failed job write gives the Cash back. Starting takes
--   the pet off the player (PetService.UnequipKey, every copy) and out of the Garden (TycoonService.GardenSet) by
--   itself and remembers where it was in Job.From ("Garden:<slot>" wins over "Follow", else "Free"). The lock is
--   DataService.TrainingKeys (PetService.Equip, GardenSet, Fusion, teams and the ring read it). Completion is decided
--   from os.time() >= Job.Ends by the 1 s tick and on profile load / rebase (provisional saves wait): the rank is a
--   TARGET value (two servers completing one job give one rank), the pet goes back by itself ("Follow" -> re-equipped
--   when a slot is free; "Garden:n" -> that place when open and empty, else the first free open place, else it stays
--   in the list), TrainingDone fires. TrainStop(key) removes the job and refunds Job.Paid in the same step (a job
--   that is already due finishes instead). Running jobs survive a Prestige. Toasts: "Rocky started Physique training
--   (4:00)", "Rocky finished Physique training: Rank 3!", "Training done while you were away! ..." on load.
-- * Home.Gym is retired: on every home load (ProfileLoaded / ProfileRebased, or the first readable tick) the old Gym
--   slots are emptied (old Gym pets come back to the list) with one toast per session, also when DataService's
--   one-time Phase 4 migration emptied them (DataService.MigratedNow(player, "P4").GymPets).
-- * Prompts (owner only, HomeFx hides them from visitors): FeedPrompt "Feed pets" on the Food Machine's Hopper part
--   (its biggest part while HomeBuilder has no Hopper yet) -> OpenPanel("Pets", { Action = "Feed" }); TrainPrompt
--   "Train pets" on Station_Gym -> OpenPanel("Train"). Rebuilt when the station is rebuilt (the CareSig attribute
--   carries a "p4:" marker so stale Kitchen prompts of a Phase 3 server never survive).
-- * Replication: the plot folder attribute TrainingPets = "1=cat:Physique:1760000000;2=fox@Golden:Speed:1760000420"
--   (mat=key:stat:Ends, written only on change; a hybrid key holds ":" itself, so readers split from the right) and
--   HomeBuilder.SetTraining(spotInfo, { [mat] = { Key, Stat, Ends } }) when HomeBuilder has such a function. Levels,
--   growth and food reach the owner through ProfileSync (DataService).
-- * Remote PetCare(action, a, b): "Feed" (key, opts), "Evolve" (key), "Train" (key, stat), "TrainStop" (key); "Cook" /
--   "GymSet" are retired (one toast). Types, lengths, ranges and NaN are checked; every action has a cooldown plus a
--   shared per-player burst budget; refusals answer with a side toast (repeated texts are throttled). Nothing here
--   moves parts (Replication rule).
--
-- Public API (the contract): Init(deps)   deps = { DataService, PetService, TycoonService, BattleService }
--   Feed(player, key, opts) -> ok, { Xp, Levels, Level, Cap, Paid, Free, Count } | reason
--   Evolve(player, key) -> ok, stage | reason
--   Train(player, key, stat) -> ok, { Rank, Ends, Cost, Slot, From } | reason
--   TrainStop(player, key) -> ok, refund | reason
--   GrantXp(player, key, xp, source) -> xpGiven, levelsGained, reason   (cap-aware XP for other services, one toast)
--   LevelCap(player, key) -> n | nil          ClearSessions(player) -> true   (developer reset)
--   Signals Fed(player, key, foodId, levelsGained)  (foodId "Machine" for machine food), LevelUp(player, key, level,
--   source), Evolved(player, key, stage), TrainingStarted(player, key, stat), TrainingDone(player, key, stat, rank)
--
-- Every Phase 4 helper lives in the table `Care` (Lua's 200-local limit). Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local PetCareService = {}
PetCareService.Fed = Util.Signal() -- Fire(player, key, foodId, levelsGained)  foodId "Machine" | "Snack" | "Meal" | "Feast"
PetCareService.LevelUp = Util.Signal() -- Fire(player, key, newLevel, source)  source "Feed" | "Trial" | "Ring" | GrantXp's
PetCareService.Evolved = Util.Signal() -- Fire(player, key, stage)
PetCareService.TrainingStarted = Util.Signal() -- Fire(player, key, stat)
PetCareService.TrainingDone = Util.Signal() -- Fire(player, key, stat, rank)

local TICK = 1 -- seconds between training ticks (completions, prompts, the TrainingPets attribute)
local FEED_COOLDOWN = 0.1
local EVOLVE_COOLDOWN = 1
local TRAIN_COOLDOWN = 0.25
local PROMPT_COOLDOWN = 0.35
local BURST_SIZE = 12 -- PetCare requests a player may send at once...
local BURST_REFILL = 6 -- ...refilled at this many per second
local TOAST_GAP = 1.5 -- the same refusal text is not repeated within this many seconds
local LOAD_TOAST_DELAY = 3 -- seconds after a player's session starts before the load toasts show (the client is ready)
local MAX_TOAST_CHARS = 90 -- NotifyController shows up to 90 characters
local MAX_NAME_CHARS = 28 -- "Rainbow Starlight Unicorn" fits; the longest toast stays under 90 characters
local MAX_ACTION_LENGTH = 16
local MAX_ID_LENGTH = 48
local MAX_STAT_LENGTH = 24
local MAX_FEEDS = 10 -- feeds in one "Level up" request
local MAX_TRAIN_SLOTS = 5 -- Training Place mats (DataService P4.MAX_JOB_SLOT)
local FALLBACK_MAX_RANK = 10
local PROMPT_RANGE = 10
local PROMPT_HOLD = 0.3
local FALLBACK_LEVEL_CAPS = { Common = 100, Uncommon = 100, Rare = 100, Epic = 100, Legendary = 100, Mythic = 100, Secret = 100 }
local FALLBACK_MAX_LEVEL = 100
local PROMPT_KEYS = { Keyboard = Enum.KeyCode.E, Gamepad = Enum.KeyCode.ButtonX }
local ATTR_TRAINING = "TrainingPets"
local ATTR_IN_BATTLE = Config.Attr.InBattle or "InBattle"
local CARE_SIG = "CareSig" -- attribute on a station model: which prompts this service built on it
local CARE_MARK = "CareMade" -- attribute on every prompt this service made
local SIG_PREFIX = "p4:" -- stale Phase 3 Kitchen prompts (sig "<level>:<userId>") never match a Phase 4 signature
local LOADING = "Your save is still loading, try again in a moment"
local STATS = { "Speed", "Physique", "Ability", "Defense" }
local STAT_LABELS = { Speed = "Attack Speed", Physique = "Physique", Ability = "Ability", Defense = "Defense" }
local STAT_BY_NAME = { speed = "Speed", attackspeed = "Speed", physique = "Physique", ability = "Ability", defense = "Defense", defence = "Defense" }

local initialized = false
local running = false
local dataService = nil
local petService = nil
local tycoonService = nil
local battleService = nil
local catalog = nil -- TycoonCatalog
local petKeys = nil -- PetKeys (optional)
local petCatalog = nil -- PetCatalog (optional)
local homeBuilder = nil -- HomeBuilder (optional: GetStation, SetTraining)
local notifyRemote = nil
local openPanelRemote = nil

local Care = {} -- every Phase 4 helper (see the header)
local sessions = {} -- [Player] = { At, Pending = { { Text, Kind, Seconds }... }, Shown = { Folder, Info, Text } | nil, GymChecked, GymToast, MigrationSeen }
local cooldowns = {} -- [Player] = { [key] = os.clock() }
local budgets = {} -- [Player] = { Tokens, At }
local toastAt = {} -- [Player] = { [text] = os.clock() }
local departed = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent ~= nil and not departed[player]
end

local function requireModule(container, name)
	local module = container and container:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	warn("[PetCareService] could not load " .. name .. ": " .. tostring(result))
	return nil
end

-- cuts a text to n characters without splitting a UTF-8 character
local function clip(text, n)
	text = tostring(text)
	if #text <= n then
		return text
	end
	local cut = string.sub(text, 1, n - 3)
	cut = string.gsub(cut, "[\192-\255][\128-\191]*$", "")
	return cut .. "..."
end

local function remote(name)
	local ok, r = pcall(Remotes.Get, name)
	if ok then
		return r
	end
	return nil
end

local function notify(player, text, kind, seconds)
	if not isPlayer(player) or type(text) ~= "string" or text == "" then
		return
	end
	notifyRemote = notifyRemote or remote("Notify")
	if notifyRemote then
		pcall(function()
			notifyRemote:FireClient(player, clip(text, MAX_TOAST_CHARS), kind or "info", seconds or 3)
		end)
	end
end

-- A refusal toast; the same text is not repeated within TOAST_GAP (spam clicks stay quiet).
local function toastOnce(player, text, kind)
	if type(text) ~= "string" or text == "" then
		return
	end
	local map = toastAt[player]
	if not map then
		map = {}
		toastAt[player] = map
	end
	local now = os.clock()
	local last = map[text]
	if last and now - last < TOAST_GAP then
		return
	end
	map[text] = now
	notify(player, text, kind or "bad", 3)
end

-- Per player per key cooldown.
local function cooldown(player, key, seconds)
	local map = cooldowns[player]
	if not map then
		map = {}
		cooldowns[player] = map
	end
	local now = os.clock()
	local last = map[key]
	if last and now - last < seconds then
		return false
	end
	map[key] = now
	return true
end

-- Per player burst budget shared by every PetCare request and care prompt.
local function spend(player)
	local now = os.clock()
	local b = budgets[player]
	if not b then
		b = { Tokens = BURST_SIZE, At = now }
		budgets[player] = b
	end
	b.Tokens = math.min(BURST_SIZE, b.Tokens + (now - b.At) * BURST_REFILL)
	b.At = now
	if b.Tokens < 1 then
		return false
	end
	b.Tokens = b.Tokens - 1
	return true
end

local function setAttr(inst, name, value)
	pcall(function()
		if inst:GetAttribute(name) ~= value then
			inst:SetAttribute(name, value)
		end
	end)
end

-- "Snack" -> "Snacks" (n ~= 1)
local function plural(name, n)
	name = tostring(name)
	if n == 1 then
		return name
	end
	return name .. "s"
end

-- 1234 -> "1.2K" (stat numbers in toasts)
local function compact(n)
	n = tonumber(n) or 0
	if not isFinite(n) then
		return "0"
	end
	local a = math.abs(n)
	local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, u in ipairs(units) do
		if a >= u[1] then
			local x = n / u[1]
			local s
			if math.abs(x) >= 100 then
				s = string.format("%d", math.floor(x))
			else
				s = string.format("%.1f", math.floor(x * 10) / 10)
				s = string.gsub(s, "%.0$", "")
			end
			return s .. u[2]
		end
	end
	return tostring(math.floor(n + 0.5))
end

----------------------------------------------------------------------
-- Data access (DataService; every call guarded)
----------------------------------------------------------------------

local function dsCall(fnName, ...)
	if not dataService or type(dataService[fnName]) ~= "function" then
		return false, nil, nil
	end
	local ok, a, b = pcall(dataService[fnName], ...)
	if not ok then
		warn("[PetCareService] DataService." .. fnName .. " failed: " .. tostring(a))
		return false, nil, nil
	end
	return true, a, b
end

local function getProfile(player)
	local ok, profile = dsCall("GetProfile", player)
	if ok and type(profile) == "table" then
		return profile
	end
	return nil
end

local function getHome(player)
	local ok, home = dsCall("GetHome", player)
	if ok and type(home) == "table" then
		return home
	end
	return nil
end

-- true while the save is a stand-in (DataService refuses XP / growth writes then)
local function isProvisional(player)
	if dataService and type(dataService.IsProvisional) == "function" then
		local ok, result = pcall(dataService.IsProvisional, player)
		return ok and result == true
	end
	return false
end

local function getCash(player)
	local ok, cash = dsCall("GetCash", player)
	if ok and isFinite(cash) and cash > 0 then
		return math.floor(cash)
	end
	return 0
end

local function spendCash(player, n)
	local ok, result = dsCall("SpendCash", player, n)
	return ok and result == true
end

local function addCash(player, n)
	local ok, result = dsCall("AddCash", player, n)
	return ok and result == true
end

local function getFood(player, foodId)
	local ok, n = dsCall("GetFood", player, foodId)
	if ok and isFinite(n) and n > 0 then
		return math.floor(n)
	end
	return 0
end

local function addFood(player, foodId, n)
	local ok, result = dsCall("AddFood", player, foodId, n)
	return ok and result == true
end

local function spendFood(player, foodId, n)
	local ok, result = dsCall("SpendFood", player, foodId, n)
	return ok and result == true
end

local function petLevel(player, key)
	local ok, level, xp = dsCall("GetPetLevel", player, key)
	if not ok or not isFinite(level) or level < 1 then
		level = 1
	end
	if not ok or not isFinite(xp) or xp < 0 then
		xp = 0
	end
	return math.floor(level), xp
end

local function addPetXp(player, key, xp)
	local ok, gained = dsCall("AddPetXp", player, key, xp)
	if ok and isFinite(gained) and gained > 0 then
		return math.floor(gained)
	end
	return 0
end

local function mutateHome(player, fn)
	local ok, result = dsCall("MutateHome", player, fn)
	return ok and result == true
end

----------------------------------------------------------------------
-- Catalog access (TycoonCatalog: the Food Machine, the Training Place, the XP curve)
----------------------------------------------------------------------

local function money(n)
	if catalog and type(catalog.FormatCash) == "function" then
		local ok, text = pcall(catalog.FormatCash, n)
		if ok and type(text) == "string" then
			return text
		end
	end
	return "$" .. tostring(math.floor(tonumber(n) or 0))
end

local function foodDef(foodId)
	if type(foodId) ~= "string" or foodId == "" or #foodId > MAX_ID_LENGTH or not catalog then
		return nil
	end
	-- the leftover foods are data (TycoonCatalog.Foods / FoodsById); FoodById is a Phase 3 compat function
	local def = type(catalog.FoodsById) == "table" and catalog.FoodsById[foodId] or nil
	if type(def) ~= "table" and type(catalog.FoodById) == "function" then
		local ok, result = pcall(catalog.FoodById, foodId)
		if ok then
			def = result
		end
	end
	if type(def) ~= "table" or def.Id ~= foodId or not isFinite(def.Xp) or def.Xp <= 0 then
		return nil
	end
	return def
end

local function foodList()
	local out = {}
	if catalog and type(catalog.Foods) == "table" then
		for _, f in ipairs(catalog.Foods) do
			if type(f) == "table" and foodDef(f.Id) then
				out[#out + 1] = f
			end
		end
	end
	return out
end

local function stationLevel(home, id)
	if catalog and type(catalog.StationLevel) == "function" then
		local ok, level = pcall(catalog.StationLevel, home, id)
		if ok and isFinite(level) then
			return math.max(0, math.floor(level))
		end
	end
	local v = type(home) == "table" and type(home.Stations) == "table" and home.Stations[id]
	return isFinite(v) and math.max(0, math.floor(v)) or 0
end

-- XP from `level` to level + 1 (the TycoonCatalog curve; DataService's own fallback curve without it)
local function xpToNext(level)
	if catalog and type(catalog.XpToNext) == "function" then
		local ok, need = pcall(catalog.XpToNext, level)
		if ok and type(need) == "number" and need == need and need > 0 then
			return need
		end
	end
	return math.floor(40 * level ^ 1.35 + 0.5)
end

local function maxPetLevel()
	if petCatalog and type(petCatalog.MaxPetLevel) == "function" then
		local ok, n = pcall(petCatalog.MaxPetLevel)
		if ok and isFinite(n) and n >= 1 then
			return math.floor(n)
		end
	end
	if catalog then
		local px = type(catalog.PetXp) == "table" and catalog.PetXp or nil
		for _, v in ipairs({ catalog.MaxPetLevel or false, px and px.MaxLevel or false }) do
			if isFinite(v) and v >= 1 then
				return math.floor(v)
			end
		end
	end
	return FALLBACK_MAX_LEVEL
end

----------------------------------------------------------------------
-- Pets (keys, defs, ownership, levels and caps)
----------------------------------------------------------------------

local function validKeyString(key)
	if type(key) ~= "string" or key == "" or #key > MAX_ID_LENGTH then
		return false
	end
	if petKeys and type(petKeys.Parse) == "function" then
		local ok, parsed = pcall(petKeys.Parse, key)
		return ok and parsed ~= nil
	end
	return string.find(key, "^[%w_%-:@]+$") ~= nil
end

local function defOf(key, profile)
	if not validKeyString(key) then
		return nil
	end
	if petKeys and type(petKeys.DefOf) == "function" then
		local ok, def = pcall(petKeys.DefOf, key, profile)
		if ok and type(def) == "table" then
			return def
		end
		return nil
	end
	if petCatalog and type(petCatalog.Get) == "function" then
		local def = petCatalog.Get(key)
		if type(def) == "table" then
			return def
		end
	end
	return nil
end

local function ownedCount(profile, key)
	if type(profile) ~= "table" or not validKeyString(key) then
		return 0
	end
	if petKeys and type(petKeys.Count) == "function" then
		local ok, n = pcall(petKeys.Count, profile, key)
		if ok and isFinite(n) and n > 0 then
			return math.floor(n)
		end
		return 0
	end
	local n = type(profile.Pets) == "table" and profile.Pets[key]
	return isFinite(n) and math.max(0, math.floor(n)) or 0
end

local function petName(def, key)
	local name = type(def) == "table" and (def.DisplayName or def.Name) or nil
	if type(name) ~= "string" or name == "" then
		name = tostring(key)
	end
	return clip(name, MAX_NAME_CHARS)
end

-- the level feeding / fights can raise this pet to (PetCatalog.LevelCap: 100 for every rarity, never above the curve)
local function levelCap(def)
	local top = maxPetLevel()
	local cap = nil
	if petCatalog and type(petCatalog.LevelCap) == "function" then
		local ok, n = pcall(petCatalog.LevelCap, def)
		if ok and isFinite(n) then
			cap = n
		end
	end
	if not cap and type(def) == "table" then
		cap = FALLBACK_LEVEL_CAPS[def.Rarity]
	end
	if not isFinite(cap) or cap < 1 then
		return top
	end
	return math.min(math.floor(cap), top)
end

-- XP the pet can still take before it reaches `cap`
local function xpRoom(level, xp, cap)
	if level >= cap then
		return 0
	end
	local total = 0
	for l = level, cap - 1 do
		local need = xpToNext(l)
		if not isFinite(need) then
			break
		end
		total = total + need
	end
	return math.max(0, total - (tonumber(xp) or 0))
end

local function statsOf(def, level)
	if not petCatalog or type(def) ~= "table" then
		return nil
	end
	local fn = petCatalog.StatsOf or petCatalog.GetStats
	if type(fn) ~= "function" then
		return nil
	end
	local ok, stats = pcall(fn, def, level)
	if ok and type(stats) == "table" then
		return stats
	end
	return nil
end

----------------------------------------------------------------------
-- Care helpers: growth, the lock, battles, catalog numbers, texts
----------------------------------------------------------------------

-- { Evo, Speed, Physique, Ability, Defense, Job | nil } (zeros when unknown)
function Care.growth(player, key)
	local ok, g = dsCall("GetGrowth", player, key)
	if ok and type(g) == "table" then
		return g
	end
	local e = { Evo = 0 }
	for _, stat in ipairs(STATS) do
		e[stat] = 0
	end
	return e
end

function Care.growthMap(player)
	local ok, map = dsCall("GetGrowthMap", player)
	if ok and type(map) == "table" then
		return map
	end
	return {}
end

function Care.mutateGrowth(player, fn)
	local ok, result = dsCall("MutateGrowth", player, fn)
	return ok and result == true
end

-- { [key] = true } of the keys in a running battle / ring run of this player, or nil when BattleService has no such
-- function yet (then the whole battle counts: InBattle attribute)
function Care.keysInBattle(player)
	if battleService and type(battleService.KeysInBattle) == "function" then
		local ok, set = pcall(battleService.KeysInBattle, player)
		if ok and type(set) == "table" then
			return set
		end
	end
	return nil
end

function Care.inBattle(player)
	local v = player:GetAttribute(ATTR_IN_BATTLE)
	return v ~= nil and v ~= false
end

function Care.busyInBattle(player, key)
	local set = Care.keysInBattle(player)
	if set then
		return set[key] == true
	end
	return Care.inBattle(player)
end

function Care.statOf(stat)
	if type(stat) ~= "string" or stat == "" or #stat > MAX_STAT_LENGTH then
		return nil
	end
	local s = string.lower((string.gsub(stat, "[%s_%-]", "")))
	return STAT_BY_NAME[s]
end

function Care.statLabel(stat)
	return STAT_LABELS[stat] or tostring(stat)
end

-- 130 -> "2:10", 3600 -> "60:00"
function Care.clock(seconds)
	local s = math.max(0, math.ceil(tonumber(seconds) or 0))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- "x1.8" / "x19.3" / "x1.2K"
function Care.factorText(n)
	n = tonumber(n) or 0
	if not isFinite(n) or n < 0 then
		n = 0
	end
	if n < 100 then
		local s = string.format("%.1f", math.floor(n * 10 + 0.5) / 10)
		s = string.gsub(s, "%.0$", "")
		return "x" .. s
	end
	return "x" .. compact(n)
end

function Care.feedXp(level, machineLevel)
	if catalog and type(catalog.FeedXp) == "function" then
		local ok, n = pcall(catalog.FeedXp, level, machineLevel)
		if ok and isFinite(n) and n > 0 then
			return math.floor(n)
		end
	end
	return 0
end

function Care.feedPrice(def, level)
	if catalog and type(catalog.FeedPrice) == "function" then
		local ok, n = pcall(catalog.FeedPrice, def, level)
		if ok and isFinite(n) and n >= 0 then
			return math.floor(n)
		end
	end
	return nil
end

function Care.trainCost(def, rank)
	if catalog and type(catalog.TrainCost) == "function" then
		local ok, n = pcall(catalog.TrainCost, def, rank)
		if ok and isFinite(n) and n >= 0 then
			return math.floor(n)
		end
	end
	return nil
end

function Care.trainSeconds(rank)
	if catalog and type(catalog.TrainSeconds) == "function" then
		local ok, n = pcall(catalog.TrainSeconds, rank)
		if ok and isFinite(n) and n > 0 then
			return math.floor(n)
		end
	end
	return nil
end

function Care.maxRank()
	local t = catalog and type(catalog.Training) == "table" and catalog.Training or nil
	local n = t and t.MaxRank
	if isFinite(n) and n >= 1 then
		return math.floor(n)
	end
	return FALLBACK_MAX_RANK
end

-- pets training at once (the Training Place level; 0 while it is not built)
function Care.trainingSlots(home)
	local n = nil
	if catalog and type(catalog.TrainingSlots) == "function" then
		local ok, v = pcall(catalog.TrainingSlots, home)
		if ok and isFinite(v) then
			n = v
		end
	end
	if n == nil then
		n = stationLevel(home, "Gym")
	end
	return math.max(0, math.min(math.floor(n), MAX_TRAIN_SLOTS))
end

function Care.gardenSlots(home)
	if catalog and type(catalog.GardenSlots) == "function" then
		local ok, n = pcall(catalog.GardenSlots, home)
		if ok and isFinite(n) and n > 0 then
			return math.floor(n)
		end
	end
	return 0
end

-- the next stage the pet may evolve to, or nil
function Care.canEvolve(def, level, stage)
	if petCatalog and type(petCatalog.CanEvolve) == "function" then
		local ok, nextStage = pcall(petCatalog.CanEvolve, def, level, stage)
		if ok and isFinite(nextStage) then
			return math.floor(nextStage)
		end
	end
	return nil
end

function Care.maxEvolution(def)
	if petCatalog and type(petCatalog.MaxEvolution) == "function" then
		local ok, n = pcall(petCatalog.MaxEvolution, def)
		if ok and isFinite(n) then
			return math.floor(n)
		end
	end
	return 1
end

-- "+25%" for stage 1, "+50%" for stage 2 (PetCatalog.EvolutionMultiplier)
function Care.boostText(stage)
	local m = 1
	if petCatalog and type(petCatalog.EvolutionMultiplier) == "function" then
		local ok, v = pcall(petCatalog.EvolutionMultiplier, stage)
		if ok and isFinite(v) and v >= 1 then
			m = v
		end
	elseif stage >= 2 then
		m = 1.5
	elseif stage >= 1 then
		m = 1.25
	end
	return "+" .. tostring(math.floor((m - 1) * 100 + 0.5)) .. "%"
end

-- the garden coin power of a pet (TycoonCatalog.PetPower; stage = the stored evolution stage)
function Care.coinsText(def, level, stage)
	if catalog and type(catalog.PetPower) == "function" then
		local ok, power = pcall(catalog.PetPower, def, level, nil, stage)
		if ok and isFinite(power) and power > 0 then
			return "Coins " .. Care.factorText(power)
		end
	end
	return ""
end

-- "Coins x1.8" (Economy) / "Power 312, Health 1.2K, Speed 98" (Combat)
function Care.statsText(def, level, stage)
	if type(def) ~= "table" then
		return ""
	end
	if def.Role == "Economy" then
		return Care.coinsText(def, level, stage)
	end
	local stats = statsOf(def, level)
	if not stats then
		return ""
	end
	return "Power " .. compact(stats.Power) .. ", Health " .. compact(stats.Health) .. ", Speed " .. compact(stats.Speed)
end

-- ONE level-up toast per XP grant: "Pebble Pup reached Lv 20: Ready to evolve! Power 312, Health 1.2K, Speed 98"
local function levelUpText(def, key, level, cap, stage, ready)
	local text = petName(def, key) .. " reached Lv " .. level
	if level >= cap then
		text = text .. " (max)"
	end
	if ready then
		text = text .. ": Ready to evolve!"
	else
		text = text .. "!"
	end
	local stats = Care.statsText(def, level, stage)
	if stats ~= "" then
		text = text .. " " .. stats
	end
	return text
end

-- PetService republishes EquippedInfo (level:stage per equipped pet) after a level-up / evolution
function Care.refreshInfo(player)
	if petService and type(petService.Refresh) == "function" then
		pcall(petService.Refresh, player)
	end
end

-- Cap-aware XP. Returns xpGiven, levelsGained, reason (nil on success), the new level / XP / cap / def and whether the
-- pet is now ready to evolve.
local function grantXp(player, key, xp, source)
	-- whole XP only: DataService reads XP back as whole points, so a fraction could never be seen to arrive
	xp = isFinite(xp) and math.floor(xp) or 0
	if xp < 1 then
		return 0, 0, "No XP to give"
	end
	local profile = getProfile(player)
	if not profile or isProvisional(player) then
		return 0, 0, LOADING
	end
	local def = defOf(key, profile)
	if not def then
		return 0, 0, "Unknown pet"
	end
	if ownedCount(profile, key) < 1 then
		return 0, 0, "You do not own that pet"
	end
	local level, have = petLevel(player, key)
	local cap = levelCap(def)
	local room = xpRoom(level, have, cap)
	if room <= 0 then
		return 0, 0, petName(def, key) .. " is at max level (Lv " .. cap .. ")", level, have, cap, def
	end
	local give = math.min(xp, room)
	local gained = addPetXp(player, key, give)
	local level2, have2 = petLevel(player, key)
	if gained == 0 and level2 == level and have2 == have then
		return 0, 0, "That pet cannot gain XP right now", level, have, cap, def
	end
	local stage = Care.growth(player, key).Evo
	local ready = Care.canEvolve(def, level2, stage) ~= nil
	if level2 > level then
		PetCareService.LevelUp:Fire(player, key, level2, source)
		Care.refreshInfo(player)
	end
	return give, math.max(0, level2 - level), nil, level2, have2, cap, def, ready, stage
end

----------------------------------------------------------------------
-- Plots (TycoonService) and station models (HomeBuilder)
----------------------------------------------------------------------

local function plotOf(player)
	if tycoonService and type(tycoonService.GetPlot) == "function" then
		local ok, info = pcall(tycoonService.GetPlot, player)
		if ok and type(info) == "table" then
			return info
		end
	end
	return nil
end

function Care.stationModel(info, id)
	local folder = info and info.Folder
	if typeof(folder) ~= "Instance" then
		return nil
	end
	if homeBuilder and type(homeBuilder.GetStation) == "function" then
		local ok, model = pcall(homeBuilder.GetStation, info, id)
		if ok and typeof(model) == "Instance" and model.Parent and model:IsA("Model") then
			return model
		end
	end
	local homeFolder = folder:FindFirstChild("Home")
	local model = homeFolder and homeFolder:FindFirstChild("Station_" .. id) or nil
	if not model and not homeFolder then
		model = folder:FindFirstChild("Station_" .. id, true)
	end
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

----------------------------------------------------------------------
-- Sessions (per player, this server only), deferred toasts, the TrainingPets attribute
----------------------------------------------------------------------

function Care.session(player)
	local s = sessions[player]
	if not s then
		s = { At = os.clock(), Pending = {}, Shown = nil, GymChecked = false, GymToast = false, MigrationSeen = false }
		sessions[player] = s
	end
	return s
end

-- a toast that waits until the client is surely listening (load toasts: LOAD_TOAST_DELAY after the session started)
function Care.queueToast(player, text, kind, seconds)
	local s = Care.session(player)
	s.Pending[#s.Pending + 1] = { Text = text, Kind = kind, Seconds = seconds }
end

function Care.flushToasts(player, s, now)
	if #s.Pending == 0 or now - s.At < LOAD_TOAST_DELAY then
		return
	end
	local list = s.Pending
	s.Pending = {}
	for _, t in ipairs(list) do
		notify(player, t.Text, t.Kind, t.Seconds)
	end
end

function Care.clearShown(player)
	local s = sessions[player]
	local shown = s and s.Shown
	if not shown then
		return
	end
	s.Shown = nil
	if typeof(shown.Folder) == "Instance" then
		setAttr(shown.Folder, ATTR_TRAINING, nil)
		if shown.Info and homeBuilder and type(homeBuilder.SetTraining) == "function" then
			pcall(homeBuilder.SetTraining, shown.Info, {})
		end
	end
end

-- TrainingPets on the plot folder (+ HomeBuilder.SetTraining when it exists), written only when it changes
function Care.publishTraining(player, map)
	local s = Care.session(player)
	local info = plotOf(player)
	local folder = info and info.Folder
	if typeof(folder) ~= "Instance" then
		Care.clearShown(player)
		return
	end
	if s.Shown and s.Shown.Folder ~= folder then
		Care.clearShown(player)
	end
	map = map or Care.growthMap(player)
	local rows = {}
	for key, e in pairs(map) do
		local job = type(e) == "table" and e.Job or nil
		if type(job) == "table" then
			local slot = isFinite(job.Slot) and math.floor(job.Slot) or 0
			rows[#rows + 1] = { Slot = slot, Key = key, Job = job, Text = tostring(slot) .. "=" .. key .. ":" .. tostring(job.Stat) .. ":" .. tostring(math.floor(tonumber(job.Ends) or 0)) }
		end
	end
	table.sort(rows, function(a, b)
		if a.Slot == b.Slot then
			return a.Key < b.Key
		end
		return a.Slot < b.Slot
	end)
	local parts = {}
	for i, r in ipairs(rows) do
		parts[i] = r.Text
	end
	local text = table.concat(parts, ";")
	if s.Shown and s.Shown.Folder == folder and s.Shown.Text == text then
		return
	end
	s.Shown = { Folder = folder, Info = info, Text = text }
	setAttr(folder, ATTR_TRAINING, text)
	if homeBuilder and type(homeBuilder.SetTraining) == "function" then
		local pets = {}
		for _, r in ipairs(rows) do
			pets[r.Slot] = { Key = r.Key, Stat = r.Job.Stat, Ends = r.Job.Ends }
		end
		local ok, err = pcall(homeBuilder.SetTraining, info, pets)
		if not ok then
			warn("[PetCareService] HomeBuilder.SetTraining failed: " .. tostring(err))
		end
	end
end

----------------------------------------------------------------------
-- Feeding (the Food Machine and the leftovers)
----------------------------------------------------------------------

-- opts -> { Food = id } | { Count = n } | {} (one machine feed), or nil, reason for junk
function Care.parseOpts(opts)
	if opts == nil then
		return {}
	end
	if type(opts) == "string" then
		if not foodDef(opts) then
			return nil, "Unknown food"
		end
		return { Food = opts }
	end
	if type(opts) ~= "table" then
		return nil, "Unknown food"
	end
	local food = opts.Food
	if food == nil then
		food = opts.FoodId
	end
	if food ~= nil then
		if type(food) ~= "string" or not foodDef(food) then
			return nil, "Unknown food"
		end
		return { Food = food }
	end
	if opts.Count ~= nil then
		local n = opts.Count
		if not isFinite(n) or n ~= math.floor(n) or n < 1 or n > MAX_FEEDS then
			return nil, "Pick how many feeds (1-" .. MAX_FEEDS .. ")"
		end
		return { Count = n }
	end
	return {}
end

-- the leftover a pet gets: the biggest food in `stock` that does not overshoot `room` (the smallest one when every
-- food would), or nil without any leftover
function Care.bowlFood(stock, room)
	local best, smallest = nil, nil
	for _, f in ipairs(foodList()) do
		if (stock[f.Id] or 0) >= 1 then
			if f.Xp <= room and (not best or f.Xp > best.Xp) then
				best = f
			end
			if not smallest or f.Xp < smallest.Xp then
				smallest = f
			end
		end
	end
	return best or smallest
end

-- Plans the feeds of one request feed by feed along the XP curve: leftovers first (free), then machine feeds priced
-- at the level each one is eaten at. Returns items { { Food = id, Name } | { Price = n }, Xp }..., the Cash sum, the
-- free count and a reason when nothing can be fed.
function Care.planFeeds(player, def, mode, level, have, cap, machineLevel)
	local count = mode.Count or 1
	local items, total, free = {}, 0, 0
	local stock = {}
	for _, f in ipairs(foodList()) do
		stock[f.Id] = getFood(player, f.Id)
	end
	local lv, xp = level, have
	local room = xpRoom(level, have, cap)
	local why = nil
	for _ = 1, count do
		if room <= 0 then
			break
		end
		local item = nil
		local f = nil
		if mode.Food then
			f = foodDef(mode.Food)
			if (stock[f.Id] or 0) < 1 then
				why = "You have no " .. plural(f.Name, 2) .. " left"
				break
			end
		else
			f = Care.bowlFood(stock, room)
		end
		if f then
			stock[f.Id] = stock[f.Id] - 1
			item = { Food = f.Id, Name = f.Name, Xp = math.min(f.Xp, room) }
			free = free + 1
		else
			if machineLevel < 1 then
				if #items == 0 then
					why = "Build the Food Machine at home first"
				end
				break
			end
			local price = Care.feedPrice(def, lv)
			local give = Care.feedXp(lv, machineLevel)
			if not price or give < 1 then
				break
			end
			item = { Price = price, Xp = math.min(give, room) }
			total = total + price
		end
		items[#items + 1] = item
		-- walk the curve: the next feed is priced at the level the pet has then
		xp = xp + item.Xp
		room = room - item.Xp
		while lv < cap do
			local need = xpToNext(lv)
			if not isFinite(need) or xp < need then
				break
			end
			xp = xp - need
			lv = lv + 1
		end
	end
	return items, total, free, why
end

local function feed(player, key, opts)
	if not initialized then
		return false, "Feeding is not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	if not validKeyString(key) then
		return false, "Unknown pet"
	end
	local mode, bad = Care.parseOpts(opts)
	if not mode then
		return false, bad
	end
	local profile = getProfile(player)
	if not profile or isProvisional(player) then
		return false, LOADING
	end
	local def = defOf(key, profile)
	if not def then
		return false, "Unknown pet"
	end
	if ownedCount(profile, key) < 1 then
		return false, "You do not own that pet"
	end
	local name = petName(def, key)
	local level, have = petLevel(player, key)
	local cap = levelCap(def)
	if xpRoom(level, have, cap) <= 0 then
		return false, name .. " is at max level (Lv " .. cap .. ")"
	end
	if Care.busyInBattle(player, key) then
		return false, "Finish your battle first"
	end
	local home = getHome(player)
	local machineLevel = home and stationLevel(home, "Kitchen") or 0
	local items, total, free, why = Care.planFeeds(player, def, mode, level, have, cap, machineLevel)
	if #items == 0 then
		return false, why or "That pet cannot eat right now"
	end
	-- the Cash check: paid feeds come after the free ones, so dropping them from the end keeps every price at its level
	local firstPrice = nil
	for _, item in ipairs(items) do
		if item.Price and not firstPrice then
			firstPrice = item.Price
		end
	end
	local cash = getCash(player)
	for i = #items, 1, -1 do
		if total <= cash then
			break
		end
		if items[i].Price then
			total = total - items[i].Price
			table.remove(items, i)
		end
	end
	if #items == 0 then
		return false, "Not enough Cash: a feed costs " .. money(firstPrice or 0)
	end
	local xpTotal, paidCount, firstFood = 0, 0, nil
	for _, item in ipairs(items) do
		xpTotal = xpTotal + item.Xp
		if item.Price then
			paidCount = paidCount + 1
		elseif not firstFood then
			firstFood = item
		end
	end
	free = #items - paidCount
	-- the foods, the Cash and the XP in one step (no yields); everything comes back when the XP was refused
	local spent = {}
	local function refundFood()
		for id, n in pairs(spent) do
			addFood(player, id, n)
		end
	end
	for _, item in ipairs(items) do
		if item.Food then
			if not spendFood(player, item.Food, 1) then
				refundFood()
				return false, "You have no " .. plural(item.Name, 2) .. " left"
			end
			spent[item.Food] = (spent[item.Food] or 0) + 1
		end
	end
	if total > 0 and not spendCash(player, total) then
		refundFood()
		return false, "Not enough Cash: a feed costs " .. money(firstPrice or total)
	end
	local given, levels, reason, newLevel, newXp, cap2, _, ready, stage = grantXp(player, key, xpTotal, "Feed")
	if given <= 0 then
		if total > 0 then
			addCash(player, total)
		end
		refundFood()
		return false, reason or "That pet cannot eat right now"
	end
	local foodId = (paidCount > 0 or not firstFood) and "Machine" or firstFood.Food
	PetCareService.Fed:Fire(player, key, foodId, levels)
	-- ONE toast per request
	if levels > 0 then
		notify(player, levelUpText(def, key, newLevel, cap2 or cap, stage, ready), "good", 5)
	else
		local need = xpToNext(newLevel)
		local progress = isFinite(need) and (" (" .. math.floor(newXp) .. "/" .. need .. " to Lv " .. (newLevel + 1) .. ")") or ""
		local what
		if #items == 1 then
			if firstFood and paidCount == 0 then
				what = " ate a free " .. tostring(firstFood.Name)
			else
				what = " ate a meal"
			end
		else
			what = " ate " .. #items .. " meals"
			if free > 0 and paidCount > 0 then
				what = what .. " (" .. free .. " free)"
			elseif paidCount == 0 then
				what = what .. " (free)"
			end
		end
		notify(player, name .. what .. ": +" .. math.floor(given) .. " XP" .. progress, "good", 3)
	end
	return true, { Xp = given, Levels = levels, Level = newLevel, Cap = cap2 or cap, Paid = total, Free = free, Count = #items }
end

function PetCareService.Feed(player, key, opts)
	return feed(player, key, opts)
end

----------------------------------------------------------------------
-- EVOLVE
----------------------------------------------------------------------

function Care.openPanel(player, panelId, args)
	openPanelRemote = openPanelRemote or remote("OpenPanel")
	if openPanelRemote and isPlayer(player) then
		pcall(function()
			openPanelRemote:FireClient(player, panelId, args)
		end)
	end
end

function PetCareService.Evolve(player, key)
	if not initialized then
		return false, "Pet care is not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	if not validKeyString(key) then
		return false, "Unknown pet"
	end
	local profile = getProfile(player)
	if not profile or isProvisional(player) then
		return false, LOADING
	end
	local def = defOf(key, profile)
	if not def then
		return false, "Unknown pet"
	end
	if ownedCount(profile, key) < 1 then
		return false, "You do not own that pet"
	end
	local name = petName(def, key)
	if Care.inBattle(player) or Care.busyInBattle(player, key) then
		return false, "Finish your battle first"
	end
	local level = petLevel(player, key)
	local stage = Care.growth(player, key).Evo or 0
	local nextStage = Care.canEvolve(def, level, stage)
	if not nextStage then
		if stage >= Care.maxEvolution(def) then
			return false, name .. " is fully evolved"
		end
		local levels = petCatalog and type(petCatalog.EvolutionLevels) == "table" and petCatalog.EvolutionLevels or { 20, 50 }
		local need = levels[stage + 1] or 20
		return false, name .. " evolves at level " .. tostring(need) .. " (Lv " .. level .. " now)"
	end
	local ok, wrote = dsCall("SetEvolution", player, key, nextStage)
	if not ok or wrote ~= true then
		return false, "Could not evolve right now, try again"
	end
	PetCareService.Evolved:Fire(player, key, nextStage)
	notify(player, name .. " evolved! " .. Care.boostText(nextStage) .. " to everything", "good", 6)
	Care.refreshInfo(player)
	Care.openPanel(player, "Evolve", { Key = key, Stage = nextStage })
	return true, nextStage
end

----------------------------------------------------------------------
-- Training (the Training Place): start, stop, completion, auto-remove / auto-return
----------------------------------------------------------------------

-- the mats in use and the running job count of a player (from the clean growth map)
function Care.usedMats(player)
	local map = Care.growthMap(player)
	local used, n = {}, 0
	for _, e in pairs(map) do
		local job = type(e) == "table" and e.Job or nil
		if type(job) == "table" then
			n = n + 1
			if isFinite(job.Slot) then
				used[math.floor(job.Slot)] = true
			end
		end
	end
	return used, n, map
end

-- where the pet is now: "Garden:<slot>" (the smallest place holding it) | "Follow" | "Free"
function Care.fromOf(profile, home, key)
	local best = nil
	if type(home) == "table" and type(home.Garden) == "table" then
		for slot, k in pairs(home.Garden) do
			if k == key and isFinite(slot) and (best == nil or slot < best) then
				best = math.floor(slot)
			end
		end
	end
	if best then
		return "Garden:" .. best
	end
	if type(profile) == "table" and type(profile.Equipped) == "table" then
		for _, k in ipairs(profile.Equipped) do
			if k == key then
				return "Follow"
			end
		end
	end
	return "Free"
end

-- clears one Garden place (TycoonService.GardenSet, else straight into the saved Home)
function Care.clearGarden(player, slot)
	if tycoonService and type(tycoonService.GardenSet) == "function" then
		local ok, done = pcall(tycoonService.GardenSet, player, slot, nil)
		if ok and done == true then
			return
		end
	end
	mutateHome(player, function(live)
		if type(live.Garden) ~= "table" or live.Garden[slot] == nil then
			return false
		end
		live.Garden[slot] = nil
		return true
	end)
end

-- a training pet leaves the player (every equipped copy) and the Garden by itself
function Care.removePet(player, key)
	if petService then
		if type(petService.UnequipKey) == "function" then
			pcall(petService.UnequipKey, player, key)
		elseif type(petService.Unequip) == "function" then
			for _ = 1, 8 do
				local ok, done = pcall(petService.Unequip, player, key)
				if not (ok and done == true) then
					break
				end
			end
		end
	end
	local home = getHome(player)
	if home and type(home.Garden) == "table" then
		local slots = {}
		for slot, k in pairs(home.Garden) do
			if k == key then
				slots[#slots + 1] = slot
			end
		end
		for _, slot in ipairs(slots) do
			Care.clearGarden(player, slot)
		end
	end
end

-- the pet comes back to where it was (Job.From): "Follow" -> re-equipped when a slot is free; "Garden:n" -> that
-- place when open and empty, else the first free open place; else it stays in the list
function Care.returnPet(player, key, from)
	if type(from) ~= "string" or not isPlayer(player) then
		return
	end
	if from == "Follow" then
		if petService and type(petService.Equip) == "function" then
			pcall(petService.Equip, player, key)
		end
		return
	end
	local slot = tonumber(string.match(from, "^Garden:(%d+)$"))
	if not slot then
		return
	end
	local home = getHome(player)
	if not home or type(home.Garden) ~= "table" then
		return
	end
	local open = Care.gardenSlots(home)
	local target = nil
	if slot <= open and home.Garden[slot] == nil then
		target = slot
	else
		for s = 1, open do
			if home.Garden[s] == nil then
				target = s
				break
			end
		end
	end
	if target and tycoonService and type(tycoonService.GardenSet) == "function" then
		pcall(tycoonService.GardenSet, player, target, key)
	end
end

-- Finishes a due job: the rank becomes the job's TARGET rank (two servers completing one job give one rank), the
-- job goes, the pet comes back. Returns true when this server completed it.
function Care.completeJob(player, key, job, atLoad)
	local wrote = Care.mutateGrowth(player, function(g)
		local e = g[key]
		if type(e) ~= "table" or type(e.Job) ~= "table" or e.Job.Stat ~= job.Stat then
			return false -- changed meanwhile (stopped, or another server's state): nothing to do here
		end
		local rank = e.Job.Rank
		if (e[job.Stat] or 0) < rank then
			e[job.Stat] = rank
		end
		e.Job = nil
		return true
	end)
	if not wrote then
		return false
	end
	local def = defOf(key, getProfile(player))
	local name = petName(def, key)
	local label = Care.statLabel(job.Stat)
	pcall(Care.returnPet, player, key, job.From)
	Care.publishTraining(player)
	if atLoad then
		Care.queueToast(player, "Training done while you were away! " .. name .. ": " .. label .. " Rank " .. tostring(job.Rank), "good", 6)
	else
		notify(player, name .. " finished " .. label .. " training: Rank " .. tostring(job.Rank) .. "!", "good", 5)
	end
	PetCareService.TrainingDone:Fire(player, key, job.Stat, job.Rank)
	return true
end

-- completes every due job (os.time() >= Job.Ends) of a loaded, non-provisional player; returns how many, the map
function Care.settleJobs(player, atLoad)
	local profile = getProfile(player)
	if not profile or isProvisional(player) then
		return 0, nil
	end
	local map = Care.growthMap(player)
	local now = os.time()
	local done = 0
	for key, e in pairs(map) do
		local job = type(e) == "table" and e.Job or nil
		if type(job) == "table" and isFinite(job.Ends) and now >= job.Ends then
			if ownedCount(profile, key) < 1 then
				Care.mutateGrowth(player, function(g)
					g[key] = nil -- a job of a pet that is gone (fused away elsewhere)
				end)
				done = done + 1
			elseif Care.completeJob(player, key, job, atLoad) then
				done = done + 1
			end
		end
	end
	if done > 0 then
		map = nil -- changed: let the caller re-read
	end
	return done, map
end

function PetCareService.Train(player, key, stat)
	if not initialized then
		return false, "Pet care is not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	if not validKeyString(key) then
		return false, "Unknown pet"
	end
	stat = Care.statOf(stat)
	if not stat then
		return false, "Pick a skill: Attack Speed, Physique, Ability or Defense"
	end
	local profile = getProfile(player)
	if not profile or isProvisional(player) then
		return false, LOADING
	end
	local def = defOf(key, profile)
	if not def then
		return false, "Unknown pet"
	end
	if ownedCount(profile, key) < 1 then
		return false, "You do not own that pet"
	end
	local name = petName(def, key)
	local label = Care.statLabel(stat)
	local home = getHome(player)
	if not home then
		return false, LOADING
	end
	local slots = Care.trainingSlots(home)
	if slots < 1 then
		return false, "Build the Training Place at home first"
	end
	local growth = Care.growth(player, key)
	if type(growth.Job) == "table" then
		return false, name .. " is already training (" .. Care.clock((tonumber(growth.Job.Ends) or 0) - os.time()) .. " left)"
	end
	local rank = isFinite(growth[stat]) and math.floor(growth[stat]) or 0
	local maxRank = Care.maxRank()
	if rank >= maxRank then
		return false, name .. "'s " .. label .. " is at Rank " .. maxRank .. " (max)"
	end
	local used, runningJobs = Care.usedMats(player)
	local mat = nil
	for s = 1, slots do
		if not used[s] then
			mat = s
			break
		end
	end
	if runningJobs >= slots or not mat then
		return false, "The Training Place is full (" .. runningJobs .. "/" .. slots .. " training)"
	end
	if Care.busyInBattle(player, key) then
		return false, "Finish your battle first"
	end
	local cost = Care.trainCost(def, rank + 1)
	local seconds = Care.trainSeconds(rank + 1)
	if not cost or not seconds then
		return false, "That pet cannot train right now"
	end
	local short = "Not enough Cash: Rank " .. (rank + 1) .. " " .. label .. " costs " .. money(cost)
	if getCash(player) < cost then
		return false, short
	end
	local from = Care.fromOf(profile, home, key)
	-- the payment and the job in one step (no yields): a failed job write gives the Cash back
	if cost > 0 and not spendCash(player, cost) then
		return false, short
	end
	local ends = os.time() + seconds
	local wrote = Care.mutateGrowth(player, function(g)
		local e = g[key]
		if type(e) ~= "table" then
			e = {}
			g[key] = e
		end
		if type(e.Job) == "table" then
			return false
		end
		e.Job = { Stat = stat, Ends = ends, Rank = (isFinite(e[stat]) and math.floor(e[stat]) or 0) + 1, Slot = mat, From = from, Paid = cost }
		return true
	end)
	if not wrote then
		if cost > 0 then
			addCash(player, cost)
		end
		return false, "Could not start training right now, try again"
	end
	-- the pet leaves the player and the Garden by itself (Job.From remembers where it was)
	pcall(Care.removePet, player, key)
	Care.publishTraining(player)
	notify(player, name .. " started " .. label .. " training (" .. Care.clock(seconds) .. ")", "good", 4)
	PetCareService.TrainingStarted:Fire(player, key, stat)
	return true, { Rank = rank + 1, Ends = ends, Cost = cost, Slot = mat, From = from }
end

function PetCareService.TrainStop(player, key)
	if not initialized then
		return false, "Pet care is not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	if not validKeyString(key) then
		return false, "Unknown pet"
	end
	local profile = getProfile(player)
	if not profile or isProvisional(player) then
		return false, LOADING
	end
	local def = defOf(key, profile)
	local name = petName(def, key)
	local job = Care.growth(player, key).Job
	if type(job) ~= "table" then
		return false, name .. " is not training"
	end
	if isFinite(job.Ends) and os.time() >= job.Ends then
		-- already done: it finishes instead (the rank is earned, nothing to refund)
		Care.completeJob(player, key, job, false)
		return true, 0
	end
	local paid = isFinite(job.Paid) and math.max(0, math.floor(job.Paid)) or 0
	-- the job goes and the Cash comes back in the same step (they travel in the same save)
	local wrote = Care.mutateGrowth(player, function(g)
		local e = g[key]
		if type(e) ~= "table" or type(e.Job) ~= "table" then
			return false
		end
		e.Job = nil
		return true
	end)
	if not wrote then
		return false, "Could not stop training right now, try again"
	end
	if paid > 0 then
		addCash(player, paid)
	end
	pcall(Care.returnPet, player, key, job.From)
	Care.publishTraining(player)
	if paid > 0 then
		notify(player, name .. " stopped training: " .. money(paid) .. " back", "info", 3)
	else
		notify(player, name .. " stopped training", "info", 3)
	end
	return true, paid
end

----------------------------------------------------------------------
-- Home load: the retired Gym, offline completions
----------------------------------------------------------------------

-- empties Home.Gym (the Gym is the Training Place now) once the home is readable; one toast per session, also when
-- DataService's one-time migration freed the Gym pets this session
function Care.freeOldGym(player)
	local s = Care.session(player)
	if s.GymChecked then
		return
	end
	local home = getHome(player)
	if not home then
		return -- not loaded yet / provisional: ProfileRebased and the tick bring us back
	end
	s.GymChecked = true
	local freed = 0
	if type(home.Gym) == "table" and next(home.Gym) ~= nil then
		local n = 0
		local wrote = mutateHome(player, function(live)
			if type(live.Gym) ~= "table" then
				return false
			end
			local slots = {}
			for slot, k in pairs(live.Gym) do
				if type(k) == "string" then
					n = n + 1
				end
				slots[#slots + 1] = slot
			end
			for _, slot in ipairs(slots) do
				live.Gym[slot] = nil
			end
			return #slots > 0
		end)
		if wrote then
			freed = freed + n
		end
	end
	if not s.MigrationSeen then
		local ok, info = dsCall("MigratedNow", player, "P4")
		if ok and type(info) == "table" then
			s.MigrationSeen = true
			if isFinite(info.GymPets) and info.GymPets > 0 then
				freed = freed + math.floor(info.GymPets)
			end
		end
	end
	if freed > 0 and not s.GymToast then
		s.GymToast = true
		Care.queueToast(player, "The Gym is now the Training Place: your gym pets are back with you", "info", 6)
	end
end

-- ProfileLoaded / ProfileRebased (and players already here at Init): the old Gym, the jobs that ended meanwhile
function Care.onProfileReady(player)
	if not isPlayer(player) then
		return
	end
	local s = Care.session(player)
	s.GymChecked = false -- a rebased save may hold Gym pets again (a Phase 3 server during the rollout)
	if not getProfile(player) or isProvisional(player) then
		return
	end
	Care.freeOldGym(player)
	local done, map = Care.settleJobs(player, true)
	if done > 0 then
		map = nil
	end
	Care.publishTraining(player, map)
end

----------------------------------------------------------------------
-- Prompts (FeedPrompt on the Food Machine, TrainPrompt on the Training Place)
----------------------------------------------------------------------

local function biggestPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local best, size = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local s = d.Size.X * d.Size.Y * d.Size.Z
			if s > size then
				best, size = d, s
			end
		end
	end
	return best
end

local function newPrompt(parent, name, action, object, ownerId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = PROMPT_KEYS.Keyboard
	prompt.GamepadKeyCode = PROMPT_KEYS.Gamepad
	prompt.HoldDuration = PROMPT_HOLD
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerUserId", ownerId)
	prompt:SetAttribute(CARE_MARK, true)
	prompt.Parent = parent
	return prompt
end

local function clearCarePrompts(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.Parent and d:GetAttribute(CARE_MARK) == true then
			d:Destroy()
		end
	end
end

-- the part a prompt sits on: the named part (a part inside a named model) when the station has it, else its biggest
function Care.anchorOf(model, anchorName)
	if anchorName then
		local found = model:FindFirstChild(anchorName, true)
		if found then
			if found:IsA("BasePart") then
				return found
			end
			local inner = found:FindFirstChildWhichIsA("BasePart", true)
			if inner then
				return inner
			end
		end
	end
	return biggestPart(model)
end

-- one owner-only prompt per station (rebuilt when the station or its owner changes; the signature carries "p4:")
function Care.ensurePrompt(player, info, home, stationId, promptName, action, object, anchorName)
	local level = stationLevel(home, stationId)
	if level < 1 then
		return
	end
	local model = Care.stationModel(info, stationId)
	if not model then
		return
	end
	local sig = SIG_PREFIX .. stationId .. ":" .. tostring(level) .. ":" .. tostring(player.UserId)
	if model:GetAttribute(CARE_SIG) == sig then
		return
	end
	clearCarePrompts(model)
	local anchor = Care.anchorOf(model, anchorName)
	if not anchor then
		return
	end
	local prompt = newPrompt(anchor, promptName, action, object, player.UserId)
	prompt:SetAttribute("StationId", stationId)
	model:SetAttribute(CARE_SIG, sig)
end

function Care.ensurePrompts(player, info, home)
	Care.ensurePrompt(player, info, home, "Kitchen", "FeedPrompt", "Feed pets", "Food Machine", "Hopper")
	Care.ensurePrompt(player, info, home, "Gym", "TrainPrompt", "Train pets", "Training Place", nil)
end

local function onPromptTriggered(prompt, player)
	if typeof(prompt) ~= "Instance" or not isPlayer(player) then
		return
	end
	local name = prompt.Name
	if name ~= "FeedPrompt" and name ~= "TrainPrompt" then
		return
	end
	if prompt:GetAttribute(CARE_MARK) ~= true or prompt:GetAttribute("OwnerUserId") ~= player.UserId then
		return -- someone else's home (their prompts are disabled locally; never trust a stray trigger)
	end
	local info = plotOf(player)
	if not info or typeof(info.Folder) ~= "Instance" or not prompt:IsDescendantOf(info.Folder) then
		return
	end
	if not cooldown(player, "Prompt", PROMPT_COOLDOWN) or not spend(player) then
		return
	end
	if name == "FeedPrompt" then
		Care.openPanel(player, "Pets", { Tab = "Pets", Action = "Feed" })
	else
		Care.openPanel(player, "Train")
	end
end

----------------------------------------------------------------------
-- Extras
----------------------------------------------------------------------

-- Cap-aware XP for other services (battles, the Champion Ring): never past the pet's level cap. Returns xpGiven,
-- levelsGained, reason (nil when XP was given). ONE toast per grant: the level-up toast with the new stats (and
-- "Ready to evolve!" at 20 / 50), whatever the number of levels crossed.
function PetCareService.GrantXp(player, key, xp, source)
	if not initialized then
		return 0, 0, "Pet care is not ready yet"
	end
	if not isPlayer(player) or not validKeyString(key) then
		return 0, 0, "Unknown pet"
	end
	local given, levels, why, newLevel, _, cap, def, ready, stage = grantXp(player, key, tonumber(xp), source or "Other")
	if levels > 0 and def then
		notify(player, levelUpText(def, key, newLevel, cap, stage, ready), "good", 5)
	end
	return given, levels, why
end

function PetCareService.LevelCap(player, key)
	local def = defOf(key, player and getProfile(player) or nil)
	if not def then
		return nil
	end
	return levelCap(def)
end

-- Developer tools ("Reset my data"): drops this server's session state of the player (deferred toasts, the published
-- TrainingPets, the Gym check). The saved growth is wiped by DevService itself.
function PetCareService.ClearSessions(player)
	if not player then
		return false
	end
	Care.clearShown(player)
	local s = sessions[player]
	if s then
		s.Pending = {}
		s.GymChecked = false
		s.GymToast = false
		s.MigrationSeen = false
	end
	cooldowns[player] = nil
	return true
end

----------------------------------------------------------------------
-- Remote PetCare(action, a, b)
----------------------------------------------------------------------

local function onPetCare(player, action, a, b)
	if not isPlayer(player) or type(action) ~= "string" or #action > MAX_ACTION_LENGTH then
		return
	end
	if not spend(player) then
		return
	end
	if action == "Feed" then
		if not cooldown(player, "Feed", FEED_COOLDOWN) then
			return
		end
		local key, opts = a, b
		if type(a) == "table" then
			key = a.Key
			if key == nil then
				key = a[1]
			end
			if opts == nil then
				if a.Count ~= nil then
					opts = { Count = a.Count }
				elseif a.Food ~= nil or a.FoodId ~= nil then
					opts = { Food = a.Food ~= nil and a.Food or a.FoodId }
				elseif a[2] ~= nil then
					opts = a[2]
				end
			end
		end
		local ok, reason = feed(player, key, opts)
		if not ok then
			toastOnce(player, reason or "That pet cannot eat now", "bad")
		end
	elseif action == "Evolve" then
		if not cooldown(player, "Evolve", EVOLVE_COOLDOWN) then
			return
		end
		local key = a
		if type(a) == "table" then
			key = a.Key
			if key == nil then
				key = a[1]
			end
		end
		local ok, reason = PetCareService.Evolve(player, key)
		if not ok then
			toastOnce(player, reason or "That pet cannot evolve now", "bad")
		end
	elseif action == "Train" then
		if not cooldown(player, "Train", TRAIN_COOLDOWN) then
			return
		end
		local key, stat = a, b
		if type(a) == "table" then
			key = a.Key
			if key == nil then
				key = a[1]
			end
			stat = a.Stat
			if stat == nil then
				stat = a.Skill
			end
			if stat == nil then
				stat = a[2]
			end
		end
		local ok, reason = PetCareService.Train(player, key, stat)
		if not ok then
			toastOnce(player, reason or "That pet cannot train now", "bad")
		end
	elseif action == "TrainStop" then
		if not cooldown(player, "Train", TRAIN_COOLDOWN) then
			return
		end
		local key = a
		if type(a) == "table" then
			key = a.Key
			if key == nil then
				key = a[1]
			end
		end
		local ok, reason = PetCareService.TrainStop(player, key)
		if not ok then
			toastOnce(player, reason or "That pet is not training", "bad")
		end
	elseif action == "Cook" then
		toastOnce(player, "The Kitchen is now the Food Machine: press E at it to feed your pets", "info")
	elseif action == "GymSet" then
		toastOnce(player, "The Gym is now the Training Place: press E at it to train a pet", "info")
	end
end

----------------------------------------------------------------------
-- Tick + players
----------------------------------------------------------------------

local function tickPlayer(player, now)
	local s = Care.session(player)
	local profile = getProfile(player)
	local readable = profile ~= nil and not isProvisional(player)
	local map = nil
	if readable then
		if not s.GymChecked then
			Care.freeOldGym(player)
		end
		local done
		done, map = Care.settleJobs(player, false)
		if done > 0 then
			map = nil
		end
	end
	local info = plotOf(player)
	if info and readable then
		local home = getHome(player)
		if home then
			Care.ensurePrompts(player, info, home)
			Care.publishTraining(player, map)
		end
	elseif s.Shown then
		Care.clearShown(player)
	end
	Care.flushToasts(player, s, now)
end

local function tickAll()
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		if isPlayer(player) then
			local ok, err = pcall(tickPlayer, player, now)
			if not ok then
				warn("[PetCareService] tick failed: " .. tostring(err))
			end
		end
	end
end

local function tickLoop()
	while running do
		task.wait(TICK)
		if not running then
			break
		end
		local ok, err = pcall(tickAll)
		if not ok then
			warn("[PetCareService] tick failed: " .. tostring(err))
		end
	end
end

local function onPlayerAdded(player)
	Care.session(player)
	if getProfile(player) and not isProvisional(player) then
		local ok, err = pcall(Care.onProfileReady, player)
		if not ok then
			warn("[PetCareService] load failed: " .. tostring(err))
		end
	end
end

local function onPlayerRemoving(player)
	departed[player] = true
	Care.clearShown(player)
	sessions[player] = nil
	cooldowns[player] = nil
	budgets[player] = nil
	toastAt[player] = nil
end

local function connectSignal(signal, fn, what)
	if type(signal) == "table" and type(signal.Connect) == "function" then
		local ok, err = pcall(function()
			signal:Connect(function(...)
				local okCall, callErr = pcall(fn, ...)
				if not okCall then
					warn("[PetCareService] " .. what .. " handler failed: " .. tostring(callErr))
				end
			end)
		end)
		if not ok then
			warn("[PetCareService] could not listen to " .. what .. ": " .. tostring(err))
		end
	end
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------

function PetCareService.Init(deps)
	if initialized then
		return
	end
	deps = deps or {}
	local services = script.Parent
	dataService = deps.DataService or requireModule(services, "DataService")
	petService = deps.PetService
	tycoonService = deps.TycoonService
	battleService = deps.BattleService
	catalog = requireModule(Shared, "TycoonCatalog")
	petKeys = requireModule(Shared, "PetKeys")
	petCatalog = requireModule(Shared, "PetCatalog")
	if not catalog then
		warn("[PetCareService] TycoonCatalog is missing: the Food Machine, EVOLVE and the Training Place are disabled")
		return
	end
	if not dataService or type(dataService.AddPetXp) ~= "function" then
		warn("[PetCareService] DataService has no pet level API: the Food Machine, EVOLVE and the Training Place are disabled")
		return
	end
	if type(dataService.MutateGrowth) ~= "function" then
		warn("[PetCareService] DataService has no PetGrowth API: EVOLVE and training will refuse")
	end
	homeBuilder = services and services:FindFirstChild("HomeBuilder") and requireModule(services, "HomeBuilder") or nil
	initialized = true

	local petCare = remote("PetCare")
	if petCare then
		petCare.OnServerEvent:Connect(onPetCare)
	else
		warn("[PetCareService] the PetCare remote is missing (Config.Remotes)")
	end
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	-- the old Gym is emptied and due jobs finish when a save becomes readable (load, rebase, dev reset)
	connectSignal(dataService.ProfileLoaded, Care.onProfileReady, "DataService.ProfileLoaded")
	connectSignal(dataService.ProfileRebased, Care.onProfileReady, "DataService.ProfileRebased")
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	running = true
	task.spawn(tickLoop)
end

return PetCareService
