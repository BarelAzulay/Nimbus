-- GateService (Phase 5, ARCHITECTURE_V3.md "Phase 5 build contract" 6.2): the prompt of the Gate Court's Altar gate.
-- Phase 6: the lobby has no Home gate any more (the player asked): players go home with the Home window's Go home
-- button (HomeAction "GoHome" -> TycoonService's home portal; without a home it leads to a free plot's gate, and the
-- Home tile's Claim a home sends GoToSpot, the same portal). "Home" is no gate id here: Use(player, "Home") is junk.
--
--   GateService.Init(lobbyInfo, deps)  deps = { SpotService, PortalService, StormAltar, ArenaInfo, MatchService,
--                                      DataService, PlayerService, ArenaBuilder } (Main.server, after SpotService.Init
--                                      and PortalService.Init)
--   GateService.Teleported             Util.Signal; Fire(player, "Altar" | "Plaza" | "Court") once per accepted teleport
--   GateService.Use(player, gateId)    the handler behind the prompt (tests call it); -> ok, reason
--   GateService.Travel(player, dest)   HUD cleanup (Quick Travel): the top-left pill's Travel drop-down (Remotes.QuickTravel
--                                      (dest), client -> server) -> ok, reason. dest "Court" = the Gate Court
--                                      (CourtCFrame), "Plaza" = the lobby spawn (PlayerService.GetLobbySpawnCFrame()).
--                                      Checks in order: a real player and a known dest ("junk"), alive ("dead"), not
--                                      InMatch ("match"), not InBattle ("battle", with the gates' toast; also set for a
--                                      whole dungeon run), not locked on a portal pad in its party countdown ("locked"),
--                                      inside the lobby world ("zone": within SpotRingRadius + 120 studs of
--                                      Config.Lobby.Origin horizontally and 80 studs vertically, and in no battle zone,
--                                      ArenaBuilder.ZoneAt), 2 s after the last accepted travel ("cooldown"); then the
--                                      teleport ("failed" when the character cannot be moved). The remote is that rate
--                                      limit too: a refused call is silent (except the battle toast).
--   GateService.CourtCFrame()          the Gate Court landing: 16 studs in front of the Ring gate (LobbyInfo.GateSites.Ring,
--                                      fallback the Dungeon gate), 3 up, facing the gates; nil without either site
--
-- Prompts (created here on LobbyInfo.Gates.<Id>.PromptPart, MaxActivationDistance 12, HoldDuration 0):
--   AltarGatePrompt  "Travel" / "Storm Altar"   -> StormAltar.GetLanding(): the island deck at the bridge end
-- bug batch 2 #4: and on StormAltar.GetReturnPad() (the small return portal beside the landing, MaxActivationDistance 8):
--   PlazaGatePrompt  "Travel" / "Plaza"         -> LobbyInfo.Gates.Altar.ReturnCFrame: the plaza 18 studs in front of
--                                                  the Altar gate (fallback: 15 studs in front of its prompt part)
--                    Teleported fires (player, "Plaza"); the pad is looked up again when the altar was rebuilt.
-- The Obby gate's prompt is PortalService's, the Dungeon gate's DungeonService's, Ring / Arena are ArenaBuilder's.
-- Every use is checked on the server (Y12): the prompt is this one, the player is alive, not InMatch, not
-- InBattle (also set for a whole dungeon run), not locked on a portal pad (PortalService.IsLocked), within
-- MaxActivationDistance + 4 of the prompt part, and 1.5 s after their last use (one cooldown for both directions).
-- A seated player (a lobby bench) is stood up before the teleport so the seat stays where it is. Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local GateService = {}
GateService.Teleported = Util.Signal()

local PROMPT_RANGE = 12
local RANGE_SLACK = 4
local COOLDOWN = 1.5
local ATTR_IN_BATTLE = (Config.Attr and Config.Attr.InBattle) or "InBattle"
local ATTR_IN_MATCH = (Config.Attr and Config.Attr.InMatch) or "InMatch"
-- HUD cleanup (Quick Travel)
local TRAVEL_COOLDOWN = 2
local LOBBY_Y_BAND = 80 -- studs above / below Config.Lobby.Origin that still count as the lobby world
local LOBBY_R = Config.Lobby.SpotRingRadius + 120 -- horizontal reach of the lobby world (plaza, islands, home ring)
local COURT_STANDOFF = 16 -- the Gate Court landing stands this far in front of the Ring gate
local TRAVEL_DESTS = { Court = true, Plaza = true }

local PROMPTS = {
	Altar = { Name = "AltarGatePrompt", Action = "Travel", Object = "Storm Altar" },
	Plaza = { Name = "PlazaGatePrompt", Action = "Travel", Object = "Plaza", Range = 8 }, -- bug batch 2 #4
}
local ORDER = { "Altar" } -- Phase 6: no Home gate (the Home window's Go home is the way home)

local S = {
	deps = {},
	prompts = {}, -- ProximityPrompt -> gate id
	parts = {}, -- gate id -> prompt part
	plazaCF = nil, -- bug batch 2 #4: the "Plaza" gate's arrival (LobbyInfo.Gates.Altar.ReturnCFrame)
	lastUse = {}, -- Player -> os.clock() of the last accepted use
	lastTravel = {}, -- Player -> os.clock() of the last accepted Quick Travel
	lobbyInfo = nil,
	conn = nil,
	initialized = false,
}

local function notify(player, text, kind)
	local ok, remote = pcall(Remotes.Get, "Notify")
	if ok and remote then
		pcall(remote.FireClient, remote, player, text, kind or "info", 4)
	end
end

local function hasFn(t, name)
	return type(t) == "table" and type(t[name]) == "function"
end

local function inMatch(player)
	if player:GetAttribute(ATTR_IN_MATCH) == true then
		return true
	end
	local ms = S.deps.MatchService
	if hasFn(ms, "GetMatchOf") then
		local ok, match = pcall(ms.GetMatchOf, player)
		if ok and match then
			return true
		end
	end
	return false
end

local function inBattle(player)
	local v = player:GetAttribute(ATTR_IN_BATTLE)
	return v ~= nil and v ~= false
end

local function isLocked(player)
	local ps = S.deps.PortalService
	if hasFn(ps, "IsLocked") then
		local ok, locked = pcall(ps.IsLocked, player)
		return ok and locked == true
	end
	return false
end

local function aliveRoot(player)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return root
end

local function placeCharacter(player, cf)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or typeof(cf) ~= "CFrame" then
		return false
	end
	-- bug batch 2 #7: a seated player is welded to an anchored seat; break the weld first or the seat comes along
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat then
		pcall(function()
			for _, d in ipairs(seat:GetChildren()) do
				if d:IsA("JointInstance") and d.Name == "SeatWeld" then
					d:Destroy()
				end
			end
			humanoid.Sit = false
		end)
	end
	local ok = pcall(function()
		char:PivotTo(cf)
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end)
	return ok
end

-- The checks of 6.2 in order, then the teleport. -> ok, reason
function GateService.Use(player, gateId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false, "junk"
	end
	if gateId == "Plaza" then
		GateService._bindPlaza() -- the altar may have been rebuilt since Init
	end
	local part = S.parts[gateId]
	local spec = PROMPTS[gateId]
	if not part or part.Parent == nil or not spec then
		return false, "junk"
	end
	local root = aliveRoot(player)
	if not root then
		return false, "dead"
	end
	if inMatch(player) then
		return false, "match"
	end
	if inBattle(player) then
		notify(player, "Finish your battle first!", "bad")
		return false, "battle"
	end
	if isLocked(player) then
		return false, "locked"
	end
	if (root.Position - part.Position).Magnitude > (spec.Range or PROMPT_RANGE) + RANGE_SLACK then
		return false, "far"
	end
	local now = os.clock()
	local last = S.lastUse[player]
	if last and now - last < COOLDOWN then
		return false, "cooldown"
	end
	S.lastUse[player] = now

	local moved = false
	if gateId == "Altar" then
		local altar = S.deps.StormAltar
		local cf = nil
		if hasFn(altar, "GetLanding") then
			local ok, result = pcall(altar.GetLanding)
			cf = ok and result or nil
		end
		moved = typeof(cf) == "CFrame" and placeCharacter(player, cf)
	elseif gateId == "Plaza" then
		moved = typeof(S.plazaCF) == "CFrame" and placeCharacter(player, S.plazaCF)
	end
	if not moved then
		return false, "failed"
	end
	GateService.Teleported:Fire(player, gateId)
	return true
end

-- The Gate Court landing (Quick Travel "Court"): in front of the Ring gate, facing the gates.
function GateService.CourtCFrame()
	local sites = type(S.lobbyInfo) == "table" and type(S.lobbyInfo.GateSites) == "table" and S.lobbyInfo.GateSites or {}
	local site = sites.Ring
	if typeof(site) ~= "CFrame" then
		site = sites.Dungeon
	end
	if typeof(site) ~= "CFrame" then
		return nil
	end
	local up = Vector3.new(0, 3, 0)
	return CFrame.lookAt(site.Position + site.LookVector * COURT_STANDOFF + up, site.Position + up)
end

-- inside the lobby world (the cylinder around the plaza) and in no battle zone (arena floor, duel rings, Ring pockets)
local function inLobbyWorld(pos)
	local origin = Config.Lobby.Origin
	local flat = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
	if flat.Magnitude > LOBBY_R or math.abs(pos.Y - origin.Y) > LOBBY_Y_BAND then
		return false
	end
	local ab = S.deps.ArenaBuilder
	if hasFn(ab, "ZoneAt") then
		local ok, zone = pcall(ab.ZoneAt, pos)
		if ok and zone ~= nil then
			return false
		end
	end
	return true
end

-- Quick Travel: the checks in order, then the teleport. -> ok, reason
function GateService.Travel(player, dest)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false, "junk"
	end
	if type(dest) ~= "string" or not TRAVEL_DESTS[dest] then
		return false, "junk"
	end
	local root = aliveRoot(player)
	if not root then
		return false, "dead"
	end
	if inMatch(player) then
		return false, "match"
	end
	if inBattle(player) then
		notify(player, "Finish your battle first!", "bad")
		return false, "battle"
	end
	if isLocked(player) then
		return false, "locked"
	end
	if not inLobbyWorld(root.Position) then
		return false, "zone"
	end
	local now = os.clock()
	local last = S.lastTravel[player]
	if last and now - last < TRAVEL_COOLDOWN then
		return false, "cooldown"
	end
	local cf = nil
	if dest == "Court" then
		cf = GateService.CourtCFrame()
	else
		local ps = S.deps.PlayerService
		if hasFn(ps, "GetLobbySpawnCFrame") then
			local ok, result = pcall(ps.GetLobbySpawnCFrame)
			cf = ok and result or nil
		end
		if typeof(cf) ~= "CFrame" and type(S.lobbyInfo) == "table" then
			cf = S.lobbyInfo.SpawnCFrame
		end
	end
	if typeof(cf) ~= "CFrame" or not placeCharacter(player, cf) then
		return false, "failed"
	end
	S.lastTravel[player] = now
	GateService.Teleported:Fire(player, dest)
	return true
end

local function makePrompt(part, spec)
	local old = part:FindFirstChild(spec.Name)
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = spec.Name
	prompt.ActionText = spec.Action
	prompt.ObjectText = spec.Object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = spec.Range or PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

function GateService.Init(lobbyInfo, deps)
	S.deps = type(deps) == "table" and deps or {}
	if S.initialized then
		return
	end
	S.initialized = true
	S.lobbyInfo = type(lobbyInfo) == "table" and lobbyInfo or nil
	local gates = type(lobbyInfo) == "table" and type(lobbyInfo.Gates) == "table" and lobbyInfo.Gates or {}
	for _, id in ipairs(ORDER) do
		local gate = gates[id]
		local part = type(gate) == "table" and gate.PromptPart or nil
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			local prompt = makePrompt(part, PROMPTS[id])
			S.prompts[prompt] = id
			S.parts[id] = part
		else
			warn("[GateService] the lobby has no " .. id .. " gate prompt part")
		end
	end
	-- bug batch 2 #4: the way back from the Storm Altar (the arrival in front of the Altar gate, then the pad's prompt)
	local altarGate = gates.Altar
	if type(altarGate) == "table" and typeof(altarGate.ReturnCFrame) == "CFrame" then
		S.plazaCF = altarGate.ReturnCFrame
	elseif S.parts.Altar then
		local p = S.parts.Altar
		local look = Vector3.new(p.CFrame.LookVector.X, 0, p.CFrame.LookVector.Z)
		look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
		local front = p.Position + look * 15 - Vector3.new(0, 0.5, 0)
		S.plazaCF = CFrame.lookAt(front, front + look)
	end
	GateService._bindPlaza()
	local altar = S.deps.StormAltar
	if type(altar) == "table" and type(altar.Built) == "table" and type(altar.Built.Connect) == "function" then
		altar.Built:Connect(function()
			GateService._bindPlaza() -- a rebuilt altar: the new pad gets the prompt at once
		end)
	end
	S.conn = ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local id = S.prompts[prompt]
		if not id then
			return
		end
		local ok, err = pcall(GateService.Use, player, id)
		if not ok then
			warn("[GateService] " .. id .. ": " .. tostring(err))
		end
	end)
	-- HUD cleanup: the pill's Travel drop-down (a refused call is silent, except the battle toast)
	local okRemote, travelRemote = pcall(Remotes.Get, "QuickTravel")
	if okRemote and travelRemote then
		travelRemote.OnServerEvent:Connect(function(player, dest)
			local ok, err = pcall(GateService.Travel, player, dest)
			if not ok then
				warn("[GateService] QuickTravel: " .. tostring(err))
			end
		end)
	else
		warn("[GateService] no QuickTravel remote")
	end
	Players.PlayerRemoving:Connect(function(player)
		S.lastUse[player] = nil
		S.lastTravel[player] = nil
	end)
end

-- bug batch 2 #4: (re)binds the "Plaza" gate to the Storm Altar's return pad; a rebuilt altar gets a fresh prompt.
function GateService._bindPlaza()
	local current = S.parts.Plaza
	if current and current.Parent ~= nil then
		return current
	end
	local altar = S.deps.StormAltar
	local part = nil
	if hasFn(altar, "GetReturnPad") then
		local ok, result = pcall(altar.GetReturnPad)
		part = ok and result or nil
	end
	for prompt, id in pairs(S.prompts) do
		if id == "Plaza" then
			S.prompts[prompt] = nil -- the old altar's prompt (destroyed with it)
		end
	end
	S.parts.Plaza = nil
	if typeof(part) == "Instance" and part:IsA("BasePart") and S.plazaCF then
		local prompt = makePrompt(part, PROMPTS.Plaza)
		S.prompts[prompt] = "Plaza"
		S.parts.Plaza = part
		return part
	end
	return nil
end

-- The prompt of a gate ("Altar", "Plaza"), for tests and tutorials.
function GateService.GetPrompt(gateId)
	if gateId == "Plaza" then
		GateService._bindPlaza()
	end
	local part = S.parts[gateId]
	local spec = PROMPTS[gateId]
	return part and spec and part:FindFirstChild(spec.Name) or nil
end

return GateService
