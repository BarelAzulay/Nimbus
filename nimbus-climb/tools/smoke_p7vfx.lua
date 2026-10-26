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
--   p7vfx_poses (pure) shared/PetPoses (Task 5): every pose at p = 0 / 0.25 / 0.5 / 1 (melee and ranged) is finite,
--               the one-shot poses start and end at rest (Ko ends on its side, PetPoses.Holds), the shapes (crouch,
--               lunge 1.5 / ranged kick 0.35, rise 0.6, flinch + shut lids, 90 deg tumble, hop 1.2 + 360 deg spin,
--               0.05 breathing + glances every 2-4 s), no pops (fine-step continuity); PetBuilder.Animate with
--               opts.Pose on real builds (stage 0 / 2, winged + tailed) moves WingL / Tail, keeps the wings mirrored,
--               shuts the lids, returns to the exact unposed frame without Pose, creates no Instances; PoseBody.
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
-- fix round 3: elements whose recipes still go over the 6-emitter budget (the engine cap trims them by rank). Task 9
-- retuned Water / Frost / Earth: none is pending now, every recipe must fit
local EMITTER_PENDING = {}
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
-- AttackFx's emitter rule (isEmitter): an Emitter layer, or a Decal WITH a texture (drawn as a flat particle sheet);
-- an untextured Decal is the glow Disc (no emitter). Counts the layers + the alive detail (fix round 3, review
-- Important 1: the old count missed textured Decals, so Flame's textured Scorch pushed recipes past the cap unseen)
local function isEmitterLayer(l)
	return type(l) == "table" and (l.Kind == "Emitter" or (l.Kind == "Decal" and type(l.Texture) == "string"))
end

local function emitterCount(r)
	local n = 0
	for _, l in ipairs(type(r) == "table" and type(r.Layers) == "table" and r.Layers or {}) do
		if isEmitterLayer(l) then
			n = n + 1
		end
	end
	if type(r) == "table" and isEmitterLayer(r.Alive) then
		n = n + 1
	end
	return n
end

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
	local ids = {}
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
	-- fix round 3 (review Important 1): every recipe fits AttackFx's 6-emitter budget (MAX_EMITTERS.High), counted by the
	-- engine's rule (textured Decals are emitters). (Task 9 retuned every element; EMITTER_PENDING stays as the hook for a future over-budget element):
	-- until then the engine cap (Burst, then Impact, Slash, Travel, Alive first) trims them at run time; they are listed as a warning
	local budget = T.tally("p7vfx catalog: every recipe fits the 6-emitter budget (engine rule: Emitters + textured Decals + an emitter Alive)")
	local overPending = {}
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
							local ne = emitterCount(r)
							if ne > 6 and EMITTER_PENDING[element] then
								local o = overPending[element] or { N = 0, Worst = 0, Kinds = {} }
								overPending[element] = o
								o.N, o.Worst, o.Kinds[v.label] = o.N + 1, math.max(o.Worst, ne), true
							else
								budget:case(ne <= 6, fmt("%s: %d emitters", label, ne))
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
	budget:report()
	local pend, pendN = {}, 0
	for element, o in pairs(overPending) do
		local kinds = {}
		for k in pairs(o.Kinds) do
			kinds[#kinds + 1] = k
		end
		table.sort(kinds)
		pend[#pend + 1] = fmt("%s: %d recipes (max %d emitters; %s)", element, o.N, o.Worst, table.concat(kinds, ", "))
		pendN = pendN + o.N
	end
	if pendN > 0 then
		table.sort(pend)
		T.warn("p7vfx catalog: Task 9 pending: " .. pendN .. " recipes over the 6-emitter budget (the engine cap trims them)", table.concat(pend, " | "))
	end

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

	-- travel by distance: 60 studs/s for the Blast orb; a basic ranged shot flies at RangedSpeed (34) and never less
	-- than MinTravel (0.24 s: player note 1, the shot is seen crossing the gap), capped; impact = Charge + Release + Travel
	local blastNear = C.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", Rarity = "Rare", Distance = 6 })
	T.check(blastNear and math.abs(blastNear.Beats.Travel - 0.1) < 1e-6 and blastNear.Beats.MinTravel == nil,
		"p7vfx catalog: the Blast orb's Travel = distance / 60 studs/s (no MinTravel)", blastNear and fmt("%.3f", blastNear.Beats.Travel))
	local near = C.Resolve({ Element = "Flame", Attack = "Ranged", Rarity = "Rare", Distance = 6 })
	local mid = C.Resolve({ Element = "Flame", Attack = "Ranged", Rarity = "Rare", Distance = 12 })
	local far = C.Resolve({ Element = "Flame", Attack = "Ranged", Rarity = "Rare", Distance = 600 })
	T.check(C.Beats.RangedSpeed == 34 and C.Beats.MinTravel == 0.24 and near and mid and far
		and math.abs(near.Beats.Travel - 0.24) < 1e-6 and math.abs(mid.Beats.Travel - 12 / 34) < 1e-6
		and math.abs(far.Beats.Travel - 0.5) < 1e-9 and near.Beats.MinTravel == 0.24,
		"p7vfx catalog: a ranged shot's Travel = distance / 34 studs/s, at least MinTravel 0.24 s, capped at 0.5 s",
		near and mid and far and fmt("%.3f / %.3f / %.3f", near.Beats.Travel, mid.Beats.Travel, far.Beats.Travel))
	local stormShot = C.Resolve({ Element = "Storm", Attack = "Ranged", Rarity = "Rare", Distance = 12 })
	T.check(stormShot and math.abs(stormShot.Beats.Travel - 0.24) < 1e-6, "p7vfx catalog: a fast element shot (Storm's bolt, 120 studs/s) still flies MinTravel",
		stormShot and fmt("%.3f", stormShot.Beats.Travel))
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
				sigOk:case(p == "" and emitterCount(r) <= 6 and sum <= 3.5 and s.Element == def.Element and s.Kind == kind and r.Band == C.BandOf(def.Rarity),
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
		Flame = { melee = { "Scorch", "Smoke" }, ranged = { "Scorch", "Mantle" }, burst = "fx_flame", alive = "SwirlUp" }, -- (Task 8: the shot wears its flame mantle, no smoke)
		Water = { ids = { "Ripple" }, burst = "fx_splash", alive = "Bounce" }, -- (Task 9 budget: the droplets are the alive bounce)
		Frost = { ids = { "FrostRing", "FrostMist" }, burst = "fx_iceshards", alive = "Melt" },
		Nature = { melee = { "Thorns", "Pollen" }, ranged = { "RootBurst" }, burst = "fx_petals", alive = "Wrap" }, -- (Task 9: green leaves -> golden pollen, read on grass)
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
		Afterimage = "Legendary", Bloom = "Legendary", DoubleArc = "Mythic", Field = "Mythic", PlasmaRim = "Secret",
		MuzzleRing = "Rare", ShotArcs = "Mythic", ShotAfterimage = "Legendary" } -- (Ranged: Slash -> MuzzleRing, DoubleArc ->
	-- ShotArcs, Afterimage -> ShotAfterimage, player note 1)
	local SWAPPED = { Ranged = { Slash = "MuzzleRing", DoubleArc = "ShotArcs", Afterimage = "ShotAfterimage" }, Melee = {} }
	-- fix round 3 (player note b): the Ranged explosion's own flash (BoomFlash, from Common) replaces the Epic Flash
	local SKIPPED = { Ranged = { Flash = true }, Melee = {} }
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
				local swappedIn, swappedOut = false, SWAPPED[attack][id] ~= nil
				for _, to in pairs(SWAPPED[attack]) do
					swappedIn = swappedIn or to == id
				end
				local ownSwap = (id == "MuzzleRing" or id == "ShotArcs" or id == "ShotAfterimage")
				if swappedOut or (ownSwap and not swappedIn) or SKIPPED[attack][id] then
					lad:case(first[id] == nil, fmt("%s %s: %s is not drawn (swapped / not this attack's)", element, attack, id))
				else
					lad:case(first[id] ~= nil, fmt("%s %s: ladder layer %s missing", element, attack, id))
				end
			end
		end
	end
	lad:report()

	-- player note 1: Ranged is a shot across the gap, never a swing; Melee stays the close swipe
	local shot = T.tally("p7vfx catalog: every element's Ranged is a shot (a Projectile core, MinTravel kept, a travel layer from caster to target, a muzzle at the mouth, no crescent) and Melee is unchanged")
	for _, element in ipairs(elements) do
		for _, rarity in ipairs(RARITIES) do
			local r = C.Resolve({ Element = element, Attack = "Ranged", Rarity = rarity, Mine = true })
			local travel, muzzle, crescent, tether = false, false, false, false
			for _, l in ipairs(r and r.Layers or {}) do
				if l.Kind == "Trail" and l.At == "Core" and not (type(l.Lifetime) == "number" and l.Lifetime <= 0.1) then
					tether = true -- (Task 8: a trail on the shot is a short comet tail, never a tether back to the mouth)
				end
				if l.Beat == "Travel" and (l.At == "Core" or l.At == "Path") then
					travel = true -- the Core rides the shot from the mouth to the target; Path = mouth -> target
				end
				if l.Beat == "Release" and l.At == "Source" and (l.Id == "Muzzle" or l.Id == "MuzzleRing") then
					muzzle = true
				end
				if l.Id == "Slash" or l.Id == "DoubleArc" then
					crescent = true
				end
			end
			local b = r and r.Beats or {}
			shot:case(r ~= nil and r.Core.Path == "Projectile" and not r.Core.Stretch and finiteNum(r.Core.Speed) and b.MinTravel == C.Beats.MinTravel
				and b.Travel >= b.MinTravel - 1e-9 and layerById(r, "Streak") ~= nil and layerById(r, "Streak").Kind == "Trail" and travel and muzzle and not crescent
				and not tether,
				fmt("%s Ranged %s: path %s, travel %.2f, min %s, travel layer %s, muzzle %s, crescent %s, tether %s", element, rarity, tostring(r and r.Core.Path),
					b.Travel or -1, tostring(b.MinTravel), tostring(travel), tostring(muzzle), tostring(crescent), tostring(tether)))
			local m = C.Resolve({ Element = element, Attack = "Melee", Rarity = rarity, Mine = true })
			local own = false
			for _, l in ipairs(m and m.Layers or {}) do
				own = own or l.Id == "Muzzle" or l.Id == "Streak" or l.Id == "MuzzleRing" or l.Id == "ShotArcs" or l.Id == "ShotAfterimage"
					or l.Id == "Boom" or l.Id == "BoomRing" or l.Id == "BoomFlash"
			end
			local band = C.BandOf(rarity)
			local wantSlash = band >= 2
			local mb = m and m.Beats or {}
			shot:case(m ~= nil and m.Beats.MinTravel == nil and not own and (layerById(m, "Slash") ~= nil) == wantSlash
				and (m.Core.Path == "Swipe" or m.Core.Path == "Ground") and math.abs((mb.Travel or -1) - ((m.Core.Path == "Ground") and 0.15 or 0.1)) < 1e-9,
				fmt("%s Melee %s: path %s, travel %.2f, slash %s, ranged layers %s", element, rarity, tostring(m and m.Core.Path), mb.Travel or -1,
					tostring(layerById(m, "Slash") ~= nil), tostring(own)))
		end
	end
	shot:report()

	-- fix round 3, player note (b): every element's ranged impact EXPLODES: a flash (BoomFlash), a bigger burst of the
	-- element's own particles (Burst Count / Size boosted over Melee's) and a pop + shockwave ring (Boom, BoomRing), all
	-- non-emitter solids (no emitter budget), sized by the band (Size <= 1.4), <= 3 lights, no Epic Flash on top
	-- (Task 9: Water's shot explodes as its boosted geyser splash, not a pop ball: the ball read as a shield bubble.
	-- Water drops the Boom (Ranged.Drop); every other element keeps it)
	local NO_POP = { Water = true }
	local boom = T.tally("p7vfx catalog: every element x rarity Ranged impact explodes (Boom pop (Water: its geyser) + BoomRing shock + BoomFlash light, burst bigger than Melee's, <= 3 lights, no Flash); Melee has none")
	for _, element in ipairs(elements) do
		local prevSize = 0
		for _, rarity in ipairs(RARITIES) do
			local r = C.Resolve({ Element = element, Attack = "Ranged", Rarity = rarity, Mine = true })
			local m = C.Resolve({ Element = element, Attack = "Melee", Rarity = rarity, Mine = true })
			local b, rg, fl = layerById(r, "Boom"), layerById(r, "BoomRing"), layerById(r, "BoomFlash")
			local rb, mb = layerById(r, "Burst"), layerById(m, "Burst")
			local lights = 0
			for _, l in ipairs(r and r.Layers or {}) do
				if l.Kind == "Light" then
					lights = lights + 1
				end
			end
			local bigger = rb ~= nil and mb ~= nil and rb.Texture == mb.Texture and (rb.Size or 1) > (mb.Size or 1) and (rb.Count or 1) > (mb.Count or 1)
			local popOk = NO_POP[element] and (b == nil and rb ~= nil and rb.Motion == "Geyser") or (b ~= nil and b.Kind == "Ring" and b.Pop == true and rb ~= nil and b.At == rb.At and b.Beat == "Impact")
			boom:case(r ~= nil and popOk
				and rg ~= nil and rg.Kind == "Ring" and rg.At == "Ground" and rg.Beat == "Impact"
				and fl ~= nil and fl.Kind == "Light" and fl.Beat == "Impact"
				and layerById(r, "Flash") == nil and lights <= 3 and bigger and r.Size <= 1.4 + 1e-9 and r.Size >= prevSize
				and layerById(m, "Boom") == nil and layerById(m, "BoomRing") == nil and layerById(m, "BoomFlash") == nil,
				fmt("%s Ranged %s: boom %s ring %s flash %s, Flash %s, lights %d, burst %s/%s vs melee %s/%s, size %.2f",
					element, rarity, tostring(b ~= nil), tostring(rg ~= nil), tostring(fl ~= nil), tostring(layerById(r, "Flash") ~= nil), lights,
					tostring(rb and rb.Count), tostring(rb and rb.Size), tostring(mb and mb.Count), tostring(mb and mb.Size), r and r.Size or -1))
			prevSize = r and r.Size or prevSize
		end
	end
	boom:report()
	local fr = C.Resolve({ Element = "Flame", Attack = "Ranged", Rarity = "Common", Mine = true })
	local frm, frmu = layerById(fr, "Mantle"), layerById(fr, "Muzzle")
	T.check(fr and fr.Core.Key == "vfx_spear" and frm and frm.Texture == "fx_flame" and frm.Beat == "Travel" and frm.At == "Core"
		and frmu and frmu.Texture == "fx_flame" and layerById(fr, "Burst") and layerById(fr, "Burst").Texture == "fx_flame",
		"p7vfx catalog: Flame's ranged shot = a flame spear wrapped in fire (Mantle) with a flame muzzle puff and a fire burst")

	-- Task 9 (Studio, two rounds): band 4's white plasma is the HEART: every element's Secret shot / swipe core is a shell
	-- of the element's colour (Palette.Mid) round a white-hot inner core (Earth: its PlasmaColor, gold), never a white shell;
	-- the ground cores (spikes, roots) stay in the element's colour too. The slash arc + the double arcs are half-lit (an
	-- additive sheet summed to white on the pale arena)
	local plasmaBad = {}
	for _, element in ipairs(Config.Elements.Order) do
		local pal = C.Elements[element].Palette
		local heart = C.Elements[element].PlasmaColor and pal[C.Elements[element].PlasmaColor] or Color3.new(1, 1, 1)
		for _, attack in ipairs({ "Melee", "Ranged" }) do
			local r = C.Resolve({ Element = element, Attack = attack, Rarity = "Secret", Mine = true })
			local core = r and r.Core
			local ok = core and core.Color == pal.Mid and core.RimShift == true
			if ok and (core.Path == "Projectile" or core.Path == "Swipe") then
				ok = core.InnerColor == heart
			end
			local sl, da = r and layerById(r, "Slash"), r and layerById(r, "DoubleArc")
			if attack == "Melee" and not (sl and da and sl.LightEmission <= 0.5 and da.LightEmission <= 0.5 and (da.Color == pal.Mid or (C.Textures[da.Texture] and C.Textures[da.Texture].Baked))) then
				ok = false
			end
			if not ok then
				plasmaBad[#plasmaBad + 1] = element .. " " .. attack
			end
		end
	end
	T.check(#plasmaBad == 0, "p7vfx catalog: band 4 = an element-colour shell round a white-hot heart (no white shell), half-lit slash / double arcs", table.concat(plasmaBad, ", "))

	-- review minors: Water's droplets + geyser, Shadow's implosion before the glass, Nature's root burst as playable layers
	local water = C.Resolve({ Element = "Water", Attack = "Melee", Rarity = "Common", Mine = true })
	local wb, wr = layerById(water, "Burst"), layerById(water, "Ripple")
	T.check(wb and wb.Texture == "fx_splash" and wb.Motion == "Geyser" and wr and wr.Texture == "fx_ripple" and water.Alive.Texture == "fx_droplets"
		and water.Alive.Motion == "Bounce" and water.Alive.Kind == "Emitter",
		"p7vfx catalog: Water's impact = a Geyser fx_splash burst + the fx_ripple ring, the fx_droplets bouncing (alive)")
	-- Task 9 (Studio + Gemini: the Water explosion read as a shield bubble round the target): the geyser erupts from the
	-- GROUND under the target and its splash sheets are see-through
	local wsec = C.Resolve({ Element = "Water", Attack = "Ranged", Rarity = "Secret", Mine = true })
	local wsb, wsr = layerById(wsec, "Burst"), layerById(wsec, "Ripple")
	T.check(wsb and wsb.At == "Ground" and (wsb.Transparency or 0) >= 0.3 and wsr ~= nil,
		"p7vfx catalog: Water's shot explodes as a see-through geyser from the ground (not a bubble)")
	-- Task 9 (Studio + Gemini: the Secret Frost shatter was a white blob that swallowed the target; the spikes read as
	-- plastic): a see-through, half-lit shatter; see-through ice spikes on the melee and the element attack
	local fr = C.Resolve({ Element = "Frost", Attack = "Ranged", Rarity = "Secret", Mine = true })
	local fm = C.Resolve({ Element = "Frost", Attack = "Melee", Rarity = "Secret", Mine = true })
	local fa = C.Resolve({ Element = "Frost", Attack = "Element", Shape = "Cone", Rarity = "Secret", Mine = true })
	local fb = fr and layerById(fr, "Burst")
	T.check(fb and (fb.Transparency or 0) >= 0.2 and (fb.LightEmission or 1) <= 0.5 and fm and (fm.Core.Transparency or 0) >= 0.15
		and fa and fa.Core.Key == "vfx_spike" and (fa.Core.Transparency or 0) >= 0.15,
		"p7vfx catalog: Frost's shatter is see-through and half-lit, its ice spikes see-through (melee + element attack)")
	-- Task 9 (Studio + Gemini: Nature's Secret roots / vines drew white-cream ghosts, then neon-yellow "electricity"): the
	-- roots, the root burst and the wrap vines are rose (Mid), Mid and Edge are saturated (not pale), the roots see-through
	local npal = C.Elements.Nature.Palette
	local function saturated(c) return c and math.min(c.R, c.G, c.B) <= 0.5 end
	local nm = C.Resolve({ Element = "Nature", Attack = "Melee", Rarity = "Secret", Mine = true })
	local nr = C.Resolve({ Element = "Nature", Attack = "Ranged", Rarity = "Secret", Mine = true })
	local na = C.Resolve({ Element = "Nature", Attack = "Element", Shape = "Circle", Rarity = "Secret", Mine = true })
	local nrb = nr and layerById(nr, "RootBurst")
	T.check(saturated(npal.Mid) and saturated(npal.Edge) and nm and nm.Alive and nm.Alive.Color == npal.Mid and nrb and nrb.Color == npal.Mid
		and (nm.Core.Transparency or 0) >= 0.15 and na and na.Core.Key == "vfx_root" and (na.Core.Transparency or 0) >= 0.15,
		"p7vfx catalog: Nature's roots / root burst / wrap vines are rose, its Mid and Edge saturated, the roots see-through")
	-- Task 9 (Studio + Gemini: the Shatter's drag held Earth's chunks in a ball that read as a boulder on the target): the
	-- chunk burst is flung further (SpeedScale), so the rock breaks outward
	local er = C.Resolve({ Element = "Earth", Attack = "Ranged", Rarity = "Secret", Mine = true })
	local eb = er and layerById(er, "Burst")
	T.check(eb and eb.Texture == "fx_rock" and eb.Motion == "Shatter" and (eb.SpeedScale or 1) >= 1.5,
		"p7vfx catalog: Earth's rock burst is flung outward (SpeedScale), not a boulder over the target")
	-- Task 9 (Studio, Storm c2: a fully additive fx_glow muzzle puff was a white glare at the mouth): the ranged Muzzle
	-- puff of the element's Burst sheet takes the element's BurstLight, like the Burst
	local muzzleBad = {}
	for _, element in ipairs(Config.Elements.Order) do
		local e = C.Elements[element]
		local r = C.Resolve({ Element = element, Attack = "Ranged", Rarity = "Secret", Mine = true })
		local mz = r and layerById(r, "Muzzle")
		if type(e.BurstLight) == "number" and mz and mz.Texture == e.Burst and mz.LightEmission ~= e.BurstLight then
			muzzleBad[#muzzleBad + 1] = element
		end
	end
	T.check(#muzzleBad == 0, "p7vfx catalog: a ranged Muzzle puff of the Burst sheet is lit like the element's Burst (BurstLight)",
		table.concat(muzzleBad, ","))
	-- Task 9 round 3 (Studio + Gemini, Storm c2: the 2.6-wide bolt strip was a scribble band on the floor, the sparks a
	-- white ball, the Secret area cores solid slabs over the lightning)
	local spal = C.Elements.Storm.Palette
	local ss = C.Resolve({ Element = "Storm", Attack = "Ranged", Rarity = "Secret", Mine = true })
	local sbolt, szig = ss and layerById(ss, "Bolt"), ss and layerById(ss, "ZigZag")
	local sline = C.Resolve({ Element = "Storm", Attack = "Element", Shape = "Line", Rarity = "Secret", Mine = true })
	local slb = sline and layerById(sline, "Bolt")
	T.check(sbolt and sbolt.Width <= 1.5 and szig and szig.Color == spal.Mid and (szig.LightEmission or 1) <= 0.6
		and sline and (sline.Core.Transparency or 0) >= 0.4 and slb and slb.Width <= 1.5,
		"p7vfx catalog: Storm's bolt is a narrow strip, its sparks the storm blue half-lit, its area cores see-through")

	-- Task 9: a template's Except matches the RESOLVED kind: a signature special asked with Kind nil (Ember Phoenix's
	-- Phoenix Flare is a Blast) still leaves out Flame's Smoke (Except Blast), like the same Blast asked by name
	local sigNil = C.Resolve({ Element = "Flame", Attack = "Special", PetId = "ember_phoenix", Rarity = "Legendary", Mine = true })
	local sigNamed = C.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", PetId = "ember_phoenix", Rarity = "Legendary", Mine = true })
	local plainStorm = C.Resolve({ Element = "Flame", Attack = "Special", Kind = "Beam", Rarity = "Legendary", Mine = true })
	T.check(sigNil and sigNil.Kind == "Blast" and layerById(sigNil, "Smoke") == nil and sigNamed and layerById(sigNamed, "Smoke") == nil
		and plainStorm and layerById(plainStorm, "Smoke") ~= nil,
		"p7vfx catalog: Except matches the resolved kind (a signature Blast with Kind nil leaves out Flame's Smoke; a Beam keeps it)")

	-- Task 9: Low quality's 2 emitters are chosen on purpose: the Burst + the element's most characteristic emitter
	-- (recipe.LowKeep, the kind's / attack's pick first); every element's Melee and Ranged have one of them, at every rarity
	local lowBad = {}
	local function isEm(l)
		return type(l) == "table" and (l.Kind == "Emitter" or (l.Kind == "Decal" and type(l.Texture) == "string"))
	end
	for _, element in ipairs(Config.Elements.Order) do
		for _, attack in ipairs({ "Melee", "Ranged" }) do
			for _, rarity in ipairs(RARITIES) do
				local r = C.Resolve({ Element = element, Attack = attack, Rarity = rarity, Mine = true })
				local found = nil
				for _, id in ipairs(r and r.LowKeep or {}) do
					if not found then
						if id == "Alive" and isEm(r.Alive) then
							found = id
						end
						local l = layerById(r, id)
						if l and isEm(l) then
							found = id
						end
					end
				end
				if not (r and type(r.LowKeep) == "table" and found and found ~= "Burst") then
					lowBad[#lowBad + 1] = fmt("%s %s %s: LowKeep %s", element, attack, rarity, r and table.concat(r.LowKeep or {}, ",") or "?")
				end
			end
		end
	end
	T.check(#lowBad == 0, "p7vfx catalog: every element's Melee / Ranged names its Low-quality emitter (LowKeep) and has it", table.concat(lowBad, " | "))
	local stormLow = C.Resolve({ Element = "Water", Attack = "Special", Kind = "Storm", Rarity = "Rare", Mine = true })
	T.check(stormLow and stormLow.LowKeep[1] == "Cloud" and stormLow.LowKeep[2] == "Ripple", "p7vfx catalog: a kind's Low pick comes before the element's (Storm: the cloud)",
		stormLow and table.concat(stormLow.LowKeep, ","))

	-- Task 9 player decision: the melee leap lands on the target, so a long gap gives it more air time (LeapTravel): the
	-- base travel at battle range (centre ~4 studs), longer in the /fx preview (10 studs), capped; no Distance = the base
	local function meleeTravel(element, d)
		local r = C.Resolve({ Element = element, Attack = "Melee", Rarity = "Common", Mine = true, Distance = d })
		return r and r.Beats.Travel or -1
	end
	T.check(math.abs(meleeTravel("Flame", 4) - 0.1) < 1e-9 and math.abs(meleeTravel("Flame", 10) - 0.22) < 1e-9 and math.abs(meleeTravel("Flame", 60) - 0.24) < 1e-9
		and math.abs(meleeTravel("Frost", 10) - 0.27) < 1e-9 and math.abs(meleeTravel("Flame", nil) - 0.1) < 1e-9,
		"p7vfx catalog: melee Travel grows with the gap past 4 studs (0.02 s/stud, +0.14 s max): the leap's air time",
		fmt("4: %.3f, 10: %.3f, 60: %.3f, frost 10: %.3f", meleeTravel("Flame", 4), meleeTravel("Flame", 10), meleeTravel("Flame", 60), meleeTravel("Frost", 10)))
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

----------------------------------------------------------------------
-- p7vfx_poses: shared/PetPoses (Task 5) and the PetBuilder.Animate rig hook (opts.Pose, PetBuilder.PoseBody)
----------------------------------------------------------------------
local POSE_NAMES = { "Windup", "Strike", "Shoot", "Recoil", "Cast", "Hurt", "Ko", "Victory", "IdleBattle" }

local function cfFinite(cf)
	if typeof(cf) ~= "CFrame" then
		return false
	end
	for _, v in ipairs({ cf:GetComponents() }) do
		if not finiteNum(v) then
			return false
		end
	end
	return true
end

-- rotation angle (radians) of a CFrame
local function angleOf(cf)
	local _, a = cf:ToAxisAngle()
	return a
end

local function isIdentity(cf, eps)
	eps = eps or 1e-4
	return cfFinite(cf) and cf.Position.Magnitude < eps and angleOf(cf) < eps * 10
end

-- how far a pose moved the pet along its own LookVector (pets face -Z: PetBuilder header)
local function forwardOf(cf)
	return -cf.Position.Z
end

local function sampleOk(s)
	if type(s) ~= "table" or not cfFinite(s.Body) or type(s.Groups) ~= "table" or not finiteNum(s.Lids) or s.Lids < 0 or s.Lids > 1 then
		return false
	end
	for _, g in pairs(s.Groups) do
		if not cfFinite(g) then
			return false
		end
	end
	return s.Still == nil or (finiteNum(s.Still) and s.Still >= 0 and s.Still <= 1)
end

-- the extreme of fn(sample) over p in [a, b] (steps of 0.005)
local function extreme(P, name, ranged, fn, useMax, a, b)
	local best = nil
	for i = math.floor((a or 0) * 200 + 0.5), math.floor((b or 1) * 200 + 0.5) do
		local v = fn(P.Sample(name, i / 200, ranged))
		if best == nil or (useMax and v > best) or (not useMax and v < best) then
			best = v
		end
	end
	return best
end

local function deg(r)
	return r * 180 / math.pi
end

-- yaw (degrees) of a CFrame's LookVector, 0 = straight ahead
local function yawOf(cf)
	local look = cf.LookVector
	return deg(math.atan2(-look.X, -look.Z))
end

S.p7vfx_poses = guarded("p7vfx_poses", function()
	local P = sharedModule("PetPoses")
	if not T.check(P ~= nil and type(P.Sample) == "function" and type(P.Names) == "table", "p7vfx poses: shared/PetPoses loads (Names, Sample)") then
		return
	end
	local namesOk = #P.Names == #POSE_NAMES
	for i, n in ipairs(POSE_NAMES) do
		namesOk = namesOk and P.Names[i] == n
	end
	T.check(namesOk, "p7vfx poses: PetPoses.Names = Windup, Strike, Shoot, Recoil, Cast, Hurt, Ko, Victory, IdleBattle (in order)")
	local loops = P.Loops or {}
	local holds = P.Holds or {}
	T.check(loops.IdleBattle == true and holds.Ko == true, "p7vfx poses: IdleBattle loops (p = time), Ko holds its downed end pose")

	-- every pose, melee and ranged, at the sample points: finite CFrames, Lids in 0..1
	local fin = T.tally("p7vfx poses: every pose at p = 0 / 0.25 / 0.5 / 1 (melee + ranged) returns finite CFrames, Lids 0..1")
	for _, name in ipairs(POSE_NAMES) do
		for _, ranged in ipairs({ false, true }) do
			for _, p in ipairs({ 0, 0.25, 0.5, 1 }) do
				fin:case(sampleOk(P.Sample(name, p, ranged)), fmt("%s p=%.2f ranged=%s", name, p, tostring(ranged)))
			end
		end
	end
	fin:report()
	local unknown = P.Sample("Nope", 0.5)
	T.check(sampleOk(unknown) and isIdentity(unknown.Body) and unknown.Lids == 0, "p7vfx poses: an unknown pose name = rest (identity)")
	T.check(sampleOk(P.Sample("Strike", 0 / 0)) and sampleOk(P.Sample("Strike", nil)) and sampleOk(P.Sample("Strike", 7))
		and sampleOk(P.Sample("IdleBattle", -3.5)) and sampleOk(P.Sample("IdleBattle", 1e6)), "p7vfx poses: NaN / nil / out-of-range p stay finite")

	-- one-shot poses: rest at p = 0 and p = 1 (Ko: rest at 0, its downed pose at 1)
	local rest = T.tally("p7vfx poses: one-shot poses are at rest at p = 0 and p = 1 (body, groups, lids, stillness)")
	for _, name in ipairs(POSE_NAMES) do
		if not loops[name] then
			for _, ranged in ipairs({ false, true }) do
				for _, p in ipairs({ 0, 1 }) do
					if not (p == 1 and holds[name]) then
						local s = P.Sample(name, p, ranged)
						local ok = isIdentity(s.Body) and s.Lids == 0 and (s.Still or 0) == 0
						for _, g in pairs(s.Groups) do
							ok = ok and isIdentity(g)
						end
						rest:case(ok, fmt("%s p=%d ranged=%s", name, p, tostring(ranged)))
					end
				end
			end
		end
	end
	rest:report()

	-- no pops: neighbouring samples (dp = 0.005; the loop: dt = 0.005 s over 12 s) stay close
	local smooth = T.tally("p7vfx poses: no pops (each 0.005 step moves the body < 0.2 studs / 0.2 rad, each group < 0.2 rad)")
	for _, name in ipairs(POSE_NAMES) do
		for _, ranged in ipairs({ false, true }) do
			local prev, worstPos, worstAng, worstGrp = nil, 0, 0, 0
			local span = loops[name] and 2400 or 200
			for i = 0, span do
				local s = P.Sample(name, i / 200, ranged)
				if prev then
					worstPos = math.max(worstPos, (s.Body.Position - prev.Body.Position).Magnitude)
					worstAng = math.max(worstAng, angleOf(prev.Body:Inverse() * s.Body))
					for k, g in pairs(s.Groups) do
						local g0 = prev.Groups[k]
						if g0 then
							worstGrp = math.max(worstGrp, angleOf(g0:Inverse() * g))
						end
					end
				end
				prev = s
			end
			smooth:case(worstPos < 0.2 and worstAng < 0.2 and worstGrp < 0.2,
				fmt("%s ranged=%s: worst step %.3f studs, %.3f rad body, %.3f rad group", name, tostring(ranged), worstPos, worstAng, worstGrp))
		end
	end
	smooth:report()

	-- the shapes (brief: Windup crouch 0.25, wings back 25, tail up; Strike lunge 1.5 / ranged recoil 0.35, wings open
	-- 35; Cast rise 0.6, wings spread 50; Hurt squash + flinch 0.3, lids shut; Ko 90 deg roll; Victory hop 1.2 + 360
	-- spin; IdleBattle 0.05 breathing, a glance every 2-4 s)
	local function fwd(s)
		return forwardOf(s.Body)
	end
	local function height(s)
		return s.Body.Position.Y
	end
	local fwdMax = extreme(P, "Strike", false, fwd, true)
	local fwdQuarter = forwardOf(P.Sample("Strike", 0.25).Body)
	T.check(fwdMax > 1.45 and fwdMax < 1.56 and fwdQuarter > 1.0, "p7vfx poses: melee Strike lunges forward (along the LookVector) 1.5 studs",
		fmt("peak %.3f, p=0.25 %.3f", fwdMax, fwdQuarter))
	local kick, kickFwd = extreme(P, "Strike", true, fwd, false), extreme(P, "Strike", true, fwd, true)
	T.check(kick < -0.32 and kick > -0.38 and kickFwd < 0.05, "p7vfx poses: ranged Strike recoils backward 0.35 studs (never lunges)", fmt("min %.3f, max %.3f", kick, kickFwd))
	local under = extreme(P, "Strike", false, fwd, false, 0.4, 1)
	-- fix round 3, player note (a): the melee Strike is a LEAP: a hop arc up and forward that lands the hit at p 0.26
	-- (where AttackFx puts the impact), then the recoil; amp (1 .. LEAP_AMP_MAX, from the rarity band) scales the
	-- height and the reach a little. A body offset only: the ranged Strike / Shoot ignore it
	local function at(p, amp, ranged)
		local s0 = P.Sample("Strike", p, ranged, amp)
		return forwardOf(s0.Body), s0.Body.Position.Y
	end
	local peakY, peakP = -1, -1
	for i = 0, 100 do
		local _, y = at(i / 100 * 0.26, 1)
		if y > peakY then
			peakY, peakP = y, i / 100 * 0.26
		end
	end
	local landF, landY = at(0.26, 1)
	local midF = at(0.13, 1)
	T.check(peakY > 0.7 and peakY < 0.9 and peakP > 0.09 and peakP < 0.17 and math.abs(landY) < 0.05 and landF > 1.4 and landF < 1.56 and midF > 0.3 and midF < landF,
		"p7vfx poses: melee Strike leaps: a hop arc ~0.8 high peaking mid-air (p ~0.13), landing the hit 1.5 forward at p 0.26",
		fmt("peak %.3f at p %.3f, land fwd %.3f y %.3f, mid fwd %.3f", peakY, peakP, landF, landY, midF))
	local _, peakBig = at(0.13, P.LEAP_AMP_MAX or 0)
	local landBig = at(0.26, P.LEAP_AMP_MAX or 0)
	local _, peakHuge = at(0.13, 9)
	local _, peakTiny = at(0.13, 0.1)
	local _, peakNaN = at(0.13, 0 / 0)
	local _, peakOne = at(0.13, 1)
	T.check(type(P.LEAP_AMP_MAX) == "number" and P.LEAP_AMP_MAX > 1 and P.LEAP_AMP_MAX <= 1.3 and peakBig > peakOne * 1.15 and landBig > landF * 1.15
		and landBig < 2 and math.abs(peakHuge - peakBig) < 1e-6 and math.abs(peakTiny - peakOne) < 1e-6 and math.abs(peakNaN - peakOne) < 1e-6,
		"p7vfx poses: a higher band leaps a little higher and further (amp up to LEAP_AMP_MAX, clamped; NaN = 1)",
		fmt("max %s: peak %.3f vs %.3f, land %.3f vs %.3f, amp 9 %.3f, amp 0.1 %.3f", tostring(P.LEAP_AMP_MAX), peakBig, peakOne, landBig, landF, peakHuge, peakTiny))
	local rangedSame = true
	for i = 0, 20 do
		local a = P.Sample("Strike", i / 20, true, 1).Body
		local b = P.Sample("Strike", i / 20, true, 1.25).Body
		local c = P.Sample("Shoot", i / 20, true, 1.25).Body
		local d = P.Sample("Shoot", i / 20, true, 1).Body
		rangedSame = rangedSame and (a.Position - b.Position).Magnitude < 1e-6 and (c.Position - d.Position).Magnitude < 1e-6
	end
	T.check(rangedSame, "p7vfx poses: the leap amp never changes the ranged Strike / Shoot")
	T.check(under < -0.02 and under > -0.25, "p7vfx poses: melee Strike settles with a small overshoot behind its start", fmt("%.3f", under))
	-- player note 1: the ranged Shoot is no lunge: the body kicks back ~0.45 and never moves forward, the head snaps
	-- forward (nose down) to loose the shot early in the pose
	local shootBack, shootFwd = extreme(P, "Shoot", false, fwd, false), extreme(P, "Shoot", false, fwd, true)
	local function pitchOf(sm)
		return deg(math.asin(math.max(-1, math.min(1, sm.Body.LookVector.Y))))
	end
	local nod = extreme(P, "Shoot", false, pitchOf, false, 0, 0.2)
	T.check(shootBack < -0.4 and shootBack > -0.5 and shootFwd < 1e-6 and nod < -10,
		"p7vfx poses: Shoot kicks the body back ~0.45 studs, never forward, the head snapping forward (nose down) to loose the shot",
		fmt("min %.3f, max %.3f, nod %.1f deg", shootBack, shootFwd, nod))
	T.check(fwdMax > 1.4 and shootFwd < 0.05, "p7vfx poses: the ranged Shoot is not the melee Strike lunge", fmt("Strike %.3f vs Shoot %.3f", fwdMax, shootFwd))
	local recoil = extreme(P, "Recoil", false, fwd, false)
	T.check(recoil < -0.25 and forwardOf(P.Sample("Recoil", 0.25).Body) < -0.2 and extreme(P, "Recoil", false, fwd, true) < 0.05,
		"p7vfx poses: Recoil moves the body backward", fmt("min %.3f, p=0.25 %.3f", recoil, forwardOf(P.Sample("Recoil", 0.25).Body)))
	-- the left wing reaches towards -X: sweep (+ = tip back, - = swung forward / open) and rise (+ = tip up), degrees
	local function sweepOf(s)
		local tip = s.Groups.wing * Vector3.new(-1, 0, 0)
		return deg(math.atan2(tip.Z, -tip.X))
	end
	local function riseOf(s)
		return deg(math.asin(math.max(-1, math.min(1, (s.Groups.wing * Vector3.new(-1, 0, 0)).Y))))
	end
	local open = -extreme(P, "Strike", false, sweepOf, false)
	local openR = -extreme(P, "Strike", true, sweepOf, false)
	T.check(open > 33 and open < 42 and openR > 33 and openR < 42, "p7vfx poses: Strike snaps the wings open 35 deg (melee + ranged)", fmt("%.1f / %.1f deg", open, openR))
	local highest, highestAt = -90, ""
	for _, name in ipairs(POSE_NAMES) do
		for _, ranged in ipairs({ false, true }) do
			local r = extreme(P, name, ranged, riseOf, true, 0, loops[name] and 12 or 1)
			if r > highest then
				highest, highestAt = r, name
			end
		end
	end
	T.check(highest <= 12, "p7vfx poses: no pose raises the wings more than 12 deg (evolved wings rest near upright)", fmt("%.1f deg (%s)", highest, highestAt))

	local crouch = extreme(P, "Windup", false, height, false)
	T.check(crouch < -0.235 and crouch > -0.27, "p7vfx poses: Windup crouches 0.25 studs", fmt("%.3f", crouch))
	local back = extreme(P, "Windup", false, sweepOf, true)
	T.check(back > 22 and back < 28, "p7vfx poses: Windup sweeps the wings back 25 deg", fmt("%.1f deg", back))
	local tailUp = extreme(P, "Windup", false, function(s)
		return (s.Groups.tail * Vector3.new(0, 0, 1)).Y -- the tail reaches back (+Z)
	end, true)
	T.check(tailUp > 0.25, "p7vfx poses: Windup lifts the tail", fmt("tail tip rise %.3f", tailUp))

	local rise = extreme(P, "Cast", false, height, true)
	T.check(rise > 0.58 and rise < 0.66, "p7vfx poses: Cast rises 0.6 studs", fmt("%.3f", rise))
	local spread = -extreme(P, "Cast", false, sweepOf, false)
	T.check(spread > 46 and spread < 56, "p7vfx poses: Cast spreads the wings 50 deg", fmt("%.1f deg", spread))

	local hurt = P.Sample("Hurt", 0.3)
	T.check(hurt.Lids >= 0.8, "p7vfx poses: Hurt shuts the lids (Lids >= 0.8 at p = 0.3)", fmt("%.2f", hurt.Lids))
	local flinch, dip = extreme(P, "Hurt", false, fwd, false), extreme(P, "Hurt", false, height, false)
	T.check(flinch < -0.27 and flinch > -0.33 and dip < -0.06, "p7vfx poses: Hurt flinches back 0.3 studs with a squash dip", fmt("back %.3f, dip %.3f", flinch, dip))

	local ko = P.Sample("Ko", 1)
	local tilt = deg(math.acos(math.max(-1, math.min(1, ko.Body:VectorToWorldSpace(Vector3.new(0, 1, 0)).Y))))
	T.check(math.abs(tilt - 90) < 3 and ko.Lids >= 0.8 and (ko.Still or 0) >= 0.9,
		"p7vfx poses: Ko ends tumbled 90 deg onto its side, eyes shut, wings / tail still", fmt("tilt %.1f deg, lids %.2f", tilt, ko.Lids))

	local hop = extreme(P, "Victory", false, height, true)
	T.check(hop > 1.17 and hop < 1.25, "p7vfx poses: Victory hops 1.2 studs", fmt("%.3f", hop))
	local spin, last = 0, 0
	for i = 0, 200 do
		local a = yawOf(P.Sample("Victory", i / 200).Body)
		local d = a - last
		if d > 180 then
			d = d - 360
		elseif d < -180 then
			d = d + 360
		end
		spin, last = spin + d, a
	end
	T.check(math.abs(math.abs(spin) - 360) < 3, "p7vfx poses: Victory spins a full 360 deg", fmt("%.1f deg", spin))

	local maxBreath, glances, inGlance, gapsOk, lastStart = 0, 0, false, true, nil
	for i = 0, 6000 do
		local t = i / 100
		local s = P.Sample("IdleBattle", t)
		maxBreath = math.max(maxBreath, math.abs(s.Body.Position.Y))
		local yaw = math.abs(yawOf(s.Body))
		if yaw > 4 and not inGlance then
			inGlance = true
			glances = glances + 1
			if lastStart and (t - lastStart < 1.9 or t - lastStart > 4.1) then
				gapsOk = false
			end
			lastStart = t
		elseif yaw < 1 then
			inGlance = false
		end
	end
	T.check(maxBreath > 0.04 and maxBreath <= 0.0501, "p7vfx poses: IdleBattle breathes 0.05 studs", fmt("%.4f", maxBreath))
	T.check(glances >= 15 and gapsOk, "p7vfx poses: IdleBattle glances every 2-4 s", fmt("%d glances in 60 s, gaps ok %s", glances, tostring(gapsOk)))

	-- the rig hook on real builds
	local PB, PC = sharedModule("PetBuilder"), sharedModule("PetCatalog")
	if not T.check(PB ~= nil and type(PB.Animate) == "function" and type(PB.PoseBody) == "function" and PC ~= nil,
		"p7vfx poses: PetBuilder loads with Animate + PoseBody") then
		return
	end
	T.check(isIdentity(PB.PoseBody(nil)) and isIdentity(PB.PoseBody({})) and isIdentity(PB.PoseBody({ Flap = 1 })), "p7vfx poses: PoseBody without a Pose = identity")
	local pb = PB.PoseBody({ Pose = { Name = "Strike", P = 0.25 } })
	T.check(cfFinite(pb) and (pb.Position - P.Sample("Strike", 0.25).Body.Position).Magnitude < 1e-6, "p7vfx poses: PoseBody returns the pose's Body")
	local pbr = PB.PoseBody({ Pose = { Name = "Strike", P = 0.1, Ranged = true } })
	T.check(forwardOf(pbr) < 0, "p7vfx poses: PoseBody honours Ranged", fmt("%.3f", forwardOf(pbr)))
	local pbAmp = PB.PoseBody({ Pose = { Name = "Strike", P = 0.13, Amp = 1.25 } })
	T.check(cfFinite(pbAmp) and (pbAmp.Position - P.Sample("Strike", 0.13, false, 1.25).Body.Position).Magnitude < 1e-6
		and pbAmp.Position.Y > PB.PoseBody({ Pose = { Name = "Strike", P = 0.13 } }).Position.Y + 0.05,
		"p7vfx poses: PoseBody passes the pose's Amp (a higher leap)", fmt("%.3f", cfFinite(pbAmp) and pbAmp.Position.Y or -1))

	-- Task 9 player decision: the leap reaches the target: `reach` (studs at scale 1) is the exact forward distance at
	-- the landing (p 0.26), the hop grows with it (0.8 + 0.12 x reach, capped), it is clamped 0 .. LEAP_REACH_MAX, and
	-- it never changes the ranged Strike / Shoot. PoseBody passes the pose's Reach
	local function reachAt(p, reach, amp)
		local s0 = P.Sample("Strike", p, false, amp or 1, reach)
		return forwardOf(s0.Body), s0.Body.Position.Y
	end
	local land2, land8 = reachAt(0.26, 2), reachAt(0.26, 8)
	local _, hop2 = reachAt(0.13, 2)
	local _, hop8 = reachAt(0.13, 8)
	local land50 = reachAt(0.26, 50)
	local land0, hop0 = reachAt(0.26, 0)
	local landNeg = reachAt(0.26, -3)
	local landNaN = reachAt(0.26, 0 / 0)
	local _, hopMax = reachAt(0.13, 50, P.LEAP_AMP_MAX)
	local under8 = 0
	for i = 40, 100 do
		under8 = math.min(under8, reachAt(i / 100, 8))
	end
	T.check(math.abs(land2 - 2) < 1e-6 and math.abs(land8 - 8) < 1e-6 and math.abs(hop2 - (0.8 + 0.24)) < 0.01 and math.abs(hop8 - (0.8 + 0.96)) < 0.01
		and P.LEAP_REACH_MAX == 12 and math.abs(land50 - 12) < 1e-6 and math.abs(land0) < 1e-6 and math.abs(hop0) < 0.1 and math.abs(landNeg) < 1e-6
		and math.abs(landNaN - 1.5) < 1e-6 and hopMax <= 2.4 + 1e-6 and under8 > -0.3,
		"p7vfx poses: the leap's reach is its landing point (2 -> 2, 8 -> 8 studs at p 0.26), higher with reach, clamped 0 .. 12 (hop <= 2.4, recoil overshoot small)",
		fmt("land %.3f / %.3f, hop %.3f / %.3f, 50 -> %.3f, 0 -> %.3f, -3 -> %.3f, NaN -> %.3f, hop max %.3f, under %.3f", land2, land8, hop2, hop8, land50, land0, landNeg, landNaN, hopMax, under8))
	local rangedReach = true
	for i = 0, 20 do
		local a = P.Sample("Strike", i / 20, true, 1).Body
		local b = P.Sample("Strike", i / 20, true, 1, 9).Body
		local c = P.Sample("Shoot", i / 20, true, 1, 9).Body
		local d = P.Sample("Shoot", i / 20, true, 1).Body
		rangedReach = rangedReach and (a.Position - b.Position).Magnitude < 1e-6 and (c.Position - d.Position).Magnitude < 1e-6
	end
	T.check(rangedReach, "p7vfx poses: the leap reach never changes the ranged Strike / Shoot")
	local pbReach = PB.PoseBody({ Pose = { Name = "Strike", P = 0.26, Reach = 6 } })
	T.check(cfFinite(pbReach) and math.abs(forwardOf(pbReach) - 6) < 1e-6, "p7vfx poses: PoseBody passes the pose's Reach (the leap lands 6 studs on)",
		fmt("%.3f", cfFinite(pbReach) and forwardOf(pbReach) or -1))

	-- one winged pet (flapping wings) and one tailed pet, each with a second evolution
	local winged, tailed = nil, nil
	for _, def in ipairs(PC.Pets) do
		if winged and tailed then
			break
		end
		if PB.MaxEvolution(def) == 2 then
			local m = PB.Build(def, { Detail = "Low" })
			local w = m:FindFirstChild("WingL")
			if not winged and w and string.find(tostring(w:GetAttribute("PB_G")), ":wing:", 1, true) then
				winged = def
			elseif not tailed and m:FindFirstChild("Tail") then
				tailed = def
			end
			m:Destroy()
		end
	end
	if not T.check(winged ~= nil and tailed ~= nil, "p7vfx poses: the catalog has a winged and a tailed pet with a second evolution",
		tostring(winged and winged.Id) .. " / " .. tostring(tailed and tailed.Id)) then
		return
	end

	local function cfNear(a, b, eps)
		eps = eps or 1e-6
		return (a.Position - b.Position).Magnitude < eps and angleOf(a:Inverse() * b) < eps * 10
	end
	local function mirroredPair(a, b)
		local l, r = a.Position, b.Position
		return math.abs(l.X + r.X) < 1e-3 and math.abs(l.Y - r.Y) < 1e-3 and math.abs(l.Z - r.Z) < 1e-3
	end
	local hook = T.tally("p7vfx poses: Animate + Pose moves WingL / Tail, wings stay mirrored, back to the exact unposed frame, no Instances")
	for _, def in ipairs({ winged, tailed }) do
		for _, stage in ipairs({ 0, 2 }) do
			local m = PB.Build(def, { Detail = "Low", Evolved = stage > 0 and stage or nil })
			local tag = fmt("%s stage %d", def.Id, stage)
			local wingL, wingR = m:FindFirstChild("WingL"), m:FindFirstChild("WingR")
			local subjectName = (def == winged) and "WingL" or "Tail"
			local subject = m:FindFirstChild(subjectName)
			if not subject then
				hook:case(false, tag .. ": has no " .. subjectName)
			else
				local t0 = 3.37
				PB.Animate(m, t0, {})
				local restCF = subject.CFrame
				local mirrored = wingL and wingR and mirroredPair(wingL.CFrame, wingR.CFrame)
				if def == winged then
					hook:case(mirrored == true, tag .. ": WingL / WingR start mirrored (so the mirror check below runs)")
					-- the pose reads right on the real wings: Windup sweeps them back (+Z), Cast raises them (+Y)
					local function wingCentre()
						local sum, n = Vector3.new(0, 0, 0), 0
						for _, part in ipairs(m:GetChildren()) do
							if part:IsA("BasePart") and string.sub(tostring(part:GetAttribute("PB_G")), 1, 6) == "WingL:" then
								sum, n = sum + part.Position, n + 1
							end
						end
						return sum / math.max(1, n)
					end
					local c0 = wingCentre()
					PB.Animate(m, t0, { Pose = { Name = "Windup", P = 0.6 } })
					local cBack = wingCentre()
					PB.Animate(m, t0, { Pose = { Name = "Cast", P = 0.5 } })
					local cOpen = wingCentre()
					hook:case(cBack.Z > c0.Z + 0.05, fmt("%s: Windup sweeps the real left wing back (dz %.3f)", tag, cBack.Z - c0.Z))
					-- the wing's reach around its hinge (PB_Rig, the root sits at the origin): swung forward, but
					-- never folded round past ~broadside (10 deg + the flap's own +-7 deg sweep)
					local hx, hz = string.match(tostring(m:GetAttribute("PB_Rig")), "WingL:[^=]*=([^,]+),[^,]+,([^,;]+)")
					hx, hz = tonumber(hx), tonumber(hz)
					local sweep = hx and deg(math.atan2(cOpen.Z - hz, -(cOpen.X - hx))) or -999
					hook:case(cOpen.Z < c0.Z - 0.05 and sweep > -20,
						fmt("%s: Cast spreads the real left wing forward, never round past broadside (dz %.3f, sweep %.1f deg)", tag, cOpen.Z - c0.Z, sweep))
					PB.Animate(m, t0, {})
				end
				local live0, desc0 = Mock.Stats().liveInstances, #m:GetDescendants()
				for _, name in ipairs({ "Windup", "Strike", "Shoot", "Recoil", "Cast", "Hurt", "Ko", "Victory" }) do
					PB.Animate(m, t0, { Pose = { Name = name, P = 0.5 } })
					hook:case(not cfNear(subject.CFrame, restCF, 1e-3), fmt("%s: %s at p=0.5 moves %s", tag, name, subjectName))
					if mirrored then
						hook:case(mirroredPair(wingL.CFrame, wingR.CFrame), fmt("%s: %s keeps WingL / WingR mirrored", tag, name))
					end
				end
				PB.Animate(m, t0, { Pose = { Name = "Strike", P = 0.2, Ranged = true } })
				PB.Animate(m, t0, { Pose = { Name = "IdleBattle", P = 7.3 } })
				PB.Animate(m, t0, {})
				hook:case(cfNear(subject.CFrame, restCF), tag .. ": the same call without Pose returns the exact unposed frame")
				hook:case(Mock.Stats().liveInstances == live0 and #m:GetDescendants() == desc0, tag .. ": posing created no Instances")
			end
			m:Destroy()
		end
	end
	hook:report()

	-- the lids: Hurt shuts them, the unposed call opens them again (outside a blink)
	local m = PB.Build(winged, { Detail = "Low" })
	local lids = {}
	for _, part in ipairs(m:GetChildren()) do
		if part:IsA("BasePart") and string.find(tostring(part:GetAttribute("PB_G")), ":lid:", 1, true) then
			lids[#lids + 1] = part
		end
	end
	if T.check(#lids > 0, "p7vfx poses: the winged pet has eyelid parts", tostring(#lids)) then
		local tOpen = nil
		for i = 0, 400 do
			PB.Animate(m, 10 + i * 0.01, {})
			if lids[1].Transparency == 1 then
				tOpen = 10 + i * 0.01
				break
			end
		end
		PB.Animate(m, tOpen, { Pose = { Name = "Hurt", P = 0.3 } })
		local shut = tOpen ~= nil
		for _, l in ipairs(lids) do
			shut = shut and l.Transparency < 1 and l.Transparency == l:GetAttribute("PB_T0")
		end
		T.check(shut, "p7vfx poses: Hurt (p = 0.3) shows every eyelid (eyes squeezed shut)")
		PB.Animate(m, tOpen, {})
		local opened = true
		for _, l in ipairs(lids) do
			opened = opened and l.Transparency == 1
		end
		T.check(opened, "p7vfx poses: without the Pose the lids open again (outside a blink)")
	end
	m:Destroy()
end)

return S
