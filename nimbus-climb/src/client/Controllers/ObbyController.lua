-- ObbyController (client, Phase 5, dungeonclient W4): the level picker of the ONE obby portal (ARCHITECTURE_V3.md
-- "Phase 5 build contract" 6.3, 6.6).
--
--   ObbyController.Init()
--   ObbyController.Open(levelId|nil, portal|nil) -> bool   the picker (the gate's ObbyPrompt "Pick level", OpenPanel("Obby"),
--                                             the party panel's CHANGE chip: HudController._onChangeLevel calls Open())
--   ObbyController.Close()
--   ObbyController.IsOpen() -> bool
--   ObbyController.Pick(levelId) -> bool      sends ObbyPick(levelId) for an unlocked level (the server checks it again with
--                                             its own copy of Stats.BestTimes: PortalService.PickLevel)
--   ObbyController.GetState() -> { Window, Picked, Highest, Levels = { {Id, Unlocked, Picked, Best}... }, Footer }
--   ObbyController.Opened / Closed (Util.Signal)
--
-- What the player sees: a docked kit B signboard (560 x 560 design px; docked right on landscape screens, a bottom sheet on
-- portrait phones; kit-b U9-8, was a NeonKit side panel) with the five levels of shared/ObbyLevels (Easy, Medium, Hard,
-- Extreme, Saint) as stone rows in a sunk well: the level's number on a square tile in its colour, name and stars,
-- "Best 3:42 . Win +35 tokens" or LOCKED "Beat Medium to unlock", a PICK / PICKED / LOCKED tag; the picked row is pale gold
-- and shows its blurb (not on a short screen). A level is open when the one before it was beaten (ObbyLevels.IsUnlocked on
-- State's Stats.BestTimes; the server decides). The line under the title says what happens next: "Step on the pad to start"
-- or "Party on the pad: Hard 2/4 - step on to join" (the gate's PartyLevel / PartyCount / PartyMax attributes), or the own
-- party's line while the player waits on the pad. On a touch screen Roblox's thumbstick and jump button go while it is
-- open. It closes when the player walks 40 studs away from the gate or steps onto the pad (a window opened there), with
-- Esc / gamepad B / the close block, or when another window opens. After a won match that unlocks the next level a kit B
-- toast says "Extreme unlocked! Pick it at the Obby portal." at the top right, clear of the result card and the HUD (a
-- screen with no room beside the result card shows it once the card has gone).
-- Remotes: OpenPanel (in), PartyState (in), MatchResult (in), ObbyPick (out). Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7b) the levels' stars, lock and tick
local SignKit = require(Shared:WaitForChild("SignKit")) -- (kit-b U9-8) the header, the list's bar, the toast's nails
local Remotes = require(Shared:WaitForChild("Remotes"))
local ObbyLevels = require(Shared:WaitForChild("ObbyLevels"))

local Client = script.Parent.Parent
local UI = Client:WaitForChild("UI")
local CloudUI = require(UI:WaitForChild("CloudUI"))
local NeonKit = require(UI:WaitForChild("NeonKit"))
local State = require(Client:WaitForChild("State"))

local ObbyController = {}
ObbyController.Opened = Util.Signal()
ObbyController.Closed = Util.Signal()

local K = {
	DISPLAY_ORDER = 23,
	TOAST_ORDER = 31, -- above NimbusNotify's stack
	PREF_W = 560,
	PREF_H = 560, -- (kit-b U9-8) the five rows, the picked one open, with no empty stone under them (was 640)
	SHORT = 520, -- docked lower than this: no blurb on the picked row (landscape phones, portrait sheets)
	ROW_H = 66, -- (kit-b U9-8) a level row: name + stars, the info line, the lip
	ROW_H_SHORT = 60, -- (U9-8 look) a short dock's row (name at 4, info at 30): four rows fit a landscape phone's sheet
	PRESS = 2, -- (U9-8 look) a pressed row's face drops this far and its lip thins by as much (the kit's press)
	CHIP_LIP = 4, -- (U9-8 look) the PICK plank's lip (it sinks onto it while its row is pressed)
	BLURB_H = 46, -- the picked row's blurb (two lines) under its info line
	ROW_GAP = 6, -- between the rows, and the list's pad at its top and bottom (whole rows at the list's edges)
	CHIP_W = 122,
	CHIP_H = 30,
	CHIP_SMALL = 34, -- a narrow row's tag: its icon alone (the tick, the lock, the arrow), so the name and stars stay whole
	TOP_H = 36, -- the line under the title and its gap
	FIRE_GAP = 0.3,
	WALK_AWAY = 40,
	TICK = 0.25,
	TOAST_SECONDS = 6,
	TOAST_W = 380,
	TOAST_H = 72, -- (a landscape phone fits it in the top row, above the middle band)
	TOAST_NARROW = 600, -- a screen narrower than this (design px: a portrait phone) gets the narrow toast ...
	TOAST_NARROW_W = 300, -- ... right of the menu column
	TOAST_NARROW_H = 88,
	TOAST_WAIT = 30, -- seconds the toast may wait for room (beside the result card) before it shows anyway
	TOAST_GAP = 10, -- kept from the HUD, the result card and the touch buttons
	EDGE = 12, -- KEEP IN SYNC with HudController / NotifyController: EDGE and TOUCH_EDGE
	TOUCH_EDGE = 20,
	BACK_ACTION = "NimbusObbyBack",
}

local SIGN = Theme.Sign
local INK = SIGN.Text
local MUTED = SIGN.TextMuted
local C = {
	Accent = SIGN.Sky, -- (kit-b U9-8) an unknown level's colour
	Star = SIGN.GoldLip, -- the stars on stone (the gold face itself is too pale there)
	StarOff = SIGN.WellEdge,
}

-- typography (kit-b U7b: the stars, the lock and the tick are PixelIcons, a level's tokens and best time say it in words)
local G = {
	Dot = "\194\183",
}

local LocalPlayer = nil
local initialized = false
local U = {}
local S = {
	Open = false,
	Token = 0,
	Want = nil, -- the optimistic pick until the ObbyLevel attribute / PartyState confirms it
	WantAt = 0,
	Party = nil, -- the last PartyState of the Obby portal (nil when not on the pad)
	AtPortal = nil,
	OpenedLocked = false,
	LastFire = {},
	BackBound = false,
	Highest = nil, -- the HighestUnlocked the player last saw
	Built = false,
	Short = false,
	Warned = {},
}
local H = {}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
function H.safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not S.Warned[key] then
		S.Warned[key] = true
		warn("[ObbyController] " .. key .. ": " .. tostring(err))
	end
	return ok
end

function H.controller(name)
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	return (ok and type(mod) == "table") and mod or nil
end

function H.frame(parent, name, props)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

function H.text(parent, name, text, role, size, color, props)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = tostring(text or "")
	-- kit-b U6: the window is a plate, so the text reads by contrast (no outline)
	Theme.Style(label, role or "Body", { Size = size, Color = color or INK })
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	label.Parent = parent
	return label
end

-- (kit-b U9-8) a square edge with mitred corners (kit B has no rounded blocks). (U9-8 look) whole screen px under the
-- dock's scale (SignKit.Whole: a 2 px edge drew 1.6 px at 0.8)
function H.edge(parent, color, thickness)
	local px = thickness or 2
	local stroke = Util.Create("UIStroke", {
		Name = "SignEdge",
		Color = color,
		Thickness = px,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
		Parent = parent,
	})
	SignKit.Whole(stroke, function(sc)
		stroke.Thickness = SignKit.Px(px, sc)
	end)
	return stroke
end

-- a flat lip along the bottom of a square tile (the block's darker underside); (U9-8 look) whole screen px tall.
-- H.setLip(lip, px) changes its height later
function H.lip(parent, color, px)
	local lip = H.frame(parent, "Lip", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, px or 4),
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
	})
	H.setLip(lip, px or 4)
	return lip
end

function H.setLip(lip, px)
	lip.Visible = px > 0
	SignKit.Whole(lip, function(sc)
		lip.Size = UDim2.new(1, 0, 0, SignKit.Px(px, sc))
	end)
end

function H.pad(parent, l, t, r, b)
	return Util.Create("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0),
		PaddingTop = UDim.new(0, t or 0),
		PaddingRight = UDim.new(0, r or 0),
		PaddingBottom = UDim.new(0, b or 0),
		Parent = parent,
	})
end

-- the colour a level's tile paints: a mid-tone that no ink reads 4.5:1 on is lightened until brown does (the Dungeon's rule)
function H.readable(color)
	for _ = 1, 6 do
		if Theme.Contrast(Theme.TextOn(color), color) >= 4.6 then
			break
		end
		color = Theme.Lighten(color, 0.08)
	end
	return color
end

-- a square tag holding a centred label "Text" (a level's state); H.paintTag colours it. (U9-8 look) with a Lip for when
-- it is the PICK plank
function H.tag(parent, name, props)
	local tag = H.frame(parent, name, props)
	tag.BackgroundTransparency = 0
	H.edge(tag, SIGN.Wood, 2)
	H.lip(tag, SIGN.SkyLip, 0)
	H.text(tag, "Text", "", "Tag", 18, INK, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	return tag
end

-- (U9-8 look) a row's tag by its state. PICK, the picker's one action, is a small sky plank (CloudUI.SignLooks.Sky: the sky
-- face on its SkyLip lip in the wood edge) that sinks onto its lip while its row is pressed (the face drops K.PRESS, the
-- lip thins by as much, the bottom stays); PICKED (gold) and LOCKED (the well, muted ink) are states: flat tags, no lip.
-- Was a flat sky rectangle drawn like the states. `w` the tag's width (design px)
function H.paintTag(ui, state, w)
	local tag = ui.Chip
	local look = CloudUI.SignLooks.Sky
	local plank = state == "PICK"
	local face = (state == "PICKED" and SIGN.Gold) or (state == "LOCKED" and SIGN.Well) or look.Face
	local sink = (plank and ui.Pressed) and K.PRESS or 0
	local lipPx = plank and (K.CHIP_LIP - sink) or 0
	tag.BackgroundColor3 = face
	tag.Position = UDim2.new(1, -10, 0, ui.ChipY + sink)
	tag.Size = UDim2.fromOffset(w, K.CHIP_H - sink)
	local lip = tag:FindFirstChild("Lip")
	lip.BackgroundColor3 = look.Lip
	H.setLip(lip, lipPx)
	for _, label in ipairs({ ui.ChipText, ui.Mark }) do
		label.Size = UDim2.new(1, 0, 1, -lipPx)
		label.TextColor3 = (state == "LOCKED") and MUTED or Theme.TextOn(face)
	end
	tag:SetAttribute("Plank", plank)
end

function H.viewport()
	local camera = Workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if vp.X < 2 or vp.Y < 2 then
		return Vector2.new(1920, 1080)
	end
	return vp
end

function H.touchOnly()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function H.tween(inst, seconds, goal, style, direction)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

function H.bestTimes()
	local ok, snap = pcall(State.Get)
	local stats = ok and type(snap) == "table" and snap.Stats or nil
	return type(stats) == "table" and type(stats.BestTimes) == "table" and stats.BestTimes or {}
end

function H.diff(id)
	if type(Config.GetDifficulty) == "function" then
		local d = Config.GetDifficulty(id)
		if d then
			return d
		end
	end
	for _, d in ipairs(Config.Difficulties or {}) do
		if d.Id == id then
			return d
		end
	end
	return { Id = id, DisplayName = tostring(id), Stars = 1, Color = C.Accent }
end

-- (kit-b U7b) a level's difficulty: 1-5 PixelIcon stars right after its name. (U9-8) GoldLip on an open level's stone,
-- the well's edge colour on a locked one; set again only when that changes
function H.stars(ui, open)
	if ui.StarsOpen == open then
		return
	end
	ui.StarsOpen = open
	local n = math.max(1, math.min(5, math.floor(tonumber(ui.StarCount) or 0)))
	PixelIcon.Lead(ui.Name, "star", { After = true, Room = true, Count = n, Of = n, Px = 18, Gap = 6, Colour = open and C.Star or C.StarOff })
end

function H.clock(seconds)
	local s = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

function H.winTokens(id)
	local t = Config.Match and Config.Match.TokenBonusOnWin
	return type(t) == "table" and tonumber(t[id]) or nil
end

function H.highest()
	local ok, n = pcall(ObbyLevels.HighestUnlocked, H.bestTimes())
	return ok and tonumber(n) or 1
end

-- the level the player has picked: the optimistic pick, the party's level (on the pad), the ObbyLevel attribute, else
-- the highest unlocked one
function H.picked()
	local list = ObbyLevels.List()
	if S.Want and os.clock() - S.WantAt < 3 then
		return S.Want
	end
	S.Want = nil
	if S.Party and type(S.Party.Level) == "string" then
		return S.Party.Level
	end
	local attr = LocalPlayer and LocalPlayer:GetAttribute((Config.Attr and Config.Attr.ObbyLevel) or "ObbyLevel")
	if type(attr) == "string" and ObbyLevels.IsUnlocked(H.bestTimes(), attr) then
		return attr
	end
	return list[math.max(1, math.min(#list, H.highest()))]
end

function H.portal()
	local lobby = Workspace:FindFirstChild("NimbusLobby")
	local gates = lobby and lobby:FindFirstChild("Gates")
	return (gates and gates:FindFirstChild("Portal_Obby")) or (lobby and lobby:FindFirstChild("Portal_Obby", true)) or nil
end

function H.positionOf(inst)
	if typeof(inst) ~= "Instance" then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		local ok, cf = pcall(function()
			return inst:GetBoundingBox()
		end)
		if ok and cf then
			return cf.Position
		end
	end
	local part = inst:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

function H.rootPosition()
	local character = LocalPlayer and LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return (root and root:IsA("BasePart")) and root.Position or nil
end

function H.locked()
	local v = LocalPlayer and LocalPlayer:GetAttribute("PortalLocked")
	return v ~= nil and v ~= false and v ~= ""
end

function H.isLeader()
	return S.Party ~= nil and LocalPlayer ~= nil and S.Party.LeaderUserId == LocalPlayer.UserId
end

-- brief: (kit-b U9-8) the short wording for a narrow dock (a phone), where the full line does not fit under the title
function H.footer(brief)
	if S.Party then
		local d = H.diff(S.Party.Level)
		local count = #(type(S.Party.Players) == "table" and S.Party.Players or {})
		local line = "On the pad: " .. tostring(d.DisplayName) .. " " .. count .. "/" .. tostring(S.Party.Max or 4)
		if H.isLeader() then
			return line .. " " .. G.Dot .. (brief and " tap to change" or " tap a level to change it")
		end
		return line .. " " .. G.Dot .. (brief and " leader picks" or " the leader picks the level")
	end
	local portal = H.portal()
	local n = portal and tonumber(portal:GetAttribute("PartyCount")) or 0
	if n > 0 then
		local level = portal:GetAttribute("PartyLevel")
		local d = H.diff(level)
		return (brief and "Party: " or "Party on the pad: ") .. tostring(d.DisplayName) .. " " .. n .. "/" .. tostring(portal:GetAttribute("PartyMax") or 4)
			.. (brief and " - step on" or " - step on to join")
	end
	return "Step on the pad to start"
end

-- the line under the title: the full wording when it fits the line's width (design px), else the short one
function H.footerFor(label)
	local text = H.footer()
	local scale = (U.Dock and U.Dock.Rect and tonumber(U.Dock.Rect.scale)) or 1
	local room = label.AbsoluteSize.X / math.max(0.01, scale)
	if room > 0 and Theme.Measure(text, "Heading", label.TextSize).X + 2 > room then
		return H.footer(true)
	end
	return text
end

----------------------------------------------------------------------
-- the window
----------------------------------------------------------------------
function H.build()
	if S.Built then
		return
	end
	S.Built = true
	local holder = H.frame(U.Gui, "Window_Obby", { Size = UDim2.fromOffset(K.PREF_W, K.PREF_H), Visible = false, ZIndex = 3 })
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	U.Dock = NeonKit.Dock(holder, U.Fit, K.PREF_W, K.PREF_H)
	local panel = CloudUI.Panel({
		Name = "ObbyPanel",
		Title = "Sky Obby",
		Closable = true,
		Skin = "Signboard", -- (kit-b U9-8) roof, navy header with the mountain, wood frame, stone body
		Icon = Config.Icons.Obby,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		OnClose = function()
			ObbyController.Close()
		end,
		Parent = holder,
	})
	U.Panel = panel
	-- a docked window's band stays inside the frame, no tails (the Dungeon's header on the same dock)
	SignKit.HeaderOverhang(panel.TitleBar, false)
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel.Root })
	local content = panel.Content
	local PAD = CloudUI.Metrics.SignPagePad
	-- what happens next, right under the title (a phone sheet's bottom edge is the far end of the thumb's reach)
	U.Footer = H.text(content, "Footer", "", "Heading", 19, INK, {
		Position = UDim2.fromOffset(PAD, 0),
		Size = UDim2.new(1, -2 * PAD, 0, 30),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- the levels in a sunk well (the pitch's .wl), the kit's square wood bar
	U.List = Instance.new("ScrollingFrame")
	U.List.Name = "Levels"
	U.List.BackgroundColor3 = SIGN.Well
	U.List.BackgroundTransparency = 0
	U.List.BorderSizePixel = 0
	H.edge(U.List, SIGN.WellEdge, 2)
	SignKit.ScrollBar(U.List)
	U.List.ScrollingDirection = Enum.ScrollingDirection.Y
	U.List.AutomaticCanvasSize = Enum.AutomaticSize.Y
	U.List.CanvasSize = UDim2.new(0, 0, 0, 0)
	U.List.Position = UDim2.fromOffset(PAD, K.TOP_H)
	U.List.Size = UDim2.new(1, -2 * PAD, 0, 300)
	U.List.Parent = content
	H.pad(U.List, 8, K.ROW_GAP, 14, K.ROW_GAP)
	Util.Create("UIListLayout", { Padding = UDim.new(0, K.ROW_GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = U.List })
	U.Cards = {}
	for i, id in ipairs(ObbyLevels.List()) do
		U.Cards[i] = H.card(i, id)
	end
end

-- one level row (a TextButton: tap to pick it). (kit-b U9-8) a stone block (pale gold with an ink edge when picked, the sunk
-- Off block when locked: H.refresh) with a square stripe in the level's colour, the level's number on a square tile in that
-- colour, the name with its stars, the info line, the blurb (the picked row only) and a square tag at the right
function H.card(i, id)
	local d = H.diff(id)
	local color = d.Color or C.Accent
	local row = Instance.new("TextButton")
	row.Name = "Level_" .. id
	row.AutoButtonColor = false
	row.Text = ""
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, K.ROW_H)
	row.LayoutOrder = i
	row.Parent = U.List
	-- (U9-8 look) the kit's press: the row's parts drop K.PRESS (a padding: the lip stays on the bottom edge) while its lip
	-- thins by as much (H.refresh), so a tap shows before the server answers
	local press = H.pad(row, 0, 0, 0, 0)
	press.Name = "Press"
	CloudUI.SignBlock(row, "Stone", { EdgePx = 2, LipPx = 4, Pad = false })
	local stripe = H.frame(row, "Stripe", { BackgroundTransparency = 0, BackgroundColor3 = color, Position = UDim2.fromOffset(4, 6), Size = UDim2.new(0, 6, 1, -16) })
	local face = H.readable(color)
	local badge = H.frame(row, "Badge", { BackgroundTransparency = 0, BackgroundColor3 = face, Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(42, 42) })
	H.edge(badge, SIGN.Wood, 2)
	H.lip(badge, Theme.Darken(face, 0.22), 4)
	H.text(badge, "Num", tostring(i), "Title", 22, Theme.TextOn(face), { Size = UDim2.new(1, 0, 1, -4), TextXAlignment = Enum.TextXAlignment.Center })
	local name = H.text(row, "LevelName", tostring(d.DisplayName or id), "Heading", 21, INK, {
		Position = UDim2.fromOffset(70, 6),
		Size = UDim2.new(1, -(80 + K.CHIP_W), 0, 28),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local info = H.text(row, "Info", "", "Body", 18, INK, {
		Position = UDim2.fromOffset(70, 34),
		Size = UDim2.new(1, -80, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local blurb = H.text(row, "Blurb", tostring(d.Blurb or ""), "Body", 18, MUTED, {
		Position = UDim2.fromOffset(70, 60),
		Size = UDim2.new(1, -80, 0, K.BLURB_H - 2),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
	})
	local chip = H.tag(row, "Chip", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(K.CHIP_W, K.CHIP_H),
	})
	local mark = H.text(chip, "Mark", "", "Tag", 18, INK, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	row.Activated:Connect(function()
		H.safe("pick", ObbyController.Pick, id)
	end)
	local ui = { Id = id, Root = row, Name = name, Blurb = blurb, Info = info, Chip = chip, ChipText = chip:FindFirstChild("Text"), Mark = mark, Color = color,
		StarCount = d.Stars, Stripe = stripe, Badge = badge, Press = press, Pressed = false, ChipY = 6 }
	local function setPressed(on)
		if ui.Pressed ~= on then
			ui.Pressed = on
			H.paintPress(ui)
		end
	end
	row.MouseButton1Down:Connect(function()
		setPressed(row:GetAttribute("Unlocked") ~= false)
	end)
	row.MouseButton1Up:Connect(function()
		setPressed(false)
	end)
	row.MouseLeave:Connect(function()
		setPressed(false)
	end)
	-- (a finger that lifts or slides into a scroll never produces MouseButton1Up)
	row.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setPressed(false)
		end
	end)
	H.stars(ui, true)
	return ui
end

-- (U9-8 look) a row's parts for its height: a short dock's 60 px row (name at 4, info at 30) or the 66 px one (name at 6,
-- info at 34); the badge centred on the face above the lip, the tag beside the name
function H.rowGeometry(ui, short)
	local h = short and K.ROW_H_SHORT or K.ROW_H
	local nameY, infoY = short and 4 or 6, short and 30 or 34
	ui.Name.Position = UDim2.fromOffset(70, nameY)
	ui.Info.Position = UDim2.fromOffset(70, infoY)
	ui.Blurb.Position = UDim2.fromOffset(70, infoY + 26)
	ui.Badge.Position = UDim2.fromOffset(16, math.floor((h - 4 - 42) / 2))
	ui.Stripe.Position = UDim2.fromOffset(4, nameY)
	ui.Stripe.Size = UDim2.new(0, 6, 1, -(2 * nameY + 4))
	ui.ChipY = nameY
	return h
end

-- (U9-8 look) the kit's press on a row: its parts drop K.PRESS, its lip thins by as much, and a PICK plank sinks onto
-- its own lip (H.paintTag)
function H.paintPress(ui)
	local down = ui.Pressed and K.PRESS or 0
	ui.Press.PaddingTop = UDim.new(0, down)
	local lip = ui.Root:FindFirstChild("Lip")
	if lip and lip.Visible then
		lip.Size = UDim2.new(1, 0, 0, SignKit.Px(4 - down, SignKit.LayoutScale(lip)))
	end
	if ui.TagState then
		H.paintTag(ui, ui.TagState, ui.Chip.Size.X.Offset)
	end
end

-- (kit-b U9-8) a row's name and stars get all the room left of the tag, and the tags are the full word where every row's
-- name and stars fit beside it, else each its icon alone (a phone's narrow row ran 4 / 5 stars under PICK; one column of
-- tags, all words or all icons). H.compactTags decides for the list, H.fitName sizes a row. What a row needs: the name at
-- its measured width, never under 0.66 em a letter (FredokaOne's wide capitals) (a short measure cut "Extreme" to "Ext..."), and the stars
-- as PixelIcon.Lead draws them (18 px, 2 px apart, after a 6 px gap, with room for a 0.8 screen's whole-px cells)
function H.rowWidth()
	local scale = ((U.Dock.Rect and tonumber(U.Dock.Rect.scale)) or 1) * (U.Pop and U.Pop.Scale or 1)
	local first = U.Cards[1]
	local rowW = first and first.Root.AbsoluteSize.X / math.max(0.01, scale) or 0
	return rowW >= 1 and rowW or (K.PREF_W - 60)
end

function H.compactTags(rowW)
	for _, ui in ipairs(U.Cards) do
		local n = math.max(1, math.min(5, math.floor(tonumber(ui.StarCount) or 0)))
		local size = ui.Name.TextSize
		local textW = math.max(Theme.Measure(ui.Name.Text, "Heading", size).X, #ui.Name.Text * size * 0.66)
		if math.ceil(textW) + 6 + n * 18 + (n - 1) * 2 + 10 > rowW - 70 - (K.CHIP_W + 10) - 8 then
			return true
		end
	end
	return false
end

function H.fitName(ui, rowW, compact, state, face, ink)
	local chipW = compact and K.CHIP_SMALL or K.CHIP_W
	ui.TagState = state
	H.paintTag(ui, state, chipW)
	ui.Name.Size = UDim2.new(0, math.max(40, rowW - 70 - chipW - 18), 0, 28)
	ui.ChipText.Visible = not compact
	ui.Mark.Visible = compact
	PixelIcon.Set(ui.Mark, compact and ((state == "PICKED" and "check") or (state == "LOCKED" and "lock") or "arrow") or nil, 18, ink or Theme.TextOn(face))
end

-- (kit-b U9-8) the list's height and scroll: whole rows only at both edges. The rows and the list's pads share one gap, so a
-- row that ends at the list's edge is followed by the gap (never 2 px of the next row's lip); the picked row is brought
-- into view once after opening (CanvasPosition is screen px: the design px times the dock's scale)
function H.layoutList(heights, picked)
	local avail = math.max((S.Short and K.ROW_H_SHORT or K.ROW_H) + 2 * K.ROW_GAP, U.Holder.Size.Y.Offset - 82 - K.TOP_H)
	local tops, y = {}, K.ROW_GAP
	for i, h in ipairs(heights) do
		tops[i] = y
		y = y + h + K.ROW_GAP
	end
	local total = y
	local listH = total
	if total > avail then
		-- the most rows from the top that fit, each with its gap under it. (U9-8 look) the list then ends in the MIDDLE of
		-- the last gap: a row's wood edge is drawn outside it, so a list ending at the next row's top showed that edge as a
		-- brown line along the list's bottom (and, scrolled, the row above's along its top)
		listH = K.ROW_GAP
		for _, h in ipairs(heights) do
			if listH + h + K.ROW_GAP > avail then
				break
			end
			listH = listH + h + K.ROW_GAP
		end
		listH = listH - K.ROW_GAP / 2
	end
	local pad = CloudUI.Metrics.SignPagePad
	U.List.Size = UDim2.new(1, -2 * pad, 0, listH)
	if S.ScrollTo then
		S.ScrollTo = nil
		local want = 0
		if total > listH and picked and tops[picked] then
			want = math.min(total - listH, tops[picked] - K.ROW_GAP / 2) -- (U9-8 look: from the middle of the gap above it)
		end
		local scale = (U.Dock.Rect and tonumber(U.Dock.Rect.scale)) or 1
		U.List.CanvasPosition = Vector2.new(0, math.max(0, want) * scale)
	end
end

function H.refresh()
	if not S.Built or not S.Open then
		return
	end
	U.Dock.Refresh()
	local rect = U.Dock.Rect
	if rect then
		S.Short = rect.designH < K.SHORT
	end
	local short = S.Short
	local best = H.bestTimes()
	local picked = H.picked()
	local list = ObbyLevels.List()
	local heights, pickedIndex = {}, nil
	local rowW = H.rowWidth()
	local compact = H.compactTags(rowW)
	for i, ui in ipairs(U.Cards) do
		local id = ui.Id
		local open = ObbyLevels.IsUnlocked(best, id)
		local isPicked = open and id == picked
		local t = tonumber(best[id])
		local win = H.winTokens(id)
		local parts = {}
		if t and t > 0 then
			parts[#parts + 1] = "Best " .. H.clock(t)
		end
		if win then
			parts[#parts + 1] = "Win +" .. win .. " tokens"
		end
		-- the picked row opens to show its blurb (two lines; a short screen keeps every row one height)
		local withBlurb = isPicked and not short and ui.Blurb.Text ~= ""
		heights[i] = H.rowGeometry(ui, short) + (withBlurb and K.BLURB_H or 0)
		pickedIndex = isPicked and i or pickedIndex
		ui.Root.Size = UDim2.new(1, 0, 0, heights[i])
		ui.Blurb.Visible = withBlurb
		local prev = list[i - 1] and H.diff(list[i - 1]) or nil
		-- the tag by role: a locked level a sunk well in muted ink, the picked one gold with its tick, any other open level sky
		if not open then
			ui.Info.Text = "Beat " .. tostring(prev and prev.DisplayName or "the level before") .. " to unlock"
			PixelIcon.Mark(ui.Info, "lock") -- (kit-b U7b)
			ui.Info.TextColor3 = MUTED
			ui.ChipText.Text = "LOCKED"
			PixelIcon.Mark(ui.ChipText, nil)
			H.fitName(ui, rowW, compact, "LOCKED", SIGN.Well, MUTED)
		else
			ui.Info.Text = (#parts > 0) and table.concat(parts, "  " .. G.Dot .. "  ") or "Not beaten yet"
			PixelIcon.Mark(ui.Info, nil)
			ui.Info.TextColor3 = INK
			ui.ChipText.Text = isPicked and "PICKED" or "PICK"
			PixelIcon.Mark(ui.ChipText, isPicked and "check" or nil) -- (kit-b U7b)
			H.fitName(ui, rowW, compact, ui.ChipText.Text, isPicked and SIGN.Gold or SIGN.Sky)
		end
		CloudUI.SignBlock(ui.Root, open and "Stone" or "Off", {
			Face = isPicked and SIGN.Selected or nil,
			Edge = isPicked and SIGN.Text or nil,
			EdgePx = isPicked and 3 or 2,
			LipPx = 4,
			Pad = false,
		})
		if not open then
			ui.Pressed = false -- (a locked row has no press)
		end
		H.paintPress(ui)
		ui.Name.TextColor3 = open and INK or MUTED
		H.stars(ui, open)
		ui.Root:SetAttribute("Unlocked", open)
		ui.Root:SetAttribute("Picked", isPicked)
	end
	H.layoutList(heights, pickedIndex)
	if S.Hint and os.clock() < S.Hint.Until then
		U.Footer.Text = S.Hint.Text
		U.Footer.TextColor3 = MUTED
	else
		U.Footer.Text = H.footerFor(U.Footer)
		U.Footer.TextColor3 = INK
	end
end

function H.hint(text)
	S.Hint = { Text = tostring(text), Until = os.clock() + 3 }
	H.refresh()
end

----------------------------------------------------------------------
-- the unlock toast (kit-b U9-8: a kit B card at the top right, clear of the result card and the HUD; never centred)
----------------------------------------------------------------------
function H.buildToast()
	local gui = CloudUI.NewScreenGui("NimbusObbyToast", K.TOAST_ORDER)
	U.ToastGui = gui
	local card = H.frame(gui, "UnlockToast", { Size = UDim2.fromOffset(K.TOAST_W, K.TOAST_H), Visible = false })
	-- (a portrait phone: K.TOAST_NARROW_W wide, K.TOAST_NARROW_H high, so it fits right of the menu column: H.toastSize)
	-- (U9-8 look) the read scale first, so the card's edge and lip (SignKit.Whole) follow it to whole screen px
	U.ToastScale = Util.Create("UIScale", { Name = "ReadScale", Scale = 1, Parent = card })
	CloudUI.SignBlock(card, "Stone", { EdgePx = 3, LipPx = 5, Pad = false })
	U.Toast = card
	-- the obby's mountain on a gold tile (the window's own icon), two nails holding the board up
	local tile = H.frame(card, "IconTile", { BackgroundTransparency = 0, BackgroundColor3 = SIGN.Gold, Position = UDim2.fromOffset(14, 11), Size = UDim2.fromOffset(45, 45) })
	U.ToastTile = tile
	H.edge(tile, SIGN.Wood, 2)
	H.lip(tile, SIGN.GoldLip, 4)
	local icon = PixelIcon.New(tile, Config.Icons.Obby or "mountain", 27, INK)
	icon.Position = UDim2.fromOffset(9, 7)
	SignKit.Nails(card, { Size = 4, Inset = 5 })
	U.ToastText = H.text(card, "Text", "", "Heading", 20, INK, {
		Position = UDim2.fromOffset(72, 4),
		Size = UDim2.new(1, -84, 1, -13),
		TextWrapped = true,
	})
end

-- the toast's size for this screen (design px): a portrait phone's is narrower and a line taller (the text wraps in three)
function H.toastSize()
	local narrow = H.viewport().X / math.max(0.01, U.ToastScale.Scale) < K.TOAST_NARROW
	local w, h = narrow and K.TOAST_NARROW_W or K.TOAST_W, narrow and K.TOAST_NARROW_H or K.TOAST_H
	U.Toast.Size = UDim2.fromOffset(w, h)
	U.ToastTile.Position = UDim2.fromOffset(14, math.floor((h - 5 - 45) / 2)) -- (centred on the face above the 5 px lip)
	return w, h
end

-- what the toast keeps clear of, in this gui's px (an IgnoreGuiInset = false ScreenGui): the HUD's currency strips, match
-- panel, party panel and vitals, the menu column, the gift and the boost chips under it, NimbusNotify's result card (at its
-- final x: it slides in) and its toasts, the touch buttons
function H.toastAvoid()
	local out = {}
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return out
	end
	local okInset, inset = pcall(function()
		return game:GetService("GuiService"):GetGuiInset().Y
	end)
	inset = (okInset and tonumber(inset)) or 0
	local function shown(o)
		local cur = o
		while cur and not cur:IsA("LayerCollector") do
			if cur:IsA("GuiObject") and not cur.Visible then
				return false
			end
			cur = cur.Parent
		end
		return cur ~= nil and cur.Enabled ~= false
	end
	local function add(o, left)
		if o and o:IsA("GuiObject") and o.AbsoluteSize.X > 4 and o.AbsoluteSize.Y > 4 and shown(o) then
			local p, s = o.AbsolutePosition, o.AbsoluteSize
			local g = o:FindFirstAncestorWhichIsA("LayerCollector")
			local dy = (g and g:IsA("ScreenGui") and g.IgnoreGuiInset) and -inset or 0
			local x0 = left or p.X
			out[#out + 1] = { X = x0, Y = p.Y + (dy or 0), R = math.max(x0 + 1, left and H.viewport().X or (p.X + s.X)), B = p.Y + s.Y + (dy or 0) }
		end
	end
	local hud = pg:FindFirstChild("NimbusHud")
	for _, name in ipairs({ "Currency", "MatchPanel", "PartyPanel", "Vitals" }) do
		add(hud and hud:FindFirstChild(name, true))
	end
	for _, spec in ipairs({ { "NimbusMenu", "MenuColumn" }, { "NimbusDaily", "GiftsButton" }, { "NimbusBoosts", "Chip_Cash" }, { "NimbusBoosts", "Chip_Xp" } }) do
		local g = pg:FindFirstChild(spec[1])
		add(g and g:FindFirstChild(spec[2], true))
	end
	local notify = pg:FindFirstChild("NimbusNotify")
	local card = notify and notify:FindFirstChild("ResultCard", true)
	local left = notify and tonumber(notify:GetAttribute("ResultCardLeft")) or 0
	add(card, left > 0 and left or nil)
	local stack = notify and notify:FindFirstChild("ToastStack", true)
	for _, t in ipairs(stack and stack:GetChildren() or {}) do
		add(t)
	end
	local mobile = pg:FindFirstChild("MobileControls")
	if mobile and mobile:IsA("ScreenGui") and mobile.Enabled then
		for _, d in ipairs(mobile:GetDescendants()) do
			if d:IsA("GuiButton") then
				add(d)
			end
		end
	end
	return out, inset
end

-- the toast's room at (x, y) for its size w x h (gui px): on the screen, never in the lower quarter, above the middle band of
-- the screen where it reaches into it sideways (NotifyController's rule), clear of every rect of H.toastAvoid
function H.toastFits(x, y, w, h, avoid, inset)
	local vp = H.viewport()
	local side = H.touchOnly() and K.TOUCH_EDGE or K.EDGE
	local r, b = x + w, y + h
	local lowest = (vp.Y - inset) * 0.72
	if x < vp.X * 0.65 and r > vp.X * 0.35 then
		lowest = math.min(lowest, vp.Y * 0.35 - 6 - inset)
	end
	if not (x >= side - 0.5 and y >= K.EDGE - 4 and r <= vp.X - side + 0.5 and b <= lowest) then
		return false
	end
	local g = K.TOAST_GAP / 2
	for _, a in ipairs(avoid) do
		if x < a.R + g and a.X < r + g and y < a.B + g and a.Y < b + g then
			return false
		end
	end
	return true
end

-- where the toast goes (its top-left, gui px), or nil when nothing has room: at the right edge under the currency strips,
-- else left of the result card, else under it, else left of the strips in the top row
function H.toastSpot()
	local vp = H.viewport()
	local k = U.ToastScale.Scale
	local w, h = H.toastSize()
	w, h = w * k, h * k
	local avoid, inset = H.toastAvoid()
	local side = H.touchOnly() and K.TOUCH_EDGE or K.EDGE
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("NimbusHud")
	local strips = hud and tonumber(hud:GetAttribute("TopRightBottom")) or 0
	local stripsLeft = hud and tonumber(hud:GetAttribute("TopRightLeft")) or 0
	local top = math.max(K.EDGE, strips > 0 and (strips + K.TOAST_GAP) or K.EDGE)
	local right = vp.X - side - w
	local spots = { { right, top } }
	local notify = pg and pg:FindFirstChild("NimbusNotify")
	local cardLeft = notify and tonumber(notify:GetAttribute("ResultCardLeft")) or 0
	local card = notify and notify:FindFirstChild("ResultCard", true)
	if cardLeft > 0 then
		spots[#spots + 1] = { cardLeft - K.TOAST_GAP - w, top }
		spots[#spots + 1] = { cardLeft - K.TOAST_GAP - w, K.EDGE }
		if card and card:IsA("GuiObject") then
			spots[#spots + 1] = { right, card.AbsolutePosition.Y + card.AbsoluteSize.Y + K.TOAST_GAP }
		end
	end
	if stripsLeft > 0 then
		spots[#spots + 1] = { stripsLeft - K.TOAST_GAP - w, K.EDGE }
	end
	for _, s in ipairs(spots) do
		local x, y = math.floor(s[1]), math.floor(s[2])
		if H.toastFits(x, y, w, h, avoid, inset) then
			return UDim2.fromOffset(x, y)
		end
	end
	return nil
end

-- shows the toast for K.TOAST_SECONDS once it has room (waiting up to K.TOAST_WAIT, then at the top right anyway). While it
-- shows it keeps its room: a panel that slides in under it (the match panel, a Notify toast) moves it to another spot, or
-- takes it away until there is room again (the time it was hidden does not count)
function H.toast(text)
	if not U.Toast then
		return
	end
	S.ToastToken = (S.ToastToken or 0) + 1
	local mine = S.ToastToken
	U.ToastText.Text = tostring(text)
	U.ToastScale.Scale = Theme.ScreenFactor()
	U.Toast.Visible = false
	local deadline = os.clock() + K.TOAST_WAIT
	task.spawn(function()
		task.wait() -- (the result card of the same MatchResult is built by the next frame)
		local shownFor, shown = 0, false
		while S.ToastToken == mine and shownFor < K.TOAST_SECONDS do
			if shown and not U.Toast.Visible then
				return -- (taken away from outside)
			end
			local k = U.ToastScale.Scale
			local avoid, inset = H.toastAvoid()
			local pos = U.Toast.Position
			if not (shown and H.toastFits(pos.X.Offset, pos.Y.Offset, U.Toast.Size.X.Offset * k, U.Toast.Size.Y.Offset * k, avoid, inset)) then
				local spot = H.toastSpot()
				if not spot and os.clock() >= deadline then
					spot = UDim2.fromOffset(math.floor(H.viewport().X - K.EDGE - U.Toast.Size.X.Offset * k), K.EDGE)
				end
				if spot then
					U.Toast.Position = spot
				end
				shown = spot ~= nil
				U.Toast.Visible = shown
			end
			local t0 = os.clock()
			task.wait(K.TICK)
			if shown then
				shownFor = shownFor + (os.clock() - t0)
			end
		end
		if S.ToastToken == mine then
			U.Toast.Visible = false
		end
	end)
end

----------------------------------------------------------------------
-- public API
----------------------------------------------------------------------
function H.onBack(_name, inputState)
	if inputState == Enum.UserInputState.Begin and S.Open then
		ObbyController.Close()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

function H.syncBack()
	if S.Open == S.BackBound then
		return
	end
	S.BackBound = S.Open
	if S.Open then
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, H.onBack, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		end)
	else
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

-- (kit-b U9-8) on a touch screen Roblox's thumbstick and jump button go while the picker is open (the jump button sat on the
-- lower rows of a landscape phone's dock) and come back as they were: MenuController keeps the one owner set (looked up at
-- open / close time: no require cycle), as the Dungeon and the Arena do
function H.syncTouch()
	local want = S.Open == true and H.touchOnly()
	if want == (S.TouchOff == true) then
		return
	end
	S.TouchOff = want
	local menu = H.controller("MenuController")
	if menu and type(menu.SetTouchHidden) == "function" then
		H.safe("touch", menu.SetTouchHidden, "Obby", want)
	end
end

function ObbyController.Open(levelId, portal)
	if not initialized then
		ObbyController.Init()
	end
	if not U.Gui then
		return false
	end
	if LocalPlayer and LocalPlayer:GetAttribute(Config.Attr.InMatch) == true then
		return false
	end
	H.build()
	S.AtPortal = (typeof(portal) == "Instance") and portal or nil
	S.OpenedLocked = H.locked()
	local was = S.Open
	if not was then
		for _, name in ipairs({ "MenuController", "IndexController", "FusionController", "CareController", "ArenaController", "DungeonController" }) do
			local mod = H.controller(name)
			if mod and type(mod.Close) == "function" then
				pcall(mod.Close)
			end
		end
	end
	S.Open = true
	S.Token = S.Token + 1
	H.syncBack()
	H.syncTouch()
	U.Holder.Visible = true
	if not was then
		S.ScrollTo = true -- (kit-b U9-8) the picked level into view once
		U.Pop.Scale = 0.9
		H.tween(U.Pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	if type(levelId) == "string" and ObbyLevels.IndexOf(levelId) then
		ObbyController.Pick(levelId)
	end
	H.refresh()
	if not was then
		ObbyController.Opened:Fire("Obby")
	end
	return true
end

function ObbyController.Close()
	if not S.Open then
		return
	end
	S.Open = false
	S.AtPortal = nil
	S.Token = S.Token + 1
	local mine = S.Token
	H.syncBack()
	H.syncTouch()
	if U.Pop then
		H.tween(U.Pop, 0.12, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(0.13, function()
		if S.Token == mine and not S.Open and U.Holder then
			U.Holder.Visible = false
			U.Pop.Scale = 1
		end
	end)
	ObbyController.Closed:Fire("Obby")
end

function ObbyController.IsOpen()
	return S.Open == true
end

function ObbyController.Pick(levelId)
	if type(levelId) ~= "string" or not ObbyLevels.IndexOf(levelId) then
		return false
	end
	if not ObbyLevels.IsUnlocked(H.bestTimes(), levelId) then
		local list = ObbyLevels.List()
		local i = ObbyLevels.IndexOf(levelId) or 1
		H.hint("Beat " .. tostring(H.diff(list[math.max(1, i - 1)]).DisplayName) .. " to unlock " .. tostring(H.diff(levelId).DisplayName))
		return false
	end
	if S.Party and not H.isLeader() then
		H.hint("The party leader picks the level")
		return false
	end
	local now = os.clock()
	if S.LastFire[levelId] and now - S.LastFire[levelId] < K.FIRE_GAP then
		return false
	end
	if not U.Remote then
		local ok, remote = pcall(Remotes.Get, "ObbyPick")
		U.Remote = ok and remote or nil
	end
	if not U.Remote then
		return false
	end
	S.LastFire[levelId] = now
	S.Want, S.WantAt = levelId, now
	pcall(function()
		U.Remote:FireServer(levelId)
	end)
	H.refresh()
	return true
end

function ObbyController.GetState()
	local best = H.bestTimes()
	local levels = {}
	local picked = H.picked()
	for _, id in ipairs(ObbyLevels.List()) do
		local open = ObbyLevels.IsUnlocked(best, id)
		levels[#levels + 1] = { Id = id, Unlocked = open, Picked = open and id == picked, Best = tonumber(best[id]) }
	end
	return { Window = S.Open and "Obby" or nil, Picked = picked, Highest = H.highest(), Levels = levels, Footer = H.footer() }
end

----------------------------------------------------------------------
-- server messages + Init
----------------------------------------------------------------------
function H.onParty(state)
	if type(state) == "table" and (state.PortalId == "Obby" or state.PortalId == nil) and type(state.Players) == "table" then
		S.Party = state
	else
		S.Party = nil
	end
	H.refresh()
end

-- a won match that raised the highest open level: "Extreme unlocked! Pick it at the Obby portal."
function H.onMatchResult(result)
	if type(result) ~= "table" or result.Won ~= true then
		return
	end
	S.WonAt = os.clock()
	local list = ObbyLevels.List()
	local before = S.Highest or H.highest()
	local index = ObbyLevels.IndexOf(result.DifficultyId) or 0
	local after = math.max(before, math.min(#list, index + 1))
	if after > before then
		S.Highest = after
		H.toast(tostring(H.diff(list[after]).DisplayName) .. " unlocked! Pick it at the Obby portal.")
	end
end

-- the gate's ObbyPrompt (OpenPanel = "Obby"): this controller opens the picker itself
function H.hookPrompt()
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
		if typeof(prompt) == "Instance" and prompt:IsA("ProximityPrompt") and prompt:GetAttribute("OpenPanel") == "Obby" then
			H.safe("prompt", ObbyController.Open, nil, prompt.Parent)
		end
	end)
end

function ObbyController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)
	U.Gui = CloudUI.NewScreenGui("NimbusObby", K.DISPLAY_ORDER)
	H.buildToast()
	S.Highest = H.highest()
	State.Changed:Connect(function()
		-- the saved wins decide (a new profile can also lower it); a sync right after a won match that raised it
		-- (the MatchResult may come after the sync) shows the unlock toast here
		local now = H.highest()
		if S.Highest and now > S.Highest and os.clock() - (S.WonAt or -100) < 15 then
			local list = ObbyLevels.List()
			H.toast(tostring(H.diff(list[now]).DisplayName) .. " unlocked! Pick it at the Obby portal.")
		end
		S.Highest = now
		H.safe("State.Changed", H.refresh)
	end)
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		H.safe("relayout", H.refresh)
	end)
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal((Config.Attr and Config.Attr.ObbyLevel) or "ObbyLevel"):Connect(function()
			S.Want = nil
			H.safe("ObbyLevel", H.refresh)
		end)
		LocalPlayer:GetAttributeChangedSignal("PortalLocked"):Connect(function()
			-- stepping onto the pad closes a picker opened at the gate (the party panel's CHANGE reopens it)
			if S.Open and H.locked() and not S.OpenedLocked then
				ObbyController.Close()
			end
		end)
		LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if LocalPlayer:GetAttribute(Config.Attr.InMatch) == true then
				ObbyController.Close()
			end
		end)
	end
	UserInputService.InputBegan:Connect(function(input)
		if S.Open and input.KeyCode == Enum.KeyCode.Escape then
			ObbyController.Close()
		end
	end)
	H.hookPrompt()
	task.spawn(function()
		local okOpen, openRemote = pcall(Remotes.Get, "OpenPanel")
		if okOpen and openRemote then
			openRemote.OnClientEvent:Connect(function(panelId, args)
				if type(panelId) == "string" and panelId:lower() == "obby" then
					args = type(args) == "table" and args or {}
					H.safe("OpenPanel", ObbyController.Open, args.Level, H.portal())
				end
			end)
		end
		local okParty, partyRemote = pcall(Remotes.Get, "PartyState")
		if okParty and partyRemote then
			partyRemote.OnClientEvent:Connect(function(state)
				H.safe("PartyState", H.onParty, state)
			end)
		end
		local okResult, resultRemote = pcall(Remotes.Get, "MatchResult")
		if okResult and resultRemote then
			resultRemote.OnClientEvent:Connect(function(result)
				H.safe("MatchResult", H.onMatchResult, result)
			end)
		end
	end)
	task.defer(function()
		for _, spec in ipairs({ { "MenuController", "WindowOpened" }, { "IndexController", "Opened" }, { "FusionController", "Opened" },
			{ "CareController", "Opened" }, { "ArenaController", "Opened" }, { "DungeonController", "Opened" } }) do
			local mod = H.controller(spec[1])
			local signal = mod and mod[spec[2]]
			if type(signal) == "table" and type(signal.Connect) == "function" then
				signal:Connect(function(windowId)
					if windowId ~= "Obby" then
						ObbyController.Close()
					end
				end)
			end
		end
	end)
	local nextTick = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextTick or not S.Open then
			return
		end
		nextTick = now + K.TICK
		local at = H.positionOf(S.AtPortal)
		local pos = H.rootPosition()
		if at and pos and (Vector3.new(pos.X - at.X, 0, pos.Z - at.Z)).Magnitude > K.WALK_AWAY then
			ObbyController.Close()
			return
		end
		H.safe("tick", H.refresh)
	end)
end

return ObbyController
