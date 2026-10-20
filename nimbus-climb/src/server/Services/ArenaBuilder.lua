-- ArenaBuilder (Phase 3, arenaworld; Phase 5 worldlobby: the Trials are gone, the two Gate Court gates are built with
-- WorldStyle.BuildGate): the Battle Arena island, Portal_Ring + Portal_Arena in the plaza's Gate Court and the private
-- Champion Ring pockets in the sky, in the DETAILED VOXEL style (ARCHITECTURE_V3.md "Phase 3: Pet battles", "Phase 3 build contract"
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
--       ReturnCFrame = CFrame   on the plaza in front of Portal_Ring, looking at the plaza (ring climbers come back)
--       RingPortal   = BasePart (Phase 4) the Champion Ring portal's pad (Portal_Ring in the Gate Court, prompt
--                               "RingPrompt" with OpenPanel = "Ring"; ring starts are accepted near it). RingSite = the
--                               gate centre (LobbyInfo.GateSites.Ring, LookVector = towards the plaza)
--       ArenaPortal  = BasePart (Phase 5) Portal_Arena's prompt part (ArenaPortalPrompt -> Spawn)
--       LobbyCFrame  = CFrame   (Phase 5) in front of Portal_Arena, looking at the plaza (the forum's Return gate)
--       -- extras
--       Radius, Bounds = { CFrame, Size }   the island (InArena uses its real outline); Link = "Bridge" | "Portal"
--       EventBoard = { Model, Gui, Labels }, Leaderboard = { Model, Gui, Rows }   the SurfaceGuis (see ApplyArenaState)
--       ApplyArenaState = ArenaBuilder.ApplyArenaState, InArena = ArenaBuilder.InArena
--     }
--   ArenaBuilder.BuildPocket(index, kind) -> { Model, CFrame, Size, Spawn, Zone, Index, Kind } | nil
--       a private battle pocket (index 1..MAX_POCKETS), cloned from one template, far out in the sky on its own grid
--       cell; CFrame = floor surface centre (axis aligned), Size = the battle floor (BattleCatalog.Zones.Ring), Spawn =
--       where the fighter stands (side 1, -Z, looking at the enemy side). Phase 5: the only kind is "Ring" (nil and
--       unknown kinds build it too; the Trial pocket is deleted): the Champion Ring, a round ring (16-gon floor of
--       apothem 33: the 44 x 44 square fits at any rotation) with a gold rim, four crown posts and a small cheering crowd of cloud puffs on a cloud bleacher behind the champion's
--       side (<= 220 parts, zone Mode "Ring", ZoneId "Ring"). Building an index that exists returns it.
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
--     entrance arch ("BATTLE ARENA") and torches in the element colours. Phase 5: Portal_Arena in the Gate Court and the
--     Return gate on the forum link it too, always (the bridge stays when its corridor is clear).
--   * Island: a big puffy voxel cloud; the forum in front (paving, the avenue with a crimson runner, torches, a golden
--     trophy statue, banners, planters) and the COLOSSEUM behind: a 16-sided stadium whose sand floor (apothem 72)
--     holds the raid zone at any rotation, an element wheel in its centre, a podium wall, four tiers of seats in the
--     eight element colours, an outer wall with blind arches, element banners and crenellations, pillars with
--     braziers; the main gate (sign "BATTLE ARENA", an "Arena" prompt), two side gates and the boss gate at the back.
--   * Two DUEL RINGS on the forum (16-sided, apothem 33: the duel zone fits at any rotation) with a coloured curb,
--     torch posts, a crossed-swords emblem and two challenge pads each (prompt "Duel", attribute OpenPanel = "Arena").
--   * The EVENT BOARD and the TROPHY LEADERBOARD: free-standing stone frames flanking the avenue in front of the main
--     gate, SurfaceGuis at 50 px per stud (titles >= 1.1 studs, every line >= 0.6 stud).
--   * Battle zones: invisible parts tagged NC_BattleZone with the attributes Mode ("Raid" | "Duel" | "Ring"), Size
--     (Vector3, the battle floor: X, height, Z), ZoneId and Index; the part itself covers the floor plus a small margin
--     (where the controls work). CanCollide / CanTouch / CanQuery false: test membership with the part's CFrame + Size.
--   * The Gate Court gates (Phase 5, 6.1 / 6.2, C4 / C12): Portal_Ring and Portal_Arena are WorldStyle.BuildGate gates
--     at LobbyInfo.GateSites.Ring / .Arena, parented to LobbyInfo.GatesFolder (workspace.NimbusLobby.Gates; the arena
--     island's budget no longer holds them). Portal_Ring: gold, the crown glyph, a pad, two crowned pedestals, the
--     prompt "RingPrompt" (OpenPanel = "Ring") on the pad and the tag "Champion Ring" / "Beat the champion, meet a
--     stronger one" with the pill "Best in this server: Alex - Round 31" drawn from the RingBoard attribute
--     BattleService writes on the model (or its pad) when a run ends ("Alex|31;Sam|24;Kim|20"). Portal_Arena: red, the
--     swords glyph, two torches, "ArenaPortalPrompt" (Travel / Battle Arena) -> ArenaInfo.Spawn; the forum's Return
--     gate ("ArenaReturnPrompt") lands in front of it (ArenaInfo.LobbyCFrame). Each gate <= 120 parts.
--   * Safe zones (contract 3.11): battles start only inside NC_BattleZone parts (the raid floor, the duel rings, the
--     ring pockets); the plaza, the forum, the stands, the bridge and the gates have none.
--   * The home Arena Gate (HomeBuilder's ArenaGatePrompt) teleports its owner to ArenaInfo.Spawn: refused in a match
--     or a battle, only near the gate, rate limited; the Arena / Return gates use the same checks.
-- Look (Phase 6 A1: back to the Phase 4 look, 7aa0df2; the helper table `Art`): every world part SmoothPlastic (Neon
-- for glow, Glass / ForceField for water and shimmer), the P4 arena palette `C` (light cream stone colosseum walls,
-- white marble trims, golden sand floors, a lime lawn, cream paving, a crimson carpet, gold trim, seats and banners in
-- the full element colours), blocky voxel shapes only (square posts, no Cylinder / Ball), P4 white / light-blue voxel
-- clouds tagged NC_StyleExempt, warm lanterns (<= 1.5, range <= 16, no shadows), small parts cast no shadow, pure
-- decor tagged NC_Detail. Art.enforce is a safety net (the attribute ArtFixes counts what it had to fix: 0 when every
-- piece is built in the look). Budgets: the arena <= 2800 parts (10.3), a ring pocket <= 250. Portal_Ring /
-- Portal_Arena / Portal_Return are WorldStyle.BuildGate gates (the P4 hoop family, 6.0.3).
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
local WorldStyle = loadShared("WorldStyle") -- the Phase 5 art kit (Kerb, Chamfer, BuildGate, Tags)

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
local PART_BUDGET = 2800 -- the island and its bridge (Phase 5 10.3: arena <= 2800; its gates stand in the Gate Court)
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
local DEFAULT_ZONES = { Raid = { X = 96, Z = 96 }, Duel = { X = 44, Z = 44 }, Ring = { X = 44, Z = 44 } }
local MAX_ZONE = { Raid = 100, Duel = 45, Ring = 45 } -- the biggest square each floor can hold

-- Island layout (island-local studs; the colosseum centre is the origin, -Z points at the lobby)
local ISL = {
	FrontZ = -205, -- the forum's front edge (the bridge docks here)
	HalfW = 103, -- forum half width (Phase 5: = DiscR, so the forum's long sides run straight into the disc's side edges)
	BackZ = -20, -- the forum rectangle reaches into the colosseum disc up to here
	DiscR = 103, -- the colosseum disc: a 16-gon (apothem 103) around the stands, like the colosseum itself
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
-- Phase 6 A1 (back to the P4 look): the only materials a part may use
local P4_MATS = { [MAT.SmoothPlastic] = true, [MAT.Neon] = true, [MAT.Glass] = true, [MAT.ForceField] = true }

local function box(parent, name, cf, size, color, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	local mat = opts.Material or MAT.SmoothPlastic
	if not P4_MATS[mat] then
		mat = MAT.SmoothPlastic -- Phase 6 A1: SmoothPlastic look (Glass / Neon / ForceField stay)
	end
	p.Material = mat
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
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and not P4_MATS[p.Material] then
			p.Material = MAT.SmoothPlastic -- Phase 6 A1 (palette entries may still name a Phase 5 material)
		end
	end
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
-- Phase 5 (6.4 rule 9): the voxel clouds are shaded for the pink sky (tops 250,244,252; sides 226,214,240;
-- undersides 186,172,222) and tagged NC_StyleExempt (they keep their voxel look on purpose)
local CLOUD_PAL = { -- P4 white / light-blue clouds (style.md 4)
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
	gatePrompts = {}, -- the Arena / Return gates' prompts (Phase 5: Portal_Arena stands in the lobby's Gates folder)
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

-- the island outline: the forum rectangle (its two front corners rounded) joined to the 16-gon disc around the stands
local function islandSdf(x, z)
	local dPoly = polyR(x, z) - ISL.DiscR
	local hx, r, ax = ISL.HalfW, ISL.Corner, abs(x)
	local dRect
	if z < ISL.FrontZ + r and ax > hx - r then
		local dx, dz = ax - (hx - r), z - (ISL.FrontZ + r)
		dRect = sqrt(dx * dx + dz * dz) - r
	else
		dRect = max(ax - hx, ISL.FrontZ - z, z - ISL.BackZ)
	end
	return min(dPoly, dRect)
end

----------------------------------------------------------------------
-- Phase 5 art pass (arenaart; ARCHITECTURE_V3.md 6.4): real materials (WorldStyle.Materials: stone, brick, wood,
-- grass), muted big surfaces (saturation <= 0.45, value 0.35..0.9), saturated colour only on small pieces and thin
-- Neon inlays, plinth + body + cap, kerbs + lips on the platform edges, round (or chamfered) tall corners, 4..6-stud
-- tiles with a +-0.05 height alternation and +-6 RGB jitter, a detail every ~12 studs of walkway, warm lanterns
-- (Brightness <= 1.5, Range <= 16), small parts cast no shadow, voxel clouds shaded for the pink sky and tagged
-- NC_StyleExempt, pure decor tagged NC_Detail. ONE helper table: the main chunk stays under the 200-locals limit.
----------------------------------------------------------------------
local Art = {
	P = { -- the Phase 4 arena palette (7aa0df2 ArenaBuilder `C`): cream stone, white marble, sand, gold, crimson
		Lawn = C.Grass,
		LawnLight = C.GrassLight,
		LawnDark = C.GrassDark,
		Hedge = C.Hedge,
		HedgeLight = rgb(98, 172, 90),
		Slate = C.PavingDark,
		SlateLight = C.Paving,
		SlateDark = C.StoneEdge,
		Cobble = C.Paving,
		CobbleLight = C.PavingLight,
		CobbleDark = C.PavingWorn,
		Marble = C.Marble,
		MarbleShade = C.StoneLight,
		Brick = C.StoneLight, -- the colosseum walls: P4 light cream stone
		BrickDark = C.Stone,
		Stone = C.StoneLight, -- the stands' tiers
		StoneDark = C.Stone,
		Sand = C.Sand,
		SandDark = C.SandDark,
		SandLight = C.SandLight,
		Wood = rgb(132, 92, 62),
		Planks = rgb(196, 146, 98),
		Brass = C.Gold,
		Gold = C.Gold,
		Iron = C.Iron,
		Steel = C.Steel,
		Carpet = C.Crimson, -- the avenue's red carpet
		Soil = C.Soil,
		Cloth = C.Crimson, -- banners
	},
	Light = C.Lamp,
}
-- the material of each palette key: SmoothPlastic everywhere (Phase 6 A1; the keys stay for the art code)
Art.M = setmetatable({}, { __index = function()
	return MAT.SmoothPlastic
end })

-- Phase 6 A1: colours stay as bright as P4 (the Phase 5 muting is gone); the signature stays for the callers.
function Art.tone(c)
	return c
end

-- +-6 RGB per tile (6.4 rule 2), deterministic
function Art.jit(c, seed)
	local d = (floor(hash3(floor(seed or 0), 5, 11, 61) * 13) - 6) / 255
	return Color3.new(min(1, max(0, c.R + d)), min(1, max(0, c.G + d)), min(1, max(0, c.B + d)))
end

-- One anchored block in a palette key's colour + material (key may be a Color3 with opts.Material).
-- opts: Collide, Query, Material, Transparency, Shadow, Jitter (seed).
function Art.part(parent, name, cf, size, key, opts)
	opts = opts or {}
	local color = key
	if type(key) == "string" then
		color = Art.P[key] or C.Stone
	end
	if opts.Jitter then
		color = Art.jit(color, opts.Jitter)
	end
	local mat = opts.Material or MAT.SmoothPlastic
	return box(parent, name, cf, size, color, { Collide = opts.Collide, Query = opts.Query, Material = mat, Transparency = opts.Transparency, Shadow = opts.Shadow })
end

-- A column standing on `cf` (its foot): h tall, d wide. Phase 6 A1: a square voxel post (no Cylinder parts).
function Art.cyl(parent, name, cf, h, d, key, opts)
	return Art.part(parent, name, cf * CFrame.new(0, h / 2, 0), Vector3.new(d, h, d), key, opts)
end

function Art.tag(inst, which)
	local tags = WorldStyle and type(WorldStyle.Tags) == "table" and WorldStyle.Tags or {}
	local name = tags[which] or ((which == "Exempt") and "NC_StyleExempt" or "NC_Detail")
	if inst and not CollectionService:HasTag(inst, name) then
		CollectionService:AddTag(inst, name)
	end
	return inst
end

-- A kerb + lip on a platform edge (WorldStyle.Kerb: cf = a point on the top surface at the edge, X along it,
-- LookVector outward).
function Art.kerb(parent, cf, length)
	Art.part(parent, "Kerb", cf * CFrame.new(0, 0.2, 0), Vector3.new(length, 0.4, 0.8), "Brick", { Collide = true })
	Art.part(parent, "KerbLip", cf * CFrame.new(0, -0.25, -0.3), Vector3.new(length + 0.2, 0.3, 1), "SlateDark")
end

-- Ring tiles: 16 sectors of a 16-gon band (apothem r0 .. r1) per course, top at `top` (+0.05 on every other
-- tile: the overlapping wedge ends never z-fight), jittered. opts: Courses (default 1), Seed, Keys = { key per course }.
function Art.ring(parent, name, cf, r0, r1, top, h, key, opts)
	opts = opts or {}
	local courses = opts.Courses or 1
	local step = (r1 - r0) / courses
	for c = 1, courses do
		local a0, a1 = r0 + (c - 1) * step, r0 + c * step
		local len = 2 * a1 * TAN16 + 0.15
		local k = (opts.Keys and opts.Keys[c]) or key
		for j = 0, 15 do
			local lift = ((j + c) % 2 == 0) and 0.05 or 0
			Art.part(parent, name, cf * CFrame.Angles(0, j * STEP16, 0) * CFrame.new(0, top + lift - h / 2, -(a0 + a1) / 2), Vector3.new(len, h, a1 - a0), k, {
				Collide = true,
				Shadow = false,
				Jitter = (opts.Seed or 0) + j * 7 + c * 131,
			})
		end
	end
end

-- The outline as a polygon (island-local), walked with the outward normal on the left of the travel direction:
-- the front edge (left to right), the front-right arc, the right side, the 16-gon's back edges, the left side, the
-- front-left arc. Each vertex carries the kind of the edge that starts there ("Front", "Arc", "Side", "Back").
function Art.outline()
	if Art.pts then
		return Art.pts
	end
	local pts = {}
	local hw, fz, r = ISL.HalfW, ISL.FrontZ, ISL.Corner
	local function add(x, z, kind)
		pts[#pts + 1] = { x, z, kind }
	end
	add(-(hw - r), fz, "Front")
	for i = 0, 5 do
		local t = rad(i * 15)
		add((hw - r) + r * sin(t), (fz + r) - r * cos(t), "Arc")
	end
	add(hw, fz + r, "Side")
	local R = ISL.DiscR / math.cos(pi / 16)
	for m = 11.5, 5.5, -1 do
		local a = m * STEP16
		add(-sin(a) * R, -cos(a) * R, "Back")
	end
	add(-hw, ISL.DiscR * TAN16, "Side")
	for i = 0, 5 do
		local u = rad(i * 15)
		add(-(hw - r) - r * cos(u), (fz + r) - r * sin(u), "Arc")
	end
	Art.pts = pts
	return pts
end

-- every outline edge: { x0, z0, x1, z1, kind, length, dx, dz (unit along), ox, oz (unit outward) }
function Art.edges()
	local pts = Art.outline()
	local out = {}
	for i = 1, #pts do
		local p, q = pts[i], pts[i % #pts + 1]
		local dx, dz = q[1] - p[1], q[2] - p[2]
		local len = sqrt(dx * dx + dz * dz)
		if len > 0.01 then
			dx, dz = dx / len, dz / len
			out[#out + 1] = { p[1], p[2], q[1], q[2], p[3], len, dx, dz, dz, -dx }
		end
	end
	return out
end

-- A small round-crowned tree (Wood trunk, three LeafyGrass tiers turned 45 degrees): 6 parts, tagged NC_Detail.
function Art.tree(parent, cf, s, seed)
	local m = newModel(parent, "Tree")
	s = s or 1
	Art.part(m, "TreeBed", cf * CFrame.new(0, 0.15, 0), Vector3.new(4.4 * s, 0.5, 4.4 * s), "Soil", { Collide = true, Shadow = false })
	Art.cyl(m, "Trunk", cf, 6 * s, 1.1 * s, "Wood", { Collide = true })
	local turn = CFrame.Angles(0, rad(45 + (hash3(seed or 1, 2, 3, 9) - 0.5) * 30), 0)
	local leaf = { { 0, 6.6, 7.4, 3.4, "Hedge" }, { 0.3, 9.4, 5.6, 3, "HedgeLight" }, { -0.2, 11.7, 3.4, 2.2, "HedgeLight" } }
	for i, l in ipairs(leaf) do
		Art.part(m, "Leaves", cf * CFrame.new(l[1] * s, l[2] * s, 0) * turn * CFrame.Angles(0, rad(i * 20), 0), Vector3.new(l[3] * s, l[4] * s, l[3] * s), l[5], { Collide = i == 1 })
	end
	return Art.tag(m, "Detail")
end

-- A lantern post (Slate foot, Wood post, a warm Neon lamp under a little iron roof): 4 parts.
function Art.lantern(parent, cf, lit)
	local m = newModel(parent, "Lantern")
	Art.part(m, "LanternFoot", cf * CFrame.new(0, 0.3, 0), Vector3.new(1.4, 0.6, 1.4), "Slate", { Collide = true })
	Art.cyl(m, "LanternPost", cf * CFrame.new(0, 0.6, 0), 4.6, 0.5, "Wood", { Collide = true })
	local lamp = Art.part(m, "LanternLamp", cf * CFrame.new(0, 5.85, 0), Vector3.new(0.85, 0.95, 0.85), Art.Light, { Material = MAT.Neon })
	Art.part(m, "LanternRoof", cf * CFrame.new(0, 6.45, 0) * CFrame.Angles(0, rad(45), 0), Vector3.new(1.2, 0.3, 1.2), "Iron")
	if lit then
		pointLight(lamp, Art.Light, 1.2, 14)
	end
	return Art.tag(m, "Detail")
end

-- A low hedge box (Brick planter, a LeafyGrass hedge, three small flowers in the element colours): 5 parts.
function Art.hedgeBox(parent, cf, w, seed)
	local m = newModel(parent, "HedgeBox")
	w = w or 4
	Art.part(m, "PlanterBox", cf * CFrame.new(0, 0.55, 0), Vector3.new(w, 1.1, 2.4), "Brick", { Collide = true })
	Art.part(m, "PlanterCap", cf * CFrame.new(0, 1.18, 0), Vector3.new(w + 0.3, 0.16, 2.7), "Marble")
	Art.part(m, "Hedge", cf * CFrame.new(0, 1.9, 0), Vector3.new(w - 0.5, 1.4, 1.9), "Hedge", { Collide = true })
	for i = 1, 2 do
		local e = floor(hash3(seed or 1, i, 5, 3) * 8) + 1
		Art.part(m, "Flower", cf * CFrame.new((i - 1.5) * (w * 0.45), 2.7, -0.3), Vector3.new(0.6, 0.6, 0.6), elementColor(e):Lerp(rgb(255, 255, 255), 0.2), { Material = MAT.SmoothPlastic, Shadow = false })
	end
	return Art.tag(m, "Detail")
end

-- Rule 9 by height: the voxel LOD merges a big cloud into few colours, so its parts are re-shaded by where they sit
-- under `cf` (the walking surface): light tops, lavender sides, violet undersides (CLOUD_PAL). Tagged NC_StyleExempt.
function Art.shadeCloud(model, cf, depth)
	if not model then
		return nil
	end
	depth = depth or 24
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local y = cf:PointToObjectSpace(p.Position).Y + p.Size.Y * 0.25
			local t = -y / depth -- 0 at the top .. 1 at the bottom
			local key = (t < 0.22 and "CloudLight") or (t < 0.45 and "Cloud") or (t < 0.68 and "CloudShade") or (t < 0.9 and "Mist") or "MistDark"
			p.Color = CLOUD_PAL[key]
		end
	end
	return Art.tag(model, "Exempt")
end

-- The safety net of Phase 6 A1 over a built model (the voxel clouds / the crowd are exempt by tag): every part is
-- SmoothPlastic unless it is Neon / Glass / ForceField, every Part is a Block (no Ball / Cylinder), Reflectance 0;
-- parts < 4 studs cast no shadow. Returns how many parts it had to fix (0 when every piece follows the rules).
function Art.enforce(root)
	local fixed = 0
	local exemptTag = (WorldStyle and type(WorldStyle.Tags) == "table" and WorldStyle.Tags.Exempt) or "NC_StyleExempt"
	local function exempt(p)
		local cur = p
		while cur and cur ~= root.Parent do
			if CollectionService:HasTag(cur, exemptTag) then
				return true
			end
			cur = cur.Parent
		end
		return false
	end
	for _, p in ipairs(root:GetDescendants()) do
		if p:IsA("BasePart") then
			local s = p.Size
			if max(s.X, s.Y, s.Z) < 4 and p.CastShadow then
				p.CastShadow = false
			end
			if not exempt(p) then
				local bad = false
				if not P4_MATS[p.Material] then
					p.Material = MAT.SmoothPlastic
					bad = true
				end
				if p:IsA("Part") and p.Shape ~= Enum.PartType.Block then
					p.Shape = Enum.PartType.Block
					bad = true
				end
				if p.Reflectance ~= 0 and p.Material ~= MAT.Glass then
					p.Reflectance = 0
				end
				if bad then
					fixed = fixed + 1
				end
			end
		end
	end
	return fixed
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
		-- Phase 5: no rim puffs over the walking surface (the stone kerb is the edge now); the puffs bulge under it
		local s = rng:Float(12, 15)
		puffs[#puffs + 1] = { bx - dx * rng:Float(1, 3), rng:Float(-12.5, -10), bz - dz * rng:Float(1, 3), s, s * rng:Float(0.55, 0.7), s }
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
			{ Inset = 2, H = 1 }, -- 2 studs inside the outline: the stone edge overhangs the cloud like a cornice
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
	return Art.shadeCloud(VX.Build(g, { V = 4, Pal = CLOUD_PAL, Name = "IslandCloud", CF = A * CFrame.new(0, -1.2 - 2, 0), Collide = true, MaxParts = 340, Parent = parent }), A, 30)
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
-- Forum ground (Phase 5 art pass, 6.4 rules 3 + 5): a mown lawn (Grass rows in two shades, top -0.2) inside a
-- Cobblestone promenade along the island's edge with a Brick kerb + Slate lip; a Cobblestone apron round the
-- colosseum and round each duel ring; the avenue of Slate tiles (5 x ~5, +-0.05 alternation, jittered) between Marble
-- borders from the bridge to the main gate, its crimson Fabric runner, a Marble compass star where the bridge lands
-- and the round trophy plaza with element tiles. Tile tops -0.15 / -0.10, runner -0.04.
----------------------------------------------------------------------
local function buildGround(parent, A)
	local f = newModel(parent, "Forum")
	local TOP_T = -0.15 -- tile tops (+0.05 on every other tile)
	local TH = 1.1 -- tile thickness (down onto the cloud's top at -1.2)
	-- the lawn: 4-stud rows (mown stripes), ends tucked under the promenade and the colosseum's apron
	local lawn = newModel(f, "Lawn")
	local row = 0
	for z0 = ISL.FrontZ, ISL.BackZ, 4 do
		row = row + 1
		local z1 = min(z0 + 4, ISL.BackZ + 4)
		local x0 = nil
		for x = -ISL.HalfW, ISL.HalfW + 1 do
			local ok = x <= ISL.HalfW and islandSdf(x, z0) <= -3 and islandSdf(x, z1) <= -3 and polyR(x, z0) > 101 and polyR(x, z1) > 101
			if ok and not x0 then
				x0 = x
			elseif not ok and x0 then
				local w = (x - 1) - x0 + 1
				Art.part(lawn, "Lawn", A * CFrame.new((x0 + x - 1) / 2, -0.2 - 0.5, (z0 + z1) / 2), Vector3.new(w, 1, z1 - z0), (row % 2 == 0) and "LawnLight" or "Lawn", { Collide = true, Shadow = false, Jitter = row * 13 + x0 })
				x0 = nil
			end
		end
	end
	-- the promenade (5 wide, Cobblestone tiles ~6 long) and the kerb on every edge (open where the bridge lands)
	local prom = newModel(f, "Promenade")
	local kerbs = newModel(f, "Kerbs")
	for ei, e in ipairs(Art.edges()) do
		local x0, z0, len, dx, dz, ox, oz = e[1], e[2], e[6], e[7], e[8], e[9], e[10]
		local look = Vector3.new(ox, 0, oz)
		if e[5] ~= "Back" then
			local n = max(1, floor(len / 6 + 0.5))
			local tl = len / n
			for i = 1, n do
				local along = (i - 0.5) * tl
				local cx, cz = x0 + dx * along - ox * 2.5, z0 + dz * along - oz * 2.5
				if polyR(cx, cz) > 101 then
					local lift = ((i + ei) % 2 == 0) and 0.05 or 0
					local pos = Vector3.new(cx, TOP_T + lift - TH / 2, cz)
					Art.part(prom, "Promenade", A * CFrame.lookAt(pos, pos + look), Vector3.new(tl + ((e[5] == "Arc") and 0.8 or 0), TH, 5), ((i + ei) % 3 == 0) and "CobbleLight" or "Cobble", { Collide = true, Shadow = false, Jitter = ei * 97 + i })
				end
			end
		end
		local spans = { { 0, len } }
		if e[5] == "Front" then
			-- the bridge's landing: no kerb across the deck (x within +-(BRIDGE_W / 2 + 1))
			local gap = BRIDGE_W / 2 + 1
			spans = { { 0, (-gap) - x0 }, { gap - x0, len } }
		end
		for _, sp in ipairs(spans) do
			local l = sp[2] - sp[1]
			if l > 0.5 then
				local mid = (sp[1] + sp[2]) / 2
				local pos = Vector3.new(x0 + dx * mid, TOP_T, z0 + dz * mid)
				Art.kerb(kerbs, A * CFrame.lookAt(pos, pos + look), l)
			end
		end
	end
	-- the colosseum's apron (two courses round the stands, under the wall and the columns)
	Art.ring(f, "Apron", A, COL.WallIn - 1, ISL.DiscR, TOP_T + 0.01, TH, "Cobble", { Courses = 2, Keys = { "CobbleDark", "Cobble" }, Seed = 401 })
	-- the duel rings' aprons
	for i, spec in ipairs(RINGS) do
		Art.ring(f, "RingApron", A * CFrame.new(spec.X, 0, spec.Z), RING_A + 1.2, RING_A + 9.2, TOP_T, TH, "Cobble", { Seed = 503 + i * 50 })
	end
	-- the avenue: 4 columns of Slate tiles between Marble borders, the trophy plaza in its middle
	local av = newModel(f, "Avenue")
	local zA, zB = ISL.FrontZ + 5, -ISL.DiscR
	local rows = floor((zB - zA) / 5 + 0.5)
	local rl = (zB - zA) / rows
	local plazaZ, plazaR = -124, 17
	for k = 1, rows do
		local zc = zA + (k - 0.5) * rl
		if abs(zc - plazaZ) > plazaR - 4 then
			for c = 1, 4 do
				local lift = ((k + c) % 2 == 0) and 0.05 or 0
				Art.part(av, "AvenueTile", A * CFrame.new(-7.5 + (c - 1) * 5, TOP_T + lift - TH / 2, zc), Vector3.new(5, TH, rl), ((k + c) % 2 == 0) and "SlateLight" or "Slate", { Collide = true, Shadow = false, Jitter = k * 11 + c })
			end
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, seg in ipairs({ { zA, plazaZ - plazaR + 1 }, { plazaZ + plazaR - 1, zB } }) do
			Art.part(av, "AvenueBorder", A * CFrame.new(sx * 10.6, -0.02 - TH / 2, (seg[1] + seg[2]) / 2), Vector3.new(1.2, TH, seg[2] - seg[1]), "Marble", { Collide = true, Shadow = false })
		end
	end
	-- the runner: from the bridge's landing to the trophy plaza, and on from it to the main gate's passage
	for _, seg in ipairs({ { ISL.FrontZ + 1, plazaZ - plazaR + 0.5 }, { plazaZ + plazaR - 0.5, -(COL.WallOut + 1.5) } }) do
		Art.part(av, "Runner", A * CFrame.new(0, -0.04 - 0.2, (seg[1] + seg[2]) / 2), Vector3.new(4, 0.4, seg[2] - seg[1]), "Carpet", { Collide = true, Shadow = false })
	end
	-- a Marble compass star with a brass heart where the bridge lands
	local star = A * CFrame.new(0, 0, ISL.FrontZ + 22)
	for i, turn in ipairs({ 0, 45 }) do
		Art.part(av, "ArrivalStar", star * CFrame.new(0, 0.02 * i - 0.15, 0) * CFrame.Angles(0, rad(turn), 0), Vector3.new(8, 0.3, 8), (i == 1) and "Marble" or "MarbleShade", { Collide = true, Shadow = false })
	end
	Art.part(av, "ArrivalHeart", star * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, rad(45), 0), Vector3.new(3, 0.3, 3), "Brass", { Collide = true, Shadow = false })
	-- the trophy plaza: a round Slate court with a Cobblestone ring, element tiles round the statue's plinth
	local plaza = A * CFrame.new(0, 0, plazaZ)
	Art.ring(av, "PlazaTile", plaza, 0, 10, TOP_T + 0.06, TH, "SlateLight", { Seed = 611 })
	Art.ring(av, "PlazaRing", plaza, 10, plazaR, TOP_T + 0.03, TH, "Cobble", { Seed = 677 })
	for e = 1, 8 do
		local turn = plaza * CFrame.Angles(0, sectionAngle(e), 0)
		Art.part(av, "TrophyTile", turn * CFrame.new(0, -0.02, -7.6) * CFrame.Angles(0, rad(45), 0), Vector3.new(2, 0.3, 2), elementColor(e), { Material = MAT.Slate, Collide = true, Shadow = false })
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
	fillA(g, COL.FloorR, COL.PodiumR, 5, 6, hwOut(COL.PodiumR), "Cap", function(ix, iy)
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
	-- Phase 5: a Marble coping course caps the wall (6.4 rule 3), the merlons stand on it
	fillA(g, COL.WallIn, COL.WallOut, COL.WallH, COL.WallH + 1, hwW, "Cornice")
	fillA(g, COL.WallIn, COL.WallOut, COL.WallH + 1, COL.WallH + 3, hwW, "Wall", function(ix)
		return floor((ix + hwW) / 4) % 2 == 0
	end)
	if gate then
		-- a gatehouse: the wall rises over the passage (the main gate's sign hangs on it), crowned by its own merlons
		local gw = gh + 5
		fillA(g, COL.WallIn, COL.WallOut, COL.WallH, COL.WallH + 6, gw, "Wall")
		fillA(g, COL.WallIn, COL.WallOut, COL.WallH + 6, COL.WallH + 7, gw, "Cornice")
		fillA(g, COL.WallIn, COL.WallOut, COL.WallH + 7, COL.WallH + 9, gw, "Wall", function(ix)
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
		-- a Marble string course over the arches (the banner hangs in front of it)
		for ix = -16, 16 do
			if abs(ix) > 2 then
				setA(g, ix, 13, fa, "Cornice")
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

-- Phase 5 (6.4): Brick walls on a Slate plinth with Marble pilasters, string course and cornice; warm limestone
-- tiers with Fabric seat cushions in the muted element colours; a Marble podium; brass trim; iron portcullises.
local SEG_PAL = { -- the Phase 4 colosseum palette (7aa0df2), SmoothPlastic (Cap kept for the P5 coping)
	Podium = C.Stone,
	Cap = C.Marble,
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
	Passage = C.Stone,
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

-- A column between two segments (Phase 5: a round Marble column on a Slate plinth with a Marble band, a capital,
-- a brass abacus and an iron brazier with an element flame), segment-local: outward = -Z, on the apothem 94.
local pillarTemplate = nil
local function pillar()
	if pillarTemplate then
		return pillarTemplate
	end
	local m = newModel(nil, "Pillar")
	local at = CFrame.new(0, 0, -(COL.WallOut + 2))
	Art.part(m, "PillarBase", at * CFrame.new(0, 0, 0), Vector3.new(4.4, 2.2, 4.4), "Slate", { Collide = true })
	Art.cyl(m, "Pillar", at * CFrame.new(0, 1.4, 0), 19.8, 2.8, "Marble", { Collide = true })
	Art.part(m, "Capital", at * CFrame.new(0, 21.7, 0), Vector3.new(3.8, 1, 3.8), "Marble", { Collide = true })
	Art.part(m, "Abacus", at * CFrame.new(0, 22.4, 0), Vector3.new(4.3, 0.4, 4.3), "Brass", { Collide = true })
	Art.part(m, "Brazier", at * CFrame.new(0, 23.0, 0), Vector3.new(2.6, 0.8, 2.6), "Iron")
	local flame = Art.part(m, "Flame", at * CFrame.new(0, 24.0, 0) * CFrame.Angles(0, rad(45), 0), Vector3.new(1.3, 1.4, 1.3), C.Gold, { Material = MAT.Neon, Shadow = false })
	flame.CanCollide = false
	flame.CanQuery = false
	pillarTemplate = m
	return m
end

-- 16-sided shapes from boxes turned k x 22.5 degrees (the colosseum's faces, the rings, the wheel). Boxes of one colour
-- may overlap: their coplanar faces are identical, so nothing flickers. Edge j's normal is the segments' (NORMALS16).
local function disc16(parent, name, cf, apothem, topY, h, color, material, collide)
	local w = 2 * apothem * TAN16 + 0.2
	for j = 0, 7 do
		-- (each slab 0.004 higher than the last: textured materials never z-fight where the slabs overlap)
		box(parent, name, cf * CFrame.Angles(0, j * STEP16, 0) * CFrame.new(0, topY + j * 0.004 - h / 2, 0), Vector3.new(w, h, apothem * 2), color, { Collide = collide, Material = material, Shadow = false })
	end
end
local function ring16(parent, name, cf, r0, r1, topY, h, color, material, collide)
	local len = 2 * r1 * TAN16 + 0.15
	for j = 0, 15 do
		box(parent, name, cf * CFrame.Angles(0, j * STEP16, 0) * CFrame.new(0, topY + (j % 2) * 0.01 - h / 2, -(r0 + r1) / 2), Vector3.new(len, h, r1 - r0), color, { Collide = collide, Material = material, Shadow = false })
	end
end

-- The arena floor (apothem 72; the sand reaches under the podium wall): sand, a stone band and a gold line along the
-- wall, a pale ring at 40 studs, an element diamond per section, and the element wheel in the middle (8 petals in the
-- element colours between gold rays, a gold core and rim). Sand top -0.1, everything else on top at 0 / +0.1.
local function buildFloor(parent, A)
	local m = newModel(parent, "ArenaFloor")
	local P = Art.P
	disc16(m, "Sand", A, COL.FloorR + 1, -0.1, 1, P.Sand, MAT.Sand, true)
	ring16(m, "FloorBand", A, COL.FloorR - 8, COL.FloorR + 1, 0, 1, P.SlateLight, MAT.Slate, true)
	ring16(m, "FloorGold", A, COL.FloorR - 9.6, COL.FloorR - 8, 0.02, 1, P.Brass, MAT.Metal, true)
	ring16(m, "FloorLine", A, 40, 41.6, 0, 1, P.MarbleShade, MAT.Marble, true)
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
	flatPatches(m, "SandDrift", cells, 4, A, -0.04, 0.2, { SandDark = P.SandDark, SandLight = P.SandLight }, MAT.Sand)
	for e = 1, 8 do
		local turn = A * CFrame.Angles(0, sectionAngle(e), 0)
		box(m, "ElementFrame", turn * CFrame.new(0, -0.52, -54) * CFrame.Angles(0, rad(45), 0), Vector3.new(6.6, 1, 6.6), P.Brass, { Collide = true, Material = MAT.Metal, Shadow = false })
		box(m, "ElementMark", turn * CFrame.new(0, -0.45, -54) * CFrame.Angles(0, rad(45), 0), Vector3.new(5, 1, 5), Art.tone(elementColor(e), 0.44, 0.5, 0.82), { Collide = true, Material = MAT.Slate, Shadow = false })
		box(m, "ElementGem", turn * CFrame.new(0, 0.1, -54) * CFrame.Angles(0, rad(45), 0), Vector3.new(1.6, 0.2, 1.6), elementColor(e), { Material = MAT.Neon, Shadow = false })
		box(m, "WheelPetal", turn * CFrame.new(0, -0.5, -10), Vector3.new(4, 1, 7), Art.tone(elementColor(e), 0.44, 0.5, 0.82), { Collide = true, Material = MAT.Slate, Shadow = false })
		box(m, "WheelRay", A * CFrame.Angles(0, sectionAngle(e) + STEP16, 0) * CFrame.new(0, -0.5, -9.75), Vector3.new(0.7, 1, 8.5), P.Brass, { Collide = true, Material = MAT.Metal, Shadow = false })
	end
	ring16(m, "WheelRim", A, 14, 15.2, 0, 1, P.Brass, MAT.Metal, true)
	disc16(m, "WheelCore", A, 5.5, 0.1, 1, P.Brass, MAT.Metal, true)
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
		recolor(seg, "Seat", Art.tone(elementColor(e), 0.42, 0.5, 0.84))
		recolor(seg, "Banner", Art.tone(elementColor(e), 0.44, 0.45, 0.78))
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
				pointLight(flame, Art.Light, 1.2, 16)
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
	Art.part(m, "PostBase", CFrame.new(0, 0.5, 0), Vector3.new(2.2, 1, 2.2), "Slate", { Collide = true, Shadow = false })
	Art.cyl(m, "Post", CFrame.new(0, 1, 0), 3.6, 1.3, "Marble", { Collide = true, Shadow = false })
	Art.part(m, "PostCap", CFrame.new(0, 4.85, 0), Vector3.new(1.9, 0.5, 1.9), "Brass", { Shadow = false })
	Art.part(m, "Flame", CFrame.new(0, 5.6, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.9, 1.1, 0.9), C.Gold, { Material = MAT.Neon, Shadow = false })
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
	local m = VX.Build(g, { V = 1, Pal = { Accent = { Color = accent, Material = MAT.Slate }, Blade = { Color = Art.P.Steel, Material = MAT.Metal }, Guard = { Color = Art.P.Gold, Material = MAT.Metal } }, Name = "Emblem", CF = CFrame.new(0, -0.5, 0), Collide = false, Shadow = false, MaxParts = 30 })
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
		box(m, "RingFloor", cf * CFrame.Angles(0, j * STEP16, 0) * CFrame.new(0, RING_Y + j * 0.004 - 0.5, 0), Vector3.new(slabW, 1, RING_A * 2), Art.P.SandLight, { Collide = true, Material = MAT.Sand, Shadow = false })
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
	flatPatches(m, "RingDrift", cells, 3, cf, RING_Y + 0.04, 0.12, { SandDark = Art.P.Sand, SandPale = Art.P.SandDark }, MAT.Sand)
	-- a painted circle (16 thin strips) where the two teams line up, and a darker sand rim inside the curb
	local lineA = 21
	local lineLen = 2 * lineA * TAN16 + 0.5
	for j = 0, 15 do
		local seg = cf * CFrame.Angles(0, j * STEP16, 0)
		box(m, "RingLine", seg * CFrame.new(0, RING_Y + 0.03 + (j % 2) * 0.01, -lineA), Vector3.new(lineLen, 0.1, 0.8), Art.P.Marble, { Material = MAT.Marble, Shadow = false })
		box(m, "RingRim", seg * CFrame.new(0, RING_Y + 0.02 + (j % 2) * 0.005, -(RING_A - 1.5)), Vector3.new(2 * (RING_A - 1.5) * TAN16 + 1.3, 0.08, 3), Art.P.SandDark, { Material = MAT.Sand, Shadow = false })
	end
	-- the curb: 16 stone blocks on the edges in the ring's (muted) colour under a Marble coping with a thin Neon
	-- inlay in the ring's colour (6.4 rule 2: saturated colour only as a thin inlay)
	local curbOut = RING_A + 1.6
	local curbLen = 2 * curbOut * TAN16 + 0.25
	local curbColor = Art.tone(accent, 0.4, 0.45, 0.66)
	for j = 0, 15 do
		local seg = cf * CFrame.Angles(0, j * STEP16, 0)
		local lift = (j % 2) * 0.01
		box(m, "Curb", seg * CFrame.new(0, RING_Y + 0.3 - 0.55 + lift, -(RING_A + 0.3)), Vector3.new(curbLen, 1.7, 2.6), curbColor, { Collide = true, Material = MAT.Slate, Shadow = false })
		box(m, "CurbCoping", seg * CFrame.new(0, RING_Y + 0.3 + 0.38 + lift, -(RING_A + 0.3)), Vector3.new(curbLen + 0.1, 0.36, 3), Art.P.Marble, { Collide = true, Material = MAT.Marble, Shadow = false })
		box(m, "CurbInlay", seg * CFrame.new(0, RING_Y + 0.3 + 0.58 + lift, -(RING_A + 0.3)), Vector3.new(curbLen - 0.6, 0.06, 0.4), accent, { Material = MAT.Neon, Shadow = false })
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
				pointLight(flame, Art.Light, 1.1, 14)
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
		local base = box(m, "ChallengePad", pcf * CFrame.new(0, 0.1, 0), Vector3.new(5.4, 0.4, 5.4), Art.P.Brass, { Collide = true, Material = MAT.Metal, Shadow = false })
		box(m, "PadGlow", pcf * CFrame.new(0, 0.33, 0), Vector3.new(4.2, 0.2, 4.2), accent, { Material = MAT.Neon, Shadow = false })
		box(m, "PadMark", pcf * CFrame.new(0, 0.47, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(3.6, 0.12, 0.6), Art.P.Gold, { Material = MAT.Metal, Shadow = false })
		box(m, "PadMark", pcf * CFrame.new(0, 0.48, 0) * CFrame.Angles(0, math.rad(-45), 0), Vector3.new(3.6, 0.12, 0.6), Art.P.Gold, { Material = MAT.Metal, Shadow = false })
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
	local base = 2.2 -- panel bottom over the ground
	-- Phase 5: a Slate step + plinths, round Marble columns with brass caps and torches, a Marble lintel with a brass
	-- trim, a Slate back; the crest (a crimson shield with crossed swords) on top
	Art.part(m, "Step", cf * CFrame.new(0, 0.3, 0.6), Vector3.new(w + 4, 0.6, 4.2), "Slate", { Collide = true })
	for _, sx in ipairs({ -1, 1 }) do
		local foot = cf * CFrame.new(sx * (w / 2 + 0.9), 0.6, 0.6)
		Art.part(m, "PostPlinth", foot * CFrame.new(0, 0.6, 0), Vector3.new(2.2, 1.2, 2.4), "SlateDark", { Collide = true, Shadow = false })
		Art.cyl(m, "Post", foot * CFrame.new(0, 1.2, 0), base + h - 1.2, 1.6, "Marble", { Collide = true })
		Art.part(m, "PostCap", cf * CFrame.new(sx * (w / 2 + 0.9), base + h + 1.85, 0.6), Vector3.new(2.2, 0.5, 2.4), "Brass", { Shadow = false })
		Art.part(m, "Flame", cf * CFrame.new(sx * (w / 2 + 0.9), base + h + 2.6, 0.6) * CFrame.Angles(0, rad(45), 0), Vector3.new(0.9, 1, 0.9), C.Gold, { Material = MAT.Neon, Shadow = false })
	end
	Art.part(m, "Lintel", cf * CFrame.new(0, base + h + 0.9, 0.6), Vector3.new(w + 2.6, 1.4, 2), "Marble", { Collide = true })
	Art.part(m, "LintelTrim", cf * CFrame.new(0, base + h + 0.2, -0.45), Vector3.new(w + 1.6, 0.3, 0.2), "Brass", { Shadow = false })
	Art.part(m, "Back", cf * CFrame.new(0, base + h / 2, 0.85), Vector3.new(w + 0.4, h + 0.4, 0.8), "Slate", { Collide = true })
	local panel = Art.part(m, "Panel", cf * CFrame.new(0, base + h / 2, 0.25), Vector3.new(w, h, 0.4), "SlateDark", { Collide = true, Shadow = false })
	-- crest: a crimson shield in a brass rim with crossed swords on the lintel
	Art.part(m, "Crest", cf * CFrame.new(0, base + h + 2.4, 0.3), Vector3.new(2.6, 2.2, 0.6), C.Crimson, { Material = MAT.Fabric, Shadow = false })
	Art.part(m, "CrestRim", cf * CFrame.new(0, base + h + 2.4, 0.5), Vector3.new(3.1, 2.7, 0.4), "Brass", { Shadow = false })
	for _, sgn in ipairs({ -1, 1 }) do
		Art.part(m, "Sword", cf * CFrame.new(0, base + h + 2.6, -0.1) * CFrame.Angles(0, 0, rad(sgn * 40)), Vector3.new(0.35, 3.6, 0.2), "Steel", { Shadow = false })
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
	Art.part(m, "TorchBase", CFrame.new(0, 0.4, 0), Vector3.new(1.8, 0.8, 1.8), "Slate", { Collide = true, Shadow = false })
	Art.cyl(m, "TorchPole", CFrame.new(0, 0.7, 0), 4.4, 0.6, "Iron", { Collide = true, Shadow = false })
	Art.part(m, "TorchBowl", CFrame.new(0, 5.3, 0), Vector3.new(1.6, 0.5, 1.6), "Brass", { Shadow = false })
	Art.part(m, "Flame", CFrame.new(0, 6.05, 0) * CFrame.Angles(0, rad(45), 0), Vector3.new(0.9, 1.1, 0.9), C.Gold, { Material = MAT.Neon, Shadow = false })
	torchTemplate = m
	return m
end

local function buildTrophy(parent, cf)
	local m = newModel(parent, "TrophyStatue")
	Art.part(m, "Plinth", cf * CFrame.new(0, 1.25, 0), Vector3.new(7, 2.5, 7), "Marble", { Collide = true })
	Art.part(m, "PlinthTrim", cf * CFrame.new(0, 2.6, 0), Vector3.new(7.6, 0.4, 7.6), "Brass", { Collide = true, Shadow = false })
	Art.part(m, "PlinthBase", cf * CFrame.new(0, 0.25, 0), Vector3.new(8.4, 0.5, 8.4), "Slate", { Collide = true, Shadow = false })
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
		Pal = {
			Base = { Color = Art.P.SlateDark, Material = MAT.Slate },
			Gold = { Color = Art.P.Gold, Material = MAT.Metal },
			Rim = { Color = rgb(250, 218, 130), Material = MAT.Metal },
			Gem = { Color = C.Crimson, Material = MAT.Neon },
		},
		Name = "Trophy",
		CF = cf * CFrame.new(0, 2.8, 0),
		Collide = false,
		MaxParts = 36,
	})
	if cup then
		cup.Parent = m
	end
	local star = Art.part(m, "TrophyStar", cf * CFrame.new(0, 2.8 + 8.8, 0) * CFrame.Angles(0, 0, rad(45)), Vector3.new(1.4, 1.4, 0.5), C.Gold, { Material = MAT.Neon, Shadow = false })
	emitter(star, { Rate = 3, Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(0.5, 1.2), SpreadAngle = Vector2.new(180, 180) })
	return m
end

local function bannerPole(parent, cf, color)
	local m = newModel(parent, "BannerPole")
	Art.part(m, "PoleBase", cf * CFrame.new(0, 0.5, 0), Vector3.new(1.6, 1, 1.6), "Slate", { Collide = true, Shadow = false })
	Art.cyl(m, "Pole", cf * CFrame.new(0, 0.5, 0), 13, 0.6, "Wood", { Collide = true })
	Art.part(m, "PoleTop", cf * CFrame.new(0, 13.8, 0), Vector3.new(1, 1, 1), "Gold", { Shadow = false })
	Art.part(m, "CrossBar", cf * CFrame.new(1.9, 12.6, 0), Vector3.new(4.2, 0.35, 0.35), "Iron", { Shadow = false })
	Art.part(m, "Banner", cf * CFrame.new(1.9, 9.6, 0), Vector3.new(3.4, 5.6, 0.2), Art.tone(color, 0.44, 0.45, 0.8), { Material = MAT.Fabric, Shadow = false })
	Art.part(m, "BannerTrim", cf * CFrame.new(1.9, 12.25, 0), Vector3.new(3.6, 0.4, 0.26), "Brass", { Shadow = false })
	Art.part(m, "BannerMark", cf * CFrame.new(1.9, 9.9, -0.05) * CFrame.Angles(0, 0, rad(45)), Vector3.new(1.3, 1.3, 0.22), "Gold", { Shadow = false })
	Art.tag(m, "Detail")
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
	local pal = {
		Curb = { Color = Art.P.Brick, Material = MAT.Brick },
		CurbTop = { Color = Art.P.Marble, Material = MAT.Marble },
		Soil = { Color = Art.P.Soil, Material = MAT.Sand },
		Grass = { Color = Art.P.Lawn, Material = MAT.Grass },
		Hedge = { Color = Art.P.Hedge, Material = MAT.LeafyGrass },
	}
	for e = 1, 8 do
		pal["Fl" .. e] = elementColor(e):Lerp(rgb(255, 255, 255), 0.15)
	end
	planterTemplate = VX.Build(g, { V = 1, Pal = pal, Name = "Planter", CF = CFrame.new(0, 0.5 - 0.2, 0), Collide = true, MaxParts = 22 })
	return planterTemplate
end

local function buildForumDecor(parent, A)
	local m = newModel(parent, "ForumDecor")
	-- torches along the avenue, in the element colours, and between them hedge boxes (a detail every ~11 studs)
	local t = 0
	for _, z in ipairs({ -186, -164, -142 }) do
		for _, sx in ipairs({ -1, 1 }) do
			t = t + 1
			local tm = place(torch(), A * CFrame.new(sx * 12.6, -0.2, z), m, "AvenueTorch")
			recolor(tm, "Flame", flameColor(elementColor(t)))
			Art.tag(tm, "Detail")
			local flame = tm:FindFirstChild("Flame")
			if flame and z == -164 then
				pointLight(flame, Art.Light, 1.2, 16)
			end
		end
	end
	for i, z in ipairs({ -175, -153 }) do
		for _, sx in ipairs({ -1, 1 }) do
			Art.hedgeBox(m, A * CFrame.new(sx * 13, -0.2, z) * CFrame.Angles(0, pi / 2, 0), 5, i * 7 + sx)
		end
	end
	-- banner poles at the arrival
	bannerPole(m, A * CFrame.new(-18, -0.2, ISL.FrontZ + 10) * CFrame.Angles(0, pi, 0), C.Crimson)
	bannerPole(m, A * CFrame.new(18, -0.2, ISL.FrontZ + 10), C.Crimson)
	-- planters between the rings and the colosseum
	for _, p in ipairs({ { -60, -102, 0 }, { 60, -102, 0 } }) do
		Art.tag(place(planter(), A * CFrame.new(p[1], 0, p[2]) * CFrame.Angles(0, p[3], 0), m, "Planter"), "Detail")
	end
	-- trees on the lawns (the front corners, beside the stands) and lanterns along the promenade (every ~24 studs,
	-- alternating sides of a bench-free walk: a detail every ~12 studs along each side)
	local trees = { { -84, -100, 1.1 }, { 84, -100, 1.0 }, { -92, -66, 0.95 }, { 92, -66, 1.05 }, { -84, -190, 0.85 }, { 84, -190, 0.9 } }
	for i, tr in ipairs(trees) do
		Art.tree(m, A * CFrame.new(tr[1], -0.2, tr[2]), tr[3], i)
	end
	local lit = 0
	for _, sx in ipairs({ -1, 1 }) do
		for i, z in ipairs({ -168, -144, -120, -84, -48 }) do
			lit = lit + 1
			Art.lantern(m, A * CFrame.new(sx * (ISL.HalfW - 4.6), -0.15, z), i % 2 == 1)
		end
	end
	for _, x in ipairs({ -66, -40, 40, 66 }) do
		Art.lantern(m, A * CFrame.new(x, -0.15, ISL.FrontZ + 4.6), abs(x) == 40)
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
	local part = Art.part(parent, "GateSign", cf, Vector3.new(w, h, 0.6), "SlateDark", { Collide = true, Shadow = false })
	local frame = Art.part(parent, "GateSignFrame", cf * CFrame.new(0, 0, 0.35), Vector3.new(w + 0.8, h + 0.8, 0.4), "Brass", { Collide = true, Shadow = false })
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
	-- Phase 5 (6.4): a stone bridge: Cobblestone deck slabs (~7.5 long, +-0.05 alternation, jittered) between Slate edge
	-- beams, the crimson Fabric runner, Brick parapets with Marble copings between Slate piers (one every ~15 studs:
	-- the walkway's detail rhythm with the deck joints), a torch on every fourth pier
	local slabs = max(4, floor(len / 7.5 + 0.5))
	local sl = len / slabs
	for i = 1, slabs do
		local z = startZ + (i - 0.5) * sl
		Art.part(m, "Deck", A * CFrame.new(0, -0.3 - 0.5 + (i % 2) * 0.05, z), Vector3.new(BRIDGE_W - 1.6, 1, sl), (i % 3 == 0) and "CobbleLight" or "Cobble", { Collide = true, Shadow = false, Jitter = i * 17 })
	end
	for _, sx in ipairs({ -1, 1 }) do
		Art.part(m, "DeckEdge", A * CFrame.new(sx * (hw - 0.4), -0.3 - 0.6, mid), Vector3.new(0.8, 1.2, len), "Slate", { Collide = true, Shadow = false })
	end
	Art.part(m, "Runner", A * CFrame.new(0, -0.3 + 0.12, mid), Vector3.new(3.6, 0.1, len - 1), "Carpet", { Collide = true, Shadow = false })
	Art.part(m, "Underside", A * CFrame.new(0, -1.8, mid), Vector3.new(BRIDGE_W - 2, 1, len), "SlateDark", { Shadow = false })
	-- piers every ~11 studs (gaps at both ends: the street and the forum), parapets between them
	local posts = {}
	local p0, p1 = startZ + 6, endZ - 4
	local nPosts = max(2, floor((p1 - p0) / 15 + 0.5) + 1)
	for i = 0, nPosts - 1 do
		posts[#posts + 1] = p0 + (p1 - p0) * i / (nPosts - 1)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for i = 1, #posts - 1 do
			local a, b = posts[i] + 0.8, posts[i + 1] - 0.8
			if b > a then
				Art.part(m, "Parapet", A * CFrame.new(sx * (hw - 0.4), 0.4, (a + b) / 2), Vector3.new(0.8, 1.4, b - a), "Brick", { Collide = true })
				Art.part(m, "ParapetCap", A * CFrame.new(sx * (hw - 0.4), 1.25, (a + b) / 2), Vector3.new(1.1, 0.3, b - a + 0.2), "Marble", { Collide = true, Shadow = false })
			end
		end
		for i, z in ipairs(posts) do
			if i % 4 == 1 then
				local tm = place(torch(), A * CFrame.new(sx * (hw - 0.4), -0.3, z), m, "BridgeTorch")
				local e = (i + (sx > 0 and 4 or 0)) % 8 + 1
				recolor(tm, "Flame", flameColor(elementColor(e)))
				local flame = tm:FindFirstChild("Flame")
				if flame and i % 2 == 1 and sx < 0 then
					pointLight(flame, Art.Light, 1.2, 16)
				end
			else
				Art.part(m, "Pier", A * CFrame.new(sx * (hw - 0.4), 0.65, z), Vector3.new(1.5, 2.1, 1.5), "Slate", { Collide = true, Shadow = false })
			end
		end
	end
	-- the entrance arch over the bridge's foot, facing the street; its back says the way home (round Marble columns on
	-- Slate plinths, brass capitals with torches, a Marble lintel)
	local az = startZ + 3
	for _, sx in ipairs({ -1, 1 }) do
		local foot = A * CFrame.new(sx * (hw + 1.6), -0.3, az)
		Art.part(m, "ArchPillarBase", foot * CFrame.new(0, 0, 0), Vector3.new(2.8, 1.4, 2.8), "Slate", { Collide = true, Shadow = false })
		Art.part(m, "ArchPillarBand", foot * CFrame.new(0, 0.8, 0), Vector3.new(3, 0.25, 3), "MarbleShade", { Shadow = false })
		Art.cyl(m, "ArchPillar", foot * CFrame.new(0, 0.9, 0), 14.4, 2.1, "Marble", { Collide = true })
		Art.part(m, "ArchCap", A * CFrame.new(sx * (hw + 1.6), 15.5, az), Vector3.new(2.6, 0.6, 2.6), "Brass", { Shadow = false })
		local fl = Art.part(m, "Flame", A * CFrame.new(sx * (hw + 1.6), 16.4, az) * CFrame.Angles(0, rad(45), 0), Vector3.new(1, 1.2, 1), flameColor(C.Crimson), { Material = MAT.Neon, Shadow = false })
		emitter(fl, { Color = ColorSequence.new(rgb(255, 220, 160), C.Crimson), Rate = 3, Speed = NumberRange.new(1, 2), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(15, 15) })
	end
	Art.part(m, "ArchLintel", A * CFrame.new(0, 14.6, az), Vector3.new(BRIDGE_W + 6, 1.2, 2.4), "Marble", { Collide = true })
	local sign = Art.part(m, "ArchSign", A * CFrame.new(0, 11.5, az), Vector3.new(12, 4, 0.6), "SlateDark", { Collide = true, Shadow = false })
	Art.part(m, "ArchSignTrim", A * CFrame.new(0, 13.75, az), Vector3.new(12.6, 0.4, 0.9), "Brass", { Shadow = false })
	-- the arch's local frame: Front (-Z) faces the street (the lobby)
	archSign(sign, Enum.NormalId.Front, "BATTLE ARENA", "Duels " .. GLYPH.Dot .. " Boss Raids " .. GLYPH.Dot .. " Trophies")
	archSign(sign, Enum.NormalId.Back, "TO THE PLAZA", "Homes " .. GLYPH.Dot .. " Portals " .. GLYPH.Dot .. " Shop")
	-- puffs under the open stretch next to the island
	local puff = Art.shadeCloud(puffTemplate(1.3), CFrame.new(), 13)
	for _, z in ipairs({ endZ - 14, endZ - 34 }) do
		if z > startZ + 20 then
			Art.tag(place(puff, A * CFrame.new(0, -1.6, z), m, "BridgePuff"), "Exempt")
		end
	end
	return m
end

----------------------------------------------------------------------
-- The Gate Court gates (Phase 5, 6.2): Portal_Ring and Portal_Arena via WorldStyle.BuildGate, parented to
-- LobbyInfo.GatesFolder; the forum's Return gate. ONE helper table keeps the main chunk under the 200-locals limit.
----------------------------------------------------------------------

-- Phase 4: the Champion Ring (Portal_Ring in the Gate Court, the ring pockets).
local Ring = {
	Color = rgb(250, 190, 56), -- champion gold (trim, crown)
	Accent = rgb(156, 96, 238), -- royal violet (glows, gems)
	PortalBudget = 120, -- Portal_Ring parts (6.2: every gate <= 120)
	PocketBudget = 250, -- Phase 5 art pass (stone deck + kerb): 10.3 counts up to 600 per pocket in the client total
	Title = "Champion Ring",
	Info = "Beat the champion, meet a stronger one",
	EmptyBoard = "No record yet: be the first!",
	PromptRange = 12,
	NameChars = 12, -- the record holder's name in the pill (longer names end in "...")
	TagWidth = 600, -- px: the pill "Best in this server: <12 letters> - Round 123" fits at PillSize
	PillSize = 22,
}

local Gates = {
	Budget = 120,
	ArenaTitle = "Battle Arena",
	ArenaInfo = "Duels and boss raids",
}

-- A Gate Court gate: WorldStyle.BuildGate (or a plain stand-in when WorldStyle is missing / throws) -> model, pad,
-- promptPart, the tag's pill label. spec = { Id, Title, Info, Color, Glyph, Pad, Pill }
function Gates.build(parent, site, spec)
	local model, pad, prompt = nil, nil, nil
	if WorldStyle and type(WorldStyle.BuildGate) == "function" then
		local ok, m, p, pp = pcall(WorldStyle.BuildGate, parent, site, {
			Id = spec.Id,
			Title = spec.Title,
			Info = spec.Info,
			Color = spec.Color,
			Glyph = spec.Glyph,
			Pad = spec.Pad,
			Pill = spec.Pill,
			Name = "Portal_" .. spec.Id,
		})
		if ok then
			model, pad, prompt = m, p, pp
		else
			warn("[ArenaBuilder] gate " .. spec.Id .. " failed: " .. tostring(m))
			local broken = parent:FindFirstChild("Portal_" .. spec.Id)
			if broken then
				broken:Destroy()
			end
		end
	end
	if not model then
		model = newModel(parent, "Portal_" .. spec.Id)
		model:SetAttribute("GateId", spec.Id)
		for _, sx in ipairs({ -1, 1 }) do
			box(model, "Column", site * CFrame.new(sx * 8.2, 8, 0), Vector3.new(2.4, 16, 2.4), C.StoneLight, { Collide = true })
		end
		model.PrimaryPart = box(model, "Lintel", site * CFrame.new(0, 17.4, 0), Vector3.new(21.4, 2.4, 3), C.Stone, { Collide = true })
		if spec.Pad then
			pad = box(model, "Pad", site * CFrame.new(0, 0.3, -14), Vector3.new(14, 0.6, 14), C.Stone, { Collide = true })
		else
			pad = box(model, "Step", site * CFrame.new(0, 0.15, -6), Vector3.new(10, 0.3, 6), C.Stone, { Collide = true })
		end
		prompt = box(model, "PromptAnchor", site * CFrame.new(0, 3, -2.2), Vector3.new(2, 2, 1), C.Stone, { Transparency = 1, Shadow = false })
		local anchor = anchorPart(model, "TagAnchor", site * CFrame.new(0, 27, 0))
		local gui = newTag(anchor, "GateTag", spec.TagWidth or 420, 150, 0, 120)
		local plate = tagPlate(gui, C.Gold, 200)
		tagText(plate, "Title", spec.Title, "Heading", 28, C.Text, 1)
		tagText(plate, "Info", spec.Info, "Body", 20, C.Text, 2)
		tagPill(plate, "Pill", spec.Pill or "", "Label", 18, C.Navy, 3)
	end
	local tag = model:FindFirstChild("GateTag", true)
	local pill = tag and tag:FindFirstChild("Pill", true)
	local label = pill and (pill:FindFirstChild("Label") or pill:FindFirstChild("PillLabel"))
	if spec.TagWidth and tag and tag:IsA("BillboardGui") then
		tag.Size = UDim2.fromOffset(spec.TagWidth, tag.Size.Y.Offset)
	end
	return model, pad, prompt, label
end

-- A crowned pedestal (Portal_Ring's extras): a Slate plinth, a Marble post, a gold crown with violet Neon gems.
function Gates.crownPedestal(parent, cf)
	box(parent, "PedestalBase", cf * CFrame.new(0, 0.6, 0), Vector3.new(2.6, 1.2, 2.6), C.Stone, { Collide = true, Material = MAT.Slate })
	box(parent, "PedestalPost", cf * CFrame.new(0, 2.4, 0), Vector3.new(1.8, 2.4, 1.8), C.StoneLight, { Collide = true, Material = MAT.Marble })
	box(parent, "PedestalCap", cf * CFrame.new(0, 3.75, 0), Vector3.new(2.3, 0.3, 2.3), C.StoneLight, { Material = MAT.Marble })
	box(parent, "CrownBand", cf * CFrame.new(0, 4.3, 0), Vector3.new(1.9, 0.8, 1.9), Ring.Color, { Material = MAT.Metal, Shadow = false })
	for _, o in ipairs({ { -0.7, -0.7 }, { 0.7, -0.7 }, { -0.7, 0.7 }, { 0.7, 0.7 } }) do
		box(parent, "CrownPoint", cf * CFrame.new(o[1], 5.05, o[2]), Vector3.new(0.45, 0.7, 0.45), Ring.Color, { Material = MAT.Metal, Shadow = false })
	end
	box(parent, "CrownGem", cf * CFrame.new(0, 4.3, -0.98), Vector3.new(0.5, 0.5, 0.12), Ring.Accent, { Material = MAT.Neon, Shadow = false })
end

-- A torch (Portal_Arena's extras): a Slate foot, a wooden post, an iron bowl and a warm Neon flame with a light.
function Gates.torch(parent, cf, flame)
	box(parent, "TorchFoot", cf * CFrame.new(0, 0.5, 0), Vector3.new(1.8, 1, 1.8), C.Stone, { Collide = true, Material = MAT.Slate })
	box(parent, "TorchPost", cf * CFrame.new(0, 3, 0), Vector3.new(0.7, 4, 0.7), C.Wood or C.StoneDark, { Collide = true, Material = MAT.Wood })
	box(parent, "TorchBowl", cf * CFrame.new(0, 5.25, 0), Vector3.new(1.5, 0.5, 1.5), C.Iron or C.StoneDark, { Material = MAT.Metal, Shadow = false })
	local f = box(parent, "TorchFlame", cf * CFrame.new(0, 5.95, 0), Vector3.new(0.8, 0.9, 0.8), flame, { Material = MAT.Neon, Shadow = false })
	f.CanCollide = false
	pointLight(f, rgb(255, 214, 170), 1.2, 12)
end

-- The gate site from the lobby (GateSites first; RingSite for Ring) or nil.
function Gates.site(lobbyInfo, id)
	local sites = type(lobbyInfo.GateSites) == "table" and lobbyInfo.GateSites or {}
	local site = sites[id]
	if typeof(site) ~= "CFrame" and id == "Ring" then
		site = lobbyInfo.RingSite
	end
	return typeof(site) == "CFrame" and site or nil
end

function Gates.folder(lobbyInfo, fallback)
	local f = lobbyInfo.GatesFolder
	if typeof(f) == "Instance" and f.Parent ~= nil then
		return f
	end
	return fallback
end

-- Portal_Arena (always built, 6.2): -> prompt part, the lobby landing (in front of the gate, looking at the plaza).
function Gates.buildArena(lobbyInfo, fallbackParent)
	local site = Gates.site(lobbyInfo, "Arena")
	if not site then
		return nil, nil
	end
	local parent = Gates.folder(lobbyInfo, fallbackParent)
	local model, _, prompt = Gates.build(parent, site, { Id = "Arena", Title = Gates.ArenaTitle, Info = Gates.ArenaInfo, Color = "Red", Glyph = "swords", Pad = false })
	for _, sx in ipairs({ -1, 1 }) do
		Gates.torch(model, site * CFrame.new(sx * 13.2, 0, -1.5), rgb(255, 150, 70))
	end
	local p = makePrompt(prompt, "ArenaPortalPrompt", "Travel", Gates.ArenaTitle)
	p.MaxActivationDistance = PROMPT_RANGE + 2
	S.gatePrompts[p] = true
	local n = countParts(model)
	if n > Gates.Budget then
		warn(string.format("[ArenaBuilder] Portal_Arena has %d parts (budget %d)", n, Gates.Budget))
	end
	local front = site.Position + site.LookVector * 10
	local landing = CFrame.lookAt(front + Vector3.new(0, 3, 0), front + site.LookVector * 20 + Vector3.new(0, 3, 0))
	return prompt, landing
end

-- The Return gate on the forum (always built): lands in front of Portal_Arena (ArenaInfo.LobbyCFrame).
function Gates.buildReturn(model, A)
	local rSite = A * CFrame.new(0, 0, ISL.FrontZ + 34) * CFrame.Angles(0, pi, 0)
	local gate, _, prompt = Gates.build(model, rSite, { Id = "Return", Title = "To the Plaza", Info = "Homes, gates, shop", Color = "Green", Glyph = "house", Pad = false })
	local p = makePrompt(prompt, "ArenaReturnPrompt", "Travel", "Plaza")
	p.MaxActivationDistance = PROMPT_RANGE + 2
	S.gatePrompts[p] = true
	return gate
end

-- The status pill of Portal_Ring from its RingBoard attribute ("Alex|31;Sam|24;Kim|20", written by BattleService when
-- a run ends): "Best in this server: Alex - Round 31" (the highest round of the list), else an invitation.
function Ring.boardText(board)
	local bestName, bestRound = nil, 0
	if type(board) == "string" then
		for entry in board:gmatch("[^;]+") do
			local name, round = entry:match("^%s*(.-)%s*|%s*(%d+)%s*$")
			round = tonumber(round)
			if name and name ~= "" and round and round > bestRound then
				bestName, bestRound = name, round
			end
		end
	end
	if not bestName then
		return Ring.EmptyBoard
	end
	bestName = fitText((bestName:gsub("[%c<>]", "")), 24, Ring.NameChars * 12)
	if bestName == "" then
		bestName = "a champion"
	end
	return "Best in this server: " .. bestName .. " - Round " .. tostring(math.min(bestRound, 99999))
end

-- keeps the pill in step with the RingBoard attribute (on the Portal_Ring model and on its pad: BattleService writes
-- both); the text changes only when a run ends (no per-frame work)
function Ring.watchBoard(model, pad, label)
	local function refresh(inst)
		if label and label.Parent then
			label.Text = Ring.boardText(inst:GetAttribute("RingBoard"))
		end
	end
	for _, inst in ipairs({ model, pad }) do
		if typeof(inst) == "Instance" then
			inst:GetAttributeChangedSignal("RingBoard"):Connect(function()
				refresh(inst)
			end)
		end
	end
	local start = model:GetAttribute("RingBoard") ~= nil and model or pad
	refresh(start)
end

-- Portal_Ring: the Gate Court's Ring gate (LobbyInfo.GateSites.Ring, = LobbyInfo.RingSite; C12) in the GatesFolder
-- -> pad part (ArenaInfo.RingPortal), site. Without a site nothing is built: nil.
function Ring.buildPortal(model, lobbyInfo)
	local site = Gates.site(lobbyInfo, "Ring")
	if not site then
		return nil, nil
	end
	local parent = Gates.folder(lobbyInfo, model)
	local portal, pad, _, pill = Gates.build(parent, site, {
		Id = "Ring",
		Title = Ring.Title,
		Info = Ring.Info,
		Color = "Gold",
		Glyph = "crown",
		Pad = true,
		Pill = Ring.EmptyBoard,
		TagWidth = Ring.TagWidth,
	})
	for _, sx in ipairs({ -1, 1 }) do
		Gates.crownPedestal(portal, site * CFrame.new(sx * 9.4, 0, -21.2))
	end
	local prompt = makePrompt(pad, "RingPrompt", Ring.Title, "Portal", "Ring")
	prompt.MaxActivationDistance = Ring.PromptRange
	Ring.watchBoard(portal, pad, pill)
	local n = countParts(portal)
	if n > Ring.PortalBudget then
		warn(string.format("[ArenaBuilder] Portal_Ring has %d parts (budget %d)", n, Ring.PortalBudget))
	end
	return pad, site
end

----------------------------------------------------------------------
-- Pockets: the private Champion Ring arenas (one template, cloned onto a grid far out in the sky)
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Phase 4: the Champion Ring pocket (BuildPocket(index, "Ring")): a round ring on its own cloud, built from one template
----------------------------------------------------------------------
Ring.FloorA = 33 -- the ring floor's apothem (16-gon): the 44 x 44 battle square fits at any rotation (half diagonal 31.1)
Ring.RimOut = 35.6 -- the gold rim around it

-- the front-most voxel of a column (the face looking at -Z): paints a face detail onto a rounded body
function Ring.paintFront(g, x, y, key)
	x, y = floor(x + 0.5), floor(y + 0.5)
	for z = -40, 40 do
		if Voxel.Get(g, x, y, z) then
			Voxel.Set(g, x, y, z, key)
			return
		end
	end
end

-- the cheering crowd: a cloud bleacher with two steps behind the champion's side and seven cloud puffs on it in soft
-- colours (a chunky body with a cloud bump on top, little arms thrown up, dark eyes and an open smile: 8 blocks each).
-- Stand-local studs: x across, y up from the cloud top, the front edge at z = 0 facing -Z (the ring).
Ring.PuffTints = { rgb(255, 255, 255), rgb(255, 208, 224), rgb(198, 228, 255), rgb(226, 212, 255), rgb(204, 244, 216) }
function Ring.crowdStand()
	if Ring.standTpl then
		return Ring.standTpl
	end
	local m = newModel(nil, "CrowdStand")
	-- Phase 5: a stone bleacher (Slate steps with Marble nosings on a plinth); the cloud puffs on it are characters
	-- (like pets: their own soft look, tagged NC_StyleExempt)
	Art.part(m, "StandStep", CFrame.new(0, 0.75, 1.9), Vector3.new(34, 1.5, 3.8), "Stone", { Collide = true, Shadow = false })
	Art.part(m, "StandStep", CFrame.new(0, 1.75, 5.7), Vector3.new(28, 3.5, 3.8), "StoneDark", { Collide = true, Shadow = false })
	Art.part(m, "StandNosing", CFrame.new(0, 1.58, 0.15), Vector3.new(34.2, 0.18, 0.5), "Marble", { Shadow = false })
	Art.part(m, "StandNosing", CFrame.new(0, 3.58, 3.95), Vector3.new(28.2, 0.18, 0.5), "Marble", { Shadow = false })
	local puffs = newModel(m, "CrowdPuffs")
	Art.tag(puffs, "Exempt")
	local spots = { { -12, 1.5, 1.9 }, { -4, 1.5, 1.9 }, { 4, 1.5, 1.9 }, { 12, 1.5, 1.9 }, { -8, 3.5, 5.7 }, { 0, 3.5, 5.7 }, { 8, 3.5, 5.7 } }
	for i, sp in ipairs(spots) do
		local tint = Ring.PuffTints[(i - 1) % #Ring.PuffTints + 1]
		local base = CFrame.new(sp[1], sp[2], sp[3]) * CFrame.Angles(0, rad((i % 3 - 1) * 8), 0)
		local shade = tint:Lerp(C.MistDark, 0.22)
		local m = puffs
		box(m, "PuffBody", base * CFrame.new(0, 1.1, 0), Vector3.new(3.4, 2.2, 2.4), tint, { Shadow = false })
		box(m, "PuffTop", base * CFrame.new(0, 2.6, 0.1), Vector3.new(2.6, 0.8, 2.1), tint, { Shadow = false })
		box(m, "PuffBump", base * CFrame.new(-0.3, 3.3, 0.2), Vector3.new(1.4, 0.7, 1.5), tint, { Shadow = false })
		for _, sx in ipairs({ -1, 1 }) do
			box(m, "PuffArm", base * CFrame.new(sx * 2, 2.3, 0) * CFrame.Angles(0, 0, rad(-sx * 28)), Vector3.new(0.6, 1.7, 0.6), shade, { Shadow = false })
			box(m, "PuffEye", base * CFrame.new(sx * 0.6, 1.75, -1.22), Vector3.new(0.38, 0.7, 0.1), C.Ink, { Shadow = false })
		end
		box(m, "PuffMouth", base * CFrame.new(0, 1.05, -1.22), Vector3.new(0.7, 0.35, 0.1), rgb(196, 70, 104), { Shadow = false })
	end
	Ring.standTpl = m
	return m
end

-- a crown post (four on the diagonals): a stone post on a dark base, a gold crown with four points and a violet gem
function Ring.crownPost(m, cf, lit)
	Art.part(m, "PostBase", cf * CFrame.new(0, 0.6, 0), Vector3.new(3.4, 1.2, 3.4), "Slate", { Collide = true, Shadow = false })
	Art.cyl(m, "Post", cf * CFrame.new(0, 1.2, 0), 5.6, 2, "Marble", { Collide = true })
	Art.part(m, "CrownBand", cf * CFrame.new(0, 7.3, 0), Vector3.new(3.2, 1.1, 3.2), Ring.Color, { Material = MAT.Metal, Collide = true, Shadow = false })
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		Art.part(m, "CrownPoint", cf * CFrame.new(c[1] * 1.25, 8.35, c[2] * 1.25), Vector3.new(0.7, 1, 0.7), Ring.Color, { Material = MAT.Metal, Shadow = false })
	end
	local gem = Art.part(m, "CrownGem", cf * CFrame.new(0, 8.4, 0) * CFrame.Angles(0, rad(45), 0), Vector3.new(1.2, 1.2, 1.2), Ring.Accent, { Material = MAT.Neon, Shadow = false })
	if lit then
		pointLight(gem, Art.Light, 1.2, 16)
	end
end

-- the ring pocket template (centre = the floor surface, axis aligned; -Z = the fighter's side, +Z = the champion's)
function Ring.pocketTemplate()
	if Ring.tpl then
		return Ring.tpl
	end
	local m = newModel(nil, "RingPocket")
	-- the cloud: round, a little wider than the rim, the crowd stands on its top
	local rng = Util.NewRng(SEED + 41)
	local puffs = {}
	for deg = 45, 359, 90 do
		local a = rad(deg)
		local sz = rng:Float(11, 14)
		puffs[#puffs + 1] = { cos(a) * 43, rng:Float(-9, -6), sin(a) * 43, sz, sz * 0.6, sz }
	end
	puffs[#puffs + 1] = { 0, -18, 0, 28, 9, 28 }
	local function sdf(x, z)
		return sqrt(x * x + z * z) - 46
	end
	local g = cloudGrid({
		V = 6,
		Sdf = sdf,
		Bounds = { -50, 50, -50, 50 },
		Tiers = { { Inset = 0, H = 1 }, { Inset = 12, H = 1 } },
		Puffs = puffs,
		Carve = function(x, y, z)
			return y > 0 and sdf(x, z) < -3
		end,
		Seed = 14,
	})
	Art.shadeCloud(VX.Build(g, { V = 6, Pal = CLOUD_PAL, Name = "RingCloud", CF = CFrame.new(0, -1.2 - 3, 0), Collide = true, MaxParts = 40, Parent = m }), CFrame.new(), 26)
	-- Phase 5 (6.4): a stone deck round the ring (Cobblestone apron with a kerb on its 16 edges) on the cloud
	Art.ring(m, "PocketApron", CFrame.new(), Ring.RimOut - 0.5, 45.5, -0.15, 1.1, "Cobble", { Seed = 707 })
	for j = 0, 15 do
		local seg = CFrame.Angles(0, j * STEP16, 0)
		Art.kerb(m, seg * CFrame.new(0, -0.15, -45.5), 2 * 45.5 * TAN16)
	end
	-- the floor: eight long slabs turned 22.5 degrees apart (the 16-gon), warm sand
	local slabW = 2 * Ring.FloorA * TAN16 + 0.4
	for j = 0, 7 do
		box(m, "RingFloor", CFrame.Angles(0, j * STEP16, 0) * CFrame.new(0, j * 0.004 - 0.5, 0), Vector3.new(slabW, 1, Ring.FloorA * 2), Art.P.Sand, { Collide = true, Material = MAT.Sand, Shadow = false })
	end
	-- a paler canvas in the middle (the fighters' lanes stay warm sand)
	disc16(m, "RingCanvas", CFrame.new(), 23, 0.04, 0.3, Art.P.SandLight, MAT.Sand, false)
	-- the rim: a Marble curb with a thin champion-gold Neon inlay all around
	ring16(m, "RingRim", CFrame.new(), Ring.FloorA - 0.4, Ring.RimOut, 0.7, 1.9, Art.P.Marble, MAT.Marble, true)
	ring16(m, "RingRimInlay", CFrame.new(), Ring.FloorA + 0.9, Ring.FloorA + 1.4, 0.74, 0.06, Ring.Color, MAT.Neon, false)
	-- the crown in the middle: a violet disc with a gold crown pointing at the champion's side (+Z)
	disc16(m, "EmblemDisc", CFrame.new(), 7.5, 0.06, 0.2, Art.tone(Ring.Accent, 0.44, 0.45, 0.7), MAT.Slate, false)
	local emblem = { { 0, -3.4, 9, 1.8 }, { 0, 0.4, 2, 6.2 }, { -3.6, -0.6, 1.8, 4.2 }, { 3.6, -0.6, 1.8, 4.2 } }
	for _, e in ipairs(emblem) do
		-- { x, z centre, width, depth }
		box(m, "EmblemCrown", CFrame.new(e[1], 0.12, e[2]), Vector3.new(e[3], 0.12, e[4]), Art.P.Gold, { Material = MAT.Metal, Shadow = false })
	end
	for _, e in ipairs({ { 0, 4.3 }, { -3.6, 2.3 }, { 3.6, 2.3 } }) do
		box(m, "EmblemGem", CFrame.new(e[1], 0.14, e[2]) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(1.3, 0.12, 1.3), rgb(255, 244, 214), { Material = MAT.Neon, Shadow = false })
	end
	-- four crown posts on the diagonals, two of them lit
	local postR = Ring.RimOut + 2
	for j = 0, 3 do
		local a = rad(45 + 90 * j)
		Ring.crownPost(m, CFrame.new(cos(a) * postR, -0.15, sin(a) * postR), j % 2 == 0)
	end
	-- the cheering crowd on its cloud bleacher behind the champion's side (+Z)
	place(Ring.crowdStand(), CFrame.new(0, -0.15, Ring.FloorA + 4.6), m, "Crowd")
	-- confetti over the crowd (particles only: no server animation)
	local confetti = box(m, "Confetti", CFrame.new(0, 14, 0), Vector3.new(80, 1, 80), Ring.Color, { Transparency = 1, Shadow = false })
	confetti.CanQuery = false
	emitter(confetti, {
		Color = ColorSequence.new(Ring.Color, Ring.Accent),
		Rate = 6,
		Lifetime = NumberRange.new(2.5, 3.5),
		Speed = NumberRange.new(1, 2),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(20, 20),
		Size = popSize(0.6),
	})
	-- the fighter's pad (-Z) and the champion's pad (+Z, gold with a violet glow)
	local hf = Ring.FloorA
	box(m, "SpawnPad", CFrame.new(0, 0.1, -(hf - 7)), Vector3.new(7, 0.4, 7), Art.P.Brass, { Collide = true, Material = MAT.Metal, Shadow = false })
	box(m, "SpawnGlow", CFrame.new(0, 0.32, -(hf - 7)), Vector3.new(5.6, 0.2, 5.6), rgb(96, 196, 108), { Material = MAT.Neon, Shadow = false })
	box(m, "ChampionPad", CFrame.new(0, 0.1, hf - 7), Vector3.new(7, 0.4, 7), Art.P.Brass, { Collide = true, Material = MAT.Metal, Shadow = false })
	box(m, "ChampionGlow", CFrame.new(0, 0.32, hf - 7), Vector3.new(5.6, 0.2, 5.6), Ring.Accent, { Material = MAT.Neon, Shadow = false })
	m:SetAttribute("ArtFixes", Art.enforce(m))
	Ring.tpl = m
	return m
end

function ArenaBuilder.GetPocket(index)
	return S.pockets[index]
end

-- Phase 5: the only pocket is the Champion Ring's ("Ring"); nil / unknown kinds build it too (the Trial pocket is
-- deleted). An index that is already built returns that pocket.
function ArenaBuilder.BuildPocket(index, kind)
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
	local okT, tpl = pcall(Ring.pocketTemplate)
	if not okT or not tpl then
		warn("[ArenaBuilder] ring pocket template failed: " .. tostring(tpl))
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
	local model = place(tpl, cf, holder, "RingPocket_" .. index)
	model:SetAttribute("PocketIndex", index)
	model:SetAttribute("PocketKind", "Ring")
	local floorSize = zoneFloorSize("Ring")
	local hf = Ring.FloorA
	local zone = makeZone(model, "BattleZone_Ring", cf, Ring.RimOut, "Ring", floorSize, "Ring", index)
	local spawn = CFrame.lookAt(pos + Vector3.new(0, 3, -(hf - 7)), pos + Vector3.new(0, 3, hf))
	local info = { Model = model, CFrame = cf, Size = floorSize, Spawn = spawn, Zone = zone, Index = index, Kind = "Ring" }
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
	-- the holder goes away with the last pocket (the workspace stays as tidy as before the first run)
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
	elseif name == "ArenaPortalPrompt" and S.gatePrompts[prompt] then
		teleport(player, prompt, S.info.Spawn, "Arena", "Portal")
	elseif name == "ArenaReturnPrompt" and S.gatePrompts[prompt] then
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

	-- Phase 5 (6.2, C12): the Gate Court's Portal_Ring and Portal_Arena (in LobbyInfo.GatesFolder) and the forum's
	-- Return gate; the Trials and the fallback portal pair are gone
	S.gatePrompts = {}
	local ringPad, ringSite = nil, nil
	section("ring portal", function()
		ringPad, ringSite = Ring.buildPortal(model, lobbyInfo)
	end)
	local arenaPrompt, lobbyCF = nil, nil
	section("arena portal", function()
		arenaPrompt, lobbyCF = Gates.buildArena(lobbyInfo, model)
	end)
	section("return gate", function()
		Gates.buildReturn(model, A)
	end)
	-- ring climbers come back in front of Portal_Ring (BattleService builds the same point from RingSite)
	local returnCF = nil
	if ringSite then
		local front = ringSite.Position + ringSite.LookVector * 12
		returnCF = CFrame.lookAt(front + Vector3.new(0, 3, 0), front + ringSite.LookVector * 30 + Vector3.new(0, 3, 0))
	end

	-- the arrival point on the forum, looking at the main gate
	local spawnPos = (A * CFrame.new(0, 3, ISL.FrontZ + 20)).Position
	local spawn = CFrame.lookAt(spawnPos, (A * CFrame.new(0, 3, 0)).Position)
	lobbyCF = lobbyCF or returnCF
	returnCF = returnCF or lobbyCF

	-- the 6.4 safety net (big SmoothPlastic, saturation / value of big faces, small-part shadows); 0 when every
	-- piece above follows the rules (the art audit of smoke_p3_arenaworld checks the result)
	model:SetAttribute("ArtFixes", Art.enforce(model))
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
		RingPortal = ringPad, -- Phase 4: Portal_Ring's pad (RingPrompt, OpenPanel = "Ring"; ring starts are accepted near it)
		RingSite = ringSite,
		ArenaPortal = arenaPrompt, -- Phase 5: Portal_Arena's prompt part (ArenaPortalPrompt)
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

-- The NC_BattleZone part (arena floor, a duel ring or a Champion Ring pocket: Mode "Raid" | "Duel" | "Ring") that
-- contains the position.
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
