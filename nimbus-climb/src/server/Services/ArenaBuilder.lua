-- ArenaBuilder (Phase 3, arenaworld): the Battle Arena island, the Trial Portal on the plaza and the private trial
-- pockets in the sky, in the DETAILED VOXEL style (ARCHITECTURE_V3.md "Phase 3: Pet battles", "Phase 3 build contract"
-- and its "Interfaces between the Phase 3 modules"; ART DIRECTION; World text rule). A server module: Main calls
-- Build(lobbyInfo) once after the lobby; BattleService / EventService / TutorialService get the ArenaInfo it returns.
--
-- Contract API:
--   ArenaBuilder.Build(lobbyInfo) -> ArenaInfo    builds workspace.BattleArena (safe to call again: rebuilds)
--     ArenaInfo = {
--       Model        = workspace.BattleArena (Model)
--       Center       = CFrame   the colosseum floor centre on the walking surface, LookVector = towards the lobby (the
--                               main gate, the forum and the bridge are on that side)
--       Floor        = { CFrame, Size, Zone }   the boss stage (Mode "Raid"): CFrame on the floor surface at the
--                               colosseum centre (rotated like Center), Size = the battle floor (X, height, Z: studs; X / Z
--                               = BattleCatalog.Zones.Raid), Zone = its NC_BattleZone part
--       Rings        = { { CFrame, Size, Pads = { BasePart... }, Zone, Index }... }   the duel rings (Mode "Duel"); the
--                               challenge pads carry the "Arena" prompts
--       Spawn        = CFrame   arrival point on the forum (the Arena Gate teleport lands here), looking at the gate
--       ReturnCFrame = CFrame   on the plaza in front of the Trial Portal, looking at the plaza (trial fighters come back)
--       TrialPortal  = BasePart the Trial Portal's pad (carries the "Trials" prompt; trial starts are accepted near it)
--       -- extras
--       Radius, Bounds = { CFrame, Size }   the island (InArena uses its real outline); Link = "Bridge" | "Portal"
--       EventBoard = { Model, Gui, Labels }, Leaderboard = { Model, Gui, Rows }   the SurfaceGuis (see ApplyArenaState)
--       ApplyArenaState = ArenaBuilder.ApplyArenaState, InArena = ArenaBuilder.InArena
--     }
--   ArenaBuilder.BuildPocket(index) -> { Model, CFrame, Size, Spawn, Zone, Index } | nil
--       a private trial arena (index 1..MAX_POCKETS), cloned from one template (<= ~250 parts), far out in the sky on
--       its own grid cell; CFrame = floor surface centre (axis aligned), Size = the battle floor (BattleCatalog.Zones.Trial),
--       Spawn = where the fighter stands (side 1, looking at the enemy side). Building an index that exists returns it.
--   ArenaBuilder.FreePocket(zone)              removes that pocket (the table from BuildPocket, its index or Model)
--   ArenaBuilder.ApplyArenaState(state)        EventService: draws the ArenaState table (the same one it broadcasts:
--       { Next = { Kind, BossId, StartsIn }, Raid = { Active, BossId, Hp, MaxHp, Players, EndsIn }, Double = { Active,
--       EndsIn }, Leaderboard = { { UserId, Name, Trophies }... } }) on the event board and the trophy leaderboard; the
--       countdowns tick down every second between two states. Without any state for a while the boards show the
--       schedule and the trophies of the players in the server (DataService) on their own.
--   ArenaBuilder.InArena(position) -> bool      on (or just above) the arena island
--   ArenaBuilder.ZoneAt(position) -> part|nil   the NC_BattleZone part that contains the position
--   ArenaBuilder.GetInfo() / GetPocket(index)   what was built
--   ArenaBuilder.Teleported                     Util.Signal: Fire(player, "Arena" | "Lobby", source) after a teleport
--
-- World (island-local frame: origin = colosseum floor centre on the walking surface, -Z = towards the lobby):
--   * placed beyond the home plots on the ray of LobbyInfo.ArenaAngle (the spoke just past the last portal), at the
--     first distance where nothing of the lobby (homes, gardens, the Storm Altar, sky clouds) comes near its outline;
--     the sky dragon flies 120+ studs higher. Linked to the plaza by a stone BRIDGE that leaves the street at
--     LobbyInfo.ArenaDock (the junction's outer rail is open there) and runs straight between the two plots, with an
--     entrance arch ("BATTLE ARENA") and torches in the element colours. Without a dock (an older lobby) or when
--     something blocks the corridor, an Arena Portal on the plaza and a Return Portal on the forum link it instead.
--   * Island: a big puffy voxel cloud; the forum in front (paving, the avenue with a crimson runner, torches, a golden
--     trophy statue, banners, planters) and the COLOSSEUM behind: a 16-sided stadium whose sand floor (apothem 72)
--     holds the raid zone at any rotation, an element wheel in its centre, a podium wall, four tiers of seats in the
--     eight element colours, an outer wall with blind arches, element banners and crenellations, pillars with
--     braziers; the main gate (sign "BATTLE ARENA", an "Arena" prompt), two side gates and the boss gate at the back.
--   * Two DUEL RINGS on the forum (16-sided, apothem 33: the duel zone fits at any rotation) with a coloured curb,
--     torch posts, a crossed-swords emblem and two challenge pads each (prompt "Duel", attribute OpenPanel = "Arena").
--   * The EVENT BOARD and the TROPHY LEADERBOARD: free-standing stone frames flanking the avenue in front of the main
--     gate, SurfaceGuis at 50 px per stud (titles >= 1.1 studs, every line >= 0.6 stud).
--   * Battle zones: invisible parts tagged NC_BattleZone with the attributes Mode ("Raid" | "Duel" | "Trial"), Size
--     (Vector3, the battle floor: X, height, Z), ZoneId and Index; the part itself covers the floor plus a small margin
--     (where the controls work). CanCollide / CanTouch / CanQuery false: test membership with the part's CFrame + Size.
--   * Trial Portal: model Portal_Trials at LobbyInfo.TrialSite (the next gate of the plaza's portal fan), styled like
--     the difficulty portals (crimson, crossed swords instead of stars), prompt "Trials" with OpenPanel = "Trials". It
--     lives in workspace.BattleArena (the lobby's own part budget is full); TutorialService can point at
--     ArenaInfo.TrialPortal.Position.
--   * The home Arena Gate (HomeBuilder's ArenaGatePrompt) teleports its owner to ArenaInfo.Spawn: refused in a match
--     or a battle, only near the gate, rate limited; the fallback portals use the same checks.
-- No server-side animation (Replication rule): torches, glows and particles only. Every text uses Theme roles.
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local ArenaBuilder = {}
ArenaBuilder.Teleported = Util.Signal()

local function loadShared(name)
	local inst = Shared:FindFirstChild(name)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	warn("[ArenaBuilder] shared/" .. name .. " unavailable: " .. tostring(result))
	return nil
end

local Voxel = loadShared("Voxel")
local Remotes = loadShared("Remotes")

-- other engineers' modules, resolved when first needed (a build may not have them yet)
local lazyCache = {}
local function lazy(key, find)
	local entry = lazyCache[key]
	if entry == nil then
		entry = false
		local inst = find()
		if inst then
			local ok, result = pcall(require, inst)
			if ok and type(result) == "table" then
				entry = result
			end
		end
		lazyCache[key] = entry
	end
	return entry or nil
end
local function battleCatalog()
	return lazy("BattleCatalog", function()
		return Shared:FindFirstChild("BattleCatalog")
	end)
end
local function dataService()
	return lazy("DataService", function()
		return script.Parent and script.Parent:FindFirstChild("DataService")
	end)
end

local floor, ceil, sqrt, abs, max, min = math.floor, math.ceil, math.sqrt, math.abs, math.max, math.min
local sin, cos, rad, pi = math.sin, math.cos, math.rad, math.pi

local function atan2(y, x)
	if math.atan2 then
		return math.atan2(y, x)
	end
	return math.atan(y, x)
end

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
local MAT = Enum.Material
local LOBBY = Config.Lobby
local ORIGIN = LOBBY.Origin
local TOP = ORIGIN.Y -- the lobby's walking height; the arena island's walking surface is at the same height
local ARENA_NAME = "BattleArena"
local ZONE_TAG = "NC_BattleZone"
local ATTR_IN_BATTLE = "InBattle" -- BattleService's player attribute (battle id) from the contract
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SEED = 20261011
local DEFAULT_ANGLE = 202.5 -- the arena's direction from the plaza when the lobby reserves none
local STEP16 = pi * 2 / 16
local TAN16 = math.tan(pi / 16) -- half width per stud of apothem of a 16-sided polygon (tan 11.25 degrees)
local PART_BUDGET = 2500 -- the island, its bridge and the Trial Portal (ARCHITECTURE_V3.md: arena <= ~2500)
local POCKET_BUDGET = 250
local MAX_POCKETS = 64
local POCKET_ORIGIN = Vector3.new(-3600, 1500, -3600) -- far from the lobby, the obby match slots (+X) and each other
local POCKET_SPACING = 380
local POCKET_COLUMNS = 8
local ZONE_H = 30 -- studs: height of a battle zone part (from 4 under the floor)
local PROMPT_RANGE = 10
local TELEPORT_COOLDOWN = 2 -- seconds between two teleports of one player (Arena Gate / fallback portals)
local TELEPORT_SLACK = 8 -- studs beyond a prompt's range that still count as "at the gate" (latency)
local BOARD_SILENCE = 20 -- seconds without an ApplyArenaState before the boards fill themselves in
local FALLBACK_REFRESH = 10 -- seconds between two self-made leaderboards

-- Battle floor sizes (BattleCatalog.Zones; local defaults when the catalog is missing or odd). The floors are built
-- so that these squares fit at ANY rotation: the colosseum floor's apothem 72 holds a 96 x 96 square (half diagonal
-- 67.9), a duel ring's apothem 33 holds 44 x 44 (31.1), a pocket's 64 x 64 square floor holds 56 x 56.
local DEFAULT_ZONES = { Raid = { X = 96, Z = 96 }, Duel = { X = 44, Z = 44 }, Trial = { X = 56, Z = 56 } }
local MAX_ZONE = { Raid = 100, Duel = 45, Trial = 62 } -- the biggest square each floor can hold

-- Island layout (island-local studs; the colosseum centre is the origin, -Z points at the lobby)
local ISL = {
	FrontZ = -205, -- the forum's front edge (the bridge docks here)
	HalfW = 100, -- forum half width
	BackZ = -40, -- the forum rectangle reaches into the colosseum disc up to here
	DiscR = 103, -- the colosseum disc
	Corner = 30, -- forum corner radius
	Clearance = 14, -- studs kept between the island's cloud and anything of the lobby
}
local COL = {
	FloorR = 72, -- floor apothem
	PodiumR = 74, -- podium wall 72..74, cap on top (top at 6)
	Tier0 = 74, -- tiers: 4 x 4 studs deep, tops 7 / 9 / 11 / 13
	Tiers = 4,
	TierDepth = 4,
	WallIn = 90, -- outer wall 90..92, top 20, merlons to 22
	WallOut = 92,
	WallH = 20,
	PillarOut = 97,
	GateHalf = 6, -- passages are 13 studs wide (|x| <= 6.5)
	GateH = 13,
}
local RING_A = 33 -- duel ring apothem
local RING_Y = 0.6 -- duel ring floor top above the forum
local RINGS = {
	{ X = -52, Z = -150, Accent = Color3.fromRGB(226, 84, 86), Name = "Duel Ring 1" },
	{ X = 52, Z = -150, Accent = Color3.fromRGB(84, 146, 232), Name = "Duel Ring 2" },
}
local BRIDGE_W = 12

----------------------------------------------------------------------
-- Palette: the lobby's calm stone and cloud colours, gold trim, battle crimson and the eight element colours
----------------------------------------------------------------------
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local C = {
	CloudLight = rgb(244, 247, 252),
	Cloud = rgb(232, 238, 249),
	CloudShade = rgb(212, 222, 241),
	Mist = rgb(194, 211, 240),
	MistDark = rgb(170, 190, 228),
	Stone = rgb(208, 202, 190),
	StoneLight = rgb(226, 221, 209),
	StoneDark = rgb(172, 164, 154),
	StoneEdge = rgb(146, 138, 132),
	Marble = rgb(236, 230, 218),
	Paving = rgb(214, 206, 192),
	PavingLight = rgb(228, 222, 208),
	PavingDark = rgb(192, 184, 170),
	PavingWorn = rgb(203, 195, 181),
	PavingWarm = rgb(224, 212, 190),
	Sand = rgb(234, 210, 160),
	SandDark = rgb(214, 186, 136),
	SandLight = rgb(242, 224, 182),
	SandDrift = rgb(222, 196, 146),
	Gold = rgb(244, 198, 84),
	GoldDark = rgb(206, 154, 62),
	Iron = rgb(64, 70, 92),
	IronLight = rgb(96, 104, 130),
	Crimson = rgb(204, 62, 72),
	CrimsonDark = rgb(150, 42, 54),
	Navy = rgb(34, 42, 76),
	Violet = rgb(68, 60, 118),
	Recess = rgb(70, 74, 104),
	Grass = rgb(108, 186, 86),
	GrassLight = rgb(132, 202, 98),
	GrassDark = rgb(86, 160, 76),
	Hedge = rgb(74, 146, 72),
	Soil = rgb(120, 86, 64),
	Steel = rgb(214, 222, 236),
	Lamp = rgb(255, 214, 140),
	Text = rgb(238, 243, 252),
	TextGold = rgb(246, 216, 132),
	TextDim = rgb(206, 216, 240),
	Ink = (Theme.Colors and Theme.Colors.TextStroke) or rgb(16, 22, 50),
}

local ELEMENTS = {} -- { { Id, Color } } in Config.Elements.Order
do
	local cfg = Config.Elements
	local order = (type(cfg) == "table" and type(cfg.Order) == "table") and cfg.Order or { "Water", "Flame", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }
	for _, id in ipairs(order) do
		local info = type(cfg) == "table" and type(cfg.Info) == "table" and cfg.Info[id]
		ELEMENTS[#ELEMENTS + 1] = { Id = id, Color = (info and typeof(info.Color) == "Color3") and info.Color or C.Gold }
	end
end
local function elementColor(i)
	local e = ELEMENTS[((i - 1) % #ELEMENTS) + 1]
	return e and e.Color or C.Gold
end
local function flameColor(color)
	return color:Lerp(rgb(255, 250, 230), 0.18)
end

local GLYPH = {
	Trophy = "\240\159\143\134",
	Swords = "\226\154\148",
	Dot = "\194\183",
	Dash = "\226\128\147",
	Clock = "\226\143\176",
}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function newModel(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

-- One anchored block. opts: Collide, Query, Material, Transparency, Shadow.
local function box(parent, name, cf, size, color, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = opts.Material or MAT.SmoothPlastic
	p.Transparency = opts.Transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = opts.Collide == true
	p.CanQuery = opts.Collide == true or opts.Query == true
	p.CanTouch = false
	if opts.Shadow ~= nil then
		p.CastShadow = opts.Shadow == true
	else
		p.CastShadow = max(size.X, size.Y, size.Z) >= 4
	end
	p.Parent = parent
	return p
end

local function anchorPart(parent, name, cf, size)
	return box(parent, name, cf, size or Vector3.new(1, 1, 1), C.Cloud, { Transparency = 1, Shadow = false })
end

local FADE_IN_OUT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.25, 0.2),
	NumberSequenceKeypoint.new(0.75, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

local function popSize(maxSize)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, maxSize),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLES
	e.Color = ColorSequence.new(C.TextGold)
	e.LightEmission = 0.6
	e.LightInfluence = 0
	e.Rate = 5
	e.Lifetime = NumberRange.new(1.2, 2)
	e.Speed = NumberRange.new(1, 2)
	e.Size = popSize(0.6)
	e.Transparency = FADE_IN_OUT
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	for k, v in pairs(props or {}) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function pointLight(parent, color, brightness, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
	return l
end

local function countParts(root)
	local n = 0
	if not root then
		return 0
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

-- flat look: a CFrame at `pos` facing `target` horizontally
local function flatLook(pos, target)
	local d = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	if d.Magnitude < 1e-3 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + d)
end

local function polar(angleDeg, radius, y)
	local a = rad(angleDeg)
	return Vector3.new(ORIGIN.X + cos(a) * radius, y or TOP, ORIGIN.Z + sin(a) * radius)
end

-- Clones a template built around the origin to `cf` (every part moved; attachments ride their parts).
local function place(tpl, cf, parent, name)
	if not tpl then
		return nil
	end
	local m = tpl:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = cf * d.CFrame
		end
	end
	if m:IsA("BasePart") then
		m.CFrame = cf * m.CFrame
	end
	if name then
		m.Name = name
	end
	m.Parent = parent
	return m
end

local function recolor(root, name, color)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == name then
			d.Color = color
		end
	end
end

----------------------------------------------------------------------
-- Voxel helpers
----------------------------------------------------------------------
local VX = {}

function VX.Fill(g, x0, x1, y0, y1, z0, z1, key)
	for y = y0, y1 do
		for x = x0, x1 do
			for z = z0, z1 do
				Voxel.Set(g, x, y, z, key)
			end
		end
	end
end

function VX.Disc(g, cx, cz, r, y0, y1, key, keep)
	local ri = ceil(r) + 1
	local r2 = r * r
	for y = y0, y1 do
		for x = floor(cx) - ri, ceil(cx) + ri do
			for z = floor(cz) - ri, ceil(cz) + ri do
				local dx, dz = x - cx, z - cz
				if dx * dx + dz * dz <= r2 and (not keep or Voxel.Get(g, x, y, z) == nil) then
					Voxel.Set(g, x, y, z, key)
				end
			end
		end
	end
end

function VX.RoundRect(g, cx, cz, sx, sz, round, y0, y1, key, keep)
	local hx, hz = sx / 2, sz / 2
	round = max(0, min(round, hx, hz))
	for y = y0, y1 do
		for x = floor(cx - hx) - 1, ceil(cx + hx) + 1 do
			for z = floor(cz - hz) - 1, ceil(cz + hz) + 1 do
				local qx, qz = abs(x - cx) - (hx - round), abs(z - cz) - (hz - round)
				local ox, oz = max(qx, 0), max(qz, 0)
				local d = sqrt(ox * ox + oz * oz) + min(max(qx, qz), 0)
				if d <= round and (not keep or Voxel.Get(g, x, y, z) == nil) then
					Voxel.Set(g, x, y, z, key)
				end
			end
		end
	end
end

-- Voxel.Build with this file's defaults. o: V, Pal, Name, CF (where voxel 0,0,0 sits), Parent, Collide, MaxParts,
-- Keep, Shadow.
function VX.Build(g, o)
	if not g or g.Count == 0 then
		return nil
	end
	local model = Voxel.Build(g, {
		VoxelSize = o.V or 1,
		Palette = o.Pal,
		Name = o.Name or "Voxels",
		CFrame = o.CF or CFrame.new(),
		CanCollide = o.Collide == true,
		CanQuery = o.Collide == true,
		MaxParts = o.MaxParts,
		Keep = o.Keep,
		CastShadow = o.Shadow,
	})
	if o.Parent then
		model.Parent = o.Parent
	end
	return model
end

-- hash noise in [0, 1) and smooth value noise (deterministic)
local function hash3(x, y, z, seed)
	local h = (x * 73856093 + y * 19349663 + z * 83492791 + (seed or 0) * 2654435761) % 2147483647
	h = (h * 16807) % 2147483647
	local a = h % 65521
	a = (a * a + (seed or 0) * 7919 + 12345) % 65521
	h = ((h + a * 32771) * 16807) % 2147483647
	return (h % 1000003) / 1000003
end

local function vnoise(x, z, scale, seed)
	local fx, fz = x / scale, z / scale
	local ix, iz = floor(fx), floor(fz)
	local tx, tz = fx - ix, fz - iz
	tx = tx * tx * (3 - 2 * tx)
	tz = tz * tz * (3 - 2 * tz)
	local a = hash3(ix, 0, iz, seed)
	local b = hash3(ix + 1, 0, iz, seed)
	local c = hash3(ix, 0, iz + 1, seed)
	local d = hash3(ix + 1, 0, iz + 1, seed)
	return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * tz
end

local TIER_KEYS = { "CloudLight", "Cloud", "CloudShade", "Mist", "MistDark" }
local CLOUD_PAL = {
	CloudLight = C.CloudLight,
	Cloud = C.Cloud,
	CloudShade = C.CloudShade,
	Mist = C.Mist,
	MistDark = C.MistDark,
}

-- A voxel cloud from a footprint signed distance. spec: V (studs per voxel), Sdf(x, z) -> studs (negative inside),
-- Bounds = { x0, x1, z0, z1 } studs, Tiers = { { Inset, H }... } from the top level (0) down, Puffs / Rim =
-- { { x, y, z, rx, ry, rz }... } studs (relative to the top centre), Carve(x, y, z) -> remove?, Seed.
local function cloudGrid(spec)
	local V = spec.V or 3
	local g = Voxel.NewGrid(16)
	local b = spec.Bounds
	for i = floor(b[1] / V), ceil(b[2] / V) do
		for k = floor(b[3] / V), ceil(b[4] / V) do
			local d = spec.Sdf(i * V, k * V)
			local y = 0
			for ti, t in ipairs(spec.Tiers) do
				local h = t.H or 1
				if d <= -(t.Inset or 0) then
					for yy = y - h + 1, y do
						Voxel.Set(g, i, yy, k, TIER_KEYS[min(ti, #TIER_KEYS)])
					end
				end
				y = y - h
			end
		end
	end
	for _, p in ipairs(spec.Puffs or {}) do
		Voxel.Shape(g, { Kind = "Ellipsoid", Center = { p[1] / V, p[2] / V, p[3] / V }, Radius = { p[4] / V, p[5] / V, p[6] / V }, Key = "Puff", KeepExisting = true })
	end
	for _, p in ipairs(spec.Rim or {}) do
		Voxel.Shape(g, { Kind = "Ellipsoid", Center = { p[1] / V, p[2] / V, p[3] / V }, Radius = { p[4] / V, p[5] / V, p[6] / V }, Key = "Rim", KeepExisting = true })
	end
	if spec.Carve then
		local remove = {}
		for key in pairs(g.Cells) do
			local x, yy, z = Voxel.Unpack(key)
			if spec.Carve(x * V, yy * V, z * V) then
				remove[#remove + 1] = key
			end
		end
		for _, key in ipairs(remove) do
			g.Cells[key] = nil
			g.Count = g.Count - 1
		end
	end
	Voxel.Shade(g, { Only = { Puff = true, Rim = true }, Smooth = 2, Seed = spec.Seed or 1 })
	Voxel.Remap(g, {
		Puff = "Cloud",
		Puff_Light = "CloudLight",
		Puff_Dark = "Mist",
		Rim = "Cloud",
		Rim_Light = "CloudLight",
		Rim_Dark = "CloudShade",
	})
	return g
end

-- A small puffy cloud (a support under a bridge), top at y = 0
local function puffTemplate(scale)
	local s = scale or 1
	local g = cloudGrid({
		V = 2,
		Sdf = function(x, z)
			return sqrt(x * x + z * z) - 6 * s
		end,
		Bounds = { -8 * s, 8 * s, -8 * s, 8 * s },
		Tiers = { { Inset = 0, H = 1 }, { Inset = 2, H = 1 } },
		Puffs = {
			{ 5 * s, -1.5, 2 * s, 5 * s, 3.5 * s, 4.5 * s },
			{ -5 * s, -2, -1.5 * s, 5.5 * s, 4 * s, 5 * s },
			{ 0, -4 * s, 0, 6 * s, 4.5 * s, 6 * s },
		},
		Seed = 3,
	})
	return VX.Build(g, { V = 2, Pal = CLOUD_PAL, Name = "CloudPuff", CF = CFrame.new(0, -1, 0), MaxParts = 16 })
end

----------------------------------------------------------------------
-- GUI helpers (World text rule: pixel-sized tags, signs at 50 px per stud; Theme font roles only)
----------------------------------------------------------------------
local SIGN_PPS = 50
local TAG_RANGE = 110

local function rounded(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function outline(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function vgradient(parent, top, bottom)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
	return g
end

local function padding(parent, top, left, bottom, right)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, top)
	p.PaddingLeft = UDim.new(0, left)
	p.PaddingBottom = UDim.new(0, bottom or top)
	p.PaddingRight = UDim.new(0, right or left)
	p.Parent = parent
	return p
end

local function listLayout(parent, direction, gap)
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction or Enum.FillDirection.Vertical
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap or 0)
	l.Parent = parent
	return l
end

local function plainFrame(parent, name, props)
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

-- Pixel-sized tag on `adornee`: the transparent w x h container's BOTTOM edge sits `lift` studs over the adornee.
local function newTag(adornee, name, w, h, lift, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Name = name or "Tag"
	gui.Size = UDim2.fromOffset(w, h)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift or 0, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or TAG_RANGE
	gui.ClipsDescendants = false
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

-- the compact solid plate of a tag (navy gradient, rounded, outlined), sized to its content
local function tagPlate(gui, edge, minW)
	local plate = plainFrame(gui, "Plate", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(minW or 0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.04,
	})
	rounded(plate, 16)
	outline(plate, edge or C.TextGold, 3.5)
	vgradient(plate, (Theme.Colors and Theme.Colors.PanelLight) or C.Violet, (Theme.Colors and Theme.Colors.Panel) or C.Navy)
	padding(plate, 7, 16, 9)
	listLayout(plate, Enum.FillDirection.Vertical, 2)
	return plate
end

local function tagText(parent, name, text, role, size, color, order)
	local label = Theme.Label(text, role, {
		Size = size,
		Color = color or C.Text,
		Stroke = 1,
		Outline = 2.5,
		OutlineColor = C.Ink,
		Props = {
			Name = name,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, size + 4),
			TextWrapped = false,
			LayoutOrder = order or 0,
		},
	})
	label.Parent = parent
	return label
end

local function tagPill(parent, name, text, role, size, fill, order)
	local pill = plainFrame(parent, name, {
		Size = UDim2.fromOffset(0, size + 8),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = fill,
		BackgroundTransparency = 0,
		LayoutOrder = order or 0,
	})
	rounded(pill, floor(size * 0.55))
	outline(pill, C.Ink, 2.5)
	padding(pill, 2, floor(size * 0.5), 3)
	local label = tagText(pill, name .. "Label", text, role, size, C.Text, 1)
	return pill, label
end

local function surfaceGui(part, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PPS
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = part
	gui.Parent = part
	return gui
end

-- navy -> violet rounded panel with an outline, filling the whole SurfaceGui
local function signPanel(gui, strokeColor)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(1, 0, 1, 0)
	panel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	panel.BorderSizePixel = 0
	vgradient(panel, C.Violet, C.Navy)
	rounded(panel, 24)
	outline(panel, strokeColor or C.TextGold, 6, 0.15)
	panel.Parent = gui
	return panel
end

-- fixed-size sign text (px at SIGN_PPS) placed with fractions of its parent
local function signText(parent, name, text, role, size, color, x, y, w, h, align)
	local label = Theme.Label(text, role, {
		Size = size,
		Color = color,
		Stroke = 1,
		Outline = max(2, floor(size / 16 + 0.5)),
		OutlineColor = C.Ink,
		Props = {
			Name = name,
			Position = UDim2.new(x, 0, y, 0),
			Size = UDim2.new(w, 0, h, 0),
			TextWrapped = false,
			TextXAlignment = align or Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		},
	})
	label.Parent = parent
	return label
end

-- Fits a text into `widthPx` at `px` (the smoke audit's 0.5 em per character estimate): cuts it with "..." when needed.
local function fitText(text, px, widthPx)
	text = tostring(text or "")
	local maxChars = floor(widthPx / (0.5 * px))
	local n = 0
	for _ in text:gmatch("[^\128-\191]") do
		n = n + 1
	end
	if n <= maxChars then
		return text
	end
	local out, count = {}, 0
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		count = count + 1
		if count > maxChars - 3 then
			break
		end
		out[#out + 1] = ch
	end
	return table.concat(out) .. "..."
end

local function clockText(seconds)
	seconds = max(0, floor((tonumber(seconds) or 0) + 0.5))
	local h = floor(seconds / 3600)
	local m = floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

local function commas(n)
	if Util.Commas then
		local ok, text = pcall(Util.Commas, n)
		if ok and type(text) == "string" then
			return text
		end
	end
	return tostring(n)
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local S = {
	info = nil, -- ArenaInfo
	model = nil, -- workspace.BattleArena
	A = nil, -- island frame
	lobby = nil,
	pockets = {}, -- [index] = pocket table
	pocketTpl = nil,
	board = nil, -- event board labels
	leaders = nil, -- leaderboard rows
	external = nil, -- os.clock() of the last ApplyArenaState
	boardState = nil, -- { NextKind, NextBoss, NextAt, Raid = {...}, RaidAt, DoubleAt, DoubleActive }
	lastFallback = nil,
	promptConn = nil,
	lastTeleport = {},
	built = 0,
	tickRunning = false,
}

----------------------------------------------------------------------
-- Battle zones
----------------------------------------------------------------------
local function zoneFloorSize(mode)
	local bc = battleCatalog()
	local z = bc and type(bc.Zones) == "table" and bc.Zones[mode]
	local d = DEFAULT_ZONES[mode]
	local x = (type(z) == "table" and tonumber(z.X)) or d.X
	local zz = (type(z) == "table" and tonumber(z.Z)) or d.Z
	if x ~= x or x <= 0 then
		x = d.X
	end
	if zz ~= zz or zz <= 0 then
		zz = d.Z
	end
	-- never more than the floor can hold
	x = min(x, MAX_ZONE[mode])
	zz = min(zz, MAX_ZONE[mode])
	return Vector3.new(x, ZONE_H, zz)
end

-- An invisible zone part: covers the floor (`half` studs each way of `cf`) from 4 under the surface to ZONE_H - 4 above.
local function makeZone(parent, name, cf, half, mode, floorSize, zoneId, index)
	local size = Vector3.new(half * 2, ZONE_H, half * 2)
	local p = box(parent, name, cf * CFrame.new(0, ZONE_H / 2 - 4, 0), size, C.Crimson, { Transparency = 1, Shadow = false })
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p:SetAttribute("Mode", mode)
	p:SetAttribute("Size", floorSize)
	p:SetAttribute("ZoneId", zoneId)
	p:SetAttribute("Index", index or 1)
	p:SetAttribute("FloorY", cf.Position.Y)
	CollectionService:AddTag(p, ZONE_TAG)
	return p
end

local function insideZonePart(part, pos)
	local rel = part.CFrame:PointToObjectSpace(pos)
	local s = part.Size
	return abs(rel.X) <= s.X / 2 and abs(rel.Y) <= s.Y / 2 and abs(rel.Z) <= s.Z / 2
end

----------------------------------------------------------------------
-- Island outline (island-local studs)
----------------------------------------------------------------------
local function islandSdf(x, z)
	local dDisc = sqrt(x * x + z * z) - ISL.DiscR
	local cz = (ISL.FrontZ + ISL.BackZ) / 2
	local hx, hz = ISL.HalfW, (ISL.BackZ - ISL.FrontZ) / 2
	local r = ISL.Corner
	local qx, qz = abs(x) - (hx - r), abs(z - cz) - (hz - r)
	local ox, oz = max(qx, 0), max(qz, 0)
	local dRect = sqrt(ox * ox + oz * oz) + min(max(qx, qz), 0) - r
	return min(dDisc, dRect)
end

-- the colosseum's 16-gon "radius" of a point (max over the edge normals), island-local
local NORMALS16 = {}
for k = 0, 15 do
	local a = k * STEP16
	-- segment k's outward axis: the template's -Z turned by k steps about +Y
	local v = CFrame.Angles(0, a, 0):VectorToWorldSpace(Vector3.new(0, 0, -1))
	NORMALS16[k + 1] = { v.X, v.Z }
end
local function polyR(x, z)
	local m = -math.huge
	for i = 1, 16 do
		local n = NORMALS16[i]
		local d = x * n[1] + z * n[2]
		if d > m then
			m = d
		end
	end
	return m
end

----------------------------------------------------------------------
-- Island cloud body
----------------------------------------------------------------------
local function buildCloud(parent, A)
	local rng = Util.NewRng(SEED + 1)
	local puffs, rim = {}, {}
	-- walk the outline from a point inside it (the footprint is star-shaped around it)
	local cx, cz = 0, -70
	for deg = 0, 359, 18 do
		local a = rad(deg + rng:Float(-2, 2))
		local dx, dz = cos(a), sin(a)
		local r = 0
		while r < 320 and islandSdf(cx + dx * r, cz + dz * r) < 0 do
			r = r + 2
		end
		local bx, bz = cx + dx * r, cz + dz * r
		local front = bz < ISL.FrontZ + 30 and abs(bx) < 24 -- the bridge docks here: keep it open and flat
		local s = rng:Float(12, 15)
		puffs[#puffs + 1] = { bx - dx * rng:Float(0, 2), rng:Float(-10, -6), bz - dz * rng:Float(0, 2), s, s * rng:Float(0.55, 0.7), s }
		if not front and deg % 36 == 0 then
			local s2 = rng:Float(5.5, 7.5)
			rim[#rim + 1] = { bx - dx * 1.5, rng:Float(-0.5, 1), bz - dz * 1.5, s2, s2 * 0.62, s2 }
		end
	end
	-- a hanging belly: big lumps under the middle, narrowing down
	for i = 1, 5 do
		local a = rng:Float(0, pi * 2)
		local d = rng:Float(10, 60)
		local s = rng:Float(28, 38)
		puffs[#puffs + 1] = { cos(a) * d, rng:Float(-34, -24), -60 + sin(a) * d * 1.4, s, rng:Float(10, 14), s }
	end
	local spec = {
		V = 4,
		Sdf = islandSdf,
		Bounds = { -ISL.HalfW - 12, ISL.HalfW + 12, ISL.FrontZ - 12, ISL.DiscR + 12 },
		Tiers = {
			{ Inset = 0, H = 1 },
			{ Inset = 10, H = 1 },
			{ Inset = 26, H = 2 },
			{ Inset = 50, H = 2 },
			{ Inset = 78, H = 2 },
		},
		Puffs = puffs,
		Rim = rim,
		-- nothing of the body rises above the ground inside the outline, nor over the bridge's landing
		Carve = function(x, y, z)
			if y <= 0 then
				return false
			end
			if islandSdf(x, z) < -5 then
				return true
			end
			if abs(x) < BRIDGE_W / 2 + 6 and z < ISL.FrontZ + 24 then
				return true
			end
			return false
		end,
		Seed = 7,
	}
	local g = cloudGrid(spec)
	-- the top tier's top face sits 1.2 under the walking surface (the ground layers lie on it)
	return VX.Build(g, { V = 4, Pal = CLOUD_PAL, Name = "IslandCloud", CF = A * CFrame.new(0, -1.2 - 2, 0), Collide = true, MaxParts = 340, Parent = parent })
end

-- the element of a stand segment (two neighbours share one) and the angle its section is centred on
local function segmentElement(k)
	return floor(k / 2) % 8 + 1
end
local function sectionAngle(e)
	return (2 * e - 1.5) * STEP16
end

-- Thin flat patches on a floor: cells = { { i, k, key }... } on a `cell`-stud grid around `cf` (cell i, k centred on
-- x = i * cell, z = k * cell), greedily merged per key into slabs `h` studs thick whose top is at `top`. A subtle
-- colour variation (sand drifts, worn paving) for a handful of parts.
local function flatPatches(parent, name, cells, cell, cf, top, h, pal, material)
	local g = Voxel.NewGrid(1)
	for _, c in ipairs(cells) do
		Voxel.Set(g, c[1], 0, c[2], c[3])
	end
	if g.Count == 0 then
		return nil
	end
	local m = newModel(parent, name)
	for _, b in ipairs(Voxel.Merge(g)) do
		local sx, sz = (b.X1 - b.X0 + 1) * cell, (b.Z1 - b.Z0 + 1) * cell
		local cx, cz = (b.X0 + b.X1) * 0.5 * cell, (b.Z0 + b.Z1) * 0.5 * cell
		box(m, b.Key, cf * CFrame.new(cx, top - h / 2, cz), Vector3.new(sx, h, sz), pal[b.Key] or C.Sand, { Collide = true, Material = material, Shadow = false })
	end
	return m
end

----------------------------------------------------------------------
-- Forum ground: one paving layer over the whole island (also under the colosseum, whose floor lies on it), the
-- avenue's crimson runner with gold edges from the bridge to the main gate, a gold star where the bridge lands and
-- element tiles around the trophy. Paving top -0.2, runner 0, star / tiles +0.1.
----------------------------------------------------------------------
local function buildGround(parent, A)
	local f = newModel(parent, "Forum")
	-- base paving (4-stud cells; its stair-stepped rim hides under the cloud's rim puffs)
	local base = Voxel.NewGrid(1)
	for i = ceil((-ISL.HalfW - 4) / 4), floor((ISL.HalfW + 4) / 4) do
		for k = ceil((ISL.FrontZ - 4) / 4), floor((ISL.DiscR + 4) / 4) do
			local x, z = i * 4, k * 4
			local d = islandSdf(x, z)
			if d <= -2 then
				-- a darker kerb band along the rim, lighter aprons around the duel rings, the trophy and along the avenue
				-- (the colosseum hides the cells under its floor)
				local key = "Paving"
				local apron = false
				for _, spec in ipairs(RINGS) do
					local pr = polyR(x - spec.X, z - spec.Z)
					if pr >= RING_A + 1 and pr <= RING_A + 9 then
						apron = true
					end
				end
				if d > -10 then
					key = "Kerb"
				elseif apron or (abs(x) <= 10 and z < -(COL.WallOut - 2)) then
					key = "Apron"
				elseif sqrt(x * x + (z + 124) * (z + 124)) <= 16 then
					key = "Apron"
				else
					-- worn and sun-warmed stretches so the big forum never reads as one flat colour
					local n = vnoise(x, z, 30, SEED + 3)
					if n < 0.3 then
						key = "Worn"
					elseif n > 0.72 then
						key = "Warm"
					end
				end
				Voxel.Set(base, i, 0, k, key)
			end
		end
	end
	VX.Build(base, {
		V = 4,
		Pal = {
			Paving = { Color = C.Paving, Material = MAT.Slate },
			Apron = { Color = C.PavingLight, Material = MAT.Slate },
			Kerb = { Color = C.PavingDark, Material = MAT.Slate },
			Worn = { Color = C.PavingWorn, Material = MAT.Slate },
			Warm = { Color = C.PavingWarm, Material = MAT.Slate },
		},
		Name = "Paving",
		CF = A * CFrame.new(0, -0.2 - 2, 0),
		Collide = true,
		Shadow = false,
		Parent = f,
		MaxParts = 370,
	})
	-- the runner: from the bridge's landing to the main gate's passage
	local z0, z1 = ISL.FrontZ + 1, -(COL.WallOut + 1.5)
	local len = z1 - z0
	local mid = (z0 + z1) / 2
	box(f, "Runner", A * CFrame.new(0, -0.2, mid), Vector3.new(4, 0.4, len), C.Crimson, { Collide = true, Shadow = false })
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "RunnerEdge", A * CFrame.new(sx * 2.6, -0.2, mid), Vector3.new(1.2, 0.4, len), C.Gold, { Collide = true, Shadow = false })
	end
	-- a gold eight-pointed star with a navy heart where the bridge lands
	local star = A * CFrame.new(0, 0, ISL.FrontZ + 22)
	for _, turn in ipairs({ 0, 45 }) do
		box(f, "ArrivalStar", star * CFrame.new(0, -0.1, 0) * CFrame.Angles(0, math.rad(turn), 0), Vector3.new(9, 0.4, 9), C.Gold, { Collide = true, Shadow = false })
	end
	box(f, "ArrivalHeart", star * CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(3.6, 0.4, 3.6), C.Navy, { Collide = true, Shadow = false })
	-- element tiles around the trophy plinth
	for e = 1, 8 do
		local turn = A * CFrame.new(0, 0, -124) * CFrame.Angles(0, sectionAngle(e), 0)
		box(f, "TrophyTile", turn * CFrame.new(0, -0.1, -7.6) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(2, 0.4, 2), elementColor(e), { Collide = true, Shadow = false })
	end
	return f
end

----------------------------------------------------------------------
-- Colosseum
----------------------------------------------------------------------
local function hwOut(a)
	-- integer voxel half width whose cells reach the 16-gon's edge at apothem `a` (neighbours overlap a little)
	return ceil(a * TAN16 - 0.4)
end
local function hwIn(a)
	-- inset half width: never reaches a neighbour's cells (seats, banners)
	return floor(a * TAN16 - 1.3)
end

-- voxel (ix, iy, ia): x in [ix - 0.5, ix + 0.5], y in [iy, iy + 1], apothem in [ia, ia + 1] (outwards = -Z)
local function setA(g, ix, iy, ia, key)
	Voxel.Set(g, ix, iy, -ia, key)
end
local function fillA(g, a0, a1, y0, y1, hw, key, cond)
	for ia = a0, a1 - 1 do
		for iy = y0, y1 - 1 do
			for ix = -hw, hw do
				if not cond or cond(ix, iy, ia) then
					setA(g, ix, iy, ia, key)
				end
			end
		end
	end
end
local function getA(g, ix, iy, ia)
	return Voxel.Get(g, ix, iy, -ia)
end

-- inside an arch shape centred at cx: |x - cx| <= hw, y from y0 up to the crown (a half disc on top)
local function inArch(ix, iy, cx, hw, y0, y1)
	if iy < y0 or iy > y1 then
		return false
	end
	local dx = ix - cx
	if abs(dx) > hw then
		return false
	end
	local spring = y1 - hw -- where the round top starts
	if iy <= spring then
		return true
	end
	local dy = iy - spring
	return dx * dx + dy * dy <= (hw + 0.45) * (hw + 0.45)
end

-- kind: "Stand" | "Gate" | "BossGate"
local function segmentGrid(kind)
	local g = Voxel.NewGrid(24)
	local gate = kind == "Gate"
	local gh = COL.GateHalf
	local function open(ix, iy)
		-- the passage through the stands (gates)
		return gate and abs(ix) <= gh and iy >= 0 and iy < COL.GateH + 6
	end
	-- podium wall + its gold cap
	fillA(g, COL.FloorR, COL.PodiumR, -1, 5, hwOut(COL.PodiumR), "Podium", function(ix, iy)
		return not open(ix, iy)
	end)
	fillA(g, COL.FloorR, COL.PodiumR, 5, 6, hwOut(COL.PodiumR), "Gold", function(ix, iy)
		return not open(ix, iy)
	end)
	-- the four tiers (solid down to the ground) with their seat cushions
	for t = 1, COL.Tiers do
		local a0 = COL.Tier0 + (t - 1) * COL.TierDepth
		local a1 = a0 + COL.TierDepth
		local topY = 5 + 2 * t
		fillA(g, a0, a1, -1, topY, hwOut(a1), (t % 2 == 1) and "TierA" or "TierB", function(ix, iy)
			return not open(ix, iy)
		end)
		fillA(g, a0, a0 + 2, topY, topY + 1, hwIn(a0), "Seat", function(ix, iy)
			return not open(ix, iy) and not (gate and abs(ix) <= gh + 1)
		end)
	end
	-- outer wall, merlons
	local hwW = hwOut(COL.WallOut + 1)
	fillA(g, COL.WallIn, COL.WallOut, -1, COL.WallH, hwW, "Wall", function(ix, iy)
		if gate then
			return not inArch(ix, iy, 0, gh, -1, COL.GateH + 1)
		end
		return true
	end)
	fillA(g, COL.WallIn, COL.WallOut, COL.WallH, COL.WallH + 2, hwW, "Wall", function(ix)
		return floor((ix + hwW) / 4) % 2 == 0
	end)
	if gate then
		-- a gatehouse: the wall rises over the passage (the main gate's sign hangs on it), crowned by its own merlons
		local gw = gh + 5
		fillA(g, COL.WallIn, COL.WallOut, COL.WallH, COL.WallH + 6, gw, "Wall")
		fillA(g, COL.WallIn, COL.WallOut, COL.WallH + 6, COL.WallH + 8, gw, "Wall", function(ix)
			return floor((ix + gw) / 3) % 2 == 0
		end)
		fillA(g, COL.WallOut, COL.WallOut + 1, COL.WallH + 5, COL.WallH + 6, gw, "Cornice")
	end
	-- facade: a plinth, two pilasters (three bays), a gold band, the cornice; dark arch panels in the bays (flush with
	-- the wall, framed by the protruding pilasters and bands: cheap and readable), the element banner in the middle bay
	local fa = COL.WallOut
	local function bayArch(ix, iy, cx, y0, y1)
		local dx = abs(ix - cx)
		if iy < y0 or iy > y1 then
			return false
		elseif iy < y1 then
			return dx <= 3
		end
		return dx <= 2
	end
	fillA(g, fa, fa + 1, COL.WallH - 1, COL.WallH, hwW, "Cornice")
	if not gate then
		fillA(g, fa, fa + 1, -1, 1, hwW, "Plinth")
		for _, px in ipairs({ -7, -6, 6, 7 }) do
			for ia = fa, fa + 1 do
				for iy = 1, 18 do
					setA(g, px, iy, ia, "Pilaster")
				end
			end
		end
		for ix = -16, 16 do
			for iy = 2, 12 do
				local side = bayArch(ix, iy, -12, 2, 12) or bayArch(ix, iy, 12, 2, 12)
				local middle = bayArch(ix, iy, 0, 2, 9)
				if side or middle then
					setA(g, ix, iy, fa, "Recess")
				end
			end
		end
		-- an element banner hanging from the cornice in the middle bay, a gold diamond on it
		for ix = -2, 2 do
			for iy = 11, COL.WallH - 2 do
				setA(g, ix, iy, fa, (iy == COL.WallH - 2) and "Gold" or "Banner")
			end
		end
		setA(g, 0, 15, fa + 1, "Gold")
		setA(g, 0, 14, fa + 1, "Gold")
		setA(g, -1, 14, fa + 1, "Gold")
		setA(g, 1, 14, fa + 1, "Gold")
		setA(g, 0, 13, fa + 1, "Gold")
	else
		-- the gate's arch frame (protruding voussoirs + pilasters) and a raised portcullis in the opening's crown
		for ix = -gh - 2, gh + 2 do
			for iy = -1, COL.GateH + 3 do
				local inner = inArch(ix, iy, 0, gh, -1, COL.GateH + 1)
				local outer = inArch(ix, iy, 0, gh + 2, -1, COL.GateH + 3)
				if outer and not inner then
					setA(g, ix, iy, fa, (iy >= COL.GateH - 3) and "Gold" or "Cornice")
				end
			end
		end
		for ix = -gh, gh do
			if ix % 2 == 0 then
				for iy = COL.GateH - 2, COL.GateH + 1 do
					if inArch(ix, iy, 0, gh, -1, COL.GateH + 1) then
						setA(g, ix, iy, COL.WallIn, "Iron")
					end
				end
			end
		end
		-- the passage floor (top at 0, like the colosseum floor's stone band) and its side walls are the cut stands
		fillA(g, COL.FloorR - 1, COL.WallOut + 1, -1, 0, gh, "Passage")
	end
	if kind == "BossGate" then
		-- the boss gate: a big iron portcullis in the podium wall, a dark tunnel behind it, a gold crest above
		for ix = -5, 5 do
			for iy = -1, 4 do
				setA(g, ix, iy, COL.FloorR, "Recess")
			end
		end
		for ix = -4, 4, 2 do
			for iy = 0, 4 do
				setA(g, ix, iy, COL.FloorR - 1, "Iron")
			end
		end
		for ix = -5, 5 do
			setA(g, ix, 5, COL.FloorR - 1, "Iron")
		end
		for ix = -3, 3 do
			setA(g, ix, 6, COL.FloorR, "Gold")
		end
		setA(g, 0, 7, COL.FloorR, "Gold")
	end
	return g
end

local SEG_PAL = {
	Podium = C.Stone,
	TierA = C.StoneLight,
	TierB = C.Stone,
	Seat = C.Crimson, -- recoloured per segment
	Wall = C.StoneLight,
	Plinth = C.StoneDark,
	Cornice = C.Marble,
	Pilaster = C.Marble,
	Recess = C.Recess,
	Gold = C.Gold,
	Banner = C.Crimson, -- recoloured per segment
	Iron = C.Iron,
	Passage = { Color = C.Stone, Material = MAT.Slate },
}

local segTemplates = {}
local function segmentTemplate(kind)
	if segTemplates[kind] then
		return segTemplates[kind]
	end
	local g = segmentGrid(kind)
	local m = VX.Build(g, {
		V = 1,
		Pal = SEG_PAL,
		Name = "Segment",
		CF = CFrame.new(0, 0.5, -0.5),
		Collide = true,
		MaxParts = 120, -- never reached: the colour clusters of the LOD would grey the stands out
		Keep = { "Seat", "Banner", "Gold", "Recess", "Passage", "Iron" },
	})
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "Recess" or d.Name == "Banner") then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	segTemplates[kind] = m
	return m
end

local pillarTemplate = nil
local function pillar()
	if pillarTemplate then
		return pillarTemplate
	end
	local g = Voxel.NewGrid(24)
	local a0 = COL.WallOut - 1
	fillA(g, a0, COL.PillarOut + 1, -1, 1, 2, "PillarBase")
	fillA(g, a0, COL.PillarOut, 1, 22, 1, "Pillar")
	fillA(g, a0, COL.PillarOut + 1, 22, 23, 2, "Gold")
	fillA(g, a0 + 1, COL.PillarOut, 23, 24, 1, "Iron")
	setA(g, 0, 24, a0 + 2, "Flame")
	setA(g, 0, 25, a0 + 2, "Flame")
	setA(g, -1, 24, a0 + 2, "Flame")
	setA(g, 1, 24, a0 + 2, "Flame")
	Voxel.Shade(g, { Only = { Pillar = true }, Smooth = 1, Seed = 9, Light = false })
	local m = VX.Build(g, {
		V = 1,
		Pal = {
			PillarBase = C.StoneDark,
			Pillar = C.Marble,
			Gold = C.Gold,
			Iron = C.Iron,
			Flame = { Color = C.Gold, Material = MAT.Neon },
		},
		Name = "Pillar",
		CF = CFrame.new(0, 0.5, -0.5),
		Collide = true,
		MaxParts = 10,
		Keep = { "Flame" },
	})
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Flame" then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	pillarTemplate = m
	return m
end

-- 16-sided shapes from boxes turned k x 22.5 degrees (the colosseum's faces, the rings, the wheel). Boxes of one colour
-- may overlap: their coplanar faces are identical, so nothing flickers. Edge j's normal is the segments' (NORMALS16).
local function disc16(parent, name, cf, apothem, topY, h, color, material, collide)
	local w = 2 * apothem * TAN16 + 0.2
	for j = 0, 7 do
		box(parent, name, cf * CFrame.Angles(0, j * STEP16, 0) * CFrame.new(0, topY - h / 2, 0), Vector3.new(w, h, apothem * 2), color, { Collide = collide, Material = material, Shadow = false })
	end
end
local function ring16(parent, name, cf, r0, r1, topY, h, color, material, collide)
	local len = 2 * r1 * TAN16 + 0.15
	for j = 0, 15 do
		box(parent, name, cf * CFrame.Angles(0, j * STEP16, 0) * CFrame.new(0, topY - h / 2, -(r0 + r1) / 2), Vector3.new(len, h, r1 - r0), color, { Collide = collide, Material = material, Shadow = false })
	end
end

-- The arena floor (apothem 72; the sand reaches under the podium wall): sand, a stone band and a gold line along the
-- wall, a pale ring at 40 studs, an element diamond per section, and the element wheel in the middle (8 petals in the
-- element colours between gold rays, a gold core and rim). Sand top -0.1, everything else on top at 0 / +0.1.
local function buildFloor(parent, A)
	local m = newModel(parent, "ArenaFloor")
	disc16(m, "Sand", A, COL.FloorR + 1, -0.1, 1, C.Sand, MAT.Sand, true)
	ring16(m, "FloorBand", A, COL.FloorR - 8, COL.FloorR + 1, 0, 1, C.Stone, MAT.Slate, true)
	ring16(m, "FloorGold", A, COL.FloorR - 9.6, COL.FloorR - 8, 0, 1, C.GoldDark, nil, true)
	ring16(m, "FloorLine", A, 40, 41.6, 0, 1, C.StoneLight, MAT.Slate, true)
	-- raked sand: darker and paler drifts (4-stud cells, top -0.04) between the wheel and the gold line
	local cells = {}
	for i = -15, 15 do
		for k = -15, 15 do
			local x, z = i * 4, k * 4
			if polyR(x, z) <= COL.FloorR - 12.6 and sqrt(x * x + z * z) > 18.2 then
				local n = vnoise(x, z, 22, SEED + 11)
				if n < 0.33 then
					cells[#cells + 1] = { i, k, "SandDark" }
				elseif n > 0.7 then
					cells[#cells + 1] = { i, k, "SandLight" }
				end
			end
		end
	end
	flatPatches(m, "SandDrift", cells, 4, A, -0.04, 0.2, { SandDark = C.SandDrift, SandLight = C.SandLight }, MAT.Sand)
	for e = 1, 8 do
		local turn = A * CFrame.Angles(0, sectionAngle(e), 0)
		box(m, "ElementFrame", turn * CFrame.new(0, -0.52, -54) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(6.6, 1, 6.6), C.GoldDark, { Collide = true, Shadow = false })
		box(m, "ElementMark", turn * CFrame.new(0, -0.45, -54) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(5, 1, 5), elementColor(e), { Collide = true, Shadow = false })
		box(m, "WheelPetal", turn * CFrame.new(0, -0.5, -10), Vector3.new(4, 1, 7), elementColor(e), { Collide = true, Shadow = false })
		box(m, "WheelRay", A * CFrame.Angles(0, sectionAngle(e) + STEP16, 0) * CFrame.new(0, -0.5, -9.75), Vector3.new(0.7, 1, 8.5), C.Gold, { Collide = true, Shadow = false })
	end
	ring16(m, "WheelRim", A, 14, 15.2, 0, 1, C.Gold, nil, true)
	disc16(m, "WheelCore", A, 5.5, 0.1, 1, C.Gold, nil, true)
	return m
end

local function segmentKind(k)
	if k == 0 or k == 4 or k == 12 then
		return "Gate"
	elseif k == 8 then
		return "BossGate"
	end
	return "Stand"
end

local function buildColosseum(parent, A)
	local m = newModel(parent, "Colosseum")
	buildFloor(m, A)
	local segs = newModel(m, "Stands")
	for k = 0, 15 do
		local kind = segmentKind(k)
		local cf = A * CFrame.Angles(0, k * STEP16, 0)
		local seg = place(segmentTemplate(kind), cf, segs, string.format("Segment_%02d", k))
		local e = segmentElement(k) -- two neighbouring segments share an element (the wheel's petals point at them)
		recolor(seg, "Seat", elementColor(e))
		recolor(seg, "Banner", elementColor(e))
		seg:SetAttribute("Element", ELEMENTS[e] and ELEMENTS[e].Id or "")
		seg:SetAttribute("Kind", kind)
	end
	local pillars = newModel(m, "Pillars")
	for k = 0, 15 do
		local cf = A * CFrame.Angles(0, (k + 0.5) * STEP16, 0)
		local p = place(pillar(), cf, pillars, string.format("Pillar_%02d", k))
		local e = segmentElement(k)
		recolor(p, "Flame", flameColor(elementColor(e)))
		if k % 2 == 0 then
			local flame = p:FindFirstChild("Flame")
			if flame then
				pointLight(flame, flameColor(elementColor(e)), 1.1, 18)
			end
		end
	end
	return m
end

----------------------------------------------------------------------
-- Duel rings
----------------------------------------------------------------------
local ringPostTemplate = nil
local function ringPost()
	if ringPostTemplate then
		return ringPostTemplate
	end
	local m = newModel(nil, "RingPost")
	box(m, "PostBase", CFrame.new(0, 0.5, 0), Vector3.new(2.2, 1, 2.2), C.StoneDark, { Collide = true, Shadow = false })
	box(m, "Post", CFrame.new(0, 2.8, 0), Vector3.new(1.3, 3.6, 1.3), C.Marble, { Collide = true, Shadow = false })
	box(m, "PostCap", CFrame.new(0, 4.85, 0), Vector3.new(1.9, 0.5, 1.9), C.Gold, { Shadow = false })
	box(m, "Flame", CFrame.new(0, 5.6, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.9, 1.1, 0.9), C.Gold, { Material = MAT.Neon, Shadow = false })
	ringPostTemplate = m
	return m
end

local emblemTemplates = {}
local function swordsEmblem(accent)
	local key = tostring(accent)
	if emblemTemplates[key] then
		return emblemTemplates[key]
	end
	local g = Voxel.NewGrid(1)
	for i = -7, 7 do
		for k = -7, 7 do
			local r = sqrt(i * i + k * k)
			if r >= 6 and r <= 7.4 then
				Voxel.Set(g, i, 0, k, "Accent")
			end
		end
	end
	-- two crossed swords: blades along the diagonals, gold guards and pommels
	for t = -4, 4 do
		Voxel.Set(g, t, 0, t, "Blade")
		Voxel.Set(g, t, 0, -t, "Blade")
	end
	for _, s in ipairs({ { 4, 4, 1, -1 }, { -4, 4, -1, -1 } }) do
		-- guards across each blade near its lower end, then grip + pommel
		local gx, gz = s[1], s[2]
		Voxel.Set(g, gx + s[3], 0, gz + s[4] * -1, "Guard")
		Voxel.Set(g, gx - s[3], 0, gz - s[4] * -1, "Guard")
		Voxel.Set(g, gx + (gx > 0 and 1 or -1), 0, gz + 1, "Guard")
		Voxel.Set(g, gx + (gx > 0 and 2 or -2), 0, gz + 2, "Guard")
	end
	local m = VX.Build(g, { V = 1, Pal = { Accent = accent, Blade = C.Steel, Guard = C.Gold }, Name = "Emblem", CF = CFrame.new(0, -0.5, 0), Collide = false, Shadow = false, MaxParts = 30 })
	emblemTemplates[key] = m
	return m
end

local function makePrompt(parent, name, action, object, panel, extra)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	if panel then
		prompt:SetAttribute("OpenPanel", panel)
	end
	for k, v in pairs(extra or {}) do
		prompt:SetAttribute(k, v)
	end
	prompt.Parent = parent
	return prompt
end

local function buildRing(parent, A, spec, index)
	local m = newModel(parent, "DuelRing_" .. index)
	m:SetAttribute("RingIndex", index)
	local cf = A * CFrame.new(spec.X, 0, spec.Z)
	local accent = spec.Accent
	-- the floor: eight long slabs turned 22.5 degrees apart make the 16-gon (same colour: the overlaps never show)
	local slabW = 2 * RING_A * TAN16 + 0.4
	for j = 0, 7 do
		box(m, "RingFloor", cf * CFrame.Angles(0, j * STEP16, 0) * CFrame.new(0, RING_Y - 0.5, 0), Vector3.new(slabW, 1, RING_A * 2), C.SandLight, { Collide = true, Material = MAT.Sand, Shadow = false })
	end
	-- sand drifts (3-stud cells) between the emblem and the rim, different on every ring
	local cells = {}
	for i = -10, 10 do
		for k = -10, 10 do
			local x, z = i * 3, k * 3
			if polyR(x, z) <= RING_A - 5.4 and sqrt(x * x + z * z) > 9.8 then
				local n = vnoise(x + spec.X, z + spec.Z, 14, SEED + 17)
				if n < 0.36 then
					cells[#cells + 1] = { i, k, "SandDark" }
				elseif n > 0.8 then
					cells[#cells + 1] = { i, k, "SandPale" }
				end
			end
		end
	end
	flatPatches(m, "RingDrift", cells, 3, cf, RING_Y + 0.04, 0.12, { SandDark = C.Sand, SandPale = C.SandDrift }, MAT.Sand)
	-- a painted circle (16 thin strips) where the two teams line up, and a darker sand rim inside the curb
	local lineA = 21
	local lineLen = 2 * lineA * TAN16 + 0.5
	for j = 0, 15 do
		local seg = cf * CFrame.Angles(0, j * STEP16, 0)
		box(m, "RingLine", seg * CFrame.new(0, RING_Y + 0.03, -lineA), Vector3.new(lineLen, 0.1, 0.8), C.Marble, { Shadow = false })
		box(m, "RingRim", seg * CFrame.new(0, RING_Y + 0.02, -(RING_A - 1.5)), Vector3.new(2 * (RING_A - 1.5) * TAN16 + 1.3, 0.08, 3), C.SandDark, { Material = MAT.Sand, Shadow = false })
	end
	-- the curb: 16 blocks on the edges, in the ring's colour
	local curbOut = RING_A + 1.6
	local curbLen = 2 * curbOut * TAN16 + 0.25
	for j = 0, 15 do
		box(m, "Curb", cf * CFrame.Angles(0, j * STEP16, 0) * CFrame.new(0, RING_Y + 0.3 - 0.55, -(RING_A + 0.3)), Vector3.new(curbLen, 1.7, 2.6), accent:Lerp(C.Navy, 0.25), { Collide = true, Shadow = false })
	end
	-- torch posts on every other vertex
	local postR = curbOut / math.cos(math.pi / 16) + 0.6
	local lit = 0
	for j = 0, 7 do
		local a = (2 * j + 0.5) * STEP16
		local post = place(ringPost(), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, RING_Y - 0.6, -postR), m, "TorchPost")
		recolor(post, "Flame", flameColor(elementColor(j + 1)))
		if j % 4 == 0 then
			local flame = post:FindFirstChild("Flame")
			if flame then
				pointLight(flame, flameColor(elementColor(j + 1)), 1, 14)
				lit = lit + 1
			end
		end
	end
	-- the crossed swords in the middle
	place(swordsEmblem(accent), cf * CFrame.new(0, RING_Y + 0.12, 0), m, "Emblem")
	-- two challenge pads on the ring's axis (the front one faces the avenue side)
	local pads = {}
	for p, side in ipairs({ -1, 1 }) do
		local pcf = cf * CFrame.new(0, RING_Y, side * (RING_A - 6))
		local base = box(m, "ChallengePad", pcf * CFrame.new(0, 0.1, 0), Vector3.new(5.4, 0.4, 5.4), C.Gold, { Collide = true, Shadow = false })
		box(m, "PadGlow", pcf * CFrame.new(0, 0.33, 0), Vector3.new(4.2, 0.2, 4.2), accent, { Material = MAT.Neon, Shadow = false })
		box(m, "PadMark", pcf * CFrame.new(0, 0.47, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(3.6, 0.12, 0.6), C.Gold, { Shadow = false })
		box(m, "PadMark", pcf * CFrame.new(0, 0.47, 0) * CFrame.Angles(0, math.rad(-45), 0), Vector3.new(3.6, 0.12, 0.6), C.Gold, { Shadow = false })
		base:SetAttribute("RingIndex", index)
		base:SetAttribute("PadIndex", p)
		makePrompt(base, "DuelPrompt", "Duel", spec.Name, "Arena", { RingIndex = index, PadIndex = p })
		-- a pixel tag over the pad
		local gui = newTag(base, "PadTag", 300, 110, 3.2, 60)
		local plate = tagPlate(gui, accent:Lerp(C.Text, 0.2), 150)
		tagText(plate, "RingName", spec.Name, "Title", 26, accent:Lerp(C.Text, 0.55), 1)
		tagText(plate, "RingHint", "Challenge a player", "Heading", 19, C.Text, 2)
		pads[#pads + 1] = base
	end
	return m, cf, pads
end

----------------------------------------------------------------------
-- Event board + trophy leaderboard
----------------------------------------------------------------------
local BOARD_W, BOARD_H = 15, 10
local LEADER_W, LEADER_H = 15, 12.5

-- a free-standing stone frame for a sign panel of w x h studs; returns the model and the panel part (Front face = sign)
local function boardFrame(parent, name, cf, w, h)
	local m = newModel(parent, name)
	local base = h * 0 + 2.2 -- panel bottom over the ground
	box(m, "Step", cf * CFrame.new(0, 0.3, 0.6), Vector3.new(w + 4, 0.6, 4.2), C.StoneDark, { Collide = true })
	for _, sx in ipairs({ -1, 1 }) do
		box(m, "Post", cf * CFrame.new(sx * (w / 2 + 0.9), (base + h + 1.6) / 2, 0.6), Vector3.new(1.6, base + h + 1.6, 1.8), C.StoneLight, { Collide = true })
		box(m, "PostCap", cf * CFrame.new(sx * (w / 2 + 0.9), base + h + 1.85, 0.6), Vector3.new(2.2, 0.5, 2.4), C.Gold, { Shadow = false })
		box(m, "Flame", cf * CFrame.new(sx * (w / 2 + 0.9), base + h + 2.6, 0.6) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.9, 1, 0.9), C.Gold, { Material = MAT.Neon, Shadow = false })
	end
	box(m, "Lintel", cf * CFrame.new(0, base + h + 0.9, 0.6), Vector3.new(w + 2.6, 1.4, 2), C.Marble, { Collide = true })
	box(m, "LintelTrim", cf * CFrame.new(0, base + h + 0.2, -0.45), Vector3.new(w + 1.6, 0.3, 0.2), C.Gold, { Shadow = false })
	box(m, "Back", cf * CFrame.new(0, base + h / 2, 0.85), Vector3.new(w + 0.4, h + 0.4, 0.8), C.Stone, { Collide = true })
	local panel = box(m, "Panel", cf * CFrame.new(0, base + h / 2, 0.25), Vector3.new(w, h, 0.4), C.Navy, { Collide = true, Shadow = false })
	-- crest: a gold shield with crossed swords on the lintel
	box(m, "Crest", cf * CFrame.new(0, base + h + 2.4, 0.3), Vector3.new(2.6, 2.2, 0.6), C.Crimson, { Shadow = false })
	box(m, "CrestRim", cf * CFrame.new(0, base + h + 2.4, 0.5), Vector3.new(3.1, 2.7, 0.4), C.Gold, { Shadow = false })
	for _, s in ipairs({ -1, 1 }) do
		box(m, "Sword", cf * CFrame.new(0, base + h + 2.6, -0.1) * CFrame.Angles(0, 0, math.rad(s * 40)), Vector3.new(0.35, 3.6, 0.2), C.Steel, { Shadow = false })
	end
	return m, panel
end

local function buildEventBoard(parent, cf)
	local m, panel = boardFrame(parent, "EventBoard", cf, BOARD_W, BOARD_H)
	local gui = surfaceGui(panel, Enum.NormalId.Front)
	gui.Name = "BoardGui"
	local p = signPanel(gui, C.TextGold)
	local labels = {}
	labels.Header = signText(p, "Header", "ARENA EVENTS", "Title", 60, C.TextGold, 0.04, 0.03, 0.92, 0.15)
	labels.Next = signText(p, "NextLabel", "NEXT EVENT", "Heading", 34, C.TextDim, 0.04, 0.2, 0.92, 0.1)
	labels.Boss = signText(p, "BossLabel", "Boss Raid", "Title", 46, C.Text, 0.04, 0.31, 0.92, 0.12)
	labels.Countdown = signText(p, "CountdownLabel", "--:--", "Display", 100, C.Text, 0.04, 0.44, 0.92, 0.27)
	labels.Status = signText(p, "StatusLabel", "", "Body", 30, C.Text, 0.04, 0.72, 0.92, 0.11)
	local pill = plainFrame(p, "DoublePill", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.845, 0),
		Size = UDim2.new(0.62, 0, 0.11, 0),
		BackgroundColor3 = C.GoldDark,
		BackgroundTransparency = 0,
		Visible = false,
	})
	rounded(pill, 18)
	outline(pill, C.Ink, 3)
	labels.Double = signText(pill, "DoubleLabel", "", "Heading", 30, C.Text, 0, 0, 1, 1)
	labels.DoublePill = pill
	-- the live boss's HP bar (in the pill's slot while a raid runs): the board reads at a glance from the forum
	local track = plainFrame(p, "RaidHpBar", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.855, 0),
		Size = UDim2.new(0.8, 0, 0.085, 0),
		BackgroundColor3 = C.Navy,
		BackgroundTransparency = 0,
		Visible = false,
		ClipsDescendants = true,
	})
	rounded(track, 16)
	outline(track, C.Ink, 3)
	labels.RaidFill = plainFrame(track, "Fill", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.Crimson,
		BackgroundTransparency = 0,
	})
	rounded(labels.RaidFill, 16)
	labels.RaidBar = track
	makePrompt(panel, "BoardPrompt", "Events", "Event Board", "Arena", { OpenPanelTab = "Events" })
	return { Model = m, Gui = gui, Panel = panel, Labels = labels }
end

local function buildLeaderboard(parent, cf)
	local m, panel = boardFrame(parent, "Leaderboard", cf, LEADER_W, LEADER_H)
	local gui = surfaceGui(panel, Enum.NormalId.Front)
	gui.Name = "LeaderGui"
	local p = signPanel(gui, C.TextGold)
	signText(p, "Header", "TROPHY LEADERS", "Title", 56, C.TextGold, 0.04, 0.025, 0.92, 0.11)
	local rows = {}
	local top, rowH = 0.15, 0.073
	for i = 1, 10 do
		local row = plainFrame(p, "Row" .. i, {
			Position = UDim2.new(0.03, 0, top + (i - 1) * rowH, 0),
			Size = UDim2.new(0.94, 0, rowH * 0.92, 0),
			BackgroundColor3 = (i % 2 == 0) and C.Navy or C.Violet,
			BackgroundTransparency = 0.35,
			Visible = false,
		})
		rounded(row, 10)
		local rankColor = (i == 1 and C.Gold) or (i == 2 and rgb(214, 222, 236)) or (i == 3 and rgb(226, 160, 110)) or C.TextDim
		local rank = signText(row, "Rank", tostring(i), "Display", 32, rankColor, 0.01, 0, 0.1, 1)
		local name = signText(row, "PlayerName", "", "Heading", 32, C.Text, 0.12, 0, 0.6, 1, Enum.TextXAlignment.Left)
		local trophies = signText(row, "Trophies", "", "Display", 32, C.TextGold, 0.72, 0, 0.27, 1, Enum.TextXAlignment.Right)
		rows[i] = { Frame = row, Rank = rank, Name = name, Trophies = trophies }
	end
	local empty = signText(p, "EmptyLabel", "No champions yet!", "Heading", 36, C.Text, 0.04, 0.42, 0.92, 0.1)
	local footer = signText(p, "Footer", "Win duels to earn trophies", "Body", 30, C.TextGold, 0.04, 0.895, 0.92, 0.08)
	makePrompt(panel, "BoardPrompt", "Leaders", "Trophy Leaders", "Arena", { OpenPanelTab = "Leaderboard" })
	return { Model = m, Gui = gui, Panel = panel, Rows = rows, Empty = empty, Footer = footer }
end

local function bossName(bossId)
	local bc = battleCatalog()
	local boss = bc and type(bc.Bosses) == "table" and bc.Bosses[bossId]
	if type(boss) == "table" and type(boss.Name) == "string" then
		return boss.Name, boss.Element
	end
	if type(bossId) == "string" and bossId ~= "" then
		local words = {}
		for w in bossId:gmatch("[^_]+") do
			words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2)
		end
		return table.concat(words, " "), nil
	end
	return "Boss Raid", nil
end

local function elementColorById(id)
	for _, e in ipairs(ELEMENTS) do
		if e.Id == id then
			return e.Color
		end
	end
	return nil
end

local function raidEveryMinutes()
	local bc = battleCatalog()
	local ev = bc and type(bc.Events) == "table" and bc.Events
	if ev and type(ev.Schedule) == "table" then
		for _, s in ipairs(ev.Schedule) do
			if type(s) == "table" and s.Kind == "BossRaid" and tonumber(s.EveryMinutes) then
				return tonumber(s.EveryMinutes)
			end
		end
	end
	return 20
end

-- the label's width in px from its fractions of the board canvas (SurfaceGuis lay out on the client only)
local function setLabel(label, text, px, color)
	if not label then
		return
	end
	local width = BOARD_W * SIGN_PPS * label.Size.X.Scale
	if label.Parent and label.Parent.Name == "DoublePill" then
		width = BOARD_W * SIGN_PPS * 0.62 * label.Size.X.Scale
	end
	label.Text = fitText(text, px, width - 4)
	if color then
		label.TextColor3 = color
	end
end

-- Draws the event board from S.boardState (seconds are counted down from the time the state arrived).
local function drawBoard()
	local b = S.board
	if not b then
		return
	end
	local L = b.Labels
	local st = S.boardState
	local now = os.clock()
	if st and st.RaidActive then
		setLabel(L.Next, "BOSS RAID LIVE!", 34, C.Gold)
		local name, element = bossName(st.RaidBoss)
		setLabel(L.Boss, name, 46, elementColorById(element) and elementColorById(element):Lerp(C.Text, 0.35) or C.Text)
		setLabel(L.Countdown, clockText((st.RaidEndsAt or now) - now), 100, C.Text)
		local hpText = ""
		if tonumber(st.RaidHp) and tonumber(st.RaidMaxHp) and st.RaidMaxHp > 0 then
			hpText = string.format("HP %d%%", floor(100 * max(0, st.RaidHp) / st.RaidMaxHp + 0.5))
		end
		local players = tonumber(st.RaidPlayers) or 0
		setLabel(L.Status, hpText .. (hpText ~= "" and "  " .. GLYPH.Dot .. "  " or "") .. players .. (players == 1 and " fighter" or " fighters") .. " - join in the arena!", 30, C.Text)
	elseif st and st.NextKind then
		if st.NextKind == "DoubleRewards" then
			setLabel(L.Next, "NEXT: DOUBLE REWARDS", 34, C.TextDim)
			setLabel(L.Boss, "x2 Tokens + XP", 46, C.Gold)
		else
			setLabel(L.Next, "NEXT: BOSS RAID", 34, C.TextDim)
			local name, element = bossName(st.NextBoss)
			setLabel(L.Boss, name, 46, elementColorById(element) and elementColorById(element):Lerp(C.Text, 0.35) or C.Text)
		end
		setLabel(L.Countdown, clockText((st.NextAt or now) - now), 100, C.Text)
		setLabel(L.Status, "Be in the arena with your team to join", 30, C.Text)
	else
		setLabel(L.Next, "BOSS RAIDS", 34, C.TextDim)
		setLabel(L.Boss, "Every " .. raidEveryMinutes() .. " minutes", 46, C.Text)
		setLabel(L.Countdown, "--:--", 100, C.TextDim)
		setLabel(L.Status, "Watch this board for the countdown", 30, C.Text)
	end
	local doubleOn = st and st.DoubleActive and (st.DoubleAt or 0) > now
	-- the HP bar takes the pill's slot while a raid runs, unless Double Rewards needs it (the HP % stays in the text)
	local raidBar = not doubleOn and st and st.RaidActive and tonumber(st.RaidHp) and tonumber(st.RaidMaxHp) and st.RaidMaxHp > 0
	if L.RaidBar then
		L.RaidBar.Visible = raidBar and true or false
		if raidBar then
			local f = max(0, min(1, st.RaidHp / st.RaidMaxHp))
			L.RaidFill.Size = UDim2.new(f, 0, 1, 0)
			local _, element = bossName(st.RaidBoss)
			L.RaidFill.BackgroundColor3 = elementColorById(element) or C.Crimson
		end
	end
	L.DoublePill.Visible = doubleOn and true or false
	if doubleOn then
		setLabel(L.Double, "x2 REWARDS  " .. clockText(st.DoubleAt - now), 30, C.Text)
	else
		L.Double.Text = ""
	end
end

local function drawLeaders(list)
	local lb = S.leaders
	if not lb then
		return
	end
	local shown = 0
	for i = 1, 10 do
		local row = lb.Rows[i]
		local e = type(list) == "table" and list[i] or nil
		if type(e) == "table" and (type(e.Name) == "string" or type(e.UserId) == "number") then
			shown = shown + 1
			row.Frame.Visible = true
			local nameW = LEADER_W * SIGN_PPS * 0.94 * 0.6
			row.Name.Text = fitText(tostring(e.Name or ("Player " .. tostring(e.UserId))), 32, nameW - 6)
			local t = max(0, floor(tonumber(e.Trophies) or 0))
			row.Trophies.Text = commas(t) .. " " .. GLYPH.Trophy
		else
			row.Frame.Visible = false
			row.Name.Text = ""
			row.Trophies.Text = ""
		end
	end
	lb.Empty.Visible = shown == 0
end

-- The trophies of the players in this server (when EventService sends nothing): DataService.GetBattle / GetProfile.
local function selfLeaders()
	local ds = dataService()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local trophies = nil
		if ds then
			if type(ds.GetBattle) == "function" then
				local ok, battle = pcall(ds.GetBattle, player)
				if ok and type(battle) == "table" then
					trophies = tonumber(battle.Trophies)
				end
			end
			if trophies == nil and type(ds.GetProfile) == "function" then
				local ok, prof = pcall(ds.GetProfile, player)
				if ok and type(prof) == "table" and type(prof.Battle) == "table" then
					trophies = tonumber(prof.Battle.Trophies)
				end
			end
		end
		if trophies and trophies > 0 then
			list[#list + 1] = { UserId = player.UserId, Name = player.DisplayName ~= "" and player.DisplayName or player.Name, Trophies = trophies }
		end
	end
	table.sort(list, function(a, b)
		if a.Trophies ~= b.Trophies then
			return a.Trophies > b.Trophies
		end
		return tostring(a.Name) < tostring(b.Name)
	end)
	while #list > 10 do
		table.remove(list)
	end
	return list
end

-- EventService: draws an ArenaState table on the boards (see the header).
function ArenaBuilder.ApplyArenaState(state)
	if type(state) ~= "table" then
		return false
	end
	S.external = os.clock()
	local now = os.clock()
	local st = {}
	local nxt = state.Next
	if type(nxt) == "table" and type(nxt.Kind) == "string" then
		st.NextKind = nxt.Kind
		st.NextBoss = nxt.BossId
		st.NextAt = now + max(0, tonumber(nxt.StartsIn) or 0)
	end
	local raid = state.Raid
	if type(raid) == "table" and raid.Active then
		st.RaidActive = true
		st.RaidBoss = raid.BossId
		st.RaidHp = tonumber(raid.Hp)
		st.RaidMaxHp = tonumber(raid.MaxHp)
		st.RaidPlayers = tonumber(raid.Players) or (type(raid.Players) == "table" and #raid.Players) or 0
		st.RaidEndsAt = now + max(0, tonumber(raid.EndsIn) or 0)
	end
	local double = state.Double
	if type(double) == "table" and double.Active then
		st.DoubleActive = true
		st.DoubleAt = now + max(0, tonumber(double.EndsIn) or 0)
	end
	S.boardState = st
	local ok, err = pcall(drawBoard)
	if not ok then
		warn("[ArenaBuilder] event board: " .. tostring(err))
	end
	if type(state.Leaderboard) == "table" then
		local okL, errL = pcall(drawLeaders, state.Leaderboard)
		if not okL then
			warn("[ArenaBuilder] leaderboard: " .. tostring(errL))
		end
	end
	return true
end

local function startBoardTicker()
	if S.tickRunning then
		return
	end
	S.tickRunning = true
	task.spawn(function()
		while S.model and S.model.Parent do
			task.wait(1)
			pcall(drawBoard)
			local now = os.clock()
			local silent = not S.external or now - S.external > BOARD_SILENCE
			if silent then
				if S.boardState and S.external then
					S.boardState = nil -- EventService went quiet: back to the schedule
				end
				if not S.lastFallback or now - S.lastFallback >= FALLBACK_REFRESH then
					S.lastFallback = now
					pcall(function()
						drawLeaders(selfLeaders())
					end)
				end
			end
		end
		S.tickRunning = false
	end)
end

----------------------------------------------------------------------
-- Forum decor: avenue torches, the trophy statue, banners, planters
----------------------------------------------------------------------
local torchTemplate = nil
local function torch()
	if torchTemplate then
		return torchTemplate
	end
	local m = newModel(nil, "Torch")
	box(m, "TorchBase", CFrame.new(0, 0.4, 0), Vector3.new(1.8, 0.8, 1.8), C.StoneDark, { Collide = true, Shadow = false })
	box(m, "TorchPole", CFrame.new(0, 2.9, 0), Vector3.new(0.6, 4.4, 0.6), C.Iron, { Collide = true, Shadow = false })
	box(m, "TorchBowl", CFrame.new(0, 5.3, 0), Vector3.new(1.6, 0.5, 1.6), C.Gold, { Shadow = false })
	box(m, "Flame", CFrame.new(0, 6.05, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.9, 1.1, 0.9), C.Gold, { Material = MAT.Neon, Shadow = false })
	torchTemplate = m
	return m
end

local function buildTrophy(parent, cf)
	local m = newModel(parent, "TrophyStatue")
	box(m, "Plinth", cf * CFrame.new(0, 1.25, 0), Vector3.new(7, 2.5, 7), C.StoneLight, { Collide = true })
	box(m, "PlinthTrim", cf * CFrame.new(0, 2.6, 0), Vector3.new(7.6, 0.4, 7.6), C.Gold, { Collide = true, Shadow = false })
	box(m, "PlinthBase", cf * CFrame.new(0, 0.25, 0), Vector3.new(8.4, 0.5, 8.4), C.StoneDark, { Collide = true, Shadow = false })
	local g = Voxel.NewGrid(20)
	-- a big gold cup (0.5-stud voxels): square foot, stem with a knot, two handles, a hollow bowl with a rim, a gem
	Voxel.Shape(g, { Kind = "RoundBox", Center = { 0, 1, 0 }, Size = { 10, 2, 10 }, Round = 1, Key = "Base" })
	Voxel.Shape(g, { Kind = "RoundBox", Center = { 0, 2.5, 0 }, Size = { 7, 1, 7 }, Round = 1, Key = "Gold" })
	Voxel.Shape(g, { Kind = "Capsule", A = { 0, 3, 0 }, B = { 0, 7.5, 0 }, Radius = 1.2, RadiusB = 0.9, Key = "Gold" })
	Voxel.Shape(g, { Kind = "Ellipsoid", Center = { 0, 6, 0 }, Radius = { 1.8, 0.9, 1.8 }, Key = "Gold" })
	for _, s in ipairs({ -1, 1 }) do
		Voxel.Shape(g, { Kind = "Torus", Center = { s * 5.6, 11.5, 0 }, Radius = 2.2, Thickness = 0.65, Rotation = CFrame.Angles(math.pi / 2, 0, 0), Key = "Gold" })
	end
	Voxel.Shape(g, { Kind = "Ellipsoid", Center = { 0, 12, 0 }, Radius = { 5.6, 5.2, 5.6 }, Key = "Gold" })
	Voxel.Shape(g, { Kind = "Ellipsoid", Center = { 0, 13, 0 }, Radius = { 4.6, 4.6, 4.6 }, Op = "Carve" })
	Voxel.Shape(g, { Kind = "Box", Center = { 0, 18.5, 0 }, Size = { 20, 8, 20 }, Op = "Carve" })
	Voxel.Shape(g, { Kind = "Torus", Center = { 0, 14.2, 0 }, Radius = 5.2, Thickness = 0.7, Key = "Rim" })
	Voxel.Shape(g, { Kind = "Ellipsoid", Center = { 0, 11, -5.4 }, Radius = { 1.2, 1.2, 0.6 }, Key = "Gem" })
	Voxel.Shade(g, { Only = { Gold = true, Rim = true }, Smooth = 1, Seed = 2 })
	local cup = VX.Build(g, {
		V = 0.5,
		Pal = { Base = C.Navy, Gold = C.Gold, Rim = rgb(255, 226, 132), Gem = { Color = C.Crimson, Material = MAT.Neon } },
		Name = "Trophy",
		CF = cf * CFrame.new(0, 2.8, 0),
		Collide = false,
		MaxParts = 36,
	})
	if cup then
		cup.Parent = m
	end
	local star = box(m, "TrophyStar", cf * CFrame.new(0, 2.8 + 8.8, 0) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(1.4, 1.4, 0.5), C.Gold, { Material = MAT.Neon, Shadow = false })
	emitter(star, { Rate = 3, Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(0.5, 1.2), SpreadAngle = Vector2.new(180, 180) })
	return m
end

local function bannerPole(parent, cf, color)
	local m = newModel(parent, "BannerPole")
	box(m, "PoleBase", cf * CFrame.new(0, 0.5, 0), Vector3.new(1.6, 1, 1.6), C.StoneDark, { Collide = true, Shadow = false })
	box(m, "Pole", cf * CFrame.new(0, 7, 0), Vector3.new(0.6, 13, 0.6), C.Iron, { Collide = true, Shadow = false })
	box(m, "PoleTop", cf * CFrame.new(0, 13.8, 0), Vector3.new(1, 1, 1), C.Gold, { Shadow = false })
	box(m, "CrossBar", cf * CFrame.new(1.9, 12.6, 0), Vector3.new(4.2, 0.35, 0.35), C.Iron, { Shadow = false })
	box(m, "Banner", cf * CFrame.new(1.9, 9.6, 0), Vector3.new(3.4, 5.6, 0.2), color, { Shadow = false })
	box(m, "BannerTrim", cf * CFrame.new(1.9, 12.25, 0), Vector3.new(3.6, 0.4, 0.26), C.Gold, { Shadow = false })
	box(m, "BannerMark", cf * CFrame.new(1.9, 9.9, -0.05) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(1.3, 1.3, 0.22), C.Gold, { Shadow = false })
	return m
end

local planterTemplate = nil
local function planter()
	if planterTemplate then
		return planterTemplate
	end
	local g = Voxel.NewGrid(1)
	-- a 14 x 6 raised stone bed with grass, a hedge row and flowers in the element colours
	for x = -7, 6 do
		for z = -3, 2 do
			local edge = x == -7 or x == 6 or z == -3 or z == 2
			Voxel.Set(g, x, 0, z, edge and "Curb" or "Soil")
			if not edge then
				Voxel.Set(g, x, 1, z, "Grass")
				local h = hash3(x, 1, z, 11)
				if z == 0 or z == -1 then
					if x % 3 ~= 0 then
						Voxel.Set(g, x, 2, z, "Hedge")
					end
				elseif h < 0.55 then
					Voxel.Set(g, x, 2, z, "Fl" .. (floor(h * 8) % 8 + 1))
				end
			else
				Voxel.Set(g, x, 1, z, "CurbTop")
			end
		end
	end
	local pal = { Curb = C.StoneDark, CurbTop = C.StoneLight, Soil = C.Soil, Grass = { Color = C.Grass, Material = MAT.Grass }, Hedge = C.Hedge }
	for e = 1, 8 do
		pal["Fl" .. e] = elementColor(e):Lerp(rgb(255, 255, 255), 0.15)
	end
	planterTemplate = VX.Build(g, { V = 1, Pal = pal, Name = "Planter", CF = CFrame.new(0, 0.5 - 0.2, 0), Collide = true, MaxParts = 22 })
	return planterTemplate
end

local function buildForumDecor(parent, A)
	local m = newModel(parent, "ForumDecor")
	-- torches along the avenue, in the element colours
	local t = 0
	for _, z in ipairs({ -186, -164, -142 }) do
		for _, sx in ipairs({ -1, 1 }) do
			t = t + 1
			local tm = place(torch(), A * CFrame.new(sx * 11.5, -0.2, z), m, "AvenueTorch")
			recolor(tm, "Flame", flameColor(elementColor(t)))
			local flame = tm:FindFirstChild("Flame")
			if flame and z == -164 then
				pointLight(flame, flameColor(elementColor(t)), 1, 16)
			end
		end
	end
	-- banner poles at the arrival
	bannerPole(m, A * CFrame.new(-18, -0.2, ISL.FrontZ + 10) * CFrame.Angles(0, math.pi, 0), C.Crimson)
	bannerPole(m, A * CFrame.new(18, -0.2, ISL.FrontZ + 10), C.Crimson)
	-- planters between the rings and the colosseum and at the forum's front corners
	for _, p in ipairs({ { -60, -102, 0 }, { 60, -102, 0 } }) do
		place(planter(), A * CFrame.new(p[1], 0, p[2]) * CFrame.Angles(0, p[3], 0), m, "Planter")
	end
	buildTrophy(m, A * CFrame.new(0, -0.2, -124))
	return m
end

----------------------------------------------------------------------
-- Main gate sign
----------------------------------------------------------------------
local function buildGateSign(parent, A)
	local w, h = 11, 4.6
	local cf = A * CFrame.new(0, COL.WallH + 1.6, -(COL.WallOut + 1.5))
	local part = box(parent, "GateSign", cf, Vector3.new(w, h, 0.6), C.Navy, { Collide = true, Shadow = false })
	local frame = box(parent, "GateSignFrame", cf * CFrame.new(0, 0, 0.35), Vector3.new(w + 0.8, h + 0.8, 0.4), C.Gold, { Collide = true, Shadow = false })
	frame.CanQuery = false
	local gui = surfaceGui(part, Enum.NormalId.Front)
	local p = signPanel(gui, C.TextGold)
	signText(p, "Title", "BATTLE ARENA", "Title", 64, C.TextGold, 0.04, 0.08, 0.92, 0.48)
	signText(p, "Subtitle", "Boss raids every " .. raidEveryMinutes() .. " min", "Heading", 30, C.Text, 0.04, 0.6, 0.92, 0.3)
	-- the main gate's own prompt: the arena panel (raids, duels, the queue)
	local anchor = anchorPart(parent, "GatePromptAnchor", A * CFrame.new(0, 3, -(COL.WallOut + 2)), Vector3.new(1, 1, 1))
	makePrompt(anchor, "ArenaPrompt", "Arena", "Battle Arena", "Arena", { OpenPanelTab = "Raid" })
	return part
end

----------------------------------------------------------------------
-- The bridge (stone, torches, an entrance arch at the street) from the lobby's dock to the forum
----------------------------------------------------------------------
local function archSign(part, face, title, sub)
	local gui = surfaceGui(part, face)
	local p = signPanel(gui, C.TextGold)
	signText(p, "Title", title, "Title", 62, C.TextGold, 0.04, 0.06, 0.92, 0.5)
	signText(p, "Subtitle", sub, "Heading", 30, C.Text, 0.04, 0.6, 0.92, 0.32)
	return gui
end

local function buildBridge(parent, A, startZ, endZ)
	local m = newModel(parent, "ArenaBridge")
	local len = endZ - startZ -- island-local z grows towards the island
	local mid = (startZ + endZ) / 2
	local hw = BRIDGE_W / 2
	-- deck: stone slabs (alternating shades), curbs and the crimson runner
	local slabs = max(4, floor(len / 12 + 0.5))
	local sl = len / slabs
	for i = 1, slabs do
		local z = startZ + (i - 0.5) * sl
		box(m, "Deck", A * CFrame.new(0, -0.3 - 0.5, z), Vector3.new(BRIDGE_W - 1.6, 1, sl), (i % 2 == 0) and C.StoneLight or C.Stone, { Collide = true, Material = MAT.Slate, Shadow = false })
	end
	for _, sx in ipairs({ -1, 1 }) do
		box(m, "DeckEdge", A * CFrame.new(sx * (hw - 0.4), -0.3 - 0.6, mid), Vector3.new(0.8, 1.2, len), C.StoneDark, { Collide = true, Shadow = false })
	end
	box(m, "Runner", A * CFrame.new(0, -0.3 + 0.05, mid), Vector3.new(3.6, 0.1, len - 1), C.Crimson, { Collide = true, Shadow = false })
	box(m, "Underside", A * CFrame.new(0, -1.8, mid), Vector3.new(BRIDGE_W - 2, 1, len), C.StoneDark, { Shadow = false })
	-- parapets with torch posts every ~22 studs (gaps at both ends: the street and the forum)
	local posts = {}
	local p0, p1 = startZ + 6, endZ - 4
	local nPosts = max(2, floor((p1 - p0) / 22 + 0.5) + 1)
	for i = 0, nPosts - 1 do
		posts[#posts + 1] = p0 + (p1 - p0) * i / (nPosts - 1)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for i = 1, #posts - 1 do
			local a, b = posts[i] + 0.9, posts[i + 1] - 0.9
			if b > a then
				box(m, "Parapet", A * CFrame.new(sx * (hw - 0.4), 0.55, (a + b) / 2), Vector3.new(0.8, 1.7, b - a), C.StoneLight, { Collide = true })
				box(m, "ParapetCap", A * CFrame.new(sx * (hw - 0.4), 1.5, (a + b) / 2), Vector3.new(1.1, 0.25, b - a), C.Marble, { Collide = true, Shadow = false })
			end
		end
		for i, z in ipairs(posts) do
			local tm = place(torch(), A * CFrame.new(sx * (hw - 0.4), -0.3, z), m, "BridgeTorch")
			local e = (i + (sx > 0 and 4 or 0)) % 8 + 1
			recolor(tm, "Flame", flameColor(elementColor(e)))
			local flame = tm:FindFirstChild("Flame")
			if flame and i % 2 == 1 and sx < 0 then
				pointLight(flame, flameColor(elementColor(e)), 1, 16)
			end
		end
	end
	-- the entrance arch over the bridge's foot, facing the street; its back says the way home
	local az = startZ + 3
	for _, sx in ipairs({ -1, 1 }) do
		box(m, "ArchPillar", A * CFrame.new(sx * (hw + 1.6), 7, az), Vector3.new(2, 16.4, 2), C.StoneLight, { Collide = true })
		box(m, "ArchPillarBase", A * CFrame.new(sx * (hw + 1.6), -0.6, az), Vector3.new(2.6, 1.2, 2.6), C.StoneDark, { Collide = true, Shadow = false })
		box(m, "ArchCap", A * CFrame.new(sx * (hw + 1.6), 15.5, az), Vector3.new(2.6, 0.6, 2.6), C.Gold, { Shadow = false })
		local fl = box(m, "Flame", A * CFrame.new(sx * (hw + 1.6), 16.4, az) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(1, 1.2, 1), flameColor(C.Crimson), { Material = MAT.Neon, Shadow = false })
		emitter(fl, { Color = ColorSequence.new(rgb(255, 220, 160), C.Crimson), Rate = 3, Speed = NumberRange.new(1, 2), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(15, 15) })
	end
	box(m, "ArchLintel", A * CFrame.new(0, 14.6, az), Vector3.new(BRIDGE_W + 6, 1.2, 2.4), C.Marble, { Collide = true })
	local sign = box(m, "ArchSign", A * CFrame.new(0, 11.5, az), Vector3.new(12, 4, 0.6), C.Navy, { Collide = true, Shadow = false })
	box(m, "ArchSignTrim", A * CFrame.new(0, 13.75, az), Vector3.new(12.6, 0.4, 0.9), C.Gold, { Shadow = false })
	-- the arch's local frame: Front (-Z) faces the street (the lobby)
	archSign(sign, Enum.NormalId.Front, "BATTLE ARENA", "Duels " .. GLYPH.Dot .. " Boss Raids " .. GLYPH.Dot .. " Trophies")
	archSign(sign, Enum.NormalId.Back, "TO THE PLAZA", "Homes " .. GLYPH.Dot .. " Portals " .. GLYPH.Dot .. " Shop")
	-- puffs under the open stretch next to the island
	local puff = puffTemplate(1.3)
	for _, z in ipairs({ endZ - 14, endZ - 34 }) do
		if z > startZ + 20 then
			place(puff, A * CFrame.new(0, -1.6, z), m, "BridgePuff")
		end
	end
	return m
end

----------------------------------------------------------------------
-- The Trial Portal (plaza), styled like the difficulty portals: crimson, crossed swords instead of stars
----------------------------------------------------------------------
local TRIAL_COLOR = rgb(222, 74, 80)
local gateBoxCache = nil

local function gatePalette(color)
	return {
		Stone = C.StoneLight,
		StoneDark = C.Stone,
		Frame = C.CloudLight,
		Puff = C.Cloud,
		Trim = color,
		Glow = { Color = color, Material = MAT.Neon },
		Swirl = { Color = color:Lerp(rgb(255, 255, 255), 0.35), Material = MAT.Neon, Transparency = 0.62 },
		Gem = { Color = C.Gold, Material = MAT.Neon },
	}
end

local function gateBoxes()
	if gateBoxCache then
		return gateBoxCache
	end
	local g = Voxel.NewGrid(24)
	VX.RoundRect(g, 0, 0, 22, 5, 1.5, 0, 0, "StoneDark")
	VX.RoundRect(g, 0, 0, 20, 4, 1.2, 1, 1, "Stone")
	for _, s in ipairs({ -1, 1 }) do
		VX.RoundRect(g, s * 9, 0, 3, 3.4, 0.8, 2, 10, "Stone")
		VX.RoundRect(g, s * 9, 0, 4, 4.2, 1, 11, 11, "Trim")
		VX.Fill(g, s * 9, s * 9, 12, 13, 0, 0, "Glow")
		VX.Fill(g, s * 9, s * 9, 3, 3, -2, -2, "Trim")
	end
	local ringRot = CFrame.Angles(pi / 2, 0, 0)
	Voxel.Shape(g, { Kind = "Torus", Center = { 0, 11, 0 }, Radius = 7.6, Thickness = 1.6, Rotation = ringRot, Key = "Frame" })
	Voxel.Shape(g, { Kind = "Torus", Center = { 0, 11, 0 }, Radius = 5.9, Thickness = 0.5, Rotation = ringRot, Key = "Glow" })
	Voxel.Shape(g, { Kind = "Ellipsoid", Center = { 0, 11, 0 }, Radius = { 5.3, 5.3, 0.2 }, Key = "Swirl", KeepExisting = true })
	Voxel.Shape(g, {
		Kind = "Torus",
		Center = { 0, 11, 0 },
		Radius = 7.6,
		Thickness = 2.2,
		Rotation = ringRot,
		Op = "Paint",
		OnlyKeys = { Frame = true },
		Key = "Trim",
		Pattern = function(x, y, z)
			local dy = y - 11
			if sqrt(x * x + dy * dy) >= 8.6 then
				return "Trim"
			end
			return false
		end,
	})
	VX.RoundRect(g, 0, 0, 4, 3, 0.8, 19, 20, "Trim")
	Voxel.Set(g, 0, 20, -2, "Gem")
	Voxel.Set(g, 0, 19, -2, "Gem")
	Voxel.Shade(g, { Skip = { Glow = true, Swirl = true, Gem = true }, Smooth = 1, Seed = 8 })
	gateBoxCache = Voxel.Merge(g, {
		Palette = gatePalette(TRIAL_COLOR),
		MaxParts = 105,
		Keep = { "Stone", "StoneDark", "Frame", "Trim", "Glow", "Swirl", "Gem" },
	})
	return gateBoxCache
end

-- `site`: CFrame on the plaza ground, LookVector = towards the plaza centre. Returns the model and the pad part.
local function buildTrialPortal(parent, site, color, id, title, info, pill)
	local model = newModel(parent, "Portal_" .. id)
	color = color or TRIAL_COLOR
	local padCF = site
	local outward = -site.LookVector
	-- the ready pad: a tiled 14 x 14 voxel plate, 0.3 above the stone, with a glowing X (crossed swords) in the middle
	local pg = Voxel.NewGrid(14)
	for i = -7, 6 do
		for k = -7, 6 do
			local ring = min(i + 7, 6 - i, k + 7, 6 - k)
			local ci, ck = i + 0.5, k + 0.5
			local key = "Stone"
			if ring == 0 then
				key = "Trim"
			elseif ring == 1 then
				key = "StoneLight"
			elseif abs(abs(ci) - abs(ck)) < 0.6 and abs(ci) <= 4 then
				key = "Glow"
			end
			Voxel.Set(pg, i, 0, k, key)
		end
	end
	local pad = VX.Build(pg, {
		V = 1,
		Name = "Pad",
		CF = padCF * CFrame.new(0.5, 0.3 - 0.5, 0.5),
		Collide = true,
		Parent = model,
		Pal = { Stone = C.Stone, StoneLight = C.StoneLight, Trim = color, Glow = { Color = color, Material = MAT.Neon } },
	})
	if pad and pad.PrimaryPart then
		model.PrimaryPart = pad.PrimaryPart
	end
	-- the prompt part (invisible, on the pad): ArenaInfo.TrialPortal
	local padPart = box(model, "PortalPad", padCF * CFrame.new(0, 0.6, 0), Vector3.new(14, 0.6, 14), color, { Transparency = 1, Shadow = false })
	padPart.CanCollide = false
	padPart.CanQuery = false
	-- lanterns on the two front corners
	for _, sx in ipairs({ -1, 1 }) do
		local base = padCF * CFrame.new(sx * 7.9, 0, -7.9)
		box(model, "LanternPost", base * CFrame.new(0, 1.6, 0), Vector3.new(0.7, 3.2, 0.7), C.Iron, { Collide = true })
		box(model, "LanternCap", base * CFrame.new(0, 3.35, 0), Vector3.new(1.1, 0.3, 1.1), C.Iron)
		box(model, "LanternGlow", base * CFrame.new(0, 3.95, 0), Vector3.new(0.9, 0.9, 0.9), color, { Material = MAT.Neon })
	end
	-- the gate behind the pad
	local gateBase = padCF.Position + outward * 9.5
	local gateCF = flatLook(gateBase, gateBase - outward)
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	Voxel.BuildBoxes(gateBoxes(), {
		VoxelSize = 1,
		Palette = gatePalette(color),
		CFrame = gateCF * CFrame.new(0, 0.5, 0),
		Model = gate,
		CanCollide = true,
		CanQuery = true,
	})
	for _, d in ipairs(gate:GetChildren()) do
		if d:IsA("BasePart") and (d.Name == "Swirl" or d.Name == "Puff" or d.Name == "Gem") then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	gate.Parent = model
	local core = box(model, "SwirlCore", gateCF * CFrame.new(0, 11.5, 0), Vector3.new(9, 9, 0.4), color, { Transparency = 1, Shadow = false })
	pointLight(core, color, 1.3, 28)
	emitter(core, {
		Color = ColorSequence.new(color:Lerp(rgb(255, 255, 255), 0.5), color),
		Rate = 12,
		Lifetime = NumberRange.new(1.4, 2.2),
		Speed = NumberRange.new(1.5, 3.5),
		EmissionDirection = Enum.NormalId.Front,
		SpreadAngle = Vector2.new(30, 30),
		Size = popSize(0.9),
	})
	-- crossed swords + a gold shield over the keystone (instead of the difficulty stars)
	box(model, "CrestPost", gateCF * CFrame.new(0, 21.6, 0), Vector3.new(0.8, 1.3, 0.6), C.GoldDark, { Shadow = false })
	box(model, "CrestShield", gateCF * CFrame.new(0, 23.4, 0), Vector3.new(2.4, 2.6, 0.7), color:Lerp(C.Navy, 0.2), { Shadow = false })
	box(model, "CrestShieldRim", gateCF * CFrame.new(0, 23.4, 0.15), Vector3.new(2.9, 3.1, 0.5), C.Gold, { Shadow = false })
	for _, s in ipairs({ -1, 1 }) do
		local scf = gateCF * CFrame.new(0, 23.6, -0.5) * CFrame.Angles(0, 0, math.rad(s * 42))
		box(model, "CrestBlade", scf * CFrame.new(0, 0.6, 0), Vector3.new(0.45, 5, 0.2), C.Steel, { Shadow = false })
		box(model, "CrestGuard", scf * CFrame.new(0, -1.9, 0), Vector3.new(1.5, 0.35, 0.3), C.Gold, { Shadow = false })
		box(model, "CrestGrip", scf * CFrame.new(0, -2.5, 0), Vector3.new(0.35, 0.9, 0.3), C.GoldDark, { Shadow = false })
	end
	-- the pixel tag above the crest (World text rule)
	local cardH = 15
	local anchor = anchorPart(model, "BillboardAnchor", CFrame.new(gateBase + Vector3.new(0, 26.4 + cardH / 2, 0)))
	local gui = newTag(anchor, "PortalBillboard", 380, 150, 1.2 - cardH / 2, 120)
	local plate = tagPlate(gui, color:Lerp(C.Text, 0.15), 200)
	tagText(plate, "TitleLabel", title, "Title", 32, color:Lerp(C.Text, 0.6), 1)
	tagText(plate, "InfoLabel", info, "Heading", 21, C.Text, 2)
	tagPill(plate, "StatusPill", pill, "Display", 24, color:Lerp(C.Navy, 0.25), 3)
	return model, padPart
end

----------------------------------------------------------------------
-- Pockets: the private trial arenas (one template, cloned onto a grid far out in the sky)
----------------------------------------------------------------------
local POCKET_FLOOR = 64 -- square floor (studs)

local function pocketSdf(x, z)
	local h, r = 46, 14
	local qx, qz = abs(x) - (h - r), abs(z) - (h - r)
	local ox, oz = max(qx, 0), max(qz, 0)
	return sqrt(ox * ox + oz * oz) + min(max(qx, qz), 0) - r
end

local function pocketTemplate()
	if S.pocketTpl then
		return S.pocketTpl
	end
	local m = newModel(nil, "TrialPocket")
	local rng = Util.NewRng(SEED + 5)
	-- cloud body
	local puffs = {}
	for deg = 0, 359, 30 do
		local a = rad(deg)
		local s = rng:Float(10, 13)
		puffs[#puffs + 1] = { cos(a) * 44, rng:Float(-8, -5), sin(a) * 44, s, s * 0.6, s }
	end
	puffs[#puffs + 1] = { 0, -20, 0, 30, 10, 30 }
	local g = cloudGrid({
		V = 4,
		Sdf = pocketSdf,
		Bounds = { -52, 52, -52, 52 },
		Tiers = { { Inset = 0, H = 1 }, { Inset = 8, H = 1 }, { Inset = 20, H = 2 } },
		Puffs = puffs,
		Carve = function(x, y, z)
			return y > 0 and pocketSdf(x, z) < -3
		end,
		Seed = 12,
	})
	VX.Build(g, { V = 4, Pal = CLOUD_PAL, Name = "PocketCloud", CF = CFrame.new(0, -1.2 - 2, 0), Collide = true, MaxParts = 70, Parent = m })
	-- the floor (2-stud cells): a stone border with gold corners, a crimson line inside it and sand
	local fg = Voxel.NewGrid(1)
	local hf = POCKET_FLOOR / 2
	for i = -hf / 2, hf / 2 - 1 do
		for k = -hf / 2, hf / 2 - 1 do
			local x, z = i * 2 + 1, k * 2 + 1
			local ax, az = abs(x), abs(z)
			local key = "Sand"
			if ax >= hf - 4 or az >= hf - 4 then
				if ax >= hf - 4 and az >= hf - 4 then
					key = "Gold"
				else
					key = "Stone"
				end
			elseif ax >= hf - 6 or az >= hf - 6 then
				key = "Line"
			elseif vnoise(x - x % 4, z - z % 4, 24, SEED + 21) < 0.32 then
				key = "SandDark" -- raked drifts so the sand never reads as one flat colour
			end
			Voxel.Set(fg, i, 0, k, key)
		end
	end
	local floorPal = {
		Sand = { Color = C.Sand, Material = MAT.Sand },
		SandDark = { Color = C.SandDrift, Material = MAT.Sand },
		Stone = { Color = C.Stone, Material = MAT.Slate },
		StoneLight = { Color = C.StoneLight, Material = MAT.Slate },
		Gold = C.Gold,
		Line = C.Crimson,
	}
	VX.Build(fg, {
		V = 2,
		Pal = floorPal,
		Name = "PocketFloor",
		CF = CFrame.new(1, -1, 1),
		Collide = true,
		Shadow = false,
		MaxParts = 58,
		Parent = m,
	})
	-- the element wheel (like the colosseum's, smaller): eight petals in the element colours, a gold rim and core
	local wheel = newModel(m, "ElementWheel")
	for e = 1, 8 do
		box(wheel, "WheelPetal", CFrame.Angles(0, sectionAngle(e), 0) * CFrame.new(0, -0.45, -7.4), Vector3.new(3.2, 1, 5.6), elementColor(e), { Collide = true, Shadow = false })
	end
	ring16(wheel, "WheelRim", CFrame.new(), 10.5, 11.6, 0.05, 1, C.Gold, nil, true)
	disc16(wheel, "WheelCore", CFrame.new(), 4.2, 0.05, 1, C.Gold, nil, true)
	ring16(wheel, "FloorCircle", CFrame.new(), 21, 22.2, 0.02, 1, C.SandLight, MAT.Sand, true)
	-- low crenellated walls on the four sides and corner towers with braziers
	local wallH = 3
	for side = 0, 3 do
		local cf = CFrame.Angles(0, side * pi / 2, 0)
		box(m, "PocketWall", cf * CFrame.new(0, wallH / 2 - 0.5, -(hf + 1)), Vector3.new(POCKET_FLOOR + 4, wallH + 1, 2), C.StoneLight, { Collide = true })
		for i = -4, 4 do
			if i ~= 0 then
				box(m, "Merlon", cf * CFrame.new(i * 7, wallH + 0.6, -(hf + 1)), Vector3.new(3, 1.2, 2), C.StoneLight, { Collide = true, Shadow = false })
			end
		end
		box(m, "WallStripe", cf * CFrame.new(0, 1.6, -(hf - 0.05)), Vector3.new(POCKET_FLOOR - 2, 0.6, 0.2), C.Crimson, { Shadow = false })
		-- two element banners hanging over the inner face of every wall (gold rod, cloth, a darker hem)
		for b, bx in ipairs({ -17, 17 }) do
			local col = elementColor(side * 2 + b)
			local bcf = cf * CFrame.new(bx, 0, -(hf - 0.1))
			box(m, "BannerRod", bcf * CFrame.new(0, 4.5, 0.05), Vector3.new(4.2, 0.35, 0.35), C.Gold, { Shadow = false })
			box(m, "Banner", bcf * CFrame.new(0, 2.6, 0.15), Vector3.new(3.2, 3.6, 0.2), col, { Shadow = false })
			box(m, "BannerHem", bcf * CFrame.new(0, 0.6, 0.15), Vector3.new(3.2, 0.5, 0.22), col:Lerp(C.Navy, 0.35), { Shadow = false })
		end
		local tower = cf * CFrame.new(hf + 1, 0, -(hf + 1))
		box(m, "Tower", tower * CFrame.new(0, 3.5, 0), Vector3.new(5, 8, 5), C.Stone, { Collide = true })
		box(m, "TowerTop", tower * CFrame.new(0, 7.8, 0), Vector3.new(6, 0.6, 6), C.Gold, { Collide = true, Shadow = false })
		box(m, "Brazier", tower * CFrame.new(0, 8.4, 0), Vector3.new(2.4, 0.6, 2.4), C.Iron, { Shadow = false })
		local fl = box(m, "Flame", tower * CFrame.new(0, 9.4, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(1.4, 1.6, 1.4), flameColor(elementColor(side * 2 + 2)), { Material = MAT.Neon, Shadow = false })
		if side % 2 == 0 then
			pointLight(fl, flameColor(elementColor(side * 2 + 2)), 1, 22)
		end
	end
	-- the fighter's pad (side 1, -Z) and the enemies' gate (side 2, +Z)
	box(m, "SpawnPad", CFrame.new(0, 0.1, -(hf - 7)), Vector3.new(7, 0.4, 7), C.Gold, { Collide = true, Shadow = false })
	box(m, "SpawnGlow", CFrame.new(0, 0.32, -(hf - 7)), Vector3.new(5.6, 0.2, 5.6), rgb(96, 196, 108), { Material = MAT.Neon, Shadow = false })
	box(m, "EnemyPad", CFrame.new(0, 0.1, hf - 7), Vector3.new(7, 0.4, 7), C.Iron, { Collide = true, Shadow = false })
	box(m, "EnemyGlow", CFrame.new(0, 0.32, hf - 7), Vector3.new(5.6, 0.2, 5.6), C.Crimson, { Material = MAT.Neon, Shadow = false })
	box(m, "EnemyGate", CFrame.new(0, 3, hf + 0.2), Vector3.new(10, 6, 0.6), C.Recess, { Collide = true, Shadow = false })
	for i = -2, 2 do
		box(m, "GateBar", CFrame.new(i * 2, 3, hf - 0.25), Vector3.new(0.4, 6, 0.4), C.Iron, { Collide = true, Shadow = false })
	end
	box(m, "GateArch", CFrame.new(0, 6.6, hf), Vector3.new(12, 1.2, 1.4), C.Gold, { Collide = true, Shadow = false })
	S.pocketTpl = m
	return m
end

function ArenaBuilder.GetPocket(index)
	return S.pockets[index]
end

function ArenaBuilder.BuildPocket(index)
	index = tonumber(index)
	if not index or index ~= index or index < 1 or index > MAX_POCKETS or index ~= floor(index) then
		return nil
	end
	local existing = S.pockets[index]
	if existing and existing.Model and existing.Model.Parent then
		return existing
	end
	if not Voxel then
		return nil
	end
	local okT, tpl = pcall(pocketTemplate)
	if not okT or not tpl then
		warn("[ArenaBuilder] pocket template failed: " .. tostring(tpl))
		return nil
	end
	local col = (index - 1) % POCKET_COLUMNS
	local row = floor((index - 1) / POCKET_COLUMNS)
	local pos = POCKET_ORIGIN + Vector3.new(col * POCKET_SPACING, 0, row * POCKET_SPACING)
	local cf = CFrame.new(pos)
	local holder = Workspace:FindFirstChild("BattlePockets")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "BattlePockets"
		holder.Parent = Workspace
	end
	local model = place(tpl, cf, holder, "TrialPocket_" .. index)
	model:SetAttribute("PocketIndex", index)
	local floorSize = zoneFloorSize("Trial")
	local zone = makeZone(model, "BattleZone_Pocket", cf, POCKET_FLOOR / 2 + 2, "Trial", floorSize, "Pocket", index)
	local hf = POCKET_FLOOR / 2
	local spawn = CFrame.lookAt(pos + Vector3.new(0, 3, -(hf - 7)), pos + Vector3.new(0, 3, hf))
	local info = { Model = model, CFrame = cf, Size = floorSize, Spawn = spawn, Zone = zone, Index = index }
	S.pockets[index] = info
	return info
end

function ArenaBuilder.FreePocket(zone)
	local index = nil
	if type(zone) == "number" then
		index = zone
	elseif type(zone) == "table" then
		index = tonumber(zone.Index)
		if not index and zone.Model then
			for i, p in pairs(S.pockets) do
				if p.Model == zone.Model then
					index = i
				end
			end
		end
	elseif typeof(zone) == "Instance" then
		for i, p in pairs(S.pockets) do
			if p.Model == zone or p.Zone == zone then
				index = i
			end
		end
	end
	local info = index and S.pockets[index]
	if not info then
		return false
	end
	S.pockets[index] = nil
	if info.Model then
		info.Model:Destroy()
	end
	-- the holder goes away with the last pocket (the workspace stays as tidy as before the first trial)
	local holder = Workspace:FindFirstChild("BattlePockets")
	if holder and next(S.pockets) == nil and #holder:GetChildren() == 0 then
		holder:Destroy()
	end
	return true
end

----------------------------------------------------------------------
-- Teleports: the home Arena Gate (HomeBuilder's ArenaGatePrompt) and the fallback portals
----------------------------------------------------------------------
local function notify(player, text, kind)
	if not Remotes then
		return
	end
	local ok, remote = pcall(Remotes.Get, "Notify")
	if ok and remote then
		pcall(function()
			remote:FireClient(player, text, kind or "info", 3)
		end)
	end
end

local function placeCharacter(char, cf)
	if not char or not char.Parent then
		return false
	end
	local ok = pcall(function()
		char:PivotTo(cf)
	end)
	if not ok then
		return false
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end
	return true
end

local function promptPosition(prompt)
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function teleport(player, prompt, target, where, source)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return false
	end
	if typeof(target) ~= "CFrame" then
		return false
	end
	local now = os.clock()
	local last = S.lastTeleport[player]
	if last and now - last < TELEPORT_COOLDOWN then
		return false
	end
	if player:GetAttribute(Config.Attr.InMatch) == true then
		return false
	end
	local inBattle = player:GetAttribute(ATTR_IN_BATTLE)
	if inBattle ~= nil and inBattle ~= false and inBattle ~= "" and inBattle ~= 0 then
		notify(player, "Finish your battle first!", "bad")
		S.lastTeleport[player] = now
		return false
	end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return false
	end
	-- only from the gate (never trust the client): the character must stand near the prompt
	local at = promptPosition(prompt)
	local range = (tonumber(prompt.MaxActivationDistance) or PROMPT_RANGE) + TELEPORT_SLACK
	if not at or (root.Position - at).Magnitude > range then
		return false
	end
	S.lastTeleport[player] = now
	-- a little spread so friends arriving together do not stack
	local rng = Random.new(player.UserId + floor(now * 10))
	local cf = target * CFrame.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-2, 2))
	if not placeCharacter(char, cf) then
		return false
	end
	if where == "Arena" then
		notify(player, "Welcome to the Battle Arena!", "info")
	end
	ArenaBuilder.Teleported:Fire(player, where, source)
	return true
end

local function onPromptTriggered(prompt, player)
	if typeof(prompt) ~= "Instance" or not S.info then
		return
	end
	local name = prompt.Name
	if name == "ArenaGatePrompt" then
		-- the home Arena Gate: only its owner (HomeBuilder writes OwnerUserId on every station prompt)
		if prompt:GetAttribute("Teleport") ~= "Arena" and prompt:GetAttribute("StationId") ~= "ArenaGate" then
			return
		end
		local owner = tonumber(prompt:GetAttribute("OwnerUserId"))
		if not owner or owner == 0 or owner ~= player.UserId then
			return
		end
		teleport(player, prompt, S.info.Spawn, "Arena", "ArenaGate")
	elseif name == "ArenaPortalPrompt" and prompt:IsDescendantOf(S.model or Workspace) then
		teleport(player, prompt, S.info.Spawn, "Arena", "Portal")
	elseif name == "ArenaReturnPrompt" and prompt:IsDescendantOf(S.model or Workspace) then
		teleport(player, prompt, S.info.LobbyCFrame or S.info.ReturnCFrame, "Lobby", "Portal")
	end
end

local function connectPrompts()
	if S.promptConn then
		return
	end
	S.promptConn = ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local ok, err = pcall(onPromptTriggered, prompt, player)
		if not ok then
			warn("[ArenaBuilder] prompt: " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		S.lastTeleport[player] = nil
	end)
end

----------------------------------------------------------------------
-- Placement: on the arena ray, just beyond everything of the lobby
----------------------------------------------------------------------
local function lobbyReach(folder, dir, side, halfW, y0, y1)
	local best = 0
	if not folder then
		return best
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			local s = d.Size / 2
			local cf = d.CFrame
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = (cf * CFrame.new(sx * s.X, sy * s.Y, sz * s.Z)).Position
						if p.Y >= y0 and p.Y <= y1 then
							local rel = p - ORIGIN
							local lat = rel.X * side.X + rel.Z * side.Z
							if abs(lat) <= halfW then
								local along = rel.X * dir.X + rel.Z * dir.Z
								if along > best then
									best = along
								end
							end
						end
					end
				end
			end
		end
	end
	return best
end

-- the corridor of the bridge: anything of the lobby above the deck between the dock and the island?
local function corridorBlocked(folder, dir, side, from, to)
	if not folder then
		return nil
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "StormfangShowcase" then
			local s = d.Size / 2
			local cf = d.CFrame
			local minA, maxA, minL, maxL, minY, maxY = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = (cf * CFrame.new(sx * s.X, sy * s.Y, sz * s.Z)).Position - ORIGIN
						local along = p.X * dir.X + p.Z * dir.Z
						local lat = p.X * side.X + p.Z * side.Z
						minA, maxA = min(minA, along), max(maxA, along)
						minL, maxL = min(minL, lat), max(maxL, lat)
						minY, maxY = min(minY, p.Y + ORIGIN.Y), max(maxY, p.Y + ORIGIN.Y)
					end
				end
			end
			if maxA > from and minA < to and maxY > TOP - 1.1 and minY < TOP + 12 and maxL > -(BRIDGE_W / 2 + 3) and minL < BRIDGE_W / 2 + 3 then
				return d
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
local function section(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		warn("[ArenaBuilder] " .. name .. " failed: " .. tostring(err))
	end
	return ok
end

function ArenaBuilder.Build(lobbyInfo)
	lobbyInfo = type(lobbyInfo) == "table" and lobbyInfo or {}
	segTemplates = {}
	pillarTemplate = nil
	ringPostTemplate = nil
	emblemTemplates = {}
	torchTemplate = nil
	planterTemplate = nil
	gateBoxCache = nil

	local old = Workspace:FindFirstChild(ARENA_NAME)
	if old then
		old:Destroy()
	end
	if not Voxel then
		warn("[ArenaBuilder] shared/Voxel is missing: no arena in this build")
		return nil
	end

	local model = Instance.new("Model")
	model.Name = ARENA_NAME
	S.model = model

	-- where: the arena ray (the spoke just past the last portal), beyond the homes
	local angle = tonumber(lobbyInfo.ArenaAngle) or DEFAULT_ANGLE
	local dir = Vector3.new(cos(rad(angle)), 0, sin(rad(angle)))
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local folder = typeof(lobbyInfo.Folder) == "Instance" and lobbyInfo.Folder or nil
	local reach = lobbyReach(folder, dir, side, ISL.HalfW + ISL.Clearance + 6, TOP - 60, TOP + 50)
	local front = max(reach + ISL.Clearance + 8, (LOBBY.SpotRingRadius or 300) + 40)
	local centre = Vector3.new(ORIGIN.X, TOP, ORIGIN.Z) + dir * (front - ISL.FrontZ)
	local A = CFrame.lookAt(centre, centre - dir)
	S.A = A
	S.lobby = lobbyInfo

	-- how it links to the plaza: a bridge from the lobby's dock, unless something blocks its corridor
	local dock = typeof(lobbyInfo.ArenaDock) == "Vector3" and lobbyInfo.ArenaDock or nil
	local link = "Portal"
	local dockAlong = nil
	if dock then
		local rel = dock - ORIGIN
		dockAlong = rel.X * dir.X + rel.Z * dir.Z
		local lat = rel.X * side.X + rel.Z * side.Z
		local blocker = nil
		if abs(lat) > 1 or dockAlong >= front then
			blocker = "the dock is off the arena ray"
		else
			blocker = corridorBlocked(folder, dir, side, dockAlong + 1.5, front + 1)
		end
		if blocker == nil then
			link = "Bridge"
		else
			warn("[ArenaBuilder] no bridge (" .. (typeof(blocker) == "Instance" and blocker:GetFullName() or tostring(blocker)) .. "): linking the arena with portals")
		end
	end

	section("cloud", function()
		buildCloud(model, A)
	end)
	section("ground", function()
		buildGround(model, A)
	end)
	section("colosseum", function()
		buildColosseum(model, A)
	end)
	section("gate sign", function()
		buildGateSign(model, A)
	end)

	-- the battle floor (raid)
	local zones = newModel(model, "BattleZones")
	local floorCF = A
	local floorSize = zoneFloorSize("Raid")
	local floorZone = makeZone(zones, "BattleZone_Arena", floorCF, COL.FloorR + 3, "Raid", floorSize, "Arena", 1)

	-- duel rings
	local rings = {}
	for i, spec in ipairs(RINGS) do
		local okR, ringModel, ringCF, pads = pcall(buildRing, model, A, spec, i)
		if not okR then
			warn("[ArenaBuilder] duel ring " .. i .. " failed: " .. tostring(ringModel))
			ringCF = A * CFrame.new(spec.X, 0, spec.Z)
			pads = {}
		end
		local surface = ringCF * CFrame.new(0, RING_Y, 0)
		local ringSize = zoneFloorSize("Duel")
		local zone = makeZone(zones, "BattleZone_Ring" .. i, surface, RING_A + 2.5, "Duel", ringSize, "Ring" .. i, i)
		rings[i] = { CFrame = surface, Size = ringSize, Pads = pads or {}, Zone = zone, Index = i, Name = spec.Name }
	end

	-- boards
	local eventBoard, leaderboard = nil, nil
	section("event board", function()
		local cf = A * CFrame.new(-30, -0.2, -106) * CFrame.Angles(0, math.rad(-16), 0)
		eventBoard = buildEventBoard(model, cf)
	end)
	section("leaderboard", function()
		local cf = A * CFrame.new(30, -0.2, -106) * CFrame.Angles(0, math.rad(16), 0)
		leaderboard = buildLeaderboard(model, cf)
	end)
	S.board = eventBoard
	S.leaders = leaderboard

	section("forum decor", function()
		buildForumDecor(model, A)
	end)

	-- the link
	if link == "Bridge" then
		local startZ = -(front - dockAlong) + ISL.FrontZ
		local okB = section("bridge", function()
			buildBridge(model, A, startZ - 0.6, ISL.FrontZ + 2)
		end)
		if not okB then
			link = "Portal"
		end
	end

	-- the Trial Portal on the plaza
	local site = typeof(lobbyInfo.TrialSite) == "CFrame" and lobbyInfo.TrialSite or flatLook(polar(225, LOBBY.PortalRingRadius or 88, TOP), Vector3.new(ORIGIN.X, TOP, ORIGIN.Z))
	local trialPad = nil
	section("trial portal", function()
		local _, pad = buildTrialPortal(model, site, TRIAL_COLOR, "Trials", "Trial Portal", "Fight NPC pet teams", "30 levels")
		trialPad = pad
		makePrompt(pad, "TrialPrompt", "Trials", "Trial Portal", "Trials")
	end)
	if not trialPad then
		trialPad = box(model, "TrialPortalPad", site * CFrame.new(0, 0.6, 0), Vector3.new(14, 0.6, 14), TRIAL_COLOR, { Transparency = 1, Shadow = false })
		trialPad.CanCollide = false
		makePrompt(trialPad, "TrialPrompt", "Trials", "Trial Portal", "Trials")
	end
	local returnCF = CFrame.lookAt(site.Position + site.LookVector * 12 + Vector3.new(0, 3, 0), site.Position + site.LookVector * 30 + Vector3.new(0, 3, 0))

	-- the arrival point on the forum, looking at the main gate
	local spawnPos = (A * CFrame.new(0, 3, ISL.FrontZ + 20)).Position
	local spawn = CFrame.lookAt(spawnPos, (A * CFrame.new(0, 3, 0)).Position)

	-- fallback link: an Arena Portal on the plaza next to the Trial Portal + a Return Portal on the forum
	local lobbyCF = nil
	if link == "Portal" then
		section("portals", function()
			local rel = site.Position - Vector3.new(ORIGIN.X, TOP, ORIGIN.Z)
			local siteAngle = math.deg(atan2(rel.Z, rel.X))
			local aSite = flatLook(polar(siteAngle + 16, Vector3.new(rel.X, 0, rel.Z).Magnitude, TOP), Vector3.new(ORIGIN.X, TOP, ORIGIN.Z))
			local _, aPad = buildTrialPortal(model, aSite, C.Gold, "Arena", "Battle Arena", "Duels and Boss Raids", "Press E")
			makePrompt(aPad, "ArenaPortalPrompt", "Travel", "Battle Arena")
			local rSite = A * CFrame.new(0, 0, ISL.FrontZ + 34) * CFrame.Angles(0, pi, 0)
			local _, rPad = buildTrialPortal(model, rSite, rgb(96, 190, 140), "Return", "To the Plaza", "Homes, portals, shop", "Press E")
			makePrompt(rPad, "ArenaReturnPrompt", "Travel", "Plaza")
			lobbyCF = CFrame.lookAt(aSite.Position + aSite.LookVector * 12 + Vector3.new(0, 3, 0), aSite.Position + aSite.LookVector * 30 + Vector3.new(0, 3, 0))
		end)
	end

	model.Parent = Workspace
	connectPrompts()

	local parts = countParts(model)
	local info = {
		Model = model,
		Center = A,
		Floor = { CFrame = floorCF, Size = floorSize, Zone = floorZone },
		Rings = rings,
		Spawn = spawn,
		ReturnCFrame = returnCF,
		TrialPortal = trialPad,
		Radius = sqrt(ISL.HalfW * ISL.HalfW + ISL.FrontZ * ISL.FrontZ),
		Bounds = { CFrame = A * CFrame.new(0, 20, (ISL.FrontZ + ISL.DiscR) / 2), Size = Vector3.new(ISL.HalfW * 2 + 24, 90, ISL.DiscR - ISL.FrontZ + 24) },
		Link = link,
		LobbyCFrame = lobbyCF,
		EventBoard = eventBoard,
		Leaderboard = leaderboard,
		Parts = parts,
		ApplyArenaState = ArenaBuilder.ApplyArenaState,
		InArena = ArenaBuilder.InArena,
	}
	S.info = info
	S.external = nil
	S.boardState = nil
	S.lastFallback = nil
	pcall(drawBoard)
	pcall(drawLeaders, {})
	startBoardTicker()
	if parts > PART_BUDGET then
		warn(string.format("[ArenaBuilder] the arena has %d parts (budget %d)", parts, PART_BUDGET))
	end
	print(string.format("[ArenaBuilder] Battle Arena built (%d parts, %s link, %.0f studs out at %.1f degrees)", parts, link, front, angle))
	return info
end

function ArenaBuilder.GetInfo()
	return S.info
end

-- On (or just above) the arena island: inside its outline (island-local) and within its height band.
function ArenaBuilder.InArena(position)
	if typeof(position) ~= "Vector3" or not S.A then
		return false
	end
	local rel = S.A:PointToObjectSpace(position)
	if rel.Y < -20 or rel.Y > 70 then
		return false
	end
	return islandSdf(rel.X, rel.Z) <= 2
end

-- The NC_BattleZone part (arena floor, a duel ring or a pocket) that contains the position.
function ArenaBuilder.ZoneAt(position)
	if typeof(position) ~= "Vector3" then
		return nil
	end
	for _, part in ipairs(CollectionService:GetTagged(ZONE_TAG)) do
		if part:IsA("BasePart") and part:IsDescendantOf(Workspace) and insideZonePart(part, position) then
			return part
		end
	end
	return nil
end

return ArenaBuilder
