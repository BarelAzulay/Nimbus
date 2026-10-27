-- HomePortalFx (client, Phase 4): the home portal and the arrival ring (ARCHITECTURE_V3.md "Phase 4 build contract"
-- 3.10 / 6). Zero server parts: TycoonService only writes two player attributes, this client draws them.
--
--   HomePortalFx.Init()
--   HomePortalFx.Stop()            disconnects everything and removes every part it made
--   HomePortalFx.Stats() -> { Portals, Parts, Shown, Faded, Closing, Rings, RingParts, Opened, Arrivals }
--   HomePortalFx.Portal(player) -> { Model, Center, Yaw, ClosesAt, Faded, Closing, Name, Scale, Gui, Mesh } | nil   (tests / debugging)
--
-- * Config.Attr.HomePortal on a player = "x,y,z,yaw,closesAt" while their portal is open (x, y, z: the point on the
--   floor; yaw in degrees, CFrame.Angles(0, rad(yaw), 0).LookVector = the owner's facing when they opened it;
--   closesAt: workspace:GetServerTimeNow() when it closes, 10 s after opening). Every player's portal is drawn while it
--   is within K.DRAW_RANGE studs of the camera, facing back toward the owner: a small homestead gate (the Blender mesh
--   gate_homeportal via MeshLibrary.Assemble, or its Part copy while the key is not usable here: coursed stone pillars,
--   an oak arch, a keystone plate in the player's colour) around a vortex in the player's colour: the Gate Court gates'
--   own vortex (client/PortalVortex: 6 broad + 9 fine Beam spiral arms turning inward at two speeds, light streaks
--   pulled to the centre, rim crackles; the textured layers once shared/TextureIds has them) in front of a deep Neon
--   backdrop filling the 4 x 7 stud opening, a lighter well and a bright core (<= 40 parts in all), sparkles, and a 22 px name tag
--   "Alex's portal" (pixel-sized BillboardGui with a stroke and a backing plate, World text rule). Other players'
--   portals are faded (only the owner and their pets can go through). It grows in when it opens and shrinks away when
--   the attribute is cleared (used) or closesAt passes (expired).
-- * Config.Attr.PortalArrived = server time of the last arrival: the arrival ring (<= 20 parts: a flat ring that
--   widens and fades around the player's feet + rising sparks) plays for 1.5 s where that player stands now.
-- * The followers' dive into the portal is PetController's (it reads HomePortal itself).
-- Cheap: one RenderStepped connection, per-frame writes only for portals near the camera (the swirl, grow / shrink)
-- and live arrival rings; parts are pooled per portal and never collide, query or touch. Plain Lua 5.1 syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local okTheme, Theme = pcall(function()
	return require(Shared:WaitForChild("Theme"))
end)
if not okTheme or type(Theme) ~= "table" then
	Theme = nil
end

local HomePortalFx = {}

local ATTR = Config.Attr or {}
local PORTAL_ATTR = ATTR.HomePortal or "HomePortal"
local ARRIVED_ATTR = ATTR.PortalArrived or "PortalArrived"

local K = {
	DRAW_RANGE = 150, -- studs from the camera: portals farther away are not drawn
	-- the homestead gate (blender gate_homeportal; bug 2026-10-24, pitch A + the player's note): the local frame's origin
	-- is the vortex centre, CENTER_Y above the floor point; the walk-through opening is x -2..2, y 0.5..7.5 above the
	-- floor (round top: centre 5.5 up, radius 2), the stone pillars 2 studs deep (the recess the vortex sits in)
	CENTER_Y = 4.0,
	MESH_KEY = "gate_homeportal",
	TOP = 9.0, -- the gate's top above the floor (the name tag floats over it)
	OPEN_HALF = 2.0, -- half the opening's width
	ARCH_Y = 5.5, -- the arch centre above the floor (= the springing line on the caps)
	-- the vortex (fix round, review: one vortex family with the Gate Court gates): client/PortalVortex at the vortex
	-- centre, a little wider than the opening so its rim tucks behind the pillars and the arch (the swirl reads as seen
	-- THROUGH the doorway), turning faster than a 23-stud gate's (same rim speed on a smaller disc)
	VORTEX_R = 2.4,
	VORTEX_Z = -0.1, -- the vortex plane (local Z; the front is -Z): mid-recess, the pillars run -1..1
	VORTEX_SPEED = 1.6, -- x PortalVortex's speeds (arms 26, fine 48 deg/s): ~42 and ~77 deg/s (Gemini: slower reads heavier, less fan)
	CORE = 0.6, -- the bright core ball (Gemini: smaller, more of the deep well shows round it)
	CORE_Z = 0.25, -- just behind the vortex plane: the arms' faded inner ends run over it
	BACK_Z = 0.82, -- the deep backdrop (inside the pillars' back face at +1)
	BREATH_PERIOD = 3.6,
	OPEN_TIME = 0.35, -- grow in
	CLOSE_TIME = 0.4, -- shrink away
	FADED = 0.55, -- extra transparency of other players' portals
	ARRIVAL_TIME = 1.5,
	ARRIVAL_BLOCKS = 14,
	ARRIVAL_SPARKS = 6,
	MAX_ARRIVALS = 4,
	NAME_PX = 22, -- the name tag at 1080p
}
HomePortalFx.K = K

-- the players' portal colours (by UserId): bright, never the gold of the coins
local PALETTE = {
	Color3.fromRGB(120, 196, 255),
	Color3.fromRGB(186, 128, 255),
	Color3.fromRGB(255, 136, 196),
	Color3.fromRGB(110, 226, 170),
	Color3.fromRGB(255, 170, 92),
	Color3.fromRGB(96, 214, 236),
}
local GOLD = Color3.fromRGB(255, 214, 92)
local INK = Color3.fromRGB(26, 30, 52)

local localPlayer = Players.LocalPlayer
local portals = {} -- [player] = record
local arrivals = {} -- live arrival rings
local conns = {} -- global connections
local playerConns = {} -- [player] = { connections }
local folder = nil
local loopConn = nil
local initialized = false
local warned = false
local stats = { Opened = 0, Arrivals = 0 }
local clock = 0

local P = {} -- helpers (one table keeps the locals few)

function P.serverNow()
	local ok, t = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.clock()
end

function P.ensureFolder()
	if folder and folder.Parent then
		return folder
	end
	local f = Workspace:FindFirstChild("HomePortalFx")
	if not f then
		f = Instance.new("Folder")
		f.Name = "HomePortalFx"
		f.Parent = Workspace
	end
	folder = f
	return f
end

function P.part(name, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Size = size
	p.Color = color
	p.Transparency = transparency or 0
	return p
end

function P.lighten(c, t)
	return Color3.new(c.R + (1 - c.R) * t, c.G + (1 - c.G) * t, c.B + (1 - c.B) * t)
end

function P.darken(c, t)
	return Color3.new(c.R * (1 - t), c.G * (1 - t), c.B * (1 - t))
end

function P.colorOf(player)
	local uid = tonumber(player and player.UserId) or 0
	return PALETTE[(math.abs(math.floor(uid)) % #PALETTE) + 1]
end

-- "x,y,z,yaw,closesAt" -> point (Vector3), yaw (degrees), closesAt; nil for junk
function P.parse(text)
	if type(text) ~= "string" then
		return nil
	end
	local vals = {}
	for item in string.gmatch(text, "[^,]+") do
		local n = tonumber(item)
		if n == nil or n ~= n or n == math.huge or n == -math.huge then
			return nil
		end
		vals[#vals + 1] = n
	end
	if #vals < 5 then
		return nil
	end
	return Vector3.new(vals[1], vals[2], vals[3]), vals[4], vals[5]
end

function P.cameraPos()
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position or nil
end

----------------------------------------------------------------------
-- The portal model: a homestead gate around a Neon vortex, local layout around the vortex centre (faces -Z)
--   Frame   the gate: the Blender mesh gate_homeportal (MeshLibrary.Assemble, when the key is usable here) or, until
--           then, a Part copy of the same silhouette (threshold, plinths, pillars, caps, a 7-block oak arch, the
--           keystone and its plate in the portal colour): <= 16 parts
--   Surface the deep backdrop filling the opening (a block + a disc for the round top) and the lighter well round the centre
--   Core    the bright eye at the back of the funnel (carries the sparkles and the name tag)
--   Vortex  client/PortalVortex.Build with a fixed layout (3 invisible client parts carrying the Beams / emitters, or
--           the textured SurfaceGui plane); SetLook grows / shrinks / dims it with the gate, Animate turns it
-- <= 40 parts in all.
----------------------------------------------------------------------
local STONE = Color3.fromRGB(226, 221, 209)
local SLAB = Color3.fromRGB(206, 200, 188)
local OAK = Color3.fromRGB(165, 125, 85)
local OAK_DARK = Color3.fromRGB(125, 85, 55)
local BRASS = Color3.fromRGB(196, 160, 86)
local NAVY = Color3.fromRGB(34, 42, 76)

function P.meshLib()
	if P.ML ~= nil then
		return P.ML or nil
	end
	local ok, ml = pcall(function()
		return require(Shared:FindFirstChild("MeshLibrary"))
	end)
	P.ML = (ok and type(ml) == "table") and ml or false
	return P.ML or nil
end

-- a client module next to Controllers (PortalVortex, GraphicsQuality), required once; nil when missing
function P.clientModule(name)
	P.Mods = P.Mods or {}
	if P.Mods[name] == nil then
		P.Mods[name] = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild(name)
		if module then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				P.Mods[name] = mod
			end
		end
	end
	return P.Mods[name] or nil
end

-- the vortex texture ids (shared/TextureIds, filled by the upload session; empty = PortalVortex's effects-only fallback)
function P.textureIds()
	if P.Ids == nil then
		local ok, ids = pcall(function()
			return require(Shared:FindFirstChild("TextureIds"))
		end)
		P.Ids = (ok and type(ids) == "table") and ids or {}
	end
	return P.Ids
end

-- Low graphics: the vortex holds still (as the gates' do)
function P.lowQuality()
	local GQ = P.clientModule("GraphicsQuality")
	if GQ and type(GQ.Effective) == "function" then
		local ok, mode = pcall(GQ.Effective)
		return ok and mode == "Low"
	end
	return false
end

-- the gate as the Blender mesh: true when it was used (every part an item of kind "Frame"), false = build the Parts
function P.meshFrame(rec, model, add)
	local ml = P.meshLib()
	if not ml or type(ml.Active) ~= "function" or not ml.Active() or not ml.IsReady(K.MESH_KEY) then
		return false
	end
	local ok, mesh = pcall(ml.Assemble, { Name = "HomePortalMesh", Root = false, Parts = { { Key = K.MESH_KEY } } },
		{ Primary = rec.Color }, { At = CFrame.new(0, -K.CENTER_Y, 0) })
	if not ok or not mesh then
		return false
	end
	for _, d in ipairs(mesh:GetChildren()) do
		if d:IsA("BasePart") then
			d.CastShadow = false
			d.Parent = model
			add(d, d.CFrame, d.Size, d.Transparency, "Frame")
		end
	end
	mesh:Destroy()
	return true
end

-- the Part copy of the gate (same silhouette, plain colours) while the mesh is not usable here
function P.partFrame(rec, add, part)
	local g = -K.CENTER_Y -- the floor in local Y
	local h = K.OPEN_HALF
	part(Vector3.new(7.5, 0.5, 3), CFrame.new(0, g + 0.25, 0), SLAB) -- threshold
	for s = -1, 1, 2 do
		part(Vector3.new(2, 0.75, 2.5), CFrame.new(s * (h + 0.75), g + 0.875, 0), SLAB) -- plinth
		part(Vector3.new(1.5, 3.75, 2), CFrame.new(s * (h + 0.75), g + 3.125, 0), STONE) -- pillar
		part(Vector3.new(2.25, 0.5, 2.5), CFrame.new(s * (h + 0.875), g + 5.25, 0), SLAB) -- impost cap
	end
	local arch = CFrame.new(0, g + K.ARCH_Y, 0)
	local n = 7
	for i = 1, n do
		if i ~= 4 then
			local a = (i - 0.5) / n * math.pi
			part(Vector3.new(1, math.pi * 2.5 / n * 1.06, 1.5), arch * CFrame.Angles(0, 0, a) * CFrame.new(2.5, 0, 0), OAK)
		end
	end
	part(Vector3.new(1, 1.75, 2), CFrame.new(0, g + 8.125, 0), OAK_DARK) -- keystone
	part(Vector3.new(0.875, 1.125, 0.125), CFrame.new(0, g + 8.06, -1.06), rec.Color:Lerp(NAVY, 0.65)) -- its plate (the mesh Enamel recipe)
	part(Vector3.new(1.5, 0.25, 1.5), CFrame.new(0, g + 8.875, 0), BRASS:Lerp(OAK_DARK, 0.6)) -- the bronze cap
end

function P.build(rec)
	local color = rec.Color
	local model = Instance.new("Model")
	model.Name = "HomePortal"
	local items = {} -- { Part, Local (CFrame), Size (Vector3), Trans, Kind, Arm, Block }
	local function add(p, cf, size, trans, kind)
		local it = { Part = p, Local = cf, Size = size, Trans = trans or 0, Kind = kind }
		items[#items + 1] = it
		return it
	end
	local function make(name, size, cf, c, material, trans, kind)
		local p = P.part(name, size, c, material, trans)
		p.Parent = model
		return add(p, cf, size, trans, kind)
	end
	rec.Mesh = P.meshFrame(rec, model, add)
	if not rec.Mesh then
		P.partFrame(rec, add, function(size, cf, c)
			make("Frame", size, cf, c, Enum.Material.SmoothPlastic, 0, "Frame")
		end)
	end
	-- the deep backdrop (a block up to the springing line + a disc for the round top), just inside the back face
	local deep = P.darken(color:Lerp(NAVY, 0.25), 0.55) -- a deep, rich well (Gemini review: not candy blue)
	local h = K.OPEN_HALF - 0.05
	local yMid = (0.5 + K.ARCH_Y) / 2 - K.CENTER_Y
	make("Surface", Vector3.new(h * 2, K.ARCH_Y - 0.5, 0.1), CFrame.new(0, yMid, K.BACK_Z), deep, Enum.Material.Neon, 0, "Surface")
	local disc = make("Surface", Vector3.new(0.1, h * 2, h * 2), CFrame.new(0, K.ARCH_Y - K.CENTER_Y, K.BACK_Z + 0.02) * CFrame.Angles(0, math.pi / 2, 0),
		deep, Enum.Material.Neon, 0, "Surface")
	disc.Part.Shape = Enum.PartType.Cylinder
	-- the well: a lighter disc round the centre, a step in front of the backdrop (the funnel's throat)
	local well = make("Surface", Vector3.new(0.1, 2.8, 2.8), CFrame.new(0, 0, K.BACK_Z - 0.06) * CFrame.Angles(0, math.pi / 2, 0),
		P.darken(color, 0.3), Enum.Material.Neon, 0, "Surface")
	well.Part.Shape = Enum.PartType.Cylinder
	-- the bright core at the back of the funnel
	local core = make("Core", Vector3.new(K.CORE, K.CORE, K.CORE), CFrame.new(0, 0, K.CORE_Z), P.lighten(color, 0.85), Enum.Material.Neon, 0, "Core")
	core.Part.Shape = Enum.PartType.Ball
	-- the vortex: the Gate Court gates' own (PortalVortex), at the vortex centre in front of the backdrop
	local V = P.clientModule("PortalVortex")
	if V and type(V.Build) == "function" and type(V.SetLook) == "function" then
		local seed = math.abs(math.floor(tonumber(rec.Player and rec.Player.UserId) or 0)) % 100000 + 11
		local ok, v = pcall(V.Build, { Fixed = { Center = rec.Frame * CFrame.new(0, 0, K.VORTEX_Z), Radius = K.VORTEX_R, Speed = K.VORTEX_SPEED } },
			model, P.textureIds(), color, seed)
		if ok and v then
			V.SetStatic(v, P.lowQuality())
			V.SetLook(v, 0.02, 0)
			V.Show(v, true)
			rec.Vortex = v
		elseif not warned then
			warned = true
			warn("[HomePortalFx] vortex: " .. tostring(v))
		end
	end
	local center = core.Part
	model.PrimaryPart = center
	-- sparkles drift out of the core
	local att = Instance.new("Attachment")
	att.Name = "Sparkles"
	att.Parent = center
	local ok = pcall(function()
		local em = Instance.new("ParticleEmitter")
		em.Name = "Sparkles"
		em.Color = ColorSequence.new(P.lighten(color, 0.6), GOLD)
		em.Rate = 6
		em.Lifetime = NumberRange.new(0.8, 1.4)
		em.Speed = NumberRange.new(0.6, 1.4)
		em.SpreadAngle = Vector2.new(180, 180)
		em.LightInfluence = 0
		em.Parent = att
	end)
	if not ok then
		att:Destroy()
	end
	-- the name tag (pixel-sized, World text rule), over the gate's top
	local gui = Instance.new("BillboardGui")
	gui.Name = "PortalName"
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.StudsOffset = Vector3.new(0, K.TOP + 1.2 - K.CENTER_Y, 0)
	gui.Parent = center
	local px = K.NAME_PX
	if Theme and type(Theme.ScaledSize) == "function" then
		local okS, s = pcall(Theme.ScaledSize, K.NAME_PX)
		if okS and type(s) == "number" then
			px = s
		end
	end
	local text = tostring(rec.Name) .. "'s portal"
	local w = math.floor(px * 0.58 * #text + 28)
	gui.Size = UDim2.fromOffset(w, math.floor(px * 1.6))
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = INK
	plate.BackgroundTransparency = 0.25
	plate.BorderSizePixel = 0
	plate.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = plate
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextSize = px
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = INK
	label.Parent = plate
	if Theme then
		label.Font = Theme.Fonts.Title
		if type(Theme.TextOutline) == "function" then
			Theme.TextOutline(label, 2, INK, 0)
		end
	end
	rec.Model, rec.Items, rec.Gui, rec.Label = model, items, gui, label
	rec.PlacedScale, rec.PlacedFade = nil, nil
	model.Parent = P.ensureFolder()
end

-- writes the parts for the current scale / fade (only portals near the camera, never for far ones): the gate, the
-- backdrop and the core only when the scale or fade changed (or the record is Dirty: just built); the vortex every
-- frame (PortalVortex writes only quantised changes: its two spinners' turn, plus its size / dimming while it grows,
-- shrinks or fades)
function P.place(rec)
	local s = math.max(0.02, rec.Scale)
	local frame = rec.Frame
	local fade = rec.Faded and K.FADED or 0
	local closing = rec.Closing and (1 - s) or 0
	local still = not rec.Dirty and rec.PlacedScale == s and rec.PlacedFade == fade + closing
	rec.PlacedScale, rec.PlacedFade, rec.Dirty = s, fade + closing, nil
	if not still then
		for _, it in ipairs(rec.Items) do
			local loc = it.Local
			it.Part.CFrame = frame * (CFrame.new(loc.Position * s) * (loc - loc.Position))
			it.Part.Size = it.Size * s
			local t = it.Trans + (1 - it.Trans) * fade
			t = t + (1 - t) * closing
			if it.Part.Transparency ~= t then
				it.Part.Transparency = t
			end
		end
	end
	local V = rec.Vortex and P.clientModule("PortalVortex")
	if V then
		V.SetLook(rec.Vortex, s, fade + (1 - fade) * closing)
		local breath = 0.5 + 0.5 * math.sin(rec.Time / K.BREATH_PERIOD * 2 * math.pi)
		V.Animate(rec.Vortex, rec.Time, s, breath, rec.Vortex.Static)
	end
	if rec.Gui then
		local show = s > 0.6 and not rec.Closing
		if rec.Gui.Enabled ~= show then
			rec.Gui.Enabled = show
		end
	end
end
function P.destroy(rec)
	local V = rec.Vortex and P.clientModule("PortalVortex")
	if V then
		V.Destroy(rec.Vortex)
	end
	if rec.Model then
		rec.Model:Destroy()
	end
	rec.Model, rec.Items, rec.Gui, rec.Label, rec.Vortex = nil, nil, nil, nil, nil
end

-- the HomePortal attribute of a player changed: open / move / close their portal (a moved portal is rebuilt at the
-- new place on the next frame: the vortex's centre is fixed when it is built)
function P.refresh(player)
	local text = player:GetAttribute(PORTAL_ATTR)
	local point, yaw, closesAt = P.parse(text)
	local rec = portals[player]
	if not point then
		if rec and not rec.Closing then
			rec.Closing = true
			rec.CloseT = 0
		end
		return
	end
	if rec and rec.Closing then
		P.destroy(rec)
		rec = nil
	end
	local frame = CFrame.new(point + Vector3.new(0, K.CENTER_Y, 0)) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(0, math.pi, 0)
	if rec and rec.Point and (rec.Point - point).Magnitude < 0.05 and math.abs((rec.Yaw or 0) - yaw) < 0.5 then
		rec.ClosesAt = closesAt
		return
	end
	if not rec then
		rec = { Player = player, Scale = 0, Time = 0, Opening = true }
		portals[player] = rec
		stats.Opened = stats.Opened + 1
	elseif rec.Model then
		P.destroy(rec) -- moved: rebuilt where it now stands (P.step), at its current scale
	end
	rec.Point, rec.Yaw, rec.ClosesAt, rec.Frame = point, yaw, closesAt, frame
	rec.Name = (player.DisplayName ~= nil and player.DisplayName ~= "") and player.DisplayName or player.Name
	rec.Color = P.colorOf(player)
	rec.Faded = player ~= localPlayer
	rec.Center = frame.Position
	rec.Dirty = true
end

-- the arrival ring where the player stands now
function P.arrive(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local eye = P.cameraPos()
	-- (the local player's own arrival always plays: the camera catches up with the teleport a frame later)
	if player ~= localPlayer and eye and (root.Position - eye).Magnitude > K.DRAW_RANGE then
		return
	end
	while #arrivals >= K.MAX_ARRIVALS do
		P.endArrival(table.remove(arrivals, 1))
	end
	local color = P.colorOf(player)
	local ring = { T = 0, Parts = {}, Base = root.Position - Vector3.new(0, 2.8, 0) }
	for i = 1, K.ARRIVAL_BLOCKS do
		local c = (i % 2 == 0) and P.lighten(color, 0.4) or color
		local p = P.part("ArrivalRing", Vector3.new(0.6, 0.18, 0.3), c, Enum.Material.Neon, 0.1)
		p.Parent = P.ensureFolder()
		ring.Parts[#ring.Parts + 1] = p
	end
	for i = 1, K.ARRIVAL_SPARKS do
		local p = P.part("ArrivalSpark", Vector3.new(0.22, 0.22, 0.22), (i % 2 == 0) and GOLD or P.lighten(color, 0.6), Enum.Material.Neon, 0)
		p.Parent = P.ensureFolder()
		ring.Parts[#ring.Parts + 1] = p
	end
	arrivals[#arrivals + 1] = ring
	stats.Arrivals = stats.Arrivals + 1
	P.stepArrival(ring, 0)
end

function P.endArrival(ring)
	for _, p in ipairs(ring.Parts) do
		p:Destroy()
	end
	ring.Parts = {}
end

-- the ring widens from 1 to 4.5 studs and fades; the sparks rise and spin out
function P.stepArrival(ring, dt)
	ring.T = ring.T + dt
	local q = math.min(1, ring.T / K.ARRIVAL_TIME)
	local ease = 1 - (1 - q) * (1 - q)
	local radius = 1 + 3.5 * ease
	local trans = 0.1 + 0.9 * q
	for i, p in ipairs(ring.Parts) do
		if i <= K.ARRIVAL_BLOCKS then
			local a = (i - 0.5) / K.ARRIVAL_BLOCKS * 2 * math.pi
			local len = 2 * math.pi * radius / K.ARRIVAL_BLOCKS * 0.85
			p.Size = Vector3.new(len, 0.18, 0.3)
			p.CFrame = CFrame.new(ring.Base + Vector3.new(math.cos(a) * radius, 0.15, math.sin(a) * radius)) * CFrame.Angles(0, -a - math.pi / 2, 0)
		else
			local k = i - K.ARRIVAL_BLOCKS
			local a = k / K.ARRIVAL_SPARKS * 2 * math.pi + q * 4
			local r = 0.8 + 1.4 * ease
			p.CFrame = CFrame.new(ring.Base + Vector3.new(math.cos(a) * r, 0.4 + 3.2 * ease, math.sin(a) * r)) * CFrame.Angles(q * 6, q * 4, 0)
		end
		p.Transparency = trans
	end
	return q >= 1
end

----------------------------------------------------------------------
-- Frame loop
----------------------------------------------------------------------
function P.step(dt)
	dt = math.min(tonumber(dt) or 0, 0.1)
	clock = clock + dt
	local eye = P.cameraPos()
	local now = P.serverNow()
	for player, rec in pairs(portals) do
		if not rec.Closing and rec.ClosesAt and now > rec.ClosesAt + 0.25 then
			rec.Closing = true -- expired (the server clears the attribute too)
			rec.CloseT = 0
		end
		local near = eye == nil or (rec.Center - eye).Magnitude <= K.DRAW_RANGE
		if rec.Closing then
			rec.CloseT = rec.CloseT + dt
			rec.Scale = math.max(0, 1 - rec.CloseT / K.CLOSE_TIME)
			if rec.Scale <= 0 or not near or not rec.Model then
				P.destroy(rec)
				portals[player] = nil
			end
		elseif near then
			if not rec.Model then
				P.build(rec)
				rec.Dirty = true
			end
			if rec.Scale < 1 then
				rec.Scale = math.min(1, rec.Scale + dt / K.OPEN_TIME)
			end
		elseif rec.Model then
			P.destroy(rec) -- too far: nothing drawn, it comes back when the camera nears
			rec.Scale = 1
		end
		if rec.Model and portals[player] then
			rec.Time = (rec.Time or 0) + dt
			P.place(rec)
		end
	end
	local i = 1
	while i <= #arrivals do
		if P.stepArrival(arrivals[i], dt) then
			P.endArrival(table.remove(arrivals, i))
		else
			i = i + 1
		end
	end
end

function P.safeStep(dt)
	local ok, err = pcall(P.step, dt)
	if not ok and not warned then
		warned = true
		warn("[HomePortalFx] frame error: " .. tostring(err))
	end
end

function P.watch(player)
	if playerConns[player] then
		return
	end
	local list = {}
	playerConns[player] = list
	list[#list + 1] = player:GetAttributeChangedSignal(PORTAL_ATTR):Connect(function()
		local ok, err = pcall(P.refresh, player)
		if not ok and not warned then
			warned = true
			warn("[HomePortalFx] " .. tostring(err))
		end
	end)
	list[#list + 1] = player:GetAttributeChangedSignal(ARRIVED_ATTR):Connect(function()
		if player:GetAttribute(ARRIVED_ATTR) ~= nil then
			local ok, err = pcall(P.arrive, player)
			if not ok and not warned then
				warned = true
				warn("[HomePortalFx] " .. tostring(err))
			end
		end
	end)
	if player:GetAttribute(PORTAL_ATTR) ~= nil then
		pcall(P.refresh, player)
	end
end

function P.unwatch(player)
	local list = playerConns[player]
	if list then
		for _, c in ipairs(list) do
			c:Disconnect()
		end
	end
	playerConns[player] = nil
	local rec = portals[player]
	if rec then
		P.destroy(rec)
		portals[player] = nil
	end
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function HomePortalFx.Stats()
	local n, parts, shown, faded, closing, ringParts = 0, 0, 0, 0, 0, 0
	for _, rec in pairs(portals) do
		n = n + 1
		if rec.Model then
			shown = shown + 1
			parts = parts + #rec.Items
			if rec.Faded then
				faded = faded + 1
			end
		end
		if rec.Closing then
			closing = closing + 1
		end
	end
	for _, ring in ipairs(arrivals) do
		ringParts = ringParts + #ring.Parts
	end
	return { Portals = n, Parts = parts, Shown = shown, Faded = faded, Closing = closing, Rings = #arrivals, RingParts = ringParts,
		Opened = stats.Opened, Arrivals = stats.Arrivals }
end

function HomePortalFx.Portal(player)
	local rec = player and portals[player]
	if not rec then
		return nil
	end
	return { Model = rec.Model, Center = rec.Center, Yaw = rec.Yaw, ClosesAt = rec.ClosesAt, Faded = rec.Faded, Closing = rec.Closing == true,
		Name = rec.Label and rec.Label.Text or nil, Scale = rec.Scale, Gui = rec.Gui, Mesh = rec.Mesh == true, Vortex = rec.Vortex }
end

-- the gate mesh became usable here: portals still wearing the Part copy are rebuilt with the mesh on the next frame
function P.meshArrived()
	for _, rec in pairs(portals) do
		if rec.Model and not rec.Mesh and not rec.Closing then
			P.destroy(rec)
		end
	end
end

function HomePortalFx.Init()
	if initialized then
		return
	end
	initialized = true
	localPlayer = localPlayer or Players.LocalPlayer
	for _, player in ipairs(Players:GetPlayers()) do
		P.watch(player)
	end
	conns[#conns + 1] = Players.PlayerAdded:Connect(P.watch)
	conns[#conns + 1] = Players.PlayerRemoving:Connect(P.unwatch)
	loopConn = RunService.RenderStepped:Connect(P.safeStep)
	-- a waiter ranks gate_homeportal ahead of the ~800 keys preloading in arrival order (MeshLibrary: rank 1)
	local ml = P.meshLib()
	if ml and type(ml.OnReady) == "function" then
		pcall(ml.OnReady, K.MESH_KEY, function()
			if initialized then
				P.meshArrived()
			end
		end)
	end
end

function HomePortalFx.Stop()
	if loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	conns = {}
	local list = {}
	for player in pairs(playerConns) do
		list[#list + 1] = player
	end
	for _, player in ipairs(list) do
		P.unwatch(player)
	end
	for player, rec in pairs(portals) do
		P.destroy(rec)
		portals[player] = nil
	end
	for _, ring in ipairs(arrivals) do
		P.endArrival(ring)
	end
	arrivals = {}
	if folder then
		folder:Destroy()
		folder = nil
	end
	initialized = false
end

return HomePortalFx
