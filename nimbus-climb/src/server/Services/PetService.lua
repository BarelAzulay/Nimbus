-- PetService: pet ownership, roulette purchases, equipping and pet perks (ARCHITECTURE_V2.md s.2).
--
--   PetService.Init(lobbyInfo, deps)         deps = { DataService = }
--   PetService.BuyRoulette(player, rouletteId, currency|nil, spins|nil) -> ok, reply|reason
--                                            currency: nil = the roulette's own ("Tokens"; the gems-only Secret
--                                            roulette: "Gems"), "Tokens" or "Gems" (also { Currency = ... });
--                                            spins: nil = 1, only 1 or 3 (never 3 on a gems-only roulette): anything
--                                            else answers "Bad spins". See "The money step" below.
--   PetService._SetRngForTest(rollRng, stripRng)   Studio / the mock only: seeded generators (nil keeps the current)
--   PetService._SetFaultForTest(stage, fn)         Studio / the mock only: fn() runs inside step 3 ("plan") or inside
--                                            the step-6 refresh pcall ("after"); nil fn clears it
--   PetService.Equip / Unequip(player, key)    -> ok, reason   (team balance: put a key in / take it out of the active
--                                            team, through DataService.SetTeam: Equip fills the first empty slot)
--   PetService.GetEquipped(player) -> {key...}
--   PetService.GetPerks(player) -> {MaxHealth, TokenBonus, StaminaRegen, CheckpointHeal}
--   PetService.GetTokenMultiplier(player) -> number >= 1
--   PetService.PerksChanged                  Util.Signal, Fire(player)
--   PetService.Rolled                        Util.Signal, Fire(player, petId) after every successful roll (v3; once per
--                                            pull of a request, after the reply)
--   PetService.GrantPet(player, petId, opts) -> ok, result|reason   store (2026-11-04, spec 5.4): the ONE pet-grant path
--                                            outside the roulette (the Store's packs, the daily gifts' Week Wisp). opts =
--                                            { Count = n >= 1 (default 1), Level = n | nil }. Grants min(Count, MaxPerStack
--                                            - owned) Normal copies through the roll's own two parts (planCopies +
--                                            writeCopies) WITHOUT a spin: the
--                                            first-pet auto-equip, the Index discovery, SetPetLevel(max(current, Level)),
--                                            MarkDirty, Refresh, Sync. result = { PetId, Key, Granted, Count, IsNew,
--                                            NewDiscovery, Level }. Refused: not here, a save not loaded or provisional
--                                            ("Your save is still loading"), an unknown pet, a junk Count / Level, a full
--                                            stack ("Stack full": nothing written, the caller substitutes). Never fires
--                                            Rolled. Non-yielding.
--   Extra (Phase 2): PetService.Refresh(player) -> changed   DataService.SyncEquipped (the followers = the active team minus
--                    busy pets, after FusionService / DevService removed copies, a training job, a Garden change) and
--                    republishes the attributes and perks. DataService.TeamsChanged republishes them too.
-- Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract" 3.7, 5.3, 5.4):
--   * the training lock: Equip refuses a key with a running training job ("Rocky is training (2:10 left)"; the ONE
--     source is DataService.TrainingKeys). A team pet that starts training keeps its slot and leaves the followers
--     (PetCareService calls Refresh).
-- Bug batch 2 #18 ("Remote recall"): a pet working in the Garden is busy gardening. A pet whose every copy is placed in
--   the Garden / Gym (DataService.PlacedCopies) cannot follow: Equip refuses it ("Rocky is gardening! Take it out of the
--   garden first"; the client asks first and recalls it with ONE request, TycoonService.GardenRecall). A team pet sent to
--   the Garden keeps its slot.
--   PetService.CanEquip(player, key, freed?) -> ok, reason   Equip's checks without equipping; `freed` = copies about to
--     leave the Garden (the recall checks before it takes the pet out).
--   * attribute EquippedInfo (Config.Attr) = "23:1,5:0": level:evolution stage per EquippedPets entry, written by
--     refreshPlayer (equip changes, Refresh after level-ups / evolutions) only when it changed and at most every 0.5 s
--     per player (a burst of level-ups coalesces into one deferred write); other clients draw the pet cards and the
--     evolved follower models from it.
--
-- v3 (ARCHITECTURE_V3.md section 3): every successful roll marks the pet as discovered for the Pet Index
-- (DataService.MarkDiscovered) before the ProfileSync goes out; RouletteResult.IsNew keeps meaning "first time
-- owned" and the payload also carries NewDiscovery (first time in the Index). Owned pets are re-checked as
-- discovered whenever a profile loads or is rebased.
--
-- Phase 2 (ARCHITECTURE_V3.md "Pet keys"): a pet COPY is a key (shared/PetKeys.lua): "petId" (Normal),
-- "petId@Golden", "petId@Rainbow", "hyb:<uid>" (a fused hybrid). Equip / Unequip take keys; an old plain petId is
-- the Normal key, so old callers keep working (Unequip(petId) also takes off a tier copy of that pet when no Normal
-- copy is equipped). Perks and the token multiplier sum PetKeys.DefOf(key).Perks x PetKeys.StatMultiplier(tier)
-- (DataService.ComputePerks), capped as before. The roulette still adds Normal copies (Pets[petId] + 1).
--
-- Phase 2 gems (ARCHITECTURE_V3.md "GemService"): a roulette can also be paid in Gems. GemService (looked up when
-- needed, so it may be missing) owns the gem prices (Config.Gems.RouletteGemPrices, the same odds as with tokens), the
-- PolicyService paid-random-items check and the gems-only Secret roulette (Config.Gems.SecretRoulette, rolled by
-- GemService.RollPet); its Quote is taken first, then the shared roll charges the Gems (DataService.SpendGems) and
-- grants in one non-yielding step. A gem roll without GemService, for a restricted (or not yet checked) account or
-- for a roulette without a gem price is refused before anything is charged. Secret pets only ever come out of a
-- roulette with AllowSecret = true: a Secret result of any other roulette is refused (nothing charged). The
-- BuyRoulette remote takes the optional currency as its second argument; RouletteResult gains Currency, Price, Gems.
--
-- The money step (lobby-shop spec 5.1 / 7): BuyRoulette(player, rouletteId, currency, spins) is ONE non-yielding step
-- (no task.wait, DataStore or remote call) that never refuses after the roll:
--   1. the checks, in order, with today's texts: a live player, a known roulette, the currency ("Unknown currency"),
--      the spins count ("Bad spins"), not in a match, the profile loaded ("Your data is still loading"), the Secret
--      Roulette's pity read (DataService.GetPity; provisional or no answer -> "Your data is still loading"), a
--      gem-priced spin only once DataService.GemsSettled (the server-hop settle hold, same text), GemService.Quote (the
--      PolicyService lock, unchanged), the balance against Price = UnitPrice x spins (computed once, both currencies);
--   2. the pulls, from RNG.Roll in order (roll(id, RNG.Roll): PetCatalog.RollPet, or the quote's GemService.RollPet
--      for the Secret Roulette; the pity's forced pull is roll(id, RNG.Roll, { ForceRarity = "Secret" }), Pity = true,
--      and must come back a Secret). A pull's rarity is its rolled pet's and never changes. A pet the player cannot hold
--      another copy of (owned + earlier pulls of this request >= MaxPerStack) is re-picked uniformly with RNG.Roll from
--      PetCatalog.RarityPool(id, rarity) minus the full pets; only when every pet of that rarity is full the pull keeps
--      its pet and becomes a Substitute of that rarity's Config.Index.Rewards Tokens (Count = the full stack). The kept
--      exception: a Secret pet out of a roulette without AllowSecret refuses the whole request "The roulette jammed, try
--      again" (an impossible roll, before the charge);
--   3. everything that can fail, before the charge, in a pcall: the grant plans (planCopies: IsNew, NewDiscovery,
--      Count), PoolSize, the strips (buildStrip, RNG.Strip), the Secret pity's new numbers, the reply table; an error
--      answers "The roulette jammed, try again" with nothing charged;
--   4. one charge (SpendTokens / SpendGems of Price);
--   5. plain writes: writeCopies per pull in order (the Pets counts, Discovered), AddTokens per substitute,
--      Stats.Spins += spins, the Secret pity (DataService.SetPity), MarkDirty;
--   6. after the step, each in its own pcall (a failure is logged and never undoes the grant): refreshPlayer, the
--      SecretPityLeft attribute (a Secret Roulette spin), the first pet ever into the active team (SetTeam), one Sync,
--      the RouletteResult reply, Rolled:Fire per pull (a substitute fires with its rolled pet), the announcement (per
--      pull, Rare and up, until lobby-shop Task 6).
-- The Secret pity (spec 5.2): Config.Gems.SecretRoulette.PityAt (7) = the 7th Secret Roulette spin in a row without a
-- Secret is a Secret. The count is the save's Pity.Secret = { Spins, Hit } (Since = max(0, Spins - Hit)): a spin is
-- forced when Since >= PityAt - 1; every spin adds 1 to Spins (a substitute too); a Secret pull (natural, forced or a
-- substitute) sets Hit = Spins. Read in step 1, computed in step 3, written in step 5 in the same profile write as the
-- spend and the pet. The strip of a forced pull is drawn as always (the plain roll from RNG.Strip): it shows the odds.
-- Attribute SecretPityLeft (Config.Attr) = clamp(PityAt - Since, 1, PityAt), written by refreshPityAttr on
-- ProfileLoaded, ProfileRebased, DataService.Settled and after each Secret spin; absent while loading, provisional or
-- not settled (DataService.GemsSettled false).
-- Every accepted request is charged once and gets all its pulls; a refused request writes nothing. x3 costs exactly 3 x
-- x1. The two generators (RNG.Roll for the pulls, RNG.Strip for the strips) are made once at Init with Util.NewRng()
-- (Random.new() without a seed: engine seeded, never the clock, the user id or Stats.Spins, never sent), so the pulls
-- of an x3 are independent and a strip says nothing about the roll generator.
-- The reply (RouletteResult, and BuyRoulette's second value):
--   { Ok = true, RouletteId, Currency, Spins, UnitPrice, Price = UnitPrice x Spins,
--     Pulls = { { PetId, Key, Rarity, IsNew, NewDiscovery, Count, PoolSize, Strip = { petId x 40, the winner at 34 },
--                 Pity = true|nil, Substitute = { Tokens } | nil }... },
--     PetId, Key, IsNew, NewDiscovery, Count, Strip (pull 1 mirrored for older readers), Tokens, Gems (after the step),
--     SecretPity = { Left = 1..PityAt } (the Secret Roulette only; the same clamped number as the attribute) }
--   The remote's failure answer: { Ok = false, Reason, RouletteId, Currency, Spins, Tokens, Gems }.
-- The BuyRoulette remote (rouletteId, currency, spins): the 0.25 s cooldown first, then rouletteId a string <= 48 and
-- spins nil / 1 / 3 (3 never on a gems-only roulette); anything else is dropped silently.
--
-- Everything is server authoritative: the client only sends ids, we validate ownership, prices,
-- stack caps and slot limits, then write to the live profile and Sync it back.
--
-- Perk plumbing:
--   * attribute EquippedPets (csv of keys)   -> every client draws that player's followers
--   * attribute EquippedHybrids              -> the looks of the equipped hybrids (other clients cannot see the
--                                               owner's profile): "uid=Body/Style/Tier/Rarity[/Seed[/Elements]];..."
--                                               -- set BEFORE EquippedPets, only once a player ever equips a hybrid.
--                                               Field 6 (gui-redo) = the record's Elements joined by "+" in their
--                                               order (the chosen first element first; field 5 "" without a Seed);
--                                               left out when the record has none (today's 4 / 5 fields)
--   * attribute PerkStaminaRegen         -> MovementController scales its stamina regen
--   * MaxHealth                          -> PlayerService (Main hands it GetPerks and calls RefreshMaxHealth
--                                           when PerksChanged fires), so this module never touches Humanoids
--   * TokenBonus / CheckpointHeal        -> read by MatchService through GetPerks / GetTokenMultiplier
-- perkState is updated BEFORE PerksChanged fires, so listeners always see the new numbers.
-- Equip / Unequip / BuyRoulette are refused while the player attribute InMatch is true, so the
-- loadout cannot be hot-swapped between token pickups and checkpoints.
--
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local PetService = {}
PetService.PerksChanged = Util.Signal()
PetService.Rolled = Util.Signal()

local STRIP_LENGTH = 40 -- cosmetic roulette strip: the client scrolls it and stops on WIN_INDEX
local WIN_INDEX = 34
local REMOTE_COOLDOWN = 0.25 -- seconds per player per remote
local PROMPT_COOLDOWN = 0.5
local ANNOUNCE_DELAY = 5 -- seconds before the puller sees their own server-wide announcement
local MAX_ID_LENGTH = 48
local PROMPT_NAME = "RoulettePrompt"
local HYBRID_ATTR = "EquippedHybrids" -- not in Config.Attr (lead-owned): the looks of equipped hybrids, see the header
local SECRET_RARITY = "Secret" -- Secret pets come only from a roulette with AllowSecret = true (Phase 2 gems)
local MAX_CURRENCY_LENGTH = 16

----------------------------------------------------------------------
-- Optional collaborators (written by other modules; every use is guarded)
----------------------------------------------------------------------

local function loadShared(name)
	local module = Shared:FindFirstChild(name) or Shared:WaitForChild(name, 5)
	if not module then
		warn("[PetService] missing shared module: " .. name)
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	warn("[PetService] could not load " .. name .. ": " .. tostring(result))
	return nil
end

local PetCatalog = loadShared("PetCatalog")
local PetKeys = loadShared("PetKeys")

-- GemService (Phase 2, gems) is looked up when a gem roll needs it: an optional module that Main loads after this one
-- (requiring it here at load time would tie the two to their load order).
local gemModule = nil
local function getGemService()
	if gemModule then
		return gemModule
	end
	local inst = script.Parent:FindFirstChild("GemService")
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		gemModule = result
		return result
	end
	return nil
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local roulettes = {} -- [id] = Config.Roulettes entry
for _, entry in ipairs(Config.Roulettes) do
	roulettes[entry.Id] = entry
end

local rarityOrder = {} -- [rarityId] = Order
for _, entry in ipairs(Config.Rarities) do
	rarityOrder[entry.Id] = entry.Order
end
local ANNOUNCE_ORDER = rarityOrder.Rare or 3

local perkState = {} -- [player] = { Perks = {...} }
local lastCall = {} -- [player] = { [key] = os.clock() }
local infoState = {} -- [player] = { At = os.clock() of the last EquippedInfo write, Pending = true while a deferred write waits }
local INFO_GAP = 0.5 -- EquippedInfo is written at most this often per player (level-up bursts coalesce)
local remotesConnected = false
local playersConnected = false
local promptObjects = {}
-- The money step's two server-wide generators (see the header): Roll for the pulls, Strip for the cosmetic strips.
-- Made in Init (or at the first spin); PetService._SetRngForTest swaps them in Studio / the mock.
local RNG = { Roll = nil, Strip = nil }
local faults = {} -- [stage] = fn: PetService._SetFaultForTest (Studio / the mock only), "plan" (step 3) or "after" (step 6)

local ZERO_PERKS = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 }

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function isLivePlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function rateLimited(player, key, interval)
	local record = lastCall[player]
	if not record then
		record = {}
		lastCall[player] = record
	end
	local now = os.clock()
	local last = record[key]
	if last and now - last < interval then
		return true
	end
	record[key] = now
	return false
end

local function validId(id)
	return type(id) == "string" and #id > 0 and #id <= MAX_ID_LENGTH
end

-- Perks are read by MatchService at the moment of each pickup / checkpoint, so the loadout must not
-- change while a match runs (same rule as the roulette and the item shop).
local function inMatch(player)
	return player:GetAttribute(Config.Attr.InMatch) == true
end

local function fireClient(remoteName, player, ...)
	local ok, remote = pcall(Remotes.Get, remoteName)
	if ok and remote and player and player.Parent then
		remote:FireClient(player, ...)
	end
end

local function notify(player, text, kind, duration)
	fireClient("Notify", player, text, kind or "info", duration or 3)
end

-- every owned copy (Normal, tiers, hybrids): the very first pet ever is equipped automatically
local function totalPets(profile)
	local n = 0
	for _, count in pairs(profile.Pets) do
		n = n + count
	end
	for _, entry in pairs(type(profile.Tiers) == "table" and profile.Tiers or {}) do
		if type(entry) == "table" then
			for _, count in pairs(entry) do
				if type(count) == "number" then
					n = n + count
				end
			end
		end
	end
	for _ in pairs(type(profile.Hybrids) == "table" and profile.Hybrids or {}) do
		n = n + 1
	end
	return n
end

-- PetKeys.Parse(key) or nil (a plain petId when PetKeys is missing)
local function parseKey(key)
	if PetKeys and type(PetKeys.Parse) == "function" then
		local ok, parsed = pcall(PetKeys.Parse, key)
		if ok then
			return parsed
		end
		return nil
	end
	if validId(key) then
		return { Key = key, PetId = key, Tier = "Normal" }
	end
	return nil
end

-- The definition of a key (PetKeys.DefOf: catalog def, tier def or hybrid def), or nil for unknown keys.
-- Without PetKeys plain ids resolve through PetCatalog; without either nothing can be called unknown (true).
local function defOf(key, profile)
	if PetKeys and type(PetKeys.DefOf) == "function" then
		local ok, def = pcall(PetKeys.DefOf, key, profile)
		if ok and type(def) == "table" then
			return def
		end
		return nil
	end
	if PetCatalog and type(PetCatalog.Get) == "function" then
		local ok, def = pcall(PetCatalog.Get, key)
		if ok and type(def) == "table" then
			return def
		end
		return nil
	end
	return true
end

-- copies of `key` the profile owns
local function ownedCount(profile, key)
	if PetKeys and type(PetKeys.Count) == "function" then
		local ok, n = pcall(PetKeys.Count, profile, key)
		if ok and type(n) == "number" then
			return n
		end
		return 0
	end
	local n = profile.Pets[key]
	if type(n) == "number" then
		return n
	end
	return 0
end

-- "uid=Body/Style/Tier/Rarity[/Seed[/Elements]];..." for the equipped hybrids (what other clients need to draw them).
-- gui-redo Task 3: field 6 = the record's Elements in their order joined by "+" (Elements[1] = the parent that gives the
-- normal attack), so other clients' stand-in defs lead with the same element; field 5 is "" when there is no Seed but
-- there are Elements (field 6 keeps its place). Only plain names are written; a record with none keeps today's value.
local function hybridLooks(profile)
	local parts, seen = {}, {}
	local hybrids = type(profile.Hybrids) == "table" and profile.Hybrids or {}
	for _, key in ipairs(profile.Equipped) do
		local parsed = parseKey(key)
		local uid = parsed and parsed.HybridId
		local rec = uid and hybrids[uid]
		if uid and not seen[uid] and type(rec) == "table" and type(rec.Body) == "string" and type(rec.Style) == "string" then
			seen[uid] = true
			local fields = { rec.Body, rec.Style, parsed.Tier, type(rec.Rarity) == "string" and rec.Rarity or "" }
			if type(rec.Seed) == "number" and rec.Seed == rec.Seed then
				fields[5] = tostring(math.floor(rec.Seed))
			end
			local elements = {}
			for _, e in ipairs(type(rec.Elements) == "table" and rec.Elements or {}) do
				if type(e) == "string" and string.find(e, "^[%w_]+$") then
					elements[#elements + 1] = e
				end
			end
			if #elements > 0 then
				fields[5] = fields[5] or ""
				fields[6] = table.concat(elements, "+")
			end
			local text = uid .. "=" .. table.concat(fields, "/")
			if not string.find(text, "[,;]") then
				parts[#parts + 1] = text
			end
		end
	end
	return table.concat(parts, ";")
end

local function copyPerks(perks)
	return {
		MaxHealth = perks.MaxHealth or 0,
		TokenBonus = perks.TokenBonus or 0,
		StaminaRegen = perks.StaminaRegen or 0,
		CheckpointHeal = perks.CheckpointHeal or 0,
	}
end

----------------------------------------------------------------------
-- Perks + attributes
----------------------------------------------------------------------

-- Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract" 3.7, 4.1): the training lock. DataService.TrainingKeys is the
-- ONE source: { [key] = true } of the keys with a running training job ({} before the load / while provisional).
local function trainingKeys(player)
	if type(DataService.TrainingKeys) ~= "function" then
		return {}
	end
	local ok, set = pcall(DataService.TrainingKeys, player)
	if ok and type(set) == "table" then
		return set
	end
	return {}
end

-- "2:10" of training left for a key (its Job.Ends is a server os.time() stamp), or nil
local function trainingLeft(player, key)
	if type(DataService.GetGrowth) ~= "function" then
		return nil
	end
	local ok, growth = pcall(DataService.GetGrowth, player, key)
	local job = ok and type(growth) == "table" and growth.Job or nil
	local ends = type(job) == "table" and tonumber(job.Ends) or nil
	if not ends or ends ~= ends then
		return nil
	end
	local s = math.max(0, math.ceil(ends - os.time()))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- Bug batch 2 #18: { [key] = copies working in the Garden / Gym } (DataService.PlacedCopies; {} before the load,
-- while provisional or without that API)
local function placedCopies(player)
	if type(DataService.PlacedCopies) ~= "function" then
		return {}
	end
	local ok, map = pcall(DataService.PlacedCopies, player)
	if ok and type(map) == "table" then
		return map
	end
	return {}
end

local function petLevelOf(player, key)
	if type(DataService.GetPetLevel) ~= "function" then
		return 1
	end
	local ok, level = pcall(DataService.GetPetLevel, player, key)
	if ok and type(level) == "number" and level == level and level >= 1 then
		return math.floor(level)
	end
	return 1
end

local function evolutionOf(player, key)
	if type(DataService.GetEvolution) ~= "function" then
		return 0
	end
	local ok, stage = pcall(DataService.GetEvolution, player, key)
	if ok and type(stage) == "number" and stage == stage and stage >= 0 then
		return math.floor(stage)
	end
	return 0
end

-- "23:1,5:0": level:stage per EquippedPets entry (Phase 4 contract 5.3; other clients draw the pet cards and the evolved
-- models from it, since PetLevels / PetGrowth only sync to the owner)
local function equippedInfo(player, profile)
	local parts = {}
	for i, key in ipairs(profile.Equipped) do
		parts[i] = tostring(petLevelOf(player, key)) .. ":" .. tostring(evolutionOf(player, key))
	end
	return table.concat(parts, ",")
end

-- Writes EquippedInfo when it changed, at most every INFO_GAP seconds per player (a burst of level-ups coalesces into
-- one deferred write that carries the final value). Written BEFORE EquippedPets when it is due, so a client that sees
-- a new list already has its levels.
local function publishInfo(player, profile)
	local attr = Config.Attr.EquippedInfo
	if type(attr) ~= "string" then
		return
	end
	local text = equippedInfo(player, profile)
	if player:GetAttribute(attr) == text then
		return
	end
	local now = os.clock()
	local state = infoState[player]
	if not state then
		state = { At = -math.huge, Pending = false }
		infoState[player] = state
	end
	if now - state.At >= INFO_GAP then
		state.At = now
		player:SetAttribute(attr, text)
		return
	end
	if state.Pending then
		return
	end
	state.Pending = true
	task.delay(INFO_GAP - (now - state.At), function()
		local s = infoState[player]
		if s then
			s.Pending = false
		end
		if not isLivePlayer(player) then
			return
		end
		local latest = DataService.GetProfile(player)
		if type(latest) ~= "table" or type(latest.Equipped) ~= "table" then
			return
		end
		local value = equippedInfo(player, latest)
		if player:GetAttribute(attr) ~= value then
			if s then
				s.At = os.clock()
			end
			player:SetAttribute(attr, value)
		end
	end)
end

-- Recomputes perks from the profile and publishes the attributes. `silent` skips PerksChanged.
local function refreshPlayer(player, silent)
	if not isLivePlayer(player) then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local perks = copyPerks(DataService.ComputePerks(profile.Equipped, profile))
	perkState[player] = { Perks = perks }
	-- the hybrid looks first: a client that sees the new EquippedPets can already draw every hybrid in it
	local looks = hybridLooks(profile)
	local currentLooks = player:GetAttribute(HYBRID_ATTR)
	if looks ~= "" or (currentLooks ~= nil and currentLooks ~= "") then
		if currentLooks ~= looks then
			player:SetAttribute(HYBRID_ATTR, looks)
		end
	end
	publishInfo(player, profile)
	player:SetAttribute(Config.Attr.EquippedPets, table.concat(profile.Equipped, ","))
	player:SetAttribute(Config.Attr.PerkStaminaRegen, perks.StaminaRegen)
	if not silent then
		PetService.PerksChanged:Fire(player)
	end
end

-- Pet Index: marks a pet as discovered. Returns true the first time. Safe when DataService predates v3.
local function markDiscovered(player, petId)
	if type(DataService.MarkDiscovered) ~= "function" then
		return false
	end
	local ok, isNew = pcall(DataService.MarkDiscovered, player, petId)
	if not ok then
		warn("[PetService] MarkDiscovered errored: " .. tostring(isNew))
		return false
	end
	return isNew == true
end

-- Every owned pet counts as discovered (DataService migrates stored profiles; this also covers pets
-- granted outside the roulette).
local function discoverOwned(player, profile)
	for petId, count in pairs(profile.Pets) do
		if type(count) == "number" and count > 0 then
			markDiscovered(player, petId)
		end
	end
	-- tier copies count for their base pet (the Index lists base pets)
	for petId, entry in pairs(type(profile.Tiers) == "table" and profile.Tiers or {}) do
		if type(entry) == "table" then
			markDiscovered(player, petId)
		end
	end
end

local function onProfileReady(player)
	if not isLivePlayer(player) then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	DataService.SyncEquipped(player)
	discoverOwned(player, profile) -- the ProfileSync snapshot already lists owned pets, so no extra Sync
	refreshPlayer(player, false)
end

local RECOVERING = "Your save is still being recovered, try again in a moment" -- a stand-in profile has no teams (activeTeam)

-- { key... } of the active team's slots and the preset number, or nil until loaded / while provisional
local function activeTeam(player)
	local teams = DataService.GetTeams(player)
	if type(teams) ~= "table" then
		return nil
	end
	return teams.Presets[teams.Active], teams.Active
end

local function teamHas(list, key)
	for i, k in ipairs(list) do
		if k == key then
			return i
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Public API: perks
----------------------------------------------------------------------

function PetService.GetEquipped(player)
	local profile = player and DataService.GetProfile(player)
	local out = {}
	if profile then
		for i, id in ipairs(profile.Equipped) do
			out[i] = id
		end
	end
	return out
end

function PetService.GetPerks(player)
	local state = player and perkState[player]
	if state then
		return copyPerks(state.Perks)
	end
	return copyPerks(ZERO_PERKS)
end

function PetService.GetTokenMultiplier(player)
	local state = player and perkState[player]
	local bonus = state and state.Perks.TokenBonus or 0
	if type(bonus) ~= "number" or bonus ~= bonus or bonus < 0 then
		bonus = 0
	end
	return 1 + bonus
end

----------------------------------------------------------------------
-- Public API: equip / unequip
----------------------------------------------------------------------

-- Equip's checks (ok, reason); `freed` (bug batch 2 #18) = Garden copies about to be taken out (the recall).
function PetService.CanEquip(player, key, freed)
	if not isLivePlayer(player) then
		return false, "Player unavailable"
	end
	if inMatch(player) then
		return false, "Pets are locked during a match"
	end
	if not validId(key) or not parseKey(key) then
		return false, "Unknown pet"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading"
	end
	if not defOf(key, profile) then
		return false, "Unknown pet"
	end
	local owned = ownedCount(profile, key)
	if owned <= 0 then
		return false, "You do not own that pet"
	end
	if trainingKeys(player)[key] then
		-- Phase 4: a training pet rests at home until its job is done (the lock: DataService.TrainingKeys)
		local def = defOf(key, profile)
		local name = type(def) == "table" and (def.DisplayName or def.Name) or key
		local left = trainingLeft(player, key)
		return false, tostring(name) .. " is training" .. (left and (" (" .. left .. " left)") or "")
	end
	local team = activeTeam(player)
	if not team then
		return false, RECOVERING
	end
	-- bug batch 2 #18: a pet with every copy in the Garden is busy gardening (the recall frees `freed` copies first)
	local rawPlaced = placedCopies(player)[key] or 0
	local placed = math.max(0, rawPlaced - (type(freed) == "number" and math.max(0, math.floor(freed)) or 0))
	if owned - placed < 1 then
		local def = defOf(key, profile)
		local name = type(def) == "table" and (def.DisplayName or def.Name) or key
		return false, tostring(name) .. " is gardening! Take it out of the garden first"
	end
	if teamHas(team, key) then
		if owned - rawPlaced < 1 then
			return true -- the recall: it keeps its slot and is back with the player once the Garden lets it go
		end
		return false, "That pet is already in your team"
	end
	if #team >= Config.Pets.MaxEquipped then
		return false, "Your team is full (" .. Config.Pets.MaxEquipped .. " pets)"
	end
	return true
end

-- Puts the key in the active team's first empty slot.
function PetService.Equip(player, key)
	local ok, reason = PetService.CanEquip(player, key, 0)
	if not ok then
		return false, reason
	end
	local team, preset = activeTeam(player)
	local list = {}
	for i, k in ipairs(team) do
		list[i] = k
	end
	list[#list + 1] = key
	return DataService.SetTeam(player, preset, list)
end

-- Takes `key` out of the active team (its slot empties, the pets behind it move up). A plain petId also matches a tier
-- copy of that pet when the Normal key is not in the team (old callers only know pet ids).
function PetService.Unequip(player, key)
	if not isLivePlayer(player) then
		return false, "Player unavailable"
	end
	if inMatch(player) then
		return false, "Pets are locked during a match"
	end
	if not validId(key) then
		return false, "Unknown pet"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading"
	end
	local team, preset = activeTeam(player)
	if not team then
		return false, RECOVERING
	end
	local slot = teamHas(team, key)
	local parsed = parseKey(key)
	if not slot and parsed and parsed.PetId and parsed.Tier == "Normal" then
		for i = #team, 1, -1 do
			local other = parseKey(team[i])
			if other and other.PetId == parsed.PetId then
				slot = i
				break
			end
		end
	end
	if not slot then
		return false, "That pet is not in your team"
	end
	local list = {}
	for i, k in ipairs(team) do
		list[i] = (i ~= slot) and k or false -- a hole: the pets behind it keep their index (a busy pet stays no new pick)
	end
	return DataService.SetTeam(player, preset, list)
end

-- Extra: brings the followers back to the active team minus busy pets (FusionService / DevService call it after removing
-- copies; PetCareService after a level-up / evolution / training start or end), republishes the attributes (EquippedPets,
-- EquippedHybrids, EquippedInfo) and perks. Returns true when the list changed.
function PetService.Refresh(player)
	if not isLivePlayer(player) then
		return false
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	local changed = DataService.SyncEquipped(player)
	refreshPlayer(player, false)
	return changed
end

----------------------------------------------------------------------
-- Public API: roulette
----------------------------------------------------------------------

-- The Secret pity (lobby-shop spec 5.2) of a { Spins, Hit } record -> PityAt (Config.Gems.SecretRoulette.PityAt, 7),
-- Since = max(0, Spins - Hit), Left = clamp(PityAt - Since, 1, PityAt). The clamp matters: two servers adding spins after
-- the same hit can merge Since above PityAt - 1; a Since of 8 shows 1 (and forces the next spin), never "in -1".
local function pityNumbers(pity)
	local cfg = type(Config.Gems) == "table" and Config.Gems.SecretRoulette or nil
	local at = type(cfg) == "table" and tonumber(cfg.PityAt) or nil
	if not at or at ~= at or at < 1 or at > 1000 or at ~= math.floor(at) then
		at = 7
	end
	local since = math.max(0, pity.Spins - pity.Hit)
	return at, since, math.max(1, math.min(at, at - since))
end

-- The attribute SecretPityLeft (Config.Attr; spec 5.2): Left of the saved pity once this load's gem settle hold ended;
-- absent while loading, provisional or not settled (DataService.GemsSettled false: a recovery's ProfileRebased fires
-- before the hold ends, so DataService.Settled is what first sets it for a stand-in). Runs on ProfileLoaded,
-- ProfileRebased and Settled and after each Secret Roulette spin; written only when it changed.
local function refreshPityAttr(player)
	if not isLivePlayer(player) then
		return
	end
	local attr = Config.Attr.SecretPityLeft or "SecretPityLeft"
	local left = nil
	local settled = type(DataService.GemsSettled) == "function" and DataService.GemsSettled(player) == true
	local pity = settled and type(DataService.GetPity) == "function" and DataService.GetPity(player) or nil
	if type(pity) == "table" and type(pity.Spins) == "number" and type(pity.Hit) == "number" then
		local _, _, n = pityNumbers(pity)
		left = n
	end
	if player:GetAttribute(attr) ~= left then
		player:SetAttribute(attr, left)
	end
end

-- Cosmetic strip: STRIP_LENGTH pet ids drawn like real rolls (so it shows realistic rarities), with the real result at
-- WIN_INDEX. `roll` = the roulette's roll (PetCatalog.RollPet when nil), always the plain call roll(id, RNG.Strip):
-- never RNG.Roll and never forced, so a strip says nothing about the roll generator and a forced pull's strip shows the
-- normal odds.
local function buildStrip(rouletteId, resultId, roll)
	RNG.Strip = RNG.Strip or Util.NewRng()
	local strip = {}
	for i = 1, STRIP_LENGTH do
		local id = nil
		local ok, rolled = pcall(roll or PetCatalog.RollPet, rouletteId, RNG.Strip)
		if ok and type(rolled) == "string" then
			id = rolled
		end
		strip[i] = id or resultId
	end
	strip[WIN_INDEX] = resultId
	return strip
end

-- Tells the server about a rare pull. Everybody else sees it at once; the puller sees it after
-- the reveal animation so it does not spoil the result.
local function announcePull(player, def)
	local order = rarityOrder[def.Rarity] or 0
	if order < ANNOUNCE_ORDER then
		return
	end
	local text = player.DisplayName .. " pulled " .. def.Name .. "!"
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			notify(other, text, "good", 4)
		end
	end
	task.delay(ANNOUNCE_DELAY, function()
		if player.Parent then
			notify(player, text, "good", 4)
		end
	end)
end

-- Copies of a pet in any form (Normal + tier copies): IsNew keeps meaning "first time owned".
local function ownedAnyForm(profile, petId)
	local n = profile.Pets[petId] or 0
	local entry = type(profile.Tiers) == "table" and profile.Tiers[petId]
	if type(entry) == "table" then
		for _, count in pairs(entry) do
			if type(count) == "number" and count > 0 then
				n = n + count
			end
		end
	end
	return n
end

-- The plan part of a pet grant (reads only, nothing written; the roll's step 3 and PetService.GrantPet): n Normal
-- copies of petId on top of `before` copies of it this request planned already (`earlier` = every copy it planned).
-- -> { PetId, Key, Granted, Count, IsNew, NewDiscovery, FirstPet }
local function planCopies(profile, petId, n, before, earlier)
	before, earlier = before or 0, earlier or 0
	local discovered = type(profile.Discovered) == "table" and profile.Discovered[petId] == true
	return {
		PetId = petId,
		Key = petId, -- the copy's key (a grant always adds Normal copies)
		Granted = n,
		Count = (profile.Pets[petId] or 0) + before + n,
		IsNew = ownedAnyForm(profile, petId) + before == 0, -- "first time owned"
		NewDiscovery = not discovered and before == 0,
		FirstPet = totalPets(profile) + earlier == 0,
	}
end

-- The write part (plain writes, nothing here yields or refuses; the caller checked the stack room and did its own spin /
-- charge): the copies, the first pet ever into the active team's slot 1 (a provisional profile has no teams yet: into
-- its Equipped list, which becomes a team once the recovery migrates it; the team's SetTeam only when `withTeam`: the
-- roll runs it after its step), the Index discovery (before the caller's Sync, so the snapshot shows it), the level
-- raised to `level` when given (never lowered), MarkDirty. -> newDiscovery, level (or nil)
local function writeCopies(player, profile, plan, level, withTeam)
	local petId = plan.PetId
	profile.Pets[petId] = (profile.Pets[petId] or 0) + plan.Granted
	if plan.FirstPet then
		local team, preset = activeTeam(player)
		if not team then
			table.insert(profile.Equipped, petId)
		elseif withTeam and #team == 0 then
			DataService.SetTeam(player, preset, { petId })
		end
	end
	local newDiscovery = markDiscovered(player, petId)
	local levelNow = nil
	if type(level) == "number" and type(DataService.GetPetLevel) == "function" and type(DataService.SetPetLevel) == "function" then
		local current = DataService.GetPetLevel(player, petId) or 1
		levelNow = math.max(current, level)
		if levelNow > current then
			DataService.SetPetLevel(player, petId, levelNow)
		end
	end
	DataService.MarkDirty(player)
	return newDiscovery, levelNow
end

-- Step 2 of the money step (see the header): `spins` pulls from RNG.Roll in order, a full stack re-picked inside its
-- rarity or turned into a Substitute, the AllowSecret guard; the Secret pity's forced pull (ctx.Pity.Forced, pull 1:
-- roll(id, RNG.Roll, { ForceRarity = "Secret" }), which must come back a Secret like any roll must come back a pet).
-- ctx = { Id, Roll, AllowSecret, Pity }.
-- -> { { PetId, Rarity, Pity = true | nil, Substitute = { Tokens } | nil }... } | nil, reason (nothing written either way)
local function rollPulls(profile, ctx, spins)
	RNG.Roll = RNG.Roll or Util.NewRng()
	local pulls, taken = {}, {}
	local function isFull(petId)
		return (profile.Pets[petId] or 0) + (taken[petId] or 0) >= Config.Pets.MaxPerStack
	end
	for j = 1, spins do
		local forced = j == 1 and type(ctx.Pity) == "table" and ctx.Pity.Forced == true
		local ok, petId
		if forced then
			ok, petId = pcall(ctx.Roll, ctx.Id, RNG.Roll, { ForceRarity = SECRET_RARITY })
		else
			ok, petId = pcall(ctx.Roll, ctx.Id, RNG.Roll)
		end
		local def = ok and type(petId) == "string" and PetCatalog.Get(petId) or nil
		if not def or (forced and def.Rarity ~= SECRET_RARITY) then
			return nil, "The roulette jammed, try again"
		end
		if def.Rarity == SECRET_RARITY and ctx.AllowSecret ~= true then
			-- Secret pets only come from a roulette with AllowSecret: never from any other one, whatever it rolled
			return nil, "The roulette jammed, try again"
		end
		local pull = { PetId = petId, Rarity = def.Rarity, Pity = forced or nil }
		if isFull(petId) then
			local open = {}
			for _, other in ipairs(PetCatalog.RarityPool(ctx.Id, def.Rarity)) do
				if not isFull(other.Id) then
					open[#open + 1] = other.Id
				end
			end
			if #open > 0 then
				local k = tonumber(RNG.Roll:Int(1, #open)) or 1
				pull.PetId = open[math.max(1, math.min(#open, math.floor(k)))]
			else
				local reward = type(Config.Index) == "table" and type(Config.Index.Rewards) == "table" and Config.Index.Rewards[def.Rarity]
				pull.Substitute = { Tokens = type(reward) == "table" and tonumber(reward.Tokens) or 0 }
			end
		end
		if not pull.Substitute then
			taken[pull.PetId] = (taken[pull.PetId] or 0) + 1
		end
		pulls[j] = pull
	end
	return pulls
end

-- Step 3 (the caller runs it in a pcall; nothing written): each pull's grant plan, PoolSize and strip, the Secret pity's
-- new numbers (ctx.NewPity = { Spins, Hit }: Spins + 1 per pull, Hit = that Spins after a Secret pull, a substitute
-- included; reply.SecretPity = { Left }) and the reply (header). ctx = { Id, Currency, UnitPrice, Price, Roll, Pity }.
-- -> reply, plans ([j] = planCopies' plan; nil for a substitute)
local function planSpin(profile, ctx, pulls)
	if faults.plan then
		faults.plan()
	end
	local plans, out, before, earlier = {}, {}, {}, 0
	for j, pull in ipairs(pulls) do
		local petId = pull.PetId
		local item = {
			PetId = petId,
			Key = petId,
			Rarity = pull.Rarity,
			PoolSize = #PetCatalog.RarityPool(ctx.Id, pull.Rarity),
			Strip = buildStrip(ctx.Id, petId, ctx.Roll),
			Pity = pull.Pity,
			Substitute = pull.Substitute,
		}
		if pull.Substitute then
			-- the stack is full: nothing is granted, the reveal shows the full stack
			item.IsNew, item.NewDiscovery = false, false
			item.Count = (profile.Pets[petId] or 0) + (before[petId] or 0)
		else
			local plan = planCopies(profile, petId, 1, before[petId], earlier)
			item.IsNew, item.NewDiscovery, item.Count = plan.IsNew, plan.NewDiscovery, plan.Count
			plans[j] = plan
			before[petId] = (before[petId] or 0) + 1
			earlier = earlier + 1
		end
		out[j] = item
	end
	local first = out[1]
	local reply = {
		Ok = true,
		RouletteId = ctx.Id,
		Currency = ctx.Currency,
		Spins = #out,
		UnitPrice = ctx.UnitPrice,
		Price = ctx.Price,
		Pulls = out,
		PetId = first.PetId,
		Key = first.Key,
		IsNew = first.IsNew,
		NewDiscovery = first.NewDiscovery,
		Count = first.Count,
		Strip = first.Strip,
	}
	if type(ctx.Pity) == "table" then
		local spins, hit = ctx.Pity.Spins, ctx.Pity.Hit
		for _, item in ipairs(out) do
			spins = spins + 1
			if item.Rarity == SECRET_RARITY then
				hit = spins
			end
		end
		if spins > 1e9 then
			error("the Secret pity count is out of range") -- SetPity would refuse it after the charge: refuse it here
		end
		ctx.NewPity = { Spins = spins, Hit = hit }
		local _, _, left = pityNumbers(ctx.NewPity)
		reply.SecretPity = { Left = left }
	end
	return reply, plans
end

-- The optional currency of a spin: nil (the roulette's own), "Tokens" or "Gems" (any case; also { Currency = ... }).
-- Returns "Tokens" | "Gems" | nil, or false for anything else.
local function parseCurrency(currency)
	if currency == nil then
		return nil
	end
	if type(currency) == "table" then
		currency = rawget(currency, "Currency")
		if currency == nil then
			return nil
		end
	end
	if type(currency) ~= "string" or #currency > MAX_CURRENCY_LENGTH then
		return false
	end
	local lower = string.lower(currency)
	if lower == "gems" or lower == "gem" then
		return "Gems"
	elseif lower == "tokens" or lower == "token" or lower == "cloudtokens" then
		return "Tokens"
	end
	return false
end

-- A gems-only roulette (the Secret roulette at the Storm Altar) by id, or nil. GemService knows them.
local function gemsOnlyRoulette(rouletteId)
	local gems = getGemService()
	if not gems or type(gems.GetRoulette) ~= "function" then
		return nil
	end
	local ok, def = pcall(gems.GetRoulette, rouletteId)
	if ok and type(def) == "table" and def.GemsOnly == true then
		return def
	end
	return nil
end

-- The gem part of step 1: the settle hold (spec 5.2: a gem-priced spin waits for DataService.GemsSettled; fails closed
-- when the call errors, skipped without that API), then GemService.Quote (gem price, PolicyService check, the
-- roulette's roll; its texts, the lock unchanged). Fills ctx.UnitPrice / Roll / AllowSecret. -> ok, reason
local function gemQuote(player, ctx)
	if type(DataService.GemsSettled) == "function" then
		local okSettle, settled = pcall(DataService.GemsSettled, player)
		if not okSettle or settled ~= true then
			return false, "Your data is still loading"
		end
	end
	local gems = getGemService()
	if not gems or type(gems.Quote) ~= "function" or type(DataService.SpendGems) ~= "function" or type(DataService.GetGems) ~= "function" then
		return false, "Gem roulettes are not available right now"
	end
	local okQuote, ok, quote = pcall(gems.Quote, player, ctx.Id)
	if not okQuote then
		warn("[PetService] GemService.Quote errored: " .. tostring(ok))
		return false, "Gem roulettes are not available right now"
	end
	if not ok then
		return false, type(quote) == "string" and quote or "Gem roulettes are not available right now"
	end
	local price = type(quote) == "table" and quote.Price or nil
	if type(price) ~= "number" or price ~= price or price < 1 or price ~= math.floor(price) or price > 1e9 then
		return false, "Gem roulettes are not available right now"
	end
	ctx.UnitPrice = price
	ctx.Roll = type(quote.Roll) == "function" and quote.Roll or ctx.Roll
	ctx.AllowSecret = quote.AllowSecret == true
	return true
end

-- The money step (see the header). Never yields; nothing refuses after the roll.
function PetService.BuyRoulette(player, rouletteId, currency, spins)
	-- step 1: the checks
	if not isLivePlayer(player) then
		return false, "Player unavailable"
	end
	if type(rouletteId) ~= "string" then
		return false, "Unknown roulette"
	end
	local roulette = roulettes[rouletteId]
	-- not a token roulette: a gems-only one (the Secret roulette) is paid in Gems even when no currency is named
	local gemsOnly = not roulette and gemsOnlyRoulette(rouletteId) or nil
	if not roulette and not gemsOnly then
		return false, "Unknown roulette"
	end
	local paidWith = parseCurrency(currency)
	if paidWith == false then
		return false, "Unknown currency"
	end
	if gemsOnly then
		if paidWith == "Tokens" then
			return false, tostring(gemsOnly.DisplayName or "That roulette") .. " takes Gems only"
		end
		paidWith = "Gems"
	end
	if spins == nil then
		spins = 1
	end
	if (spins ~= 1 and spins ~= 3) or (spins == 3 and gemsOnly) then
		return false, "Bad spins"
	end
	if inMatch(player) then
		return false, "The shop is closed during a match"
	end
	if not PetCatalog or type(PetCatalog.RollPet) ~= "function" or type(PetCatalog.Get) ~= "function" or type(PetCatalog.RarityPool) ~= "function" then
		return false, "Pets are unavailable right now"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading"
	end
	-- the Secret pity (spec 5.2) reads the saved record: the Secret Roulette is refused while provisional or when GetPity
	-- cannot answer (fails closed); a pull is forced once Since >= PityAt - 1. Token roulettes never touch it.
	local pity = nil
	local secretDef = type(Config.Gems) == "table" and Config.Gems.SecretRoulette or nil
	if gemsOnly and type(secretDef) == "table" and rouletteId == secretDef.Id then
		local okPity, read = pcall(function()
			if type(DataService.IsProvisional) == "function" and DataService.IsProvisional(player) == true then
				return nil
			end
			return DataService.GetPity(player)
		end)
		local s = okPity and type(read) == "table" and tonumber(read.Spins) or nil
		local h = okPity and type(read) == "table" and tonumber(read.Hit) or nil
		if not s or not h or s ~= math.floor(s) or h ~= math.floor(h) or h < 0 or h > s or s > 1e9 then
			return false, "Your data is still loading"
		end
		local at, since = pityNumbers({ Spins = s, Hit = h })
		pity = { Spins = s, Hit = h, Forced = since >= at - 1 }
	end
	local ctx = {
		Id = rouletteId,
		Currency = paidWith or "Tokens",
		Roll = PetCatalog.RollPet, -- read now: tests that replace RollPet still steer the pulls
		AllowSecret = roulette ~= nil and roulette.AllowSecret == true,
		UnitPrice = roulette and roulette.Price,
		Pity = pity, -- the Secret Roulette only: { Spins, Hit, Forced } read above
	}
	if ctx.Currency == "Gems" then
		local okQuote, reason = gemQuote(player, ctx)
		if not okQuote then
			return false, reason
		end
	end
	ctx.Price = ctx.UnitPrice * spins -- computed once: the balance check and the charge use it
	local poor = ctx.Currency == "Gems" and "Not enough Gems" or "Not enough cloud tokens"
	local balance = ctx.Currency == "Gems" and DataService.GetGems(player) or DataService.GetTokens(player)
	if balance < ctx.Price then
		return false, poor
	end

	-- step 2: the pulls (the only refusal after them: the AllowSecret guard, still before the charge)
	local pulls, why = rollPulls(profile, ctx, spins)
	if not pulls then
		return false, why
	end

	-- step 3: everything that can fail, before the charge
	local okPlan, reply, plans = pcall(planSpin, profile, ctx, pulls)
	if not okPlan or type(reply) ~= "table" then
		warn("[PetService] spin plan failed (nothing charged): " .. tostring(reply))
		return false, "The roulette jammed, try again"
	end

	-- step 4: one charge
	local charged
	if ctx.Currency == "Gems" then
		charged = DataService.SpendGems(player, ctx.Price)
	else
		charged = DataService.SpendTokens(player, ctx.Price)
	end
	if not charged then
		return false, poor
	end

	-- step 5: plain writes only
	local firstPet = nil
	for j, pull in ipairs(pulls) do
		if pull.Substitute then
			DataService.AddTokens(player, pull.Substitute.Tokens)
		else
			writeCopies(player, profile, plans[j], nil, false)
			if plans[j].FirstPet then
				firstPet = pull.PetId
			end
		end
	end
	profile.Stats.Spins = profile.Stats.Spins + spins
	if ctx.NewPity and not DataService.SetPity(player, ctx.NewPity.Spins, ctx.NewPity.Hit) then
		-- cannot happen: GetPity answered in step 1 and step 3 checked the numbers; logged, never undoes the grant
		warn("[PetService] SetPity refused the Secret pity numbers after the charge")
	end
	DataService.MarkDirty(player)

	-- step 6: after the step, each in its own pcall (a failure is logged and never undoes the grant)
	local after = {
		{ "refresh", function()
			reply.Tokens = DataService.GetTokens(player) -- the balances after the charge and the substitute tokens
			reply.Gems = type(DataService.GetGems) == "function" and DataService.GetGems(player) or nil
			if faults.after then
				faults.after()
			end
			refreshPlayer(player, false)
		end },
		{ "pity", function()
			if ctx.Pity then
				refreshPityAttr(player) -- the attribute follows the new count at once (the reply carries the same Left)
			end
		end },
		{ "team", function()
			-- the first pet ever joins the active team's slot 1 (a provisional profile got it in its Equipped list)
			local team, preset = activeTeam(player)
			if firstPet and team and #team == 0 then
				DataService.SetTeam(player, preset, { firstPet })
			end
		end },
		{ "sync", function()
			DataService.Sync(player)
		end },
		{ "reply", function()
			fireClient("RouletteResult", player, reply)
		end },
	}
	for _, pull in ipairs(pulls) do
		after[#after + 1] = { "rolled", function()
			PetService.Rolled:Fire(player, pull.PetId) -- a substitute pull fires with its rolled pet (tutorial, Index)
		end }
	end
	for _, pull in ipairs(pulls) do
		after[#after + 1] = { "announce", function()
			announcePull(player, PetCatalog.Get(pull.PetId))
		end }
	end
	for _, call in ipairs(after) do
		local ok, err = pcall(call[2])
		if not ok then
			warn("[PetService] after a spin (" .. call[1] .. "): " .. tostring(err))
		end
	end
	return true, reply
end

-- store (2026-11-04, spec 5.4): the one pet-grant path outside the roulette (see the header). Non-yielding; nothing
-- between the checks and the write yields. A full stack answers "Stack full" and writes nothing: the caller
-- substitutes (StoreService pays the rarity's Index Tokens, DailyService pays Days[7].Else).
function PetService.GrantPet(player, petId, opts)
	if not isLivePlayer(player) then
		return false, "Player unavailable"
	end
	opts = type(opts) == "table" and opts or {}
	local def = (PetCatalog and type(PetCatalog.Get) == "function" and type(petId) == "string") and PetCatalog.Get(petId) or nil
	if not def then
		return false, "Unknown pet"
	end
	local count = opts.Count
	if count == nil then
		count = 1
	end
	if type(count) ~= "number" or count ~= count or count < 1 or count > 1e6 or count ~= math.floor(count) then
		return false, "Bad count"
	end
	local level = opts.Level
	if level ~= nil then
		local top = (type(PetCatalog.MaxPetLevel) == "function" and PetCatalog.MaxPetLevel()) or 100
		if type(level) ~= "number" or level ~= level or level < 1 or level ~= math.floor(level) then
			return false, "Bad level"
		end
		level = math.min(level, top)
	end
	local profile = DataService.GetProfile(player)
	if not profile or (type(DataService.IsProvisional) == "function" and DataService.IsProvisional(player) == true) then
		return false, "Your save is still loading"
	end
	local room = Config.Pets.MaxPerStack - (profile.Pets[petId] or 0)
	if room <= 0 then
		return false, "Stack full"
	end
	-- the roll's own two parts in a row (nothing yields), then the perks / attributes and the Sync
	local plan = planCopies(profile, petId, math.min(count, room))
	local newDiscovery, levelNow = writeCopies(player, profile, plan, level, true)
	refreshPlayer(player, false)
	DataService.Sync(player)
	return true, {
		PetId = petId,
		Key = petId,
		Granted = plan.Granted,
		Count = plan.Count,
		IsNew = plan.IsNew,
		NewDiscovery = newDiscovery,
		Level = levelNow,
	}
end

-- Studio and the mock only (RunService:IsStudio(); false elsewhere): seeded generators for tests (anything with
-- :Float(a, b) and :Int(a, b), e.g. Util.NewRng(seed)); nil keeps the current one.
function PetService._SetRngForTest(rollRng, stripRng)
	if not game:GetService("RunService"):IsStudio() then
		return false
	end
	if rollRng ~= nil then
		RNG.Roll = rollRng
	end
	if stripRng ~= nil then
		RNG.Strip = stripRng
	end
	return true
end

-- Studio and the mock only: fn() runs inside the money step's step 3 (stage "plan", before the charge) or inside its
-- step-6 refresh pcall (stage "after"); a nil fn clears that stage.
function PetService._SetFaultForTest(stage, fn)
	if not game:GetService("RunService"):IsStudio() or (stage ~= "plan" and stage ~= "after") then
		return false
	end
	faults[stage] = type(fn) == "function" and fn or nil
	return true
end

----------------------------------------------------------------------
-- Remotes (client -> server). Rate limited and type checked.
----------------------------------------------------------------------

local function connectRemotes()
	if remotesConnected then
		return
	end
	local okBuy, buyRemote = pcall(Remotes.Get, "BuyRoulette")
	local okEquip, equipRemote = pcall(Remotes.Get, "EquipPet")
	local okUnequip, unequipRemote = pcall(Remotes.Get, "UnequipPet")
	if not (okBuy and okEquip and okUnequip) then
		warn("[PetService] pet remotes are missing (did Remotes.Init run?)")
		return
	end
	remotesConnected = true

	-- BuyRoulette(rouletteId, currency|nil, spins|nil): currency "Tokens" / "Gems" (or nil: the roulette's own), spins
	-- nil / 1 / 3 (3 never on a gems-only roulette; anything else is dropped silently), see BuyRoulette
	buyRemote.OnServerEvent:Connect(function(player, rouletteId, currency, spins)
		if rateLimited(player, "BuyRoulette", REMOTE_COOLDOWN) then
			return
		end
		if type(rouletteId) ~= "string" or #rouletteId > MAX_ID_LENGTH then
			return
		end
		if spins ~= nil and spins ~= 1 and spins ~= 3 then
			return
		end
		if spins == 3 and gemsOnlyRoulette(rouletteId) then
			return
		end
		local ok, success, info = pcall(PetService.BuyRoulette, player, rouletteId, currency, spins)
		if not ok then
			warn("[PetService] BuyRoulette errored: " .. tostring(success))
			success, info = false, "Something went wrong, try again"
		end
		if not success then
			local answer = {
				Ok = false,
				Reason = tostring(info),
				RouletteId = rouletteId,
				Currency = (parseCurrency(currency) == "Gems" or gemsOnlyRoulette(rouletteId)) and "Gems" or "Tokens",
				Spins = spins or 1,
				Tokens = DataService.GetTokens(player),
			}
			if type(DataService.GetGems) == "function" then
				answer.Gems = DataService.GetGems(player)
			end
			fireClient("RouletteResult", player, answer)
		end
	end)

	local function handleEquip(remoteName, fn)
		return function(player, petId)
			if rateLimited(player, remoteName, REMOTE_COOLDOWN) then
				return
			end
			if type(petId) ~= "string" or #petId > MAX_ID_LENGTH then
				return
			end
			local ok, success, reason = pcall(fn, player, petId)
			if not ok then
				warn("[PetService] " .. remoteName .. " errored: " .. tostring(success))
				return
			end
			if not success and reason then
				notify(player, tostring(reason), "bad", 3)
			end
		end
	end
	equipRemote.OnServerEvent:Connect(handleEquip("EquipPet", PetService.Equip))
	unequipRemote.OnServerEvent:Connect(handleEquip("UnequipPet", PetService.Unequip))
end

----------------------------------------------------------------------
-- Roulette machines in the lobby: one ProximityPrompt each
----------------------------------------------------------------------

local function buildPrompts(lobbyInfo)
	for _, prompt in ipairs(promptObjects) do
		if prompt.Parent then
			prompt:Destroy()
		end
	end
	promptObjects = {}

	local shop = type(lobbyInfo) == "table" and lobbyInfo.Shop
	local machines = type(shop) == "table" and shop.Roulettes
	if type(machines) ~= "table" then
		warn("[PetService] lobbyInfo.Shop.Roulettes missing: no roulette prompts created")
		return
	end

	for _, roulette in ipairs(Config.Roulettes) do
		local machine = machines[roulette.Id]
		local part = type(machine) == "table" and machine.PromptPart
		if part and typeof(part) == "Instance" then
			local old = part:FindFirstChild(PROMPT_NAME)
			if old then
				old:Destroy()
			end
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = PROMPT_NAME
			prompt.ActionText = "Open"
			prompt.ObjectText = roulette.DisplayName
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
			table.insert(promptObjects, prompt)

			local rouletteId = roulette.Id
			prompt.Triggered:Connect(function(player)
				if not isLivePlayer(player) then
					return
				end
				if player:GetAttribute(Config.Attr.InMatch) == true then
					return
				end
				if rateLimited(player, "Prompt_" .. rouletteId, PROMPT_COOLDOWN) then
					return
				end
				fireClient("OpenPanel", player, "Shop", { Tab = "Roulette", RouletteId = rouletteId })
			end)
		else
			warn("[PetService] no PromptPart for roulette " .. tostring(roulette.Id))
		end
	end
end

----------------------------------------------------------------------
-- Player lifecycle
----------------------------------------------------------------------

local function onPlayerAdded(player)
	if DataService.GetProfile(player) then
		task.spawn(onProfileReady, player)
	end
end

local function connectPlayers()
	if playersConnected then
		return
	end
	playersConnected = true

	DataService.ProfileLoaded:Connect(function(player)
		onProfileReady(player)
		pcall(refreshPityAttr, player)
	end)
	DataService.ProfileRebased:Connect(function(player)
		onProfileReady(player)
		pcall(refreshPityAttr, player) -- another server's Secret spins arrive here (a recovery: still not settled)
	end)
	if type(DataService.Settled) == "table" and type(DataService.Settled.Connect) == "function" then
		DataService.Settled:Connect(function(player)
			pcall(refreshPityAttr, player) -- the gem settle hold ended: the first SecretPityLeft of this load
		end)
	end
	DataService.TeamsChanged:Connect(function(player)
		refreshPlayer(player, false) -- the followers are the active team: every team change republishes them
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		perkState[player] = nil
		lastCall[player] = nil
		infoState[player] = nil
	end)
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------

function PetService.Init(lobbyInfo, deps)
	if type(deps) == "table" then
		if deps.DataService then
			DataService = deps.DataService
		end
	end
	if type(DataService.Init) == "function" then
		pcall(DataService.Init)
	end
	if not PetCatalog then
		warn("[PetService] PetCatalog is missing: roulettes and equipping are limited")
	end
	-- the money step's generators: engine seeded once (Random.new() without a seed), never sent
	RNG.Roll = RNG.Roll or Util.NewRng()
	RNG.Strip = RNG.Strip or Util.NewRng()
	connectRemotes()
	connectPlayers()
	buildPrompts(lobbyInfo)
end

return PetService
