-- WorldStyle: the shared art kit of the Phase 5 world (ARCHITECTURE_V3.md "Phase 5 build contract" 6.2 / 6.4).
-- "Less cute, crafted, still bright": real Roblox materials (stone, wood, grass), plinth + body + cap on every
-- structure, kerbs and lips on platform edges, chamfered tall corners, muted big surfaces with ONE accent hue
-- per structure, neon only as thin inlays. Every world builder (LobbyBuilder, HomeBuilder, ArenaBuilder,
-- DungeonBuilder) builds with these pieces so the whole world reads as one place. Usable on the server and the
-- client (pure part building; no services, no remotes). Plain Lua 5.1-compatible syntax only.
--
--   WorldStyle.Materials                      name -> Enum.Material: the ONLY materials a world part may use
--   WorldStyle.Palette                        muted surface colours, lantern / cloud colours, Accent.<Name> gate colours
--   WorldStyle.Plinth(parent, cf, size, mat, color) -> body, band
--       the darker base of a structure: a `size` block centred on `cf` (default Slate) + a 0.2-stud Marble band
--       overhanging 0.15 on top (the moulding the body stands on)
--   WorldStyle.Kerb(parent, cf, length, mat, color) -> kerb, lip
--       a platform edge: cf = a point ON the platform's top surface at the edge, X = along the edge, LookVector =
--       outward. A 0.4-tall x 0.8 kerb straddling the edge (default Brick) + a 0.3-tall lip under the top surface
--       sticking out 0.3 (Slate)
--   WorldStyle.Chamfer(parent, cf, size, mat, color, cut) -> body, parts
--       a box with chamfered VERTICAL corners (the art rule for corners >= 4 studs tall): a cross of two boxes +
--       four 45-degree corner posts whose outer faces are the bevels; cut = bevel leg (default 0.6). 6 parts.
--   WorldStyle.BuildGate(parent, siteCFrame, spec) -> model, pad, promptPart
--       siteCFrame = ground CFrame of the gate centre, LookVector toward the plaza (the gate's front).
--       spec = { Id, Title, Info, Color (Theme.Neon.* / Palette.Accent.*), Glyph = "house"|"cloud"|"torch"|"crown"|
--                "swords"|"bolt", Pad = bool, Name = "Portal_<Id>", Pill = text (optional, the builder's status) }
--       22 wide x 8 deep x 26 tall: two round Marble columns on Slate plinths, a Slate lintel with a Marble
--       keystone medallion carrying the 6x6 voxel glyph (built once per glyph and cloned), a 0.4-stud Neon inlay
--       ring around the 14 x 15 opening, a Neon disc (Transparency 0.35) + a ForceField disc, the pixel tag
--       (BillboardGui "GateTag": title 28 px, info 20 px, pill 18 px, 27 studs up, MaxDistance 120), one PointLight
--       (Range 14, Brightness 1.2, Shadows false) and a sparkle emitter (Rate 6). Pad = true: a 14 x 0.6 x 14 Slate
--       slab 14 studs in front with a Marble border and a Neon glyph inlay (the PortalService zone part sits on
--       it); else a 10 x 0.3 x 6 step. promptPart = an invisible anchor in the front of the opening (prompts go
--       here). Model attributes: GateId, Glyph. <= 90 parts; the owner adds <= 30 (crown, torches).
-- Extras: WorldStyle.Jitter(color, seed, amount), WorldStyle.Glyphs (the 6x6 patterns), WorldStyle.IsWorldMaterial(m),
--   WorldStyle.Saturation(color), WorldStyle.GateSize, WorldStyle.Tags.Detail ("NC_Detail": pure decor, the Low
--   graphics setting hides it), WorldStyle.Tags.Exempt ("NC_StyleExempt": voxel clouds / pets / tokens, skipped by the
--   material + saturation checks of p5world_style).

local Shared = script.Parent
local Voxel = require(Shared:WaitForChild("Voxel", 10))
local Theme = require(Shared:WaitForChild("Theme", 10))

local WorldStyle = {}

local rgb = Color3.fromRGB
local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt
local PI = math.pi

WorldStyle.Tags = { Detail = "NC_Detail", Exempt = "NC_StyleExempt" }

----------------------------------------------------------------------
-- Materials (6.4 rule 1): the only materials a world part may use
----------------------------------------------------------------------
WorldStyle.Materials = {
	Slate = Enum.Material.Slate, -- courts, plinths, lintels
	Cobblestone = Enum.Material.Cobblestone, -- paths, avenues
	Brick = Enum.Material.Brick, -- kerbs, low walls
	Marble = Enum.Material.Marble, -- columns, gates, statues, trims
	WoodPlanks = Enum.Material.WoodPlanks, -- decks, bridges, boardwalks
	Wood = Enum.Material.Wood, -- posts, beams
	Grass = Enum.Material.Grass, -- lawns
	LeafyGrass = Enum.Material.LeafyGrass, -- hedges
	Sand = Enum.Material.Sand, -- flower / berry beds
	ClayRoofTiles = Enum.Material.ClayRoofTiles, -- roofs
	RoofShingles = Enum.Material.RoofShingles, -- roofs
	Metal = Enum.Material.Metal, -- gold trims, lamp posts
	Glass = Enum.Material.Glass, -- windows, lanterns
	Neon = Enum.Material.Neon, -- inlays only (<= 0.5 stud thick)
	Fabric = Enum.Material.Fabric, -- banners, awnings
	ForceField = Enum.Material.ForceField, -- the gate shimmer disc only
	SmoothPlastic = Enum.Material.SmoothPlastic, -- the voxel cloud palette + parts <= 2 studs (rule 1)
}

local MATERIAL_SET = {}
for _, m in pairs(WorldStyle.Materials) do
	MATERIAL_SET[m] = true
end

function WorldStyle.IsWorldMaterial(material)
	return MATERIAL_SET[material] == true
end

----------------------------------------------------------------------
-- Palette (6.4 rule 2): big surfaces saturation <= 0.45, value 0.35..0.9
----------------------------------------------------------------------
WorldStyle.Palette = {
	SlateDark = rgb(82, 86, 104),
	Slate = rgb(108, 112, 130),
	SlateLight = rgb(140, 144, 160),
	Marble = rgb(222, 218, 228),
	MarbleShade = rgb(196, 190, 210),
	Cobble = rgb(152, 146, 156),
	Brick = rgb(156, 106, 96),
	WoodPlanks = rgb(156, 118, 90),
	Wood = rgb(116, 88, 70),
	Grass = rgb(112, 152, 100),
	LeafyGrass = rgb(86, 130, 86),
	Sand = rgb(214, 198, 164),
	Roof = rgb(148, 96, 90),
	Metal = rgb(200, 166, 98), -- gold trim (small pieces only)
	Glass = rgb(190, 210, 226),
	Fabric = rgb(196, 176, 206),
	Lantern = rgb(255, 214, 170), -- warm lights: Brightness <= 1.5, Range <= 16
	-- the voxel clouds, shaded for the pink sky (6.4 rule 9)
	CloudTop = rgb(250, 244, 252),
	CloudSide = rgb(226, 214, 240),
	CloudUnder = rgb(186, 172, 222),
	-- gate / mode accents (the Neon kit hues; Theme.Neon.* wins when present)
	Accent = {
		Yellow = rgb(255, 214, 92),
		Blue = rgb(92, 178, 255),
		Purple = rgb(178, 112, 255),
		Gold = rgb(255, 190, 70),
		Red = rgb(255, 96, 110),
		Cyan = rgb(80, 232, 240),
		Pink = rgb(255, 120, 200),
		Green = rgb(110, 230, 140),
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

-- Deterministic +-amount RGB jitter (default 6) so tiles / planks / bricks never read as one flat toy colour.
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
	mat = mat or WorldStyle.Materials.Slate
	local body = Voxel.Box(parent, cf, size, color or WorldStyle.Palette.SlateDark, mat, solidProps("Plinth"))
	local band = Voxel.Box(
		parent,
		cf * CFrame.new(0, size.Y * 0.5 - 0.1, 0),
		Vector3.new(size.X + 0.3, 0.2, size.Z + 0.3),
		WorldStyle.Palette.MarbleShade,
		WorldStyle.Materials.Marble,
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
		color or WorldStyle.Palette.Brick,
		mat or WorldStyle.Materials.Brick,
		solidProps("Kerb")
	)
	-- the lip: 0.3 tall, just under the top surface, 0.3 beyond the kerb's outer face (-Z local = outward)
	local lip = Voxel.Box(
		parent,
		cf * CFrame.new(0, -0.25, -0.3),
		Vector3.new(length + 0.2, 0.3, 1.0),
		WorldStyle.Palette.SlateDark,
		WorldStyle.Materials.Slate,
		decoProps("KerbLip")
	)
	return kerb, lip
end

function WorldStyle.Chamfer(parent, cf, size, mat, color, cut)
	cut = tonumber(cut) or 0.6
	cut = min(cut, size.X * 0.25, size.Z * 0.25)
	mat = mat or WorldStyle.Materials.Marble
	color = color or WorldStyle.Palette.Marble
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
-- The gate (6.2)
----------------------------------------------------------------------
WorldStyle.GateSize = Vector3.new(22, 26, 8)

local GATE = {
	ColumnX = 8.2, -- column centres (opening 14 wide between the shafts)
	PlinthH = 1.2,
	ShaftH = 14,
	CapitalH = 1,
	LintelH = 2.4,
	PadDistance = 14, -- pad centre in front of the gate centre (gate r 118, pad r 104)
	TagLift = 27,
}

local function accentOf(spec)
	local c = spec.Color
	if typeof(c) == "Color3" then
		return c
	end
	if type(c) == "string" then
		local neon = Theme.Neon
		if type(neon) == "table" and typeof(neon[c]) == "Color3" then
			return neon[c]
		end
		if WorldStyle.Palette.Accent[c] then
			return WorldStyle.Palette.Accent[c]
		end
	end
	return WorldStyle.Palette.Accent.Blue
end

function WorldStyle.BuildGate(parent, siteCFrame, spec)
	spec = spec or {}
	local id = tostring(spec.Id or "Gate")
	local color = accentOf(spec)
	local glyph = WorldStyle.Glyphs[spec.Glyph] and spec.Glyph or "cloud"
	local P, M = WorldStyle.Palette, WorldStyle.Materials
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

	local G = GATE
	local topOfShaft = G.PlinthH + G.ShaftH
	local lintelY = topOfShaft + G.CapitalH + G.LintelH * 0.5 -- 17.4
	-- columns: Slate plinth + Marble base ring + round Marble shaft + capital + a gold collar
	for side = -1, 1, 2 do
		local x = side * G.ColumnX
		WorldStyle.Plinth(model, site * CFrame.new(x, G.PlinthH * 0.5, 0), Vector3.new(4, G.PlinthH, 4))
		Voxel.Box(model, site * CFrame.new(x, G.PlinthH + 0.2, 0), Vector3.new(3, 0.4, 3), P.MarbleShade, M.Marble, solidProps("ColumnBase"))
		Voxel.Box(
			model,
			site * CFrame.new(x, G.PlinthH + G.ShaftH * 0.5, 0) * CFrame.Angles(0, 0, PI / 2),
			Vector3.new(G.ShaftH, 2.4, 2.4),
			P.Marble,
			M.Marble,
			{ Name = "Column", Shape = Enum.PartType.Cylinder, CanCollide = true, CanQuery = true, CanTouch = false }
		)
		Voxel.Box(model, site * CFrame.new(x, topOfShaft - 0.6, 0) * CFrame.Angles(0, 0, PI / 2), Vector3.new(0.3, 2.6, 2.6), P.Metal, M.Metal, { Name = "Collar", Shape = Enum.PartType.Cylinder })
		Voxel.Box(model, site * CFrame.new(x, topOfShaft + G.CapitalH * 0.5, 0), Vector3.new(3.2, G.CapitalH, 3.2), P.MarbleShade, M.Marble, solidProps("Capital"))
	end
	-- lintel (Slate) + a Marble cornice on top and a darker soffit band below
	local lintel = Voxel.Box(model, site * CFrame.new(0, lintelY, 0), Vector3.new(21.4, G.LintelH, 3), P.Slate, M.Slate, solidProps("Lintel"))
	Voxel.Box(model, site * CFrame.new(0, lintelY + G.LintelH * 0.5 + 0.2, 0), Vector3.new(22, 0.4, 3.6), P.MarbleShade, M.Marble, solidProps("Cornice"))
	Voxel.Box(model, site * CFrame.new(0, lintelY - G.LintelH * 0.5 + 0.15, 0), Vector3.new(20.8, 0.3, 3.3), P.SlateDark, M.Slate, decoProps("Soffit"))
	-- the keystone medallion: a chamfered Marble block standing on the cornice, the glyph on its front face
	local medY = lintelY + G.LintelH * 0.5 + 0.7 + 3.2 -- centre of a 6.4-tall block on its base (cap top at 26)
	WorldStyle.Plinth(model, site * CFrame.new(0, lintelY + G.LintelH * 0.5 + 0.55, 0), Vector3.new(9, 0.3, 3.2))
	local _, medParts = WorldStyle.Chamfer(model, site * CFrame.new(0, medY, 0), Vector3.new(7.8, 6.4, 2), M.Marble, P.Marble, 0.8)
	medParts[1].Name = "Keystone"
	Voxel.Box(model, site * CFrame.new(0, medY + 3.35, 0), Vector3.new(6.2, 0.3, 2.2), P.Metal, M.Metal, decoProps("KeystoneCap"))
	-- a dark Slate inset behind the glyph so the neon reads from across the plaza
	Voxel.Box(model, site * CFrame.new(0, medY, -1.0), Vector3.new(6.6, 6.2, 0.12), P.SlateDark, M.Slate, decoProps("EmblemPanel"))
	placeGlyph(model, glyph, site * CFrame.new(0, medY, -1.14), color, 1, 0.2, false).Name = "Emblem"
	-- corbels: two Marble wedges in the upper corners of the opening (an arch feel without curves)
	for side = -1, 1, 2 do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Corbel"
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.CanTouch = false
		wedge.CastShadow = false
		wedge.Material = M.Marble
		wedge.Color = P.MarbleShade
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.BottomSurface = Enum.SurfaceType.Smooth
		wedge.Size = Vector3.new(2.2, 1.6, 1.6)
		-- flipped (full faces up + toward the column), then turned so the column side faces outward
		wedge.CFrame = site * CFrame.new(side * (G.ColumnX - 1.6 - 0.8), topOfShaft + G.CapitalH - 0.8, 0)
			* CFrame.Angles(0, -side * PI / 2, 0) * CFrame.Angles(PI, 0, 0)
		wedge.Parent = model
	end

	-- the opening: a 0.4-stud Neon inlay ring, the Neon disc and the ForceField shimmer
	local inX = G.ColumnX - 1.2 - 0.2 -- just inside the shaft faces
	local ringTop = topOfShaft - 0.9 -- under the corbels
	local function inlay(name, cf, size)
		local p = Voxel.Box(model, site * cf, size, color, M.Neon, decoProps(name))
		p.CastShadow = false
		return p
	end
	inlay("InlayL", CFrame.new(-inX, (G.PlinthH + ringTop) * 0.5, -1.0), Vector3.new(0.4, ringTop - G.PlinthH, 0.4))
	inlay("InlayR", CFrame.new(inX, (G.PlinthH + ringTop) * 0.5, -1.0), Vector3.new(0.4, ringTop - G.PlinthH, 0.4))
	inlay("InlayTop", CFrame.new(0, ringTop, -1.0), Vector3.new(inX * 2 + 0.4, 0.4, 0.4))
	inlay("InlayLintel", CFrame.new(0, lintelY, -1.6), Vector3.new(17, 0.25, 0.2))
	inlay("InlaySill", CFrame.new(0, 0.32, -1.0), Vector3.new(inX * 2 + 0.4, 0.4, 0.4))
	local discY = (G.PlinthH + ringTop) * 0.5 + 0.2
	local discD = min(inX * 2 - 0.6, ringTop - G.PlinthH - 0.4)
	local disc = Voxel.Box(model, site * CFrame.new(0, discY, 0) * CFrame.Angles(0, PI / 2, 0), Vector3.new(0.2, discD, discD), color, M.Neon, {
		Name = "PortalDisc",
		Shape = Enum.PartType.Cylinder,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	disc.CastShadow = false
	local shimmer = Voxel.Box(model, site * CFrame.new(0, discY, -0.3) * CFrame.Angles(0, PI / 2, 0), Vector3.new(0.2, discD, discD), color:Lerp(rgb(255, 255, 255), 0.4), M.ForceField, {
		Name = "PortalShimmer",
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	shimmer.CastShadow = false
	-- threshold: a Slate sill between the plinths
	Voxel.Box(model, site * CFrame.new(0, 0.1, 0), Vector3.new(inX * 2 + 1.2, 0.2, 4), P.Slate, M.Slate, solidProps("Sill"))

	local light = Instance.new("PointLight")
	light.Name = "GateLight"
	light.Range = 14
	light.Brightness = 1.2
	light.Color = color
	light.Shadows = false
	light.Parent = disc
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 6
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Speed = NumberRange.new(0.5, 1.5)
	sparkles.Size = NumberSequence.new(0.35)
	sparkles.Color = ColorSequence.new(color:Lerp(rgb(255, 255, 255), 0.5))
	sparkles.LightEmission = 0.8
	sparkles.LightInfluence = 0
	sparkles.SpreadAngle = Vector2.new(30, 30)
	sparkles.Parent = disc

	-- the prompt anchor: invisible, in the front of the opening at chest height
	local promptPart = Voxel.Box(model, site * CFrame.new(0, 3, -2.2), Vector3.new(2, 2, 1), P.Slate, M.Slate, {
		Name = "PromptAnchor",
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	promptPart.CastShadow = false

	-- pad (Pad = true) or a step
	local pad
	if spec.Pad then
		local padCF = site * CFrame.new(0, 0.3, -G.PadDistance)
		pad = Voxel.Box(model, padCF, Vector3.new(14, 0.6, 14), P.Slate, M.Slate, solidProps("Pad"))
		local border = { { 0, -6.6, 14, 0.8 }, { 0, 6.6, 14, 0.8 }, { -6.6, 0, 0.8, 12.4 }, { 6.6, 0, 0.8, 12.4 } }
		for i, b in ipairs(border) do
			Voxel.Box(model, padCF * CFrame.new(b[1], 0.35, b[2]), Vector3.new(b[3], 0.1, b[4]), P.Marble, M.Marble, solidProps("PadBorder" .. i))
		end
		placeGlyph(model, glyph, padCF * CFrame.new(0, 0.33, 0), color, 1.4, 0.08, true).Name = "PadGlyph"
	else
		pad = Voxel.Box(model, site * CFrame.new(0, 0.15, -6), Vector3.new(10, 0.3, 6), P.Slate, M.Slate, solidProps("Step"))
	end

	buildTag(lintel, GATE.TagLift - lintelY, spec, color)
	model.PrimaryPart = lintel
	model.Parent = parent
	return model, pad, promptPart
end

-- The six Gate Court gates in a row (facing -Z) + one of each piece on a small kerbed court: the reference
-- sample for renders (tools/render_model.py module:shared/WorldStyle:Sample) and the style tests. Not used in game.
WorldStyle.SampleGates = {
	{ Id = "Home", Title = "My Home", Info = "Your house and pets", Color = "Yellow", Glyph = "house", Pad = false },
	{ Id = "Obby", Title = "Sky Obby", Info = "Climb the clouds - pick a level", Color = "Blue", Glyph = "cloud", Pad = true, Pill = "Easy - 1/4" },
	{ Id = "Dungeon", Title = "Dungeon", Info = "12 floors of monsters and loot", Color = "Purple", Glyph = "torch", Pad = true },
	{ Id = "Ring", Title = "Champion Ring", Info = "Win rounds in a row", Color = "Gold", Glyph = "crown", Pad = true },
	{ Id = "Arena", Title = "Battle Arena", Info = "Duels and boss raids", Color = "Red", Glyph = "swords", Pad = false },
	{ Id = "Altar", Title = "Storm Altar", Info = "Secret pets", Color = "Cyan", Glyph = "bolt", Pad = false },
}

function WorldStyle.Sample(parent)
	local root = Instance.new("Model")
	root.Name = "WorldStyleSample"
	local P, M = WorldStyle.Palette, WorldStyle.Materials
	local n = #WorldStyle.SampleGates
	local step = 30
	-- the court: Slate tiles (jittered, +-0.05 height alternation) with Brick kerbs on the long edges
	local w, d = n * step, 40
	for ix = 0, floor(w / 5) - 1 do
		for iz = 0, floor(d / 5) - 1 do
			local h = ((ix + iz) % 2 == 0) and 0.05 or 0
			Voxel.Box(root, CFrame.new(-w * 0.5 + 2.5 + ix * 5, -0.5 + h, -d * 0.5 + 2.5 + iz * 5), Vector3.new(5, 1, 5),
				WorldStyle.Jitter(P.Slate, ix * 31 + iz), M.Slate, solidProps("Tile"))
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
