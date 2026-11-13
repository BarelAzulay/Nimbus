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
-- Layout (kit B U4, .superpowers/slop-audit/round3/BUILD_PLAN.md, findings 5 and 19; SignKit / PixelIcon; design px of a
-- 1080p screen under one UIScale clamp(H / 1080, 0.8, 1.25)): no shade over the world. A Signboard on two ropes: landscape
-- at x 60 (right of the thumbstick zone on touch), 440 wide; portrait docked at the bottom above the thumb zones. The flat
-- awning, the navy header (Config.MainMenu.Header = "NIMBUS CLIMB", Title role; the greeting is the owner's pick M4), the
-- stone body: the tag line (Config.Tagline), PLAY (the one green plank, 72 tall, a 6 px lip, FredokaOne 40, the pixel
-- play triangle), SETTINGS (pixel gear) + UPDATES (pixel scroll; the pixel star while UpdateNotes.Latest >
-- Settings.SeenNotes is the one NEW marker) as half-width stone planks, the version line "vN · <latest title>" (opens
-- UPDATES) and the hint (keyboard / gamepad / touch). The CREDITS wood tag hangs on its own rope with "vN" beside it:
-- bottom-right on a desktop, top-right under Roblox's buttons on touch / portrait. (sign build, the owner's picks on
-- .superpowers/sign-pitch) Entrance "Rope drop": once the loading screen has faded, the board falls on its ropes, the
-- ropes snap taut (two pixel dust puffs, the SignThunk hook), it bounces and swings gently (Config.MainMenu.Entrance),
-- the buttons pop from their centre 60 ms apart; then it sways +-1 degree about the rope tops until PLAY
-- (Config.MainMenu.Sway; Camera shake OFF = none). The board wears SignKit.Workshop's trim. It is laid out again when the
-- viewport changes (a short screen shortens its ropes). PLAY: the board is pulled up (0.3 s, Quad In) while the camera
-- tweens to the spawn view (0.8 s, Sine InOut); the release (the HUD back, Custom) waits for it to land.
-- Behind Config.Preview.TitleShots (PICK, off): the camera holds Key A / Key P of Config.MainMenu.Shots (FOV 50) instead
-- of the orbit.
-- Windows (docked by NeonKit.Dock: right side panel / bottom sheet):
--   SETTINGS  Music and Sound (11 steps 0..10, - / + and the step segments), Graphics (Auto / Low / High chips),
--             Camera shake (ON / OFF), Mouse lock (ON / OFF, keyboard + mouse devices only; the L key toggles it too);
--             applied at once through ClientSettings.Set (sent after a 0.4 s debounce)
--   UPDATES   UpdateNotes.Notes newest first; opening it sends SettingsSet("SeenNotes", UpdateNotes.Latest)
--   (kit B U5, finding 5) Both are Signboards built from SignKit, like the title screen: the flat awning, the navy header
--             (SETTINGS / WHAT'S NEW in the Title role, gold, the pixel gear / scroll on its gold square, the red Close
--             plank with the pixel x), the wood frame and the stone body. Settings: each row its pixel icon (music,
--             speaker, monitor, camera shake, mouse; no emoji) and brown FredokaOne title; the 0..10 scale a BlockRow of
--             10 between the - / + planks; the chips planks (selected = gold with its lip). Updates: each version a navy
--             plank in FredokaOne gold, each line Nunito brown after a 6 px square bullet. Rebuilt when the screen
--             changes size.
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
--             (kit B, U2) The roof, header, wood frame and body are shared/SignKit parts; the gable (Shape = "Gable") and
--             the K.SIGN colours go in as overrides, so the window looks exactly as the owner approved it
--             (smoke credits_unchanged_on_signkit pins its dump).
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
local SignKit = require(Shared:WaitForChild("SignKit"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon"))

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
	FADE = 0.35,
	LOADING_FADE = 0.4,
	CHAR_WAIT = 5,
	ACTION = "NimbusMenuPlay",
	WIN_W = 520,
	WIN_H = 640,
	INK = Theme.Colors.PanelInk or Color3.fromRGB(8, 10, 28),
	WHITE = Color3.new(1, 1, 1),
	-- (kit B U5) the Settings / Updates Signboard windows, design px of a 1080p screen
	WIN = {
		HEAD_Y = 15, -- the header under the awning (its lower edge hides behind the header)
		HEAD_H = 64,
		CLOSE = 44, -- the red Close plank
		ICON = 27, -- the pixel icons (a multiple of 9)
		PAD = 16, -- the list inside the stone body
		BAR = 10, -- the scroll bar's room on the right
		ROW_H = 102, -- a setting: its title line, then the strip
		STRIP_Y = 42,
		BTN = 52, -- - / + and the chips
		GAP = 10,
		BLOCK_GAP = 4,
		BLOCK_H = 32,
		BULLET = 6, -- the square bullet of an update line
	},
	MOUSE_HOLD = "MainMenu",
	TOAST_HOLD = "MainMenu", -- NotifyController.SetHeld owner key (quick wins, win 1)
	TAGLINE = "Climb the storm. Together.", -- when Config.Tagline is missing
	HEADER = "NIMBUS CLIMB", -- when Config.MainMenu.Header is missing
	-- (kit B U4) the hint line on the board, by input (H.inputKind)
	HINTS = { Keyboard = "Press ENTER to play", Gamepad = "Press A to play", Touch = "Tap PLAY to jump in!" },
	-- (kit B U4) the title screen's Signboard, design px of a 1080p screen, and its motion (seconds)
	BOARD = {
		X = 60, -- landscape: from the left edge
		W = 440,
		W_MAX = 560, -- portrait: the screen less the gutter, at most this
		GUTTER = 16, -- portrait: screen px each side
		DOCK = 16, -- portrait: screen px between the board and the thumb zones (or the bottom edge)
		ROPE_AT = 0.25, -- the left rope, as a part of the board's width (the right one mirrors it) ...
		ROPE_CLEAR = 128, -- ... moved in (both) until the left rope is this many screen px from the left: Roblox's top-left buttons
		PLAY_H = 72,
		PLAY_LIP = 6,
		BTN_H = 52,
		GAP = 12, -- between SETTINGS and UPDATES
		TAG_W = 140, -- the CREDITS tag
		TAG_H = 44,
		ROPE_UP = 48, -- (sign build) the ropes start this far above the screen top: no rope end shows through a bounce
		BOTTOM = 16, -- (sign build) screen px kept free under the swinging board (shorter ropes on a short screen)
		RELAYOUT = 0.15, -- (sign build) a viewport change lays the screen out again this long after the last one
		POP_START = 0.1, -- the entrance (Config.MainMenu.Entrance): the buttons' pops, POP apart
		POP = 0.06,
		POP_TIME = 0.2,
		PULL = 0.3, -- PLAY: the board pulled up (Quad In)
		FLY = 0.8, -- PLAY: the camera to the spawn view (Sine InOut), then Custom
	},
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

-- (kit B U4, PICK) the authored shot of Config.MainMenu.Shots while Config.Preview.TitleShots is on: Key A on a wide
-- screen, Key P on a portrait one, drifting sideways and back every DriftSeconds; returns cframe, fov (nil when off)
function Orbit.shot()
	local preview = Config.Preview
	local shots = H.menuCfg().Shots
	if not (type(preview) == "table" and preview.TitleShots == true and type(shots) == "table") then
		return nil
	end
	local vp = H.viewport()
	local key = vp.Y > vp.X and shots.P or shots.A
	if type(key) ~= "table" then
		return nil
	end
	local lobby = type(Config.Lobby) == "table" and Config.Lobby or {}
	local origin = typeof(lobby.Origin) == "Vector3" and lobby.Origin or Vector3.new(0, 300, 0)
	local a = math.rad(tonumber(lobby.GateFacing) or 90)
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local drift = tonumber(key.Drift) or 0
	local period = math.max(1, tonumber(shots.DriftSeconds) or 30)
	local side = drift * (0.5 - 0.5 * math.cos(math.pi * M.Orbit.T / period)) - drift / 2
	local pos = origin + dir * (tonumber(shots.Arch) or 40) - dir * (tonumber(key.Back) or 26) + Vector3.new(0, tonumber(key.Up) or 6, 0) + right * side
	local pitch = math.rad(tonumber(key.Pitch) or 12)
	local look = dir * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
	return CFrame.lookAt(pos, pos + look), tonumber(shots.Fov) or 50
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
	local shot, fov = Orbit.shot()
	if shot then
		if O.Fov0 == nil then
			O.Fov0 = camera.FieldOfView -- given back at PLAY
		end
		camera.FieldOfView = fov
		camera.CFrame = shot
		return
	end
	local angle = (O.T / math.max(1, period)) * math.pi * 2
	local c = O.Centre
	camera.CFrame = CFrame.lookAt(
		Vector3.new(c.X + math.cos(angle) * radius, c.Y + height, c.Z + math.sin(angle) * radius),
		Vector3.new(c.X, c.Y + 8, c.Z)
	)
end

function Orbit.start()
	local O = M.Orbit
	if O.Fly then -- a PLAY's camera move still under way (/menu right after PLAY): drop it
		local fly = O.Fly
		O.Fly, O.Release = nil, false
		fly:Cancel()
	end
	if O.Conn then
		return
	end
	O.Centre = Orbit.centre()
	O.T = 0 -- each title screen starts its orbit (or a title shot's drift) from the start
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	Orbit.place(0)
	O.Conn = RunService.RenderStepped:Connect(Orbit.place)
end

-- the orbit's frame loop off (the camera stays where it is, Scriptable); cleared before the disconnect, so one that throws
-- is reported once
function Orbit.halt()
	local O = M.Orbit
	local conn = O.Conn
	O.Conn = nil
	if conn then
		conn:Disconnect()
	end
end

-- (kit B U4) where the camera lands at PLAY: behind the character (or the lobby spawn, looking towards the gates), up a little
function Orbit.spawnView()
	local lobby = type(Config.Lobby) == "table" and Config.Lobby or {}
	local a = math.rad(tonumber(lobby.GateFacing) or 90)
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	local at = (typeof(lobby.Origin) == "Vector3" and lobby.Origin or Vector3.new(0, 300, 0)) + Vector3.new(0, 3, 0)
	local root = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		at = root.Position
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.1 then
			dir = flat.Unit
		end
	end
	return CFrame.lookAt(at - dir * 14 + Vector3.new(0, 6, 0), at + Vector3.new(0, 2, 0) + dir * 6)
end

-- (kit B U4) PLAY: the camera tweens to the spawn view (0.8 s, Sine InOut; a title shot's field of view goes back with it);
-- Custom follows when it lands, or at the release if that comes later (Orbit.stop)
function Orbit.fly()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local O = M.Orbit
	local goal = { CFrame = Orbit.spawnView() }
	if O.Fov0 then
		goal.FieldOfView = O.Fov0
	end
	local fly = TweenService:Create(camera, TweenInfo.new(K.BOARD.FLY, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
	O.Fly, O.Release = fly, false
	fly.Completed:Connect(function()
		if O.Fly ~= fly then
			return
		end
		O.Fly = nil
		if O.Release then
			O.Release = false
			Orbit.custom()
		end
	end)
	fly:Play()
end

-- the camera back to Custom on the humanoid, a title shot's field of view given back
function Orbit.custom()
	local O = M.Orbit
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if O.Fov0 then
		camera.FieldOfView = O.Fov0
		O.Fov0 = nil
	end
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- the release after PLAY: the orbit off and the camera Custom, once the PLAY camera move has landed
function Orbit.stop()
	Orbit.halt()
	if M.Orbit.Fly then
		M.Orbit.Release = true
		return
	end
	Orbit.custom()
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

-- (U4 review) runs fn once the loading screen is done (its Done, or it is gone), at once when none is up
function Loading.onDone(fn)
	local pg = H.playerGui()
	local gui = pg and pg:FindFirstChild("NimbusLoading")
	if not gui or gui:GetAttribute("Done") == true then
		fn()
		return
	end
	local conns = {}
	local function finish()
		if not conns[1] then
			return
		end
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		conns = {}
		fn()
	end
	conns[1] = gui:GetAttributeChangedSignal("Done"):Connect(function()
		if gui:GetAttribute("Done") == true then
			finish()
		end
	end)
	conns[2] = gui.AncestryChanged:Connect(function()
		if not gui.Parent then
			finish()
		end
	end)
end

-- (sign build) runs fn once the loading screen has faded away: when it is gone (Loading.fade destroys it), or its fade's
-- length after Done should it linger; at once when none is up. The owner's pick: the sign drops in only after the fade
function Loading.afterFade(fn)
	local pg = H.playerGui()
	local gui = pg and pg:FindFirstChild("NimbusLoading")
	if not gui then
		fn()
		return
	end
	local done, conn = false, nil
	local function finish()
		if done then
			return
		end
		done = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		fn()
	end
	conn = gui.AncestryChanged:Connect(function()
		if not gui.Parent then
			finish()
		end
	end)
	Loading.onDone(function()
		task.delay(K.LOADING_FADE + 0.15, finish)
	end)
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

-- (kit B U4) a PixelIcon left of a plank's label, the two centred together on the face by a row layout (the engine
-- measures the text: AutomaticSize); returns the icon. (U5 review) The text is fitted again to the face less the icon
-- and the gap (SignKit fitted it to the bare face), and the auto-sized label never truncates: under the board's UIScale
-- a 1 px auto-size shortfall would otherwise draw "PLA..."
function Menu.plankIcon(plank, name, px, colour)
	local face = plank:FindFirstChild("Face", true)
	local label = face and face:FindFirstChild("Label")
	local icon = label and PixelIcon.New(face, name, px, colour)
	if not icon then
		return nil
	end
	local gap = math.floor(px * 0.4)
	local group = H.frame("Group", { Size = UDim2.fromScale(1, 1), ZIndex = 3 }, face)
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap),
		Parent = group,
	})
	icon.LayoutOrder = 1
	icon.ZIndex = 3
	icon.Parent = group
	local edge = plank:GetAttribute("EdgePx") or SignKit.Sizes.Edge
	local room = plank.Size.X.Offset - 2 * edge - 2 * SignKit.Sizes.LabelPad - icon.Size.X.Offset - gap
	label.TextSize = SignKit.FitSize(label.Text, label.TextSize, room)
	label.TextTruncate = Enum.TextTruncate.None
	label.LayoutOrder = 2
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Position = UDim2.fromOffset(0, 0)
	label.Size = UDim2.new(0, 0, 1, 0)
	label.Parent = group
	return icon
end
MainMenuController._PlankIcon = Menu.plankIcon -- tests (U5 review)

-- the hint line's input: a gamepad (a console, or the pad was the last input), touch, else keyboard
function H.inputKind()
	local UIS = game:GetService("UserInputService")
	local last = nil
	pcall(function()
		last = UIS:GetLastInputType()
	end)
	local padLast = last ~= nil and string.find(tostring(last), "Gamepad", 1, true) ~= nil
	if UIS.GamepadEnabled and (not UIS.KeyboardEnabled or padLast) then
		return "Gamepad"
	end
	if H.isTouch() then
		return "Touch"
	end
	return "Keyboard"
end

-- (kit B U4) the title screen: the Signboard hanging on two ropes over the world (no shade). Design px of a 1080p screen
-- under one UIScale (Theme.ScreenFactor). Landscape: the board at x 60 (right of the thumbstick zone on a touch screen),
-- 440 wide, a little above the middle; portrait: docked at the bottom just above the thumbstick / jump zones, the screen
-- less a 16 px gutter wide (560 at most). In the board: the awning, the navy header (Config.MainMenu.Header, Title role),
-- the stone body with the tag line, PLAY (the one green plank), SETTINGS + UPDATES (half-width stone planks; the pixel
-- star on UPDATES is the one NEW marker), the version line (opens UPDATES) and the hint line. The CREDITS tag hangs on
-- its own rope, "vN" beside it: bottom-right on a desktop, top-right under Roblox's buttons on a landscape touch screen,
-- and under the board (swinging with it, between the thumb zones) on a portrait one, where the top strip has room only
-- for the board's two ropes (U4 review). The ropes keep right of Roblox's top-left buttons (ROPE_CLEAR).
-- `enter`: the board drops in on its ropes, settles with a swing, the buttons pop (Menu.enter)
function Menu.build(enter)
	local gui = Menu.gui()
	if not gui then
		return nil
	end
	local old = gui:FindFirstChild("Menu")
	if old then
		old:Destroy()
	end
	local B, Z, Sign = K.BOARD, SignKit.Sizes, Theme.Sign
	local vp = H.viewport()
	local f = Theme.ScreenFactor(vp.Y)
	local portrait = vp.Y > vp.X
	local dw, dh = vp.X / f, vp.Y / f
	local short = dh < 600
	local menu = H.frame("Menu", { Size = UDim2.fromScale(1, 1), Active = true, ZIndex = 1 }, gui)
	M.Menu = menu
	M.Ui = {}
	local content = H.frame("Content", { Size = UDim2.fromOffset(math.floor(dw + 0.5), math.floor(dh + 0.5)), ZIndex = 2 }, menu)
	Util.Create("UIScale", { Name = "ReadScale", Scale = f, Parent = content })

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

	-- the board's size: header, then the body rows top-down (the tag line drops out on a short screen)
	local boardW = portrait and math.floor(math.min(dw - 2 * B.GUTTER / f, B.W_MAX)) or B.W
	local inner = boardW - 2 * Z.Frame
	local pad = short and 14 or 18
	local headY = Z.RoofH - 3
	local headH = short and 56 or 72
	local tagH = short and 0 or 26
	local playW = inner - 2 * pad
	local y = pad
	local rows = {}
	if tagH > 0 then
		rows.Tag = y - 4
		y = y + tagH + 8
	end
	rows.Play = y
	y = y + B.PLAY_H + 10
	rows.Pair = y
	y = y + B.BTN_H + 8
	rows.Version = y
	y = y + 24 + 2
	rows.Hint = y
	y = y + 22 + pad
	local bodyH = y + Z.Lip
	local woodH = bodyH + 2 * Z.Frame
	local boardH = headY + headH + woodH

	-- the CREDITS tag: its rope, then the plank; "vN" (its measured width) on its left
	local notes = H.notes()
	local latest = tostring(notes and notes.Latest or 6)
	local tagW, ropeH, vW = B.TAG_W, 22, 48
	local okV, vSize = pcall(Theme.Measure, "v" .. latest, "Label", 18)
	if okV and vSize then
		vW = math.ceil(vSize.X) + 6
	end
	local lead = vW + 8

	-- where it hangs: below Roblox's top bar; a portrait board docks above the thumb zones (and above the CREDITS tag
	-- hanging under it where there are no thumb zones)
	local minTop = math.ceil(58 / f) + 12
	local boardX, topY
	if portrait then
		boardX = math.floor((dw - boardW) / 2)
		local below = math.max(zoneH, math.ceil((ropeH + B.TAG_H) * f) + 8)
		topY = math.max(minTop, math.floor(dh - (below + B.DOCK) / f - boardH))
	else
		boardX = math.max(B.X, touch and math.ceil((zoneW + 8) / f) or 0)
		topY = math.max(minTop, math.floor((dh - boardH) * 0.42))
	end
	-- (sign build) the swinging board ends B.BOTTOM screen px above the bottom: on a short screen its ropes shorten (it
	-- hangs higher, at most up to 8 design px from the top)
	local droop = math.ceil(0.5 * boardW * math.sin(math.rad(Menu.maxTilt())))
	local lowest = math.floor(dh - B.BOTTOM / f - droop - boardH)
	if topY > lowest then
		topY = math.max(8, lowest)
	end
	local half = topY + boardH
	local side = 32
	local swing = H.frame("Swing", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(boardX + math.floor(boardW / 2), 0),
		Size = UDim2.fromOffset(boardW + 2 * side, 2 * half),
		ZIndex = 2,
	}, content)
	-- the ropes: at ROPE_AT and its mirror, moved in together until the left one clears Roblox's top-left buttons
	-- (sign build) each from ROPE_UP above the screen top to 8 px into the board (no rope end shows through a bounce)
	local ropeAt = math.min(math.max(B.ROPE_AT, (B.ROPE_CLEAR / f + Z.RopeW / 2 - boardX) / boardW), 0.4)
	local ropes = {}
	for i, at in ipairs({ ropeAt, 1 - ropeAt }) do
		ropes[i] = SignKit.Rope(swing, {
			Name = "Rope",
			Length = topY + 8 + B.ROPE_UP,
			Position = UDim2.fromOffset(side + math.floor(at * boardW) - math.floor(Z.RopeW / 2), half - B.ROPE_UP),
			ZIndex = 1,
			LayoutOrder = i,
		})
	end
	local board = H.frame("Board", { Position = UDim2.fromOffset(side, half + topY), Size = UDim2.fromOffset(boardW, boardH), ZIndex = 2 }, swing)
	local roof = SignKit.Roof(board, { Width = boardW + 24, ZIndex = 3 })
	-- the header title: Config.MainMenu.Header in the Title role, stepped down until it fits the plate with 12 px each side
	local header = tostring(H.menuCfg().Header or K.HEADER)
	local titleSize = short and 44 or 54
	local room = boardW - 2 * Z.Rim - 24
	while titleSize > 24 do
		local ok, size = pcall(Theme.Measure, header, "Title", titleSize)
		if not ok or not size or size.X <= room then
			break
		end
		titleSize = titleSize - 2
	end
	local head, plate = SignKit.Header(board, { Title = header, TitleSize = titleSize, Y = headY, Height = headH, ZIndex = 2 })
	local title = plate:FindFirstChild("Title")
	if title then
		title.Position = UDim2.fromOffset(0, 0)
		title.Size = UDim2.fromScale(1, 1)
		title.TextXAlignment = Enum.TextXAlignment.Center
	end
	local wood = SignKit.Frame(board, { Y = headY + headH, Height = woodH, ZIndex = 1 })
	local body = SignKit.Body(wood)
	-- (sign build) the owner's "Workshop" trim: grain, nails, rope rings, the striped awning's notched lip, a chip
	SignKit.Workshop({ Roof = roof, Head = head, Frame = wood, Ropes = ropes })

	local tagline = Theme.Label(tostring(Config.Tagline or K.TAGLINE), "Body", { Size = 20, Color = Theme.TextOn("Stone") })
	tagline.Name = "Tagline"
	tagline.Position = UDim2.fromOffset(pad, rows.Tag or 0)
	tagline.Size = UDim2.fromOffset(playW, math.max(tagH, 1))
	tagline.Visible = tagH > 0
	tagline.ZIndex = 2
	tagline.Parent = body

	M.Ui.Play = SignKit.Plank(body, {
		Name = "PlayButton",
		Text = "PLAY",
		Style = "Grass",
		Width = playW,
		Height = B.PLAY_H,
		LipPx = B.PLAY_LIP,
		TextSize = 40,
		Position = UDim2.fromOffset(pad, rows.Play),
		ZIndex = 2,
		Callback = function()
			MainMenuController.Play()
		end,
	})
	Menu.plankIcon(M.Ui.Play, "play", 27, Sign.OnGrass) -- (U5) the label's dark green, like the pitch's icon (currentColor)
	local halfW = math.floor((playW - B.GAP) / 2)
	M.Ui.Settings = SignKit.Plank(body, {
		Name = "SettingsButton",
		Text = "SETTINGS",
		Width = halfW,
		Height = B.BTN_H,
		TextSize = 22,
		Position = UDim2.fromOffset(pad, rows.Pair),
		ZIndex = 2,
		Callback = function()
			MainMenuController.OpenSettings()
		end,
	})
	Menu.plankIcon(M.Ui.Settings, "gear", 18, Sign.Text)
	M.Ui.Updates = SignKit.Plank(body, {
		Name = "UpdatesButton",
		Text = "UPDATES",
		Width = halfW,
		Height = B.BTN_H,
		TextSize = 22,
		Position = UDim2.fromOffset(pad + playW - halfW, rows.Pair),
		ZIndex = 2,
		Callback = function()
			MainMenuController.OpenUpdates()
		end,
	})
	Menu.plankIcon(M.Ui.Updates, "scroll", 18, Sign.Text)
	-- (sign build, U4 minor) anchored at their centre, so the entrance's pop grows them from the middle, not a corner
	for _, plank in ipairs({ M.Ui.Play, M.Ui.Settings, M.Ui.Updates }) do
		local p, s = plank.Position, plank.Size
		plank.AnchorPoint = Vector2.new(0.5, 0.5)
		plank.Position = UDim2.fromOffset(p.X.Offset + math.floor(s.X.Offset / 2), p.Y.Offset + math.floor(s.Y.Offset / 2))
	end
	-- the one NEW marker: a gold pixel star on a dark tile at UPDATES' corner (shown while UpdateNotes.Latest > SeenNotes);
	-- (U5) the star is drawn at 18 (a multiple of 9) and the tile grows round it by a 4 px padding
	local badge = PixelIcon.New(M.Ui.Updates, "star", 18, Sign.Gold)
	badge.Name = "NewBadge"
	badge.Size = UDim2.fromOffset(26, 26)
	Util.Create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), Parent = badge })
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = Sign.Text
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -6, 0, 6)
	badge.ZIndex = 5
	M.Ui.NewBadge = badge
	Menu.refreshBadge()

	-- the version line (opens UPDATES) and the hint line, Nunito on the stone
	local first = notes and type(notes.Notes) == "table" and notes.Notes[1] or nil
	local versionText = "v" .. latest
	if first and type(first.Title) == "string" then
		versionText = versionText .. " \194\183 " .. first.Title
	end
	local version = Instance.new("TextButton")
	version.Name = "VersionLine"
	version.AutoButtonColor = false
	version.BackgroundTransparency = 1
	version.Text = versionText
	Theme.Style(version, "Body", { Size = 18, Color = Sign.TextMuted })
	version.TextTruncate = Enum.TextTruncate.AtEnd
	version.Position = UDim2.fromOffset(pad, rows.Version)
	version.Size = UDim2.fromOffset(playW, 24)
	version.ZIndex = 2
	version.Parent = body
	version.Activated:Connect(function()
		MainMenuController.OpenUpdates()
	end)
	local hint = Theme.Label(K.HINTS[H.inputKind()] or K.HINTS.Keyboard, "Label", { Size = 18, Color = Sign.TextMuted })
	hint.Name = "Hint"
	hint.Position = UDim2.fromOffset(pad, rows.Hint)
	hint.Size = UDim2.fromOffset(playW, 22)
	hint.ZIndex = 2
	hint.Parent = body

	-- the CREDITS tag on its rope with "vN" beside it: bottom-right on a desktop; top-right under Roblox's buttons on a
	-- landscape touch screen (clear of the thumb zones); on a portrait screen it hangs from the board's bottom edge,
	-- centred between the thumb zones, and drops, swings and leaves with the board (it is in the Swing)
	local tag = H.frame("CreditsTag", { Size = UDim2.fromOffset(lead + tagW, ropeH + B.TAG_H), ZIndex = 3 }, portrait and swing or content)
	if portrait then
		tag.Position = UDim2.fromOffset(side + math.floor((boardW - lead - tagW) / 2), half + topY + boardH)
	elseif touch then
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.fromOffset(math.floor(dw - 16 / f), math.ceil(58 / f) + 4)
	else
		tag.AnchorPoint = Vector2.new(1, 1)
		tag.Position = UDim2.fromOffset(math.floor(dw - 20), math.floor(dh - 18))
	end
	H.frame("Peg", { BackgroundTransparency = 0, BackgroundColor3 = Sign.Text, Position = UDim2.fromOffset(lead + math.floor(tagW / 2) - 6, 0), Size = UDim2.fromOffset(12, 6), ZIndex = 4 }, tag)
	SignKit.Rope(tag, { Name = "Rope", Length = ropeH + 6, Position = UDim2.fromOffset(lead + math.floor((tagW - Z.RopeW) / 2), 2), ZIndex = 3 })
	M.Ui.Credits = SignKit.Plank(tag, {
		Name = "CreditsButton",
		Text = "CREDITS",
		Width = tagW,
		Height = B.TAG_H,
		TextSize = 18,
		Face = Sign.Wood,
		Lip = K.SIGN.WoodDark,
		Edge = Sign.Text,
		TextColor = Sign.Stone,
		Position = UDim2.fromOffset(lead, ropeH),
		ZIndex = 4,
		Callback = function()
			MainMenuController.OpenCredits()
		end,
	})
	local v = Theme.Label("v" .. latest, "Label", { Size = 18, Color = K.WHITE, Outline = "World", OutlineColor = K.INK })
	v.Name = "Version"
	v.Position = UDim2.fromOffset(0, ropeH)
	v.Size = UDim2.fromOffset(vW, B.TAG_H - Z.Lip)
	v.TextXAlignment = Enum.TextXAlignment.Right
	v.ZIndex = 4
	v.Parent = tag

	M.Ui.Swing, M.Ui.Board, M.Ui.Tag = swing, board, tag
	M.Ui.Rest, M.Ui.Lift = swing.Position, half + 40
	-- (sign build) the screen it was laid out for, and where the dust puffs rise at the snap (beside the awning's ends)
	M.Ui.Vp, M.Ui.Content, M.Ui.Tw = vp, content, {}
	M.Ui.PuffAt = { L = boardX - 18, R = boardX + boardW + 18, Y = topY + 22 }
	if enter then
		Menu.enter()
	end
	return menu
end

-- (sign build) the entrance and sway numbers (Config.MainMenu.Entrance / Sway)
function Menu.entrance()
	local E = H.menuCfg().Entrance
	return type(E) == "table" and E or { Drop = 0.6, Bounce = {}, BounceTime = 0.13, Swing = {}, SwingTime = 0.32, Puff = 0.45 }
end

function Menu.swayCfg()
	local W = H.menuCfg().Sway
	return type(W) == "table" and W or { Degrees = 0, Period = 3.6 }
end

-- the sway is on: some degrees, and Settings Camera shake not OFF
function Menu.swayOn()
	return (tonumber(Menu.swayCfg().Degrees) or 0) > 0 and ClientSettings.Get("Shake") ~= false
end

-- the most the board turns (the entrance's swing, the sway): the layout keeps its lower corner on screen
function Menu.maxTilt()
	local most = tonumber(Menu.swayCfg().Degrees) or 0
	for _, d in ipairs(Menu.entrance().Swing or {}) do
		most = math.max(most, math.abs(tonumber(d) or 0))
	end
	return most
end

-- one motion of the board at a time per key ("Move" = Position, "Turn" = Rotation): a new one cancels the one before.
-- onDone runs when it completes (never when it was cancelled, the menu was rebuilt or PLAY began); a finished tween is
-- destroyed with its connection
function Menu.tween(ui, key, inst, info, goal, onDone)
	local old = ui.Tw[key]
	if old then
		ui.Tw[key] = nil
		old:Cancel()
	end
	local tw = TweenService:Create(inst, info, goal)
	ui.Tw[key] = tw
	tw.Completed:Connect(function(state)
		if ui.Tw[key] == tw then
			ui.Tw[key] = nil
		end
		tw:Destroy()
		if onDone and state == Enum.PlaybackState.Completed and M.Ui == ui and not M.Playing and inst.Parent then
			onDone()
		end
	end)
	tw:Play()
	return tw
end

-- steps = { { Info, Goal }, ... } played one after the other on `key`, then done()
function Menu.chain(ui, key, inst, steps, done)
	local i = 0
	local function step()
		i = i + 1
		local s = steps[i]
		if not s then
			if done then
				done()
			end
			return
		end
		Menu.tween(ui, key, inst, s[1], s[2], step)
	end
	step()
end

-- every board motion stopped (PLAY, a re-layout)
function Menu.stopMotion(ui)
	for key, tw in pairs(ui.Tw or {}) do
		ui.Tw[key] = nil
		tw:Cancel()
	end
end

-- (kit B U4; sign build, the owner's pick "Rope drop") the entrance. On a real join the menu opens at boot under the
-- loading screen: the board waits lifted, the buttons at pop scale 0, and the entrance starts once the loading screen
-- has FADED away (built again first if the screen changed size meanwhile); with no loading screen up (/menu) at once.
-- The board falls on its ropes (Entrance.Drop, Quad In) while PLAY, SETTINGS and UPDATES pop in from their centres
-- (a UIScale "Pop" 0 -> 1, 60 ms apart); Menu.snap follows
function Menu.enter()
	local ui = M.Ui
	if not Menu.lift(ui) then
		return
	end
	Loading.afterFade(function()
		if M.Ui ~= ui or not ui.Swing.Parent or M.Playing then
			return
		end
		local vp = H.viewport()
		if vp.X ~= ui.Vp.X or vp.Y ~= ui.Vp.Y then
			if not H.safe("build", Menu.build, false) or not M.Ui.Swing then
				return
			end
			ui = M.Ui
			Menu.lift(ui)
		end
		Menu.run(ui)
	end)
end

-- the board lifted off the top of the screen, the buttons at pop scale 0
function Menu.lift(ui)
	local swing, rest = ui.Swing, ui.Rest
	if not swing then
		return false
	end
	ui.Phase = "Waiting"
	swing.Position = UDim2.new(rest.X.Scale, rest.X.Offset, rest.Y.Scale, rest.Y.Offset - ui.Lift)
	ui.Pops = {}
	for i, plank in ipairs({ ui.Play, ui.Settings, ui.Updates }) do
		ui.Pops[i] = Util.Create("UIScale", { Name = "Pop", Scale = 0, Parent = plank })
	end
	return true
end

function Menu.run(ui)
	local B, E = K.BOARD, Menu.entrance()
	ui.Phase = "Entering"
	Menu.tween(ui, "Move", ui.Swing, TweenInfo.new(tonumber(E.Drop) or 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = ui.Rest }, function()
		Menu.snap(ui)
	end)
	for i, pop in ipairs(ui.Pops) do
		TweenService:Create(pop, TweenInfo.new(B.POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, B.POP_START + (i - 1) * B.POP), { Scale = 1 }):Play()
	end
end

-- the ropes snap taut: the thunk, two dust puffs, then the gentle bounces (up Bounce[i] design px, Sine Out, back down,
-- Sine In) and the swing legs (Sine InOut from level: no instant tilt); with the sway on, the last leg ends where the
-- sway starts, else the board swings back to level. Then it rests (Menu.sway)
function Menu.snap(ui)
	local E = Menu.entrance()
	local swing, rest = ui.Swing, ui.Rest
	if type(E.Sound) == "string" then
		H.sound(E.Sound)
	end
	H.safe("puffs", Menu.puffs, ui)
	local half = tonumber(E.BounceTime) or 0.13
	local hops = {}
	for _, b in ipairs(E.Bounce or {}) do
		local up = UDim2.new(rest.X.Scale, rest.X.Offset, rest.Y.Scale, rest.Y.Offset - math.floor(tonumber(b) or 0))
		hops[#hops + 1] = { TweenInfo.new(half, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Position = up } }
		hops[#hops + 1] = { TweenInfo.new(half, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Position = rest } }
	end
	Menu.chain(ui, "Move", swing, hops)
	local legs = {}
	for _, d in ipairs(E.Swing or {}) do
		legs[#legs + 1] = tonumber(d) or 0
	end
	if Menu.swayOn() then
		legs[math.max(1, #legs)] = -(tonumber(Menu.swayCfg().Degrees) or 0)
	else
		legs[#legs + 1] = 0
	end
	local turns = {}
	for _, d in ipairs(legs) do
		turns[#turns + 1] = { TweenInfo.new(tonumber(E.SwingTime) or 0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rotation = d } }
	end
	Menu.chain(ui, "Turn", swing, turns, function()
		ui.Phase = "Rest"
		Menu.sway(ui)
	end)
end

-- two pixel dust puffs beside the awning's ends: three flat white blocks each (no image), drifting out and up while they
-- fade, then gone
function Menu.puffs(ui)
	local at, content = ui.PuffAt, ui.Content
	if not (at and content and content.Parent) then
		return
	end
	local info = TweenInfo.new(tonumber(Menu.entrance().Puff) or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, side in ipairs({ -1, 1 }) do
		local x = side < 0 and at.L or at.R
		local puff = H.frame("DustPuff", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(x, at.Y), Size = UDim2.fromOffset(40, 22), ZIndex = 4 }, content)
		for _, b in ipairs({ { 0, 8 }, { 10, 0 }, { 20, 8 } }) do
			local block = H.frame("PuffBlock", {
				BackgroundTransparency = 0,
				BackgroundColor3 = K.WHITE,
				Position = UDim2.fromOffset(b[1], b[2]),
				Size = UDim2.fromOffset(20, 14),
				ZIndex = 4,
			}, puff)
			TweenService:Create(block, info, { BackgroundTransparency = 1 }):Play()
		end
		local drift = TweenService:Create(puff, info, { Position = UDim2.fromOffset(x + side * 26, at.Y - 14) })
		drift.Completed:Connect(function()
			drift:Destroy()
			if puff.Parent then
				puff:Destroy()
			end
		end)
		drift:Play()
	end
end

-- (sign build, the owner's note "make it stay moving gently after dropping") the board at rest sways +-Sway.Degrees about
-- the rope tops (the Swing's centre at the screen top), Sway.Period a full back-and-forth, Sine InOut, endlessly, until
-- PLAY; Camera shake OFF = no sway: the board turns back to level. Called again when the setting changes
function Menu.sway(ui)
	local swing = ui and ui.Swing
	if not swing or not swing.Parent or ui.Phase ~= "Rest" or M.Playing or M.Ui ~= ui then
		return
	end
	local W = Menu.swayCfg()
	local d = tonumber(W.Degrees) or 0
	if Menu.swayOn() then
		if ui.Swaying and ui.Tw.Turn == ui.Swaying then
			return
		end
		local function start()
			ui.Swaying = Menu.tween(ui, "Turn", swing, TweenInfo.new((tonumber(W.Period) or 3.6) / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = d })
		end
		if math.abs(swing.Rotation + d) > 0.01 then
			Menu.tween(ui, "Turn", swing, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rotation = -d }, start)
		else
			start()
		end
	else
		ui.Swaying = nil
		if math.abs(swing.Rotation) > 1e-3 then
			Menu.tween(ui, "Turn", swing, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Rotation = 0 })
		elseif ui.Tw.Turn then
			local tw = ui.Tw.Turn
			ui.Tw.Turn = nil
			tw:Cancel()
		end
	end
end

-- (sign build) the title screen laid out again for the screen it is on now (a viewport change): the board keeps its
-- phase (still waiting for the loading screen, or at rest with its sway); an open portrait sheet keeps it hidden
function Menu.relayout()
	local old = M.Ui
	if not M.Open or M.Playing or not M.Menu or not old.Vp then
		return
	end
	local vp = H.viewport()
	if vp.X == old.Vp.X and vp.Y == old.Vp.Y then
		return
	end
	Menu.stopMotion(old)
	if not H.safe("relayout", Menu.build, false) or not M.Ui.Swing then
		return
	end
	local ui = M.Ui
	if old.Phase == "Waiting" then
		Menu.enter()
	else
		ui.Phase = "Rest"
		Menu.sway(ui)
	end
	if M.Win.Name and M.Win.Name ~= "Credits" and vp.Y > vp.X then
		ui.Swing.Visible = false
	end
end

-- (sign build) watch the viewport while the menu is open: every change (and a new CurrentCamera, as at boot) lays the
-- screen out again RELAYOUT s after the last one of a burst (a window drag fires many). on = false disconnects it
function Menu.watch(on)
	for _, key in ipairs({ "Resize", "CameraWatch" }) do
		if M[key] then
			M[key]:Disconnect()
			M[key] = nil
		end
	end
	M.RelayoutToken = (M.RelayoutToken or 0) + 1
	if not on then
		return
	end
	local function schedule()
		M.RelayoutToken = M.RelayoutToken + 1
		local token = M.RelayoutToken
		task.delay(K.BOARD.RELAYOUT, function()
			if M.RelayoutToken == token then
				H.safe("relayout", Menu.relayout)
			end
		end)
	end
	local function hook(camera)
		if M.Resize then
			M.Resize:Disconnect()
			M.Resize = nil
		end
		if camera then
			M.Resize = camera:GetPropertyChangedSignal("ViewportSize"):Connect(schedule)
		end
	end
	hook(Workspace.CurrentCamera)
	pcall(function()
		M.CameraWatch = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			hook(Workspace.CurrentCamera)
			schedule()
		end)
	end)
end

-- (kit B U4) PLAY: every board motion stops (the sway too), the board is pulled up off the screen (0.3 s, Quad In) and
-- the CREDITS tag fades with it
function Menu.leave()
	local B, ui = K.BOARD, M.Ui
	Menu.stopMotion(ui)
	ui.Phase, ui.Swaying = "Leaving", nil
	local swing = ui.Swing
	if swing and swing.Parent then
		local p = ui.Rest or swing.Position
		TweenService:Create(swing, TweenInfo.new(B.PULL, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset - (ui.Lift or 600)),
		}):Play()
	end
	if ui.Tag and ui.Tag.Parent then
		Menu.fade(ui.Tag, B.PULL)
	end
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
	if M.Ui.Swing then
		M.Ui.Swing.Visible = true -- (U5) the title screen's board comes back (Win.open hid it behind a portrait sheet)
	end
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

-- (kit B U5) a pixel icon in the middle of a plank's face (a plank with no text: Close, - and +); returns the icon
function Win.mark(plank, name, colour, px)
	local face = plank and plank:FindFirstChild("Face", true)
	local icon = face and PixelIcon.New(face, name, px or K.WIN.ICON, colour)
	if icon then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 4
	end
	return icon
end

-- (kit B U5) the window's scrolling list on the stone body (a 16 px margin, room for the scroll bar on the right, the
-- body's lip kept clear)
function Win.list(body)
	local D, Z = K.WIN, SignKit.Sizes
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(D.PAD, D.PAD)
	list.Size = UDim2.new(1, -2 * D.PAD, 1, -(2 * D.PAD + Z.Lip))
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.Sign.Wood
	list.ZIndex = 2
	list.Parent = body
	Util.Create("UIPadding", { PaddingRight = UDim.new(0, D.BAR), Parent = list })
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
		Parent = list,
	})
	return list
end

-- (kit B U5, finding 5) a Signboard window like the title screen's board: the flat awning (one fixed-size piece), the
-- navy header with `title` in the Title role (gold, stepped down until it fits), the pixel `icon` on its gold square and
-- the red Close plank with the pixel x, the wood frame and the stone body holding the scrolling list. It is built at the
-- docked design size and rebuilt by `reopen(true)` when the screen changes size (as Credits is). Returns the list and its
-- content width (design px)
function Win.open(name, title, icon, prefH, reopen)
	local holder = Win.holder(name, K.WIN_W, prefH)
	if not holder then
		return nil
	end
	local W, D, Z, Sign = M.Win, K.WIN, SignKit.Sizes, Theme.Sign
	local w = holder.Size.X.Offset
	local vp = H.viewport()
	if M.Ui.Swing and vp.Y > vp.X then
		-- a portrait sheet covers the docked title board but for its awning's ends: the board waits hidden (Win.close)
		M.Ui.Swing.Visible = false
	end
	local sign = H.frame(name .. "Sign", { Size = UDim2.fromScale(1, 1) }, holder)
	SignKit.Roof(sign, { Width = w + 20, ZIndex = 3 })
	local room = w - 2 * Z.Rim - (12 + Z.IconSlot + 12) - (D.CLOSE + 20)
	local size = Theme.RoleSize("Title")
	while size > 22 do
		local ok, m = pcall(Theme.Measure, title, "Title", size)
		if not ok or not m or m.X <= room then
			break
		end
		size = size - 2
	end
	local _, plate = SignKit.Header(sign, {
		Title = title,
		TitleSize = size,
		IconSlot = true,
		Reserve = D.CLOSE + 20,
		Y = D.HEAD_Y,
		Height = D.HEAD_H,
		ZIndex = 2,
	})
	local slot = plate:FindFirstChild("IconSlot")
	local mark = slot and PixelIcon.New(slot, icon, D.ICON, Sign.Text)
	if mark then
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(0.5, 0.5)
	end
	local close = SignKit.Plank(plate, {
		Name = "Close",
		Text = "",
		Style = "Red",
		Width = D.CLOSE,
		Height = D.CLOSE,
		LipPx = 6,
		Edge = Sign.Text, -- the pitch's close X: an ink edge
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		ZIndex = 3,
		Callback = function()
			H.sound("Click")
			Win.close()
		end,
	})
	Win.mark(close, "x", K.WHITE, 18)
	local wood = SignKit.Frame(sign, { Y = D.HEAD_Y + D.HEAD_H, ZIndex = 1 })
	local body = SignKit.Body(wood)
	W.Panel = body
	local list = Win.list(body)
	local camera = Workspace.CurrentCamera
	if camera and reopen then
		-- one rebuild per burst of size changes (a window drag fires many)
		local pending = false
		W.Resize = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if pending then
				return
			end
			pending = true
			task.defer(function()
				if M.Win.Name == name and M.Win.Holder == holder then
					H.safe(name .. " resize", reopen, true)
				end
			end)
		end)
	end
	return list, w - 2 * Z.Frame - 2 * D.PAD - D.BAR
end

-- a setting's title line on the stone: its pixel icon, the title (brown FredokaOne) and, for a scale, the value
function Win.rowHead(row, title, icon, withValue, width)
	local D, ink = K.WIN, Theme.TextOn("Stone")
	local mark = PixelIcon.New(row, icon, D.ICON, ink)
	if mark then
		mark.Position = UDim2.fromOffset(0, 4)
	end
	local room = width - (D.ICON + 10 + (withValue and 90 or 0))
	local size = 24
	while size > 18 do
		local ok, m = pcall(Theme.Measure, title, "Heading", size)
		if not ok or not m or m.X <= room then
			break
		end
		size = size - 1
	end
	local label = Theme.Label(title, "Heading", { Size = size, Color = ink })
	label.Name = "Title"
	label.Position = UDim2.fromOffset(D.ICON + 10, 0)
	label.Size = UDim2.new(1, -(D.ICON + 10 + (withValue and 90 or 0)), 0, 34)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = row
	if not withValue then
		return nil
	end
	local value = Theme.Label("", "Display", { Size = 26, Color = ink })
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, 0, 0, 0)
	value.Size = UDim2.fromOffset(90, 34)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = row
	return value
end

-- a 0..10 setting (kit B U5): the title line, then - [a SignKit BlockRow of 10, each block a tap target] +; the first
-- <value> blocks are gold
function Win.sliderRow(parent, key, title, icon, order, width)
	local D = K.WIN
	local row = H.frame("Row_" .. key, { Size = UDim2.new(1, 0, 0, D.ROW_H), LayoutOrder = order }, parent)
	local value = Win.rowHead(row, title, icon, true, width)
	local strip = H.frame("Strip", { Position = UDim2.fromOffset(0, D.STRIP_Y), Size = UDim2.new(1, 0, 0, D.BTN) }, row)
	local function step(delta)
		H.sound("Click")
		ClientSettings.Set(key, (tonumber(ClientSettings.Get(key)) or 0) + delta)
	end
	local minus = SignKit.Plank(strip, { Name = "Minus", Text = "", Width = D.BTN, Height = D.BTN, Callback = function()
		step(-1)
	end })
	Win.mark(minus, "minus", Theme.Sign.Text)
	local plus = SignKit.Plank(strip, { Name = "Plus", Text = "", Width = D.BTN, Height = D.BTN, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Callback = function()
		step(1)
	end })
	Win.mark(plus, "plus", Theme.Sign.Text)
	local trackW = width - 2 * (D.BTN + D.GAP)
	local bw = math.max(10, math.floor((trackW - 9 * D.BLOCK_GAP) / 10))
	local rowW = 10 * bw + 9 * D.BLOCK_GAP
	local blocks = SignKit.BlockRow(strip, {
		Count = 10,
		BlockW = bw,
		BlockH = D.BLOCK_H,
		Gap = D.BLOCK_GAP,
		Position = UDim2.fromOffset(D.BTN + D.GAP + math.floor((trackW - rowW) / 2), math.floor((D.BTN - SignKit.Sizes.Lip - D.BLOCK_H) / 2) + 2),
	})
	for i = 1, 10 do
		local tap = Instance.new("TextButton")
		tap.Name = "Step" .. i
		tap.Text = ""
		tap.AutoButtonColor = false
		tap.BackgroundTransparency = 1
		tap.BorderSizePixel = 0
		tap.Size = UDim2.fromScale(1, 1)
		tap.ZIndex = 3
		tap.Activated:Connect(function()
			H.sound("Click")
			local current = tonumber(ClientSettings.Get(key)) or 0
			ClientSettings.Set(key, (current == i and i == 1) and 0 or i)
		end)
		tap.Parent = blocks:FindFirstChild("Block" .. i)
	end
	local function paint()
		local v = tonumber(ClientSettings.Get(key)) or 0
		value.Text = v == 0 and "OFF" or tostring(v)
		SignKit.FillBlocks(blocks, v)
	end
	paint()
	M.Settings.Rows[key] = paint
	return row
end

-- chips (kit B U5): one of `options` ({ { Text, Value } }) for `key`, as planks side by side; the selected one is gold
-- with its lip (the pitch's .bt.sel: gold is "selected", green stays the one main action), the others stone. A chip is
-- rebuilt when its state changes
function Win.chipRow(parent, key, title, icon, options, order, width)
	local D = K.WIN
	local row = H.frame("Row_" .. key, { Size = UDim2.new(1, 0, 0, D.ROW_H), LayoutOrder = order }, parent)
	Win.rowHead(row, title, icon, false, width)
	local strip = H.frame("Chips", { Position = UDim2.fromOffset(0, D.STRIP_Y), Size = UDim2.new(1, 0, 0, D.BTN) }, row)
	local chips = {}
	local n = #options
	local chipW = math.floor((width - D.GAP * (n - 1)) / n)
	local function paint()
		local v = ClientSettings.Get(key)
		for i, opt in ipairs(options) do
			local selected = v == opt[2]
			local old = chips[i]
			if not old or old:GetAttribute("Selected") ~= selected then
				local chip = SignKit.Plank(strip, {
					Name = "Chip_" .. tostring(opt[1]),
					Text = opt[1],
					Style = selected and "Gold" or "Stone",
					Width = chipW,
					Height = D.BTN,
					TextSize = 22,
					Position = UDim2.fromOffset((i - 1) * (chipW + D.GAP), 0),
					LayoutOrder = i,
					Callback = function()
						H.sound("Click")
						ClientSettings.Set(key, opt[2])
					end,
				})
				chip:SetAttribute("Selected", selected)
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

-- quiet: a rebuild after a screen resize (no click, the window was already open)
function MainMenuController.OpenSettings(quiet)
	local list, width = Win.open("Settings", "SETTINGS", "gear", K.WIN_H, MainMenuController.OpenSettings)
	if not list then
		return
	end
	if quiet ~= true then
		H.sound("Click")
	end
	Win.sliderRow(list, "Music", "Music", "music", 1, width)
	Win.sliderRow(list, "Sfx", "Sound", "speaker", 2, width)
	Win.chipRow(list, "Gfx", "Graphics", "monitor", { { "AUTO", "Auto" }, { "LOW", "Low" }, { "HIGH", "High" } }, 3, width)
	Win.chipRow(list, "Shake", "Camera shake", "shake", { { "ON", true }, { "OFF", false } }, 4, width)
	local desktop = H.isDesktop()
	if desktop then
		-- (bug batch 2 #21: on by default; the key that frees it is in the note below)
		Win.chipRow(list, "MouseLock", "Mouse lock (recommended)", "mouse", { { "ON", true }, { "OFF", false } }, 5, width)
	end
	local note = "Low graphics hides small decorations and glow. Saved to your account."
	if desktop then
		local ml = H.mod("MouseLock")
		local free = (ml and ml.KEY_NAME) and (" (press " .. ml.KEY_NAME .. " to free it)") or ""
		note = "Mouse lock: the mouse turns the camera" .. free .. ". Low graphics hides small decorations and glow. Saved to your account."
	end
	local label = Theme.Label(note, "Label", { Size = 18, Color = Theme.Sign.TextMuted })
	label.Name = "Note"
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 24)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.LayoutOrder = 6
	label.Parent = list
end

-- an update's version head (kit B U5): a navy plank (the pitch's sign: a gold-lip edge, a darker navy lip) with
-- "vN · Title" in FredokaOne gold, stepped down until it fits, then truncated
function Win.versionHead(parent, name, text, order, width, newest)
	local Z, Sign = SignKit.Sizes, Theme.Sign
	local h = newest and 50 or 44
	local head = H.frame(name, { Size = UDim2.new(1, 0, 0, h), LayoutOrder = order }, parent)
	local block = H.frame("Block", { BackgroundTransparency = 0, BackgroundColor3 = Sign.GoldLip, Size = UDim2.fromScale(1, 1) }, head)
	H.frame("Lip", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Sign.NavyLip,
		Position = UDim2.fromOffset(Z.Edge, Z.Edge),
		Size = UDim2.new(1, -2 * Z.Edge, 1, -2 * Z.Edge),
	}, block)
	local face = H.frame("Face", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Sign.Navy,
		Position = UDim2.fromOffset(Z.Edge, Z.Edge),
		Size = UDim2.new(1, -2 * Z.Edge, 1, -(2 * Z.Edge + 6)),
		ZIndex = 2,
	}, block)
	local size = newest and 24 or 21
	local room = width - 2 * Z.Edge - 24
	while size > 16 do
		local ok, m = pcall(Theme.Measure, text, "Heading", size)
		if not ok or not m or m.X <= room then
			break
		end
		size = size - 1
	end
	local label = Theme.Label(text, "Heading", { Size = size, Color = Sign.Gold })
	label.Name = "Label"
	label.Position = UDim2.fromOffset(12, 0)
	label.Size = UDim2.new(1, -24, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 3
	label.Parent = face
	return head
end

-- an update's line (kit B U5): a 6 px square bullet, then the text in Nunito brown on the stone, as tall as it wraps
function Win.noteLine(parent, name, text, order)
	local D, ink = K.WIN, Theme.TextOn("Stone")
	local line = H.frame(name, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order }, parent)
	H.frame("Bullet", {
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Sign.Wood,
		Position = UDim2.fromOffset(4, 9),
		Size = UDim2.fromOffset(D.BULLET, D.BULLET),
	}, line)
	local label = Theme.Label(tostring(text), "Body", { Size = 19, Color = ink })
	label.Name = "Text"
	label.Position = UDim2.fromOffset(4 + D.BULLET + 10, 0)
	label.Size = UDim2.new(1, -(4 + D.BULLET + 10), 0, 24)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = line
	return line
end

-- quiet: a rebuild after a screen resize (no click, the window was already open)
function MainMenuController.OpenUpdates(quiet)
	local list, width = Win.open("Updates", "WHAT'S NEW", "scroll", K.WIN_H, MainMenuController.OpenUpdates)
	if not list then
		return
	end
	if quiet ~= true then
		H.sound("Click")
	end
	local notes = H.notes()
	local order = 0
	for _, note in ipairs(notes and notes.Notes or {}) do
		order = order + 1
		Win.versionHead(list, "Head" .. order, "v" .. tostring(note.Version) .. " \194\183 " .. tostring(note.Title or ""), order * 100, width, order == 1)
		for i, line in ipairs(note.Lines or {}) do
			Win.noteLine(list, "Line" .. order .. "_" .. i, line, order * 100 + i)
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

-- the roof: SignKit's gable (two tilted slopes whose lower parts hide behind the header, a darker fascia board, a round
-- vent) in this window's approved colours; one fixed-size piece centred on the header, whatever the window's width
function Credits.roof(parent)
	local C, S = K.CR, K.SIGN
	return SignKit.Roof(parent, {
		Shape = "Gable", -- the owner's approved look (not the kit's flat awning; morning item M5)
		Width = C.ROOF_W,
		Height = C.ROOF_H,
		Slope = C.SLOPE_T,
		Fascia = C.FASCIA_H,
		Color = S.Roof,
		Shade = S.RoofShade,
		Vent = S.Cream,
		VentEdge = S.WoodDark,
		ZIndex = 2,
	})
end

-- the header: SignKit's header (dark wood rim, navy plate) with CREDITS in white over its drop line, and the drawn red X
function Credits.head(parent, L)
	local C, S = K.CR, K.SIGN
	local closeSize = L.Small and 38 or 44
	local head, plate = SignKit.Header(parent, {
		Title = C.TITLE,
		TitleRole = "Sign",
		TitleSize = L.Small and 28 or Theme.Sizes.Sign,
		TitleColor = K.WHITE,
		Drop = S.Drop,
		TitleX = 18,
		Reserve = closeSize + 20,
		Y = L.HeadY,
		Height = L.HeadH,
		Rim = C.RIM,
		RimColor = S.WoodDark,
		Color = S.Navy,
		ZIndex = 3,
	})
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
	-- the gold ring is its own round disc behind the emblem: a UIStroke on the ImageLabel drew as a square in Studio
	-- (2026-11-13), and a circle needs no tilt
	local ring = H.frame("StickerRing", {
		BackgroundTransparency = 0,
		BackgroundColor3 = S.Ring,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(L.StickerX, L.StickerY),
		Size = UDim2.fromOffset(L.S + 2 * L.Ring, L.S + 2 * L.Ring),
		ZIndex = 4,
	}, body)
	H.corner(ring)
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
	local wood = SignKit.Frame(sign, { Y = L.WoodY, Height = L.WoodH, Color = S.Wood, ZIndex = 3 })
	-- the cream body has no stone lip (the approved look); its inner line instead
	local body = SignKit.Body(wood, {
		Inset = C.WOOD,
		Color = S.Cream,
		Lip = 0,
		Line = { Inset = C.LINE, Thickness = C.LINE_T, Color = S.CreamLine },
	})
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
	local ok = H.safe("build", Menu.build, true)
	if not ok and M.Menu then
		M.Menu:Destroy()
		M.Menu = nil
	end
	Orbit.start()
	Menu.bindKeys(true)
	Menu.watch(true) -- (sign build) laid out again when the screen changes size
end

function MainMenuController.Play()
	if not M.Open or M.Playing then
		return false
	end
	if Loading.busy() then
		return false -- the loading screen is still up (SKIP takes it away)
	end
	M.Playing = true
	Menu.watch(false)
	H.sound("Confirm")
	Win.close()
	Menu.bindKeys(false)
	-- (kit B U4) the board goes up and the camera flies to the spawn view straight away (the release below waits as before)
	H.safe("leave", Menu.leave)
	H.safe("orbit", Orbit.halt)
	H.safe("fly", Orbit.fly)
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
		-- (sign build, U4 minor) the release waits for the camera move to land (the HUD came back mid-flight before); a
		-- tween's Completed fires on landing and on a cancel alike
		local fly = M.Orbit.Fly
		if fly and fly.PlaybackState == Enum.PlaybackState.Playing then
			fly.Completed:Wait()
		end
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
	if key == "Shake" and M.Open and not M.Playing then
		H.safe("sway", Menu.sway, M.Ui) -- (sign build) Camera shake OFF stops the title board's sway, ON brings it back
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
