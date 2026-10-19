-- TycoonService: the tycoon homes (ARCHITECTURE_V3.md "Phase 2: Tycoon homes" + "Phase 4: pets make the money" and
-- the "Phase 4 build contract", sections 3.1-3.3, 3.10, 3.11, 5.1-5.4, 7).
--
-- * Claiming: every free plot's gate carries a "Claim Home" ProximityPrompt named ClaimPrompt (HomeBuilder.PreparePlot
--   builds it; when HomeBuilder is missing or built none, this service puts a plain one on the gate). Pressing E
--   claims that plot for the session: one plot per player, refused during a match and while the save is still
--   loading. SpotService keeps the plot <-> player map (GetSpot answers the claimed plot). The SAVED progress is the
--   player's Home build (profile Home), not a plot number: it is rebuilt on whichever plot they claim. Leaving
--   releases the plot (the build is cleared, the gate reads "Claim Home" again). A claim also re-derives
--   Home.Level from the stations (TycoonCatalog.HomeLevelOf) when an older save disagrees. The gate's prompt must be
--   triggered from near the gate (its range + a little slack). The first claim of a migrated Phase 3 veteran shows
--   the one-time welcome toast (Migrations.P4Veteran -> P4Welcome, a union: never twice, also across servers).
-- * Buy pads: HomeBuilder.SetPads shows TycoonCatalog.AvailablePads(home) as pads `Pad_<StationId>` with a
--   ProximityPrompt `BuyPrompt` (attributes StationId, OwnerUserId). A purchase (pad or the Home window's "Upgrade")
--   is validated here: the player owns that plot, the station is in AvailablePads and not locked
--   (TycoonCatalog.CheckPurchase, whose price is the STAR price TycoonCatalog.PriceAt: x1.5 per Prestige star unless
--   Home.LegacyPrices), the price is paid with DataService.SpendCash and the level written with DataService.MutateHome
--   IN ONE NON-YIELDING STEP (the cash is refunded if the home write is refused). The station then appears
--   (HomeBuilder.SetStation; the client pops it in), the pads refresh and a side toast confirms it. The Prestige pad
--   (StationId "Prestige", prompt "Prestige") never resets anything by itself: E on it opens the Home window on its
--   prestige confirmation (OpenPanel("Home", { Action = "Prestige" })) and only HomeAction "Prestige" prestiges.
-- * Rainbow coins (the ONLY money source, contract 3.2): every open garden place (slot <= TycoonCatalog.GardenSlots)
--   with an owned, non-training pet eats one meal every Coins.MealSeconds (a server timer per place, random start
--   phase after a load; a NEW placement's first coin waits a full meal; the same key back in its place within one
--   meal keeps its timer: X5) and pops out one coin worth TycoonCatalog.CoinValue(home, PetPower(pet)) (Food x
--   PetPower x 1.25^stars; the pet's STORED evolution stage from DataService.GetEvolution), Lucky with
--   TycoonCatalog.LuckyChance (x Coins.LuckyMult). A place's pile holds PileSeconds(home) x that pet's coin rate;
--   full = the pet naps and eats nothing until scooped. Keys above the open count (LegacySlots ended) rest: they keep
--   their place but do not eat. No pet in the garden = no coins.
-- * The coin ledger (X4, exactly once): Home.CollectorCash IS the bank (persisted, delta-merged): the 1 s tick adds
--   every new coin to it in one MutateHome. The piles are SESSION memory (Coins.state[player]: a value and a coin
--   count per place + the Welcome-back pile) rebuilt from the bank as the Welcome-back pile on load, claim and
--   ProfileRebased, and always reconciled so that sum(piles) + welcome == CollectorCash. Scooping: a 0.25 s loop
--   reads the OWNER's HumanoidRootPart; every pile within ScoopRadius(home) horizontally and SCOOP_HEIGHT vertically
--   is paid: MutateHome(CollectorCash - take) then DataService.AddCash(take) in one non-yielding step, clamped to
--   the bank, refunded when AddCash fails; whole Cash only, fractions stay in their pile. No pickup remote (X1):
--   HomeAction "Collect" / Collect(player) = "scoop every pile in range" for old clients and tests. Only the plot's
--   owner is ever checked (X2). Offline coins (the Vault's OfflineEarnings on IncomePerSecond) go INTO the bank in
--   the same MutateHome that writes LastSeen (X6; the "Welcome back! Your pets made $X ..." toast).
-- * GardenSet (any role): slot 1..GardenSlots(home), an owned free copy, not a training key (DataService.TrainingKeys),
--   not a key in the caller's running battle (BattleService.KeysInBattle when it exists); nil / "" clears any slot.
-- * House tiers (every 10 Home Levels: Villa 10, Manor 20, Sky Castle 30) and the station caps per tier come from
--   TycoonCatalog (lock reasons on the pads). Prestige (Home Level 40 + Sky Castle): TycoonCatalog.StationsAfterPrestige
--   (decor kept, the Garden back at its ResetLevel 1 so the coins never stop), the bank and the piles zeroed, Cash to 0,
--   +1 star (coins x1.25 each), +1 garden place ("Garden place N unlocked!"), the Gems reward; at 1 star the Fusion
--   Machine pad unlocks. DataService.MutateHome clears LegacySlots / LegacyPrices itself when Prestige rises.
-- * The home portal (3.10): HomeAction "GoHome" / OpenHomePortal(player): refused in an obby match, in a battle or ring
--   run (InBattle), while locked in a portal party (PortalLocked), while dead; cooldown 3 s; one portal per player
--   (pressing again keeps the open one). It opens 6 studs ahead on the ground (server raycasts: forward stops 1.5
--   studs before a wall, down finds the floor, no floor -> the character's own spot) for 10 s as the player attribute
--   HomePortal = "x,y,z,yaw,closesAt". A 0.2 s loop checks ONLY the owner's root against open portals and teleports
--   them with SpotService.Teleport (home SpawnCFrame; without a home the suggested free gate + "Press E at the gate to
--   claim this home!"), writes PortalArrived = server time and fires PortalUsed. Zero server parts (HomePortalFx draws).
-- * Safe zones (3.11): nothing here starts damage or a fight; every teleport refuses InBattle.
-- * Remote HomeAction(action, arg): "Upgrade" stationId, "GardenSet" {slot, key|nil} (also {Slot =, Key =}),
--   "Collect", "Prestige", "GoHome". Types, ranges and NaN are checked; every action is rate limited (a per-action
--   cooldown plus a per-player burst budget); refusals answer with a side toast (repeated texts are throttled).
-- * Replication (5.3): the plot folder (SpotInfo.Folder) carries attributes for the clients, written only on change:
--   HomeLevel, Prestige, CollectorCash (the bank, whole), IncomePerSecond, GardenPets ("1=cat;3=fox@Golden", every
--   placed owned key incl. resting ones), GardenInfo ("1=12:0;3=20:1" level:stage per placed slot), GardenSlots (the
--   open place count), CoinPiles ("1=3;2=5F;4=2*;W=5": heap stage 0-5 per pile by coin count, F = full / the pet
--   naps, * = a Lucky coin in the pile, W = the Welcome-back pile while it holds >= $1). HomeBuilder.SetGarden(info,
--   valid, open) gets the placed keys and the open count. Nothing here moves parts (HomeFx animates on the client).
--
-- Public API (the contract, 5.4):
--   Init(lobbyInfo, deps)                deps = { DataService, PetService, SpotService, BattleService }
--   GetPlot(player) -> SpotInfo | nil    GetHome(player) -> home copy | nil
--   Buy(player, stationId) -> ok, newLevel | reason   (stations only: "Prestige" is refused, see the Prestige pad)
--   Collect(player) -> ok, amount | reason   scoops every pile in range of the owner
--   Prestige(player) -> ok, stars | reason
--   IncomePerSecond(player) -> cash/s, { Food, Pets, Lucky, Multiplier }
--   PileSeconds(player) -> seconds (+ CollectorCap alias), CoinsWaiting(player) -> whole Cash on the lawn
--   GardenSet(player, slot, key) -> ok, reason      OpenHomePortal(player) -> ok, reason   GoHome = OpenHomePortal
--   ClearCoins(player) (the developer reset: bank + piles to 0)
--   Signals HomeChanged(player), Claimed(player, spotInfo), Prestiged(player, stars), Released(player, spotInfo),
--           CoinsScooped(player, amount), PortalUsed(player)
-- Extras: Claim(player, index) -> ok, reason, Release(player), Piles(player) -> { [slot] = { Coins, Value, Lucky, Full,
--   Pos }, W = { Value, Pos } } (a copy of the session ledger: tests, the tutorial arrow).
--
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local TycoonService = {}
TycoonService.HomeChanged = Util.Signal() -- Fire(player)
TycoonService.Claimed = Util.Signal() -- Fire(player, spotInfo)
TycoonService.Prestiged = Util.Signal() -- Fire(player, stars)
TycoonService.Released = Util.Signal() -- Fire(player, spotInfo)  (extra)
TycoonService.CoinsScooped = Util.Signal() -- Fire(player, amount)  Phase 4: whole Cash scooped from the lawn
TycoonService.PortalUsed = Util.Signal() -- Fire(player)  Phase 4: the owner went through their home portal

local TICK = 1 -- seconds between coin ticks
local MAX_TICK_DT = 5 -- a stalled server never pays more than this many seconds in one tick
local LASTSEEN_EVERY = 15 -- seconds between Home.LastSeen refreshes while online (offline pay starts after 120 s)
local PROFILE_WAIT = 90 -- seconds a joining player's home is waited for (then ProfileRebased takes over)
local CLAIM_COOLDOWN = 0.5
local BUY_COOLDOWN = 0.2
local COLLECT_COOLDOWN = 0.5
local GARDEN_COOLDOWN = 0.2
local PRESTIGE_COOLDOWN = 1
local COLLECT_TOAST_GAP = 3 -- seconds between "scooped" toasts of the explicit Collect action
local BURST_SIZE = 10 -- HomeAction / prompt requests a player may send at once...
local BURST_REFILL = 5 -- ...refilled at this many per second
local TOAST_GAP = 1.5 -- the same refusal text is not repeated within this many seconds
local OFFLINE_TOAST_DELAY = 3 -- the HUD / toasts are up a moment after the profile loaded
local MAX_ID_LENGTH = 48
local MAX_ACTION_LENGTH = 24
local MAX_SLOT = 64
local GATE_PROMPT_LIFT = 3.5 -- the fallback ClaimPrompt anchor above the gate's ground point
local CLAIM_DISTANCE = 12
local CLAIM_SLACK = 15 -- studs past the prompt's MaxActivationDistance a claimer may stand (latency, big avatars)
local ATTR_IN_BATTLE = Config.Attr.InBattle or "InBattle" -- BattleService's player attribute (battle id)

local initialized = false
local running = false
local dataService = nil
local petService = nil
local spotService = nil
local battleService = nil -- BattleService module table (its Init runs after ours: every call is guarded)
local homeBuilder = nil
local catalog = nil -- TycoonCatalog
local petKeys = nil -- PetKeys (optional)
local petCatalog = nil -- PetCatalog (optional)
local notifyRemote = nil
local openPanelRemote = nil -- OpenPanel (the Prestige pad opens the Home window on its confirmation)
local spotList = {} -- [index] = SpotInfo (from lobbyInfo.Spots)

local plots = {} -- [Player] = index
local plotOwner = {} -- [index] = Player (this service's own view; survives SpotService's release order)
local built = {} -- [index] = { [stationId] = level } what HomeBuilder shows right now
local padSig = {} -- [index] = signature of the last SetPads
local shown = {} -- [index] = { Cash, Income, Level, Prestige, Garden, Open, Piles, Info } last replicated values
local fallbackPrompts = {} -- [index] = ClaimPrompt this service created (no HomeBuilder prompt)
local lastTick = {} -- [Player] = os.clock() of the last coin tick
local lastSeenAt = {} -- [Player] = os.clock() of the last LastSeen write
local offlineDone = {} -- [Player] = true once the offline earnings were settled for this session
local watching = {} -- [Player] = true while a join waiter runs
local cooldowns = {} -- [Player] = { [key] = os.clock() }
local budgets = {} -- [Player] = { Tokens, At }
local toastAt = {} -- [Player] = { [text] = os.clock() }
local departed = setmetatable({}, { __mode = "k" })
local hbWarned = {} -- [fnName] = count of warnings printed

-- Phase 4 helper tables (contract section 6: every new helper lives in Coins / Portal, not in a new local)
local Coins = {
	SCOOP_TICK = 0.25, -- seconds between owner proximity passes
	SCOOP_HEIGHT = 10, -- studs of vertical reach of a scoop
	MAX_POOPS_PER_TICK = 2, -- a stalled server catches up at most this many poops per slot per tick (3.5)
	DROPS_WRITE_GAP = 2, -- seconds between CoinDrops attribute writes (<= 0.5 / s per plot)
	state = {}, -- [Player] = the session ledger (see Coins.ensure)
}
local homeRoam = nil -- shared/HomeRoam (the deterministic roaming plans: poop times and points)
Coins.welcomedP5 = {} -- [Player] = true once the 'Your home got simpler!' toast was shown this session
-- old Phase 4 station ids an old client may still send: what they became (3.3 / FoldLegacy)
Coins.LEGACY_HOME = {
	Press2 = "Berry Farm", Press3 = "Berry Farm", Press4 = "Berry Farm", Collector = "Pet Garden",
	DecorLamps = "Fountain", DecorFlowers = "Yard Fence", DecorBanners = "Yard Fence",
}
local Portal = {
	TICK = 0.2, -- seconds between owner checks
	COOLDOWN = 3, -- contract 3.10 / X19: one portal request per 3 s
	ATTR_LOCKED = "PortalLocked", -- PortalService: locked on a portal pad for a party countdown
	AHEAD = 6, -- studs in front of the character
	WALL_GAP = 1.5, -- the portal stops this far before a wall
	OPEN_SECONDS = 10,
	ENTER_RADIUS = 3.5, -- horizontal studs from the portal point that count as "walked in"
	ENTER_HEIGHT = 5, -- vertical studs (the root stands ~3 studs over the floor)
	DROP = 24, -- studs the floor is searched for below a point
	open = {}, -- [Player] = { Pos = Vector3, Yaw, ClosesAt = os.clock() }
}

----------------------------------------------------------------------
-- Modules (other agents write some of them: every use is guarded)
----------------------------------------------------------------------

local function requireModule(container, name)
	local module = container and container:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	warn("[TycoonService] could not load " .. name .. ": " .. tostring(result))
	return nil
end

-- Calls HomeBuilder[fnName](...) under pcall. Missing functions are skipped quietly.
local function hb(fnName, ...)
	if not homeBuilder or type(homeBuilder[fnName]) ~= "function" then
		return nil
	end
	local ok, result = pcall(homeBuilder[fnName], ...)
	if not ok then
		local n = (hbWarned[fnName] or 0) + 1
		hbWarned[fnName] = n
		if n <= 3 then
			warn("[TycoonService] HomeBuilder." .. fnName .. " failed: " .. tostring(result))
		end
		return nil
	end
	return result
end

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function notify(player, text, kind, seconds)
	if not player or not player.Parent or type(text) ~= "string" then
		return
	end
	if not notifyRemote then
		local ok, remote = pcall(Remotes.Get, "Notify")
		if ok then
			notifyRemote = remote
		end
	end
	if notifyRemote then
		pcall(function()
			notifyRemote:FireClient(player, text, kind or "info", seconds or 3)
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

-- Per player burst budget shared by every HomeAction / prompt request.
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

local function money(n)
	if catalog and type(catalog.FormatCash) == "function" then
		local ok, text = pcall(catalog.FormatCash, n)
		if ok and type(text) == "string" then
			return text
		end
	end
	return "$" .. tostring(math.floor(tonumber(n) or 0))
end

-- 1.25 -> "1.25", 1.5625 -> "1.56", 2 -> "2"
local function multiplierText(mult)
	local text = string.format("%.2f", tonumber(mult) or 1)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

local function isPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent ~= nil and not departed[player]
end

local function getHome(player)
	if not dataService or type(dataService.GetHome) ~= "function" then
		return nil
	end
	local ok, home = pcall(dataService.GetHome, player)
	if ok and type(home) == "table" then
		return home
	end
	return nil
end

local function getProfile(player)
	if not dataService or type(dataService.GetProfile) ~= "function" then
		return nil
	end
	local ok, profile = pcall(dataService.GetProfile, player)
	if ok and type(profile) == "table" then
		return profile
	end
	return nil
end

local function mutateHome(player, fn)
	if not dataService or type(dataService.MutateHome) ~= "function" then
		return false
	end
	local ok, result = pcall(dataService.MutateHome, player, fn)
	return ok and result == true
end

local function getCash(player)
	if dataService and type(dataService.GetCash) == "function" then
		local ok, cash = pcall(dataService.GetCash, player)
		if ok and isFinite(cash) then
			return cash
		end
	end
	return 0
end

local function stationLevel(home, id)
	if catalog and type(catalog.StationLevel) == "function" then
		return catalog.StationLevel(home, id)
	end
	local v = type(home) == "table" and type(home.Stations) == "table" and home.Stations[id]
	return isFinite(v) and math.max(0, math.floor(v)) or 0
end

local function homeLevelOf(home)
	if catalog and type(catalog.HomeLevelOf) == "function" then
		return catalog.HomeLevelOf(home)
	end
	return 0
end

local function starsOf(home)
	local v = type(home) == "table" and home.Prestige
	if isFinite(v) and v > 0 then
		return math.floor(v)
	end
	return 0
end

local function stationName(id)
	local def = catalog and catalog.Get(id)
	return (def and def.Name) or tostring(id)
end

local function houseTierName(index)
	local tiers = catalog and catalog.HouseTiers
	local tier = type(tiers) == "table" and tiers[index]
	return (tier and tier.Name) or "house"
end

-- The bank: the Cash lying on the lawn (Home.CollectorCash), never negative or NaN.
local function bankOf(home)
	local v = type(home) == "table" and tonumber(home.CollectorCash) or 0
	if not isFinite(v) or v < 0 then
		return 0
	end
	return v
end

----------------------------------------------------------------------
-- Pets in the Garden
----------------------------------------------------------------------

local function validKeyString(key)
	return type(key) == "string" and key ~= "" and #key <= MAX_ID_LENGTH
end

-- def, tier of a pet key (any role; hybrids through PetKeys.DefOf); nil, nil, reason for junk keys / unknown pets.
local function petDefOf(key, profile)
	if not validKeyString(key) then
		return nil, nil, "Unknown pet"
	end
	local def, tier = nil, "Normal"
	if petKeys and type(petKeys.Parse) == "function" then
		local parsed = petKeys.Parse(key)
		if not parsed then
			return nil, nil, "Unknown pet"
		end
		tier = parsed.Tier or "Normal"
		if type(petKeys.DefOf) == "function" then
			local ok, result = pcall(petKeys.DefOf, key, profile)
			if ok and type(result) == "table" then
				def = result
			end
		end
	elseif petCatalog and type(petCatalog.Get) == "function" then
		def = petCatalog.Get(key)
	end
	if type(def) ~= "table" then
		return nil, nil, "Unknown pet"
	end
	return def, tier, nil
end

local function ownedCount(profile, key)
	if not profile or not validKeyString(key) then
		return 0
	end
	if petKeys and type(petKeys.Count) == "function" then
		local ok, n = pcall(petKeys.Count, profile, key)
		if ok and isFinite(n) then
			return n
		end
		return 0
	end
	local n = type(profile.Pets) == "table" and profile.Pets[key]
	return isFinite(n) and n or 0
end

local function petLevel(player, key)
	if dataService and type(dataService.GetPetLevel) == "function" then
		local ok, level = pcall(dataService.GetPetLevel, player, key)
		if ok and isFinite(level) and level >= 1 then
			return math.floor(level)
		end
	end
	return 1
end

-- The STORED evolution stage of a key (the boost counts only after EVOLVE was pressed, never from the level).
local function evolutionOf(player, key)
	if dataService and type(dataService.GetEvolution) == "function" then
		local ok, stage = pcall(dataService.GetEvolution, player, key)
		if ok and isFinite(stage) and stage > 0 then
			return math.floor(stage)
		end
	end
	return 0
end

-- { [key] = true } of the keys with a running training job: the ONE lock source (DataService.TrainingKeys).
local function trainingKeys(player)
	if dataService and type(dataService.TrainingKeys) == "function" then
		local ok, set = pcall(dataService.TrainingKeys, player)
		if ok and type(set) == "table" then
			return set
		end
	end
	return {}
end

local function gardenSlots(home)
	if catalog and type(catalog.GardenSlots) == "function" then
		return catalog.GardenSlots(home)
	end
	return 0
end

-- Every placed pet that counts: slots 1..MAX_SLOT of Home.Garden holding an owned key (one copy per slot) that is
-- not training (any role). Returns entries { [slot] = { Def, Level, Tier, Stage, Key } } (TycoonCatalog.PetPower
-- shapes; the catalog counts only entries[1 .. GardenSlots(home)], the rest rest) and valid { [slot] = key }.
local function gardenEntries(player, home, profile)
	local entries, valid = {}, {}
	local garden = type(home) == "table" and home.Garden
	if type(garden) ~= "table" then
		return entries, valid
	end
	local training = trainingKeys(player)
	local used = {}
	for slot = 1, MAX_SLOT do
		local key = garden[slot]
		if validKeyString(key) and not training[key] then
			local def, tier = petDefOf(key, profile)
			if def then
				used[key] = (used[key] or 0) + 1
				if used[key] <= ownedCount(profile, key) then
					entries[slot] = { Def = def, Level = petLevel(player, key), Tier = tier, Stage = evolutionOf(player, key), Key = key }
					valid[slot] = key
				end
			end
		end
	end
	return entries, valid
end

-- income per second (prestige multiplier applied), parts, valid garden map, entries
local function incomeOf(player, home)
	if not catalog or type(home) ~= "table" then
		return 0, { Food = 0, Pets = 0, Lucky = 1, Multiplier = 1 }, {}, {}
	end
	local entries, valid = gardenEntries(player, home, getProfile(player))
	local ok, income, parts = pcall(catalog.IncomePerSecond, home, entries, starsOf(home))
	if not ok or not isFinite(income) or income < 0 then
		return 0, { Food = 0, Pets = 0, Lucky = 1, Multiplier = 1 }, valid, entries
	end
	return income, parts, valid, entries
end

----------------------------------------------------------------------
-- The plot in the world (HomeBuilder) + replicated attributes
----------------------------------------------------------------------

local function plotInfo(index)
	if spotService and type(spotService.GetSpotByIndex) == "function" then
		local info = spotService.GetSpotByIndex(index)
		if info then
			return info
		end
	end
	return spotList[index]
end

local function setFolderAttr(info, name, value)
	local folder = info and info.Folder
	if typeof(folder) ~= "Instance" then
		return
	end
	pcall(function()
		if folder:GetAttribute(name) ~= value then
			folder:SetAttribute(name, value)
		end
	end)
end

local function gardenText(valid)
	local slots = {}
	for slot in pairs(valid) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	local parts = {}
	for _, slot in ipairs(slots) do
		parts[#parts + 1] = tostring(slot) .. "=" .. valid[slot]
	end
	return table.concat(parts, ";")
end

-- "1=12:0;3=20:1": level:stage per placed slot (GardenInfo)
local function gardenInfoText(entries)
	local slots = {}
	for slot in pairs(entries) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	local parts = {}
	for _, slot in ipairs(slots) do
		local e = entries[slot]
		parts[#parts + 1] = tostring(slot) .. "=" .. tostring(e.Level or 1) .. ":" .. tostring(e.Stage or 0)
	end
	return table.concat(parts, ";")
end

----------------------------------------------------------------------
-- Cloud Cash: the session ledger (Coins.state), the roaming epochs, the drops on the lawn, the scoop (Phase 5, 3.5)
----------------------------------------------------------------------

-- the shared server clock (workspace:GetServerTimeNow() on both sides; epochs ride in the Roam attribute)
function Coins.serverNow()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and isFinite(t) then
		return t
	end
	return os.time()
end

function Coins.seedOf(player)
	local id = tonumber(player and player.UserId) or 0
	return (math.floor(id) % 2147483646) + 1
end

function Coins.cycle()
	return (homeRoam and tonumber(homeRoam.Cycle)) or 24
end

function Coins.settle()
	return (homeRoam and tonumber(homeRoam.SettleSeconds)) or 20
end

function Coins.maxSlots()
	return (homeRoam and tonumber(homeRoam.MaxSlots)) or 12
end

-- epochs are rounded to 0.1 s so the server and every client compute from the SAME number (the attribute carries one decimal)
function Coins.roundEpoch(t)
	return math.floor(t * 10 + 0.5) / 10
end

function Coins.ensure(player)
	local st = Coins.state[player]
	if not st then
		st = {
			Drops = {}, -- [slot] = { { Cycle, Value, Lucky, Poops, X, Z }... } (creation order)
			Welcome = 0,
			Epoch = {}, -- [slot] = server time of cycle 0 (nil: no pet / resting)
			Nap = {}, -- [slot] = cycle the pet fell asleep in (no poop until a scoop below the cap)
			Done = {}, -- [slot] = the last cycle whose poop was decided
			Keys = {},
			Left = {}, -- [slot] = { Key, Epoch, Done, Nap, At } (churn: the same key back within a cycle keeps its epoch)
			Rng = Random.new(Coins.seedOf(player)),
			Fresh = true,
			BerryFrac = 0, -- the fraction of a berry the poops owe (whole berries go to DataService)
			RoamText = nil,
			DropsText = nil,
			DropsDirty = false,
			DropsAt = nil,
		}
		Coins.state[player] = st
	end
	return st
end

-- Rebuilds the ledger from the bank: every drop goes, the whole bank waits in the Welcome-back pile (on load, claim,
-- ProfileRebased, Prestige and the developer reset). The epochs start over (a fresh ledger staggers them).
function Coins.reset(player, bank)
	local st = Coins.ensure(player)
	st.Drops = {}
	st.Welcome = math.max(0, tonumber(bank) or 0)
	st.Epoch = {}
	st.Nap = {}
	st.Done = {}
	st.Keys = {}
	st.Left = {}
	st.Fresh = true
	return st
end

function Coins.slotValue(st, slot)
	local total = 0
	for _, d in ipairs(st.Drops[slot] or {}) do
		total = total + (d.Value or 0)
	end
	return total
end

function Coins.liveSum(st)
	local total = 0
	for _, list in pairs(st.Drops) do
		for _, d in ipairs(list) do
			total = total + (d.Value or 0)
		end
	end
	return total
end

-- Makes sum(drops) + welcome == bank. The bank only ever moves through this service's own MutateHome calls while
-- the plot is held, so normally this just sets the Welcome-back pile; when the bank shrank under the live drops
-- (another server scooped the same coins, a developer reset, a stale merge) the drops are trimmed from the newest.
function Coins.reconcile(st, bank)
	bank = math.max(0, tonumber(bank) or 0)
	local live = Coins.liveSum(st)
	if live <= bank + 1e-6 then
		st.Welcome = bank - live
		if st.Welcome < 1e-6 then
			st.Welcome = 0
		end
		return
	end
	st.Welcome = 0
	local over = live - bank
	for slot = MAX_SLOT, 1, -1 do
		local list = st.Drops[slot]
		if list then
			for i = #list, 1, -1 do
				if over <= 0 then
					break
				end
				local d = list[i]
				local cut = math.min(d.Value, over)
				d.Value = d.Value - cut
				over = over - cut
				if d.Value < 1e-6 then
					table.remove(list, i)
				end
			end
			if #list == 0 then
				st.Drops[slot] = nil
			end
		end
	end
end

-- the plot frame of a held plot (cached per ledger; a claim on another plot refreshes it)
function Coins.plotFrame(st, index)
	if st.Index == index and typeof(st.PlotCF) == "CFrame" then
		return st.PlotCF
	end
	local info = plotInfo(index)
	local plotCF = info and info.PlotCFrame
	if typeof(plotCF) ~= "CFrame" then
		return nil
	end
	st.Index = index
	st.PlotCF = plotCF
	st.WelcomePos = nil
	return plotCF
end

-- the world point of a plot-local (x, z) on the lawn
function Coins.worldPoint(st, index, x, z)
	local plotCF = Coins.plotFrame(st, index)
	if not plotCF or not isFinite(x) or not isFinite(z) then
		return nil
	end
	return plotCF:PointToWorldSpace(Vector3.new(x, 0, z))
end

function Coins.welcomePoint(st, index)
	if st.WelcomePos and st.Index == index then
		return st.WelcomePos
	end
	local plotCF = Coins.plotFrame(st, index)
	local def = catalog and catalog.Get("Garden")
	local local3 = def and def.Slot and def.Slot.WelcomePile
	if not plotCF or typeof(local3) ~= "Vector3" then
		return nil
	end
	st.WelcomePos = plotCF:PointToWorldSpace(local3)
	return st.WelcomePos
end

-- the drop stage (1..4) of `poops` poops by Coins.DropStages {1, 2, 4, 8}; 0 for a fraction left by a scoop
function Coins.stageOf(poops)
	local n = tonumber(poops) or 0
	local stages = catalog and catalog.Coins and catalog.Coins.DropStages or { 1, 2, 4, 8 }
	local stage = 0
	for i, need in ipairs(stages) do
		if n >= need then
			stage = i
		end
	end
	return stage
end

-- "1=812:1,813:2*;3=40:1;W=5" (slot = cycle:stage[* Lucky] per drop; W the Welcome-back pile while it holds >= $1)
function Coins.dropsText(st)
	local slots = {}
	for slot, list in pairs(st.Drops) do
		if #list > 0 then
			slots[#slots + 1] = slot
		end
	end
	table.sort(slots)
	local parts = {}
	for _, slot in ipairs(slots) do
		local items = {}
		for _, d in ipairs(st.Drops[slot]) do
			if (d.Poops or 0) >= 1 then
				items[#items + 1] = tostring(d.Cycle) .. ":" .. tostring(Coins.stageOf(d.Poops)) .. (d.Lucky and "*" or "")
			end
		end
		if #items > 0 then
			parts[#parts + 1] = tostring(slot) .. "=" .. table.concat(items, ",")
		end
	end
	if (st.Welcome or 0) >= 1 then
		parts[#parts + 1] = "W=5"
	end
	return table.concat(parts, ";")
end

-- "1=1760001234.5;3=1760001240.0:N812" (slot = epoch, one decimal; :N<cycle> while the pet naps)
function Coins.roamText(st)
	local slots = {}
	for slot in pairs(st.Epoch) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	local parts = {}
	for _, slot in ipairs(slots) do
		local text = tostring(slot) .. "=" .. string.format("%.1f", st.Epoch[slot])
		if st.Nap[slot] then
			text = text .. ":N" .. tostring(st.Nap[slot])
		end
		parts[#parts + 1] = text
	end
	return table.concat(parts, ";")
end

-- Replicates the coin numbers of a plot (written only on change): CollectorCash (the bank, whole), IncomePerSecond,
-- RoamSeed / RoamVersion, Roam, CoinDrops (<= one write per Coins.DROPS_WRITE_GAP), BerryCap, GardenInfo, GardenSlots.
function Coins.show(index, st, home, income, entries, player)
	local info = plotInfo(index)
	if not info then
		return
	end
	local s = shown[index]
	if not s then
		s = {}
		shown[index] = s
	end
	local whole = math.floor(bankOf(home))
	if s.Cash ~= whole then
		s.Cash = whole
		setFolderAttr(info, "CollectorCash", whole)
	end
	local rate = math.floor((income or 0) * 10 + 0.5) / 10
	if s.Income ~= rate then
		s.Income = rate
		setFolderAttr(info, "IncomePerSecond", rate)
	end
	if player then
		local seed = Coins.seedOf(player)
		if s.RoamSeed ~= seed then
			s.RoamSeed = seed
			setFolderAttr(info, "RoamSeed", seed)
		end
		local version = (homeRoam and homeRoam.Version) or 0
		if s.RoamVersion ~= version then
			s.RoamVersion = version
			setFolderAttr(info, "RoamVersion", version)
		end
	end
	local roam = Coins.roamText(st)
	if s.Roam ~= roam then
		s.Roam = roam
		setFolderAttr(info, "Roam", roam)
	end
	local drops = Coins.dropsText(st)
	if s.Drops ~= drops then
		local now = os.clock()
		if st.DropsAt == nil or now - st.DropsAt >= Coins.DROPS_WRITE_GAP then
			s.Drops = drops
			st.DropsAt = now
			st.DropsDirty = false
			setFolderAttr(info, "CoinDrops", drops)
		else
			st.DropsDirty = true -- the next tick after the gap writes it
		end
	else
		st.DropsDirty = false
	end
	if catalog and type(catalog.BasketCap) == "function" then
		local okCap, cap = pcall(catalog.BasketCap, home, income or 0)
		if okCap and isFinite(cap) then
			cap = math.floor(cap)
			if s.BerryCap ~= cap then
				s.BerryCap = cap
				setFolderAttr(info, "BerryCap", cap)
			end
		end
	end
	local infoText = gardenInfoText(entries or {})
	if s.Info ~= infoText then
		s.Info = infoText
		setFolderAttr(info, "GardenInfo", infoText)
	end
	local open = gardenSlots(home)
	if s.Open ~= open then
		s.Open = open
		setFolderAttr(info, "GardenSlots", open)
	end
end

-- The epochs follow the placed keys: a NEW key in a slot gets Epoch = now + SettleSeconds (its first poop >= a full
-- cycle later: X5 / Y8); the same key back in its slot within one cycle keeps its old epoch (and its done / nap
-- marks: removing and re-placing a pet right after a poop gains nothing). Keys found on a fresh ledger (load / claim /
-- rebase) get a staggered start so a dozen pets do not all poop in the same second. A key resting above the open
-- count (`open`) owns no epoch: the place that opens later (a Prestige) starts with a settle, never with a backlog.
function Coins.followKeys(st, valid, now, cycle, open)
	for slot = 1, MAX_SLOT do
		local key = valid[slot]
		local was = st.Keys[slot]
		if key ~= was then
			if was ~= nil then
				st.Left[slot] = { Key = was, Epoch = st.Epoch[slot], Done = st.Done[slot], Nap = st.Nap[slot], At = now }
			end
			st.Keys[slot] = key
			if key ~= nil then
				local left = st.Left[slot]
				if left and left.Key == key and left.Epoch and now - left.At <= cycle then
					st.Epoch[slot] = left.Epoch
					st.Done[slot] = left.Done
					st.Nap[slot] = left.Nap
				elseif st.Fresh then
					st.Epoch[slot] = Coins.roundEpoch(now + st.Rng:NextNumber() * cycle)
					st.Done[slot] = -1
					st.Nap[slot] = nil
				else
					st.Epoch[slot] = Coins.roundEpoch(now + Coins.settle())
					st.Done[slot] = -1
					st.Nap[slot] = nil
				end
				st.Left[slot] = nil
			else
				st.Epoch[slot] = nil
				st.Done[slot] = nil
				st.Nap[slot] = nil
			end
		end
		if open ~= nil and slot > open and st.Epoch[slot] ~= nil then
			st.Epoch[slot] = nil -- resting: no poop is owed while the place is closed
			st.Done[slot] = nil
			st.Nap[slot] = nil
		end
	end
	st.Fresh = false
end

-- the lawn cap of one slot: PileSeconds(home) of that pet's coin rate (Lucky counted at its expected value)
function Coins.capOf(home, coin)
	local meal = catalog.Coins.MealSeconds
	return catalog.PileSeconds(home) * coin / meal * catalog.LuckyEV(home)
end

-- A napping slot wakes when its lawn value is below its cap again: the pet walks back from where it slept (the nap
-- cycle's OutLen / Speed) and the cycles start over from the new epoch. Returns true when something changed.
function Coins.wake(st, seed, slot, now, cap)
	local napCycle = st.Nap[slot]
	if not napCycle then
		return false
	end
	if Coins.slotValue(st, slot) >= cap - 1e-9 then
		return false
	end
	local back = Coins.cycle()
	local plan = homeRoam and homeRoam.Plan(seed, slot, napCycle)
	if plan and isFinite(plan.OutLen) and isFinite(plan.Speed) and plan.Speed > 0 then
		back = math.max(0, math.min(back, plan.OutLen / plan.Speed))
	end
	st.Nap[slot] = nil
	st.Epoch[slot] = Coins.roundEpoch(now + back)
	st.Done[slot] = -1
	return true
end

-- The poops of one tick: for every OPEN place with a pet, every poop whose time (HomeRoam.PoopTime on the slot's
-- epoch) has come drops Cloud Cash at the plan's poop point (Lucky with LuckyChance), at most MAX_POOPS_PER_TICK per
-- slot per tick (a stalled server catches up a little at a time). A slot whose lawn value reached its cap naps
-- instead (`:N<cycle>` in Roam, no poop) until a scoop below the cap wakes it. Returns the Cash of the new poops and
-- the list of { Slot, Cycle, Value, Lucky, X, Z } to lay down once the bank took them.
function Coins.poops(st, home, entries, valid, now, seed)
	if not homeRoam or type(homeRoam.PoopTime) ~= "function" then
		return 0, {}
	end
	local stars = starsOf(home)
	local lucky = catalog.LuckyChance(home)
	local luckyMult = catalog.Coins.LuckyMult
	local poopMeals = catalog.Coins.PoopMeals or 3
	local open = math.min(gardenSlots(home), MAX_SLOT, Coins.maxSlots())
	local added, drops = 0, {}
	for slot = 1, open do
		local entry = valid[slot] and entries[slot]
		if entry then
			if not st.Epoch[slot] then
				-- a place that just opened (or an epoch dropped while resting): a settle first, never a backlog
				st.Epoch[slot] = Coins.roundEpoch(now + Coins.settle())
				st.Done[slot] = -1
				st.Nap[slot] = nil
			end
			local coin = catalog.CoinValue(home, catalog.PetPower(entry), stars)
			local cap = Coins.capOf(home, coin)
			Coins.wake(st, seed, slot, now, cap)
			local epoch = st.Epoch[slot]
			local n = 0
			while n < Coins.MAX_POOPS_PER_TICK and not st.Nap[slot] do
				local c = (st.Done[slot] or -1) + 1
				local at = homeRoam.PoopTime(seed, slot, epoch, c)
				if not isFinite(at) or at > now then
					break
				end
				n = n + 1
				if coin <= 0 then
					st.Done[slot] = c
				elseif Coins.slotValue(st, slot) >= cap - 1e-9 then
					st.Nap[slot] = c -- full lawn: the pet naps where it stands until a scoop below the cap
				else
					local plan = homeRoam.Plan(seed, slot, c)
					local pt = plan and plan.Poop
					if not pt then
						st.Done[slot] = c
					else
						local v = coin * poopMeals
						local isLucky = false
						if lucky > 0 and st.Rng:NextNumber() < lucky then
							v = v * luckyMult
							isLucky = true
						end
						drops[#drops + 1] = { Slot = slot, Cycle = c, Value = v, Lucky = isLucky, X = pt.x or pt[1], Z = pt.z or pt[2] }
						added = added + v
						st.Done[slot] = c
					end
				end
			end
			-- never owe more than two cycles of backlog (a long stall is forgiven, the pets keep their rhythm)
			local lastDue = (st.Done[slot] or -1)
			if not st.Nap[slot] then
				local late = homeRoam.PoopTime(seed, slot, epoch, lastDue + 1)
				while isFinite(late) and now - late > 2 * Coins.cycle() do
					lastDue = lastDue + 1
					late = homeRoam.PoopTime(seed, slot, epoch, lastDue + 1)
				end
				st.Done[slot] = lastDue
			end
		end
	end
	return added, drops
end

-- Lays the new poops on the lawn: a slot keeps at most Coins.DropsPerPet drops, a further poop merges into the
-- NEAREST drop of that slot (its value and poop count grow, its cycle id stays).
function Coins.applyDrops(st, drops)
	local maxDrops = (catalog.Coins and catalog.Coins.DropsPerPet) or 3
	for _, d in ipairs(drops) do
		local list = st.Drops[d.Slot]
		if not list then
			list = {}
			st.Drops[d.Slot] = list
		end
		local real = 0
		for _, e in ipairs(list) do
			if (e.Poops or 0) >= 1 then
				real = real + 1
			end
		end
		if real < maxDrops then
			list[#list + 1] = { Cycle = d.Cycle, Value = d.Value, Lucky = d.Lucky == true, Poops = 1, X = d.X, Z = d.Z }
		else
			local best, bestD = nil, math.huge
			for _, e in ipairs(list) do
				if (e.Poops or 0) >= 1 then
					local dx, dz = (e.X or 0) - d.X, (e.Z or 0) - d.Z
					local dist = dx * dx + dz * dz
					if dist < bestD then
						best, bestD = e, dist
					end
				end
			end
			best.Value = best.Value + d.Value
			best.Poops = (best.Poops or 0) + 1
			if d.Lucky then
				best.Lucky = true
			end
		end
	end
end

-- Berries from the poops of one tick: value x Berries.Share whole berries into Profile.Berries (the fraction stays in
-- the ledger), clamped so the poops never lift Berries above BasketCap (a cap below the berries removes none; the lost
-- berries toast "Basket full!" once until the basket has room again). Non-yielding.
function Coins.berries(player, st, home, income, added)
	local B = catalog.Berries
	if type(B) ~= "table" or not dataService or type(dataService.AddBerries) ~= "function" then
		return 0
	end
	local pot = (st.BerryFrac or 0) + added * (tonumber(B.Share) or 0)
	local whole = math.floor(pot + 1e-9)
	st.BerryFrac = math.max(0, pot - whole)
	if whole < 1 then
		return 0
	end
	local have = 0
	if type(dataService.GetBerries) == "function" then
		local okH, h = pcall(dataService.GetBerries, player)
		if okH and isFinite(h) then
			have = h
		end
	end
	local cap = whole + have
	if type(catalog.BasketCap) == "function" then
		local okCap, c = pcall(catalog.BasketCap, home, income or 0)
		if okCap and isFinite(c) then
			cap = c
		end
	end
	local room = math.max(0, math.floor(cap) - have)
	local give = math.min(whole, room)
	if give < whole then
		if not st.BasketFull then
			st.BasketFull = true
			notify(player, "Basket full! Feed your pets", "info", 4)
		end
	elseif have + give < cap then
		st.BasketFull = nil
	end
	if give < 1 then
		return 0
	end
	local okAdd, wrote = pcall(dataService.AddBerries, player, give)
	if not okAdd or wrote ~= true then
		st.BerryFrac = st.BerryFrac + give -- not banked (not loaded yet): the next tick tries again
		return 0
	end
	return give
end

-- Scoops every drop within ScoopRadius(home) (horizontally; SCOOP_HEIGHT vertically) of the OWNER's root: the bank
-- pays `take` (whole Cash, clamped to the bank) in one MutateHome, then AddCash; refunded when AddCash fails.
-- Fractions stay on the lawn (an invisible drop below $1). Napping slots whose lawn fell under the cap wake up.
-- Returns ok, amount | reason.
function Coins.scoop(player, index)
	local st = Coins.state[player]
	local info = plotInfo(index)
	if not st or not info then
		return false, "Nothing to scoop yet"
	end
	local root = Util.GetRoot(player)
	if not root then
		return false, "Nothing to scoop yet"
	end
	local home = getHome(player)
	if not home then
		return false, "Your home is still loading..."
	end
	local radius = catalog.ScoopRadius(home)
	local at = root.Position
	local function inRange(pos)
		if typeof(pos) ~= "Vector3" then
			return false
		end
		local dx, dz = pos.X - at.X, pos.Z - at.Z
		return math.sqrt(dx * dx + dz * dz) <= radius and math.abs(pos.Y - at.Y) <= Coins.SCOOP_HEIGHT
	end
	local hit, sum = {}, 0
	local slots = {}
	for slot in pairs(st.Drops) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	for _, slot in ipairs(slots) do
		for i, d in ipairs(st.Drops[slot]) do
			if d.Value > 0 and inRange(Coins.worldPoint(st, index, d.X, d.Z)) then
				hit[#hit + 1] = { Slot = slot, Index = i, Drop = d }
				sum = sum + d.Value
			end
		end
	end
	local welcomeIn = st.Welcome > 0 and inRange(Coins.welcomePoint(st, index))
	if welcomeIn then
		sum = sum + st.Welcome
	end
	local take = math.floor(sum + 1e-6)
	if take < 1 then
		return false, "Nothing to scoop yet"
	end
	local paid = 0
	local wrote = mutateHome(player, function(live)
		local cur = bankOf(live)
		paid = math.min(take, math.floor(cur + 1e-6)) -- clamped to the bank (X4)
		if paid < 1 then
			return false
		end
		live.CollectorCash = cur - paid
		return true
	end)
	if not wrote or paid < 1 then
		Coins.reconcile(st, bankOf(getHome(player) or home)) -- the bank holds less than the drops claim
		return false, "Nothing to scoop yet"
	end
	if not dataService.AddCash(player, paid) then
		mutateHome(player, function(live)
			live.CollectorCash = bankOf(live) + paid -- the Cash could not be banked: back onto the lawn
			return true
		end)
		return false, "Could not bank the Cash right now"
	end
	-- the drops in range are gone; the fraction below one Cash stays in the first of them (invisible: no poops)
	local left = math.max(0, sum - paid)
	local first = hit[1]
	for i = #hit, 1, -1 do
		local h = hit[i]
		local list = st.Drops[h.Slot]
		if list then
			for j = #list, 1, -1 do
				if list[j] == h.Drop then
					table.remove(list, j)
				end
			end
			if #list == 0 then
				st.Drops[h.Slot] = nil
			end
		end
	end
	if welcomeIn then
		st.Welcome = 0
	end
	if left > 1e-6 then
		if first then
			local list = st.Drops[first.Slot]
			if not list then
				list = {}
				st.Drops[first.Slot] = list
			end
			table.insert(list, 1, { Cycle = first.Drop.Cycle, Value = left, Lucky = false, Poops = 0, X = first.Drop.X, Z = first.Drop.Z })
		else
			st.Welcome = left
		end
	end
	Coins.reconcile(st, bankOf(getHome(player) or home))
	-- napping pets whose lawn has room again walk back to the bowl
	local seed = Coins.seedOf(player)
	local now = Coins.serverNow()
	local _, _, valid, entries = incomeOf(player, home)
	for slot in pairs(st.Nap) do
		local entry = valid[slot] and entries[slot]
		if entry then
			local coin = catalog.CoinValue(home, catalog.PetPower(entry), starsOf(home))
			Coins.wake(st, seed, slot, now, Coins.capOf(home, coin))
		else
			Coins.wake(st, seed, slot, now, math.huge)
		end
	end
	TycoonService.CoinsScooped:Fire(player, paid)
	return true, paid
end

-- The 0.25 s owner proximity pass over every held plot (X1 / X2: no remote, only the owner's root).
function Coins.scoopAll()
	for player, index in pairs(plots) do
		local st = Coins.state[player]
		if st and player.Parent and not departed[player] and (st.Welcome >= 1 or next(st.Drops) ~= nil) then
			local ok, paid = pcall(Coins.scoop, player, index)
			if not ok then
				warn("[TycoonService] scoop failed: " .. tostring(paid))
			elseif paid == true then
				local home = getHome(player)
				if home then
					local income, _, _, entries = incomeOf(player, home)
					Coins.show(index, st, home, income, entries, player)
				end
			end
		end
	end
end

function Coins.loop()
	while running do
		task.wait(Coins.SCOOP_TICK)
		if not running then
			break
		end
		local ok, err = pcall(Coins.scoopAll)
		if not ok then
			warn("[TycoonService] scoop pass failed: " .. tostring(err))
		end
	end
end

----------------------------------------------------------------------
-- The plot sync
----------------------------------------------------------------------

local function padSignature(pads)
	local parts = {}
	for i, pad in ipairs(pads) do
		parts[i] = tostring(pad.StationId) .. ":" .. tostring(pad.NextLevel) .. ":" .. tostring(pad.Price) .. ":" .. tostring(pad.Locked or "")
	end
	return table.concat(parts, "|")
end

-- Brings the plot in line with the home: stations (diff only), pads, coins, attributes, garden, nameplate.
-- Returns true when a station changed.
local function syncPlot(player, home, income, valid, entries)
	local index = plots[player]
	local info = index and plotInfo(index)
	if not info or type(home) ~= "table" or not catalog then
		return false
	end
	local map = built[index]
	if not map then
		map = {}
		built[index] = map
	end
	local changed = false
	for _, def in ipairs(catalog.Stations) do
		local id = def.Id
		local level = stationLevel(home, id)
		if (map[id] or 0) ~= level then
			map[id] = level
			hb("SetStation", info, id, level)
			changed = true
		end
	end
	local okPads, pads = pcall(catalog.AvailablePads, home)
	if okPads and type(pads) == "table" then
		local sig = padSignature(pads)
		if padSig[index] ~= sig then
			padSig[index] = sig
			hb("SetPads", info, pads)
		end
	end
	if income == nil or valid == nil or entries == nil then
		local parts
		income, parts, valid, entries = incomeOf(player, home)
	end
	local st = Coins.ensure(player)
	if st.Fresh then
		-- a rebuilt ledger (claim, load, rebase, prestige, reset): the keys already in the garden get their random
		-- start phase NOW, so a pet placed a moment later waits a full meal like every new placement (X5)
		Coins.followKeys(st, valid or {}, Coins.serverNow(), Coins.cycle(), gardenSlots(home))
	end
	Coins.reconcile(st, bankOf(home))
	Coins.show(index, st, home, income, entries, player)
	local s = shown[index] or {}
	shown[index] = s
	local level, stars = homeLevelOf(home), starsOf(home)
	if s.Level ~= level or s.Prestige ~= stars then
		s.Level, s.Prestige = level, stars
		setFolderAttr(info, "HomeLevel", level)
		setFolderAttr(info, "Prestige", stars)
		if spotService and type(spotService.Refresh) == "function" then
			pcall(spotService.Refresh, player)
		end
	end
	local garden = gardenText(valid or {})
	local open = gardenSlots(home)
	if s.Garden ~= garden or s.GardenOpen ~= open then
		s.Garden = garden
		s.GardenOpen = open
		setFolderAttr(info, "GardenPets", garden)
		hb("SetGarden", info, valid or {}, open)
	end
	return changed
end

local function resetPlotState(index)
	built[index] = nil
	padSig[index] = nil
	shown[index] = nil
end

local function clearPlotAttributes(info)
	for _, name in ipairs({ "HomeLevel", "Prestige", "CollectorCash", "IncomePerSecond", "GardenPets", "GardenInfo", "GardenSlots", "RoamSeed", "RoamVersion", "Roam", "CoinDrops", "BerryCap" }) do
		setFolderAttr(info, name, nil)
	end
end

----------------------------------------------------------------------
-- Gate prompts
----------------------------------------------------------------------

local function findPrompt(container, name)
	if typeof(container) ~= "Instance" then
		return nil
	end
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == name then
			return d
		end
	end
	return nil
end

-- ClaimPrompts HomeBuilder built outside the spot folders, by their SpotIndex attribute (one scan at Init).
local function claimPromptsBySpot()
	local out = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
			local index = d:GetAttribute("SpotIndex")
			if type(index) == "number" then
				out[index] = d
			end
		end
	end
	return out
end

-- A plain ClaimPrompt on the gate when HomeBuilder did not build one (or is missing).
local function ensureClaimPrompt(index, info, existing)
	if findPrompt(info.Folder, "ClaimPrompt") or (existing and existing[index]) then
		return
	end
	local gate = nil
	if spotService and type(spotService.GateCFrame) == "function" then
		gate = spotService.GateCFrame(info)
	end
	if typeof(gate) ~= "CFrame" then
		gate = typeof(info.GateCFrame) == "CFrame" and info.GateCFrame or info.SpawnCFrame
	end
	if typeof(gate) ~= "CFrame" or typeof(info.Folder) ~= "Instance" then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "ClaimAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = gate * CFrame.new(0, GATE_PROMPT_LIFT, 0)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimPrompt"
	prompt.ActionText = "Claim Home"
	prompt.ObjectText = "Free home"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = CLAIM_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("SpotIndex", index)
	prompt.Parent = anchor
	anchor.Parent = info.Folder
	fallbackPrompts[index] = prompt
end

local function setFallbackPrompt(index, owner)
	local prompt = fallbackPrompts[index]
	if not prompt or not prompt.Parent then
		return
	end
	pcall(function()
		prompt.Enabled = owner == nil
		prompt.ObjectText = "Free home"
	end)
end

----------------------------------------------------------------------
-- Claim / release
----------------------------------------------------------------------

local function validIndex(index)
	return type(index) == "number" and index == index and index == math.floor(index) and plotInfo(index) ~= nil
end

-- The one-time welcome toast of a migrated Phase 3 veteran (contract 4.3): Migrations.P4Veteran owes it,
-- P4Welcome marks it shown (a union in the merge: never twice, also across servers).
local function welcomeVeteran(player)
	if not dataService or type(dataService.IsMigrated) ~= "function" or type(dataService.MarkMigrated) ~= "function" then
		return false
	end
	local okV, veteran = pcall(dataService.IsMigrated, player, "P4Veteran")
	local okW, welcomed = pcall(dataService.IsMigrated, player, "P4Welcome")
	if not okV or not okW or veteran ~= true or welcomed ~= false then
		return false
	end
	local okMark, marked = pcall(dataService.MarkMigrated, player, "P4Welcome")
	if not okMark or marked ~= true then
		return false
	end
	notify(player, "Welcome to the new home! Your presses grew into food plants, the Collector is now a Coin Magnet, and your old Collector Cash waits in a coin pile by your garden. Put pets in your garden: they make the money now!", "good", 9)
	return true
end

-- The one-time 'Your home got simpler!' toast of a Phase 4 home folded by THIS session's P5Home step
-- (DataService.MigratedNow(player, "P5Home") answers only in the session that ran the fold for the first time).
local function welcomeP5(player)
	if Coins.welcomedP5[player] or not dataService or type(dataService.MigratedNow) ~= "function" then
		return false
	end
	local ok, info = pcall(dataService.MigratedNow, player, "P5Home")
	if not ok or type(info) ~= "table" or info.FirstTime ~= true then
		return false
	end
	if info.Folded ~= true and info.Veteran ~= true and (tonumber(info.Berries) or 0) < 1 then
		return false -- a brand-new profile marked on its first load: nothing changed for this player
	end
	Coins.welcomedP5[player] = true
	notify(player, "Your home got simpler! Your plants grew into one Berry Farm and your garden pets now roam your yard. Old snacks count as berries, and feeding is free: berries!", "good", 9)
	return true
end

function TycoonService.Claim(player, index)
	if not initialized or not spotService or type(spotService.Claim) ~= "function" then
		return false, "Homes are not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	if not validIndex(index) then
		return false, "Unknown home"
	end
	if plots[player] then
		if plots[player] == index then
			return false, "This is already your home"
		end
		return false, "You already have a home"
	end
	if player:GetAttribute(Config.Attr.InMatch) == true then
		return false, "Finish your match first"
	end
	local home = getHome(player)
	if not home then
		return false, "Your home is still loading..."
	end
	local ok, reason = spotService.Claim(player, index)
	if not ok then
		return false, reason or "This home is taken"
	end
	local info = plotInfo(index)
	plots[player] = index
	plotOwner[index] = player
	lastTick[player] = os.clock()
	-- Home.Level always mirrors the stations (an old or hand-edited save may disagree)
	local level = homeLevelOf(home)
	if home.Level ~= level then
		mutateHome(player, function(live)
			live.Level = homeLevelOf(live)
			return true
		end)
	end

	-- a clean plot, then the saved build on top of it; the coins waiting in the bank become the Welcome-back pile
	hb("ClearPlot", info)
	resetPlotState(index)
	hb("SetOwner", info, player)
	setFallbackPrompt(index, player)
	Coins.reset(player, bankOf(home))
	local income, _, valid, entries = incomeOf(player, home)
	syncPlot(player, home, income, valid, entries)

	TycoonService.Claimed:Fire(player, info)
	TycoonService.HomeChanged:Fire(player)
	if level > 0 then
		notify(player, "Welcome home! Rebuilt at Home Level " .. level .. ".", "good", 5)
	else
		notify(player, "Welcome home! Use the glowing pads to build.", "good", 6)
	end
	welcomeVeteran(player)
	welcomeP5(player)
	return true, nil
end

-- Clears this service's view of a plot and the build in the world (only while `player` still holds it).
local function dropPlot(player, index)
	if not index or plotOwner[index] ~= player then
		return nil
	end
	plotOwner[index] = nil
	if plots[player] == index then
		plots[player] = nil
	end
	Coins.state[player] = nil -- the piles are session memory: the bank waits as the Welcome-back pile next time
	local info = plotInfo(index)
	if info then
		hb("ClearPlot", info)
		hb("SetOwner", info, nil)
		clearPlotAttributes(info)
	end
	resetPlotState(index)
	setFallbackPrompt(index, nil)
	return info
end

function TycoonService.Release(player)
	if not player then
		return
	end
	local index = plots[player]
	plots[player] = nil
	local info = dropPlot(player, index)
	if spotService and type(spotService.Release) == "function" and spotService.GetSpot and spotService.GetSpot(player) then
		pcall(spotService.Release, player)
	end
	if info then
		TycoonService.Released:Fire(player, info)
	end
end

-- The prompt's world position (its part or attachment), or nil.
local function promptPosition(prompt)
	local parent = prompt.Parent
	if typeof(parent) ~= "Instance" then
		return nil
	end
	if parent:IsA("BasePart") then
		return parent.Position
	end
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	if parent:IsA("Model") then
		local ok, pivot = pcall(function()
			return parent:GetPivot()
		end)
		if ok and typeof(pivot) == "CFrame" then
			return pivot.Position
		end
	end
	return nil
end

-- A claim needs the player AT the gate (the engine checks prompt range too; this also covers a stray trigger).
local function nearPrompt(player, prompt)
	local at = promptPosition(prompt)
	local root = Util.GetRoot(player)
	if not at or not root then
		return at == nil -- no position to compare: allow; no character: refuse
	end
	local reach = (tonumber(prompt.MaxActivationDistance) or CLAIM_DISTANCE) + CLAIM_SLACK
	return (root.Position - at).Magnitude <= reach
end

local function onClaimPrompt(player, index, prompt)
	if prompt and not nearPrompt(player, prompt) then
		return
	end
	if not cooldown(player, "Claim", CLAIM_COOLDOWN) or not spend(player) then
		return
	end
	local ok, reason = TycoonService.Claim(player, index)
	if not ok then
		toastOnce(player, reason or "You cannot claim this home", "bad")
	end
end

----------------------------------------------------------------------
-- Purchases
----------------------------------------------------------------------

local function milestoneToasts(player, before, after)
	local levelBefore, levelAfter = homeLevelOf(before), homeLevelOf(after)
	local houseBefore, houseAfter = stationLevel(before, "House"), stationLevel(after, "House")
	if houseAfter > houseBefore and houseAfter >= 2 then
		notify(player, houseTierName(houseAfter) .. " built! Stations can level higher.", "good", 5)
	end
	local tiers = catalog.HouseTiers or {}
	for i, tier in ipairs(tiers) do
		local need = tonumber(tier.HomeLevel) or 0
		if i >= 2 and need > 0 and levelBefore < need and levelAfter >= need and houseAfter < i then
			notify(player, "Home Level " .. need .. ": the " .. tostring(tier.Name) .. " can be built!", "good", 5)
		end
	end
	if type(catalog.CanPrestige) == "function" then
		local wasReady = catalog.CanPrestige(before)
		local isReady = catalog.CanPrestige(after)
		if isReady and not wasReady then
			notify(player, "Prestige is ready at your home!", "good", 6)
		end
	end
	if stationLevel(before, "Garden") < 1 and stationLevel(after, "Garden") >= 1 then
		notify(player, "Put pets in your Pet Garden: they eat and pop out rainbow coins!", "info", 6)
	end
end

function TycoonService.Buy(player, stationId)
	if not initialized or not catalog then
		return false, "Homes are not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	if type(stationId) ~= "string" or #stationId > MAX_ID_LENGTH then
		return false, "Unknown station"
	end
	if stationId == "Prestige" then
		-- never a one-press reset: Prestige() / HomeAction "Prestige" (the Home window's confirm button) do that
		return false, "Prestige from the Home window (it shows what resets first)"
	end
	local def = catalog.Get(stationId)
	if not def and Coins.LEGACY_HOME[stationId] then
		-- an old client's pad id (Phase 4 presses, Collector, old decor): the fold moved it into a Phase 5 station
		return false, "That station is now part of the " .. Coins.LEGACY_HOME[stationId]
	end
	if not def or def.Kind == "Prestige" then
		return false, "Unknown station"
	end
	if not plots[player] then
		return false, "Claim a home first (E at a free gate)"
	end
	local home = getHome(player)
	if not home then
		return false, "Your home is still loading..."
	end
	-- CheckPurchase answers the STAR price (TycoonCatalog.PriceAt: x1.5 per star unless Home.LegacyPrices)
	local ok, price, reason = catalog.CheckPurchase(home, stationId)
	if not ok then
		return false, reason or "Not available yet"
	end
	price = tonumber(price) or 0
	if not isFinite(price) or price < 0 then
		return false, "Not available yet"
	end
	price = math.ceil(price)
	if price > getCash(player) then
		return false, "Not enough Cash: need " .. money(price)
	end
	local level = stationLevel(home, stationId)

	-- check + pay + write in ONE non-yielding step (MutateHome runs fn synchronously)
	local spent = false
	local wrote = mutateHome(player, function(live)
		if stationLevel(live, stationId) ~= level then
			return false
		end
		local okLive, priceLive = catalog.CheckPurchase(live, stationId)
		if not okLive or math.ceil(tonumber(priceLive) or -1) ~= price then
			return false
		end
		if price > 0 then
			if not dataService.SpendCash(player, price) then
				return false
			end
			spent = true
		end
		if type(live.Stations) ~= "table" then
			live.Stations = {}
		end
		live.Stations[stationId] = level + 1
		live.Level = homeLevelOf(live)
		if offlineDone[player] then
			live.LastSeen = os.time() -- income just rose: the next offline payout starts from here
		end
		return true
	end)
	if not wrote then
		if spent then
			dataService.AddCash(player, price) -- the home write was refused: give the cash back
		end
		if price > getCash(player) then
			return false, "Not enough Cash: need " .. money(price)
		end
		return false, "Could not build that right now"
	end

	local after = getHome(player) or home
	syncPlot(player, after)
	local newLevel = level + 1
	if level == 0 then
		notify(player, "Built " .. stationName(stationId) .. "!" .. (price > 0 and (" (-" .. money(price) .. ")") or ""), "good", 3)
	else
		notify(player, stationName(stationId) .. " is now Lv " .. newLevel .. "! (-" .. money(price) .. ")", "good", 3)
	end
	milestoneToasts(player, home, after)
	TycoonService.HomeChanged:Fire(player)
	return true, newLevel
end

----------------------------------------------------------------------
-- Collect = scoop every pile in range (old clients / tests; the 0.25 s loop does it by itself)
----------------------------------------------------------------------

function TycoonService.Collect(player, quiet)
	if not initialized or not dataService then
		return false, "Homes are not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	local index = plots[player]
	if not index then
		return false, "Claim a home first (E at a free gate)"
	end
	local ok, result = Coins.scoop(player, index)
	if not ok then
		return false, result
	end
	local home = getHome(player)
	if home then
		local income, _, _, entries = incomeOf(player, home)
		Coins.show(index, Coins.ensure(player), home, income, entries, player)
	end
	if not quiet or cooldown(player, "CollectToast", COLLECT_TOAST_GAP) then
		notify(player, "+" .. money(result) .. " scooped!", "good", 2.5)
	end
	return true, result
end

----------------------------------------------------------------------
-- Prestige
----------------------------------------------------------------------

-- Can this player prestige right now? true, home | false, reason (no side effects).
local function prestigeCheck(player)
	if not initialized or not catalog then
		return false, "Homes are not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	if not plots[player] then
		return false, "Claim a home first (E at a free gate)"
	end
	local home = getHome(player)
	if not home then
		return false, "Your home is still loading..."
	end
	local can, reason = catalog.CanPrestige(home)
	if not can then
		return false, reason or "Not ready to prestige yet"
	end
	return true, home
end

local function openPanel(player, panelId, args)
	if not player or not player.Parent then
		return false
	end
	if not openPanelRemote then
		local ok, remote = pcall(Remotes.Get, "OpenPanel")
		if ok then
			openPanelRemote = remote
		end
	end
	if not openPanelRemote then
		return false
	end
	local ok = pcall(function()
		openPanelRemote:FireClient(player, panelId, args)
	end)
	return ok
end

-- E on the Prestige pad. A prestige resets the whole build and all Cash, so one press never does it: the pad opens
-- the Home window on its prestige confirmation ("Starts over / You keep / You get"), and only that window's confirm
-- button (HomeAction "Prestige") prestiges. ok | false, reason
local function askPrestige(player)
	local ok, reason = prestigeCheck(player)
	if not ok then
		return false, reason
	end
	if not openPanel(player, "Home", { Action = "Prestige" }) then
		return false, "Open the Home window to prestige"
	end
	return true
end

function TycoonService.Prestige(player)
	local ready, homeOrReason = prestigeCheck(player)
	if not ready then
		return false, homeOrReason
	end
	local home = homeOrReason
	local stars = starsOf(home) + 1
	local gems = 0
	if type(catalog.PrestigeGems) == "function" then
		local okG, g = pcall(catalog.PrestigeGems, stars)
		if okG and isFinite(g) and g > 0 then
			gems = math.floor(g)
		end
	end

	-- reset the stations (decor kept, the Garden back at its ResetLevel), the bank, +1 star; then Cash to 0 and the
	-- gems: one non-yielding step (MutateHome itself drops LegacySlots / LegacyPrices when Prestige rises)
	local wrote = mutateHome(player, function(live)
		if starsOf(live) ~= stars - 1 or not catalog.CanPrestige(live) then
			return false
		end
		if type(live.Stations) ~= "table" then
			live.Stations = {}
		end
		local keep = catalog.StationsAfterPrestige(live.Stations)
		local ids = {}
		for id in pairs(live.Stations) do
			ids[#ids + 1] = id
		end
		for _, id in ipairs(ids) do
			live.Stations[id] = keep[id] -- in place: Home.Rooms stays the same table
		end
		for id, level in pairs(keep) do
			live.Stations[id] = level
		end
		live.Prestige = stars
		live.CollectorCash = 0
		live.Level = homeLevelOf(live)
		if offlineDone[player] then
			live.LastSeen = os.time()
		end
		return true
	end)
	if not wrote then
		return false, "Could not prestige right now"
	end
	local cash = math.floor(getCash(player))
	if cash > 0 then
		dataService.SpendCash(player, cash)
	end
	if gems > 0 and type(dataService.AddGems) == "function" then
		dataService.AddGems(player, gems)
	end
	-- the running training jobs keep going (3.7) but the Cash paid into them went with the old run: a Stop after the
	-- prestige refunds nothing (otherwise Cash parked in training would carry over the reset)
	if type(dataService.MutateGrowth) == "function" then
		dataService.MutateGrowth(player, function(growth)
			for _, entry in pairs(growth) do
				if type(entry) == "table" and type(entry.Job) == "table" then
					entry.Job.Paid = 0
				end
			end
			return true
		end)
	end

	Coins.reset(player, 0) -- the coins on the lawn are gone with the bank
	local after = getHome(player)
	if after then
		syncPlot(player, after)
	end
	local mult = 1
	if type(catalog.PrestigeMultiplier) == "function" then
		mult = catalog.PrestigeMultiplier(stars)
	end
	local text = "Prestige " .. stars .. "! Coins x" .. multiplierText(mult) .. " forever"
	if gems > 0 then
		text = text .. ", +" .. gems .. " Gems"
	end
	notify(player, text .. ".", "good", 6)
	local open = gardenSlots(after or home)
	if open > 0 then
		notify(player, "Garden place " .. open .. " unlocked!", "good", 6)
	end
	local fusionAt = catalog.Prestige and tonumber(catalog.Prestige.FusionUnlock) or 1
	if stars == fusionAt then
		notify(player, "Fusion Machine unlocked at your home!", "good", 6)
	end
	TycoonService.Prestiged:Fire(player, stars)
	TycoonService.HomeChanged:Fire(player)
	return true, stars
end

----------------------------------------------------------------------
-- Garden
----------------------------------------------------------------------

local function wholeSlot(slot)
	if type(slot) ~= "number" or slot ~= slot or slot == math.huge or slot == -math.huge then
		return nil
	end
	if slot ~= math.floor(slot) or slot < 1 or slot > MAX_SLOT then
		return nil
	end
	return slot
end

-- "2:10" of a training job's remaining time (DataService.GetGrowth(player, key).Job.Ends is server os.time())
local function trainingLeftText(player, key)
	if dataService and type(dataService.GetGrowth) == "function" then
		local ok, growth = pcall(dataService.GetGrowth, player, key)
		local job = ok and type(growth) == "table" and growth.Job
		local ends = type(job) == "table" and tonumber(job.Ends)
		if isFinite(ends) then
			local left = math.max(0, math.floor(ends - os.time()))
			return string.format("%d:%02d", math.floor(left / 60), left % 60)
		end
	end
	return nil
end

-- { [key] = true } of the caller's keys in a running battle or ring run (BattleService.KeysInBattle when it exists).
local function keysInBattle(player)
	if battleService and type(battleService.KeysInBattle) == "function" then
		local ok, set = pcall(battleService.KeysInBattle, player)
		if ok and type(set) == "table" then
			return set
		end
	end
	return {}
end

function TycoonService.GardenSet(player, slot, key)
	if not initialized or not catalog then
		return false, "Homes are not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	slot = wholeSlot(slot)
	if not slot then
		return false, "Unknown garden slot"
	end
	if key == "" or key == false then
		key = nil
	end
	if key ~= nil and not validKeyString(key) then
		return false, "Unknown pet"
	end
	local home = getHome(player)
	if not home then
		return false, "Your home is still loading..."
	end
	-- (clearing works on any slot: a key resting above the open count can always be taken out)
	if key ~= nil and slot > gardenSlots(home) then
		if gardenSlots(home) <= 0 then
			return false, "Build the Pet Garden first"
		end
		return false, "Garden place locked: Prestige to open it"
	end
	local profile = getProfile(player)
	local def = nil
	if key ~= nil then
		local tier, why
		def, tier, why = petDefOf(key, profile)
		if not def then
			return false, why or "Unknown pet"
		end
		local name = tostring(def.DisplayName or def.Name or key)
		if trainingKeys(player)[key] then
			local left = trainingLeftText(player, key)
			return false, name .. " is training" .. (left and (" (" .. left .. " left)") or "")
		end
		if keysInBattle(player)[key] then
			return false, "Finish your battle first!"
		end
	end

	local why = nil
	local wrote = mutateHome(player, function(live)
		if key ~= nil and slot > gardenSlots(live) then
			why = "Garden place locked: Prestige to open it"
			return false
		end
		if type(live.Garden) ~= "table" then
			live.Garden = {}
		end
		if key == nil then
			if live.Garden[slot] == nil then
				return false
			end
			live.Garden[slot] = nil
			return true
		end
		if live.Garden[slot] == key then
			return false
		end
		local uses = 1
		for s, k in pairs(live.Garden) do
			if s ~= slot and k == key then
				uses = uses + 1
			end
		end
		if uses > ownedCount(profile, key) then
			why = "You have no free copy of that pet"
			return false
		end
		live.Garden[slot] = key
		if offlineDone[player] then
			live.LastSeen = os.time()
		end
		return true
	end)
	if not wrote then
		if why then
			return false, why
		end
		return true, nil -- nothing to change (already there / already empty)
	end
	if plots[player] then
		local after = getHome(player)
		if after then
			local income, _, valid, entries = incomeOf(player, after)
			local st = Coins.ensure(player)
			Coins.followKeys(st, valid, Coins.serverNow(), Coins.cycle(), gardenSlots(after)) -- X5 / Y8: the epoch rule, right away
			syncPlot(player, after, income, valid, entries)
		end
	end
	if key ~= nil then
		local name = (def and (def.DisplayName or def.Name)) or key
		notify(player, tostring(name) .. " is working in your Garden!", "good", 3)
	end
	TycoonService.HomeChanged:Fire(player)
	return true, nil
end

----------------------------------------------------------------------
-- Public reads
----------------------------------------------------------------------

function TycoonService.GetPlot(player)
	local index = player and plots[player]
	if index then
		return plotInfo(index)
	end
	return nil
end

function TycoonService.GetHome(player)
	return getHome(player)
end

function TycoonService.IncomePerSecond(player)
	local home = getHome(player)
	if not home then
		return 0, { Food = 0, Pets = 0, Lucky = 1, Multiplier = 1 }
	end
	local income, parts = incomeOf(player, home)
	return income, parts
end

-- The seconds of coins a place's pile holds (Coin Magnet + Vault; Coins.BasePileSeconds without a Magnet).
function TycoonService.PileSeconds(player)
	local home = getHome(player)
	if not home or not catalog or type(catalog.PileSeconds) ~= "function" then
		return catalog and catalog.Coins and catalog.Coins.BasePileSeconds or 0
	end
	return catalog.PileSeconds(home)
end
TycoonService.CollectorCap = TycoonService.PileSeconds -- Phase 3 name, kept one release

-- The whole Cash waiting on the lawn (the bank: live piles + the Welcome-back pile).
function TycoonService.CoinsWaiting(player)
	local home = getHome(player)
	if not home then
		return 0
	end
	return math.floor(bankOf(home))
end

-- The drops on the lawn (a copy of the session ledger, slot then cycle order): { { Slot, Cycle, Position, Value,
-- Lucky, Poops, Stage } } (nil without a plot). Drops of a fraction left by a scoop (Poops 0) are included.
function TycoonService.Drops(player)
	local index = player and plots[player]
	local st = index and Coins.state[player]
	if not st then
		return nil
	end
	local slots = {}
	for slot in pairs(st.Drops) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	local out = {}
	for _, slot in ipairs(slots) do
		for _, d in ipairs(st.Drops[slot]) do
			out[#out + 1] = {
				Slot = slot,
				Cycle = d.Cycle,
				Position = Coins.worldPoint(st, index, d.X, d.Z),
				Value = d.Value,
				Lucky = d.Lucky == true,
				Poops = d.Poops or 0,
				Stage = Coins.stageOf(d.Poops),
			}
		end
	end
	return out
end

-- Per-slot sums of the drops (the Phase 4 shape, kept): { [slot] = { Coins (= poops), Value, Lucky, Full (= napping),
-- Pos (the first drop) }, W = { Value, Pos } } (nil without a plot).
function TycoonService.Piles(player)
	local index = player and plots[player]
	local st = index and Coins.state[player]
	if not st then
		return nil
	end
	local out = {}
	for slot, list in pairs(st.Drops) do
		if #list > 0 then
			local sum = { Coins = 0, Value = 0, Lucky = false, Full = st.Nap[slot] ~= nil, Pos = nil }
			for _, d in ipairs(list) do
				sum.Coins = sum.Coins + (d.Poops or 0)
				sum.Value = sum.Value + d.Value
				if d.Lucky then
					sum.Lucky = true
				end
				if not sum.Pos then
					sum.Pos = Coins.worldPoint(st, index, d.X, d.Z)
				end
			end
			out[slot] = sum
		end
	end
	for slot in pairs(st.Nap) do
		if not out[slot] then
			out[slot] = { Coins = 0, Value = 0, Lucky = false, Full = true, Pos = nil }
		end
	end
	out.W = { Value = st.Welcome, Pos = Coins.welcomePoint(st, index) }
	return out
end

-- The developer reset: the bank and every pile to 0 (the Home itself was reset by DataService.ResetFields).
function TycoonService.ClearCoins(player)
	if not isPlayer(player) then
		return false
	end
	mutateHome(player, function(live)
		live.CollectorCash = 0
		return true
	end)
	if plots[player] then
		Coins.reset(player, 0)
		local home = getHome(player)
		if home then
			syncPlot(player, home)
		end
	elseif Coins.state[player] then
		Coins.reset(player, 0)
	end
	return true
end

----------------------------------------------------------------------
-- The home portal (3.10)
----------------------------------------------------------------------

-- The reason a portal may not open / be used right now, or nil (in order: match, battle, portal party, dead).
function Portal.refuse(player)
	if player:GetAttribute(Config.Attr.InMatch) == true then
		return "Finish your match first"
	end
	local inBattle = player:GetAttribute(ATTR_IN_BATTLE)
	if (inBattle ~= nil and inBattle ~= false and inBattle ~= "") or (battleService and type(battleService.IsInBattle) == "function" and battleService.IsInBattle(player) == true) then
		return "Finish your battle first!"
	end
	if player:GetAttribute(Portal.ATTR_LOCKED) ~= nil then
		return "Leave the portal party first"
	end
	local humanoid = Util.GetHumanoid(player)
	if not humanoid or humanoid.Health <= 0 or not Util.GetRoot(player) then
		return "You cannot open a portal right now"
	end
	return nil
end

-- Where the portal opens: 6 studs ahead on the ground (raycasts stop 1.5 studs before a wall and find the floor;
-- with no floor ahead the character's own spot). Returns pos (Vector3), yaw (degrees).
function Portal.place(player)
	local root = Util.GetRoot(player)
	local char = player.Character
	if not root or not char then
		return nil
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end
	local yaw = math.deg(math.atan2(-flat.X, -flat.Z))
	local origin = root.Position
	local params = nil
	pcall(function()
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		params.RespectCanCollide = true
	end)
	local function cast(from, dir)
		local ok, hit = pcall(function()
			return workspace:Raycast(from, dir, params)
		end)
		if ok and hit then
			return hit
		end
		return nil
	end
	local ahead = Portal.AHEAD
	local wall = cast(origin, flat * ahead)
	if wall then
		ahead = math.max(0, wall.Distance - Portal.WALL_GAP)
	end
	local at = origin + flat * ahead
	local floor = cast(at + Vector3.new(0, 2, 0), Vector3.new(0, -Portal.DROP, 0))
	if floor then
		return floor.Position, yaw
	end
	local under = cast(origin + Vector3.new(0, 1, 0), Vector3.new(0, -Portal.DROP, 0))
	if under then
		return under.Position, yaw
	end
	return origin - Vector3.new(0, 3, 0), yaw
end

function Portal.close(player)
	Portal.open[player] = nil
	if typeof(player) == "Instance" and player.Parent then
		pcall(function()
			player:SetAttribute(Config.Attr.HomePortal, nil)
		end)
	end
end

-- Opens the player's home portal (one per player; pressing again keeps the open one). ok | false, reason.
function Portal.openFor(player)
	if not initialized or not spotService or type(spotService.Teleport) ~= "function" then
		return false, "Homes are not ready yet"
	end
	if not isPlayer(player) then
		return false, "Not in the game"
	end
	local reason = Portal.refuse(player)
	if reason then
		toastOnce(player, reason, "bad")
		return false, reason
	end
	local rec = Portal.open[player]
	if rec and os.clock() < rec.ClosesAt then
		return true, nil -- the open portal stays
	end
	if not plots[player] then
		local target = nil
		if type(spotService.SuggestSpot) == "function" then
			local okS, suggested = pcall(spotService.SuggestSpot, player)
			target = okS and suggested or nil
		end
		if not target then
			toastOnce(player, "Every home is taken right now.", "bad")
			return false, "Every home is taken right now."
		end
	end
	if not cooldown(player, "GoHome", Portal.COOLDOWN) then
		return false, "Wait a moment"
	end
	local pos, yaw = Portal.place(player)
	if typeof(pos) ~= "Vector3" then
		return false, "You cannot open a portal right now"
	end
	local closesAt = workspace:GetServerTimeNow() + Portal.OPEN_SECONDS
	Portal.open[player] = { Pos = pos, Yaw = yaw, ClosesAt = os.clock() + Portal.OPEN_SECONDS }
	pcall(function()
		player:SetAttribute(Config.Attr.HomePortal, string.format("%.2f,%.2f,%.2f,%.1f,%.3f", pos.X, pos.Y, pos.Z, yaw, closesAt))
	end)
	return true, nil
end

-- The owner walked in: SpotService.Teleport (home, or the suggested free gate), PortalArrived, PortalUsed.
function Portal.enter(player)
	if Portal.refuse(player) then
		Portal.close(player)
		return false
	end
	local hadHome = plots[player] ~= nil
	local ok, moved = pcall(spotService.Teleport, player)
	Portal.close(player)
	if not ok or moved ~= true then
		if not hadHome then
			toastOnce(player, "Every home is taken right now.", "bad")
		end
		return false
	end
	pcall(function()
		player:SetAttribute(Config.Attr.PortalArrived, workspace:GetServerTimeNow())
	end)
	if not hadHome then
		notify(player, "Press E at the gate to claim this home!", "info", 4)
	end
	TycoonService.PortalUsed:Fire(player)
	return true
end

-- The 0.2 s pass: expiry, and ONLY the owner's root against their own portal point.
function Portal.tick()
	local now = os.clock()
	for player, rec in pairs(Portal.open) do
		if not player.Parent or departed[player] or now >= rec.ClosesAt then
			Portal.close(player)
		else
			local root = Util.GetRoot(player)
			if root then
				local d = root.Position - rec.Pos
				if math.sqrt(d.X * d.X + d.Z * d.Z) <= Portal.ENTER_RADIUS and math.abs(d.Y) <= Portal.ENTER_HEIGHT then
					local ok, err = pcall(Portal.enter, player)
					if not ok then
						warn("[TycoonService] portal failed: " .. tostring(err))
						Portal.close(player)
					end
				end
			end
		end
	end
end

function Portal.loop()
	while running do
		task.wait(Portal.TICK)
		if not running then
			break
		end
		local ok, err = pcall(Portal.tick)
		if not ok then
			warn("[TycoonService] portal pass failed: " .. tostring(err))
		end
	end
end

function TycoonService.OpenHomePortal(player)
	return Portal.openFor(player)
end

function TycoonService.GoHome(player)
	return Portal.openFor(player)
end

----------------------------------------------------------------------
-- Profile load: offline coins into the bank, LastSeen
----------------------------------------------------------------------

local function touchLastSeen(player)
	lastSeenAt[player] = os.clock()
	local now = os.time()
	mutateHome(player, function(live)
		live.LastSeen = now
		return true
	end)
end

-- Runs once per session when the home is readable (profile loaded and not provisional); again on ProfileRebased.
local function onHomeLoaded(player)
	if not isPlayer(player) then
		return
	end
	local home = getHome(player)
	if not home then
		return -- not loaded yet / provisional: ProfileRebased brings us back
	end
	if offlineDone[player] then
		if plots[player] then
			-- the save was rebased (recovered or merged): the ledger is rebuilt from the merged bank (X4)
			Coins.reset(player, bankOf(home))
			syncPlot(player, home)
			TycoonService.HomeChanged:Fire(player)
		end
		return
	end
	offlineDone[player] = true
	local now = os.time()
	local last = tonumber(home.LastSeen) or 0
	local amount, away = 0, 0
	if isFinite(last) and last > 0 and now > last then
		away = now - last
		local income = incomeOf(player, home)
		local ok, value = pcall(catalog.OfflineEarnings, home, away, income)
		if ok and isFinite(value) and value >= 1 then
			amount = math.floor(value)
		end
	end
	lastSeenAt[player] = os.clock() -- the periodic refresh takes over from here
	if amount < 1 and isFinite(last) and last > 0 then
		return -- nothing paid: the stored LastSeen may stay until the first refresh (no needless write)
	end
	-- (a home seen for the first time - a new or migrated save - gets its LastSeen right away)
	-- the offline coins go INTO the bank (the Welcome-back pile) in the same step as the new LastSeen: a second load
	-- can never pay the same absence again (X6)
	local wrote = mutateHome(player, function(live)
		live.LastSeen = now
		if amount >= 1 then
			live.CollectorCash = bankOf(live) + amount
		end
		return true
	end)
	local berries = 0
	if wrote and amount >= 1 then
		-- the offline coins also grow their berries (offline x Share, the basket cap ignored), in the same step
		local share = catalog.Berries and tonumber(catalog.Berries.Share) or 0
		berries = math.floor(amount * share)
		if berries >= 1 and type(dataService.AddBerries) == "function" then
			local okB, gave = pcall(dataService.AddBerries, player, berries)
			if not okB or gave ~= true then
				berries = 0
			end
		end
	end
	if wrote and amount >= 1 then
		if plots[player] then
			local after = getHome(player)
			if after then
				Coins.reset(player, bankOf(after))
				syncPlot(player, after)
			end
		end
		task.delay(OFFLINE_TOAST_DELAY, function()
			local extra = berries >= 1 and (" and " .. tostring(berries) .. " berries") or ""
			notify(player, "Welcome back! Your pets made " .. money(amount) .. extra .. " while you were away: scoop it in your garden!", "good", 7)
		end)
	end
end

local function watchPlayer(player)
	if watching[player] or offlineDone[player] then
		return
	end
	watching[player] = true
	task.spawn(function()
		local waited = 0
		while isPlayer(player) and not offlineDone[player] and waited < PROFILE_WAIT do
			if getHome(player) then
				onHomeLoaded(player)
				break
			end
			task.wait(0.5)
			waited = waited + 0.5
		end
		watching[player] = nil
	end)
end

local function forget(player)
	plots[player] = nil
	lastTick[player] = nil
	lastSeenAt[player] = nil
	offlineDone[player] = nil
	watching[player] = nil
	cooldowns[player] = nil
	budgets[player] = nil
	toastAt[player] = nil
	Coins.state[player] = nil
	Portal.open[player] = nil
	Coins.welcomedP5[player] = nil
end

-- (LastSeen is not written here: the periodic refresh keeps it within LASTSEEN_EVERY of the leave and the offline pay
-- only starts after 120 s, so the leave save gains nothing from it. A write here would be saved, though: DataService's
-- leave save runs after the other PlayerRemoving handlers.)
local function onPlayerRemoving(player)
	departed[player] = true
	TycoonService.Release(player)
	forget(player)
end

----------------------------------------------------------------------
-- The coin tick (1 s): meals into the piles and the bank, the plot attributes
----------------------------------------------------------------------

local function tickPlayer(player, index, now)
	local last = lastTick[player] or now
	local dt = math.max(0, math.min(now - last, MAX_TICK_DT))
	lastTick[player] = now
	local home = getHome(player)
	if not home then
		return
	end
	local income, _, valid, entries = incomeOf(player, home)
	local st = Coins.ensure(player)
	local sNow = Coins.serverNow()
	Coins.followKeys(st, valid, sNow, Coins.cycle(), gardenSlots(home))
	if dt > 0 then
		local added, drops = Coins.poops(st, home, entries, valid, sNow, Coins.seedOf(player))
		if added > 0 then
			-- the bank takes the new coins and the basket its berries in ONE non-yielding step per tick
			local wrote = mutateHome(player, function(live)
				live.CollectorCash = bankOf(live) + added
				return true
			end)
			if wrote then
				Coins.applyDrops(st, drops)
				home.CollectorCash = bankOf(home) + added
				Coins.berries(player, st, home, income, added)
			end
		end
	end
	if st.DropsDirty and st.DropsAt and now - st.DropsAt >= Coins.DROPS_WRITE_GAP then
		st.DropsAt = nil -- the throttled CoinDrops write lands now (syncPlot -> Coins.show)
	end
	if syncPlot(player, home, income, valid, entries) then
		TycoonService.HomeChanged:Fire(player) -- another module changed the stations (rebase, dev reset)
	end
end

local function tickAll()
	local now = os.clock()
	for player, index in pairs(plots) do
		if player.Parent and not departed[player] then
			local ok, err = pcall(tickPlayer, player, index, now)
			if not ok then
				warn("[TycoonService] coin tick failed: " .. tostring(err))
			end
		else
			TycoonService.Release(player)
			forget(player)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if offlineDone[player] and now - (lastSeenAt[player] or 0) >= LASTSEEN_EVERY then
			touchLastSeen(player)
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
			warn("[TycoonService] tick failed: " .. tostring(err))
		end
	end
end

----------------------------------------------------------------------
-- Prompts (one ProximityPromptService listener: prompts HomeBuilder rebuilds keep working)
----------------------------------------------------------------------

local function attrUp(inst, name, depth)
	local node = inst
	for _ = 1, depth or 10 do
		if typeof(node) ~= "Instance" or node == workspace or node == game then
			return nil
		end
		local v = node:GetAttribute(name)
		if v ~= nil then
			return v
		end
		node = node.Parent
	end
	return nil
end

-- The plot a prompt belongs to: its SpotIndex attribute (prompt or an ancestor), else the spot folder it is in.
local function plotIndexOf(inst)
	local index = attrUp(inst, "SpotIndex")
	if validIndex(index) then
		return index
	end
	for i, info in pairs(spotList) do
		if typeof(info.Folder) == "Instance" and inst:IsDescendantOf(info.Folder) then
			return i
		end
	end
	return nil
end

local function stationIdOf(prompt)
	local id = attrUp(prompt, "StationId", 6)
	if type(id) == "string" then
		return id
	end
	local node = prompt.Parent
	for _ = 1, 6 do
		if typeof(node) ~= "Instance" then
			break
		end
		local name = node.Name
		local padId = type(name) == "string" and name:match("^Pad_(.+)$")
		if padId then
			return padId
		end
		node = node.Parent
	end
	return nil
end

local function onBuyPrompt(player, prompt)
	local index = plots[player]
	if not index then
		return
	end
	local owner = attrUp(prompt, "OwnerUserId", 6)
	if owner ~= nil and owner ~= player.UserId then
		return -- someone else's pad (their prompts are disabled locally; never trust a stray trigger)
	end
	local promptPlot = plotIndexOf(prompt)
	if promptPlot ~= index then
		return
	end
	local stationId = stationIdOf(prompt)
	if type(stationId) ~= "string" then
		return
	end
	if not cooldown(player, "Buy", BUY_COOLDOWN) or not spend(player) then
		return
	end
	local ok, reason
	if stationId == "Prestige" then
		ok, reason = askPrestige(player) -- opens the confirmation; nothing resets here
	else
		ok, reason = TycoonService.Buy(player, stationId)
	end
	if not ok then
		toastOnce(player, reason or "Not available yet", "bad")
	end
end

local function onPromptTriggered(prompt, player)
	if typeof(prompt) ~= "Instance" or not isPlayer(player) then
		return
	end
	local name = prompt.Name
	if name == "ClaimPrompt" then
		local index = attrUp(prompt, "SpotIndex", 8)
		if not validIndex(index) then
			index = plotIndexOf(prompt)
		end
		if validIndex(index) then
			onClaimPrompt(player, index, prompt)
		end
	elseif name == "BuyPrompt" then
		onBuyPrompt(player, prompt)
	end
end

----------------------------------------------------------------------
-- Remote HomeAction(action, arg)
----------------------------------------------------------------------

local function gardenArgs(arg)
	if type(arg) ~= "table" then
		return nil, nil
	end
	local slot = arg.Slot
	local key = arg.Key
	if slot == nil then
		slot = arg[1]
	end
	if key == nil then
		key = arg[2]
	end
	return slot, key
end

local function onHomeAction(player, action, arg)
	if not isPlayer(player) or type(action) ~= "string" or #action > MAX_ACTION_LENGTH then
		return
	end
	if not spend(player) then
		return
	end
	if action == "Upgrade" then
		if type(arg) ~= "string" or #arg > MAX_ID_LENGTH or not cooldown(player, "Buy", BUY_COOLDOWN) then
			return
		end
		local ok, reason = TycoonService.Buy(player, arg)
		if not ok then
			toastOnce(player, reason or "Not available yet", "bad")
		end
	elseif action == "GardenSet" then
		if not cooldown(player, "Garden", GARDEN_COOLDOWN) then
			return
		end
		local slot, key = gardenArgs(arg)
		local ok, reason = TycoonService.GardenSet(player, slot, key)
		if not ok then
			toastOnce(player, reason or "You cannot place that pet", "bad")
		end
	elseif action == "Collect" then
		if not cooldown(player, "Collect", COLLECT_COOLDOWN) then
			return
		end
		local ok, reason = TycoonService.Collect(player, true)
		if not ok then
			toastOnce(player, reason or "Nothing to scoop yet", "info")
		end
	elseif action == "Prestige" then
		if not cooldown(player, "Prestige", PRESTIGE_COOLDOWN) then
			return
		end
		local ok, reason = TycoonService.Prestige(player)
		if not ok then
			toastOnce(player, reason or "Not ready to prestige yet", "bad")
		end
	elseif action == "GoHome" then
		Portal.openFor(player) -- its own 3 s cooldown and refusal toasts
	end
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------

function TycoonService.Init(lobbyInfo, deps)
	if initialized then
		return
	end
	deps = deps or {}
	dataService = deps.DataService or requireModule(script.Parent, "DataService")
	petService = deps.PetService
	spotService = deps.SpotService or requireModule(script.Parent, "SpotService")
	battleService = deps.BattleService
	catalog = requireModule(Shared, "TycoonCatalog")
	homeRoam = requireModule(Shared, "HomeRoam")
	petKeys = requireModule(Shared, "PetKeys")
	petCatalog = requireModule(Shared, "PetCatalog")
	if not catalog then
		warn("[TycoonService] TycoonCatalog is missing: tycoon homes are disabled")
		return
	end
	if not dataService or type(dataService.MutateHome) ~= "function" then
		warn("[TycoonService] DataService has no Home API: tycoon homes are disabled")
		return
	end
	if not spotService or type(spotService.Claim) ~= "function" then
		warn("[TycoonService] SpotService cannot hand out plots: claiming is disabled")
	end
	initialized = true

	local list = lobbyInfo and lobbyInfo.Spots
	if type(list) == "table" then
		for index, info in pairs(list) do
			if type(index) == "number" and type(info) == "table" then
				spotList[index] = info
			end
		end
	end

	homeBuilder = requireModule(script.Parent, "HomeBuilder")
	if homeBuilder then
		hb("Init", lobbyInfo)
	else
		warn("[TycoonService] HomeBuilder is missing: plots get a plain claim prompt and no buildings")
	end
	local indices = {}
	for index in pairs(spotList) do
		indices[#indices + 1] = index
	end
	table.sort(indices)
	for _, index in ipairs(indices) do
		hb("PreparePlot", spotList[index])
	end
	local existing = nil
	if homeBuilder then
		local okScan, found = pcall(claimPromptsBySpot)
		existing = okScan and found or nil
	end
	for _, index in ipairs(indices) do
		local ok, err = pcall(ensureClaimPrompt, index, spotList[index], existing)
		if not ok then
			warn("[TycoonService] could not add a claim prompt: " .. tostring(err))
		end
	end

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	local okRemote, remote = pcall(Remotes.Get, "HomeAction")
	if okRemote and remote then
		remote.OnServerEvent:Connect(onHomeAction)
	else
		warn("[TycoonService] HomeAction remote unavailable")
	end

	-- a plot released by SpotService itself (e.g. by another module) is cleared here too
	if spotService and spotService.Released and type(spotService.Released.Connect) == "function" then
		spotService.Released:Connect(function(player, index)
			if plotOwner[index] == player then
				local info = dropPlot(player, index)
				if info then
					TycoonService.Released:Fire(player, info)
				end
			end
		end)
	end

	if dataService.ProfileLoaded and type(dataService.ProfileLoaded.Connect) == "function" then
		dataService.ProfileLoaded:Connect(function(player)
			onHomeLoaded(player)
		end)
	end
	if dataService.ProfileRebased and type(dataService.ProfileRebased.Connect) == "function" then
		dataService.ProfileRebased:Connect(function(player)
			onHomeLoaded(player)
		end)
	end

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player) -- players who joined before Init (PlayerService loads profiles first)
	end

	running = true
	task.spawn(tickLoop)
	task.spawn(Coins.loop)
	task.spawn(Portal.loop)
	game:BindToClose(function()
		running = false
		for _, player in ipairs(Players:GetPlayers()) do
			if offlineDone[player] then
				pcall(touchLastSeen, player)
			end
		end
	end)
end

return TycoonService
