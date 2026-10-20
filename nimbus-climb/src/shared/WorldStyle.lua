-- WorldStyle: the shared art kit of the world (ARCHITECTURE_V3.md "Phase 6" 6.0.2 / 6.0.3 / 6.1 A1, docs/phase6/style.md
-- section 4). Phase 6 = the Phase 4 look again (7aa0df2): bright, cute, colourful voxels in SmoothPlastic, the P4
-- palette (lime grass, cream stone paths, white / light-blue clouds), no realistic textures and no round primitives.
-- Glow stays Neon (gate rings, swirls, gems, lanterns, inlays); water may be Glass. The Part builds here are the
-- fallback + colliders until the Blender meshes (wave 2) dress them. Every world builder (LobbyBuilder, HomeBuilder,
-- ArenaBuilder, DungeonBuilder) builds with these pieces so the world reads as one place. Usable on the server and
-- the client (pure part building; no services, no remotes). Plain Lua 5.1-compatible syntax only.
--
--   WorldStyle.Materials                      name -> Enum.Material. The P4 look: SmoothPlastic for every surface,
--       Neon for glow, Glass for water. The Phase 5 names (Slate, Cobblestone, Brick, Marble, WoodPlanks, Wood, Grass,
--       LeafyGrass, Sand, ClayRoofTiles, RoofShingles, Metal, Fabric) stay as aliases of SmoothPlastic and ForceField
--       as an alias of Neon, so older builder code keeps working and looks P4.
--   WorldStyle.Palette                        the P4 colours (style.md 4), the legacy Phase 5 keys recoloured to their
--       P4 counterparts, Accent.<Name> = the gate / mode colours (Obby Blue, Home Yellow, Dungeon Purple, Ring Gold +
--       Violet, Arena Red, Altar Cyan, Return Green)
--   WorldStyle.Plinth(parent, cf, size, mat, color) -> body, band          a base block + a 0.2-stud band on top
--   WorldStyle.Kerb(parent, cf, length, mat, color) -> kerb, lip           a platform edge (cf on the top surface at
--       the edge, X = along it, LookVector = outward): a 0.4 x 0.8 kerb + a 0.3-stud lip under the top
--   WorldStyle.Chamfer(parent, cf, size, mat, color, cut) -> body, parts    a box with bevelled vertical corners
--   WorldStyle.BuildGate(parent, siteCFrame, spec) -> model, pad, promptPart
--       The P4 round voxel hoop gate family (6.0.3; P4 LobbyBuilder buildPortal / ArenaBuilder buildTrialPortal):
--       siteCFrame = ground CFrame of the gate centre, LookVector toward the plaza (the gate's front, local -Z).
--       spec = { Id, Title, Info, Color (Palette.Accent name | Theme.Neon name | Color3), Glyph = "house" | "cloud" |
--                "torch" | "crown" | "swords" | "bolt", Pad = bool, Name = "Portal_<Id>", Pill = text (optional),
--                Stars = 0..5 (the "cloud" star crest, default 5), Accent = Color3 (the crowned arch's glow) }
--       Shape by glyph: "crown" = the P4 Champion Ring crowned square arch (gold trim, violet glow, crown baked into
--       the voxels); every other glyph = the round hoop: a stone base, two stone pillars with coloured caps and a
--       glowing dot, a chunky pixel ring whose outer band is the gate colour around a white cloud frame, an inner Neon
--       ring, a translucent Neon swirl (Transparency 0.62) and a coloured keystone with two gold gems. Crest on top by
--       glyph: cloud = 5 gold stars on a bar (Obby), swords = crossed swords + shield (Arena), house = a little house
--       (Home), torch = a skull (Dungeon), bolt = a cloud with a lightning bolt (Altar). Voxels are 1 stud, shaded like
--       P4 (Voxel.Shade: _Light tops, _Dark creases), sculpted once per shape and cloned with the gate's palette.
--       Children: the voxel parts (named by key: StoneDark, Stone, Frame, Trim, Glow, Swirl, Gem; Swirl / Glow / Gem
--       never collide), "GlowCore" (invisible, the PrimaryPart, 11.5 up; not named SwirlCore so PortalService keeps the countdown face at the lock wall: PointLight "GateLight" Range 28 Brightness 1.3
--       + ParticleEmitter "Sparkles" Rate 12 drifting toward the plaza), "Crest*" / "Star*" parts, "PromptAnchor"
--       (invisible, front of the opening, 3 up: prompts go here), the BillboardGui "GateTag" (Plate: Title 28 px,
--       Info 20 px, Pill.Label 18 px; anchor 27 studs up, MaxDistance 120). Pad = true: "Pad" (14 x 0.6 x 14, 14 studs
--       in front, walkable; the PortalService zone sits on it) tiled like P4 (a colour rim, a light stone ring, a Neon
--       plus; X for swords, a crown for the arch: "PadTile*" 0.06 thick on top) + two lanterns on its front corners;
--       else "Step" (10 x 0.3 x 6, 6 studs in front). Attributes GateId, Glyph, GateShape ("Hoop" | "Arch").
--       <= 100 parts; the owner adds <= 20 (crown pedestals, torches): every gate <= 120.
-- Extras: WorldStyle.Jitter(color, seed, amount), WorldStyle.Glyphs (the 6x6 patterns), WorldStyle.GlyphRects,
--   WorldStyle.IsWorldMaterial(m), WorldStyle.Saturation(color), WorldStyle.GateSize, WorldStyle.Look = "P4",
--   WorldStyle.Tags.Detail ("NC_Detail": pure decor, the Low graphics setting hides it), WorldStyle.Tags.Exempt
--   ("NC_StyleExempt": pets / tokens / the storm island, skipped by the look audit of p5world_style).

local Shared = script.Parent
local Voxel = require(Shared:WaitForChild("Voxel", 10))
local Theme = require(Shared:WaitForChild("Theme", 10))

local WorldStyle = {}

local rgb = Color3.fromRGB
local floor, max, min, sqrt, abs = math.floor, math.max, math.min, math.sqrt, math.abs
local PI = math.pi

WorldStyle.Look = "P4"
WorldStyle.Tags = { Detail = "NC_Detail", Exempt = "NC_StyleExempt" }

----------------------------------------------------------------------
-- Materials (6.1 A1): SmoothPlastic surfaces, Neon glow, Glass water. The rest are aliases (see the header).
----------------------------------------------------------------------
local SMOOTH = Enum.Material.SmoothPlastic
WorldStyle.Materials = {
	SmoothPlastic = SMOOTH, -- every surface
	Neon = Enum.Material.Neon, -- glow: gate rings, swirls, gems, lanterns, inlays
	Glass = Enum.Material.Glass, -- water, lantern cages, machine domes (translucent)
	-- Phase 5 names, kept so older builder code runs: all P4 SmoothPlastic now (style.md 4: no textures)
	Slate = SMOOTH,
	Cobblestone = SMOOTH,
	Brick = SMOOTH,
	Marble = SMOOTH,
	WoodPlanks = SMOOTH,
	Wood = SMOOTH,
	Grass = SMOOTH,
	LeafyGrass = SMOOTH,
	Sand = SMOOTH,
	ClayRoofTiles = SMOOTH,
	RoofShingles = SMOOTH,
	Metal = SMOOTH,
	Fabric = SMOOTH,
	ForceField = Enum.Material.Neon, -- shimmer sheets become translucent Neon (the P4 swirl)
}

local MATERIAL_SET = {}
for _, m in pairs(WorldStyle.Materials) do
	MATERIAL_SET[m] = true
end

function WorldStyle.IsWorldMaterial(material)
	return MATERIAL_SET[material] == true
end

----------------------------------------------------------------------
-- Palette (style.md 4: big surfaces bright and saturated; the P4 numbers are the reference)
----------------------------------------------------------------------
WorldStyle.Palette = {
	-- the P4 world
	Grass = rgb(108, 186, 86),
	GrassLight = rgb(132, 202, 98),
	GrassDark = rgb(86, 160, 76),
	Hedge = rgb(74, 146, 72),
	Stone = rgb(208, 202, 190), -- cream stone paths
	StoneLight = rgb(226, 221, 209),
	StoneDark = rgb(172, 164, 154),
	StoneEdge = rgb(146, 138, 132), -- path borders
	Sand = rgb(236, 214, 166),
	Plank = rgb(196, 146, 98),
	PlankLight = rgb(214, 166, 114),
	PlankDark = rgb(152, 108, 72),
	Bark = rgb(132, 92, 62),
	Gold = rgb(244, 198, 84),
	GoldDark = rgb(206, 154, 62),
	Iron = rgb(64, 70, 92),
	IronLight = rgb(96, 104, 130),
	Steel = rgb(206, 214, 228),
	Water = rgb(92, 178, 236),
	WaterDeep = rgb(62, 136, 212),
	Blossom = rgb(246, 174, 204),
	Cream = rgb(246, 234, 210),
	Bone = rgb(240, 236, 226),
	RoofBlue = rgb(88, 136, 226),
	RoofRed = rgb(232, 104, 112),
	StarOff = rgb(96, 104, 136),
	Navy = rgb(34, 42, 76),
	-- white / light-blue clouds (never pure white; tops < 249)
	CloudLight = rgb(244, 247, 252),
	Cloud = rgb(232, 238, 249),
	CloudShade = rgb(212, 222, 241),
	Mist = rgb(194, 211, 240),
	MistDark = rgb(170, 190, 228),
	-- the Phase 5 keys, recoloured to their P4 counterparts (older builder code keeps working, looks P4)
	SlateDark = rgb(172, 164, 154),
	Slate = rgb(208, 202, 190),
	SlateLight = rgb(226, 221, 209),
	Marble = rgb(240, 234, 220),
	MarbleShade = rgb(226, 221, 209),
	Cobble = rgb(208, 202, 190),
	Brick = rgb(146, 138, 132),
	WoodPlanks = rgb(196, 146, 98),
	Wood = rgb(132, 92, 62),
	LeafyGrass = rgb(74, 146, 72),
	Roof = rgb(88, 136, 226),
	Metal = rgb(244, 198, 84), -- gold trim
	Glass = rgb(150, 206, 244),
	Fabric = rgb(246, 174, 204),
	Lantern = rgb(255, 214, 140), -- warm lights
	CloudTop = rgb(244, 247, 252),
	CloudSide = rgb(232, 238, 249),
	CloudUnder = rgb(194, 211, 240),
	-- gate / mode colours (6.0.3; the P4 difficulty / Trial / Ring hues; Palette.Accent wins over Theme.Neon)
	Accent = {
		Yellow = rgb(246, 196, 60), -- Home
		Blue = rgb(96, 160, 224), -- Obby (the P4 Medium blue)
		Purple = rgb(150, 110, 220), -- Dungeon (the P4 Saint purple)
		Gold = rgb(250, 190, 56), -- Champion Ring trim
		Violet = rgb(156, 96, 238), -- Champion Ring glow and gems
		Red = rgb(222, 74, 80), -- Arena (the P4 Trial red)
		Cyan = rgb(64, 196, 222), -- Storm Altar
		Pink = rgb(234, 120, 170),
		Green = rgb(96, 190, 140), -- the arena's Return gate (the P4 Easy green)
	},
	TagPlate = rgb(20, 24, 52), -- the dark navy tag card
	TagInfo = rgb(214, 220, 255),
}

-- HSV saturation of a Color3 (0..1).
function WorldStyle.Saturation(color)
	local r, g, b = color.R, color.G, color.B
	local hi = max(r, g, b)
	if hi <= 0 then
		return 0
	end
	return (hi - min(r, g, b)) / hi
end

-- Deterministic +-amount RGB jitter (default 6): tile checkers that never read as one flat colour.
function WorldStyle.Jitter(color, seed, amount)
	amount = amount or 6
	local s = tonumber(seed) or 0
	local d = floor((Voxel.Hash(s, 17, 3, 91) * 2 - 1) * amount + 0.5)
	local function ch(c)
		return max(0, min(255, floor(c * 255 + 0.5) + d))
	end
	return rgb(ch(color.R), ch(color.G), ch(color.B))
end

----------------------------------------------------------------------
-- Pieces
----------------------------------------------------------------------
local function solidProps(name)
	return { Name = name, CanCollide = true, CanQuery = true, CanTouch = false }
end

local function decoProps(name)
	return { Name = name, CanCollide = false, CanQuery = false, CanTouch = false }
end

function WorldStyle.Plinth(parent, cf, size, mat, color)
	mat = mat or SMOOTH
	local body = Voxel.Box(parent, cf, size, color or WorldStyle.Palette.StoneDark, mat, solidProps("Plinth"))
	local band = Voxel.Box(
		parent,
		cf * CFrame.new(0, size.Y * 0.5 - 0.1, 0),
		Vector3.new(size.X + 0.3, 0.2, size.Z + 0.3),
		WorldStyle.Palette.StoneLight,
		SMOOTH,
		solidProps("PlinthBand")
	)
	return body, band
end

function WorldStyle.Kerb(parent, cf, length, mat, color)
	length = tonumber(length) or 4
	local kerb = Voxel.Box(
		parent,
		cf * CFrame.new(0, 0.2, 0),
		Vector3.new(length, 0.4, 0.8),
		color or WorldStyle.Palette.StoneEdge,
		mat or SMOOTH,
		solidProps("Kerb")
	)
	-- the lip: 0.3 tall, just under the top surface, 0.3 beyond the kerb's outer face (-Z local = outward)
	local lip = Voxel.Box(
		parent,
		cf * CFrame.new(0, -0.25, -0.3),
		Vector3.new(length + 0.2, 0.3, 1.0),
		WorldStyle.Palette.StoneDark,
		SMOOTH,
		decoProps("KerbLip")
	)
	return kerb, lip
end

function WorldStyle.Chamfer(parent, cf, size, mat, color, cut)
	cut = tonumber(cut) or 0.6
	cut = min(cut, size.X * 0.25, size.Z * 0.25)
	mat = mat or SMOOTH
	color = color or WorldStyle.Palette.StoneLight
	local parts = {}
	local body = Voxel.Box(parent, cf, Vector3.new(size.X - 2 * cut, size.Y, size.Z), color, mat, solidProps("Chamfer"))
	parts[1] = body
	parts[2] = Voxel.Box(parent, cf, Vector3.new(size.X, size.Y, size.Z - 2 * cut), color, mat, solidProps("ChamferX"))
	-- a square post of side cut*sqrt(2), turned 45 degrees, centred on each re-entrant corner of the cross:
	-- its outer face runs from (X/2, Z/2 - cut) to (X/2 - cut, Z/2), the bevel
	local side = cut * sqrt(2)
	local hx, hz = size.X * 0.5 - cut, size.Z * 0.5 - cut
	local signs = { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } }
	for i, s in ipairs(signs) do
		parts[#parts + 1] = Voxel.Box(
			parent,
			cf * CFrame.new(s[1] * hx, 0, s[2] * hz) * CFrame.Angles(0, PI / 4, 0),
			Vector3.new(side, size.Y, side),
			color,
			mat,
			solidProps("ChamferCorner" .. i)
		)
	end
	return body, parts
end

----------------------------------------------------------------------
-- Glyphs: 6 x 6, top row first ("#" = lit)
----------------------------------------------------------------------
WorldStyle.Glyphs = {
	house = { "..##..", ".####.", "######", ".#..#.", ".#..#.", ".####." },
	cloud = { "......", "..##..", ".####.", "######", ".####.", "......" },
	torch = { "...#..", "..##..", "..###.", ".####.", "..##..", "..##.." },
	crown = { "#.##.#", "#.##.#", "######", "######", ".####.", "......" },
	swords = { "#....#", ".#..#.", "..##..", "..##..", ".#..#.", "#....#" },
	bolt = { "...##.", "..##..", ".####.", "..##..", ".##...", ".#...." },
}

-- Greedy rectangles of a glyph: runs per row, merged downwards while identical. Deterministic order.
local function glyphRects(rows)
	local rects = {}
	local open = {} -- key "x0:x1" -> rect still growing
	for y = 1, #rows do
		local row = rows[y]
		local nextOpen = {}
		local x = 1
		while x <= #row do
			if row:sub(x, x) == "#" then
				local x1 = x
				while x1 + 1 <= #row and row:sub(x1 + 1, x1 + 1) == "#" do
					x1 = x1 + 1
				end
				local key = x .. ":" .. x1
				local r = open[key]
				if r then
					r.Y1 = y
				else
					r = { X0 = x, X1 = x1, Y0 = y, Y1 = y }
					rects[#rects + 1] = r
				end
				nextOpen[key] = r
				x = x1 + 1
			else
				x = x + 1
			end
		end
		open = nextOpen
	end
	return rects
end
WorldStyle.GlyphRects = glyphRects

-- One template per glyph (and orientation): a Model of Neon cells, built once and cloned (6.2).
-- Vertical = the medallion face (cells in X/Y, `depth` thick along Z); flat = the pad inlay (cells in X/Z).
local glyphCache = {}
local function glyphTemplate(glyph, cell, depth, flat)
	local key = glyph .. "|" .. cell .. "|" .. depth .. "|" .. tostring(flat)
	local t = glyphCache[key]
	if t then
		return t
	end
	local rows = WorldStyle.Glyphs[glyph] or WorldStyle.Glyphs.cloud
	t = Instance.new("Model")
	t.Name = "Glyph"
	for i, r in ipairs(glyphRects(rows)) do
		local w = (r.X1 - r.X0 + 1) * cell
		local h = (r.Y1 - r.Y0 + 1) * cell
		local cx = ((r.X0 + r.X1) * 0.5 - 3.5) * cell
		local cy = (3.5 - (r.Y0 + r.Y1) * 0.5) * cell
		local size, pos
		if flat then
			-- top row toward -Z (the far side seen from the plaza is the glyph's top)
			size, pos = Vector3.new(w, depth, h), CFrame.new(cx, 0, -cy)
		else
			size, pos = Vector3.new(w, h, depth), CFrame.new(cx, cy, 0)
		end
		local p = Voxel.Box(t, pos, size, WorldStyle.Palette.Accent.Blue, WorldStyle.Materials.Neon, decoProps("GlyphCell" .. i))
		p.CastShadow = false
	end
	glyphCache[key] = t
	return t
end

-- Places a clone of the glyph template at `cf`, coloured `color`.
local function placeGlyph(parent, glyph, cf, color, cell, depth, flat)
	local model = glyphTemplate(glyph, cell, depth, flat):Clone()
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			p.CFrame = cf * p.CFrame
			p.Color = color
		end
	end
	model.Parent = parent
	return model
end

----------------------------------------------------------------------
-- The pixel tag (World text rule): constant on-screen size, compact navy plate, neon border
----------------------------------------------------------------------
local TAG_TITLE, TAG_INFO, TAG_PILL = 28, 20, 18

local function tagLabel(parent, name, text, role, size, color, order)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text or ""
	label.Font = Theme.Fonts[role] or Theme.Fonts.Body
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	label.TextWrapped = false
	label.Size = UDim2.fromOffset(0, size + 4)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.LayoutOrder = order
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TextOutline"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = (Theme.Colors and Theme.Colors.Ink) or rgb(26, 32, 64)
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function buildTag(adornee, lift, spec, color)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GateTag"
	gui.Size = UDim2.fromOffset(420, 150)
	gui.SizeOffset = Vector2.new(0, 0.5) -- the plate grows upwards from the anchor
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = false
	gui.Adornee = adornee
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.new(0.5, 0, 1, 0)
	plate.Size = UDim2.fromOffset(0, 0)
	plate.AutomaticSize = Enum.AutomaticSize.XY
	plate.BackgroundColor3 = WorldStyle.Palette.TagPlate
	plate.BackgroundTransparency = 0.08
	plate.BorderSizePixel = 0
	plate.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = plate
	local border = Instance.new("UIStroke")
	border.Name = "Border"
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = color
	border.Thickness = 3
	border.Parent = plate
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = plate
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = plate
	tagLabel(plate, "Title", spec.Title or spec.Id or "", "Heading", TAG_TITLE, rgb(255, 255, 255), 1)
	local info = tagLabel(plate, "Info", spec.Info or "", "Body", TAG_INFO, WorldStyle.Palette.TagInfo, 2)
	info.Visible = (spec.Info or "") ~= ""
	-- the pill: the builder's status line (party, board, record); hidden while empty
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.BackgroundColor3 = color:Lerp(rgb(0, 0, 0), 0.55)
	pill.BorderSizePixel = 0
	pill.Size = UDim2.fromOffset(0, TAG_PILL + 8)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.LayoutOrder = 3
	pill.Visible = (spec.Pill or "") ~= ""
	pill.Parent = plate
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = pill
	local pp = Instance.new("UIPadding")
	pp.PaddingLeft = UDim.new(0, 10)
	pp.PaddingRight = UDim.new(0, 10)
	pp.Parent = pill
	tagLabel(pill, "Label", spec.Pill or "", "Label", TAG_PILL, rgb(255, 255, 255), 1)
	gui.Parent = adornee
	return gui
end

----------------------------------------------------------------------
-- The gate family (6.0.3): the P4 round voxel hoop + the P4 crowned arch, a crest per mode
----------------------------------------------------------------------
WorldStyle.GateSize = Vector3.new(23, 26, 5) -- the P4 hoop: a 23-voxel base, crest tops ~26, 5 deep

local GATE = {
	PadDistance = 14, -- pad centre in front of the gate centre (gate r 118, pad r 104)
	TagLift = 27, -- the tag's anchor height (just over the crests)
	SwirlY = 11.5, -- the swirl's centre (the ring is centred 11 voxels up, voxel centres 0.5 above the site)
	HoopParts = 80, -- MaxParts of the merged hoop voxels: ~76 boxes, the shade variants fold away (every gate <= 120)
	ArchParts = 56,
}
local NEON = Enum.Material.Neon
local WHITE = rgb(255, 255, 255)
-- ring radii (voxel units from the ring centre 11 up): swirl < Glow <= neon ring < Inner <= white frame < Band <=
-- coloured band < Outer
local RING = { Glow = 5.7, Inner = 6.6, Band = 8.6, Outer = 9.6 }
local KEEP = { "Stone", "StoneDark", "Frame", "Trim", "Glow", "Swirl", "Gem" }

-- Inclusive integer box of voxels.
local function vxFill(g, x0, x1, y0, y1, z0, z1, key)
	for y = y0, y1 do
		for x = x0, x1 do
			for z = z0, z1 do
				Voxel.Set(g, x, y, z, key)
			end
		end
	end
end

-- Rounded rectangle prism centred on (cx, cz): sx by sz voxels, corner radius `round` (P4 VX.RoundRect).
local function vxRoundRect(g, cx, cz, sx, sz, round, y0, y1, key)
	local hx, hz = sx / 2, sz / 2
	round = max(0, min(round, hx, hz))
	for y = y0, y1 do
		for x = floor(cx - hx) - 1, math.ceil(cx + hx) + 1 do
			for z = floor(cz - hz) - 1, math.ceil(cz + hz) + 1 do
				local qx, qz = abs(x - cx) - (hx - round), abs(z - cz) - (hz - round)
				local ox, oz = max(qx, 0), max(qz, 0)
				local d = sqrt(ox * ox + oz * oz) + min(max(qx, qz), 0)
				if d <= round then
					Voxel.Set(g, x, y, z, key)
				end
			end
		end
	end
end

-- The round hoop (P4 LobbyBuilder gateBoxes / ArenaBuilder gateHoop; x across, y up, -z = the front)
local function hoopVoxels(g)
	vxRoundRect(g, 0, 0, 22, 5, 1.5, 0, 0, "StoneDark")
	vxRoundRect(g, 0, 0, 20, 4, 1.2, 1, 1, "Stone")
	for _, s in ipairs({ -1, 1 }) do
		vxRoundRect(g, s * 9, 0, 3, 3.4, 0.8, 2, 10, "Stone")
		vxRoundRect(g, s * 9, 0, 4, 4.2, 1, 11, 11, "Trim")
		vxFill(g, s * 9, s * 9, 12, 13, 0, 0, "Glow")
		vxFill(g, s * 9, s * 9, 3, 3, -2, -2, "Trim")
	end
	-- the ring (P4: a torus R 7.6 / 1.6 thick): a 3-voxel-deep pixel annulus, the white cloud frame inside the
	-- stepped outer band in the gate colour, a thin Neon ring at its inner edge and the swirl disc in the middle.
	-- Extruded (every depth layer the same) so the greedy merge keeps it near 60 boxes instead of 110.
	for y = 1, 21 do
		for x = -10, 10 do
			local dy = y - 11
			local r = sqrt(x * x + dy * dy)
			if r >= RING.Inner and r < RING.Outer then
				local key = (r >= RING.Band) and "Trim" or "Frame"
				vxFill(g, x, x, y, y, -1, 1, key)
			elseif r >= RING.Glow and r < RING.Inner then
				Voxel.Set(g, x, y, 0, "Glow")
			elseif r < RING.Glow and Voxel.Get(g, x, y, 0) == nil then
				Voxel.Set(g, x, y, 0, "Swirl")
			end
		end
	end
	-- the keystone with two gold gems facing the plaza
	vxRoundRect(g, 0, 0, 4, 3, 0.8, 19, 20, "Trim")
	Voxel.Set(g, 0, 20, -2, "Gem")
	Voxel.Set(g, 0, 19, -2, "Gem")
end

-- The crowned square arch (P4 ArenaBuilder Ring.gateVoxels): gold bands, a glowing frame around the swirl, violet
-- gems up the pillars and a big gold crown on the lintel
local function archVoxels(g)
	vxRoundRect(g, 0, 0, 22, 5, 1.5, 0, 0, "StoneDark")
	vxRoundRect(g, 0, 0, 20, 4, 1.2, 1, 1, "Stone")
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = min(sx * 7, sx * 9), max(sx * 7, sx * 9)
		vxFill(g, x0, x1, 2, 16, -1, 1, "Stone")
		vxFill(g, x0 - 1, x1 + 1, 2, 2, -2, 2, "Trim")
		vxFill(g, x0 - 1, x1 + 1, 15, 15, -2, 2, "Trim")
		vxFill(g, sx * 6, sx * 6, 3, 14, 0, 0, "Glow")
		for _, y in ipairs({ 6, 9, 12 }) do
			Voxel.Set(g, sx * 8, y, -2, "Gem")
		end
	end
	vxFill(g, -10, 10, 17, 17, -1, 1, "Trim")
	vxFill(g, -10, 10, 18, 18, -1, 1, "Stone")
	vxFill(g, -5, 5, 16, 16, 0, 0, "Glow")
	vxFill(g, -5, 5, 3, 15, 0, 0, "Swirl")
	-- the crown: a band with a row of gems, three big points (the middle one tallest), two small ones, gems on the tips
	vxFill(g, -7, 7, 19, 20, -1, 1, "Trim")
	for _, x in ipairs({ -4, 0, 4 }) do
		Voxel.Set(g, x, 20, -2, "Gem")
	end
	for _, pt in ipairs({ { -6, 22 }, { 0, 23 }, { 6, 22 } }) do
		vxFill(g, pt[1] - 1, pt[1] + 1, 21, 21, -1, 1, "Trim")
		vxFill(g, pt[1], pt[1], 22, pt[2], -1, 1, "Trim")
		Voxel.Set(g, pt[1], pt[2] + 1, 0, "Gem")
	end
	for _, x in ipairs({ -3, 3 }) do
		Voxel.Set(g, x, 21, 0, "Trim")
		Voxel.Set(g, x, 22, 0, "Gem")
	end
end

-- The gate palette (P4 gatePalette): stone light pillars, a white cloud frame, the trim in the gate colour, Neon glow /
-- swirl / gems
local function gatePalette(trim, glow, gem)
	local P = WorldStyle.Palette
	return {
		Stone = P.StoneLight,
		StoneDark = P.Stone,
		Frame = P.CloudLight,
		Puff = P.Cloud,
		Trim = trim,
		Glow = { Color = glow, Material = NEON },
		Swirl = { Color = glow:Lerp(WHITE, 0.35), Material = NEON, Transparency = 0.62 },
		Gem = { Color = gem, Material = NEON },
	}
end

-- sculpted, shaded and merged once per shape; every gate builds the same boxes with its own palette
local boxCache = {}
local function gateBoxes(shape)
	if boxCache[shape] then
		return boxCache[shape]
	end
	local g = Voxel.NewGrid(24)
	if shape == "Arch" then
		archVoxels(g)
	else
		hoopVoxels(g)
	end
	Voxel.Shade(g, { Skip = { Glow = true, Swirl = true, Gem = true }, Smooth = 1, Seed = 8 })
	local sample = rgb(120, 180, 140)
	boxCache[shape] = Voxel.Merge(g, {
		Palette = gatePalette(sample, sample, WorldStyle.Palette.Gold),
		MaxParts = (shape == "Arch") and GATE.ArchParts or GATE.HoopParts,
		Keep = KEEP,
	})
	return boxCache[shape]
end

local function accentOf(spec)
	local c = spec.Color
	if typeof(c) == "Color3" then
		return c
	end
	if type(c) == "string" then
		if WorldStyle.Palette.Accent[c] then
			return WorldStyle.Palette.Accent[c]
		end
		local neon = Theme.Neon
		if type(neon) == "table" and typeof(neon[c]) == "Color3" then
			return neon[c]
		end
	end
	return WorldStyle.Palette.Accent.Blue
end

-- one anchored block in the gate's frame
local function block(model, name, cf, size, color, opts)
	opts = opts or {}
	local p = Voxel.Box(model, cf, size, color, opts.Material or SMOOTH, {
		Name = name,
		Transparency = opts.Transparency or 0,
		CanCollide = opts.Collide == true,
		CanQuery = opts.Collide == true,
		CanTouch = false,
	})
	p.CastShadow = opts.Shadow == true
	return p
end

----------------------------------------------------------------------
-- Crests (P4 star crest / Trial sword crest; house, skull and storm bolt in the same toy style). The hoop's keystone
-- top is 21 studs up; every crest stays under ~26 (the tag's anchor is 27).
----------------------------------------------------------------------
local Crest = {}

function Crest.post(m, site)
	block(m, "CrestPost", site * CFrame.new(0, 21.6, 0), Vector3.new(0.8, 1.3, 0.6), WorldStyle.Palette.GoldDark)
end

-- cloud (Obby): five gold star gems on a bar (lit = Neon gold, unlit = dim stone); spec.Stars lights the first n
function Crest.cloud(m, site, color, spec)
	local P = WorldStyle.Palette
	local n = 5
	local lit = floor(tonumber(spec.Stars) or n)
	lit = max(0, min(n, lit))
	block(m, "StarPost", site * CFrame.new(0, 21.6, 0), Vector3.new(0.8, 1.3, 0.6), P.GoldDark)
	block(m, "StarBar", site * CFrame.new(0, 22.45, 0), Vector3.new((n - 1) * 2.6 + 1.2, 0.5, 0.5), P.GoldDark)
	for s = 1, n do
		local gx = ((n + 1) / 2 - s) * 2.6 -- gate +X is the viewer's left: lit stars first
		local on = s <= lit
		block(m, on and "StarGem" or "StarGemOff", site * CFrame.new(gx, 23.6, 0) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(1.5, 1.5, 0.8), on and P.Gold or P.StarOff, { Material = on and NEON or SMOOTH })
	end
end

-- swords (Arena): a shield in the gate colour with a gold rim and two crossed steel swords (P4 Trial crest)
function Crest.swords(m, site, color)
	local P = WorldStyle.Palette
	Crest.post(m, site)
	block(m, "CrestShield", site * CFrame.new(0, 23.4, 0), Vector3.new(2.4, 2.6, 0.7), color:Lerp(P.Navy, 0.2))
	block(m, "CrestShieldRim", site * CFrame.new(0, 23.4, 0.15), Vector3.new(2.9, 3.1, 0.5), P.Gold)
	for _, s in ipairs({ -1, 1 }) do
		local scf = site * CFrame.new(0, 23.6, -0.5) * CFrame.Angles(0, 0, math.rad(s * 42))
		block(m, "CrestBlade", scf * CFrame.new(0, 0.6, 0), Vector3.new(0.45, 5, 0.2), P.Steel)
		block(m, "CrestGuard", scf * CFrame.new(0, -1.9, 0), Vector3.new(1.5, 0.35, 0.3), P.Gold)
		block(m, "CrestGrip", scf * CFrame.new(0, -2.5, 0), Vector3.new(0.35, 0.9, 0.3), P.GoldDark)
	end
end

-- house (Home): a little cream house with a stepped coral roof, a door, two lit windows and a chimney
function Crest.house(m, site)
	local P = WorldStyle.Palette
	Crest.post(m, site)
	block(m, "CrestHouse", site * CFrame.new(0, 23.3, 0), Vector3.new(3.8, 2.4, 1.2), P.Cream)
	block(m, "CrestRoof", site * CFrame.new(0, 24.85, 0), Vector3.new(4.8, 0.7, 1.5), P.RoofRed)
	block(m, "CrestRoofTop", site * CFrame.new(0, 25.5, 0), Vector3.new(2.8, 0.6, 1.5), P.RoofRed:Lerp(WHITE, 0.15))
	block(m, "CrestChimney", site * CFrame.new(1.5, 25.5, 0.25), Vector3.new(0.6, 1.0, 0.6), P.PlankDark)
	block(m, "CrestDoor", site * CFrame.new(0, 22.85, -0.65), Vector3.new(1, 1.4, 0.15), P.Plank)
	for _, s in ipairs({ -1, 1 }) do
		block(m, "CrestWindow", site * CFrame.new(s * 1.25, 23.7, -0.65), Vector3.new(0.7, 0.7, 0.15), P.Lantern, { Material = NEON })
	end
end

-- torch (Dungeon): a cute bone skull with glowing eyes in the gate colour over two crossed bones; its jaw sits on
-- the keystone
function Crest.torch(m, site, color)
	local P = WorldStyle.Palette
	for _, s in ipairs({ -1, 1 }) do
		block(m, "CrestBone", site * CFrame.new(0, 23.4, 0.5) * CFrame.Angles(0, 0, math.rad(s * 45)), Vector3.new(0.55, 5.4, 0.4), P.StoneLight)
	end
	block(m, "CrestSkull", site * CFrame.new(0, 23.6, 0), Vector3.new(3.6, 2.8, 1.5), P.Bone)
	block(m, "CrestSkullTop", site * CFrame.new(0, 25.25, 0), Vector3.new(2.6, 0.5, 1.3), P.Bone)
	block(m, "CrestJaw", site * CFrame.new(0, 21.8, 0), Vector3.new(2.4, 0.8, 1.3), P.Bone)
	for _, s in ipairs({ -1, 1 }) do
		block(m, "CrestEye", site * CFrame.new(s * 0.8, 23.75, -0.77), Vector3.new(0.9, 0.9, 0.12), color, { Material = NEON })
	end
	block(m, "CrestNose", site * CFrame.new(0, 22.8, -0.77), Vector3.new(0.45, 0.45, 0.12), P.Navy)
end

-- bolt (Storm Altar): a puffy little storm cloud with a misty underside and a gold Neon lightning bolt on its face,
-- striking down out of it
function Crest.bolt(m, site)
	local P = WorldStyle.Palette
	block(m, "CrestPost", site * CFrame.new(0, 21.85, 0), Vector3.new(0.8, 1.7, 0.6), WorldStyle.Palette.GoldDark)
	block(m, "CrestCloudBase", site * CFrame.new(0, 22.9, 0), Vector3.new(4.4, 0.4, 1.3), P.Mist)
	block(m, "CrestCloud", site * CFrame.new(0, 23.9, 0), Vector3.new(5.6, 1.6, 1.4), P.CloudLight)
	block(m, "CrestCloudTop", site * CFrame.new(-0.6, 25.1, 0), Vector3.new(3.2, 0.8, 1.3), P.CloudLight)
	block(m, "CrestCloudPuff", site * CFrame.new(1.5, 24.95, 0), Vector3.new(2, 0.5, 1.2), P.Cloud)
	local bolt = rgb(252, 214, 72)
	block(m, "CrestBolt", site * CFrame.new(0.5, 24.3, -0.8) * CFrame.Angles(0, 0, math.rad(-28)), Vector3.new(0.7, 1.4, 0.2), bolt, { Material = NEON })
	block(m, "CrestBolt", site * CFrame.new(0.1, 23.65, -0.8), Vector3.new(1.4, 0.45, 0.2), bolt, { Material = NEON })
	block(m, "CrestBolt", site * CFrame.new(-0.3, 22.95, -0.8) * CFrame.Angles(0, 0, math.rad(-28)), Vector3.new(0.6, 1.4, 0.2), bolt, { Material = NEON })
end

----------------------------------------------------------------------
-- The ready pad (P4): a 14 x 14 tiled plate, a colour rim, a light stone ring, a Neon plus (X for swords, a crown
-- for the arch), and two lanterns on its front corners
----------------------------------------------------------------------
local function padInlay(kind, ci, ck)
	local ai, ak = abs(ci), abs(ck)
	if kind == "swords" then
		return abs(ai - ak) < 0.6 and ai <= 4
	elseif kind == "crown" then
		-- +k points at the gate: the crown's points
		if (ck == -2.5 or ck == -1.5) and ai <= 3 then
			return true
		end
		return (ai == 0.5 and ck >= -0.5 and ck <= 2.5) or (ai == 2.5 and ck >= -0.5 and ck <= 1.5)
	end
	return ai + ak <= 2.5
end

local padCache = {}
local function padBoxes(kind)
	if padCache[kind] then
		return padCache[kind]
	end
	local g = Voxel.NewGrid(14)
	for i = -7, 6 do
		for k = -7, 6 do
			local ring = min(i + 7, 6 - i, k + 7, 6 - k)
			local key = nil
			-- the pad itself is the light stone ring; one Stone tile covers the middle, the inlay lies on top of it
			if ring == 0 then
				key = "Trim"
			elseif padInlay(kind, i + 0.5, k + 0.5) then
				key = "Glow"
			end
			if key then
				Voxel.Set(g, i, 0, k, key)
			end
		end
	end
	padCache[kind] = Voxel.Merge(g, {})
	return padCache[kind]
end

local function buildPad(model, site, kind, trim, glow)
	local P = WorldStyle.Palette
	local padCF = site * CFrame.new(0, 0, -GATE.PadDistance) -- ground under the pad centre
	local pad = Voxel.Box(model, padCF * CFrame.new(0, 0.3, 0), Vector3.new(14, 0.6, 14), P.StoneLight, SMOOTH, { Name = "Pad", CanCollide = true, CanQuery = true, CanTouch = false })
	pad.CastShadow = false
	block(model, "PadTileStone", padCF * CFrame.new(0, 0.63, 0), Vector3.new(10, 0.06, 10), P.Stone)
	for _, b in ipairs(padBoxes(kind)) do
		local key = b.Key
		local w, d = b.X1 - b.X0 + 1, b.Z1 - b.Z0 + 1
		local cx, cz = (b.X0 + b.X1) * 0.5 + 0.5, (b.Z0 + b.Z1) * 0.5 + 0.5
		local glowTile = key == "Glow"
		-- the inlay pokes 0.02 over the Stone tile (no z-fighting); the rim is level with it
		block(model, "PadTile" .. key, padCF * CFrame.new(cx, glowTile and 0.64 or 0.63, cz), Vector3.new(w, glowTile and 0.08 or 0.06, d), glowTile and glow or trim, { Material = glowTile and NEON or SMOOTH })
	end
	-- lanterns on the two front corners (away from the gate)
	for _, sx in ipairs({ -1, 1 }) do
		local base = padCF * CFrame.new(sx * 7.9, 0, -7.9)
		block(model, "LanternPost", base * CFrame.new(0, 1.6, 0), Vector3.new(0.7, 3.2, 0.7), P.Iron, { Collide = true })
		block(model, "LanternCap", base * CFrame.new(0, 3.35, 0), Vector3.new(1.1, 0.3, 1.1), P.Iron)
		block(model, "LanternGlow", base * CFrame.new(0, 3.95, 0), Vector3.new(0.9, 0.9, 0.9), glow, { Material = NEON })
	end
	return pad
end

----------------------------------------------------------------------
-- Phase 6 (art-gates, contract 6.0.3 / A7): the Blender gate meshes (blender/kit/props/gates.py, keys gate_<kind>).
-- BuildGate tags the gate model with MeshLibrary.Tag; once the key's asset is ready a client Dresses it: the voxels
-- named in GATE_MESH_HIDE (stone, cloud frame, coloured trim, crest bodies) go transparent locally and the mesh takes
-- their place. Every other part stays visible (ML_Keep): the Neon glow ring / swirl / gems / star gems / crest eyes,
-- windows and bolt (PortalFxController animates them), the pad, the lanterns, the invisible anchors, and whatever a
-- builder adds to the gate later (torches, pedestals: the keep list follows DescendantAdded on the server). With
-- empty MeshIds the tag changes nothing.
----------------------------------------------------------------------
WorldStyle.GateMeshKeys = { cloud = "gate_obby", crown = "gate_ring", swords = "gate_arena", torch = "gate_dungeon", house = "gate_home", bolt = "gate_altar" }
WorldStyle.GATE_MESH_HIDE = {
	Stone = true, StoneDark = true, Frame = true, Trim = true,
	StarPost = true, StarBar = true, CrestPost = true,
	CrestShield = true, CrestShieldRim = true, CrestBlade = true, CrestGuard = true, CrestGrip = true,
	CrestHouse = true, CrestRoof = true, CrestRoofTop = true, CrestChimney = true, CrestDoor = true,
	CrestBone = true, CrestSkull = true, CrestSkullTop = true, CrestJaw = true, CrestNose = true,
	CrestCloudBase = true, CrestCloud = true, CrestCloudTop = true, CrestCloudPuff = true,
}

local meshLib = nil
local function meshLibrary()
	if meshLib == nil then
		meshLib = false
		local mod = Shared:FindFirstChild("MeshLibrary")
		if mod then
			local ok, lib = pcall(require, mod)
			if ok and type(lib) == "table" and type(lib.Tag) == "function" then
				meshLib = lib
			end
		end
	end
	return meshLib or nil
end

-- the mesh key of a gate: the arch is gate_ring; a hoop takes its crest's key (an unknown glyph wears the stars)
function WorldStyle.GateMeshKey(shape, glyph)
	if shape == "Arch" then
		return "gate_ring"
	end
	if glyph == "crown" or not WorldStyle.GateMeshKeys[glyph] then
		return "gate_obby"
	end
	return WorldStyle.GateMeshKeys[glyph]
end

local function keepList(keep)
	local names = {}
	for name in pairs(keep) do
		names[#names + 1] = name
	end
	table.sort(names)
	return table.concat(names, ",")
end

-- model pivot = GlowCore (SwirlY up the site): ML_Offset puts the mesh origin back on the site
local function tagGateMesh(model, key, color, stars)
	local ML = meshLibrary()
	if not ML then
		return
	end
	local hide = WorldStyle.GATE_MESH_HIDE
	local keep = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not hide[d.Name] then
			keep[d.Name] = true
		end
	end
	ML.Tag(model, key, { Primary = color, Stars = stars, Offset = CFrame.new(0, -GATE.SwirlY, 0) }, keep)
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and not hide[d.Name] and not keep[d.Name] and model:GetAttribute("ML_DressKey") == key then
			keep[d.Name] = true
			model:SetAttribute("ML_Keep", keepList(keep))
		end
	end)
end

local function popSize(maxSize)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, maxSize),
		NumberSequenceKeypoint.new(1, 0),
	})
end

function WorldStyle.BuildGate(parent, siteCFrame, spec)
	spec = spec or {}
	local id = tostring(spec.Id or "Gate")
	local color = accentOf(spec)
	local glyph = WorldStyle.Glyphs[spec.Glyph] and spec.Glyph or "cloud"
	local shape = (spec.Shape == "Arch" or spec.Shape == "Hoop") and spec.Shape or ((glyph == "crown") and "Arch" or "Hoop")
	local P = WorldStyle.Palette
	-- level the site: gates always stand upright, facing the site's horizontal look direction
	local look = siteCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local site = CFrame.lookAt(siteCFrame.Position, siteCFrame.Position + flat.Unit)

	local model = Instance.new("Model")
	model.Name = spec.Name or ("Portal_" .. id)
	model:SetAttribute("GateId", id)
	model:SetAttribute("Glyph", glyph)
	model:SetAttribute("GateShape", shape)

	-- the arch glows violet under its gold trim (P4 Champion Ring); the hoop glows in its own colour
	local glow = color
	local gem = P.Gold
	if shape == "Arch" then
		glow = (typeof(spec.Accent) == "Color3") and spec.Accent or P.Accent.Violet
		gem = glow:Lerp(WHITE, 0.2)
	end
	Voxel.BuildBoxes(gateBoxes(shape), {
		VoxelSize = 1,
		Palette = gatePalette(color, glow, gem),
		CFrame = site * CFrame.new(0, 0.5, 0),
		Model = model,
		CanCollide = true,
		CanQuery = true,
	})
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and (d.Name == "Swirl" or d.Name == "Glow" or d.Name == "Gem" or d.Name == "Puff") then
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	if shape == "Hoop" then
		local crest = Crest[glyph] or Crest.cloud
		crest(model, site, color, spec)
	end

	-- the swirl's light and sparkles drifting out toward the pad (an invisible core: the PrimaryPart)
	local core = block(model, "GlowCore", site * CFrame.new(0, GATE.SwirlY, 0), Vector3.new(9, 9, 0.4), glow, { Transparency = 1 })
	local light = Instance.new("PointLight")
	light.Name = "GateLight"
	light.Range = 28
	light.Brightness = 1.3
	light.Color = glow
	light.Shadows = false
	light.Parent = core
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 12
	sparkles.Lifetime = NumberRange.new(1.4, 2.2)
	sparkles.Speed = NumberRange.new(1.5, 3.5)
	sparkles.Size = popSize(0.9)
	sparkles.Color = ColorSequence.new(glow:Lerp(WHITE, 0.5), (shape == "Arch") and color or glow)
	sparkles.LightEmission = 0.6
	sparkles.LightInfluence = 0
	sparkles.EmissionDirection = Enum.NormalId.Front
	sparkles.SpreadAngle = Vector2.new(30, 30)
	sparkles.Parent = core

	-- the prompt anchor: invisible, in front of the opening at chest height
	local promptPart = block(model, "PromptAnchor", site * CFrame.new(0, 3.5, -2.8), Vector3.new(2, 2, 1), P.Stone, { Transparency = 1 })

	-- pad (Pad = true) or a step
	local pad
	if spec.Pad then
		local kind = (shape == "Arch") and "crown" or ((glyph == "swords") and "swords" or "plus")
		pad = buildPad(model, site, kind, color, glow)
	else
		pad = Voxel.Box(model, site * CFrame.new(0, 0.15, -6), Vector3.new(10, 0.3, 6), P.StoneLight, SMOOTH, { Name = "Step", CanCollide = true, CanQuery = true, CanTouch = false })
		pad.CastShadow = false
	end

	buildTag(core, GATE.TagLift - GATE.SwirlY, spec, color)
	model.PrimaryPart = core
	local stars = (shape == "Hoop" and not (Crest[glyph] and glyph ~= "cloud")) and max(0, min(5, floor(tonumber(spec.Stars) or 5))) or nil
	tagGateMesh(model, WorldStyle.GateMeshKey(shape, glyph), color, stars)
	model.Parent = parent
	return model, pad, promptPart
end

-- The five Gate Court gates in a row (facing -Z) on a small cream court: the reference sample for renders
-- (tools/render_model.py module:shared/WorldStyle:Sample) and the style tests. Not used in game. (Phase 6: no Home
-- gate in the lobby any more, so no Home sample; the house crest still exists for the arena's Return gate.)
WorldStyle.SampleGates = {
	{ Id = "Obby", Title = "Sky Obby", Info = "Climb the clouds - pick a level", Color = "Blue", Glyph = "cloud", Pad = true, Pill = "Easy - 1/4" },
	{ Id = "Dungeon", Title = "Dungeon", Info = "12 floors of monsters and loot", Color = "Purple", Glyph = "torch", Pad = true },
	{ Id = "Ring", Title = "Champion Ring", Info = "Win rounds in a row", Color = "Gold", Glyph = "crown", Pad = true },
	{ Id = "Arena", Title = "Battle Arena", Info = "Duels and boss raids", Color = "Red", Glyph = "swords", Pad = false },
	{ Id = "Altar", Title = "Storm Altar", Info = "Secret pets", Color = "Cyan", Glyph = "bolt", Pad = false },
}

function WorldStyle.Sample(parent)
	local root = Instance.new("Model")
	root.Name = "WorldStyleSample"
	local P = WorldStyle.Palette
	local n = #WorldStyle.SampleGates
	local step = 30
	-- the court: cream stone tiles (a light / dark checker) with stone-edge kerbs on the long edges, on lime grass
	local w, d = n * step, 40
	Voxel.Box(root, CFrame.new(0, -1.5, 0), Vector3.new(w + 24, 1, d + 24), P.Grass, SMOOTH, { Name = "Lawn", CanCollide = true, CanQuery = true })
	for ix = 0, floor(w / 5) - 1 do
		for iz = 0, floor(d / 5) - 1 do
			local alt = (ix + iz) % 2 == 0
			Voxel.Box(root, CFrame.new(-w * 0.5 + 2.5 + ix * 5, -0.5, -d * 0.5 + 2.5 + iz * 5), Vector3.new(5, 1, 5),
				alt and P.StoneLight or P.Stone, SMOOTH, { Name = "Tile", CanCollide = true, CanQuery = true })
		end
	end
	WorldStyle.Kerb(root, CFrame.new(0, 0, -d * 0.5), w)
	WorldStyle.Kerb(root, CFrame.new(0, 0, d * 0.5) * CFrame.Angles(0, PI, 0), w)
	for i, spec in ipairs(WorldStyle.SampleGates) do
		local x = (i - (n + 1) * 0.5) * step
		WorldStyle.BuildGate(root, CFrame.new(x, 0, 8), spec)
	end
	-- loose pieces: a plinth with a chamfered pillar on it
	WorldStyle.Plinth(root, CFrame.new(-w * 0.5 - 8, 0.4, 8), Vector3.new(5, 0.8, 5))
	WorldStyle.Chamfer(root, CFrame.new(-w * 0.5 - 8, 0.8 + 3, 8), Vector3.new(4, 6, 4))
	root.Parent = parent
	return root
end

return WorldStyle
