-- PortalFxController (client, Phase 6): the gates come alive. Every gate WorldStyle.BuildGate builds (a Model with the
-- attribute GateId: the Gate Court's Obby / Dungeon / Ring / Arena / Altar gates, the arena's Return gate, the Dungeon
-- portal) gets a slow, soft, looping animation on the client only:
--   * Glow (the Neon ring)   a soft light runs round the ring (one lap in RING_PERIOD s, a wide cos^3 bump) on top of
--                            the gate's breath: the Neon colour eases toward white and back, so the ring seems to turn
--   * Swirl (the translucent disc)  breathes: its transparency and lightness swell and settle in a ripple that starts in
--                            the middle and runs outward (the swirl strips are timed by their distance from the centre)
--   * Gem / StarGem          twinkle one after another, left to right, then rest (a smooth bell, never a flash)
--   * GlowCore.GateLight     a soft brightness pulse with the breath
--   * GlowCore.Sparkles      drift gently upward (a small Acceleration while the gate is animated)
-- Rules: no Part is created, moved or resized (collision parts, prompt anchors and the stone / frame / trim voxels that
-- become Blender meshes, ML_Dress, are never touched; a Neon part that MeshLibrary hides for a mesh is skipped); only
-- Color / Transparency of those Neon parts, the light's Brightness and the emitter's Acceleration change, and every one
-- goes back to the value the server built when the gate stops animating. Cheap: ONE Heartbeat connection for all gates,
-- updates at UPDATE_HZ, at most MAX_ACTIVE gates (the nearest within RANGE studs of the camera), colours come from ramps
-- built once per part (no allocation per frame), and a property is written only when its value changes. Low graphics
-- (GraphicsQuality "Low") = static: everything restored, no updates. Streaming: gates are found by GateId as they
-- arrive (workspace.DescendantAdded), parts that stream into a gate later rescan it, removed gates are forgotten.
--
--   PortalFxController.Init()        idempotent (Main.client.lua starts it)
--   PortalFxController.Stop()        disconnects everything and restores every gate
--   PortalFxController.Stats() -> { Gates, Active, Parts, Writes, Time, Quality }
--   PortalFxController.Gate(model) -> the record of a tracked gate (tests) | nil
--   PortalFxController.K             the tuning numbers (tests read them)
--   PortalFxController.Flare(model, seconds) -> bool   wave 5 (bug #15): the Dungeon entrance: the ring and the light
--                                    flare up and settle over `seconds` (the same properties, restored as always);
--                                    false for an untracked / static gate (Low graphics)
-- Plain Lua 5.1-compatible syntax only.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PortalFx = {}

local K = {
	RANGE = 150, -- studs from the camera: farther gates stand still
	RANGE_OUT = 165, -- ... an animated gate stops only past this (no flicker at the edge)
	MAX_ACTIVE = 8, -- at most this many gates animate at once (the nearest)
	UPDATE_HZ = 30, -- property updates per second (the motion is slow: 30 Hz reads perfectly smooth)
	REFRESH = 0.5, -- seconds between two passes that pick the active gates, rescan and read the graphics quality
	FADE_IN = 0.8, -- seconds a gate takes to ease into its animation
	STEPS = 32, -- colour ramp steps per part
	-- the breath of the whole gate (swirl, light, the ring's base)
	BREATH_PERIOD = 3.6,
	-- the glow ring: a soft light running round it
	RING_PERIOD = 4.8, -- seconds per lap
	RING_LIFT = 0.5, -- the crest of the running light: this far toward white
	RING_BREATH = 0.1, -- the breath adds up to this much
	RING_POWER = 4, -- the bump's sharpness (cos^p over half the ring)
	-- the swirl: transparency and lightness swell outward from the middle
	SWIRL_AMP = 0.14, -- transparency +- this around the built value
	SWIRL_LIFT = 0.32,
	SWIRL_RIPPLE = 0.32, -- radians of delay per stud from the centre
	-- gems: twinkle in turn
	GEM_PERIOD = 4.2, -- one sweep over all gems, then rest
	GEM_SPACING = 0.32, -- seconds between two gems
	GEM_TWINKLE = 0.9, -- seconds one twinkle lasts
	GEM_LIFT = 0.6,
	-- the light pulse
	LIGHT_AMP = 0.22, -- brightness x (1 +- this)
	-- wave 5 (bug #15): the entrance flare (PortalFx.Flare): the ring toward white, the light brighter, settling
	FLARE_RING = 0.6,
	FLARE_LIGHT = 1.2, -- brightness + LightBase x this at the peak
	-- the sparkles drift upward while the gate is animated
	SPARKLE_RISE = Vector3.new(0, 1.1, 0),
}
PortalFx.K = K

local WHITE = Color3.new(1, 1, 1)
local TWO_PI = math.pi * 2
local GEM_NAMES = { Gem = true, StarGem = true }

local St = {
	Started = false,
	Gates = {}, -- [model] = record
	Count = 0,
	Active = {}, -- array of active records
	Conns = {},
	Time = 0, -- accumulated Heartbeat time (deterministic in tests)
	Acc = 0, -- time since the last property update
	RefreshAcc = 0,
	Quality = "High",
	Writes = 0, -- property writes so far (tests / profiling)
	Quality0 = nil, -- GraphicsQuality module (lazy)
	Vortex0 = nil, -- client/PortalVortex (lazy)
	TextureIds = {}, -- shared/TextureIds: empty = the fallback vortex (effects only)
	Folder = nil, -- workspace.PortalFxLocal: the client-only vortex planes
	Built = 0, -- vortices built so far (tests: built once per gate)
}
PortalFx._St = St

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function smooth01(x)
	if x <= 0 then
		return 0
	elseif x >= 1 then
		return 1
	end
	return x * x * (3 - 2 * x)
end

-- a deterministic phase offset per gate id (gates do not breathe in unison)
local function phaseOf(id)
	local h = 0
	id = tostring(id or "")
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 100003
	end
	return (h % 1000) / 1000 * TWO_PI
end

local function ramp(base, lift)
	local list = {}
	for i = 0, K.STEPS do
		list[i] = base:Lerp(WHITE, lift * i / K.STEPS)
	end
	return list
end

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

-- A part MeshLibrary hides for a Blender mesh (inside ML_Mesh, or under an ML_DressKey target that does not keep it)
-- or one that is already invisible is left alone.
local function skipPart(part, model)
	if part.Transparency >= 0.99 then
		return true
	end
	local node = part
	while node and node ~= model.Parent do
		if node.Name == "ML_Mesh" then
			return true
		end
		local key = node:GetAttribute("ML_DressKey")
		if key ~= nil or CollectionService:HasTag(node, "ML_Dress") then
			local keep = tostring(node:GetAttribute("ML_Keep") or "")
			local kept = false
			for name in string.gmatch(keep, "[^,]+") do
				if name == part.Name then
					kept = true
				end
			end
			if not kept then
				return true
			end
		end
		if node == model then
			break
		end
		node = node.Parent
	end
	return false
end

----------------------------------------------------------------------
-- one gate
----------------------------------------------------------------------

-- the Neon ring, gems, light and sparkles back to their built values (the swirl and the vortex are separate)
local function restoreNeon(rec)
	for _, e in ipairs(rec.Ring) do
		if e.Part.Parent then
			e.Part.Color = e.Base
		end
		e.Last = -1
	end
	for _, e in ipairs(rec.Gems) do
		if e.Part.Parent then
			e.Part.Color = e.Base
		end
		e.Last = -1
	end
	if rec.Light and rec.Light.Parent then
		rec.Light.Brightness = rec.LightBase
	end
	rec.LastLight = -1
	if rec.Emitter and rec.Emitter.Parent and rec.EmitterBase ~= nil then
		pcall(function()
			rec.Emitter.Acceleration = rec.EmitterBase
		end)
	end
	rec.Rising = false
end

local function restoreSwirl(rec)
	for _, e in ipairs(rec.Swirl) do
		if e.Part.Parent then
			e.Part.Color = e.Base
			e.Part.Transparency = e.BaseT
		end
		e.Last = -1
		e.LastT = -1
	end
	rec.SwirlLook = nil
end

local function vortexModule()
	if St.Vortex0 == nil then
		St.Vortex0 = false
		local client = script.Parent and script.Parent.Parent
		local module = client and client:FindFirstChild("PortalVortex")
		if module then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" and type(mod.Build) == "function" then
				St.Vortex0 = mod
			end
		end
	end
	return St.Vortex0 or nil
end

-- everything back to the server's build: the Neon parts, the swirl, and the vortex hidden
local function restore(rec)
	restoreNeon(rec)
	restoreSwirl(rec)
	local V = vortexModule()
	if V and rec.Vortex then
		V.Show(rec.Vortex, false)
	end
	rec.Shown = false
	rec.StaticDone = false
end

local function dropVortex(rec)
	local V = vortexModule()
	if V and rec.Vortex then
		V.Destroy(rec.Vortex)
	end
	rec.Vortex = nil
end

-- (re)collects the animated parts of a gate; the gate is restored first so every base value is the built one
local function scan(rec)
	restore(rec)
	local model = rec.Model
	rec.Ring, rec.Swirl, rec.Gems = {}, {}, {}
	rec.Light, rec.Emitter, rec.EmitterBase = nil, nil, nil
	local core = model:FindFirstChild("GlowCore")
	if core and not core:IsA("BasePart") then
		core = nil
	end
	local origin = core and core.CFrame or nil
	if not origin then
		local ok, pivot = pcall(function()
			return model:GetPivot()
		end)
		origin = ok and pivot or CFrame.new()
		origin = origin * CFrame.new(0, 11.5, 0)
	end
	rec.Center = origin.Position
	rec.Origin = origin
	dropVortex(rec)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon and (d.Name == "Glow" or d.Name == "Swirl" or GEM_NAMES[d.Name]) and not skipPart(d, model) then
			local lp = origin:PointToObjectSpace(d.Position)
			if d.Name == "Glow" then
				local angle = math.atan2(lp.Y, lp.X)
				rec.Ring[#rec.Ring + 1] = { Part = d, Base = d.Color, Ramp = ramp(d.Color, K.RING_LIFT + K.RING_BREATH), Angle = angle, Last = -1 }
			elseif d.Name == "Swirl" then
				local dist = math.sqrt(lp.X * lp.X + lp.Y * lp.Y)
				rec.Swirl[#rec.Swirl + 1] = { Part = d, Base = d.Color, BaseT = d.Transparency, Ramp = ramp(d.Color, K.SWIRL_LIFT), Dist = dist, Last = -1, LastT = -1 }
			else
				rec.Gems[#rec.Gems + 1] = { Part = d, Base = d.Color, Ramp = ramp(d.Color, K.GEM_LIFT), X = lp.X, Y = lp.Y, Last = -1 }
			end
		end
	end
	-- gems twinkle left -> right as seen from the plaza (the gate looks along -Z, so its +X is the viewer's left),
	-- then bottom -> top
	table.sort(rec.Gems, function(a, b)
		if math.abs(a.X - b.X) > 0.25 then
			return a.X > b.X
		end
		return a.Y < b.Y
	end)
	for i, e in ipairs(rec.Gems) do
		e.Index = i
	end
	if core then
		local light = core:FindFirstChild("GateLight")
		if light and light:IsA("Light") then
			rec.Light = light
			rec.LightBase = light.Brightness
		end
		local emitter = core:FindFirstChild("Sparkles")
		if emitter and emitter:IsA("ParticleEmitter") then
			rec.Emitter = emitter
			local ok, accel = pcall(function()
				return emitter.Acceleration
			end)
			rec.EmitterBase = (ok and typeof(accel) == "Vector3") and accel or nil
		end
	end
	rec.Parts = #rec.Ring + #rec.Swirl + #rec.Gems
	rec.Dirty = false
end

local function forget(model)
	local rec = St.Gates[model]
	if not rec then
		return
	end
	restore(rec)
	dropVortex(rec)
	for _, c in ipairs(rec.Conns) do
		c:Disconnect()
	end
	rec.Conns = {}
	St.Gates[model] = nil
	St.Count = St.Count - 1
	for i = #St.Active, 1, -1 do
		if St.Active[i] == rec then
			table.remove(St.Active, i)
		end
	end
end

local function track(model)
	if St.Gates[model] or not model:IsA("Model") or model:GetAttribute("GateId") == nil then
		return
	end
	local rec = {
		Model = model,
		Id = tostring(model:GetAttribute("GateId")),
		Ring = {}, Swirl = {}, Gems = {},
		Conns = {},
		Dirty = true,
		Fade = 0,
		Shown = false,
		Rising = false,
		LastLight = -1,
	}
	rec.Phase = phaseOf(rec.Id)
	St.Gates[model] = rec
	St.Count = St.Count + 1
	local function dirty(d)
		if d:IsA("BasePart") or d:IsA("Light") or d:IsA("ParticleEmitter") then
			rec.Dirty = true
		end
	end
	rec.Conns[#rec.Conns + 1] = model.DescendantAdded:Connect(dirty)
	rec.Conns[#rec.Conns + 1] = model.DescendantRemoving:Connect(dirty)
	rec.Conns[#rec.Conns + 1] = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			forget(model)
		end
	end)
	scan(rec)
end

----------------------------------------------------------------------
-- the animation (pure functions of the time; tests read them)
----------------------------------------------------------------------

function PortalFx.Breath(t, phase)
	return 0.5 + 0.5 * math.sin(TWO_PI * t / K.BREATH_PERIOD + (phase or 0))
end

-- 0..1 lift of a ring part at `angle` (radians) at time t
function PortalFx.RingLevel(t, angle, phase)
	local head = TWO_PI * t / K.RING_PERIOD + (phase or 0)
	local c = math.cos(angle - head) -- runs clockwise as seen from the plaza
	local bump = c > 0 and c ^ K.RING_POWER or 0
	local total = K.RING_LIFT + K.RING_BREATH
	return (K.RING_LIFT * bump + K.RING_BREATH * PortalFx.Breath(t, phase)) / total
end

-- 0..1 swell of a swirl strip `dist` studs from the centre
function PortalFx.SwirlLevel(t, dist, phase)
	return 0.5 + 0.5 * math.sin(TWO_PI * t / K.BREATH_PERIOD + (phase or 0) - K.SWIRL_RIPPLE * (dist or 0))
end

-- 0..1 twinkle of gem `index` (1-based) of `count`
function PortalFx.GemLevel(t, index, count, phase)
	local period = math.max(K.GEM_PERIOD, (count or 1) * K.GEM_SPACING + K.GEM_TWINKLE)
	local local_t = (t + (phase or 0) / TWO_PI * period) % period
	local start = ((index or 1) - 1) * K.GEM_SPACING
	local x = (local_t - start) / K.GEM_TWINKLE
	if x <= 0 or x >= 1 then
		return 0
	end
	local s = math.sin(math.pi * x)
	return smooth01(s * s)
end

local function setColor(e, level, fade)
	local i = math.floor(level * fade * K.STEPS + 0.5)
	if i < 0 then
		i = 0
	elseif i > K.STEPS then
		i = K.STEPS
	end
	if i ~= e.Last then
		e.Last = i
		e.Part.Color = e.Ramp[i]
		St.Writes = St.Writes + 1
	end
end

local NONE = {}

-- the old swirl's look while the vortex shows (written once)
local function applySwirlLook(rec, V)
	if rec.SwirlLook then
		return
	end
	local look = V.SwirlLook(rec.Vortex)
	rec.SwirlLook = look
	for _, e in ipairs(rec.Swirl) do
		if e.Part.Parent then
			e.Part.Color = look.Color
			e.Part.Transparency = look.Transparency
			St.Writes = St.Writes + 2
		end
		e.Last = -1
		e.LastT = -1
	end
end

-- the gate colour: the average of its glow ring (the arch glows violet under gold)
local function gateColor(rec)
	local r, g, b, n = 0, 0, 0, 0
	for _, e in ipairs(rec.Ring) do
		r, g, b, n = r + e.Base.R, g + e.Base.G, b + e.Base.B, n + 1
	end
	if n == 0 then
		for _, e in ipairs(rec.Swirl) do
			r, g, b, n = r + e.Base.R, g + e.Base.G, b + e.Base.B, n + 1
		end
	end
	if n == 0 then
		return Color3.fromRGB(150, 120, 255)
	end
	return Color3.new(r / n, g / n, b / n)
end

local function localFolder()
	local f = St.Folder
	if f and f.Parent then
		return f
	end
	f = Instance.new("Folder")
	f.Name = "PortalFxLocal" -- client-only: created here, never replicated
	f.Parent = Workspace
	St.Folder = f
	return f
end

-- the vortex of a gate, built once (lazily, when it first animates) and shown
local function ensureVortex(rec)
	local V = vortexModule()
	if not V or #rec.Swirl == 0 then
		return nil
	end
	if not rec.Vortex then
		local ok, v = pcall(V.Build, rec, localFolder(), St.TextureIds, gateColor(rec), math.floor(rec.Phase * 100000) + 7)
		if not ok then
			warn("[PortalFxController] vortex for " .. rec.Id .. ": " .. tostring(v))
			rec.Swirl = rec.Swirl -- keep the plain animation
			return nil
		end
		rec.Vortex = v
		St.Built = St.Built + 1
	end
	V.SetStatic(rec.Vortex, St.Quality == "Low")
	V.Show(rec.Vortex, true)
	return rec.Vortex
end

local function animate(rec, t)
	local fade = smooth01(rec.Fade)
	local phase = rec.Phase
	local flare = 0
	if rec.FlareAt then
		local p = (os.clock() - rec.FlareAt) / rec.FlareDur
		if p >= 1 or p < 0 then
			rec.FlareAt = nil
		else
			flare = 1 - p
		end
	end
	for _, e in ipairs(rec.Ring) do
		setColor(e, math.min(1, PortalFx.RingLevel(t, e.Angle, phase) + K.FLARE_RING * flare), fade)
	end
	local V = rec.Vortex and vortexModule()
	if V and rec.Vortex.Shown then
		applySwirlLook(rec, V)
		St.Writes = St.Writes + V.Animate(rec.Vortex, t, fade, PortalFx.Breath(t, phase), false)
	end
	for _, e in ipairs((V and rec.Vortex.Shown) and NONE or rec.Swirl) do
		local level = PortalFx.SwirlLevel(t, e.Dist, phase)
		setColor(e, level, fade)
		-- more solid at the swell, clearer between (quantised to 0.01 so a write happens only on a change)
		local tr = e.BaseT + K.SWIRL_AMP * fade * (1 - 2 * level)
		tr = math.floor(tr * 100 + 0.5) / 100
		if tr ~= e.LastT then
			e.LastT = tr
			e.Part.Transparency = tr
			St.Writes = St.Writes + 1
		end
	end
	local n = #rec.Gems
	for _, e in ipairs(rec.Gems) do
		setColor(e, PortalFx.GemLevel(t, e.Index, n, phase), fade)
	end
	if rec.Light then
		local b = rec.LightBase * (1 + K.LIGHT_AMP * fade * (2 * PortalFx.Breath(t, phase) - 1) + K.FLARE_LIGHT * flare)
		b = math.floor(b * 200 + 0.5) / 200
		if b ~= rec.LastLight then
			rec.LastLight = b
			rec.Light.Brightness = b
			St.Writes = St.Writes + 1
		end
	end
	if rec.Emitter and rec.EmitterBase ~= nil and not rec.Rising then
		rec.Rising = true
		pcall(function()
			rec.Emitter.Acceleration = K.SPARKLE_RISE
		end)
	end
	rec.Shown = true
end

----------------------------------------------------------------------
-- the loop
----------------------------------------------------------------------

local function viewPoint()
	local cam = Workspace.CurrentCamera
	if cam then
		return cam.CFrame.Position
	end
	return nil
end

-- picks the active gates (nearest first, within range, at most MAX_ACTIVE), rescans dirty ones, reads the quality
local function refresh()
	St.Quality = quality()
	local eye = viewPoint()
	local wanted = {}
	for model, rec in pairs(St.Gates) do
		if model.Parent == nil or not model:IsDescendantOf(Workspace) then
			forget(model)
		else
			if rec.Dirty then
				scan(rec)
			end
			local d = math.huge
			if eye and rec.Center then
				d = (rec.Center - eye).Magnitude
			end
			rec.Dist = d
			local limit = rec.On and K.RANGE_OUT or K.RANGE
			if d <= limit and rec.Parts > 0 then
				wanted[#wanted + 1] = rec
			end
		end
	end
	table.sort(wanted, function(a, b)
		return a.Dist < b.Dist
	end)
	local keep = {}
	for i = 1, math.min(#wanted, K.MAX_ACTIVE) do
		keep[wanted[i]] = true
	end
	for _, rec in pairs(St.Gates) do
		if keep[rec] then
			if not rec.On then
				rec.On = true
				rec.Fade = 0
			end
			local low = St.Quality == "Low"
			if low ~= rec.Low then
				rec.Low = low
				rec.StaticDone = false
				restoreNeon(rec) -- Low: the ring, gems and light hold their built values
				rec.SwirlLook = nil
			end
			ensureVortex(rec)
		elseif rec.On then
			rec.On = false
			rec.Fade = 0
			restore(rec)
		end
	end
	local active = {}
	for i = 1, math.min(#wanted, K.MAX_ACTIVE) do
		active[i] = wanted[i]
	end
	St.Active = active
end

function PortalFx.Step(dt)
	dt = tonumber(dt) or 0
	if dt <= 0 then
		return
	end
	St.Time = St.Time + dt
	St.RefreshAcc = St.RefreshAcc + dt
	if St.RefreshAcc >= K.REFRESH then
		St.RefreshAcc = 0
		refresh()
	end
	St.Acc = St.Acc + dt
	if St.Acc < 1 / K.UPDATE_HZ then
		return
	end
	local step = St.Acc
	St.Acc = 0
	for _, rec in ipairs(St.Active) do
		if rec.On and rec.Model.Parent then
			if rec.Low then
				-- Low graphics: a still vortex (posed once), no other motion
				if not rec.StaticDone then
					rec.StaticDone = true
					local V = rec.Vortex and vortexModule()
					if V then
						applySwirlLook(rec, V)
						St.Writes = St.Writes + V.Animate(rec.Vortex, 0, 1, 0.5, true)
					end
				end
			else
				rec.Fade = math.min(1, rec.Fade + step / K.FADE_IN)
				animate(rec, St.Time)
			end
		end
	end
end

function PortalFx.Stats()
	local parts = 0
	for _, rec in pairs(St.Gates) do
		parts = parts + (rec.Parts or 0)
	end
	local shown, mode = 0, nil
	for _, rec in pairs(St.Gates) do
		if rec.Vortex and rec.Vortex.Shown then
			shown = shown + 1
			mode = rec.Vortex.Mode
		end
	end
	return { Gates = St.Count, Active = #St.Active, Parts = parts, Writes = St.Writes, Time = St.Time, Quality = St.Quality,
		Vortices = shown, VortexMode = mode, Built = St.Built }
end

function PortalFx.Gate(model)
	return St.Gates[model]
end

-- wave 5 (bug #15): the gate flares up (the Dungeon entrance's rush); a static gate (Low, out of range) does nothing
function PortalFx.Flare(model, seconds)
	local rec = St.Gates[model]
	if not rec or St.Quality == "Low" or not rec.On then
		return false
	end
	rec.FlareAt = os.clock()
	rec.FlareDur = (type(seconds) == "number" and seconds > 0) and math.min(seconds, 3) or 0.6
	return true
end

function PortalFx.Stop()
	for _, c in ipairs(St.Conns) do
		c:Disconnect()
	end
	St.Conns = {}
	local models = {}
	for model in pairs(St.Gates) do
		models[#models + 1] = model
	end
	for _, model in ipairs(models) do
		forget(model)
	end
	St.Active = {}
	St.Started = false
	if St.Folder then
		St.Folder:Destroy()
		St.Folder = nil
	end
end

-- the vortex texture ids (shared/TextureIds; tests pass fake ones): every vortex is rebuilt in the new mode
function PortalFx.SetTextureIds(ids)
	St.TextureIds = type(ids) == "table" and ids or {}
	for _, rec in pairs(St.Gates) do
		restoreSwirl(rec)
		dropVortex(rec)
	end
	St.RefreshAcc = K.REFRESH
end

function PortalFx.Init()
	if St.Started then
		return
	end
	St.Started = true
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	local idsModule = shared and shared:FindFirstChild("TextureIds")
	if idsModule then
		local ok, ids = pcall(require, idsModule)
		St.TextureIds = (ok and type(ids) == "table") and ids or {}
	end
	St.Conns[#St.Conns + 1] = Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") and inst:GetAttribute("GateId") ~= nil then
			track(inst)
		end
	end)
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") and inst:GetAttribute("GateId") ~= nil then
			track(inst)
		end
	end
	St.Conns[#St.Conns + 1] = RunService.Heartbeat:Connect(PortalFx.Step)
	refresh()
end

return PortalFx
