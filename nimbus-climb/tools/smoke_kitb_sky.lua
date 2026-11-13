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
--   S2 (preload, painted boot sky, stars; sky audit F4, F5, F12):
--   sky_painted_looks_have_no_engine_stars (server world, pure) every phase and raid look with a painted skybox has
--                             StarCount 0 (the stars are painted; no engine field popping on at the mid-blend)
--   lightingservice_boot_uses_painted_day (server world, booted) empty (or half-pasted) Config.Sky.Faces boots the
--                             painted skybox of the loop's first phase (S2 review; the Day's when that one is not
--                             uploaded), StarCount 0, CelestialBodiesShown false, Glare 0, its own SunRays at 0 ("Painted"):
--                             faces / stars / sun / glare / rays = SkyCycle.Preset at that phase; the stock sky only when
--                             neither theme is uploaded; six owner faces win
--   skytransition_preloads_next_theme (client) SkyTransition.Preload(theme) = one ContentProvider:PreloadAsync with exactly
--                             its six face ids (nothing for a missing theme); SkyController preloads the next theme once
--                             per blend window, at its first refresh inside it
--   skytransition_preloads_raids_after_menu (client) the four raid skies preload Transitions.Preload.RaidDelay s after the
--                             menu's PLAY fires (UiGate.Played), one at a time in one thread (S2 review), once per start;
--                             a controller started after PLAY: RaidDelay s after its start; stopped in the delay: nothing
--   S3 (small transitions; sky audit F9, F10):
--   hatchfx_blur_tweens_out   (client) HatchFx.Dim(false, s): NimbusHatchBlur tweens Size -> 0 over s (Quad In) and is
--                             destroyed when that completes (SkyTransition.BlurOut; default Transitions.Screen.Out); on
--                             again mid-fade keeps the same blur (the fade cancelled, never destroyed later)
--   dungeon_light_dim_duration (client) the run's Dungeon light pushes over Transitions.Zone.In (1.5 s) and, at an End
--                             with no fade on screen, pops over Zone.Out (2 s)
--   dungeon_late_mood_slow_push (client) a tier mood read after the start (the pocket streamed in) is re-pushed once,
--                             over Zone.Late (2.5 s)
--   dungeon_end_fade_tweens_out (client) End under the black fade: the light pops at 0 s (unseen) and the frame tweens out
--                             over Transitions.Screen.Lift (0.3 s), then the overlay is off
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

	-- S2 (sky audit F5): the painted skies have their stars painted in; 3000 engine pinpoints on top of them read as a
	-- second star field that pops on at the mid-blend
	S.sky_painted_looks_have_no_engine_stars = guarded("sky_painted_looks_have_no_engine_stars", function()
		local Config = loadModule("Config")
		local cfg = Config and Config.Sky
		if not T.check(type(cfg) == "table" and type(cfg.Looks) == "table", "Config.Sky.Looks exists") then
			return
		end
		local tally = T.tally("every look with a painted skybox (Themes / RaidThemes) has StarCount 0")
		local n = 0
		for _, map in ipairs({ cfg.Themes, cfg.RaidThemes }) do
			for id, theme in pairs(map) do
				local look = cfg.Looks[id]
				local stars = look and look.Sky and look.Sky.StarCount
				tally:case(stars == 0, fmt("%s (%s): StarCount %s", id, tostring(theme), tostring(stars)))
				n = n + 1
			end
		end
		tally:report()
		T.check(n == 8, fmt("4 phases + 4 raids checked (%d)", n))
	end)

	-- S2 (sky audit F4, F12): with no owner faces in Config.Sky.Faces the boot sky is the painted Day skybox (never the
	-- stock Roblox sky), with no engine sun / stars and no glare, so the loading screen's preload of Lighting.Sky fetches
	-- the faces the player sees first. The stock sky stays only as the last resort (the Day theme not uploaded)
	S.lightingservice_boot_uses_painted_day = guarded("lightingservice_boot_uses_painted_day", function()
		local LS = K.M["server/Services/LightingService"]
		local Config = K.config()
		local SkyFaces = K.M["shared/SkyFaces"] or loadModule("SkyFaces")
		local SkyCycle = K.M["shared/SkyCycle"] or loadModule("SkyCycle")
		local Lighting = game:GetService("Lighting")
		if not T.check(type(LS) == "table" and type(LS.Init) == "function" and type(SkyFaces) == "table" and type(SkyCycle) == "table", "LightingService + SkyFaces + SkyCycle are loaded") then
			return
		end
		-- S2 review: the boot sky is the theme of the loop's position 0 (SkyService boots SkyOffset 0: a fresh server's first
		-- phase), so a fresh Play's first client apply keeps the faces the loading screen preloaded
		local first = SkyCycle.At(0, 0, 1, 0).Phase
		local savedFaces, savedDay, savedFirst = {}, Config.Sky.Themes.Day, Config.Sky.Themes[first]
		for k, v in pairs(Config.Sky.Faces) do
			savedFaces[k] = v
		end
		local function setFaces(faces)
			for _, k in ipairs({ "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }) do
				Config.Sky.Faces[k] = faces[k] or ""
			end
		end
		-- theme = the boot theme expected; phase = the phase whose SkyCycle.Preset (with faces) the sky must equal
		local function painted(label, theme, phase)
			local want = SkyFaces.For(theme)
			local s = Lighting:FindFirstChildOfClass("Sky")
			local atm = Lighting:FindFirstChildOfClass("Atmosphere")
			local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
			if not T.check(want ~= nil and s ~= nil and atm ~= nil and rays ~= nil, label .. ": the boot theme's faces exist, a Sky, an Atmosphere and SunRays") then
				return
			end
			local faces = T.tally(label .. ": the six Skybox faces = SkyFaces.For(" .. tostring(theme) .. ")")
			for slot, id in pairs(want) do
				faces:case(s[slot] == id and id:sub(1, 13) == "rbxassetid://", fmt("%s %s vs %s", slot, tostring(s[slot]), id))
			end
			faces:report()
			T.check(s.StarCount == 0 and s.CelestialBodiesShown == false, label .. ": no engine stars, no engine sun / moon", fmt("StarCount %s, CelestialBodiesShown %s", tostring(s.StarCount), tostring(s.CelestialBodiesShown)))
			T.check(atm.Glare == 0, label .. ": Atmosphere Glare 0", tostring(atm.Glare))
			-- S2 review: what SkyController's first apply at that phase writes (SkyCycle.Preset with faces): the sun rays,
			-- glare, engine sun and stars do not move when the living sky takes over
			if phase then
				local at = { Phase = phase, Next = phase, T = 0, Blend = 0 }
				local p = SkyCycle.Preset(at, nil, 0, SkyFaces.For)
				T.check(rays.Intensity == p.SunRays.Intensity, fmt("%s: SunRays.Intensity %s = SkyCycle.Preset at %s (%s)", label, tostring(rays.Intensity), phase, tostring(p.SunRays.Intensity)))
				T.check(atm.Glare == p.Atmosphere.Glare and s.CelestialBodiesShown == p.Sky.CelestialBodiesShown and s.StarCount == p.Sky.StarCount,
					fmt("%s: Glare / CelestialBodiesShown / StarCount = SkyCycle.Preset at %s", label, phase), fmt("%s / %s / %s", tostring(p.Atmosphere.Glare), tostring(p.Sky.CelestialBodiesShown), tostring(p.Sky.StarCount)))
				T.check(s.SkyboxBk == p.Sky.SkyboxBk and s.SkyboxUp == p.Sky.SkyboxUp, fmt("%s: the faces = SkyCycle.Preset at %s (no swap at the first apply)", label, phase), tostring(p.Sky.SkyboxBk))
			end
		end
		local ok, err = pcall(function()
			setFaces({})
			K.resetCursors() -- only this scenario's warnings below (not the boot's)
			T.eq(LS.Init(), "Painted", "empty Config.Sky.Faces -> Init returns Painted")
			T.eq(LS.Current, "Painted", "LightingService.Current = Painted")
			T.check(type(LS.Look.Painted) == "table", "LightingService.Look.Painted exists")
			T.check(type(LS.Look.Painted.SunRays) == "table" and LS.Look.Painted.SunRays ~= LS.Look.Custom.SunRays and LS.Look.Painted.SunRays.Intensity == 0 and LS.Look.Custom.SunRays == LS.Look.Fallback.SunRays and LS.Look.Custom.SunRays.Intensity > 0,
				"Look.Painted has its own SunRays at Intensity 0; Custom and Fallback keep the shared faint rays")
			T.check(first == Config.Sky.Cycle.Order[1] and Config.Sky.Themes[first] ~= Config.Sky.Themes.Day, fmt("the loop starts at %s, whose sky (%s) is not the Day's (the case S2 got wrong)", tostring(first), tostring(Config.Sky.Themes[first])))
			painted("empty faces", Config.Sky.Themes[first], first)
			K.flushWarnings("lightingservice_boot_uses_painted_day: empty faces warn nothing")
			-- a half-pasted Config.Sky.Faces warns (names the missing face) and still boots painted, never the stock sky
			setFaces({ Bk = "rbxassetid://101", Dn = "rbxassetid://102", Ft = "rbxassetid://103", Lf = "rbxassetid://104", Rt = "rbxassetid://105" })
			T.eq(LS.Init(), "Painted", "one owner face missing (Up) -> Painted")
			painted("one owner face missing", Config.Sky.Themes[first], first)
			K.flushWarnings("lightingservice_boot_uses_painted_day", { "[LightingService]" })
			-- the first phase's theme not uploaded: the painted Day sky
			setFaces({})
			Config.Sky.Themes[first] = "kitb_not_uploaded"
			T.eq(LS.Init(), "Painted", "the first phase's theme not uploaded -> still Painted")
			painted("first theme missing", Config.Sky.Themes.Day, "Day")
			-- neither uploaded: the stock sky is the last resort
			Config.Sky.Themes.Day = "kitb_not_uploaded"
			T.eq(LS.Init(), "Fallback", "no first-phase or Day theme faces either -> Fallback")
			local s = Lighting:FindFirstChildOfClass("Sky")
			T.check(s ~= nil and s.SkyboxBk == "" and s.SkyboxUp == "", "Fallback: the stock sky (faces cleared)")
			local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
			T.check(rays ~= nil and rays.Intensity == LS.Look.Fallback.SunRays.Intensity, "Fallback: its faint sun rays come back", rays and tostring(rays.Intensity))
			Config.Sky.Themes.Day = savedDay
			Config.Sky.Themes[first] = savedFirst
			-- six owner faces still win
			setFaces({ Bk = "rbxassetid://101", Dn = "rbxassetid://102", Ft = "rbxassetid://103", Lf = "rbxassetid://104", Rt = "rbxassetid://105", Up = "rbxassetid://106" })
			T.eq(LS.Init(), "Custom", "six owner faces -> Custom")
		end)
		T.check(ok, "lightingservice_boot_uses_painted_day ran without errors", tostring(err))
		Config.Sky.Themes.Day = savedDay
		Config.Sky.Themes[first] = savedFirst
		for k in pairs(Config.Sky.Faces) do
			Config.Sky.Faces[k] = savedFaces[k]
		end
		LS.Init()
		K.flushWarnings("lightingservice_boot_uses_painted_day restore", { "[LightingService]" })
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
			Mock.PreloadHook = nil
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

	-- S2 (sky audit F4): every ContentProvider:PreloadAsync list from here on (Mock.PreloadHook; withSky drops it)
	local function preloads()
		local lists = {}
		Mock.PreloadHook = function(list)
			local copy = {}
			for i, v in ipairs(list) do
				copy[i] = v
			end
			lists[#lists + 1] = copy
		end
		return lists
	end

	-- the list is exactly the six face ids of SkyFaces.For(theme), as strings
	local function isTheme(list, theme)
		local SkyFaces = require(Mock.GetPath(ROOTS["shared"] .. "/SkyFaces"))
		local want = SkyFaces.For(theme)
		if not want or #list ~= 6 then
			return false
		end
		local left = {}
		for _, id in pairs(want) do
			left[id] = true
		end
		for _, v in ipairs(list) do
			if type(v) ~= "string" or not left[v] then
				return false
			end
			left[v] = nil
		end
		return next(left) == nil
	end

	local function describe(lists)
		local out = {}
		for i, l in ipairs(lists) do
			out[i] = fmt("#%d (%d ids: %s)", i, #l, tostring(l[1]))
		end
		return #out > 0 and table.concat(out, ", ") or "none"
	end

	S.skytransition_preloads_next_theme = withSky("skytransition_preloads_next_theme", function(SC)
		local inst = Mock.GetPath(ROOTS["client"] .. "/SkyTransition")
		local ok, ST = false, nil
		if inst then
			ok, ST = pcall(require, inst)
		end
		if not T.check(ok and type(ST) == "table" and type(ST.Preload) == "function", "client/SkyTransition.Preload exists", tostring(ST)) then
			return
		end
		local Themes = Cfg.Sky.Themes
		-- the module alone: one PreloadAsync with the six face ids; a theme that is not uploaded preloads nothing
		local lists = preloads()
		ST.Preload(Themes.Sunset)
		KC.advance(0.05)
		T.check(#lists == 1 and isTheme(lists[1], Themes.Sunset), "Preload(theme): one PreloadAsync with exactly its six face ids", describe(lists))
		lists = preloads()
		ST.Preload("kitb_not_uploaded")
		ST.Preload(nil)
		KC.advance(0.05)
		T.check(#lists == 0, "Preload of a missing / junk theme: nothing", describe(lists))
		-- the controller: the next theme once, when its blend window opens (Day ends at loop 480, its window from 405)
		SC.Stop()
		local epoch = publish(300)
		lists = preloads()
		local opened = nil
		for t = 0, 100, 2 do
			SC.Refresh(epoch + t) -- loop 300 .. 400: no window yet
		end
		KC.advance(0.05)
		T.check(#lists == 0, "no preload before the Day -> Sunset window opens", describe(lists))
		for t = 102, 200, 2 do
			SC.Refresh(epoch + t) -- loop 402 .. 500: the window (405-480) and on into the Sunset
			KC.advance(0.01)
			if opened == nil and #lists > 0 then
				opened = 300 + t
			end
		end
		T.check(#lists == 1 and isTheme(lists[1], Themes.Sunset), "Day -> Sunset: one preload of the Sunset theme's six faces in the window", describe(lists))
		T.check(opened ~= nil and opened >= 405 and opened <= 407, "...at the first refresh inside the window (loop 405-407), 37 s before the swap", tostring(opened))
		-- the next window: once again, the Night theme
		lists = preloads()
		for pos = 940, 1030, 2 do
			SC.Refresh(epoch + pos - 300)
		end
		KC.advance(0.05)
		T.check(#lists == 1 and isTheme(lists[1], Themes.Night), "Sunset -> Night: one preload of the Night theme", describe(lists))
	end)

	S.skytransition_preloads_raids_after_menu = withSky("skytransition_preloads_raids_after_menu", function(SC)
		local Util = require(Mock.GetPath(ROOTS["shared"] .. "/Util"))
		local St = SC._St
		local played = false
		local gate = { Played = Util.Signal() }
		function gate.HasPlayed()
			return played
		end
		local function raidLists(lists)
			local seen, n = {}, 0
			for _, l in ipairs(lists) do
				for bossId, theme in pairs(Cfg.Sky.RaidThemes) do
					if isTheme(l, theme) then
						seen[bossId] = true
						n = n + 1
					end
				end
			end
			local all = true
			for bossId in pairs(Cfg.Sky.RaidThemes) do
				all = all and seen[bossId] == true
			end
			return n, all
		end
		-- S2 review: one theme at a time in one thread (each PreloadAsync here takes 1 s), RaidDelay s after PLAY so the
		-- lobby's own assets load first
		local delay = Cfg.Sky.Transitions.Preload and Cfg.Sky.Transitions.Preload.RaidDelay
		local function slowPreloads()
			local lists = {}
			lists.threads = {}
			Mock.PreloadHook = function(list)
				lists[#lists + 1] = list
				lists.threads[coroutine.running()] = true
				task.wait(1)
			end
			return lists
		end
		local function threads(lists)
			local n = 0
			for _ in pairs(lists.threads) do
				n = n + 1
			end
			return n
		end
		local ok, err = pcall(function()
			T.check(type(delay) == "number" and delay >= 2 and delay <= 10, "Config.Sky.Transitions.Preload.RaidDelay: a few seconds", tostring(delay))
			delay = type(delay) == "number" and delay or 4
			SC.Stop()
			St.Gate = gate
			local lists = slowPreloads()
			publish(300) -- Day, no window near
			SC.Start()
			KC.advance(0.1)
			local n = raidLists(lists)
			T.check(n == 0, "the menu is still up: no raid sky preloaded", describe(lists))
			played = true
			gate.Played:Fire()
			KC.advance(0.1)
			T.check(#lists == 0, "PLAY: nothing at once (the lobby loads first)", describe(lists))
			KC.advance(delay - 0.15)
			T.check(#lists == 0, fmt("still nothing just before RaidDelay (%.1f s)", delay), describe(lists))
			KC.advance(0.15)
			T.check(#lists == 1, "RaidDelay s after PLAY: the first raid sky starts (only one)", describe(lists))
			KC.advance(1.0)
			T.check(#lists == 2, "one at a time: the second starts when the first is done", describe(lists))
			KC.advance(2.5)
			local count, all = raidLists(lists)
			T.check(count == 4 and all and #lists == 4, "the four raid skies preloaded (four lists of six faces)", describe(lists))
			T.check(threads(lists) == 1, "all four from one thread", fmt("%d threads", threads(lists)))
			gate.Played:Fire()
			KC.advance(delay + 4.5)
			T.check(#lists == 4, "once per start: a second Played adds nothing", describe(lists))
			-- a controller that starts after PLAY preloads them RaidDelay s after its start
			SC.Stop()
			lists = slowPreloads()
			SC.Start()
			KC.advance(0.1)
			T.check(#lists == 0, "started after PLAY: nothing at once", describe(lists))
			KC.advance(delay + 4)
			count, all = raidLists(lists)
			T.check(count == 4 and all and threads(lists) == 1, "started after PLAY: the raid skies preload after RaidDelay, one thread", describe(lists))
			-- stopped before the delay ran out: nothing
			SC.Stop()
			lists = slowPreloads()
			SC.Start()
			KC.advance(0.1)
			SC.Stop()
			KC.advance(delay + 4)
			T.check(#lists == 0, "a controller stopped during RaidDelay preloads nothing", describe(lists))
		end)
		St.Gate = nil
		T.check(ok, "skytransition_preloads_raids_after_menu ran without errors", tostring(err))
	end)

	-- S3 (sky audit F9, F10): small transitions -------------------------------------------------------------------------
	local Lighting = game:GetService("Lighting")

	-- the tweens playing on `inst` right now
	local function playingOn(inst)
		local out = {}
		for tw in pairs(Mock.ActiveTweens) do
			if tw.Instance == inst and tw.PlaybackState == Enum.PlaybackState.Playing then
				out[#out + 1] = tw
			end
		end
		return out
	end

	local function countBlurs()
		local n = 0
		for _, c in ipairs(Lighting:GetChildren()) do
			if c.Name == "NimbusHatchBlur" then
				n = n + 1
			end
		end
		return n
	end

	S.hatchfx_blur_tweens_out = guarded("hatchfx_blur_tweens_out", function()
		local okF, FX = pcall(require, Mock.GetPath(ROOTS["client"] .. "/UI/HatchFx"))
		local okT, ST = pcall(require, Mock.GetPath(ROOTS["client"] .. "/SkyTransition"))
		if not T.check(okF and type(FX) == "table" and okT and type(ST) == "table" and type(ST.BlurOut) == "function", "HatchFx + SkyTransition.BlurOut load", tostring(okT and ST)) then
			return
		end
		local Scr = Cfg.Sky.Transitions.Screen
		T.check(type(Scr) == "table" and type(Scr.Out) == "number" and Scr.Out > 0, "Config.Sky.Transitions.Screen.Out (BlurOut's default)", tostring(Scr))
		local function blur()
			return Lighting:FindFirstChild("NimbusHatchBlur")
		end
		local ok, err = pcall(function()
			FX.Dim(false, 0.01)
			KC.advance(0.1)
			FX.Dim(true, 0.2)
			KC.advance(0.3)
			local b = blur()
			if not T.check(b ~= nil and b:IsA("BlurEffect") and b.Size == 14, "Dim(true): NimbusHatchBlur at Size 14 (High)", b and tostring(b.Size) or "no blur") then
				return
			end
			-- off: the blur eases to 0 over the given seconds (Quad In), then goes
			local on = FX.Dim(false, 0.35)
			KC.advance(0.05)
			local tw = playingOn(b)
			T.check(blur() == b and b.Parent == Lighting, "Dim(false): the blur is still there 0.05 s later (no one-frame snap)")
			T.check(#tw == 1 and Mock.TweenGoals(tw[1]).Size == 0 and math.abs(tw[1].TweenInfo.Time - 0.35) < 1e-6 and tw[1].TweenInfo.EasingStyle == Enum.EasingStyle.Quad and tw[1].TweenInfo.EasingDirection == Enum.EasingDirection.In,
				"Dim(false, 0.35): one Size -> 0 tween over 0.35 s, Quad In", tw[1] and fmt("%d tweens, %.2f s %s %s", #tw, tw[1].TweenInfo.Time, tw[1].TweenInfo.EasingStyle.Name, tw[1].TweenInfo.EasingDirection.Name) or "none")
			T.check(on == 0 and FX.Stats().Effects == 0, "Dim(false): the effects count says off at once (the fading blur is on its way out)", tostring(on))
			KC.advance(0.35)
			T.check(blur() == nil and b.Parent == nil, "the blur is destroyed when its fade completes")
			-- on again in the middle of a fade: the same blur comes back from where it is (no new one, no pop to 0)
			FX.Dim(true, 0.2)
			KC.advance(0.3)
			b = blur()
			FX.Dim(false, 0.35)
			KC.advance(0.1)
			FX.Dim(true, 0.2)
			KC.advance(0.01)
			local tw2 = playingOn(b)
			T.check(blur() == b and countBlurs() == 1, "Dim(true) mid-fade keeps the fading blur (one NimbusHatchBlur)", fmt("%d blurs", countBlurs()))
			T.check(#tw2 == 1 and Mock.TweenGoals(tw2[1]).Size == 14, "...the fade is cancelled, one tween back to 14", fmt("%d tweens", #tw2))
			KC.advance(0.6)
			T.check(blur() == b and b.Size == 14, "...and the cancelled fade never destroys it", blur() and tostring(blur().Size) or "gone")
			FX.Dim(false, 0.35)
			KC.advance(0.5)
			T.check(blur() == nil and countBlurs() == 0, "off again: gone after the fade")
			-- the helper alone: the kind's seconds when none are given; junk does nothing
			local bb = Instance.new("BlurEffect")
			bb.Name = "KitbBlurOut"
			bb.Size = 10
			bb.Parent = Lighting
			local t3 = ST.BlurOut(bb)
			T.check(t3 ~= nil and math.abs(t3.TweenInfo.Time - Scr.Out) < 1e-6 and Mock.TweenGoals(t3).Size == 0, "SkyTransition.BlurOut(blur): Size -> 0 over Screen.Out", t3 and tostring(t3.TweenInfo.Time) or "no tween")
			KC.advance(Scr.Out + 0.1)
			T.check(bb.Parent == nil, "SkyTransition.BlurOut: destroyed after the tween")
			local okJ = pcall(function()
				ST.BlurOut(nil)
				ST.BlurOut("x")
				ST.BlurOut(Instance.new("Folder"))
			end)
			T.check(okJ, "SkyTransition.BlurOut ignores junk")
		end)
		T.check(ok, "hatchfx_blur_tweens_out ran without errors", tostring(err))
		pcall(FX.Dim, false, 0.01)
		KC.advance(0.1)
	end)

	-- a dungeon run on this client (the DungeonState payloads), the Dungeon pushes / pops of LightingStack recorded
	local function withDungeon(name, fn)
		return guarded(name, function()
			local okD, DC = pcall(require, Mock.GetPath(ROOTS["client"] .. "/Controllers/DungeonController"))
			local okL, LSt = pcall(require, Mock.GetPath(ROOTS["client"] .. "/LightingStack"))
			if not T.check(okD and type(DC) == "table" and okL and type(LSt) == "table", "DungeonController + LightingStack load", tostring(DC)) then
				return
			end
			pcall(DC.Init)
			local LP = game:GetService("Players").LocalPlayer
			local me = LP.UserId
			local function endRun()
				KC.toClient("DungeonState", "End", { Floor = 2, Name = "Stone Halls", Cleared = false, Reason = "Quit", Room = 1, Totals = { Cash = 0, Tokens = 0, Xp = 0, Gems = 0 } })
			end
			endRun()
			KC.advance(2.6)
			local rec = { pushes = {}, pops = {} }
			local realPush, realPop = LSt.Push, LSt.Pop
			LSt.Push = function(id, preset, seconds)
				if id == "Dungeon" then
					rec.pushes[#rec.pushes + 1] = { preset = preset, s = seconds }
				end
				return realPush(id, preset, seconds)
			end
			LSt.Pop = function(id, seconds)
				if id == "Dungeon" then
					rec.pops[#rec.pops + 1] = { s = seconds }
				end
				return realPop(id, seconds)
			end
			LP:SetAttribute("InMatch", false)
			LP:SetAttribute("InBattle", "D88")
			rec.run = { RunId = "D88", Floor = 2, Name = "Stone Halls", Element = "Earth", Room = 0, RoomCount = 4, Wave = 0, Waves = 0, State = "Hall",
				Members = { { UserId = me, Name = LP.Name } }, Confirmed = {}, NeedConfirm = 1, EnterOpen = true, Next = 1, Joinable = true }
			rec.endRun = endRun
			local ok, err = pcall(fn, DC, LP, rec)
			LSt.Push, LSt.Pop = realPush, realPop
			endRun()
			LP:SetAttribute("InBattle", nil)
			KC.advance(2.6)
			T.check(ok, name .. " ran without errors", tostring(err))
			T.check(DC.GetState().Lit ~= true, name .. ": the run's light is off afterwards")
			KC.flushErrors(name)
		end)
	end

	local function zone()
		local Z = Cfg.Sky.Transitions.Zone
		T.check(type(Z) == "table" and Z.In == 1.5 and Z.Out == 2 and Z.Late == 2.5, "Config.Sky.Transitions.Zone: In 1.5, Out 2, Late 2.5", Z and fmt("%s / %s / %s", tostring(Z.In), tostring(Z.Out), tostring(Z.Late)) or "missing")
		return Z or { In = 1.5, Out = 2, Late = 2.5 }
	end

	S.dungeon_light_dim_duration = withDungeon("dungeon_light_dim_duration", function(DC, LP, rec)
		local Z = zone()
		KC.toClient("DungeonState", "Run", rec.run)
		KC.advance(0.1)
		T.check(DC.GetState().Lit == true and #rec.pushes == 1 and rec.pushes[1].s == Z.In, fmt("the run's dim: one Dungeon push over Zone.In (%.1f s; was 1 s)", Z.In), rec.pushes[1] and tostring(rec.pushes[1].s) or "no push")
		KC.advance(0.5)
		rec.endRun()
		KC.advance(0.1)
		T.check(#rec.pops == 1 and rec.pops[1].s == Z.Out, fmt("End with no fade on screen: the light comes back over Zone.Out (%.1f s; was 1 s)", Z.Out), rec.pops[1] and tostring(rec.pops[1].s) or "no pop")
	end)

	S.dungeon_late_mood_slow_push = withDungeon("dungeon_late_mood_slow_push", function(DC, LP, rec)
		local Z = zone()
		local char = LP.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not T.check(root ~= nil and root:IsA("BasePart"), "the client world has a character root (the pocket is found near it)") then
			return
		end
		local folder = Workspace:FindFirstChild("Dungeons")
		local madeFolder = folder == nil
		if madeFolder then
			folder = Instance.new("Folder")
			folder.Name = "Dungeons"
			folder.Parent = Workspace
		end
		local holder = nil
		local ok, err = pcall(function()
			KC.toClient("DungeonState", "Run", rec.run)
			KC.advance(0.1)
			T.check(#rec.pushes == 1 and rec.pushes[1].s == Z.In, "the run starts with no pocket mood readable: the contract preset over Zone.In", rec.pushes[1] and tostring(rec.pushes[1].s) or "no push")
			-- the pocket streams in a moment later with its tier mood
			holder = Instance.new("Part")
			holder.Name = "KitbMoodPocket"
			holder.Anchored = true
			holder.Position = root.Position
			holder:SetAttribute("MoodAmbient", Color3.fromRGB(150, 140, 170))
			holder:SetAttribute("MoodOutdoor", Color3.fromRGB(160, 150, 180))
			holder:SetAttribute("MoodBrightness", 0.02)
			holder:SetAttribute("MoodContrast", 0.12)
			holder:SetAttribute("MoodTint", Color3.fromRGB(250, 246, 255))
			holder.Parent = folder
			KC.advance(1.3)
			local p = rec.pushes[2]
			local want = DC._Mood.Read(holder)
			T.check(#rec.pushes == 2 and p.s == Z.Late, fmt("the late mood is re-pushed over Zone.Late (%.1f s, not a 1 s re-tint mid-play)", Z.Late), fmt("%d pushes, %s", #rec.pushes, p and tostring(p.s) or "-"))
			T.check(p ~= nil and want ~= nil and p.preset.Lighting.Ambient == want.Lighting.Ambient, "...with the pocket's mood", p and tostring(p.preset.Lighting.Ambient) or "-")
			KC.advance(3)
			T.check(#rec.pushes == 2, "...once (no further re-pushes)", tostring(#rec.pushes))
		end)
		if holder then
			holder:Destroy()
		end
		if madeFolder then
			folder:Destroy()
		end
		T.check(ok, "dungeon_late_mood_slow_push body", tostring(err))
	end)

	S.dungeon_end_fade_tweens_out = withDungeon("dungeon_end_fade_tweens_out", function(DC, LP, rec)
		local Scr = Cfg.Sky.Transitions.Screen
		T.check(type(Scr) == "table" and Scr.Lift == 0.3, "Config.Sky.Transitions.Screen.Lift: 0.3 s", Scr and tostring(Scr.Lift) or "missing")
		local lift = Scr and Scr.Lift or 0.3
		local pg = LP:FindFirstChild("PlayerGui")
		local fg = pg and pg:FindFirstChild("NimbusDungeonFade")
		local frame = fg and fg:FindFirstChild("Fade")
		if not T.check(frame ~= nil, "the NimbusDungeonFade overlay exists") then
			return
		end
		KC.toClient("DungeonState", "Run", rec.run)
		KC.advance(0.6)
		KC.toClient("DungeonState", "Fade", { Out = 0.45, Hold = 0.35, In = 0.45, Room = 1 })
		KC.advance(0.6)
		T.check(frame.Visible and frame.BackgroundTransparency <= 0.05, "(setup) the screen is black", tostring(frame.BackgroundTransparency))
		rec.endRun()
		KC.advance(0.05)
		local tw = playingOn(frame)
		T.check(frame.Visible == true and fg.Enabled == true, "End under the black: the frame is still up 0.05 s later (no one-frame cut)")
		T.check(#tw == 1 and Mock.TweenGoals(tw[1]).BackgroundTransparency == 1 and math.abs(tw[1].TweenInfo.Time - lift) < 1e-6, fmt("...it tweens out over Screen.Lift (%.1f s)", lift), tw[1] and fmt("%d tweens, %.2f s", #tw, tw[1].TweenInfo.Time) or "no tween")
		T.check(DC.GetState().Fade == nil, "...the fade itself is over (GetState().Fade nil)", tostring(DC.GetState().Fade))
		T.check(#rec.pops == 1 and rec.pops[1].s == 0, "the light pops back under the black (0 s: never seen)", rec.pops[1] and tostring(rec.pops[1].s) or "no pop")
		KC.advance(lift + 0.05)
		T.check(frame.Visible == false and fg.Enabled == false, "after Screen.Lift the overlay is off")
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
