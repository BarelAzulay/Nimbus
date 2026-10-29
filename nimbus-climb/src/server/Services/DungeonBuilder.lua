--!nocheck
-- DungeonBuilder (ARCHITECTURE_V3.md "Phase 5 build contract" 5.5, art per image 22, the rules of 6.4; dungeon W3)
--
-- The Dungeon gate in the Gate Court and the run instances (pockets) of DungeonService.
--
--   DungeonBuilder.Build(lobbyInfo) -> DungeonInfo    the gate (BuildPortal) + the template folder; the templates are
--                                                      built in a task.spawn after boot, one set per task.wait()
--   DungeonBuilder.BuildPortal(gatesFolder, siteCFrame) -> DungeonInfo { Portal, Pad, PromptPart, ReturnCFrame, Prompt }
--                                                      WorldStyle.BuildGate (the P4 hoop, Purple, "torch" = the skull
--                                                      crest, pill from the attribute DungeonBoard) + two torches on its
--                                                      pillars, <= 120 parts; prompt "DungeonPrompt"
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
--   (wave 6) every placed piece model carries CamMin / CamMax (Vector3, world): its camera box (the W x D shell, a
--                                                      corridor's floor tiles; floor - 2 .. its ceiling's bottom), read
--                                                      by DungeonController's camera clamp
--   DungeonBuilder.SetDoor(roomInfo, "Entrance"|"Exit", open) the bars' two states (CanCollide + Transparency) + the
--                                                      room model attributes DoorOpen (exit) / EntranceOpen
--   DungeonBuilder.FreeRun(index)                     the holder destroyed; the Dungeons folder goes with the last run
--   DungeonBuilder.Template(name) -> Model            a template (built on demand); EnsureTemplates() builds every set
--   DungeonBuilder.CountParts(instance) -> n          BasePart descendants
--   DungeonBuilder.Templates / Budgets / Kinds        data for tests and the renderer
--
-- RoomInfo = { Index, Kind, Template, Model, Zone, ZoneFloor (CFrame: the floor centre ON the floor top = the encounter
--             centre), Entrance (CFrame), Threshold (part), Door = { Bars }, ExitDoor = { Bars }, Center (Vector3), Spawns
--             = { CFrame... }, Chests = { part... }, Corridor, EnterPrompt (the entrance's, corridor side), NextPrompt (the
--             boss room's exit -> the treasure; Pocket.Hall.NextPrompt = the hall's exit -> room 1) }
-- Doors (dungeon-fixes decision 2): every Door_Entrance is placed CLOSED (EntranceOpen false); the EnterPrompt
-- ProximityPrompts (E, HoldDuration 0, RequiresLineOfSight false, MaxActivationDistance 10, DungeonAction "Enter",
-- ActionText "Enter", ObjectText "Room N" / "Boss room" / "Treasure", attribute TargetRoom) are built DISABLED;
-- DungeonService enables the one the group walks to and moves the group on when every member pressed it.
--
-- Art (Phase 6 A1: a cute, colourful voxel dungeon in the P4 spirit): lilac storybook stone walls with plinth, body
-- and cap, warm sandstone 6-stud flagstones (+-0.05 alternation), wall torches (bracket + stick + Neon flame + Fire +
-- PointLight range 18 amber, Shadows off), puddles, juicy moss, barrels, crates, chains, pillars, arches, a
-- portcullis on every door, stairs to a dais and a throne under a magenta carpet (the Throne set), caves with rock
-- walls, stalagmites, a turquoise pool and a waterfall wall, bridges over a deep violet chasm (an invisible floor
-- under it), a dark violet ceiling 16 studs up. SmoothPlastic only (Neon for glow, Glass for water and bottles,
-- ForceField for shimmer), blocky voxel shapes only (no Cylinder / Ball: barrels, bowls and rings are blocks);
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
-- bug batch 2 #14: the chests Treasure_1 builds (each member picks ONE); DungeonService.Init asserts this is >= its
-- CHEST_SLOTS (= MAX_PARTY 4). Read through deps there, so no require loop.
DungeonBuilder.CHEST_COUNT = 4

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local PI = math.pi
local rgb = Color3.fromRGB

-- Phase 6 A1 (back to the P4 look): every material key is SmoothPlastic; only Neon / Glass / ForceField stay
local M = setmetatable({ Neon = Enum.Material.Neon, Glass = Enum.Material.Glass, ForceField = Enum.Material.ForceField }, {
	__index = function()
		return Enum.Material.SmoothPlastic
	end,
})
local P4_MATS = { [Enum.Material.SmoothPlastic] = true, [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }
local ZONE_TAG = "NC_BattleZone"
local DETAIL_TAG = (WorldStyle.Tags and WorldStyle.Tags.Detail) or "NC_Detail"
local TEMPLATE_FOLDER = "DungeonTemplates"
local DUNGEONS_FOLDER = "Dungeons"
local WALL_H = 15 -- wall height; the ceiling slab sits on the cap, 16 studs up
local CEIL_Y = 15.8
local ASTRO_HUB_Y = 12.9 -- the B boss room's astrolabe hub (the outer ring's mesh top 15.4: 0.4 under the ceiling)
local TILE = 6
local MAX_INDEX = 12
local JOG = 15 -- the lateral shift of a Left / Right corridor
-- the battle zones (BattleCatalog.Dungeon.Zones when it loads: Room 44 x 44, Boss 56 x 72 = the whole Throne floor)
local ROOM_ZONE = { X = 44, Z = 44 }
local BOSS_ZONE = { X = 56, Z = 72 }
do
	local okZ, BattleCatalog = pcall(require, Shared:FindFirstChild("BattleCatalog"))
	local zones = okZ and type(BattleCatalog) == "table" and type(BattleCatalog.Dungeon) == "table" and BattleCatalog.Dungeon.Zones or nil
	if type(zones) == "table" then
		for name, target in pairs({ Room = ROOM_ZONE, Boss = BOSS_ZONE }) do
			local z = zones[name]
			if type(z) == "table" and tonumber(z.X) and tonumber(z.Z) then
				target.X, target.Z = tonumber(z.X), tonumber(z.Z)
			end
		end
	end
end

-- the chain of a run (room 0 = the hall, 1..4 the fight rooms, 5 the treasure alcove); every piece heads +Z
DungeonBuilder.Budgets = { Room = 320, Boss = 420, Hall = 140, Corridor = 70, Treasure = 90, Run = 950, Portal = 120 }
DungeonBuilder.Kinds = { Hall = 3, Cellar = 3, Cave = 3, Bridge = 2, Throne = 1 }
DungeonBuilder.Templates = {
	"Hall_1", "Hall_2", "Hall_3", "Cellar_1", "Cellar_2", "Cellar_3", "Cave_1", "Cave_2", "Cave_3", "Bridge_1", "Bridge_2",
	"Throne_1", "Entrance_1", "Corridor_Straight", "Corridor_Left", "Corridor_Right", "Treasure_1",
}

----------------------------------------------------------------------
-- Colours (Phase 6 A1: a cute, colourful voxel dungeon in the P4 spirit: lilac storybook stone, warm sandstone
-- flagstones, gold trim, juicy moss and turquoise water; bright enough for the dungeon's darker lighting preset)
----------------------------------------------------------------------
local BASE = {
	Stone = rgb(170, 160, 212), -- lilac castle stone
	StoneDark = rgb(130, 120, 182),
	StoneLight = rgb(198, 190, 236),
	Brick = rgb(186, 156, 214),
	Flag = rgb(232, 210, 166), -- the warm sandstone floor
	FlagDark = rgb(210, 184, 140),
	Ceiling = rgb(104, 92, 156),
	Wood = rgb(150, 100, 66),
	Plank = rgb(196, 146, 98),
	Iron = rgb(74, 82, 108),
	Gold = rgb(244, 198, 84),
	Flame = rgb(255, 184, 96),
	Ember = rgb(255, 120, 60),
	Light = rgb(255, 190, 120), -- amber torch light
	Moss = rgb(110, 200, 120),
	Hay = rgb(250, 214, 120),
	Water = rgb(92, 200, 236), -- the turquoise pool
	WaterGlow = rgb(150, 236, 255),
	Puddle = rgb(120, 190, 240),
	Carpet = rgb(206, 72, 150), -- the throne's magenta carpet
	Rock = rgb(156, 146, 196),
	RockDark = rgb(124, 114, 170),
	Abyss = rgb(60, 50, 104),
	Bone = rgb(246, 240, 226),
	Marble = rgb(240, 238, 248),
	Accent = rgb(176, 120, 240), -- the default accent (recoloured to the floor's element)
	Core = rgb(255, 184, 96), -- a brazier's glowing heart (the flame)
	CoreLight = rgb(255, 190, 120),
}

----------------------------------------------------------------------
-- bug #5 (art wave, player-approved B "The Weatherworks" + the note "every dungeon level needs a different design ...
-- the higher level of the dungeon the more serious it looks"): three looks, one per depth tier, chosen by the run's
-- floor. The colliders and the room layouts are the same in every look; the Part colours (the fallback), the Blender
-- keys (dungeon_<style>_wall_48 ...: blender/kit/props/dungeon_style.py) and a few style props differ.
--   c  The Root Conservatory  floors 1-3   the softest: a seed vault taken over by roots (terracotta, glasshouse ribs)
--   b  The Weatherworks       floors 4-8   the approved look: the Cloud-Smiths' machine halls (riveted panels, pipes)
--   a  The Cloudkeep Undercroft floors 9-12 the most serious: the old castle under everything (dark granite, pointed
--                             arches, a sky window behind the throne)
-- Inside a tier each floor's colours get a little darker (Deepen) and its contrast a little harder (the client mood,
-- Mood*). The mood is never darker than the P4 dungeon preset (MoodFloor: ambient 70,62,86, brightness -0.12): the
-- fights must stay readable on a phone; the palette, the colours and the contrast carry "serious". Every floor also gets its
-- element's weathering set (dungeon_wx_<element>_high / _low: moss, crystals, drips, icicles, soot, scorch, star-moss,
-- shadow crystals) and its element colour on one accent per look (ML_Secondary). Ranges are data: StyleTiers.
----------------------------------------------------------------------
DungeonBuilder.DefaultStyle = "b"
DungeonBuilder.StyleTiers = {
	{ First = 1, Last = 3, Style = "c" },
	{ First = 4, Last = 8, Style = "b" },
	{ First = 9, Last = 12, Style = "a" },
}
DungeonBuilder.StyleOrder = { "c", "b", "a" } -- by seriousness (Rank)
DungeonBuilder.Styles = {
	c = {
		Id = "c",
		Name = "The Root Conservatory",
		Rank = 1,
		Deepen = 0.9, -- the tier's last floor: wall / floor colours x 0.9
		Bricks = true, -- the protruding stones of a wall run (a terracotta brick out of line)
		Palette = {
			Stone = rgb(198, 118, 84), -- terracotta brick
			StoneDark = rgb(104, 82, 66), -- the soil-stone base
			StoneLight = rgb(226, 170, 132),
			Brick = rgb(186, 106, 78),
			Flag = rgb(148, 154, 126), -- mossy grey flagstones
			FlagDark = rgb(128, 136, 110),
			Ceiling = rgb(84, 70, 58), -- old timber
			Carpet = rgb(204, 126, 88), -- the terracotta path
			Rock = rgb(150, 136, 112),
			RockDark = rgb(120, 106, 88),
			Abyss = rgb(46, 62, 56),
			Marble = rgb(234, 236, 224),
			Light = rgb(255, 208, 140),
			Flame = rgb(255, 200, 112),
			Core = rgb(236, 255, 150), -- the pitcher plants' glow
			CoreLight = rgb(220, 255, 170),
		},
		Mood = { Ambient = rgb(94, 88, 96), Outdoor = rgb(110, 104, 112), Brightness = -0.05, Contrast = 0.06, Tint = rgb(246, 238, 222) },
	},
	b = {
		Id = "b",
		Name = "The Weatherworks",
		Rank = 2,
		Deepen = 0.84,
		Bricks = false, -- riveted panels: nothing sticks out of line
		Palette = {
			Stone = rgb(226, 230, 240), -- white dressed panels
			StoneDark = rgb(62, 76, 108), -- the storm-blue plinth / girders
			StoneLight = rgb(238, 240, 248),
			Brick = rgb(208, 214, 228),
			Flag = rgb(122, 136, 168), -- slate-blue tiles
			FlagDark = rgb(104, 118, 150),
			Ceiling = rgb(44, 54, 82),
			Carpet = rgb(58, 74, 132), -- the navy runner
			Gold = rgb(222, 172, 72), -- brass
			Iron = rgb(70, 80, 106),
			Rock = rgb(124, 132, 160),
			RockDark = rgb(96, 104, 134),
			Abyss = rgb(30, 40, 66),
			Light = rgb(255, 222, 170), -- lantern light
			Flame = rgb(255, 214, 140),
			Core = rgb(150, 232, 255), -- the condenser coils' cyan heart
			CoreLight = rgb(160, 226, 255),
		},
		Mood = { Ambient = rgb(70, 66, 90), Outdoor = rgb(86, 82, 108), Brightness = -0.1, Contrast = 0.12, Tint = rgb(230, 234, 242) },
	},
	a = {
		Id = "a",
		Name = "The Cloudkeep Undercroft",
		Rank = 3,
		Deepen = 0.78,
		Bricks = true,
		Palette = {
			Stone = rgb(154, 160, 178), -- grey-blue granite blocks
			StoneDark = rgb(70, 82, 110), -- the slate plinth / cornice
			StoneLight = rgb(182, 186, 202),
			Brick = rgb(140, 146, 166),
			Flag = rgb(150, 146, 144), -- big worn flagstones
			FlagDark = rgb(124, 120, 120),
			Ceiling = rgb(44, 44, 58),
			Carpet = rgb(150, 34, 48), -- the red carpet
			Gold = rgb(214, 170, 80),
			Iron = rgb(58, 62, 78),
			Rock = rgb(118, 120, 136),
			RockDark = rgb(92, 94, 110),
			Abyss = rgb(24, 22, 38),
			Marble = rgb(222, 220, 214),
			Light = rgb(255, 176, 104), -- old warm torchlight
			Flame = rgb(255, 176, 92),
			Core = rgb(255, 150, 70),
			CoreLight = rgb(255, 160, 90),
		},
		-- (the review: a 4-way darkening stack (ambient 52,50,66 x0.85, brightness -0.20, lights -15%, colours x0.78) had no
		-- in-engine evidence of readability; A now sits AT the P4 preset and gets its weight from the granite palette,
		-- Deepen, a harder contrast and the warm old-torch tint)
		Mood = { Ambient = rgb(70, 62, 86), Outdoor = rgb(86, 78, 104), Brightness = -0.12, Contrast = 0.16, Tint = rgb(226, 216, 204) },
	},
}

-- the darkest a run's mood may get (the P4 dungeon preset, DungeonController PRESET / contract 5.6): BuildRun clamps every
-- tier's MoodAmbient / MoodOutdoor per channel and MoodBrightness to it
DungeonBuilder.MoodFloor = { Ambient = rgb(70, 62, 86), Outdoor = rgb(86, 78, 104), Brightness = -0.12 }

-- the look of a floor (StyleTiers; DefaultStyle outside every range)
function DungeonBuilder.StyleFor(floorIndex)
	local f = tonumber(floorIndex) or 1
	for _, tier in ipairs(DungeonBuilder.StyleTiers) do
		if f >= tier.First and f <= tier.Last and DungeonBuilder.Styles[tier.Style] then
			return tier.Style
		end
	end
	return DungeonBuilder.DefaultStyle
end

-- 0 on a tier's first floor .. 1 on its last (how far down the tier the floor is: darker, dimmer)
function DungeonBuilder.StyleDepth(floorIndex)
	local f = tonumber(floorIndex) or 1
	for _, tier in ipairs(DungeonBuilder.StyleTiers) do
		if f >= tier.First and f <= tier.Last then
			return (tier.Last > tier.First) and (f - tier.First) / (tier.Last - tier.First) or 0
		end
	end
	return 0
end

-- the style the Kit builds with right now (Template / PlaceRoom set it; nil = the lobby portal: the base look)
local Style = { Cur = nil }
local C = setmetatable({}, {
	__index = function(_, k)
		local s = Style.Cur
		local v = s and s.Palette[k]
		if v ~= nil then
			return v
		end
		return BASE[k]
	end,
})
DungeonBuilder._Style = Style

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

-- deterministic +-6 RGB shade noise (P4 Voxel.Shade spirit: big areas are never one flat colour)
local function jitter(color, seed)
	local n = (floor(seed or 0) * 7919 + 13) % 13 - 6
	local function ch(v)
		return max(0, min(255, floor(v * 255 + 0.5) + n))
	end
	return rgb(ch(color.R), ch(color.G), ch(color.B))
end

----------------------------------------------------------------------
-- Phase 6 (ARCHITECTURE_V3.md "## Phase 6" A7, owner art-arenadungeon): Blender mesh dressing. The Part build stays
-- exactly as it is (the fallback, the colliders, every name / prompt / attribute / Accent part). The reusable pieces
-- (wall runs, floor tiles, pillars, torch bodies, chests, crates, cave rocks, stalagmites, cracks, door frames) sit in
-- small wrapper Models whose PrimaryPart moves with the clone (clonePiece moves BaseParts), and are tagged with
-- MeshLibrary.Tag(target, key, look, keep): clients Dress them (Parts hidden locally, Keep parts stay: flames, bars).
-- Keys: blender/catalog/arenadungeon.json, baked by blender/kit/props/dungeon.py from this very build. A key is tagged
-- only once it has an uploaded id (MeshLibrary.Status ~= "missing": the shipped empty MeshIds change nothing) and,
-- for pieces baked from a layout (walls, floors, pillars, door frames), only while the live piece still matches the
-- manifest's "LayoutSig" (part count + position / size sums in origin space; the random protruding Bricks are not
-- counted: the mesh carries its own). Tint parts take the piece's colour (look Primary). Targets never nest.
----------------------------------------------------------------------
local Mesh = { Lib = nil, Skip = { Brick = true }, Placed = setmetatable({}, { __mode = "k" }) } -- Placed: target -> its Tag call

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

-- part count + weighted sums of the visible BaseParts' positions / sizes in `origin` space (/ scale), Skip names out
function Mesh.Signature(target, origin, scale, keep)
	local inv = origin:Inverse()
	local s = tonumber(scale) or 1
	local kept = {}
	for _, k in ipairs(keep or {}) do
		kept[k] = true
	end
	local n, a, b = 0, 0, 0
	local list = target:GetDescendants()
	list[#list + 1] = target
	for _, d in ipairs(list) do
		if d:IsA("BasePart") and d.Transparency < 0.99 and not Mesh.Skip[d.Name] and not kept[d.Name] then
			local p = inv * d.Position
			local z = d.Size
			n = n + 1
			a = a + (p.X + p.Y * 0.37 + p.Z * 0.61) / s
			b = b + (z.X + z.Y * 1.3 + z.Z * 1.7) / s
		end
	end
	return n, a, b
end

function Mesh.sigOk(ML, key, target, origin, scale, keep)
	local man = type(ML.Manifest) == "function" and ML.Manifest(key)
	if not man then
		return false
	end
	local att = man.Attachments and man.Attachments.LayoutSig
	if not att then
		return true -- a designed piece (rock, crack): no layout to match
	end
	local pos = att.Pos or att.pos
	if type(pos) ~= "table" then
		return false
	end
	local n, a, b = Mesh.Signature(target, origin, scale, keep)
	local tol = 0.05 + n * 1e-4
	return n == pos[1] and math.abs(a - pos[2]) <= tol and math.abs(b - pos[3]) <= tol
end

-- target: the piece (Model with a PrimaryPart, or one Part); origin: world CFrame of the mesh pivot; look: { Primary };
-- keep: names that stay visible; scale: uniform placement scale. Returns true when tagged.
function Mesh.tag(target, key, origin, look, keep, scale)
	if typeof(target) ~= "Instance" or typeof(origin) ~= "CFrame" then
		return false
	end
	Mesh.Placed[target] = { Key = key, Origin = origin, Look = look, Keep = keep, Scale = scale }
	local kit = DungeonBuilder._Kit
	if type(kit) == "table" and type(kit.Targets) == "table" then
		kit.Targets[#kit.Targets + 1] = { Key = key, Target = target, Origin = origin, Look = look, Keep = keep, Scale = scale }
	end
	local ML = Mesh.lib()
	if not ML or type(ML.Status) ~= "function" then
		return false
	end
	local okStatus, st = pcall(ML.Status, key)
	if not okStatus or st == "missing" or not Mesh.sigOk(ML, key, target, origin, scale, keep) then
		return false
	end
	local tagLook = {}
	for k, v in pairs(look or {}) do
		tagLook[k] = v
	end
	local pivot = target:IsA("BasePart") and target.CFrame or target:GetPivot() -- (a Part's pivot: PivotOffset is never set here)
	tagLook.Offset = pivot:Inverse() * origin
	if scale and scale ~= 1 then
		target:SetAttribute("ML_Scale", scale)
	end
	ML.Tag(target, key, tagLook, keep)
	return true
end

-- a number in a key: 15 -> "15", 15.5 -> "15p5", -6 -> "m6"
function Mesh.num(v)
	local t = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
	return (t:gsub("%-", "m"):gsub("%.", "p"))
end

-- bug #5: the key of a styled piece. The baked shell pieces (walls, floors, pillars, torches, door frames) take the
-- current style: dungeon_wall_48 -> dungeon_b_wall_48. Outside a style (a Geo build called on its own) the shell takes
-- DefaultStyle; only a torch outside a style (the lobby portal's) keeps the base key dungeon_torch.
Mesh.Styled = { wall = true, floor = true, pillar = true, torch = true, door = true }
-- the base shell keys of the lilac look (uploaded and live before bug #5): nothing tags them any more. Their manifests
-- and ids stay until the styled keys are uploaded and live (then they can be deleted: blender/catalog no longer
-- builds them); the mesh smoke skips them in its orphan check
DungeonBuilder.RetiredKeys = {}
for _, k in ipairs({ "wall_10_lite", "wall_15_lite", "wall_22_lite", "wall_24", "wall_30", "wall_30_door", "wall_30_door_lite", "wall_30_lite", "wall_48", "wall_50_door", "wall_5_lite", "wall_62_door", "wall_62_door20", "wall_72", "floor_28x22", "floor_28x24", "floor_44x48", "floor_48x48", "floor_60x72", "pillar_7", "pillar_10p5", "pillar_15", "pillar_15p5", "door_8" }) do
	DungeonBuilder.RetiredKeys["dungeon_" .. k] = true
end
function Mesh.key(base)
	local kind = string.match(base, "^dungeon_(%a+)")
	if not (kind and Mesh.Styled[kind]) then
		return base
	end
	local id = Style.Cur and Style.Cur.Id or (kind ~= "torch" and DungeonBuilder.DefaultStyle) or nil
	if id then
		return "dungeon_" .. id .. "_" .. string.sub(base, 9)
	end
	return base
end

-- a style's own designed prop: Mesh.skey("throne") -> dungeon_b_throne (DefaultStyle outside a style)
function Mesh.skey(name)
	local s = Style.Cur
	return "dungeon_" .. (s and s.Id or DungeonBuilder.DefaultStyle) .. "_" .. name
end

-- a wrapper Model for one piece (PrimaryPart set by the caller once its first part exists)
function Mesh.group(parent, name)
	local g = Instance.new("Model")
	g.Name = name
	g.Parent = parent
	return g
end
DungeonBuilder._Mesh = Mesh

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
	-- Phase 6 A1: blocks only (opts.Shape is ignored: no Cylinder / Ball) and P4 materials only
	if not P4_MATS[mat or M.Slate] then
		mat = M.Slate
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
	local tiles = Mesh.group(parent, "FloorTiles")
	for i = 1, nx do
		for j = 1, nz do
			local lift = ((i + j) % 2 == 0) and 0.05 or -0.05
			local x = -w / 2 + (i - 0.5) * tw
			local z = -d / 2 + (j - 0.5) * td
			local c = color
			if (i * 7 + j * 3 + seed) % 6 == 0 then
				c = C.FlagDark
			end
			local tile = Kit.part(tiles, CFrame.new(x, base - 0.5 + lift, z), Vector3.new(tw, 1, td), jitter(c, seed * 31 + i * 7 + j), mat or M.Cobblestone, { Name = "Floor", Collide = true })
			if not tiles.PrimaryPart then
				tiles.PrimaryPart = tile
			end
			n = n + 1
		end
	end
	Mesh.tag(tiles, Mesh.key("dungeon_floor_" .. Mesh.num(w) .. "x" .. Mesh.num(d)), CFrame.new(0, base, 0), { Primary = color, Secondary = C.Accent })
	tiles:SetAttribute("DG_Element", true) -- bug #5: the grates / joints glow in the floor's element colour
	-- cracks between the flagstones
	local r = rng(seed * 13 + 5)
	for k = 1, max(2, floor((nx * nz) / 12)) do
		local x = -w / 2 + 4 + r() * (w - 8)
		local z = -d / 2 + 4 + r() * (d - 8)
		local ccf = CFrame.new(x, base + 0.06, z) * CFrame.Angles(0, r() * PI, 0)
		local len = 2.5 + r() * 3
		local crack = Kit.part(parent, ccf, Vector3.new(len, 0.12, 0.25), C.StoneDark, M.Slate, { Name = "Crack" })
		Mesh.tag(crack, "dungeon_crack", ccf, nil, nil, len / 4)
		n = n + 1
	end
	return n
end

-- a wall of length `len` whose centre is `cf` (local X along the wall, LookVector into the room): plinth band, body,
-- cap, a few protruding stones; door = { X = offset, Width } leaves a doorway with a lintel
function Kit.wall(outer, cf, len, color, mat, seed, door, lite)
	local h = WALL_H
	local r = rng(seed)
	local parent = Mesh.group(outer, "WallRun")
	-- plinth (rule 3)
	parent.PrimaryPart = Kit.part(parent, cf * CFrame.new(0, 0.6, -0.35), Vector3.new(len, 1.2, 1.7), C.StoneDark, M.Slate, { Name = "Plinth", Collide = true })
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
	-- protruding stones (bug #5: not on the Weatherworks' riveted panels)
	-- (bug #5: one stone fewer per run: the bannered walls' new brackets and chain rods kept Treasure inside its 90)
	local n = lite and 1 or max(3, min(7, floor(len / 6)))
	if not (Style.Cur or DungeonBuilder.Styles[DungeonBuilder.DefaultStyle]).Bricks then
		n = 0
	end
	for i = 1, n do
		local x = -len / 2 + 2 + r() * (len - 4)
		local y = 1.6 + r() * (h - 4)
		if not door or abs(x - (door.X or 0)) > (door.Width or 8) / 2 + 1.2 or y > 8.5 then
			local sw = 1.8 + r() * 1.4
			local shade = (i % 3 == 0) and C.StoneDark or C.StoneLight
			Kit.part(parent, cf * CFrame.new(x, y, -0.6), Vector3.new(sw, 1.0, 0.4), jitter(shade, seed + i * 3), M.Slate, { Name = "Brick" })
		end
	end
	local key = "dungeon_wall_" .. Mesh.num(len)
	if door then
		key = key .. "_door" .. (((door.X or 0) ~= 0) and Mesh.num(door.X) or "") .. (((door.Width or 8) ~= 8) and ("w" .. Mesh.num(door.Width)) or "")
	end
	if lite then
		key = key .. "_lite"
	end
	Mesh.tag(parent, Mesh.key(key), cf, { Primary = color, Secondary = C.Accent })
	parent:SetAttribute("DG_Element", true)
	return parent
end

function Kit.pillar(outer, cf, h, color)
	local parent = Mesh.group(outer, "PillarStack")
	parent.PrimaryPart = Kit.part(parent, cf * CFrame.new(0, 0.5, 0), Vector3.new(2.6, 1, 2.6), C.StoneDark, M.Slate, { Name = "PillarBase", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(2, h, 2), color or C.Stone, M.Slate, { Name = "Pillar", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, h - 0.4, 0), Vector3.new(2.6, 0.8, 2.6), C.StoneDark, M.Slate, { Name = "PillarCap" })
	Mesh.tag(parent, Mesh.key("dungeon_pillar_" .. Mesh.num(h)), cf, { Primary = color or C.Stone, Secondary = C.Accent })
	parent:SetAttribute("DG_Element", true)
	return parent
end

-- a wall torch: cf = the mount point on the wall face (LookVector into the room)
function Kit.torch(outer, cf, bright)
	local parent = Mesh.group(outer, "WallTorch")
	parent.PrimaryPart = Kit.part(parent, cf * CFrame.new(0, 0.6, -0.1), Vector3.new(1.2, 2.2, 0.2), C.Iron, M.Metal, { Name = "Sconce" })
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
	Mesh.tag(parent, Mesh.key("dungeon_torch"), cf, nil, { "Flame" })
	Kit.sound(parent, "torch")
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
	door.PrimaryPart = door:FindFirstChild("Lintel")
	door.Parent = parent
	-- the frame (jambs + lintel) is the mesh; the Bars stay Parts (SetDoor flips them on the server)
	Mesh.tag(door, Mesh.key("dungeon_door_" .. Mesh.num(w)), cf, nil, { "Bar" })
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

-- the "Enter" prompt of a door (dungeon-fixes decision 2): an invisible anchored point a little in front of the bars with
-- a ProximityPrompt EnterPrompt (E, no hold, no line of sight, 10 studs, DungeonAction "Enter"), DISABLED: DungeonService
-- enables it only while the group may move on and handles the press in its PromptTriggered (nothing new from the client)
function Kit.enterPrompt(parent, cf, objectText, targetRoom)
	local point = Instance.new("Part")
	point.Name = "EnterPoint"
	point.Anchored = true
	point.CanCollide = false
	point.CanQuery = false
	point.CanTouch = false
	point.CastShadow = false
	point.Transparency = 1
	point.Material = Enum.Material.SmoothPlastic
	point.Size = Vector3.new(1, 1, 1)
	point.CFrame = cf
	point:SetAttribute("DungeonAction", "Enter")
	point:SetAttribute("TargetRoom", targetRoom)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Enter"
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("DungeonAction", "Enter")
	prompt:SetAttribute("TargetRoom", targetRoom)
	prompt.Parent = point
	point.Parent = parent
	return prompt, point
end

local function enterLabel(targetRoom)
	if targetRoom >= 5 then
		return "Treasure"
	elseif targetRoom == 4 then
		return "Boss room"
	end
	return "Room " .. tostring(targetRoom)
end

-- bug batch 2 (#19): the ceiling collides (CanCollide + CanQuery), so Roblox's camera occlusion (Poppercam only stops at
-- colliding, queryable parts) keeps the camera under it: with the dungeon zoom cap of 14 a steep downward look used to
-- lift the camera 18 studs up, through the 16-stud ceiling, above the pocket (nobody can jump that high)
function Kit.ceiling(parent, w, d, y)
	Kit.part(parent, CFrame.new(0, (y or CEIL_Y) + 0.5, 0), Vector3.new(w + 2, 1, d + 2), C.Ceiling, M.Slate, { Name = "Ceiling", Collide = true })
end

-- bug #5 (art rule: every visible piece is a Blender mesh): a prop's Part build sits in its own wrapper Model and is
-- dressed by `key` (pivot = the Tag origin `cf`); the Parts stay as the collider and the fallback. element = true: the
-- key's Secondary tint takes the floor's element colour (PlaceRoom). Shared keys (one look for every style: barrel,
-- table, hay, bench, cauldron, shield, candles, chandelier, hearth, rug, wine rack, weapon rack) are dungeon_<name>;
-- style keys (throne, dais, carpet, arch, statue, brazier, banner, curio ...) dungeon_<style>_<name> (Mesh.skey).
function Kit.dress(group, key, cf, look, keep, scale, element)
	if not group.PrimaryPart then
		for _, d in ipairs(group:GetChildren()) do
			if d:IsA("BasePart") then
				group.PrimaryPart = d
				break
			end
		end
	end
	Mesh.tag(group, key, cf, look, keep, scale)
	if element then
		group:SetAttribute("DG_Element", true)
	end
	return group
end

-- bug #5: the dungeon's sound sources, tagged for the audio branch (no playback here): CollectionService tag
-- DungeonBuilder.SoundTag on the instance + attribute DungeonSound = the kind ("torch", "brazier_<style>",
-- "astrolabe", "curio_<style>", "weather_<element>")
DungeonBuilder.SoundTag = "NC_DungeonSound"
function Kit.sound(inst, kind)
	CollectionService:AddTag(inst, DungeonBuilder.SoundTag)
	inst:SetAttribute("DungeonSound", kind)
	return inst
end

-- props (pure decor sits in one NC_Detail model per room)
-- bug #5 review: the Weatherworks (b) is a guild workshop, not the castle cellar; its rooms swap the cellar leftovers
-- for its own honest pieces (placement only, no new keys): barrel / hay -> a supply crate, the wine rack -> a stand-pipe
-- with its red valve wheel against the wall (the b curio), the cauldron -> a condenser coil (the b brazier)
local function machineHall()
	return Style.Cur ~= nil and Style.Cur.Id == "b"
end
DungeonBuilder.B_SWAPS = { BarrelSet = "CrateBox", HayBale = "CrateBox", WineRackSet = "CurioSet", CauldronSet = "BrazierSet" }

function Kit.barrel(outer, cf)
	if machineHall() then
		return Kit.crate(outer, cf, 2.6)
	end
	local parent = Mesh.group(outer, "BarrelSet")
	local up = CFrame.Angles(0, 0, PI / 2)
	Kit.part(parent, cf * CFrame.new(0, 1.6, 0) * up, Vector3.new(3.2, 2.8, 2.8), C.Wood, M.Wood, { Name = "Barrel", Shape = Enum.PartType.Cylinder, Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 0.7, 0) * up, Vector3.new(0.25, 2.95, 2.95), C.Iron, M.Metal, { Name = "Band", Shape = Enum.PartType.Cylinder })
	Kit.part(parent, cf * CFrame.new(0, 2.5, 0) * up, Vector3.new(0.25, 2.95, 2.95), C.Iron, M.Metal, { Name = "Band", Shape = Enum.PartType.Cylinder })
	return Kit.dress(parent, "dungeon_barrel", cf)
end

function Kit.crate(outer, cf, s)
	s = s or 3
	local parent = Mesh.group(outer, "CrateBox")
	parent.PrimaryPart = Kit.part(parent, cf * CFrame.new(0, s / 2, 0), Vector3.new(s, s, s), C.Plank, M.WoodPlanks, { Name = "Crate", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, s / 2, s / 2 + 0.05), Vector3.new(s * 0.9, 0.3, 0.1), C.Wood, M.Wood, { Name = "Slat" })
	Kit.part(parent, cf * CFrame.new(0, s / 2, -s / 2 - 0.05), Vector3.new(s * 0.9, 0.3, 0.1), C.Wood, M.Wood, { Name = "Slat" })
	Mesh.tag(parent, "dungeon_crate", cf, nil, nil, s / 3)
	return parent
end

-- a chain hanging from the ceiling (bug #5: the three links used to hang in mid-air; a rod now reaches the ceiling
-- slab). Shared key dungeon_chain (pivot = the top link; the rod's length is the room's, so no LayoutSig on the rod:
-- the key covers the links and a ceiling staple, the rod stays a Part)
function Kit.chain(outer, cf)
	local parent = Mesh.group(outer, "ChainHang")
	for i = 0, 2 do
		Kit.part(parent, cf * CFrame.new((i % 2) * 0.2 - 0.1, -i * 0.9, 0), Vector3.new(0.35, 1, 0.2), C.Iron, M.Metal, { Name = "Chain" })
	end
	local top = cf.Position.Y + 0.5
	local len = max(0.2, CEIL_Y - top)
	Kit.part(outer, CFrame.new(cf.Position.X, top + len / 2, cf.Position.Z), Vector3.new(0.2, len, 0.2), C.Iron, M.Metal, { Name = "ChainRod" })
	return Kit.dress(parent, "dungeon_chain", cf)
end

function Kit.puddle(parent, cf, w, d)
	Kit.part(parent, cf * CFrame.new(0, 0.07, 0), Vector3.new(w or 4, 0.14, d or 3), C.Puddle, M.Glass, { Name = "Puddle", Transparency = 0.35, Accent = true })
end

function Kit.moss(parent, cf, w, d)
	Kit.part(parent, cf * CFrame.new(0, 0.1, 0), Vector3.new(w or 3, 0.2, d or 2), C.Moss, M.Grass, { Name = "Moss" })
end

function Kit.hay(outer, cf)
	if machineHall() then
		-- (a long low crate pair over the bale's footprint: the 1.1 step rule is kept by the crates' own colliders)
		Kit.crate(outer, cf * CFrame.new(-0.9, 0, 0), 2.4)
		return Kit.crate(outer, cf * CFrame.new(1.3, 0, 0.3) * CFrame.Angles(0, 0.3, 0), 1.6)
	end
	local parent = Mesh.group(outer, "HayBale")
	-- bug batch 2 (#3): the bale collides (a 1.1 step, like the wall plinth): no wading through it
	Kit.part(parent, cf * CFrame.new(0, 0.55, 0), Vector3.new(4.4, 1.1, 3.6), C.Hay, M.Sand, { Name = "Hay", Collide = true })
	Kit.part(parent, cf * CFrame.new(0.5, 1.35, -0.3) * CFrame.Angles(0, 0.4, 0), Vector3.new(2.6, 0.6, 2), C.Hay, M.Sand, { Name = "Hay" })
	return Kit.dress(parent, "dungeon_hay", cf)
end

function Kit.table(outer, cf)
	local parent = Mesh.group(outer, "TableSet")
	Kit.part(parent, cf * CFrame.new(0, 2.5, 0), Vector3.new(7, 0.45, 3), C.Plank, M.WoodPlanks, { Name = "TableTop", Collide = true })
	Kit.part(parent, cf * CFrame.new(-2.8, 1.15, 0), Vector3.new(0.6, 2.3, 2.4), C.Wood, M.Wood, { Name = "TableLeg" })
	Kit.part(parent, cf * CFrame.new(2.8, 1.15, 0), Vector3.new(0.6, 2.3, 2.4), C.Wood, M.Wood, { Name = "TableLeg" })
	Kit.part(parent, cf * CFrame.new(-1.6, 3.0, 0.4), Vector3.new(0.9, 0.6, 0.9), C.Gold, M.Metal, { Name = "Cup" })
	Kit.part(parent, cf * CFrame.new(1.4, 2.9, -0.5), Vector3.new(1.6, 0.3, 1.2), C.Bone, M.Marble, { Name = "Plate" })
	return Kit.dress(parent, "dungeon_table", cf)
end

function Kit.bench(outer, cf)
	local parent = Mesh.group(outer, "BenchSet")
	Kit.part(parent, cf * CFrame.new(0, 1.3, 0), Vector3.new(6, 0.4, 1.4), C.Plank, M.WoodPlanks, { Name = "Bench", Collide = true })
	Kit.part(parent, cf * CFrame.new(-2.4, 0.55, 0), Vector3.new(0.5, 1.1, 1.2), C.Wood, M.Wood, { Name = "BenchLeg" })
	Kit.part(parent, cf * CFrame.new(2.4, 0.55, 0), Vector3.new(0.5, 1.1, 1.2), C.Wood, M.Wood, { Name = "BenchLeg" })
	return Kit.dress(parent, "dungeon_bench", cf)
end

function Kit.bones(parent, cf)
	if machineHall() then
		-- (fix round, Gemini: bones read as crypt leftovers in a workshop) a dropped copper pipe offcut and a brass nut
		Kit.part(parent, cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0.5, 0), Vector3.new(2.2, 0.35, 0.35), rgb(70, 168, 140), M.Metal, { Name = "PipeOffcut" })
		Kit.part(parent, cf * CFrame.new(0.8, 0.12, 0.6) * CFrame.Angles(0, -0.9, 0), Vector3.new(0.5, 0.24, 0.5), C.Gold, M.Metal, { Name = "Nut" })
		return
	end
	Kit.part(parent, cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0.5, 0), Vector3.new(2.2, 0.35, 0.35), C.Bone, M.Marble, { Name = "Bone" })
	Kit.part(parent, cf * CFrame.new(0.8, 0.2, 0.6) * CFrame.Angles(0, -0.9, 0), Vector3.new(1.6, 0.3, 0.3), C.Bone, M.Marble, { Name = "Bone" })
end

-- a hanging banner (Accent: recoloured to the floor's element) ON the wall face (bug #5: cf = the face itself; the pole
-- and the cloth hang 0.3 out, clear of the 0.11-stud mortar courses, held by two iron brackets; they used to float ~0.9
-- stud off the wall with nothing holding them). Style key dungeon_<s>_banner (its stripe = the element: Secondary)
function Kit.banner(outer, cf)
	local parent = Mesh.group(outer, "BannerHang")
	Kit.part(parent, cf * CFrame.new(0, 0, -0.3), Vector3.new(4.4, 0.3, 0.3), C.Wood, M.Wood, { Name = "BannerPole" })
	Kit.part(parent, cf * CFrame.new(-1.8, 0, -0.15), Vector3.new(0.3, 0.3, 0.3), C.Iron, M.Metal, { Name = "BannerBracket" })
	Kit.part(parent, cf * CFrame.new(1.8, 0, -0.15), Vector3.new(0.3, 0.3, 0.3), C.Iron, M.Metal, { Name = "BannerBracket" })
	Kit.part(parent, cf * CFrame.new(0, -2.8, -0.3), Vector3.new(3.6, 5.4, 0.25), C.Accent, M.Fabric, { Name = "Banner", Accent = true })
	return Kit.dress(parent, Mesh.skey("banner"), cf, { Secondary = C.Accent }, nil, nil, true)
end

-- a thin Neon rune inlay in the floor (Accent)
function Kit.rune(parent, cf, w, d)
	Kit.part(parent, cf * CFrame.new(0, 0.08, 0), Vector3.new(w or 3, 0.16, d or 0.6), C.Accent, M.Neon, { Name = "Rune", Accent = true })
end

-- an arch over the aisle: two pillar stacks (their own pillar keys) + the top. bug #5: the lintel, the two diagonal
-- ArchStones and the keystone are one style key dungeon_<s>_arch_<width> (a pointed granite arch (a), a riveted
-- storm-blue girder with a weathervane (b), two woven roots (c))
function Kit.arch(parent, cf, width, height)
	local w, h = width or 10, height or 11
	Kit.pillar(parent, cf * CFrame.new(-w / 2 - 1, 0, 0), h - 2, C.StoneLight)
	Kit.pillar(parent, cf * CFrame.new(w / 2 + 1, 0, 0), h - 2, C.StoneLight)
	local top = Mesh.group(parent, "ArchTop")
	Kit.part(top, cf * CFrame.new(0, h - 0.6, 0), Vector3.new(w + 4.6, 1.2, 2.2), C.StoneLight, M.Slate, { Name = "ArchLintel" })
	Kit.part(top, cf * CFrame.new(-w / 2 + 0.6, h - 2.2, 0) * CFrame.Angles(0, 0, 0.75), Vector3.new(2, 1, 2), C.StoneLight, M.Slate, { Name = "ArchStone" })
	Kit.part(top, cf * CFrame.new(w / 2 - 0.6, h - 2.2, 0) * CFrame.Angles(0, 0, -0.75), Vector3.new(2, 1, 2), C.StoneLight, M.Slate, { Name = "ArchStone" })
	Kit.part(top, cf * CFrame.new(0, h + 0.6, 0), Vector3.new(4, 1.2, 2.4), C.Stone, M.Slate, { Name = "Keystone" })
	Kit.dress(top, Mesh.skey("arch_" .. Mesh.num(w)), cf, { Secondary = C.Accent }, nil, nil, true)
end

function Kit.stairs(parent, cf, width, steps, rise)
	local depth = 1.6
	for i = 1, steps do
		Kit.part(parent, cf * CFrame.new(0, (i - 0.5) * rise, (i - 0.5) * depth), Vector3.new(width, rise, depth), jitter(C.StoneLight, i * 11), M.Slate, { Name = "Step", Collide = true })
	end
end

-- bug batch 2 (#3): an invisible collider around the foot, stem and bowl (the flame stays above it). bug #5: the style
-- key dungeon_<s>_brazier (an iron brazier on a tripod (a), a copper condenser coil round a cyan core (b), a glowing
-- pitcher plant (c)); the flame stays a Neon Part in the style's Core colour
function Kit.brazier(outer, cf)
	local parent = Mesh.group(outer, "BrazierSet")
	Kit.part(parent, cf * CFrame.new(0, 1.8, 0), Vector3.new(3.2, 3.6, 3.2), C.Iron, M.Metal, { Name = "BrazierCollider", Collide = true, Transparency = 1 })
	Kit.part(parent, cf * CFrame.new(0, 0.3, 0), Vector3.new(2, 0.6, 2), C.Iron, M.Metal, { Name = "BrazierFoot" })
	Kit.part(parent, cf * CFrame.new(0, 1.6, 0), Vector3.new(0.5, 2, 0.5), C.Iron, M.Metal, { Name = "BrazierStem" })
	Kit.part(parent, cf * CFrame.new(0, 3.0, 0) * CFrame.Angles(0, 0, PI / 2), Vector3.new(1.1, 3.2, 3.2), C.Iron, M.Metal, { Name = "BrazierBowl", Shape = Enum.PartType.Cylinder })
	local flame = Kit.part(parent, cf * CFrame.new(0, 4.3, 0), Vector3.new(1.8, 1.8, 1.8), C.Core, M.Neon, { Name = "BrazierFlame" })
	local light = Instance.new("PointLight")
	light.Name = "BrazierLight"
	light.Color = C.CoreLight
	light.Brightness = 1.4
	light.Range = 18
	light.Shadows = false
	light.Parent = flame
	Kit.sound(parent, "brazier_" .. (Style.Cur and Style.Cur.Id or DungeonBuilder.DefaultStyle))
	return Kit.dress(parent, Mesh.skey("brazier"), cf, nil, { "BrazierFlame" })
end

function Kit.rock(parent, cf, size, seed)
	local r = rng(seed)
	local rock = Kit.part(parent, cf * CFrame.Angles((r() - 0.5) * 0.4, (r() - 0.5) * 0.6, (r() - 0.5) * 0.4), size, jitter((r() > 0.5) and C.Rock or C.RockDark, seed), M.Slate, { Name = "Rock", Collide = true })
	-- a real voxel rock (3 shapes) upright at the box's centre, sized to the box's volume (the tilted box stays the collider)
	local vol = (size.X * size.Y * size.Z) ^ (1 / 3)
	local thin = min(size.X, size.Y, size.Z)
	local shape = (floor(seed or 0) % 3) + 1
	Mesh.tag(rock, "dungeon_rock_" .. shape, cf * CFrame.new(0, -size.Y / 2, 0), { Primary = rock.Color }, nil, min(vol, thin * 1.3) / 4)
	return rock
end

function Kit.stalagmite(outer, cf, h)
	h = h or 4
	local parent = Mesh.group(outer, "StalagmiteStack")
	-- bug batch 2 (#3): every tier collides (standing on the base used to put the player inside the upper tiers)
	parent.PrimaryPart = Kit.part(parent, cf * CFrame.new(0, h * 0.2, 0) * CFrame.Angles(0, 0.4, 0), Vector3.new(2.6, h * 0.4, 2.6), C.RockDark, M.Slate, { Name = "Stalagmite", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, h * 0.55, 0) * CFrame.Angles(0, 0.8, 0), Vector3.new(1.6, h * 0.35, 1.6), C.Rock, M.Slate, { Name = "Stalagmite", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, h * 0.85, 0), Vector3.new(0.7, h * 0.3, 0.7), C.Rock, M.Slate, { Name = "Stalagmite", Collide = true })
	Mesh.tag(parent, "dungeon_stalagmite", cf, nil, nil, h / 4)
	return parent
end

-- a cobweb in a ceiling corner: cf = the corner at the ceiling, LookVector along one wall
function Kit.cobweb(parent, cf)
	Kit.part(parent, cf * CFrame.new(1.4, -0.3, -1.4) * CFrame.Angles(0, PI / 4, 0), Vector3.new(4, 0.1, 0.1), C.Marble, M.Glass, { Name = "Web", Transparency = 0.45 })
	Kit.part(parent, cf * CFrame.new(1.0, -1.1, -1.0) * CFrame.Angles(0, PI / 4, 0), Vector3.new(2.8, 0.1, 0.1), C.Marble, M.Glass, { Name = "Web", Transparency = 0.5 })
	Kit.part(parent, cf * CFrame.new(0.5, -2.0, -0.5) * CFrame.Angles(0, PI / 4, 0), Vector3.new(1.4, 0.1, 0.1), C.Marble, M.Glass, { Name = "Web", Transparency = 0.55 })
end

function Kit.skulls(parent, cf)
	if machineHall() then
		-- (fix round, Gemini: a skull pile is a crypt leftover in a workshop) a riveted toolbox and a dropped spanner
		Kit.part(parent, cf * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.6, 0.8, 0.8), C.StoneDark, M.Metal, { Name = "Toolbox" })
		Kit.part(parent, cf * CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.0, 0.1, 0.2), C.Gold, M.Metal, { Name = "ToolboxHandle" })
		Kit.part(parent, cf * CFrame.new(-0.9, 0.08, 0.6) * CFrame.Angles(0, 1.1, 0), Vector3.new(1.4, 0.16, 0.3), C.Iron, M.Metal, { Name = "Spanner" })
		return
	end
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

-- a weapon rack ON a wall face (cf on the face, LookVector into the room); bug batch 2 (#3): one invisible collider over
-- the whole rack (wall face to the front of the foot, up past the spear heads), so nobody stands in the spears
function Kit.rack(outer, cf)
	local parent = Mesh.group(outer, "RackSet")
	Kit.part(parent, cf * CFrame.new(0, 2.15, -0.55), Vector3.new(4.2, 4.3, 1.1), C.Wood, M.Wood, { Name = "RackCollider", Collide = true, Transparency = 1 })
	Kit.part(parent, cf * CFrame.new(0, 1.6, -0.15), Vector3.new(4, 3.2, 0.3), C.Wood, M.Wood, { Name = "RackBack" })
	Kit.part(parent, cf * CFrame.new(0, 0.3, -0.4), Vector3.new(4.2, 0.6, 0.8), C.Wood, M.Wood, { Name = "RackFoot" })
	for i = -1, 1 do
		Kit.part(parent, cf * CFrame.new(i * 1.2, 2.0, -0.45), Vector3.new(0.25, 3.4, 0.25), C.Iron, M.Metal, { Name = "Spear" })
		Kit.part(parent, cf * CFrame.new(i * 1.2, 3.8, -0.45), Vector3.new(0.5, 0.9, 0.15), C.Marble, M.Metal, { Name = "SpearHead" })
	end
	return Kit.dress(parent, "dungeon_rack", cf)
end

function Kit.cauldron(outer, cf)
	if machineHall() then
		return Kit.brazier(outer, cf)
	end
	local parent = Mesh.group(outer, "CauldronSet")
	Kit.part(parent, cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, PI / 2), Vector3.new(0.6, 2.4, 2.4), C.Iron, M.Metal, { Name = "CauldronFoot", Shape = Enum.PartType.Cylinder })
	Kit.part(parent, cf * CFrame.new(0, 1.8, 0), Vector3.new(3.2, 3.2, 3.2), C.Iron, M.Metal, { Name = "Cauldron", Shape = Enum.PartType.Ball, Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0, PI / 2), Vector3.new(0.3, 2.6, 2.6), C.Moss, M.Neon, { Name = "Brew", Shape = Enum.PartType.Cylinder, Accent = true })
	return Kit.dress(parent, "dungeon_cauldron", cf, nil, { "Brew" })
end

-- a wall emblem ON the wall face: a shield with crossed swords (bug #5: a bracket holds it, the plate sits 0.12 out,
-- clear of the courses; it used to float 0.75 stud off the wall). Shared key dungeon_shield (crest = the element)
function Kit.shield(outer, cf)
	local parent = Mesh.group(outer, "ShieldMount")
	Kit.part(parent, cf * CFrame.new(0, 0, -0.27), Vector3.new(2.6, 3.2, 0.3), C.Iron, M.Metal, { Name = "Shield" })
	Kit.part(parent, cf * CFrame.new(0, 0.4, -0.06), Vector3.new(0.8, 0.8, 0.12), C.Iron, M.Metal, { Name = "ShieldBracket" })
	Kit.part(parent, cf * CFrame.new(0, 0, -0.47), Vector3.new(1.6, 2, 0.15), C.Accent, M.Fabric, { Name = "ShieldCrest", Accent = true })
	Kit.part(parent, cf * CFrame.new(0, 0, -0.62) * CFrame.Angles(0, 0, 0.75), Vector3.new(4, 0.25, 0.2), C.Gold, M.Metal, { Name = "Sword" })
	Kit.part(parent, cf * CFrame.new(0, 0, -0.62) * CFrame.Angles(0, 0, -0.75), Vector3.new(4, 0.25, 0.2), C.Gold, M.Metal, { Name = "Sword" })
	return Kit.dress(parent, "dungeon_shield", cf, { Secondary = C.Accent }, nil, nil, true)
end

-- a guardian statue on a plinth; bug batch 2 (#3): an invisible collider from the plinth top past the spear tip (arms,
-- head and spear stick out of the body: standing on the plinth put the player inside them). bug #5: the style key
-- dungeon_<s>_statue (a hooded stone warden (a), a retired weather robot (b), a hedge knight in a planter (c))
function Kit.statue(outer, cf)
	local parent = Mesh.group(outer, "StatueSet")
	Kit.part(parent, cf * CFrame.new(0, 4.2, 0), Vector3.new(3.2, 6, 3.2), C.StoneLight, M.Marble, { Name = "StatueCollider", Collide = true, Transparency = 1 })
	Kit.part(parent, cf * CFrame.new(0, 0.6, 0), Vector3.new(3, 1.2, 3), C.StoneDark, M.Slate, { Name = "StatueBase", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 3.2, 0), Vector3.new(1.8, 4, 1.4), C.StoneLight, M.Marble, { Name = "StatueBody", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 5.8, 0), Vector3.new(1.2, 1.2, 1.2), C.StoneLight, M.Marble, { Name = "StatueHead" })
	Kit.part(parent, cf * CFrame.new(-1.3, 3.6, 0), Vector3.new(0.6, 2.6, 0.6), C.StoneLight, M.Marble, { Name = "StatueArm" })
	Kit.part(parent, cf * CFrame.new(1.3, 4.0, -0.4) * CFrame.Angles(0.5, 0, 0), Vector3.new(0.6, 2.6, 0.6), C.StoneLight, M.Marble, { Name = "StatueArm" })
	Kit.part(parent, cf * CFrame.new(1.3, 5.4, -1.2), Vector3.new(0.3, 3.4, 0.3), C.Iron, M.Metal, { Name = "StatueSpear" })
	return Kit.dress(parent, Mesh.skey("statue"), cf, { Secondary = C.Accent }, nil, nil, true)
end

function Kit.candles(outer, cf)
	local parent = Mesh.group(outer, "CandleSet")
	for i = -1, 1 do
		Kit.part(parent, cf * CFrame.new(i * 0.7, 0.35, 0), Vector3.new(0.3, 0.7, 0.3), C.Marble, M.Marble, { Name = "Candle" })
		Kit.part(parent, cf * CFrame.new(i * 0.7, 0.85, 0), Vector3.new(0.25, 0.3, 0.25), C.Flame, M.Neon, { Name = "CandleFlame" })
	end
	return Kit.dress(parent, "dungeon_candles", cf, nil, { "CandleFlame" })
end

-- a chandelier hanging from the ceiling (cf = the ceiling point)
function Kit.chandelier(outer, cf)
	local parent = Mesh.group(outer, "ChandelierSet")
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
	return Kit.dress(parent, "dungeon_chandelier", cf, nil, { "CandleFlame" })
end

-- a hearth ON a wall face (cf on the face at floor level, LookVector into the room); bug batch 2 (#3): an invisible
-- collider fills the fire opening between the sides (the back, the log and the flame), so nobody walks into the fire
function Kit.hearth(outer, cf)
	local parent = Mesh.group(outer, "HearthSet")
	Kit.part(parent, cf * CFrame.new(0, 2.6, -0.9), Vector3.new(5, 5.2, 1.8), C.Ceiling, M.Slate, { Name = "HearthCollider", Collide = true, Transparency = 1 })
	Kit.part(parent, cf * CFrame.new(-3.2, 2.6, -0.9), Vector3.new(1.4, 5.2, 1.8), C.StoneDark, M.Slate, { Name = "HearthSide", Collide = true })
	Kit.part(parent, cf * CFrame.new(3.2, 2.6, -0.9), Vector3.new(1.4, 5.2, 1.8), C.StoneDark, M.Slate, { Name = "HearthSide", Collide = true })
	Kit.part(parent, cf * CFrame.new(0, 5.6, -0.9), Vector3.new(7.8, 0.8, 2), C.StoneDark, M.Slate, { Name = "Mantle" })
	Kit.part(parent, cf * CFrame.new(0, 2.6, -0.25), Vector3.new(5, 5.2, 0.5), C.Ceiling, M.Slate, { Name = "HearthBack" })
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
	return Kit.dress(parent, "dungeon_hearth", cf, nil, { "HearthFlame" })
end

function Kit.rug(outer, cf, w, d)
	local parent = Mesh.group(outer, "RugSet")
	Kit.part(parent, cf * CFrame.new(0, 0.07, 0), Vector3.new(w or 8, 0.14, d or 6), C.Carpet, M.Fabric, { Name = "Rug" })
	Kit.part(parent, cf * CFrame.new(0, 0.15, 0), Vector3.new((w or 8) - 1.6, 0.06, (d or 6) - 1.6), C.Accent, M.Fabric, { Name = "RugInlay", Accent = true })
	return Kit.dress(parent, "dungeon_rug_" .. Mesh.num(w or 8) .. "x" .. Mesh.num(d or 6), cf, { Primary = C.Carpet, Secondary = C.Accent }, nil, nil, true)
end

-- a wine rack ON a wall face (cf on the face, LookVector into the room; bug #5: it stood 0.7 stud off the wall)
function Kit.wineRack(outer, cf)
	if machineHall() then
		-- the curio's pipe stands 1 stud off the face (its box reaches back to the wall)
		return Kit.curio(outer, cf * CFrame.new(0, 0, -1.0))
	end
	local parent = Mesh.group(outer, "WineRackSet")
	Kit.part(parent, cf * CFrame.new(0, 2, -0.9), Vector3.new(5, 4, 1.8), C.Wood, M.Wood, { Name = "WineRack", Collide = true })
	for i = -1, 1 do
		for j = 0, 1 do
			Kit.part(parent, cf * CFrame.new(i * 1.5, 1.1 + j * 1.8, -1.95) * CFrame.Angles(PI / 2, 0, 0), Vector3.new(0.6, 0.6, 0.6), C.Moss, M.Glass, { Name = "Bottle", Shape = Enum.PartType.Cylinder })
		end
	end
	return Kit.dress(parent, "dungeon_winerack", cf)
end

-- bug #5 fix 4: the throne room's own clutter instead of the cellar's hay, barrel, crate and table: a style "curio"
-- (the people who use the place): a journal + a half-melted candle on a lectern (a), a stand-pipe with a red valve
-- wheel, a wrench and a mug (b), a cracked pot, a watering can and a spilled seed packet (c). Parts: a block + two
-- small pieces (the collider is the block)
function Kit.curio(outer, cf)
	local parent = Mesh.group(outer, "CurioSet")
	local s = Style.Cur and Style.Cur.Id or DungeonBuilder.DefaultStyle
	if s == "b" then
		Kit.part(parent, cf * CFrame.new(0, 0.8, 0.6), Vector3.new(2.4, 1.6, 1.6), C.StoneDark, M.Metal, { Name = "CurioBox", Collide = true })
		Kit.part(parent, cf * CFrame.new(-0.6, 2.4, -0.6), Vector3.new(0.6, 4.8, 0.6), C.Gold, M.Metal, { Name = "CurioPipe", Collide = true })
		Kit.part(parent, cf * CFrame.new(-0.6, 3.4, -1.0), Vector3.new(1.8, 1.8, 0.2), rgb(196, 44, 44), M.Metal, { Name = "CurioWheel" })
	elseif s == "a" then
		Kit.part(parent, cf * CFrame.new(0, 1.6, 0), Vector3.new(2.2, 3.2, 1.6), C.Wood, M.Wood, { Name = "CurioBox", Collide = true })
		Kit.part(parent, cf * CFrame.new(0, 3.3, -0.1), Vector3.new(1.8, 0.2, 1.3), C.Marble, M.Fabric, { Name = "CurioBook" })
		Kit.part(parent, cf * CFrame.new(0.7, 3.6, 0.4), Vector3.new(0.35, 0.5, 0.35), C.Marble, M.Marble, { Name = "CurioCandle" })
	else
		Kit.part(parent, cf * CFrame.new(0, 0.8, 0), Vector3.new(1.8, 1.6, 1.8), C.Stone, M.Slate, { Name = "CurioBox", Collide = true })
		Kit.part(parent, cf * CFrame.new(1.7, 0.6, -0.4), Vector3.new(1.4, 1.2, 0.9), rgb(120, 150, 176), M.Metal, { Name = "CurioCan" })
		Kit.part(parent, cf * CFrame.new(-1.0, 0.05, -1.3), Vector3.new(1.6, 0.1, 1.2), C.Moss, M.Fabric, { Name = "CurioSeeds" })
	end
	Kit.sound(parent, "curio_" .. s)
	return Kit.dress(parent, Mesh.skey("curio"), cf)
end

function Kit.chest(outer, cf, slot)
	local parent = Mesh.group(outer, "ChestBox")
	local body = Kit.part(parent, cf * CFrame.new(0, 0.9, 0), Vector3.new(3, 1.8, 2), C.Plank, M.WoodPlanks, { Name = "Chest", Collide = true })
	parent.PrimaryPart = body
	Kit.part(parent, cf * CFrame.new(0, 2.05, 0), Vector3.new(3.1, 0.5, 2.1), C.Wood, M.Wood, { Name = "ChestLid" })
	Kit.part(parent, cf * CFrame.new(0, 1.0, 1.05), Vector3.new(0.6, 0.6, 0.15), C.Gold, M.Metal, { Name = "ChestLock" })
	body:SetAttribute("ChestSlot", slot)
	-- bug batch 2 #14: each member picks ONE chest by walking to it (DungeonService reads the prompt's ChestSlot, checks
	-- the range and turns the prompt off for everyone once taken); 7 studs so the chests 6 apart do not overlap much
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChestPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Pick ONE chest"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("DungeonAction", "Chest")
	prompt:SetAttribute("ChestSlot", slot)
	prompt.Parent = body
	Mesh.tag(parent, "dungeon_chest", cf)
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
		Kit.torch(model, CFrame.new(-hw, 6.5, z) * CFrame.Angles(0, -PI / 2, 0))
		Kit.torch(model, CFrame.new(hw, 6.5, z) * CFrame.Angles(0, PI / 2, 0))
	end
	Kit.torch(model, CFrame.new(-doorW / 2 - 3, 7, -hd) * CFrame.Angles(0, PI, 0))
	Kit.torch(model, CFrame.new(doorW / 2 + 3, 7, -hd) * CFrame.Angles(0, PI, 0))
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
		Kit.banner(detail, CFrame.new(x, 11, -24) * CFrame.Angles(0, PI, 0))
		Kit.banner(detail, CFrame.new(x, 11, 24))
	end
	Kit.shield(detail, CFrame.new(0, 9, 24))
	Kit.rack(detail, CFrame.new(24, 0, -6) * CFrame.Angles(0, PI / 2, 0))
	Kit.chandelier(model, CFrame.new(0, CEIL_Y, 0))
	Kit.hearth(model, CFrame.new(24, 0, 10) * CFrame.Angles(0, PI / 2, 0))
	Kit.rug(detail, CFrame.new(0, 0, -14), 10, 7)
	Kit.skulls(detail, CFrame.new(-21, 0, -8))
	Kit.rubble(detail, CFrame.new(12, 0, 20), seed + 7)
	-- bug batch 2 (#25): no table on the door axis (6 studs either side of the doors' centre line stay clear: the smoke
	-- bug2dgn_doorlanes); the candles stand on a table in every variant (they floated in mid-air in Hall_2 / Hall_3)
	if variant == 1 then
		Kit.table(detail, CFrame.new(-18, 0, 14))
		Kit.candles(detail, CFrame.new(-18, 2.5, 14))
		Kit.bench(detail, CFrame.new(-18, 0, 11.4))
		Kit.crate(detail, CFrame.new(20, 0, -18))
		Kit.crate(detail, CFrame.new(20, 2.4, -18), 1.8)
		Kit.barrel(detail, CFrame.new(17.5, 0, -17.5))
		Kit.hay(detail, CFrame.new(20, 0, 16))
		Kit.puddle(detail, CFrame.new(6, 0, -14), 5, 3.5)
		Kit.rack(detail, CFrame.new(-24, 0, 6) * CFrame.Angles(0, -PI / 2, 0))
	elseif variant == 2 then
		Kit.table(detail, CFrame.new(18, 0, -12))
		Kit.table(detail, CFrame.new(18, 0, 16))
		Kit.candles(detail, CFrame.new(18, 2.5, 16))
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
		Kit.table(detail, CFrame.new(-18, 0, 14)) -- was (0, 0, 19): right in front of the exit door (#25)
		Kit.candles(detail, CFrame.new(-18, 2.5, 14))
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
	Kit.wineRack(detail, CFrame.new(24, 0, 12) * CFrame.Angles(0, PI / 2, 0))
	-- a cell in one corner: bars on two sides (bug batch 2, #3: the bars collide, 0.9-stud gaps: nobody walks into the cell)
	local cx, cz = 16, -14
	for i = 0, 5 do
		Kit.part(detail, CFrame.new(cx - 6 + i * 1.2, 4, cz + 6), Vector3.new(0.3, 8, 0.3), C.Iron, M.Metal, { Name = "CellBar", Collide = true })
		Kit.part(detail, CFrame.new(cx - 6, 4, cz + i * 1.2), Vector3.new(0.3, 8, 0.3), C.Iron, M.Metal, { Name = "CellBar", Collide = true })
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
	Kit.rack(detail, CFrame.new(-24, 0, -6) * CFrame.Angles(0, -PI / 2, 0))
	Kit.candles(detail, CFrame.new(-19, 0, 0))
	if variant == 2 then
		-- bug batch 2 (#25): the table + bench moved off the exit door's axis (they stood at x 0, z 20 / 17.4, 4 studs
		-- in front of the doorway) to the free corner between the wine rack and the exit wall
		Kit.table(detail, CFrame.new(14, 0, 18))
		Kit.bench(detail, CFrame.new(14, 0, 15.4))
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
		-- bug batch 2 (#25): the exit wall's bulges at x -3 / 9 stood in (or beside) the doorway; they slide sideways until
		-- their tilted box clears the door lane (6 studs either side of the centre line); same r() calls, so the rest is unchanged
		local ry, rz = 3 + r() * 5, 23.5 - 0.8 * r()
		local size = Vector3.new(6 + r() * 2, 6 + r() * 4, 3 + r() * 2)
		local ex = x + 3
		local clear = 6.5 + size.X / 2 + 2 -- + the random tilt of Kit.rock
		if abs(ex) < clear then
			ex = (ex < 0) and -clear or clear
		end
		Kit.rock(model, CFrame.new(ex, ry, rz), size, seed + i + 60)
	end
	-- (#25) a stalagmite drawn on the exit's door lane (z > 10: its turned 2.6 base reaches z 12) steps out of it to the
	-- side away from the pool (x -8 clears the lane); they are drawn at z -8..18, never on the entrance lane
	local function offLane(x, z)
		if abs(x) < 8 and z > 10 then
			return -8
		end
		return x
	end
	for i = 1, 7 do
		local sx, sz = -18 + r() * 36, -8 + r() * 26
		Kit.stalagmite(detail, CFrame.new(offLane(sx, sz), 0, sz), 2.5 + r() * 2.5)
	end
	Kit.rock(detail, CFrame.new(-14, 1.2, -6), Vector3.new(3.5, 2.4, 3), seed + 81)
	Kit.rock(detail, CFrame.new(8, 0.9, -16), Vector3.new(2.6, 1.8, 2.2), seed + 82)
	Kit.rubble(detail, CFrame.new(-6, 0, 4), seed + 83)
	Kit.skulls(detail, CFrame.new(18, 0, -18))
	-- the pool in the far corner, a rim of stones and the waterfall wall over it (bug batch 2: the rim stones collide,
	-- a 1.2 step like the wall plinth; the pool sits 1 stud further from the exit door so its rim keeps off the door lane)
	local px, pz = 16, 15
	Kit.part(model, CFrame.new(px, 0.1, pz), Vector3.new(14, 0.2, 12), C.Water, M.Glass, { Name = "Pool", Transparency = 0.3 })
	for i = 1, 6 do
		local ang = (i / 6) * PI * 2
		Kit.part(model, CFrame.new(px + math.cos(ang) * 7.9, 0.6, pz + math.sin(ang) * 7.4) * CFrame.Angles(0, -ang, 0), Vector3.new(3.2, 1.2, 2), jitter(C.RockDark, seed + i), M.Slate, { Name = "PoolRim", Collide = true })
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
		Kit.stalagmite(detail, CFrame.new(-9, 0, -12), 4) -- was x -6: its base reached into the entrance lane (#25)
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
			Kit.part(model, CFrame.new(sx * 20.5, 2.5, z), Vector3.new(0.6, 5, 0.6), C.Iron, M.Metal, { Name = "LampPost", Collide = true })
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
	Kit.torch(model, CFrame.new(-7, 7, -24) * CFrame.Angles(0, PI, 0))
	Kit.torch(model, CFrame.new(7, 7, -24) * CFrame.Angles(0, PI, 0))
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
	-- the carpet runner (bug #5: the style key dungeon_<s>_carpet: a navy runner with brass edges and chevrons (b), a red
	-- carpet with a gold border (a), a terracotta herringbone path (c); its edge stripe = the floor's element colour. The
	-- two long lime Neon edge runes are gone: the screenshot's harsh green lines)
	local carpet = Mesh.group(model, "CarpetRun")
	Kit.part(carpet, CFrame.new(0, 0.1, -4), Vector3.new(8, 0.2, 56), C.Carpet, M.Fabric, { Name = "Carpet" })
	Kit.dress(carpet, Mesh.skey("carpet"), CFrame.new(0, 0, -4), { Primary = C.Carpet, Secondary = C.Accent }, nil, nil, true)
	-- the dais with stairs (one style key dungeon_<s>_dais, baked from these Parts), the throne and two braziers
	local daisZ = 28
	local dais = Mesh.group(model, "DaisSet")
	Kit.part(dais, CFrame.new(0, 1.2, daisZ), Vector3.new(24, 2.4, 14), C.StoneLight, M.Slate, { Name = "Dais", Collide = true })
	Kit.part(dais, CFrame.new(0, 2.5, daisZ), Vector3.new(6, 0.2, 10), C.Carpet, M.Fabric, { Name = "DaisCarpet" })
	Kit.part(dais, CFrame.new(0, 2.6, daisZ - 7.2), Vector3.new(24, 0.4, 0.6), C.StoneDark, M.Slate, { Name = "DaisKerb" })
	Kit.stairs(dais, CFrame.new(0, 0, daisZ - 7 - 4.8), 10, 3, 0.8)
	Kit.dress(dais, Mesh.skey("dais"), CFrame.new(0, 0, daisZ), { Secondary = C.Accent }, nil, nil, true)
	-- the throne (bug #5: the style key dungeon_<s>_throne: a carved granite throne with a red cushion and a cloud crest
	-- (a), the guild master's iron and brass chair with a copper lightning rod (b), a hollow stump with a moss cushion and
	-- a crown of leaves (c)); the Parts are its collider and fallback
	local tz = daisZ + 3
	local style = Style.Cur and Style.Cur.Id or DungeonBuilder.DefaultStyle
	local throne = Mesh.group(model, "ThroneSet")
	Kit.part(throne, CFrame.new(0, 3.4, tz), Vector3.new(3.4, 2, 2.4), C.StoneDark, M.Slate, { Name = "ThroneSeat", Collide = true })
	Kit.part(throne, CFrame.new(0, 6.2, tz + 1), Vector3.new(3.4, 7.6, 0.6), C.StoneDark, M.Slate, { Name = "ThroneBack", Collide = true })
	Kit.part(throne, CFrame.new(-1.7, 4.6, tz), Vector3.new(0.4, 2.4, 2.4), C.StoneDark, M.Slate, { Name = "ThroneArm", Collide = true })
	Kit.part(throne, CFrame.new(1.7, 4.6, tz), Vector3.new(0.4, 2.4, 2.4), C.StoneDark, M.Slate, { Name = "ThroneArm", Collide = true })
	if style == "b" then
		Kit.part(throne, CFrame.new(0, 10.35, tz + 1), Vector3.new(0.25, 0.7, 0.25), C.Gold, M.Metal, { Name = "LightningRod" })
	else
		Kit.part(throne, CFrame.new(0, 10.4, tz + 1), Vector3.new(1.6, 1, 0.5), C.Gold, M.Metal, { Name = "ThroneCrown" })
	end
	Kit.part(throne, CFrame.new(0, 4.6, tz - 0.2), Vector3.new(2.6, 0.5, 2), C.Carpet, M.Fabric, { Name = "ThroneCushion" })
	Kit.dress(throne, Mesh.skey("throne"), CFrame.new(0, 2.4, tz), { Secondary = C.Accent }, nil, nil, true)
	if style == "b" then
		-- the weather astrolabe over the chair: a captured storm cloud (a Neon cyan heart inside a puff mesh) in three
		-- brass gimbal rings that turn slowly (DungeonFx spins the NC_DungeonSpin parts about their local Y; each ring's
		-- plane holds its spin axis, so they sweep nested spheres: 2.4 / 2.0 / 1.6 studs, the rod tip at 2.2 sits between)
		-- (the review: at 13.2 the outer ring's mesh reached 15.7 under the 15.8 ceiling; at 12.9 it clears it by 0.4, and
		-- the rod tip (10.7, the throne key) stays 2.2 below the hub, between the outer and middle rings' spheres)
		local hub = CFrame.new(0, ASTRO_HUB_Y, tz + 1)
		local heart = Kit.part(model, hub, Vector3.new(0.9, 0.9, 0.9), C.Core, M.Neon, { Name = "CloudHeart" })
		local glow = Instance.new("PointLight")
		glow.Name = "CloudLight"
		glow.Color = C.CoreLight
		glow.Brightness = 1.2
		glow.Range = 16
		glow.Shadows = false
		glow.Parent = heart
		Kit.sound(heart, "astrolabe")
		local cloud = Kit.part(model, hub, Vector3.new(2.2, 1.6, 2.2), C.Marble, M.Slate, { Name = "StormCloud" })
		Mesh.tag(cloud, "dungeon_b_cloud", hub, nil, nil)
		local rings = {
			{ R = 2.4, Rot = CFrame.new(), Speed = 0.35 },
			{ R = 2.0, Rot = CFrame.Angles(0, 0, -PI / 2), Speed = -0.5 },
			{ R = 1.6, Rot = CFrame.Angles(PI / 2, 0, 0), Speed = 0.65 },
		}
		for i, rg in ipairs(rings) do
			local cf = hub * rg.Rot
			local ring = Kit.part(model, cf, Vector3.new(rg.R * 2, 0.3, 0.3), C.Gold, M.Metal, { Name = "AstroRing" })
			ring:SetAttribute("SpinSpeed", rg.Speed)
			ring:SetAttribute("SpinIndex", i)
			ring:SetAttribute("ML_Weld", true) -- the uploaded ring mesh rides the Part DungeonFx turns (client-side)
			CollectionService:AddTag(ring, "NC_DungeonSpin")
			Mesh.tag(ring, "dungeon_b_ring", cf, nil, nil, rg.R / 2.4)
		end
	end
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
	if style == "a" then
		-- the Undercroft's round sky window behind the throne (it lights the far end: the far arch used to read navy-black)
		local win = Kit.part(model, CFrame.new(0, 10.6, 35.9), Vector3.new(7, 7, 0.2), rgb(176, 214, 255), M.Slate, { Name = "SkyWindow" })
		local sky = Instance.new("PointLight")
		sky.Name = "SkyLight"
		sky.Color = rgb(186, 214, 255)
		sky.Brightness = 0.9
		sky.Range = 26
		sky.Shadows = false
		sky.Parent = win
		Mesh.tag(win, "dungeon_a_window", CFrame.new(0, 10.6, 36), nil, nil)
	else
		Kit.shield(detail, CFrame.new(0, 10, 36))
	end
	Kit.rubble(detail, CFrame.new(-20, 0, 4), seed + 9)
	-- banners on the side walls BETWEEN the torches (bug #5 fix 1: they hung at z -10 / 6, and the torch at z -9 burned
	-- through the cloth; roomShell's 4 torches stand at z -27, -9, 9, 27), chains from the ceiling, the bones
	for _, x in ipairs({ -30, 30 }) do
		Kit.banner(detail, CFrame.new(x, 12, 0) * CFrame.Angles(0, x < 0 and -PI / 2 or PI / 2, 0))
		Kit.banner(detail, CFrame.new(x, 12, 18) * CFrame.Angles(0, x < 0 and -PI / 2 or PI / 2, 0))
	end
	Kit.chain(detail, CFrame.new(-29.3, 12, -26))
	Kit.chain(detail, CFrame.new(29.3, 12, 24))
	Kit.bones(detail, CFrame.new(-24, 0, -30))
	-- bug #5 fix 4: the hay, barrel, crates, table, puddles and moss square of the cellar are gone; the throne room has
	-- its own two curios (the people who keep it) in the far-left and near-right corners, off both door lanes
	Kit.curio(detail, CFrame.new(-25, 0, 31) * CFrame.Angles(0, -PI / 2, 0))
	Kit.curio(detail, CFrame.new(25, 0, -30) * CFrame.Angles(0, PI / 2, 0))
	-- points: the zone covers the WHOLE room (56 x 72 on the 60 x 72 floor: the dais, the throne and the back strip are
	-- inside it, so a member who climbs the stairs is never dropped out of the fight); the enemies spawn at the foot of
	-- the dais stairs (SpawnAnchor), not on the throne
	attach(base, "Threshold", Vector3.new(0, 1.5, -26))
	for i = 1, 4 do
		attach(base, "Spawn" .. i, Vector3.new(-6 + (i - 1) * 4, 1.5, -32))
	end
	attach(base, "Dais", Vector3.new(0, 1.5, daisZ))
	attach(base, "ZoneCenter", Vector3.new(0, 1.5, 0))
	attach(base, "SpawnAnchor", Vector3.new(0, 1.5, 15))
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
		Kit.torch(model, CFrame.new(sx * 14, 6.5, 1) * CFrame.Angles(0, sx * PI / 2, 0))
	end
	Kit.torch(model, CFrame.new(-7, 7, 12))
	Kit.torch(model, CFrame.new(7, 7, 12))
	-- four spawn pads (Marble inlays) and the banner wall
	for i = 1, 4 do
		local x = -7.5 + (i - 1) * 5
		Kit.part(model, CFrame.new(x, 0.1, -4), Vector3.new(3.6, 0.2, 3.6), C.Marble, M.Marble, { Name = "Pad" })
		attach(base, "Spawn" .. i, Vector3.new(x, 1.5, -4))
	end
	Kit.banner(detail, CFrame.new(-6, 11, -12) * CFrame.Angles(0, PI, 0))
	Kit.banner(detail, CFrame.new(6, 11, -12) * CFrame.Angles(0, PI, 0))
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
		Kit.torch(model, CFrame.new(-5, 6.5, 0) * CFrame.Angles(0, -PI / 2, 0))
		Kit.torch(model, CFrame.new(5, 6.5, 0) * CFrame.Angles(0, PI / 2, 0))
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
		Kit.torch(model, CFrame.new(s * 5, 6.5, -5) * CFrame.Angles(0, s * PI / 2, 0))
		Kit.torch(model, CFrame.new(jog - s * 5, 6.5, 5) * CFrame.Angles(0, -s * PI / 2, 0))
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
	Kit.torch(model, CFrame.new(-14, 6.5, 0) * CFrame.Angles(0, -PI / 2, 0))
	Kit.torch(model, CFrame.new(14, 6.5, 0) * CFrame.Angles(0, PI / 2, 0))
	local chests = DungeonBuilder.CHEST_COUNT
	for i = 1, chests do
		local x = (i - (chests + 1) / 2) * 6
		Kit.chest(model, CFrame.new(x, 0, 3), i)
		attach(base, "Chest" .. i, Vector3.new(x, 1.5, 3))
	end
	Kit.rune(detail, CFrame.new(0, 0, -3), 20, 0.5)
	-- the exit portal: a Marble arch with a purple shimmer and the prompt part
	Kit.arch(model, CFrame.new(0, 0, 9.4), 6, 9)
	Kit.part(model, CFrame.new(0, 4.2, 9.4), Vector3.new(5.6, 8, 0.15), C.Accent, M.ForceField, { Name = "ExitShimmer", Transparency = 0.4 })
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
	Kit.banner(detail, CFrame.new(-10, 11, 11))
	Kit.banner(detail, CFrame.new(10, 11, 11))
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

-- the template of a style (built now when missing, ~0.1 s). bug #5: one set per style (the same layout and colliders,
-- the style's colours, keys and style props); style = DefaultStyle when nil. The models keep the plain names
-- (Hall_1 ...) with a Style attribute, so the set of every style lives side by side in DungeonTemplates.
local TplCache = {}
function DungeonBuilder.Template(name, style)
	local g = Geo[name]
	if not g then
		return nil
	end
	style = DungeonBuilder.Styles[style or ""] and style or DungeonBuilder.DefaultStyle
	local f = templateFolder()
	TplCache[style] = TplCache[style] or {}
	local existing = TplCache[style][name]
	if existing and existing.Parent == f then
		return existing
	end
	local prev = Style.Cur
	Style.Cur = DungeonBuilder.Styles[style]
	local ok, model = pcall(g.build)
	Style.Cur = prev
	if not ok then
		error(model, 0)
	end
	model:SetAttribute("Kind", g.Kind)
	model:SetAttribute("Budget", g.Budget)
	model:SetAttribute("Style", style)
	model.Parent = f
	TplCache[style][name] = model
	return model
end

-- every template of `style` (DefaultStyle when nil; "all" = every style)
function DungeonBuilder.EnsureTemplates(style)
	local styles = (style == "all") and DungeonBuilder.StyleOrder or { style or DungeonBuilder.DefaultStyle }
	for _, s in ipairs(styles) do
		for _, name in ipairs(DungeonBuilder.Templates) do
			DungeonBuilder.Template(name, s)
		end
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
	-- two torches on the front faces of the hoop's stone pillars (P6 A1: the P4 hoop gate), facing the plaza
	local look = siteCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local site = CFrame.lookAt(siteCFrame.Position, siteCFrame.Position + flat.Unit)
	for _, sx in ipairs({ -1, 1 }) do
		local mount = site * CFrame.new(sx * 9.9, 4.2, -1.5)
		local flame = Kit.torch(model, mount, 1.2)
		local light = flame:FindFirstChild("TorchLight")
		if light then
			light.Range = 16 -- the lobby rule (6.4 rule 7)
			light.Color = C.Light
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
			-- bug #5: every style's set (floors 1-3, 4-8 and 9-12 each use their own), one template per task.wait()
			for _, style in ipairs(DungeonBuilder.StyleOrder) do
				for _, name in ipairs(DungeonBuilder.Templates) do
					local ok, err = pcall(DungeonBuilder.Template, name, style)
					if not ok then
						warn("[DungeonBuilder] template " .. name .. " (" .. style .. ") failed: " .. tostring(err))
					end
					task.wait()
				end
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
	return C.Accent
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
	return { Floor = floorIndex, Seed = seed, Def = def, Kind = kind, Pieces = pieces, Rooms = rooms, Style = DungeonBuilder.StyleFor(floorIndex) }
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

-- bug #5: the floor's own look on a placed piece (before it is parented): the style's per-floor depth (colours x
-- Deepen; the lights are NOT dimmed, the review's readability cap), the element colour on every dressed key's Secondary
-- tint (DG_Element: banners, stripes, grates, crests), the Accent parts recoloured
local NO_DEEPEN = { [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }
local function lerpColor(a, f)
	return Color3.new(a.R * f, a.G * f, a.B * f)
end
local function dressFloor(model, pocket)
	local color = elementColor(pocket.Layout.Def.Element)
	local style = DungeonBuilder.Styles[pocket.Style or ""]
	local depth = DungeonBuilder.StyleDepth(pocket.Floor)
	local f = 1 - (1 - (style and style.Deepen or 1)) * depth
	recolourAccents(model, color)
	local list = model:GetDescendants()
	list[#list + 1] = model
	for _, d in ipairs(list) do
		if d:IsA("BasePart") then
			if f < 1 and not NO_DEEPEN[d.Material] and d:GetAttribute("Accent") ~= true then
				d.Color = lerpColor(d.Color, f)
			end
		end
		if d:GetAttribute("DG_Element") == true then
			d:SetAttribute("ML_Secondary", color)
		end
		local primary = d:GetAttribute("ML_Primary")
		if f < 1 and typeof(primary) == "Color3" then
			d:SetAttribute("ML_Primary", lerpColor(primary, f))
		end
	end
	return color
end

-- bug #5: the element weathering of a floor (blender keys dungeon_wx_<element>_high / _low: Nature moss and ferns, Earth
-- crystals and rubble, Water drip stains and puddles, Frost icicles and rime, Flame soot and ember cracks, Storm scorch
-- marks and a spark coil, Celestial star-moss, Shadow dark crystals). Two hang under the cornice of the entrance / exit
-- walls beside the doors, two sit at the foot of the side walls; a spot is skipped when a prop already stands there.
-- The anchors are invisible (a flat stand-in would bring back the pasted squares the pitch removed): the clusters show
-- once their keys are uploaded.
DungeonBuilder.WeatherKeys = {
	Nature = "nature", Earth = "earth", Water = "water", Frost = "frost", Flame = "flame", Storm = "storm", Celestial = "celestial", Shadow = "shadow",
}
-- the review (bug batch 2 #3 rule "no visible prop a player can stand inside"): the _low sets that stand taller than
-- the 1.1-stud step out on the floor get a collider over their footprint (spot space: x along the wall, z into the room
-- is negative, y up from the floor; from blender/kit/props/dungeon_props.py wx()). Shadow: crystals up to 1.9 studs;
-- Nature: fern fronds up to 1.3. The others stay under 1.1 on the floor (Earth crystals 1.05, Frost ice blocks 0.6,
-- Celestial star 0.95, Flame coals, Storm coil, Water drips: their taller bits sit on the plinth or the wall face).
DungeonBuilder.WeatherLowSolid = {
	Shadow = { X0 = -1.75, X1 = 1.85, Y1 = 2.0, Z0 = -2.0, Z1 = -0.5 },
	Nature = { X0 = -2.25, X1 = 1.95, Y1 = 1.35, Z0 = -2.05, Z1 = -0.5 },
}
local WEATHER_SKIP = { Floor = true, Wall = true, Plinth = true, Cap = true, Course = true, Dado = true, Brick = true, Ceiling = true, Crack = true, Base = true, Weather = true }
local function weatherSpots(g)
	local hw, hd = g.W / 2, g.D / 2
	local x = min(11, hw - 4)
	local spots = {}
	spots[#spots + 1] = { High = true, CF = CFrame.new(-x, WALL_H - 0.2, -hd) * CFrame.Angles(0, PI, 0) }
	spots[#spots + 1] = { High = true, CF = CFrame.new(x, WALL_H - 0.2, hd) }
	spots[#spots + 1] = { High = true, CF = CFrame.new(x, WALL_H - 0.2, -hd) * CFrame.Angles(0, PI, 0) }
	spots[#spots + 1] = { High = true, CF = CFrame.new(-x, WALL_H - 0.2, hd) }
	if g.Name and string.sub(g.Name, 1, 6) == "Bridge" then
		spots[#spots + 1] = { CF = CFrame.new(x, 0, -hd) * CFrame.Angles(0, PI, 0) }
		spots[#spots + 1] = { CF = CFrame.new(-x, 0, hd) }
	else
		for _, z in ipairs({ -0.4, 0.15, -0.1, 0.4 }) do
			spots[#spots + 1] = { CF = CFrame.new(-hw, 0, z * g.D) * CFrame.Angles(0, -PI / 2, 0) }
			spots[#spots + 1] = { CF = CFrame.new(hw, 0, -z * g.D) * CFrame.Angles(0, PI / 2, 0) }
		end
	end
	return spots
end

local function placeWeather(holder, model, element, g)
	local name = DungeonBuilder.WeatherKeys[element]
	local base = model.PrimaryPart
	if not name or not base or not g then
		return 0
	end
	local room = base.CFrame * CFrame.new(0, 1.5, 0)
	local inv = room:Inverse()
	-- the room-space boxes of what already stands in the room (walls, floor, ceiling and big slabs left out)
	local boxes = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not WEATHER_SKIP[d.Name] then
			local s = d.Size
			if max(s.X, s.Y, s.Z) < 20 then
				local cf = inv * d.CFrame
				local r = { cf:GetComponents() }
				local ex = abs(r[4]) * s.X / 2 + abs(r[5]) * s.Y / 2 + abs(r[6]) * s.Z / 2
				local ey = abs(r[7]) * s.X / 2 + abs(r[8]) * s.Y / 2 + abs(r[9]) * s.Z / 2
				local ez = abs(r[10]) * s.X / 2 + abs(r[11]) * s.Y / 2 + abs(r[12]) * s.Z / 2
				boxes[#boxes + 1] = { cf.X - ex, cf.Y - ey, cf.Z - ez, cf.X + ex, cf.Y + ey, cf.Z + ez }
			end
		end
	end
	local placed, high, low = 0, 0, 0
	for _, spot in ipairs(weatherSpots(g)) do
		if (spot.High and high < 2) or (not spot.High and low < 2) then
			-- the cluster's room-space box: 4.6 wide, under the cornice 3 tall x 1.2 deep, at the wall foot 2.6 x 2.6
			local c = spot.CF * CFrame.new(0, spot.High and -1.5 or 1.3, spot.High and -0.6 or -1.3)
			local hx, hy, hz = 2.3, spot.High and 1.5 or 1.3, spot.High and 0.6 or 1.3
			local r = { c:GetComponents() }
			local ex = abs(r[4]) * hx + abs(r[5]) * hy + abs(r[6]) * hz
			local ez = abs(r[10]) * hx + abs(r[11]) * hy + abs(r[12]) * hz
			local a = { c.X - ex, c.Y - hy, c.Z - ez, c.X + ex, c.Y + hy, c.Z + ez }
			local free = true
			for _, b in ipairs(boxes) do
				if a[1] < b[4] and b[1] < a[4] and a[2] < b[5] and b[2] < a[5] and a[3] < b[6] and b[3] < a[6] then
					free = false
					break
				end
			end
			if free then
				local at = room * spot.CF
				local solid = (not spot.High) and DungeonBuilder.WeatherLowSolid[element] or nil
				local anchor
				if solid then
					-- the anchor IS the collider (invisible, colliding, queryable) over the cluster's footprint
					anchor = Kit.part(holder, at * CFrame.new((solid.X0 + solid.X1) / 2, solid.Y1 / 2, (solid.Z0 + solid.Z1) / 2),
						Vector3.new(solid.X1 - solid.X0, solid.Y1, solid.Z1 - solid.Z0), elementColor(element), M.Slate, { Name = "Weather", Transparency = 1, Collide = true })
				else
					anchor = Kit.part(holder, at * CFrame.new(0, spot.High and -1.5 or 0.5, spot.High and -0.3 or -1), Vector3.new(4.4, 1, 0.6), elementColor(element), M.Slate, { Name = "Weather", Transparency = 1 })
				end
				anchor:SetAttribute("Element", element)
				Kit.sound(anchor, "weather_" .. element)
				local key = "dungeon_wx_" .. name .. (spot.High and "_high" or "_low")
				Mesh.tag(anchor, key, at, nil, nil)
				placed = placed + 1
				if spot.High then
					high = high + 1
				else
					low = low + 1
				end
				boxes[#boxes + 1] = a
			end
		end
	end
	return placed
end
DungeonBuilder._PlaceWeather = placeWeather
DungeonBuilder.AstroHubY = ASTRO_HUB_Y
DungeonBuilder._KitFns = Kit -- TESTS / RENDERS ONLY (tools, blender renders: doors + weathering on a bare template)
DungeonBuilder._ElementColor = function(e)
	return elementColor(e)
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
-- wave 6: the piece's camera box for DungeonController's camera clamp (attributes CamMin / CamMax, world space; pieces
-- never rotate). The hall, the rooms and the treasure: the W x D shell; a corridor: its floor tiles (a Left / Right
-- corridor's walkway is not centred on its origin). From 2 studs under the floor top up to the lowest Ceiling part's
-- bottom (CEIL_Y without one).
local function camBox(copy, piece, cf)
	local o = cf.Position
	local minX, maxX, minZ, maxZ = o.X - piece.W / 2, o.X + piece.W / 2, o.Z - piece.D / 2, o.Z + piece.D / 2
	local detail = copy:FindFirstChild("Detail")
	local ceil = nil
	local fx0, fx1, fz0, fz1 = math.huge, -math.huge, math.huge, -math.huge
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") and not (detail and d:IsDescendantOf(detail)) then
			if d.Name == "Ceiling" then
				local bottom = d.Position.Y - d.Size.Y / 2
				ceil = ceil and min(ceil, bottom) or bottom
			elseif d.Name == "Floor" and piece.Kind == "Corridor" then
				local p, s = d.Position, d.Size
				fx0, fx1 = min(fx0, p.X - s.X / 2), max(fx1, p.X + s.X / 2)
				fz0, fz1 = min(fz0, p.Z - s.Z / 2), max(fz1, p.Z + s.Z / 2)
			end
		end
	end
	if fx0 < fx1 then
		minX, maxX, minZ, maxZ = fx0, fx1, fz0, fz1
	end
	copy:SetAttribute("CamMin", Vector3.new(minX, o.Y - 2, minZ))
	copy:SetAttribute("CamMax", Vector3.new(maxX, ceil or (o.Y + CEIL_Y), maxZ))
end

local function clonePiece(pocket, pieceIndex, holder)
	local piece = pocket.Layout.Pieces[pieceIndex]
	local template = DungeonBuilder.Template(piece.Name, pocket.Style or pocket.Layout.Style)
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
	camBox(copy, piece, cf)
	copy.Parent = holder
	return copy
end

-- the zone part of a fight room: Mode "Dungeon", ZoneId "Room", Index (pocket), Room. `floorCf` is the room's floor
-- centre (the floor top, y 0 of the template): the 16-stud part stands 6 studs above it (presence box floor -2..+14) and
-- FloorY is the floor top itself (dungeon-fixes root cause B: the encounter centre is RoomInfo.ZoneFloor, never the part)
local function makeZone(model, pocket, room, size, floorCf)
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
	zone.CFrame = floorCf * CFrame.new(0, 6, 0)
	zone:SetAttribute("Mode", "Dungeon")
	zone:SetAttribute("ZoneId", "Room")
	zone:SetAttribute("Index", pocket.Index)
	zone:SetAttribute("Room", room)
	zone:SetAttribute("Size", size.X)
	zone:SetAttribute("FloorY", floorCf.Position.Y)
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
	-- bug #5: the doors and the weathering are built in the run's style (its colours and keys). The styled section runs
	-- in a pcall so Style.Cur is restored on an error too (else every later Kit call outside Template() would build in
	-- this run's style)
	local prevStyle = Style.Cur
	Style.Cur = DungeonBuilder.Styles[pocket.Style or ""] or Style.Cur
	local info
	local okStyled, styledErr = pcall(function()
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
	info = {
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
		local size = piece.Kind == "Boss" and Vector3.new(BOSS_ZONE.X, 0, BOSS_ZONE.Z) or Vector3.new(ROOM_ZONE.X, 0, ROOM_ZONE.Z)
		-- the floor centre: the ZoneCenter attachment or the room's centre, both ON the floor top (attachments sit at
		-- template y 0); the old fallback took the centre 1.5 studs BELOW the floor (FloorY 1.5 low, enemies ~4.5 up)
		local zc = worldPoint(model, "ZoneCenter")
		local floorCf = CFrame.new(zc and zc.Position or center.Position)
		info.ZoneFloor = floorCf
		info.Zone = makeZone(staging, pocket, room, size, floorCf)
		-- the enemies' spawn point in zone-local x / z when the template names one (DungeonService passes it to SpawnWave)
		local sa = worldPoint(model, "SpawnAnchor")
		if sa then
			local rel = info.Zone.CFrame:PointToObjectSpace(sa.Position)
			info.SpawnAnchor = { x = rel.X, z = rel.Z }
		end
		-- the two portcullis doors: Entrance (CLOSED until the group enters the room after everyone pressed E at it:
		-- DungeonService opens it in Dg.enterRoom, closes it again when the fight starts) and Exit (opens after the clear).
		-- The entrance's EnterPrompt stands on the corridor side; the boss room's exit carries the one to the treasure
		-- (the alcove has no door of its own), on the room side
		if entranceCf then
			local door, bars = Kit.door(staging, CFrame.new(entranceCf.Position - Vector3.new(0, 1.5, 0)) * CFrame.new(0, 0, 0), "Door_Entrance", 8)
			info.Door = { Model = door, Bars = bars }
			Kit.setDoor(door, false)
			info.EnterPrompt, info.EnterPoint = Kit.enterPrompt(staging, entranceCf * CFrame.new(0, 3, -2.5), enterLabel(room), room)
		end
		if exitCf then
			local door, bars = Kit.door(staging, CFrame.new(exitCf.Position - Vector3.new(0, 1.5, 0)), "Door_Exit", 8)
			info.ExitDoor = { Model = door, Bars = bars }
			Kit.setDoor(door, false)
			if piece.Kind == "Boss" then
				info.NextPrompt, info.NextPoint = Kit.enterPrompt(staging, exitCf * CFrame.new(0, 3, -2.5), enterLabel(room + 1), room + 1)
			end
		end
		staging:SetAttribute("DoorOpen", false)
		staging:SetAttribute("EntranceOpen", false)
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
	-- bug #5: the floor's element weathering in the room (not the treasure alcove), then the floor's look on everything
	if piece.Kind == "Room" or piece.Kind == "Boss" then
		placeWeather(staging, model, pocket.Layout.Def.Element, Geo[piece.Name])
	end
	dressFloor(staging, pocket)
	end)
	Style.Cur = prevStyle
	if not okStyled then
		staging:Destroy()
		error(styledErr, 0)
	end
	staging:SetAttribute("Room", room)
	staging:SetAttribute("Floor", pocket.Floor)
	staging:SetAttribute("Element", pocket.Layout.Def.Element)
	staging:SetAttribute("Style", pocket.Style)
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
	-- bug #5: the run's look (StyleTiers by floor) and its mood for the client (DungeonController's lighting preset):
	-- the style's ambient / colour correction (never darker than MoodFloor), the contrast a little harder deeper in the tier
	pocket.Style = pocket.Layout.Style or DungeonBuilder.StyleFor(floorIndex)
	do
		local st = DungeonBuilder.Styles[pocket.Style]
		local depth = DungeonBuilder.StyleDepth(floorIndex)
		local fl = DungeonBuilder.MoodFloor
		local function atLeast(c, lo)
			return Color3.new(max(c.R, lo.R), max(c.G, lo.G), max(c.B, lo.B))
		end
		holder:SetAttribute("DungeonStyle", pocket.Style)
		holder:SetAttribute("StyleName", st and st.Name or "")
		if st and st.Mood then
			holder:SetAttribute("MoodAmbient", atLeast(st.Mood.Ambient, fl.Ambient))
			holder:SetAttribute("MoodOutdoor", atLeast(st.Mood.Outdoor, fl.Outdoor))
			holder:SetAttribute("MoodBrightness", max(st.Mood.Brightness, fl.Brightness))
			holder:SetAttribute("MoodContrast", st.Mood.Contrast + 0.03 * depth)
			holder:SetAttribute("MoodTint", st.Mood.Tint)
		end
	end
	holder.Parent = folder
	-- the hall
	local hall = clonePiece(pocket, 1, holder)
	if hall then
		local prevStyle = Style.Cur
		Style.Cur = DungeonBuilder.Styles[pocket.Style] or Style.Cur
		local okStyled, styledErr = pcall(function()
		local spawns = {}
		for i = 1, 4 do
			local sp = worldPoint(hall, "Spawn" .. i)
			spawns[i] = sp and (sp * CFrame.new(0, 3, 0)) or (hall.PrimaryPart.CFrame * CFrame.new(0, 4.5, 0))
		end
		local exitCf = worldPoint(hall, "Exit")
		local door, bars = Kit.door(hall, CFrame.new(exitCf and (exitCf.Position - Vector3.new(0, 1.5, 0)) or hall.PrimaryPart.Position), "Door_Exit", 8)
		Kit.setDoor(door, false)
		hall:SetAttribute("DoorOpen", false)
		-- the hall's exit carries room 1's EnterPrompt (hall side; the run moves on when every member pressed E)
		local nextPrompt, nextPoint = nil, nil
		if exitCf then
			nextPrompt, nextPoint = Kit.enterPrompt(hall, exitCf * CFrame.new(0, 3, -2.5), enterLabel(1), 1)
		end
		dressFloor(hall, pocket)
		pocket.Hall = { Index = 0, Kind = "Hall", Model = hall, Room = hall, Spawns = spawns, Center = hall.PrimaryPart.Position + Vector3.new(0, 1.5, 0), ExitDoor = { Model = door, Bars = bars }, Entrance = spawns[1], NextPrompt = nextPrompt, NextPoint = nextPoint }
		pocket.Rooms[0] = pocket.Hall
		end)
		-- (Style.Cur restored on both paths: an error in the styled hall must not leave the Kit building in this style)
		Style.Cur = prevStyle
		if not okStyled then
			holder:Destroy()
			error(styledErr, 0)
		end
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
