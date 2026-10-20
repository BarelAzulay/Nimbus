-- GateService (Phase 5, ARCHITECTURE_V3.md "Phase 5 build contract" 6.2): the prompt of the Gate Court's Altar gate.
-- Phase 6: the lobby has no Home gate any more (the player asked): players go home with the Home window's Go home
-- button (HomeAction "GoHome" -> TycoonService's home portal; without a home it leads to a free plot's gate, and the
-- Home tile's Claim a home sends GoToSpot, the same portal). "Home" is no gate id here: Use(player, "Home") is junk.
--
--   GateService.Init(lobbyInfo, deps)  deps = { SpotService, PortalService, StormAltar, ArenaInfo, MatchService,
--                                      DataService } (Main.server, after SpotService.Init and PortalService.Init)
--   GateService.Teleported             Util.Signal; Fire(player, "Altar") once per accepted teleport
--   GateService.Use(player, gateId)    the handler behind the prompt (tests call it); -> ok, reason
--
-- Prompts (created here on LobbyInfo.Gates.<Id>.PromptPart, MaxActivationDistance 12, HoldDuration 0):
--   AltarGatePrompt  "Travel" / "Storm Altar"   -> StormAltar.GetLanding(): the island deck at the bridge end
-- The Obby gate's prompt is PortalService's, the Dungeon gate's DungeonService's, Ring / Arena are ArenaBuilder's.
-- Every use is checked on the server (Y12): the prompt is this one, the player is alive, not InMatch, not
-- InBattle, not locked on a portal pad (PortalService.IsLocked), within MaxActivationDistance + 4 of the prompt
-- part, and 1.5 s after their last use. Plain Lua 5.1-compatible syntax only.

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

local PROMPTS = {
	Altar = { Name = "AltarGatePrompt", Action = "Travel", Object = "Storm Altar" },
}
local ORDER = { "Altar" } -- Phase 6: no Home gate (the Home window's Go home is the way home)

local S = {
	deps = {},
	prompts = {}, -- ProximityPrompt -> gate id
	parts = {}, -- gate id -> prompt part
	lastUse = {}, -- Player -> os.clock() of the last accepted use
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
	local part = S.parts[gateId]
	if not part or part.Parent == nil then
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
	if (root.Position - part.Position).Magnitude > PROMPT_RANGE + RANGE_SLACK then
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
	end
	if not moved then
		return false, "failed"
	end
	GateService.Teleported:Fire(player, gateId)
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
	prompt.MaxActivationDistance = PROMPT_RANGE
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
	Players.PlayerRemoving:Connect(function(player)
		S.lastUse[player] = nil
	end)
end

-- The prompt of a gate ("Altar"), for tests and tutorials.
function GateService.GetPrompt(gateId)
	local part = S.parts[gateId]
	local spec = PROMPTS[gateId]
	return part and spec and part:FindFirstChild(spec.Name) or nil
end

return GateService
