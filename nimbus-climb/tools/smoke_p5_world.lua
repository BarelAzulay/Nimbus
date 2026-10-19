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

		-- [W2 worldlobby] the lobby-wide pass goes here: styleAudit(workspace.NimbusLobby, WS, { label = "lobby" }) with the
		-- exempt tag on clouds / pets / tokens, every child of LobbyInfo.GatesFolder <= 120 parts with a pixel tag
		-- (pixelTagCheck), <= 12 shadow-casting lights, the 8000 budget (from the W3 gate).
		_G.P5WorldStyleAudit = { styleAudit = styleAudit, pixelTagCheck = pixelTagCheck }
	end)

	-- [W2 worldlobby] S.p5world_lobby, S.p5world_gates, S.p5obby_levels, S.p5obby_migration, S.p5world_client_total go here
	-- (and their names back on this file's line in tools/smoke.py).

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

	-- [W4 dungeonclient] S.client_p5obby goes here (and its name back on this file's line in tools/smoke.py).

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
