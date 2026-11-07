-- TitleController (client, lobby-shop Task 19; spec 16.6 "Client"): the rank and Creator titles above the head.
--
--   TitleController.Init()
--   TitleController.TagOf(player) -> BillboardGui | nil   that player's TitleTag (nil without a title or a head)
--   TitleController.SetCrown(player, on)                  VipController's crown rule for a titled player: the crown is
--                                                          drawn inside the TitleTag (a pixel gap, never a stud gap)
--
-- Per player: the Title / TitleRank attributes (only the server writes them: LeaderboardService), CharacterAdded and
-- InBattle. A BillboardGui "TitleTag" on the head (Adornee = Head, 240 x 36 px, 240 x 74 with the crown slot, MaxDistance
-- 90, not on top, LightInfluence 0) > Plate (navy at 0.35, round corners, a 2 px stroke, the text's width) > Label
-- (Display, 22 px, 24 for Creator, white, a 2 px navy UIStroke) > Fill (UIGradient). Its height above Roblox's name is
-- set in pixels: StudsOffset (0, 2.0, 0) (about where Roblox anchors the name) and SizeOffset (0, 0.5 + 26 / H), so the
-- plate's bottom stays 26 px above that point at any distance (the tag, the crown and Roblox's name are all constant-pixel
-- billboards: a stud gap shrinks on screen with distance and lets them slide into each other).
--   Top10    "TOP 10 \194\183 #N": a rainbow, seven hues twice across 0..1, whose Fill.Offset tweens (0, 0) -> (-0.5, 0)
--            over 2.4 s, Linear, endless. A UIGradient holds its last colour past 1, so the Label is twice the text's
--            width and left-aligned (the Plate keeps the text's width): the text always sits in the half that maps to
--            one whole period, and the loop never snaps.
--   Top100   "TOP 100", a static gold gradient (Rotation 90).
--   Creator  "CREATOR", a static cyan -> violet gradient, 24 px.
--   The crown (SetCrown on): the VipCrown glyph as "Crown", 34 x 34 px, centred, 4 px above the Plate.
-- Hidden while that player is InBattle (the battle scene); for the local player also while the camera is within 2 studs
-- of the head (first person). One 4 Hz task does that check (local player only), follows the graphics level (Low pauses
-- the rainbows: a still rainbow; High plays them) and once a second rebuilds a titled player's tag whose head changed
-- (a respawn the CharacterAdded wait missed, a character streamed out and back). No Heartbeat, no per-frame Lua: at most
-- one engine tween per Top10 tag. A tag, its tween and the connections go when the title clears, on a respawn (rebuilt
-- on the new head) or when the player leaves. Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))

local Client = script.Parent.Parent
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))
local GraphicsQuality = require(Client:WaitForChild("GraphicsQuality"))

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
	PLATE_ALPHA = 0.35,
	CORNER = 10,
	PERIOD = 2.4, -- seconds of one rainbow loop
	TICK = 0.25, -- the 4 Hz check
	SWEEP = 4, -- ticks between two head sweeps (1 s)
	NEAR = 2, -- studs: the camera this close to the local head = first person
	TAGS = { Creator = "CREATOR", Top10 = "TOP 10", Top100 = "TOP 100" }, -- when Config has no RankTitles.Tag
}
TitleController.K = K

do
	local rgb = Color3.fromRGB
	-- red, orange, yellow, green, cyan, blue, violet, twice across 0..1 and red again at 1: one period per half
	local hues = { rgb(255, 84, 84), rgb(255, 156, 52), rgb(255, 228, 72), rgb(96, 222, 110), rgb(72, 214, 240), rgb(86, 128, 255), rgb(178, 100, 255) }
	local rainbow = {}
	for k = 0, 14 do
		rainbow[#rainbow + 1] = ColorSequenceKeypoint.new(k / 14, hues[(k % 7) + 1])
	end
	K.FILL = {
		Top10 = { ColorSequence.new(rainbow), 0 },
		Top100 = { ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 236, 150)), ColorSequenceKeypoint.new(0.5, rgb(242, 182, 68)), ColorSequenceKeypoint.new(1, rgb(196, 128, 32)) }), 90 },
		Creator = { ColorSequence.new(rgb(120, 220, 255), rgb(160, 120, 255)), 0 },
	}
	-- the plate's 2 px ring: the tag's own accent
	K.RING = { Top10 = rgb(255, 255, 255), Top100 = rgb(242, 182, 68), Creator = rgb(150, 160, 255) }
end

local S = {
	Tags = {}, -- [player] = { Gui, Plate, Label, Fill, Tween, Head, Key }
	Crown = {}, -- [player] = true while VipController wants the crown drawn in that player's tag
	Watch = {}, -- [player] = { connections }
	FirstPerson = false, -- the camera is at the local player's head
	Quality = "High", -- the graphics level the rainbows follow
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
	if type(kind) == "string" and tags[kind] and K.FILL[kind] then
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

local function quality()
	local ok, mode = pcall(GraphicsQuality.Effective)
	return (ok and mode == "Low") and "Low" or "High"
end

local function drop(player)
	local t = S.Tags[player]
	S.Tags[player] = nil
	if t then
		if t.Tween then
			t.Tween:Cancel()
		end
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
	local textW = math.ceil(TextService:GetTextSize(text, size, Theme.Fonts.Display, Vector2.new(4096, 1024)).X)
	local plateW = math.min(K.WIDTH, textW + 2 * K.PAD)
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.fromScale(0.5, 1)
	plate.Size = UDim2.fromOffset(plateW, K.PLATE_H)
	plate.BackgroundColor3 = Theme.Colors.Navy
	plate.BackgroundTransparency = K.PLATE_ALPHA
	plate.BorderSizePixel = 0
	Theme.Corner(plate, UDim.new(0, K.CORNER))
	Theme.Stroke(plate, K.RING[kind], 2, 0.15)
	plate.Parent = gui

	local rainbow = kind == "Top10"
	local label = Theme.Label(text, "Display", {
		Size = size,
		Stroke = 1,
		Props = {
			Name = "Label",
			Position = UDim2.fromOffset(math.floor((plateW - textW) / 2), 0),
			Size = UDim2.new(0, rainbow and 2 * textW or textW, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		},
	})
	Theme.TextOutline(label, 2, Theme.Colors.Navy, 0)
	local fill = Instance.new("UIGradient")
	fill.Name = "Fill"
	fill.Color = K.FILL[kind][1]
	fill.Rotation = K.FILL[kind][2]
	fill.Parent = label
	label.Parent = plate

	if crown then
		local icon = NeonKit.Icon(gui, "VipCrown", math.floor(K.CROWN * 0.8))
		icon.Name = "Crown"
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.fromScale(0.5, 0)
		icon.Size = UDim2.fromOffset(K.CROWN, K.CROWN)
		if icon:IsA("TextLabel") then
			icon.TextScaled = true
		end
	end

	local tween = nil
	if rainbow then
		tween = TweenService:Create(fill, TweenInfo.new(K.PERIOD, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(-0.5, 0) })
		if quality() ~= "Low" then
			tween:Play()
		end
	end
	gui.Enabled = shown(player)
	gui.Parent = head
	return { Gui = gui, Plate = plate, Label = label, Fill = fill, Tween = tween, Head = head }
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

local function setQuality(mode)
	if mode == S.Quality then
		return
	end
	S.Quality = mode
	for _, t in pairs(S.Tags) do
		if t.Tween then
			if mode == "Low" then
				t.Tween:Pause()
			else
				t.Tween:Play()
			end
		end
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
	setQuality(quality())
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
	S.Quality = quality()
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
