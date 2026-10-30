-- smoke_sky.lua: the living sky cycle + raid skies (docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md, plan
-- docs/superpowers/plans/2026-10-30-living-sky.md). Loaded by tools/smoke.py in BOTH worlds (ARGS.context).
--   sky_phase_math     (server world, pure) SkyCycle.At with epoch 0, speed 1, offset 0: t = 0 Dawn T 0; 119 Dawn with
--                      Blend > 0.95; 120 Day; 1199 Night; 1200 Dawn again (the loop wraps); -5 (clock skew) = Night near
--                      its end, no error; LoopT in [0, 1)
--   sky_blend_window   (server world, pure) Blend is 0 until Config.Sky.Cycle.Blend (75) s before a phase ends, then rises
--                      monotonically to 1; Next is the following phase in Order (Night -> Dawn)
--   sky_clock_no_wrap  (server world, pure) one loop sampled every 1 s: within a phase ClockTime is monotonic, in [0, 24)
--                      and never crosses 24 -> 0; Sunset stays in [16, 17] outside its blend; across the Sunset -> Night
--                      blend the clock walks on to Night's start: monotonic, no 2 s step over 0.2 h, continuous into Night
--                      (no one-frame horizon crossing); only the Night -> Dawn wrap steps backwards
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
--                      switch to the raid theme exactly at eventBlend >= 0.5; phase theme swaps at Blend 0.5; raid to
--                      raid (fromId / fromBlend): blend 0 = exactly the old raid sky, 1 = the new one, the midpoint lies
--                      between the two raid looks (never toward the cycle), theme + clock swap at 0.5
--   stack_setbase_under_preset (client) LightingStack.SetBase under Push("Dungeon"): the preset's Brightness keeps winning,
--                      a property only the base names (ClockTime) moves; Pop("Dungeon") lands on the moved base, not the
--                      boot value; a tweened SetBase reaches its goal and is not Busy; junk SetBase calls change nothing
--   stack_setbase_value (client) LightingStack.Value(group, prop, "Dungeon") = the new base after SetBase
--   stack_busy_skips   (client) Busy() is true while a Push / Pop fade runs (the mock tween's own completion), false after;
--                      a SetBase during the fade stores the base without cancelling or restarting that fade and applies
--                      nothing; the next SetBase after it applies
--   stack_setbase_instant (client) SkyCycle.Integer (StarCount) is set at once under a tweened SetBase / Push, never
--                      tweened; SetBase(preset, seconds, instant) sets the named props (the clock jump) at once while the
--                      rest tweens; an instant asked while Busy waits and is set at once by the next apply
--   client_sky_first_instant (client) SkyController: no SkyEpoch = inert (nothing applied); Start() with the clock
--                      published applies at once (seconds 0): Lighting = the SkyCycle preset of that moment
--   client_sky_refresh (client) the loop calls SetBase every Refresh (2) s with Tween (2) s; skips while Busy(); one loop
--                      (Start twice = one; Stop ends it); no RenderStepped / Heartbeat connection; a clock jump of more
--                      than Config.Sky.ClockJump at a phase change (the Night 23.6 -> Dawn 7 wrap) is set at once; the
--                      Sunset -> Night change is NOT (the clock tweens through it, monotonic, every 2 s step <= 0.2 h)
--   client_sky_event   (client) SkyEvent + SkyEventAt: the raid blend rises over EventBlend (3) s to 1 (a late joiner
--                      mid-raid lands on the raid sky at once); cleared -> back to the cycle over 3 s
--   client_sky_event_back_to_back (client) SkyEvent storm_titan -> lava_golem with no clear: the base blends from the
--                      storm look to the lava look (every step on the line between the two, never toward the cycle),
--                      look / theme / clock swap at the midpoint, the full lava sky after 3 s; a raid that ends half
--                      blended in leaves from where it was (no jump up to 1)
--   client_sky_battle_lift (client) InBattle "B12" at Night -> Push("SkyLift", Config.Sky.Lift.Preset, 1.5); "D3" (a
--                      dungeon run) -> no lift; cleared -> Pop over 1.5 s; Day -> no lift
--   client_sky_lamps   (client) LampGlass / LanternLight / StallLight / DomeGlow PointLights x Config.Sky.Lamps.Night at
--                      Night, their own value otherwise; other lights untouched; written on a look change only
--   client_sky_fireflies (client) Night + High graphics -> one capped emitter group near the lobby trees; Low -> none;
--                      Day -> none
--   client_gfx_cloud_cap (client) GfxLow Clouds Density = min(0.4, the cycle's), Recap follows the moving base
--   client_gfx_recap_keeps_tweens (client) a Recap after a sky refresh on Low updates GfxLow in place (LightingStack.Update):
--                      no Push, nothing Busy, the sky's running linear tweens are not cancelled; the next refresh carries
--                      the new cap
--   client_dungeon_density_follows (client) the dungeon's Atmosphere Density adds to the CURRENT cycle density (no
--                      boot-time cache, no double add on a re-push)
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
		local sunset = T.tally("Sunset ClockTime stays in [16, 17] outside its blend (a modest sun, short shadows)")
		local walk = T.tally("Sunset -> Night blend: ClockTime walks on to Night's start (monotonic, every 2 s step <= 0.2 h, continuous into Night)")
		local back = T.tally("the clock steps backwards only at the Night -> Dawn wrap")
		local lastPhase, lastClock
		local clocks = {}
		for t = 0, 1199 do
			local at = SC.At(t, 0, 1, 0)
			local p = SC.Preset(at, nil, 0, nil)
			local clock = p.Lighting and p.Lighting.ClockTime
			clocks[t] = clock
			range:case(type(clock) == "number" and clock >= 0 and clock < 24, fmt("t %d clock %s", t, tostring(clock)))
			if type(clock) == "number" then
				if at.Phase == lastPhase then
					mono:case(clock >= lastClock - 1e-9, fmt("t %d %s %.3f after %.3f", t, at.Phase, clock, lastClock))
					range:case(lastClock - clock < 12, fmt("t %d %s wrapped %.3f -> %.3f", t, at.Phase, lastClock, clock))
				elseif lastClock then
					back:case(clock >= lastClock - 1e-9 or (lastPhase == "Night" and at.Phase == "Dawn"), fmt("t %d %s -> %s %.3f -> %.3f", t, tostring(lastPhase), at.Phase, lastClock, clock))
				end
				if at.Phase == "Sunset" and at.Blend == 0 then
					sunset:case(clock >= 16 - 1e-9 and clock <= 17 + 1e-9, fmt("t %d clock %.3f", t, clock))
				end
				lastPhase, lastClock = at.Phase, clock
			end
		end
		-- the Sunset -> Night window: from 75 s before Night to its start, in the client's 2 s refresh steps
		local c = cfg.Cycle
		local nightAt = c.Seconds.Dawn + c.Seconds.Day + c.Seconds.Sunset
		local nightFrom = cfg.Looks.Night.Clock[1]
		local prev
		for t = nightAt - c.Blend - 2, nightAt + 4, 2 do
			local clock = clocks[t]
			if prev and type(clock) == "number" then
				walk:case(clock >= prev - 1e-9 and clock - prev <= 0.2, fmt("t %d %.3f after %.3f (step %.3f h)", t, clock, prev, clock - prev))
			end
			prev = clock
		end
		walk:case(clocks[nightAt - 1] > 17 + 1, fmt("1 s before Night the clock is already near Night's start (%.3f)", clocks[nightAt - 1]))
		walk:case(abs(clocks[nightAt] - nightFrom) < 1e-9 and nightFrom - clocks[nightAt - 1] < 0.05, fmt("Night starts at %.2f, %.3f h after the last Sunset second", nightFrom, nightFrom - clocks[nightAt - 1]))
		mono:report()
		range:report()
		sunset:report()
		walk:report()
		back:report()
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
		-- a raid boss id is a Looks key but never a phase: at.Phase / at.Next are checked against Cycle.Order
		local dawn, dawnTheme = SC.Preset({ Phase = "Dawn", Next = "Dawn", T = 0.5, Blend = 0.7 }, nil, 0, nil)
		local okR, pR, thR = pcall(SC.Preset, { Phase = "storm_titan", Next = "frost_wyrm", T = 0.5, Blend = 0.7 }, nil, 0, nil)
		local sameR, whyR = false, tostring(pR)
		if okR then
			sameR, whyR = same(dawn, pR)
		end
		T.check(okR and sameR and thR == dawnTheme and thR == cfg.Themes.Dawn, "a raid id as at.Phase / at.Next = Dawn (validated against Cycle.Order, not Looks)", tostring(whyR) .. " theme " .. tostring(thR))
		local day = SC.Preset({ Phase = "Day", Next = "Day", T = 0.5, Blend = 0.7 }, nil, 0, nil)
		local _, pN = pcall(SC.Preset, { Phase = "Day", Next = "lava_golem", T = 0.5, Blend = 0.7 }, nil, 0, nil)
		T.check(same(day, pN), "a raid id as at.Next = no blend (the phase itself)")
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
		-- raid to raid (back-to-back raids, no clear between): fromId at fromBlend is the start, never the cycle
		for _, t in ipairs({ 300, 1100 }) do
			local at = SC.At(t, 0, 1, 0)
			local storm = SC.Preset(at, "storm_titan", 1, faces)
			local lava, thLava = SC.Preset(at, "lava_golem", 1, faces)
			local p0, th0 = SC.Preset(at, "lava_golem", 0, faces, "storm_titan", 1)
			local p1, th1 = SC.Preset(at, "lava_golem", 1, faces, "storm_titan", 1)
			local okA, whyA = same(storm, p0, "from 0")
			local okB, whyB = same(lava, p1, "from 1")
			T.check(okA and th0 == "storm_teal", fmt("t %d storm -> lava at 0 = exactly the storm sky (theme storm_teal)", t), whyA or tostring(th0))
			T.check(okB and th1 == thLava, fmt("t %d storm -> lava at 1 = exactly the lava sky", t), whyB or tostring(th1))
			local cyc = SC.Preset(at, nil, 0, nil)
			local line = T.tally(fmt("t %d storm -> lava: every step lies between the two raid looks (not the cycle)", t))
			for _, x in ipairs({ 0.1, 0.25, 0.49, 0.5, 0.75, 0.9 }) do
				local px, thx = SC.Preset(at, "lava_golem", x, faces, "storm_titan", 1)
				for _, prop in ipairs({ "Brightness", "ExposureCompensation" }) do
					local a, b, v = storm.Lighting[prop], lava.Lighting[prop], px.Lighting[prop]
					line:case(abs(v - (a + (b - a) * x)) < 1e-9, fmt("x %.2f %s %.4f vs %.4f..%.4f (cycle %.4f)", x, prop, v, a, b, cyc.Lighting[prop]))
				end
				local ca, cb, cv = storm.Atmosphere.Color, lava.Atmosphere.Color, px.Atmosphere.Color
				local ce = ca:Lerp(cb, x)
				line:case(abs(cv.R - ce.R) < 1e-9 and abs(cv.G - ce.G) < 1e-9 and abs(cv.B - ce.B) < 1e-9, fmt("x %.2f Atmosphere.Color", x))
				local wantTheme = x >= 0.5 and "lava_obsidian" or "storm_teal"
				local wantClock = x >= 0.5 and cfg.Looks.lava_golem.Clock[1] or cfg.Looks.storm_titan.Clock[1]
				line:case(thx == wantTheme and px.Sky.SkyboxBk == "bk:" .. wantTheme and abs(px.Lighting.ClockTime - wantClock) < 1e-9, fmt("x %.2f theme %s clock %.2f (want %s %.2f)", x, tostring(thx), px.Lighting.ClockTime, wantTheme, wantClock))
			end
			line:report()
			-- the same id as from (a re-start of the same raid) = the plain raid blend; a junk fromId = no from
			local pSame = SC.Preset(at, "storm_titan", 0.3, nil, "storm_titan", 1)
			local pPlain = SC.Preset(at, "storm_titan", 0.3, nil)
			local pJunk = SC.Preset(at, "storm_titan", 0.3, nil, "no_such_boss", 1)
			T.check(same(pPlain, pSame) and same(pPlain, pJunk), fmt("t %d fromId = eventId or junk: ignored", t))
		end
		-- integers switch, never lerp
		local night = SC.Preset(SC.At(1100, 0, 1, 0), nil, 0, nil)
		T.eq(night.Sky.StarCount, cfg.Looks.Night.Sky.StarCount, "Night: StarCount = the Night look's")
		local half = SC.Preset(SC.At(1100, 0, 1, 0), "storm_titan", 0.5, nil)
		T.check(half.Sky.StarCount == floor(half.Sky.StarCount), "StarCount is always a whole number (switches, never lerps)", tostring(half.Sky.StarCount))
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- the client world: LightingStack's moving base (Task 2); Task 5 adds the SkyController scenarios here
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Lighting = game:GetService("Lighting")

	local function stackModule()
		local inst = Mock.GetPath(ROOTS["client"] .. "/LightingStack")
		local ok, LS = pcall(require, inst)
		if not T.check(inst ~= nil and ok and type(LS) == "table", "client/LightingStack loads") then
			return nil
		end
		for _, f in ipairs({ "SetBase", "Busy", "Push", "Pop", "Value", "Ids" }) do
			if not T.check(type(LS[f]) == "function", "LightingStack." .. f .. " is a function") then
				return nil
			end
		end
		return LS
	end

	-- each scenario starts from a known base (and gives it back at the end), whatever ran before it in this world:
	-- the booted client may already hold GfxLow, so these use the base of the two Lighting properties they name
	local function withBase(name, fn)
		return guarded(name, function()
			local LS = stackModule()
			if not LS then
				return
			end
			local before = LS.Ids()
			local saved = { Brightness = LS.Value("Lighting", "Brightness", "Dungeon"), ClockTime = LS.Value("Lighting", "ClockTime", "Dungeon") }
			LS.SetBase({ Lighting = { Brightness = 2, ClockTime = 14.5 } }, 0)
			local ok, err = pcall(fn, LS)
			T.check(ok, name .. " ran without errors", tostring(err))
			LS.Pop("Dungeon", 0)
			KC.advance(0.1)
			LS.SetBase({ Lighting = saved }, 0)
			T.eq(#LS.Ids(), #before, name .. ": the stack is as it was")
		end)
	end

	S.stack_setbase_under_preset = withBase("stack_setbase_under_preset", function(LS)
		LS.Push("Dungeon", { Lighting = { Brightness = 0.5 } }, 0)
		T.eq(Lighting.Brightness, 0.5, "Push Dungeon (0 s): Brightness 0.5")
		LS.SetBase({ Lighting = { Brightness = 1.4, ClockTime = 21 } }, 0)
		T.check(Lighting.Brightness == 0.5 and Lighting.ClockTime == 21, "SetBase under Dungeon: Brightness stays 0.5 (the preset wins), ClockTime becomes 21", tostring(Lighting.Brightness) .. " " .. tostring(Lighting.ClockTime))
		LS.Pop("Dungeon", 0)
		T.check(Lighting.Brightness == 1.4 and Lighting.ClockTime == 21, "Pop Dungeon -> the moved base (1.4 / 21), not the boot value", tostring(Lighting.Brightness) .. " " .. tostring(Lighting.ClockTime))
		-- a tweened SetBase reaches its goal and is not a Push / Pop fade (Busy stays false)
		LS.SetBase({ Lighting = { Brightness = 1.1, ClockTime = 22 } }, 2)
		T.check(Lighting.Brightness == 1.4 and not LS.Busy(), "a 2 s SetBase tweens (no jump) and does not count as Busy", tostring(Lighting.Brightness))
		KC.advance(2.2)
		T.check(math.abs(Lighting.Brightness - 1.1) < 1e-9 and math.abs(Lighting.ClockTime - 22) < 1e-9, "the SetBase tween reaches 1.1 / 22", tostring(Lighting.Brightness))
		-- junk: no error, nothing changes
		LS.SetBase(nil, 1)
		LS.SetBase("nope", 1)
		LS.SetBase({ Nonsense = { Foo = 1 } }, 0)
		T.check(math.abs(Lighting.Brightness - 1.1) < 1e-9, "junk SetBase calls change nothing")
	end)

	S.stack_setbase_value = withBase("stack_setbase_value", function(LS)
		LS.Push("Dungeon", { Lighting = { Brightness = 0.5 } }, 0)
		T.eq(LS.Value("Lighting", "Brightness", "Dungeon"), 2, "Value without Dungeon = the base (2)")
		LS.SetBase({ Lighting = { Brightness = 1.4, ClockTime = 21 } }, 0)
		T.eq(LS.Value("Lighting", "Brightness", "Dungeon"), 1.4, "Value without Dungeon = the new base after SetBase")
		T.eq(LS.Value("Lighting", "Brightness"), 0.5, "Value with Dungeon = the preset's 0.5")
		T.eq(LS.Value("Lighting", "ClockTime", "Dungeon"), 21, "Value of ClockTime = the new base 21")
	end)

	S.stack_busy_skips = withBase("stack_busy_skips", function(LS)
		T.check(not LS.Busy(), "an idle stack is not Busy")
		LS.Push("Dungeon", { Lighting = { Brightness = 0.5 } }, 1.5)
		T.check(LS.Busy(), "a 1.5 s Push: Busy() is true while its fade runs")
		KC.advance(0.5)
		T.check(LS.Busy(), "still Busy 0.5 s in")
		-- SetBase during the fade: stores the base, does not cancel or restart the Dungeon fade, applies nothing yet
		LS.SetBase({ Lighting = { Brightness = 1.4, ClockTime = 21 } }, 2)
		T.check(LS.Busy() and Lighting.ClockTime == 14.5, "SetBase while Busy: deferred (ClockTime still 14.5, the fade still runs)", tostring(Lighting.ClockTime))
		T.eq(LS.Value("Lighting", "Brightness", "Dungeon"), 1.4, "SetBase while Busy: the base is stored")
		KC.advance(1.1) -- the Dungeon fade ends 1.5 s after the Push (a restarted 2 s tween would still run)
		T.check(Lighting.Brightness == 0.5 and not LS.Busy(), "the Dungeon fade completes on its own time; Busy() false after", tostring(Lighting.Brightness))
		T.eq(Lighting.ClockTime, 14.5, "nothing applied the deferred base by itself")
		-- the next refresh after the fade applies the stored base
		LS.SetBase({ Lighting = { Brightness = 1.4, ClockTime = 21 } }, 0)
		T.check(Lighting.Brightness == 0.5 and Lighting.ClockTime == 21, "the next SetBase applies (ClockTime 21, Dungeon's Brightness wins)", tostring(Lighting.ClockTime))
		-- a Pop fade is Busy too, and lands on the moved base
		LS.Pop("Dungeon", 1.5)
		T.check(LS.Busy(), "a 1.5 s Pop: Busy() is true")
		KC.advance(1.7)
		T.check(Lighting.Brightness == 1.4 and not LS.Busy(), "Pop fade done: Brightness = the moved base 1.4, Busy() false", tostring(Lighting.Brightness))
	end)

	-- a Lighting child of `class` for the scenario (made when the client has none; `made` = remove it afterwards)
	local function ensureChild(parent, class)
		local inst = parent:FindFirstChildOfClass(class)
		if inst then
			return inst, false
		end
		inst = Instance.new(class)
		inst.Parent = parent
		return inst, true
	end

	S.stack_setbase_instant = withBase("stack_setbase_instant", function(LS)
		local SCy = require(Mock.GetPath(ROOTS["shared"] .. "/SkyCycle"))
		T.check(type(SCy.Integer) == "table" and SCy.Integer.StarCount == true, "SkyCycle.Integer names StarCount (whole numbers: set at once)")
		local sky, made = ensureChild(Lighting, "Sky")
		local savedStars = LS.Value("Sky", "StarCount", "Dungeon")
		LS.SetBase({ Sky = { StarCount = 0 } }, 0)
		T.eq(sky.StarCount, 0, "SetBase 0 s: StarCount 0")
		-- a tweened SetBase: StarCount jumps at once, Brightness tweens
		LS.SetBase({ Lighting = { Brightness = 1 }, Sky = { StarCount = 3000 } }, 2)
		T.check(sky.StarCount == 3000 and Lighting.Brightness == 2, "SetBase 2 s: StarCount 3000 at once (never tweened), Brightness still tweening", tostring(sky.StarCount) .. " / " .. tostring(Lighting.Brightness))
		KC.advance(0.5)
		T.check(sky.StarCount == 3000 and sky.StarCount == math.floor(sky.StarCount), "StarCount stays a whole number mid-tween", tostring(sky.StarCount))
		KC.advance(1.7)
		-- a Push that names StarCount: at once too
		LS.Push("Dungeon", { Sky = { StarCount = 1500 } }, 1.5)
		T.eq(sky.StarCount, 1500, "Push 1.5 s with StarCount: set at once")
		LS.Pop("Dungeon", 0)
		KC.advance(0.1)
		-- the instant set: ClockTime jumps (14.5 -> 18.4) while Brightness tweens
		LS.SetBase({ Lighting = { Brightness = 1.5, ClockTime = 18.4 } }, 2, { Lighting = { ClockTime = true } })
		T.check(math.abs(Lighting.ClockTime - 18.4) < 1e-9 and math.abs(Lighting.Brightness - 1) < 1e-9, "SetBase with instant ClockTime: the clock jumps at once, Brightness tweens", tostring(Lighting.ClockTime) .. " / " .. tostring(Lighting.Brightness))
		KC.advance(2.2)
		-- without the instant set the clock tweens as before
		LS.SetBase({ Lighting = { ClockTime = 19 } }, 2)
		T.check(Lighting.ClockTime < 19 - 1e-6, "SetBase without instant: ClockTime tweens", tostring(Lighting.ClockTime))
		KC.advance(2.2)
		-- asked while Busy: stored, then set at once by the next apply (here the Pop fade)
		LS.Push("Dungeon", { Lighting = { Brightness = 0.5 } }, 1.5)
		LS.SetBase({ Lighting = { ClockTime = 7 } }, 2, { Lighting = { ClockTime = true } })
		T.check(math.abs(Lighting.ClockTime - 19) < 1e-9, "an instant SetBase while Busy waits (ClockTime still 19)", tostring(Lighting.ClockTime))
		KC.advance(1.7)
		LS.Pop("Dungeon", 1.5)
		T.check(math.abs(Lighting.ClockTime - 7) < 1e-9, "the next apply (a 1.5 s Pop) sets the waiting clock jump at once", tostring(Lighting.ClockTime))
		KC.advance(1.7)
		LS.SetBase({ Lighting = { ClockTime = 14.5 }, Sky = { StarCount = savedStars } }, 0)
		if made then
			sky:Destroy()
		end
	end)

	----------------------------------------------------------------------------------------------------
	-- Task 5: SkyController (the cycle and the raid skies on the client, the battle lift, lamps, fireflies)
	----------------------------------------------------------------------------------------------------
	local Workspace = game:GetService("Workspace")
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local Cfg = require(Mock.GetPath(ROOTS["shared"] .. "/Config"))
	local A = Cfg.Sky.Attr

	local function skyModules()
		local LS = stackModule()
		local inst = Mock.GetPath(ROOTS["client"] .. "/Controllers/SkyController")
		local ok, SC = false, nil
		if inst then
			ok, SC = pcall(require, inst)
		end
		if not T.check(LS ~= nil and ok and type(SC) == "table", "client/Controllers/SkyController loads", tostring(SC)) then
			return nil
		end
		for _, f in ipairs({ "Init", "Start", "Stop", "Refresh", "State" }) do
			if not T.check(type(SC[f]) == "function", "SkyController." .. f .. " is a function") then
				return nil
			end
		end
		local SCy = require(Mock.GetPath(ROOTS["shared"] .. "/SkyCycle"))
		return SC, LS, SCy
	end

	-- publish the clock as SkyService does: the loop at `pos` s now (speed 1), optionally a raid event
	local function publish(pos, event, eventAt)
		local now = Workspace:GetServerTimeNow()
		Workspace:SetAttribute(A.Epoch, now)
		Workspace:SetAttribute(A.Speed, 1)
		Workspace:SetAttribute(A.Offset, pos)
		Workspace:SetAttribute(A.Event, event or "")
		Workspace:SetAttribute(A.EventAt, eventAt or (now - 100))
		return now
	end

	local function unpublish()
		for _, key in pairs(A) do
			Workspace:SetAttribute(key, nil)
		end
	end

	-- the cycle preset SkyController should show now
	local function expected(SCy, event, eventBlend)
		local now = Workspace:GetServerTimeNow()
		local at = SCy.At(now, Workspace:GetAttribute(A.Epoch), Workspace:GetAttribute(A.Speed), Workspace:GetAttribute(A.Offset))
		return SCy.Preset(at, event, eventBlend or 0, nil), at
	end

	local function near(a, b, eps)
		eps = eps or 1e-6
		if typeof(a) == "Color3" and typeof(b) == "Color3" then
			return math.abs(a.R - b.R) < eps and math.abs(a.G - b.G) < eps and math.abs(a.B - b.B) < eps
		end
		return type(a) == "number" and type(b) == "number" and math.abs(a - b) < eps
	end

	-- each SkyController scenario: no Dungeon / SkyLift left, the controller stopped and the clock unpublished after
	local function withSky(name, fn)
		return guarded(name, function()
			local SC, LS, SCy = skyModules()
			if not SC then
				return
			end
			local before = LS.Ids()
			local savedBattle = LocalPlayer:GetAttribute(Cfg.Attr.InBattle)
			local savedBase = { Brightness = LS.Value("Lighting", "Brightness", "Dungeon"), ClockTime = LS.Value("Lighting", "ClockTime", "Dungeon") }
			local ok, err = pcall(fn, SC, LS, SCy)
			T.check(ok, name .. " ran without errors", tostring(err))
			LocalPlayer:SetAttribute(Cfg.Attr.InBattle, savedBattle)
			unpublish()
			pcall(SC.Refresh)
			KC.advance(2.2)
			LS.Pop("Dungeon", 0)
			LS.Pop(Cfg.Sky.Lift.Id, 0)
			LS.SetBase({ Lighting = savedBase }, 0)
			T.eq(#LS.Ids(), #before, name .. ": the stack is as it was")
			T.check(SC.State().Lift ~= true and (SC.State().Fireflies or 0) == 0, name .. ": inert again once the clock is gone (no lift, no fireflies)")
		end)
	end

	S.client_sky_first_instant = withSky("client_sky_first_instant", function(SC, LS, SCy)
		SC.Stop()
		unpublish()
		LS.SetBase({ Lighting = { Brightness = 2.5, ClockTime = 14.5 } }, 0)
		SC.Start()
		T.check(Lighting.Brightness == 2.5 and SC.State().Phase == nil, "no SkyEpoch: SkyController is inert (the boot sky stays)", tostring(Lighting.Brightness))
		SC.Stop()
		publish(1100) -- mid Night
		SC.Start()
		local want = expected(SCy)
		local st = SC.State()
		T.check(st.Phase == "Night" and st.Look == "Night", "Start with the clock at 1100 s: Night", tostring(st.Phase))
		local bad
		for _, prop in ipairs({ "Brightness", "OutdoorAmbient", "Ambient", "ColorShift_Top", "ExposureCompensation" }) do
			if not near(Lighting[prop], want.Lighting[prop], 1e-3) then
				bad = bad or (prop .. " " .. tostring(Lighting[prop]) .. " vs " .. tostring(want.Lighting[prop]))
			end
		end
		T.check(bad == nil and near(Lighting.ClockTime, want.Lighting.ClockTime, 1e-3), "the first apply is instant (seconds 0): Lighting = the Night preset at once", bad or tostring(Lighting.ClockTime))
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm then
			T.check(near(atm.Density, want.Atmosphere.Density, 1e-3), "Atmosphere at once too", tostring(atm.Density))
		end
	end)

	S.client_sky_refresh = withSky("client_sky_refresh", function(SC, LS, SCy)
		SC.Stop()
		publish(300)
		local function rsConns()
			local n = 0
			for sigName, count in pairs(Mock.ConnectionReport()) do
				if sigName:find("RenderStepped", 1, true) or sigName:find("Heartbeat", 1, true) or sigName:find("Stepped", 1, true) then
					n = n + count
				end
			end
			return n
		end
		local conns0 = rsConns()
		SC.Start()
		SC.Start()
		T.eq(SC.State().Loops, 1, "Start twice: one SkyController loop")
		T.eq(rsConns(), conns0, "no RenderStepped / Heartbeat / Stepped connection (a 2 s loop only)")
		local calls = {}
		local real = LS.SetBase
		LS.SetBase = function(preset, seconds, instant)
			calls[#calls + 1] = { seconds = seconds, instant = instant, preset = preset }
			return real(preset, seconds, instant)
		end
		local ok, err = pcall(function()
			KC.advance(4.1)
			local tweened = 0
			for _, c in ipairs(calls) do
				if c.seconds == Cfg.Sky.Cycle.Tween then
					tweened = tweened + 1
				end
			end
			T.check(#calls >= 2 and tweened == #calls, fmt("4 s of the loop: SetBase every %d s with a %d s tween", Cfg.Sky.Cycle.Refresh, Cfg.Sky.Cycle.Tween), fmt("%d calls, %d tweened", #calls, tweened))
			-- a Dungeon fade running: the refresh skips (no SetBase, the fade never restarts)
			LS.Push("Dungeon", { Lighting = { Brightness = 0.6 } }, 5)
			local n0, skipped0 = #calls, SC.State().Skipped
			KC.advance(4.1)
			T.check(#calls == n0 and SC.State().Skipped > skipped0 and LS.Busy(), "while Busy() the refresh skips (no SetBase)", fmt("%d new calls", #calls - n0))
			KC.advance(1.2)
			LS.Pop("Dungeon", 0)
			KC.advance(2.1)
			T.check(#calls > n0, "after the fade the refresh applies again")
			-- Sunset -> Night (17 -> 18.4, across the ~18 h horizon where sunlight and shadows go off): never a jump;
			-- the loop's 2 s steps walk the clock across the 75 s blend
			local C = Cfg.Sky.Cycle
			local nightAt = C.Seconds.Dawn + C.Seconds.Day + C.Seconds.Sunset
			publish(nightAt - C.Blend - 2)
			KC.advance(0.05)
			calls = {}
			for _ = 1, math.ceil((C.Blend + 8) / C.Refresh) do
				KC.advance(C.Refresh)
			end
			local walkBad, maxStep, prevClock, instants = nil, 0, nil, 0
			for _, c in ipairs(calls) do
				local clock = c.preset.Lighting.ClockTime
				if c.instant then
					instants = instants + 1
				end
				if prevClock then
					if clock < prevClock - 1e-9 then
						walkBad = walkBad or fmt("%.3f after %.3f", clock, prevClock)
					end
					maxStep = math.max(maxStep, clock - prevClock)
				end
				prevClock = clock
			end
			local first = calls[1] and calls[1].preset.Lighting.ClockTime
			T.check(#calls >= 35 and SC.State().Phase == "Night" and first ~= nil and first <= 17 + 1e-6 and prevClock >= Cfg.Sky.Looks.Night.Clock[1] - 1e-6, fmt("Sunset -> Night through the loop: %d refreshes from %.2f h to %.2f h", #calls, first or -1, prevClock or -1), tostring(SC.State().Phase))
			T.check(walkBad == nil and maxStep <= 0.2, "Sunset -> Night: ClockTime monotonic across the blend, no 2 s refresh step over 0.2 h", fmt("%s, max step %.3f h", tostring(walkBad), maxStep))
			T.check(instants == 0, "Sunset -> Night: no instant clock set (the sun goes down over the blend, not in one frame)", fmt("%d instant sets", instants))
			-- the Night -> Dawn wrap (23.6 -> 7) is the one backward step: set at once, never tweened back through the day
			publish(nightAt + C.Seconds.Night - 1)
			KC.advance(0.05)
			calls = {}
			KC.advance(2.1)
			SC.Refresh()
			local jumped
			for _, c in ipairs(calls) do
				if c.instant and c.instant.Lighting and c.instant.Lighting.ClockTime then
					jumped = c
				end
			end
			T.check(jumped ~= nil and SC.State().Phase == "Dawn" and near(Lighting.ClockTime, Cfg.Sky.Looks.Dawn.Clock[1], 0.05), "Night -> Dawn: the backward wrap (23.6 -> 7) is set at once", tostring(Lighting.ClockTime))
			local inPhase = #calls
			KC.advance(2.1)
			local again = false
			for i = inPhase + 1, #calls do
				if calls[i].instant then
					again = true
				end
			end
			T.check(not again, "inside a phase the clock tweens (no instant set)")
		end)
		LS.SetBase = real
		T.check(ok, "client_sky_refresh body", tostring(err))
		SC.Stop()
		KC.advance(2.2)
		T.eq(SC.State().Loops, 0, "Stop ends the loop")
		SC.Start()
	end)

	S.client_sky_event = withSky("client_sky_event", function(SC, LS, SCy)
		local now = publish(300)
		SC.Refresh()
		T.check(SC.State().Event == nil and SC.State().EventBlend == 0, "no SkyEvent: the plain cycle")
		Workspace:SetAttribute(A.Event, "storm_titan")
		Workspace:SetAttribute(A.EventAt, Workspace:GetServerTimeNow())
		SC.Refresh()
		local st = SC.State()
		T.check(st.Event == "storm_titan" and st.EventBlend < 0.1, "raid start: the blend begins at 0", tostring(st.EventBlend))
		KC.advance(1.5)
		SC.Refresh()
		T.check(near(SC.State().EventBlend, 0.5, 0.05), "1.5 s in: blend ~0.5", tostring(SC.State().EventBlend))
		KC.advance(1.6)
		SC.Refresh()
		st = SC.State()
		T.check(st.EventBlend == 1 and st.Look == "storm_titan" and st.Theme == Cfg.Sky.RaidThemes.storm_titan, "after EventBlend (3) s: the full raid sky (theme storm_teal)", tostring(st.EventBlend) .. " " .. tostring(st.Theme))
		T.check(near(LS.Value("Lighting", "Brightness"), Cfg.Sky.Looks.storm_titan.Lighting.Brightness, 1e-3), "the base is the raid look", tostring(LS.Value("Lighting", "Brightness")))
		-- (the mock's tweens land only when they complete: stop the loop so the last 2 s step is not restarted)
		SC.Stop()
		KC.advance(2.2)
		T.check(near(Lighting.Brightness, Cfg.Sky.Looks.storm_titan.Lighting.Brightness, 1e-3), "Lighting lands on the raid look", tostring(Lighting.Brightness))
		-- a late joiner mid-raid: a fresh Start lands on the raid sky at once
		LS.SetBase({ Lighting = { Brightness = 2.5 } }, 0)
		SC.Start()
		T.check(SC.State().EventBlend == 1 and near(Lighting.Brightness, Cfg.Sky.Looks.storm_titan.Lighting.Brightness, 1e-3), "a late joiner mid-raid: the raid sky at once", tostring(Lighting.Brightness))
		-- the raid ends: back to the cycle over 3 s
		Workspace:SetAttribute(A.Event, "")
		Workspace:SetAttribute(A.EventAt, Workspace:GetServerTimeNow())
		SC.Refresh()
		T.check(SC.State().Event == "storm_titan" and SC.State().EventBlend > 0.9, "raid end: the blend starts back from 1")
		KC.advance(1.5)
		SC.Refresh()
		T.check(near(SC.State().EventBlend, 0.5, 0.05), "1.5 s after the end: ~0.5", tostring(SC.State().EventBlend))
		KC.advance(1.6)
		SC.Refresh()
		st = SC.State()
		T.check(st.Event == nil and st.EventBlend == 0 and st.Look == "Day", "3 s after the end: the cycle again (Day)", tostring(st.Event) .. " " .. tostring(st.Look))
		-- junk event ids never show a raid sky
		Workspace:SetAttribute(A.Event, "no_such_boss")
		Workspace:SetAttribute(A.EventAt, Workspace:GetServerTimeNow() - 10)
		SC.Refresh()
		T.check(SC.State().Event == nil, "an unknown SkyEvent id = no raid sky")
		local _ = now
	end)

	S.client_sky_event_back_to_back = withSky("client_sky_event_back_to_back", function(SC, LS, SCy)
		SC.Stop() -- the refreshes by hand (the base is read back: no tween timing involved)
		publish(300) -- Day
		Workspace:SetAttribute(A.Event, "storm_titan")
		Workspace:SetAttribute(A.EventAt, Workspace:GetServerTimeNow() - 10)
		SC.Refresh()
		local st = SC.State()
		T.check(st.Event == "storm_titan" and st.EventBlend == 1 and st.Look == "storm_titan", "the storm raid is up: the full storm sky", tostring(st.Event) .. " " .. tostring(st.EventBlend))
		local function presets()
			local at = SCy.At(Workspace:GetServerTimeNow(), Workspace:GetAttribute(A.Epoch), Workspace:GetAttribute(A.Speed), Workspace:GetAttribute(A.Offset))
			return SCy.Preset(at, "storm_titan", 1, nil), SCy.Preset(at, "lava_golem", 1, nil), SCy.Preset(at, nil, 0, nil)
		end
		local function base(prop)
			return LS.Value("Lighting", prop, "Dungeon")
		end
		-- the lava golem spawns with no clear between (SkyService.SetEvent: Event + EventAt, no "")
		Workspace:SetAttribute(A.Event, "lava_golem")
		Workspace:SetAttribute(A.EventAt, Workspace:GetServerTimeNow())
		local line = T.tally("storm -> lava: the base stays on the line between the two raid looks (never toward the cycle)")
		local swap = T.tally("storm -> lava: look, theme and clock stay storm's below blend 0.5 and are lava's from 0.5")
		local firstBlend
		for _ = 0, 6 do
			SC.Refresh()
			st = SC.State()
			local pS, pL = presets()
			local x = st.EventBlend
			firstBlend = firstBlend or x
			for _, prop in ipairs({ "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient" }) do
				local a, b, v = pS.Lighting[prop], pL.Lighting[prop], base(prop)
				local want = (typeof(a) == "Color3") and a:Lerp(b, x) or (a + (b - a) * x)
				line:case(st.Event == "lava_golem" and near(v, want, 1e-6), fmt("blend %.2f %s %s vs %s", x, prop, tostring(v), tostring(want)))
			end
			local wantLook = x >= 0.5 and "lava_golem" or "storm_titan"
			local wantTheme = Cfg.Sky.RaidThemes[wantLook]
			local wantClock = Cfg.Sky.Looks[wantLook].Clock[1]
			swap:case(st.Look == wantLook and st.Theme == wantTheme and near(base("ClockTime"), wantClock, 1e-6), fmt("blend %.2f look %s theme %s clock %s", x, tostring(st.Look), tostring(st.Theme), tostring(base("ClockTime"))))
			KC.advance(0.5)
		end
		line:report()
		swap:report()
		local pS0, _, pC = presets()
		T.check(firstBlend ~= nil and firstBlend < 0.1, "the new raid's blend starts at 0", tostring(firstBlend))
		T.check(math.abs(pS0.Lighting.Brightness - pC.Lighting.Brightness) > 0.2, "(the storm and the cycle looks differ, so a flash back would show)")
		SC.Refresh()
		st = SC.State()
		local _, pL = presets()
		T.check(st.Event == "lava_golem" and st.EventBlend == 1 and st.EventFrom == nil and near(base("Brightness"), pL.Lighting.Brightness, 1e-6), "3 s on: the full lava sky, nothing left to blend from", tostring(st.EventBlend) .. " " .. tostring(st.EventFrom))
		-- the raid ends: back to the cycle from the lava sky over 3 s
		Workspace:SetAttribute(A.Event, "")
		Workspace:SetAttribute(A.EventAt, Workspace:GetServerTimeNow())
		SC.Refresh()
		T.check(SC.State().Event == "lava_golem" and SC.State().EventBlend > 0.95, "the lava raid ends: the blend back starts from 1")
		KC.advance(3.2)
		SC.Refresh()
		T.check(SC.State().Event == nil and SC.State().EventBlend == 0, "3 s after: the plain cycle")
		-- a raid that ends while still blending in leaves from where it was (no jump up to the full raid sky)
		Workspace:SetAttribute(A.Event, "frost_wyrm")
		Workspace:SetAttribute(A.EventAt, Workspace:GetServerTimeNow())
		KC.advance(0.9)
		SC.Refresh()
		local mid = SC.State().EventBlend
		Workspace:SetAttribute(A.Event, "")
		Workspace:SetAttribute(A.EventAt, Workspace:GetServerTimeNow())
		SC.Refresh()
		st = SC.State()
		T.check(mid > 0.2 and mid < 0.4 and st.Event == "frost_wyrm" and st.EventBlend <= mid + 1e-6, fmt("the frost raid ends at blend %.2f: it leaves from %.2f (not 1)", mid, st.EventBlend))
		KC.advance(1.5)
		SC.Refresh()
		T.check(SC.State().EventBlend < mid * 0.6, "and keeps fading out", tostring(SC.State().EventBlend))
		KC.advance(1.7)
		SC.Refresh()
		T.check(SC.State().Event == nil, "gone after 3 s")
		SC.Start()
	end)

	S.client_sky_battle_lift = withSky("client_sky_battle_lift", function(SC, LS, SCy)
		local L = Cfg.Sky.Lift
		local function hasLift()
			for _, id in ipairs(LS.Ids()) do
				if id == L.Id then
					return true
				end
			end
			return false
		end
		publish(1100) -- Night
		SC.Refresh()
		KC.advance(2.1)
		T.check(not hasLift() and SC.State().Lift ~= true, "Night, no battle: no lift")
		LocalPlayer:SetAttribute(Cfg.Attr.InBattle, "B12")
		KC.advance(0.05)
		T.check(hasLift() and SC.State().Lift == true and LS.Busy(), "InBattle B12 at Night: Push SkyLift (fading in)")
		KC.advance(L.Seconds + 0.1)
		T.check(near(Lighting.Brightness, L.Preset.Lighting.Brightness, 1e-6) and near(Lighting.OutdoorAmbient, L.Preset.Lighting.OutdoorAmbient, 1e-6), fmt("after %.1f s: the twilight lift (Brightness %.2f)", L.Seconds, L.Preset.Lighting.Brightness), tostring(Lighting.Brightness))
		LocalPlayer:SetAttribute(Cfg.Attr.InBattle, nil)
		KC.advance(0.05)
		T.check(not hasLift() and SC.State().Lift ~= true and LS.Busy(), "battle over: Pop SkyLift (fading out)")
		KC.advance(L.Seconds + 0.1)
		local want = expected(SCy)
		T.check(near(Lighting.Brightness, want.Lighting.Brightness, 0.05), "after the fade: the night again", tostring(Lighting.Brightness))
		-- a dungeon run ("D...") stays under the dungeon preset: no lift
		LocalPlayer:SetAttribute(Cfg.Attr.InBattle, "D3")
		KC.advance(0.05)
		SC.Refresh()
		T.check(not hasLift(), "InBattle D3 (a dungeon run): no lift")
		LocalPlayer:SetAttribute(Cfg.Attr.InBattle, nil)
		KC.advance(0.05)
		-- the day needs no lift
		publish(300)
		LocalPlayer:SetAttribute(Cfg.Attr.InBattle, "B13")
		KC.advance(0.05)
		SC.Refresh()
		T.check(not hasLift(), "InBattle at Day: no lift")
		-- night falls during a battle: the lift comes; day breaks: it goes
		publish(1100)
		SC.Refresh()
		T.check(hasLift(), "Night falls mid-battle: the lift comes")
		KC.advance(L.Seconds + 0.1)
		publish(100)
		SC.Refresh()
		T.check(not hasLift(), "Dawn mid-battle: the lift goes")
		LocalPlayer:SetAttribute(Cfg.Attr.InBattle, nil)
		KC.advance(L.Seconds + 0.1)
	end)

	-- a test lobby (NimbusLobby: made when the client has none, and removed again)
	local function testLobby()
		local lobby = Workspace:FindFirstChild("NimbusLobby")
		local made = false
		if not lobby then
			lobby = Instance.new("Folder")
			lobby.Name = "NimbusLobby"
			lobby.Parent = Workspace
			made = true
		end
		local box = Instance.new("Model")
		box.Name = "SkyTestProps"
		box.Parent = lobby
		return box, function()
			box:Destroy()
			if made then
				lobby:Destroy()
			end
		end
	end

	local function lampPart(parent, name, brightness, pos)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Position = pos or Vector3.new(0, 10, 0)
		p.Parent = parent
		local l = Instance.new("PointLight")
		l.Brightness = brightness
		l.Parent = p
		return l
	end

	S.client_sky_lamps = withSky("client_sky_lamps", function(SC, LS, SCy)
		local box, cleanup = testLobby()
		local k = Cfg.Sky.Lamps.Night
		local glass = lampPart(box, "LampGlass", 1.0)
		local lantern = lampPart(box, "LanternLight", 0.8)
		local stall = lampPart(box, "StallLight", 0.8)
		local dome = lampPart(box, "DomeGlow", 0.9)
		local other = lampPart(box, "Window", 1.0)
		local ok, err = pcall(function()
			publish(300)
			SC.Refresh()
			T.check(glass.Brightness == 1.0 and dome.Brightness == 0.9, "Day: lamps at their own value")
			publish(1100)
			SC.Refresh()
			T.check(near(glass.Brightness, 1.0 * k) and near(lantern.Brightness, 0.8 * k) and near(stall.Brightness, 0.8 * k) and near(dome.Brightness, 0.9 * k), fmt("Night: LampGlass / LanternLight / StallLight / DomeGlow x%.1f", k), fmt("%.3f %.3f %.3f %.3f", glass.Brightness, lantern.Brightness, stall.Brightness, dome.Brightness))
			T.eq(other.Brightness, 1.0, "Night: another light is untouched")
			T.check((SC.State().Lamps or 0) >= 4, "State().Lamps counts the raised lamps", tostring(SC.State().Lamps))
			-- written on a look change only: a second Night refresh writes nothing
			glass.Brightness = 3
			SC.Refresh()
			KC.advance(2.1)
			T.eq(glass.Brightness, 3, "the same look again: no lamp write (phase changes only)")
			glass.Brightness = 1.0 * k
			publish(100) -- Dawn
			SC.Refresh()
			T.check(near(glass.Brightness, 1.0) and near(lantern.Brightness, 0.8) and near(dome.Brightness, 0.9), "Dawn: every lamp back to its own value", fmt("%.3f %.3f", glass.Brightness, dome.Brightness))
			T.eq(SC.State().Lamps or 0, 0, "Dawn: no lamp raised")
		end)
		cleanup()
		T.check(ok, "client_sky_lamps body", tostring(err))
	end)

	S.client_sky_fireflies = withSky("client_sky_fireflies", function(SC, LS, SCy)
		local GQ = require(Mock.GetPath(ROOTS["client"] .. "/GraphicsQuality"))
		local mode0 = GQ.Effective()
		local box, cleanup = testLobby()
		local F = Cfg.Sky.Fireflies
		for i = 1, F.Max + 3 do
			local tree = Instance.new("Model")
			tree.Name = (i % 2 == 0) and "RoundTree" or "BlossomTree"
			local trunk = Instance.new("Part")
			trunk.Anchored = true
			trunk.Position = Vector3.new(i * 30, 5, 0)
			trunk.Parent = tree
			tree.PrimaryPart = trunk
			tree.Parent = box
		end
		local function emitters()
			local folder = Workspace:FindFirstChild(F.Folder)
			local on, total = 0, 0
			if folder then
				for _, d in ipairs(folder:GetDescendants()) do
					if d:IsA("ParticleEmitter") then
						total = total + 1
						if d.Enabled then
							on = on + 1
						end
					end
				end
			end
			return on, total, folder
		end
		local ok, err = pcall(function()
			GQ.Apply("High")
			KC.advance(0.6)
			publish(300)
			SC.Refresh()
			T.eq((emitters()), 0, "Day: no fireflies")
			publish(1100)
			SC.Refresh()
			local on, total, folder = emitters()
			T.check(on > 0 and on <= F.Max and total == on, fmt("Night + High: a capped firefly group (%d emitters, max %d)", on, F.Max), fmt("%d on / %d", on, total))
			T.eq(SC.State().Fireflies, on, "State().Fireflies = the emitters on")
			local capped = true
			if folder then
				for _, d in ipairs(folder:GetDescendants()) do
					if d:IsA("ParticleEmitter") and (d.Rate > F.Rate + 1e-9 or d.LightEmission < 0.5) then
						capped = false
					end
					if d:IsA("BasePart") and (d.CanCollide or d.CanTouch or d.CanQuery or d.Transparency < 1) then
						capped = false
					end
				end
			end
			T.check(capped, "fireflies: low rate, glowing, on invisible non-colliding hosts")
			SC.Refresh()
			T.eq(select(2, emitters()), on, "a second Night refresh makes no more")
			GQ.Apply("Low")
			KC.advance(0.6)
			SC.Refresh()
			T.check(emitters() == 0 and (SC.State().Fireflies or 0) == 0, "Low graphics: no fireflies")
			GQ.Apply("High")
			KC.advance(0.6)
			SC.Refresh()
			T.check(emitters() > 0, "High again at Night: the fireflies come back")
			publish(300)
			SC.Refresh()
			T.check(emitters() == 0 and Workspace:FindFirstChild(F.Folder) == nil, "Day: the fireflies are gone")
		end)
		GQ.Apply(mode0)
		KC.advance(0.6)
		cleanup()
		T.check(ok, "client_sky_fireflies body", tostring(err))
	end)

	S.client_gfx_cloud_cap = withSky("client_gfx_cloud_cap", function(SC, LS, SCy)
		local GQ = require(Mock.GetPath(ROOTS["client"] .. "/GraphicsQuality"))
		T.check(type(GQ.Recap) == "function", "GraphicsQuality.Recap is a function")
		local mode0 = GQ.Effective()
		local terrain = Workspace:FindFirstChildOfClass("Terrain")
		if not T.check(terrain ~= nil, "the client has a Terrain") then
			return
		end
		local clouds, made = ensureChild(terrain, "Clouds")
		local saved = LS.Value("Clouds", "Density", "GfxLow")
		local ok, err = pcall(function()
			GQ.Apply("High")
			KC.advance(0.6)
			LS.SetBase({ Clouds = { Density = 0.3 } }, 0)
			GQ.Apply("Low")
			KC.advance(0.6)
			T.check(near(clouds.Density, 0.3), "Low under a thin night sky (0.3): the cap keeps the cycle's 0.3", tostring(clouds.Density))
			GQ.Apply("High")
			KC.advance(0.6)
			LS.SetBase({ Clouds = { Density = 0.65 } }, 0)
			GQ.Apply("Low")
			KC.advance(0.6)
			T.check(near(clouds.Density, 0.4), "Low under a full sunset sky (0.65): capped at 0.4", tostring(clouds.Density))
			-- the cycle thins while Low is on: Recap updates GfxLow in place, the next SetBase carries the new cap
			LS.SetBase({ Clouds = { Density = 0.35 } }, 0)
			T.check(near(clouds.Density, 0.4), "the base moved, GfxLow still holds its old 0.4", tostring(clouds.Density))
			T.check(GQ.Recap() == true, "Recap: the cap moved")
			T.check(near(LS.Value("Clouds", "Density"), 0.35) and near(clouds.Density, 0.4) and not LS.Busy(), "Recap: GfxLow holds 0.35 at once, nothing applied (no fade)", tostring(LS.Value("Clouds", "Density")) .. " / " .. tostring(clouds.Density))
			LS.SetBase({ Clouds = { Density = 0.35 } }, 0)
			T.check(near(clouds.Density, 0.35), "the next SetBase carries it: GfxLow follows the cycle down to 0.35", tostring(clouds.Density))
			LS.SetBase({ Clouds = { Density = 0.6 } }, 0)
			GQ.Recap()
			LS.SetBase({ Clouds = { Density = 0.6 } }, 0)
			T.check(near(clouds.Density, 0.4), "Recap + the next SetBase: back up to the 0.4 cap", tostring(clouds.Density))
			T.check(GQ.Recap() == false, "Recap with the cap unchanged: nothing to do")
			GQ.Apply("High")
			KC.advance(0.6)
			T.check(near(clouds.Density, 0.6), "High: the cycle's own 0.6", tostring(clouds.Density))
			-- SkyController calls Recap after each applied refresh while Low (the refresh after carries the cap)
			SC.Stop()
			GQ.Apply("Low")
			KC.advance(0.6)
			publish(1100)
			SC.Refresh()
			KC.advance(2.1)
			SC.Refresh()
			KC.advance(2.1)
			local want = expected(SCy)
			T.check(near(clouds.Density, math.min(0.4, want.Clouds.Density), 1e-3), "Low at Night through SkyController: min(0.4, the night's density)", tostring(clouds.Density) .. " vs " .. tostring(want.Clouds.Density))
		end)
		GQ.Apply(mode0)
		KC.advance(0.6)
		LS.SetBase({ Clouds = { Density = saved } }, 0)
		if made then
			clouds:Destroy()
		end
		SC.Start()
		T.check(ok, "client_gfx_cloud_cap body", tostring(err))
	end)

	S.client_gfx_recap_keeps_tweens = withSky("client_gfx_recap_keeps_tweens", function(SC, LS, SCy)
		local GQ = require(Mock.GetPath(ROOTS["client"] .. "/GraphicsQuality"))
		local mode0 = GQ.Effective()
		local terrain = Workspace:FindFirstChildOfClass("Terrain")
		if not T.check(terrain ~= nil, "the client has a Terrain") then
			return
		end
		local clouds, made = ensureChild(terrain, "Clouds")
		local saved = LS.Value("Clouds", "Density", "GfxLow")
		local realSet, realPush = LS.SetBase, LS.Push
		local ok, err = pcall(function()
			SC.Stop()
			GQ.Apply("High")
			KC.advance(0.6)
			publish(300) -- Day: clouds 0.6, so Low caps them at 0.4
			SC.Refresh()
			KC.advance(2.1)
			GQ.Apply("Low")
			KC.advance(0.6)
			T.check(near(GQ._St.CloudDensity, 0.4) and not LS.Busy(), "Low under the day sky: GfxLow caps the clouds at 0.4", tostring(GQ._St.CloudDensity))
			-- night falls (clouds 0.35): this refresh moves the base AND the cap
			publish(1100)
			LS.SetBase({ Lighting = { Brightness = 2.5 } }, 0)
			local started, pushes = {}, {}
			LS.SetBase = function(preset, seconds, instant)
				local r = realSet(preset, seconds, instant)
				for tw in pairs(Mock.ActiveTweens) do
					local target = tw.Instance
					if target == Lighting or target == clouds then
						started[#started + 1] = tw
					end
				end
				return r
			end
			LS.Push = function(id, preset, seconds)
				pushes[#pushes + 1] = tostring(id)
				return realPush(id, preset, seconds)
			end
			SC.Refresh()
			LS.SetBase, LS.Push = realSet, realPush
			local want = expected(SCy)
			T.check(near(GQ._St.CloudDensity, math.min(0.4, want.Clouds.Density)), "the refresh ran Recap: the cap moved to the night's density", tostring(GQ._St.CloudDensity))
			T.check(#pushes == 0, "no Push during the refresh (Recap updates GfxLow in place)", table.concat(pushes, ","))
			T.check(not LS.Busy(), "nothing Busy after it (the next refresh is not skipped)")
			local playing, linear = 0, 0
			for _, tw in ipairs(started) do
				if tw.PlaybackState.Name == "Playing" then
					playing = playing + 1
				end
				if tw.TweenInfo.EasingStyle.Name == "Linear" then
					linear = linear + 1
				end
			end
			T.check(#started > 0 and playing == #started and linear == #started, "the sky's base tweens still run, linear, after Recap (none cancelled or re-eased)", fmt("%d started, %d playing, %d linear", #started, playing, linear))
			KC.advance(2.1)
			T.check(near(Lighting.Brightness, want.Lighting.Brightness, 1e-3), "the Lighting tween lands on the night", tostring(Lighting.Brightness))
			SC.Refresh()
			KC.advance(2.1)
			T.check(near(clouds.Density, math.min(0.4, want.Clouds.Density), 1e-3), "the next refresh carries the new cap", tostring(clouds.Density))
		end)
		LS.SetBase, LS.Push = realSet, realPush
		GQ.Apply(mode0)
		KC.advance(0.6)
		LS.SetBase({ Clouds = { Density = saved } }, 0)
		if made then
			clouds:Destroy()
		end
		SC.Start()
		T.check(ok, "client_gfx_recap_keeps_tweens body", tostring(err))
	end)

	S.client_dungeon_density_follows = withSky("client_dungeon_density_follows", function(SC, LS, SCy)
		local DC = require(Mock.GetPath(ROOTS["client"] .. "/Controllers/DungeonController"))
		local M = DC._Mood
		if not T.check(type(M) == "table" and type(M.Build) == "function", "DungeonController._Mood.Build (the run's preset)") then
			return
		end
		local atm, made = ensureChild(Lighting, "Atmosphere")
		local saved = LS.Value("Atmosphere", "Density", "Dungeon")
		local add = M.Preset.AtmosphereAdd
		local ok, err = pcall(function()
			LS.SetBase({ Atmosphere = { Density = 0.3 } }, 0)
			local p1 = M.Build()
			T.check(p1.Atmosphere and near(p1.Atmosphere.Density, 0.3 + add), fmt("the dungeon adds %.2f to the cycle's 0.3", add), tostring(p1.Atmosphere and p1.Atmosphere.Density))
			LS.SetBase({ Atmosphere = { Density = 0.2 } }, 0)
			local p2 = M.Build()
			T.check(near(p2.Atmosphere.Density, 0.2 + add), "the cycle moved to 0.2: the dungeon follows it (no boot-time cache)", tostring(p2.Atmosphere.Density))
			LS.Push("Dungeon", p2, 0)
			local p3 = M.Build()
			T.check(near(p3.Atmosphere.Density, 0.2 + add), "a re-push while the dungeon is on never adds twice", tostring(p3.Atmosphere.Density))
			LS.Pop("Dungeon", 0)
		end)
		LS.SetBase({ Atmosphere = { Density = saved } }, 0)
		if made then
			atm:Destroy()
		end
		T.check(ok, "client_dungeon_density_follows body", tostring(err))
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
