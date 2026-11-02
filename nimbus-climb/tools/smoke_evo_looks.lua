-- smoke_evo_looks.lua: the looks of evolved forms (docs/superpowers/specs/2026-11-01-evolved-forms-design.md; plan Task 4), loaded by tools/smoke.py in
-- BOTH worlds (ARGS.context):
--   evo_looks_catalog        (server world, pure) Stormfang's three stages; every kind / element x stage x rarity x mine within the caps; Form 0 is the plain
--                            recipe; stage 2 keeps stage 1; every Twists id has no charge; the Beam's cooler start (Lens, Pulse, Thick x1.15), its MarkRing, Pulse
--                            yielding before Wrap; Rally / Haste with Seconds; the four Plain pets; the form names match BattleCatalog.FormNames
--   client_evo_forms         (client world, BattleController) a real stage-1 Stormfang's Special reaches AttackFx with its charge line in WORLD space and reads
--                            "SHADOW PACK!"; a ranged Earth pet's Circle lands on the aim point, a melee one's on itself; the cube fallback too
--   client_evo_pack          (client world, the engine on a fake clock) wolves start on the line behind the caster, reach the target at the impact, run to the line's
--                            end, stay on the line; Low: plain; others' pets x0.6; a Thunder Pack under the piece and beam caps
--   client_evo_beams         the Lens at the mouth, the Pulse along the path, a MarkRing per target; a Twin twist draws a second stretched core
--   client_evo_auras         a Rally / Haste aura lasts its Seconds, EndAura ends it within a frame, AuraScale, a tail with no budget slot; Low: no ring extras, no scale
--   client_evo_twists        (BattleController, a real sim) one effect per Twist event at its point, the Patch zone's disc and tail, Shatter / Burst / Lingering, the callouts;
--                            a Thorns / Double strike hit draws no second swing
--   client_evo_budget        8 raiders' Thunder Packs + 8 Twists in one second under the caps; auras on 4 fighters + 10 plays
--   client_evo_looks_mobile  (phone world) the pack at 844x390 on Low: wolves plain, no rim
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, ceil, floor, max, min = math.abs, math.ceil, math.floor, math.max, math.min
local fmt = string.format

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
end

local function layerById(r, id)
	for _, l in ipairs(r and r.Layers or {}) do
		if l.Id == id then
			return l
		end
	end
	return nil
end

local function isEmitter(l)
	return l.Kind == "Emitter" or (l.Kind == "Decal" and type(l.Texture) == "string")
end

----------------------------------------------------------------------------------------------------
-- the server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function shared(name)
		local inst = K.moduleInstance("shared/" .. name)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	local function emittersOf(r)
		local n = (type(r.Alive) == "table" and isEmitter(r.Alive)) and 1 or 0
		for _, l in ipairs(r.Layers) do
			if isEmitter(l) then
				n = n + 1
			end
		end
		return n
	end

	-- the beams this recipe's own layers ask for (the engine's beamBudget hands them out under MAX_BEAMS: one layer each first)
	local function beamLayersOf(r)
		local n = (type(r.Alive) == "table" and r.Alive.Kind == "Beam") and 1 or 0
		for _, l in ipairs(r.Layers) do
			if l.Kind == "Beam" then
				n = n + 1
			end
		end
		return n
	end

	local function beamsAsked(r)
		local n = 0
		for _, l in ipairs(r.Layers) do
			if l.Kind == "Beam" then
				n = n + (l.Count or 1)
			end
		end
		return n
	end

	local function trailsOf(r)
		local n = 0
		for _, l in ipairs(r.Layers) do
			if l.Kind == "Trail" then
				n = n + min(2, l.Afterimages or 1)
			end
		end
		return n
	end

	local function lightsOf(r)
		local n = 0
		for _, l in ipairs(r.Layers) do
			if l.Kind == "Light" then
				n = n + 1
			end
		end
		return n
	end

	local function idsOf(r)
		local out = {}
		for _, l in ipairs(r.Layers) do
			out[l.Id] = true
		end
		return out
	end

	local function idList(r)
		local out = {}
		for i, l in ipairs(r.Layers) do
			out[i] = l.Id
		end
		return table.concat(out, ",")
	end

	local function capsProblem(r)
		if emittersOf(r) > 6 then
			return fmt("%d emitters (%s)", emittersOf(r), idList(r))
		elseif beamLayersOf(r) > 4 then
			return fmt("%d beam layers", beamLayersOf(r))
		elseif trailsOf(r) > 4 then
			return fmt("%d trails", trailsOf(r))
		elseif lightsOf(r) > 3 then
			return fmt("%d lights", lightsOf(r))
		elseif r.Size > 2.08 + 1e-9 then
			return fmt("size %s", tostring(r.Size))
		end
		return nil
	end

	-- every texture in a recipe is known and of the right sheet type; every piece's key is one of the game's cores (no new asset)
	local function assetProblem(C, cores, r)
		local function bad(what, k)
			return what .. " " .. tostring(k)
		end
		for _, l in ipairs(r.Layers) do
			local t = l.Texture and C.Textures[l.Texture]
			if l.Texture and not t then
				return bad("unknown texture", l.Texture)
			elseif t and (l.Kind == "Beam" or l.Kind == "Trail") and t.Grid ~= 1 then
				return bad("a flipbook on a strip layer", l.Id)
			elseif t and (l.Kind == "Emitter" or l.Kind == "Decal") and t.Grid ~= 4 then
				return bad("a strip on a flipbook layer", l.Id)
			end
			if l.Key and not cores[l.Key] then
				return bad("unknown key", l.Key)
			end
		end
		if r.Core.Key and not cores[r.Core.Key] then
			return bad("unknown core", r.Core.Key)
		end
		local actor = r.Sig and r.Sig.Actor
		if actor and not cores[actor.Key] then
			return bad("unknown actor", actor.Key)
		end
		return nil
	end

	S.evo_looks_catalog = guarded("evo_looks_catalog", function()
		local Cat = shared("AttackFxCatalog")
		local BC = shared("BattleCatalog")
		local PC = shared("PetCatalog")
		local Ids = shared("MeshIds")
		if not T.check(Cat ~= nil and BC ~= nil and PC ~= nil and Ids ~= nil, "evo looks: the modules load") then
			return
		end
		local cores = {}
		for k in pairs(Ids) do
			cores[k] = true
		end

		local function fang(stage, form)
			return Cat.Resolve({ Element = "Storm", Attack = "Special", Kind = "Pounce", Rarity = "Secret", Stage = stage, Form = form, PetId = "stormfang", Mine = true })
		end
		local r0 = fang(0)
		T.check(r0 ~= nil and r0.Sig ~= nil and r0.Sig.Actor == nil and layerById(r0, "SigShock") ~= nil and layerById(r0, "SigSlamBolts") ~= nil and layerById(r0, "SigCloudRide") ~= nil and layerById(r0, "SigBolts") == nil,
			"evo looks: Stormfang's start is a plain storm pounce: no wolf, no path bolts; slam ring, slam bolts and cloud kept")
		local r1 = fang(1, 1)
		T.check(r1 ~= nil and r1.Sig.Actor ~= nil and r1.Sig.Actor.Key == "vfx_sig_wolf" and r1.Sig.Actor.Count == 3 and r1.Sig.Actor.Motion == "PackCharge" and r1.Sig.Name == "Shadow Pack",
			"evo looks: Shadow Pack: three wolves on the charge line")
		local r2 = fang(2, 2)
		T.check(r2 ~= nil and r2.Sig.Actor.Count == 5 and r2.Sig.Actor.Key == "vfx_sig_wolf" and r2.Sig.Actor.Motion == "PackCharge" and r2.Sig.Name == "Thunder Pack",
			"evo looks: Thunder Pack: five wolves", r2 and r2.Sig.Name)
		local land = layerById(r2, "SigLandBolts")
		T.check(land ~= nil and land.Count == 4 and land.KeepCount == 4 and land.Strike == true and layerById(r2, "SigSlamBolts") == nil and beamsAsked(r2) <= 4,
			"evo looks: ...4 strikes at most: the slam's two bolts yield to them", land and tostring(land.Count))
		T.check(typeof(r1.Sig.Actor.Rim.Color) == "Color3" and r1.Sig.Actor.Rim.Scale == 1.08 and near(r2.Sig.Actor.Rim.Scale, 1.08) and r2.Sig.Actor.Color ~= r1.Sig.Actor.Color,
			"evo looks: stage 2 recolours the pack and keeps the rim's other numbers")
		T.check(type(Cat.Forms) == "table" and type(Cat.ElementForms) == "table" and type(Cat.Twists) == "table", "evo looks: Forms, ElementForms and Twists are tables")

		-- every kind x stage x rarity x mine x element: within the caps. A kind's Form is the stage. Form 0 is the plain recipe; stage 2 keeps stage 1
		local elements = {}
		for name in pairs(Cat.Elements) do
			elements[#elements + 1] = name
		end
		table.sort(elements)
		local matrix = T.tally("evo looks: every kind x stage x rarity x mine x element resolves within the caps (6 emitters, 4 beam layers, 4 trails, 3 lights, size 2.08)")
		local zero = T.tally("evo looks: Form 0 draws the plain recipe's layers")
		local keeps = T.tally("evo looks: Form 2's layers include Form 1's, Form 1's include the start's (a Pulse that yielded to the cap aside)")
		local assets = T.tally("evo looks: every form layer uses a known sheet and an existing core")
		local cases = 0
		for _, element in ipairs(elements) do
			for _, kind in ipairs(Cat.KindNames) do
				for _, rarity in ipairs(Cat.Rarities) do
					for _, mine in ipairs({ true, false }) do
						local function at(stage, form)
							return Cat.Resolve({ Element = element, Attack = "Special", Kind = kind, Rarity = rarity, Stage = stage, Form = form, Mine = mine })
						end
						local tag = fmt("%s %s %s %s", element, kind, rarity, tostring(mine))
						local plain, f0, f1, f2 = at(0), at(0, 0), at(1, 1), at(2, 2)
						for stage, r in ipairs({ f1, f2 }) do
							local p = r == nil and "nil" or capsProblem(r)
							matrix:case(p == nil, fmt("%s form %d: %s", tag, stage, tostring(p)))
							if r then
								local a = assetProblem(Cat, cores, r)
								assets:case(a == nil, fmt("%s form %d: %s", tag, stage, tostring(a)))
							end
							cases = cases + 1
						end
						zero:case(plain ~= nil and f0 ~= nil and idList(plain) == idList(f0), tag)
						if f1 and f2 then
							local has1, has2 = idsOf(f1), idsOf(f2)
							for id in pairs(has1) do
								keeps:case(has2[id] == true, tag .. " " .. id)
							end
							for id in pairs(idsOf(plain)) do
								keeps:case(has1[id] == true or id == "Pulse" or id == "Sparks", tag .. " start's " .. id)
							end
						end
					end
				end
			end
		end
		matrix:report(cases .. " recipes")
		zero:report()
		keeps:report()
		assets:report()

		-- every element x stage
		local elem = T.tally("evo looks: every element x stage x rarity x mine: ElementForms resolve within the caps; Form 0 is plain; Form 2 keeps Form 1")
		for _, element in ipairs(elements) do
			local shape = BC.ElementAttacks[element] and BC.ElementAttacks[element].Shape
			T.check(Cat.ElementForms[element] ~= nil and Cat.ElementForms[element][1] ~= nil and Cat.ElementForms[element][2] ~= nil, "evo looks: ElementForms has both stages of " .. element)
			local want = BC.ElementAttacks[element] and BC.ElementAttacks[element].Forms
			T.check(want ~= nil and Cat.ElementForms[element] ~= nil and Cat.ElementForms[element][1].Name == want[1].Name and Cat.ElementForms[element][2].Name == want[2].Name,
				"evo looks: ElementForms' names are BattleCatalog's for " .. element)
			for _, rarity in ipairs(Cat.Rarities) do
				for _, mine in ipairs({ true, false }) do
					local function at(stage, form)
						return Cat.Resolve({ Element = element, Attack = "Element", Shape = shape, Rarity = rarity, Stage = stage, Form = form, Mine = mine })
					end
					local tag = fmt("%s %s %s", element, rarity, tostring(mine))
					local plain, f0, f1, f2 = at(0), at(0, 0), at(1, 1), at(2, 2)
					local p1, p2 = capsProblem(f1), capsProblem(f2)
					elem:case(p1 == nil and p2 == nil, fmt("%s: %s / %s", tag, tostring(p1), tostring(p2)))
					elem:case(idList(plain) == idList(f0), tag .. " form 0")
					local has2 = idsOf(f2)
					for id in pairs(idsOf(f1)) do
						elem:case(has2[id] == true, tag .. " " .. id)
					end
					elem:case(idList(f1) ~= idList(plain) and idList(f2) ~= idList(f1), tag .. " each stage adds to the look")
					elem:case(assetProblem(Cat, cores, f2) == nil, tag .. " assets")
				end
			end
		end
		elem:report()

		-- the Twist recipes: which kind or element each belongs to, none charged
		local SPECIAL_TWISTS = { Aftershock = "Blast", Twin = "Beam", LastStrike = "Storm", Shatter = "Freeze", Chill = "Freeze", Burst = "Shield", Thorns = "Shield", Landing = "Pounce", Lingering = "Heal", Overflow = "Heal", DoubleHit = "Haste" }
		local ELEMENT_TWISTS = { Maelstrom = "Water", Fissure = "Earth", Rockspire = "Earth", Forked = "Storm", Starfall = "Celestial" }
		local tw = T.tally("evo looks: every Twists id resolves with Charge 0, Release 0, Travel 0 (Twin 0.1), within the caps, tinted by the element")
		local named = 0
		for id in pairs(Cat.Twists) do
			named = named + 1
			local kind, el = SPECIAL_TWISTS[id], ELEMENT_TWISTS[id]
			tw:case(kind ~= nil or el ~= nil, "unexpected twist " .. id)
			for _, rarity in ipairs(Cat.Rarities) do
				for _, mine in ipairs({ true, false }) do
					local attack = kind and "Special" or "Element"
					for _, element in ipairs(kind and elements or { el }) do
						local r = Cat.Resolve({ Element = element, Attack = attack, Kind = kind, Twist = id, Rarity = rarity, Stage = 2, Mine = mine })
						local tag = fmt("%s %s %s", id, element, rarity)
						if r then
							local p = capsProblem(r) or assetProblem(Cat, cores, r)
							tw:case(p == nil, tag .. ": " .. tostring(p))
							tw:case(r.Twist == id and r.Beats.Charge == 0 and r.Beats.Release == 0 and near(r.Beats.Travel, (id == "Twin") and 0.1 or 0), fmt("%s: beats %s %s %s", tag, tostring(r.Beats.Charge), tostring(r.Beats.Release), tostring(r.Beats.Travel)))
							tw:case(r.Afterglow == 0 and r.CameraPunch == false and r.ScreenGlow == false, tag .. " is quiet: no afterglow, no kick, no glow")
							tw:case(r.Palette.Mid == Cat.Elements[element].Palette.Mid, tag .. " in the element's colours")
						else
							tw:case(false, tag .. " does not resolve")
						end
					end
				end
			end
		end
		tw:report()
		T.check(named == 16, "evo looks: 16 twist recipes (the plan's 15 + the Thorns hit-back)", tostring(named))
		T.check(Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", Twist = "NoSuchTwist", Rarity = "Rare", Mine = true }) == nil, "evo looks: an unknown twist resolves to nil (the cube fallback)")
		local blue = Cat.Resolve({ Element = "Water", Attack = "Special", Kind = "Blast", Twist = "Aftershock", Rarity = "Rare", Mine = true })
		local red = Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", Twist = "Aftershock", Rarity = "Rare", Mine = true })
		T.check(layerById(blue, "Dome") ~= nil and layerById(blue, "Blastwave") ~= nil and layerById(blue, "Dome").Color ~= layerById(red, "Dome").Color and layerById(blue, "Blastwave").Reach == true,
			"evo looks: the Aftershock is the Blast's dome + blastwave at its real radius, in the element's colour")
		T.check(near(layerById(blue, "Dome").Grow, Cat.Specials.Blast.Layers[1].Grow * 0.7), "evo looks: ...the dome at 0.7 x", tostring(layerById(blue, "Dome").Grow))
		local twin = Cat.Resolve({ Element = "Frost", Attack = "Special", Kind = "Beam", Twist = "Twin", Rarity = "Secret", Mine = true })
		local beam = Cat.Resolve({ Element = "Frost", Attack = "Special", Kind = "Beam", Rarity = "Secret", Mine = true })
		T.check(twin.Core.Key == "vfx_beam" and twin.Core.Stretch == true and near(twin.Core.Thick, beam.Core.Thick * 0.8), "evo looks: the Twin is the Beam's core at Thick x 0.8", tostring(twin.Core.Thick))
		local fork = Cat.Resolve({ Element = "Storm", Attack = "Element", Twist = "Forked", Rarity = "Rare", Mine = true })
		T.check(layerById(fork, "ForkBolt") ~= nil and layerById(fork, "ForkBolt").Kind == "Beam" and layerById(fork, "ForkBolt").Texture == "fx_lightning", "evo looks: Forked is one lightning bolt")
		local rock = Cat.Resolve({ Element = "Earth", Attack = "Element", Twist = "Rockspire", Rarity = "Rare", Mine = true })
		T.check(rock.Shape == "Circle" and rock.Sig.Actor.Key == "vfx_sig_lava_spike" and rock.Sig.Actor.Motion == "RingRise", "evo looks: Rockspire's spikes are the lava spike recoloured, in a ring")
		T.check(rock.Sig.Actor.Color ~= Cat.Signatures.magma_cub.Palette.Mid, "evo looks: ...earth-brown, not lava")

		-- the Beam at every stage
		local thick = { 1.1, 1.3, 1.5, 1.7 }
		local beams = T.tally("evo looks: a Beam at Stage 0 has its Lens and Pulse, Core.Thick = the band's x 1.15")
		local yields = T.tally("evo looks: a Beam at the emitter cap drops Pulse before Wrap")
		local dropped = 0
		for _, element in ipairs(elements) do
			for _, rarity in ipairs(Cat.Rarities) do
				local r = Cat.Resolve({ Element = element, Attack = "Special", Kind = "Beam", Rarity = rarity, Stage = 0, Mine = true })
				local tag = element .. " " .. rarity
				local lens = layerById(r, "Lens")
				beams:case(lens ~= nil and lens.Kind == "Ring" and lens.Beat == "Charge" and lens.At == "Source" and lens.Level == true and near(lens.Grow, 1.2) and near(lens.Transparency, 0.35), tag .. " Lens")
				beams:case(near(r.Core.Thick, thick[r.Band] * 1.15), tag .. " Thick " .. tostring(r.Core.Thick))
				local pulse = layerById(r, "Pulse")
				if pulse then
					beams:case(pulse.Kind == "Emitter" and pulse.Texture == "fx_glow" and pulse.Beat == "Travel" and pulse.At == "Path" and pulse.Along == true and pulse.Color == r.Palette.Core and near(pulse.Size, 1.4), tag .. " Pulse")
				else
					dropped = dropped + 1
					local list = table.concat(r.Dropped or {}, ",")
					yields:case(string.find(list, "Pulse", 1, true) ~= nil and layerById(r, "Wrap") ~= nil, tag .. ": dropped " .. list)
				end
				yields:case(pulse ~= nil or layerById(r, "Wrap") ~= nil, tag .. " keeps its Wrap")
				local p = capsProblem(r)
				beams:case(p == nil, tag .. ": " .. tostring(p))
			end
		end
		beams:report()
		yields:report(dropped .. " Pulses yielded")
		local pulses = 0
		for _, element in ipairs(elements) do
			if layerById(Cat.Resolve({ Element = element, Attack = "Special", Kind = "Beam", Rarity = "Common", Stage = 0, Mine = true }), "Pulse") then
				pulses = pulses + 1
			end
		end
		T.check(pulses == #elements, "evo looks: every element's Beam has its Pulse (the owner: beams look boring): a Beam at the cap gives up an impact detail for it", fmt("%d of %d", pulses, #elements))
		local mark = layerById(Cat.Resolve({ Element = "Frost", Attack = "Special", Kind = "Beam", Rarity = "Rare", Stage = 1, Form = 1, Mine = true }), "MarkRing")
		T.check(mark ~= nil and mark.Kind == "Ring" and mark.Each == true and mark.At == "Target" and mark.Level == true and near(mark.Grow, 1.4) and near(mark.Transparency, 0.4), "evo looks: a stage-1 Beam marks each target (MarkRing)")
		T.check(layerById(Cat.Resolve({ Element = "Frost", Attack = "Special", Kind = "Beam", Rarity = "Rare", Stage = 0, Mine = true }), "MarkRing") == nil, "evo looks: ...a start's Beam has no mark")

		-- Rally and Haste carry their aura
		local rally = Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Rally", Rarity = "Rare", Stage = 0, Mine = true, Seconds = 8 })
		local haste = Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Haste", Rarity = "Rare", Stage = 0, Mine = true, Seconds = 8 })
		T.check(rally.Aura == 8 and haste.Aura == 8, "evo looks: Rally and Haste with Seconds = 8: recipe.Aura == 8", tostring(rally.Aura))
		T.check(layerById(rally, "AllyRing").Linger == true and layerById(rally, "Rouse").Linger == true and layerById(haste, "Wind").Linger == true and layerById(haste, "Gust").Linger == true,
			"evo looks: ...AllyRing, Rouse, Wind and Gust hold through it (Linger)")
		local plainRally = Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Rally", Rarity = "Rare", Stage = 0, Mine = true })
		T.check(plainRally.Aura == nil and layerById(plainRally, "AllyRing").Linger == nil and layerById(plainRally, "Rouse").Linger == nil, "evo looks: ...with no Seconds (a helper's plain buff) no aura and nothing holds")
		T.check(Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", Rarity = "Rare", Mine = true, Seconds = 8 }).Aura == nil, "evo looks: a Blast has no aura, whatever it is asked")
		local h1 = layerById(Cat.Resolve({ Element = "Storm", Attack = "Special", Kind = "Haste", Rarity = "Rare", Stage = 1, Form = 1, Mine = true }), "HasteRing")
		local h2 = layerById(Cat.Resolve({ Element = "Storm", Attack = "Special", Kind = "Haste", Rarity = "Rare", Stage = 2, Form = 2, Mine = true }), "HasteRing")
		T.check(h1 ~= nil and h2 ~= nil and near(h1.Grow, 1.3) and near(h2.Grow, 1.5) and h1.At == "Self" and h1.Level == true and h1.NoLow == true, "evo looks: Haste's HasteRing grows 1.3 / 1.5 by stage; none on Low")
		T.check(layerById(Cat.Resolve({ Element = "Storm", Attack = "Special", Kind = "Haste", Rarity = "Rare", Stage = 0, Mine = true }), "HasteRing") == nil, "evo looks: ...none at the start")

		-- the four Plain pets
		local PLAIN = {
			aurora_fox = { "Frost", "Beam", "Epic", "Aurora Mark", "Twin Aurora" }, moonlit_owl = { "Celestial", "Shield", "Epic", "Crescent Ward", "Full Moon Ward" },
			nebula_axolotl = { "Water", "Haste", "Epic", "Nebula Swirl", "Supernova Swirl" }, candy_unicorn = { "Celestial", "Haste", "Legendary", "Candy Rush", "Sugar Frenzy" },
		}
		local plains = T.tally("evo looks: the four Plain pets: Form 0 is the plain kind (no Signature), Forms 1 / 2 carry the spec's names")
		for id, row in pairs(PLAIN) do
			local sig = Cat.Signatures[id]
			plains:case(sig ~= nil and sig.Plain == true and sig.Element == row[1] and sig.Kind == row[2] and sig.Rarity == row[3], id .. " entry")
			local function at(stage, form, petId)
				return Cat.Resolve({ Element = row[1], Attack = "Special", Kind = row[2], Rarity = row[3], Stage = stage, Form = form, PetId = petId, Mine = true })
			end
			local kindOnly, start, stage0, one, two = at(0), at(0, nil, id), at(0, 0, id), at(1, 1, id), at(2, 2, id)
			plains:case(start.Signature == nil and start.Sig == nil and idList(start) == idList(kindOnly), id .. " no form")
			plains:case(stage0.Signature == nil and stage0.Sig == nil and idList(stage0) == idList(kindOnly), id .. " form 0")
			plains:case(one.Signature == id and one.Sig.Name == row[4], id .. " form 1: " .. tostring(one.Sig and one.Sig.Name))
			plains:case(two.Signature == id and two.Sig.Name == row[5], id .. " form 2: " .. tostring(two.Sig and two.Sig.Name))
			plains:case(idList(one) ~= idList(kindOnly) or one.Sig.Actor ~= nil or one.Core.Thick ~= kindOnly.Core.Thick, id .. " form 1 changes the look")
			plains:case(capsProblem(one) == nil and capsProblem(two) == nil, id .. " caps")
		end
		plains:report()

		-- the form names, every pet's. A pet with its own forms: Signatures[p].Forms[s].Name; a shared look: Forms[kind][s]
		local names = T.tally("evo looks: every form name of BattleCatalog.FormNames matches its look")
		local total, own = 0, 0
		for petId, list in pairs(BC.FormNames) do
			local def = PC.Get(petId)
			local kind = def and type(def.Special) == "table" and def.Special.Kind
			local sig = Cat.Signatures[petId]
			for stage, name in ipairs(list) do
				total = total + 1
				if sig then
					own = own + 1
					names:case(sig.Forms ~= nil and sig.Forms[stage] ~= nil and sig.Forms[stage].Name == name, fmt("%s %d: %s vs %s", petId, stage, tostring(sig.Forms and sig.Forms[stage] and sig.Forms[stage].Name), name))
				else
					names:case(kind and Cat.Forms[kind] ~= nil and Cat.Forms[kind][stage] ~= nil and type(Cat.Forms[kind][stage].Name) == "string", fmt("%s %d: no shared look for %s", petId, stage, tostring(kind)))
				end
			end
		end
		names:report(fmt("%d names, %d the pets' own", total, own))
		T.check(total == 49 and own == 32, "evo looks: 33 pets name 49 forms (17 with one, 16 with two; the plan's '40' miscounts)", fmt("%d / %d", total, own))
		local kinds = T.tally("evo looks: Forms has both stages of every kind, named as BattleCatalog.Forms")
		for _, kind in ipairs(Cat.KindNames) do
			for stage = 1, 2 do
				local look = Cat.Forms[kind] and Cat.Forms[kind][stage]
				kinds:case(look ~= nil and look.Name == BC.Forms[kind][stage].Id, fmt("%s %d: %s", kind, stage, tostring(look and look.Name)))
			end
		end
		kinds:report()

		-- every signature pet at its own rarity and form
		local forms = T.tally("evo looks: the 16 pets' forms within the caps at every rarity (a budget step-down draws one band lower)")
		local sigCount = 0
		for petId, sig in pairs(Cat.Signatures) do
			sigCount = sigCount + 1
			forms:case(sig.Forms ~= nil and sig.Forms[1] ~= nil and sig.Forms[2] ~= nil, petId .. " has two forms")
			for _, rarity in ipairs(Cat.Rarities) do
				for _, mine in ipairs({ true, false }) do
					for stage = 1, 2 do
						local r = Cat.Resolve({ Element = sig.Element, Attack = "Special", Kind = sig.Kind, Rarity = rarity, Stage = stage, Form = stage, PetId = petId, Mine = mine })
						local p = capsProblem(r) or assetProblem(Cat, cores, r)
						forms:case(p == nil, fmt("%s %s %d: %s", petId, rarity, stage, tostring(p)))
					end
				end
			end
			for stage, form in pairs(sig.Forms or {}) do
				for id in pairs(form.Twists or {}) do
					forms:case(Cat.Twists[id] ~= nil, fmt("%s %d: no twist %s", petId, stage, id))
				end
			end
		end
		forms:report()
		T.check(sigCount == 16, "evo looks: 16 Signatures entries (12 + the 4 Plain)", tostring(sigCount))
		-- a pet's flavour on a twist reaches the recipe, from the stage that names it
		local rise = Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", Twist = "Aftershock", Rarity = "Legendary", Stage = 1, PetId = "ember_phoenix", Mine = true })
		T.check(rise ~= nil and rise.Sig ~= nil and rise.Sig.Actor ~= nil and rise.Sig.Actor.Key == "vfx_sig_phoenix_wing", "evo looks: Phoenix Burst's second fire-bird is in its Aftershock (a pet's Twists flavour)")
		local none = Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", Twist = "Aftershock", Rarity = "Legendary", Stage = 1, Mine = true })
		T.check(none.Sig == nil or none.Sig.Actor == nil, "evo looks: ...another pet's plain Aftershock has none")

		T.check(Cat.Unit({ petId = "stormfang", special = { Form = 2 } }).Form == 2 and Cat.Unit({ petId = "stormfang" }).Form == nil, "evo looks: Unit carries info.special.Form")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- the client world
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local LocalPlayer = game:GetService("Players").LocalPlayer

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

	-- the engine on a fake clock: a caster at the origin looking down -Z, a target 12 studs off
	local function rig(name, startAt)
		local Fx = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local Cat = moduleAt(ROOTS.shared .. "/AttackFxCatalog")
		Fx.ClearAll()
		Fx._Deps({ MeshLibrary = fakeMeshLibrary() })
		Fx.SetQuality("High")
		local holder = Instance.new("Folder")
		holder.Name = name
		holder.Parent = workspace
		local R = { Fx = Fx, Cat = Cat, holder = holder, clock = startAt, errs0 = Fx.Stats().Errors }
		R.A = unitModel(holder, "A", Vector3.new(0, 2, 0))
		R.B = unitModel(holder, "B", Vector3.new(0, 2, -12))
		function R.ctx(over)
			local c = { Attack = "Melee", Element = "Flame", Rarity = "Secret", Stage = 0, Mine = true,
				From = { Unit = 1, Model = R.A }, To = { Unit = 2, Model = R.B }, Ground = 0.5, Now = R.clock }
			for k, v in pairs(over or {}) do
				c[k] = v
			end
			return c
		end
		function R.play(over)
			if not Fx.Play(R.ctx(over)) then
				return nil
			end
			return Fx._Live()[#Fx._Live()]
		end
		function R.run(seconds, each)
			for _ = 1, ceil(seconds * 30 - 1e-9) do
				R.clock = R.clock + 1 / 30
				Fx.Update(R.clock)
				if each then
					each()
				end
			end
		end
		function R.runTo(eff, rel, each)
			while R.clock - eff.Start < rel do
				R.clock = R.clock + 1 / 30
				Fx.Update(R.clock)
				if each then
					each()
				end
			end
		end
		function R.finish()
			Fx.ClearAll()
			Fx.SetQuality("High")
			Fx._Deps({ MeshLibrary = false })
			holder:Destroy()
		end
		return R
	end

	local function itemsOf(eff, id)
		local out = {}
		for _, it in ipairs(eff and eff.Items or {}) do
			if it.Layer and it.Layer.Id == id then
				out[#out + 1] = it
			end
		end
		return out
	end

	-- the actor pieces of an effect: wolves and their rim copies
	local function actorsOf(eff)
		local main, rims = {}, {}
		for _, it in ipairs(eff.Items) do
			if it.Actor then
				if it.Rim then
					rims[#rims + 1] = it
				else
					main[#main + 1] = it
				end
			end
		end
		return main, rims
	end

	-- a charge line: from 8 behind the caster (at the origin) through the target at (0, -12) to 3 past it: -Z is angle -pi/2
	local function packLine()
		return { X0 = 0, Z0 = 8, Angle = -math.pi / 2, Length = 23, Width = 4.6 }
	end

	-- a recorded Duel fed to the client (the client_afx_reach_draw fixture)
	local function duel(Sim, id, petId, evo, spots, extra)
		local me = LocalPlayer.UserId
		local frogs = {}
		for i = 1, #spots do
			frogs[i] = { PetId = "puddle_frog", Key = "puddle_frog", Level = 20, Tier = "Normal", Slot = i }
		end
		local sim = Sim.new({ Mode = "Duel", Seed = 23, Id = id, Zone = { X = 90, Z = 90 }, TimeLimit = 300,
			Teams = { { Owner = me, Side = 1, Pets = { { PetId = petId, Key = petId, Level = 50, Tier = "Normal", Slot = 1, Evo = evo } } },
				{ Owner = "frogs", Side = 2, Npc = true, Specials = false, Pets = frogs } } })
		local mine, foes = nil, {}
		for _, u in ipairs(sim.units) do
			u.maxHp, u.hp = 1e7, 1e7
			if u.side == 1 then
				mine = u
				u.x, u.z = 0, 0
			else
				foes[#foes + 1] = u
				local p = spots[#foes]
				u.x, u.z, u.moveSpeed = p[1], p[2], 0
			end
		end
		local start = sim:Describe()
		start.BattleId = id
		start.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(start.Zone.X, 30, start.Zone.Z), X = start.Zone.X, Z = start.Zone.Z }
		start.Names = { [tostring(me)] = LocalPlayer.Name }
		start.Side, start.Spectator, start.T = 1, false, sim:Time()
		local team = sim:TeamOf(me)
		if team then
			start.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
				Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = {} } }
		end
		LocalPlayer:SetAttribute("InBattle", id)
		KC.toClient("BattleState", "Start", start, id)
		local last = {}
		local function step(dt)
			local evs = sim:Step(dt)
			if #evs > 0 then
				KC.toClient("BattleState", "Events", evs, id)
			end
			local snap = sim:SnapshotDelta(last)
			snap.BattleId = id
			KC.toClient("BattleState", "Snapshot", snap, id)
			for _ = 1, max(1, floor(dt * 30 + 0.5)) do
				Mock.Step(1 / 30)
			end
			return evs
		end
		for _ = 1, 10 do
			step(0.1)
		end
		return sim, mine, foes, step
	end

	local function endDuel(id)
		KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
			Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0 } }, id)
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
	end

	-- the number / callout labels on the screen now
	local function labelsNow()
		local out = {}
		local function scan(root)
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("TextLabel") and d.Parent and d.Parent:IsA("BillboardGui") and d.Parent.Enabled then
					out[d.Text] = true
				end
			end
		end
		scan(workspace)
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		if pg then
			scan(pg)
		end
		return out
	end

	-- one real cast: a full meter, the lock on `aim`; steps on until `until_` says stop (or 3 s of sim); -> the events seen
	local function cast(sim, mine, aim, step)
		local me = LocalPlayer.UserId
		mine.meter, mine.castUntil, mine.nextAttack = 100, 0, 0
		if aim then
			sim:Command(me, "Target", aim.id)
		end
		local ok, why = sim:Command(me, "Special")
		return ok, why, step(0.1)
	end

	------------------------------------------------------------------------------------------------
	-- client_evo_pack: the wolves on the line
	------------------------------------------------------------------------------------------------
	S.client_evo_pack = guarded("client_evo_pack", function()
		local R = rig("SmokeEvoPack", 9100)
		local Fx = R.Fx
		local function pack(over)
			local c = { Attack = "Special", Kind = "Pounce", Element = "Storm", PetId = "stormfang", Rarity = "Secret", Stage = 1, Form = 1, Line = packLine() }
			for k, v in pairs(over or {}) do
				c[k] = v
			end
			return R.play(c)
		end
		local eff = pack()
		if not T.check(eff ~= nil, "evo pack: a Shadow Pack plays") then
			R.finish()
			return
		end
		local wolves, rims = actorsOf(eff)
		T.check(#wolves == 3 and #rims == 3, "evo pack: 3 wolf cores + 3 rims on High", fmt("%d / %d", #wolves, #rims))
		T.check(#wolves > 0 and wolves[1].Kit ~= nil and wolves[1].Motion == "PackCharge", "evo pack: ...running the PackCharge motion")
		-- every frame: each wolf's first visible spot, its spot at the impact, at the line's end
		local lineStart, dir = Vector3.new(0, 2, 8), Vector3.new(0, 0, -1)
		local right = dir:Cross(Vector3.new(0, 1, 0))
		local first, atImpact, atEnd, wide = {}, {}, {}, 0
		local T1 = eff.Times
		local function sample()
			local t = R.clock - eff.Start
			for i, w in ipairs(wolves) do
				local part = w.Kit and w.Kit.Root
				if part and part.Transparency < 1 then
					local p = part.Position
					if not first[i] then
						first[i] = p
					end
					local off = p - lineStart
					wide = max(wide, abs(off:Dot(right)))
				end
				if part and t >= T1.Impact and not atImpact[i] then
					atImpact[i] = part.Position
				end
				if part and w.TE and t >= w.TE and not atEnd[i] then
					atEnd[i] = part.Position
				end
			end
		end
		R.runTo(eff, eff.TailAt - 0.05, sample)
		local caster, target = Vector3.new(0, 2, 0), Vector3.new(0, 2, -12)
		local lineEnd = lineStart + dir * 23
		local behind, near0, hit, far = T.tally("evo pack: each wolf starts on the line's start, BEHIND the caster"), nil, nil, nil
		for i = 1, #wolves do
			local p = first[i]
			if p then
				behind:case((p - caster):Dot(dir) < 0 and abs((p - lineStart):Dot(dir)) <= 1.5, fmt("wolf %d first at %s", i, tostring(p)))
			else
				behind:case(false, fmt("wolf %d never shown", i))
			end
		end
		behind:report()
		local onHit = T.tally("evo pack: each wolf is within 2 of the target at the impact")
		local onEnd = T.tally("evo pack: each wolf ends within 2 of the line's end")
		for i = 1, #wolves do
			onHit:case(atImpact[i] ~= nil and (atImpact[i] - target).Magnitude <= 2, fmt("wolf %d: %s", i, tostring(atImpact[i])))
			onEnd:case(atEnd[i] ~= nil and abs((atEnd[i] - lineEnd):Dot(dir)) <= 2 and abs((atEnd[i] - lineEnd):Dot(right)) <= 4.6 / 2 + 1.5, fmt("wolf %d: %s", i, tostring(atEnd[i])))
		end
		onHit:report()
		onEnd:report()
		T.check(wide > 0.5 and wide <= 4.6 / 2 + 1.5, "evo pack: the pack spreads across the line and stays within Width / 2 + 1.5 of it", fmt("%.2f", wide))
		-- staggered 0.08 s
		T.check(wolves[2] ~= nil and near(wolves[2].T0 - wolves[1].T0, 0.08, 1e-6) and near(wolves[3].T0 - wolves[1].T0, 0.16, 1e-6), "evo pack: staggered 0.08 s")
		T.check(wolves[1] ~= nil and near(wolves[1].T0, T1.Travel, 1e-6) and near(wolves[1].TA, T1.Impact, 1e-6) and near(wolves[1].TE, T1.Impact + 0.25, 1e-6), "evo pack: over the Travel beat + 0.25 s")
		Fx.ClearAll()
		-- Low: plain
		Fx.SetQuality("Low")
		local low = pack()
		local lw, lr = actorsOf(low)
		T.check(#lw == 3 and #lr == 0, "evo pack: Low: 3 wolves, no rim", fmt("%d / %d", #lw, #lr))
		T.check(Fx.Stats().Beams == 0, "evo pack: Low: no bolts")
		Fx.ClearAll()
		Fx.SetQuality("High")
		-- someone else's pet
		local others = pack({ Mine = false })
		local ow, orims = actorsOf(others)
		T.check(#ow == 2 and #orims == 2, "evo pack: another player's Shadow Pack: 2 wolves (x 0.6)", fmt("%d / %d", #ow, #orims))
		Fx.ClearAll()
		-- a Thunder Pack
		local thunder = pack({ Stage = 2, Form = 2 })
		local tw, tr = actorsOf(thunder)
		T.check(#tw == 5 and #tr == 5, "evo pack: a Thunder Pack: 5 wolves + rims", fmt("%d / %d", #tw, #tr))
		T.check(thunder.Cores <= Fx.MAX_CORES and thunder.Beams <= Fx.MAX_BEAMS, "evo pack: ...Cores <= 14, Beams <= 4", fmt("%d / %d", thunder.Cores, thunder.Beams))
		T.check(#itemsOf(thunder, "SigLandBolts") == 4 and #itemsOf(thunder, "SigSlamBolts") == 0, "evo pack: ...its 4 strikes, the slam's two gone", tostring(#itemsOf(thunder, "SigLandBolts")))
		T.check(#itemsOf(thunder, "SigLandBolts") > 0 and itemsOf(thunder, "SigLandBolts")[1].Mode == "Strike", "evo pack: ...strike down where they land")
		Fx.ClearAll()
		local thunderOthers = pack({ Stage = 2, Form = 2, Mine = false })
		T.check(#(actorsOf(thunderOthers)) == 3, "evo pack: another player's Thunder Pack: floor(5 x 0.6 + 0.5) = 3 wolves", tostring(#(actorsOf(thunderOthers))))
		Fx.ClearAll()
		-- the start: no wolf at all
		local start = R.play({ Attack = "Special", Kind = "Pounce", Element = "Storm", PetId = "stormfang", Rarity = "Secret", Stage = 0 })
		T.check(#(actorsOf(start)) == 0 and #itemsOf(start, "SigSlamBolts") > 0 and #itemsOf(start, "SigShock") == 1, "evo pack: Stormfang's start has no wolf: the slam ring and bolts remain")
		Fx.ClearAll()
		-- a shared Pounce: ghost copies on the same line, in the pet's colours
		local ghosts = R.play({ Attack = "Special", Kind = "Pounce", Element = "Flame", PetId = "maple_fox", Rarity = "Uncommon", Stage = 1, Form = 1, Line = packLine() })
		local gw = actorsOf(ghosts)
		T.check(#gw == 3 and gw[1].Motion == "PackCharge" and gw[1].Color ~= nil and ghosts.Line ~= nil, "evo pack: a Common-Rare Pounce's ghost copies charge on the line", tostring(#gw))
		Fx.ClearAll()
		-- no line (the /fx preview): the look's own from behind the caster through the target
		local bare = R.play({ Attack = "Special", Kind = "Pounce", Element = "Storm", PetId = "stormfang", Rarity = "Secret", Stage = 1, Form = 1 })
		T.check(bare ~= nil and bare.Line ~= nil and (bare.Line.From - caster):Dot(bare.Dir) < 0, "evo pack: with no line the pack still comes from behind the caster")
		T.check(Fx.Stats().Errors == R.errs0, "evo pack: no engine error", tostring(Fx.Stats().Errors))
		R.finish()
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_beams
	------------------------------------------------------------------------------------------------
	S.client_evo_beams = guarded("client_evo_beams", function()
		local R = rig("SmokeEvoBeams", 9300)
		local Fx = R.Fx
		local third = unitModel(R.holder, "C", Vector3.new(3, 2, -14))
		local function beam(over)
			local c = { Attack = "Special", Kind = "Beam", Element = "Storm", Rarity = "Common", Stage = 0, Length = 26, Width = 4,
				To = { { Unit = 2, Model = R.B }, { Unit = 3, Model = third } } }
			for k, v in pairs(over or {}) do
				c[k] = v
			end
			return R.play(c)
		end
		local eff = beam()
		if not T.check(eff ~= nil, "evo beams: a Beam at Stage 0 plays") then
			R.finish()
			return
		end
		local lens = itemsOf(eff, "Lens")
		T.check(#lens == 1 and lens[1].T0 < eff.Times.Release + 1e-6 and lens[1].Anchor == "Source", "evo beams: a Lens ring at the mouth during the charge")
		local seenLens = false
		R.runTo(eff, eff.Times.Release, function()
			if lens[1] and lens[1].Kit and lens[1].Kit.Root.Transparency < 1 then
				seenLens = true
			end
		end)
		T.check(seenLens, "evo beams: ...drawn while the charge lasts")
		local pulse = itemsOf(eff, "Pulse")
		T.check(#pulse == 1 and pulse[1].Stream == "Along" and pulse[1].Mode == "Stream", "evo beams: Pulse emitters along the path")
		T.check(eff.Beams <= Fx.MAX_BEAMS, "evo beams: Beams <= 4", tostring(eff.Beams))
		T.check(#itemsOf(eff, "MarkRing") == 0, "evo beams: no mark at the start")
		Fx.ClearAll()
		local marked = beam({ Stage = 1, Form = 1 })
		local rings = itemsOf(marked, "MarkRing")
		T.check(#rings == 2 and rings[1].Anchor == 1 and rings[2].Anchor == 2, "evo beams: Stage 1: a MarkRing on each target", tostring(#rings))
		Fx.ClearAll()
		-- the Twin: 0.5 s after the first, a second stretched core; no second Cast pose
		local first = beam({ Stage = 2, Form = 2 })
		R.run(0.5)
		local poseBefore = Fx.Pose(1)
		local poseName = poseBefore and poseBefore.Name
		local twin = R.play({ Attack = "Special", Kind = "Beam", Element = "Storm", Twist = "Twin", Rarity = "Common", Stage = 2, Length = 26, Width = 4,
			Angle = -math.pi / 2, AimFixed = true, To = { Unit = 2, Model = R.B } })
		T.check(twin ~= nil and twin ~= first and twin.Recipe.Twist == "Twin", "evo beams: a Twin twist plays")
		local core, firstCore = nil, nil
		for _, it in ipairs(twin and twin.Items or {}) do
			if it.Line and it.Thick then
				core = it
			end
		end
		for _, it in ipairs(first.Items) do
			if it.Line and it.Thick then
				firstCore = it
			end
		end
		T.check(core ~= nil and firstCore ~= nil and near(core.Thick, firstCore.Thick * 0.8, 1e-6), "evo beams: ...a second stretched core at x 0.8", core and tostring(core.Thick))
		T.check(twin ~= nil and near(twin.Times.Travel, 0, 1e-6) and near(twin.Times.Impact, 0.1, 1e-6), "evo beams: ...no charge, a Travel of 0.1", twin and tostring(twin.Times.Impact))
		local poseAfter = Fx.Pose(1)
		T.check((poseAfter and poseAfter.Name) == poseName, "evo beams: ...the caster does not cast again", tostring(poseAfter and poseAfter.Name))
		R.run(0.15)
		T.check(core ~= nil and core.Kit ~= nil and core.Kit.Root.Transparency < 1, "evo beams: ...drawn on screen", core and core.Kit and tostring(core.Kit.Root.Transparency))
		T.check(Fx.Stats().Errors == R.errs0, "evo beams: no engine error")
		R.finish()
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_auras
	------------------------------------------------------------------------------------------------
	S.client_evo_auras = guarded("client_evo_auras", function()
		local R = rig("SmokeEvoAuras", 9500)
		local Fx = R.Fx
		T.check(type(Fx.EndAura) == "function", "evo auras: AttackFx.EndAura exists")
		local function rally(over)
			local c = { Attack = "Special", Kind = "Rally", Element = "Flame", Rarity = "Rare", Stage = 1, Form = 1, Seconds = 3, Scale = 1.2,
				To = { Unit = 1, Model = R.A } }
			for k, v in pairs(over or {}) do
				c[k] = v
			end
			return R.play(c)
		end
		local t0 = R.clock
		local eff = rally()
		if not T.check(eff ~= nil, "evo auras: a Rally plays") then
			R.finish()
			return
		end
		T.check(near(eff.AuraRel, 3 + (t0 - eff.Start), 1e-6) and near(eff.End, t0 + 3, 1e-6), "evo auras: the effect runs to its Seconds", fmt("AuraRel %s End - t0 %s", tostring(eff.AuraRel), tostring(eff.End - t0)))
		T.check(eff.TailAt < 3 and eff.Recipe.Aura == 3, "evo auras: past its beats", tostring(eff.TailAt))
		local ring, rouse, glow = itemsOf(eff, "AllyRing")[1], itemsOf(eff, "Rouse")[1], itemsOf(eff, "AllyGlow")[1]
		T.check(ring ~= nil and rouse ~= nil and glow ~= nil, "evo auras: its AllyRing, Rouse and flash")
		T.check(R.A:GetAttribute("AuraScale") == nil or R.A:GetAttribute("AuraScale") == 1, "evo auras: the pet is its size through the charge", tostring(R.A:GetAttribute("AuraScale")))
		R.runTo(eff, eff.Times.Impact + 1 / 30)
		T.check(near(R.A:GetAttribute("AuraScale"), 1.2, 1e-6), "evo auras: at the impact AuraScale = 1.2", tostring(R.A:GetAttribute("AuraScale")))
		while R.clock - t0 < 2.5 do
			R.run(1 / 30)
		end
		T.check(ring.Kit ~= nil and rouse.Kit ~= nil and itemsOf(eff, "AllyRing")[1] ~= nil, "evo auras: AllyRing and Rouse live at t0 + 2.5")
		T.check(ring.Kit ~= nil and ring.Kit.Root.Transparency < 1 and rouse.Mode == "Stream", "evo auras: ...the ring drawn, the motif streaming")
		T.check(eff.Tail == true, "evo auras: ...past the beats the effect is a tail: only its aura holds")
		local s = Fx.Stats()
		T.check(s.Live == 0 and s.Stepped == 0 and s.Tails == 1, "evo auras: ...in neither Live count", fmt("%d %d %d", s.Live, s.Stepped, s.Tails))
		T.check(near(R.A:GetAttribute("AuraScale"), 1.2, 1e-6), "evo auras: ...the pet still bigger", tostring(R.A:GetAttribute("AuraScale")))
		local p0 = ring.Kit.Root.Position
		R.A:PivotTo(CFrame.new(5, 2, 0))
		R.run(1 / 30)
		T.check((ring.Kit.Root.Position - p0).Magnitude > 2, "evo auras: ...the aura follows its pet")
		R.A:PivotTo(CFrame.new(0, 2, 0))
		while R.clock - t0 < 3.1 do
			R.run(1 / 30)
		end
		local gone = true
		for _, e in ipairs(Fx._Live()) do
			if e == eff then
				gone = false
			end
		end
		T.check(gone, "evo auras: gone by t0 + 3.1")
		T.check(R.A:GetAttribute("AuraScale") == 1, "evo auras: AuraScale back to 1 at the end", tostring(R.A:GetAttribute("AuraScale")))
		-- EndAura: ends within a frame
		t0 = R.clock
		eff = rally()
		while R.clock - t0 < 1 do
			R.run(1 / 30)
		end
		T.check(#itemsOf(eff, "AllyRing") == 1 and near(R.A:GetAttribute("AuraScale"), 1.2, 1e-6), "evo auras: at t0 + 1 the aura is on")
		T.check(Fx.EndAura(1) == true, "evo auras: EndAura(unit) says it ended one")
		R.run(1 / 30)
		T.check(#itemsOf(eff, "AllyRing") == 0 and #itemsOf(eff, "Rouse") == 0 and R.A:GetAttribute("AuraScale") == 1, "evo auras: ...within a frame: AllyRing and Rouse gone, the scale back", tostring(R.A:GetAttribute("AuraScale")))
		T.check(Fx.EndAura(1) == false and Fx.EndAura(77) == false, "evo auras: EndAura with no aura is nothing")
		R.run(1.5)
		-- EndAura as a tail, the unit's other effects untouched
		t0 = R.clock
		eff = rally()
		local melee = nil
		R.runTo(eff, eff.TailAt + 0.1)
		T.check(eff.Tail == true, "evo auras: a tail's aura")
		melee = R.play({ Attack = "Melee", Now = R.clock })
		Fx.EndAura(1)
		R.run(1 / 30)
		local alive, meleeAlive = false, false
		for _, e in ipairs(Fx._Live()) do
			alive = alive or e == eff
			meleeAlive = meleeAlive or e == melee
		end
		T.check(not alive and meleeAlive, "evo auras: EndAura on a tail finishes it, and leaves the unit's other effects")
		R.run(1.5)
		-- a second aura replaces the first; the scale stays until the last one ends
		eff = rally()
		R.runTo(eff, eff.Times.Impact + 0.05)
		local second = rally({ Now = R.clock })
		local count = 0
		for _, e in ipairs(Fx._Live()) do
			if e.AuraRel then
				count = count + 1
			end
		end
		T.check(count == 1 and second.AuraRel ~= nil, "evo auras: one aura a unit: a new cast replaces it", tostring(count))
		R.runTo(second, second.Times.Impact + 0.05)
		T.check(near(R.A:GetAttribute("AuraScale"), 1.2, 1e-6), "evo auras: ...its own scale on")
		Fx.Cancel(1)
		T.check(R.A:GetAttribute("AuraScale") == 1, "evo auras: Cancel puts the scale back")
		-- ClearAll too
		eff = rally()
		R.runTo(eff, eff.Times.Impact + 0.05)
		Fx.ClearAll()
		T.check(R.A:GetAttribute("AuraScale") == 1, "evo auras: ClearAll puts the scale back")
		-- no Scale: no attribute change, the hook reports the rest
		R.A:SetAttribute("AuraScale", nil)
		-- the hook hears every change
		local heard = {}
		local oldHook = Fx.Hooks.AuraScale
		Fx.Hooks.AuraScale = function(unit, k)
			heard[#heard + 1] = { unit, k }
		end
		eff = rally()
		R.runTo(eff, eff.Times.Impact + 0.05)
		Fx.EndAura(1)
		T.check(#heard == 2 and heard[1][1] == 1 and near(heard[1][2], 1.2) and heard[2][2] == 1, "evo auras: Hooks.AuraScale(unit, k) hears the growth and the return", tostring(#heard))
		Fx.Hooks.AuraScale = oldHook
		Fx.ClearAll()
		-- Haste
		local function haste(over)
			local c = { Attack = "Special", Kind = "Haste", Element = "Storm", Rarity = "Rare", Stage = 2, Form = 2, Seconds = 3,
				To = { Unit = 1, Model = R.A } }
			for k, v in pairs(over or {}) do
				c[k] = v
			end
			return R.play(c)
		end
		t0 = R.clock
		eff = haste()
		local wind, gust = itemsOf(eff, "Wind")[1], itemsOf(eff, "Gust")[1]
		T.check(wind ~= nil and gust ~= nil and #itemsOf(eff, "HasteRing") == 1, "evo auras: a Haste's Wind, Gust and HasteRing")
		while R.clock - t0 < 2.5 do
			R.run(1 / 30)
		end
		T.check(wind ~= nil and wind.Kit ~= nil and gust.Kit ~= nil and wind.T1 >= 2.5 and wind.Kit.Trail.Enabled == true, "evo auras: Wind streams for its Seconds", tostring(wind and wind.T1))
		T.check(gust.Mode == "Stream" and gust.T1 >= 2.4, "evo auras: Gust streams for its Seconds", tostring(gust.T1))
		T.check(#itemsOf(eff, "HasteRing") == 0, "evo auras: the HasteRing is a pulse at the cast, not an aura")
		local lastPos = wind.Kit.Root.Position
		R.run(5 / 30)
		T.check((wind.Kit.Root.Position - lastPos).Magnitude > 0.2, "evo auras: the wind still circles the pet near the end")
		while R.clock - t0 < 3.1 do
			R.run(1 / 30)
		end
		T.check(wind.Kit == nil and gust.Kit == nil, "evo auras: ...gone by the end")
		-- a Haste has no bigger pet: no attribute
		R.A:SetAttribute("AuraScale", nil)
		eff = haste()
		R.runTo(eff, eff.Times.Impact + 0.05)
		T.check(R.A:GetAttribute("AuraScale") == nil, "evo auras: a Haste does not grow the pet")
		Fx.ClearAll()
		-- Low: no HasteRing, no scale, still only its 2 emitters
		Fx.SetQuality("Low")
		eff = haste({ Seconds = 3 })
		T.check(#itemsOf(eff, "HasteRing") == 0, "evo auras: Low: no HasteRing")
		T.check(eff.Emitters <= 2 and #itemsOf(eff, "Gust") == 1 and eff.AuraRel ~= nil, "evo auras: Low: the kind's Low recipe, the Gust holding", tostring(eff.Emitters))
		T.check(#itemsOf(eff, "Wind") == 0 and eff.Trails == 0, "evo auras: Low: no trail")
		Fx.ClearAll()
		R.A:SetAttribute("AuraScale", nil)
		eff = rally()
		R.runTo(eff, eff.Times.Impact + 0.05)
		T.check(R.A:GetAttribute("AuraScale") == nil, "evo auras: Low: no bigger pet", tostring(R.A:GetAttribute("AuraScale")))
		Fx.ClearAll()
		Fx.SetQuality("High")
		-- a switch to Low mid-aura: the look ends, the scale goes back
		eff = rally()
		R.runTo(eff, eff.TailAt + 0.05)
		T.check(near(R.A:GetAttribute("AuraScale"), 1.2, 1e-6), "evo auras: on before the switch")
		Fx.SetQuality("Low")
		R.run(1 / 30)
		T.check(R.A:GetAttribute("AuraScale") == 1, "evo auras: switching to Low ends the bigger pet")
		Fx.ClearAll()
		Fx.SetQuality("High")
		-- a predicted charge is no aura
		local preOk = Fx.Precharge(R.ctx({ Kind = "Rally", Element = "Flame", Rarity = "Rare", Seconds = 0.7, To = { Unit = 1, Model = R.A } }))
		local pre = Fx.Precharging(1)
		T.check(preOk == true and pre ~= nil and pre.AuraRel == nil and pre.Recipe.Aura == nil, "evo auras: a press's predicted charge has no aura (its Seconds are the wait)")
		Fx.ClearAll()
		-- a helper's buff: no Seconds, plain
		eff = R.play({ Attack = "Special", Kind = "Rally", Element = "Flame", Rarity = "Rare", Stage = 1, To = { Unit = 1, Model = R.A } })
		T.check(eff ~= nil and eff.AuraRel == nil and itemsOf(eff, "AllyRing")[1].Lingers ~= true, "evo auras: no Seconds: the plain Rally")
		Fx.ClearAll()
		-- very short Seconds: a buff that is already ending holds nothing past its beats
		eff = rally({ Seconds = 0.2 })
		T.check(eff ~= nil and near(eff.EndRel, eff.TailAt, 1e-6), "evo auras: Seconds shorter than the beats: the beats still play", eff and tostring(eff.EndRel))
		T.check(Fx.Stats().Errors == R.errs0, "evo auras: no engine error", tostring(Fx.Stats().Errors))
		R.finish()
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_forms: through BattleController
	------------------------------------------------------------------------------------------------
	S.client_evo_forms = guarded("client_evo_forms", function()
		local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
		local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local Sim = moduleAt(ROOTS.shared .. "/BattleSim")
		local BCat = moduleAt(ROOTS.shared .. "/BattleCatalog")
		if not T.check(BC ~= nil and AF ~= nil and Sim ~= nil and BCat ~= nil, "evo forms: the modules load") then
			return
		end
		AF.ClearAll()
		AF._Deps({ MeshLibrary = fakeMeshLibrary() })
		AF.SetQuality("High")
		local function liveFor(unit, pred)
			for _, e in ipairs(AF._Live()) do
				if e.Unit == unit and pred(e) then
					return e
				end
			end
			return nil
		end
		-- a real stage-1 Stormfang: its Special event, the sim's own numbers
		local id = "evo_forms_fang"
		local sim, mine, foes, step = duel(Sim, id, "stormfang", 1, { { 10, 0 } })
		local ok, why, evs = cast(sim, mine, foes[1], step)
		T.check(ok == true, "evo forms: Stormfang casts", tostring(why))
		local special = nil
		for _, ev in ipairs(evs) do
			if ev.type == "Special" then
				special = ev
			end
		end
		T.check(special ~= nil and special.form == 1 and special.x0 ~= nil and special.name == "Shadow Pack", "evo forms: the sim's event: form 1, its line, its name")
		local eff = liveFor(mine.id, function(e)
			return e.Recipe.Attack == "Special"
		end)
		T.check(eff ~= nil and eff.Recipe.Sig ~= nil and eff.Recipe.Sig.Name == "Shadow Pack" and eff.Recipe.Stage == 1, "evo forms: AttackFx plays the Shadow Pack")
		if eff and special then
			T.check(eff.Line ~= nil, "evo forms: ...with its charge line")
			if eff.Line then
				-- (the caster is already leaping: measured from the standing target; the sim: the line runs Past = 3 studs through it, from 8 behind the caster's spot)
				local from = eff.Line.From - eff.S
				local flatFrom = Vector3.new(from.X, 0, from.Z)
				local toTarget = eff.T[1] - eff.Line.From
				local back = math.sqrt((special.x - special.x0) ^ 2 + (special.z - special.z0) ^ 2)
				T.check(near(back, 8, 0.2) and flatFrom:Dot(eff.Dir) < 0 and near(Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude, special.length - 3, 0.5), "evo forms: the line starts behind the caster in WORLD space, 8 studs back", fmt("%.2f back, %.2f to the target of %.2f", back, Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude, special.length))
				T.check(near(eff.Line.Length, special.length, 1e-6) and near(eff.Line.Width, special.width, 1e-6), "evo forms: its length and width are the event's", fmt("%s / %s", tostring(eff.Line.Length), tostring(eff.Line.Width)))
				local along = eff.T[1] - eff.Line.From
				T.check(abs(along:Dot(eff.Line.Right)) < 0.5, "evo forms: the line runs through the target", tostring(along:Dot(eff.Line.Right)))
			end
			local wolves = actorsOf(eff)
			T.check(#wolves == 3, "evo forms: three wolves", tostring(#wolves))
		end
		local seen = false
		for _ = 1, 12 do
			if labelsNow()["SHADOW PACK!"] then
				seen = true
			end
			Mock.Step(1 / 30)
		end
		T.check(seen, "evo forms: the callout reads SHADOW PACK!")
		endDuel(id)

		-- a start's Stormfang: no line, no wolf
		id = "evo_forms_fang0"
		sim, mine, foes, step = duel(Sim, id, "stormfang", 0, { { 10, 0 } })
		ok, why, evs = cast(sim, mine, foes[1], step)
		eff = liveFor(mine.id, function(e)
			return e.Recipe.Attack == "Special"
		end)
		T.check(eff ~= nil and eff.Line == nil and #(actorsOf(eff)) == 0, "evo forms: Stormfang's start: no line, no wolf")
		endDuel(id)

		-- a ranged Earth pet's Circle on its aim point; a melee one on itself
		local earthRanged, earthMelee = nil, nil
		local PC = moduleAt(ROOTS.shared .. "/PetCatalog")
		for _, def in ipairs(PC.Pets) do
			local els = def.Element
			if els == "Earth" and def.Role ~= "Economy" and not def.EventOnly then
				local attack = BCat.ProfileOf(def).Attack
				if attack == "Ranged" and not earthRanged then
					earthRanged = def.Id
				elseif attack == "Melee" and not earthMelee then
					earthMelee = def.Id
				end
			end
		end
		T.check(earthMelee ~= nil, "evo forms: a melee Earth pet", tostring(earthMelee))
		local function element(petId, sid, aimX)
			local s, m, f, st = duel(Sim, sid, petId, 0, { { aimX, 0 } })
			local me = LocalPlayer.UserId
			-- the event as the sim would send a ranged pet's, on the aim point
			KC.toClient("BattleState", "Events", { { type = "Element", unit = m.id, element = "Earth", name = "Quake", x = 0, z = 0, angle = 0, tx = aimX, tz = 0, shape = "Circle", targets = { f[1].id }, r = 12 } }, sid)
			local e = nil
			for _ = 1, 30 do
				Mock.Step(1 / 30)
				e = liveFor(m.id, function(x)
					return x.Recipe.Attack == "Element"
				end)
				if e then
					break
				end
			end
			return e, m, f, s, me
		end
		if earthRanged then
			local e, m, f = element(earthRanged, "evo_forms_ranged", 10)
			T.check(e ~= nil and (Vector3.new(e.Hit.X, 0, e.Hit.Z) - Vector3.new(e.T[1].X, 0, e.T[1].Z)).Magnitude <= 0.5, "evo forms: a ranged Earth pet's Circle is centred on its aim point", e and tostring(e.Hit))
			T.check(e ~= nil and (Vector3.new(e.Hit.X, 0, e.Hit.Z) - Vector3.new(e.S.X, 0, e.S.Z)).Magnitude > 5, "evo forms: ...far from itself", e and tostring(e.Hit))
			endDuel("evo_forms_ranged")
		else
			T.check(true, "evo forms: (no ranged Earth pet in the catalog)")
		end
		local e2 = element(earthMelee, "evo_forms_melee", 10)
		T.check(e2 ~= nil and (Vector3.new(e2.Hit.X, 0, e2.Hit.Z) - Vector3.new(e2.S.X, 0, e2.S.Z)).Magnitude <= 0.5, "evo forms: a melee one's on itself", e2 and tostring(e2.Hit))
		endDuel("evo_forms_melee")

		-- a real Rally: the aura runs to the buff's until, the pet back at the end; KO ends it
		id = "evo_forms_rally"
		sim, mine, foes, step = duel(Sim, id, "waffle_corgi", 1, { { 10, 0 } })
		ok, why, evs = cast(sim, mine, foes[1], step)
		eff = liveFor(mine.id, function(e)
			return e.AuraRel ~= nil
		end)
		T.check(eff ~= nil and eff.Recipe.Kind == "Rally", "evo forms: a real Rally plays its aura")
		if eff then
			local left = eff.End - os.clock()
			T.check(left > 6.5 and left < 9, "evo forms: ...for the buff's 8 seconds", tostring(left))
			T.check(eff.Scale ~= nil and near(eff.Scale, 1.2, 1e-6), "evo forms: ...a stage-1 Rally's bigger pet is x1.2", tostring(eff.Scale))
		end
		endDuel(id)

		-- a real Haste, its aura ends with the Speed event
		id = "evo_forms_haste"
		sim, mine, foes, step = duel(Sim, id, "pebble_pup", 0, { { 10, 0 } })
		ok, why, evs = cast(sim, mine, foes[1], step)
		eff = liveFor(mine.id, function(e)
			return e.AuraRel ~= nil
		end)
		T.check(eff ~= nil and eff.Recipe.Kind == "Haste", "evo forms: a real Haste plays its aura at the start too")
		local speedAt = nil
		for _ = 1, 100 do
			local e2s = step(0.1)
			for _, ev in ipairs(e2s) do
				if ev.type == "Speed" and speedAt == nil and sim:Time() > 7 then
					speedAt = sim:Time()
				end
			end
			if speedAt then
				break
			end
		end
		T.check(speedAt ~= nil, "evo forms: the Speed event falls back", tostring(speedAt))
		for _ = 1, 15 do
			Mock.Step(1 / 30)
		end
		local still = liveFor(mine.id, function(e)
			return e.AuraRel ~= nil
		end)
		T.check(still == nil, "evo forms: ...and the aura has ended with it")
		endDuel(id)

		AF._Deps({ MeshLibrary = false })
		AF.SetQuality("High")
		KC.flushErrors("client_evo_forms")
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_twists
	------------------------------------------------------------------------------------------------
	S.client_evo_twists = guarded("client_evo_twists", function()
		local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
		local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local Sim = moduleAt(ROOTS.shared .. "/BattleSim")
		if not T.check(BC ~= nil and AF ~= nil and Sim ~= nil, "evo twists: the modules load") then
			return
		end
		AF.ClearAll()
		AF._Deps({ MeshLibrary = fakeMeshLibrary() })
		AF.SetQuality("High")
		local function twistsLive(id)
			local out = {}
			for _, e in ipairs(AF._Live()) do
				if e.Recipe.Twist == id then
					out[#out + 1] = e
				end
			end
			return out
		end
		-- runs the sim until a Twist of this id arrives; -> its event
		local function waitFor(step, twist, seconds)
			for _ = 1, floor(seconds * 10) do
				for _, ev in ipairs(step(0.1)) do
					if ev.type == "Twist" and ev.twist == twist then
						return ev
					end
				end
			end
			return nil
		end

		-- a Blast fighter at Evo 1 against standing frogs
		local id = "evo_twist_blast"
		local sim, mine, foes, step = duel(Sim, id, "puddle_frog", 1, { { 10, 0 }, { 11, 2 } })
		local ok, why = cast(sim, mine, foes[1], step)
		T.check(ok == true, "evo twists: the Blast casts", tostring(why))
		local after = waitFor(step, "Aftershock", 1.5)
		if T.check(after ~= nil, "evo twists: the sim sends an Aftershock") then
			local list = twistsLive("Aftershock")
			T.check(#list == 1, "evo twists: it plays ONE AttackFx effect", tostring(#list))
			local e = list[1]
			if e then
				T.check(e.Kind == "Blast" and e.Recipe.Twist == "Aftershock" and e.Recipe.Kind == "Blast", "evo twists: ...Kind Blast, Twist Aftershock")
				local want = sim.units and nil
				local g = e.Hit
				local dx, dz = g.X - e.Src.Last.X, g.Z - e.Src.Last.Z
				T.check(abs(dx) < 0.01 and abs(dz) < 0.01, "evo twists: ...its From is the point")
				T.check(near(e.Reach, after.r, 1e-6), "evo twists: ...its ground ring peaks at the event's radius", tostring(e.Reach))
				local wave = itemsOf(e, "Blastwave")[1]
				T.check(wave ~= nil and near(wave.To * wave.Base.X * wave.S / 2, after.r, 0.05), "evo twists: ...the Blastwave's peak", wave and tostring(wave.To))
			end
			local seen = false
			for _ = 1, 8 do
				if labelsNow()["AFTERSHOCK!"] then
					seen = true
				end
				Mock.Step(1 / 30)
			end
			T.check(seen, "evo twists: the callout is the twist's name")
		end
		endDuel(id)

		-- a Blast at Evo 2: the burning ground, a disc of its r with the tail
		id = "evo_twist_patch"
		sim, mine, foes, step = duel(Sim, id, "ember_phoenix", 2, { { 10, 0 } })
		cast(sim, mine, foes[1], step)
		local patch = nil
		for _ = 1, 3 do
			if not patch then
				for _, ev in ipairs(step(0.1)) do
					if ev.type == "Zone" and ev.kind == "Patch" then
						patch = ev
					end
				end
			end
		end
		-- (the cast's own step already sent it: send a hand-made one where nothing else can be mistaken for it)
		local R_PATCH = 6.7
		KC.toClient("BattleState", "Events", { { type = "Zone", unit = mine.id, kind = "Patch", special = "Blast", x = 20, z = 20, r = R_PATCH, seconds = 2, side = 1 } }, id)
		local function discOf()
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "BattleFx" and near(d.Size.Y, R_PATCH * 2, 1e-6) and near(d.Size.Z, R_PATCH * 2, 1e-6) then
					return d
				end
			end
			return nil
		end
		local function frames(seconds)
			for _ = 1, floor(seconds * 30 + 0.5) do
				Mock.Step(1 / 30)
			end
		end
		frames(1)
		local disc = discOf()
		T.check(disc ~= nil and disc.Transparency < 0.7, "evo twists: a Patch zone draws a disc of its r", disc and tostring(disc.Transparency))
		local mid = disc and disc.Color
		T.check(mid ~= nil and mid ~= Color3.fromRGB(255, 120, 60), "evo twists: ...in the special's colour, not a boss pool's")
		frames(1.3)
		disc = discOf()
		T.check(disc ~= nil and disc.Transparency >= 0.85 and disc.Transparency < 1, "evo twists: ...past its seconds it stays dim (K.ZONE_TAIL)", disc and tostring(disc.Transparency))
		frames(1.4)
		T.check(discOf() == nil, "evo twists: ...then gone")
		endDuel(id)
		-- an element's Patch reads the element's colour (a fresh fight: with no snapshots for seconds the render clock fell behind the last one)
		id = "evo_twist_patch_el"
		sim, mine, foes, step = duel(Sim, id, "ember_phoenix", 2, { { 10, 0 } })
		KC.toClient("BattleState", "Events", { { type = "Zone", unit = mine.id, kind = "Patch", special = "Flame", x = 20, z = 20, r = R_PATCH, seconds = 1, side = 1 } }, id)
		frames(1)
		T.check(discOf() ~= nil, "evo twists: an Inferno's Patch draws too")
		frames(2.8)
		endDuel(id)

		-- a Freeze at Evo 2 (a real Shatter)
		id = "evo_twist_freeze"
		sim, mine, foes, step = duel(Sim, id, "rime_wyrmling", 2, { { 10, 0 } })
		cast(sim, mine, foes[1], step)
		local shatter = waitFor(step, "Shatter", 5)
		if T.check(shatter ~= nil, "evo twists: the sim sends a Shatter") then
			T.check(#twistsLive("Shatter") == 1, "evo twists: ...it plays once", tostring(#twistsLive("Shatter")))
			local e = twistsLive("Shatter")[1]
			T.check(e ~= nil and e.Recipe.Sig ~= nil and e.Recipe.Sig.Actor ~= nil and e.Recipe.Sig.Actor.Key == "vfx_sig_glacier", "evo twists: ...Glacier Shatter: the whole glacier shatters outward", e and tostring(e.Recipe.Sig and e.Recipe.Sig.Actor and e.Recipe.Sig.Actor.Key))
		end
		endDuel(id)

		-- a Shield at Evo 2 (a real Burst when it runs out: a Legendary, a Common evolves once)
		id = "evo_twist_shield"
		sim, mine, foes, step = duel(Sim, id, "sunbeam_bear", 2, { { 10, 0 } })
		mine.hp = mine.maxHp * 0.5
		cast(sim, mine, foes[1], step)
		local burst = waitFor(step, "Burst", 8)
		if T.check(burst ~= nil, "evo twists: the sim sends a Burst") then
			T.check(#twistsLive("Burst") == 1, "evo twists: ...it plays once", tostring(#twistsLive("Burst")))
		end
		endDuel(id)

		-- a Heal at Evo 1 (real Lingering ticks: one effect per tick, the heal's number, no callout)
		id = "evo_twist_heal"
		sim, mine, foes, step = duel(Sim, id, "honey_bunny", 1, { { 10, 0 } })
		mine.hp = mine.maxHp * 0.1
		cast(sim, mine, foes[1], step)
		local tick = waitFor(step, "Lingering", 3)
		if T.check(tick ~= nil, "evo twists: the sim sends a Lingering tick") then
			T.check(#twistsLive("Lingering") == 1, "evo twists: ...it plays once", tostring(#twistsLive("Lingering")))
		end
		endDuel(id)

		-- the wire's other twists, by hand: every one plays (mine, no error), a cube ring when AttackFx is refused
		id = "evo_twist_wire"
		sim, mine, foes, step = duel(Sim, id, "puddle_frog", 1, { { 10, 0 } })
		local foeId = foes[1].id
		local wire = {
			{ type = "Twist", unit = mine.id, kind = "Beam", twist = "Twin", x = 0, z = 0, angle = 0, length = 26, width = 4, targets = { foeId } },
			{ type = "Twist", unit = mine.id, kind = "Storm", twist = "LastStrike", x = 10, z = 0, r = 6, targets = { foeId } },
			{ type = "Twist", unit = mine.id, kind = "Freeze", twist = "Chill", x = 10, z = 0, targets = { foeId } },
			{ type = "Twist", unit = mine.id, kind = "Heal", twist = "Overflow", shields = { mine.id }, amount = 50 },
			{ type = "Twist", unit = mine.id, kind = "Water", twist = "Maelstrom", x = 0, z = 0, angle = 0, length = 14, targets = { foeId } },
			{ type = "Twist", unit = mine.id, kind = "Earth", twist = "Fissure", x = 10, z = 0, r = 8, targets = { foeId } },
			{ type = "Twist", unit = mine.id, kind = "Earth", twist = "Rockspire", x = 10, z = 0, r = 8, band = 3, targets = { foeId } },
			{ type = "Twist", unit = mine.id, kind = "Storm", twist = "Forked", x = 10, z = 0, tx = 14, tz = 0, targets = { foeId } },
			{ type = "Twist", unit = mine.id, kind = "Celestial", twist = "Starfall", x = 0, z = 0, heals = { { mine.id, 40 } } },
		}
		local plays = T.tally("evo twists: every twist of the wire plays one effect")
		for _, ev in ipairs(wire) do
			AF.ClearAll()
			KC.toClient("BattleState", "Events", { ev }, id)
			frames(0.2)
			plays:case(#twistsLive(ev.twist) == 1, fmt("%s: %d", ev.twist, #twistsLive(ev.twist)))
		end
		plays:report()
		-- the Fork runs from the last struck to the next
		AF.ClearAll()
		KC.toClient("BattleState", "Events", { wire[8] }, id)
		frames(0.1)
		local fork = twistsLive("Forked")[1]
		if T.check(fork ~= nil, "evo twists: a Forked bolt") then
			local d = (fork.Hit - fork.S)
			T.check(near(Vector3.new(d.X, 0, d.Z).Magnitude, 4, 0.2), "evo twists: ...from the last struck to the next (4 studs)", tostring(Vector3.new(d.X, 0, d.Z).Magnitude))
			T.check(#itemsOf(fork, "ForkBolt") == 1, "evo twists: ...one bolt")
		end
		-- Rockspire's ring stands at the band
		AF.ClearAll()
		KC.toClient("BattleState", "Events", { wire[7] }, id)
		frames(0.1)
		local rock = twistsLive("Rockspire")[1]
		if T.check(rock ~= nil, "evo twists: a Rockspire") then
			local spikes = actorsOf(rock)
			T.check(#spikes >= 3, "evo twists: ...its spikes", tostring(#spikes))
			if spikes[1] then
				local off = math.sqrt((spikes[1].OffR or 0) ^ 2 + (spikes[1].OffD or 0) ^ 2)
				T.check(near(off, 8 + 3 / 2, 0.1), "evo twists: ...in a ring at the band's middle", tostring(off))
			end
		end
		AF.ClearAll()

		-- Double strike and Thorns: a small flash, no second swing or lunge
		local a, v = mine, foes[1]
		KC.toClient("BattleState", "Events", { { type = "Hit", from = a.id, to = v.id, dmg = 5, double = true } }, id)
		frames(0.2)
		T.check(#twistsLive("DoubleHit") == 1, "evo twists: Hit.double plays the DoubleHit flash", tostring(#twistsLive("DoubleHit")))
		local swings = 0
		for _, e in ipairs(AF._Live()) do
			if e.Recipe.Attack == "Melee" or e.Recipe.Attack == "Ranged" then
				swings = swings + 1
			end
		end
		T.check(swings == 0, "evo twists: ...no second swing", tostring(swings))
		AF.ClearAll()
		frames(0.4)
		KC.toClient("BattleState", "Events", { { type = "Hit", from = a.id, to = v.id, dmg = 5, thorns = true } }, id)
		frames(0.2)
		T.check(#twistsLive("Thorns") == 1, "evo twists: Hit.thorns plays the hit-back", tostring(#twistsLive("Thorns")))
		swings = 0
		for _, e in ipairs(AF._Live()) do
			if e.Recipe.Attack == "Melee" or e.Recipe.Attack == "Ranged" then
				swings = swings + 1
			end
		end
		T.check(swings == 0, "evo twists: ...no swing from the wearer", tostring(swings))
		-- ...at most one a RIPPLE gap
		AF.ClearAll()
		frames(0.8)
		KC.toClient("BattleState", "Events", { { type = "Hit", from = a.id, to = v.id, dmg = 5, thorns = true }, { type = "Hit", from = a.id, to = v.id, dmg = 5, thorns = true }, { type = "Hit", from = a.id, to = v.id, dmg = 5, thorns = true } }, id)
		frames(0.1)
		T.check(#twistsLive("Thorns") == 1, "evo twists: a burst of thorns hits plays one", tostring(#twistsLive("Thorns")))
		endDuel(id)

		-- a Pounce at Evo 2: the Landing burst plays with the charge
		id = "evo_twist_pounce"
		sim, mine, foes, step = duel(Sim, id, "stormfang", 2, { { 10, 0 } })
		cast(sim, mine, foes[1], step)
		T.check(#twistsLive("Landing") == 1, "evo twists: a stage-2 Pounce plays its Landing", tostring(#twistsLive("Landing")))
		local landing = twistsLive("Landing")[1]
		if landing then
			T.check(landing.Reach ~= nil and landing.Reach > 3, "evo twists: ...at the burst's radius", tostring(landing.Reach))
		end
		endDuel(id)

		AF._Deps({ MeshLibrary = false })
		AF.SetQuality("High")
		KC.flushErrors("client_evo_twists")
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_budget
	------------------------------------------------------------------------------------------------
	S.client_evo_budget = guarded("client_evo_budget", function()
		local R = rig("SmokeEvoBudget", 9700)
		local Fx = R.Fx
		local units = {}
		for i = 1, 8 do
			units[i] = unitModel(R.holder, "U" .. i, Vector3.new(i * 4, 2, 0))
		end
		local function over(stats, tag)
			T.check(stats.Live <= Fx.MAX_LIVE and stats.Stepped <= Fx.MAX_STEPPED, tag .. ": Live <= MAX_LIVE and Stepped <= MAX_STEPPED", fmt("%d / %d", stats.Live, stats.Stepped))
		end
		-- 8 raiders' Thunder Packs + 8 Twists in one second, 7 of the 8 someone else's
		local twists = { "Aftershock", "LastStrike", "Shatter", "Burst", "Chill", "Twin", "Overflow", "Lingering" }
		local kinds = { "Blast", "Storm", "Freeze", "Shield", "Freeze", "Beam", "Heal", "Heal" }
		local played, refused = 0, 0
		for i = 1, 8 do
			R.clock = R.clock + 1 / 16
			local mine = i == 1
			local ok = Fx.Play(R.ctx({ Attack = "Special", Kind = "Pounce", Element = "Storm", PetId = "stormfang", Rarity = "Secret", Stage = 2, Form = 2, Mine = mine,
				From = { Unit = 100 + i, Model = units[i] }, To = { Unit = 2, Model = R.B }, Line = packLine(), Now = R.clock }))
			played, refused = played + (ok and 1 or 0), refused + (ok and 0 or 1)
			ok = Fx.Play(R.ctx({ Attack = "Special", Kind = kinds[i], Element = "Flame", Twist = twists[i], Rarity = "Rare", Stage = 2, Mine = mine,
				From = { Unit = 100 + i, Pos = Vector3.new(i * 4, 2, -6) }, To = { Unit = 2, Model = R.B }, Radius = 6, Now = R.clock }))
			played, refused = played + (ok and 1 or 0), refused + (ok and 0 or 1)
			Fx.Update(R.clock)
		end
		T.check(played >= 10, "evo budget: the first plays go through", fmt("%d played, %d refused", played, refused))
		over(Fx.Stats(), "evo budget: 8 Thunder Packs + 8 Twists")
		local perEffect = T.tally("evo budget: per effect: Cores <= 14, Beams <= 4, Emitters <= 6, Trails <= 4, Lights <= 3")
		for _, e in ipairs(Fx._Live()) do
			perEffect:case(e.Cores <= Fx.MAX_CORES and e.Beams <= Fx.MAX_BEAMS and e.Emitters <= 6 and e.Trails <= Fx.MAX_TRAILS and e.Lights <= Fx.MAX_LIGHTS,
				fmt("%s: %d %d %d %d %d", tostring(e.Kind), e.Cores, e.Beams, e.Emitters, e.Trails, e.Lights))
		end
		perEffect:report()
		T.check(Fx.Stats().Errors == R.errs0, "evo budget: no Play error", tostring(Fx.Stats().Errors))
		R.run(3)
		T.check(Fx.Stats().Live == 0 and Fx.Stats().Stepped == 0, "evo budget: all played out")
		Fx.ClearAll()
		-- a Rally aura on 4 fighters + 10 plays: the auras hold no budget slot
		for i = 1, 4 do
			Fx.Play(R.ctx({ Attack = "Special", Kind = "Rally", Element = "Flame", Rarity = "Rare", Stage = 2, Form = 2, Seconds = 8, Scale = 1.28,
				From = { Unit = 200 + i, Model = units[i] }, To = { Unit = 200 + i, Model = units[i] }, Mine = i == 1, Now = R.clock }))
		end
		R.run(2.5) -- (past their beats: four tails)
		T.check(Fx.Stats().Tails == 4 and Fx.Stats().Live == 0, "evo budget: four auras are four tails, no Live slot", fmt("%d / %d", Fx.Stats().Tails, Fx.Stats().Live))
		local on = 0
		for i = 1, 10 do
			if Fx.Play(R.ctx({ Attack = "Melee", From = { Unit = 300 + i, Model = units[(i % 8) + 1] }, Now = R.clock })) then
				on = on + 1
			end
		end
		T.check(on == 10, "evo budget: ...10 plays all go through at full rarity", tostring(on))
		over(Fx.Stats(), "evo budget: auras + 10 plays")
		T.check(Fx.Stats().Stepped == 0, "evo budget: ...none stepped down", tostring(Fx.Stats().Stepped))
		-- MAX_TAILS never finishes an aura: 12 tails on top
		local before = 0
		for _, e in ipairs(Fx._Live()) do
			if e.AuraRel then
				before = before + 1
			end
		end
		for i = 1, 16 do
			Fx.Play(R.ctx({ Attack = "Melee", Now = R.clock, From = { Unit = 400 + i, Model = units[(i % 8) + 1] } }))
			R.run(0.1)
		end
		R.run(0.6)
		local afterN = 0
		for _, e in ipairs(Fx._Live()) do
			if e.AuraRel then
				afterN = afterN + 1
			end
		end
		T.check(before == 4 and afterN == 4, "evo budget: a storm of tails does not push an aura out", fmt("%d -> %d", before, afterN))
		T.check(Fx.Stats().Errors == R.errs0, "evo budget: no engine error")
		R.finish()
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_looks_mobile
	------------------------------------------------------------------------------------------------
	S.client_evo_looks_mobile = guarded("client_evo_looks_mobile", function()
		local R = rig("SmokeEvoLooksPhone", 9900)
		local Fx = R.Fx
		Mock.SetViewport(844, 390)
		Fx.SetQuality("Low")
		local eff = R.play({ Attack = "Special", Kind = "Pounce", Element = "Storm", PetId = "stormfang", Rarity = "Secret", Stage = 2, Form = 2, Line = packLine() })
		if T.check(eff ~= nil, "evo phone: a Thunder Pack plays at 844x390 on Low") then
			local wolves, rims = actorsOf(eff)
			T.check(#wolves == 5 and #rims == 0, "evo phone: wolves plain: no rim", fmt("%d / %d", #wolves, #rims))
			local s = Fx.Stats()
			T.check(s.Rims == 0 and s.Beams == 0 and s.Trails == 0 and s.Emitters <= 2, "evo phone: no rim light, no bolts, no trails, 2 emitters", fmt("%d %d %d %d", s.Rims, s.Beams, s.Trails, s.Emitters))
			R.run(1.2)
		end
		R.finish()
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
