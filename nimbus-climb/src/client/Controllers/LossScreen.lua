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
-- ScreenGui NimbusLoss (DisplayOrder 24: above the battle HUD's result card, below Notify 30), card LossCard (NeonKit.Card, kit B's
-- cream sign with a red lip (kit-b U9-6: square, flat, colour by role: a loss is the danger red; brown ink), centred
-- under the top bar over a Shade that dims the screen below the top bar; 16 px side gutters on a phone; every button >= 44 px;
-- nailed up like the Dungeon End card): Title, Sub, PetRow1..3 (Face viewport, Name, Lift: Levels "L1", the pixel arrow, LevelTo
-- "L3" with a pop + one SoundFx "Reward" for the whole card and a gold sparkle on the row, or Levels "L1" + XpBar, ten sky kit
-- blocks lighting from XpBefore to XpFrac), Lines (the run's rewards as stone fact tags with their pixel icons), FightAgain
-- ("Fight again", hidden without OnFightAgain), EditTeam ("Edit team"), CloseButton (NeonKit.CloseBlock: its X drawn).
-- The buttons are kit B blocks (CloudUI.Button Skin "Sign": Fight again the one green action, Edit team stone, Close danger red).
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
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (LOOK-ui2) whole-px edges and lips, the reward and level icons
local SignKit = require(Shared:WaitForChild("SignKit")) -- (LOOK-ui2) the XP block rows, the nails
local State = require(Client:WaitForChild("State"))

local LossScreen = {}

local K = {
	DISPLAY_ORDER = 24,
	GUTTER_X = 16, -- screen px kept free around the card
	GUTTER_Y = 8,
	W_WIDE = 848, -- design px of a 1080p screen (at the phone scale the buttons end left of the jump button)
	W_TALL = 440, -- a portrait phone: the rows stack
	TOUCH_SCALE = 0.8, -- a narrow phone's card is narrower rather than under this fit: K.CLOSE and K.BUTTON_H stay >= 44 px
	JUMP_RIGHT = 120, -- a low screen: the buttons end this far from its right edge (Roblox's jump button: 70 px, 45 px in; kit-b U9-6)
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
	TAG_H = 32, -- (LOOK-ui2) a reward's fact tag in its LINE_H row
	XP_BLOCKS = 10,
	SHADE = 0.55, -- the PetPicker's shade under the card
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

-- (kit-b U9-6) the Cloud Shop Signboard: brown ink on the cream sign, the pets in their wells; (LOOK-ui2) the XP a row of kit
-- blocks in XP's one role colour, sky (as Pets and Feed; it was grass here)
local SIGN = Theme.Sign
local INK = SIGN.Text
local MUTED = SIGN.TextMuted
local LIP = SIGN.Red -- the card's lip: a loss
local LIFT = SIGN.Good or Theme.Darken(SIGN.GrassLip, 0.35) -- "L1 -> L3": the levels gained (kit B's good ink, as Care and Train)
local XP_FILL, XP_LIP = SIGN.Sky, SIGN.SkyLip
local ROW_BACK = SIGN.PetWell

-- (LOOK-ui2) a reward line's pixel icon (the dock family's fact tag: the Dungeon End card's chips), by what it pays
local REWARD_ICONS = {
	{ "Tokens", Config.Icons and Config.Icons.Tokens or "token" }, { "Gems", "gem" }, { "Cash", Config.Icons and Config.Icons.Cash or "note" },
	{ "Trophies", "trophy" }, { "Pet XP", "up" }, { "Rounds won", "crown" }, { "Best", "star" }, { "Floor", "key" },
}
local function rewardIcon(line)
	line = tostring(line or "")
	for _, pair in ipairs(REWARD_ICONS) do
		if line:find(pair[1], 1, true) then
			return pair[2]
		end
	end
	return nil
end

-- (LOOK-ui2) a rough drawn width (FredokaOne: 0.72 em a capital, 0.58 any other letter or digit, 0.3 a space), or
-- Theme.Measure's when it is wider
local function drawnW(value, role, px)
	local est = 0
	for ch in tostring(value):gmatch(".") do
		est = est + ((ch == " ") and 0.3 or (ch:match("%u") and 0.72 or 0.58))
	end
	local okM, size = pcall(Theme.Measure, tostring(value), role, px)
	return math.ceil(math.max(est * px, (okM and typeof(size) == "Vector2") and size.X or 0))
end

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
	-- kit-b U6: the card is a plate, so the text reads by contrast (no outline)
	Theme.Style(label, role, { Size = size, Color = color or INK })
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	label.Parent = parent
	return label
end

-- (kit-b U9-6) a square wood edge (kit B: no rounded corners)
local function edge(obj, color, thickness)
	return Util.Create("UIStroke", { Name = "SignEdge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Miter, Color = color, Thickness = thickness, Parent = obj })
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
			row.PlaceLift(rowW < K.ROW_W_SHORT and K.LEVELS_SHORT or 26)
		end
	end
	y = y + (tall and (n * (rowH + K.ROW_GAP)) or (rowH + K.ROW_GAP))

	-- the run's rewards (LOOK-ui2: were three bare text lines): fact tags as wide as their words, 6 px apart, in rows
	local lines = {}
	for _, c in ipairs(U.Lines:GetChildren()) do
		if c:IsA("TextLabel") then
			lines[#lines + 1] = c
		end
	end
	table.sort(lines, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local lx, lineRows = 0, (#lines > 0) and 1 or 0
	for _, label in ipairs(lines) do
		local pad = label:FindFirstChildOfClass("UIPadding")
		-- (merge kitb-look1 x U9-6) 6 px spare (was 4): under the card's 0.67 at 1280 x 720 the icon keeps its 2 px cells
		-- (PixelIcon: never under 2) and 4 design px were 2.7 screen px, under the text's measured width
		local tw = math.min(inner, drawnW(label.Text, "Heading", label.TextSize) + (pad and (pad.PaddingLeft.Offset + pad.PaddingRight.Offset) or 20) + 6)
		if lx > 0 and lx + tw > inner then
			lx, lineRows = 0, lineRows + 1
		end
		label.Position = UDim2.fromOffset(lx, (lineRows - 1) * K.LINE_H + math.floor((K.LINE_H - K.TAG_H) / 2))
		label.Size = UDim2.fromOffset(tw, K.TAG_H)
		lx = lx + tw + 6
	end
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

	-- (LOOK-ui2: the HUD stayed live round the card: the wallet pills, half of DASH, the Index tile cut by its edge) the
	-- PetPicker's shade dims everything under the top bar while the card is up
	U.Shade.Position = UDim2.fromOffset(0, inset)
	U.Shade.Size = UDim2.fromOffset(vp.X, math.max(0, vp.Y - inset))
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
	edge(root, SIGN.Wood, 2)
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
	text(root, "Name", def and (def.DisplayName or def.Name) or entry.PetId or key, "Body", 19, INK, {
		Position = UDim2.fromOffset(x, 8),
		Size = UDim2.new(1, -x - 6, 0, 26),
	})
	-- (LOOK-ui2: "L18 -> L20" with an ASCII arrow) the levels gained: "L18", the kit's pixel arrow, "L20" (Lift, which pops),
	-- and a gold pixel sparkle in the row's corner; no level-up: "L18" and the XP as ten sky kit blocks
	local lift = Instance.new("Frame")
	lift.Name = "Lift"
	lift.BackgroundTransparency = 1
	lift.BorderSizePixel = 0
	lift.Position = UDim2.fromOffset(x, 36)
	lift.Size = UDim2.new(1, -x - 6, 0, 36)
	lift.Parent = root
	local pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = lift })
	local levels = text(lift, "Levels", "L" .. (gained and before or after), "Heading", gained and 26 or 24, gained and LIFT or INK, {
		Size = UDim2.new(1, 0, 1, 0),
		TextTruncate = Enum.TextTruncate.None,
	})
	local out = { Root = root, Handle = handle, Gained = gained, Levels = levels, Pop = pop, To = math.max(0, math.min(1, tonumber(entry.XpFrac) or 0)) }
	if gained then
		local to = text(lift, "LevelTo", "L" .. after, "Heading", 26, LIFT, { TextTruncate = Enum.TextTruncate.None })
		local arrow = PixelIcon.New(lift, "arrow", 18, LIFT)
		arrow.Name = "Arrow"
		out.LevelTo, out.Arrow = to, arrow
		-- the line's parts side by side at `px`: the arrow 6 px off each number, centred on the line
		function out.PlaceLift(px)
			levels.TextSize, to.TextSize = px, px
			local w1 = drawnW(levels.Text, "Heading", px) + 2
			local w2 = drawnW(to.Text, "Heading", px) + 2
			levels.Size = UDim2.new(0, w1, 1, 0)
			arrow.AnchorPoint = Vector2.new(0, 0.5)
			arrow.Position = UDim2.new(0, w1 + 6, 0.5, 0)
			to.Position = UDim2.fromOffset(w1 + 6 + 18 + 6, 0)
			to.Size = UDim2.new(0, w2, 1, 0)
		end
		out.PlaceLift(26)
		local spark = PixelIcon.New(root, "sparkle", 18, SIGN.Gold)
		spark.Name = "Sparkle"
		spark.AnchorPoint = Vector2.new(1, 0)
		spark.Position = UDim2.new(1, -6, 0, 6)
	else
		out.Bar = SignKit.FitBlocks(root, { Name = "XpBar", Count = K.XP_BLOCKS, Gap = 2, EdgePx = 2, LipPx = 3, Fill = XP_FILL, FillLip = XP_LIP,
			Position = UDim2.fromOffset(x, 76), Size = UDim2.new(1, -x - 10, 0, 14) })
		SignKit.FillBlocks(out.Bar, math.floor(math.max(0, math.min(1, tonumber(entry.XpBefore) or 0)) * K.XP_BLOCKS + 1e-6))
	end
	return out
end

-- (LOOK-ui2) the XP row lights block by block from what it held to where it ends, over K.XP_SECONDS
local function xpTo(row, token)
	local bar = row.Bar
	if not bar then
		return
	end
	local from = bar:GetAttribute("Filled") or 0
	local to = math.floor(row.To * K.XP_BLOCKS + 1e-6)
	if to <= from then
		SignKit.FillBlocks(bar, to)
		return
	end
	local step = K.XP_SECONDS / (to - from)
	task.spawn(function()
		for k = from + 1, to do
			task.wait(step)
			if token ~= S.Token or not bar.Parent then
				return
			end
			SignKit.FillBlocks(bar, k)
		end
	end)
end

local function moment(token)
	local any = false
	for _, row in ipairs(S.Rows) do
		if row.Gained then
			any = true
			row.Pop.Scale = 0.4
		else
			xpTo(row, token)
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
	-- (LOOK-ui2: under the card's Fit of 0.8 a 2 px edge drew 1.6 screen px, a 8 px lip 6.4) every wood edge and lip of the
	-- card, now and as rows are added, on whole screen px (PixelIcon.WholeTree, kitb-look1's one helper)
	PixelIcon.WholeTree(gui)
	gui.Enabled = false
	-- (LOOK-ui2) the shade under the card (the PetPicker's: kit B's navy lip, see-through); an Active frame, not a button, so
	-- it takes the HUD's taps but never sits as a control under Roblox's thumbstick or jump button
	local shade = Util.Create("Frame", {
		Name = "Shade", BorderSizePixel = 0, Active = true, BackgroundColor3 = SIGN.NavyLip, BackgroundTransparency = K.SHADE, Parent = gui,
	})
	local card = NeonKit.Card({ Name = "LossCard", Skin = "Sign", Size = UDim2.fromOffset(K.W_WIDE, 400), Color = LIP, LipPx = 8, Active = true, Parent = gui })
	card.Root.Visible = false
	card.Root.ZIndex = math.max(2, card.Root.ZIndex)
	SignKit.Nails(card.Root, { Inset = 5, ZIndex = 3 }) -- (LOOK-ui2) nailed up like its sibling, the Dungeon End card
	local fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = card.Root })
	local body = card.Body
	local lines = Instance.new("Frame")
	lines.Name = "Lines"
	lines.BackgroundTransparency = 1
	lines.BorderSizePixel = 0
	lines.Parent = body
	U = {
		Gui = gui,
		Shade = shade,
		Card = card,
		Fit = fit,
		-- (owner ruling 2026-11-14: a pop-up's title is kit B's plain Section title, the gold ribbon is for windows)
		Title = Theme.StyleTitle(text(body, "Title", "", "Title", 34, INK, { TextXAlignment = Enum.TextXAlignment.Left }), "Section"),
		Sub = text(body, "Sub", "", "Body", 19, MUTED),
		Lines = lines,
		Close = CloudUI.Button({ Name = "CloseButton", Text = "", Style = "Red", Skin = "Sign", Size = UDim2.fromOffset(K.CLOSE, K.CLOSE), TextSize = 24, Parent = body, Callback = function()
			local payload = S.Payload
			LossScreen.Hide()
			if payload and payload.OnClose then
				safe("close", payload.OnClose)
			end
		end }),
		FightAgain = CloudUI.Button({ Name = "FightAgain", Text = "Fight again", Style = "Green", Skin = "Sign", Size = UDim2.fromOffset(300, K.BUTTON_H), TextSize = 24, Parent = body, Callback = fightAgain }),
		EditTeam = CloudUI.Button({ Name = "EditTeam", Text = "Edit team", Style = "Gray", Skin = "Sign", Size = UDim2.fromOffset(300, K.BUTTON_H), TextSize = 24, Parent = body, Callback = editTeam }),
	}
	NeonKit.CloseMark(U.Close, { Square = true, Ink = SIGN.RedLip, Color = INK }) -- slop audit 2026-11-12: a drawn X (no "X" letter, no glyph)
	NeonKit.CloseBlock(U.Close) -- (LOOK-ui2) one close for kit B: never under 44 screen px, its x in 3 px cells
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
	U.Card.SetColor(LIP) -- (kit-b U9-6: the lip by role; the payload's Color was the neon card's tint)
	U.Title.Text = tostring(payload.Title or "RUN OVER")
	U.Title.TextColor3 = INK
	U.Sub.Text = tostring(payload.Sub or "")
	for _, c in ipairs(U.Lines:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for i, line in ipairs(type(payload.Lines) == "table" and payload.Lines or {}) do
		-- (LOOK-ui2) the dock family's fact tag: stone in a 2 px wood edge, the pixel icon before the words in the ink
		local tag = text(U.Lines, "Line" .. i, line[1], "Heading", 18, INK, { LayoutOrder = i, BackgroundTransparency = 0, BackgroundColor3 = SIGN.Tile,
			TextXAlignment = Enum.TextXAlignment.Center })
		edge(tag, SIGN.Wood, 2)
		Util.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = tag })
		local icon = rewardIcon(line[1])
		if icon then
			PixelIcon.Lead(tag, icon)
		end
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
		if row.Bar then
			SignKit.FillBlocks(row.Bar, math.floor(row.To * K.XP_BLOCKS + 1e-6))
		end
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
