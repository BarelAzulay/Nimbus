-- HomePortalFx (client, Phase 4): the home portal and the arrival ring (ARCHITECTURE_V3.md "Phase 4 build contract"
-- 3.10 / 6). Zero server parts: TycoonService only writes two player attributes, this client draws them.
--
--   HomePortalFx.Init()
--   HomePortalFx.Stop()            disconnects everything and removes every part it made
--   HomePortalFx.Stats() -> { Portals, Parts, Shown, Faded, Closing, Rings, RingParts, Opened, Arrivals }
--   HomePortalFx.Portal(player) -> { Model, Center, Yaw, ClosesAt, Faded, Closing, Name } | nil   (tests / debugging)
--
-- * Config.Attr.HomePortal on a player = "x,y,z,yaw,closesAt" while their portal is open (x, y, z: the point on the
--   floor; yaw in degrees, CFrame.Angles(0, rad(yaw), 0).LookVector = the owner's facing when they opened it;
--   closesAt: workspace:GetServerTimeNow() when it closes, 10 s after opening). Every player's portal is drawn while it
--   is within K.DRAW_RANGE studs of the camera: a standing voxel ring (<= 30 parts) in the player's colour facing back
--   toward the owner, a swirl that turns inside it, a glowing surface, sparkles, and a 22 px name tag
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
	RING_RADIUS = 2.6, -- studs: the ring's middle line
	RING_BLOCKS = 20, -- voxel blocks around the ring
	CENTER_Y = 3.0, -- the ring's centre above the floor point
	OPEN_TIME = 0.35, -- grow in
	CLOSE_TIME = 0.4, -- shrink away
	SWIRL_SPEED = 2.4, -- radians per second
	FADED = 0.55, -- extra transparency of other players' portals
	ARRIVAL_TIME = 1.5,
	ARRIVAL_BLOCKS = 14,
	ARRIVAL_SPARKS = 6,
	MAX_ARRIVALS = 4,
	NAME_PX = 22, -- the name tag at 1080p
}

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
-- The portal model: <= 30 parts, local layout around the ring centre (the portal faces -Z of its frame)
----------------------------------------------------------------------
function P.build(rec)
	local color = rec.Color
	local model = Instance.new("Model")
	model.Name = "HomePortal"
	local items = {} -- { Part, Local (CFrame), Size (Vector3), Trans, Kind }
	local function add(name, size, cf, c, material, trans, kind)
		local p = P.part(name, size, c, material, trans)
		p.Parent = model
		items[#items + 1] = { Part = p, Local = cf, Size = size, Trans = trans or 0, Kind = kind }
		return p
	end
	local r = K.RING_RADIUS
	local seg = 2 * math.pi * r / K.RING_BLOCKS
	for i = 1, K.RING_BLOCKS do
		local a = (i - 0.5) / K.RING_BLOCKS * 2 * math.pi
		local shade = (i % 2 == 0) and P.lighten(color, 0.25) or color
		if i % 5 == 0 then
			shade = GOLD
		end
		-- each block sits on the circle, its long side along the ring (a voxel ring with stepped edges)
		add("Ring", Vector3.new(seg * 1.08, 0.55, 0.6), CFrame.Angles(0, 0, a) * CFrame.new(0, r, 0), shade, Enum.Material.SmoothPlastic, 0, "Ring")
	end
	-- the glowing surface inside (two crossed squares read as a round disc) and the swirl arms that turn
	add("Surface", Vector3.new(r * 1.27, r * 1.27, 0.08), CFrame.Angles(0, 0, math.pi / 4), P.darken(color, 0.1), Enum.Material.Neon, 0.3, "Surface")
	add("Surface", Vector3.new(r * 1.27, r * 1.27, 0.06), CFrame.new(0, 0, 0.02), P.darken(color, 0.25), Enum.Material.Neon, 0.35, "Surface")
	for k = 1, 3 do
		add("Swirl", Vector3.new(r * 1.5, 0.26, 0.1), CFrame.new(0, 0, -0.06), P.lighten(color, 0.75), Enum.Material.Neon, 0.05, "Swirl" .. k)
	end
	-- the base: a stone step under the ring and a glowing sill
	add("Base", Vector3.new(r * 1.6, 0.4, 1.4), CFrame.new(0, -r - 0.2, 0), P.darken(color, 0.45), Enum.Material.SmoothPlastic, 0, "Base")
	add("Sill", Vector3.new(r * 1.2, 0.12, 1.0), CFrame.new(0, -r + 0.06, 0), P.lighten(color, 0.5), Enum.Material.Neon, 0.2, "Base")
	local center = items[K.RING_BLOCKS + 1].Part
	model.PrimaryPart = center
	-- sparkles drift out of the surface
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
	-- the name tag (pixel-sized, World text rule)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PortalName"
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.StudsOffset = Vector3.new(0, r + 1.4, 0)
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
	model.Parent = P.ensureFolder()
end

-- writes every part for the current scale / swirl angle / fade (only portals near the camera, never for far ones)
function P.place(rec)
	local s = math.max(0.02, rec.Scale)
	local frame = rec.Frame
	local fade = rec.Faded and K.FADED or 0
	for _, it in ipairs(rec.Items) do
		local loc = it.Local
		local kind = it.Kind
		if kind and string.sub(kind, 1, 5) == "Swirl" then
			local k = tonumber(string.sub(kind, 6)) or 1
			loc = CFrame.Angles(0, 0, rec.Angle + k * (math.pi / 3)) * loc
		end
		local p = loc.Position * s
		it.Part.CFrame = frame * (CFrame.new(p) * (loc - loc.Position))
		it.Part.Size = it.Size * s
		local t = it.Trans + (1 - it.Trans) * fade
		if rec.Closing then
			t = t + (1 - t) * (1 - s)
		end
		if it.Part.Transparency ~= t then
			it.Part.Transparency = t
		end
	end
	if rec.Gui then
		local show = s > 0.6 and not rec.Closing
		if rec.Gui.Enabled ~= show then
			rec.Gui.Enabled = show
		end
	end
end

function P.destroy(rec)
	if rec.Model then
		rec.Model:Destroy()
	end
	rec.Model, rec.Items, rec.Gui, rec.Label = nil, nil, nil, nil
end

-- the HomePortal attribute of a player changed: open / move / close their portal
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
		rec = { Player = player, Scale = 0, Angle = 0, Opening = true }
		portals[player] = rec
		stats.Opened = stats.Opened + 1
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
			rec.Angle = (rec.Angle + dt * K.SWIRL_SPEED) % (2 * math.pi)
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
		Name = rec.Label and rec.Label.Text or nil, Scale = rec.Scale, Gui = rec.Gui }
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
