-- BattleController (client, Phase 3, battleclient): draws every pet battle the server simulates and gives the local
-- player the battle controls (ARCHITECTURE_V3.md "Phase 3: Pet battles", "Phase 3 build contract", "Interfaces between
-- the Phase 3 modules"). The server simulates, the clients draw: nothing here is authoritative. Battle units are built
-- locally (PetBuilder for pets with their keys / looks, BossBuilder for raid bosses) and animated between the server's
-- 10 Hz snapshots (Replication rule).
--
-- API
--   BattleController.Init()                 connects BattleState, the frame loop and the input (once)
--   BattleController.Stop()                 tears everything down (tests / hot reload)
--   BattleController.HandleState(kind, payload, battleId)   what the BattleState remote does (tests / dump_gui)
--   BattleController.Command(action, arg) -> bool   sends BattleCommand ("Attack" (unitId|nil), "Retreat",
--                                           "Special" (slot), "Forfeit") with a local throttle; false when refused here
--   BattleController.Focus(unitId)          focus an enemy (= Command("Attack", unitId)); nil clears the focus
--   BattleController.GetBattle() -> { Id, Mode, Side, Spectator, Fighter, Ended, Units = n, Models = n, Focus,
--                                     Order, Hud = bool, Layout = "Wide" | "Compact" } | nil
--   BattleController.GetUnit(id) -> { Id, Side, Kind, Name, Hp, MaxHp, State, Meter, Model, X, Z, World (Vector3) } | nil
--   BattleController.GetStats() -> { Frames, AvgMs, PeakMs, LastMs, Units, Models, FxParts, Numbers, Flashes,
--                                     Telegraphs, Builds }  (cost of the frame loop, measured with os.clock, or with
--                                     BattleController.PerfClock when a test sets one; ResetStats() starts over)
--   BattleController.IsHudVisible() -> bool
--   BattleController.ScreenPick(x, y) -> unitId | nil   the enemy a tap / click at viewport pixel (x, y) would focus
--
-- Messages (BattleState(kind, payload, battleId), sent by BattleService)
--   "Start"    battle:Describe() + Zone = { CFrame (floor centre), Size, X, Z } + Names + Side (0 = spectator) + Spectator
--              + T (+ Trial = { Level, Name, Chapter, MiniBoss }). A second "Start" for the same battle (a raid
--              spectator who joins) refreshes the units and the controls without rebuilding the models it keeps.
--   "Snapshot" { BattleId, T, Units = dense array [id] = { x, z, hp, state, target?, meter, shield? } }
--   "Events"   a list of BattleSim events (Hit, Special, KO, Telegraph, Spawn, Enrage, Order, Zone, Leave, End)
--   "End"      { BattleId, Mode, Result, Rewards, Outcome, Won, Spectator, Reason }
--
-- Drawing
--   * Snapshots are buffered and drawn INTERP_DELAY seconds behind the estimated server clock (smooth at 10 Hz,
--     no extrapolation overshoot); events are queued with their arrival time and played on that same delayed clock,
--     so lunges, numbers and telegraph impacts line up with the positions.
--   * Pets hover over the floor (zone-local x / z from the zone CFrame), face their target or their path, bob, flap
--     (PetBuilder.Animate), lunge on melee hits, recoil and shoot voxel bolts on ranged hits, hop on a Pounce. Static
--     parts are welded to the anchored root once per build, so a pose is one root CFrame write (like PetController).
--     Your own pets are built at High detail, everyone else's at Low; builds run under a per-frame time budget.
--   * The raid boss: BossBuilder model + BossBuilder.Animate poses (Idle, Windup during a telegraph, Attack at the hit,
--     Basic on its plain attacks, Enrage, Down) facing its target; SetEnraged on the Enrage event.
--   * Hit flashes (a pooled Highlight per hit victim), floating damage numbers (pooled pixel-sized BillboardGuis
--     above the victim in the world, never a screen-centre overlay: crits bigger and gold, strong / weak element hits
--     tinted, shield blocks light blue, heals green), KO poofs (voxel bursts; the downed pet is parked until the fight
--     ends), special callouts above the caster, and VFX per Special.Kind in the special's / element's colour: Blast
--     (voxel shock ring + burst), Heal (rising voxel sparks), Shield (a translucent force-field cube on every shielded
--     ally while the snapshot reports a shield), Storm (a voxel storm cloud with lightning over its zone), Pounce
--     (a dash trail + hop), Freeze (ice crystals on every stunned unit), Beam (a long neon beam).
--   * Boss telegraphs: a glowing floor circle / line in BossBuilder.TelegraphColor that FILLS UP until the hit, then
--     flashes; lingering pools (Zone "Linger") glow for their seconds.
--   * Small HP bars (pixel BillboardGuis, no text) above every unit: green = yours, blue = allies, red = enemies; a
--     bobbing voxel arrow marks the enemy your team focuses.
--   * Spectators (a player near a duel ring / the raid floor) see the same battle from the stands, with only a slim
--     top card (no controls).
--
-- The battle HUD (only while the local player fights; ScreenGui "NimbusBattle", designed in 1080p pixels under one
-- UIScale of Theme.ScreenFactor()): never in the screen centre.
--   * Top card (top centre, under the Roblox bar): the mode, the opponent / trial / boss, the time left; the boss HP
--     bar with its element and ENRAGED / minion pills in raids; one chip per enemy (name, element stripe, HP) in trials
--     and duels: tap / click a chip to focus that enemy.
--   * Team card (bottom right on wide screens): one row per team pet: slot key, name, level, element badge, HP bar,
--     special meter, and its SPECIAL button (lights up gold and pulses when the meter is full, shows KO when down).
--   * ATTACK / RETREAT above it (key hints F / R; gamepad X / Y; specials 1-4, gamepad LB / RB / LT / RT). ATTACK
--     shows the regroup countdown after a RETREAT. The header names the focused enemy (tap it to clear the focus).
--   * Compact layout (touch screens and small windows): the team as a row of cards under the top card (tap a card =
--     its special), ATTACK / RETREAT as big touch buttons at the right edge, clear of the RUN / DASH buttons.
--   * Tap / click an enemy in the world to focus it (a short tap that is not a camera drag; the nearest enemy on the
--     screen within reach of the tap).
--   * Result card at the end (bottom right, or at the top in the compact layout; never centred): VICTORY / DEFEAT /
--     DRAW, the reason, the rewards (tokens, gems, trophies, XP, first clear, raid tier + damage share, event pet,
--     level-ups, double rewards), OK; it closes by itself after RESULT_SECONDS.
-- Keys 1-4 are bound through ContextActionService only while you fight (High priority, sunk), so the item hotbar does
-- not also fire them; they are released when the battle ends.
--
-- Cost: one RenderStepped connection, alive only while a battle is drawn or effects play. Per frame: one root CFrame
-- write + PetBuilder.Animate per visible pet (other players' / enemy pets are drawn every 2nd frame in a crowd, every
-- 3rd beyond ANIM_MID studs from the camera, every 4th beyond ANIM_FAR; your own pets every frame), one
-- BossBuilder.Animate, the live effect parts (pooled, capped at MAX_FX_PARTS), the live numbers (capped) and HUD
-- writes only when a shown value changes. GetStats() reports the measured milliseconds.
-- Plain Lua 5.1-compatible syntax only. Every font comes from a Theme role. No asset ids.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local Client = script.Parent.Parent

-- optional modules (a build without one still draws what it can)
local function optional(parent, name, waitSeconds)
	if not parent then
		return nil
	end
	local inst = parent:FindFirstChild(name)
	if not inst and waitSeconds then
		inst = parent:WaitForChild(name, waitSeconds)
	end
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	warn("[BattleController] " .. name .. " failed to load: " .. tostring(result))
	return nil
end

local CloudUI = optional(Client:FindFirstChild("UI") or Client:WaitForChild("UI", 10), "CloudUI", 10)
local PetBuilder = optional(Shared, "PetBuilder", 5)
local PetCatalog = optional(Shared, "PetCatalog", 5)
local PetKeys = optional(Shared, "PetKeys")
local BattleCatalog = optional(Shared, "BattleCatalog")
local BattleSim = optional(Shared, "BattleSim") -- constants only (States / Events); the client never simulates
local BossBuilder = nil -- loaded on the first raid (lazyBoss)

local BattleController = {}

local LocalPlayer = Players.LocalPlayer
local sin, cos, sqrt, abs, floor, max, min, exp, pi = math.sin, math.cos, math.sqrt, math.abs, math.floor, math.max, math.min, math.exp, math.pi
local atan2 = math.atan2 or function(y, x)
	return math.atan(y, x)
end
local TAU = pi * 2

----------------------------------------------------------------------
-- Tuning
----------------------------------------------------------------------
local K = {
	GUI_NAME = "NimbusBattle",
	DISPLAY_ORDER = 12, -- above the HUD (10) and the hotbar (11), below windows (20) and toasts (30)
	FOLDER = "ClientBattle", -- workspace folder of the drawn battles
	INTERP_DELAY = 0.12, -- seconds behind the server clock (snapshots arrive every 0.1 s)
	OFFSET_RATE = 0.1, -- clock offset filter
	MAX_SNAPS = 8,
	PET_SCALE = 1.3, -- battle pets are a little bigger than followers, so they read from the stands
	HOVER = 0.55, -- studs between the floor and a pet's lowest point
	BOB = 0.18,
	FACE_RATE = 10,
	LUNGE_TIME = 0.26,
	LUNGE_DIST = 1.5,
	RECOIL_DIST = 0.35,
	HOP_TIME = 0.4,
	HOP_HEIGHT = 2.6,
	KO_PARK = 0.3, -- seconds after a KO before the downed pet is parked (the poof covers it)
	BUILD_BUDGET = 0.006, -- seconds of model building per frame (the first build of a frame always runs)
	BUILD_MAX = 4,
	CROWD = 14, -- more units than this: other players' / enemy pets are drawn every other frame
	ANIM_MID = 90, -- studs from the camera: beyond this, other players' / enemy pets are drawn every 3rd frame ...
	ANIM_FAR = 160, -- ... and beyond this every 4th (a whole pet at once: root + wings, so nothing comes apart)
	MAX_FX_PARTS = 260,
	POOL_KEEP = 160,
	MAX_NUMBERS = 26,
	MAX_FLASHES = 8,
	FLASH_TIME = 0.2,
	NUMBER_TIME = 0.95,
	NUMBER_RISE = 2.6,
	NUMBER_PX = 26, -- 1080p pixel size of a damage number (World text rule: >= 22)
	CRIT_PX = 32,
	CALLOUT_PX = 26,
	NUMBER_DISTANCE = 170,
	BAR_DISTANCE = 140,
	END_LINGER = 3.5, -- seconds the floor stays drawn after the end
	SPECTATOR_LINGER = 1.5,
	RESULT_SECONDS = 12,
	CMD_GAP = 0.25, -- local throttle between two commands of a kind
	TAP_TIME = 0.35,
	TAP_MOVE = 14, -- px
	TAP_REACH = 64, -- px (1080p, scaled) around an enemy's centre on the screen
	ACTION_ATTACK = "NimbusBattleAttack",
	ACTION_RETREAT = "NimbusBattleRetreat",
	ACTION_SPECIAL = "NimbusBattleSpecial",
	-- HUD geometry (design px at 1080p)
	TEAM_W = 470,
	ROW_H = 70,
	ROW_GAP = 6,
	HEAD_H = 34,
	PAD = 10,
	CMD_H = 62,
	TOP_W = 600,
	TOP_W_COMPACT = 460,
	CARD_W = 124,
	CARD_H = 100,
	TOUCH_W = 112, -- compact ATTACK / RETREAT buttons (design px)
	TOUCH_H = 72,
	MIN_TEXT_PX = 14, -- no HUD text is ever drawn smaller on the screen (Readability rule)
	EDGE = 16,
	RESULT_W = 440,
}

local STATES = (BattleSim and BattleSim.States) or { Idle = 0, Moving = 1, Attacking = 2, Retreating = 3, Casting = 4, Down = 5, Stunned = 6 }
local S_DOWN, S_STUNNED, S_RETREATING, S_CASTING, S_ATTACKING = STATES.Down, STATES.Stunned, STATES.Retreating, STATES.Casting, STATES.Attacking
local EV = (BattleSim and BattleSim.Events) or {
	Hit = "Hit", Special = "Special", KO = "KO", Telegraph = "Telegraph", Spawn = "Spawn", Enrage = "Enrage",
	Order = "Order", Zone = "Zone", Leave = "Leave", End = "End",
}

local DMG = (BattleCatalog and BattleCatalog.Damage) or {}
local METER_MAX = tonumber(DMG.MeterMax) or 100
local RETREAT_LOCK = tonumber(DMG.RetreatLock) or 1.5
local SPECIALS = (BattleCatalog and BattleCatalog.Specials) or {}

local COLORS = {
	Mine = Theme.Colors.Health,
	Ally = Color3.fromRGB(98, 172, 232),
	Enemy = Color3.fromRGB(236, 88, 100),
	Gold = Theme.Colors.Gold or Color3.fromRGB(244, 196, 78),
	Heal = Color3.fromRGB(120, 230, 140),
	Shield = Color3.fromRGB(150, 210, 255),
	Ice = Color3.fromRGB(170, 228, 255),
	Weak = Color3.fromRGB(176, 190, 214),
	Strong = Color3.fromRGB(255, 150, 70),
	White = Color3.fromRGB(255, 255, 255),
	Ink = Theme.Colors.TextStroke or Color3.fromRGB(16, 22, 50),
	Panel = Theme.Colors.Panel,
	PanelLight = Theme.Colors.PanelLight,
	Navy = Theme.Colors.Navy or Color3.fromRGB(24, 34, 78),
	Muted = Theme.Colors.Muted or Color3.fromRGB(212, 224, 246),
	Track = Color3.fromRGB(28, 36, 76),
	Storm = Color3.fromRGB(72, 78, 108),
	StormLight = Color3.fromRGB(112, 118, 150),
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local St = {
	initialized = false,
	battle = nil, -- the drawn battle (see newBattle)
	old = {}, -- battles that ended and still fade out: { battle, until }
	conns = {}, -- long-lived connections
	loop = nil, -- RenderStepped connection (only while needed)
	folder = nil, -- workspace.ClientBattle
	fxFolder = nil,
	pool = {}, -- free effect parts
	fxLive = 0,
	effects = {}, -- live effects
	numbers = {}, -- live numbers
	numberPool = {},
	flashes = {}, -- live flashes
	flashPool = {},
	lastCmd = {}, -- [action .. arg] = os.clock()
	bound = false, -- ContextActionService bindings active
	gamepad = false, -- the last input was a gamepad
	tap = nil, -- { pos, t } a press that may become a tap
	frameNo = 0,
	perf = { frames = 0, total = 0, peak = 0, last = 0, builds = 0, split = {} },
	warned = {},
	remoteCmd = nil,
	result = nil, -- result card timer
}

local Hud = {} -- the battle HUD (built once, lazily)
local Fx = {} -- pooled effects
local Units = {} -- battle units
local Tele = {} -- telegraphs and zones
local Input = {} -- keys, gamepad, taps
local Net = {} -- messages

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function clamp(x, lo, hi)
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

local function warnOnce(key, message)
	if St.warned[key] then
		return
	end
	St.warned[key] = true
	warn("[BattleController] " .. tostring(message))
end

local function num(v, default)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

local function wrapAngle(a)
	return (a + pi) % TAU - pi
end

local function elementColor(element)
	local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[element]
	if info and typeof(info.Color) == "Color3" then
		return info.Color
	end
	return Color3.fromRGB(170, 180, 200)
end

local function myUserId()
	return LocalPlayer and LocalPlayer.UserId or 0
end

local function make(className, props, parent)
	local inst = Instance.new(className)
	if props then
		for key, value in pairs(props) do
			inst[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function fmtTime(seconds)
	seconds = max(0, floor(seconds + 0.5))
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

local function lazyBoss()
	if BossBuilder == nil then
		BossBuilder = optional(Shared, "BossBuilder") or false
	end
	return BossBuilder or nil
end

local function battleFolder()
	if St.folder and St.folder.Parent == workspace then
		return St.folder
	end
	local f = workspace:FindFirstChild(K.FOLDER)
	if not f then
		f = make("Folder", { Name = K.FOLDER }, workspace)
	end
	St.folder = f
	return f
end

local function fxFolder()
	if St.fxFolder and St.fxFolder.Parent then
		return St.fxFolder
	end
	St.fxFolder = make("Folder", { Name = "Fx" }, battleFolder())
	return St.fxFolder
end

----------------------------------------------------------------------
-- Effects: pooled voxel parts
----------------------------------------------------------------------
function Fx.Part(color, material, transparency)
	local p = table.remove(St.pool)
	if not p then
		if St.fxLive >= K.MAX_FX_PARTS then
			return nil
		end
		p = make("Part", {
			Name = "BattleFx",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Massless = true,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
		})
	end
	St.fxLive = St.fxLive + 1
	p.Shape = Enum.PartType.Block
	p.Material = material or Enum.Material.Neon
	p.Color = color or COLORS.White
	p.Transparency = transparency or 0
	p.Parent = fxFolder()
	return p
end

function Fx.Free(p)
	if not p then
		return
	end
	St.fxLive = max(0, St.fxLive - 1)
	if #St.pool < K.POOL_KEEP then
		p.Parent = nil
		St.pool[#St.pool + 1] = p
	else
		p:Destroy()
	end
end

-- registers a live effect: update(e, p, now) -> nothing; e.parts are freed when it ends
function Fx.Add(dur, update, parts, data)
	local e = data or {}
	e.t0 = os.clock()
	e.dur = dur
	e.update = update
	e.parts = parts or {}
	St.effects[#St.effects + 1] = e
	BattleController._wake()
	return e
end

local function burstUpdate(e, p)
	local t = p * e.dur
	local g = e.gravity
	local fade = p * p
	for i, part in ipairs(e.parts) do
		local v = e.vel[i]
		local x = e.ox + v[1] * t
		local y = e.oy + v[2] * t - 0.5 * g * t * t
		local z = e.oz + v[3] * t
		local a = v[4] * t
		local c, s = cos(a), sin(a)
		part.CFrame = CFrame.new(x, y, z, c, 0, s, 0, 1, 0, -s, 0, c)
		local size = e.size * (1 - 0.7 * p)
		part.Size = Vector3.new(size, size, size)
		part.Transparency = e.alpha + (1 - e.alpha) * fade
	end
end

-- a burst of voxel cubes flying out of `pos`
function Fx.Burst(pos, color, count, speed, size, dur, opts)
	opts = opts or {}
	local parts, vel = {}, {}
	local rnd = math.random
	for i = 1, count do
		local c = color
		if opts.color2 and i % 2 == 0 then
			c = opts.color2
		end
		local part = Fx.Part(c, opts.material, opts.alpha or 0)
		if not part then
			break
		end
		local a = rnd() * TAU
		local up = (opts.up or 0.6) + rnd() * 0.6
		local sp = speed * (0.55 + rnd() * 0.6)
		parts[#parts + 1] = part
		vel[#vel + 1] = { cos(a) * sp, up * sp, sin(a) * sp, (rnd() - 0.5) * 12 }
		part.Size = Vector3.new(size, size, size)
		part.CFrame = CFrame.new(pos)
	end
	if #parts == 0 then
		return nil
	end
	return Fx.Add(dur, burstUpdate, parts, {
		ox = pos.X, oy = pos.Y, oz = pos.Z, vel = vel, size = size, gravity = opts.gravity or 18, alpha = opts.alpha or 0,
	})
end

local function ringUpdate(e, p)
	local r = e.r * (0.25 + 0.75 * (1 - (1 - p) * (1 - p)))
	local n = #e.parts
	for i, part in ipairs(e.parts) do
		local a = (i / n) * TAU + e.spin * p
		part.CFrame = CFrame.new(e.ox + cos(a) * r, e.oy + 0.3 + 0.6 * p, e.oz + sin(a) * r)
		part.Transparency = e.alpha + (1 - e.alpha) * p
	end
end

-- a ring of cubes that expands from `pos` to radius r (shock waves)
function Fx.Ring(pos, r, color, count, size, dur, alpha)
	local parts = {}
	for _ = 1, count do
		local part = Fx.Part(color, Enum.Material.Neon, alpha or 0.1)
		if not part then
			break
		end
		part.Size = Vector3.new(size, size * 0.6, size)
		parts[#parts + 1] = part
	end
	if #parts == 0 then
		return nil
	end
	return Fx.Add(dur, ringUpdate, parts, { ox = pos.X, oy = pos.Y, oz = pos.Z, r = r, spin = 0.6, alpha = alpha or 0.1 })
end

local function riseUpdate(e, p)
	local t = p * e.dur
	for i, part in ipairs(e.parts) do
		local v = e.vel[i]
		part.CFrame = CFrame.new(e.ox + v[1], e.oy + v[2] * t, e.oz + v[3])
		part.Transparency = 0.1 + 0.9 * p * p
	end
end

-- cubes rising around a point (heal sparks)
function Fx.Rise(pos, color, count, size, dur, spread)
	local parts, vel = {}, {}
	local rnd = math.random
	for _ = 1, count do
		local part = Fx.Part(color, Enum.Material.Neon, 0.1)
		if not part then
			break
		end
		part.Size = Vector3.new(size, size, size)
		parts[#parts + 1] = part
		local a = rnd() * TAU
		local r = spread * (0.3 + rnd() * 0.7)
		vel[#vel + 1] = { cos(a) * r, 2 + rnd() * 3, sin(a) * r }
	end
	if #parts == 0 then
		return nil
	end
	return Fx.Add(dur, riseUpdate, parts, { ox = pos.X, oy = pos.Y - 0.6, oz = pos.Z, vel = vel })
end

local function boltUpdate(e, p)
	local q = clamp(p * 1.25, 0, 1)
	local x = e.ax + (e.bx - e.ax) * q
	local y = e.ay + (e.by - e.ay) * q + sin(q * pi) * e.arc
	local z = e.az + (e.bz - e.az) * q
	local core = e.parts[1]
	if core then
		core.CFrame = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(e.bx, e.by, e.bz))
		core.Transparency = (p > 0.8) and 1 or 0
	end
	local tail = e.parts[2]
	if tail then
		local q2 = max(0, q - 0.12)
		tail.CFrame = CFrame.new(e.ax + (e.bx - e.ax) * q2, e.ay + (e.by - e.ay) * q2 + sin(q2 * pi) * e.arc, e.az + (e.bz - e.az) * q2)
		tail.Transparency = (p > 0.8) and 1 or 0.45
	end
	if p >= 0.8 and not e.landed then
		e.landed = true
		Fx.Burst(Vector3.new(e.bx, e.by, e.bz), e.color, 5, 7, 0.28, 0.35, { up = 0.3, gravity = 10 })
	end
end

-- a voxel bolt flying from a to b (ranged attacks), with a small burst where it lands
function Fx.Bolt(a, b, color, size, dur)
	local core = Fx.Part(color, Enum.Material.Neon, 0)
	if not core then
		return nil
	end
	core.Size = Vector3.new(size, size, size * 1.8)
	local tail = Fx.Part(color, Enum.Material.Neon, 0.45)
	if tail then
		tail.Size = Vector3.new(size * 0.6, size * 0.6, size * 0.6)
	end
	local dist = (b - a).Magnitude
	return Fx.Add(dur, boltUpdate, { core, tail }, {
		ax = a.X, ay = a.Y, az = a.Z, bx = b.X, by = b.Y, bz = b.Z, arc = min(2.2, dist * 0.08), color = color,
	})
end

local function beamUpdate(e, p)
	local w = e.width * (1 - p * 0.85)
	local core, glow = e.parts[1], e.parts[2]
	if core then
		core.Size = Vector3.new(w * 0.45, w * 0.45, e.length)
		core.Transparency = p * p
	end
	if glow then
		glow.Size = Vector3.new(w, w, e.length)
		glow.Transparency = 0.55 + 0.45 * p
	end
end

-- a straight beam (Beam specials): cf = the beam's centre frame (LookVector along the beam)
function Fx.Beam(cf, length, width, color, dur)
	local core = Fx.Part(COLORS.White:Lerp(color, 0.35), Enum.Material.Neon, 0)
	if not core then
		return nil
	end
	core.CFrame = cf
	core.Size = Vector3.new(width * 0.45, width * 0.45, length)
	local glow = Fx.Part(color, Enum.Material.Neon, 0.55)
	if glow then
		glow.CFrame = cf
		glow.Size = Vector3.new(width, width, length)
	end
	return Fx.Add(dur, beamUpdate, { core, glow }, { length = length, width = width })
end

local function trailUpdate(e, p)
	for i, part in ipairs(e.parts) do
		local k = i / #e.parts
		part.Transparency = clamp(0.2 + p * 1.2 - k * 0.3, 0, 1)
	end
end

-- a dash trail of fading cubes from a to b (Pounce)
function Fx.Trail(a, b, color, count, dur)
	local parts = {}
	for i = 1, count do
		local part = Fx.Part(color, Enum.Material.Neon, 0.2)
		if not part then
			break
		end
		local k = (i - 0.5) / count
		local s = 0.35 + 0.35 * k
		part.Size = Vector3.new(s, s, s)
		part.CFrame = CFrame.new(a:Lerp(b, k) + Vector3.new(0, sin(k * pi) * 1.2, 0))
		parts[#parts + 1] = part
	end
	if #parts == 0 then
		return nil
	end
	return Fx.Add(dur, trailUpdate, parts, {})
end

local function zoneUpdate(e, p, now)
	local t = now - e.t0
	local fadeIn = clamp(t / 0.3, 0, 1)
	local fadeOut = clamp((e.dur - t) / 0.4, 0, 1)
	local vis = fadeIn * fadeOut
	local disc = e.parts[1]
	if disc then
		disc.Transparency = 1 - (1 - e.discAlpha) * vis
	end
	if e.cloud then
		-- the storm cloud bobs; bolts strike every 0.5 s
		local bob = sin(t * 2.2) * 0.25
		for i = 2, e.cloudEnd do
			local part = e.parts[i]
			local o = e.offsets[i]
			part.CFrame = CFrame.new(e.ox + o.X, e.oy + o.Y + bob, e.oz + o.Z)
			part.Transparency = 1 - (1 - o.alpha) * vis
		end
		local phase = (t % 0.5) / 0.5
		for i = e.cloudEnd + 1, #e.parts do
			local part = e.parts[i]
			if phase < 0.3 and vis > 0.2 then
				if not e.boltFor or e.boltFor ~= floor(t / 0.5) then
					e.boltFor = floor(t / 0.5)
					local rnd = math.random
					local a, r = rnd() * TAU, rnd() * e.r * 0.8
					e.bx, e.bz = e.ox + cos(a) * r, e.oz + sin(a) * r
				end
				local k = i - e.cloudEnd
				local seg = (e.oy - e.floorY) / 3
				local y = e.oy - seg * (k - 0.5) - 0.3
				local jig = (k % 2 == 0) and 0.5 or -0.5
				part.CFrame = CFrame.new(e.bx + jig, y, e.bz - jig * 0.5) * CFrame.Angles(0, 0, jig * 0.4)
				part.Transparency = 0.05
			else
				part.Transparency = 1
			end
		end
	elseif e.bubbles then
		for i = 2, #e.parts do
			local part = e.parts[i]
			local o = e.offsets[i]
			local q = ((t * o.speed) + o.phase) % 1
			part.CFrame = CFrame.new(e.ox + o.X, e.oy + q * 1.4, e.oz + o.Z)
			part.Transparency = 1 - (1 - 0.15) * vis * (1 - q)
		end
	end
end

-- a damaging area on the floor for `seconds`: Storm (a voxel storm cloud with lightning) or a lingering pool
function Fx.Zone(floorCF, r, seconds, color, kind)
	local parts = {}
	local disc = Fx.Part(color, Enum.Material.Neon, 0.7)
	if not disc then
		return nil
	end
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.12, r * 2, r * 2)
	disc.CFrame = floorCF * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, pi / 2)
	parts[1] = disc
	local pos = floorCF.Position
	local e = { ox = pos.X, oy = pos.Y, oz = pos.Z, floorY = pos.Y, r = r, offsets = {}, discAlpha = 0.62 }
	local rnd = math.random
	if kind == "Storm" then
		e.cloud = true
		e.oy = pos.Y + 7.5
		local puffs = 9
		for i = 1, puffs do
			local shade = (i % 3 == 0) and COLORS.StormLight or COLORS.Storm
			local part = Fx.Part(shade, Enum.Material.SmoothPlastic, 0.05)
			if not part then
				break
			end
			local a = (i / puffs) * TAU
			local rr = (i == 1) and 0 or r * (0.25 + rnd() * 0.45)
			local s = 1.6 + rnd() * 1.4
			part.Size = Vector3.new(s * 1.3, s * 0.8, s * 1.3)
			parts[#parts + 1] = part
			e.offsets[#parts] = { X = cos(a) * rr, Y = rnd() * 0.8, Z = sin(a) * rr, alpha = 0.05 }
		end
		e.cloudEnd = #parts
		for _ = 1, 3 do
			local bolt = Fx.Part(Color3.fromRGB(230, 236, 255), Enum.Material.Neon, 1)
			if not bolt then
				break
			end
			bolt.Size = Vector3.new(0.25, (e.oy - pos.Y) / 3 + 0.4, 0.25)
			parts[#parts + 1] = bolt
		end
	else
		e.bubbles = true
		for _ = 1, 7 do
			local part = Fx.Part(color:Lerp(COLORS.White, 0.25), Enum.Material.Neon, 0.3)
			if not part then
				break
			end
			local a, rr = rnd() * TAU, rnd() * r * 0.85
			local s = 0.35 + rnd() * 0.35
			part.Size = Vector3.new(s, s, s)
			parts[#parts + 1] = part
			e.offsets[#parts] = { X = cos(a) * rr, Z = sin(a) * rr, speed = 0.6 + rnd() * 0.8, phase = rnd() }
		end
	end
	return Fx.Add(seconds, zoneUpdate, parts, e)
end

function Fx.Update(now)
	local list = St.effects
	local i = 1
	while i <= #list do
		local e = list[i]
		local p = (now - e.t0) / e.dur
		local ok = true
		if p < 1 then
			ok = pcall(e.update, e, clamp(p, 0, 1), now)
		end
		if p >= 1 or not ok then
			for _, part in ipairs(e.parts) do
				Fx.Free(part)
			end
			e.parts = {}
			list[i] = list[#list]
			list[#list] = nil
		else
			i = i + 1
		end
	end
end

function Fx.ClearAll()
	for _, e in ipairs(St.effects) do
		for _, part in ipairs(e.parts) do
			Fx.Free(part)
		end
	end
	St.effects = {}
	for _, n in ipairs(St.numbers) do
		n.gui.Enabled = false
		n.gui.Adornee = nil
		St.numberPool[#St.numberPool + 1] = n
	end
	St.numbers = {}
	for _, f in ipairs(St.flashes) do
		f.hl.Enabled = false
		f.hl.Adornee = nil
		St.flashPool[#St.flashPool + 1] = f
	end
	St.flashes = {}
end

----------------------------------------------------------------------
-- Effects: floating numbers (pixel-sized billboards in the world: World text rule) and hit flashes
----------------------------------------------------------------------
local function newNumber()
	local gui = make("BillboardGui", {
		Name = "BattleNumber",
		Size = UDim2.fromOffset(240, 64),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = K.NUMBER_DISTANCE,
		Enabled = false,
	})
	local label = Theme.Label("", "Accent", { Size = K.NUMBER_PX, Stroke = 0, Outline = 2.5 })
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = gui
	local scale = make("UIScale", { Name = "Pop", Scale = 1 }, label)
	return { gui = gui, label = label, scale = scale }
end

-- shows `text` above `adornee` (a BasePart), rising and fading; kind tweaks size / life
function Fx.Number(adornee, height, text, color, px, life)
	if not adornee or not adornee.Parent then
		return nil
	end
	local n = table.remove(St.numberPool)
	if not n then
		if #St.numbers >= K.MAX_NUMBERS then
			n = table.remove(St.numbers, 1) -- recycle the oldest
		else
			n = newNumber()
		end
	end
	if not n then
		return nil
	end
	n.gui.Parent = fxFolder()
	n.gui.Adornee = adornee
	n.label.Text = text
	n.label.TextColor3 = color or COLORS.White
	n.label.TextSize = Theme.ScaledSize(px or K.NUMBER_PX, 22)
	n.label.TextTransparency = 0
	local outline = n.label:FindFirstChild("TextOutline")
	if outline then
		outline.Transparency = 0
	end
	n.t0 = os.clock()
	n.life = life or K.NUMBER_TIME
	n.base = height
	n.jx = (math.random() - 0.5) * 1.4
	n.gui.StudsOffset = Vector3.new(n.jx, height, 0)
	n.gui.Enabled = true
	St.numbers[#St.numbers + 1] = n
	BattleController._wake()
	return n
end

function Fx.UpdateNumbers(now)
	local list = St.numbers
	local i = 1
	while i <= #list do
		local n = list[i]
		local p = (now - n.t0) / n.life
		if p >= 1 or not n.gui.Adornee or not n.gui.Adornee.Parent then
			n.gui.Enabled = false
			n.gui.Adornee = nil
			table.remove(list, i)
			St.numberPool[#St.numberPool + 1] = n
		else
			local rise = 1 - (1 - p) * (1 - p)
			n.gui.StudsOffset = Vector3.new(n.jx, n.base + rise * K.NUMBER_RISE, 0)
			n.scale.Scale = 1 + 0.45 * max(0, 1 - p * 6)
			local fade = clamp((p - 0.6) / 0.4, 0, 1)
			n.label.TextTransparency = fade
			local outline = n.label:FindFirstChild("TextOutline")
			if outline then
				outline.Transparency = fade
			end
			i = i + 1
		end
	end
end

-- a short white (or tinted) flash on a model (a pooled Highlight)
function Fx.Flash(u, color)
	if not u or not u.model or u.parked then
		return
	end
	local f = u.flash
	if not f then
		f = table.remove(St.flashPool)
		if not f then
			if #St.flashes >= K.MAX_FLASHES then
				return
			end
			f = {
				hl = make("Highlight", {
					Name = "HitFlash",
					DepthMode = Enum.HighlightDepthMode.Occluded,
					OutlineTransparency = 1,
					FillTransparency = 1,
					Enabled = false,
				}),
			}
		end
		f.hl.Parent = fxFolder()
		St.flashes[#St.flashes + 1] = f
		u.flash = f
		f.unit = u
	end
	f.t0 = os.clock()
	f.hl.FillColor = color or COLORS.White
	f.hl.Adornee = u.model
	f.hl.FillTransparency = 0.25
	f.hl.Enabled = true
	BattleController._wake()
end

function Fx.UpdateFlashes(now)
	local list = St.flashes
	local i = 1
	while i <= #list do
		local f = list[i]
		local p = (now - f.t0) / K.FLASH_TIME
		if p >= 1 or not f.hl.Adornee then
			f.hl.Enabled = false
			f.hl.Adornee = nil
			if f.unit then
				f.unit.flash = nil
				f.unit = nil
			end
			list[i] = list[#list]
			list[#list] = nil
			St.flashPool[#St.flashPool + 1] = f
		else
			f.hl.FillTransparency = 0.25 + 0.75 * p
			i = i + 1
		end
	end
end

----------------------------------------------------------------------
-- Battle record + coordinates
----------------------------------------------------------------------
local function newBattle(payload, battleId)
	local zone = type(payload.Zone) == "table" and payload.Zone or {}
	local cf = zone.CFrame
	if typeof(cf) ~= "CFrame" then
		cf = CFrame.new()
	end
	local size = zone.Size
	local zx = num(zone.X, typeof(size) == "Vector3" and size.X or 60)
	local zz = num(zone.Z, typeof(size) == "Vector3" and size.Z or 60)
	local side = num(payload.Side, 0)
	local spectator = payload.Spectator == true or side == 0
	local B = {
		Id = payload.BattleId or battleId,
		Mode = tostring(payload.Mode or "Duel"),
		Side = side,
		Spectator = spectator,
		Fighter = not spectator,
		ZoneCF = cf,
		ZoneX = zx,
		ZoneZ = zz,
		Names = type(payload.Names) == "table" and payload.Names or {},
		Trial = type(payload.Trial) == "table" and payload.Trial or nil,
		TimeLimit = num(payload.TimeLimit, 0),
		Level = payload.Level,
		BossId = payload.BossId,
		units = {},
		list = {},
		mine = {},
		snaps = {},
		offset = 0,
		haveOffset = false,
		renderT = num(payload.T, 0),
		evq = {},
		teles = {},
		buildQueue = {},
		focus = nil,
		order = "Attack",
		retreatAt = -math.huge,
		ended = false,
		simEnded = false,
		enraged = false,
		wave = 0,
		folder = nil,
	}
	-- the zone basis, so a zone-local point becomes a world point with plain arithmetic per frame
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	B.basis = { px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
	B.folder = make("Folder", { Name = "Battle_" .. tostring(B.Id) }, battleFolder())
	return B
end

-- zone-local (x, y, z) -> world Vector3
local function worldPoint(B, x, y, z)
	local b = B.basis
	return Vector3.new(b[1] + b[4] * x + b[5] * y + b[6] * z, b[2] + b[7] * x + b[8] * y + b[9] * z, b[3] + b[10] * x + b[11] * y + b[12] * z)
end

-- zone-local position + yaw (0 = facing -Z of the zone) -> world CFrame (one allocation)
local function worldFrame(B, x, y, z, yaw)
	local b = B.basis
	local c, s = cos(yaw), sin(yaw)
	-- R = Z * Ry(yaw): columns of Ry are (c,0,-s), (0,1,0), (s,0,c)
	local m00 = b[4] * c - b[6] * s
	local m01 = b[5]
	local m02 = b[4] * s + b[6] * c
	local m10 = b[7] * c - b[9] * s
	local m11 = b[8]
	local m12 = b[7] * s + b[9] * c
	local m20 = b[10] * c - b[12] * s
	local m21 = b[11]
	local m22 = b[10] * s + b[12] * c
	return CFrame.new(
		b[1] + b[4] * x + b[5] * y + b[6] * z,
		b[2] + b[7] * x + b[8] * y + b[9] * z,
		b[3] + b[10] * x + b[11] * y + b[12] * z,
		m00, m01, m02, m10, m11, m12, m20, m21, m22
	)
end

local function yawToward(dx, dz)
	return atan2(-dx, -dz)
end

----------------------------------------------------------------------
-- Units
----------------------------------------------------------------------
-- the definition PetBuilder draws for a unit (its look from the sim; else its key / pet id)
function Units.Def(info)
	local look = info.look
	local base = nil
	if PetCatalog and type(PetCatalog.Get) == "function" then
		if info.petId then
			local ok, d = pcall(PetCatalog.Get, info.petId)
			base = ok and type(d) == "table" and d or nil
		end
		if not base and type(look) == "table" and look.BodyId then
			local ok, d = pcall(PetCatalog.Get, look.BodyId)
			base = ok and type(d) == "table" and d or nil
		end
	end
	if type(look) == "table" then
		return { Id = tostring(info.key or info.petId or info.id), Rarity = base and base.Rarity or nil, Look = look }
	end
	if PetKeys and type(info.key) == "string" then
		local ok, d = pcall(PetKeys.DefOf, info.key)
		if ok and type(d) == "table" then
			return d
		end
	end
	return base
end

local function isAnimatedPart(part)
	local spec = part:GetAttribute("PB_G")
	if type(spec) ~= "string" or type(part:GetAttribute("PB_Base")) ~= "string" then
		return false
	end
	local kind = string.match(spec, "^[^:]*:([^:]*)")
	return kind ~= "lid"
end

-- welds the static parts to the anchored root once: a pose is then one root CFrame write
local function weldStatic(model, root)
	local inv = root.CFrame:Inverse()
	local identity = CFrame.new()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root and part.Anchored and not isAnimatedPart(part) then
			make("Weld", { Name = "BattleWeld", Part0 = root, Part1 = part, C0 = inv * part.CFrame, C1 = identity }, part)
			part.Anchored = false
		end
	end
	root.Anchored = true
end

function Units.Add(B, info)
	if type(info) ~= "table" then
		return nil
	end
	local id = tonumber(info.id)
	if not id then
		return nil
	end
	local u = B.units[id]
	if u then
		u.info = info
		return u
	end
	local me = myUserId()
	local side = num(info.side, 2)
	local mine = B.Fighter and info.owner == me
	local ally
	if B.Fighter then
		ally = side == B.Side
	else
		ally = side == 1
	end
	u = {
		id = id,
		info = info,
		side = side,
		owner = info.owner,
		slot = num(info.slot, 0),
		kind = tostring(info.kind or "Pet"),
		name = tostring(info.name or "Pet"),
		element = info.element,
		elements = type(info.elements) == "table" and info.elements or { info.element },
		maxHp = max(1, num(info.maxHp, 100)),
		level = num(info.level, 1),
		tier = info.tier,
		scale = num(info.scale, 1),
		ranged = info.ranged == true,
		radius = num(info.radius, 1.8),
		special = type(info.special) == "table" and info.special or nil,
		isBoss = info.kind == "Boss",
		bossId = info.boss,
		mine = mine,
		ally = ally,
		x = 0,
		z = 0,
		seen = false,
		yaw = 0,
		hp = max(1, num(info.maxHp, 100)),
		state = 0,
		meter = 0,
		shield = 0,
		phase = math.random() * TAU,
		animOpts = { Flap = 1, Excited = 0 },
		bossOpts = { CFrame = nil, Progress = 0, Attack = nil, Enraged = false },
		pose = "Idle",
		poseAt = 0,
		poseDur = 0,
	}
	B.units[id] = u
	B.list[#B.list + 1] = u
	if u.isBoss then
		B.boss = u
	end
	if mine and u.slot >= 1 and u.slot <= 4 then
		B.mine[u.slot] = u
	end
	B.buildQueue[#B.buildQueue + 1] = u
	return u
end

function Units.Destroy(u)
	if u.flash then
		u.flash.hl.Adornee = nil
	end
	for _, key in ipairs({ "shieldPart", "icePart", "focusMark" }) do
		local p = u[key]
		if p then
			pcall(p.Destroy, p)
			u[key] = nil
		end
	end
	if u.model then
		pcall(u.model.Destroy, u.model)
	end
	u.model = nil
	u.root = nil
	u.bar = nil
	u.gone = true
end

function Units.Remove(B, id)
	local u = B.units[id]
	if not u then
		return
	end
	B.units[id] = nil
	for i, v in ipairs(B.list) do
		if v == u then
			table.remove(B.list, i)
			break
		end
	end
	for slot, v in pairs(B.mine) do
		if v == u then
			B.mine[slot] = nil
		end
	end
	if B.boss == u then
		B.boss = nil
	end
	Units.Destroy(u)
end

-- the pixel HP bar above a unit (no text: World text rule only covers text)
local function addBar(u, adornee, height)
	local color = u.mine and COLORS.Mine or (u.ally and COLORS.Ally or COLORS.Enemy)
	local w, h = Theme.ScaledSize(74, 50), Theme.ScaledSize(11, 8)
	local gui = make("BillboardGui", {
		Name = "HpBar",
		Adornee = adornee,
		Size = UDim2.fromOffset(w, h),
		StudsOffset = Vector3.new(0, height, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = K.BAR_DISTANCE,
	})
	local back = make("Frame", {
		Name = "Back",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.Track,
		BorderSizePixel = 0,
	}, gui)
	Theme.Corner(back, UDim.new(0, 4))
	Theme.Stroke(back, u.mine and COLORS.Gold or COLORS.Ink, u.mine and 2 or 1.5, 0)
	local fill = make("Frame", {
		Name = "Fill",
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, back)
	Theme.Corner(fill, UDim.new(0, 3))
	gui.Parent = u.model
	u.bar = gui
	u.barFill = fill
	u.barFrac = 1
end

-- builds one unit's model (pcall'd by the caller)
local function buildUnit(B, u)
	if u.isBoss then
		local BB = lazyBoss()
		if not BB then
			error("BossBuilder is missing")
		end
		local cf = worldFrame(B, u.x, 0, u.z, u.yaw)
		local model = BB.Build(u.bossId, { Detail = "High", CFrame = cf })
		if not model then
			error("BossBuilder.Build returned nil for " .. tostring(u.bossId))
		end
		local okH, h = pcall(BB.GetHeight, model)
		u.height = (okH and num(h, 20)) or 20
		u.model = model
		u.root = model.PrimaryPart or model:FindFirstChild("Root")
		model.Parent = B.folder
		if B.enraged then
			pcall(BB.SetEnraged, model, true)
		end
		return
	end
	if not PetBuilder then
		error("PetBuilder is missing")
	end
	local def = Units.Def(u.info)
	if not def then
		error("no definition for unit " .. tostring(u.id))
	end
	local detail = u.mine and "High" or "Low"
	local model = PetBuilder.Build(def, { Scale = K.PET_SCALE * u.scale, Detail = detail })
	local root = model.PrimaryPart or model:FindFirstChild("Body")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		error("pet model without a root")
	end
	local okSize, size = pcall(model.GetExtentsSize, model)
	u.height = (okSize and typeof(size) == "Vector3") and size.Y or 3.5
	u.centerY = u.height / 2 + K.HOVER
	-- weld at the built pose FIRST, then move: a pose is one root CFrame write from here on
	local okWeld = pcall(weldStatic, model, root)
	u.rigid = okWeld
	local cf = worldFrame(B, u.x, u.centerY, u.z, u.yaw)
	if okWeld then
		root.CFrame = cf
	else
		pcall(model.PivotTo, model, cf)
	end
	u.model = model
	u.root = root
	u.folder = B.folder
	model.Name = "Unit_" .. tostring(u.id)
	addBar(u, root, u.height / 2 + 0.9)
	model.Parent = B.folder
end

function Units.BuildPending(B)
	local q = B.buildQueue
	if #q == 0 then
		return
	end
	local t0 = os.clock()
	local built = 0
	while #q > 0 and built < K.BUILD_MAX do
		if built > 0 and os.clock() - t0 > K.BUILD_BUDGET then
			break
		end
		local u = table.remove(q, 1)
		if not u.gone and not u.model then
			local ok, err = pcall(buildUnit, B, u)
			if not ok then
				warnOnce("build_" .. tostring(u.kind) .. tostring(u.info and (u.info.key or u.info.boss)), "could not build unit " .. tostring(u.name) .. ": " .. tostring(err))
				u.failed = true
			end
			built = built + 1
			St.perf.builds = St.perf.builds + 1
		end
	end
end

-- a pet's KO: poof, then the model is parked until the end
local function parkUnit(u, parked)
	if not u.model then
		return
	end
	if parked and not u.parked then
		u.parked = true
		u.model.Parent = nil
	elseif not parked and u.parked then
		u.parked = false
		u.model.Parent = u.folder or u.model.Parent
	end
end

function Units.SetPose(u, pose, dur, attackId)
	u.pose = pose
	u.poseAt = os.clock()
	u.poseDur = dur or 0
	if attackId then
		u.attackId = attackId
	end
end

-- per-frame update of one unit (position from the snapshots, facing, lunge / hop, animation)
local function updateUnit(B, u, now, dt, sa, sb, alpha, animate)
	local a = sa and sa.Units[u.id]
	local b = sb and sb.Units[u.id]
	local x, z = u.x, u.z
	if type(a) == "table" and type(b) == "table" then
		x = a.x + (b.x - a.x) * alpha
		z = a.z + (b.z - a.z) * alpha
	elseif type(a) == "table" then
		x, z = a.x, a.z
	elseif type(b) == "table" then
		x, z = b.x, b.z
	end
	local d = (alpha >= 0.5 and type(b) == "table" and b) or (type(a) == "table" and a) or (type(b) == "table" and b) or nil
	if d then
		u.hp = num(d.hp, u.hp)
		u.state = num(d.state, u.state)
		u.target = d.target
		u.meter = num(d.meter, 0)
		u.shield = num(d.shield, 0)
	end
	x, z = num(x, u.x), num(z, u.z)
	local mx, mz = x - u.x, z - u.z
	if not u.seen then
		u.seen = true
		mx, mz = 0, 0
		-- face the floor centre at first
		u.yaw = yawToward(-x, -z)
	end
	u.x, u.z = x, z
	if not u.model then
		return
	end
	local down = u.state == S_DOWN or u.hp <= 0
	if u.isBoss then
		Units.UpdateBoss(B, u, now, down, dt)
		return
	end
	-- downed pets: poof once, then park
	if down then
		if not u.downAt then
			u.downAt = now
			if not u.poofed then
				u.poofed = true
				local pos = worldPoint(B, x, u.centerY or 1.5, z)
				Fx.Burst(pos, Color3.fromRGB(236, 240, 250), 12, 9, 0.5, 0.6, { color2 = elementColor(u.element), alpha = 0.05 })
			end
		end
		if now - u.downAt >= K.KO_PARK then
			parkUnit(u, true)
		end
		return
	elseif u.parked then
		u.downAt = nil
		parkUnit(u, false)
	end
	u.accDt = (u.accDt or 0) + dt
	if u.parked or not animate then
		return
	end
	u.posed = true
	dt = u.accDt -- the time since this pet was last drawn (strided far / crowded pets)
	u.accDt = 0
	-- facing: the target while fighting, else the way it moves
	local want = nil
	local tgt = u.target and B.units[u.target]
	if tgt and (u.state == S_ATTACKING or u.state == S_CASTING or (u.state ~= S_RETREATING and mx * mx + mz * mz < 0.0004)) then
		want = yawToward(tgt.x - x, tgt.z - z)
	elseif mx * mx + mz * mz > 0.0004 then
		want = yawToward(mx, mz)
	end
	if want and u.state ~= S_STUNNED then
		local k = 1 - exp(-K.FACE_RATE * dt)
		u.yaw = u.yaw + wrapAngle(want - u.yaw) * k
	end
	-- lunge / recoil / hop
	local ox, oz, oy = 0, 0, 0
	if u.lungeAt then
		local p = (now - u.lungeAt) / K.LUNGE_TIME
		if p >= 1 then
			u.lungeAt = nil
		else
			local amt = sin(p * pi) * (u.ranged and -K.RECOIL_DIST or K.LUNGE_DIST)
			ox, oz = u.lungeX * amt, u.lungeZ * amt
		end
	end
	if u.hopAt then
		local p = (now - u.hopAt) / K.HOP_TIME
		if p >= 1 then
			u.hopAt = nil
		elseif p > 0 then
			oy = sin(p * pi) * K.HOP_HEIGHT
		end
	end
	if u.hurtAt then
		local p = (now - u.hurtAt) / 0.18
		if p >= 1 then
			u.hurtAt = nil
		else
			local amt = sin(p * pi) * 0.3
			ox, oz = ox + (u.hurtX or 0) * amt, oz + (u.hurtZ or 0) * amt
		end
	end
	local bob = 0
	local stunned = u.state == S_STUNNED
	if not stunned then
		bob = sin(now * 3.1 + u.phase) * K.BOB
	end
	local cf = worldFrame(B, x + ox, (u.centerY or 1.5) + bob + oy, z + oz, u.yaw)
	if u.rigid then
		u.root.CFrame = cf
	else
		pcall(u.model.PivotTo, u.model, cf)
	end
	if PetBuilder and not u.animBroken then
		local opts = u.animOpts
		opts.Flap = stunned and 0 or ((u.state == S_RETREATING or mx * mx + mz * mz > 0.0004) and 1.8 or 1)
		opts.Excited = (u.state == S_ATTACKING or u.state == S_CASTING) and 0.6 or 0
		local ok = pcall(PetBuilder.Animate, u.model, now + u.phase, opts)
		if not ok then
			u.animBroken = true
		end
	end
	-- the HP bar (only when it changes)
	local frac = clamp(u.hp / u.maxHp, 0, 1)
	if u.barFill and abs(frac - (u.barFrac or -1)) > 0.004 then
		u.barFrac = frac
		u.barFill.Size = UDim2.new(max(frac, 0.02), -2, 1, -2)
	end
	-- shield cube and ice crystals follow the unit
	Units.UpdateStatus(B, u, now, cf)
end

-- shield bubble (while the snapshot reports a shield) and ice (while stunned)
function Units.UpdateStatus(B, u, now, cf)
	local h = u.height or 3
	if u.shield > 0 then
		local p = u.shieldPart
		if not p then
			p = make("Part", {
				Name = "ShieldCube",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.ForceField,
				Color = COLORS.Shield,
				Transparency = 0,
				Size = Vector3.new(h * 1.25, h * 1.15, h * 1.25),
			}, u.model)
			u.shieldPart = p
		end
		p.CFrame = cf * CFrame.Angles(0, now * 0.8, 0)
	elseif u.shieldPart then
		u.shieldPart:Destroy()
		u.shieldPart = nil
	end
	local iced = u.state == S_STUNNED or (u.iceUntil and now < u.iceUntil)
	if iced then
		local p = u.icePart
		if not p then
			p = make("Model", { Name = "Ice" }, u.model)
			for i = 1, 5 do
				local a = (i / 5) * TAU
				local s = h * (0.28 + 0.06 * (i % 3))
				make("Part", {
					Name = "Crystal",
					Anchored = true,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
					CastShadow = false,
					Material = Enum.Material.Glass,
					Color = COLORS.Ice,
					Transparency = 0.35,
					Size = Vector3.new(s * 0.45, s * 1.4, s * 0.45),
				}, p):SetAttribute("Angle", a)
			end
			u.icePart = p
		end
		local r = (u.radius or 1.8) * 0.75 * K.PET_SCALE * 0.6
		for _, c in ipairs(p:GetChildren()) do
			local a = c:GetAttribute("Angle") or 0
			c.CFrame = cf * CFrame.new(cos(a) * r, -h * 0.25, sin(a) * r) * CFrame.Angles(0.35 * cos(a), a, 0.35 * sin(a))
		end
	elseif u.icePart then
		u.icePart:Destroy()
		u.icePart = nil
	end
end

-- the raid boss: BossBuilder poses on the interpolated position
function Units.UpdateBoss(B, u, now, down, dt)
	local BB = lazyBoss()
	if not BB then
		return
	end
	local tgt = u.target and B.units[u.target]
	local want = nil
	if u.faceX then
		want = yawToward(u.faceX - u.x, u.faceZ - u.z)
	elseif tgt then
		want = yawToward(tgt.x - u.x, tgt.z - u.z)
	end
	if want and not down then
		u.yaw = u.yaw + wrapAngle(want - u.yaw) * (1 - exp(-3 * (dt or 0.016)))
	end
	local pose = u.pose
	local progress = 0
	if down then
		if pose ~= "Down" then
			Units.SetPose(u, "Down", 1.6)
			pose = "Down"
		end
	end
	if u.poseDur > 0 then
		progress = clamp((now - u.poseAt) / u.poseDur, 0, 1)
		if progress >= 1 and pose ~= "Down" and pose ~= "Windup" then
			Units.SetPose(u, "Idle", 0)
			pose = "Idle"
			u.faceX, u.faceZ = nil, nil
		end
	end
	if pose == "Windup" and u.windupAt then
		progress = clamp((B.renderT - u.windupFrom) / max(0.1, u.windupAt - u.windupFrom), 0, 1)
	end
	local opts = u.bossOpts
	opts.CFrame = worldFrame(B, u.x, 0, u.z, u.yaw)
	opts.Progress = progress
	opts.Attack = u.attackId
	opts.Enraged = B.enraged
	local ok, err = pcall(BB.Animate, u.model, pose, now, opts)
	if not ok then
		warnOnce("bossanim", "BossBuilder.Animate failed: " .. tostring(err))
	end
end

-- the world point of a unit's body centre (effects, numbers)
local function unitCenter(B, u)
	local y = u.isBoss and (u.height or 20) * 0.55 or (u.centerY or 1.5)
	return worldPoint(B, u.x, y, u.z)
end

----------------------------------------------------------------------
-- Telegraphs (boss attacks) and zones
----------------------------------------------------------------------
function Tele.Start(B, ev)
	local id = ev.id
	if id == nil or B.teles[id] then
		return
	end
	local fill, edge = Color3.fromRGB(255, 110, 90), Color3.fromRGB(255, 220, 160)
	local BB = lazyBoss()
	local boss = ev.boss and B.units[ev.boss]
	local bossId = (boss and boss.bossId) or B.BossId
	if BB and bossId then
		local ok, f, e = pcall(BB.TelegraphColor, bossId, ev.attack)
		if ok and typeof(f) == "Color3" then
			fill = f
			if typeof(e) == "Color3" then
				edge = e
			end
		end
	end
	local hits = max(0.2, num(ev.hits, 1.5))
	local at = num(ev.at, B.renderT + hits)
	local tl = {
		id = id,
		shape = ev.shape == "Line" and "Line" or "Circle",
		x = num(ev.x, 0),
		z = num(ev.z, 0),
		r = num(ev.r, 6),
		angle = num(ev.angle, 0),
		length = num(ev.length, 30),
		width = num(ev.width, 4),
		at = at,
		from = at - hits,
		fill = fill,
		edgeColor = edge,
		freeze = ev.freeze,
	}
	local edgePart = Fx.Part(edge, Enum.Material.Neon, 0.6)
	local fillPart = Fx.Part(fill, Enum.Material.Neon, 0.35)
	tl.edge, tl.fillPart = edgePart, fillPart
	if tl.shape == "Circle" then
		local cf = worldFrame(B, tl.x, 0.08, tl.z, 0) * CFrame.Angles(0, 0, pi / 2)
		if edgePart then
			edgePart.Shape = Enum.PartType.Cylinder
			edgePart.Size = Vector3.new(0.1, tl.r * 2, tl.r * 2)
			edgePart.CFrame = cf
		end
		if fillPart then
			fillPart.Shape = Enum.PartType.Cylinder
			fillPart.Size = Vector3.new(0.14, 0.1, 0.1)
			fillPart.CFrame = cf * CFrame.new(0.04, 0, 0)
		end
	else
		-- a line from (x, z) along angle (atan2(dz, dx) in zone space)
		local dx, dz = cos(tl.angle), sin(tl.angle)
		tl.dx, tl.dz = dx, dz
		local yaw = yawToward(dx, dz)
		tl.yaw = yaw
		if edgePart then
			edgePart.Size = Vector3.new(tl.width, 0.1, tl.length)
			edgePart.CFrame = worldFrame(B, tl.x + dx * tl.length / 2, 0.08, tl.z + dz * tl.length / 2, yaw)
		end
		if fillPart then
			fillPart.Size = Vector3.new(tl.width * 0.96, 0.14, 0.1)
		end
	end
	B.teles[id] = tl
	-- the boss winds up toward it
	if boss and boss.isBoss then
		Units.SetPose(boss, "Windup", hits, ev.attack)
		boss.windupFrom = tl.from
		boss.windupAt = tl.at
		if tl.shape == "Line" then
			boss.faceX, boss.faceZ = tl.x + (tl.dx or 0) * 10, tl.z + (tl.dz or 0) * 10
		else
			boss.faceX, boss.faceZ = tl.x, tl.z
		end
	end
end

function Tele.Free(tl)
	Fx.Free(tl.edge)
	Fx.Free(tl.fillPart)
	tl.edge, tl.fillPart = nil, nil
end

function Tele.Update(B, now)
	local t = B.renderT
	for id, tl in pairs(B.teles) do
		if t >= tl.at then
			if not tl.impactAt then
				tl.impactAt = now
				-- the hit: a flash of the shape + a shock ring / burst
				local center
				if tl.shape == "Circle" then
					center = worldPoint(B, tl.x, 0.4, tl.z)
					Fx.Ring(center, tl.r, tl.edgeColor, 18, 0.9, 0.45, 0.05)
					Fx.Burst(center, tl.fill, 12, 12, 0.6, 0.55, { up = 0.9, color2 = tl.edgeColor })
				else
					local mid = worldPoint(B, tl.x + tl.dx * tl.length / 2, 1.4, tl.z + tl.dz * tl.length / 2)
					Fx.Beam(worldFrame(B, tl.x + tl.dx * tl.length / 2, 1.4, tl.z + tl.dz * tl.length / 2, tl.yaw), tl.length, tl.width * 0.8, tl.fill, 0.4)
					Fx.Burst(mid, tl.edgeColor, 8, 10, 0.5, 0.5, { up = 0.7 })
				end
				if tl.freeze then
					local c = worldPoint(B, tl.x, 0.6, tl.z)
					Fx.Burst(c, COLORS.Ice, 10, 9, 0.55, 0.6, { material = Enum.Material.Glass, alpha = 0.2, up = 0.8 })
				end
				if tl.fillPart then
					tl.fillPart.Transparency = 0.05
				end
				local boss = B.boss
				if boss and boss.pose == "Windup" then
					Units.SetPose(boss, "Attack", 0.7)
					boss.windupAt = nil
				end
			end
			local p = (now - tl.impactAt) / 0.35
			if p >= 1 then
				Tele.Free(tl)
				B.teles[id] = nil
			else
				if tl.edge then
					tl.edge.Transparency = 0.6 + 0.4 * p
				end
				if tl.fillPart then
					tl.fillPart.Transparency = 0.05 + 0.95 * p
				end
			end
		else
			local p = clamp((t - tl.from) / max(0.05, tl.at - tl.from), 0, 1)
			local pulse = 0.5 + 0.5 * sin(now * 10)
			if tl.edge then
				tl.edge.Transparency = 0.5 + 0.2 * pulse
			end
			if tl.fillPart then
				if tl.shape == "Circle" then
					local d = max(0.1, tl.r * 2 * p)
					tl.fillPart.Size = Vector3.new(0.14, d, d)
				else
					local len = max(0.1, tl.length * p)
					tl.fillPart.Size = Vector3.new(tl.width * 0.96, 0.14, len)
					tl.fillPart.CFrame = worldFrame(B, tl.x + tl.dx * len / 2, 0.12, tl.z + tl.dz * len / 2, tl.yaw)
				end
				tl.fillPart.Transparency = 0.45 - 0.25 * p
			end
		end
	end
end

function Tele.ClearAll(B)
	for id, tl in pairs(B.teles) do
		Tele.Free(tl)
		B.teles[id] = nil
	end
end

----------------------------------------------------------------------
-- Events (played on the delayed render clock)
----------------------------------------------------------------------
local function specialColor(u, kind)
	if u and u.special and typeof(u.special.Color) == "Color3" then
		return u.special.Color
	end
	if u then
		return elementColor(u.element)
	end
	if kind == "Heal" then
		return COLORS.Heal
	end
	return COLORS.Gold
end

local function numberHeight(u)
	if u.isBoss then
		return (u.height or 20) * 0.5 + 2
	end
	return (u.height or 3) / 2 + 1.8
end

local Handlers = {}

Handlers[EV.Hit] = function(B, ev)
	local victim = B.units[tonumber(ev.to) or -1]
	local attacker = ev.from and B.units[tonumber(ev.from) or -1]
	if not victim then
		return
	end
	local dmg = num(ev.dmg, 0)
	-- attacker motion: plain attacks lunge (melee) or shoot a bolt (ranged)
	if attacker and not ev.special and not ev.zone and not ev.tele then
		if attacker.isBoss then
			if attacker.pose ~= "Windup" and attacker.pose ~= "Attack" and attacker.pose ~= "Enrage" then
				Units.SetPose(attacker, "Basic", 0.6, ev.attack)
				attacker.faceX, attacker.faceZ = victim.x, victim.z
			end
			Fx.Bolt(unitCenter(B, attacker), unitCenter(B, victim), elementColor(attacker.element), 0.7, 0.35)
		else
			local dx, dz = victim.x - attacker.x, victim.z - attacker.z
			local d = sqrt(dx * dx + dz * dz)
			if d > 0.01 then
				attacker.lungeAt = os.clock()
				attacker.lungeX, attacker.lungeZ = dx / d, dz / d
			end
			if attacker.ranged and attacker.model and not attacker.parked then
				Fx.Bolt(unitCenter(B, attacker), unitCenter(B, victim), elementColor(attacker.element), 0.42, 0.24)
			end
		end
	end
	-- victim feedback
	if not victim.isBoss and attacker then
		local dx, dz = victim.x - attacker.x, victim.z - attacker.z
		local d = sqrt(dx * dx + dz * dz)
		if d > 0.01 then
			victim.hurtAt = os.clock()
			victim.hurtX, victim.hurtZ = dx / d, dz / d
		end
	end
	if not ev.zone or math.random() < 0.5 then
		Fx.Flash(victim, (ev.elem and ev.elem > 1) and Color3.fromRGB(255, 226, 190) or COLORS.White)
	end
	local adornee = victim.root
	if not adornee or victim.parked then
		return
	end
	local text, color, px = tostring(floor(dmg + 0.5)), COLORS.White, K.NUMBER_PX
	if ev.crit then
		text = "CRIT " .. text
		color = COLORS.Gold
		px = K.CRIT_PX
	elseif ev.elem and ev.elem > 1 then
		text = text .. "!"
		color = COLORS.Strong
		px = K.NUMBER_PX + 2
	elseif ev.elem and ev.elem < 1 then
		color = COLORS.Weak
	end
	if victim.mine then
		color = (color == COLORS.White) and Color3.fromRGB(255, 196, 196) or color
	end
	if ev.special and attacker then
		color = specialColor(attacker):Lerp(COLORS.White, 0.35)
		px = max(px, K.NUMBER_PX + 2)
	end
	if dmg > 0 then
		Fx.Number(adornee, numberHeight(victim), text, color, px)
	end
	if num(ev.absorbed, 0) > 0 then
		Fx.Number(adornee, numberHeight(victim) + 0.8, "BLOCK " .. tostring(floor(ev.absorbed + 0.5)), COLORS.Shield, K.NUMBER_PX - 2, 0.8)
	end
	if ev.freeze then
		victim.iceUntil = os.clock() + num(ev.freeze, 2)
	end
end

Handlers[EV.Special] = function(B, ev)
	local u = B.units[tonumber(ev.unit) or -1]
	local kind = tostring(ev.kind or "")
	local color = specialColor(u, kind)
	local S = SPECIALS[kind] or {}
	if u and u.root and not u.parked then
		local label = tostring(ev.name or kind)
		Fx.Number(u.root, numberHeight(u) + 0.6, string.upper(label) .. "!", color:Lerp(COLORS.White, 0.2), K.CALLOUT_PX, 1.2)
		Fx.Burst(unitCenter(B, u), color, 8, 6, 0.35, 0.45, { up = 0.9, gravity = 4 })
	end
	local tx, tz = num(ev.tx, num(ev.x, 0)), num(ev.tz, num(ev.z, 0))
	if kind == "Blast" then
		local c = worldPoint(B, tx, 0.6, tz)
		local r = num(S.Radius, 7)
		Fx.Ring(c, r, color, 20, 0.8, 0.5, 0.05)
		Fx.Burst(c + Vector3.new(0, 0.8, 0), color, 16, 13, 0.6, 0.6, { color2 = COLORS.White:Lerp(color, 0.4), up = 0.8 })
	elseif kind == "Heal" then
		for _, h in ipairs(type(ev.heals) == "table" and ev.heals or {}) do
			local a = B.units[tonumber(h[1]) or -1]
			if a and a.root and not a.parked then
				Fx.Rise(unitCenter(B, a), COLORS.Heal, 8, 0.32, 0.9, 1.6)
				if num(h[2], 0) > 0 then
					Fx.Number(a.root, numberHeight(a), "+" .. tostring(floor(num(h[2], 0) + 0.5)), COLORS.Heal, K.NUMBER_PX)
				end
			end
		end
	elseif kind == "Shield" then
		local seconds = num(S.Seconds, 6)
		for _, id in ipairs(type(ev.shields) == "table" and ev.shields or {}) do
			local a = B.units[tonumber(id) or -1]
			if a and a.root and not a.parked then
				a.shieldUntil = os.clock() + seconds + 0.5
				Fx.Ring(unitCenter(B, a), 2.2, COLORS.Shield, 10, 0.4, 0.5, 0.2)
			end
		end
	elseif kind == "Pounce" then
		if u then
			local a = worldPoint(B, num(ev.x, u.x), 1.4, num(ev.z, u.z))
			local b = worldPoint(B, tx, 1.4, tz)
			Fx.Trail(a, b, color, 9, 0.5)
			u.hopAt = os.clock()
		end
		Fx.Burst(worldPoint(B, tx, 1.2, tz), color, 12, 11, 0.5, 0.55, { up = 0.7, color2 = COLORS.White })
	elseif kind == "Freeze" then
		local c = worldPoint(B, tx, 0.5, tz)
		local r = num(S.Radius, 6)
		Fx.Ring(c, r, COLORS.Ice, 16, 0.7, 0.55, 0.1)
		Fx.Burst(c + Vector3.new(0, 0.6, 0), COLORS.Ice, 14, 10, 0.55, 0.7, { material = Enum.Material.Glass, alpha = 0.15, up = 0.8, color2 = COLORS.White })
		local stun = num(S.Stun, 1) + 0.4
		for _, id in ipairs(type(ev.stunned) == "table" and ev.stunned or {}) do
			local a = B.units[tonumber(id) or -1]
			if a then
				a.iceUntil = os.clock() + stun
			end
		end
	elseif kind == "Beam" then
		local length = num(S.Length, 26)
		local width = num(S.Width, 4)
		local angle = num(ev.angle, 0)
		local dx, dz = cos(angle), sin(angle)
		local sx, sz = num(ev.x, u and u.x or 0), num(ev.z, u and u.z or 0)
		local cf = worldFrame(B, sx + dx * length / 2, 1.6, sz + dz * length / 2, yawToward(dx, dz))
		Fx.Beam(cf, length, width * 0.7, color, 0.5)
		Fx.Burst(worldPoint(B, sx + dx * length, 1.6, sz + dz * length), color, 8, 8, 0.4, 0.45, { up = 0.5 })
	elseif kind == "Storm" then
		-- the Zone event that follows draws the cloud
		Fx.Burst(worldPoint(B, tx, 5, tz), COLORS.StormLight, 6, 5, 0.6, 0.5, { up = 0.3, gravity = 2 })
	end
end

Handlers[EV.Zone] = function(B, ev)
	local kind = tostring(ev.kind or "")
	local x, z = num(ev.x, 0), num(ev.z, 0)
	local r = num(ev.r, 6)
	local seconds = max(0.5, num(ev.seconds, 4))
	local floorCF = worldFrame(B, x, 0, z, 0)
	if kind == "Storm" then
		local u = B.units[tonumber(ev.unit) or -1]
		Fx.Zone(floorCF, r, seconds, specialColor(u, "Storm"), "Storm")
	else
		local color = Color3.fromRGB(255, 120, 60)
		local BB = lazyBoss()
		if BB and B.BossId then
			local ok, f = pcall(BB.TelegraphColor, B.BossId, ev.attack)
			if ok and typeof(f) == "Color3" then
				color = f
			end
		end
		Fx.Zone(floorCF, r, seconds, color, "Linger")
	end
end

Handlers[EV.KO] = function(B, ev)
	local u = B.units[tonumber(ev.unit) or -1]
	if not u then
		return
	end
	if u.root and not u.parked then
		Fx.Number(u.root, numberHeight(u) + 0.4, "KO!", Color3.fromRGB(220, 226, 240), K.CALLOUT_PX, 1.1)
		if not u.isBoss and not u.poofed then
			u.poofed = true
			Fx.Burst(unitCenter(B, u), Color3.fromRGB(236, 240, 250), 12, 9, 0.5, 0.6, { color2 = elementColor(u.element), alpha = 0.05 })
		elseif u.isBoss then
			Fx.Burst(unitCenter(B, u), elementColor(u.element), 24, 16, 0.9, 1.1, { color2 = COLORS.White, up = 0.9 })
		end
	end
	u.hp = 0
	u.state = S_DOWN
	if B.focus == u.id then
		B.focus = nil
	end
end

Handlers[EV.Telegraph] = function(B, ev)
	Tele.Start(B, ev)
end

Handlers[EV.Spawn] = function(B, ev)
	for _, info in ipairs(type(ev.units) == "table" and ev.units or {}) do
		local u = Units.Add(B, info)
		if u then
			u.spawnFx = true
		end
	end
	if ev.wave then
		B.wave = num(ev.wave, 0)
		local boss = B.boss
		if boss and boss.root then
			Fx.Number(boss.root, numberHeight(boss) + 1, "MINIONS!", COLORS.Enemy:Lerp(COLORS.White, 0.3), K.CALLOUT_PX, 1.4)
		end
	end
	Hud.Rebuild()
end

Handlers[EV.Enrage] = function(B, ev)
	B.enraged = true
	local boss = B.units[tonumber(ev.unit) or -1] or B.boss
	if boss and boss.model then
		local BB = lazyBoss()
		if BB then
			pcall(BB.SetEnraged, boss.model, true)
		end
		Units.SetPose(boss, "Enrage", 1.3)
		if boss.root then
			Fx.Number(boss.root, numberHeight(boss) + 1, "ENRAGED!", COLORS.Enemy, K.CRIT_PX, 1.6)
		end
		Fx.Ring(unitCenter(B, boss), 14, COLORS.Enemy, 24, 1, 0.8, 0.1)
	end
end

Handlers[EV.Order] = function(B, ev)
	if ev.owner ~= myUserId() then
		return
	end
	if ev.order == "Retreat" then
		B.order = "Retreat"
		B.retreatAt = os.clock()
		B.focus = nil
	elseif ev.order == "Attack" then
		B.order = "Attack"
		B.focus = tonumber(ev.target)
	end
end

Handlers[EV.Leave] = function(B, ev)
	for _, id in ipairs(type(ev.units) == "table" and ev.units or {}) do
		local u = B.units[tonumber(id) or -1]
		if u then
			if u.root and not u.parked then
				Fx.Burst(unitCenter(B, u), Color3.fromRGB(226, 232, 246), 8, 7, 0.45, 0.5, { alpha = 0.1 })
			end
			Units.Remove(B, u.id)
		end
	end
	Hud.Rebuild()
end

Handlers[EV.End] = function(B)
	B.simEnded = true
end

function Net.PlayDue(B, now)
	local q = B.evq
	if #q == 0 then
		return
	end
	local played = 0
	local t = B.renderT
	while #q > 0 and (q[1].t <= t or #q > 400) do
		local item = table.remove(q, 1)
		local fn = Handlers[item.ev.type]
		if fn then
			local ok, err = pcall(fn, B, item.ev)
			if not ok then
				warnOnce("event_" .. tostring(item.ev.type), "event " .. tostring(item.ev.type) .. " failed: " .. tostring(err))
			end
		end
		played = played + 1
		if played > 120 then
			break
		end
	end
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------
local function label(parent, text, role, size, props)
	local l = Theme.Label(text, role, { Size = size, Stroke = 0.15, Outline = 2 })
	l.BackgroundTransparency = 1
	if props then
		for key, value in pairs(props) do
			l[key] = value
		end
	end
	l.Parent = parent
	return l
end

local function card(parent, name, props)
	local f = Theme.Panel(props)
	f.Name = name
	f.Parent = parent
	return f
end

local function smallPill(parent, text, color, props)
	local dark = Theme.Darken(color, 0.62)
	local l = Theme.Label(text, "Heading", { Size = 15, Stroke = 0.1, StrokeColor = dark, Outline = 1.5, OutlineColor = dark })
	l.Name = "Pill"
	l.BackgroundTransparency = 0
	l.BackgroundColor3 = color
	l.BorderSizePixel = 0
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, 22)
	l.TextXAlignment = Enum.TextXAlignment.Center
	Theme.Corner(l, UDim.new(0, 11))
	Theme.Stroke(l, COLORS.Navy, 2, 0)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, l)
	if props then
		for key, value in pairs(props) do
			l[key] = value
		end
	end
	l.Parent = parent
	return l
end

local function bar(parent, name, height, color, props)
	if CloudUI and type(CloudUI.Bar) == "function" then
		local b = CloudUI.Bar({ Name = name, Height = height, Color = color, Parent = parent, TextSize = props and props.TextSize })
		if props then
			if props.Size then
				b.Root.Size = props.Size
			end
			if props.Position then
				b.Root.Position = props.Position
			end
			if props.AnchorPoint then
				b.Root.AnchorPoint = props.AnchorPoint
			end
		end
		return b
	end
	-- fallback without CloudUI
	local root = make("Frame", { Name = name, BackgroundColor3 = COLORS.Track, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, height) }, parent)
	if props then
		for key, value in pairs(props) do
			if key ~= "TextSize" then
				root[key] = value
			end
		end
	end
	Theme.Corner(root, UDim.new(0, 6))
	local fill = make("Frame", { Name = "Fill", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, root)
	Theme.Corner(fill, UDim.new(0, 6))
	local text = label(root, "", "Heading", 15, { Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	return {
		Root = root,
		Fill = fill,
		Label = text,
		SetFraction = function(f)
			fill.Size = UDim2.fromScale(clamp(f, 0, 1), 1)
		end,
		SetText = function(t)
			text.Text = tostring(t or "")
		end,
		SetColor = function(c)
			fill.BackgroundColor3 = c
		end,
	}
end

-- a thin bar without text (the special meter, enemy chips): returns { Root, Fill }
local function thinBar(parent, name, height, color, props)
	local root = make("Frame", {
		Name = name,
		BackgroundColor3 = COLORS.Track,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height),
	}, parent)
	if props then
		for key, value in pairs(props) do
			root[key] = value
		end
	end
	Theme.Corner(root, UDim.new(0, max(2, floor(height / 2))))
	Theme.Stroke(root, COLORS.Navy, 2, 0)
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, root)
	Theme.Corner(fill, UDim.new(0, max(2, floor(height / 2))))
	return { Root = root, Fill = fill, frac = 1 }
end

local function setThin(b, frac)
	frac = clamp(frac, 0, 1)
	if abs(frac - (b.frac or -1)) > 0.003 then
		b.frac = frac
		b.Fill.Size = UDim2.fromScale(max(frac, 0.001), 1)
		b.Fill.Visible = frac > 0.002
	end
end

-- a rough width of `text` in px at `size` (bold display fonts run ~0.62 em per character)
local function textWidth(text, size)
	return #tostring(text or "") * size * 0.62
end

local function setText(lbl, text)
	if lbl and lbl.Text ~= text then
		lbl.Text = text
	end
end

local function keyChip(parent, text, props)
	local chip = make("Frame", {
		Name = "Key",
		BackgroundColor3 = COLORS.Navy,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(30, 26),
		ZIndex = 6,
	}, parent)
	Theme.Corner(chip, UDim.new(0, 7))
	Theme.Stroke(chip, COLORS.White, 1.5, 0.35)
	local l = label(chip, text, "Heading", 15, { Name = "Text", Size = UDim2.fromScale(1, 1), ZIndex = 7, TextXAlignment = Enum.TextXAlignment.Center })
	if props then
		for key, value in pairs(props) do
			chip[key] = value
		end
	end
	return chip, l
end

local function button(parent, name, text, style, size, callback)
	local b
	if CloudUI and type(CloudUI.Button) == "function" then
		b = CloudUI.Button({ Name = name, Text = text, Style = style, Size = size, TextSize = 22, Parent = parent, Callback = callback })
	else
		b = make("TextButton", { Name = name, Text = text, Size = size, BackgroundColor3 = Theme.Buttons[style] or COLORS.Ally, AutoButtonColor = true }, parent)
		Theme.Style(b, "Button", { Size = 22 })
		Theme.Corner(b, UDim.new(0, 12))
		b.Activated:Connect(function()
			callback(b)
		end)
	end
	return b
end

-- every HUD text stays >= MIN_TEXT_PX on the screen: design sizes grow to MIN_TEXT_PX / factor on small screens
-- (the 1080p design sizes are kept as the attribute BaseText)
function Hud.FixText(root, factor)
	local minDesign = math.ceil(K.MIN_TEXT_PX / max(0.05, factor) - 1e-6)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			local base = d:GetAttribute("BaseText")
			if type(base) ~= "number" then
				base = d.TextSize
				d:SetAttribute("BaseText", base)
			end
			local want = max(base, minDesign)
			if d.TextSize ~= want then
				d.TextSize = want
			end
		end
	end
end

local function setDisabled(b, disabled)
	if (b:GetAttribute("Disabled") == true) ~= (disabled == true) then
		b:SetAttribute("Disabled", disabled == true)
	end
end


function Hud.Ensure()
	if Hud.gui and Hud.gui.Parent then
		return true
	end
	local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return false
	end
	local old = playerGui:FindFirstChild(K.GUI_NAME)
	if old then
		old:Destroy()
	end
	local gui = make("ScreenGui", {
		Name = K.GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = K.DISPLAY_ORDER,
		Enabled = true,
	}, playerGui)
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	Hud.scale = make("UIScale", { Name = "ReadScale", Scale = 1 }, root)
	Hud.gui, Hud.root = gui, root
	Hud.top = card(root, "TopCard", { Visible = false, AnchorPoint = Vector2.new(0.5, 0) })
	Hud.team = make("Frame", { Name = "Team", BackgroundTransparency = 1, Visible = false }, root)
	Hud.cmd = make("Frame", { Name = "Commands", BackgroundTransparency = 1, Visible = false }, root)
	Hud.result = card(root, "ResultCard", { Visible = false })
	Hud.rows = {}
	Hud.chips = {}
	Hud.BuildCommands()
	return true
end

-- the screen in design pixels + the layout kind
function Hud.Metrics()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local inset = 36
	local ok, a = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(a) == "Vector2" then
		inset = a.Y
	end
	local f = Theme.ScreenFactor(vp.Y)
	local w = vp.X / f
	local h = max(200, vp.Y - inset) / f
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local compact = touch or w < 1150 or h < 640
	return { W = w, H = h, F = f, Compact = compact, Touch = touch, Landscape = w / h > 1.3, VX = vp.X, VY = vp.Y, Inset = inset }
end

function Hud.KeyText(kind, slot)
	if St.gamepad then
		if kind == "Attack" then
			return "X"
		elseif kind == "Retreat" then
			return "Y"
		end
		return ({ "LB", "RB", "LT", "RT" })[slot] or ""
	end
	if kind == "Attack" then
		return "F"
	elseif kind == "Retreat" then
		return "R"
	end
	return tostring(slot)
end

function Hud.BuildCommands()
	local cmd = Hud.cmd
	Hud.attack = button(cmd, "AttackButton", "ATTACK", "Red", UDim2.fromOffset(215, K.CMD_H), function()
		BattleController.Command("Attack", nil)
	end)
	Hud.retreat = button(cmd, "RetreatButton", "RETREAT", "Blue", UDim2.fromOffset(215, K.CMD_H), function()
		BattleController.Command("Retreat")
	end)
	Hud.attackKey = keyChip(Hud.attack, "F", { Position = UDim2.fromOffset(-6, -8) })
	Hud.retreatKey = keyChip(Hud.retreat, "R", { Position = UDim2.fromOffset(-6, -8) })
	for _, b in ipairs({ Hud.attack, Hud.retreat }) do
		local ring = make("Frame", {
			Name = "ActiveRing",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 10, 1, 10),
			Position = UDim2.fromOffset(-5, -5),
			Visible = false,
			ZIndex = 0,
		}, b)
		Theme.Corner(ring, UDim.new(0, 16))
		Theme.Stroke(ring, COLORS.Gold, 3, 0)
	end
end

local function rowFor(i)
	local row = Hud.rows[i]
	if row then
		return row
	end
	row = {}
	local f = make("Frame", { Name = "Row" .. i, BackgroundColor3 = COLORS.Panel, BackgroundTransparency = 0.15, BorderSizePixel = 0 }, Hud.team)
	Theme.Corner(f, UDim.new(0, 12))
	Theme.Stroke(f, COLORS.Navy, 2, 0)
	row.Frame = f
	-- slot chip (element coloured, with the key)
	local chip = make("Frame", { Name = "Slot", BackgroundColor3 = COLORS.Ally, BorderSizePixel = 0 }, f)
	Theme.Corner(chip, UDim.new(0, 10))
	Theme.Stroke(chip, COLORS.Navy, 2, 0)
	row.Chip = chip
	row.ChipText = label(chip, tostring(i), "Display", 24, { Name = "Text", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	row.Name = label(f, "", "Body", 18, { Name = "PetName", RichText = true, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	row.Level = label(f, "", "Label", 16, { Name = "Level", TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = COLORS.Muted })
	row.Element = smallPill(f, "", COLORS.Ally, { Name = "Element" })
	row.Hp = bar(f, "Hp", 22, COLORS.Mine, { TextSize = 15 })
	row.Meter = thinBar(f, "Meter", 8, COLORS.Gold)
	-- the special button
	row.Glow = make("Frame", { Name = "Glow", BackgroundColor3 = COLORS.Gold, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, f)
	Theme.Corner(row.Glow, UDim.new(0, 16))
	local sb = make("TextButton", { Name = "Special", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(110, 120, 150), BorderSizePixel = 0, ZIndex = 2 }, f)
	Theme.Corner(sb, UDim.new(0, 12))
	row.SpecialStroke = Theme.Stroke(sb, COLORS.Navy, 3, 0)
	row.SpecialTop = label(sb, "SPECIAL", "Button", 20, { Name = "Top", TextXAlignment = Enum.TextXAlignment.Center })
	row.SpecialSub = label(sb, "", "Label", 15, { Name = "Sub", TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
	row.Special = sb
	-- the compact card: the whole card is the special button
	row.CardHit = make("TextButton", { Name = "CardHit", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8, Visible = false }, f)
	local slot = i
	sb.Activated:Connect(function()
		BattleController.Command("Special", Hud.SlotOfRow(slot))
	end)
	row.CardHit.Activated:Connect(function()
		BattleController.Command("Special", Hud.SlotOfRow(slot))
	end)
	Hud.rows[i] = row
	return row
end

function Hud.SlotOfRow(i)
	local row = Hud.rows[i]
	return row and row.slot or i
end

-- lays the team rows out (wide: rows; compact: cards)
function Hud.LayoutTeam(m, units)
	local n = #units
	for i = 1, max(n, #Hud.rows) do
		local row = (i <= n) and rowFor(i) or Hud.rows[i]
		if row then
			row.Frame.Visible = i <= n
		end
	end
	if n == 0 then
		return 0, 0
	end
	if not m.Compact then
		local w = K.TEAM_W
		local y = K.PAD + K.HEAD_H
		for i = 1, n do
			local row = Hud.rows[i]
			local f = row.Frame
			f.Size = UDim2.fromOffset(w - 2 * K.PAD, K.ROW_H)
			f.Position = UDim2.fromOffset(K.PAD, y)
			row.Chip.Size = UDim2.fromOffset(40, 40)
			row.Chip.Position = UDim2.fromOffset(8, 15)
			row.Chip.Visible = true
			row.ChipText.TextSize = 24
			row.ChipText:SetAttribute("BaseText", 24)
			local mid = (w - 2 * K.PAD) - 144 - 8 - 56 -- the middle column between the slot chip and the button
			local pillW = 22 + textWidth(units[i].element or "?", max(15, math.ceil(K.MIN_TEXT_PX / max(0.05, m.F))))
			row.Name.Position = UDim2.fromOffset(56, 5)
			row.Name.Size = UDim2.fromOffset(max(60, mid - pillW - 8), 24)
			row.Name.TextSize = 18
			row.Name:SetAttribute("BaseText", 18)
			row.Level.Visible = false
			row.Element.Visible = true
			row.Element.AnchorPoint = Vector2.new(1, 0)
			row.Element.Position = UDim2.fromOffset(56 + mid, 6)
			row.Hp.Root.Visible = true
			row.Hp.Root.Position = UDim2.fromOffset(56, 32)
			row.Hp.Root.Size = UDim2.fromOffset(mid, 22)
			row.Meter.Root.Position = UDim2.fromOffset(56, 58)
			row.Meter.Root.Size = UDim2.fromOffset(mid, 8)
			row.Special.Visible = true
			row.Special.Size = UDim2.fromOffset(136, 56)
			row.Special.Position = UDim2.new(1, -144, 0, 7)
			row.Glow.Size = UDim2.fromOffset(146, 66)
			row.Glow.Position = UDim2.new(1, -149, 0, 2)
			row.SpecialTop.TextSize = 20
			row.SpecialTop:SetAttribute("BaseText", 20)
			row.SpecialTop.Position = UDim2.fromOffset(0, 5)
			row.SpecialTop.Size = UDim2.new(1, 0, 0, 24)
			row.SpecialSub.Visible = true
			row.SpecialSub.Position = UDim2.fromOffset(6, 30)
			row.SpecialSub.Size = UDim2.new(1, -12, 0, 20)
			row.CardHit.Visible = false
			y = y + K.ROW_H + K.ROW_GAP
		end
		return w, y - K.ROW_GAP + K.PAD
	end
	-- compact cards in a row
	local avail = m.W - 16
	if m.Landscape then
		avail = avail - (2 * K.TOUCH_W + 30)
	end
	local cw = min(K.CARD_W, floor((avail - (n - 1) * 8) / n))
	for i = 1, n do
		local row = Hud.rows[i]
		local f = row.Frame
		f.Size = UDim2.fromOffset(cw, K.CARD_H)
		f.Position = UDim2.fromOffset((i - 1) * (cw + 8), 0)
		row.Chip.Visible = true
		row.Chip.Size = UDim2.fromOffset(26, 26)
		row.Chip.Position = UDim2.fromOffset(4, 4)
		row.ChipText.TextSize = 18
		row.ChipText:SetAttribute("BaseText", 18)
		row.Name.Position = UDim2.fromOffset(34, 6)
		row.Name.Size = UDim2.fromOffset(cw - 38, 22)
		row.Name.TextSize = 16
		row.Name:SetAttribute("BaseText", 16)
		row.Level.Visible = false
		row.Element.Visible = false
		row.Hp.Root.Visible = true
		row.Hp.Root.Position = UDim2.fromOffset(5, 32)
		row.Hp.Root.Size = UDim2.fromOffset(cw - 10, 21)
		row.Meter.Root.Position = UDim2.fromOffset(5, 57)
		row.Meter.Root.Size = UDim2.fromOffset(cw - 10, 8)
		row.Special.Visible = true
		row.Special.Size = UDim2.fromOffset(cw - 10, 28)
		row.Special.Position = UDim2.fromOffset(5, 68)
		row.Glow.Size = UDim2.fromOffset(cw - 2, 36)
		row.Glow.Position = UDim2.fromOffset(1, 64)
		row.SpecialTop.TextSize = 17
		row.SpecialTop:SetAttribute("BaseText", 17)
		row.SpecialTop.Position = UDim2.fromOffset(0, 2)
		row.SpecialTop.Size = UDim2.new(1, 0, 1, -4)
		row.SpecialSub.Visible = false
		row.CardHit.Visible = true
	end
	return n * cw + (n - 1) * 8, K.CARD_H
end

-- the enemy chips of the top card (trials and duels)
local function chipFor(i)
	local chip = Hud.chips[i]
	if chip then
		return chip
	end
	chip = {}
	local f = make("TextButton", { Name = "Enemy" .. i, Text = "", AutoButtonColor = false, BackgroundColor3 = COLORS.Panel, BackgroundTransparency = 0.05, BorderSizePixel = 0 }, Hud.top)
	Theme.Corner(f, UDim.new(0, 10))
	chip.Stroke = Theme.Stroke(f, COLORS.Navy, 2, 0)
	chip.Stripe = make("Frame", { Name = "Element", BorderSizePixel = 0, Size = UDim2.new(1, -12, 0, 4), Position = UDim2.fromOffset(6, 3) }, f)
	Theme.Corner(chip.Stripe, UDim.new(0, 2))
	chip.Name = label(f, "", "Label", 15, { Name = "PetName", Position = UDim2.fromOffset(6, 8), Size = UDim2.new(1, -12, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
	chip.Hp = thinBar(f, "Hp", 12, COLORS.Enemy, { Position = UDim2.fromOffset(6, 32), Size = UDim2.new(1, -12, 0, 12) })
	chip.Frame = f
	local index = i
	f.Activated:Connect(function()
		local id = chip.unitId
		if id then
			BattleController.Focus(id)
		end
		return index
	end)
	Hud.chips[i] = chip
	return chip
end

-- lists the units the HUD shows: my team by slot, enemies (non-boss) in id order
function Hud.Lists(B)
	local mine = {}
	for slot = 1, 4 do
		if B.mine[slot] then
			mine[#mine + 1] = B.mine[slot]
		end
	end
	local enemies = {}
	for _, u in ipairs(B.list) do
		if not u.ally and not u.isBoss and u.kind ~= "Minion" then
			enemies[#enemies + 1] = u
		end
	end
	return mine, enemies
end

-- (re)builds the HUD for the drawn battle and lays it out for the screen
function Hud.Rebuild()
	local B = St.battle
	if not Hud.Ensure() then
		return
	end
	local m = Hud.Metrics()
	Hud.m = m
	Hud.scale.Scale = m.F
	Hud.root.Size = UDim2.new(1 / m.F, 0, 1 / m.F, 0)
	if not B then
		Hud.top.Visible = false
		Hud.team.Visible = false
		Hud.cmd.Visible = false
		return
	end
	local isFighting = B.Fighter and not B.ended
	local mine, enemies = Hud.Lists(B)
	Hud.mineList = mine
	Hud.enemyList = enemies
	-- top card ------------------------------------------------------------------------------
	local top = Hud.top
	local topW = m.Compact and min(K.TOP_W_COMPACT, m.W - 16) or K.TOP_W
	top.Visible = not B.ended or not B.Fighter
	top.Position = UDim2.new(0.5, 0, 0, 6)
	if not Hud.topBuilt then
		Hud.topBuilt = true
		Hud.mode = smallPill(top, "", COLORS.Ally, { Name = "Mode", Position = UDim2.fromOffset(K.PAD, 10) })
		Hud.title = label(top, "", "Heading", 22, { Name = "Title", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
		Hud.timer = label(top, "", "Display", 26, { Name = "Timer", TextXAlignment = Enum.TextXAlignment.Right })
		Hud.bossBar = bar(top, "BossHp", 28, COLORS.Enemy, { TextSize = 18 })
		Hud.pills = make("Frame", { Name = "Pills", BackgroundTransparency = 1 }, top)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, Hud.pills)
		Hud.bossElement = smallPill(Hud.pills, "", COLORS.Enemy, { Name = "Element", LayoutOrder = 1 })
		Hud.enragePill = smallPill(Hud.pills, "ENRAGED", COLORS.Enemy, { Name = "Enraged", LayoutOrder = 2, Visible = false })
		Hud.minionPill = smallPill(Hud.pills, "", Color3.fromRGB(150, 110, 220), { Name = "Minions", LayoutOrder = 3, Visible = false })
		Hud.playersPill = smallPill(Hud.pills, "", COLORS.Ally, { Name = "Players", LayoutOrder = 4, Visible = false })
		Hud.sideBars = {
			bar(top, "Side1", 22, COLORS.Ally, { TextSize = 15 }),
			bar(top, "Side2", 22, COLORS.Enemy, { TextSize = 15 }),
		}
	end
	local y = K.PAD
	local pillSize = max(15, math.ceil(K.MIN_TEXT_PX / max(0.05, m.F)))
	local modeW = 30 + textWidth(Hud.ModeText(B), pillSize) * 1.2
	Hud.title.Position = UDim2.fromOffset(K.PAD + modeW + 10, y)
	Hud.title.Size = UDim2.fromOffset(topW - 2 * K.PAD - modeW - 10 - 84, 26)
	Hud.timer.Position = UDim2.new(1, -K.PAD - 80, 0, y - 2)
	Hud.timer.Size = UDim2.fromOffset(80, 30)
	y = y + 34
	local raid = B.Mode == "Raid" and B.boss ~= nil
	Hud.bossBar.Root.Visible = raid
	Hud.pills.Visible = raid
	Hud.sideBars[1].Root.Visible = false
	Hud.sideBars[2].Root.Visible = false
	for _, chip in ipairs(Hud.chips) do
		chip.Frame.Visible = false
	end
	if raid then
		Hud.bossBar.Root.Position = UDim2.fromOffset(K.PAD, y)
		Hud.bossBar.Root.Size = UDim2.fromOffset(topW - 2 * K.PAD, 28)
		Hud.bossBar.SetColor(elementColor(B.boss.element))
		y = y + 34
		Hud.pills.Position = UDim2.fromOffset(K.PAD, y)
		Hud.pills.Size = UDim2.fromOffset(topW - 2 * K.PAD, 24)
		setText(Hud.bossElement, tostring(B.boss.element or "?"))
		Hud.bossElement.BackgroundColor3 = elementColor(B.boss.element)
		y = y + 28
	elseif not isFighting then
		-- spectator of a duel / trial: one HP bar per side
		for s = 1, 2 do
			local sb = Hud.sideBars[s]
			sb.Root.Visible = true
			sb.Root.Position = UDim2.fromOffset(K.PAD + (s - 1) * ((topW - 2 * K.PAD) / 2 + 4), y)
			sb.Root.Size = UDim2.fromOffset((topW - 2 * K.PAD) / 2 - 4, 22)
		end
		y = y + 28
	else
		local n = min(#enemies, 6)
		local gap = 6
		local cw = min(150, floor((topW - 2 * K.PAD - (n - 1) * gap) / max(1, n)))
		local x0 = floor((topW - (n * cw + (n - 1) * gap)) / 2)
		for i = 1, n do
			local chip = chipFor(i)
			local u = enemies[i]
			chip.unitId = u.id
			chip.Frame.Visible = true
			chip.Frame.Size = UDim2.fromOffset(cw, 50)
			chip.Frame.Position = UDim2.fromOffset(x0 + (i - 1) * (cw + gap), y)
			chip.Stripe.BackgroundColor3 = elementColor(u.element)
			setText(chip.Name, u.name)
			chip.boss = u.kind == "MiniBoss"
		end
		y = y + (n > 0 and 56 or 0)
	end
	top.Size = UDim2.fromOffset(topW, y + K.PAD - 4)
	Hud.topH = y + K.PAD - 4
	-- team + commands ---------------------------------------------------------------------------
	Hud.team.Visible = isFighting
	Hud.cmd.Visible = isFighting
	if isFighting then
		for i, u in ipairs(mine) do
			local row = rowFor(i)
			row.slot = u.slot
			row.unitId = u.id
			row.Chip.BackgroundColor3 = elementColor(u.element)
			setText(row.ChipText, Hud.KeyText("Special", u.slot))
			if m.Compact then
				setText(row.Name, u.name)
			else
				-- the level first (muted), so a long name is what gets cut
				setText(row.Name, '<font color="#C9D6F2">Lv ' .. tostring(floor(u.level)) .. "</font> " .. u.name)
			end
			setText(row.Level, "Lv " .. tostring(floor(u.level)))
			setText(row.Element, tostring(u.element or "?"))
			row.Element.BackgroundColor3 = elementColor(u.element)
			local special = u.special
			row.kind = special and special.Kind or nil
			setText(row.SpecialSub, special and tostring(special.Name or special.Kind) or "No special")
			row.last = nil
		end
		local tw, th = Hud.LayoutTeam(m, mine)
		if not m.Compact then
			-- the team card: a panel behind the rows, bottom right
			if not Hud.teamBack then
				Hud.teamBack = card(Hud.team, "Back", { ZIndex = 0 })
				Hud.teamTitle = label(Hud.team, "YOUR TEAM", "Heading", 20, { Name = "Header", Position = UDim2.fromOffset(K.PAD + 4, K.PAD), Size = UDim2.fromOffset(160, 26), TextXAlignment = Enum.TextXAlignment.Left })
				Hud.focusPill = make("TextButton", { Name = "Focus", Text = "", AutoButtonColor = false, BackgroundColor3 = COLORS.Enemy, BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), AnchorPoint = Vector2.new(1, 0) }, Hud.team)
				Theme.Corner(Hud.focusPill, UDim.new(0, 13))
				Theme.Stroke(Hud.focusPill, COLORS.Navy, 2, 0)
				make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, Hud.focusPill)
				Hud.focusText = label(Hud.focusPill, "", "Heading", 15, { Name = "Text", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26) })
				Hud.focusPill.Activated:Connect(function()
					BattleController.Focus(nil)
				end)
			end
			Hud.teamBack.Visible = true
			Hud.teamTitle.Visible = true
			Hud.teamBack.Size = UDim2.fromScale(1, 1)
			Hud.team.AnchorPoint = Vector2.new(1, 1)
			Hud.team.Size = UDim2.fromOffset(tw, th)
			Hud.team.Position = UDim2.new(1, -K.EDGE, 1, -K.EDGE)
			Hud.focusPill.Position = UDim2.new(1, -K.PAD - 2, 0, K.PAD)
			-- commands above the team card
			Hud.cmd.AnchorPoint = Vector2.new(1, 1)
			Hud.cmd.Size = UDim2.fromOffset(tw, K.CMD_H)
			Hud.cmd.Position = UDim2.new(1, -K.EDGE, 1, -K.EDGE - th - 14)
			local bw = floor((tw - 12) / 2)
			Hud.attack.Size = UDim2.fromOffset(bw, K.CMD_H)
			Hud.attack.Position = UDim2.fromOffset(0, 0)
			Hud.retreat.Size = UDim2.fromOffset(bw, K.CMD_H)
			Hud.retreat.Position = UDim2.fromOffset(bw + 12, 0)
			Hud.attack.TextSize = 24
			Hud.retreat.TextSize = 24
			Hud.attack:SetAttribute("BaseText", 24)
			Hud.retreat:SetAttribute("BaseText", 24)
		else
			if Hud.teamBack then
				Hud.teamBack.Visible = false
				Hud.teamTitle.Visible = false
				Hud.focusPill.Visible = false
			end
			Hud.team.AnchorPoint = Vector2.new(0.5, 0)
			Hud.team.Size = UDim2.fromOffset(tw, th)
			local teamY = 6 + Hud.topH + 8
			local bw, bh = K.TOUCH_W, K.TOUCH_H
			local cx = m.W / 2
			if m.Landscape and cx + tw / 2 > m.W - (2 * bw + 30) then
				cx = (m.W - (2 * bw + 30)) / 2
			end
			Hud.team.Position = UDim2.fromOffset(cx, teamY)
			-- big touch buttons at the right edge, between the currency pill (top right) and RUN / DASH (bottom right)
			Hud.cmd.AnchorPoint = Vector2.new(1, 0)
			if m.Landscape then
				Hud.cmd.Size = UDim2.fromOffset(2 * bw + 10, bh)
				Hud.cmd.Position = UDim2.fromOffset(m.W - 8, floor(m.H * 0.3))
				Hud.attack.Position = UDim2.fromOffset(0, 0)
				Hud.retreat.Position = UDim2.fromOffset(bw + 10, 0)
			else
				Hud.cmd.Size = UDim2.fromOffset(bw, 2 * bh + 12)
				Hud.cmd.Position = UDim2.fromOffset(m.W - 8, floor(m.H * 0.47))
				Hud.attack.Position = UDim2.fromOffset(0, 0)
				Hud.retreat.Position = UDim2.fromOffset(0, bh + 12)
			end
			Hud.attack.Size = UDim2.fromOffset(bw, bh)
			Hud.retreat.Size = UDim2.fromOffset(bw, bh)
			Hud.attack.TextSize = 20
			Hud.retreat.TextSize = 20
			Hud.attack:SetAttribute("BaseText", 20)
			Hud.retreat:SetAttribute("BaseText", 20)
		end
		Hud.attackKey.Visible = not m.Touch
		Hud.retreatKey.Visible = not m.Touch
		Hud.Keys()
	end
	Hud.TrimButton(Hud.attack, m.Compact)
	Hud.TrimButton(Hud.retreat, m.Compact)
	Hud.FixText(Hud.root, m.F)
	Hud.last = {}
	Hud.Update(B, os.clock(), true)
end

-- compact buttons: less side padding (CloudUI pads 10 px), so ATTACK / RETREAT fit at a readable size
function Hud.TrimButton(b, compact)
	local pad = b and b:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, compact and 3 or 10)
		pad.PaddingRight = UDim.new(0, compact and 3 or 10)
	end
end

function Hud.Keys()
	if not Hud.attackKey then
		return
	end
	local a = Hud.attackKey:FindFirstChild("Text")
	if a then
		setText(a, Hud.KeyText("Attack"))
	end
	local r = Hud.retreatKey:FindFirstChild("Text")
	if r then
		setText(r, Hud.KeyText("Retreat"))
	end
	-- the slot chip of a team row is the key of its SPECIAL (1-4, or LB / RB / LT / RT on a gamepad)
	for _, row in ipairs(Hud.rows) do
		if row.ChipText and row.slot then
			setText(row.ChipText, Hud.KeyText("Special", row.slot))
		end
	end
end

-- per-frame HUD values (writes only on change)
function Hud.Update(B, now, force)
	if not Hud.gui or not B then
		return
	end
	local last = Hud.last or {}
	Hud.last = last
	-- top card
	local modeText, modeColor = Hud.ModeText(B)
	if last.mode ~= modeText then
		last.mode = modeText
		Hud.mode.Text = modeText
		Hud.mode.BackgroundColor3 = modeColor
	end
	local title = Hud.TitleText(B)
	if last.title ~= title then
		last.title = title
		Hud.title.Text = title
	end
	local left = B.TimeLimit > 0 and (B.TimeLimit - B.renderT) or 0
	local timerText = B.TimeLimit > 0 and fmtTime(left) or ""
	if last.timer ~= timerText then
		last.timer = timerText
		Hud.timer.Text = timerText
		Hud.timer.TextColor3 = (left < 15 and B.TimeLimit > 0) and COLORS.Enemy:Lerp(COLORS.White, 0.25) or COLORS.White
	end
	if B.Mode == "Raid" and B.boss then
		local boss = B.boss
		local frac = clamp(boss.hp / boss.maxHp, 0, 1)
		if force or last.bossHp ~= boss.hp or last.bossMax ~= boss.maxHp then
			last.bossHp, last.bossMax = boss.hp, boss.maxHp
			Hud.bossBar.SetFraction(frac, false)
			Hud.bossBar.SetText(Theme.ShortNumber(clamp(boss.hp, 0, boss.maxHp)) .. " / " .. Theme.ShortNumber(boss.maxHp))
		end
		if last.enraged ~= B.enraged then
			last.enraged = B.enraged
			Hud.enragePill.Visible = B.enraged
		end
		local minions, players = 0, {}
		for _, u in ipairs(B.list) do
			if u.kind == "Minion" and u.hp > 0 and u.state ~= S_DOWN then
				minions = minions + 1
			elseif u.kind == "Pet" and u.side == 1 and u.owner ~= nil then
				players[u.owner] = true
			end
		end
		local pc = 0
		for _ in pairs(players) do
			pc = pc + 1
		end
		if last.minions ~= minions then
			last.minions = minions
			Hud.minionPill.Visible = minions > 0
			Hud.minionPill.Text = "Minions x" .. minions
		end
		if last.players ~= pc then
			last.players = pc
			Hud.playersPill.Visible = pc > 0
			Hud.playersPill.Text = pc == 1 and "1 player" or (pc .. " players")
		end
	elseif B.Spectator or (B.ended and B.Fighter) then
		local hp, maxHp = { 0, 0 }, { 0, 0 }
		for _, u in ipairs(B.list) do
			local s = (u.side == 1) and 1 or 2
			hp[s] = hp[s] + max(0, u.hp)
			maxHp[s] = maxHp[s] + u.maxHp
		end
		for s = 1, 2 do
			local key = "side" .. s
			local value = floor(hp[s])
			if force or last[key] ~= value then
				last[key] = value
				local sb = Hud.sideBars[s]
				sb.SetFraction(maxHp[s] > 0 and hp[s] / maxHp[s] or 0, false)
				sb.SetText(Hud.SideName(B, s))
			end
		end
	else
		for i, u in ipairs(Hud.enemyList or {}) do
			local chip = Hud.chips[i]
			if chip and chip.Frame.Visible then
				local frac = clamp(u.hp / u.maxHp, 0, 1)
				local down = u.hp <= 0 or u.state == S_DOWN
				setThin(chip.Hp, frac)
				local focused = B.focus == u.id
				local key = (down and "d" or "a") .. (focused and "f" or "")
				if force or chip.key ~= key then
					chip.key = key
					chip.Frame.BackgroundColor3 = down and Color3.fromRGB(70, 74, 92) or COLORS.Panel
					chip.Stroke.Color = focused and COLORS.Gold or (chip.boss and COLORS.Gold:Lerp(COLORS.Navy, 0.4) or COLORS.Navy)
					chip.Stroke.Thickness = focused and 3 or 2
					chip.Name.TextColor3 = down and COLORS.Weak or COLORS.White
					if down then
						chip.Name.Text = "KO"
					else
						chip.Name.Text = u.name
					end
				end
			end
		end
	end
	if not B.Fighter or B.ended then
		return
	end
	-- team rows
	local pulse = 0.5 + 0.5 * sin(now * 6)
	for i, u in ipairs(Hud.mineList or {}) do
		local row = Hud.rows[i]
		if row then
			local down = u.hp <= 0 or u.state == S_DOWN
			local frac = clamp(u.hp / u.maxHp, 0, 1)
			local hpKey = floor(u.hp)
			if force or row.hp ~= hpKey then
				row.hp = hpKey
				row.Hp.SetFraction(frac, false)
				row.Hp.SetText(down and "KO" or (Theme.ShortNumber(clamp(u.hp, 0, u.maxHp)) .. " / " .. Theme.ShortNumber(u.maxHp)))
				row.Hp.SetColor(Theme.HealthColor(frac))
			end
			setThin(row.Meter, u.meter / METER_MAX)
			local ready = not down and row.kind ~= nil and u.meter >= METER_MAX and B.order ~= "Retreat" and u.state ~= S_STUNNED
			local stateKey = down and "down" or (ready and "ready" or (row.kind and "charge" or "none"))
			if force or row.stateKey ~= stateKey then
				row.stateKey = stateKey
				local sb = row.Special
				if stateKey == "ready" then
					sb.BackgroundColor3 = COLORS.Gold
					row.SpecialTop.TextColor3 = COLORS.White
				elseif stateKey == "down" then
					sb.BackgroundColor3 = Color3.fromRGB(80, 84, 104)
				else
					sb.BackgroundColor3 = Color3.fromRGB(96, 106, 140)
				end
				row.Frame.BackgroundTransparency = down and 0.45 or 0.15
				row.Meter.Fill.BackgroundColor3 = ready and COLORS.Gold or Color3.fromRGB(226, 186, 92)
			end
			local top
			if stateKey == "ready" then
				top = "SPECIAL!"
			elseif stateKey == "down" then
				top = "KO"
			elseif stateKey == "none" then
				top = "-"
			else
				top = tostring(floor(clamp(u.meter / METER_MAX, 0, 1) * 100)) .. "%"
			end
			setText(row.SpecialTop, top)
			if stateKey == "ready" then
				row.Glow.BackgroundTransparency = 0.35 + 0.45 * pulse
				row.SpecialStroke.Color = COLORS.White
			elseif row.Glow.BackgroundTransparency ~= 1 then
				row.Glow.BackgroundTransparency = 1
				row.SpecialStroke.Color = COLORS.Navy
			end
		end
	end
	-- commands
	local lockLeft = 0
	if B.order == "Retreat" then
		lockLeft = RETREAT_LOCK - (now - B.retreatAt)
	end
	local attackText = (lockLeft > 0.05) and string.format("ATTACK %.1f", lockLeft) or "ATTACK"
	if Hud.m and Hud.m.Compact and lockLeft > 0.05 then
		attackText = string.format("%.1f", lockLeft)
	end
	setText(Hud.attack, attackText)
	setDisabled(Hud.attack, lockLeft > 0.05)
	local compact = Hud.m and Hud.m.Compact
	setText(Hud.retreat, (B.order == "Retreat" and not compact) and "RETREATING" or "RETREAT")
	local ringA = Hud.attack:FindFirstChild("ActiveRing")
	local ringR = Hud.retreat:FindFirstChild("ActiveRing")
	if ringA then
		ringA.Visible = B.order == "Attack" and B.focus ~= nil
	end
	if ringR then
		ringR.Visible = B.order == "Retreat"
	end
	if Hud.focusPill and not (Hud.m and Hud.m.Compact) then
		local f = B.focus and B.units[B.focus]
		local text = f and ("TARGET: " .. f.name .. "  X") or ""
		if last.focus ~= text then
			last.focus = text
			Hud.focusPill.Visible = f ~= nil
			Hud.focusText.Text = text
		end
	end
end

function Hud.ModeText(B)
	local text, color
	if B.Mode == "Raid" then
		text, color = "BOSS RAID", COLORS.Enemy
	elseif B.Mode == "Trial" then
		text, color = "TRIAL " .. tostring(B.Trial and B.Trial.Level or B.Level or ""), Color3.fromRGB(150, 110, 220)
	else
		text, color = "DUEL", COLORS.Ally
	end
	if B.Spectator then
		text = "WATCHING"
	end
	return text, color
end

function Hud.SideName(B, side)
	local names = {}
	for _, owner in ipairs((B.sides and B.sides[side]) or {}) do
		local n = B.Names[tostring(owner)]
		if n then
			names[#names + 1] = n
		end
	end
	if #names > 0 then
		return table.concat(names, ", ")
	end
	if B.Mode == "Trial" and side == 2 then
		return (B.Trial and B.Trial.Name) or "Trial team"
	end
	return side == 1 and "Blue side" or "Red side"
end

function Hud.TitleText(B)
	if B.Mode == "Raid" then
		return (B.boss and B.boss.name) or "Boss Raid"
	elseif B.Mode == "Trial" then
		local t = B.Trial
		if t and t.Name then
			return tostring(t.Name)
		end
		return "Trial " .. tostring(B.Level or "")
	end
	if B.Spectator then
		return Hud.SideName(B, 1) .. " vs " .. Hud.SideName(B, 2)
	end
	return "vs " .. Hud.SideName(B, B.Side == 1 and 2 or 1)
end

-- the result card at the end (bottom right, or at the top in the compact layout)
function Hud.ShowResult(B, payload)
	if not Hud.Ensure() then
		return
	end
	local m = Hud.Metrics()
	local res = Hud.result
	for _, c in ipairs(res:GetChildren()) do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") and not c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	local outcome = payload.Outcome
	if outcome == nil then
		outcome = payload.Won and "Win" or "Loss"
	end
	local raid = B.Mode == "Raid"
	local titleText, color = "DEFEAT", COLORS.Enemy
	if outcome == "Win" then
		titleText, color = raid and "BOSS DEFEATED!" or "VICTORY!", COLORS.Gold
	elseif outcome == "Draw" then
		titleText, color = "DRAW", COLORS.Ally
	elseif outcome == "Left" then
		titleText, color = "YOU LEFT", COLORS.Weak
	elseif raid then
		titleText = "THE BOSS WON"
	end
	local reasons = {
		BossDown = "The boss is down!",
		Wipe = (outcome == "Win") and "Every enemy is knocked out." or "Your team was knocked out.",
		KO = (outcome == "Win") and "Every enemy is knocked out." or "Your team was knocked out.",
		Timeout = "Time is up.",
		Forfeit = (outcome == "Win") and "Your opponent gave up." or "You gave up.",
		Left = "You left the battle.",
		Abandoned = "Everyone left the raid.",
		Ended = "The raid has ended.",
		Error = "The battle was cancelled. No rewards were lost.",
	}
	local sub = reasons[tostring(payload.Reason)] or ""
	if B.Mode == "Trial" then
		sub = "Trial " .. tostring(B.Trial and B.Trial.Level or B.Level or "") .. (sub ~= "" and (" - " .. sub) or "")
	end
	local w = m.Compact and min(K.RESULT_W, m.W - 16) or K.RESULT_W
	local y = K.PAD + 2
	local title = label(res, titleText, "Title", 36, { Name = "Title", Position = UDim2.fromOffset(K.PAD + 4, y), Size = UDim2.fromOffset(w - 2 * K.PAD - 8, 42), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color })
	title.TextStrokeColor3 = COLORS.Ink
	y = y + 44
	if sub ~= "" then
		label(res, sub, "Body", 18, { Name = "Reason", Position = UDim2.fromOffset(K.PAD + 4, y), Size = UDim2.fromOffset(w - 2 * K.PAD - 8, 24), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextColor3 = COLORS.Muted })
		y = y + 28
	end
	local list = make("Frame", { Name = "Rewards", BackgroundTransparency = 1, Position = UDim2.fromOffset(K.PAD, y), Size = UDim2.fromOffset(w - 2 * K.PAD, 10), AutomaticSize = Enum.AutomaticSize.Y }, res)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(floor((w - 2 * K.PAD - 8) / 2), 30), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rw = type(payload.Rewards) == "table" and payload.Rewards or {}
	local lines = Hud.RewardLines(B, rw)
	for i, line in ipairs(lines) do
		local p = smallPill(list, line[1], line[2], { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromScale(1, 1) })
		p.TextSize = 17
	end
	local rowsN = math.ceil(#lines / 2)
	y = y + rowsN * 36 + (rowsN > 0 and 4 or 0)
	local ok = button(res, "OkButton", "OK", "Green", UDim2.fromOffset(120, 46), function()
		Hud.HideResult()
	end)
	ok.Position = UDim2.new(1, -K.PAD - 120, 0, y)
	Hud.resultTimer = thinBar(res, "Timer", 8, COLORS.Muted, { Position = UDim2.fromOffset(K.PAD + 4, y + 19), Size = UDim2.fromOffset(w - 2 * K.PAD - 140, 8) })
	y = y + 46 + K.PAD
	res.Size = UDim2.fromOffset(w, y)
	if m.Compact then
		res.AnchorPoint = Vector2.new(0.5, 0)
		res.Position = UDim2.new(0.5, 0, 0, 6)
	else
		res.AnchorPoint = Vector2.new(1, 1)
		res.Position = UDim2.new(1, -K.EDGE, 1, -K.EDGE)
	end
	res.Visible = true
	Hud.FixText(res, m.F)
	Hud.top.Visible = false
	Hud.team.Visible = false
	Hud.cmd.Visible = false
	St.result = { t0 = os.clock(), dur = K.RESULT_SECONDS }
	BattleController._wake()
end

function Hud.RewardLines(B, rw)
	local lines = {}
	local tokens = num(rw.Tokens, 0)
	if tokens > 0 then
		lines[#lines + 1] = { "+" .. Theme.ShortNumber(tokens) .. " Tokens", Theme.Currency.Tokens.Color }
	end
	local gems = num(rw.Gems, 0)
	if gems > 0 then
		lines[#lines + 1] = { "+" .. Theme.ShortNumber(gems) .. " Gems", Theme.Currency.Gems.Color }
	end
	local trophies = num(rw.Trophies, 0)
	if trophies ~= 0 or B.Mode == "Duel" then
		lines[#lines + 1] = { (trophies >= 0 and "+" or "") .. tostring(trophies) .. " Trophies", trophies >= 0 and COLORS.Gold or COLORS.Enemy }
	end
	local xp = num(rw.Xp, 0)
	if xp > 0 then
		lines[#lines + 1] = { "+" .. Theme.ShortNumber(xp) .. " Pet XP", COLORS.Ally }
	end
	if rw.FirstClear == true then
		lines[#lines + 1] = { "First clear!", COLORS.Mine }
	end
	if rw.Tier then
		local share = num(rw.Share, 0)
		lines[#lines + 1] = { tostring(rw.Tier) .. " tier", COLORS.Gold }
		lines[#lines + 1] = { tostring(floor(share * 100 + 0.5)) .. "% of the damage", Color3.fromRGB(150, 110, 220) }
	end
	if rw.EventPet then
		local name = tostring(rw.EventPet)
		if PetCatalog and PetCatalog.Get then
			local ok, d = pcall(PetCatalog.Get, rw.EventPet)
			if ok and type(d) == "table" and d.Name then
				name = d.Name
			end
		end
		lines[#lines + 1] = { "New pet: " .. name, Color3.fromRGB(236, 110, 170) }
	end
	local ups = num(rw.LevelUps, 0)
	if ups > 0 then
		lines[#lines + 1] = { ups == 1 and "1 level up!" or (ups .. " level ups!"), COLORS.Mine }
	end
	if rw.Double == true then
		lines[#lines + 1] = { "Double rewards", COLORS.Gold }
	end
	return lines
end

function Hud.HideResult()
	St.result = nil
	if Hud.result then
		Hud.result.Visible = false
	end
	if not St.battle then
		Hud.SetVisible(false)
	end
end

function Hud.UpdateResult(now)
	local r = St.result
	if not r then
		return
	end
	local p = (now - r.t0) / r.dur
	if p >= 1 then
		Hud.HideResult()
		return
	end
	if Hud.resultTimer then
		setThin(Hud.resultTimer, 1 - p)
	end
end

function Hud.SetVisible(on)
	if not Hud.gui then
		return
	end
	if not on then
		Hud.top.Visible = false
		Hud.team.Visible = false
		Hud.cmd.Visible = false
	end
end

----------------------------------------------------------------------
-- Input
----------------------------------------------------------------------
local SPECIAL_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.ButtonL1] = 1,
	[Enum.KeyCode.ButtonR1] = 2,
	[Enum.KeyCode.ButtonL2] = 3,
	[Enum.KeyCode.ButtonR2] = 4,
}

local function sink()
	local ok, v = pcall(function()
		return Enum.ContextActionResult.Sink
	end)
	return ok and v or nil
end

local function pass()
	local ok, v = pcall(function()
		return Enum.ContextActionResult.Pass
	end)
	return ok and v or nil
end

local function fighting()
	local B = St.battle
	return B ~= nil and B.Fighter and not B.ended
end

function Input.OnAction(name, state, input)
	if not fighting() then
		return pass()
	end
	if state ~= Enum.UserInputState.Begin then
		return sink()
	end
	if name == K.ACTION_ATTACK then
		BattleController.Command("Attack", nil)
	elseif name == K.ACTION_RETREAT then
		BattleController.Command("Retreat")
	elseif name == K.ACTION_SPECIAL then
		local slot = input and SPECIAL_KEYS[input.KeyCode]
		if slot then
			BattleController.Command("Special", slot)
		end
	end
	return sink()
end

function Input.Bind(on)
	if on == St.bound then
		return
	end
	St.bound = on
	if on then
		local priority = 2000
		pcall(function()
			priority = Enum.ContextActionPriority.High.Value
		end)
		pcall(function()
			ContextActionService:BindActionAtPriority(K.ACTION_ATTACK, Input.OnAction, false, priority, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
			ContextActionService:BindActionAtPriority(K.ACTION_RETREAT, Input.OnAction, false, priority, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
			ContextActionService:BindActionAtPriority(
				K.ACTION_SPECIAL, Input.OnAction, false, priority,
				Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
				Enum.KeyCode.KeypadOne, Enum.KeyCode.KeypadTwo, Enum.KeyCode.KeypadThree, Enum.KeyCode.KeypadFour,
				Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2
			)
		end)
	else
		for _, name in ipairs({ K.ACTION_ATTACK, K.ACTION_RETREAT, K.ACTION_SPECIAL }) do
			pcall(function()
				ContextActionService:UnbindAction(name)
			end)
		end
	end
end

-- the enemy a tap at viewport pixel (x, y) focuses (nearest projected enemy within reach), or nil
function BattleController.ScreenPick(x, y)
	local B = St.battle
	local cam = workspace.CurrentCamera
	if not B or not cam then
		return nil
	end
	local reach = K.TAP_REACH * Theme.ScreenFactor()
	local best, bestD = nil, math.huge
	for _, u in ipairs(B.list) do
		if not u.ally and u.model and not u.parked and u.hp > 0 and u.state ~= S_DOWN then
			local ok, p, onScreen = pcall(cam.WorldToViewportPoint, cam, unitCenter(B, u))
			if ok and onScreen and p.Z > 0 then
				local dx, dy = p.X - x, p.Y - y
				local d = sqrt(dx * dx + dy * dy)
				local r = reach
				if u.isBoss then
					r = reach * 3
				elseif u.kind == "MiniBoss" then
					r = reach * 1.6
				end
				if d <= r and d < bestD then
					best, bestD = u.id, d
				end
			end
		end
	end
	return best
end

function Input.OnBegan(input, processed)
	local t = input.UserInputType
	if t == Enum.UserInputType.Gamepad1 or t == Enum.UserInputType.Gamepad2 then
		if not St.gamepad then
			St.gamepad = true
			Hud.Keys()
		end
	elseif t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		if St.gamepad then
			St.gamepad = false
			Hud.Keys()
		end
	end
	if processed or not fighting() then
		return
	end
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		St.tap = { x = input.Position.X, y = input.Position.Y, t = os.clock(), input = input }
	end
end

function Input.OnEnded(input)
	local tap = St.tap
	if not tap then
		return
	end
	local t = input.UserInputType
	if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
		return
	end
	St.tap = nil
	if not fighting() or os.clock() - tap.t > K.TAP_TIME then
		return
	end
	local dx, dy = input.Position.X - tap.x, input.Position.Y - tap.y
	if dx * dx + dy * dy > K.TAP_MOVE * K.TAP_MOVE then
		return
	end
	-- input positions are in GUI space (below the top bar); the camera projects into the full viewport
	local inset = 36
	local ok, a = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(a) == "Vector2" then
		inset = a.Y
	end
	local id = BattleController.ScreenPick(input.Position.X, input.Position.Y + inset)
	if id then
		BattleController.Focus(id)
	end
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------
local function commandRemote()
	if St.remoteCmd and St.remoteCmd.Parent then
		return St.remoteCmd
	end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("BattleCommand")
	St.remoteCmd = r
	return r
end

function BattleController.Command(action, arg)
	local B = St.battle
	if not B or not B.Fighter or B.ended then
		return false
	end
	if action ~= "Attack" and action ~= "Retreat" and action ~= "Special" and action ~= "Forfeit" then
		return false
	end
	local key = action .. tostring(arg)
	local now = os.clock()
	if St.lastCmd[key] and now - St.lastCmd[key] < K.CMD_GAP then
		return false
	end
	-- local checks (the server decides; these only avoid pointless traffic and give instant feedback)
	if action == "Attack" then
		if B.order == "Retreat" and now - B.retreatAt < RETREAT_LOCK then
			return false
		end
		if arg ~= nil then
			local u = B.units[arg]
			if not u or u.ally or u.hp <= 0 then
				return false
			end
		end
	elseif action == "Retreat" then
		if B.order == "Retreat" then
			return false
		end
	elseif action == "Special" then
		local u = B.mine[tonumber(arg) or 0]
		local row = nil
		for _, r in ipairs(Hud.rows) do
			if r.slot == arg then
				row = r
			end
		end
		if not u or u.hp <= 0 or not u.special or u.meter < METER_MAX or B.order == "Retreat" then
			if row and row.Special then
				row.shakeAt = now
				Hud.Shake(row.Special)
			end
			return false
		end
	end
	St.lastCmd[key] = now
	local remote = commandRemote()
	if not remote then
		return false
	end
	local ok = pcall(function()
		if arg ~= nil then
			remote:FireServer(action, arg)
		else
			remote:FireServer(action)
		end
	end)
	if not ok then
		return false
	end
	-- optimistic feedback (the Order event confirms)
	if action == "Retreat" then
		B.order = "Retreat"
		B.retreatAt = now
		B.focus = nil
	elseif action == "Attack" then
		B.order = "Attack"
		B.focus = arg
	end
	Hud.Update(B, now)
	return true
end

function BattleController.Focus(unitId)
	return BattleController.Command("Attack", unitId)
end

-- a short "not yet" wiggle (rotation only, so the layout is never disturbed)
function Hud.Shake(obj)
	if not obj or not obj.Parent then
		return
	end
	pcall(function()
		obj.Rotation = 5
		Util.Tween(obj, 0.06, { Rotation = -5 })
		task.delay(0.06, function()
			Util.Tween(obj, 0.08, { Rotation = 0 })
		end)
	end)
end

----------------------------------------------------------------------
-- Messages
----------------------------------------------------------------------
function Net.Cleanup(B, immediate)
	if not B then
		return
	end
	Tele.ClearAll(B)
	for _, u in ipairs(B.list) do
		Units.Destroy(u)
	end
	B.list = {}
	B.units = {}
	B.mine = {}
	if B.folder then
		pcall(B.folder.Destroy, B.folder)
		B.folder = nil
	end
	if St.battle == B then
		St.battle = nil
		Input.Bind(false)
		if not St.result then
			Hud.SetVisible(false)
		end
	end
	if immediate then
		Fx.ClearAll()
	end
end

function Net.Start(payload, battleId)
	if type(payload) ~= "table" then
		return
	end
	local id = payload.BattleId or battleId
	local B = St.battle
	if B and B.Id == id and not B.ended then
		-- a refresh (a raid spectator joins): keep the models, update the side and the units
		local side = num(payload.Side, 0)
		B.Side = side
		B.Spectator = payload.Spectator == true or side == 0
		B.Fighter = not B.Spectator
		B.Names = type(payload.Names) == "table" and payload.Names or B.Names
		B.sides = type(payload.Sides) == "table" and payload.Sides or B.sides
		local keep = {}
		for _, info in ipairs(type(payload.Units) == "table" and payload.Units or {}) do
			local u = Units.Add(B, info)
			if u then
				keep[u.id] = true
				local me = myUserId()
				u.mine = B.Fighter and info.owner == me
				if B.Fighter then
					u.ally = u.side == B.Side
				else
					u.ally = u.side == 1
				end
				if u.mine and u.slot >= 1 then
					B.mine[u.slot] = u
				end
				if u.barFill then
					u.barFill.BackgroundColor3 = u.mine and COLORS.Mine or (u.ally and COLORS.Ally or COLORS.Enemy)
				end
			end
		end
		for i = #B.list, 1, -1 do
			local u = B.list[i]
			if not keep[u.id] then
				Units.Remove(B, u.id)
			end
		end
		Input.Bind(B.Fighter)
		Hud.Rebuild()
		return
	end
	if B then
		Net.Cleanup(B, false)
	end
	B = newBattle(payload, battleId)
	B.sides = type(payload.Sides) == "table" and payload.Sides or {}
	St.battle = B
	B.renderT = num(payload.T, 0)
	for _, info in ipairs(type(payload.Units) == "table" and payload.Units or {}) do
		Units.Add(B, info)
	end
	-- spread the first positions from the static info until the first snapshot arrives
	if B.Mode == "Raid" then
		local BB = lazyBoss()
		if BB and B.BossId and type(BB.Preload) == "function" then
			pcall(BB.Preload, B.BossId)
		end
	end
	St.result = nil
	if Hud.result then
		Hud.result.Visible = false
	end
	Input.Bind(B.Fighter)
	Hud.Rebuild()
	BattleController._wake()
end

function Net.Snapshot(payload, battleId)
	local B = St.battle
	if not B or type(payload) ~= "table" or type(payload.Units) ~= "table" then
		return
	end
	local id = payload.BattleId or battleId
	if id ~= nil and id ~= B.Id then
		return
	end
	local T = num(payload.T, nil)
	if not T then
		return
	end
	local snaps = B.snaps
	if #snaps > 0 and T <= snaps[#snaps].T then
		return -- out of order / duplicate
	end
	snaps[#snaps + 1] = { T = T, Units = payload.Units }
	while #snaps > K.MAX_SNAPS do
		table.remove(snaps, 1)
	end
	local now = os.clock()
	local offset = T - now
	if not B.haveOffset then
		B.haveOffset = true
		B.offset = offset
	else
		-- follow slowly, but never let the render clock run ahead of what arrived
		B.offset = B.offset + (offset - B.offset) * K.OFFSET_RATE
		if offset < B.offset then
			B.offset = offset
		end
	end
end

function Net.Events(list, battleId)
	local B = St.battle
	if not B or type(list) ~= "table" then
		return
	end
	if battleId ~= nil and battleId ~= B.Id then
		return
	end
	-- played on the delayed render clock: stamp them with the estimated server time of their arrival
	local t = B.haveOffset and (os.clock() + B.offset) or B.renderT
	for _, ev in ipairs(list) do
		if type(ev) == "table" and type(ev.type) == "string" then
			-- telegraphs start at once (their fill must complete at the hit), the rest on the render clock
			if ev.type == EV.Telegraph then
				local fn = Handlers[ev.type]
				pcall(fn, B, ev)
			else
				B.evq[#B.evq + 1] = { t = t, ev = ev }
			end
		end
	end
end

function Net.End(payload, battleId)
	local B = St.battle
	if type(payload) ~= "table" then
		return
	end
	local id = payload.BattleId or battleId
	if not B or (id ~= nil and id ~= B.Id) then
		return
	end
	if B.ended then
		return
	end
	-- play what is still queued, so the last KO shows
	local latest = B.snaps[#B.snaps]
	B.renderT = max(B.renderT, (latest and latest.T or B.renderT)) + 5
	Net.PlayDue(B, os.clock())
	B.ended = true
	B.endAt = os.clock()
	Input.Bind(false)
	local participant = payload.Spectator ~= true and B.Fighter
	if participant then
		B.linger = K.END_LINGER
		Hud.ShowResult(B, payload)
		-- winners cheer
		if payload.Outcome == "Win" or payload.Won then
			for _, u in ipairs(B.list) do
				if u.ally and u.root and not u.parked then
					u.hopAt = os.clock() + math.random() * 0.4
				end
			end
		end
	else
		B.linger = (payload.Reason == "OutOfRange") and 0 or K.SPECTATOR_LINGER
		Hud.SetVisible(false)
	end
	if B.linger <= 0 then
		Net.Cleanup(B, false)
	end
end

function BattleController.HandleState(kind, payload, battleId)
	if kind == "Start" then
		Net.Start(payload, battleId)
	elseif kind == "Snapshot" then
		Net.Snapshot(payload, battleId)
	elseif kind == "Events" then
		Net.Events(payload, battleId)
	elseif kind == "End" then
		Net.End(payload, battleId)
	end
end

----------------------------------------------------------------------
-- Frame loop
----------------------------------------------------------------------
local function sampleSnaps(B)
	local snaps = B.snaps
	local n = #snaps
	if n == 0 then
		return nil, nil, 0
	end
	local t = B.renderT
	if t <= snaps[1].T then
		return snaps[1], nil, 0
	end
	for i = n - 1, 1, -1 do
		local a = snaps[i]
		if a.T <= t then
			local b = snaps[i + 1]
			local span = b.T - a.T
			local alpha = span > 0 and clamp((t - a.T) / span, 0, 1) or 1
			return a, b, alpha
		end
	end
	return snaps[n], nil, 0
end

-- per-section cost (only while a test injects BattleController.PerfClock)
local function section(name, t0)
	local clock = BattleController.PerfClock
	if not clock then
		return nil
	end
	local t = clock()
	if t0 then
		local split = St.perf.split
		split[name] = (split[name] or 0) + (t - t0) * 1000
	end
	return t
end

local function stepBattle(B, now, dt)
	local s0 = section()
	if not B.ended then
		if B.haveOffset then
			local latest = B.snaps[#B.snaps]
			local t = now + B.offset - K.INTERP_DELAY
			if latest and t > latest.T + 0.15 then
				t = latest.T + 0.15
			end
			if t > B.renderT then
				B.renderT = t
			end
		end
		Net.PlayDue(B, now)
	end
	local sa, sb, alpha = sampleSnaps(B)
	s0 = section("Events", s0)
	Units.BuildPending(B)
	s0 = section("Builds", s0)
	local crowded = #B.list > K.CROWD
	local frameNo = St.frameNo
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for i, u in ipairs(B.list) do
		local animate = true
		if not u.mine and not u.isBoss then
			local stride = crowded and 2 or 1
			if camPos and u.root and not u.parked then
				local p = u.root.Position
				local dx, dy, dz = p.X - camPos.X, p.Y - camPos.Y, p.Z - camPos.Z
				local d2 = dx * dx + dy * dy + dz * dz
				if d2 > K.ANIM_FAR * K.ANIM_FAR then
					stride = 4
				elseif d2 > K.ANIM_MID * K.ANIM_MID then
					stride = 3
				end
			end
			-- a skipped frame skips the WHOLE pet (root and wings), so it never comes apart
			animate = (not u.posed) or ((frameNo + i) % stride) == 0
		end
		local ok, err = pcall(updateUnit, B, u, now, dt, sa, sb, alpha, animate)
		if not ok then
			warnOnce("unit", "unit update failed: " .. tostring(err))
		end
	end
	s0 = section("Units", s0)
	Tele.Update(B, now)
	Units.UpdateFocus(B, now)
	s0 = section("Telegraphs", s0)
	if Hud.gui then
		local ok, err = pcall(Hud.Update, B, now)
		if not ok then
			warnOnce("hud", "HUD update failed: " .. tostring(err))
		end
	end
	section("Hud", s0)
end

-- a bobbing voxel arrow over the enemy the team focuses
function Units.UpdateFocus(B, now)
	local u = B.focus and B.units[B.focus]
	local mark = B.focusMark
	if not u or not u.model or u.parked or u.hp <= 0 or B.ended then
		if mark then
			mark.Parent = nil
		end
		return
	end
	if not mark then
		mark = make("Model", { Name = "FocusArrow" })
		local spec = { { 0, 0, 0.9 }, { 0, 0.7, 0.6 }, { 0, 1.3, 0.35 } }
		for i, s in ipairs(spec) do
			make("Part", {
				Name = "Arrow" .. i,
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = COLORS.Gold,
				Size = Vector3.new(s[3] * 1.4, 0.5, s[3] * 1.4),
			}, mark):SetAttribute("Y", s[2])
		end
		B.focusMark = mark
	end
	if mark.Parent ~= B.folder then
		mark.Parent = B.folder
	end
	local top = u.isBoss and (u.height or 20) + 2 or (u.centerY or 1.5) + (u.height or 3) / 2 + 2.4
	local base = worldPoint(B, u.x, top + sin(now * 4) * 0.35, u.z)
	local spin = now * 2
	for _, p in ipairs(mark:GetChildren()) do
		p.CFrame = CFrame.new(base.X, base.Y - (p:GetAttribute("Y") or 0) * 0.8, base.Z) * CFrame.Angles(0, spin, 0)
	end
end

local function onFrame(dt)
	local perfClock = BattleController.PerfClock or os.clock
	local p0 = perfClock()
	local t0 = os.clock()
	St.frameNo = St.frameNo + 1
	local now = t0
	local B = St.battle
	if B then
		stepBattle(B, now, dt)
		if B.ended and now - (B.endAt or now) >= (B.linger or 0) then
			Net.Cleanup(B, false)
		end
	end
	local f0 = section()
	Fx.Update(now)
	Fx.UpdateNumbers(now)
	Fx.UpdateFlashes(now)
	Hud.UpdateResult(now)
	section("Effects", f0)
	local ms = (perfClock() - p0) * 1000
	local perf = St.perf
	perf.frames = perf.frames + 1
	perf.total = perf.total + ms
	perf.last = ms
	if ms > perf.peak then
		perf.peak = ms
	end
	-- the loop sleeps when nothing is drawn
	if not St.battle and #St.effects == 0 and #St.numbers == 0 and #St.flashes == 0 and not St.result then
		if St.loop then
			St.loop:Disconnect()
			St.loop = nil
		end
	end
end

function BattleController._wake()
	if St.loop or not St.initialized then
		return
	end
	St.loop = RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(onFrame, dt)
		if not ok then
			warnOnce("frame", "frame failed: " .. tostring(err))
		end
	end)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function BattleController.GetBattle()
	local B = St.battle
	if not B then
		return nil
	end
	local models = 0
	for _, u in ipairs(B.list) do
		if u.model then
			models = models + 1
		end
	end
	return {
		Id = B.Id,
		Mode = B.Mode,
		Side = B.Side,
		Spectator = B.Spectator,
		Fighter = B.Fighter,
		Ended = B.ended,
		Units = #B.list,
		Models = models,
		Focus = B.focus,
		Order = B.order,
		Hud = BattleController.IsHudVisible(),
		Layout = (Hud.m and Hud.m.Compact) and "Compact" or "Wide",
		RenderT = B.renderT,
		Telegraphs = (function()
			local n = 0
			for _ in pairs(B.teles) do
				n = n + 1
			end
			return n
		end)(),
	}
end

function BattleController.GetUnit(id)
	local B = St.battle
	local u = B and B.units[id]
	if not u then
		return nil
	end
	return {
		Id = u.id, Side = u.side, Kind = u.kind, Name = u.name, Hp = u.hp, MaxHp = u.maxHp, State = u.state, Meter = u.meter,
		Model = u.model, X = u.x, Z = u.z, Parked = u.parked == true, Mine = u.mine, Ally = u.ally,
		World = u.model and unitCenter(B, u) or nil,
	}
end

function BattleController.GetStats()
	local perf = St.perf
	local B = St.battle
	local models = 0
	if B then
		for _, u in ipairs(B.list) do
			if u.model then
				models = models + 1
			end
		end
	end
	local teles = 0
	if B then
		for _ in pairs(B.teles) do
			teles = teles + 1
		end
	end
	return {
		Frames = perf.frames,
		AvgMs = perf.frames > 0 and perf.total / perf.frames or 0,
		PeakMs = perf.peak,
		LastMs = perf.last,
		Units = B and #B.list or 0,
		Models = models,
		FxParts = St.fxLive,
		Effects = #St.effects,
		Numbers = #St.numbers,
		Flashes = #St.flashes,
		Telegraphs = teles,
		Builds = perf.builds,
		Bound = St.bound,
		Split = (function()
			local out = {}
			for k, v in pairs(perf.split or {}) do
				out[k] = perf.frames > 0 and v / perf.frames or 0
			end
			return out
		end)(),
	}
end

function BattleController.ResetStats()
	St.perf = { frames = 0, total = 0, peak = 0, last = 0, builds = 0, split = {} }
end

function BattleController.IsHudVisible()
	return Hud.gui ~= nil and Hud.gui.Parent ~= nil and ((Hud.team and Hud.team.Visible) or (Hud.result and Hud.result.Visible)) == true
end

function BattleController.Stop()
	if St.battle then
		Net.Cleanup(St.battle, true)
	end
	Fx.ClearAll()
	Input.Bind(false)
	for _, c in ipairs(St.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	St.conns = {}
	if St.loop then
		St.loop:Disconnect()
		St.loop = nil
	end
	if Hud.gui then
		Hud.gui:Destroy()
	end
	Hud.gui = nil
	Hud.topBuilt = false
	Hud.teamBack = nil
	Hud.rows = {}
	Hud.chips = {}
	St.result = nil
	for _, p in ipairs(St.pool) do
		pcall(p.Destroy, p)
	end
	St.pool = {}
	St.fxLive = 0
	if St.folder then
		pcall(St.folder.Destroy, St.folder)
		St.folder = nil
		St.fxFolder = nil
	end
	St.initialized = false
end

function BattleController.Init()
	if St.initialized then
		return
	end
	St.initialized = true
	local conns = St.conns
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		local ok, err = pcall(Input.OnBegan, input, processed)
		if not ok then
			warnOnce("input", err)
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		local ok, err = pcall(Input.OnEnded, input)
		if not ok then
			warnOnce("input2", err)
		end
	end)
	local okGp, gpConn = pcall(function()
		return UserInputService.LastInputTypeChanged:Connect(function(t)
			local gp = t == Enum.UserInputType.Gamepad1 or t == Enum.UserInputType.Gamepad2
			if gp ~= St.gamepad then
				St.gamepad = gp
				pcall(Hud.Keys)
			end
		end)
	end)
	if okGp and gpConn then
		conns[#conns + 1] = gpConn
	end
	local cam = workspace.CurrentCamera
	if cam then
		conns[#conns + 1] = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if St.battle then
				pcall(Hud.Rebuild)
			end
		end)
	end
	-- the remote (BattleState may arrive a little after the controller starts)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes", 30)
		local remote = folder and folder:WaitForChild("BattleState", 30)
		if not remote or not St.initialized then
			if St.initialized then
				warnOnce("remote", "BattleState remote not found: battles will not be drawn")
			end
			return
		end
		conns[#conns + 1] = remote.OnClientEvent:Connect(function(kind, payload, battleId)
			local ok, err = pcall(BattleController.HandleState, kind, payload, battleId)
			if not ok then
				warnOnce("state_" .. tostring(kind), "BattleState " .. tostring(kind) .. " failed: " .. tostring(err))
			end
		end)
		commandRemote()
	end)
end

return BattleController
