-- smoke_eggs.lua: the lobby-shop egg rolls (docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.1; plan
-- docs/superpowers/plans/2026-11-07-lobby-shop.md Tasks 1 / 4 / 6). Loaded by tools/smoke.py; ARGS.context picks the
-- half (like smoke_storm.lua; only the server half has scenarios so far):
--   egg_roll_pure   (server, pure) eggs are rarities (Config.Eggs: the seven names in Config.Rarities order); one odds
--                   source for every roulette, the Secret Roulette included: PetCatalog.RollRarity / RollFromRarity /
--                   RarityPool keep RollPet's exact draws (10,000 seeds per roulette: RollPet == RollFromRarity(RollRarity)
--                   == an inline copy of the old algorithm), the rarity shares hold, the pools never hold an EventOnly or
--                   ExclusiveTo pet; GemService.RollPet's ForceRarity (always that rarity, the rng left where an unforced
--                   roll leaves it); PetCatalog and GemService answer the Secret Roulette with one table (Mythic 85 / Secret
--                   15); Util.NewRng() without a seed calls Random.new() with no argument
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, fmt = math.abs, string.format
local SECRET = "Secret"
local SEEDS = 10000
local SHARE_TOLERANCE = 0.015 -- 1.5 points over 10,000 rolls (about 3 sigma at a 60% share)

local function serverScenarios()
	local K = _G.K
	local S = {}

	local function req(path)
		local inst = K.moduleInstance(path)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	local function sortedRarities(Config)
		local list = {}
		for _, r in ipairs(Config.Rarities) do
			list[#list + 1] = r
		end
		table.sort(list, function(a, b)
			return a.Order < b.Order
		end)
		return list
	end

	-- every roulette the shop sells: the token roulettes, then the gems-only Secret Roulette
	local function rouletteSources(Config)
		local out = {}
		for _, r in ipairs(Config.Roulettes) do
			out[#out + 1] = r
		end
		out[#out + 1] = Config.Gems.SecretRoulette
		return out
	end

	-- the old algorithm, copied inline (PetCatalog.RollPet before lobby-shop, and GemService's gems-only copy): the rows
	-- in rarity order (weight > 0, a non-empty pool, Secret only with AllowSecret), one Float over the rows, one Int over
	-- the picked pool
	local function oldRows(Config, PC, src)
		local rows, total = {}, 0
		for _, r in ipairs(sortedRarities(Config)) do
			local w = src.Odds[r.Id]
			local pool = PC.ListByRarity(r.Id)
			if type(w) == "number" and w > 0 and #pool > 0 and (r.Id ~= SECRET or src.AllowSecret == true) then
				rows[#rows + 1] = { Rarity = r.Id, Weight = w, Pets = pool }
				total = total + w
			end
		end
		return rows, total
	end

	local function oldRoll(rows, total, rng)
		local x = rng:Float(0, total)
		local picked = rows[#rows]
		local acc = 0
		for _, e in ipairs(rows) do
			acc = acc + e.Weight
			if x < acc then
				picked = e
				break
			end
		end
		local idx = rng:Int(1, #picked.Pets)
		if idx < 1 then
			idx = 1
		elseif idx > #picked.Pets then
			idx = #picked.Pets
		end
		return picked.Pets[idx].Id
	end

	local function idsOf(list)
		local out = {}
		for i, def in ipairs(list or {}) do
			out[i] = type(def) == "table" and def.Id or tostring(def)
		end
		return table.concat(out, ",")
	end

	S.egg_roll_pure = guarded("egg_roll_pure", function()
		local Config = K.config()
		local PC = K.M["shared/PetCatalog"] or req("shared/PetCatalog")
		local GS = req("server/Services/GemService")
		local Util = req("shared/Util")
		if not T.check(type(PC) == "table" and type(GS) == "table" and type(Util) == "table", "eggs: PetCatalog, GemService and Util load") then
			return
		end
		local sources = rouletteSources(Config)

		-- Config.Eggs: one egg per rarity, in rarity order
		local Eggs = Config.Eggs
		if T.check(type(Eggs) == "table" and type(Eggs.Order) == "table" and type(Eggs.Names) == "table", "eggs: Config.Eggs has Order and Names") then
			local want = {}
			for i, r in ipairs(sortedRarities(Config)) do
				want[i] = r.Id
			end
			T.eq(table.concat(Eggs.Order, ","), table.concat(want, ","), "eggs: Config.Eggs.Order is the Config.Rarities ids sorted by Order")
			local names = T.tally("eggs: every rarity has an egg name (a non-empty string)")
			for _, r in ipairs(want) do
				names:case(type(Eggs.Names[r]) == "string" and Eggs.Names[r] ~= "", r .. " = " .. tostring(Eggs.Names[r]))
			end
			names:report()
			local spec = { Common = "Cloud Puff Egg", Uncommon = "Breeze Egg", Rare = "Raindrop Egg", Epic = "Thunder Egg", Legendary = "Sunburst Egg", Mythic = "Aurora Egg", Secret = "Starry Night Egg" }
			local named = T.tally("eggs: the egg names are the spec's (Cloud Puff .. Starry Night)")
			for r, name in pairs(spec) do
				named:case(Eggs.Names[r] == name, r .. " = " .. tostring(Eggs.Names[r]))
			end
			named:report()
		end

		-- Util.NewRng without a seed: Random.new() with no argument (engine seeded)
		local origNew = Random.new
		local argc = nil
		Random.new = function(...)
			argc = select("#", ...)
			return origNew(...)
		end
		local okRng, rng0 = pcall(Util.NewRng)
		Random.new = origNew
		T.check(okRng and argc == 0, "eggs: Util.NewRng() calls Random.new() with no argument (engine seeded)", "argument count " .. tostring(argc))
		local die = okRng and type(rng0) == "table" and rng0:Int(1, 6)
		T.check(type(die) == "number" and die >= 1 and die <= 6, "eggs: Util.NewRng():Int(1, 6) is in 1..6", tostring(die))

		-- every roulette (Secret included) has odds rows, and PetCatalog / GemService read one table
		local rowsOk = T.tally("eggs: every roulette (the Secret Roulette included) has at least one odds row in PetCatalog")
		for _, src in ipairs(sources) do
			rowsOk:case(#PC.GetRarityOdds(src.Id) >= 1 and #PC.GetOdds(src.Id) >= 1 and #PC.PossiblePets(src.Id) >= 1, src.Id)
		end
		rowsOk:report()
		local pr, gr = PC.GetRarityOdds(SECRET), GS.GetRarityOdds(SECRET)
		local same = #pr == #gr and #pr == 2
		for i = 1, math.max(#pr, #gr) do
			local a, b = pr[i], gr[i]
			if not (a and b and a.Rarity == b.Rarity and abs(a.Chance - b.Chance) < 1e-12 and a.Count == b.Count) then
				same = false
			end
		end
		T.check(same, "eggs: PetCatalog.GetRarityOdds(\"Secret\") equals GemService.GetRarityOdds(\"Secret\") row for row (Rarity, Chance, Count)", fmt("%d / %d rows", #pr, #gr))
		T.check(#pr == 2 and pr[1].Rarity == "Mythic" and abs(pr[1].Chance - 0.85) < 1e-12 and pr[2].Rarity == SECRET and abs(pr[2].Chance - 0.15) < 1e-12,
			"eggs: the Secret Roulette's odds are Mythic 85% / Secret 15%", pr[1] and fmt("%s %.4f", tostring(pr[1].Rarity), pr[1].Chance) or "no rows")
		T.eq(idsOf(PC.PossiblePets(SECRET)), idsOf(GS.PossiblePets(SECRET)), "eggs: PossiblePets(\"Secret\") lists the same pets in PetCatalog and GemService")
		local po, go = PC.GetOdds(SECRET), GS.GetOdds(SECRET)
		local sameOdds = #po == #go and #po > 0
		for i = 1, math.min(#po, #go) do
			if po[i].PetId ~= go[i].PetId or abs(po[i].Chance - go[i].Chance) > 1e-12 then
				sameOdds = false
			end
		end
		T.check(sameOdds, "eggs: GetOdds(\"Secret\") is the same per-pet table in PetCatalog and GemService", fmt("%d / %d", #po, #go))

		local helpers = type(PC.RollRarity) == "function" and type(PC.RollFromRarity) == "function" and type(PC.RarityPool) == "function"
		if not T.check(helpers, "eggs: PetCatalog has RollRarity, RollFromRarity and RarityPool") then
			K.flushErrors("egg_roll_pure")
			return
		end

		-- the pools: RarityPool is ListByRarity per row, never an EventOnly or ExclusiveTo pet; not a row -> {}
		local pools = T.tally("eggs: RarityPool(id, r) ids equal PetCatalog.ListByRarity(r) ids for every odds row")
		for _, src in ipairs(sources) do
			for _, row in ipairs(PC.GetRarityOdds(src.Id)) do
				pools:case(idsOf(PC.RarityPool(src.Id, row.Rarity)) == idsOf(PC.ListByRarity(row.Rarity)), src.Id .. "/" .. row.Rarity)
			end
		end
		pools:report()
		local cloudMythic = PC.RarityPool("Cloud", "Mythic")
		T.check(type(cloudMythic) == "table" and #cloudMythic == 0, "eggs: RarityPool(\"Cloud\", \"Mythic\") is {} (not one of Cloud's rows)")
		T.check(PC.RollFromRarity("Cloud", "Mythic", Util.NewRng(3)) == nil and PC.RollFromRarity("Cloud", nil, Util.NewRng(3)) == nil and PC.RollFromRarity("NoSuch", "Common", Util.NewRng(3)) == nil,
			"eggs: RollFromRarity answers nil for a rarity that is not a row of that roulette (and for junk)")
		T.check(PC.RollRarity("NoSuch", Util.NewRng(3)) == nil and #PC.RarityPool("NoSuch", "Common") == 0, "eggs: an unknown roulette has no rarity and no pool")
		local pool1 = PC.RarityPool("Celestial", "Mythic")
		local size = #pool1
		pool1[#pool1 + 1] = { Id = "intruder" }
		T.eq(#PC.RarityPool("Celestial", "Mythic"), size, "eggs: RarityPool hands out a copy (a caller cannot grow the pool)")
		local drawn = T.tally("eggs: RollFromRarity gives only pets of that rarity, never EventOnly or ExclusiveTo (300 draws per row)")
		local rngD = Util.NewRng(77)
		for _, src in ipairs(sources) do
			for _, row in ipairs(PC.GetRarityOdds(src.Id)) do
				local bad = nil
				for _ = 1, 300 do
					local id = PC.RollFromRarity(src.Id, row.Rarity, rngD)
					local def = id and PC.Get(id)
					if not def or def.Rarity ~= row.Rarity or def.EventOnly == true or def.ExclusiveTo ~= nil then
						bad = tostring(id)
					end
				end
				drawn:case(bad == nil, src.Id .. "/" .. row.Rarity .. ": " .. tostring(bad))
			end
		end
		drawn:report()
		T.check(PC.RollRarity("Cloud") ~= nil and PC.RollFromRarity("Cloud", "Common") ~= nil, "eggs: RollRarity / RollFromRarity work without an rng (math.random)")

		-- the draws: RollPet == RollFromRarity(RollRarity) == the old algorithm, seed for seed; the shares hold
		for _, src in ipairs(sources) do
			local rows, total = oldRows(Config, PC, src)
			local identical = T.tally(fmt("eggs: %s: %d seeds, RollPet == RollFromRarity(RollRarity) == the old algorithm (today's results unchanged)", src.Id, SEEDS))
			local counts = {}
			for s = 1, SEEDS do
				local a, b, c = Util.NewRng(s), Util.NewRng(s), Util.NewRng(s)
				local viaPet = PC.RollPet(src.Id, a)
				local viaRarity = PC.RollFromRarity(src.Id, PC.RollRarity(src.Id, b), b)
				local old = (#rows > 0) and oldRoll(rows, total, c) or nil
				if identical:case(viaPet ~= nil and viaPet == viaRarity and viaPet == old, fmt("seed %d: %s / %s / %s", s, tostring(viaPet), tostring(viaRarity), tostring(old))) then
					local r = PC.Get(viaPet).Rarity
					counts[r] = (counts[r] or 0) + 1
				end
			end
			identical:report()
			local shares = T.tally(fmt("eggs: %s: each rarity's share over %d rolls is within %.1f points of its odds", src.Id, SEEDS, SHARE_TOLERANCE * 100))
			for _, row in ipairs(rows) do
				local got = (counts[row.Rarity] or 0) / SEEDS
				local want = row.Weight / total
				shares:case(abs(got - want) <= SHARE_TOLERANCE, fmt("%s %.4f vs %.4f", row.Rarity, got, want))
			end
			shares:report()
		end

		-- ForceRarity (the pity's pull): always that rarity; the rng ends where an unforced roll leaves it
		local forced = T.tally("eggs: GemService.RollPet(\"Secret\", rng, { ForceRarity = \"Secret\" }) is always a Secret pet, never EventOnly (seeds 1..200)")
		for s = 1, 200 do
			local id = GS.RollPet(SECRET, Util.NewRng(s), { ForceRarity = SECRET })
			local def = id and PC.Get(id)
			forced:case(def ~= nil and def.Rarity == SECRET and def.EventOnly ~= true and def.ExclusiveTo == nil, fmt("seed %d: %s", s, tostring(id)))
		end
		forced:report()
		local a, b = Util.NewRng(9), Util.NewRng(9)
		local fid = GS.RollPet(SECRET, a, { ForceRarity = SECRET })
		GS.RollPet(SECRET, b)
		local fa, fb = a:Float(0, 1), b:Float(0, 1)
		T.check(fid ~= nil and PC.Get(fid).Rarity == SECRET and fa == fb, "eggs: a forced roll draws the same Float + Int as an unforced one (the next draw matches)", fmt("%s %.6f %.6f", tostring(fid), fa, fb))
		local m = GS.RollPet("Celestial", Util.NewRng(4), { ForceRarity = "Mythic" })
		T.check(m ~= nil and PC.Get(m).Rarity == "Mythic", "eggs: ForceRarity works on a token roulette's own row (Celestial, Mythic)", tostring(m))
		T.check(GS.RollPet("Cloud", Util.NewRng(4), { ForceRarity = "Mythic" }) == nil, "eggs: ForceRarity of a rarity the roulette does not have gives nothing (Cloud, Mythic)")
		T.check(GS.RollPet(SECRET, Util.NewRng(5)) == PC.RollPet(SECRET, Util.NewRng(5)), "eggs: GemService.RollPet(\"Secret\") is PetCatalog's roll (one source)")
		K.flushErrors("egg_roll_pure")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return {}
