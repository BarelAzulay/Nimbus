-- smoke_afx_impact.lua: bigger attacks and the impact package (docs/superpowers/specs/2026-11-01-attack-fx-design.md "Owner's decisions",
-- "Claude's calls"; plan Task 2), loaded by tools/smoke.py in both worlds. Server world, pure:
--   afx_impact_sizes     SizeOf = rarity 1.3 .. 1.6 x (1, 1.15, 1.3) by stage, cap 2.08; CloudSizeOf caps at 1.6; an Evolved II Common
--                        out-sizes an unevolved Secret
--   afx_impact_package   every hit of every element and rarity has the ring, the flash, the sparks and the ground mark (Shockwave2 from
--                        Epic), stronger by band (ImpactScale); no support cast or reaction has any of them; the 6-emitter / 3-light / light
--                        caps hold; Sparks yield only where 6 emitters already fill the recipe (never at Common on a basic or element
--                        attack; the list is printed for the owner)
--   afx_impact_readable  a Secret Evo 2 recipe differs from the Stage 0 one by Size alone: same layers, same particle counts and sizes, same
--                        cloud size, same lights; the 12 signatures fit their caps at Stage 2
-- Client world:
--   client_afx_impact_engine  the engine draws it: particles follow CloudSize, rings and ground marks the full Size; Sparks survive the cap
--                             where the recipe lists them; Graphics Low gets no Sparks
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, min = math.abs, math.min
local fmt = string.format

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
local SIZE = { Common = 1.3, Uncommon = 1.35, Rare = 1.4, Epic = 1.45, Legendary = 1.5, Mythic = 1.55, Secret = 1.6 }
local PACKAGE = { "Shockwave", "Shockwave2", "Flash", "Sparks", "GroundGlow" }

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-9)
end

local function layerById(r, id)
	for _, l in ipairs(r and r.Layers or {}) do
		if l.Id == id then
			return l
		end
	end
	return nil
end

-- AttackFx's emitter rule (isEmitter): an Emitter layer, a textured Decal, an emitter Alive
local function isEmitterLayer(l)
	return type(l) == "table" and (l.Kind == "Emitter" or (l.Kind == "Decal" and type(l.Texture) == "string"))
end

local function emitterCount(r)
	local n = 0
	for _, l in ipairs(r.Layers) do
		if isEmitterLayer(l) then
			n = n + 1
		end
	end
	return n + (isEmitterLayer(r.Alive) and 1 or 0)
end

local function lightsOf(r)
	local out = {}
	for _, l in ipairs(r.Layers) do
		if l.Kind == "Light" then
			out[#out + 1] = l
		end
	end
	return out
end

local function serverScenarios()
	local S = {}

	local function catalog()
		local inst = Mock.GetPath(ROOTS.shared .. "/AttackFxCatalog")
		local ok, mod = pcall(require, inst)
		return ok and type(mod) == "table" and mod or nil
	end

	local function elementNames()
		local inst = Mock.GetPath(ROOTS.shared .. "/Config")
		local ok, mod = pcall(require, inst)
		return ok and mod.Elements.Order or {}
	end

	-- every attack that lands a hit (the package plays on these)
	local HITS = {
		{ Attack = "Melee", label = "Melee" },
		{ Attack = "Ranged", label = "Ranged" },
		{ Attack = "Element", Shape = "Cone", label = "Element/Cone" },
		{ Attack = "Element", Shape = "Circle", label = "Element/Circle" },
		{ Attack = "Element", Shape = "Line", label = "Element/Line" },
		{ Attack = "Special", Kind = "Blast", label = "Special/Blast" },
		{ Attack = "Special", Kind = "Beam", label = "Special/Beam" },
		{ Attack = "Special", Kind = "Pounce", label = "Special/Pounce" },
		{ Attack = "Special", Kind = "Freeze", label = "Special/Freeze" },
		{ Attack = "Special", Kind = "Storm", label = "Special/Storm" },
	}
	-- support casts and reactions: none of the package
	local QUIET = {
		{ Attack = "Special", Kind = "Heal", label = "Special/Heal" },
		{ Attack = "Special", Kind = "Shield", label = "Special/Shield" },
		{ Attack = "Special", Kind = "Rally", label = "Special/Rally" },
		{ Attack = "Special", Kind = "Haste", label = "Special/Haste" },
		{ Attack = "Hurt", label = "Hurt" },
		{ Attack = "Ko", label = "Ko" },
		{ Attack = "Victory", label = "Victory" },
		{ Attack = "ShieldHit", label = "ShieldHit" },
	}

	local function resolve(C, element, v, rarity, stage)
		return C.Resolve({ Element = element, Attack = v.Attack, Kind = v.Kind, Shape = v.Shape, Rarity = rarity, Stage = stage or 0, Mine = true })
	end

	S.afx_impact_sizes = guarded("afx_impact_sizes", function()
		local C = catalog()
		if not T.check(C ~= nil, "afx sizes: AttackFxCatalog loads") then
			return
		end
		if not T.check(type(C.CloudSizeOf) == "function" and type(C.ImpactScale) == "table", "afx sizes: CloudSizeOf and ImpactScale exist") then
			return
		end
		local sizes = T.tally("afx sizes: SizeOf = 1.3 .. 1.6 x (1, 1.15, 1.3) by stage, cap 2.08; CloudSizeOf = the same, cap 1.6")
		for _, r in ipairs(RARITIES) do
			for stage = 0, 2 do
				local want = min(2.08, SIZE[r] * (1 + 0.15 * stage))
				sizes:case(near(C.SizeOf(r, stage), want) and near(C.CloudSizeOf(r, stage), min(1.6, want)),
					fmt("%s stage %d: size %s (want %.4f), cloud %s", r, stage, tostring(C.SizeOf(r, stage)), want, tostring(C.CloudSizeOf(r, stage))))
			end
		end
		sizes:report()
		T.check(near(C.SizeOf("Secret", 2), 2.08) and C.SizeCap == 2.08 and C.CloudCap == 1.6, "afx sizes: Secret Evo 2 = 2.08 = the cap; clouds cap at 1.6")
		T.check(C.SizeOf("Common", 2) > C.SizeOf("Secret", 0), "afx sizes: an Evolved II Common (1.69) out-sizes an unevolved Secret (1.6): evolution shows")
		T.check(near(C.SizeOf("Bogus", 0), 1.3) and near(C.SizeOf("Secret", 9), 2.08) and near(C.SizeOf("Common", nil), 1.3), "afx sizes: unknown rarity = Common, stage clamped 0..2")
		T.check(near(C.StageBonus[1], 0.15) and near(C.StageBonus[2], 0.30) and C.StageBonus[0] == 0, "afx sizes: StageBonus 0 / 0.15 / 0.30")
		local r = C.Resolve({ Element = "Flame", Attack = "Melee", Rarity = "Secret", Stage = 2, Mine = true })
		T.check(r ~= nil and near(r.Size, 2.08) and near(r.CloudSize, 1.6), "afx sizes: a recipe carries Size and CloudSize", r and fmt("%s / %s", tostring(r.Size), tostring(r.CloudSize)))
	end)

	S.afx_impact_package = guarded("afx_impact_package", function()
		local C = catalog()
		local elements = elementNames()
		if not T.check(C ~= nil and #elements > 0, "afx package: the catalog and the elements load") then
			return
		end
		local sc = C.ImpactScale
		if not T.check(type(sc) == "table" and near(sc[1], 0.8) and near(sc[2], 0.95) and near(sc[3], 1.1) and near(sc[4], 1.25), "afx package: ImpactScale 0.8 / 0.95 / 1.1 / 1.25 by band") then
			return
		end
		local has = T.tally("afx package: every hit of every element and rarity has the Shockwave ring, the Flash (Ranged: BoomFlash, Freeze: Lock), the GroundGlow and the Sparks (unless Dropped); Shockwave2 from Epic")
		local caps = T.tally("afx package: <= 6 emitters, <= 3 lights, every Light Brightness <= 2 and Range <= 8")
		local strong = T.tally("afx package: stronger by band: Ring Grow, GroundGlow Size, Sparks Count, Flash Brightness x ImpactScale")
		local dropped, droppedSeen = {}, {}
		local dropBad, commonBad = {}, {}
		for _, element in ipairs(elements) do
			for _, v in ipairs(HITS) do
				for i, rarity in ipairs(RARITIES) do
					local r = resolve(C, element, v, rarity)
					local label = fmt("%s %s %s", element, v.label, rarity)
					local band = C.BandOf(rarity)
					local sw, sw2, glow, sparks = layerById(r, "Shockwave"), layerById(r, "Shockwave2"), layerById(r, "GroundGlow"), layerById(r, "Sparks")
					local flash = layerById(r, "Flash")
					if v.Attack == "Ranged" then
						flash = layerById(r, "Flash") == nil and layerById(r, "BoomFlash") or nil
					elseif v.Kind == "Freeze" then
						flash = layerById(r, "Flash") == nil and layerById(r, "Lock") or nil
					end
					local isDropped = type(r.Dropped) == "table" and r.Dropped[1] == "Sparks"
					if isDropped and rarity == "Common" and v.Attack ~= "Special" then
						commonBad[#commonBad + 1] = label
					end
					has:case(sw ~= nil and sw.Kind == "Ring" and sw.At == "Ground"
						and flash ~= nil and flash.Kind == "Light"
						and glow ~= nil and glow.Kind == "Decal" and glow.At == "Ground"
						and (isDropped or (sparks ~= nil and sparks.Kind == "Emitter" and sparks.Texture == "fx_sparks"))
						and ((i >= 4) == (sw2 ~= nil)),
						fmt("%s: ring %s flash %s glow %s sparks %s (dropped %s) second ring %s", label, tostring(sw ~= nil), tostring(flash ~= nil), tostring(glow ~= nil), tostring(sparks ~= nil), tostring(isDropped), tostring(sw2 ~= nil)))
					local lights = lightsOf(r)
					local lightsOk = #lights <= 3
					for _, l in ipairs(lights) do
						lightsOk = lightsOk and l.Brightness <= 2 and l.Range <= 8
					end
					caps:case(emitterCount(r) <= 6 and lightsOk, fmt("%s: %d emitters, %d lights", label, emitterCount(r), #lights))
					local s = sc[band]
					strong:case(sw ~= nil and near(sw.Grow, 1.7 * s) and glow ~= nil and near(glow.Size, 5 * s)
						and (sw2 == nil or near(sw2.Grow, 2.4 * s))
						and (layerById(r, "Flash") == nil or near(layerById(r, "Flash").Brightness, min(2, 1.6 * s)))
						and (sparks == nil or sparks.Count == math.max(1, math.floor(math.floor(5 * C.CountScale[band] + 0.5) * s + 0.5))),
						fmt("%s: grow %s, glow %s, sparks %s", label, tostring(sw and sw.Grow), tostring(glow and glow.Size), tostring(sparks and sparks.Count)))
					if isDropped then
						local name = element .. " " .. v.label
						if not droppedSeen[name] then
							droppedSeen[name] = true
							dropped[#dropped + 1] = name
						end
						if sparks ~= nil or emitterCount(r) ~= 6 then
							dropBad[#dropBad + 1] = fmt("%s: %d emitters, sparks %s", label, emitterCount(r), tostring(sparks ~= nil))
						end
					end
				end
			end
		end
		has:report()
		caps:report()
		strong:report()
		table.sort(dropped)
		T.check(#dropBad == 0, "afx package: Sparks dropped only where 6 emitters already fill the recipe", table.concat(dropBad, ", "))
		T.check(#commonBad == 0, "afx package: a Common basic or element attack always has its sparks (the pets this package is for)", table.concat(commonBad, ", "))
		T.check(#dropped <= 42, "afx package: Sparks yield on no more element x attack pairs than the 42 the owner was told about", #dropped .. ": " .. table.concat(dropped, ", "))
		print("  [afx package] Sparks yield to the 6-emitter cap on: " .. (#dropped > 0 and table.concat(dropped, ", ") or "nothing"))

		local quiet = T.tally("afx package: no support cast or reaction has any of the five (Shockwave, Shockwave2, Flash, Sparks, GroundGlow)")
		for _, element in ipairs(elements) do
			for _, v in ipairs(QUIET) do
				for _, rarity in ipairs(RARITIES) do
					local r = resolve(C, element, v, rarity)
					local found = {}
					for _, id in ipairs(PACKAGE) do
						if layerById(r, id) then
							found[#found + 1] = id
						end
					end
					quiet:case(r ~= nil and #found == 0, fmt("%s %s %s: %s", element, v.label, rarity, table.concat(found, ",")))
				end
			end
		end
		quiet:report()

		-- the numbers the plan names, literally
		local common = C.Resolve({ Element = "Flame", Attack = "Melee", Rarity = "Common", Mine = true })
		local secret = C.Resolve({ Element = "Flame", Attack = "Melee", Rarity = "Secret", Mine = true })
		T.check(near(layerById(common, "Shockwave").Grow, 1.36) and near(layerById(secret, "Shockwave").Grow, 2.125), "afx package: Shockwave Grow 1.7 x 0.8 at Common, x 1.25 at Secret")
		T.check(near(layerById(common, "Flash").Brightness, 1.28) and near(layerById(secret, "Flash").Brightness, 2), "afx package: Flash Brightness 1.28 at Common, 2 at Secret (the cap)")
		T.check(near(layerById(common, "Flash").Range, 8) and near(layerById(secret, "Flash").Range, 8), "afx package: Flash Range untouched")
		local sparksCommon = C.Resolve({ Element = "Celestial", Attack = "Melee", Rarity = "Common", Mine = true })
		local sparksSecret = C.Resolve({ Element = "Celestial", Attack = "Melee", Rarity = "Secret", Mine = true })
		T.check(layerById(sparksCommon, "Sparks").Count == 4 and layerById(sparksSecret, "Sparks").Count == 10, "afx package: Sparks 4 at Common, 10 at Secret")
	end)

	S.afx_impact_readable = guarded("afx_impact_readable", function()
		local C = catalog()
		local elements = elementNames()
		if not T.check(C ~= nil and #elements > 0, "afx readable: the catalog and the elements load") then
			return
		end
		local same = T.tally("afx readable: Secret Stage 2 vs Stage 0: same layer ids in the same order, every emitter's Count and Size equal, the same Transparency, lights and CloudSize 1.6; Size 2.08 vs 1.6")
		local variants = { { Attack = "Melee", label = "Melee" }, { Attack = "Ranged", label = "Ranged" }, { Attack = "Special", Kind = "Blast", label = "Special/Blast" } }
		for _, element in ipairs(elements) do
			for _, v in ipairs(variants) do
				local s0, s2 = resolve(C, element, v, "Secret", 0), resolve(C, element, v, "Secret", 2)
				local bad = {}
				if #s0.Layers ~= #s2.Layers then
					bad[#bad + 1] = fmt("%d vs %d layers", #s0.Layers, #s2.Layers)
				end
				for i, a in ipairs(s0.Layers) do
					local b = s2.Layers[i]
					if not b or a.Id ~= b.Id then
						bad[#bad + 1] = fmt("layer %d: %s vs %s", i, tostring(a.Id), tostring(b and b.Id))
					else
						if a.Kind == "Emitter" and (a.Count ~= b.Count or a.Size ~= b.Size) then
							bad[#bad + 1] = fmt("%s: count %s/%s size %s/%s", a.Id, tostring(a.Count), tostring(b.Count), tostring(a.Size), tostring(b.Size))
						end
						if a.Transparency ~= b.Transparency then
							bad[#bad + 1] = a.Id .. " transparency"
						end
						if a.Kind == "Light" and (a.Brightness ~= b.Brightness or a.Range ~= b.Range or b.Brightness > 2 or b.Range > 8) then
							bad[#bad + 1] = a.Id .. " light"
						end
					end
				end
				if s0.Alive.Count ~= s2.Alive.Count or s0.Alive.Size ~= s2.Alive.Size then
					bad[#bad + 1] = "alive"
				end
				if not (near(s0.CloudSize, 1.6) and near(s2.CloudSize, 1.6) and near(s0.Size, 1.6) and near(s2.Size, 2.08)) then
					bad[#bad + 1] = fmt("sizes %s / %s, clouds %s / %s", tostring(s0.Size), tostring(s2.Size), tostring(s0.CloudSize), tostring(s2.CloudSize))
				end
				same:case(#bad == 0, fmt("%s %s: %s", element, v.label, table.concat(bad, "; ")))
			end
		end
		same:report()

		local sigs = T.tally("afx readable: the 12 signatures resolve at Stage 2 with Size <= 2.08, <= 6 emitters, <= 3 lights")
		local n = 0
		for petId, sig in pairs(C.Signatures) do
			n = n + 1
			local r = C.Resolve({ Attack = "Special", PetId = petId, Element = sig.Element, Kind = sig.Kind, Rarity = sig.Rarity, Stage = 2, Mine = true })
			local lights = r and lightsOf(r) or {}
			local ok = r ~= nil and r.Size <= 2.08 + 1e-9 and emitterCount(r) <= 6 and #lights <= 3
			sigs:case(ok, fmt("%s: size %s, %d emitters, %d lights", petId, tostring(r and r.Size), r and emitterCount(r) or -1, #lights))
		end
		sigs:report()
		T.check(n == 12, "afx readable: 12 signatures", tostring(n))
	end)

	return S
end

local function clientScenarios()
	local S = {}

	local function moduleAt(path)
		local inst = Mock.GetPath(path)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	local function fakeMeshLibrary()
		return {
			IsReady = function(key)
				return type(key) == "string" and string.sub(key, 1, 4) == "vfx_"
			end,
			Assemble = function(spec)
				local key = type(spec) == "string" and spec or (type(spec) == "table" and spec.Key) or "?"
				local m = Instance.new("Model")
				m.Name = key
				local p = Instance.new("MeshPart")
				p.Name = "Core"
				p.Size = Vector3.new(2, 2, 2)
				p.Anchored = true
				p.Parent = m
				return m
			end,
		}
	end

	local function unitModel(parent, name, pos)
		local m = Instance.new("Model")
		m.Name = name
		local root = Instance.new("Part")
		root.Name = "Body"
		root.Anchored = true
		root.Size = Vector3.new(2, 2, 2)
		root.CFrame = CFrame.new(pos)
		root.Parent = m
		m.PrimaryPart = root
		m.Parent = parent
		return m
	end

	local function maxKey(seq)
		local best = 0
		for _, kp in ipairs(seq.Keypoints) do
			best = math.max(best, kp.Value)
		end
		return best
	end

	S.client_afx_impact_engine = guarded("client_afx_impact_engine", function()
		local Fx = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local Cat = moduleAt(ROOTS.shared .. "/AttackFxCatalog")
		if not T.check(Fx ~= nil and Cat ~= nil, "afx engine: the modules load") then
			return
		end
		Fx.ClearAll()
		Fx._Deps({ MeshLibrary = fakeMeshLibrary() })
		Fx.SetQuality("High")
		local holder = Instance.new("Folder")
		holder.Name = "SmokeAfxImpact"
		holder.Parent = workspace
		local A = unitModel(holder, "A", Vector3.new(0, 2, 0))
		local B = unitModel(holder, "B", Vector3.new(0, 2, -12))
		local clock = 7000

		-- one fresh effect, its items by layer id
		local function play(over)
			Fx.ClearAll()
			clock = clock + 10
			local c = { Attack = "Melee", Element = "Flame", Rarity = "Secret", Stage = 0, Mine = true,
				From = { Unit = 1, Model = A }, To = { Unit = 2, Model = B }, Ground = 0.5, Now = clock }
			for k, v in pairs(over or {}) do
				c[k] = v
			end
			if not Fx.Play(c) then
				return nil, {}
			end
			local eff = Fx._Live()[#Fx._Live()]
			local items = {} -- read now: the next play's ClearAll takes the kits back
			for _, it in ipairs(eff.Items) do
				if it.Layer and it.Layer.Id then
					local em = it.Kit and it.Kit.Em
					items[it.Layer.Id] = { S = it.S, D = it.D, Particle = em and maxKey(em.Size) or nil, B = it.B, Range = it.Kit and it.Kit.Light and it.Kit.Light.Range or nil }
				end
			end
			return eff, items
		end

		local e0, i0 = play({ Stage = 0 })
		local e2, i2 = play({ Stage = 2 })
		T.check(e2 ~= nil and near(e2.Size, 2.08) and near(e2.CloudSize, 1.6), "afx engine: a Secret Evo 2 effect has Size 2.08, CloudSize 1.6", e2 and fmt("%s / %s", tostring(e2.Size), tostring(e2.CloudSize)))
		local b0, b2 = i0.Burst and i0.Burst.Particle, i2.Burst and i2.Burst.Particle
		T.check(b0 ~= nil and b2 ~= nil and near(b0, b2, 1e-6), "afx engine: the Burst's particles are no bigger at Evo 2 (clouds stop at 1.6)", fmt("%s vs %s", tostring(b0), tostring(b2)))
		local _, g0 = play({ Element = "Earth", Stage = 0 })
		local _, g2 = play({ Element = "Earth", Stage = 2 })
		local sc0, sc2 = g0.GroundCrack and g0.GroundCrack.Particle, g2.GroundCrack and g2.GroundCrack.Particle
		T.check(sc0 ~= nil and sc2 ~= nil and near(sc2, sc0 * 1.3, 1e-6), "afx engine: a textured ground mark (Earth's GroundCrack) takes the full Size x1.3 (spec: evolved size goes into rings and ground marks)", fmt("%s vs %s", tostring(sc0), tostring(sc2)))
		T.check(i2.Shockwave ~= nil and near(i2.Shockwave.S, 2.08, 1e-6), "afx engine: the Shockwave ring takes the full Size", i2.Shockwave and tostring(i2.Shockwave.S))
		T.check(i0.GroundGlow ~= nil and i2.GroundGlow ~= nil and near(i2.GroundGlow.D, i0.GroundGlow.D * 1.3, 1e-6), "afx engine: the GroundGlow disc takes the full Size")
		local _, l2 = play({ Element = "Celestial", Stage = 2 })
		T.check(l2.Sparks ~= nil and l2.Sparks.Particle ~= nil and l2.Flash ~= nil, "afx engine: the Sparks and the Flash play")

		-- the lights keep the effective caps Task 8 judged in Studio: Range x the Size stops at 1.4 (the biggest Size of that round),
		-- Brightness <= 2 after the crit, unless a signature's own light was already over it
		local LS = 1.4
		local _, ls0 = play({ Rarity = "Common", Stage = 0 })
		local _, ls2 = play({ Rarity = "Secret", Stage = 2 })
		T.check(ls0.Flash ~= nil and near(ls0.Flash.Range, 8 * 1.3, 1e-6), "afx lights: a Common Flash reaches 8 x 1.3 = 10.4 studs", ls0.Flash and tostring(ls0.Flash.Range))
		T.check(ls2.Flash ~= nil and near(ls2.Flash.Range, 8 * LS, 1e-6), "afx lights: a Secret Evo 2 Flash reaches 11.2 studs, not 16.6", ls2.Flash and tostring(ls2.Flash.Range))
		T.check(ls2.Bloom ~= nil and near(ls2.Bloom.Range, 8 * LS, 1e-6), "afx lights: ...its Bloom 11.2", ls2.Bloom and tostring(ls2.Bloom.Range))
		T.check(ls2.PlasmaRim ~= nil and near(ls2.PlasmaRim.Range, 6 * LS, 1e-6), "afx lights: ...its PlasmaRim 8.4", ls2.PlasmaRim and tostring(ls2.PlasmaRim.Range))
		local _, crit = play({ Rarity = "Secret", Crit = true })
		T.check(crit.Flash ~= nil and near(crit.Flash.B, 2, 1e-6), "afx lights: a Secret crit's Flash stays at Brightness 2 (2 x 1.3 was over the cap)", crit.Flash and tostring(crit.Flash.B))
		local _, critC = play({ Rarity = "Common", Crit = true })
		T.check(critC.Flash ~= nil and near(critC.Flash.B, 1.28 * 1.3, 1e-6), "afx lights: a Common crit still flashes brighter than its plain hit", critC.Flash and tostring(critC.Flash.B))
		local slamPet = nil
		for petId, sig in pairs(Cat.Signatures) do
			for _, l in ipairs(sig.Layers or {}) do
				if l.Id == "SigSlamFlash" then
					slamPet = petId
				end
			end
		end
		local slamSig = slamPet and Cat.Signatures[slamPet]
		local _, slam = play(slamSig and { Attack = "Special", PetId = slamPet, Element = slamSig.Element, Kind = slamSig.Kind, Rarity = "Secret", Stage = 2 } or {})
		T.check(slam.SigSlamFlash ~= nil and near(slam.SigSlamFlash.Range, 14 * LS, 1e-6) and near(slam.SigSlamFlash.B, 4, 1e-6), "afx lights: the Storm Pounce's slam flash reaches 19.6 studs, not 29 (its own Brightness 4 stays)", slam.SigSlamFlash and fmt("%s @ %s", tostring(slam.SigSlamFlash.B), tostring(slam.SigSlamFlash.Range)))

		-- Common: the package plays at the bottom of the ladder too
		local _, c = play({ Rarity = "Common" })
		T.check(c.Shockwave ~= nil and c.GroundGlow ~= nil and c.Flash ~= nil and c.Sparks ~= nil, "afx engine: a Common hit plays the ring, the mark, the flash and the sparks")

		-- Sparks survive the 6-emitter cap wherever the recipe lists them
		local full = T.tally("afx engine: every recipe that lists Sparks draws them at High, under the 6-emitter cap")
		local cfg = moduleAt(ROOTS.shared .. "/Config")
		local n6 = 0
		for _, element in ipairs(cfg.Elements.Order) do
			for _, attack in ipairs({ "Melee", "Ranged" }) do
				local eff, items = play({ Element = element, Attack = attack })
				local listed = eff ~= nil and eff.Recipe ~= nil
				local has = false
				for _, l in ipairs(eff and eff.Recipe.Layers or {}) do
					has = has or l.Id == "Sparks"
				end
				if listed and has then
					n6 = n6 + 1
					full:case(items.Sparks ~= nil and eff.Emitters <= 6, fmt("%s %s: sparks %s, %d emitters", element, attack, tostring(items.Sparks ~= nil), eff.Emitters))
				end
			end
		end
		full:report()
		T.check(n6 > 0, "afx engine: recipes listed Sparks", tostring(n6))

		-- Graphics Low: rings, lights and ground marks only: no Sparks, still 2 emitters at most
		Fx.SetQuality("Low")
		local low = T.tally("afx engine: Graphics Low draws no Sparks, <= 2 emitters")
		for _, element in ipairs(cfg.Elements.Order) do
			local eff, items = play({ Element = element })
			low:case(eff ~= nil and items.Sparks == nil and eff.Emitters <= 2, fmt("%s: sparks %s, %s emitters", element, tostring(items.Sparks ~= nil), tostring(eff and eff.Emitters)))
		end
		low:report()
		Fx.SetQuality("High")
		Fx.ClearAll()
		holder:Destroy()
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
