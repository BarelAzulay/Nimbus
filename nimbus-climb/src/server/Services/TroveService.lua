-- TroveService (store 2026-11-04; docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.3 / 7 Z10-Z11 / 13b.5): the
-- Sky Trove, the lobby chest in the old item stall's place (LobbyBuilder buildTrove) that pays ONCE PER ACCOUNT for a
-- verified join of the owner's Roblox group (Config.Trove: GroupId, PromptRange, Slack, Cooldown, Asks).
--
-- Flow
--   * Init puts a ProximityPrompt ("Sky Trove" / "Open", PromptRange studs, no hold, no line of sight) on
--     lobbyInfo.Shop.ItemShop.PromptPart. Triggered -> Open(player): a live player, not InMatch / InBattle, the root
--     within PromptRange + Slack studs of the chest's Center, one Open per Cooldown seconds -> OpenPanel("Trove") +
--     TroveState(State(player)) to that client only. Found by walking: no arrow, no tutorial step, no HUD entry.
--   * The client's JOIN runs GroupService:PromptJoinAsync; on Joined / AlreadyMember it sends TroveRequest("Joined").
--   * Joined(player): junk and a second request within 1 s are ignored; refused in a match, while GroupId is 0 ("Coming
--     soon"), while the save is loading or provisional (no call: State Loading), silently once the ask is set (Done),
--     and with the 13b.5 copy (no call) once THIS visit's check answered false (Checked: a server cannot refresh a false
--     answer, so only a rejoin asks again). Otherwise ONE pcall(player.IsInGroupAsync, player, GroupId):
--       true  -> DataService.MarkTrove(player, "Group", reward) and, in the same non-yielding step, AddCash + AddTokens
--                (the raw amounts: never through Multipliers), Claimed:Fire, the reward toast, TroveState (Done)
--       false -> this visit is Checked; the "Rejoin the game" toast
--       error -> Unavailable ("Roblox is busy, try again in a bit"); not counted as the visit's check (the next Open
--                clears it and JOIN shows again)
--   * Z10: IsInGroupAsync is NEVER called on join, spawn or Open, only inside Joined, at most once per server visit
--     (a call in flight blocks the next Joined); the distance, match and cooldown checks guard Open.
--   * Z11: the grant and the ask bit travel together in ONE save (MarkTrove's TroveGrants annotation): two servers that
--     both grant end with one grant in the store (DataService's union + twin rule); a failed save keeps grant and bit for
--     the orphan retry.
--   * PlayerRemoving clears the visit (a rejoin is a new visit).
--
-- Public API
--   TroveService.Init(lobbyInfo, deps)   deps = { DataService }
--   TroveService.Open(player) -> ok, state | reason
--   TroveService.Joined(player) -> ok, state | reason
--   TroveService.State(player) -> { GroupId, Preview = bool, Asks = { { Id = "Group", State, Reward = { Cash, Tokens } },
--                                    { Id = "Like" } } }
--                                 State: "Soon" (GroupId 0) | "Preview" (GroupId 0 under the StorePreview attribute) |
--                                 "Loading" | "Done" | "Checked" | "Unavailable" | "Open"
--   TroveService.Claimed   Util.Signal Fire(player, askId, reward) once an ask paid out on this server
--
-- Plain Lua 5.1-compatible syntax only. Nothing here yields between a check and its write.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local TroveService = {}
TroveService.Claimed = Util.Signal() -- Fire(player, askId, reward)

local REQUEST_GAP = 1 -- seconds between two TroveRequests of one player
local GROUP_ASK = "Group"
local TEXT = {
	Paid = "The Sky Trove paid you $%s and %s Cloud Tokens!",
	Checked = "Roblox says you're not in the group yet. Joined for real? Rejoin the game and open the Trove again!",
	Busy = "Roblox is busy, try again in a bit",
	Loading = "Your save is still loading",
	Soon = "Coming soon",
}

local S = {
	DS = nil,
	Info = nil, -- lobbyInfo.Shop.ItemShop
	Prompt = nil,
	Visits = {}, -- [player] = { Checked, Unavailable, Asking }
	LastOpen = {}, -- [player] = os.clock() of the last accepted Open
	LastRequest = {}, -- [player] = os.clock() of the last TroveRequest
	Started = false,
}
TroveService._S = S

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function cfg()
	return type(Config.Trove) == "table" and Config.Trove or {}
end

local function groupId()
	local id = tonumber(cfg().GroupId) or 0
	if id ~= id or id < 0 then
		return 0
	end
	return math.floor(id)
end

local function isLivePlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function attr(player, key)
	local name = Config.Attr and Config.Attr[key]
	if type(name) ~= "string" then
		return nil
	end
	return player:GetAttribute(name)
end

local function busy(player)
	local inBattle = attr(player, "InBattle")
	return attr(player, "InMatch") == true or (inBattle ~= nil and inBattle ~= false and inBattle ~= "")
end

local function fire(name, player, ...)
	local ok, remote = pcall(Remotes.Get, name)
	if ok and remote and isLivePlayer(player) then
		remote:FireClient(player, ...)
	end
end

local function notify(player, text, kind)
	fire("Notify", player, text, kind or "info", 4)
end

local function commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s
	while true do
		local k
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return out
end

-- the ask's config entry (Config.Trove.Asks), or nil
local function askDef(id)
	for _, a in ipairs(type(cfg().Asks) == "table" and cfg().Asks or {}) do
		if type(a) == "table" and a.Id == id then
			return a
		end
	end
	return nil
end

-- a whole-number copy of the Group ask's reward ({ Cash, Tokens }; no Gems by design)
local function groupReward()
	local def = askDef(GROUP_ASK)
	local r = def and type(def.Reward) == "table" and def.Reward or {}
	local cash = math.max(0, math.floor(tonumber(r.Cash) or 0))
	local tokens = math.max(0, math.floor(tonumber(r.Tokens) or 0))
	return { Cash = cash, Tokens = tokens }
end

local function visitOf(player)
	local v = S.Visits[player]
	if not v then
		v = { Checked = false, Unavailable = false, Asking = false }
		S.Visits[player] = v
	end
	return v
end

-- the stored asks ({ [askId] = true }) or nil while the save is not readable (loading, provisional, no field yet)
local function troveOf(player)
	local DS = S.DS
	if not DS or type(DS.GetTrove) ~= "function" or type(DS.MarkTrove) ~= "function" then
		return nil
	end
	if type(DS.IsProvisional) == "function" and DS.IsProvisional(player) then
		return nil
	end
	local ok, trove = pcall(DS.GetTrove, player)
	if ok and type(trove) == "table" then
		return trove
	end
	return nil
end

local function groupState(player)
	if groupId() == 0 then
		return (attr(player, "StorePreview") == true) and "Preview" or "Soon"
	end
	local trove = troveOf(player)
	if not trove then
		return "Loading"
	end
	if trove[GROUP_ASK] == true then
		return "Done"
	end
	local v = S.Visits[player]
	if v and v.Checked then
		return "Checked"
	end
	if v and v.Unavailable then
		return "Unavailable"
	end
	return "Open"
end

----------------------------------------------------------------------
-- public
----------------------------------------------------------------------
function TroveService.State(player)
	local asks = {}
	for _, a in ipairs(type(cfg().Asks) == "table" and cfg().Asks or {}) do
		if type(a) == "table" and type(a.Id) == "string" then
			if a.Id == GROUP_ASK then
				asks[#asks + 1] = { Id = GROUP_ASK, State = isLivePlayer(player) and groupState(player) or "Loading", Reward = groupReward() }
			else
				asks[#asks + 1] = { Id = a.Id }
			end
		end
	end
	return {
		GroupId = groupId(),
		Preview = isLivePlayer(player) and attr(player, "StorePreview") == true or false,
		Asks = asks,
	}
end

local function sendState(player)
	local state = TroveService.State(player)
	fire("TroveState", player, state)
	return state
end

function TroveService.Open(player)
	if not isLivePlayer(player) then
		return false, "Player unavailable"
	end
	if busy(player) then
		return false, "In a match"
	end
	local info = S.Info
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not info or typeof(info.Center) ~= "Vector3" or not root then
		return false, "Too far"
	end
	local reach = (tonumber(cfg().PromptRange) or 10) + (tonumber(cfg().Slack) or 6)
	if (root.Position - info.Center).Magnitude > reach then
		return false, "Too far"
	end
	local now = os.clock()
	local last = S.LastOpen[player]
	if last and now - last < (tonumber(cfg().Cooldown) or 5) then
		return false, "Too fast"
	end
	S.LastOpen[player] = now
	local v = S.Visits[player]
	if v then
		v.Unavailable = false -- a new look at the chest: JOIN may ask Roblox again after an error
	end
	fire("OpenPanel", player, "Trove")
	return true, sendState(player)
end

function TroveService.Joined(player)
	if not isLivePlayer(player) then
		return false, "Player unavailable"
	end
	local now = os.clock()
	local last = S.LastRequest[player]
	if last and now - last < REQUEST_GAP then
		return false, "Too fast"
	end
	S.LastRequest[player] = now
	if attr(player, "InMatch") == true then
		return false, "In a match"
	end
	local gid = groupId()
	if gid == 0 then
		sendState(player)
		return false, TEXT.Soon
	end
	local trove = troveOf(player)
	if not trove then
		sendState(player)
		return false, TEXT.Loading
	end
	if trove[GROUP_ASK] == true then
		sendState(player)
		return false, "Done" -- a set ask refuses silently
	end
	local v = visitOf(player)
	if v.Checked then
		notify(player, TEXT.Checked, "bad")
		sendState(player)
		return false, TEXT.Checked
	end
	if v.Asking then
		return false, "Too fast"
	end
	v.Asking = true
	local ok, member = pcall(player.IsInGroupAsync, player, gid)
	v.Asking = false
	if not isLivePlayer(player) or S.Visits[player] ~= v then
		return false, "Player unavailable"
	end
	if not ok then
		v.Unavailable = true
		notify(player, TEXT.Busy, "bad")
		sendState(player)
		return false, TEXT.Busy
	end
	if member ~= true then
		v.Checked = true
		notify(player, TEXT.Checked, "bad")
		sendState(player)
		return false, TEXT.Checked
	end
	v.Unavailable = false
	-- the grant: the ask bit + its grant record, then the currencies, in one non-yielding step
	local now2 = troveOf(player)
	if not now2 then
		sendState(player)
		return false, TEXT.Loading
	end
	if now2[GROUP_ASK] == true then
		sendState(player)
		return false, "Done"
	end
	local reward = groupReward()
	local DS = S.DS
	local okMark, marked = pcall(DS.MarkTrove, player, GROUP_ASK, { Cash = reward.Cash, Tokens = reward.Tokens })
	if not okMark or marked ~= true then
		sendState(player)
		return false, TEXT.Loading
	end
	if reward.Cash > 0 then
		DS.AddCash(player, reward.Cash)
	end
	if reward.Tokens > 0 then
		DS.AddTokens(player, reward.Tokens)
	end
	TroveService.Claimed:Fire(player, GROUP_ASK, reward)
	notify(player, string.format(TEXT.Paid, commas(reward.Cash), commas(reward.Tokens)), "good")
	return true, sendState(player)
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
local function makePrompt(part)
	local old = part:FindFirstChild("TrovePrompt")
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TrovePrompt"
	prompt.ObjectText = "Sky Trove"
	prompt.ActionText = "Open"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = tonumber(cfg().PromptRange) or 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(TroveService.Open, player)
		if not ok then
			warn("[TroveService] Open failed: " .. tostring(err))
		end
	end)
	return prompt
end

function TroveService.Init(lobbyInfo, deps)
	deps = type(deps) == "table" and deps or {}
	S.DS = deps.DataService or S.DS
	local shop = type(lobbyInfo) == "table" and lobbyInfo.Shop or nil
	S.Info = type(shop) == "table" and type(shop.ItemShop) == "table" and shop.ItemShop or nil
	local part = S.Info and S.Info.PromptPart
	if typeof(part) == "Instance" and part:IsA("BasePart") then
		S.Prompt = makePrompt(part)
	else
		warn("[TroveService] no Sky Trove PromptPart in lobbyInfo.Shop.ItemShop: the chest has no prompt")
	end
	if S.Started then
		return
	end
	S.Started = true
	local okRemote, remote = pcall(Remotes.Get, "TroveRequest")
	if okRemote and remote then
		remote.OnServerEvent:Connect(function(player, action)
			if action ~= "Joined" then
				return -- junk: nothing, no answer
			end
			local ok, err = pcall(TroveService.Joined, player)
			if not ok then
				warn("[TroveService] Joined failed: " .. tostring(err))
			end
		end)
	else
		warn("[TroveService] TroveRequest remote is unavailable: " .. tostring(remote))
	end
	Players.PlayerRemoving:Connect(function(player)
		S.Visits[player] = nil
		S.LastOpen[player] = nil
		S.LastRequest[player] = nil
	end)
end

return TroveService
