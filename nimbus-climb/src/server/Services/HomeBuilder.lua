-- HomeBuilder (Phase 2 + Phase 4, homeworld): builds the tycoon home of a lobby plot in the DETAILED VOXEL style
-- (ARCHITECTURE_V3.md "Phase 2 build contract", "Phase 4 build contract" 3.1 / 3.3 / 3.7 / 5.2 / 5.4 / 6 + ART
-- DIRECTION), sculpted with shared/Voxel.lua. A server module: TycoonService requires it and decides WHAT is built;
-- HomeBuilder only draws.
--
-- Contract API:
--   HomeBuilder.Init(lobbyInfo)                 remembers the lobby and prepares every plot in lobbyInfo.Spots
--   HomeBuilder.PreparePlot(spotInfo)           the plot's `Home` folder (tag NC_Home) and the gate's "Claim Home"
--                                               ProximityPrompt `ClaimPrompt` (attribute SpotIndex; E, ObjectText
--                                               "Free home") plus a crafted "FREE HOME" signpost on the verge.
--                                               Idempotent; returns the Home folder.
--   HomeBuilder.SetOwner(spotInfo, player|nil)  attributes OwnerUserId / OwnerName on the Home folder, every pad and
--                                               owner-only prompt; the claim prompt + signpost only while free; the
--                                               stone paths of the yard while owned (and the staked-out house lot
--                                               while there is no House yet)
--   HomeBuilder.SetStation(spotInfo, id, level) builds or replaces the station model `Station_<Id>` (attributes
--                                               StationId, Level, BuiltAt = workspace:GetServerTimeNow(), Kind + the
--                                               art's points / info) under the Home folder at PlotCFrame * Slot.CFrame;
--                                               level 0 removes it; the same level again is a no-op. Returns the model.
--                                               The art is chosen by the station's Kind (TycoonCatalog.Kinds).
--   HomeBuilder.SetPads(spotInfo, pads)         the buy pads `Pad_<StationId>` (Home/Pads) for TycoonCatalog.AvailablePads
--                                               entries: a glowing voxel pad + a pixel sign (icon, name, "Lv a -> b",
--                                               price or the lock reason) + ProximityPrompt `BuyPrompt` (ActionText "Buy",
--                                               HoldDuration 0.25, attributes StationId, OwnerUserId; disabled while
--                                               locked; the Prestige pad's says "Prestige" and needs a 1.5 s hold: it
--                                               opens the prestige confirmation, see TycoonService).
--                                               Pads missing from the list are removed, unchanged pads are kept
--                                               (only their texts / attributes update). Locked "Unlocks at Prestige" /
--                                               "Coming soon" stations show a blue hologram silhouette (`Ghost_<Id>`).
--   HomeBuilder.SetGarden(spotInfo, valid, open)  (Phase 4, TycoonService) the Garden's open places (3 + Prestige
--                                               stars, <= 12; NOT the Garden level) and the placed keys valid =
--                                               { [slot] = key }: a new open count rebuilds the Garden (template
--                                               Garden:<level>:<open>); the GardenSpotPrompt of every OPEN EMPTY place
--                                               is enabled, the others disabled. Remembered per plot.
--   HomeBuilder.SetTraining(spotInfo, pets)     (Phase 4, PetCareService, optional) pets = { [mat] = { Key, Stat, Ends } }:
--                                               attributes Busy / Key / Stat / Ends on the Training Place's Spot<i>
--                                               (HomeFx reads the plot's TrainingPets attribute)
--   HomeBuilder.ClearPlot(spotInfo)             removes every station, pad and ghost (the paths too when nobody owns
--                                               the plot; while owned the paths and the house lot stay); the claim
--                                               prompt stays; the remembered garden / training state is dropped
-- Extras (nothing depends on them): GetHomeFolder(spotInfo), GetStation(spotInfo, id), GetPad(spotInfo, id),
--   GetClaimPrompt(spotInfo), BuildHome(spotInfo, home) (every station of home.Stations, others removed),
--   BuildStationModel(id, level, accent, open) -> a fresh clone at the origin (renders / tests; open = the Garden's
--   open place count), PartCount(spotInfo), StationBuilt = Util.Signal Fire(spotInfo, stationId, model|nil),
--   Points(id, level) (local fx points). Phase 4 removed SetCollector, the Collector screen / CollectPad / conveyor.
--
-- Workspace layout (Spot_NN = spotInfo.Folder):
--   Spot_NN/ClaimGate          ClaimSign (a two-part signpost, while free); ClaimAnchor (invisible, only when the lobby
--                              has no gate part) -- the ClaimPrompt rides the Attachment ClaimPoint in the gate opening,
--                              on the lobby's GateBeam when there is one (free plots add 2 parts to the lobby)
--   Spot_NN/Home  (Folder, tag NC_Home; attributes SpotIndex, PlotCFrame, OwnerUserId, OwnerName)
--     Paths                    the yard's stone paths (TycoonCatalog.Layout.Paths), one merged voxel layer
--     HouseLot                 stakes, a string, planks and bricks where the house will stand (owned, no House yet)
--     Station_<Id>             the station models (section 6 budgets: plant 45, Magnet 55, Garden 85, Food Machine 55,
--                              Training Place 90, House 150, Fusion 90, fence 60, others 80):
--                              * Plant (Press1..4: Berry Bush, Carrot Patch, Cloud Melons, Starfruit Tree): a planter
--                                that grows with the level; attributes FruitPoint (world point), Fruit, FruitColor
--                              * Magnet (Collector): the Coin Magnet totem; `MagnetHead` (a Model HomeFx spins) and the
--                                MagnetCenter attribute
--                              * Garden: 12 places (Slot.Spots, 3 x 4) with sand walks (parts named after
--                                Slot.Walkable), flower beds + cushions on the open places, seedling beds with a
--                                "Prestige to open" placard (ClosedSign / ClosedGui) on the others; Attachments
--                                Spot<i> (attributes Slot, Open) on every cushion; on every open place an Attachment
--                                PromptPoint<i> with the owner-only ProximityPrompt `GardenSpotPrompt` ("Put a pet
--                                here", E, attributes Slot / OwnerUserId / StationId, MaxActivationDistance 3,
--                                RequiresLineOfSight false) at the cushion's far edge; attribute Open on the model.
--                                Bowls, fruit, coins and heaps are CLIENT parts (HomeFx).
--                              * FoodMachine (Kitchen): the glass `Hopper` part (PetCareService's FeedPrompt sits on
--                                it), attributes ChuteMouth / Tray / HopperTop
--                              * Training (Gym): mats with Attachments Spot<i> (attribute Slot) on the deck
--                              * Fusion Machine: Swirl (a Model HomeFx spins) and `FusionPrompt` ("Fuse", owner only);
--                                Arena Gate: `ArenaGatePrompt` ("Go to Arena", owner only, attributes StationId /
--                                Teleport = "Arena": ArenaBuilder teleports the owner to the Battle Arena)
--     Pads/Pad_<StationId>     buy pads, 4 parts each (attributes StationId, OwnerUserId, NextLevel, Level, Price,
--                              Locked ("" when unlocked), Title, LevelText, Kind, BuiltAt): a stone Base (walkable; it
--                              carries the BuyPrompt and the BillboardGui `PadSign`), the state's neon Glow plate and a
--                              two-part neon Emblem ("+" build, arrow upgrade, padlock, star prestige)
--     Ghost_<Id>               hologram silhouette (the 12 biggest blocks, ForceField) of a station that unlocks later
--
-- Art: every station grows visibly with its level (a level-1 Berry Bush is a small bush in a wooden planter, level 10
-- a big berry-laden bush in a gold one; the House is a Cottage -> Villa -> Manor -> Sky Castle; the Fusion Machine has
-- two input pods, a swirling cloud chamber and an output pod). Each (station, level) is sculpted ONCE per server,
-- merged with the greedy voxel merge and kept as a template that is :Clone()d onto every plot. A fully built plot stays
-- <= 950 parts (pads included; tools/smoke_p2_homeworld.lua walks a whole greedy progression and checks it). No
-- server-side animation and no Instance per coin (Replication rule): HomeFx (client) pops stations in, spins the magnet
-- and the fusion swirl, draws the coins, bowls, fruit and pets, and hides other players' pads and prompts. The art is
-- sculpted on a 0.5 stud voxel grid (cell edges round half away from the model's axis, so the models stay symmetric).
-- Texts follow the World text rule (pixel-sized billboard tags, surface signs at 50 px per stud with >= 0.6 stud
-- letters). The only fonts are Theme roles. Plain Lua 5.1-compatible syntax only.

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

local FLOWERS = { rgb(246, 150, 188), rgb(250, 214, 92), rgb(244, 244, 248), rgb(172, 142, 232), rgb(236, 104, 108), rgb(112, 172, 240) }

-- Base palette shared by every sculpt (station palettes add their own keys; Voxel derives _Light / _Dark).
local P = {
	Stone = C.Stone,
	StoneLight = C.StoneLight,
	StoneDark = C.StoneDark,
	StoneEdge = C.StoneEdge,
	Marble = C.Marble,
	Iron = C.Iron,
	IronLight = C.IronLight,
	IronDark = C.IronDark,
	Gold = { Color = C.Gold, Reflectance = 0.05 },
	GoldDark = C.GoldDark,
	Copper = C.Copper,
	Plank = C.Plank,
	PlankLight = C.PlankLight,
	PlankDark = C.PlankDark,
	Bark = C.Bark,
	Cloud = C.Cloud,
	CloudShade = C.CloudShade,
	Mist = C.Mist,
	Glass = { Color = C.Glass, Material = MAT.Glass, Transparency = 0.45 },
	Window = C.Window,
	WarmWindow = { Color = C.WarmWindow, Material = MAT.Neon },
	Lamp = { Color = C.Lamp, Material = MAT.Neon },
	Cash = C.Cash,
	CashGlow = { Color = C.CashGlow, Material = MAT.Neon },
	Leaf = C.Leaf,
	LeafDark = C.LeafDark,
	Grass = C.Grass,
	Soil = C.Soil,
	Hedge = C.Hedge,
	Water = { Color = C.Water, Material = MAT.Glass, Transparency = 0.3 },
	Red = C.Red,
	Rose = C.Rose,
	Cream = C.Cream,
	Navy = C.Navy,
	Crystal = { Color = C.Crystal, Material = MAT.Neon },
	Dark = rgb(40, 44, 64),
	White = rgb(246, 246, 250),
}
for i, color in ipairs(FLOWERS) do
	P["Flower" .. i] = color
end

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local floor, max, min, abs, huge = math.floor, math.max, math.min, math.abs, math.huge

local function snap(v, step)
	step = step or 0.5
	return floor(v / step + 0.5) * step
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function mergeTables(a, b)
	local out = {}
	for k, v in pairs(a) do
		out[k] = v
	end
	if b then
		for k, v in pairs(b) do
			out[k] = v
		end
	end
	return out
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

-- One anchored block. opts: Collide, Material, Transparency, Shadow, Reflectance, Touch, Query.
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
-- Sculpt kit (studs in, voxels out). Cell i covers [i * V, (i + 1) * V) on every axis, so a model built with
-- SK.Build sits exactly on y = 0 and whole-stud widths centred on 0 stay symmetric.
----------------------------------------------------------------------
local SK = {}

function SK.New(V)
	return { G = Voxel.NewGrid(16), V = V or 0.5 }
end

-- grid lines are rounded half AWAY from zero, so a box from -a to +a always stays symmetric about the model's
-- axis (adjacent boxes still tile: the rounding only depends on the coordinate)
local function gridLine(v)
	if v >= 0 then
		return floor(v + 0.5)
	end
	return -floor(-v + 0.5)
end

local function cells(V, a, b)
	if b < a then
		a, b = b, a
	end
	return gridLine(a / V), gridLine(b / V) - 1
end

-- fills [x0, x1) x [y0, y1) x [z0, z1); key nil clears; keep = only empty cells
function SK.Box(s, x0, x1, y0, y1, z0, z1, key, keep)
	local V, G = s.V, s.G
	local a0, a1 = cells(V, x0, x1)
	local b0, b1 = cells(V, y0, y1)
	local c0, c1 = cells(V, z0, z1)
	for i = a0, a1 do
		for j = b0, b1 do
			for k = c0, c1 do
				if not keep or Voxel.Get(G, i, j, k) == nil then
					Voxel.Set(G, i, j, k, key)
				end
			end
		end
	end
end

-- recolours the existing cells of a box (only = { key = true } limits it)
function SK.Paint(s, x0, x1, y0, y1, z0, z1, key, only)
	local V, G = s.V, s.G
	local a0, a1 = cells(V, x0, x1)
	local b0, b1 = cells(V, y0, y1)
	local c0, c1 = cells(V, z0, z1)
	for i = a0, a1 do
		for j = b0, b1 do
			for k = c0, c1 do
				local cur = Voxel.Get(G, i, j, k)
				if cur ~= nil and (not only or only[cur]) then
					Voxel.Set(G, i, j, k, key)
				end
			end
		end
	end
end

local function vp(s, x, y, z)
	local V = s.V
	return { x / V - 0.5, y / V - 0.5, z / V - 0.5 }
end

local function shape(s, sh, extra)
	if extra then
		for k, v in pairs(extra) do
			sh[k] = v
		end
	end
	Voxel.Shape(s.G, sh)
end

function SK.Ell(s, x, y, z, rx, ry, rz, key, extra)
	local V = s.V
	shape(s, { Kind = "Ellipsoid", Center = vp(s, x, y, z), Radius = { rx / V, ry / V, rz / V }, Key = key }, extra)
end

-- rounded box over [x0, x1) x [y0, y1) x [z0, z1), corner radius `round` (studs)
function SK.RBox(s, x0, x1, y0, y1, z0, z1, round, key, extra)
	local V = s.V
	shape(s, {
		Kind = "RoundBox",
		Center = vp(s, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Size = { (x1 - x0) / V, (y1 - y0) / V, (z1 - z0) / V },
		Round = (round or 1) / V,
		Key = key,
		Bias = 0,
	}, extra)
end

function SK.Cone(s, x, z, y0, y1, r0, r1, key, extra)
	local V = s.V
	shape(s, { Kind = "Cone", A = vp(s, x, y0, z), B = vp(s, x, y1, z), Radius = r0 / V, RadiusB = (r1 or 0) / V, Key = key }, extra)
end

function SK.Cap(s, a, b, r, rb, key, extra)
	local V = s.V
	shape(s, { Kind = "Capsule", A = vp(s, a[1], a[2], a[3]), B = vp(s, b[1], b[2], b[3]), Radius = r / V, RadiusB = (rb or r) / V, Key = key }, extra)
end

function SK.Curve(s, pts, r, rb, key, extra)
	local V = s.V
	local list = {}
	for i, p in ipairs(pts) do
		list[i] = vp(s, p[1], p[2], p[3])
	end
	shape(s, { Kind = "Curve", Points = list, Radius = r / V, RadiusB = (rb or r) / V, Smooth = true, Key = key }, extra)
end

function SK.Torus(s, x, y, z, R, r, key, extra)
	local V = s.V
	shape(s, { Kind = "Torus", Center = vp(s, x, y, z), Radius = R / V, Thickness = r / V, Key = key }, extra)
end

-- vertical cylinder over [y0, y1): cells whose centre lies within r of (x, z)
function SK.Cyl(s, x, z, r, y0, y1, key, keep, inner)
	local V, G = s.V, s.G
	local b0, b1 = cells(V, y0, y1)
	local cx, cz = x / V - 0.5, z / V - 0.5
	local rv = r / V + 0.25
	local r2 = rv * rv
	local in2 = inner and ((inner / V + 0.25) ^ 2) or -1
	local ri = math.ceil(rv) + 1
	for i = floor(cx) - ri, math.ceil(cx) + ri do
		for k = floor(cz) - ri, math.ceil(cz) + ri do
			local dx, dz = i - cx, k - cz
			local d2 = dx * dx + dz * dz
			if d2 <= r2 and d2 > in2 then
				for j = b0, b1 do
					if not keep or Voxel.Get(G, i, j, k) == nil then
						Voxel.Set(G, i, j, k, key)
					end
				end
			end
		end
	end
end

-- a disc standing upright, facing -Z (normal along Z): radius r, centre (x, y), thickness [z0, z1)
function SK.DiscZ(s, x, y, z0, z1, r, key, keep)
	local V, G = s.V, s.G
	local c0, c1 = cells(V, z0, z1)
	local cx, cy = x / V - 0.5, y / V - 0.5
	local rv = r / V + 0.25
	local ri = math.ceil(rv) + 1
	for i = floor(cx) - ri, math.ceil(cx) + ri do
		for j = floor(cy) - ri, math.ceil(cy) + ri do
			local dx, dy = i - cx, j - cy
			if dx * dx + dy * dy <= rv * rv then
				for k = c0, c1 do
					if not keep or Voxel.Get(G, i, j, k) == nil then
						Voxel.Set(G, i, j, k, key)
					end
				end
			end
		end
	end
end

-- same, facing +-X
function SK.DiscX(s, z, y, x0, x1, r, key, keep)
	local V, G = s.V, s.G
	local a0, a1 = cells(V, x0, x1)
	local cz, cy = z / V - 0.5, y / V - 0.5
	local rv = r / V + 0.25
	local ri = math.ceil(rv) + 1
	for k = floor(cz) - ri, math.ceil(cz) + ri do
		for j = floor(cy) - ri, math.ceil(cy) + ri do
			local dz, dy = k - cz, j - cy
			if dz * dz + dy * dy <= rv * rv then
				for i = a0, a1 do
					if not keep or Voxel.Get(G, i, j, k) == nil then
						Voxel.Set(G, i, j, k, key)
					end
				end
			end
		end
	end
end

-- stepped gable roof over [x0, x1) x [z0, z1) starting at yBase; ridge along X (axis "X") or Z. altKey: every
-- other row of tiles in a second colour (reads as tile rows, costs nothing: a row is one box either way)
function SK.Gable(s, x0, x1, z0, z1, yBase, step, key, axis, ridgeKey, altKey)
	local V = s.V
	step = step or V
	local layer = 0
	while true do
		local inset = layer * step
		local y = yBase + layer * V
		local k = (altKey and layer % 2 == 1) and altKey or key
		if axis == "Z" then
			if x1 - x0 - 2 * inset < V * 0.99 then
				break
			end
			if x1 - x0 - 2 * inset < 2 * step + V * 0.5 then
				k = ridgeKey or k
			end
			SK.Box(s, x0 + inset, x1 - inset, y, y + V, z0, z1, k)
		else
			if z1 - z0 - 2 * inset < V * 0.99 then
				break
			end
			if z1 - z0 - 2 * inset < 2 * step + V * 0.5 then
				k = ridgeKey or k
			end
			SK.Box(s, x0, x1, y, y + V, z0 + inset, z1 - inset, k)
		end
		layer = layer + 1
		if layer > 200 then
			break
		end
	end
	return yBase + layer * V
end

-- stepped hip roof (shrinks on every side); altKey as in Gable
function SK.Hip(s, x0, x1, z0, z1, yBase, step, key, topKey, altKey)
	local V = s.V
	step = step or V
	local layer = 0
	while true do
		local inset = layer * step
		if x1 - x0 - 2 * inset < V * 0.99 or z1 - z0 - 2 * inset < V * 0.99 then
			break
		end
		local y = yBase + layer * V
		local last = (x1 - x0 - 2 * inset < 2 * step + V * 0.5) or (z1 - z0 - 2 * inset < 2 * step + V * 0.5)
		local k = (altKey and layer % 2 == 1) and altKey or key
		SK.Box(s, x0 + inset, x1 - inset, y, y + V, z0 + inset, z1 - inset, last and (topKey or k) or k)
		layer = layer + 1
		if layer > 200 then
			break
		end
	end
	return yBase + layer * V
end

-- a cheap round prism: two crossing boxes (an octagon-ish plus); `r` and the cut snap to the grid
function SK.Oct(s, x, z, r, y0, y1, key, keep)
	local V = s.V
	r = max(V, snap(r, V))
	local c = max(V, snap(r * 0.6, V))
	SK.Box(s, x - r, x + r, y0, y1, z - c, z + c, key, keep)
	if c < r then
		SK.Box(s, x - c, x + c, y0, y1, z - r, z + r, key, keep)
	end
end

-- a stepped round spire: Oct layers shrinking from r0 to a point, `lh` studs per layer (alternating colours)
function SK.Spire(s, x, z, r0, y0, y1, key, altKey, lh)
	lh = lh or 1.0
	local n = max(1, floor((y1 - y0) / lh + 0.5))
	for i = 0, n - 1 do
		local r = r0 * (1 - i / n)
		local k = (altKey and i % 2 == 1) and altKey or key
		SK.Oct(s, x, z, max(s.V, r), y0 + i * lh, y0 + (i + 1) * lh, k)
	end
	return y0 + n * lh
end

function SK.Shade(s, opts)
	Voxel.Shade(s.G, opts or { Smooth = 1 })
end

-- parts of one sculpt; opts: Name, Collide (true / "big"), MaxParts, Keep, CFrame, Shadow
function SK.Build(s, pal, opts)
	opts = opts or {}
	local V = s.V
	if s.G.Count == 0 then
		local empty = Instance.new("Model")
		empty.Name = opts.Name or "Voxels"
		return empty
	end
	-- LOD may only fold shade variants back into their colour: distinct colours are never merged
	local keep = opts.Keep
	if not keep then
		keep = {}
		for _, v in pairs(s.G.Cells) do
			local base, variant = Voxel.BaseKey(v)
			if not variant then
				keep[base] = true
			end
		end
	end
	local model = Voxel.Build(s.G, {
		VoxelSize = V,
		Palette = pal or P,
		Name = opts.Name or "Voxels",
		CFrame = (opts.CFrame or CFrame.new()) * CFrame.new(V / 2, V / 2, V / 2),
		MaxParts = opts.MaxParts,
		Keep = keep,
		CastShadow = opts.Shadow,
	})
	local collide = opts.Collide
	if collide then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				local big = max(p.Size.X, p.Size.Y, p.Size.Z) >= 1.5 and p.Transparency < 0.5
				if collide == true or big then
					p.CanCollide = true
					p.CanQuery = true
				end
			end
		end
	end
	return model
end

local puffCloud -- defined with the art (stations share it)

-- moves every child of `from` into `to` (merging sculpts into one station model)
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

----------------------------------------------------------------------
-- Templates: every (station, level) is sculpted once per server and cloned onto the plots.
-- A template is { Model = Model at the origin (front = -Z, ground = y 0), Points = { name = local Vector3 },
-- Info = {...} }.
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

----------------------------------------------------------------------
-- ART: stations. Each Art.<Kind>(def, level) returns a template.
----------------------------------------------------------------------
local Art = {}

-- a puffy voxel cloud sitting on y0: a shaded underside, a big round middle, a bright crown and a side puff.
-- r = the middle puff's radius (studs). Cheap: about 6 boxes.
puffCloud = function(s, x, y0, z, r, seed)
	local V = s.V
	r = max(1.0, r)
	local h = max(V, snap(r * 0.6, V))
	SK.Oct(s, x, z, r - 0.25, y0, y0 + V, "CloudShade")
	SK.Oct(s, x, z, r + 0.25, y0 + V, y0 + V + h, "Cloud")
	SK.Box(s, x - snap(r * 0.5), x + snap(r * 0.5), y0 + V + h, y0 + V + h + h * 0.75, z - snap(r * 0.5), z + snap(r * 0.5), "CloudLight")
	local side = ((seed or 1) % 2 == 0) and 1 or -1
	local px = x + side * snap(r * 0.9)
	SK.Box(s, px - snap(r * 0.45), px + snap(r * 0.45), y0 + V, y0 + V + h * 0.75, z - snap(r * 0.45), z + snap(r * 0.45), "Cloud", true)
end

----------------------------------------------------------------------
-- Food plants (Phase 4: the four old Cloud Press slots, ids Press1..4 = Berry Bush, Carrot Patch, Cloud Melons,
-- Starfruit Tree). Front -Z faces the pad. Each grows in a raised planter (wood at 1-3, stone at 4-6, stone with gold
-- corner caps at 7-9, all gold at 10) and visibly GROWS with its level: taller, wider, more fruit. <= 45 parts.
-- HomeFx (client) reads the FruitPoint (world point) / Fruit / FruitColor attributes to fly fruit into the bowls.
----------------------------------------------------------------------
local Plant = {}

Plant.LOOK = {
	Press1 = { Fruit = "Berry", Color = rgb(226, 58, 94) },
	Press2 = { Fruit = "Carrot", Color = rgb(250, 140, 46) },
	Press3 = { Fruit = "Melon", Color = rgb(98, 178, 240) },
	Press4 = { Fruit = "Starfruit", Color = rgb(255, 212, 70) },
}
Plant.MAX_PARTS = 44 -- contract section 6: a plant <= 45 parts (the sparkle attachment adds none)
Plant.CARROTS = { 2, 3, 4, 4, 5, 6, 6, 7, 8, 9 } -- carrots in the patch per level
-- the patch's 3 x 3 cells in planting order (the last one, the middle, holds the giant carrot at level 10)
Plant.CELLS = { { -1, 0 }, { 1, 0 }, { 0, 1 }, { 0, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 }, { -1, -1 }, { 0, 0 } }

function Plant.palette(level)
	local base, rim
	if level >= 10 then
		base, rim = C.GoldDark, P.Gold
	elseif level >= 4 then
		base, rim = C.StoneDark, C.Stone
	else
		base, rim = C.PlankDark, C.PlankLight
	end
	return mergeTables(P, {
		RimBase = base,
		Rim = rim,
		Soil = rgb(112, 80, 60),
		Leaf = rgb(76, 164, 82),
		Berry = rgb(226, 58, 94),
		BerryBlue = rgb(104, 96, 218),
		Blossom = rgb(252, 246, 240),
		Carrot = rgb(250, 140, 46),
		CarrotDark = rgb(214, 104, 34),
		Greens = rgb(100, 190, 80),
		GreensDark = rgb(70, 150, 70),
		Melon = rgb(98, 178, 240),
		Stripe = rgb(248, 252, 255),
		Post = C.PlankDark,
		Vine = rgb(74, 150, 82),
		Curl = rgb(110, 186, 86),
		Canopy = rgb(104, 196, 116),
		Star = (level >= 8) and { Color = rgb(255, 222, 96), Material = MAT.Neon } or rgb(255, 210, 66),
		StarDark = rgb(232, 170, 52),
	})
end

-- the raised planter (half width h): a darker base layer, the rim on top and the soil inside
function Plant.planter(s, h, level)
	SK.Box(s, -h, h, 0, 0.5, -h, h, "RimBase")
	SK.Box(s, -h, h, 0.5, 1.0, -h, h, "Rim")
	SK.Box(s, -h + 0.5, h - 0.5, 0.5, 1.0, -h + 0.5, h - 0.5, "Soil")
	if level >= 7 and level <= 9 then
		-- gold caps on the two front corners (the back corners stay free for trellis posts)
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and -h or (h - 1.0)
			SK.Box(s, x0, x0 + 1.0, 1.0, 1.5, -h, -h + 1.0, "Gold")
		end
	end
end

-- n points spread over an ellipsoid (golden-angle spiral), elevations from lo to hi (radians); each point also
-- carries its outward direction in the ground plane ({ x, y, z, dx, dz })
function Plant.spread(n, cx, cy, cz, rx, ry, rz, lo, hi, seed)
	local out = {}
	for i = 1, n do
		local a = (i + (seed or 0)) * 2.39996
		local f = (n > 1) and ((i - 1) / (n - 1)) or 0.5
		local e = lo + (hi - lo) * f
		local ca, sa = math.cos(a), math.sin(a)
		out[i] = { cx + rx * math.cos(e) * ca, cy + ry * math.sin(e), cz + rz * math.cos(e) * sa, ca, sa }
	end
	return out
end

-- Berry Bush: a round, clumpy bush dotted with berries (red, some blue from 6) and white blossoms (3+)
function Plant.Berry(s, level, t)
	local h = (level >= 4) and 3.0 or 2.5
	Plant.planter(s, h, level)
	local rx = 1.5 + 1.25 * t
	local ry = 1.25 + 1.5 * t
	local cy = 1.0 + ry * 0.85
	local f = s.Foliage
	SK.Ell(f, 0, cy, 0, rx, ry, rx * 0.9, "Leaf")
	SK.Ell(f, -rx * 0.55, cy - ry * 0.3, rx * 0.25, rx * 0.6, ry * 0.6, rx * 0.6, "Leaf")
	SK.Ell(f, rx * 0.55, cy - ry * 0.35, -rx * 0.25, rx * 0.55, ry * 0.55, rx * 0.55, "Leaf")
	if level >= 4 then
		SK.Ell(f, rx * 0.15, cy + ry * 0.55, 0, rx * 0.5, ry * 0.45, rx * 0.5, "Leaf")
	end
	SK.Shade(f, { Only = { Leaf = true }, Smooth = 1, Seed = 5 })
	for i, p in ipairs(Plant.spread(3 + level, 0, cy, 0, rx + 0.15, ry + 0.15, rx * 0.9 + 0.15, -0.2, 1.05, 1)) do
		local bx, by, bz = snap(p[1]), snap(p[2]), snap(p[3])
		local key = (level >= 6 and i % 3 == 0) and "BerryBlue" or "Berry"
		SK.Box(s, bx - 0.5, bx + 0.5, by - 0.5, by + 0.5, bz - 0.5, bz + 0.5, key)
	end
	if level >= 3 then
		for _, p in ipairs(Plant.spread(floor(level / 3) + 1, 0, cy, 0, rx + 0.1, ry + 0.1, rx * 0.9 + 0.1, 0.35, 1.2, 7)) do
			local bx, by, bz = snap(p[1]), snap(p[2]), snap(p[3])
			SK.Box(s, bx, bx + 0.5, by, by + 0.5, bz, bz + 0.5, "Blossom")
		end
	end
	return cy + ry * 0.6, cy + ry
end

-- Carrot Patch: rows of fat orange carrots peeking out of the soil, each under a bushy green tuft (a stalk and a
-- wider crown), more carrots and bigger tufts with every level; a giant carrot in the middle at 10
function Plant.Carrot(s, level, t)
	local h = (level >= 4) and 3.0 or 2.5
	Plant.planter(s, h, level)
	local step = (h >= 3) and 2.0 or 1.5
	local lh = snap(0.75 + 0.15 * level)
	local top = 1.0
	for i = 1, Plant.CARROTS[level] or 9 do
		local c = Plant.CELLS[i]
		local x, z = c[1] * step, c[2] * step
		local giant = level >= 10 and i == 9
		local w = giant and 1.0 or 0.5
		local sh = giant and 2.5 or ((level >= 5) and 1.5 or 1.0)
		SK.Box(s, x - w, x + w, top, top + sh, z - w, z + w, "Carrot")
		if not giant then
			-- the carrot's darker ring where it leaves the soil
			SK.Box(s, x - w, x + w, top, top + 0.5, z - w, z + w, "CarrotDark")
		end
		local gy = top + sh
		local gh = giant and (lh + 1.5) or lh
		local key = (i % 2 == 0) and "GreensDark" or "Greens"
		-- the tuft: a short stalk and a crown twice as wide (turned every other carrot), the crown's middle a step taller
		local cw = giant and 1.5 or 1.0
		SK.Box(s, x - 0.5, x + 0.5, gy, gy + gh + 0.5, z - 0.5, z + 0.5, key)
		if i % 2 == 0 then
			SK.Box(s, x - cw, x + cw, gy + 0.5, gy + gh, z - 0.5, z + 0.5, key)
		else
			SK.Box(s, x - 0.5, x + 0.5, gy + 0.5, gy + gh, z - cw, z + cw, key)
		end
	end
	return top + 1.5, top + lh + 4.5
end

-- Cloud Melons: plump sky-blue melons with white cloud stripes on a green vine bed. The big melon swells with
-- every level; a second melon joins at 4, a third at 7; from 5 a wooden vine trellis rises behind them (taller at 8+)
function Plant.Melon(s, level, t)
	local h = (level >= 4) and 3.0 or 2.5
	Plant.planter(s, h, level)
	-- vine leaves on the soil corners (the back ones sit under the trellis)
	for _, c in ipairs({ { -1, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 } }) do
		local x0 = (c[1] < 0) and (-h + 0.5) or (h - 2.0)
		local z0 = (c[2] < 0) and (-h + 0.5) or (h - 2.0)
		SK.Box(s, x0, x0 + 1.5, 1.0, 1.5, z0, z0 + 1.5, "Vine")
	end
	local topY = 1.0
	if level >= 5 then
		-- the trellis: two posts at the back corners, a top bar and vine leaves climbing it
		local th = (level >= 8) and 5.5 or 4.5
		local zb = h - 1.0
		SK.Box(s, -h + 0.5, -h + 1.0, 1.0, th, zb, zb + 0.5, "Post")
		SK.Box(s, h - 1.0, h - 0.5, 1.0, th, zb, zb + 0.5, "Post")
		SK.Box(s, -h + 0.5, h - 0.5, th, th + 0.5, zb, zb + 0.5, "Post")
		SK.Box(s, -h + 1.0, -0.5, th - 1.0, th, zb - 0.5, zb + 0.5, "Vine")
		SK.Box(s, 0.5, h - 1.0, th - 1.5, th - 0.5, zb - 0.5, zb + 0.5, "Curl")
		if level >= 10 then
			-- a little melon hanging from the trellis
			SK.Box(s, -2.0, -1.0, th - 2.5, th - 1.0, zb - 0.5, zb + 0.5, "Melon")
		end
		topY = th + 0.5
	end
	local r = 1.1 + 0.1 * (level - 1)
	local list = { { 0, -0.25, r } }
	if level >= 4 then
		list[1] = { 0.5, 0, r }
		list[2] = { -1.5, -1.5, 0.75 }
	end
	if level >= 7 then
		list[3] = { 1.5, -1.75, 0.65 }
	end
	local melonTop = 1.0
	for i, m in ipairs(list) do
		local mr = m[3]
		local ry = mr * 0.85
		local cy = 1.0 + ry * 0.8
		SK.Ell(s, m[1], cy, m[2], mr, ry, mr, "Melon")
		local cx, cz = snap(m[1]), snap(m[2])
		if i == 1 then
			-- two white cloud stripes over the big melon (only on its own voxels) and a curly stem with a leaf
			local a, b = snap(cx - mr * 0.45), snap(cx + mr * 0.45)
			SK.Paint(s, a, a + 0.5, cy - ry * 0.3, cy + ry + 0.5, cz - mr - 0.5, cz + mr + 0.5, "Stripe", { Melon = true })
			SK.Paint(s, b - 0.5, b, cy - ry * 0.3, cy + ry + 0.5, cz - mr - 0.5, cz + mr + 0.5, "Stripe", { Melon = true })
			SK.Box(s, cx - 0.5, cx, cy + ry - 0.25, cy + ry + 0.5, cz - 0.5, cz, "Curl")
			SK.Box(s, cx, cx + 1.0, cy + ry, cy + ry + 0.5, cz - 0.5, cz, "Vine")
			melonTop = cy + ry
		end
	end
	return melonTop * 0.8, max(topY, melonTop + 0.5)
end

-- Starfruit Tree: a sapling at 1 that grows into a big round tree hung with golden starfruit (glowing from 8). The
-- canopy is sculpted on a coarser grid (Foliage, 1 stud) so the tree stays inside the plant budget.
function Plant.Star(s, level, t)
	local h = (level >= 4) and 3.0 or 2.5
	Plant.planter(s, h, level)
	local tw = (level >= 6) and 1.0 or 0.5
	local th = snap(1.5 + 0.5 * level)
	local y0 = 1.0
	SK.Box(s, -tw, tw, y0, y0 + th, -tw, tw, "Bark")
	if level >= 4 then
		-- root flare
		SK.Box(s, -tw - 0.5, tw + 0.5, y0, y0 + 0.5, -tw - 0.5, tw + 0.5, "Bark")
	end
	local cr = min(3.0, 1.25 + 0.2 * level)
	local cy = y0 + th + cr * 0.45
	if level >= 5 then
		-- two stepped branches reaching into the side crowns
		local by = y0 + snap(th * 0.6)
		SK.Box(s, -tw - 1.0, -tw, by, by + 0.5, -0.5, 0.5, "Bark")
		SK.Box(s, -tw - 1.5, -tw - 0.5, by + 0.5, by + 1.0, -0.5, 0.5, "Bark")
		SK.Box(s, tw, tw + 1.0, by + 0.5, by + 1.0, -0.5, 0.5, "Bark")
		SK.Box(s, tw + 0.5, tw + 1.5, by + 1.0, by + 1.5, -0.5, 0.5, "Bark")
	end
	local f = s.Foliage
	SK.Ell(f, 0, cy, 0, cr, cr * 0.7, cr, "Canopy")
	if level >= 3 then
		SK.Ell(f, -cr * 0.6, cy - cr * 0.15, cr * 0.2, cr * 0.6, cr * 0.5, cr * 0.6, "Canopy")
		SK.Ell(f, cr * 0.6, cy - cr * 0.1, -cr * 0.2, cr * 0.6, cr * 0.5, cr * 0.6, "Canopy")
	end
	if level >= 7 then
		SK.Ell(f, 0, cy + cr * 0.55, 0, cr * 0.55, cr * 0.4, cr * 0.55, "Canopy")
	end
	SK.Shade(f, { Only = { Canopy = true }, Smooth = 1, Seed = 9 })
	-- the starfruit: little five-point stars (a plus of voxels) hanging around the canopy
	local n = 1 + math.ceil(level / 2)
	for _, p in ipairs(Plant.spread(n, 0, cy, 0, cr + 0.4, cr * 0.7 + 0.4, cr + 0.4, -0.75, 0.25, 3)) do
		local x, y, z = floor(p[1] / 0.5) * 0.5, floor(p[2] / 0.5) * 0.5, floor(p[3] / 0.5) * 0.5
		if abs(p[4]) > abs(p[5]) then
			SK.Box(s, x, x + 0.5, y, y + 0.5, z - 0.5, z + 1.0, "Star")
			SK.Box(s, x, x + 0.5, y - 0.5, y + 1.0, z, z + 0.5, "Star")
		else
			SK.Box(s, x - 0.5, x + 1.0, y, y + 0.5, z, z + 0.5, "Star")
			SK.Box(s, x, x + 0.5, y - 0.5, y + 1.0, z, z + 0.5, "Star")
		end
	end
	return cy, cy + cr
end

function Art.Plant(def, level)
	local look = Plant.LOOK[def.Id] or Plant.LOOK.Press1
	local t = (level - 1) / max(1, (def.MaxLevel or 10) - 1)
	local tpl = newTemplate("Plant")
	local s = SK.New(0.5)
	s.Foliage = SK.New(1.0)
	local sculpt = Plant[look.Fruit] or Plant.Berry
	if look.Fruit == "Starfruit" then
		sculpt = Plant.Star
	end
	local fruitY, topY = sculpt(s, level, t)
	local pal = Plant.palette(level)
	local m = SK.Build(s, pal, { Name = "Body", Collide = "big", MaxParts = Plant.MAX_PARTS - 6 })
	absorb(tpl.Model, m)
	if s.Foliage.G.Count > 0 then
		absorb(tpl.Model, SK.Build(s.Foliage, pal, { Name = "Foliage", Collide = "big", MaxParts = Plant.MAX_PARTS - #tpl.Model:GetChildren() }))
	end
	if level >= 10 then
		local anchor = biggestPart(tpl.Model)
		if anchor then
			local att = Instance.new("Attachment")
			att.Name = "Sparkle"
			att.CFrame = anchor.CFrame:Inverse() * CFrame.new(0, topY, 0)
			att.Parent = anchor
			emitter(att, { Color = ColorSequence.new(C.TextGold), Rate = 3, SpreadAngle = Vector2.new(180, 180) })
		end
	end
	tpl.Points.FruitPoint = Vector3.new(0, fruitY, 0)
	tpl.Info.Fruit = look.Fruit
	tpl.Info.FruitColor = look.Color
	return tpl
end

----------------------------------------------------------------------
-- Coin Magnet (the old Collector slot): a carved totem pole with a happy face on a round stone base, crowned by a
-- big red horseshoe magnet holding a gold coin. The magnet is its own model `MagnetHead` (HomeFx spins it about
-- the MagnetCenter point). Taller, gold trims (4+), more coins and sparks at the top level. <= 55 parts.
----------------------------------------------------------------------
function Art.Magnet(def, level)
	local tpl = newTemplate("Magnet")
	local s = SK.New(0.5)
	local gold = level >= 4
	local trim = gold and "Gold" or "Trim"
	SK.Oct(s, 0, 0, 2.5, 0, 0.5, "Base")
	SK.Oct(s, 0, 0, 2.0, 0.5, 1.0, trim)
	local poleTop = snap(3.5 + 0.75 * level)
	SK.Box(s, -1.0, 1.0, 1.0, poleTop, -1.0, 1.0, "Totem")
	local y = 1.5
	while y + 0.5 <= poleTop - 2.5 do
		SK.Box(s, -1.0, 1.0, y, y + 0.5, -1.0, 1.0, "Band")
		y = y + 1.5
	end
	-- the happy face on the front (-Z): two eyes and a smile, little wing ears from 2
	local fy = poleTop - 1.5
	SK.Box(s, -1.0, -0.5, fy, fy + 0.5, -1.0, -0.5, "Eye")
	SK.Box(s, 0.5, 1.0, fy, fy + 0.5, -1.0, -0.5, "Eye")
	SK.Box(s, -0.5, 0.5, fy - 1.0, fy - 0.5, -1.0, -0.5, "Smile")
	if level >= 2 then
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and -1.5 or 1.0
			SK.Box(s, x0, x0 + 0.5, fy - 0.5, fy + 0.5, -0.5, 0.5, "Wing")
			local x1 = x0 + sx * 0.5
			SK.Box(s, x1, x1 + 0.5, fy, fy + 1.0, -0.5, 0.5, "Wing")
		end
	end
	SK.Box(s, -1.5, 1.5, poleTop, poleTop + 0.5, -1.5, 1.5, trim)
	SK.Box(s, -0.5, 0.5, poleTop + 0.5, poleTop + 1.0, -0.5, 0.5, trim)
	-- coin stacks on the base (3+)
	if level >= 3 then
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and -2.5 or 1.5
			SK.Box(s, x0, x0 + 1.0, 0.5, (level >= 5) and 2.0 or 1.5, -2.0, -1.0, "Coin")
		end
	end
	local pal = mergeTables(P, {
		Base = C.StoneDark,
		Trim = rgb(124, 156, 210),
		Totem = rgb(204, 150, 104),
		Band = rgb(170, 112, 78),
		Eye = rgb(40, 44, 64),
		Smile = rgb(232, 94, 100),
		Wing = rgb(122, 196, 236),
		Coin = P.Gold,
		Magnet = rgb(226, 62, 70),
		Tip = rgb(226, 232, 244),
		Spark = { Color = rgb(150, 236, 255), Material = MAT.Neon },
	})
	local body = SK.Build(s, pal, { Name = "Body", Collide = "big" })
	absorb(tpl.Model, body)

	-- the magnet: a horseshoe (opening up) standing in the XY plane, facing the yard
	local hs = SK.New(0.5)
	local hw = (level >= 3) and 2.0 or 1.5
	local y0 = poleTop + 1.0
	local armH = (level >= 3) and 2.5 or 2.0
	SK.Box(hs, -hw + 0.5, hw - 0.5, y0, y0 + 1.0, -0.5, 0.5, "Magnet")
	SK.Box(hs, -hw, hw, y0 + 0.5, y0 + 1.0, -0.5, 0.5, "Magnet")
	SK.Box(hs, -hw, -hw + 1.0, y0 + 1.0, y0 + 1.0 + armH, -0.5, 0.5, "Magnet")
	SK.Box(hs, hw - 1.0, hw, y0 + 1.0, y0 + 1.0 + armH, -0.5, 0.5, "Magnet")
	local ty = y0 + 1.0 + armH
	SK.Box(hs, -hw, -hw + 1.0, ty, ty + 1.0, -0.5, 0.5, "Tip")
	SK.Box(hs, hw - 1.0, hw, ty, ty + 1.0, -0.5, 0.5, "Tip")
	if level >= 2 then
		-- the gold coin it caught, between the arms
		local cr = (level >= 3) and 0.9 or 0.5
		SK.DiscZ(hs, 0, y0 + 1.0 + cr + 0.25, -0.5, 0.5, cr, "Coin")
	end
	if level >= 5 then
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and (-hw) or (hw - 0.5)
			SK.Box(hs, x0, x0 + 0.5, ty + 1.0, ty + 1.5, -0.5, 0, "Spark")
		end
	end
	local head = SK.Build(hs, pal, { Name = "MagnetHead" })
	local primary = biggestPart(head, "Magnet") or biggestPart(head)
	if primary then
		head.PrimaryPart = primary
	end
	head.Parent = tpl.Model
	if level >= 5 and primary then
		local att = Instance.new("Attachment")
		att.Name = "Sparkle"
		att.CFrame = primary.CFrame:Inverse() * CFrame.new(0, ty + 1.0, 0)
		att.Parent = primary
		emitter(att, { Color = ColorSequence.new(rgb(150, 236, 255), C.TextGold), Rate = 3, SpreadAngle = Vector2.new(180, 180) })
	end
	tpl.Points.MagnetCenter = Vector3.new(0, y0 + (armH + 2.0) / 2, 0)
	return tpl
end

----------------------------------------------------------------------
-- Garden (section 3.3): 12 pet places on a 3 x 4 grid (Slot.Spots), sand walks (Slot.Walkable) with the 3-stud
-- entrance at the front middle (the pad faces it). Open places (`open`, from SetGarden: 3 + Prestige stars, not the
-- Garden level) are flower beds with a soft cushion; the others are seedling beds with a small "Prestige to open"
-- sign. Bowls, fruit, coins and heaps are CLIENT parts (HomeFx). The Garden level adds decor (birdhouse, hedges,
-- the entrance arch, fruit trees, lanterns, gold). Every place has an Attachment Spot<i> (attributes Slot, Open) on
-- its cushion; every open place a GardenSpotPrompt ("Put a pet here", E, attributes Slot / OwnerUserId) at the
-- cushion's far edge (the edge farthest from the walks' centre lines), MaxActivationDistance 3, so it never pops up
-- for a kid walking the walks. HomeBuilder.SetGarden enables it only on OPEN EMPTY places. <= 85 parts.
----------------------------------------------------------------------
local Garden = {}

Garden.PROMPT_RANGE = 3 -- studs (contract 3.3)
Garden.PROMPT_LIFT = 2.0 -- the prompt point: half a stud over the cushion top (reachable from the cushion and the bed)
Garden.CUSHION_TOP = 1.5

function Garden.places(def)
	return (def and def.Slot and type(def.Slot.Spots) == "table") and def.Slot.Spots or {}
end

function Garden.walks(def)
	local w = def and def.Slot and def.Slot.Walkable
	return (type(w) == "table") and w or {}
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

-- distance (ground plane) from q to a walk's centre line (its long axis, inset by half its width at both ends)
function Garden.lineDistance(q, w)
	local c, sz = w.Center, w.Size
	if typeof(c) ~= "Vector3" or typeof(sz) ~= "Vector3" then
		return huge
	end
	local ax, az
	if sz.X >= sz.Z then
		local half = max(0, sz.X / 2 - sz.Z / 2)
		ax, az = max(c.X - half, min(c.X + half, q.X)), c.Z
	else
		local half = max(0, sz.Z / 2 - sz.X / 2)
		ax, az = c.X, max(c.Z - half, min(c.Z + half, q.Z))
	end
	return math.sqrt((q.X - ax) ^ 2 + (q.Z - az) ^ 2)
end

-- the prompt point of place i (station frame): the cushion edge midpoint farthest from every walk's centre line
function Garden.promptPoint(def, i)
	local p = Garden.places(def)[i]
	if typeof(p) ~= "Vector3" then
		return nil
	end
	local best, bestD = nil, -1
	for _, c in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		local q = Vector3.new(p.X + c[1], Garden.PROMPT_LIFT, p.Z + c[2])
		local d = huge
		for _, w in ipairs(Garden.walks(def)) do
			d = min(d, Garden.lineDistance(q, w))
		end
		if d > bestD + 1e-6 then
			best, bestD = q, d
		end
	end
	return best
end

-- the entrance walk's x half-width (the front-row beds beside it are trimmed to keep it clear)
function Garden.entranceHalf(def)
	for _, w in ipairs(Garden.walks(def)) do
		if w.Name == "Entrance" and typeof(w.Size) == "Vector3" then
			return w.Size.X / 2, w
		end
	end
	return 1.5, nil
end

-- the "Prestige to open" placard of a seedling bed (World text rule: 50 px per stud; a big gold star >= 0.95 stud,
-- the words at 0.6 stud). 3.4 studs wide (the bed is 3): kept clear of the entrance walk (|x| >= ent)
function Garden.closedSign(parent, x, z, ent)
	local w = 3.4
	local cx = x
	if ent and abs(x) - w / 2 < ent then
		cx = (x < 0) and -(ent + w / 2) or (ent + w / 2)
	end
	local board = box(parent, "ClosedSign", CFrame.new(cx, 1.6, z - 1.3), Vector3.new(w, 1.4, 0.2), C.PlankLight, { Shadow = false })
	local gui = surfaceGui(board, Enum.NormalId.Front, "ClosedGui")
	local panel = plainFrame(gui, "Panel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0 })
	vgradient(panel, C.Violet, C.Navy)
	rounded(panel, 10)
	outline(panel, C.TextGold, 4, 0.1)
	signText(panel, GLYPH.Star, "Heading", 48, C.TextGold, "Star", 0.0, 0.0, 0.28, 1.0)
	signText(panel, "Prestige", "Heading", 30, C.TextGold, "Title", 0.28, 0.02, 0.72, 0.48)
	signText(panel, "to open", "Body", 30, C.Text, "Info", 0.28, 0.5, 0.72, 0.48)
	return board
end

function Art.Garden(def, level, open)
	local tpl = newTemplate("Garden")
	local fp = (def.Slot and def.Slot.Footprint) or Vector3.new(22, 4, 20)
	local hx, hz = fp.X / 2, fp.Z / 2
	local spots = Garden.places(def)
	open = Garden.clampOpen(open, #spots)
	local ent, entWalk = Garden.entranceHalf(def)
	local gold = level >= 8
	local s = SK.New(0.5)
	-- a low stone rim (the back a hedge from 2); the front line sits half a stud in, leaving a grass verge
	local fz = -hz + 0.5
	SK.Box(s, -hx, -hx + 0.5, 0.5, 1.0, fz, hz, "Border")
	SK.Box(s, hx - 0.5, hx, 0.5, 1.0, fz, hz, "Border")
	SK.Box(s, -hx, -ent, 0.5, 1.0, fz, fz + 0.5, "Border")
	SK.Box(s, ent, hx, 0.5, 1.0, fz, fz + 0.5, "Border")
	if level >= 2 then
		SK.Box(s, -hx + 0.5, hx - 0.5, 0.5, 2.0, hz - 1.0, hz, "Hedge")
		SK.Box(s, -hx + 1.0, hx - 1.0, 2.0, 2.5, hz - 0.5, hz, "HedgeTop")
	else
		SK.Box(s, -hx, hx, 0.5, 1.0, hz - 0.5, hz, "Border")
	end
	-- the places: open = flower bed + cushion; closed = soil bed + seedling (the placard is added below)
	local ez0 = entWalk and (entWalk.Center.Z - entWalk.Size.Z / 2) or -hz
	local ez1 = entWalk and (entWalk.Center.Z + entWalk.Size.Z / 2) or -5
	for i, p in ipairs(spots) do
		local x, z = p.X, p.Z
		local x0, x1 = x - 1.5, x + 1.5
		if z + 1.5 > ez0 and z - 1.5 < ez1 then
			if x < 0 then
				x1 = min(x1, -ent)
			else
				x0 = max(x0, ent)
			end
		end
		if i <= open then
			SK.Box(s, x0, x1, 0.5, 1.0, z - 1.5, z + 1.5, "Bloom" .. ((i - 1) % 3 + 1))
			SK.Box(s, x - 1.0, x + 1.0, 1.0, Garden.CUSHION_TOP, z - 1.0, z + 1.0, "Cushion")
		else
			SK.Box(s, x0, x1, 0.5, 1.0, z - 1.5, z + 1.5, "Soil")
			SK.Box(s, x - 0.5, x + 0.5, 1.0, 2.0, z, z + 0.5, "Stem")
			SK.Box(s, x - 1.0, x + 1.0, 2.0, 2.5, z, z + 0.5, "Sprout")
		end
	end
	-- the entrance: stone posts (1), an arch with leaves (3+), blossoms on it (4+), lanterns hanging under it (6+)
	local postTop = (level >= 3) and 4.5 or 2.0
	local postKey = gold and "Gold" or ((level >= 3) and "PlankLight" or "StoneLight")
	SK.Box(s, -ent - 0.5, -ent, 0.5, postTop, fz, fz + 0.5, postKey)
	SK.Box(s, ent, ent + 0.5, 0.5, postTop, fz, fz + 0.5, postKey)
	if level >= 3 then
		SK.Box(s, -ent - 1.0, ent + 1.0, postTop, postTop + 0.5, fz - 0.5, fz + 1.0, postKey)
		SK.Box(s, -ent - 0.5, ent + 0.5, postTop + 0.5, postTop + 1.0, fz, fz + 0.5, "Leaf")
	end
	if level >= 4 then
		SK.Box(s, -ent, -0.5, postTop + 1.0, postTop + 1.5, fz, fz + 0.5, "Bloom1")
		SK.Box(s, 0.5, ent, postTop + 1.0, postTop + 1.5, fz, fz + 0.5, "Bloom2")
	end
	if level >= 6 then
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and (-ent - 1.0) or ent
			SK.Box(s, x0, x0 + 1.0, postTop - 1.0, postTop, fz, fz + 0.5, "Lamp")
		end
	end
	-- the birdhouse on a post behind the back row's middle (always)
	local bz = hz - 1.5
	SK.Box(s, -0.5, 0.5, 0.5, 3.5, bz, bz + 0.5, "PlankDark")
	SK.Box(s, -1.0, 1.0, 3.5, 5.0, bz - 0.5, bz + 1.0, "Birdhouse")
	SK.Box(s, -1.5, 1.5, 5.0, 5.5, bz - 1.0, bz + 1.5, gold and "Gold" or "Roof")
	-- round bushes in the front corners (4+); fruit trees in the back corners (5: left, 7: both)
	if level >= 4 then
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and (-hx + 0.5) or (hx - 2.0)
			SK.Box(s, x0, x0 + 1.5, 0.5, 2.0, fz + 0.5, fz + 2.0, "Hedge")
		end
	end
	if level >= 5 then
		for _, sx in ipairs((level >= 7) and { -1, 1 } or { -1 }) do
			-- trunk just outside the back corner bed, the crown kept inside the footprint (above the pets' heads)
			local tx = sx * (hx - 1.5)
			local tz = hz - 1.5
			SK.Box(s, tx - 0.5, tx + 0.5, 0.5, 4.5, tz - 0.5, tz + 0.5, "Bark")
			SK.Box(s, tx - 1.5, tx + 1.5, 4.5, 6.0, tz - 1.5, tz + 1.5, "Leaf")
			SK.Box(s, tx - 1.0, tx + 1.0, 6.0, 7.0, tz - 1.0, tz + 1.0, "LeafLight")
			SK.Box(s, tx - 0.5, tx, 4.0, 4.5, tz - 2.0, tz - 1.5, "Fruit")
		end
	end
	-- a row of flowers along the front rim (7+)
	if level >= 7 then
		SK.Box(s, -hx + 1.0, -ent - 1.0, 1.0, 1.5, fz, fz + 0.5, "Bloom3")
		SK.Box(s, ent + 1.0, hx - 1.0, 1.0, 1.5, fz, fz + 0.5, "Bloom3")
	end
	local pal = mergeTables(P, {
		Border = C.StoneLight,
		Birdhouse = rgb(250, 214, 140),
		Roof = rgb(222, 104, 82),
		Cushion = rgb(250, 228, 170),
		Soil = rgb(118, 86, 64),
		Stem = rgb(92, 160, 70),
		Sprout = rgb(146, 216, 104),
		Bloom1 = rgb(246, 150, 188),
		Bloom2 = rgb(250, 214, 92),
		Bloom3 = rgb(172, 142, 232),
		HedgeTop = rgb(98, 172, 90),
		LeafLight = rgb(122, 196, 98),
		Fruit = C.Red,
	})
	local m = SK.Build(s, pal, { Name = "Body", Collide = "big" })
	absorb(tpl.Model, m)
	-- the lawn (one part) and the sand walks (thin plates on it, exactly the catalog's walks; the side joins stop at
	-- the rim, the long walks between the joins, so no two plates overlap)
	local lawn = box(tpl.Model, "Lawn", CFrame.new(0, 0.25, 0), Vector3.new(2 * hx, 0.5, 2 * hz), rgb(128, 200, 98), { Collide = true })
	local sand = rgb(228, 212, 172)
	local joinX = nil
	for _, w in ipairs(Garden.walks(def)) do
		if (w.Name == "WestJoin" or w.Name == "EastJoin") and typeof(w.Center) == "Vector3" then
			joinX = abs(w.Center.X) - w.Size.X / 2
		end
	end
	for _, w in ipairs(Garden.walks(def)) do
		local c, sz = w.Center, w.Size
		if typeof(c) == "Vector3" and typeof(sz) == "Vector3" then
			local x0, x1 = c.X - sz.X / 2, c.X + sz.X / 2
			local z0, z1 = c.Z - sz.Z / 2, c.Z + sz.Z / 2
			x0, x1 = max(x0, -hx + 0.5), min(x1, hx - 0.5)
			if sz.X > sz.Z and joinX then
				x0, x1 = max(x0, -joinX), min(x1, joinX)
			end
			if w.Name == "Entrance" then
				z0 = -hz
			end
			if x1 > x0 and z1 > z0 then
				box(tpl.Model, tostring(w.Name or "Walk"), CFrame.new((x0 + x1) / 2, 0.55, (z0 + z1) / 2), Vector3.new(x1 - x0, 0.1, z1 - z0), sand, { Collide = true, Shadow = false })
			end
		end
	end
	-- the placards of the closed places
	for i, p in ipairs(spots) do
		if i > open then
			Garden.closedSign(tpl.Model, p.X, p.Z, ent)
		end
	end
	if gold then
		local att = Instance.new("Attachment")
		att.Name = "Sparkle"
		att.CFrame = lawn.CFrame:Inverse() * CFrame.new(0, postTop + 1.5, fz)
		att.Parent = lawn
		emitter(att, { Color = ColorSequence.new(C.TextGold), Rate = 3, SpreadAngle = Vector2.new(180, 180) })
	end
	-- where pets sit (Spot<i>, every place) and the GardenSpotPrompts (open places; SetGarden enables them)
	for i, p in ipairs(spots) do
		local a = Instance.new("Attachment")
		a.Name = "Spot" .. i
		a.CFrame = lawn.CFrame:Inverse() * CFrame.new(p.X, Garden.CUSHION_TOP, p.Z)
		a:SetAttribute("Slot", i)
		a:SetAttribute("Open", i <= open)
		a.Parent = lawn
		local q = (i <= open) and Garden.promptPoint(def, i) or nil
		if q then
			local pa = Instance.new("Attachment")
			pa.Name = "PromptPoint" .. i
			pa.CFrame = lawn.CFrame:Inverse() * CFrame.new(q)
			pa:SetAttribute("Slot", i)
			pa.Parent = lawn
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "GardenSpotPrompt"
			prompt.ActionText = "Put a pet here"
			prompt.ObjectText = "Garden place " .. i
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = Garden.PROMPT_RANGE
			prompt.RequiresLineOfSight = false
			prompt.Enabled = false
			prompt:SetAttribute("Slot", i)
			prompt:SetAttribute("StationId", "Garden")
			prompt.Parent = pa
		end
	end
	tpl.Info.Open = open
	return tpl
end

----------------------------------------------------------------------
-- Food Machine (the old Kitchen slot, section 3.4): front -Z. A cheerful cabinet with a glass Hopper full of fruit
-- on top (the part named `Hopper`: PetCareService puts the FeedPrompt on it), a dispenser mouth with a chute over a
-- bowl tray, a big round FEED button and a food window. Lights (2+), a second side hopper (3+), a shelf of bowls
-- (4+), gold trims and a star (5). HomeFx animates the food (points ChuteMouth, Tray, HopperTop). <= 55 parts.
----------------------------------------------------------------------
function Art.FoodMachine(def, level)
	local tpl = newTemplate("FoodMachine")
	local s = SK.New(0.5)
	local gold = level >= 5
	local trim = gold and "Gold" or "Trim"
	local hw = ({ 3.5, 3.5, 4.0, 4.5, 5.0 })[level] or 5.0
	local top = ({ 4.5, 5.0, 5.0, 5.5, 6.0 })[level] or 6.0
	local z0, z1 = -1.5, 2.5
	local zc = (z0 + z1) / 2
	SK.RBox(s, -hw - 0.5, hw + 0.5, 0, 0.5, z0 - 2.5, z1 + 0.5, 0.5, "Plinth")
	SK.RBox(s, -hw, hw, 0.5, top, z0, z1, 0.75, "Body")
	SK.Box(s, -hw, hw, top - 0.5, top, z0, z1, trim)
	-- the front: a cream panel, the dark dispenser mouth, a two-step chute and the bowl tray below it
	SK.Box(s, -hw + 0.5, hw - 0.5, 1.0, top - 1.0, z0 - 0.5, z0, "Panel")
	SK.Box(s, -1.0, 1.0, 1.5, 3.0, z0 - 0.5, z0, "Mouth")
	SK.Box(s, -1.0, 1.0, 2.0, 2.5, z0 - 1.0, z0 - 0.5, "Chute")
	SK.Box(s, -1.0, 1.0, 1.5, 2.0, z0 - 1.5, z0 - 1.0, "Chute")
	SK.Box(s, -1.5, 1.5, 0.5, 1.0, z0 - 2.5, z0 - 1.0, "Tray")
	SK.Box(s, -1.0, 1.0, 1.0, 1.5, z0 - 2.0, z0 - 1.5, "Kibble")
	-- the big FEED button (right) and the food window (left)
	SK.DiscZ(s, hw - 1.25, 3.25, z0 - 0.5, z0, 0.95, gold and "Gold" or "ButtonRim")
	SK.DiscZ(s, hw - 1.25, 3.25, z0 - 1.0, z0 - 0.5, 0.6, "Button")
	SK.Box(s, -hw + 1.0, -1.5, 2.0, top - 1.5, z0 - 0.5, z0, "Window")
	-- the hopper funnel and lid (the glass Hopper itself is one part, added below)
	local gw = (level >= 4) and 4.0 or 3.0
	local gh = snap(2.5 + 0.25 * level)
	local gy0 = top + 0.5
	SK.Oct(s, 0, zc, 1.0, top, gy0, "Funnel")
	-- fruit inside the hopper: berry, carrot and melon layers with a heap of starfruit on top
	local fi = gw / 2 - 0.5
	SK.Box(s, -fi, fi, gy0, gy0 + 0.5, zc - fi, zc + fi, "FoodA")
	SK.Box(s, -fi, fi, gy0 + 0.5, gy0 + 1.0, zc - fi, zc + fi, "FoodB")
	SK.Box(s, -fi, fi, gy0 + 1.0, gy0 + 1.5, zc - fi, zc + fi, "FoodC")
	SK.Box(s, -fi + 0.5, fi - 0.5, gy0 + 1.5, gy0 + 2.0, zc - fi + 0.5, zc + fi - 0.5, "FoodD")
	SK.Box(s, -gw / 2 - 0.5, gw / 2 + 0.5, gy0 + gh, gy0 + gh + 0.5, zc - gw / 2 - 0.5, zc + gw / 2 + 0.5, trim)
	SK.Box(s, -0.5, 0.5, gy0 + gh + 0.5, gy0 + gh + 1.0, zc - 0.5, zc + 0.5, gold and "Gold" or "Knob")
	if gold then
		-- a gold star on the lid
		SK.Box(s, -1.0, 1.0, gy0 + gh + 1.5, gy0 + gh + 2.0, zc - 0.5, zc + 0.5, "Gold")
		SK.Box(s, -0.5, 0.5, gy0 + gh + 1.0, gy0 + gh + 2.5, zc - 0.5, zc + 0.5, "Gold")
	end
	-- 2+: two lamps on the front corners of the roof
	if level >= 2 then
		SK.Box(s, -hw + 0.5, -hw + 1.0, top, top + 1.0, z0 + 0.5, z0 + 1.0, "Bulb")
		SK.Box(s, hw - 1.0, hw - 0.5, top, top + 1.0, z0 + 0.5, z0 + 1.0, "Bulb")
	end
	-- 3+: a second, smaller hopper on a stand at the left with a pipe into the cabinet
	local side = nil
	if level >= 3 then
		local sx = -hw - 1.5
		SK.Box(s, sx - 1.0, sx + 1.0, 0.5, 2.5, zc - 1.0, zc + 1.0, "Stand")
		SK.Box(s, sx - 0.5, sx + 0.5, 2.5, 3.0, zc - 0.5, zc + 0.5, "FoodB")
		SK.Box(s, sx - 0.5, sx + 0.5, 3.0, 3.5, zc - 0.5, zc + 0.5, "FoodD")
		SK.Box(s, sx - 1.5, sx + 1.5, 5.0, 5.5, zc - 1.5, zc + 1.5, trim)
		SK.Box(s, sx + 1.0, -hw, 4.0, 4.5, zc - 0.5, zc + 0.5, "Pipe")
		side = { X = sx, Y = 3.75, Z = zc }
	end
	-- 4+: a shelf with stacked bowls on the right
	if level >= 4 then
		local bx = hw + 1.5
		SK.Box(s, bx - 1.0, bx + 1.0, 0.5, 1.5, zc - 1.0, zc + 1.0, "Stand")
		SK.Box(s, bx - 1.0, bx + 1.0, 1.5, 2.0, zc - 1.0, zc + 1.0, "Bowl1")
		SK.Box(s, bx - 1.0, bx + 1.0, 2.0, 2.5, zc - 1.0, zc + 1.0, "Bowl2")
		SK.Box(s, bx - 1.0, bx + 1.0, 2.5, 3.0, zc - 1.0, zc + 1.0, "Bowl3")
	end
	local pal = mergeTables(P, {
		Plinth = C.StoneDark,
		Body = rgb(240, 112, 104),
		Trim = rgb(118, 168, 236),
		Panel = rgb(252, 240, 220),
		Mouth = rgb(44, 40, 58),
		Chute = C.IronLight,
		Tray = rgb(92, 150, 230),
		Kibble = rgb(250, 168, 72),
		ButtonRim = rgb(246, 242, 232),
		Button = { Color = rgb(255, 72, 84), Material = MAT.Neon },
		Window = { Color = rgb(170, 226, 255), Material = MAT.Neon },
		Funnel = C.IronLight,
		FoodA = rgb(226, 58, 94),
		FoodB = rgb(250, 140, 46),
		FoodC = rgb(150, 224, 176),
		FoodD = rgb(255, 212, 70),
		Knob = rgb(240, 112, 104),
		Bulb = { Color = C.Lamp, Material = MAT.Neon },
		Stand = C.PlankDark,
		Pipe = C.IronLight,
		Bowl1 = rgb(246, 150, 188),
		Bowl2 = rgb(250, 214, 92),
		Bowl3 = rgb(150, 224, 176),
	})
	local m = SK.Build(s, pal, { Name = "Body", Collide = "big" })
	absorb(tpl.Model, m)
	-- the glass hopper (PetCareService's FeedPrompt sits on it) and the side hopper's glass
	box(tpl.Model, "Hopper", CFrame.new(0, gy0 + gh / 2, zc), Vector3.new(gw, gh, gw), rgb(206, 236, 252), { Material = MAT.Glass, Transparency = 0.55, Shadow = false })
	if side then
		box(tpl.Model, "HopperSide", CFrame.new(side.X, side.Y, side.Z), Vector3.new(2, 2.5, 2), rgb(206, 236, 252), { Material = MAT.Glass, Transparency = 0.55, Shadow = false })
	end
	if gold then
		local anchor = biggestPart(tpl.Model, "Body") or biggestPart(tpl.Model)
		if anchor then
			local att = Instance.new("Attachment")
			att.Name = "Sparkle"
			att.CFrame = anchor.CFrame:Inverse() * CFrame.new(0, gy0 + gh + 2.0, zc)
			att.Parent = anchor
			emitter(att, { Color = ColorSequence.new(C.TextGold), Rate = 3, SpreadAngle = Vector2.new(180, 180) })
		end
	end
	tpl.Points.ChuteMouth = Vector3.new(0, 2.0, z0 - 1.25)
	tpl.Points.Tray = Vector3.new(0, 1.5, z0 - 1.75)
	tpl.Points.HopperTop = Vector3.new(0, gy0 + gh, zc)
	return tpl
end

----------------------------------------------------------------------
-- Training Place (the old Gym slot, section 3.7): front -Z. A wooden deck that grows from the left edge; one bright
-- training mat per level at Slot.Spots (Attachments Spot1..5 on the deck, attribute Slot; HomeFx puts the training
-- pet and its skill prop on it) and behind each mat its skill corner: weights (Physique, 1), hurdles (Attack Speed,
-- 2), a glowing orb on a pedestal (Ability, 3), a shield wall (Defense, 4) and a scoreboard with a trophy (5, gold).
-- The front stays open so the yard sees the training pets. <= 90 parts.
----------------------------------------------------------------------
local TRAIN_MATS = { rgb(236, 92, 96), rgb(250, 204, 72), rgb(176, 120, 236), rgb(84, 140, 226), rgb(110, 200, 120) }

function Art.Training(def, level)
	local tpl = newTemplate("Training")
	local s = SK.New(0.5)
	local fp = (def.Slot and def.Slot.Footprint) or Vector3.new(18, 10, 9)
	local hz = fp.Z / 2
	local spots = (def.Slot and def.Slot.Spots) or {}
	local w = ({ 9, 12, 15, 18, 18 })[level] or 18
	local x0 = -fp.X / 2
	local x1 = x0 + w
	local gold = level >= 5
	SK.Box(s, x0, x1, 0, 0.5, -hz, hz, "Deck2")
	SK.Box(s, x0 + 0.5, x1 - 0.5, 0.5, 1.0, -hz + 0.5, hz - 0.5, "Deck")
	if gold then
		SK.Box(s, x0, x1, 0.5, 1.0, -hz, -hz + 0.5, "Gold")
	end
	local bz = 2.0 -- the skill corners stand behind the mats (z 2 .. hz - 0.5)
	local function spotX(i)
		local p = spots[i]
		return (typeof(p) == "Vector3") and p.X or (x0 + 3 * i)
	end
	-- 1 Physique: a barbell on a rack
	do
		local cx = spotX(1)
		SK.Box(s, cx - 1.5, cx + 1.5, 1.0, 2.0, bz, bz + 1.5, "Rack")
		SK.Box(s, cx - 1.5, cx - 1.0, 2.0, 3.0, bz + 0.5, bz + 1.0, "Iron")
		SK.Box(s, cx + 1.0, cx + 1.5, 2.0, 3.0, bz + 0.5, bz + 1.0, "Iron")
		SK.Box(s, cx - 2.0, cx + 2.0, 3.0, 3.5, bz + 0.5, bz + 1.0, "Iron")
		SK.Box(s, cx - 2.5, cx - 2.0, 2.5, 4.0, bz, bz + 1.5, "Weight")
		SK.Box(s, cx + 2.0, cx + 2.5, 2.5, 4.0, bz, bz + 1.5, "Weight")
	end
	-- 2 Attack Speed: two striped hurdles
	if level >= 2 then
		local cx = spotX(2)
		for _, hx in ipairs({ cx - 1.0, cx + 1.0 }) do
			SK.Box(s, hx - 0.5, hx, 1.0, 2.5, bz, bz + 0.5, "Iron")
			SK.Box(s, hx - 0.5, hx, 1.0, 2.5, bz + 2.0, bz + 2.5, "Iron")
			SK.Box(s, hx - 0.5, hx, 2.5, 3.0, bz, bz + 2.5, "Hurdle")
			SK.Box(s, hx - 0.5, hx, 2.5, 3.0, bz + 1.0, bz + 1.5, "HurdleStripe")
		end
	end
	-- 3 Ability: a glowing orb on a stone pedestal
	if level >= 3 then
		local cx = spotX(3)
		SK.Box(s, cx - 1.0, cx + 1.0, 1.0, 1.5, bz, bz + 2.0, "Stone")
		SK.Box(s, cx - 0.5, cx + 0.5, 1.5, 3.0, bz + 0.5, bz + 1.5, "Stone")
		SK.Box(s, cx - 1.0, cx + 1.0, 3.0, 3.5, bz, bz + 2.0, gold and "Gold" or "Stone")
		SK.Ell(s, cx, 4.25, bz + 1.0, 0.8, 0.8, 0.8, "Orb")
	end
	-- 4 Defense: a wooden wall with a round shield
	if level >= 4 then
		local cx = spotX(4)
		SK.Box(s, cx - 1.5, cx + 1.5, 1.0, 4.5, hz - 1.0, hz - 0.5, "Plank")
		SK.Box(s, cx - 1.5, cx + 1.5, 4.5, 5.0, hz - 1.5, hz - 0.5, "PlankDark")
		SK.DiscZ(s, cx, 2.75, hz - 1.5, hz - 1.0, 1.2, "Shield")
		SK.DiscZ(s, cx, 2.75, hz - 2.0, hz - 1.5, 0.45, gold and "Gold" or "IronLight")
	end
	-- 5: a scoreboard with lights and a gold trophy on a little stand
	if gold then
		local cx = spotX(5)
		SK.Box(s, cx - 2.0, cx - 1.5, 1.0, 5.5, hz - 1.0, hz - 0.5, "PlankDark")
		SK.Box(s, cx + 1.5, cx + 2.0, 1.0, 5.5, hz - 1.0, hz - 0.5, "PlankDark")
		SK.Box(s, cx - 2.0, cx + 2.0, 5.5, 7.5, hz - 1.0, hz - 0.5, "Board")
		for i, key in ipairs({ "Light1", "Light2", "Light3" }) do
			local lx = cx - 2.5 + i
			SK.Box(s, lx, lx + 1.0, 6.0, 7.0, hz - 1.5, hz - 1.0, key)
		end
		SK.Box(s, cx - 0.5, cx + 0.5, 1.0, 2.0, bz, bz + 1.0, "Stone")
		SK.Box(s, cx - 0.5, cx + 0.5, 2.0, 3.0, bz, bz + 1.0, "Gold")
		SK.Box(s, cx - 1.0, cx + 1.0, 3.0, 3.5, bz, bz + 1.0, "Gold")
	end
	-- pennant posts at the deck's back corners (3+)
	if level >= 3 then
		for _, px in ipairs({ x0, x1 - 0.5 }) do
			SK.Box(s, px, px + 0.5, 1.0, 6.0, hz - 0.5, hz, gold and "Gold" or "PlankDark")
			local fx = (px < 0) and (px + 0.5) or (px - 1.5)
			SK.Box(s, fx, fx + 1.5, 5.0, 6.0, hz - 0.5, hz, "Pennant")
		end
	end
	local pal = mergeTables(P, {
		Deck = C.PlankLight,
		Deck2 = C.PlankDark,
		Rack = rgb(70, 76, 98),
		Weight = rgb(46, 50, 64),
		Hurdle = rgb(236, 86, 86),
		HurdleStripe = rgb(250, 244, 236),
		Orb = { Color = rgb(186, 130, 255), Material = MAT.Neon },
		Shield = rgb(84, 140, 226),
		Board = rgb(40, 52, 88),
		Pennant = rgb(236, 86, 86),
		Light1 = { Color = rgb(120, 220, 120), Material = MAT.Neon },
		Light2 = { Color = rgb(250, 214, 90), Material = MAT.Neon },
		Light3 = { Color = rgb(255, 120, 110), Material = MAT.Neon },
	})
	local m = SK.Build(s, pal, { Name = "Body", Collide = "big" })
	absorb(tpl.Model, m)
	-- the training mats: a bright plate with a white inner square, lying on the deck (the deck stays one part)
	for i, p in ipairs(spots) do
		if i <= level then
			box(tpl.Model, "Mat", CFrame.new(p.X, 1.05, p.Z), Vector3.new(2.6, 0.1, 2.6), TRAIN_MATS[i] or TRAIN_MATS[1], { Shadow = false })
			box(tpl.Model, "MatIn", CFrame.new(p.X, 1.1, p.Z), Vector3.new(1.4, 0.1, 1.4), rgb(250, 246, 238), { Shadow = false })
		end
	end
	local deck = biggestPart(tpl.Model, "Deck") or biggestPart(tpl.Model)
	for i, p in ipairs(spots) do
		if i <= level and deck then
			local a = Instance.new("Attachment")
			a.Name = "Spot" .. i
			a.CFrame = deck.CFrame:Inverse() * CFrame.new(p.X, 1.15, p.Z)
			a:SetAttribute("Slot", i)
			a.Parent = deck
		end
	end
	return tpl
end

----------------------------------------------------------------------
-- Vault: front -Z. A small safe (1) ... a grand gold-domed vault (5).
----------------------------------------------------------------------
function Art.Vault(def, level)
	local tpl = newTemplate("Vault")
	local s = SK.New(0.5)
	-- { width, wall height }: the outer width (plinth, columns: width + 1) stays inside the footprint and clear of
	-- the press lane beside it, so the top levels grow upward; heights keep the door's centre on a quarter stud so
	-- its wheel stays symmetric
	local sizes = { { 3, 3 }, { 4, 4 }, { 5, 5.5 }, { 5, 6.5 }, { 5, 7.5 } }
	local sz = sizes[level] or sizes[5]
	local w, h = sz[1], sz[2]
	local hw = w / 2
	local hd = min(w, 6) / 2
	local cy = 0.5 + h / 2 -- the door's centre height
	local wheel = nil -- { centre, radius } of the door wheel (parts added after the build)
	SK.RBox(s, -hw - 0.5, hw + 0.5, 0, 0.5, -hd - 0.5, hd + 0.5, 0.5, "Plinth")
	if level <= 2 then
		-- a sturdy safe on little feet: a dark steel body, a lighter door panel, a dial and a gold handle
		SK.RBox(s, -hw, hw, 1.0, 0.5 + h, -hd, hd, 0.5, "Safe")
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and (-hw + 0.5) or (hw - 1.0)
			SK.Box(s, x0, x0 + 0.5, 0.5, 1.0, -hd + 0.5, -hd + 1.0, "Safe")
		end
		SK.Box(s, -hw + 0.5, hw - 0.5, 1.5, h, -hd - 0.5, -hd, "Door")
		SK.DiscZ(s, -0.25, cy, -hd - 1.0, -hd - 0.5, 0.55, "Steel")
		SK.Box(s, hw - 1.0, hw - 0.5, cy - 0.5, cy + 0.5, -hd - 1.0, -hd - 0.5, "Gold")
		if level >= 2 then
			SK.Box(s, -hw, hw, 0.5 + h - 0.5, 0.5 + h, -hd - 0.5, hd, "Gold")
		end
	else
		-- a stone vault house: walls, marble corner columns, a cornice (gold from 4), a big round steel door with a
		-- gold wheel, and a slate hip roof (3-4) or a stepped gold dome with a crystal (5)
		SK.Box(s, -hw, hw, 0.5, 0.5 + h, -hd, hd, "Wall")
		SK.Box(s, -hw - 0.5, hw + 0.5, 0.5 + h, 1.0 + h, -hd - 0.5, hd + 0.5, (level >= 4) and "Gold" or "StoneLight")
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and (-hw - 0.5) or (hw - 0.5)
			SK.Box(s, x0, x0 + 1.0, 0.5, 0.5 + h, -hd - 0.5, -hd + 0.5, "Column")
		end
		local dr = min(hw - 1.0, h / 2 - 0.5)
		SK.DiscZ(s, 0, cy, -hd - 0.5, -hd, dr + 0.5, "Steel")
		SK.DiscZ(s, 0, cy, -hd - 1.0, -hd - 0.5, dr, "Door")
		wheel = { cy, dr }
		if level >= 5 then
			local y = 1.0 + h
			SK.Box(s, -hw, hw, y, y + 0.5, -hd, hd, "Gold")
			SK.Box(s, -hw + 0.5, hw - 0.5, y + 0.5, y + 1.5, -hd + 0.5, hd - 0.5, "Gold")
			SK.Box(s, -hw + 1.5, hw - 1.5, y + 1.5, y + 2.5, -hd + 1.5, hd - 1.5, "Gold")
			SK.Box(s, -0.5, 0.5, y + 2.5, y + 3.0, -0.5, 0.5, "Gold")
		else
			SK.Hip(s, -hw, hw, -hd, hd, 1.0 + h, 0.5, "Roof", "RoofTop", "Roof2")
		end
	end
	-- coin piles on the plinth's front corner (2+), a stack of gold bars on the other (4+)
	if level >= 2 then
		SK.Box(s, hw - 0.5, hw + 0.5, 0.5, 1.0, -hd - 0.5, -hd + 0.5, "Coins")
		SK.Box(s, hw - 0.5, hw, 1.0, 1.5, -hd - 0.5, -hd, "Coins")
	end
	if level >= 4 then
		SK.Box(s, -hw - 0.5, -hw + 1.0, 0.5, 1.0, -hd - 0.5, -hd + 0.5, "Gold")
		SK.Box(s, -hw - 0.5, -hw + 0.5, 1.0, 1.5, -hd - 0.5, -hd, "GoldDark")
	end
	local pal = mergeTables(P, {
		Plinth = C.StoneDark,
		Safe = rgb(80, 92, 124),
		Door = rgb(122, 134, 166),
		Steel = rgb(170, 180, 204),
		Wall = rgb(218, 212, 200),
		Column = C.Marble,
		Roof = rgb(84, 104, 150),
		Roof2 = rgb(100, 122, 170),
		RoofTop = rgb(68, 86, 136),
		Coins = P.Gold,
	})
	SK.Shade(s, { Only = { Wall = true }, Smooth = 2, Light = false, Seed = 13 })
	local m = SK.Build(s, pal, { Name = "Body", Collide = "big" })
	absorb(tpl.Model, m)
	-- the door wheel: a gold hub and two crossed spokes, and the crystal on the dome (5)
	if wheel then
		local c = CFrame.new(0, wheel[1], -hd - 1.15)
		local len = wheel[2] * 2 - 0.6
		box(tpl.Model, "Wheel", c * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(len, 0.35, 0.3), C.Gold, { Shadow = false })
		box(tpl.Model, "Wheel", c * CFrame.Angles(0, 0, math.rad(-45)), Vector3.new(len, 0.35, 0.3), C.Gold, { Shadow = false })
		box(tpl.Model, "Wheel", c * CFrame.new(0, 0, -0.05), Vector3.new(0.8, 0.8, 0.4), C.GoldDark, { Shadow = false })
	end
	if level >= 5 then
		box(tpl.Model, "Crystal", CFrame.new(0, 1.0 + h + 3.7, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.9, 1.4, 0.9), C.Crystal, { Material = MAT.Neon, Shadow = false })
	end
	return tpl
end

----------------------------------------------------------------------
-- House: Cottage (1) -> Villa (2) -> Manor (3) -> Sky Castle (4). Front -Z faces the gate.
----------------------------------------------------------------------
local HOUSE_PAL = mergeTables(P, {
	Found = rgb(150, 144, 138),
	Wall = rgb(250, 238, 214),
	Timber = rgb(128, 88, 60),
	Roof = rgb(222, 104, 82),
	Roof2 = rgb(236, 124, 98),
	RoofTop = rgb(190, 82, 68),
	Door = rgb(150, 100, 66),
	Shutter = rgb(98, 148, 226),
	Sill = rgb(236, 226, 206),
	Chimney = rgb(176, 112, 92),
	VillaWall = rgb(250, 214, 196),
	VillaTrim = rgb(252, 248, 240),
	Rail = rgb(252, 248, 240),
	Terracotta = rgb(220, 120, 80),
	Terracotta2 = rgb(232, 140, 98),
	ManorWall = rgb(232, 226, 240),
	ManorTrim = rgb(252, 250, 246),
	Slate = rgb(86, 106, 160),
	Slate2 = rgb(102, 124, 178),
	SlateTop = rgb(68, 86, 136),
	Castle = rgb(240, 240, 246),
	CastleShade = rgb(212, 216, 232),
	Tower = rgb(232, 234, 244),
	Spire = rgb(88, 136, 226),
	Spire2 = rgb(110, 158, 238),
	SpireTop = rgb(70, 112, 204),
	Banner = rgb(236, 88, 110),
	Bush = C.Hedge,
	Bush2 = rgb(96, 170, 88),
	CloudLight = rgb(252, 253, 255),
})

-- a window as relief on a face: the frame block one voxel out of the wall and the glass one more
local function windowZ(s, x, y, z, w, h, glassKey, frameKey, sillKey)
	SK.Box(s, x - w / 2 - 0.25, x + w / 2 + 0.25, y - 0.25, y + h + 0.25, z - 0.5, z, frameKey or "Sill")
	SK.Box(s, x - w / 2 + 0.25, x + w / 2 - 0.25, y + 0.25, y + h - 0.25, z - 1.0, z - 0.5, glassKey or "Window")
	if sillKey then
		SK.Box(s, x - w / 2 - 0.5, x + w / 2 + 0.5, y - 0.75, y - 0.25, z - 1.0, z, sillKey)
	end
end

local function houseCottage(s)
	-- a half-timbered cottage, 14 x 9, on a stone foundation; front at local z = -5
	local x0, x1, z0, z1 = -7, 7, -5, 4
	SK.Box(s, x0 - 0.5, x1 + 0.5, 0, 0.5, z0 - 0.5, z1 + 0.5, "Found")
	SK.Box(s, x0, x1, 0.5, 6.0, z0, z1, "Wall")
	for _, x in ipairs({ x0, -2.5, 2.0, x1 - 0.5 }) do
		SK.Box(s, x, x + 0.5, 0.5, 6.0, z0 - 0.5, z0, "Timber")
	end
	SK.Box(s, x0, x1, 3.0, 3.5, z0 - 0.5, z0, "Timber")
	SK.Box(s, x0 - 0.5, x1 + 0.5, 5.5, 6.0, z0 - 0.5, z1 + 0.5, "Timber")
	-- door (round top) + step + a brass knob
	SK.Box(s, -1.5, 1.5, 0, 0.5, z0 - 1.5, z0, "Found")
	SK.Box(s, -1.0, 1.0, 0.5, 3.5, z0 - 0.5, z0, "Door")
	SK.Box(s, -0.5, 0.5, 3.5, 4.0, z0 - 0.5, z0, "Door")
	SK.Box(s, 0.5, 1.0, 1.75, 2.25, z0 - 1.0, z0 - 0.5, "Gold")
	-- windows with blue shutters and flower boxes
	for _, x in ipairs({ -4.75, 4.25 }) do
		windowZ(s, x, 1.75, z0, 2.0, 1.75, "Window", "Sill")
		SK.Box(s, x - 1.75, x - 1.25, 1.5, 3.75, z0 - 1.0, z0 - 0.5, "Shutter")
		SK.Box(s, x + 1.25, x + 1.75, 1.5, 3.75, z0 - 1.0, z0 - 0.5, "Shutter")
		SK.Box(s, x - 1.25, x + 1.25, 1.0, 1.5, z0 - 1.5, z0 - 0.5, "Plank")
		SK.Box(s, x - 1.0, x, 1.5, 2.0, z0 - 1.5, z0 - 1.0, "Flower1")
		SK.Box(s, x, x + 1.0, 1.5, 2.0, z0 - 1.5, z0 - 1.0, "Flower2")
	end
	-- gabled roof (ridge along X) in two tile tones, chimney, a round attic window in the side gable
	local top = SK.Gable(s, x0 - 1.0, x1 + 1.0, z0 - 1.0, z1 + 1.0, 6.0, 0.5, "Roof", "X", "RoofTop", "Roof2")
	SK.Box(s, 3.5, 5.0, 6.0, top + 1.0, 0.5, 2.0, "Chimney")
	SK.Box(s, 3.25, 5.25, top + 1.0, top + 1.5, 0.25, 2.25, "StoneDark")
	-- two round bushes by the door
	for _, x in ipairs({ -2.75, 2.75 }) do
		SK.Oct(s, x, z0 - 1.25, 0.75, 0, 1.5, "Bush")
	end
	return top
end

local function houseVilla(s)
	-- a two-storey villa, 20 x 12, stucco + white trim, terracotta hip roof, a portico with a balcony
	local x0, x1, z0, z1 = -10, 10, -6, 6
	SK.Box(s, x0 - 0.5, x1 + 0.5, 0, 0.75, z0 - 0.5, z1 + 0.5, "Found")
	SK.Box(s, x0, x1, 0.75, 11.0, z0, z1, "VillaWall")
	SK.Box(s, x0 - 0.25, x1 + 0.25, 5.75, 6.25, z0 - 0.25, z1 + 0.25, "VillaTrim")
	SK.Box(s, x0 - 0.5, x1 + 0.5, 10.75, 11.25, z0 - 0.5, z1 + 0.5, "VillaTrim")
	for _, x in ipairs({ x0, x1 - 0.5 }) do
		SK.Box(s, x, x + 0.5, 0.75, 11.0, z0 - 0.5, z0, "VillaTrim")
	end
	-- portico: columns, the balcony slab with a railing, the door
	SK.Box(s, -3.5, 3.5, 0, 0.75, z0 - 3.5, z0, "Found")
	for _, x in ipairs({ -3.0, 2.5 }) do
		SK.Box(s, x, x + 0.5, 0.75, 6.0, z0 - 3.0, z0 - 2.5, "Marble")
	end
	SK.Box(s, -3.5, 3.5, 6.0, 6.5, z0 - 3.5, z0, "VillaTrim")
	SK.Box(s, -3.5, 3.5, 6.5, 7.75, z0 - 3.5, z0 - 3.0, "Rail")
	SK.Box(s, -1.25, 1.25, 0.75, 4.5, z0 - 0.5, z0, "Door")
	SK.Box(s, -1.5, 1.5, 4.5, 5.0, z0 - 0.5, z0, "VillaTrim")
	-- tall windows, two rows
	for _, x in ipairs({ -7.5, -5.0, 5.0, 7.5 }) do
		windowZ(s, x, 2.0, z0, 1.5, 2.5, "Window", "VillaTrim")
		windowZ(s, x, 7.5, z0, 1.5, 2.5, "Window", "VillaTrim")
	end
	windowZ(s, 0, 7.5, z0, 2.0, 2.5, "Window", "VillaTrim")
	-- terracotta hip roof in two tones, chimneys, potted bushes
	local top = SK.Hip(s, x0 - 1.0, x1 + 1.0, z0 - 1.0, z1 + 1.0, 11.25, 0.75, "Terracotta", "RoofTop", "Terracotta2")
	for _, x in ipairs({ -6.5, 6.0 }) do
		SK.Box(s, x, x + 1.5, 11.0, top + 1.0, 1.0, 2.5, "Chimney")
	end
	for _, x in ipairs({ -5.5, 5.5 }) do
		SK.Box(s, x - 0.5, x + 0.5, 0.75, 1.5, z0 - 2.0, z0 - 1.0, "Terracotta")
		SK.Oct(s, x, z0 - 1.5, 0.75, 1.5, 3.0, "Bush")
	end
	return top
end

local function houseManor(s)
	-- a manor: a three-storey centre block with a pediment and two lower wings, slate roofs, chimneys
	local cx0, cx1, z0, z1 = -6, 6, -7, 7
	SK.Box(s, -12.5, 12.5, 0, 1.0, z0 - 0.5, z1 + 0.5, "Found")
	for _, sx in ipairs({ -1, 1 }) do
		local wx0, wx1 = (sx < 0) and -12 or 6, (sx < 0) and -6 or 12
		SK.Box(s, wx0, wx1, 1.0, 10.0, z0 + 1, z1, "ManorWall")
		SK.Box(s, wx0 - 0.25, wx1 + 0.25, 9.75, 10.25, z0 + 0.75, z1 + 0.25, "ManorTrim")
		SK.Hip(s, wx0 - 0.5, wx1 + 0.5, z0 + 0.5, z1 + 0.5, 10.25, 0.75, "Slate", "SlateTop", "Slate2")
		for _, x in ipairs({ wx0 + 1.75, wx1 - 1.75 }) do
			windowZ(s, x, 2.5, z0 + 1, 1.5, 2.5, "Window", "ManorTrim")
			windowZ(s, x, 6.5, z0 + 1, 1.5, 2.5, "Window", "ManorTrim")
		end
	end
	SK.Box(s, cx0, cx1, 1.0, 15.0, z0, z1, "ManorWall")
	SK.Box(s, cx0 - 0.25, cx1 + 0.25, 14.75, 15.25, z0 - 0.25, z1 + 0.25, "ManorTrim")
	for _, x in ipairs({ cx0, -2.5, 2.0, cx1 - 0.5 }) do
		SK.Box(s, x, x + 0.5, 1.0, 15.0, z0 - 0.5, z0, "ManorTrim")
	end
	-- pediment over the centre front with a round window, the slate roof behind it
	SK.Gable(s, cx0 - 0.5, cx1 + 0.5, z0 - 0.5, z0 + 1.0, 15.25, 0.5, "ManorTrim", "Z")
	SK.DiscZ(s, 0, 16.75, z0 - 1.0, z0 - 0.5, 0.8, "Window")
	local top = SK.Hip(s, cx0 - 0.5, cx1 + 0.5, z0 + 1.0, z1 + 0.5, 15.25, 0.75, "Slate", "SlateTop", "Slate2")
	-- grand door with steps, lanterns, windows
	SK.Box(s, -2.5, 2.5, 0, 1.0, z0 - 2.0, z0, "Marble")
	SK.Box(s, -2.0, 2.0, 0, 0.5, z0 - 2.5, z0 - 2.0, "Marble")
	SK.Box(s, -1.25, 1.25, 1.0, 5.0, z0 - 0.5, z0, "Door")
	SK.Box(s, -1.75, 1.75, 5.0, 5.5, z0 - 1.0, z0, "Gold")
	for _, x in ipairs({ -4.25, 4.25 }) do
		windowZ(s, x, 2.5, z0, 1.5, 2.5, "Window", "ManorTrim")
	end
	for _, x in ipairs({ -4.25, 0, 4.25 }) do
		windowZ(s, x, 6.75, z0, 1.5, 2.5, "Window", "ManorTrim")
		windowZ(s, x, 10.75, z0, 1.5, 2.5, "Window", "ManorTrim")
	end
	for _, x in ipairs({ -10.5, 9.5 }) do
		SK.Box(s, x, x + 1.0, 10.0, 15.0, 2.0, 3.5, "Chimney")
	end
	for _, x in ipairs({ -3.25, 2.75 }) do
		SK.Box(s, x, x + 0.5, 2.5, 3.5, z0 - 1.0, z0 - 0.5, "Lamp")
	end
	-- topiary cones flanking the steps
	for _, x in ipairs({ -4.0, 4.0 }) do
		SK.Spire(s, x, z0 - 2.0, 1.0, 0, 3.0, "Bush", "Bush2", 1.0)
	end
	return top
end

local function houseCastle(s)
	-- the Sky Castle: a keep with crenellations, four round towers with stepped blue spires, a gold gate,
	-- banners and soft cloud puffs around the base
	local x0, x1, z0, z1 = -9, 9, -6, 7
	-- it floats on its own cloud: a soft two-tone cloud slab with puffs at the corners
	SK.Box(s, -13.5, 13.5, 0, 0.5, -9.5, 9.5, "CloudShade")
	SK.Box(s, -13, 13, 0.5, 1.0, -9, 9, "Cloud")
	-- cloud puffs on the slab: two in front beside the gate, one on each side between the towers
	for _, q in ipairs({ { -6.5, -9.0 }, { 6.5, -9.0 }, { -12.5, 0 }, { 12.5, 0 } }) do
		SK.Oct(s, q[1], q[2], 1.5, 1.0, 2.0, "Cloud")
		SK.Box(s, q[1] - 0.5, q[1] + 0.5, 2.0, 2.5, q[2] - 0.5, q[2] + 0.5, "CloudLight")
	end
	-- curtain walls between the towers, crenellated at the front
	SK.Box(s, -10, 10, 1.0, 9.0, -8, -6.5, "Castle")
	SK.Box(s, -10, 10, 1.0, 9.0, 7, 8.5, "Castle")
	for x = -7.5, 7.0, 2.5 do
		if abs(x + 0.5) > 3 then
			SK.Box(s, x, x + 1, 9.0, 10.0, -8, -7, "Castle")
		end
	end
	-- the keep: a cornice and merlons along the front
	SK.Box(s, x0, x1, 1.0, 16.0, z0, z1, "Castle")
	SK.Box(s, x0 - 0.5, x1 + 0.5, 15.5, 16.5, z0 - 0.5, z1 + 0.5, "CastleShade")
	for x = x0 - 0.5, x1 - 0.5, 2 do
		SK.Box(s, x, x + 1, 16.5, 17.5, z0 - 0.5, z0 + 0.5, "Castle")
	end
	-- the central tower and its spire with a pennant
	SK.Box(s, -3, 3, 16.0, 21.0, -2, 4, "Tower")
	SK.Box(s, -3.5, 3.5, 20.5, 21.0, -2.5, 4.5, "CastleShade")
	local tip = SK.Spire(s, 0, 1, 4.0, 21.0, 28.0, "Spire", "Spire2", 1.0)
	SK.Box(s, -0.5, 0.5, tip, tip + 2.0, 0.5, 1.5, "Gold")
	SK.Box(s, 0.5, 2.5, tip + 1.0, tip + 2.0, 0.5, 1.5, "Banner")
	windowZ(s, 0, 17.5, -2, 1.5, 2.0, "WarmWindow", "Gold")
	-- four round towers with spires, finials and pennants
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local tx, tz = sx * 10.5, sz * 6.5
			SK.Oct(s, tx, tz, 2.75, 1.0, 13.5, "Tower")
			local top = SK.Spire(s, tx, tz, 3.5, 13.5, 21.5, "Spire", "Spire2", 2.0)
			SK.Box(s, tx - 0.5, tx + 0.5, top, top + 1.5, tz - 0.5, tz + 0.5, "Gold")
			SK.Box(s, tx + sx * 0.5, tx + sx * 2.0, top + 0.5, top + 1.5, tz - 0.5, tz + 0.5, "Banner")
			if sz < 0 then
				windowZ(s, tx, 8.5, tz - 2.75, 1.0, 1.5, "WarmWindow", "CastleShade")
			end
		end
	end
	-- the gate: a gold door under an arch, banners and lit windows on the keep
	SK.Box(s, -2.5, 2.5, 1.0, 7.0, -8.5, -8, "CastleShade")
	SK.Box(s, -2.0, 2.0, 1.0, 6.0, -9, -8.5, "Door")
	SK.Box(s, -1.5, 1.5, 6.0, 6.5, -9, -8.5, "Door")
	SK.Box(s, -2.0, 2.0, 3.0, 3.5, -9.5, -9, "Gold")
	SK.Box(s, -0.25, 0.25, 1.0, 6.0, -9.5, -9, "Gold")
	for _, x in ipairs({ -6.0, 5.0 }) do
		SK.Box(s, x, x + 1.0, 4.0, 8.5, -8.5, -8.0, "Banner")
		windowZ(s, x + 0.5, 11.0, z0, 1.5, 2.5, "WarmWindow", "Gold")
	end
	-- a gold-framed rose window over the gate (the facade's centrepiece) and a gold band under the cornice
	SK.DiscZ(s, 0, 12.0, z0 - 0.5, z0, 2.25, "Gold")
	SK.DiscZ(s, 0, 12.0, z0 - 1.0, z0 - 0.5, 1.75, "WarmWindow")
	SK.Box(s, -0.25, 0.25, 10.5, 13.5, z0 - 1.5, z0 - 1.0, "Gold")
	SK.Box(s, -1.5, 1.5, 11.75, 12.25, z0 - 1.5, z0 - 1.0, "Gold")
	SK.Box(s, x0, x1, 14.5, 15.0, z0 - 0.5, z0, "Gold")
	return 29
end

function Art.House(def, level)
	local tpl = newTemplate("House")
	local s = SK.New(0.5)
	local tierFn = ({ houseCottage, houseVilla, houseManor, houseCastle })[level] or houseCottage
	tierFn(s)
	local m = SK.Build(s, HOUSE_PAL, { Name = "Body", Collide = "big" })
	absorb(tpl.Model, m)
	if level >= 4 then
		local spire = biggestPart(tpl.Model, "Spire")
		if spire then
			local att = Instance.new("Attachment")
			att.Name = "Sparkle"
			att.Parent = spire
			emitter(att, { Color = ColorSequence.new(C.TextGold), Rate = 2, SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(1.5, 2.5) })
		end
	end
	return tpl
end

----------------------------------------------------------------------
-- Fusion Machine: two input pods, a swirling cloud chamber and an output pod. Front -Z.
-- A round two-step dais (an indigo foot, a violet deck with a gold rim at level 3, a lit front step). Left a cyan pod,
-- right a magenta pod: a round pedestal, a tinted glass capsule (one clean part) with a floating neon gem, a wider lid
-- with a beacon, and a curved pipe arching from the lid into the chamber. In the middle the tall glass chamber on a
-- round pedestal with a breathing neon seam, four ribs (gold at 3), the crown ring, a stepped dome and the fusion
-- crystal on top (tesla prongs from level 2); inside, puffy clouds and a glowing heart swirl (the Swirl model HomeFx
-- spins). In front the output pod (a lit pedestal under a small golden glass dome, where the FusionPrompt rides),
-- fed by two neon trails on the deck from the input pods. Level 3 adds crystal shards and rainbow gems around the
-- dais. Parts named "Glow" (neon) breathe on the client.
----------------------------------------------------------------------
function Art.Fusion(def, level)
	local tpl = newTemplate("FusionMachine")
	local s = SK.New(0.5)
	local gold = level >= 2
	local trim = gold and "Gold" or "Trim"
	local cz = 1.0 -- the chamber's and the pods' centre line (local z); every coordinate sits on the 0.5 grid
	-- the dais: an indigo foot, a violet deck (a gold rim at 3) and a lit step toward the output pod
	SK.Oct(s, 0, 0.5, 5.0, 0, 0.5, "Base")
	SK.Oct(s, 0, 0.5, 4.5, 0.5, 1.0, (level >= 3) and "Gold" or "Deck")
	SK.Oct(s, 0, 0.5, 4.0, 0.5, 1.0, "Deck")
	SK.Box(s, -1.5, 1.5, 0, 0.5, -5.5, -4.5, "Base")
	SK.Box(s, -1.0, 1.0, 0, 0.5, -5.5, -4.5, "Walk")
	-- the two input pods (left = cyan, right = magenta): a round pedestal, the glass capsule (one part, below) and a
	-- wider lid with a beacon; a curved pipe arches from the lid into the chamber
	for _, sx in ipairs({ -1, 1 }) do
		local px = sx * 3.5
		local glowKey = (sx < 0) and "GlowA" or "GlowB"
		SK.Oct(s, px, cz, 1.5, 1.0, 1.5, "Metal")
		SK.Oct(s, px, cz, 1.0, 1.5, 2.0, trim)
		SK.Oct(s, px, cz, 1.5, 5.0, 5.5, trim)
		SK.Oct(s, px, cz, 1.0, 5.5, 6.0, "Metal")
		-- the pipe leaves the lid on its inner side (the beacon on top stays clear) and arches into the chamber
		SK.Curve(s, {
			{ px - sx * 0.75, 5.75, cz },
			{ px - sx * 1.0, 7.5, cz },
			{ sx * 2.25, 8.25, cz },
			{ sx * 1.75, 8.25, cz },
		}, 0.4, 0.4, "Pipe")
		SK.Box(s, px - 0.5, px + 0.5, 6.0, 6.5, cz - 0.5, cz + 0.5, glowKey)
	end
	-- the chamber: a round pedestal, a gold or lavender trim, the neon seam, four ribs, the crown ring and a stepped
	-- dome with the fusion crystal's holder
	SK.Oct(s, 0, cz, 2.5, 1.0, 2.0, "Metal")
	SK.Oct(s, 0, cz, 3.0, 2.0, 2.5, trim)
	SK.Oct(s, 0, cz, 2.5, 2.5, 3.0, "Glow")
	for _, a in ipairs({ -1, 1 }) do
		for _, b in ipairs({ -1, 1 }) do
			local rx = (a < 0) and -2.5 or 2.0
			local rz = cz + ((b < 0) and -2.5 or 2.0)
			SK.Box(s, rx, rx + 0.5, 3.0, 9.0, rz, rz + 0.5, (level >= 3) and "Gold" or "Rib")
		end
	end
	SK.Oct(s, 0, cz, 3.0, 9.0, 9.5, trim)
	SK.Oct(s, 0, cz, 2.5, 9.5, 10.0, "Dome")
	SK.Oct(s, 0, cz, 2.0, 10.0, 10.5, "DomeLight")
	SK.Oct(s, 0, cz, 1.5, 10.5, 11.0, "Dome")
	SK.Oct(s, 0, cz, 1.0, 11.0, 11.5, trim)
	SK.Box(s, -0.5, 0.5, 11.5, 12.0, cz - 0.5, cz + 0.5, "Metal")
	if level >= 2 then
		-- tesla prongs on the dome with glowing tips
		for _, sx in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and -2.0 or 1.5
			SK.Box(s, x0, x0 + 0.5, 10.0, 12.0, cz - 0.25, cz + 0.25, "Rib")
			SK.Box(s, x0, x0 + 0.5, 12.0, 12.5, cz - 0.25, cz + 0.25, "Glow")
		end
	end
	if level >= 3 then
		-- crystal shards and rainbow gems around the dais
		for i, q in ipairs({ { -4.0, -2.5 }, { 3.5, -2.5 }, { -2.5, 4.0 }, { 2.0, 4.0 } }) do
			SK.Box(s, q[1], q[1] + 0.5, 1.0, 1.5, q[2], q[2] + 0.5, "Gem" .. i)
		end
	end
	-- the output pod in front: a round pedestal with a glowing ring (the glass dome is a separate part)
	SK.Oct(s, 0, -3.0, 1.5, 1.0, 1.5, "Metal")
	SK.Oct(s, 0, -3.0, 1.0, 1.5, 2.0, "Glow")
	local pal = mergeTables(P, {
		Base = rgb(56, 50, 112),
		Deck = rgb(120, 102, 198),
		Walk = { Color = rgb(150, 210, 255), Material = MAT.Neon },
		Metal = rgb(222, 224, 246),
		Trim = rgb(176, 160, 236),
		Rib = rgb(84, 72, 160),
		Dome = rgb(150, 116, 226),
		DomeLight = rgb(186, 160, 246),
		Glow = { Color = rgb(206, 156, 255), Material = MAT.Neon },
		GlowA = { Color = rgb(110, 228, 255), Material = MAT.Neon },
		GlowB = { Color = rgb(255, 128, 222), Material = MAT.Neon },
		Pipe = rgb(132, 96, 214),
		Gem1 = { Color = rgb(255, 120, 140), Material = MAT.Neon },
		Gem2 = { Color = rgb(255, 214, 110), Material = MAT.Neon },
		Gem3 = { Color = rgb(120, 236, 160), Material = MAT.Neon },
		Gem4 = { Color = rgb(130, 170, 255), Material = MAT.Neon },
	})
	SK.Shade(s, { Only = { Metal = true, Deck = true, Pipe = true }, Smooth = 2, Seed = 7 })
	local m = SK.Build(s, pal, { Name = "Body", Collide = "big", MaxParts = 66 })
	absorb(tpl.Model, m)
	-- glass (one clean part each, so nothing inside splits it), the pods' floating gems and the fusion crystal
	for _, sx in ipairs({ -1, 1 }) do
		local px = sx * 3.5
		local tint = (sx < 0) and rgb(168, 236, 255) or rgb(255, 194, 238)
		box(tpl.Model, "PodGlass", CFrame.new(px, 3.5, cz), Vector3.new(2.0, 3.0, 2.0), tint, { Material = MAT.Glass, Transparency = 0.45, Shadow = false })
		box(tpl.Model, "Glow", CFrame.new(px, 3.5, cz) * CFrame.Angles(math.rad(35), math.rad(45), 0), Vector3.new(0.8, 0.8, 0.8),
			(sx < 0) and rgb(110, 228, 255) or rgb(255, 128, 222), { Material = MAT.Neon, Shadow = false })
	end
	box(tpl.Model, "Chamber", CFrame.new(0, 6.0, cz), Vector3.new(4.0, 6.0, 4.0), rgb(222, 212, 255), { Material = MAT.Glass, Transparency = 0.6, Shadow = false })
	-- two neon trails on the deck from the input pods to the output pod (what goes in comes out in front)
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = Vector3.new(sx * 2.7, 1.03, -0.3), Vector3.new(sx * 1.25, 1.03, -2.4)
		box(tpl.Model, "Glow", CFrame.lookAt((a + b) / 2, b), Vector3.new(0.35, 0.06, (b - a).Magnitude), (sx < 0) and rgb(110, 228, 255) or rgb(255, 128, 222),
			{ Material = MAT.Neon, Shadow = false })
	end
	box(tpl.Model, "PodGlass", CFrame.new(0, 2.65, -3.0), Vector3.new(1.8, 1.3, 1.8), rgb(255, 238, 196), { Material = MAT.Glass, Transparency = 0.45, Shadow = false })
	local crystalColor = (level >= 3) and rgb(255, 214, 120) or rgb(150, 230, 255)
	box(tpl.Model, "Crystal", CFrame.new(0, 12.9, cz) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.9, 1.6, 0.9), crystalColor, { Material = MAT.Neon, Shadow = false })
	box(tpl.Model, "Crystal", CFrame.new(0, 12.9, cz) * CFrame.Angles(0, math.rad(45), math.rad(45)) * CFrame.Angles(math.rad(45), 0, 0), Vector3.new(0.7, 0.7, 0.7), crystalColor,
		{ Material = MAT.Neon, Shadow = false })
	if level >= 3 then
		-- crystal shards on the dais's back corners
		for _, sx in ipairs({ -1, 1 }) do
			box(tpl.Model, "Crystal", CFrame.new(sx * 3.6, 1.9, 4.0) * CFrame.Angles(0, math.rad(45), math.rad(sx * 12)), Vector3.new(0.7, 1.8, 0.7), rgb(150, 230, 255), { Material = MAT.Neon, Shadow = false })
		end
	end
	-- the swirl: three puffy clouds on a rising spiral around a glowing heart; HomeFx spins it inside the chamber
	local w = SK.New(0.5)
	SK.Box(w, 0.0, 1.5, 3.5, 4.5, cz - 0.5, cz + 1.0, "Cloud")
	SK.Box(w, 0.5, 1.0, 4.5, 5.0, cz, cz + 0.5, "CloudLight")
	SK.Box(w, -1.5, 0.0, 5.5, 6.5, cz - 1.0, cz + 0.5, "Cloud")
	SK.Box(w, -1.0, -0.5, 6.5, 7.0, cz - 0.5, cz, "CloudLight")
	SK.Box(w, 0.0, 1.5, 7.5, 8.5, cz - 1.0, cz + 0.5, "SwirlB")
	SK.Box(w, -0.5, 0.5, 4.5, 7.5, cz - 0.5, cz + 0.5, "SwirlC")
	local swirl = SK.Build(w, mergeTables(P, {
		CloudLight = rgb(252, 253, 255),
		SwirlB = rgb(226, 210, 255),
		SwirlC = { Color = (level >= 3) and rgb(255, 230, 160) or rgb(214, 176, 255), Material = MAT.Neon, Transparency = 0.15 },
	}), { Name = "Swirl" })
	swirl.Parent = tpl.Model
	tpl.Points.SwirlCenter = Vector3.new(0, 6.0, cz)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FusionPrompt"
	prompt.ActionText = "Fuse"
	prompt.ObjectText = "Fusion Machine"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("StationId", "FusionMachine")
	local deck = biggestPart(tpl.Model, "Deck") or biggestPart(tpl.Model)
	if deck then
		local att = Instance.new("Attachment")
		att.Name = "PromptPoint"
		att.CFrame = deck.CFrame:Inverse() * CFrame.new(0, 2.5, -3.0)
		att.Parent = deck
		prompt.Parent = att
		local light = Instance.new("Attachment")
		light.Name = "ChamberLight"
		light.CFrame = deck.CFrame:Inverse() * CFrame.new(0, 6, cz)
		light.Parent = deck
		pointLight(light, rgb(186, 120, 255), 1.2, 16)
		if level >= 3 then
			emitter(light, { Color = ColorSequence.new(rgb(214, 180, 255), C.TextGold), Rate = 4, SpreadAngle = Vector2.new(180, 180) })
		end
	end
	return tpl
end

----------------------------------------------------------------------
-- Arena Gate: a stone arch with crossed swords and a portal surface. Front -Z.
----------------------------------------------------------------------
function Art.Arena(def, level)
	local tpl = newTemplate("ArenaGate")
	local s = SK.New(0.5)
	-- a stone gate: two pillars with capitals, a lintel with a cornice and a crest, braziers on top, red banners,
	-- a red-and-gold shield over the portal (crossed swords added below) and the violet portal surface
	SK.Box(s, -3.5, 3.5, 0, 0.5, -2.0, 2.0, "StoneDark")
	for _, sx in ipairs({ -1, 1 }) do
		local x0 = (sx < 0) and -3.5 or 2.0
		SK.Box(s, x0, x0 + 1.5, 0.5, 9.0, -1.0, 1.0, "Stone")
		SK.Box(s, x0 - 0.5, x0 + 2.0, 0.5, 1.0, -1.5, 1.5, "StoneLight")
		SK.Box(s, x0 - 0.5, x0 + 2.0, 9.0, 9.5, -1.5, 1.5, "StoneLight")
		SK.Box(s, x0, x0 + 1.5, 4.0, 8.0, -1.5, -1.0, "Banner")
		SK.Box(s, x0 + 0.5, x0 + 1.0, 3.5, 4.0, -1.5, -1.0, "Banner")
		SK.Box(s, x0, x0 + 1.5, 7.5, 8.0, -1.5, -1.0, "Gold")
		local bx = (sx < 0) and -3.5 or 2.5
		SK.Box(s, bx, bx + 1.0, 11.5, 12.0, -0.5, 0.5, "Iron")
		SK.Box(s, bx, bx + 1.0, 12.0, 13.0, -0.5, 0.5, "Fire")
	end
	SK.Box(s, -3.5, 3.5, 9.5, 11.0, -1.0, 1.0, "Stone")
	SK.Box(s, -4.0, 4.0, 11.0, 11.5, -1.5, 1.5, "StoneLight")
	SK.Box(s, -1.0, 1.0, 11.5, 12.5, -0.5, 0.5, "StoneLight")
	SK.Box(s, -2.0, 2.0, 0.5, 9.5, -0.5, 0.5, "Portal")
	SK.Box(s, -1.0, 1.0, 9.0, 11.0, -1.5, -1.0, "Shield")
	SK.Box(s, -0.5, 0.5, 8.5, 9.0, -1.5, -1.0, "Shield")
	SK.Box(s, -1.0, 1.0, 10.5, 11.0, -2.0, -1.5, "Gold")
	local pal = mergeTables(P, {
		Portal = { Color = rgb(140, 96, 220), Material = MAT.Neon, Transparency = 0.45 },
		Fire = { Color = rgb(255, 170, 80), Material = MAT.Neon },
		Banner = rgb(214, 70, 74),
		Shield = rgb(196, 58, 66),
	})
	SK.Shade(s, { Only = { Stone = true }, Smooth = 2, Light = false, Seed = 19 })
	local m = SK.Build(s, pal, { Name = "Body", Collide = "big", MaxParts = 40 })
	absorb(tpl.Model, m)
	for _, p in ipairs(tpl.Model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name == "Portal" then
			p.CanCollide = false
			p.CanQuery = false
		end
	end
	-- two swords crossed in front of the shield: steel blades, gold cross-guards and grips
	for _, sx in ipairs({ -1, 1 }) do
		local cf = CFrame.new(0, 9.9, -1.75 - (sx + 1) * 0.06) * CFrame.Angles(0, 0, math.rad(sx * 40))
		box(tpl.Model, "Sword", cf * CFrame.new(0, 0.4, 0), Vector3.new(0.4, 3.6, 0.15), rgb(214, 222, 236), { Shadow = false })
		box(tpl.Model, "Hilt", cf * CFrame.new(0, -1.5, 0), Vector3.new(1.2, 0.3, 0.3), C.Gold, { Shadow = false })
		box(tpl.Model, "Hilt", cf * CFrame.new(0, -2.0, 0), Vector3.new(0.3, 0.8, 0.3), C.GoldDark, { Shadow = false })
	end
	-- Phase 3: the gate is a working teleport to the Battle Arena. ArenaBuilder handles `ArenaGatePrompt` (owner only,
	-- near the gate, refused in a match or a battle); applyOwnerAttr writes OwnerUserId and enables it while owned.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ArenaGatePrompt"
	prompt.ActionText = "Go to Arena"
	prompt.ObjectText = "Arena Gate"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("StationId", "ArenaGate")
	prompt:SetAttribute("Teleport", "Arena")
	local portal = biggestPart(tpl.Model, "Portal") or biggestPart(tpl.Model)
	if portal then
		local att = Instance.new("Attachment")
		att.Name = "PromptPoint"
		att.CFrame = portal.CFrame:Inverse() * CFrame.new(0, 3.0, -1.5)
		att.Parent = portal
		prompt.Parent = att
	end
	return tpl
end

----------------------------------------------------------------------
-- Decor
----------------------------------------------------------------------
-- lantern posts beside the main path (local z positions in the slot frame per pair count)
local LAMP_Z = { { -8.5, 7 }, { -8.5, -3, 7 }, { -8.5, -3, 7, 12 } }

local function lampPiece(style)
	local key = "LampPiece" .. style
	if templates[key] then
		return templates[key]
	end
	local tpl = newTemplate("Lamp")
	local m = tpl.Model
	if style == "Wood" then
		box(m, "Base", CFrame.new(0, 0.25, 0), Vector3.new(1, 0.5, 1), C.StoneDark, { Collide = true })
		box(m, "Post", CFrame.new(0, 2.75, 0), Vector3.new(0.5, 4.5, 0.5), C.PlankDark, { Collide = true })
		box(m, "Arm", CFrame.new(0.5, 4.85, 0), Vector3.new(1.5, 0.3, 0.3), C.PlankDark)
		box(m, "Lantern", CFrame.new(1.0, 4.0, 0), Vector3.new(0.9, 1.1, 0.9), rgb(255, 190, 110), { Material = MAT.Neon })
	elseif style == "Brass" then
		box(m, "Base", CFrame.new(0, 0.25, 0), Vector3.new(1, 0.5, 1), C.StoneDark, { Collide = true })
		box(m, "Post", CFrame.new(0, 2.6, 0), Vector3.new(0.45, 4.2, 0.45), C.Iron, { Collide = true })
		box(m, "Lantern", CFrame.new(0, 5.2, 0), Vector3.new(0.85, 1.0, 0.85), C.Lamp, { Material = MAT.Neon })
		box(m, "Cap", CFrame.new(0, 5.85, 0), Vector3.new(1.25, 0.3, 1.25), rgb(214, 170, 92))
	else
		box(m, "Base", CFrame.new(0, 0.3, 0), Vector3.new(1.2, 0.6, 1.2), C.Marble, { Collide = true })
		box(m, "Post", CFrame.new(0, 2.3, 0), Vector3.new(0.7, 3.4, 0.7), C.Marble, { Collide = true })
		box(m, "Collar", CFrame.new(0, 4.1, 0), Vector3.new(1.0, 0.25, 1.0), C.Gold)
		box(m, "Crystal", CFrame.new(0, 5.0, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35)), Vector3.new(0.8, 0.8, 0.8), C.Crystal, { Material = MAT.Neon })
	end
	templates[key] = tpl
	return tpl
end

function Art.DecorLamps(def, level)
	local tpl = newTemplate("DecorLamps")
	local eff = def.Effects and def.Effects[level] or {}
	local style = eff.Style or ({ "Wood", "Brass", "Crystal" })[level] or "Wood"
	local pieces = eff.Pieces or (2 + level * 2)
	local piece = lampPiece(style)
	local zs = LAMP_Z[min(#LAMP_Z, max(1, floor(pieces / 2) - 1))] or LAMP_Z[1]
	local n = 0
	for _, z in ipairs(zs) do
		for _, sx in ipairs({ -1, 1 }) do
			if n < pieces then
				n = n + 1
				-- lanterns lean toward the path (their arm points at x = 0)
				local cf = CFrame.new(sx * 4.25, 0, z) * CFrame.Angles(0, (sx > 0) and math.pi or 0, 0)
				absorb(tpl.Model, cloneAt(piece, cf))
			end
		end
	end
	return tpl
end

-- the fence follows the yard's edge (Perimeter): built in the PLOT frame (the slot is the yard centre)
function Art.DecorFence(def, level, plotSize)
	local tpl = newTemplate("DecorFence")
	local half = (plotSize or 72) / 2
	local edge = half - 0.6
	local gate = 8.6
	local eff = def.Effects and def.Effects[level] or {}
	local style = eff.Style or ({ "Picket", "Hedge", "Cloudstone" })[level] or "Picket"
	-- runs { x0, z0, x1, z1 } along the edge, the front split at the gate
	local runs = {
		{ -edge, edge, edge, edge },
		{ -edge, -edge, -edge, edge },
		{ edge, -edge, edge, edge },
		{ -edge, -edge, -gate, -edge },
		{ gate, -edge, edge, -edge },
	}
	local function seg(name, r, y0, y1, thick, color, opts)
		local dx, dz = r[3] - r[1], r[4] - r[2]
		local len = math.sqrt(dx * dx + dz * dz)
		local mid = Vector3.new((r[1] + r[3]) / 2, (y0 + y1) / 2, (r[2] + r[4]) / 2)
		local size = (abs(dx) > abs(dz)) and Vector3.new(len + thick, y1 - y0, thick) or Vector3.new(thick, y1 - y0, len + thick)
		return box(tpl.Model, name, CFrame.new(mid), size, color, opts)
	end
	-- calls fn(x, z, run) for evenly spaced points along the runs; a corner shared by two runs comes once
	local function posts(every, fn, frontOnly)
		local seen = {}
		for i, r in ipairs(runs) do
			if not frontOnly or i >= 4 then
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
	end
	local white = rgb(248, 246, 240)
	if style == "Picket" then
		-- white rails all round, pickets along the street side, posts every 12 studs elsewhere
		for _, r in ipairs(runs) do
			seg("Rail", r, 0.9, 1.25, 0.3, white, { Collide = true })
			seg("Rail", r, 2.0, 2.35, 0.3, white)
		end
		posts(2.5, function(x, z)
			box(tpl.Model, "Picket", CFrame.new(x, 1.45, z), Vector3.new(0.7, 2.9, 0.4), white, { Collide = true })
		end, true)
		posts(18, function(x, z, i)
			if i <= 3 then
				box(tpl.Model, "Post", CFrame.new(x, 1.6, z), Vector3.new(0.7, 3.2, 0.7), white, { Collide = true })
			end
		end)
	elseif style == "Hedge" then
		for _, r in ipairs(runs) do
			seg("Hedge", r, 0, 2.4, 1.4, C.Hedge, { Collide = true })
			seg("HedgeTop", r, 2.4, 2.8, 1.0, rgb(104, 176, 92))
			seg("Blooms", r, 1.5, 1.9, 1.5, rgb(246, 170, 196))
		end
		posts(18, function(x, z)
			box(tpl.Model, "Topiary", CFrame.new(x, 3.4, z), Vector3.new(1.6, 2.0, 1.6), rgb(98, 172, 90))
		end)
	else
		for _, r in ipairs(runs) do
			seg("Wall", r, 0, 1.8, 1.0, rgb(222, 218, 210), { Collide = true })
			seg("WallCap", r, 1.8, 2.2, 1.3, rgb(244, 242, 236))
			seg("Hedge", r, 0, 1.0, 1.8, C.Hedge)
		end
		posts(24, function(x, z)
			box(tpl.Model, "Pillar", CFrame.new(x, 1.6, z), Vector3.new(1.6, 3.2, 1.6), rgb(232, 230, 224), { Collide = true })
			box(tpl.Model, "Puff", CFrame.new(x, 3.55, z), Vector3.new(2.0, 0.9, 2.0), C.Cloud)
		end)
		for _, sx in ipairs({ -1, 1 }) do
			box(tpl.Model, "Lantern", CFrame.new(sx * gate, 4.75, -edge), Vector3.new(0.8, 0.9, 0.8), C.Lamp, { Material = MAT.Neon })
		end
	end
	return tpl
end

local FLOWER_STYLE = {
	Tulips = { rgb(236, 96, 104), rgb(250, 210, 90), rgb(246, 150, 188) },
	Roses = { rgb(214, 60, 84), rgb(246, 150, 188), rgb(250, 244, 246) },
	Starflowers = { rgb(196, 156, 255), rgb(140, 226, 255), rgb(255, 222, 140) },
}

function Art.DecorFlowers(def, level)
	local tpl = newTemplate("DecorFlowers")
	local eff = def.Effects and def.Effects[level] or {}
	local style = eff.Style or ({ "Tulips", "Roses", "Starflowers" })[level] or "Tulips"
	local pieces = eff.Pieces or (1 + level * 2)
	local colors = FLOWER_STYLE[style] or FLOWER_STYLE.Tulips
	local glow = style == "Starflowers"
	local fp = (def.Slot and def.Slot.Footprint) or Vector3.new(18, 2, 2.2)
	local len = fp.X - 0.5
	-- one long planter (front -Z faces the yard), soil, then flower clusters: a leafy mound and three blooms
	-- (the planter stands 0.6 stud in from the slot centre, clear of every fence style along the edge)
	local pz = -0.6
	box(tpl.Model, "Planter", CFrame.new(0, 0.35, pz), Vector3.new(len, 0.7, 1.8), C.PlankDark, { Collide = true })
	box(tpl.Model, "PlanterRim", CFrame.new(0, 0.75, pz), Vector3.new(len + 0.2, 0.15, 2.0), C.Plank)
	box(tpl.Model, "Soil", CFrame.new(0, 0.78, pz), Vector3.new(len - 0.4, 0.12, 1.4), C.Soil)
	for i = 1, pieces do
		local x = -len / 2 + (i - 0.5) * len / pieces
		box(tpl.Model, "Leaves", CFrame.new(x, 1.15, pz), Vector3.new(2.0, 0.7, 1.3), (i % 2 == 0) and C.Leaf or C.LeafDark, { Shadow = false })
		for k = 1, 3 do
			local c = colors[((i + k) % #colors) + 1]
			local bx = x + (k - 2) * 0.65
			local by = 1.85 + ((k == 2) and 0.35 or 0)
			box(tpl.Model, "Bloom", CFrame.new(bx, by, pz + ((k % 2 == 0) and 0.15 or -0.15)), Vector3.new(0.65, 0.8, 0.65), c,
				{ Shadow = false, Material = glow and MAT.Neon or MAT.SmoothPlastic })
		end
	end
	return tpl
end

function Art.DecorFountain(def, level)
	local tpl = newTemplate("DecorFountain")
	local s = SK.New(0.5)
	-- an octagonal basin with water, a centre column; bowls stack up with the level, a cloud on top at 3
	-- (radius 4: the basin stays inside the ring of stone paths around it)
	SK.Oct(s, 0, 0, 4.0, 0, 0.5, "StoneDark")
	SK.Oct(s, 0, 0, 3.5, 0.5, 1.5, "Stone")
	SK.Oct(s, 0, 0, 3.0, 1.0, 1.5, "Pool")
	SK.Oct(s, 0, 0, 0.75, 1.25, 3.0, "StoneLight")
	local top = 3.0
	if level >= 2 then
		SK.Oct(s, 0, 0, 2.0, 3.0, 3.5, "Stone")
		SK.Oct(s, 0, 0, 1.5, 3.5, 3.75, "Pool")
		SK.Oct(s, 0, 0, 0.5, 3.75, 5.5, "StoneLight")
		top = 5.5
	end
	if level >= 3 then
		SK.Oct(s, 0, 0, 1.0, 5.5, 6.0, "Gold")
		puffCloud(s, 0, 6.0, 0, 1.5, 3)
		SK.Box(s, -0.25, 0.25, 8.25, 8.75, -0.25, 0.25, "Crystal")
		top = 8.5
	else
		SK.Oct(s, 0, 0, 0.5, top, top + 0.75, "Gold")
	end
	local pal = mergeTables(P, { CloudShade = rgb(212, 222, 244), CloudLight = rgb(252, 253, 255), Pool = { Color = rgb(96, 182, 238), Reflectance = 0.1 } })
	local m = SK.Build(s, pal, { Name = "Body", Collide = "big" })
	absorb(tpl.Model, m)
	local col = biggestPart(tpl.Model, "StoneDark") or biggestPart(tpl.Model)
	if col then
		local att = Instance.new("Attachment")
		att.Name = "Splash"
		att.CFrame = col.CFrame:Inverse() * CFrame.new(0, top + 0.6, 0)
		att.Parent = col
		emitter(att, {
			Color = ColorSequence.new(rgb(200, 236, 255)),
			LightEmission = 0.2,
			Rate = 10 + level * 4,
			Lifetime = NumberRange.new(0.8, 1.3),
			Speed = NumberRange.new(4, 6),
			SpreadAngle = Vector2.new(18, 18),
			Acceleration = Vector3.new(0, -14, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.15) }),
		})
	end
	return tpl
end

function Art.DecorBanners(def, level, plotSize, accent)
	local tpl = newTemplate("DecorBanners")
	local eff = def.Effects and def.Effects[level] or {}
	local style = eff.Style or ({ "Cloth", "Gold", "Royal" })[level] or "Cloth"
	local pieces = eff.Pieces or (level * 2)
	local fp = (def.Slot and def.Slot.Footprint) or Vector3.new(18, 6, 2.2)
	local len = fp.X - 1
	local cloth = (style == "Royal") and rgb(118, 82, 196) or (accent or C.Rose)
	for i = 1, pieces do
		local x = -len / 2 + (i - 0.5) * len / pieces
		local cf = CFrame.new(x, 0, -0.2)
		box(tpl.Model, "Pole", cf * CFrame.new(0, 3.5, 0), Vector3.new(0.45, 7.0, 0.45), C.Iron, { Collide = true })
		box(tpl.Model, "Finial", cf * CFrame.new(0, 7.3, 0), Vector3.new(0.7, 0.7, 0.7), C.Gold)
		box(tpl.Model, "Bar", cf * CFrame.new(0, 6.6, -0.3), Vector3.new(2.6, 0.3, 0.3), (style == "Cloth") and C.Iron or C.Gold)
		box(tpl.Model, "Cloth", cf * CFrame.new(0, 4.9, -0.35), Vector3.new(2.2, 3.2, 0.14), cloth, { Shadow = false })
		if style == "Cloth" then
			box(tpl.Model, "ClothTip", cf * CFrame.new(0, 3.05, -0.35), Vector3.new(1.1, 0.5, 0.14), cloth, { Shadow = false })
		else
			box(tpl.Model, "Emblem", cf * CFrame.new(0, 5.0, -0.44) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.9, 0.9, 0.1), (style == "Royal") and C.Gold or C.Cloud, { Shadow = false })
		end
	end
	return tpl
end

function Art.DecorPodium(def, level)
	local tpl = newTemplate("DecorPodium")
	local s = SK.New(0.5)
	-- a stage around the lobby's own podium (6 x 6 base, 5.2 top, 3 tall; the best pet stands on it): a wide step,
	-- a raised ring around the podium's foot (its middle left open, so no face is shared with the podium), and corner
	-- posts that change with the level: stone lanterns (1), marble pillars with gold caps (2), crystal pillars (3)
	SK.Box(s, -4, 4, 0, 0.5, -4, 4, "StoneLight")
	SK.Box(s, -3.5, 3.5, 0.5, 1.0, -3.5, 3.5, "Stone")
	SK.Box(s, -3.0, 3.0, 0.5, 1.0, -3.0, 3.0, nil)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x0 = (sx < 0) and -4.0 or 3.0
			local z0 = (sz < 0) and -4.0 or 3.0
			if level == 1 then
				SK.Box(s, x0, x0 + 1.0, 1.0, 2.5, z0, z0 + 1.0, "Stone")
				SK.Box(s, x0, x0 + 1.0, 2.5, 3.0, z0, z0 + 1.0, "Lamp")
				SK.Box(s, x0, x0 + 1.0, 3.0, 3.5, z0, z0 + 1.0, "StoneDark")
			elseif level == 2 then
				SK.Box(s, x0, x0 + 1.0, 1.0, 3.5, z0, z0 + 1.0, "Marble")
				SK.Box(s, x0, x0 + 1.0, 3.5, 4.0, z0, z0 + 1.0, "Gold")
			else
				SK.Box(s, x0, x0 + 1.0, 1.0, 2.5, z0, z0 + 1.0, "Marble")
				SK.Box(s, x0, x0 + 1.0, 2.5, 3.0, z0, z0 + 1.0, "Gold")
			end
		end
	end
	SK.Shade(s, { Only = { Stone = true }, Smooth = 1, Seed = 29 })
	local m = SK.Build(s, P, { Name = "Body", Collide = "big", MaxParts = 30 })
	absorb(tpl.Model, m)
	-- a gold collar around the podium's top block (2+), glowing crystals on the pillars (3), a red carpet toward the
	-- yard (2+)
	if level >= 2 then
		for _, sz in ipairs({ -1, 1 }) do
			box(tpl.Model, "Collar", CFrame.new(0, 2.25, sz * 2.85), Vector3.new(6.2, 0.5, 0.5), C.Gold, { Shadow = false })
			box(tpl.Model, "Collar", CFrame.new(sz * 2.85, 2.25, 0), Vector3.new(0.5, 0.5, 5.2), C.Gold, { Shadow = false })
		end
		box(tpl.Model, "Carpet", CFrame.new(0, 0.05, -5.0), Vector3.new(2.4, 0.1, 2.0), rgb(196, 58, 72), { Shadow = false })
	end
	if level >= 3 then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				box(tpl.Model, "Crystal", CFrame.new(sx * 3.5, 3.8, sz * 3.5) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.8, 1.6, 0.8), C.Crystal,
					{ Material = MAT.Neon, Shadow = false })
			end
		end
	end
	return tpl
end

----------------------------------------------------------------------
-- Template lookup
----------------------------------------------------------------------
local function fallbackTemplate(def, level)
	-- plain stand-in when the voxel kit is missing: a coloured block of the footprint
	local tpl = newTemplate(def.Id)
	local fp = (def.Slot and def.Slot.Footprint) or Vector3.new(6, 6, 6)
	local h = max(1, fp.Y * (0.5 + 0.5 * level / max(1, def.MaxLevel or 1)))
	box(tpl.Model, "Body", CFrame.new(0, h / 2, 0), Vector3.new(min(fp.X, 30), h, min(fp.Z, 30)), C.Stone, { Collide = true })
	return tpl
end

local ART_BY_KIND = {
	Plant = Art.Plant,
	Magnet = Art.Magnet,
	Garden = Art.Garden,
	FoodMachine = Art.FoodMachine,
	Training = Art.Training,
	Vault = Art.Vault,
	House = Art.House,
	Fusion = Art.Fusion,
	Arena = Art.Arena,
}

-- template for (def, level); extra = plot specifics that change the art (accent colour for banners, the Garden's open
-- place count: its cache key is Garden:<level>:<open>)
local function stationTemplate(def, level, accent, open)
	local key = def.Id .. ":" .. level
	if def.Id == "DecorBanners" and accent then
		key = key .. ":" .. accent:ToHex()
	end
	local garden = def.Kind == "Garden"
	if garden then
		open = Garden.clampOpen(open, #Garden.places(def))
		key = key .. ":" .. open
	end
	local tpl = templates[key]
	if tpl then
		return tpl
	end
	local fn = ART_BY_KIND[def.Kind] or Art[def.Id]
	local ok, result = false, nil
	if Voxel and fn then
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
				box(tpl.Model, "PathEdge", CFrame.new((x0 + x1) / 2, -0.02, (z0 + z1) / 2), Vector3.new(x1 - x0, 0.2, z1 - z0), rgb(176, 166, 152), { Collide = true, Shadow = false })
			end
		end
		local model = Voxel.Build(g, {
			VoxelSize = 1,
			Palette = { Path = rgb(214, 206, 188), PathLight = rgb(232, 226, 210), PathEdge = rgb(176, 166, 152) },
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
	box(m, "Planks", CFrame.new(-6, 0.25, 1.5) * CFrame.Angles(0, math.rad(8), 0), Vector3.new(4.5, 0.5, 1.6), C.PlankLight, deco)
	box(m, "Planks", CFrame.new(-6, 0.75, 1.6) * CFrame.Angles(0, math.rad(-6), 0), Vector3.new(4.0, 0.5, 1.4), C.Plank, deco)
	box(m, "Bricks", CFrame.new(6, 0.5, 2.5), Vector3.new(2.4, 1.0, 1.6), rgb(206, 110, 92), deco)
	box(m, "Bricks", CFrame.new(5.8, 1.25, 2.5) * CFrame.Angles(0, math.rad(10), 0), Vector3.new(1.6, 0.5, 1.2), rgb(222, 132, 108), deco)
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
