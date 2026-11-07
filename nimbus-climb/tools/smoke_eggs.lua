-- smoke_eggs.lua: the lobby-shop egg rolls (docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.1; plan
-- docs/superpowers/plans/2026-11-07-lobby-shop.md Tasks 1 / 4 / 6). Loaded by tools/smoke.py; ARGS.context picks the
-- half (like smoke_storm.lua):
--   egg_roll_pure   (server, pure) eggs are rarities (Config.Eggs: the seven names in Config.Rarities order); one odds
--                   source for every roulette, the Secret Roulette included: PetCatalog.RollRarity / RollFromRarity /
--                   RarityPool keep RollPet's exact draws (10,000 seeds per roulette: RollPet == RollFromRarity(RollRarity)
--                   == an inline copy of the old algorithm), the rarity shares hold, the pools never hold an EventOnly or
--                   ExclusiveTo pet; GemService.RollPet's ForceRarity (always that rarity, the rng left where an unforced
--                   roll leaves it); PetCatalog and GemService answer the Secret Roulette with one table (Mythic 85 / Secret
--                   15); Util.NewRng() without a seed calls Random.new() with no argument
--   egg_spin_x1     (server, booted; Task 4) the reply of one spin (Pulls[1] with every field, the mirrored top level,
--                   PoolSize, the 40-cell strip with the winner at 34), one charge, Stats.Spins + 1, one Rolled; the
--                   AllowSecret guard (a Secret pet out of a token roulette refuses the whole request, an x3 too, before
--                   the charge)
--   egg_spin_x3     (server, booted; Task 4) x3 = one charge of 3 x the price (tokens and gems), three pulls, Stats.Spins
--                   + 3, three Rolled, one Sync; not enough Gems refused with nothing written; 2,000 seeded x3 requests:
--                   the three pulls are independent (identical triples rare, each position at the odds); junk spins
--                   dropped by the remote and answered "Bad spins" by BuyRoulette; junk currencies; the PolicyService
--                   lock; the 0.25 s cooldown counts one request; a fault after the charge keeps the grant, a fault in
--                   the plan step charges nothing
--   egg_full_stack  (server, booted; Task 4) a full stack never refuses after the roll and is never a free reroll: every
--                   Common at 99 -> each Common pull pays the Common Index Tokens (Substitute), every spin is charged and
--                   the Common share holds; one Common at 99 -> that pet is re-picked away, never granted; the Secret
--                   Roulette with both Mythics at 99 -> Mythic pulls pay the Mythic Index Tokens and the natural Secret
--                   share stays at 15%; Task 5: the pity forces pulls (each a Secret), GetPity's Spins grows by every
--                   spin (substitutes included), every reply carries SecretPity.Left, and the share over all pulls is
--                   near 15% / (1 - 0.85^7) = 22.1% (the pity working)
--   egg_strip       (server, booted; Task 4) the strips come from their own generator (a fixed roll generator leaves them
--                   free), the three strips of an x3 differ, every filler is a pet that roulette can roll
--   egg_announce    (server, booted; Task 6) one chat line per request, Legendary and up (spec 5.5): an Epic pull is not
--                   announced; a Legendary sends Notify kind "pull" "<DisplayName> hatched a Legendary <pet>!" to the
--                   others at once and to the puller after 5 s; an x3 names its best pull (the first on ties) with
--                   " (+N more)"; at most one line per player every 10 s: requests inside the gap are held and go out as
--                   one line when it ends (the best held pull named, (+N more) counting every other held one); five x3
--                   Legendary requests in 10 s reach a witness as at most 2 lines; a held line of a player who left is
--                   dropped
--   egg_spin_x1 also checks (Task 6) that an Epic pull sends no "pull" Notify and a Legendary sends one
--   client_notify_pull (client; Task 6) Notify kind "pull" -> a system chat line in TextChatService's RBXSystem channel
--                   (the rarity word in its Config.Rarities colour, rich text escaped), no toast; without the channel ->
--                   today's toast with the text
-- The booted bulk runs (thousands of requests) check every reply here with K.V.rouletteResult and keep their
-- RouletteResult / ProfileSync / announcement traffic out of the shared logs (memory; see bulkSpins).
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

	------------------------------------------------------------------------------------------------------------------
	-- booted helpers (Task 4: the money step)
	------------------------------------------------------------------------------------------------------------------
	local B = {}
	local JAMMED = "The roulette jammed, try again"
	local LOADING = "Your data is still loading"
	local ALLOWED_WARNINGS = { "[DataService]", "[GemService]", "[PetService] after a spin", "[PetService] spin plan failed" }
	local PolS = game:GetService("PolicyService")
	local policyModes = {} -- [userId] = "allow" | "restrict"
	local joinSeq = 0

	-- the PolicyService double (the smoke_p2_gems.lua shape): installed before the joins, removed after the scenario
	function B.installPolicy()
		PolS.GetPolicyInfoForPlayerAsync = function(_, player)
			return { ArePaidRandomItemsRestricted = policyModes[player.UserId] == "restrict", IsPaidItemTradingAllowed = true }
		end
	end

	function B.removePolicy()
		PolS.GetPolicyInfoForPlayerAsync = nil
	end

	function B.join(prefix, mode)
		joinSeq = joinSeq + 1
		local uid = 988600 + joinSeq
		policyModes[uid] = mode or "allow"
		local p = Mock.AddPlayer(prefix .. joinSeq, uid)
		K.advance(1.0)
		return p
	end

	function B.leave(list)
		for _, p in ipairs(list) do
			if p and p.Parent then
				Mock.RemovePlayer(p)
			end
		end
		K.advance(0.8)
	end

	function B.mods()
		return K.config(), K.mod("PetService"), K.mod("DataService"), K.M["shared/PetCatalog"] or req("shared/PetCatalog")
	end

	function B.roulette(id)
		for _, r in ipairs(K.config().Roulettes) do
			if r.Id == id then
				return r
			end
		end
		return nil
	end

	-- sets the balances exactly (nil leaves one alone)
	function B.give(p, tokens, gems)
		local D = K.mod("DataService")
		if tokens then
			local cur = D.GetTokens(p)
			if tokens > cur then
				D.AddTokens(p, tokens - cur)
			elseif tokens < cur then
				D.SpendTokens(p, cur - tokens)
			end
		end
		if gems then
			local cur = D.GetGems(p)
			if gems > cur then
				D.AddGems(p, gems - cur)
			elseif gems < cur then
				D.SpendGems(p, cur - gems)
			end
		end
	end

	function B.wallet(p)
		local D = K.mod("DataService")
		local prof = D.GetProfile(p)
		local pets = 0
		for _, n in pairs(prof and prof.Pets or {}) do
			pets = pets + n
		end
		return { Tokens = D.GetTokens(p), Gems = D.GetGems(p), Pets = pets, Spins = prof and prof.Stats.Spins or -1 }
	end

	function B.same(a, b)
		return a.Tokens == b.Tokens and a.Gems == b.Gems and a.Pets == b.Pets and a.Spins == b.Spins
	end

	function B.show(w)
		return fmt("tokens %s, gems %s, pets %s, spins %s", tostring(w.Tokens), tostring(w.Gems), tostring(w.Pets), tostring(w.Spins))
	end

	function B.fire(p, id, currency, spins)
		local folder = K.remoteFolder()
		Mock.FromClient(folder:FindFirstChild("BuyRoulette"), p, id, currency, spins)
	end

	-- the RouletteResult payloads sent to p after log index `mark`
	function B.results(p, mark)
		local out = {}
		for _, e in ipairs(K.remotesFor("RouletteResult", p.UserId, mark)) do
			out[#out + 1] = e.args[1]
		end
		return out
	end

	-- counts PetService.Rolled fires for p until stop()
	function B.countRolled(PS, p)
		local box = { n = 0, ids = {} }
		local conn = PS.Rolled:Connect(function(who, petId)
			if who == p then
				box.n = box.n + 1
				box.ids[#box.ids + 1] = petId
			end
		end)
		box.stop = function()
			conn:Disconnect()
		end
		return box
	end

	-- drops p's RouletteResult / ProfileSync / Notify entries (and every announcement naming p) logged after `mark`
	function B.dropTraffic(p, mark)
		local log = Mock.RemoteLog
		local name = p.DisplayName
		local keep = mark
		for i = mark + 1, #log do
			local e = log[i]
			local mine = e.userId == p.UserId and (e.remote == "RouletteResult" or e.remote == "ProfileSync" or e.remote == "Notify")
			local text = e.remote == "Notify" and type(e.args) == "table" and e.args[1] or nil
			local about = type(text) == "string" and string.find(text, name, 1, true) == 1
			if not (mine or about) then
				keep = keep + 1
				log[keep] = e
			end
		end
		for i = #log, keep + 1, -1 do
			log[i] = nil
		end
	end

	-- Bulk spins: fn(flush) runs with the replication recorder off (no client replay of thousands of spins) and p's
	-- spin traffic is dropped from Mock.RemoteLog at every flush() and at the end (each reply is checked by the caller).
	-- The announcements are let out before the recorder comes back: a bulk run takes no time, so its first request sends
	-- a line and every later one is held until the 10 s gap ends (Task 6), and the puller's copy follows 5 s later:
	-- 10 + 5 + 1 = 16 s.
	function B.bulkSpins(p, fn)
		local mark = #Mock.RemoteLog
		local recorder = Mock._onRemote
		Mock._onRemote = nil
		local ok, err = pcall(fn, function()
			B.dropTraffic(p, mark)
		end)
		K.advance(16)
		Mock._onRemote = recorder
		B.dropTraffic(p, mark)
		if not ok then
			error(err, 0)
		end
	end

	-- every owned count of p above `cap` back to `cap` except the pets in `keep` (bulk runs stay below the stack cap)
	function B.trimStacks(prof, cap, keep)
		for id, n in pairs(prof.Pets) do
			if not (keep and keep[id]) and n > cap then
				prof.Pets[id] = cap
			end
		end
	end

	-- a pull carries every field of spec 5.1's reply
	function B.pullProblems(PC, rouletteId, pull)
		local out = {}
		local def = type(pull) == "table" and type(pull.PetId) == "string" and PC.Get(pull.PetId) or nil
		if not def then
			return { "PetId " .. tostring(type(pull) == "table" and pull.PetId) }
		end
		if pull.Key ~= pull.PetId then
			out[#out + 1] = "Key " .. tostring(pull.Key)
		end
		if pull.Rarity ~= def.Rarity then
			out[#out + 1] = "Rarity " .. tostring(pull.Rarity) .. " (the pet is " .. tostring(def.Rarity) .. ")"
		end
		if type(pull.IsNew) ~= "boolean" or type(pull.NewDiscovery) ~= "boolean" then
			out[#out + 1] = "IsNew / NewDiscovery"
		end
		if type(pull.Count) ~= "number" or pull.Count < 1 then
			out[#out + 1] = "Count " .. tostring(pull.Count)
		end
		if pull.PoolSize ~= #PC.RarityPool(rouletteId, def.Rarity) then
			out[#out + 1] = "PoolSize " .. tostring(pull.PoolSize)
		end
		if type(pull.Strip) ~= "table" or #pull.Strip ~= 40 or pull.Strip[34] ~= pull.PetId then
			out[#out + 1] = "Strip (40 ids, the winner at 34)"
		end
		if pull.Pity ~= nil and pull.Pity ~= true then
			out[#out + 1] = "Pity " .. tostring(pull.Pity)
		end
		if pull.Substitute ~= nil and (type(pull.Substitute) ~= "table" or type(pull.Substitute.Tokens) ~= "number") then
			out[#out + 1] = "Substitute"
		end
		return out
	end

	-- Task 6: a roll generator that lands each Float draw on the given fraction of its range (in order; the last one
	-- repeats) and each Int draw on the given index (clamped; 1 when none is given). Steers PetService's RNG.Roll.
	function B.steer(fracs, ints)
		local fi, ii = 0, 0
		local rng = {}
		function rng:Float(a, b)
			fi = fi + 1
			return a + (b - a) * fracs[math.min(fi, #fracs)]
		end
		function rng:Int(a, b)
			ii = ii + 1
			local v = (ints and ints[math.min(ii, #ints)]) or a
			return math.max(a, math.min(b, v))
		end
		return rng
	end

	-- the middle of `rarity`'s band in a roulette's one Float draw, as a fraction of the range (PetCatalog.GetRarityOdds
	-- rows are RollRarity's rows in the same order)
	function B.band(PC, id, rarity)
		local acc = 0
		for _, row in ipairs(PC.GetRarityOdds(id)) do
			if row.Rarity == rarity then
				return acc + row.Chance / 2
			end
			acc = acc + row.Chance
		end
		error("no " .. tostring(rarity) .. " row in roulette " .. tostring(id), 0)
	end

	-- the texts of the Notify kind "pull" lines sent to `who` after log index `mark`, in order (and their durations)
	function B.pullLines(who, mark)
		local out, durations = {}, {}
		for _, e in ipairs(K.remotesFor("Notify", who.UserId, mark)) do
			if e.args[2] == "pull" then
				out[#out + 1] = tostring(e.args[1])
				durations[#durations + 1] = e.args[3]
			end
		end
		return out, durations
	end

	-- every Notify after `mark` (to anyone) that is an announcement: kind "pull", or the new or the old wording
	function B.announcements(mark)
		local n = 0
		for _, e in ipairs(K.remotesFor("Notify", nil, mark)) do
			local text = tostring(e.args[1])
			if e.args[2] == "pull" or string.find(text, " hatched a ", 1, true) or string.find(text, " pulled ", 1, true) then
				n = n + 1
			end
		end
		return n
	end

	local function sameList(a, b)
		if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
			return false
		end
		for i = 1, #a do
			if a[i] ~= b[i] then
				return false
			end
		end
		return true
	end

	------------------------------------------------------------------------------------------------------------------
	-- egg_spin_x1
	------------------------------------------------------------------------------------------------------------------
	S.egg_spin_x1 = guarded("egg_spin_x1", function()
		if not K.needBoot() then
			return
		end
		local Config, PS, D, PC = B.mods()
		local Util = req("shared/Util")
		local players = {}
		local origRoll = PC.RollPet
		local okRun, errRun = pcall(function()
			B.installPolicy()
			local p = B.join("EggOne")
			players[1] = p
			local prof = D.GetProfile(p)
			local cloud = Config.Roulettes[1]
			B.give(p, 1000, 0)
			local before = B.wallet(p)
			local rolled = B.countRolled(PS, p)
			local mark = K.logSize()
			local ok, res = PS.BuyRoulette(p, cloud.Id)
			K.advance(0.2)
			rolled.stop()
			local after = B.wallet(p)
			local reason = type(res) == "table" and tostring(res.Reason) or tostring(res)
			if T.check(ok == true and type(res) == "table" and res.Ok == true and type(res.Pulls) == "table", "egg x1: a Cloud spin with tokens answers Ok with a Pulls list", reason) then
				T.check(res.Spins == 1 and res.RouletteId == cloud.Id and res.Currency == "Tokens", "egg x1: Spins 1, RouletteId, Currency 'Tokens'",
					fmt("%s / %s / %s", tostring(res.Spins), tostring(res.RouletteId), tostring(res.Currency)))
				T.check(res.UnitPrice == cloud.Price and res.Price == cloud.Price, "egg x1: UnitPrice == Price == the roulette's price (" .. cloud.Price .. ")",
					tostring(res.UnitPrice) .. " / " .. tostring(res.Price))
				T.eq(#res.Pulls, 1, "egg x1: one pull")
				local pull = res.Pulls[1] or {}
				local problems = B.pullProblems(PC, cloud.Id, pull)
				T.check(#problems == 0, "egg x1: the pull has every field (PetId, Key, Rarity, IsNew, NewDiscovery, Count, PoolSize, Strip)", table.concat(problems, ", "))
				T.check(type(pull.Strip) == "table" and #pull.Strip == 40 and pull.Strip[34] == pull.PetId, "egg x1: the strip lists 40 pets with the winner at 34")
				T.check(pull.PoolSize == #PC.RarityPool(cloud.Id, tostring(pull.Rarity)), "egg x1: PoolSize == #PetCatalog.RarityPool(roulette, rarity)", tostring(pull.PoolSize))
				T.check(pull.Pity == nil and pull.Substitute == nil and res.SecretPity == nil, "egg x1: no Pity, no Substitute, no SecretPity on a token roulette's normal pull")
				T.check(res.PetId == pull.PetId and res.Key == pull.Key and res.IsNew == pull.IsNew and res.NewDiscovery == pull.NewDiscovery and res.Count == pull.Count
					and sameList(res.Strip, pull.Strip), "egg x1: the top level mirrors pull 1 (PetId, Key, IsNew, NewDiscovery, Count, Strip)")
				T.check(res.IsNew == true and res.NewDiscovery == true and res.Count == 1, "egg x1: the first copy ever: IsNew, NewDiscovery, Count 1")
				T.check(res.Tokens == after.Tokens and res.Gems == after.Gems, "egg x1: the reply carries the balances after the charge", tostring(res.Tokens))
				local vp = K.V.rouletteResult(res)
				T.check(#vp == 0, "egg x1: the reply passes the RouletteResult payload check (smoke_server V.rouletteResult)", table.concat(vp, ", "))
			end
			T.check(after.Tokens == before.Tokens - cloud.Price and after.Spins == before.Spins + 1 and after.Pets == before.Pets + 1,
				"egg x1: one charge of " .. cloud.Price .. " tokens, Stats.Spins + 1, one pet", B.show(before) .. " -> " .. B.show(after))
			T.eq(rolled.n, 1, "egg x1: PetService.Rolled fired once")
			local sent = B.results(p, mark)
			T.check(#sent == 1 and type(sent[1]) == "table" and sent[1].Ok == true and type(res) == "table" and sent[1].PetId == res.PetId,
				"egg x1: one RouletteResult went to the buyer (the same reply)", #sent .. " sent")

			-- the AllowSecret guard: a Secret pet out of a token roulette refuses the whole request, before the charge
			local secretPet = PC.ListByRarity("Secret")[1].Id
			PC.RollPet = function()
				return secretPet
			end
			before = B.wallet(p)
			rolled = B.countRolled(PS, p)
			mark = K.logSize()
			local okS, whyS = PS.BuyRoulette(p, cloud.Id)
			PC.RollPet = origRoll
			K.advance(0.2)
			rolled.stop()
			T.check(okS == false and whyS == JAMMED, "egg x1: a Secret pet rolled by a token roulette refuses the request 'The roulette jammed, try again'", tostring(whyS))
			T.check(B.same(before, B.wallet(p)) and (prof.Pets[secretPet] or 0) == 0 and rolled.n == 0 and #B.results(p, mark) == 0,
				"egg x1: ...nothing charged, no pet, Stats.Spins unchanged, no Rolled", B.show(B.wallet(p)))
			local common = PC.RarityPool(cloud.Id, "Common")[1].Id
			local calls = 0
			PC.RollPet = function()
				calls = calls + 1
				return calls == 2 and secretPet or common
			end
			B.give(p, 1000, nil)
			before = B.wallet(p)
			rolled = B.countRolled(PS, p)
			local ok3, why3 = PS.BuyRoulette(p, cloud.Id, nil, 3)
			PC.RollPet = origRoll
			K.advance(0.2)
			rolled.stop()
			T.check(ok3 == false and why3 == JAMMED and B.same(before, B.wallet(p)) and rolled.n == 0,
				"egg x1: a Cloud x3 whose 2nd pull is a Secret pet is refused whole (nothing charged, no pet, no Rolled)", tostring(why3) .. "; " .. B.show(B.wallet(p)))
			T.eq(calls, 2, "egg x1: ...refused at the roll (no third pull, no strip drawn)")

			-- Task 6: only Legendary and up are announced (spec 9: an Epic pull sends no "pull" Notify, a Legendary does)
			local witness = B.join("EggOneWit")
			players[2] = witness
			local storm = B.roulette("Storm")
			B.give(p, 5 * storm.Price, nil)
			PS._SetRngForTest(B.steer({ B.band(PC, storm.Id, "Epic") }), nil)
			mark = K.logSize()
			local okE, resE = PS.BuyRoulette(p, storm.Id)
			K.advance(6)
			local pullE = okE == true and type(resE) == "table" and type(resE.Pulls) == "table" and resE.Pulls[1] or nil
			T.check(pullE ~= nil and pullE.Rarity == "Epic", "egg x1: the steered Storm spin is an Epic", tostring(pullE and pullE.Rarity))
			T.check(#B.pullLines(witness, mark) == 0 and #B.pullLines(p, mark) == 0 and B.announcements(mark) == 0,
				"egg x1: an Epic pull sends no 'pull' Notify (nor any announcement) to the witness or the puller in 6 s", B.announcements(mark) .. " announcements")
			PS._SetRngForTest(B.steer({ B.band(PC, storm.Id, "Legendary") }), nil)
			mark = K.logSize()
			local okL, resL = PS.BuyRoulette(p, storm.Id)
			K.advance(6)
			local pullL = okL == true and type(resL) == "table" and type(resL.Pulls) == "table" and resL.Pulls[1] or nil
			T.check(pullL ~= nil and pullL.Rarity == "Legendary", "egg x1: the steered Storm spin is a Legendary", tostring(pullL and pullL.Rarity))
			local wL, pL = B.pullLines(witness, mark), B.pullLines(p, mark)
			T.check(#wL == 1 and #pL == 1 and wL[1] == pL[1], "egg x1: a Legendary pull sends one 'pull' Notify to the witness and the same one to the puller",
				#wL .. " / " .. #pL .. ": " .. table.concat(wL, " | "))
		end)
		PC.RollPet = origRoll
		pcall(PS._SetRngForTest, Util.NewRng(), Util.NewRng())
		B.removePolicy()
		B.leave(players)
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("egg_spin_x1")
		K.flushWarnings("egg_spin_x1", ALLOWED_WARNINGS)
	end)

	------------------------------------------------------------------------------------------------------------------
	-- egg_spin_x3
	------------------------------------------------------------------------------------------------------------------
	S.egg_spin_x3 = guarded("egg_spin_x3", function()
		if not K.needBoot() then
			return
		end
		local Config, PS, D, PC = B.mods()
		local Util = req("shared/Util")
		local players = {}
		local origSync = D.Sync
		local okRun, errRun = pcall(function()
			if not T.check(type(PS._SetRngForTest) == "function" and type(PS._SetFaultForTest) == "function", "egg x3: PetService._SetRngForTest / _SetFaultForTest exist") then
				return
			end
			B.installPolicy()
			local p = B.join("EggThree")
			local locked = B.join("EggLocked", "restrict")
			players[1], players[2] = p, locked
			T.check(D._SettleForTest(p) == true and D._SettleForTest(locked) == true, "egg x3: (setup) the gem settle hold ends (DataService._SettleForTest)")
			local prof = D.GetProfile(p)
			local cloud, celestial = B.roulette("Cloud"), B.roulette("Celestial")
			-- setup: p owns a pet already (the first pet ever joins the team with its own SyncSoon)
			B.give(p, cloud.Price, 0)
			T.eq((PS.BuyRoulette(p, "Cloud")), true, "egg x3: (setup) a first Cloud spin")
			K.advance(1)

			-- Cloud x3 with tokens: one charge of 3 x 50, three pulls, three Rolled, one Sync
			B.give(p, 3 * cloud.Price, 0)
			local before = B.wallet(p)
			local syncs = 0
			D.Sync = function(who, ...)
				if who == p then
					syncs = syncs + 1
				end
				return origSync(who, ...)
			end
			local rolled = B.countRolled(PS, p)
			local mark = K.logSize()
			local ok, res = PS.BuyRoulette(p, "Cloud", nil, 3)
			D.Sync = origSync
			K.advance(0.2)
			rolled.stop()
			local after = B.wallet(p)
			if T.check(ok == true and type(res) == "table" and type(res.Pulls) == "table", "egg x3: a Cloud x3 with tokens answers Ok", tostring(type(res) == "table" and res.Reason or res)) then
				T.check(res.Spins == 3 and #res.Pulls == 3 and res.UnitPrice == cloud.Price and res.Price == 3 * cloud.Price, "egg x3: Spins 3, three pulls, Price = 3 x UnitPrice",
					fmt("%s pulls, %s x %s = %s", tostring(#res.Pulls), tostring(res.Spins), tostring(res.UnitPrice), tostring(res.Price)))
				local bad = {}
				for j, pull in ipairs(res.Pulls) do
					for _, why in ipairs(B.pullProblems(PC, "Cloud", pull)) do
						bad[#bad + 1] = j .. ": " .. why
					end
				end
				T.check(#bad == 0, "egg x3: every pull has every field", table.concat(bad, ", "))
				local vp = K.V.rouletteResult(res)
				T.check(#vp == 0, "egg x3: the reply passes V.rouletteResult (every pull and the mirrored top level)", table.concat(vp, ", "))
			end
			T.check(after.Tokens == before.Tokens - 3 * cloud.Price and after.Spins == before.Spins + 3 and after.Pets == before.Pets + 3,
				"egg x3: one charge of 3 x " .. cloud.Price .. ", Stats.Spins + 3, three pets", B.show(before) .. " -> " .. B.show(after))
			T.eq(rolled.n, 3, "egg x3: PetService.Rolled fired three times")
			T.eq(syncs, 1, "egg x3: DataService.Sync called once for the request")
			T.eq(#B.results(p, mark), 1, "egg x3: one RouletteResult for the request")

			-- Celestial x3 with tokens, Sky x3 with gems
			B.give(p, 3 * celestial.Price, nil)
			before = B.wallet(p)
			local okC = PS.BuyRoulette(p, "Celestial", "Tokens", 3)
			after = B.wallet(p)
			T.check(okC == true and after.Tokens == before.Tokens - 3 * celestial.Price and after.Spins == before.Spins + 3,
				"egg x3: Celestial x3 with tokens: one charge of 3 x " .. celestial.Price, B.show(before) .. " -> " .. B.show(after))
			local skyGems = Config.Gems.RouletteGemPrices.Sky
			B.give(p, 0, 3 * skyGems)
			before = B.wallet(p)
			local okG, resG = PS.BuyRoulette(p, "Sky", "Gems", 3)
			after = B.wallet(p)
			T.check(okG == true and after.Gems == before.Gems - 3 * skyGems and after.Tokens == before.Tokens and after.Spins == before.Spins + 3 and after.Pets == before.Pets + 3
				and type(resG) == "table" and resG.Currency == "Gems" and resG.Price == 3 * skyGems and resG.Gems == after.Gems,
				"egg x3: Sky x3 with gems: one charge of 3 x " .. skyGems .. " Gems (Currency Gems, Price, Gems balance)", tostring(type(resG) == "table" and resG.Reason or resG) .. "; " .. B.show(after))
			B.give(p, 0, 3 * skyGems - 1)
			before = B.wallet(p)
			local okPoor, whyPoor = PS.BuyRoulette(p, "Sky", "Gems", 3)
			T.check(okPoor == false and whyPoor == "Not enough Gems" and B.same(before, B.wallet(p)), "egg x3: Sky x3 with one gem less: 'Not enough Gems', nothing written", tostring(whyPoor))

			-- independence: 2,000 seeded x3 requests (direct calls: the remote cooldown does not stretch the run)
			PS._SetRngForTest(Util.NewRng(9101), Util.NewRng(9102))
			local REQUESTS, CHUNK = 2000, 200
			local identical, okCount, badReplies, badCharge = 0, 0, {}, 0
			local counts = { {}, {}, {} }
			B.bulkSpins(p, function(flush)
				for i = 1, REQUESTS do
					if i % CHUNK == 1 then
						B.trimStacks(prof, 1)
						B.give(p, CHUNK * 3 * cloud.Price, nil)
					end
					local okI, r = PS.BuyRoulette(p, "Cloud", nil, 3)
					if okI == true and type(r) == "table" and type(r.Pulls) == "table" and #r.Pulls == 3 then
						okCount = okCount + 1
						local a, b, c = r.Pulls[1].PetId, r.Pulls[2].PetId, r.Pulls[3].PetId
						if a == b and b == c then
							identical = identical + 1
						end
						for j = 1, 3 do
							local rar = r.Pulls[j].Rarity
							counts[j][rar] = (counts[j][rar] or 0) + 1
						end
						if #badReplies < 3 then
							local vp = K.V.rouletteResult(r)
							if #vp > 0 then
								badReplies[#badReplies + 1] = i .. ": " .. table.concat(vp, ", ")
							end
						end
					end
					if i % CHUNK == 0 then
						if D.GetTokens(p) ~= 0 then
							badCharge = badCharge + 1
						end
						flush()
					end
				end
			end)
			PS._SetRngForTest(Util.NewRng(), Util.NewRng())
			T.eq(okCount, REQUESTS, "egg x3 independence: all " .. REQUESTS .. " seeded x3 requests answered Ok with three pulls")
			T.eq(badCharge, 0, "egg x3 independence: ...each chunk of 200 requests spent exactly 200 x 150 tokens (one charge each)")
			T.check(#badReplies == 0, "egg x3 independence: ...every reply passes V.rouletteResult", table.concat(badReplies, " | "))
			T.check(identical / REQUESTS < 0.02, "egg x3 independence: requests with three identical pets stay under 2% (independent pulls: about 0.7%)", fmt("%d of %d", identical, REQUESTS))
			local tol = { Common = 0.035, Uncommon = 0.035, Rare = 0.02, Epic = 0.02 }
			local total = 0
			for _, w in pairs(cloud.Odds) do
				total = total + w
			end
			local shares = T.tally("egg x3 independence: each pull position's rarity share is within about 3 sigma of the Cloud odds (Common / Uncommon 3.5 points, Rare / Epic 2)")
			for j = 1, 3 do
				for rar, w in pairs(cloud.Odds) do
					local got = (counts[j][rar] or 0) / REQUESTS
					shares:case(abs(got - w / total) <= (tol[rar] or 0.02), fmt("position %d %s %.4f vs %.4f", j, rar, got, w / total))
				end
			end
			shares:report()

			-- junk spins: the remote drops them silently; BuyRoulette answers "Bad spins"
			B.give(p, 1000, 0)
			K.advance(0.4)
			before = B.wallet(p)
			mark = K.logSize()
			local junk = { { "Cloud", 2 }, { "Cloud", 3.5 }, { "Cloud", "3" }, { "Cloud", {} }, { "Cloud", 0 }, { "Secret", 3 } }
			for _, case in ipairs(junk) do
				B.fire(p, case[1], nil, case[2])
				K.advance(0.3)
			end
			T.check(#B.results(p, mark) == 0 and B.same(before, B.wallet(p)), "egg x3 remote: junk spins (2, 3.5, '3', {}, 0, and 3 on the Secret Roulette) get no RouletteResult and cost nothing",
				#B.results(p, mark) .. " answers; " .. B.show(B.wallet(p)))
			B.fire(p, "Cloud", nil, 3)
			K.advance(0.3)
			local sent = B.results(p, mark)
			T.check(#sent == 1 and type(sent[1]) == "table" and sent[1].Ok == true and sent[1].Spins == 3 and #sent[1].Pulls == 3, "egg x3 remote: BuyRoulette(id, nil, 3) through the remote is one x3 request", #sent .. " answers")
			local badTally = T.tally("egg x3: PetService.BuyRoulette answers a bad spins count 'Bad spins' (nothing charged)")
			for _, case in ipairs({ { "Cloud", nil, 2 }, { "Cloud", nil, 0 }, { "Cloud", "Tokens", 3.5 }, { "Cloud", nil, "3" }, { "Cloud", nil, {} }, { "Secret", "Gems", 3 }, { "Secret", nil, 3 } }) do
				local b = B.wallet(p)
				local okB, whyB = PS.BuyRoulette(p, case[1], case[2], case[3])
				badTally:case(okB == false and whyB == "Bad spins" and B.same(b, B.wallet(p)), tostring(case[1]) .. " x " .. tostring(case[3]) .. ": " .. tostring(whyB))
			end
			badTally:report()
			local curTally = T.tally("egg x3: junk currencies are still answered 'Unknown currency' (x1 and x3)")
			for _, cur in ipairs({ "diamonds", 5, { Currency = "x" } }) do
				for _, n in ipairs({ 1, 3 }) do
					local b = B.wallet(p)
					local okJ, whyJ = PS.BuyRoulette(p, "Cloud", cur, n)
					curTally:case(okJ == false and whyJ == "Unknown currency" and B.same(b, B.wallet(p)), tostring(cur) .. " x" .. n .. ": " .. tostring(whyJ))
				end
			end
			curTally:report()

			-- the PolicyService lock: gems x3 for a restricted account
			B.give(locked, 1000, 10000)
			before = B.wallet(locked)
			local okL, whyL = PS.BuyRoulette(locked, "Sky", "Gems", 3)
			T.check(okL == false and whyL == "Gem roulettes are not available on your account" and B.same(before, B.wallet(locked)),
				"egg x3: gems x3 for a restricted account: GemService's text, nothing charged", tostring(whyL))
			local okLT = PS.BuyRoulette(locked, "Cloud", nil, 3)
			T.check(okLT == true and B.wallet(locked).Tokens == 1000 - 3 * cloud.Price, "egg x3: ...token x3 stays open to that account")

			-- the 0.25 s cooldown counts one request
			B.give(p, 1000, 0)
			K.advance(0.4)
			before = B.wallet(p)
			mark = K.logSize()
			B.fire(p, "Cloud", nil, 3)
			K.advance(0.1)
			B.fire(p, "Cloud", nil, 3)
			K.advance(0.3)
			T.check(#B.results(p, mark) == 1 and B.wallet(p).Tokens == before.Tokens - 3 * cloud.Price, "egg x3 remote: two fires 0.1 s apart get one reply and one charge",
				#B.results(p, mark) .. " replies; " .. B.show(B.wallet(p)))

			-- a fault after the charge keeps the grant; a fault in the plan step charges nothing
			B.give(p, 1000, 0)
			before = B.wallet(p)
			rolled = B.countRolled(PS, p)
			PS._SetFaultForTest("after", function()
				error("smoke: injected fault after the charge")
			end)
			K.advance(0.4)
			mark = K.logSize()
			B.fire(p, "Cloud", nil, 3)
			K.advance(0.3)
			PS._SetFaultForTest("after", nil)
			rolled.stop()
			after = B.wallet(p)
			sent = B.results(p, mark)
			T.check(after.Tokens == before.Tokens - 3 * cloud.Price and after.Pets == before.Pets + 3 and after.Spins == before.Spins + 3,
				"egg x3 fault: an error in the refresh after the charge: the charge and all three pets landed together", B.show(before) .. " -> " .. B.show(after))
			T.check(#sent == 1 and type(sent[1]) == "table" and sent[1].Ok == true and #sent[1].Pulls == 3 and rolled.n == 3, "egg x3 fault: ...the reply was sent and Rolled fired three times",
				#sent .. " replies, " .. rolled.n .. " Rolled")
			before = B.wallet(p)
			PS._SetFaultForTest("plan", function()
				error("smoke: injected fault in the plan step")
			end)
			local okF, whyF = PS.BuyRoulette(p, "Cloud", nil, 3)
			K.advance(0.4)
			mark = K.logSize()
			B.fire(p, "Cloud", nil, 3)
			K.advance(0.3)
			PS._SetFaultForTest("plan", nil)
			sent = B.results(p, mark)
			T.check(okF == false and whyF == JAMMED and B.same(before, B.wallet(p)), "egg x3 fault: an error in the plan step (before the charge): nothing charged or granted", tostring(whyF) .. "; " .. B.show(B.wallet(p)))
			T.check(#sent == 1 and type(sent[1]) == "table" and sent[1].Ok == false and sent[1].Reason == JAMMED and sent[1].Spins == 3,
				"egg x3 fault: ...the remote answers Ok = false, Reason 'The roulette jammed, try again', Spins 3", #sent .. " replies")
		end)
		D.Sync = origSync
		pcall(function()
			PS._SetFaultForTest("after", nil)
			PS._SetFaultForTest("plan", nil)
			PS._SetRngForTest(Util.NewRng(), Util.NewRng())
		end)
		B.removePolicy()
		B.leave(players)
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("egg_spin_x3")
		K.flushWarnings("egg_spin_x3", ALLOWED_WARNINGS)
	end)

	------------------------------------------------------------------------------------------------------------------
	-- egg_full_stack
	------------------------------------------------------------------------------------------------------------------
	S.egg_full_stack = guarded("egg_full_stack", function()
		if not K.needBoot() then
			return
		end
		local Config, PS, D, PC = B.mods()
		local Util = req("shared/Util")
		local MAX = Config.Pets.MaxPerStack
		local players = {}
		local okRun, errRun = pcall(function()
			if not T.check(type(PS._SetRngForTest) == "function", "egg full stack: PetService._SetRngForTest exists") then
				return
			end
			B.installPolicy()
			local p = B.join("EggFull")
			players[1] = p
			T.eq(D._SettleForTest(p), true, "egg full stack: (setup) the gem settle hold ends")
			local prof = D.GetProfile(p)
			local cloud = B.roulette("Cloud")
			local commons = PC.RarityPool("Cloud", "Common")
			local commonTokens = Config.Index.Rewards.Common.Tokens
			local cloudTotal = 0
			for _, w in pairs(cloud.Odds) do
				cloudTotal = cloudTotal + w
			end
			local commonShare = cloud.Odds.Common / cloudTotal

			-- every Common at 99: each Common pull pays the Common Index Tokens; every spin charged; the share holds
			local full = {}
			for _, d in ipairs(commons) do
				prof.Pets[d.Id] = MAX
				full[d.Id] = true
			end
			D.MarkDirty(p)
			PS._SetRngForTest(Util.NewRng(7301), Util.NewRng(7302))
			local SPINS, CHUNK = 4000, 200
			local nCommon, badSub, badCharge, notOk, badReply, spins0 = 0, {}, 0, 0, {}, prof.Stats.Spins
			B.bulkSpins(p, function(flush)
				local expect = 0
				for i = 1, SPINS do
					if i % CHUNK == 1 then
						B.trimStacks(prof, 1, full)
						B.give(p, CHUNK * cloud.Price, nil)
						expect = 0
					end
					local okI, r = PS.BuyRoulette(p, "Cloud")
					local pull = okI == true and type(r) == "table" and type(r.Pulls) == "table" and r.Pulls[1] or nil
					if not pull then
						notOk = notOk + 1
					else
						if pull.Rarity == "Common" then
							nCommon = nCommon + 1
							if not (type(pull.Substitute) == "table" and pull.Substitute.Tokens == commonTokens and pull.Count == MAX and full[pull.PetId]) and #badSub < 3 then
								badSub[#badSub + 1] = fmt("spin %d: %s, Substitute %s, Count %s", i, tostring(pull.PetId), tostring(type(pull.Substitute) == "table" and pull.Substitute.Tokens), tostring(pull.Count))
							end
						end
						if type(pull.Substitute) == "table" then
							expect = expect + pull.Substitute.Tokens
						end
						if #badReply < 3 then
							local vp = K.V.rouletteResult(r)
							if #vp > 0 then
								badReply[#badReply + 1] = i .. ": " .. table.concat(vp, ", ")
							end
						end
					end
					if i % CHUNK == 0 then
						if D.GetTokens(p) ~= expect then
							badCharge = badCharge + 1
						end
						flush()
					end
				end
			end)
			T.eq(notOk, 0, "egg full stack: every Common at " .. MAX .. ": all " .. SPINS .. " Cloud spins answered Ok (a full stack never refuses after the roll)")
			T.check(#badSub == 0, "egg full stack: ...each Common pull pays Substitute.Tokens = " .. commonTokens .. " (the Common Index reward) with Count " .. MAX, table.concat(badSub, " | "))
			T.eq(badCharge, 0, "egg full stack: ...every spin was charged (each chunk: 200 x price spent, the substitute tokens added after the charge)")
			T.eq(prof.Stats.Spins, spins0 + SPINS, "egg full stack: ...Stats.Spins counts every spin")
			T.check(#badReply == 0, "egg full stack: ...the replies pass V.rouletteResult", table.concat(badReply, " | "))
			local grown = {}
			for _, d in ipairs(commons) do
				if prof.Pets[d.Id] ~= MAX then
					grown[#grown + 1] = d.Id .. "=" .. tostring(prof.Pets[d.Id])
				end
			end
			T.check(#grown == 0, "egg full stack: ...no Common stack grew", table.concat(grown, ", "))
			T.check(abs(nCommon / SPINS - commonShare) <= 0.025, "egg full stack: ...the Common share stays within 2.5 points of " .. fmt("%.0f%%", commonShare * 100) .. " (not a free reroll)",
				fmt("%.4f", nCommon / SPINS))

			-- one Common at 99: that pet is re-picked away (never granted), the others take its pulls, the share holds
			local capped = commons[1].Id
			for _, d in ipairs(commons) do
				prof.Pets[d.Id] = (d.Id == capped) and MAX or 1
			end
			D.MarkDirty(p)
			local SPINS2 = 2000
			local n2, granted, subs, notOk2 = 0, 0, 0, 0
			B.bulkSpins(p, function(flush)
				for i = 1, SPINS2 do
					if i % CHUNK == 1 then
						B.trimStacks(prof, 1, { [capped] = true })
						B.give(p, CHUNK * cloud.Price, nil)
					end
					local okI, r = PS.BuyRoulette(p, "Cloud")
					local pull = okI == true and type(r) == "table" and type(r.Pulls) == "table" and r.Pulls[1] or nil
					if not pull then
						notOk2 = notOk2 + 1
					elseif pull.Rarity == "Common" then
						n2 = n2 + 1
						if pull.PetId == capped then
							granted = granted + 1
						end
						if pull.Substitute ~= nil then
							subs = subs + 1
						end
					end
					if i % CHUNK == 0 then
						flush()
					end
				end
			end)
			T.eq(notOk2, 0, "egg full stack: one Common at " .. MAX .. ": all " .. SPINS2 .. " spins answered Ok")
			T.check(granted == 0 and prof.Pets[capped] == MAX and subs == 0, "egg full stack: ...that pet is never granted (re-picked from the other Commons, no substitute while they have room)",
				fmt("%d pulls named it, %d substitutes, count %s", granted, subs, tostring(prof.Pets[capped])))
			T.check(abs(n2 / SPINS2 - commonShare) <= 0.035, "egg full stack: ...the Common share is unchanged (within about 3 sigma at n = 2,000: 3.5 points)", fmt("%.4f", n2 / SPINS2))

			-- the Secret Roulette with both Mythics at 99: Mythic pulls pay the Mythic Index Tokens; the natural Secret share
			-- stays at 15% (only pulls without Pity count: a forced pity pull is not a natural one)
			local sr = Config.Gems.SecretRoulette
			local mythics = PC.RarityPool(sr.Id, "Mythic")
			local fullM = {}
			for _, d in ipairs(mythics) do
				prof.Pets[d.Id] = MAX
				fullM[d.Id] = true
			end
			D.MarkDirty(p)
			local mythicTokens = Config.Index.Rewards.Mythic.Tokens
			local SPINS3 = 2000
			local natural, secretNatural, badMythic, notOk3, badGems = 0, 0, {}, 0, 0
			-- Task 5 (the pity): every pull's Secret count, the forced pulls (each must be a Secret pet, or a Secret
			-- substitute when every Secret is full) and the replies without SecretPity.Left
			local allSecret, forced, badForced, noLeft = 0, 0, {}, 0
			local srTotal = 0
			for _, w in pairs(sr.Odds) do
				srTotal = srTotal + w
			end
			local pity0 = type(D.GetPity) == "function" and D.GetPity(p) or nil
			local tokens0, expect = D.GetTokens(p), 0
			B.bulkSpins(p, function(flush)
				for i = 1, SPINS3 do
					if i % CHUNK == 1 then
						B.trimStacks(prof, 1, fullM)
						B.give(p, nil, CHUNK * sr.GemPrice)
					end
					local okI, r = PS.BuyRoulette(p, sr.Id)
					local pull = okI == true and type(r) == "table" and type(r.Pulls) == "table" and r.Pulls[1] or nil
					if not pull then
						notOk3 = notOk3 + 1
					else
						if pull.Pity ~= true then
							natural = natural + 1
							if pull.Rarity == "Secret" then
								secretNatural = secretNatural + 1
							end
						else
							forced = forced + 1
							if pull.Rarity ~= "Secret" and #badForced < 3 then
								badForced[#badForced + 1] = fmt("spin %d: %s (%s)", i, tostring(pull.PetId), tostring(pull.Rarity))
							end
						end
						if pull.Rarity == "Secret" then
							allSecret = allSecret + 1
						end
						if not (type(r.SecretPity) == "table" and type(r.SecretPity.Left) == "number") then
							noLeft = noLeft + 1
						end
						if pull.Rarity == "Mythic" then
							if not (type(pull.Substitute) == "table" and pull.Substitute.Tokens == mythicTokens) and #badMythic < 3 then
								badMythic[#badMythic + 1] = fmt("spin %d: %s Substitute %s", i, tostring(pull.PetId), tostring(type(pull.Substitute) == "table" and pull.Substitute.Tokens))
							end
							expect = expect + mythicTokens
						end
					end
					if i % CHUNK == 0 then
						if D.GetGems(p) ~= 0 then
							badGems = badGems + 1
						end
						flush()
					end
				end
			end)
			T.eq(notOk3, 0, "egg full stack Secret: both Mythics at " .. MAX .. ": all " .. SPINS3 .. " Secret Roulette spins answered Ok")
			T.check(#badMythic == 0, "egg full stack Secret: ...every Mythic pull pays Substitute.Tokens = " .. mythicTokens .. " (the Mythic Index reward)", table.concat(badMythic, " | "))
			T.eq(badGems, 0, "egg full stack Secret: ...every spin was charged its " .. sr.GemPrice .. " Gems")
			T.check(expect > 0 and D.GetTokens(p) == tokens0 + expect, "egg full stack Secret: ...and the Mythic substitute tokens were added (" .. mythicTokens .. " per Mythic pull)",
				fmt("%s -> %s, expected +%d", tostring(tokens0), tostring(D.GetTokens(p)), expect))
			local want = (sr.Odds.Secret or 0) / srTotal
			T.check(natural > 0 and abs(secretNatural / natural - want) <= 0.03, "egg full stack Secret: ...the natural Secret share (pulls without Pity) stays within 3 points of " .. fmt("%.0f%%", want * 100),
				fmt("%d of %d natural pulls (%.4f)", secretNatural, natural, natural > 0 and secretNatural / natural or 0))
			-- Task 5: the pity forces a Secret after every PityAt - 1 dry spins, so over every pull the long-run share is
			-- want / (1 - (1 - want)^PityAt) (22.1% at 15% and 7): that is the pity working, not a failure
			T.check(forced > 0 and #badForced == 0, "egg full stack Secret: ...the pity forced pulls (Pity == true) and every forced pull is a Secret",
				forced .. " forced; " .. table.concat(badForced, " | "))
			local pity1 = type(D.GetPity) == "function" and D.GetPity(p) or nil
			T.check(type(pity0) == "table" and type(pity1) == "table" and pity1.Spins == pity0.Spins + SPINS3,
				"egg full stack Secret: ...GetPity(p).Spins grew by exactly " .. SPINS3 .. " (substitute pulls count)",
				tostring(type(pity0) == "table" and pity0.Spins) .. " -> " .. tostring(type(pity1) == "table" and pity1.Spins))
			T.eq(noLeft, 0, "egg full stack Secret: ...every Secret Roulette reply carries SecretPity.Left")
			local at = tonumber(sr.PityAt) or 7
			local wantAll = want / (1 - (1 - want) ^ at)
			T.check(abs(allSecret / SPINS3 - wantAll) <= 0.03, "egg full stack Secret: ...the Secret share over all pulls is near " .. fmt("%.1f%%", wantAll * 100) .. " (within 3 points; the pity working)",
				fmt("%d of %d (%.4f)", allSecret, SPINS3, allSecret / SPINS3))
		end)
		pcall(PS._SetRngForTest, Util.NewRng(), Util.NewRng())
		B.removePolicy()
		B.leave(players)
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("egg_full_stack")
		K.flushWarnings("egg_full_stack", ALLOWED_WARNINGS)
	end)

	------------------------------------------------------------------------------------------------------------------
	-- egg_strip
	------------------------------------------------------------------------------------------------------------------
	S.egg_strip = guarded("egg_strip", function()
		if not K.needBoot() then
			return
		end
		local _, PS, D, PC = B.mods()
		local Util = req("shared/Util")
		local players = {}
		local okRun, errRun = pcall(function()
			if not T.check(type(PS._SetRngForTest) == "function", "egg strip: PetService._SetRngForTest exists") then
				return
			end
			local p = B.join("EggStrip")
			players[1] = p
			local cloud = B.roulette("Cloud")
			-- a roll generator that always draws the same numbers: every pull is the same pet, the strips still vary
			local fixed = {}
			function fixed:Float(a, b)
				return a + (b - a) * 0.3
			end
			function fixed:Int(a)
				return a
			end
			T.eq(PS._SetRngForTest(fixed, Util.NewRng(5151)), true, "egg strip: _SetRngForTest answers true in the mock (Studio)")
			local possible = {}
			for _, def in ipairs(PC.PossiblePets("Cloud")) do
				possible[def.Id] = true
			end
			B.give(p, 60 * cloud.Price, 0)
			local strips, winners, fillersOk, bad = {}, {}, true, nil
			for i = 1, 50 do
				local ok, r = PS.BuyRoulette(p, "Cloud")
				local pull = ok == true and type(r) == "table" and type(r.Pulls) == "table" and r.Pulls[1] or nil
				if pull and type(pull.Strip) == "table" then
					strips[#strips + 1] = table.concat(pull.Strip, ",")
					winners[pull.PetId] = true
					for k, id in ipairs(pull.Strip) do
						if k ~= 34 and not possible[id] then
							fillersOk, bad = false, tostring(id)
						end
					end
				end
			end
			local distinct, nWinners = {}, 0
			local nDistinct = 0
			for _, s in ipairs(strips) do
				if not distinct[s] then
					distinct[s] = true
					nDistinct = nDistinct + 1
				end
			end
			for _ in pairs(winners) do
				nWinners = nWinners + 1
			end
			T.check(#strips == 50 and nWinners == 1, "egg strip: (precondition) the fixed roll generator gives the same pet on all 50 spins", #strips .. " strips, " .. nWinners .. " winners")
			T.check(nDistinct > 1, "egg strip: ...yet the 50 strips are not all equal (they come from the strip generator, not the roll generator)", nDistinct .. " distinct strips")
			T.check(fillersOk, "egg strip: ...every filler is a pet the Cloud Roulette can roll", tostring(bad))
			local ok3, r3 = PS.BuyRoulette(p, "Cloud", nil, 3)
			local s = {}
			if ok3 == true and type(r3) == "table" and type(r3.Pulls) == "table" then
				for j = 1, 3 do
					s[j] = type(r3.Pulls[j]) == "table" and type(r3.Pulls[j].Strip) == "table" and table.concat(r3.Pulls[j].Strip, ",") or ("?" .. j)
				end
			end
			T.check(#s == 3 and s[1] ~= s[2] and s[2] ~= s[3] and s[1] ~= s[3], "egg strip: the three strips of one x3 differ")
			T.check(D.GetTokens(p) == 60 * cloud.Price - 53 * cloud.Price, "egg strip: (the 53 spins were charged as usual)", tostring(D.GetTokens(p)))
		end)
		pcall(PS._SetRngForTest, Util.NewRng(), Util.NewRng())
		B.leave(players)
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("egg_strip")
		K.flushWarnings("egg_strip", ALLOWED_WARNINGS)
	end)

	------------------------------------------------------------------------------------------------------------------
	-- egg_announce (Task 6): one chat line per request, Legendary and up, at most one per player every 10 s
	------------------------------------------------------------------------------------------------------------------
	S.egg_announce = guarded("egg_announce", function()
		if not K.needBoot() then
			return
		end
		local Config, PS, D, PC = B.mods()
		local Util = req("shared/Util")
		local GAP, DELAY = 10, 5 -- PetService ANNOUNCE_GAP / ANNOUNCE_DELAY (spec 5.5)
		local players = {}
		local okRun, errRun = pcall(function()
			B.installPolicy()
			local p = B.join("EggAnn")
			local witness = B.join("EggWit")
			players = { p, witness }
			local storm, sky = B.roulette("Storm"), B.roulette("Sky")
			-- one steered request of `who`; checks the pulls came out as asked (the test's own precondition)
			local function spin(who, id, rarities, spins, ints)
				local fracs = {}
				for j, r in ipairs(rarities) do
					fracs[j] = B.band(PC, id, r)
				end
				B.give(who, 3 * 1000 * #rarities + D.GetTokens(who), nil)
				PS._SetRngForTest(B.steer(fracs, ints), nil)
				local ok, res = PS.BuyRoulette(who, id, "Tokens", spins)
				local got = {}
				for j, pull in ipairs(ok == true and type(res) == "table" and type(res.Pulls) == "table" and res.Pulls or {}) do
					got[j] = tostring(pull.Rarity)
				end
				T.check(ok == true and table.concat(got, ",") == table.concat(rarities, ","), "egg announce: the steered " .. id .. " request gives " .. table.concat(rarities, ", "),
					table.concat(got, ",") .. " " .. tostring((not ok) and res or ""))
				return type(res) == "table" and res or { Pulls = {} }
			end
			local function line(who, res, j, rarity, more)
				local pull = res.Pulls[j]
				local def = pull and PC.Get(pull.PetId)
				local text = who.DisplayName .. " hatched a " .. rarity .. " " .. tostring(def and def.Name) .. "!"
				if more > 0 then
					text = text .. " (+" .. more .. " more)"
				end
				return text
			end

			-- an Epic pull: not announced, to anyone
			local mark = K.logSize()
			spin(p, storm.Id, { "Epic" })
			K.advance(DELAY + 1)
			T.eq(B.announcements(mark), 0, "egg announce: an Epic pull sends no 'pull' Notify (nor any announcement) to anyone, the puller included")

			-- a Legendary: the witness at once, the puller after 5 s and not before
			mark = K.logSize()
			local rL = spin(p, storm.Id, { "Legendary" })
			local wantL = line(p, rL, 1, "Legendary", 0)
			K.advance(0.2)
			local w, dur = B.pullLines(witness, mark)
			T.check(#w == 1 and w[1] == wantL, "egg announce: a Legendary -> the witness gets one Notify kind 'pull' '" .. wantL .. "' at once", table.concat(w, " | "))
			T.eq(dur[1], 4, "egg announce: ...shown for 4 s")
			T.eq(#B.pullLines(p, mark), 0, "egg announce: ...the puller gets nothing at once")
			K.advance(DELAY - 0.6)
			T.eq(#B.pullLines(p, mark), 0, "egg announce: ...nor at 4.6 s (his reveal still plays)")
			K.advance(0.8)
			local mine = B.pullLines(p, mark)
			T.check(#mine == 1 and mine[1] == wantL, "egg announce: ...the puller gets the same line after 5 s", table.concat(mine, " | "))
			T.eq(#B.pullLines(witness, mark), 1, "egg announce: ...and the witness still has exactly one")
			K.advance(GAP - DELAY + 0.5) -- the 10 s gap ends

			-- an x3: one line, the best pull named, the other Legendary-or-better pulls counted
			mark = K.logSize()
			local r3 = spin(p, sky.Id, { "Legendary", "Mythic", "Epic" }, 3)
			local want3 = line(p, r3, 2, "Mythic", 1)
			K.advance(0.2)
			w = B.pullLines(witness, mark)
			T.check(#w == 1 and w[1] == want3, "egg announce: an x3 Legendary + Mythic + Epic -> one line naming the Mythic with ' (+1 more)'", table.concat(w, " | "))
			K.advance(GAP + 0.5)
			mine = B.pullLines(p, mark)
			T.check(#B.pullLines(witness, mark) == 1 and #mine == 1 and mine[1] == want3, "egg announce: ...one line in all (the puller's copy is the same line)", table.concat(mine, " | "))

			-- ties go to the first pull
			local legendaryPool = 0
			for _, row in ipairs(PC.GetRarityOdds(sky.Id)) do
				if row.Rarity == "Legendary" then
					legendaryPool = row.Count
				end
			end
			mark = K.logSize()
			local rT = spin(p, sky.Id, { "Legendary", "Legendary", "Epic" }, 3, { 1, 2, 1 })
			local wantT = line(p, rT, 1, "Legendary", 1)
			K.advance(0.2)
			w = B.pullLines(witness, mark)
			T.check(#w == 1 and w[1] == wantT, "egg announce: two Legendary pulls in one x3 -> the first one is named (ties go to the first), ' (+1 more)'", table.concat(w, " | "))
			T.check(legendaryPool < 2 or (rT.Pulls[1] and rT.Pulls[2] and rT.Pulls[1].PetId ~= rT.Pulls[2].PetId), "egg announce: ...(the two Legendary pulls are different pets)")
			K.advance(GAP + 0.5)

			-- two Legendary requests 2 s apart: the second is held and arrives as one line when the gap ends
			mark = K.logSize()
			local rA = spin(p, storm.Id, { "Legendary" })
			local wantA = line(p, rA, 1, "Legendary", 0)
			K.advance(2)
			local rB = spin(p, storm.Id, { "Legendary" }, 1, { 2 })
			local wantB = line(p, rB, 1, "Legendary", 0)
			K.advance(0.2)
			w = B.pullLines(witness, mark)
			T.check(#w == 1 and w[1] == wantA, "egg announce: two Legendary requests 2 s apart -> the first line at once, the second held", table.concat(w, " | "))
			K.advance(GAP - 2.2 - 0.4)
			T.eq(#B.pullLines(witness, mark), 1, "egg announce: ...nothing more before the 10 s gap ends (9.6 s)")
			K.advance(0.8)
			w = B.pullLines(witness, mark)
			T.check(#w == 2 and w[2] == wantB, "egg announce: ...the held request arrives as one line when the gap ends (10.4 s)", table.concat(w, " | "))
			K.advance(DELAY + 0.5)
			mine = B.pullLines(p, mark)
			T.check(#mine == 2 and mine[1] == wantA and mine[2] == wantB, "egg announce: ...the puller gets both, each 5 s after the others", table.concat(mine, " | "))
			K.advance(GAP)

			-- several requests held in one gap: one line, the best held pull named (the first on ties), every other held
			-- Legendary-or-better pull counted
			mark = K.logSize()
			local rC = spin(p, storm.Id, { "Legendary" })
			local wantC = line(p, rC, 1, "Legendary", 0)
			K.advance(1)
			spin(p, sky.Id, { "Legendary", "Epic", "Legendary" }, 3)
			K.advance(1)
			local rE = spin(p, sky.Id, { "Mythic" })
			K.advance(1)
			spin(p, sky.Id, { "Mythic" }, 1, { 2 })
			K.advance(GAP - 3 + 0.4)
			local wantHeld = line(p, rE, 1, "Mythic", 3)
			w = B.pullLines(witness, mark)
			T.check(#w == 2 and w[1] == wantC and w[2] == wantHeld,
				"egg announce: requests held in one gap go out as one line: the best held pull named (the first Mythic), ' (+3 more)' for the other three held",
				table.concat(w, " | "))
			K.advance(DELAY + GAP + 0.5)

			-- five x3 Legendary requests within 10 s: at most 2 lines reach the witness in those 10 s
			mark = K.logSize()
			local five = {}
			for i = 1, 5 do
				five[i] = spin(p, sky.Id, { "Legendary", "Legendary", "Legendary" }, 3)
				K.advance(i < 5 and 2 or 1.5)
			end
			w = B.pullLines(witness, mark)
			T.check(#w >= 1 and #w <= 2, "egg announce: five x3 Legendary requests within 10 s -> at most 2 lines reach the witness in those 10 s", #w .. " lines: " .. table.concat(w, " | "))
			T.check(w[1] == line(p, five[1], 1, "Legendary", 2), "egg announce: ...the first names its first pull with ' (+2 more)'", tostring(w[1]))
			K.advance(1)
			w = B.pullLines(witness, mark)
			T.check(#w == 2 and w[2] == line(p, five[2], 1, "Legendary", 11),
				"egg announce: ...the four held x3 requests arrive as one line when the gap ends (the first held pull named, ' (+11 more)')", table.concat(w, " | "))
			K.advance(DELAY + GAP + 0.5)

			-- a held line of a player who leaves is dropped (nothing announced for him after he left, no error)
			local q = B.join("EggLeaver")
			players[3] = q
			mark = K.logSize()
			local rQ = spin(q, storm.Id, { "Legendary" })
			K.advance(2)
			spin(q, storm.Id, { "Legendary" })
			K.advance(1)
			Mock.RemovePlayer(q)
			K.advance(GAP + DELAY)
			w = B.pullLines(witness, mark)
			T.check(#w == 1 and w[1] == line(q, rQ, 1, "Legendary", 0), "egg announce: a player who leaves while a line is held: only his first line went out (the held one is dropped)",
				table.concat(w, " | "))
		end)
		pcall(PS._SetRngForTest, Util.NewRng(), Util.NewRng())
		B.removePolicy()
		B.leave(players)
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("egg_announce")
		K.flushWarnings("egg_announce", ALLOWED_WARNINGS)
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC

	-- shown labels whose text is exactly `text`
	local function shownExactly(text)
		local n = 0
		for _, d in ipairs(KC.texts(nil, true)) do
			if tostring(d.Text) == text then
				n = n + 1
			end
		end
		return n
	end

	S.client_notify_pull = guarded("client_notify_pull", function()
		local TCS = game:GetService("TextChatService")
		local channels = TCS:FindFirstChild("TextChannels")
		T.check(channels ~= nil and channels:FindFirstChild("RBXSystem") ~= nil and channels.RBXSystem:IsA("TextChannel"),
			"notify pull: the mock has TextChatService.TextChannels.RBXSystem (a TextChannel)")
		Mock.SystemMessages = Mock.SystemMessages or {}
		KC.advance(6) -- earlier toasts leave
		local n0 = #Mock.SystemMessages
		local text = "Ann hatched a Legendary Sun Fox!"
		KC.toClient("Notify", text, "pull", 4)
		KC.advance(0.5)
		local got = Mock.SystemMessages[n0 + 1]
		T.check(#Mock.SystemMessages == n0 + 1 and type(got) == "string" and string.find(got, '<font color="#F2B644">Legendary</font>', 1, true) ~= nil,
			"notify pull: kind 'pull' -> one RBXSystem system message with the rarity word in its colour (<font color=\"#F2B644\">Legendary</font>)",
			tostring(got) .. " (" .. (#Mock.SystemMessages - n0) .. " messages)")
		T.check(type(got) == "string" and string.find(got, "Ann hatched a ", 1, true) == 1 and string.find(got, " Sun Fox!", 1, true) ~= nil,
			"notify pull: ...the rest of the line unchanged", tostring(got))
		T.check(KC.findText("sun fox") == nil, "notify pull: ...and no toast", KC.allShownText())

		-- the best of an x3 with (+N more), a Mythic in its colour, rich text in the name escaped
		KC.toClient("Notify", "A<b>&c hatched a Mythic Aurora Fox! (+2 more)", "pull", 4)
		KC.advance(0.5)
		got = Mock.SystemMessages[n0 + 2]
		T.check(type(got) == "string" and string.find(got, '<font color="#EE628C">Mythic</font>', 1, true) ~= nil and string.find(got, "(+2 more)", 1, true) ~= nil,
			"notify pull: a Mythic line keeps ' (+2 more)' and colours 'Mythic' (#EE628C)", tostring(got))
		T.check(type(got) == "string" and string.find(got, "A&lt;b&gt;&amp;c hatched a ", 1, true) == 1, "notify pull: ...'<', '>' and '&' of the text are escaped for rich text", tostring(got))

		-- other kinds still toast and never reach the chat
		KC.toClient("Notify", "Plain toast here", "good", 3)
		KC.advance(0.5)
		T.check(#Mock.SystemMessages == n0 + 2 and KC.findText("plain toast here") ~= nil, "notify pull: kind 'good' stays a toast, no system message")
		KC.advance(4)

		-- no channel (the legacy chat, or not replicated yet): today's toast with the text
		if channels then
			channels.Parent = nil
		end
		local okRun, errRun = pcall(function()
			local n1 = #Mock.SystemMessages
			KC.toClient("Notify", text, "pull", 4)
			KC.advance(0.5)
			T.check(#Mock.SystemMessages == n1 and shownExactly(text) == 1, "notify pull: without TextChannels -> one toast with the text, no system message", KC.allShownText())
			KC.advance(5)
		end)
		if channels then
			channels.Parent = TCS
		end
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_notify_pull")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
