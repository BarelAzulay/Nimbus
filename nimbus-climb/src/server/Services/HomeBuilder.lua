-- HomeBuilder (Phase 2 + 4 + 5, homeworld): builds the tycoon home of a lobby plot (ARCHITECTURE_V3.md "Phase 2 build
-- contract", "Phase 4 build contract", "Phase 5 build contract" 3.3 / 3.4 / 3.6 / 6.4). A server module: TycoonService
-- requires it and decides WHAT is built; HomeBuilder only draws.
--
-- Contract API:
--   HomeBuilder.Init(lobbyInfo)                 remembers the lobby and prepares every plot in lobbyInfo.Spots
--   HomeBuilder.PreparePlot(spotInfo)           the plot's `Home` folder (tag NC_Home) and the gate's "Claim Home"
--                                               ProximityPrompt `ClaimPrompt` (attribute SpotIndex; E, ObjectText
--                                               "Free home") plus a crafted "FREE HOME" signpost on the verge.
--                                               Idempotent; returns the Home folder.
--   HomeBuilder.SetOwner(spotInfo, player|nil)  attributes OwnerUserId / OwnerName on the Home folder, every pad and
--                                               owner-only prompt; the claim prompt + signpost only while free; the
--                                               cobble paths of the yard while owned (and the staked-out house lot
--                                               while there is no House yet)
--   HomeBuilder.SetStation(spotInfo, id, level) builds or replaces the station model `Station_<Id>` (attributes
--                                               StationId, Level, BuiltAt = workspace:GetServerTimeNow(), Kind + the
--                                               art's points / info) under the Home folder at PlotCFrame * Slot.CFrame;
--                                               level 0 removes it; the same level again is a no-op. Returns the model.
--                                               The art is chosen by the station's Kind (TycoonCatalog.Kinds) or Id.
--   HomeBuilder.SetPads(spotInfo, pads)         the buy pads `Pad_<StationId>` (Home/Pads) for TycoonCatalog.AvailablePads
--                                               entries: a slate pad with a neon plate + a pixel sign `PadSign` (icon,
--                                               name, "Lv a -> b", price or the lock reason; HomeFx hides the unsigned
--                                               ones) + ProximityPrompt `BuyPrompt` (ActionText "Buy", HoldDuration 0.25,
--                                               attributes StationId, OwnerUserId; disabled while locked; the Prestige
--                                               pad's says "Prestige" and needs a 1.5 s hold). Pads missing from the list
--                                               are removed, unchanged pads are kept. Locked "Unlocks at Prestige" /
--                                               "Coming soon" stations show a hologram silhouette (`Ghost_<Id>`)
--                                               unless their def says Ghost = "Pad" (the Fusion Machine: pad + sign).
--   HomeBuilder.SetGarden(spotInfo, valid, open)  (TycoonService) the Garden's open beds (3 + Prestige stars, <= 12;
--                                               NOT the Garden level) and the placed keys valid = { [slot] = key }: a
--                                               new open count rebuilds the Garden (template Garden:<level>:<open>);
--                                               the GardenSpotPrompt of every OPEN EMPTY bed is enabled, the others
--                                               disabled. Remembered per plot.
--   HomeBuilder.SetTraining(spotInfo, pets)     (PetCareService, optional) pets = { [mat] = { Key, Stat, Ends } }:
--                                               attributes Busy / Key / Stat / Ends on the Training Place's Spot<i>
--   HomeBuilder.ClearPlot(spotInfo)             removes every station, pad and ghost (the paths too when nobody owns
--                                               the plot); the claim prompt stays; the remembered garden / training
--                                               state is dropped
-- Extras (nothing depends on them): GetHomeFolder(spotInfo), GetStation(spotInfo, id), GetPad(spotInfo, id),
--   GetClaimPrompt(spotInfo), BuildHome(spotInfo, home) (every station of home.Stations, others removed),
--   BuildStationModel(id, level, accent, open) -> a fresh clone at the origin (renders / tests; open = the Garden's
--   open bed count), PartCount(spotInfo), StationBuilt = Util.Signal Fire(spotInfo, stationId, model|nil),
--   Points(id, level) (local fx points), Art (the art functions, for tests).
--
-- Workspace layout (Spot_NN = spotInfo.Folder):
--   Spot_NN/ClaimGate          ClaimSign (a two-part signpost, while free); ClaimAnchor (invisible, only when the lobby
--                              has no gate part) -- the ClaimPrompt rides the Attachment ClaimPoint in the gate opening
--   Spot_NN/Home  (Folder, tag NC_Home; attributes SpotIndex, PlotCFrame, OwnerUserId, OwnerName)
--     Paths                    the yard's cobble paths (TycoonCatalog.Layout.Paths), one merged voxel layer
--     HouseLot                 stakes, a string, planks and bricks where the house will stand (owned, no House yet)
--     Station_<Id>             the station models (contract 3.6 budgets: Farm 150, Garden 95, Food Machine 55,
--                              Training Place 90, House 150, Fusion 90, Fence 90, Fountain 80, others 80; a fully
--                              built plot <= 950 with its pads):
--                              * Farm (Press1, Berry Farm, 40 levels): red-berry bushes 1-10, blue-berry bushes 11-22,
--                                a golden trellis 23-37, the glowing Starberry tree 38-40, a barn + crates; the
--                                BillboardGui `FarmSign` ("Berry Farm Lv N" / "Grows berries for your pets", 70 studs);
--                                point BerryPoint (where HomeFx's berry flights start)
--                              * Garden: the fence ring with the entrance, the Food Bowl (`FoodBowl` + `BowlSign`
--                                "Food Bowl" / "Pets eat here, then poop Cloud Cash!", 40 studs; point BowlCenter),
--                                12 beds at Slot.Beds: Attachments Spot<i> (attributes Slot, Open) on the lawn; an open
--                                bed = bed + cushion + tiny roof with PromptPoint<i> -> `GardenSpotPrompt` ("Put a pet
--                                here", E, attributes Slot / OwnerUserId / StationId, MaxActivationDistance 3, no line of
--                                sight); a closed bed = soil + Stem + Sprout + `ClosedSign` ("Prestige to open"). The
--                                lawn top is y 0.2; the interior stays clear for the roaming pets (HomeRoam)
--                              * FoodMachine (Kitchen): the glass `Hopper` part (PetCareService's FeedPrompt), the
--                                BillboardGui `MachineSign` (Title "Food Machine", Info "Berries -> XP: press E", the
--                                TextLabel `BasketLine` HomeFx rewrites); points ChuteMouth / Tray / HopperTop / BasketTop
--                              * Training (Gym): mats with Attachments Spot<i> (attribute Slot) on the `Deck`
--                              * Fusion Machine: `Swirl` (a Model HomeFx spins) and `FusionPrompt` ("Fuse", owner
--                                only); Arena Gate: `ArenaGatePrompt` ("Go to Arena", owner only, Teleport = "Arena")
--                              * Decor: Yard Fence (Perimeter, plot frame), Fountain (lanterns 4 / 6 / 8), Pet Podium
--     Pads/Pad_<StationId>     buy pads, 4 parts each (attributes StationId, OwnerUserId, NextLevel, Level, Price,
--                              Locked ("" when unlocked), Title, LevelText, Kind, BuiltAt)
--     Ghost_<Id>               hologram silhouette (the 12 biggest blocks, ForceField) of a station that unlocks later
--
-- Art (Phase 6 A1: back to the Phase 4 look, 7aa0df2): SmoothPlastic everywhere (Neon for glow, Glass for windows
-- and water, ForceField for holograms), the bright P4 palette (white castle keep, blue / terracotta stepped voxel
-- roofs, gold trim, juicy greens, cream stone), blocky voxel shapes only (no Ball / Cylinder: the "round" helpers
-- build square prisms, roofs are stepped layers); warm lanterns (Brightness <= 1.5, Range <= 16, no shadows), parts
-- < 4 studs cast no shadow; pure decor sits in sub-models tagged NC_Detail (the Low graphics setting hides them),
-- voxel clouds are tagged NC_StyleExempt. Kit.finish guards the look on every template. Each (station,
-- level) is built ONCE per server and kept as a template that is :Clone()d onto every plot. No server-side
-- animation and no Instance per coin (Replication rule): HomeFx (client) pops stations in, spins the fusion swirl,
-- poses the roaming pets, draws the coins and berries, and hides other players' pads and prompts. Texts follow the
-- World text rule (pixel-sized billboard tags, surface signs at 50 px per stud with >= 0.6 stud letters). The only
-- fonts are Theme roles. Plain Lua 5.1-compatible syntax only.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)

local HomeBuilder = {}

local function loadShared(name)
	local inst = Shared:FindFirstChild(name)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	warn("[HomeBuilder] shared/" .. name .. " unavailable: " .. tostring(result))
	return nil
end

local Voxel = loadShared("Voxel")
local Util = loadShared("Util")
local WorldStyle = loadShared("WorldStyle")
local TycoonCatalog = nil -- resolved lazily (the economy agent's module may arrive later in a build)

local function catalog()
	if TycoonCatalog == nil then
		TycoonCatalog = loadShared("TycoonCatalog") or false
	end
	return TycoonCatalog or nil
end

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
local MAT = Enum.Material
local HOME_TAG = "NC_Home"
local PROMPT_RANGE = 9 -- studs: buy pads and station prompts
local PRESTIGE_HOLD = 1.5 -- seconds: the Prestige pad's prompt (it opens the prestige confirmation, never a quick tap)
local CLAIM_RANGE = 12
local PAD_SIGN_RANGE = 60 -- studs: pad signs (pixel tags) hide beyond this
local PAD_SIGN_LIFT = 4.2 -- studs above the pad's base where the sign's plate starts
local GHOST_PARTS = 12 -- a locked station's silhouette keeps only its biggest blocks
local SIGN_PPS = 50 -- surface signs: pixels per stud
local TAG_NAME = 24 -- px: pad sign names (World text rule: >= 22)
local TAG_INFO = 20 -- px: info lines (>= 18)
local TAG_PRICE = 22
local GLYPH = {
	Lock = "\240\159\148\146",
	Star = "\226\173\144",
	Cloud = "\226\152\129",
	Arrow = "\226\150\182",
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local C = {
	Stone = rgb(208, 202, 190),
	StoneLight = rgb(226, 221, 209),
	StoneDark = rgb(160, 152, 144),
	StoneEdge = rgb(132, 124, 120),
	Marble = rgb(238, 236, 232),
	Iron = rgb(74, 82, 108),
	IronLight = rgb(118, 128, 156),
	IronDark = rgb(46, 52, 72),
	Gold = rgb(244, 198, 84),
	GoldDark = rgb(206, 154, 62),
	Copper = rgb(212, 134, 84),
	Plank = rgb(196, 146, 98),
	PlankLight = rgb(218, 170, 118),
	PlankDark = rgb(146, 102, 70),
	Bark = rgb(128, 90, 62),
	Cloud = rgb(240, 244, 252),
	CloudShade = rgb(210, 220, 240),
	Mist = rgb(190, 206, 236),
	Glass = rgb(186, 224, 250),
	Window = rgb(150, 200, 240),
	WarmWindow = rgb(255, 222, 150),
	Lamp = rgb(255, 214, 140),
	Cash = rgb(112, 204, 98),
	CashGlow = rgb(150, 236, 120),
	Leaf = rgb(98, 178, 80),
	LeafDark = rgb(70, 146, 70),
	Grass = rgb(118, 192, 92),
	Soil = rgb(122, 88, 66),
	Hedge = rgb(76, 150, 76),
	Water = rgb(92, 178, 236),
	Red = rgb(226, 92, 90),
	Rose = rgb(234, 120, 146),
	Cream = rgb(246, 236, 214),
	Navy = rgb(34, 42, 76),
	Violet = rgb(68, 60, 118),
	Crystal = rgb(120, 220, 255),
	Ink = (Theme.Colors and Theme.Colors.TextStroke) or rgb(16, 22, 50),
	Text = rgb(238, 243, 252),
	TextGold = rgb(246, 216, 132),
	TextGreen = rgb(170, 244, 140),
	TextLock = rgb(255, 176, 160),
	Ghost = rgb(120, 190, 255),
}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local floor, max, min, abs, huge = math.floor, math.max, math.min, math.abs, math.huge

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function serverNow()
	local ok, t = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.clock()
end

local function newFolder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- One anchored block (Voxel.Box when the kit is there). opts: Collide, Material, Transparency, Shadow, Reflectance,
-- Touch, Query.
local function box(parent, name, cf, size, color, opts)
	opts = opts or {}
	local p
	if Voxel and Voxel.Box then
		p = Voxel.Box(nil, cf, size, color, opts.Material or MAT.SmoothPlastic)
	else
		p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = opts.Material or MAT.SmoothPlastic
	end
	p.Name = name
	p.Transparency = opts.Transparency or 0
	if opts.Reflectance then
		p.Reflectance = opts.Reflectance
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = opts.Collide == true
	p.CanQuery = opts.Collide == true or opts.Query == true
	p.CanTouch = opts.Touch == true
	if opts.Shadow ~= nil then
		p.CastShadow = opts.Shadow == true
	else
		p.CastShadow = max(size.X, size.Y, size.Z) >= 4
	end
	p.Parent = parent
	return p
end

local function anchorPart(parent, name, cf)
	return box(parent, name, cf, Vector3.new(1, 1, 1), C.Cloud, { Transparency = 1, Shadow = false })
end

local function countParts(inst)
	if not inst then
		return 0
	end
	local n = 0
	if inst:IsA("BasePart") then
		n = 1
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLES
	e.LightEmission = 0.5
	e.LightInfluence = 0
	e.Rate = 4
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(1, 2)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	if props then
		for k, v in pairs(props) do
			e[k] = v
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
-- GUI helpers (World text rule; fonts only through Theme roles)
----------------------------------------------------------------------
local function rounded(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = (type(radius) == "number") and UDim.new(0, radius) or radius
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

local function listLayout(parent, direction, gap, hAlign)
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction or Enum.FillDirection.Vertical
	l.HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center
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
	if props then
		for k, v in pairs(props) do
			f[k] = v
		end
	end
	f.Parent = parent
	return f
end

-- Fixed-size outlined text that sizes itself (tags, pills).
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

-- Pixel-sized billboard (constant on-screen size) whose bottom edge sits on the adornee.
local function newTag(adornee, name, w, h, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromOffset(w, h)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or PAD_SIGN_RANGE
	gui.ClipsDescendants = false
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

local function tagPlate(gui, edge)
	local plate = plainFrame(gui, "Plate", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(150, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.04,
	})
	rounded(plate, 14)
	local stroke = outline(plate, edge or C.TextGold, 3.5)
	stroke.Name = "Edge"
	vgradient(plate, (Theme.Colors and Theme.Colors.PanelLight) or C.Violet, (Theme.Colors and Theme.Colors.Panel) or C.Navy)
	padding(plate, 6, 14, 8)
	listLayout(plate, Enum.FillDirection.Vertical, 3)
	return plate
end

local function surfaceGui(part, face, name)
	local gui = Instance.new("SurfaceGui")
	gui.Name = name or "SignGui"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PPS
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = part
	gui.Parent = part
	return gui
end

local function signText(parent, text, role, size, color, name, x, y, w, h)
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
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		},
	})
	label.Parent = parent
	return label
end

local function formatCash(n)
	local TC = catalog()
	if TC and type(TC.FormatCash) == "function" then
		local ok, s = pcall(TC.FormatCash, n)
		if ok and type(s) == "string" then
			return s
		end
	end
	n = floor(tonumber(n) or 0)
	if Util and Util.Commas then
		return "$" .. Util.Commas(n)
	end
	return "$" .. tostring(n)
end


----------------------------------------------------------------------
-- The art kit (Phase 6 A1: back to the Phase 4 look, 7aa0df2): SmoothPlastic everywhere (Glass / Neon / ForceField
-- only for glass, glow and holograms), the bright P4 palette, blocky voxel shapes only (no Cylinder / Ball: the
-- "round" helpers below build square prisms and cubes, roofs are stepped voxel stacks). The material keys stay so
-- the art code reads the same; every one of them is SmoothPlastic now. The detail comes later from the Blender
-- meshes (wave 2), so this is a revert, not new Part detail.
----------------------------------------------------------------------
local PLASTIC = MAT.SmoothPlastic
local M = {
	Slate = PLASTIC,
	Cobble = PLASTIC,
	Brick = PLASTIC,
	Marble = PLASTIC,
	Planks = PLASTIC,
	Wood = PLASTIC,
	Grass = PLASTIC,
	Leafy = PLASTIC,
	Sand = PLASTIC,
	Clay = PLASTIC,
	Shingles = PLASTIC,
	Metal = PLASTIC,
	Glass = MAT.Glass,
	Neon = MAT.Neon,
	Fabric = PLASTIC,
	Force = MAT.ForceField,
	Plastic = PLASTIC,
}
-- the materials a home part may use (Kit.finish turns anything else into SmoothPlastic)
local ALLOWED_MATS = { [PLASTIC] = true, [MAT.Neon] = true, [MAT.Glass] = true, [MAT.ForceField] = true }

-- the Phase 4 palette (7aa0df2 HomeBuilder.lua:151-191 + its House / station colours; style.md 4): bright stone,
-- white castle walls, blue and terracotta roofs, gold trim, juicy greens. The old key names stay.
local K = {
	SlateDark = rgb(160, 152, 144), -- P4 StoneDark: plinths and steps
	Slate = rgb(208, 202, 190), -- P4 Stone
	SlateLight = rgb(226, 221, 209), -- P4 StoneLight
	Marble = rgb(240, 240, 246), -- P4 Castle white
	MarbleShade = rgb(212, 216, 232), -- P4 CastleShade
	Cobble = rgb(208, 202, 190),
	Brick = rgb(250, 214, 196), -- P4 VillaWall (peach)
	BrickDark = rgb(220, 120, 80), -- P4 Terracotta
	Planks = rgb(196, 146, 98),
	PlanksLight = rgb(218, 170, 118),
	PlanksDark = rgb(146, 102, 70),
	Wood = rgb(128, 90, 62), -- P4 Bark
	WoodDark = rgb(150, 100, 66), -- P4 Door
	Whitewash = rgb(252, 248, 240), -- P4 VillaTrim
	Cream = rgb(250, 238, 214), -- P4 cottage Wall
	Manor = rgb(232, 226, 240), -- P4 ManorWall
	Grass = rgb(118, 192, 92),
	GrassLight = rgb(132, 202, 98),
	Leafy = rgb(98, 178, 80),
	LeafyDark = rgb(70, 146, 70),
	LeafyTeal = rgb(104, 196, 116), -- P4 Canopy
	Soil = rgb(122, 88, 66),
	SoilDark = rgb(100, 72, 56),
	Sand = rgb(236, 214, 166),
	Roof = rgb(222, 104, 82), -- P4 Roof (terracotta)
	RoofDark = rgb(190, 82, 68), -- P4 RoofTop
	RoofBlue = rgb(88, 136, 226), -- P4 Spire
	RoofBlueLight = rgb(110, 158, 238), -- P4 Spire2
	RoofBlueDark = rgb(70, 112, 204), -- P4 SpireTop
	Shingle = rgb(86, 106, 160), -- P4 manor Slate roof
	ShingleLight = rgb(102, 124, 178),
	BarnRed = rgb(226, 92, 90),
	Gold = rgb(244, 198, 84),
	GoldBright = rgb(255, 214, 96),
	Iron = rgb(74, 82, 108),
	IronDark = rgb(46, 52, 72),
	Copper = rgb(212, 134, 84),
	Glass = rgb(186, 224, 250),
	WarmGlass = rgb(255, 222, 150),
	Shutter = rgb(98, 148, 226),
	Fabric = rgb(246, 150, 188),
	Banner = rgb(236, 88, 110),
	Lantern = rgb(255, 214, 140),
	Water = rgb(92, 178, 236),
	WaterDeep = rgb(62, 136, 212),
	BerryRed = rgb(226, 58, 94),
	BerryRed2 = rgb(240, 92, 104),
	BerryBlue = rgb(84, 120, 230),
	BerryBlue2 = rgb(118, 160, 244),
	BerryGold = rgb(255, 210, 66),
	Star = rgb(255, 222, 96),
	CloudTop = rgb(244, 247, 252),
	CloudSide = rgb(232, 238, 249),
	CloudUnder = rgb(212, 222, 241),
}
local LANTERN = K.Lantern
local DETAIL_TAG = (WorldStyle and WorldStyle.Tags and WorldStyle.Tags.Detail) or "NC_Detail"
local EXEMPT_TAG = (WorldStyle and WorldStyle.Tags and WorldStyle.Tags.Exempt) or "NC_StyleExempt"
local PI = math.pi
local rad = math.rad

local Kit = {}

-- one block in a world material; collide = true makes it solid (walkable / blocking)
function Kit.p(parent, name, cf, size, color, mat, collide, extra)
	local opts = { Material = mat or M.Slate, Collide = collide == true }
	if extra then
		for k, v in pairs(extra) do
			opts[k] = v
		end
	end
	return box(parent, name, cf, size, color, opts)
end

-- a "ball" (P6 A1: a voxel cube, no round primitives) centred on pos, d studs wide
function Kit.ball(parent, name, pos, d, color, mat, collide)
	return Kit.p(parent, name, CFrame.new(pos), Vector3.new(d, d, d), color, mat, collide)
end

-- an upright "cylinder" standing on (x, y0, z): a square voxel prism d wide, h tall
function Kit.cyl(parent, name, x, y0, z, d, h, color, mat, collide)
	return Kit.p(parent, name, CFrame.new(x, y0 + h / 2, z), Vector3.new(d, h, d), color, mat, collide)
end

-- a "cylinder" along an arbitrary CFrame's X axis (pipes, door wheels, medallions): a square bar / tile
function Kit.cylAt(parent, name, cf, length, d, color, mat, collide)
	return Kit.p(parent, name, cf, Vector3.new(length, d, d), color, mat, collide)
end

-- a wedge (P6 A1: no slopes either; a block of the same size)
function Kit.wedge(parent, name, cf, size, color, mat, collide)
	return Kit.p(parent, name, cf, size, color, mat or M.Planks, collide)
end

-- a round slab of width w and height h standing on y0: a square voxel slab
function Kit.oct(parent, name, x, y0, z, w, h, color, mat, collide)
	return Kit.cyl(parent, name, x, y0, z, w, h, color, mat, collide)
end

-- a stepped voxel roof over a rectangle (the P4 look): cf = the centre of the wall tops (ridge along local X),
-- len = ridge length, span = the width it covers (local Z), rise = ridge height. Layers of blocks shrink toward
-- the ridge (light / dark alternate like P4's stepped spires); the first layer overhangs the walls. opts: Overhang,
-- EndOverhang, Ridge (a ridge cap colour), Collide, Dark (the alternate layer colour). Returns the layers.
function Kit.gable(parent, name, cf, len, span, rise, color, mat, opts)
	opts = opts or {}
	local ov = opts.Overhang or 0.6
	local eo = opts.EndOverhang or 0.4
	local n = max(2, min(5, floor(rise / 0.9 + 0.5)))
	local lh = rise / n
	local w0 = span + 2 * ov
	local layers = {}
	for i = 0, n - 1 do
		local w = w0 * (1 - i / n)
		local c = (opts.Dark and i % 2 == 1) and opts.Dark or color
		layers[#layers + 1] = Kit.p(parent, name, cf * CFrame.new(0, (i + 0.5) * lh, 0), Vector3.new(len + 2 * eo, lh, max(0.5, w)), c, mat, opts.Collide)
	end
	if opts.Ridge then
		Kit.p(parent, name .. "Ridge", cf * CFrame.new(0, rise + 0.15, 0), Vector3.new(len + 2 * eo + 0.1, 0.3, 0.5), opts.Ridge, M.Wood)
	end
	return layers
end

-- a window on a wall: cf = the window centre ON the wall surface, local -Z = outward. A wooden frame and warm glass
-- set 0.08 proud of the wall, a sill below (3 parts)
function Kit.window(parent, cf, w, h, frameColor, glassColor, opts)
	opts = opts or {}
	Kit.p(parent, "WindowFrame", cf * CFrame.new(0, 0, -0.06), Vector3.new(w + 0.3, h + 0.3, 0.12), frameColor or K.Whitewash, M.Wood)
	Kit.p(parent, "Window", cf * CFrame.new(0, 0, -0.14), Vector3.new(w, h, 0.06), glassColor or K.WarmGlass, M.Glass, false, { Transparency = opts.Transparency or 0.1, Reflectance = 0.05 })
	if opts.Sill ~= false then
		Kit.p(parent, "Sill", cf * CFrame.new(0, -h / 2 - 0.2, -0.2), Vector3.new(w + 0.5, 0.18, 0.4), opts.SillColor or K.SlateLight, M.Slate)
	end
end

-- a wall lantern / post-top lantern: a dark iron cap and a glowing warm body; light = a PointLight (no shadows)
function Kit.lantern(parent, pos, size, light, style)
	size = size or 0.6
	local cap = (style == "Brass") and K.Gold or ((style == "Crystal") and K.Marble or K.IronDark)
	local body = Kit.p(parent, "Lantern", CFrame.new(pos), Vector3.new(size, size * 1.25, size), (style == "Crystal") and rgb(200, 236, 255) or LANTERN, M.Neon)
	Kit.p(parent, "LanternCap", CFrame.new(pos + Vector3.new(0, size * 0.75, 0)), Vector3.new(size * 1.35, size * 0.25, size * 1.35), cap, (style == "Crystal") and M.Marble or M.Metal)
	if light then
		pointLight(body, (style == "Crystal") and rgb(214, 236, 255) or LANTERN, 1.2, 12)
	end
	return body
end

-- an inset corner post (6.4 rule 4: a 0.6-stud post on a corner >= 4 studs tall)
function Kit.corner(parent, x, y0, z, h, color, mat)
	return Kit.p(parent, "CornerPost", CFrame.new(x, y0 + h / 2, z), Vector3.new(0.6, h, 0.6), color or K.Whitewash, mat or M.Wood)
end

-- the four inset corner posts of a box [x0, x1] x [z0, z1]
function Kit.corners(parent, x0, x1, z0, z1, y0, h, color, mat)
	for _, x in ipairs({ x0, x1 }) do
		for _, z in ipairs({ z0, z1 }) do
			Kit.corner(parent, x, y0, z, h, color, mat)
		end
	end
end

-- a sub-model of pure decoration (tagged NC_Detail: the Low graphics setting hides it)
function Kit.detail(parent, name)
	local d = Instance.new("Model")
	d.Name = name or "Detail"
	d.Parent = parent
	CollectionService:AddTag(d, DETAIL_TAG)
	return d
end

-- deterministic +-6 RGB shade noise for repeated pieces (P4 Voxel.Shade spirit: never one flat colour)
function Kit.jit(color, seed)
	local n = ((seed or 0) * 7919 + 13) % 13 - 6
	local function ch(v)
		return max(0, min(255, floor(v * 255 + 0.5) + n))
	end
	return Color3.fromRGB(ch(color.R), ch(color.G), ch(color.B))
end

-- a pixel billboard sign (World text rule): a title line and info lines on a navy plate; returns gui, labels
function Kit.sign(adornee, name, lift, title, infos, maxDistance, edge)
	local gui = newTag(adornee, name, 360, 120, maxDistance or 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift or 3, 0)
	local plate = tagPlate(gui, edge or C.TextGold)
	local labels = {}
	labels.Title = tagText(plate, "Title", title, "Title", TAG_NAME, C.Text, 1)
	for i, info in ipairs(infos or {}) do
		local key = info.Name or ("Info" .. i)
		labels[key] = tagText(plate, key, info.Text, "Body", TAG_INFO, info.Color or C.TextGold, i + 1)
	end
	return gui, labels
end

----------------------------------------------------------------------
-- The style finish (a guard after every template, Phase 6 A1): every visible part is SmoothPlastic unless it is
-- Glass / Neon / ForceField, every Part is a Block (no Ball / Cylinder), Reflectance 0; parts < 4 studs cast no
-- shadow. Voxel clouds / pets / tokens (NC_StyleExempt) are skipped.
----------------------------------------------------------------------
local function exemptPart(p, root)
	local cur = p
	while cur and cur ~= root.Parent do
		if CollectionService:HasTag(cur, EXEMPT_TAG) then
			return true
		end
		cur = cur.Parent
	end
	return false
end

function Kit.finish(root)
	for _, p in ipairs(root:GetDescendants()) do
		if p:IsA("BasePart") then
			local s = p.Size
			if max(s.X, s.Y, s.Z) < 4 then
				p.CastShadow = false
			end
			if not exemptPart(p, root) then
				if not ALLOWED_MATS[p.Material] then
					p.Material = PLASTIC
				end
				if p:IsA("Part") and p.Shape ~= Enum.PartType.Block then
					p.Shape = Enum.PartType.Block
				end
				if p.Material ~= MAT.Glass then
					p.Reflectance = 0
				end
			end
		end
	end
end
----------------------------------------------------------------------
-- Templates: every (station, level) is built once per server and cloned onto the plots. A template is
-- { Model = Model at the origin (front = -Z, ground = y 0), Points = { name = local Vector3 }, Info = {...} }.
----------------------------------------------------------------------
local templates = {}

local function newTemplate(name)
	local m = Instance.new("Model")
	m.Name = name
	return { Model = m, Points = {}, Info = {} }
end

-- clones a template model to `cf` (every part moved by cf), returns the clone (unparented)
local function cloneAt(tpl, cf)
	local m = tpl.Model:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = cf * d.CFrame
		end
	end
	pcall(function()
		m.WorldPivot = cf
	end)
	return m
end

-- moves every child of `from` into `to` (merging sculpts into one model)
local function absorb(to, from)
	for _, c in ipairs(from:GetChildren()) do
		c.Parent = to
	end
	from:Destroy()
end

local function biggestPart(model, nameFilter)
	local best, bestVol = nil, -1
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 and (not nameFilter or p.Name == nameFilter) then
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > bestVol then
				best, bestVol = p, v
			end
		end
	end
	return best
end

local function attach(part, name, localPos, attrs)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = part.CFrame:Inverse() * CFrame.new(localPos)
	if attrs then
		for k, v in pairs(attrs) do
			a:SetAttribute(k, v)
		end
	end
	a.Parent = part
	return a
end

local function newPrompt(name, action, object, stationId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("StationId", stationId)
	return prompt
end

----------------------------------------------------------------------
-- ART: stations. Each Art.<Kind>(def, level) returns a template.
----------------------------------------------------------------------
local Art = {}

----------------------------------------------------------------------
-- Berry Farm (Press1, Kind Farm, 40 levels; contract 3.6): a long terraced field beside the PressLane, front -Z
-- toward the lane, local +X = the north end. Three wooden-framed soil rows rise toward the back: the front row
-- grows red-berry bushes (one per level 1-10), the middle row blue-berry bushes (11-22), the back row a golden
-- trellis (a vine with gold berries per level 23-37), and the glowing Starberry tree on its mound at the north end
-- (38-40). Planted bushes keep growing for a few levels. A little red barn, berry crates and the farm sign stand
-- at the south end. <= 150 parts (L40 ~ 145).
----------------------------------------------------------------------
local Farm = {}
Farm.X0, Farm.X1 = -10.8, 13.2 -- the soil frame (local x)
Farm.ROWS = { { Z = -2.25, Top = 0.75 }, { Z = 0.0, Top = 1.15 }, { Z = 2.25, Top = 1.55 } }
Farm.RED, Farm.BLUE, Farm.VINES = 10, 12, 15 -- plants per row (levels 1-10, 11-22, 23-37)
Farm.TREE_X = 15.7

-- how grown a plant planted at level `at` is at `level` (0 = just planted .. 1 = full)
function Farm.age(level, at, span)
	return max(0, min(1, (level - at) / (span or 6)))
end

-- a berry bush: a leafy ball with berries on its front (the yard side)
function Farm.bush(parent, x, row, d, berry, berry2, n, seed)
	local r = Farm.ROWS[row]
	local cy = r.Top + d * 0.4
	Kit.ball(parent, "Bush", Vector3.new(x, cy, r.Z), d, Kit.jit(row == 1 and K.Leafy or K.LeafyDark, seed), M.Leafy)
	local spots = { { -0.28, 0.12 }, { 0.26, 0.26 }, { 0.04, -0.1 } }
	for k = 1, n do
		local o = spots[k]
		Kit.ball(parent, "Berry", Vector3.new(x + o[1] * d, cy + o[2] * d, r.Z - d * 0.4), 0.42 + 0.04 * k, (k % 2 == 0) and berry2 or berry, M.Plastic)
	end
end

function Art.Farm(def, level)
	local tpl = newTemplate("BerryFarm")
	local m = tpl.Model
	level = max(1, min(floor(level), (def and def.MaxLevel) or 40))
	local x0, x1 = Farm.X0, Farm.X1
	local len = x1 - x0
	local cx = (x0 + x1) / 2
	-- the field: a slate plinth, three soil rows stepping up toward the back (grass where a row is not planted yet)
	Kit.p(m, "Plinth", CFrame.new(cx + 2.4, 0.15, 0), Vector3.new(len + 4.8, 0.3, 7.0), K.SlateDark, M.Slate, true)
	for i, r in ipairs(Farm.ROWS) do
		local planted = (i == 1) or (i == 2 and level > Farm.RED) or (i == 3 and level > Farm.RED + Farm.BLUE)
		local top = r.Top -- an unplanted row is a grassed-over bed, ready for its bushes
		Kit.p(m, planted and "Soil" or "Grass", CFrame.new(cx, (0.3 + top) / 2, r.Z), Vector3.new(len - 0.3, top - 0.3, 2.15),
			planted and Kit.jit(K.Soil, i) or K.Grass, planted and M.Sand or M.Grass, true)
	end
	-- the wooden frame: the front board, two step boards between the rows, the back board and the two ends
	local fz = { -3.35, -1.12, 1.12, 3.35 }
	local fh = { 0.85, 1.25, 1.65, 1.65 }
	for i, z in ipairs(fz) do
		Kit.p(m, "Frame", CFrame.new(cx, fh[i] / 2, z), Vector3.new(len + 0.3, fh[i], 0.3), Kit.jit(K.Planks, 10 + i), M.Planks, i == 1 or i == 4)
	end
	for _, x in ipairs({ x0, x1 }) do
		Kit.p(m, "FrameEnd", CFrame.new(x, 0.85, 0), Vector3.new(0.3, 1.7, 7.0), K.PlanksDark, M.Planks, true)
	end
	-- the north mound where the Starberry tree grows
	Kit.cyl(m, "Mound", Farm.TREE_X, 0.3, 0, 4.4, 0.5, K.Grass, M.Grass, true)
	-- row 1: red berries (levels 1-10)
	local span = len - 1.2
	for i = 1, min(level, Farm.RED) do
		local x = x0 + 0.6 + (i - 0.5) * span / Farm.RED
		local g = Farm.age(level, i, 6)
		Farm.bush(m, x, 1, 1.45 + 0.5 * g, K.BerryRed, K.BerryRed2, (g >= 0.5) and 2 or 1, i)
	end
	-- row 2: blue berries (levels 11-22)
	for i = 1, min(level - Farm.RED, Farm.BLUE) do
		local x = x0 + 0.6 + (i - 0.5) * span / Farm.BLUE
		local g = Farm.age(level, Farm.RED + i, 6)
		Farm.bush(m, x, 2, 1.35 + 0.45 * g, K.BerryBlue, K.BerryBlue2, (g >= 0.5) and 2 or 1, 20 + i)
	end
	-- row 3: the golden trellis (levels 23-37): six posts and a top rail, then one vine with gold berries per level
	local vines = min(level - Farm.RED - Farm.BLUE, Farm.VINES)
	if vines > 0 then
		local r = Farm.ROWS[3]
		for k = 0, 5 do
			local px = x0 + 0.5 + k * (len - 1.0) / 5
			Kit.p(m, "TrellisPost", CFrame.new(px, r.Top + 1.75, r.Z + 0.35), Vector3.new(0.3, 3.5, 0.3), K.Wood, M.Wood)
		end
		Kit.p(m, "TrellisRail", CFrame.new(cx, r.Top + 3.4, r.Z + 0.35), Vector3.new(len - 0.6, 0.25, 0.25), K.Wood, M.Wood)
		local vspan = len - 1.4
		for j = 1, vines do
			local x = x0 + 0.7 + (j - 0.5) * vspan / Farm.VINES
			local g = Farm.age(level, Farm.RED + Farm.BLUE + j, 5)
			local h = ((j % 2 == 0) and 1.7 or 2.2) + 1.0 * g
			Kit.p(m, "Vine", CFrame.new(x, r.Top + h / 2, r.Z + 0.1), Vector3.new(0.85, h, 0.45), Kit.jit((j % 2 == 0) and K.Leafy or K.LeafyDark, 40 + j), M.Leafy)
			Kit.ball(m, "GoldBerry", Vector3.new(x + ((j % 2 == 0) and 0.25 or -0.25), r.Top + h * 0.62, r.Z - 0.3), 0.5 + 0.12 * g, K.BerryGold, M.Metal)
		end
	end
	-- a young sapling on the mound foreshadows the Starberry tree (30-37)
	if level >= 30 and level < 38 then
		Kit.cyl(m, "Sapling", Farm.TREE_X, 0.8, 0, 0.35, 1.6, K.Wood, M.Wood)
		Kit.ball(m, "SaplingLeaves", Vector3.new(Farm.TREE_X, 2.7, 0), 1.5, K.LeafyTeal, M.Leafy)
	end
	-- the Starberry tree (levels 38-40): a trunk, a teal crown of three puffs and glowing star fruit
	if level >= 38 then
		local t = level - 37 -- 1..3
		local trunkH = 2.6 + 0.7 * t
		local crown = 3.0 + 0.55 * t
		local tx = Farm.TREE_X
		Kit.cyl(m, "Trunk", tx, 0.8, 0, 0.9, trunkH, K.Wood, M.Wood)
		local cy = 0.8 + trunkH + crown * 0.3
		Kit.ball(m, "Crown", Vector3.new(tx, cy, 0), crown, K.LeafyTeal, M.Leafy)
		Kit.ball(m, "Crown", Vector3.new(tx - crown * 0.32, cy - crown * 0.22, -0.3), crown * 0.66, Kit.jit(K.LeafyTeal, 7), M.Leafy)
		Kit.ball(m, "Crown", Vector3.new(tx + crown * 0.32, cy - crown * 0.18, 0.3), crown * 0.62, Kit.jit(K.LeafyTeal, 9), M.Leafy)
		local stars = { { -0.35, -0.05, -0.5 }, { 0.3, 0.2, -0.48 }, { 0.0, 0.42, -0.36 }, { 0.42, -0.25, -0.3 } }
		for k = 1, min(#stars, t + 1) do
			local o = stars[k]
			local sp = Kit.p(m, "Starberry", CFrame.new(tx + o[1] * crown, cy + o[2] * crown, o[3] * crown) * CFrame.Angles(rad(45), rad(30), rad(45)),
				Vector3.new(0.55, 0.55, 0.55), K.Star, M.Neon)
			if k == 1 and t >= 3 then
				pointLight(sp, LANTERN, 1.2, 12)
				local att = Instance.new("Attachment")
				att.Name = "Sparkle"
				att.Parent = sp
				emitter(att, { Color = ColorSequence.new(C.TextGold), Rate = 3, SpreadAngle = Vector2.new(180, 180) })
			end
		end
	end
	-- the little red barn at the south end (its door faces the lane)
	local bx = -15.6
	local bw, bd, bh = 4.8, 5.4, 3.4
	local bz = 0.6
	Kit.p(m, "BarnPlinth", CFrame.new(bx, 0.25, bz), Vector3.new(bw + 0.5, 0.5, bd + 0.5), K.SlateDark, M.Slate, true)
	Kit.p(m, "Barn", CFrame.new(bx, 0.5 + bh / 2, bz), Vector3.new(bw, bh, bd), K.BarnRed, M.Planks, true)
	for _, sx in ipairs({ -1, 1 }) do
		Kit.corner(m, bx + sx * (bw / 2 - 0.15), 0.5, bz - bd / 2 + 0.15, bh, K.Whitewash, M.Wood)
	end
	-- the roof: its ridge runs front to back, so the gable (with the hay-loft door) faces the lane
	local roofCF = CFrame.new(bx, 0.5 + bh, bz) * CFrame.Angles(0, PI / 2, 0)
	local slabs = Kit.gable(m, "BarnRoof", roofCF, bd, bw, 2.0, K.Shingle, M.Shingles, { Overhang = 0.45, Ridge = K.WoodDark, GableColor = K.BarnRed })
	slabs[1].Name = "BarnRoof"
	Kit.p(m, "BarnDoor", CFrame.new(bx, 0.5 + 1.25, bz - bd / 2 - 0.06), Vector3.new(2.0, 2.5, 0.14), K.WoodDark, M.Wood)
	Kit.p(m, "DoorBrace", CFrame.new(bx, 0.5 + 1.25, bz - bd / 2 - 0.15) * CFrame.Angles(0, 0, math.atan(2.5 / 2.0)), Vector3.new(3.0, 0.22, 0.06), K.Whitewash, M.Wood)
	Kit.p(m, "LoftDoor", CFrame.new(bx, 0.5 + bh + 0.65, bz - bd / 2 - 0.2), Vector3.new(1.0, 0.9, 0.12), K.WoodDark, M.Wood)
	local sign = Kit.p(m, "SignBoard", CFrame.new(bx, 0.5 + bh - 0.45, bz - bd / 2 - 0.1), Vector3.new(2.8, 0.55, 0.12), K.Whitewash, M.Wood)
	if level >= 10 then
		Kit.lantern(m, Vector3.new(bx + 1.55, 0.5 + 2.6, bz - bd / 2 - 0.35), 0.45, true)
	end
	-- berry crates by the barn (pure decor)
	local d = Kit.detail(m, "Crates")
	local crates = { { -12.25, 0.55, -2.6, K.BerryRed }, { -12.25, 0.55, -1.3, K.BerryBlue }, { -12.25, 1.65, -1.95, K.BerryGold } }
	local nCrates = (level >= 23) and 3 or ((level >= 11) and 2 or 1)
	for i = 1, nCrates do
		local c = crates[i]
		Kit.p(d, "Crate", CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(0, rad((i - 2) * 6), 0), Vector3.new(1.15, 1.1, 1.15), Kit.jit(K.PlanksLight, i), M.Planks)
		Kit.p(d, "CrateBerries", CFrame.new(c[1], c[2] + 0.6, c[3]) * CFrame.Angles(0, rad((i - 2) * 6), 0), Vector3.new(0.95, 0.18, 0.95), c[4], M.Plastic)
	end
	-- the farm sign (World text rule, MaxDistance 70)
	Kit.sign(sign, "FarmSign", 4.2, "Berry Farm Lv " .. level, { { Name = "Info", Text = "Grows berries for your pets", Color = C.TextGreen } }, 70, C.CashGlow)
	-- where HomeFx's berry flights start: the top of the planted rows, in the middle of the field
	local topRow = (vines > 0) and 3 or ((level > Farm.RED) and 2 or 1)
	tpl.Points.BerryPoint = Vector3.new(cx, Farm.ROWS[topRow].Top + 2.2, Farm.ROWS[topRow].Z)
	tpl.Info.Rows = topRow
	return tpl
end

----------------------------------------------------------------------
-- Pet Garden (Kind Garden; contract 3.3 / 3.6): front -Z = the entrance (Slot.Entrance, 4 wide) toward its pad. A
-- grass lawn inside a fence ring on the footprint edge (Slot.Fence 0.6: a cobble kerb, posts and a wooden rail),
-- the Food Bowl in the middle (Slot.Bowl, filled with berries; its "Food Bowl" sign) and 12 beds (Slot.Beds):
-- an OPEN bed = a wooden bed with a cushion under a tiny lean-to roof (Attachment Spot<i>, and a PromptPoint<i> with
-- the owner-only GardenSpotPrompt on its yard side), a CLOSED bed = a soil bed with a seedling (Stem + Sprout) and a
-- "Prestige to open" sign. The interior stays clear for the roaming pets (HomeRoam): every level's decor sits on the
-- fence (flower strips, the entrance arch, lanterns, bunting, gold rails at 8). The lawn top is y 0.2. <= 95 parts.
----------------------------------------------------------------------
local Garden = {}

Garden.PROMPT_RANGE = 3 -- studs (contract 3.6)
Garden.CUSHION_TOP = 0.95
Garden.LAWN_TOP = 0.2
Garden.CUSHIONS = { rgb(246, 150, 188), rgb(150, 224, 176), rgb(130, 170, 255), rgb(250, 214, 92) }

function Garden.places(def)
	return (def and def.Slot and type(def.Slot.Beds) == "table") and def.Slot.Beds or {}
end

function Garden.defaultOpen()
	local cat = catalog()
	local p = cat and type(cat.Prestige) == "table" and cat.Prestige or nil
	return (p and tonumber(p.GardenSlotsBase)) or 3
end

function Garden.clampOpen(open, places)
	open = tonumber(open)
	if not open or open ~= open then
		open = Garden.defaultOpen()
	end
	return max(0, min(floor(open), places))
end

-- the bed's frame: at the bed centre on the lawn, local -Z = toward the garden's interior, +Z = the fence behind it
function Garden.bedFrame(def, v)
	local hx = ((def.Slot.Footprint and def.Slot.Footprint.X) or 22) / 2
	local out
	if abs(v.X) >= hx - 3 then
		out = Vector3.new((v.X > 0) and 1 or -1, 0, 0)
	else
		out = Vector3.new(0, 0, 1)
	end
	local pos = Vector3.new(v.X, Garden.LAWN_TOP, v.Z)
	return CFrame.lookAt(pos, pos - out)
end

-- the prompt point of bed i (station frame): on the bed's interior side, half a stud over the cushion
function Garden.promptPoint(def, i)
	local v = Garden.places(def)[i]
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local size = def.Slot.BedSize or 2.5
	return (Garden.bedFrame(def, v) * CFrame.new(0, 1.3, -(size / 2 + 0.35))).Position
end

-- the "Prestige to open" sign of a closed bed (World text rule: 50 px per stud, letters 0.6 stud)
function Garden.closedSign(parent, bedCF, size)
	local board = Kit.p(parent, "ClosedSign", bedCF * CFrame.new(0, 0.95, -(size / 2 + 0.05)), Vector3.new(3.4, 1.4, 0.15), K.PlanksLight, M.Planks)
	local gui = surfaceGui(board, Enum.NormalId.Front, "ClosedGui")
	local panel = plainFrame(gui, "Panel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0 })
	vgradient(panel, C.Violet, C.Navy)
	rounded(panel, 10)
	outline(panel, C.TextGold, 4, 0.1)
	signText(panel, GLYPH.Star, "Heading", 48, C.TextGold, "Star", 0.0, 0.0, 0.28, 1.0)
	signText(panel, "Prestige", "Heading", 30, C.TextGold, "Title", 0.28, 0.02, 0.72, 0.48)
	signText(panel, "to open", "Heading", 30, C.Text, "Info", 0.28, 0.5, 0.72, 0.48)
	return board
end

function Art.Garden(def, level, open)
	local tpl = newTemplate("Garden")
	local m = tpl.Model
	local slot = def.Slot
	local fp = slot.Footprint or Vector3.new(22, 4, 20)
	local hx, hz = fp.X / 2, fp.Z / 2
	local t = slot.Fence or 0.6
	local beds = Garden.places(def)
	local size = slot.BedSize or 2.5
	open = Garden.clampOpen(open, #beds)
	local ent = slot.Entrance or { Center = Vector3.new(0, 0, -hz), Width = 4 }
	local g0, g1 = ent.Center.X - ent.Width / 2, ent.Center.X + ent.Width / 2
	local gold = level >= 8
	-- the lawn
	local lawn = Kit.p(m, "Lawn", CFrame.new(0, Garden.LAWN_TOP / 2, 0), Vector3.new(fp.X, Garden.LAWN_TOP, fp.Z), K.GrassLight, M.Grass, true)
	-- the fence ring: kerb runs (the sides between the front and back runs), a rail on posts
	local kh, railY = 0.7, 1.55
	local runs = {
		{ "Back", 0, hz - t / 2, fp.X, t },
		{ "Left", -hx + t / 2, 0, t, fp.Z - 2 * t },
		{ "Right", hx - t / 2, 0, t, fp.Z - 2 * t },
		{ "FrontL", (-hx + g0) / 2, -hz + t / 2, g0 + hx, t },
		{ "FrontR", (g1 + hx) / 2, -hz + t / 2, hx - g1, t },
	}
	local railColor = gold and K.Gold or K.Planks
	local railMat = gold and M.Metal or M.Planks
	for i, r in ipairs(runs) do
		Kit.p(m, "Kerb", CFrame.new(r[2], Garden.LAWN_TOP + kh / 2, r[3]), Vector3.new(r[4], kh, r[5]), Kit.jit(K.Cobble, i), M.Cobble, true)
		Kit.p(m, "Rail", CFrame.new(r[2], railY, r[3]), Vector3.new(r[4], 0.22, r[5] * 0.6), railColor, railMat, true)
	end
	local postH = 1.85
	local posts = {
		{ -hx + t / 2, -hz + t / 2 }, { hx - t / 2, -hz + t / 2 }, { -hx + t / 2, hz - t / 2 }, { hx - t / 2, hz - t / 2 },
		{ -hx + t / 2, 0 }, { hx - t / 2, 0 }, { 0, hz - t / 2 },
	}
	for i, p in ipairs(posts) do
		Kit.p(m, "Post", CFrame.new(p[1], postH / 2, p[2]), Vector3.new(0.72, postH, 0.72), Kit.jit(K.Wood, 30 + i), M.Wood, true)
	end
	-- the entrance posts (taller from level 3: they carry the arch)
	local arch = level >= 3
	local eh = arch and 3.9 or postH + 0.2
	for _, x in ipairs({ g0 - 0.45, g1 + 0.45 }) do
		Kit.p(m, "EntrancePost", CFrame.new(x, eh / 2, -hz + t / 2), Vector3.new(0.75, eh, 0.75), K.Wood, M.Wood, true)
	end
	-- a cobble walk from the entrance to the bowl (flush with the lawn: pets and players walk over it)
	local walkZ0, walkZ1 = -hz + t, (slot.Bowl and (slot.Bowl.Center.Z - slot.Bowl.Radius) or -2.5) + 0.2
	Kit.p(m, "Walk", CFrame.new(ent.Center.X, Garden.LAWN_TOP + 0.03, (walkZ0 + walkZ1) / 2), Vector3.new(ent.Width - 0.6, 0.06, walkZ1 - walkZ0), K.Cobble, M.Cobble, true)
	-- the Food Bowl: a slate basin with a marble rim, full of berries
	local bowl = slot.Bowl or { Center = Vector3.new(0, 0, 0), Radius = 2.5 }
	local bc, br = bowl.Center, bowl.Radius
	local basin = Kit.cyl(m, "FoodBowl", bc.X, Garden.LAWN_TOP, bc.Z, 2 * br, 0.55, K.Slate, M.Slate, true)
	Kit.cyl(m, "BowlRim", bc.X, Garden.LAWN_TOP + 0.55, bc.Z, 2 * br + 0.2, 0.18, K.Marble, M.Marble, true)
	Kit.cyl(m, "BowlBerries", bc.X, Garden.LAWN_TOP + 0.73, bc.Z, 2 * br - 0.8, 0.16, rgb(226, 58, 94), M.Sand)
	local heap = { { -0.55, 0.1, K.BerryRed2 }, { 0.5, -0.3, K.BerryBlue } }
	for _, h in ipairs(heap) do
		Kit.ball(m, "BowlBerry", Vector3.new(bc.X + h[1], Garden.LAWN_TOP + 1.05, bc.Z + h[2]), 0.85, h[3], M.Plastic)
	end
	Kit.sign(basin, "BowlSign", 3.4, "Food Bowl", { { Name = "Info", Text = "Pets eat here, then poop Cloud Cash!", Color = C.TextGreen } }, 40, C.CashGlow)
	tpl.Points.BowlCenter = Vector3.new(bc.X, Garden.LAWN_TOP + 0.9, bc.Z)
	-- the beds
	for i, v in ipairs(beds) do
		local cf = Garden.bedFrame(def, v)
		if i <= open then
			Kit.p(m, "Bed", cf * CFrame.new(0, 0.225, 0), Vector3.new(size, 0.45, size), Kit.jit(K.Planks, 50 + i), M.Planks, true)
			Kit.p(m, "Cushion", cf * CFrame.new(0, 0.6, 0.05), Vector3.new(size - 0.5, 0.3, size - 0.55), Kit.jit(Garden.CUSHIONS[(i - 1) % 4 + 1], i), M.Fabric)
			Kit.p(m, "Headboard", cf * CFrame.new(0, 1.05, size / 2 - 0.12), Vector3.new(size, 1.7, 0.24), Kit.jit(K.PlanksDark, 70 + i), M.Planks)
			Kit.p(m, "BedRoof", cf * CFrame.new(0, 2.05, size / 2 - 0.55), Vector3.new(size + 0.4, 0.2, 1.5), Kit.jit(K.Roof, 60 + i), M.Clay)
		else
			Kit.p(m, "SoilBed", cf * CFrame.new(0, 0.175, 0), Vector3.new(size, 0.35, size), K.SoilDark, M.Sand, true)
			Kit.p(m, "Stem", cf * CFrame.new(0, 0.7, 0.3), Vector3.new(0.18, 0.7, 0.18), K.LeafyDark, M.Leafy)
			Kit.p(m, "Sprout", cf * CFrame.new(0, 1.1, 0.3), Vector3.new(0.75, 0.22, 0.45), K.GrassLight, M.Leafy)
			Garden.closedSign(m, cf, size)
		end
	end
	-- the level decor, all on the fence ring or overhead (the interior stays clear for the roaming pets)
	local d = Kit.detail(m, "GardenDecor")
	if level >= 2 then
		-- flower strips on the front kerb, both sides of the entrance
		for _, r in ipairs({ runs[4], runs[5] }) do
			Kit.p(d, "FlowerStrip", CFrame.new(r[2], Garden.LAWN_TOP + kh + 0.15, r[3]), Vector3.new(r[4] - 1.2, 0.3, 0.5), K.Leafy, M.Leafy)
			Kit.p(d, "Blooms", CFrame.new(r[2], Garden.LAWN_TOP + kh + 0.36, r[3]), Vector3.new(r[4] - 1.6, 0.14, 0.34), rgb(246, 150, 188), M.Fabric)
		end
	end
	if arch then
		Kit.p(m, "Arch", CFrame.new(ent.Center.X, eh + 0.2, -hz + t / 2), Vector3.new(ent.Width + 2.0, 0.4, 0.9), K.Planks, M.Planks)
		Kit.p(d, "Garland", CFrame.new(ent.Center.X, eh - 0.15, -hz + t / 2 - 0.1), Vector3.new(ent.Width + 0.8, 0.35, 0.6), K.Leafy, M.Leafy)
	end
	if level >= 4 then
		for _, x in ipairs({ g0 - 0.45, g1 + 0.45 }) do
			Kit.lantern(d, Vector3.new(x, eh - 1.0, -hz + t / 2 - 0.62), 0.42, x > ent.Center.X)
		end
	end
	if level >= 5 then
		for _, r in ipairs({ runs[2], runs[3] }) do
			Kit.p(d, "FlowerStrip", CFrame.new(r[2], Garden.LAWN_TOP + kh + 0.15, r[3]), Vector3.new(0.5, 0.3, r[5] - 2.0), K.Leafy, M.Leafy)
			Kit.p(d, "Blooms", CFrame.new(r[2], Garden.LAWN_TOP + kh + 0.36, r[3]), Vector3.new(0.34, 0.14, r[5] - 2.6), rgb(172, 142, 232), M.Fabric)
		end
	end
	if level >= 6 then
		for _, p in ipairs({ posts[3], posts[4] }) do
			Kit.lantern(d, Vector3.new(p[1], postH + 0.45, p[2]), 0.5, false)
		end
	end
	if level >= 7 then
		Kit.p(d, "Bunting", CFrame.new(0, railY - 0.3, hz - t / 2 - 0.05), Vector3.new(fp.X - 2.0, 0.4, 0.06), rgb(250, 168, 72), M.Fabric)
		Kit.p(d, "Bunting", CFrame.new(0, railY - 0.3, hz - t / 2 + 0.05), Vector3.new(fp.X - 2.4, 0.4, 0.06), rgb(118, 168, 236), M.Fabric)
	end
	if gold then
		local att = Instance.new("Attachment")
		att.Name = "Sparkle"
		att.CFrame = lawn.CFrame:Inverse() * CFrame.new(ent.Center.X, eh + 0.6, -hz + t / 2)
		att.Parent = lawn
		emitter(att, { Color = ColorSequence.new(C.TextGold), Rate = 3, SpreadAngle = Vector2.new(180, 180) })
	end
	-- where pets sleep (Spot<i>, every bed) and the GardenSpotPrompts (open beds; SetGarden enables the empty ones)
	for i, v in ipairs(beds) do
		local cf = Garden.bedFrame(def, v)
		attach(lawn, "Spot" .. i, (cf * CFrame.new(0, Garden.CUSHION_TOP - Garden.LAWN_TOP, 0)).Position, { Slot = i, Open = i <= open })
		if i <= open then
			local pa = attach(lawn, "PromptPoint" .. i, Garden.promptPoint(def, i), { Slot = i })
			local prompt = newPrompt("GardenSpotPrompt", "Put a pet here", "Garden bed " .. i, "Garden")
			prompt.MaxActivationDistance = Garden.PROMPT_RANGE
			prompt.Enabled = false
			prompt:SetAttribute("Slot", i)
			prompt.Parent = pa
		end
	end
	tpl.Info.Open = open
	return tpl
end
----------------------------------------------------------------------
-- Food Machine (Kitchen, contract 3.4 / 3.6; the slot swapped with the Training Place): front -Z. A wooden cabinet
-- with iron bands on a slate plinth, a glass `Hopper` full of berries on a copper funnel (PetCareService puts the
-- FeedPrompt on it), a dispenser mouth with a chute over a tray, a big red FEED button, the Berry Basket beside it
-- (HomeFx's berry flights land in it) and the machine's sign: "Food Machine" / "Berries -> XP: press E" + the basket
-- line (TextLabel `BasketLine`, HomeFx rewrites it from the player attribute Berries and the plot's BerryCap).
-- Lamps (2+), a berry press barrel (3+), a shelf of bowls (4+), brass trims and a bell (5). Points ChuteMouth,
-- Tray, HopperTop, BasketTop. <= 55 parts.
----------------------------------------------------------------------
function Art.FoodMachine(def, level)
	local tpl = newTemplate("FoodMachine")
	local m = tpl.Model
	local gold = level >= 5
	local band = gold and K.Gold or K.IronDark
	local hw = ({ 2.6, 2.8, 3.0, 3.2, 3.4 })[level] or 3.4
	local top = ({ 4.2, 4.4, 4.6, 4.8, 5.0 })[level] or 5.0
	local z0, z1 = -1.6, 2.2
	local zc = (z0 + z1) / 2
	local dz = z1 - z0
	Kit.p(m, "Plinth", CFrame.new(0, 0.25, zc - 0.6), Vector3.new(2 * hw + 1.4, 0.5, dz + 2.6), K.SlateDark, M.Slate, true)
	local body = Kit.p(m, "Cabinet", CFrame.new(0, 0.5 + (top - 0.5) / 2, zc), Vector3.new(2 * hw, top - 0.5, dz), rgb(240, 112, 104), M.Planks, true)
	Kit.corners(m, -hw + 0.2, hw - 0.2, z0 + 0.2, z1 - 0.2, 0.5, top - 0.5, rgb(118, 168, 236), M.Wood)
	for _, y in ipairs({ 1.3, top - 0.9 }) do
		Kit.p(m, "Band", CFrame.new(0, y, z0 - 0.04), Vector3.new(2 * hw + 0.1, 0.22, 0.1), band, M.Metal)
	end
	Kit.p(m, "Cornice", CFrame.new(0, top + 0.17, zc), Vector3.new(2 * hw + 0.5, 0.35, dz + 0.5), rgb(92, 150, 230), M.Wood, true)
	Kit.p(m, "Panel", CFrame.new(0, 0.5 + (top - 0.5) / 2, z0 - 0.02), Vector3.new(2 * hw - 0.9, top - 1.6, 0.06), K.Whitewash, M.Planks)
	-- the dispenser: a slate mouth, a two-step copper chute, the tray with a few berries
	Kit.p(m, "Mouth", CFrame.new(-0.6, 2.4, z0 - 0.06), Vector3.new(1.7, 1.4, 0.14), K.IronDark, M.Slate)
	Kit.p(m, "Chute", CFrame.new(-0.6, 2.0, z0 - 0.45) * CFrame.Angles(rad(-25), 0, 0), Vector3.new(1.2, 0.18, 1.0), K.Copper, M.Metal)
	Kit.p(m, "Tray", CFrame.new(-0.6, 0.75, z0 - 1.0), Vector3.new(2.2, 0.3, 1.3), K.Iron, M.Metal, true)
	Kit.p(m, "TrayBerries", CFrame.new(-0.6, 0.95, z0 - 1.0), Vector3.new(1.6, 0.12, 0.8), K.BerryRed, M.Plastic)
	-- the FEED button (the one accent: berry red)
	Kit.cylAt(m, "ButtonRim", CFrame.new(hw - 1.0, 2.6, z0 - 0.06) * CFrame.Angles(0, PI / 2, 0), 0.12, 1.3, gold and K.Gold or K.Iron, M.Metal)
	Kit.cylAt(m, "Button", CFrame.new(hw - 1.0, 2.6, z0 - 0.16) * CFrame.Angles(0, PI / 2, 0), 0.14, 0.85, rgb(232, 64, 80), M.Neon)
	-- the hopper: a copper funnel, the glass Hopper (one part) with berry layers inside, a wooden lid with a knob
	local gw = (level >= 3) and 2.8 or 2.4
	local gh = 2.0 + 0.2 * level
	local gy0 = top + 0.35 + 0.5
	Kit.cyl(m, "Funnel", 0, top + 0.35, zc, 1.5, 0.5, K.Copper, M.Metal)
	local hopper = Kit.p(m, "Hopper", CFrame.new(0, gy0 + gh / 2, zc), Vector3.new(gw, gh, gw), rgb(214, 234, 246), M.Glass, false, { Transparency = 0.55 })
	hopper.CastShadow = false
	Kit.p(m, "HopperBerries", CFrame.new(0, gy0 + 0.4, zc), Vector3.new(gw - 0.3, 0.8, gw - 0.3), K.BerryRed, M.Plastic)
	Kit.p(m, "HopperBerries", CFrame.new(0, gy0 + 1.05, zc), Vector3.new(gw - 0.3, 0.5, gw - 0.3), K.BerryBlue, M.Plastic)
	Kit.p(m, "Lid", CFrame.new(0, gy0 + gh + 0.15, zc), Vector3.new(gw + 0.4, 0.3, gw + 0.4), rgb(92, 150, 230), M.Wood)
	for _, cx in ipairs({ -1, 1 }) do
		for _, cz2 in ipairs({ -1, 1 }) do
			Kit.p(m, "HopperRod", CFrame.new(cx * gw / 2, gy0 + gh / 2, zc + cz2 * gw / 2), Vector3.new(0.16, gh, 0.16), band, M.Metal)
		end
	end
	Kit.p(m, "Knob", CFrame.new(0, gy0 + gh + 0.45, zc), Vector3.new(0.5, 0.3, 0.5), gold and K.Gold or K.Copper, M.Metal)
	-- the Berry Basket on the plinth at the front right
	local bx = hw + 0.05
	Kit.cyl(m, "Basket", bx, 0.5, z0 - 1.05, 1.5, 0.75, K.PlanksLight, M.Planks)
	Kit.ball(m, "BasketBerries", Vector3.new(bx, 1.2, z0 - 1.05), 1.15, K.BerryRed2, M.Plastic)
	tpl.Points.BasketTop = Vector3.new(bx, 1.6, z0 - 1.05)
	local d = Kit.detail(m, "MachineDecor")
	if level >= 2 then
		for _, sx in ipairs({ -1, 1 }) do
			Kit.lantern(d, Vector3.new(sx * (hw + 0.1), top - 0.4, z0 - 0.35), 0.45, sx > 0)
		end
	end
	if level >= 3 then
		-- a berry press barrel on the left with a crank
		local px = -hw - 1.25
		Kit.cyl(m, "PressBarrel", px, 0.5, zc, 1.8, 1.9, K.Wood, M.Wood, true)
		Kit.cyl(m, "Hoop", px, 0.85, zc, 1.88, 0.18, band, M.Metal)
		Kit.cyl(m, "Hoop", px, 1.95, zc, 1.88, 0.18, band, M.Metal)
		Kit.p(m, "Crank", CFrame.new(px, 2.75, zc), Vector3.new(0.25, 0.9, 0.25), K.Iron, M.Metal)
		Kit.p(m, "PressPipe", CFrame.new((px - hw) / 2 + 0.2, 2.2, zc), Vector3.new(abs(px + hw) + 0.4, 0.35, 0.35), K.Copper, M.Metal)
	end
	if level >= 4 then
		-- a shelf of bowls on the right side
		local sx = hw + 1.0
		Kit.p(m, "Shelf", CFrame.new(sx, 1.4, zc + 0.6), Vector3.new(1.4, 1.8, 1.6), K.PlanksDark, M.Planks, true)
		local bowls = { K.BerryRed2, K.BerryBlue2, K.BerryGold }
		for i, c in ipairs(bowls) do
			Kit.cyl(d, "Bowl", sx, 2.3 + (i - 1) * 0.28, zc + 0.6, 1.2 - 0.12 * i, 0.26, c, M.Plastic)
		end
	end
	if gold then
		Kit.p(m, "Bell", CFrame.new(0, gy0 + gh + 0.95, zc), Vector3.new(0.7, 0.7, 0.7), K.GoldBright, M.Metal)
		local att = Instance.new("Attachment")
		att.Name = "Sparkle"
		att.CFrame = body.CFrame:Inverse() * CFrame.new(0, gy0 + gh + 1.2, zc)
		att.Parent = body
		emitter(att, { Color = ColorSequence.new(C.TextGold), Rate = 3, SpreadAngle = Vector2.new(180, 180) })
	end
	-- the machine's sign (World text rule); HomeFx rewrites BasketLine for the owner
	Kit.sign(body, "MachineSign", (gy0 + gh + 1.6) - (0.5 + (top - 0.5) / 2), "Food Machine", {
		{ Name = "Info", Text = "Berries -> XP: press E", Color = C.TextGreen },
		{ Name = "BasketLine", Text = "Berry Basket", Color = C.TextGold },
	}, 60, C.CashGlow)
	tpl.Points.ChuteMouth = Vector3.new(-0.6, 2.0, z0 - 0.5)
	tpl.Points.Tray = Vector3.new(-0.6, 1.0, z0 - 1.0)
	tpl.Points.HopperTop = Vector3.new(0, gy0 + gh, zc)
	return tpl
end

----------------------------------------------------------------------
-- Training Place (Gym; its slot swapped with the Food Machine): front -Z, open toward the yard. A plank deck on a
-- slate plinth that grows from the left edge; one fabric mat per level at Slot.Spots (Attachments Spot1..5 on the
-- deck, attribute Slot; HomeFx puts the training pet and its skill prop on it) and behind each mat its skill corner:
-- a barbell rack (Physique, 1), two hurdles (Attack Speed, 2), a marble pedestal with a glowing orb (Ability, 3), a
-- shield wall (Defense, 4) and a scoreboard with a trophy (5). Pennant posts from 3. <= 90 parts.
----------------------------------------------------------------------
local TRAIN_MATS = { rgb(236, 92, 96), rgb(250, 204, 72), rgb(176, 120, 236), rgb(84, 140, 226), rgb(110, 200, 120) }

function Art.Training(def, level)
	local tpl = newTemplate("Training")
	local m = tpl.Model
	local fp = (def.Slot and def.Slot.Footprint) or Vector3.new(18, 10, 9)
	local hz = fp.Z / 2
	local spots = (def.Slot and def.Slot.Spots) or {}
	local w = ({ 9, 12, 15, 18, 18 })[level] or 18
	local x0 = -fp.X / 2
	local x1 = x0 + w
	local cx = (x0 + x1) / 2
	local gold = level >= 5
	local deckTop = 0.8
	Kit.p(m, "Plinth", CFrame.new(cx, 0.22, 0), Vector3.new(w, 0.44, fp.Z), K.SlateDark, M.Slate, true)
	local deck = Kit.p(m, "Deck", CFrame.new(cx, 0.44 + (deckTop - 0.44) / 2, 0.15), Vector3.new(w - 0.5, deckTop - 0.44, fp.Z - 0.8), K.Planks, M.Planks, true)
	Kit.p(m, "Kerb", CFrame.new(cx, 0.6, -hz + 0.2), Vector3.new(w, 0.32, 0.4), gold and K.Gold or K.Brick, gold and M.Metal or M.Brick, true)
	Kit.p(m, "BackRail", CFrame.new(cx, deckTop + 0.5, hz - 0.15), Vector3.new(w - 0.2, 1.0, 0.3), K.PlanksDark, M.Planks, true)
	local bz = 2.6 -- the skill corners stand behind the mats
	local function spotX(i)
		local p = spots[i]
		return (typeof(p) == "Vector3") and p.X or (x0 + 3 * i)
	end
	local y = deckTop
	-- 1 Physique: a barbell on a rack
	do
		local x = spotX(1)
		Kit.p(m, "Rack", CFrame.new(x, y + 0.4, bz), Vector3.new(2.6, 0.8, 1.0), K.IronDark, M.Metal, true)
		for _, sx in ipairs({ -1, 1 }) do
			Kit.p(m, "RackPost", CFrame.new(x + sx * 1.0, y + 1.35, bz), Vector3.new(0.25, 1.1, 0.25), K.Iron, M.Metal)
			Kit.cylAt(m, "Weight", CFrame.new(x + sx * 1.55, y + 1.9, bz), 0.3, 1.2, K.IronDark, M.Metal)
		end
		Kit.cylAt(m, "Bar", CFrame.new(x, y + 1.9, bz), 3.6, 0.2, K.Iron, M.Metal)
	end
	-- 2 Attack Speed: two hurdles with striped bars
	if level >= 2 then
		local x = spotX(2)
		for _, hx in ipairs({ x - 0.8, x + 0.8 }) do
			for _, lz in ipairs({ bz - 0.9, bz + 0.9 }) do
				Kit.p(m, "HurdleLeg", CFrame.new(hx, y + 0.65, lz), Vector3.new(0.2, 1.3, 0.2), K.Whitewash, M.Wood)
			end
			Kit.p(m, "Hurdle", CFrame.new(hx, y + 1.2, bz), Vector3.new(0.25, 0.3, 2.0), rgb(236, 86, 86), M.Wood)
		end
	end
	-- 3 Ability: a marble pedestal with a glowing orb
	if level >= 3 then
		local x = spotX(3)
		Kit.p(m, "Pedestal", CFrame.new(x, y + 0.2, bz), Vector3.new(1.6, 0.4, 1.6), K.MarbleShade, M.Marble, true)
		Kit.cyl(m, "Pedestal", x, y + 0.4, bz, 0.9, 1.4, K.Marble, M.Marble, true)
		Kit.p(m, "Pedestal", CFrame.new(x, y + 1.95, bz), Vector3.new(1.3, 0.3, 1.3), gold and K.Gold or K.MarbleShade, gold and M.Metal or M.Marble)
		Kit.ball(m, "Orb", Vector3.new(x, y + 2.75, bz), 1.2, rgb(176, 130, 255), M.Neon)
	end
	-- 4 Defense: a plank wall with a round shield
	if level >= 4 then
		local x = spotX(4)
		Kit.p(m, "ShieldWall", CFrame.new(x, y + 1.8, hz - 0.9), Vector3.new(2.8, 3.6, 0.4), K.PlanksDark, M.Planks, true)
		Kit.p(m, "ShieldWallCap", CFrame.new(x, y + 3.75, hz - 0.9), Vector3.new(3.2, 0.3, 0.7), K.WoodDark, M.Wood)
		Kit.cylAt(m, "Shield", CFrame.new(x, y + 1.9, hz - 1.18) * CFrame.Angles(0, PI / 2, 0), 0.16, 2.2, rgb(84, 140, 226), M.Metal)
		Kit.cylAt(m, "ShieldBoss", CFrame.new(x, y + 1.9, hz - 1.3) * CFrame.Angles(0, PI / 2, 0), 0.14, 0.7, gold and K.Gold or K.Iron, M.Metal)
	end
	-- 5: a scoreboard with three lights and a trophy on a little stand
	if gold then
		local x = spotX(5)
		for _, sx in ipairs({ -1, 1 }) do
			Kit.p(m, "BoardPost", CFrame.new(x + sx * 1.8, y + 2.4, hz - 0.8), Vector3.new(0.35, 4.8, 0.35), K.WoodDark, M.Wood)
		end
		Kit.p(m, "Board", CFrame.new(x, y + 4.0, hz - 0.8), Vector3.new(3.4, 1.6, 0.3), K.SlateDark, M.Slate)
		local lights = { rgb(120, 220, 130), rgb(250, 214, 90), rgb(255, 120, 110) }
		for i, c in ipairs(lights) do
			Kit.p(m, "BoardLight", CFrame.new(x - 1.6 + 0.8 * i, y + 4.0, hz - 1.0), Vector3.new(0.5, 0.5, 0.12), c, M.Neon)
		end
		Kit.p(m, "TrophyStand", CFrame.new(x, y + 0.5, bz), Vector3.new(1.0, 1.0, 1.0), K.MarbleShade, M.Marble, true)
		Kit.cyl(m, "Trophy", x, y + 1.0, bz, 0.5, 0.6, K.GoldBright, M.Metal)
		Kit.cyl(m, "Trophy", x, y + 1.6, bz, 1.0, 0.55, K.GoldBright, M.Metal)
	end
	-- pennant posts at the deck's back corners (3+)
	if level >= 3 then
		local d = Kit.detail(m, "Pennants")
		for _, px in ipairs({ x0 + 0.4, x1 - 0.4 }) do
			Kit.p(d, "PennantPost", CFrame.new(px, y + 2.6, hz - 0.4), Vector3.new(0.3, 5.2, 0.3), gold and K.Gold or K.WoodDark, gold and M.Metal or M.Wood)
			local fx = (px < cx) and (px + 0.85) or (px - 0.85)
			Kit.p(d, "Pennant", CFrame.new(fx, y + 4.6, hz - 0.4), Vector3.new(1.4, 0.9, 0.06), rgb(236, 86, 86), M.Fabric)
		end
	end
	-- the training mats (one per level) and their Spot<i> attachments on the deck
	for i, p in ipairs(spots) do
		if i <= level then
			Kit.p(m, "Mat", CFrame.new(p.X, y + 0.05, p.Z), Vector3.new(2.6, 0.1, 2.6), Kit.jit(TRAIN_MATS[i] or TRAIN_MATS[1], i), M.Fabric)
			Kit.p(m, "MatIn", CFrame.new(p.X, y + 0.11, p.Z), Vector3.new(1.5, 0.04, 1.5), K.Whitewash, M.Fabric)
			attach(deck, "Spot" .. i, Vector3.new(p.X, y + 0.15, p.Z), { Slot = i })
		end
	end
	return tpl
end

----------------------------------------------------------------------
-- Vault: front -Z. A chamfered slate strongroom on a plinth with a marble cornice and a round metal door (1),
-- marble pilasters and a brass band (2), a glass gem case on top (3), coin stacks and sconces (4), a gold crown (5).
-- <= 80 parts.
----------------------------------------------------------------------
function Art.Vault(def, level)
	local tpl = newTemplate("Vault")
	local m = tpl.Model
	local w, d, h = 5.6, 6.0, 4.4
	Kit.p(m, "Plinth", CFrame.new(0, 0.3, 0), Vector3.new(w + 1.0, 0.6, d + 1.0), K.SlateDark, M.Slate, true)
	Kit.p(m, "Step", CFrame.new(0, 0.15, -d / 2 - 1.0), Vector3.new(3.2, 0.3, 1.2), K.Slate, M.Slate, true)
	Kit.p(m, "Vault", CFrame.new(0, 0.6 + h / 2, 0), Vector3.new(w, h, d), rgb(218, 212, 200), M.Slate, true)
	Kit.p(m, "Cornice", CFrame.new(0, 0.6 + h + 0.12, 0), Vector3.new(w + 0.6, 0.24, d + 0.6), rgb(100, 122, 170), M.Marble, true)
	Kit.p(m, "Roof", CFrame.new(0, 0.6 + h + 0.32, 0), Vector3.new(w - 0.4, 0.16, d - 0.4), rgb(84, 104, 150), M.Slate)
	for _, y in ipairs({ 1.55, 3.95 }) do
		Kit.p(m, "Course", CFrame.new(0, y, 0), Vector3.new(w + 0.12, 0.16, d - 1.2), K.SlateLight, M.Slate)
		Kit.p(m, "Course", CFrame.new(0, y, 0), Vector3.new(w - 1.2, 0.16, d + 0.12), K.SlateLight, M.Slate)
	end
	Kit.p(m, "Keystone", CFrame.new(0, 4.55, -d / 2 - 0.1), Vector3.new(0.9, 0.7, 0.2), K.MarbleShade, M.Marble)
	-- the round door: a metal disc, a hub, a three-spoke wheel
	local dz = -d / 2 - 0.08
	Kit.cylAt(m, "Door", CFrame.new(0, 2.6, dz) * CFrame.Angles(0, PI / 2, 0), 0.18, 3.0, K.Iron, M.Metal)
	Kit.cylAt(m, "DoorRing", CFrame.new(0, 2.6, dz - 0.1) * CFrame.Angles(0, PI / 2, 0), 0.06, 2.5, K.IronDark, M.Metal)
	Kit.cylAt(m, "Hub", CFrame.new(0, 2.6, dz - 0.18) * CFrame.Angles(0, PI / 2, 0), 0.16, 0.7, K.Gold, M.Metal)
	for k = 0, 2 do
		Kit.p(m, "Spoke", CFrame.new(0, 2.6, dz - 0.2) * CFrame.Angles(0, 0, rad(k * 60)), Vector3.new(1.9, 0.14, 0.08), K.Gold, M.Metal)
	end
	if level >= 2 then
		for _, sx in ipairs({ -1, 1 }) do
			Kit.p(m, "Pilaster", CFrame.new(sx * 2.15, 0.6 + h / 2, -d / 2 - 0.15), Vector3.new(0.6, h, 0.3), K.MarbleShade, M.Marble)
		end
		Kit.p(m, "Band", CFrame.new(0, 0.6 + h - 0.35, -d / 2 - 0.12), Vector3.new(w - 1.4, 0.25, 0.1), K.Gold, M.Metal)
	end
	local topY = 0.6 + h + 0.4
	if level >= 3 then
		-- a glass gem case on the roof
		Kit.p(m, "CaseBase", CFrame.new(0, topY + 0.2, 0), Vector3.new(2.6, 0.4, 2.6), K.MarbleShade, M.Marble)
		Kit.p(m, "GemCase", CFrame.new(0, topY + 1.3, 0), Vector3.new(2.2, 1.8, 2.2), rgb(214, 234, 246), M.Glass, false, { Transparency = 0.6 })
		Kit.p(m, "CaseLid", CFrame.new(0, topY + 2.3, 0), Vector3.new(2.6, 0.2, 2.6), K.Gold, M.Metal)
		local gems = { { -0.45, rgb(120, 220, 255) }, { 0.5, rgb(255, 130, 190) }, { 0.0, rgb(140, 240, 160) } }
		for i, g in ipairs(gems) do
			Kit.p(m, "Gem", CFrame.new(g[1], topY + 0.75 + 0.15 * i, (i - 2) * 0.3) * CFrame.Angles(rad(45), rad(35), 0), Vector3.new(0.55, 0.55, 0.55), g[2], M.Neon)
		end
	end
	if level >= 4 then
		local deco = Kit.detail(m, "VaultDecor")
		for _, sx in ipairs({ -1, 1 }) do
			Kit.cyl(deco, "Coins", sx * 2.4, 0.6, -d / 2 - 0.9, 0.9, 0.5 + 0.15 * (sx + 1), K.GoldBright, M.Metal)
			Kit.lantern(deco, Vector3.new(sx * 2.15, 3.9, -d / 2 - 0.55), 0.42, sx > 0)
		end
	end
	if level >= 5 then
		local cy = topY + ((level >= 3) and 2.4 or 0)
		Kit.cyl(m, "Crown", 0, cy, 0, 1.8, 0.4, K.GoldBright, M.Metal)
		for k = 0, 3 do
			local a = k * PI / 2 + PI / 4
			Kit.p(m, "CrownPoint", CFrame.new(math.cos(a) * 0.65, cy + 0.65, math.sin(a) * 0.65) * CFrame.Angles(0, -a, 0), Vector3.new(0.3, 0.6, 0.3), K.GoldBright, M.Metal)
		end
		local att = Instance.new("Attachment")
		att.Name = "Sparkle"
		local anchor = biggestPart(m, "Cornice") or biggestPart(m)
		att.CFrame = anchor.CFrame:Inverse() * CFrame.new(0, cy + 1.0, 0)
		att.Parent = anchor
		emitter(att, { Color = ColorSequence.new(C.TextGold), Rate = 3, SpreadAngle = Vector2.new(180, 180) })
	end
	return tpl
end

----------------------------------------------------------------------
-- Fusion Machine: front -Z. A slate-and-marble dais with a neon inlay line, two glass input pods on metal pedestals
-- (cyan left, magenta right) piped into the marble-ringed glass chamber where the `Swirl` (a Model HomeFx spins: two
-- cloud puffs around a glowing heart) turns, and a small output pod in front. Brass trims and lamps (2), crystal
-- shards and sparkles (3). `FusionPrompt` ("Fuse", owner only) on PromptPoint, SwirlCenter, ChamberLight. <= 90.
----------------------------------------------------------------------
function Art.Fusion(def, level)
	local tpl = newTemplate("FusionMachine")
	local m = tpl.Model
	local gold = level >= 2
	local trim = gold and K.Gold or K.Iron
	local cz = 1.0
	local violet = rgb(170, 118, 255)
	Kit.oct(m, "Base", 0, 0, 0.5, 9.4, 0.5, rgb(84, 72, 160), M.Slate, true)
	local deckA = Kit.oct(m, "Deck", 0, 0.5, 0.5, 8.4, 0.45, rgb(150, 128, 226), M.Marble, true)
	deckA.Name = "Deck"
	Kit.oct(m, "Inlay", 0, 0.62, 0.5, 8.6, 0.08, violet, M.Neon)
	Kit.p(m, "Step", CFrame.new(0, 0.25, -4.7), Vector3.new(3.0, 0.5, 1.2), K.Slate, M.Slate, true)
	Kit.p(m, "StepInlay", CFrame.new(0, 0.52, -4.7), Vector3.new(2.0, 0.04, 0.3), violet, M.Neon)
	-- the input pods
	for _, sx in ipairs({ -1, 1 }) do
		local px = sx * 3.0
		local glow = (sx < 0) and rgb(110, 230, 240) or rgb(240, 120, 210)
		Kit.cyl(m, "PodBase", px, 0.95, cz, 1.9, 0.6, trim, M.Metal, true)
		Kit.cyl(m, "Pod", px, 1.55, cz, 1.5, 2.6, rgb(214, 234, 246), M.Glass).Transparency = 0.55
		Kit.cyl(m, "PodCore", px, 1.75, cz, 0.6, 1.6, glow, M.Neon)
		Kit.cyl(m, "PodLid", px, 4.15, cz, 1.9, 0.45, trim, M.Metal)
		-- a pipe from the lid into the chamber
		Kit.cylAt(m, "Pipe", CFrame.new(px * 0.62, 4.75, cz), abs(px) * 0.75, 0.4, K.Copper, M.Metal)
		Kit.p(m, "PipeElbow", CFrame.new(px, 4.55, cz), Vector3.new(0.45, 0.6, 0.45), K.Copper, M.Metal)
	end
	-- the chamber: a marble base ring and crown ring around a glass column, neon inlay bands and three marble ribs
	Kit.cyl(m, "ChamberBase", 0, 0.95, cz, 3.4, 0.7, K.Marble, M.Marble, true)
	Kit.cyl(m, "Chamber", 0, 1.65, cz, 2.8, 5.0, rgb(214, 226, 246), M.Glass).Transparency = 0.6
	Kit.cyl(m, "ChamberCrown", 0, 6.65, cz, 3.4, 0.7, K.Marble, M.Marble)
	Kit.cyl(m, "ChamberInlay", 0, 1.6, cz, 3.45, 0.12, violet, M.Neon)
	Kit.cyl(m, "ChamberInlay", 0, 6.6, cz, 3.45, 0.12, violet, M.Neon)
	for k = 0, 2 do
		local a = rad(90 + k * 120)
		Kit.p(m, "Rib", CFrame.new(math.cos(a) * 1.5, 4.15, cz + math.sin(a) * 1.5) * CFrame.Angles(0, -a, 0), Vector3.new(0.35, 5.0, 0.35), K.MarbleShade, M.Marble)
	end
	Kit.cyl(m, "ChamberCap", 0, 7.35, cz, 1.6, 0.5, trim, M.Metal)
	local crystalColor = (level >= 3) and rgb(255, 226, 150) or rgb(200, 170, 255)
	Kit.p(m, "Crystal", CFrame.new(0, 8.3, cz) * CFrame.Angles(rad(45), rad(45), 0), Vector3.new(0.7, 0.7, 0.7), crystalColor, M.Neon)
	-- the output pod in front
	Kit.cyl(m, "OutputBase", 0, 0.95, -2.6, 1.6, 0.5, trim, M.Metal, true)
	Kit.ball(m, "OutputDome", Vector3.new(0, 1.55, -2.6), 1.3, rgb(214, 234, 246), M.Glass).Transparency = 0.5
	if gold then
		local deco = Kit.detail(m, "FusionDecor")
		for _, sx in ipairs({ -1, 1 }) do
			Kit.lantern(deco, Vector3.new(sx * 3.6, 1.35, -3.0), 0.4, false)
		end
	end
	if level >= 3 then
		for _, sx in ipairs({ -1, 1 }) do
			Kit.p(m, "Shard", CFrame.new(sx * 3.4, 1.9, 3.6) * CFrame.Angles(0, rad(45), rad(sx * 12)), Vector3.new(0.6, 1.8, 0.6), rgb(150, 230, 255), M.Neon)
		end
	end
	-- the swirl (HomeFx spins it): two cloud puffs on a rising spiral around a glowing heart (voxel-cloud palette)
	local swirl = Instance.new("Model")
	swirl.Name = "Swirl"
	CollectionService:AddTag(swirl, EXEMPT_TAG)
	Kit.ball(swirl, "Cloud", Vector3.new(0.7, 3.2, cz), 1.3, K.CloudTop, M.Plastic)
	Kit.ball(swirl, "Cloud", Vector3.new(-0.7, 4.9, cz), 1.2, K.CloudSide, M.Plastic)
	Kit.p(swirl, "Heart", CFrame.new(0, 4.0, cz), Vector3.new(0.5, 2.4, 0.5), (level >= 3) and rgb(255, 230, 160) or rgb(214, 176, 255), M.Neon, false, { Transparency = 0.15 })
	swirl.Parent = m
	tpl.Points.SwirlCenter = Vector3.new(0, 4.1, cz)
	local prompt = newPrompt("FusionPrompt", "Fuse", "Fusion Machine", "FusionMachine")
	local deck = biggestPart(m, "Deck") or biggestPart(m)
	if deck then
		local att = attach(deck, "PromptPoint", Vector3.new(0, 2.5, -3.0))
		prompt.Parent = att
		local light = attach(deck, "ChamberLight", Vector3.new(0, 4.0, cz))
		pointLight(light, rgb(186, 120, 255), 1.2, 16)
		if level >= 3 then
			emitter(light, { Color = ColorSequence.new(rgb(214, 180, 255), C.TextGold), Rate = 4, SpreadAngle = Vector2.new(180, 180) })
		end
	end
	return tpl
end

----------------------------------------------------------------------
-- Arena Gate (Kind Arena): front -Z. The P4 home Arena Gate (7aa0df2 Art.Arena): two square stone pillars on
-- plinths, a stone lintel with a red shield crest and crossed swords, a violet neon inlay around the opening, the
-- violet portal + a ForceField shimmer, braziers on top and red banners. `ArenaGatePrompt` ("Go to Arena", owner
-- only, attributes StationId / Teleport = "Arena"; ArenaBuilder teleports). <= 80 parts.
----------------------------------------------------------------------
function Art.ArenaGate(def, level)
	local tpl = newTemplate("ArenaGate")
	local m = tpl.Model
	local accent = rgb(140, 96, 220) -- the P4 home Arena Gate: a violet portal under a red shield
	local cx = 2.55 -- column centres at +-cx
	local colH = 7.4
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * cx
		Kit.p(m, "Plinth", CFrame.new(x, 0.45, 0), Vector3.new(1.9, 0.9, 1.9), K.SlateDark, M.Slate, true)
		Kit.p(m, "PlinthBand", CFrame.new(x, 0.95, 0), Vector3.new(2.05, 0.15, 2.05), K.MarbleShade, M.Marble)
		Kit.cyl(m, "Column", x, 1.0, 0, 1.35, colH, K.Marble, M.Marble, true)
		Kit.p(m, "Capital", CFrame.new(x, 1.0 + colH + 0.25, 0), Vector3.new(1.8, 0.5, 1.8), K.MarbleShade, M.Marble)
		Kit.p(m, "Banner", CFrame.new(x, 5.0, -0.72), Vector3.new(0.9, 3.4, 0.06), rgb(214, 70, 74), M.Fabric)
		Kit.p(m, "Brazier", CFrame.new(x, 11.05, 0), Vector3.new(0.9, 0.5, 0.9), K.IronDark, M.Metal)
		local fire = Kit.p(m, "Fire", CFrame.new(x, 11.55, 0), Vector3.new(0.55, 0.6, 0.55), rgb(255, 170, 80), M.Neon)
		if sx > 0 then
			pointLight(fire, LANTERN, 1.2, 12)
		end
	end
	local ly = 1.0 + colH + 0.5
	Kit.p(m, "Lintel", CFrame.new(0, ly + 0.7, 0), Vector3.new(6.9, 1.4, 2.0), K.Slate, M.Slate, true)
	Kit.p(m, "Cornice", CFrame.new(0, ly + 1.55, 0), Vector3.new(7.0, 0.3, 2.3), K.MarbleShade, M.Marble)
	Kit.cylAt(m, "Medallion", CFrame.new(0, ly + 0.7, -1.05) * CFrame.Angles(0, PI / 2, 0), 0.2, 1.7, rgb(196, 58, 66), M.Marble)
	for _, sx in ipairs({ -1, 1 }) do
		local cf = CFrame.new(0, ly + 0.7, -1.2) * CFrame.Angles(0, 0, rad(sx * 40))
		Kit.p(m, "Sword", cf, Vector3.new(0.22, 1.7, 0.06), rgb(214, 222, 236), M.Metal)
		Kit.p(m, "Hilt", cf * CFrame.new(0, -0.7, 0), Vector3.new(0.7, 0.16, 0.08), K.GoldBright, M.Metal)
	end
	-- the opening: a neon inlay frame, the red disc and the ForceField shimmer (non-solid)
	local ow, oh = 3.5, colH
	Kit.p(m, "Inlay", CFrame.new(-ow / 2 - 0.12, 1.0 + oh / 2, -0.35), Vector3.new(0.18, oh, 0.18), accent, M.Neon)
	Kit.p(m, "Inlay", CFrame.new(ow / 2 + 0.12, 1.0 + oh / 2, -0.35), Vector3.new(0.18, oh, 0.18), accent, M.Neon)
	Kit.p(m, "Inlay", CFrame.new(0, ly - 0.05, -0.35), Vector3.new(ow + 0.42, 0.18, 0.18), accent, M.Neon)
	Kit.p(m, "Portal", CFrame.new(0, 1.0 + oh / 2, 0), Vector3.new(ow, oh, 0.12), accent, M.Neon, false, { Transparency = 0.35 })
	Kit.p(m, "Shimmer", CFrame.new(0, 1.0 + oh / 2, -0.1), Vector3.new(ow, oh, 0.05), rgb(206, 180, 255), M.Force, false, { Transparency = 0.2 })
	Kit.p(m, "Threshold", CFrame.new(0, 0.3, 0), Vector3.new(ow + 0.6, 0.6, 2.6), K.Slate, M.Slate, true)
	local prompt = newPrompt("ArenaGatePrompt", "Go to Arena", "Arena Gate", "ArenaGate")
	prompt:SetAttribute("Teleport", "Arena")
	local portal = biggestPart(m, "Portal") or biggestPart(m)
	if portal then
		prompt.Parent = attach(portal, "PromptPoint", Vector3.new(0, 3.0, -1.5))
	end
	return tpl
end
----------------------------------------------------------------------
-- House (4 tiers; Phase 6 A1 = the P4 colours): front -Z toward the gate (the HouseWalk ends at local z -10). Stone
-- plinths, walls with corner posts, stepped voxel roofs, glass windows, warm lanterns. Cottage (cream walls, a
-- terracotta roof, a chimney), Villa (two storeys: peach below, cream above, a porch, a cross gable, terracotta
-- roofs), Manor (a lavender-white hall with two wings, slate-blue roofs, a white portico), Sky Castle (a white keep,
-- four square towers with blue stepped spires and gold tips, pink banners, a rose window). <= 150 parts.
----------------------------------------------------------------------
local House = {}

-- a walled block: a plinth band, the walls (centre cx, cz; w x d; from y0, h tall) and its four corner posts
function House.block(m, name, cx, cz, w, d, y0, h, color, mat, postColor)
	Kit.p(m, name, CFrame.new(cx, y0 + h / 2, cz), Vector3.new(w, h, d), color, mat, true)
	Kit.corners(m, cx - w / 2 + 0.15, cx + w / 2 - 0.15, cz - d / 2 + 0.15, cz + d / 2 - 0.15, y0, h, postColor or K.WoodDark, M.Wood)
end

-- a row of windows on the front wall (z = the wall's front face)
function House.windows(m, xs, y, z, w, h, frame)
	for _, x in ipairs(xs) do
		Kit.window(m, CFrame.new(x, y, z), w, h, frame)
	end
end

function House.door(m, x, y0, z, w, h, frame)
	Kit.p(m, "DoorFrame", CFrame.new(x, y0 + (h + 0.3) / 2, z - 0.06), Vector3.new(w + 0.5, h + 0.3, 0.12), frame or K.Whitewash, M.Wood)
	Kit.p(m, "Door", CFrame.new(x, y0 + h / 2, z - 0.14), Vector3.new(w, h, 0.1), K.WoodDark, M.Wood)
end

function House.chimney(m, x, z, y0, h)
	Kit.p(m, "Chimney", CFrame.new(x, y0 + h / 2, z), Vector3.new(1.3, h, 1.3), K.Brick, M.Brick, true)
	Kit.p(m, "ChimneyCap", CFrame.new(x, y0 + h + 0.15, z), Vector3.new(1.6, 0.3, 1.6), K.SlateDark, M.Slate)
end

function House.cottage(m)
	Kit.p(m, "Plinth", CFrame.new(0, 0.35, 0), Vector3.new(13.2, 0.7, 9.2), K.SlateDark, M.Slate, true)
	House.block(m, "Walls", 0, 0, 12, 8, 0.7, 4.6, K.Cream, M.Planks, K.Wood)
	Kit.gable(m, "Roof", CFrame.new(0, 5.3, 0), 12, 8, 3.4, K.Roof, M.Clay, { Overhang = 0.8, Ridge = K.RoofDark, Dark = K.RoofDark })
	House.door(m, 0, 0.7, -4, 1.8, 3.0)
	House.windows(m, { -3.6, 3.6 }, 2.9, -4, 1.8, 1.5)
	Kit.window(m, CFrame.new(6, 2.9, 0) * CFrame.Angles(0, -PI / 2, 0), 1.6, 1.4)
	House.chimney(m, 3.8, 1.6, 6.0, 3.6)
	Kit.p(m, "Step", CFrame.new(0, 0.2, -5.2), Vector3.new(3.0, 0.4, 1.4), K.Slate, M.Slate, true)
	local d = Kit.detail(m, "HouseDecor")
	for _, x in ipairs({ -1.6, 1.6 }) do
		Kit.lantern(d, Vector3.new(x, 3.2, -4.35), 0.45, x > 0)
	end
	for _, x in ipairs({ -3.6, 3.6 }) do
		Kit.p(d, "FlowerBox", CFrame.new(x, 1.75, -4.35), Vector3.new(1.9, 0.4, 0.5), K.PlanksDark, M.Planks)
		Kit.p(d, "Flowers", CFrame.new(x, 2.05, -4.35), Vector3.new(1.7, 0.25, 0.4), rgb(246, 150, 188), M.Leafy)
	end
	return 9.6
end

function House.villa(m)
	local w, d = 18, 11
	Kit.p(m, "Plinth", CFrame.new(0, 0.35, 0.5), Vector3.new(w + 1.2, 0.7, d + 1.2), K.SlateDark, M.Slate, true)
	House.block(m, "Walls", 0, 0.5, w, d, 0.7, 4.4, K.Brick, M.Brick, K.Whitewash)
	Kit.p(m, "Band", CFrame.new(0, 5.25, 0.5), Vector3.new(w + 0.4, 0.3, d + 0.4), K.SlateLight, M.Slate)
	House.block(m, "Upper", 0, 0.5, w - 0.4, d - 0.4, 5.4, 3.8, K.Cream, M.Planks, K.Whitewash)
	Kit.gable(m, "Roof", CFrame.new(0, 9.2, 0.5), w - 0.4, d - 0.4, 4.2, K.Roof, M.Clay, { Overhang = 0.9, Ridge = K.RoofDark, Dark = K.RoofDark })
	-- the cross gable over the entrance
	local fz = 0.5 - d / 2
	Kit.p(m, "Bay", CFrame.new(0, 7.3, fz - 0.6), Vector3.new(5.4, 3.8, 1.2), K.Cream, M.Planks, true)
	Kit.gable(m, "BayRoof", CFrame.new(0, 9.2, fz - 0.2) * CFrame.Angles(0, PI / 2, 0), 2.4, 5.4, 2.4, K.Roof, M.Clay, { Overhang = 0.5, Dark = K.RoofDark })
	House.door(m, 0, 0.7, fz, 2.4, 3.2)
	House.windows(m, { -6.4, -3.4, 3.4, 6.4 }, 2.9, fz, 1.6, 1.6)
	House.windows(m, { -6.4, -3.4, 3.4, 6.4 }, 7.2, fz + 0.2, 1.5, 1.5)
	Kit.window(m, CFrame.new(0, 7.4, fz - 1.2), 2.2, 1.6)
	-- the porch: a slate floor, two posts, a little roof
	Kit.p(m, "Porch", CFrame.new(0, 0.3, fz - 1.5), Vector3.new(5.4, 0.6, 3.0), K.Slate, M.Slate, true)
	for _, x in ipairs({ -2.4, 2.4 }) do
		Kit.p(m, "PorchPost", CFrame.new(x, 2.3, fz - 2.6), Vector3.new(0.4, 3.4, 0.4), K.Whitewash, M.Wood)
	end
	Kit.p(m, "PorchRoof", CFrame.new(0, 4.15, fz - 1.6) * CFrame.Angles(rad(12), 0, 0), Vector3.new(6.0, 0.3, 3.0), K.RoofDark, M.Clay)
	House.chimney(m, -5.6, 2.4, 9.6, 4.4)
	House.chimney(m, 5.6, 2.4, 9.6, 4.4)
	local deco = Kit.detail(m, "HouseDecor")
	for _, x in ipairs({ -2.4, 2.4 }) do
		Kit.lantern(deco, Vector3.new(x, 3.4, fz - 0.4), 0.45, x > 0)
	end
	return 14
end

function House.manor(m)
	local cw, cd = 14, 12
	Kit.p(m, "Plinth", CFrame.new(0, 0.4, 0.5), Vector3.new(25.2, 0.8, cd + 1.4), K.SlateDark, M.Slate, true)
	House.block(m, "Walls", 0, 0.5, cw, cd, 0.8, 4.6, K.Manor, M.Brick, K.Whitewash)
	Kit.p(m, "Band", CFrame.new(0, 5.55, 0.5), Vector3.new(cw + 0.4, 0.3, cd + 0.4), K.Marble, M.Marble)
	House.block(m, "Upper", 0, 0.5, cw, cd, 5.7, 4.3, K.Manor, M.Brick, K.Whitewash)
	Kit.p(m, "Cornice", CFrame.new(0, 10.15, 0.5), Vector3.new(cw + 0.6, 0.3, cd + 0.6), K.Marble, M.Marble)
	Kit.gable(m, "Roof", CFrame.new(0, 10.3, 0.5), cw, cd, 5.6, K.Shingle, M.Clay, { Overhang = 0.8, Ridge = K.Gold, Dark = K.ShingleLight })
	-- the wings (their gables face the yard)
	for _, sx in ipairs({ -1, 1 }) do
		local wx = sx * 9.6
		House.block(m, "Wing", wx, 1.0, 5.0, 10, 0.8, 6.0, K.Manor, M.Brick, K.Whitewash)
		Kit.gable(m, "WingRoof", CFrame.new(wx, 6.8, 1.0) * CFrame.Angles(0, PI / 2, 0), 10, 5.0, 3.0, K.Shingle, M.Clay, { Overhang = 0.6, Dark = K.ShingleLight })
		Kit.window(m, CFrame.new(wx, 3.2, -4.0), 1.8, 2.0)
		Kit.window(m, CFrame.new(wx, 7.6, -4.15), 1.0, 1.0, nil, nil, { Sill = false })
	end
	local fz = 0.5 - cd / 2
	House.door(m, 0, 0.8, fz, 2.6, 3.4, K.Marble)
	House.windows(m, { -4.6, -2.3, 2.3, 4.6 }, 3.1, fz, 1.4, 1.9, K.Marble)
	House.windows(m, { -4.6, -2.3, 0, 2.3, 4.6 }, 7.8, fz, 1.4, 1.7, K.Marble)
	-- the marble portico: two columns, an entablature, a pediment, two steps
	for _, x in ipairs({ -2.2, 2.2 }) do
		Kit.cyl(m, "Column", x, 0.8, fz - 1.9, 0.75, 4.6, K.Marble, M.Marble, true)
	end
	Kit.p(m, "Entablature", CFrame.new(0, 5.65, fz - 1.1), Vector3.new(5.6, 0.5, 2.4), K.MarbleShade, M.Marble)
	Kit.gable(m, "Pediment", CFrame.new(0, 5.9, fz - 1.1) * CFrame.Angles(0, PI / 2, 0), 2.4, 5.6, 1.4, K.MarbleShade, M.Marble, { Overhang = 0.25, EndOverhang = 0.1, Dark = K.Marble })
	Kit.p(m, "Steps", CFrame.new(0, 0.5, fz - 1.5), Vector3.new(5.2, 1.0, 2.8), K.Slate, M.Slate, true)
	Kit.p(m, "Steps", CFrame.new(0, 0.2, fz - 3.2), Vector3.new(4.6, 0.4, 1.0), K.SlateLight, M.Slate, true)
	House.chimney(m, -4.2, 3.0, 11.0, 5.4)
	House.chimney(m, 4.2, 3.0, 11.0, 5.4)
	local deco = Kit.detail(m, "HouseDecor")
	for _, x in ipairs({ -3.4, 3.4 }) do
		Kit.lantern(deco, Vector3.new(x, 3.6, fz - 0.35), 0.5, x > 0)
	end
	for _, sx in ipairs({ -1, 1 }) do
		Kit.lantern(deco, Vector3.new(sx * 9.6 + sx * 1.5, 3.4, -4.4), 0.45, false)
	end
	return 15
end

function House.castle(m)
	local hw, hd, hh = 16, 12, 9.0
	local cz = 0.5
	Kit.p(m, "Plinth", CFrame.new(0, 0.45, cz), Vector3.new(hw + 2.0, 0.9, hd + 1.6), K.SlateDark, M.Slate, true)
	House.block(m, "Keep", 0, cz, hw, hd, 0.9, hh, K.Marble, M.Marble, K.MarbleShade)
	Kit.p(m, "Band", CFrame.new(0, 5.2, cz), Vector3.new(hw + 0.3, 0.3, hd + 0.3), K.Gold, M.Slate)
	Kit.p(m, "Cornice", CFrame.new(0, 0.9 + hh + 0.2, cz), Vector3.new(hw + 0.6, 0.4, hd + 0.6), K.MarbleShade, M.Slate)
	-- battlements along the front and the back
	local fz = cz - hd / 2
	for k = 0, 5 do
		local x = -hw / 2 + 1.0 + k * (hw - 2.0) / 5
		for _, z in ipairs({ fz + 0.3, cz + hd / 2 - 0.3 }) do
			Kit.p(m, "Merlon", CFrame.new(x, 0.9 + hh + 0.95, z), Vector3.new(1.2, 1.1, 0.6), K.MarbleShade, M.Marble)
		end
	end
	-- the great door, the portcullis, the rose window
	Kit.p(m, "GateArch", CFrame.new(0, 2.9, fz - 0.1), Vector3.new(4.4, 4.6, 0.3), K.Gold, M.Slate)
	Kit.p(m, "Door", CFrame.new(0, 2.6, fz - 0.28), Vector3.new(3.2, 3.6, 0.12), K.WoodDark, M.Wood)
	Kit.p(m, "Portcullis", CFrame.new(0, 4.25, fz - 0.36), Vector3.new(3.2, 0.5, 0.1), K.Iron, M.Metal)
	Kit.cylAt(m, "RoseFrame", CFrame.new(0, 7.3, fz - 0.06) * CFrame.Angles(0, PI / 2, 0), 0.14, 2.9, K.SlateLight, M.Slate)
	Kit.cylAt(m, "RoseWindow", CFrame.new(0, 7.3, fz - 0.16) * CFrame.Angles(0, PI / 2, 0), 0.08, 2.3, rgb(220, 186, 240), M.Glass)
	House.windows(m, { -5.4, -2.8, 2.8, 5.4 }, 3.0, fz, 1.2, 2.0, K.MarbleShade)
	House.windows(m, { -5.4, -2.8, 2.8, 5.4 }, 7.4, fz, 1.2, 1.8, K.MarbleShade)
	-- the central tower behind the gate
	Kit.cyl(m, "Tower", 0, 0.9 + hh, cz + 1.5, 5.2, 6.0, K.Marble, M.Marble, true)
	Kit.cyl(m, "TowerBand", 0, 0.9 + hh + 6.0, cz + 1.5, 5.8, 0.45, K.Gold, M.Slate)
	Kit.window(m, CFrame.new(0, 0.9 + hh + 3.2, cz + 1.5 - 2.62), 1.1, 1.8, K.MarbleShade, nil, { Sill = false })
	local function spire(x, z, y0, d0, h)
		local steps = { 1.0, 0.8, 0.6, 0.42, 0.26 }
		for k, f in ipairs(steps) do
			Kit.cyl(m, "Spire", x, y0 + (k - 1) * h * 0.17, z, d0 * f, h * 0.17, (k % 2 == 0) and K.RoofBlueDark or K.RoofBlue, M.Clay)
		end
		Kit.cyl(m, "SpireTip", x, y0 + h * 0.85, z, d0 * 0.1, h * 0.2, K.Gold, M.Metal)
	end
	spire(0, cz + 1.5, 0.9 + hh + 6.45, 5.6, 6.2)
	-- four corner towers with spires, windows and banners
	local towers = { { -10.4, cz - 4.6 }, { 10.4, cz - 4.6 }, { -10.4, cz + 4.4 }, { 10.4, cz + 4.4 } }
	for i, t in ipairs(towers) do
		local th = (i <= 2) and 12.5 or 11.0
		Kit.cyl(m, "TowerBase", t[1], 0, t[2], 4.8, 0.9, K.SlateDark, M.Slate, true)
		Kit.cyl(m, "CornerTower", t[1], 0.9, t[2], 4.2, th, Kit.jit(K.Marble, i), M.Marble, true)
		Kit.cyl(m, "TowerBand", t[1], 0.9 + th, t[2], 4.7, 0.4, K.Gold, M.Slate)
		spire(t[1], t[2], 0.9 + th + 0.4, 4.9, 5.2)
		if i <= 2 then
			Kit.window(m, CFrame.new(t[1], 8.0, t[2] - 2.12), 0.9, 1.6, K.MarbleShade, nil, { Sill = false })
			Kit.p(m, "Banner", CFrame.new(t[1] + ((t[1] < 0) and 2.2 or -2.2), 6.4, fz - 0.12), Vector3.new(1.4, 3.6, 0.08), K.Banner, M.Fabric)
		end
	end
	-- the bridge steps and lanterns
	Kit.p(m, "Steps", CFrame.new(0, 0.45, fz - 1.0), Vector3.new(5.0, 0.9, 2.0), K.Slate, M.Slate, true)
	Kit.p(m, "Steps", CFrame.new(0, 0.2, fz - 2.5), Vector3.new(4.4, 0.4, 1.2), K.SlateLight, M.Slate, true)
	local deco = Kit.detail(m, "HouseDecor")
	for _, x in ipairs({ -2.9, 2.9 }) do
		Kit.lantern(deco, Vector3.new(x, 3.8, fz - 0.4), 0.5, true)
	end
	return 30
end

function Art.House(def, level)
	local tpl = newTemplate("House")
	local m = tpl.Model
	level = max(1, min(4, floor(level)))
	local top
	if level == 1 then
		top = House.cottage(m)
	elseif level == 2 then
		top = House.villa(m)
	elseif level == 3 then
		top = House.manor(m)
	else
		top = House.castle(m)
	end
	tpl.Info.Tier = level
	tpl.Points.RoofTop = Vector3.new(0, top, 0)
	return tpl
end

----------------------------------------------------------------------
-- Yard Fence (DecorFence, Perimeter: built in the PLOT frame just inside the lobby's fence, open at the gate),
-- the looks of the old Flower Beds + Banners merged in: picket panels + tulip boxes (1), a hedge + cloth banners +
-- the tulips (2), a cloudstone wall with cloud-capped pillars + royal banners + glowing starflowers (3). <= 90 parts.
----------------------------------------------------------------------
local Fence = {}

-- the runs { x0, z0, x1, z1 } along the yard's edge, the front split at the gate
function Fence.runs(half, inset)
	local e = half - (inset or 0.6)
	local gate = 8.6
	return {
		{ -e, e, e, e },
		{ -e, -e, -e, e },
		{ e, -e, e, e },
		{ -e, -e, -gate, -e },
		{ gate, -e, e, -e },
	}, e, gate
end

-- a box along a run: y0..y1 tall, `thick` across
function Fence.seg(parent, name, r, y0, y1, thick, color, mat, collide, shrink)
	local dx, dz = r[3] - r[1], r[4] - r[2]
	local len = math.sqrt(dx * dx + dz * dz) - (shrink or 0)
	local mid = Vector3.new((r[1] + r[3]) / 2, (y0 + y1) / 2, (r[2] + r[4]) / 2)
	local size = (abs(dx) > abs(dz)) and Vector3.new(len + thick, y1 - y0, thick) or Vector3.new(thick, y1 - y0, len + thick)
	return Kit.p(parent, name, CFrame.new(mid), size, color, mat, collide)
end

-- evenly spaced points along the runs (a corner shared by two runs comes once): fn(x, z, runIndex)
function Fence.points(runs, every, fn)
	local seen = {}
	for i, r in ipairs(runs) do
		local len = math.sqrt((r[3] - r[1]) ^ 2 + (r[4] - r[2]) ^ 2)
		local n = max(1, floor(len / every + 0.5))
		for k = 0, n do
			local f = k / n
			local x, z = lerp(r[1], r[3], f), lerp(r[2], r[4], f)
			local key = floor(x * 2 + 0.5) .. ":" .. floor(z * 2 + 0.5)
			if not seen[key] then
				seen[key] = true
				fn(x, z, i)
			end
		end
	end
end

-- the flower boxes beside the gate (inside the yard, along the front runs): a planter, foliage and blooms
function Fence.flowers(parent, e, gate, colors, glow)
	local d = Kit.detail(parent, "Flowers")
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * 16.2, sx * 25.2
		local cx = (x0 + x1) / 2
		local z = -e + 1.2
		Kit.p(d, "Planter", CFrame.new(cx, 0.35, z), Vector3.new(9.0, 0.7, 0.9), K.PlanksDark, M.Planks)
		Kit.p(d, "Foliage", CFrame.new(cx, 0.85, z), Vector3.new(8.6, 0.4, 0.6), K.Leafy, M.Leafy)
		for k = 1, 5 do
			local bx = cx - 3.6 + (k - 1) * 1.8
			Kit.p(d, "Bloom", CFrame.new(bx, 1.25, z + ((k % 2 == 0) and 0.12 or -0.12)), Vector3.new(0.55, 0.55, 0.55), colors[(k % #colors) + 1], glow and M.Neon or M.Fabric)
		end
	end
end

-- a banner on a pole: pole, crossbar, cloth (+ an emblem for the royal ones)
function Fence.banner(parent, x, z, face, cloth, royal)
	local d = Kit.detail(parent, "Banner")
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, face, 0)
	Kit.p(d, "Pole", cf * CFrame.new(0, 3.3, 0), Vector3.new(0.35, 6.6, 0.35), royal and K.Gold or K.IronDark, M.Metal)
	Kit.p(d, "Crossbar", cf * CFrame.new(0, 6.3, -0.25), Vector3.new(2.2, 0.22, 0.22), royal and K.Gold or K.Wood, royal and M.Metal or M.Wood)
	Kit.p(d, "Cloth", cf * CFrame.new(0, 4.8, -0.3), Vector3.new(1.8, 2.8, 0.08), cloth, M.Fabric)
	if royal then
		Kit.p(d, "Emblem", cf * CFrame.new(0, 4.9, -0.36) * CFrame.Angles(0, 0, rad(45)), Vector3.new(0.7, 0.7, 0.06), K.GoldBright, M.Metal)
	end
end

function Art.Fence(def, level, plotSize)
	local tpl = newTemplate("DecorFence")
	local m = tpl.Model
	local half = (tonumber(plotSize) or 72) / 2
	level = max(1, min(3, floor(level)))
	-- the thicker looks step inward so they fit between the lobby's own fence posts (|x|, |z| >= 35.5) and the
	-- stations along the edge (the Pet Garden ends at x 34)
	local runs, e, gate = Fence.runs(half, ({ 0.6, 1.25, 1.25 })[level])
	if level == 1 then
		-- whitewashed picket panels between a top rail and posts every ~9 studs
		for _, r in ipairs(runs) do
			Fence.seg(m, "Pickets", r, 0, 1.9, 0.22, K.Whitewash, M.Planks, true)
			Fence.seg(m, "Rail", r, 1.55, 1.8, 0.4, Kit.jit(K.Whitewash, 3), M.Wood)
		end
		Fence.points(runs, 9, function(x, z, i)
			Kit.p(m, "Post", CFrame.new(x, 1.15, z), Vector3.new(0.55, 2.3, 0.55), K.Whitewash, M.Wood, true)
		end)
		Fence.flowers(m, e, gate, { rgb(236, 104, 108), rgb(250, 214, 92), rgb(246, 150, 188) }, false)
	elseif level == 2 then
		-- a clipped hedge on a brick kerb, brick pillars, the tulips and cloth banners at the gate and the corners
		for _, r in ipairs(runs) do
			Fence.seg(m, "Kerb", r, 0, 0.5, 1.2, K.Brick, M.Brick, true)
			Fence.seg(m, "Hedge", r, 0.5, 2.3, 1.1, K.Leafy, M.Leafy, true)
			Fence.seg(m, "HedgeTop", r, 2.3, 2.6, 0.8, K.GrassLight, M.Leafy)
		end
		Fence.points(runs, 18, function(x, z)
			Kit.p(m, "Pillar", CFrame.new(x, 1.45, z), Vector3.new(1.3, 2.9, 1.3), K.Brick, M.Brick, true)
			Kit.p(m, "PillarCap", CFrame.new(x, 3.05, z), Vector3.new(1.5, 0.3, 1.5), K.SlateLight, M.Slate)
		end)
		Fence.flowers(m, e, gate, { rgb(236, 104, 108), rgb(250, 214, 92), rgb(246, 150, 188) }, false)
		for _, sx in ipairs({ -1, 1 }) do
			Fence.banner(m, sx * (gate + 0.4), -e, 0, rgb(236, 88, 110), false)
			Fence.banner(m, sx * (e - 1.0), e - 1.0, PI, rgb(236, 88, 110), false)
		end
	else
		-- a cloudstone wall: a slate base, marble wall and cap, pillars with cloud puffs, royal banners, starflowers
		for _, r in ipairs(runs) do
			Fence.seg(m, "WallBase", r, 0, 0.5, 1.1, K.SlateDark, M.Slate, true)
			Fence.seg(m, "Wall", r, 0.5, 1.9, 0.9, K.Marble, M.Marble, true)
			Fence.seg(m, "WallCap", r, 1.9, 2.2, 1.1, K.MarbleShade, M.Marble)
		end
		local clouds = Kit.detail(m, "CloudPuffs")
		CollectionService:AddTag(clouds, EXEMPT_TAG)
		Fence.points(runs, 18, function(x, z)
			Kit.p(m, "Pillar", CFrame.new(x, 1.55, z), Vector3.new(1.3, 3.1, 1.3), K.Marble, M.Marble, true)
			Kit.ball(clouds, "Puff", Vector3.new(x, 3.5, z), 1.5, K.CloudTop, M.Plastic)
		end)
		Fence.flowers(m, e, gate, { rgb(196, 156, 255), rgb(140, 226, 255), rgb(255, 222, 140) }, true)
		for _, sx in ipairs({ -1, 1 }) do
			Fence.banner(m, sx * (gate + 0.4), -e, 0, rgb(150, 116, 226), true)
			Fence.banner(m, sx * (e - 1.0), e - 1.0, PI, rgb(150, 116, 226), true)
			Kit.lantern(m, Vector3.new(sx * gate, 4.6, -e), 0.6, true, "Crystal")
		end
	end
	return tpl
end

----------------------------------------------------------------------
-- Fountain (DecorFountain): the yard's centrepiece inside the ring of stone paths (radius <= 4.3), with the old
-- Lanterns merged in: a marble basin + 4 wood lanterns (1), a second tier + a cobble kerb + 6 brass lanterns (2),
-- a third tier with a cloud and a crystal + 8 crystal lanterns (3). The splash is a ParticleEmitter. <= 80 parts.
----------------------------------------------------------------------
function Art.Fountain(def, level)
	local tpl = newTemplate("DecorFountain")
	local m = tpl.Model
	level = max(1, min(3, floor(level)))
	local eff = (def and def.Effects and def.Effects[level]) or {}
	local style = eff.LanternStyle or ({ "Wood", "Brass", "Crystal" })[level]
	local count = tonumber(eff.Lanterns) or (2 + 2 * level)
	local water = K.Water
	Kit.oct(m, "Plinth", 0, 0, 0, 7.4, 0.4, K.SlateDark, M.Slate, true)
	local basin = Kit.cyl(m, "Basin", 0, 0.4, 0, 6.6, 1.0, K.Marble, M.Marble, true)
	Kit.cyl(m, "BasinFoot", 0, 0.4, 0, 6.9, 0.3, K.MarbleShade, M.Marble, true)
	Kit.cyl(m, "Water", 0, 1.4, 0, 5.9, 0.08, water, M.Glass, false).Transparency = 0.2
	Kit.cyl(m, "Column", 0, 1.4, 0, 0.9, 2.2, K.MarbleShade, M.Marble, true)
	Kit.cyl(m, "Bowl", 0, 3.6, 0, 2.6, 0.45, K.Marble, M.Marble)
	Kit.cyl(m, "BowlWater", 0, 4.0, 0, 2.2, 0.1, water, M.Glass).Transparency = 0.25
	local top = 4.1
	if level >= 2 then
		Kit.oct(m, "Kerb", 0, 0, 0, 8.4, 0.25, K.Cobble, M.Cobble, true)
		Kit.cyl(m, "Column", 0, 4.05, 0, 0.6, 1.6, K.MarbleShade, M.Marble)
		Kit.cyl(m, "Bowl", 0, 5.65, 0, 1.6, 0.35, K.Marble, M.Marble)
		Kit.cyl(m, "Trim", 0, 3.55, 0, 2.7, 0.12, K.Gold, M.Metal)
		top = 6.0
	end
	if level >= 3 then
		local clouds = Kit.detail(m, "Cloud")
		CollectionService:AddTag(clouds, EXEMPT_TAG)
		Kit.ball(clouds, "Puff", Vector3.new(0, 6.6, 0), 1.6, K.CloudTop, M.Plastic)
		Kit.ball(clouds, "Puff", Vector3.new(0.7, 6.3, 0.3), 1.1, K.CloudSide, M.Plastic)
		Kit.ball(clouds, "Puff", Vector3.new(-0.7, 6.25, -0.2), 1.0, K.CloudSide, M.Plastic)
		Kit.p(m, "Crystal", CFrame.new(0, 7.9, 0) * CFrame.Angles(rad(45), 0, rad(35)), Vector3.new(0.8, 0.8, 0.8), rgb(160, 226, 255), M.Neon)
		top = 7.2
	end
	-- the lanterns on an ellipse around the basin (clear of the paths), every other one lit
	local d = Kit.detail(m, "Lanterns")
	for i = 1, count do
		local a = (i - 0.5) / count * 2 * PI + PI / 4
		local x, z = math.cos(a) * 4.25, math.sin(a) * 3.65
		local postColor = (style == "Crystal") and K.Marble or ((style == "Brass") and K.IronDark or K.WoodDark)
		local postMat = (style == "Crystal") and M.Marble or ((style == "Brass") and M.Metal or M.Wood)
		Kit.p(d, "LanternPost", CFrame.new(x, 1.1, z), Vector3.new(0.3, 2.2, 0.3), postColor, postMat)
		Kit.lantern(d, Vector3.new(x, 2.45, z), 0.45, i % 2 == 1, style)
	end
	local att = Instance.new("Attachment")
	att.Name = "Splash"
	att.CFrame = basin.CFrame:Inverse() * CFrame.new(0, top + 0.4, 0)
	att.Parent = basin
	emitter(att, {
		Color = ColorSequence.new(rgb(206, 232, 250)),
		LightEmission = 0.2,
		Rate = 10 + level * 4,
		Lifetime = NumberRange.new(0.8, 1.3),
		Speed = NumberRange.new(4, 6),
		SpreadAngle = Vector2.new(18, 18),
		Acceleration = Vector3.new(0, -14, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.15) }),
	})
	return tpl
end

----------------------------------------------------------------------
-- Pet Podium (DecorPodium): dresses up the lobby's own podium (6 x 6, 3 tall; the best pet stands on it): a slate
-- stage with a marble step ring and corner posts: stone lanterns (1), marble pillars with gold caps + a carpet (2),
-- crystal pillars (3). The looks are unchanged from Phase 4; the materials follow 6.4. <= 80 parts.
----------------------------------------------------------------------
function Art.Podium(def, level)
	local tpl = newTemplate("DecorPodium")
	local m = tpl.Model
	level = max(1, min(3, floor(level)))
	Kit.p(m, "Stage", CFrame.new(0, 0.25, 0), Vector3.new(8, 0.5, 8), K.Slate, M.Slate, true)
	-- the step ring around the podium's foot (its middle left open: no face shared with the podium)
	for _, s in ipairs({ { 0, 3.25, 7, 0.5 }, { 0, -3.25, 7, 0.5 }, { 3.25, 0, 0.5, 6 }, { -3.25, 0, 0.5, 6 } }) do
		Kit.p(m, "Step", CFrame.new(s[1], 0.75, s[2]), Vector3.new(s[3], 0.5, s[4]), K.MarbleShade, M.Marble, true)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x, z = sx * 3.5, sz * 3.5
			if level == 1 then
				Kit.p(m, "Post", CFrame.new(x, 1.75, z), Vector3.new(0.9, 1.5, 0.9), K.SlateLight, M.Slate)
				Kit.lantern(m, Vector3.new(x, 2.8, z), 0.55, false)
			elseif level == 2 then
				Kit.p(m, "Pillar", CFrame.new(x, 2.25, z), Vector3.new(0.9, 2.5, 0.9), K.Marble, M.Marble)
				Kit.p(m, "Cap", CFrame.new(x, 3.65, z), Vector3.new(1.1, 0.3, 1.1), K.Gold, M.Metal)
			else
				Kit.p(m, "Pillar", CFrame.new(x, 1.75, z), Vector3.new(0.9, 1.5, 0.9), K.Marble, M.Marble)
				Kit.p(m, "Cap", CFrame.new(x, 2.65, z), Vector3.new(1.1, 0.3, 1.1), K.Gold, M.Metal)
				Kit.p(m, "Crystal", CFrame.new(x, 3.5, z) * CFrame.Angles(0, rad(45), 0), Vector3.new(0.7, 1.4, 0.7), rgb(150, 220, 255), M.Neon)
			end
		end
	end
	if level >= 2 then
		for _, sz in ipairs({ -1, 1 }) do
			Kit.p(m, "Collar", CFrame.new(0, 2.25, sz * 2.85), Vector3.new(6.2, 0.4, 0.4), K.Gold, M.Metal)
			Kit.p(m, "Collar", CFrame.new(sz * 2.85, 2.25, 0), Vector3.new(0.4, 0.4, 5.3), K.Gold, M.Metal)
		end
		Kit.p(m, "Carpet", CFrame.new(0, 0.53, -4.35), Vector3.new(2.4, 0.06, 0.8), rgb(236, 88, 110), M.Fabric)
	end
	return tpl
end

----------------------------------------------------------------------
-- Template lookup
----------------------------------------------------------------------
local function fallbackTemplate(def, level)
	-- plain stand-in when the art fails: a slate block of the footprint
	local tpl = newTemplate(def.Id)
	local fp = (def.Slot and def.Slot.Footprint) or Vector3.new(6, 6, 6)
	local h = max(1, fp.Y * (0.5 + 0.5 * level / max(1, def.MaxLevel or 1)))
	Kit.p(tpl.Model, "Body", CFrame.new(0, h / 2, 0), Vector3.new(min(fp.X, 30), h, min(fp.Z, 30)), K.Slate, M.Slate, true)
	return tpl
end

local ART_BY_KIND = {
	Farm = Art.Farm,
	Garden = Art.Garden,
	FoodMachine = Art.FoodMachine,
	Training = Art.Training,
	Vault = Art.Vault,
	House = Art.House,
	Fusion = Art.Fusion,
	Arena = Art.ArenaGate,
}
local ART_BY_ID = {
	DecorFence = Art.Fence,
	DecorFountain = Art.Fountain,
	DecorPodium = Art.Podium,
}

-- template for (def, level); the Garden's open bed count changes its art (cache key Garden:<level>:<open>)
local function stationTemplate(def, level, accent, open)
	local key = def.Id .. ":" .. level
	local garden = def.Kind == "Garden"
	if garden then
		open = Garden.clampOpen(open, #Garden.places(def))
		key = key .. ":" .. open
	end
	local tpl = templates[key]
	if tpl then
		return tpl
	end
	local fn = ART_BY_ID[def.Id] or ART_BY_KIND[def.Kind]
	local ok, result = false, nil
	if fn then
		if garden then
			ok, result = pcall(fn, def, level, open)
		else
			ok, result = pcall(fn, def, level, TycoonCatalog and TycoonCatalog.PlotSize or 72, accent)
		end
		if not ok then
			warn("[HomeBuilder] art for " .. key .. " failed: " .. tostring(result))
		end
	end
	if not ok or type(result) ~= "table" then
		result = fallbackTemplate(def, level)
	end
	Kit.finish(result.Model)
	local primary = biggestPart(result.Model)
	if primary then
		result.Model.PrimaryPart = primary
	end
	result.Parts = countParts(result.Model)
	templates[key] = result
	return result
end

----------------------------------------------------------------------
-- Pads
----------------------------------------------------------------------
local PAD_COLORS = {
	Build = C.CashGlow,
	Upgrade = rgb(255, 210, 110),
	Locked = rgb(150, 160, 186),
	Prestige = rgb(196, 140, 255),
}

local function padState(pad)
	if pad.Prestige or pad.StationId == "Prestige" then
		return "Prestige"
	end
	if pad.Locked and pad.Locked ~= "" then
		return "Locked"
	end
	if (tonumber(pad.Level) or 0) <= 0 then
		return "Build"
	end
	return "Upgrade"
end

-- the pad's parts for one state, built once (origin = pad centre on the ground, front -Z = toward the station).
-- Four parts: a stone base (walkable; it carries the BuyPrompt and the sign), the glowing plate in the state's
-- colour and a two-part neon emblem: "+" build, an arrow toward the station upgrade, a padlock, a star (prestige).
local function padTemplate(state)
	local key = "Pad:" .. state
	if templates[key] then
		return templates[key]
	end
	local tpl = newTemplate("Pad")
	local m = tpl.Model
	local glow = PAD_COLORS[state] or PAD_COLORS.Build
	local size = Vector3.new(4, 0.6, 4)
	local cat = catalog()
	if cat and cat.Layout and typeof(cat.Layout.PadSize) == "Vector3" then
		size = cat.Layout.PadSize
	end
	local w, d = size.X, size.Z
	local base = box(m, "Base", CFrame.new(0, 0.2, 0), Vector3.new(w, 0.4, d), (state == "Locked") and C.StoneDark or C.StoneEdge, { Collide = true, Shadow = false })
	box(m, "Glow", CFrame.new(0, 0.45, 0), Vector3.new(w - 0.7, 0.1, d - 0.7), glow, { Material = MAT.Neon, Shadow = false, Collide = true })
	local ec = (state == "Locked") and rgb(214, 220, 236) or rgb(255, 255, 255)
	local eo = { Material = MAT.Neon, Shadow = false }
	local y = 0.52
	if state == "Build" then
		box(m, "Emblem", CFrame.new(0, y, 0), Vector3.new(1.8, 0.05, 0.5), ec, eo)
		box(m, "Emblem", CFrame.new(0, y, 0), Vector3.new(0.5, 0.05, 1.8), ec, eo)
	elseif state == "Upgrade" then
		box(m, "Emblem", CFrame.new(0, y, 0.35), Vector3.new(0.5, 0.05, 1.3), ec, eo)
		box(m, "Emblem", CFrame.new(0, y, -0.45) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.95, 0.05, 0.95), ec, eo)
	elseif state == "Locked" then
		box(m, "Emblem", CFrame.new(0, y, 0.3), Vector3.new(1.3, 0.05, 1.0), ec, eo)
		box(m, "Emblem", CFrame.new(0, y, -0.45), Vector3.new(0.8, 0.05, 0.5), ec, eo)
	else
		box(m, "Emblem", CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(1.2, 0.05, 1.2), ec, eo)
		box(m, "Emblem", CFrame.new(0, y, 0), Vector3.new(1.2, 0.05, 1.2), ec, eo)
	end
	m.PrimaryPart = base
	templates[key] = tpl
	return tpl
end

----------------------------------------------------------------------
-- Plot records
----------------------------------------------------------------------
local lobbyInfo = nil
local plots = {} -- [key] = record
local initialized = false

HomeBuilder.StationBuilt = Util and Util.Signal and Util.Signal() or nil

local function spotKey(spotInfo)
	if type(spotInfo) == "table" then
		return tonumber(spotInfo.Index) or spotInfo
	end
	return tonumber(spotInfo)
end

local function resolveSpot(spotInfo)
	if type(spotInfo) == "number" then
		local spots = lobbyInfo and lobbyInfo.Spots
		return type(spots) == "table" and spots[spotInfo] or nil
	end
	if type(spotInfo) == "table" then
		return spotInfo
	end
	return nil
end

local function plotFrame(spotInfo)
	if typeof(spotInfo.PlotCFrame) == "CFrame" then
		return spotInfo.PlotCFrame
	end
	if typeof(spotInfo.Center) == "Vector3" then
		return CFrame.new(spotInfo.Center)
	end
	return nil
end

local function ownerId(rec)
	return rec.OwnerUserId or 0
end

-- the plot record (created by PreparePlot)
local function recordOf(spotInfo)
	local key = spotKey(spotInfo)
	return key ~= nil and plots[key] or nil
end

local function buildClaimSign(rec)
	if rec.ClaimSign then
		return rec.ClaimSign
	end
	local cf = rec.CF
	local half = (rec.Size or 72) / 2
	local m = Instance.new("Model")
	m.Name = "ClaimSign"
	-- a signboard on a wooden post on the verge beside the gate, facing the street. Two parts only: the free plots
	-- live inside the lobby and count toward its part budget. (World text rule: 50 px per stud, 1.1 stud title,
	-- 0.6 stud info, both fitting the 7 x 2.6 stud board; the GUI draws the board's frame.)
	local base = cf * CFrame.new(11, 0, -half - 2) * CFrame.Angles(0, math.pi, 0)
	box(m, "Post", base * CFrame.new(0, 1.6, 0), Vector3.new(0.6, 3.2, 0.6), C.PlankDark, { Collide = true })
	local board = box(m, "Board", base * CFrame.new(0, 3.9, 0), Vector3.new(7.0, 2.6, 0.4), C.Plank, { Collide = true, Shadow = false })
	local gui = surfaceGui(board, Enum.NormalId.Back, "ClaimGui")
	local panel = plainFrame(gui, "Panel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0 })
	vgradient(panel, C.Violet, C.Navy)
	rounded(panel, 14)
	outline(panel, C.CashGlow, 5, 0.1)
	signText(panel, "FREE HOME", "Title", 56, C.TextGreen, "Title", 0.03, 0.06, 0.94, 0.5)
	signText(panel, "Press E at the gate", "Body", 30, C.Text, "Info", 0.03, 0.58, 0.94, 0.34)
	rec.ClaimSign = m
	return m
end

-- the lobby's own gate part closest to the gate opening (LobbyBuilder names them GateBeam / GateBase / GatePillar)
local GATE_PARTS = { GateBeam = 1, GateBase = 2, GatePillar = 3 }

local function gateHolder(parent, point)
	local best, bestRank, bestDist = nil, huge, huge
	for _, d in ipairs(parent:GetDescendants()) do
		local rank = GATE_PARTS[d.Name]
		if rank and d:IsA("BasePart") then
			local dist = (d.Position - point).Magnitude
			if dist <= 14 and (rank < bestRank or (rank == bestRank and dist < bestDist)) then
				best, bestRank, bestDist = d, rank, dist
			end
		end
	end
	return best
end

local function setClaimVisible(rec, free)
	if rec.ClaimPrompt then
		rec.ClaimPrompt.Enabled = free
	end
	local sign = buildClaimSign(rec)
	if free then
		if sign.Parent ~= rec.ClaimGate then
			sign.Parent = rec.ClaimGate
		end
	else
		sign.Parent = nil
	end
end

function HomeBuilder.PreparePlot(spotInfo)
	spotInfo = resolveSpot(spotInfo)
	if type(spotInfo) ~= "table" then
		return nil
	end
	local key = spotKey(spotInfo)
	local rec = plots[key]
	if rec and rec.Home and rec.Home.Parent then
		return rec.Home
	end
	local cf = plotFrame(spotInfo)
	if not cf then
		warn("[HomeBuilder] PreparePlot: SpotInfo " .. tostring(key) .. " has no PlotCFrame")
		return nil
	end
	local parent = spotInfo.Folder
	if typeof(parent) ~= "Instance" then
		parent = Workspace:FindFirstChild("NimbusHomes") or newFolder(Workspace, "NimbusHomes")
		parent = parent:FindFirstChild(string.format("Spot_%02d", tonumber(spotInfo.Index) or 0)) or newFolder(parent, string.format("Spot_%02d", tonumber(spotInfo.Index) or 0))
	end
	rec = {
		Key = key,
		Spot = spotInfo,
		Index = tonumber(spotInfo.Index) or 0,
		CF = cf,
		Size = tonumber(spotInfo.PlotSize) or (catalog() and catalog().PlotSize) or Config.Lobby.PlotSize or 72,
		Stations = {}, -- [id] = model
		Levels = {}, -- [id] = level
		Pads = {}, -- [id] = { Model, Sig, Prompt, ... }
		Ghosts = {},
		OwnerUserId = 0,
	}
	plots[key] = rec
	local old = parent:FindFirstChild("Home")
	if old then
		old:Destroy()
	end
	local home = newFolder(parent, "Home")
	home:SetAttribute("SpotIndex", rec.Index)
	home:SetAttribute("PlotCFrame", cf)
	home:SetAttribute("OwnerUserId", 0)
	home:SetAttribute("OwnerName", "")
	CollectionService:AddTag(home, HOME_TAG)
	rec.Home = home
	rec.PadFolder = newFolder(home, "Pads")

	-- the claim gate: the prompt rides an Attachment ("ClaimPoint") in the gate opening, on the lobby's own gate part
	-- when the plot has one (no extra part per plot), else on an invisible anchor (ClaimGate/ClaimAnchor)
	local oldGate = parent:FindFirstChild("ClaimGate")
	if oldGate then
		oldGate:Destroy()
	end
	for _, d in ipairs(parent:GetDescendants()) do
		if d:IsA("Attachment") and d.Name == "ClaimPoint" then
			d:Destroy()
		end
	end
	local gate = Instance.new("Model")
	gate.Name = "ClaimGate"
	gate.Parent = parent
	rec.ClaimGate = gate
	local gatePoint = cf * CFrame.new(0, 2.6, -rec.Size / 2)
	local holder = gateHolder(parent, gatePoint.Position) or anchorPart(gate, "ClaimAnchor", gatePoint)
	local anchor = Instance.new("Attachment")
	anchor.Name = "ClaimPoint"
	anchor.CFrame = holder.CFrame:ToObjectSpace(gatePoint)
	anchor.Parent = holder
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimPrompt"
	prompt.ActionText = "Claim Home"
	prompt.ObjectText = "Free home"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = CLAIM_RANGE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("SpotIndex", rec.Index)
	prompt.Parent = anchor
	rec.ClaimPrompt = prompt
	setClaimVisible(rec, true)
	return home
end

----------------------------------------------------------------------
-- Paths (one merged voxel layer of every TycoonCatalog.Layout.Paths entry; built while the plot is owned)
----------------------------------------------------------------------
local PATH_EDGES = false -- a darker outline costs ~2x the parts (junctions fragment it)

local function pathTemplate()
	if templates.Paths then
		return templates.Paths
	end
	local tpl = newTemplate("Paths")
	local cat = catalog()
	local paths = cat and cat.Layout and cat.Layout.Paths or {}
	local g = Voxel and Voxel.NewGrid(1) or nil
	if g then
		local inside = {}
		local function key(i, k)
			return i * 4096 + k
		end
		for _, p in ipairs(paths) do
			local a, b, w = p.Start, p.Finish, p.Width or 4
			if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
				local x0, x1 = min(a.X, b.X) - w / 2, max(a.X, b.X) + w / 2
				local z0, z1 = min(a.Z, b.Z) - w / 2, max(a.Z, b.Z) + w / 2
				for i = floor(x0 + 0.5), floor(x1 + 0.5) - 1 do
					for k = floor(z0 + 0.5), floor(z1 + 0.5) - 1 do
						inside[key(i, k)] = true
					end
				end
			end
		end
		for code in pairs(inside) do
			local i = floor((code + 2048) / 4096)
			local k = code - i * 4096
			local edge = not (inside[key(i + 1, k)] and inside[key(i - 1, k)] and inside[key(i, k + 1)] and inside[key(i, k - 1)])
			local cellKey = edge and "PathEdge" or "Path"
			if not PATH_EDGES then
				cellKey = "Path"
			end
			Voxel.Set(g, i, 0, k, cellKey)
		end
		-- the border: one slab per path, 0.5 stud wider on each side and a hair lower than the path top
		for _, p in ipairs(paths) do
			local a, b, w = p.Start, p.Finish, p.Width or 4
			if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
				local x0, x1 = min(a.X, b.X) - w / 2 - 0.5, max(a.X, b.X) + w / 2 + 0.5
				local z0, z1 = min(a.Z, b.Z) - w / 2 - 0.5, max(a.Z, b.Z) + w / 2 + 0.5
				local half = (catalog() and catalog().PlotSize or 72) / 2 - 0.3
				x0, x1 = max(x0, -half), min(x1, half)
				z0, z1 = max(z0, -half), min(z1, half)
				box(tpl.Model, "PathEdge", CFrame.new((x0 + x1) / 2, -0.02, (z0 + z1) / 2), Vector3.new(x1 - x0, 0.2, z1 - z0), rgb(146, 138, 132), { Collide = true, Shadow = false })
			end
		end
		local model = Voxel.Build(g, {
			VoxelSize = 1,
			Palette = { Path = { Color = rgb(208, 202, 190), Material = MAT.SmoothPlastic }, PathEdge = { Color = rgb(146, 138, 132), Material = MAT.SmoothPlastic } },
			Name = "Paths",
			CFrame = CFrame.new(0.5, -0.32, 0.5), -- one voxel layer whose top sits 0.18 stud over the lawn
			CanCollide = true,
			CanQuery = true,
			CastShadow = false,
		})
		absorb(tpl.Model, model)
	end
	templates.Paths = tpl
	return tpl
end

local function setPaths(rec, on)
	local existing = rec.Home:FindFirstChild("Paths")
	if on then
		if not existing then
			local m = cloneAt(pathTemplate(), rec.CF)
			m.Name = "Paths"
			m.Parent = rec.Home
		end
	elseif existing then
		existing:Destroy()
	end
end

----------------------------------------------------------------------
-- The house lot: while the plot is owned and has no House yet (a new home, or right after a prestige) four stakes
-- and a string mark where the house will stand, with a little pile of planks and a stack of bricks beside it, so an
-- empty yard reads "your house goes here" (12 parts, gone as soon as the House is built; no collisions)
----------------------------------------------------------------------
local function lotTemplate()
	if templates.HouseLot then
		return templates.HouseLot
	end
	local tpl = newTemplate("HouseLot")
	local m = tpl.Model
	-- in the House slot's frame (front -Z, toward the yard); kept clear of the walk in front of the house
	local x0, x1, z0, z1 = -12, 12, -6.5, 8
	local rope = rgb(244, 238, 222)
	local deco = { Shadow = false }
	local plank = { Shadow = false }
	for _, x in ipairs({ x0, x1 }) do
		for _, z in ipairs({ z0, z1 }) do
			box(m, "Stake", CFrame.new(x, 0.8, z), Vector3.new(0.4, 1.6, 0.4), C.Plank, deco)
		end
	end
	box(m, "String", CFrame.new(0, 1.25, z0), Vector3.new(x1 - x0, 0.12, 0.12), rope, deco)
	box(m, "String", CFrame.new(0, 1.25, z1), Vector3.new(x1 - x0, 0.12, 0.12), rope, deco)
	box(m, "String", CFrame.new(x0, 1.25, (z0 + z1) / 2), Vector3.new(0.12, 0.12, z1 - z0), rope, deco)
	box(m, "String", CFrame.new(x1, 1.25, (z0 + z1) / 2), Vector3.new(0.12, 0.12, z1 - z0), rope, deco)
	-- planks (two crossed layers) and bricks inside the lot
	box(m, "Planks", CFrame.new(-6, 0.25, 1.5) * CFrame.Angles(0, math.rad(8), 0), Vector3.new(4.5, 0.5, 1.6), C.PlankLight, plank)
	box(m, "Planks", CFrame.new(-6, 0.75, 1.6) * CFrame.Angles(0, math.rad(-6), 0), Vector3.new(4.0, 0.5, 1.4), C.Plank, plank)
	box(m, "Bricks", CFrame.new(6, 0.5, 2.5), Vector3.new(2.4, 1.0, 1.6), rgb(220, 120, 80), { Shadow = false })
	box(m, "Bricks", CFrame.new(5.8, 1.25, 2.5) * CFrame.Angles(0, math.rad(10), 0), Vector3.new(1.6, 0.5, 1.2), rgb(232, 140, 98), { Shadow = false })
	templates.HouseLot = tpl
	return tpl
end

local function refreshLot(rec)
	local existing = rec.Home:FindFirstChild("HouseLot")
	local want = ownerId(rec) ~= 0 and (rec.Levels.House or 0) <= 0
	if want and not existing then
		local cat = catalog()
		local def = cat and cat.Get("House")
		if def and type(def.Slot) == "table" and typeof(def.Slot.CFrame) == "CFrame" then
			local m = cloneAt(lotTemplate(), rec.CF * def.Slot.CFrame)
			m.Name = "HouseLot"
			m.Parent = rec.Home
		end
	elseif existing and not want then
		existing:Destroy()
	end
end

----------------------------------------------------------------------
-- Stations
----------------------------------------------------------------------
local function stationDef(id)
	local cat = catalog()
	if not cat or type(id) ~= "string" then
		return nil
	end
	local def = cat.Get(id)
	if type(def) ~= "table" or def.Kind == "Prestige" or type(def.Slot) ~= "table" or typeof(def.Slot.CFrame) ~= "CFrame" then
		return nil
	end
	return def
end

local function applyOwnerAttr(rec, root)
	local uid = ownerId(rec)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name ~= "ClaimPrompt" then
			if d:GetAttribute("OwnerUserId") ~= uid then
				d:SetAttribute("OwnerUserId", uid)
			end
			-- buy pads follow their lock; garden places follow SetGarden (Garden.applyPrompts)
			if d.Name ~= "BuyPrompt" and d.Name ~= "GardenSpotPrompt" then
				d.Enabled = uid ~= 0
			end
		end
	end
	root:SetAttribute("OwnerUserId", uid)
end

----------------------------------------------------------------------
-- Garden places (SetGarden) and training mats (SetTraining): per-plot state re-applied to every rebuilt model
----------------------------------------------------------------------
function Garden.openOf(rec)
	local g = rec.Garden
	if g and g.Open then
		return g.Open
	end
	return Garden.defaultOpen()
end

-- GardenSpotPrompt.Enabled = owned AND open AND empty; OwnerUserId on every one (written only on change)
function Garden.applyPrompts(rec)
	local model = rec.Stations.Garden
	if not model then
		return
	end
	local uid = ownerId(rec)
	local open = Garden.openOf(rec)
	local valid = (rec.Garden and rec.Garden.Valid) or {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "GardenSpotPrompt" then
			local slot = tonumber(d:GetAttribute("Slot")) or 0
			local want = uid ~= 0 and slot >= 1 and slot <= open and valid[slot] == nil
			if d.Enabled ~= want then
				d.Enabled = want
			end
			if d:GetAttribute("OwnerUserId") ~= uid then
				d:SetAttribute("OwnerUserId", uid)
			end
		end
	end
end

-- the training mats show who trains on them: attributes Busy / Key / Stat / Ends on each Spot<i> (on change only)
function Garden.applyTraining(rec)
	local model = rec.Stations.Gym
	if not model then
		return
	end
	local pets = rec.Training or {}
	for i = 1, 5 do
		local att = model:FindFirstChild("Spot" .. i, true)
		if att then
			local job = pets[i]
			local busy = job ~= nil
			local values = {
				Busy = busy,
				Key = busy and job.Key or "",
				Stat = busy and job.Stat or "",
				Ends = busy and job.Ends or 0,
			}
			for name, v in pairs(values) do
				if att:GetAttribute(name) ~= v then
					att:SetAttribute(name, v)
				end
			end
		end
	end
end

local function removeGhost(rec, id)
	local g = rec.Ghosts[id]
	if g then
		g:Destroy()
		rec.Ghosts[id] = nil
	end
end

----------------------------------------------------------------------
-- Phase 6 (art-home, ARCHITECTURE_V3 6.1 A7 / recipe 4.8 "World path"): Blender meshes for the station art. Every
-- placed station is tagged with MeshLibrary.Tag(station, "home_<stem>_<level>"): the client hides the Part build
-- locally and shows the fine-voxel mesh (blender/catalog/home.json, built by blender/kit/props/home*.py from THIS
-- file's own Part build). The Part build stays: colliders, names, prompts, attachments, signs and the fallback.
-- Kept visible over the mesh (Mesh.keepOf): Neon / ForceField glow (HomeFx and the light pulse them), the parts HomeFx
-- moves (the Fusion `Swirl`), SurfaceGui sign boards (text stays Parts) and the Garden's bed pieces, which carry one
-- key each (home_bed_<piece>, tagged per Part, so a bed swap never needs a new station key). A key is tagged only
-- when it has an uploaded id (MeshLibrary.Status ~= "missing": the shipped empty MeshIds change nothing) and while
-- its manifest's "LayoutSig" (part count + position / size sums of the Part build it was baked from) still matches
-- the live build, so a later art change can never show a stale mesh. The kit reads Mesh.keepOf / Mesh.signature
-- through HomeBuilder._Mesh, so both sides use the same rules.
----------------------------------------------------------------------
local Mesh = {
	Lib = nil,
	-- key stem per station Kind (decor per Id): home_<stem>_<level>
	Stems = {
		Farm = "farm", Garden = "garden", FoodMachine = "foodmachine", Training = "training", Vault = "vault",
		House = "house", Fusion = "fusion", Arena = "arena", DecorFence = "fence", DecorFountain = "fountain",
		DecorPodium = "podium",
	},
	-- per-Part element keys (station Kind -> part name -> key); the element meshes' own parts use the same names
	Elements = {
		Garden = {
			Bed = "home_bed_frame", Cushion = "home_bed_cushion", Headboard = "home_bed_headboard",
			BedRoof = "home_bed_roof", SoilBed = "home_bed_soil", Stem = "home_bed_stem", Sprout = "home_bed_sprout",
			Post = "home_bed_post",
		},
	},
	NoElements = {},
}

function Mesh.lib()
	if Mesh.Lib == nil then
		Mesh.Lib = false
		local module = Shared:FindFirstChild("MeshLibrary")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" and type(result.Tag) == "function" and type(result.Status) == "function" then
				Mesh.Lib = result
			end
		end
	end
	return Mesh.Lib or nil
end

function Mesh.elementsOf(def)
	return (def and Mesh.Elements[def.Kind]) or Mesh.NoElements
end

-- the part names that stay visible over a dressed station (sorted list) + the set
function Mesh.keepOf(model, elements)
	local set = {}
	for name in pairs(elements or Mesh.NoElements) do
		set[name] = true
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local keep = d.Material == MAT.Neon or d.Material == MAT.ForceField
				or (d.Material ~= MAT.Glass and d.Transparency > 0.05 and d.Transparency < 0.99)
				or d:FindFirstChildWhichIsA("SurfaceGui") ~= nil
			local a = d.Parent
			while not keep and a and a ~= model do
				if a.Name == "Swirl" then
					keep = true
				end
				a = a.Parent
			end
			if keep then
				set[d.Name] = true
			end
		end
	end
	local list = {}
	for name in pairs(set) do
		list[#list + 1] = name
	end
	table.sort(list)
	return list, set
end

-- part count + weighted sums of the visible, not kept BaseParts in `origin` space (LobbyBuilder Mesh.Signature's
-- formula; the kit stores the same numbers as the manifest attachment "LayoutSig")
function Mesh.signature(target, origin, skip)
	local inv = origin:Inverse()
	local n, a, b = 0, 0, 0
	local list = target:GetDescendants()
	list[#list + 1] = target
	for _, d in ipairs(list) do
		if d:IsA("BasePart") and d.Transparency < 0.99 and not (skip and skip[d.Name]) then
			local p = inv * d.Position
			local s = d.Size
			n = n + 1
			a = a + p.X + p.Y * 0.37 + p.Z * 0.61
			b = b + s.X + s.Y * 1.3 + s.Z * 1.7
		end
	end
	return n, a, b
end

function Mesh.sigOk(ML, key, n, a, b)
	local man = type(ML.Manifest) == "function" and ML.Manifest(key)
	local att = man and man.Attachments and (man.Attachments.LayoutSig or man.Attachments.layoutSig)
	local pos = att and (att.Pos or att.pos)
	if type(pos) ~= "table" then
		return false -- every home key is baked from a layout
	end
	local tol = 0.05 + n * 1e-4
	return n == pos[1] and math.abs(a - pos[2]) <= tol and math.abs(b - pos[3]) <= tol
end

-- per template (cached): the station key, keep list and layout signature in template space
function Mesh.info(def, level, tpl)
	if tpl.Mesh then
		return tpl.Mesh
	end
	local stem = Mesh.Stems[def.Id] or Mesh.Stems[def.Kind]
	local elements = Mesh.elementsOf(def)
	local keepList, keepSet = Mesh.keepOf(tpl.Model, elements)
	local n, a, b = Mesh.signature(tpl.Model, CFrame.new(), keepSet)
	tpl.Mesh = { Key = stem and ("home_" .. stem .. "_" .. level) or nil, Keep = keepList, Sig = { n, a, b } }
	return tpl.Mesh
end

-- tags a placed station (model pivot = cf) and its element parts; returns the number of tags
function Mesh.station(m, def, level, tpl, cf)
	local ML = Mesh.lib()
	if not ML or not tpl or not tpl.Model then
		return 0
	end
	local info = Mesh.info(def, level, tpl)
	local tags = 0
	local key = info.Key
	if key and ML.Status(key) ~= "missing" and Mesh.sigOk(ML, key, info.Sig[1], info.Sig[2], info.Sig[3]) then
		ML.Tag(m, key, { Offset = m:GetPivot():Inverse() * cf }, info.Keep)
		tags = tags + 1
	end
	local elements = Mesh.elementsOf(def)
	if next(elements) then
		for _, d in ipairs(m:GetDescendants()) do
			local ekey = d:IsA("BasePart") and elements[d.Name]
			if ekey and d.Transparency < 0.99 and ML.Status(ekey) ~= "missing" then
				local n, a, b = Mesh.signature(d, d.CFrame)
				if Mesh.sigOk(ML, ekey, n, a, b) then
					ML.Tag(d, ekey, { Primary = d.Color }, nil) -- a tinted piece (the cushions) takes the part's colour
					tags = tags + 1
				end
			end
		end
	end
	return tags
end

HomeBuilder._Mesh = Mesh

local function placeStation(rec, def, level)
	local accent = (typeof(rec.Spot.Accent) == "Color3") and rec.Spot.Accent or nil
	local tpl = stationTemplate(def, level, accent, (def.Kind == "Garden") and Garden.openOf(rec) or nil)
	local slotCF = rec.CF * def.Slot.CFrame
	local m = cloneAt(tpl, slotCF)
	m.Name = "Station_" .. def.Id
	m:SetAttribute("StationId", def.Id)
	m:SetAttribute("Level", level)
	m:SetAttribute("Kind", def.Kind)
	m:SetAttribute("BuiltAt", serverNow())
	for name, p in pairs(tpl.Points) do
		m:SetAttribute(name, (slotCF * CFrame.new(p)).Position)
	end
	for name, v in pairs(tpl.Info) do
		m:SetAttribute(name, v)
	end
	applyOwnerAttr(rec, m)
	Mesh.station(m, def, level, tpl, slotCF) -- Phase 6: the Blender mesh (no-op without uploaded ids)
	return m
end

-- after a station model is placed: the per-plot state that lives on it (garden prompts, training mats)
local function afterPlace(rec, def)
	if def.Kind == "Garden" then
		Garden.applyPrompts(rec)
	elseif def.Kind == "Training" then
		Garden.applyTraining(rec)
	end
end

function HomeBuilder.SetStation(spotInfo, stationId, level)
	local rec = recordOf(spotInfo)
	if not rec then
		HomeBuilder.PreparePlot(spotInfo)
		rec = recordOf(spotInfo)
	end
	local def = stationDef(stationId)
	if not rec or not def then
		return nil
	end
	level = tonumber(level)
	if not level or level ~= level then
		return nil
	end
	level = floor(level)
	level = max(0, min(level, def.MaxLevel or level))
	local current = rec.Stations[stationId]
	if level == 0 then
		if current then
			current:Destroy()
		end
		rec.Stations[stationId] = nil
		rec.Levels[stationId] = nil
		if def.Kind == "House" then
			refreshLot(rec)
		end
		if HomeBuilder.StationBuilt then
			HomeBuilder.StationBuilt:Fire(rec.Spot, stationId, nil)
		end
		return nil
	end
	if current and current.Parent and rec.Levels[stationId] == level then
		return current
	end
	local ok, model = pcall(placeStation, rec, def, level)
	if not ok or not model then
		warn("[HomeBuilder] SetStation " .. tostring(stationId) .. " " .. tostring(level) .. " failed: " .. tostring(model))
		return nil
	end
	if current then
		current:Destroy()
	end
	removeGhost(rec, stationId)
	model.Parent = rec.Home
	rec.Stations[stationId] = model
	rec.Levels[stationId] = level
	afterPlace(rec, def)
	if def.Kind == "House" then
		refreshLot(rec)
	end
	if HomeBuilder.StationBuilt then
		HomeBuilder.StationBuilt:Fire(rec.Spot, stationId, model)
	end
	return model
end

-- every station of a Home table (others removed): a returning player's saved home on a fresh plot
function HomeBuilder.BuildHome(spotInfo, home)
	local rec = recordOf(spotInfo)
	if not rec then
		HomeBuilder.PreparePlot(spotInfo)
		rec = recordOf(spotInfo)
	end
	local cat = catalog()
	if not rec or not cat then
		return false
	end
	local stations = type(home) == "table" and type(home.Stations) == "table" and home.Stations or {}
	for _, def in ipairs(cat.Stations or {}) do
		HomeBuilder.SetStation(rec.Spot, def.Id, tonumber(stations[def.Id]) or 0)
	end
	return true
end

----------------------------------------------------------------------
-- Pads
----------------------------------------------------------------------
local function padSlot(id)
	local cat = catalog()
	local def = cat and cat.Get(id)
	if type(def) == "table" and type(def.Slot) == "table" and typeof(def.Slot.Pad) == "CFrame" then
		return def.Slot.Pad, def
	end
	return nil, def
end

-- "x1.25" (two decimals at most, no trailing zeros)
local function multText(m)
	local text = string.format("%.2f", m):gsub("0+$", ""):gsub("%.$", "")
	return "x" .. text
end

local function priceText(pad)
	local price = tonumber(pad.Price) or 0
	if pad.Prestige or pad.StationId == "Prestige" then
		-- what the reset buys: every star multiplies the income (the Home window says the same, per star)
		local cat = catalog()
		local m = cat and type(cat.Prestige) == "table" and tonumber(cat.Prestige.IncomeMultiplier) or nil
		if m and m == m and m > 1 and m < 100 then
			return "Reset: " .. multText(m) .. " income"
		end
		return "Start over: +1 " .. GLYPH.Star
	end
	if price <= 0 then
		return "FREE"
	end
	return formatCash(price)
end

local function padSignature(pad, uid)
	return table.concat({
		tostring(pad.NextLevel), tostring(pad.Price), tostring(pad.Locked or ""), tostring(pad.Title or pad.Name), tostring(pad.LevelText), tostring(uid), padState(pad),
	}, "|")
end

-- the floating sign (pixel tag): icon + name, then "Lv a -> b" + price, or the lock reason
local function buildPadSign(anchor, pad, state)
	local edge = PAD_COLORS[state] or C.TextGold
	local gui = newTag(anchor, "PadSign", 360, 130, PAD_SIGN_RANGE)
	gui.StudsOffsetWorldSpace = Vector3.new(0, PAD_SIGN_LIFT, 0)
	local plate = tagPlate(gui, edge)
	local row1 = plainFrame(plate, "NameRow", { AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 1 })
	listLayout(row1, Enum.FillDirection.Horizontal, 6)
	tagText(row1, "Icon", tostring(pad.Icon or GLYPH.Cloud), "Title", TAG_NAME, C.Text, 1)
	tagText(row1, "NameLabel", tostring(pad.Title or pad.Name or pad.StationId), "Title", TAG_NAME, C.Text, 2)
	local row2 = plainFrame(plate, "InfoRow", { AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 2 })
	listLayout(row2, Enum.FillDirection.Horizontal, 10)
	if state == "Locked" then
		tagText(row2, "LockLabel", GLYPH.Lock .. " " .. tostring(pad.Locked), "Body", TAG_INFO, C.TextLock, 1)
	else
		tagText(row2, "LevelLabel", tostring(pad.LevelText or ""), "Body", TAG_INFO, C.TextGold, 1)
		tagText(row2, "PriceLabel", priceText(pad), "Display", TAG_PRICE, (state == "Prestige") and rgb(226, 196, 255) or C.TextGreen, 2)
	end
	return gui
end

local function ghostFor(rec, id, def)
	if rec.Ghosts[id] or rec.Stations[id] or not def then
		return
	end
	-- def.Ghost = "Pad": no hologram, the locked pad and its sign say it all (the Fusion Machine: a silhouette of its
	-- glass pods / chamber read as a broken model, bug batch 2 #10)
	if def.Ghost == "Pad" then
		return
	end
	local ok, tpl = pcall(stationTemplate, def, 1, nil)
	if not ok or type(tpl) ~= "table" then
		return
	end
	local m = cloneAt(tpl, rec.CF * def.Slot.CFrame)
	m.Name = "Ghost_" .. id
	-- a silhouette needs only the biggest blocks: keep GHOST_PARTS of them
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[#parts + 1] = d
		end
	end
	table.sort(parts, function(a, b)
		return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z
	end)
	for k = GHOST_PARTS + 1, #parts do
		parts[k]:Destroy()
	end
	-- drawn as a soft blue hologram (the ForceField material shimmers on its own: no animation needed)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = C.Ghost
			d.Material = MAT.ForceField
			d.Transparency = 0.3
			d.Reflectance = 0
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("ProximityPrompt") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("SurfaceGui") then
			d:Destroy()
		end
	end
	m:SetAttribute("StationId", id)
	m.Parent = rec.Home
	rec.Ghosts[id] = m
end

local function updatePad(rec, pad)
	local id = pad.StationId
	local slotCF, def = padSlot(id)
	if not slotCF then
		return nil
	end
	local uid = ownerId(rec)
	local state = padState(pad)
	local sig = padSignature(pad, uid)
	local entry = rec.Pads[id]
	if entry and entry.Sig == sig and entry.Model.Parent then
		return entry
	end
	-- the pad parts only change with the state; the sign and the attributes with every change
	if not entry or entry.State ~= state or not entry.Model.Parent then
		if entry then
			entry.Model:Destroy()
		end
		local m = cloneAt(padTemplate(state), rec.CF * slotCF)
		m.Name = "Pad_" .. id
		m:SetAttribute("BuiltAt", serverNow())
		local base = m:FindFirstChild("Base")
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BuyPrompt"
		-- the Prestige pad buys nothing: a deliberate hold opens the Home window's prestige confirmation
		local prestigePad = id == "Prestige"
		prompt.ActionText = prestigePad and "Prestige" or "Buy"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = prestigePad and PRESTIGE_HOLD or 0.25
		prompt.MaxActivationDistance = PROMPT_RANGE
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("StationId", id)
		prompt.Parent = base or m
		entry = { Model = m, Prompt = prompt, Anchor = base, State = state }
		rec.Pads[id] = entry
		m.Parent = rec.PadFolder
	end
	local m = entry.Model
	if entry.Sign then
		entry.Sign:Destroy()
	end
	entry.Sign = buildPadSign(entry.Anchor, pad, state)
	local locked = (pad.Locked ~= nil and pad.Locked ~= "") and tostring(pad.Locked) or ""
	m:SetAttribute("StationId", id)
	m:SetAttribute("OwnerUserId", uid)
	m:SetAttribute("NextLevel", tonumber(pad.NextLevel) or 1)
	m:SetAttribute("Level", tonumber(pad.Level) or 0)
	m:SetAttribute("Price", tonumber(pad.Price) or 0)
	m:SetAttribute("Locked", locked)
	m:SetAttribute("Title", tostring(pad.Title or pad.Name or id))
	m:SetAttribute("LevelText", tostring(pad.LevelText or ""))
	m:SetAttribute("Kind", tostring(pad.Kind or (def and def.Kind) or ""))
	entry.Prompt:SetAttribute("OwnerUserId", uid)
	entry.Prompt.ObjectText = tostring(pad.Title or pad.Name or id) .. ((locked == "") and ("  " .. priceText(pad)) or "")
	entry.Prompt.Enabled = locked == "" and uid ~= 0
	entry.Sig = sig
	-- a ghost of the station while it unlocks only later ("Unlocks at Prestige 1", "Coming soon")
	if locked ~= "" and (locked:find("Prestige", 1, true) or locked:find("Coming soon", 1, true)) and (tonumber(pad.Level) or 0) == 0 then
		ghostFor(rec, id, stationDef(id))
	else
		removeGhost(rec, id)
	end
	return entry
end

function HomeBuilder.SetPads(spotInfo, pads)
	local rec = recordOf(spotInfo)
	if not rec then
		HomeBuilder.PreparePlot(spotInfo)
		rec = recordOf(spotInfo)
	end
	if not rec then
		return false
	end
	local keep = {}
	if type(pads) == "table" then
		for _, pad in ipairs(pads) do
			if type(pad) == "table" and type(pad.StationId) == "string" and not keep[pad.StationId] then
				local ok, entry = pcall(updatePad, rec, pad)
				if ok and entry then
					keep[pad.StationId] = true
				elseif not ok then
					warn("[HomeBuilder] pad " .. pad.StationId .. " failed: " .. tostring(entry))
				end
			end
		end
	end
	for id, entry in pairs(rec.Pads) do
		if not keep[id] then
			entry.Model:Destroy()
			rec.Pads[id] = nil
			removeGhost(rec, id)
		end
	end
	return true
end

----------------------------------------------------------------------
-- Owner, collector, clear
----------------------------------------------------------------------
function HomeBuilder.SetOwner(spotInfo, player)
	local rec = recordOf(spotInfo)
	if not rec then
		HomeBuilder.PreparePlot(spotInfo)
		rec = recordOf(spotInfo)
	end
	if not rec then
		return false
	end
	local uid, name = 0, ""
	if typeof(player) == "Instance" and player:IsA("Player") then
		uid = player.UserId
		name = player.DisplayName ~= "" and player.DisplayName or player.Name
	end
	rec.OwnerUserId = uid
	rec.Home:SetAttribute("OwnerUserId", uid)
	rec.Home:SetAttribute("OwnerName", name)
	setClaimVisible(rec, uid == 0)
	setPaths(rec, uid ~= 0)
	refreshLot(rec)
	for _, model in pairs(rec.Stations) do
		applyOwnerAttr(rec, model)
	end
	Garden.applyPrompts(rec)
	for _, entry in pairs(rec.Pads) do
		entry.Model:SetAttribute("OwnerUserId", uid)
		entry.Prompt:SetAttribute("OwnerUserId", uid)
		local locked = entry.Model:GetAttribute("Locked")
		entry.Prompt.Enabled = uid ~= 0 and (locked == nil or locked == "")
		entry.Sig = nil
	end
	return true
end

-- SetGarden(spotInfo, valid, open): the Garden's open place count (3 + Prestige stars, at most 12: TycoonService's
-- GardenSlots, NOT the Garden level) and the placed keys valid = { [slot] = key }. A new open count rebuilds the
-- Garden model (template Garden:<level>:<open>); the GardenSpotPrompts follow the empty open places. Kept per plot,
-- so a Garden built later (or rebuilt with a new level) shows the same places.
function HomeBuilder.SetGarden(spotInfo, valid, open)
	local rec = recordOf(spotInfo)
	if not rec then
		HomeBuilder.PreparePlot(spotInfo)
		rec = recordOf(spotInfo)
	end
	if not rec then
		return false
	end
	local cat = catalog()
	local def = stationDef("Garden")
	local places = def and #Garden.places(def) or ((cat and cat.Prestige and tonumber(cat.Prestige.GardenSlotsMax)) or 12)
	local slots = {}
	if type(valid) == "table" then
		for k, v in pairs(valid) do
			local slot = tonumber(k)
			if slot and slot == slot and slot >= 1 and slot <= places and slot == floor(slot) and type(v) == "string" and v ~= "" then
				slots[slot] = v
			end
		end
	end
	local before = Garden.openOf(rec)
	open = Garden.clampOpen((open == nil) and before or open, places)
	rec.Garden = { Open = open, Valid = slots }
	local model = rec.Stations.Garden
	if def and model and model.Parent and open ~= before and (rec.Levels.Garden or 0) > 0 then
		-- the places changed (a Prestige): rebuild the Garden with the new open count
		local ok, fresh = pcall(placeStation, rec, def, rec.Levels.Garden)
		if ok and fresh then
			model:Destroy()
			fresh.Parent = rec.Home
			rec.Stations.Garden = fresh
			if HomeBuilder.StationBuilt then
				HomeBuilder.StationBuilt:Fire(rec.Spot, "Garden", fresh)
			end
		else
			warn("[HomeBuilder] SetGarden rebuild failed: " .. tostring(fresh))
		end
	end
	Garden.applyPrompts(rec)
	if rec.Stations.Garden and rec.Stations.Garden:GetAttribute("Open") ~= open then
		rec.Stations.Garden:SetAttribute("Open", open)
	end
	return true
end

-- SetTraining(spotInfo, pets): pets = { [mat] = { Key, Stat, Ends } } (PetCareService; HomeFx reads the plot's
-- TrainingPets attribute). Only attributes on the mats' Spot<i> attachments: Busy, Key, Stat, Ends.
function HomeBuilder.SetTraining(spotInfo, pets)
	local rec = recordOf(spotInfo)
	if not rec then
		return false
	end
	local map = {}
	if type(pets) == "table" then
		for k, v in pairs(pets) do
			local mat = tonumber(k)
			if mat and mat == mat and mat >= 1 and mat <= 5 and mat == floor(mat) and type(v) == "table" then
				local ends = tonumber(v.Ends) or 0
				if ends ~= ends or ends == huge or ends == -huge then
					ends = 0
				end
				map[mat] = { Key = tostring(v.Key or ""), Stat = tostring(v.Stat or ""), Ends = floor(ends) }
			end
		end
	end
	rec.Training = map
	Garden.applyTraining(rec)
	return true
end

function HomeBuilder.ClearPlot(spotInfo)
	local rec = recordOf(spotInfo)
	if not rec then
		return false
	end
	for id, model in pairs(rec.Stations) do
		model:Destroy()
		rec.Stations[id] = nil
	end
	rec.Levels = {}
	for id, entry in pairs(rec.Pads) do
		entry.Model:Destroy()
		rec.Pads[id] = nil
	end
	for id in pairs(rec.Ghosts) do
		removeGhost(rec, id)
	end
	rec.Garden = nil
	rec.Training = nil
	-- anything else a caller parented under Home (but keep the Pads folder)
	for _, c in ipairs(rec.Home:GetChildren()) do
		if c ~= rec.PadFolder and c.Name ~= "Paths" and c.Name ~= "HouseLot" then
			c:Destroy()
		end
	end
	for _, c in ipairs(rec.PadFolder:GetChildren()) do
		c:Destroy()
	end
	if ownerId(rec) == 0 then
		setPaths(rec, false)
	end
	refreshLot(rec)
	return true
end

----------------------------------------------------------------------
-- Extras
----------------------------------------------------------------------
function HomeBuilder.GetHomeFolder(spotInfo)
	local rec = recordOf(spotInfo)
	return rec and rec.Home or nil
end

function HomeBuilder.GetStation(spotInfo, id)
	local rec = recordOf(spotInfo)
	return rec and rec.Stations[id] or nil
end

function HomeBuilder.GetPad(spotInfo, id)
	local rec = recordOf(spotInfo)
	local entry = rec and rec.Pads[id]
	return entry and entry.Model or nil
end

function HomeBuilder.GetClaimPrompt(spotInfo)
	local rec = recordOf(spotInfo)
	return rec and rec.ClaimPrompt or nil
end

function HomeBuilder.PartCount(spotInfo)
	local rec = recordOf(spotInfo)
	return rec and countParts(rec.Home) or 0
end

-- a fresh copy of a station's model at the origin (front -Z), for renders and tests; open = the Garden's open place
-- count (default: Prestige.GardenSlotsBase)
function HomeBuilder.BuildStationModel(id, level, accent, open)
	local def = stationDef(id)
	if not def then
		return nil
	end
	level = max(1, min(floor(tonumber(level) or 1), def.MaxLevel or 1))
	local tpl = stationTemplate(def, level, accent, open)
	local m = cloneAt(tpl, CFrame.new())
	m.Name = "Station_" .. id
	m:SetAttribute("StationId", id)
	m:SetAttribute("Level", level)
	m:SetAttribute("Kind", def.Kind)
	for name, v in pairs(tpl.Info) do
		m:SetAttribute(name, v)
	end
	Mesh.station(m, def, level, tpl, CFrame.new()) -- Phase 6: the Blender mesh (no-op without uploaded ids)
	return m
end

-- local fx points of a station level (FruitPoint, MagnetCenter, ChuteMouth, Tray, HopperTop, SwirlCenter ...)
function HomeBuilder.Points(id, level)
	local def = stationDef(id)
	if not def then
		return nil
	end
	local tpl = stationTemplate(def, max(1, floor(tonumber(level) or 1)), nil)
	return tpl.Points, tpl.Info
end

HomeBuilder.Art = Art

function HomeBuilder.Init(info)
	if type(info) == "table" then
		lobbyInfo = info
	end
	initialized = true
	if type(lobbyInfo) == "table" and type(lobbyInfo.Spots) == "table" then
		for _, spot in pairs(lobbyInfo.Spots) do
			local ok, err = pcall(HomeBuilder.PreparePlot, spot)
			if not ok then
				warn("[HomeBuilder] PreparePlot failed: " .. tostring(err))
			end
		end
	end
	return true
end

function HomeBuilder.IsReady()
	return initialized
end

return HomeBuilder
