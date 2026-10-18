-- TutorialService: server-authoritative progress of the new-player tutorial (ARCHITECTURE_V3.md section 4, the
-- Phase 2 "Tutorial" paragraph, rewritten by Phase 4 "Phase 4 build contract" section 9: claim a home, put a pet in the
-- Pet Garden, scoop its rainbow coins, build the Food Machine, feed a pet; the Phase 3 chapter: go to the Battle Arena,
-- set a battle team, win Trial 1, see a Boss Raid; and the Phase 4 chapter: train a pet, win a Champion Ring round, walk
-- through the home portal).
--
--   TutorialService.Init(lobbyInfo, deps)     deps = { DataService, PetService, MatchService, SpotService, IndexService,
--                                                      TycoonService, PetCareService, BattleService, ArenaInfo }
--                                                      (missing ones are looked up; ArenaInfo = ArenaBuilder.Build's)
--   TutorialService.GetState(player) -> payload | nil       (the TutorialState payload below, a fresh copy)
--   TutorialService.HandleEvent(player, eventName) -> ok, reason      (what the TutorialEvent remote does)
--   TutorialService.Reload(player, opts) -> ok   drops the running tutorial and reads it again from the profile
--                                                (opts.Replay = true: no chapter rewards again; the developer tools)
--   TutorialService.StepCompleted              Util.Signal, Fire(player, stepId, stepIndex)
--   TutorialService.Finished                   Util.Signal, Fire(player, skipped)
--
-- Steps come from shared/TutorialSteps.lua, in CHAPTERS (1 = the basics, 2 = the tycoon home, 3 = pet battles, 4 = pets
-- make the money).
-- Progress lives in the
-- profile (DataService.GetTutorial / SetTutorial: { Step, Done, Gifted }); DataService merges Done and Gifted so they
-- stick once true, so the stored fields mean:
--   Done = false              chapter 1 is running at Step
--   Done = true, Step inside a later chapter (2..)   chapter 1 is behind the player and that chapter runs at Step
--                             (a player who finished the Phase 1 tutorial has Step = 10: the home chapter starts there)
--   Done = true, Step = #Steps + 1   everything finished (a chapter added later starts from there)
--   Done = true, Step = SKIPPED_STEP (or a chapter-1 step: old saves)   skipped: no tutorial any more
-- Completing a step marked ChapterEnd pays that chapter's reward once (the step is stored BEFORE paying, so a crash
-- can never pay twice): chapter 1 = Config.Tutorial.FinishReward (tokens), chapter 2 = HOME_FINISH_CASH Cash,
-- chapter 3 = ARENA_FINISH_TOKENS Cloud Tokens, chapter 4 = RING_FINISH_TOKENS Cloud Tokens.
--
-- A step completes on what the SERVER observes:
--   Claimed       the player owns a home plot (SpotService.GetSpot; TycoonService.Claimed / the SpotIndex attribute
--                 for an instant answer, a 2 Hz poll as the backup)
--   Built         the saved home has the step's Station at level >= 1 (DataService.GetHome; TycoonService.HomeChanged)
--   Collected     (Phase 2, retired with the Collector: no step uses it, a step that still did passes at once)
--   Fed           PetCareService.Fed (a feed at the Food Machine / the Pets panel)
--   GardenPlaced  (Phase 4) a pet sits in an OPEN place of the Pet Garden (Home.Garden, TycoonCatalog.GardenSlots;
--                 TycoonService.HomeChanged + the poll)
--   CoinsScooped  TycoonService.CoinsScooped while the step runs; a home that already has the Food Machine passes at once
--   TrainingStarted  PetCareService.TrainingStarted, or any training job / rank in DataService.GetGrowthMap
--   RingWon       BattleService.BattleEnded with Mode "Ring" and Won, or DataService.GetRing(player).Best >= 1
--   PortalUsed    TycoonService.PortalUsed while the step runs (the player walked through their home portal)
--   NearSpot      2 Hz poll: the character within 14 studs (horizontally) of SpotService.GetSpot(player).Center
--   Rolled        PetService.Rolled (backup: Profile.Stats.Spins grew since the step began)
--   Equipped      the equipped list changed to a non-empty one (PetService.PerksChanged / attribute EquippedPets),
--                 or the client reports "PetsOpened" while a pet is equipped
--   MatchStarted  / MatchEnded: the player attribute InMatch turning true / false
--   ArenaReached  (Phase 3) the character stands in the Battle Arena: ArenaBuilder.InArena(position), else within
--                 ArenaInfo.Radius of ArenaInfo.Center (2 Hz poll)
--   TeamSet       the active battle team holds the player's pets: DataService.ActiveTeamKeys has at least
--                 min(3, the pets that can join a team: DataService.FieldableKeys) entries, so a player with one pet
--                 passes with that one pet and a player with many must field three (DataService.TeamsChanged + the poll)
--   TrialWon      Trial level 1 is cleared: BattleService.BattleEnded (a Trial the player won) or the saved
--                 Battle.TrialCleared / TrialBest (DataService.GetBattle)
--   RaidSeen      the player joined a Boss Raid (BattleService.RaidJoined / a Raid BattleEnded naming them), has a raid
--                 in the record (Battle.Raids), or stands in the arena while BattleService.GetRaidStatus() is not nil
--   Next / ShopOpened / IndexOpened: client reports through the TutorialEvent remote, accepted only when they
--                 match the CURRENT step. "Skip" ends the tutorial (no reward, no later chapter); "Sync" asks for the
--                 current state again. The remote is type checked and rate limited.
-- Entering a Gift step grants Config.Tutorial.GiftTokens once (Tutorial.Gifted is stored first). A step that cannot
-- be done in this server because a service is missing (no PetService, MatchService, TycoonService, PetCareService)
-- is passed automatically, and so is a "Claimed" step while every plot stays taken for a minute.
--
-- Guide targets of the home steps are resolved HERE (the client only knows the lobby names): the gate of the plot to
-- claim (the claimed plot, else the last plot when free, else the nearest free one; pinned while it stays free so
-- the arrow does not hop between plots), a buy pad on the own plot (HomeBuilder.GetPad, else the TycoonCatalog slot),
-- the next pad on the way to a station (its prerequisites first), a built station (the Food Machine's Hopper, a
-- Training Place mat), the first empty open place of the Pet Garden, the fullest rainbow-coin pile
-- (TycoonService.Piles), or the Shop / the Pets menu button when a pet is missing. They are sent as
-- { Kind = "Spot", Position, SpotIndex, Label } (or { Kind = "Menu", Id = "Pets" }) with a matching Hint, and the
-- poll re-sends the state whenever the target or the hint changes. Phase 3 targets { Kind = "Arena", Place } are
-- resolved from ArenaInfo the same way (sent as Kind "Spot" + Position: the client draws its guide arrow for those):
-- "Gate" = ArenaInfo.Spawn (the forum), "Trials" = ArenaInfo.TrialPortal, "Floor" = the colosseum floor, "Ring" = the
-- Champion Ring portal (ArenaInfo.RingPortal; the gate of a free home first while the player has none); no arrow while
-- the player fights (attribute InBattle). The raid step's hint counts down to the next raid in minutes
-- (EventService.SecondsUntil) or says that one is running.
--
-- TutorialState payload (server -> that player, on join, on every change, on "Sync"):
--   { Step = n, Total = #Steps, Id, Title, Text, Target = {Kind, Id, Label, Position = Vector3|nil, SpotIndex},
--     CompleteOn, Hint, Button, Gift = bool, Chapter, Done = bool, Completed = bool (finished this session),
--     Skipped = bool, Reward = tokens granted on completion }
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local TutorialService = {}
TutorialService.StepCompleted = Util.Signal()
TutorialService.Finished = Util.Signal()

local POLL_INTERVAL = 0.5 -- seconds (NearSpot / level checks / target refresh run at 2 Hz)
local EVENT_COOLDOWN = 0.25 -- seconds per player between TutorialEvent requests
local SYNC_COOLDOWN = 1 -- seconds per player between "Sync" requests
local MAX_EVENT_LENGTH = 32
local NEAR_SPOT_RADIUS = 14 -- studs, horizontal
local NEAR_SPOT_HEIGHT = 24 -- studs of vertical slack (the root stands ~3 studs above the yard)
local NO_SPOT_GRACE = 10 -- seconds without a spot before a NearSpot step is passed
local NO_FREE_GRACE = 60 -- seconds without any free plot before a Claimed step is passed
local SKIPPED_STEP = 1000 -- Tutorial.Step of a skipped tutorial (DataService caps Step at 1000): no later chapter
-- Not in Config (lead-owned): the home chapter's reward, paid once when the "feed" step completes.
local HOME_FINISH_CASH = 1000
-- Not in Config (lead-owned): the pet-battle chapter's reward, paid once when its last step completes.
local ARENA_FINISH_TOKENS = 500
-- Not in Config (lead-owned): the Phase 4 chapter's reward ("Pets tutorial complete!"), paid once by its last step.
local RING_FINISH_TOKENS = 300
local ARENA_RADIUS = 160 -- studs around ArenaInfo.Center that count as the arena when ArenaBuilder.InArena is missing
local ATTR_IN_BATTLE = "InBattle" -- BattleService's attribute (the battle id while the player fights)
local STATION_FRONT_GAP = 2.5 -- studs in front of a station's footprint where its guide arrow stands
local TOKEN_GLYPH = "\226\152\129" -- cloud

-- client event -> the CompleteOn it can complete (Skip / Sync are handled separately)
local EVENT_COMPLETES = {
	Next = "Next",
	ShopOpened = "ShopOpened",
	IndexOpened = "IndexOpened",
	PetsOpened = "Equipped",
}

local KNOWN_COMPLETE_ON = {
	Next = true,
	NearSpot = true,
	ShopOpened = true,
	Rolled = true,
	Equipped = true,
	IndexOpened = true,
	MatchStarted = true,
	MatchEnded = true,
	-- Phase 2 (the home chapter)
	Claimed = true,
	Built = true,
	Collected = true,
	Fed = true,
	-- Phase 3 (the pet-battle chapter)
	ArenaReached = true,
	TeamSet = true,
	TrialWon = true,
	RaidSeen = true,
	-- Phase 4 (chapter 2 rewritten + chapter 4)
	GardenPlaced = true,
	CoinsScooped = true,
	TrainingStarted = true,
	RingWon = true,
	PortalUsed = true,
}

----------------------------------------------------------------------
-- Collaborators (other engineers' modules: every use is guarded)
----------------------------------------------------------------------

local function loadModule(parent, name)
	local module = parent and parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	warn("[TutorialService] could not load " .. name .. ": " .. tostring(result))
	return nil
end

local TutorialSteps = loadModule(Shared, "TutorialSteps")

local DataService = nil
local PetService = nil
local MatchService = nil
local SpotService = nil
local TycoonService = nil
local PetCareService = nil
local HomeBuilder = nil -- read-only lookups of pads / stations (GetPad / GetStation)
local TycoonCatalog = nil
local PetKeys = nil -- read-only: List(profile) (does the player own a pet?)
local lobby = nil
-- Phase 3 (the pet-battle chapter): every use is guarded
local BattleService = nil
local ArenaBuilder = nil -- read-only: InArena(position)
local EventService = nil -- read-only: SecondsUntil("BossRaid")
local BattleCatalog = nil
local arenaInfo = nil

local function hasSignal(module, name)
	return type(module) == "table" and type(module[name]) == "table" and type(module[name].Connect) == "function"
end

local function hasFunction(module, name)
	return type(module) == "table" and type(module[name]) == "function"
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local steps = {} -- validated copy of TutorialSteps.Steps
local tracks = {} -- [player] = track (see newTrack)
local playerConns = {} -- [player] = { RBXScriptConnection... }
local lastEvent = {} -- [player] = os.clock() of the last accepted TutorialEvent
local lastSync = {} -- [player] = os.clock() of the last answered "Sync"
local initialized = false
local running = false

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function isLivePlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function fireClient(remoteName, player, ...)
	if not isLivePlayer(player) then
		return
	end
	local okGet, remote = pcall(Remotes.Get, remoteName)
	if not okGet or not remote then
		return
	end
	local args = { n = select("#", ...), ... }
	local ok, err = pcall(function()
		remote:FireClient(player, unpack(args, 1, args.n))
	end)
	if not ok then
		warn("[TutorialService] " .. remoteName .. " failed: " .. tostring(err))
	end
end

local function notify(player, text, kind, duration)
	fireClient("Notify", player, text, kind or "info", duration or 4)
end

local function positiveInt(n)
	if type(n) == "number" and n == n and n > 0 and n < math.huge then
		return math.floor(n)
	end
	return 0
end

local function giftTokens()
	local t = type(Config.Tutorial) == "table" and Config.Tutorial or {}
	return positiveInt(t.GiftTokens)
end

local function finishTokens()
	local t = type(Config.Tutorial) == "table" and Config.Tutorial or {}
	local reward = t.FinishReward
	if type(reward) == "table" then
		return positiveInt(reward.Tokens)
	end
	return positiveInt(reward)
end

local function formatText(text)
	text = tostring(text or "")
	text = text:gsub("{GiftTokens}", tostring(giftTokens()))
	text = text:gsub("{FinishTokens}", tostring(finishTokens()))
	if text:find("{RaidMinutes}", 1, true) then
		local minutes = 20
		local events = type(BattleCatalog) == "table" and BattleCatalog.Events
		local first = type(events) == "table" and type(events.Schedule) == "table" and events.Schedule[1]
		if type(first) == "table" and tonumber(first.EveryMinutes) then
			minutes = math.floor(tonumber(first.EveryMinutes))
		end
		text = text:gsub("{RaidMinutes}", tostring(minutes))
	end
	return text
end

local function commas(n)
	return Util.Commas(math.floor(tonumber(n) or 0))
end

local function money(n)
	return "$" .. commas(n)
end

-- Copies TutorialSteps.Steps into a clean local list (bad entries are dropped, unknown CompleteOn -> "Next").
local function buildSteps()
	steps = {}
	local source = type(TutorialSteps) == "table" and TutorialSteps.Steps
	if type(source) ~= "table" then
		return
	end
	for _, raw in ipairs(source) do
		if type(raw) == "table" and type(raw.Id) == "string" then
			local completeOn = raw.CompleteOn
			if not KNOWN_COMPLETE_ON[completeOn] then
				completeOn = "Next"
			end
			local target = nil
			if type(raw.Target) == "table" and type(raw.Target.Kind) == "string" then
				local t = raw.Target
				target = {
					Kind = t.Kind,
					Id = t.Id,
					Label = t.Label,
					Gate = t.Gate == true,
					Pad = type(t.Pad) == "string" and t.Pad or nil,
					Station = type(t.Station) == "string" and t.Station or nil,
					Path = t.Path == true,
					Food = t.Food == true,
					GardenSpot = t.GardenSpot == true,
					Coins = t.Coins == true,
					Place = type(t.Place) == "string" and t.Place or nil,
				}
			end
			local chapter = tonumber(raw.Chapter) or 1
			table.insert(steps, {
				Id = raw.Id,
				Chapter = math.max(1, math.floor(chapter)),
				ChapterEnd = raw.ChapterEnd == true,
				Title = type(raw.Title) == "string" and raw.Title or "",
				Text = type(raw.Text) == "string" and raw.Text or "",
				Target = target,
				CompleteOn = completeOn,
				Station = type(raw.Station) == "string" and raw.Station or nil,
				Gift = raw.Gift == true,
				Hint = type(raw.Hint) == "string" and raw.Hint or nil,
				Button = type(raw.Button) == "string" and raw.Button or nil,
			})
		end
	end
end

local function chapterOf(index)
	local step = steps[index]
	return step and step.Chapter or 1
end

-- true when a stored "Done" tutorial whose Step is `index` still has something to show (a later chapter)
local function resumable(index)
	return type(index) == "number" and index >= 1 and index <= #steps and chapterOf(index) > 1
end

local function inMatch(player)
	return player:GetAttribute(Config.Attr.InMatch) == true
end

local function getProfile(player)
	if not hasFunction(DataService, "GetProfile") then
		return nil
	end
	local ok, profile = pcall(DataService.GetProfile, player)
	if ok and type(profile) == "table" then
		return profile
	end
	return nil
end

local function spinsOf(player)
	local profile = getProfile(player)
	local stats = profile and profile.Stats
	if type(stats) == "table" and type(stats.Spins) == "number" then
		return stats.Spins
	end
	return 0
end

-- The equipped list as a csv (profile first, the replicated attribute as a fallback).
local function equippedCsv(player)
	local profile = getProfile(player)
	if profile and type(profile.Equipped) == "table" then
		local ids = {}
		for _, id in ipairs(profile.Equipped) do
			if type(id) == "string" then
				table.insert(ids, id)
			end
		end
		return table.concat(ids, ",")
	end
	local attr = player:GetAttribute(Config.Attr.EquippedPets)
	if type(attr) == "string" then
		return attr
	end
	return ""
end

local function getSpot(player)
	if not hasFunction(SpotService, "GetSpot") then
		return nil
	end
	local ok, spot = pcall(SpotService.GetSpot, player)
	if ok and type(spot) == "table" then
		return spot
	end
	return nil
end

local function rootOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function firstRouletteId()
	local list = Config.Roulettes
	if type(list) == "table" and type(list[1]) == "table" and type(list[1].Id) == "string" then
		return list[1].Id
	end
	return "Cloud"
end

-- the saved home (a copy) or nil
local function getHome(player)
	if not hasFunction(DataService, "GetHome") then
		return nil
	end
	local ok, home = pcall(DataService.GetHome, player)
	if ok and type(home) == "table" then
		return home
	end
	return nil
end

local function stationLevel(home, id)
	local stations = type(home) == "table" and home.Stations
	local level = type(stations) == "table" and stations[id]
	if type(level) == "number" and level == level then
		return level
	end
	return 0
end

-- true when the player owns at least one pet (PetKeys.List, else the plain Pets counts)
local function ownsPet(player)
	local profile = getProfile(player)
	if not profile then
		return false
	end
	if hasFunction(PetKeys, "List") then
		local ok, list = pcall(PetKeys.List, profile)
		if ok and type(list) == "table" then
			return #list > 0
		end
	end
	for _, n in pairs(type(profile.Pets) == "table" and profile.Pets or {}) do
		if type(n) == "number" and n > 0 then
			return true
		end
	end
	return false
end

local function stationDef(id)
	if not TycoonCatalog or type(id) ~= "string" then
		return nil
	end
	local ok, def = pcall(TycoonCatalog.Get, id)
	if ok and type(def) == "table" then
		return def
	end
	return nil
end

----------------------------------------------------------------------
-- Guide targets
----------------------------------------------------------------------

-- World position of a Phase 1 step target (nil when unknown); the client also finds the models by name.
local function lobbyPosition(player, target)
	local kind = target.Kind
	if kind == "Spot" then
		local spot = getSpot(player)
		if spot and typeof(spot.Center) == "Vector3" then
			return spot.Center
		end
	elseif kind == "Portal" then
		local portals = lobby and lobby.Portals
		local info = type(portals) == "table" and portals[target.Id or "Easy"]
		if type(info) == "table" and typeof(info.Center) == "Vector3" then
			return info.Center
		end
	elseif kind == "Roulette" or kind == "Shop" then
		local shop = lobby and lobby.Shop
		local roulettes = type(shop) == "table" and shop.Roulettes
		local info = type(roulettes) == "table" and roulettes[target.Id or firstRouletteId()]
		if type(info) == "table" and typeof(info.Center) == "Vector3" then
			return info.Center
		end
	end
	return nil
end

local function spotIndexOf(info)
	if type(info) ~= "table" then
		return nil
	end
	if type(info.Index) == "number" then
		return info.Index
	end
	local folder = info.Folder
	if typeof(folder) == "Instance" then
		local index = folder:GetAttribute("SpotIndex")
		if type(index) == "number" then
			return index
		end
	end
	return nil
end

local function spotByIndex(index)
	if type(index) ~= "number" then
		return nil
	end
	if hasFunction(SpotService, "GetSpotByIndex") then
		local ok, info = pcall(SpotService.GetSpotByIndex, index)
		if ok and type(info) == "table" then
			return info
		end
	end
	local spots = lobby and lobby.Spots
	if type(spots) == "table" and type(spots[index]) == "table" then
		return spots[index]
	end
	return nil
end

local function ownerOf(index)
	if hasFunction(SpotService, "GetOwner") then
		local ok, owner = pcall(SpotService.GetOwner, index)
		if ok then
			return owner
		end
	end
	return nil
end

local function gatePosition(info)
	if hasFunction(SpotService, "GateCFrame") then
		local ok, cf = pcall(SpotService.GateCFrame, info)
		if ok and typeof(cf) == "CFrame" then
			return cf.Position
		end
	end
	if typeof(info.GateCFrame) == "CFrame" then
		return info.GateCFrame.Position
	end
	if typeof(info.Center) == "Vector3" then
		return info.Center
	end
	return nil
end

-- The gate of the plot to claim: { Kind, Position, SpotIndex, Label } or nil. The suggestion is pinned on the track
-- while that plot stays free (the nearest free plot changes as the player walks).
local function gateTarget(player, track)
	local own = getSpot(player)
	if own then
		local position = typeof(own.Center) == "Vector3" and own.Center or gatePosition(own)
		return { Kind = "Spot", SpotIndex = spotIndexOf(own), Position = position, Label = "Your Home" }
	end
	local info = nil
	if track.GateIndex and ownerOf(track.GateIndex) == nil then
		info = spotByIndex(track.GateIndex)
	end
	if not info and hasFunction(SpotService, "SuggestSpot") then
		local ok, suggestion = pcall(SpotService.SuggestSpot, player)
		if ok and type(suggestion) == "table" then
			info = suggestion
		end
	end
	if not info then
		track.GateIndex = nil
		return nil
	end
	track.GateIndex = spotIndexOf(info)
	local position = gatePosition(info)
	if not position then
		return nil
	end
	return { Kind = "Spot", SpotIndex = track.GateIndex, Position = position, Label = "Free home" }
end

-- A model's pivot position, or nil.
local function pivotOf(model)
	if typeof(model) ~= "Instance" then
		return nil
	end
	local ok, cf = pcall(function()
		if model:IsA("Model") then
			return model:GetPivot()
		elseif model:IsA("BasePart") then
			return model.CFrame
		end
		return nil
	end)
	if ok and typeof(cf) == "CFrame" then
		return cf.Position
	end
	return nil
end

local function homeBuilderCall(fnName, spot, id)
	if not hasFunction(HomeBuilder, fnName) then
		return nil
	end
	local ok, result = pcall(HomeBuilder[fnName], spot, id)
	if ok and typeof(result) == "Instance" then
		return result
	end
	return nil
end

-- the buy pad of `id` on the claimed plot (HomeBuilder's model, else the catalog slot)
local function padPosition(spot, id)
	local at = pivotOf(homeBuilderCall("GetPad", spot, id))
	if at then
		return at
	end
	local def = stationDef(id)
	if def and type(def.Slot) == "table" and typeof(def.Slot.Pad) == "CFrame" and typeof(spot.PlotCFrame) == "CFrame" then
		return (spot.PlotCFrame * def.Slot.Pad).Position
	end
	return nil
end

-- the world position of a marker inside a model: a BasePart's Position or an Attachment's WorldPosition
local function markerPosition(model, name)
	local mark = typeof(model) == "Instance" and model:FindFirstChild(name, true) or nil
	if mark and mark:IsA("BasePart") then
		return mark.Position
	elseif mark and mark:IsA("Attachment") then
		return mark.WorldPosition
	end
	return nil
end

-- the marker of a built station the arrow points at (HomeBuilder's Phase 4 art): the Food Machine's Hopper, the first
-- Training Place mat
local STATION_MARKERS = { Kitchen = "Hopper", Gym = "Spot1" }

-- where a built station's arrow stands: its marker (STATION_MARKERS), else just in front of the station's footprint
local function stationPosition(spot, id)
	local model = homeBuilderCall("GetStation", spot, id)
	local marked = STATION_MARKERS[id] and markerPosition(model, STATION_MARKERS[id]) or nil
	if marked then
		return marked
	end
	local def = stationDef(id)
	if def and type(def.Slot) == "table" and typeof(def.Slot.CFrame) == "CFrame" and typeof(spot.PlotCFrame) == "CFrame" then
		local depth = typeof(def.Slot.Footprint) == "Vector3" and def.Slot.Footprint.Z or 8
		return (spot.PlotCFrame * def.Slot.CFrame * CFrame.new(0, 0, -(depth / 2 + STATION_FRONT_GAP))).Position
	end
	return pivotOf(model)
end

----------------------------------------------------------------------
-- Phase 4: the Pet Garden and its rainbow coins (Home.Garden, TycoonCatalog.GardenSlots, TycoonService.Piles)
----------------------------------------------------------------------
local Garden = {}

-- how many garden places are open (0 while the Pet Garden is not built)
function Garden.open(home)
	if not hasFunction(TycoonCatalog, "GardenSlots") or type(home) ~= "table" then
		return 0
	end
	local ok, n = pcall(TycoonCatalog.GardenSlots, home)
	if ok and type(n) == "number" and n == n then
		return math.max(0, math.floor(n))
	end
	return 0
end

-- the key in garden place `slot`, or nil
function Garden.keyAt(home, slot)
	local garden = type(home) == "table" and home.Garden or nil
	local key = type(garden) == "table" and (garden[slot] or garden[tostring(slot)]) or nil
	if type(key) == "string" and key ~= "" then
		return key
	end
	return nil
end

-- true when a pet sits in an open garden place (the "garden" step)
function Garden.placed(player)
	local home = getHome(player)
	if not home or stationLevel(home, "Garden") < 1 then
		return false
	end
	for slot = 1, Garden.open(home) do
		if Garden.keyAt(home, slot) then
			return true
		end
	end
	return false
end

-- the world position of garden place `slot` (the lawn's Spot<slot> attachment, else the catalog layout)
function Garden.placePosition(spot, slot)
	local model = homeBuilderCall("GetStation", spot, "Garden")
	local at = markerPosition(model, "Spot" .. tostring(slot))
	if at then
		return at
	end
	local def = stationDef("Garden")
	local spots = def and type(def.Slot) == "table" and def.Slot.Spots or nil
	local local3 = type(spots) == "table" and spots[slot] or nil
	if typeof(local3) == "Vector3" and typeof(def.Slot.CFrame) == "CFrame" and typeof(spot.PlotCFrame) == "CFrame" then
		return (spot.PlotCFrame * def.Slot.CFrame * CFrame.new(local3)).Position
	end
	return pivotOf(model)
end

-- the pile with the most Cash in it ({ Coins, Value, Pos } from TycoonService.Piles; "W" = the Welcome-back pile), or nil
function Garden.fullestPile(player)
	if not hasFunction(TycoonService, "Piles") then
		return nil
	end
	local ok, piles = pcall(TycoonService.Piles, player)
	if not ok or type(piles) ~= "table" then
		return nil
	end
	local best, bestValue = nil, -1
	for slot, pile in pairs(piles) do
		if type(pile) == "table" and typeof(pile.Pos) == "Vector3" then
			local value = tonumber(pile.Value) or 0
			local real = (slot == "W" and value >= 1) or (slot ~= "W" and (tonumber(pile.Coins) or 0) >= 1)
			if real and value > bestValue then
				best, bestValue = pile, value
			end
		end
	end
	return best
end

-- the "garden" step: no pet -> the Shop; no Pet Garden -> its free pad; else the first empty open place (or Pets)
function Garden.target(player, spot, home, index, step)
	if not ownsPet(player) then
		local shop = { Kind = "Shop", Id = firstRouletteId(), Label = "Cloud Shop" }
		local ok, position = pcall(lobbyPosition, player, shop)
		shop.Position = ok and typeof(position) == "Vector3" and position or nil
		return shop, "Spin a roulette for a pet"
	end
	if stationLevel(home, "Garden") < 1 then
		return { Kind = "Spot", SpotIndex = index, Position = padPosition(spot, "Garden"), Label = "Pet Garden pad" },
			"Build your free Pet Garden (press E on its pad)"
	end
	for slot = 1, Garden.open(home) do
		if not Garden.keyAt(home, slot) then
			local at = Garden.placePosition(spot, slot)
			if at then
				return { Kind = "Spot", SpotIndex = index, Position = at, Label = step.Target.Label or "Pet Garden" },
					"Press E on a garden spot to put a pet in it"
			end
		end
	end
	return { Kind = "Menu", Id = "Pets", Label = "Pets" }, "Open Pets and press Garden"
end

-- the "coins" step: the fullest pile, else the Garden while its pets make the first coins
function Garden.coinsTarget(player, spot, index, step)
	local pile = Garden.fullestPile(player)
	if pile then
		return { Kind = "Spot", SpotIndex = index, Position = pile.Pos, Label = step.Target.Label or "Your coins" },
			"Walk over your rainbow coins"
	end
	return { Kind = "Spot", SpotIndex = index, Position = stationPosition(spot, "Garden"), Label = "Pet Garden" },
		"Your garden pets are making coins: wait a moment"
end

-- true when the player trains (or has trained) a pet: any Job or any rank in PetGrowth
local function hasTrained(player)
	if not hasFunction(DataService, "GetGrowthMap") then
		return false
	end
	local ok, map = pcall(DataService.GetGrowthMap, player)
	if not ok or type(map) ~= "table" then
		return false
	end
	for _, entry in pairs(map) do
		if type(entry) == "table" then
			if type(entry.Job) == "table" then
				return true
			end
			for _, stat in ipairs({ "Speed", "Physique", "Ability", "Defense" }) do
				if (tonumber(entry[stat]) or 0) > 0 then
					return true
				end
			end
		end
	end
	return false
end

-- true when the stored Champion Ring record has a won round
local function ringBest(player)
	if not hasFunction(DataService, "GetRing") then
		return 0
	end
	local ok, ring = pcall(DataService.GetRing, player)
	return ok and type(ring) == "table" and (tonumber(ring.Best) or 0) or 0
end

local function padsById(home)
	local byId = {}
	if not TycoonCatalog or not hasFunction(TycoonCatalog, "AvailablePads") then
		return byId
	end
	local ok, pads = pcall(TycoonCatalog.AvailablePads, home)
	if ok and type(pads) == "table" then
		for _, pad in ipairs(pads) do
			if type(pad) == "table" and type(pad.StationId) == "string" then
				byId[pad.StationId] = pad
			end
		end
	end
	return byId
end

-- The pad to buy next on the way to station `goal`: its own pad when it can be bought, else (depth first, in
-- catalog order) a prerequisite's. nil when nothing on the way can be bought right now.
local function padToward(home, byId, goal, depth, seen)
	if depth > 8 or seen[goal] then
		return nil
	end
	seen[goal] = true
	local pad = byId[goal]
	if pad and not pad.Locked then
		return pad
	end
	local def = stationDef(goal)
	if not def or type(def.Requires) ~= "table" then
		return nil
	end
	local keys = {}
	for key in pairs(def.Requires) do
		if stationDef(key) and key ~= "Prestige" then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys, function(a, b)
		local da, db = stationDef(a), stationDef(b)
		return (da.Order or 0) < (db.Order or 0)
	end)
	for _, key in ipairs(keys) do
		if stationLevel(home, key) < (tonumber(def.Requires[key]) or 0) then
			local found = padToward(home, byId, key, depth + 1, seen)
			if found then
				return found
			end
		end
	end
	return nil
end

local function cheapestPad(byId)
	local best = nil
	for _, pad in pairs(byId) do
		if not pad.Locked and not pad.Prestige and type(pad.Price) == "number" then
			if not best or pad.Price < best.Price or (pad.Price == best.Price and pad.StationId < best.StationId) then
				best = pad
			end
		end
	end
	return best
end

local function padText(pad)
	local def = stationDef(pad.StationId)
	local name = (def and def.Name) or pad.Name or pad.StationId
	local price = tonumber(pad.Price) or 0
	local cost = price > 0 and (" for " .. money(price)) or " (free)"
	if (tonumber(pad.Level) or 0) > 0 then
		return name .. " Lv " .. tostring(pad.NextLevel) .. cost
	end
	return name .. cost
end

-- target, hint for a home step (Kind "Spot" targets with a Pad / Station / Gate / Food field)
local function homeTarget(player, track, step)
	local t = step.Target
	if t.Gate then
		local target = gateTarget(player, track)
		if target then
			track.NoFree = false
			if target.Label == "Your Home" then
				return target, "Your home is claimed!"
			end
			return target, step.Hint
		end
		track.NoFree = true
		return nil, "Every home is taken: wait for a free gate"
	end
	local spot = getSpot(player)
	if not spot then
		-- every other home step happens on the player's own plot: claim one first
		return gateTarget(player, track), "Claim a home first: press E at a free gate"
	end
	local home = getHome(player) or {}
	local index = spotIndexOf(spot)
	if t.GardenSpot then
		return Garden.target(player, spot, home, index, step)
	end
	if t.Coins then
		return Garden.coinsTarget(player, spot, index, step)
	end
	if t.Food then
		local machine = t.Station or "Kitchen"
		if stationLevel(home, machine) >= 1 then
			return { Kind = "Spot", SpotIndex = index, Position = stationPosition(spot, machine), Label = t.Label or "Food Machine" },
				"Press E at the Food Machine, then Feed"
		end
		local byId = padsById(home)
		local pad = padToward(home, byId, machine, 0, {}) or cheapestPad(byId)
		if pad then
			return { Kind = "Spot", SpotIndex = index, Position = padPosition(spot, pad.StationId), Label = padText(pad) },
				"Build the Food Machine first"
		end
		return nil, step.Hint
	end
	local stationId = t.Station
	if stationId and stationLevel(home, stationId) >= 1 then
		local hint = step.Hint
		if stationId == "Gym" then
			hint = "Press E at the Training Place: pick a pet and a skill"
		end
		return { Kind = "Spot", SpotIndex = index, Position = stationPosition(spot, stationId), Label = t.Label or stationId }, hint
	end
	local goal = t.Pad
	if not goal then
		return nil, step.Hint
	end
	local byId = padsById(home)
	local pad = byId[goal]
	if t.Path then
		local next = padToward(home, byId, goal, 0, {})
		if not next and not (pad and not pad.Locked) then
			next = cheapestPad(byId)
		end
		if next and next.StationId ~= goal then
			return { Kind = "Spot", SpotIndex = index, Position = padPosition(spot, next.StationId), Label = "Next: " .. padText(next) },
				"Next: " .. padText(next)
		end
	end
	local hint = step.Hint
	if pad and not pad.Locked and t.Path then
		hint = "Build " .. padText(pad)
	elseif pad and pad.Locked then
		hint = tostring(pad.Locked)
	end
	return { Kind = "Spot", SpotIndex = index, Position = padPosition(spot, goal), Label = t.Label or goal }, hint
end

----------------------------------------------------------------------
-- Phase 3: the Battle Arena (ArenaInfo from ArenaBuilder.Build, BattleService, EventService)
----------------------------------------------------------------------
local function positionOfInfo(value)
	if typeof(value) == "CFrame" then
		return value.Position
	elseif typeof(value) == "Vector3" then
		return value
	elseif typeof(value) == "Instance" then
		if value:IsA("BasePart") then
			return value.Position
		elseif value:IsA("Model") then
			local ok, cf = pcall(function()
				return value:GetPivot()
			end)
			if ok and cf then
				return cf.Position
			end
		end
	elseif type(value) == "table" then
		return positionOfInfo(value.CFrame)
	end
	return nil
end

-- the ArenaInfo (from Init, else ArenaBuilder.GetInfo once the arena is built)
local function getArenaInfo()
	if type(arenaInfo) == "table" then
		return arenaInfo
	end
	if hasFunction(ArenaBuilder, "GetInfo") then
		local ok, info = pcall(ArenaBuilder.GetInfo)
		if ok and type(info) == "table" then
			arenaInfo = info
			return info
		end
	end
	return nil
end

local function arenaKnown()
	return getArenaInfo() ~= nil or hasFunction(ArenaBuilder, "InArena")
end

-- true while the player's character stands in the Battle Arena
local function inArena(player)
	local root = rootOf(player)
	if not root then
		return false
	end
	if hasFunction(ArenaBuilder, "InArena") then
		local ok, inside = pcall(ArenaBuilder.InArena, root.Position)
		if ok and type(inside) == "boolean" then
			return inside
		end
	end
	local info = getArenaInfo()
	local center = info and positionOfInfo(info.Center)
	if not center then
		return false
	end
	local offset = root.Position - center
	local radius = tonumber(info.Radius) or ARENA_RADIUS
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= 80
end

local function inBattle(player)
	local id = player:GetAttribute(ATTR_IN_BATTLE)
	return id ~= nil and id ~= false and id ~= ""
end

local function activeTeamSize(player)
	if not hasFunction(DataService, "ActiveTeamKeys") then
		return 0
	end
	local ok, keys = pcall(DataService.ActiveTeamKeys, player)
	if ok and type(keys) == "table" then
		return #keys
	end
	return 0
end

-- how many pets the player could put in a team (owned, not busy in the Garden / Gym); nil when unknown
local function fieldablePets(player)
	if not hasFunction(DataService, "FieldableKeys") then
		return nil
	end
	local ok, keys = pcall(DataService.FieldableKeys, player)
	if ok and type(keys) == "table" then
		return #keys
	end
	return nil
end

-- the "team" step: the team holds the player's pets, up to the three slots the text promises (one pet is enough
-- for a player who owns one)
local function teamFilled(player)
	local size = activeTeamSize(player)
	if size <= 0 then
		return false
	end
	local owned = fieldablePets(player) or size
	return size >= math.min(3, owned)
end

local function battleRecord(player)
	if not hasFunction(DataService, "GetBattle") then
		return nil
	end
	local ok, record = pcall(DataService.GetBattle, player)
	if ok and type(record) == "table" then
		return record
	end
	return nil
end

local function trialOneCleared(player)
	local record = battleRecord(player)
	if not record then
		return false
	end
	if type(record.TrialCleared) == "table" and (record.TrialCleared[1] == true or record.TrialCleared["1"] == true) then
		return true
	end
	return (tonumber(record.TrialBest) or 0) >= 1
end

local function raidStatus()
	if not hasFunction(BattleService, "GetRaidStatus") then
		return nil
	end
	local ok, status = pcall(BattleService.GetRaidStatus)
	if ok and type(status) == "table" then
		return status
	end
	return nil
end

-- the raid step's hint: a running raid, or the minutes to the next one (minute steps: the state is re-sent rarely)
local function raidHint(step)
	local status = raidStatus()
	if status then
		return "A Boss Raid is on! Go to the colosseum"
	end
	if hasFunction(EventService, "SecondsUntil") then
		local ok, seconds = pcall(EventService.SecondsUntil, "BossRaid")
		if ok and type(seconds) == "number" and seconds >= 0 and seconds < math.huge then
			local minutes = math.max(1, math.ceil(seconds / 60))
			if minutes <= 1 then
				return "Next Boss Raid in under a minute!"
			end
			return "Next Boss Raid in " .. minutes .. " min"
		end
	end
	return step.Hint
end

-- { Kind = "Spot", Position, Label } for an Arena target (the client draws world arrows for Spot targets), or nil
local function arenaTarget(player, target)
	if inBattle(player) then
		return nil
	end
	local info = getArenaInfo()
	if not info then
		return nil
	end
	local position = nil
	if target.Place == "Trials" then
		position = positionOfInfo(info.TrialPortal)
	elseif target.Place == "Floor" then
		position = positionOfInfo(info.Floor) or positionOfInfo(info.Center)
	elseif target.Place == "Ring" then
		position = positionOfInfo(info.RingPortal) or positionOfInfo(info.RingSite) or positionOfInfo(info.TrialPortal)
	else
		position = positionOfInfo(info.Spawn) or positionOfInfo(info.Center)
	end
	if typeof(position) ~= "Vector3" then
		return nil
	end
	return { Kind = "Spot", Position = position, Label = target.Label or "Battle Arena", Arena = target.Place or "Gate" }
end

-- The target (sent to the client) and the hint of the current step.
local function resolveStep(player, track, step)
	local target = step.Target
	local hint = step.Hint
	if step.CompleteOn == "RaidSeen" then
		hint = raidHint(step)
	end
	if not target then
		return nil, hint
	end
	if target.Kind == "Arena" then
		if target.Place == "Ring" and TycoonService ~= nil and getSpot(player) == nil and not inBattle(player) then
			-- the Champion Ring needs a claimed home: the gate of a free one first
			local okGate, gate = pcall(gateTarget, player, track)
			return okGate and gate or nil, "Claim your home first: press E at a free gate"
		end
		local ok, out = pcall(arenaTarget, player, target)
		return ok and out or nil, hint
	end
	if target.Kind == "Spot" and (target.Gate or target.Pad or target.Station or target.Food or target.GardenSpot or target.Coins) then
		local ok, out, hint = pcall(homeTarget, player, track, step)
		if not ok then
			return nil, step.Hint
		end
		if out and out.Kind == "Spot" and typeof(out.Position) ~= "Vector3" then
			out.Position = nil
		end
		return out, hint
	end
	local out = { Kind = target.Kind, Id = target.Id, Label = target.Label }
	if out.Kind == "Shop" and out.Id == nil then
		out.Id = firstRouletteId()
	end
	if out.Kind == "Spot" then
		local index = player:GetAttribute(Config.Attr.SpotIndex)
		if type(index) == "number" then
			out.SpotIndex = index
		end
	end
	local ok, position = pcall(lobbyPosition, player, out)
	if ok and typeof(position) == "Vector3" then
		out.Position = position
	end
	return out, step.Hint
end

local function targetSignature(target, hint)
	if not target then
		return "none|" .. tostring(hint)
	end
	local p = typeof(target.Position) == "Vector3" and target.Position or nil
	return table.concat({
		tostring(target.Kind),
		tostring(target.Id),
		tostring(target.SpotIndex),
		tostring(target.Label),
		tostring(target.Arena),
		p and string.format("%.0f,%.0f,%.0f", p.X, p.Y, p.Z) or "-",
		tostring(hint),
	}, "|")
end

local function currentStep(track)
	if not track or track.Done then
		return nil
	end
	return steps[track.Step]
end

----------------------------------------------------------------------
-- State payload + persistence
----------------------------------------------------------------------

local function buildPayload(player, track)
	local total = #steps
	local index = math.max(1, math.min(track.Step, total))
	local step = steps[index]
	local target, hint = nil, step.Hint
	if not track.Done then
		target, hint = resolveStep(player, track, step)
		track.TargetSig = targetSignature(target, hint)
	end
	return {
		Step = index,
		Total = total,
		Id = step.Id,
		Title = step.Title,
		Text = formatText(step.Text),
		Target = target,
		CompleteOn = step.CompleteOn,
		Hint = hint,
		Button = step.Button,
		Gift = step.Gift,
		Chapter = step.Chapter,
		Done = track.Done == true,
		Completed = track.Completed == true,
		Skipped = track.Skipped == true,
		Reward = track.Reward or 0,
	}
end

local function sendState(player, track)
	if not isLivePlayer(player) or not track or #steps == 0 then
		return
	end
	fireClient("TutorialState", player, buildPayload(player, track))
end

-- Writes the progress to the profile. Returns true when stored.
local function persist(player, track)
	if not hasFunction(DataService, "SetTutorial") then
		return false
	end
	local ok, stored = pcall(DataService.SetTutorial, player, {
		Step = track.Step,
		Done = track.Done == true or track.BaseDone == true,
		Gifted = track.Gifted == true,
	})
	return ok and stored == true
end

local function addTokens(player, amount)
	if amount <= 0 or not hasFunction(DataService, "AddTokens") then
		return false
	end
	local ok, err = pcall(DataService.AddTokens, player, amount)
	if not ok then
		warn("[TutorialService] AddTokens failed: " .. tostring(err))
	end
	return ok
end

local function addCash(player, amount)
	if amount <= 0 or not hasFunction(DataService, "AddCash") then
		return false
	end
	local ok, result = pcall(DataService.AddCash, player, amount)
	if not ok then
		warn("[TutorialService] AddCash failed: " .. tostring(result))
		return false
	end
	return result ~= false
end

-- Pays the reward of a finished chapter (the progress is already stored). Returns the tokens paid (for the payload).
local function payChapter(player, track, chapter)
	if track.Replay then
		return 0
	end
	if chapter <= 1 then
		local amount = finishTokens()
		if amount > 0 and addTokens(player, amount) then
			notify(player, "Basics complete! +" .. amount .. " " .. TOKEN_GLYPH .. " from Nimbus", "good", 6)
			return amount
		end
		return 0
	end
	if chapter >= 4 then
		if RING_FINISH_TOKENS > 0 and addTokens(player, RING_FINISH_TOKENS) then
			notify(player, "Pets tutorial complete! +" .. commas(RING_FINISH_TOKENS) .. " Tokens", "good", 6)
			return RING_FINISH_TOKENS
		end
		return 0
	end
	if chapter >= 3 then
		if ARENA_FINISH_TOKENS > 0 and addTokens(player, ARENA_FINISH_TOKENS) then
			notify(player, "Battle tutorial complete! +" .. commas(ARENA_FINISH_TOKENS) .. " " .. TOKEN_GLYPH .. " from Nimbus", "good", 6)
			return ARENA_FINISH_TOKENS
		end
		return 0
	end
	if HOME_FINISH_CASH > 0 and addCash(player, HOME_FINISH_CASH) then
		notify(player, "Home tutorial complete! +" .. money(HOME_FINISH_CASH) .. " Cash from Nimbus", "good", 6)
	end
	return 0
end

----------------------------------------------------------------------
-- Step flow
----------------------------------------------------------------------

-- Called whenever a player arrives on a step (also on load): baselines + the one-time gift.
-- Returns true when it already stored the progress (the gift step does).
local function enterStep(player, track)
	local step = currentStep(track)
	if not step then
		return false
	end
	track.SpinsBase = spinsOf(player)
	track.LastEquipped = equippedCsv(player)
	track.NoSpotTime = 0
	track.NoFreeTime = 0
	track.TargetSig = nil
	track.TrialWon = false
	track.RaidSeen = false
	track.CoinsScooped = false
	track.TrainingStarted = false
	track.RingWon = false
	track.PortalUsed = false
	if step.Gift and not track.Gifted then
		local amount = giftTokens()
		track.Gifted = true
		-- Gifted is stored BEFORE the tokens are paid: a crash in between can never pay twice
		if persist(player, track) then
			if amount > 0 and addTokens(player, amount) then
				notify(player, "Nimbus gave you " .. amount .. " " .. TOKEN_GLYPH .. " Cloud Tokens!", "token", 5)
			end
			return true
		end
		track.Gifted = false -- not stored: try again on the next load
	end
	return false
end

local function finish(player, track, skipped)
	if track.Done then
		return
	end
	local chapter = chapterOf(math.min(track.Step, #steps))
	track.Done = true
	track.BaseDone = true
	if skipped then
		track.Skipped = true
		track.Step = SKIPPED_STEP -- no later chapter either
	else
		track.Completed = true
		track.Step = #steps + 1 -- one past the end: a chapter appended later starts from here
	end
	local stored = persist(player, track)
	if not skipped and stored then
		track.Reward = payChapter(player, track, chapter)
	elseif skipped then
		notify(player, "Tutorial skipped. Nimbus is cheering for you!", "info", 4)
	end
	sendState(player, track)
	TutorialService.Finished:Fire(player, skipped == true)
end

-- Completes the current step and moves on (the last step finishes the tutorial).
local function advance(player, track)
	local step = currentStep(track)
	if not step then
		return
	end
	local index = track.Step
	TutorialService.StepCompleted:Fire(player, step.Id, index)
	if index >= #steps then
		finish(player, track, false)
		return
	end
	local chapterDone = step.ChapterEnd == true or chapterOf(index + 1) ~= step.Chapter
	track.Step = index + 1
	if chapterDone then
		track.BaseDone = true -- the stored Done flips with the first chapter and sticks
	end
	local stored = enterStep(player, track)
	if not stored then
		stored = persist(player, track)
	end
	if chapterDone and step.ChapterEnd == true and stored then
		payChapter(player, track, step.Chapter)
	end
	sendState(player, track)
end

local function homeReady()
	return TycoonService ~= nil and TycoonCatalog ~= nil and hasFunction(DataService, "GetHome")
end

-- True when a step cannot be done in this server (a service is missing) and should be passed.
local function impossible(player, track, step)
	local kind = step.CompleteOn
	if kind == "Rolled" or kind == "Equipped" then
		return PetService == nil
	elseif kind == "NearSpot" then
		return not hasFunction(SpotService, "GetSpot") or (track.NoSpotTime or 0) >= NO_SPOT_GRACE
	elseif kind == "MatchStarted" or kind == "MatchEnded" then
		return MatchService == nil
	elseif kind == "Claimed" then
		return TycoonService == nil or not hasFunction(SpotService, "GetSpot") or (track.NoFreeTime or 0) >= NO_FREE_GRACE
	elseif kind == "Built" then
		return not homeReady() or stationDef(step.Station) == nil
	elseif kind == "Collected" then
		return true -- retired with the Collector (Phase 4): nothing can complete it any more
	elseif kind == "GardenPlaced" or kind == "CoinsScooped" then
		return not homeReady() or not hasFunction(TycoonService, "GardenSet")
	elseif kind == "TrainingStarted" then
		return not hasFunction(PetCareService, "Train")
	elseif kind == "RingWon" then
		return not hasFunction(BattleService, "StartRing")
	elseif kind == "PortalUsed" then
		return not hasFunction(TycoonService, "OpenHomePortal")
	elseif kind == "Fed" then
		return not hasSignal(PetCareService, "Fed")
	elseif kind == "ArenaReached" then
		return not arenaKnown()
	elseif kind == "TeamSet" then
		return not hasFunction(DataService, "ActiveTeamKeys")
	elseif kind == "TrialWon" then
		return BattleService == nil or not (hasSignal(BattleService, "BattleEnded") or hasFunction(DataService, "GetBattle"))
	elseif kind == "RaidSeen" then
		return BattleService == nil or not (hasFunction(BattleService, "GetRaidStatus") or hasSignal(BattleService, "BattleEnded"))
	end
	return false
end

local function nearSpot(player)
	local spot = getSpot(player)
	local root = rootOf(player)
	if not spot or not root or typeof(spot.Center) ~= "Vector3" then
		return false
	end
	local offset = root.Position - spot.Center
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return flat <= NEAR_SPOT_RADIUS and math.abs(offset.Y) <= NEAR_SPOT_HEIGHT
end

-- Level-based completion checks (state the server can see right now).
local function satisfied(player, track, step)
	local kind = step.CompleteOn
	if kind == "MatchStarted" then
		return inMatch(player)
	elseif kind == "MatchEnded" then
		return not inMatch(player)
	elseif kind == "NearSpot" then
		return not inMatch(player) and nearSpot(player)
	elseif kind == "Rolled" then
		return spinsOf(player) > (track.SpinsBase or math.huge)
	elseif kind == "Claimed" then
		return getSpot(player) ~= nil
	elseif kind == "Built" then
		return step.Station ~= nil and stationLevel(getHome(player), step.Station) >= 1
	elseif kind == "GardenPlaced" then
		return Garden.placed(player)
	elseif kind == "CoinsScooped" then
		-- a mid-chapter veteran whose home already has the Food Machine knows the coins
		return track.CoinsScooped == true or stationLevel(getHome(player), "Kitchen") >= 1
	elseif kind == "TrainingStarted" then
		return track.TrainingStarted == true or hasTrained(player)
	elseif kind == "RingWon" then
		return track.RingWon == true or ringBest(player) >= 1
	elseif kind == "PortalUsed" then
		return track.PortalUsed == true
	elseif kind == "ArenaReached" then
		return not inMatch(player) and inArena(player)
	elseif kind == "TeamSet" then
		return teamFilled(player)
	elseif kind == "TrialWon" then
		return track.TrialWon == true or trialOneCleared(player)
	elseif kind == "RaidSeen" then
		if track.RaidSeen == true then
			return true
		end
		local record = battleRecord(player)
		if record and (tonumber(record.Raids) or 0) >= 1 then
			return true
		end
		return raidStatus() ~= nil and inArena(player)
	end
	return false
end

-- Advances through every step that is already complete (bounded by the step count).
local function settle(player, track)
	for _ = 1, #steps + 1 do
		local step = currentStep(track)
		if not step or not isLivePlayer(player) then
			return
		end
		if not (satisfied(player, track, step) or impossible(player, track, step)) then
			return
		end
		advance(player, track)
	end
end

-- Equip changes: complete "Equipped" when the list changed to a non-empty one.
local function onEquipChanged(player)
	local track = tracks[player]
	if not track or track.Done then
		return
	end
	local csv = equippedCsv(player)
	if csv == track.LastEquipped then
		return
	end
	track.LastEquipped = csv
	local step = currentStep(track)
	if step and step.CompleteOn == "Equipped" and csv ~= "" then
		advance(player, track)
		settle(player, track)
	end
end

-- Re-sends the state when a home step's target or hint changed (a pad got built, food arrived, a plot was taken).
local function refreshTarget(player, track)
	local step = currentStep(track)
	local t = step and step.Target
	local dynamic = step ~= nil and (step.CompleteOn == "RaidSeen" or (t ~= nil and t.Kind == "Arena"))
	if not dynamic and (not t or not (t.Gate or t.Pad or t.Station or t.Food or t.GardenSpot or t.Coins)) then
		return
	end
	local ok, target, hint = pcall(resolveStep, player, track, step)
	if not ok then
		return
	end
	if targetSignature(target, hint) ~= track.TargetSig then
		sendState(player, track)
	end
end

----------------------------------------------------------------------
-- Players
----------------------------------------------------------------------

local function newTrack(stored)
	local step = math.max(1, math.floor(tonumber(stored.Step) or 1))
	local track = {
		Step = step,
		Done = false,
		BaseDone = stored.Done == true,
		Gifted = stored.Gifted == true,
		Completed = false,
		Skipped = false,
		Reward = 0,
		NoSpotTime = 0,
		NoFreeTime = 0,
	}
	if not track.BaseDone then
		if track.Step > #steps then
			track.Step = #steps -- steps were removed since: land on the last one
		end
	elseif not resumable(track.Step) then
		track.Done = true -- finished (or skipped): nothing left to show
	end
	return track
end

-- Creates the player's track from the stored progress. Returns true once loaded.
local function loadPlayer(player)
	if tracks[player] then
		return true
	end
	if #steps == 0 or not isLivePlayer(player) or not hasFunction(DataService, "GetTutorial") then
		return false
	end
	local ok, stored = pcall(DataService.GetTutorial, player)
	if not ok or type(stored) ~= "table" then
		return false -- profile not loaded yet
	end
	local track = newTrack(stored)
	tracks[player] = track
	if not track.Done then
		enterStep(player, track)
	end
	sendState(player, track)
	settle(player, track)
	return true
end

-- Drops the running tutorial and reads it again from the profile (used by the developer tools after they rewind
-- the stored tutorial). opts.Replay = true marks a replay of a tutorial that was already finished once: its chapter
-- rewards are not paid again. Returns true when the player's tutorial is running again.
local function reloadPlayer(player, opts)
	if not isLivePlayer(player) then
		return false
	end
	tracks[player] = nil
	local ok = loadPlayer(player)
	local track = tracks[player]
	if track and type(opts) == "table" and opts.Replay == true then
		track.Replay = true
	end
	return ok == true
end

-- The stored profile changed under us (recovered load / another server): merge forward, never back.
local function onProfileRebased(player)
	local track = tracks[player]
	if not track then
		loadPlayer(player)
		return
	end
	if not hasFunction(DataService, "GetTutorial") then
		return
	end
	local ok, stored = pcall(DataService.GetTutorial, player)
	if not ok or type(stored) ~= "table" then
		return
	end
	local fresh = newTrack(stored)
	local changed = false
	if fresh.Gifted and not track.Gifted then
		track.Gifted = true
	end
	if fresh.BaseDone and not track.BaseDone then
		track.BaseDone = true
	end
	if not track.Done then
		if fresh.Done then
			-- finished or skipped elsewhere: it ends here too
			track.Done = true
			track.Step = fresh.Step
			changed = true
		elseif fresh.Step > track.Step then
			track.Step = math.min(fresh.Step, #steps)
			enterStep(player, track)
			changed = true
		end
	end
	if changed then
		sendState(player, track)
		settle(player, track)
	end
end

local function disconnectPlayer(player)
	local conns = playerConns[player]
	if conns then
		for _, conn in ipairs(conns) do
			pcall(function()
				conn:Disconnect()
			end)
		end
	end
	playerConns[player] = nil
end

local function onPlayerAdded(player)
	if playerConns[player] then
		return
	end
	local conns = {}
	playerConns[player] = conns
	table.insert(conns, player:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
		local track = tracks[player]
		if track then
			settle(player, track)
		end
	end))
	table.insert(conns, player:GetAttributeChangedSignal(Config.Attr.EquippedPets):Connect(function()
		onEquipChanged(player)
	end))
	-- a claimed plot: complete "Claimed" at once and point the home steps at the new plot
	table.insert(conns, player:GetAttributeChangedSignal(Config.Attr.SpotIndex):Connect(function()
		local track = tracks[player]
		local step = currentStep(track)
		if step then
			track.NoSpotTime = 0
			settle(player, track)
			track = tracks[player]
			if track and currentStep(track) then
				refreshTarget(player, track)
			end
		end
	end))
	task.spawn(loadPlayer, player)
end

local function onPlayerRemoving(player)
	disconnectPlayer(player)
	tracks[player] = nil
	lastEvent[player] = nil
	lastSync[player] = nil
end

----------------------------------------------------------------------
-- Client events
----------------------------------------------------------------------

function TutorialService.HandleEvent(player, eventName)
	if not isLivePlayer(player) then
		return false, "Player unavailable"
	end
	if type(eventName) ~= "string" or #eventName > MAX_EVENT_LENGTH then
		return false, "Bad event"
	end
	local track = tracks[player]
	if not track then
		if not loadPlayer(player) then
			return false, "Not loaded"
		end
		track = tracks[player]
	end
	if eventName == "Sync" then
		sendState(player, track)
		return true
	end
	if track.Done then
		return false, "Tutorial already finished"
	end
	if eventName == "Skip" then
		finish(player, track, true)
		return true
	end
	local completes = EVENT_COMPLETES[eventName]
	if not completes then
		return false, "Unknown event"
	end
	local step = currentStep(track)
	if not step or step.CompleteOn ~= completes then
		return false, "Not the current step"
	end
	if completes == "Equipped" and equippedCsv(player) == "" then
		return false, "Equip a pet first"
	end
	advance(player, track)
	settle(player, track)
	return true
end

local function onTutorialEvent(player, eventName)
	if type(eventName) ~= "string" or #eventName > MAX_EVENT_LENGTH then
		return
	end
	local now = os.clock()
	if eventName == "Sync" then
		local last = lastSync[player]
		if last and now - last < SYNC_COOLDOWN then
			return
		end
		lastSync[player] = now
	else
		local last = lastEvent[player]
		if last and now - last < EVENT_COOLDOWN then
			return
		end
		lastEvent[player] = now
	end
	local ok, err = pcall(TutorialService.HandleEvent, player, eventName)
	if not ok then
		warn("[TutorialService] event " .. eventName .. " failed: " .. tostring(err))
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function TutorialService.Reload(player, opts)
	return reloadPlayer(player, opts)
end

function TutorialService.GetState(player)
	local track = player and tracks[player]
	if not track or #steps == 0 then
		return nil
	end
	return buildPayload(player, track)
end

-- Stops the poll loop (tests / shutdown). Tracks stay readable.
function TutorialService.Stop()
	running = false
end

----------------------------------------------------------------------
-- Poll loop (2 Hz): level checks, grace timers, home targets, profiles that loaded without a signal
----------------------------------------------------------------------

local function pollPlayer(player, dt)
	local track = tracks[player]
	if not track then
		loadPlayer(player)
		return
	end
	local step = currentStep(track)
	if not step then
		return
	end
	if step.CompleteOn == "NearSpot" then
		if getSpot(player) then
			track.NoSpotTime = 0
		elseif not inMatch(player) then
			track.NoSpotTime = (track.NoSpotTime or 0) + dt
		end
	elseif step.CompleteOn == "Claimed" then
		if track.NoFree and not getSpot(player) and not inMatch(player) then
			track.NoFreeTime = (track.NoFreeTime or 0) + dt
		else
			track.NoFreeTime = 0
		end
	end
	settle(player, track)
	track = tracks[player]
	if track and currentStep(track) and not inMatch(player) then
		refreshTarget(player, track)
	end
end

local function pollLoop()
	local last = os.clock()
	while running do
		task.wait(POLL_INTERVAL)
		if not running then
			break
		end
		local now = os.clock()
		local dt = math.min(now - last, 2)
		last = now
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(pollPlayer, player, dt)
			if not ok then
				warn("[TutorialService] poll failed: " .. tostring(err))
			end
		end
	end
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------

-- settles the current step of `player` (a signal said something changed)
local function nudge(player)
	local track = typeof(player) == "Instance" and tracks[player] or nil
	if track and not track.Done then
		settle(player, track)
		track = tracks[player]
		if track and currentStep(track) then
			refreshTarget(player, track)
		end
	end
end

function TutorialService.Init(lobbyInfo, deps)
	if initialized then
		return
	end
	initialized = true
	deps = type(deps) == "table" and deps or {}
	lobby = type(lobbyInfo) == "table" and lobbyInfo or nil
	local services = script.Parent
	DataService = deps.DataService or loadModule(services, "DataService")
	PetService = deps.PetService or loadModule(services, "PetService")
	MatchService = deps.MatchService or loadModule(services, "MatchService")
	SpotService = deps.SpotService or loadModule(services, "SpotService")
	-- Phase 2 (Main initialises these after this service: only their signals are used before then)
	TycoonService = deps.TycoonService or loadModule(services, "TycoonService")
	PetCareService = deps.PetCareService or loadModule(services, "PetCareService")
	HomeBuilder = loadModule(services, "HomeBuilder")
	TycoonCatalog = loadModule(Shared, "TycoonCatalog")
	PetKeys = loadModule(Shared, "PetKeys")
	-- Phase 3 (the pet-battle chapter)
	BattleService = deps.BattleService or loadModule(services, "BattleService")
	arenaInfo = type(deps.ArenaInfo) == "table" and deps.ArenaInfo or nil
	ArenaBuilder = loadModule(services, "ArenaBuilder")
	EventService = deps.EventService or loadModule(services, "EventService")
	BattleCatalog = loadModule(Shared, "BattleCatalog")

	buildSteps()
	if #steps == 0 then
		warn("[TutorialService] no tutorial steps (shared/TutorialSteps missing?): tutorial disabled")
		return
	end
	if not DataService then
		warn("[TutorialService] DataService unavailable: tutorial disabled")
		return
	end

	-- remote: client-observed events
	local okRemote, remote = pcall(Remotes.Get, "TutorialEvent")
	if okRemote and remote then
		remote.OnServerEvent:Connect(onTutorialEvent)
	else
		warn("[TutorialService] TutorialEvent remote missing: " .. tostring(remote))
	end

	-- profile lifecycle
	if hasSignal(DataService, "ProfileLoaded") then
		DataService.ProfileLoaded:Connect(function(player)
			loadPlayer(player)
		end)
	end
	if hasSignal(DataService, "ProfileRebased") then
		DataService.ProfileRebased:Connect(function(player)
			onProfileRebased(player)
		end)
	end

	-- pets
	if hasSignal(PetService, "Rolled") then
		PetService.Rolled:Connect(function(player)
			local track = tracks[player]
			local step = currentStep(track)
			if step and step.CompleteOn == "Rolled" then
				advance(player, track)
				settle(player, track)
			end
		end)
	end
	if hasSignal(PetService, "PerksChanged") then
		PetService.PerksChanged:Connect(function(player)
			onEquipChanged(player)
		end)
	end

	-- the home chapter
	if hasSignal(TycoonService, "Claimed") then
		TycoonService.Claimed:Connect(function(player)
			nudge(player)
		end)
	end
	if hasSignal(TycoonService, "HomeChanged") then
		TycoonService.HomeChanged:Connect(function(player)
			nudge(player)
		end)
	end
	if hasSignal(TycoonService, "Released") then
		TycoonService.Released:Connect(function(player)
			nudge(player)
		end)
	end
	if hasSignal(PetCareService, "Fed") then
		PetCareService.Fed:Connect(function(player)
			local track = typeof(player) == "Instance" and tracks[player] or nil
			local step = currentStep(track)
			if step and step.CompleteOn == "Fed" then
				advance(player, track)
				settle(player, track)
			end
		end)
	end
	-- Phase 4: the server signals of the new steps (each marks only the step that waits for it)
	local function markOn(module, signalName, mark)
		if hasSignal(module, signalName) then
			module[signalName]:Connect(function(player)
				local track = typeof(player) == "Instance" and tracks[player] or nil
				local step = currentStep(track)
				if step and step.CompleteOn == mark then
					track[mark] = true
					nudge(player)
				end
			end)
		end
	end
	markOn(TycoonService, "CoinsScooped", "CoinsScooped")
	markOn(TycoonService, "PortalUsed", "PortalUsed")
	markOn(PetCareService, "TrainingStarted", "TrainingStarted")

	-- the pet-battle chapter (signals exist at module load, so these connect even before those services Init)
	if hasSignal(DataService, "TeamsChanged") then
		DataService.TeamsChanged:Connect(function(player)
			nudge(player)
		end)
	end
	if hasSignal(BattleService, "BattleEnded") then
		BattleService.BattleEnded:Connect(function(_battleId, result)
			if type(result) ~= "table" then
				return
			end
			local mark = nil
			local list = nil
			if result.Mode == "Trial" then
				mark, list = "TrialWon", result.Winners
			elseif result.Mode == "Raid" then
				mark, list = "RaidSeen", result.Participants or result.Winners
			elseif result.Mode == "Ring" and result.Won == true then
				mark, list = "RingWon", result.Winners
			end
			if not mark or type(list) ~= "table" then
				return
			end
			for _, userId in ipairs(list) do
				local player = type(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
				local track = player and tracks[player]
				local step = currentStep(track)
				if step and step.CompleteOn == mark then
					track[mark] = true
					nudge(player)
				end
			end
		end)
	end
	if hasSignal(BattleService, "RaidJoined") then
		BattleService.RaidJoined:Connect(function(player)
			local track = typeof(player) == "Instance" and tracks[player] or nil
			local step = currentStep(track)
			if step and step.CompleteOn == "RaidSeen" then
				track.RaidSeen = true
				nudge(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	running = true
	task.spawn(pollLoop)
end

return TutorialService
