-- LobbyBuilder (v3): builds the Nimbus Climb sky village in the DETAILED VOXEL style
-- (ARCHITECTURE_V3.md, "ART DIRECTION" + section 6), sculpted with shared/Voxel.lua.
--
-- Top view (+X right, +Z up the page, angles in degrees: x = cos, z = sin, plaza centre = Origin):
--
--   * PLAZA          a big round cloud island (Phase 5: PlazaRadius 150, 1.8x the Phase 4 area). Its body is a tiered
--                    voxel cloud (white / light-blue, tagged NC_StyleExempt); the top is built in the Phase 4 look again
--                    (Phase 6, 6.0.2 / 6.1 A1: SmoothPlastic, bright lime grass, cream stone paths with darker borders,
--                    glow in Neon) on the Phase 5 layout: the spawn court (concentric cream stone tile rings, a light
--                    ring, a gold sun medallion with Neon arrows in the gate colours), the grand avenue to the Gate
--                    Court (stone kerbs, lamps every 16 studs, a tall cream welcome arch at r 40 carrying the welcome
--                    sign), the circle walk (r 100) with clipped hedges and lamps, the east / west walks, the shop
--                    boardwalk with the fountain roundabout, lawns with trees, benches, flower beds and the six NPC
--                    spots, a kerb along the edge.
--   * GATE COURT     (6.1) a sector 48..132 degrees, r 96..146: cream tile rings, a light rim, a raised terrace with
--                    hedges, a banner behind every gate and two obelisks. Five gates left -> right Obby, Dungeon, Ring,
--                    Arena, Altar on the arc r Config.Lobby.GateArcRadius, spread evenly over the court's six Phase 5
--                    slots (GateStep degrees apart) around GateFacing, the Ring gate in the middle, every gate facing
--                    the spawn (WorldStyle.BuildGate: the P4 round voxel hoop family, 6.0.3). Phase 6: no Home gate (the
--                    player asked; the Home window's Go home portal is the way home). This module builds Obby and Altar
--                    into the Gates folder; ArenaBuilder adds Ring + Arena, DungeonBuilder the Dungeon gate.
--   * SHOP ISLAND    at Config.Lobby.ShopOffset: four voxel gacha machines (Model Roulette_<Id>, built in
--                    the roulette colour), the striped item stall (Model ItemShop; HUD cleanup: decoration only,
--                    boarded up with a Closed sign, no prompt), a rarity board, a token
--                    statue and an entrance arch, joined to the plaza by a short stone neck.
--   * HOME PLOTS     Config.Lobby.SpotCount cloud islands on Config.Lobby.SpotRingRadius: a puffy cloud body
--                    (billows along the sides and back, a hanging cumulus underneath, a soft rim of puffs on the
--                    outer margins) under a flat PlotSize x PlotSize mowed lawn yard (kept EMPTY for the
--                    phase-2 home), fence posts and rails, a gate facing the ring street, a mailbox with the
--                    nameplate, the pet podium.
--   * RING STREET    a stone street along the front of every plot; wooden bridges join neighbouring plots
--                    at the junctions. Wooden spoke bridges (supported by cloud puffs) join the plaza to every
--                    other junction; two garden islands hang off the street; one junction slot stays free for
--                    the Storm Altar (LobbyInfo.AltarSite).
--   * SKY            voxel cumulus clouds around the village and one far below it.
--
-- LobbyBuilder.Build() -> LobbyInfo (ARCHITECTURE.md / _V2 / _V3 contract):
--   Folder, SpawnCFrame, Portals = { Obby = PortalInfo (+ Model, PromptPart) } (Phase 5: the one Sky Obby portal),
--   Spots[i] = SpotInfo, Shop = { Roulettes[id], ItemShop },
--   NpcSpots = { CFrame x6 }   ground-level CFrames on the plaza lawn beside the walkways, LookVector = towards
--                              the walkway / court, each with ~5 studs of free space for an NPC pedestal
--   AltarSite = CFrame | nil   reserved, empty spot inside the ring for the Storm Altar island (faces the plaza)
--   AltarDock = Vector3 | nil  inner edge of the street junction in front of it (where a bridge can dock; that
--                              junction's inner rope rail is left open for the altar's bridge and gate)
--   Phase 3 (built by ArenaBuilder into workspace.BattleArena; the lobby only keeps their ground free):
--   ArenaAngle = degrees | nil  the spoke just past the last portal; its junction's OUTER rope rail is open
--   ArenaDock = Vector3 | nil   outer edge of that junction on the spoke's ray: the arena bridge leaves the street here
--   ArenaBridgeWidth = studs    the arena bridge's deck width (the rail gap is 1.6 studs wider)
--   Phase 5 (6.1): GateSites = { Obby, Dungeon, Ring, Arena, Altar } ground CFrames of the gate centres
--                              (LookVector = towards the plaza centre); RingSite = GateSites.Ring; DungeonSite =
--                              GateSites.Dungeon; GatesFolder = workspace.NimbusLobby.Gates; Gates = { Obby, Altar
--                              = { Model, Pad, PromptPart } } (GateService / PortalService put the prompts on them).
--                              NimbusLobby.PartCount is written by Main after the last gate builder, not here.
-- SpotInfo also carries PlotCFrame (centre of the flat yard surface, LookVector = towards the gate),
-- PlotSize (= Config.Lobby.PlotSize), GateCFrame (gate, on the ground) and Accent (the plot colour).
-- Spot folders are named Spot_NN and carry the attribute SpotIndex; portal / roulette models are named
-- Portal_<Id> / Roulette_<Id> (tutorial targets).
--
-- Walkability: every walking surface is a flat collidable part at the plaza height (TOP); layers that meet
-- differ by at most 0.3 studs (no gaps, no jumps, no z-fighting: overlapping layers are offset in height).
-- Decor stands on the surface under it: props on the lawn sit LAWN studs under TOP (nothing hovers), pennants
-- hang from their rope, puffs under bridges stop at the deck, and no cloud rises over a path or an exit.
-- No server-side animation (v3 replication rule): life comes from ParticleEmitters and lights only.
--
-- Part budget: the lobby with all six gates <= 8000 parts after the greedy voxel merge (10.3). Repeated decor (trees, lamps, benches, flower beds,
-- the whole plot with its island, fence and gate, cloud puffs, sky clouds) is sculpted once and :Clone()d.
-- No external assets: Parts, built-in particle textures and Theme-styled GUI text. Deterministic (seeded).
-- ProximityPrompts are NOT created here: PetService attaches them to the PromptParts (the item stall's PromptPart
-- stays for the LobbyInfo shape and gets none since the HUD cleanup). The one exception
-- (bug batch 2 #7): every bench's "Sit" prompts, handled here (Benches).
--
-- Robustness: gates, spots, the shop machines and the item stall are what other services depend on. Each
-- is built inside pcall with a plain-part fallback that still returns the same LobbyInfo shape (the
-- fallbacks also cover a missing shared/Voxel module), and all decoration runs in guarded sections.
-- Plain Lua 5.1-compatible syntax only.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local Util = require(Shared.Util)

local LobbyBuilder = {}

local function loadShared(name)
	local inst = Shared:FindFirstChild(name)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	warn("[LobbyBuilder] shared/" .. name .. " unavailable: " .. tostring(result))
	return nil
end

local Voxel = loadShared("Voxel")
local WorldStyle = loadShared("WorldStyle")
local DETAIL_TAG = (WorldStyle and WorldStyle.Tags and WorldStyle.Tags.Detail) or "NC_Detail" -- pure decor (Low graphics hides it)
local EXEMPT_TAG = (WorldStyle and WorldStyle.Tags and WorldStyle.Tags.Exempt) or "NC_StyleExempt" -- voxel clouds / pets / tokens

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

local LOBBY = Config.Lobby
local ORIGIN = LOBBY.Origin
local TOP = ORIGIN.Y -- y of every walking surface
local LAWN = 0.4 -- the lawn layer's top sits this far under TOP (paths 0, borders -0.1, patches -0.3)
local OX, OZ = ORIGIN.X, ORIGIN.Z
local PLAZA_R = (LOBBY.PlazaRadius or 110) + 6 -- walkable radius of the plaza ground
local SPOT_R = LOBBY.SpotRingRadius or 300
local SPOT_COUNT = math.max(1, LOBBY.SpotCount or 16)
local PLOT = LOBBY.PlotSize or 72
local SEED = 20261009
local MAT = Enum.Material
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

-- Glyphs as UTF-8 byte escapes (keeps the source file ASCII).
local GLYPH = {
	StarFull = "\226\152\133",
	StarEmpty = "\226\152\134",
	Cloud = "\226\152\129",
	Bullet = "\226\128\162",
	Ellipsis = "\226\128\166",
}

local function atan2(y, x)
	if math.atan2 then
		return math.atan2(y, x)
	end
	return math.atan(y, x)
end

-- Layout numbers (studs). Plot-local frames: origin = yard centre on the ground, -Z = towards the plaza
-- (the gate side), +X = across.
local G = {}
-- Phase 5 Gate Court (6.1): six gates on an arc in front of the spawn
G.GateR = LOBBY.GateArcRadius or 118
G.GateStep = LOBBY.GateStep or 14.5
G.GateFacing = LOBBY.GateFacing or 90
G.CourtSlots = 6 -- Phase 6: the court keeps its Phase 5 width of six gate slots; the five gates spread over it
G.CourtR = 34 -- the spawn court (Slate rings + a Marble ring around the medallion)
G.AvenueHalf = 10 -- the grand avenue to the Gate Court (20 wide, Cobblestone, Brick kerbs)
G.RingRoadR = 100 -- the cobbled circle walk around the lawns (the spokes leave it)
G.CourtIn = 96 -- the Gate Court sector: Slate rings from r 96 ...
G.CourtOut = 146 -- ... to r 146
G.TerraceIn = 126 -- the raised terrace behind the gates (r 126 .. 146)
G.TerraceLift = 0.3
G.PadR = G.GateR - 14 -- pad centres (WorldStyle.BuildGate puts the pad 14 studs in front of the gate)
G.PathHalf = 5 -- radial stone paths (half width incl. border)
G.BoardHalf = 7 -- the wooden boardwalk to the shop
G.StubHalf = 5 -- sand paths to the spoke bridges
G.FountainD = 66 -- fountain roundabout, distance from the centre towards the shop
G.Step = 360 / SPOT_COUNT
G.HalfStep = G.Step / 2
G.PlotHalf = PLOT / 2
G.Verge = 4
G.StreetW = 14
G.StreetZ = -(G.PlotHalf + G.Verge + G.StreetW / 2) -- plot-local z of the street centre line
G.StreetR = SPOT_R + G.StreetZ -- distance of the street centre line from the origin
G.IslandHalfX = G.PlotHalf + 6
G.IslandBack = G.PlotHalf + 6
G.IslandFront = G.StreetZ - G.StreetW / 2
G.JunctionX = G.StreetR * math.tan(math.rad(G.HalfStep)) -- plot-local x of the junctions
G.StreetExt = (G.StreetW / 2) * math.tan(math.rad(G.HalfStep)) + 0.8 -- overlap past the junction
G.SpokeEndR = (G.StreetR - G.StreetW / 2) / math.cos(math.rad(G.HalfStep)) + 2.4
G.SpokeW = 10
G.GardenR = (PLAZA_R + G.StreetR - G.StreetW / 2) / 2 -- garden island centres, halfway between the plaza and the street (221)
G.GardenSize = 22 -- garden island radius
G.ArenaBridgeW = 12 -- Phase 3: the arena bridge (ArenaBuilder) leaves the street through a gap this wide + 1.6

----------------------------------------------------------------------
-- Palette: cheerful but not blinding. Nothing is pure white (cloud tops stay below 249 on red).
----------------------------------------------------------------------

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Phase 6 (6.0.2 / 6.1 A1): the Phase 4 look again (7aa0df2 LobbyBuilder palette): bright lime grass, cream stone
-- paths with darker borders, white / light-blue clouds, everything SmoothPlastic (glow Neon, water Glass). The
-- Phase 5 layout keys (Slate courts, Marble rings and arches, Navy signs) keep their names with P4 colours.
local C = {
	CloudLight = rgb(244, 247, 252),
	Cloud = rgb(232, 238, 249),
	CloudShade = rgb(212, 222, 241),
	Mist = rgb(194, 211, 240),
	MistDark = rgb(170, 190, 228),
	Grass = rgb(108, 186, 86),
	GrassLight = rgb(132, 202, 98),
	GrassDark = rgb(86, 160, 76),
	GrassWild = rgb(94, 168, 76), -- bug #12: the unmown outer meadow's floor (between Grass and GrassDark)
	Hedge = rgb(74, 146, 72),
	HedgeLight = rgb(100, 170, 84),
	Stone = rgb(208, 202, 190), -- cream stone paths
	StoneLight = rgb(226, 221, 209),
	StoneDark = rgb(172, 164, 154),
	StoneEdge = rgb(146, 138, 132), -- path borders / kerbs
	Slate = rgb(214, 208, 196), -- the courts: cream stone tiles (a hair lighter than the paths)
	SlateLight = rgb(228, 223, 211),
	SlateDark = rgb(172, 164, 154),
	Marble = rgb(242, 237, 226), -- the courts' light rings, arches, columns
	MarbleShade = rgb(226, 221, 209),
	Sand = rgb(236, 214, 166),
	SandDark = rgb(212, 186, 138),
	Plank = rgb(196, 146, 98),
	PlankLight = rgb(214, 166, 114),
	PlankDark = rgb(152, 108, 72),
	Bark = rgb(132, 92, 62),
	Iron = rgb(64, 70, 92),
	IronLight = rgb(96, 104, 130),
	Gold = rgb(244, 198, 84),
	GoldDark = rgb(206, 154, 62),
	Lamp = rgb(255, 214, 140),
	Water = rgb(92, 178, 236),
	WaterDeep = rgb(62, 136, 212),
	Leaf = rgb(98, 178, 80),
	Pine = rgb(60, 138, 92),
	Blossom = rgb(246, 174, 204),
	BlossomWhite = rgb(250, 228, 238),
	Soil = rgb(120, 86, 64),
	-- the Sky-Oasis fountain (bug #13): cool natural rock, island soil, twigs, rope, the paper boat, the sign's paint
	Rock = rgb(170, 170, 186),
	RockDark = rgb(140, 142, 160),
	Dirt = rgb(150, 106, 72),
	DirtDark = rgb(120, 84, 58),
	PoolFloor = rgb(112, 132, 156),
	Twig = rgb(156, 112, 70),
	Rope = rgb(214, 192, 142),
	Paper = rgb(250, 248, 240),
	SignPaint = rgb(122, 170, 206),
	Navy = rgb(34, 42, 76),
	Violet = rgb(68, 60, 118),
	Ink = (Theme.Colors and Theme.Colors.Ink) or rgb(26, 32, 64),
	Text = rgb(238, 243, 252),
	TextDim = rgb(190, 202, 230),
	TextGold = rgb(246, 216, 132),
	StarOff = rgb(96, 104, 136),
	Rose = rgb(234, 120, 146),
	Cream = rgb(246, 234, 210),
	PanelTop = rgb(68, 60, 118), -- sign GUI panels only (never a part colour)
	PanelBottom = rgb(34, 42, 76),
}

-- Material of every colour key: the P4 look is SmoothPlastic everywhere; lamps glow (Neon), water is Glass.
-- (materialOf keeps the Phase 5 material names working: they all resolve to SmoothPlastic.)
local MATS = {
	Lamp = "Neon", Water = "Glass", WaterDeep = "Glass",
}
local LOOK_MATERIALS = { Neon = MAT.Neon, Glass = MAT.Glass, SmoothPlastic = MAT.SmoothPlastic }
local function materialOf(name)
	return LOOK_MATERIALS[name] or MAT.SmoothPlastic
end
-- colour -> material for box() calls that pass a C colour (keyed by "r,g,b": Color3 values are not table keys)
local function colorKey(color)
	return string.format("%d,%d,%d", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end
local MAT_BY_COLOR = {}
for key, name in pairs(MATS) do
	if C[key] then
		MAT_BY_COLOR[colorKey(C[key])] = materialOf(name)
	end
end

local FLOWERS = {
	rgb(246, 150, 188), -- pink
	rgb(250, 214, 92), -- yellow
	rgb(244, 244, 248), -- white (not pure)
	rgb(172, 142, 232), -- violet
	rgb(236, 104, 108), -- red
	rgb(112, 172, 240), -- blue
}

-- One accent per home plot (cycled): banner, mailbox flag, podium trim.
local ACCENTS = {
	rgb(232, 112, 132),
	rgb(240, 160, 84),
	rgb(236, 204, 92),
	rgb(108, 192, 124),
	rgb(86, 186, 206),
	rgb(98, 148, 226),
	rgb(154, 122, 222),
	rgb(222, 120, 192),
}

-- The five gates of the Gate Court, left -> right (6.1 / 6.2): id, gate colour (WorldStyle.Palette.Accent), glyph.
-- (Phase 6: the Home gate is gone; players go home with the Home window's Go home button.)
local GATE_SPECS = {
	{ Id = "Obby", Accent = "Blue", Glyph = "cloud" },
	{ Id = "Dungeon", Accent = "Purple", Glyph = "torch" },
	{ Id = "Ring", Accent = "Gold", Glyph = "crown" },
	{ Id = "Arena", Accent = "Red", Glyph = "swords" },
	{ Id = "Altar", Accent = "Cyan", Glyph = "bolt" },
}
local function gateAccent(name)
	local acc = WorldStyle and WorldStyle.Palette and WorldStyle.Palette.Accent
	return (acc and acc[name]) or C.Gold
end

-- One palette for every voxel grid (keys are shared; Voxel derives missing _Light / _Dark variants).
local P = {}
for key, color in pairs(C) do
	P[key] = { Color = color, Material = materialOf(MATS[key] or "SmoothPlastic") }
end
P.GoldGlow = { Color = C.Gold, Material = MAT.Neon }
P.Water = { Color = C.Water, Material = materialOf("Glass"), Transparency = 0.35 }
for i, color in ipairs(FLOWERS) do
	P["Flower" .. i] = { Color = color, Material = materialOf("LeafyGrass") }
end
for i, spec in ipairs(GATE_SPECS) do
	P["Gate" .. i] = { Color = gateAccent(spec.Accent), Material = MAT.Neon }
end

-- Cloud keys used by tiers, from the top tier down (height-banded shading: cheap and soft).
local TIER_KEYS = { "CloudLight", "Cloud", "CloudShade", "Mist", "MistDark" }

----------------------------------------------------------------------
-- Per-build state
----------------------------------------------------------------------

local templates = {} -- name -> unparented Model built at the origin, cloned with place()
local reserved = {} -- { x, z, radius } world circles taken by plaza decor (keeps props apart)

----------------------------------------------------------------------
-- Small math helpers
----------------------------------------------------------------------

local function polar(angleDeg, radius, y)
	local a = math.rad(angleDeg)
	return Vector3.new(OX + math.cos(a) * radius, y or TOP, OZ + math.sin(a) * radius)
end

local function dirOf(angleDeg)
	local a = math.rad(angleDeg)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- CFrame at `pos` looking (flat) at `target`.
local function flatLook(pos, target)
	local d = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	if d.Magnitude < 1e-3 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + d.Unit)
end

local function faceCentre(pos)
	return flatLook(pos, Vector3.new(OX, pos.Y, OZ))
end

local function angleDiff(a, b)
	local d = math.abs((a - b) % 360)
	if d > 180 then
		d = 360 - d
	end
	return d
end

local function nearAny(angle, list, half)
	for _, other in ipairs(list or {}) do
		if angleDiff(angle, other) < half then
			return true
		end
	end
	return false
end

-- angle inside [from, to] (degrees, from may be negative)
local function angleIn(angle, from, to)
	local a = (angle - from) % 360
	return a <= (to - from)
end

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

-- Deterministic hash of integers -> [0, 1). The squared term makes hashes with different seeds independent.
local function hash3(x, y, z, seed)
	local h = (x * 73856093 + y * 19349663 + z * 83492791 + seed * 2654435761) % 2147483647
	h = (h * 16807) % 2147483647
	local a = h % 65521
	a = (a * a + seed * 7919 + 12345) % 65521
	h = ((h + a * 32771) * 16807) % 2147483647
	return h / 2147483647
end

-- Smooth 2D value noise in 0..1 (deterministic).
local function vnoise(x, z, scale, seed)
	local fx, fz = x / scale, z / scale
	local x0, z0 = math.floor(fx), math.floor(fz)
	local tx, tz = fx - x0, fz - z0
	tx = tx * tx * (3 - 2 * tx)
	tz = tz * tz * (3 - 2 * tz)
	local a, b = hash3(x0, 0, z0, seed), hash3(x0 + 1, 0, z0, seed)
	local c, d = hash3(x0, 0, z0 + 1, seed), hash3(x0 + 1, 0, z0 + 1, seed)
	local ab = a + (b - a) * tx
	local cd = c + (d - c) * tx
	return ab + (cd - ab) * tz
end

----------------------------------------------------------------------
-- Instance helpers
----------------------------------------------------------------------

local function newFolder(parent, name)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function newModel(parent, name)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- One anchored block. opts: Collide (default false), Material, Transparency, Shadow, Reflectance.
local function box(parent, name, cf, size, color, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	-- the P4 look: SmoothPlastic unless the caller (or the colour: lamps, water) says Neon / Glass
	p.Material = opts.Material or MAT_BY_COLOR[colorKey(color)] or MAT.SmoothPlastic
	p.Transparency = opts.Transparency or 0
	if opts.Reflectance then
		p.Reflectance = opts.Reflectance
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = opts.Collide == true
	p.CanQuery = opts.Collide == true or opts.Query == true
	p.CanTouch = false
	if opts.Shadow ~= nil then
		p.CastShadow = opts.Shadow == true
	else
		p.CastShadow = math.max(size.X, size.Y, size.Z) >= 4
	end
	p.Parent = parent
	return p
end

-- Invisible part used to host emitters / billboards / lights.
local function anchorPart(parent, name, pos, size)
	local p = box(parent, name, CFrame.new(pos), size or Vector3.new(1, 1, 1), C.Cloud, { Transparency = 1, Shadow = false })
	return p
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

-- Sparkle ParticleEmitter with soft defaults; `props` overrides anything.
local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLES
	e.Color = ColorSequence.new(C.TextGold)
	e.LightEmission = 0.6
	e.LightInfluence = 0
	e.Rate = 6
	e.Lifetime = NumberRange.new(1.5, 2.5)
	e.Speed = NumberRange.new(1, 2)
	e.Size = popSize(0.7)
	e.Transparency = FADE_IN_OUT
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	if props then
		for key, value in pairs(props) do
			e[key] = value
		end
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

----------------------------------------------------------------------
-- GUI helpers (all text goes through Theme font roles)
----------------------------------------------------------------------
-- World text rule (ARCHITECTURE_V3.md, added after the playtest "letters too small"):
--   * Tags above things are PIXEL-sized BillboardGuis (offset UDim2), so their text keeps one on-screen size at
--     any distance: names >= 22 px and info lines >= 18 px at 1080p, outlined glyphs on a compact solid plate
--     that sizes itself to its text, LightInfluence 0 and a MaxDistance of ~60-120 studs.
--   * Signs on surfaces are SurfaceGuis at SIGN_PPS pixels per stud with FIXED text sizes: titles >= 1 stud,
--     info lines >= 0.6 stud.
--   * Never TextScaled in the world: the engine drew the auto-scaled world text tiny in the playtest.

local INK = (Theme.Colors and Theme.Colors.TextStroke) or C.Ink
local TAG_NAME = 28 -- px: the name / title of a tag
local TAG_INFO = 20 -- px: info lines of a tag
local TAG_SMALL = 18 -- px: badges and pills (the info-line minimum)
local TAG_RANGE = 110 -- studs: MaxDistance of an ordinary tag
local SIGN_PPS = 50 -- pixels per stud on every surface sign
local SIGN_TITLE = 56 -- px at SIGN_PPS = 1.12 studs
local SIGN_INFO = 30 -- px at SIGN_PPS = 0.6 stud

-- Pixel-sized tag on `adornee`. The `w` x `h` container is transparent (the plate inside sizes itself to its
-- text); SizeOffset puts the container's BOTTOM edge on the adornee, raised `lift` studs in world space, so the
-- tag grows upwards and never sinks into what it labels, whatever the camera distance.
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

local function listLayout(parent, direction, gap, hAlign)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap or 0)
	layout.Parent = parent
	return layout
end

local function padding(parent, top, left, bottom, right)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top)
	pad.PaddingLeft = UDim.new(0, left)
	pad.PaddingBottom = UDim.new(0, bottom or top)
	pad.PaddingRight = UDim.new(0, right or left)
	pad.Parent = parent
	return pad
end

local function rounded(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = (type(radius) == "number") and UDim.new(0, radius) or radius
	corner.Parent = parent
	return corner
end

local function outline(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function vgradient(parent, top, bottom)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
	return g
end

local function plainFrame(parent, name, props)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	if props then
		for key, value in pairs(props) do
			f[key] = value
		end
	end
	f.Parent = parent
	return f
end

-- The compact solid plate of a tag in the HUD card look (navy gradient, rounded, a thick outline in `edge`),
-- sized to its content and standing on the bottom centre of the tag; its children are laid out by a list.
local function tagPlate(gui, edge, minW, direction, gap)
	local plate = plainFrame(gui, "Plate", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(minW or 0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), -- the gradient supplies the colour
		BackgroundTransparency = 0.04,
	})
	rounded(plate, 16)
	outline(plate, edge or C.TextGold, 3.5)
	vgradient(plate, (Theme.Colors and Theme.Colors.PanelLight) or C.Violet, (Theme.Colors and Theme.Colors.Panel) or C.Navy)
	padding(plate, 7, 16, 9)
	listLayout(plate, direction, gap or 2)
	return plate
end

-- Fixed-size outlined text that sizes itself to its text (tags, pills, list layouts).
local function tagText(parent, name, text, role, size, color, order, thickness)
	local label = Theme.Label(text, role, {
		Size = size,
		Color = color or C.Text,
		Stroke = 1, -- the glyph outline below replaces the classic text stroke
		Outline = thickness or 2.5,
		OutlineColor = INK,
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

-- A rounded colour pill around one short text (status, price, rarity). Returns pill, label.
local function tagPill(parent, name, text, role, size, fill, order)
	local pill = plainFrame(parent, name, {
		Size = UDim2.fromOffset(0, size + 8),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = fill,
		BackgroundTransparency = 0,
		LayoutOrder = order or 0,
	})
	rounded(pill, math.floor(size * 0.55))
	outline(pill, INK, 2.5)
	padding(pill, 2, math.floor(size * 0.5), 3)
	local label = tagText(pill, name .. "Label", text, role, size, C.Text, 1, 2)
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
	return gui
end

-- Navy -> violet rounded panel with a soft golden outline, filling the whole SurfaceGui.
local function signPanel(gui, strokeColor)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(1, 0, 1, 0)
	panel.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- UIGradient multiplies this
	panel.BorderSizePixel = 0
	vgradient(panel, C.PanelTop, C.PanelBottom)
	rounded(panel, 24)
	outline(panel, strokeColor or C.TextGold, 6, 0.2)
	panel.Parent = gui
	return panel
end

-- Sign text with a FIXED size (px at SIGN_PPS), placed with fractions of its parent (x, y, w, h).
local function signText(parent, text, role, size, color, name, x, y, w, h, align, wrap)
	local label = Theme.Label(text, role, {
		Size = size,
		Color = color,
		Stroke = 1,
		Outline = math.max(2, math.floor(size / 16 + 0.5)),
		OutlineColor = INK,
		Props = {
			Name = name,
			Position = UDim2.new(x, 0, y, 0),
			Size = UDim2.new(w, 0, h, 0),
			TextWrapped = wrap == true,
			TextXAlignment = align or Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		},
	})
	label.Parent = parent
	return label
end

local function textGradient(label, keypoints, rotation)
	local seq = {}
	for _, kp in ipairs(keypoints) do
		seq[#seq + 1] = ColorSequenceKeypoint.new(kp[1], kp[2])
	end
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(seq)
	g.Rotation = rotation or 0
	g.Parent = label
	return g
end

local function hex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

-- "50 <cloud>" / "5,000 <cloud>"
local function priceText(price)
	return Util.Commas(price) .. " " .. GLYPH.Cloud
end

-- Rich-text star row: `filled` gold stars then dim hollow ones up to `total`.
local function starRow(filled, total)
	local out = string.format('<font color="%s">%s</font>', hex(C.TextGold), string.rep(GLYPH.StarFull, filled))
	if total > filled then
		out = out .. string.format('<font color="%s">%s</font>', hex(C.StarOff), string.rep(GLYPH.StarEmpty, total - filled))
	end
	return out
end

-- A key-cap chip + a description: one row of a notice board (fractions of the 550 x 400 px board canvas).
local function keyRow(parent, y, rowH, keyText, descText)
	local chip = Instance.new("Frame")
	chip.Name = "KeyChip"
	chip.Size = UDim2.new(0.27, 0, rowH, 0)
	chip.Position = UDim2.new(0.04, 0, y, 0)
	chip.BackgroundColor3 = rgb(58, 66, 100)
	chip.BorderSizePixel = 0
	rounded(chip, 12)
	outline(chip, C.TextGold, 2.5, 0.25)
	chip.Parent = parent
	signText(chip, keyText, "Heading", SIGN_INFO, C.TextGold, "Key", 0, 0, 1, 1)
	signText(parent, descText, "Body", SIGN_INFO, C.Text, "Desc", 0.335, y, 0.64, rowH, Enum.TextXAlignment.Left)
end

----------------------------------------------------------------------
-- Voxel helpers
----------------------------------------------------------------------

local VX = {}

-- Vertical cylinder of voxels (voxel units). keep = only fill empty voxels.
function VX.Disc(g, cx, cz, r, y0, y1, key, keep)
	local ri = math.ceil(r) + 1
	local r2 = r * r
	for y = y0, y1 do
		for x = math.floor(cx) - ri, math.ceil(cx) + ri do
			for z = math.floor(cz) - ri, math.ceil(cz) + ri do
				local dx, dz = x - cx, z - cz
				if dx * dx + dz * dz <= r2 and (not keep or Voxel.Get(g, x, y, z) == nil) then
					Voxel.Set(g, x, y, z, key)
				end
			end
		end
	end
end

function VX.Ring(g, cx, cz, r0, r1, y0, y1, key)
	local ri = math.ceil(r1) + 1
	for y = y0, y1 do
		for x = math.floor(cx) - ri, math.ceil(cx) + ri do
			for z = math.floor(cz) - ri, math.ceil(cz) + ri do
				local dx, dz = x - cx, z - cz
				local d = math.sqrt(dx * dx + dz * dz)
				if d >= r0 and d <= r1 then
					Voxel.Set(g, x, y, z, key)
				end
			end
		end
	end
end

-- Inclusive integer box of voxels.
function VX.Fill(g, x0, x1, y0, y1, z0, z1, key)
	for y = y0, y1 do
		for x = x0, x1 do
			for z = z0, z1 do
				Voxel.Set(g, x, y, z, key)
			end
		end
	end
end

-- Rounded rectangle prism centred on (cx, cz): sx by sz voxels, corner radius `round`.
function VX.RoundRect(g, cx, cz, sx, sz, round, y0, y1, key, keep)
	local hx, hz = sx / 2, sz / 2
	round = math.max(0, math.min(round, hx, hz))
	for y = y0, y1 do
		for x = math.floor(cx - hx) - 1, math.ceil(cx + hx) + 1 do
			for z = math.floor(cz - hz) - 1, math.ceil(cz + hz) + 1 do
				local qx, qz = math.abs(x - cx) - (hx - round), math.abs(z - cz) - (hz - round)
				local ox, oz = math.max(qx, 0), math.max(qz, 0)
				local d = math.sqrt(ox * ox + oz * oz) + math.min(math.max(qx, qz), 0)
				if d <= round and (not keep or Voxel.Get(g, x, y, z) == nil) then
					Voxel.Set(g, x, y, z, key)
				end
			end
		end
	end
end

-- Moves every voxel whose base key is in `keys` into a new grid (for split collision / materials).
function VX.Split(g, keys)
	local out = Voxel.NewGrid(g.Resolution)
	local move = {}
	for k, v in pairs(g.Cells) do
		if keys[Voxel.BaseKey(v)] or keys[v] then
			move[#move + 1] = k
		end
	end
	for _, k in ipairs(move) do
		out.Cells[k] = g.Cells[k]
		out.Count = out.Count + 1
		g.Cells[k] = nil
		g.Count = g.Count - 1
	end
	return out
end

-- Voxel.Build with the lobby defaults. o: V (voxel size), Name, CF (where voxel 0,0,0 sits), Parent,
-- Collide, MaxParts, Keep, Shadow, Pal.
function VX.Build(g, o)
	if not g or g.Count == 0 then
		return nil
	end
	local model = Voxel.Build(g, {
		VoxelSize = o.V or 1,
		Palette = o.Pal or P,
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

----------------------------------------------------------------------
-- Phase 6 (ARCHITECTURE_V3.md "## Phase 6" A7, owner art-lobby): Blender mesh dressing. Every Part build in this
-- file stays exactly as it is (the fallback, the colliders, every name / prompt / zone / sign); the static decoration
-- subtrees are tagged with MeshLibrary.Tag(target, key, look, keep) and clients Dress them (Parts hidden locally, the
-- mesh placed at the target's pivot * ML_Offset = `origin`). Keys: blender/catalog/lobby.json. A key is tagged only
-- once it has an uploaded id (MeshLibrary.Status ~= "missing"): with the shipped empty MeshIds nothing changes.
-- Keys baked from this file's own layout (clouds, floors, the altar) carry a "LayoutSig" attachment in their manifest
-- (part count + position / size sums of the Part build, relative to `origin`): they are tagged only while the live
-- build still matches it, so a Config change can never show a stale mesh.
----------------------------------------------------------------------
local Mesh = {
	Lib = nil,
	-- template name -> mesh key (place() tags every clone)
	Templates = {
		TreeRound = "prop_tree_round",
		TreeBlossom = "prop_tree_blossom",
		TreePine = "prop_tree_pine",
		Lamp = "prop_lamp",
		Bench = "prop_bench",
		PuffS = "cloud_puff_s",
		PuffM = "cloud_puff_m",
		SkyBig = "cloud_sky_big",
		SkySmall = "cloud_sky_small",
		Plot = "prop_plot",
	},
	-- parts that stay visible over the mesh (live per-plot colour, signs)
	Keep = {
		Plot = { "PodiumBase", "Accent", "PodiumTop" },
	},
	Names = {}, -- template model -> template name
	-- the part names of a dressed cloud puff (Voxel cloud keys + the cloud mesh's parts): kept by the bridge that
	-- carries one, so the two dresses never hide each other
	CloudParts = { "Cloud", "CloudLight", "CloudShade", "Mist", "MistDark", "Puff" },
	Template = nil, -- the template being built (VX.CloudModel records it for the kit)
}

function Mesh.lib()
	if Mesh.Lib == nil then
		Mesh.Lib = false
		local module = Shared:FindFirstChild("MeshLibrary")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" and type(result.Tag) == "function" then
				Mesh.Lib = result
			end
		end
	end
	return Mesh.Lib or nil
end

-- part count + weighted sums of every visible BasePart's position / size in `origin` space (the kit computes the
-- same numbers from the same build: blender/kit/props/lobby_world.py)
function Mesh.Signature(target, origin)
	local inv = origin:Inverse()
	local n, a, b = 0, 0, 0
	local list = target:GetDescendants()
	list[#list + 1] = target
	for _, d in ipairs(list) do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local p = inv * d.Position
			local s = d.Size
			n = n + 1
			a = a + p.X + p.Y * 0.37 + p.Z * 0.61
			b = b + s.X + s.Y * 1.3 + s.Z * 1.7
		end
	end
	return n, a, b
end

local function meshSigOk(ML, key, target, origin)
	local man = type(ML.Manifest) == "function" and ML.Manifest(key)
	local att = man and man.Attachments and man.Attachments.LayoutSig
	if not att then
		return true -- a designed prop: no layout to match
	end
	local pos = att.Pos or att.pos
	if type(pos) ~= "table" then
		return false
	end
	local n, a, b = Mesh.Signature(target, origin)
	local tol = 0.05 + n * 1e-4
	return n == pos[1] and math.abs(a - pos[2]) <= tol and math.abs(b - pos[3]) <= tol
end

-- target: Model / Part subtree; key: mesh key; origin: world CFrame of the mesh pivot; look: { Primary, Secondary };
-- keep: part names that stay visible. Returns true when tagged.
function Mesh.tag(target, key, origin, look, keep)
	if typeof(target) ~= "Instance" or typeof(origin) ~= "CFrame" then
		return false
	end
	local kit = LobbyBuilder._Kit
	if type(kit) == "table" and type(kit.Targets) == "table" then
		kit.Targets[#kit.Targets + 1] = { Key = key, Target = target, Origin = origin, Look = look, Keep = keep }
	end
	local ML = Mesh.lib()
	if not ML or type(ML.Status) ~= "function" then
		return false
	end
	local okStatus, st = pcall(ML.Status, key)
	if not okStatus or st == "missing" or not meshSigOk(ML, key, target, origin) then
		return false
	end
	local tagLook = {}
	for k, v in pairs(look or {}) do
		tagLook[k] = v
	end
	tagLook.Offset = target:GetPivot():Inverse() * origin
	ML.Tag(target, key, tagLook, keep)
	return true
end

-- Clones a template (built at the origin) to `cf`; returns the clone.
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
	if not m.PrimaryPart and m:IsA("Model") then
		m.WorldPivot = cf -- the clone's pivot = where it was placed (TutorialController reads Plot:GetPivot())
	end
	if name then
		m.Name = name
	end
	m.Parent = parent
	local tname = Mesh.Names[tpl]
	local key = tname and (Mesh.Templates[tname] or (tname:match("^FlowerBed") and "prop_flowerbed"))
	if key then
		local look = nil
		local v = tonumber(tname:match("^FlowerBed(%d+)"))
		if v then -- the bed's two flower colours (Props.FlowerBed)
			look = { Primary = FLOWERS[v], Secondary = FLOWERS[v % #FLOWERS + 1] }
		end
		Mesh.tag(m, key, cf, look, Mesh.Keep[tname])
	end
	return m
end

local function template(name, make)
	local t = templates[name]
	if t == nil then
		local outer = Mesh.Template
		Mesh.Template = name
		local ok, result = pcall(make)
		Mesh.Template = outer
		if ok and result then
			t = result
			Mesh.Names[t] = name
		else
			warn("[LobbyBuilder] template " .. name .. " failed: " .. tostring(result))
			t = false
		end
		templates[name] = t
	end
	return t or nil
end

-- One flat layer of ground cells (a one-voxel-thick grid) whose top face sits at topY. fn(x, z) -> key | nil
-- gets the cell centre in studs relative to `centre`. Layers that overlap are offset in height (no z-fight).
local function groundLayer(parent, name, centre, radius, topY, cell, fn, maxParts)
	local g = Voxel.NewGrid(1)
	local n = math.ceil(radius / cell)
	for i = -n, n do
		for k = -n, n do
			local key = fn(i * cell, k * cell)
			if key then
				Voxel.Set(g, i, 0, k, key)
			end
		end
	end
	return VX.Build(g, {
		V = cell,
		Name = name,
		CF = CFrame.new(centre.X, topY - cell / 2, centre.Z),
		Collide = true,
		Shadow = false,
		Parent = parent,
		MaxParts = maxParts,
	})
end

-- A tiered voxel cloud body (tops at y = 0, V studs per voxel). spec:
--   Tiers = { { R = studs | SX =, SZ =, Round = studs, H = levels }, ... } from the top tier down
--   Puffs = { { x, y, z, rx, ry, rz } (studs, relative to the top centre) } soft bulges (shaded)
--   Rim = { same } puffs that rise above the walking surface; Carve = fn(x, y, z) -> remove voxel?
function VX.Cloud(spec)
	local V = spec.V or 3
	local g = Voxel.NewGrid(16)
	local y = 0
	for i, t in ipairs(spec.Tiers) do
		local key = t.Key or TIER_KEYS[math.min(i, #TIER_KEYS)]
		local h = t.H or 1
		if t.R then
			VX.Disc(g, 0, 0, t.R / V, y - h + 1, y, key)
		else
			VX.RoundRect(g, (t.X or 0) / V, (t.Z or 0) / V, t.SX / V, t.SZ / V, (t.Round or 6) / V, y - h + 1, y, key)
		end
		y = y - h
	end
	for _, p in ipairs(spec.Puffs or {}) do
		Voxel.Shape(g, { Kind = "Ellipsoid", Center = { p[1] / V, p[2] / V, p[3] / V }, Radius = { p[4] / V, p[5] / V, p[6] / V }, Key = "Puff", KeepExisting = true })
	end
	for _, p in ipairs(spec.Rim or {}) do
		Voxel.Shape(g, { Kind = "Ellipsoid", Center = { p[1] / V, p[2] / V, p[3] / V }, Radius = { p[4] / V, p[5] / V, p[6] / V }, Key = "Rim", KeepExisting = true })
	end
	if spec.Carve then
		local remove = {}
		for k in pairs(g.Cells) do
			local x, yy, z = Voxel.Unpack(k)
			if spec.Carve(x * V, yy * V, z * V) then
				remove[#remove + 1] = k
			end
		end
		for _, k in ipairs(remove) do
			g.Cells[k] = nil
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

-- Builds a cloud spec at a CFrame whose position is the top centre of the cloud.
function VX.CloudModel(spec, cf, parent, name, collide)
	local V = spec.V or 3
	local g = VX.Cloud(spec)
	local model = VX.Build(g, {
		V = V,
		Name = name or "Cloud",
		CF = cf * CFrame.new(0, -V / 2, 0),
		Collide = collide,
		MaxParts = spec.MaxParts,
		Parent = parent,
	})
	if model then
		CollectionService:AddTag(model, EXEMPT_TAG) -- the voxel clouds keep their look on purpose (6.4 rule 9)
		local kit = LobbyBuilder._Kit
		if type(kit) == "table" and type(kit.Clouds) == "table" then -- Phase 6 kit hook (blender/kit/props/lobby_world.py)
			kit.Clouds[model] = { Spec = spec, CF = cf, Template = Mesh.Template, Name = name }
		end
	end
	return model
end

----------------------------------------------------------------------
-- Prop templates (sculpted once, cloned everywhere)
----------------------------------------------------------------------

local Props = {}

-- Detailed voxel trees (~18 studs, ~1.1-stud voxels). kind: "Round" (green, red fruit), "Blossom" (pink), "Pine".
-- Shapes are written in 1.4-stud units and scaled by S, so the voxels get finer without the tree changing size.
function Props.Tree(kind)
	return template("Tree" .. kind, function()
		local S = 1.3
		local function v(x, y, z)
			return { x * S, y * S, z * S }
		end
		local g = Voxel.NewGrid(16)
		local leaf = (kind == "Blossom") and "Blossom" or ((kind == "Pine") and "Pine" or "Leaf")
		-- trunk with a slight bend, flared roots and two branch stubs into the canopy
		Voxel.Shape(g, { Kind = "Curve", Points = { v(0, 0, 0), v(0.3, 2.4, 0), v(-0.2, 4.6, 0.2), v(0, 6.4, 0) }, Radius = 1.05 * S, RadiusB = 0.6 * S, Key = "Bark" })
		Voxel.Shape(g, { Kind = "Capsule", A = v(0, 0.3, 0), B = v(1.5, 0, 0.5), Radius = 0.55 * S, RadiusB = 0.25 * S, Key = "Bark" })
		Voxel.Shape(g, { Kind = "Capsule", A = v(0, 0.3, 0), B = v(-1.1, 0, -1.1), Radius = 0.55 * S, RadiusB = 0.25 * S, Key = "Bark" })
		Voxel.Shape(g, { Kind = "Capsule", A = v(0, 0.3, 0), B = v(-0.4, 0, 1.4), Radius = 0.5 * S, RadiusB = 0.25 * S, Key = "Bark" })
		if kind == "Pine" then
			-- three stacked, shrinking cone tiers
			Voxel.Shape(g, { Kind = "Cone", A = v(0, 3.2, 0), B = v(0, 8.6, 0), Radius = 4.6 * S, RadiusB = 1.2 * S, Key = leaf })
			Voxel.Shape(g, { Kind = "Cone", A = v(0, 6.6, 0), B = v(0, 11.4, 0), Radius = 3.7 * S, RadiusB = 0.8 * S, Key = leaf })
			Voxel.Shape(g, { Kind = "Cone", A = v(0, 9.6, 0), B = v(0, 14.2, 0), Radius = 2.6 * S, RadiusB = 0, Key = leaf })
		else
			Voxel.Shape(g, { Kind = "Curve", Points = { v(0, 5.4, 0), v(1.8, 7, 0.6) }, Radius = 0.45 * S, Key = "Bark" })
			Voxel.Shape(g, { Kind = "Curve", Points = { v(0, 5.8, 0), v(-1.6, 7.2, -0.8) }, Radius = 0.45 * S, Key = "Bark" })
			Voxel.Shape(g, { Kind = "Ellipsoid", Center = v(0, 8.3, 0), Radius = { 3.8 * S, 3.0 * S, 3.8 * S }, Key = leaf })
			Voxel.Shape(g, { Kind = "Ellipsoid", Center = v(2.3, 7.1, 1.1), Radius = { 2.4 * S, 2.1 * S, 2.4 * S }, Key = leaf })
			Voxel.Shape(g, { Kind = "Ellipsoid", Center = v(-2.1, 7.3, -1.4), Radius = { 2.5 * S, 2.1 * S, 2.5 * S }, Key = leaf })
			Voxel.Shape(g, { Kind = "Ellipsoid", Center = v(-0.8, 7.0, 2.3), Radius = { 2.2 * S, 2.0 * S, 2.2 * S }, Key = leaf })
			Voxel.Shape(g, { Kind = "Ellipsoid", Center = v(0.4, 10.6, -0.4), Radius = { 2.3 * S, 1.8 * S, 2.3 * S }, Key = leaf })
		end
		Voxel.Shade(g, { Smooth = 2, Noise = 0.05, Seed = 7 })
		local accent, onlyKey, chance = nil, nil, 0
		if kind == "Blossom" then
			accent, onlyKey, chance = "BlossomWhite", "Blossom_Light", 0.18 -- pale petals on the lit side
		elseif kind == "Round" then
			accent, onlyKey, chance = "Flower5", "Leaf", 0.05 -- small red fruit
		end
		if accent then
			Voxel.Shape(g, {
				Kind = "Ellipsoid",
				Center = v(0, 8.3, 0),
				Radius = { 5 * S, 4.5 * S, 5 * S },
				Op = "Paint",
				OnlyKeys = { [onlyKey] = true },
				Pattern = function(x, y, z)
					if hash3(x, y, z, 5) < chance then
						return accent
					end
					return false
				end,
			})
		end
		local V = 1.4 / S
		return VX.Build(g, { V = V, Name = kind .. "Tree", CF = CFrame.new(0, V / 2, 0), Collide = true, MaxParts = 54 })
	end)
end

-- Lamp post (~9 studs) with a warm neon lantern. Built from crafted blocks.
function Props.Lamp()
	return template("Lamp", function()
		local m = Instance.new("Model")
		m.Name = "Lamp"
		-- plinth + body + cap (6.4 rule 3): a Slate foot with a Marble band, an iron post, a glass lantern
		box(m, "LampBase", CFrame.new(0, 0.6, 0), Vector3.new(1.8, 1.2, 1.8), C.Slate, { Collide = true })
		box(m, "LampBand", CFrame.new(0, 1.3, 0), Vector3.new(2, 0.2, 2), C.MarbleShade)
		box(m, "LampPole", CFrame.new(0, 4.6, 0), Vector3.new(0.5, 6.6, 0.5), C.Iron, { Collide = true })
		box(m, "LampCollar", CFrame.new(0, 8, 0), Vector3.new(1.2, 0.3, 1.2), C.IronLight)
		box(m, "LampCage", CFrame.new(0, 8.85, 0), Vector3.new(1.3, 1.4, 1.3), C.Lamp, { Material = materialOf("Glass"), Transparency = 0.45 })
		box(m, "LampGlass", CFrame.new(0, 8.85, 0), Vector3.new(0.7, 1.0, 0.7), C.Lamp, { Material = MAT.Neon })
		box(m, "LampRoof", CFrame.new(0, 9.75, 0), Vector3.new(1.8, 0.4, 1.8), C.Iron)
		box(m, "LampTip", CFrame.new(0, 10.15, 0), Vector3.new(0.5, 0.4, 0.5), C.GoldDark)
		return m
	end)
end

-- bug batch 2 #7 (the player: "benches should be sittable, when a player sits on them the pets sit on the ground"):
-- every bench carries invisible Seats that stay Disabled (running past still never sits you down) with a "Sit" prompt
-- (E). The server checks the press (Benches.sit: alive, not in a battle / dungeon run / match, near, the seat free,
-- the player not seated already, a 0.5 s cooldown), enables that seat for the sit and seats the player; when the
-- occupant leaves (jump, death, leaving) the seat goes back to Disabled and its prompt shows again. While a seat is
-- taken a 4 Hz watchdog frees it if a teleport dragged it (or its occupant) away and puts it back home.
local Benches = {
	SEAT = "BenchSeat",
	PROMPT = "BenchSitPrompt",
	RANGE = 7, -- the prompt's MaxActivationDistance ...
	SLACK = 3, -- ... + this much on the server (lag)
	COOLDOWN = 0.5,
	DRIFT = 4, -- studs a taken seat or its occupant may stray from the seat's home before the watchdog frees it
	lastUse = {}, -- [Player] = os.clock() of the last accepted sit
	homes = {}, -- [Seat] = its CFrame as built
	watched = {}, -- [Seat] = true while its watchdog runs
	hooked = false,
}

-- one Seat (+ prompt) per 2.2 studs of bench (a seated player is ~2 studs wide): the bench seats two
function Benches.addSeats(m, length, seatY, seatZ)
	local n = math.max(1, math.floor(length / 2.2 + 1e-6))
	for i = 1, n do
		local seat = Instance.new("Seat")
		seat.Name = Benches.SEAT
		seat.Anchored = true
		seat.Size = Vector3.new(2, 0.4, 1.8)
		seat.CFrame = CFrame.new(-length / 2 + (i - 0.5) * length / n, seatY, seatZ) -- faces -Z like the bench
		seat.Transparency = 1
		seat.CanCollide = false
		seat.CanQuery = false
		seat.CastShadow = false
		seat.Disabled = true
		seat.Parent = m
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = Benches.PROMPT
		prompt.ActionText = "Sit"
		prompt.ObjectText = "Bench"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Benches.RANGE
		prompt.RequiresLineOfSight = false
		prompt.Parent = seat
	end
end

-- Sit `player` on `seat` (the prompt's handler; tests call it). -> ok, reason
function Benches.sit(player, seat)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false, "junk"
	end
	if typeof(seat) ~= "Instance" or not seat:IsA("Seat") or seat.Name ~= Benches.SEAT or not seat:IsDescendantOf(Workspace) then
		return false, "junk"
	end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return false, "dead"
	end
	-- InBattle is also set for a whole dungeon run (Config.Attr.InBattle)
	local attr = Config.Attr or {}
	local battle = player:GetAttribute(attr.InBattle or "InBattle")
	if (battle ~= nil and battle ~= false) or player:GetAttribute(attr.InMatch or "InMatch") == true then
		return false, "busy"
	end
	if (root.Position - seat.Position).Magnitude > Benches.RANGE + Benches.SLACK then
		return false, "far"
	end
	if seat.Occupant ~= nil then
		return false, "taken"
	end
	if humanoid.Sit or humanoid.SeatPart ~= nil then
		return false, "seated"
	end
	local now = os.clock()
	local last = Benches.lastUse[player]
	if last and now - last < Benches.COOLDOWN then
		return false, "cooldown"
	end
	Benches.lastUse[player] = now
	seat.Disabled = false -- for this sit only: Benches.refresh disables it again once the seat is free
	local ok = pcall(seat.Sit, seat, humanoid)
	if ok and seat.Occupant == humanoid then
		Benches.refresh(seat)
		return true
	end
	-- the weld may land a frame later: give it a moment, then the seat is Disabled again unless someone sits
	task.delay(0.5, function()
		Benches.refresh(seat)
	end)
	return ok, ok and "pending" or "failed"
end

-- Disabled + prompt shown while free; prompt hidden (and the watchdog running) while taken
function Benches.refresh(seat)
	if seat.Parent == nil then
		return
	end
	local taken = seat.Occupant ~= nil
	seat.Disabled = not taken
	local prompt = seat:FindFirstChild(Benches.PROMPT)
	if prompt then
		prompt.Enabled = not taken
	end
	if taken and not Benches.watched[seat] then
		Benches.watched[seat] = true
		task.spawn(Benches.watch, seat)
	end
end

-- while the seat is taken: a teleport that moved the welded occupant (and with it the seat) frees the seat at home
function Benches.watch(seat)
	while seat.Parent and seat.Occupant ~= nil do
		Benches.check(seat)
		task.wait(0.25)
	end
	Benches.watched[seat] = nil
	if seat.Parent then
		Benches.refresh(seat)
	end
end

function Benches.check(seat)
	local home = Benches.homes[seat]
	local occupant = seat.Occupant
	local root = occupant and occupant.Parent and occupant.Parent:FindFirstChild("HumanoidRootPart")
	if not home then
		return
	end
	local strayed = (seat.Position - home.Position).Magnitude > Benches.DRIFT
		or (root and (root.Position - home.Position).Magnitude > Benches.DRIFT + 3)
	if not strayed then
		return
	end
	for _, d in ipairs(seat:GetChildren()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy() -- the SeatWeld: the occupant stays where the teleport put them
		end
	end
	if occupant and occupant.Parent then
		pcall(function()
			occupant.Sit = false
		end)
	end
	seat.CFrame = home
	Benches.refresh(seat)
end

-- after the build: every bench seat gets its prompt handler, its Occupant watcher and its home CFrame
function Benches.wire(root)
	for _, seat in ipairs(root:GetDescendants()) do
		if seat:IsA("Seat") and seat.Name == Benches.SEAT then
			Benches.homes[seat] = seat.CFrame
			local prompt = seat:FindFirstChild(Benches.PROMPT)
			if prompt then
				prompt.Triggered:Connect(function(player)
					local ok, err = pcall(Benches.sit, player, seat)
					if not ok then
						warn("[LobbyBuilder] bench sit: " .. tostring(err))
					end
				end)
			end
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				Benches.refresh(seat)
			end)
			seat.AncestryChanged:Connect(function()
				if not seat:IsDescendantOf(game) then
					Benches.homes[seat] = nil
				end
			end)
		end
	end
	if not Benches.hooked then
		Benches.hooked = true
		game:GetService("Players").PlayerRemoving:Connect(function(player)
			Benches.lastUse[player] = nil
		end)
	end
end

-- Wooden bench (plain parts) with two Disabled Seats + "Sit" prompts (bug batch 2 #7, Benches). Faces -Z.
function Props.Bench()
	return template("Bench", function()
		local m = Instance.new("Model")
		m.Name = "Bench"
		box(m, "Seat", CFrame.new(0, 1.55, -0.45), Vector3.new(5.6, 0.4, 1), C.PlankLight, { Collide = true })
		box(m, "Seat", CFrame.new(0, 1.55, 0.55), Vector3.new(5.6, 0.4, 1), C.Plank, { Collide = true })
		box(m, "Back", CFrame.new(0, 2.55, 1.05), Vector3.new(5.6, 0.7, 0.3), C.PlankLight)
		box(m, "Back", CFrame.new(0, 3.35, 1.05), Vector3.new(5.6, 0.7, 0.3), C.Plank)
		box(m, "Frame", CFrame.new(-2.4, 1.6, 0.25), Vector3.new(0.4, 3.2, 2.2), C.Iron, { Collide = true })
		box(m, "Frame", CFrame.new(2.4, 1.6, 0.25), Vector3.new(0.4, 3.2, 2.2), C.Iron, { Collide = true })
		-- the seats' tops sit on the planks' top (1.75); between the frames (inner width 4.4 -> 2 x 2.2)
		Benches.addSeats(m, 4.4, 1.55, 0.05)
		return m
	end)
end

-- Raised wooden flower bed (6 x 3) with leaves and flower pixels. variant picks the flower colours.
function Props.FlowerBed(variant)
	return template("FlowerBed" .. variant, function()
		local g = Voxel.NewGrid(4)
		for x = -3, 2 do
			for z = -2, 1 do
				local edge = x == -3 or x == 2 or z == -2 or z == 1
				Voxel.Set(g, x, 0, z, edge and "PlankDark" or "Soil")
				if not edge then
					local h = hash3(x, variant, z, 3)
					if h < 0.45 then
						Voxel.Set(g, x, 1, z, "Flower" .. (((variant + x + z) % 3 == 0) and variant or (variant % #FLOWERS + 1)))
					else
						Voxel.Set(g, x, 1, z, "Leaf")
					end
				end
			end
		end
		return VX.Build(g, { V = 1, Name = "FlowerBed", CF = CFrame.new(0.5, 0.5, 0.5), Collide = true, MaxParts = 16 })
	end)
end

-- A small voxel cloud puff (supports under bridges). size: "S" | "M".
function Props.Puff(size)
	return template("Puff" .. size, function()
		local s = (size == "M") and 1.35 or 1
		local spec = {
			V = 3,
			Tiers = { { R = 6 * s, H = 1 }, { R = 4.5 * s, H = 1 } },
			Puffs = {
				{ 5 * s, -1, 2 * s, 5 * s, 4 * s, 5 * s },
				{ -5 * s, -2, -1 * s, 5.5 * s, 4.5 * s, 5 * s },
				{ 0, -4, 0, 6 * s, 5 * s, 6 * s },
			},
			MaxParts = 12,
			Seed = 3,
		}
		return VX.CloudModel(spec, CFrame.new(), nil, "CloudPuff", false)
	end)
end

-- Bunting: a sagging rope with stepped voxel pennants in the given colours between two points.
local function bunting(parent, a, b, colors, sag)
	local m = newModel(parent, "Bunting")
	local span = b - a
	local len = span.Magnitude
	if len < 2 then
		return m
	end
	sag = sag or math.min(2, len * 0.06)
	local dir = span.Unit
	local count = math.max(2, math.floor(len / 4))
	local pieces = 3
	local knots = {}
	for i = 0, pieces do
		local t = i / pieces
		knots[i] = a + span * t - Vector3.new(0, sag * 4 * t * (1 - t), 0)
	end
	for i = 1, pieces do
		local p, prev = knots[i], knots[i - 1]
		local mid = (p + prev) * 0.5
		box(m, "Rope", CFrame.lookAt(mid, p), Vector3.new(0.18, 0.18, (p - prev).Magnitude + 0.1), C.PlankDark, { Shadow = false })
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(1, 0, 0)
	end
	for i = 1, count do
		-- on the straight rope piece (not the parabola through its knots), so every pennant hangs from it
		local t = (i - 0.5) / count
		local k = math.min(pieces - 1, math.floor(t * pieces))
		local p = knots[k]:Lerp(knots[k + 1], t * pieces - k)
		local color = colors[(i - 1) % #colors + 1]
		local cf = CFrame.lookAt(p, p + flat) * CFrame.Angles(0, math.rad(90), 0)
		box(m, "Pennant", cf * CFrame.new(0, -0.4, 0), Vector3.new(0.12, 0.8, 1.3), color, { Shadow = false })
		box(m, "Pennant", cf * CFrame.new(0, -1.05, 0), Vector3.new(0.12, 0.6, 0.6), color, { Shadow = false })
	end
	return m
end

-- Tall banner pole with a hanging cloth in `color` (and a gold finial). cf at ground level.
local function bannerPole(parent, cf, color)
	local m = newModel(parent, "Banner")
	box(m, "Pole", cf * CFrame.new(0, 5.5, 0), Vector3.new(0.5, 11, 0.5), C.Iron, { Collide = true })
	box(m, "Finial", cf * CFrame.new(0, 11.3, 0), Vector3.new(0.9, 0.7, 0.9), C.Gold)
	box(m, "Bar", cf * CFrame.new(0.9, 10.5, 0), Vector3.new(2.4, 0.3, 0.3), C.Iron)
	box(m, "Cloth", cf * CFrame.new(1.2, 8.2, 0), Vector3.new(2, 4.2, 0.15), color, { Shadow = false })
	box(m, "ClothTip", cf * CFrame.new(1.2, 5.75, 0), Vector3.new(1, 0.7, 0.15), color, { Shadow = false })
	Mesh.tag(m, "prop_banner", cf, { Primary = color }) -- Phase 6: the cloth takes `color`
	return m
end

-- A wooden notice board with a small roof; returns the face part for the SurfaceGui. cf: ground, faces -Z.
local function noticeBoard(parent, cf, width, height, name)
	local m = newModel(parent, name or "NoticeBoard")
	local postH = height + 3.4
	for _, s in ipairs({ -1, 1 }) do
		box(m, "Post", cf * CFrame.new(s * (width / 2 + 0.5), postH / 2, 0), Vector3.new(1, postH, 1), C.PlankDark, { Collide = true })
		box(m, "PostFoot", cf * CFrame.new(s * (width / 2 + 0.5), 0.4, 0), Vector3.new(1.6, 0.8, 1.6), C.StoneDark, { Collide = true })
	end
	box(m, "Frame", cf * CFrame.new(0, 2.4 + height / 2, 0.15), Vector3.new(width + 0.6, height + 0.6, 0.6), C.Plank, { Collide = true })
	local face = box(m, "Face", cf * CFrame.new(0, 2.4 + height / 2, -0.2), Vector3.new(width, height, 0.2), C.Navy)
	box(m, "Roof", cf * CFrame.new(0, postH + 0.25, 0), Vector3.new(width + 3, 0.5, 2.4), C.PlankDark)
	box(m, "RoofTop", cf * CFrame.new(0, postH + 0.75, 0), Vector3.new(width + 1.6, 0.5, 1.4), C.Rose)
	-- Phase 6: prop_board_s (11 x 8) / prop_board_l (14 x 9); the Face keeps its SurfaceGui and stays visible
	local boardKey = (width == 11 and height == 8) and "prop_board_s" or ((width == 14 and height == 9) and "prop_board_l" or nil)
	if boardKey then
		Mesh.tag(m, boardKey, cf, nil, { "Face" })
	end
	return face, m
end

----------------------------------------------------------------------
-- Layout (derived once from Config.Lobby / Config.Difficulties)
----------------------------------------------------------------------

local function computeLayout()
	local L = {}

	-- Phase 5 Gate Court (6.1): the gates left -> right on the arc r G.GateR around G.GateFacing (the spawn looks this
	-- way); Phase 6: the court keeps its six-slot width ((G.CourtSlots - 1) * G.GateStep) and the five gates spread
	-- evenly over it (the end gates stand on the old end slots, Ring in the middle); the sector reaches 5.75 degrees
	-- past the end gates.
	L.MidAngle = G.GateFacing
	L.GateAngles = {}
	L.GateOrder = {}
	local nGates = #GATE_SPECS
	local span = (G.CourtSlots - 1) * G.GateStep
	local step = nGates > 1 and span / (nGates - 1) or 0
	for i, spec in ipairs(GATE_SPECS) do
		local a = G.GateFacing + (i - (nGates + 1) / 2) * step
		L.GateAngles[spec.Id] = a
		L.GateOrder[i] = spec.Id
	end
	L.CourtFrom = G.GateFacing - span / 2 - 5.75
	L.CourtTo = G.GateFacing + span / 2 + 5.75

	-- Shop island.
	local off = LOBBY.ShopOffset or Vector3.new(0, 0, -150)
	L.ShopCenter = Vector3.new(OX + off.X, TOP, OZ + off.Z)
	L.ShopDist = math.max(1, math.sqrt(off.X * off.X + off.Z * off.Z))
	L.ShopAngle = math.deg(atan2(off.Z, off.X)) % 360
	L.ShopR = clamp(L.ShopDist - PLAZA_R - 4, 18, 34)
	L.FountainX = math.cos(math.rad(L.ShopAngle)) * G.FountainD
	L.FountainZ = math.sin(math.rad(L.ShopAngle)) * G.FountainD

	-- Home plots sit between the junctions of the ring street; spokes join every other junction (never through the
	-- Gate Court, whose terrace fills the plaza edge behind the gates, and never right beside the shop neck).
	L.PlotAngles = {}
	for i = 1, SPOT_COUNT do
		L.PlotAngles[i] = (i - 1) * G.Step + G.HalfStep
	end
	L.Junctions = {}
	L.SpokeAngles = {}
	for j = 0, SPOT_COUNT - 1 do
		local a = j * G.Step
		local info = { Angle = a, Index = j }
		L.Junctions[#L.Junctions + 1] = info
		if j % 2 == 1 and angleDiff(a, L.ShopAngle) > 14 and not angleIn(a, L.CourtFrom - 8, L.CourtTo + 8) then
			info.Spoke = true
			L.SpokeAngles[#L.SpokeAngles + 1] = a
		end
	end

	-- Gardens (and the reserved Storm Altar site) hang off even junctions inside the ring.
	local function pickEven(target)
		local best, bestD = nil, 1e9
		for _, info in ipairs(L.Junctions) do
			local d = angleDiff(info.Angle, target)
			if not info.Spoke and not info.Garden and not info.Altar and d < bestD and angleDiff(info.Angle, L.ShopAngle) > 30 then
				best, bestD = info, d
			end
		end
		return best
	end
	L.Gardens = {}
	local specs = {
		{ Target = L.MidAngle - 45, Name = "Blossom Garden", Kind = "Blossom" },
		{ Target = L.MidAngle + 45, Name = "Lily Pond", Kind = "Pond" },
	}
	for _, spec in ipairs(specs) do
		local j = pickEven(spec.Target)
		if j then
			j.Garden = true
			L.Gardens[#L.Gardens + 1] = { Angle = j.Angle, Name = spec.Name, Kind = spec.Kind }
		end
	end
	local altar = pickEven(L.ShopAngle + 45)
	if altar then
		altar.Altar = true
		L.AltarAngle = altar.Angle
	end

	-- Phase 3 / 5: the Battle Arena island floats beyond the homes; its bridge continues the spoke junction nearest
	-- 135 degrees straight through the street (the junction's outer rail opens for it). Portal_Arena in the Gate Court
	-- is the other way in (ArenaBuilder).
	local arenaTarget = L.CourtTo + 3
	local arenaJ, arenaD = nil, 1e9
	for _, info in ipairs(L.Junctions) do
		if info.Spoke and not info.Garden and not info.Altar and angleDiff(info.Angle, L.ShopAngle) > 30
			and (not L.AltarAngle or angleDiff(info.Angle, L.AltarAngle) > 30) then
			local d = angleDiff(info.Angle, arenaTarget)
			if d < arenaD then
				arenaJ, arenaD = info, d
			end
		end
	end
	if arenaJ then
		arenaJ.Arena = true
		L.ArenaAngle = arenaJ.Angle
	end

	-- Exits through the plaza's soft cloud rim: spokes and the shop boardwalk.
	L.RimGaps = {}
	for _, a in ipairs(L.SpokeAngles) do
		L.RimGaps[#L.RimGaps + 1] = a
	end
	L.RimGaps[#L.RimGaps + 1] = L.ShopAngle

	-- Plaza path segments (plaza-local studs): { ax, az, dx, dz, len, half, kind }.
	local segs = {}
	local function segAB(ax, az, bx, bz, half, kind)
		local dx, dz = bx - ax, bz - az
		local len = math.max(0.01, math.sqrt(dx * dx + dz * dz))
		segs[#segs + 1] = { ax = ax, az = az, dx = dx / len, dz = dz / len, len = len, half = half, kind = kind }
	end
	local function seg(angle, r0, r1, half, kind)
		local d = dirOf(angle)
		segAB(d.X * r0, d.Z * r0, d.X * r1, d.Z * r1, half, kind)
	end
	-- the grand avenue (spawn court -> Gate Court), the shop boardwalk, the east / west walks to the circle walk
	seg(L.MidAngle, G.CourtR - 1, G.CourtIn + 1, G.AvenueHalf, "Stone")
	seg(L.ShopAngle, G.CourtR - 1, PLAZA_R + 1, G.BoardHalf, "Plank")
	L.CrossAngles = { (L.MidAngle + 90) % 360, (L.MidAngle - 90) % 360 }
	for _, a in ipairs(L.CrossAngles) do
		seg(a, G.CourtR - 1, G.RingRoadR, G.PathHalf, "Stone")
	end
	-- every spoke leaves the circle walk
	for _, a in ipairs(L.SpokeAngles) do
		seg(a, G.RingRoadR - 2, PLAZA_R + 1, G.StubHalf, "Stone")
	end
	L.PlazaSegs = segs
	return L
end

----------------------------------------------------------------------
-- Plaza: ground (layered voxel tiles), cloud body, decor
----------------------------------------------------------------------

local BORDER_KEY = { Stone = "StoneEdge", Sand = "SandDark", Plank = "PlankDark" }

local function segDist(px, pz, s)
	local rx, rz = px - s.ax, pz - s.az
	local t = rx * s.dx + rz * s.dz
	if t < 0 or t > s.len then
		return math.huge, t
	end
	return math.abs(-rx * s.dz + rz * s.dx), t
end

-- Signed lateral distance (studs) of a plaza-local point inside the Gate Court sector: > 0 inside, the distance to
-- the nearer side edge (the rays at L.CourtFrom / L.CourtTo).
local function courtSide(x, z, L)
	local a0, a1 = math.rad(L.CourtFrom), math.rad(L.CourtTo)
	-- the left edge ray at a0: inside is counter-clockwise of it; the right edge ray at a1: inside is clockwise
	local d0 = math.cos(a0) * z - math.sin(a0) * x
	local d1 = math.sin(a1) * x - math.cos(a1) * z
	return math.min(d0, d1)
end

-- Keys of the plaza ground layers at a cell centre (plaza-local studs):
-- l1 lawn patches / flowers, l2 borders and the grout under the tiled courts (just below the surface), l3 surfaces
-- (cobbles, planks); the spawn court and the Gate Court get their Slate tiles from Court.Tiles on top of the grout.
local function plazaCell(x, z, L)
	local r = math.sqrt(x * x + z * z)
	if r > PLAZA_R - 0.5 then
		return nil
	end
	local l1, l2, l3
	local n = vnoise(x + 400, z + 400, 46, 11)
	if r > PLAZA_R - 3.5 then
		n = 0.5 -- lawn only at the very edge (no patch faces flush with the lawn's edge)
	end
	if n < 0.17 then
		l1 = "GrassDark"
	elseif n > 0.83 then
		l1 = "GrassLight"
	end
	-- spawn court (tiles on top) and the Gate Court sector (tiles, terrace)
	if r <= G.CourtR + 1 then
		l2 = "SlateDark"
	end
	local side = courtSide(x, z, L)
	if r >= G.CourtIn - 2 and r <= G.CourtOut + 1 and side >= -1.5 then
		l2 = "SlateDark"
	end
	-- (the cobbled circle walk is built from arc segments by Court.RingRoad; keep its band free of lawn patches)
	if math.abs(r - G.RingRoadR) <= G.PathHalf + 0.5 then
		l1 = nil
	end
	-- fountain roundabout
	local fx, fz = x - L.FountainX, z - L.FountainZ
	local fr = math.sqrt(fx * fx + fz * fz)
	if fr <= 16 then
		l2 = l2 or "StoneEdge"
		if fr <= 14 then
			l3 = l3 or "Stone"
		end
	end
	-- paths
	for _, s in ipairs(L.PlazaSegs) do
		local d, t = segDist(x, z, s)
		if d <= s.half then
			l2 = l2 or BORDER_KEY[s.kind]
			-- (the surface stops one cell before the island's edge, its border runs on: no two layers end flush)
			if d <= s.half - 2 and not l3 and l2 ~= "SlateDark" and r <= PLAZA_R - 2.5 then
				if s.kind == "Plank" then
					l3 = (math.floor(t / 4) % 2 == 0) and "Plank" or "PlankLight"
				else
					-- cobbles in two shades by large soft patches (+-6 RGB, rule 2)
					l3 = (vnoise(x + 1300, z + 1300, 9, 3) > 0.5) and "Stone" or "StoneLight"
				end
			end
		end
	end
	-- (bug #12: no flat "Flower" lawn pixels any more: the grass and wildflowers are 3D clumps the clients grow from
	-- the Meadow scatter, built after every prop has its place: see Meadow below.) The unmown outer lawns get a
	-- slightly deeper floor in soft drifts, so the gaps between the tufts read as meadow, not mown lawn.
	if not l1 and not l2 and not l3 and r > G.RingRoadR + G.PathHalf + 1.5 and r < PLAZA_R - 3.5
		and vnoise(x - 700, z + 300, 34, 29) > 0.28 then
		l1 = "GrassWild"
	end
	return l1, l2, l3
end

-- The spawn medallion (1-stud inlay cells, thinned to 0.3-stud inlays when built): a Metal sun, a Marble ring and six
-- Neon arrows in the gate colours, each pointing at its gate.
local function courtInlay(x, z, L)
	local r = math.sqrt(x * x + z * z)
	if r <= 3.6 then
		return "Gold"
	elseif r <= 4.8 then
		return "GoldDark"
	elseif r >= 15.4 and r <= 16.9 then
		return "Marble"
	end
	for i, id in ipairs(L.GateOrder) do
		local pa = L.GateAngles[id]
		local dx, dz = math.cos(math.rad(pa)), math.sin(math.rad(pa))
		local t = x * dx + z * dz
		local d = math.abs(-x * dz + z * dx)
		if t >= 18 and t <= 23 and d <= (23.4 - t) * 0.4 then
			return "Gate" .. i
		end
	end
	-- short sun rays
	if r >= 5.6 and r <= 7.6 then
		local a = (math.deg(atan2(z, x)) - L.MidAngle) % 45
		if a < 7 or a > 38 then
			return "GoldDark"
		end
	end
	return nil
end

local function plazaKind(x, z, L)
	local r = math.sqrt(x * x + z * z)
	if r > PLAZA_R - 6 then
		return "edge"
	end
	local _, l2, l3 = plazaCell(x, z, L)
	if l2 or l3 then
		return "path"
	end
	return "lawn"
end

-- Is a circle (plaza-local) free lawn, away from paths, the rim and other decor?
local function plazaFree(x, z, radius, L)
	for _, o in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } }) do
		if plazaKind(x + o[1] * radius, z + o[2] * radius, L) ~= "lawn" then
			return false
		end
	end
	for _, rsv in ipairs(reserved) do
		local dx, dz = x - rsv[1], z - rsv[2]
		local need = radius + rsv[3]
		if dx * dx + dz * dz < need * need then
			return false
		end
	end
	return true
end

local function reserve(x, z, radius)
	reserved[#reserved + 1] = { x, z, radius }
end

-- Places a prop on the plaza lawn when the spot is free; returns the world ground position or nil.
local function plazaSpot(angle, radius, clearance, L, force)
	local d = dirOf(angle)
	local x, z = d.X * radius, d.Z * radius
	if not force and not plazaFree(x, z, clearance, L) then
		warn(string.format("[LobbyBuilder] plaza decor skipped at %.0f deg r=%.0f (not free)", angle, radius))
		return nil
	end
	reserve(x, z, clearance)
	return Vector3.new(OX + x, TOP, OZ + z), x, z
end

local function buildPlazaGround(f, L)
	local cell = 2
	local n = math.ceil(PLAZA_R / cell)
	local grids = { Voxel.NewGrid(1), Voxel.NewGrid(1), Voxel.NewGrid(1), Voxel.NewGrid(1), Voxel.NewGrid(1) }
	local r2 = (PLAZA_R - 0.5) * (PLAZA_R - 0.5)
	for i = -n, n do
		for k = -n, n do
			local x, z = i * cell, k * cell
			if x * x + z * z <= r2 then
				Voxel.Set(grids[1], i, 0, k, "Grass")
				local l1, l2, l3 = plazaCell(x, z, L)
				if l1 then
					Voxel.Set(grids[2], i, 0, k, l1)
				end
				if l2 then
					Voxel.Set(grids[3], i, 0, k, l2)
				end
				if l3 then
					Voxel.Set(grids[4], i, 0, k, l3)
				end
			end
		end
	end
	-- the medallion uses finer 1-stud cells
	local inlay = grids[5]
	local ci = math.ceil(G.CourtR)
	for i = -ci, ci do
		for k = -ci, ci do
			local key = courtInlay(i, k, L)
			if key then
				Voxel.Set(inlay, i, 0, k, key)
			end
		end
	end
	-- top surfaces: lawn -0.4, patches -0.3, borders -0.1, paths 0, inlays +0.1 (walkable steps, no z-fight;
	-- bridge decks that dock into the ground sit at -0.2)
	local tops = { -0.4, -0.3, -0.1, 0, 0.1 }
	local names = { "Lawn", "LawnPatches", "PathBorders", "Paths", "Inlays" }
	for li = 1, 5 do
		local cellSize = (li == 5) and 1 or cell
		local model = VX.Build(grids[li], {
			V = cellSize,
			Name = names[li],
			CF = CFrame.new(OX, TOP + tops[li] - cellSize / 2, OZ),
			Collide = li ~= 5,
			Shadow = false,
			Parent = f,
		})
		if li == 5 and model then
			-- the medallion: 0.3-stud inlays (rule 2: saturated colours only as thin inlays) on top of the court tiles
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					local topY = p.Position.Y + p.Size.Y / 2
					p.Size = Vector3.new(p.Size.X, 0.3, p.Size.Z)
					p.CFrame = CFrame.new(p.Position.X, topY - 0.15, p.Position.Z)
					p.CanCollide = false
					p.CanQuery = false
				end
			end
		end
		if model then -- Phase 6: floor_plaza_<layer> (baked from this very build: LayoutSig)
			Mesh.tag(model, "floor_plaza_" .. string.lower(names[li]), CFrame.new(OX, TOP, OZ))
		end
	end
end

-- The plaza's cloud body: tiered, with lumpy side puffs and a soft rim of clouds around the lawn.
local function buildPlazaBody(f, L)
	local rng = Util.NewRng(SEED + 2)
	local R = PLAZA_R
	local puffs = {}
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2 + rng:Float(-0.2, 0.2)
		local tier = rng:Int(1, 2)
		local tr = ({ R - 8, R - 30 })[tier]
		local ty = ({ -7, -14 })[tier]
		local s = rng:Float(12, 17)
		puffs[#puffs + 1] = { math.cos(a) * tr, ty, math.sin(a) * tr, s, s * 0.7, s }
	end
	for i = 1, 3 do
		local a = rng:Float(0, math.pi * 2)
		local d = rng:Float(10, 40)
		puffs[#puffs + 1] = { math.cos(a) * d, -26, math.sin(a) * d, rng:Float(16, 24), rng:Float(8, 11), rng:Float(16, 24) }
	end
	-- the exits through the rim: unit direction + half width kept clear (path + border + a little air)
	local exits = {}
	for _, a in ipairs(L.RimGaps) do
		local d = dirOf(a)
		local half = ((angleDiff(a, L.ShopAngle) < 1) and G.BoardHalf or G.StubHalf) + 2.5
		exits[#exits + 1] = { d.X, d.Z, half }
	end
	-- rim puffs: one right beside every exit, the arcs between exits filled evenly (<= ~30 degrees apart)
	local rim = {}
	local gaps = {}
	for _, a in ipairs(L.RimGaps) do
		gaps[#gaps + 1] = a % 360
	end
	table.sort(gaps)
	local function addRim(adeg)
		local a = math.rad(adeg)
		local rr = R + rng:Float(-1, 1.5)
		local s = rng:Float(8.5, 11)
		rim[#rim + 1] = { math.cos(a) * rr, rng:Float(-1, 1.5), math.sin(a) * rr, s, s * 0.62, s }
	end
	if #gaps == 0 then
		gaps[1] = 0
	end
	for i, g0 in ipairs(gaps) do
		local g1 = gaps[i % #gaps + 1]
		local span = (g1 - g0) % 360
		if span == 0 then
			span = 360
		end
		local from, to = g0 + 9, g0 + span - 9
		if to > from then
			local n = math.max(1, math.ceil((to - from) / 30))
			for k = 0, n do
				addRim(from + (to - from) * k / n)
			end
		end
	end
	local spec = {
		V = 3,
		Tiers = {
			{ R = R + 3, H = 1 },
			{ R = R - 6, H = 2 },
			{ R = R - 28, H = 2 },
			{ R = R - 62, H = 3 },
		},
		Puffs = puffs,
		Rim = rim,
		-- keep the walking area clear: nothing of the body may rise above the lawn inside the rim, nor over an
		-- exit (the spoke bridges and the shop neck dock there)
		Carve = function(x, y, z)
			if y <= 0 then
				return false
			end
			if (x * x + z * z) < (R - 6) * (R - 6) then
				return true
			end
			for _, ex in ipairs(exits) do
				local along = x * ex[1] + z * ex[2]
				if along > R - 24 and math.abs(-x * ex[2] + z * ex[1]) < ex[3] then
					return true
				end
			end
			return false
		end,
		Seed = 4,
		MaxParts = 360,
	}
	-- top of tier 1 sits 1.2 under the lawn surface; rim puffs rise up to ~5 studs above the lawn
	local body = VX.CloudModel(spec, CFrame.new(OX, TOP - 1.2, OZ), f, "PlazaCloud", true)
	if body then
		Mesh.tag(body, "cloud_plaza", CFrame.new(OX, TOP - 1.2, OZ))
	end
end

-- Fountain on the roundabout (bug #13, the player's pick on the pitch board: option C "Sky-Oasis Steps"). Three chunks
-- of a broken sky-island stand in a mossy rock pool: the low one came down in the water, the settlers propped the
-- other two on drum-stone pillars. A spring on the top island feeds a small fall onto the middle island, its stream
-- runs to the big fall into the pool, and a seep on the low island gives a small west fall. Players climb it: stepping
-- stones, a ladder (low -> middle) and a knotted rope (middle -> top) up to Nimbus's twig nest.
--   Meshes (blender/kit/props/lobby_oasis.py, catalog lobby.json): prop_oasis_pool / _islands / _water dress the Part
--   build below (the colliders and the fallback until the keys are uploaded), prop_oasis_boat rides the paper boat's
--   root part (ML_Weld; client FountainFx bobs it). The falls are Beams (TextureSpeed: they move with no script), the
--   splashes / ripples / mist ParticleEmitters with Roblox's own soft textures (no glitter: the old spray was the
--   sparkle star and started inside the statue). The two climbs are invisible TrussParts with plank landings on top.
-- OASIS mirrors the kit's LAYOUT (studs, fountain frame: origin = the ground under the pool centre, -Z = the front,
-- toward the plaza centre). Change both together; tools/smoke_bug13_fountain.lua checks them against the manifests.
local OASIS = {
	PoolIn = 8.6, -- the rim wall's inner radius (the water reaches it)
	RimR = 9.55, -- the boulders' centre line
	Water = 1.25, -- the water surface
	Islands = { -- centre (x, z), grass top, radii (x, z), underside depth below the soil band
		{ C = { -3.8, -0.6 }, Top = 4.0, R = { 3.4, 3.2 }, Depth = 2.6 },
		{ C = { 3.0, -1.0 }, Top = 7.5, R = { 3.4, 3.3 }, Depth = 2.6 },
		{ C = { -0.6, 4.0 }, Top = 10.5, R = { 4.3, 3.4 }, Depth = 3.0 },
	},
	Stones = { { -2.3, -7.0, 2.0, 1.05 }, { -3.6, -5.3, 3.0, 0.95 } }, -- x, z, top, radius
	-- the climbs: truss centre (x, z), bottom / top, the face the player climbs (local), the plank landing's extent
	Ladder = { C = { -1.4, -0.85 }, Y0 = 3.55, Y1 = 7.55, Deck = { -2.45, -0.25 } },
	Rope = { C = { 2.3, 0.5 }, Y0 = 6.6, Y1 = 10.6, Deck = { -0.55, 1.55 } },
	Nest = { C = { -0.9, 4.7 }, R = 2.35, Floor = 10.5 },
	StatueScale = 2.1, -- Nimbus nests in it (2.6 swallowed the top island; Gemini and Claude agreed on 2.1)
	Tree = { -6.0, -1.7 },
	Lantern = { 5.4, 0.6 },
	Spring = { 2.0, 5.6 },
	Streams = {
		{ { 2.0, 4.8 }, { 2.7, 3.4 }, { 3.15, 2.35 } }, -- island 3: the spring -> its right rim
		{ { 3.75, 1.75 }, { 3.85, -0.8 }, { 3.6, -4.2 } }, -- island 2: under the small fall -> its front rim
		{ { -5.0, 1.0 }, { -5.9, 1.1 }, { -6.75, 1.05 } }, -- island 1: the seep -> its west rim
	},
	-- the falls: lip (x, y, z), outward direction (x, z), landing height, sheet width; Big = the one into the pool
	Falls = {
		{ Lip = { 3.25, 10.25, 2.25 }, Dir = { 0.81, -0.59 }, Land = 7.5, Width = 1.0 },
		{ Lip = { 3.6, 7.25, -4.35 }, Dir = { 0.12, -0.99 }, Land = 1.25, Width = 1.9, Big = true },
		{ Lip = { -6.85, 3.85, 1.05 }, Dir = { -0.95, 0.31 }, Land = 1.25, Width = 1.0 },
	},
	Sign = { Pos = { -6.45, -9.2 }, Face = { -0.57, -0.82 } },
	Boat = { 0.7, -6.3 },
}

-- Roblox's own particle textures (shipped with every client; nothing to upload)
local Oasis = {} -- the fountain helpers (one main-chunk local: LobbyBuilder is near the 200-locals limit)
Oasis.Tex = {
	Glow = "rbxasset://textures/particles/explosion01_implosion_main.dds", -- a soft round glow: drops, fall cores, streaks
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds", -- a soft ring: ripples
	Puff = "rbxasset://textures/particles/smoke_main.dds", -- a soft puff: foam, mist
}
-- Fall direction. The Beam reference: a positive TextureSpeed scrolls the texture from Attachment0 toward Attachment1,
-- a negative one from Attachment1 toward Attachment0. Each fall's Attachment0 is its impact and Attachment1 its lip, so
-- Flow = -1 runs the streaks downhill, lip -> impact. (Studio check #1 after upload: if they ever climb, the engine
-- disagrees with its docs: flip this to 1.)
Oasis.Flow = -1

Oasis.Drop = ColorSequence.new(rgb(236, 248, 255), rgb(160, 214, 250))
Oasis.Foam = ColorSequence.new(rgb(250, 253, 255), rgb(214, 236, 252))

-- fountain-local stud point -> world
function Oasis.at(origin, x, y, z)
	return (origin * CFrame.new(x, y, z)).Position
end

-- An emitter with the water look: soft round texture by default, never the sparkle star.
function Oasis.emitter(parent, props)
	local e = emitter(parent, {
		Texture = Oasis.Tex.Glow,
		Color = Oasis.Drop,
		LightEmission = 0.35,
		LightInfluence = 0.4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(0, 0),
	})
	for k, v in pairs(props or {}) do
		e[k] = v
	end
	return e
end

-- Voxel helpers for the Part build in fountain-local studs. Grid "fine" = 0.5-stud voxels whose rows span
-- [j * 0.5, j * 0.5 + 0.5] above the ground (built at origin * (0, 0.25, 0)); grid "rock" = 1-stud voxels spanning
-- [j, j + 1] (built at origin * (0, 0.5, 0)). So island tops (4.0 / 7.5 / 10.5) and stone tops land exactly.
function Oasis.fill(g, x0, x1, z0, z1, y0, y1, key, inside)
	for i = math.floor(x0 * 2), math.ceil(x1 * 2) do
		for k = math.floor(z0 * 2), math.ceil(z1 * 2) do
			local x, z = i * 0.5, k * 0.5
			local lo, hi = inside(x, z)
			if lo then
				for j = math.max(math.ceil(lo * 2 - 0.5), math.floor(y0 * 2)), math.min(math.floor(hi * 2 - 0.5), math.ceil(y1 * 2)) do
					Voxel.Set(g, i, j, k, key)
				end
			end
		end
	end
end

function Oasis.island(g, I, isLow)
	local cx, cz, rx, rz = I.C[1], I.C[2], I.R[1], I.R[2]
	local top = I.Top
	Oasis.fill(g, cx - rx - 0.5, cx + rx + 0.5, cz - rz - 0.5, cz + rz + 0.5, 0, top, "Dirt", function(x, z)
		local q = math.sqrt(((x - cx) / rx) ^ 2 + ((z - cz) / rz) ^ 2)
		if q > 1 then
			return nil
		end
		-- the soil band (1 stud) then the craggy cone: deeper toward the middle; the low island reaches the pool floor
		local depth = 1.0 + (I.Depth + 0.2) * (1 - q ^ 1.6)
		local bottom = isLow and math.max(0, top - depth - 1.5) or (top - depth)
		return bottom, top
	end)
	-- grass on top (a slight lip past the soil), a stony core toward the tip
	Oasis.fill(g, cx - rx - 0.6, cx + rx + 0.6, cz - rz - 0.6, cz + rz + 0.6, top - 0.5, top, "Grass", function(x, z)
		local q = math.sqrt(((x - cx) / (rx + 0.2)) ^ 2 + ((z - cz) / (rz + 0.2)) ^ 2)
		if q > 1 then
			return nil
		end
		return top - 0.5, top
	end)
	-- the stony tip: the lowest part of the cone turns to rock
	local tipY = top - 1.0 - (I.Depth + 0.2) * 0.7
	for i = math.floor((cx - rx) * 2), math.ceil((cx + rx) * 2) do
		for k = math.floor((cz - rz) * 2), math.ceil((cz + rz) * 2) do
			for j = 0, math.floor(tipY * 2) do
				if Voxel.Get(g, i, j, k) == "Dirt" then
					Voxel.Set(g, i, j, k, "Rock")
				end
			end
		end
	end
	-- a darker soil band a stud under the grass (the broken edge's strata)
	local jb = math.floor((top - 1.5) * 2)
	for i = math.floor((cx - rx) * 2), math.ceil((cx + rx) * 2) do
		for k = math.floor((cz - rz) * 2), math.ceil((cz + rz) * 2) do
			if Voxel.Get(g, i, jb, k) == "Dirt" then
				Voxel.Set(g, i, jb, k, "DirtDark")
			end
		end
	end
end

-- distance from (x, z) to the polyline `pts` ({ {x, z}, ... })
function Oasis.polyDist(x, z, pts)
	local best = math.huge
	for n = 1, #pts - 1 do
		local ax, az, bx, bz = pts[n][1], pts[n][2], pts[n + 1][1], pts[n + 1][2]
		local vx, vz = bx - ax, bz - az
		local t = ((x - ax) * vx + (z - az) * vz) / math.max(vx * vx + vz * vz, 1e-9)
		t = math.max(0, math.min(1, t))
		best = math.min(best, math.sqrt((x - ax - vx * t) ^ 2 + (z - az - vz * t) ^ 2))
	end
	return best
end

function Oasis.partBuild(m, origin)
	local O = OASIS
	local fineCF = origin * CFrame.new(0, 0.25, 0)
	local rockCF = origin * CFrame.new(0, 0.5, 0)
	-- 1) the pool: boulder rim (1-stud voxels) and the stepping stones, collidable
	local rock = Voxel.NewGrid(16)
	VX.Ring(rock, 0, 0, O.PoolIn, O.PoolIn + 1.2, 0, 0, "RockDark")
	for i = 0, 20 do
		local a = (i + (Voxel.Hash(i, 1, 21, 3) - 0.5) * 0.35) / 21 * math.pi * 2
		local rr = O.RimR + (Voxel.Hash(i, 2, 21, 3) - 0.5) * 0.4
		local h = 2 -- boulder tops at 2 studs (the meshes' 1.55 .. 2.25), size varies with the hash below
		Voxel.Shape(rock, {
			Kind = "Ellipsoid",
			Key = (i % 4 == 1) and "RockDark" or "Rock",
			Center = { math.cos(a) * rr, h * 0.5 - 0.5, math.sin(a) * rr },
			Radius = { 0.9 + Voxel.Hash(i, 4, 21, 3) * 0.3, h * 0.5 + 0.3, 1.3 + Voxel.Hash(i, 3, 21, 3) * 0.5 },
			Rotation = CFrame.Angles(0, -a, 0),
		})
	end
	for _, s in ipairs(O.Stones) do
		VX.Disc(rock, s[1], s[2], s[4], 0, s[3] - 1, "Rock")
	end
	Voxel.Shade(rock, { Only = { Rock = true, RockDark = true }, Smooth = 1, Seed = 13 })
	local pool = Instance.new("Model")
	pool.Name = "Pool"
	pool.Parent = m
	VX.Build(rock, { V = 1, Name = "Rim", CF = rockCF, Collide = true, Parent = pool, MaxParts = 84 })
	-- the pool floor: four squares turned by 22.5 degrees (a 16-gon whose corners hide under the rim), 0.5 stud thick
	local side = O.PoolIn * 2 * math.cos(math.pi / 4) + 0.2
	for i = 0, 3 do
		box(pool, "Floor", origin * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, i * math.pi / 8, 0), Vector3.new(side, 0.5, side),
			C.PoolFloor, { Collide = true, Shadow = false })
	end
	-- the sign (pool key): two posts and the faded board, Parts
	do
		local sp, sf = O.Sign.Pos, O.Sign.Face
		local yaw = math.atan2(-sf[1], -sf[2])
		local cf = origin * CFrame.new(sp[1], 0, sp[2]) * CFrame.Angles(0, yaw, 0)
		local sign = Instance.new("Model")
		sign.Name = "Sign"
		sign.Parent = pool
		for _, sx in ipairs({ -1.15, 1.15 }) do
			box(sign, "Post", cf * CFrame.new(sx, 1.45, 0.12), Vector3.new(0.3, 2.9, 0.3), C.PlankDark, { Collide = true })
		end
		box(sign, "Board", cf * CFrame.new(0, 2.02, -0.06), Vector3.new(2.6, 1.2, 0.22), C.Plank)
		box(sign, "Cap", cf * CFrame.new(0, 2.75, 0), Vector3.new(2.8, 0.18, 0.4), C.PlankLight)
		box(sign, "Paint", cf * CFrame.new(-0.45, 2.05, -0.19), Vector3.new(0.5, 0.6, 0.06), C.SignPaint)
	end

	-- 2) the islands, pillars and the pool floor (0.5-stud voxels), collidable
	local g = Voxel.NewGrid(64)
	local I1, I2, I3 = O.Islands[1], O.Islands[2], O.Islands[3]
	for _, p in ipairs({ { I2.C[1] - 0.1, I2.C[2] + 0.2, I2.Top - 3.5, 0.9 }, { I3.C[1] + 0.2, I3.C[2] + 0.1, I3.Top - 3.9, 1.0 } }) do
		Oasis.fill(g, p[1] - 1.2, p[1] + 1.2, p[2] - 1.2, p[2] + 1.2, 0, p[3], "Rock", function(x, z)
			if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 > p[4] * p[4] then
				return nil
			end
			return 0, p[3]
		end)
	end
	for i, I in ipairs(O.Islands) do
		Oasis.island(g, I, i == 1)
	end
	-- the streams: the top grass row cut away along each stream (the water grid fills the channel)
	for s, pts in ipairs(O.Streams) do
		local j = math.floor(O.Islands[4 - s].Top * 2 - 0.5)
		for i = -24, 24 do
			for k = -24, 24 do
				if Oasis.polyDist(i * 0.5, k * 0.5, pts) <= 0.45 then
					Voxel.Set(g, i, j, k, nil)
				end
			end
		end
	end
	Voxel.Shade(g, { Only = { Grass = true }, Smooth = 1, Seed = 5 })
	local islands = Instance.new("Model")
	islands.Name = "Islands"
	islands.Parent = m
	VX.Build(g, { V = 0.5, Name = "Ground", CF = fineCF, Collide = true, Parent = islands, MaxParts = 180 })

	-- 3) decor on the islands (islands key), not collidable: the tree, the nest, the lantern, ladder, rope, landings
	local d = Voxel.NewGrid(64)
	local function shape(t)
		Voxel.Shape(d, t)
	end
	local function v(x, y, z) -- studs -> fine voxel coords
		return { x * 2, (y - 0.25) * 2, z * 2 }
	end
	local tx, tz = O.Tree[1], O.Tree[2]
	shape({ Kind = "Capsule", Key = "Bark", A = v(tx, I1.Top, tz), B = v(tx, I1.Top + 2.6, tz), Radius = 0.6, RadiusB = 0.45 })
	shape({ Kind = "Ellipsoid", Key = "Leaf", Center = v(tx, I1.Top + 3.3, tz), Radius = { 2.7, 2.1, 2.6 } })
	shape({ Kind = "Ellipsoid", Key = "Leaf", Center = v(tx + 0.7, I1.Top + 2.75, tz - 0.25), Radius = { 1.7, 1.4, 1.7 } })
	local nc = O.Nest.C
	shape({ Kind = "Torus", Key = "Twig", Center = v(nc[1], O.Nest.Floor + 0.25, nc[2]), Radius = O.Nest.R * 2, Thickness = 0.8 })
	local lx, lz = O.Lantern[1], O.Lantern[2]
	-- (thin pieces are capsules: a capsule always keeps the voxels along its line, a thin box can miss every centre)
	shape({ Kind = "Capsule", Key = "PlankDark", A = v(lx, I2.Top, lz), B = v(lx, I2.Top + 2.5, lz), Radius = 0.5 })
	shape({ Kind = "Capsule", Key = "Iron", A = v(lx, I2.Top + 2.45, lz), B = v(lx - 0.65, I2.Top + 2.45, lz), Radius = 0.4 })
	shape({ Kind = "Box", Key = "Iron", Center = v(lx - 0.65, I2.Top + 2.1, lz), Size = { 2, 1, 2 } })
	shape({ Kind = "Box", Key = "Lamp", Center = v(lx - 0.65, I2.Top + 1.6, lz), Size = { 1.2, 1.4, 1.2 } })
	-- the ladder on the low truss's -X face, its landing; the rope on the high truss's -Z face, its landing
	local L, R = O.Ladder, O.Rope
	local fx = L.C[1] - 1.0 + 0.12
	for _, sz in ipairs({ -0.7, 0.7 }) do
		shape({ Kind = "Capsule", Key = "Plank", A = v(fx, L.Y0 + 0.4, L.C[2] + sz), B = v(fx, L.Y1 + 0.75, L.C[2] + sz), Radius = 0.5 })
	end
	local y = L.Y0 + 0.95
	while y < L.Y1 - 0.3 do
		shape({ Kind = "Capsule", Key = "PlankLight", A = v(fx, y, L.C[2] - 0.75), B = v(fx, y, L.C[2] + 0.75), Radius = 0.4 })
		y = y + 0.75
	end
	shape({ Kind = "Box", Key = "Plank", Center = v((L.Deck[1] + L.Deck[2]) / 2, L.Y1 - 0.25, L.C[2]), Size = { (L.Deck[2] - L.Deck[1]) * 2, 1, 4 } })
	shape({ Kind = "Box", Key = "Plank", Center = v(R.C[1], R.Y1 - 0.25, (R.Deck[1] + R.Deck[2]) / 2), Size = { 4, 1, (R.Deck[2] - R.Deck[1]) * 2 } })
	shape({ Kind = "Capsule", Key = "Rope", A = v(R.C[1], I2.Top, R.C[2] - 0.9), B = v(R.C[1], R.Y1 + 0.05, R.C[2] - 0.9), Radius = 0.45 })
	local ky = R.Y1 - 0.6
	while ky > I2.Top + 0.6 do -- the knots
		shape({ Kind = "Ellipsoid", Key = "Rope", Center = v(R.C[1], ky, R.C[2] - 0.9), Radius = 0.8 })
		ky = ky - 0.7
	end
	-- (not NC_Detail: the ladder and the rope show where to climb, Low graphics keeps them)
	VX.Build(d, { V = 0.5, Name = "Decor", CF = fineCF, Collide = false, Parent = islands, MaxParts = 60 })

	-- 4) the water (water key): the pool surface and the island streams, translucent, not collidable
	local w = Voxel.NewGrid(64)
	local wCF = origin -- 0.5-stud rows centred on j * 0.5: the surface row j = 2 spans 0.75 .. 1.25
	Oasis.fill(w, -O.PoolIn, O.PoolIn, -O.PoolIn, O.PoolIn, 0, 2, "Water", function(x, z)
		if x * x + z * z > (O.PoolIn + 0.2) ^ 2 then
			return nil
		end
		return 0.5, 1.5
	end)
	for s, pts in ipairs(O.Streams) do
		local jy = math.floor((O.Islands[4 - s].Top - 0.1) * 2) -- the row just under the channel lip
		for i = -24, 24 do
			for k = -24, 24 do
				if Oasis.polyDist(i * 0.5, k * 0.5, pts) <= 0.45 then
					Voxel.Set(w, i, jy, k, "Water")
				end
			end
		end
	end
	local waterModel = VX.Build(w, { V = 0.5, Name = "Water", CF = wCF, Collide = false, Parent = m })
	return pool, islands, waterModel
end

-- One fall: a soft core sheet and thin fast streaks (Beams, FaceCamera), droplets off the lip (big fall), and at the
-- impact a splash of drops, foam, ripple rings on the water (and mist off the big one). Attachment0 = the impact,
-- Attachment1 = the lip (Oasis.Flow = -1: the texture runs A1 -> A0, down); both live on the invisible `anchor` part.
function Oasis.fall(anchor, origin, f, index)
	local lx, ly, lz = f.Lip[1], f.Lip[2], f.Lip[3]
	local dx, dz = f.Dir[1], f.Dir[2]
	local drop = ly - f.Land
	local throw = 0.3 + drop * 0.1
	local up = Vector3.new(0, 1, 0)
	local out = Vector3.new(dx, 0, dz).Unit
	local side = Vector3.new(-dz, 0, dx).Unit
	local lip = Vector3.new(lx, ly + 0.05, lz) + out * 0.2
	local impact = Vector3.new(lx, f.Land, lz) + out * (0.2 + throw)
	local inv = anchor.CFrame:Inverse() * origin -- fountain-local -> anchor-local
	local function attach(name, pos, xAxis)
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = inv * CFrame.fromMatrix(pos, xAxis, side:Cross(xAxis).Unit)
		a.Parent = anchor
		return a
	end
	local xBottom = up -- from the impact the curve rises (P1 = A0 + X0 * CurveSize0)
	local xTop = (out * -0.6 + up * 0.8).Unit -- P2 = A1 - X1 * CurveSize1: out and down from the lip
	local function beam(name, a0, a1, props)
		local b = Instance.new("Beam")
		b.Name = name
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.Segments = 14
		b.CurveSize0 = drop * 0.3
		b.CurveSize1 = 0.45 + throw * 0.5
		b.LightInfluence = 0.5
		for k, v in pairs(props) do
			b[k] = v
		end
		b.Parent = anchor
		return b
	end
	local tag = "Fall" .. index
	local a0 = attach(tag .. "Impact", impact, xBottom)
	local a1 = attach(tag .. "Lip", lip, xTop)
	beam(tag .. "Core", a0, a1, {
		Texture = Oasis.Tex.Glow,
		TextureMode = Enum.TextureMode.Stretch,
		TextureLength = 1,
		TextureSpeed = 0,
		Width0 = f.Width * 1.25,
		Width1 = f.Width,
		Color = ColorSequence.new(rgb(150, 206, 246), rgb(120, 190, 242)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.15, 0.2),
			NumberSequenceKeypoint.new(0.9, 0.2),
			NumberSequenceKeypoint.new(1, 0.5),
		}),
		LightEmission = 0.15,
	})
	local n = f.Big and 3 or 2
	for k = 1, n do
		local off = ((k - 1) / math.max(1, n - 1) - 0.5) * f.Width * 0.55
		local s0 = attach(tag .. "StreakImpact" .. k, impact + side * off * 1.2, xBottom)
		local s1 = attach(tag .. "StreakLip" .. k, lip + side * off, xTop)
		beam(tag .. "Streak" .. k, s0, s1, {
			Texture = Oasis.Tex.Glow,
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 0.9 + k * 0.15,
			TextureSpeed = Oasis.Flow * (2.4 + k * 0.35 + (f.Big and 0.4 or 0)),
			Width0 = 0.42,
			Width1 = 0.32,
			Color = Oasis.Foam,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(0.2, 0.15),
				NumberSequenceKeypoint.new(0.85, 0.15),
				NumberSequenceKeypoint.new(1, 0.7),
			}),
			LightEmission = 0.45,
			ZOffset = 0.05 * k,
		})
	end
	-- the impact: drops, foam (and mist) on the Splash part, tagged NC_Detail so Low graphics (GraphicsQuality) parks
	-- it with its emitters off; the ripple rings on their own untagged part, so on Low the falls (Core + streak Beams)
	-- still land in rings on the water
	local big = f.Big and 1 or 0.6
	local splash = anchorPart(anchor.Parent, tag .. "Splash", Oasis.at(origin, impact.X, f.Land + 0.1, impact.Z),
		Vector3.new(f.Width, 0.2, f.Width))
	splash.CFrame = origin * CFrame.new(impact.X, f.Land + 0.1, impact.Z)
	CollectionService:AddTag(splash, DETAIL_TAG)
	local rings = anchorPart(anchor.Parent, tag .. "Ripples", splash.Position, Vector3.new(f.Width, 0.2, f.Width))
	rings.CFrame = splash.CFrame
	Oasis.emitter(splash, {
		Name = "Drops",
		Rate = 30 * big,
		Lifetime = NumberRange.new(0.45, 0.8),
		Speed = NumberRange.new(3.5 * big + 1, 6 * big + 1),
		SpreadAngle = Vector2.new(38, 38),
		Acceleration = Vector3.new(0, -24, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.38), NumberSequenceKeypoint.new(1, 0.08) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.6) }),
	})
	Oasis.emitter(splash, {
		Name = "Foam",
		Texture = Oasis.Tex.Puff,
		Color = Oasis.Foam,
		Rate = 9 * big,
		Lifetime = NumberRange.new(0.6, 1.0),
		Speed = NumberRange.new(0.6, 1.6),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, -1, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7 * big + 0.3), NumberSequenceKeypoint.new(1, 1.9 * big + 0.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		RotSpeed = NumberRange.new(-40, 40),
		LightEmission = 0.2,
	})
	Oasis.emitter(rings, {
		Name = "Ripples",
		Texture = Oasis.Tex.Ring,
		Color = Oasis.Foam,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, -- flat on the water
		EmissionDirection = Enum.NormalId.Top,
		Rate = 2.4 * big + 0.4,
		Lifetime = NumberRange.new(1.1, 1.4),
		Speed = NumberRange.new(0.05, 0.05),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.4 * big + 0.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 0.25,
	})
	if f.Big then
		Oasis.emitter(splash, {
			Name = "Mist",
			Texture = Oasis.Tex.Puff,
			Color = Oasis.Foam,
			Rate = 4,
			Lifetime = NumberRange.new(1.6, 2.6),
			Speed = NumberRange.new(0.6, 1.2),
			SpreadAngle = Vector2.new(70, 70),
			Acceleration = Vector3.new(0, 0.4, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 4.2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) }),
			RotSpeed = NumberRange.new(-20, 20),
			LightEmission = 0.1,
		})
		-- droplets breaking off the lip (the sheet tears into drops as it falls): the part's front (-Z) faces out
		local lipWorld = Oasis.at(origin, lip.X, lip.Y - 0.1, lip.Z)
		local outWorld = origin:VectorToWorldSpace(out)
		local lipPart = anchorPart(anchor.Parent, tag .. "LipDrops", lipWorld, Vector3.new(f.Width, 0.2, 0.3))
		lipPart.CFrame = CFrame.lookAt(lipWorld, lipWorld + outWorld)
		CollectionService:AddTag(lipPart, DETAIL_TAG)
		Oasis.emitter(lipPart, {
			Name = "LipDrops",
			Rate = 12,
			Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(1.2, 2.2),
			EmissionDirection = Enum.NormalId.Front,
			SpreadAngle = Vector2.new(15, 15),
			Acceleration = Vector3.new(0, -26, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.14) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.5) }),
		})
	end
	return impact
end

-- The paper boat: one root Part and its sail under it, both Anchored like every lobby part (the server never moves
-- them; client FountainFx moves the root and the sail together at their rest offsets, and the dressed mesh rides the
-- root, ML_Weld). Returns the root and its fountain-local rest frame.
function Oasis.boat(m, origin)
	local b = OASIS.Boat
	local rest = CFrame.new(b[1], OASIS.Water, b[2]) * CFrame.Angles(0, 0.5, 0)
	local cf = origin * rest
	local root = box(m, "PaperBoat", cf * CFrame.new(0, 0.1, 0), Vector3.new(0.6, 0.3, 1.3), C.Paper, { Shadow = false })
	local sail = box(root, "Sail", cf * CFrame.new(0, 0.5, 0), Vector3.new(0.1, 0.55, 0.6), C.Paper, { Shadow = false })
	sail.CanCollide = false
	root:SetAttribute("ML_Weld", true) -- a moving root: the dressed mesh is welded to it (MeshLibrary.Dress)
	CollectionService:AddTag(root, "OasisBoat")
	return root, rest
end

local function buildFountain(f, centre, lookTarget)
	local m = newModel(f, "Fountain")
	local ground = flatLook(Vector3.new(centre.X, TOP, centre.Z), Vector3.new(lookTarget.X, TOP, lookTarget.Z))
	local pool, islands, waterModel = Oasis.partBuild(m, ground)
	-- Phase 6: the Blender meshes dress these Part builds once their keys are uploaded (the Parts stay the colliders)
	Mesh.tag(pool, "prop_oasis_pool", ground)
	Mesh.tag(islands, "prop_oasis_islands", ground)
	if waterModel then
		Mesh.tag(waterModel, "prop_oasis_water", ground)
	end
	local boat, boatRest = Oasis.boat(m, ground)
	Mesh.tag(boat, "prop_oasis_boat", ground * boatRest)

	-- the climbs: invisible trusses (reliable climbing for every rig), tops flush with the plank landings
	for _, spec in ipairs({ { "LadderTruss", OASIS.Ladder }, { "RopeTruss", OASIS.Rope } }) do
		local c = spec[2]
		local t = Instance.new("TrussPart")
		t.Name = spec[1]
		t.Anchored = true
		t.Size = Vector3.new(2, c.Y1 - c.Y0, 2)
		t.CFrame = ground * CFrame.new(c.C[1], (c.Y0 + c.Y1) / 2, c.C[2])
		t.Transparency = 1
		t.CanCollide = true
		t.CanQuery = true
		t.CanTouch = false
		t.CastShadow = false
		t.Parent = m
	end

	-- the water: three falls (Beams on one anchor), their splashes, a few bubbles at the spring
	local anchor = anchorPart(m, "Falls", ground.Position)
	anchor.CFrame = ground
	CollectionService:AddTag(anchor, "OasisFalls")
	for i, fall in ipairs(OASIS.Falls) do
		Oasis.fall(anchor, ground, fall, i)
	end
	local sp = OASIS.Spring
	local bubbles = anchorPart(m, "SpringBubbles", Oasis.at(ground, sp[1] - 0.05, OASIS.Islands[3].Top - 0.2, sp[2] - 0.75),
		Vector3.new(0.8, 0.1, 0.6))
	CollectionService:AddTag(bubbles, DETAIL_TAG) -- Low graphics: the bubbles rest (the falls and ripples keep running)
	Oasis.emitter(bubbles, {
		Name = "Bubbles",
		Rate = 5,
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(0.5, 1.0),
		SpreadAngle = Vector2.new(20, 20),
		Acceleration = Vector3.new(0, -2, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0.05) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.8) }),
	})
	-- the lantern's warm glow on the middle island (the old blue spray light went with the spray)
	local lp = OASIS.Lantern
	local lamp = anchorPart(m, "LanternLight", Oasis.at(ground, lp[1] - 0.65, OASIS.Islands[2].Top + 1.6, lp[2] - 0.05))
	pointLight(lamp, C.Lamp, 0.8, 12)

	-- Nimbus in the nest (optional: the pet modules); the statue's lowest point sits on the nest floor, facing front
	local ok, err = pcall(function()
		local builderModule = Shared:FindFirstChild("PetBuilder")
		local catalogModule = Shared:FindFirstChild("PetCatalog")
		if not builderModule or not catalogModule then
			return
		end
		local PetBuilder = require(builderModule)
		local PetCatalog = require(catalogModule)
		local def = PetCatalog.Get and PetCatalog.Get("cloudy_dragon")
		if not def or type(PetBuilder.Build) ~= "function" then
			return
		end
		local opts = { Scale = OASIS.StatueScale, Detail = "Low" }
		local nest = OASIS.Nest
		local function statue()
			local pet = PetBuilder.Build(def, opts)
			if not pet then
				return nil
			end
			pet.Name = "NimbusStatue"
			pet:PivotTo(CFrame.new(0, 0, 0))
			local boxCf, boxSize = pet:GetBoundingBox()
			local bottom = pet:GetPivot().Position.Y - (boxCf.Position.Y - boxSize.Y * 0.5)
			if type(bottom) ~= "number" or bottom ~= bottom or bottom < -50 or bottom > 100 then
				bottom = 2
			end
			pet:PivotTo(ground * CFrame.new(nest.C[1], nest.Floor + bottom, nest.C[2]))
			for _, d in ipairs(pet:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanTouch = false
					d.CanQuery = false
				end
			end
			CollectionService:AddTag(pet, EXEMPT_TAG) -- a pet statue: skipped by the 6.4 material / saturation audit
			return pet
		end
		local pet = statue()
		if not pet then
			return
		end
		pet.Parent = m
		-- Phase 6: the mesh Nimbus replaces this Part build once its keys load after boot (MeshLibrary.Swap)
		if type(PetBuilder.SwapWhenReady) == "function" then
			PetBuilder.SwapWhenReady(pet, def, opts, statue)
		end
	end)
	if not ok then
		warn("[LobbyBuilder] fountain statue skipped: " .. tostring(err))
	end
	return m
end

----------------------------------------------------------------------
-- Phase 5 courts (6.1; Phase 6: the P4 colours): the tiled spawn court, the Gate Court with its terrace, the avenue,
-- the welcome arch
----------------------------------------------------------------------
local Court = {}

-- Boxes along an annulus sector (plaza angles in degrees, radii in studs): each segment spans [r0, r1] radially and
-- about `seg` studs of arc. fn(i, n) -> color | nil (skip), topOffset (above TOP), material | nil. A grout gap
-- separates the tiles; neighbours overlap a little at the inner edge, so their heights alternate (rule 5).
function Court.Arc(parent, name, r0, r1, a0, a1, seg, thick, gap, fn)
	local span = a1 - a0
	local rm = (r0 + r1) / 2
	local n = math.max(1, math.floor(math.rad(span) * rm / seg + 0.5))
	local step = span / n
	local width = 2 * r1 * math.sin(math.rad(step) / 2) - gap
	for i = 1, n do
		local color, top, material = fn(i, n)
		if color then
			local a = a0 + (i - 0.5) * step
			local pos = polar(a, rm, TOP + top - thick / 2)
			local cf = CFrame.lookAt(pos, Vector3.new(OX, pos.Y, OZ))
			local p = box(parent, name, cf, Vector3.new(math.max(0.4, width), thick, (r1 - r0) - gap), color, { Collide = true, Material = material, Shadow = false })
			p.CanQuery = true
		end
	end
end

-- Tile colour: the base cream stone with a +-6 RGB jitter per tile, deterministic.
function Court.Jitter(color, a, b)
	local h = hash3(a, b, 7, 31) * 2 - 1
	local d = h * 6 / 255
	return Color3.new(clamp(color.R + d, 0, 1), clamp(color.G + d, 0, 1), clamp(color.B + d * 1.2, 0, 1))
end

-- The tiled courts: concentric Slate rings around the medallion (r 4 .. 32) inside a Marble ring (32 .. 34); the Gate
-- Court's lower level (r 96 .. 126) and its raised terrace (r 126 .. 146, a Marble step in front), Marble rims.
function Court.Tiles(f, L)
	local m = newModel(f, "Courts")
	local slate, slateL = C.Slate, C.SlateLight
	local ring = 0
	local function tiles(name, r0, r1, a0, a1, depth, seg, top)
		local r = r0
		while r < r1 - 0.5 do
			local rb = math.min(r1, r + depth)
			ring = ring + 1
			local thisRing = ring
			Court.Arc(m, name, r, rb, a0, a1, seg, top + 0.6, 0.22, function(i)
				local alt = (i + thisRing) % 2 == 0
				return Court.Jitter(alt and slateL or slate, i, thisRing), top + (alt and 0.05 or 0), materialOf("Slate")
			end)
			r = rb
		end
	end
	-- the spawn court
	tiles("SpawnTile", 4.6, 32, 0, 360, 4.6, 6, 0)
	Court.Arc(m, "SpawnRing", 32, 34.4, 0, 360, 7, 0.7, 0.12, function(i)
		return (i % 2 == 0) and C.Marble or C.MarbleShade, 0.08
	end)
	-- the Gate Court (lower level + the raised terrace)
	tiles("CourtTile", G.CourtIn, G.TerraceIn - 1, L.CourtFrom, L.CourtTo, 6, 6, 0)
	Court.Arc(m, "CourtRim", G.CourtIn - 1.6, G.CourtIn + 0.2, L.CourtFrom, L.CourtTo, 8, 0.6, 0.1, function(i)
		return (i % 2 == 0) and C.Marble or C.MarbleShade, 0.08
	end)
	Court.Arc(m, "TerraceStep", G.TerraceIn - 1, G.TerraceIn + 1.2, L.CourtFrom, L.CourtTo, 8, 0.9, 0.1, function(i)
		return (i % 2 == 0) and C.Marble or C.MarbleShade, G.TerraceLift + 0.05
	end)
	tiles("TerraceTile", G.TerraceIn + 1.2, G.CourtOut, L.CourtFrom, L.CourtTo, 6.3, 6, G.TerraceLift)
	-- the side edges of the sector: Marble kerbs from the rim to the back of the terrace
	for _, a in ipairs({ L.CourtFrom, L.CourtTo }) do
		local inward = (a == L.CourtFrom) and 1 or -1
		local mid = (G.CourtIn - 1.6 + G.CourtOut) / 2
		local len = G.CourtOut - (G.CourtIn - 1.6)
		local d = dirOf(a)
		local side = dirOf(a + 90) * inward
		local pos = Vector3.new(OX, TOP, OZ) + d * mid + side * 0.6 + Vector3.new(0, G.TerraceLift / 2 - 0.15, 0)
		local p = box(m, "CourtSide", CFrame.lookAt(pos, pos + d), Vector3.new(1.4, G.TerraceLift + 0.75, len), C.MarbleShade, { Collide = true })
		p.CanQuery = true
	end
	Mesh.tag(m, "floor_plaza_courts", CFrame.new(OX, TOP, OZ)) -- Phase 6 (LayoutSig)
	return m
end

-- The cobbled circle walk (r RingRoadR, 8 wide + Brick borders) from one end of the Gate Court round to the other:
-- arc segments read smoother than voxel cells and cost fewer parts. Its tops sit 0.03 / 0.06 above the voxel paths
-- that cross it (no coplanar overlap).
function Court.RingRoad(f, L)
	local m = newModel(f, "CircleWalk")
	local a0, a1 = L.CourtTo + 0.4, L.CourtFrom + 360 - 0.4
	local R, h = G.RingRoadR, G.PathHalf - 1
	Court.Arc(m, "Walk", R - h, R + h, a0, a1, 8, 0.7, 0.05, function(i)
		local alt = i % 2 == 0
		return Court.Jitter(alt and C.StoneLight or C.Stone, i, 3), alt and 0.06 or 0.03, materialOf("Cobblestone")
	end)
	for _, rb in ipairs({ { R - h - 1.2, R - h + 0.05 }, { R + h - 0.05, R + h + 1.2 } }) do
		Court.Arc(m, "WalkBorder", rb[1], rb[2], a0, a1, 10, 0.6, 0.02, function(i)
			return C.StoneEdge, (i % 2 == 0) and 0.0 or 0.02, materialOf("Brick")
		end)
	end
	Mesh.tag(m, "floor_plaza_walk", CFrame.new(OX, TOP, OZ)) -- Phase 6 (LayoutSig)
	return m
end

-- Angular gaps (degrees) of the walks crossing a ring of radius r: { centre, half } per crossing walk.
function Court.Gaps(L, r, extra)
	local gaps = {}
	local function add(a, half)
		gaps[#gaps + 1] = { a, math.deg((half + (extra or 0)) / r) }
	end
	for _, a in ipairs(L.SpokeAngles) do
		add(a, G.StubHalf)
	end
	for _, a in ipairs(L.CrossAngles) do
		add(a, G.PathHalf)
	end
	add(L.ShopAngle, G.BoardHalf)
	return gaps
end

-- Arcs of a ring between the gaps (and outside the Gate Court sector when `skipCourt`) -> { { a0, a1 } ... }
function Court.Runs(L, r, gaps, skipCourt)
	local cuts = {}
	for _, g in ipairs(gaps) do
		cuts[#cuts + 1] = { g[1] - g[2], g[1] + g[2] }
	end
	if skipCourt then
		cuts[#cuts + 1] = { L.CourtFrom - 1.5, L.CourtTo + 1.5 }
	end
	-- walk the circle in 0.5-degree steps and collect the free stretches (deterministic, cheap)
	local runs, start = {}, nil
	local function blocked(a)
		for _, c in ipairs(cuts) do
			if angleIn(a, c[1], c[2]) then
				return true
			end
		end
		return false
	end
	local base = 0
	while not blocked(base) and base < 360 do
		base = base + 0.5
	end
	for k = 0, 720 do
		local a = base + k * 0.5
		if not blocked(a) then
			start = start or a
		elseif start then
			if a - 0.5 - start >= 2 then
				runs[#runs + 1] = { start, a - 0.5 }
			end
			start = nil
		end
	end
	return runs
end

-- The plaza's edge: a low Brick kerb all round the lawn (6.4 rule 3: platform edges), open at every exit; clipped
-- hedges along the inner side of the circle walk; lamps along its outer side.
function Court.Edges(f, L)
	local m = newModel(f, "PlazaEdges")
	local rimR0, rimR1 = PLAZA_R - 4.6, PLAZA_R - 3.2
	for _, run in ipairs(Court.Runs(L, rimR1, Court.Gaps(L, rimR1, 2.5), false)) do
		Court.Arc(m, "EdgeKerb", rimR0, rimR1, run[1], run[2], 14, 1.1, 0.02, function(i)
			return C.StoneEdge, (i % 2 == 0) and 0.32 or 0.3, materialOf("Brick")
		end)
	end
	Mesh.tag(m, "floor_plaza_edges", CFrame.new(OX, TOP, OZ)) -- Phase 6 (LayoutSig)
	local decor = newModel(f, "WalkHedges")
	CollectionService:AddTag(decor, DETAIL_TAG)
	local hr0 = G.RingRoadR - G.PathHalf - 4.4
	local hr1 = hr0 + 2.2
	for _, run in ipairs(Court.Runs(L, hr1, Court.Gaps(L, hr1, 1.5), true)) do
		Court.Arc(decor, "Hedge", hr0, hr1, run[1], run[2], 11, 2.2, 0.15, function(i)
			return (i % 2 == 0) and C.Hedge or C.HedgeLight, (i % 2 == 0) and 1.4 or 1.45, materialOf("LeafyGrass")
		end)
	end
	local lampTpl = Props.Lamp()
	local lit = 0
	for _, a in ipairs({ 15, 165, 200, 236, 304, 340 }) do
		if angleDiff(a, L.ShopAngle) > 12 then
			local pos = polar(a, G.RingRoadR + G.PathHalf + 2.2, TOP - LAWN)
			local lamp = place(lampTpl, CFrame.new(pos), decor, "WalkLamp")
			local glass = lamp and lamp:FindFirstChild("LampGlass")
			lit = lit + 1
			if glass and lit % 2 == 1 then
				pointLight(glass, C.Lamp, 1.0, 14)
			end
		end
	end
	return m
end

-- The grand avenue's Brick kerbs (WorldStyle.Kerb), lamp posts every 16 studs and the welcome arch at r 40.
function Court.Avenue(f, L)
	local m = newModel(f, "Avenue")
	local d = dirOf(L.MidAngle)
	local side = dirOf(L.MidAngle - 90) -- the viewer's right when looking up the avenue
	local r0, r1 = G.CourtR + 0.6, G.CourtIn - 1.8
	local mid = (r0 + r1) / 2
	if WorldStyle and WorldStyle.Kerb then
		for _, s in ipairs({ -1, 1 }) do
			local p = Vector3.new(OX, TOP, OZ) + d * mid + side * s * (G.AvenueHalf - 0.6)
			-- X along the edge, LookVector outward
			local cf = CFrame.fromMatrix(p, d * s, Vector3.new(0, 1, 0), -(side * s))
			pcall(WorldStyle.Kerb, m, cf, r1 - r0, materialOf("Brick"), C.StoneEdge)
		end
	end
	local lampTpl = Props.Lamp()
	local r = G.CourtR + 10
	local n = 0
	while r <= G.CourtIn - 6 do
		for _, s in ipairs({ -1, 1 }) do
			local pos = Vector3.new(OX, TOP - LAWN, OZ) + d * r + side * s * (G.AvenueHalf + 2)
			local lamp = place(lampTpl, CFrame.new(pos), m, "AvenueLamp")
			n = n + 1
			local glass = lamp and lamp:FindFirstChild("LampGlass")
			if glass and n % 2 == 1 then
				pointLight(glass, C.Lamp, 1.1, 14)
			end
			reserve(pos.X - OX, pos.Z - OZ, 2)
		end
		r = r + 16
	end
	Court.WelcomeArch(m, L, 40)
	return m
end

-- A stone arch over the avenue with the welcome sign (replaces the rainbow arch): two chamfered Marble piers on Slate
-- plinths, a Slate beam with a Marble cornice, the sign board on the beam (readable from the spawn and the gates).
function Court.WelcomeArch(parent, L, radius)
	local m = newModel(parent, "WelcomeArch")
	local base = polar(L.MidAngle, radius, TOP)
	local cf = flatLook(base, base + dirOf(L.MidAngle)) -- local -Z = up the avenue, towards the gates
	local px = G.AvenueHalf + 2.4
	-- tall enough that the beam stays above the gates' tags seen from the spawn (eye 5 studs up: the tags at 27 studs
	-- and 118 studs out sit ~11 degrees up; the beam's underside at ~27.5 studs and 40 out ~29 degrees)
	local pierH = 24
	for _, s in ipairs({ -1, 1 }) do
		local pc = cf * CFrame.new(s * px, 0, 0)
		if WorldStyle then
			WorldStyle.Plinth(m, pc * CFrame.new(0, 0.7, 0), Vector3.new(4.4, 1.4, 4.4), materialOf("Slate"), C.Slate)
			WorldStyle.Chamfer(m, pc * CFrame.new(0, 1.4 + pierH / 2, 0), Vector3.new(3.2, pierH, 3.2), materialOf("Marble"), C.Marble, 0.5)
		else
			box(m, "Pier", pc * CFrame.new(0, pierH / 2 + 0.7, 0), Vector3.new(3.2, pierH + 1.4, 3.2), C.Marble, { Collide = true })
		end
		box(m, "PierCap", pc * CFrame.new(0, 1.4 + pierH + 0.35, 0), Vector3.new(4, 0.7, 4), C.MarbleShade)
		reserve(base.X - OX + cf.RightVector.X * s * px, base.Z - OZ + cf.RightVector.Z * s * px, 4)
	end
	local beamY = 1.4 + pierH + 0.7 + 1.1
	box(m, "Beam", cf * CFrame.new(0, beamY, 0), Vector3.new(px * 2 + 4, 2.2, 3), C.MarbleShade, { Collide = true })
	box(m, "Cornice", cf * CFrame.new(0, beamY + 1.3, 0), Vector3.new(px * 2 + 4.8, 0.4, 3.6), C.Marble)
	box(m, "Soffit", cf * CFrame.new(0, beamY - 1.25, 0), Vector3.new(px * 2 + 2.6, 0.3, 3.3), C.SlateDark)
	local inlay = box(m, "Inlay", cf * CFrame.new(0, beamY - 0.3, -1.55), Vector3.new(px * 2, 0.25, 0.2), gateAccent("Gold"), { Material = MAT.Neon, Shadow = false })
	inlay.CastShadow = false
	-- the sign on the beam
	local boardCf = cf * CFrame.new(0, beamY + 1.5 + 3.4, 0) * CFrame.Angles(0, math.pi, 0)
	box(m, "SignFrame", boardCf, Vector3.new(19.4, 6.4, 0.8), C.SlateDark)
	box(m, "SignCap", boardCf * CFrame.new(0, 3.45, 0), Vector3.new(20.2, 0.5, 1.2), C.MarbleShade)
	local board = box(m, "WelcomeSign", boardCf, Vector3.new(18.4, 5.4, 1.0), C.Navy, { Shadow = true })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = surfaceGui(board, face)
		local panel = signPanel(gui, C.TextGold)
		signText(panel, "~ welcome to the clouds ~", "Script", 36, C.TextGold, "Welcome", 0.04, 0.05, 0.92, 0.17)
		local title = signText(panel, Config.GameName, "Title", 100, rgb(255, 255, 255), "Title", 0.03, 0.23, 0.94, 0.44)
		textGradient(title, {
			{ 0, rgb(255, 236, 160) },
			{ 0.5, rgb(255, 255, 255) },
			{ 1, rgb(180, 220, 255) },
		}, 90)
		signText(panel, Config.Tagline or "", "Script", 36, C.Text, "Tagline", 0.04, 0.72, 0.92, 0.17)
		gui.Parent = board
	end
	Mesh.tag(m, "prop_welcome_arch", cf, nil, { "WelcomeSign" }) -- Phase 6: the sign board stays (SurfaceGuis)
	return m
end

-- An obelisk (plinth + chamfered Marble shaft + a Metal cap and a small Neon band in `color`).
function Court.Obelisk(parent, ground, color)
	local m = newModel(parent, "Obelisk")
	local cf = CFrame.new(ground)
	if WorldStyle then
		WorldStyle.Plinth(m, cf * CFrame.new(0, 0.8, 0), Vector3.new(5, 1.6, 5), materialOf("Slate"), C.Slate)
		WorldStyle.Chamfer(m, cf * CFrame.new(0, 1.6 + 7, 0), Vector3.new(3, 14, 3), materialOf("Marble"), C.Marble, 0.5)
	else
		box(m, "Shaft", cf * CFrame.new(0, 8, 0), Vector3.new(3, 16, 3), C.Marble, { Collide = true })
	end
	box(m, "Band", cf * CFrame.new(0, 13, 0), Vector3.new(3.15, 0.3, 3.15), color, { Material = MAT.Neon, Shadow = false })
	box(m, "Cap", cf * CFrame.new(0, 15.95, 0), Vector3.new(3.4, 0.7, 3.4), C.MarbleShade)
	local tip = Instance.new("WedgePart")
	tip.Name = "Tip"
	tip.Anchored = true
	tip.CanCollide = false
	tip.CanQuery = false
	tip.CanTouch = false
	tip.CastShadow = false
	tip.Material = materialOf("Metal")
	tip.Color = C.Gold
	tip.Size = Vector3.new(2.2, 1.6, 1.1)
	tip.CFrame = cf * CFrame.new(0, 17.1, -0.55)
	tip.Parent = m
	local tip2 = tip:Clone()
	tip2.CFrame = cf * CFrame.new(0, 17.1, 0.55) * CFrame.Angles(0, math.pi, 0)
	tip2.Parent = m
	Mesh.tag(m, "prop_obelisk", cf, { Primary = color }) -- Phase 6: the band takes `color`
	return m
end

-- The Gate Court's dressing: hedges in Brick planters along the back of the terrace, a banner behind every gate in its
-- colour, two obelisks at the ends and lamps at the court's front corners.
function Court.Decor(f, L)
	local m = newModel(f, "GateCourtDecor")
	CollectionService:AddTag(m, DETAIL_TAG)
	-- hedges
	local hedgeR0, hedgeR1 = G.CourtOut - 3.4, G.CourtOut - 0.4
	Court.Arc(m, "Planter", hedgeR0, hedgeR1, L.CourtFrom + 1.2, L.CourtTo - 1.2, 10, 1.0, 0.3, function()
		return C.StoneEdge, G.TerraceLift + 1.0, materialOf("Brick")
	end)
	Court.Arc(m, "Hedge", hedgeR0 + 0.3, hedgeR1 - 0.3, L.CourtFrom + 1.2, L.CourtTo - 1.2, 10, 2.4, 0.5, function(i)
		return (i % 2 == 0) and C.Hedge or C.HedgeLight, G.TerraceLift + 3.2, materialOf("LeafyGrass")
	end)
	-- banners behind every gate (their colours, small cloth pieces: rule 2)
	for i, id in ipairs(L.GateOrder) do
		local a = L.GateAngles[id]
		for _, s in ipairs({ -1, 1 }) do
			local pos = polar(a + s * 3.4, G.TerraceIn + 6, TOP + G.TerraceLift)
			bannerPole(m, faceCentre(pos), gateAccent(GATE_SPECS[i].Accent))
		end
	end
	-- obelisks at both ends of the terrace
	for _, a in ipairs({ L.CourtFrom + 3.2, L.CourtTo - 3.2 }) do
		Court.Obelisk(m, polar(a, G.TerraceIn + 9, TOP + G.TerraceLift), gateAccent("Gold"))
	end
	-- lamps at the court's front corners (where the circle walk meets it)
	local lampTpl = Props.Lamp()
	for _, a in ipairs({ L.CourtFrom - 2.5, L.CourtTo + 2.5 }) do
		local pos = polar(a, G.CourtIn - 4, TOP - LAWN)
		local lamp = place(lampTpl, CFrame.new(pos), m, "CourtLamp")
		local glass = lamp and lamp:FindFirstChild("LampGlass")
		if glass then
			pointLight(glass, C.Lamp, 1.2, 16)
		end
	end
	return m
end

-- "How to play" and "Guide" notice boards on both sides of the avenue, facing the spawn.
local function buildBoards(f, L)
	local function spotFor(angle)
		local pos = plazaSpot(angle, 48, 6, L)
		if not pos then
			return nil
		end
		return faceCentre(pos - Vector3.new(0, LAWN, 0)) -- the board's face (-Z, the Front face) looks at the centre
	end
	-- 550 x 400 px canvas (11 x 8 studs): a 1.04-stud header, five 0.6-stud rows, a 0.6-stud footer
	-- (beside the lawns, clear of the sight lines from the spawn to the six gates)
	local howCf = spotFor(L.MidAngle - 58)
	if howCf then
		local face = noticeBoard(f, howCf, 11, 8, "HowToBoard")
		local gui = surfaceGui(face, Enum.NormalId.Front)
		local panel = signPanel(gui)
		signText(panel, "HOW TO PLAY", "Title", 52, C.TextGold, "Header", 0.04, 0.025, 0.92, 0.14)
		local rows = {
			{ "W A S D", "Move around" },
			{ "SHIFT", "Hold to run" },
			{ "Q", "Dash over wide gaps" },
			{ "SPACE", "Jump" },
			{ "E", "Use a gate" },
		}
		for i, row in ipairs(rows) do
			keyRow(panel, 0.18 + (i - 1) * 0.12, 0.105, row[1], row[2])
		end
		signText(panel, "Walk up the avenue to the GATES!", "Body", SIGN_INFO, C.TextGold, "Footer", 0.05, 0.785, 0.9, 0.19, nil, true)
		gui.Parent = face
	end
	local guideCf = spotFor(L.MidAngle + 58)
	if guideCf then
		local face = noticeBoard(f, guideCf, 11, 8, "GuideBoard")
		local gui = surfaceGui(face, Enum.NormalId.Front)
		local panel = signPanel(gui, rgb(150, 200, 255))
		signText(panel, "THE GATES", "Title", 52, C.TextGold, "Header", 0.04, 0.025, 0.92, 0.14)
		-- Phase 6: the 5 real Gate Court gates (no Home gate any more); the way home is the footer hint
		local lines = {
			{ "OBBY", "Climb with friends" },
			{ "DUNGEON", "Explore with your team" },
			{ "RING", "Beat the champion" },
			{ "ARENA", "Duels and raids" },
			{ "ALTAR", "Secret storm pets!" },
		}
		for i, line in ipairs(lines) do
			keyRow(panel, 0.18 + (i - 1) * 0.12, 0.105, line[1], line[2])
		end
		signText(panel, "Going home?\nTap Home, then Go home!", "Body", SIGN_INFO, C.TextGold, "Footer", 0.05, 0.785, 0.9, 0.19, nil, true)
		gui.Parent = face
	end
end

-- Plaza decor: courts, avenue, fountain, boards, NPC spots, trees, lamps, benches, flower beds.
local function buildPlazaDecor(f, L)
	reserve(L.FountainX, L.FountainZ, 15)
	reserve(0, 0, G.CourtR + 2)

	local fountainPos = Vector3.new(OX + L.FountainX, TOP, OZ + L.FountainZ)
	local okF, errF = pcall(buildFountain, f, fountainPos, Vector3.new(OX, TOP, OZ))
	if not okF then
		warn("[LobbyBuilder] fountain failed: " .. tostring(errF))
	end
	for _, part in ipairs({
		{ "court decor", Court.Decor },
		{ "avenue", Court.Avenue },
		{ "boards", buildBoards },
	}) do
		local ok, err = pcall(part[2], f, L)
		if not ok then
			warn("[LobbyBuilder] " .. part[1] .. " failed: " .. tostring(err))
		end
	end

	-- NPC spots (NpcService builds the pets): on the east / west lawns (6.1: r 62..80, >= 12 studs from any path),
	-- facing the nearest walk.
	L.NpcSpots = {}
	local npcPlan = { 20, 160, 215, 235, 305, 325 }
	for _, a in ipairs(npcPlan) do
		local pos = plazaSpot(a, 70, 5, L, false)
		if not pos then
			pos = plazaSpot(a, 76, 5, L, true)
		end
		L.NpcSpots[#L.NpcSpots + 1] = flatLook(pos, Vector3.new(OX, TOP, OZ))
	end

	local decor = newModel(f, "LawnDecor")
	CollectionService:AddTag(decor, DETAIL_TAG)
	-- Trees on the lawns, between the walks (never near the courts).
	local trees = {
		{ 8, 120, "Round" }, { 36, 130, "Pine" }, { 144, 130, "Pine" }, { 172, 120, "Round" },
		{ 196, 126, "Blossom" }, { 226, 130, "Round" }, { 314, 130, "Round" }, { 344, 126, "Blossom" },
	}
	for i, t in ipairs(trees) do
		local pos = plazaSpot(t[1], t[2], 6, L)
		if pos then
			place(Props.Tree(t[3]), CFrame.new(pos - Vector3.new(0, LAWN, 0)) * CFrame.Angles(0, math.rad(i * 77), 0), decor, t[3] .. "Tree")
		end
	end

	-- Lamps where the walks meet the circle walk and at every exit through the rim.
	local lampTpl = Props.Lamp()
	local lit = 0
	local function lampAt(pos, name, light)
		local lamp = place(lampTpl, CFrame.new(pos), decor, name)
		local glass = lamp and lamp:FindFirstChild("LampGlass")
		if glass and light and lit < 6 then
			lit = lit + 1
			pointLight(glass, C.Lamp, 1.0, 14)
		end
	end
	for _, a in ipairs(L.CrossAngles) do
		for _, s in ipairs({ -1, 1 }) do
			local pos = polar(a, G.RingRoadR - G.PathHalf - 2.2, TOP - LAWN) + dirOf(a + 90) * s * (G.PathHalf + 2)
			lampAt(pos, "WalkLamp", s > 0)
		end
	end
	for _, a in ipairs(L.RimGaps) do
		local half = (angleDiff(a, L.ShopAngle) < 1) and G.BoardHalf or G.StubHalf
		local side = dirOf(a + 90)
		for _, s in ipairs({ -1, 1 }) do
			if s > 0 or angleDiff(a, L.ShopAngle) < 1 then
				lampAt(polar(a, PLAZA_R - 6, TOP - LAWN) + side * s * (half + 1.8), "ExitLamp", angleDiff(a, L.ShopAngle) < 1)
			end
		end
	end

	-- Benches on the inner lawns facing the spawn, flower beds along the circle walk.
	local benchTpl = Props.Bench()
	for _, b in ipairs({ { 50, 44 }, { 130, 44 }, { 200, 44 }, { 340, 44 } }) do
		local pos = plazaSpot(b[1], b[2], 3.5, L)
		if pos then
			place(benchTpl, faceCentre(pos - Vector3.new(0, LAWN, 0)), decor, "Bench")
		end
	end
	local beds = { 30, 150, 190, 250, 290, 350 }
	for i, a in ipairs(beds) do
		local pos = plazaSpot(a, G.RingRoadR - G.PathHalf - 14, 4, L)
		if pos then
			local bed = place(Props.FlowerBed((i - 1) % #FLOWERS + 1), faceCentre(pos - Vector3.new(0, LAWN, 0)), decor, "FlowerBed")
			if bed then
				bed:SetAttribute("FlowerVariant", (i - 1) % #FLOWERS + 1) -- bug #12: the seed drift wears the bed's colours
			end
		end
	end

	-- Fireflies and sparkle dust over the lawns.
	local flies = anchorPart(f, "Fireflies", Vector3.new(OX, TOP + 6, OZ), Vector3.new(PLAZA_R * 1.7, 10, PLAZA_R * 1.7))
	emitter(flies, {
		Color = ColorSequence.new(rgb(255, 236, 150), rgb(190, 240, 170)),
		Rate = 10,
		Lifetime = NumberRange.new(5, 8),
		Speed = NumberRange.new(0.3, 1),
		SpreadAngle = Vector2.new(180, 180),
		Size = popSize(0.45),
	})
end

local function buildPlaza(root, L)
	local f = newFolder(root, "Plaza")
	buildPlazaGround(f, L)
	for _, part in ipairs({ { "court tiles", Court.Tiles }, { "circle walk", Court.RingRoad }, { "edges", Court.Edges } }) do
		local ok, err = pcall(part[2], f, L)
		if not ok then
			warn("[LobbyBuilder] " .. part[1] .. " failed: " .. tostring(err))
		end
	end
	local okBody, errBody = pcall(buildPlazaBody, f, L)
	if not okBody then
		warn("[LobbyBuilder] plaza cloud failed: " .. tostring(errBody))
	end
	local okDecor, errDecor = pcall(buildPlazaDecor, f, L)
	if not okDecor then
		warn("[LobbyBuilder] plaza decor failed: " .. tostring(errDecor))
	end
	return f
end

----------------------------------------------------------------------
-- Phase 5 Gate Court gates (6.1 / 6.2): Obby and Altar are built here with WorldStyle.BuildGate into the
-- Gates folder; Ring / Arena (ArenaBuilder) and Dungeon (DungeonBuilder, W3) stand at LobbyInfo.GateSites.
----------------------------------------------------------------------
local Gates = {}

Gates.Info = {
	Obby = { Title = "Sky Obby", Info = "Climb the clouds", Pad = true },
	Altar = { Title = "Storm Altar", Info = "The secret roulette", Pad = false },
}
Gates.Built = { "Obby", "Altar" } -- the lobby's own gates, in Build order (Phase 6: no Home gate)

function Gates.Spec(id)
	for _, s in ipairs(GATE_SPECS) do
		if s.Id == id then
			return s
		end
	end
	return GATE_SPECS[1]
end

-- Ground CFrame of every gate centre on the arc (LookVector = towards the plaza centre).
function Gates.Sites(L)
	local sites = {}
	for _, id in ipairs(L.GateOrder) do
		sites[id] = faceCentre(polar(L.GateAngles[id], G.GateR, TOP))
	end
	return sites
end

-- A plain gate when WorldStyle is missing or BuildGate throws: two columns, a lintel, the pad / step, the prompt anchor
-- and a pixel tag (the same names as BuildGate, so GateService / PortalService work unchanged).
function Gates.Fallback(parent, site, id, info, color)
	local model = newModel(parent, "Portal_" .. id)
	model:SetAttribute("GateId", id)
	for side = -1, 1, 2 do
		box(model, "Column", site * CFrame.new(side * 8.2, 8, 0), Vector3.new(2.4, 16, 2.4), C.Marble, { Collide = true })
	end
	local lintel = box(model, "Lintel", site * CFrame.new(0, 17.4, 0), Vector3.new(21.4, 2.4, 3), C.Slate, { Collide = true })
	box(model, "PortalDisc", site * CFrame.new(0, 8, 0), Vector3.new(13, 14, 0.2), color, { Material = MAT.Neon, Transparency = 0.35, Shadow = false })
	local pad
	if info.Pad then
		pad = box(model, "Pad", site * CFrame.new(0, 0.3, -14), Vector3.new(14, 0.6, 14), C.Slate, { Collide = true })
	else
		pad = box(model, "Step", site * CFrame.new(0, 0.15, -6), Vector3.new(10, 0.3, 6), C.Slate, { Collide = true })
	end
	local prompt = box(model, "PromptAnchor", site * CFrame.new(0, 3, -2.2), Vector3.new(2, 2, 1), C.Slate, { Transparency = 1, Shadow = false })
	local gui = newTag(lintel, "GateTag", 420, 150, 27 - 17.4, 120)
	local plate = tagPlate(gui, color, 190, Enum.FillDirection.Vertical, 2)
	tagText(plate, "Title", info.Title, "Heading", 28, rgb(255, 255, 255), 1)
	tagText(plate, "Info", info.Info, "Body", 20, C.TextDim, 2)
	local pill = tagPill(plate, "Pill", "", "Label", 18, color:Lerp(C.Ink, 0.55), 3)
	pill.Visible = false
	model.PrimaryPart = lintel
	return model, pad, prompt
end

-- One gate of the court -> { Model, Pad, PromptPart }.
function Gates.BuildOne(parent, site, id)
	local spec = Gates.Spec(id)
	local info = Gates.Info[id] or { Title = id, Info = "", Pad = false }
	local ok, model, pad, prompt = false, nil, nil, nil
	if WorldStyle and type(WorldStyle.BuildGate) == "function" then
		ok, model, pad, prompt = pcall(WorldStyle.BuildGate, parent, site, {
			Id = id,
			Title = info.Title,
			Info = info.Info,
			Color = spec.Accent,
			Glyph = spec.Glyph,
			Pad = info.Pad,
			Name = "Portal_" .. id,
		})
		if not ok then
			warn("[LobbyBuilder] gate " .. id .. " failed: " .. tostring(model))
			local broken = parent:FindFirstChild("Portal_" .. id)
			if broken then
				broken:Destroy()
			end
		end
	end
	if not ok or not model then
		model, pad, prompt = Gates.Fallback(parent, site, id, info, gateAccent(spec.Accent))
	end
	return { Model = model, Pad = pad, PromptPart = prompt, Site = site }
end

-- The Obby portal's PortalInfo: the gate + the PortalService zone on its pad (14 x 6 x 14, floor flush with the pad,
-- -Z facing the plaza) and the gate's pixel tag (PortalService writes the live party state into it).
function Gates.ObbyPortal(gate)
	local pad = gate.Pad
	local top = pad.Position.Y + pad.Size.Y / 2
	local zonePos = Vector3.new(pad.Position.X, top + 3, pad.Position.Z)
	local zone = box(gate.Model, "Zone_Obby", faceCentre(zonePos), Vector3.new(14, 6, 14), C.Slate, { Transparency = 1, Shadow = false })
	zone.CanQuery = false
	zone:SetAttribute("PortalId", "Obby")
	local tag = gate.Model:FindFirstChild("GateTag", true)
	local plate = tag and tag:FindFirstChild("Plate")
	local pill = plate and plate:FindFirstChild("Pill")
	return {
		Id = "Obby",
		Model = gate.Model,
		Zone = zone,
		Center = zone.Position,
		Pad = pad,
		PromptPart = gate.PromptPart,
		Billboard = tag,
		TitleLabel = plate and plate:FindFirstChild("Title"),
		InfoLabel = plate and plate:FindFirstChild("Info"),
		StatusPill = pill,
		StatusLabel = pill and (pill:FindFirstChild("Label") or pill:FindFirstChild("PillLabel")),
	}
end

----------------------------------------------------------------------
-- Shop island: four gacha-style roulette machines, the item stall, a rarity board, a token statue
----------------------------------------------------------------------

-- Size (studs) of the name + price card floating above every roulette machine.
local MACHINE_CARD_W = 14
local MACHINE_CARD_H = 7.6
local machineBoxCache = nil

-- Pixel tag of a roulette machine: the name in the roulette colour + a gold price. The machines stand ~15 studs
-- apart, so the tags hide beyond 60 studs (constant-size tags of neighbours would overlap on screen from afar).
local function machineTag(anchor, roulette, lift)
	local color = roulette.Color or C.Rose
	local gui = newTag(anchor, "PriceBillboard", 320, 110, lift, 60)
	local plate = tagPlate(gui, color, 160)
	tagText(plate, "NameLabel", roulette.DisplayName or roulette.Id, "Title", 26, color:Lerp(C.Text, 0.55), 1)
	tagText(plate, "PriceLabel", priceText(roulette.Price or 0), "Display", 24, C.TextGold, 2)
	return gui
end

-- Rarities (in Config order) that a roulette can actually pay out.
local function oddsRarities(roulette)
	local list = {}
	for _, rarity in ipairs(Config.Rarities) do
		if roulette.Odds and (roulette.Odds[rarity.Id] or 0) > 0 then
			list[#list + 1] = rarity
		end
	end
	return list
end

-- the P4 machine colours: the roulette colour on the cabinet, gold trims, cream wheel segments, a glass dome
local function machinePalette(roulette)
	local color = roulette.Color or C.Rose
	local pal = {
		Base = C.Iron,
		Body = color,
		Trim = C.Gold,
		Seg1 = color:Lerp(rgb(255, 255, 255), 0.45),
		Seg2 = C.Cream,
		Rim = C.GoldDark,
		Hub = C.Gold,
		Dark = rgb(42, 46, 70),
		Glass = { Color = rgb(214, 236, 255), Material = MAT.Glass, Transparency = 0.55 },
		Bulb = { Color = C.Lamp, Material = MAT.Neon },
		Knob = { Color = color, Material = MAT.Neon },
		Iron = C.IronLight,
	}
	local rarities = oddsRarities(roulette)
	for i = 1, 4 do
		local r = rarities[(i - 1) % math.max(1, #rarities) + 1]
		pal["Egg" .. i] = (r and r.Color) or color
	end
	return pal
end

-- The machine is sculpted and merged once; each roulette builds it with its own colours. Front = -Z.
-- Two resolutions: the cabinet, wheel and lever in fine half-stud voxels, the glass dome in 1-stud voxels
-- (translucent voxels cannot hide behind each other, so a coarse dome keeps the part count sane).
local function machineBoxes()
	if machineBoxCache then
		return machineBoxCache
	end
	local g = Voxel.NewGrid(28)
	VX.RoundRect(g, 0, 0, 18, 14, 3, 0, 1, "Base")
	VX.RoundRect(g, 0, 0, 15, 11, 2, 2, 2, "Trim")
	VX.RoundRect(g, 0, 0, 14, 10, 2, 3, 10, "Body")
	VX.RoundRect(g, 0, 0, 15, 11, 2, 11, 11, "Trim")
	VX.RoundRect(g, 0, 0, 8, 8, 2, 12, 13, "Trim")
	-- the prize wheel on the front: eight coloured segments, a gold rim and hub, a red pointer on top
	local wy = 7
	for x = -4, 4 do
		for y = 3, 11 do
			local dy = y - wy
			local d = math.sqrt(x * x + dy * dy)
			if d <= 3.7 then
				local key
				if d <= 1.0 then
					key = "Hub"
				elseif d >= 2.9 then
					key = "Rim"
				else
					local seg = math.floor((atan2(dy, x) + math.pi) / (math.pi / 4))
					key = (seg % 2 == 0) and "Seg1" or "Seg2"
				end
				Voxel.Set(g, x, y, -6, key)
			end
		end
	end
	Voxel.Set(g, 0, 11, -6, "Knob")
	Voxel.Set(g, 0, 11, -7, "Knob")
	-- prize chute + gold tray, marquee bulbs on the top band
	VX.Fill(g, -2, 2, 3, 3, -6, -6, "Dark")
	VX.Fill(g, -2, 2, 2, 2, -7, -6, "Trim")
	for _, x in ipairs({ -6, -3, 3, 6 }) do
		Voxel.Set(g, x, 11, -6, "Bulb")
	end
	-- lever on the right side
	Voxel.Shape(g, { Kind = "Capsule", A = { 7.4, 6, 0 }, B = { 9, 12, 0 }, Radius = 0.6, Key = "Iron" })
	Voxel.Shape(g, { Kind = "Ellipsoid", Center = { 9, 13.2, 0 }, Radius = 1.3, Key = "Knob" })
	Voxel.Shade(g, {
		Skip = { Bulb = true, Seg1 = true, Seg2 = true, Hub = true, Rim = true, Dark = true, Knob = true },
		Smooth = 1,
		Seed = 12,
	})

	-- the glass dome full of pet eggs (1-stud voxels), sitting on the neck
	local d = Voxel.NewGrid(8)
	Voxel.Shape(d, { Kind = "Ellipsoid", Center = { 0, 9.4, 0 }, Radius = { 3.1, 2.9, 3.1 }, Key = "Glass" })
	local eggs = { { -1.2, 8.1, -0.9 }, { 1.2, 8.2, 0.7 }, { 0.2, 9.8, -1.3 }, { -0.9, 10, 1.1 }, { 1.4, 9.9, -0.2 }, { -0.1, 8.4, 1.6 } }
	for i, e in ipairs(eggs) do
		Voxel.Shape(d, { Kind = "Ellipsoid", Center = e, Radius = { 0.75, 0.95, 0.75 }, Key = "Egg" .. ((i - 1) % 4 + 1), Bias = 0.15 })
	end
	VX.RoundRect(d, 0, 0, 3, 3, 0.8, 12, 12, "Trim")
	Voxel.Set(d, 0, 13, 0, "Bulb")
	local pal = machinePalette(Config.Roulettes[1] or { Color = C.Rose })
	-- LOD only folds shade variants (the coloured keys differ per roulette, so they are kept as they are)
	local keep = { "Body", "Trim", "Seg1", "Seg2", "Rim", "Hub", "Glass", "Egg1", "Egg2", "Egg3", "Egg4", "Bulb", "Knob", "Base", "Iron", "Dark" }
	machineBoxCache = {
		Fine = Voxel.Merge(g, { Palette = pal, MaxParts = 70, Keep = keep }),
		Dome = Voxel.Merge(d, { Palette = pal, Keep = keep }),
	}
	return machineBoxCache
end

-- A gacha roulette machine (Model Roulette_<Id>). `cf` sits on the ground; LookVector = towards the customer.
local function buildMachine(parent, cf, roulette)
	local model = newModel(parent, "Roulette_" .. roulette.Id)
	local body = Instance.new("Model")
	body.Name = "Machine"
	-- the sculpt's front (-Z) faces along cf.LookVector (the customer)
	local boxes = machineBoxes()
	local pal = machinePalette(roulette)
	Voxel.BuildBoxes(boxes.Fine, { VoxelSize = 0.5, Palette = pal, CFrame = cf * CFrame.new(0, 0.25, 0), Model = body, CanCollide = true, CanQuery = true })
	Voxel.BuildBoxes(boxes.Dome, { VoxelSize = 1, Palette = pal, CFrame = cf * CFrame.new(0, 0.5, 0), Model = body, CanCollide = true, CanQuery = true })
	body.Parent = model
	-- Phase 6: one cabinet design for every roulette (cabinet + knob = the roulette colour, eggs = its top rarity)
	local rarities = oddsRarities(roulette)
	local top = rarities[#rarities]
	Mesh.tag(body, "prop_roulette", cf, { Primary = roulette.Color or C.Rose, Secondary = (top and top.Color) or C.Gold })
	local cabinet = nil
	for _, d in ipairs(body:GetChildren()) do
		if d:IsA("BasePart") and d.Name == "Body" and (not cabinet or d.Size.Magnitude > cabinet.Size.Magnitude) then
			cabinet = d
		end
	end
	local glow = anchorPart(model, "DomeGlow", (cf * CFrame.new(0, 9.5, 0)).Position)
	pointLight(glow, roulette.Color or C.Lamp, 0.9, 18)
	emitter(glow, {
		Color = ColorSequence.new((roulette.Color or C.Rose):Lerp(rgb(255, 255, 255), 0.4), C.TextGold),
		Rate = 3,
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(180, 180),
		Size = popSize(0.5),
	})

	-- Name + price tag standing on the dome.
	local anchor = anchorPart(model, "PriceAnchor", (cf * CFrame.new(0, 14.2 + MACHINE_CARD_H * 0.5, 0)).Position)
	machineTag(anchor, roulette, 0.5 - MACHINE_CARD_H * 0.5)

	-- Invisible spot in front where PetService hangs the ProximityPrompt.
	local prompt = box(model, "PromptPart", cf * CFrame.new(0, 2, -5.4), Vector3.new(5, 4, 3), roulette.Color or C.Rose, { Transparency = 1, Shadow = false })
	prompt.CanQuery = false
	model.PrimaryPart = cabinet or prompt
	return {
		Id = roulette.Id,
		PromptPart = prompt,
		Center = (cf * CFrame.new(0, 3.5, 0)).Position,
		Model = model,
	}
end

local function fallbackMachine(parent, cf, roulette)
	local old = parent:FindFirstChild("Roulette_" .. roulette.Id)
	if old then
		old:Destroy()
	end
	local model = newModel(parent, "Roulette_" .. roulette.Id)
	local cabinet = box(model, "Cabinet", cf * CFrame.new(0, 3, 0), Vector3.new(7, 6, 5), roulette.Color or C.Rose, { Collide = true })
	local anchor = anchorPart(model, "PriceAnchor", (cf * CFrame.new(0, 10, 0)).Position)
	machineTag(anchor, roulette, -2.5)
	local prompt = box(model, "PromptPart", cf * CFrame.new(0, 2, -5), Vector3.new(5, 4, 3), C.Cloud, { Transparency = 1, Shadow = false })
	model.PrimaryPart = cabinet
	return { Id = roulette.Id, PromptPart = prompt, Center = cabinet.Position, Model = model }
end

-- Striped market stall with goods on the shelf (Model ItemShop). Front (-Z of the sculpt) faces the customer.
local function buildItemStall(parent, cf)
	local model = newModel(parent, "ItemShop")
	local g = Voxel.NewGrid(14)
	VX.RoundRect(g, 0, 0, 10, 3, 0.6, 0, 2, "Wood")
	VX.RoundRect(g, 0, 0, 11, 4, 0.8, 3, 3, "Top")
	for x = -4, 4 do
		for y = 0, 2 do
			Voxel.Set(g, x, y, -2, (math.floor((x + 4) / 1) % 2 == 0) and "Rose" or "Cream")
		end
	end
	VX.Fill(g, -5, 5, 0, 8, 3, 3, "WoodDark")
	VX.Fill(g, -4, 4, 5, 5, 2, 2, "Wood")
	for _, sx in ipairs({ -6, 6 }) do
		VX.Fill(g, sx, sx, 0, 8, -3, -3, "Post")
		VX.Fill(g, sx, sx, 0, 10, 3, 3, "Post")
	end
	-- striped awning in three steps, sloping down to the front, with a scalloped fringe
	for x = -7, 7 do
		local stripe = (math.floor((x + 7) / 2) % 2 == 0) and "Rose" or "Cream"
		for z = -4, 4 do
			local y = 9 + math.floor((z + 4) / 3)
			Voxel.Set(g, x, y, z, stripe)
		end
		if x % 2 == 0 then
			Voxel.Set(g, x, 8, -4, stripe)
		end
	end
	-- goods: heal cloud, shield bubble, phoenix feather on the shelf; coins on the counter
	Voxel.Shape(g, { Kind = "Ellipsoid", Center = { -3, 6.5, 2 }, Radius = { 1.3, 0.8, 0.6 }, Key = "Heal" })
	Voxel.Shape(g, { Kind = "Ellipsoid", Center = { 0, 6.7, 2 }, Radius = { 0.9, 0.9, 0.6 }, Key = "Shield" })
	Voxel.Shape(g, { Kind = "Curve", Points = { { 2.6, 6, 2 }, { 3.2, 7, 2 }, { 3.5, 8.1, 2 } }, Radius = 0.45, RadiusB = 0.2, Key = "Feather" })
	Voxel.Set(g, 3, 8, 2, "Gold")
	Voxel.Set(g, 2, 4, 0, "Gold")
	Voxel.Set(g, 3, 4, -1, "Gold")
	Voxel.Set(g, -3, 4, 0, "Heal")
	Voxel.Shade(g, { Skip = { Shield = true, Rose = true, Cream = true }, Smooth = 1, Seed = 13 })
	local stallModel = VX.Build(g, {
		V = 1,
		Name = "Stall",
		CF = cf * CFrame.new(0, 0.5, 0),
		Collide = true,
		Parent = model,
		Pal = {
			Wood = P.Plank,
			WoodDark = P.PlankDark,
			Post = P.PlankDark,
			Top = { Color = C.Cream, Material = materialOf("Fabric") },
			Rose = { Color = C.Rose, Material = materialOf("Fabric") },
			Cream = { Color = C.Cream, Material = materialOf("Fabric") },
			Heal = { Color = rgb(124, 214, 150), Material = materialOf("Glass") },
			Shield = { Color = rgb(120, 184, 250), Material = MAT.Glass, Transparency = 0.35 },
			Feather = rgb(244, 136, 70),
			Gold = C.Gold,
		},
		MaxParts = 80,
	})
	if stallModel then
		Mesh.tag(stallModel, "prop_item_stall", cf) -- Phase 6
	end
	-- Phase 6 / HUD cleanup: the stall is decoration, boarded up (no prompt). Two dark planks cross the counter front;
	-- each end is nailed to a front post (x +-6, front face z -3.5; the mesh dress has the same posts), and they sit in
	-- their own Model Boards beside the mesh-tagged Stall, so the Phase 6 mesh dress leaves them in place.
	local boards = newModel(model, "Boards")
	box(boards, "Plank1", cf * CFrame.new(0, 5, -3.68) * CFrame.Angles(0, 0, math.rad(28)), Vector3.new(13.4, 0.9, 0.35), P.PlankDark.Color, { Collide = false })
	box(boards, "Plank2", cf * CFrame.new(0, 5, -3.68) * CFrame.Angles(0, 0, -math.rad(28)), Vector3.new(13.4, 0.9, 0.35), P.PlankDark.Color, { Collide = false })
	local lamp = anchorPart(model, "StallLight", (cf * CFrame.new(0, 7.5, 0)).Position)
	pointLight(lamp, C.Lamp, 0.8, 16)

	-- name tag standing on the awning (bottom edge 13.3 studs up)
	local anchor = anchorPart(model, "SignAnchor", (cf * CFrame.new(0, 15.5, 0)).Position)
	local bb = newTag(anchor, "ItemShopBillboard", 320, 110, -2.2, 80)
	local plate = tagPlate(bb, C.Rose, 160)
	tagText(plate, "NameLabel", "Item Shop", "Title", TAG_NAME, C.Text, 1)
	tagText(plate, "SubLabel", "Closed", "Body", TAG_INFO, C.Text, 2, 2)

	local prompt = box(model, "PromptPart", cf * CFrame.new(0, 2, -4.6), Vector3.new(5, 4, 3), C.Cloud, { Transparency = 1, Shadow = false })
	local counter = model:FindFirstChild("Stall")
	model.PrimaryPart = (counter and counter.PrimaryPart) or prompt
	return { PromptPart = prompt, Center = (cf * CFrame.new(0, 1.7, 0)).Position, Model = model }
end

local function fallbackItemStall(parent, cf)
	local old = parent:FindFirstChild("ItemShop")
	if old then
		old:Destroy()
	end
	local model = newModel(parent, "ItemShop")
	local counter = box(model, "Counter", cf * CFrame.new(0, 1.7, 0), Vector3.new(9, 3.4, 3.2), C.Plank, { Collide = true })
	local prompt = box(model, "PromptPart", cf * CFrame.new(0, 2, -4.6), Vector3.new(5, 4, 3), C.Cloud, { Transparency = 1, Shadow = false })
	model.PrimaryPart = counter
	return { PromptPart = prompt, Center = counter.Position, Model = model }
end

-- Board that explains the roulettes: price, and which rarities each one can give.
local function buildRarityBoard(parent, cf)
	-- 700 x 450 px canvas (14 x 9 studs): a 1-stud header, then one row per roulette: the name and the price
	-- (0.6 stud) over rarity pills that spell out what it can pay (0.6 stud)
	local face = noticeBoard(parent, cf, 14, 9, "RarityBoard")
	local gui = surfaceGui(face, Enum.NormalId.Front)
	local panel = signPanel(gui)
	local H = 450
	signText(panel, "WINGED PETS", "Title", 50, C.Gold, "Header", 0.04, 6 / H, 0.92, 54 / H)
	signText(panel, "Pricier roulette = rarer pets", "Body", SIGN_INFO, C.Text, "Sub", 0.04, 60 / H, 0.92, 34 / H)
	for i, roulette in ipairs(Config.Roulettes) do
		local top = 102 + (i - 1) * 84
		local y = top / H
		local color = roulette.Color or C.Rose
		signText(panel, roulette.DisplayName or roulette.Id, "Heading", SIGN_INFO, color:Lerp(C.Text, 0.35), "Name" .. i, 0.04, y, 0.6, 36 / H, Enum.TextXAlignment.Left)
		signText(panel, priceText(roulette.Price or 0), "Body", SIGN_INFO, C.TextGold, "Price" .. i, 0.6, y, 0.36, 36 / H, Enum.TextXAlignment.Right)
		local pills = plainFrame(panel, "Rarities" .. i, {
			Position = UDim2.new(0.04, 0, (top + 38) / H, 0),
			Size = UDim2.new(0.92, 0, 36 / H, 0),
		})
		local layout = listLayout(pills, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		for k, rarity in ipairs(oddsRarities(roulette)) do
			local pill = tagPill(pills, "Rarity_" .. rarity.Id, rarity.Id, "Body", SIGN_INFO, rarity.Color:Lerp(C.Navy, 0.18), k)
			local pad = pill:FindFirstChildOfClass("UIPadding")
			if pad then -- a slim pill: the row keeps a clear gap to the next roulette
				pad.PaddingTop = UDim.new(0, 0)
				pad.PaddingBottom = UDim.new(0, 0)
			end
			pill.Size = UDim2.fromOffset(0, 34)
		end
	end
	gui.Parent = face
end

-- A big decorative voxel coin with a cloud emblem on a pedestal (NOT a collectible token).
local function buildTokenStatue(parent, ground)
	local m = newModel(parent, "TokenStatue")
	local g = Voxel.NewGrid(12)
	VX.RoundRect(g, 0, 0, 6, 6, 1.2, 0, 1, "StoneLight")
	VX.RoundRect(g, 0, 0, 4.4, 4.4, 1, 2, 2, "Stone")
	for x = -4, 4 do
		for y = -4, 4 do
			local d = math.sqrt(x * x + y * y)
			if d <= 4.3 then
				local key = (d >= 3.4) and "GoldDark" or "Gold"
				Voxel.Set(g, x, 7 + y, 0, key)
			end
		end
	end
	-- the cloud emblem in relief on both faces
	local emblem = {}
	for _, row in ipairs({ { 2, -1, 0 }, { 1, -2, 2 }, { 0, -3, 3 }, { -1, -2, 2 } }) do
		for x = row[2], row[3] do
			emblem[#emblem + 1] = { x, row[1] }
		end
	end
	for _, e in ipairs(emblem) do
		Voxel.Set(g, e[1], 7 + e[2], -1, "GoldGlow")
		Voxel.Set(g, e[1], 7 + e[2], 1, "GoldGlow")
	end
	VX.Fill(g, -1, 1, 3, 3, 0, 0, "GoldDark")
	Voxel.Shade(g, { Only = { StoneLight = true, Stone = true }, Smooth = 1 })
	local coinCf = flatLook(ground, Vector3.new(OX, ground.Y, OZ))
	local coin = VX.Build(g, { V = 1, Name = "Coin", CF = coinCf * CFrame.new(0, 0.5, 0), Collide = true, Parent = m })
	if coin then
		Mesh.tag(coin, "prop_token_statue", coinCf) -- Phase 6
	end
	local sparkle = anchorPart(m, "CoinSparkle", ground + Vector3.new(0, 7, 0), Vector3.new(6, 6, 2))
	emitter(sparkle, { Rate = 5, Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180), Size = popSize(0.6) })
	return m
end

local function buildShop(root, L)
	local f = newFolder(root, "Shop")
	local S = L.ShopCenter
	local R = L.ShopR
	local shopCF = flatLook(S, Vector3.new(OX, TOP, OZ)) -- local -Z = towards the plaza (the entrance)
	local function at(x, z)
		return (shopCF * CFrame.new(x, 0, z)).Position
	end
	local function local2(wx, wz)
		local p = shopCF:PointToObjectSpace(Vector3.new(S.X + wx, TOP, S.Z + wz))
		return p.X, p.Z
	end
	local rng = Util.NewRng(SEED + 4)

	-- Ground layers (2-stud cells): lawn, patches + flowers, borders, the stone court + entrance path, inlays.
	local cell = 2
	local n = math.ceil(R / cell)
	local grids = { Voxel.NewGrid(1), Voxel.NewGrid(1), Voxel.NewGrid(1), Voxel.NewGrid(1), Voxel.NewGrid(1) }
	for i = -n, n do
		for k = -n, n do
			local wx, wz = i * cell, k * cell
			local r = math.sqrt(wx * wx + wz * wz)
			if r <= R - 0.5 then
				local x, z = local2(wx, wz)
				Voxel.Set(grids[1], i, 0, k, "Grass")
				local nz = vnoise(wx + 50, wz + 50, 22, 31)
				if r > R - 3 then
					nz = 0.5 -- lawn only at the very edge
				end
				if nz < 0.26 then
					Voxel.Set(grids[2], i, 0, k, "GrassDark")
				elseif nz > 0.76 then
					Voxel.Set(grids[2], i, 0, k, "GrassLight")
				end
				local court = r <= 21
				local path = z < 0 and math.abs(x) <= 7
				if court or path then
					Voxel.Set(grids[3], i, 0, k, "StoneEdge")
				end
				if r <= 19 or (z < 0 and math.abs(x) <= 5) then
					Voxel.Set(grids[4], i, 0, k, "Stone")
				end -- (bug #12: the rim's flat flower pixels became Meadow clumps)
				if r <= 19 then
					if r >= 12 and r <= 13.5 then
						Voxel.Set(grids[5], i, 0, k, "StoneLight")
					elseif r >= 4.5 and r <= 6.5 then
						Voxel.Set(grids[5], i, 0, k, "GoldDark")
					end
				end
			end
		end
	end
	local tops = { -0.4, -0.3, -0.1, 0, 0.1 }
	for li = 1, 5 do
		local layer = VX.Build(grids[li], { V = cell, Name = "Ground" .. li, CF = CFrame.new(S.X, TOP + tops[li] - cell / 2, S.Z), Collide = true, Shadow = false, Parent = f })
		if layer then
			Mesh.tag(layer, "floor_shop_" .. li, CFrame.new(S.X, TOP, S.Z)) -- Phase 6 (LayoutSig)
		end
	end

	-- The shop's cloud body + the stone neck to the plaza.
	local okBody, errBody = pcall(function()
		local rim = {}
		for i = 1, 9 do
			local a = (i - 1) / 9 * 360 + rng:Float(-5, 5)
			local wx, wz = math.cos(math.rad(a)) * (R + 1.5), math.sin(math.rad(a)) * (R + 1.5)
			local _, lz = local2(wx, wz)
			if lz > -R * 0.55 then
				local s = rng:Float(8, 10)
				rim[#rim + 1] = { wx, rng:Float(-1, 1), wz, s, s * 0.6, s }
			end
		end
		local puffs = {}
		for i = 1, 6 do
			local a = (i - 1) / 6 * math.pi * 2 + rng:Float(-0.3, 0.3)
			local s = rng:Float(7, 11)
			puffs[#puffs + 1] = { math.cos(a) * (R - 6), -7, math.sin(a) * (R - 6), s, s * 0.7, s }
		end
		local shopCloud = VX.CloudModel({
			V = 3,
			Tiers = { { R = R + 3, H = 1 }, { R = R - 3, H = 2 }, { R = R - 11, H = 2 }, { R = R - 19, H = 2 } },
			Puffs = puffs,
			Rim = rim,
			Carve = function(x, y, z)
				return y > 0 and (x * x + z * z) < (R - 4) * (R - 4)
			end,
			Seed = 5,
			MaxParts = 84,
		}, CFrame.new(S.X, TOP - 1.2, S.Z), f, "ShopCloud", true)
		if shopCloud then
			Mesh.tag(shopCloud, "cloud_shop", CFrame.new(S.X, TOP - 1.2, S.Z)) -- Phase 6 (LayoutSig)
		end
	end)
	if not okBody then
		warn("[LobbyBuilder] shop cloud failed: " .. tostring(errBody))
	end
	local neckA = polar(L.ShopAngle, PLAZA_R - 4, TOP)
	local neckB = polar(L.ShopAngle, L.ShopDist - R + 5, TOP)
	local neckMid = (neckA + neckB) * 0.5
	box(f, "ShopNeck", flatLook(neckMid, neckB) * CFrame.new(0, -0.2 - 0.6, 0), Vector3.new(G.BoardHalf * 2 - 0.3, 1.2, (neckB - neckA).Magnitude), C.Stone, { Collide = true })
	place(Props.Puff("S"), CFrame.new(neckMid - Vector3.new(0, 1.4, 0)), f, "NeckPuff")

	-- Roulette machines on an arc across the back, cheapest on the left as the customer walks in.
	local roulettes = {}
	local count = #Config.Roulettes
	local arcR = 19
	local stepDeg = math.deg(2 * math.asin(math.min(1, (MACHINE_CARD_W + 1) / (2 * arcR))))
	if count > 1 then
		stepDeg = math.min(stepDeg, 150 / (count - 1))
	end
	for i, roulette in ipairs(Config.Roulettes) do
		local phi = math.rad((i - (count + 1) / 2) * stepDeg)
		local pos = at(-math.sin(phi) * arcR, math.cos(phi) * arcR)
		local cf = flatLook(pos, S)
		local ok, result = pcall(buildMachine, f, cf, roulette)
		if not ok then
			warn("[LobbyBuilder] roulette machine " .. tostring(roulette.Id) .. " failed: " .. tostring(result))
			result = fallbackMachine(f, cf, roulette)
		end
		roulettes[roulette.Id] = result
	end

	-- Item stall (left of the entrance) and rarity board (right), both facing the centre.
	local stallPos = at(-21, -8) - Vector3.new(0, LAWN, 0) -- on the lawn layer
	local stallCF = flatLook(stallPos, S - Vector3.new(0, LAWN, 0))
	local okStall, stall = pcall(buildItemStall, f, stallCF)
	if not okStall then
		warn("[LobbyBuilder] item stall failed: " .. tostring(stall))
		stall = fallbackItemStall(f, stallCF)
	end
	local okBoard, errBoard = pcall(buildRarityBoard, f, flatLook(at(21, -8) - Vector3.new(0, LAWN, 0), S - Vector3.new(0, LAWN, 0)))
	if not okBoard then
		warn("[LobbyBuilder] rarity board failed: " .. tostring(errBoard))
	end

	-- Decor: token statue, entrance arch with the shop sign, lamps, bunting, flower beds, fireflies.
	local okDecor, errDecor = pcall(function()
		buildTokenStatue(f, S)
		local archCF = shopCF * CFrame.new(0, 0, -(R - 5)) * CFrame.Angles(0, math.pi, 0)
		local arch = newModel(f, "ShopArch")
		for _, s in ipairs({ -1, 1 }) do
			box(arch, "Pillar", archCF * CFrame.new(s * 7.6, 0.35, 0), Vector3.new(2.6, 1.7, 2.6), C.StoneDark, { Collide = true })
			box(arch, "Pillar", archCF * CFrame.new(s * 7.6, 5.6, 0), Vector3.new(1.8, 8.8, 1.8), C.StoneLight, { Collide = true })
			box(arch, "PillarCap", archCF * CFrame.new(s * 7.6, 10.3, 0), Vector3.new(2.6, 0.8, 2.6), C.Rose)
			box(arch, "PillarLamp", archCF * CFrame.new(s * 7.6, 11.2, 0), Vector3.new(1, 1, 1), C.Lamp, { Material = MAT.Neon })
		end
		box(arch, "Beam", archCF * CFrame.new(0, 10.3, 0), Vector3.new(13, 0.6, 1.2), C.PlankDark)
		local sign = box(arch, "ShopSign", archCF * CFrame.new(0, 12.38, 0), Vector3.new(12.4, 3.6, 0.8), C.Navy, { Shadow = true })
		box(arch, "SignRoof", archCF * CFrame.new(0, 14.46, 0), Vector3.new(14, 0.6, 1.8), C.Rose)
		Mesh.tag(arch, "prop_shop_arch", archCF, nil, { "ShopSign" }) -- Phase 6: the sign board stays (SurfaceGuis)
		-- 620 x 180 px canvas: the name 1.6 studs tall, the caption 0.68 stud
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local gui = surfaceGui(sign, face)
			local panel = signPanel(gui, C.TextGold)
			signText(panel, "CLOUD SHOP", "Title", 80, C.Gold, "Name", 0.03, 0.05, 0.94, 0.56)
			signText(panel, "pets & items", "Body", 34, C.Text, "Sub", 0.04, 0.62, 0.92, 0.3)
			gui.Parent = sign
		end
		local lampTpl = Props.Lamp()
		local lampTops = {}
		for i, p in ipairs({ { -9, -13 }, { 9, -13 }, { -25, 6 }, { 25, 6 } }) do
			local base = at(p[1], p[2]) - Vector3.new(0, (i > 2) and LAWN or 0, 0) -- the outer pair stands on the lawn
			local lamp = place(lampTpl, CFrame.new(base), f, "ShopLamp")
			local glass = lamp and lamp:FindFirstChild("LampGlass")
			if glass and i <= 2 then
				pointLight(glass, C.Lamp, 0.8, 16)
			end
			lampTops[i] = base + Vector3.new(0, 7.4, 0)
		end
		bunting(f, lampTops[1], lampTops[2], { C.Rose, C.Cream, C.Gold, rgb(120, 190, 235) }, 1.2)
		local down = Vector3.new(0, LAWN, 0)
		place(Props.FlowerBed(2), flatLook(at(-11.5, -19) - down, S - down) * CFrame.Angles(0, math.rad(90), 0), f, "FlowerBed")
		place(Props.FlowerBed(4), flatLook(at(11.5, -19) - down, S - down) * CFrame.Angles(0, math.rad(90), 0), f, "FlowerBed")
		local flies = anchorPart(f, "Fireflies", S + Vector3.new(0, 5, 0), Vector3.new(R * 1.5, 8, R * 1.5))
		emitter(flies, {
			Color = ColorSequence.new(rgb(255, 236, 150), rgb(190, 240, 170)),
			Rate = 5,
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(0.3, 1),
			SpreadAngle = Vector2.new(180, 180),
			Size = popSize(0.45),
		})
	end)
	if not okDecor then
		warn("[LobbyBuilder] shop decor failed: " .. tostring(errDecor))
	end
	return { Roulettes = roulettes, ItemShop = stall }
end

-- Last-resort shop: plain machines and a counter with their PromptParts, so pets and items stay purchasable.
local function fallbackShop(root, L)
	local f = newFolder(root, "ShopFallback")
	local S = L.ShopCenter
	box(f, "ShopTop", CFrame.new(S - Vector3.new(0, 1, 0)), Vector3.new(L.ShopR * 2, 2, L.ShopR * 2), C.Cloud, { Collide = true })
	local neckA = polar(L.ShopAngle, PLAZA_R - 4, TOP)
	local neckB = polar(L.ShopAngle, L.ShopDist - L.ShopR + 5, TOP)
	local mid = (neckA + neckB) * 0.5
	box(f, "ShopNeck", flatLook(mid, neckB) * CFrame.new(0, -0.8, 0), Vector3.new(14, 1.2, (neckB - neckA).Magnitude), C.Stone, { Collide = true })
	local roulettes = {}
	local count = #Config.Roulettes
	for i, roulette in ipairs(Config.Roulettes) do
		local pos = S + Vector3.new((i - (count + 1) / 2) * 12, 0, -12)
		roulettes[roulette.Id] = fallbackMachine(f, flatLook(pos, S), roulette)
	end
	local stallPos = S + Vector3.new(0, 0, 12)
	local stall = fallbackItemStall(f, flatLook(stallPos, S))
	return { Roulettes = roulettes, ItemShop = stall }
end

----------------------------------------------------------------------
-- Home plots (one per spot) and the ring street
----------------------------------------------------------------------

-- Local positions inside a plot (studs; origin = yard centre on the ground, -Z = gate / street side).
local PLOT_POS = {
	Gate = -G.PlotHalf,
	Mailbox = Vector3.new(-11, 0, -G.PlotHalf - 2),
	Podium = Vector3.new(G.PlotHalf - 12, 0, -G.PlotHalf + 10),
	Spawn = Vector3.new(0, 3, -12),
}

-- Everything every plot shares, built once in plot-local space and cloned per plot.
local function plotTemplate()
	return template("Plot", function()
		local m = Instance.new("Model")
		m.Name = "Plot"
		local half = G.PlotHalf
		local ix = G.IslandHalfX
		local front, back = G.IslandFront, G.IslandBack
		local depth = back - front
		local midZ = (back + front) / 2

		-- cloud island body (top 1.2 under the lawn): a puffy cushion, not a slab. Two flat tiers carry the lawn;
		-- overlapping billows bulge out along both sides and the back (a scalloped outline from above, round
		-- bumps from the side), a hanging cumulus of big lumps rounds the underside off, and a soft rim of
		-- small puffs rises from the outer margins (outside the fence; the yard, verge and street stay clear).
		local rng = Util.NewRng(SEED + 77)
		local puffs, rim = {}, {}
		local sideZ0, sideZ1 = front + 12, back - 8
		for _, sx in ipairs({ -1, 1 }) do
			for i = 0, 3 do
				local z = sideZ0 + i * (sideZ1 - sideZ0) / 3 + rng:Float(-3, 3)
				puffs[#puffs + 1] = { sx * (ix + rng:Float(1, 3)), rng:Float(-5, -3.5), z, rng:Float(8, 10), rng:Float(5.5, 7), rng:Float(10, 12.5) }
			end
			rim[#rim + 1] = { sx * (ix - 1), 0, rng:Float(-12, -4), 6, 4, 8 }
		end
		for i = 0, 2 do
			local x = -ix + 12 + i * (2 * ix - 24) / 2 + rng:Float(-3, 3)
			puffs[#puffs + 1] = { x, rng:Float(-5, -3.5), back + rng:Float(1, 3), rng:Float(12, 14), rng:Float(5.5, 7), rng:Float(8, 10) }
		end
		rim[#rim + 1] = { -ix + 2, 0, back - 1, 10, 6.5, 10 }
		rim[#rim + 1] = { ix - 2, 0, back - 1, 10, 6.5, 10 }
		-- the hanging underside (studs below the top of the cloud)
		local hang = {
			{ 0, -10, midZ, ix * 0.95, 7.5, depth * 0.48 },
			{ ix * 0.1, -15, midZ, 20, 6.5, 22 },
		}
		for _, h in ipairs(hang) do
			puffs[#puffs + 1] = h
		end
		-- 6-stud voxels: the island is cloned 16 times, so its body must stay cheap (~56 parts)
		VX.CloudModel({
			V = 6,
			Tiers = {
				{ SX = ix * 2 + 4, SZ = depth + 4, Z = midZ, Round = 10, H = 1 },
			},
			Puffs = puffs,
			Rim = rim,
			-- nothing may rise above the yard, the verge or the street
			Carve = function(x, y, z)
				return y > 0 and ((math.abs(x) < G.PlotHalf + 1.5 and z < G.PlotHalf + 1.5 and z > -G.PlotHalf - G.Verge - 1) or (z <= -G.PlotHalf - G.Verge - 1 and z > front - 3 and math.abs(x) < ix + 6))
			end,
			MaxParts = 80,
			Seed = 9,
		}, CFrame.new(0, -1.2, 0), m, "Island", true)

		-- mowed lawn stripes in the yard + darker margins and verge (all flush at the walking height)
		local stripeW = PLOT / 6
		for i = 1, 6 do
			local z = -half + (i - 0.5) * stripeW
			box(m, "Yard", CFrame.new(0, -0.5, z), Vector3.new(PLOT, 1, stripeW), (i % 2 == 0) and C.GrassLight or C.Grass, { Collide = true, Shadow = false })
		end
		local verge = G.Verge
		box(m, "Margin", CFrame.new(-(half + ix) / 2, -0.5, (back + (-half - verge)) / 2), Vector3.new(ix - half, 1, back + half + verge), C.GrassDark, { Collide = true, Shadow = false })
		box(m, "Margin", CFrame.new((half + ix) / 2, -0.5, (back + (-half - verge)) / 2), Vector3.new(ix - half, 1, back + half + verge), C.GrassDark, { Collide = true, Shadow = false })
		box(m, "Margin", CFrame.new(0, -0.5, (back + half) / 2), Vector3.new(PLOT, 1, back - half), C.GrassDark, { Collide = true, Shadow = false })
		box(m, "Verge", CFrame.new(0, -0.5, -half - verge / 2), Vector3.new(PLOT, 1, verge), C.GrassDark, { Collide = true, Shadow = false })
		-- stepping stones from the gate into the yard
		for i, z in ipairs({ -half + 2.5, -half + 6.5, -half + 10.5 }) do
			box(m, "SteppingStone", CFrame.new((i % 2 == 0) and 0.6 or -0.4, 0.05, z), Vector3.new(4, 0.1, 2.6), C.StoneLight, { Collide = true, Shadow = false })
		end

		-- the street in front: stone slabs in two shades with darker curbs
		local sw = G.StreetW
		local slabs = 4
		local slabLen = (ix * 2) / slabs
		for i = 1, slabs do
			local x = -ix + (i - 0.5) * slabLen
			box(m, "Street", CFrame.new(x, -0.5, G.StreetZ), Vector3.new(slabLen, 1, sw - 3), (i % 2 == 0) and C.StoneLight or C.Stone, { Collide = true, Shadow = false })
		end
		for _, s in ipairs({ -1, 1 }) do
			box(m, "Curb", CFrame.new(0, -0.5, G.StreetZ + s * (sw / 2 - 0.75)), Vector3.new(ix * 2, 1, 1.5), C.StoneDark, { Collide = true, Shadow = false })
		end
		-- low hedge along the plaza side of the street (keeps walkers from stepping off the island)
		box(m, "Hedge", CFrame.new(0, 0.9, front - 0.9), Vector3.new(ix * 2, 1.8, 1.8), C.Hedge, { Collide = true })
		box(m, "HedgeTop", CFrame.new(0, 1.9, front - 0.9), Vector3.new(ix * 2 - 1, 0.4, 1.3), C.HedgeLight)

		-- fence posts + rails around the yard, open at the gate
		local postSpots = {}
		for _, x in ipairs({ -half, -half / 3, half / 3, half }) do
			postSpots[#postSpots + 1] = { x, half }
		end
		for _, z in ipairs({ -half / 3, half / 3 }) do
			postSpots[#postSpots + 1] = { -half, z }
			postSpots[#postSpots + 1] = { half, z }
		end
		postSpots[#postSpots + 1] = { -half, -half }
		postSpots[#postSpots + 1] = { half, -half }
		for _, p in ipairs(postSpots) do
			box(m, "FencePost", CFrame.new(p[1], 1.5, p[2]), Vector3.new(1, 3, 1), C.PlankDark, { Collide = true })
		end
		for _, y in ipairs({ 2.3 }) do
			box(m, "FenceRail", CFrame.new(0, y, half), Vector3.new(PLOT, 0.35, 0.35), C.Plank, { Collide = true })
			box(m, "FenceRail", CFrame.new(-half, y, 0), Vector3.new(0.35, 0.35, PLOT), C.Plank, { Collide = true })
			box(m, "FenceRail", CFrame.new(half, y, 0), Vector3.new(0.35, 0.35, PLOT), C.Plank, { Collide = true })
			local seg = half - 8
			box(m, "FenceRail", CFrame.new(-half + seg / 2, y, -half), Vector3.new(seg, 0.35, 0.35), C.Plank, { Collide = true })
			box(m, "FenceRail", CFrame.new(half - seg / 2, y, -half), Vector3.new(seg, 0.35, 0.35), C.Plank, { Collide = true })
		end

		-- the gate: stone pillars with lanterns, a beam across
		for _, s in ipairs({ -1, 1 }) do
			box(m, "GateBase", CFrame.new(s * 7.2, 0.5, -half), Vector3.new(2.6, 1, 2.6), C.StoneDark, { Collide = true })
			box(m, "GatePillar", CFrame.new(s * 7.2, 4, -half), Vector3.new(2, 6, 2), C.StoneLight, { Collide = true })
			box(m, "GateCap", CFrame.new(s * 7.2, 7.3, -half), Vector3.new(2.6, 0.6, 2.6), C.Stone)
			box(m, "GateLantern", CFrame.new(s * 7.2, 8.1, -half), Vector3.new(1, 1, 1), C.Lamp, { Material = MAT.Neon })
		end
		box(m, "GateBeam", CFrame.new(0, 6.6, -half), Vector3.new(13.4, 0.8, 1), C.PlankDark)

		-- mailbox (the nameplate floats above it); the gate lanterns light the street
		local mb = PLOT_POS.Mailbox
		box(m, "MailPost", CFrame.new(mb.X, 1.5, mb.Z), Vector3.new(0.5, 3, 0.5), C.PlankDark, { Collide = true })
		box(m, "MailBox", CFrame.new(mb.X, 3.4, mb.Z), Vector3.new(1.4, 1.2, 2.2), C.IronLight)

		-- pet podium: stepped stone with a band in the plot accent (recoloured per plot)
		local pod = Instance.new("Model")
		pod.Name = "Podium"
		local pp = PLOT_POS.Podium
		box(pod, "PodiumBase", CFrame.new(pp + Vector3.new(0, 0.5, 0)), Vector3.new(6, 1, 6), C.StoneDark, { Collide = true })
		box(pod, "Accent", CFrame.new(pp + Vector3.new(0, 1.5, 0)), Vector3.new(4.4, 1, 4.4), C.Rose, { Collide = true })
		box(pod, "PodiumTop", CFrame.new(pp + Vector3.new(0, 2.5, 0)), Vector3.new(5.2, 1, 5.2), C.StoneLight, { Collide = true })
		pod.Parent = m
		return m
	end)
end

-- "No. 7" on both faces of the plot's gate sign: 220 x 90 px, the number 1.12 studs tall, gold on navy.
local function numberSign(sign, index, accent)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = surfaceGui(sign, face)
		local plate = plainFrame(gui, "Plate", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0,
		})
		vgradient(plate, C.Violet, C.Navy)
		rounded(plate, 10)
		outline(plate, accent:Lerp(C.TextGold, 0.5), 4)
		signText(plate, "No. " .. tostring(index), "Title", SIGN_TITLE, C.TextGold, "Number", 0.03, 0.04, 0.94, 0.92)
		gui.Parent = sign
	end
end

-- Home nameplate over the mailbox (World text rule): a compact pixel tag, readable from ~80 studs. Left: a round
-- avatar disc with the plot number badge; right: the name (big, outlined) and an info line. The disc holds
--   Headshot    ImageLabel: SpotService loads the owner's headshot into it (Players:GetUserThumbnailAsync)
--   Silhouette  the fallback built from frames (head + shoulders) while no headshot is available
--   FreeIcon    a "+" shown while the home is free
-- and the attributes OwnedColor / FreeColor (disc colour per state, read by SpotService).
-- Returns gui, nameLabel, subLabel.
local AVATAR_PX = 60

local function avatarDisc(parent, index, accent)
	local holder = plainFrame(parent, "AvatarHolder", { Size = UDim2.fromOffset(AVATAR_PX + 8, AVATAR_PX + 8), LayoutOrder = 1 })
	local freeColor = (Theme.Buttons and Theme.Buttons.Green) or rgb(96, 196, 108)
	local ownedColor = accent:Lerp(C.Cloud, 0.45)
	local disc = plainFrame(holder, "Avatar", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(AVATAR_PX, AVATAR_PX),
		BackgroundColor3 = freeColor,
		BackgroundTransparency = 0,
	})
	disc:SetAttribute("OwnedColor", ownedColor)
	disc:SetAttribute("FreeColor", freeColor)
	rounded(disc, UDim.new(0.5, 0))
	outline(disc, INK, 3)

	-- fallback avatar: head + shoulders in a deeper shade of the plot colour (fits inside the circle)
	local shade = Theme.Darken and Theme.Darken(accent, 0.38) or accent:Lerp(C.Navy, 0.38)
	local silhouette = plainFrame(disc, "Silhouette", { Size = UDim2.fromScale(1, 1), Visible = false })
	local head = plainFrame(silhouette, "Head", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(23, 23),
		BackgroundColor3 = shade,
		BackgroundTransparency = 0,
	})
	rounded(head, UDim.new(0.5, 0))
	local body = plainFrame(silhouette, "Shoulders", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 35),
		Size = UDim2.fromOffset(36, 19),
		BackgroundColor3 = shade,
		BackgroundTransparency = 0,
	})
	rounded(body, 10)

	-- free home: a chunky "+"
	local plus = plainFrame(disc, "FreeIcon", { Size = UDim2.fromScale(1, 1) })
	for _, size in ipairs({ Vector2.new(30, 9), Vector2.new(9, 30) }) do
		local bar = plainFrame(plus, "Bar", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundColor3 = C.Text,
			BackgroundTransparency = 0,
		})
		rounded(bar, 4)
	end

	local shot = Instance.new("ImageLabel")
	shot.Name = "Headshot"
	shot.AnchorPoint = Vector2.new(0.5, 0.5)
	shot.Position = UDim2.fromScale(0.5, 0.5)
	shot.Size = UDim2.new(1, -4, 1, -4)
	shot.BackgroundTransparency = 1
	shot.BorderSizePixel = 0
	shot.Image = ""
	shot.ScaleType = Enum.ScaleType.Crop
	shot.Visible = false
	rounded(shot, UDim.new(0.5, 0))
	shot.Parent = disc

	-- plot number badge on the disc's lower-left edge
	local badge = plainFrame(holder, "NumberBadge", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 10, 1, -9),
		Size = UDim2.fromOffset(26, TAG_SMALL + 6),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Gold,
		BackgroundTransparency = 0,
		ZIndex = 3,
	})
	rounded(badge, 10)
	outline(badge, INK, 2.5)
	padding(badge, 1, 6, 2)
	local number = tagText(badge, "Number", "#" .. tostring(index), "Display", TAG_SMALL, C.Text, 1, 2)
	number.ZIndex = 4
	return holder
end

local function homeNameplate(anchor, index, accent)
	-- bottom edge 7.2 studs up: a few studs over the mailbox, under the gate lanterns' glow
	local gui = newTag(anchor, "Nameplate", 460, 110, -2.4, 100)
	local plate = tagPlate(gui, accent, 230, Enum.FillDirection.Horizontal, 12)
	local pad = plate:FindFirstChildOfClass("UIPadding")
	if pad then -- the avatar disc hugs the left edge
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 18)
		pad.PaddingTop = UDim.new(0, 5)
		pad.PaddingBottom = UDim.new(0, 5)
	end
	avatarDisc(plate, index, accent)
	local texts = plainFrame(plate, "Texts", { AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 2 })
	listLayout(texts, Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left)
	local nameLabel = tagText(texts, "NameLabel", "Free home", "Title", TAG_NAME, C.Text, 1)
	local subLabel = tagText(texts, "SubLabel", "Step in to claim", "Body", TAG_INFO, C.TextGold, 2, 2)
	return gui, nameLabel, subLabel
end

local function buildSpot(parent, index, angle)
	local accent = ACCENTS[(index - 1) % #ACCENTS + 1]
	local f = newFolder(parent, string.format("Spot_%02d", index))
	f:SetAttribute("SpotIndex", index)
	local centre = polar(angle, SPOT_R, TOP)
	local plotCF = faceCentre(centre) -- LookVector = towards the gate / street / plaza
	local function at(v)
		return plotCF * CFrame.new(v)
	end

	local plot = place(plotTemplate(), plotCF, f, "Plot")
	if plot then
		-- the podium trim takes the plot accent
		local podium = plot:FindFirstChild("Podium")
		if podium then
			for _, d in ipairs(podium:GetChildren()) do
				if d:IsA("BasePart") and d.Name == "Accent" then
					d.Color = accent
				end
			end
		end
	else
		-- plain stand-in (template failed): a lawn slab so the spot stays usable
		box(f, "Yard", plotCF * CFrame.new(0, -0.5, -9), Vector3.new(PLOT + 12, 1, PLOT + 30), C.Grass, { Collide = true })
	end

	-- per-plot accents: banner pennants on the gate beam, mailbox flag, number sign
	for _, s in ipairs({ -1, 1 }) do
		box(f, "GateBanner", at(Vector3.new(s * 5.4, 5.4, PLOT_POS.Gate - 0.6)), Vector3.new(1.6, 2, 0.15), accent, { Shadow = false })
	end
	local mb = PLOT_POS.Mailbox
	box(f, "MailFlag", at(Vector3.new(mb.X + 0.77, 4.2, mb.Z + 0.4)), Vector3.new(0.15, 1, 0.8), accent, { Shadow = false })
	local sign = box(f, "NumberSign", at(Vector3.new(0, 7.9, PLOT_POS.Gate)), Vector3.new(4.4, 1.8, 0.5), C.Plank)
	numberSign(sign, index, accent)

	-- nameplate over the mailbox
	local anchor = anchorPart(f, "NameplateAnchor", at(Vector3.new(mb.X, 9.6, mb.Z)).Position)
	local gui, nameLabel, subLabel = homeNameplate(anchor, index, accent)

	local podiumTop = at(PLOT_POS.Podium + Vector3.new(0, 3, 0)).Position
	local spawnPos = at(PLOT_POS.Spawn).Position
	return {
		Index = index,
		Folder = f,
		Center = centre,
		SpawnCFrame = flatLook(spawnPos, centre + Vector3.new(0, 3, 0) + plotCF.LookVector * -30),
		NameLabel = nameLabel,
		SubLabel = subLabel,
		Nameplate = gui,
		PodiumCFrame = flatLook(podiumTop, podiumTop + plotCF.LookVector),
		PlotCFrame = plotCF,
		PlotSize = PLOT,
		GateCFrame = at(Vector3.new(0, 0, PLOT_POS.Gate)),
		Accent = accent,
	}
end

-- Bare-minimum spot (see fallbackPortal): a lawn slab, a podium and the two labels.
local function fallbackSpot(parent, index, angle)
	local old = parent:FindFirstChild(string.format("Spot_%02d", index))
	if old then
		old:Destroy()
	end
	local f = newFolder(parent, string.format("Spot_%02d", index))
	f:SetAttribute("SpotIndex", index)
	local centre = polar(angle, SPOT_R, TOP)
	local plotCF = faceCentre(centre)
	box(f, "Yard", plotCF * CFrame.new(0, -0.5, -9), Vector3.new(PLOT + 12, 1, PLOT + 30), C.Grass, { Collide = true })
	box(f, "PodiumBase", plotCF * CFrame.new(PLOT_POS.Podium + Vector3.new(0, 1.5, 0)), Vector3.new(5, 3, 5), C.Stone, { Collide = true })
	local anchor = anchorPart(f, "NameplateAnchor", (plotCF * CFrame.new(PLOT_POS.Mailbox + Vector3.new(0, 9.6, 0))).Position)
	local gui, nameLabel, subLabel = homeNameplate(anchor, index, C.TextGold)
	local podiumTop = (plotCF * CFrame.new(PLOT_POS.Podium + Vector3.new(0, 3, 0))).Position
	local spawnPos = (plotCF * CFrame.new(PLOT_POS.Spawn)).Position
	return {
		Index = index,
		Folder = f,
		Center = centre,
		SpawnCFrame = flatLook(spawnPos, centre + Vector3.new(0, 3, 0) + plotCF.LookVector * -30),
		NameLabel = nameLabel,
		SubLabel = subLabel,
		Nameplate = gui,
		PodiumCFrame = flatLook(podiumTop, podiumTop + plotCF.LookVector),
		PlotCFrame = plotCF,
		PlotSize = PLOT,
		GateCFrame = plotCF * CFrame.new(0, 0, PLOT_POS.Gate),
		Accent = C.TextGold,
	}
end

-- Rope rail with end posts along a straight edge (a, b = ground points).
local function rail(parent, a, b, height)
	height = height or 2.8
	local m = newModel(parent, "Rail")
	local dir = b - a
	local len = dir.Magnitude
	if len < 1 then
		return m
	end
	local posts = math.max(2, math.floor(len / 30) + 1)
	for i = 0, posts - 1 do
		local p = a + dir * (i / (posts - 1))
		box(m, "RailPost", CFrame.new(p + Vector3.new(0, height / 2, 0)), Vector3.new(0.6, height, 0.6), C.PlankDark, { Collide = true })
	end
	local mid = (a + b) * 0.5 + Vector3.new(0, height - 0.4, 0)
	box(m, "RailRope", CFrame.lookAt(mid, mid + dir), Vector3.new(0.3, 0.3, len), C.Plank, { Collide = true, Shadow = false })
	return m
end

-- A wooden bridge between two ground points (deck top `topOffset` below TOP): longitudinal planks, edge
-- beams, rope rails on both sides (open ends) and optional cloud puffs underneath.
local function woodBridge(parent, name, a, b, width, opts)
	opts = opts or {}
	local m = newModel(parent, name)
	local topY = TOP + (opts.Top or -0.2)
	a = Vector3.new(a.X, topY, a.Z)
	b = Vector3.new(b.X, topY, b.Z)
	local dir = b - a
	local len = dir.Magnitude
	local cf = CFrame.lookAt((a + b) * 0.5, b)
	local planks = math.max(3, math.floor(width / 2 + 0.5))
	local pw = width / planks
	for i = 1, planks do
		local x = -width / 2 + (i - 0.5) * pw
		box(m, "Plank", cf * CFrame.new(x, -0.5, 0), Vector3.new(pw, 1, len), (i % 2 == 0) and C.PlankLight or C.Plank, { Collide = true, Shadow = len > 8 })
	end
	if opts.Rails ~= false then
		local insetA = opts.RailInsetA or opts.RailInset or 3
		local insetB = opts.RailInsetB or opts.RailInset or 3
		local right = cf.RightVector
		for _, s in ipairs({ -1, 1 }) do
			if not (opts.NoRail and opts.NoRail[s]) then
				local off = right * (s * (width / 2 - 0.3))
				local p0 = a + dir.Unit * insetA + off
				local p1 = b - dir.Unit * insetB + off
				rail(m, Vector3.new(p0.X, topY, p0.Z), Vector3.new(p1.X, topY, p1.Z))
			end
		end
	end
	for _, t in ipairs(opts.Puffs or {}) do
		-- the puff's highest voxels reach 3 studs over its anchor: anchored 4 under the deck top, it touches the
		-- underside of the 1-stud planks and nothing pokes through
		place(Props.Puff(opts.PuffSize or "M"), CFrame.new(a + dir * t - Vector3.new(0, 4, 0)) * CFrame.Angles(0, t * 7, 0), m, "BridgePuff")
	end
	if opts.MeshKey then -- Phase 6 (LayoutSig); the puff under it is dressed on its own (its parts are kept)
		Mesh.tag(m, opts.MeshKey, cf, nil, Mesh.CloudParts)
	end
	return m
end

-- Ring street junctions (plank bridges between neighbouring plots), spoke bridges and garden bridges.
local function buildRoads(root, L)
	local f = newFolder(root, "Roads")
	local ext = G.JunctionX + G.StreetExt
	local ix = G.IslandHalfX
	local sw = G.StreetW
	for j, info in ipairs(L.Junctions) do
		local a = info.Angle
		local open = info.Spoke or info.Garden or info.Altar -- something docks on the plaza side here
		local jf = newModel(f, string.format("Junction_%02d", j))
		-- half A belongs to the plot before the junction (its local -X side), half B to the plot after it
		for half = 1, 2 do
			local plotAngle = (half == 1) and (a - G.HalfStep) or (a + G.HalfStep)
			local plotCF = faceCentre(polar(plotAngle, SPOT_R, TOP))
			local s = (half == 1) and -1 or 1
			local lift = (half == 1) and 0 or -0.1 -- the halves overlap at the junction: never coplanar
			local x0, x1 = s * ix, s * ext
			local len = math.abs(x1 - x0)
			local count = math.max(2, math.floor(len / 4 + 0.5))
			local pw = len / count
			for i = 1, count do
				local x = x0 + s * (i - 0.5) * pw
				box(jf, "Plank", plotCF * CFrame.new(x, -0.5 + lift, G.StreetZ), Vector3.new(pw, 1, sw), (i % 2 == 0) and C.PlankLight or C.Plank, { Collide = true, Shadow = false })
			end
		end
		-- one straight rail per side across both halves: outer always, inner unless a bridge docks here
		local plotA = faceCentre(polar(a - G.HalfStep, SPOT_R, TOP))
		local plotB = faceCentre(polar(a + G.HalfStep, SPOT_R, TOP))
		local sides = { G.StreetZ + sw / 2 - 0.9 }
		if not open then
			sides[2] = G.StreetZ - sw / 2 + 0.9
		end
		for k, z in ipairs(sides) do
			local pA = (plotA * CFrame.new(-ix - 0.8, 0, z)).Position
			local pB = (plotB * CFrame.new(ix + 0.8, 0, z)).Position
			if k == 1 and info.Arena then
				-- Phase 3: the outer rail opens around the junction's ray for the arena bridge (ArenaBuilder)
				local mid = (pA + pB) * 0.5
				local u = Vector3.new(pB.X - pA.X, 0, pB.Z - pA.Z).Unit
				local keep = G.ArenaBridgeW / 2 + 0.8
				local q0, q1 = mid - u * keep, mid + u * keep
				rail(jf, Vector3.new(pA.X, TOP, pA.Z), Vector3.new(q0.X, TOP, q0.Z))
				rail(jf, Vector3.new(q1.X, TOP, q1.Z), Vector3.new(pB.X, TOP, pB.Z))
			else
				rail(jf, Vector3.new(pA.X, TOP, pA.Z), Vector3.new(pB.X, TOP, pB.Z))
			end
		end
		if open then
			-- short inner rails on both sides of the docking bridge
			local zIn = G.StreetZ - sw / 2 + 0.9
			local dock = polar(a, G.StreetR / math.cos(math.rad(G.HalfStep)) - sw / 2, TOP)
			-- (the Storm Altar's bridge docks with a 14-stud entrance gate whose low walls close the gap)
			local keep = info.Altar and 7.6 or (((info.Spoke and G.SpokeW) or 8) / 2 + 0.8)
			for _, p in ipairs({ (plotA * CFrame.new(-ix - 0.8, 0, zIn)).Position, (plotB * CFrame.new(ix + 0.8, 0, zIn)).Position }) do
				local d = Vector3.new(dock.X - p.X, 0, dock.Z - p.Z)
				local len = d.Magnitude - keep
				if len > 1.5 then
					local q = p + d.Unit * len
					rail(jf, Vector3.new(p.X, TOP, p.Z), Vector3.new(q.X, TOP, q.Z))
				end
			end
		end
		-- Phase 6: one plank-deck mesh per junction kind (identical local geometry; LayoutSig)
		local kind = (info.Arena and "arena") or (info.Altar and "altar") or (info.Spoke and "spoke") or (info.Garden and "garden") or "plain"
		Mesh.tag(jf, "floor_junction_" .. kind, faceCentre(polar(a, G.StreetR, TOP)))
	end

	-- Spokes: plaza rim -> junction, over open sky, carried by cloud puffs.
	for _, a in ipairs(L.SpokeAngles) do
		local p0 = polar(a, PLAZA_R - 3, TOP)
		local p1 = polar(a, G.SpokeEndR, TOP)
		-- rails run from the plaza's cloud rim right up to the street edge (no open window over the sky)
		woodBridge(f, "Spoke", p0, p1, G.SpokeW, { Puffs = { 0.52 }, PuffSize = "S", RailInsetA = 6, RailInsetB = 2.6, MeshKey = "floor_spoke" })
	end
end

----------------------------------------------------------------------
-- Garden islands (hanging off the street) and the reserved Storm Altar site
----------------------------------------------------------------------

-- Five stacked ground layers around `centre` (2-stud cells). fn(x, z, r) -> l1, l2, l3, l4 (see plazaCell).
local function layeredGround(parent, centre, radius, fn, meshPrefix)
	local cell = 2
	local n = math.ceil(radius / cell)
	local grids = { Voxel.NewGrid(1), Voxel.NewGrid(1), Voxel.NewGrid(1), Voxel.NewGrid(1), Voxel.NewGrid(1) }
	for i = -n, n do
		for k = -n, n do
			local x, z = i * cell, k * cell
			local r = math.sqrt(x * x + z * z)
			if r <= radius - 0.5 then
				Voxel.Set(grids[1], i, 0, k, "Grass")
				local keys = { fn(x, z, r) }
				for li = 1, 4 do
					if keys[li] then
						Voxel.Set(grids[li + 1], i, 0, k, keys[li])
					end
				end
			end
		end
	end
	local tops = { -0.4, -0.3, -0.1, 0, 0.1 }
	for li = 1, 5 do
		local layer = VX.Build(grids[li], { V = cell, Name = "Ground" .. li, CF = CFrame.new(centre.X, TOP + tops[li] - cell / 2, centre.Z), Collide = true, Shadow = false, Parent = parent })
		if layer and meshPrefix then
			Mesh.tag(layer, meshPrefix .. li, CFrame.new(centre.X, TOP, centre.Z)) -- Phase 6 (LayoutSig)
		end
	end
end

local function buildPond(parent, ground)
	local g = Voxel.NewGrid(14)
	VX.Ring(g, 0, 0, 5.2, 6.9, 0, 1, "Stone")
	VX.Disc(g, 0, 0, 5.3, -1, -1, "WaterDeep")
	VX.Disc(g, 0, 0, 5.3, 0, 0, "Water")
	for _, p in ipairs({ { -2, 1 }, { 2, -2 }, { 1, 3 } }) do
		Voxel.Set(g, p[1], 0, p[2], "Leaf")
		Voxel.Set(g, p[1] + 1, 0, p[2], "Leaf")
	end
	Voxel.Set(g, 1, 1, 3, "Blossom")
	Voxel.Set(g, -2, 1, 1, "BlossomWhite")
	local water = VX.Split(g, { Water = true })
	local cf = CFrame.new(ground.X, TOP + 0.1, ground.Z)
	local stone = VX.Build(g, { V = 1, Name = "PondStone", CF = cf, Collide = true, Parent = parent })
	local pondWater = VX.Build(water, { V = 1, Name = "PondWater", CF = cf, Collide = false, Parent = parent })
	-- Phase 6: the pond ring and its water
	local ground0 = CFrame.new(ground.X, TOP, ground.Z)
	if stone then
		Mesh.tag(stone, "prop_pond", ground0)
	end
	if pondWater then
		Mesh.tag(pondWater, "prop_pond_water", ground0)
	end
	local sparkle = anchorPart(parent, "PondSparkle", ground + Vector3.new(0, 1, 0), Vector3.new(9, 1, 9))
	emitter(sparkle, { Color = ColorSequence.new(rgb(200, 236, 255)), Rate = 3, Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(0.2, 0.6), Size = popSize(0.5) })
end

local function buildGarden(parent, spec, L)
	local f = newFolder(parent, "Garden_" .. (spec.Name:gsub("%s", "")))
	local a = spec.Angle
	local c = polar(a, G.GardenR, TOP)
	local R = G.GardenSize
	local out = dirOf(a)
	local rng = Util.NewRng(SEED + 40 + math.floor(a))
	local cf = flatLook(c, c + out) -- local -Z = outwards (towards the street bridge)

	local rim, puffs = {}, {}
	for i = 1, 6 do
		local deg = (i - 1) * 60 + a + 180 + rng:Float(-6, 6)
		if angleDiff(deg, a) > 30 then
			local s = rng:Float(8, 9.5)
			rim[#rim + 1] = { math.cos(math.rad(deg)) * (R + 1.5), rng:Float(-1.5, 0), math.sin(math.rad(deg)) * (R + 1.5), s, s * 0.62, s }
		end
	end
	for i = 1, 3 do
		local ang = (i - 1) / 3 * math.pi * 2 + rng:Float(-0.3, 0.3)
		local s = rng:Float(7, 9)
		puffs[#puffs + 1] = { math.cos(ang) * (R - 5), -6, math.sin(ang) * (R - 5), s, s * 0.7, s }
	end
	local gardenKind = (spec.Kind == "Pond") and "pond" or "blossom"
	local gardenCloud = VX.CloudModel({
		V = 3,
		Tiers = { { R = R + 3, H = 1 }, { R = R - 3, H = 2 }, { R = R - 10, H = 2 }, { R = R - 16, H = 1 } },
		Puffs = puffs,
		Rim = rim,
		Carve = function(x, y, z)
			return y > 0 and (x * x + z * z) < (R - 3) * (R - 3)
		end,
		MaxParts = 46,
		Seed = 20 + math.floor(a),
	}, CFrame.new(c.X, TOP - 1.2, c.Z), f, "GardenCloud", true)
	if gardenCloud then
		Mesh.tag(gardenCloud, "cloud_garden_" .. gardenKind, CFrame.new(c.X, TOP - 1.2, c.Z)) -- Phase 6 (LayoutSig)
	end

	layeredGround(f, c, R, function(x, z, r)
		local l1, l2, l3
		local nz = vnoise(x + a, z - a, 18, 17)
		if nz < 0.26 then
			l1 = "GrassDark"
		elseif nz > 0.76 then
			l1 = "GrassLight"
		end
		local ring = math.abs(r - 10)
		local t = x * out.X + z * out.Z
		local d = math.abs(-x * out.Z + z * out.X)
		-- the border reaches 2.2 studs past the sand (more than one 2-stud cell), so the sand never ends flush
		-- with it on the grid
		local onPath = t >= 9 and d <= 4.4
		if ring <= 4.4 or onPath then
			l2 = "SandDark"
		end
		if ring <= 2.2 or (t >= 9 and d <= 2.2 and r <= R - 2.5) then
			l3 = "Sand"
		end
		if r > R - 3 then
			l1 = nil -- lawn only at the very edge
		end -- (bug #12: the rim's flat flower pixels became Meadow clumps)
		return l1, l2, l3, nil
	end, "floor_garden_" .. gardenKind .. "_")

	-- features
	local function localPos(deg, dist)
		-- deg measured from the outward direction
		return (cf * CFrame.Angles(0, math.rad(deg), 0) * CFrame.new(0, 0, -dist)).Position
	end
	local down = Vector3.new(0, LAWN, 0) -- props stand on the lawn layer
	if spec.Kind == "Pond" then
		buildPond(f, c)
		place(Props.Tree("Round"), CFrame.new(localPos(180, 16) - down) * CFrame.Angles(0, 1.3, 0), f, "RoundTree")
		place(Props.FlowerBed(6), flatLook(localPos(140, 16) - down, c - down) * CFrame.Angles(0, math.rad(90), 0), f, "FlowerBed")
	else
		place(Props.Tree("Blossom"), CFrame.new(c - down) * CFrame.Angles(0, 0.7, 0), f, "BlossomTree")
		place(Props.FlowerBed(1), flatLook(localPos(180, 16) - down, c - down) * CFrame.Angles(0, math.rad(90), 0), f, "FlowerBed")
	end
	for _, deg in ipairs({ 75, -75 }) do
		local p = localPos(deg, 15.5) - down
		place(Props.Bench(), flatLook(p, c - down), f, "Bench")
	end

	-- name tag + the bridge to the street junction
	local tag = anchorPart(f, "NameTag", c + Vector3.new(0, 22, 0))
	local gui = newTag(tag, "NameTag", 320, 80, -1.7, 120)
	local plate = tagPlate(gui, rgb(150, 210, 160), 160)
	tagText(plate, "Text", spec.Name, "Title", TAG_NAME + 2, C.Text, 1)
	woodBridge(f, "GardenBridge", polar(a, G.GardenR + R - 3, TOP), polar(a, G.SpokeEndR, TOP), 8, { RailInsetA = 3, RailInsetB = 2.6, MeshKey = "floor_garden_bridge" })
	return f
end

----------------------------------------------------------------------
-- Sky: voxel cumulus around the village and one far below it (never collidable)
----------------------------------------------------------------------

-- kind: "Big" (96 studs) | "Small" (60 studs)
local function cumulus(kind)
	return template("Sky" .. kind, function()
		local r = Util.NewRng(SEED + #kind * 13)
		local w = (kind == "Big") and 96 or 60
		local rim = {}
		local n = 5
		for i = 1, n do
			local x = (i - (n + 1) / 2) / n * w * 0.9 + r:Float(-4, 4)
			local s = r:Float(0.16, 0.24) * w
			rim[#rim + 1] = { x, r:Float(0, 6), r:Float(-w * 0.12, w * 0.12), s, s * 0.8, s * 0.9 }
		end
		rim[#rim + 1] = { r:Float(-6, 6), w * 0.18, 0, w * 0.22, w * 0.2, w * 0.2 }
		local spec = {
			V = 6,
			Tiers = { { SX = w, SZ = w * 0.55, Round = w * 0.2, H = 1, Key = "Mist" } },
			Rim = rim,
			MaxParts = 32,
			Seed = #kind,
		}
		return VX.CloudModel(spec, CFrame.new(), nil, "SkyCloud", false)
	end)
end

local function buildSky(root)
	local f = newFolder(root, "Sky")
	local rng = Util.NewRng(SEED + 5)
	local count = 3
	for i = 1, count do
		local ang = (i - 1) * (360 / count) + rng:Float(-14, 14) + 20
		local dist = rng:Float(430, 620)
		local y = TOP + rng:Float(-40, 80)
		local kind = (i == 2) and "Small" or "Big"
		local pos = polar(ang, dist, y)
		place(cumulus(kind), CFrame.new(pos) * CFrame.Angles(0, math.rad(rng:Float(0, 360)), 0), f, "SkyCloud")
	end
	-- far below: one big puffy cumulus (depth under the village), not a flat sheet
	place(cumulus("Big"), CFrame.new(polar(rng:Float(40, 80), rng:Float(200, 320), TOP - rng:Float(130, 160))) * CFrame.Angles(0, math.rad(rng:Float(0, 360)), 0), f, "CloudSea")
	local dust = anchorPart(f, "SkyDust", Vector3.new(OX, TOP + 24, OZ), Vector3.new(560, 90, 560))
	emitter(dust, {
		Color = ColorSequence.new(rgb(255, 236, 200), rgb(200, 220, 255)),
		Rate = 14,
		Lifetime = NumberRange.new(8, 12),
		Speed = NumberRange.new(0.3, 1.2),
		SpreadAngle = Vector2.new(180, 180),
		Size = popSize(0.8),
	})
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

local function section(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		warn("[LobbyBuilder] section '" .. name .. "' failed: " .. tostring(err))
	end
	return ok
end

-- Six spots on the plaza lawn when the decor pass could not compute them.
local function defaultNpcSpots(L)
	local spots = {}
	local plan = { 22.5, 157.5, L.ShopAngle - 30, L.ShopAngle + 30, L.ShopAngle - 60, L.ShopAngle + 60 }
	for _, a in ipairs(plan) do
		local pos = polar(a, 58, TOP)
		spots[#spots + 1] = faceCentre(pos)
	end
	return spots
end

----------------------------------------------------------------------
-- Bug #12 "Wind-Sown Sky Meadow" (the player's pick, option B; note: "make sure the grass/flowers quality is high and
-- the animation is smooth"). Up here the wind never stops: the outer lawns go wild (tufts leaning downwind, grass gone
-- to seed, wildflowers, cornflowers, dandelions), the settlers still mow the inner lawns (short tufts, clover, daisies),
-- and a sack of flower seed torn open against a flower bed sends a trail of the bed's own two colours downwind.
--
-- The SERVER only decides where things grow; it builds no grass parts (the lobby is at ~7.5k of its 8k-part budget):
--   * it reads the built ground itself (every lawn / patch / path / prop part in the lobby, rasterised on a 1-stud
--     grid per area), so a clump can never sit on a path, under a tree's roots, a lamp, a bench, a flower bed, the
--     fountain, an NPC spot or past the rim, whatever the layout becomes; grass thins out near every edge
--     (MEADOW.Edge / Thin);
--   * it scatters clumps on a jittered 2-stud grid AFTER all of that exists (the old flat squares were picked before
--     the props reserved their spots: the pink square under the tree in the bug screenshot);
--   * it publishes the result as compact strings on workspace.NimbusLobby.Meadow (attributes Clumps1..N: 9 chars
--     per clump) + Wind / Base / Kinds / Tint1..6; clients (MeadowFx) grow the clumps locally from the Blender keys
--     (meadow_*) or plain-part stand-ins, thin them with distance and sway them in rolling gusts;
--   * the torn seed sacks are a small Part build + Mesh.tag "prop_seedsack" (Detail decor), and a few invisible
--     emitter boxes let dandelion seeds drift downwind over the wild lawns (NC_Detail: Low graphics parks them).
----------------------------------------------------------------------
-- (built inside its own function: its helpers stay out of this chunk's local-variable budget)
local Meadow = (function()
	local Meadow = {}
	local MEADOW = {
		Version = 1,
		-- the lobby's prevailing wind (from the west-south-west): every blade leans along it, the gusts roll along it
		Wind = Vector3.new(0.96, 0, 0.28).Unit,
		-- clump kinds: index (1-based) -> mesh key (the encoding stores index - 1)
		Kinds = { "meadow_tuft_tall", "meadow_tuft_short", "meadow_tuft_seed", "meadow_sprig", "meadow_flowers",
			"meadow_cornflower", "meadow_dandelion", "meadow_clover" },
		Cell = 1.7, -- candidate grid: at most one clump per 1.7 x 1.7-stud cell, jittered inside it
		Edge = 1.1, -- no clump closer than this to a path, a prop, an NPC spot or the rim (studs)
		Thin = 2.6, -- ... and up to this distance only short ones, sparser (paths and pets stay easy to read)
		Pad = 0.35, -- props (anything standing on the lawn) are grown by this before the distance test
		Density = { wild = 0.9, mown = 0.48, garden = 0.4 }, -- mown 0.34 -> 0.48 after the final review (the inner lawns read bare)
		-- weights per zone, in Kinds order (tall, short, seed, sprig, flowers, cornflower, dandelion, clover)
		Mix = {
			wild = { 22, 22, 10, 26, 8, 5, 5, 2 },
			mown = { 0, 34, 0, 20, 20, 0, 6, 20 }, -- more short tufts + daisies (they read from afar), fewer sprigs
			garden = { 14, 26, 0, 18, 22, 5, 4, 11 },
			edge = { 0, 30, 0, 50, 0, 0, 0, 20 },
		},
		-- wildflower tints (index into FLOWERS): wild meadow pink / yellow / white, mown lawn white daisies, gardens any
		WildTints = { 1, 1, 1, 2, 2, 2, 3, 3 },
		ChunkClumps = 450, -- clumps per attribute string (9 chars each: ~4 KB per attribute)
		Sacks = 2, -- plaza flower beds that get a torn seed sack (the best downwind runs)
		Sack = { W = 1.15, D = 0.85, H = 1.35, Lean = 0.22 }, -- blender/kit/props/lobby_meadow.py SACK
		Drift = { Length = 24, Width0 = 1.3, Spread = 0.3 },
		Seeds = { Sectors = 6, MinClocks = 6, Rate = 1.2 },
		GLOW = "rbxasset://textures/particles/explosion01_implosion_main.dds",
		Stats = nil, -- the last scatter's numbers (tests, the build log)
	}
	Meadow.K = MEADOW

	local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local B64I = {}
	for i = 1, #B64 do
		B64I[string.sub(B64, i, i)] = i - 1
	end

	local function b64(v, n)
		local out = {}
		for i = n, 1, -1 do
			local d = v % 64
			out[i] = string.sub(B64, d + 1, d + 1)
			v = (v - d) / 64
		end
		return table.concat(out)
	end

	-- one clump -> 9 chars: [kind*8 + tint] [x: 3] [z: 3] [yaw 0..63] [scale 0..15 + 16 * patch]; x / z relative to the
	-- lobby origin, 1/64 stud, +-2048
	function Meadow.encode(c)
		local qx = math.floor((c.X + 2048) * 64 + 0.5)
		local qz = math.floor((c.Z + 2048) * 64 + 0.5)
		qx = math.max(0, math.min(262143, qx))
		qz = math.max(0, math.min(262143, qz))
		local yaw = math.floor(((c.Yaw % (2 * math.pi)) / (2 * math.pi)) * 64 + 0.5) % 64
		local sc = math.max(0, math.min(15, math.floor((c.Scale - 0.7) / 0.04 + 0.5)))
		return b64((c.Kind - 1) * 8 + (c.Tint or 0), 1) .. b64(qx, 3) .. b64(qz, 3) .. b64(yaw, 1)
			.. b64(sc + (c.Patch and 16 or 0), 1)
	end

	function Meadow.decode(s, i)
		local function n(a, len)
			local v = 0
			for j = a, a + len - 1 do
				v = v * 64 + (B64I[string.sub(s, j, j)] or 0)
			end
			return v
		end
		local o = (i - 1) * 9 + 1
		local kt = n(o, 1)
		local tint = kt % 8
		local f = n(o + 8, 1)
		return {
			Kind = (kt - tint) / 8 + 1,
			Tint = tint,
			X = n(o + 1, 3) / 64 - 2048,
			Z = n(o + 4, 3) / 64 - 2048,
			Yaw = n(o + 7, 1) / 64 * 2 * math.pi,
			Scale = 0.7 + (f % 16) * 0.04,
			Patch = f >= 16,
		}
	end

	-- ground codes of a 1-stud grid: 0 nothing (sky), 1 lawn, 2 lawn patch (0.1 higher), 3 blocked (path, border, prop)
	local function areaGrid(cx, cz, R)
		local N = math.ceil(R) + 2
		return { CX = cx, CZ = cz, R = R, N = N, S = 2 * N, Code = {}, Dist = nil }
	end

	local function gridIndex(g, x, z)
		local i = math.floor(x - g.CX) + g.N
		local k = math.floor(z - g.CZ) + g.N
		if i < 0 or k < 0 or i >= g.S or k >= g.S then
			return nil
		end
		return i * g.S + k + 1
	end

	local function gridMark(g, x0, z0, x1, z1, code)
		local S, N = g.S, g.N
		local i0 = math.max(0, math.floor(x0 - g.CX) + N)
		local i1 = math.min(S - 1, math.floor(x1 - g.CX) + N)
		local k0 = math.max(0, math.floor(z0 - g.CZ) + N)
		local k1 = math.min(S - 1, math.floor(z1 - g.CZ) + N)
		local code_ = g.Code
		for i = i0, i1 do
			local base = i * S + 1
			for k = k0, k1 do
				local idx = base + k
				if (code_[idx] or 0) < code then
					code_[idx] = code
				end
			end
		end
	end

	local function gridCircle(g, x, z, r)
		gridMark(g, x - r, z - r, x + r, z + r, 3)
	end

	-- every visible part of the lobby that reaches into the area: lawn / patch / blocked
	local function rasterise(g, parts)
		local R = g.R + 2
		for _, p in ipairs(parts) do
			local pos, s, cf = p.Position, p.Size, p.CFrame
			local rx, ry, rz = cf.RightVector, cf.UpVector, cf.LookVector
			local ex = (math.abs(rx.X) * s.X + math.abs(ry.X) * s.Y + math.abs(rz.X) * s.Z) / 2
			local ey = (math.abs(rx.Y) * s.X + math.abs(ry.Y) * s.Y + math.abs(rz.Y) * s.Z) / 2
			local ez = (math.abs(rx.Z) * s.X + math.abs(ry.Z) * s.Y + math.abs(rz.Z) * s.Z) / 2
			if pos.X + ex >= g.CX - R and pos.X - ex <= g.CX + R and pos.Z + ez >= g.CZ - R and pos.Z - ez <= g.CZ + R then
				local top, bottom = pos.Y + ey, pos.Y - ey
				if top > TOP - LAWN - 0.05 and bottom < TOP + 2.5 then
					if top <= TOP - LAWN + 0.05 then
						-- the lawn layer: cells whose centre it covers (half-open, so neighbouring slabs never double up)
						gridMark(g, pos.X - ex + 0.5, pos.Z - ez + 0.5, pos.X + ex - 0.5, pos.Z + ez - 0.5, 1)
					elseif top <= TOP - LAWN + 0.15 then
						gridMark(g, pos.X - ex + 0.5, pos.Z - ez + 0.5, pos.X + ex - 0.5, pos.Z + ez - 0.5, 2)
					elseif top <= TOP + 0.15 then
						gridMark(g, pos.X - ex, pos.Z - ez, pos.X + ex, pos.Z + ez, 3) -- borders, paths, inlays
					else
						local pad = MEADOW.Pad -- anything standing on the lawn: trunks, roots, lamps, benches, beds...
						local aligned = math.abs(ry.Y) > 0.999 and (math.abs(rx.X) > 0.999 or math.abs(rx.Z) > 0.999)
						if aligned then
							gridMark(g, pos.X - ex - pad, pos.Z - ez - pad, pos.X + ex + pad, pos.Z + ez + pad, 3)
						else
							-- a turned prop: only the cells its own (padded) box covers, not its world bounding box
							local S, N, code = g.S, g.N, g.Code
							local hx, hy, hz = s.X / 2 + pad, s.Y / 2 + pad, s.Z / 2 + pad
							local i0 = math.max(0, math.floor(pos.X - ex - pad - g.CX) + N)
							local i1 = math.min(S - 1, math.floor(pos.X + ex + pad - g.CX) + N)
							local k0 = math.max(0, math.floor(pos.Z - ez - pad - g.CZ) + N)
							local k1 = math.min(S - 1, math.floor(pos.Z + ez + pad - g.CZ) + N)
							local yProbe = math.max(bottom, math.min(top, TOP - LAWN + 0.1))
							for i = i0, i1 do
								for k = k0, k1 do
									local q = cf:PointToObjectSpace(Vector3.new(g.CX + i - N + 0.5, yProbe, g.CZ + k - N + 0.5))
									if math.abs(q.X) <= hx and math.abs(q.Z) <= hz and math.abs(q.Y) <= hy then
										code[i * S + k + 1] = 3
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- distance (studs) from every cell to the nearest cell that is not lawn (chamfer 3-4 / 3)
	local function distances(g)
		local S, code = g.S, g.Code
		local D = {}
		local BIG = 1e6
		for idx = 1, S * S do
			local c = code[idx] or 0
			D[idx] = (c == 1 or c == 2) and BIG or 0
		end
		for i = 0, S - 1 do
			for k = 0, S - 1 do
				local idx = i * S + k + 1
				local d = D[idx]
				if d > 0 then
					if i > 0 then
						d = math.min(d, D[idx - S] + 3)
						if k > 0 then
							d = math.min(d, D[idx - S - 1] + 4)
						end
						if k < S - 1 then
							d = math.min(d, D[idx - S + 1] + 4)
						end
					else
						d = math.min(d, 3)
					end
					if k > 0 then
						d = math.min(d, D[idx - 1] + 3)
					else
						d = math.min(d, 3)
					end
					D[idx] = d
				end
			end
		end
		for i = S - 1, 0, -1 do
			for k = S - 1, 0, -1 do
				local idx = i * S + k + 1
				local d = D[idx]
				if d > 0 then
					if i < S - 1 then
						d = math.min(d, D[idx + S] + 3)
						if k > 0 then
							d = math.min(d, D[idx + S - 1] + 4)
						end
						if k < S - 1 then
							d = math.min(d, D[idx + S + 1] + 4)
						end
					else
						d = math.min(d, 3)
					end
					if k < S - 1 then
						d = math.min(d, D[idx + 1] + 3)
					else
						d = math.min(d, 3)
					end
					D[idx] = d
				end
			end
		end
		g.Dist = D
	end

	-- distance of a point to the nearest non-lawn cell (studs; the cell centre value, minus half a cell of slack)
	local function distAt(g, x, z)
		local idx = gridIndex(g, x, z)
		if not idx then
			return 0
		end
		return math.max(0, g.Dist[idx] / 3 - 0.5)
	end

	local function pick(weights, h)
		local total = 0
		for _, w in ipairs(weights) do
			total = total + w
		end
		local t = h * total
		for i, w in ipairs(weights) do
			t = t - w
			if t < 0 then
				return i
			end
		end
		return #weights
	end

	-- the lobby's parts once (visible ones only), shared by every area
	local function lobbyParts(root)
		local list = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 0.99 then
				list[#list + 1] = d
			end
		end
		return list
	end

	-- the seed sacks: at the plaza's flower beds whose downwind run over open lawn is longest; returns the comets
	local function buildSacks(root, g, decorParent)
		local beds = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") and d.Name == "FlowerBed" and d.Parent and d.Parent.Name == "LawnDecor" then
				beds[#beds + 1] = d
			end
		end
		table.sort(beds, function(a, b)
			local pa, pb = a:GetPivot().Position, b:GetPivot().Position
			return pa.X + pa.Z * 0.001 < pb.X + pb.Z * 0.001
		end)
		local w = MEADOW.Wind
		local up = Vector3.new(0, 1, 0)
		local options = {}
		for bi, bed in ipairs(beds) do
			local pivot = bed:GetPivot()
			-- the bed's half extents in its own frame (its parts)
			local hx, hz = 0, 0
			for _, p in ipairs(bed:GetDescendants()) do
				if p:IsA("BasePart") then
					local lp = pivot:PointToObjectSpace(p.Position)
					local ls = pivot:VectorToObjectSpace(p.CFrame:VectorToWorldSpace(p.Size))
					hx = math.max(hx, math.abs(lp.X) + math.abs(ls.X) / 2)
					hz = math.max(hz, math.abs(lp.Z) + math.abs(ls.Z) / 2)
				end
			end
			local v = tonumber((bed:GetAttribute("FlowerVariant"))) or (((bi - 1) % #FLOWERS) + 1)
			for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local nLocal = Vector3.new(side[1], 0, side[2])
				local n = pivot:VectorToWorldSpace(nLocal)
				n = Vector3.new(n.X, 0, n.Z).Unit
				local look = -n
				local right = look:Cross(up)
				if right:Dot(w) > 0.5 then
					local reach = (side[1] ~= 0) and hx or hz
					local along = (side[1] ~= 0) and hz or hx
					local footD = reach + MEADOW.Sack.D / 2 + 0.25
					-- the sack slumps at the downwind end of that side, its spill just past the bed's corner
					local tangent = right
					local offset = math.max(0, along + 0.8 - (MEADOW.Sack.W / 2 + 0.7)) -- the spill lands just past the corner
					local foot = pivot.Position + n * footD + tangent * offset
					local spill = foot + right * (MEADOW.Sack.W / 2 + 0.7)
					local okFoot = true
					for _, probe in ipairs({ foot, spill, foot - right * 0.5 }) do
						local idx = gridIndex(g, probe.X, probe.Z)
						local c = idx and g.Code[idx] or 0
						if c ~= 1 and c ~= 2 then
							okFoot = false
						end
					end
					if okFoot then
						local run = 0
						for t = 1, MEADOW.Drift.Length do
							local q = spill + w * t
							local idx = gridIndex(g, q.X, q.Z)
							local c = idx and g.Code[idx] or 0
							if c ~= 1 and c ~= 2 then
								break
							end
							run = t
						end
						local score = run + right:Dot(w) * 4
						options[#options + 1] = { Bed = bed, Score = score, Foot = foot, Look = look, Spill = spill,
							Variant = v, Patch = (g.Code[gridIndex(g, foot.X, foot.Z)] == 2) }
					end
				end
			end
		end
		table.sort(options, function(a, b)
			if math.abs(a.Score - b.Score) > 1e-6 then
				return a.Score > b.Score
			end
			return a.Foot.X < b.Foot.X
		end)
		local comets, used = {}, {}
		local S = MEADOW.Sack
		local burlap, burlapDark, seed, twine = rgb(206, 178, 128), rgb(190, 162, 114), rgb(232, 214, 160), rgb(160, 122, 78)
		for _, o in ipairs(options) do
			if #comets >= MEADOW.Sacks then
				break
			end
			if not used[o.Bed] then
				used[o.Bed] = true
				local y = TOP - LAWN + (o.Patch and 0.1 or 0)
				local frame = CFrame.lookAt(Vector3.new(o.Foot.X, y, o.Foot.Z), Vector3.new(o.Foot.X, y, o.Foot.Z) + o.Look)
				local m = newModel(decorParent, "SeedSack")
				m:SetAttribute("Bed", o.Bed:GetFullName())
				-- the Part build (the fallback and the shape the mesh dresses): a slumped body, the bunched neck, the
				-- flopped top and the spilled mound
				local tilt = frame * CFrame.Angles(-S.Lean, 0, 0)
				box(m, "Sack", tilt * CFrame.new(0, S.H / 2, 0), Vector3.new(S.W, S.H, S.D), burlap)
				box(m, "SackNeck", tilt * CFrame.new(0, S.H + 0.08, 0), Vector3.new(0.5, 0.26, 0.5), twine)
				box(m, "SackTop", tilt * CFrame.new(0, S.H + 0.32, 0.05), Vector3.new(0.6, 0.28, 0.45), burlapDark)
				box(m, "Spill", frame * CFrame.new(S.W / 2 + 0.5, 0.06, 0.2), Vector3.new(1.0, 0.16, 0.9), seed)
				m.WorldPivot = frame
				Mesh.tag(m, "prop_seedsack", frame)
				gridCircle(g, o.Foot.X, o.Foot.Z, 1.0)
				gridCircle(g, o.Spill.X, o.Spill.Z, 0.8)
				local v = o.Variant
				comets[#comets + 1] = { From = o.Spill, Tints = { v, v % #FLOWERS + 1 }, Sack = m }
			end
		end
		return comets
	end

	-- where a point sits in a seed drift (a comet streaming downwind from the spill): t along it, its half width there
	local function inComet(c, x, z)
		local w = MEADOW.Wind
		local rel = Vector3.new(x - c.From.X, 0, z - c.From.Z)
		local t = rel:Dot(w)
		local side = math.abs(rel.X * w.Z - rel.Z * w.X)
		local half = MEADOW.Drift.Width0 + math.max(0, t) * MEADOW.Drift.Spread
		if t >= -0.6 and t <= MEADOW.Drift.Length and side <= half then
			return t, side, half
		end
		return nil
	end

	local function zoneScale(zone, edge, h)
		if zone == "wild" and not edge then
			return 0.9 + 0.32 * h
		elseif zone == "mown" then
			return 0.72 + 0.2 * h
		end
		return 0.8 + 0.26 * h
	end

	-- one area's clumps (appended to `out`); zoneOf(x, z) -> "wild" | "mown" | "garden" | nil (relative to the area centre)
	local function scatter(g, out, zoneOf, seed, comets, npcSpots)
		for _, s in ipairs(npcSpots or {}) do
			local p = typeof(s) == "CFrame" and s.Position or s
			if typeof(p) == "Vector3" then
				gridCircle(g, p.X, p.Z, 3)
			end
		end
		distances(g)
		local cell = MEADOW.Cell
		local n = math.ceil(g.R / cell)
		local w = MEADOW.Wind
		local yaw0 = math.atan2(-w.Z, w.X) -- CFrame.Angles(0, yaw0, 0) turns +X onto the wind
		local stats = out.Stats
		local function add(kind, tint, x, z, h, sc, code, zone, drift)
			out[#out + 1] = {
				Kind = kind,
				Tint = tint,
				X = x - OX,
				Z = z - OZ,
				Yaw = yaw0 + (h - 0.5) * 0.7,
				Scale = sc,
				Patch = code == 2,
				Zone = zone,
				Drift = drift,
			}
			local key = drift and "Drift" or zone
			stats[key] = (stats[key] or 0) + 1
		end
		-- the meadow / lawn on a jittered 2-stud grid
		for i = -n, n - 1 do
			for k = -n, n - 1 do
				local h1, h2 = hash3(i, 1, k, seed), hash3(i, 2, k, seed)
				local lx, lz = (i + 0.12 + 0.76 * h1) * cell, (k + 0.12 + 0.76 * h2) * cell
				local x, z = g.CX + lx, g.CZ + lz
				local idx = gridIndex(g, x, z)
				local code = idx and g.Code[idx] or 0
				if (code == 1 or code == 2) and lx * lx + lz * lz <= g.R * g.R then
					local d = distAt(g, x, z)
					local zone = zoneOf(lx, lz)
					if zone and d >= MEADOW.Edge then
						local p, mix = MEADOW.Density[zone] or 0, MEADOW.Mix[zone]
						-- clumpy meadow: soft patches of thicker and thinner growth
						p = p * (0.45 + 0.75 * vnoise(x + 311, z - 97, 13, seed + 3))
						for _, c in ipairs(comets or {}) do
							if inComet(c, x, z) then
								p = p * 0.5 -- the drift's flowers stand in thinner grass
							end
						end
						local edge = d < MEADOW.Thin
						if edge then
							p = p * (0.1 + 0.4 * (d - MEADOW.Edge) / (MEADOW.Thin - MEADOW.Edge))
							mix = MEADOW.Mix.edge
						end
						if hash3(i, 3, k, seed) < p then
							local kind = pick(mix, hash3(i, 4, k, seed))
							local tint = 0
							if kind == 5 then
								if zone == "wild" then
									tint = MEADOW.WildTints[math.floor(hash3(i, 5, k, seed) * #MEADOW.WildTints) + 1]
								elseif zone == "mown" then
									tint = (hash3(i, 5, k, seed) < 0.7) and 3 or 2 -- daisies, a few buttercups
								else
									tint = math.floor(hash3(i, 5, k, seed) * #FLOWERS) + 1
								end
							end
							add(kind, tint, x, z, hash3(i, 9, k, seed), zoneScale(zone, edge, hash3(i, 6, k, seed)), code, zone, false)
						end
					end
				end
			end
		end
		-- the seed drifts: the bed's two colours on a finer 1-stud grid, densest by the sack, thinning downwind
		for ci, c in ipairs(comets or {}) do
			local L_ = MEADOW.Drift.Length
			local reach = L_ + MEADOW.Drift.Width0 + L_ * MEADOW.Drift.Spread + 1
			local i0, i1 = math.floor(c.From.X - reach), math.ceil(c.From.X + reach)
			local k0, k1 = math.floor(c.From.Z - reach), math.ceil(c.From.Z + reach)
			for i = i0, i1 do
				for k = k0, k1 do
					local hs = seed + 50 + ci
					local x, z = i + 0.1 + 0.8 * hash3(i, 11, k, hs), k + 0.1 + 0.8 * hash3(i, 12, k, hs)
					local t, side, half = inComet(c, x, z)
					local idx = gridIndex(g, x, z)
					local code = idx and g.Code[idx] or 0
					if t and (code == 1 or code == 2) and distAt(g, x, z) >= MEADOW.Edge * 0.8 then
						local fall = 1 - math.max(0, t) / L_
						local core = 1 - side / (half + 0.01)
						local p = 0.9 * (fall ^ 0.6) * (0.5 + 0.5 * core)
						if hash3(i, 13, k, hs) < p then
							local r = hash3(i, 14, k, hs)
							local kind, tint = 5, c.Tints[(hash3(i, 15, k, hs) < 0.55) and 1 or 2]
							if r > 0.9 then
								kind, tint = 4, 0
							elseif r > 0.85 then
								kind, tint = 8, 0
							end
							add(kind, tint, x, z, hash3(i, 16, k, hs), 0.74 + 0.22 * hash3(i, 17, k, hs), code, zoneOf(x - g.CX, z - g.CZ) or "mown", true)
						end
					end
				end
			end
		end
	end

	-- dandelion seeds drifting off the wild lawns: one invisible emitter box per sector rich in seed clocks
	local function buildSeeds(parent, clumps)
		local K = MEADOW.Seeds
		local sectors = {}
		for _, c in ipairs(clumps) do
			if c.Kind == 7 and c.Zone == "wild" then
				local a = math.floor(((math.deg(atan2(c.Z, c.X)) % 360) / 360) * K.Sectors) + 1
				local s = sectors[a] or { N = 0, X = 0, Z = 0, X2 = 0, Z2 = 0 }
				s.N, s.X, s.Z = s.N + 1, s.X + c.X, s.Z + c.Z
				s.X2, s.Z2 = s.X2 + c.X * c.X, s.Z2 + c.Z * c.Z
				sectors[a] = s
			end
		end
		local model = newModel(parent, "MeadowSeeds")
		CollectionService:AddTag(model, DETAIL_TAG)
		local w = MEADOW.Wind
		for a = 1, K.Sectors do
			local s = sectors[a]
			if s and s.N >= K.MinClocks then
				local mx, mz = s.X / s.N, s.Z / s.N
				local sx = math.sqrt(math.max(1, s.X2 / s.N - mx * mx)) * 2
				local sz = math.sqrt(math.max(1, s.Z2 / s.N - mz * mz)) * 2
				local anchor = anchorPart(model, "Seeds" .. a, Vector3.new(OX + mx, TOP + 0.4, OZ + mz),
					Vector3.new(math.min(40, sx), 0.6, math.min(40, sz)))
				local e = emitter(anchor, {
					Texture = MEADOW.GLOW,
					Color = ColorSequence.new(rgb(255, 255, 250)),
					LightEmission = 0.25,
					LightInfluence = 0.6,
					Rate = K.Rate,
					Lifetime = NumberRange.new(6, 10),
					Speed = NumberRange.new(0.4, 1.0),
					SpreadAngle = Vector2.new(25, 25),
					Acceleration = Vector3.new(w.X * 0.9, 0.12, w.Z * 0.9),
					Drag = 0.35,
					Size = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(0.1, 0.16),
						NumberSequenceKeypoint.new(0.85, 0.13),
						NumberSequenceKeypoint.new(1, 0),
					}),
					Transparency = FADE_IN_OUT,
					RotSpeed = NumberRange.new(-40, 40),
				})
				e.Name = "DandelionSeeds"
				pcall(function()
					e.Shape = Enum.ParticleEmitterShape.Box
					e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
				end)
			end
		end
		return model
	end

	-- publish the clumps for the clients (MeadowFx): attributes only, no parts
	local function publish(root, clumps)
		local folder = Instance.new("Folder")
		folder.Name = "Meadow"
		local chunk, buf, nchunks = MEADOW.ChunkClumps, {}, 0
		for i, c in ipairs(clumps) do
			buf[#buf + 1] = Meadow.encode(c)
			if #buf >= chunk or i == #clumps then
				nchunks = nchunks + 1
				folder:SetAttribute("Clumps" .. nchunks, table.concat(buf))
				buf = {}
			end
		end
		folder:SetAttribute("Version", MEADOW.Version)
		folder:SetAttribute("Count", #clumps)
		folder:SetAttribute("Chunks", nchunks)
		folder:SetAttribute("Wind", MEADOW.Wind)
		folder:SetAttribute("Base", TOP - LAWN)
		folder:SetAttribute("Origin", Vector3.new(OX, 0, OZ))
		folder:SetAttribute("Kinds", table.concat(MEADOW.Kinds, ","))
		for i, col in ipairs(FLOWERS) do
			folder:SetAttribute("Tint" .. i, col)
		end
		folder.Parent = root
		return folder
	end

	function Meadow.build(root, L)
		local parts = lobbyParts(root)
		local clumps = { Stats = {} }
		local plaza = root:FindFirstChild("Plaza")
		-- the plaza: wild beyond the circle walk, mown inside it
		if plaza then
			local g = areaGrid(OX, OZ, PLAZA_R - 4.5)
			rasterise(g, parts)
			local decor = plaza:FindFirstChild("LawnDecor") or plaza
			local okSacks, comets = pcall(buildSacks, root, g, decor)
			if not okSacks then
				warn("[LobbyBuilder] meadow sacks failed: " .. tostring(comets))
				comets = {}
			end
			local wildR = G.RingRoadR + G.PathHalf
			scatter(g, clumps, function(x, z)
				local r = math.sqrt(x * x + z * z)
				if r > wildR then
					return "wild"
				end
				return "mown"
			end, 1201, comets, L and L.NpcSpots)
			clumps.Comets = comets
		end
		-- the shop lawn and the garden islands: a lighter garden mix
		local shop = root:FindFirstChild("Shop")
		if shop and L and L.ShopCenter then
			local g = areaGrid(L.ShopCenter.X, L.ShopCenter.Z, (L.ShopR or 30) - 3)
			rasterise(g, parts)
			scatter(g, clumps, function()
				return "garden"
			end, 1301)
		end
		local gardens = root:FindFirstChild("Gardens")
		if gardens and L and L.Gardens then
			for gi, spec in ipairs(L.Gardens) do
				local c = polar(spec.Angle, G.GardenR, TOP)
				local g = areaGrid(c.X, c.Z, G.GardenSize - 3)
				rasterise(g, parts)
				scatter(g, clumps, function()
					return "garden"
				end, 1400 + gi)
			end
		end
		local stats = clumps.Stats
		clumps.Stats = nil
		local comets = clumps.Comets or {}
		clumps.Comets = nil
		section("meadow seeds", function()
			buildSeeds(plaza or root, clumps)
		end)
		local folder = publish(root, clumps)
		stats.Total = #clumps
		stats.Sacks = #comets
		MEADOW.Stats = stats
		MEADOW.Last = { Clumps = clumps, Comets = comets, Folder = folder }
		return folder
	end

	return Meadow
end)()

function LobbyBuilder.Build()
	templates = {}
	reserved = {}
	machineBoxCache = nil
	Mesh.Names = {}

	local old = Workspace:FindFirstChild("NimbusLobby")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "NimbusLobby"

	local L = computeLayout()
	if not Voxel then
		warn("[LobbyBuilder] shared/Voxel is missing: building the plain fallback lobby")
	end

	-- Gameplay-critical objects first (gates, spots, shop); each has a bare-bones fallback.
	-- The Gate Court (6.1): Obby, Altar here; Ring / Arena (ArenaBuilder) and Dungeon (DungeonBuilder) join the
	-- same folder later, at GateSites.
	local gatesFolder = newFolder(root, "Gates")
	local sites = Gates.Sites(L)
	local gates = {}
	for _, id in ipairs(Gates.Built) do
		local ok, gate = pcall(Gates.BuildOne, gatesFolder, sites[id], id)
		if not ok then
			warn("[LobbyBuilder] gate " .. id .. ": " .. tostring(gate))
			gate = { Model = nil }
		end
		if not gate.Model then
			local spec = Gates.Spec(id)
			local m, pad, prompt = Gates.Fallback(gatesFolder, sites[id], id, Gates.Info[id], gateAccent(spec.Accent))
			gate = { Model = m, Pad = pad, PromptPart = prompt, Site = sites[id] }
		end
		gates[id] = gate
	end
	local portals = {}
	local okObby, obbyInfo = pcall(Gates.ObbyPortal, gates.Obby)
	if okObby then
		portals.Obby = obbyInfo
	else
		warn("[LobbyBuilder] obby portal zone failed: " .. tostring(obbyInfo))
	end

	local spots = {}
	local spotFolder = newFolder(root, "Spots")
	for i = 1, SPOT_COUNT do
		local angle = L.PlotAngles[i]
		local ok, result = pcall(buildSpot, spotFolder, i, angle)
		if not ok then
			warn("[LobbyBuilder] spot " .. tostring(i) .. " failed: " .. tostring(result))
			result = fallbackSpot(spotFolder, i, angle)
		end
		spots[i] = result
	end

	local okShop, shop = pcall(buildShop, root, L)
	if not okShop then
		warn("[LobbyBuilder] shop failed: " .. tostring(shop))
		local broken = root:FindFirstChild("Shop")
		if broken then
			broken:Destroy()
		end
		shop = fallbackShop(root, L)
	end

	-- The plaza ground is where everyone spawns: keep a plain floor if the voxel plaza cannot be built.
	local okPlaza = section("plaza", function()
		buildPlaza(root, L)
	end)
	if not okPlaza or not root:FindFirstChild("Plaza") or not root.Plaza:FindFirstChild("Paths") then
		local floor = newFolder(root, "PlazaFallback")
		box(floor, "PlazaFloor", CFrame.new(OX, TOP - 1, OZ), Vector3.new(PLAZA_R * 1.7, 2, PLAZA_R * 1.7), C.Grass, { Collide = true })
		box(floor, "ShopNeckFloor", CFrame.new((Vector3.new(OX, TOP - 1, OZ) + L.ShopCenter - Vector3.new(0, 1, 0)) * 0.5), Vector3.new(16, 2, L.ShopDist), C.Stone, { Collide = true })
	end
	if type(L.NpcSpots) ~= "table" or #L.NpcSpots < 6 then
		L.NpcSpots = defaultNpcSpots(L)
	end

	section("roads", function()
		buildRoads(root, L)
	end)
	section("gardens", function()
		local gf = newFolder(root, "Gardens")
		for _, spec in ipairs(L.Gardens) do
			section("garden " .. spec.Name, function()
				buildGarden(gf, spec, L)
			end)
		end
	end)
	section("sky", function()
		buildSky(root)
	end)
	section("benches", function()
		Benches.wire(root) -- bug batch 2 #7: the Sit prompts of every bench (plaza lawns + gardens)
	end)
	section("meadow", function()
		Meadow.build(root, L) -- bug #12: where the grass and wildflowers grow (after every prop has its place)
	end)

	root.Parent = Workspace
	-- the templates and merged box lists are only needed while building
	templates = {}
	machineBoxCache = nil

	-- Spawn on the medallion in the middle of the spawn court, looking up the avenue at the Gate Court.
	local spawnPos = Vector3.new(OX, TOP + 3, OZ)
	local focus = polar(L.MidAngle, G.GateR, TOP + 3)
	local altarSite = nil
	local altarDock = nil
	if L.AltarAngle then
		altarSite = faceCentre(polar(L.AltarAngle, G.GardenR, TOP))
		altarDock = polar(L.AltarAngle, G.SpokeEndR - 2.4, TOP)
	end
	-- Phase 3: where ArenaBuilder links the Battle Arena (the outer edge of the junction on the arena spoke's ray)
	local arenaDock = nil
	if L.ArenaAngle then
		arenaDock = polar(L.ArenaAngle, (G.StreetR + G.StreetW / 2) / math.cos(math.rad(G.HalfStep)), TOP)
	end

	local parts = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			parts = parts + 1
		end
	end
	print(string.format("[LobbyBuilder] lobby built (%d parts, %d gates, %d plots)", parts, #Gates.Built, #spots))

	local gateInfo = {}
	for id, g in pairs(gates) do
		gateInfo[id] = { Model = g.Model, Pad = g.Pad, PromptPart = g.PromptPart }
	end
	-- bug batch 2 #4: where the Storm Altar's return portal (GateService gate "Plaza") lands: on the plaza 18 studs in
	-- front of the Altar gate (~15.2 from its PromptAnchor at 2.8 out, well clear of the 12-stud prompt), 3 studs up,
	-- looking at the plaza
	local altarGate = sites.Altar
	if gateInfo.Altar and typeof(altarGate) == "CFrame" then
		local front = altarGate.Position + altarGate.LookVector * 18
		gateInfo.Altar.ReturnCFrame = CFrame.lookAt(front + Vector3.new(0, 3, 0), front + altarGate.LookVector * 30 + Vector3.new(0, 3, 0))
	end
	return {
		Folder = root,
		SpawnCFrame = flatLook(spawnPos, focus),
		Portals = portals, -- Phase 5: exactly { Obby = PortalInfo } (6.3)
		Spots = spots,
		Shop = shop,
		NpcSpots = L.NpcSpots,
		AltarSite = altarSite, -- the Storm Altar island (StormAltar.Build), faces the plaza
		AltarDock = altarDock, -- street inner edge where the bridge to the altar island docks
		-- Phase 3 (ArenaBuilder): the arena bridge leaves the street here, straight out along ArenaAngle (degrees, the
		-- spoke's ray through that junction, whose outer rail is open ArenaBridgeWidth + 1.6 studs)
		ArenaAngle = L.ArenaAngle,
		ArenaDock = arenaDock,
		ArenaBridgeWidth = G.ArenaBridgeW,
		-- Phase 5 Gate Court (6.1): ground CFrame of every gate centre (LookVector = towards the plaza centre), the
		-- folder every gate builder parents its gate to, and the lobby's own gates
		GateSites = sites,
		GatesFolder = gatesFolder,
		Gates = gateInfo, -- bug batch 2 #4: Gates.Altar.ReturnCFrame = the Storm Altar return portal's arrival
		RingSite = sites.Ring, -- ArenaBuilder's Portal_Ring (C12)
		DungeonSite = sites.Dungeon, -- DungeonBuilder.BuildPortal (W3)
	}
end

----------------------------------------------------------------------
-- Phase 6 kit hooks (read-only; the game never calls them): blender/kit/props/lobby_world.py sets
-- LobbyBuilder._Kit = { Targets = {}, Clouds = {} } before Build() to list every mesh target (key, subtree, origin) and
-- every voxel cloud spec, then re-voxels a cloud at a finer grain with _CloudGrid. Tests use _Mesh (Signature, tag).
----------------------------------------------------------------------
LobbyBuilder._Kit = nil
LobbyBuilder._Mesh = Mesh
LobbyBuilder._Oasis = OASIS -- bug #13: the fountain layout (tests compare it with the committed meshes)
LobbyBuilder._Benches = Benches -- bug batch 2 #7: tests call _Benches.sit / .check
LobbyBuilder._Meadow = Meadow -- bug #12: tests decode the scatter (Meadow.decode, Meadow.K.Stats / .Last)

-- the cells of a recorded VX.Cloud spec at `V` studs per voxel (tier heights keep their stud thickness)
function LobbyBuilder._CloudGrid(spec, V)
	local V0 = spec.V or 3
	local copy = {}
	for k, v in pairs(spec) do
		copy[k] = v
	end
	copy.V = V
	copy.Tiers = {}
	for i, t in ipairs(spec.Tiers) do
		local tt = {}
		for k, v in pairs(t) do
			tt[k] = v
		end
		tt.H = math.max(1, math.floor((t.H or 1) * V0 / V + 0.5))
		copy.Tiers[i] = tt
	end
	return VX.Cloud(copy)
end

return LobbyBuilder
