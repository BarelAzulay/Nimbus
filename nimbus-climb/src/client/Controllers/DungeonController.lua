-- DungeonController (client, Phase 5, dungeonclient W4): the Dungeon window, the run card, the loot / chest toasts, the
-- End card and the dungeon mood (ARCHITECTURE_V3.md "Phase 5 build contract" 5.3, 5.6, 5.7, 6.4, 6.6).
--
--   DungeonController.Init()
--   DungeonController.Open(floor|nil, portal|nil) -> bool   the Dungeon side panel (Portal_Dungeon's DungeonPrompt is
--                                             handed over by ArenaController; OpenPanel("Dungeon", { Floor }) from the
--                                             server: the tutorial / the prompt). Refused (false) inside a run / a match.
--   DungeonController.Close()
--   DungeonController.IsOpen() -> bool
--   DungeonController.Request(action, a, b) -> bool   DungeonRequest(action, a, b), spaced per action (K.FIRE_GAP);
--                                             the server validates everything (DungeonService ladder + cooldowns)
--   DungeonController.GetState() -> { Window, Floor, Lobby, Run, End, Loot, Totals, Ready, Lit, CardMode, Countdown, Fade,
--                                     Door, Enter, Walk, Shoulder }
--   DungeonController.Opened / Closed (Util.Signal)
--
-- What the player sees
--   * The Dungeon window (a NeonKit side panel, 640 x 860 design px, Purple; docked right on landscape screens, a
--     bottom sheet on portrait phones; never dims the screen): the record ("Best: floor 5 - 7 clears - 12 runs") and
--     the team power; the 12 floors (element orb, name, "Cleared" / "Recommended power 512" / "Clear floor 6 first";
--     the next floor to beat marked NEXT); then the party box: SOLO / PARTY + the open parties ("Ava's party - Floor 3
--     - 2/4 - JOIN", "in room 2 - JOIN"), or the own party (members with READY ticks, team power, the leader's crown
--     and KICK (x), READY / START / LEAVE, the countdown "Dungeon in 5..." / "Starting in 30 - press READY").
--     READY flips at once (optimistic) and the next Lobby payload says what the server decided.
--   * The run card (ScreenGui NimbusDungeonRun): on desktops a side card at the right edge between the enemy list and
--     the battle buttons ("Floor 3 - Frozen Crypt", "Room 2 / 4" pips with the boss room crowned, "Wave 1 / 3",
--     the status: "Walk into the room", "Go to the door and press E" / "Waiting for 1 more (Ava)" (dungeon-fixes
--     decision 2: no room changes by timer; the door's EnterPrompt E goes through ProximityPromptService on the
--     server, this controller sends nothing for it), "Pick ONE chest!" (bug batch 2 #14: no CHEST button; each
--     member walks to ONE chest of the alcove and presses its E prompt, the server rolls that chest's own drop; once
--     I picked or Run.ChestOwed does not list me, the pocket's other ChestPrompts are switched off locally),
--     member chips with Downed / Left, the loot so far, LEAVE (two presses -> DungeonRequest("Quit"))); on phones a one-line
--     chip in Roblox's top band. The party countdown uses the same card while the window is closed. Loot and chest
--     toasts flash inside it ("Room 2 cleared! +$340 +24 tokens +70 XP"). The End card (totals, first clear, unlock,
--     new best) sits at the right (desktop / landscape) or under the top bar (portrait), never in the centre.
--   * Lighting: LightingStack.Push("Dungeon", preset, 1) when a run starts (darker ambient, ColorCorrection Brightness
--     -0.12 / Contrast 0.1 / a warm grey tint, Atmosphere density +0.15); Pop("Dungeon", 1) on End or when the player
--     is no longer in the pocket (InBattle released). The music follows the same switch: SoundFx.SetLayer("Dungeon",
--     true / false) (the Dungeon track while the run lasts; BattleController's Battle layer wins in the boss room).
--   * Sounds: SoundFx "Reward" when the chest pays out (DungeonState "Chest") and when a room's loot comes in (not
--     the third-of-the-XP consolation of a lost run).
--   * Camera (wave 6): while a run lasts, R.camClamp (RenderStep NimbusDungeonCamBox at Camera + 1) keeps the camera
--     inside the pieces' camera boxes (DungeonBuilder's CamMin / CamMax): the boom from the Focus is cut on its own ray
--     where it leaves the box the Focus is in (CAM_MARGIN 0.6 inside; through a doorway it carries on in the next box,
--     at most 2 hops), so no zoom or turn shows the outside of a room, over a ceiling or across the chasm. First person
--     (a boom < 1 stud), a Scriptable camera (the walk-in, the entrance) and a Focus in no box are left alone.
--   * Camera (bug batch 2, #19): MovementController.SetZoomMax(K.ZOOM_RUN 14) with the first Run payload, so the camera
--     stays inside the 16-stud rooms; SetZoomMax(nil) (the normal 40) on End, when the run vanished without an End
--     (R.check) and, as a safety net, on any light-loop tick that finds the zoom capped with no run (every exit path).
--   * Doors: the room models' DoorOpen / EntranceOpen attributes play a local slide (copies of the bars sink into the
--     floor) in the player's own pocket.
--   * The room change fade (DungeonState "Fade" { Out, Hold, In }): ONE black full-screen Frame in its own ScreenGui
--     NimbusDungeonFade (IgnoreGuiInset, DisplayOrder K.FADE_ORDER 25: above the HUD 10, the battle HUD / run card 12
--     and the windows 20-23, below Notify 30); tweens to black over Out, holds (until the next room's Run payload,
--     at least Hold), back over In; never stuck: a FADE_SAFETY 6 s clear, End and leaving the run clear it at once.
--     (wave 6: the black waits up to FADE_SAFETY for the room: the server's payload can queue behind a big
--     replication; the old 3 s clear dropped the walk-in when it came late.)
--   * Wave 5 (bugs #15 / #26):
--     - The entrance (DungeonState "Enter" { Cover, Reveal, Element }, before the server teleports the party into the
--       hall after Cover): the camera rushes into the Dungeon gate's vortex (0.5 s, FOV 70 -> 55, the gate flares,
--       Whoosh), the screen fills with voxel blocks in the floor's element colour from the centre out (ScreenGui
--       NimbusDungeonEnter, DisplayOrder K.ENTER_ORDER 26; 16 x 9 / 9 x 16 portrait / 8 x 5 on Low graphics), they
--       hold until the run's first Run payload, then hop and fall away (Reveal). Any key / click / tap skips (the
--       cover snaps full, the reveal ends at once); ENTER_SAFETY 3 s, End and the run's InBattle release clear it.
--     - The room walk-in: when the next room's Run payload (Corridor / Threshold) arrives under the fade, the camera is
--       placed inside the room looking back through the doorway (Scriptable, FOV 60), the controls are off and, as the
--       fade lifts, the character walks itself (Humanoid:MoveTo, 6 studs/s) past the Threshold while the camera dollies
--       back, swings a little and opens to FOV 70; the first member across starts the fight on the server; then the
--       camera blends back (0.35 s) to where it was at the door and the controls return. Any key / click / tap skips
--       (the character is set at the Threshold). Never stuck: WALK_SAFETY 3 s, End, the InBattle release, the
--       character removed. Outside a fade (a late join, a rejoin) there is no walk-in.
--     - The dungeon camera: Humanoid.CameraOffset = DUNGEON_SHOULDER (a little over the right shoulder) for the run,
--       zero again on End / leaving the run. The Camera shake setting OFF turns off ONLY the hit shakes (player ruling
--       2026-10-28): the entrance rush, the walk-in shot and the FOV punch on big attacks play regardless (all short and
--       skippable). The rush is skipped when the camera is > ENTER_RUSH_MAX from the gate (no flight across the plaza).
--       MovementController.SetFovOverride / SetCinematic do the FOV and the walk speed (the one place that writes them
--       every frame).
-- Remotes: DungeonState (in), OpenPanel (in), DungeonRequest (out). One side panel at a time: opening it closes the
-- menu windows, the Pet Index, the Fusion / Care windows and the Arena windows; theirs close this one. Esc / gamepad
-- B / the red X / walking 40 studs away from the gate close it. Text is designed at 1080p (>= 18 design px).
-- Plain Lua 5.1-compatible syntax only. All fonts come from Theme roles; no asset ids.

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

local Client = script.Parent.Parent
local UI = Client:WaitForChild("UI")
local CloudUI = require(UI:WaitForChild("CloudUI"))
local NeonKit = require(UI:WaitForChild("NeonKit"))
local State = require(Client:WaitForChild("State"))

local DungeonController = {}
DungeonController.Opened = Util.Signal()
DungeonController.Closed = Util.Signal()

----------------------------------------------------------------------
-- Tunables (design px of a 1080p screen unless noted)
----------------------------------------------------------------------
local K = {
	DISPLAY_ORDER = 23, -- the windows' layer (like the Arena windows)
	RUN_ORDER = 12, -- the run card: above the HUD (10) and the hotbar (11), below the windows
	PREF_W = 640,
	PREF_H = 860,
	SHORT = 560, -- a docked window lower than this uses the compact rows (landscape phones)
	FIRE_GAP = 0.3, -- seconds between two sends of the same request
	WALK_AWAY = 40, -- studs from the gate that close a window opened there
	FLOORS = 12,
	ROW_H = 66,
	ROW_H_SHORT = 52,
	MEMBER_H = 46,
	MEMBER_H_SHORT = 40,
	CARD_W = 330, -- the desktop run card
	CHIP_H = 50, -- the phone chip (design px; scale 0.8)
	END_W = 400,
	LEAVE_CONFIRM = 3, -- seconds the first LEAVE press stays armed
	TOAST_SECONDS = 4,
	END_SECONDS = 14, -- the End card hides by itself after this
	TREASURE = 45,
	FADE_ORDER = 25, -- the room change fade: above the HUD (10), the run card (12) and the windows (20-23), below Notify (30)
	FADE_SAFETY = 6, -- a fade never stays on longer than this (seconds; wave 6: 3 -> 6, it waits for a late room payload)
	FADE_MAX_STEP = 2, -- Out / Hold / In are clamped to 0..this
	TICK = 0.25, -- the light loop
	BACK_ACTION = "NimbusDungeonBack",
	LIGHT_ID = "Dungeon",
	LIGHT_SECONDS = 1,
	MOOD_RETRY = 1, -- bug #5 review: re-read the tier mood every 1 s ...
	MOOD_TRIES = 10, -- ... up to 10 s while the run is lit (streaming / a slow join)
	ZOOM_RUN = 14, -- bug batch 2 (#19): the camera zoom cap inside a run (rooms are 16 studs high)
	ZOOM_NUDGE = 10, -- wave 5 (#15): a run starts zoomed in to 10 (the shoulder camera), the player may zoom out to the cap
	-- wave 5 (bug #26): the room walk-in (seconds, studs, degrees)
	WALK_SECONDS = 1.3, -- the scripted walk's camera clock (7.5 studs at WALK_SPEED)
	WALK_SPEED = 6, -- studs/s, a deliberate "entering" pace
	WALK_BLEND = 0.35, -- the scripted -> normal camera blend
	WALK_SKIP_BLEND = 0.25,
	WALK_FIGHT_GRACE = 0.4, -- the fight started (someone crossed): the walk-in hands back control within this
	WALK_CAM = { Ahead = 9, Pull = 3, Up = 3.5, Settle = 0.8, Swing = 2.5, Fov0 = 60, Fov1 = 70 },
	WALK_SAFETY = 3, -- the camera is never left Scriptable longer than this
	WALK_REISSUE = 0.5, -- Humanoid:MoveTo again this often (a fresh Humanoid needs it)
	WALK_LANE = 4.8, -- studs: everybody keeps their lane across the doorway
	WALK_IN = 1.5, -- studs past the Threshold's centre (inside its box)
	WALK_REACH = 1.2, -- this close to the end point = arrived
	WALK_BIND = "NimbusDungeonWalk",
	CAM_BIND = "NimbusDungeonCamBox", -- wave 6: the camera box clamp (RenderPriority.Camera + 1, while a run lasts)
	CAM_MARGIN = 0.6, -- the camera stays this far inside a piece's box
	WALK_ACTION = "NimbusDungeonWalkSink",
	-- wave 5 (bug #15): the voxel-shatter entrance
	ENTER_ORDER = 26, -- above the fade (25) and every window, below Notify (30)
	ENTER_GRID = { Desktop = { 16, 9 }, Portrait = { 9, 16 }, Low = { 8, 5 }, LowPortrait = { 5, 8 } },
	ENTER_RUSH = 0.5, -- the camera rush into the gate
	ENTER_RUSH_FOV = 55,
	ENTER_RUSH_MAX = 60, -- studs: a camera further than this from the gate gets no rush (the blocks still cover)
	ENTER_LEAD = 0.10, -- the first blocks pop this long after the rush began
	ENTER_MARGIN = 0.15, -- every block is full this long before Cover (the hall teleport can never show at the edges)
	ENTER_POP = 0.12, -- one block's pop-in (Back Out)
	ENTER_HOP = 0.12, -- the reveal: a block's hop ...
	ENTER_FALL = 0.5, -- ... and its fall
	ENTER_JITTER = 0.08,
	ENTER_SAFETY = 3, -- the blocks never stay longer than this without the run's Run payload
	ENTER_BIND = "NimbusDungeonEnter",
	DUNGEON_SHOULDER = Vector3.new(1.4, 0.35, 0), -- Humanoid.CameraOffset inside a run (bug #15 "3D" camera)
}

local Colors = Theme.Colors
local NEON = Theme.Neon or {}
local WHITE = Colors.White
local INK = Colors.PanelInk or Color3.fromRGB(8, 10, 28)
local C = {
	Accent = Theme.NeonColor and Theme.NeonColor("Dungeon") or Color3.fromRGB(176, 104, 255),
	Gold = NEON.Gold or Color3.fromRGB(255, 196, 64),
	Green = NEON.Green or Color3.fromRGB(72, 224, 120),
	Red = NEON.Red or Color3.fromRGB(255, 76, 100),
	Blue = NEON.Blue or Color3.fromRGB(64, 170, 255),
	Grey = NEON.Grey or Color3.fromRGB(150, 166, 204),
	Muted = Color3.fromRGB(176, 184, 214),
	Row = Color3.fromRGB(30, 36, 78),
	RowDark = Color3.fromRGB(18, 22, 52),
	Locked = Color3.fromRGB(110, 116, 150),
	Power = Color3.fromRGB(255, 214, 110),
	Cash = Color3.fromRGB(120, 230, 140),
	Token = Colors.Token or Color3.fromRGB(255, 210, 90),
	Gem = Colors.Gem or Color3.fromRGB(84, 196, 246),
}

-- glyphs as UTF-8 escapes (the source stays ASCII)
local G = {
	Swords = "\226\154\148",
	Crown = "\240\159\145\145",
	Check = "\226\156\147",
	Lock = "\240\159\148\146",
	Cloud = "\226\152\129",
	Gem = (Theme.Currency and Theme.Currency.Gems and Theme.Currency.Gems.Glyph) or "\226\151\134",
	Skull = "\240\159\146\128",
	Dot = "\194\183",
	Cross = "\226\156\149",
	Chest = "\240\159\142\129",
	Star = "\226\152\133",
	Pip = "\226\151\143",
	PipOff = "\226\151\139",
	Torch = "\240\159\148\165",
	Hourglass = "\226\143\179",
}

-- the dungeon mood (contract 5.6): absolute values for the ambient / colour correction, the haze relative to the base
local PRESET = {
	Lighting = { Ambient = Color3.fromRGB(70, 62, 86), OutdoorAmbient = Color3.fromRGB(86, 78, 104) },
	ColorCorrection = { Brightness = -0.12, Contrast = 0.1, TintColor = Color3.fromRGB(236, 226, 212) },
	AtmosphereAdd = 0.15,
}

----------------------------------------------------------------------
-- Module state
----------------------------------------------------------------------
local LocalPlayer = nil
local initialized = false
local U = {} -- gui references
local S = {
	Open = false,
	Token = 0,
	Floor = nil, -- the selected floor in the window
	Lobby = nil, -- last DungeonState "Lobby"
	LobbyAt = 0,
	Run = nil, -- last "Run" (nil outside a run)
	RunAt = 0,
	PhaseAt = 0, -- os.clock() when the run's State / Phase last changed
	PhaseKey = nil,
	End = nil, -- last "End" (the End card)
	EndAt = 0,
	Loot = nil, -- last "Loot"
	Totals = { Cash = 0, Tokens = 0, Xp = 0, Gems = 0 },
	Toast = nil, -- { Text, Color, Until }
	ReadyWant = nil, -- optimistic READY until the next Lobby payload
	Lit = false,
	LeaveArmed = 0,
	LastFire = {},
	BackBound = false,
	AtPortal = nil,
	Hint = nil, -- { Text, Until } the window footer
	Built = false,
	Short = false,
	CardMode = nil, -- "Card" | "Chip" | nil
	Warned = {},
	Doors = {}, -- connections watching the pocket's doors
	Pocket = nil,
	Zoomed = false, -- the camera zoom is capped at K.ZOOM_RUN (a run)
	Walk = nil, -- wave 5: the room walk-in (R.walkPrepare)
	WalkSkip = nil, -- wave 6: why the last room payload played no walk-in (GetState().WalkSkip, the run gui's attribute)
	CamBoxes = nil, -- wave 6: the pocket's piece camera boxes (R.camBoxes), nil = rebuild
	CamBound = false, -- wave 6: NimbusDungeonCamBox is bound
	Enter = nil, -- wave 5: the voxel-shatter entrance (R.enter)
	Gate = nil, -- the Dungeon gate model (GateId "Dungeon"), cached
	ShoulderHum = nil, -- the Humanoid whose CameraOffset is the dungeon shoulder
}

local H = {} -- helpers
local W = {} -- the window
local R = {} -- the run card / End card / lighting / doors

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
function H.warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[DungeonController] " .. key .. ": " .. tostring(err))
	end
end

function H.safe(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		H.warnOnce(key, err)
	end
	return ok
end

function H.optionalShared(name)
	local module = Shared:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

function H.catalog()
	if H.BC == nil then
		H.BC = H.optionalShared("BattleCatalog") or false
	end
	return H.BC or nil
end

function H.controller(name)
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
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
	return Util.Create("UIStroke", {
		Color = color or INK,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function H.list(parent, direction, gap, hAlign, vAlign)
	return Util.Create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		Parent = parent,
	})
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

function H.clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

function H.commas(n)
	return Util.Commas(math.floor((tonumber(n) or 0) + 0.5))
end

function H.clock(seconds)
	local s = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

function H.tween(inst, seconds, goal, style, direction)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

function H.attr(name)
	return LocalPlayer and LocalPlayer:GetAttribute(name) or nil
end

function H.inMatch()
	return H.attr(Config.Attr.InMatch) == true
end

-- the dungeon run id while the player is in a run (InBattle = "D12"), else nil
function H.runAttr()
	local v = H.attr((Config.Attr and Config.Attr.InBattle) or "InBattle")
	if type(v) == "string" and v:sub(1, 1) == "D" then
		return v
	end
	return nil
end

function H.viewport()
	local camera = Workspace.CurrentCamera
	local vp = camera and camera.ViewportSize
	if not vp or vp.X < 2 or vp.Y < 2 then
		return Vector2.new(1920, 1080)
	end
	return vp
end

function H.isPhone()
	local vp = H.viewport()
	return math.min(vp.X, vp.Y) < 500
end

function H.rootPosition()
	local character = LocalPlayer and LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
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

-- floor data from the catalog: { Name, Element, Floor } (a plain fallback when the catalog is missing)
function H.floorInfo(f)
	local BC = H.catalog()
	local list = BC and BC.DungeonFloors
	local info = type(list) == "table" and list[f] or nil
	if type(info) == "table" then
		return info
	end
	return { Name = "Floor " .. tostring(f), Element = nil, Floor = f }
end

function H.floorCount()
	local BC = H.catalog()
	local D = BC and BC.Dungeon
	return math.max(1, math.floor(tonumber(D and D.Floors) or K.FLOORS))
end

function H.elementColor(element)
	local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[element]
	return info and info.Color or C.Accent
end

function H.recommended(f)
	local BC = H.catalog()
	if BC and type(BC.DungeonPower) == "function" then
		local ok, p = pcall(BC.DungeonPower, f, 1)
		if ok and tonumber(p) then
			return math.max(1, math.ceil(tonumber(p) - 1e-9))
		end
	end
	return nil
end

function H.dungeonNumber(field, default)
	local BC = H.catalog()
	local D = BC and BC.Dungeon
	return tonumber(D and D[field]) or default
end

-- the saved record: the Lobby payload's Record (fresh from the server) or State.Dungeon()
function H.record()
	local rec = S.Lobby and type(S.Lobby.Record) == "table" and S.Lobby.Record or nil
	local out = { Best = 0, Cleared = {}, Runs = 0, Clears = 0 }
	if not rec and type(State.Dungeon) == "function" then
		local ok, d = pcall(State.Dungeon)
		rec = ok and type(d) == "table" and d or nil
	end
	if rec then
		out.Best = math.floor(tonumber(rec.Best) or 0)
		out.Runs = math.floor(tonumber(rec.Runs) or 0)
		out.Clears = math.floor(tonumber(rec.Clears) or 0)
		if type(rec.Cleared) == "table" then
			for i = 1, K.FLOORS do
				if rec.Cleared[i] == true then
					out.Cleared[i] = true
				end
			end
		end
	end
	return out
end

-- floor f is open for the player as a leader: Best >= f - 1 (members are carried; the server decides)
function H.unlocked(f, rec)
	rec = rec or H.record()
	return f <= 1 or rec.Best >= f - 1 or rec.Cleared[f - 1] == true
end

function H.nextFloor(rec)
	rec = rec or H.record()
	return math.min(H.floorCount(), math.max(1, rec.Best + 1))
end

----------------------------------------------------------------------
-- The player's team power (team -> equipped -> best owned; training skipped), like the server's TeamSpec
----------------------------------------------------------------------
function H.entryOf(key)
	local def = nil
	if type(State.DefOf) == "function" then
		local ok, result = pcall(State.DefOf, key)
		def = ok and type(result) == "table" and result or nil
	end
	if not def then
		return nil
	end
	local level = 1
	if type(State.PetLevel) == "function" then
		local ok, lv = pcall(State.PetLevel, key)
		level = ok and tonumber(lv) or 1
	end
	local g = {}
	if type(State.PetGrowth) == "function" then
		local ok, result = pcall(State.PetGrowth, key)
		g = ok and type(result) == "table" and result or {}
	end
	return { Def = def, Level = level, Key = key, Evo = tonumber(g.Evo) or 0,
		Train = { Speed = g.Speed or 0, Physique = g.Physique or 0, Ability = g.Ability or 0, Defense = g.Defense or 0 } }
end

function H.collect(keys)
	local out = {}
	for _, key in ipairs(type(keys) == "table" and keys or {}) do
		local busy = false
		if type(State.IsTraining) == "function" then
			local ok, b = pcall(State.IsTraining, key)
			busy = ok and b == true
		end
		if type(key) == "string" and not busy then
			local e = H.entryOf(key)
			if e then
				out[#out + 1] = e
			end
		end
	end
	return out
end

function H.teamPower()
	local now = os.clock()
	if H.PowerAt and now - H.PowerAt < 1 and H.PowerSnap == State.Get() then
		return H.Power
	end
	H.PowerAt, H.PowerSnap = now, State.Get()
	H.Power = H.teamPowerNow()
	return H.Power
end

function H.teamPowerNow()
	local BC = H.catalog()
	if not BC or type(BC.TeamPower) ~= "function" then
		return 0
	end
	local list = {}
	if type(State.Teams) == "function" then
		local ok, t = pcall(State.Teams)
		if ok and type(t) == "table" and type(t.Presets) == "table" then
			list = H.collect(t.Presets[t.Active or 1])
		end
	end
	if #list == 0 and type(State.EquippedList) == "function" then
		local ok, eq = pcall(State.EquippedList)
		list = H.collect(ok and eq or nil)
	end
	if #list == 0 and type(State.Keys) == "function" then
		local ok, keys = pcall(State.Keys)
		list = H.collect(ok and keys or nil)
		if type(BC.UnitPower) == "function" then
			for _, e in ipairs(list) do
				local okP, p = pcall(BC.UnitPower, e)
				e.P = okP and tonumber(p) or 0
			end
			table.sort(list, function(a, b)
				if a.P ~= b.P then
					return a.P > b.P
				end
				return tostring(a.Key) < tostring(b.Key)
			end)
		end
		while #list > 3 do
			table.remove(list)
		end
	end
	local ok, p = pcall(BC.TeamPower, list)
	return ok and math.floor((tonumber(p) or 0) + 0.5) or 0
end

----------------------------------------------------------------------
-- Requests (DungeonRequest; spaced here, validated on the server)
----------------------------------------------------------------------
function H.request(action, a, b)
	local now = os.clock()
	local key = tostring(action) .. "|" .. tostring(a)
	if S.LastFire[key] and now - S.LastFire[key] < K.FIRE_GAP then
		return false
	end
	if not H.remote then
		local ok, remote = pcall(Remotes.Get, "DungeonRequest")
		H.remote = ok and remote or nil
	end
	if not H.remote then
		return false
	end
	S.LastFire[key] = now
	local ok, err = pcall(function()
		H.remote:FireServer(action, a, b)
	end)
	if not ok then
		H.warnOnce("DungeonRequest " .. tostring(action), err)
	end
	return ok
end

function H.hint(text, seconds)
	S.Hint = { Text = tostring(text), Until = os.clock() + (seconds or 4) }
	if S.Open then
		H.safe("footer", W.footer)
	end
end

function H.avoidRight(x)
	local hb = H.controller("HotbarController")
	if hb and type(hb.SetAvoidRight) == "function" then
		pcall(hb.SetAvoidRight, x)
	end
end

----------------------------------------------------------------------
-- The window (CloudUI.Panel on NeonKit.Dock)
----------------------------------------------------------------------
function W.build()
	if S.Built then
		return true
	end
	S.Built = true
	local holder = H.frame(U.Gui, "Window_Dungeon", { Size = UDim2.fromOffset(K.PREF_W, K.PREF_H), Visible = false, ZIndex = 3 })
	U.Holder = holder
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = holder })
	U.Dock = NeonKit.Dock(holder, U.Fit, K.PREF_W, K.PREF_H)
	local panel = CloudUI.Panel({
		Name = "DungeonPanel",
		Title = "The Dungeon",
		Closable = true,
		Category = "Dungeon",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		OnClose = function()
			DungeonController.Close()
		end,
		Parent = holder,
	})
	U.Panel = panel
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = panel.Root })
	local content = panel.Content
	-- the record line
	U.Top = H.frame(content, "Top", { Size = UDim2.new(1, 0, 0, 30) })
	U.Record = H.text(U.Top, "Record", "", "Heading", 19, WHITE, { Size = UDim2.new(1, -150, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	U.Power = H.text(U.Top, "Power", "", "Heading", 19, C.Power, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 150, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	-- the floor list
	U.Floors = Instance.new("ScrollingFrame")
	U.Floors.Name = "Floors"
	U.Floors.BackgroundTransparency = 0.25
	U.Floors.BackgroundColor3 = C.RowDark
	U.Floors.BorderSizePixel = 0
	U.Floors.ScrollBarThickness = 8
	U.Floors.ScrollBarImageColor3 = C.Accent
	U.Floors.ScrollingDirection = Enum.ScrollingDirection.Y
	U.Floors.AutomaticCanvasSize = Enum.AutomaticSize.Y
	U.Floors.CanvasSize = UDim2.new(0, 0, 0, 0)
	U.Floors.Position = UDim2.fromOffset(0, 36)
	U.Floors.Parent = content
	H.corner(U.Floors, 12)
	H.pad(U.Floors, 8, 8, 14, 8)
	H.list(U.Floors, Enum.FillDirection.Vertical, 6)
	U.FloorRows = {}
	for f = 1, H.floorCount() do
		U.FloorRows[f] = W.floorRow(f)
	end
	-- the party box
	U.Party = Instance.new("ScrollingFrame")
	U.Party.Name = "Party"
	U.Party.BackgroundTransparency = 0.2
	U.Party.BackgroundColor3 = C.RowDark
	U.Party.BorderSizePixel = 0
	U.Party.ScrollBarThickness = 6
	U.Party.ScrollBarImageColor3 = C.Accent
	U.Party.ScrollingDirection = Enum.ScrollingDirection.Y
	U.Party.AutomaticCanvasSize = Enum.AutomaticSize.Y
	U.Party.CanvasSize = UDim2.new(0, 0, 0, 0)
	U.Party.Parent = content
	H.corner(U.Party, 12)
	H.pad(U.Party, 10, 8, 10, 8)
	H.list(U.Party, Enum.FillDirection.Vertical, 6)
	-- the footer hint
	U.Footer = H.text(content, "Footer", "", "Body", 18, C.Muted, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return true
end

-- one floor row (a TextButton: tap to select it)
function W.floorRow(f)
	local info = H.floorInfo(f)
	local color = H.elementColor(info.Element)
	local row = Instance.new("TextButton")
	row.Name = "Floor" .. f
	row.AutoButtonColor = false
	row.Text = ""
	row.BorderSizePixel = 0
	row.BackgroundColor3 = C.Row
	row.Size = UDim2.new(1, 0, 0, K.ROW_H)
	row.LayoutOrder = f
	row.Parent = U.Floors
	H.corner(row, 10)
	local rim = H.stroke(row, Theme.Darken(color, 0.35), 2, 0.2)
	local stripe = H.frame(row, "Stripe", { BackgroundTransparency = 0, BackgroundColor3 = color, Size = UDim2.new(0, 6, 1, -12), Position = UDim2.fromOffset(4, 6) })
	H.corner(stripe, 3)
	local orbHolder = H.frame(row, "OrbHolder", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 48, 1, 0) })
	local orb = NeonKit.Orb(orbHolder, color, 44)
	local num = H.text(orb, "Num", tostring(f), "Title", 22, WHITE, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	local name = H.text(row, "FloorName", info.Name, "Heading", 21, WHITE, {
		Position = UDim2.fromOffset(70, 6),
		Size = UDim2.new(1, -190, 0, 28),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local sub = H.text(row, "Status", "", "Body", 18, C.Muted, {
		Position = UDim2.fromOffset(70, 34),
		Size = UDim2.new(1, -190, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local chip = H.frame(row, "Chip", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(106, 34),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.RowDark,
	})
	H.corner(chip, 17)
	local chipRim = H.stroke(chip, color, 2, 0)
	local chipText = H.text(chip, "Text", "", "Button", 18, WHITE, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	row.Activated:Connect(function()
		H.safe("pick floor", W.pick, f)
	end)
	return { Root = row, Rim = rim, Orb = orb, Num = num, Name = name, Sub = sub, Chip = chip, ChipRim = chipRim, ChipText = chipText, Color = color }
end

-- a tap on floor f: select it (the leader of a party also moves the party's floor)
function W.pick(f)
	local rec = H.record()
	local mine = S.Lobby and S.Lobby.Mine or nil
	if mine and LocalPlayer and mine.Leader ~= LocalPlayer.UserId then
		H.hint("The party leader picks the floor")
		return
	end
	if not H.unlocked(f, rec) then
		H.hint("Clear floor " .. (f - 1) .. " first")
		return
	end
	S.Floor = f
	if mine then
		H.request("SetFloor", f)
	end
	W.refresh()
end

function W.selected()
	local mine = S.Lobby and S.Lobby.Mine or nil
	if mine and tonumber(mine.Floor) then
		return math.floor(mine.Floor)
	end
	local rec = H.record()
	local f = S.Floor or H.nextFloor(rec)
	if not H.unlocked(f, rec) then
		f = H.nextFloor(rec)
	end
	return f
end

function W.refreshFloors(rec, short)
	local sel = W.selected()
	local nextF = H.nextFloor(rec)
	local power = H.teamPower()
	for f, ui in ipairs(U.FloorRows) do
		local open = H.unlocked(f, rec)
		local cleared = rec.Cleared[f] == true
		local rp = H.recommended(f)
		local h = short and K.ROW_H_SHORT or K.ROW_H
		ui.Root.Size = UDim2.new(1, 0, 0, h)
		ui.Name.Position = UDim2.fromOffset(70, short and 2 or 6)
		ui.Sub.Position = UDim2.fromOffset(70, short and 26 or 34)
		ui.Sub.Size = UDim2.new(1, -190, 0, short and 22 or 24)
		local status, subColor, chip, chipColor
		if not open then
			status = G.Lock .. " Clear floor " .. (f - 1) .. " first"
			subColor = C.Muted
			chip, chipColor = "LOCKED", C.Locked
		elseif cleared then
			status = G.Check .. " Cleared"
			subColor = C.Green
			chip, chipColor = "CLEARED", C.Green
		else
			status = "Recommended power " .. (rp and H.commas(rp) or "?")
			subColor = (rp and power >= rp) and C.Green or C.Power
			if f == nextF then
				chip, chipColor = "NEXT", C.Gold
			else
				chip, chipColor = "OPEN", C.Blue
			end
		end
		ui.Sub.Text = status
		ui.Sub.TextColor3 = subColor
		ui.ChipText.Text = chip
		ui.ChipRim.Color = chipColor
		ui.ChipText.TextColor3 = (chip == "LOCKED") and C.Muted or WHITE
		ui.Root.BackgroundColor3 = (f == sel) and Theme.Lighten(C.Row, 0.14) or (open and C.Row or C.RowDark)
		ui.Rim.Color = (f == sel) and C.Accent or Theme.Darken(ui.Color, 0.35)
		ui.Rim.Thickness = (f == sel) and 3 or 2
		ui.Rim.Transparency = (f == sel) and 0 or 0.2
		ui.Name.TextColor3 = open and WHITE or C.Muted
		ui.Root:SetAttribute("Selected", f == sel)
		ui.Root:SetAttribute("Unlocked", open)
		ui.Root:SetAttribute("Cleared", cleared)
	end
end

-- a button inside the party box (NeonKit); returns the TextButton
function W.button(parent, name, text, color, size, order, callback, variant)
	return NeonKit.Button({
		Name = name,
		Text = text,
		Color = color,
		Variant = variant or "Primary",
		Size = size,
		TextSize = 20,
		LayoutOrder = order,
		Parent = parent,
		Callback = function()
			H.safe(name, callback)
		end,
	})
end

function W.setDisabled(button, disabled)
	if button then
		button:SetAttribute("Disabled", disabled == true)
	end
end

-- seconds left of the party countdown (ticks locally between two Lobby payloads)
function W.countdown(mine)
	local n = mine and tonumber(mine.Countdown)
	if not n then
		return nil
	end
	return math.max(0, math.ceil(n - (os.clock() - S.LobbyAt) - 1e-6))
end

function W.allReady(mine)
	for _, m in ipairs(type(mine.Members) == "table" and mine.Members or {}) do
		if type(m) == "table" and m.Ready ~= true and m.UserId ~= mine.Leader then
			return false
		end
	end
	return true
end

function W.myReady(mine)
	if S.ReadyWant ~= nil then
		return S.ReadyWant
	end
	for _, m in ipairs(type(mine.Members) == "table" and mine.Members or {}) do
		if type(m) == "table" and LocalPlayer and m.UserId == LocalPlayer.UserId then
			return m.Ready == true
		end
	end
	return false
end

function W.countdownText(mine)
	local left = W.countdown(mine)
	if not left then
		return nil
	end
	if W.allReady(mine) then
		return "Dungeon in " .. left .. "..."
	end
	return "Starting in " .. left .. " - press READY"
end

-- the party box when the player has no party: SOLO / PARTY + the open parties
function W.partyNone(box, short, sel)
	local info = H.floorInfo(sel)
	H.text(box, "Title", "Floor " .. sel .. " " .. G.Dot .. " " .. tostring(info.Name), "Heading", 20, WHITE, {
		Size = UDim2.new(1, 0, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
	})
	local row = H.frame(box, "Buttons", { Size = UDim2.new(1, 0, 0, short and 46 or 52), LayoutOrder = 2 })
	H.list(row, Enum.FillDirection.Horizontal, 10)
	local bw = UDim2.new(0.5, -5, 1, 0)
	U.Solo = W.button(row, "SoloButton", "SOLO", C.Green, bw, 1, function()
		if H.request("Solo", W.selected()) then
			H.hint("Starting floor " .. W.selected() .. "...", 3)
		end
	end)
	U.Create = W.button(row, "PartyButton", "PARTY", C.Accent, bw, 2, function()
		if H.request("Create", W.selected()) then
			H.hint("Party made! Friends can JOIN it here", 4)
		end
	end)
	local parties = {}
	for _, p in ipairs(S.Lobby and type(S.Lobby.Parties) == "table" and S.Lobby.Parties or {}) do
		if type(p) == "table" then
			parties[#parties + 1] = p
		end
	end
	local maxRows = W.maxParties(short)
	H.text(box, "OpenTitle", (#parties > 0) and "Open parties" or "No open parties yet - make one!", "Heading", 18, C.Muted, {
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 3,
	})
	for i, p in ipairs(parties) do
		if i > maxRows then
			break
		end
		W.partyRow(box, p, i, short)
	end
end

function W.partyRow(box, p, i, short)
	local row = H.frame(box, "Open" .. i, { BackgroundTransparency = 0, BackgroundColor3 = C.Row, Size = UDim2.new(1, 0, 0, short and 40 or 44), LayoutOrder = 3 + i })
	H.corner(row, 10)
	local count = tostring(p.Count or 1) .. "/" .. tostring(p.Max or 4)
	local where = p.InRun and ("in room " .. tostring(p.Room or 1)) or ("Floor " .. tostring(p.Floor or 1))
	H.text(row, "Text", tostring(p.LeaderName or "Someone") .. "'s party " .. G.Dot .. " " .. where .. " " .. G.Dot .. " " .. count, "Body", 18, WHITE, {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -120, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local join = W.button(row, "JoinButton", p.Open and "JOIN" or (p.InRun and "BUSY" or "FULL"), C.Blue, UDim2.fromOffset(96, short and 34 or 38), 1, function()
		if p.Open and H.request("Join", p.Leader) then
			H.hint("Joining " .. tostring(p.LeaderName or "the") .. "'s party...", 3)
		end
	end)
	join.AnchorPoint = Vector2.new(1, 0.5)
	join.Position = UDim2.new(1, -6, 0.5, 0)
	W.setDisabled(join, p.Open ~= true)
	join:SetAttribute("Leader", p.Leader)
end

-- the party box of the player's own party
function W.partyMine(box, short, mine)
	local me = LocalPlayer and LocalPlayer.UserId
	local leader = mine.Leader == me
	local f = math.floor(tonumber(mine.Floor) or 1)
	local info = H.floorInfo(f)
	H.text(box, "Title", (leader and "Your party" or "Party") .. " " .. G.Dot .. " Floor " .. f .. " " .. G.Dot .. " " .. tostring(info.Name), "Heading", 20, WHITE, {
		Size = UDim2.new(1, 0, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
	})
	local cd = W.countdownText(mine)
	U.Countdown = H.text(box, "Countdown", cd or (leader and "Press START when everyone is READY" or "Press READY, the leader starts"), "Body", 18, cd and C.Gold or C.Muted, {
		Size = UDim2.new(1, 0, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
	})
	local h = short and K.MEMBER_H_SHORT or K.MEMBER_H
	for i, m in ipairs(type(mine.Members) == "table" and mine.Members or {}) do
		if type(m) == "table" then
			local isMe = m.UserId == me
			local ready = m.Ready == true
			if isMe and S.ReadyWant ~= nil and not leader then
				ready = S.ReadyWant
			end
			local row = H.frame(box, "Member" .. i, { BackgroundTransparency = 0, BackgroundColor3 = isMe and Theme.Lighten(C.Row, 0.1) or C.Row, Size = UDim2.new(1, 0, 0, h), LayoutOrder = 10 + i })
			H.corner(row, 10)
			row:SetAttribute("UserId", m.UserId)
			row:SetAttribute("Ready", ready)
			local tick = H.text(row, "Ready", ready and G.Check or G.Hourglass, "Heading", 20, ready and C.Green or C.Muted, {
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(0, 28, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			tick:SetAttribute("Ready", ready)
			local name = (m.UserId == mine.Leader and (G.Crown .. " ") or "") .. tostring(m.Name or "?")
			H.text(row, "Name", name, "Body", 19, WHITE, { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -190, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
			H.text(row, "Power", G.Swords .. " " .. H.commas(m.Power or 0), "Heading", 18, C.Power, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, leader and not isMe and -52 or -10, 0, 0),
				Size = UDim2.new(0, 110, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			if leader and not isMe then
				local kick = W.button(row, "KickButton", G.Cross, C.Red, UDim2.fromOffset(38, h - 8), 1, function()
					if H.request("Kick", m.UserId) then
						H.hint("Removed " .. tostring(m.Name or "the player"), 3)
					end
				end, "Outline")
				kick.AnchorPoint = Vector2.new(1, 0.5)
				kick.Position = UDim2.new(1, -6, 0.5, 0)
				kick:SetAttribute("UserId", m.UserId)
			end
		end
	end
	-- the buttons come before the member list (a phone's sheet bottom sits under the thumbstick / jump buttons)
	local row = H.frame(box, "Buttons", { Size = UDim2.new(1, 0, 0, short and 46 or 52), LayoutOrder = 3 })
	H.list(row, Enum.FillDirection.Horizontal, 10)
	local bw = UDim2.new(0.5, -5, 1, 0)
	if leader then
		U.Start = W.button(row, "StartButton", "START", C.Green, bw, 1, function()
			if H.request("Start") then
				H.hint(W.allReady(mine) and "Starting..." or "Waiting 30 s for READY...", 3)
			end
		end)
		W.setDisabled(U.Start, W.countdown(mine) ~= nil and W.allReady(mine))
	else
		local want = W.myReady(mine)
		U.Ready = W.button(row, "ReadyButton", want and "NOT READY" or "READY", want and C.Grey or C.Green, bw, 1, function()
			local now = not W.myReady(mine)
			if H.request("Ready", now) then
				S.ReadyWant = now -- optimistic: the next Lobby payload is the truth
				W.refresh()
			end
		end)
	end
	U.LeaveParty = W.button(row, "LeaveButton", "LEAVE", C.Red, bw, 2, function()
		if H.request("Leave") then
			S.ReadyWant = nil
			H.hint("You left the party", 3)
		end
	end, "Outline")
end

-- open parties shown at once: 3 on desktops, 2 on a portrait phone, 1 on a landscape phone (the jump button corner)
function W.maxParties(short)
	if short then
		return 1
	end
	return H.isPhone() and 2 or 3
end

function W.partyHeight(short, mine)
	local h = 16
	if mine then
		local n = #(type(mine.Members) == "table" and mine.Members or {})
		h = h + 26 + 24 + n * ((short and K.MEMBER_H_SHORT or K.MEMBER_H) + 6) + (short and 46 or 52) + 18
	else
		local parties = S.Lobby and type(S.Lobby.Parties) == "table" and #S.Lobby.Parties or 0
		local rows = math.min(parties, W.maxParties(short))
		h = h + 26 + (short and 46 or 52) + 24 + rows * ((short and 40 or 44) + 6) + 18
	end
	return h
end

function W.footer()
	if not U.Footer then
		return
	end
	local text = ""
	if S.Hint and os.clock() < S.Hint.Until then
		text = S.Hint.Text
	else
		local rec = H.record()
		local sel = W.selected()
		local rp = H.recommended(sel)
		local power = H.teamPower()
		if rp and power > 0 and power < rp then
			text = "Your team looks weak for floor " .. sel .. ". Train it, or bring friends!"
		elseif rec.Best >= H.floorCount() then
			text = "Every floor cleared! Run them again for loot."
		else
			text = "Rooms, waves and a boss. Solo or up to 4 friends."
		end
	end
	U.Footer.Text = text
end

function W.layout()
	if not U.Dock then
		return
	end
	U.Dock.Refresh()
	local rect = U.Dock.Rect
	if not rect then
		return
	end
	if S.Open then
		H.avoidRight(rect.mode == "Side" and rect.x or nil)
	end
	S.Short = rect.designH < K.SHORT
end

function W.refresh()
	if not S.Built or not S.Open then
		return
	end
	W.layout()
	local short = S.Short
	local rec = H.record()
	local power = H.teamPower()
	U.Record.Text = "Best: floor " .. rec.Best .. " " .. G.Dot .. " " .. rec.Clears .. " clears " .. G.Dot .. " " .. rec.Runs .. " runs"
	U.Power.Text = G.Swords .. " " .. H.commas(power)
	W.refreshFloors(rec, short)
	-- the party box (rebuilt: a handful of frames, only on a payload / a tap)
	local mine = S.Lobby and type(S.Lobby.Mine) == "table" and S.Lobby.Mine or nil
	local sig = W.partySig(mine, short)
	if sig ~= S.PartySig then
		S.PartySig = sig
		H.clear(U.Party)
		U.Countdown, U.Start, U.Ready, U.Solo, U.Create = nil, nil, nil, nil, nil
		if mine then
			W.partyMine(U.Party, short, mine)
		else
			W.partyNone(U.Party, short, W.selected())
		end
	elseif mine and U.Countdown then
		local cd = W.countdownText(mine)
		if cd then
			U.Countdown.Text = cd
			U.Countdown.TextColor3 = C.Gold
		end
	end
	local contentH = U.Holder.Size.Y.Offset - 82
	local partyH = W.partyHeight(short, mine)
	-- phones: no footer line (the bottom edge of the sheet sits under Roblox's thumbstick / jump buttons)
	local footerH = H.isPhone() and 0 or 26
	U.Footer.Visible = footerH > 0
	local listH = math.max(short and 96 or 150, contentH - 36 - partyH - footerH - 12)
	U.Floors.Size = UDim2.new(1, 0, 0, listH)
	U.Party.Position = UDim2.fromOffset(0, 36 + listH + 6)
	U.Party.Size = UDim2.new(1, 0, 0, math.max(60, contentH - 36 - listH - 6 - footerH - 6))
	W.footer()
	if S.ScrollTo and U.Dock.Rect and U.Dock.Rect.mode == "Sheet" then
		-- (a portrait sheet keeps the list at the top: its rows scrolled above the sheet would count as covered screen
		-- for the coverage rule, which does not clip scrolling frames)
		S.ScrollTo = nil
		U.Floors.CanvasPosition = Vector2.new(0, 0)
	end
	if S.ScrollTo then
		-- bring the selected floor into view once after opening
		local f = S.ScrollTo
		S.ScrollTo = nil
		local rowH = (short and K.ROW_H_SHORT or K.ROW_H) + 6
		local top = 8 + (f - 1) * rowH
		local maxY = math.max(0, 8 + H.floorCount() * rowH + 8 - listH)
		U.Floors.CanvasPosition = Vector2.new(0, math.max(0, math.min(maxY, top - rowH * 0.5)))
	end
end

function W.partySig(mine, short)
	local parts = { tostring(short) }
	if mine then
		parts[#parts + 1] = "m" .. tostring(mine.Leader) .. ":" .. tostring(mine.Floor) .. ":" .. tostring(mine.Countdown ~= nil) .. ":" .. tostring(S.ReadyWant)
			.. ":" .. tostring(S.LobbyAt)
		for _, m in ipairs(type(mine.Members) == "table" and mine.Members or {}) do
			if type(m) == "table" then
				parts[#parts + 1] = tostring(m.UserId) .. tostring(m.Ready) .. tostring(m.Power)
			end
		end
	else
		parts[#parts + 1] = "n" .. tostring(W.selected())
		for _, p in ipairs(S.Lobby and type(S.Lobby.Parties) == "table" and S.Lobby.Parties or {}) do
			if type(p) == "table" then
				parts[#parts + 1] = tostring(p.Leader) .. ":" .. tostring(p.Floor) .. ":" .. tostring(p.Count) .. ":" .. tostring(p.Open) .. ":" .. tostring(p.Room)
			end
		end
	end
	return table.concat(parts, ",")
end

----------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------
function W.onBack(_name, inputState)
	if inputState == Enum.UserInputState.Begin and S.Open then
		DungeonController.Close()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

function W.syncBack()
	if S.Open == S.BackBound then
		return
	end
	S.BackBound = S.Open
	if S.Open then
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, W.onBack, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		end)
	else
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

function W.closeOthers()
	for _, name in ipairs({ "MenuController", "IndexController", "FusionController", "CareController", "ArenaController", "ObbyController" }) do
		local mod = H.controller(name)
		if mod and type(mod.Close) == "function" then
			pcall(mod.Close)
		end
	end
end

function DungeonController.Open(floorIndex, portal)
	if not initialized then
		DungeonController.Init()
	end
	if not U.Gui or H.inMatch() then
		return false
	end
	if S.Run or H.runAttr() then
		return false -- inside a run the run card is the dungeon's UI
	end
	if not W.build() then
		return false
	end
	local n = tonumber(floorIndex)
	if n and n >= 1 and n <= H.floorCount() then
		S.Floor = math.floor(n)
	end
	S.AtPortal = (typeof(portal) == "Instance") and portal or nil
	local was = S.Open
	if not was then
		W.closeOthers()
	end
	S.Open = true
	S.Token = S.Token + 1
	S.PartySig = nil
	if not was then
		S.ScrollTo = W.selected()
	end
	W.syncBack()
	U.Holder.Visible = true
	if not was then
		U.Pop.Scale = 0.9
		H.tween(U.Pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	H.request("Open")
	W.refresh()
	R.refresh()
	if not was then
		DungeonController.Opened:Fire("Dungeon")
	end
	return true
end

function DungeonController.Close()
	if not S.Open then
		return
	end
	S.Open = false
	S.AtPortal = nil
	S.Token = S.Token + 1
	local mine = S.Token
	W.syncBack()
	H.avoidRight(nil)
	if U.Pop then
		H.tween(U.Pop, 0.12, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(0.13, function()
		if S.Token == mine and not S.Open and U.Holder then
			U.Holder.Visible = false
			U.Pop.Scale = 1
		end
	end)
	R.refresh()
	DungeonController.Closed:Fire("Dungeon")
end

function DungeonController.IsOpen()
	return S.Open == true
end

function DungeonController.Request(action, a, b)
	return H.request(action, a, b)
end

function DungeonController.GetState()
	return {
		Window = S.Open and "Dungeon" or nil,
		Floor = S.Built and W.selected() or S.Floor,
		Lobby = S.Lobby,
		Run = S.Run,
		End = S.End,
		Loot = S.Loot,
		Totals = S.Totals,
		Ready = S.ReadyWant,
		Lit = S.Lit,
		CardMode = S.CardMode,
		Countdown = S.Lobby and S.Lobby.Mine and W.countdown(S.Lobby.Mine) or nil,
		Fade = S.Fade and S.Fade.Phase or nil, -- "Out" | "Hold" | "In" while the room change fade shows
		Door = (S.Run and R.doorWait()) or nil, -- "press" | "wait" | "go" at an open door
		Enter = S.Enter and S.Enter.Phase or nil, -- "Rush" | "Cover" | "Hold" | "Reveal" while the entrance plays
		Walk = S.Walk and S.Walk.Phase or nil, -- "Hold" | "Walk" | "Blend" while the room walk-in plays
		WalkSkip = S.WalkSkip, -- wave 6: why the last room payload played no walk-in: "NoFade" | "FadeIn" | "InMatch" |
		-- "NoCharacter" | "NoRoom" | "Inward" | "Error" (nil = it played)
		Shoulder = S.ShoulderHum ~= nil,
	}
end

----------------------------------------------------------------------
-- The run card (desktop side card / phone top-band chip), the toasts and the End card
----------------------------------------------------------------------
function R.build()
	-- (IgnoreGuiInset stays false like every text-carrying gui; R.place converts screen px to the gui area)
	local gui = CloudUI.NewScreenGui("NimbusDungeonRun", K.RUN_ORDER)
	U.RunGui = gui
	-- the side card
	local card = NeonKit.Card({ Name = "RunCard", Size = UDim2.fromOffset(K.CARD_W, 200), Color = C.Accent, Glow = true, Parent = gui })
	card.Root.Visible = false
	U.Card = card
	U.CardScale = Util.Create("UIScale", { Name = "ReadScale", Scale = 1, Parent = card.Root })
	local body = H.frame(card.Body, "List", { Size = UDim2.new(1, 0, 1, 0) })
	H.pad(body, 14, 10, 12, 12)
	H.list(body, Enum.FillDirection.Vertical, 6)
	U.CardList = body
	U.CardTitle = H.text(body, "Title", "", "Heading", 21, WHITE, { Size = UDim2.new(1, 0, 0, 28), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1 })
	U.CardRoom = H.text(body, "Room", "", "Heading", 19, C.Gold, { Size = UDim2.new(1, 0, 0, 26), RichText = false, LayoutOrder = 2 })
	U.CardWave = H.text(body, "Wave", "", "Body", 18, WHITE, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 3 })
	U.CardStatus = H.text(body, "Status", "", "Body", 19, WHITE, { Size = UDim2.new(1, 0, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 4 })
	U.CardToast = H.frame(body, "LootToast", { BackgroundTransparency = 0, BackgroundColor3 = Theme.Darken(C.Gold, 0.55), Size = UDim2.new(1, 0, 0, 58), Visible = false, LayoutOrder = 5 })
	H.corner(U.CardToast, 10)
	H.stroke(U.CardToast, C.Gold, 2, 0)
	H.pad(U.CardToast, 10, 6, 10, 6)
	U.CardToastText = H.text(U.CardToast, "Text", "", "Heading", 19, WHITE, { Size = UDim2.new(1, 0, 1, 0), TextWrapped = true })
	U.CardMembers = H.frame(body, "Members", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 6 })
	Util.Create("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 26), CellPadding = UDim2.fromOffset(6, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = U.CardMembers })
	U.CardLoot = H.text(body, "Loot", "", "Heading", 18, C.Cash, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 7 })
	local buttons = H.frame(body, "Buttons", { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 8 })
	U.CardButtons = buttons
	H.list(buttons, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right)
	-- (bug batch 2 #14: no CHEST button; a chest is picked only with its own E prompt in the alcove)
	U.CardReady = W.button(buttons, "ReadyButton", "READY", C.Green, UDim2.new(0.5, -4, 1, 0), 2, R.ready)
	U.CardLeave = W.button(buttons, "LeaveButton", "LEAVE", C.Red, UDim2.new(0.5, -4, 1, 0), 3, R.leave, "Outline")
	-- the phone chip (one line in Roblox's top band)
	local chip = NeonKit.Card({ Name = "RunChip", Size = UDim2.fromOffset(420, K.CHIP_H), Color = C.Accent, Glow = false, Floor = false, Parent = gui })
	chip.Root.Visible = false
	U.Chip = chip
	U.ChipScale = Util.Create("UIScale", { Name = "ReadScale", Scale = 0.8, Parent = chip.Root })
	U.ChipText = H.text(chip.Body, "Text", "", "Heading", 19, WHITE, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -112, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	U.ChipButton = W.button(chip.Body, "LeaveButton", "LEAVE", C.Red, UDim2.fromOffset(92, K.CHIP_H - 10), 1, function()
		if S.Run then
			R.leave()
		elseif S.Lobby and S.Lobby.Mine and LocalPlayer and S.Lobby.Mine.Leader ~= LocalPlayer.UserId and not W.myReady(S.Lobby.Mine) then
			R.ready()
		end
	end, "Outline")
	U.ChipButton.AnchorPoint = Vector2.new(1, 0.5)
	U.ChipButton.Position = UDim2.new(1, -5, 0.5, 0)
	-- the End card
	local endCard = NeonKit.Card({ Name = "EndCard", Size = UDim2.fromOffset(K.END_W, 200), Color = C.Accent, Glow = true, Parent = gui })
	endCard.Root.Visible = false
	U.End = endCard
	U.EndScale = Util.Create("UIScale", { Name = "ReadScale", Scale = 1, Parent = endCard.Root })
	local eb = H.frame(endCard.Body, "List", { Size = UDim2.new(1, 0, 1, 0) })
	H.pad(eb, 16, 12, 16, 14)
	H.list(eb, Enum.FillDirection.Vertical, 6)
	U.EndTitle = H.text(eb, "Title", "", "Title", 28, WHITE, { Size = UDim2.new(1, 0, 0, 36), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1 })
	U.EndReason = H.text(eb, "Reason", "", "Body", 19, C.Muted, { Size = UDim2.new(1, 0, 0, 50), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2 })
	U.EndTotals = H.text(eb, "Totals", "", "Heading", 20, WHITE, { Size = UDim2.new(1, 0, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 3 })
	U.EndFirst = H.text(eb, "FirstClear", "", "Heading", 20, C.Gold, { Size = UDim2.new(1, 0, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 4 })
	U.EndUnlock = H.text(eb, "Unlocked", "", "Heading", 19, C.Green, { Size = UDim2.new(1, 0, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 5 })
	local ok = W.button(eb, "OkButton", "OK", C.Accent, UDim2.new(1, 0, 0, 46), 6, function()
		S.End = nil
		R.refresh()
	end)
	U.EndOk = ok
end

function R.ready()
	local mine = S.Lobby and S.Lobby.Mine
	if not mine then
		return
	end
	local now = not W.myReady(mine)
	if H.request("Ready", now) then
		S.ReadyWant = now
		S.PartySig = nil
		R.refresh()
		W.refresh()
	end
end

-- bug batch 2 #14: true while the server still owes me a chest in the alcove (Run.ChestOwed lists the members who have
-- not picked one; an older payload without it: until my Chest arrives)
function R.chestOwed()
	local run = S.Run
	if not run or run.State ~= "Treasure" or S.ChestOpened then
		return false
	end
	if type(run.ChestOwed) ~= "table" then
		return true
	end
	local me = LocalPlayer and LocalPlayer.UserId
	for _, uid in ipairs(run.ChestOwed) do
		if uid == me then
			return true
		end
	end
	return false
end

-- bug batch 2 #14: once I picked (or the alcove owes me nothing) the other chests' "Pick ONE chest / Open" prompts
-- would only refuse: switch them off locally (the server still checks every pick; it switches taken ones off for all)
function R.lockChests()
	local run = S.Run
	if not run or run.State ~= "Treasure" or R.chestOwed() then
		return
	end
	local pocket = (S.Pocket and S.Pocket.Parent) and S.Pocket or R.findPocket()
	if not pocket then
		return
	end
	for _, d in ipairs(pocket:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "ChestPrompt" and d.Enabled then
			d.Enabled = false
		end
	end
end

-- LEAVE: two presses within LEAVE_CONFIRM seconds -> DungeonRequest("Quit")
function R.leave()
	if not S.Run then
		return
	end
	local now = os.clock()
	if now <= S.LeaveArmed then
		S.LeaveArmed = 0
		H.request("Quit")
		R.refresh()
		return
	end
	S.LeaveArmed = now + K.LEAVE_CONFIRM
	R.refresh()
end

function R.toast(text, color, seconds, short)
	S.Toast = { Text = tostring(text), Short = short, Color = color or C.Gold, Until = os.clock() + (seconds or K.TOAST_SECONDS) }
	R.refresh()
end

-- seconds left of the current run phase (counted locally from when it began)
function R.phaseLeft()
	local run = S.Run
	if not run then
		return nil
	end
	local since = os.clock() - S.PhaseAt
	if run.State == "Treasure" then
		return math.max(0, H.dungeonNumber("TreasureSeconds", K.TREASURE) - since)
	end
	return nil
end

-- the door wait (decision 2): "press" (go and press E), "wait" (I pressed, others not yet), "go" (the transit) or nil;
-- -> kind, missing count, names of who did not press yet
function R.doorWait()
	local run = S.Run
	if not run or run.EnterOpen ~= true then
		if run and run.Transit == true then
			return "go", 0, {}
		end
		return nil, 0, {}
	end
	local pressed = {}
	for _, uid in ipairs(type(run.Confirmed) == "table" and run.Confirmed or {}) do
		pressed[uid] = true
	end
	local names = {}
	for _, m in ipairs(type(run.Members) == "table" and run.Members or {}) do
		if not m.Left and not pressed[m.UserId] then
			names[#names + 1] = tostring(m.Name or "?")
		end
	end
	local missing = math.max(0, math.floor(tonumber(run.NeedConfirm) or #names))
	if LocalPlayer and pressed[LocalPlayer.UserId] then
		return "wait", missing, names
	end
	return "press", missing, names
end

-- touch-only devices tap the prompt's button instead of pressing E
function R.pressWord()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "tap Enter"
	end
	return "press E"
end

function R.doorText(short)
	local kind, missing, names = R.doorWait()
	if kind == "go" then
		return "Here we go!"
	elseif kind == "wait" then
		if missing <= 0 then
			return "Here we go!"
		end
		if short then
			return "Waiting for " .. missing .. " more"
		end
		return "Waiting for " .. missing .. " more (" .. table.concat(names, ", ") .. ")"
	elseif kind == "press" then
		return short and ("Door: " .. R.pressWord()) or ("Go to the door and " .. R.pressWord())
	end
	return nil
end

function R.statusText()
	local run = S.Run
	local left = R.phaseLeft()
	local door = R.doorText(false)
	if run.State == "Hall" then
		return door or "Get ready!"
	elseif run.State == "Corridor" then
		if run.Phase == "Walk" then
			return door or "Room cleared! The bars open..."
		end
		if S.Walk then
			return "Here we go!"
		end
		return door or "Walk into the room to start the fight"
	elseif run.State == "Fight" then
		return (tonumber(run.Room) == 4) and "Boss fight! Beat the boss and its escort" or "Fight! Beat every wave"
	elseif run.State == "Treasure" then
		return (R.chestOwed() and "Pick ONE chest! Exit in " or "Back to the plaza in ") .. H.clock(left or 0)
	elseif run.State == "Ending" then
		return "Back to the plaza..."
	end
	return ""
end

-- the run card is exactly as tall as its visible rows (fixed rows, no AutomaticSize)
function R.cardHeight()
	U.CardButtons.Visible = U.CardReady.Visible or U.CardLeave.Visible
	U.ChipText.Size = UDim2.new(1, U.ChipButton.Visible and -112 or -20, 1, 0)
	local h = 10 + 12
	local n = 0
	for _, child in ipairs(U.CardList:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			h = h + child.Size.Y.Offset
			n = n + 1
		end
	end
	h = h + math.max(0, n - 1) * 6
	U.Card.Root.Size = UDim2.fromOffset(K.CARD_W, h)
end

-- the phone chip's one line (the battle HUD shows the wave during a fight)
function R.chipText(room, count)
	local run = S.Run
	local left = R.phaseLeft()
	if run.State == "Fight" then
		return (room >= count) and ("Floor " .. tostring(run.Floor or 1) .. " " .. G.Dot .. " Boss") or ("Room " .. room .. "/" .. count)
	elseif run.State == "Hall" or (run.State == "Corridor" and run.Phase == "Walk") then
		return R.doorText(true) or ((run.State == "Hall") and "Get ready!" or "Cleared!")
	elseif run.State == "Corridor" then
		return R.doorText(true) or "Walk in!"
	elseif run.State == "Treasure" then
		return (R.chestOwed() and "Pick ONE chest! " or "Exit in ") .. H.clock(left or 0)
	end
	return "Back soon..."
end

function R.pips(room, count)
	local out = {}
	for i = 1, count do
		if i == count then
			out[#out + 1] = (i <= room) and G.Crown or G.PipOff
		else
			out[#out + 1] = (i <= room) and G.Pip or G.PipOff
		end
	end
	return table.concat(out, " ")
end

function R.lootText()
	local t = S.Totals
	local parts = { "$" .. H.commas(t.Cash), G.Cloud .. " " .. H.commas(t.Tokens), "+" .. H.commas(t.Xp) .. " XP" }
	if (tonumber(t.Gems) or 0) > 0 then
		parts[#parts + 1] = G.Gem .. " " .. H.commas(t.Gems)
	end
	return table.concat(parts, "   ")
end

-- which card to show: "Run" (in a run), "Countdown" (a party countdown while the window is closed), or nil
function R.view()
	if H.inMatch() then
		return nil
	end
	if S.Run then
		return "Run"
	end
	local mine = S.Lobby and S.Lobby.Mine
	if mine and not S.Open and W.countdown(mine) ~= nil and not mine.InRun then
		return "Countdown"
	end
	return nil
end

-- Roblox's top bar height (the gui area starts below it)
function R.inset()
	local ok, inset = pcall(function()
		return game:GetService("GuiService"):GetGuiInset().Y
	end)
	return (ok and tonumber(inset)) or 0
end

function R.place()
	local vp = H.viewport()
	local w, h = vp.X, vp.Y
	local top = R.inset()
	local f = Theme.ScreenFactor(h)
	local phone = H.isPhone()
	S.CardMode = nil
	-- the End card
	local endH = U.End.Root.Size.Y.Offset
	-- bug batch 2 #1: phones start the End card below the HUD's top-right currency strips, so they stay in view
	-- for the result (the HUD still hides them should the card ever reach them)
	local strips = R.stripsBottom()
	if phone and w < h then
		-- portrait: right of the menu tile column, under the currency strips (clear of the screen's centre)
		local scale = 0.8
		U.EndScale.Scale = scale
		U.End.Root.Size = UDim2.fromOffset(math.floor((w - 172) / scale), endH)
		U.End.Root.Position = UDim2.fromOffset(160, math.max(math.floor(h * 0.18) - top, strips))
	elseif phone then
		-- landscape: below the strips it must still end above Roblox's jump button (70 px, 20 px off the bottom); it
		-- shrinks down to 0.7 (20 px design text -> 14 px) for that, else it keeps its old spot and the strips hide
		local y = math.max(52 - top, strips)
		local scale = math.min(0.8, (h - top - 90 - 8 - y) / math.max(1, endH))
		if scale < 0.7 then
			y, scale = 52 - top, 0.8
		end
		local width = math.min(K.END_W, math.floor(w * 0.44 / scale))
		U.EndScale.Scale = scale
		U.End.Root.Size = UDim2.fromOffset(width, endH)
		U.End.Root.Position = UDim2.fromOffset(math.floor(w - 12 - width * scale), y)
	else
		U.EndScale.Scale = f
		U.End.Root.Size = UDim2.fromOffset(K.END_W, endH)
		U.End.Root.Position = UDim2.fromOffset(math.floor(w - 12 - K.END_W * f), math.floor(h * 0.3) - top)
	end
	-- the run card / chip
	if phone then
		local scale = 0.8
		local x0 = (w < h) and 132 or math.max(300, math.floor(w * 0.36), R.pillsRight() + 8)
		local x1 = w - ((w < h) and 54 or 68)
		local width = math.max(220, math.floor((x1 - x0) / scale))
		width = math.min(width, 520)
		U.ChipScale.Scale = scale
		U.Chip.Root.Size = UDim2.fromOffset(width, K.CHIP_H)
		U.Chip.Root.Position = UDim2.fromOffset(x0, 4 - top)
		S.CardMode = "Chip"
	else
		U.CardScale.Scale = f
		U.Card.Root.Position = UDim2.fromOffset(math.floor(w - 12 - K.CARD_W * f), math.floor(h * 0.4) - top)
		S.CardMode = "Card"
	end
end

-- just below the HUD's currency strips when they sit in the top-right corner under the top bar (gui-area px, the
-- same space as our cards), 0 when they are elsewhere (Roblox's top band in a battle) or unmeasured
function R.stripsBottom()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("NimbusHud")
	if not hud or hud:GetAttribute("CurrencyMode") ~= "TopRight" then
		return 0
	end
	local bottom = tonumber(hud:GetAttribute("TopRightBottom"))
	return (bottom and bottom > 0) and math.ceil(bottom + 8) or 0
end

-- landscape phones in a battle: the HUD's currency strips share Roblox's top band; the chip starts right of them
function R.pillsRight()
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("NimbusHud")
	if not hud or hud:GetAttribute("CurrencyMode") ~= "TopBand" then
		return 0
	end
	local cur = hud:FindFirstChild("Currency", true)
	if not cur or not cur:IsA("GuiObject") then
		return 0
	end
	return math.floor(cur.AbsolutePosition.X + cur.AbsoluteSize.X + 0.5)
end

function R.refresh()
	if not U.RunGui then
		return
	end
	local view = R.view()
	local now = os.clock()
	if view == nil and S.End == nil then
		-- nothing to show (the common case in the lobby): no layout work on the 4 Hz tick
		U.Card.Root.Visible = false
		U.Chip.Root.Visible = false
		U.End.Root.Visible = false
		return
	end
	R.place()
	local toast = S.Toast and now < S.Toast.Until and S.Toast or nil
	local chip = S.CardMode == "Chip"
	U.Card.Root.Visible = view ~= nil and not chip
	U.Chip.Root.Visible = view ~= nil and chip
	U.Card.Root:SetAttribute("View", view)
	U.Chip.Root:SetAttribute("View", view)
	-- the End card
	local endShown = S.End ~= nil and now - S.EndAt < K.END_SECONDS and not H.inMatch()
	U.End.Root.Visible = endShown
	if endShown then
		R.fillEnd()
	end
	if not view then
		return
	end
	if view == "Countdown" then
		local mine = S.Lobby.Mine
		local cd = W.countdownText(mine) or ""
		local isLeader = LocalPlayer and mine.Leader == LocalPlayer.UserId
		local needReady = not isLeader and not W.myReady(mine)
		local f = math.floor(tonumber(mine.Floor) or 1)
		U.CardTitle.Text = G.Torch .. " The Dungeon " .. G.Dot .. " Floor " .. f
		U.CardRoom.Text = cd
		U.CardWave.Visible = false
		U.CardStatus.Text = "Stay near the Dungeon gate"
		U.CardMembers.Visible = false
		U.CardLoot.Visible = false
		U.CardToast.Visible = false
		U.CardReady.Visible = needReady
		U.CardLeave.Visible = false
		U.ChipText.Text = cd
		U.ChipButton.Text = "READY"
		U.ChipButton.Visible = needReady
		R.cardHeight()
		return
	end
	local run = S.Run
	local info = H.floorInfo(tonumber(run.Floor) or 1)
	local f = tonumber(run.Floor) or 1
	local room = math.floor(tonumber(run.Room) or 1)
	local count = math.floor(tonumber(run.RoomCount) or 4)
	U.Card.SetColor(H.elementColor(run.Element or info.Element))
	U.CardTitle.Text = "Floor " .. f .. " " .. G.Dot .. " " .. tostring(run.Name or info.Name)
	U.CardRoom.Text = ((room >= count) and "Boss room" or ("Room " .. room .. " / " .. count)) .. "   " .. R.pips(room, count)
	local waves = tonumber(run.Waves)
	local wave = tonumber(run.Wave)
	U.CardWave.Visible = waves ~= nil and waves > 0 and run.State == "Fight"
	U.CardWave.Text = "Wave " .. tostring(wave or 1) .. " / " .. tostring(waves or 1)
	U.CardStatus.Text = R.statusText()
	U.CardToast.Visible = toast ~= nil
	if toast then
		U.CardToastText.Text = toast.Text
		U.CardToast.BackgroundColor3 = Theme.Darken(toast.Color, 0.6)
	end
	-- members (a party only)
	local members = type(run.Members) == "table" and run.Members or {}
	U.CardMembers.Visible = #members > 1
	U.CardMembers.Size = UDim2.new(1, 0, 0, math.ceil(math.min(4, #members) / 2) * 30)
	local sig = ""
	for _, m in ipairs(members) do
		sig = sig .. tostring(m.UserId) .. tostring(m.Downed) .. tostring(m.Left) .. ";"
	end
	if sig ~= S.MemberSig then
		S.MemberSig = sig
		H.clear(U.CardMembers)
		for i, m in ipairs(members) do
			if i > 4 then
				break
			end
			local glyph = m.Left and G.Cross or (m.Downed and G.Skull or G.Check)
			local color = m.Left and C.Muted or (m.Downed and C.Red or C.Green)
			local chipF = H.frame(U.CardMembers, "Member" .. i, { BackgroundTransparency = 0, BackgroundColor3 = C.RowDark, LayoutOrder = i })
			H.corner(chipF, 8)
			chipF:SetAttribute("Downed", m.Downed == true)
			chipF:SetAttribute("Left", m.Left == true)
			H.text(chipF, "Text", glyph .. " " .. tostring(m.Name or "?"), "Body", 18, color, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -8, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
		end
	end
	local t = S.Totals
	U.CardLoot.Visible = (t.Cash + t.Tokens + t.Xp + (t.Gems or 0)) > 0
	U.CardLoot.Text = R.lootText()
	U.CardReady.Visible = false
	U.CardLeave.Visible = run.State ~= "Ending"
	local armed = now <= S.LeaveArmed
	U.CardLeave.Text = armed and "Sure? Tap again" or "LEAVE"
	-- the phone chip: room / wave or the toast or the status
	U.ChipText.Text = toast and (toast.Short or toast.Text) or R.chipText(room, count)
	U.ChipButton.Visible = run.State ~= "Ending"
	R.cardHeight()
	-- (bug batch 2 #14: the chip's button is LEAVE in the alcove too; chests open only at the chest)
	U.ChipButton.Text = armed and "SURE?" or "LEAVE"
	U.ChipButton:SetAttribute("Color", "Red")
end

function R.fillEnd()
	local e = S.End
	local cleared = e.Cleared == true
	local f = math.floor(tonumber(e.Floor) or 1)
	local info = H.floorInfo(f)
	local name = tostring(e.Name or info.Name)
	U.End.SetColor(cleared and C.Green or C.Red)
	U.EndTitle.Text = cleared and ("Floor " .. f .. " cleared!") or "Run over"
	U.EndTitle.TextColor3 = cleared and C.Green or WHITE
	local reason = tostring(e.Reason or "")
	local text
	if cleared then
		text = "You beat the " .. name .. "!"
	elseif reason == "Wipe" or reason == "Timeout" then
		text = "Floor " .. f .. ": the " .. name .. " got you in room " .. tostring(e.Room or 1) .. ". Train your team and try again!"
	elseif reason == "Quit" or reason == "Left" then
		text = "You left the dungeon. Your loot is kept."
	elseif reason == "Shutdown" then
		text = "The server is restarting. Your loot is kept."
	else
		text = "The run ended. Your loot is kept."
	end
	U.EndReason.Text = text
	local t = type(e.Totals) == "table" and e.Totals or S.Totals
	local parts = { "$" .. H.commas(t.Cash), G.Cloud .. " " .. H.commas(t.Tokens), "+" .. H.commas(t.Xp) .. " XP" }
	if (tonumber(t.Gems) or 0) > 0 then
		parts[#parts + 1] = G.Gem .. " " .. H.commas(t.Gems)
	end
	U.EndTotals.Text = table.concat(parts, "   ")
	local first = type(e.FirstClear) == "table" and e.FirstClear or nil
	U.EndFirst.Visible = first ~= nil
	if first then
		U.EndFirst.Text = G.Star .. " First clear! +" .. H.commas(first.Tokens or 0) .. " " .. G.Cloud .. "  +" .. H.commas(first.Gems or 0) .. " " .. G.Gem
	end
	local lines = {}
	if tonumber(e.Unlocked) then
		lines[#lines + 1] = "Floor " .. math.floor(e.Unlocked) .. " unlocked!"
	end
	if e.NewBest and #lines == 0 then
		lines[#lines + 1] = "New best: floor " .. tostring(tonumber(e.NewBest) or f)
	end
	U.EndUnlock.Visible = #lines > 0
	U.EndUnlock.Text = table.concat(lines, "  " .. G.Dot .. "  ")
	-- fixed rows (no AutomaticSize): the card is exactly as tall as what it shows; a narrow card (portrait phone)
	-- gives every row two lines
	local narrow = U.End.Root.Size.X.Offset < 340
	local row = narrow and 46 or 26
	local reasonH = (#text > (narrow and 26 or 40)) and 50 or 26
	U.EndReason.Size = UDim2.new(1, 0, 0, reasonH)
	for _, label in ipairs({ U.EndTotals, U.EndFirst, U.EndUnlock }) do
		label.Size = UDim2.new(1, 0, 0, row)
		label.TextWrapped = narrow
		label.TextTruncate = narrow and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
	end
	local h = 12 + 36 + 6 + reasonH + 6 + row + 6 + (first and (row + 6) or 0) + (#lines > 0 and (row + 6) or 0) + 46 + 14
	U.End.Root.Size = UDim2.fromOffset(U.End.Root.Size.X.Offset, h)
end

----------------------------------------------------------------------
-- The room change fade (dungeon-fixes decision 2): one black Frame in its own ScreenGui
----------------------------------------------------------------------
function R.buildFade()
	local gui = CloudUI.NewScreenGui("NimbusDungeonFade", K.FADE_ORDER)
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	U.FadeGui = gui
	U.Fade = Util.Create("Frame", {
		Name = "Fade",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
end

function R.fadeStep(v, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	return math.max(0, math.min(K.FADE_MAX_STEP, v))
end

function R.fadeTween(target, seconds)
	if S.FadeTween then
		pcall(function()
			S.FadeTween:Cancel()
		end)
		S.FadeTween = nil
	end
	if seconds <= 0 then
		U.Fade.BackgroundTransparency = target
		return
	end
	S.FadeTween = H.tween(U.Fade, seconds, { BackgroundTransparency = target }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
end

-- DungeonState "Fade" { Out, Hold, In }: to black over Out, hold (until the next room's Run payload arrived, >= Hold),
-- back over In; FADE_SAFETY clears it whatever happens
function R.fade(payload)
	if not U.Fade then
		return
	end
	local fade = {
		Token = (S.Fade and S.Fade.Token or S.FadeSeq or 0) + 1,
		Out = R.fadeStep(payload.Out, 0.45),
		Hold = R.fadeStep(payload.Hold, 0.35),
		In = R.fadeStep(payload.In, 0.45),
		Key = S.PhaseKey,
		Phase = "Out",
		HardAt = os.clock() + K.FADE_SAFETY,
	}
	-- wave 5: where the camera sits behind the character at the door (the walk-in blends back to it)
	local camera = Workspace.CurrentCamera
	local rp = H.rootPosition()
	if camera and rp and camera.CameraType ~= Enum.CameraType.Scriptable then
		fade.CamOff = camera.CFrame.Position - rp
		fade.CamRot = camera.CFrame - camera.CFrame.Position
	end
	S.FadeSeq = fade.Token
	S.Fade = fade
	U.FadeGui.Enabled = true
	U.Fade.Visible = true
	R.fadeTween(0, fade.Out)
	task.delay(fade.Out + fade.Hold, function()
		if S.Fade == fade then
			fade.Phase = "Hold"
			-- the server moved us already (a new State / Room): fade back in now, else on the next Run payload
			if S.PhaseKey ~= fade.Key or not S.Run then
				R.fadeIn()
			end
		end
	end)
	task.delay(K.FADE_SAFETY, function()
		if S.Fade == fade then
			R.clearFade()
		end
	end)
end

function R.fadeIn()
	local fade = S.Fade
	if not fade or fade.Phase == "In" then
		return
	end
	fade.Phase = "In"
	if S.Walk and S.Walk.Phase == "Hold" then
		H.safe("walk go", R.walkGo)
	end
	R.fadeTween(1, fade.In)
	task.delay(fade.In, function()
		if S.Fade == fade then
			R.clearFade()
		end
	end)
end

-- the overlay off at once (End, leaving the run, the safety timeout)
function R.clearFade()
	S.Fade = nil
	if S.Walk and S.Walk.Phase == "Hold" then
		H.safe("walk go", R.walkGo)
	end
	if S.FadeTween then
		pcall(function()
			S.FadeTween:Cancel()
		end)
		S.FadeTween = nil
	end
	if U.Fade then
		U.Fade.BackgroundTransparency = 1
		U.Fade.Visible = false
	end
	if U.FadeGui then
		U.FadeGui.Enabled = false
	end
end

-- the light loop's safety net (a lost task.delay never leaves the screen black)
function R.fadeTick()
	local fade = S.Fade
	if not fade then
		return
	end
	local now = os.clock()
	if now >= fade.HardAt then
		R.clearFade()
	elseif fade.Phase == "Hold" and now >= fade.HardAt - fade.In then
		R.fadeIn()
	end
end

----------------------------------------------------------------------
-- Lighting (LightingStack "Dungeon") and the door slides
----------------------------------------------------------------------
function R.lightingStack()
	if R.LS == nil then
		local module = Client:FindFirstChild("LightingStack")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module)
		end
		R.LS = (ok and type(result) == "table") and result or false
	end
	return R.LS or nil
end

-- bug #5: each style tier has its own mood (DungeonBuilder.Styles[s].Mood, a little darker deeper in the tier); the
-- server writes it on the pocket's holder (MoodAmbient / MoodOutdoor / MoodBrightness / MoodContrast / MoodTint).
-- No holder attributes (an older server, the lobby) = the contract 5.6 preset. The mood is never darker than that
-- preset (ambient per channel, brightness): the review's phone-readability cap (DungeonBuilder.MoodFloor, server side).
local function atLeast(c, lo)
	return Color3.new(math.max(c.R, lo.R), math.max(c.G, lo.G), math.max(c.B, lo.B))
end
function R.mood(holder)
	local amb = holder and holder:GetAttribute("MoodAmbient")
	if typeof(amb) ~= "Color3" then
		return nil
	end
	local out = holder:GetAttribute("MoodOutdoor")
	local tint = holder:GetAttribute("MoodTint")
	return {
		Lighting = {
			Ambient = atLeast(amb, PRESET.Lighting.Ambient),
			OutdoorAmbient = atLeast(typeof(out) == "Color3" and out or PRESET.Lighting.OutdoorAmbient, PRESET.Lighting.OutdoorAmbient),
		},
		ColorCorrection = {
			Brightness = math.max(tonumber(holder:GetAttribute("MoodBrightness")) or PRESET.ColorCorrection.Brightness, PRESET.ColorCorrection.Brightness),
			Contrast = tonumber(holder:GetAttribute("MoodContrast")) or PRESET.ColorCorrection.Contrast,
			TintColor = typeof(tint) == "Color3" and tint or PRESET.ColorCorrection.TintColor,
		},
	}
end

function R.preset()
	local mood = R.mood(R.findPocket and R.findPocket() or nil)
	S.MoodSet = mood ~= nil
	local preset = { Lighting = mood and mood.Lighting or PRESET.Lighting, ColorCorrection = mood and mood.ColorCorrection or PRESET.ColorCorrection }
	local atmosphere = game:GetService("Lighting"):FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		if not R.BaseDensity then
			R.BaseDensity = atmosphere.Density
		end
		preset.Atmosphere = { Density = math.min(1, (R.BaseDensity or 0.3) + PRESET.AtmosphereAdd) }
	end
	return preset
end

-- client/SoundFx (optional: a build without it is silent)
function R.soundFx()
	if R.SF == nil then
		local module = Client:FindFirstChild("SoundFx")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module)
		end
		R.SF = (ok and type(result) == "table") and result or false
	end
	return R.SF or nil
end

function R.sound(name)
	local SF = R.soundFx()
	if SF and type(SF.Play) == "function" then
		H.safe("sound", SF.Play, name)
	end
end

function R.light(on)
	if on == S.Lit then
		return
	end
	local LS = R.lightingStack()
	S.Lit = on
	local SF = R.soundFx()
	if SF and type(SF.SetLayer) == "function" then
		H.safe("music", SF.SetLayer, "Dungeon", on) -- (the dungeon's track while in the run; back to the lobby's after)
	end
	if not LS then
		return
	end
	if on then
		H.safe("light push", LS.Push, K.LIGHT_ID, R.preset(), K.LIGHT_SECONDS)
		if not S.MoodSet then
			-- the run started before the player stood in the pocket (streaming, a slow join): re-read the style's mood
			-- every K.MOOD_RETRY s up to K.MOOD_TRIES times while the run's lighting is on, push it once it can be read
			S.MoodGen = (S.MoodGen or 0) + 1
			local gen = S.MoodGen
			task.spawn(function()
				for _ = 1, K.MOOD_TRIES or 10 do
					task.wait(K.MOOD_RETRY or 1)
					if not S.Lit or S.MoodSet or S.MoodGen ~= gen then
						return
					end
					local preset = R.preset()
					if S.MoodSet then
						H.safe("light push", LS.Push, K.LIGHT_ID, preset, K.LIGHT_SECONDS)
						return
					end
				end
			end)
		end
	else
		H.safe("light pop", LS.Pop, K.LIGHT_ID, K.LIGHT_SECONDS)
	end
end

-- bug batch 2 (#19): the camera zoom cap of a run (MovementController.SetZoomMax: K.ZOOM_RUN on, nil = the normal 40)
function R.zoom(on)
	on = on == true
	if on == S.Zoomed then
		return
	end
	S.Zoomed = on
	R.camBind(on)
	local MC = H.controller("MovementController")
	if MC and type(MC.SetZoomMax) == "function" then
		if not on then
			H.safe("zoom", MC.SetZoomMax, nil)
			return
		end
		-- the nudge: the max at 10 pulls the current zoom in at once, then the cap goes back up to 14
		H.safe("zoom", MC.SetZoomMax, K.ZOOM_NUDGE)
		task.delay(0.1, function()
			if S.Zoomed then
				H.safe("zoom", MC.SetZoomMax, K.ZOOM_RUN)
			end
		end)
	end
end

-- wave 6: the camera boxes of the pieces in my pocket (the hall, each Room_<n>'s corridor + room, the treasure: the
-- CamMin / CamMax attributes on the piece models), cached until a Run payload or a room added / removed
function R.camBoxes()
	if S.CamBoxes then
		return S.CamBoxes
	end
	local pocket = S.Pocket and S.Pocket.Parent and S.Pocket or nil
	if not pocket then
		return nil
	end
	local out = {}
	local function add(m)
		local a, b = m:GetAttribute("CamMin"), m:GetAttribute("CamMax")
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			out[#out + 1] = { Min = a, Max = b }
		end
	end
	for _, child in ipairs(pocket:GetChildren()) do
		if child:IsA("Model") then
			add(child)
			for _, piece in ipairs(child:GetChildren()) do
				if piece:IsA("Model") then
					add(piece)
				end
			end
		end
	end
	S.CamBoxes = out
	return out
end

local function camInBox(b, p)
	return p.X >= b.Min.X and p.X <= b.Max.X and p.Y >= b.Min.Y and p.Y <= b.Max.Y and p.Z >= b.Min.Z and p.Z <= b.Max.Z
end

-- where the ray F + boom * t (t >= 0) leaves box b shrunk by m (slab method; >= 0)
local function camExit(b, F, boom, m)
	local t = math.huge
	for _, axis in ipairs({ "X", "Y", "Z" }) do
		local v = boom[axis]
		if v > 1e-6 then
			t = math.min(t, (b.Max[axis] - m - F[axis]) / v)
		elseif v < -1e-6 then
			t = math.min(t, (b.Min[axis] + m - F[axis]) / v)
		end
	end
	return math.max(0, t)
end

-- every frame after the camera scripts: the boom cut where it leaves the boxes (same ray, so the view keeps its look)
function R.camClamp()
	local cam = Workspace.CurrentCamera
	if not cam or not S.Run or S.Walk or cam.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local boxes = R.camBoxes()
	if not boxes or #boxes == 0 then
		return
	end
	local cf = cam.CFrame
	local F = cam.Focus.Position
	local boom = cf.Position - F
	if boom.Magnitude < 1 then
		return -- first person
	end
	local box = nil
	for _, b in ipairs(boxes) do
		if camInBox(b, F) then
			box = b
			break
		end
	end
	if not box then
		return -- a teleport frame
	end
	local t = 1
	for hop = 1, 3 do
		local inner = camExit(box, F, boom, K.CAM_MARGIN)
		if inner >= 1 then
			t = 1
			break
		end
		-- through a doorway: the ray goes on in the box it enters
		local p = F + boom * math.min(1, camExit(box, F, boom, 0) + 0.02)
		local nextBox = nil
		if hop < 3 then
			for _, b in ipairs(boxes) do
				if b ~= box and camInBox(b, p) then
					nextBox = b
					break
				end
			end
		end
		if not nextBox then
			t = inner
			break
		end
		box = nextBox
	end
	if t < 1 then
		cam.CFrame = CFrame.new(F + boom * t) * (cf - cf.Position)
	end
end

function R.camBind(on)
	if on == S.CamBound then
		return
	end
	S.CamBound = on
	S.CamBoxes = nil
	pcall(function()
		if on then
			RunService:BindToRenderStep(K.CAM_BIND, H.renderPriority(1), function()
				H.safe("camera box", R.camClamp)
			end)
		else
			RunService:UnbindFromRenderStep(K.CAM_BIND)
		end
	end)
end

-- the pocket (workspace.Dungeons.Dungeon_<i>) the player stands in: the nearest holder within 400 studs
function R.findPocket()
	local folder = Workspace:FindFirstChild("Dungeons")
	local pos = H.rootPosition()
	if not folder or not pos then
		return nil
	end
	local best, bestD = nil, 400
	for _, holder in ipairs(folder:GetChildren()) do
		local at = H.positionOf(holder:FindFirstChild("Entrance_1") or holder:FindFirstChildWhichIsA("Model") or holder)
		if at then
			local d = (at - pos).Magnitude
			if d < bestD then
				best, bestD = holder, d
			end
		end
	end
	return best
end

function R.unwatchDoors()
	for _, conn in ipairs(S.Doors) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	S.Doors = {}
	S.Pocket = nil
	S.CamBoxes = nil
end

-- local copies of a door's bars sink into the floor (the server already switched the real bars off)
function R.slide(door)
	if typeof(door) ~= "Instance" then
		return
	end
	local n = 0
	for _, bar in ipairs(door:GetChildren()) do
		if bar.Name == "Bar" and bar:IsA("BasePart") and n < 8 then
			n = n + 1
			local ghost = Instance.new("Part")
			ghost.Name = "BarSlide"
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			ghost.Size = bar.Size
			ghost.CFrame = bar.CFrame
			ghost.Color = bar.Color
			ghost.Material = bar.Material
			ghost.Parent = Workspace
			H.tween(ghost, 0.7, { CFrame = bar.CFrame * CFrame.new(0, -bar.Size.Y, 0), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.8, function()
				ghost:Destroy()
			end)
		end
	end
end

function R.watchRoom(room)
	if not room:IsA("Model") then
		return
	end
	table.insert(S.Doors, room:GetAttributeChangedSignal("DoorOpen"):Connect(function()
		if room:GetAttribute("DoorOpen") == true then
			R.slide(room:FindFirstChild("Door_Exit"))
		end
	end))
	table.insert(S.Doors, room:GetAttributeChangedSignal("EntranceOpen"):Connect(function()
		if room:GetAttribute("EntranceOpen") == true then
			R.slide(room:FindFirstChild("Door_Entrance"))
		end
	end))
end

function R.watchDoors()
	if S.Pocket and S.Pocket.Parent then
		return
	end
	R.unwatchDoors()
	local pocket = R.findPocket()
	if not pocket then
		return
	end
	S.Pocket = pocket
	for _, room in ipairs(pocket:GetChildren()) do
		R.watchRoom(room)
	end
	table.insert(S.Doors, pocket.ChildAdded:Connect(function(child)
		R.watchRoom(child)
		S.CamBoxes = nil
	end))
	table.insert(S.Doors, pocket.ChildRemoved:Connect(function()
		S.CamBoxes = nil
	end))
	S.CamBoxes = nil
end

----------------------------------------------------------------------
-- Wave 5 helpers (bugs #15 / #26)
----------------------------------------------------------------------
function H.clientModule(name)
	H.Mods = H.Mods or {}
	if H.Mods[name] == nil then
		local inst = Client:FindFirstChild(name)
		local ok, mod = false, nil
		if inst then
			ok, mod = pcall(require, inst)
		end
		H.Mods[name] = (ok and type(mod) == "table") and mod or false
	end
	return H.Mods[name] or nil
end

function H.mc()
	if H.MC == nil then
		H.MC = H.controller("MovementController") or false
	end
	return H.MC or nil
end

function H.mcCall(fn, ...)
	local mc = H.mc()
	if mc and type(mc[fn]) == "function" then
		pcall(mc[fn], ...)
	end
end

function H.lowGfx()
	local gq = H.clientModule("GraphicsQuality")
	if gq and type(gq.Effective) == "function" then
		local ok, mode = pcall(gq.Effective)
		return ok and mode == "Low"
	end
	return false
end

function H.character()
	local char = LocalPlayer and LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and root:IsA("BasePart") then
		return char, hum, root
	end
	return nil
end

function H.renderPriority(extra)
	local ok, v = pcall(function()
		return Enum.RenderPriority.Camera.Value
	end)
	return (ok and v or 200) + extra
end

function H.smooth(p)
	return p * p * (3 - 2 * p)
end

function H.clamp01(v)
	return math.max(0, math.min(1, v))
end

-- a key / click / tap / button that skips a cinematic (not a mouse move, a stick, a focus change, sensors)
local SKIP_IGNORE = { MouseMovement = true, MouseWheel = true, Focus = true, TextInput = true, Gyro = true, Accelerometer = true, None = true, InputMethod = true }
local STICKS = { Thumbstick1 = true, Thumbstick2 = true }
function H.isSkipInput(input)
	if typeof(input) ~= "Instance" and type(input) ~= "table" and typeof(input) ~= "InputObject" then
		return false
	end
	local okT, t = pcall(function()
		return input.UserInputType.Name
	end)
	local okK, k = pcall(function()
		return input.KeyCode.Name
	end)
	if not okT or SKIP_IGNORE[t] then
		return false
	end
	if okK and STICKS[k] then
		return false
	end
	if okT and t:sub(1, 7) == "Gamepad" and (not okK or k == "Unknown") then
		return false
	end
	return true
end

function H.onSkipInput(input, processed)
	if not S.Walk and not S.Enter then
		return
	end
	if processed then
		return
	end
	if not H.isSkipInput(input) then
		return
	end
	if S.Walk then
		R.walkSkip()
	elseif S.Enter then
		R.enterSkip()
	end
end

----------------------------------------------------------------------
-- Wave 5 (bug #26): the room walk-in
----------------------------------------------------------------------
local SINK_KEYS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left,
	Enum.KeyCode.Right, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.KeyCode.Thumbstick1,
}

-- the movement keys during the walk-in: sunk (the character walks itself); a press skips
function R.walkSink(_name, state, input)
	if state == Enum.UserInputState.Begin then
		local okK, k = pcall(function()
			return input.KeyCode.Name
		end)
		if not (okK and STICKS[k]) then
			R.walkSkip()
		end
	end
	return Enum.ContextActionResult.Sink
end

function R.walkControls(off, w)
	if off then
		local ok, controls = pcall(function()
			local ps = LocalPlayer:FindFirstChild("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			if not pm then
				return nil
			end
			return require(pm):GetControls()
		end)
		if ok and type(controls) == "table" and type(controls.Disable) == "function" then
			if pcall(controls.Disable, controls) then
				w.Controls = controls
			end
		end
		w.Sunk = pcall(function()
			ContextActionService:BindActionAtPriority(K.WALK_ACTION, R.walkSink, false, Enum.ContextActionPriority.High.Value + 1, (table.unpack or unpack)(SINK_KEYS))
		end)
	else
		if w.Controls then
			pcall(w.Controls.Enable, w.Controls)
			w.Controls = nil
		end
		if w.Sunk then
			pcall(function()
				ContextActionService:UnbindAction(K.WALK_ACTION)
			end)
			w.Sunk = false
		end
	end
end

-- the camera of the walk-in at progress e (0..1): inside the room, in front of the walkers, looking back at them
function R.walkCam(w, e)
	local c = K.WALK_CAM
	local at = w.End + w.Inward * (c.Ahead + c.Pull * e) + w.Right * (c.Swing * math.sin(e * math.pi / 2) * w.Side) + Vector3.new(0, c.Up - c.Settle * e, 0)
	return CFrame.lookAt(at, w.Root.Position + Vector3.new(0, 1.2, 0))
end

-- wave 6: why a room payload played no walk-in (nil = it played): GetState().WalkSkip and the run gui's WalkSkip
-- attribute (readable in Studio's Explorer during a play test)
function R.walkSkipped(why)
	S.WalkSkip = why
	if U.RunGui then
		U.RunGui:SetAttribute("WalkSkip", why)
	end
end

-- the next room's Run payload arrived under the fade: set the shot up while the screen is still black
-- -> true, or false + why ("InMatch" | "NoCharacter" | "NoRoom" | "Inward")
function R.walkPrepare(room, key)
	if S.Walk then
		R.walkClear()
	end
	if H.inMatch() or not LocalPlayer then
		return false, "InMatch"
	end
	local char, hum, root = H.character()
	local camera = Workspace.CurrentCamera
	if not char or hum.Health <= 0 or not camera then
		return false, "NoCharacter"
	end
	local pocket = (S.Pocket and S.Pocket.Parent and S.Pocket) or R.findPocket()
	local model = pocket and pocket:FindFirstChild("Room_" .. tostring(room))
	local th = model and model:FindFirstChild("Threshold")
	if not th or not th:IsA("BasePart") then
		return false, "NoRoom"
	end
	local doorPos = H.positionOf(model:FindFirstChild("Door_Entrance")) or root.Position
	local d = th.Position - doorPos
	local inward = Vector3.new(d.X, 0, d.Z)
	if inward.Magnitude < 0.5 then
		d = th.Position - root.Position
		inward = Vector3.new(d.X, 0, d.Z)
	end
	if inward.Magnitude < 0.5 then
		return false, "Inward"
	end
	inward = inward.Unit
	local right = inward:Cross(Vector3.new(0, 1, 0))
	local fade = S.Fade
	local w = {
		Token = (S.WalkSeq or 0) + 1,
		Room = room,
		Key = key,
		Phase = "Hold",
		Th = th,
		Inward = inward,
		Right = right,
		Hum = hum,
		Root = root,
		CamOff = fade and fade.CamOff or (camera.CFrame.Position - root.Position),
		CamRot = fade and fade.CamRot or (camera.CFrame - camera.CFrame.Position),
		HardAt = os.clock() + K.FADE_SAFETY + K.WALK_SAFETY,
		T0 = os.clock(),
	}
	R.walkLane(w)
	S.WalkSeq = w.Token
	S.Walk = w
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = R.walkCam(w, 0)
	H.mcCall("SetFovOverride", K.WALK_CAM.Fov0)
	H.mcCall("SetCinematic", K.WALK_SPEED)
	R.walkControls(true, w)
	RunService:BindToRenderStep(K.WALK_BIND, H.renderPriority(2), function(dt)
		H.safe("walk step", R.walkStep, dt)
	end)
	R.refresh()
	-- the fade is already lifting (a late payload): go now
	if S.Fade == nil or S.Fade.Phase == "In" then
		R.walkGo()
	end
	return true
end

-- my lane across the doorway and the end point, from where the root stands NOW (the server's teleport into the room
-- and its Run payload are not ordered, so R.walkGo recomputes them as the fade lifts)
function R.walkLane(w)
	local th, root, right = w.Th, w.Root, w.Right
	local lane = math.max(-K.WALK_LANE, math.min(K.WALK_LANE, (root.Position - th.Position):Dot(right)))
	local base = Vector3.new(th.Position.X, root.Position.Y, th.Position.Z)
	w.Lane = lane
	w.Side = (lane >= 0) and -1 or 1 -- the swing goes to the far side of my lane: the party stays centred
	w.End = base + w.Inward * K.WALK_IN + right * lane
end

-- the fade lifts: the character walks in
function R.walkGo()
	local w = S.Walk
	if not w or w.Phase ~= "Hold" then
		return
	end
	if w.Th.Parent and w.Root.Parent then
		R.walkLane(w)
	end
	w.Phase = "Walk"
	w.T0 = os.clock()
	w.HardAt = w.T0 + K.WALK_SAFETY
	w.NextMove = w.T0 + K.WALK_REISSUE
	pcall(function()
		w.Hum:MoveTo(w.End)
	end)
end

function R.walkStep(_dt)
	local w = S.Walk
	if not w then
		pcall(function()
			RunService:UnbindFromRenderStep(K.WALK_BIND)
		end)
		return
	end
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	if now >= w.HardAt or not camera or not w.Root.Parent or not w.Hum.Parent then
		return R.walkClear()
	end
	if w.Phase == "Hold" or w.Phase == "Walk" then
		local p, e = 0, 0
		if w.Phase == "Walk" then
			p = H.clamp01((now - w.T0) / K.WALK_SECONDS)
			e = H.smooth(p)
		end
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		camera.CFrame = R.walkCam(w, e)
		local c = K.WALK_CAM
		H.mcCall("SetFovOverride", c.Fov0 + (c.Fov1 - c.Fov0) * e)
		if w.Phase == "Walk" then
			if now >= w.NextMove then
				w.NextMove = now + K.WALK_REISSUE
				pcall(function()
					w.Hum:MoveTo(w.End)
				end)
			end
			local rp = w.Root.Position
			local flat = Vector3.new(rp.X - w.End.X, 0, rp.Z - w.End.Z).Magnitude
			if flat < K.WALK_REACH or p >= 1 or (w.ReleaseBy and now >= w.ReleaseBy) then
				R.walkRelease()
			end
		end
	elseif w.Phase == "Blend" then
		local q = H.clamp01((now - w.T0) / w.Dur)
		local s = H.smooth(q)
		local target = CFrame.new(w.Root.Position + w.CamOff) * w.CamRot
		camera.CFrame = w.From:Lerp(target, s)
		H.mcCall("SetFovOverride", w.FromFov + (K.WALK_CAM.Fov1 - w.FromFov) * s)
		if q >= 1 then
			R.walkClear()
		end
	end
end

-- control comes back now; the camera blends to where it was at the door over `dur`
function R.walkRelease(dur)
	local w = S.Walk
	if not w or w.Phase == "Blend" then
		return
	end
	local camera = Workspace.CurrentCamera
	w.Phase = "Blend"
	w.T0 = os.clock()
	w.Dur = dur or K.WALK_BLEND
	w.From = camera and camera.CFrame or CFrame.new()
	w.FromFov = camera and camera.FieldOfView or K.WALK_CAM.Fov1
	w.HardAt = w.T0 + w.Dur + 1
	H.mcCall("SetCinematic", nil)
	R.walkControls(false, w)
	R.refresh()
end

-- any key / click / tap: at the Threshold at once (the server sees the crossing on its next tick)
function R.walkSkip()
	local w = S.Walk
	if not w or w.Phase == "Blend" then
		return
	end
	local char = LocalPlayer and LocalPlayer.Character
	if char and w.Root.Parent then
		local at = Vector3.new(w.End.X, w.Root.Position.Y, w.End.Z)
		pcall(function()
			char:PivotTo(CFrame.lookAt(at, at + w.Inward))
		end)
	end
	R.walkRelease(K.WALK_SKIP_BLEND)
end

-- the fight began (someone crossed the line): the walk-in hands control back within WALK_FIGHT_GRACE
function R.walkFight()
	local w = S.Walk
	if not w then
		return
	end
	if w.Phase == "Hold" then
		return R.walkClear()
	end
	if w.Phase == "Walk" then
		local by = os.clock() + K.WALK_FIGHT_GRACE
		w.ReleaseBy = math.min(w.ReleaseBy or by, by)
	end
end

-- every exit path (idempotent): the camera back to Custom, the FOV and the controls back, nothing bound
function R.walkClear()
	local w = S.Walk
	if not w then
		return
	end
	S.Walk = nil
	pcall(function()
		RunService:UnbindFromRenderStep(K.WALK_BIND)
	end)
	H.mcCall("SetFovOverride", nil)
	H.mcCall("SetCinematic", nil)
	R.walkControls(false, w)
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
	R.refresh()
end

-- the light loop's safety net (a lost RenderStep never leaves the camera Scriptable)
function R.walkTick()
	local w = S.Walk
	if w and os.clock() >= w.HardAt then
		R.walkClear()
	end
	local e = S.Enter
	if e and os.clock() >= e.HardAt + 2 then
		R.enterClear()
	end
end

----------------------------------------------------------------------
-- Wave 5 (bug #15): the voxel-shatter entrance and the dungeon shoulder camera
----------------------------------------------------------------------
-- the Dungeon gate (GateId "Dungeon"; its PrimaryPart GlowCore is the vortex centre). Looked up in the known places
-- only (the Gate Court folder NimbusLobby/Gates, PortalFxController's tracked gates, Workspace's own children), never
-- with a Workspace:GetDescendants() walk (a hitch on a big plaza at the worst moment)
function R.dungeonGate()
	local g = S.Gate
	if g and g.Parent then
		return g
	end
	S.Gate = nil
	local function isGate(d)
		return typeof(d) == "Instance" and d:IsA("Model") and d:GetAttribute("GateId") == "Dungeon"
	end
	local lobby = Workspace:FindFirstChild("NimbusLobby")
	local folder = lobby and lobby:FindFirstChild("Gates")
	for _, d in ipairs(folder and folder:GetChildren() or {}) do
		if isGate(d) then
			S.Gate = d
			return d
		end
	end
	local pfx = H.controller("PortalFxController")
	if pfx and type(pfx.FindGate) == "function" then
		local ok, d = pcall(pfx.FindGate, "Dungeon")
		if ok and isGate(d) and d:IsDescendantOf(Workspace) then
			S.Gate = d
			return d
		end
	end
	for _, d in ipairs(Workspace:GetChildren()) do
		if isGate(d) then
			S.Gate = d
			return d
		end
	end
	return nil
end

function R.enterGrid(low)
	local vp = H.viewport()
	local portrait = vp.Y > vp.X
	local g = K.ENTER_GRID
	local pick = low and (portrait and g.LowPortrait or g.Low) or (portrait and g.Portrait or g.Desktop)
	return pick[1], pick[2]
end

-- the block grid (built once per grid size)
function R.buildEnter(cols, rows)
	if not U.EnterGui then
		local gui = CloudUI.NewScreenGui("NimbusDungeonEnter", K.ENTER_ORDER)
		gui.IgnoreGuiInset = true
		gui.Enabled = false
		U.EnterGui = gui
		U.EnterGrid = H.frame(gui, "Grid", { Size = UDim2.fromScale(1, 1), ZIndex = 10 })
	end
	if U.EnterCols == cols and U.EnterRows == rows and U.EnterCells then
		return
	end
	H.clear(U.EnterGrid)
	U.EnterCells = {}
	U.EnterCols, U.EnterRows = cols, rows
	local maxD = math.sqrt((cols / 2) ^ 2 + (rows / 2) ^ 2)
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local x, y = (c + 0.5) / cols, (r + 0.5) / rows
			local f = Util.Create("Frame", {
				Name = "Cell",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, y),
				Size = UDim2.fromScale(0, 0),
				BorderSizePixel = 0,
				BackgroundTransparency = 0,
				ZIndex = 10,
				Parent = U.EnterGrid,
			})
			local stroke = H.stroke(f, INK, 1, 0)
			local dx, dy = c + 0.5 - cols / 2, r + 0.5 - rows / 2
			local hash = (c * 7 + r * 13 + c * r * 3) % 17
			U.EnterCells[#U.EnterCells + 1] = {
				F = f, Stroke = stroke, X = x, Y = y, W = 1 / cols, H = 1 / rows,
				Dist = math.sqrt(dx * dx + dy * dy) / maxD,
				Hash = hash,
				Jitter = (hash % 9) / 8 * K.ENTER_JITTER,
				Rot = ((hash % 2 == 0) and 1 or -1) * (8 + hash % 12),
				Shade = (hash % 7) * 0.025 - 0.075,
			}
		end
	end
end

function R.enterColour(element)
	local base = H.elementColor(element) or C.Accent
	for _, cell in ipairs(U.EnterCells or {}) do
		local col = (cell.Shade >= 0) and Theme.Lighten(base, cell.Shade) or base:Lerp(Color3.new(0, 0, 0), -cell.Shade)
		cell.F.BackgroundColor3 = col
		cell.Stroke.Color = col:Lerp(Color3.new(0, 0, 0), 0.25)
	end
end

function R.enterResetCells()
	for _, cell in ipairs(U.EnterCells or {}) do
		cell.F.Size = UDim2.fromScale(0, 0)
		cell.F.Position = UDim2.fromScale(cell.X, cell.Y)
		cell.F.Rotation = 0
		cell.F.BackgroundTransparency = 0
		cell.S, cell.Ty = nil, nil
	end
end

local function backOut(k)
	local c1 = 1.70158
	local c3 = c1 + 1
	local m = k - 1
	return 1 + c3 * m * m * m + c1 * m * m
end

-- DungeonState "Enter": the rush + the blocks; the server teleports the party after Cover
function R.enter(payload)
	if S.Run or H.inMatch() then
		return
	end
	if S.Enter then
		R.enterClear()
	end
	local function secs(v, default)
		v = tonumber(v)
		if not v or v ~= v then
			return default
		end
		return math.max(0.1, math.min(2, v))
	end
	local low = H.lowGfx()
	local cols, rows = R.enterGrid(low)
	R.buildEnter(cols, rows)
	R.enterResetCells()
	R.enterColour(payload.Element)
	local now = os.clock()
	local e = {
		Token = (S.EnterSeq or 0) + 1,
		Phase = "Cover",
		Cover = secs(payload.Cover, 0.55),
		Reveal = secs(payload.Reveal, 0.9),
		At = now,
		HardAt = now + K.ENTER_SAFETY,
		Low = low,
		Lead = 0,
	}
	S.EnterSeq = e.Token
	local camera = Workspace.CurrentCamera
	local gate = R.dungeonGate()
	local core = gate and gate.PrimaryPart
	if camera and core and (camera.CFrame.Position - core.Position).Magnitude > K.ENTER_RUSH_MAX then
		core = nil -- the camera is far from the gate (a member who wandered off): no flight across the plaza
	end
	if camera and core then
		local cp = core.Position
		local lv = core.CFrame.LookVector
		local sign = ((camera.CFrame.Position - cp):Dot(lv) >= 0) and 1 or -1
		local target = cp + lv * sign
		e.Rush = { From = camera.CFrame, To = CFrame.lookAt(target, cp), Fov = camera.FieldOfView }
		e.Phase = "Rush"
		e.Lead = K.ENTER_LEAD
		camera.CameraType = Enum.CameraType.Scriptable
		local pfx = H.controller("PortalFxController")
		if pfx and type(pfx.Flare) == "function" then
			pcall(pfx.Flare, gate, 0.6)
		end
		local sfx = H.clientModule("SoundFx")
		if sfx and type(sfx.Play) == "function" then
			pcall(sfx.Play, "Whoosh")
		end
	end
	S.Enter = e
	U.EnterGui.Enabled = true
	RunService:BindToRenderStep(K.ENTER_BIND, H.renderPriority(3), function(dt)
		H.safe("enter step", R.enterStep, dt)
	end)
end

function R.enterStep(_dt)
	local e = S.Enter
	if not e then
		pcall(function()
			RunService:UnbindFromRenderStep(K.ENTER_BIND)
		end)
		return
	end
	local now = os.clock()
	local t = now - e.At
	if e.Phase == "Rush" or e.Phase == "Cover" then
		if now >= e.HardAt then
			return R.enterClear()
		end
		local camera = Workspace.CurrentCamera
		if e.Rush and camera then
			local p = H.clamp01(t / K.ENTER_RUSH)
			local q = p * p
			camera.CFrame = e.Rush.From:Lerp(e.Rush.To, q)
			H.mcCall("SetFovOverride", e.Rush.Fov + (K.ENTER_RUSH_FOV - e.Rush.Fov) * q)
			if p >= 1 then
				e.Phase = "Cover"
			end
		end
		local span = math.max(0, e.Cover - K.ENTER_MARGIN - e.Lead - K.ENTER_POP) -- full by Cover - ENTER_MARGIN
		for _, cell in ipairs(U.EnterCells) do
			local k = H.clamp01((t - (e.Lead + span * cell.Dist)) / K.ENTER_POP)
			local s = (k >= 1) and 1 or backOut(k)
			if s ~= cell.S then
				cell.S = s
				cell.F.Size = UDim2.new(cell.W * s, 2, cell.H * s, 2)
			end
		end
		if t >= e.Cover then
			R.enterSnapCover()
		end
	elseif e.Phase == "Hold" then
		if e.RunSeen then
			R.enterReveal()
		elseif now >= e.HardAt then
			-- no run came (refused / ended during the cover): reveal anyway
			R.enterReveal()
		end
	elseif e.Phase == "Reveal" then
		local tr = now - e.RevealAt
		local spread = math.max(0, e.Reveal - K.ENTER_HOP - K.ENTER_FALL - K.ENTER_JITTER)
		for _, cell in ipairs(U.EnterCells) do
			local tau = tr - (spread * cell.Dist + cell.Jitter)
			local y, q = 0, 0
			if tau > 0 then
				if tau < K.ENTER_HOP then
					y = -0.06 * math.sin(tau / K.ENTER_HOP * math.pi / 2)
				else
					q = H.clamp01((tau - K.ENTER_HOP) / K.ENTER_FALL)
					y = -0.06 + 1.36 * q * q
				end
			end
			if y ~= cell.Ty then
				cell.Ty = y
				cell.F.Position = UDim2.fromScale(cell.X, cell.Y + y)
				if not e.Low then
					cell.F.Rotation = cell.Rot * q
					cell.F.BackgroundTransparency = 0.35 * q
				end
			end
		end
		if tr >= e.Reveal or now >= e.HardAt then
			R.enterClear()
		end
	end
end

-- every block full; the camera back to normal under them (the teleport is about to happen / happened)
function R.enterSnapCover()
	local e = S.Enter
	if not e or (e.Phase ~= "Rush" and e.Phase ~= "Cover") then
		return
	end
	for _, cell in ipairs(U.EnterCells or {}) do
		cell.S = 1
		cell.F.Size = UDim2.new(cell.W, 2, cell.H, 2)
	end
	R.enterCamera(e)
	e.Phase = "Hold"
	if e.RunSeen then
		R.enterReveal()
	end
end

function R.enterCamera(e)
	if e.Rush and not e.CameraBack then
		e.CameraBack = true
		H.mcCall("SetFovOverride", nil)
		local camera = Workspace.CurrentCamera
		if camera and camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end

-- the run's first Run payload (the party stands in the hall): the blocks hop and fall away
function R.enterReveal()
	local e = S.Enter
	if not e or e.Phase == "Reveal" then
		return
	end
	if e.Phase == "Rush" or e.Phase == "Cover" then
		e.RunSeen = true
		return -- (the cover finishes first: the teleport is under it)
	end
	e.Phase = "Reveal"
	e.RevealAt = os.clock()
	e.HardAt = e.RevealAt + e.Reveal + 0.5
end

function R.enterSkip()
	local e = S.Enter
	if not e then
		return
	end
	if e.Phase == "Rush" or e.Phase == "Cover" then
		R.enterSnapCover()
	elseif e.Phase == "Reveal" then
		R.enterClear()
	end
end

-- every exit path (idempotent): nothing bound, the camera and the FOV back, the blocks hidden and reset
function R.enterClear()
	local e = S.Enter
	if not e then
		return
	end
	S.Enter = nil
	pcall(function()
		RunService:UnbindFromRenderStep(K.ENTER_BIND)
	end)
	R.enterCamera(e)
	if U.EnterGui then
		U.EnterGui.Enabled = false
	end
	R.enterResetCells()
end

-- the dungeon shoulder: Humanoid.CameraOffset while in a run (re-applied to a new character), zero outside
function R.shoulder()
	local _, hum = H.character()
	if S.Run and hum then
		if S.ShoulderHum ~= hum then
			S.ShoulderHum = hum
			hum.CameraOffset = K.DUNGEON_SHOULDER
		end
	elseif S.ShoulderHum then
		local old = S.ShoulderHum
		S.ShoulderHum = nil
		if old.Parent then
			old.CameraOffset = Vector3.new(0, 0, 0)
		end
	end
end

----------------------------------------------------------------------
-- Server messages
----------------------------------------------------------------------
function R.onState(kind, payload)
	if type(payload) ~= "table" then
		return
	end
	if kind == "Lobby" then
		S.Lobby = payload
		S.LobbyAt = os.clock()
		S.ReadyWant = nil -- the server's word wins (the optimistic READY is reverted or confirmed here)
		S.PartySig = nil
		if type(payload.Mine) == "table" and tonumber(payload.Mine.Floor) then
			S.Floor = math.floor(payload.Mine.Floor)
		end
		W.refresh()
		R.refresh()
	elseif kind == "Run" then
		local fresh = S.Run == nil or S.Run.RunId ~= payload.RunId
		local key = tostring(payload.State) .. ":" .. tostring(payload.Phase) .. ":" .. tostring(payload.Room)
		local newKey = key ~= S.PhaseKey
		if fresh then
			S.Totals = { Cash = 0, Tokens = 0, Xp = 0, Gems = 0 }
			S.ChestOpened = false
			S.End = nil
			S.LeaveArmed = 0
			S.MemberSig = nil
			R.unwatchDoors()
		end
		if key ~= S.PhaseKey then
			S.PhaseKey = key
			S.PhaseAt = os.clock()
		end
		S.Run = payload
		S.RunAt = os.clock()
		S.CamBoxes = nil
		-- wave 5 (bug #15): the run's first payload lifts the entrance blocks
		if fresh and S.Enter then
			R.enterReveal()
		end
		-- wave 5 (bug #26): the next room arrived under the fade: the walk-in (set up while black); another phase ends it
		local room = tonumber(payload.Room) or 0
		if S.Walk and key ~= S.Walk.Key then
			if payload.State == "Fight" and not fresh then
				R.walkFight()
			else
				R.walkClear()
			end
		end
		local threshold = payload.State == "Corridor" and payload.Phase == "Threshold" and room >= 1 and room <= 4
		if not S.Walk and S.Fade and (S.Fade.Phase == "Out" or S.Fade.Phase == "Hold") and key ~= S.Fade.Key and threshold then
			local okP, prepared, why = pcall(R.walkPrepare, room, key)
			if not okP then
				H.warnOnce("walk prepare", prepared)
			end
			R.walkSkipped(okP and not prepared and (why or "NoRoom") or (not okP and "Error") or nil)
		elseif threshold and newKey and not S.Walk then
			R.walkSkipped(S.Fade and "FadeIn" or "NoFade")
		end
		-- the next room arrived while the screen holds black: fade back in
		if S.Fade and S.Fade.Phase == "Hold" and key ~= S.Fade.Key then
			R.fadeIn()
		end
		if S.Open then
			DungeonController.Close()
		end
		R.light(true)
		R.zoom(true)
		H.safe("doors", R.watchDoors)
		H.safe("chests", R.lockChests)
		H.safe("shoulder", R.shoulder)
		R.refresh()
	elseif kind == "Enter" then
		H.safe("enter", R.enter, payload)
	elseif kind == "Loot" then
		S.Loot = payload
		local t = S.Totals
		t.Cash = t.Cash + (tonumber(payload.Cash) or 0)
		t.Tokens = t.Tokens + (tonumber(payload.Tokens) or 0)
		t.Xp = t.Xp + (tonumber(payload.Xp) or 0)
		local text
		if payload.Loss then
			text = "A third of the XP for trying: +" .. H.commas(payload.Xp) .. " XP"
		else
			local room = tonumber(payload.Room) or 1
			text = ((room >= 4) and "Boss beaten!" or ("Room " .. room .. " cleared!")) .. " +$" .. H.commas(payload.Cash) .. " +" .. H.commas(payload.Tokens) .. " tokens +"
				.. H.commas(payload.Xp) .. " XP"
			if (tonumber(payload.LevelUps) or 0) > 0 then
				text = text .. " (" .. math.floor(payload.LevelUps) .. " level up!)"
			end
		end
		R.toast(text, payload.Loss and C.Blue or C.Gold, nil, "+$" .. H.commas(payload.Cash) .. " +" .. H.commas(payload.Tokens) .. G.Cloud .. " +" .. H.commas(payload.Xp) .. "XP")
		if not payload.Loss then
			R.sound("Reward")
		end
	elseif kind == "Chest" then
		local amount = tonumber(payload.Amount) or 0
		local kindName = tostring(payload.Kind)
		if kindName == "Gems" then
			S.Totals.Gems = S.Totals.Gems + amount
		elseif kindName == "Tokens" then
			S.Totals.Tokens = S.Totals.Tokens + amount
		elseif kindName == "Cash" then
			S.Totals.Cash = S.Totals.Cash + amount
		end
		S.ChestOpened = true
		H.safe("chests", R.lockChests)
		local label = (kindName == "Cash") and ("$" .. H.commas(amount)) or (H.commas(amount) .. " " .. (kindName == "Gems" and "Gems" or "tokens"))
		R.toast(G.Chest .. " Chest: +" .. label .. "!", (kindName == "Gems") and C.Gem or C.Gold, nil, G.Chest .. " +" .. label)
		R.sound("Reward")
	elseif kind == "Fade" then
		if S.Run then
			R.fade(payload)
		end
	elseif kind == "End" then
		S.End = payload
		S.EndAt = os.clock()
		S.Run = nil
		S.PhaseKey = nil
		S.LeaveArmed = 0
		S.Toast = nil
		H.safe("walk clear", R.walkClear)
		H.safe("enter clear", R.enterClear)
		R.clearFade()
		R.light(false)
		R.zoom(false)
		R.unwatchDoors()
		H.safe("shoulder", R.shoulder)
		R.refresh()
	end
end

-- a run that vanished without an End (InBattle released, the pocket left): clean up and restore the light
function R.check()
	if S.Run and not H.runAttr() and os.clock() - S.RunAt > 3 then
		S.Run = nil
		S.PhaseKey = nil
		H.safe("walk clear", R.walkClear)
		H.safe("enter clear", R.enterClear)
		H.safe("shoulder", R.shoulder)
		R.clearFade()
		R.unwatchDoors()
		R.light(false)
		R.zoom(false)
		R.refresh()
	elseif (S.Lit or S.Zoomed) and not S.Run and not H.runAttr() then
		R.light(false)
		R.zoom(false)
	end
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function H.connectOthers()
	local function hook(name, signalName)
		local mod = H.controller(name)
		local signal = mod and mod[signalName]
		if type(signal) == "table" and type(signal.Connect) == "function" then
			signal:Connect(function(windowId)
				if name == "DungeonController" or windowId == "Dungeon" then
					return
				end
				DungeonController.Close()
			end)
		end
	end
	hook("MenuController", "WindowOpened")
	hook("IndexController", "Opened")
	hook("FusionController", "Opened")
	hook("CareController", "Opened")
	hook("ArenaController", "Opened")
	hook("ObbyController", "Opened")
end

function DungeonController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)
	U.Gui = CloudUI.NewScreenGui("NimbusDungeon", K.DISPLAY_ORDER)
	R.build()
	R.buildFade()
	R.refresh()
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		H.safe("relayout", function()
			S.PartySig = nil
			W.refresh()
			R.refresh()
		end)
	end)
	State.Changed:Connect(function()
		H.safe("State.Changed", W.refresh)
	end)
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal(Config.Attr.InMatch):Connect(function()
			if H.inMatch() then
				DungeonController.Close()
			end
			H.safe("InMatch", R.refresh)
		end)
		LocalPlayer:GetAttributeChangedSignal((Config.Attr and Config.Attr.InBattle) or "InBattle"):Connect(function()
			-- wave 5: out of the run (released): no cinematic may stay on
			if not H.runAttr() then
				H.safe("walk clear", R.walkClear)
				H.safe("enter clear", R.enterClear)
			end
			task.delay(3.2, function()
				H.safe("InBattle", R.check)
			end)
		end)
		LocalPlayer.CharacterRemoving:Connect(function()
			H.safe("walk clear", R.walkClear) -- (death / respawn: the walk-in ends with the character)
		end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		H.safe("skip", H.onSkipInput, input, processed)
	end)
	UserInputService.InputBegan:Connect(function(input)
		if S.Open and input.KeyCode == Enum.KeyCode.Escape then
			DungeonController.Close()
		end
	end)
	task.spawn(function()
		local okState, stateRemote = pcall(Remotes.Get, "DungeonState")
		if okState and stateRemote then
			stateRemote.OnClientEvent:Connect(function(kind, payload)
				H.safe("DungeonState " .. tostring(kind), R.onState, kind, payload)
			end)
		end
		local okOpen, openRemote = pcall(Remotes.Get, "OpenPanel")
		if okOpen and openRemote then
			openRemote.OnClientEvent:Connect(function(panelId, args)
				if type(panelId) == "string" and panelId:lower() == "dungeon" then
					args = type(args) == "table" and args or {}
					H.safe("OpenPanel", DungeonController.Open, args.Floor)
				end
			end)
		end
	end)
	task.defer(function()
		H.safe("hooks", H.connectOthers)
	end)
	-- one light loop: countdowns, phase clocks, the toasts, walk-away (4 times a second)
	local nextTick = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextTick then
			return
		end
		nextTick = now + K.TICK
		if S.Open and S.AtPortal then
			local pos, at = H.rootPosition(), H.positionOf(S.AtPortal)
			if pos and at and (Vector3.new(pos.X - at.X, 0, pos.Z - at.Z)).Magnitude > K.WALK_AWAY then
				DungeonController.Close()
				return
			end
		end
		if S.Open then
			H.safe("tick window", W.refresh)
		end
		H.safe("tick fade", R.fadeTick)
		H.safe("tick walk", R.walkTick)
		H.safe("tick shoulder", R.shoulder)
		H.safe("tick card", R.refresh)
		if S.Zoomed and not S.Run then
			H.safe("tick zoom", R.zoom, false) -- every exit path: no run, no zoom cap
		end
	end)
end

-- TESTS ONLY (smoke_bug5_dungeon client_bug5dgn_mood): the tier mood reader, the preset it never goes below, the retry
DungeonController._Mood = { Read = R.mood, Preset = PRESET, Tries = K.MOOD_TRIES, Retry = K.MOOD_RETRY }

return DungeonController
