-- LightingService: owns the sky, the atmosphere, the post effects, the moving sky clouds and the global
-- workspace rules (ARCHITECTURE_V3.md "Phase 5 build contract" 6.4 / 6.5: the Big Sky look).
--
-- Phase 5 look ("a sky like 23.png": soft pink / purple / blue clouds with small stars, bright and happy, the
-- world rebuilt from real stone / wood / grass under Future lighting):
--   * Look.Custom   the owner's painted skybox (branding/sky/*.png, uploaded, the 6 ids pasted into
--                   Config.Sky.Faces): a high afternoon sun, no engine stars (they are painted in the sky)
--   * Look.Fallback no ids yet: the stock sky pushed toward pink at golden hour, pink air with a violet horizon,
--                   pink moving clouds and 3000 stars, so the world already reads "pink-purple sky" on day one
-- Init() picks Custom only when ALL SIX faces are set (one missing -> Fallback, with a warning that names it).
-- A face is the full content id Studio's Asset Manager copies (scheme://..., an Image id); anything else counts as unset.
-- The tuned numbers live in the Look table so the owner can tweak the mood in one place.
-- Lighting.Technology (Future) cannot be written from a script (plugin security): default.project.json sets it.
-- The server writes Lighting ONLY here, at boot (C3); the client's LightingStack layers its presets on top.
-- Plain Lua 5.1-compatible syntax only. Init() is idempotent (twice = the same result).

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local LightingService = {}

local rgb = Color3.fromRGB

-- Shared by both looks (the same table in each, so a tweak applies to both)
local BLOOM = { Enabled = true, Intensity = 0.25, Size = 24, Threshold = 1.35 } -- neon inlays glow, voxel whites do not
local COLOR = { Enabled = true, Brightness = 0, Contrast = 0.12, Saturation = 0.06, TintColor = rgb(255, 246, 252) }
-- Depth of field stays off (it blurs the course edges players need to read).
local DOF = { Enabled = false, FarIntensity = 0.05, NearIntensity = 0, FocusDistance = 200, InFocusRadius = 160 }

local FACE_KEYS = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }

LightingService.FaceKeys = FACE_KEYS

LightingService.Look = {
	Custom = {
		Lighting = {
			ClockTime = 14.5, -- a high, friendly sun
			GeographicLatitude = 34,
			Brightness = 2.2,
			ExposureCompensation = 0,
			Ambient = rgb(112, 104, 140), -- lavender fill: no black creases
			OutdoorAmbient = rgb(150, 138, 176),
			ColorShift_Top = rgb(70, 46, 40), -- warm sun
			ColorShift_Bottom = rgb(30, 20, 60), -- violet bounce
			EnvironmentDiffuseScale = 0.7, -- the sky colours the shade (Future)
			EnvironmentSpecularScale = 0.45,
			GlobalShadows = true,
			ShadowSoftness = 0.3,
			FogStart = 0,
			FogEnd = 100000, -- the Atmosphere does the distance haze
		},
		Atmosphere = {
			Density = 0.32,
			Offset = 0.2,
			Color = rgb(226, 188, 232), -- pink air
			Decay = rgb(150, 120, 210), -- violet horizon
			Glare = 0.15,
			Haze = 1.2,
		},
		Sky = {
			StarCount = 0, -- the stars are painted in the custom sky
			CelestialBodiesShown = true,
			SunAngularSize = 11,
			MoonAngularSize = 9,
		},
		Clouds = { Enabled = true, Cover = 0.45, Density = 0.55, Color = rgb(255, 222, 242) },
		SunRays = { Enabled = true, Intensity = 0.04, Spread = 0.6 },
		Bloom = BLOOM,
		ColorCorrection = COLOR,
		DepthOfField = DOF,
	},
	Fallback = {
		Lighting = {
			ClockTime = 16.6, -- golden hour pushes the stock sky toward pink
			GeographicLatitude = 34,
			Brightness = 2.6, -- keep the world bright under the purple air
			ExposureCompensation = 0.1,
			Ambient = rgb(118, 104, 140),
			OutdoorAmbient = rgb(160, 140, 180),
			ColorShift_Top = rgb(80, 50, 40),
			ColorShift_Bottom = rgb(34, 22, 64),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.35,
			GlobalShadows = true,
			ShadowSoftness = 0.3,
			FogStart = 0,
			FogEnd = 100000,
		},
		Atmosphere = {
			Density = 0.36,
			Offset = 0.2,
			Color = rgb(220, 176, 232),
			Decay = rgb(126, 104, 214),
			Glare = 0.4,
			Haze = 2.0,
		},
		Sky = {
			StarCount = 3000,
			CelestialBodiesShown = true,
			SunAngularSize = 14,
			MoonAngularSize = 9,
		},
		Clouds = { Enabled = true, Cover = 0.62, Density = 0.7, Color = rgb(255, 206, 236) },
		SunRays = { Enabled = true, Intensity = 0.06, Spread = 0.6 },
		Bloom = BLOOM,
		ColorCorrection = COLOR,
		DepthOfField = DOF,
	},
}

-- the look Init() applied last: "Custom" | "Fallback" | nil (before Init)
LightingService.Current = nil

-- Assign every property in `props` to `inst`; a property that does not exist (or is not scriptable on this
-- engine version) only produces a warning instead of breaking boot.
local function setProps(inst, props)
	for key, value in pairs(props) do
		local ok, err = pcall(function()
			inst[key] = value
		end)
		if not ok then
			warn("[LightingService] could not set " .. inst.ClassName .. "." .. tostring(key) .. ": " .. tostring(err))
		end
	end
end

-- Reuse the first child of `className` under `parent`, otherwise create one (idempotent; a place that already
-- ships a Sky / Atmosphere does not double up).
local function ensure(parent, className, name)
	local inst = parent:FindFirstChildOfClass(className)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
	end
	return inst
end

-- One face id: the trimmed content URL (the "Copy ID" text Studio gives, scheme://...), nil when empty or unusable
-- (a bare number, junk, a non-string), so the fallback look is used instead of a grey box.
function LightingService.FaceId(value)
	if type(value) ~= "string" then
		return nil
	end
	local s = value:match("^%s*(.-)%s*$")
	if s:match("^%a[%w%+%.%-]*://%S+$") then
		return s
	end
	return nil
end

-- { Bk = id, ... } when all six faces of Config.Sky.Faces are usable, else nil + the list of missing / bad keys.
function LightingService.CustomFaces()
	local faces = (type(Config.Sky) == "table" and type(Config.Sky.Faces) == "table") and Config.Sky.Faces or {}
	local out, missing, any = {}, {}, false
	for _, key in ipairs(FACE_KEYS) do
		local raw = faces[key]
		local id = LightingService.FaceId(raw)
		if id then
			out[key] = id
			any = true
		else
			missing[#missing + 1] = key
			if raw ~= nil and raw ~= "" then
				any = true
			end
		end
	end
	if #missing > 0 then
		return nil, missing, any
	end
	return out, missing, any
end

-- workspace.Terrain.Clouds (skipped quietly when the engine has no Terrain or no Clouds class).
local function applyClouds(props)
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	local ok, err = pcall(function()
		setProps(ensure(terrain, "Clouds", "NimbusClouds"), props)
	end)
	if not ok then
		warn("[LightingService] sky clouds skipped: " .. tostring(err))
	end
end

-- Global physics / world rules. StreamingEnabled is deliberately left alone (false). Spawning is NOT decided
-- here: Main / PlayerService hold the character until the menu's PLAY (7.2), so CharacterAutoLoads is untouched.
function LightingService.ApplyWorldRules()
	setProps(Workspace, {
		Gravity = Config.Physics.Gravity,
		FallenPartsDestroyHeight = -2000, -- far below the lobby kill plane and every course kill plane
	})
end

function LightingService.Init()
	local faces, missing, any = LightingService.CustomFaces()
	local name = faces and "Custom" or "Fallback"
	if not faces and any then
		-- the owner started pasting ids: say which ones are still missing / unreadable (a warning, not an error)
		warn("[LightingService] Config.Sky.Faces is missing " .. table.concat(missing, ", ") .. " (paste the full id from Asset Manager -> Copy ID): using the fallback sky until all six are set")
	end
	local look = LightingService.Look[name]

	setProps(Lighting, look.Lighting)
	setProps(ensure(Lighting, "Atmosphere", "NimbusAtmosphere"), look.Atmosphere)
	local sky = ensure(Lighting, "Sky", "NimbusSky")
	setProps(sky, look.Sky)
	local skybox = {}
	for _, key in ipairs(FACE_KEYS) do
		-- the fallback clears the faces (the engine's stock sky); Init twice gives the same Sky
		skybox["Skybox" .. key] = faces and faces[key] or ""
	end
	setProps(sky, skybox)
	setProps(ensure(Lighting, "BloomEffect", "NimbusBloom"), look.Bloom)
	setProps(ensure(Lighting, "SunRaysEffect", "NimbusSunRays"), look.SunRays)
	setProps(ensure(Lighting, "ColorCorrectionEffect", "NimbusColor"), look.ColorCorrection)
	setProps(ensure(Lighting, "DepthOfFieldEffect", "NimbusDepthOfField"), look.DepthOfField)
	applyClouds(look.Clouds)

	LightingService.Current = name
	LightingService.ApplyWorldRules()
	return name
end

return LightingService
