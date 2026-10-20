-- PortalVortex (client, Phase 6 W2b): the magical swirling vortex inside a gate's hoop (the player's reference: spiral
-- arms turning into a deep centre, a bright glowing rim with small lightning crackles, thin light streaks pulled
-- inward), in the gate's own colour and bright enough for the cute voxel world. PortalFxController owns WHEN (which
-- gates, distance, quality); this module owns WHAT. Two modes, chosen per gate when it is built:
--   "Texture"   every key of K.TEXTURE_KEYS has an id in shared/TextureIds (tools/upload_assets.py --textures fills it):
--               a SurfaceGui (LightInfluence 0, Brightness 2, AlwaysOnTop false) on an invisible client plane inside
--               the ring holding the layers of blender/textures/build_vortex.py: the disc, the deep core, the broad arms
--               and the fine streaks turning at two speeds (clockwise: they flow inward), two streak layers shrinking to
--               the centre in turn, the rim breathing, four lightning frames that flicker softly at seeded random times;
--               a second, simpler SurfaceGui on the back face (disc, arms, rim)
--   "Fallback"  no ids yet (today): the same look from effects only: two invisible client spinner parts with curved
--               Beam spiral arms (broad + fine, two speeds), a ParticleEmitter of light streaks pulled to the centre
--               (Disc, Inward, VelocityParallel + Squash), a rim crackle emitter bursting at seeded random times, and
--               the old Neon swirl recoloured deep as the backdrop
-- Everything is created ONCE per gate (an invisible, anchored, non-colliding, non-querying, non-touching client part:
-- nothing replicates), disabled when the gate stops animating and destroyed with Destroy. No part of the gate itself is
-- moved, resized or re-parented. Per frame only numbers change (rotations, transparencies, the spinners' CFrame) and
-- every value is quantised and written only on a change. Plain Lua 5.1-compatible syntax only.
--
--   PortalVortex.Mode(ids) -> "Texture" | "Fallback"
--   PortalVortex.Layout(rec, mode) -> { Center = CFrame, Radius, Arch, Behind }   (from the gate's Swirl parts; tests)
--   PortalVortex.Build(rec, folder, ids, color, seed) -> v
--   PortalVortex.Show(v, on)            PortalVortex.Animate(v, t, fade, static)        PortalVortex.Destroy(v)
--   PortalVortex.SwirlLook(v) -> { Color, Transparency }   what the gate's old Swirl parts show while the vortex does

local PortalVortex = {}

local K = {
	TEXTURE_KEYS = { "vortex_disc", "vortex_core", "vortex_arms", "vortex_fine", "vortex_streaks", "vortex_rim" },
	CRACKLES = { "vortex_crackle_1", "vortex_crackle_2", "vortex_crackle_3", "vortex_crackle_4" },
	CANVAS = 512,
	BRIGHTNESS = 2,
	RIM_PAD = 0.8, -- studs the disc reaches under the glow ring past the swirl's edge
	ARMS_SPEED = 26, -- degrees per second (clockwise = inward)
	FINE_SPEED = 48,
	STREAK_PERIOD = 1.8, -- seconds a streak layer takes from the rim to the centre
	STREAK_SPIN = 64,
	CRACKLE_GAP = { 0.7, 2.2 }, -- seconds between two crackles (seeded)
	CRACKLE_LIFE = 0.42, -- fade in 0.08, hold, fade out
	BREATH_PERIOD = 3.6,
	-- fallback
	ARMS = 6,
	FINE = 9,
	ARM_SWEEP = 2.8, -- radians an arm winds from the rim to the centre
	FINE_SWEEP = 3.4,
	STREAK_RATE = 20,
	CRACKLE_BURST = { 4, 7 },
}
PortalVortex.K = K

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TWO_PI = math.pi * 2

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function try(inst, key, value)
	pcall(function()
		inst[key] = value
	end)
end

-- a deterministic random stream (no shared global state; tests replay it)
local function stream(seed)
	local s = math.floor(tonumber(seed) or 1) % 2147483646 + 1
	return function()
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

-- the gate colour made vivid (the gates' pastel accents look grey once darkened)
local function vivid(color)
	local ok, h, sat, val = pcall(function()
		return color:ToHSV()
	end)
	if not ok or type(h) ~= "number" then
		return color
	end
	return Color3.fromHSV(h, math.max(sat, 0.72), math.max(val, 0.92))
end

local function tints(color)
	local c = vivid(color)
	return {
		deep = c:Lerp(BLACK, 0.42),
		core = c:Lerp(BLACK, 0.78),
		arm = c:Lerp(WHITE, 0.22),
		fine = c:Lerp(WHITE, 0.72),
		spark = c:Lerp(WHITE, 0.88),
		rim = c:Lerp(WHITE, 0.62),
	}
end

function PortalVortex.Mode(ids)
	if type(ids) ~= "table" then
		return "Fallback"
	end
	for _, key in ipairs(K.TEXTURE_KEYS) do
		local id = ids[key]
		if type(id) ~= "number" or id <= 0 then
			return "Fallback"
		end
	end
	return "Texture"
end

-- where the vortex sits: the middle of the gate's Swirl parts (in the GlowCore's frame). Behind = the textured disc of a
-- hoop: the old swirl is hidden and the disc sits inside the swirl's voxel layer, reaching just under the glow ring
-- (the ring's front faces cover its edge). Otherwise (the effects-only fallback, or the crowned arch whose taller
-- opening keeps the old swirl as backdrop) the vortex floats just in front of the swirl and stays inside its edge.
function PortalVortex.Layout(rec, mode)
	local origin = rec.Origin or CFrame.new()
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, e in ipairs(rec.Swirl or {}) do
		local p = e.Part
		local lp = origin:PointToObjectSpace(p.Position)
		local hx, hy = p.Size.X / 2, p.Size.Y / 2
		x0, x1 = math.min(x0, lp.X - hx), math.max(x1, lp.X + hx)
		y0, y1 = math.min(y0, lp.Y - hy), math.max(y1, lp.Y + hy)
	end
	local cx, cy, w, h = 0, 0, 11, 11
	if x0 < x1 and y0 < y1 then
		cx, cy, w, h = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
	end
	local arch = rec.Model and rec.Model:GetAttribute("GateShape") == "Arch" or (h - w) > 1.5
	arch = arch and true or false
	local behind = mode == "Texture" and not arch
	local radius = math.min(w, h) / 2 + (behind and K.RIM_PAD or 0)
	return { Center = origin * CFrame.new(cx, cy, behind and -0.1 or -0.6), Radius = radius, Arch = arch, Behind = behind }
end

local function plane(folder, name, cf, radius)
	return make("Part", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Massless = true,
		Transparency = 1,
		Size = Vector3.new(radius * 2, radius * 2, 0.05),
		CFrame = cf,
	}, folder)
end

----------------------------------------------------------------------
-- texture mode
----------------------------------------------------------------------

local LAYERS = {
	{ Name = "Disc", Key = "vortex_disc", Tint = "deep", Z = 1 },
	{ Name = "Core", Key = "vortex_core", Tint = "core", Z = 2, T = 0.12 },
	{ Name = "Arms", Key = "vortex_arms", Tint = "arm", Z = 3, Spin = "ARMS_SPEED" },
	{ Name = "Fine", Key = "vortex_fine", Tint = "fine", Z = 4, Spin = "FINE_SPEED", Rot0 = 40, T = 0.12 },
	{ Name = "StreaksA", Key = "vortex_streaks", Tint = "spark", Z = 5, Flow = 0 },
	{ Name = "StreaksB", Key = "vortex_streaks", Tint = "spark", Z = 5, Flow = 0.5 },
	{ Name = "Rim", Key = "vortex_rim", Tint = "rim", Z = 6, Breath = true },
}
local BACK_LAYERS = { Disc = true, Arms = true, Rim = true }
PortalVortex.LAYERS = LAYERS

local function label(gui, spec, id, tint)
	return make("ImageLabel", {
		Name = spec.Name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Image = "rbxassetid://" .. tostring(id),
		ImageColor3 = tint,
		ImageTransparency = spec.T or 0,
		Rotation = spec.Rot0 or 0,
		ZIndex = spec.Z,
	}, gui)
end

local function surface(part, face, name)
	local gui = make("SurfaceGui", {
		Name = name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(K.CANVAS, K.CANVAS),
		LightInfluence = 0,
		Brightness = K.BRIGHTNESS,
		AlwaysOnTop = false,
		ClipsDescendants = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Adornee = part,
		Enabled = false,
	}, part)
	return gui
end

local function buildTexture(v, ids, tint)
	v.Front = surface(v.Plane, Enum.NormalId.Front, "VortexFront")
	v.Back = surface(v.Plane, Enum.NormalId.Back, "VortexBack")
	v.Layers, v.BackLayers, v.Crackles = {}, {}, {}
	for _, spec in ipairs(LAYERS) do
		local entry = { Spec = spec, Label = label(v.Front, spec, ids[spec.Key], tint[spec.Tint]), Base = spec.T or 0 }
		entry.Last = { Rotation = spec.Rot0 or 0, T = entry.Base, S = 1 }
		v.Layers[#v.Layers + 1] = entry
		if BACK_LAYERS[spec.Name] then
			local b = { Spec = spec, Label = label(v.Back, spec, ids[spec.Key], tint[spec.Tint]), Base = spec.T or 0 }
			b.Last = { Rotation = spec.Rot0 or 0, T = b.Base, S = 1 }
			v.BackLayers[#v.BackLayers + 1] = b
		end
	end
	for i, key in ipairs(K.CRACKLES) do
		local id = ids[key]
		if type(id) == "number" and id > 0 then
			local spec = { Name = "Crackle" .. i, Z = 7, T = 1 }
			local l = label(v.Front, spec, id, tint.spark)
			l.Visible = false
			v.Crackles[#v.Crackles + 1] = { Label = l, Last = 1 }
		end
	end
end

----------------------------------------------------------------------
-- fallback mode (effects only)
----------------------------------------------------------------------

-- one spiral arm from the rim to the centre as a cubic Bezier Beam (exact for the spiral's own tangents)
local function arm(part, i, n, radius, sweep, width0, width1, color, transparency, emission, name)
	local a0 = TWO_PI * (i - 1) / n
	local r0, r1 = radius * 0.9, radius * 0.1
	local k = math.log(r1 / r0)
	local function point(s)
		local r = r0 * math.exp(k * s)
		local th = a0 + sweep * s
		return Vector3.new(r * math.cos(th), r * math.sin(th), 0), r, th
	end
	local function tangent(s)
		local _, r, th = point(s)
		local dr = r * k
		return Vector3.new(dr * math.cos(th) - r * sweep * math.sin(th), dr * math.sin(th) + r * sweep * math.cos(th), 0)
	end
	local p0, p3 = point(0), point(1)
	local d0, d3 = tangent(0) / 3, tangent(1) / 3
	local normal = Vector3.new(0, 0, 1)
	local at0 = make("Attachment", { Name = name .. "A" .. i, CFrame = CFrame.fromMatrix(p0, d0.Unit, normal) }, part)
	local at1 = make("Attachment", { Name = name .. "B" .. i, CFrame = CFrame.fromMatrix(p3, d3.Unit, normal) }, part)
	return make("Beam", {
		Name = name .. i,
		Attachment0 = at0,
		Attachment1 = at1,
		CurveSize0 = d0.Magnitude,
		CurveSize1 = d3.Magnitude,
		FaceCamera = true,
		Segments = 16,
		Width0 = width0,
		Width1 = width1,
		Color = color,
		Transparency = transparency,
		LightEmission = emission,
		LightInfluence = 0,
		Brightness = 1.6,
		Enabled = false,
	}, part)
end

local function buildFallback(v, tint, folder)
	local radius = v.Radius
	v.SpinA = plane(folder, "VortexArms", v.Center, radius)
	v.SpinB = plane(folder, "VortexFine", v.Center, radius)
	v.Beams = {}
	local armColor = ColorSequence.new(tint.arm, tint.fine)
	local armT = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.3, 0.12),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	for i = 1, K.ARMS do
		v.Beams[#v.Beams + 1] = arm(v.SpinA, i, K.ARMS, radius, K.ARM_SWEEP, radius * 0.19, 0.12, armColor, armT, 0.7, "Arm")
	end
	local fineColor = ColorSequence.new(tint.fine, tint.spark)
	local fineT = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.4, 0.3),
		NumberSequenceKeypoint.new(1, 0.95),
	})
	for i = 1, K.FINE do
		v.Beams[#v.Beams + 1] = arm(v.SpinB, i, K.FINE, radius, K.FINE_SWEEP, radius * 0.06, 0.03, fineColor, fineT, 1, "Fine")
	end
	-- light streaks pulled to the centre
	local streaks = make("ParticleEmitter", {
		Name = "VortexStreaks",
		Rate = K.STREAK_RATE,
		Lifetime = NumberRange.new(0.7, 1.0),
		Speed = NumberRange.new(radius * 0.85, radius * 1.1),
		Size = NumberSequence.new(0.16),
		Color = ColorSequence.new(tint.spark, tint.fine),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
		LightEmission = 1,
		LightInfluence = 0,
		EmissionDirection = Enum.NormalId.Front,
		Enabled = false,
	}, v.Plane)
	try(streaks, "Shape", Enum.ParticleEmitterShape.Disc)
	try(streaks, "ShapeStyle", Enum.ParticleEmitterShapeStyle.Surface)
	try(streaks, "ShapeInOut", Enum.ParticleEmitterShapeInOut.Inward)
	try(streaks, "ShapePartial", 1)
	try(streaks, "Orientation", Enum.ParticleOrientation.VelocityParallel)
	try(streaks, "Squash", NumberSequence.new(1.4))
	try(streaks, "Brightness", 2)
	v.Streaks = streaks
	-- rim crackles: short bright sparks on the rim, emitted in soft bursts
	local crackle = make("ParticleEmitter", {
		Name = "VortexCrackle",
		Rate = 0,
		Lifetime = NumberRange.new(0.12, 0.24),
		Speed = NumberRange.new(0.2, 0.6),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.1) }),
		Color = ColorSequence.new(WHITE, tint.rim),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360),
		LightEmission = 1,
		LightInfluence = 0,
		EmissionDirection = Enum.NormalId.Front,
		Enabled = false,
	}, v.Plane)
	try(crackle, "Shape", Enum.ParticleEmitterShape.Disc)
	try(crackle, "ShapeStyle", Enum.ParticleEmitterShapeStyle.Surface)
	try(crackle, "ShapePartial", 1)
	try(crackle, "Squash", NumberSequence.new(1.8))
	try(crackle, "Brightness", 2)
	v.Crackle = crackle
end

----------------------------------------------------------------------
-- public
----------------------------------------------------------------------

function PortalVortex.Build(rec, folder, ids, color, seed)
	local mode = PortalVortex.Mode(ids)
	local layout = PortalVortex.Layout(rec, mode)
	local tint = tints(color)
	local v = {
		Mode = mode,
		Center = layout.Center,
		Radius = layout.Radius,
		Arch = layout.Arch,
		Behind = layout.Behind,
		Color = color,
		Tint = tint,
		Random = stream(seed),
		NextCrackle = 0.6,
		CrackleAt = -1,
		CrackleIndex = 0,
		Shown = false,
		Static = false,
		LastA = -1,
		LastB = -1,
	}
	v.Plane = plane(folder, "PortalVortex", layout.Center, layout.Radius)
	if v.Mode == "Texture" then
		buildTexture(v, ids, tint)
	else
		buildFallback(v, tint, folder)
	end
	return v
end

-- the old Neon swirl while the vortex shows: hidden behind the textured disc (hoops); a deep backdrop otherwise
function PortalVortex.SwirlLook(v)
	if v.Behind then
		return { Color = v.Tint.deep, Transparency = 1 }
	end
	return { Color = v.Tint.deep, Transparency = v.Mode == "Texture" and 0.55 or 0.3 }
end

function PortalVortex.Show(v, on)
	on = on and true or false
	if not v or v.Shown == on then
		return
	end
	v.Shown = on
	if v.Mode == "Texture" then
		v.Front.Enabled = on
		v.Back.Enabled = on
	else
		for _, b in ipairs(v.Beams) do
			b.Enabled = on
		end
		v.Streaks.Enabled = on and not v.Static
		v.Crackle.Enabled = false
	end
end

-- static = Low graphics: the vortex holds still (no spin, no streaks, no crackles)
function PortalVortex.SetStatic(v, static)
	static = static and true or false
	if not v or v.Static == static then
		return
	end
	v.Static = static
	if v.Mode == "Fallback" then
		v.Streaks.Enabled = v.Shown and not static
	else
		for _, c in ipairs(v.Crackles) do
			c.Label.Visible = false
			c.Last = 1
		end
		v.CrackleAt = -1
	end
end

local function write(entry, key, value)
	if entry.Last[key] ~= value then
		entry.Last[key] = value
		return true
	end
	return false
end

local function q(x, step)
	return math.floor(x / step + 0.5) * step
end

-- the crackle schedule (seeded): -> the index of the crackle to show (or 0) and its opacity 0..1
local function crackle(v, t)
	if t >= v.NextCrackle then
		local gap = K.CRACKLE_GAP
		v.CrackleAt = v.NextCrackle
		v.CrackleIndex = 1 + math.floor(v.Random() * 4) % 4
		v.NextCrackle = v.NextCrackle + gap[1] + (gap[2] - gap[1]) * v.Random()
		if t > v.NextCrackle then
			v.NextCrackle = t + gap[1]
		end
		v.Burst = true
	end
	local age = t - v.CrackleAt
	if v.CrackleAt < 0 or age < 0 or age > K.CRACKLE_LIFE then
		return 0, 0
	end
	local a
	if age < 0.08 then
		a = age / 0.08
	elseif age < 0.2 then
		a = 1
	else
		a = 1 - (age - 0.2) / (K.CRACKLE_LIFE - 0.2)
	end
	return v.CrackleIndex, math.max(0, math.min(1, a))
end

local function animateTexture(v, t, fade, breath)
	local writes = 0
	for _, list in ipairs({ v.Layers, v.BackLayers }) do
		local mirror = list == v.BackLayers and -1 or 1
		for _, e in ipairs(list) do
			local spec = e.Spec
			local rot, tr, sc = spec.Rot0 or 0, e.Base, 1
			if spec.Spin then
				rot = rot + K[spec.Spin] * t * mirror
			elseif spec.Flow then
				local phase = (t / K.STREAK_PERIOD + spec.Flow) % 1
				sc = 1.12 - 0.8 * phase
				local s = math.sin(math.pi * phase)
				tr = 1 - 0.9 * s * s * fade
				rot = K.STREAK_SPIN * t + spec.Flow * 180
			elseif spec.Breath then
				tr = 0.18 * (1 - breath * fade)
				sc = 1 + 0.015 * breath * fade
			elseif spec.Name == "Core" then
				tr = e.Base + 0.08 * breath * fade
			end
			rot = q(rot % 360, 0.5)
			tr = q(tr, 0.01)
			sc = q(sc, 0.005)
			if write(e, "Rotation", rot) then
				e.Label.Rotation = rot
				writes = writes + 1
			end
			if write(e, "T", tr) then
				e.Label.ImageTransparency = tr
				writes = writes + 1
			end
			if write(e, "S", sc) then
				e.Label.Size = UDim2.fromScale(sc, sc)
				writes = writes + 1
			end
		end
	end
	if not v.Static then
		local idx, a = crackle(v, t)
		for i, c in ipairs(v.Crackles) do
			local tr = (i == idx) and q(1 - 0.85 * a * fade, 0.02) or 1
			if tr ~= c.Last then
				c.Last = tr
				c.Label.ImageTransparency = tr
				c.Label.Visible = tr < 1
				writes = writes + 1
			end
		end
	end
	return writes
end

local function animateFallback(v, t)
	local writes = 0
	local a = q((K.ARMS_SPEED * t) % 360, 0.25)
	local b = q((K.FINE_SPEED * t + 23) % 360, 0.25)
	if a ~= v.LastA then
		v.LastA = a
		v.SpinA.CFrame = v.Center * CFrame.Angles(0, 0, -math.rad(a))
		writes = writes + 1
	end
	if b ~= v.LastB then
		v.LastB = b
		v.SpinB.CFrame = v.Center * CFrame.Angles(0, 0, -math.rad(b))
		writes = writes + 1
	end
	if not v.Static then
		crackle(v, t)
		if v.Burst then
			v.Burst = false
			local n = K.CRACKLE_BURST
			pcall(function()
				v.Crackle:Emit(n[1] + math.floor((n[2] - n[1] + 1) * v.Random()))
			end)
			writes = writes + 1
		end
	end
	return writes
end

-- one update at time t (seconds), fade 0..1 (the gate easing in), breath 0..1; -> property writes made
function PortalVortex.Animate(v, t, fade, breath, static)
	if not v or not v.Shown then
		return 0
	end
	if static then
		if v.StaticDone then
			return 0
		end
		v.StaticDone = true
		t, fade, breath = 0, 1, 0.5
	else
		v.StaticDone = false
	end
	if v.Mode == "Texture" then
		return animateTexture(v, t, fade or 1, breath or 0.5)
	end
	return animateFallback(v, t)
end

function PortalVortex.Destroy(v)
	if not v then
		return
	end
	for _, p in ipairs({ v.Plane, v.SpinA, v.SpinB }) do
		if p then
			p:Destroy()
		end
	end
	v.Shown = false
end

return PortalVortex
