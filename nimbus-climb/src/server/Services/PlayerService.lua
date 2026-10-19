-- PlayerService: per-player lifecycle, spawn placement, humanoid setup, leaderstats, lobby rules.
--
-- * PlayerAdded: attributes, leaderstats, saved profile (via DataService).
-- * CharacterAdded: perk-aware humanoid stats, placement, brief spawn i-frames.
--     placement order: spawn provider (match checkpoint) -> own spot (lobby respawns only)
--                      -> scattered plaza spawn (first spawn, or no spot).
-- * Perk-aware max health: Main hands us PetService.GetPerks via SetPerkProvider(fn) and calls
--   RefreshMaxHealth(player) whenever PetService.PerksChanged fires. A refresh keeps the health
--   FRACTION (a half-health player stays at half health with the new maximum).
-- * 0.5s lobby loop: players who fall off the lobby are sent back (no damage), the lobby keeps
--   everybody at full health, and max health self-heals if it ever drifts from the perks.
-- * PlayerRemoving: save + cleanup (DataService decides when the profile cache entry is released:
--   never while the final save failed).
--
-- Public API (ARCHITECTURE.md + v2):
--   Init(lobbyInfo)  SetSpawnProvider(fn)  SetPerkProvider(fn)  SetHomeProvider(fn)
--   SendToLobby(player)  GetLobbySpawnCFrame()  ApplyHumanoidStats(player)
--   GetMaxHealth(player)  RefreshMaxHealth(player)
--   SpawnPlayer(player) -> bool   HasSpawned(player) -> bool          (Phase 5, 7.2)
--
-- Phase 5 spawn gate (ARCHITECTURE_V3.md "Phase 5 build contract" 7.2, judge M7 / C17): the SERVER holds the
-- character until the main menu's PLAY. Init sets Players.CharacterAutoLoads = false for the server's life (Main's
-- boot gate never re-enables it once SpawnPlayer exists), so every character is loaded here:
--   * Config.MainMenu.Enabled = true: PlayerAdded only records the player as waiting; the remote MenuPlay (c->s, no
--     args, the first one per session counts, 1 per second) or a Config.MainMenu.FallbackSeconds (90) timer calls
--     SpawnPlayer. A client that never sends MenuPlay (old client, script error, exploit) still spawns after 90 s (Y13).
--   * Config.MainMenu.Enabled = false: the character spawns at once on PlayerAdded (the Phase 4 behaviour).
--   * After the first spawn, Humanoid.Died -> task.delay(Players.RespawnTime) -> a new character (Roblox's automatic
--     respawn is off); the lobby loop also respawns a spawned player whose character vanished without dying.
-- SpawnPlayer = one player:LoadCharacter(), idempotent: skipped when the player left or already has a live character.
--
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local DamageService = require(script.Parent.DamageService)

local PlayerService = {}

local SCATTER_RADIUS = 8 -- studs; plaza spawns are spread so players don't stack
local LOBBY_TICK = 0.5 -- seconds between lobby safety checks
local SPAWN_IFRAMES = 1.5 -- seconds of protection after every (re)spawn
local SAFE_MARGIN = 15 -- studs above KillY a position must be to count as "last safe"

local lobbySpawn = CFrame.new(Config.Lobby.Origin + Vector3.new(0, 3, 0))
local spawnProvider = nil -- fn(player) -> CFrame|nil   (match checkpoint)
local perkProvider = nil -- fn(player) -> { MaxHealth = fraction, ... }|nil
local homeProvider = nil -- fn(player) -> CFrame|nil    (the owner's lobby spot)
local initialized = false
local running = false
local perkWarned = false
-- perPlayer[player] = { Conns = { RBXScriptConnection... }, Spawned = bool, LastSafe = Vector3|nil }
local perPlayer = {}
local rng = Random.new()
-- Phase 5 spawn gate state (7.2). Tests read it through PlayerService._St.
--   waiting[player] = true until the first spawn; timers[player] = the fallback thread; played[player] = the clock of the
--   accepted MenuPlay (only the first counts); lastPlay[player] = the clock of the last MenuPlay (1/s rate);
--   spawned[player] = true after the first SpawnPlayer; respawning[player] = true while a respawn is scheduled
local Spawn = { St = { waiting = {}, timers = {}, played = {}, lastPlay = {}, spawned = {}, respawning = {}, missing = {} } }
PlayerService._St = Spawn.St

----------------------------------------------------------------------
-- Placement helpers
----------------------------------------------------------------------

-- A plaza spawn CFrame nudged to a random spot near the spawn point.
local function scatteredLobbyCFrame()
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(rng:NextNumber(0, 1)) * SCATTER_RADIUS
	return lobbySpawn * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- The owner's spot spawn, or nil when the player has none (or the provider is not wired).
local function homeCFrameFor(player)
	if not homeProvider then
		return nil
	end
	local ok, result = pcall(homeProvider, player)
	if ok and typeof(result) == "CFrame" then
		return result
	end
	if not ok then
		warn("[PlayerService] home provider failed: " .. tostring(result))
	end
	return nil
end

-- Teleport a character and kill any leftover momentum.
local function placeCharacter(char, cframe)
	if not char or not char.Parent then
		return
	end
	local ok, err = pcall(function()
		char:PivotTo(cframe)
	end)
	if not ok then
		warn("[PlayerService] PivotTo failed: " .. tostring(err))
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end
end

-- Roblox's built-in "Health" script slowly regenerates health, which would heal players during a
-- match (and un-pin downed players). DamageService is the only authority, so remove it.
local function removeDefaultRegen(char)
	local regen = char:WaitForChild("Health", 3)
	if regen and regen:IsA("Script") then
		regen:Destroy()
	end
end

----------------------------------------------------------------------
-- Perks -> max health
----------------------------------------------------------------------

-- The perk table for a player, or nil (no provider / provider failed / not a table).
local function getPerks(player)
	if not perkProvider then
		return nil
	end
	local ok, perks = pcall(perkProvider, player)
	if ok then
		if type(perks) == "table" then
			return perks
		end
		return nil
	end
	if not perkWarned then
		perkWarned = true
		warn("[PlayerService] perk provider failed: " .. tostring(perks))
	end
	return nil
end

-- Config.Physics.MaxHealth * (1 + MaxHealth perk), rounded to a whole number and never below 1.
function PlayerService.GetMaxHealth(player)
	local bonus = 0
	local perks = getPerks(player)
	if perks then
		local value = perks.MaxHealth
		if type(value) == "number" and value == value then
			local cap = 1
			if Config.Pets and Config.Pets.PerkCaps and type(Config.Pets.PerkCaps.MaxHealth) == "number" then
				cap = Config.Pets.PerkCaps.MaxHealth
			end
			bonus = Util.Clamp(value, 0, cap)
		end
	end
	return math.max(1, math.floor(Config.Physics.MaxHealth * (1 + bonus) + 0.5))
end

-- Re-applies the perk-aware maximum to the live humanoid and KEEPS the health fraction.
-- A downed player keeps their pinned health (DamageService owns it).
function PlayerService.RefreshMaxHealth(player)
	local humanoid = Util.GetHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local newMax = PlayerService.GetMaxHealth(player)
	local oldMax = humanoid.MaxHealth
	if math.abs(oldMax - newMax) < 0.01 then
		return
	end
	local fraction = 1
	if oldMax > 0 then
		fraction = Util.Clamp(humanoid.Health / oldMax, 0, 1)
	end
	humanoid.MaxHealth = newMax
	if player:GetAttribute(Config.Attr.Downed) ~= true then
		humanoid.Health = math.max(Config.Damage.DownedHealth, math.min(newMax, newMax * fraction))
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function PlayerService.GetLobbySpawnCFrame()
	return lobbySpawn
end

-- fn(player) -> CFrame|nil : the match checkpoint to (re)spawn at, nil => lobby.
function PlayerService.SetSpawnProvider(fn)
	if fn == nil or type(fn) == "function" then
		spawnProvider = fn
	else
		warn("[PlayerService] SetSpawnProvider expects a function or nil")
	end
end

-- fn(player) -> { MaxHealth = fraction, ... } (PetService.GetPerks). Applied to everyone right away.
function PlayerService.SetPerkProvider(fn)
	if fn == nil or type(fn) == "function" then
		perkProvider = fn
		perkWarned = false
	else
		warn("[PlayerService] SetPerkProvider expects a function or nil")
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerService.RefreshMaxHealth(player)
	end
end

-- fn(player) -> CFrame|nil : where a lobby RESPAWN goes (the owner's spot). The first spawn of a
-- session always uses the plaza.
function PlayerService.SetHomeProvider(fn)
	if fn == nil or type(fn) == "function" then
		homeProvider = fn
	else
		warn("[PlayerService] SetHomeProvider expects a function or nil")
	end
end

-- WalkSpeed / JumpPower / MaxHealth (perk-aware) / Health from Config. A downed player keeps
-- their frozen stats and their pinned health so a stray call can never "heal" them.
function PlayerService.ApplyHumanoidStats(player)
	local humanoid = Util.GetHumanoid(player)
	if not humanoid then
		return
	end
	humanoid.UseJumpPower = true
	humanoid.MaxHealth = PlayerService.GetMaxHealth(player)

	if player:GetAttribute(Config.Attr.Downed) == true then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	else
		humanoid.WalkSpeed = Config.Physics.WalkSpeed
		humanoid.JumpPower = Config.Physics.JumpPower
		humanoid.Health = humanoid.MaxHealth
	end

	-- Cosmetic: the custom HUD owns the health display, and auto-jump fights precise parkour.
	pcall(function()
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.AutoJumpEnabled = false
	end)
end

-- Clears InMatch/Downed, heals, and puts the player back on the lobby plaza.
function PlayerService.SendToLobby(player)
	if not player or not player.Parent then
		return
	end
	pcall(DamageService.ClearDowned, player)
	player:SetAttribute(Config.Attr.InMatch, false)
	player:SetAttribute(Config.Attr.Downed, false)

	local record = perPlayer[player]
	if record then
		record.LastSafe = nil
	end

	local char = player.Character
	local humanoid = Util.GetHumanoid(player)
	if char and humanoid and humanoid.Health > 0 then
		PlayerService.ApplyHumanoidStats(player)
		placeCharacter(char, scatteredLobbyCFrame())
	end
	-- If the character is dead or missing, the respawn flow places the new one in the lobby
	-- (InMatch is false now, so the spawn provider returns nil).
end

----------------------------------------------------------------------
-- Phase 5 spawn gate (7.2)
----------------------------------------------------------------------

function Spawn.menuEnabled()
	return type(Config.MainMenu) == "table" and Config.MainMenu.Enabled == true
end

function Spawn.hasLiveCharacter(player)
	local char = player.Character
	if not char or not char.Parent then
		return false
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	return humanoid == nil or humanoid.Health > 0
end

function Spawn.cancelFallback(player)
	local timer = Spawn.St.timers[player]
	Spawn.St.timers[player] = nil
	if timer and coroutine.running() ~= timer then
		pcall(task.cancel, timer)
	end
end

-- one LoadCharacter; true when a character was loaded
function Spawn.loadCharacter(player)
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn("[PlayerService] LoadCharacter failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

-- Loads the player's character once: skipped when the player left, is unknown here, or already has a live character.
function PlayerService.SpawnPlayer(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent or not perPlayer[player] then
		return false
	end
	Spawn.St.waiting[player] = nil
	Spawn.cancelFallback(player)
	if Spawn.hasLiveCharacter(player) then
		Spawn.St.spawned[player] = true
		return false
	end
	Spawn.St.spawned[player] = true
	return Spawn.loadCharacter(player)
end

-- True once the player's first spawn happened (MenuPlay, the fallback, or at once with the menu disabled).
function PlayerService.HasSpawned(player)
	return Spawn.St.spawned[player] == true
end

-- Roblox's automatic respawn is off (CharacterAutoLoads = false): a dead character comes back after RespawnTime.
function Spawn.scheduleRespawn(player, char)
	if Spawn.St.respawning[player] then
		return
	end
	Spawn.St.respawning[player] = true
	local delaySeconds = 5
	pcall(function()
		delaySeconds = Players.RespawnTime
	end)
	task.delay(delaySeconds, function()
		Spawn.St.respawning[player] = nil
		if not player.Parent or not perPlayer[player] then
			return
		end
		local current = player.Character
		if current ~= nil and current ~= char and Spawn.hasLiveCharacter(player) then
			return -- something else (a match) already gave the player a new character
		end
		Spawn.loadCharacter(player)
	end)
end

function Spawn.watchDeath(player, char, humanoid)
	humanoid.Died:Connect(function()
		if player.Character == char then
			Spawn.scheduleRespawn(player, char)
		end
	end)
end

-- MenuPlay (c->s, no args): only the first per session counts, at most one per second; junk arguments are ignored.
function Spawn.onMenuPlay(player)
	if typeof(player) ~= "Instance" or not perPlayer[player] then
		return
	end
	local now = os.clock()
	local last = Spawn.St.lastPlay[player]
	if last and now - last < 1 then
		return
	end
	Spawn.St.lastPlay[player] = now
	if Spawn.St.played[player] then
		return
	end
	Spawn.St.played[player] = now
	if Spawn.St.waiting[player] then
		PlayerService.SpawnPlayer(player)
	end
end

-- A new player: wait for PLAY (menu on, with the 90 s fallback) or spawn at once (menu off).
function Spawn.holdOrSpawn(player)
	if Spawn.St.spawned[player] or Spawn.St.waiting[player] then
		return
	end
	if not Spawn.menuEnabled() then
		PlayerService.SpawnPlayer(player)
		return
	end
	Spawn.St.waiting[player] = true
	local seconds = tonumber(Config.MainMenu.FallbackSeconds) or 90
	Spawn.St.timers[player] = task.delay(seconds, function()
		Spawn.St.timers[player] = nil
		if Spawn.St.waiting[player] and player.Parent then
			PlayerService.SpawnPlayer(player)
		end
	end)
end

-- Lobby loop safety net: a spawned player whose character vanished without dying (destroyed, not Died) gets a new one
-- after two quiet seconds.
function Spawn.checkMissing(player)
	if not Spawn.St.spawned[player] or Spawn.St.respawning[player] or Spawn.St.waiting[player] then
		Spawn.St.missing[player] = nil
		return
	end
	local char = player.Character
	if char and char.Parent then
		Spawn.St.missing[player] = nil
		return
	end
	local now = os.clock()
	local since = Spawn.St.missing[player]
	if not since then
		Spawn.St.missing[player] = now
	elseif now - since >= 2 then
		Spawn.St.missing[player] = nil
		Spawn.loadCharacter(player)
	end
end

----------------------------------------------------------------------
-- Character + player lifecycle
----------------------------------------------------------------------

local function onCharacterAdded(player, char)
	local humanoid = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	-- The player may have left or respawned again while we waited.
	if not player.Parent or player.Character ~= char or not char.Parent then
		return
	end
	local record = perPlayer[player]

	PlayerService.ApplyHumanoidStats(player)

	-- 1. A match checkpoint, when the provider has one for this player.
	local target = nil
	if spawnProvider then
		local ok, result = pcall(spawnProvider, player)
		if ok then
			if typeof(result) == "CFrame" then
				target = result
			end
		else
			warn("[PlayerService] spawn provider failed: " .. tostring(result))
		end
	end
	-- 2. A lobby respawn goes home (the first spawn of a session always uses the plaza).
	if not target and record and record.Spawned and player:GetAttribute(Config.Attr.InMatch) ~= true then
		target = homeCFrameFor(player)
	end
	-- 3. The plaza.
	if not target then
		target = scatteredLobbyCFrame()
	end
	placeCharacter(char, target)
	if record then
		record.Spawned = true
		record.LastSafe = nil
	end

	DamageService.GrantInvulnerability(player, SPAWN_IFRAMES)
	Spawn.watchDeath(player, char, humanoid)
	task.spawn(removeDefaultRegen, char)
end

local function setupPlayer(player)
	if perPlayer[player] then
		return
	end
	local record = { Conns = {}, Spawned = false, LastSafe = nil }
	perPlayer[player] = record

	-- Attributes first so the HUD never reads nil.
	player:SetAttribute(Config.Attr.Tokens, 0)
	player:SetAttribute(Config.Attr.MatchTokens, 0)
	player:SetAttribute(Config.Attr.InMatch, false)
	player:SetAttribute(Config.Attr.Downed, false)

	-- leaderstats.Tokens mirrors the CloudTokens attribute (DataService also pushes into it).
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local tokensValue = stats:FindFirstChild("Tokens")
	if not tokensValue then
		tokensValue = Instance.new("IntValue")
		tokensValue.Name = "Tokens"
		tokensValue.Value = 0
		tokensValue.Parent = stats
	end

	table.insert(
		record.Conns,
		player:GetAttributeChangedSignal(Config.Attr.Tokens):Connect(function()
			local value = player:GetAttribute(Config.Attr.Tokens)
			if type(value) == "number" then
				tokensValue.Value = math.floor(value)
			end
		end)
	)

	-- Connect before the (yielding) data load so an early character is not missed.
	table.insert(
		record.Conns,
		player.CharacterAdded:Connect(function(char)
			onCharacterAdded(player, char)
		end)
	)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	-- Phase 5 (7.2): hold the character for the main menu, or spawn it now (menu disabled). Before the data load so a
	-- menu-less join gets its character at once, like the Phase 4 automatic spawn.
	Spawn.holdOrSpawn(player)

	-- Saved data. DataService.Load never errors; the pcall is belt and braces.
	pcall(DataService.Load, player)
	if not player.Parent then
		-- Left while loading: PlayerRemoving may already have run its save, so ask DataService to free
		-- the cache. Release is conditional (it keeps an entry that still holds unsaved progress).
		if type(DataService.Release) == "function" then
			pcall(DataService.Release, player)
		end
		return
	end
	-- Phase 5 (7.1): the loading screen waits for the player attribute ProfileLoaded (loaded or provisional). The contract
	-- has DataService write it; until it does, the end of Load (it never errors, provisional included) is the moment.
	local profileAttr = (Config.Attr and Config.Attr.ProfileLoaded) or "ProfileLoaded"
	if player:GetAttribute(profileAttr) ~= true then
		player:SetAttribute(profileAttr, true)
	end
	local okTokens, tokens = pcall(DataService.GetTokens, player)
	if okTokens and type(tokens) == "number" then
		player:SetAttribute(Config.Attr.Tokens, tokens)
		tokensValue.Value = math.floor(tokens)
	end
	-- Pet perks may be known by now; if PetService is slower it fires PerksChanged later.
	PlayerService.RefreshMaxHealth(player)
end

local function onPlayerRemoving(player)
	local record = perPlayer[player]
	perPlayer[player] = nil
	Spawn.cancelFallback(player)
	for _, map in pairs(Spawn.St) do
		map[player] = nil
	end
	if record then
		for _, conn in ipairs(record.Conns) do
			conn:Disconnect()
		end
	end
	-- Save only. Freeing the profile cache entry is DataService's decision (its own PlayerRemoving
	-- handler releases after ITS save): a failed final save must keep the entry for retries.
	pcall(DataService.Save, player)
end

----------------------------------------------------------------------
-- Lobby rules
----------------------------------------------------------------------

-- Where a player who fell off the village goes: their own spot when they fell closer to it than
-- to the plaza, otherwise the plaza.
local function recoverCFrame(player, record)
	if record and record.LastSafe then
		local home = homeCFrameFor(player)
		if home then
			local toHome = (record.LastSafe - home.Position).Magnitude
			local toPlaza = (record.LastSafe - lobbySpawn.Position).Magnitude
			if toHome < toPlaza then
				return home
			end
		end
	end
	return scatteredLobbyCFrame()
end

local function lobbyTick()
	for _, player in ipairs(Players:GetPlayers()) do
		if perPlayer[player] then
			Spawn.checkMissing(player)
		end
		if player:GetAttribute(Config.Attr.InMatch) ~= true then
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 then
				local record = perPlayer[player]
				local y = root.Position.Y
				if y < Config.Lobby.KillY then
					-- Fell off the cloud village: back home / to the plaza, no damage.
					placeCharacter(char, recoverCFrame(player, record))
					if record then
						record.LastSafe = nil
					end
				elseif record and y > Config.Lobby.KillY + SAFE_MARGIN and humanoid.FloorMaterial ~= Enum.Material.Air then
					record.LastSafe = root.Position
				end

				-- Safety net: max health follows the perks even if a PerksChanged event was missed.
				if math.abs(humanoid.MaxHealth - PlayerService.GetMaxHealth(player)) >= 0.5 then
					PlayerService.RefreshMaxHealth(player)
				end
				-- The lobby is safe: keep everybody topped up.
				if humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = humanoid.MaxHealth
				end
			end
		end
	end
end

local function lobbyLoop()
	while running do
		task.wait(LOBBY_TICK)
		if not running then
			break
		end
		local ok, err = pcall(lobbyTick)
		if not ok then
			warn("[PlayerService] lobby loop error: " .. tostring(err))
		end
	end
end

function PlayerService.Init(lobbyInfo)
	if initialized then
		return
	end
	initialized = true

	-- Phase 5 (7.2): the server spawns every character itself (SpawnPlayer) for the server's life
	pcall(function()
		Players.CharacterAutoLoads = false
	end)
	local okRemote, menuPlay = pcall(Remotes.Get, "MenuPlay")
	if okRemote and menuPlay then
		menuPlay.OnServerEvent:Connect(Spawn.onMenuPlay)
	else
		warn("[PlayerService] no MenuPlay remote: players spawn after the fallback timer")
	end

	if type(lobbyInfo) == "table" and typeof(lobbyInfo.SpawnCFrame) == "CFrame" then
		lobbySpawn = lobbyInfo.SpawnCFrame
	else
		warn("[PlayerService] no lobbyInfo.SpawnCFrame; using the default lobby origin")
	end

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end

	running = true
	task.spawn(lobbyLoop)
	game:BindToClose(function()
		running = false -- stop the lobby loop on shutdown
	end)
end

return PlayerService
