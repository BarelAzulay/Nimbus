-- SkyCycle: the living sky's pure phase math and looks (docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md,
-- plan docs/superpowers/plans/2026-10-30-living-sky.md Task 1). The server publishes one epoch / speed / offset (Workspace
-- attributes); every client turns the shared server time into the SAME phase, blend and lighting preset with these
-- functions, so the clock costs no remote traffic and a late joiner lands on the same values as a long-running client.
-- Pure Lua 5.1-compatible syntax; no Instances, no services, no yields, no state between calls.
--
-- API (the contract):
--   SkyCycle.At(serverNow, epoch, speed, offset) -> { Phase, Next, T, Blend, LoopT }
--       loop position = ((serverNow - epoch) x speed + offset) mod the loop (Config.Sky.Cycle: Dawn 120, Day 360,
--       Sunset 540, Night 180 s); T = 0..1 through the phase; Blend = 0 until the last Cycle.Blend (75) s of the phase,
--       then a smoothstep 0 -> 1 toward Next; LoopT = 0..1 through the loop. Junk never errors: a nil / NaN epoch,
--       now or offset = 0, speed clamped to Config.Sky.Speed (0.1..120; NaN / non-number = 1).
--   SkyCycle.Preset(at, eventId, eventBlend, facesFor, fromId, fromBlend) -> preset, themeId
--       preset = LightingStack groups { Lighting, Atmosphere, Clouds, ColorCorrection, Sky } (fresh tables every call):
--       the phase look mixed toward the next one by at.Blend, then toward the raid look Config.Sky.Looks[fromId] by
--       fromBlend (optional: the raid sky that showed when eventId's began, back-to-back raids), then toward the raid
--       look Config.Sky.Looks[eventId] by eventBlend (0..1; an unknown / empty id or a junk blend = no event; fromId =
--       eventId is ignored). So eventBlend 0 with fromId = the old raid at fromBlend 1 is exactly the old raid sky and
--       a new raid never flashes back toward the cycle. Numbers lerp, Color3 :Lerp; integers (StarCount), strings and
--       booleans switch at blend >= 0.5. ClockTime walks the phase's Clock range { from, to } with T on an UNWRAPPED
--       clock (to may pass 24: Night { 18.4, 31 } runs through midnight to 7 h next morning), always forward; in the
--       phase's blend window it walks on across the gap to the next phase's start (the first from + 24k at or after
--       to: Sunset 17 -> Night 18.4, so the sun sets across the 75 s blend, never in one frame; Dawn -> Day,
--       Day -> Sunset and Night 31 -> Dawn 7 meet already). The returned ClockTime is that clock mod 24 ([0, 24)), so
--       over a whole loop it only ever moves forward round the dial (SkyCycle.ClockDelta), wrapping 24 -> 0 once, in
--       the Night. A raid switches it to its look's fixed Clock at its blend >= 0.5 (fromId's first, then eventId's).
--       themeId =
--       Config.Sky.Themes[phase] (Themes[Next] from Blend 0.5, the skybox swap while the haze is thickest),
--       RaidThemes[fromId] from fromBlend 0.5, RaidThemes[eventId] from eventBlend 0.5. facesFor(themeId) (SkyFaces.For)
--       -> { SkyboxBk = id, ... } adds the Skybox* strings to the Sky group; nil / no facesFor = no Skybox keys, so the
--       Sky keeps what LightingService set at boot. The result is passed through Floor.
--   SkyCycle.Floor(preset) -> preset   the readability floor, in place: Lighting.Brightness >= Floor.Brightness (1.0),
--       every OutdoorAmbient channel >= Floor.OutdoorAmbientMin (70) / 255, every ColorCorrection TintColor channel
--       within Floor.TintMax (8) / 255 of white (the colour comes from the world light, never a screen tint).
--   SkyCycle.Integer = { StarCount = true }   the whole-number properties: switched here, never lerped, and set at
--       once by client/LightingStack (never tweened through fractions)
--   SkyCycle.ClockDelta(from, to) -> hours in [-12, 12)   the step from one ClockTime to another round the 24 h dial
--       (23.9 -> 0.1 = +0.2: 24 h and 0 h are the same sun position)
-- at.Phase / at.Next are checked against Config.Sky.Cycle.Order (a raid boss id is a Looks key, never a phase).
-- The cycle's clock never jumps: every 2 s refresh step is a small forward step round the dial (Night, the fastest:
-- 12.6 h in 180 s = 0.14 h per 2 s). Client SkyController sets ClockTime at once only (a) when it passes midnight
-- (23.9 -> 0.1: a tween would run backwards through the day; the set is invisible, 24 h = 0 h, and only one refresh
-- step long) and (b) at a raid sky's mid-blend (its fixed clock, a step of more than Config.Sky.ClockJump h).

local Shared = script.Parent
local Config = require(Shared.Config)

local SkyCycle = {}

local floor, max, min = math.floor, math.max, math.min

-- the groups a preset carries, in a fixed order (deterministic output; LightingStack ignores the rest)
local GROUPS = { "Lighting", "Atmosphere", "Clouds", "ColorCorrection", "Sky" }
-- whole-number properties: set at once, never tweened or lerped
local INTEGER = { StarCount = true }
SkyCycle.Integer = INTEGER

local function cfg()
	return Config.Sky
end

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- a finite number, else `default`
local function num(v, default)
	if finite(v) then
		return v
	end
	return default
end

local function clamp(v, lo, hi)
	return max(lo, min(hi, v))
end

-- speed: NaN / non-number = the default, inf / huge / negative clamped into [Min, Max]
local function cleanSpeed(speed)
	local s = cfg().Speed
	if type(speed) ~= "number" or speed ~= speed then
		return s.Default
	end
	return clamp(speed, s.Min, s.Max)
end

function SkyCycle.At(serverNow, epoch, speed, offset)
	local cycle = cfg().Cycle
	local order, seconds = cycle.Order, cycle.Seconds
	local loop = 0
	for _, phase in ipairs(order) do
		loop = loop + seconds[phase]
	end
	local elapsed = (num(serverNow, 0) - num(epoch, 0)) * cleanSpeed(speed) + num(offset, 0)
	if not finite(elapsed) then
		elapsed = 0
	end
	local pos = elapsed - floor(elapsed / loop) * loop
	if pos < 0 or pos >= loop then
		pos = 0 -- float edge of the modulo
	end
	local start = 0
	for i, phase in ipairs(order) do
		local len = seconds[phase]
		if pos < start + len or i == #order then
			local into = clamp(pos - start, 0, len)
			local window = min(cycle.Blend, len)
			local left = len - into
			local blend = 0
			if left < window then
				local x = (window - left) / window
				blend = x * x * (3 - 2 * x)
			end
			local t = into / len
			if t >= 1 then
				t = 1 - 1e-9
			end
			return { Phase = phase, Next = order[i % #order + 1], T = t, Blend = blend, LoopT = pos / loop }
		end
		start = start + len
	end
	return { Phase = order[1], Next = order[2], T = 0, Blend = 0, LoopT = 0 }
end

local function copyLook(look)
	local out = {}
	for _, group in ipairs(GROUPS) do
		local props = {}
		for prop, v in pairs(look[group] or {}) do
			props[prop] = v
		end
		out[group] = props
	end
	return out
end

-- one property between a and b at t (0..1)
local function mixValue(prop, a, b, t)
	if a == nil then
		return b
	elseif b == nil then
		return a
	end
	if type(a) == "number" and type(b) == "number" and not INTEGER[prop] then
		return a + (b - a) * t
	end
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return a:Lerp(b, t)
	end
	if t >= 0.5 then
		return b
	end
	return a
end

-- a fresh preset between two (copied) looks; t = 0 is exactly a, 1 exactly b
local function mix(a, b, t)
	local out = {}
	for _, group in ipairs(GROUPS) do
		local ga, gb = a[group] or {}, b[group] or {}
		local props = {}
		for prop, v in pairs(ga) do
			props[prop] = mixValue(prop, v, gb[prop], t)
		end
		for prop, v in pairs(gb) do
			if ga[prop] == nil then
				props[prop] = v
			end
		end
		out[group] = props
	end
	return out
end

local DAY = 24

-- a clock on the 24 h dial: [0, 24)
local function dial(c)
	local d = c - floor(c / DAY) * DAY
	if d < 0 or d >= DAY then
		d = 0
	end
	return d
end

function SkyCycle.ClockDelta(from, to)
	if not (finite(from) and finite(to)) then
		return 0
	end
	local d = dial(to - from + DAY / 2) - DAY / 2
	return d
end

-- the phase's (unwrapped) clock at T: Clock = { from, to }, walked linearly (a fixed clock when from == to)
local function clockAt(look, t)
	local c = look.Clock
	if type(c) ~= "table" then
		return nil
	end
	return c[1] + (c[2] - c[1]) * t
end

function SkyCycle.Floor(preset)
	local f = cfg().Floor
	local L = preset.Lighting
	if type(L) == "table" then
		if type(L.Brightness) == "number" then
			L.Brightness = max(L.Brightness, f.Brightness)
		end
		local oa = L.OutdoorAmbient
		if typeof(oa) == "Color3" then
			local m = f.OutdoorAmbientMin / 255
			L.OutdoorAmbient = Color3.new(max(oa.R, m), max(oa.G, m), max(oa.B, m))
		end
	end
	local cc = preset.ColorCorrection
	if type(cc) == "table" and typeof(cc.TintColor) == "Color3" then
		local m = 1 - (f.TintMax or 8) / 255
		local tc = cc.TintColor
		cc.TintColor = Color3.new(max(tc.R, m), max(tc.G, m), max(tc.B, m))
	end
	return preset
end

function SkyCycle.Preset(at, eventId, eventBlend, facesFor, fromId, fromBlend)
	local sky = cfg()
	local order, looks = sky.Cycle.Order, sky.Looks
	at = type(at) == "table" and at or {}
	local isPhase = {}
	for _, name in ipairs(order) do
		isPhase[name] = looks[name] ~= nil
	end
	local phase = isPhase[at.Phase] and at.Phase or order[1]
	local nextPhase = isPhase[at.Next] and at.Next or phase
	local blend = clamp(num(at.Blend, 0), 0, 1)
	local t = clamp(num(at.T, 0), 0, 1)

	local preset = mix(copyLook(looks[phase]), copyLook(looks[nextPhase]), blend)
	local clock = clockAt(looks[phase], t)
	local range = looks[phase].Clock
	if clock and blend > 0 and nextPhase ~= phase and type(range) == "table" then
		-- the gap to the next phase's start (unwrapped: the first from + 24k at or after this phase's end) is walked
		-- across the blend; monotonic, the clock only gains
		local to, nextFrom = range[2], clockAt(looks[nextPhase], 0)
		if finite(to) and finite(nextFrom) then
			nextFrom = nextFrom + math.ceil((to - nextFrom - 1e-9) / DAY) * DAY
			clock = clock + (nextFrom - to) * blend
		end
	end
	preset.Lighting.ClockTime = clock and dial(clock) or nil
	local theme = sky.Themes[blend >= 0.5 and nextPhase or phase]

	-- the raid sky that showed when this one began (back-to-back raids), then this raid sky on top
	local function raidOn(id, b)
		local look = type(id) == "string" and sky.RaidThemes[id] and looks[id] or nil
		b = clamp(num(b, 0), 0, 1)
		if look and b > 0 then
			preset = mix(preset, copyLook(look), b)
			if b >= 0.5 then
				local fixed = clockAt(look, 0)
				preset.Lighting.ClockTime = fixed and dial(fixed) or nil
				theme = sky.RaidThemes[id]
			end
		end
	end
	if fromId ~= eventId then
		raidOn(fromId, fromBlend)
	end
	raidOn(eventId, eventBlend)

	local faces = type(facesFor) == "function" and facesFor(theme) or nil
	if type(faces) == "table" then
		for key, id in pairs(faces) do
			if type(key) == "string" and key:sub(1, 6) == "Skybox" and type(id) == "string" then
				preset.Sky[key] = id
			end
		end
		-- the painted skies carry their own sun / moon / black sun: the engine's would be a second one on top. Its disc
		-- goes, and so do the Atmosphere glare and the sun rays, which glow at the engine sun even with the disc hidden
		-- (checked in Studio 2026-10-30: a bright second "sun" next to the painted one until both were 0)
		preset.Sky.CelestialBodiesShown = false
		preset.Atmosphere = preset.Atmosphere or {}
		preset.Atmosphere.Glare = 0
		preset.SunRays = { Intensity = 0 }
	end
	return SkyCycle.Floor(preset), theme
end

return SkyCycle
