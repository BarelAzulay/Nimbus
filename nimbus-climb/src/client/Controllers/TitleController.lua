-- TitleController (client, lobby-shop Task 19; spec 16.6 "Client"): the rank and Creator titles above the head.
--
--   TitleController.Init()
--   TitleController.TagOf(player) -> BillboardGui | nil   that player's TitleTag (nil without a title or a head)
--   TitleController.SetCrown(player, on)                  VipController's crown rule for a titled player: the crown is
--                                                          drawn inside the TitleTag (a pixel gap, never a stud gap)
--
-- Per player: the Title / TitleRank attributes (only the server writes them: LeaderboardService), CharacterAdded and
-- InBattle. A BillboardGui "TitleTag" on the head (Adornee = Head, 240 x 36 px, 240 x 74 with the crown slot, MaxDistance
-- 90, not on top, LightInfluence 0) > Plate (the text's width) > Label (22 px, 24 for Creator). Its height above Roblox's
-- name is set in pixels: StudsOffset (0, 2.0, 0) (about where Roblox anchors the name) and SizeOffset (0, 0.5 + 26 / H),
-- so the plate's bottom stays 26 px above that point at any distance (the tag, the crown and Roblox's name are all
-- constant-pixel billboards: a stud gap shrinks on screen with distance and lets them slide into each other).
-- (kit-b U9-3, finding 15) the tag is a kit B sign tag, one colour by role, no glow, gloss or animation: the Plate a flat
-- opaque face with its darker lip along the bottom and a 2 px wood edge, square (CloudUI.SignBlock); the Label FredokaOne
-- (Nameplate) in the ink that reads on that face, centred above the lip, no outline (the face is opaque). The rainbow, the
-- gradients and the navy glass plate went.
--   Top10    "TOP 10 \194\183 #N": the gold block (CloudUI.SignLooks.Selected), brown letters.
--   Top100   "TOP 100": the stone block (Stone), brown letters.
--   Creator  "CREATOR", 24 px: the navy plank with gold letters (Navy), the game's own sign voice.
--   The crown (SetCrown on): VipController.Crown (the gold pixel crown on its wood lip) as "Crown", 34 x 34 px, centred,
--   4 px above the Plate.
-- Hidden while that player is InBattle (the battle scene); for the local player also while the camera is within 2 studs
-- of the head (first person). One 4 Hz task does that check (local player only) and once a second rebuilds a titled
-- player's tag whose head changed (a respawn the CharacterAdded wait missed, a character streamed out and back). No
-- Heartbeat, no per-frame Lua, no tween. A tag and the connections go when the title clears, on a respawn (rebuilt on the
-- new head) or when the player leaves. Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
-- (kit-b U9-3) the crown's look lives with the VIP pass (VipController.Crown); VipController requires this module only
-- lazily, from a call, so there is no loop at load
local VipController = require(script.Parent:WaitForChild("VipController"))

local TitleController = {}

local K = {
	NAME = "TitleTag",
	WIDTH = 240, -- the billboard (px)
	PLATE_H = 36,
	CROWN = 34, -- the crown slot (px)
	CROWN_GAP = 4, -- the crown's bottom to the plate's top (px)
	ABOVE = 26, -- the plate's bottom above the anchor (px; Roblox's name is about 20 px tall)
	STUDS = 2.0, -- the anchor above the head (about where Roblox draws the name; tuned in Studio, in studs only)
	MAX_DISTANCE = 90,
	PAD = 12, -- px each side of the text inside the plate
	TEXT = 22,
	CREATOR_TEXT = 24,
	EDGE = 2, -- (kit-b U9-3) the plate's wood edge (px)
	LIP = 4, -- ... and its darker lip along the bottom (px)
	-- (kit-b U9-3) each title's kit B look (CloudUI.SignLooks): the gold block, the stone block, the navy plank
	LOOK = { Top10 = "Selected", Top100 = "Stone", Creator = "Navy" },
	TICK = 0.25, -- the 4 Hz check
	SWEEP = 4, -- ticks between two head sweeps (1 s)
	NEAR = 2, -- studs: the camera this close to the local head = first person
	TAGS = { Creator = "CREATOR", Top10 = "TOP 10", Top100 = "TOP 100" }, -- when Config has no RankTitles.Tag
}
TitleController.K = K

local S = {
	Tags = {}, -- [player] = { Gui, Plate, Label, Head, Key }
	Crown = {}, -- [player] = true while VipController wants the crown drawn in that player's tag
	Watch = {}, -- [player] = { connections }
	FirstPerson = false, -- the camera is at the local player's head
	Warned = {},
	Started = false,
}
TitleController._S = S

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not S.Warned[key] then
		S.Warned[key] = true
		warn("[TitleController] " .. key .. ": " .. tostring(err))
	end
	return ok
end

-- "Creator" | "Top10" | "Top100" | nil (anything else the attribute could hold draws nothing)
local function kindOf(player)
	local kind = player:GetAttribute(Config.Attr.Title or "Title")
	local rt = Config.Leaderboard and Config.Leaderboard.RankTitles
	local tags = (rt and rt.Tag) or K.TAGS
	if type(kind) == "string" and tags[kind] and K.LOOK[kind] then
		return kind
	end
	return nil
end

local function textOf(kind, player)
	local rt = Config.Leaderboard and Config.Leaderboard.RankTitles
	local text = tostring(((rt and rt.Tag) or K.TAGS)[kind])
	if kind == "Top10" then
		local rank = tonumber(player:GetAttribute(Config.Attr.TitleRank or "TitleRank"))
		if rank and rank >= 1 then
			text = text .. " \194\183 #" .. math.floor(rank)
		end
	end
	return text
end

local function headOf(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function shown(player)
	if player:GetAttribute(Config.Attr.InBattle or "InBattle") ~= nil then
		return false
	end
	return not (player == Players.LocalPlayer and S.FirstPerson)
end

local function drop(player)
	local t = S.Tags[player]
	S.Tags[player] = nil
	if t then
		t.Gui:Destroy()
	end
end

local function build(player, head, kind, text, crown)
	local H = crown and (K.CROWN + K.CROWN_GAP + K.PLATE_H) or K.PLATE_H
	local gui = Instance.new("BillboardGui")
	gui.Name = K.NAME
	gui.Size = UDim2.fromOffset(K.WIDTH, H)
	gui.StudsOffset = Vector3.new(0, K.STUDS, 0)
	gui.SizeOffset = Vector2.new(0, 0.5 + K.ABOVE / H)
	gui.MaxDistance = K.MAX_DISTANCE
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Adornee = head

	local size = (kind == "Creator") and K.CREATOR_TEXT or K.TEXT
	local textW = math.ceil(Theme.Measure(text, "Nameplate", size, 4096).X)
	local plateW = math.min(K.WIDTH, textW + 2 * K.PAD)
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.fromScale(0.5, 1)
	plate.Size = UDim2.fromOffset(plateW, K.PLATE_H)
	plate.BorderSizePixel = 0
	-- (kit-b U9-3) the flat block: its face, the wood edge, the lip
	local look = CloudUI.SignLooks[K.LOOK[kind]]
	CloudUI.SignBlock(plate, K.LOOK[kind], { EdgePx = K.EDGE, LipPx = K.LIP, Pad = false })
	plate.Parent = gui

	local label = Theme.Label(text, "Nameplate", {
		Size = size,
		Color = look.Text,
		Props = {
			Name = "Label",
			Size = UDim2.new(1, 0, 1, -K.LIP), -- centred over the lip
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		},
	})
	label.Parent = plate

	if crown then
		local holder = VipController.Crown(gui, K.CROWN)
		holder.Name = "Crown"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.fromScale(0.5, 0)
	end

	gui.Enabled = shown(player)
	gui.Parent = head
	return { Gui = gui, Plate = plate, Label = label, Head = head }
end

-- builds, rebuilds (kind, text, crown or head changed), shows / hides or removes that player's tag; a no-op otherwise
local function refresh(player)
	if not player or not player.Parent then
		return
	end
	local kind = kindOf(player)
	local head = kind and headOf(player)
	if not head then
		drop(player)
		if not kind then
			S.Crown[player] = nil -- VipController sets it again when a title comes back
		end
		return
	end
	local text = textOf(kind, player)
	local crown = S.Crown[player] == true
	local key = kind .. "|" .. text .. "|" .. tostring(crown)
	local t = S.Tags[player]
	if not (t and t.Key == key and t.Head == head and t.Gui.Parent ~= nil) then
		drop(player)
		t = build(player, head, kind, text, crown)
		t.Key = key
		S.Tags[player] = t
	end
	local want = shown(player)
	if t.Gui.Enabled ~= want then
		t.Gui.Enabled = want
	end
end

-- the camera within K.NEAR studs of the local player's head (first person)
local function firstPerson()
	local camera = workspace.CurrentCamera
	local t = S.Tags[Players.LocalPlayer]
	local head = t and t.Head
	if not (camera and head and head.Parent) then
		return false
	end
	return (camera.CFrame.Position - head.Position).Magnitude < K.NEAR
end

local function unwatch(player)
	local conns = S.Watch[player]
	S.Watch[player] = nil
	for _, c in ipairs(conns or {}) do
		c:Disconnect()
	end
	drop(player)
	S.Crown[player] = nil
end

local function watch(player)
	if S.Watch[player] then
		return
	end
	local conns = {}
	S.Watch[player] = conns
	local attr = Config.Attr
	for _, name in ipairs({ attr.Title or "Title", attr.TitleRank or "TitleRank", attr.InBattle or "InBattle" }) do
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

local function tick(sweep)
	local fp = firstPerson()
	if fp ~= S.FirstPerson then
		S.FirstPerson = fp
		refresh(Players.LocalPlayer)
	end
	if sweep then
		for player in pairs(S.Watch) do
			if not player.Parent then
				unwatch(player)
			elseif kindOf(player) then
				local t = S.Tags[player]
				if not t or t.Gui.Parent == nil or t.Head ~= headOf(player) then
					refresh(player)
				end
			end
		end
	end
end

function TitleController.TagOf(player)
	local t = S.Tags[player]
	if t and t.Gui.Parent ~= nil then
		return t.Gui
	end
	return nil
end

function TitleController.SetCrown(player, on)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	on = on == true
	if (S.Crown[player] == true) == on then
		return
	end
	S.Crown[player] = on or nil
	safe("refresh", refresh, player)
end

function TitleController.Init()
	if S.Started then
		return
	end
	S.Started = true
	for _, player in ipairs(Players:GetPlayers()) do
		safe("watch", watch, player)
	end
	Players.PlayerAdded:Connect(function(player)
		safe("watch", watch, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		safe("unwatch", unwatch, player)
	end)
	task.spawn(function()
		local n = 0
		while true do
			task.wait(K.TICK)
			n = n + 1
			safe("tick", tick, n % K.SWEEP == 0)
		end
	end)
end

return TitleController
