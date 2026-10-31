-- Main (Script): boots every server service in the order defined in ARCHITECTURE.md / V2 / V3.
-- Each step runs under pcall + warn so one failing service can never brick the whole server.
-- Plain Lua 5.1-compatible syntax only.
--
-- Boot order (Phase 5, ARCHITECTURE_V3.md "Phase 5 build contract" 10.1):
--   Remotes -> Lighting -> Lobby -> Storm Altar -> Arena -> Dungeon world (DungeonBuilder.Build -> NimbusLobby.PartCount)
--   -> Damage -> Token -> Data (autosave / BindToClose)
--   -> Pet / Spot services (they subscribe to profile events; HUD cleanup: the obby items and ItemService are gone)
--   -> Player service (this is what starts loading profiles, so it comes after the subscribers)
--   -> Match -> Portals -> Gates -> Index / Npc -> Tutorial -> Tycoon / PetCare / Fusion / Gem
--   -> Battle -> Dungeon -> Events -> Sky (the living sky clock + raid skies, after Events: it hooks its signals) -> Dev
--   -> Dash relay
-- Every Phase 3+ service is optional (loadOptionalService): a module that is not in the build is skipped quietly, so the
-- game boots at every wave of the build.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
do local okMesh, MeshLibrary = pcall(require, Shared:WaitForChild("MeshLibrary", 5)) if okMesh and type(MeshLibrary) == "table" then MeshLibrary.Start() end end -- Phase 6: Blender meshes (no-op while MeshIds is empty)

local Services = script.Parent:WaitForChild("Services")

local TAG = "[NimbusClimb] "

----------------------------------------------------------------------
-- Boot helpers
----------------------------------------------------------------------

-- Require a service module; returns nil (and warns) instead of erroring.
local function loadService(name)
	local moduleScript = Services:FindFirstChild(name) or Services:WaitForChild(name, 3)
	if not moduleScript then
		warn(TAG .. "service module missing: " .. name)
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(TAG .. "failed to load " .. name .. ": " .. tostring(result))
		return nil
	end
	return result
end

-- Call module[funcName](...) under pcall. Returns (result, success).
-- Optional (newer) services: Rojo syncs every module before scripts run, so a module that is not there
-- right away is simply not part of this build. Do not wait for it (waiting would delay the whole boot).
local function loadOptionalService(name)
	local moduleScript = Services:FindFirstChild(name)
	if not moduleScript then
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(TAG .. "failed to load " .. name .. ": " .. tostring(result))
		return nil
	end
	return result
end

local function call(label, module, funcName, ...)
	if type(module) ~= "table" or type(module[funcName]) ~= "function" then
		warn(TAG .. label .. " skipped (module or function unavailable)")
		return nil, false
	end
	local ok, result = pcall(module[funcName], ...)
	if not ok then
		warn(TAG .. label .. " failed: " .. tostring(result))
		return nil, false
	end
	return result, true
end

-- Run an arbitrary function under pcall + warn.
local function step(label, fn)
	local ok, err = pcall(fn)
	if not ok then
		warn(TAG .. label .. " failed: " .. tostring(err))
	end
	return ok
end

-- True when module[name] is a Util.Signal-like object.
local function hasSignal(module, name)
	return type(module) == "table" and type(module[name]) == "table" and type(module[name].Connect) == "function"
end

-- A tiny cloud platform so players are never dropped into the void if the lobby failed to build.
local function buildEmergencyLobby()
	local origin = Config.Lobby.Origin
	local platform = Instance.new("Part")
	platform.Name = "NimbusEmergencyPlaza"
	platform.Anchored = true
	platform.Shape = Enum.PartType.Cylinder
	platform.Material = Enum.Material.SmoothPlastic
	platform.Color = Color3.fromRGB(150, 168, 200)
	platform.Size = Vector3.new(2, 120, 120) -- cylinder axis is X: rotate it flat below
	platform.CFrame = CFrame.new(origin - Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	platform.Parent = Workspace
	return platform
end

-- Services index lobbyInfo.Portals / .Spots / .Shop directly: make sure those always exist.
local function normaliseLobbyInfo(info)
	if type(info) ~= "table" then
		warn(TAG .. "LobbyBuilder.Build returned nothing; using an emergency plaza")
		local platform = buildEmergencyLobby()
		info = {
			Folder = platform,
			SpawnCFrame = CFrame.new(Config.Lobby.Origin + Vector3.new(0, 4, 0)),
		}
	end
	if type(info.Portals) ~= "table" then
		info.Portals = {}
	end
	if type(info.Spots) ~= "table" then
		info.Spots = {}
	end
	if type(info.Shop) ~= "table" then
		info.Shop = {}
	end
	if type(info.Shop.Roulettes) ~= "table" then
		info.Shop.Roulettes = {}
	end
	return info
end

-- Phase 5 (10.1 / 10.2, judge m3): NimbusLobby.PartCount = the number of BaseParts under the lobby folder AFTER the last
-- gate builder (DungeonBuilder.Build). The loading screen (ReplicatedFirst) compares the replicated count with it.
local function writePartCount(info)
	local folder = type(info) == "table" and info.Folder or nil
	if typeof(folder) ~= "Instance" then
		return
	end
	local count = folder:IsA("BasePart") and 1 or 0
	for _, inst in ipairs(folder:GetDescendants()) do
		if inst:IsA("BasePart") then
			count = count + 1
		end
	end
	folder:SetAttribute("PartCount", count)
end

-- Global world rules. LightingService applies them too; this copy makes sure they hold even if
-- that service failed to load.
local function applyWorldRules()
	pcall(function()
		Workspace.Gravity = Config.Physics.Gravity
	end)
	pcall(function()
		Workspace.FallenPartsDestroyHeight = -2000
	end)
end

-- Spawn gate. Building the lobby takes a moment; a player who joins meanwhile would spawn at the
-- world origin, far below the village, and fall into the void. So characters are held back until
-- the lobby, PlayerService and the spawn providers are ready, then released.
--
-- Phase 5 (7.2, judge M7 / C17): once PlayerService owns the spawn (PlayerService.SpawnPlayer exists: the main menu
-- lands in wave 3), CharacterAutoLoads stays false for the server's life and PlayerService spawns every character
-- itself (on MenuPlay, after Config.MainMenu.FallbackSeconds, or at once when Config.MainMenu.Enabled is false).
-- Until then (Phase 4 PlayerService) the release re-enables CharacterAutoLoads like before.
local spawnsReleased = false
local releaseTimer = nil -- safety net: releases the gate even if a boot step stalls
local playerServiceSpawns = false -- set once PlayerService is loaded and has SpawnPlayer

local function holdSpawns()
	if spawnsReleased then
		return -- the safety timer already opened the gate; never close it again
	end
	pcall(function()
		Players.CharacterAutoLoads = false
	end)
end

local function releaseSpawns()
	if spawnsReleased then
		return
	end
	spawnsReleased = true
	if releaseTimer then
		pcall(task.cancel, releaseTimer)
		releaseTimer = nil
	end
	if playerServiceSpawns then
		return -- the gate stays closed for good: PlayerService.SpawnPlayer loads every character (7.2)
	end
	pcall(function()
		Players.CharacterAutoLoads = true
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent and not player.Character then
			task.spawn(function()
				local ok, err = pcall(function()
					player:LoadCharacter()
				end)
				if not ok then
					warn(TAG .. "LoadCharacter failed for " .. player.Name .. ": " .. tostring(err))
				end
			end)
		end
	end
end

----------------------------------------------------------------------
-- 0. Close the spawn gate first thing; a timer guarantees it opens even if a boot step stalls
----------------------------------------------------------------------

step("Hold spawns", holdSpawns)
releaseTimer = task.delay(30, function()
	releaseTimer = nil
	releaseSpawns()
end)

----------------------------------------------------------------------
-- 1. Remotes must exist before any service that grabs them
----------------------------------------------------------------------

step("Remotes.Init", function()
	Remotes.Init()
end)

local LightingService = loadService("LightingService")
local LobbyBuilder = loadService("LobbyBuilder")
local DamageService = loadService("DamageService")
local TokenService = loadService("TokenService")
local DataService = loadService("DataService")
local PlayerService = loadService("PlayerService")
local PetService = loadService("PetService")
local SpotService = loadService("SpotService")
local HazardService = loadService("HazardService")
local CourseBuilder = loadService("CourseBuilder")
local MatchService = loadService("MatchService")
local PortalService = loadService("PortalService")
-- v3 services (ARCHITECTURE_V3.md)
local IndexService = loadOptionalService("IndexService")
local NpcService = loadOptionalService("NpcService")
local TutorialService = loadOptionalService("TutorialService")
local DevService = loadOptionalService("DevService") -- owner-only developer tools (Config.Dev)
-- Phase 2 services (ARCHITECTURE_V3.md "Phase 2 build contract")
local TycoonService = loadOptionalService("TycoonService")
local PetCareService = loadOptionalService("PetCareService")
local FusionService = loadOptionalService("FusionService")
local GemService = loadOptionalService("GemService")
-- Phase 3 services (ARCHITECTURE_V3.md "Phase 3 build contract")
local ArenaBuilder = loadOptionalService("ArenaBuilder")
local BattleService = loadOptionalService("BattleService")
local EventService = loadOptionalService("EventService")
local StormAltar = loadOptionalService("StormAltar") -- the player's Stormfang landmark (ARCHITECTURE_V3.md section 10)
-- Phase 5 services (ARCHITECTURE_V3.md "Phase 5 build contract" 5.4, 5.5, 6.2)
local DungeonBuilder = loadOptionalService("DungeonBuilder") -- the dungeon gate, templates and runs (dungeon, W3)
local DungeonService = loadOptionalService("DungeonService") -- parties, runs, loot (dungeon, W3)
local GateService = loadOptionalService("GateService") -- the Gate Court prompts (worldlobby, W2)
local SkyService = loadOptionalService("SkyService") -- the living sky: the clock attributes + the raid skies (sky, Task 4)

playerServiceSpawns = type(PlayerService) == "table" and type(PlayerService.SpawnPlayer) == "function"

----------------------------------------------------------------------
-- 2. World: lighting, lobby, altar, arena, dungeon gate, damage, tokens, persistence
----------------------------------------------------------------------

call("LightingService.Init", LightingService, "Init")
step("World rules", applyWorldRules)

-- The Phase 4 LightingService re-enables CharacterAutoLoads; keep the gate closed until the end.
step("Hold spawns", holdSpawns)

local lobbyInfo = call("LobbyBuilder.Build", LobbyBuilder, "Build")
lobbyInfo = normaliseLobbyInfo(lobbyInfo)
if StormAltar then
	call("StormAltar.Build", StormAltar, "Build", lobbyInfo)
end
local arenaInfo = nil
if ArenaBuilder then
	arenaInfo = call("ArenaBuilder.Build", ArenaBuilder, "Build", lobbyInfo)
end
-- Phase 5: the Dungeon gate is the last gate built in the Gate Court; PartCount is written right after it (m3)
local dungeonInfo = nil
if DungeonBuilder then
	dungeonInfo = call("DungeonBuilder.Build", DungeonBuilder, "Build", lobbyInfo)
end
step("NimbusLobby.PartCount", function()
	writePartCount(lobbyInfo)
end)

call("DamageService.Init", DamageService, "Init")
call("TokenService.Init", TokenService, "Init")
call("DataService.StartAutosave", DataService, "StartAutosave")
call("DataService.BindToClose", DataService, "BindToClose")

----------------------------------------------------------------------
-- 3. Economy + spots (subscribe to profile events BEFORE PlayerService starts loading profiles)
----------------------------------------------------------------------

call("PetService.Init", PetService, "Init", lobbyInfo, {
	DataService = DataService,
})

-- HUD cleanup (Task 3): the obby items are gone; a save that still held some was refunded once as Tokens
-- (DataService's B3ItemsRefund migration). The one toast that explains it:
step("Items refund toast", function()
	DataService.Migrated:Connect(function(player, name, info)
		if name ~= "B3ItemsRefund" or type(info) ~= "table" or (tonumber(info.Tokens) or 0) <= 0 then
			return
		end
		pcall(function()
			Remotes.Get("Notify"):FireClient(player, "Items are gone from Nimbus: your old ones were refunded, +" .. tostring(info.Tokens) .. " Tokens!", "token", 6)
		end)
	end)
end)

call("SpotService.Init", SpotService, "Init", lobbyInfo, {
	DataService = DataService,
	PetService = PetService,
})

----------------------------------------------------------------------
-- 4. Players: providers first, then Init (which loads profiles and places characters)
----------------------------------------------------------------------

-- Respawns inside a match go to the team checkpoint; MatchService returns nil otherwise (lobby).
if type(MatchService) == "table" and type(MatchService.GetRespawnCFrame) == "function" then
	call("PlayerService.SetSpawnProvider", PlayerService, "SetSpawnProvider", MatchService.GetRespawnCFrame)
else
	warn(TAG .. "no spawn provider: players will always respawn in the lobby")
end

-- Lobby respawns (after the first spawn) go to the owner's spot when they have one.
if type(SpotService) == "table" and type(SpotService.GetSpot) == "function" then
	call("PlayerService.SetHomeProvider", PlayerService, "SetHomeProvider", function(player)
		local spot = SpotService.GetSpot(player)
		if spot then
			return spot.SpawnCFrame
		end
		return nil
	end)
end

-- Pet perks raise max health; a refresh keeps the health fraction.
if type(PetService) == "table" and type(PetService.GetPerks) == "function" then
	call("PlayerService.SetPerkProvider", PlayerService, "SetPerkProvider", PetService.GetPerks)
	if hasSignal(PetService, "PerksChanged") then
		step("PerksChanged wiring", function()
			PetService.PerksChanged:Connect(function(player)
				if type(PlayerService) == "table" and type(PlayerService.RefreshMaxHealth) == "function" then
					local ok, err = pcall(PlayerService.RefreshMaxHealth, player)
					if not ok then
						warn(TAG .. "RefreshMaxHealth failed: " .. tostring(err))
					end
				end
			end)
		end)
	end
else
	warn(TAG .. "no pet perks: max health stays at the base value")
end

call("PlayerService.Init", PlayerService, "Init", lobbyInfo)

----------------------------------------------------------------------
-- 5. Match flow, portals, gates
----------------------------------------------------------------------

call("MatchService.Init", MatchService, "Init", {
	PlayerService = PlayerService,
	DamageService = DamageService,
	DataService = DataService,
	HazardService = HazardService,
	TokenService = TokenService,
	CourseBuilder = CourseBuilder,
	PetService = PetService,
})

call("PortalService.Init", PortalService, "Init", lobbyInfo, MatchService)

-- Phase 5 (6.2): the Gate Court prompts (the Altar gate; Phase 6: no Home gate; the Obby and Dungeon gates are their services')
if GateService then call("GateService.Init", GateService, "Init", lobbyInfo, {
	SpotService = SpotService,
	PortalService = PortalService,
	StormAltar = StormAltar,
	ArenaInfo = arenaInfo, -- the Arena gate teleports to ArenaInfo.Spawn
	MatchService = MatchService,
	DataService = DataService,
	PlayerService = PlayerService, -- HUD cleanup: the Lobby portal's landing (GetLobbySpawnCFrame)
	TycoonService = TycoonService, -- ... and the portal itself (OpenLobbyPortal; its Init runs below)
}) end

-- v3: Pet Index rewards, lobby NPC pets, new-player tutorial (each handles players who joined before Init).
if IndexService then call("IndexService.Init", IndexService, "Init", { DataService = DataService, PetService = PetService }) end
if NpcService then call("NpcService.Init", NpcService, "Init", lobbyInfo, {}) end
if TutorialService then call("TutorialService.Init", TutorialService, "Init", lobbyInfo, {
	DataService = DataService,
	PetService = PetService,
	MatchService = MatchService,
	SpotService = SpotService,
	IndexService = IndexService,
	BattleService = BattleService, -- Phase 3: tutorial chapter 3 listens to BattleService.BattleEnded
	ArenaInfo = arenaInfo,
	DungeonInfo = dungeonInfo, -- Phase 5: chapter 3 points at the Dungeon gate (the module tables below Init later)
	DungeonService = DungeonService,
}) end
-- Phase 4: TycoonService (the home portal), PetCareService (feeding / evolving / training) and FusionService refuse
-- pets in a running battle or Champion Ring run: they get BattleService's module table now (its Init runs below).
if TycoonService then call("TycoonService.Init", TycoonService, "Init", lobbyInfo, {
	DataService = DataService,
	PetService = PetService,
	SpotService = SpotService,
	BattleService = BattleService,
	GateService = GateService, -- the pill's Travel: a Lobby portal lands through GateService.ToLobby
}) end
if PetCareService then call("PetCareService.Init", PetCareService, "Init", {
	DataService = DataService,
	PetService = PetService,
	TycoonService = TycoonService,
	BattleService = BattleService,
}) end
if FusionService then call("FusionService.Init", FusionService, "Init", {
	DataService = DataService,
	PetService = PetService,
	TycoonService = TycoonService,
	BattleService = BattleService,
}) end
if GemService then call("GemService.Init", GemService, "Init", {
	DataService = DataService,
	PetService = PetService,
}) end
if BattleService then call("BattleService.Init", BattleService, "Init", {
	DataService = DataService,
	PetService = PetService,
	PetCareService = PetCareService,
	TycoonService = TycoonService,
	ArenaBuilder = ArenaBuilder,
	ArenaInfo = arenaInfo,
}) end
-- Phase 5 (5.4, C16): the dungeon lands AFTER BattleService and registers itself with BattleService.SetRunProvider
-- inside its own Init; BattleService never requires DungeonService.
if DungeonService then call("DungeonService.Init", DungeonService, "Init", {
	DataService = DataService,
	PetCareService = PetCareService,
	TycoonService = TycoonService,
	BattleService = BattleService,
	DungeonBuilder = DungeonBuilder,
	DungeonInfo = dungeonInfo,
	LobbyInfo = lobbyInfo,
	PetService = PetService,
}) end
if EventService then call("EventService.Init", EventService, "Init", {
	DataService = DataService,
	BattleService = BattleService,
	PetCareService = PetCareService,
	ArenaInfo = arenaInfo,
}) end
if SkyService then call("SkyService.Init", SkyService, "Init", {
	EventService = EventService, -- EventStarted BossRaid puts the boss's sky up
	BattleService = BattleService, -- BattleEnded Mode "Raid" takes it down; GetRaidStatus for the watchdog
}) end
if DevService then call("DevService.Init", DevService, "Init", {
	DataService = DataService,
	PetService = PetService,
	TutorialService = TutorialService,
	IndexService = IndexService,
	BattleService = BattleService, -- Phase 3: /raid and the DEV panel's raid button
	EventService = EventService,
	DungeonService = DungeonService, -- Phase 5: /reset is refused during a dungeon run
	SkyService = SkyService, -- the living sky: /sky
}) end

----------------------------------------------------------------------
-- 6. Dash relay: validate the cooldown server-side, then show the trail to everyone
----------------------------------------------------------------------

step("Dash remote", function()
	local dashRemote = Remotes.Get("Dash")
	local dashFx = Remotes.Get("DashFx")
	local lastDash = {} -- [player] = os.clock() of the last accepted dash
	-- The client enforces the exact cooldown; allow 20% slack for latency and frame timing.
	local minInterval = Config.Physics.DashCooldown * 0.8

	dashRemote.OnServerEvent:Connect(function(player)
		if player:GetAttribute(Config.Attr.Downed) == true then
			return
		end
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		local now = os.clock()
		local last = lastDash[player]
		if last and now - last < minInterval then
			return
		end
		lastDash[player] = now
		dashFx:FireAllClients(player.UserId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastDash[player] = nil
	end)
end)

-- Everything is wired: let characters spawn (providers are set, the lobby exists). With a Phase 5 PlayerService the
-- gate stays closed and PlayerService spawns the characters itself (7.2).
step("Release spawns", releaseSpawns)

print(TAG .. "ready")
