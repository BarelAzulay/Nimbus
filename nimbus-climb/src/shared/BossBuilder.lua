-- BossBuilder (Phase 3, events): the four arena bosses as big DETAILED-VOXEL models (ARCHITECTURE_V3.md "Phase 3:
-- Pet battles", "Phase 3 build contract": EventService + BossBuilder; ART DIRECTION). Built on the CLIENT from a
-- BattleCatalog boss id (BattleController builds the raid boss; the server never moves these parts: Replication rule)
-- and animated locally between snapshots. Works in the Workspace and in ViewportFrames. Plain Lua 5.1-compatible.
--
-- API
--   BossBuilder.Build(bossId, opts) -> Model | nil
--       opts = { Detail = "High" | "Low" (default High; Low merges shades: about half the parts), Scale = n (default
--       BattleCatalog.Bosses[id].Scale or 1), CFrame = where the feet centre stands (LookVector = facing; default
--       identity), Parent, Pose = "Idle" (the first pose applied), PoseTime = 0 }.
--       The sculpt runs once per (bossId, detail, scale) and is cached: later builds clone it (fast). Call
--       BossBuilder.Preload(bossId) during the 2-minute raid announcement so the raid start never hitches.
--   BossBuilder.Animate(model, pose, t, opts)   applies a pose at time t (seconds, any running clock):
--       pose = "Idle" | "Windup" | "Attack" | "Basic" | "Enrage" | "Hurt" | "Down"
--       opts = { CFrame = the root CFrame this frame (the client's interpolated boss position; default: unchanged),
--                Progress = 0..1 (how far into a Windup / Attack / Basic / Enrage / Hurt / Down; default from t),
--                Attack = attack id (BattleCatalog.Bosses[id].Attacks[i].Id: picks the move, e.g. a one-arm zap or
--                the two-arm slam), Enraged = true (faster, fiercer idle) }
--       One BulkMoveTo per call (parts are anchored; only Workspace:BulkMoveTo or CFrame writes, nothing per part
--       allocated): cheap enough every frame for the one raid boss.
--   BossBuilder.SetEnraged(model, on)           the glowing parts (Glow / Eye / Bolt / Magma ... keys) turn the boss's
--                                               enrage colour (and back); the core light brightens
--   BossBuilder.Colors(bossId) -> { Glow, Telegraph, Edge, Enrage, Element }   (Color3s)
--   BossBuilder.TelegraphColor(bossId, attackId) -> fill Color3, edge Color3     colour of a floor telegraph
--   BossBuilder.FxPoint(model, name) -> Vector3 | nil   world position of a named effect point ("Mouth", "HandL",
--                                               "HandR", "Core", "Head1".."Head3", "Tail", "Crown"; see Rigs)
--   BossBuilder.GetHeight(model) -> studs       (also attribute Height; Radius = attribute Radius)
--   BossBuilder.Ids() -> { bossId... }          BattleCatalog.BossOrder (or the built-in list)
--   BossBuilder.Rigs[bossId]                    { Joints = { name -> { Parent, Pivot (voxels) } }, Fx = {...} }
--
-- Model layout (names are part of the contract: BattleController animates / attaches effects by them):
--   Boss_<id> (Model; attributes BossId, Element, Height, Radius, Detail, Scale; PrimaryPart = Root)
--     Root      invisible 1-stud part at the feet centre (the model's pivot; LookVector = facing)
--     Body      Model  the torso (every boss); its parts are named by palette key (Rock, Cloud, Scale, Glow, ...)
--     Head      Model  storm_titan / lava_golem / frost_wyrm          Jaw   Model  frost_wyrm (opens for the breath)
--     ArmL/ArmR Model  storm_titan / lava_golem (the fists that slam) Base  Model  storm_titan (its spinning vortex)
--     WingL/WingR Model frost_wyrm                                     Head1/Head2/Head3 Model shadow_hydra (L, C, R)
--   Every joint Model has attributes Pivot (Vector3, studs, Root space at rest) and JointParent (string, "" = Root).
--   Effect points are Attachments named "Fx_<name>" inside the joint that carries them.
-- Facing: -Z (Root.CFrame.LookVector). The bosses are 22-27 studs tall at Scale 1 (VoxelSize 0.5 stud), so they read
-- from the colosseum stands; High <= ~950 parts, Low <= ~700 (Low merges shades first).

local Shared = script.Parent
local Voxel = require(Shared:WaitForChild("Voxel"))

local BossBuilder = {}

local sin, cos, pi, max, min, floor, abs = math.sin, math.cos, math.pi, math.max, math.min, math.floor, math.abs

local VOXEL = 0.5 -- studs per voxel at Scale 1

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local lazyCatalog = nil
local function battleCatalog()
	if lazyCatalog == nil then
		lazyCatalog = false
		local inst = Shared:FindFirstChild("BattleCatalog")
		if inst then
			local ok, mod = pcall(require, inst)
			if ok and type(mod) == "table" then
				lazyCatalog = mod
			end
		end
	end
	return lazyCatalog or nil
end

local DEFAULT_IDS = { "storm_titan", "lava_golem", "frost_wyrm", "shadow_hydra" }

function BossBuilder.Ids()
	local bc = battleCatalog()
	local out = {}
	local src = (bc and type(bc.BossOrder) == "table" and #bc.BossOrder > 0) and bc.BossOrder or DEFAULT_IDS
	for i, id in ipairs(src) do
		out[i] = id
	end
	return out
end

----------------------------------------------------------------------
-- Colours: the glow, the floor telegraphs (fill + edge) and the enrage tint per boss
----------------------------------------------------------------------
local COLORS = {
	storm_titan = { Element = "Storm", Glow = rgb(110, 210, 255), Telegraph = rgb(80, 190, 255), Edge = rgb(255, 238, 140), Enrage = rgb(255, 92, 92) },
	lava_golem = { Element = "Flame", Glow = rgb(255, 112, 34), Telegraph = rgb(255, 104, 36), Edge = rgb(255, 214, 96), Enrage = rgb(255, 44, 44) },
	frost_wyrm = { Element = "Frost", Glow = rgb(140, 232, 255), Telegraph = rgb(110, 214, 255), Edge = rgb(240, 252, 255), Enrage = rgb(96, 120, 255) },
	shadow_hydra = { Element = "Shadow", Glow = rgb(196, 112, 255), Telegraph = rgb(170, 88, 255), Edge = rgb(255, 140, 236), Enrage = rgb(255, 60, 150) },
}
-- per attack overrides (BattleCatalog attack ids): fill, edge
local ATTACK_COLORS = {
	storm_titan = { slam = { rgb(80, 190, 255), rgb(255, 238, 140) }, chain = { rgb(255, 230, 110), rgb(255, 255, 220) } },
	lava_golem = { pool = { rgb(255, 128, 40), rgb(255, 214, 96) }, eruption = { rgb(255, 64, 32), rgb(255, 196, 80) } },
	frost_wyrm = { breath = { rgb(110, 214, 255), rgb(240, 252, 255) }, blizzard = { rgb(200, 236, 255), rgb(110, 190, 255) } },
	shadow_hydra = { fangs = { rgb(170, 88, 255), rgb(255, 140, 236) }, pulse = { rgb(236, 72, 200), rgb(255, 190, 250) } },
}

local FALLBACK_COLORS = { Element = "Storm", Glow = rgb(255, 220, 120), Telegraph = rgb(255, 90, 70), Edge = rgb(255, 230, 160), Enrage = rgb(255, 50, 50) }

function BossBuilder.Colors(bossId)
	local c = COLORS[bossId] or FALLBACK_COLORS
	return { Element = c.Element, Glow = c.Glow, Telegraph = c.Telegraph, Edge = c.Edge, Enrage = c.Enrage }
end

function BossBuilder.TelegraphColor(bossId, attackId)
	local per = ATTACK_COLORS[bossId]
	local a = per and per[attackId]
	if a then
		return a[1], a[2]
	end
	local c = COLORS[bossId] or FALLBACK_COLORS
	return c.Telegraph, c.Edge
end

----------------------------------------------------------------------
-- Sculpt helpers (voxel units; y up from the feet, the boss faces -Z, +X is its right)
----------------------------------------------------------------------
-- Phase 6 kit hook (read-only; the game never sets it): BossBuilder._Blueprint sculpts at k voxels per boss voxel
local MESH_K = nil
local MESH_FIELDS = { Center = true, A = true, B = true, Pivot = true, Radius = true, RadiusB = true, Size = true, Round = true, Thickness = true, ThicknessB = true }
local function meshScaled(t)
	local o = {}
	for key, v in pairs(t) do
		if MESH_FIELDS[key] then
			if type(v) == "number" then
				v = v * MESH_K
			elseif type(v) == "table" then
				local c = {}
				for i, x in pairs(v) do
					c[i] = (type(x) == "number") and x * MESH_K or x
				end
				v = c
			end
		elseif key == "Points" or key == "Radii" then
			local list = {}
			for i, pt in ipairs(v) do
				if type(pt) == "number" then
					list[i] = pt * MESH_K
				else
					list[i] = { pt[1] * MESH_K, pt[2] * MESH_K, pt[3] * MESH_K }
				end
			end
			v = list
		end
		o[key] = v
	end
	return o
end

local function shape(g, t)
	if MESH_K then
		t = meshScaled(t)
	end
	return Voxel.Shape(g, t)
end
local function ell(g, key, c, r, extra)
	local t = { Kind = "Ellipsoid", Center = c, Radius = r, Key = key }
	if extra then
		for k, v in pairs(extra) do
			t[k] = v
		end
	end
	return shape(g, t)
end
local function cap(g, key, a, b, r, rb, extra)
	local t = { Kind = "Capsule", A = a, B = b, Radius = r, RadiusB = rb, Key = key }
	if extra then
		for k, v in pairs(extra) do
			t[k] = v
		end
	end
	return shape(g, t)
end
local function cone(g, key, a, b, r, rb, extra)
	local t = { Kind = "Cone", A = a, B = b, Radius = r, RadiusB = rb or 0, Key = key }
	if extra then
		for k, v in pairs(extra) do
			t[k] = v
		end
	end
	return shape(g, t)
end
local function curve(g, key, pts, r, rb, extra)
	local t = { Kind = "Curve", Points = pts, Radius = r, RadiusB = rb, Key = key, Smooth = true }
	if extra then
		for k, v in pairs(extra) do
			t[k] = v
		end
	end
	return shape(g, t)
end
local function rbox(g, key, c, size, round, extra)
	local t = { Kind = "RoundBox", Center = c, Size = size, Round = round or 1, Key = key }
	if extra then
		for k, v in pairs(extra) do
			t[k] = v
		end
	end
	return shape(g, t)
end
local function box(g, key, c, size, extra)
	local t = { Kind = "Box", Center = c, Size = size, Key = key }
	if extra then
		for k, v in pairs(extra) do
			t[k] = v
		end
	end
	return shape(g, t)
end
local function paint(g, key, t, only)
	t.Key = key
	t.Op = "Paint"
	t.OnlyKeys = only
	if t.Kind == "Curve" and t.Smooth == nil then
		t.Smooth = true
	end
	return shape(g, t)
end
local function carve(g, t, only)
	t.Op = "Carve"
	t.OnlyKeys = only
	if t.Kind == "Curve" and t.Smooth == nil then
		t.Smooth = true
	end
	return shape(g, t)
end

-- a zig-zag lightning / crack path from a to b with n kinks (deterministic)
local function zigzag(a, b, n, amp, seed)
	local pts = { a }
	for i = 1, n - 1 do
		local f = i / n
		local h = Voxel.Hash(i, seed or 1, n, 7)
		local h2 = Voxel.Hash(seed or 1, i, 3, 11)
		pts[#pts + 1] = {
			a[1] + (b[1] - a[1]) * f + (h - 0.5) * 2 * amp,
			a[2] + (b[2] - a[2]) * f + (h2 - 0.5) * amp,
			a[3] + (b[3] - a[3]) * f + (h2 - h) * amp,
		}
	end
	pts[#pts + 1] = b
	return pts
end

----------------------------------------------------------------------
-- The rigs: joints (parent + pivot in voxels) and effect points (joint + voxel position)
----------------------------------------------------------------------
BossBuilder.Rigs = {
	storm_titan = {
		Height = 50,
		Order = { "Base", "Body", "Head", "ArmL", "ArmR" },
		Joints = {
			Base = { Parent = "", Pivot = { 0, 8, 0 } },
			Body = { Parent = "", Pivot = { 0, 15, 0 } },
			Head = { Parent = "Body", Pivot = { 0, 33, 0 } },
			ArmL = { Parent = "Body", Pivot = { -11, 29, 0 } },
			ArmR = { Parent = "Body", Pivot = { 11, 29, 0 } },
		},
		Fx = { Core = { "Body", { 0, 25, -7 } }, Mouth = { "Head", { 0, 36, -5 } }, Crown = { "Head", { 0, 46, 0 } },
			HandL = { "ArmL", { -14.6, 8, -4 } }, HandR = { "ArmR", { 14.6, 8, -4 } } },
	},
	lava_golem = {
		Height = 44,
		Order = { "Body", "Head", "ArmL", "ArmR" },
		Joints = {
			Body = { Parent = "", Pivot = { 0, 10, 0 } },
			Head = { Parent = "Body", Pivot = { 0, 28, -3 } },
			ArmL = { Parent = "Body", Pivot = { -12, 27, 0 } },
			ArmR = { Parent = "Body", Pivot = { 12, 27, 0 } },
		},
		Fx = { Core = { "Body", { 0, 21, -8 } }, Mouth = { "Head", { 0, 28, -9 } }, Crown = { "Body", { 0, 37, 7 } },
			HandL = { "ArmL", { -16.5, 4.5, -4 } }, HandR = { "ArmR", { 16.5, 4.5, -4 } } },
	},
	frost_wyrm = {
		Height = 52,
		Order = { "Body", "WingL", "WingR", "Head", "Jaw" },
		Joints = {
			Body = { Parent = "", Pivot = { 0, 4, 2 } },
			Head = { Parent = "Body", Pivot = { 0, 33, 1 } },
			Jaw = { Parent = "Head", Pivot = { 0, 36, -3 } },
			WingL = { Parent = "Body", Pivot = { -4, 27, 3 } },
			WingR = { Parent = "Body", Pivot = { 4, 27, 3 } },
		},
		Fx = { Mouth = { "Head", { 0, 36, -12 } }, Core = { "Body", { 0, 22, -2 } }, Crown = { "Head", { 0, 42, 1 } },
			Tail = { "Body", { 13, 3, -6 } } },
	},
	shadow_hydra = {
		Height = 42,
		Order = { "Body", "Head1", "Head2", "Head3" },
		Joints = {
			Body = { Parent = "", Pivot = { 0, 6, 3 } },
			Head1 = { Parent = "Body", Pivot = { -5, 15, -4 } },
			Head2 = { Parent = "Body", Pivot = { 0, 16, -5 } },
			Head3 = { Parent = "Body", Pivot = { 5, 15, -4 } },
		},
		Fx = { Core = { "Body", { 0, 18, 3 } }, Head1 = { "Head1", { -13, 31, -16 } }, Head2 = { "Head2", { 0, 36, -19 } },
			Head3 = { "Head3", { 13, 31, -16 } }, Mouth = { "Head2", { 0, 36, -19 } }, Tail = { "Body", { 8, 3, 27 } } },
	},
}

----------------------------------------------------------------------
-- Palettes (base colours; Voxel derives _Light / _Dark). Glow keys are Neon and recolour when enraged.
----------------------------------------------------------------------
local NEON = "Neon"
local function neon(c)
	return { Color = c, Material = NEON }
end

local PALETTES = {
	storm_titan = {
		Cloud = rgb(112, 126, 170), CloudDark = rgb(62, 70, 106), Mist = rgb(192, 204, 230), Storm = rgb(80, 90, 132),
		Stone = rgb(78, 82, 98), Metal = rgb(204, 172, 92), Rune = neon(rgb(110, 210, 255)), Bolt = neon(rgb(255, 240, 150)),
		Eye = neon(rgb(214, 244, 255)), Mouth = rgb(30, 34, 52),
	},
	lava_golem = {
		Rock = rgb(74, 60, 56), RockDark = rgb(46, 38, 38), Ash = rgb(124, 110, 102), Crust = rgb(150, 54, 28),
		Magma = neon(rgb(255, 112, 34)), MagmaHot = neon(rgb(255, 204, 84)), Eye = neon(rgb(255, 226, 130)), Mouth = rgb(28, 20, 20),
	},
	frost_wyrm = {
		Scale = rgb(112, 166, 220), ScaleDark = rgb(50, 88, 156), Belly = rgb(196, 224, 246), Frost = rgb(244, 250, 255),
		Crystal = { Color = rgb(150, 220, 250), Material = "Ice" }, Membrane = { Color = rgb(170, 216, 246), Material = "Ice", Transparency = 0.15 },
		Bone = rgb(236, 244, 252), Eye = neon(rgb(150, 236, 255)), Glow = neon(rgb(140, 232, 255)), Mouth = rgb(26, 44, 86), Tooth = rgb(250, 252, 255),
	},
	shadow_hydra = {
		Hide = rgb(72, 50, 110), HideDark = rgb(40, 28, 62), Belly = rgb(126, 92, 166), Spike = rgb(46, 32, 68),
		Glow = neon(rgb(196, 112, 255)), Eye = neon(rgb(186, 255, 120)), Fang = rgb(240, 232, 250), Mouth = rgb(20, 12, 30), Claw = rgb(214, 204, 228),
	},
}
-- keys whose parts glow (recoloured by SetEnraged)
local GLOW_KEYS = { Rune = true, Bolt = true, Eye = true, Magma = true, MagmaHot = true, Glow = true }

local function resolvePalette(raw)
	local out = {}
	for k, v in pairs(raw) do
		if type(v) == "table" then
			local mat = v.Material
			if type(mat) == "string" then
				local ok, enum = pcall(function()
					return Enum.Material[mat]
				end)
				mat = ok and enum or nil
			end
			out[k] = { Color = v.Color, Material = mat, Transparency = v.Transparency }
		else
			out[k] = v
		end
	end
	return out
end

----------------------------------------------------------------------
-- Storm Titan: a thunderhead given arms. A spinning storm-cloud vortex instead of legs, a broad slate chest with a
-- glowing rune core and lightning veins, cloud pauldrons, stone gauntlets with brass bands and crackling fists, a
-- visored head under a crown of lightning.
----------------------------------------------------------------------
local function sculptStormTitan(G)
	-- Base: the vortex - a funnel of storm cloud narrowing to the floor, two spiral bands of mist and dark cloud
	-- winding up it (it spins when animated), a puffy rim under the waist and mist rolling over the floor
	local g = G.Base
	cone(g, "Storm", { 0, 16.5, 0 }, { 0, 0.5, 0 }, 8.2, 2.4)
	for band = 0, 1 do
		local pts = {}
		for k = 0, 26 do
			local y = 0.8 + k * 0.58
			local a = k * 0.62 + band * pi
			local r = 2.6 + (y / 16.5) * 5.9
			pts[#pts + 1] = { cos(a) * r, y, sin(a) * r }
		end
		curve(g, band == 0 and "Mist" or "CloudDark", pts, 0.9, 1.5, { Steps = 4 })
	end
	for i = 0, 9 do
		local a = i / 10 * 2 * pi
		ell(g, (i % 2 == 0) and "Cloud" or "Storm", { cos(a) * 7.4, 15.4, sin(a) * 7.4 }, { 2.8, 2.3, 2.8 })
	end
	for i = 0, 6 do
		local a = i / 7 * 2 * pi + 0.3
		ell(g, (i % 2 == 0) and "Mist" or "Cloud", { cos(a) * 5.2, 1, sin(a) * 5.2 }, { 2.6, 1.4, 2.6 })
	end
	-- lightning flickering through the funnel
	curve(g, "Bolt", zigzag({ -2, 1.5, -3.4 }, { -5.4, 14, -6.4 }, 5, 1.2, 3), 0.55, 0.45)
	curve(g, "Bolt", zigzag({ 2.5, 3, -3.6 }, { 6.2, 13, -5 }, 4, 1.2, 5), 0.55, 0.45)
	curve(g, "Bolt", zigzag({ 1, 3, 4 }, { -2, 13, 7 }, 4, 1.2, 9), 0.5, 0.4)

	-- Body: waist, broad chest, the rune core, lightning veins, cloud pauldrons, a neck of mist
	g = G.Body
	ell(g, "Cloud", { 0, 18, 0 }, { 8.5, 5, 6.5 })
	ell(g, "Cloud", { 0, 25, 0 }, { 11.5, 9.5, 7.8 })
	ell(g, "CloudDark", { 0, 21, 1 }, { 9.5, 4, 7 }, { KeepExisting = true })
	-- pectoral plates (darker storm cloud), belt of mist
	ell(g, "Storm", { -4.6, 27, -5.2 }, { 4.6, 3.6, 2.6 })
	ell(g, "Storm", { 4.6, 27, -5.2 }, { 4.6, 3.6, 2.6 })
	shape(g, { Kind = "Torus", Center = { 0, 16.5, 0 }, Radius = 8.4, Thickness = 1.6, Key = "Mist" })
	-- the rune core: a socket with a glowing ball and a ring of brass
	carve(g, { Kind = "Ellipsoid", Center = { 0, 25, -7.6 }, Radius = { 3, 3, 2 } })
	ell(g, "Rune", { 0, 25, -6.6 }, { 2.4, 2.4, 1.8 })
	shape(g, { Kind = "Torus", Center = { 0, 25, -7 }, Radius = 3.2, Thickness = 0.7, Key = "Metal", Rotation = CFrame.Angles(pi / 2, 0, 0) })
	-- lightning veins running from the core over the chest
	for i, tip in ipairs({ { -9, 31, -4 }, { 9, 31, -4 }, { -8, 18, -5 }, { 8, 18, -5 }, { 0, 32, -6 } }) do
		paint(g, "Bolt", { Kind = "Curve", Points = zigzag({ 0, 25, -7.5 }, tip, 4, 1.1, 20 + i), Radius = 0.75 }, { Cloud = true, Storm = true, CloudDark = true })
	end
	-- pauldrons: dark cloud domes with mist tops and a brass rim
	for _, s in ipairs({ -1, 1 }) do
		ell(g, "CloudDark", { s * 11, 30, 0 }, { 6.2, 5.2, 6.4 })
		ell(g, "Mist", { s * 11.5, 33.6, 0.4 }, { 3.8, 2.4, 3.8 })
		ell(g, "Mist", { s * 14.5, 31.5, -2 }, { 2.4, 2, 2.4 })
		ell(g, "Cloud", { s * 8.5, 33, 2.5 }, { 2.6, 2.2, 2.6 })
		shape(g, { Kind = "Torus", Center = { s * 11, 27.6, 0 }, Radius = 5.6, Thickness = 0.7, Key = "Metal" })
	end
	ell(g, "Mist", { 0, 32.5, 0.5 }, { 4.6, 2.6, 4.6 })
	-- a mantle of storm puffs across the upper back
	for i = -2, 2 do
		ell(g, "Storm", { i * 4, 31.5 - abs(i) * 0.8, 5.2 }, { 3.2, 3, 2.8 })
	end

	-- Head: helm-like cloud skull, brow, glowing visor, crown of lightning, mist beard
	g = G.Head
	ell(g, "Cloud", { 0, 38.5, -0.5 }, { 5.8, 6, 5.6 })
	ell(g, "CloudDark", { 0, 40.2, -3.6 }, { 5.4, 1.5, 2.2 })
	ell(g, "Stone", { 0, 37.6, -4.2 }, { 4.2, 1.8, 1.6 }, { KeepExisting = true })
	carve(g, { Kind = "Box", Center = { 0, 38.2, -5.2 }, Size = { 7, 1.4, 2 } })
	box(g, "Eye", { -2.1, 38.2, -4.6 }, { 2.4, 1, 1 })
	box(g, "Eye", { 2.1, 38.2, -4.6 }, { 2.4, 1, 1 })
	box(g, "Mouth", { 0, 35.4, -4.9 }, { 3, 0.8, 1 })
	ell(g, "Mist", { 0, 34.2, -3.4 }, { 3.6, 2, 2.4 })
	ell(g, "Mist", { -2.6, 34.8, -2.6 }, { 1.8, 1.6, 1.8 })
	ell(g, "Mist", { 2.6, 34.8, -2.6 }, { 1.8, 1.6, 1.8 })
	-- the crown: five lightning spikes fanning out of the head
	cone(g, "Bolt", { 0, 43, 0 }, { 0, 49.5, 0.8 }, 1.15, 0)
	for _, s in ipairs({ -1, 1 }) do
		cone(g, "Bolt", { s * 2.6, 42.6, 0.2 }, { s * 4.8, 48, 1.2 }, 1.0, 0)
		cone(g, "Bolt", { s * 4.4, 41, 0.2 }, { s * 7.6, 45, 1.2 }, 0.85, 0)
	end
	shape(g, { Kind = "Torus", Center = { 0, 42, -0.3 }, Radius = 4.2, Thickness = 0.7, Key = "Metal" })

	-- Arms: cloud upper arm, dark elbow puff, stone gauntlet with brass bands, a big fist crackling with lightning
	for _, side in ipairs({ { "ArmL", -1 }, { "ArmR", 1 } }) do
		g = G[side[1]]
		local s = side[2]
		cap(g, "Cloud", { s * 12, 28.5, 0 }, { s * 14, 20.5, -1 }, 3.7, 3.2)
		ell(g, "CloudDark", { s * 14, 19.8, -1 }, { 3.8, 3.4, 3.8 })
		ell(g, "Mist", { s * 15.6, 21.5, 0.6 }, { 1.8, 1.6, 1.8 })
		cap(g, "Stone", { s * 14, 18.5, -1.2 }, { s * 14.5, 11.5, -3 }, 3.6, 4.3)
		paint(g, "Metal", { Kind = "Box", Center = { s * 14.2, 16.4, -1.8 }, Size = { 12, 1.2, 12 } }, "Stone")
		paint(g, "Metal", { Kind = "Box", Center = { s * 14.4, 12.6, -2.7 }, Size = { 12, 1.2, 12 } }, "Stone")
		paint(g, "Rune", { Kind = "Ellipsoid", Center = { s * 18.2, 14.5, -2.4 }, Radius = { 1.2, 1.6, 1.2 } }, "Stone")
		rbox(g, "Stone", { s * 14.6, 8, -3.6 }, { 7.4, 6.6, 7.4 }, 2.2)
		-- knuckles + thumb
		for k = -1, 1 do
			ell(g, "Metal", { s * 14.6 + k * 2.2, 8.6, -7.2 }, { 1.0, 1.0, 0.7 })
		end
		ell(g, "Stone", { s * 11.4, 8.6, -5.4 }, { 1.4, 2.4, 1.6 })
		-- crackling lightning around the fist
		curve(g, "Bolt", zigzag({ s * 17.5, 9, -5 }, { s * 21, 12, -7 }, 3, 1, 31), 0.5, 0.3)
		curve(g, "Bolt", zigzag({ s * 13, 5, -6 }, { s * 12, 1.5, -9 }, 3, 1, 37), 0.5, 0.3)
		curve(g, "Bolt", zigzag({ s * 16, 6, -1 }, { s * 19.5, 3, 1.5 }, 3, 1, 41), 0.45, 0.3)
	end
end

----------------------------------------------------------------------
-- Lava Golem: a walking volcano. Basalt boulders on stumpy legs, glowing magma cracks, a magma heart in the chest,
-- a smoking crater on its back, a small sunken head with furnace eyes, huge boulder fists.
----------------------------------------------------------------------
local function sculptLavaGolem(G)
	local g = G.Body
	local ROCK = { Rock = true, RockDark = true, Ash = true }
	-- legs + feet
	for _, s in ipairs({ -1, 1 }) do
		cap(g, "Rock", { s * 6, 11, 1 }, { s * 6.6, 4, 0 }, 4.4, 4.6)
		rbox(g, "RockDark", { s * 6.8, 2, -1.2 }, { 9.4, 4, 11 }, 1.8)
		for k = -1, 1 do
			ell(g, "Ash", { s * 6.8 + k * 2.6, 1.6, -6.4 }, { 1.2, 1.2, 1 })
		end
		paint(g, "Magma", { Kind = "Curve", Points = zigzag({ s * 4, 10, -3.6 }, { s * 7.5, 3, -4.6 }, 3, 0.8, 50 + s), Radius = 0.7 }, ROCK)
	end
	-- pelvis + hunched torso
	ell(g, "RockDark", { 0, 12, 0.5 }, { 9.6, 4.6, 7 })
	ell(g, "Rock", { 0, 21.5, 1 }, { 12.5, 10.5, 9 })
	-- boulder plates: chest, belly, back
	ell(g, "RockDark", { -5, 25, -6.8 }, { 5, 4, 2.8 })
	ell(g, "RockDark", { 5, 25, -6.8 }, { 5, 4, 2.8 })
	ell(g, "Ash", { 0, 15.5, -6.6 }, { 6.5, 3.6, 2.6 })
	ell(g, "Rock", { -6, 19, 7.4 }, { 5, 5, 3 })
	ell(g, "Rock", { 6, 19, 7.4 }, { 5, 5, 3 })
	-- the magma heart in a cracked socket
	carve(g, { Kind = "Ellipsoid", Center = { 0, 20.5, -9.2 }, Radius = { 3.6, 3.4, 2.4 } })
	ell(g, "MagmaHot", { 0, 20.5, -7.6 }, { 2.6, 2.6, 1.6 })
	ell(g, "Magma", { 0, 20.5, -7.2 }, { 3.4, 3.2, 1.6 }, { KeepExisting = true })
	-- glowing cracks over the whole body
	for i, seg in ipairs({
		{ { 0, 23, -8.5 }, { -8, 30, -5 } }, { { 0, 23, -8.5 }, { 9, 29, -5 } }, { { -2, 18, -8.5 }, { -9, 13, -5 } },
		{ { 2, 18, -8.4 }, { 10, 14, -4 } }, { { -10, 22, 3 }, { -4, 30, 8 } }, { { 10, 21, 3 }, { 5, 14, 8.5 } },
		{ { 0, 28, 8 }, { 0, 14, 9.6 } },
	}) do
		paint(g, "Magma", { Kind = "Curve", Points = zigzag(seg[1], seg[2], 4, 1.2, 60 + i), Radius = 0.8 }, ROCK)
	end
	-- cooling crust around the cracks near the heart
	paint(g, "Crust", { Kind = "Ellipsoid", Center = { 0, 20.5, -8.6 }, Radius = { 5, 4.6, 1.6 } }, { Rock = true, RockDark = true })
	-- shoulder boulders
	for _, s in ipairs({ -1, 1 }) do
		ell(g, "RockDark", { s * 11, 28, 1 }, { 6.2, 5, 6.2 })
		ell(g, "Ash", { s * 12.5, 31.5, 2 }, { 3, 2, 3 })
		ell(g, "Rock", { s * 8, 31, 4 }, { 3, 2.6, 3 })
	end
	-- the volcano on its back, crater + lava pool + drips
	cone(g, "RockDark", { 0, 25, 5.5 }, { 0, 37.5, 7.5 }, 7, 3.4)
	ell(g, "Ash", { 0, 37, 7.5 }, { 4, 1.4, 4 })
	carve(g, { Kind = "Ellipsoid", Center = { 0, 38, 7.5 }, Radius = { 2.8, 2.4, 2.8 } })
	ell(g, "MagmaHot", { 0, 35.6, 7.5 }, { 2.6, 0.9, 2.6 })
	for i, d in ipairs({ { -2.6, 1 }, { 2.4, 0.6 }, { 0.4, -2.4 }, { 0, 3 } }) do
		paint(g, "Magma", { Kind = "Curve", Points = { { d[1], 37, 7.5 + d[2] }, { d[1] * 1.7, 31, 7.5 + d[2] * 1.9 }, { d[1] * 2.2, 27 - i, 7.5 + d[2] * 2.3 } }, Radius = 0.7 }, ROCK)
	end

	-- Head: a sunken block of basalt, brow overhang, furnace eyes, a glowing mouth slit, small horns
	g = G.Head
	rbox(g, "Rock", { 0, 30, -5 }, { 8.4, 7.4, 7.4 }, 2.6)
	box(g, "RockDark", { 0, 32.8, -8.6 }, { 8.6, 1.8, 2 })
	carve(g, { Kind = "Box", Center = { 0, 30.6, -9.4 }, Size = { 6.4, 1.6, 2.2 } })
	ell(g, "Eye", { -2, 30.6, -8.4 }, { 1.3, 0.8, 0.6 })
	ell(g, "Eye", { 2, 30.6, -8.4 }, { 1.3, 0.8, 0.6 })
	rbox(g, "RockDark", { 0, 27, -7 }, { 6.6, 2.6, 4.4 }, 1)
	box(g, "Magma", { 0, 28.2, -9 }, { 4.4, 0.7, 0.8 })
	for _, s in ipairs({ -1, 1 }) do
		cone(g, "Ash", { s * 3.6, 33.2, -5 }, { s * 5.8, 37, -3.6 }, 1.2, 0.2)
	end

	-- Arms: boulder upper arm, a thick forearm, a huge fist; magma seams and an ash knuckle row
	for _, side in ipairs({ { "ArmL", -1 }, { "ArmR", 1 } }) do
		g = G[side[1]]
		local s = side[2]
		cap(g, "Rock", { s * 12.5, 26, 0 }, { s * 15.5, 16, -1 }, 4.2, 3.8)
		ell(g, "RockDark", { s * 15.5, 16, -1 }, { 4, 3.6, 4 })
		cap(g, "Rock", { s * 15.6, 15, -1.4 }, { s * 16.4, 8.5, -3 }, 4.2, 5)
		rbox(g, "RockDark", { s * 16.5, 4.6, -3.8 }, { 9.6, 8, 9.6 }, 2.8)
		for k = -1, 1 do
			ell(g, "Ash", { s * 16.5 + k * 2.6, 5.4, -8.6 }, { 1.3, 1.3, 0.8 })
		end
		paint(g, "Magma", { Kind = "Curve", Points = zigzag({ s * 13, 25, -3 }, { s * 16, 10, -5.6 }, 4, 0.9, 80 + s), Radius = 0.75 }, ROCK)
		paint(g, "Magma", { Kind = "Curve", Points = zigzag({ s * 20.4, 8, -2 }, { s * 19, 2, -7 }, 3, 0.7, 90 + s), Radius = 0.7 }, ROCK)
		for k = -1, 1 do
			paint(g, "MagmaHot", { Kind = "Ellipsoid", Center = { s * 16.5 + k * 2.6, 3.4, -8.7 }, Radius = { 0.7, 0.9, 0.7 } }, ROCK)
		end
	end
end

----------------------------------------------------------------------
-- Frost Wyrm: a serpent of living ice. Coils on the floor, a long neck rising into a horned head with a crystal
-- frill, glacier crystals along the spine, two crystal-membrane wings, small clawed forearms, a frost-white belly.
----------------------------------------------------------------------
local function sculptFrostWyrm(G)
	local g = G.Body
	local spine = {
		{ 12, 3.2, -4 }, { 10, 3.4, 4 }, { 3, 3.6, 9 }, { -6, 3.6, 7.5 }, { -10, 4, 0 }, { -6.5, 6, -6.5 },
		{ 0, 10, -5.5 }, { 3, 16, -1.5 }, { 2.4, 23, 2 }, { 0.6, 29.5, 2.4 }, { 0, 34, 1 },
	}
	local radii = { 1.8, 3.2, 4, 4.4, 4.6, 4.6, 4.6, 4.4, 4.0, 3.6, 3.3 }
	shape(g, { Kind = "Curve", Points = spine, Radii = radii, Key = "Scale", Smooth = true, Steps = 8 })
	-- tail tip: a long ice blade
	cone(g, "Crystal", { 12, 3.2, -4 }, { 13.5, 3, -10 }, 1.6, 0)
	-- dark scale bands down the back, frost-white belly plates on the front of the rising neck
	for i = 2, #spine - 1, 2 do
		local p = spine[i]
		paint(g, "ScaleDark", { Kind = "Ellipsoid", Center = { p[1], p[2] + 2.2, p[3] }, Radius = { 3.6, 1.6, 3.6 } }, "Scale")
	end
	paint(g, "Belly", { Kind = "Curve", Points = { { -5.5, 5, -9.8 }, { 1, 10, -9.6 }, { 4.6, 16, -5.6 }, { 3.6, 23, -2.6 }, { 1.4, 30, -2.6 } }, Radius = 2.4 }, "Scale")
	paint(g, "Belly", { Kind = "Box", Center = { 0, 1, 0 }, Size = { 40, 2.2, 40 } }, "Scale")
	-- glacier crystals along the spine (pointing up and back)
	local crystals = {
		{ { 9.5, 6.5, 5 }, { 11, 10, 7.5 }, 1.4 }, { { 2, 7.5, 11 }, { 2.5, 12, 14 }, 1.7 }, { { -7, 7.5, 9 }, { -9.5, 12.5, 11 }, 1.8 },
		{ { -12.5, 7.5, 0.5 }, { -16, 11.5, 1 }, 1.6 }, { { 4, 19, 1.5 }, { 6.5, 21.5, 5.5 }, 1.5 }, { { 2.5, 25.5, 4.5 }, { 4, 28, 8 }, 1.4 },
		{ { 0.6, 31, 4.2 }, { 1, 34, 7.5 }, 1.2 }, { { 6, 13, 1 }, { 9.5, 15, 3.5 }, 1.4 },
	}
	for _, c in ipairs(crystals) do
		cone(g, "Crystal", c[1], c[2], c[3], 0)
	end
	-- small forearms with claws, folded at the chest
	for _, s in ipairs({ -1, 1 }) do
		cap(g, "Scale", { s * 3.6, 20, -2.4 }, { s * 5.6, 16.5, -5.6 }, 1.5, 1.2)
		cap(g, "Scale", { s * 5.6, 16.5, -5.6 }, { s * 4.4, 15, -8 }, 1.2, 1)
		for k = -1, 1 do
			cone(g, "Bone", { s * 4.4 + k * 0.7, 14.8, -8.2 }, { s * 4.2 + k * 0.9, 13.4, -9.6 }, 0.5, 0)
		end
	end
	-- frost runes glowing along the flank
	for i, p in ipairs({ { -9.5, 5, -3 }, { -3, 4.8, 11.5 }, { 7, 4.6, 8.6 }, { 4.8, 12, -4.8 } }) do
		paint(g, "Glow", { Kind = "Ellipsoid", Center = p, Radius = { 1, 1.4, 1 } }, { Scale = true, ScaleDark = true })
		local _ = i
	end
	-- a frosty patch on the floor where it coils
	for i = 0, 5 do
		local a = i / 6 * 2 * pi
		ell(g, "Frost", { cos(a) * 9, 0.6, sin(a) * 9 + 1 }, { 3, 0.8, 3 }, { KeepExisting = true })
	end

	-- Head: long snout, brow ridges, glowing eyes, curved crystal horns, a frill of ice shards, upper teeth
	g = G.Head
	ell(g, "Scale", { 0, 38, 0.2 }, { 4.2, 3.8, 4.6 })
	cap(g, "Scale", { 0, 37.4, -2 }, { 0, 36.8, -10.4 }, 3, 2)
	ell(g, "ScaleDark", { 0, 40.8, 0.4 }, { 3.2, 1.2, 3.6 })
	paint(g, "ScaleDark", { Kind = "Capsule", A = { 0, 39.6, -2 }, B = { 0, 38.4, -9.6 }, Radius = 1.1 }, "Scale")
	for _, s in ipairs({ -1, 1 }) do
		-- brow ridge, a carved socket with a glowing eye, swept crystal horns, cheek spikes, a nostril
		cap(g, "ScaleDark", { s * 2.2, 40.2, -1.6 }, { s * 3.2, 39.6, -4.6 }, 0.9, 0.7)
		carve(g, { Kind = "Ellipsoid", Center = { s * 3.3, 38.5, -3.8 }, Radius = { 1.2, 0.9, 1.2 } })
		ell(g, "Eye", { s * 3, 38.5, -3.6 }, { 0.9, 0.7, 0.9 })
		curve(g, "Crystal", { { s * 2.4, 40.4, 1 }, { s * 4.2, 43.2, 3.4 }, { s * 4.8, 44.6, 6.8 } }, 1.25, 0.35)
		cone(g, "Crystal", { s * 3.8, 37.6, 2.4 }, { s * 7.4, 38.6, 4.6 }, 1.0, 0)
		cone(g, "Crystal", { s * 3.4, 35.8, 1.6 }, { s * 6.4, 34.8, 4.2 }, 0.9, 0)
		ell(g, "Mouth", { s * 1, 37.6, -10.6 }, { 0.45, 0.45, 0.45 })
	end
	cone(g, "Crystal", { 0, 41, 1.5 }, { 0, 44.8, 4 }, 1.1, 0)
	-- open mouth line + upper teeth hanging over the jaw
	carve(g, { Kind = "Box", Center = { 0, 35.2, -6.2 }, Size = { 4.6, 1.2, 8.4 } })
	box(g, "Mouth", { 0, 35.7, -5.6 }, { 3.4, 0.6, 7 }, { KeepExisting = true })
	for k = 0, 3 do
		cone(g, "Tooth", { -1.5, 35.6, -3.4 - k * 1.8 }, { -1.5, 34.2, -3.4 - k * 1.8 }, 0.45, 0)
		cone(g, "Tooth", { 1.5, 35.6, -3.4 - k * 1.8 }, { 1.5, 34.2, -3.4 - k * 1.8 }, 0.45, 0)
	end
	-- Jaw (opens for the breath)
	g = G.Jaw
	cap(g, "Scale", { 0, 34, -1.6 }, { 0, 34, -8.2 }, 2.2, 1.7)
	paint(g, "Belly", { Kind = "Box", Center = { 0, 32.8, -5 }, Size = { 6, 1.6, 10 } }, "Scale")
	carve(g, { Kind = "Box", Center = { 0, 35.4, -5 }, Size = { 3.2, 1.6, 6.4 } })
	box(g, "Mouth", { 0, 34.8, -5 }, { 3, 0.6, 6 }, { KeepExisting = true })
	for k = 0, 2 do
		cone(g, "Tooth", { -1.3, 34.6, -3.6 - k * 1.7 }, { -1.3, 35.8, -3.6 - k * 1.7 }, 0.4, 0)
		cone(g, "Tooth", { 1.3, 34.6, -3.6 - k * 1.7 }, { 1.3, 35.8, -3.6 - k * 1.7 }, 0.4, 0)
	end

	-- Wings: a bone arm + three fingers holding a crystal membrane with a scalloped trailing edge
	for _, side in ipairs({ { "WingL", -1 }, { "WingR", 1 } }) do
		g = G[side[1]]
		local s = side[2]
		local wrist = { s * 12, 34, 5 }
		curve(g, "Bone", { { s * 4, 27, 3 }, { s * 8, 31.5, 4 }, wrist }, 1.3, 0.9)
		local tips = { { s * 20, 36, 7.5 }, { s * 21, 28, 8 }, { s * 17, 20, 7.5 }, { s * 10, 18.5, 6 } }
		for _, tip in ipairs(tips) do
			curve(g, "Bone", { wrist, { (wrist[1] + tip[1]) / 2, (wrist[2] + tip[2]) / 2 + 0.6, (wrist[3] + tip[3]) / 2 }, tip }, 0.75, 0.4)
		end
		-- membrane: a thin slab between the fingers, tilted back
		shape(g, { Kind = "Ellipsoid", Center = { s * 13.5, 27.5, 6.2 }, Radius = { 8.4, 8.2, 0.7 }, Key = "Membrane", KeepExisting = true,
			Rotation = CFrame.Angles(0, s * -0.18, 0) })
		shape(g, { Kind = "Ellipsoid", Center = { s * 8, 25, 4.6 }, Radius = { 4.6, 6, 0.7 }, Key = "Membrane", KeepExisting = true })
		for k = 0, 2 do
			carve(g, { Kind = "Ellipsoid", Center = { s * (13 + k * 3.4), 18.6 + k * 2.4, 7 }, Radius = { 2.4, 2.6, 3 } }, "Membrane")
		end
		cone(g, "Crystal", wrist, { s * 13, 38, 5.5 }, 0.9, 0)
	end
end

----------------------------------------------------------------------
-- Shadow Hydra: three heads, one grudge. A heavy body on four clawed legs, a ridge of black spikes, glowing violet
-- runes, a spiked tail, three long necks (the centre one bigger) with glowing eyes and pale fangs.
----------------------------------------------------------------------
local function hydraHead(g, base, mid, top, dir, size)
	-- neck
	curve(g, "Hide", { base, mid, top }, 3.3 * size, 2.5 * size)
	-- belly stripe on the front of the neck
	paint(g, "Belly", { Kind = "Curve", Points = { { base[1], base[2], base[3] - 1.8 * size }, { mid[1], mid[2], mid[3] - 1.9 * size }, { top[1], top[2] - 0.6, top[3] - 1.8 * size } }, Radius = 1.4 * size }, "Hide")
	-- the head: a skull pointing along dir (x, z) from the top of the neck
	local hx, hz = dir[1], dir[2]
	local skull = { top[1] + hx * 1.2 * size, top[2] + 1.6 * size, top[3] + hz * 1.2 * size }
	local snout = { top[1] + hx * 6.2 * size, top[2] + 0.8 * size, top[3] + hz * 6.2 * size }
	ell(g, "Hide", skull, { 3.2 * size, 2.8 * size, 3.2 * size })
	cap(g, "Hide", skull, snout, 2.6 * size, 1.8 * size)
	ell(g, "HideDark", { skull[1] + hx * 0.8 * size, skull[2] + 2 * size, skull[3] + hz * 0.8 * size }, { 2.6 * size, 1.1 * size, 2.8 * size })
	-- eyes on both sides of the skull (perpendicular to dir)
	local px, pz = -hz, hx
	for _, s in ipairs({ -1, 1 }) do
		local e = { skull[1] + hx * 2 * size + px * s * 2 * size, skull[2] + 1 * size, skull[3] + hz * 2 * size + pz * s * 2 * size }
		carve(g, { Kind = "Ellipsoid", Center = e, Radius = 0.95 * size })
		ell(g, "Eye", e, { 0.8 * size, 0.6 * size, 0.8 * size })
		-- a back-swept horn
		cone(g, "Spike", { skull[1] + px * s * 1.6 * size, skull[2] + 2 * size, skull[3] + pz * s * 1.6 * size },
			{ skull[1] - hx * 3.6 * size + px * s * 2.6 * size, skull[2] + 4.2 * size, skull[3] - hz * 3.6 * size + pz * s * 2.6 * size }, 0.9 * size, 0)
		-- fangs at the front of the snout
		local f = { snout[1] - hx * 0.6 * size + px * s * 1.1 * size, snout[2] - 1 * size, snout[3] - hz * 0.6 * size + pz * s * 1.1 * size }
		cone(g, "Fang", f, { f[1], f[2] - 2.2 * size, f[3] }, 0.55 * size, 0)
	end
	-- glowing mouth line along the snout + a crest of spikes down the neck
	paint(g, "Glow", { Kind = "Capsule", A = { skull[1] + hx * 2 * size, skull[2] - 1.2 * size, skull[3] + hz * 2 * size }, B = { snout[1], snout[2] - 1 * size, snout[3] }, Radius = 0.5 * size }, { Hide = true, HideDark = true })
	for k = 0, 2 do
		local f = k / 3
		local p = { top[1] + (mid[1] - top[1]) * f, top[2] + (mid[2] - top[2]) * f + 2.4 * size, top[3] + (mid[3] - top[3]) * f + 1.6 * size }
		cone(g, "Spike", p, { p[1] - hx * 1.4, p[2] + 2.2 * size, p[3] + 1.6 * size }, 0.8 * size, 0)
	end
end

local function sculptShadowHydra(G)
	local g = G.Body
	-- body + belly
	ell(g, "Hide", { 0, 12, 3.5 }, { 11, 8, 12 })
	paint(g, "Belly", { Kind = "Ellipsoid", Center = { 0, 7, 2 }, Radius = { 9, 4.6, 10.6 } }, "Hide")
	-- four legs with claws
	for _, s in ipairs({ -1, 1 }) do
		for _, zz in ipairs({ -3.5, 10.5 }) do
			cap(g, "Hide", { s * 8, 9, zz }, { s * 10.2, 3, zz - 1.6 }, 3.3, 2.8)
			ell(g, "HideDark", { s * 10.4, 1.8, zz - 2.2 }, { 3.2, 1.8, 3.6 })
			for k = -1, 1 do
				cone(g, "Claw", { s * 10.4 + k * 1.3, 1.2, zz - 5 }, { s * 10.4 + k * 1.5, 0.6, zz - 6.6 }, 0.55, 0)
			end
		end
	end
	-- the spike ridge along the back + glowing runes between the spikes
	for k = 0, 6 do
		local z = -2 + k * 3
		local h = 19.4 - abs(k - 2.5) * 0.9
		cone(g, "Spike", { 0, h - 1.4, z }, { 0, h + 3.2 - abs(k - 2.5) * 0.4, z + 1.4 }, 1.6, 0)
		if k < 6 then
			paint(g, "Glow", { Kind = "Ellipsoid", Center = { 0, h - 0.6, z + 1.5 }, Radius = { 0.8, 0.8, 0.8 } }, { Hide = true })
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		paint(g, "Glow", { Kind = "Curve", Points = { { s * 6, 18, -1 }, { s * 9.4, 15, 4 }, { s * 8.6, 16.6, 10 } }, Radius = 0.7 }, { Hide = true })
		paint(g, "HideDark", { Kind = "Ellipsoid", Center = { s * 7, 17, 4 }, Radius = { 3, 3, 5 } }, { Hide = true })
		cone(g, "Spike", { s * 7.5, 16.5, 6 }, { s * 11, 19, 8 }, 1.1, 0)
	end
	-- dark scale bands across the back
	for k = 0, 4 do
		paint(g, "HideDark", { Kind = "Box", Center = { 0, 16, -3 + k * 4.4 }, Size = { 26, 10, 1.4 } }, "Hide")
	end
	-- spiked tail
	curve(g, "Hide", { { 0, 11, 14 }, { 0, 8, 20 }, { 3, 5, 24.5 }, { 7.5, 3, 27 } }, 3, 0.9)
	for k, p in ipairs({ { 0, 11.5, 18 }, { 1, 8.4, 22 }, { 4.6, 5.8, 25.6 } }) do
		cone(g, "Spike", p, { p[1], p[2] + 2.6 - k * 0.3, p[3] + 1.6 }, 0.9, 0)
	end
	cone(g, "Spike", { 7.5, 3, 27 }, { 11, 2.6, 28.5 }, 1.2, 0)

	-- the three heads (L, C, R): the centre one bigger and taller
	hydraHead(G.Head1, { -5, 15, -4 }, { -10, 21, -8 }, { -12, 27, -10 }, { -0.35, -0.94 }, 1.08)
	hydraHead(G.Head2, { 0, 16, -5 }, { 0, 25, -10 }, { 0, 32, -12 }, { 0, -1 }, 1.28)
	hydraHead(G.Head3, { 5, 15, -4 }, { 10, 21, -8 }, { 12, 27, -10 }, { 0.35, -0.94 }, 1.08)
end

local SCULPT = {
	storm_titan = sculptStormTitan,
	lava_golem = sculptLavaGolem,
	frost_wyrm = sculptFrostWyrm,
	shadow_hydra = sculptShadowHydra,
}

-- part budget per joint group (High; Low uses LOW_FACTOR). The torsos get enough parts to keep their light / dark
-- shading (ART DIRECTION: 2-3 shades per colour region); below it the LOD folds the shades away and the biggest
-- surfaces of the bosses read as one flat colour. The storm vortex stays lean (it spins: detail there is noise).
local BUDGET = {
	storm_titan = { Base = 170, Body = 420, Head = 130, ArmL = 150, ArmR = 150 },
	lava_golem = { Body = 560, Head = 90, ArmL = 150, ArmR = 150 },
	frost_wyrm = { Body = 560, Head = 170, Jaw = 60, WingL = 120, WingR = 120 },
	shadow_hydra = { Body = 470, Head1 = 160, Head2 = 160, Head3 = 160 },
}
-- colour regions the LOD never blends into their neighbours (a belly, the frost patch, brass bands)
local KEEP = {
	storm_titan = { "Metal", "Mist", "Bolt", "Rune", "Eye" },
	lava_golem = { "Ash", "Crust", "Magma", "MagmaHot", "Eye" },
	frost_wyrm = { "Belly", "ScaleDark", "Frost", "Glow", "Eye", "Crystal" },
	shadow_hydra = { "Belly", "Spike", "Glow", "Eye", "Fang", "Claw" },
}
local LOW_FACTOR = 0.5

----------------------------------------------------------------------
-- Build (cached templates, cloned)
----------------------------------------------------------------------
local templates = {} -- [bossId .. "|" .. detail .. "|" .. scale] = Model at rest at the origin (never parented)
local rigs = setmetatable({}, { __mode = "k" }) -- [model] = rig runtime

local function vec3(t, vs)
	return Vector3.new(t[1] * vs, t[2] * vs, t[3] * vs)
end

local function scaleOf(bossId, opts)
	local s = tonumber(opts and opts.Scale)
	if not s then
		local bc = battleCatalog()
		local boss = bc and type(bc.Bosses) == "table" and bc.Bosses[bossId]
		s = boss and tonumber(boss.Scale) or 1
	end
	if s ~= s or s <= 0 then
		s = 1
	end
	return min(max(s, 0.1), 4)
end

local function biggestPart(model)
	local best, vol = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > vol then
				best, vol = d, v
			end
		end
	end
	return best
end

local function nearestPart(model, pos)
	local best, dist = nil, math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local dd = (d.Position - pos).Magnitude
			if dd < dist then
				best, dist = d, dd
			end
		end
	end
	return best
end

local function buildTemplate(bossId, detail, scale)
	local rigDef = BossBuilder.Rigs[bossId]
	local sculpt = SCULPT[bossId]
	if not rigDef or not sculpt then
		return nil
	end
	local vs = VOXEL * scale
	local grids = {}
	for _, name in ipairs(rigDef.Order) do
		grids[name] = Voxel.NewGrid(rigDef.Height)
	end
	sculpt(grids)
	local palette = resolvePalette(PALETTES[bossId])
	local colors = COLORS[bossId] or FALLBACK_COLORS
	local model = Instance.new("Model")
	model.Name = "Boss_" .. bossId
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Transparency = 1
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	local budget = BUDGET[bossId] or {}
	local low = detail == "Low"
	local skip = {}
	for k in pairs(GLOW_KEYS) do
		skip[k] = true
	end
	skip.Mouth = true
	for _, name in ipairs(rigDef.Order) do
		local g = grids[name]
		Voxel.Shade(g, { Skip = skip, Smooth = 1 })
		local maxParts = budget[name] or 150
		if low then
			maxParts = floor(maxParts * LOW_FACTOR)
		end
		local joint = rigDef.Joints[name]
		local group, parts = Voxel.Build(g, { VoxelSize = vs, Palette = palette, Name = name, MaxParts = maxParts, Keep = KEEP[bossId], CastShadow = false })
		for _, p in ipairs(parts) do
			-- big pieces cast shadows (the boss should sit on the floor); small ones stay cheap
			p.CastShadow = max(p.Size.X, p.Size.Y, p.Size.Z) >= 3 * scale
		end
		group:SetAttribute("Pivot", vec3(joint.Pivot, vs))
		group:SetAttribute("JointParent", joint.Parent or "")
		group.PrimaryPart = nil
		group.Parent = model
	end
	-- effect points
	for fxName, fx in pairs(rigDef.Fx or {}) do
		local group = model:FindFirstChild(fx[1])
		if group then
			local pos = vec3(fx[2], vs)
			local host = nearestPart(group, pos)
			if host then
				local att = Instance.new("Attachment")
				att.Name = "Fx_" .. fxName
				att.Position = host.CFrame:PointToObjectSpace(pos)
				att.Parent = host
			end
		end
	end
	-- the core light (brightens when enraged)
	local core = model:FindFirstChild("Fx_Core", true)
	local host = core and core.Parent or biggestPart(model)
	if host then
		local light = Instance.new("PointLight")
		light.Name = "BossLight"
		light.Color = colors.Glow
		light.Brightness = 1.6
		light.Range = 22 * scale
		light.Shadows = false
		light.Parent = host
	end
	-- the Workspace-visible attributes
	local y0, y1 = math.huge, -math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			y0 = min(y0, d.Position.Y - d.Size.Y / 2)
			y1 = max(y1, d.Position.Y + d.Size.Y / 2)
		end
	end
	local height = (y1 > y0) and (y1 - y0) or rigDef.Height * vs
	model:SetAttribute("BossId", bossId)
	model:SetAttribute("Element", colors.Element)
	model:SetAttribute("Height", height)
	local bc = battleCatalog()
	local boss = bc and type(bc.Bosses) == "table" and bc.Bosses[bossId]
	model:SetAttribute("Radius", (boss and tonumber(boss.Radius) or 7) * scale)
	model:SetAttribute("Detail", low and "Low" or "High")
	model:SetAttribute("Scale", scale)
	return model
end

-- Phase 6 kit hook (read-only, never used by the game): the shaded joint grids of a boss sculpted at k voxels per
-- boss voxel (blender/kit/bridge.py). Joint pivots stay in boss voxels (VOXEL studs each); grid voxels are VOXEL / k.
function BossBuilder._Blueprint(bossId, k)
	local rigDef = BossBuilder.Rigs[bossId]
	local sculpt = SCULPT[bossId]
	if not rigDef or not sculpt then
		return nil
	end
	local grids = {}
	for _, name in ipairs(rigDef.Order) do
		grids[name] = Voxel.NewGrid(rigDef.Height)
	end
	MESH_K = tonumber(k) or 1
	local ok, err = pcall(sculpt, grids)
	MESH_K = nil
	if not ok then
		error(err, 0)
	end
	local skip = { Mouth = true }
	for key in pairs(GLOW_KEYS) do
		skip[key] = true
	end
	for _, name in ipairs(rigDef.Order) do
		Voxel.Shade(grids[name], { Skip = skip, Smooth = 1 })
	end
	return {
		Grids = grids, Order = rigDef.Order, Joints = rigDef.Joints, Fx = rigDef.Fx, Keep = KEEP[bossId],
		Palette = resolvePalette(PALETTES[bossId]), Colors = COLORS[bossId] or FALLBACK_COLORS, K = MESH_K or tonumber(k) or 1,
		VoxelStuds = VOXEL / (tonumber(k) or 1),
	}
end

-- the runtime rig of a model built by Build (read from its joint attributes; the model must be at rest)
local function registerRig(model, bossId)
	local rigDef = BossBuilder.Rigs[bossId]
	local root = model:FindFirstChild("Root")
	if not rigDef or not root then
		return nil
	end
	local rootInv = root.CFrame:Inverse()
	local rig = { BossId = bossId, Model = model, Root = root, Joints = {}, Order = {}, Parts = { root }, Rest = { CFrame.new() },
		Owner = { false }, CFs = { root.CFrame }, Glow = {}, Light = model:FindFirstChild("BossLight", true), Enraged = false }
	for _, name in ipairs(rigDef.Order) do
		local group = model:FindFirstChild(name)
		if group then
			local pivot = group:GetAttribute("Pivot")
			local j = { Name = name, Parent = group:GetAttribute("JointParent") or "", Pivot = typeof(pivot) == "Vector3" and pivot or Vector3.new(), World = CFrame.new() }
			j.PivotCF = CFrame.new(j.Pivot)
			j.PivotInv = CFrame.new(-j.Pivot)
			rig.Joints[name] = j
			table.insert(rig.Order, j)
			for _, d in ipairs(group:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(rig.Parts, d)
					table.insert(rig.Rest, rootInv * d.CFrame)
					table.insert(rig.Owner, j)
					table.insert(rig.CFs, d.CFrame)
					if GLOW_KEYS[d.Name] then
						table.insert(rig.Glow, { Part = d, Color = d.Color })
					end
				end
			end
		end
	end
	rig.RootCF = root.CFrame
	rigs[model] = rig
	return rig
end

function BossBuilder.Build(bossId, opts)
	opts = type(opts) == "table" and opts or {}
	if type(bossId) ~= "string" or not BossBuilder.Rigs[bossId] then
		return nil
	end
	local detail = opts.Detail == "Low" and "Low" or "High"
	local scale = scaleOf(bossId, opts)
	local key = bossId .. "|" .. detail .. "|" .. tostring(scale)
	local template = templates[key]
	if not template then
		local ok, result = pcall(buildTemplate, bossId, detail, scale)
		if not ok then
			warn("[BossBuilder] " .. bossId .. " failed: " .. tostring(result))
			return nil
		end
		template = result
		if not template then
			return nil
		end
		templates[key] = template
	end
	local model = template:Clone()
	local root = model:FindFirstChild("Root")
	if root then
		model.PrimaryPart = root
	end
	registerRig(model, bossId)
	BossBuilder.Animate(model, opts.Pose or "Idle", tonumber(opts.PoseTime) or 0, { CFrame = typeof(opts.CFrame) == "CFrame" and opts.CFrame or CFrame.new(), Progress = opts.Progress, Attack = opts.Attack, Enraged = opts.Enraged })
	if opts.Enraged then
		BossBuilder.SetEnraged(model, true)
	end
	if opts.Parent then
		model.Parent = opts.Parent
	end
	return model
end

-- builds (and caches) the template now, so the raid start only clones
function BossBuilder.Preload(bossId, opts)
	opts = type(opts) == "table" and opts or {}
	if type(bossId) ~= "string" or not BossBuilder.Rigs[bossId] then
		return false
	end
	local detail = opts.Detail == "Low" and "Low" or "High"
	local scale = scaleOf(bossId, opts)
	local key = bossId .. "|" .. detail .. "|" .. tostring(scale)
	if templates[key] then
		return true
	end
	local ok, result = pcall(buildTemplate, bossId, detail, scale)
	if ok and result then
		templates[key] = result
		return true
	end
	return false
end

function BossBuilder.GetHeight(model)
	if typeof(model) ~= "Instance" then
		return 0
	end
	return tonumber(model:GetAttribute("Height")) or 0
end

function BossBuilder.FxPoint(model, name)
	if typeof(model) ~= "Instance" or type(name) ~= "string" then
		return nil
	end
	local att = model:FindFirstChild("Fx_" .. name, true)
	if not att or not att:IsA("Attachment") then
		return nil
	end
	local host = att.Parent
	if host and host:IsA("BasePart") then
		return host.CFrame:PointToWorldSpace(att.Position)
	end
	return nil
end

----------------------------------------------------------------------
-- Poses: per boss, a function(pose, t, p, opts) -> { joint = CFrame (rotation / offset about the joint pivot) }
-- p = progress 0..1 of a one-shot pose. Angles in radians: +X rotation lifts a forward-pointing part (head / snout
-- up, an arm hanging down swings forward and up); +Z rotation swings the right side (+X) up.
----------------------------------------------------------------------
local A = CFrame.Angles
local IDENTITY = CFrame.new()

local function ease(p)
	p = min(max(p, 0), 1)
	return p * p * (3 - 2 * p)
end

-- a strike curve: fast to 1 by `hit`, holds, then eases back during the last third
local function strike(p, hit)
	hit = hit or 0.3
	if p < hit then
		return ease(p / hit)
	elseif p < 0.7 then
		return 1
	end
	return 1 - ease((p - 0.7) / 0.3)
end

local function titanPose(pose, t, p, opts)
	local speed = opts.Enraged and 1.8 or 1
	local tt = t * speed
	local out = {}
	local bob = sin(tt * 1.6) * 0.35
	out.Base = A(0, tt * 1.4, 0)
	out.Body = CFrame.new(0, bob, 0) * A(sin(tt * 0.8) * 0.02 + (opts.Enraged and -0.06 or 0), sin(tt * 0.5) * 0.04, 0)
	out.Head = A(sin(tt * 0.9) * 0.05, sin(tt * 0.7) * 0.14, 0)
	local swing = sin(tt * 1.6) * 0.08
	local spread = opts.Enraged and 0.22 or 0.1
	out.ArmR = A(swing, 0, spread)
	out.ArmL = A(-swing, 0, -spread)
	if pose == "Windup" then
		local e = ease(p)
		if opts.Attack == "chain" then
			out.ArmR = A(1.4 * e, 0, 0.5 * e)
			out.Body = out.Body * A(0.1 * e, -0.3 * e, 0)
		else
			out.ArmR = A(2.6 * e, 0, 0.25 * e)
			out.ArmL = A(2.6 * e, 0, -0.25 * e)
			out.Body = out.Body * A(0.16 * e, 0, 0)
			out.Head = A(0.25 * e, 0, 0)
		end
	elseif pose == "Attack" then
		local s = strike(p, 0.25)
		if opts.Attack == "chain" then
			out.ArmR = A(1.5, 0, 0.1 - 0.2 * s)
			out.Body = out.Body * A(-0.08 * s, 0.25 * s, 0)
		else
			local a = 2.6 - 2.2 * s
			out.ArmR = A(a, 0, 0.25 - 0.3 * s)
			out.ArmL = A(a, 0, -0.25 + 0.3 * s)
			out.Body = out.Body * CFrame.new(0, -0.8 * s, 0) * A(-0.28 * s, 0, 0)
			out.Head = A(-0.15 * s, 0, 0)
		end
	elseif pose == "Basic" then
		local s = strike(p, 0.3)
		out.ArmR = A(1.3 * s, 0, 0.1)
		out.Body = out.Body * A(-0.08 * s, 0.15 * s, 0)
	elseif pose == "Enrage" then
		local e = sin(min(p, 1) * pi)
		out.ArmR = A(0.6 * e, 0, 1.2 * e)
		out.ArmL = A(0.6 * e, 0, -1.2 * e)
		out.Head = A(0.4 * e, 0, 0)
		out.Body = out.Body * A(0.18 * e, 0, 0)
	elseif pose == "Hurt" then
		local e = 1 - ease(p)
		out.Body = out.Body * A(0.14 * e, 0, 0.05 * e)
		out.Head = A(0.2 * e, 0, 0)
	elseif pose == "Down" then
		local e = ease(p)
		out.Body = CFrame.new(0, -5 * e, 1.5 * e) * A(0.5 * e, 0, 0.12 * e)
		out.ArmR = A(0.2, 0, 0.5 * e)
		out.ArmL = A(0.2, 0, -0.5 * e)
		out.Head = A(-0.5 * e, 0, 0)
		out.Base = CFrame.new(0, -2 * e, 0) * A(0, tt * 0.3, 0)
	end
	return out
end

local function golemPose(pose, t, p, opts)
	local speed = opts.Enraged and 1.6 or 1
	local tt = t * speed
	local out = {}
	local breathe = sin(tt * 1.2)
	out.Body = CFrame.new(0, breathe * 0.2, 0) * A(breathe * 0.02 + (opts.Enraged and -0.08 or 0), sin(tt * 0.45) * 0.06, sin(tt * 0.6) * 0.02)
	out.Head = A(sin(tt * 0.8) * 0.04, sin(tt * 0.55) * 0.12, 0)
	out.ArmR = A(sin(tt * 1.2) * 0.06, 0, 0.06)
	out.ArmL = A(-sin(tt * 1.2) * 0.06, 0, -0.06)
	if pose == "Windup" then
		local e = ease(p)
		if opts.Attack == "eruption" then
			out.Body = out.Body * CFrame.new(0, -1.2 * e, 0)
			out.ArmR = A(2.4 * e, 0, 0.6 * e)
			out.ArmL = A(2.4 * e, 0, -0.6 * e)
			out.Head = A(0.35 * e, 0, 0)
		else
			out.ArmR = A(2.5 * e, 0, 0.15 * e)
			out.Body = out.Body * A(0.1 * e, -0.2 * e, 0)
		end
	elseif pose == "Attack" then
		local s = strike(p, 0.22)
		if opts.Attack == "eruption" then
			local a = 2.4 - 2.2 * s
			out.ArmR = A(a, 0, 0.6 - 0.4 * s)
			out.ArmL = A(a, 0, -0.6 + 0.4 * s)
			out.Body = out.Body * CFrame.new(0, -1.6 * s, 0) * A(-0.2 * s, 0, 0)
			out.Head = A(0.3 * (1 - s), 0, 0)
		else
			out.ArmR = A(2.5 - 2.1 * s, 0, 0.15)
			out.Body = out.Body * A(-0.22 * s, 0.15 * s, 0)
		end
	elseif pose == "Basic" then
		local s = strike(p, 0.3)
		out.ArmL = A(1.4 * s, 0, -0.05)
		out.Body = out.Body * A(-0.08 * s, -0.15 * s, 0)
	elseif pose == "Enrage" then
		local e = sin(min(p, 1) * pi)
		out.ArmR = A(2.2 * e, 0, 0.7 * e)
		out.ArmL = A(2.2 * e, 0, -0.7 * e)
		out.Head = A(0.45 * e, 0, 0)
		out.Body = out.Body * A(0.15 * e, 0, 0)
	elseif pose == "Hurt" then
		local e = 1 - ease(p)
		out.Body = out.Body * A(0.12 * e, 0, -0.05 * e)
	elseif pose == "Down" then
		local e = ease(p)
		out.Body = CFrame.new(0, -3.5 * e, 0) * A(-0.35 * e, 0, 0.1 * e)
		out.ArmR = A(0.3 * e, 0, 0.4 * e)
		out.ArmL = A(0.3 * e, 0, -0.4 * e)
		out.Head = A(-0.4 * e, 0, 0)
	end
	return out
end

local function wyrmPose(pose, t, p, opts)
	local speed = opts.Enraged and 1.7 or 1
	local tt = t * speed
	local out = {}
	out.Body = A(sin(tt * 0.9) * 0.03, sin(tt * 0.6) * 0.06, sin(tt * 0.7) * 0.02)
	out.Head = A(sin(tt * 1.1) * 0.08, sin(tt * 0.8) * 0.18, sin(tt * 0.6) * 0.05)
	out.Jaw = A(-0.08 - (sin(tt * 1.3) + 1) * 0.04, 0, 0)
	local flap = sin(tt * 1.4) * (opts.Enraged and 0.3 or 0.16)
	out.WingR = A(0, -0.1, flap)
	out.WingL = A(0, 0.1, -flap)
	if pose == "Windup" then
		local e = ease(p)
		if opts.Attack == "blizzard" then
			out.WingR = A(0, -0.3 * e, 0.7 * e)
			out.WingL = A(0, 0.3 * e, -0.7 * e)
			out.Head = A(0.5 * e, 0, 0)
			out.Jaw = A(-0.5 * e, 0, 0)
		else
			out.Head = A(0.55 * e, 0, 0)
			out.Body = out.Body * A(0.08 * e, 0, 0)
			out.Jaw = A(-0.3 * e, 0, 0)
		end
	elseif pose == "Attack" then
		local s = strike(p, 0.2)
		if opts.Attack == "blizzard" then
			out.WingR = A(0, 0.1 * s, 0.7 - 1.1 * s)
			out.WingL = A(0, -0.1 * s, -0.7 + 1.1 * s)
			out.Head = A(0.5 - 0.3 * s, 0, 0)
			out.Jaw = A(-0.7 * s, 0, 0)
		else
			out.Head = A(0.55 - 0.85 * s, 0, 0)
			out.Body = out.Body * A(-0.08 * s, 0, 0)
			out.Jaw = A(-0.75 * s, 0, 0)
		end
	elseif pose == "Basic" then
		local s = strike(p, 0.3)
		out.Head = A(-0.2 * s, 0, 0)
		out.Jaw = A(-0.5 * s, 0, 0)
	elseif pose == "Enrage" then
		local e = sin(min(p, 1) * pi)
		out.Head = A(0.7 * e, 0, 0)
		out.Jaw = A(-0.8 * e, 0, 0)
		out.WingR = A(0, -0.2 * e, 0.8 * e)
		out.WingL = A(0, 0.2 * e, -0.8 * e)
	elseif pose == "Hurt" then
		local e = 1 - ease(p)
		out.Head = A(0.3 * e, 0, 0.1 * e)
	elseif pose == "Down" then
		local e = ease(p)
		out.Body = CFrame.new(0, -1.5 * e, 0) * A(-0.25 * e, 0, 0.2 * e)
		out.Head = A(-0.7 * e, 0, 0)
		out.Jaw = A(-0.2 * e, 0, 0)
		out.WingR = A(0, 0, -0.5 * e)
		out.WingL = A(0, 0, 0.5 * e)
	end
	return out
end

local function hydraPose(pose, t, p, opts)
	local speed = opts.Enraged and 1.7 or 1
	local tt = t * speed
	local out = {}
	out.Body = CFrame.new(0, sin(tt * 1.3) * 0.2, 0) * A(sin(tt * 0.8) * 0.02, sin(tt * 0.5) * 0.04, 0)
	out.Head1 = A(sin(tt * 1.1) * 0.12, sin(tt * 0.9 + 1) * 0.16, sin(tt * 0.8) * 0.06)
	out.Head2 = A(sin(tt * 1.0 + 2) * 0.1, sin(tt * 0.7 + 2) * 0.12, 0)
	out.Head3 = A(sin(tt * 1.2 + 4) * 0.12, sin(tt * 0.85 + 3) * 0.16, -sin(tt * 0.8) * 0.06)
	if pose == "Windup" then
		local e = ease(p)
		if opts.Attack == "pulse" then
			out.Head1 = A(0.5 * e, 0, -0.3 * e)
			out.Head2 = A(0.55 * e, 0, 0)
			out.Head3 = A(0.5 * e, 0, 0.3 * e)
			out.Body = out.Body * CFrame.new(0, -0.8 * e, 0)
		else
			out.Head1 = A(0.4 * e, 0.2 * e, 0)
			out.Head2 = A(0.45 * e, 0, 0)
			out.Head3 = A(0.4 * e, -0.2 * e, 0)
		end
	elseif pose == "Attack" then
		local s = strike(p, 0.2)
		if opts.Attack == "pulse" then
			out.Head1 = A(0.5 - 0.3 * s, 0, -0.3 - 0.2 * s)
			out.Head2 = A(0.55 - 0.2 * s, 0, 0)
			out.Head3 = A(0.5 - 0.3 * s, 0, 0.3 + 0.2 * s)
			out.Body = out.Body * CFrame.new(0, -1.4 * s, 0)
		else
			out.Head1 = A(0.4 - 0.9 * s, 0.2 - 0.3 * s, 0)
			out.Head2 = A(0.45 - 1.0 * s, 0, 0)
			out.Head3 = A(0.4 - 0.9 * s, -0.2 + 0.3 * s, 0)
			out.Body = out.Body * A(-0.08 * s, 0, 0)
		end
	elseif pose == "Basic" then
		local s = strike(p, 0.3)
		out.Head2 = A(-0.6 * s, 0, 0)
	elseif pose == "Enrage" then
		local e = sin(min(p, 1) * pi)
		out.Head1 = A(0.7 * e, 0.3 * e, -0.3 * e)
		out.Head2 = A(0.8 * e, 0, 0)
		out.Head3 = A(0.7 * e, -0.3 * e, 0.3 * e)
	elseif pose == "Hurt" then
		local e = 1 - ease(p)
		out.Head1 = out.Head1 * A(0.3 * e, 0, 0)
		out.Head2 = out.Head2 * A(0.3 * e, 0, 0)
		out.Head3 = out.Head3 * A(0.3 * e, 0, 0)
	elseif pose == "Down" then
		local e = ease(p)
		out.Body = CFrame.new(0, -2.5 * e, 0) * A(0, 0, 0.15 * e)
		out.Head1 = A(-0.8 * e, 0, -0.4 * e)
		out.Head2 = A(-0.9 * e, 0, 0)
		out.Head3 = A(-0.8 * e, 0, 0.4 * e)
	end
	return out
end

local POSES = { storm_titan = titanPose, lava_golem = golemPose, frost_wyrm = wyrmPose, shadow_hydra = hydraPose }
BossBuilder.Poses = { "Idle", "Windup", "Attack", "Basic", "Enrage", "Hurt", "Down" }
-- default one-shot lengths (seconds) when Progress is not given
local POSE_SECONDS = { Windup = 1.8, Attack = 1.0, Basic = 0.6, Enrage = 1.6, Hurt = 0.35, Down = 1.4 }

local function bulkMove(parts, cfs)
	local ws = workspace
	if ws and ws.BulkMoveTo then
		local ok = pcall(function()
			ws:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if ok then
			return
		end
	end
	for i, part in ipairs(parts) do
		part.CFrame = cfs[i]
	end
end

function BossBuilder.Animate(model, pose, t, opts)
	local rig = typeof(model) == "Instance" and rigs[model]
	if not rig then
		return false
	end
	opts = type(opts) == "table" and opts or {}
	t = tonumber(t) or 0
	local rootCF = opts.CFrame
	if typeof(rootCF) ~= "CFrame" then
		rootCF = rig.RootCF
	end
	rig.RootCF = rootCF
	pose = type(pose) == "string" and pose or "Idle"
	local p = tonumber(opts.Progress)
	if not p then
		local len = POSE_SECONDS[pose]
		p = len and ((t % len) / len) or 0
	end
	p = min(max(p, 0), 1)
	local fn = POSES[rig.BossId]
	local locals = {}
	if fn then
		local ok, result = pcall(fn, pose, t, p, opts)
		if ok and type(result) == "table" then
			locals = result
		end
	end
	for _, j in ipairs(rig.Order) do
		local parentWorld = IDENTITY
		if j.Parent ~= "" and rig.Joints[j.Parent] then
			parentWorld = rig.Joints[j.Parent].World
		end
		local l = locals[j.Name]
		if l then
			j.World = parentWorld * j.PivotCF * l * j.PivotInv
		else
			j.World = parentWorld
		end
	end
	local parts, cfs, rest, owner = rig.Parts, rig.CFs, rig.Rest, rig.Owner
	cfs[1] = rootCF
	for i = 2, #parts do
		cfs[i] = rootCF * owner[i].World * rest[i]
	end
	bulkMove(parts, cfs)
	return true
end

function BossBuilder.SetEnraged(model, on)
	local rig = typeof(model) == "Instance" and rigs[model]
	if not rig then
		return false
	end
	on = on == true
	if rig.Enraged == on then
		return true
	end
	rig.Enraged = on
	local colors = COLORS[rig.BossId] or FALLBACK_COLORS
	for _, entry in ipairs(rig.Glow) do
		if on then
			entry.Part.Color = entry.Color:Lerp(colors.Enrage, entry.Part.Name == "Eye" and 0.85 or 0.6)
		else
			entry.Part.Color = entry.Color
		end
	end
	if rig.Light then
		rig.Light.Color = on and colors.Enrage or colors.Glow
		rig.Light.Brightness = on and 3 or 1.6
	end
	return true
end

-- extra (tests / tools): the part count of a built model
function BossBuilder.PartCount(model)
	local n = 0
	if typeof(model) == "Instance" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n = n + 1
			end
		end
	end
	return n
end

return BossBuilder
