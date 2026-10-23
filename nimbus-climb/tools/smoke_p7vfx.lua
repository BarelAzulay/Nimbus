-- smoke_p7vfx.lua: the pet attack VFX (docs/superpowers/plans/2026-10-23-pet-attack-vfx.md). Loaded by tools/smoke.py
-- in the server world.
--   p7vfx_ids   (pure) the uploaded ids: every key of blender/vfx/textures.json is in shared/TextureIds as a positive
--               integer (an Image id, checked in Studio when uploaded; the file is written by tools/upload_assets.py
--               --textures), TextureIds has no key besides those and the gate vortex layers (blender/textures/
--               textures.json), and every vfx_* key of blender/catalog/vfx.json is in shared/MeshIds (the 22 cores).
--   p7vfx_catalog (pure) shared/AttackFxCatalog (Task 4): bands / sizes (1.4 cap), every element x attack x rarity x
--               stage x mine resolves (beats, size, band, known texture / core keys, Beam / Trail strips vs Emitter
--               flipbooks, <= 6 emitters), monotonic layers, density / camera punch / screen glow, the 12 signatures,
--               Unit (hybrids: first element + the hybrid's rarity), Nature's petal trail with no green-only colour.
-- Deterministic: keys are read from the committed manifests in file order. Plain Lua 5.1 syntax.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local fmt = string.format

-- "rb": Windows text mode stops at byte 0x1A
local function readFile(rel)
	for _, prefix in ipairs({ "", "../", "nimbus-climb/" }) do
		local fh = io.open(prefix .. rel, "rb")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src
		end
	end
	return nil
end

-- every "key": "<name>" of a manifest whose name starts with `prefix`, in file order
local function manifestKeys(rel, prefix)
	local src = readFile(rel)
	if not src then
		return nil
	end
	local keys = {}
	for k in string.gmatch(src, '"key"%s*:%s*"([%w_]+)"') do
		if string.sub(k, 1, #prefix) == prefix then
			keys[#keys + 1] = k
		end
	end
	return keys
end

local function sharedModule(name)
	local ok, inst = pcall(Mock.GetPath, ROOTS.shared .. "/" .. name)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

S.p7vfx_ids = guarded("p7vfx_ids", function()
	local texKeys = manifestKeys("blender/vfx/textures.json", "")
	local coreKeys = manifestKeys("blender/catalog/vfx.json", "vfx_")
	local TextureIds = sharedModule("TextureIds")
	local MeshIds = sharedModule("MeshIds")
	if not T.check(texKeys ~= nil and #texKeys > 0, "p7vfx ids: blender/vfx/textures.json lists texture keys")
		or not T.check(coreKeys ~= nil and #coreKeys > 0, "p7vfx ids: blender/catalog/vfx.json lists vfx_* keys")
		or not T.check(TextureIds ~= nil and MeshIds ~= nil, "p7vfx ids: shared/TextureIds and shared/MeshIds load as tables") then
		return
	end

	-- textures: every manifest key, as a positive integer Image id (check.mjs texture-ids: numbers only)
	local known, okTex = {}, 0
	for _, key in ipairs(texKeys) do
		known[key] = true
		local v = TextureIds[key]
		if v == nil then
			T.fail("p7vfx ids: TextureIds missing " .. key)
		elseif type(v) ~= "number" or v <= 0 or v ~= math.floor(v) then
			T.fail("p7vfx ids: TextureIds." .. key .. " is not a positive integer id", tostring(v))
		else
			okTex = okTex + 1
		end
	end
	T.check(okTex == #texKeys, fmt("p7vfx ids: every texture key has a positive integer Image id (%d / %d)", okTex, #texKeys))

	-- no extra keys: TextureIds = the VFX keys + (once uploaded) the gate vortex layers of the uploader's other Image
	-- index blender/textures/textures.json ({ "keys": { key: { ... } } }); nothing else
	local vortexSrc = readFile("blender/textures/textures.json") or ""
	local vortex = {}
	for k in string.gmatch(vortexSrc, '"([%w_]+)"%s*:%s*{') do
		if k ~= "keys" then
			vortex[k] = true
		end
	end
	local extra = {}
	for k in pairs(TextureIds) do
		if not known[k] and not vortex[k] then
			extra[#extra + 1] = tostring(k)
		end
	end
	table.sort(extra)
	T.check(#extra == 0, "p7vfx ids: TextureIds has no key outside blender/vfx/textures.json + the vortex layers", table.concat(extra, ","))

	-- cores: every vfx_* key of the catalog is uploaded
	local okCore = 0
	for _, key in ipairs(coreKeys) do
		if MeshIds[key] == nil then
			T.fail("p7vfx ids: MeshIds missing " .. key)
		else
			okCore = okCore + 1
		end
	end
	T.check(okCore == #coreKeys, fmt("p7vfx ids: every vfx_* core key is in MeshIds (%d / %d)", okCore, #coreKeys))
end)

----------------------------------------------------------------------
-- p7vfx_catalog: shared/AttackFxCatalog (Task 4) resolves every attack into a recipe that keeps the spec's rules
----------------------------------------------------------------------

-- blender/vfx/textures.json -> { [key] = { grid = n, tint = "baked"|"runtime" } } (one object per texture line)
local function textureManifest()
	local src = readFile("blender/vfx/textures.json")
	if not src then
		return nil
	end
	local out, n = {}, 0
	for obj in string.gmatch(src, "{[^{}]*}") do
		local key = string.match(obj, '"key"%s*:%s*"([%w_]+)"')
		if key then
			out[key] = {
				grid = tonumber(string.match(obj, '"grid"%s*:%s*(%d+)')),
				tint = string.match(obj, '"tint"%s*:%s*"(%a+)"'),
			}
			n = n + 1
		end
	end
	return out, n
end

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
local BAND = { Common = 1, Uncommon = 1, Rare = 2, Epic = 2, Legendary = 3, Mythic = 3, Secret = 4 }
local SIZE = { Common = 1.0, Uncommon = 1.05, Rare = 1.1, Epic = 1.15, Legendary = 1.2, Mythic = 1.3, Secret = 1.4 }
local KINDS = { "Blast", "Beam", "Pounce", "Storm", "Freeze", "Heal", "Shield", "Rally", "Haste" }
local SHAPES = { "Cone", "Circle", "Line" }
local LAYER_KINDS = { Emitter = true, Beam = true, Trail = true, Light = true, Ring = true, Decal = true, Mesh = true }
local AT = { Source = true, Core = true, Path = true, Target = true, Ground = true, Above = true, Behind = true, Self = true, Allies = true }
local PATHS = { Projectile = true, Swipe = true, Ground = true, Self = true, Allies = true, Area = true }
local BEATS = { "Charge", "Release", "Travel", "Impact", "Linger" }
local SIGNATURE_PETS = {
	"ember_phoenix", "sunbeam_bear", "twilight_dragon", "cloudy_dragon", "starlight_unicorn", "stormfang",
	"eclipse_dragon", "obsidian_phoenix", "phantom_kitsune", "magma_cub", "rime_wyrmling", "hydralotl",
}

-- every attack variant a recipe can be asked for: { Attack, Kind?, Shape?, label }
local function variants()
	local out = {}
	for _, a in ipairs({ "Melee", "Ranged", "Hurt", "Ko", "Victory" }) do
		out[#out + 1] = { Attack = a, label = a }
	end
	for _, s in ipairs(SHAPES) do
		out[#out + 1] = { Attack = "Element", Shape = s, label = "Element/" .. s }
	end
	for _, k in ipairs(KINDS) do
		out[#out + 1] = { Attack = "Special", Kind = k, label = "Special/" .. k }
	end
	return out
end

local function finiteNum(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- a Color3 that is mostly green (it would vanish on the grass)
local function greenOnly(c)
	if type(c) ~= "userdata" and type(c) ~= "table" then
		return false
	end
	local r, g, b = tonumber(c.R) or 0, tonumber(c.G) or 0, tonumber(c.B) or 0
	return g >= 0.35 and g - math.max(r, b) > 0.15
end

-- problems of one recipe against the shared rules (texture grid per layer kind, known keys, budgets); "" = fine
local function recipeProblems(r, tex, cores)
	local bad = {}
	local function key(k, where)
		if type(k) ~= "string" or not cores[k] then
			bad[#bad + 1] = where .. " key " .. tostring(k)
		end
	end
	local function texture(t, kind, where)
		if t == nil then
			if kind == "Emitter" then
				bad[#bad + 1] = where .. " Emitter without a texture"
			end
			return
		end
		local m = tex[t]
		if not m then
			bad[#bad + 1] = where .. " unknown texture " .. tostring(t)
		elseif (kind == "Beam" or kind == "Trail") and m.grid ~= 1 then
			bad[#bad + 1] = where .. " " .. kind .. " uses the flipbook " .. t
		elseif (kind == "Emitter" or kind == "Decal") and m.grid ~= 4 then
			bad[#bad + 1] = where .. " " .. kind .. " uses the strip " .. t
		elseif kind == "Light" or kind == "Ring" or kind == "Mesh" then
			bad[#bad + 1] = where .. " " .. kind .. " has a texture"
		end
	end
	if type(r.Core) ~= "table" then
		bad[#bad + 1] = "no Core"
	else
		key(r.Core.Key, "Core")
		if not PATHS[r.Core.Path] then
			bad[#bad + 1] = "Core.Path " .. tostring(r.Core.Path)
		end
		if r.Core.Color == nil or type(r.Core.Material) ~= "string" then
			bad[#bad + 1] = "Core colour / material"
		end
	end
	local emitters, ids = 0, {}
	if type(r.Layers) ~= "table" or #r.Layers == 0 then
		bad[#bad + 1] = "no Layers"
	else
		for i, l in ipairs(r.Layers) do
			local where = "layer " .. i .. " " .. tostring(l.Id)
			if l.Id == nil or ids[l.Id] then
				bad[#bad + 1] = where .. " id missing or repeated"
			end
			ids[l.Id or i] = true
			if not LAYER_KINDS[l.Kind] then
				bad[#bad + 1] = where .. " kind " .. tostring(l.Kind)
			end
			texture(l.Texture, l.Kind, where)
			if l.Key ~= nil then
				key(l.Key, where)
			end
			if (l.Kind == "Ring" or l.Kind == "Mesh") and l.Key == nil then
				bad[#bad + 1] = where .. " " .. tostring(l.Kind) .. " without a core key"
			end
			if not AT[l.At] then
				bad[#bad + 1] = where .. " At " .. tostring(l.At)
			end
			if l.Color == nil then
				bad[#bad + 1] = where .. " no Color"
			end
			if l.Count ~= nil and not (finiteNum(l.Count) and l.Count >= 1) then
				bad[#bad + 1] = where .. " Count " .. tostring(l.Count)
			end
			if l.Kind == "Emitter" then
				emitters = emitters + 1
			end
		end
	end
	if type(r.Alive) ~= "table" then
		bad[#bad + 1] = "no Alive table"
	elseif r.Alive.Kind ~= nil then
		local k = r.Alive.Kind
		if k ~= "Mesh" and not LAYER_KINDS[k] then
			bad[#bad + 1] = "Alive kind " .. tostring(k)
		end
		if k == "Mesh" then
			key(r.Alive.Key, "Alive")
		else
			texture(r.Alive.Texture, k, "Alive")
		end
		if k == "Emitter" then
			emitters = emitters + 1
		end
	end
	if emitters > 6 then
		bad[#bad + 1] = emitters .. " emitters (> 6)"
	end
	if type(r.Sig) == "table" and r.Sig.Actor ~= nil then
		key(r.Sig.Actor.Key, "Sig.Actor")
		if not AT[r.Sig.Actor.At] then
			bad[#bad + 1] = "Sig.Actor At " .. tostring(r.Sig.Actor.At)
		end
	end
	return table.concat(bad, "; ")
end

local function kindSet(r)
	local s = {}
	for _, l in ipairs(r.Layers or {}) do
		s[l.Kind] = true
	end
	return s
end

local function idSet(r)
	local s = {}
	for _, l in ipairs(r.Layers or {}) do
		s[tostring(l.Id)] = true
	end
	return s
end

local function subset(a, b)
	for k in pairs(a) do
		if not b[k] then
			return false, k
		end
	end
	return true
end

S.p7vfx_catalog = guarded("p7vfx_catalog", function()
	local C = sharedModule("AttackFxCatalog")
	if C == nil then
		T.fail("p7vfx catalog: could not load AttackFxCatalog")
		return
	end
	T.ok("p7vfx catalog: AttackFxCatalog loads")
	local Config = sharedModule("Config")
	local PetCatalog = sharedModule("PetCatalog")
	local tex, texCount = textureManifest()
	local coreList = manifestKeys("blender/catalog/vfx.json", "vfx_")
	if not T.check(Config ~= nil and PetCatalog ~= nil, "p7vfx catalog: Config and PetCatalog load")
		or not T.check(tex ~= nil and texCount == 30, "p7vfx catalog: blender/vfx/textures.json has the 30 textures", tostring(texCount))
		or not T.check(coreList ~= nil and #coreList == 22, "p7vfx catalog: blender/catalog/vfx.json has the 22 cores", tostring(coreList and #coreList)) then
		return
	end
	local cores = {}
	for _, k in ipairs(coreList) do
		cores[k] = true
	end
	for _, fn in ipairs({ "BandOf", "SizeOf", "Resolve", "Unit" }) do
		T.check(type(C[fn]) == "function", "p7vfx catalog: AttackFxCatalog." .. fn .. " is a function")
	end
	if type(C.Resolve) ~= "function" or type(C.BandOf) ~= "function" or type(C.SizeOf) ~= "function" or type(C.Unit) ~= "function" then
		return
	end

	-- the catalog's own texture table mirrors the manifest (grid + baked / runtime tint)
	local texMirror = T.tally("p7vfx catalog: AttackFxCatalog.Textures mirrors blender/vfx/textures.json (grid, tint)")
	local mirrored = type(C.Textures) == "table" and C.Textures or {}
	for k, m in pairs(tex) do
		local e = mirrored[k]
		texMirror:case(type(e) == "table" and e.Grid == m.grid and (e.Baked == true) == (m.tint == "baked"), k)
	end
	for k in pairs(mirrored) do
		texMirror:case(tex[k] ~= nil, "extra " .. tostring(k))
	end
	texMirror:report()

	-- bands and sizes (spec "Rarity ladder")
	local bands = T.tally("p7vfx catalog: BandOf = 1 Common/Uncommon, 2 Rare/Epic, 3 Legendary/Mythic, 4 Secret; unknown -> 1")
	for _, r in ipairs(RARITIES) do
		bands:case(C.BandOf(r) == BAND[r], r .. " -> " .. tostring(C.BandOf(r)))
	end
	bands:case(C.BandOf("Bogus") == 1 and C.BandOf(nil) == 1 and C.BandOf(7) == 1, "unknown -> " .. tostring(C.BandOf("Bogus")))
	bands:report()
	local sizes = T.tally("p7vfx catalog: SizeOf = rarity size x (1, 1.05, 1.10) by stage, never past the 1.4 cap")
	for _, r in ipairs(RARITIES) do
		for stage = 0, 2 do
			local want = math.min(1.4, SIZE[r] * (1 + 0.05 * stage))
			local got = C.SizeOf(r, stage)
			sizes:case(finiteNum(got) and math.abs(got - want) < 1e-6 and got <= 1.4, fmt("%s stage %d: %s (want %.4f)", r, stage, tostring(got), want))
		end
	end
	sizes:case(C.SizeOf("Bogus", 0) == 1 and C.SizeOf("Secret", 9) == 1.4 and C.SizeOf("Common", nil) == 1, "unknown rarity / stage")
	sizes:report()

	-- the full matrix: element x attack variant x rarity x stage x mine
	local elements = Config.Elements.Order
	local matrix = T.tally("p7vfx catalog: every element x attack x rarity x stage resolves (finite beats <= 2.5 s / specials <= 3.5 s, Size <= 1.4, Band, known keys, strip/flipbook per layer kind, <= 6 emitters, unique layer ids)")
	local mineRules = T.tally("p7vfx catalog: Mine = false -> Density 0.6, no camera punch, no screen glow; Mine = true -> Density 1, punch at band >= 3, glow at band 4")
	local mono = T.tally("p7vfx catalog: each rarity keeps every layer of the rarities below it (layer ids and kinds monotonic across bands)")
	local total = 0
	for _, element in ipairs(elements) do
		for _, v in ipairs(variants()) do
			for stage = 0, 2 do
				local prevIds, prevKinds, prevBandKinds, prevBand = nil, nil, nil, nil
				for _, rarity in ipairs(RARITIES) do
					local label = fmt("%s %s %s s%d", element, v.label, rarity, stage)
					local mineRecipe = nil
					for _, mine in ipairs({ true, false }) do
						local ok, r = pcall(C.Resolve, { Element = element, Attack = v.Attack, Kind = v.Kind, Shape = v.Shape, Rarity = rarity, Stage = stage, Mine = mine })
						total = total + 1
						if not ok or type(r) ~= "table" then
							matrix:case(false, label .. ": " .. (ok and "nil recipe" or tostring(r)))
						else
							local problems = {}
							local sum = 0
							for _, b in ipairs(BEATS) do
								local x = type(r.Beats) == "table" and r.Beats[b]
								if not (finiteNum(x) and x >= 0) then
									problems[#problems + 1] = "beat " .. b .. " " .. tostring(x)
								else
									sum = sum + x
								end
							end
							local cap = (v.Attack == "Special") and 3.5 or 2.5
							if sum > cap then
								problems[#problems + 1] = fmt("beats sum %.2f > %.1f", sum, cap)
							end
							if not (finiteNum(r.Size) and r.Size <= 1.4 and math.abs(r.Size - C.SizeOf(rarity, stage)) < 1e-9) then
								problems[#problems + 1] = "Size " .. tostring(r.Size)
							end
							if r.Band ~= C.BandOf(rarity) then
								problems[#problems + 1] = "Band " .. tostring(r.Band)
							end
							if r.Signature ~= nil then
								problems[#problems + 1] = "Signature without a pet " .. tostring(r.Signature)
							end
							local more = recipeProblems(r, tex, cores)
							if more ~= "" then
								problems[#problems + 1] = more
							end
							matrix:case(#problems == 0, label .. ": " .. table.concat(problems, "; "))
							local band = BAND[rarity]
							if mine then
								mineRecipe = r
								mineRules:case(r.Density == 1 and r.CameraPunch == (band >= 3) and r.ScreenGlow == (band == 4),
									fmt("%s mine: Density %s punch %s glow %s", label, tostring(r.Density), tostring(r.CameraPunch), tostring(r.ScreenGlow)))
							else
								mineRules:case(r.Density == 0.6 and r.CameraPunch == false and r.ScreenGlow == false,
									fmt("%s others: Density %s punch %s glow %s", label, tostring(r.Density), tostring(r.CameraPunch), tostring(r.ScreenGlow)))
							end
						end
					end
					if mineRecipe then
						local ids, kinds = idSet(mineRecipe), kindSet(mineRecipe)
						if prevIds then
							local okIds, missing = subset(prevIds, ids)
							mono:case(okIds, label .. " lost layer " .. tostring(missing))
						end
						if prevBand and BAND[rarity] > prevBand then
							local okKinds, missingKind = subset(prevBandKinds, kinds)
							mono:case(okKinds, label .. " lost layer kind " .. tostring(missingKind))
						end
						if prevBand == nil or BAND[rarity] > prevBand then
							prevBandKinds, prevBand = kinds, BAND[rarity]
						end
						prevIds, prevKinds = ids, kinds
					end
				end
			end
		end
	end
	matrix:report(total .. " resolves")
	mineRules:report()
	mono:report()

	-- Mine defaults to "others" (nil is not my team)
	local rNil = C.Resolve({ Element = "Flame", Attack = "Melee", Rarity = "Secret", Stage = 0 })
	T.check(type(rNil) == "table" and rNil.Density == 0.6 and rNil.CameraPunch == false and rNil.ScreenGlow == false,
		"p7vfx catalog: Mine missing -> treated as another player's effect (0.6, no punch, no glow)")

	-- bad requests return nil, never throw
	local badReqs = {
		{ nil, "nil request" },
		{ {}, "empty request" },
		{ { Element = "Plasma", Attack = "Melee", Rarity = "Rare" }, "unknown element" },
		{ { Element = "Flame", Attack = "Dance", Rarity = "Rare" }, "unknown attack" },
		{ { Element = "Flame", Attack = "Special", Kind = "Sneeze", Rarity = "Rare" }, "unknown special kind" },
		{ { Element = "Flame", Attack = "Element", Shape = "Star", Rarity = "Rare" }, "unknown shape" },
	}
	local badT = T.tally("p7vfx catalog: bad requests return nil without an error")
	for _, b in ipairs(badReqs) do
		local ok, r = pcall(C.Resolve, b[1])
		badT:case(ok and r == nil, b[2] .. ": " .. tostring(r))
	end
	badT:report()
	local unknownRarity = C.Resolve({ Element = "Frost", Attack = "Ranged", Rarity = "Bogus", Stage = "x", Mine = true })
	T.check(type(unknownRarity) == "table" and unknownRarity.Band == 1 and unknownRarity.Size == 1,
		"p7vfx catalog: an unknown rarity / stage resolves as band 1, size 1.0")
	local defShape = C.Resolve({ Element = "Storm", Attack = "Element", Rarity = "Rare" })
	T.check(type(defShape) == "table" and defShape.Shape == "Line",
		"p7vfx catalog: Element without a Shape uses BattleCatalog.ElementAttacks (Storm Bolt = Line)", defShape and tostring(defShape.Shape))

	-- recipes are fresh copies: editing one never changes the next
	local r1 = C.Resolve({ Element = "Water", Attack = "Ranged", Rarity = "Epic", Stage = 1, Mine = true })
	r1.Layers[1].Count = 999
	r1.Core.Key = "broken"
	r1.Beats.Charge = 99
	local r2 = C.Resolve({ Element = "Water", Attack = "Ranged", Rarity = "Epic", Stage = 1, Mine = true })
	T.check(r2.Layers[1].Count ~= 999 and r2.Core.Key ~= "broken" and r2.Beats.Charge ~= 99, "p7vfx catalog: Resolve returns a fresh recipe each call")

	-- travel by distance: 60 studs/s for a projectile, capped; impact time = Charge + Release + Travel
	local near = C.Resolve({ Element = "Flame", Attack = "Ranged", Rarity = "Rare", Distance = 6 })
	local far = C.Resolve({ Element = "Flame", Attack = "Ranged", Rarity = "Rare", Distance = 600 })
	T.check(near and far and math.abs(near.Beats.Travel - 0.1) < 1e-6 and far.Beats.Travel <= 0.5 + 1e-9 and far.Beats.Travel > near.Beats.Travel,
		"p7vfx catalog: projectile Travel = distance / 60 studs/s, capped", near and far and fmt("%.3f / %.3f", near.Beats.Travel, far.Beats.Travel))
	T.check(near and finiteNum(near.ImpactAt) and math.abs(near.ImpactAt - (near.Beats.Charge + near.Beats.Release + near.Beats.Travel)) < 1e-9,
		"p7vfx catalog: ImpactAt = Charge + Release + Travel")

	-- beat ranges of the brief: Charge 0.12-0.3 (specials up to 0.8), Release 0.05, Impact 0.15, Linger 0.4-1.0
	local ranges = T.tally("p7vfx catalog: attack beats in range (Charge 0.12-0.3 / specials <= 0.8, Release 0.05, Impact 0.15, Linger 0.4-1.0)")
	for _, element in ipairs(elements) do
		for _, v in ipairs(variants()) do
			if v.Attack ~= "Hurt" and v.Attack ~= "Ko" and v.Attack ~= "Victory" then
				for _, rarity in ipairs(RARITIES) do
					local r = C.Resolve({ Element = element, Attack = v.Attack, Kind = v.Kind, Shape = v.Shape, Rarity = rarity, Mine = true })
					local b = r and r.Beats or {}
					local cmax = (v.Attack == "Special") and 0.8 or 0.3
					ranges:case(r ~= nil and b.Charge >= 0.12 - 1e-9 and b.Charge <= cmax + 1e-9 and math.abs(b.Release - 0.05) < 1e-9
						and math.abs(b.Impact - 0.15) < 1e-9 and b.Linger >= 0.4 - 1e-9 and b.Linger <= 1.0 + 1e-9,
						fmt("%s %s %s: C %.2f R %.2f I %.2f L %.2f", element, v.label, rarity, b.Charge or -1, b.Release or -1, b.Impact or -1, b.Linger or -1))
				end
			end
		end
	end
	ranges:report()

	-- signatures: exactly the 12 spec pets, on their special only
	local sigKeys = {}
	for k in pairs(type(C.Signatures) == "table" and C.Signatures or {}) do
		sigKeys[#sigKeys + 1] = k
	end
	table.sort(sigKeys)
	local want = {}
	for _, id in ipairs(SIGNATURE_PETS) do
		want[#want + 1] = id
	end
	table.sort(want)
	T.check(table.concat(sigKeys, ",") == table.concat(want, ","), "p7vfx catalog: Signatures are keyed by the 12 spec pets", table.concat(sigKeys, ","))
	local isSig = {}
	for _, id in ipairs(SIGNATURE_PETS) do
		isSig[id] = true
	end
	local sigT = T.tally("p7vfx catalog: Signature = the pet id exactly for the 12 spec pets on Attack Special (each pet, its own element / kind / rarity)")
	local sigOk = T.tally("p7vfx catalog: every signature recipe is valid (keys, strips / flipbooks, <= 6 emitters, beats <= 3.5 s, its spec element + kind)")
	local usedSig = {}
	local pets = 0
	for _, def in ipairs(PetCatalog.Pets or {}) do
		pets = pets + 1
		local kind = type(def.Special) == "table" and def.Special.Kind or nil
		for _, mine in ipairs({ true, false }) do
			local r = C.Resolve({ Element = def.Element, Attack = "Special", Kind = kind, Rarity = def.Rarity, Stage = 2, PetId = def.Id, Mine = mine })
			local want2 = isSig[def.Id] and def.Id or nil
			sigT:case(r ~= nil and r.Signature == want2, def.Id .. " -> " .. tostring(r and r.Signature))
			local melee = C.Resolve({ Element = def.Element, Attack = "Melee", Rarity = def.Rarity, PetId = def.Id, Mine = mine })
			sigT:case(melee ~= nil and melee.Signature == nil, def.Id .. " melee carries a signature")
			if want2 and r then
				local p = recipeProblems(r, tex, cores)
				local sum = 0
				for _, b in ipairs(BEATS) do
					sum = sum + (tonumber(r.Beats[b]) or 99)
				end
				local s = C.Signatures[def.Id]
				sigOk:case(p == "" and sum <= 3.5 and s.Element == def.Element and s.Kind == kind and r.Band == C.BandOf(def.Rarity),
					def.Id .. ": " .. p .. fmt(" beats %.2f", sum))
				if type(r.Core) == "table" then
					usedSig[r.Core.Key] = true
				end
				if type(r.Sig) == "table" and type(r.Sig.Actor) == "table" then
					usedSig[r.Sig.Actor.Key] = true
				end
			end
		end
	end
	sigT:report(pets .. " pets")
	sigOk:report()
	local unused = {}
	for _, k in ipairs(coreList) do
		if string.sub(k, 1, 8) == "vfx_sig_" and not usedSig[k] then
			unused[#unused + 1] = k
		end
	end
	T.check(#unused == 0, "p7vfx catalog: every vfx_sig_* core is used by a signature", table.concat(unused, ","))
	local withoutKind = C.Resolve({ Element = "Flame", Attack = "Special", Rarity = "Legendary", PetId = "ember_phoenix", Mine = true })
	T.check(withoutKind ~= nil and withoutKind.Signature == "ember_phoenix" and withoutKind.Kind == "Blast",
		"p7vfx catalog: a signature pet's Special without a Kind uses the signature's kind")

	-- Unit: from a BattleSim unitInfo (Review Focus 2: hybrids)
	local function rarityOf(id)
		local d = PetCatalog.Get(id)
		return d and d.Rarity
	end
	local hyb = C.Unit({ id = 4, key = "hyb:abc123", petId = "hyb:abc123", element = "Storm", elements = { "Storm", "Flame" }, evo = 1, ranged = true,
		look = { Hybrid = true, BodyId = "storm_tabby", StyleId = "maple_fox", Species = "Cat" } })
	T.check(type(hyb) == "table" and hyb.Element == "Storm" and hyb.Rarity == rarityOf("storm_tabby") and hyb.Stage == 1 and hyb.Ranged == true,
		"p7vfx catalog: Unit on a hyb: unit = its first element (Storm) and the hybrid's rarity (Rare body > Uncommon style)",
		hyb and fmt("%s %s %s %s", tostring(hyb.Element), tostring(hyb.Rarity), tostring(hyb.Stage), tostring(hyb.Ranged)))
	-- PetKeys' rule: a hybrid without a record rarity is the HIGHER of its body and style pets
	local styleRarer = C.Unit({ key = "hyb:s", petId = "hyb:s", elements = { "Storm", "Flame" }, look = { Hybrid = true, BodyId = "storm_tabby", StyleId = "ember_phoenix" } })
	T.check(rarityOf("storm_tabby") == "Rare" and rarityOf("ember_phoenix") == "Legendary" and styleRarer and styleRarer.Rarity == "Legendary" and styleRarer.Element == "Storm",
		"p7vfx catalog: Unit on a hybrid whose Style is rarer than its Body = the Style's rarity", styleRarer and tostring(styleRarer.Rarity))
	local styleExplicit = C.Unit({ key = "hyb:t", petId = "hyb:t", elements = { "Storm" }, look = { Hybrid = true, BodyId = "storm_tabby", StyleId = "ember_phoenix", Rarity = "Epic" } })
	T.check(styleExplicit and styleExplicit.Rarity == "Epic", "p7vfx catalog: an explicit hybrid Rarity still wins over body / style", styleExplicit and tostring(styleExplicit.Rarity))
	local hybFirst = C.Unit({ key = "hyb:z", petId = "hyb:z", elements = { "Flame", "Storm" }, look = { Hybrid = true, BodyId = "storm_tabby" } })
	T.check(hybFirst and hybFirst.Element == "Flame", "p7vfx catalog: Unit takes the FIRST of several elements", hybFirst and tostring(hybFirst.Element))
	local hybExplicit = C.Unit({ key = "hyb:q", petId = "hyb:q", elements = { "Storm", "Flame" }, look = { Hybrid = true, BodyId = "storm_tabby", Rarity = "Mythic" } })
	T.check(hybExplicit and hybExplicit.Rarity == "Mythic", "p7vfx catalog: Unit uses an explicit look Rarity first (hybrid record)", hybExplicit and tostring(hybExplicit.Rarity))
	local infoRarity = C.Unit({ key = "hyb:r", petId = "hyb:r", rarity = "Epic", elements = { "Water" }, look = { Hybrid = true, BodyId = "storm_tabby" } })
	T.check(infoRarity and infoRarity.Rarity == "Epic", "p7vfx catalog: Unit uses an explicit unitInfo rarity first", infoRarity and tostring(infoRarity.Rarity))
	local plain = C.Unit({ key = "ember_phoenix@Golden", petId = "ember_phoenix", element = "Flame", elements = { "Flame" }, evo = 2, ranged = false })
	T.check(plain and plain.Rarity == "Legendary" and plain.Element == "Flame" and plain.Stage == 2 and plain.PetId == "ember_phoenix" and plain.Ranged == false,
		"p7vfx catalog: Unit on a catalogue pet = its rarity, element, evo stage, pet id, ranged flag")
	local keyOnly = C.Unit({ key = "stormfang@Rainbow", elements = { "Storm" } })
	T.check(keyOnly and keyOnly.Rarity == "Secret" and keyOnly.PetId == "stormfang", "p7vfx catalog: Unit falls back to the key's base pet id", keyOnly and tostring(keyOnly.Rarity))
	local odd = C.Unit({ evo = 7 })
	T.check(odd and odd.Rarity == "Common" and odd.Stage == 2 and odd.Element == nil and odd.Ranged == false,
		"p7vfx catalog: Unit on an unknown unit = Common, stage clamped, no element")
	T.check(C.Unit(nil) ~= nil, "p7vfx catalog: Unit(nil) does not error")

	-- Nature ranged: the petal trail, and nothing green-only (it must read on green grass)
	local nature = T.tally("p7vfx catalog: Nature ranged uses fx_petals (the trail from Uncommon up) and no green-only colour")
	for _, rarity in ipairs(RARITIES) do
		for _, mine in ipairs({ true, false }) do
			local r = C.Resolve({ Element = "Nature", Attack = "Ranged", Rarity = rarity, Stage = 0, Mine = mine })
			local hasPetals, trailPetals, green = false, false, {}
			for _, l in ipairs(r and r.Layers or {}) do
				if l.Texture == "fx_petals" then
					hasPetals = true
					if l.Id == "Trail" then
						trailPetals = true
					end
				end
				if greenOnly(l.Color) then
					green[#green + 1] = tostring(l.Id)
				end
			end
			if r and greenOnly(r.Core.Color) then
				green[#green + 1] = "Core"
			end
			if r and r.Alive and greenOnly(r.Alive.Color) then
				green[#green + 1] = "Alive"
			end
			nature:case(r ~= nil and hasPetals and (BAND[rarity] == 1 and rarity == "Common" or trailPetals) and #green == 0,
				fmt("%s: petals %s trail %s green %s", rarity, tostring(hasPetals), tostring(trailPetals), table.concat(green, ",")))
		end
	end
	nature:report()

	-- the spec's element table: each element's normal attacks use their own core + textures + alive detail
	local spec = {
		Flame = { melee = "vfx_crescent", ranged = "vfx_spear", trail = "fx_embers", alive = "SwirlUp" },
		Water = { melee = "vfx_crescent", ranged = "vfx_orb", trail = "fx_droplets", alive = "Bounce" },
		Frost = { melee = "vfx_spike", ranged = "vfx_shard", trail = "fx_snow", alive = "Melt" },
		Nature = { melee = "vfx_root", ranged = "vfx_orb", trail = "fx_petals", alive = "Wrap" },
		Earth = { melee = "vfx_spike", ranged = "vfx_chunk", trail = "fx_dust", alive = "Bounce" },
		Storm = { melee = "vfx_crescent", ranged = "vfx_shard", trail = "fx_sparks", alive = "Strike" },
		Celestial = { melee = "vfx_crescent", ranged = "vfx_star", trail = "fx_sparkle", alive = "Connect" },
		Shadow = { melee = "vfx_crescent", ranged = "vfx_orb", trail = "fx_wisps", alive = "Darken" },
	}
	local el = T.tally("p7vfx catalog: element normal attacks follow the spec table (melee / ranged core, trail, alive detail)")
	for _, element in ipairs(elements) do
		local s = spec[element]
		local m = C.Resolve({ Element = element, Attack = "Melee", Rarity = "Uncommon", Mine = true })
		local r = C.Resolve({ Element = element, Attack = "Ranged", Rarity = "Uncommon", Mine = true })
		local trail = nil
		for _, l in ipairs(r and r.Layers or {}) do
			if l.Id == "Trail" then
				trail = l.Texture
			end
		end
		el:case(s and m and r and m.Core.Key == s.melee and r.Core.Key == s.ranged and trail == s.trail and r.Alive.Motion == s.alive and r.Core.Path == "Projectile",
			fmt("%s: melee %s ranged %s trail %s alive %s", element, tostring(m and m.Core.Key), tostring(r and r.Core.Key), tostring(trail), tostring(r and r.Alive.Motion)))
	end
	el:report()
	local storm = C.Resolve({ Element = "Storm", Attack = "Ranged", Rarity = "Common", Mine = true })
	local bolt = false
	for _, l in ipairs(storm and storm.Layers or {}) do
		if l.Kind == "Beam" and l.Texture == "fx_lightning" then
			bolt = true
		end
	end
	T.check(bolt, "p7vfx catalog: Storm's ranged bolt is a fx_lightning Beam from Common up")

	-- Ruling 8: each element's OWN impact detail (spec Impact + Alive columns) shows at EVERY rarity, from Common, with a
	-- reduced count that grows by band; the ladder layers stay where the spec ladder puts them
	local detail = {
		Flame = { ids = { "Scorch", "Smoke" }, burst = "fx_flame", alive = "SwirlUp" },
		Water = { ids = { "Droplets", "Ripple" }, burst = "fx_splash", alive = "Bounce" },
		Frost = { ids = { "FrostRing", "FrostMist" }, burst = "fx_iceshards", alive = "Melt" },
		Nature = { melee = { "Thorns", "Leaves" }, ranged = { "RootBurst" }, burst = "fx_petals", alive = "Wrap" },
		Earth = { ids = { "Dust", "GroundCrack" }, burst = "fx_rock", alive = "Bounce" },
		Storm = { ids = { "ZigZag" }, burst = "fx_glow", alive = "Strike" },
		Celestial = { ids = { "Rays" }, burst = "fx_stars", alive = "Connect" },
		Shadow = { ids = { "Glass", "GlitchSparks" }, burst = "fx_voidring", alive = "Darken" },
	}
	local function layerById(r, id)
		for _, l in ipairs(r and r.Layers or {}) do
			if l.Id == id then
				return l
			end
		end
		return nil
	end
	local det = T.tally("p7vfx catalog: every element's Common Melee and Ranged recipes contain its own impact detail (burst, detail layers, alive)")
	local grow = T.tally("p7vfx catalog: the impact / alive detail starts reduced at Common and grows by band (Count Common < Secret)")
	for _, element in ipairs(elements) do
		local d = detail[element]
		for _, attack in ipairs({ "Melee", "Ranged" }) do
			local common = C.Resolve({ Element = element, Attack = attack, Rarity = "Common", Mine = true })
			local secret = C.Resolve({ Element = element, Attack = attack, Rarity = "Secret", Mine = true })
			local ids = d.ids or (attack == "Melee" and d.melee or d.ranged)
			local missing = {}
			for _, id in ipairs(ids) do
				local l = layerById(common, id)
				if not l then
					missing[#missing + 1] = id
				elseif l.Count ~= nil then
					local l2 = layerById(secret, id)
					grow:case(l2 ~= nil and l2.Count ~= nil and l.Count < l2.Count, fmt("%s %s %s: %s -> %s", element, attack, id, tostring(l.Count), tostring(l2 and l2.Count)))
				end
			end
			local burst = layerById(common, "Burst")
			det:case(common ~= nil and #missing == 0 and burst ~= nil and burst.Texture == d.burst and common.Alive.Motion == d.alive,
				fmt("%s %s Common: missing %s, burst %s, alive %s", element, attack, table.concat(missing, ","), tostring(burst and burst.Texture), tostring(common and common.Alive.Motion)))
			grow:case(common and secret and common.Alive.Count < secret.Alive.Count, fmt("%s %s alive %s -> %s", element, attack, tostring(common and common.Alive.Count), tostring(secret and secret.Alive.Count)))
		end
	end
	det:report()
	grow:report()

	-- the ladder layers join exactly where the spec ladder puts them (Melee / Ranged of every element)
	local LADDER_AT = { Charge = "Common", Burst = "Common", Trail = "Uncommon", Slash = "Rare", GroundGlow = "Rare", Shockwave = "Epic", Flash = "Epic",
		Afterimage = "Legendary", Bloom = "Legendary", DoubleArc = "Mythic", Field = "Mythic", PlasmaRim = "Secret" }
	local rarityIndex = {}
	for i, r in ipairs(RARITIES) do
		rarityIndex[r] = i
	end
	local lad = T.tally("p7vfx catalog: ladder layers first appear at their spec rarity (Uncommon trail ... Secret rim); no other layer is gated by rarity")
	for _, element in ipairs(elements) do
		for _, attack in ipairs({ "Melee", "Ranged" }) do
			local first = {}
			for _, rarity in ipairs(RARITIES) do
				local r = C.Resolve({ Element = element, Attack = attack, Rarity = rarity, Mine = true })
				for _, l in ipairs(r and r.Layers or {}) do
					if first[l.Id] == nil then
						first[l.Id] = rarity
					end
				end
			end
			for id, at in pairs(first) do
				local want = LADDER_AT[id] or "Common"
				lad:case(at == want, fmt("%s %s: %s first at %s (want %s)", element, attack, id, at, want))
			end
			for id in pairs(LADDER_AT) do
				lad:case(first[id] ~= nil, fmt("%s %s: ladder layer %s missing", element, attack, id))
			end
		end
	end
	lad:report()

	-- review minors: Water's droplets + geyser, Shadow's implosion before the glass, Nature's root burst as playable layers
	local water = C.Resolve({ Element = "Water", Attack = "Melee", Rarity = "Common", Mine = true })
	local wb, wd = layerById(water, "Burst"), layerById(water, "Droplets")
	T.check(wb and wb.Texture == "fx_splash" and wb.Motion == "Geyser" and wd and wd.Texture == "fx_droplets" and wd.Kind == "Emitter",
		"p7vfx catalog: Water's impact = a Geyser fx_splash burst + fx_droplets droplets")
	local shadow = C.Resolve({ Element = "Shadow", Attack = "Ranged", Rarity = "Common", Mine = true })
	local sb, sg = layerById(shadow, "Burst"), layerById(shadow, "Glass")
	T.check(sb and sb.Texture == "fx_voidring" and sb.Motion == "Implode" and sg and sg.Texture == "fx_darkglass" and finiteNum(sg.Delay) and sg.Delay > 0,
		"p7vfx catalog: Shadow's impact = the fx_voidring Implode burst, then the fx_darkglass shatter (Delay > 0)")
	local natureR = C.Resolve({ Element = "Nature", Attack = "Ranged", Rarity = "Common", Mine = true })
	local rb = layerById(natureR, "RootBurst")
	T.check(rb and rb.Kind == "Mesh" and rb.Key == "vfx_root" and rb.Motion == "Erupt" and rb.Texture == nil,
		"p7vfx catalog: Nature's ranged root burst is a vfx_root Mesh layer that erupts")

	-- the Shield shell and the Freeze cage stay Glass at every band (other cores follow the band)
	local glass = T.tally("p7vfx catalog: Shield shell / Freeze cage cores are Glass at every rarity; other band-4 cores are Neon")
	for _, element in ipairs(elements) do
		for _, rarity in ipairs(RARITIES) do
			for _, kind in ipairs({ "Shield", "Freeze" }) do
				local r = C.Resolve({ Element = element, Attack = "Special", Kind = kind, Rarity = rarity, Mine = true })
				glass:case(r and r.Core.Material == "Glass", fmt("%s %s %s: %s", element, kind, rarity, tostring(r and r.Core.Material)))
			end
		end
		local blast = C.Resolve({ Element = element, Attack = "Special", Kind = "Blast", Rarity = "Secret", Mine = true })
		glass:case(blast and blast.Core.Material == "Neon", element .. " Secret Blast core " .. tostring(blast and blast.Core.Material))
	end
	glass:report()
	local hyd = C.Resolve({ Element = "Shadow", Attack = "Special", Kind = "Rally", Rarity = "Secret", PetId = "hydralotl", Mine = true })
	T.check(hyd and hyd.Sig and hyd.Sig.Actor and hyd.Sig.Actor.At == "Behind", "p7vfx catalog: Hydralotl's serpents rise Behind the pet (a documented At)")
end)

return S
