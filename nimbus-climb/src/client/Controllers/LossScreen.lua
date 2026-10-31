-- LossScreen (client, team balance Task 6; spec 2026-10-31 s.7): a lost Ring run or Dungeon floor feels like progress. The result
-- screen shows what the team gained, with Fight again and Edit team. BattleController and DungeonController load it when a loss
-- arrives; a build without it keeps today's cards. It has no Init: the first Show builds it.
--
--   LossScreen.Show(payload) -> bool
--       payload = { Mode = "Ring" | "Dungeon", Title, Color, Sub, Pets = { { Key, PetId, Before, After, XpFrac, XpBefore }... },
--                   Lines = { { text, color }... }, Start = round | floor, OnFightAgain = fn | nil, OnClose = fn | nil }
--       Pets come from the server (Rewards.Pets / End.Pets): the client never computes a level.
--   LossScreen.Reopen()     the last payload again, without the sound or the pop (PetsController's ReturnTo { Window = "Loss" })
--   LossScreen.Hide()       closed and forgotten
--   LossScreen.IsOpen() -> bool
--
-- ScreenGui NimbusLoss (DisplayOrder 24: above the battle HUD's result card, below Notify 30), card LossCard (NeonKit.Card, centred
-- under the top bar; 16 px side gutters on a phone; every button >= 44 px): Title, Sub, PetRow1..3 (Face viewport, Name, Levels
-- "L1 -> L3" with a pop + one SoundFx "Reward" for the whole card, or "L1" + XpBar moving from XpBefore to XpFrac), Lines,
-- FightAgain ("Fight again", hidden without OnFightAgain), EditTeam ("Edit team"), CloseButton.
-- Fight again and Edit team wait for the return teleport: while Config.Attr.InBattle is still set (RETURN_DELAY after the end) the
-- button says "Returning..." and ignores taps, then acts once. A refused start leaves the screen (the server's toast says why) and
-- the button works again after START_WAIT; the next battle's InBattle closes the screen.
-- Edit team opens PetsController's window with ReturnTo { Window = "Loss" }; its Close comes back through Reopen.
-- Plain Lua 5.1-compatible syntax only. All fonts come from Theme roles; no asset ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local Client = script.Parent.Parent
local UI = Client:WaitForChild("UI")
local CloudUI = require(UI:WaitForChild("CloudUI"))
local NeonKit = require(UI:WaitForChild("NeonKit"))
local State = require(Client:WaitForChild("State"))

local LossScreen = {}

local K = {
	DISPLAY_ORDER = 24,
	GUTTER_X = 16, -- screen px kept free around the card
	GUTTER_Y = 8,
	W_WIDE = 848, -- design px of a 1080p screen (at the phone scale the buttons end left of the jump button)
	W_TALL = 440, -- a portrait phone: the rows stack
	TOUCH_SCALE = 0.8, -- a narrow phone's card is narrower rather than under this fit: K.CLOSE and K.BUTTON_H stay >= 44 px
	JUMP_RIGHT = 95, -- a low screen: the buttons end this far from its right edge (Roblox's jump button, 70 px, 25 px in)
	ROW_W_SHORT = 260, -- design px: a narrower pet row takes "L99 -> L100" at LEVELS_SHORT
	LEVELS_SHORT = 22,
	PAD = 16,
	TITLE_H = 44,
	SUB_H = 28,
	SUB_H_TALL = 52,
	ROW_H = 104,
	ROW_H_TALL = 96,
	ROW_GAP = 8,
	LINE_H = 36,
	BUTTON_H = 60,
	CLOSE = 56,
	SHORT = 500, -- a screen lower than this keeps the card up at the top, clear of the jump button
	POLL = 0.2, -- seconds between two looks at InBattle
	RETURN_WAIT = 7, -- BattleService / DungeonService RETURN_DELAY (4) + 3: longest wait for the return teleport
	START_WAIT = 2.5, -- a Fight again the server did not start: the button works again after this
	POP_DELAY = 0.3, -- the level-up moment, after the card shows
	POP_SECONDS = 0.35,
	XP_SECONDS = 0.9,
}

local Colors = Theme.Colors
local WHITE = Colors.White
local INK = Colors.PanelInk or Color3.fromRGB(8, 10, 28)
local MUTED = Color3.fromRGB(176, 184, 214)
local GOLD = Theme.Neon.Gold
local GREEN = Theme.Neon.Green
local BAR_BACK = Color3.fromRGB(18, 22, 52)
local ROW_BACK = Color3.fromRGB(30, 36, 78)

local LocalPlayer = Players.LocalPlayer
local IN_BATTLE = (Config.Attr and Config.Attr.InBattle) or "InBattle"

local U = nil -- the widgets, built by the first Show
local S = {
	Open = false,
	Payload = nil,
	Rows = {}, -- { Root, Handle } per pet
	Token = 0, -- a newer Show / Hide drops what an older one still has waiting
	Busy = false, -- Fight again / Edit team is waiting
	InBattleAtShow = nil,
}

local function warnOf(what, err)
	warn("[LossScreen] " .. what .. ": " .. tostring(err))
end

local function safe(what, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOf(what, err)
	end
	return ok
end

local function optional(parent, name)
	local inst = parent:FindFirstChild(name)
	if not inst then
		return nil
	end
	local ok, mod = pcall(require, inst)
	return ok and type(mod) == "table" and mod or nil
end

local function inBattle()
	local v = LocalPlayer and LocalPlayer:GetAttribute(IN_BATTLE)
	return v ~= nil and v ~= false and v ~= ""
end

local function text(parent, name, value, role, size, color, props)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = tostring(value or "")
	Theme.Style(label, role, { Size = size, Color = color or WHITE, Stroke = 1 })
	Theme.TextOutline(label, 1.5, INK, 0.1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	label.Parent = parent
	return label
end

----------------------------------------------------------------------
-- Layout: one UIScale fits the card inside the screen, under the top bar
----------------------------------------------------------------------
local function viewportSize()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if vp.X < 2 or vp.Y < 2 then
		return Vector2.new(1920, 1080)
	end
	return vp
end

local function layout()
	local vp = viewportSize()
	local tall = vp.X < vp.Y
	local w = math.min(tall and K.W_TALL or K.W_WIDE, math.floor((vp.X - 2 * K.GUTTER_X) / K.TOUCH_SCALE))
	local inner = w - 2 * K.PAD
	local y = 12
	U.Title.Position = UDim2.fromOffset(K.PAD + 4, y)
	U.Title.Size = UDim2.fromOffset(inner - K.CLOSE - 12, K.TITLE_H)
	U.Close.Position = UDim2.fromOffset(w - K.PAD - K.CLOSE, 10)
	U.Close.Size = UDim2.fromOffset(K.CLOSE, K.CLOSE)
	y = y + K.TITLE_H + 2
	local subH = tall and K.SUB_H_TALL or K.SUB_H
	U.Sub.Position = UDim2.fromOffset(K.PAD + 4, y)
	U.Sub.Size = UDim2.fromOffset(inner - 8 - (tall and 0 or K.CLOSE), subH)
	U.Sub.TextWrapped = tall
	y = y + subH + K.ROW_GAP

	-- the pets: three columns, stacked rows on a portrait phone
	local n = math.max(1, #S.Rows)
	local rowH = tall and K.ROW_H_TALL or K.ROW_H
	local rowW = tall and inner or math.floor((inner - (n - 1) * K.ROW_GAP) / n)
	for i, row in ipairs(S.Rows) do
		if tall then
			row.Root.Position = UDim2.fromOffset(K.PAD, y + (i - 1) * (rowH + K.ROW_GAP))
		else
			row.Root.Position = UDim2.fromOffset(K.PAD + (i - 1) * (rowW + K.ROW_GAP), y)
		end
		row.Root.Size = UDim2.fromOffset(rowW, rowH)
		if row.Gained then
			row.Levels.TextSize = rowW < K.ROW_W_SHORT and K.LEVELS_SHORT or 26
		end
	end
	y = y + (tall and (n * (rowH + K.ROW_GAP)) or (rowH + K.ROW_GAP))

	-- the run's lines: one row, two columns on a portrait phone
	local lines = {}
	for _, c in ipairs(U.Lines:GetChildren()) do
		if c:IsA("TextLabel") then
			lines[#lines + 1] = c
		end
	end
	table.sort(lines, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local cols = tall and 2 or math.max(1, #lines)
	local cellW = math.floor(inner / cols)
	for i, label in ipairs(lines) do
		label.Position = UDim2.fromOffset(((i - 1) % cols) * cellW + 4, math.floor((i - 1) / cols) * K.LINE_H)
		label.Size = UDim2.fromOffset(cellW - 8, K.LINE_H)
	end
	local lineRows = math.ceil(#lines / cols)
	U.Lines.Position = UDim2.fromOffset(K.PAD, y)
	U.Lines.Size = UDim2.fromOffset(inner, lineRows * K.LINE_H)
	y = y + lineRows * K.LINE_H + K.ROW_GAP

	local buttonsY = y
	y = y + K.BUTTON_H + K.PAD

	U.Card.Root.Size = UDim2.fromOffset(w, y)
	local inset = 0
	local okI, topLeft = pcall(function()
		return (GuiService:GetGuiInset())
	end)
	if okI and typeof(topLeft) == "Vector2" then
		inset = topLeft.Y
	end
	local factor = 1
	local okF, f = pcall(CloudUI.ScreenFactor)
	if okF and tonumber(f) then
		factor = f
	end
	local fit = math.min((vp.X - 2 * K.GUTTER_X) / w, (vp.Y - inset - 2 * K.GUTTER_Y) / y)
	U.Fit.Scale = math.max(0.3, math.min(factor, fit))

	-- the buttons: on a low screen they end left of the jump button
	local buttonsW = inner
	if not tall and vp.Y < K.SHORT then
		local cardLeft = (vp.X - w * U.Fit.Scale) / 2
		buttonsW = math.min(inner, math.floor((vp.X - K.JUMP_RIGHT - cardLeft) / U.Fit.Scale) - K.PAD)
	end
	local again = U.FightAgain.Visible
	local half = math.floor((buttonsW - K.ROW_GAP) / 2)
	U.FightAgain.Position = UDim2.fromOffset(K.PAD, buttonsY)
	U.FightAgain.Size = UDim2.fromOffset(half, K.BUTTON_H)
	U.EditTeam.Position = again and UDim2.fromOffset(K.PAD + half + K.ROW_GAP, buttonsY) or UDim2.fromOffset(K.PAD, buttonsY)
	U.EditTeam.Size = again and UDim2.fromOffset(half, K.BUTTON_H) or UDim2.fromOffset(buttonsW, K.BUTTON_H)

	U.Card.Root.AnchorPoint = Vector2.new(0.5, 0.5)
	local h = y * U.Fit.Scale
	local free = vp.Y - inset - h
	U.Card.Root.Position = UDim2.fromOffset(math.floor(vp.X / 2), math.floor(inset + (vp.Y < K.SHORT and math.min(free / 2, K.GUTTER_Y / 2) or free / 2) + h / 2))
end

----------------------------------------------------------------------
-- The pets
----------------------------------------------------------------------
local function clearRows()
	for _, row in ipairs(S.Rows) do
		if row.Handle and type(row.Handle.Destroy) == "function" then
			pcall(row.Handle.Destroy)
		end
		row.Root:Destroy()
	end
	S.Rows = {}
end

local function petRow(i, entry)
	local key = tostring(entry.Key)
	local before, after = math.floor(tonumber(entry.Before) or 1), math.floor(tonumber(entry.After) or 1)
	local gained = after > before
	local root = Instance.new("Frame")
	root.Name = "PetRow" .. i
	root.BackgroundColor3 = ROW_BACK
	root.BorderSizePixel = 0
	root.Parent = U.Card.Body
	Util.Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = root })
	local rowH = viewportSize().X < viewportSize().Y and K.ROW_H_TALL or K.ROW_H
	local faceSize = rowH - 32 -- (the rest of the column holds "L99 -> L100" at this size)
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BackgroundTransparency = 1
	face.BorderSizePixel = 0
	face.Position = UDim2.fromOffset(8, 16)
	face.Size = UDim2.fromOffset(faceSize, faceSize)
	face.Parent = root
	local def = State.DefOf(key)
	local handle = nil
	if def then
		local stage = tonumber(State.PetStage(key)) or 0
		local okV, h = pcall(CloudUI.PetViewport, face, def, UDim2.fromScale(1, 1), { Spin = "sway", Detail = "Low", Evolved = stage > 0 and stage or nil })
		handle = okV and h or nil
	end
	local x = faceSize + 16
	text(root, "Name", def and (def.DisplayName or def.Name) or entry.PetId or key, "Body", 19, WHITE, {
		Position = UDim2.fromOffset(x, 8),
		Size = UDim2.new(1, -x - 6, 0, 26),
	})
	local levels = text(root, "Levels", gained and ("L" .. before .. " -> L" .. after) or ("L" .. after), "Heading", gained and 26 or 24, gained and GOLD or WHITE, {
		Position = UDim2.fromOffset(x, 36),
		Size = UDim2.new(1, -x - 6, 0, 36),
	})
	local pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = levels })
	local bar = Instance.new("Frame")
	bar.Name = "XpBar"
	bar.BackgroundColor3 = BAR_BACK
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(x, 76)
	bar.Size = UDim2.new(1, -x - 10, 0, 12)
	bar.Visible = not gained
	bar.Parent = root
	Util.Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = bar })
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = GREEN
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(math.max(0, math.min(1, tonumber(entry.XpBefore) or 0)), 1)
	fill.Parent = bar
	Util.Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = fill })
	return { Root = root, Handle = handle, Gained = gained, Levels = levels, Pop = pop, Fill = fill, To = math.max(0, math.min(1, tonumber(entry.XpFrac) or 0)) }
end

local function moment(token)
	local any = false
	for _, row in ipairs(S.Rows) do
		if row.Gained then
			any = true
			row.Pop.Scale = 0.4
		else
			TweenService:Create(row.Fill, TweenInfo.new(K.XP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(row.To, 1) }):Play()
		end
	end
	if not any then
		return
	end
	task.delay(K.POP_DELAY, function()
		if token ~= S.Token then
			return
		end
		for _, row in ipairs(S.Rows) do
			if row.Gained then
				TweenService:Create(row.Pop, TweenInfo.new(K.POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end
		local sound = optional(Client, "SoundFx")
		if sound and type(sound.Play) == "function" then
			safe("sound", sound.Play, "Reward")
		end
	end)
end

----------------------------------------------------------------------
-- The buttons
----------------------------------------------------------------------
-- fn() once the return teleport is over; the button says so meanwhile, and other taps are ignored
local function afterReturn(button, idleText, fn)
	if S.Busy then
		return
	end
	S.Busy = true
	local token = S.Token
	button.Text = "Returning..."
	task.spawn(function()
		local t0 = os.clock()
		while inBattle() and os.clock() - t0 < K.RETURN_WAIT do
			task.wait(K.POLL)
			if token ~= S.Token then
				return
			end
		end
		S.Busy = false
		button.Text = idleText
		if not inBattle() then
			safe("button", fn)
		end
	end)
end

local function hideCard()
	S.Open = false
	S.Token = S.Token + 1
	S.Busy = false
	if U then
		U.Card.Root.Visible = false
		U.Gui.Enabled = false
	end
end

local function fightAgain()
	local payload = S.Payload
	if not payload or not payload.OnFightAgain then
		return
	end
	afterReturn(U.FightAgain, "Fight again", function()
		S.Busy = true
		local token = S.Token
		payload.OnFightAgain()
		task.delay(K.START_WAIT, function()
			if token == S.Token then
				S.Busy = false
			end
		end)
	end)
end

local function editTeam()
	afterReturn(U.EditTeam, "Edit team", function()
		local pets = optional(script.Parent, "PetsController")
		if pets and type(pets.Open) == "function" then
			hideCard()
			pets.Open({ ReturnTo = { Window = "Loss" } })
		end
	end)
end

local function build()
	if U and U.Gui.Parent then
		return true
	end
	local gui = CloudUI.NewScreenGui("NimbusLoss", K.DISPLAY_ORDER)
	if not gui then
		return false
	end
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	local card = NeonKit.Card({ Name = "LossCard", Size = UDim2.fromOffset(K.W_WIDE, 400), Color = GOLD, Floor = false, Active = true, Parent = gui })
	card.Root.Visible = false
	local fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = card.Root })
	local body = card.Body
	local lines = Instance.new("Frame")
	lines.Name = "Lines"
	lines.BackgroundTransparency = 1
	lines.BorderSizePixel = 0
	lines.Parent = body
	U = {
		Gui = gui,
		Card = card,
		Fit = fit,
		Title = text(body, "Title", "", "Title", 34, GOLD, { TextXAlignment = Enum.TextXAlignment.Left }),
		Sub = text(body, "Sub", "", "Body", 19, MUTED),
		Lines = lines,
		Close = NeonKit.Button({ Name = "CloseButton", Text = "X", Color = "Red", Variant = "Outline", Size = UDim2.fromOffset(K.CLOSE, K.CLOSE), TextSize = 24, Parent = body, Callback = function()
			local payload = S.Payload
			LossScreen.Hide()
			if payload and payload.OnClose then
				safe("close", payload.OnClose)
			end
		end }),
		FightAgain = NeonKit.Button({ Name = "FightAgain", Text = "Fight again", Color = "Green", Size = UDim2.fromOffset(300, K.BUTTON_H), TextSize = 24, Parent = body, Callback = fightAgain }),
		EditTeam = NeonKit.Button({ Name = "EditTeam", Text = "Edit team", Color = "Blue", Variant = "Outline", Size = UDim2.fromOffset(300, K.BUTTON_H), TextSize = 24, Parent = body, Callback = editTeam }),
	}
	local mouse = optional(Client, "MouseLock")
	if mouse and type(mouse.WatchVisible) == "function" then
		safe("mouse", mouse.WatchVisible, "LossScreen", card.Root) -- the cursor is free while the card shows
	end
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal(IN_BATTLE):Connect(function()
			if S.Open and inBattle() and LocalPlayer:GetAttribute(IN_BATTLE) ~= S.InBattleAtShow then
				LossScreen.Hide() -- the next battle started
			end
		end)
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if S.Open then
				safe("layout", layout)
			end
		end)
	end
	return true
end

local function fill(payload)
	U.Card.SetColor(payload.Color or GOLD)
	U.Title.Text = tostring(payload.Title or "RUN OVER")
	U.Title.TextColor3 = payload.Color or GOLD
	U.Sub.Text = tostring(payload.Sub or "")
	for _, c in ipairs(U.Lines:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for i, line in ipairs(type(payload.Lines) == "table" and payload.Lines or {}) do
		text(U.Lines, "Line" .. i, line[1], "Body", 18, line[2] or WHITE, { LayoutOrder = i })
	end
	clearRows()
	for i, entry in ipairs(type(payload.Pets) == "table" and payload.Pets or {}) do
		if i > 3 then
			break
		end
		S.Rows[i] = petRow(i, entry)
	end
	U.FightAgain.Text = "Fight again"
	U.EditTeam.Text = "Edit team"
	U.FightAgain.Visible = payload.OnFightAgain ~= nil
end

local function present(payload)
	S.Token = S.Token + 1
	S.Busy = false
	S.Open = true
	S.Payload = payload
	S.InBattleAtShow = LocalPlayer and LocalPlayer:GetAttribute(IN_BATTLE) or nil
	fill(payload)
	layout()
	U.Gui.Enabled = true
	U.Card.Root.Visible = true
end

function LossScreen.Show(payload)
	if type(payload) ~= "table" or not build() then
		return false
	end
	present(payload)
	moment(S.Token)
	return true
end

function LossScreen.Reopen()
	local payload = S.Payload
	if S.Open or not payload or not build() then
		return
	end
	-- a battle started while the player was away: this loss is over
	if inBattle() and LocalPlayer:GetAttribute(IN_BATTLE) ~= S.InBattleAtShow then
		S.Payload = nil
		return
	end
	present(payload)
	for _, row in ipairs(S.Rows) do
		row.Fill.Size = UDim2.fromScale(row.To, 1)
	end
end

function LossScreen.Hide()
	S.Payload = nil
	hideCard()
end

function LossScreen.IsOpen()
	return S.Open
end

return LossScreen
