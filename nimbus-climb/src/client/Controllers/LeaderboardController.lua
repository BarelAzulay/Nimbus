-- LeaderboardController (client, lobby-shop Task 24; spec 5.10 "Client", pages per section 15): the lobby board's face.
--
--   LeaderboardController.Init()
--   LeaderboardController.Page() -> stat         the page on the board ("Trophies" | "Pets" | "Ring": Config.Leaderboard.Pages)
--   LeaderboardController.SetPage(stat)          the tap path: shows that page and restarts the turn count
--   LeaderboardController.State() -> payload | nil   the last LeaderboardState (nil before the first)
--
-- A SurfaceGui "LobbyLeaderboard" in the PlayerGui (so its tabs take taps) adorned to the Face of the workspace model
-- LobbyLeaderboard (server/Services/LobbyBoardBuilder tags that Face Config.Tags.LeaderboardFace; found through
-- CollectionService: at Init and whenever a tagged Face arrives, so a rebuilt or streamed-in board re-adorns the same
-- SurfaceGui; the newest board wins; review round 1: no handler on every instance added to the workspace). It is built
-- when the first board is found, so a world without the board gets no SurfaceGui. Face Front,
-- PixelsPerStud 50: the 16 x 13 stud face is an 800 x 650 px canvas (CanvasSize says the same for tools; Roblox ignores
-- it under PixelsPerStud), MaxDistance 80, ResetOnSpawn false, LightInfluence 0. Layout (the pitch mock-up boardA):
--   Board > IconL / IconR (the page's glyph), Title (50 px, Config.Leaderboard.Titles[stat]), Tabs > Tab_<stat> (one
--   TextButton per page, its Label), Scope ("All players . all time" / "This server only"), Rows > Row1..10 (38 px each:
--   Rank badge, Head 34 px headshot, Name, Value; ranks 1-3 gold, silver, bronze; my own row green), YouRow
--   ("You . 1,240 . #37" / "You . 1,240 . not in the top 100" / "You . ..." while my value is unknown), Footer
--   ("Refreshes in m:ss . tap a tab, or it turns in 0:ss", from NextAt on workspace:GetServerTimeNow()), Status
--   ("Loading scores..." before the first state / "No scores yet. Be the first!" for an empty page).
-- Every text is at least 30 px (0.6 stud: the project's world-text floor); values have commas, Theme.ShortNumber from 1e6.
-- The page turns by itself every Config.Leaderboard.TurnSeconds; a tap (SetPage) restarts that count. One 4 Hz task
-- turns the page, counts the footer down and drops a Face that left the workspace for any tagged one still there (no
-- Heartbeat).
-- Headshots: Players:GetUserThumbnailAsync(id, HeadShot, Size48x48) in a deferred pcall'd task, cached per user for the
-- session (a failed one stays blank: the round placeholder shows). The client sends nothing.
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))

local LocalPlayer = Players.LocalPlayer

local LeaderboardController = {}

local rgb = Color3.fromRGB
local K = {
	MODEL = "LobbyLeaderboard", -- the workspace board model and the PlayerGui SurfaceGui
	PPS = 50, -- px per stud: 16 x 13 studs -> 800 x 650 px
	W = 800,
	H = 650,
	MAX_DISTANCE = 80,
	PAD = 14,
	TITLE_Y = 4, TITLE_H = 56, TITLE_TEXT = 50, ICON = 44, ICON_BOX = 56,
	TABS_Y = 64, TABS_H = 46, TAB_GAP = 8,
	SCOPE_Y = 114, SCOPE_H = 34,
	ROWS_Y = 150, ROW_H = 38, ROWS = 10,
	BADGE = 34, -- the rank badge and the headshot (px)
	NAME_X = 90, NAME_W = 450, VALUE_W = 226,
	YOU_Y = 534, YOU_H = 40,
	FOOT_Y = 578, FOOT_H = 66,
	TEXT = 30, -- the floor: every text on the board
	VALUE_TEXT = 32,
	STATUS_TEXT = 32,
	SHORT_FROM = 1e6, -- Theme.ShortNumber from here, commas below
	TICK = 0.25,
	HEAD_CACHE = 200, -- headshots kept before the cache starts over
	ICONS = { Trophies = "Stats", Pets = "Pets", Ring = "Ring" }, -- NeonKit glyph ids (trophy, paw prints, crown)
	GOLD = rgb(255, 211, 77),
	MUTED = rgb(201, 211, 242),
	TOP = rgb(36, 50, 122),
	BOTTOM = rgb(20, 27, 72),
	TAB_OFF = rgb(46, 62, 140),
	MEDALS = { rgb(255, 201, 60), rgb(217, 224, 238), rgb(224, 149, 90) },
	ME = rgb(42, 106, 58),
	ME_RING = rgb(141, 255, 166),
	HEAD_BG = rgb(70, 90, 160),
}
LeaderboardController.K = K

local S = {
	Gui = nil, -- the SurfaceGui (built at the first board)
	Face = nil, -- the adorned Face part
	Ui = nil, -- { Board, Title, IconL, IconR, Tabs = { [stat] = button }, Scope, Rows = { { Frame, Rank, Head, Name, Value, UserId } }, RowsFrame, You, Footer, Status }
	State = nil, -- the last LeaderboardState
	Page = nil,
	TurnAt = 0, -- os.clock() of the next turn
	Icon = nil, -- the page whose glyph the title shows
	Heads = {}, -- [userId] = content | "" (failed) | false (asking)
	HeadCount = 0,
	Warned = {},
	Started = false,
}
LeaderboardController._S = S

local function safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not S.Warned[key] then
		S.Warned[key] = true
		warn("[LeaderboardController] " .. key .. ": " .. tostring(err))
	end
	return ok
end

local function cfg()
	return type(Config.Leaderboard) == "table" and Config.Leaderboard or {}
end

local function pages()
	local list = cfg().Pages
	return type(list) == "table" and list or {}
end

local function turnSeconds()
	return math.max(1, tonumber(cfg().TurnSeconds) or 15)
end

-- "m:ss", counted up to the next whole second (a millisecond of slack: 138.4 - 123.4 is 15.000000000000014, not 16 s)
local function mmss(seconds)
	local s = math.max(0, math.ceil((tonumber(seconds) or 0) - 0.001))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function label(parent, name, text, role, size, props)
	props = props or {}
	props.Name = name
	local l = Theme.Label(text, role, { Size = size, Color = props.TextColor3, Stroke = props.TextStrokeTransparency, Props = props })
	l.Parent = parent
	return l
end

local function frame(parent, name, pos, size, color, alpha)
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color or Theme.Colors.White
	f.BackgroundTransparency = alpha or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

----------------------------------------------------------------------
-- the face
----------------------------------------------------------------------
local function setIcons(stat)
	local ui = S.Ui
	if not ui or S.Icon == stat then
		return
	end
	S.Icon = stat
	for _, holder in ipairs({ ui.IconL, ui.IconR }) do
		holder:ClearAllChildren()
		NeonKit.Icon(holder, K.ICONS[stat] or "Stats", K.ICON)
	end
end

local function buildRow(parent, i)
	local row = frame(parent, "Row" .. i, UDim2.fromOffset(10, (i - 1) * K.ROW_H + 1), UDim2.fromOffset(K.W - 20, K.ROW_H - 2), Theme.Colors.White, 0.92)
	Theme.Corner(row, UDim.new(0, 8))
	local medal = K.MEDALS[i]
	local rank = label(row, "Rank", tostring(i), "Display", K.TEXT, {
		Position = UDim2.fromOffset(6, 1), Size = UDim2.fromOffset(K.BADGE, K.BADGE),
		BackgroundTransparency = medal and 0 or 0.86, BackgroundColor3 = medal or Theme.Colors.White,
		TextColor3 = medal and Theme.Colors.Navy or Theme.Colors.White, TextStrokeTransparency = medal and 1 or 0.4,
	})
	Theme.Corner(rank, UDim.new(0.5, 0))
	local head = Instance.new("ImageLabel")
	head.Name = "Head"
	head.Position = UDim2.fromOffset(12 + K.BADGE, 1)
	head.Size = UDim2.fromOffset(K.BADGE, K.BADGE)
	head.BackgroundColor3 = K.HEAD_BG
	head.BorderSizePixel = 0
	head.Image = ""
	head.ScaleType = Enum.ScaleType.Crop
	Theme.Corner(head, UDim.new(0.5, 0))
	head.Parent = row
	local name = label(row, "Name", "", "Body", K.TEXT, {
		Position = UDim2.fromOffset(K.NAME_X, 0), Size = UDim2.fromOffset(K.NAME_W, K.ROW_H - 2),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local value = label(row, "Value", "", "Display", K.VALUE_TEXT, {
		Position = UDim2.fromOffset(K.W - 20 - 12 - K.VALUE_W, 0), Size = UDim2.fromOffset(K.VALUE_W, K.ROW_H - 2),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	return { Frame = row, Rank = rank, Head = head, Name = name, Value = value, UserId = nil }
end

local function build()
	local gui = Instance.new("SurfaceGui")
	gui.Name = K.MODEL
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = K.PPS
	gui.CanvasSize = Vector2.new(K.W, K.H)
	pcall(function()
		gui.MaxDistance = K.MAX_DISTANCE -- (a pcall: the board still builds where the engine lacks the member)
	end)
	gui.ResetOnSpawn = false
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local ui = { Tabs = {}, Rows = {} }
	local board = frame(gui, "Board", UDim2.fromOffset(0, 0), UDim2.fromOffset(K.W, K.H), Theme.Colors.White, 0)
	Theme.Gradient(board, K.TOP, K.BOTTOM, 90)
	Theme.Corner(board, UDim.new(0, 10))
	Theme.Stroke(board, Theme.Colors.Navy, 3, 0)
	ui.Board = board

	ui.IconL = frame(board, "IconL", UDim2.fromOffset(K.PAD, K.TITLE_Y), UDim2.fromOffset(K.ICON_BOX, K.ICON_BOX), nil, 1)
	ui.IconR = frame(board, "IconR", UDim2.fromOffset(K.W - K.PAD - K.ICON_BOX, K.TITLE_Y), UDim2.fromOffset(K.ICON_BOX, K.ICON_BOX), nil, 1)
	ui.Title = label(board, "Title", "", "Heading", K.TITLE_TEXT, {
		Position = UDim2.fromOffset(K.PAD + K.ICON_BOX + 8, K.TITLE_Y), Size = UDim2.fromOffset(K.W - 2 * (K.PAD + K.ICON_BOX + 8), K.TITLE_H),
		TextColor3 = K.GOLD, TextStrokeTransparency = 0.2,
	})

	local tabs = frame(board, "Tabs", UDim2.fromOffset(K.PAD, K.TABS_Y), UDim2.fromOffset(K.W - 2 * K.PAD, K.TABS_H), nil, 1)
	local list = pages()
	local n = math.max(1, #list)
	local tw = math.floor((K.W - 2 * K.PAD - (n - 1) * K.TAB_GAP) / n)
	for i, stat in ipairs(list) do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. stat
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.Position = UDim2.fromOffset((i - 1) * (tw + K.TAB_GAP), 0)
		b.Size = UDim2.fromOffset(tw, K.TABS_H)
		b.Text = tostring((type(cfg().Labels) == "table" and cfg().Labels[stat]) or stat)
		Theme.Style(b, "Button", { Size = K.TEXT })
		Theme.Corner(b, UDim.new(0, 10))
		b.Parent = tabs
		b.Activated:Connect(function()
			safe("tap", LeaderboardController.SetPage, stat)
		end)
		ui.Tabs[stat] = b
	end

	ui.Scope = label(board, "Scope", "", "Body", K.TEXT, {
		Position = UDim2.fromOffset(K.PAD, K.SCOPE_Y), Size = UDim2.fromOffset(K.W - 2 * K.PAD, K.SCOPE_H), TextColor3 = K.MUTED,
	})
	ui.RowsFrame = frame(board, "Rows", UDim2.fromOffset(0, K.ROWS_Y), UDim2.fromOffset(K.W, K.ROWS * K.ROW_H), nil, 1)
	for i = 1, K.ROWS do
		ui.Rows[i] = buildRow(ui.RowsFrame, i)
	end
	ui.Status = label(board, "Status", "", "Heading", K.STATUS_TEXT, {
		Position = UDim2.fromOffset(K.PAD, K.ROWS_Y), Size = UDim2.fromOffset(K.W - 2 * K.PAD, K.ROWS * K.ROW_H), TextWrapped = true,
	})
	ui.You = label(board, "YouRow", "", "Heading", K.TEXT, {
		Position = UDim2.fromOffset(10, K.YOU_Y), Size = UDim2.fromOffset(K.W - 20, K.YOU_H),
		BackgroundTransparency = 0, BackgroundColor3 = K.ME, TextXAlignment = Enum.TextXAlignment.Left,
	})
	Theme.Corner(ui.You, UDim.new(0, 8))
	Theme.Stroke(ui.You, K.ME_RING, 2, 0)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = ui.You
	ui.Footer = label(board, "Footer", "", "Body", K.TEXT, {
		Position = UDim2.fromOffset(K.PAD, K.FOOT_Y), Size = UDim2.fromOffset(K.W - 2 * K.PAD, K.FOOT_H), TextColor3 = K.MUTED, TextWrapped = true,
	})

	S.Gui, S.Ui, S.Icon = gui, ui, nil
	gui.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

----------------------------------------------------------------------
-- headshots
----------------------------------------------------------------------
local applyHeads

-- the cached headshot of a user ("" until it arrives or when it failed); asks once per user, in a deferred task
local function headOf(userId)
	local h = S.Heads[userId]
	if type(h) == "string" then
		return h
	end
	if h == nil and type(userId) == "number" and userId > 0 then
		if S.HeadCount >= K.HEAD_CACHE then
			S.Heads, S.HeadCount = {}, 0
		end
		local heads = S.Heads
		heads[userId] = false
		S.HeadCount = S.HeadCount + 1
		task.defer(function()
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			end)
			heads[userId] = (ok and type(content) == "string") and content or ""
			safe("heads", applyHeads)
		end)
	end
	return ""
end

applyHeads = function()
	for _, r in ipairs(S.Ui and S.Ui.Rows or {}) do
		local image = r.UserId and headOf(r.UserId) or ""
		if r.Head.Image ~= image then
			r.Head.Image = image
		end
	end
end

----------------------------------------------------------------------
-- rendering
----------------------------------------------------------------------
local function footer()
	local ui = S.Ui
	if not ui then
		return
	end
	local turn = "tap a tab, or it turns in " .. mmss(S.TurnAt - os.clock())
	local nextAt = S.State and tonumber(S.State.NextAt)
	local text
	if not nextAt then
		text = "Tap a tab, or it turns in " .. mmss(S.TurnAt - os.clock())
	elseif nextAt - Workspace:GetServerTimeNow() > 0 then
		text = "Refreshes in " .. mmss(nextAt - Workspace:GetServerTimeNow()) .. " \194\183 " .. turn
	else
		text = "Refreshing... \194\183 " .. turn
	end
	if ui.Footer.Text ~= text then
		ui.Footer.Text = text
	end
end

local function render()
	local ui = S.Ui
	if not ui then
		return
	end
	local stat = LeaderboardController.Page()
	local c = cfg()
	ui.Title.Text = tostring((type(c.Titles) == "table" and c.Titles[stat]) or string.upper(tostring(stat)))
	setIcons(stat)
	for key, b in pairs(ui.Tabs) do
		local on = key == stat
		b.BackgroundColor3 = on and K.GOLD or K.TAB_OFF
		b.TextColor3 = on and Theme.Colors.Navy or Theme.Colors.White
		b.TextStrokeTransparency = on and 1 or 0.4
	end
	local state = S.State
	ui.Scope.Text = (state and state.Scope == "Server") and "This server only" or "All players \194\183 all time"
	local data = state and type(state.Stats) == "table" and state.Stats[stat] or nil
	local top = type(data) == "table" and type(data.Top) == "table" and data.Top or {}
	local me = LocalPlayer and LocalPlayer.UserId
	for i, r in ipairs(ui.Rows) do
		local e = type(top[i]) == "table" and top[i] or nil
		r.Frame.Visible = e ~= nil
		r.UserId = e and tonumber(e.UserId) or nil
		if e then
			r.Name.Text = tostring(e.Name or "Player")
			r.Value.Text = Theme.ShortNumber(tonumber(e.Value) or 0, K.SHORT_FROM)
			local mine = r.UserId ~= nil and r.UserId == me
			r.Frame.BackgroundColor3 = mine and K.ME or (i <= 3 and K.GOLD or Theme.Colors.White)
			r.Frame.BackgroundTransparency = mine and 0 or (i <= 3 and 0.88 or (i % 2 == 0 and 0.96 or 0.92))
		end
	end
	applyHeads()
	ui.Status.Text = (state == nil) and "Loading scores..." or "No scores yet. Be the first!"
	ui.Status.Visible = state == nil or type(top[1]) ~= "table"
	ui.RowsFrame.Visible = not ui.Status.Visible
	local you = type(data) == "table" and type(data.You) == "table" and data.You or {}
	local value, rank = tonumber(you.Value), tonumber(you.Rank)
	if not value then
		ui.You.Text = "You \194\183 ..."
	elseif rank then
		ui.You.Text = "You \194\183 " .. Theme.ShortNumber(value, K.SHORT_FROM) .. " \194\183 #" .. math.floor(rank)
	else
		ui.You.Text = "You \194\183 " .. Theme.ShortNumber(value, K.SHORT_FROM) .. " \194\183 not in the top " .. tostring(tonumber(c.ReadSize) or 100)
	end
	footer()
end

----------------------------------------------------------------------
-- the board in the workspace
----------------------------------------------------------------------
local function valid(face)
	return face ~= nil and face.Parent ~= nil and face:IsDescendantOf(Workspace)
end

local function adopt(face)
	if not (face and face:IsA("BasePart") and face:IsDescendantOf(Workspace)) then
		return
	end
	S.Face = face
	if not S.Gui then
		build()
		render()
	end
	S.Gui.Adornee = face
end

-- the board's Face carries Config.Tags.LeaderboardFace (LobbyBoardBuilder; review round 1: a CollectionService tag, not
-- a handler on every instance added to the workspace): a tagged Face arriving (a rebuild, streaming) is adopted, the
-- newest board wins; a Face that left is replaced by any tagged Face still in the workspace (the tick)
local function faceTag()
	return type(Config.Tags) == "table" and Config.Tags.LeaderboardFace or "NC_LeaderboardFace"
end

local function adoptAnyTagged()
	local tagged = game:GetService("CollectionService"):GetTagged(faceTag())
	for i = #tagged, 1, -1 do
		if valid(tagged[i]) and tagged[i]:IsA("BasePart") then
			adopt(tagged[i])
			return
		end
	end
end

local function tick()
	if S.Face and not valid(S.Face) then
		S.Face = nil
		if S.Gui then
			S.Gui.Adornee = nil
		end
		safe("find", adoptAnyTagged)
	end
	if S.Gui and not S.Gui.Parent then
		S.Gui.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	local list = pages()
	if #list > 1 and os.clock() >= S.TurnAt then
		local cur = LeaderboardController.Page()
		local idx = 1
		for i, stat in ipairs(list) do
			if stat == cur then
				idx = i
			end
		end
		S.Page = list[idx % #list + 1]
		S.TurnAt = os.clock() + turnSeconds()
		render()
	else
		footer()
	end
end

----------------------------------------------------------------------
-- public
----------------------------------------------------------------------
function LeaderboardController.Page()
	local list = pages()
	for _, stat in ipairs(list) do
		if stat == S.Page then
			return stat
		end
	end
	return list[1]
end

function LeaderboardController.SetPage(stat)
	for _, s in ipairs(pages()) do
		if s == stat then
			S.Page = stat
			S.TurnAt = os.clock() + turnSeconds()
			render()
			return
		end
	end
end

function LeaderboardController.State()
	return S.State
end

function LeaderboardController.Init()
	if S.Started then
		return
	end
	S.Started = true
	S.Page = pages()[1]
	S.TurnAt = os.clock() + turnSeconds()
	game:GetService("CollectionService"):GetInstanceAddedSignal(faceTag()):Connect(function(inst)
		safe("added", adopt, inst)
	end)
	safe("find", adoptAnyTagged)
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, "LeaderboardState")
		if ok and remote then
			remote.OnClientEvent:Connect(function(state)
				if type(state) == "table" then
					S.State = state
					safe("render", render)
				end
			end)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(K.TICK)
			safe("tick", tick)
		end
	end)
end

return LeaderboardController
