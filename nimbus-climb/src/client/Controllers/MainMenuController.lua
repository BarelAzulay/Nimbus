-- MainMenuController: the main menu BEFORE spawning, the settings / updates / credits windows and the hand-off from
-- the loading screen (ARCHITECTURE_V3.md "Phase 5 build contract" 7.1-7.3; judge M7 / C17).
--
-- With Config.MainMenu.Enabled:
--   * The server holds the character until PLAY (PlayerService: MenuPlay or the 90 s fallback), so there is no
--     character behind the menu. Until PLAY every ScreenGui in PlayerGui that is not in UiGate.ALLOW (NimbusLoading,
--     NimbusMainMenu, NimbusNotify) is kept Enabled = false: the ones there now and any added later (ChildAdded); an
--     owner that switches its gui on meanwhile gets it back on at PLAY (its wish is remembered).
--   * The camera is Scriptable and orbits the Gate Court (centre = Lobby.Origin + GateArcRadius towards GateFacing;
--     Config.MainMenu OrbitRadius 90, OrbitHeight 38, OrbitPeriod 60 s; RenderStepped while the menu is up only).
--   * The loading screen (NimbusLoading) is faded (0.4 s) and destroyed once its Done attribute is true.
--   * PLAY (button, Enter / keypad Enter, gamepad A): MenuPlay fired once per session (no args), wait for the
--     character (<= 5 s, then go on anyway), 0.35 s fade, camera Custom on the humanoid, the guis back, UiGate.MarkPlayed().
--     Shown once per session; respawns never show it again. DevController's /menu reopens it (Open(): client-side
--     only, the character stays, MenuPlay is never sent again).
-- With Enabled false: UiGate.MarkPlayed() at once, nothing gated (the loading screen fades by itself).
-- Always: GraphicsQuality.Init() and SoundFx.Music(SoundFx.Wanted()) (Lobby unless a battle / dungeon layer is on).
--
-- Layout (NeonKit; design px of a 1080p screen under one UIScale clamp(H / 1080, 0.8, 1.25)): a left column on
-- landscape screens (x = 60, <= 0.42 W), a centred column on portrait ones: logo NIMBUS / CLIMB, the tag line, the
-- "NEW" update ribbon, PLAY (Primary Green, 76 tall), SETTINGS (Blue outline) + UPDATES (Purple outline with a NEW
-- badge while UpdateNotes.Latest > Settings.SeenNotes), a dark gradient over the world so the text reads, and a
-- version + CREDITS chip bottom-right.
-- Windows (docked by NeonKit.Dock: right side panel / bottom sheet):
--   SETTINGS  Music and Sound (11 steps 0..10, - / + and the step segments), Graphics (Auto / Low / High chips),
--             Camera shake (ON / OFF), Mouse lock (ON / OFF, keyboard + mouse devices only; the L key toggles it too);
--             applied at once through ClientSettings.Set (sent after a 0.4 s debounce)
--   UPDATES   UpdateNotes.Notes newest first; opening it sends SettingsSet("SeenNotes", UpdateNotes.Latest)
--   CREDITS   UpdateNotes.Credits
-- MouseLock (client/MouseLock.lua, dungeon-fixes decision 6): Init starts it (idempotent); the menu screen is a hold
-- ("MainMenu", from Open until the PLAY fade ends); the windows are holds through NeonKit.Dock.
--
-- Public: Init(), Open(), Play(), IsOpen(), OpenSettings(), OpenUpdates(), OpenCredits(), CloseWindows(), Window()
-- Plain Lua 5.1-compatible syntax only; fonts only through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local UI = Client:WaitForChild("UI")
local NeonKit = require(UI:WaitForChild("NeonKit"))
local CloudUI = require(UI:WaitForChild("CloudUI"))
local UiGate = require(Client:WaitForChild("UiGate"))
local ClientSettings = require(Client:WaitForChild("ClientSettings"))

local MainMenuController = {}

local K = {
	GUI = "NimbusMainMenu",
	ORDER = 40, -- above the HUD / windows (<= 30), below the loading screen (100)
	COL_W = 500,
	MARGIN = 60,
	PLAY_H = 76,
	BTN_H = 58,
	FADE = 0.35,
	LOADING_FADE = 0.4,
	CHAR_WAIT = 5,
	ACTION = "NimbusMenuPlay",
	WIN_W = 520,
	WIN_H = 640,
	NEW_GOLD = Theme.Neon.Gold,
	INK = Theme.Colors.PanelInk or Color3.fromRGB(8, 10, 28),
	WHITE = Color3.new(1, 1, 1),
	GLYPH_MUSIC = "\240\159\142\181",
	GLYPH_SOUND = "\240\159\148\138",
	GLYPH_GFX = "\226\156\168",
	GLYPH_SHAKE = "\240\159\147\183",
	GLYPH_MOUSE = "\240\159\142\175",
	MOUSE_HOLD = "MainMenu",
	DOT = "  \226\128\162  ",
}

-- state (tests read it through MainMenuController._M)
local M = {
	Started = false,
	Enabled = false,
	Open = false, -- the menu screen is up
	Playing = false, -- a PLAY is in progress
	SentPlay = false, -- MenuPlay fired (once per session)
	Gui = nil,
	Menu = nil, -- the full-screen menu frame
	Ui = {},
	Win = { Name = nil, Holder = nil, Dock = nil, Panel = nil },
	Gate = { On = false, Wanted = {}, Conns = {}, AddConn = nil },
	Orbit = { Conn = nil, T = 0 },
	Mods = {},
	Notes = nil,
	Settings = { Rows = {} },
	MouseHeld = false, -- the "MainMenu" MouseLock hold is on
}
MainMenuController._M = M

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local H = {}

function H.safe(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[MainMenuController] " .. label .. ": " .. tostring(err))
	end
	return ok, err
end

function H.optional(parent, name)
	local inst = parent and parent:FindFirstChild(name)
	if not inst then
		return nil
	end
	local ok, mod = pcall(require, inst)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

function H.mod(name)
	if M.Mods[name] == nil then
		M.Mods[name] = H.optional(Client, name) or H.optional(Client:FindFirstChild("Controllers"), name) or false
	end
	return M.Mods[name] or nil
end

function H.notes()
	if M.Notes == nil then
		M.Notes = H.optional(Shared, "UpdateNotes") or false
	end
	return M.Notes or nil
end

function H.sound(name)
	local SoundFx = H.mod("SoundFx")
	if SoundFx and type(SoundFx.Play) == "function" then
		pcall(SoundFx.Play, name)
	end
end

function H.frame(name, props, parent)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for key, value in pairs(props or {}) do
		f[key] = value
	end
	f.Parent = parent
	return f
end

function H.label(name, text, role, size, props, parent)
	local outline = props.Outline or 2
	local l = Theme.Label(text, role, {
		Size = size,
		Stroke = 1,
		Outline = outline > 0 and outline or nil,
		OutlineColor = K.INK,
		Color = props.Color,
	})
	l.Name = name
	for key, value in pairs(props) do
		if key ~= "Outline" and key ~= "Color" then
			l[key] = value
		end
	end
	l.Parent = parent
	return l
end

function H.corner(parent, px)
	return Util.Create("UICorner", { CornerRadius = px and UDim.new(0, px) or UDim.new(1, 0), Parent = parent })
end

function H.viewport()
	local camera = Workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if vp.X < 2 or vp.Y < 2 then
		vp = Vector2.new(1920, 1080)
	end
	return vp
end

function H.playerGui()
	return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

function H.menuCfg()
	return type(Config.MainMenu) == "table" and Config.MainMenu or {}
end

----------------------------------------------------------------------
-- the gate: every ScreenGui outside UiGate.ALLOW is off until PLAY
----------------------------------------------------------------------
local Gate = {}

function Gate.track(g)
	local G = M.Gate
	if not G.On or not g:IsA("ScreenGui") or UiGate.IsAllowed(g.Name) or G.Wanted[g] ~= nil then
		return
	end
	G.Wanted[g] = g.Enabled
	g.Enabled = false
	G.Conns[g] = g:GetPropertyChangedSignal("Enabled"):Connect(function()
		if G.On and g.Enabled then
			G.Wanted[g] = true -- its owner switched it on: remember, keep it off until PLAY
			g.Enabled = false
		end
	end)
end

function Gate.close()
	local G = M.Gate
	if G.On then
		return
	end
	G.On = true
	local pg = H.playerGui()
	if not pg then
		return
	end
	for _, g in ipairs(pg:GetChildren()) do
		Gate.track(g)
	end
	G.AddConn = pg.ChildAdded:Connect(function(child)
		Gate.track(child)
	end)
end

function Gate.open()
	local G = M.Gate
	G.On = false
	if G.AddConn then
		G.AddConn:Disconnect()
		G.AddConn = nil
	end
	for g, conn in pairs(G.Conns) do
		conn:Disconnect()
		G.Conns[g] = nil
	end
	for g, want in pairs(G.Wanted) do
		if g.Parent then
			g.Enabled = want
		end
		G.Wanted[g] = nil
	end
end

----------------------------------------------------------------------
-- the camera orbit around the Gate Court
----------------------------------------------------------------------
local Orbit = {}

function Orbit.centre()
	local lobby = type(Config.Lobby) == "table" and Config.Lobby or {}
	local origin = typeof(lobby.Origin) == "Vector3" and lobby.Origin or Vector3.new(0, 300, 0)
	local a = math.rad(tonumber(lobby.GateFacing) or 90)
	local r = tonumber(lobby.GateArcRadius) or 118
	return origin + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

function Orbit.place(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cfg = H.menuCfg()
	local period = tonumber(cfg.OrbitPeriod) or 60
	local radius = tonumber(cfg.OrbitRadius) or 90
	local height = tonumber(cfg.OrbitHeight) or 38
	local O = M.Orbit
	O.T = O.T + (tonumber(dt) or 0)
	local angle = (O.T / math.max(1, period)) * math.pi * 2
	local c = O.Centre
	camera.CFrame = CFrame.lookAt(
		Vector3.new(c.X + math.cos(angle) * radius, c.Y + height, c.Z + math.sin(angle) * radius),
		Vector3.new(c.X, c.Y + 8, c.Z)
	)
end

function Orbit.start()
	local O = M.Orbit
	if O.Conn then
		return
	end
	O.Centre = Orbit.centre()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	Orbit.place(0)
	O.Conn = RunService.RenderStepped:Connect(Orbit.place)
end

function Orbit.stop()
	local O = M.Orbit
	if O.Conn then
		O.Conn:Disconnect()
		O.Conn = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

----------------------------------------------------------------------
-- the loading screen hand-off
----------------------------------------------------------------------
local Loading = {}

function Loading.fade(gui)
	if not gui or not gui.Parent or gui:GetAttribute("Fading") then
		return
	end
	gui:SetAttribute("Fading", true)
	local info = TweenInfo.new(K.LOADING_FADE)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("GuiObject") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				TweenService:Create(d, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(K.LOADING_FADE, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

function Loading.watch(gui)
	if not gui or gui.Name ~= "NimbusLoading" or not gui:IsA("ScreenGui") then
		return
	end
	if gui:GetAttribute("Done") == true then
		Loading.fade(gui)
		return
	end
	local conn
	conn = gui:GetAttributeChangedSignal("Done"):Connect(function()
		if gui:GetAttribute("Done") == true then
			conn:Disconnect()
			Loading.fade(gui)
		end
	end)
end

-- watch the loading screen there now and any added later (once)
function Loading.hook()
	if M.LoadingHooked then
		return
	end
	local pg = H.playerGui()
	if not pg then
		return
	end
	M.LoadingHooked = true
	Loading.watch(pg:FindFirstChild("NimbusLoading"))
	pg.ChildAdded:Connect(Loading.watch)
end

function Loading.busy()
	local pg = H.playerGui()
	local gui = pg and pg:FindFirstChild("NimbusLoading")
	return gui ~= nil and gui:GetAttribute("Done") ~= true
end

----------------------------------------------------------------------
-- the menu screen
----------------------------------------------------------------------
local Menu = {}

function Menu.gui()
	if M.Gui and M.Gui.Parent then
		return M.Gui
	end
	local pg = H.playerGui()
	if not pg then
		return nil
	end
	local gui = pg:FindFirstChild(K.GUI)
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = K.GUI
		gui.DisplayOrder = K.ORDER
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = pg
	end
	M.Gui = gui
	return gui
end

function Menu.badge()
	local notes = H.notes()
	local latest = notes and tonumber(notes.Latest) or 0
	local seen = tonumber(ClientSettings.Get("SeenNotes")) or 0
	return latest > seen
end

function Menu.refreshBadge()
	local badge = M.Ui.NewBadge
	if badge then
		badge.Visible = Menu.badge()
	end
end

-- the logo block: NIMBUS (white) over CLIMB (gold), left-aligned (landscape) or centred (portrait)
function Menu.logo(parent, width, size, align, order)
	local logo = H.frame("Logo", { Size = UDim2.fromOffset(width, math.floor(size * 1.9)), LayoutOrder = order }, parent)
	H.label("Nimbus", "NIMBUS", "Title", size, {
		Outline = 5,
		Color = K.WHITE,
		Size = UDim2.new(1, 0, 0, size),
		TextXAlignment = align,
	}, logo)
	H.label("Climb", "CLIMB", "Title", size, {
		Outline = 5,
		Color = K.NEW_GOLD,
		Position = UDim2.fromOffset(0, math.floor(size * 0.9)),
		Size = UDim2.new(1, 0, 0, size),
		TextXAlignment = align,
	}, logo)
	return logo
end

function Menu.ribbon(parent, width, align, order)
	local notes = H.notes()
	local title = notes and notes.Notes and notes.Notes[1] and notes.Notes[1].Title or nil
	if type(title) ~= "string" then
		return nil
	end
	local row = H.frame("Ribbon", { Size = UDim2.fromOffset(width, 44), LayoutOrder = order }, parent)
	local pillW = math.min(width, 380)
	local pill = H.frame("Pill", {
		BackgroundTransparency = 0.2,
		BackgroundColor3 = K.INK,
		Size = UDim2.fromOffset(pillW, 40),
		Position = align == Enum.TextXAlignment.Center and UDim2.new(0.5, -pillW / 2, 0, 2) or UDim2.fromOffset(0, 2),
	}, row)
	H.corner(pill)
	Util.Create("UIStroke", { Color = K.NEW_GOLD, Thickness = 2, Transparency = 0.1, Parent = pill })
	local tag = H.label("Tag", "NEW", "Button", 18, {
		Outline = 0,
		Color = K.INK,
		BackgroundTransparency = 0,
		BackgroundColor3 = K.NEW_GOLD,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(58, 28),
	}, pill)
	tag.TextStrokeTransparency = 1
	H.corner(tag)
	H.label("Title", title, "Heading", 20, {
		Outline = 2,
		Position = UDim2.fromOffset(70, 0),
		Size = UDim2.new(1, -80, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, pill)
	return row
end

function Menu.build()
	local gui = Menu.gui()
	if not gui then
		return nil
	end
	local old = gui:FindFirstChild("Menu")
	if old then
		old:Destroy()
	end
	local vp = H.viewport()
	local f = Theme.ScreenFactor(vp.Y)
	local portrait = vp.Y > vp.X
	local designW, designH = vp.X / f, vp.Y / f
	local short = designH < 600
	local menu = H.frame("Menu", { Size = UDim2.fromScale(1, 1), Active = true, ZIndex = 1 }, gui)
	M.Menu = menu
	M.Ui = {}

	-- the shade: dark on the text side, the world shows through on the other
	local shade = H.frame("Shade", { BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(16, 12, 44), Size = UDim2.fromScale(1, 1) }, menu)
	Util.Create("UIGradient", {
		Rotation = portrait and 90 or 0,
		Transparency = portrait and NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.55, 0.45),
			NumberSequenceKeypoint.new(1, 0.92),
		}) or NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.45, 0.55),
			NumberSequenceKeypoint.new(1, 0.92),
		}),
		Parent = shade,
	})

	-- Roblox's touch thumbstick (bottom-left) and jump button (bottom-right) zones in screen px, kept clear of every
	-- button: the classic stick / jump button of a small phone (<= 500 px on the short side), the big ones elsewhere
	-- (the rule TutorialController and MovementController use)
	local touch = H.isTouch()
	local zoneW, zoneH = 0, 0
	if touch then
		if math.min(vp.X, vp.Y) <= 500 then
			zoneW, zoneH = 104, 96
		else
			zoneW, zoneH = 206, 210
		end
	end

	-- the column (landscape touch: right of the thumbstick zone, a little higher than on a desktop)
	local colW = portrait and math.min(K.COL_W, designW - 48) or math.min(K.COL_W, math.max(300, 0.42 * designW - K.MARGIN))
	local align = portrait and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
	local logoSize = short and 70 or (portrait and 88 or 100)
	local colX = math.max(math.floor(K.MARGIN * f), touch and (zoneW + math.floor(8 * f)) or 0)
	local colY = touch and -math.floor(6 * f) or math.floor(22 * f)
	local column = H.frame("Column", {
		AnchorPoint = portrait and Vector2.new(0.5, 0) or Vector2.new(0, 0.5),
		Position = portrait and UDim2.new(0.5, 0, 0.1, 0) or UDim2.new(0, colX, 0.5, colY),
		Size = UDim2.fromOffset(colW, short and 420 or 560),
		ZIndex = 2,
	}, menu)
	Util.Create("UIScale", { Name = "ReadScale", Scale = f, Parent = column })
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = portrait and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Left,
		VerticalAlignment = portrait and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, short and 8 or 12),
		Parent = column,
	})
	M.Ui.Column = column
	M.Ui.Logo = Menu.logo(column, colW, logoSize, align, 1)
	H.label("Tagline", "Pets" .. K.DOT .. "Homes" .. K.DOT .. "Battles" .. K.DOT .. "Sky obbies", "Heading", short and 20 or 23, {
		Outline = 2,
		Color = Color3.fromRGB(255, 236, 252),
		Size = UDim2.fromOffset(colW, 30),
		TextXAlignment = align,
		LayoutOrder = 2,
	}, column)
	if not short then
		Menu.ribbon(column, colW, align, 3)
	end
	H.frame("Gap", { Size = UDim2.fromOffset(10, short and 2 or 8), LayoutOrder = 4 }, column)

	M.Ui.Play = NeonKit.Button({
		Name = "PlayButton",
		Text = "\226\150\182  PLAY",
		Color = "Green",
		Variant = "Primary",
		Size = UDim2.fromOffset(colW, K.PLAY_H),
		TextSize = 38,
		LayoutOrder = 5,
		Callback = function()
			MainMenuController.Play()
		end,
		Parent = column,
	})
	local row = H.frame("Row", { Size = UDim2.fromOffset(colW, K.BTN_H), LayoutOrder = 6 }, column)
	local half = math.floor((colW - 12) / 2)
	M.Ui.Settings = NeonKit.Button({
		Name = "SettingsButton",
		Text = "SETTINGS",
		Color = "Blue",
		Variant = "Outline",
		Size = UDim2.fromOffset(half, K.BTN_H),
		TextSize = 22,
		Callback = function()
			MainMenuController.OpenSettings()
		end,
		Parent = row,
	})
	M.Ui.Updates = NeonKit.Button({
		Name = "UpdatesButton",
		Text = "UPDATES",
		Color = "Purple",
		Variant = "Outline",
		Size = UDim2.fromOffset(half, K.BTN_H),
		Position = UDim2.fromOffset(colW - half, 0),
		TextSize = 22,
		Callback = function()
			MainMenuController.OpenUpdates()
		end,
		Parent = row,
	})
	local badge = H.label("NewBadge", "NEW", "Button", 18, {
		Outline = 0,
		Color = K.INK,
		BackgroundTransparency = 0,
		BackgroundColor3 = K.NEW_GOLD,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 6, 0, 2),
		Size = UDim2.fromOffset(60, 26),
		ZIndex = 9,
	}, M.Ui.Updates)
	badge.TextStrokeTransparency = 1
	H.corner(badge)
	Util.Create("UIStroke", { Color = K.WHITE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = badge })
	M.Ui.NewBadge = badge
	Menu.refreshBadge()

	-- the hint under the buttons (keyboard / gamepad / touch)
	H.label("Hint", (H.isTouch() and "Tap PLAY to jump in!") or "Press ENTER to play", "Label", 18, {
		Outline = 2,
		Color = Color3.fromRGB(226, 220, 255),
		Size = UDim2.fromOffset(colW, 24),
		TextXAlignment = align,
		LayoutOrder = 7,
	}, column)

	-- version + CREDITS chip, bottom-right
	-- desktop: bottom-right; landscape touch: top-right under Roblox's buttons; portrait: bottom-centre, ABOVE the
	-- thumbstick and the jump button a character would bring (never inside either zone)
	local chipAnchor, chipPos = Vector2.new(1, 1), UDim2.new(1, -math.floor(20 * f), 1, -math.floor(18 * f))
	if portrait then
		chipAnchor, chipPos = Vector2.new(0.5, 1), UDim2.new(0.5, -math.floor(10 * f), 1, -(zoneH + math.floor(12 * f)))
	elseif touch then
		chipAnchor, chipPos = Vector2.new(1, 0), UDim2.new(1, -math.floor(16 * f), 0, 66)
	end
	local chip = H.frame("Chip", {
		AnchorPoint = chipAnchor,
		Position = chipPos,
		Size = UDim2.fromOffset(250, 44),
		ZIndex = 3,
	}, menu)
	Util.Create("UIScale", { Name = "ReadScale", Scale = f, Parent = chip })
	local notes = H.notes()
	H.label("Version", "v" .. tostring(notes and notes.Latest or 5) .. ".0", "Label", 18, {
		Outline = 2,
		Color = Color3.fromRGB(226, 220, 255),
		Size = UDim2.fromOffset(80, 44),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, chip)
	M.Ui.Credits = NeonKit.Button({
		Name = "CreditsButton",
		Text = "CREDITS",
		Color = "Pink",
		Variant = "Outline",
		Size = UDim2.fromOffset(150, 44),
		Position = UDim2.fromOffset(96, 0),
		TextSize = 18,
		Callback = function()
			MainMenuController.OpenCredits()
		end,
		Parent = chip,
	})
	return menu
end

function H.isTouch()
	local UIS = game:GetService("UserInputService")
	return UIS.TouchEnabled and not UIS.KeyboardEnabled
end

-- a keyboard + mouse device (where MouseLock does anything)
function H.isDesktop()
	local UIS = game:GetService("UserInputService")
	return UIS.KeyboardEnabled == true and UIS.MouseEnabled == true
end

-- MouseLock.Hold / Release for the menu screen (once each way; the module is optional)
function H.mouseHold(on)
	on = on == true
	if (M.MouseHeld == true) == on then
		return
	end
	local ml = H.mod("MouseLock")
	if not ml then
		return
	end
	M.MouseHeld = on
	pcall(on and ml.Hold or ml.Release, K.MOUSE_HOLD)
end

function Menu.bindKeys(on)
	if on then
		ContextActionService:BindActionAtPriority(K.ACTION, function(_, state)
			if state == Enum.UserInputState.Begin and M.Open and not M.Win.Name then
				MainMenuController.Play()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, 3000, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.ButtonA)
	else
		pcall(function()
			ContextActionService:UnbindAction(K.ACTION)
		end)
	end
end

function Menu.fade(menu, seconds)
	local info = TweenInfo.new(seconds)
	for _, d in ipairs(menu:GetDescendants()) do
		if d:IsA("GuiObject") then
			if d.BackgroundTransparency < 1 then
				TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			end
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				TweenService:Create(d, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
end

----------------------------------------------------------------------
-- windows: settings / updates / credits (docked by the window rule)
----------------------------------------------------------------------
local Win = {}

function Win.close()
	local W = M.Win
	if W.Dock then
		pcall(W.Dock.Disconnect)
	end
	if W.Holder then
		W.Holder:Destroy()
	end
	W.Name, W.Holder, W.Dock, W.Panel = nil, nil, nil, nil
	M.Settings.Rows = {}
end

function Win.open(name, title, category, prefH)
	Win.close()
	local gui = Menu.gui()
	if not gui then
		return nil
	end
	local W = M.Win
	local holder = H.frame("Window_" .. name, { Size = UDim2.fromOffset(K.WIN_W, prefH), ZIndex = 10 }, gui)
	local fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	W.Dock = NeonKit.Dock(holder, fit, K.WIN_W, prefH)
	W.Panel = CloudUI.Panel({
		Name = name .. "Panel",
		Title = title,
		Closable = true,
		Category = category,
		Size = UDim2.new(1, 0, 1, 0),
		OnClose = function()
			H.sound("Click")
			Win.close()
		end,
		Parent = holder,
	})
	W.Name, W.Holder = name, holder
	return W.Panel
end

-- a 0..10 setting: label, value, - [10 segments] +
function Win.sliderRow(parent, key, title, glyph, order)
	local row = H.frame("Row_" .. key, { Size = UDim2.new(1, 0, 0, 104), LayoutOrder = order }, parent)
	H.label("Title", glyph .. "  " .. title, "Heading", 24, {
		Size = UDim2.new(1, -90, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local value = H.label("Value", "", "Display", 28, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(90, 34),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	local strip = H.frame("Strip", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 52) }, row)
	local function step(delta)
		H.sound("Click")
		ClientSettings.Set(key, (tonumber(ClientSettings.Get(key)) or 0) + delta)
	end
	NeonKit.Button({ Name = "Minus", Text = "-", Color = "Blue", Variant = "Outline", Size = UDim2.fromOffset(52, 52), TextSize = 30, Callback = function()
		step(-1)
	end, Parent = strip })
	NeonKit.Button({ Name = "Plus", Text = "+", Color = "Blue", Variant = "Outline", Size = UDim2.fromOffset(52, 52), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), TextSize = 30, Callback = function()
		step(1)
	end, Parent = strip })
	local track = H.frame("Track", { Position = UDim2.fromOffset(64, 8), Size = UDim2.new(1, -128, 0, 36) }, strip)
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = track,
	})
	local segs = {}
	for i = 1, 10 do
		local seg = Instance.new("TextButton")
		seg.Name = "Step" .. i
		seg.Text = ""
		seg.AutoButtonColor = false
		seg.BorderSizePixel = 0
		seg.Size = UDim2.new(0.1, -4, 0, 18 + i * 1.8)
		seg.LayoutOrder = i
		seg.BackgroundColor3 = K.WHITE
		H.corner(seg, 5)
		seg.Activated:Connect(function()
			H.sound("Click")
			local current = tonumber(ClientSettings.Get(key)) or 0
			ClientSettings.Set(key, (current == i and i == 1) and 0 or i)
		end)
		seg.Parent = track
		segs[i] = seg
	end
	local function paint()
		local v = tonumber(ClientSettings.Get(key)) or 0
		value.Text = v == 0 and "OFF" or tostring(v)
		for i, seg in ipairs(segs) do
			local on = i <= v
			seg.BackgroundColor3 = on and Theme.Neon.Cyan or Color3.fromRGB(46, 52, 96)
			seg.BackgroundTransparency = on and 0 or 0.2
		end
	end
	paint()
	M.Settings.Rows[key] = paint
	return row
end

-- chips: one of `options` ({ { Text, Value } }) for `key`
function Win.chipRow(parent, key, title, glyph, options, order)
	local row = H.frame("Row_" .. key, { Size = UDim2.new(1, 0, 0, 104), LayoutOrder = order }, parent)
	H.label("Title", glyph .. "  " .. title, "Heading", 24, {
		Size = UDim2.new(1, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local strip = H.frame("Chips", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 52) }, row)
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = strip,
	})
	local chips = {}
	local n = #options
	-- the selected chip is a filled (Primary) green button, the others blue outlines; rebuilt on every change
	local function paint()
		local v = ClientSettings.Get(key)
		for i, opt in ipairs(options) do
			local selected = v == opt[2]
			local old = chips[i]
			if not old or old:GetAttribute("Selected") ~= selected then
				local chip = NeonKit.Button({
					Name = "Chip_" .. tostring(opt[1]),
					Text = opt[1],
					Color = selected and "Green" or "Blue",
					Variant = selected and "Primary" or "Outline",
					Size = UDim2.new(1 / n, -math.ceil(10 * (n - 1) / n), 0, 52),
					LayoutOrder = i,
					TextSize = 22,
					Callback = function()
						H.sound("Click")
						ClientSettings.Set(key, opt[2])
					end,
				})
				chip:SetAttribute("Selected", selected)
				chip.Parent = strip
				if old then
					old:Destroy()
				end
				chips[i] = chip
			end
		end
	end
	paint()
	M.Settings.Rows[key] = paint
	return row
end

function Win.list(panel)
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = K.WHITE
	list.ZIndex = 5
	list.Parent = panel.Content
	Util.Create("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
		Parent = list,
	})
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
		Parent = list,
	})
	return list
end

function MainMenuController.OpenSettings()
	local panel = Win.open("Settings", "Settings", "Settings", K.WIN_H)
	if not panel then
		return
	end
	H.sound("Click")
	local list = Win.list(panel)
	Win.sliderRow(list, "Music", "Music", K.GLYPH_MUSIC, 1)
	Win.sliderRow(list, "Sfx", "Sound", K.GLYPH_SOUND, 2)
	Win.chipRow(list, "Gfx", "Graphics", K.GLYPH_GFX, { { "AUTO", "Auto" }, { "LOW", "Low" }, { "HIGH", "High" } }, 3)
	Win.chipRow(list, "Shake", "Camera shake", K.GLYPH_SHAKE, { { "ON", true }, { "OFF", false } }, 4)
	local desktop = H.isDesktop()
	if desktop then
		-- (bug batch 2 #21: on by default; the key that frees it is in the note below)
		Win.chipRow(list, "MouseLock", "Mouse lock (recommended)", K.GLYPH_MOUSE, { { "ON", true }, { "OFF", false } }, 5)
	end
	local note = "Low graphics hides small decorations and glow. Saved to your account."
	if desktop then
		local ml = H.mod("MouseLock")
		local free = (ml and ml.KEY_NAME) and (" (press " .. ml.KEY_NAME .. " to free it)") or ""
		note = "Mouse lock: the mouse turns the camera" .. free .. ". Low graphics hides small decorations and glow. Saved to your account."
	end
	H.label("Note", note, "Label", 18, {
		Outline = 2,
		Color = Color3.fromRGB(206, 210, 240),
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, desktop and 72 or 48),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 6,
	}, list)
end

function MainMenuController.OpenUpdates()
	local panel = Win.open("Updates", "What's new", "Index", K.WIN_H)
	if not panel then
		return
	end
	H.sound("Click")
	local notes = H.notes()
	local list = Win.list(panel)
	local order = 0
	for _, note in ipairs(notes and notes.Notes or {}) do
		order = order + 1
		local newest = order == 1
		H.label("Head" .. order, "v" .. tostring(note.Version) .. "  " .. tostring(note.Title or ""), "Heading", newest and 26 or 22, {
			Outline = 2,
			Color = newest and K.NEW_GOLD or K.WHITE,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order * 100,
		}, list)
		for i, line in ipairs(note.Lines or {}) do
			H.label("Line" .. order .. "_" .. i, "\226\128\162  " .. tostring(line), "Body", 19, {
				Outline = 2,
				TextWrapped = true,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = order * 100 + i,
			}, list)
		end
	end
	if notes and tonumber(notes.Latest) then
		ClientSettings.Set("SeenNotes", notes.Latest)
	end
	Menu.refreshBadge()
end

function MainMenuController.OpenCredits()
	local panel = Win.open("Credits", "Credits", "Fusion", 420)
	if not panel then
		return
	end
	H.sound("Click")
	local notes = H.notes()
	local list = Win.list(panel)
	for i, line in ipairs(notes and notes.Credits or {}) do
		H.label("Credit" .. i, tostring(line), "Heading", 24, {
			Outline = 2,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = i,
		}, list)
	end
	H.label("Thanks", "Thanks for playing Nimbus Climb!", "Body", 20, {
		Outline = 2,
		Color = K.NEW_GOLD,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 99,
	}, list)
end

function MainMenuController.CloseWindows()
	Win.close()
end

function MainMenuController.Window()
	return M.Win.Holder, M.Win.Name
end

----------------------------------------------------------------------
-- open / play
----------------------------------------------------------------------

function MainMenuController.IsOpen()
	return M.Open
end

function MainMenuController.Open()
	if M.Open then
		return
	end
	M.Open = true
	M.Playing = false
	H.mouseHold(true)
	Loading.hook()
	Gate.close()
	local ok = H.safe("build", Menu.build)
	if not ok and M.Menu then
		M.Menu:Destroy()
		M.Menu = nil
	end
	Orbit.start()
	Menu.bindKeys(true)
end

function MainMenuController.Play()
	if not M.Open or M.Playing then
		return false
	end
	if Loading.busy() then
		return false -- the loading screen is still up (SKIP takes it away)
	end
	M.Playing = true
	H.sound("Confirm")
	Win.close()
	Menu.bindKeys(false)
	task.spawn(function()
		if not M.SentPlay and not UiGate.HasPlayed() then
			M.SentPlay = true
			local okRemote, remote = pcall(Remotes.Get, "MenuPlay")
			if okRemote and remote then
				pcall(function()
					remote:FireServer()
				end)
			end
			-- wait for the character the server spawns (<= 5 s, then on anyway)
			local waited = 0
			while not (LocalPlayer.Character and LocalPlayer.Character.Parent) and waited < K.CHAR_WAIT do
				waited = waited + task.wait(0.1)
			end
		end
		if M.Menu then
			Menu.fade(M.Menu, K.FADE)
		end
		task.wait(K.FADE)
		if M.Menu then
			M.Menu:Destroy()
			M.Menu = nil
		end
		Orbit.stop()
		Gate.open()
		M.Open = false
		M.Playing = false
		H.mouseHold(false)
		UiGate.MarkPlayed()
		H.sound("Whoosh")
	end)
	return true
end

----------------------------------------------------------------------
-- init
----------------------------------------------------------------------

local function onSettingChanged(key)
	local paint = M.Settings.Rows[key]
	if paint then
		pcall(paint)
	end
	if key == "SeenNotes" then
		Menu.refreshBadge()
	end
end

function MainMenuController.Init()
	if M.Started then
		return
	end
	M.Started = true
	if not LocalPlayer then
		return
	end
	ClientSettings.Changed:Connect(onSettingChanged)
	local MouseLock = H.mod("MouseLock")
	if MouseLock and type(MouseLock.Start) == "function" then
		H.safe("MouseLock", MouseLock.Start) -- idempotent (Main.client.lua may start it first)
	end
	local GraphicsQuality = H.mod("GraphicsQuality")
	if GraphicsQuality and type(GraphicsQuality.Init) == "function" then
		H.safe("GraphicsQuality", GraphicsQuality.Init)
	end
	local SoundFx = H.mod("SoundFx")
	if SoundFx and type(SoundFx.Music) == "function" then
		-- the track the game state asks for (SoundFx layers: a battle / dungeon that is already on wins), else Lobby
		local context = type(SoundFx.Wanted) == "function" and SoundFx.Wanted() or "Lobby"
		H.safe("music", SoundFx.Music, context)
	end
	M.Enabled = H.menuCfg().Enabled == true
	if not M.Enabled then
		UiGate.MarkPlayed()
		return
	end
	local pg = LocalPlayer:WaitForChild("PlayerGui", 30)
	if not pg then
		UiGate.MarkPlayed()
		return
	end
	Loading.hook()
	if UiGate.HasPlayed() then
		return
	end
	MainMenuController.Open()
end

return MainMenuController
