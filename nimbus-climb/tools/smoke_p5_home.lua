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
--   tycoon+care (W2), server world: p5home_signs, p5home_berries, p5home_roam_server   (placeholders below: info only)
--   homefx+pets (W3), client world: client_p5home_roam, client_p5home_flow_ui            (placeholders below: info only)
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
-- wave 2 (tycoon+care) - server scenarios: replace each placeholder with the real scenario
----------------------------------------------------------------------------------------------------
-- [W2 tycoon+care] p5home_signs: HomeFx-free server half of the pad signs (TycoonCatalog.SignedPads on a booted home)
S.p5home_signs = guarded("p5home_signs", function()
	T.info("p5home_signs: pending (tycoon+care, wave 2)")
end)
-- [W2 tycoon+care] p5home_berries: berries from poops (Share, BasketCap), Feed with berries, the Berries attribute
S.p5home_berries = guarded("p5home_berries", function()
	T.info("p5home_berries: pending (tycoon+care, wave 2)")
end)
-- [W2 tycoon+care] p5home_roam_server: the roaming ledger (epochs, drops == Plan, CoinDrops, naps, scoops, invariant)
S.p5home_roam_server = guarded("p5home_roam_server", function()
	T.info("p5home_roam_server: pending (tycoon+care, wave 2)")
end)

----------------------------------------------------------------------------------------------------
-- wave 3 (homefx+pets) - client scenarios: replace each placeholder with the real scenario
----------------------------------------------------------------------------------------------------
if CONTEXT == "client" then
	-- [W3 homefx+pets] client_p5home_roam: poses == HomeRoam.At, coins pending / confirmed, budgets, RoamVersion
	S.client_p5home_roam = guarded("client_p5home_roam", function()
		T.info("client_p5home_roam: pending (homefx+pets, wave 3)")
	end)
	-- [W3 homefx+pets / careui] client_p5home_flow_ui: Home strip texts, Feed button, basket line, three signs
	S.client_p5home_flow_ui = guarded("client_p5home_flow_ui", function()
		T.info("client_p5home_flow_ui: pending (homefx+pets / careui, wave 3)")
	end)
end

-- the client world runs only the client half (smoke.py lists the pure / server names in the server world only)
if CONTEXT == "client" then
	for _, name in ipairs({ "p5home_catalog", "p5home_fold", "p5home_roam_shared", "p5home_signs", "p5home_berries", "p5home_roam_server" }) do
		S[name] = nil
	end
end

return S
