-- smoke_p5_home.lua: the Phase 5 home (ARCHITECTURE_V3.md "Phase 5 build contract" 3.3-3.5, 9.2 step 3, 12.1).
-- Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half. Owners by wave (table 11.1):
--   economy+roam (W1), pure, server world:
--     p5home_catalog      the 11 stations == the constants block of tools/sim_tycoon.py (ids, kinds, prices, caps),
--                         Kinds, decor 0.4x, caps 24 / 45 / 72 / 80, Validate, the no-dead-end build-out from a fresh
--                         home and from stars 1-3, HomeLevelOf with DecorCredit / the legacy magnet, SignedPads on real
--                         pads, BasketCap / FeedBerries
--     p5home_fold         TycoonCatalog.FoldLegacy fixtures: fresh / Press1 6 + Press2 4 / all plants 10 / Collector 3
--                         at Prestige 2 / all decor 3 / a Phase 4 Press2 after the marker: Home Level and food never
--                         drop, the expected farm level, credits, idempotent
--     p5home_roam_shared  HomeRoam: Version, the graph (>= 300 nodes), two copies give identical plans for 3 seeds x 12
--                         slots x 50 cycles, speeds 4-9, idle >= 1 s, poop points inside the yard and off every Blocked
--                         rect, continuity (never faster than MaxSpeed between 0.05 s samples, cycle edges and the settle
--                         walk included), At states / PoopTime / BedPoint / EatPoint, cache <= 3 cycles, junk
--   tycoon+care (W2), server world (booted game):
--     p5home_signs        TycoonCatalog.SignedPads over a booted home's pads: the cheapest when nothing is affordable,
--                         the 3 cheapest affordable, never a locked pad, the Prestige pad first when unlocked, pure
--     p5home_berries      poops grow value x Share berries (whole, fraction in the ledger), BerryCap = BasketCap,
--                         the clamp at the cap + 'Basket full!' once, a cap below the berries removes none, no sync
--                         on a Berries-only change, the Berries attribute <= 2 / s, Feed spends FeedBerries for FeedXp
--                         (no Food path, { Count } = one feed, every refusal, XP 0 refunds, provisional), offline
--                         berries once with the cap ignored
--     p5home_roam_server  12 roaming pets: Epoch = now + 20 (0.1 s), first poop >= 24 s, every drop at Plan().Poop,
--                         poops == due PoopTimes, <= 3 drops per slot then merging, stages, the invariant every tick,
--                         CoinDrops format / <= 0.5 writes/s / <= 400 B, owner scoop radius 8 / visitor never, churn
--                         keeps the epoch, nap at the cap + wake by a scoop (epoch = now + back walk), rebase -> Welcome once
--   homefx+pets (W3), client world:
--     client_p5home_roam     12 roaming pets posed within 0.5 stud of HomeRoam.At (+ the soft separation <= 1.5), eating
--                            at the Food Bowl, an evolved pet at Low, a poop pops a pending TokenLook coin at Plan().Poop,
--                            CoinDrops confirms it / it fades after 2.5 s, a merge changes the look, the scoop zip +
--                            '+$' at the drop, others' coins dimmed and still, budgets (24 pets, 36 coins x 6, 16
--                            bits, 9000 parts), a nap at the far point + Zzz, RoamVersion mismatch parks, beyond 110
--     client_p5home_flow_ui  the three signs, the basket line follows Berries / BerryCap, berry flights, SignedPads'
--                            'Unsigned' pad signs, the Home window texts (careui) when MenuController is there
-- Plain Lua 5.1 syntax only; deterministic (fixed seeds and epochs, no game clock).

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, max, min, sqrt = math.abs, math.floor, math.max, math.min, math.sqrt

local S = {}

local CONTRACT_IDS = {
	"Press1", "Garden", "Kitchen", "Gym", "Vault", "House", "FusionMachine", "ArenaGate",
	"DecorFence", "DecorFountain", "DecorPodium",
}

-- the Phase 4 data the fold is measured against (Phase 4 contract table 3.1)
local P4_PLANT_FOOD = {
	Press1 = { 7, 9, 12, 16, 21, 27, 35, 45, 59, 76 },
	Press2 = { 19, 24, 32, 42, 53, 69, 91, 118, 153, 199 },
	Press3 = { 49, 63, 82, 107, 140, 180, 235, 302, 396, 518 },
	Press4 = { 127, 164, 215, 278, 360, 468, 612, 792, 1030, 1339 },
}

local function loadModule(path)
	local inst = K.moduleInstance(path)
	if not inst then
		return nil, "no ModuleScript " .. path
	end
	local ok, result = pcall(require, inst)
	if not ok or type(result) ~= "table" then
		return nil, tostring(result)
	end
	return result
end

local function readRepoFile(rel)
	local here = debug.getinfo(1, "S").source:match("^=(.*)smoke_p5_home%.lua$")
	local candidates = { rel, "../" .. rel }
	if here and here ~= "" then
		table.insert(candidates, 1, here .. "../" .. rel)
	end
	for _, path in ipairs(candidates) do
		local fh = io.open(path, "r")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src, path
		end
	end
	return nil, rel .. " not found from the working directory"
end

-- a fresh copy of a shared module from its source (its own upvalues / caches), with `script.Parent` answering the
-- given children
local function freshCopy(rel, name, children)
	local src, err = readRepoFile(rel)
	if not src then
		return nil, err
	end
	local shared = {}
	for k, v in pairs(children) do
		shared[k] = { Name = k, Value = v }
	end
	function shared:FindFirstChild(n)
		return rawget(self, n)
	end
	local env = setmetatable({
		script = { Parent = shared },
		require = function(m)
			if type(m) == "table" and m.Value ~= nil then
				return m.Value
			end
			error("no module " .. tostring(m))
		end,
	}, { __index = _G })
	local fn
	if setfenv and loadstring then
		fn, err = loadstring(src, "=" .. name .. "(copy)")
		if fn then
			setfenv(fn, env)
		end
	else
		fn, err = load(src, "=" .. name .. "(copy)", "t", env)
	end
	if not fn then
		return nil, err
	end
	local ok, result = pcall(fn)
	if not ok then
		return nil, tostring(result)
	end
	return result
end

local function home(stations, prestige, extra)
	local h = { Stations = stations or {}, Prestige = prestige or 0 }
	for k, v in pairs(extra or {}) do
		h[k] = v
	end
	return h
end

local function copyStations(st)
	local out = {}
	for k, v in pairs(st) do
		out[k] = v
	end
	return out
end

local function idList(set)
	local out = {}
	for k, v in pairs(set) do
		if v then
			out[#out + 1] = k
		end
	end
	table.sort(out)
	return table.concat(out, ", ")
end

----------------------------------------------------------------------------------------------------
-- p5home_catalog (economy+roam W1)
----------------------------------------------------------------------------------------------------
S.p5home_catalog = guarded("p5home_catalog", function()
	local TC, err = loadModule("shared/TycoonCatalog")
	if not T.check(TC ~= nil, "p5 home: TycoonCatalog loads", err) then
		return
	end
	T.eq(TC.Version, 5, "p5 home: TycoonCatalog.Version 5")
	-- the 11 stations == the sim's constants block (ids from its PRICE_<id> lines)
	local src = readRepoFile("tools/sim_tycoon.py")
	local block = src and src:match("# ==== BEGIN SIM CONSTANTS ====\n(.-)\n# ==== END SIM CONSTANTS ====")
	local simIds = {}
	for id in (block or ""):gmatch("\nPRICE_([%w_]+) = ") do
		simIds[id] = true
	end
	if block and block:match("^PRICE_([%w_]+) = ") then
		simIds[block:match("^PRICE_([%w_]+) = ")] = true
	end
	local catIds = {}
	for _, def in ipairs(TC.Stations) do
		catIds[def.Id] = true
	end
	T.check(idList(simIds) == idList(catIds) and #TC.Stations == 11, "p5 home: the 11 stations == the sim's PRICE_<id> block",
		"sim " .. idList(simIds) .. " / catalog " .. idList(catIds))
	local kinds = {}
	for _, def in ipairs(TC.Stations) do
		kinds[def.Kind] = true
	end
	T.check(kinds.Farm and not kinds.Plant and not kinds.Magnet and TC.Get("Press1").Kind == "Farm" and TC.Get("Press1").MaxLevel == 40,
		"p5 home: one Berry Farm (Kind Farm, 40 levels); no Plant / Magnet kinds")
	local decorOk = TC.Get("DecorFence").Price[1] == 2800 and TC.Get("DecorFountain").Price[1] == 18000 and TC.Get("DecorPodium").Price[1] == 3600
	T.check(decorOk, "p5 home: decor = 0.4 x Phase 4 (2,800 / 18,000 / 3,600)")
	local ok, problems = TC.Validate()
	T.check(ok == true, "p5 home: Validate() passes (beds, bowl, entrance, Welcome pile, the roaming graph)", table.concat(problems or {}, " | "))
	-- build-outs: cheapest first with unlimited Cash from a fresh home and from stars 1-3: the prestige, no dead end
	local function buildOut(stars)
		local h = home({}, stars)
		for _ = 1, 600 do
			if TC.CanPrestige(h) then
				return true, h
			end
			local best = nil
			for _, pad in ipairs(TC.AvailablePads(h)) do
				if not pad.Locked and not pad.Prestige and (not best or pad.Price < best.Price) then
					best = pad
				end
			end
			if not best then
				break
			end
			h.Stations[best.StationId] = best.NextLevel
		end
		return TC.CanPrestige(h), h
	end
	local outs = {}
	for stars = 0, 3 do
		local okB, h = buildOut(stars)
		outs[#outs + 1] = (okB and "ok" or "DEAD END") .. " (stars " .. stars .. ", Home Level " .. TC.HomeLevelOf(h) .. ")"
		T.check(okB, "p5 home: the cheapest-first build-out reaches the prestige from stars " .. stars, outs[#outs])
	end
	-- a full first run reaches Home Level 77 >= 40 without the Fusion Machine
	local full = home({}, 0)
	for _, def in ipairs(TC.Stations) do
		if not (def.Requires.Prestige and def.Requires.Prestige > 0) then
			full.Stations[def.Id] = def.MaxLevel
		end
	end
	T.eq(TC.HomeLevelOf(full), 77, "p5 home: every station but the Fusion Machine maxed = Home Level 77")
	T.eq(TC.HomeLevelOf(home({ Garden = 1 }, 0, { DecorCredit = 4, LegacyMagnet = 2, LegacyMagnetStar = 0 })), 7,
		"p5 home: HomeLevelOf = stations + DecorCredit + the legacy magnet")
	-- signs on real pads
	local h = home({ Garden = 1, Press1 = 2 }, 0)
	local pads = TC.AvailablePads(h)
	local signs = TC.SignedPads(pads, 200)
	local n = 0
	for _ in pairs(signs) do
		n = n + 1
	end
	T.check(signs.Press1 == true and signs.House == true and n == 2, "p5 home: with $200 only the affordable Farm 3 ($160) and Cottage ($180) are signed", idList(signs))
	signs = TC.SignedPads(pads, 1e9)
	n = 0
	for id in pairs(signs) do
		n = n + 1
		local _ = id
	end
	T.check(n == 3, "p5 home: rich: the 3 cheapest open pads are signed", idList(signs))
	-- berries
	T.check(TC.BasketCap(h, 0) == 500 and TC.BasketCap(h, 40) == 18000 and TC.FeedBerries("Common", 1) == 40 and TC.FeedBerries("Legendary", 99) == TC.FeedPrice("Legendary", 99),
		"p5 home: BasketCap 500 minimum / 30 min of berries (40 $/s -> 18,000); FeedBerries = the Phase 4 FeedPrice")
end)

----------------------------------------------------------------------------------------------------
-- p5home_fold (economy+roam W1)
----------------------------------------------------------------------------------------------------
-- the Phase 4 Home Level and meal food of a Phase 4 home (18 stations, plants 1-4)
local function p4HomeLevel(st)
	local n = 0
	for _, v in pairs(st) do
		n = n + v
	end
	return n
end

local function p4Food(st)
	if (st.Garden or 0) < 1 then
		return 0
	end
	local f = 12
	for id, food in pairs(P4_PLANT_FOOD) do
		local lv = st[id] or 0
		if lv > 0 then
			f = f + food[lv]
		end
	end
	return f
end

S.p5home_fold = guarded("p5home_fold", function()
	local TC, err = loadModule("shared/TycoonCatalog")
	if not T.check(TC ~= nil and type(TC.FoldLegacy) == "function", "p5 fold: TycoonCatalog.FoldLegacy exists", err) then
		return
	end
	local fixtures = {
		{ name = "fresh home", st = {}, stars = 0, first = true, changed = false, farm = nil, credit = nil, magnet = nil },
		{ name = "Press1 6 + Press2 4", st = { Garden = 2, Press1 = 6, Press2 = 4 }, stars = 0, first = true, changed = true, farm = 10 },
		{ name = "Press1 3 + Press3 2 (the food floor lifts 5 -> 11)", st = { Garden = 2, Press1 = 3, Press3 = 2 }, stars = 0, first = true,
			changed = true, farm = 11 },
		{ name = "all plants 10", st = { Garden = 8, Press1 = 10, Press2 = 10, Press3 = 10, Press4 = 10, House = 4 }, stars = 1, first = true,
			changed = true, farm = 40 },
		{ name = "Collector 3 at Prestige 2", st = { Garden = 1, Press1 = 1, Collector = 3 }, stars = 2, first = true, changed = true,
			farm = 1, magnet = 3 },
		{ name = "all decor 3", st = { Garden = 1, DecorLamps = 3, DecorFence = 3, DecorFlowers = 3, DecorFountain = 3, DecorBanners = 3, DecorPodium = 3 },
			stars = 1, first = true, changed = true, credit = 9, fence = 3, fountain = 3 },
		{ name = "Press1 alone (L5 -> L6 by the food floor)", st = { Garden = 1, Press1 = 5 }, stars = 0, first = true, changed = true, farm = 6 },
	}
	for _, fx in ipairs(fixtures) do
		local before = copyStations(fx.st)
		local h = home(copyStations(fx.st), fx.stars)
		local changed = TC.FoldLegacy(h, fx.first)
		local st = h.Stations
		local oldHL, newHL = p4HomeLevel(before), TC.HomeLevelOf(h)
		local oldFood, newFood = p4Food(before), TC.FoodOf(h)
		T.check(changed == fx.changed, "p5 fold " .. fx.name .. ": changed = " .. tostring(fx.changed), tostring(changed))
		T.check(newHL >= oldHL and newFood >= oldFood, "p5 fold " .. fx.name .. ": Home Level and food never drop",
			"HL " .. oldHL .. " -> " .. newHL .. ", food " .. oldFood .. " -> " .. newFood)
		T.check(st.Press2 == nil and st.Press3 == nil and st.Press4 == nil and st.Collector == nil and st.DecorLamps == nil
			and st.DecorFlowers == nil and st.DecorBanners == nil, "p5 fold " .. fx.name .. ": every old key removed")
		if fx.farm ~= nil or fx.name == "fresh home" then
			T.eq(st.Press1, fx.farm, "p5 fold " .. fx.name .. ": Berry Farm level")
		end
		if fx.magnet then
			T.check(h.LegacyMagnet == fx.magnet and h.LegacyMagnetStar == fx.stars and TC.LegacyMagnetLevel(h) == fx.magnet
				and TC.ScoopRadius(h) == TC.LegacyMagnet.Radius[fx.magnet],
				"p5 fold " .. fx.name .. ": LegacyMagnet " .. fx.magnet .. " at this Prestige (counts, keeps its radius)")
			local next_ = home(copyStations(h.Stations), fx.stars + 1, { LegacyMagnet = h.LegacyMagnet, LegacyMagnetStar = h.LegacyMagnetStar })
			T.check(TC.LegacyMagnetLevel(next_) == 0, "p5 fold " .. fx.name .. ": ...and stops counting after the next Prestige")
		end
		if fx.credit then
			T.check(h.DecorCredit == fx.credit and st.DecorFence == fx.fence and st.DecorFountain == fx.fountain and st.DecorPodium == 3,
				"p5 fold " .. fx.name .. ": Fence " .. fx.fence .. " / Fountain " .. fx.fountain .. " / DecorCredit " .. fx.credit,
				tostring(h.DecorCredit) .. " / " .. tostring(st.DecorFence) .. " / " .. tostring(st.DecorFountain))
		end
		-- idempotent: a second fold (after the marker) changes nothing
		local snapshot = copyStations(h.Stations)
		local again = TC.FoldLegacy(h, false)
		local same = true
		for k, v in pairs(snapshot) do
			if h.Stations[k] ~= v then
				same = false
			end
		end
		for k, v in pairs(h.Stations) do
			if snapshot[k] ~= v then
				same = false
			end
		end
		T.check(again == false and same, "p5 fold " .. fx.name .. ": idempotent (a second fold changes nothing)")
	end
	-- a Phase 4 server sold a Carrot Patch after the marker: its level is added, no food floor
	local h = home({ Garden = 3, Press1 = 13, Press2 = 1 }, 0)
	T.check(TC.FoldLegacy(h, false) == true and h.Stations.Press1 == 14 and h.Stations.Press2 == nil,
		"p5 fold: a Phase 4 Press2 sold after the marker folds into the farm (13 + 1 = 14, the farm level kept)", tostring(h.Stations.Press1))
	local h2 = home({ Garden = 3, Press1 = 13 }, 0)
	T.check(TC.FoldLegacy(h2, false) == false and h2.Stations.Press1 == 13, "p5 fold: after the marker a folded farm alone is left alone")
	local h3 = home({ Garden = 1, Press1 = 10, Press2 = 10, Press3 = 10, Press4 = 10 }, 0)
	TC.FoldLegacy(h3, true)
	T.eq(h3.Stations.Press1, 40, "p5 fold: four maxed plants = Farm 40 (food 2,132 = the old 2,132)")
	local h4 = home({ Garden = 1, DecorFence = 1 }, 0, { DecorCredit = 17 })
	h4.Stations.DecorFlowers = 3
	h4.Stations.DecorBanners = 3
	TC.FoldLegacy(h4, true)
	T.check(h4.DecorCredit == 18 and h4.Stations.DecorFence == 3, "p5 fold: DecorCredit adds up and stops at 18")
end)

----------------------------------------------------------------------------------------------------
-- p5home_roam_shared (economy+roam W1)
----------------------------------------------------------------------------------------------------
S.p5home_roam_shared = guarded("p5home_roam_shared", function()
	local TC = loadModule("shared/TycoonCatalog")
	local HR, err = loadModule("shared/HomeRoam")
	if not T.check(TC ~= nil and HR ~= nil, "p5 roam: HomeRoam and TycoonCatalog load", err) then
		return
	end
	local before = #game:GetDescendants()
	T.eq(HR.Version, 1, "p5 roam: HomeRoam.Version 1")
	T.check(HR.Cycle == 24 and HR.EatSeconds == 3 and HR.PoopSeconds == 1.5 and HR.MinSpeed == 4 and HR.MaxSpeed == 9 and HR.WalkBudget == 16.5,
		"p5 roam: Cycle 24, EatSeconds 3, PoopSeconds 1.5, speeds 4..9, WalkBudget 16.5")
	local nodes = HR.Build()
	T.check(type(nodes) == "number" and nodes >= 300, "p5 roam: the walk graph has >= 300 nodes", tostring(nodes))
	T.eq(HR.Build(), nodes, "p5 roam: Build() is lazy (a second call returns the same graph)")
	local copy, cerr = freshCopy("src/shared/HomeRoam.lua", "HomeRoam", { TycoonCatalog = TC })
	if not T.check(copy ~= nil and copy ~= HR, "p5 roam: a second copy of HomeRoam loads (its own graph and cache)", cerr) then
		return
	end
	T.eq(copy.Build(), nodes, "p5 roam: ...and builds the same graph")
	local layout = TC.RoamLayout()
	local blocked = layout.Blocked
	local function insideBlocked(x, z)
		for _, r in ipairs(blocked) do
			local p = (r.pad or 0) - 0.06 -- poop points are rounded to 0.1 stud: a path along an edge may touch it
			if x > r[1] - p and x < r[3] + p and z > r[2] - p and z < r[4] + p then
				return true
			end
		end
		return false
	end
	local same = T.tally("p5 roam: two copies give identical plans (3 seeds x 12 slots x 50 cycles)", 3)
	local plans = T.tally("p5 roam: every plan: speed 4..9, idle >= 1 s, PoopAt inside the cycle, the poop point inside the yard and off every Blocked rect", 3)
	local speeds = {}
	for _, seed in ipairs({ 101, 2024, 2147483646 }) do
		for slot = 1, 12 do
			for cycle = 0, 49 do
				local a, b = HR.Plan(seed, slot, cycle), copy.Plan(seed, slot, cycle)
				local eq = a and b and a.Poop.x == b.Poop.x and a.Poop.z == b.Poop.z and a.PoopAt == b.PoopAt and a.Speed == b.Speed
					and a.OutLen == b.OutLen and #a.Out == #b.Out
				same:case(eq, seed .. "/" .. slot .. "/" .. cycle)
				if a then
					speeds[#speeds + 1] = a.Speed
					local px, pz = a.Poop.x, a.Poop.z
					plans:case(a.Speed >= 4 and a.Speed <= 9 and a.Idle >= 1 and a.PoopAt > 3 and a.PoopAt < 24 and abs(px) <= 33 and abs(pz) <= 33
						and not insideBlocked(px, pz) and a.Poop[1] == px and a.Poop[2] == pz,
						seed .. "/" .. slot .. "/" .. cycle .. ": speed " .. a.Speed .. " idle " .. a.Idle .. " poop " .. px .. ", " .. pz)
				end
			end
		end
	end
	same:report()
	plans:report()
	table.sort(speeds)
	T.info("p5 roam: walk speeds p10 / median / p90", string.format("%.1f / %.1f / %.1f", speeds[floor(#speeds * 0.1) + 1], speeds[floor(#speeds * 0.5) + 1], speeds[floor(#speeds * 0.9) + 1]))
	-- order independence: a plan computed cold equals the one computed after many others
	local fresh2 = freshCopy("src/shared/HomeRoam.lua", "HomeRoam", { TycoonCatalog = TC })
	local p7 = fresh2 and fresh2.Plan(2024, 5, 37)
	local q7 = HR.Plan(2024, 5, 37)
	T.check(p7 and q7 and p7.Poop.x == q7.Poop.x and p7.Poop.z == q7.Poop.z and p7.PoopAt == q7.PoopAt,
		"p5 roam: a plan does not depend on what was computed before it")
	-- continuity: never faster than MaxSpeed between 0.05 s samples (cycle edges and the settle walk included)
	local cont = T.tally("p5 roam: continuity: <= MaxSpeed between 0.05 s samples over 3 cycles + the settle walk, every slot", 3)
	local states = {}
	for slot = 1, 12 do
		local epoch = 1000 + slot * 1.7
		local px, pz = nil, nil
		local worst = 0
		for k = 0, 1800 do
			local now = epoch - 15 + k * 0.05
			local x, z, state = HR.At(77, slot, epoch, now)
			states[state] = true
			if px then
				worst = max(worst, sqrt((x - px) ^ 2 + (z - pz) ^ 2) / 0.05)
			end
			px, pz = x, z
		end
		cont:case(worst <= HR.MaxSpeed + 1e-6, "slot " .. slot .. ": " .. string.format("%.2f", worst) .. " studs/s")
	end
	cont:report()
	T.check(states.Settle and states.Eat and states.Walk and states.Poop and states.Idle, "p5 roam: At walks through Settle, Eat, Walk, Poop and Idle",
		idList(states))
	-- At / PoopTime / EatPoint / BedPoint agree
	local agree = T.tally("p5 roam: At(PoopTime) = \"Poop\" at Plan.Poop; At(epoch + cycle x 24 + 1) = \"Eat\" at EatPoint; At(epoch - 60) = \"Settle\" on BedPoint", 3)
	for slot = 1, 12 do
		local epoch = 5000 + slot
		local ex, ez = HR.EatPoint(slot)
		local bx, bz = HR.BedPoint(slot)
		for cycle = 0, 5 do
			local pt = HR.PoopTime(77, slot, epoch, cycle)
			local p = HR.Plan(77, slot, cycle)
			local x, z, state = HR.At(77, slot, epoch, pt)
			agree:case(state == "Poop" and x == p.Poop.x and z == p.Poop.z, "poop " .. slot .. "/" .. cycle .. " " .. tostring(state))
			local x2, z2, s2 = HR.At(77, slot, epoch, epoch + cycle * 24 + 1)
			agree:case(s2 == "Eat" and abs(x2 - ex) < 1e-9 and abs(z2 - ez) < 1e-9, "eat " .. slot .. "/" .. cycle)
		end
		local x3, z3, s3 = HR.At(77, slot, epoch, epoch - 60)
		agree:case(s3 == "Settle" and x3 == bx and z3 == bz, "settle " .. slot)
		local a = math.rad((slot - 1) * 30)
		agree:case(abs(ex - (24 + math.cos(a) * 5)) < 1e-9 and abs(ez - (-1 + math.sin(a) * 5)) < 1e-9, "EatPoint " .. slot)
		local lb = layout.Beds[slot]
		agree:case(bx == lb[1] and bz == lb[2], "BedPoint " .. slot)
	end
	agree:report()
	-- the cache keeps the 3 newest cycles per (seed, slot)
	for cycle = 0, 9 do
		HR.Plan(4242, 3, cycle)
	end
	local cached = HR.CachedCycles(4242, 3)
	T.check(#cached == 3 and cached[1] == 7 and cached[3] == 9, "p5 roam: the plan cache keeps the 3 newest cycles per (seed, slot)",
		table.concat(cached, ", "))
	-- junk
	local okJ, e = pcall(function()
		assert(HR.Plan(1, 0, 0) == nil and HR.Plan(1, 13, 0) == nil and HR.Plan(1, 1.5, 0) == nil and HR.Plan(0 / 0, 1, 0) == nil
			and HR.Plan(1, 1, -1) == nil and HR.Plan("x", 1, 0) == nil)
		assert(HR.BedPoint(0) == nil and HR.EatPoint(13) == nil and HR.PoopTime(1, 1, 0 / 0, 0) == nil)
		local x, z, s = HR.At(1, 99, 0, 10)
		assert(type(x) == "number" and type(z) == "number" and s == "Settle")
		x, z, s = HR.At(1, 1, 0 / 0, 10)
		assert(s == "Settle")
	end)
	T.check(okJ, "p5 roam: junk arguments answer nil / Settle and never error", tostring(e))
	T.eq(#game:GetDescendants(), before, "p5 roam: HomeRoam is pure (no Instances created)")
end)

----------------------------------------------------------------------------------------------------
-- wave 2 (tycoon+care) - server scenarios on the booted game (TycoonService's Cloud Cash ledger, berries, signs)
----------------------------------------------------------------------------------------------------
local W2 = {} -- helpers of the booted-world scenarios (one table: this file is also loaded in the client world)

function W2.requireAt(key)
	local inst = K.moduleInstance(key)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

function W2.mods()
	return W2.requireAt("server/Services/TycoonService"), W2.requireAt("shared/TycoonCatalog"), W2.requireAt("shared/HomeRoam"),
		K.mod("DataService"), K.mod("SpotService"), W2.requireAt("server/Services/PetCareService")
end

W2.userSeq = 0
function W2.join(prefix, userId)
	W2.userSeq = W2.userSeq + 1
	local p = Mock.AddPlayer(prefix .. W2.userSeq, userId or (965200 + W2.userSeq))
	K.advance(1.0)
	return p
end

function W2.leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	K.advance(0.6)
end

function W2.spots()
	return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
end

function W2.freeIndex(skip)
	local SS = K.mod("SpotService")
	for i = 1, K.config().Lobby.SpotCount do
		if W2.spots()[i] and not SS.GetOwner(i) and i ~= skip then
			return i
		end
	end
	return nil
end

-- claims a free plot through TycoonService (the gate prompt is p2tycoon's business) and builds the free Garden
function W2.startHome(Ty, p, stations)
	local index = W2.freeIndex()
	local ok = Ty.Claim(p, index)
	if not ok then
		return nil
	end
	K.mod("DataService").MutateHome(p, function(h)
		h.Stations.Garden = 1
		for id, lv in pairs(stations or {}) do
			h.Stations[id] = lv
		end
		h.Level = W2.requireAt("shared/TycoonCatalog").HomeLevelOf(h)
	end)
	K.advance(1.2)
	return index, W2.spots()[index]
end

function W2.givePet(p, key, n)
	local DataS = K.mod("DataService")
	local ok = W2.requireAt("shared/PetKeys").Add(DataS.GetProfile(p), key, n or 1)
	DataS.MarkDirty(p)
	return ok
end

function W2.ecoPet()
	local PC = K.M["shared/PetCatalog"] or W2.requireAt("shared/PetCatalog")
	for _, rarity in ipairs({ "Common", "Uncommon", "Rare" }) do
		for _, def in ipairs(PC.Pets) do
			if def.Rarity == rarity and def.Role == "Economy" and not def.EventOnly then
				return def
			end
		end
	end
	return nil
end

function W2.entryOf(p, def)
	local DataS = K.mod("DataService")
	return { Def = def, Level = DataS.GetPetLevel(p, def.Id) or 1, Tier = "Normal", Stage = DataS.GetEvolution(p, def.Id) or 0, Key = def.Id }
end

function W2.bankOf(p)
	local home = K.mod("DataService").GetHome(p)
	return home and home.CollectorCash or 0
end

function W2.cashOf(p)
	return K.mod("DataService").GetCash(p)
end

function W2.standAt(p, pos)
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 0)))
end

function W2.away(p)
	Mock.Teleport(p, K.config().Lobby.Origin + Vector3.new(0, 4, 0))
end

function W2.now()
	return workspace:GetServerTimeNow()
end

function W2.seedOf(p)
	return (p.UserId % 2147483646) + 1
end

-- "1=1760001234.5;3=1760001240.0:N812" -> { [slot] = { Epoch, Nap } }
function W2.roamOf(info)
	local out = {}
	local text = info and info.Folder and info.Folder:GetAttribute("Roam") or ""
	for part in tostring(text):gmatch("[^;]+") do
		local slot, epoch, nap = part:match("^(%d+)=([%d%.]+):N(%d+)$")
		if not slot then
			slot, epoch = part:match("^(%d+)=([%d%.]+)$")
		end
		if slot then
			out[tonumber(slot)] = { Epoch = tonumber(epoch), Nap = nap and tonumber(nap) or nil }
		end
	end
	return out
end

function W2.dropsText(info)
	return info and info.Folder and info.Folder:GetAttribute("CoinDrops") or ""
end

function W2.liveSum(Ty, p)
	local total, poops = 0, 0
	for _, d in ipairs(Ty.Drops(p) or {}) do
		total = total + d.Value
		poops = poops + d.Poops
	end
	local piles = Ty.Piles(p)
	return total, poops, piles and piles.W and piles.W.Value or 0
end

function W2.poopWorld(HR, info, seed, slot, cycle)
	local plan = HR.Plan(seed, slot, cycle)
	if not plan or not plan.Poop then
		return nil
	end
	return info.PlotCFrame:PointToWorldSpace(Vector3.new(plan.Poop.x, 0, plan.Poop.z))
end

-- the number of poop times of (slot, epoch) at or before `now`
function W2.dueCount(HR, seed, slot, epoch, now)
	local n = 0
	while n < 1000 do
		local t = HR.PoopTime(seed, slot, epoch, n)
		if not t or t > now then
			break
		end
		n = n + 1
	end
	return n
end

-- [W2 tycoon+care] p5home_signs: the pad signs on a booted home (TycoonCatalog.SignedPads over TycoonService's pads)
S.p5home_signs = guarded("p5home_signs", function()
	if not K.needBoot() then
		return
	end
	local Ty, Cat, HR, DataS = W2.mods()
	if not Ty or not Cat or not HR then
		T.fail("p5 signs: TycoonService, TycoonCatalog and HomeRoam load")
		return
	end
	T.check(type(Cat.SignedPads) == "function" and type(Cat.SignRules) == "table" and Cat.SignRules.MaxSigns == 3, "p5 signs: TycoonCatalog.SignedPads + SignRules.MaxSigns 3")
	local p = W2.join("P5Sign")
	local index, info = W2.startHome(Ty, p, { Press1 = 1 })
	if not T.check(index ~= nil, "p5 signs: (precondition) a claimed home with the Garden and the Berry Farm") then
		W2.leave(p)
		return
	end
	local function signsAt(cash)
		local pads = Cat.AvailablePads(Ty.GetHome(p))
		return Cat.SignedPads(pads, cash, Cat.SignRules.MaxSigns), pads
	end
	local function count(set)
		local n = 0
		for _, v in pairs(set) do
			if v then
				n = n + 1
			end
		end
		return n
	end
	-- nothing affordable: the single cheapest pad is signed
	local signs, pads = signsAt(0)
	local cheapest, cheapestPrice = nil, math.huge
	for _, pad in ipairs(pads) do
		if not pad.Locked and pad.Price < cheapestPrice then
			cheapest, cheapestPrice = pad.StationId, pad.Price
		end
	end
	T.check(count(signs) == 1 and cheapest ~= nil and signs[cheapest] == true, "p5 signs: with $0 exactly the cheapest unlocked pad is signed (" .. tostring(cheapest) .. ")", idList(signs))
	-- rich: the 3 cheapest affordable, never a locked pad
	signs, pads = signsAt(1e9)
	local affordable = {}
	for _, pad in ipairs(pads) do
		if not pad.Locked then
			affordable[#affordable + 1] = pad
		end
	end
	table.sort(affordable, function(a, b)
		return a.Price < b.Price
	end)
	local okCheap = count(signs) == math.min(3, #affordable)
	for i = 1, math.min(3, #affordable) do
		if signs[affordable[i].StationId] ~= true then
			okCheap = false
		end
	end
	for _, pad in ipairs(pads) do
		if pad.Locked and signs[pad.StationId] then
			okCheap = false
		end
	end
	T.check(okCheap, "p5 signs: with plenty of Cash the 3 cheapest unlocked pads are signed, locked pads never", idList(signs))
	-- the server replicates what the client needs for the signs: the pads (HomeBuilder) and the Cash (DataService)
	local hb = W2.requireAt("server/Services/HomeBuilder")
	if hb and type(hb.GetPad) == "function" then
		local pad = hb.GetPad(info, affordable[1] and affordable[1].StationId or "Kitchen")
		T.check(pad ~= nil, "p5 signs: the cheapest pad stands on the plot (HomeBuilder.GetPad) for HomeFx's sign")
	else
		T.info("*p5 signs: HomeBuilder.GetPad missing (homeworld W2): pad presence not checked")
	end
	-- a prestige-ready home: the Prestige pad is signed first, then the cheapest affordable
	DataS.MutateHome(p, function(h)
		h.Stations = { Press1 = 15, Garden = 8, Kitchen = 5, Gym = 5, Vault = 5, House = 4 }
		h.Level = Cat.HomeLevelOf(h)
	end)
	K.advance(1.2)
	T.check(Cat.CanPrestige(Ty.GetHome(p)) == true, "p5 signs: (precondition) a prestige-ready home")
	signs, pads = signsAt(1e9)
	T.check(signs.Prestige == true and count(signs) <= 4, "p5 signs: the Prestige pad is signed when unlocked (plus the 3 cheapest affordable)", idList(signs))
	signs = signsAt(0)
	T.check(signs.Prestige == true, "p5 signs: ...even with $0")
	-- pure: no Instances, the same answer twice
	local before = #game:GetDescendants()
	local a1, a2 = idList(signsAt(1234)), idList(signsAt(1234))
	T.check(a1 == a2 and #game:GetDescendants() == before, "p5 signs: SignedPads is pure (deterministic, no Instances)")
	W2.leave(p)
	K.flushErrors("p5home_signs")
	K.flushWarnings("p5home_signs", { "HomeBuilder is missing" })
end)

-- [W2 tycoon+care] p5home_berries: berries from poops (Share, BasketCap), Feed with berries, the Berries attribute
S.p5home_berries = guarded("p5home_berries", function()
	if not K.needBoot() then
		return
	end
	local Ty, Cat, HR, DataS, SS, Care = W2.mods()
	if not Ty or not Cat or not HR or not Care then
		T.fail("p5 berries: TycoonService, TycoonCatalog, HomeRoam and PetCareService load")
		return
	end
	local B = Cat.Berries
	local Eco = W2.ecoPet()
	local Config = K.config()
	local attrName = Config.Attr.Berries or "Berries"
	local name, userId = "P5Berry", 965301
	local p = W2.join(name, userId)
	local index, info = W2.startHome(Ty, p, { Press1 = 2, Vault = 1 })
	if not T.check(index ~= nil and Eco ~= nil, "p5 berries: (precondition) a home with the Garden, a Berry Farm and a Vault; an Economy pet") then
		W2.leave(p)
		return
	end
	if DataS.GetBerries(p) > 0 then
		DataS.SpendBerries(p, DataS.GetBerries(p))
	end
	W2.givePet(p, Eco.Id, 3)
	W2.away(p)
	T.eq(info.Folder:GetAttribute("BerryCap"), B.BasketMin, "p5 berries: BerryCap = BasketMin " .. B.BasketMin .. " while nothing earns")

	-- poops grow value x Share berries (whole; the fraction stays in the server ledger)
	Ty.GardenSet(p, 1, Eco.Id)
	Ty.GardenSet(p, 2, Eco.Id)
	local attrWrites, syncs = 0, 0
	local conn = p:GetAttributeChangedSignal(attrName):Connect(function()
		attrWrites = attrWrites + 1
	end)
	local okExact = true
	local t0 = os.clock()
	for _ = 1, HR.SettleSeconds + 3 * HR.Cycle + 2 do
		K.advance(1)
		local bank = W2.bankOf(p)
		local want = math.floor(bank * B.Share + 1e-9)
		if DataS.GetBerries(p) ~= want then
			okExact = false
		end
	end
	local poops = select(2, W2.liveSum(Ty, p))
	T.check(poops >= 6, "p5 berries: (precondition) several poops landed (" .. poops .. ")")
	T.check(okExact and DataS.GetBerries(p) >= 1, "p5 berries: after every tick Berries == floor(the lawn's value x Share 0.25): whole berries, the fraction kept in the ledger (" .. DataS.GetBerries(p) .. ")")
	local elapsed = os.clock() - t0
	T.check(attrWrites <= 2 * elapsed + 2, "p5 berries: the Berries attribute is written <= 2 / s (" .. attrWrites .. " writes in " .. string.format("%.0f", elapsed) .. " s)")
	K.advance(0.6)
	T.eq(p:GetAttribute(attrName), DataS.GetBerries(p), "p5 berries: ...and it carries the whole berries (the trailing write lands)")
	local income = Ty.IncomePerSecond(p)
	T.eq(info.Folder:GetAttribute("BerryCap"), Cat.BasketCap(Ty.GetHome(p), income), "p5 berries: BerryCap follows BasketCap(home, income) (" .. tostring(info.Folder:GetAttribute("BerryCap")) .. ")")
	T.check(Cat.BasketCap(Ty.GetHome(p), income) == math.max(B.BasketMin, math.floor(income * B.Share * 60 * B.BasketMinutes)), "p5 berries: (catalog) BasketCap = max(BasketMin, income x Share x 30 min)")

	-- the basket cap: a poop never lifts Berries above the cap; 'Basket full!' once; a cap that drops removes none
	local cap = Cat.BasketCap(Ty.GetHome(p), income)
	DataS.AddBerries(p, cap - DataS.GetBerries(p) - 2)
	local mark = K.logSize()
	local bankAt = W2.bankOf(p)
	local waited = 0
	while W2.bankOf(p) <= bankAt + 1e-6 and waited < 2 * HR.Cycle + 5 do
		K.advance(1)
		waited = waited + 1
	end
	K.advance(1)
	T.check(W2.bankOf(p) > bankAt and DataS.GetBerries(p) == cap, "p5 berries: a poop that would overflow the basket is clamped at BasketCap (" .. cap .. ")", tostring(DataS.GetBerries(p)))
	T.check(K.notified(p, "Basket full! Feed your pets", nil, mark), "p5 berries: ...with the 'Basket full! Feed your pets' toast")
	local toastsAt = #K.remotesFor("Notify", p.UserId, mark)
	K.advance(HR.Cycle + 2)
	T.check(DataS.GetBerries(p) == cap and #K.remotesFor("Notify", p.UserId, mark) == toastsAt and W2.bankOf(p) > bankAt, "p5 berries: the coins never stop at a full basket; the toast is not repeated")
	DataS.AddBerries(p, 5000) -- a dev grant / an offline payout above the cap
	local over = DataS.GetBerries(p)
	K.advance(HR.Cycle + 2)
	T.check(DataS.GetBerries(p) == over and over > cap, "p5 berries: a basket above its cap (the cap dropped below the berries) loses nothing; poops add nothing")
	conn:Disconnect()

	-- a Berries-only change sends no ProfileSync (C14)
	Ty.GardenSet(p, 1, nil)
	Ty.GardenSet(p, 2, nil)
	K.advance(1.5)
	mark = K.logSize()
	T.eq(DataS.AddBerries(p, 10), true, "p5 berries: AddBerries(10)")
	K.advance(1.0)
	T.eq(#K.remotesFor("ProfileSync", p.UserId, mark), 0, "p5 berries: ...a Berries-only change sends no ProfileSync (the attribute is the fast path)")

	-- Feed: FeedBerries(def, level) berries -> FeedXp(level, machineLevel) XP; no Food path; refusals; one feed; refunds
	DataS.MutateHome(p, function(h)
		h.Stations.Kitchen = 1
		h.Level = Cat.HomeLevelOf(h)
	end)
	K.advance(1.2)
	local lv = DataS.GetPetLevel(p, Eco.Id)
	local cost, xpWant = Cat.FeedBerries(Eco, lv), Cat.FeedXp(lv, 1)
	local b0, c0 = DataS.GetBerries(p), W2.cashOf(p)
	local x0 = select(2, DataS.GetPetLevel(p, Eco.Id))
	local okFeed, res = Care.Feed(p, Eco.Id)
	local lv1, x1 = DataS.GetPetLevel(p, Eco.Id)
	T.check(okFeed == true and type(res) == "table" and res.Xp == xpWant and res.Berries == b0 - cost and DataS.GetBerries(p) == b0 - cost and W2.cashOf(p) == c0
		and (lv1 > lv or x1 == x0 + xpWant) and res.Level == lv1 and res.Cap == 100 and res.Levels == lv1 - lv,
		"p5 berries: Feed spends FeedBerries " .. cost .. " and grants FeedXp " .. xpWant .. "; answers { Xp, Levels, Level, Cap, Berries }; no Cash moves", tostring(res and res.Xp) .. " / " .. tostring(res and res.Berries))
	if type(DataS.AddFood) == "function" and type(DataS.GetFood) == "function" then
		DataS.AddFood(p, "Feast", 1) -- a leftover a Phase 4 server wrote after the fold: care ignores it
		b0 = DataS.GetBerries(p)
		local lvF = DataS.GetPetLevel(p, Eco.Id)
		local okF2 = Care.Feed(p, Eco.Id)
		T.check(okF2 == true and DataS.GetBerries(p) == b0 - Cat.FeedBerries(Eco, lvF) and DataS.GetFood(p, "Feast") == 1,
			"p5 berries: no Food path: a stray Feast is never eaten, the feed takes berries (the old foods were converted once by P5Home)")
		DataS.SpendFood(p, "Feast", 1)
	end
	local lvN = DataS.GetPetLevel(p, Eco.Id)
	b0 = DataS.GetBerries(p)
	local okC, resC = Care.Feed(p, Eco.Id, { Count = 5 })
	T.check(okC == true and b0 - DataS.GetBerries(p) == Cat.FeedBerries(Eco, lvN) and resC.Xp == Cat.FeedXp(lvN, 1), "p5 berries: { Count = 5 } (an old client) = exactly one feed")
	-- refusals in the contract's order, nothing moves
	local other = nil
	for _, def in ipairs((K.M["shared/PetCatalog"] or W2.requireAt("shared/PetCatalog")).Pets) do
		if def.Id ~= Eco.Id and not def.EventOnly then
			other = def
			break
		end
	end
	b0 = DataS.GetBerries(p)
	local okO, whyO = Care.Feed(p, other.Id)
	T.check(okO == false and whyO == "You do not own that pet" and DataS.GetBerries(p) == b0, "p5 berries: refusal: not owned", tostring(whyO))
	DataS.SetPetLevel(p, Eco.Id, 100)
	local okCap, whyCap = Care.Feed(p, Eco.Id)
	T.check(okCap == false and tostring(whyCap):find("max level", 1, true) ~= nil and DataS.GetBerries(p) == b0, "p5 berries: refusal: at the cap", tostring(whyCap))
	DataS.SetPetLevel(p, Eco.Id, 10)
	local BS = W2.requireAt("server/Services/BattleService")
	if BS then
		local had = BS.KeysInBattle
		BS.KeysInBattle = function(pl)
			return pl == p and { [Eco.Id] = true } or {}
		end
		local okB, whyB = Care.Feed(p, Eco.Id)
		BS.KeysInBattle = had
		T.check(okB == false and whyB == "Finish your battle first" and DataS.GetBerries(p) == b0, "p5 berries: refusal: a key in a running battle", tostring(whyB))
	end
	DataS.MutateHome(p, function(h)
		h.Stations.Kitchen = nil
		h.Level = Cat.HomeLevelOf(h)
	end)
	local okM, whyM = Care.Feed(p, Eco.Id)
	T.check(okM == false and whyM == "Build the Food Machine at home first" and DataS.GetBerries(p) == b0, "p5 berries: refusal: no Food Machine", tostring(whyM))
	DataS.MutateHome(p, function(h)
		h.Stations.Kitchen = 1
		h.Level = Cat.HomeLevelOf(h)
	end)
	DataS.SpendBerries(p, DataS.GetBerries(p))
	local need = Cat.FeedBerries(Eco, 10)
	local okS, whyS = Care.Feed(p, Eco.Id)
	T.check(okS == false and whyS == "Not enough berries: a feed needs " .. need .. " (you have 0). Your garden pets grow more!" and DataS.GetBerries(p) == 0,
		"p5 berries: refusal: not enough berries (the toast names the need and the balance)", tostring(whyS))
	DataS.AddBerries(p, need * 10)
	-- an XP write of 0 refunds the berries in the same step
	local realAdd = DataS.AddPetXp
	DataS.AddPetXp = function()
		return 0
	end
	b0 = DataS.GetBerries(p)
	local okR = Care.Feed(p, Eco.Id)
	DataS.AddPetXp = realAdd
	T.check(okR == false and DataS.GetBerries(p) == b0, "p5 berries: an XP write of 0 refunds the berries")
	-- provisional: refused
	local DSt = Mock.DataStore
	DSt.Fail = true
	local v = W2.join("P5BerryOutage")
	K.advance(3)
	if T.check(DataS.IsProvisional(v) == true, "p5 berries: (precondition) an outage makes a newcomer provisional") then
		local okP, whyP = Care.Feed(v, Eco.Id)
		T.check(okP == false and tostring(whyP):find("still loading", 1, true) ~= nil, "p5 berries: a provisional save cannot feed ('Your save is still loading...')", tostring(whyP))
	end
	DSt.Fail = false
	W2.leave(v)

	-- offline berries: offline coins x Share into the basket ONCE, the cap ignored, in the LastSeen step
	Ty.GardenSet(p, 1, Eco.Id)
	Ty.GardenSet(p, 2, Eco.Id)
	K.advance(2)
	local homeBefore = Ty.GetHome(p)
	income = Ty.IncomePerSecond(p)
	DataS.AddBerries(p, 100000) -- far above the cap
	local storeKey = Config.Tokens.DataStoreName .. "/u_" .. userId
	W2.leave(p)
	K.advance(1)
	local rec = Mock.DataStore.Data[storeKey]
	if T.check(rec ~= nil and type(rec.Home) == "table", "p5 berries: (precondition) the leave save") then
		local awayFor = 3 * 3600
		rec.Home.LastSeen = os.time() - awayFor
		local want = Cat.OfflineEarnings(homeBefore, awayFor, income)
		local storedBerries = rec.Berries or 0
		local storedBank = rec.Home.CollectorCash or 0
		p = W2.join(name, userId)
		K.advance(4)
		local wantBerries = math.floor(math.floor(want) * B.Share)
		T.check(want > 0 and wantBerries >= 1 and DataS.GetBerries(p) == storedBerries + wantBerries and math.abs(W2.bankOf(p) - (storedBank + math.floor(want))) < 1,
			"p5 berries: offline coins add offline x Share berries (" .. wantBerries .. ") with the bank, the cap ignored", tostring(DataS.GetBerries(p) - storedBerries))
		K.advance(10)
		T.eq(DataS.GetBerries(p), storedBerries + wantBerries, "p5 berries: ...once (LastSeen moved on in the same step)")
	end
	W2.leave(p)
	K.flushErrors("p5home_berries")
	K.flushWarnings("p5home_berries", { "HomeBuilder is missing", "[DataService]" })
end)

-- [W2 tycoon+care] p5home_roam_server: the roaming ledger (epochs, drops == Plan, CoinDrops, naps, scoops, invariant)
S.p5home_roam_server = guarded("p5home_roam_server", function()
	if not K.needBoot() then
		return
	end
	local Ty, Cat, HR, DataS, SS = W2.mods()
	if not Ty or not Cat or not HR then
		T.fail("p5 roam server: TycoonService, TycoonCatalog and HomeRoam load")
		return
	end
	local Eco = W2.ecoPet()
	local p = W2.join("P5Roam")
	local seed = W2.seedOf(p)
	local index, info = W2.startHome(Ty, p)
	if not T.check(index ~= nil and Eco ~= nil, "p5 roam server: (precondition) a home with the Garden; an Economy pet") then
		W2.leave(p)
		return
	end
	T.eq(info.Folder:GetAttribute("RoamSeed"), seed, "p5 roam server: RoamSeed = (UserId % 2147483646) + 1")
	T.eq(info.Folder:GetAttribute("RoamVersion"), HR.Version, "p5 roam server: RoamVersion = HomeRoam.Version")
	T.eq(info.Folder:GetAttribute("CoinPiles"), nil, "p5 roam server: no CoinPiles attribute")
	W2.givePet(p, Eco.Id, 12)
	DataS.MutateHome(p, function(h)
		h.LegacySlots = 12 -- every bed open: 12 roaming pets
	end)
	K.advance(1.2)
	T.eq(Cat.GardenSlots(Ty.GetHome(p)), 12, "p5 roam server: (precondition) 12 open places (LegacySlots)")
	W2.away(p)
	local placedAt = W2.now()
	for slot = 1, 12 do
		Ty.GardenSet(p, slot, Eco.Id)
	end
	local roam = W2.roamOf(info)
	local okEpoch = true
	for slot = 1, 12 do
		local r = roam[slot]
		if not r or math.abs(r.Epoch - (placedAt + HR.SettleSeconds)) > 0.11 or r.Nap ~= nil or math.floor(r.Epoch * 10 + 0.5) / 10 ~= r.Epoch then
			okEpoch = false
		end
	end
	T.check(okEpoch, "p5 roam server: every placed slot gets Epoch = now + SettleSeconds 20, rounded to 0.1 s, in Roam", tostring(info.Folder:GetAttribute("Roam")))
	local firstPoop = math.huge
	for slot = 1, 12 do
		firstPoop = math.min(firstPoop, HR.PoopTime(seed, slot, roam[slot].Epoch, 0))
	end
	T.check(firstPoop - placedAt >= HR.Cycle - 1e-6, "p5 roam server: the first poop of every slot comes >= 24 s after the placement (" .. string.format("%.1f", firstPoop - placedAt) .. " s)")
	local poopValue = Cat.CoinValue(Ty.GetHome(p), Cat.PetPower(W2.entryOf(p, Eco)), 0) * Cat.Coins.PoopMeals

	-- 4 cycles, checked every second: the invariant, every drop at its plan point, poops == due poops (<= one tick late),
	-- at most 3 drops per slot, the CoinDrops format and rate, the byte budget
	local okInv, okPoints, okDue, okMax, okFormat = true, true, true, true, true
	local writes, lastText, maxBytes = 0, W2.dropsText(info), 0
	local dropConn = info.Folder:GetAttributeChangedSignal("CoinDrops"):Connect(function()
		writes = writes + 1
	end)
	local seconds = HR.SettleSeconds + 4 * HR.Cycle + 2
	for _ = 1, seconds do
		K.advance(1)
		local live, _, welcome = W2.liveSum(Ty, p)
		if math.abs(live + welcome - W2.bankOf(p)) > 1e-6 then
			okInv = false
		end
		local perSlot = {}
		for _, d in ipairs(Ty.Drops(p) or {}) do
			local at = W2.poopWorld(HR, info, seed, d.Slot, d.Cycle)
			if not at or (at - d.Position).Magnitude > 1e-3 then
				okPoints = false
			end
			if d.Poops >= 1 then
				perSlot[d.Slot] = (perSlot[d.Slot] or 0) + 1
			end
		end
		for slot, n in pairs(perSlot) do
			if n > Cat.Coins.DropsPerPet then
				okMax = false
			end
		end
		local piles = Ty.Piles(p)
		local now = W2.now()
		for slot = 1, 12 do
			local due = W2.dueCount(HR, seed, slot, roam[slot].Epoch, now)
			local have = piles[slot] and piles[slot].Coins or 0
			if have ~= due and have ~= due - 1 then
				okDue = false
			end
		end
		local text = W2.dropsText(info)
		if text ~= "" and not text:match("^%d+=%d+:%d%*?[%d:,%*]*[;%d=:,%*W]*$") then
			okFormat = false
		end
		maxBytes = math.max(maxBytes, #text)
	end
	dropConn:Disconnect()
	T.check(okInv, "p5 roam server: sum(drops) + Welcome == CollectorCash after every tick")
	T.check(okPoints, "p5 roam server: every drop lies at HomeRoam.Plan(seed, slot, cycle).Poop in the plot frame")
	T.check(okDue, "p5 roam server: every slot's poop count equals its due PoopTime count (at most one tick late)")
	T.check(okMax, "p5 roam server: a slot never holds more than DropsPerPet 3 drops (the 4th poop merges into the nearest)")
	local merged = 0
	for _, d in ipairs(Ty.Drops(p) or {}) do
		if d.Poops >= 2 then
			merged = merged + 1
		end
	end
	T.check(merged >= 12, "p5 roam server: after 4 poops per slot every slot has a merged drop (" .. merged .. ")")
	T.check(okFormat, "p5 roam server: CoinDrops reads 'slot=cycle:stage[*],...;...' throughout", W2.dropsText(info))
	T.check(writes <= 0.5 * seconds + 2, "p5 roam server: CoinDrops is written <= 0.5 / s (" .. writes .. " writes in " .. seconds .. " s)")
	T.check(maxBytes <= 400, "p5 roam server: CoinDrops stays <= 400 bytes with 12 pets (" .. maxBytes .. ")")
	-- stages by poops: 1 poop -> 1, 2-3 -> 2, 4-7 -> 3
	local okStage = true
	for _, d in ipairs(Ty.Drops(p) or {}) do
		local want = (d.Poops >= 8 and 4) or (d.Poops >= 4 and 3) or (d.Poops >= 2 and 2) or (d.Poops >= 1 and 1) or 0
		if d.Stage ~= want then
			okStage = false
		end
	end
	T.check(okStage, "p5 roam server: a drop's stage follows Coins.DropStages {1, 2, 4, 8} by its poops")

	-- owner scoop within the Garden L1 radius 8, a visitor never
	local radius = Cat.ScoopRadius(Ty.GetHome(p))
	T.eq(radius, 8, "p5 roam server: ScoopRadius at Garden L1 = 8")
	local target = (Ty.Drops(p) or {})[1]
	local visitor = W2.join("P5RoamVisitor")
	local vCash, bank0 = W2.cashOf(visitor), W2.bankOf(p)
	W2.standAt(visitor, target.Position)
	K.advance(1.0)
	T.check(W2.cashOf(visitor) == vCash and W2.bankOf(p) >= bank0 - 1e-6, "p5 roam server: a visitor standing on a drop scoops nothing")
	W2.leave(visitor)
	local want = 0
	for _, d in ipairs(Ty.Drops(p) or {}) do
		if K.planar(d.Position, target.Position) <= radius then
			want = want + d.Value
		end
	end
	local cash0 = W2.cashOf(p)
	W2.standAt(p, target.Position)
	K.advance(0.4)
	T.eq(W2.cashOf(p) - cash0, math.floor(want + 1e-6), "p5 roam server: the owner scoops every drop within 8 studs, whole Cash (" .. math.floor(want) .. ")")
	local live, _, welcome = W2.liveSum(Ty, p)
	T.check(math.abs(live + welcome - W2.bankOf(p)) <= 1e-6, "p5 roam server: ...the invariant holds after the scoop")
	W2.away(p)

	-- churn: remove + re-place within a cycle keeps the epoch (and its poop count); after a cycle a new epoch
	local e3 = W2.roamOf(info)[3].Epoch
	local poops3 = Ty.Piles(p)[3] and Ty.Piles(p)[3].Coins or 0
	Ty.GardenSet(p, 3, nil)
	K.advance(5)
	Ty.GardenSet(p, 3, Eco.Id)
	T.check(math.abs(W2.roamOf(info)[3].Epoch - e3) < 1e-6, "p5 roam server: the same key back within one cycle keeps its epoch (Y8)")
	K.advance(HR.Cycle + 1)
	T.check((Ty.Piles(p)[3] and Ty.Piles(p)[3].Coins or 0) <= poops3 + 2, "p5 roam server: ...and no extra poop came from the churn")
	Ty.GardenSet(p, 3, nil)
	K.advance(HR.Cycle + 1)
	local t3 = W2.now()
	Ty.GardenSet(p, 3, Eco.Id)
	T.check(math.abs(W2.roamOf(info)[3].Epoch - (t3 + HR.SettleSeconds)) <= 0.11, "p5 roam server: a placement after more than a cycle away gets a new epoch (now + 20)")

	-- nap at the cap, wake by a scoop: one pet alone (the cap = PileSeconds of its coins)
	for slot = 2, 12 do
		Ty.GardenSet(p, slot, nil)
	end
	Ty.ClearCoins(p)
	K.advance(1.2)
	local home = Ty.GetHome(p)
	local cap = Cat.PileSeconds(home) * Cat.CoinValue(home, Cat.PetPower(W2.entryOf(p, Eco)), 0) / Cat.Coins.MealSeconds * Cat.LuckyEV(home)
	local waited = 0
	while waited < Cat.PileSeconds(home) + 4 * HR.Cycle do
		local r1 = W2.roamOf(info)[1]
		if r1 and r1.Nap then
			break
		end
		K.advance(1)
		waited = waited + 1
	end
	local r1 = W2.roamOf(info)[1]
	local lawn = Ty.Piles(p)[1] and Ty.Piles(p)[1].Value or 0
	T.check(r1 and r1.Nap ~= nil and lawn >= cap - 1e-6 and lawn <= cap + poopValue * Cat.Coins.LuckyMult + 1e-6, "p5 roam server: at PileSeconds x its coin rate the slot naps (':N<cycle>' in Roam)",
		tostring(info.Folder:GetAttribute("Roam")) .. " lawn " .. string.format("%.1f of %.1f", lawn, cap))
	T.check(Ty.Piles(p)[1] and Ty.Piles(p)[1].Full == true, "p5 roam server: ...Piles[slot].Full says so")
	local bankNap = W2.bankOf(p)
	K.advance(2 * HR.Cycle)
	T.check(math.abs(W2.bankOf(p) - bankNap) <= 1e-6, "p5 roam server: a napping pet poops nothing")
	local napPlan = HR.Plan(seed, 1, r1.Nap)
	local backWalk = napPlan.OutLen / napPlan.Speed
	local d1 = nil
	for _, d in ipairs(Ty.Drops(p) or {}) do
		if d.Slot == 1 and d.Poops >= 1 then
			d1 = d
			break
		end
	end
	local wakeAt = W2.now()
	W2.standAt(p, d1.Position)
	K.advance(0.3)
	local r1b = W2.roamOf(info)[1]
	T.check(r1b and r1b.Nap == nil and math.abs(r1b.Epoch - (wakeAt + backWalk)) <= 0.5, "p5 roam server: a scoop below the cap wakes the pet: Epoch = now + the back walk (" .. string.format("%.1f", backWalk) .. " s)",
		tostring(info.Folder:GetAttribute("Roam")) .. " vs " .. string.format("%.1f", wakeAt + backWalk))
	W2.away(p)
	local poopsNow = Ty.Piles(p)[1] and Ty.Piles(p)[1].Coins or 0
	K.advance(backWalk + HR.Cycle + 2)
	T.check((Ty.Piles(p)[1] and Ty.Piles(p)[1].Coins or 0) > poopsNow, "p5 roam server: ...and it poops again from its new epoch")

	-- a rebase moves everything to the Welcome pile once; a scoop pays it once
	local liveBefore = W2.liveSum(Ty, p)
	T.check(liveBefore > 0, "p5 roam server: (precondition) drops before the rebase")
	DataS.ProfileRebased:Fire(p, DataS.GetProfile(p))
	K.advance(0.3)
	local piles = Ty.Piles(p)
	T.check(piles.W and math.abs(piles.W.Value - W2.bankOf(p)) <= 1e-6 and #(Ty.Drops(p) or {}) == 0 and W2.dropsText(info):find("W=5", 1, true) ~= nil,
		"p5 roam server: ProfileRebased rebuilds the ledger: the whole bank waits in the Welcome pile (CoinDrops 'W=5')", W2.dropsText(info))
	cash0 = W2.cashOf(p)
	local wantW = math.floor(piles.W.Value + 1e-6)
	W2.standAt(p, piles.W.Pos)
	K.advance(0.4)
	T.eq(W2.cashOf(p) - cash0, wantW, "p5 roam server: ...scooped once")
	K.advance(1.0)
	T.eq(W2.cashOf(p) - cash0, wantW, "p5 roam server: ...and never twice")
	W2.away(p)
	W2.leave(p)
	K.flushErrors("p5home_roam_server")
	K.flushWarnings("p5home_roam_server", { "HomeBuilder is missing", "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- wave 3 (homefx+pets) - client scenarios
----------------------------------------------------------------------------------------------------
if CONTEXT == "client" then
	local KC = _G.KC
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer

	local function req(path)
		local inst = Mock.GetPath(ROOTS[string.match(path, "^(%a+)/")] .. "/" .. string.match(path, "^%a+/(.+)$"))
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	local function partsUnder(root)
		local n = 0
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				n = n + 1
			end
		end
		return n
	end

	-- a client test world: the local player's home (and optionally a neighbour's) with 12 roaming pets, the camera
	-- and the character next to the Garden; every epoch / drop is written by the test (fixed seeds, the mock clock)
	local C = {}
	function C.setup(tag, x, opts)
		opts = opts or {}
		local HF = KC.M.HomeFx or req("client/Controllers/HomeFx")
		local HB = req("server/Services/HomeBuilder")
		local TC = req("shared/TycoonCatalog")
		local PC = req("shared/PetCatalog")
		local HR = req("shared/HomeRoam")
		if not (HF and HB and TC and PC and HR and type(HF.Garden) == "function") then
			T.fail("p5 home client: HomeFx / HomeBuilder / TycoonCatalog / PetCatalog / HomeRoam load in the client world")
			return nil
		end
		HF.Init()
		local ids = {}
		for _, d in ipairs(PC.Pets) do
			if not d.EventOnly and #ids < 12 then
				ids[#ids + 1] = d.Id
			end
		end
		local root = Instance.new("Folder")
		root.Name = "SmokeP5Home" .. tag
		root.Parent = workspace
		local neighbour = nil
		if opts.Neighbour then
			neighbour = Mock.AddPlayer("RoamNeighbour" .. tag, 7700 + #tag, { character = false })
		end
		local base = CFrame.new(x, 300, -9000)
		local function makeSpot(index, cf, owner)
			local f = Instance.new("Folder")
			f.Name = string.format("Spot_%02d", index)
			f.Parent = root
			local spot = { Index = index, PlotCFrame = cf, PlotSize = TC.PlotSize, Center = cf.Position, Folder = f }
			HB.PreparePlot(spot)
			HB.SetOwner(spot, owner)
			HB.BuildHome(spot, { Stations = opts.Stations or { Press1 = 12, Garden = 8, Kitchen = 1, Gym = 1, House = 1 }, Prestige = 9 })
			HB.SetGarden(spot, {}, 12)
			f:SetAttribute("GardenSlots", 12)
			return spot
		end
		local mine = makeSpot(81, base, LocalPlayer)
		local theirs = neighbour and makeSpot(82, base * CFrame.new(80, 0, 0), neighbour) or nil
		local character = LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local saved = { Hrp = hrp and hrp.CFrame, Anchored = hrp and hrp.Anchored, Cam = workspace.CurrentCamera and workspace.CurrentCamera.CFrame }
		if hrp then
			hrp.Anchored = true
		end
		local ctx = { HF = HF, HB = HB, TC = TC, HR = HR, Ids = ids, Mine = mine, Theirs = theirs, Neighbour = neighbour, Hrp = hrp, Base = base }
		function ctx.seedOf(uid)
			return (uid % 2147483646) + 1
		end
		-- the roam of one plot: every slot's epoch is now - offset[slot] (one decimal, like the server)
		function ctx.roam(spot, uid, offsets, naps, version)
			local now = workspace:GetServerTimeNow()
			local parts, epochs = {}, {}
			for slot = 1, 12 do
				local off = offsets[slot]
				if off then
					local e = math.floor((now - off) * 10 + 0.5) / 10
					epochs[slot] = e
					parts[#parts + 1] = string.format("%d=%.1f", slot, e) .. ((naps and naps[slot]) and (":N" .. naps[slot]) or "")
				end
			end
			spot.Folder:SetAttribute("RoamSeed", ctx.seedOf(uid))
			spot.Folder:SetAttribute("RoamVersion", version or HR.Version)
			spot.Folder:SetAttribute("Roam", table.concat(parts, ";"))
			return epochs
		end
		function ctx.pets(spot, n, infoStage)
			local list, info, valid = {}, {}, {}
			for i = 1, n do
				local key = ids[((i - 1) % #ids) + 1]
				valid[i] = key
				list[#list + 1] = i .. "=" .. key
				info[#info + 1] = i .. "=5:" .. tostring((infoStage and infoStage[i]) or 0)
			end
			HB.SetGarden(spot, valid, 12)
			spot.Folder:SetAttribute("GardenPets", table.concat(list, ";"))
			spot.Folder:SetAttribute("GardenInfo", table.concat(info, ";"))
		end
		function ctx.standAt(pos)
			if hrp then
				hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
			end
			local cam = workspace.CurrentCamera
			if cam then
				cam.CFrame = CFrame.lookAt(pos + Vector3.new(0, 18, -26), pos)
			end
		end
		function ctx.g(spot)
			return HF.Garden((spot or mine).Folder) or { Heaps = {}, Coins = {}, Pets = {}, Training = {} }
		end
		local function cleanup()
			if hrp and saved.Hrp then
				hrp.CFrame = saved.Hrp
				hrp.Anchored = saved.Anchored
			end
			if workspace.CurrentCamera and saved.Cam then
				workspace.CurrentCamera.CFrame = saved.Cam
			end
			LocalPlayer:SetAttribute("Cash", nil)
			LocalPlayer:SetAttribute("Berries", nil)
			root:Destroy()
			if neighbour then
				Mock.RemovePlayer(neighbour)
			end
			KC.advance(0.5)
		end
		ctx.standAt(mine.PlotCFrame * TC.Get("Garden").Slot.CFrame.Position)
		KC.advance(0.3)
		return ctx, cleanup
	end

	-- the cycle time t (0..24) of `slot` whose epoch makes it stand at t now
	local function flatDist(a, b)
		return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	end

	-- [W3 homefx+pets] client_p5home_roam: poses == HomeRoam.At, coins pending / confirmed, budgets, RoamVersion
	S.client_p5home_roam = guarded("client_p5home_roam", function()
		local ctx, cleanup = C.setup("roam", 9000, { Neighbour = true })
		if not ctx then
			return
		end
		local HF, HR, TC = ctx.HF, ctx.HR, ctx.TC
		local mine, theirs = ctx.Mine, ctx.Theirs
		local uid = LocalPlayer.UserId
		local seed = ctx.seedOf(uid)
		local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
		ctx.pets(mine, 12, { [3] = 1 })
		-- slot 1 eats (1 s into its cycle), slot 2 is 0.3 s before its poop, the rest spread over the cycle
		local poopAt2 = HR.Plan(seed, 2, 5).PoopAt
		local poopAt4 = HR.Plan(seed, 4, 5).PoopAt
		local offsets = { [1] = 5 * 24 + 1.0, [2] = 5 * 24 + poopAt2 - 0.3, [4] = 5 * 24 + poopAt4 - 0.3 }
		for slot = 1, 12 do
			offsets[slot] = offsets[slot] or (5 * 24 + (slot * 1.9) % 24)
		end
		local epochs = ctx.roam(mine, uid, offsets)
		mine.Folder:SetAttribute("CoinDrops", "")
		for _ = 1, 20 do
			KC.advance(0.05)
		end
		local g = ctx.g()
		local placed, near, worst, worstSlot = 0, 0, 0, nil
		local plot = mine.PlotCFrame
		local now = workspace:GetServerTimeNow()
		for slot = 1, 12 do
			local p = g.Pets[slot]
			if p and p.Model and p.Model.Parent then
				placed = placed + 1
				local x, z = HR.At(seed, slot, epochs[slot], now)
				local lp = plot:PointToObjectSpace(p.Model:GetPivot().Position)
				local ex, ez = x + p.SepX, z + p.SepZ
				local slack = (p.State == "Eat") and (p.Hw or 1) + 0.05 or 0
				local d = math.sqrt((lp.X - ex) ^ 2 + (lp.Z - ez) ^ 2) - slack
				if d > worst then
					worst, worstSlot = d, slot
				end
				if math.abs(p.SepX) + math.abs(p.SepZ) <= 1.5 * 1.42 then
					near = near + 1
				end
			end
		end
		T.eq(placed, 12, "p5 roam client: 12 garden pets roam the own home (GardenPets, RoamSeed, Roam)")
		T.check(worst <= 0.5, "p5 roam client: every pet stands within 0.5 stud of HomeRoam.At (+ its soft separation <= 1.5)", string.format("worst %.2f (slot %s)", worst, tostring(worstSlot)))
		T.eq(near, placed, "p5 roam client: ...the separation never pushes more than 1.5 studs")
		-- eating at the bowl
		local e1 = g.Pets[1]
		local bowl = TC.RoamLayout().Bowl
		local lp1 = plot:PointToObjectSpace(e1.Model:GetPivot().Position)
		local bd = math.sqrt((lp1.X - bowl.X) ^ 2 + (lp1.Z - bowl.Z) ^ 2)
		T.check(e1.State == "Eat" and bd >= 4.5 and bd <= 5 + (e1.Hw or 1) + 1.6, "p5 roam client: slot 1 eats at the Food Bowl (eat ring 5 + half its width out)", string.format("%s %.2f", tostring(e1.State), bd))
		-- evolved own pet (GardenInfo stage 1 -> PB_Evolved 1, Low)
		local e3 = g.Pets[3]
		T.check(e3 and e3.Model:GetAttribute("PB_Evolved") == 1 and e3.Model:GetAttribute("PB_Detail") == "Low", "p5 roam client: an evolved garden pet is built evolved at Low (3.7)",
			e3 and tostring(e3.Model:GetAttribute("PB_Evolved")) or "no pet")
		-- the pending coin of slot 2's poop: arcs, then CoinDrops confirms it
		local st0 = HF.Stats()
		for _ = 1, 8 do
			KC.advance(0.05)
		end
		g = ctx.g()
		local c2 = g.Coins["2:5"]
		T.check(c2 ~= nil and c2.Pending == true, "p5 roam client: slot 2 crossed PoopAt -> a pending Cloud Cash coin '2:5'", c2 and tostring(c2.Pending) or "none")
		local want2 = mine.PlotCFrame:PointToWorldSpace(Vector3.new(HR.Plan(seed, 2, 5).Poop.x, 0, HR.Plan(seed, 2, 5).Poop.z))
		T.check(c2 and flatDist(c2.Point, want2) < 0.05 and c2.Look == "Cash1" and c2.Parts == 6, "p5 roam client: ...at Plan(seed, 2, 5).Poop, TokenLook Cash stage 1, 6 parts", c2 and c2.Look or "")
		T.check(g.Coins["4:5"] ~= nil, "p5 roam client: slot 4's poop pops its own pending coin too")
		mine.Folder:SetAttribute("CoinDrops", "2=5:1")
		KC.advance(0.1)
		g = ctx.g()
		c2 = g.Coins["2:5"]
		T.check(c2 and c2.Pending == false and HF.Stats().Confirmed > st0.Confirmed, "p5 roam client: CoinDrops '2=5:1' confirms the pending coin (same part, not pending)")
		-- the coin moves (bob / spin) for the owner
		local cfA = c2 and c2.Part.CFrame
		KC.advance(0.2)
		local cfB = c2 and c2.Part.CFrame
		T.check(cfA and cfB and (cfA.Position - cfB.Position).Magnitude > 1e-4 or (cfA and cfA.LookVector:Dot(cfB.LookVector) < 0.9999), "p5 roam client: the own coin bobs and spins (TokenLook.Motion)")
		-- slot 4's coin is never confirmed: it fades after 2.5 s
		for _ = 1, 32 do
			KC.advance(0.1)
		end
		g = ctx.g()
		T.check(g.Coins["4:5"] == nil and g.Coins["2:5"] ~= nil and HF.Stats().Faded > st0.Faded, "p5 roam client: an unconfirmed pending coin fades after 2.5 s; the confirmed one stays")
		-- a merged / Lucky drop changes its look in place
		mine.Folder:SetAttribute("CoinDrops", "2=5:3*")
		KC.advance(0.1)
		g = ctx.g()
		T.check(g.Coins["2:5"] and g.Coins["2:5"].Look == "GoldenCash3" and g.Coins["2:5"].Lucky, "p5 roam client: a merged Lucky drop '2=5:3*' becomes GoldenCash at stage 3", g.Coins["2:5"] and g.Coins["2:5"].Look or "")
		-- the scoop: zip + "+$" at the drop
		LocalPlayer:SetAttribute("Cash", 1000)
		mine.Folder:SetAttribute("CollectorCash", 120)
		KC.advance(0.1)
		local dropPt = g.Coins["2:5"].Point
		ctx.standAt(dropPt)
		KC.advance(0.1)
		local zips, labels = HF.Stats().Zips, HF.Stats().Labels
		mine.Folder:SetAttribute("CoinDrops", "")
		mine.Folder:SetAttribute("CollectorCash", 20)
		LocalPlayer:SetAttribute("Cash", 1100)
		KC.advance(0.1)
		local st = HF.Stats()
		T.check(st.Zips == zips + 1 and st.Labels == labels + 1 and st.LastLabel == "+$100", "p5 roam client: the scoop zips the coin to the owner and floats '+$100'", tostring(st.LastLabel))
		T.check(st.LastLabelAt and flatDist(st.LastLabelAt, dropPt) < 1, "p5 roam client: ...the label at the drop, not over the player")
		g = ctx.g()
		T.check(g.Coins["2:5"] == nil, "p5 roam client: ...and the coin is gone")
		-- the neighbour's coins: dimmed and still
		ctx.pets(theirs, 12)
		local nuid = ctx.Neighbour.UserId
		local nseed = ctx.seedOf(nuid)
		local noff = {}
		for slot = 1, 12 do
			noff[slot] = 3 * 24 + slot
		end
		ctx.roam(theirs, nuid, noff)
		local drops = {}
		for slot = 1, 12 do
			drops[#drops + 1] = slot .. "=0:1,1:2,2:4"
		end
		theirs.Folder:SetAttribute("CoinDrops", table.concat(drops, ";") .. ";W=5")
		local mdrops = {}
		for slot = 1, 12 do
			mdrops[#mdrops + 1] = slot .. "=1:1"
		end
		mine.Folder:SetAttribute("CoinDrops", table.concat(mdrops, ";"))
		ctx.standAt(mine.PlotCFrame.Position + Vector3.new(40, 0, 0))
		for _ = 1, 30 do
			KC.advance(0.05)
		end
		local gt = ctx.g(theirs)
		local dimAll, n, pt0 = true, 0, {}
		for key, c in pairs(gt.Coins) do
			n = n + 1
			dimAll = dimAll and c.Dim and string.sub(c.Look, -1) == "d"
			pt0[key] = c.Part.CFrame
		end
		KC.advance(0.3)
		local still = true
		for key, c in pairs(ctx.g(theirs).Coins) do
			if pt0[key] and (pt0[key].Position - c.Part.CFrame.Position).Magnitude > 1e-6 then
				still = false
			end
		end
		T.check(n > 0 and dimAll and still, "p5 roam client: another player's coins are dimmed and still", n .. " coins")
		T.check(gt.Heaps.W and gt.Heaps.W.Dim, "p5 roam client: ...their Welcome-back heap too")
		st = HF.Stats()
		T.check(st.Coins <= 36 and st.CoinParts <= 36 * 6, "p5 roam client: <= 36 Cloud Cash coins x 6 parts over every home (72 drops listed)", st.Coins .. " coins")
		T.check(st.Posed <= 24 and st.GardenPets <= 24, "p5 roam client: <= 24 posed garden pets over every home (own home first)", st.Posed .. " posed, " .. st.GardenPets .. " placed")
		local ownPlaced = 0
		for _ in pairs(ctx.g().Pets) do
			ownPlaced = ownPlaced + 1
		end
		T.eq(ownPlaced, 12, "p5 roam client: ...the own home keeps all 12")
		T.check(st.PetParts <= 9000, "p5 roam client: the posed pets stay inside the part budget (HOME_PET_PARTS 9000)", tostring(st.PetParts))
		T.check(st.Bits <= 16, "p5 roam client: berries + puffs <= 16 pooled parts", tostring(st.Bits))
		-- a nap: slot 6 lies down at the far point of its napping cycle with a Zzz
		local napOff = {}
		for slot = 1, 12 do
			napOff[slot] = offsets[slot] + 0.05 * 0
		end
		napOff[6] = 5 * 24 + 22
		ctx.roam(mine, uid, napOff, { [6] = 5 })
		ctx.standAt(mine.PlotCFrame * TC.Get("Garden").Slot.CFrame.Position)
		KC.advance(0.2)
		g = ctx.g()
		local p6 = g.Pets[6]
		local far6 = HR.Plan(seed, 6, 5).Out
		far6 = far6[#far6]
		local lp6 = p6 and plot:PointToObjectSpace(p6.Model:GetPivot().Position)
		T.check(p6 and p6.State == "Nap" and p6.Sleep and p6.Zzz ~= nil and math.sqrt((lp6.X - far6.x - p6.SepX) ^ 2 + (lp6.Z - far6.z - p6.SepZ) ^ 2) < 1.6,
			"p5 roam client: a napping slot (':N5') lies at that cycle's far point with a 'Zzz'", p6 and tostring(p6.State) or "none")
		-- RoamVersion mismatch: pets parked on their beds, coins hidden
		mine.Folder:SetAttribute("RoamVersion", HR.Version + 7)
		KC.advance(0.2)
		g = ctx.g()
		local parked, coinsLeft = 0, 0
		for slot, p in pairs(g.Pets) do
			local bx, bz = HR.BedPoint(slot)
			local lp = plot:PointToObjectSpace(p.Model:GetPivot().Position)
			if p.State == "Park" and math.sqrt((lp.X - bx - p.SepX) ^ 2 + (lp.Z - bz - p.SepZ) ^ 2) < 0.6 then
				parked = parked + 1
			end
		end
		for _ in pairs(g.Coins) do
			coinsLeft = coinsLeft + 1
		end
		T.check(parked == 12 and coinsLeft == 0 and not g.RoamOk, "p5 roam client: a RoamVersion mismatch parks every pet on its bed and hides the coins", parked .. " parked, " .. coinsLeft .. " coins")
		mine.Folder:SetAttribute("RoamVersion", HR.Version)
		-- parked beyond 110 studs: no pets, no coins for that home
		ctx.standAt(mine.PlotCFrame.Position + Vector3.new(0, 0, 400))
		local cam = workspace.CurrentCamera
		if cam then
			cam.CFrame = CFrame.lookAt(mine.PlotCFrame.Position + Vector3.new(0, 20, 200), mine.PlotCFrame.Position)
		end
		for _ = 1, 12 do
			KC.advance(0.1)
		end
		g = ctx.g()
		local left = 0
		for _ in pairs(g.Pets) do
			left = left + 1
		end
		for _ in pairs(g.Coins) do
			left = left + 1
		end
		T.eq(left, 0, "p5 roam client: a home beyond 110 studs draws no pets and no coins")
		local errs = #Mock.Errors - errorsBefore
		local warned = nil
		for i = outputBefore + 1, #Mock.Output do
			local o = Mock.Output[i]
			if o.kind == "warn" and o.text:find("HomeFx", 1, true) then
				warned = o.text
			end
		end
		T.check(errs == 0 and warned == nil, "p5 roam client: no errors or HomeFx warnings", tostring(warned))
		cleanup()
		KC.flushErrors("client_p5home_roam")
	end)

	-- [W3 homefx+pets / careui] client_p5home_flow_ui: three signs, the basket line follows the attributes, only the
	-- next affordable pads carry a sign; the Home strip / Feed window (careui) when MenuController / CareController say
	S.client_p5home_flow_ui = guarded("client_p5home_flow_ui", function()
		local ctx, cleanup = C.setup("flow", 9400, { Stations = { Press1 = 13, Garden = 4, Kitchen = 2, House = 1 } })
		if not ctx then
			return
		end
		local HF, HB, TC = ctx.HF, ctx.HB, ctx.TC
		local mine = ctx.Mine
		local home = mine.Folder:FindFirstChild("Home")
		local function textOf(gui, name)
			local l = gui and gui:FindFirstChild(name, true)
			return l and l:IsA("TextLabel") and l.Text or nil
		end
		local farm = home and home:FindFirstChild("FarmSign", true)
		local bowl = home and home:FindFirstChild("BowlSign", true)
		local machine = home and home:FindFirstChild("MachineSign", true)
		T.check(farm and textOf(farm, "Title") == "Berry Farm Lv 13" and textOf(farm, "Info") == "Grows berries for your pets", "p5 flow ui: the Berry Farm sign 'Berry Farm Lv 13 / Grows berries for your pets'", farm and tostring(textOf(farm, "Title")) or "none")
		T.check(bowl and textOf(bowl, "Title") == "Food Bowl" and textOf(bowl, "Info") == "Pets eat here, then poop Cloud Cash!", "p5 flow ui: the Food Bowl sign", bowl and tostring(textOf(bowl, "Info")) or "none")
		T.check(machine and textOf(machine, "Title") == "Food Machine" and textOf(machine, "Info") == "Berries -> XP: press E", "p5 flow ui: the Food Machine sign", machine and tostring(textOf(machine, "Info")) or "none")
		LocalPlayer:SetAttribute("Berries", 1240)
		mine.Folder:SetAttribute("BerryCap", 3000)
		KC.advance(0.2)
		T.eq(textOf(machine, "BasketLine"), "1,240 / 3,000 berries", "p5 flow ui: the basket line follows Berries / BerryCap")
		LocalPlayer:SetAttribute("Berries", 2999)
		KC.advance(0.1)
		T.eq(textOf(machine, "BasketLine"), "2,999 / 3,000 berries", "p5 flow ui: ...and the next change of the Berries attribute")
		mine.Folder:SetAttribute("BerryCap", 4500)
		KC.advance(0.1)
		T.eq(textOf(machine, "BasketLine"), "2,999 / 4,500 berries", "p5 flow ui: ...and of the plot's BerryCap")
		-- berry flights while the farm is built (pooled with the puffs)
		local fl0 = HF.Stats().BerryFlights
		for _ = 1, 50 do
			KC.advance(0.1)
		end
		local st = HF.Stats()
		T.check(st.BerryFlights >= fl0 + 2 and st.Bits <= 16, "p5 flow ui: berries hop from the farm to the bowl (3 s) and the basket (4 s), pooled <= 16", (st.BerryFlights - fl0) .. " flights")
		-- the pad signs: only TycoonCatalog.SignedPads' pads show
		local homeTable = { Stations = { Press1 = 13, Garden = 4, Kitchen = 2, House = 1 }, Prestige = 0 }
		local pads = TC.AvailablePads(homeTable)
		HB.SetPads(mine, pads)
		LocalPlayer:SetAttribute("Cash", 2500)
		KC.advance(0.4)
		local want = TC.SignedPads(pads, 2500)
		local okAll, shown, unsigned, bad = true, 0, 0, nil
		for _, pad in ipairs(home.Pads:GetChildren()) do
			local sign = pad:FindFirstChild("PadSign", true)
			local id = pad:GetAttribute("StationId")
			local locked = pad:GetAttribute("Locked")
			local state = sign and HF.SignState(sign)
			if sign and (locked == nil or locked == "") then
				if want[id] then
					if state == "Unsigned" then
						okAll, bad = false, id .. " unsigned"
					end
				elseif state ~= "Unsigned" or sign.Enabled then
					okAll, bad = false, id .. " " .. tostring(state)
				else
					unsigned = unsigned + 1
				end
				if state ~= "Unsigned" then
					shown = shown + 1
				end
			end
		end
		T.check(okAll and unsigned > 0, "p5 flow ui: an open pad SignedPads did not pick is 'Unsigned' (hidden); the picked ones may show", tostring(bad) .. ", " .. unsigned .. " unsigned")
		LocalPlayer:SetAttribute("Cash", 1e12)
		KC.advance(0.3)
		local want2 = TC.SignedPads(pads, 1e12)
		local n2 = 0
		for _ in pairs(want2) do
			n2 = n2 + 1
		end
		local nShow = 0
		for _, pad in ipairs(home.Pads:GetChildren()) do
			local sign = pad:FindFirstChild("PadSign", true)
			if sign and HF.SignState(sign) ~= "Unsigned" and HF.SignState(sign) ~= "Locked" then
				nShow = nShow + 1
			end
		end
		T.check(nShow <= n2 and n2 <= 4, "p5 flow ui: a rich player still sees at most the 3 cheapest affordable (+ Prestige) signs", nShow .. " / " .. n2)
		-- the Home window / Food Machine window (careui, MenuController / CareController): read when they exist
		local MC = KC.M.MenuController or req("client/Controllers/MenuController")
		if MC and type(MC.Open) == "function" then
			pcall(MC.Open, "Home")
			KC.advance(0.5)
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			local texts = {}
			for _, d in ipairs(pg and pg:GetDescendants() or {}) do
				if d:IsA("TextLabel") or d:IsA("TextButton") then
					texts[#texts + 1] = d.Text
				end
			end
			local all = table.concat(texts, "\n")
			if all:find("Berry Basket", 1, true) or all:find("poop", 1, true) then
				-- careui's Phase 5 Home strip is there: the strip names the loop and no window offers "Level up"
				T.check(all:find("Berry Farm", 1, true) ~= nil and all:find("Food Machine", 1, true) ~= nil, "p5 flow ui: the Home strip names the Berry Farm and the Food Machine (careui)")
				T.check(all:find("Level up", 1, true) == nil, "p5 flow ui: no 'Level up' button anywhere (one Feed button)")
			else
				T.info("p5 flow ui: the Home window draws no Phase 5 flow strip in this world yet: careui's smoke_p4_careui / smoke_p5_looks check the strip and the Feed window")
			end
			pcall(MC.Close)
		else
			T.info("p5 flow ui: MenuController.Open not in this world: the Home strip is checked by careui's smoke_p4_careui")
		end
		cleanup()
		KC.flushErrors("client_p5home_flow_ui")
	end)
end

-- the client world runs only the client half (smoke.py lists the pure / server names in the server world only)
if CONTEXT == "client" then
	for _, name in ipairs({ "p5home_catalog", "p5home_fold", "p5home_roam_shared", "p5home_signs", "p5home_berries", "p5home_roam_server" }) do
		S[name] = nil
	end
end

return S
