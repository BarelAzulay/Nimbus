-- MainMenuController: the main menu BEFORE spawning, the settings / updates / credits windows and the hand-off from
-- the loading screen (ARCHITECTURE_V3.md "Phase 5 build contract" 7.1-7.3; judge M7 / C17).
--
-- With Config.MainMenu.Enabled:
--   * The server holds the character until PLAY (PlayerService: MenuPlay or the 90 s fallback), so there is no
--     character behind the menu. Until PLAY every ScreenGui in PlayerGui that is not in UiGate.ALLOW (NimbusLoading,
--     NimbusMainMenu, NimbusNotify) is kept Enabled = false: the ones there now and any added later (ChildAdded); an
--     owner that switches its gui on meanwhile gets it back on at PLAY (its wish is remembered).
--   * (quick wins 2026-11-12, win 1) The title screen is clean: the world name cards (BillboardGuis named in
--     Config.MainMenu.HideCards: the gate / portal cards, the obby join board, the Sky Trove, garden names, NPC and
--     home nameplates, the raid gate and home portal tags) anywhere in the workspace are kept Enabled = false by the
--     same rule (there now, added later, an owner's wish remembered; one that was off stays off), client-side only;
--     and NotifyController.SetHeld("MainMenu", true) holds the gameplay toasts until the end of PLAY.
--   * The camera is Scriptable and orbits the Gate Court (centre = Lobby.Origin + GateArcRadius towards GateFacing;
--     Config.MainMenu OrbitRadius 90, OrbitHeight 38, OrbitPeriod 60 s; RenderStepped while the menu is up only).
--   * The loading screen (NimbusLoading) is faded (0.4 s) and destroyed once its Done attribute is true.
--   * PLAY (button, Enter / keypad Enter, gamepad A): MenuPlay fired once per session (no args), wait for the
--     character (<= 5 s, then go on anyway), 0.35 s fade, camera Custom on the humanoid, the guis and world cards back,
--     UiGate.MarkPlayed(), then the held toasts (SetHeld("MainMenu", false)).
--     Shown once per session; respawns never show it again. DevController's /menu reopens it (Open(): client-side
--     only, the character stays, MenuPlay is never sent again).
-- With Enabled false: UiGate.MarkPlayed() at once, nothing gated (the loading screen fades by itself).
-- Always: GraphicsQuality.Init() and SoundFx.Music(SoundFx.Wanted()) (Lobby unless a battle / dungeon layer is on).
--
-- Layout (NeonKit; design px of a 1080p screen under one UIScale clamp(H / 1080, 0.8, 1.25)): a left column on
-- landscape screens (x = 60, <= 0.42 W), a centred column on portrait ones: logo NIMBUS / CLIMB, the tag line
-- (Config.Tagline, "Climb the storm. Together."), the
-- "NEW" update ribbon, PLAY (Primary Green, 76 tall), SETTINGS (Blue outline) + UPDATES (Purple outline with a NEW
-- badge while UpdateNotes.Latest > Settings.SeenNotes), a dark gradient over the world so the text reads, and a
-- version + CREDITS chip bottom-right.
-- Windows (docked by NeonKit.Dock: right side panel / bottom sheet):
--   SETTINGS  Music and Sound (11 steps 0..10, - / + and the step segments), Graphics (Auto / Low / High chips),
--             Camera shake (ON / OFF), Mouse lock (ON / OFF, keyboard + mouse devices only; the L key toggles it too);
--             applied at once through ClientSettings.Set (sent after a 0.4 s debounce)
--   UPDATES   UpdateNotes.Notes newest first; opening it sends SettingsSet("SeenNotes", UpdateNotes.Latest)
--   CREDITS   (credits look B "Signed by the Maker", the owner's pick 2026-11-13) a Signboard window, not the neon panel:
--             a small pink roof (ONE fixed-size piece, K.CR.ROOF_W x ROOF_H, never stretched with the window), a navy header
--             with CREDITS (Theme Sign = LuckiestGuy, a dark drop line) and the drawn X, a wood frame round a cream body.
--             In the body: a polaroid (-5 deg, a red pin, the creator's headshot via Players:GetUserThumbnailAsync on a
--             sky gradient, "the boss"), a navy plank holding the studio's SAINTSFIELD wordmark picture (TextureIds
--             saintsfield_wordmark), CREATED BY, the signature (Theme.Fonts.Signature, -3 deg, a swash), the gold italic
--             thank-you line, and the round SF emblem sticker (TextureIds saintsfield_emblem, gold ring, 12 deg) in the
--             bottom-right corner, clear of every text. Every text is UpdateNotes.Credits; the headshot is game.CreatorId
--             for a user-owned game, else Config.CreatorUserId. Landscape: the polaroid left of the text; portrait: above
--             it (a portrait phone too short for that: beside it). The texts are measured (TextService): the polaroid
--             shrinks before the column gets too narrow, the signature fills its row, the thank-you line wraps to as
--             many rows as it needs, and only the rows that reach the sticker end left of it. Rebuilt when the screen
--             changes size.
-- Every window: X, Esc (InputBegan), gamepad B ("NimbusMenuWinBack", High, bound while one is open) and CloseWindows close
-- it; opening one fires MenuController.WindowOpened(<name>) (the game's windows close on it, as for each other) and
-- closes the DEV panel, so nothing peeks out from under it (the Restart / Skip tutorial buttons did, under Credits).
-- MouseLock (client/MouseLock.lua, dungeon-fixes decision 6): Init starts it (idempotent); the menu screen is a hold
-- ("MainMenu", from Open until the PLAY fade ends); the windows are holds through NeonKit.Dock.
--
-- Public: Init(), Open(), Play(), IsOpen(), OpenSettings(), OpenUpdates(), OpenCredits(), CloseWindows(), Window(),
-- CreditsMetrics (the K.CR table: sizes; MEASURE, a text-width hook for the offline renderer)
-- Plain Lua 5.1-compatible syntax only; fonts only through Theme roles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local TextService = game:GetService("TextService")

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
	TOAST_HOLD = "MainMenu", -- NotifyController.SetHeld owner key (quick wins, win 1)
	TAGLINE = "Climb the storm. Together.", -- when Config.Tagline is missing
	-- (quick wins, win 1) the world name cards hidden on the title screen, by BillboardGui name: Config.MainMenu.HideCards
	-- (review round 1: every lobby label the orbit can see); this list only when Config has none
	WORLD_CARDS = { "GateTag", "PortalBillboard" },
	WIN_BACK = "NimbusMenuWinBack", -- gamepad B closes a window (bound only while one is open)
	-- (credits look B) the Signboard Credits window, design px of a 1080p screen
	CR = {
		W = 760, -- the preferred window: roof + header + body + drop line
		H = 520,
		TALL_H = 540, -- a portrait screen (the polaroid stacked above the text)
		ROOF_W = 300, -- the roof: one fixed-size piece, never stretched with the window
		ROOF_H = 44,
		SLOPE_T = 52, -- a roof slope's thickness (its lower part hides behind the header)
		FASCIA_H = 9,
		HEAD_H = 64,
		HEAD_H_SMALL = 52,
		RIM = 5, -- the header's dark wood rim
		WOOD = 6, -- the wood frame round the body
		LINE = 5, -- the body's inner line: inset ...
		LINE_T = 3, -- ... and thickness
		DROP = 8, -- the window's drop line
		WIDE_MIN = 560, -- a narrower body is the small layout (phones)
		WM_ASPECT = 1024 / 230, -- the wordmark picture
		-- the texts are MEASURED (Credits.textW), never guessed: the signature as big as its row allows, the thank-you
		-- line's wrapped line count
		SIG_SPARE = 1.06, -- the signature's measured width times this (the -3 deg lean, the marker's ragged ends)
		FACE_SPARE = 1.1, -- a FontFace text (Nunito Bold Italic) measured with its role's Enum.Font, times this
		SIG_MIN = 30, -- the smallest signature (design px)
		COL_MIN = 190, -- side by side: the text column is never narrower (the polaroid shrinks first)
		P_MIN = 84, -- the smallest polaroid side by side ...
		STACK_P_MIN = 112, -- ... and stacked (below it a short portrait screen goes side by side instead)
		MEASURE = nil, -- function(text, size, font, face) -> width: replaces TextService (tools/dump_gui.lua's renders)
		STICKER_TILT = 12,
		POLAROID_TILT = -5,
		SIG_TILT = -3,
		TITLE = "CREDITS",
		WORDMARK = "saintsfield_wordmark", -- TextureIds keys (tools/upload_assets.py --textures)
		EMBLEM = "saintsfield_emblem",
	},
	-- the Signboard kit's colours (the pitch's --g-* tokens)
	SIGN = {
		Roof = Color3.fromRGB(233, 132, 155), -- #e9849b
		RoofShade = Color3.fromRGB(185, 86, 109), -- #b9566d
		Navy = Color3.fromRGB(29, 43, 85), -- #1d2b55 (the header, the plank, the signature ink)
		Wood = Color3.fromRGB(138, 90, 50), -- #8a5a32
		WoodDark = Color3.fromRGB(94, 58, 29), -- #5e3a1d
		Cream = Color3.fromRGB(246, 236, 214), -- #f6ecd6
		CreamLine = Color3.fromRGB(234, 219, 184), -- #eadbb8
		Drop = Color3.fromRGB(11, 19, 48), -- #0b1330 (the title's drop line)
		Muted = Color3.fromRGB(122, 106, 76), -- #7a6a4c (CREATED BY)
		Gold = Color3.fromRGB(138, 101, 18), -- #8a6512 (the thank-you line)
		Ring = Color3.fromRGB(227, 179, 65), -- #e3b341 (the sticker's ring, the plank's nails)
		SkyTop = Color3.fromRGB(127, 196, 242), -- #7fc4f2
		SkyBottom = Color3.fromRGB(207, 234, 252), -- #cfeafc
		Pin = Color3.fromRGB(214, 69, 91), -- #d6455b
		PinDark = Color3.fromRGB(143, 31, 51), -- #8f1f33
		Caption = Color3.fromRGB(58, 58, 58), -- #3a3a3a
		PhotoEdge = Color3.fromRGB(216, 207, 189),
		Shadow = Color3.fromRGB(40, 26, 10),
	},
}
MainMenuController.CreditsMetrics = K.CR

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
	Win = { Name = nil, Holder = nil, Dock = nil, Panel = nil, Resize = nil, Back = false },
	Heads = {}, -- [userId] = the headshot content (Players:GetUserThumbnailAsync, once per user)
	Gate = { On = false, Wanted = {}, Conns = {}, AddConn = nil },
	Cards = { On = false, Names = {}, Wanted = {}, Conns = {}, AddConn = nil }, -- the world cards (HideCards), like Gate
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
-- the world cards (quick wins, win 1): the BillboardGuis named in Config.MainMenu.HideCards anywhere in the workspace
-- are off while the menu is up (client-side only), the same rule as the gate: the ones there now and any that appear
-- later (a gate streaming in, /menu mid-game); an owner that switches one on meanwhile gets it back at PLAY; one that
-- was already off stays off. The owners that switch their card on and off at run time (LobbyFxController's join board,
-- HomePortalFx, RaidGateController) re-apply their own state every pass, so a card whose owner switched it off while
-- it was held off is put right by that owner's next pass after PLAY. Every other BillboardGui (players' TitleTag, pet
-- cards) is untouched.
----------------------------------------------------------------------
local Cards = {}

-- the names to hide, as a set: Config.MainMenu.HideCards (K.WORLD_CARDS when Config has no list)
function Cards.names()
	local list = H.menuCfg().HideCards
	local set = {}
	for _, name in ipairs(type(list) == "table" and list or K.WORLD_CARDS) do
		set[tostring(name)] = true
	end
	return set
end

function Cards.track(g)
	local C = M.Cards
	if not C.On or not C.Names[g.Name] or not g:IsA("BillboardGui") or C.Wanted[g] ~= nil then
		return
	end
	C.Wanted[g] = g.Enabled
	g.Enabled = false
	C.Conns[g] = g:GetPropertyChangedSignal("Enabled"):Connect(function()
		if C.On and g.Enabled then
			C.Wanted[g] = true -- its owner switched it on: remember, keep it off until PLAY
			g.Enabled = false
		end
	end)
end

function Cards.close()
	local C = M.Cards
	if C.On then
		return
	end
	C.On = true
	C.Names = Cards.names()
	for _, d in ipairs(Workspace:GetDescendants()) do
		Cards.track(d)
	end
	C.AddConn = Workspace.DescendantAdded:Connect(function(d)
		Cards.track(d)
	end)
end

function Cards.open()
	local C = M.Cards
	C.On = false
	if C.AddConn then
		C.AddConn:Disconnect()
		C.AddConn = nil
	end
	for g, conn in pairs(C.Conns) do
		conn:Disconnect()
		C.Conns[g] = nil
	end
	for g, want in pairs(C.Wanted) do
		-- every remembered card gets its wish back: a destroyed one is a harmless no-op (pcall), and one that was only
		-- taken out of the workspace meanwhile (streamed out, moved) is not left off for good if it comes back
		pcall(function()
			g.Enabled = want
		end)
		C.Wanted[g] = nil
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
	H.label("Tagline", tostring(Config.Tagline or K.TAGLINE), "Heading", short and 20 or 23, {
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

-- (quick wins, win 1) NotifyController.SetHeld for the menu screen: gameplay toasts wait for PLAY (the module is
-- optional; a missing or older one without SetHeld is skipped)
function H.holdToasts(on)
	local notify = H.mod("NotifyController")
	if notify and type(notify.SetHeld) == "function" then
		H.safe("toasts", notify.SetHeld, K.TOAST_HOLD, on == true)
	end
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

-- gamepad B closes the open window: bound at High priority only while one is open (B is the dash button too), so the
-- press that closes it is sunk; the unbind waits a frame (that press is still being dispatched)
function Win.bindBack(on)
	local W = M.Win
	if on then
		if W.Back then
			return
		end
		W.Back = true
		H.safe("bind back", function()
			ContextActionService:BindActionAtPriority(K.WIN_BACK, function(_, state)
				if not M.Win.Name then
					return Enum.ContextActionResult.Pass
				end
				if state == Enum.UserInputState.Begin then
					H.sound("Click")
					Win.close()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		end)
	elseif W.Back then
		task.defer(function()
			if M.Win.Name or not M.Win.Back then
				return -- another window opened meanwhile (it keeps the binding)
			end
			M.Win.Back = false
			pcall(function()
				ContextActionService:UnbindAction(K.WIN_BACK)
			end)
		end)
	end
end

function Win.close()
	local W = M.Win
	if W.Resize then
		W.Resize:Disconnect()
	end
	if W.Dock then
		pcall(W.Dock.Disconnect)
	end
	if W.Holder then
		W.Holder:Destroy()
	end
	W.Name, W.Holder, W.Dock, W.Panel, W.Resize = nil, nil, nil, nil, nil
	M.Settings.Rows = {}
	Win.bindBack(false)
end

-- what lies behind a window that opens: the game's windows close on MenuController.WindowOpened (as they do for each
-- other), and the DEV panel (docked right, under the menu's gui) is closed so its buttons never peek out from under it
function Win.clearBehind(name)
	local menu = H.mod("MenuController")
	local signal = menu and menu.WindowOpened
	if type(signal) == "table" and type(signal.Fire) == "function" then
		H.safe("WindowOpened", function()
			signal:Fire(name)
		end)
	end
	local dev = H.mod("DevController")
	if dev and type(dev.IsOpen) == "function" and type(dev.Close) == "function" and dev.IsOpen() then
		H.safe("dev panel", dev.Close)
	end
end

-- a window's root, docked by the window rule (prefW x prefH design px); nil without a gui
function Win.holder(name, prefW, prefH)
	Win.close()
	local gui = Menu.gui()
	if not gui then
		return nil
	end
	local W = M.Win
	local holder = H.frame("Window_" .. name, { Size = UDim2.fromOffset(prefW, prefH), ZIndex = 10 }, gui)
	local fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	W.Dock = NeonKit.Dock(holder, fit, prefW, prefH)
	W.Name, W.Holder = name, holder
	Win.clearBehind(name)
	Win.bindBack(true)
	return holder
end

function Win.open(name, title, category, prefH)
	local holder = Win.holder(name, K.WIN_W, prefH)
	if not holder then
		return nil
	end
	local W = M.Win
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

----------------------------------------------------------------------
-- the Credits window (credits look B "Signed by the Maker"): a Signboard window built from Frames
----------------------------------------------------------------------
local Credits = {}

-- the owner's texts (UpdateNotes.Credits: the one place they live)
function Credits.texts()
	local notes = H.notes()
	local c = notes and notes.Credits
	return type(c) == "table" and c or {}
end

-- the headshot's user: the game's owner when a user owns it, else the creator's account (Config.CreatorUserId)
function Credits.creatorId()
	local id = nil
	pcall(function()
		if game.CreatorType == Enum.CreatorType.User and tonumber(game.CreatorId) and game.CreatorId > 0 then
			id = game.CreatorId
		end
	end)
	return id or tonumber(Config.CreatorUserId)
end

-- "rbxassetid://<id>" of a TextureIds key, nil while it has no id
function Credits.image(key)
	local ids = H.optional(Shared, "TextureIds")
	local id = ids and ids[key]
	if type(id) == "number" and id > 0 then
		local digits = string.format("%.0f", id) -- whole digits (a 15-digit id never prints as 1.05e+14)
		return "rbxassetid://" .. digits
	end
	return nil
end

-- the headshot into `label` (a web call: once per user, off the build)
function Credits.headshot(label, userId)
	if not userId then
		return
	end
	local cached = M.Heads[userId]
	if type(cached) == "string" then
		label.Image = cached
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)
		if ok and type(content) == "string" and content ~= "" then
			M.Heads[userId] = content
			if label.Parent then
				label.Image = content
			end
		end
	end)
end

-- a plain text on the cream body (no outline: dark ink on a light card reads by itself)
function Credits.text(name, text, role, size, color, props, parent)
	local l = Theme.Label(tostring(text or ""), role, { Size = size, Color = color, Stroke = 1 })
	l.Name = name
	for key, value in pairs(props) do
		l[key] = value
	end
	l.Parent = parent
	return l
end

function Credits.stroke(parent, color, thickness)
	return Util.Create("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
		Parent = parent,
	})
end

-- a text's width in px (TextService: the real font). K.CR.MEASURE(text, size, font, face) replaces it when set:
-- tools/dump_gui.lua's renders pass the renderer's font metrics (the mock's GetTextSize is a flat 0.5 em per
-- character). GetTextSize knows no FontFace: a face text is measured with its role font, times FACE_SPARE.
function Credits.textW(text, size, font, face)
	local C = K.CR
	text = tostring(text or "")
	-- one layout tries many sizes: a text is measured once per build (Credits.layout starts a fresh cache)
	local key = text .. "|" .. tostring(size) .. "|" .. tostring(font) .. "|" .. tostring(face)
	local cache = Credits.Widths
	if cache and cache[key] then
		return cache[key]
	end
	local ok, v = pcall(function()
		if type(C.MEASURE) == "function" then
			return C.MEASURE(text, size, font, face)
		end
		local w = TextService:GetTextSize(text, size, font, Vector2.new(100000, 1000)).X
		return face and w * C.FACE_SPARE or w
	end)
	if not (ok and type(v) == "number") then
		v = #text * size * 0.55
	end
	if cache then
		cache[key] = v
	end
	return v
end

-- the rows `text` wraps to in `width` px (Roblox wraps on spaces) and the widest single word
function Credits.wrap(text, size, font, face, width)
	local rows, line, widest = 0, nil, 0
	for word in tostring(text or ""):gmatch("%S+") do
		widest = math.max(widest, Credits.textW(word, size, font, face))
		local try = line and (line .. " " .. word) or word
		if line and Credits.textW(try, size, font, face) > width then
			rows = rows + 1
			line = word
		else
			line = try
		end
	end
	return rows + (line and 1 or 0), widest
end

-- the polaroid's numbers for a side of P design px: white frame, square photo, caption band
function Credits.polaroidSize(L, P)
	L.P = P
	L.Border = math.max(6, math.floor(P * 0.055 + 0.5))
	L.Photo = P - 2 * L.Border
	L.CapSize = math.max(18, math.floor(P * 0.105 + 0.5))
	L.CapH = L.CapSize + math.max(10, math.floor(P * 0.09 + 0.5))
	L.PolH = L.Border + L.Photo + L.CapH
end

-- the column's rows top to bottom (column px) for its width L.ColW: a row that meets the sticker (narrow[row]) ends
-- left of it; the signature as big as its row allows (<= sigMax); the thank-you line as many rows as it wraps to
function Credits.rows(L, texts, sigMax, narrow)
	local C = K.CR
	local function rowW(key)
		return narrow[key] and math.floor(math.min(L.ColW, L.StickerLeft - L.ColX - 6)) or L.ColW
	end
	local small = L.Small
	-- the plank fits the wordmark (1024:230), as wide as the column allows
	L.PadX, L.PadY = small and 10 or 14, small and 8 or 10
	local wmH = small and 44 or 62
	local wmW = wmH * C.WM_ASPECT
	if wmW > L.ColW - 2 * L.PadX then
		wmW = L.ColW - 2 * L.PadX
		wmH = wmW / C.WM_ASPECT
	end
	L.WmW, L.WmH = math.floor(wmW), math.floor(wmH)
	L.PlankW, L.PlankH = L.WmW + 2 * L.PadX, L.WmH + 2 * L.PadY
	L.CreatedW, L.SigW, L.ThanksW = rowW("Created"), rowW("Sig"), rowW("Thanks")
	local sigFont = Theme.Fonts.Signature
	local em = Credits.textW(texts.Creator, 100, sigFont) / 100 * C.SIG_SPARE
	L.SigSize = math.max(C.SIG_MIN, math.min(sigMax, math.floor(L.SigW / math.max(em, 1))))
	L.SigH = math.ceil(L.SigSize * 1.2)
	local lines, widest = Credits.wrap(texts.Thanks, L.ThanksSize, Theme.Fonts.Body, Theme.Faces.Thanks, L.ThanksW - 2)
	L.ThanksLines = math.max(1, lines)
	-- every row's text fits its width: the signature on one line, CREATED BY, no thank-you word wider than its row
	local createdW = Credits.textW(texts.Role, L.CreatedSize, Theme.Fonts.Label, Theme.Faces.Caps)
	L.RowsFit = L.SigSize * em <= L.SigW and widest <= L.ThanksW - 2 and createdW <= L.CreatedW - 2
	L.ThanksH = L.ThanksLines * math.ceil(L.ThanksSize * 1.25) + 4
	local gapPlank = small and 8 or 14
	local gapThanks = small and 6 or 10
	L.PlankY = 0
	L.CreatedY = L.PlankH + gapPlank
	L.CreatedH = L.CreatedSize + 6
	L.SigY = L.CreatedY + L.CreatedH
	L.SwashY = L.SigY + math.floor(L.SigSize * 1.04) -- just under the name's baseline (the text sits centred in SigH)
	L.ThanksY = L.SwashY + gapThanks + 6
	L.ColH = L.ThanksY + L.ThanksH
end

-- the column in its room (centred below the polaroid when stacked, beside it otherwise); true when it fits. Rows that
-- reach down to the sticker's tilted box (the leaning signature's box a little lower) are narrowed and the column
-- laid out again, until no new row meets it
function Credits.placeColumn(L, texts, sigMax, pad)
	local narrow = {}
	local room = (L.BodyH - pad) - L.ColTop
	for _ = 1, 4 do
		Credits.rows(L, texts, sigMax, narrow)
		L.ColY = L.ColTop + math.max(0, math.floor((room - L.ColH) / 2))
		local added = false
		if L.ColX + L.ColW > L.StickerLeft then
			for _, row in ipairs({
				{ "Created", L.CreatedY + L.CreatedH },
				{ "Sig", L.SigY + L.SigH + math.ceil(L.SigW * 0.06) },
				{ "Thanks", L.ThanksY + L.ThanksH },
			}) do
				if not narrow[row[1]] and L.ColY + row[2] + 2 > L.StickerTop then
					narrow[row[1]] = true
					added = true
				end
			end
		end
		if not added then
			break
		end
	end
	return L.ColH <= room and L.RowsFit
end

-- every number of the body's layout for a window of w x h design px (stacked: the polaroid above the text; a portrait
-- screen too short for that falls back to side by side, L.Stacked says which)
function Credits.layout(w, h, stacked, texts)
	local C = K.CR
	Credits.Widths = {}
	local L = { Stacked = stacked }
	local small = stacked or (w - 2 * C.WOOD) < C.WIDE_MIN
	L.Small = small
	L.HeadH = small and C.HEAD_H_SMALL or C.HEAD_H
	L.HeadY = C.ROOF_H
	L.WoodY = L.HeadY + L.HeadH
	L.WoodH = h - L.WoodY - C.DROP
	L.BodyW = w - 2 * C.WOOD
	L.BodyH = L.WoodH - 2 * C.WOOD
	local pad = small and 12 or 18

	-- the sticker: bottom-right corner; its tilted box (ring included) is what the texts keep clear of
	L.S = small and 60 or 92
	L.Ring = small and 3 or 4
	local inset = small and 12 or 16
	L.StickerX = L.BodyW - inset - L.S / 2
	L.StickerY = L.BodyH - inset - L.S / 2
	local a = math.rad(C.STICKER_TILT)
	local half = L.S / 2 * (math.abs(math.cos(a)) + math.abs(math.sin(a))) + L.Ring
	L.StickerLeft = L.StickerX - half
	L.StickerTop = L.StickerY - half

	L.Pin = small and 18 or 22
	L.CreatedSize = small and 18 or 20
	L.ThanksSize = small and 18 or 20
	local sigMax = small and 54 or 72

	-- stacked: the column as wide as the body, the polaroid as big as the height left above it allows
	if stacked then
		L.ColX = pad + 4
		L.ColW = L.BodyW - 2 * L.ColX
		L.PolX = L.BodyW / 2
		for P = 140, C.STACK_P_MIN, -2 do
			Credits.polaroidSize(L, P)
			L.PolY = pad + L.Pin / 2 + L.PolH / 2
			L.ColTop = pad + L.Pin / 2 + L.PolH + 10
			if Credits.placeColumn(L, texts, sigMax, pad) then
				return L
			end
		end
		-- too short to stack (a small portrait phone): side by side in the same window
		L.Stacked = false
	end

	-- side by side: the polaroid as big as the height allows and the column's minimum width leaves; smaller still
	-- (then a smaller signature) until the column fits beside it
	local gapCol = small and 10 or 18
	local function side(P)
		Credits.polaroidSize(L, P)
		L.PolX = pad + P * 0.56
		L.PolY = L.BodyH / 2 + L.Pin / 4
		L.ColX = math.floor(P * 1.12) + pad + gapCol
		L.ColW = L.BodyW - L.ColX - pad
		L.ColTop = pad
	end
	local pMax = math.min(small and 150 or 210, math.floor((L.BodyH - 2 * pad - 20) / 1.22),
		math.floor((L.BodyW - 2 * pad - gapCol - C.COL_MIN) / 1.12))
	pMax = math.max(C.P_MIN, pMax)
	for P = pMax, C.P_MIN, -4 do
		side(P)
		if Credits.placeColumn(L, texts, sigMax, pad) then
			return L
		end
	end
	side(C.P_MIN)
	for size = sigMax - 2, C.SIG_MIN, -2 do
		if Credits.placeColumn(L, texts, size, pad) then
			return L
		end
	end
	return L
end

-- the roof: a gable of two tilted slopes (their lower parts hide behind the header), a darker fascia board under it
-- and a round vent; one fixed-size piece centred on the header, whatever the window's width
function Credits.roof(parent)
	local C, S = K.CR, K.SIGN
	local roof = H.frame("Roof", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(C.ROOF_W, C.ROOF_H),
		ZIndex = 2,
	}, parent)
	local halfW = C.ROOF_W / 2
	local theta = math.atan2(C.ROOF_H, halfW)
	local len = math.sqrt(halfW * halfW + C.ROOF_H * C.ROOF_H)
	-- the slope's top edge runs eave -> ridge; its centre sits half a thickness below that edge's middle
	local nx, ny = math.sin(theta), math.cos(theta)
	local cx, cy = halfW / 2 + nx * C.SLOPE_T / 2, C.ROOF_H / 2 + ny * C.SLOPE_T / 2
	for _, side in ipairs({ { "SlopeL", cx, -1 }, { "SlopeR", C.ROOF_W - cx, 1 } }) do
		H.frame(side[1], {
			BackgroundTransparency = 0,
			BackgroundColor3 = S.Roof,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(side[2], cy),
			Size = UDim2.fromOffset(len + 1, C.SLOPE_T),
			Rotation = side[3] * math.deg(theta),
			ZIndex = 1,
		}, roof)
	end
	H.frame("Fascia", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.RoofShade,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(C.ROOF_W + 16, C.FASCIA_H),
		ZIndex = 2,
	}, roof)
	local vent = H.frame("Vent", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.Cream,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(halfW, math.floor(C.ROOF_H * 0.52)),
		Size = UDim2.fromOffset(14, 14),
		ZIndex = 3,
	}, roof)
	H.corner(vent)
	Credits.stroke(vent, S.WoodDark, 2)
	return roof
end

-- the header: dark wood rim, navy plate, CREDITS with its drop line, the drawn red X
function Credits.head(parent, L)
	local C, S = K.CR, K.SIGN
	local head = H.frame("Head", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.WoodDark,
		Position = UDim2.fromOffset(0, L.HeadY),
		Size = UDim2.new(1, 0, 0, L.HeadH),
		Active = true,
		ZIndex = 3,
	}, parent)
	local plate = H.frame("Plate", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.Navy,
		Position = UDim2.fromOffset(C.RIM, C.RIM),
		Size = UDim2.new(1, -2 * C.RIM, 1, -C.RIM),
	}, head)
	local closeSize = L.Small and 38 or 44
	local titleSize = L.Small and 28 or Theme.Sizes.Sign
	local box = UDim2.new(1, -(18 + closeSize + 20), 1, 0)
	Credits.text("TitleDrop", C.TITLE, "Sign", titleSize, S.Drop, {
		Position = UDim2.fromOffset(18, 3),
		Size = box,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 1,
	}, plate)
	Credits.text("Title", C.TITLE, "Sign", titleSize, K.WHITE, {
		Position = UDim2.fromOffset(18, 0),
		Size = box,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	}, plate)
	local close = CloudUI.Button({
		Name = "Close",
		Text = "",
		Style = "Red",
		TextSize = 24,
		Size = UDim2.fromOffset(closeSize, closeSize),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		ZIndex = 3,
		Callback = function()
			H.sound("Click")
			Win.close()
		end,
		Parent = plate,
	})
	NeonKit.CloseMark(close)
	return head
end

-- the polaroid: white frame, sky-gradient photo with the headshot, a red pin, the marker caption
function Credits.polaroid(body, L, texts)
	local C, S = K.CR, K.SIGN
	H.frame("PolaroidShadow", {
		BackgroundTransparency = 0.78,
		BackgroundColor3 = S.Shadow,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(L.PolX + 4, L.PolY + 6),
		Size = UDim2.fromOffset(L.P, L.PolH),
		Rotation = C.POLAROID_TILT,
		ZIndex = 2,
	}, body)
	local pol = H.frame("Polaroid", {
		BackgroundTransparency = 0,
		BackgroundColor3 = K.WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(L.PolX, L.PolY),
		Size = UDim2.fromOffset(L.P, L.PolH),
		Rotation = C.POLAROID_TILT,
		ZIndex = 3,
	}, body)
	local photo = H.frame("Photo", {
		BackgroundTransparency = 0,
		BackgroundColor3 = K.WHITE,
		Position = UDim2.fromOffset(L.Border, L.Border),
		Size = UDim2.fromOffset(L.Photo, L.Photo),
	}, pol)
	Util.Create("UIGradient", { Color = ColorSequence.new(S.SkyTop, S.SkyBottom), Rotation = 90, Parent = photo })
	Credits.stroke(photo, S.PhotoEdge, 1)
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundTransparency = 1
	avatar.BorderSizePixel = 0
	avatar.Size = UDim2.fromScale(1, 1)
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.Image = ""
	avatar.Parent = photo
	Credits.headshot(avatar, Credits.creatorId())
	Credits.text("Caption", texts.Caption, "Signature", L.CapSize, S.Caption, {
		Position = UDim2.fromOffset(0, L.Border + L.Photo),
		Size = UDim2.fromOffset(L.P, L.CapH),
	}, pol)
	local pin = H.frame("Pin", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.Pin,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(L.P / 2, 2),
		Size = UDim2.fromOffset(L.Pin, L.Pin),
		ZIndex = 2,
	}, pol)
	H.corner(pin)
	Credits.stroke(pin, S.PinDark, 1.5)
	local shine = H.frame("PinShine", {
		BackgroundTransparency = 0.15,
		BackgroundColor3 = K.WHITE,
		Position = UDim2.fromScale(0.24, 0.2),
		Size = UDim2.fromScale(0.3, 0.3),
		ZIndex = 3,
	}, pin)
	H.corner(shine)
	return pol
end

-- the text column: the plank with the wordmark, CREATED BY, the signature + swash, the thank-you line
function Credits.column(body, L, texts)
	local C, S = K.CR, K.SIGN
	local col = H.frame("Column", {
		Position = UDim2.fromOffset(L.ColX, L.ColY),
		Size = UDim2.fromOffset(L.ColW, L.ColH),
		ZIndex = 3,
	}, body)
	local plank = H.frame("Plank", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.Navy,
		Position = UDim2.fromOffset(0, L.PlankY),
		Size = UDim2.fromOffset(L.PlankW, L.PlankH),
	}, col)
	Credits.stroke(plank, S.WoodDark, 3)
	for _, side in ipairs({ { "NailL", 0 }, { "NailR", 1 } }) do
		local nail = H.frame(side[1], {
			BackgroundTransparency = 0,
			BackgroundColor3 = S.Ring,
			AnchorPoint = Vector2.new(side[2], 0.5),
			Position = UDim2.new(side[2], side[2] == 0 and 4 or -4, 0.5, 0),
			Size = UDim2.fromOffset(5, 5),
			ZIndex = 2,
		}, plank)
		H.corner(nail)
	end
	local wordmark = Credits.image(C.WORDMARK)
	if wordmark then
		local wm = Instance.new("ImageLabel")
		wm.Name = "Wordmark"
		wm.BackgroundTransparency = 1
		wm.BorderSizePixel = 0
		wm.AnchorPoint = Vector2.new(0.5, 0.5)
		wm.Position = UDim2.fromScale(0.5, 0.5)
		wm.Size = UDim2.fromOffset(L.WmW, L.WmH)
		wm.ScaleType = Enum.ScaleType.Fit
		wm.Image = wordmark
		wm.ZIndex = 3
		Util.Create("UIAspectRatioConstraint", { AspectRatio = C.WM_ASPECT, Parent = wm })
		wm.Parent = plank
	else
		-- no uploaded picture (a fresh place): the studio's name on the plank
		Credits.text("WordmarkText", texts.Studio, "Heading", L.Small and 18 or 22, K.WHITE, {
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		}, plank)
	end
	Credits.text("CreatedBy", texts.Role, "Label", L.CreatedSize, S.Muted, {
		Position = UDim2.fromOffset(2, L.CreatedY),
		Size = UDim2.fromOffset(L.CreatedW - 2, L.CreatedH),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
	}, col)
	Theme.Face(col:FindFirstChild("CreatedBy"), "Caps")
	local sig = Credits.text("Signature", texts.Creator, "Signature", L.SigSize, S.Navy, {
		Position = UDim2.fromOffset(0, L.SigY),
		Size = UDim2.fromOffset(L.SigW, L.SigH),
		TextXAlignment = Enum.TextXAlignment.Left,
		Rotation = C.SIG_TILT,
		ZIndex = 2,
	}, col)
	-- the swash: one round pen stroke under the name (a child of the name: it leans with it)
	local swashW = math.min(L.SigW - 24, math.floor(L.SigSize * 3.1))
	local swash = H.frame("Swash", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.Navy,
		Position = UDim2.fromOffset(math.floor(L.SigSize * 0.12), L.SwashY - L.SigY),
		Size = UDim2.fromOffset(swashW, L.Small and 4 or 5),
	}, sig)
	H.corner(swash)
	Credits.text("Thanks", texts.Thanks, "Body", L.ThanksSize, S.Gold, {
		Position = UDim2.fromOffset(2, L.ThanksY),
		Size = UDim2.fromOffset(L.ThanksW - 2, L.ThanksH),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, col)
	Theme.Face(col:FindFirstChild("Thanks"), "Thanks")
	return col
end

-- the round SF emblem, a gold ring, tilted, in the body's bottom-right corner
function Credits.sticker(body, L)
	local C, S = K.CR, K.SIGN
	local shadow = H.frame("StickerShadow", {
		BackgroundTransparency = 0.72,
		BackgroundColor3 = S.Shadow,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(L.StickerX + 2, L.StickerY + 4),
		Size = UDim2.fromOffset(L.S, L.S),
		ZIndex = 4,
	}, body)
	H.corner(shadow)
	local emblem = Credits.image(C.EMBLEM)
	local sticker = Instance.new("ImageLabel")
	sticker.Name = "Sticker"
	sticker.BackgroundTransparency = emblem and 1 or 0
	sticker.BackgroundColor3 = S.Navy
	sticker.BorderSizePixel = 0
	sticker.AnchorPoint = Vector2.new(0.5, 0.5)
	sticker.Position = UDim2.fromOffset(L.StickerX, L.StickerY)
	sticker.Size = UDim2.fromOffset(L.S, L.S)
	sticker.ScaleType = Enum.ScaleType.Fit
	sticker.Image = emblem or ""
	sticker.Rotation = C.STICKER_TILT
	sticker.ZIndex = 5
	H.corner(sticker)
	Credits.stroke(sticker, S.Ring, L.Ring)
	sticker.Parent = body
	return sticker
end

-- builds the whole window into the docked holder (its design size is the dock's)
function Credits.build(holder, stacked)
	local C, S = K.CR, K.SIGN
	local texts = Credits.texts()
	local w, h = holder.Size.X.Offset, holder.Size.Y.Offset
	local L = Credits.layout(w, h, stacked, texts)
	local sign = H.frame("CreditsSign", { Size = UDim2.fromScale(1, 1) }, holder)
	H.frame("Drop", {
		BackgroundTransparency = 0.6,
		BackgroundColor3 = S.Drop,
		Position = UDim2.fromOffset(0, L.HeadY + C.DROP),
		Size = UDim2.new(1, 0, 0, L.HeadH + L.WoodH),
		ZIndex = 1,
	}, sign)
	Credits.roof(sign)
	Credits.head(sign, L)
	local wood = H.frame("Wood", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.Wood,
		Position = UDim2.fromOffset(0, L.WoodY),
		Size = UDim2.new(1, 0, 0, L.WoodH),
		Active = true,
		ZIndex = 3,
	}, sign)
	local body = H.frame("Body", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.Cream,
		Position = UDim2.fromOffset(C.WOOD, C.WOOD),
		Size = UDim2.new(1, -2 * C.WOOD, 1, -2 * C.WOOD),
	}, wood)
	local line = H.frame("Line", {
		Position = UDim2.fromOffset(C.LINE, C.LINE),
		Size = UDim2.new(1, -2 * C.LINE, 1, -2 * C.LINE),
		ZIndex = 1,
	}, body)
	Credits.stroke(line, S.CreamLine, C.LINE_T)
	Credits.polaroid(body, L, texts)
	Credits.column(body, L, texts)
	Credits.sticker(body, L)
	holder:SetAttribute("CreditsLayout", L.Stacked and "Stacked" or (L.Small and "Small" or "Wide"))
	return sign
end

-- quiet: a rebuild after a screen resize (no click, the window was already open)
function MainMenuController.OpenCredits(quiet)
	local vp = H.viewport()
	local stacked = vp.Y > vp.X
	local holder = Win.holder("Credits", K.CR.W, stacked and K.CR.TALL_H or K.CR.H)
	if not holder then
		return
	end
	if quiet ~= true then
		H.sound("Click")
	end
	H.safe("credits", Credits.build, holder, stacked)
	local camera = Workspace.CurrentCamera
	if camera then
		-- one rebuild per burst of size changes (a window drag fires many)
		local pending = false
		M.Win.Resize = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if pending then
				return
			end
			pending = true
			task.defer(function()
				if M.Win.Name == "Credits" and M.Win.Holder == holder then
					H.safe("credits resize", MainMenuController.OpenCredits, true)
				end
			end)
		end)
	end
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
	H.holdToasts(true)
	Loading.hook()
	Gate.close()
	H.safe("cards", Cards.close)
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
			H.safe("fade", Menu.fade, M.Menu, K.FADE)
		end
		task.wait(K.FADE)
		-- (review round 1) the release always runs to the end: every step on its own guard, so one that fails never
		-- strands the next (the HUD, the world cards and the held toasts must come back whatever happens)
		local menu = M.Menu
		M.Menu = nil
		if menu then
			H.safe("destroy", function()
				menu:Destroy()
			end)
		end
		H.safe("orbit", Orbit.stop)
		H.safe("gate", Gate.open)
		H.safe("cards", Cards.open)
		M.Open = false
		M.Playing = false
		H.safe("mouse", H.mouseHold, false)
		H.safe("played", UiGate.MarkPlayed)
		H.sound("Whoosh")
		H.holdToasts(false) -- last: the held toasts land on the game screen, the HUD already back
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
	-- Esc closes an open window (Settings / Updates / Credits; gamepad B: Win.bindBack)
	game:GetService("UserInputService").InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and M.Win.Name then
			H.sound("Click")
			Win.close()
		end
	end)
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
