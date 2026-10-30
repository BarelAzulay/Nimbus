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
-- What the player sees: a NeonKit side panel (560 x 640 design px, Blue; docked right on landscape screens, a bottom sheet on
-- portrait phones) with the five levels of shared/ObbyLevels (Easy, Medium, Hard, Extreme, Saint): stars, name, blurb,
-- "Best 3:42", "+35 tokens on a win" and LOCKED "Beat Medium to unlock" / PICK / PICKED. A level is open when the one
-- before it was beaten (ObbyLevels.IsUnlocked on State's Stats.BestTimes; the server decides). The footer says what happens
-- next: "Step on the pad to start" or "Party on the pad: Hard 2/4 - step on to join" (the gate's PartyLevel / PartyCount /
-- PartyMax attributes), or the own party's line while the player waits on the pad. It closes when the player walks 40
-- studs away from the gate or steps onto the pad (a window opened there), with Esc / gamepad B / the red X, or when
-- another window opens. After a won match that unlocks the next level a side toast says "Extreme unlocked! Pick it at
-- the Obby portal."
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
	PREF_H = 640,
	SHORT = 520, -- docked lower than this: one-line cards (landscape phones)
	CARD_H = 96,
	CARD_H_SHORT = 58,
	FIRE_GAP = 0.3,
	WALK_AWAY = 40,
	TICK = 0.25,
	TOAST_SECONDS = 6,
	BACK_ACTION = "NimbusObbyBack",
}

local Colors = Theme.Colors
local NEON = Theme.Neon or {}
local WHITE = Colors.White
local INK = Colors.PanelInk or Color3.fromRGB(8, 10, 28)
local C = {
	Accent = Theme.NeonColor and Theme.NeonColor("Obby") or Color3.fromRGB(64, 170, 255),
	Gold = NEON.Gold or Color3.fromRGB(255, 196, 64),
	Green = NEON.Green or Color3.fromRGB(72, 224, 120),
	Grey = NEON.Grey or Color3.fromRGB(150, 166, 204),
	Muted = Color3.fromRGB(176, 184, 214),
	Row = Color3.fromRGB(30, 36, 78),
	RowDark = Color3.fromRGB(18, 22, 52),
	Token = Colors.Token or Color3.fromRGB(255, 210, 90),
}

local G = {
	Star = "\226\152\133",
	StarOff = "\226\152\134",
	Lock = "\240\159\148\146",
	Check = "\226\156\147",
	Cloud = "\226\152\129",
	Clock = "\226\143\177",
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
	Theme.Style(label, role or "Body", { Size = size, Color = color or WHITE, Stroke = 1 })
	Theme.TextOutline(label, 1.5, INK, 0.1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	label.Parent = parent
	return label
end

function H.corner(parent, px)
	return Util.Create("UICorner", { CornerRadius = UDim.new(0, px or 10), Parent = parent })
end

function H.stroke(parent, color, thickness, transparency)
	return Util.Create("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
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

function H.stars(n)
	n = math.max(0, math.min(5, math.floor(tonumber(n) or 0)))
	return string.rep(G.Star, math.max(1, n))
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

function H.footer()
	if S.Party then
		local d = H.diff(S.Party.Level)
		local count = #(type(S.Party.Players) == "table" and S.Party.Players or {})
		local line = "On the pad: " .. tostring(d.DisplayName) .. " " .. count .. "/" .. tostring(S.Party.Max or 4)
		if H.isLeader() then
			return line .. " " .. G.Dot .. " tap a level to change it"
		end
		return line .. " " .. G.Dot .. " the leader picks the level"
	end
	local portal = H.portal()
	local n = portal and tonumber(portal:GetAttribute("PartyCount")) or 0
	if n > 0 then
		local level = portal:GetAttribute("PartyLevel")
		local d = H.diff(level)
		return "Party on the pad: " .. tostring(d.DisplayName) .. " " .. n .. "/" .. tostring(portal:GetAttribute("PartyMax") or 4) .. " - step on to join"
	end
	return "Step on the pad to start"
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
		Category = "Obby",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		OnClose = function()
			ObbyController.Close()
		end,
		Parent = holder,
	})
	U.Panel = panel
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel.Root })
	local content = panel.Content
	U.List = Instance.new("ScrollingFrame")
	U.List.Name = "Levels"
	U.List.BackgroundTransparency = 1
	U.List.BorderSizePixel = 0
	U.List.ScrollBarThickness = 8
	U.List.ScrollBarImageColor3 = C.Accent
	U.List.ScrollingDirection = Enum.ScrollingDirection.Y
	U.List.AutomaticCanvasSize = Enum.AutomaticSize.Y
	U.List.CanvasSize = UDim2.new(0, 0, 0, 0)
	U.List.Size = UDim2.new(1, 0, 1, -38)
	U.List.Position = UDim2.fromOffset(0, 38)
	U.List.Parent = content
	Util.Create("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), Parent = U.List })
	Util.Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = U.List })
	U.Cards = {}
	for i, id in ipairs(ObbyLevels.List()) do
		U.Cards[i] = H.card(i, id)
	end
	-- what happens next, right under the title (a phone sheet's bottom edge sits under Roblox's touch buttons)
	U.Footer = H.text(content, "Footer", "", "Heading", 19, C.Gold, {
		Position = UDim2.new(0, 4, 0, 0),
		Size = UDim2.new(1, -8, 0, 32),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

function H.card(i, id)
	local d = H.diff(id)
	local color = d.Color or C.Accent
	local row = Instance.new("TextButton")
	row.Name = "Level_" .. id
	row.AutoButtonColor = false
	row.Text = ""
	row.BorderSizePixel = 0
	row.BackgroundColor3 = C.Row
	row.Size = UDim2.new(1, 0, 0, K.CARD_H)
	row.LayoutOrder = i
	row.Parent = U.List
	H.corner(row, 12)
	local rim = H.stroke(row, Theme.Darken(color, 0.3), 2, 0.1)
	local stripe = H.frame(row, "Stripe", { BackgroundTransparency = 0, BackgroundColor3 = color, Position = UDim2.fromOffset(5, 8), Size = UDim2.new(0, 6, 1, -16) })
	H.corner(stripe, 3)
	local name = H.text(row, "LevelName", tostring(d.DisplayName or id), "Heading", 23, WHITE, { Position = UDim2.fromOffset(20, 8), Size = UDim2.new(0, 150, 0, 30) })
	local stars = H.text(row, "Stars", H.stars(d.Stars), "Heading", 20, C.Gold, { Position = UDim2.fromOffset(170, 8), Size = UDim2.new(1, -310, 0, 30), TextTruncate = Enum.TextTruncate.AtEnd })
	local blurb = H.text(row, "Blurb", tostring(d.Blurb or ""), "Body", 18, C.Muted, { Position = UDim2.fromOffset(20, 38), Size = UDim2.new(1, -150, 0, 24), TextTruncate = Enum.TextTruncate.AtEnd })
	local info = H.text(row, "Info", "", "Body", 18, WHITE, { Position = UDim2.fromOffset(20, 64), Size = UDim2.new(1, -150, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd })
	local chip = H.frame(row, "Chip", { BackgroundTransparency = 0, BackgroundColor3 = C.RowDark, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(118, 40) })
	H.corner(chip, 20)
	local chipRim = H.stroke(chip, color, 2, 0)
	local chipText = H.text(chip, "Text", "", "Button", 19, WHITE, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	row.Activated:Connect(function()
		H.safe("pick", ObbyController.Pick, id)
	end)
	return { Id = id, Root = row, Rim = rim, Name = name, Stars = stars, Blurb = blurb, Info = info, Chip = chip, ChipRim = chipRim, ChipText = chipText, Color = color }
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
	for i, ui in ipairs(U.Cards) do
		local id = ui.Id
		local open = ObbyLevels.IsUnlocked(best, id)
		local isPicked = open and id == picked
		local t = tonumber(best[id])
		local win = H.winTokens(id)
		local parts = {}
		if t and t > 0 then
			parts[#parts + 1] = G.Clock .. " Best " .. H.clock(t)
		end
		if win then
			parts[#parts + 1] = "Win +" .. win .. " " .. G.Cloud .. " tokens"
		end
		ui.Root.Size = UDim2.new(1, 0, 0, short and K.CARD_H_SHORT or K.CARD_H)
		ui.Blurb.Visible = not short
		ui.Name.Position = UDim2.fromOffset(20, short and 2 or 8)
		ui.Stars.Position = UDim2.fromOffset(170, short and 2 or 8)
		ui.Info.Position = UDim2.fromOffset(20, short and 30 or 64)
		ui.Info.Size = UDim2.new(1, -150, 0, short and 24 or 26)
		local prev = list[i - 1] and H.diff(list[i - 1]) or nil
		if not open then
			ui.Info.Text = G.Lock .. " Beat " .. tostring(prev and prev.DisplayName or "the level before") .. " to unlock"
			ui.Info.TextColor3 = C.Muted
			ui.ChipText.Text = "LOCKED"
			ui.ChipRim.Color = C.Grey
			ui.ChipText.TextColor3 = C.Muted
		else
			ui.Info.Text = (#parts > 0) and table.concat(parts, "  " .. G.Dot .. "  ") or "Not beaten yet"
			ui.Info.TextColor3 = WHITE
			ui.ChipText.Text = isPicked and (G.Check .. " PICKED") or "PICK"
			ui.ChipRim.Color = isPicked and C.Green or ui.Color
			ui.ChipText.TextColor3 = WHITE
		end
		ui.Name.TextColor3 = open and WHITE or C.Muted
		ui.Stars.TextColor3 = open and C.Gold or C.Grey
		ui.Root.BackgroundColor3 = isPicked and Theme.Lighten(C.Row, 0.14) or (open and C.Row or C.RowDark)
		ui.Rim.Color = isPicked and C.Accent or Theme.Darken(ui.Color, 0.3)
		ui.Rim.Thickness = isPicked and 3 or 2
		ui.Root:SetAttribute("Unlocked", open)
		ui.Root:SetAttribute("Picked", isPicked)
	end
	if S.Hint and os.clock() < S.Hint.Until then
		U.Footer.Text = S.Hint.Text
		U.Footer.TextColor3 = C.Muted
	else
		U.Footer.Text = H.footer()
		U.Footer.TextColor3 = C.Gold
	end
end

function H.hint(text)
	S.Hint = { Text = tostring(text), Until = os.clock() + 3 }
	H.refresh()
end

----------------------------------------------------------------------
-- the unlock toast (right edge, under the toast column; never centred)
----------------------------------------------------------------------
function H.buildToast()
	local gui = CloudUI.NewScreenGui("NimbusObbyToast", K.TOAST_ORDER)
	U.ToastGui = gui
	local card = NeonKit.Card({ Name = "UnlockToast", Size = UDim2.fromOffset(380, 64), Color = C.Gold, Glow = true, Parent = gui })
	card.Root.AnchorPoint = Vector2.new(1, 0)
	card.Root.Position = UDim2.new(1, -12, 0.3, 0)
	card.Root.Visible = false
	U.Toast = card
	U.ToastScale = Util.Create("UIScale", { Name = "ReadScale", Scale = 1, Parent = card.Root })
	U.ToastText = H.text(card.Body, "Text", "", "Heading", 20, WHITE, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -24, 1, 0), TextWrapped = true })
end

function H.toast(text)
	if not U.Toast then
		return
	end
	S.ToastToken = (S.ToastToken or 0) + 1
	local mine = S.ToastToken
	U.ToastText.Text = tostring(text)
	U.ToastScale.Scale = Theme.ScreenFactor()
	-- phones: right under the top bar (the screen's middle stays clear for the result card); desktops: a third down
	local camera = Workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local phone = math.min(vp.X, vp.Y) < 500
	U.Toast.Root.Position = phone and UDim2.new(1, -12, 0, 8) or UDim2.new(1, -12, 0.3, 0)
	U.Toast.Root.Visible = true
	task.delay(K.TOAST_SECONDS, function()
		if S.ToastToken == mine and U.Toast then
			U.Toast.Root.Visible = false
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
	U.Holder.Visible = true
	if not was then
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
