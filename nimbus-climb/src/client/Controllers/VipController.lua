-- VipController (client, store 2026-11-04; spec 5.1 "VIP" / 8 / 14): the VIP pass's two looks, both client-side only.
--
--   VipController.Init()
--   VipController.IsVip(player) -> bool   the player's replicated OwnedPasses csv has the entry "VIP"
--
-- Chat: TextChatService.OnIncomingMessage returns a TextChatMessageProperties whose PrefixText is
--   '<font color="#FFC440">[VIP]</font> <font color="#FFC440">' .. message.PrefixText .. '</font>' when the message's
--   TextSource.UserId is a VIP in this server; any other message (no source, a non-VIP, an error) is left as it is (nil).
--   Set under pcall: a place without the property (the legacy chat) keeps its nil callback.
-- Lobby crown: a BillboardGui "VipCrown" (the VipCrown glyph, 2.4 studs above the head, MaxDistance 60, client-only)
--   on every VIP character while Graphics is High; disabled while that player is InBattle / InMatch; every player's
--   OwnedPasses / InBattle / InMatch attributes and CharacterAdded are watched, and a 1 s sweep follows the graphics
--   level; the crown and the connections go when the player leaves.
-- Titled players (lobby-shop Task 19, spec 16.6): while a player has a Title (Top10 / Top100 / Creator) and the
--   TitleController is in the build, that player has no VipCrown billboard of its own: the same rule (VIP, Graphics High,
--   not InBattle / InMatch) goes to TitleController.SetCrown(player, on), which draws the crown inside the TitleTag 4 px
--   above the plate (a pixel gap that never closes far away). The Title attribute is watched too, so the crown moves
--   between the two the moment a title comes or goes.
--   VipController.TitleHost(player) -> the TitleController module while the player has a valid Title, else nil
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Client = script.Parent.Parent
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))
local GraphicsQuality = require(Client:WaitForChild("GraphicsQuality"))

local VipController = {}

local K = {
	PASS = "VIP",
	COLOR = "#FFC440",
	CROWN = "VipCrown",
	OFFSET = 2.4, -- studs above the head
	MAX_DISTANCE = 60,
	SIZE = 34, -- the billboard (px)
	SWEEP = 1, -- seconds between two graphics-level sweeps
	-- the chat callback's return class: creatable in Roblox (the TextChatService.OnIncomingMessage docs build one with
	-- Instance.new); tools/roblox-api.json predates it, so the name is kept here rather than as a literal at the call
	PROPS_CLASS = "TextChatMessageProperties",
}
VipController.K = K

local initialized = false
local Watch = {} -- [player] = { conns }
local warned = {}

local function warnOnce(key, err)
	if not warned[key] then
		warned[key] = true
		warn("[VipController] " .. key .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, err)
	end
	return ok
end

function VipController.IsVip(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	local csv = player:GetAttribute(Config.Attr.OwnedPasses or "OwnedPasses")
	if type(csv) ~= "string" then
		return false
	end
	for entry in csv:gmatch("[^,]+") do
		if (entry:gsub("^%s+", ""):gsub("%s+$", "")) == K.PASS then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Chat
----------------------------------------------------------------------
local function tagged(message)
	local source = message and message.TextSource
	local userId = source and tonumber(source.UserId)
	if not userId then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if not VipController.IsVip(player) then
		return nil
	end
	local props = Instance.new(K.PROPS_CLASS)
	local open = '<font color="' .. K.COLOR .. '">'
	props.PrefixText = open .. "[VIP]</font> " .. open .. tostring(message.PrefixText or "") .. "</font>"
	return props
end

local function onIncoming(message)
	local ok, props = pcall(tagged, message)
	if ok then
		return props
	end
	warnOnce("chat", props)
	return nil
end

----------------------------------------------------------------------
-- The lobby crown
----------------------------------------------------------------------
local function crownOf(character)
	return character and character:FindFirstChild(K.CROWN, true) or nil
end

-- the TitleController (required once, lazily: no top-level local) while this player has a valid Title; nil without a
-- Title or when the build has no TitleController (the crown is then this controller's own billboard, as before)
function VipController.TitleHost(player)
	local kind = player:GetAttribute(Config.Attr.Title or "Title")
	local rt = Config.Leaderboard and Config.Leaderboard.RankTitles
	if type(kind) ~= "string" or not (rt and rt.Tag and rt.Tag[kind]) then
		return nil
	end
	if VipController._titles == nil then
		local module = script.Parent and script.Parent:FindFirstChild("TitleController")
		local ok, mod = false, nil
		if module then
			ok, mod = pcall(require, module)
		end
		VipController._titles = (ok and type(mod) == "table" and type(mod.SetCrown) == "function") and mod or false
	end
	return VipController._titles or nil
end

local function wantsCrown(player)
	if not VipController.IsVip(player) or GraphicsQuality.Effective() == "Low" then
		return false
	end
	return player:GetAttribute(Config.Attr.InMatch) ~= true and player:GetAttribute(Config.Attr.InBattle or "InBattle") == nil
end

local function makeCrown(head)
	local bb = Instance.new("BillboardGui")
	bb.Name = K.CROWN
	bb.Size = UDim2.fromOffset(K.SIZE, K.SIZE)
	bb.StudsOffset = Vector3.new(0, K.OFFSET, 0)
	bb.MaxDistance = K.MAX_DISTANCE
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Adornee = head
	local icon = NeonKit.Icon(bb, "VipCrown", K.SIZE * 0.8)
	icon.Size = UDim2.fromScale(1, 1)
	icon.TextScaled = true
	bb.Parent = head
	return bb
end

local function refresh(player)
	if not player or not player.Parent then
		return
	end
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local crown = crownOf(character)
	local want = head ~= nil and wantsCrown(player)
	local titles = VipController.TitleHost(player)
	if titles then
		-- a titled player: the crown is drawn inside the TitleTag (lobby-shop Task 19)
		if crown then
			crown:Destroy()
		end
		titles.SetCrown(player, want)
		return
	end
	if want and not crown then
		crown = makeCrown(head)
	end
	if crown then
		if not VipController.IsVip(player) then
			crown:Destroy()
		else
			crown.Enabled = want
		end
	end
end

local function unwatch(player)
	local w = Watch[player]
	if w then
		for _, c in ipairs(w) do
			c:Disconnect()
		end
		Watch[player] = nil
	end
	local crown = crownOf(player.Character)
	if crown then
		crown:Destroy()
	end
end

local function watch(player)
	if Watch[player] then
		return
	end
	local conns = {}
	Watch[player] = conns
	local attr = Config.Attr
	for _, name in ipairs({ attr.OwnedPasses or "OwnedPasses", attr.InMatch, attr.InBattle or "InBattle", attr.Title or "Title" }) do
		conns[#conns + 1] = player:GetAttributeChangedSignal(name):Connect(function()
			safe("refresh", refresh, player)
		end)
	end
	conns[#conns + 1] = player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 5)
		safe("refresh", refresh, player)
	end)
	safe("refresh", refresh, player)
end

function VipController.Init()
	if initialized then
		return
	end
	initialized = true
	pcall(function()
		local chat = game:GetService("TextChatService")
		chat.OnIncomingMessage = onIncoming
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(function(player)
		safe("watch", watch, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		safe("unwatch", unwatch, player)
	end)
	task.spawn(function()
		while true do
			task.wait(K.SWEEP)
			for player in pairs(Watch) do
				if player.Parent then
					safe("sweep", refresh, player)
				else
					safe("unwatch", unwatch, player)
				end
			end
		end
	end)
end

return VipController
