-- SkyFaces: the living sky's painted skybox faces (plan docs/superpowers/plans/2026-10-30-living-sky.md Task 3). The
-- 7 themes of Config.Sky.Themes / RaidThemes (blender/sky/sky_themes.py, 1024 px faces) are Image assets in shared/
-- TextureIds under "sky_<theme>_<Face>" (blender/sky/build_sky_manifest.py indexes them, tools/upload_assets.py
-- --textures uploads them from the owner's keyed session and writes TextureIds). Until all six of a theme are there the
-- theme counts as missing: SkyCycle.Preset then carries no Skybox* keys and the Sky keeps LightingService's boot faces,
-- so a half-uploaded theme never shows a grey face. Pure Lua 5.1-compatible syntax; no Instances, no state.
--
-- API (the contract):
--   SkyFaces.For(themeId [, ids]) -> { SkyboxBk = "rbxassetid://<id>", ... the six } | nil
--       nil unless all six ids[Keys(themeId)] are positive whole numbers (Image ids). ids = shared/TextureIds (tests
--       pass their own table). A fresh table every call.
--   SkyFaces.Keys(themeId) -> { "sky_<theme>_Bk", "_Dn", "_Ft", "_Lf", "_Rt", "_Up" } ({} for a junk theme id)
--   SkyFaces.Faces = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" } (the Roblox face names, the Sky's Skybox<Face> order)

local Shared = script.Parent
local TextureIds = require(Shared.TextureIds)

local SkyFaces = {}

local FACES = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }
SkyFaces.Faces = FACES

local function validTheme(themeId)
	return type(themeId) == "string" and themeId ~= ""
end

-- an Image id: a finite, positive whole number (0 / NaN / a string = not uploaded)
local function validId(v)
	return type(v) == "number" and v == v and v > 0 and v ~= math.huge and v == math.floor(v)
end

function SkyFaces.Keys(themeId)
	local out = {}
	if validTheme(themeId) then
		for i, face in ipairs(FACES) do
			out[i] = "sky_" .. themeId .. "_" .. face
		end
	end
	return out
end

function SkyFaces.For(themeId, ids)
	if not validTheme(themeId) then
		return nil
	end
	ids = type(ids) == "table" and ids or TextureIds
	local out = {}
	for i, key in ipairs(SkyFaces.Keys(themeId)) do
		local id = ids[key]
		if not validId(id) then
			return nil
		end
		local digits = string.format("%.0f", id) -- a 15-digit id printed whole (tostring may give 1.4e+14 off Roblox)
		out["Skybox" .. FACES[i]] = "rbxassetid://" .. digits
	end
	return out
end

return SkyFaces
