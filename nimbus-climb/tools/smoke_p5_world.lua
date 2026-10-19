-- smoke_p5_world.lua: the Phase 5 world (ARCHITECTURE_V3.md "Phase 5 build contract" 6.1-6.5, 10.3, 12.1).
-- Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half.
--
-- worldstyle (W1):
--   p5world_lighting       (server, booted) LightingService.Look = { Custom, Fallback } with the contract's numbers; boot
--                          with empty Config.Sky.Faces = Fallback (stock skybox, 3000 stars, pink clouds); all six ids =
--                          Custom (the Sky's six Skybox* ids, StarCount 0); one id missing / unreadable -> Fallback + a
--                          warning naming it (a bare number is unreadable); Init() twice = the same Lighting (values
--                          and children); Init never touches Players.CharacterAutoLoads (Main holds spawns, 7.2)
--   p5world_style          (server, booted) the WorldStyle helpers: Materials / Palette (big-surface colours obey the
--                          saturation / value rule), Jitter, Plinth / Kerb / Chamfer geometry (the chamfer's bevels),
--                          BuildGate for all six Gate Court specs (22 x 8 x 26, <= 90 parts, pad 14 x 0.6 x 14 fourteen
--                          studs in front or the 10 x 0.3 x 6 step, the prompt anchor, one PointLight + sparkles, the
--                          Neon / ForceField discs, the cloned 6x6 emblem, the pixel tag per the World text rule, upright
--                          on a tilted site, deterministic) and the art-rule audit (styleAudit) run on every gate.
--                          [W2 worldlobby] extends it with the lobby-wide audit (marked below).
--   client_p5lightingstack (client) LightingStack: Push A, Push B, Pop A -> B applied; Pop B -> base exact; unknown id
--                          no-op; tweened pushes reach their goal and a later Push cancels a running tween; re-push moves
--                          to the top; GfxLow + Dungeon stacked (each restores only its own properties)
-- worldlobby (W2): p5world_lobby, p5world_gates, p5obby_levels, p5obby_migration, p5world_client_total (spots marked
-- below); dungeonclient (W4): client_p5obby.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, min, floor, sqrt = math.abs, math.max, math.min, math.floor, math.sqrt

local function fmt(v, n)
	return string.format("%." .. (n or 2) .. "f", tonumber(v) or 0)
end

local function rgb255(c)
	return floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5)
end

local function sameColor(c, r, g, b)
	local cr, cg, cb = rgb255(c)
	return abs(cr - r) <= 1 and abs(cg - g) <= 1 and abs(cb - b) <= 1
end

local function hsv(c)
	local hi = max(c.R, c.G, c.B)
	local lo = min(c.R, c.G, c.B)
	return hi > 0 and (hi - lo) / hi or 0, hi
end

local function parts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			out[#out + 1] = d
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- The art-rule audit (6.4 rules 1, 2, 7, 8): shared by p5world_style (gates, W1) and the lobby-wide pass (W2).
-- opts: { label, exemptTag = "NC_StyleExempt", maxShadowLights = 12, gateParts = 120 }
-- Returns { parts, shadowLights, bad = { material, plastic, saturation, value, shadow } }.
----------------------------------------------------------------------------------------------------
local function styleAudit(root, WS, opts)
	opts = opts or {}
	local label = opts.label or root.Name
	local CS = game:GetService("CollectionService")
	local exemptTag = (WS.Tags and WS.Tags.Exempt) or "NC_StyleExempt"
	local function exempt(p)
		local cur = p
		while cur and cur ~= game do
			if CS:HasTag(cur, exemptTag) then
				return true
			end
			cur = cur.Parent
		end
		return false
	end
	local tMat = T.tally(label .. ": every part uses a WorldStyle.Materials material (6.4 rule 1)")
	local tPlastic = T.tally(label .. ": no SmoothPlastic part with a side > 2 studs (rule 1)")
	local tSat = T.tally(label .. ": large faces (> 16 studs^2) have saturation <= 0.45 unless a thin Neon inlay / a piece <= 8 studs^3 (rule 2)")
	local tVal = T.tally(label .. ": large opaque faces have value 0.35..0.9 (rule 2)")
	local tShadow = T.tally(label .. ": parts < 4 studs cast no shadow (rule 8)")
	local n, shadowLights = 0, 0
	for _, p in ipairs(parts(root)) do
		n = n + 1
		local s = p.Size
		local dims = { s.X, s.Y, s.Z }
		table.sort(dims)
		local face = dims[2] * dims[3]
		local vol = s.X * s.Y * s.Z
		local visible = p.Transparency < 0.99
		local isNeon = p.Material == Enum.Material.Neon
		if visible and not exempt(p) then
			tMat:case(WS.IsWorldMaterial(p.Material), p:GetFullName() .. " " .. tostring(p.Material))
			tPlastic:case(not (p.Material == Enum.Material.SmoothPlastic and dims[3] > 2), p:GetFullName() .. " " .. fmt(dims[3], 1))
			if face > 16 then
				local sat, val = hsv(p.Color)
				local thinNeon = isNeon and dims[1] <= 0.5
				local forceField = p.Material == Enum.Material.ForceField
				tSat:case(sat <= 0.45 or thinNeon or forceField or vol <= 8, p:GetFullName() .. " sat " .. fmt(sat))
				if not isNeon and not forceField and p.Transparency < 0.3 then
					tVal:case(val >= 0.35 and val <= 0.9, p:GetFullName() .. " value " .. fmt(val))
				end
			end
		end
		if dims[3] < 4 then
			tShadow:case(p.CastShadow == false, p:GetFullName())
		end
	end
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight")) and d.Shadows then
			shadowLights = shadowLights + 1
		end
	end
	tMat:report()
	tPlastic:report()
	tSat:report()
	tVal:report()
	tShadow:report()
	T.check(shadowLights <= (opts.maxShadowLights or 12), label .. ": <= " .. (opts.maxShadowLights or 12) .. " shadow-casting lights (rule 7)", tostring(shadowLights))
	return { parts = n, shadowLights = shadowLights }
end

-- The pixel tag of the World text rule: offset-only sizes, TextSize >= 18 (titles >= 22), an outline on every
-- label, LightInfluence 0, MaxDistance 60..120, never TextScaled.
local function pixelTagCheck(gui, label)
	if not T.check(gui ~= nil and gui:IsA("BillboardGui"), label .. ": has a BillboardGui tag") then
		return
	end
	T.check(gui.Size.X.Scale == 0 and gui.Size.Y.Scale == 0 and gui.Size.X.Offset > 0, label .. ": the tag is pixel-sized (offset UDim2)", tostring(gui.Size))
	T.check(gui.MaxDistance >= 60 and gui.MaxDistance <= 120, label .. ": MaxDistance 60..120", tostring(gui.MaxDistance))
	T.eq(gui.LightInfluence, 0, label .. ": LightInfluence 0")
	local t = T.tally(label .. ": every tag label is >= 18 px, outlined, not TextScaled")
	local count = 0
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") then
			count = count + 1
			local stroke = d:FindFirstChildOfClass("UIStroke")
			t:case(d.TextSize >= 18 and not d.TextScaled and stroke ~= nil, d.Name .. " " .. tostring(d.TextSize))
		end
	end
	t:report(count .. " labels")
end

----------------------------------------------------------------------------------------------------
-- server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local K = _G.K
	local S = {}
	local M = K.M
	local Players = game:GetService("Players")
	local Lighting = game:GetService("Lighting")

	local function config()
		return K.config()
	end

	------------------------------------------------------------------------------------------------
	-- p5world_lighting
	------------------------------------------------------------------------------------------------
	local LIGHTING_PROPS = {
		"ClockTime", "GeographicLatitude", "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient", "ColorShift_Top",
		"ColorShift_Bottom", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows", "ShadowSoftness", "FogStart", "FogEnd",
	}
	local CHILD_PROPS = {
		{ "Atmosphere", { "Density", "Offset", "Color", "Decay", "Glare", "Haze" } },
		{ "Sky", { "StarCount", "CelestialBodiesShown", "SunAngularSize", "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" } },
		{ "BloomEffect", { "Enabled", "Intensity", "Size", "Threshold" } },
		{ "SunRaysEffect", { "Enabled", "Intensity", "Spread" } },
		{ "ColorCorrectionEffect", { "Enabled", "Contrast", "Saturation", "TintColor", "Brightness" } },
	}
	-- a printable snapshot of everything LightingService writes (deterministic order)
	local function lightingSnapshot()
		local out = {}
		for _, k in ipairs(LIGHTING_PROPS) do
			out[#out + 1] = k .. "=" .. tostring(Lighting[k])
		end
		for _, entry in ipairs(CHILD_PROPS) do
			local inst = Lighting:FindFirstChildOfClass(entry[1])
			out[#out + 1] = entry[1] .. ":" .. tostring(inst ~= nil)
			if inst then
				for _, k in ipairs(entry[2]) do
					out[#out + 1] = entry[1] .. "." .. k .. "=" .. tostring(inst[k])
				end
			end
		end
		local clouds = workspace.Terrain and workspace.Terrain:FindFirstChildOfClass("Clouds")
		if clouds then
			out[#out + 1] = "Clouds=" .. tostring(clouds.Cover) .. "/" .. tostring(clouds.Density) .. "/" .. tostring(clouds.Color)
		end
		out[#out + 1] = "children=" .. #Lighting:GetChildren()
		return table.concat(out, "\n")
	end

	local function setFaces(Config, faces)
		for _, k in ipairs({ "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }) do
			Config.Sky.Faces[k] = faces[k] or ""
		end
	end

	S.p5world_lighting = guarded("p5world_lighting", function()
		local Config = config()
		local LS = M["server/Services/LightingService"]
		if not T.check(type(LS) == "table" and type(LS.Init) == "function", "LightingService is loaded") then
			return
		end
		if not T.check(type(Config.Sky) == "table" and type(Config.Sky.Faces) == "table", "Config.Sky.Faces exists (lead W0)") then
			return
		end
		local saved = {}
		for k, v in pairs(Config.Sky.Faces) do
			saved[k] = v
		end
		local look = LS.Look
		T.check(type(look) == "table" and type(look.Custom) == "table" and type(look.Fallback) == "table", "LightingService.Look = { Custom, Fallback }")
		if type(look) ~= "table" or not look.Custom or not look.Fallback then
			return
		end
		-- the contract's numbers (6.4)
		local C, F = look.Custom, look.Fallback
		local function numbers(t, L, name)
			T.eq(t.Lighting.ClockTime, L[1], name .. ": ClockTime")
			T.eq(t.Lighting.Brightness, L[2], name .. ": Brightness")
			T.eq(t.Lighting.ExposureCompensation, L[3], name .. ": ExposureCompensation")
			T.check(sameColor(t.Lighting.Ambient, L[4][1], L[4][2], L[4][3]), name .. ": Ambient")
			T.check(sameColor(t.Lighting.OutdoorAmbient, L[5][1], L[5][2], L[5][3]), name .. ": OutdoorAmbient")
			T.check(sameColor(t.Lighting.ColorShift_Top, L[6][1], L[6][2], L[6][3]), name .. ": ColorShift_Top")
			T.check(sameColor(t.Lighting.ColorShift_Bottom, L[7][1], L[7][2], L[7][3]), name .. ": ColorShift_Bottom")
			T.eq(t.Lighting.EnvironmentDiffuseScale, L[8], name .. ": EnvironmentDiffuseScale")
			T.eq(t.Lighting.EnvironmentSpecularScale, L[9], name .. ": EnvironmentSpecularScale")
			T.eq(t.Atmosphere.Density, L[10], name .. ": Atmosphere.Density")
			T.eq(t.Atmosphere.Offset, 0.2, name .. ": Atmosphere.Offset")
			T.check(sameColor(t.Atmosphere.Color, L[11][1], L[11][2], L[11][3]), name .. ": Atmosphere.Color")
			T.check(sameColor(t.Atmosphere.Decay, L[12][1], L[12][2], L[12][3]), name .. ": Atmosphere.Decay")
			T.eq(t.Atmosphere.Glare, L[13], name .. ": Atmosphere.Glare")
			T.eq(t.Atmosphere.Haze, L[14], name .. ": Atmosphere.Haze")
			T.eq(t.Sky.StarCount, L[15], name .. ": Sky.StarCount")
			T.eq(t.Sky.SunAngularSize, L[16], name .. ": SunAngularSize")
			T.eq(t.Clouds.Cover, L[17], name .. ": Clouds.Cover")
			T.eq(t.Clouds.Density, L[18], name .. ": Clouds.Density")
			T.check(sameColor(t.Clouds.Color, L[19][1], L[19][2], L[19][3]), name .. ": Clouds.Color")
			T.eq(t.SunRays.Intensity, L[20], name .. ": SunRays.Intensity")
			T.eq(t.Bloom.Intensity, 0.25, name .. ": Bloom.Intensity")
			T.eq(t.Bloom.Size, 24, name .. ": Bloom.Size")
			T.eq(t.Bloom.Threshold, 1.35, name .. ": Bloom.Threshold")
			T.eq(t.ColorCorrection.Contrast, 0.12, name .. ": ColorCorrection.Contrast")
			T.eq(t.ColorCorrection.Saturation, 0.06, name .. ": ColorCorrection.Saturation")
			T.check(sameColor(t.ColorCorrection.TintColor, 255, 246, 252), name .. ": ColorCorrection.TintColor")
		end
		numbers(C, { 14.5, 2.2, 0, { 112, 104, 140 }, { 150, 138, 176 }, { 70, 46, 40 }, { 30, 20, 60 }, 0.7, 0.45, 0.32, { 226, 188, 232 }, { 150, 120, 210 }, 0.15, 1.2, 0, 11, 0.45, 0.55, { 255, 222, 242 }, 0.04 }, "Look.Custom")
		numbers(F, { 16.6, 2.6, 0.1, { 118, 104, 140 }, { 160, 140, 180 }, { 80, 50, 40 }, { 34, 22, 64 }, 0.6, 0.35, 0.36, { 220, 176, 232 }, { 126, 104, 214 }, 0.4, 2.0, 3000, 14, 0.62, 0.7, { 255, 206, 236 }, 0.06 }, "Look.Fallback")
		T.check(C.Bloom == F.Bloom and C.ColorCorrection == F.ColorCorrection, "Bloom and ColorCorrection are shared by both looks")

		-- FaceId: the full pasted id (trimmed); bare numbers and junk are unusable
		if T.check(type(LS.FaceId) == "function", "LightingService.FaceId exists") then
			T.eq(LS.FaceId("rbxassetid://123"), "rbxassetid://123", "FaceId keeps rbxassetid://<n>")
			T.eq(LS.FaceId(" rbxassetid://456 "), "rbxassetid://456", "FaceId trims spaces around a pasted id")
			T.eq(LS.FaceId("456"), nil, "FaceId: a bare number is not a content id (unset, the warning tells the owner)")
			T.eq(LS.FaceId(789), nil, "FaceId: a number = unset")
			T.eq(LS.FaceId(""), nil, "FaceId: empty = unset")
			T.eq(LS.FaceId("hello"), nil, "FaceId: junk = unset")
			T.eq(LS.FaceId("rbxassetid://"), nil, "FaceId: a scheme without an id = unset")
			T.eq(LS.FaceId({}), nil, "FaceId: a table = unset")
		end

		local function sky()
			return Lighting:FindFirstChildOfClass("Sky")
		end
		local ok, err = pcall(function()
			-- 1. empty faces (the shipped Config) -> Fallback
			setFaces(Config, {})
			K.resetCursors()
			T.eq(LS.Init(), "Fallback", "empty Config.Sky.Faces -> Init returns Fallback")
			T.eq(LS.Current, "Fallback", "LightingService.Current = Fallback")
			T.eq(Lighting.ClockTime, 16.6, "Fallback: ClockTime 16.6 (golden hour pinks the stock sky)")
			T.eq(Lighting.Brightness, 2.6, "Fallback: Brightness 2.6")
			local s = sky()
			if T.check(s ~= nil, "Fallback: a Sky exists") then
				T.eq(s.StarCount, 3000, "Fallback: 3000 stars")
				T.eq(s.SkyboxBk .. s.SkyboxDn .. s.SkyboxFt .. s.SkyboxLf .. s.SkyboxRt .. s.SkyboxUp, "", "Fallback: no skybox ids (the stock sky)")
			end
			local atm = Lighting:FindFirstChildOfClass("Atmosphere")
			T.check(atm ~= nil and atm.Density == 0.36 and sameColor(atm.Color, 220, 176, 232), "Fallback: pink Atmosphere (Density 0.36)")
			local clouds = workspace.Terrain and workspace.Terrain:FindFirstChildOfClass("Clouds")
			T.check(clouds ~= nil and clouds.Cover == 0.62 and sameColor(clouds.Color, 255, 206, 236), "Fallback: pink moving clouds (Cover 0.62)")
			K.flushWarnings("p5world_lighting: Init with no ids warns nothing")

			-- 2. all six ids -> Custom
			setFaces(Config, { Bk = "rbxassetid://101", Dn = "rbxassetid://102", Ft = "rbxassetid://103", Lf = " rbxassetid://104 ", Rt = "rbxassetid://105", Up = "rbxassetid://106" })
			T.eq(LS.Init(), "Custom", "six ids -> Init returns Custom")
			s = sky()
			if s then
				T.eq(s.SkyboxBk, "rbxassetid://101", "Custom: SkyboxBk")
				T.eq(s.SkyboxDn, "rbxassetid://102", "Custom: SkyboxDn")
				T.eq(s.SkyboxFt, "rbxassetid://103", "Custom: SkyboxFt")
				T.eq(s.SkyboxLf, "rbxassetid://104", "Custom: SkyboxLf (pasted with spaces, trimmed)")
				T.eq(s.SkyboxRt, "rbxassetid://105", "Custom: SkyboxRt")
				T.eq(s.SkyboxUp, "rbxassetid://106", "Custom: SkyboxUp")
				T.eq(s.StarCount, 0, "Custom: no engine stars (they are painted)")
				T.eq(s.SunAngularSize, 11, "Custom: SunAngularSize 11")
			end
			T.eq(Lighting.ClockTime, 14.5, "Custom: ClockTime 14.5")
			T.eq(Lighting.Brightness, 2.2, "Custom: Brightness 2.2")
			T.eq(Lighting.EnvironmentDiffuseScale, 0.7, "Custom: EnvironmentDiffuseScale 0.7")
			K.flushWarnings("p5world_lighting: Init with six ids warns nothing")
			-- Init twice = the same
			local before = lightingSnapshot()
			LS.Init()
			local after = lightingSnapshot()
			T.check(before == after, "Init() twice = the same Lighting (values and children)", before ~= after and (before .. "\n---\n" .. after) or nil)

			-- 3. one id missing -> Fallback (and a warning that names it), the skybox cleared
			setFaces(Config, { Bk = "rbxassetid://101", Dn = "rbxassetid://102", Ft = "rbxassetid://103", Lf = "rbxassetid://104", Rt = "rbxassetid://105" })
			local cursor = #Mock.Output
			T.eq(LS.Init(), "Fallback", "one id missing (Up) -> Fallback")
			local warned = false
			for i = cursor + 1, #Mock.Output do
				local o = Mock.Output[i]
				if o.kind == "warn" and o.text:find("[LightingService]", 1, true) and o.text:find("Up", 1, true) then
					warned = true
				end
			end
			T.check(warned, "one id missing -> a [LightingService] warning names the missing face (Up)")
			s = sky()
			T.check(s ~= nil and s.SkyboxBk == "" and s.StarCount == 3000, "one id missing -> the stock sky again (ids cleared, 3000 stars)")
			-- an unreadable id counts as missing
			setFaces(Config, { Bk = "rbxassetid://101", Dn = "rbxassetid://102", Ft = "103", Lf = "rbxassetid://104", Rt = "rbxassetid://105", Up = "rbxassetid://106" })
			T.eq(LS.Init(), "Fallback", "a bare number (\"103\") is unreadable -> Fallback")
			K.flushWarnings("p5world_lighting", { "[LightingService]" })

			-- 4. Init never touches CharacterAutoLoads (Main / PlayerService hold the spawn, 7.2)
			local autoLoads = Players.CharacterAutoLoads
			Players.CharacterAutoLoads = false
			LS.Init()
			T.eq(Players.CharacterAutoLoads, false, "LightingService.Init leaves Players.CharacterAutoLoads alone (was set to true in Phase 4)")
			Players.CharacterAutoLoads = autoLoads
			T.eq(workspace.Gravity, Config.Physics.Gravity, "world rules: workspace.Gravity = Config.Physics.Gravity")
		end)
		T.check(ok, "p5world_lighting ran without errors", tostring(err))
		-- restore the shipped Config and the boot look for the scenarios after this one
		for k in pairs(Config.Sky.Faces) do
			Config.Sky.Faces[k] = saved[k]
		end
		LS.Init()
		K.flushWarnings("p5world_lighting restore", { "[LightingService]" })
	end)

	------------------------------------------------------------------------------------------------
	-- p5world_style (the W1 helper checks; W2 adds the lobby-wide pass at the marked spot)
	------------------------------------------------------------------------------------------------
	S.p5world_style = guarded("p5world_style", function()
		local WS = M["shared/WorldStyle"]
		if not T.check(type(WS) == "table", "shared/WorldStyle is loaded") then
			return
		end
		for _, f in ipairs({ "BuildGate", "Plinth", "Kerb", "Chamfer" }) do
			T.check(type(WS[f]) == "function", "WorldStyle." .. f .. " is a function")
		end
		T.check(type(WS.Materials) == "table" and type(WS.Palette) == "table", "WorldStyle.Materials and WorldStyle.Palette are tables")
		if type(WS.BuildGate) ~= "function" or type(WS.Materials) ~= "table" or type(WS.Palette) ~= "table" then
			return
		end
		-- Materials: the contract's list (6.4 rule 1)
		for _, name in ipairs({ "Slate", "Cobblestone", "Brick", "Marble", "WoodPlanks", "Wood", "Grass", "LeafyGrass", "Sand", "ClayRoofTiles", "RoofShingles", "Metal", "Glass", "Neon", "Fabric" }) do
			T.check(WS.Materials[name] == Enum.Material[name], "WorldStyle.Materials." .. name)
		end
		T.check(WS.IsWorldMaterial(Enum.Material.Slate) and not WS.IsWorldMaterial(Enum.Material.Plastic) and not WS.IsWorldMaterial(Enum.Material.DiamondPlate), "IsWorldMaterial: Slate yes, Plastic / DiamondPlate no")
		-- Palette: big-surface colours obey the rule (saturation <= 0.45, value 0.35..0.9)
		local surf = T.tally("Palette: big-surface colours have saturation <= 0.45 and value 0.35..0.9")
		for _, key in ipairs({ "SlateDark", "Slate", "SlateLight", "Marble", "MarbleShade", "Cobble", "Brick", "WoodPlanks", "Wood", "Grass", "LeafyGrass", "Sand", "Roof", "Glass", "Fabric" }) do
			local c = WS.Palette[key]
			local sat, val = 0, 0
			if typeof(c) == "Color3" then
				sat, val = hsv(c)
			end
			surf:case(typeof(c) == "Color3" and sat <= 0.45 and val >= 0.35 and val <= 0.9, key .. " sat " .. fmt(sat) .. " val " .. fmt(val))
		end
		surf:report()
		T.check(sameColor(WS.Palette.Lantern, 255, 214, 170), "Palette.Lantern = (255, 214, 170) (rule 7)")
		T.check(sameColor(WS.Palette.CloudTop, 250, 244, 252) and sameColor(WS.Palette.CloudSide, 226, 214, 240) and sameColor(WS.Palette.CloudUnder, 186, 172, 222), "Palette clouds: tops / sides / undersides (rule 9)")
		-- Jitter: deterministic, within +-6
		local j1, j2 = WS.Jitter(WS.Palette.Slate, 42), WS.Jitter(WS.Palette.Slate, 42)
		T.check(j1 == j2, "Jitter is deterministic for a seed")
		local jt = T.tally("Jitter stays within +-6 RGB and varies")
		local seen = {}
		local br, bg, bb = rgb255(WS.Palette.Slate)
		for seed = 1, 40 do
			local r, g, b = rgb255(WS.Jitter(WS.Palette.Slate, seed))
			jt:case(abs(r - br) <= 6 and abs(g - bg) <= 6 and abs(b - bb) <= 6, "seed " .. seed)
			seen[r] = true
		end
		local variety = 0
		for _ in pairs(seen) do
			variety = variety + 1
		end
		jt:report(variety .. " distinct reds")
		T.check(variety >= 5, "Jitter gives several shades", tostring(variety))

		local folder = Instance.new("Folder")
		folder.Name = "P5StyleTest"
		folder.Parent = workspace
		local ok, err = pcall(function()
			local origin = CFrame.new(2000, 600, 2000)
			-- Plinth
			local body, band = WS.Plinth(folder, origin, Vector3.new(4, 1, 4))
			T.check(body and body.Size == Vector3.new(4, 1, 4) and body.Material == Enum.Material.Slate, "Plinth: the body is the given size in Slate")
			T.check(band and abs(band.Position.Y + band.Size.Y * 0.5 - (origin.Y + 0.5)) < 1e-3 and band.Size.X > 4, "Plinth: a band flush with the top, overhanging")
			T.check(body.CanCollide == true and body.Anchored == true, "Plinth: solid and anchored")
			-- Kerb: edge at origin2, outward = LookVector (-Z)
			local edge = CFrame.new(2100, 600, 2000)
			local kerb, lip = WS.Kerb(folder, edge, 12)
			if T.check(kerb ~= nil and lip ~= nil, "Kerb returns the kerb and the lip") then
				T.check(abs(kerb.Size.Y - 0.4) < 1e-3 and abs(kerb.Size.X - 12) < 1e-3, "Kerb: 0.4 tall, the given length")
				T.check(abs((kerb.Position.Y - kerb.Size.Y * 0.5) - 600) < 1e-3, "Kerb: stands on the platform surface")
				T.check(abs(lip.Size.Y - 0.3) < 1e-3 and lip.Position.Y + lip.Size.Y * 0.5 <= 600 + 1e-3, "Kerb: a 0.3-stud lip under the top surface")
				local lipOut = -(lip.Position.Z - lip.Size.Z * 0.5 - 2000) -- how far it sticks out toward -Z
				local kerbOut = -(kerb.Position.Z - kerb.Size.Z * 0.5 - 2000)
				T.check(lipOut >= kerbOut + 0.3 - 1e-3, "Kerb: the lip sticks out >= 0.3 beyond the kerb", fmt(lipOut) .. " vs " .. fmt(kerbOut))
			end
			-- Chamfer: a 6 x 5 x 4 box, cut 0.6
			local cOrigin = CFrame.new(2200, 600, 2000) * CFrame.Angles(0, 0.4, 0)
			local cbody, cparts = WS.Chamfer(folder, cOrigin, Vector3.new(6, 5, 4), nil, nil, 0.6)
			if T.check(cbody ~= nil and type(cparts) == "table" and #cparts == 6, "Chamfer: 6 parts (a cross + 4 corner posts)") then
				-- union extents in the local frame, and the bevel: a point just inside the box corner is NOT covered,
				-- a point just inside the bevel face is
				local function covered(lp)
					local wp = cOrigin:PointToWorldSpace(lp)
					for _, p in ipairs(cparts) do
						local q = p.CFrame:PointToObjectSpace(wp)
						if abs(q.X) <= p.Size.X * 0.5 + 1e-4 and abs(q.Y) <= p.Size.Y * 0.5 + 1e-4 and abs(q.Z) <= p.Size.Z * 0.5 + 1e-4 then
							return true
						end
					end
					return false
				end
				local ext = { 0, 0, 0 }
				for _, p in ipairs(cparts) do
					for sx = -1, 1, 2 do
						for sy = -1, 1, 2 do
							for sz = -1, 1, 2 do
								local w = p.CFrame:PointToWorldSpace(Vector3.new(sx * p.Size.X * 0.5, sy * p.Size.Y * 0.5, sz * p.Size.Z * 0.5))
								local l = cOrigin:PointToObjectSpace(w)
								ext[1] = max(ext[1], abs(l.X))
								ext[2] = max(ext[2], abs(l.Y))
								ext[3] = max(ext[3], abs(l.Z))
							end
						end
					end
				end
				T.check(abs(ext[1] - 3) < 1e-3 and abs(ext[2] - 2.5) < 1e-3 and abs(ext[3] - 2) < 1e-3, "Chamfer: the union is exactly the box", fmt(ext[1]) .. " " .. fmt(ext[2]) .. " " .. fmt(ext[3]))
				T.check(not covered(Vector3.new(2.95, 0, 1.95)), "Chamfer: the vertical corner is cut away (bevel)")
				T.check(covered(Vector3.new(2.95, 0, 1.3)) and covered(Vector3.new(2.6, 0, 1.6)), "Chamfer: the bevel face runs 0.6 along each side (45 degrees)")
				T.check(covered(Vector3.new(0, 2.45, 0)) and covered(Vector3.new(2.9, 2.45, 0)), "Chamfer: solid inside, full height")
			end

			-- the gates
			local specs = WS.SampleGates or {}
			T.check(#specs == 6, "WorldStyle.SampleGates lists the six Gate Court gates", tostring(#specs))
			local seenGlyph = {}
			for i, spec in ipairs(specs) do
				local yaw = (i - 1) * 0.7
				local site = CFrame.new(2300 + i * 40, 600, 2000) * CFrame.Angles(0, yaw, 0)
				local model, pad, prompt = WS.BuildGate(folder, site, spec)
				local label = "gate " .. spec.Id
				if T.check(model ~= nil and model:IsA("Model") and model.Parent == folder, label .. ": BuildGate returns a Model in the parent") then
					T.eq(model.Name, "Portal_" .. spec.Id, label .. ": named Portal_<Id>")
					T.eq(model:GetAttribute("GateId"), spec.Id, label .. ": attribute GateId")
					local ps = parts(model)
					T.check(#ps <= 90, label .. ": <= 90 parts (builders add <= 30: every gate <= 120)", tostring(#ps))
					T.check(pad ~= nil and pad:IsDescendantOf(model) and prompt ~= nil and prompt:IsDescendantOf(model), label .. ": returns its pad and prompt part")
					-- footprint in the site's frame (the pad / step excluded): 22 wide, 8 deep, 26 tall
					local x0, x1, y0, y1, z0, z1 = 1e9, -1e9, 1e9, -1e9, 1e9, -1e9
					local padParts = {}
					for _, p in ipairs(ps) do
						local n = p.Name
						if n == "Pad" or n == "Step" or n:sub(1, 9) == "PadBorder" or (p.Parent and p.Parent.Name == "PadGlyph") then
							padParts[#padParts + 1] = p
						elseif p.Transparency < 1 then
							for sx = -1, 1, 2 do
								for sy = -1, 1, 2 do
									for sz = -1, 1, 2 do
										local l = site:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(sx * p.Size.X * 0.5, sy * p.Size.Y * 0.5, sz * p.Size.Z * 0.5)))
										x0, x1 = min(x0, l.X), max(x1, l.X)
										y0, y1 = min(y0, l.Y), max(y1, l.Y)
										z0, z1 = min(z0, l.Z), max(z1, l.Z)
									end
								end
							end
						end
					end
					T.check(x1 - x0 <= 22.01 and x1 - x0 >= 20, label .. ": 22 studs wide", fmt(x1 - x0))
					T.check(z1 - z0 <= 8.01, label .. ": <= 8 studs deep", fmt(z1 - z0))
					T.check(abs(y1 - 26) < 0.05 and y0 >= -0.01, label .. ": 26 tall, standing on the site", fmt(y0) .. ".." .. fmt(y1))
					-- pad or step
					if spec.Pad then
						T.check(pad.Name == "Pad" and pad.Size == Vector3.new(14, 0.6, 14) and pad.Material == Enum.Material.Slate, label .. ": a 14 x 0.6 x 14 Slate pad")
						local l = site:PointToObjectSpace(pad.Position)
						T.check(abs(l.X) < 1e-3 and abs(l.Z + 14) < 1e-3 and abs(l.Y - 0.3) < 1e-3, label .. ": the pad lies 14 studs in front (toward the plaza)", tostring(l))
						local border, glyphNeon = 0, 0
						for _, p in ipairs(padParts) do
							if p.Name:sub(1, 9) == "PadBorder" and p.Material == Enum.Material.Marble then
								border = border + 1
							elseif p.Material == Enum.Material.Neon then
								glyphNeon = glyphNeon + 1
							end
						end
						T.check(border == 4 and glyphNeon >= 3, label .. ": the pad has a Marble border and a Neon glyph", border .. " / " .. glyphNeon)
						T.check(pad.CanCollide == true, label .. ": the pad is walkable")
					else
						T.check(pad.Name == "Step" and pad.Size == Vector3.new(10, 0.3, 6), label .. ": no pad -> a 10 x 0.3 x 6 step")
						T.check(site:PointToObjectSpace(pad.Position).Z < -3, label .. ": the step lies in front")
					end
					-- prompt anchor
					local pl = site:PointToObjectSpace(prompt.Position)
					T.check(prompt.Transparency == 1 and prompt.CanCollide == false and abs(pl.X) < 1 and pl.Z < 0 and pl.Z > -4 and pl.Y > 1 and pl.Y < 5, label .. ": an invisible prompt anchor in the front of the opening", tostring(pl))
					-- the discs, the light, the sparkles
					local disc = model:FindFirstChild("PortalDisc", true)
					local shimmer = model:FindFirstChild("PortalShimmer", true)
					T.check(disc ~= nil and disc.Material == Enum.Material.Neon and abs(disc.Transparency - 0.35) < 1e-6, label .. ": a Neon disc at Transparency 0.35")
					T.check(shimmer ~= nil and shimmer.Material == Enum.Material.ForceField, label .. ": a ForceField shimmer disc")
					local lights, emitters = {}, {}
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("Light") or d:IsA("PointLight") then
							lights[#lights + 1] = d
						elseif d:IsA("ParticleEmitter") then
							emitters[#emitters + 1] = d
						end
					end
					T.check(#lights == 1 and lights[1]:IsA("PointLight") and lights[1].Range == 14 and abs(lights[1].Brightness - 1.2) < 1e-6 and lights[1].Shadows == false, label .. ": one PointLight (Range 14, Brightness 1.2, no shadows)", tostring(#lights))
					T.check(#emitters == 1 and emitters[1].Rate == 6, label .. ": one sparkle emitter (Rate 6)")
					-- the emblem: one per glyph, cloned, <= 30 parts, all Neon in the accent
					local emblem = model:FindFirstChild("Emblem")
					local rects = WS.GlyphRects(WS.Glyphs[spec.Glyph])
					if T.check(emblem ~= nil, label .. ": has the voxel emblem") then
						local cells = emblem:GetChildren()
						local allNeon = true
						for _, c in ipairs(cells) do
							allNeon = allNeon and c:IsA("BasePart") and c.Material == Enum.Material.Neon and c.Color == disc.Color
						end
						T.check(#cells == #rects and #cells <= 30 and allNeon, label .. ": the emblem = " .. #rects .. " Neon cells in the accent (<= 30)", tostring(#cells))
						-- 6 x 6 cells of 1 stud
						local ex0, ex1, ey0, ey1 = 1e9, -1e9, 1e9, -1e9
						for _, c in ipairs(cells) do
							local l = site:PointToObjectSpace(c.Position)
							ex0, ex1 = min(ex0, l.X - c.Size.X * 0.5), max(ex1, l.X + c.Size.X * 0.5)
							ey0, ey1 = min(ey0, l.Y - c.Size.Y * 0.5), max(ey1, l.Y + c.Size.Y * 0.5)
						end
						T.check(ex1 - ex0 <= 6.01 and ey1 - ey0 <= 6.01 and ey0 > 18.6, label .. ": the emblem fits 6 x 6 above the lintel", fmt(ex1 - ex0) .. " x " .. fmt(ey1 - ey0))
					end
					seenGlyph[spec.Glyph] = true
					-- the tag (World text rule), 27 studs up
					local tag = model:FindFirstChild("GateTag", true)
					pixelTagCheck(tag, label)
					if tag and tag.Adornee then
						local anchorY = tag.Adornee.Position.Y + tag.StudsOffsetWorldSpace.Y
						T.check(abs(anchorY - (site.Y + 27)) < 0.05, label .. ": the tag sits 27 studs up", fmt(anchorY - site.Y))
						local title = tag:FindFirstChild("Title", true)
						local info = tag:FindFirstChild("Info", true)
						local pill = tag:FindFirstChild("Pill", true)
						T.check(title and title.Text == spec.Title and title.TextSize == 28, label .. ": title " .. tostring(spec.Title) .. " at 28 px")
						T.check(info and info.Text == spec.Info and info.TextSize == 20, label .. ": info line at 20 px")
						local pillLabel = pill and pill:FindFirstChildOfClass("TextLabel")
						T.check(pill and pillLabel and pillLabel.TextSize == 18 and pill.Visible == ((spec.Pill or "") ~= ""), label .. ": the pill (18 px) shows only with text")
					end
					-- art rules on the gate
					styleAudit(model, WS, { label = label, maxShadowLights = 0 })
				end
			end
			local glyphCount = 0
			for _ in pairs(seenGlyph) do
				glyphCount = glyphCount + 1
			end
			T.eq(glyphCount, 6, "six different glyphs (house, cloud, torch, crown, swords, bolt)")

			-- determinism + the cached emblem: two builds of the same spec are identical relative to their sites
			local function signature(model, site)
				local rows = {}
				for _, p in ipairs(parts(model)) do
					local l = site:ToObjectSpace(p.CFrame)
					local function q(v)
						return floor(v * 1000 + 0.5) -- integer thousandths: no "-0.000"
					end
					rows[#rows + 1] = string.format("%s %d %d %d %d %d %d %s %d,%d,%d", p.Name, q(l.X), q(l.Y), q(l.Z), q(p.Size.X), q(p.Size.Y), q(p.Size.Z), tostring(p.Material), rgb255(p.Color))
				end
				table.sort(rows)
				return table.concat(rows, "\n")
			end
			local s1 = CFrame.new(3000, 600, 2000)
			local s2 = CFrame.new(3100, 650, 2100) * CFrame.Angles(0, 1.1, 0)
			local m1 = WS.BuildGate(folder, s1, specs[2])
			local m2 = WS.BuildGate(folder, s2, specs[2])
			local sig1, sig2 = signature(m1, s1), signature(m2, s2)
			local firstDiff = nil
			if sig1 ~= sig2 then
				local a, b = {}, {}
				for line in sig1:gmatch("[^\n]+") do
					a[#a + 1] = line
				end
				for line in sig2:gmatch("[^\n]+") do
					b[#b + 1] = line
				end
				for i = 1, max(#a, #b) do
					if a[i] ~= b[i] then
						firstDiff = tostring(a[i]) .. " vs " .. tostring(b[i])
						break
					end
				end
			end
			T.check(sig1 == sig2, "BuildGate is deterministic (the same gate at any site / yaw)", firstDiff)
			-- a tilted site still gives an upright gate facing the site's horizontal look
			local tilted = CFrame.new(3200, 600, 2000) * CFrame.Angles(0.3, 0.5, 0.2)
			local m3, pad3 = WS.BuildGate(folder, tilted, specs[2])
			local up = m3.PrimaryPart and m3.PrimaryPart.CFrame.UpVector
			T.check(up and up.Y > 0.999, "a tilted site -> the gate stands upright")
			local look = tilted.LookVector
			local flat = Vector3.new(look.X, 0, look.Z).Unit
			local toPad = (pad3.Position - Vector3.new(3200, pad3.Position.Y, 2000)).Unit
			T.check(toPad:Dot(flat) > 0.999, "the pad lies along the site's horizontal LookVector (the gate faces the plaza)")
			-- accents: a name, a Color3, junk
			local cm = WS.BuildGate(folder, CFrame.new(3300, 600, 2000), { Id = "T1", Title = "T", Color = Color3.fromRGB(10, 200, 30), Glyph = "bolt" })
			T.check(cm:FindFirstChild("PortalDisc", true).Color == Color3.fromRGB(10, 200, 30), "a Color3 accent colours the disc")
			local jm = WS.BuildGate(folder, CFrame.new(3400, 600, 2000), { Id = "T2", Glyph = "nope", Color = 5 })
			T.check(jm ~= nil and jm:GetAttribute("Glyph") == "cloud", "junk glyph / colour -> the cloud glyph in the default accent (no error)")
			-- the reference sample builds
			local sample = WS.Sample and WS.Sample(folder)
			T.check(sample ~= nil and #parts(sample) > 300, "WorldStyle.Sample builds (the renders' reference court)", sample and tostring(#parts(sample)) or "nil")
		end)
		T.check(ok, "p5world_style helper checks ran without errors", tostring(err))
		folder:Destroy()

		-- [W2 worldlobby] the lobby-wide pass: styleAudit(workspace.NimbusLobby) with the exempt tag on clouds / pets /
		-- tokens, every child of LobbyInfo.GatesFolder <= 120 parts with a pixel tag (pixelTagCheck), <= 12
		-- shadow-casting lights (the 8000 budget is p5world_lobby's)
		local lobbyInfo = K.W and K.W.lobbyInfo
		local lobby = workspace:FindFirstChild("NimbusLobby")
		if T.check(lobby ~= nil and type(lobbyInfo) == "table", "lobby style: the booted lobby exists") then
			-- the plots' stations (HomeBuilder, homeworld) and the Storm Altar island (its own look on purpose, 6.4) are
			-- audited by their owners: the pass covers the plaza, the courts, the gates, the shop, roads, gardens, plots
			local skip = {}
			for _, spot in ipairs(type(lobbyInfo.Spots) == "table" and lobbyInfo.Spots or {}) do
				local home = type(spot) == "table" and typeof(spot.Folder) == "Instance" and spot.Folder:FindFirstChild("Home")
				if home then
					skip[#skip + 1] = home
				end
			end
			for _, spot in ipairs(type(lobbyInfo.Spots) == "table" and lobbyInfo.Spots or {}) do
				if type(spot) == "table" and typeof(spot.Folder) == "Instance" then
					for _, d in ipairs(spot.Folder:GetDescendants()) do
						-- HomeBuilder's claim gate (homeworld audits its own models) and the podium pets (pets are exempt)
						if d:IsA("Model") and (d.Name == "ClaimGate" or d.Name == "ShowcasePet" or d:GetAttribute("PetId") ~= nil) then
							skip[#skip + 1] = d
						end
					end
				end
			end
			local altar = lobby:FindFirstChild("StormAltar", true)
			if altar then
				skip[#skip + 1] = altar
			end
			local holder = Instance.new("Folder")
			holder.Name = "LobbyStyleAudit"
			local moved = {}
			for _, m in ipairs(skip) do
				moved[#moved + 1] = { m, m.Parent }
			end
			-- audit everything except the skipped models: tag them exempt for the duration of the pass
			local CS = game:GetService("CollectionService")
			local exemptTag = (WS.Tags and WS.Tags.Exempt) or "NC_StyleExempt"
			local added = {}
			for _, m in ipairs(skip) do
				if not CS:HasTag(m, exemptTag) then
					CS:AddTag(m, exemptTag)
					added[#added + 1] = m
				end
			end
			local res = styleAudit(lobby, WS, { label = "lobby" })
			for _, m in ipairs(added) do
				CS:RemoveTag(m, exemptTag)
			end
			holder:Destroy()
			T.info("*lobby style: " .. tostring(res.parts) .. " parts audited, " .. tostring(res.shadowLights) .. " shadow lights")
			local gatesFolder = lobbyInfo.GatesFolder
			if T.check(typeof(gatesFolder) == "Instance" and gatesFolder.Parent == lobby, "lobby style: LobbyInfo.GatesFolder is NimbusLobby.Gates") then
				local n = 0
				for _, gate in ipairs(gatesFolder:GetChildren()) do
					n = n + 1
					local count = #parts(gate)
					T.check(count <= 120, "lobby style: " .. gate.Name .. " <= 120 parts (6.4 rule 8)", count .. " parts")
					pixelTagCheck(gate:FindFirstChild("GateTag", true), "lobby style: " .. gate.Name)
				end
				T.check(n >= 5, "lobby style: the Gate Court holds the five gates of W2 (the Dungeon gate joins in W3)", n .. " gates")
			end
		end
		_G.P5WorldStyleAudit = { styleAudit = styleAudit, pixelTagCheck = pixelTagCheck }
	end)

	-- [W2 worldlobby] S.p5world_lobby, S.p5world_gates, S.p5obby_levels, S.p5obby_migration, S.p5world_client_total
	local GATE_ORDER = { "Home", "Obby", "Dungeon", "Ring", "Arena", "Altar" }
	local function hdist(a, b)
		local dx, dz = a.X - b.X, a.Z - b.Z
		return math.sqrt(dx * dx + dz * dz)
	end
	local function angleOf(pos, origin)
		return math.deg(math.atan2(pos.Z - origin.Z, pos.X - origin.X)) % 360
	end
	local function groundAt(pos, depth)
		local params = RaycastParams.new()
		local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -(depth or 8) - 2, 0), params)
		return hit
	end
	-- stand a player at a point (feet on the ground below it)
	local function standAt(player, pos, look)
		local cf = look and CFrame.lookAt(pos + Vector3.new(0, 3, 0), look + Vector3.new(0, 3, 0)) or CFrame.new(pos + Vector3.new(0, 3, 0))
		Mock.Teleport(player, cf)
		K.advance(0.05)
	end

	------------------------------------------------------------------------------------------------
	-- p5world_lobby (6.1, 10.3): the Gate Court and the bigger plaza
	------------------------------------------------------------------------------------------------
	S.p5world_lobby = guarded("p5world_lobby", function()
		if not K.needBoot() then
			return
		end
		local Config = config()
		local info = K.W.lobbyInfo
		local L = Config.Lobby
		local origin = L.Origin
		local folder = info.Folder
		-- the six gate sites: on the arc (r GateArcRadius +- 1), 50..130 degrees, >= 26 studs apart, facing the centre,
		-- left -> right Home .. Altar (rising angle: the spawn looks +Z, lower angles are on the left)
		local sites = info.GateSites
		if T.check(type(sites) == "table", "LobbyInfo.GateSites is a table") then
			local last = -1
			for i, id in ipairs(GATE_ORDER) do
				local cf = sites[id]
				if T.check(typeof(cf) == "CFrame", "GateSites." .. id .. " is a CFrame") then
					local r = hdist(cf.Position, origin)
					local a = angleOf(cf.Position, origin)
					T.check(math.abs(r - L.GateArcRadius) <= 1, id .. ": on the gate arc (r " .. L.GateArcRadius .. ")", fmt(r, 2))
					T.check(a >= 50 and a <= 130, id .. ": within 50..130 degrees", fmt(a, 2))
					T.check(a > last, id .. ": the gates run left -> right " .. table.concat(GATE_ORDER, ", "), fmt(a, 2))
					last = a
					local toC = Vector3.new(origin.X - cf.Position.X, 0, origin.Z - cf.Position.Z).Unit
					T.check(cf.LookVector:Dot(toC) > 0.999, id .. ": the site looks at the plaza centre")
					T.check(math.abs(cf.Position.Y - origin.Y) < 0.01, id .. ": ground level")
					for j = 1, i - 1 do
						local other = sites[GATE_ORDER[j]]
						if typeof(other) == "CFrame" then
							T.check(hdist(other.Position, cf.Position) >= 26, id .. ": >= 26 studs from " .. GATE_ORDER[j], fmt(hdist(other.Position, cf.Position), 1))
						end
					end
				end
			end
			T.check(info.RingSite == sites.Ring and info.DungeonSite == sites.Dungeon, "LobbyInfo.RingSite / DungeonSite = GateSites.Ring / .Dungeon")
		end
		T.check(info.TrialSite == nil, "LobbyInfo.TrialSite is gone")
		-- the folder of the six gates
		local gf = info.GatesFolder
		T.check(typeof(gf) == "Instance" and gf:IsA("Folder") and gf.Name == "Gates" and gf.Parent == folder, "LobbyInfo.GatesFolder = workspace.NimbusLobby.Gates")
		if typeof(gf) == "Instance" then
			for _, id in ipairs({ "Home", "Obby", "Ring", "Arena", "Altar" }) do
				local m = gf:FindFirstChild("Portal_" .. id)
				if T.check(m ~= nil and m:IsA("Model"), "Portal_" .. id .. " stands in the Gates folder") and typeof(sites[id]) == "CFrame" then
					T.check(hdist(m:GetPivot().Position, sites[id].Position) < 1.5, "Portal_" .. id .. " stands on its site")
				end
			end
			-- W3: the Dungeon gate; until then its site is free ground of the court
			if typeof(sites.Dungeon) == "CFrame" and not gf:FindFirstChild("Portal_Dungeon") then
				local hit = groundAt(sites.Dungeon.Position, 6)
				T.check(hit ~= nil, "the reserved Dungeon site is paved court ground (DungeonBuilder builds its gate there in W3)")
			end
		end
		for _, id in ipairs({ "Home", "Obby", "Altar" }) do
			local g = type(info.Gates) == "table" and info.Gates[id]
			T.check(type(g) == "table" and typeof(g.Model) == "Instance" and typeof(g.Pad) == "Instance" and typeof(g.PromptPart) == "Instance", "LobbyInfo.Gates." .. id .. " = { Model, Pad, PromptPart }")
		end
		-- Portals = exactly Obby; no per-difficulty portal and no Trial portal anywhere
		local n = 0
		for _ in pairs(info.Portals or {}) do
			n = n + 1
		end
		T.check(n == 1 and type(info.Portals.Obby) == "table" and typeof(info.Portals.Obby.PromptPart) == "Instance", "LobbyInfo.Portals = { Obby = PortalInfo + PromptPart }", n .. " portals")
		local stale = {}
		for _, name in ipairs({ "Portal_Easy", "Portal_Medium", "Portal_Hard", "Portal_Extreme", "Portal_Saint", "Portal_Trials" }) do
			if workspace:FindFirstChild(name, true) then
				stale[#stale + 1] = name
			end
		end
		T.check(#stale == 0, "no Portal_Easy..Saint / Portal_Trials left in the world", table.concat(stale, ", "))
		-- the plaza: 1.8x the Phase 4 area (PlazaRadius 150): the walkable ground reaches r 150 in every lawn direction
		local reach = T.tally("the plaza ground reaches r " .. L.PlazaRadius .. " (1.8x the Phase 4 area)")
		for a = 0, 330, 30 do
			local p = origin + Vector3.new(math.cos(math.rad(a)) * (L.PlazaRadius - 2), 0, math.sin(math.rad(a)) * (L.PlazaRadius - 2))
			reach:case(groundAt(p, 3) ~= nil, "angle " .. a)
		end
		reach:report()
		-- 16 spots on r 340 +- 30
		local ring = T.tally("16 spots on r " .. L.SpotRingRadius .. " +- 30")
		local nSpots = 0
		for i, sp in ipairs(info.Spots or {}) do
			nSpots = nSpots + 1
			ring:case(math.abs(hdist(sp.Center, origin) - L.SpotRingRadius) <= 30, "spot " .. i .. " r " .. fmt(hdist(sp.Center, origin), 1))
		end
		ring:report()
		T.eq(nSpots, L.SpotCount, "LobbyInfo.Spots holds SpotCount spots")
		-- the spawn looks at the Gate Court
		local face = Vector3.new(math.cos(math.rad(L.GateFacing)), 0, math.sin(math.rad(L.GateFacing)))
		T.check(info.SpawnCFrame.LookVector:Dot(face) > 0.99 and hdist(info.SpawnCFrame.Position, origin) < 2, "the spawn stands on the medallion looking at the Gate Court (GateFacing)")
		-- gardens / altar between the plaza and the street; the shop beyond the plaza
		local streetIn = L.SpotRingRadius - L.PlotSize / 2 - 4 - 14
		local gardens = folder:FindFirstChild("Gardens")
		local gTally = T.tally("the gardens float between the plaza and the street")
		for _, g in ipairs(gardens and gardens:GetChildren() or {}) do
			local sum, cnt = Vector3.new(0, 0, 0), 0
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("BasePart") then
					sum = sum + d.Position
					cnt = cnt + 1
				end
			end
			if cnt > 0 then
				local r = hdist(sum / cnt, origin)
				gTally:case(r > L.PlazaRadius + 8 and r < streetIn - 8, g.Name .. " r " .. fmt(r, 1))
			end
		end
		gTally:report()
		if typeof(info.AltarSite) == "CFrame" then
			local r = hdist(info.AltarSite.Position, origin)
			T.check(r > L.PlazaRadius + 8 and r < streetIn - 8, "the Storm Altar site lies between the plaza and the street", fmt(r, 1))
		end
		T.check(L.ShopOffset.Magnitude > L.PlazaRadius + 30, "the shop island lies beyond the plaza")
		-- NPC spots: on lawn, no path within 8 studs, >= 10 studs from every gate pad
		local pads = {}
		for _, id in ipairs({ "Home", "Obby", "Altar" }) do
			local g = info.Gates and info.Gates[id]
			if g and typeof(g.Pad) == "Instance" then
				pads[#pads + 1] = g.Pad.Position
			end
		end
		local npc = T.tally("every NPC spot stands on lawn, >= 8 studs from any path and >= 10 from every gate pad")
		for i, cf in ipairs(info.NpcSpots or {}) do
			local okSpot, why = true, ""
			local r = hdist(cf.Position, origin)
			if r < 62 - 1 or r > 80 + 9 then
				okSpot, why = false, "r " .. fmt(r, 1)
			end
			for k = 0, 7 do
				local a = k * math.pi / 4
				for _, rad in ipairs({ 0, 4, 8 }) do
					local hit = groundAt(cf.Position + Vector3.new(math.cos(a) * rad, 0.5, math.sin(a) * rad), 3)
					if hit and hit.Instance and hit.Instance.Material ~= Enum.Material.Grass and hit.Instance.Material ~= Enum.Material.LeafyGrass then
						okSpot, why = false, hit.Instance:GetFullName() .. " (" .. tostring(hit.Instance.Material) .. ") within " .. rad .. " studs"
					end
				end
			end
			for _, pp in ipairs(pads) do
				if hdist(pp, cf.Position) < 10 then
					okSpot, why = false, "a gate pad within 10 studs"
				end
			end
			npc:case(okSpot, "NPC spot " .. i .. ": " .. why)
		end
		npc:report()
		-- the budget: the lobby with every gate (the Storm Altar's island has its own 500 and the plots' homes theirs)
		local count = 0
		local altar = folder:FindFirstChild("StormAltar", true)
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") and not (altar and d:IsDescendantOf(altar)) then
				-- the homes, HomeBuilder's claim gates and the podium pets have their own budgets
				local home = false
				local cur = d.Parent
				while cur and cur ~= folder do
					if cur.Name == "Home" or cur.Name == "ClaimGate" or cur.Name == "ShowcasePet" or (cur:IsA("Model") and cur:GetAttribute("PetId") ~= nil) then
						home = true
						break
					end
					cur = cur.Parent
				end
				if not home then
					count = count + 1
				end
			end
		end
		T.check(count <= 8000, "the lobby (the plaza, the courts, every gate, the shop, roads, gardens and the plot islands) stays <= 8000 parts (10.3)", count .. " parts")
		T.info("*p5 lobby: " .. count .. " parts (the Storm Altar island and the homes not counted)")
		local pc = folder:GetAttribute("PartCount")
		T.check(type(pc) == "number" and pc > 2000, "NimbusLobby.PartCount is written (Main, after the last gate builder)", tostring(pc))
		-- the arena island stays clear of the plots
		local AB = M["server/Services/ArenaBuilder"]
		if AB and type(AB.InArena) == "function" then
			local hits = 0
			for _, sp in ipairs(info.Spots or {}) do
				if AB.InArena(sp.Center) then
					hits = hits + 1
				end
			end
			T.eq(hits, 0, "the arena island is clear of every plot")
		end
		K.flushErrors("p5world_lobby")
	end)

	------------------------------------------------------------------------------------------------
	-- p5world_gates (6.2, Y12): GateService's Home / Altar prompts, Portal_Arena and the Return gate
	------------------------------------------------------------------------------------------------
	S.p5world_gates = guarded("p5world_gates", function()
		if not K.needBoot() then
			return
		end
		local GS = M["server/Services/GateService"]
		if not T.check(type(GS) == "table" and type(GS.Init) == "function" and type(GS.Use) == "function" and GS.Teleported ~= nil, "GateService is loaded (Init, Use, Teleported)") then
			return
		end
		local info = K.W.lobbyInfo
		local SpotService = K.mod("SpotService")
		local fired = {}
		local conn = GS.Teleported:Connect(function(player, id)
			fired[#fired + 1] = { player, id }
		end)
		local function prompt(id)
			local g = info.Gates and info.Gates[id]
			local part = g and g.PromptPart
			return part and part:FindFirstChild(id .. "GatePrompt"), part
		end
		for _, id in ipairs({ "Home", "Altar" }) do
			local pr = prompt(id)
			if T.check(pr ~= nil and pr:IsA("ProximityPrompt"), id .. "GatePrompt sits on LobbyInfo.Gates." .. id .. ".PromptPart") then
				T.eq(pr.MaxActivationDistance, 12, id .. "GatePrompt: MaxActivationDistance 12")
				T.eq(pr.HoldDuration, 0, id .. "GatePrompt: HoldDuration 0")
			end
		end
		local hp = prompt("Home")
		local ap = prompt("Altar")
		T.check(hp and hp.ActionText == "Go home" and hp.ObjectText == "My Home", "HomeGatePrompt: 'Go home' / 'My Home'")
		T.check(ap and ap.ActionText == "Travel" and ap.ObjectText == "Storm Altar", "AltarGatePrompt: 'Travel' / 'Storm Altar'")
		local players = K.freshPlayers(2, "Gate")
		local a, b = players[1], players[2]
		local function atGate(p, id)
			local site = info.GateSites[id]
			standAt(p, site.Position + site.LookVector * 5, site.Position)
		end
		-- Home without a plot: the gate of a free plot + the claim toast
		atGate(a, "Home")
		local mark = K.logSize()
		local n0 = #fired
		Mock.Trigger(hp, a)
		K.advance(0.3)
		local pos = K.root(a).Position
		local nearFree = false
		for _, sp in ipairs(info.Spots) do
			if SpotService.GetOwner(sp.Index) == nil and typeof(sp.GateCFrame) == "CFrame" and hdist(pos, sp.GateCFrame.Position) < 16 then
				nearFree = true
			end
		end
		T.check(nearFree, "Home without a plot: the player stands at the gate of a free plot", "at " .. tostring(pos))
		T.check(K.notified(a, "claim this home", "info", mark), "...with 'Press E at the gate to claim this home!'")
		T.check(#fired == n0 + 1 and fired[#fired][1] == a and fired[#fired][2] == "Home", "GateService.Teleported fires once (player, \"Home\")")
		-- Home with a plot
		K.advance(1.6)
		local claimed = nil
		for _, sp in ipairs(info.Spots) do
			if not claimed and SpotService.GetOwner(sp.Index) == nil then
				local ok = SpotService.Claim(a, sp.Index)
				if ok then
					claimed = sp
				end
			end
		end
		if T.check(claimed ~= nil, "precondition: the player claims a plot") then
			atGate(a, "Home")
			Mock.Trigger(hp, a)
			K.advance(0.3)
			T.check(hdist(K.root(a).Position, claimed.SpawnCFrame.Position) < 8, "Home with a plot: the player lands at home", fmt(hdist(K.root(a).Position, claimed.SpawnCFrame.Position), 1))
		end
		-- refusals: in a match, in a battle, locked on the obby pad, far away, cooldown
		K.advance(1.6)
		atGate(b, "Home")
		b:SetAttribute("InMatch", true)
		local ok, why = GS.Use(b, "Home")
		T.check(not ok and why == "match", "refused in a match", tostring(why))
		b:SetAttribute("InMatch", nil)
		b:SetAttribute("InBattle", "B1")
		mark = K.logSize()
		ok, why = GS.Use(b, "Home")
		T.check(not ok and why == "battle", "refused in a battle", tostring(why))
		b:SetAttribute("InBattle", nil)
		K.enterPortal(b)
		K.advance(0.6)
		ok, why = GS.Use(b, "Home")
		T.check(not ok and why == "locked", "refused while locked on the obby pad (PortalService.IsLocked)", tostring(why))
		K.mod("PortalService").RemovePlayer(b)
		K.leavePortalArea(b)
		K.advance(0.4)
		standAt(b, info.SpawnCFrame.Position)
		ok, why = GS.Use(b, "Home")
		T.check(not ok and why == "far", "refused from far away (> 12 + 4 studs)", tostring(why))
		atGate(b, "Altar")
		local n1 = #fired
		ok, why = GS.Use(b, "Altar")
		T.check(ok == true, "the Altar gate accepts a player at the gate", tostring(why))
		local SA = M["server/Services/StormAltar"]
		local landing = SA and SA.GetLanding and SA.GetLanding()
		if T.check(typeof(landing) == "CFrame", "StormAltar.GetLanding() is a CFrame") then
			T.check((K.root(b).Position - landing.Position).Magnitude < 6 and groundAt(K.root(b).Position, 8) ~= nil, "Altar: the player lands within 6 studs of GetLanding(), on the island deck")
			local altarCF = SA.GetCFrame()
			local toAltar = Vector3.new(altarCF.Position.X - landing.Position.X, 0, altarCF.Position.Z - landing.Position.Z).Unit
			T.check(landing.LookVector:Dot(toAltar) > 0.95, "GetLanding faces the altar")
		end
		T.check(#fired == n1 + 1 and fired[#fired][2] == "Altar", "Teleported fires once (player, \"Altar\")")
		atGate(b, "Altar")
		ok, why = GS.Use(b, "Altar")
		T.check(not ok and why == "cooldown", "a second use inside 1.5 s is refused (cooldown)", tostring(why))
		T.check(#fired == n1 + 1, "...and fires nothing")
		local junkOk = pcall(GS.Use, "x", "Home") and pcall(GS.Use, b, "Nope") and pcall(GS.Use, nil, nil)
		T.check(junkOk and select(1, GS.Use(b, "Nope")) == false, "junk players / gate ids are refused without errors")
		-- Portal_Arena -> ArenaInfo.Spawn; the forum's Return gate -> in front of Portal_Arena
		local AB = M["server/Services/ArenaBuilder"]
		local ainfo = AB and AB.GetInfo and AB.GetInfo()
		local arenaGate = info.GatesFolder:FindFirstChild("Portal_Arena")
		local ap2 = arenaGate and arenaGate:FindFirstChild("ArenaPortalPrompt", true)
		if T.check(ainfo ~= nil and ap2 ~= nil, "Portal_Arena carries ArenaPortalPrompt") then
			K.advance(2.2)
			atGate(b, "Arena")
			Mock.Trigger(ap2, b)
			K.advance(0.3)
			T.check(hdist(K.root(b).Position, ainfo.Spawn.Position) < 8, "Portal_Arena: E lands on the arena's Spawn")
			local ret = ainfo.Model:FindFirstChild("ArenaReturnPrompt", true)
			if T.check(ret ~= nil, "the forum's Return gate carries ArenaReturnPrompt") then
				K.advance(2.2)
				local rp = ret.Parent
				standAt(b, rp.Position + Vector3.new(0, -3, 0) + (rp.CFrame.LookVector * 4))
				Mock.Trigger(ret, b)
				K.advance(0.3)
				T.check(hdist(K.root(b).Position, ainfo.LobbyCFrame.Position) < 8, "the Return gate lands in front of Portal_Arena (ArenaInfo.LobbyCFrame)")
			end
		end
		conn:Disconnect()
		SpotService.Release(a)
		K.removePlayers(players)
		K.flushErrors("p5world_gates")
	end)

	------------------------------------------------------------------------------------------------
	-- p5obby_levels (6.3, Y10): ObbyLevels, ObbyPick, the party level
	------------------------------------------------------------------------------------------------
	S.p5obby_levels = guarded("p5obby_levels", function()
		local OL = M["shared/ObbyLevels"]
		local Config = config()
		if not T.check(type(OL) == "table", "shared/ObbyLevels is loaded") then
			return
		end
		-- the HighestUnlocked table (pure)
		local cases = {
			{ {}, 1 }, { { Easy = 100 }, 2 }, { { Medium = 90 }, 3 }, { { Easy = 100, Medium = 90 }, 3 },
			{ { Extreme = 300 }, 5 }, { { Saint = 500 }, 5 }, { { Hard = 0 }, 1 }, { { Hard = -5 }, 1 }, { { Hard = "x" }, 1 },
			{ { Hard = 0 / 0 }, 1 }, { "junk", 1 },
		}
		for i, c in ipairs(cases) do
			T.eq(OL.HighestUnlocked(c[1]), c[2], "HighestUnlocked case " .. i)
		end
		T.check(OL.IsUnlocked({ Medium = 90 }, "Hard") and not OL.IsUnlocked({ Medium = 90 }, "Extreme") and not OL.IsUnlocked({}, "Nope"), "IsUnlocked follows HighestUnlocked")
		if not K.needBoot() then
			return
		end
		local PS = K.mod("PortalService")
		local DS = K.mod("DataService")
		T.check(type(PS.PickLevel) == "function", "PortalService.PickLevel exists")
		local players = K.freshPlayers(2, "Lvl")
		local a, b = players[1], players[2]
		K.advance(0.5)
		local remote = K.remoteFolder().ObbyPick
		T.check(remote ~= nil, "the ObbyPick remote exists")
		local attr = Config.Attr.ObbyLevel
		-- refusals leave the attribute alone
		local mark = K.logSize()
		for _, junk in ipairs({ 5, {}, "", string.rep("E", 17), "Nope", "Hard" }) do
			Mock.FromClient(remote, a, junk)
			K.advance(0.3)
		end
		T.eq(a:GetAttribute(attr), nil, "junk / unknown / locked picks leave ObbyLevel unset")
		T.check(K.notified(a, "Beat Medium to unlock Hard", "bad", mark), "a locked pick answers 'Beat Medium to unlock Hard'")
		local okJ, whyJ = PS.PickLevel(a, "Nope")
		T.check(okJ == false and whyJ == "junk", "an unknown level is dropped silently (junk)")
		-- the rate limit: 4/s burst 4
		K.advance(1.5)
		local accepted = 0
		for _ = 1, 8 do
			local okR = PS.PickLevel(a, "Easy")
			if okR then
				accepted = accepted + 1
			end
		end
		T.check(accepted == 4, "ObbyPick: burst 4 (4/s)", accepted .. " of 8 accepted")
		K.advance(1.5)
		-- a win unlocks the next level; the accepted pick sets the attribute
		DS.RecordMatch(a, "Medium", true, 200)
		local okP = PS.PickLevel(a, "Hard")
		T.check(okP == true and a:GetAttribute(attr) == "Hard", "after beating Medium, ObbyPick('Hard') sets ObbyLevel = Hard")
		-- first on the pad -> the party level
		K.enterPortal(a)
		K.advance(0.6)
		local party = PS.GetParty("Obby")
		T.eq(party.Level, "Hard", "the first player on the pad starts a Hard party (their pick)")
		T.eq(K.W.lobbyInfo.Portals.Obby.Model:GetAttribute("PartyLevel"), "Hard", "Portal_Obby PartyLevel = Hard")
		-- a joiner without the unlock joins the Hard party
		K.enterPortal(b)
		K.advance(0.6)
		T.eq(#PS.GetParty("Obby").Players, 2, "a joiner without the unlock joins whatever the level")
		-- PartyState fields
		local st = K.lastRemote("PartyState", b.UserId)
		st = st and st.args[1]
		T.check(type(st) == "table" and st.Level == "Hard" and st.Stars == Config.GetDifficulty("Hard").Stars and st.LeaderUserId == a.UserId and st.PortalId == "Obby", "PartyState: Level / Stars / LeaderUserId / PortalId")
		-- a member's pick does not move the party; the leader's re-pick does (+ 8 s, a toast to the members)
		DS.RecordMatch(b, "Easy", true, 100)
		K.advance(0.6)
		PS.PickLevel(b, "Medium")
		T.eq(PS.GetParty("Obby").Level, "Hard", "a member's pick leaves the party level alone")
		T.eq(b:GetAttribute(attr), "Medium", "...but sets the member's own ObbyLevel")
		mark = K.logSize()
		K.advance(0.3)
		local before = PS.GetParty("Obby").Countdown
		PS.PickLevel(a, "Medium")
		local after = PS.GetParty("Obby")
		T.eq(after.Level, "Medium", "the leader's re-pick changes the party level")
		T.check(after.Countdown ~= nil and after.Countdown >= 8, "...and leaves at least 8 s on the countdown", tostring(before) .. " -> " .. tostring(after.Countdown))
		T.check(K.notified(b, "Level: Medium", "info", mark), "...and tells the members 'Level: Medium'")
		-- launch: StartMatch(level)
		PS.PickLevel(a, "Hard")
		local started = K.waitFor(function()
			return K.MS().GetMatchOf(a) ~= nil
		end, Config.Match.PartyCountdown + 12)
		T.check(started, "the party launches")
		if started then
			T.eq(K.MS().GetMatchOf(a).DifficultyId, "Hard", "launch: StartMatch(\"Hard\", players)")
		end
		K.endAllMatches(players)
		-- unlock after a win
		T.eq(OL.HighestUnlocked(DS.GetProfile(a).Stats.BestTimes), 3, "before a Hard win: Hard is the top")
		DS.RecordMatch(a, "Hard", true, 300)
		T.eq(OL.HighestUnlocked(DS.GetProfile(a).Stats.BestTimes), 4, "a Hard win unlocks Extreme")
		K.advance(1.5)
		T.check(PS.PickLevel(a, "Extreme") == true, "...and ObbyPick('Extreme') is accepted")
		K.removePlayers(players)
		K.flushErrors("p5obby_levels")
	end)

	------------------------------------------------------------------------------------------------
	-- p5obby_migration (6.3): Phase 4 saves keep every win; no migration step
	------------------------------------------------------------------------------------------------
	S.p5obby_migration = guarded("p5obby_migration", function()
		if not K.needBoot() then
			return
		end
		local Config = config()
		local PS = K.mod("PortalService")
		local DS = K.mod("DataService")
		local key = function(uid)
			return Config.Tokens.DataStoreName .. "/u_" .. uid
		end
		local fixtures = {
			{ 812001, { Easy = 120, Medium = 210 }, 3, "Hard" },
			{ 812002, { Extreme = 400 }, 5, "Saint" },
			{ 812003, {}, 1, "Easy" },
		}
		for _, f in ipairs(fixtures) do
			local uid, bt, top, expect = f[1], f[2], f[3], f[4]
			-- a Phase 4 record: a fresh save without the Phase 5 fields, with these best times
			local p = Mock.AddPlayer("Old" .. uid, uid)
			K.advance(1.0)
			K.removePlayers({ p })
			K.advance(3)
			local rec = Mock.DataStore.Data[key(uid)]
			if T.check(type(rec) == "table" and type(rec.Stats) == "table", uid .. ": the save exists") then
				rec.Stats.BestTimes = {}
				for k, v in pairs(bt) do
					rec.Stats.BestTimes[k] = v
				end
				rec.Dungeon, rec.Berries, rec.Settings = nil, nil, nil
				if type(rec.Migrations) == "table" then
					for k in pairs(rec.Migrations) do
						if tostring(k):sub(1, 2) == "P5" then
							rec.Migrations[k] = nil
						end
					end
				end
			end
			p = Mock.AddPlayer("Old" .. uid, uid)
			K.advance(1.0)
			local prof = DS.GetProfile(p)
			T.check(prof ~= nil, uid .. ": the Phase 4 save loads")
			if prof then
				local OL = M["shared/ObbyLevels"]
				T.eq(OL.HighestUnlocked(prof.Stats.BestTimes), top, uid .. ": the highest unlocked level is " .. expect)
				K.enterPortal(p)
				K.advance(0.6)
				T.eq(PS.GetParty("Obby").Level, expect, uid .. ": the first party on the pad climbs " .. expect)
				PS.RemovePlayer(p)
				K.leavePortalArea(p)
				K.advance(3.5)
			end
			K.removePlayers({ p })
			K.advance(3)
			local back = Mock.DataStore.Data[key(uid)]
			local same = type(back) == "table" and type(back.Stats) == "table"
			for k, v in pairs(bt) do
				same = same and back.Stats.BestTimes[k] == v
			end
			for k in pairs(same and back.Stats.BestTimes or {}) do
				same = same and bt[k] ~= nil
			end
			T.check(same, uid .. ": the best times round-trip unchanged (the record is the unlock)")
		end
		K.flushErrors("p5obby_migration")
	end)

	------------------------------------------------------------------------------------------------
	-- p5world_client_total (10.3): every client holds everything (streaming off)
	------------------------------------------------------------------------------------------------
	S.p5world_client_total = guarded("p5world_client_total", function()
		if not K.needBoot() then
			return
		end
		local function count(root)
			return root and #parts(root) or 0
		end
		local lobby = workspace:FindFirstChild("NimbusLobby")
		local npcs = workspace:FindFirstChild("NimbusNpcs")
		local arena = workspace:FindFirstChild("BattleArena")
		local AB = M["server/Services/ArenaBuilder"]
		local pockets = 0
		if AB and type(AB.BuildPocket) == "function" then
			for _, i in ipairs({ 63, 64 }) do
				local pk = AB.BuildPocket(i, "Ring")
				pockets = pockets + (pk and count(pk.Model) or 0)
				AB.FreePocket(i)
			end
		end
		-- 16 Sky Castle plots and 8 dungeon runs as their budgets (stand-ins until the W3 gate builds real ones)
		local plots = 16 * 950
		local runs = 8 * 950
		local course = 0
		for _, f in ipairs(K.courseFolders and K.courseFolders() or {}) do
			course = math.max(course, count(f))
		end
		local lobbyN, npcN, arenaN = count(lobby), count(npcs), count(arena)
		local total = lobbyN + npcN + arenaN + plots + runs + pockets + course
		T.info(string.format("*client total: lobby %d + NPCs %d + arena %d + 16 plots %d + 8 runs %d + 2 pockets %d + an obby course %d = %d", lobbyN, npcN, arenaN, plots, runs, pockets, course, total))
		T.check(total <= 45000, "the client holds <= 45,000 BaseParts in the worst case (10.3)", total .. " parts")
		K.flushErrors("p5world_client_total")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client world
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Lighting = game:GetService("Lighting")

	-- the replicated Lighting children the server's LightingService made (the client world starts bare)
	local function ensure(parent, className, props)
		local inst = parent:FindFirstChildOfClass(className)
		if not inst then
			inst = Instance.new(className)
			inst.Parent = parent
		end
		for k, v in pairs(props or {}) do
			inst[k] = v
		end
		return inst
	end

	S.client_p5lightingstack = guarded("client_p5lightingstack", function()
		local inst = Mock.GetPath(ROOTS["client"] .. "/LightingStack")
		if not T.check(inst ~= nil, "client/LightingStack exists") then
			return
		end
		local LSt = require(inst)
		for _, f in ipairs({ "Push", "Pop", "Top" }) do
			T.check(type(LSt[f]) == "function", "LightingStack." .. f .. " is a function")
		end
		-- the fallback look as replicated
		Lighting.Brightness = 2.6
		Lighting.ClockTime = 16.6
		Lighting.ExposureCompensation = 0.1
		Lighting.Ambient = Color3.fromRGB(118, 104, 140)
		local atm = ensure(Lighting, "Atmosphere", { Density = 0.36, Color = Color3.fromRGB(220, 176, 232) })
		local bloom = ensure(Lighting, "BloomEffect", { Enabled = true, Intensity = 0.25, Size = 24, Threshold = 1.35 })
		local rays = ensure(Lighting, "SunRaysEffect", { Enabled = true, Intensity = 0.06 })
		local cc = ensure(Lighting, "ColorCorrectionEffect", { Saturation = 0.06, Contrast = 0.12 })
		local clouds = workspace.Terrain and ensure(workspace.Terrain, "Clouds", { Cover = 0.62, Density = 0.7 })
		local outputBefore = #Mock.Output
		local ok, err = pcall(function()
			T.eq(LSt.Top(), nil, "an empty stack: Top() = nil")
			-- Push A, Push B, Pop A -> B applied
			LSt.Push("A", { Lighting = { Brightness = 1, ClockTime = 20 }, Atmosphere = { Density = 0.6 } }, 0)
			T.check(Lighting.Brightness == 1 and Lighting.ClockTime == 20 and atm.Density == 0.6, "Push A (0 s) applies at once")
			T.eq(LSt.Top(), "A", "Top() = A")
			LSt.Push("B", { Lighting = { Brightness = 0.5 }, ColorCorrection = { Saturation = -0.3 } }, 0)
			T.check(Lighting.Brightness == 0.5 and Lighting.ClockTime == 20 and cc.Saturation == -0.3, "Push B: B's Brightness wins, A's ClockTime stays")
			T.eq(LSt.Top(), "B", "Top() = B")
			LSt.Pop("A", 0)
			T.check(Lighting.Brightness == 0.5 and cc.Saturation == -0.3, "Pop A -> B still applied")
			T.check(Lighting.ClockTime == 16.6 and atm.Density == 0.36, "Pop A -> A's own properties back to the base", tostring(Lighting.ClockTime) .. " " .. tostring(atm.Density))
			T.eq(LSt.Top(), "B", "Top() = B after popping A")
			LSt.Pop("B", 0)
			T.check(Lighting.Brightness == 2.6 and Lighting.ClockTime == 16.6 and atm.Density == 0.36 and cc.Saturation == 0.06, "Pop B -> the base exactly")
			T.eq(LSt.Top(), nil, "Top() = nil again")
			-- unknown id: no-op
			LSt.Pop("nope", 1)
			T.check(Lighting.Brightness == 2.6, "Pop of an unknown id is a no-op")
			-- tweens: a 1 s push reaches its goal; a later Push cancels the running tween
			LSt.Push("T", { Lighting = { Brightness = 1, Ambient = Color3.fromRGB(20, 20, 40) } }, 1)
			T.check(Lighting.Brightness == 2.6, "a tweened Push does not jump (still the base right after)", tostring(Lighting.Brightness))
			KC.advance(1.3)
			T.check(Lighting.Brightness == 1 and sameColor(Lighting.Ambient, 20, 20, 40), "the tween reaches the preset (numbers and Color3)", tostring(Lighting.Brightness))
			LSt.Pop("T", 1)
			KC.advance(0.3)
			LSt.Push("T2", { Lighting = { ExposureCompensation = -0.5 } }, 0) -- cancels T's restore tween, sets the base at once
			KC.advance(1.5)
			T.check(Lighting.Brightness == 2.6 and sameColor(Lighting.Ambient, 118, 104, 140) and Lighting.ExposureCompensation == -0.5, "a Push during a running tween cancels it (no late jump back)", tostring(Lighting.Brightness))
			LSt.Pop("T2", 0)
			T.eq(Lighting.ExposureCompensation, 0.1, "Pop T2 -> ExposureCompensation base")
			-- re-push moves to the top
			LSt.Push("X", { Lighting = { Brightness = 1 } }, 0)
			LSt.Push("Y", { Lighting = { Brightness = 2 } }, 0)
			LSt.Push("X", { Lighting = { Brightness = 1.5 } }, 0)
			T.check(LSt.Top() == "X" and Lighting.Brightness == 1.5, "re-pushing X moves it to the top with its new preset")
			LSt.Pop("X", 0)
			T.eq(Lighting.Brightness, 2, "Pop X -> Y")
			LSt.Pop("Y", 0)
			T.eq(Lighting.Brightness, 2.6, "Pop Y -> base")
			-- GfxLow + Dungeon (the two real users)
			LSt.Push("GfxLow", { Bloom = { Enabled = false }, SunRays = { Enabled = false }, Clouds = { Density = 0.4 } }, 0)
			LSt.Push("Dungeon", { Lighting = { Brightness = 0.8, ClockTime = 0 }, Bloom = { Intensity = 0.6 }, Atmosphere = { Density = 0.5 } }, 1.5)
			KC.advance(1.7)
			T.check(bloom.Enabled == false and bloom.Intensity == 0.6 and Lighting.Brightness == 0.8 and Lighting.ClockTime == 0, "GfxLow + Dungeon: both presets apply (Bloom off, the dungeon's darkness)")
			T.check(rays.Enabled == false and (clouds == nil or clouds.Density == 0.4), "GfxLow: SunRays off, Clouds Density 0.4")
			LSt.Pop("Dungeon", 1.5)
			KC.advance(1.7)
			T.check(bloom.Enabled == false and bloom.Intensity == 0.25 and Lighting.Brightness == 2.6 and Lighting.ClockTime == 16.6 and atm.Density == 0.36, "Pop Dungeon -> GfxLow stays (Bloom off), the rest back to the base")
			LSt.Pop("GfxLow", 0)
			T.check(bloom.Enabled == true and rays.Enabled == true and (clouds == nil or clouds.Density == 0.7), "Pop GfxLow -> Bloom, SunRays and the clouds back")
			T.eq(LSt.Top(), nil, "the stack is empty at the end")
			-- junk: no error, nothing changes
			LSt.Push(nil, {})
			LSt.Push("J", "nope")
			LSt.Push("J2", { Nonsense = { Foo = 1 } }, 0)
			LSt.Pop("J2", 0)
			T.check(Lighting.Brightness == 2.6, "junk pushes change nothing")
		end)
		T.check(ok, "client_p5lightingstack ran without errors", tostring(err))
		-- the junk pushes above warn once each on purpose: drop those lines so the client's warning check stays clean
		for i = #Mock.Output, outputBefore + 1, -1 do
			local o = Mock.Output[i]
			if o.kind == "warn" and o.text:find("[LightingStack]", 1, true) then
				table.remove(Mock.Output, i)
			end
		end
	end)

	-- [W4 dungeonclient] client_p5obby: the ONE obby portal's level picker (ObbyController, contract 6.3): five cards with
	-- locks from Stats.BestTimes (ObbyLevels), ObbyPick only for an open level (optimistic PICKED, the ObbyLevel attribute
	-- wins), the gate's party footer, a member cannot pick, the leader's CHANGE chip opens it (HudController.
	-- _onChangeLevel), the ObbyPrompt opens it, stepping onto the pad / walking 40 studs away closes it, the unlock toast
	-- after a won match, docked right / a bottom sheet.
	S.client_p5obby = guarded("client_p5obby", function()
		local LP = game:GetService("Players").LocalPlayer
		local RS = game:GetService("ReplicatedStorage")
		local function req(key)
			local inst = Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", ""))
			local ok, mod = pcall(require, inst)
			return ok and type(mod) == "table" and mod or nil
		end
		local pg = LP:FindFirstChild("PlayerGui") or LP:WaitForChild("PlayerGui")
		if not RS:FindFirstChild("Remotes") or not pg:FindFirstChild("NimbusMenu") then
			if not RS:FindFirstChild("Remotes") then
				local Config = req("shared/Config")
				local folder = Instance.new("Folder")
				folder.Name = "Remotes"
				for _, n in ipairs(Config.Remotes) do
					local r = Instance.new("RemoteEvent")
					r.Name = n
					r.Parent = folder
				end
				folder.Parent = RS
			end
			Mock.RunScript(Mock.GetPath(ROOTS["client"] .. "/Main"))
			Mock.Advance(3)
		end
		local OC = (KC and KC.M and KC.M.ObbyController) or req("client/Controllers/ObbyController")
		local Hud = (KC and KC.M and KC.M.HudController) or req("client/Controllers/HudController")
		if not T.check(type(OC) == "table" and type(OC.Open) == "function", "p5obby client: ObbyController loads with a public Open()") then
			return
		end
		pcall(OC.Init)
		local function toClient(name, ...)
			Mock.ToClient(RS.Remotes:FindFirstChild(name), ...)
		end
		local function find(root, name)
			for _, d in ipairs(root and root:GetDescendants() or {}) do
				if d.Name == name then
					return d
				end
			end
			return nil
		end
		local function picks(mark)
			local out = {}
			for i = mark + 1, #Mock.RemoteLog do
				local e = Mock.RemoteLog[i]
				if e.kind == "server" and e.remote == "ObbyPick" then
					out[#out + 1] = (e.args or {})[1]
				end
			end
			return out
		end
		LP:SetAttribute("InMatch", false)
		LP:SetAttribute("PortalLocked", nil)
		LP:SetAttribute("ObbyLevel", nil)
		toClient("PartyState", nil)
		local snap = { Tokens = 100, Pets = {}, Equipped = {}, Items = {}, Discovered = {}, IndexClaimed = {},
			Stats = { Matches = 4, Wins = 2, TokensEarned = 40, Spins = 0, BestTimes = { Easy = 200.5, Medium = 301 } },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 }, Tutorial = { Step = 99, Done = true, Gifted = true } }
		toClient("ProfileSync", snap)
		Mock.Advance(0.5)
		Mock.SetViewport(1920, 1080)
		Mock.Advance(0.3)
		OC.Open()
		Mock.Advance(0.6)
		local gui = pg:FindFirstChild("NimbusObby")
		local win = gui and gui:FindFirstChild("Window_Obby")
		if not T.check(win and KC.isShown(win) and OC.IsOpen(), "p5obby client: Open() shows the picker") then
			return
		end
		local cards = {}
		for _, id in ipairs({ "Easy", "Medium", "Hard", "Extreme", "Saint" }) do
			cards[id] = find(win, "Level_" .. id)
		end
		T.check(cards.Easy and cards.Saint and cards.Hard, "p5obby client: five level cards Easy .. Saint")
		T.check(cards.Easy:GetAttribute("Unlocked") and cards.Medium:GetAttribute("Unlocked") and cards.Hard:GetAttribute("Unlocked")
			and not cards.Extreme:GetAttribute("Unlocked") and not cards.Saint:GetAttribute("Unlocked"), "p5obby client: a Medium win opens Hard; Extreme / Saint locked")
		T.check(cards.Hard:GetAttribute("Picked") == true, "p5obby client: with no ObbyLevel the highest open level (Hard) is picked")
		T.check(find(cards.Extreme, "Info").Text:find("Beat Hard to unlock", 1, true), "p5obby client: a locked card says 'Beat Hard to unlock'", find(cards.Extreme, "Info").Text)
		T.check(find(cards.Easy, "Info").Text:find("Best 3:21", 1, true), "p5obby client: an open card shows the best time", find(cards.Easy, "Info").Text)
		T.check(win:GetAttribute("DockMode") == "Side" and (win:GetAttribute("DockLeft") or 0) >= 960, "p5obby client: docked right on 1920x1080")
		local mark = #Mock.RemoteLog
		Mock.Click(cards.Extreme)
		Mock.Advance(0.4)
		T.eq(#picks(mark), 0, "p5obby client: a locked level sends no ObbyPick")
		Mock.Click(cards.Medium)
		Mock.Advance(0.2)
		local p = picks(mark)
		T.check(#p == 1 and p[1] == "Medium" and cards.Medium:GetAttribute("Picked") == true, "p5obby client: PICK sends ObbyPick('Medium') and shows it PICKED")
		LP:SetAttribute("ObbyLevel", "Easy")
		Mock.Advance(0.3)
		T.check(cards.Easy:GetAttribute("Picked") == true and cards.Medium:GetAttribute("Picked") ~= true, "p5obby client: the server's ObbyLevel attribute wins")
		-- the gate's party footer
		local lobby = workspace:FindFirstChild("NimbusLobby") or Instance.new("Folder")
		lobby.Name = "NimbusLobby"
		lobby.Parent = workspace
		local gates = lobby:FindFirstChild("Gates") or Instance.new("Folder")
		gates.Name = "Gates"
		gates.Parent = lobby
		local portal = Instance.new("Model")
		portal.Name = "Portal_Obby"
		local padPart = Instance.new("Part")
		padPart.Anchored = true
		padPart.Name = "Pad"
		local rootPart = KC.root and KC.root()
		padPart.CFrame = CFrame.new((rootPart and rootPart.Position or Vector3.new()) + Vector3.new(6, 0, 0))
		padPart.Parent = portal
		portal:SetAttribute("PartyCount", 2)
		portal:SetAttribute("PartyMax", 4)
		portal:SetAttribute("PartyLevel", "Hard")
		portal.Parent = gates
		Mock.Advance(3.2) -- (the locked-card hint of the tap above lasts 3 s)
		local footer = find(win, "Footer")
		T.check(footer and footer.Text == "Party on the pad: Hard 2/4 - step on to join", "p5obby client: the footer reads the gate's party", footer and footer.Text)
		-- a member on the pad cannot pick
		toClient("PartyState", { PortalId = "Obby", Level = "Hard", Stars = 3, LeaderUserId = 77, Players = { { UserId = 77, Name = "Buddy" }, { UserId = LP.UserId, Name = LP.Name } }, Max = 4, Countdown = 10 })
		Mock.Advance(0.3)
		mark = #Mock.RemoteLog
		Mock.Click(cards.Medium)
		Mock.Advance(0.3)
		T.eq(#picks(mark), 0, "p5obby client: a party member's tap sends nothing (the leader picks)")
		-- the leader's CHANGE chip opens the picker (HudController._onChangeLevel -> ObbyController.Open)
		OC.Close()
		Mock.Advance(0.3)
		toClient("PartyState", { PortalId = "Obby", Level = "Hard", Stars = 3, LeaderUserId = LP.UserId, Players = { { UserId = LP.UserId, Name = LP.Name } }, Max = 4, Countdown = 10 })
		LP:SetAttribute("PortalLocked", "Obby")
		Mock.Advance(0.5)
		if Hud and type(Hud._onChangeLevel) == "function" then
			Hud._onChangeLevel()
			Mock.Advance(0.4)
			T.check(OC.IsOpen(), "p5obby client: the party panel's CHANGE (leader) opens the picker")
		else
			T.info("p5obby client: HudController._onChangeLevel missing")
		end
		OC.Close()
		LP:SetAttribute("PortalLocked", nil)
		toClient("PartyState", nil)
		Mock.Advance(0.4)
		-- the gate's ObbyPrompt opens it; stepping onto the pad closes it
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ObbyPrompt"
		prompt:SetAttribute("OpenPanel", "Obby")
		prompt.Parent = padPart
		Mock.Trigger(prompt, LP)
		Mock.Advance(0.5)
		T.check(OC.IsOpen(), "p5obby client: the gate's ObbyPrompt (OpenPanel 'Obby') opens the picker")
		LP:SetAttribute("PortalLocked", "Obby")
		Mock.Advance(0.3)
		T.check(not OC.IsOpen(), "p5obby client: stepping onto the pad closes a picker opened at the gate")
		LP:SetAttribute("PortalLocked", nil)
		-- walking away (> 40 studs from the gate) closes it
		if rootPart then
			Mock.Trigger(prompt, LP)
			Mock.Advance(0.4)
			local home = rootPart.CFrame
			Mock.Teleport(LP, home * CFrame.new(0, 0, 80))
			Mock.Advance(0.6)
			T.check(not OC.IsOpen(), "p5obby client: walking 40+ studs away closes it")
			Mock.Teleport(LP, home)
		else
			T.info("p5obby client: no character root: walk-away not measured")
		end
		-- a portrait phone: a bottom sheet
		Mock.SetViewport(390, 844)
		Mock.Advance(0.4)
		OC.Open()
		Mock.Advance(0.6)
		T.check(win:GetAttribute("DockMode") == "Sheet", "p5obby client: a bottom sheet on 390x844")
		OC.Close()
		Mock.SetViewport(1920, 1080)
		Mock.Advance(0.4)
		-- the unlock toast after a won match that raised the highest open level
		toClient("MatchResult", { Won = true, Reason = "Finished", Seconds = 380, MatchTokens = 30, Bonus = 35, DifficultyId = "Hard", DifficultyName = "Hard", Stars = 3, TotalTokens = 40, Members = {} })
		Mock.Advance(0.3)
		local tg = pg:FindFirstChild("NimbusObbyToast")
		local toast = tg and tg:FindFirstChild("UnlockToast")
		T.check(toast and KC.isShown(toast) and find(toast, "Text").Text == "Extreme unlocked! Pick it at the Obby portal.", "p5obby client: 'Extreme unlocked! Pick it at the Obby portal.' after a Hard win",
			toast and find(toast, "Text").Text)
		toClient("MatchResult", { Won = true, DifficultyId = "Easy", Members = {} })
		Mock.Advance(7)
		T.check(toast and not KC.isShown(toast), "p5obby client: no toast for a win that unlocks nothing (and the toast fades)")
		portal:Destroy()
		LP:SetAttribute("ObbyLevel", nil)
		if KC and KC.flushErrors then
			KC.flushErrors("client_p5obby")
		end
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
