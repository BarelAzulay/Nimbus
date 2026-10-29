-- Podium (wave 6 "fight focus", docs/superpowers/specs/2026-10-29-fight-focus-wave6-design.md goal 3): in the Champion
-- Ring and PvP duels the trainer stands on the podium for the whole fight and cheers; the pet does the fighting. The
-- podium is the spot each mode already teleports the trainer to: the Ring pocket's SpawnPad (the run's Zone.Spawn) and the
-- duel side's ChallengePad (BattleService duelStand). The lock is by position, never by colour. Server-authoritative:
-- the character's HumanoidRootPart is ANCHORED at the stand CFrame (turning the camera still works) and the player
-- attribute Config.Attr.OnPodium = true tells the client to loop the cheer emote. Not used in dungeons or raids.
-- Plain Lua 5.1-compatible syntax only.
--
-- API
--   Podium.Init(deps)                 deps = { Notify = fn(player, text, kind, seconds) } (optional); CharacterAdded /
--                                     PlayerRemoving release a lock (a fresh character is never anchored)
--   Podium.Lock(player, standCFrame, key) -> bool   teleports the character onto the stand, anchors the root, sets
--                                     OnPodium; one toast per `key` (the battle / ring run id): TOAST
--   Podium.Release(player, key)       idempotent: unanchors the locked root, clears OnPodium, forgets the lock; with a
--                                     `key` only a lock taken with that key (a ring's next round keeps its own lock)
--   Podium.IsLocked(player) -> bool
--   Podium.Tick()                     (the battle heartbeat) a locked root > SNAP studs off its stand is put back; one
--                                     > LET_GO studs off (a game teleport) and a lock whose character died / respawned /
--                                     left are released
--   Podium.ReleaseAll()               (Shutdown) every lock released
--   Podium.TOAST                      "You're the trainer: cheer your pet on from the podium!"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Podium = {}

Podium.TOAST = "You're the trainer: cheer your pet on from the podium!"
Podium.SNAP = 2 -- studs a locked root may drift (an exploit nudge, a physics push) before it is put back
Podium.LET_GO = 25 -- a root moved further than this was teleported by the game (an obby match, a return): the lock lets go
-- (the battle's presence check / leash then judges where the player went, exactly as before the podium)

local ATTR = (Config.Attr and Config.Attr.OnPodium) or "OnPodium"

local locks = {} -- [player] = { stand = CFrame, root = BasePart, char = Model, key = string }
local toasted = {} -- [player] = { [key] = true }
local deps = {}

-- root, humanoid, character of a living character (nil otherwise)
local function aliveRoot(player)
	local char = typeof(player) == "Instance" and player.Character
	if not char then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	return root, humanoid, char
end

local function setAttr(player, value)
	pcall(function()
		player:SetAttribute(ATTR, value)
	end)
end

function Podium.Release(player, key)
	local lock = locks[player]
	if lock and key ~= nil and tostring(lock.key) ~= tostring(key) then
		return
	end
	locks[player] = nil
	if lock and lock.root then
		pcall(function()
			lock.root.Anchored = false
		end)
	end
	if typeof(player) == "Instance" then
		setAttr(player, nil)
	end
end

function Podium.Lock(player, standCFrame, key)
	if typeof(standCFrame) ~= "CFrame" then
		return false
	end
	local root, _, char = aliveRoot(player)
	if not root then
		return false
	end
	local old = locks[player]
	if old and old.root and old.root ~= root then
		pcall(function()
			old.root.Anchored = false
		end)
	end
	local ok = pcall(function()
		root.Anchored = false
		char:PivotTo(standCFrame)
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		root.Anchored = true
	end)
	if not ok then
		return false
	end
	locks[player] = { stand = standCFrame, root = root, char = char, key = tostring(key or "") }
	setAttr(player, true)
	key = tostring(key or "")
	local seen = toasted[player]
	if not seen then
		seen = {}
		toasted[player] = seen
	end
	if not seen[key] then
		seen[key] = true
		if type(deps.Notify) == "function" then
			pcall(deps.Notify, player, Podium.TOAST, "info", 4)
		end
	end
	return true
end

function Podium.IsLocked(player)
	return locks[player] ~= nil
end

function Podium.Tick()
	for player, lock in pairs(locks) do
		local root, _, char = aliveRoot(player)
		if not root or root ~= lock.root or char ~= lock.char or not player.Parent then
			-- died, respawned or left: let go (the new character is never anchored)
			Podium.Release(player)
		else
			local off = (root.Position - lock.stand.Position).Magnitude
			if off > Podium.LET_GO then
				Podium.Release(player)
			elseif off > Podium.SNAP or not root.Anchored then
				pcall(function()
					root.Anchored = false
					char:PivotTo(lock.stand)
					root.Anchored = true
				end)
			end
		end
	end
end

function Podium.ReleaseAll()
	local list = {}
	for player in pairs(locks) do
		list[#list + 1] = player
	end
	for _, player in ipairs(list) do
		Podium.Release(player)
	end
end

local function watch(player)
	player.CharacterAdded:Connect(function()
		if locks[player] then
			Podium.Release(player)
		end
	end)
end

function Podium.Init(d)
	deps = type(d) == "table" and d or {}
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		Podium.Release(player)
		toasted[player] = nil
	end)
end

return Podium
