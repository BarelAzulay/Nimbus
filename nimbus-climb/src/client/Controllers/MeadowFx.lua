-- MeadowFx (client, bug #12 "Wind-Sown Sky Meadow"): grows the lobby's grass and wildflowers on THIS client and sways
-- them in the wind. The server only decides where things grow (LobbyBuilder Meadow: attributes on
-- workspace.NimbusLobby.Meadow, 9 characters per clump) and builds no grass parts at all (the lobby part budget).
--
-- What a clump is: one of eight Blender keys (meadow_tuft_tall / _short / _seed, meadow_sprig, meadow_flowers (petals
-- tinted per clump), meadow_cornflower, meadow_dandelion, meadow_clover), cloned from a MeshLibrary.Assemble template
-- once the key is ready here; until then (no uploaded id, still loading, a failed download on this device) a small
-- plain-part stand-in of the same kind (2-3 thin parts). A key that becomes ready later swaps its clumps over. Every
-- part is local, anchored, never collides / touches / is queried, casts no shadow.
--
-- Distance: clumps live in 16-stud buckets; every REFRESH seconds (or when the camera moved MOVE studs) the buckets
-- round the camera are walked: a clump shows while its fixed random rank is under the density at its distance (all of
-- them within FULL studs, a smooth fall to FAR_KEEP at FAR, none beyond; flowers count double so the colour carries
-- further). Spawns per pass are capped (no hitch); hidden clumps go back to a pool and are reused.
--
-- Wind (smooth, every frame): each shown clump within SWAY_FADE studs tilts about its foot, round the horizontal axis
-- across the wind, by
--     amp * (0.35 * breeze + 1.05 * gust^2 - 0.12) + flutter
--   gust    = a raised cosine band GUST_LEN studs long rolling downwind at GUST_LEN / GUST_PERIOD studs/s, its front
--             bent by a slow cross-wind wobble (so the wave is not a ruler line);
--   breeze  = a slow lobby-wide swell (0..1, 17 s), so no two loops look the same;
--   flutter = a small fast shiver (FLUTTER_HZ) with a random phase per clump.
-- Grass tilts up to ~12 degrees, flowers / seed heads ~17 (Gemini's numbers), the low clover and sprigs ~5. The
-- amplitude fades to 0 between SWAY_R and SWAY_FADE, so a clump leaving the moving ring stops at rest (no frozen
-- lean, no pop). All parts are written with ONE Workspace:BulkMoveTo per frame from reused buffers.
--
-- Low graphics (GraphicsQuality.Effective() == "Low") or Stop(): every clump is removed, nothing runs per frame.
--
--   MeadowFx.Init()                  idempotent (Main.client.lua starts it)
--   MeadowFx.Stop()                  everything removed, connections dropped
--   MeadowFx.Step(dt)                one Heartbeat (tests drive it)
--   MeadowFx.Tilt(t, along, cross, amp, flutter, phase) -> radians   (pure; tests)
--   MeadowFx.Density(d) -> 0..1      (pure; tests)
--   MeadowFx.Stats() -> { Clumps, Shown, Moving, Mesh, Parts, Writes, Quality, Time, Spawned }
--   MeadowFx.K                       the tuning numbers
-- Plain Lua 5.1-compatible syntax only.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MeadowFx = {}

local K = {
	FOLDER = "Meadow",
	FULL = 34, -- studs from the camera: every clump
	FAR = 95, -- ... falling to FAR_KEEP of them here; none beyond
	FAR_KEEP = 0.12,
	FLOWER_RANK = 0.5, -- flowers' rank is halved: they carry further
	FALLBACK_KEEP = 0.6, -- plain-part stand-ins: this share of the clumps (the meshes are what the meadow is for)
	BUCKET = 16,
	REFRESH = 0.25, -- seconds between LOD passes
	MOVE = 4, -- ... or as soon as the camera moved this far
	SPAWN_MAX = 300, -- clumps made per pass
	HYST = 0.05, -- a shown clump stays until its rank is this far over the density
	SWAY_R = 32, -- full sway within
	SWAY_FADE = 46, -- no sway beyond (at rest)
	GUST_LEN = 36, -- studs between gust fronts
	GUST_PERIOD = 4, -- seconds for one front to pass (9 studs/s)
	BREEZE_PERIOD = 17,
	WOBBLE = 0.16, -- how far (in gust lengths) the fronts bend across the wind
	FLUTTER_HZ = 1.3,
	-- per kind: amplitude (rad), flutter (rad); Kinds order of the server (LobbyBuilder MEADOW.Kinds)
	SWAY = {
		meadow_tuft_tall = { 0.2, 0.035 },
		meadow_tuft_short = { 0.16, 0.03 },
		meadow_tuft_seed = { 0.27, 0.06 },
		meadow_sprig = { 0.09, 0.02 },
		meadow_flowers = { 0.29, 0.065 },
		meadow_cornflower = { 0.29, 0.065 },
		meadow_dandelion = { 0.25, 0.05 },
		meadow_clover = { 0.07, 0.015 },
	},
	FLOWERY = { meadow_flowers = true, meadow_cornflower = true, meadow_dandelion = true },
	-- the low ones are gone sooner (their distance counts 1 / this): they are a few pixels past ~25 studs anyway
	RANGE = { meadow_sprig = 0.6, meadow_clover = 0.6 },
	-- Roblox's own graphics slider (1..10; 0 = Automatic): mid settings grow a thinner meadow (Low hides it all)
	SLIDER_MID = { 4, 6, 0.65 },
}
MeadowFx.K = K

local TWO_PI = math.pi * 2
local cos, sin, sqrt, floor = math.cos, math.sin, math.sqrt, math.floor

local St = {
	Started = false,
	Conns = {},
	Time = 0,
	RefreshAcc = 0,
	Quality = "High",
	Quality0 = nil,
	Lib = nil, -- MeshLibrary (or false)
	Folder = nil, -- the server's Meadow folder we parsed
	Holder = nil, -- our local folder of clump parts
	Wind = Vector3.new(1, 0, 0),
	Axis = Vector3.new(0, 0, -1),
	Base = 0,
	Kinds = {},
	Tints = {},
	N = 0,
	-- per clump (arrays)
	PX = {}, PY = {}, PZ = {}, Yaw = {}, Scale = {}, Kind = {}, Tint = {}, Rank = {}, Along = {}, Cross = {},
	Phase = {}, Bucket = {},
	Inst = {}, -- [i] = { Parts = { part... }, Offs = { CFrame... }, Mesh = bool, Key = poolKey }
	Buckets = {}, -- [bucketKey] = { i... }
	Live = {}, -- [bucketKey] = true (buckets with shown clumps)
	Moving = {}, -- list of i
	Fade = {}, -- [i] = sway amplitude factor (1 near, 0 at SWAY_FADE)
	Pools = {}, -- [poolKey] = { inst... }
	Protos = {}, -- [poolKey] = { Parts = { part... }, Offs = { CFrame... }, Mesh = bool } (unparented)
	LastCam = nil,
	Scale0 = 1, -- the graphics-slider density factor
	Shown = 0,
	Spawned = 0,
	Writes = 0,
	PartList = {},
	CFList = {},
}
MeadowFx._St = St

----------------------------------------------------------------------
-- pure helpers
----------------------------------------------------------------------

-- the tilt (radians) of a clump at time t; along / cross = its position along / across the wind (studs)
-- phase (0..1, per clump) also staggers the gust a little and sets the flutter rate (0.8x .. 1.2x), so neighbours never
-- move in lock-step (Gemini review: "a chorus line")
function MeadowFx.Tilt(t, along, cross, amp, flutter, phase)
	phase = phase or 0
	local u = along / K.GUST_LEN - t / K.GUST_PERIOD + K.WOBBLE * sin(cross / 23 + 0.4) + 0.05 * sin(cross / 7.3)
		+ 0.06 * phase
	local band = 0.5 - 0.5 * cos(TWO_PI * u)
	local gust = band * band
	local breeze = 0.5 + 0.5 * sin(TWO_PI * t / K.BREEZE_PERIOD + along / 90)
	return amp * (0.35 * breeze + 1.05 * gust - 0.12) + flutter * sin(TWO_PI * (K.FLUTTER_HZ * (0.8 + 0.4 * phase) * t + phase))
end

-- share of clumps shown at distance d from the camera
function MeadowFx.Density(d)
	if d <= K.FULL then
		return 1
	elseif d >= K.FAR then
		return 0
	end
	local x = (d - K.FULL) / (K.FAR - K.FULL)
	x = x * x * (3 - 2 * x)
	return 1 + (K.FAR_KEEP - 1) * x
end

local function hash01(i)
	local h = (i * 2654435761 + 40503) % 4294967296
	h = (h * 1103515245 + 12345) % 2147483648
	return (h % 100003) / 100003
end

-- the server's 9-character clump records (LobbyBuilder Meadow.encode)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64I = {}
for i = 1, #B64 do
	B64I[string.byte(B64, i)] = i - 1
end

function MeadowFx.Decode(s, i)
	local o = (i - 1) * 9
	local b = { string.byte(s, o + 1, o + 9) }
	if #b < 9 then
		return nil
	end
	local function v(a, len)
		local x = 0
		for j = a, a + len - 1 do
			x = x * 64 + (B64I[b[j]] or 0)
		end
		return x
	end
	local kt = v(1, 1)
	local tint = kt % 8
	local f = v(9, 1)
	return {
		Kind = (kt - tint) / 8 + 1,
		Tint = tint,
		X = v(2, 3) / 64 - 2048,
		Z = v(5, 3) / 64 - 2048,
		Yaw = v(8, 1) / 64 * TWO_PI,
		Scale = 0.7 + (f % 16) * 0.04,
		Patch = f >= 16,
	}
end

----------------------------------------------------------------------
-- environment
----------------------------------------------------------------------

local function quality()
	if St.Quality0 == nil then
		St.Quality0 = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild("GraphicsQuality")
		if module then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" and type(mod.Effective) == "function" then
				St.Quality0 = mod
			end
		end
	end
	if St.Quality0 then
		local ok, mode = pcall(St.Quality0.Effective)
		if ok and (mode == "Low" or mode == "High") then
			return mode
		end
	end
	return "High"
end

local function readSlider()
	local v = UserSettings().GameSettings.SavedQualityLevel
	if typeof(v) == "EnumItem" then
		return v.Value
	end
	return tonumber(v)
end

local function sliderScale()
	local ok, level = pcall(readSlider) -- module-level function: no closure per call
	level = ok and tonumber(level) or 0
	local m = K.SLIDER_MID
	if level >= m[1] and level <= m[2] then
		return m[3]
	end
	return 1
end

local function meshLib()
	if St.Lib == nil then
		St.Lib = false
		local ok, lib = pcall(function()
			local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
			local m = shared and shared:FindFirstChild("MeshLibrary")
			return m and require(m)
		end)
		if ok and type(lib) == "table" and type(lib.IsReady) == "function" and type(lib.Assemble) == "function" then
			St.Lib = lib
			if type(lib.Changed) == "table" and type(lib.Changed.Connect) == "function" then
				local okC, conn = pcall(function()
					return lib.Changed:Connect(function(key)
						MeadowFx._KeyChanged(key)
					end)
				end)
				if okC and conn then
					St.Conns[#St.Conns + 1] = conn
				end
			end
		end
	end
	return St.Lib or nil
end

function MeadowFx._SetLib(lib) -- tests: a stand-in MeshLibrary (or false = none)
	St.Lib = lib
end

local function findFolder()
	local lobby = Workspace:FindFirstChild("NimbusLobby")
	return lobby and lobby:FindFirstChild(K.FOLDER) or nil
end

----------------------------------------------------------------------
-- prototypes: one per (kind, tint) and look (mesh or parts)
----------------------------------------------------------------------

local function flagPart(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
end

local GREEN = {
	Color3.fromRGB(72, 140, 62), Color3.fromRGB(98, 170, 78), Color3.fromRGB(128, 192, 92),
}
local STRAW = Color3.fromRGB(204, 196, 124)
local STEM = Color3.fromRGB(84, 150, 68)
local YELLOW = Color3.fromRGB(250, 214, 92)

-- the plain-part stand-in of a kind: parts at their offsets from the clump's foot (+X downwind)
local function standIn(key, tint)
	local parts, offs = {}, {}
	local function add(size, cf, color, shape)
		local p = Instance.new("Part")
		p.Name = "MeadowBit"
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		flagPart(p)
		parts[#parts + 1] = p
		offs[#offs + 1] = cf
	end
	local function blade(h, x, z, lean, side, col)
		add(Vector3.new(0.14, h, 0.05), CFrame.new(x, 0, z) * CFrame.Angles(side, 0, -lean) * CFrame.new(0, h / 2 - 0.04, 0), col)
	end
	if key == "meadow_tuft_tall" or key == "meadow_tuft_seed" then
		blade(0.95, 0, 0, 0.32, 0.12, GREEN[2])
		blade(0.75, 0.1, 0.12, 0.42, -0.25, GREEN[1])
		blade(0.65, -0.1, -0.1, 0.22, 0.3, key == "meadow_tuft_seed" and STRAW or GREEN[3])
	elseif key == "meadow_tuft_short" then
		blade(0.5, 0, 0, 0.3, 0.15, GREEN[2])
		blade(0.42, 0.12, 0.1, 0.45, -0.35, GREEN[3])
		blade(0.38, -0.1, -0.12, 0.2, 0.4, GREEN[1])
	elseif key == "meadow_sprig" then
		blade(0.38, 0, 0, 0.3, 0.2, GREEN[2])
		blade(0.3, 0.08, 0.08, 0.45, -0.3, GREEN[3])
	elseif key == "meadow_clover" then
		add(Vector3.new(0.5, 0.06, 0.4), CFrame.new(0, 0.12, 0), Color3.fromRGB(104, 176, 82))
		add(Vector3.new(0.12, 0.12, 0.12), CFrame.new(0.1, 0.28, 0.05), Color3.fromRGB(246, 222, 232))
	else
		local head = YELLOW
		if key == "meadow_flowers" then
			head = St.Tints[tint] or Color3.fromRGB(246, 150, 188)
		elseif key == "meadow_cornflower" then
			head = Color3.fromRGB(96, 140, 236)
		end
		add(Vector3.new(0.06, 0.8, 0.06), CFrame.new(0.08, 0.38, 0) * CFrame.Angles(0, 0, -0.18), STEM)
		add(Vector3.new(0.36, 0.08, 0.36), CFrame.new(0.15, 0.8, 0), head)
		if key == "meadow_dandelion" then
			add(Vector3.new(0.26, 0.26, 0.26), CFrame.new(-0.05, 0.95, 0.1), Color3.fromRGB(246, 246, 240), Enum.PartType.Ball)
		else
			add(Vector3.new(0.12, 0.06, 0.12), CFrame.new(0.15, 0.85, 0), YELLOW)
		end
	end
	return { Parts = parts, Offs = offs, Mesh = false }
end

local function meshProto(key, tint)
	local lib = meshLib()
	if not lib then
		return nil
	end
	local okReady, ready = pcall(lib.IsReady, key)
	if not okReady or not ready then
		return nil
	end
	local look = {}
	if key == "meadow_flowers" and St.Tints[tint] then
		look.Primary = St.Tints[tint]
	end
	local ok, model = pcall(lib.Assemble, key, look, { At = CFrame.new() })
	if not ok or typeof(model) ~= "Instance" then
		return nil
	end
	local parts, offs = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			flagPart(d)
			parts[#parts + 1] = d
			offs[#offs + 1] = d.CFrame -- relative to the foot (Assemble placed the pivot at the origin)
		end
	end
	for _, p in ipairs(parts) do
		p.Parent = nil
	end
	model:Destroy()
	if #parts == 0 then
		return nil
	end
	return { Parts = parts, Offs = offs, Mesh = true }
end

local function poolKey(kind, tint)
	return kind * 8 + tint
end

local function proto(kind, tint)
	local pk = poolKey(kind, tint)
	local p = St.Protos[pk]
	if p == nil then
		local key = St.Kinds[kind] or ""
		p = meshProto(key, tint) or standIn(key, tint)
		-- split each part offset once: its rotation (about the foot) and its position (scaled per clump at spawn)
		p.Rot, p.Pos = {}, {}
		for j, o in ipairs(p.Offs) do
			p.Rot[j] = o - o.Position
			p.Pos[j] = o.Position
		end
		St.Protos[pk] = p
	end
	return p
end

----------------------------------------------------------------------
-- clumps
----------------------------------------------------------------------

-- the wind tilt (radians) of shown clump i at the current time; f = its sway fade (1 near .. 0 at SWAY_FADE)
local function tiltOf(i, f)
	local sw = K.SWAY[St.Kinds[St.Kind[i]]] or K.SWAY.meadow_tuft_short
	return MeadowFx.Tilt(St.Time, St.Along[i], St.Cross[i], sw[1] * f, sw[2] * f, St.Phase[i])
end

-- part j of a shown clump sits at  foot * Tilt * Yaw * (Rot[j] + Pos[j] * scale);  the last three factors never change
-- while the clump is shown, so spawnClump keeps Yaw * (Rot[j] + Pos[j] * scale) as inst.Local[j] and a frame costs one
-- CFrame for the tilted foot (built straight from the tilt's quaternion) and one product per part (review: fewer
-- transient CFrames in the hot loop)
local function place(i, inst, tilt)
	local foot
	if tilt and tilt ~= 0 then
		local h = tilt * 0.5
		local sh = sin(h)
		local ax = St.Axis
		foot = CFrame.new(St.PX[i], St.PY[i], St.PZ[i], ax.X * sh, ax.Y * sh, ax.Z * sh, cos(h))
	else
		foot = CFrame.new(St.PX[i], St.PY[i], St.PZ[i])
	end
	local pl, cl = St.PartList, St.CFList
	local loc = inst.Local
	for j, part in ipairs(inst.Parts) do
		pl[#pl + 1] = part
		cl[#cl + 1] = foot * loc[j]
	end
end

local function flush()
	local pl, cl = St.PartList, St.CFList
	local n = #pl
	if n == 0 then
		return
	end
	local ok = pcall(function()
		Workspace:BulkMoveTo(pl, cl, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for j = 1, n do
			pl[j].CFrame = cl[j]
		end
	end
	St.Writes = St.Writes + n
	for j = n, 1, -1 do
		pl[j] = nil
		cl[j] = nil
	end
end

-- tilt: the clump's wind tilt right now (0 beyond SWAY_FADE), so a clump that appears inside the moving ring (a
-- teleport, a respawn, Low -> High) starts leaning with its neighbours instead of upright for a frame
local function spawnClump(i, tilt)
	local kind, tint = St.Kind[i], St.Tint[i]
	local pk = poolKey(kind, tint)
	local pool = St.Pools[pk]
	local inst = pool and table.remove(pool)
	if not inst then
		local p = proto(kind, tint)
		inst = { Parts = {}, Offs = p.Offs, Rot = p.Rot, Pos = p.Pos, Local = {}, Mesh = p.Mesh, Key = pk, BaseSize = {} }
		for j, src in ipairs(p.Parts) do
			inst.Parts[j] = src:Clone()
			inst.BaseSize[j] = src.Size
		end
	end
	local s = St.Scale[i]
	local yaw = CFrame.Angles(0, St.Yaw[i], 0)
	for j, part in ipairs(inst.Parts) do
		part.Size = inst.BaseSize[j] * s
		inst.Local[j] = yaw * (inst.Rot[j] + inst.Pos[j] * s)
	end
	place(i, inst, tilt or 0)
	for _, part in ipairs(inst.Parts) do
		part.Parent = St.Holder
	end
	St.Inst[i] = inst
	St.Shown = St.Shown + 1
	St.Spawned = St.Spawned + 1
end

local function despawnClump(i)
	local inst = St.Inst[i]
	if not inst then
		return
	end
	for _, part in ipairs(inst.Parts) do
		part.Parent = nil
	end
	local pool = St.Pools[inst.Key]
	if not pool then
		pool = {}
		St.Pools[inst.Key] = pool
	end
	pool[#pool + 1] = inst
	St.Inst[i] = nil
	St.Shown = St.Shown - 1
end

local function clearAll()
	for i in pairs(St.Inst) do
		despawnClump(i)
	end
	St.Moving = {}
	St.Live = {}
	flush()
end

local function destroyPools()
	for _, pool in pairs(St.Pools) do
		for _, inst in ipairs(pool) do
			for _, part in ipairs(inst.Parts) do
				part:Destroy()
			end
		end
	end
	St.Pools = {}
	for _, p in pairs(St.Protos) do
		for _, part in ipairs(p.Parts) do
			part:Destroy()
		end
	end
	St.Protos = {}
end

-- a key became ready (or broken) here: its clumps are rebuilt from the new prototype at the next pass
function MeadowFx._KeyChanged(key)
	local kind = nil
	for k, name in ipairs(St.Kinds) do
		if name == key then
			kind = k
		end
	end
	if not kind then
		return
	end
	for i, inst in pairs(St.Inst) do
		if St.Kind[i] == kind then
			despawnClump(i)
		end
	end
	for pk, pool in pairs(St.Pools) do
		if floor(pk / 8) == kind then
			for _, inst in ipairs(pool) do
				for _, part in ipairs(inst.Parts) do
					part:Destroy()
				end
			end
			St.Pools[pk] = nil
		end
	end
	for pk, p in pairs(St.Protos) do
		if floor(pk / 8) == kind then
			for _, part in ipairs(p.Parts) do
				part:Destroy()
			end
			St.Protos[pk] = nil
		end
	end
	St.LastCam = nil -- refresh at once
end

local function bucketOf(x, z)
	return floor(x / K.BUCKET) * 65536 + floor(z / K.BUCKET)
end

-- read the server's scatter (once per folder)
local function parse(folder)
	clearAll()
	destroyPools()
	St.Folder = folder
	local wind = folder:GetAttribute("Wind")
	if typeof(wind) == "Vector3" and wind.Magnitude > 0 then
		St.Wind = Vector3.new(wind.X, 0, wind.Z).Unit
	end
	St.Axis = Vector3.new(0, 1, 0):Cross(St.Wind) -- tilting about it pushes a clump's top downwind
	St.Base = tonumber(folder:GetAttribute("Base")) or 0
	local origin = folder:GetAttribute("Origin")
	local ox, oz = 0, 0
	if typeof(origin) == "Vector3" then
		ox, oz = origin.X, origin.Z
	end
	St.Kinds = {}
	for name in string.gmatch(tostring(folder:GetAttribute("Kinds") or ""), "[^,]+") do
		St.Kinds[#St.Kinds + 1] = name
	end
	St.Tints = {}
	for t = 1, 7 do
		local c = folder:GetAttribute("Tint" .. t)
		if typeof(c) == "Color3" then
			St.Tints[t] = c
		end
	end
	local n = 0
	St.Buckets = {}
	local chunks = tonumber(folder:GetAttribute("Chunks")) or 0
	local wx, wz = St.Wind.X, St.Wind.Z
	for ch = 1, chunks do
		local s = folder:GetAttribute("Clumps" .. ch)
		if type(s) == "string" then
			for j = 1, floor(#s / 9) do
				local c = MeadowFx.Decode(s, j)
				local key = c and St.Kinds[c.Kind]
				if key then
					n = n + 1
					local x, z = ox + c.X, oz + c.Z
					St.PX[n], St.PY[n], St.PZ[n] = x, St.Base + (c.Patch and 0.1 or 0), z
					St.Yaw[n], St.Scale[n], St.Kind[n], St.Tint[n] = c.Yaw, c.Scale, c.Kind, c.Tint
					local r = hash01(n)
					if K.FLOWERY[key] then
						r = r * K.FLOWER_RANK
					end
					St.Rank[n] = r
					St.Along[n] = x * wx + z * wz
					St.Cross[n] = -x * wz + z * wx
					St.Phase[n] = hash01(n + 7919)
					local b = bucketOf(x, z)
					St.Bucket[n] = b
					local list = St.Buckets[b]
					if not list then
						list = {}
						St.Buckets[b] = list
					end
					list[#list + 1] = n
				end
			end
		end
	end
	for j = n + 1, St.N do
		St.PX[j], St.PY[j], St.PZ[j], St.Yaw[j], St.Scale[j], St.Kind[j], St.Tint[j] = nil, nil, nil, nil, nil, nil, nil
		St.Rank[j], St.Along[j], St.Cross[j], St.Phase[j], St.Bucket[j] = nil, nil, nil, nil, nil
	end
	St.N = n
	St.LastCam = nil
end

local function cameraPos()
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position or nil
end

-- the LOD pass: show / hide by distance and rank, rebuild the moving list
local function refresh(force)
	St.Quality = quality()
	St.Scale0 = sliderScale()
	local folder = findFolder()
	if folder ~= St.Folder then
		if folder then
			parse(folder)
		else
			clearAll()
			St.Folder = nil
			St.N = 0
		end
	end
	if St.Quality == "Low" or St.N == 0 then
		if St.Shown > 0 then
			clearAll()
		end
		-- idle (Low, or no Meadow folder yet): look again on the REFRESH timer only, not every frame (Step re-runs the
		-- pass while LastCam is nil); the timer pass is forced, so a folder that arrives or a switch to High is seen
		St.LastCam = cameraPos() or Vector3.new()
		return
	end
	local cam = cameraPos()
	if not cam then
		return
	end
	if not St.Holder or not St.Holder.Parent then
		local h = Instance.new("Folder")
		h.Name = "MeadowLocal"
		h.Parent = Workspace
		St.Holder = h
	end
	if not force and St.LastCam and (cam - St.LastCam).Magnitude < K.MOVE and St.RefreshAcc < K.REFRESH then
		return
	end
	St.LastCam = cam
	local cx, cz, cy = cam.X, cam.Z, cam.Y
	local reach = K.FAR + K.BUCKET
	local b0x, b1x = floor((cx - reach) / K.BUCKET), floor((cx + reach) / K.BUCKET)
	local b0z, b1z = floor((cz - reach) / K.BUCKET), floor((cz + reach) / K.BUCKET)
	local live = {}
	local moving = {}
	local budget = K.SPAWN_MAX
	local fallbackKeep = K.FALLBACK_KEEP
	for bx = b0x, b1x do
		for bz = b0z, b1z do
			local b = bx * 65536 + bz
			local list = St.Buckets[b]
			if list then
				live[b] = true
				for _, i in ipairs(list) do
					local dx, dz, dy = St.PX[i] - cx, St.PZ[i] - cz, St.PY[i] - cy
					local d = sqrt(dx * dx + dz * dz + dy * dy * 0.25)
					local range = K.RANGE[St.Kinds[St.Kind[i]]] or 1
					local dens = MeadowFx.Density(d / range) * St.Scale0
					local inst = St.Inst[i]
					local rank = St.Rank[i]
					if not proto(St.Kind[i], St.Tint[i]).Mesh then
						dens = dens * fallbackKeep -- the plain stand-ins stay sparser
					end
					local f = nil -- sway fade inside the moving ring
					if d < K.SWAY_FADE then
						f = 1
						if d > K.SWAY_R then
							f = 1 - (d - K.SWAY_R) / (K.SWAY_FADE - K.SWAY_R)
							f = f * f * (3 - 2 * f)
						end
					end
					if inst then
						if rank > dens + K.HYST then
							despawnClump(i)
							inst = nil
						end
					elseif rank < dens and budget > 0 then
						spawnClump(i, f and tiltOf(i, f) or 0)
						budget = budget - 1
						inst = St.Inst[i]
					end
					if inst and f then
						moving[#moving + 1] = i
						St.Fade[i] = f
					end
				end
			end
		end
	end
	-- buckets that fell out of reach: everything in them goes back to the pools
	for b in pairs(St.Live) do
		if not live[b] then
			for _, i in ipairs(St.Buckets[b] or {}) do
				despawnClump(i)
			end
		end
	end
	St.Live = live
	-- clumps that stopped moving rest exactly at their rest pose
	local was = St.Moving
	local still = {}
	for _, i in ipairs(moving) do
		still[i] = true
	end
	for _, i in ipairs(was) do
		if not still[i] and St.Inst[i] then
			place(i, St.Inst[i], 0)
		end
	end
	flush()
	St.Moving = moving
	if budget <= 0 then
		St.LastCam = nil -- more to spawn: run again next frame
	end
end

function MeadowFx.Step(dt)
	dt = tonumber(dt) or 0
	if dt <= 0 then
		return
	end
	St.Time = St.Time + dt
	St.RefreshAcc = St.RefreshAcc + dt
	local cam = cameraPos()
	if St.RefreshAcc >= K.REFRESH or St.LastCam == nil or (cam and St.LastCam and (cam - St.LastCam).Magnitude >= K.MOVE) then
		refresh(St.RefreshAcc >= K.REFRESH)
		St.RefreshAcc = 0
	end
	if St.Quality == "Low" then
		return
	end
	local fade = St.Fade
	for _, i in ipairs(St.Moving) do
		local inst = St.Inst[i]
		if inst then
			place(i, inst, tiltOf(i, fade[i] or 1))
		end
	end
	flush()
end

function MeadowFx.Stats()
	local mesh, parts = 0, 0
	for _, inst in pairs(St.Inst) do
		if inst.Mesh then
			mesh = mesh + 1
		end
		parts = parts + #inst.Parts
	end
	return { Clumps = St.N, Shown = St.Shown, Moving = #St.Moving, Mesh = mesh, Parts = parts, Writes = St.Writes,
		Quality = St.Quality, Time = St.Time, Spawned = St.Spawned }
end

function MeadowFx.Stop()
	for _, c in ipairs(St.Conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	St.Conns = {}
	clearAll()
	destroyPools()
	if St.Holder then
		St.Holder:Destroy()
		St.Holder = nil
	end
	St.Folder = nil
	St.N = 0
	St.Lib = nil
	St.Quality0 = nil
	St.LastCam = nil
	St.Started = false
end

function MeadowFx.Init()
	if St.Started then
		return
	end
	St.Started = true
	meshLib()
	St.Conns[#St.Conns + 1] = RunService.Heartbeat:Connect(MeadowFx.Step)
	refresh(true)
end

return MeadowFx
