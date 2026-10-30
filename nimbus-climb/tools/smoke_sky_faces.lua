-- smoke_sky_faces.lua: the living sky's painted faces (plan docs/superpowers/plans/2026-10-30-living-sky.md Task 3,
-- spec docs/superpowers/specs/2026-10-30-living-sky-cycle-design.md). Loaded by tools/smoke.py in the server world.
--   skyfaces_none      (server world, pure) an empty TextureIds -> SkyFaces.For = nil for all 7 themes (Config.Sky.Themes +
--                      RaidThemes); Keys(theme) = the six "sky_<theme>_<Face>" keys in Bk Dn Ft Lf Rt Up order; junk
--                      theme ids give nil / no keys; For(theme) without ids reads the real shared/TextureIds
--   skyfaces_full      (server world, pure) six positive integer ids -> the six SkyboxBk..SkyboxUp = "rbxassetid://<id>"
--                      strings (big ids printed whole), nothing else; another theme's ids are never mixed in
--   skyfaces_partial   (server world, pure) five of six ids -> nil (a half-uploaded theme counts as missing, so no grey
--                      face ever shows); a junk sixth id (0, negative, fractional, NaN, a string) -> nil too
--   skyfaces_preset_fallback (server world, pure) SkyCycle.Preset with a facesFor returning nil (SkyFaces.For on an
--                      empty TextureIds) carries no Skybox* keys in every phase and raid (the Sky keeps LightingService's
--                      boot faces); with all six ids of every theme it carries exactly that theme's six faces
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local fmt = string.format

local FACES = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }

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

-- SkyFaces + the 7 theme ids of Config.Sky (sorted), or nil after one failed check
local function faces()
	local SF = loadModule("SkyFaces")
	local Config = loadModule("Config")
	if not T.check(SF and type(SF.For) == "function" and type(SF.Keys) == "function", "SkyFaces exists with For / Keys", "src/shared/SkyFaces.lua missing or incomplete") then
		return nil
	end
	local sky = Config and Config.Sky
	if not T.check(type(sky) == "table" and type(sky.Themes) == "table" and type(sky.RaidThemes) == "table", "Config.Sky has Themes / RaidThemes") then
		return nil
	end
	local seen, themes = {}, {}
	for _, list in ipairs({ sky.Themes, sky.RaidThemes }) do
		for _, theme in pairs(list) do
			if not seen[theme] then
				seen[theme] = true
				themes[#themes + 1] = theme
			end
		end
	end
	table.sort(themes)
	T.check(#themes == 7, "7 sky themes (3 cycle + 4 raid)", tostring(#themes))
	return SF, themes, sky
end

-- six ids for a theme (a distinct big id per face and theme), as TextureIds would carry them after the upload
local function idsFor(theme, base, ids)
	ids = ids or {}
	for i, face in ipairs(FACES) do
		ids["sky_" .. theme .. "_" .. face] = base + i
	end
	return ids
end

-- skyfaces_none
S.skyfaces_none = guarded("skyfaces_none", function()
	local SF, themes = faces()
	if not SF then
		return
	end
	local none = T.tally("empty TextureIds: For = nil for every theme")
	for _, theme in ipairs(themes) do
		none:case(SF.For(theme, {}) == nil, theme)
	end
	none:report()
	local keys = SF.Keys("day_vivid")
	local want = { "sky_day_vivid_Bk", "sky_day_vivid_Dn", "sky_day_vivid_Ft", "sky_day_vivid_Lf", "sky_day_vivid_Rt", "sky_day_vivid_Up" }
	local okKeys = type(keys) == "table" and #keys == 6
	for i = 1, 6 do
		okKeys = okKeys and keys[i] == want[i]
	end
	T.check(okKeys, "Keys(day_vivid) = sky_day_vivid_Bk .. _Up in Bk Dn Ft Lf Rt Up order", type(keys) == "table" and table.concat(keys, ",") or tostring(keys))
	T.check(SF.Keys("day_vivid") ~= keys, "Keys returns a fresh table every call")
	local junk = T.tally("junk theme ids: For = nil, Keys = {}")
	for _, bad in ipairs({ false, 7, "", {} }) do
		local k = SF.Keys(bad)
		junk:case(SF.For(bad, idsFor("day_vivid", 100)) == nil and type(k) == "table" and #k == 0, tostring(bad))
	end
	junk:case(SF.For(nil, {}) == nil and #SF.Keys(nil) == 0, "nil")
	junk:report()
	-- without an ids table For reads shared/TextureIds (no sky keys there until the owner's keyed upload)
	local TextureIds = loadModule("TextureIds")
	if T.check(type(TextureIds) == "table", "shared/TextureIds loads") then
		local same = T.tally("For(theme) = For(theme, TextureIds)")
		for _, theme in ipairs(themes) do
			local a, b = SF.For(theme), SF.For(theme, TextureIds)
			same:case((a == nil) == (b == nil) and (a == nil or a.SkyboxBk == b.SkyboxBk), theme)
		end
		same:report()
	end
end)

-- skyfaces_full
S.skyfaces_full = guarded("skyfaces_full", function()
	local SF, themes = faces()
	if not SF then
		return
	end
	local ids = {}
	for i, theme in ipairs(themes) do
		idsFor(theme, 140427438072000 + i * 10, ids)
	end
	local full = T.tally("six ids -> the six SkyboxBk..SkyboxUp rbxassetid:// strings, nothing else")
	for i, theme in ipairs(themes) do
		local f = SF.For(theme, ids)
		local ok = type(f) == "table"
		local count = 0
		for key, v in pairs(f or {}) do
			count = count + 1
			ok = ok and type(key) == "string" and type(v) == "string"
		end
		-- the rendered Lf / Rt faces trade slots (Roblox draws SkyboxRt on -X): SkyFaces' SLOT
		local slot = { Bk = "Bk", Dn = "Dn", Ft = "Ft", Lf = "Rt", Rt = "Lf", Up = "Up" }
		for j, face in ipairs(FACES) do
			ok = ok and f["Skybox" .. slot[face]] == fmt("rbxassetid://%d", 140427438072000 + i * 10 + j)
		end
		full:case(ok and count == 6, theme .. (f and (" " .. tostring(f.SkyboxBk)) or " nil"))
	end
	full:report()
	local a, b = SF.For(themes[1], ids), SF.For(themes[1], ids)
	T.check(a ~= b and a.SkyboxUp == b.SkyboxUp, "For returns a fresh table every call")
	T.eq(SF.For("day_vivid", idsFor("day_vivid", 96614468669578)).SkyboxBk, "rbxassetid://96614468669579", "a 14-digit id is printed whole")
	-- another theme's six ids never make this theme known
	T.check(SF.For("night_aurora", idsFor("day_vivid", 100)) == nil, "day_vivid's ids do not give night_aurora faces")
end)

-- skyfaces_partial
S.skyfaces_partial = guarded("skyfaces_partial", function()
	local SF, themes = faces()
	if not SF then
		return
	end
	local part = T.tally("five of six ids (each face missing in turn) -> nil")
	for _, theme in ipairs(themes) do
		for _, face in ipairs(FACES) do
			local ids = idsFor(theme, 5000)
			ids["sky_" .. theme .. "_" .. face] = nil
			part:case(SF.For(theme, ids) == nil, theme .. " without " .. face)
		end
	end
	part:report()
	local junk = T.tally("a junk sixth id -> nil")
	for _, bad in ipairs({ 0, -12, 1.5, 0 / 0, math.huge, "123", true }) do
		local ids = idsFor("storm_teal", 5000)
		ids.sky_storm_teal_Up = bad
		junk:case(SF.For("storm_teal", ids) == nil, tostring(bad))
	end
	junk:report()
	T.check(type(SF.For("storm_teal", idsFor("storm_teal", 5000))) == "table", "the same six without the junk -> faces")
end)

-- skyfaces_preset_fallback
S.skyfaces_preset_fallback = guarded("skyfaces_preset_fallback", function()
	local SF, themes, sky = faces()
	local SC = loadModule("SkyCycle")
	if not SF or not T.check(SC and type(SC.Preset) == "function" and type(SC.At) == "function", "SkyCycle exists with At / Preset") then
		return
	end
	local function noFaces(theme)
		return SF.For(theme, {})
	end
	local ids, base = {}, {}
	for i, theme in ipairs(themes) do
		base[theme] = 7000 + i * 10
		idsFor(theme, base[theme], ids)
	end
	local function allFaces(theme)
		return SF.For(theme, ids)
	end
	local bosses = { false }
	for bossId in pairs(sky.RaidThemes) do
		bosses[#bosses + 1] = bossId
	end
	local loop = 0
	for _, phase in ipairs(sky.Cycle.Order) do
		loop = loop + sky.Cycle.Seconds[phase]
	end
	local none = T.tally("facesFor -> nil: no Skybox* keys (every phase sample, every raid)")
	local some = T.tally("all ids known: exactly the returned theme's six faces")
	for t = 0, loop - 1, 15 do
		local at = SC.At(t, 0, 1, 0)
		for _, bossId in ipairs(bosses) do
			local event = bossId or nil
			local p = SC.Preset(at, event, event and 1 or 0, noFaces)
			local stray
			for key in pairs(p.Sky or {}) do
				if type(key) == "string" and key:sub(1, 6) == "Skybox" then
					stray = key
				end
			end
			none:case(stray == nil, fmt("t %d %s: %s", t, tostring(event), tostring(stray)))
			local p2, theme = SC.Preset(at, event, event and 1 or 0, allFaces)
			local ok = type(theme) == "string" and base[theme] ~= nil
			local slot = { Bk = "Bk", Dn = "Dn", Ft = "Ft", Lf = "Rt", Rt = "Lf", Up = "Up" } -- SkyFaces' SLOT
			for j, face in ipairs(FACES) do
				ok = ok and p2.Sky["Skybox" .. slot[face]] == fmt("rbxassetid://%d", (base[theme] or 0) + j)
			end
			-- a painted sky hides the engine sun / moon (no second sun on top of the painted one)
			ok = ok and p2.Sky.CelestialBodiesShown == false
			-- ... and its glow: no Atmosphere glare, no sun rays at the engine sun
			ok = ok and p2.Atmosphere and p2.Atmosphere.Glare == 0 and p2.SunRays and p2.SunRays.Intensity == 0
			some:case(ok, fmt("t %d %s: %s", t, tostring(event), tostring(theme)))
		end
	end
	none:report()
	some:report()
end)

return S
