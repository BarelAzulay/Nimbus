--!nocheck
-- DungeonBuilder (ARCHITECTURE_V3.md "Phase 5 build contract" 5.5, art per image 22, the rules of 6.4; dungeon W3)
--
-- The Dungeon gate in the Gate Court and the run instances (pockets) of DungeonService.
--
--   DungeonBuilder.Build(lobbyInfo) -> DungeonInfo    the gate (BuildPortal) + the template folder; the templates are
--                                                      built in a task.spawn after boot, one set per task.wait()
--   DungeonBuilder.BuildPortal(gatesFolder, siteCFrame) -> DungeonInfo { Portal, Pad, PromptPart, ReturnCFrame, Prompt }
--                                                      WorldStyle.BuildGate (Purple, "torch", pill from the attribute
--                                                      DungeonBoard) + two torches, <= 120 parts; prompt "DungeonPrompt"
--                                                      with OpenPanel = "Dungeon" on the prompt part
--   DungeonBuilder.BuildRun(index, floor, seed) -> Pocket { Index, Origin, Model, Floor, Seed, Layout, Rooms, Hall }
--                                                      the holder workspace.Dungeons.Dungeon_<index>, the Entrance Hall,
--                                                      the corridor to room 1 and room 1 (rooms chained on a seeded
--                                                      corridor path, never overlapping)
--   DungeonBuilder.PlaceRoom(pocket, room) -> RoomInfo  room 1..4 (5 = the treasure alcove): the template cloned, the
--                                                      Accent parts recoloured to the floor's element, the NC_BattleZone
--                                                      part (Mode "Dungeon", ZoneId "Room", Index, Room), the Threshold
--                                                      and the two bar doors; assembled under ServerStorage and parented
--                                                      in ONE step
--   DungeonBuilder.RemoveRoom(pocket, room)           destroys that room (and its inbound corridor)
--   DungeonBuilder.SetDoor(roomInfo, "Entrance"|"Exit", open) the bars' two states (CanCollide + Transparency) + the
--                                                      room model attributes DoorOpen (exit) / EntranceOpen
--   DungeonBuilder.FreeRun(index)                     the holder destroyed; the Dungeons folder goes with the last run
--   DungeonBuilder.Template(name) -> Model            a template (built on demand); EnsureTemplates() builds every set
--   DungeonBuilder.CountParts(instance) -> n          BasePart descendants
--   DungeonBuilder.Templates / Budgets / Kinds        data for tests and the renderer
--
-- RoomInfo = { Index, Kind, Template, Model, Zone, Entrance (CFrame), Threshold (part), Door = { Bars }, ExitDoor =
--             { Bars }, Center (Vector3), Spawns = { CFrame... }, Chests = { part... }, Corridor }
--
-- Art: Slate / Cobblestone / Brick walls with plinth, body and cap, 6-stud flagstone floors (+-0.05 alternation), wall
-- torches (bracket + stick + Neon flame + Fire + PointLight range 18 amber, Shadows off), puddles, moss, barrels,
-- crates, chains, pillars, arches, a portcullis on every door, stairs to a dais and a throne under a plum carpet (the
-- Throne set), caves with rock walls, stalagmites, a turquoise pool and a waterfall wall, bridges over a dark chasm
-- (an invisible floor under it), a dark stone ceiling 16 studs up. Materials from WorldStyle.Materials only (rule 1:
-- the design's Sandstone / Rock are Cobblestone / Slate here); saturated colours only on small pieces or Neon inlays;
-- parts < 4 studs do not cast shadows (Voxel.Box). Budgets per template: wave room <= 320, boss room <= 420, hall <=
-- 140, corridor <= 70, treasure <= 90; live per run hall + room k + corridor + room k+1 <= 950.
-- Plain Lua 5.1 syntax only (Luau subset).

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Voxel = require(Shared.Voxel)
local WorldStyle = require(Shared.WorldStyle)

local DungeonBuilder = {}

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local PI = math.pi
local rgb = Color3.fromRGB

local M = WorldStyle.Materials
local ZONE_TAG = "NC_BattleZone"
local DETAIL_TAG = (WorldStyle.Tags and WorldStyle.Tags.Detail) or "NC_Detail"
local TEMPLATE_FOLDER = "DungeonTemplates"
local DUNGEONS_FOLDER = "Dungeons"
local WALL_H = 15 -- wall height; the ceiling slab sits on the cap, 16 studs up
local CEIL_Y = 15.8
local TILE = 6
local MAX_INDEX = 12
local JOG = 15 -- the lateral shift of a Left / Right corridor

-- the chain of a run (room 0 = the hall, 1..4 the fight rooms, 5 the treasure alcove); every piece heads +Z
DungeonBuilder.Budgets = { Room = 320, Boss = 420, Hall = 140, Corridor = 70, Treasure = 90, Run = 950, Portal = 120 }
DungeonBuilder.Kinds = { Hall = 3, Cellar = 3, Cave = 3, Bridge = 2, Throne = 1 }
DungeonBuilder.Templates = {
	"Hall_1", "Hall_2", "Hall_3", "Cellar_1", "Cellar_2", "Cellar_3", "Cave_1", "Cave_2", "Cave_3", "Bridge_1", "Bridge_2",
	"Throne_1", "Entrance_1", "Corridor_Straight", "Corridor_Left", "Corridor_Right", "Treasure_1",
}

----------------------------------------------------------------------
-- Colours (big faces: saturation <= 0.45, value 0.35..0.9)
----------------------------------------------------------------------
local C = {
	Stone = rgb(122, 120, 116),
	StoneDark = rgb(98, 96, 94),
	StoneLight = rgb(146, 142, 136),
	Brick = rgb(134, 112, 102),
	Flag = rgb(176, 162, 134), -- the warm flagstone floor
	FlagDark = rgb(150, 138, 114),
	Ceiling = rgb(96, 92, 98),
	Wood = rgb(118, 88, 66),
	Plank = rgb(150, 116, 86),
	Iron = rgb(92, 92, 100),
	Gold = rgb(200, 166, 98),
	Flame = rgb(255, 184, 96),
	Ember = rgb(255, 120, 60),
	Light = rgb(255, 190, 120), -- amber torch light
	Moss = rgb(104, 136, 92),
	Hay = rgb(206, 182, 112),
	Water = rgb(110, 184, 184), -- the muted turquoise pool
	WaterGlow = rgb(140, 230, 230),
	Puddle = rgb(140, 170, 190),
	Carpet = rgb(132, 92, 150), -- plum: the big face stays under 0.45 saturation
	Rock = rgb(112, 104, 100),
	RockDark = rgb(98, 92, 90),
	Abyss = rgb(92, 88, 100),
	Bone = rgb(222, 214, 196),
	Marble = rgb(206, 200, 210),
}

----------------------------------------------------------------------
-- Small deterministic RNG per template (never math.random: templates are the same on every server)
----------------------------------------------------------------------
local function rng(seed)
	local s = floor(seed or 1) % 2147483647
	if s <= 0 then
		s = s + 2147483646
	end
	return function(n)
		s = (s * 48271) % 2147483647
		if n then
			return 1 + (s % n)
		end
		return s / 2147483647
	end
end

local function jitter(color, seed)
	local ok, c = pcall(WorldStyle.Jitter, color, seed, 6)
	if ok and typeof(c) == "Color3" then
		return c
	end
	return color
end

----------------------------------------------------------------------
-- Kit: the parts (Voxel.Box) of the dungeon
----------------------------------------------------------------------
local Kit = {}

-- a box; opts: Name, Collide, Material, Transparency, Shape, Accent, Detail
function Kit.part(parent, cf, size, color, mat, opts)
	opts = opts or {}
	local props = { Name = opts.Name or "Stone", CanCollide = opts.Collide == true, CanQuery = opts.Collide == true, CanTouch = false }
	if opts.Transparency then
		props.Transparency = opts.Transparency
	end
	if opts.Shape then
		props.Shape = opts.Shape
	end
	local p = Voxel.Box(parent, cf, size, color, mat or M.Slate, props)
	if opts.Accent then
		p:SetAttribute("Accent", true)
	end
	return p
end

-- the floor: TILE-stud flagstones with +-0.05 alternation, top at y 0, walkable
function Kit.floorTiles(parent, w, d, color, mat, seed, y)
	local nx, nz = max(1, floor(w / TILE + 0.5)), max(1, floor(d / TILE + 0.5))
	local tw, td = w / nx, d / nz
	local base = y or 0
	local n = 0
	for i = 1, nx do
		for j = 1, nz do
			local lift = ((i + j) % 2 == 0) and 0.05 or -0.05
			local x = -w / 2 + (i - 0.5) * tw
			local z = -d / 2 + (j - 0.5) * td
			local c = color
			if (i * 7 + j * 3 + seed) % 6 == 0 then
				c = C.FlagDark
			end
			Kit.part(parent, CFrame.new(x, base - 0.5 + lift, z), Vector3.new(tw, 1, td), jitter(c, seed * 31 + i * 7 + j), mat or M.Cobblestone, { Name = "Floor", Collide = true })
			n = n + 1
		end
	end
	-- cracks between the flagstones
	local r = rng(seed * 13 + 5)
	for k = 1, max(2, floor((nx * nz) / 12)) do
		local x = -w / 2 + 4 + r() * (w - 8)
		local z = -d / 2 + 4 + r() * (d - 8)
		Kit.part(parent, CFrame.new(x, base + 0.06, z) * CFrame.Angles(0, r() * PI, 0), Vector3.new(2.5 + r() * 3, 0.12, 0.25), C.StoneDark, M.Slate, { Name = "Crack" })
		n = n + 1
	end
	return n
end

-- a wall of length `len` whose centre is `cf` (local X along the wall, LookVector into the room): plinth band, body,
-- cap, a few protruding stones; door = { X = offset, Width } leaves a doorway with a lintel
function Kit.wall(parent, cf, len, color, mat, seed, door, lite)
	local h = WALL_H
	local r = rng(seed)
	-- plinth (rule 3)
	Kit.part(parent, cf * CFrame.new(0, 0.6, -0.35), Vector3.new(len, 1.2, 1.7), C.StoneDark, M.Slate, { Name = "Plinth", Collide = true })
	if door then
		local dw = door.Width or 8
		local dx = door.X or 0
		local leftLen = (dx - dw / 2) - (-len / 2)
		local rightLen = (len / 2) - (dx + dw / 2)
		if leftLen > 0.5 then
			Kit.part(parent, cf * CFrame.new(-len / 2 + leftLen / 2, h / 2, 0), Vector3.new(leftLen, h, 1), jitter(color, seed), mat, { Name = "Wall", Collide = true })
		end
		if rightLen > 0.5 then
			Kit.part(parent, cf * CFrame.new(len / 2 - rightLen / 2, h / 2, 0), Vector3.new(rightLen, h, 1), jitter(color, seed + 1), mat, { Name = "Wall", Collide = true })
		end
		-- the wall above the doorway
		Kit.part(parent, cf * CFrame.new(dx, (h + 8) / 2, 0), Vector3.new(dw, h - 8, 1), jitter(color, seed + 2), mat, { Name = "Wall", Collide = true })
	else
		Kit.part(parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(len, h, 1), jitter(color, seed), mat, { Name = "Wall", Collide = true })
	end
	-- cap / cornice, the dado band and two mortar courses (the brick read of image 22)
	Kit.part(parent, cf * CFrame.new(0, h + 0.4, -0.3), Vector3.new(len, 0.8, 1.6), C.StoneDark, M.Slate, { Name = "Cap" })
	if lite then
		Kit.part(parent, cf * CFrame.new(0, 7.2, -0.55), Vector3.new(len, 0.4, 0.12), C.StoneDark, M.Brick, { Name = "Course" })
	elseif not door then
		Kit.part(parent, cf * CFrame.new(0, 3.4, -0.6), Vector3.new(len, 0.5, 0.2), C.StoneDark, M.Brick, { Name = "Dado" })
		Kit.part(parent, cf * CFrame.new(0, 7.2, -0.55), Vector3.new(len, 0.4, 0.12), C.StoneDark, M.Brick, { Name = "Course" })
		Kit.part(parent, cf * CFrame.new(0, 11, -0.55), Vector3.new(len, 0.4, 0.12), C.StoneDark, M.Brick, { Name = "Course" })
	else
		Kit.part(parent, cf * CFrame.new(0, 11.4, -0.55), Vector3.new(len, 0.4, 0.12), C.StoneDark, M.Brick, { Name = "Course" })
	end
	-- protruding stones
	local n = lite and 2 or max(4, min(8, floor(len / 5)))
	for i = 1, n do
		local x = -len / 2 + 2 + r() * (len - 4)
		local y = 1.6 + r() * (h - 4)
		if not door or abs(x - (door.X or 0)) > (door.Width or 8) / 2 + 1.2 or y > 8.5 then
			local sw = 1.8 + r() * 1.4
			local shade = (i % 3 == 0) and C.StoneDark or C.StoneLight
			Kit.part(parent, cf * CFrame.new(x, y, -0.6), Vector3.new(sw, 1.0, 0.4), jitter(shade, seed + i * 3), M.Slate, { Name = "Brick" })
		end
	end
end

function Kit.pillar(parent, cf, h, color)
	Kit.part(parent, cf * CFrame.new(0, 0.5, 0), Vector3.new(2.6, 1, 2.6), C.StoneDark, M.Slate, { Name = "PillarBase", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(2, h, 2), color or C.Stone, M.Slate, { Name = "Pillar", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, h - 0.4, 0), Vector3.new(2.6, 0.8, 2.6), C.StoneDark, M.Slate, { Name = "PillarCap" })
end

-- a wall torch: cf = the mount point on the wall face (LookVector into the room)
function Kit.torch(parent, cf, bright)
	Kit.part(parent, cf * CFrame.new(0, 0.6, -0.1), Vector3.new(1.2, 2.2, 0.2), C.Iron, M.Metal, { Name = "Sconce" })
	Kit.part(parent, cf * CFrame.new(0, 0, -0.3), Vector3.new(0.5, 0.7, 0.6), C.Iron, M.Metal, { Name = "Bracket" })
	Kit.part(parent, cf * CFrame.new(0, 0.7, -0.75) * CFrame.Angles(-0.35, 0, 0), Vector3.new(0.3, 1.8, 0.3), C.Wood, M.Wood, { Name = "Stick" })
	local flame = Kit.part(parent, cf * CFrame.new(0, 1.9, -1.05), Vector3.new(0.8, 1.3, 0.8), C.Flame, M.Neon, { Name = "Flame" })
	local light = Instance.new("PointLight")
	light.Name = "TorchLight"
	light.Color = C.Light
	light.Brightness = bright or 1.2
	light.Range = 18
	light.Shadows = false
	light.Parent = flame
	pcall(function()
		local fire = Instance.new("Fire")
		fire.Name = "TorchFire"
		fire.Size = 2
		fire.Heat = 4
		fire.Color = C.Flame
		fire.SecondaryColor = C.Ember
		fire.Parent = flame
	end)
	return flame
end

-- a doorway's portcullis: cf = the doorway centre on the floor (LookVector into the room); the bars are a Model
function Kit.door(parent, cf, name, width)
	local w = width or 8
	local h = 8
	local door = Instance.new("Model")
	door.Name = name
	Kit.part(door, cf * CFrame.new(-w / 2 - 0.5, h / 2, 0), Vector3.new(1, h, 1.6), C.StoneDark, M.Slate, { Name = "Jamb", Collide = true })
	Kit.part(door, cf * CFrame.new(w / 2 + 0.5, h / 2, 0), Vector3.new(1, h, 1.6), C.StoneDark, M.Slate, { Name = "Jamb", Collide = true })
	Kit.part(door, cf * CFrame.new(0, h + 0.5, 0), Vector3.new(w + 2, 1, 1.6), C.StoneDark, M.Slate, { Name = "Lintel", Collide = true })
	local n = max(3, floor(w / 1.6))
	local bars = {}
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * (w / n)
		bars[i] = Kit.part(door, cf * CFrame.new(x, h / 2, 0), Vector3.new(0.35, h, 0.35), C.Iron, M.Metal, { Name = "Bar", Collide = true })
	end
	door:SetAttribute("Open", false)
	door.Parent = parent
	return door, bars
end

function Kit.setDoor(door, open)
	if not door then
		return
	end
	for _, bar in ipairs(door:GetChildren()) do
		if bar.Name == "Bar" and bar:IsA("BasePart") then
			bar.CanCollide = not open
			bar.CanQuery = not open
			bar.Transparency = open and 1 or 0
		end
	end
	door:SetAttribute("Open", open == true)
end

function Kit.ceiling(parent, w, d, y)
	Kit.part(parent, CFrame.new(0, (y or CEIL_Y) + 0.5, 0), Vector3.new(w + 2, 1, d + 2), C.Ceiling, M.Slate, { Name = "Ceiling" })
end

-- props (pure decor sits in one NC_Detail model per room)
function Kit.barrel(parent, cf)
	local up = CFrame.Angles(0, 0, PI / 2)
	Kit.part(parent, cf * CFrame.new(0, 1.6, 0) * up, Vector3.new(3.2, 2.8, 2.8), C.Wood, M.Wood, { Name = "Barrel", Shape = Enum.PartType.Cylinder, Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 0.7, 0) * up, Vector3.new(0.25, 2.95, 2.95), C.Iron, M.Metal, { Name = "Band", Shape = Enum.PartType.Cylinder })
	Kit.part(parent, cf * CFrame.new(0, 2.5, 0) * up, Vector3.new(0.25, 2.95, 2.95), C.Iron, M.Metal, { Name = "Band", Shape = Enum.PartType.Cylinder })
end

function Kit.crate(parent, cf, s)
	s = s or 3
	Kit.part(parent, cf * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), C.Plank, M.WoodPlanks, { Name = "Crate", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, s / 2, s / 2 + 0.05), Vector3.new(s * 0.9, 0.3, 0.1), C.Wood, M.Wood, { Name = "Slat" })
	Kit.part(parent, cf * CFrame.new(0, s / 2, -s / 2 - 0.05), Vector3.new(s * 0.9, 0.3, 0.1), C.Wood, M.Wood, { Name = "Slat" })
end

function Kit.chain(parent, cf)
	for i = 0, 2 do
		Kit.part(parent, cf * CFrame.new((i % 2) * 0.2 - 0.1, -i * 0.9, 0), Vector3.new(0.35, 1, 0.2), C.Iron, M.Metal, { Name = "Chain" })
	end
end

function Kit.puddle(parent, cf, w, d)
	Kit.part(parent, cf * CFrame.new(0, 0.07, 0), Vector3.new(w or 4, 0.14, d or 3), C.Puddle, M.Glass, { Name = "Puddle", Transparency = 0.35, Accent = true })
end

function Kit.moss(parent, cf, w, d)
	Kit.part(parent, cf * CFrame.new(0, 0.1, 0), Vector3.new(w or 3, 0.2, d or 2), C.Moss, M.Grass, { Name = "Moss" })
end

function Kit.hay(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 0.55, 0), Vector3.new(4.4, 1.1, 3.6), C.Hay, M.Sand, { Name = "Hay" })
	Kit.part(parent, cf * CFrame.new(0.5, 1.35, -0.3) * CFrame.Angles(0, 0.4, 0), Vector3.new(2.6, 0.6, 2), C.Hay, M.Sand, { Name = "Hay" })
end

function Kit.table(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 2.5, 0), Vector3.new(7, 0.45, 3), C.Plank, M.WoodPlanks, { Name = "TableTop", Collide = true })
	Kit.part(parent, cf * CFrame.new(-2.8, 1.15, 0), Vector3.new(0.6, 2.3, 2.4), C.Wood, M.Wood, { Name = "TableLeg" })
	Kit.part(parent, cf * CFrame.new(2.8, 1.15, 0), Vector3.new(0.6, 2.3, 2.4), C.Wood, M.Wood, { Name = "TableLeg" })
	Kit.part(parent, cf * CFrame.new(-1.6, 3.0, 0.4), Vector3.new(0.9, 0.6, 0.9), C.Gold, M.Metal, { Name = "Cup" })
	Kit.part(parent, cf * CFrame.new(1.4, 2.9, -0.5), Vector3.new(1.6, 0.3, 1.2), C.Bone, M.Marble, { Name = "Plate" })
end

function Kit.bench(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 1.3, 0), Vector3.new(6, 0.4, 1.4), C.Plank, M.WoodPlanks, { Name = "Bench", Collide = true })
	Kit.part(parent, cf * CFrame.new(-2.4, 0.55, 0), Vector3.new(0.5, 1.1, 1.2), C.Wood, M.Wood, { Name = "BenchLeg" })
	Kit.part(parent, cf * CFrame.new(2.4, 0.55, 0), Vector3.new(0.5, 1.1, 1.2), C.Wood, M.Wood, { Name = "BenchLeg" })
end

function Kit.bones(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0.5, 0), Vector3.new(2.2, 0.35, 0.35), C.Bone, M.Marble, { Name = "Bone" })
	Kit.part(parent, cf * CFrame.new(0.8, 0.2, 0.6) * CFrame.Angles(0, -0.9, 0), Vector3.new(1.6, 0.3, 0.3), C.Bone, M.Marble, { Name = "Bone" })
end

-- a hanging banner (Accent: recoloured to the floor's element) on a wall mount point
function Kit.banner(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 0, -0.5), Vector3.new(4.4, 0.3, 0.3), C.Wood, M.Wood, { Name = "BannerPole" })
	Kit.part(parent, cf * CFrame.new(0, -2.8, -0.45), Vector3.new(3.6, 5.4, 0.25), WorldStyle.Palette.Accent.Purple, M.Fabric, { Name = "Banner", Accent = true })
end

-- a thin Neon rune inlay in the floor (Accent)
function Kit.rune(parent, cf, w, d)
	Kit.part(parent, cf * CFrame.new(0, 0.08, 0), Vector3.new(w or 3, 0.16, d or 0.6), WorldStyle.Palette.Accent.Purple, M.Neon, { Name = "Rune", Accent = true })
end

function Kit.arch(parent, cf, width, height)
	local w, h = width or 10, height or 11
	Kit.pillar(parent, cf * CFrame.new(-w / 2 - 1, 0, 0), h - 2, C.StoneLight)
	Kit.pillar(parent, cf * CFrame.new(w / 2 + 1, 0, 0), h - 2, C.StoneLight)
	Kit.part(parent, cf * CFrame.new(0, h - 0.6, 0), Vector3.new(w + 4.6, 1.2, 2.2), C.StoneLight, M.Slate, { Name = "ArchLintel" })
	Kit.part(parent, cf * CFrame.new(-w / 2 + 0.6, h - 2.2, 0) * CFrame.Angles(0, 0, 0.75), Vector3.new(2, 1, 2), C.StoneLight, M.Slate, { Name = "ArchStone" })
	Kit.part(parent, cf * CFrame.new(w / 2 - 0.6, h - 2.2, 0) * CFrame.Angles(0, 0, -0.75), Vector3.new(2, 1, 2), C.StoneLight, M.Slate, { Name = "ArchStone" })
	Kit.part(parent, cf * CFrame.new(0, h + 0.6, 0), Vector3.new(4, 1.2, 2.4), C.Stone, M.Slate, { Name = "Keystone" })
end

function Kit.stairs(parent, cf, width, steps, rise)
	local depth = 1.6
	for i = 1, steps do
		Kit.part(parent, cf * CFrame.new(0, (i - 0.5) * rise, (i - 0.5) * depth), Vector3.new(width, rise, depth), jitter(C.StoneLight, i * 11), M.Slate, { Name = "Step", Collide = true })
	end
end

function Kit.brazier(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 0.3, 0), Vector3.new(2, 0.6, 2), C.Iron, M.Metal, { Name = "BrazierFoot" })
	Kit.part(parent, cf * CFrame.new(0, 1.6, 0), Vector3.new(0.5, 2, 0.5), C.Iron, M.Metal, { Name = "BrazierStem" })
	Kit.part(parent, cf * CFrame.new(0, 3.0, 0) * CFrame.Angles(0, 0, PI / 2), Vector3.new(1.1, 3.2, 3.2), C.Iron, M.Metal, { Name = "BrazierBowl", Shape = Enum.PartType.Cylinder })
	local flame = Kit.part(parent, cf * CFrame.new(0, 4.3, 0), Vector3.new(1.8, 1.8, 1.8), C.Flame, M.Neon, { Name = "BrazierFlame" })
	local light = Instance.new("PointLight")
	light.Name = "BrazierLight"
	light.Color = C.Light
	light.Brightness = 1.4
	light.Range = 18
	light.Shadows = false
	light.Parent = flame
end

function Kit.rock(parent, cf, size, seed)
	local r = rng(seed)
	Kit.part(parent, cf * CFrame.Angles((r() - 0.5) * 0.4, (r() - 0.5) * 0.6, (r() - 0.5) * 0.4), size, jitter((r() > 0.5) and C.Rock or C.RockDark, seed), M.Slate, { Name = "Rock", Collide = true })
end

function Kit.stalagmite(parent, cf, h)
	h = h or 4
	Kit.part(parent, cf * CFrame.new(0, h * 0.2, 0) * CFrame.Angles(0, 0.4, 0), Vector3.new(2.6, h * 0.4, 2.6), C.RockDark, M.Slate, { Name = "Stalagmite", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, h * 0.55, 0) * CFrame.Angles(0, 0.8, 0), Vector3.new(1.6, h * 0.35, 1.6), C.Rock, M.Slate, { Name = "Stalagmite" })
	Kit.part(parent, cf * CFrame.new(0, h * 0.85, 0), Vector3.new(0.7, h * 0.3, 0.7), C.Rock, M.Slate, { Name = "Stalagmite" })
end

-- a cobweb in a ceiling corner: cf = the corner at the ceiling, LookVector along one wall
function Kit.cobweb(parent, cf)
	Kit.part(parent, cf * CFrame.new(1.4, -0.3, -1.4) * CFrame.Angles(0, PI / 4, 0), Vector3.new(4, 0.1, 0.1), C.Marble, M.Glass, { Name = "Web", Transparency = 0.45 })
	Kit.part(parent, cf * CFrame.new(1.0, -1.1, -1.0) * CFrame.Angles(0, PI / 4, 0), Vector3.new(2.8, 0.1, 0.1), C.Marble, M.Glass, { Name = "Web", Transparency = 0.5 })
	Kit.part(parent, cf * CFrame.new(0.5, -2.0, -0.5) * CFrame.Angles(0, PI / 4, 0), Vector3.new(1.4, 0.1, 0.1), C.Marble, M.Glass, { Name = "Web", Transparency = 0.55 })
end

function Kit.skulls(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 0.45, 0), Vector3.new(0.9, 0.9, 0.9), C.Bone, M.Marble, { Name = "Skull" })
	Kit.part(parent, cf * CFrame.new(1.0, 0.4, 0.5) * CFrame.Angles(0, 0.6, 0.2), Vector3.new(0.8, 0.8, 0.8), C.Bone, M.Marble, { Name = "Skull" })
	Kit.part(parent, cf * CFrame.new(-0.9, 0.2, 0.6) * CFrame.Angles(0, 1.1, 0), Vector3.new(1.8, 0.3, 0.3), C.Bone, M.Marble, { Name = "Bone" })
end

function Kit.rubble(parent, cf, seed)
	local r = rng(seed or 1)
	for i = 1, 3 do
		Kit.part(parent, cf * CFrame.new((r() - 0.5) * 3, 0.3, (r() - 0.5) * 3) * CFrame.Angles(0, r() * PI, 0), Vector3.new(0.8 + r(), 0.6, 0.7 + r() * 0.6), jitter(C.StoneLight, (seed or 1) + i), M.Slate, { Name = "Rubble" })
	end
end

-- a weapon rack against a wall (cf on the wall face, LookVector into the room)
function Kit.rack(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 1.6, -0.5), Vector3.new(4, 3.2, 0.3), C.Wood, M.Wood, { Name = "RackBack" })
	Kit.part(parent, cf * CFrame.new(0, 0.3, -0.7), Vector3.new(4.2, 0.6, 0.8), C.Wood, M.Wood, { Name = "RackFoot" })
	for i = -1, 1 do
		Kit.part(parent, cf * CFrame.new(i * 1.2, 2.0, -0.75), Vector3.new(0.25, 3.4, 0.25), C.Iron, M.Metal, { Name = "Spear" })
		Kit.part(parent, cf * CFrame.new(i * 1.2, 3.8, -0.75), Vector3.new(0.5, 0.9, 0.15), C.Marble, M.Metal, { Name = "SpearHead" })
	end
end

function Kit.cauldron(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, PI / 2), Vector3.new(0.6, 2.4, 2.4), C.Iron, M.Metal, { Name = "CauldronFoot", Shape = Enum.PartType.Cylinder })
	Kit.part(parent, cf * CFrame.new(0, 1.8, 0), Vector3.new(3.2, 3.2, 3.2), C.Iron, M.Metal, { Name = "Cauldron", Shape = Enum.PartType.Ball, Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0, PI / 2), Vector3.new(0.3, 2.6, 2.6), C.Moss, M.Neon, { Name = "Brew", Shape = Enum.PartType.Cylinder, Accent = true })
end

-- a wall emblem: a shield with crossed bars (cf on the wall face, LookVector into the room)
function Kit.shield(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 0, -0.3), Vector3.new(2.6, 3.2, 0.3), C.Iron, M.Metal, { Name = "Shield" })
	Kit.part(parent, cf * CFrame.new(0, 0, -0.5), Vector3.new(1.6, 2, 0.15), WorldStyle.Palette.Accent.Purple, M.Fabric, { Name = "ShieldCrest", Accent = true })
	Kit.part(parent, cf * CFrame.new(0, 0, -0.65) * CFrame.Angles(0, 0, 0.75), Vector3.new(4, 0.25, 0.2), C.Gold, M.Metal, { Name = "Sword" })
	Kit.part(parent, cf * CFrame.new(0, 0, -0.65) * CFrame.Angles(0, 0, -0.75), Vector3.new(4, 0.25, 0.2), C.Gold, M.Metal, { Name = "Sword" })
end

-- a stone guardian statue on a plinth
function Kit.statue(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 0.6, 0), Vector3.new(3, 1.2, 3), C.StoneDark, M.Slate, { Name = "StatueBase", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 3.2, 0), Vector3.new(1.8, 4, 1.4), C.StoneLight, M.Marble, { Name = "StatueBody", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 5.8, 0), Vector3.new(1.2, 1.2, 1.2), C.StoneLight, M.Marble, { Name = "StatueHead" })
	Kit.part(parent, cf * CFrame.new(-1.3, 3.6, 0), Vector3.new(0.6, 2.6, 0.6), C.StoneLight, M.Marble, { Name = "StatueArm" })
	Kit.part(parent, cf * CFrame.new(1.3, 4.0, -0.4) * CFrame.Angles(0.5, 0, 0), Vector3.new(0.6, 2.6, 0.6), C.StoneLight, M.Marble, { Name = "StatueArm" })
	Kit.part(parent, cf * CFrame.new(1.3, 5.4, -1.2), Vector3.new(0.3, 3.4, 0.3), C.Iron, M.Metal, { Name = "StatueSpear" })
end

function Kit.candles(parent, cf)
	for i = -1, 1 do
		Kit.part(parent, cf * CFrame.new(i * 0.7, 0.35, 0), Vector3.new(0.3, 0.7, 0.3), C.Marble, M.Marble, { Name = "Candle" })
		Kit.part(parent, cf * CFrame.new(i * 0.7, 0.85, 0), Vector3.new(0.25, 0.3, 0.25), C.Flame, M.Neon, { Name = "CandleFlame" })
	end
end

-- a chandelier hanging from the ceiling (cf = the ceiling point)
function Kit.chandelier(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, -2.5, 0), Vector3.new(0.3, 5, 0.3), C.Iron, M.Metal, { Name = "ChandelierChain" })
	Kit.part(parent, cf * CFrame.new(0, -5.2, 0) * CFrame.Angles(0, 0, PI / 2), Vector3.new(0.4, 5, 5), C.Iron, M.Metal, { Name = "ChandelierRing", Shape = Enum.PartType.Cylinder })
	Kit.part(parent, cf * CFrame.new(0, -5.2, 0) * CFrame.Angles(0, 0, PI / 2), Vector3.new(0.5, 3.6, 3.6), C.StoneDark, M.Metal, { Name = "ChandelierHub", Shape = Enum.PartType.Cylinder })
	for i = 0, 3 do
		local a = i * PI / 2 + PI / 4
		local x, z = math.cos(a) * 2.1, math.sin(a) * 2.1
		Kit.part(parent, cf * CFrame.new(x, -4.6, z), Vector3.new(0.35, 0.8, 0.35), C.Marble, M.Marble, { Name = "Candle" })
		Kit.part(parent, cf * CFrame.new(x, -4.0, z), Vector3.new(0.3, 0.4, 0.3), C.Flame, M.Neon, { Name = "CandleFlame" })
	end
	local light = Instance.new("PointLight")
	light.Name = "ChandelierLight"
	light.Color = C.Light
	light.Brightness = 1.0
	light.Range = 18
	light.Shadows = false
	light.Parent = parent:FindFirstChild("ChandelierHub")
end

-- a hearth in a wall (cf on the wall face at floor level, LookVector into the room)
function Kit.hearth(parent, cf)
	Kit.part(parent, cf * CFrame.new(-3.2, 2.6, -0.9), Vector3.new(1.4, 5.2, 1.8), C.StoneDark, M.Slate, { Name = "HearthSide", Collide = true })
	Kit.part(parent, cf * CFrame.new(3.2, 2.6, -0.9), Vector3.new(1.4, 5.2, 1.8), C.StoneDark, M.Slate, { Name = "HearthSide", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 5.6, -0.9), Vector3.new(7.8, 0.8, 2), C.StoneDark, M.Slate, { Name = "Mantle" })
	Kit.part(parent, cf * CFrame.new(0, 2.6, -0.35), Vector3.new(5, 5.2, 0.5), C.Ceiling, M.Slate, { Name = "HearthBack" })
	Kit.part(parent, cf * CFrame.new(0, 0.2, -1.2), Vector3.new(7.8, 0.4, 2.4), C.StoneDark, M.Slate, { Name = "HearthStone" })
	Kit.part(parent, cf * CFrame.new(0, 0.7, -0.9), Vector3.new(2.6, 0.6, 1.2), C.Wood, M.Wood, { Name = "Log" })
	local flame = Kit.part(parent, cf * CFrame.new(0, 1.6, -0.9), Vector3.new(2.2, 1.6, 1), C.Ember, M.Neon, { Name = "HearthFlame" })
	local light = Instance.new("PointLight")
	light.Name = "HearthLight"
	light.Color = C.Light
	light.Brightness = 1.4
	light.Range = 18
	light.Shadows = false
	light.Parent = flame
end

function Kit.rug(parent, cf, w, d)
	Kit.part(parent, cf * CFrame.new(0, 0.07, 0), Vector3.new(w or 8, 0.14, d or 6), C.Carpet, M.Fabric, { Name = "Rug" })
	Kit.part(parent, cf * CFrame.new(0, 0.15, 0), Vector3.new((w or 8) - 1.6, 0.06, (d or 6) - 1.6), WorldStyle.Palette.Accent.Purple, M.Fabric, { Name = "RugInlay", Accent = true })
end

-- a wine rack against a wall (cf on the wall face, LookVector into the room)
function Kit.wineRack(parent, cf)
	Kit.part(parent, cf * CFrame.new(0, 2, -1), Vector3.new(5, 4, 1.8), C.Wood, M.Wood, { Name = "WineRack", Collide = true })
	for i = -1, 1 do
		for j = 0, 1 do
			Kit.part(parent, cf * CFrame.new(i * 1.5, 1.1 + j * 1.8, -2.05) * CFrame.Angles(PI / 2, 0, 0), Vector3.new(0.6, 0.6, 0.6), C.Moss, M.Glass, { Name = "Bottle", Shape = Enum.PartType.Cylinder })
		end
	end
end

function Kit.chest(parent, cf, slot)
	local body = Kit.part(parent, cf * CFrame.new(0, 0.9, 0), Vector3.new(3, 1.8, 2), C.Plank, M.WoodPlanks, { Name = "Chest", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 2.05, 0), Vector3.new(3.1, 0.5, 2.1), C.Wood, M.Wood, { Name = "ChestLid" })
	Kit.part(parent, cf * CFrame.new(0, 1.0, 1.05), Vector3.new(0.6, 0.6, 0.15), C.Gold, M.Metal, { Name = "ChestLock" })
	body:SetAttribute("ChestSlot", slot)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChestPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Chest"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("DungeonAction", "Chest")
	prompt:SetAttribute("ChestSlot", slot)
	prompt.Parent = body
	return body
end

----------------------------------------------------------------------
-- Template sets. Every template is a Model whose PrimaryPart "Base" sits at the local origin (floor top y 0); the
-- piece heads +Z: Entrance at the -Z edge, Exit at the +Z edge (attachments on Base, like Threshold / Spawn1..4 / Dais).
----------------------------------------------------------------------
local Rooms = {}

local function attach(base, name, pos)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = CFrame.new(pos)
	a.Parent = base
	return a
end

local function newTemplate(name, w, d, entrance, exit)
	local model = Instance.new("Model")
	model.Name = name
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.Transparency = 1
	base.Size = Vector3.new(1, 1, 1)
	base.Material = Enum.Material.SmoothPlastic
	base.CFrame = CFrame.new(0, -1.5, 0)
	base.Parent = model
	model.PrimaryPart = base
	model:SetAttribute("Width", w)
	model:SetAttribute("Depth", d)
	-- attachments carry the piece's local points (relative to the Base part, which stands at the origin)
	attach(base, "Entrance", Vector3.new(entrance.X, 1.5, entrance.Z))
	attach(base, "Exit", Vector3.new(exit.X, 1.5, exit.Z))
	local detail = Instance.new("Model")
	detail.Name = "Detail"
	detail.Parent = model
	CollectionService:AddTag(detail, DETAIL_TAG)
	return model, base, detail
end

-- the four walls (with doorways at the entrance / exit) + corner pillars + torches of a rectangular room
local function roomShell(model, w, d, color, mat, seed, exitX, torches, doorW)
	local hw, hd = w / 2, d / 2
	doorW = doorW or 8
	Kit.wall(model, CFrame.new(0, 0, -hd - 0.5, -1, 0, 0, 0, 1, 0, 0, 0, -1), w + 2, color, mat, seed + 1, { X = 0, Width = doorW })
	Kit.wall(model, CFrame.new(0, 0, hd + 0.5, 1, 0, 0, 0, 1, 0, 0, 0, 1), w + 2, color, mat, seed + 2, { X = exitX or 0, Width = doorW })
	Kit.wall(model, CFrame.new(-hw - 0.5, 0, 0) * CFrame.Angles(0, -PI / 2, 0), d, color, mat, seed + 3)
	Kit.wall(model, CFrame.new(hw + 0.5, 0, 0) * CFrame.Angles(0, PI / 2, 0), d, color, mat, seed + 4)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Kit.pillar(model, CFrame.new(sx * (hw - 1.4), 0, sz * (hd - 1.4)), WALL_H + 0.5, color)
		end
	end
	-- torches along the side walls every ~12 studs (rule 6) + one each side of the doors
	Kit.cobweb(model, CFrame.new(-hw + 0.5, WALL_H - 0.3, -hd + 0.5))
	Kit.cobweb(model, CFrame.new(hw - 0.5, WALL_H - 0.3, hd - 0.5) * CFrame.Angles(0, PI, 0))
	local n = torches or max(2, floor(d / 12))
	for i = 1, n do
		local z = -hd + (i - 0.5) * (d / n)
		Kit.torch(model, CFrame.new(-hw + 0.5, 6.5, z) * CFrame.Angles(0, -PI / 2, 0))
		Kit.torch(model, CFrame.new(hw - 0.5, 6.5, z) * CFrame.Angles(0, PI / 2, 0))
	end
	Kit.torch(model, CFrame.new(-doorW / 2 - 3, 7, -hd + 0.5) * CFrame.Angles(0, PI, 0))
	Kit.torch(model, CFrame.new(doorW / 2 + 3, 7, -hd + 0.5) * CFrame.Angles(0, PI, 0))
end

local function roomPoints(base, w, d, exitX)
	local hd = d / 2
	attach(base, "Threshold", Vector3.new(0, 1.5, -hd + 10))
	for i = 1, 4 do
		attach(base, "Spawn" .. i, Vector3.new(-6 + (i - 1) * 4, 1.5, -hd + 4))
	end
	attach(base, "Dais", Vector3.new(exitX or 0, 1.5, hd - 6))
end

-- Hall_1..3: pillared halls with tables, banners, benches and runes (floors Stone Halls, Ember Forge, Star Chapel,
-- Eclipse Sanctum)
function Rooms.Hall(variant)
	local w, d = 48, 48
	local seed = 100 + variant * 17
	local r = rng(seed)
	local model, base, detail = newTemplate("Hall_" .. variant, w, d, Vector3.new(0, 0, -24), Vector3.new(0, 0, 24))
	Kit.floorTiles(model, w, d, C.Flag, M.Cobblestone, seed)
	roomShell(model, w, d, C.Stone, M.Slate, seed, 0, 3)
	Kit.ceiling(model, w, d)
	-- two rows of pillars down the hall
	for _, x in ipairs({ -14, 14 }) do
		for _, z in ipairs({ -10, 4 }) do
			Kit.pillar(model, CFrame.new(x, 0, z), WALL_H, C.StoneLight)
		end
	end
	Kit.rune(detail, CFrame.new(0, 0, 0), 10, 0.6)
	Kit.rune(detail, CFrame.new(0, 0, 0), 0.6, 10)
	for _, x in ipairs({ -20, 20 }) do
		Kit.banner(detail, CFrame.new(x, 11, -23.4) * CFrame.Angles(0, PI, 0))
		Kit.banner(detail, CFrame.new(x, 11, 23.4))
	end
	Kit.shield(detail, CFrame.new(0, 9, 23.4))
	Kit.rack(detail, CFrame.new(23.4, 0, -6) * CFrame.Angles(0, PI / 2, 0))
	Kit.chandelier(model, CFrame.new(0, CEIL_Y, 0))
	Kit.hearth(model, CFrame.new(23.4, 0, 10) * CFrame.Angles(0, PI / 2, 0))
	Kit.rug(detail, CFrame.new(0, 0, -14), 10, 7)
	Kit.skulls(detail, CFrame.new(-21, 0, -8))
	Kit.rubble(detail, CFrame.new(12, 0, 20), seed + 7)
	Kit.candles(detail, CFrame.new(-18, 2.5, 14))
	if variant == 1 then
		Kit.table(detail, CFrame.new(-18, 0, 14))
		Kit.bench(detail, CFrame.new(-18, 0, 11.4))
		Kit.crate(detail, CFrame.new(20, 0, -18))
		Kit.crate(detail, CFrame.new(20, 2.4, -18), 1.8)
		Kit.barrel(detail, CFrame.new(17.5, 0, -17.5))
		Kit.hay(detail, CFrame.new(20, 0, 16))
		Kit.puddle(detail, CFrame.new(6, 0, -14), 5, 3.5)
		Kit.rack(detail, CFrame.new(-23.4, 0, 6) * CFrame.Angles(0, -PI / 2, 0))
	elseif variant == 2 then
		Kit.table(detail, CFrame.new(18, 0, -12))
		Kit.table(detail, CFrame.new(18, 0, 16))
		Kit.bench(detail, CFrame.new(18, 0, 13.4))
		Kit.crate(detail, CFrame.new(-20, 0, 18), 2.8)
		Kit.crate(detail, CFrame.new(-20, 0, 15), 1.8)
		Kit.moss(detail, CFrame.new(-10, 0, 20), 4, 2.6)
		Kit.bones(detail, CFrame.new(10, 0, -19))
	else
		Kit.barrel(detail, CFrame.new(-20, 0, -18))
		Kit.barrel(detail, CFrame.new(-20, 0, -15.4))
		Kit.crate(detail, CFrame.new(20, 0, 18))
		Kit.puddle(detail, CFrame.new(-8, 0, 12), 4, 4)
		Kit.chain(detail, CFrame.new(-23.3, 11, 0))
		Kit.chain(detail, CFrame.new(23.3, 11, 6))
		Kit.table(detail, CFrame.new(0, 0, 19))
	end
	-- a loose stone or two
	for _ = 1, 2 do
		Kit.part(detail, CFrame.new(-16 + r() * 32, 0.3, -16 + r() * 32), Vector3.new(1.2, 0.6, 1), C.StoneLight, M.Slate, { Name = "Rubble" })
	end
	roomPoints(base, w, d, 0)
	return model
end

-- Cellar_1..3: brick cellars with barrels, crates, hay, chains and a cell (Mossy Cellar, Frozen Crypt)
function Rooms.Cellar(variant)
	local w, d = 48, 48
	local seed = 200 + variant * 23
	local r = rng(seed)
	local model, base, detail = newTemplate("Cellar_" .. variant, w, d, Vector3.new(0, 0, -24), Vector3.new(0, 0, 24))
	Kit.floorTiles(model, w, d, C.FlagDark, M.Cobblestone, seed)
	roomShell(model, w, d, C.Brick, M.Brick, seed, 0, 3)
	Kit.ceiling(model, w, d)
	-- beams across the ceiling, a wine rack
	Kit.part(model, CFrame.new(0, CEIL_Y - 0.6, -8), Vector3.new(w, 1.2, 1.6), C.Wood, M.Wood, { Name = "Beam" })
	Kit.part(model, CFrame.new(0, CEIL_Y - 0.6, 8), Vector3.new(w, 1.2, 1.6), C.Wood, M.Wood, { Name = "Beam" })
	Kit.wineRack(detail, CFrame.new(23.4, 0, 12) * CFrame.Angles(0, PI / 2, 0))
	-- a cell in one corner: bars on two sides
	local cx, cz = 16, -14
	for i = 0, 5 do
		Kit.part(detail, CFrame.new(cx - 6 + i * 1.2, 4, cz + 6), Vector3.new(0.3, 8, 0.3), C.Iron, M.Metal, { Name = "CellBar" })
		Kit.part(detail, CFrame.new(cx - 6, 4, cz + i * 1.2), Vector3.new(0.3, 8, 0.3), C.Iron, M.Metal, { Name = "CellBar" })
	end
	Kit.part(detail, CFrame.new(cx - 3, 8.1, cz + 3), Vector3.new(6.6, 0.3, 6.6), C.Iron, M.Metal, { Name = "CellRail" })
	Kit.hay(detail, CFrame.new(cx + 0.5, 0, cz - 2))
	Kit.bones(detail, CFrame.new(cx - 2, 0, cz + 1))
	Kit.chain(detail, CFrame.new(cx + 3, 10, cz - 7.6))
	for i = 1, 3 do
		Kit.barrel(detail, CFrame.new(-20 + (i - 1) * 2.6, 0, 19))
	end
	Kit.crate(detail, CFrame.new(-19, 0, -19), 2.6)
	Kit.crate(detail, CFrame.new(-16, 0, -19.5), 1.8)
	Kit.crate(detail, CFrame.new(-19, 2.6, -19), 1.8)
	Kit.moss(detail, CFrame.new(-10, 0, 20), 4, 2.4)
	Kit.moss(detail, CFrame.new(21, 0, 8), 2.4, 5)
	Kit.puddle(detail, CFrame.new(-6 + r() * 12, 0, -6 + r() * 8), 5, 4)
	Kit.cauldron(detail, CFrame.new(-19, 0, 8))
	Kit.skulls(detail, CFrame.new(-16, 0, 11))
	Kit.rubble(detail, CFrame.new(8, 0, -20), seed + 3)
	Kit.rack(detail, CFrame.new(-23.4, 0, -6) * CFrame.Angles(0, -PI / 2, 0))
	Kit.candles(detail, CFrame.new(-19, 0, 0))
	if variant == 2 then
		Kit.table(detail, CFrame.new(0, 0, 20))
		Kit.bench(detail, CFrame.new(0, 0, 17.4))
		Kit.chain(detail, CFrame.new(-23.3, 11, 8))
	elseif variant == 3 then
		Kit.hay(detail, CFrame.new(18, 0, 18))
		Kit.hay(detail, CFrame.new(20, 0, 15))
		Kit.barrel(detail, CFrame.new(-20, 0, 0))
		Kit.puddle(detail, CFrame.new(8, 0, 14), 3.6, 3)
	else
		Kit.bones(detail, CFrame.new(-4, 0, 18))
		Kit.crate(detail, CFrame.new(19, 0, 19))
	end
	roomPoints(base, w, d, 0)
	return model
end

-- Cave_1..3: rough rock walls, stalagmites, a turquoise pool and a waterfall wall (Flooded Vaults, Shadow Keep, Magma Mines)
function Rooms.Cave(variant)
	local w, d = 48, 48
	local seed = 300 + variant * 29
	local r = rng(seed)
	local model, base, detail = newTemplate("Cave_" .. variant, w, d, Vector3.new(0, 0, -24), Vector3.new(0, 0, 24))
	Kit.floorTiles(model, w, d, C.FlagDark, M.Slate, seed)
	roomShell(model, w, d, C.Rock, M.Slate, seed, 0, 2)
	Kit.ceiling(model, w, d)
	-- rock bulges along every wall (the cave read), boulders on the floor
	for i = 1, 7 do
		local z = -21 + (i - 1) * 7
		Kit.rock(model, CFrame.new(-23.5 + 0.8 * r(), 3 + r() * 6, z), Vector3.new(3 + r() * 2.5, 6 + r() * 5, 6 + r() * 2), seed + i)
		Kit.rock(model, CFrame.new(23.5 - 0.8 * r(), 3 + r() * 6, z + 3), Vector3.new(3 + r() * 2.5, 6 + r() * 5, 6 + r() * 2), seed + i + 20)
	end
	for i = 1, 4 do
		local x = -18 + (i - 1) * 12
		if abs(x) > 6 then
			Kit.rock(model, CFrame.new(x, 3 + r() * 5, -23.5 + 0.8 * r()), Vector3.new(6 + r() * 2, 6 + r() * 4, 3 + r() * 2), seed + i + 40)
		end
		Kit.rock(model, CFrame.new(x + 3, 3 + r() * 5, 23.5 - 0.8 * r()), Vector3.new(6 + r() * 2, 6 + r() * 4, 3 + r() * 2), seed + i + 60)
	end
	for i = 1, 7 do
		Kit.stalagmite(detail, CFrame.new(-18 + r() * 36, 0, -8 + r() * 26), 2.5 + r() * 2.5)
	end
	Kit.rock(detail, CFrame.new(-14, 1.2, -6), Vector3.new(3.5, 2.4, 3), seed + 81)
	Kit.rock(detail, CFrame.new(8, 0.9, -16), Vector3.new(2.6, 1.8, 2.2), seed + 82)
	Kit.rubble(detail, CFrame.new(-6, 0, 4), seed + 83)
	Kit.skulls(detail, CFrame.new(18, 0, -18))
	-- the pool in the far corner, a rim of stones and the waterfall wall over it
	local px, pz = 15, 15
	Kit.part(model, CFrame.new(px, 0.1, pz), Vector3.new(14, 0.2, 12), C.Water, M.Glass, { Name = "Pool", Transparency = 0.3 })
	for i = 1, 6 do
		local ang = (i / 6) * PI * 2
		Kit.part(model, CFrame.new(px + math.cos(ang) * 8.4, 0.6, pz + math.sin(ang) * 7.4) * CFrame.Angles(0, -ang, 0), Vector3.new(3.2, 1.2, 2), jitter(C.RockDark, seed + i), M.Slate, { Name = "PoolRim" })
	end
	Kit.part(model, CFrame.new(px + 4, 7, 23.2), Vector3.new(6, 13, 0.6), C.Water, M.Glass, { Name = "Waterfall", Transparency = 0.45 })
	for i = 1, 3 do
		Kit.part(model, CFrame.new(px + 2 + i * 1.2, 7 + (i % 2), 22.8), Vector3.new(0.3, 10, 0.3), C.WaterGlow, M.Neon, { Name = "WaterStreak", Accent = true })
	end
	Kit.puddle(detail, CFrame.new(px - 10, 0, pz + 2), 4, 3)
	Kit.moss(detail, CFrame.new(-16, 0, -16), 5, 3)
	Kit.moss(detail, CFrame.new(-20, 0, 10), 3, 5)
	Kit.bones(detail, CFrame.new(-10, 0, 16))
	if variant == 2 then
		Kit.crate(detail, CFrame.new(-20, 0, 18))
		Kit.stalagmite(detail, CFrame.new(-6, 0, -12), 4)
	elseif variant == 3 then
		Kit.rock(detail, CFrame.new(-12, 1.5, 4), Vector3.new(4, 3, 3), seed + 90)
		Kit.hay(detail, CFrame.new(20, 0, -16))
	end
	roomPoints(base, w, d, 0)
	return model
end

-- Bridge_1..2: a stone causeway over a dark chasm (an invisible floor below), rope rails and lamp posts (Thunder Spire,
-- Howling Peak)
function Rooms.Bridge(variant)
	local w, d = 48, 48
	local seed = 400 + variant * 31
	local model, base, detail = newTemplate("Bridge_" .. variant, w, d, Vector3.new(0, 0, -24), Vector3.new(0, 0, 24))
	-- the causeway floor (44 wide: the zone), the abyss plane and the invisible safety floor
	Kit.floorTiles(model, 44, d, C.Flag, M.Cobblestone, seed)
	Kit.part(model, CFrame.new(0, -7, 0), Vector3.new(w + 2, 0.4, d + 2), C.Abyss, M.Slate, { Name = "Abyss", Transparency = 0.35 })
	Kit.part(model, CFrame.new(0, -6.5, 0), Vector3.new(w + 2, 0.5, d + 2), C.Abyss, M.Slate, { Name = "SafetyFloor", Transparency = 1, Collide = true })
	-- the edge kerbs (rule 3) + posts with rope rails
	for _, sx in ipairs({ -1, 1 }) do
		Kit.part(model, CFrame.new(sx * 22.2, 0.2, 0), Vector3.new(0.6, 0.4, d), C.StoneDark, M.Slate, { Name = "Kerb", Collide = true })
		Kit.part(model, CFrame.new(sx * 22.2, -1.2, 0), Vector3.new(1, 2.4, d), C.StoneDark, M.Slate, { Name = "Edge" })
		for i = 0, 4 do
			local z = -22 + i * 11
			Kit.part(model, CFrame.new(sx * 22.2, 1.6, z), Vector3.new(0.6, 3.2, 0.6), C.Wood, M.Wood, { Name = "Post", Collide = true })
		end
		Kit.part(model, CFrame.new(sx * 22.2, 2.9, 0), Vector3.new(0.25, 0.25, d - 2), C.Iron, M.Metal, { Name = "Rail" })
		Kit.part(model, CFrame.new(sx * 22.2, 1.9, 0), Vector3.new(0.25, 0.25, d - 2), C.Iron, M.Metal, { Name = "Rail" })
	end
	-- the end walls with doors + lamp posts (the sides are open to the chasm; the ceiling still closes the room)
	Kit.wall(model, CFrame.new(0, 0, -24.5, -1, 0, 0, 0, 1, 0, 0, 0, -1), w + 2, C.Stone, M.Slate, seed + 1, { X = 0, Width = 8 })
	Kit.wall(model, CFrame.new(0, 0, 24.5, 1, 0, 0, 0, 1, 0, 0, 0, 1), w + 2, C.Stone, M.Slate, seed + 2, { X = 0, Width = 8 })
	Kit.ceiling(model, w, d)
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -12, 12 }) do
			Kit.part(model, CFrame.new(sx * 20.5, 2.5, z), Vector3.new(0.6, 5, 0.6), C.Iron, M.Metal, { Name = "LampPost" })
			local lamp = Kit.part(model, CFrame.new(sx * 20.5, 5.4, z), Vector3.new(1, 1, 1), C.Flame, M.Neon, { Name = "Lamp" })
			local light = Instance.new("PointLight")
			light.Name = "LampLight"
			light.Color = C.Light
			light.Brightness = 1.2
			light.Range = 18
			light.Shadows = false
			light.Parent = lamp
		end
	end
	Kit.torch(model, CFrame.new(-7, 7, -23.5) * CFrame.Angles(0, PI, 0))
	Kit.torch(model, CFrame.new(7, 7, -23.5) * CFrame.Angles(0, PI, 0))
	Kit.skulls(detail, CFrame.new(-16, 0, -10))
	Kit.rubble(detail, CFrame.new(10, 0, 16), seed + 5)
	-- a few plank patches and a broken crate
	for i = 1, 3 do
		Kit.part(detail, CFrame.new(-12 + i * 6, 0.1, -4 + i * 3), Vector3.new(4.5, 0.2, 2.6), C.Plank, M.WoodPlanks, { Name = "Plank" })
	end
	Kit.crate(detail, CFrame.new(-18, 0, 18), 2.2)
	if variant == 2 then
		Kit.chain(detail, CFrame.new(-20.8, 12, -20))
		Kit.chain(detail, CFrame.new(20.8, 12, 20))
		Kit.rune(detail, CFrame.new(0, 0, 0), 8, 0.6)
	else
		Kit.bones(detail, CFrame.new(14, 0, -14))
		Kit.puddle(detail, CFrame.new(-8, 0, 10), 4, 3)
	end
	roomPoints(base, w, d, 0)
	return model
end

-- Throne_1: the boss room (every floor's room 4): three arches, a long carpet, two braziers, stairs to a dais and the
-- throne; the exit (to the treasure alcove) is a door beside the dais
function Rooms.Throne(variant)
	local w, d = 60, 72
	local seed = 500 + variant * 37
	local exitX = 20
	local model, base, detail = newTemplate("Throne_" .. variant, w, d, Vector3.new(0, 0, -36), Vector3.new(exitX, 0, 36))
	Kit.floorTiles(model, w, d, C.Flag, M.Cobblestone, seed)
	roomShell(model, w, d, C.Stone, M.Slate, seed, exitX, 4, 8)
	Kit.ceiling(model, w, d)
	-- three arches across the room
	for _, z in ipairs({ -20, 4 }) do
		Kit.pillar(model, CFrame.new(-19, 0, z), WALL_H, C.StoneLight)
		Kit.pillar(model, CFrame.new(19, 0, z), WALL_H, C.StoneLight)
	end
	-- the carpet (plum Fabric, big face under 0.45 saturation) and the Neon edge runes
	Kit.part(model, CFrame.new(0, 0.1, -4), Vector3.new(8, 0.2, 56), C.Carpet, M.Fabric, { Name = "Carpet" })
	Kit.rune(detail, CFrame.new(-4.3, 0, -4), 0.5, 56)
	Kit.rune(detail, CFrame.new(4.3, 0, -4), 0.5, 56)
	-- the dais with stairs, the throne and two braziers
	local daisZ = 28
	Kit.part(model, CFrame.new(0, 1.2, daisZ), Vector3.new(24, 2.4, 14), C.StoneLight, M.Slate, { Name = "Dais", Collide = true })
	Kit.part(model, CFrame.new(0, 2.5, daisZ), Vector3.new(6, 0.2, 10), C.Carpet, M.Fabric, { Name = "DaisCarpet" })
	Kit.part(model, CFrame.new(0, 2.6, daisZ - 7.2), Vector3.new(24, 0.4, 0.6), C.StoneDark, M.Slate, { Name = "DaisKerb" })
	Kit.stairs(model, CFrame.new(0, 0, daisZ - 7 - 4.8), 10, 3, 0.8)
	local tz = daisZ + 3
	Kit.part(model, CFrame.new(0, 3.4, tz), Vector3.new(3.4, 2, 2.4), C.StoneDark, M.Slate, { Name = "ThroneSeat", Collide = true })
	Kit.part(model, CFrame.new(0, 6.2, tz + 1), Vector3.new(3.4, 7.6, 0.6), C.StoneDark, M.Slate, { Name = "ThroneBack" })
	Kit.part(model, CFrame.new(-1.7, 4.6, tz), Vector3.new(0.4, 2.4, 2.4), C.StoneDark, M.Slate, { Name = "ThroneArm" })
	Kit.part(model, CFrame.new(1.7, 4.6, tz), Vector3.new(0.4, 2.4, 2.4), C.StoneDark, M.Slate, { Name = "ThroneArm" })
	Kit.part(model, CFrame.new(0, 10.4, tz + 1), Vector3.new(1.6, 1, 0.5), C.Gold, M.Metal, { Name = "ThroneCrown" })
	Kit.part(model, CFrame.new(0, 4.6, tz - 0.2), Vector3.new(2.6, 0.5, 2), C.Carpet, M.Fabric, { Name = "ThroneCushion" })
	Kit.brazier(model, CFrame.new(-8, 2.4, daisZ - 2))
	Kit.brazier(model, CFrame.new(8, 2.4, daisZ - 2))
	-- two arches spanning the aisle, guardian statues by the stairs, skull piles, candles
	Kit.arch(model, CFrame.new(0, 0, -20), 10, 12.5)
	Kit.arch(model, CFrame.new(0, 0, -2), 10, 12.5)
	Kit.statue(model, CFrame.new(-9, 0, 14))
	Kit.statue(model, CFrame.new(9, 0, 14))
	Kit.skulls(detail, CFrame.new(-26, 0, -12))
	Kit.candles(detail, CFrame.new(-6, 2.4, daisZ + 5))
	Kit.candles(detail, CFrame.new(6, 2.4, daisZ + 5))
	Kit.shield(detail, CFrame.new(0, 10, 35.4))
	Kit.rubble(detail, CFrame.new(-20, 0, 4), seed + 9)
	-- banners between the arches, chains, a bookshelf nook, puddles
	for _, x in ipairs({ -29.4, 29.4 }) do
		Kit.banner(detail, CFrame.new(x, 12, -10) * CFrame.Angles(0, x < 0 and -PI / 2 or PI / 2, 0))
		Kit.banner(detail, CFrame.new(x, 12, 6) * CFrame.Angles(0, x < 0 and -PI / 2 or PI / 2, 0))
	end
	Kit.chain(detail, CFrame.new(-29.3, 12, -26))
	Kit.chain(detail, CFrame.new(29.3, 12, 24))
	Kit.crate(detail, CFrame.new(-26, 0, 32), 2.6)
	Kit.crate(detail, CFrame.new(-23, 0, 33), 1.8)
	Kit.barrel(detail, CFrame.new(-26, 0, 28))
	Kit.table(detail, CFrame.new(26, 0, -30))
	Kit.bones(detail, CFrame.new(-24, 0, -30))
	Kit.puddle(detail, CFrame.new(-14, 0, -24), 5, 4)
	Kit.puddle(detail, CFrame.new(16, 0, 10), 4, 3)
	Kit.moss(detail, CFrame.new(24, 0, -14), 4, 3)
	Kit.hay(detail, CFrame.new(27, 0, 0))
	-- points: the zone centre sits at z -8 (56 x 56 from -36 to 20, in front of the dais)
	attach(base, "Threshold", Vector3.new(0, 1.5, -26))
	for i = 1, 4 do
		attach(base, "Spawn" .. i, Vector3.new(-6 + (i - 1) * 4, 1.5, -32))
	end
	attach(base, "Dais", Vector3.new(0, 1.5, daisZ))
	attach(base, "ZoneCenter", Vector3.new(0, 1.5, -8))
	return model
end

-- Entrance_1: the hall where a run starts (the pads Spawn1..4, a stair down to the first corridor's door)
function Rooms.Entrance()
	local w, d = 28, 24
	local seed = 600
	local model, base, detail = newTemplate("Entrance_1", w, d, Vector3.new(0, 0, -12), Vector3.new(0, 0, 12))
	Kit.floorTiles(model, w, d, C.Flag, M.Cobblestone, seed)
	Kit.wall(model, CFrame.new(0, 0, -12.5, -1, 0, 0, 0, 1, 0, 0, 0, -1), w + 2, C.Stone, M.Slate, seed + 1)
	Kit.wall(model, CFrame.new(0, 0, 12.5, 1, 0, 0, 0, 1, 0, 0, 0, 1), w + 2, C.Stone, M.Slate, seed + 2, { X = 0, Width = 8 })
	Kit.wall(model, CFrame.new(-14.5, 0, 0) * CFrame.Angles(0, -PI / 2, 0), d, C.Stone, M.Slate, seed + 3)
	Kit.wall(model, CFrame.new(14.5, 0, 0) * CFrame.Angles(0, PI / 2, 0), d, C.Stone, M.Slate, seed + 4)
	Kit.ceiling(model, w, d)
	for _, sx in ipairs({ -1, 1 }) do
		Kit.pillar(model, CFrame.new(sx * 12.6, 0, -10.6), WALL_H + 0.5, C.Stone)
		Kit.pillar(model, CFrame.new(sx * 12.6, 0, 10.6), WALL_H + 0.5, C.Stone)
		Kit.torch(model, CFrame.new(sx * 13.5, 6.5, 1) * CFrame.Angles(0, sx * PI / 2, 0))
	end
	Kit.torch(model, CFrame.new(-7, 7, 11.5))
	Kit.torch(model, CFrame.new(7, 7, 11.5))
	-- four spawn pads (Marble inlays) and the banner wall
	for i = 1, 4 do
		local x = -7.5 + (i - 1) * 5
		Kit.part(model, CFrame.new(x, 0.1, -4), Vector3.new(3.6, 0.2, 3.6), C.Marble, M.Marble, { Name = "Pad" })
		attach(base, "Spawn" .. i, Vector3.new(x, 1.5, -4))
	end
	Kit.banner(detail, CFrame.new(-6, 11, -11.4) * CFrame.Angles(0, PI, 0))
	Kit.banner(detail, CFrame.new(6, 11, -11.4) * CFrame.Angles(0, PI, 0))
	Kit.barrel(detail, CFrame.new(-11, 0, 9))
	Kit.crate(detail, CFrame.new(11, 0, 9), 2.2)
	Kit.moss(detail, CFrame.new(10, 0, -9), 3, 2.4)
	Kit.puddle(detail, CFrame.new(-9, 0, 2), 3.6, 3)
	attach(base, "Threshold", Vector3.new(0, 1.5, 6))
	attach(base, "Dais", Vector3.new(0, 1.5, 8))
	return model
end

-- Corridor_Straight / Left / Right: 10-wide, 15-long passages (Left / Right jog JOG studs sideways: the seeded path)
function Rooms.Corridor(kind)
	local jog = (kind == "Left") and -JOG or ((kind == "Right") and JOG or 0)
	local seed = 700 + (jog + 20)
	local model, base, detail = newTemplate("Corridor_" .. kind, 10 + abs(jog), 15, Vector3.new(0, 0, -7.5), Vector3.new(jog, 0, 7.5))
	-- floor tiles (5 studs): the entry column, the cross row, the exit column
	local function tile(x, z)
		Kit.part(model, CFrame.new(x, -0.5 + (((x + z) / 5) % 2 == 0 and 0.05 or -0.05), z), Vector3.new(5, 1, 5), jitter(C.FlagDark, seed + x * 3 + z), M.Cobblestone, { Name = "Floor", Collide = true })
	end
	if jog == 0 then
		for _, x in ipairs({ -2.5, 2.5 }) do
			for _, z in ipairs({ -5, 0, 5 }) do
				tile(x, z)
			end
		end
		for _, sx in ipairs({ -1, 1 }) do
			Kit.wall(model, CFrame.new(sx * 5.5, 0, 0) * CFrame.Angles(0, sx * PI / 2, 0), 15, C.Stone, M.Slate, seed + sx, nil, true)
		end
		Kit.ceiling(model, 10, 15)
		Kit.torch(model, CFrame.new(-4.5, 6.5, 0) * CFrame.Angles(0, -PI / 2, 0))
		Kit.torch(model, CFrame.new(4.5, 6.5, 0) * CFrame.Angles(0, PI / 2, 0))
	else
		local s = jog > 0 and 1 or -1
		-- entry column (z -7.5..-2.5), cross row (z -2.5..2.5), exit column (z 2.5..7.5)
		tile(-2.5, -5)
		tile(2.5, -5)
		for i = 0, 4 do
			tile(s * (-2.5 + i * 5), 0)
		end
		tile(jog - 2.5, 5)
		tile(jog + 2.5, 5)
		-- walls around the jog (LookVector into the walkway): entry outer / inner, the cross row's two sides, exit inner / outer
		Kit.wall(model, CFrame.new(-s * 5.5, 0, -2.5) * CFrame.Angles(0, -s * PI / 2, 0), 10, C.Stone, M.Slate, seed + 1, nil, true)
		Kit.wall(model, CFrame.new(s * 5.5, 0, -5) * CFrame.Angles(0, s * PI / 2, 0), 5, C.Stone, M.Slate, seed + 2, nil, true)
		Kit.wall(model, CFrame.new(s * 12.5, 0, -3) * CFrame.Angles(0, PI, 0), 15, C.Stone, M.Slate, seed + 3, nil, true)
		Kit.wall(model, CFrame.new(s * 2.5, 0, 3), 15, C.Stone, M.Slate, seed + 4, nil, true)
		Kit.wall(model, CFrame.new(jog + s * 5.5, 0, 2.5) * CFrame.Angles(0, s * PI / 2, 0), 10, C.Stone, M.Slate, seed + 5, nil, true)
		Kit.wall(model, CFrame.new(jog - s * 5.5, 0, 5) * CFrame.Angles(0, -s * PI / 2, 0), 5, C.Stone, M.Slate, seed + 6, nil, true)
		Kit.ceiling(model, 10 + abs(jog), 15)
		Kit.torch(model, CFrame.new(s * 4.5, 6.5, -5) * CFrame.Angles(0, s * PI / 2, 0))
		Kit.torch(model, CFrame.new(jog - s * 4.5, 6.5, 5) * CFrame.Angles(0, -s * PI / 2, 0))
	end
	Kit.puddle(detail, CFrame.new(jog / 2, 0, 0), 3, 2.4)
	if jog == 0 then
		Kit.chain(detail, CFrame.new(-4.6, 11, 4))
		Kit.moss(detail, CFrame.new(0, 0, 5.5), 2.4, 1.8)
	end
	return model
end

-- Treasure_1: the alcove after the boss: four chests, the exit portal "Back to the plaza"
function Rooms.Treasure()
	local w, d = 28, 22
	local seed = 800
	local model, base, detail = newTemplate("Treasure_1", w, d, Vector3.new(0, 0, -11), Vector3.new(0, 0, 11))
	Kit.floorTiles(model, w, d, C.Flag, M.Cobblestone, seed)
	Kit.wall(model, CFrame.new(0, 0, -11.5, -1, 0, 0, 0, 1, 0, 0, 0, -1), w + 2, C.Stone, M.Slate, seed + 1, { X = 0, Width = 8 }, true)
	Kit.wall(model, CFrame.new(0, 0, 11.5, 1, 0, 0, 0, 1, 0, 0, 0, 1), w + 2, C.Stone, M.Slate, seed + 2, nil, true)
	Kit.wall(model, CFrame.new(-14.5, 0, 0) * CFrame.Angles(0, -PI / 2, 0), d, C.Stone, M.Slate, seed + 3, nil, true)
	Kit.wall(model, CFrame.new(14.5, 0, 0) * CFrame.Angles(0, PI / 2, 0), d, C.Stone, M.Slate, seed + 4, nil, true)
	Kit.ceiling(model, w, d)
	Kit.torch(model, CFrame.new(-13.5, 6.5, 0) * CFrame.Angles(0, -PI / 2, 0))
	Kit.torch(model, CFrame.new(13.5, 6.5, 0) * CFrame.Angles(0, PI / 2, 0))
	for i = 1, 4 do
		local x = -9 + (i - 1) * 6
		Kit.chest(model, CFrame.new(x, 0, 3), i)
		attach(base, "Chest" .. i, Vector3.new(x, 1.5, 3))
	end
	Kit.rune(detail, CFrame.new(0, 0, -3), 20, 0.5)
	-- the exit portal: a Marble arch with a purple shimmer and the prompt part
	Kit.arch(model, CFrame.new(0, 0, 9.4), 6, 9)
	Kit.part(model, CFrame.new(0, 4.2, 9.4), Vector3.new(5.6, 8, 0.15), WorldStyle.Palette.Accent.Purple, M.ForceField, { Name = "ExitShimmer", Transparency = 0.4 })
	local exitPart = Kit.part(model, CFrame.new(0, 3, 7.4), Vector3.new(1, 1, 1), C.Stone, M.Slate, { Name = "ExitPrompt", Transparency = 1 })
	exitPart:SetAttribute("DungeonAction", "Exit")
	local exitPrompt = Instance.new("ProximityPrompt")
	exitPrompt.Name = "ExitPrompt"
	exitPrompt.ActionText = "Leave"
	exitPrompt.ObjectText = "Back to the plaza"
	exitPrompt.KeyboardKeyCode = Enum.KeyCode.E
	exitPrompt.HoldDuration = 0
	exitPrompt.MaxActivationDistance = 10
	exitPrompt.RequiresLineOfSight = false
	exitPrompt:SetAttribute("DungeonAction", "Exit")
	exitPrompt.Parent = exitPart
	Kit.banner(detail, CFrame.new(-10, 11, 10.4))
	Kit.banner(detail, CFrame.new(10, 11, 10.4))
	Kit.skulls(detail, CFrame.new(-12, 0, -8))
	for i = 1, 4 do
		attach(base, "Spawn" .. i, Vector3.new(-6 + (i - 1) * 4, 1.5, -7))
	end
	attach(base, "Threshold", Vector3.new(0, 1.5, -6))
	attach(base, "Dais", Vector3.new(0, 1.5, 8))
	return model
end

----------------------------------------------------------------------
-- Template registry (geometry known without building: the layout plans a run before any set exists)
----------------------------------------------------------------------
local Geo = {} -- name -> { W, D, Entrance = Vector3, Exit = Vector3, Kind, Budget, build = fn }
local function geo(name, w, d, entrance, exit, kind, budget, build)
	Geo[name] = { Name = name, W = w, D = d, Entrance = entrance, Exit = exit, Kind = kind, Budget = budget, build = build }
end
for v = 1, 3 do
	geo("Hall_" .. v, 48, 48, Vector3.new(0, 0, -24), Vector3.new(0, 0, 24), "Room", 320, function() return Rooms.Hall(v) end)
	geo("Cellar_" .. v, 48, 48, Vector3.new(0, 0, -24), Vector3.new(0, 0, 24), "Room", 320, function() return Rooms.Cellar(v) end)
	geo("Cave_" .. v, 48, 48, Vector3.new(0, 0, -24), Vector3.new(0, 0, 24), "Room", 320, function() return Rooms.Cave(v) end)
end
for v = 1, 2 do
	geo("Bridge_" .. v, 48, 48, Vector3.new(0, 0, -24), Vector3.new(0, 0, 24), "Room", 320, function() return Rooms.Bridge(v) end)
end
geo("Throne_1", 60, 72, Vector3.new(0, 0, -36), Vector3.new(20, 0, 36), "Boss", 420, function() return Rooms.Throne(1) end)
geo("Entrance_1", 28, 24, Vector3.new(0, 0, -12), Vector3.new(0, 0, 12), "Hall", 140, function() return Rooms.Entrance() end)
geo("Corridor_Straight", 10, 15, Vector3.new(0, 0, -7.5), Vector3.new(0, 0, 7.5), "Corridor", 70, function() return Rooms.Corridor("Straight") end)
geo("Corridor_Left", 25, 15, Vector3.new(0, 0, -7.5), Vector3.new(-JOG, 0, 7.5), "Corridor", 70, function() return Rooms.Corridor("Left") end)
geo("Corridor_Right", 25, 15, Vector3.new(0, 0, -7.5), Vector3.new(JOG, 0, 7.5), "Corridor", 70, function() return Rooms.Corridor("Right") end)
geo("Treasure_1", 28, 22, Vector3.new(0, 0, -11), Vector3.new(0, 0, 11), "Treasure", 90, function() return Rooms.Treasure() end)

DungeonBuilder.Geo = Geo

local function templateFolder()
	local f = ServerStorage:FindFirstChild(TEMPLATE_FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = TEMPLATE_FOLDER
		f.Parent = ServerStorage
	end
	return f
end

function DungeonBuilder.CountParts(inst)
	local n = 0
	if typeof(inst) ~= "Instance" then
		return 0
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

-- the template (built now when missing, ~0.1 s)
function DungeonBuilder.Template(name)
	local g = Geo[name]
	if not g then
		return nil
	end
	local f = templateFolder()
	local existing = f:FindFirstChild(name)
	if existing then
		return existing
	end
	local model = g.build()
	model:SetAttribute("Kind", g.Kind)
	model:SetAttribute("Budget", g.Budget)
	model.Parent = f
	return model
end

function DungeonBuilder.EnsureTemplates()
	for _, name in ipairs(DungeonBuilder.Templates) do
		DungeonBuilder.Template(name)
	end
	return templateFolder()
end

----------------------------------------------------------------------
-- The portal (C4: built with WorldStyle.BuildGate into the Gate Court)
----------------------------------------------------------------------
local State = { Info = nil, Pockets = {}, Built = false }

function DungeonBuilder.BuildPortal(gatesFolder, siteCFrame)
	if typeof(siteCFrame) ~= "CFrame" then
		siteCFrame = CFrame.new(Config.Lobby.Origin + Vector3.new(0, 0, 118), Config.Lobby.Origin)
	end
	local model, pad, promptPart = WorldStyle.BuildGate(gatesFolder, siteCFrame, {
		Id = "Dungeon",
		Title = "The Dungeon",
		Info = "Rooms, waves and a boss. Solo or up to 4 friends",
		Pill = "Floors cleared here: -",
		Color = "Purple",
		Glyph = "torch",
		Pad = true,
	})
	-- two torches on the columns' inner faces
	local look = siteCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local site = CFrame.lookAt(siteCFrame.Position, siteCFrame.Position + flat.Unit)
	for _, sx in ipairs({ -1, 1 }) do
		local mount = site * CFrame.new(sx * 6.6, 9, -0.4) * CFrame.Angles(0, PI, 0)
		local flame = Kit.torch(model, mount, 1.2)
		local light = flame:FindFirstChild("TorchLight")
		if light then
			light.Range = 16 -- the lobby rule (6.4 rule 7)
			light.Color = WorldStyle.Palette.Lantern
		end
	end
	model:SetAttribute("DungeonBoard", "")
	-- the prompt (handled by ArenaController's onPromptTriggered next to "Ring": OpenPanel = "Dungeon")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DungeonPrompt"
	prompt.ActionText = "Enter"
	prompt.ObjectText = "The Dungeon"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenPanel", "Dungeon")
	prompt.Parent = promptPart
	-- the return point: on the pad, looking at the plaza
	local padCf = pad and pad.CFrame or (site * CFrame.new(0, 1, -14))
	local returnCf = CFrame.new(padCf.Position + Vector3.new(0, 3.5, 0) + flat.Unit * -2, padCf.Position + Vector3.new(0, 3.5, 0) + flat.Unit * -30)
	local info = { Portal = model, Pad = pad, PromptPart = promptPart, Prompt = prompt, ReturnCFrame = returnCf, Site = site }
	State.Info = info
	return info
end

-- Build(lobbyInfo) -> DungeonInfo: the gate now, the template sets in the background
function DungeonBuilder.Build(lobbyInfo)
	lobbyInfo = type(lobbyInfo) == "table" and lobbyInfo or {}
	local gates = lobbyInfo.GatesFolder
	if not gates then
		local lobby = workspace:FindFirstChild("NimbusLobby")
		gates = lobby and lobby:FindFirstChild("Gates")
		if not gates then
			gates = Instance.new("Folder")
			gates.Name = "Gates"
			gates.Parent = lobby or workspace
		end
	end
	local site = lobbyInfo.GateSites and lobbyInfo.GateSites.Dungeon or lobbyInfo.DungeonSite
	local info = DungeonBuilder.BuildPortal(gates, site)
	info.TemplateFolder = templateFolder()
	if not State.Built then
		State.Built = true
		task.spawn(function()
			for _, name in ipairs(DungeonBuilder.Templates) do
				local ok, err = pcall(DungeonBuilder.Template, name)
				if not ok then
					warn("[DungeonBuilder] template " .. name .. " failed: " .. tostring(err))
				end
				task.wait()
			end
		end)
	end
	return info
end

function DungeonBuilder.GetInfo()
	return State.Info
end

----------------------------------------------------------------------
-- Runs
----------------------------------------------------------------------
local function dungeonsFolder(create)
	local f = workspace:FindFirstChild(DUNGEONS_FOLDER)
	if not f and create then
		f = Instance.new("Folder")
		f.Name = DUNGEONS_FOLDER
		f.Parent = workspace
	end
	return f
end

local function elementColor(element)
	local ok, PetCatalog = pcall(require, Shared:FindFirstChild("PetCatalog"))
	if ok and type(PetCatalog) == "table" and type(PetCatalog.Elements) == "table" and PetCatalog.Elements[element] and typeof(PetCatalog.Elements[element].Color) == "Color3" then
		return PetCatalog.Elements[element].Color
	end
	local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[element]
	if info and typeof(info.Color) == "Color3" then
		return info.Color
	end
	return WorldStyle.Palette.Accent.Purple
end

local function floorDef(floorIndex)
	local ok, BattleCatalog = pcall(require, Shared:FindFirstChild("BattleCatalog"))
	local list = ok and type(BattleCatalog) == "table" and BattleCatalog.DungeonFloors or nil
	local def = type(list) == "table" and list[floorIndex] or nil
	if type(def) ~= "table" then
		def = { Name = "Floor " .. tostring(floorIndex), Element = "Earth", Kind = "Hall" }
	end
	return def
end

-- the seeded chain of a run: piece names + their placement CFrames (pocket-local, heading +Z from the origin)
local Layout = {}

function Layout.plan(floorIndex, seed)
	local def = floorDef(floorIndex)
	local kind = DungeonBuilder.Kinds[def.Kind] and def.Kind or "Hall"
	local variants = DungeonBuilder.Kinds[kind]
	local r = rng((seed or 1) * 7 + floorIndex * 131)
	local names = { "Entrance_1" }
	local x = 0
	local function corridor()
		local pick = r(3)
		local name = "Corridor_Straight"
		if pick == 2 and x - JOG >= -60 then
			name = "Corridor_Left"
		elseif pick == 3 and x + JOG <= 60 then
			name = "Corridor_Right"
		end
		x = x + Geo[name].Exit.X
		names[#names + 1] = name
	end
	for room = 1, 3 do
		corridor()
		names[#names + 1] = kind .. "_" .. r(variants)
	end
	corridor()
	names[#names + 1] = "Throne_1"
	corridor()
	names[#names + 1] = "Treasure_1"
	-- placements: each piece's Entrance lands on the previous piece's Exit (same heading)
	local pieces = {}
	local cursor = CFrame.new(0, 0, 0) -- the current piece's origin
	for i, name in ipairs(names) do
		local g = Geo[name]
		if i == 1 then
			cursor = CFrame.new(-g.Entrance.X, 0, -g.Entrance.Z)
		else
			local prev = pieces[i - 1]
			local exitWorld = prev.CFrame * CFrame.new(Geo[prev.Name].Exit)
			cursor = exitWorld * CFrame.new(-g.Entrance.X, 0, -g.Entrance.Z)
		end
		pieces[i] = { Name = name, CFrame = cursor, Kind = g.Kind, W = g.W, D = g.D }
	end
	-- rooms by index: 0 = hall, 1..4 fight rooms, 5 the treasure; corridor k leads into room k
	local rooms = {}
	rooms[0] = { Piece = 1 }
	local roomIndex = 0
	for i = 2, #pieces, 2 do
		roomIndex = roomIndex + 1
		rooms[roomIndex] = { Piece = i + 1, Corridor = i }
	end
	return { Floor = floorIndex, Seed = seed, Def = def, Kind = kind, Pieces = pieces, Rooms = rooms }
end

function DungeonBuilder.Plan(floorIndex, seed)
	return Layout.plan(floorIndex, seed)
end

-- the world-space bounding box of a planned piece (for the overlap test)
function DungeonBuilder.PieceBox(pocket, pieceIndex)
	local piece = pocket.Layout.Pieces[pieceIndex]
	if not piece then
		return nil
	end
	local cf = CFrame.new(pocket.Origin) * piece.CFrame
	local p = cf.Position
	return { MinX = p.X - piece.W / 2, MaxX = p.X + piece.W / 2, MinZ = p.Z - piece.D / 2, MaxZ = p.Z + piece.D / 2, Name = piece.Name }
end

local function recolourAccents(model, color)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Accent") == true then
			d.Color = color
			n = n + 1
		end
	end
	return n
end

local function worldPoint(model, name)
	local base = model.PrimaryPart
	local a = base and base:FindFirstChild(name)
	if a then
		return base.CFrame * a.CFrame
	end
	return nil
end

-- clones the template of a piece and places it in pocket space (not parented yet)
local function clonePiece(pocket, pieceIndex, holder)
	local piece = pocket.Layout.Pieces[pieceIndex]
	local template = DungeonBuilder.Template(piece.Name)
	if not template then
		return nil
	end
	local copy = template:Clone()
	copy:SetAttribute("PieceIndex", pieceIndex)
	local cf = CFrame.new(pocket.Origin) * piece.CFrame
	-- the template's Base stands at its local origin: every part moves by the same delta
	local base = copy.PrimaryPart or copy:FindFirstChild("Base")
	local delta = base and (cf * base.CFrame) * base.CFrame:Inverse() or cf
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	copy.Parent = holder
	return copy
end

-- the zone part of a fight room: Mode "Dungeon", ZoneId "Room", Index (pocket), Room
local function makeZone(model, pocket, room, size, centerCf)
	local zone = Instance.new("Part")
	zone.Name = "NC_BattleZone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Material = Enum.Material.SmoothPlastic
	zone.CastShadow = false
	zone.Size = Vector3.new(size.X, 16, size.Z)
	zone.CFrame = centerCf * CFrame.new(0, 6, 0)
	zone:SetAttribute("Mode", "Dungeon")
	zone:SetAttribute("ZoneId", "Room")
	zone:SetAttribute("Index", pocket.Index)
	zone:SetAttribute("Room", room)
	zone:SetAttribute("Size", size.X)
	zone:SetAttribute("FloorY", centerCf.Position.Y)
	CollectionService:AddTag(zone, ZONE_TAG)
	zone.Parent = model
	return zone
end

-- PlaceRoom(pocket, room) -> RoomInfo: room 1..4 (the fight rooms) or 5 (the treasure alcove); the inbound corridor
-- comes with it. Assembled under ServerStorage, parented in ONE step.
function DungeonBuilder.PlaceRoom(pocket, room)
	if type(pocket) ~= "table" or not pocket.Layout or not pocket.Layout.Rooms[room] then
		return nil, "BadRoom"
	end
	if pocket.Rooms[room] then
		return pocket.Rooms[room]
	end
	local entry = pocket.Layout.Rooms[room]
	if not pocket.Model or pocket.Model.Parent == nil then
		return nil, "Freed"
	end
	local staging = Instance.new("Model")
	staging.Name = "Room_" .. room
	staging.Parent = templateFolder() -- assembled out of the workspace
	local corridor = entry.Corridor and clonePiece(pocket, entry.Corridor, staging) or nil
	local model = clonePiece(pocket, entry.Piece, staging)
	if not model then
		staging:Destroy()
		return nil, "NoTemplate"
	end
	local piece = pocket.Layout.Pieces[entry.Piece]
	local color = elementColor(pocket.Layout.Def.Element)
	recolourAccents(staging, color)
	-- floor 1 is the brightest (no abyss): every torch a little stronger
	if pocket.Floor == 1 then
		for _, d in ipairs(staging:GetDescendants()) do
			if d:IsA("PointLight") then
				d.Brightness = min(1.5, d.Brightness + 0.3)
			elseif d.Name == "Abyss" and d:IsA("BasePart") then
				d.Transparency = 1
			end
		end
	end
	local info = {
		Index = room,
		Kind = piece.Kind,
		Template = piece.Name,
		Model = staging,
		Room = model,
		Corridor = corridor,
		Spawns = {},
		Chests = {},
	}
	local entranceCf = worldPoint(model, "Entrance")
	local exitCf = worldPoint(model, "Exit")
	local center = model.PrimaryPart.CFrame * CFrame.new(0, 1.5, 0)
	info.Center = center.Position
	info.Entrance = entranceCf and (entranceCf * CFrame.new(0, 3, 3)) or center
	for i = 1, 4 do
		local sp = worldPoint(model, "Spawn" .. i)
		info.Spawns[i] = sp and (sp * CFrame.new(0, 3, 0)) or info.Entrance
	end
	local thresholdCf = worldPoint(model, "Threshold")
	if thresholdCf then
		local th = Instance.new("Part")
		th.Name = "Threshold"
		th.Anchored = true
		th.CanCollide = false
		th.CanQuery = false
		th.CanTouch = false
		th.Transparency = 1
		th.Material = Enum.Material.SmoothPlastic
		th.CastShadow = false
		th.Size = Vector3.new(12, 8, 4)
		th.CFrame = thresholdCf * CFrame.new(0, 2.5, 0)
		th:SetAttribute("Room", room)
		th.Parent = staging
		info.Threshold = th
	end
	if piece.Kind == "Room" or piece.Kind == "Boss" then
		local size = piece.Kind == "Boss" and Vector3.new(56, 0, 56) or Vector3.new(44, 0, 44)
		local zc = worldPoint(model, "ZoneCenter")
		info.Zone = makeZone(staging, pocket, room, size, zc and CFrame.new(zc.Position) or CFrame.new(center.Position - Vector3.new(0, 1.5, 0)))
		-- the two portcullis doors: Entrance (closed when the fight starts) and Exit (opens after the clear)
		if entranceCf then
			local door, bars = Kit.door(staging, CFrame.new(entranceCf.Position - Vector3.new(0, 1.5, 0)) * CFrame.new(0, 0, 0), "Door_Entrance", 8)
			info.Door = { Model = door, Bars = bars }
			Kit.setDoor(door, true)
		end
		if exitCf then
			local door, bars = Kit.door(staging, CFrame.new(exitCf.Position - Vector3.new(0, 1.5, 0)), "Door_Exit", 8)
			info.ExitDoor = { Model = door, Bars = bars }
			Kit.setDoor(door, false)
		end
		staging:SetAttribute("DoorOpen", false)
		staging:SetAttribute("EntranceOpen", true)
	else
		for i = 1, 4 do
			local c = worldPoint(model, "Chest" .. i)
			if c then
				for _, d in ipairs(model:GetDescendants()) do
					if d.Name == "Chest" and d:GetAttribute("ChestSlot") == i then
						info.Chests[i] = d
					end
				end
			end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "ExitPrompt" then
				info.ExitPrompt = d
			end
		end
	end
	staging:SetAttribute("Room", room)
	staging:SetAttribute("Floor", pocket.Floor)
	staging:SetAttribute("Element", pocket.Layout.Def.Element)
	-- one replication burst
	staging.Parent = pocket.Model
	pocket.Rooms[room] = info
	return info
end

function DungeonBuilder.SetDoor(info, which, open)
	if type(info) ~= "table" then
		return
	end
	local door = (which == "Exit") and info.ExitDoor or info.Door
	if door and door.Model then
		Kit.setDoor(door.Model, open == true)
	end
	if info.Model then
		info.Model:SetAttribute(which == "Exit" and "DoorOpen" or "EntranceOpen", open == true)
	end
end

function DungeonBuilder.RemoveRoom(pocket, room)
	if type(pocket) ~= "table" or not pocket.Rooms then
		return false
	end
	local info = pocket.Rooms[room]
	if not info then
		return false
	end
	pocket.Rooms[room] = nil
	if info.Model then
		info.Model:Destroy()
	end
	return true
end

function DungeonBuilder.PocketOrigin(index)
	local i = max(1, floor(index or 1)) - 1
	local col, row = i % 4, floor(i / 4)
	return Vector3.new(9000 + col * 600, 160, 9000 + row * 600)
end

-- BuildRun(index, floor, seed) -> Pocket: the holder, the hall (room 0), the corridor to room 1 and room 1
function DungeonBuilder.BuildRun(index, floorIndex, seed)
	index = floor(tonumber(index) or 1)
	if index < 1 or index > MAX_INDEX then
		return nil, "BadIndex"
	end
	if State.Pockets[index] then
		return nil, "Busy"
	end
	floorIndex = max(1, min(12, floor(tonumber(floorIndex) or 1)))
	seed = floor(tonumber(seed) or 1)
	local folder = dungeonsFolder(true)
	local holder = Instance.new("Model")
	holder.Name = "Dungeon_" .. index
	holder:SetAttribute("Index", index)
	holder:SetAttribute("Floor", floorIndex)
	holder:SetAttribute("Seed", seed)
	local pocket = {
		Index = index,
		Origin = DungeonBuilder.PocketOrigin(index),
		Model = holder,
		Floor = floorIndex,
		Seed = seed,
		Layout = Layout.plan(floorIndex, seed),
		Rooms = {},
	}
	pocket.Name = pocket.Layout.Def.Name
	pocket.Element = pocket.Layout.Def.Element
	holder.Parent = folder
	-- the hall
	local hall = clonePiece(pocket, 1, holder)
	if hall then
		local color = elementColor(pocket.Element)
		recolourAccents(hall, color)
		local spawns = {}
		for i = 1, 4 do
			local sp = worldPoint(hall, "Spawn" .. i)
			spawns[i] = sp and (sp * CFrame.new(0, 3, 0)) or (hall.PrimaryPart.CFrame * CFrame.new(0, 4.5, 0))
		end
		local exitCf = worldPoint(hall, "Exit")
		local door, bars = Kit.door(hall, CFrame.new(exitCf and (exitCf.Position - Vector3.new(0, 1.5, 0)) or hall.PrimaryPart.Position), "Door_Exit", 8)
		Kit.setDoor(door, false)
		hall:SetAttribute("DoorOpen", false)
		pocket.Hall = { Index = 0, Kind = "Hall", Model = hall, Room = hall, Spawns = spawns, Center = hall.PrimaryPart.Position + Vector3.new(0, 1.5, 0), ExitDoor = { Model = door, Bars = bars }, Entrance = spawns[1] }
		pocket.Rooms[0] = pocket.Hall
	end
	State.Pockets[index] = pocket
	DungeonBuilder.PlaceRoom(pocket, 1)
	return pocket
end

function DungeonBuilder.GetPocket(index)
	return State.Pockets[index]
end

function DungeonBuilder.FreeRun(index)
	index = floor(tonumber(index) or 0)
	local pocket = State.Pockets[index]
	State.Pockets[index] = nil
	local folder = dungeonsFolder(false)
	local holder = pocket and pocket.Model or (folder and folder:FindFirstChild("Dungeon_" .. index))
	if holder then
		holder:Destroy()
	end
	if pocket then
		pocket.Rooms = {}
	end
	if folder and #folder:GetChildren() == 0 then
		folder:Destroy()
	end
	return pocket ~= nil
end

-- the live BasePart count of a run (hall + rooms + corridors)
function DungeonBuilder.LiveParts(pocket)
	if type(pocket) ~= "table" or not pocket.Model then
		return 0
	end
	return DungeonBuilder.CountParts(pocket.Model)
end

return DungeonBuilder
