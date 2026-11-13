-- smoke_kitb_sky.lua: the kit-b SKY lane (S1-S4 of .superpowers/slop-audit/round3/BUILD_PLAN.md; branch kitb-sky). Loaded
-- by tools/smoke.py in both worlds, ARGS.context picks the half. Each wave adds its scenarios here and their names on the
-- SKY line of tools/smoke.py (that line only).
--   S1 (haze bridge, raid cadence, pocket-fight refresh; sky audit F1-F3, the owner: "the sky changing (instant instead of
--   fading(animated)"):
--   skycycle_bridge_shape     (server world, pure) SkyCycle.Bridge(blend, half) -> k: 0 outside |blend - 0.5| < half, 1 at
--                             0.5, symmetric, rising toward the peak, never above 1, junk = 0; the cycle's bridge spans
--                             about 30 s of the 75 s phase blend
--   skycycle_bridge_peak_swaps_faces (server world, pure) across every phase change, every raid in (Day and Night) and a
--                             raid to raid change: the theme, the Skybox faces, StarCount and the raid's fixed clock change
--                             only between two samples where the bridge is at its peak (k >= 0.98), once; at the peak the
--                             air is thick (Density and cloud Cover well above both looks)
--   skycycle_bridge_keeps_floor (server world, pure) every step of every bridge (phase changes, raids in from Day / Night,
--                             raid to raid): Brightness >= 1, OutdoorAmbient >= 70, Density <= 0.7, Cover <= 1
--   skycycle_bridge_same_for_all (server world, pure) a long-running client (2 s steps since the epoch) and one that just
--                             joined compute the same bridged preset at each bridge peak
--   sky_raid_in8_out6         (client) a raid sky blends in over Config.Sky.Transitions.Raid.In (8) s and out over Out (6) s
--                             (Cycle.EventBlend is gone); the look swaps at the blend's midpoint
--   skycontroller_raid_cadence (client) the loop refreshes every 2 s with 2 s tweens, every 0.5 s with 0.5 s tweens while a
--                             raid blend runs (in and out), and 2 s again after
--   skycontroller_dev_speed_bridge (client; S1 review) at /sky speed 10 the whole phase blend refreshes every 0.5 s with
--                             0.5 s tweens, so the faces swap under thick air (the refresh before the swap >= 0.6 into the
--                             bridge); at speed 1 the phase blend keeps the 2 s cadence
--   skycontroller_localevent_refreshes_now (client) SetLocalEvent on / off refreshes at once (task.defer), not on the
--                             next 2 s tick; a stopped controller does not
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local abs, max, min = math.abs, math.max, math.min
local fmt = string.format

local function isColor(v)
	return typeof(v) == "Color3"
end

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

	-- SkyCycle (with Bridge) + Config.Sky (with Transitions and Bridge), or nil after one failed check
	local function sky()
		local SC = loadModule("SkyCycle")
		local Config = loadModule("Config")
		local cfg = Config and Config.Sky
		if not T.check(SC and type(SC.Bridge) == "function" and type(SC.Preset) == "function", "SkyCycle.Bridge exists", "src/shared/SkyCycle.lua has no Bridge") then
			return nil
		end
		local tr = cfg and cfg.Transitions
		if not T.check(type(tr) == "table" and type(tr.Cycle) == "table" and type(tr.Raid) == "table" and type(cfg.Bridge) == "table", "Config.Sky.Transitions.Cycle / Raid and Config.Sky.Bridge exist") then
			return nil
		end
		return SC, cfg, tr
	end

	local function faces(theme)
		return { SkyboxBk = "bk:" .. tostring(theme), SkyboxDn = "dn:" .. tostring(theme), SkyboxFt = "ft:" .. tostring(theme), SkyboxLf = "lf:" .. tostring(theme), SkyboxRt = "rt:" .. tostring(theme), SkyboxUp = "up:" .. tostring(theme) }
	end

	-- the start (loop seconds) of each phase and of its blend window
	local function windows(cfg)
		local c = cfg.Cycle
		local out, start = {}, 0
		for i, phase in ipairs(c.Order) do
			local len = c.Seconds[phase]
			out[#out + 1] = { Phase = phase, Next = c.Order[i % #c.Order + 1], From = start + len - c.Blend, To = start + len }
			start = start + len
		end
		return out
	end

	S.skycycle_bridge_shape = guarded("skycycle_bridge_shape", function()
		local SC, cfg, tr = sky()
		if not SC then
			return
		end
		for _, half in ipairs({ tr.Cycle.BridgeHalf, tr.Raid.BridgeHalf, 0.2 }) do
			local label = fmt("half %s", tostring(half))
			T.check(type(half) == "number" and half > 0 and half <= 0.5, label .. ": a half width in (0, 0.5]")
			T.near(SC.Bridge(0.5, half), 1, 1e-9, label .. ": k = 1 at blend 0.5")
			local shape = T.tally(label .. ": k in [0, 1], symmetric, 0 outside the window, rising toward 0.5")
			local last = -1
			for i = 0, 200 do
				local b = i / 200
				local k = SC.Bridge(b, half)
				shape:case(type(k) == "number" and k >= 0 and k <= 1, fmt("b %.3f k %s", b, tostring(k)))
				shape:case(abs(k - SC.Bridge(1 - b, half)) < 1e-9, fmt("b %.3f k %.6f vs mirror %.6f", b, k, SC.Bridge(1 - b, half)))
				if abs(b - 0.5) >= half then
					shape:case(k == 0, fmt("b %.3f outside: k %.6f", b, k))
				end
				if b <= 0.5 then
					shape:case(k >= last, fmt("b %.3f k %.6f after %.6f", b, k, last))
					last = k
				end
			end
			shape:report()
		end
		local nan = 0 / 0
		local junk = T.tally("junk blends / halves give k = 0 (no error)")
		for _, c in ipairs({ { nan, 0.2 }, { "x", 0.2 }, { nil, 0.2 }, { 0.5, 0 }, { 0.5, -1 }, { 0.5, nan }, { 0.5, "w" }, { math.huge, 0.2 } }) do
			local ok, k = pcall(SC.Bridge, c[1], c[2])
			junk:case(ok and k == 0, fmt("Bridge(%s, %s) = %s", tostring(c[1]), tostring(c[2]), tostring(k)))
		end
		junk:report()
		-- the cycle's bridge spans about 30 s of each 75 s phase blend (BUILD_PLAN decision 6: start at 30 s, tune in Studio)
		for _, w in ipairs(windows(cfg)) do
			local on = 0
			for t = w.From, w.To - 0.05, 0.05 do
				if SC.Bridge(SC.At(t, 0, 1, 0).Blend, tr.Cycle.BridgeHalf) > 0 then
					on = on + 0.05
				end
			end
			T.check(on >= 26 and on <= 34, fmt("%s -> %s: the bridge runs %.1f s of the %d s blend (about 30)", w.Phase, w.Next, on, cfg.Cycle.Blend))
		end
	end)

	S.skycycle_bridge_peak_swaps_faces = guarded("skycycle_bridge_peak_swaps_faces", function()
		local SC, cfg, tr = sky()
		if not SC then
			return
		end
		-- samples = { { k, theme, preset } ... } in order: what may only change at the peak
		local function swapsAtPeak(label, samples, wantSwaps)
			local tally = T.tally(label .. ": theme / faces / StarCount / clock jump change only at the bridge peak (k >= 0.98 on both sides)")
			local themes = 0
			for i = 2, #samples do
				local a, b = samples[i - 1], samples[i]
				local pa, pb = a.preset, b.preset
				local changed = {}
				if a.theme ~= b.theme then
					changed[#changed + 1] = "theme"
					themes = themes + 1
				end
				if pa.Sky.SkyboxBk ~= pb.Sky.SkyboxBk then
					changed[#changed + 1] = "faces"
				end
				if pa.Sky.StarCount ~= pb.Sky.StarCount then
					changed[#changed + 1] = "StarCount"
				end
				if b.clockJump and abs(SC.ClockDelta(pa.Lighting.ClockTime, pb.Lighting.ClockTime)) > cfg.ClockJump then
					changed[#changed + 1] = "clock"
				end
				if #changed > 0 then
					tally:case(a.k >= 0.98 and b.k >= 0.98, fmt("%s changed at k %.3f -> %.3f", table.concat(changed, "+"), a.k, b.k))
				end
			end
			tally:report()
			T.check(themes == wantSwaps, fmt("%s: the skybox swaps %d time(s)", label, wantSwaps), fmt("%d swaps", themes))
		end
		-- the peak is thick air: Density and Cover well above both looks (the bridge is applied, not only computed)
		local function thickAtPeak(label, peak, lookA, lookB)
			local dA, dB = lookA.Atmosphere.Density, lookB.Atmosphere.Density
			local cA, cB = lookA.Clouds.Cover, lookB.Clouds.Cover
			local d, c = peak.Atmosphere.Density, peak.Clouds.Cover
			T.check(d >= max(dA, dB) + 0.2 and c >= min(1, max(cA, cB) + 0.05) - 1e-9, fmt("%s: the peak is thick air (Density %.2f over %.2f / %.2f, Cover %.2f over %.2f / %.2f)", label, d, dA, dB, c, cA, cB))
		end
		-- every phase change, sampled every 0.05 s across its blend window
		local half = tr.Cycle.BridgeHalf
		for _, w in ipairs(windows(cfg)) do
			local samples, peak, best = {}, nil, -1
			for t = w.From - 1, w.To + 1, 0.05 do
				local at = SC.At(t, 0, 1, 0)
				local p, theme = SC.Preset(at, nil, 0, faces)
				local k = at.Phase == w.Phase and SC.Bridge(at.Blend, half) or 0
				samples[#samples + 1] = { k = k, theme = theme, preset = p }
				if k > best then
					best, peak = k, p
				end
			end
			local label = w.Phase .. " -> " .. w.Next
			local swaps = cfg.Themes[w.Phase] ~= cfg.Themes[w.Next] and 1 or 0
			swapsAtPeak(label, samples, swaps)
			if swaps == 1 then
				thickAtPeak(label, peak, cfg.Looks[w.Phase], cfg.Looks[w.Next])
			end
		end
		-- every raid sky blending in (and out: the same blend backwards) in the Day and at Night
		local rhalf = tr.Raid.BridgeHalf
		for bossId in pairs(cfg.RaidThemes) do
			for _, t in ipairs({ 300, 1100 }) do
				local at = SC.At(t, 0, 1, 0)
				local samples = {}
				for i = 0, 200 do
					local b = i / 200
					local p, theme = SC.Preset(at, bossId, b, faces)
					samples[#samples + 1] = { k = SC.Bridge(b, rhalf), theme = theme, preset = p, clockJump = true }
				end
				local label = fmt("%s at t %d", bossId, t)
				swapsAtPeak(label, samples, 1)
				thickAtPeak(label, SC.Preset(at, bossId, 0.5, faces), cfg.Looks[at.Phase], cfg.Looks[bossId])
			end
		end
		-- raid to raid (back-to-back: storm up, lava spawns)
		local at = SC.At(300, 0, 1, 0)
		local samples = {}
		for i = 0, 200 do
			local b = i / 200
			local p, theme = SC.Preset(at, "lava_golem", b, faces, "storm_titan", 1)
			samples[#samples + 1] = { k = SC.Bridge(b, rhalf), theme = theme, preset = p, clockJump = true }
		end
		swapsAtPeak("storm -> lava", samples, 1)
		thickAtPeak("storm -> lava", SC.Preset(at, "lava_golem", 0.5, faces, "storm_titan", 1), cfg.Looks.storm_titan, cfg.Looks.lava_golem)
		-- off the peak window the bridge adds nothing: blend 0 / 1 are exactly the looks (no haze left over)
		local plain = SC.Preset(at, "storm_titan", 1, faces)
		T.near(plain.Atmosphere.Density, cfg.Looks.storm_titan.Atmosphere.Density, 1e-9, "a raid at blend 1: the raid look's Density (no bridge left)")
		T.near(plain.Clouds.Cover, cfg.Looks.storm_titan.Clouds.Cover, 1e-9, "a raid at blend 1: the raid look's Cover")
	end)

	S.skycycle_bridge_keeps_floor = guarded("skycycle_bridge_keeps_floor", function()
		local SC, cfg, tr = sky()
		if not SC then
			return
		end
		T.check(cfg.Floor.Brightness == 1.0 and cfg.Floor.OutdoorAmbientMin == 70, "the floor of sky_floor: Brightness 1.0, OutdoorAmbient 70")
		T.check(tr.Cycle.Density <= 0.7 and tr.Raid.Density <= 0.7, fmt("the bridge peaks: Cycle Density %s, Raid Density %s (<= 0.7)", tostring(tr.Cycle.Density), tostring(tr.Raid.Density)))
		local floorB, floorA = cfg.Floor.Brightness, cfg.Floor.OutdoorAmbientMin / 255
		local tally = T.tally("every bridge step: Brightness >= 1, OutdoorAmbient >= 70, Density <= 0.7, Cover <= 1, Haze <= 10")
		local function readable(p, label)
			local L, atm, cl = p.Lighting or {}, p.Atmosphere or {}, p.Clouds or {}
			local oa = L.OutdoorAmbient
			tally:case(type(L.Brightness) == "number" and L.Brightness >= floorB - 1e-9, label .. " Brightness " .. tostring(L.Brightness))
			tally:case(isColor(oa) and oa.R >= floorA - 1e-9 and oa.G >= floorA - 1e-9 and oa.B >= floorA - 1e-9, label .. " OutdoorAmbient " .. tostring(oa))
			tally:case(type(atm.Density) == "number" and atm.Density <= 0.7 + 1e-9, label .. " Density " .. tostring(atm.Density))
			tally:case(type(cl.Cover) == "number" and cl.Cover <= 1 + 1e-9, label .. " Cover " .. tostring(cl.Cover))
			tally:case(type(atm.Haze) == "number" and atm.Haze <= 10, label .. " Haze " .. tostring(atm.Haze))
		end
		for _, w in ipairs(windows(cfg)) do
			for t = w.From, w.To, 0.5 do
				readable(SC.Preset(SC.At(t, 0, 1, 0), nil, 0, faces), fmt("%s->%s t %.1f", w.Phase, w.Next, t))
			end
		end
		for bossId in pairs(cfg.RaidThemes) do
			for _, t in ipairs({ 300, 1100, 900 }) do
				local at = SC.At(t, 0, 1, 0)
				for i = 0, 50 do
					readable(SC.Preset(at, bossId, i / 50, faces), fmt("%s t %d blend %.2f", bossId, t, i / 50))
				end
			end
			for other in pairs(cfg.RaidThemes) do
				if other ~= bossId then
					for i = 0, 20 do
						readable(SC.Preset(SC.At(1100, 0, 1, 0), bossId, i / 20, faces, other, 1), fmt("%s -> %s blend %.2f", other, bossId, i / 20))
					end
				end
			end
		end
		-- a raid starting at a phase change's peak: the two bridges together still keep the cap
		for _, w in ipairs(windows(cfg)) do
			local at = SC.At((w.From + w.To) / 2, 0, 1, 0)
			for bossId in pairs(cfg.RaidThemes) do
				readable(SC.Preset(at, bossId, 0.5, faces), fmt("%s at the %s->%s peak", bossId, w.Phase, w.Next))
			end
		end
		tally:report()
	end)

	S.skycycle_bridge_same_for_all = guarded("skycycle_bridge_same_for_all", function()
		local SC, cfg, tr = sky()
		if not SC then
			return
		end
		local function same(a, b, path)
			if type(a) ~= type(b) or typeof(a) ~= typeof(b) then
				return false, path
			end
			if isColor(a) then
				return abs(a.R - b.R) < 1e-9 and abs(a.G - b.G) < 1e-9 and abs(a.B - b.B) < 1e-9, path
			end
			if type(a) == "number" then
				return abs(a - b) < 1e-9, path .. fmt(" %.9g vs %.9g", a, b)
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
						return false, path .. "." .. tostring(k)
					end
				end
				return true
			end
			return a == b, path
		end
		local epoch, speed, offset = 1730000000.5, 1, 0
		local peaks = {}
		for _, w in ipairs(windows(cfg)) do
			peaks[#peaks + 1] = { t = (w.From + w.To) / 2, w = w }
		end
		-- client A: running since the epoch, a Preset every 2 s (with a raid passing through); client B: joins at the peak
		local walkedTo, walked = 0, {}
		for i, pk in ipairs(peaks) do
			while walkedTo < pk.t do
				local ev = (walkedTo > 600 and walkedTo < 700) and "frost_wyrm" or nil
				SC.Preset(SC.At(epoch + walkedTo, epoch, speed, offset), ev, ev and 1 or 0, faces)
				walkedTo = walkedTo + 2
			end
			walked[i] = { SC.Preset(SC.At(epoch + pk.t, epoch, speed, offset), nil, 0, faces) }
			walked[i].raid = { SC.Preset(SC.At(epoch + pk.t, epoch, speed, offset), "storm_titan", 0.5, faces) }
		end
		for i, pk in ipairs(peaks) do
			local label = pk.w.Phase .. " -> " .. pk.w.Next
			local fresh, theme = SC.Preset(SC.At(epoch + pk.t, epoch, speed, offset), nil, 0, faces)
			local ok, why = same(walked[i][1], fresh, "preset")
			T.check(ok and walked[i][2] == theme, label .. " peak: a client that just joined = a long-running one", why)
			local look = math.max(cfg.Looks[pk.w.Phase].Atmosphere.Density, cfg.Looks[pk.w.Next].Atmosphere.Density)
			T.check(fresh.Atmosphere.Density > look + 0.2, fmt("%s peak: both see the bridge (Density %.2f over the looks' %.2f)", label, fresh.Atmosphere.Density, look))
			local rFresh = SC.Preset(SC.At(epoch + pk.t, epoch, speed, offset), "storm_titan", 0.5, faces)
			local okR, whyR = same(walked[i].raid[1], rFresh, "raid")
			T.check(okR, label .. " peak + a raid at its peak: the same for both", whyR)
		end
		local _ = tr
	end)

	return S
end

local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Workspace = game:GetService("Workspace")
	local Cfg = require(Mock.GetPath(ROOTS["shared"] .. "/Config"))
	local A = Cfg.Sky.Attr

	local function modules()
		local okL, LS = pcall(require, Mock.GetPath(ROOTS["client"] .. "/LightingStack"))
		local inst = Mock.GetPath(ROOTS["client"] .. "/Controllers/SkyController")
		local ok, SC = false, nil
		if inst then
			ok, SC = pcall(require, inst)
		end
		if not T.check(okL and type(LS) == "table" and ok and type(SC) == "table", "SkyController + LightingStack load", tostring(SC)) then
			return nil
		end
		return SC, LS
	end

	local function publish(pos)
		local now = Workspace:GetServerTimeNow()
		Workspace:SetAttribute(A.Epoch, now)
		Workspace:SetAttribute(A.Speed, 1)
		Workspace:SetAttribute(A.Offset, pos)
		Workspace:SetAttribute(A.Event, "")
		Workspace:SetAttribute(A.EventAt, now - 100)
		return now
	end

	-- the controller restarted on the boot clock afterwards, the base and the stack as they were (smoke_sky's withSky)
	local function withSky(name, fn)
		return guarded(name, function()
			local SC, LS = modules()
			if not SC then
				return
			end
			local before = #LS.Ids()
			local savedBase = { Brightness = LS.Value("Lighting", "Brightness", "Dungeon"), ClockTime = LS.Value("Lighting", "ClockTime", "Dungeon") }
			local realSetBase = LS.SetBase
			local ok, err = pcall(fn, SC, LS)
			LS.SetBase = realSetBase
			T.check(ok, name .. " ran without errors", tostring(err))
			pcall(SC.SetLocalEvent, nil)
			SC.Stop()
			for _, key in pairs(A) do
				Workspace:SetAttribute(key, nil)
			end
			KC.advance(2.2)
			LS.SetBase({ Lighting = savedBase }, 0)
			SC.Start()
			KC.advance(0.1)
			T.eq(#LS.Ids(), before, name .. ": the stack is as it was")
		end)
	end

	-- every SetBase from here on: { t = server time, s = tween seconds }
	local function spy(LS)
		local calls = {}
		local real = LS.SetBase
		LS.SetBase = function(preset, seconds, instant)
			calls[#calls + 1] = { t = Workspace:GetServerTimeNow(), s = seconds }
			return real(preset, seconds, instant)
		end
		return calls
	end

	S.sky_raid_in8_out6 = withSky("sky_raid_in8_out6", function(SC)
		local R = Cfg.Sky.Transitions and Cfg.Sky.Transitions.Raid
		T.check(type(R) == "table" and R.In == 8 and R.Out == 6, "Config.Sky.Transitions.Raid: In 8, Out 6", R and fmt("%s / %s", tostring(R.In), tostring(R.Out)) or "missing")
		T.check(Cfg.Sky.Cycle.EventBlend == nil, "Config.Sky.Cycle.EventBlend is gone (Raid.In / Out replace it)", tostring(Cfg.Sky.Cycle.EventBlend))
		SC.Stop() -- the refreshes by hand at given server times
		local t0 = publish(300) -- Day
		Workspace:SetAttribute(A.Event, "storm_titan")
		Workspace:SetAttribute(A.EventAt, t0)
		local function at(t)
			SC.Refresh(t)
			return SC.State()
		end
		local st = at(t0)
		T.check(st.Event == "storm_titan" and st.EventBlend < 0.01, "raid start: blend 0", tostring(st.EventBlend))
		st = at(t0 + 3.9)
		T.check(abs(st.EventBlend - 3.9 / 8) < 1e-6 and st.Look == "Day", "3.9 s in: blend 3.9 / 8, still the Day look", fmt("%.3f %s", st.EventBlend, tostring(st.Look)))
		st = at(t0 + 4)
		T.check(abs(st.EventBlend - 0.5) < 1e-6 and st.Look == "storm_titan" and st.Theme == Cfg.Sky.RaidThemes.storm_titan, "4 s in: the midpoint, the storm sky swaps in", fmt("%.3f %s", st.EventBlend, tostring(st.Look)))
		st = at(t0 + 7.9)
		T.check(st.EventBlend < 1 and st.EventBlend > 0.95, "7.9 s in: still blending", tostring(st.EventBlend))
		st = at(t0 + 8)
		T.check(st.EventBlend == 1, "8 s in: the full raid sky", tostring(st.EventBlend))
		local t1 = t0 + 20
		Workspace:SetAttribute(A.Event, "")
		Workspace:SetAttribute(A.EventAt, t1)
		st = at(t1)
		T.check(st.Event == "storm_titan" and st.EventBlend == 1, "raid end: the blend back starts from 1", tostring(st.EventBlend))
		st = at(t1 + 2.9)
		T.check(st.Event == "storm_titan" and st.Look == "storm_titan" and abs(st.EventBlend - (1 - 2.9 / 6)) < 1e-6, "2.9 s after: 1 - 2.9 / 6, the storm look still", fmt("%.3f %s", st.EventBlend, tostring(st.Look)))
		st = at(t1 + 3)
		T.check(abs(st.EventBlend - 0.5) < 1e-6 and st.Look == "storm_titan", "3 s after: the midpoint (blend 0.5 is still the raid's, as on the way in)", fmt("%.3f %s", st.EventBlend, tostring(st.Look)))
		st = at(t1 + 3.1)
		T.check(st.EventBlend < 0.5 and st.Look == "Day", "just past the midpoint: the Day sky swaps back", fmt("%.3f %s", st.EventBlend, tostring(st.Look)))
		st = at(t1 + 5.9)
		T.check(st.Event == "storm_titan" and st.EventBlend > 0 and st.EventBlend < 0.05, "5.9 s after: nearly out", tostring(st.EventBlend))
		st = at(t1 + 6)
		T.check(st.Event == nil and st.EventBlend == 0 and st.Look == "Day", "6 s after: the plain cycle", tostring(st.Event))
	end)

	S.skycontroller_raid_cadence = withSky("skycontroller_raid_cadence", function(SC, LS)
		local R = Cfg.Sky.Transitions and Cfg.Sky.Transitions.Raid or { In = 8, Out = 6, Step = 0.5 }
		local C = Cfg.Sky.Cycle
		T.check(R.Step == 0.5 and C.Refresh == 2 and C.Tween == 2, "Raid.Step 0.5; Cycle Refresh / Tween 2", tostring(R.Step))
		SC.Stop()
		publish(300) -- Day, nowhere near a phase change
		SC.Start()
		KC.advance(0.05)
		local calls = spy(LS)
		KC.advance(6.1)
		local evAt = Workspace:GetServerTimeNow()
		Workspace:SetAttribute(A.Event, "storm_titan")
		Workspace:SetAttribute(A.EventAt, evAt)
		for _ = 1, 64 do
			KC.advance(0.25) -- 16 s: the 8 s in, then the full raid sky
		end
		local endAt = Workspace:GetServerTimeNow()
		Workspace:SetAttribute(A.Event, "")
		Workspace:SetAttribute(A.EventAt, endAt)
		for _ = 1, 56 do
			KC.advance(0.25) -- 14 s: the 6 s out, then the plain cycle
		end
		local function between(lo, hi)
			local out = {}
			for _, c in ipairs(calls) do
				if c.t >= lo - 1e-6 and c.t < hi - 1e-6 then
					out[#out + 1] = c
				end
			end
			return out
		end
		local function judge(label, list, step, minCount)
			local bad, maxGap = nil, 0
			for i, c in ipairs(list) do
				if c.s ~= step then
					bad = bad or fmt("#%d tween %s", i, tostring(c.s))
				end
				if i > 1 then
					maxGap = max(maxGap, c.t - list[i - 1].t)
				end
			end
			T.check(#list >= minCount and bad == nil and maxGap <= step + 0.05, fmt("%s: %d refreshes, every %.1f s with %.1f s tweens", label, #list, step, step), fmt("%d calls, %s, max gap %.2f", #list, tostring(bad), maxGap))
		end
		judge("before the raid", between(evAt - 6.1, evAt), C.Refresh, 3)
		judge("the raid blending in", between(evAt, evAt + R.In - 0.5), R.Step, math.floor((R.In - 0.5) / R.Step) - 1)
		judge("the full raid sky", between(evAt + R.In + 0.5, endAt), C.Refresh, 3)
		judge("the raid blending out", between(endAt, endAt + R.Out - 0.5), R.Step, math.floor((R.Out - 0.5) / R.Step) - 1)
		judge("the plain cycle again", between(endAt + R.Out + 0.5, endAt + 14), C.Refresh, 3)
	end)

	S.skycontroller_dev_speed_bridge = withSky("skycontroller_dev_speed_bridge", function(SC, LS)
		local SCy = require(Mock.GetPath(ROOTS["shared"] .. "/SkyCycle"))
		local R, C = Cfg.Sky.Transitions.Raid, Cfg.Sky.Cycle
		local half = Cfg.Sky.Transitions.Cycle.BridgeHalf
		-- /sky speed 10, 35 loop s before the Day -> Sunset blend (Day ends at loop 480, its blend from 405; on 2 s steps
		-- this phase samples loop 430 (k ~0.06) and then 450 (past the swap): the faces would swap in clear air)
		SC.Stop()
		local epoch = publish(370)
		Workspace:SetAttribute(A.Speed, 10)
		SC.Start()
		KC.advance(0.05)
		local calls = spy(LS)
		for _ = 1, 48 do
			KC.advance(0.25) -- 12 s = 120 loop s: through the whole 75 s blend
		end
		local inBlend, bad, maxGap, prev, swapK = 0, nil, 0, nil, nil
		for i, c in ipairs(calls) do
			local at = SCy.At(c.t, epoch, 10, 370)
			if at.Phase == "Day" and at.Blend > 0 then
				inBlend = inBlend + 1
				if c.s ~= R.Step then
					bad = bad or fmt("#%d tween %s at blend %.2f", i, tostring(c.s), at.Blend)
				end
				if prev and prev.Phase == "Day" and prev.Blend > 0 then
					maxGap = max(maxGap, c.t - calls[i - 1].t)
				end
				if swapK == nil and at.Blend >= 0.5 then
					-- the faces swap at this refresh; the air on screen is still the previous refresh's target
					swapK = prev and SCy.Bridge(prev.Phase == "Day" and prev.Blend or 0, half) or 0
				end
			end
			prev = at
		end
		T.check(inBlend >= 10 and bad == nil and maxGap <= R.Step + 0.05, fmt("speed 10: every refresh inside the phase blend runs every %.1f s with %.1f s tweens", R.Step, R.Step), fmt("%d in the blend, %s, max gap %.2f", inBlend, tostring(bad), maxGap))
		T.check(swapK ~= nil and swapK >= 0.6, "speed 10: the faces swap under thick air (the refresh before the swap is >= 0.6 into the bridge)", tostring(swapK))
		-- speed 1 (play): the phase blend keeps the 2 s cadence
		SC.Stop()
		publish(430)
		SC.Start()
		KC.advance(0.05)
		local slow = spy(LS)
		for _ = 1, 33 do
			KC.advance(0.25)
		end
		local wrong, gap = nil, 0
		for i, c in ipairs(slow) do
			if c.s ~= C.Tween then
				wrong = wrong or fmt("#%d tween %s", i, tostring(c.s))
			end
			if i > 1 then
				gap = max(gap, c.t - slow[i - 1].t)
			end
		end
		T.check(#slow >= 3 and wrong == nil and gap <= C.Refresh + 0.05, "speed 1: the phase blend refreshes every 2 s with 2 s tweens (unchanged)", fmt("%d calls, %s, max gap %.2f", #slow, tostring(wrong), gap))
	end)

	S.skycontroller_localevent_refreshes_now = withSky("skycontroller_localevent_refreshes_now", function(SC, LS)
		SC.Stop()
		publish(300)
		SC.Start()
		KC.advance(0.3)
		local calls = spy(LS)
		T.check(SC.SetLocalEvent("storm_titan") == true, "SetLocalEvent(storm_titan) is taken")
		KC.advance(0.05)
		local st = SC.State()
		T.check(#calls >= 1 and st.Local == "storm_titan" and st.Event == "storm_titan", "the pocket fight's sky starts at once (a refresh within 0.05 s, not on the next 2 s tick)", fmt("%d calls, Event %s", #calls, tostring(st.Event)))
		T.check(calls[1] ~= nil and calls[1].s == Cfg.Sky.Transitions.Raid.Step, "that refresh already runs on the raid cadence (a 0.5 s tween)", calls[1] and tostring(calls[1].s) or "no call")
		KC.advance(9) -- fully on
		local n = #calls
		SC.SetLocalEvent(nil)
		KC.advance(0.05)
		st = SC.State()
		T.check(#calls > n and st.Local == nil and st.Event == "storm_titan" and st.EventBlend > 0.9, "taking it off refreshes at once too (the blend out starts now)", fmt("%d new calls, blend %s", #calls - n, tostring(st.EventBlend)))
		-- a stopped controller only stores the request
		SC.Stop()
		local m = #calls
		SC.SetLocalEvent("frost_wyrm")
		KC.advance(0.05)
		T.check(#calls == m, "a stopped controller does not refresh on SetLocalEvent", fmt("%d calls", #calls - m))
		SC.SetLocalEvent(nil)
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
