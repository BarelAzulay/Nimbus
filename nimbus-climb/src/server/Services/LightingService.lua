-- LightingService: owns the sky, the atmosphere, the post effects, the moving sky clouds and the global
-- workspace rules (ARCHITECTURE_V3.md "Phase 6" 6.0.2 / 6.1 A2 and docs/phase6/style.md section 4).
--
-- Phase 6 look = the Phase 4 look again ("bright, warm afternoon"; P4 LOOK at 7aa0df2): a high warm sun, light shade
-- (no black creases on the voxels), exposure a little under 0 so the cloud whites keep their shades, subtle bloom
-- (only neon trims and tokens glow), colours a touch richer, faint sun rays. No golden hour, no purple haze.
--   * Look.Fallback no sky ids yet (the shipped Config): the stock sky with the P4 light sky-blue air and a soft peach
--                   horizon, white moving clouds and 2500 stars
--   * Look.Custom   the owner's painted skybox (branding/sky/*.png, the 6 ids pasted into Config.Sky.Faces): the same
--                   P4 light, a light pink air to match the painted sky, no engine stars (they are painted)
-- Init() picks Custom only when ALL SIX faces are set (one missing -> Fallback, with a warning that names it).
-- A face is the full content id Studio's Asset Manager copies (scheme://..., an Image id); anything else counts as unset.
-- The tuned numbers live in the Look table so the owner can tweak the mood in one place.
-- Lighting.Technology (ShadowMap, as in Phase 4) cannot be written from a script (plugin security):
-- default.project.json sets it. The server writes Lighting ONLY here, at boot; the client's LightingStack layers
-- its presets (dungeon, low graphics) on top. Plain Lua 5.1-compatible syntax only. Init() is idempotent.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local LightingService = {}

local rgb = Color3.fromRGB

-- Shared by both looks (the same table in each, so a tweak applies to both): the Phase 4 numbers
local BLOOM = { Enabled = true, Intensity = 0.16, Size = 18, Threshold = 1.6 } -- only the brightest accents (neon, tokens) glow
local COLOR = { Enabled = true, Brightness = 0, Contrast = 0.1, Saturation = 0.14, TintColor = rgb(255, 250, 242) }
local SUNRAYS = { Enabled = true, Intensity = 0.06, Spread = 0.6 }
-- Depth of field stays off (it blurs the course edges players need to read).
local DOF = { Enabled = false, FarIntensity = 0.05, NearIntensity = 0, FocusDistance = 200, InFocusRadius = 160 }

-- The world light of Phase 4 (both looks): at latitude 34 and 14:30 the sun stands about 50 degrees up, voxel tops
-- are well lit, sides keep a readable shade and shadows stay short and crisp.
local function p4Light()
	return {
		ClockTime = 14.5,
		GeographicLatitude = 34,
		Brightness = 2.0,
		ExposureCompensation = -0.15, -- the near-white cloud voxels never blow out
		Ambient = rgb(98, 106, 132),
		OutdoorAmbient = rgb(132, 138, 160), -- no black creases
		ColorShift_Top = rgb(66, 50, 26), -- a warm sun
		ColorShift_Bottom = rgb(14, 20, 40), -- a cool sky bounce
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.35,
		GlobalShadows = true,
		ShadowSoftness = 0.3,
		FogStart = 0,
		FogEnd = 100000, -- the Atmosphere does the distance haze
	}
end

local FACE_KEYS = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }

LightingService.FaceKeys = FACE_KEYS

LightingService.Look = {
	Custom = {
		Lighting = p4Light(),
		Atmosphere = {
			Density = 0.28,
			Offset = 0.25,
			Color = rgb(240, 214, 232), -- light pink air to match the painted sky
			Decay = rgb(238, 200, 180), -- soft peach horizon
			Glare = 0.25,
			Haze = 1.0,
		},
		Sky = {
			StarCount = 0, -- the stars are painted in the custom sky
			CelestialBodiesShown = true,
			SunAngularSize = 11,
			MoonAngularSize = 9,
		},
		Clouds = { Enabled = true, Cover = 0.5, Density = 0.6, Color = rgb(252, 238, 246) },
		SunRays = SUNRAYS,
		Bloom = BLOOM,
		ColorCorrection = COLOR,
		DepthOfField = DOF,
	},
	Fallback = {
		Lighting = p4Light(),
		Atmosphere = {
			Density = 0.28,
			Offset = 0.25,
			Color = rgb(178, 198, 228), -- light sky-blue air (Phase 4)
			Decay = rgb(238, 200, 170), -- soft warm peach horizon (Phase 4)
			Glare = 0.25,
			Haze = 1.0,
		},
		Sky = {
			StarCount = 2500,
			CelestialBodiesShown = true,
			SunAngularSize = 16,
			MoonAngularSize = 9,
		},
		Clouds = { Enabled = true, Cover = 0.5, Density = 0.6, Color = rgb(240, 244, 252) }, -- soft white, never overcast
		SunRays = SUNRAYS,
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
