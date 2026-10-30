-- smoke_sky.lua: the living sky cycle + raid skies (docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md, plan
-- docs/superpowers/plans/2026-10-30-living-sky.md). Loaded by tools/smoke.py in BOTH worlds (ARGS.context).
--   sky_phase_math     (server world, pure) SkyCycle.At with epoch 0, speed 1, offset 0: t = 0 Dawn T 0; 119 Dawn with
--                      Blend > 0.95; 120 Day; 1199 Night; 1200 Dawn again (the loop wraps); -5 (clock skew) = Night near
--                      its end, no error; LoopT in [0, 1)
--   sky_blend_window   (server world, pure) Blend is 0 until Config.Sky.Cycle.Blend (75) s before a phase ends, then rises
--                      monotonically to 1; Next is the following phase in Order (Night -> Dawn)
--   sky_clock_no_wrap  (server world, pure) one loop sampled every 1 s: within a phase ClockTime is monotonic, in [0, 24)
--                      and never crosses 24 -> 0; Sunset stays in [16, 17]
--   sky_floor          (server world, pure) every phase sample and every raid look after Preset: Brightness >= 1.0, each
--                      OutdoorAmbient channel >= 70/255, ColorCorrection TintColor within 8/255 of white; Floor lifts a
--                      dark preset onto the floor
--   sky_join_matches   (server world, pure) Preset at t computed fresh = Preset at t after walking 0..t in 2 s steps (no
--                      hidden state; Config.Sky.Looks never changes)
--   sky_bad_inputs     (server world, pure) speed 0 / negative / NaN / 1e9 / inf and a nil epoch / now / offset give a valid
--                      phase (speed clamped to [0.1, 120], nil epoch = 0), no NaN anywhere in the preset; junk event ids
--                      and blends are ignored
--   sky_event_blend    (server world, pure) the four raid themes match BattleCatalog.Bosses; eventBlend 1 = the raid look,
--                      0.5 = the midpoint for numbers and Color3; the returned themeId (and the faces asked of facesFor)
--                      switch to the raid theme exactly at eventBlend >= 0.5; phase theme swaps at Blend 0.5
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, min = math.abs, math.floor, math.min
local fmt = string.format

local GROUPS = { "Lighting", "Atmosphere", "Clouds", "ColorCorrection", "Sky" }

local function isColor(v)
	return typeof(v) == "Color3"
end

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- a deep, order-independent description of a preset (numbers to 1e-9, Color3 by channel), for equality checks
local function same(a, b, path)
	path = path or "preset"
	if type(a) ~= type(b) or typeof(a) ~= typeof(b) then
		return false, path .. ": " .. typeof(a) .. " vs " .. typeof(b)
	end
	if isColor(a) then
		if abs(a.R - b.R) > 1e-9 or abs(a.G - b.G) > 1e-9 or abs(a.B - b.B) > 1e-9 then
			return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
		end
		return true
	end
	if type(a) == "number" then
		if abs(a - b) > 1e-9 then
			return false, fmt("%s: %.12g vs %.12g", path, a, b)
		end
		return true
	end
	if type(a) == "table" then
		for k, v in pairs(a) do
			local ok, why = same(v, b[k], path .. "." .. tostring(k))
			if not ok then
				return false, why
			end
		end
		for k in pairs(b) do
			if a[k] == nil then
				return false, path .. "." .. tostring(k) .. " only on one side"
			end
		end
		return true
	end
	if a ~= b then
		return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
	end
	return true
end

local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end

-- every number / Color3 channel in a preset is finite (no NaN reaches Lighting)
local function allFinite(preset)
	local bad
	for _, group in ipairs(GROUPS) do
		for prop, v in pairs(preset[group] or {}) do
			if type(v) == "number" and not finite(v) then
				bad = bad or (group .. "." .. prop .. " = " .. tostring(v))
			elseif isColor(v) and not (finite(v.R) and finite(v.G) and finite(v.B)) then
				bad = bad or (group .. "." .. prop .. " = " .. tostring(v))
			end
		end
	end
	return bad == nil, bad
end

----------------------------------------------------------------------------------------------------
-- the server world (pure: SkyCycle + Config only)
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function loadModule(name)
		local inst = K.moduleInstance("shared/" .. name)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		if ok and type(result) == "table" then
			return result
		end
		return nil
	end

	-- SkyCycle + Config.Sky (Cycle / Looks / Floor), or nil after one failed check
	local function sky()
		local SC = loadModule("SkyCycle")
		local Config = loadModule("Config")
		local cfg = Config and Config.Sky
		if not T.check(SC and type(SC.At) == "function" and type(SC.Preset) == "function" and type(SC.Floor) == "function", "SkyCycle exists with At / Preset / Floor", "src/shared/SkyCycle.lua missing or incomplete") then
			return nil
		end
		if not T.check(type(cfg) == "table" and type(cfg.Cycle) == "table" and type(cfg.Looks) == "table" and type(cfg.Floor) == "table" and type(cfg.Themes) == "table" and type(cfg.RaidThemes) == "table", "Config.Sky has Cycle / Themes / RaidThemes / Looks / Floor") then
			return nil
		end
		T.check(type(cfg.Faces) == "table", "Config.Sky.Faces is kept (LightingService's boot sky)")
		return SC, cfg, Config
	end

	-- sky_phase_math
	S.sky_phase_math = guarded("sky_phase_math", function()
		local SC, cfg = sky()
		if not SC then
			return
		end
		local c = cfg.Cycle
		T.check(c.Order[1] == "Dawn" and c.Order[2] == "Day" and c.Order[3] == "Sunset" and c.Order[4] == "Night" and #c.Order == 4, "Cycle.Order = Dawn, Day, Sunset, Night")
		T.check(c.Seconds.Dawn == 120 and c.Seconds.Day == 360 and c.Seconds.Sunset == 540 and c.Seconds.Night == 180, "Cycle.Seconds = Dawn 120, Day 360, Sunset 540, Night 180 (a 20 min loop)")
		T.check(c.Blend == 75 and c.Refresh == 2 and c.Tween == 2 and c.EventBlend == 3, "Cycle Blend 75, Refresh 2, Tween 2, EventBlend 3")
		local a = SC.At(0, 0, 1, 0)
		T.check(a.Phase == "Dawn" and abs(a.T) < 1e-9 and a.Blend == 0 and a.Next == "Day", "t = 0: Dawn, T = 0, Blend 0, Next Day", fmt("%s T %.3f Blend %.3f", tostring(a.Phase), a.T or -1, a.Blend or -1))
		a = SC.At(119, 0, 1, 0)
		T.check(a.Phase == "Dawn" and a.Blend > 0.95, "t = 119: still Dawn, Blend > 0.95 toward Day", fmt("%s Blend %.3f", tostring(a.Phase), a.Blend or -1))
		a = SC.At(120, 0, 1, 0)
		T.check(a.Phase == "Day" and abs(a.T) < 1e-9 and a.Blend == 0, "t = 120: Day starts (T 0, Blend 0)", fmt("%s T %.3f", tostring(a.Phase), a.T or -1))
		a = SC.At(480, 0, 1, 0)
		T.check(a.Phase == "Sunset", "t = 480: Sunset starts", tostring(a.Phase))
		a = SC.At(1020, 0, 1, 0)
		T.check(a.Phase == "Night" and a.Next == "Dawn", "t = 1020: Night starts, Next Dawn", tostring(a.Phase))
		a = SC.At(1199, 0, 1, 0)
		T.check(a.Phase == "Night" and a.Blend > 0.95, "t = 1199: Night, Blend > 0.95 toward Dawn", fmt("%s Blend %.3f", tostring(a.Phase), a.Blend or -1))
		a = SC.At(1200, 0, 1, 0)
		T.check(a.Phase == "Dawn" and abs(a.T) < 1e-9 and abs(a.LoopT) < 1e-9, "t = 1200: the loop wraps to Dawn", fmt("%s T %.3f LoopT %.3f", tostring(a.Phase), a.T or -1, a.LoopT or -1))
		local ok, res = pcall(SC.At, -5, 0, 1, 0)
		T.check(ok and res.Phase == "Night" and res.T > 0.95 and res.T < 1, "t = -5 (clock skew): Night near its end, no error", ok and fmt("%s T %.3f", tostring(res.Phase), res.T or -1) or tostring(res))
		-- epoch / speed / offset move the clock the documented way: ((now - epoch) x speed + offset) mod 1200
		a = SC.At(1000 + 60, 1000, 1, 0)
		T.check(a.Phase == "Dawn" and abs(a.T - 0.5) < 1e-9, "epoch 1000, now 1060: Dawn half way", fmt("%s T %.3f", tostring(a.Phase), a.T or -1))
		a = SC.At(10, 0, 50, 0)
		T.check(a.Phase == "Sunset" and abs(a.T - 20 / 540) < 1e-9, "speed 50: 10 s = 500 cycle s = Sunset + 20 s", fmt("%s T %.4f", tostring(a.Phase), a.T or -1))
		a = SC.At(0, 0, 1, 1020)
		T.check(a.Phase == "Night" and abs(a.T) < 1e-9, "offset 1020: Night starts at t 0", fmt("%s T %.3f", tostring(a.Phase), a.T or -1))
		local lt = T.tally("LoopT in [0, 1) and T in [0, 1) over three loops")
		for t = -1200, 2400, 7 do
			local x = SC.At(t, 0, 1, 0)
			lt:case(x.LoopT >= 0 and x.LoopT < 1 and x.T >= 0 and x.T < 1, fmt("t %d LoopT %.4f T %.4f", t, x.LoopT, x.T))
		end
		lt:report()
	end)

	-- sky_blend_window
	S.sky_blend_window = guarded("sky_blend_window", function()
		local SC, cfg = sky()
		if not SC then
			return
		end
		local c = cfg.Cycle
		local start = 0
		for i, phase in ipairs(c.Order) do
			local len = c.Seconds[phase]
			local zero = T.tally(phase .. ": Blend 0 until " .. c.Blend .. " s before the end")
			local rise = T.tally(phase .. ": Blend rises monotonically to 1 over the last " .. c.Blend .. " s")
			local nextOk = T.tally(phase .. ": Next = " .. tostring(c.Order[i % #c.Order + 1]))
			local last = -1
			for s = 0, len - 0.25, 0.25 do
				local a = SC.At(start + s, 0, 1, 0)
				nextOk:case(a.Phase == phase and a.Next == c.Order[i % #c.Order + 1], fmt("s %.2f %s -> %s", s, tostring(a.Phase), tostring(a.Next)))
				if s <= len - c.Blend then
					zero:case(a.Blend == 0, fmt("s %.2f Blend %.4f", s, a.Blend))
				else
					rise:case(a.Blend >= last and a.Blend > 0 and a.Blend <= 1, fmt("s %.2f Blend %.4f after %.4f", s, a.Blend, last))
				end
				last = a.Blend
			end
			local e = SC.At(start + len - 1e-6, 0, 1, 0)
			rise:case(e.Blend > 0.999, fmt("end Blend %.5f", e.Blend))
			zero:report()
			rise:report()
			nextOk:report()
			start = start + len
		end
	end)

	-- sky_clock_no_wrap
	S.sky_clock_no_wrap = guarded("sky_clock_no_wrap", function()
		local SC, cfg = sky()
		if not SC then
			return
		end
		local mono = T.tally("ClockTime is monotonic within each phase (one loop, every 1 s)")
		local range = T.tally("ClockTime stays in [0, 24) and never crosses 24 -> 0 inside a phase")
		local sunset = T.tally("Sunset ClockTime stays in [16, 17] (a modest sun, short shadows)")
		local lastPhase, lastClock
		for t = 0, 1199 do
			local at = SC.At(t, 0, 1, 0)
			local p = SC.Preset(at, nil, 0, nil)
			local clock = p.Lighting and p.Lighting.ClockTime
			range:case(type(clock) == "number" and clock >= 0 and clock < 24, fmt("t %d clock %s", t, tostring(clock)))
			if type(clock) == "number" then
				if at.Phase == lastPhase then
					mono:case(clock >= lastClock - 1e-9, fmt("t %d %s %.3f after %.3f", t, at.Phase, clock, lastClock))
					range:case(lastClock - clock < 12, fmt("t %d %s wrapped %.3f -> %.3f", t, at.Phase, lastClock, clock))
				end
				if at.Phase == "Sunset" then
					sunset:case(clock >= 16 - 1e-9 and clock <= 17 + 1e-9, fmt("t %d clock %.3f", t, clock))
				end
				lastPhase, lastClock = at.Phase, clock
			end
		end
		mono:report()
		range:report()
		sunset:report()
		-- every look's Clock range: from <= to, both inside one day
		local ranges = T.tally("every Config.Sky.Looks[*].Clock = { from, to } with 0 <= from <= to < 24")
		for id, look in pairs(cfg.Looks) do
			local c = look.Clock
			ranges:case(type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and c[1] >= 0 and c[1] <= c[2] and c[2] < 24, id)
		end
		ranges:report()
	end)

	-- sky_floor
	S.sky_floor = guarded("sky_floor", function()
		local SC, cfg = sky()
		if not SC then
			return
		end
		T.check(cfg.Floor.Brightness == 1.0 and cfg.Floor.OutdoorAmbientMin == 70, "Config.Sky.Floor = { Brightness 1.0, OutdoorAmbientMin 70 }")
		local floorB, floorA = cfg.Floor.Brightness, cfg.Floor.OutdoorAmbientMin / 255
		local function readable(p, label, tally)
			local L = p.Lighting or {}
			local cc = p.ColorCorrection or {}
			local oa, tint = L.OutdoorAmbient, cc.TintColor
			tally:case(type(L.Brightness) == "number" and L.Brightness >= floorB - 1e-9, label .. " Brightness " .. tostring(L.Brightness))
			tally:case(isColor(oa) and oa.R >= floorA - 1e-9 and oa.G >= floorA - 1e-9 and oa.B >= floorA - 1e-9, label .. " OutdoorAmbient " .. tostring(oa))
			tally:case(isColor(tint) and tint.R >= 1 - 8 / 255 - 1e-9 and tint.G >= 1 - 8 / 255 - 1e-9 and tint.B >= 1 - 8 / 255 - 1e-9, label .. " TintColor " .. tostring(tint))
		end
		local cyc = T.tally("every cycle moment (one loop, every 5 s): Brightness >= 1, OutdoorAmbient >= 70, tint near white")
		for t = 0, 1199, 5 do
			readable(SC.Preset(SC.At(t, 0, 1, 0), nil, 0, nil), "t " .. t, cyc)
		end
		cyc:report()
		local raids = T.tally("every raid look (blend 0.5 and 1, at night and at noon): the same floor")
		local n = 0
		for bossId in pairs(cfg.RaidThemes) do
			n = n + 1
			for _, t in ipairs({ 300, 1100 }) do
				for _, b in ipairs({ 0.5, 1 }) do
					readable(SC.Preset(SC.At(t, 0, 1, 0), bossId, b, nil), fmt("%s t %d blend %.1f", bossId, t, b), raids)
				end
			end
		end
		raids:report(n .. " raid looks")
		-- the raw looks already sit on the floor (Floor is a safety net, not the look)
		local raw = T.tally("every Config.Sky.Looks entry is authored on the floor already")
		for id, look in pairs(cfg.Looks) do
			readable(look, id, raw)
		end
		raw:report()
		-- Floor lifts a dark preset (and returns it)
		local dark = {
			Lighting = { Brightness = 0.2, OutdoorAmbient = Color3.fromRGB(10, 90, 40) },
			ColorCorrection = { TintColor = Color3.fromRGB(255, 200, 120) },
		}
		local out = SC.Floor(dark)
		T.check(out == dark, "Floor returns the preset it was given")
		T.near(out.Lighting.Brightness, 1.0, 1e-9, "Floor: Brightness 0.2 -> 1.0")
		local oa = out.Lighting.OutdoorAmbient
		T.check(abs(oa.R * 255 - 70) < 1e-6 and abs(oa.G * 255 - 90) < 1e-6 and abs(oa.B * 255 - 70) < 1e-6, "Floor: OutdoorAmbient (10, 90, 40) -> (70, 90, 70)", tostring(oa))
		local tc = out.ColorCorrection.TintColor
		T.check(abs(tc.R - 1) < 1e-6 and abs(tc.G * 255 - 247) < 1e-6 and abs(tc.B * 255 - 247) < 1e-6, "Floor: a strong orange TintColor is pulled back to within 8 of white", tostring(tc))
		local ok = pcall(SC.Floor, { Sky = { StarCount = 10 } })
		T.check(ok, "Floor on a preset without Lighting / ColorCorrection: no error")
	end)

	-- sky_join_matches
	S.sky_join_matches = guarded("sky_join_matches", function()
		local SC, cfg = sky()
		if not SC then
			return
		end
		local looks0 = copy(cfg.Looks)
		local function faces(theme)
			return { SkyboxBk = "bk:" .. theme, SkyboxDn = "dn:" .. theme, SkyboxFt = "ft:" .. theme, SkyboxLf = "lf:" .. theme, SkyboxRt = "rt:" .. theme, SkyboxUp = "up:" .. theme }
		end
		local epoch, speed, offset = 1730000000.25, 1, 37
		local targets = { 0, 119.3, 437, 1000.7, 1199.9, 2461.5 }
		local walked = {}
		local t, ti = 0, 1
		-- one long-running client: every 2 s step, with a raid in the middle of the walk
		while ti <= #targets do
			local ev, eb = nil, 0
			if t > 900 and t < 1300 then
				ev, eb = "lava_golem", min(1, (t - 900) / 3)
			end
			SC.Preset(SC.At(epoch + t, epoch, speed, offset), ev, eb, faces)
			while ti <= #targets and targets[ti] < t + 2 do
				local x = targets[ti]
				walked[ti] = { SC.Preset(SC.At(epoch + x, epoch, speed, offset), "frost_wyrm", 0.7, faces) }
				SC.Preset(SC.At(epoch + x, epoch, speed, offset), nil, 0, nil)
				ti = ti + 1
			end
			t = t + 2
		end
		for i, x in ipairs(targets) do
			local fresh, theme = SC.Preset(SC.At(epoch + x, epoch, speed, offset), "frost_wyrm", 0.7, faces)
			local ok, why = same(walked[i][1], fresh)
			T.check(ok and walked[i][2] == theme, fmt("t %.1f: a late joiner gets the same preset + theme as a long-running client", x), why)
		end
		local ok, why = same(looks0, cfg.Looks, "Looks")
		T.check(ok, "Preset never changes Config.Sky.Looks (no shared tables handed out)", why)
		-- presets are fresh tables: editing one never leaks into the next call
		local a = SC.Preset(SC.At(300, 0, 1, 0), nil, 0, nil)
		a.Lighting.Brightness = -99
		a.Atmosphere.Density = -99
		local b = SC.Preset(SC.At(300, 0, 1, 0), nil, 0, nil)
		T.check(b.Lighting.Brightness ~= -99 and b.Atmosphere.Density ~= -99, "Preset returns fresh tables")
	end)

	-- sky_bad_inputs
	S.sky_bad_inputs = guarded("sky_bad_inputs", function()
		local SC, cfg = sky()
		if not SC then
			return
		end
		local valid = {}
		for _, p in ipairs(cfg.Cycle.Order) do
			valid[p] = true
		end
		local nan = 0 / 0
		local cases = {
			{ "speed 0", 50, 0, 0, 0 },
			{ "speed -3", 50, 0, -3, 0 },
			{ "speed NaN", 50, 0, nan, 0 },
			{ "speed 1e9", 50, 0, 1e9, 0 },
			{ "speed inf", 50, 0, math.huge, 0 },
			{ "speed -inf", 50, 0, -math.huge, 0 },
			{ "speed 'fast'", 50, 0, "fast", 0 },
			{ "epoch nil", 50, nil, 1, 0 },
			{ "epoch NaN", 50, nan, 1, 0 },
			{ "now nil", nil, 0, 1, 0 },
			{ "now NaN", nan, 0, 1, 0 },
			{ "offset NaN", 50, 0, 1, nan },
			{ "offset inf", 50, 0, 1, math.huge },
			{ "offset junk", 50, 0, 1, {} },
			{ "everything nil", nil, nil, nil, nil },
			{ "huge now", 1e15, 0, 120, 0 },
		}
		local tally = T.tally("junk clock inputs give a valid phase and a finite preset (no error)")
		for _, c in ipairs(cases) do
			local ok, at = pcall(SC.At, c[2], c[3], c[4], c[5])
			local good = ok and type(at) == "table" and valid[at.Phase] and valid[at.Next] and finite(at.T) and at.T >= 0 and at.T < 1 and finite(at.Blend) and at.Blend >= 0 and at.Blend <= 1 and finite(at.LoopT)
			if good then
				local ok2, p = pcall(SC.Preset, at, nil, 0, nil)
				local fin, bad = false, "Preset error " .. tostring(p)
				if ok2 then
					fin, bad = allFinite(p)
				end
				tally:case(ok2 and fin, c[1] .. ": " .. tostring(bad))
			else
				tally:case(false, c[1] .. ": " .. (ok and (type(at) == "table" and fmt("%s T %s Blend %s", tostring(at.Phase), tostring(at.T), tostring(at.Blend)) or tostring(at)) or tostring(at)))
			end
		end
		tally:report()
		-- speed is clamped to [0.1, 120]
		local a0 = SC.At(100, 0, 0, 0)
		local aMin = SC.At(100, 0, 0.1, 0)
		T.check(abs(a0.LoopT - aMin.LoopT) < 1e-9 and abs(SC.At(100, 0, -5, 0).LoopT - aMin.LoopT) < 1e-9, "speed 0 / negative = 0.1 (the clamp's floor)", fmt("%.6f vs %.6f", a0.LoopT, aMin.LoopT))
		local aMax = SC.At(7, 0, 120, 0)
		T.check(abs(SC.At(7, 0, 1e9, 0).LoopT - aMax.LoopT) < 1e-9, "speed 1e9 = 120 (the clamp's ceiling)")
		T.check(abs(SC.At(100, nil, 1, 0).LoopT - SC.At(100, 0, 1, 0).LoopT) < 1e-12, "a nil epoch = epoch 0")
		-- junk At tables / events / blends
		local okA, pA = pcall(SC.Preset, nil, nil, 0, nil)
		T.check(okA and allFinite(pA), "Preset(nil at) = a finite Dawn preset, no error", tostring(pA))
		local okB, pB = pcall(SC.Preset, { Phase = "Noon", Next = 7, T = nan, Blend = "x" }, nil, 0, nil)
		T.check(okB and allFinite(pB), "Preset with a junk at table: no error, finite", tostring(pB))
		local at = SC.At(300, 0, 1, 0)
		local plain, plainTheme = SC.Preset(at, nil, 0, nil)
		for _, junk in ipairs({ { "no_such_boss", 1 }, { "", 1 }, { 42, 1 }, { "storm_titan", nan }, { "storm_titan", "half" }, { "storm_titan", -4 } }) do
			local okJ, pj, thj = pcall(SC.Preset, at, junk[1], junk[2], nil)
			local sameOk, why = false, tostring(pj)
			if okJ then
				sameOk, why = same(plain, pj)
			end
			T.check(okJ and sameOk and thj == plainTheme, fmt("event %s blend %s is ignored (the plain cycle)", tostring(junk[1]), tostring(junk[2])), why)
		end
		local okH, pH, thH = pcall(SC.Preset, at, "storm_titan", 7, nil)
		T.check(okH and thH == cfg.RaidThemes.storm_titan and allFinite(pH), "eventBlend 7 is clamped to 1 (the raid look)")
		local okF, pF = pcall(SC.Preset, at, nil, 0, function()
			return "junk"
		end)
		T.check(okF and pF.Sky.SkyboxBk == nil, "a facesFor returning junk adds no Skybox keys")
	end)

	-- sky_event_blend
	S.sky_event_blend = guarded("sky_event_blend", function()
		local SC, cfg = sky()
		if not SC then
			return
		end
		local BC = loadModule("BattleCatalog")
		local want = { storm_titan = "storm_teal", lava_golem = "lava_obsidian", frost_wyrm = "frost_glacial", shadow_hydra = "shadow_eclipse" }
		for bossId, theme in pairs(want) do
			T.check(cfg.RaidThemes[bossId] == theme, fmt("RaidThemes.%s = %s", bossId, theme), tostring(cfg.RaidThemes[bossId]))
			T.check(BC and BC.Bosses and BC.Bosses[bossId] ~= nil, fmt("%s is a BattleCatalog.Bosses id", bossId))
			T.check(type(cfg.Looks[bossId]) == "table", fmt("Looks.%s exists", bossId))
		end
		for bossId in pairs(BC and BC.Bosses or {}) do
			T.check(cfg.RaidThemes[bossId] ~= nil, fmt("boss %s has a raid sky", bossId))
		end
		T.check(cfg.Themes.Dawn == "dusk_amber" and cfg.Themes.Day == "day_vivid" and cfg.Themes.Sunset == "dusk_amber" and cfg.Themes.Night == "night_aurora", "Themes: Day day_vivid, Dawn + Sunset dusk_amber, Night night_aurora")
		local asked = {}
		local function faces(theme)
			asked[#asked + 1] = theme
			return { SkyboxBk = "bk:" .. theme, SkyboxDn = "dn:" .. theme, SkyboxFt = "ft:" .. theme, SkyboxLf = "lf:" .. theme, SkyboxRt = "rt:" .. theme, SkyboxUp = "up:" .. theme }
		end
		for _, t in ipairs({ 300, 1100 }) do
			local at = SC.At(t, 0, 1, 0)
			local p0, th0 = SC.Preset(at, nil, 0, faces)
			for bossId, theme in pairs(want) do
				local look = cfg.Looks[bossId]
				local p1, th1 = SC.Preset(at, bossId, 1, faces)
				-- eventBlend 1 = the raid look (ClockTime = its fixed Clock)
				local okL, why = true, nil
				for _, group in ipairs(GROUPS) do
					for prop, v in pairs(look[group] or {}) do
						local ok2, w2 = same(v, p1[group] and p1[group][prop], group .. "." .. prop)
						if not ok2 and okL then
							okL, why = false, w2
						end
					end
				end
				T.check(okL and abs(p1.Lighting.ClockTime - look.Clock[1]) < 1e-9, fmt("t %d %s blend 1 = the raid look (ClockTime %.2f)", t, bossId, look.Clock[1]), why or tostring(p1.Lighting.ClockTime))
				T.check(th1 == theme and p1.Sky.SkyboxBk == "bk:" .. theme, fmt("t %d %s blend 1: theme + faces %s", t, bossId, theme), tostring(th1))
				-- 0.5 = the midpoint of every number (not ClockTime / integers) and Color3
				local pm, thm = SC.Preset(at, bossId, 0.5, faces)
				local mid = T.tally(fmt("t %d %s blend 0.5 = the midpoint (numbers + Color3)", t, bossId))
				for _, group in ipairs(GROUPS) do
					for prop, v1 in pairs(p1[group] or {}) do
						local v0, vm = p0[group] and p0[group][prop], pm[group][prop]
						if prop ~= "ClockTime" and prop ~= "StarCount" and v0 ~= nil then
							if type(v1) == "number" then
								mid:case(abs(vm - (v0 + v1) / 2) < 1e-9, fmt("%s.%s %.4f vs %.4f / %.4f", group, prop, vm, v0, v1))
							elseif isColor(v1) then
								local e = v0:Lerp(v1, 0.5)
								mid:case(abs(vm.R - e.R) < 1e-9 and abs(vm.G - e.G) < 1e-9 and abs(vm.B - e.B) < 1e-9, fmt("%s.%s %s vs %s", group, prop, tostring(vm), tostring(e)))
							end
						end
					end
				end
				mid:report()
				T.check(thm == theme and pm.Sky.SkyboxBk == "bk:" .. theme, fmt("t %d %s blend 0.5: the skybox swaps to %s", t, bossId, theme), tostring(thm))
				local pb, thb = SC.Preset(at, bossId, 0.49, faces)
				T.check(thb == th0 and pb.Sky.SkyboxBk == "bk:" .. th0 and abs(pb.Lighting.ClockTime - p0.Lighting.ClockTime) < 1e-9, fmt("t %d %s blend 0.49: still the cycle sky %s and its clock", t, bossId, th0), tostring(thb))
			end
		end
		-- the phase themes swap at Blend 0.5 of each change (Sunset and Dawn share dusk_amber)
		local c = cfg.Cycle
		local start = 0
		for i, phase in ipairs(c.Order) do
			local len = c.Seconds[phase]
			local nextPhase = c.Order[i % #c.Order + 1]
			local before, after
			for s = len - c.Blend, len - 0.01, 0.01 do
				local at = SC.At(start + s, 0, 1, 0)
				local _, th = SC.Preset(at, nil, 0, nil)
				if at.Blend < 0.5 then
					before = th
				elseif after == nil then
					after = th
				end
			end
			T.check(before == cfg.Themes[phase] and after == cfg.Themes[nextPhase], fmt("%s -> %s: the theme %s -> %s at Blend 0.5", phase, nextPhase, tostring(before), tostring(after)))
			start = start + len
		end
		-- no faces known (facesFor nil / returns nil): no Skybox keys, the boot sky stays
		local pn = SC.Preset(SC.At(300, 0, 1, 0), nil, 0, nil)
		local pn2 = SC.Preset(SC.At(300, 0, 1, 0), "storm_titan", 1, function()
			return nil
		end)
		T.check(pn.Sky.SkyboxBk == nil and pn2.Sky.SkyboxBk == nil and type(pn.Sky.StarCount) == "number", "no faces: the Sky group carries StarCount only (no Skybox keys)")
		T.check(#asked > 0, "facesFor is asked with the theme id")
		-- integers switch, never lerp
		local night = SC.Preset(SC.At(1100, 0, 1, 0), nil, 0, nil)
		T.eq(night.Sky.StarCount, cfg.Looks.Night.Sky.StarCount, "Night: StarCount = the Night look's")
		local half = SC.Preset(SC.At(1100, 0, 1, 0), "storm_titan", 0.5, nil)
		T.check(half.Sky.StarCount == floor(half.Sky.StarCount), "StarCount is always a whole number (switches, never lerps)", tostring(half.Sky.StarCount))
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- the client world (Task 2+ adds the LightingStack and SkyController scenarios here)
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	return {}
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
