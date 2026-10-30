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
--   SkyCycle.Preset(at, eventId, eventBlend, facesFor) -> preset, themeId
--       preset = LightingStack groups { Lighting, Atmosphere, Clouds, ColorCorrection, Sky } (fresh tables every call):
--       the phase look mixed toward the next one by at.Blend, then toward the raid look Config.Sky.Looks[eventId] by
--       eventBlend (0..1; an unknown / empty event id or a junk blend = no event). Numbers lerp, Color3 :Lerp;
--       integers (StarCount), strings and booleans switch at blend >= 0.5. ClockTime walks the phase's Clock range
--       { from, to } with T (monotonic inside a phase, never across 24 -> 0); an event switches it to the raid look's
--       fixed Clock at eventBlend >= 0.5. themeId = Config.Sky.Themes[phase] (Themes[Next] from Blend 0.5, the skybox
--       swap while the haze is thickest), RaidThemes[eventId] from eventBlend 0.5. facesFor(themeId) (SkyFaces.For)
--       -> { SkyboxBk = id, ... } adds the Skybox* strings to the Sky group; nil / no facesFor = no Skybox keys, so the
--       Sky keeps what LightingService set at boot. The result is passed through Floor.
--   SkyCycle.Floor(preset) -> preset   the readability floor, in place: Lighting.Brightness >= Floor.Brightness (1.0),
--       every OutdoorAmbient channel >= Floor.OutdoorAmbientMin (70) / 255, every ColorCorrection TintColor channel
--       within Floor.TintMax (8) / 255 of white (the colour comes from the world light, never a screen tint).
-- The clock jumps twice a loop at a phase start (Sunset 17 -> Night 18.4 forward, Night 23.6 -> Dawn 7 backward):
-- the applier sets ClockTime at once when it goes backward instead of tweening through the day.

local Shared = script.Parent
local Config = require(Shared.Config)

local SkyCycle = {}

local floor, max, min = math.floor, math.max, math.min

-- the groups a preset carries, in a fixed order (deterministic output; LightingStack ignores the rest)
local GROUPS = { "Lighting", "Atmosphere", "Clouds", "ColorCorrection", "Sky" }
-- whole-number properties: set at once, never tweened or lerped
local INTEGER = { StarCount = true }

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

-- the phase's ClockTime at T: Clock = { from, to }, walked linearly (a fixed clock when from == to)
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

function SkyCycle.Preset(at, eventId, eventBlend, facesFor)
	local sky = cfg()
	local order, looks = sky.Cycle.Order, sky.Looks
	at = type(at) == "table" and at or {}
	local phase = looks[at.Phase] and at.Phase or order[1]
	local nextPhase = looks[at.Next] and at.Next or phase
	local blend = clamp(num(at.Blend, 0), 0, 1)
	local t = clamp(num(at.T, 0), 0, 1)

	local preset = mix(copyLook(looks[phase]), copyLook(looks[nextPhase]), blend)
	preset.Lighting.ClockTime = clockAt(looks[phase], t)
	local theme = sky.Themes[blend >= 0.5 and nextPhase or phase]

	local raid = type(eventId) == "string" and sky.RaidThemes[eventId] and looks[eventId] or nil
	local eb = clamp(num(eventBlend, 0), 0, 1)
	if raid and eb > 0 then
		preset = mix(preset, copyLook(raid), eb)
		if eb >= 0.5 then
			preset.Lighting.ClockTime = clockAt(raid, 0)
			theme = sky.RaidThemes[eventId]
		end
	end

	local faces = type(facesFor) == "function" and facesFor(theme) or nil
	if type(faces) == "table" then
		for key, id in pairs(faces) do
			if type(key) == "string" and key:sub(1, 6) == "Skybox" and type(id) == "string" then
				preset.Sky[key] = id
			end
		end
	end
	return SkyCycle.Floor(preset), theme
end

return SkyCycle
