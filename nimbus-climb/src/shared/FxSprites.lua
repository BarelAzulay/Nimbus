-- FxSprites (shared; kit B X1, .superpowers/slop-audit/round3/BUILD_PLAN.md): the game's own particle sprites by
-- role. Every ParticleEmitter outside AttackFx takes its texture from here, so nothing in the game shows the Roblox
-- default sparkle or smoke (tools/check.mjs: no rbxasset://textures/particles path outside this file, no emitter
-- created without a texture). A role names a LOOK; it maps to one of the uploaded 4x4 flipbook sheets of
-- blender/vfx/textures.json (ids in shared/TextureIds, the same sheets AttackFx plays):
--   Sparkle  fx_sparkle   a four-point glint that pops and turns: pickups, rarity flair, gates, NPC rugs (runtime tint)
--   Puff     fx_smoke     a puff that swells then breaks up: run dust, landings, foam, mist (runtime tint)
--   Glow     fx_glow      a soft round glow that breathes: fireflies, motes, auras, seeds, vortex streaks (runtime tint)
--   Ember    fx_embers    embers rising and flickering: torches, Flame pets (baked)
--   Dust     fx_dust      a sandy dust puff with grit (baked)
--   Droplet  fx_droplets  a water drop that wobbles, squashes and pops: splashes, bubbles, Water pets (baked)
--   Wisp     fx_wisps     curling purple wisps: Shadow pets (baked)
--   Snow     fx_snow      a six-armed snowflake: Frost pets (baked)
--   Spark    fx_sparks    zig-zag electric crackles: Storm pets, the vortex rim (runtime tint)
--   Leaf     fx_leaves    two leaves tumbling: Nature pets (baked)
--   Star     fx_stars     a plump five-point star twinkling: Celestial pets (baked)
--   Ring     fx_ripple    ripple rings spreading out (flat, facing up): the fountain (baked)
-- "baked" sheets carry their own colour (a site's Color multiplies it), "runtime" ones are white shapes for Color.
-- An id of 0 or a missing key (an upload not approved yet) falls back to the old built-in texture with the flipbook
-- off, so a missing upload never shows an empty emitter.
--
--   FxSprites.Roles                     role -> { Key, Mode, Fps, Stock }
--   FxSprites.Texture(role) -> string   "rbxassetid://<id>", or the role's Stock path when the id is 0 / missing
--   FxSprites.Apply(emitter, role) -> emitter   Texture + flipbook: Grid4x4, the sheet's FlipbookMode and fps, a
--                                       random start frame on Loop sheets (fallback: FlipbookLayout None)
--   FxSprites.RoleOf(texture) -> role | nil   which role a Texture string belongs to (own id or fallback; tests)
--   FxSprites.Strip(role) -> string     a single-frame Beam / Trail strip: Dash = fx_speedlines ("" = a plain Beam
--                                       when not uploaded); Beams cannot play the 4x4 sheets
--   FxSprites._Deps({ TextureIds = t }) / FxSprites._Deps(false)   TESTS ONLY: another id table / the real one again
-- An unknown role warns once and uses Sparkle. Plain Lua 5.1-compatible syntax only.

local FxSprites = {}

local STOCK = "rbxasset://textures/particles/"

-- mode / fps = blender/vfx/textures.json (the same numbers as AttackFx SHEETS)
local ROLES = {
	Sparkle = { Key = "fx_sparkle", Mode = "Loop", Fps = 16, Stock = STOCK .. "sparkles_main.dds" },
	Puff = { Key = "fx_smoke", Mode = "OneShot", Fps = 16, Stock = STOCK .. "smoke_main.dds" },
	Glow = { Key = "fx_glow", Mode = "Loop", Fps = 12, Stock = STOCK .. "explosion01_implosion_main.dds" },
	Ember = { Key = "fx_embers", Mode = "Loop", Fps = 20, Stock = STOCK .. "fire_sparks_main.dds" },
	Dust = { Key = "fx_dust", Mode = "OneShot", Fps = 16, Stock = STOCK .. "smoke_main.dds" },
	Droplet = { Key = "fx_droplets", Mode = "OneShot", Fps = 16, Stock = STOCK .. "explosion01_implosion_main.dds" },
	Wisp = { Key = "fx_wisps", Mode = "Loop", Fps = 16, Stock = STOCK .. "smoke_main.dds" },
	Snow = { Key = "fx_snow", Mode = "Loop", Fps = 12, Stock = STOCK .. "sparkles_main.dds" },
	Spark = { Key = "fx_sparks", Mode = "Loop", Fps = 24, Stock = STOCK .. "fire_sparks_main.dds" },
	Leaf = { Key = "fx_leaves", Mode = "Loop", Fps = 16, Stock = STOCK .. "sparkles_main.dds" },
	Star = { Key = "fx_stars", Mode = "Loop", Fps = 16, Stock = STOCK .. "sparkles_main.dds" },
	Ring = { Key = "fx_ripple", Mode = "OneShot", Fps = 16, Stock = STOCK .. "explosion01_shockwave_main.dds" },
}
FxSprites.Roles = ROLES

-- single-frame strips (grid 1 in textures.json) for Beams / Trails
local STRIPS = {
	Dash = "fx_speedlines",
}

local realIds = nil -- shared/TextureIds, required lazily (false when missing)
local override = nil
local warned = {}

local function ids()
	if override then
		return override
	end
	if realIds == nil then
		realIds = false
		local ok, mod = pcall(function()
			local inst = script.Parent:FindFirstChild("TextureIds")
			return inst and require(inst) or nil
		end)
		if ok and type(mod) == "table" then
			realIds = mod
		end
	end
	return realIds or {}
end

local function roleOf(role)
	local r = ROLES[role]
	if r then
		return r
	end
	if not warned[tostring(role)] then
		warned[tostring(role)] = true
		warn("[FxSprites] unknown role " .. tostring(role) .. ": using Sparkle")
	end
	return ROLES.Sparkle
end

-- the role's uploaded id (a positive number) or nil
local function idOf(r)
	local id = tonumber(ids()[r.Key])
	if id and id > 0 then
		return id
	end
	return nil
end

function FxSprites.Texture(role)
	local r = roleOf(role)
	local id = idOf(r)
	return id and ("rbxassetid://" .. tostring(id)) or r.Stock
end

function FxSprites.Apply(emitter, role)
	local r = roleOf(role)
	local id = idOf(r)
	if id then
		emitter.Texture = "rbxassetid://" .. tostring(id)
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		emitter.FlipbookMode = Enum.ParticleFlipbookMode[r.Mode]
		emitter.FlipbookFramerate = NumberRange.new(r.Fps)
		emitter.FlipbookStartRandom = r.Mode == "Loop"
	else
		emitter.Texture = r.Stock
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.None
	end
	return emitter
end

function FxSprites.RoleOf(texture)
	if type(texture) ~= "string" or texture == "" then
		return nil
	end
	for name, r in pairs(ROLES) do
		local id = idOf(r)
		if (id and texture == "rbxassetid://" .. tostring(id)) or (not id and texture == r.Stock) then
			return name
		end
	end
	return nil
end

function FxSprites.Strip(role)
	local key = STRIPS[role]
	local id = key and tonumber(ids()[key])
	if id and id > 0 then
		return "rbxassetid://" .. tostring(id)
	end
	return ""
end

-- TESTS ONLY
function FxSprites._Deps(deps)
	if deps == false or deps == nil then
		override = nil
	elseif type(deps) == "table" and type(deps.TextureIds) == "table" then
		override = deps.TextureIds
	end
end

return FxSprites
