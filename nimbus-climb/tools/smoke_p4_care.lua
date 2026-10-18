-- smoke_p4_care.lua: Phase 4 pet care (ARCHITECTURE_V3.md "Phase 4 build contract" 3.4-3.7, 4.5, 5.1-5.4, 7, 8.1):
-- server/Services/PetCareService.lua (the Food Machine, EVOLVE, the Training Place), PetService (the training lock,
-- UnequipKey, EquippedInfo). Replaces the kitchen / gym / shutdown scenarios of smoke_p2_care.lua (p2care_feed and
-- p2care_exploits moved here). Loaded by tools/smoke.py in the SERVER world (booted):
--   p4care_feed      the API (the retired Cook / GymSet / GetQueue / ClearKitchen / Cooked / GymChanged are gone);
--                    the Food Machine: refused before any Cash moves without a machine, price = FeedPrice(def, level)
--                    and XP = FeedXp(level, machineLevel) per feed (a Lv 3 machine gives more XP for the same price),
--                    "Level up" (Count) priced per feed at the level each one is eaten at, leftovers first and free
--                    (nil opts, { Food = }, a plain string for old clients), the cap (100) refused, a failed XP write
--                    refunds Cash and food, Fed fires ("Machine" / the leftover id), ONE toast per grant (a feed, a
--                    batch, a fight crossing many levels) with "Ready to evolve!" at 20, Cook / GymSet answer one
--                    toast, the FeedPrompt on the Food Machine (owner only, "p4:" signature) opens the Pets panel on
--                    Feed, the TrainPrompt opens Train; refusals: not owned, in a battle, provisional
--   p4care_evolve    Evolve at 19 / 20 / 49 / 50 for Common / Rare / Epic / Legendary (Common never stage 2), the
--                    stored stage (DataService.GetEvolution), Evolved fires, the toast, OpenPanel("Evolve") to that
--                    client only, EquippedInfo "level:stage", refusals (battle, provisional, unowned, junk), a training
--                    pet may evolve, the remote cooldown
--   p4care_train     Train: no station / cost / time / the Job shape (Stat, Ends, Rank, Slot, From, Paid) / unequips
--                    every copy / clears the Garden slot / remembers From / TrainingStarted / TrainingPets; the lock
--                    (Equip, GardenSet, FieldableKeys skip with the preset kept); spots; already training; rank cap 10;
--                    completion by the tick adds the rank, returns the pet (Garden:n / Follow / Free, a taken place ->
--                    the first free one), TrainingDone, the toast; Stop refunds once; a due job stops into a completion
--                    (no refund); a stale stop changes nothing
--   p4care_load      a leave + rejoin mid-training finishes on load ("Training done while you were away!", the pet
--                    back), two servers completing one job = one rank (a real second DataService copy), a prestige
--                    keeps the job and the station reset blocks new jobs, Home.Gym emptied once on load with one toast
--                    (a migrated save and a stale Phase 3 write), ClearSessions
--   p4care_exploits  junk / NaN / huge / wrong-type PetCare arguments change nothing and raise nothing; spam (one Feed
--                    per cooldown, the burst budget, every paid feed gave exactly its XP); someone else's pets and
--                    prompts; a stray prompt; Cash never negative
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local abs, floor, ceil = math.abs, math.floor, math.ceil
local advance, config, mod = K.advance, K.config, K.mod
local STATS = { "Speed", "Physique", "Ability", "Defense" }
local LOAD_TOAST_DELAY = 3 -- PetCareService shows load toasts this long after the session started

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
end

local function requireAt(key)
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

local function PCS()
	return requireAt("server/Services/PetCareService")
end
local function TS()
	return requireAt("server/Services/TycoonService")
end
local function TC()
	return requireAt("shared/TycoonCatalog")
end
local function PK()
	return requireAt("shared/PetKeys")
end
local function PC()
	return requireAt("shared/PetCatalog")
end
local function PS()
	return mod("PetService")
end
local function DS()
	return mod("DataService")
end
local function BS()
	return requireAt("server/Services/BattleService")
end

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
local userSeq = 0
local function newUserId()
	userSeq = userSeq + 1
	return 964000 + userSeq
end

local function join(prefix, uid)
	uid = uid or newUserId()
	local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
	advance(1.0)
	return p
end

local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	advance(0.6)
end

local function spots()
	return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
end

local function freeIndex()
	local SS = mod("SpotService")
	for i = 1, config().Lobby.SpotCount do
		if spots()[i] and not SS.GetOwner(i) then
			return i
		end
	end
	return nil
end

-- claims the first free plot (TycoonService.Claim); returns its index or nil
local function claimFree(p)
	local Ty = TS()
	local index = freeIndex()
	if not Ty or not index then
		return nil
	end
	local ok = Ty.Claim(p, index)
	advance(0.6)
	if ok then
		return index
	end
	return nil
end

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

local function care(p, ...)
	Mock.FromClient(remote("PetCare"), p, ...)
end

local function cashOf(p)
	return DS().GetCash(p)
end

local function foodOf(p, id)
	return DS().GetFood(p, id)
end

local function homeOf(p)
	return DS().GetHome(p)
end

local function growthOf(p, key)
	return DS().GetGrowth(p, key)
end

local function storeKey(userId)
	return config().Tokens.DataStoreName .. "/u_" .. userId
end

local function stored(userId)
	return Mock.DataStore.Data[storeKey(userId)]
end

-- writes station levels straight into the saved home (Home.Level follows), then lets the services sync the plot
local function setStations(p, map)
	local Cat = TC()
	DS().MutateHome(p, function(h)
		for id, lv in pairs(map) do
			if lv > 0 then
				h.Stations[id] = lv
			else
				h.Stations[id] = nil
			end
		end
		h.Level = Cat.HomeLevelOf(h)
	end)
	advance(2.1) -- one TycoonService tick builds the stations, one PetCareService tick dresses the prompts
end

local function givePet(p, key, n)
	local prof = DS().GetProfile(p)
	local ok = PK().Add(prof, key, n or 1)
	DS().MarkDirty(p)
	return ok
end

-- a non-Secret, non-event catalog pet of that role (and rarity), skipping `not1` / `not2`
local function pickPet(role, rarity, not1, not2)
	for _, def in ipairs(PC().Pets) do
		if def.EventOnly ~= true and def.Role == role and def.Rarity ~= "Secret" and (rarity == nil or def.Rarity == rarity) and def.Id ~= not1 and def.Id ~= not2 then
			return def
		end
	end
	return nil
end

local function anyPet(rarity, not1)
	return pickPet("Economy", rarity, not1) or pickPet("Combat", rarity, not1)
end

-- total XP of a pet copy (level and XP folded into one number)
local function totalXp(p, key)
	local level, xp = DS().GetPetLevel(p, key)
	return TC().XpForLevel(level) + xp, level, xp
end

local function setLevel(p, key, level)
	return DS().SetPetLevel(p, key, level)
end

local function toasts(p, needle, kind, mark)
	local n = 0
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		if (needle == nil or string.find(tostring(e.args[1]), needle, 1, true)) and (kind == nil or e.args[2] == kind) then
			n = n + 1
		end
	end
	return n
end

local function toasted(p, needle, kind, mark)
	return toasts(p, needle, kind, mark) > 0
end

-- the last few toasts of a player (failure details)
local function toastsSince(p, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		out[#out + 1] = tostring(e.args[1])
	end
	local first = math.max(1, #out - 3)
	local tail = {}
	for i = first, #out do
		tail[#tail + 1] = out[i]
	end
	return table.concat(tail, " | ")
end

-- OpenPanel(panelId, args) messages sent to a player since `mark`
local function panels(p, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("OpenPanel", p.UserId, mark or 0)) do
		out[#out + 1] = { Id = e.args[1], Args = e.args[2] }
	end
	return out
end

local function count(map)
	local n = 0
	for _ in pairs(type(map) == "table" and map or {}) do
		n = n + 1
	end
	return n
end

local function listHas(list, v)
	for _, x in ipairs(type(list) == "table" and list or {}) do
		if x == v then
			return true
		end
	end
	return false
end

local function equipped(p)
	local prof = DS().GetProfile(p)
	return prof and prof.Equipped or {}
end

local function equippedCount(p, key)
	local n = 0
	for _, k in ipairs(equipped(p)) do
		if k == key then
			n = n + 1
		end
	end
	return n
end

local function compactText(n)
	if n >= 1000 then
		local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
		for _, u in ipairs(units) do
			if n >= u[1] then
				local x = n / u[1]
				local s
				if x >= 100 then
					s = string.format("%d", floor(x))
				else
					s = string.format("%.1f", floor(x * 10) / 10)
					s = string.gsub(s, "%.0$", "")
				end
				return s .. u[2]
			end
		end
	end
	return tostring(floor(n + 0.5))
end

local function stationOf(index, id)
	local info = spots()[index]
	local home = info and info.Folder:FindFirstChild("Home")
	return (home and home:FindFirstChild("Station_" .. id)) or (info and info.Folder:FindFirstChild("Station_" .. id, true))
end

local function promptIn(model, name)
	for _, d in ipairs(model and model:GetDescendants() or {}) do
		if d:IsA("ProximityPrompt") and d.Name == name then
			return d
		end
	end
	return nil
end

-- the running job of a key as text (failure details)
local function jobText(g)
	local job = type(g) == "table" and g.Job or nil
	if type(job) ~= "table" then
		return "no job"
	end
	return tostring(job.Stat) .. "/" .. tostring(job.Rank) .. "/" .. tostring(job.Ends) .. "/" .. tostring(job.Slot) .. "/" .. tostring(job.From) .. "/" .. tostring(job.Paid)
end

-- marks a key as fighting: BattleService.KeysInBattle (patched when it exists) and the InBattle attribute
local function startFakeBattle(p, key)
	local Bs = BS()
	local saved = nil
	if Bs and type(Bs.KeysInBattle) == "function" then
		saved = Bs.KeysInBattle
		Bs.KeysInBattle = function(pl)
			if pl == p then
				return { [key] = true }
			end
			return saved(pl)
		end
	end
	local attr = config().Attr.InBattle or "InBattle"
	p:SetAttribute(attr, "fake_battle")
	return function()
		if saved then
			Bs.KeysInBattle = saved
		end
		p:SetAttribute(attr, nil)
	end
end

-- the Cash and XP a "Level up" batch of `n` machine feeds costs / gives from (level, xp): priced feed by feed along
-- the curve, like the server
local function planBatch(def, level, xp, n, machineLevel, cap)
	local Cat = TC()
	local cash, gain, lv, have = 0, 0, level, xp
	for _ = 1, n do
		if lv >= cap then
			break
		end
		local price = Cat.FeedPrice(def, lv)
		local give = Cat.FeedXp(lv, machineLevel)
		cash = cash + price
		gain = gain + give
		have = have + give
		while lv < cap and have >= Cat.XpToNext(lv) do
			have = have - Cat.XpToNext(lv)
			lv = lv + 1
		end
	end
	return cash, gain, lv, have
end

-- a second, independent copy of DataService (its own cache, the same mock DataStore): "another server" (the pattern of
-- smoke_p4_data.lua: the hooks its first Load connects are dropped again by release())
local function hookedSignals()
	local out = { game:GetService("Players").PlayerRemoving }
	local folder = K.remoteFolder and K.remoteFolder()
	local r = folder and folder:FindFirstChild("RequestProfile")
	if r then
		out[#out + 1] = r.OnServerEvent
	end
	return out
end

local function connectionMarks()
	local marks = {}
	for _, sig in ipairs(hookedSignals()) do
		local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
		marks[#marks + 1] = { conns = conns, n = conns and #conns or 0 }
	end
	return marks
end

local function dropHooks(marks)
	local clean = true
	for _, m in ipairs(marks) do
		if m.conns then
			for i = #m.conns, m.n + 1, -1 do
				local conn = m.conns[i]
				if type(conn) == "table" and conn.Disconnect then
					conn:Disconnect()
				end
			end
			clean = clean and #m.conns == m.n
		else
			clean = false
		end
	end
	return clean
end

local function secondServer(name)
	local inst = K.moduleInstance("server/Services/DataService")
	if not inst then
		return nil
	end
	local marks = connectionMarks()
	local clone = inst:Clone()
	clone.Name = name
	clone.Parent = inst.Parent
	local ok, module = pcall(require, clone)
	if not ok then
		clone:Destroy()
		return nil, module
	end
	local function release()
		clone:Destroy()
		return dropHooks(marks)
	end
	return module, clone, release
end

-- a ready player: a claimed plot with the given stations, Cash, and pets
local function readyPlayer(prefix, stations, cash)
	local p = join(prefix)
	local index = claimFree(p)
	if not index then
		return p, nil
	end
	setStations(p, stations or {})
	if cash and cash > 0 then
		DS().AddCash(p, cash)
	end
	return p, index
end

----------------------------------------------------------------------------------------------------
-- p4care_feed
----------------------------------------------------------------------------------------------------
S.p4care_feed = guarded("p4care_feed", function()
	if not K.needBoot() then
		return
	end
	local Care, Ty, Cat, PCat = PCS(), TS(), TC(), PC()
	if not Care or not Ty or not Cat or not PCat then
		T.fail("care feed: PetCareService, TycoonService, TycoonCatalog and PetCatalog load")
		return
	end
	local DataS = DS()
	local Config = config()

	-- the API (contract 5.4)
	for _, fn in ipairs({ "Init", "Feed", "Evolve", "Train", "TrainStop", "GrantXp", "LevelCap", "ClearSessions" }) do
		T.check(type(Care[fn]) == "function", "care api: PetCareService." .. fn .. " is a function")
	end
	for _, sig in ipairs({ "Fed", "LevelUp", "Evolved", "TrainingStarted", "TrainingDone" }) do
		T.check(type(Care[sig]) == "table" and type(Care[sig].Connect) == "function" and type(Care[sig].Fire) == "function", "care api: PetCareService." .. sig .. " is a signal")
	end
	for _, gone in ipairs({ "Cook", "GymSet", "GetQueue", "ClearKitchen", "Cooked", "GymChanged" }) do
		T.check(Care[gone] == nil, "care api: the Phase 2 " .. gone .. " is gone (the Kitchen is the Food Machine, the Gym the Training Place)")
	end
	T.check(type(PS().UnequipKey) == "function" and type(PS().Refresh) == "function", "care api: PetService.UnequipKey / Refresh exist")

	local p, index = readyPlayer("CareFeed", { Garden = 1, Press1 = 1 }, 0)
	if not T.check(index ~= nil, "care feed: (precondition) the player claims a plot") then
		leave(p)
		return
	end
	local eco = pickPet("Economy", "Common")
	local combat = pickPet("Combat", "Common")
	if not T.check(eco ~= nil and combat ~= nil, "care feed: (precondition) the catalog has Common Economy and Combat pets") then
		leave(p)
		return
	end
	givePet(p, eco.Id)
	givePet(p, combat.Id)
	DataS.AddCash(p, 1000000)
	local cap = PCat.LevelCap(eco.Id)
	T.eq(cap, PCat.MaxPetLevel(), "care feed: the level cap is the top of the curve (" .. tostring(cap) .. ")")
	T.eq(Care.LevelCap(p, eco.Id), cap, "care feed: PetCareService.LevelCap(player, key) = PetCatalog.LevelCap")

	local fed, ups = {}, {}
	local c1 = Care.Fed:Connect(function(pl, key, foodId, levels)
		if pl == p then
			fed[#fed + 1] = { key, foodId, levels }
		end
	end)
	local c2 = Care.LevelUp:Connect(function(pl, key, level, source)
		if pl == p then
			ups[#ups + 1] = { key, level, source }
		end
	end)

	-- no Food Machine: refused before any Cash moves
	local cash0 = cashOf(p)
	local mark = K.logSize()
	care(p, "Feed", eco.Id)
	advance(0.15)
	T.check(cashOf(p) == cash0 and totalXp(p, eco.Id) == 0 and toasted(p, "Build the Food Machine at home first", "bad", mark),
		"care feed: without a Food Machine a feed is refused ('Build the Food Machine at home first') and no Cash moves", toastsSince(p, mark))
	local okNo, whyNo = Care.Feed(p, eco.Id)
	T.check(okNo == false and whyNo == "Build the Food Machine at home first", "care feed: ...the API answers false, reason")

	-- one machine feed: FeedPrice(def, level) Cash for FeedXp(level, machineLevel) XP
	setStations(p, { Garden = 1, Press1 = 1, Kitchen = 1 })
	local price1 = Cat.FeedPrice(eco, 1)
	local xp1 = Cat.FeedXp(1, 1)
	T.check(price1 == Cat.XpToNext(1) * (Config.PetStats.RarityScale.Common or 1) * Cat.FeedBase and xp1 == math.max(1, floor(Cat.XpToNext(1) * Cat.FeedShare[1] + 0.5)),
		"care feed: (catalog) a Common's Lv 1 feed costs XpToNext x RarityScale x FeedBase = $" .. tostring(price1) .. " for 25% of the bar = " .. tostring(xp1) .. " XP")
	mark = K.logSize()
	cash0 = cashOf(p)
	care(p, "Feed", eco.Id)
	advance(0.15)
	local total, lv, xp = totalXp(p, eco.Id)
	T.check(cash0 - cashOf(p) == price1 and total == xp1, "care feed: one machine feed (opts nil) costs $" .. price1 .. " and gives " .. xp1 .. " XP", "cash -" .. (cash0 - cashOf(p)) .. ", xp " .. total)
	T.check(#fed == 1 and fed[1][1] == eco.Id and fed[1][2] == "Machine" and fed[1][3] == 0, "care feed: Fed fired (player, key, 'Machine', levelsGained 0)")
	T.check(toasted(p, eco.Name .. " ate a meal: +" .. xp1 .. " XP (" .. xp .. "/" .. Cat.XpToNext(1) .. " to Lv 2)", "good", mark),
		"care feed: a feed without a level-up toasts the XP and the progress", toastsSince(p, mark))
	T.eq(toasts(p, nil, nil, mark), 1, "care feed: ...exactly one toast")

	-- a Lv 3 machine: more XP for the same price
	setStations(p, { Garden = 1, Press1 = 1, Kitchen = 3 })
	local before = totalXp(p, eco.Id)
	cash0 = cashOf(p)
	local okF, info = Care.Feed(p, eco.Id)
	local xp3 = Cat.FeedXp(lv, 3)
	T.check(okF and type(info) == "table" and info.Xp == xp3 and info.Paid == Cat.FeedPrice(eco, lv) and info.Free == 0 and info.Count == 1 and cash0 - cashOf(p) == info.Paid and totalXp(p, eco.Id) == before + xp3 and xp3 > Cat.FeedXp(lv, 1),
		"care feed: a Lv 3 Food Machine gives FeedXp(level, 3) = " .. xp3 .. " XP (more than Lv 1's " .. Cat.FeedXp(lv, 1) .. ") for the same price; Feed answers { Xp, Paid, Free, Count }",
		okF and (tostring(info.Xp) .. "/" .. tostring(info.Paid)) or tostring(info))

	-- "Level up": Count feeds in one request, each priced at the level it is eaten at
	setStations(p, { Garden = 1, Press1 = 1, Kitchen = 1 })
	local _, lvA, xpA = totalXp(p, eco.Id)
	local missing = Cat.XpToNext(lvA) - xpA
	local n = ceil(missing / Cat.FeedXp(lvA, 1))
	local wantCash, wantXp, wantLv = planBatch(eco, lvA, xpA, n, 1, cap)
	cash0 = cashOf(p)
	mark = K.logSize()
	care(p, "Feed", eco.Id, { Count = n })
	advance(0.15)
	local totalB, lvB = totalXp(p, eco.Id)
	T.check(cash0 - cashOf(p) == wantCash and totalB == Cat.XpForLevel(lvA) + xpA + wantXp and lvB == wantLv and lvB == lvA + 1,
		"care feed: 'Level up' { Count = " .. n .. " } feeds " .. n .. " times in ONE request for the sum of the per-feed prices ($" .. wantCash .. ") and reaches Lv " .. (lvA + 1),
		"cash -" .. (cash0 - cashOf(p)) .. ", Lv " .. lvB)
	T.eq(toasts(p, nil, nil, mark), 1, "care feed: ...ONE toast for the whole batch")
	T.check(toasted(p, eco.Name .. " reached Lv " .. lvB .. "!", "good", mark) and toasted(p, "Coins x", "good", mark),
		"care feed: ...the level-up toast names the new level and the pet's coin power ('Coins x1.1' for an Economy pet)", toastsSince(p, mark))
	T.check(#ups >= 1 and ups[#ups][1] == eco.Id and ups[#ups][2] == lvB and ups[#ups][3] == "Feed", "care feed: LevelUp fired (player, key, " .. lvB .. ", 'Feed')")
	-- a batch that crosses a level pays the higher price for the feeds after the level-up
	local _, lvC, xpC = totalXp(p, eco.Id)
	local n2 = 10
	local wantCash2, wantXp2, wantLv2 = planBatch(eco, lvC, xpC, n2, 1, cap)
	local flat = n2 * Cat.FeedPrice(eco, lvC)
	cash0 = cashOf(p)
	local okB, infoB = Care.Feed(p, eco.Id, { Count = n2 })
	local totalD, lvD = totalXp(p, eco.Id)
	T.check(okB and cash0 - cashOf(p) == wantCash2 and wantCash2 > flat and totalD == Cat.XpForLevel(lvC) + xpC + wantXp2 and lvD == wantLv2 and infoB.Count == n2 and infoB.Paid == wantCash2,
		"care feed: a batch of 10 that crosses a level is priced feed by feed ($" .. wantCash2 .. ", not 10 x the first price $" .. flat .. "): X7",
		"cash -" .. (cash0 - cashOf(p)) .. ", Lv " .. lvD)
	-- Count junk
	for _, bad in ipairs({ 0, 11, 2.5, -1, 0 / 0, 1 / 0, "3" }) do
		local c0 = cashOf(p)
		local x0 = totalXp(p, eco.Id)
		local okJ = Care.Feed(p, eco.Id, { Count = bad })
		T.check(okJ == false and cashOf(p) == c0 and totalXp(p, eco.Id) == x0, "care feed: Count " .. tostring(bad) .. " is refused (whole 1..10), nothing moves")
	end
	-- not enough Cash: refused before anything moves
	DataS.SpendCash(p, cashOf(p))
	DataS.AddCash(p, 5)
	mark = K.logSize()
	local x0 = totalXp(p, eco.Id)
	care(p, "Feed", eco.Id)
	advance(0.15)
	T.check(cashOf(p) == 5 and totalXp(p, eco.Id) == x0 and toasted(p, "Not enough Cash", "bad", mark), "care feed: short of Cash: refused, nothing moves", toastsSince(p, mark))
	DataS.AddCash(p, 1000000)

	-- leftovers (old Kitchen food) are fed first and free: the biggest that does not overshoot the cap
	setLevel(p, eco.Id, 40) -- far from the next level: no level-up toast gets in the way
	DataS.AddFood(p, "Snack", 2)
	DataS.AddFood(p, "Meal", 1)
	local snack, meal = Cat.Foods.Snack, Cat.Foods.Meal
	cash0 = cashOf(p)
	x0 = totalXp(p, eco.Id)
	mark = K.logSize()
	local nFed = #fed
	care(p, "Feed", eco.Id)
	advance(0.15)
	T.check(cashOf(p) == cash0 and totalXp(p, eco.Id) == x0 + meal.Xp and foodOf(p, "Meal") == 0 and foodOf(p, "Snack") == 2,
		"care feed: with leftovers a plain feed eats the biggest leftover (a Meal, " .. meal.Xp .. " XP) for free: no Cash moves", "cash " .. (cashOf(p) - cash0) .. ", xp +" .. (totalXp(p, eco.Id) - x0))
	T.check(#fed == nFed + 1 and fed[#fed][2] == "Meal", "care feed: ...Fed carries the leftover's id ('Meal')")
	T.check(toasted(p, "ate a free Meal", "good", mark), "care feed: ...the toast says it was free", toastsSince(p, mark))
	x0 = totalXp(p, eco.Id)
	care(p, "Feed", eco.Id, { Food = "Snack" })
	advance(0.15)
	care(p, "Feed", eco.Id, "Snack") -- an old client sends the food id as a plain string
	advance(0.15)
	T.check(cashOf(p) == cash0 and totalXp(p, eco.Id) == x0 + 2 * snack.Xp and foodOf(p, "Snack") == 0,
		"care feed: { Food = 'Snack' } and a plain 'Snack' (old clients) each eat one Snack for free")
	mark = K.logSize()
	care(p, "Feed", eco.Id, { Food = "Snack" })
	advance(0.15)
	T.check(toasted(p, "You have no Snacks left", "bad", mark) and cashOf(p) == cash0, "care feed: a leftover the player has none of is refused (no machine feed in its place)", toastsSince(p, mark))
	-- a batch mixes free leftovers and paid feeds
	DataS.AddFood(p, "Snack", 2)
	local _, lvE, xpE = totalXp(p, eco.Id)
	cash0 = cashOf(p)
	local okM, infoM = Care.Feed(p, eco.Id, { Count = 3 })
	T.check(okM and infoM.Free == 2 and infoM.Count == 3 and infoM.Paid > 0 and cash0 - cashOf(p) == infoM.Paid and foodOf(p, "Snack") == 0,
		"care feed: a 'Level up' of 3 eats the 2 leftover Snacks first (free) and pays one machine feed", okM and (tostring(infoM.Free) .. "/" .. tostring(infoM.Paid)) or tostring(infoM))

	-- Combat pets: the level-up toast shows Power / Health / Speed
	setLevel(p, combat.Id, 1)
	mark = K.logSize()
	local n3 = ceil(Cat.XpToNext(1) / Cat.FeedXp(1, 1))
	Care.Feed(p, combat.Id, { Count = n3 })
	local cs = PCat.GetStats(combat.Id, 2)
	T.check(toasted(p, combat.Name .. " reached Lv 2! Power " .. compactText(cs.Power) .. ", Health " .. compactText(cs.Health) .. ", Speed " .. compactText(cs.Speed), "good", mark),
		"care feed: a Combat pet's level-up toast shows Power, Health and Speed", toastsSince(p, mark))

	-- ONE toast per XP grant, whatever the number of levels crossed (the client_replay GUI-size pin)
	setLevel(p, combat.Id, 1)
	mark = K.logSize()
	local big = Cat.XpForLevel(30) + 7
	local given, levels = Care.GrantXp(p, combat.Id, big, "Ring")
	advance(0.1)
	T.check(given == big and levels == 29 and DataS.GetPetLevel(p, combat.Id) == 30, "care feed: GrantXp of " .. big .. " XP takes a Lv 1 pet to Lv 30 at once (29 levels)", tostring(given) .. "/" .. tostring(levels))
	T.eq(toasts(p, nil, nil, mark), 1, "care feed: ...with exactly ONE toast (never one per level)")
	T.check(toasted(p, combat.Name .. " reached Lv 30: Ready to evolve!", "good", mark), "care feed: ...which says 'Ready to evolve!' (level >= 20, not evolved yet)", toastsSince(p, mark))
	setLevel(p, combat.Id, 19)
	mark = K.logSize()
	Care.GrantXp(p, combat.Id, Cat.XpToNext(19), "Trial")
	T.check(toasted(p, combat.Name .. " reached Lv 20: Ready to evolve!", "good", mark) and toasts(p, nil, nil, mark) == 1, "care feed: Lv 19 -> 20 by a fight: one toast, 'Ready to evolve!'", toastsSince(p, mark))
	setLevel(p, combat.Id, 1)
	mark = K.logSize()
	Care.GrantXp(p, combat.Id, Cat.XpToNext(1), "Trial")
	T.check(toasted(p, combat.Name .. " reached Lv 2!", "good", mark) and not toasted(p, "Ready to evolve", nil, mark), "care feed: Lv 1 -> 2: no 'Ready to evolve!' yet", toastsSince(p, mark))
	local g0 = Care.GrantXp(p, combat.Id, 0, "Trial")
	local g1 = Care.GrantXp(p, combat.Id, -5, "Trial")
	local g2 = Care.GrantXp(p, combat.Id, 0 / 0, "Trial")
	T.check(g0 == 0 and g1 == 0 and g2 == 0, "care feed: GrantXp of 0 / negative / NaN gives nothing")

	-- the cap: refused before any Cash moves, GrantXp never passes it
	setLevel(p, eco.Id, cap)
	cash0 = cashOf(p)
	DataS.AddFood(p, "Feast", 1)
	mark = K.logSize()
	care(p, "Feed", eco.Id)
	advance(0.15)
	T.check(cashOf(p) == cash0 and foodOf(p, "Feast") == 1 and DataS.GetPetLevel(p, eco.Id) == cap and toasted(p, eco.Name .. " is at max level (Lv " .. cap .. ")", "bad", mark),
		"care caps: a pet at the cap (Lv " .. cap .. ") is refused before any Cash or food is used ('... is at max level')", toastsSince(p, mark))
	local gc, lc, whyC = Care.GrantXp(p, eco.Id, 5000, "Ring")
	T.check(gc == 0 and lc == 0 and type(whyC) == "string" and DataS.GetPetLevel(p, eco.Id) == cap, "care caps: GrantXp (fights) never passes the cap either")
	DataS.SpendFood(p, "Feast", 1)
	setLevel(p, eco.Id, cap - 1)
	local room = Cat.XpToNext(cap - 1)
	local okCap, infoCap = Care.Feed(p, eco.Id, { Count = 10 })
	local lvF, xpF = DataS.GetPetLevel(p, eco.Id)
	T.check(okCap and lvF == cap and xpF == 0 and infoCap.Xp == room and infoCap.Count == ceil(room / Cat.FeedXp(cap - 1, 1)) and infoCap.Count < 10,
		"care caps: a batch stops exactly at the cap (only the feeds needed are eaten and paid, the last one partly used)", okCap and (tostring(infoCap.Xp) .. "/" .. tostring(infoCap.Count)) or tostring(infoCap))
	T.check(Cat.FeedXp(cap, 1) == 0 and Cat.FeedPrice(eco, cap) == nil, "care caps: (catalog) FeedXp / FeedPrice at the cap are 0 / nil")

	-- a failed XP write refunds the Cash and the food (X7)
	setLevel(p, eco.Id, 5)
	DataS.AddFood(p, "Snack", 1)
	local realAdd = DataS.AddPetXp
	DataS.AddPetXp = function()
		return 0
	end
	cash0 = cashOf(p)
	x0 = totalXp(p, eco.Id)
	local okR, whyR = Care.Feed(p, eco.Id, { Count = 3 })
	DataS.AddPetXp = realAdd
	T.check(okR == false and type(whyR) == "string" and cashOf(p) == cash0 and foodOf(p, "Snack") == 1 and totalXp(p, eco.Id) == x0,
		"care feed: when the XP write gives 0 the Cash and the leftover come back (nothing is lost)", tostring(whyR) .. " cash " .. (cashOf(p) - cash0) .. " snacks " .. foodOf(p, "Snack"))
	DataS.SpendFood(p, "Snack", 1)

	-- refusals: not owned, junk, a battle
	local other = pickPet("Economy", nil, eco.Id)
	for _, r in ipairs({ { other.Id, nil, "You do not own that pet", "a pet the player does not own" }, { "!!", nil, "Unknown pet", "a junk key" }, { eco.Id, "Cake", "Unknown food", "an unknown food" }, { eco.Id, { Food = "Cake" }, "Unknown food", "an unknown food table" } }) do
		cash0 = cashOf(p)
		x0 = totalXp(p, eco.Id)
		mark = K.logSize()
		advance(1.6) -- past the repeat-toast throttle (the same refusal text is shown once per 1.5 s)
		care(p, "Feed", r[1], r[2])
		advance(0.15)
		T.check(cashOf(p) == cash0 and totalXp(p, eco.Id) == x0 and toasted(p, r[3], "bad", mark), "care feed: feeding " .. r[4] .. " is refused ('" .. r[3] .. "'), nothing moves", toastsSince(p, mark))
	end
	local stop = startFakeBattle(p, eco.Id)
	cash0 = cashOf(p)
	x0 = totalXp(p, eco.Id)
	local okBt, whyBt = Care.Feed(p, eco.Id)
	stop()
	T.check(okBt == false and whyBt == "Finish your battle first" and cashOf(p) == cash0 and totalXp(p, eco.Id) == x0, "care feed: a key in a running battle is refused ('Finish your battle first'), nothing moves", tostring(whyBt))

	-- Cook / GymSet are retired: one toast each
	mark = K.logSize()
	care(p, "Cook", "Snack", 1)
	advance(0.3)
	care(p, "GymSet", 1, combat.Id)
	advance(0.3)
	T.check(toasted(p, "The Kitchen is now the Food Machine", "info", mark) and toasted(p, "The Gym is now the Training Place", "info", mark) and toasts(p, nil, nil, mark) == 2,
		"care feed: Cook / GymSet (old clients) answer one toast each", toastsSince(p, mark))
	T.check((p:GetAttribute("KitchenQueue") == nil) and (p:GetAttribute("KitchenReadyAt") == nil) and (p:GetAttribute("KitchenDishSeconds") == nil), "care feed: no kitchen queue attributes on the player")

	-- the prompts: FeedPrompt on the Food Machine (owner only, "p4:" signature), TrainPrompt on the Training Place
	setStations(p, { Garden = 1, Press1 = 1, Kitchen = 1, Gym = 1 })
	local kitchen = stationOf(index, "Kitchen")
	local gym = stationOf(index, "Gym")
	local feedPrompt = promptIn(kitchen, "FeedPrompt")
	local trainPrompt = promptIn(gym, "TrainPrompt")
	T.check(kitchen ~= nil and feedPrompt ~= nil and feedPrompt.ActionText == "Feed pets" and feedPrompt:GetAttribute("CareMade") == true and feedPrompt:GetAttribute("OwnerUserId") == p.UserId,
		"care prompts: the Food Machine carries a FeedPrompt 'Feed pets' (CareMade, OwnerUserId)")
	T.check(kitchen ~= nil and promptIn(kitchen, "CookPrompt") == nil, "care prompts: ...and no CookPrompt")
	local sig = kitchen and kitchen:GetAttribute("CareSig")
	T.check(type(sig) == "string" and string.sub(sig, 1, 3) == "p4:", "care prompts: the station's CareSig carries the 'p4:' marker (stale Phase 3 Kitchen prompts rebuild)", tostring(sig))
	if kitchen and feedPrompt then
		local hopper = kitchen:FindFirstChild("Hopper", true)
		if hopper then
			T.check(feedPrompt:IsDescendantOf(hopper) or feedPrompt.Parent == hopper, "care prompts: the FeedPrompt sits on the Hopper part")
		else
			T.info("*care prompts: the Food Machine has no Hopper part yet (homeworld W2): the prompt sits on its biggest part")
		end
	end
	T.check(gym ~= nil and trainPrompt ~= nil and trainPrompt.ActionText == "Train pets" and trainPrompt:GetAttribute("OwnerUserId") == p.UserId, "care prompts: the Training Place carries a TrainPrompt 'Train pets'")
	if feedPrompt and trainPrompt then
		mark = K.logSize()
		Mock.Trigger(feedPrompt, p)
		advance(0.5)
		local got = panels(p, mark)
		T.check(#got == 1 and got[1].Id == "Pets" and type(got[1].Args) == "table" and got[1].Args.Action == "Feed", "care prompts: E on the FeedPrompt sends OpenPanel('Pets', { Action = 'Feed' }) to the owner", #got .. " panels")
		mark = K.logSize()
		Mock.Trigger(trainPrompt, p)
		advance(0.5)
		got = panels(p, mark)
		T.check(#got == 1 and got[1].Id == "Train", "care prompts: E on the TrainPrompt sends OpenPanel('Train')", #got .. " panels")
		local q = join("CareFeedGuest")
		mark = K.logSize()
		Mock.Trigger(feedPrompt, q)
		Mock.Trigger(trainPrompt, q)
		advance(0.5)
		T.check(#panels(q, mark) == 0 and #panels(p, mark) == 0, "care prompts: another player's presses on the owner's prompts open nothing (for anyone)")
		leave(q)
	end
	-- a rebuilt station gets its prompt again (one per station)
	setStations(p, { Garden = 1, Press1 = 1, Kitchen = 2, Gym = 1 })
	kitchen = stationOf(index, "Kitchen")
	local nFeed = 0
	for _, d in ipairs(kitchen and kitchen:GetDescendants() or {}) do
		if d:IsA("ProximityPrompt") and d.Name == "FeedPrompt" then
			nFeed = nFeed + 1
		end
	end
	T.eq(nFeed, 1, "care prompts: the rebuilt Lv 2 Food Machine carries exactly one FeedPrompt")

	-- provisional: refused without taking anything (a stand-in save)
	local DSt = Mock.DataStore
	local savedFail = DSt.Fail
	DSt.Fail = true
	local v = join("CareFeedOutage")
	advance(3)
	if T.check(DataS.IsProvisional(v) == true, "care feed: (precondition) the outage makes the newcomer's profile provisional") then
		local okP, whyP = Care.Feed(v, eco.Id)
		local okE, whyE = Care.Evolve(v, eco.Id)
		local okT, whyT = Care.Train(v, eco.Id, "Speed")
		T.check(okP == false and whyP == "Your save is still loading, try again in a moment" and okE == false and whyE == whyP and okT == false and whyT == whyP,
			"care feed: Feed / Evolve / Train refuse a provisional save ('Your save is still loading, try again in a moment')", tostring(whyP) .. " / " .. tostring(whyE) .. " / " .. tostring(whyT))
	end
	DSt.Fail = savedFail
	leave(v)
	advance(1)

	c1:Disconnect()
	c2:Disconnect()
	leave(p)
	K.flushErrors("p4care_feed")
	K.flushWarnings("p4care_feed", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- p4care_evolve
----------------------------------------------------------------------------------------------------
S.p4care_evolve = guarded("p4care_evolve", function()
	if not K.needBoot() then
		return
	end
	local Care, Cat, PCat = PCS(), TC(), PC()
	if not Care or not Cat or not PCat then
		T.fail("care evolve: PetCareService, TycoonCatalog and PetCatalog load")
		return
	end
	local DataS, Pets = DS(), PS()
	local Config = config()
	local p = readyPlayer("CareEvolve", { Garden = 1, Press1 = 1, Kitchen = 1, Gym = 1 }, 100000)
	local evolved = {}
	local conn = Care.Evolved:Connect(function(pl, key, stage)
		if pl == p then
			evolved[#evolved + 1] = { key, stage }
		end
	end)

	local function tryEvolve(key, level, want, label)
		setLevel(p, key, level)
		local mark = K.logSize()
		local ok, result = Care.Evolve(p, key)
		advance(0.1)
		return ok, result, mark
	end

	local cases = {}
	for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary" }) do
		local def = anyPet(rarity)
		if def then
			cases[#cases + 1] = def
		end
	end
	local tally = T.tally("care evolve: at 19 refused / 20 -> stage 1 / 20 again refused / 49 refused / 50 -> stage 2 only for Epic and rarer (Common / Uncommon / Rare stay at 1), the stage is stored")
	for _, def in ipairs(cases) do
		givePet(p, def.Id)
		local maxEvo = PCat.MaxEvolution(def)
		local ok19, why19 = tryEvolve(def.Id, 19)
		tally:case(ok19 == false and tostring(why19):find("evolves at level 20", 1, true) ~= nil and DataS.GetEvolution(p, def.Id) == 0, def.Id .. " @19: " .. tostring(why19))
		local ok20, st20, mark20 = tryEvolve(def.Id, 20)
		tally:case(ok20 == true and st20 == 1 and DataS.GetEvolution(p, def.Id) == 1, def.Id .. " @20 -> " .. tostring(st20))
		tally:case(toasted(p, def.Name .. " evolved! +25% to everything", "good", mark20), def.Id .. " toast: " .. toastsSince(p, mark20))
		local okAgain, whyAgain = tryEvolve(def.Id, 20)
		tally:case(okAgain == false and DataS.GetEvolution(p, def.Id) == 1, def.Id .. " @20 again: " .. tostring(whyAgain))
		local ok49, why49 = tryEvolve(def.Id, 49)
		tally:case(ok49 == false and DataS.GetEvolution(p, def.Id) == 1, def.Id .. " @49: " .. tostring(why49))
		local ok50, st50, mark50 = tryEvolve(def.Id, 50)
		if maxEvo >= 2 then
			tally:case(ok50 == true and st50 == 2 and DataS.GetEvolution(p, def.Id) == 2 and toasted(p, def.Name .. " evolved! +50% to everything", "good", mark50), def.Id .. " @50 -> " .. tostring(st50) .. " (" .. def.Rarity .. ")")
			local okMax, whyMax = tryEvolve(def.Id, 100)
			tally:case(okMax == false and tostring(whyMax):find("fully evolved", 1, true) ~= nil and DataS.GetEvolution(p, def.Id) == 2, def.Id .. " @100: " .. tostring(whyMax))
		else
			tally:case(ok50 == false and tostring(st50):find("fully evolved", 1, true) ~= nil and DataS.GetEvolution(p, def.Id) == 1, def.Id .. " @50 (" .. def.Rarity .. " stops at 1): " .. tostring(st50))
		end
	end
	tally:report()
	T.check(#evolved >= #cases and evolved[1][2] == 1, "care evolve: Evolved(player, key, stage) fired for every evolution (" .. #evolved .. ")")

	-- OpenPanel("Evolve", { Key, Stage }) goes to that client only; EquippedInfo follows for an equipped pet
	local common = cases[1]
	local extra = anyPet("Common", common.Id)
	givePet(p, extra.Id)
	setLevel(p, extra.Id, 23)
	Pets.Equip(p, extra.Id)
	advance(0.6)
	local q = join("CareEvolveWatcher")
	local info0 = p:GetAttribute(Config.Attr.EquippedInfo)
	T.check(info0 == "23:0", "care evolve: EquippedInfo reads '23:0' (level:stage) for the one equipped pet", tostring(info0))
	local mark = K.logSize()
	local okE, stE = Care.Evolve(p, extra.Id)
	advance(0.6)
	local got = panels(p, mark)
	T.check(okE and stE == 1 and #got == 1 and got[1].Id == "Evolve" and type(got[1].Args) == "table" and got[1].Args.Key == extra.Id and got[1].Args.Stage == 1,
		"care evolve: OpenPanel('Evolve', { Key, Stage }) is sent to the evolving player", #got .. " panels")
	T.eq(#panels(q, mark), 0, "care evolve: ...and to nobody else")
	T.eq(p:GetAttribute(Config.Attr.EquippedInfo), "23:1", "care evolve: EquippedInfo follows the evolution ('23:1')")
	leave(q)

	-- the boost is NOT in GetStats (the pure level formula), it is in TycoonCatalog.PetPower / BattleCatalog.UnitStats
	local s1 = PCat.GetStats(extra.Id, 23)
	T.check(near(s1.Power, extra.Stats.Power * (Config.PetStats.RarityScale[extra.Rarity] or 1) * (1 + 0.1 * 22), 1e-6 * s1.Power), "care evolve: PetCatalog.GetStats keeps the pure level formula (no evolution boost)")
	T.check(near(Cat.PetPower(extra, 23, "Normal", 1) / Cat.PetPower(extra, 23, "Normal", 0), 1.25, 1e-9), "care evolve: TycoonCatalog.PetPower with the stored stage 1 is x1.25 (coins)")

	-- refusals: junk, unowned, a battle; a training pet MAY evolve
	local okJ1 = Care.Evolve(p, "!!")
	local okJ2 = Care.Evolve(p, 42)
	local okJ3 = Care.Evolve(p, nil)
	local other = pickPet("Combat", "Rare", extra.Id) or pickPet("Combat", nil, extra.Id)
	local okUn, whyUn = Care.Evolve(p, other.Id)
	T.check(okJ1 == false and okJ2 == false and okJ3 == false and okUn == false and whyUn == "You do not own that pet", "care evolve: junk keys and a pet the player does not own are refused", tostring(whyUn))
	givePet(p, other.Id)
	setLevel(p, other.Id, 20)
	local stop = startFakeBattle(p, other.Id)
	local okB, whyB = Care.Evolve(p, other.Id)
	stop()
	T.check(okB == false and whyB == "Finish your battle first" and DataS.GetEvolution(p, other.Id) == 0, "care evolve: refused during a battle ('Finish your battle first')", tostring(whyB))
	local okTr, infoTr = Care.Train(p, other.Id, "Speed")
	local okEv, stEv = Care.Evolve(p, other.Id)
	T.check(okTr == true and okEv == true and stEv == 1 and DataS.TrainingKeys(p)[other.Id] == true, "care evolve: a TRAINING pet may evolve (the animation plays on clones)", tostring(infoTr) .. " / " .. tostring(stEv))
	Care.TrainStop(p, other.Id)

	-- the remote: Evolve (key), 1 s cooldown
	local used = {}
	for _, def in ipairs(cases) do
		used[def.Id] = true
	end
	used[extra.Id] = true
	used[other.Id] = true
	local third = nil
	for _, def in ipairs(PCat.Pets) do
		if def.EventOnly ~= true and def.Rarity == "Uncommon" and not used[def.Id] then
			third = def
			break
		end
	end
	givePet(p, third.Id)
	setLevel(p, third.Id, 50)
	mark = K.logSize()
	care(p, "Evolve", third.Id)
	care(p, "Evolve", third.Id)
	advance(0.2)
	T.check(DataS.GetEvolution(p, third.Id) == 1 and toasts(p, "evolved!", "good", mark) == 1, "care evolve: the remote evolves once (a second request within the 1 s cooldown is dropped)", toastsSince(p, mark))
	advance(1.1)
	mark = K.logSize()
	care(p, "Evolve", third.Id)
	advance(0.2)
	T.check(DataS.GetEvolution(p, third.Id) == 1 and toasted(p, "fully evolved", "bad", mark), "care evolve: ...an Uncommon at 50 is fully evolved at stage 1 (the refusal toasts once)", toastsSince(p, mark))
	-- a level above 50 never forces a stage from the client
	care(p, "Evolve", { Key = third.Id, Stage = 2 })
	advance(1.2)
	T.eq(DataS.GetEvolution(p, third.Id), 1, "care evolve: a client cannot force a stage (X9)")

	conn:Disconnect()
	leave(p)
	K.flushErrors("p4care_evolve")
	K.flushWarnings("p4care_evolve", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- p4care_train
----------------------------------------------------------------------------------------------------
S.p4care_train = guarded("p4care_train", function()
	if not K.needBoot() then
		return
	end
	local Care, Ty, Cat, PCat = PCS(), TS(), TC(), PC()
	if not Care or not Ty or not Cat or not PCat then
		T.fail("care train: PetCareService, TycoonService, TycoonCatalog and PetCatalog load")
		return
	end
	local DataS, Pets = DS(), PS()
	local Config = config()
	local p, index = readyPlayer("CareTrain", { Garden = 1, Press1 = 1, Kitchen = 1 }, 10000000)
	if not T.check(index ~= nil, "care train: (precondition) the player claims a plot") then
		leave(p)
		return
	end
	local info = spots()[index]
	local eco = pickPet("Economy", "Common")
	local combat = pickPet("Combat", "Common")
	local rare = pickPet("Combat", "Rare") or pickPet("Economy", "Rare")
	givePet(p, eco.Id, 3)
	givePet(p, combat.Id, 1)
	givePet(p, rare.Id, 1)
	local started, done = {}, {}
	local c1 = Care.TrainingStarted:Connect(function(pl, key, stat)
		if pl == p then
			started[#started + 1] = { key, stat }
		end
	end)
	local c2 = Care.TrainingDone:Connect(function(pl, key, stat, rank)
		if pl == p then
			done[#done + 1] = { key, stat, rank }
		end
	end)

	-- no Training Place
	local cash0 = cashOf(p)
	local okNo, whyNo = Care.Train(p, eco.Id, "Physique")
	T.check(okNo == false and whyNo == "Build the Training Place at home first" and cashOf(p) == cash0, "care train: without a Training Place a job is refused before any Cash moves", tostring(whyNo))
	setStations(p, { Garden = 1, Press1 = 1, Kitchen = 1, Gym = 1 })

	-- the pet is equipped twice and works in the Garden: Train takes it off the player and out of the Garden
	Pets.Equip(p, eco.Id)
	Pets.Equip(p, eco.Id)
	local okG, whyG = Ty.GardenSet(p, 1, eco.Id)
	advance(0.3)
	T.check(okG == true and equippedCount(p, eco.Id) == 2 and homeOf(p).Garden[1] == eco.Id, "care train: (precondition) 2 copies equipped and one in Garden place 1", tostring(whyG) .. " eq " .. equippedCount(p, eco.Id))
	local cost1 = Cat.TrainCost(eco, 1)
	local secs1 = Cat.TrainSeconds(1)
	T.check(cost1 == 300 * (Config.PetStats.RarityScale.Common or 1) and secs1 == 60, "care train: (catalog) rank 1 of a Common costs $300 and takes 60 s")
	cash0 = cashOf(p)
	local mark = K.logSize()
	local t0 = os.time()
	local okT, job = Care.Train(p, eco.Id, "Physique")
	advance(0.3)
	T.check(okT == true and type(job) == "table" and job.Rank == 1 and job.Cost == cost1 and job.Ends == t0 + secs1 and job.Slot == 1 and job.From == "Garden:1",
		"care train: Train answers { Rank 1, Ends = now + 60, Cost, Slot 1, From 'Garden:1' }", okT and (tostring(job.Rank) .. "/" .. tostring(job.Ends - t0) .. "/" .. tostring(job.Cost) .. "/" .. tostring(job.Slot) .. "/" .. tostring(job.From)) or tostring(job))
	T.eq(cash0 - cashOf(p), cost1, "care train: the Cash is taken once")
	local g = growthOf(p, eco.Id)
	T.check(type(g.Job) == "table" and g.Job.Stat == "Physique" and g.Job.Ends == t0 + secs1 and g.Job.Rank == 1 and g.Job.Slot == 1 and g.Job.From == "Garden:1" and g.Job.Paid == cost1,
		"care train: the stored Job = { Stat, Ends, Rank, Slot, From, Paid } (DataService.GetGrowth)", jobText(g))
	T.check(equippedCount(p, eco.Id) == 0 and homeOf(p).Garden[1] == nil, "care train: starting unequips EVERY copy and clears the Garden place by itself")
	T.check(DataS.TrainingKeys(p)[eco.Id] == true, "care train: DataService.TrainingKeys holds the key (the lock)")
	T.check(#started == 1 and started[1][1] == eco.Id and started[1][2] == "Physique", "care train: TrainingStarted(player, key, 'Physique') fired")
	T.check(toasted(p, eco.Name .. " started Physique training (1:00)", "good", mark), "care train: toast 'Rocky started Physique training (1:00)'", toastsSince(p, mark))
	local attr = info.Folder:GetAttribute("TrainingPets")
	T.eq(attr, "1=" .. eco.Id .. ":Physique:" .. tostring(t0 + secs1), "care train: the plot attribute TrainingPets = 'mat=key:stat:Ends'")
	T.check(info.Folder:GetAttribute("GymPets") == nil, "care train: no GymPets attribute any more")

	-- the lock: Equip, GardenSet, teams (the preset keeps the key), a second Train
	local okEq, whyEq = Pets.Equip(p, eco.Id)
	T.check(okEq == false and tostring(whyEq):find(eco.Name .. " is training (", 1, true) ~= nil and tostring(whyEq):find("left)", 1, true) ~= nil, "care train: Equip refuses a training key ('Rocky is training (0:59 left)')", tostring(whyEq))
	local okGs, whyGs = Ty.GardenSet(p, 2, eco.Id)
	T.check(okGs == false and tostring(whyGs):find("is training", 1, true) ~= nil, "care train: GardenSet refuses a training key", tostring(whyGs))
	local okTeam = DataS.SetTeam(p, 1, { eco.Id, combat.Id })
	local active = DataS.ActiveTeamKeys(p)
	T.check(okTeam == true and listHas(DataS.GetTeams(p).Presets[1], eco.Id) and not listHas(active, eco.Id) and listHas(active, combat.Id),
		"care train: a preset may keep the training key, ActiveTeamKeys skips it at read time", table.concat(active, ","))
	local okTw, whyTw = Care.Train(p, eco.Id, "Speed")
	T.check(okTw == false and tostring(whyTw):find("is already training", 1, true) ~= nil, "care train: a second job on the same pet is refused", tostring(whyTw))
	cash0 = cashOf(p)
	local okFull, whyFull = Care.Train(p, combat.Id, "Speed")
	T.check(okFull == false and whyFull == "The Training Place is full (1/1 training)" and cashOf(p) == cash0, "care train: a Lv 1 Training Place has one mat: 'The Training Place is full (1/1 training)'", tostring(whyFull))
	-- junk stats, unowned, rank 10, short of Cash, a battle
	local okSt, whySt = Care.Train(p, combat.Id, "Luck")
	T.check(okSt == false and whySt == "Pick a skill: Attack Speed, Physique, Ability or Defense", "care train: an unknown skill is refused", tostring(whySt))
	setStations(p, { Garden = 1, Press1 = 1, Kitchen = 1, Gym = 2 })
	local okUn, whyUn = Care.Train(p, pickPet("Economy", nil, eco.Id).Id, "Speed")
	T.check(okUn == false and whyUn == "You do not own that pet", "care train: a pet the player does not own is refused", tostring(whyUn))
	DataS.MutateGrowth(p, function(gr)
		gr[rare.Id] = gr[rare.Id] or {}
		gr[rare.Id].Defense = 10
	end)
	local okMax, whyMax = Care.Train(p, rare.Id, "Defense")
	T.check(okMax == false and tostring(whyMax):find("Rank 10 (max)", 1, true) ~= nil, "care train: rank 10 is the cap ('... Defense is at Rank 10 (max)')", tostring(whyMax))
	T.check(Cat.TrainCost(rare, 11) == nil and Cat.TrainSeconds(11) == nil, "care train: (catalog) no cost / time past rank 10")
	local stop = startFakeBattle(p, combat.Id)
	local okBt, whyBt = Care.Train(p, combat.Id, "Speed")
	stop()
	T.check(okBt == false and whyBt == "Finish your battle first", "care train: a key in a running battle is refused", tostring(whyBt))
	local saveCash = cashOf(p)
	DataS.SpendCash(p, saveCash)
	DataS.AddCash(p, cost1 - 1)
	local okPoor, whyPoor = Care.Train(p, combat.Id, "Speed")
	T.check(okPoor == false and tostring(whyPoor):find("Not enough Cash", 1, true) ~= nil and cashOf(p) == cost1 - 1, "care train: short of Cash: refused, nothing taken", tostring(whyPoor))
	DataS.SpendCash(p, cashOf(p))
	DataS.AddCash(p, saveCash)

	-- Stop refunds Paid once; a stale stop changes nothing
	Pets.Equip(p, combat.Id)
	cash0 = cashOf(p)
	local okC, jobC = Care.Train(p, combat.Id, "Speed")
	T.check(okC and jobC.From == "Follow" and jobC.Slot == 2 and equippedCount(p, combat.Id) == 0 and cashOf(p) == cash0 - cost1, "care train: a follower trains on mat 2 with From 'Follow' (unequipped)", okC and (jobC.From .. "/" .. jobC.Slot) or tostring(jobC))
	mark = K.logSize()
	local okS, refund = Care.TrainStop(p, combat.Id)
	T.check(okS == true and refund == cost1 and cashOf(p) == cash0 and growthOf(p, combat.Id).Job == nil and DataS.TrainingKeys(p)[combat.Id] == nil,
		"care train: TrainStop removes the job and refunds Job.Paid in the same step", tostring(refund) .. " cash " .. (cashOf(p) - cash0))
	T.check(equippedCount(p, combat.Id) == 1, "care train: ...the stopped follower comes back to the player")
	T.check(toasted(p, combat.Name .. " stopped training: $" .. cost1 .. " back", nil, mark) or toasted(p, "stopped training", nil, mark), "care train: ...one toast", toastsSince(p, mark))
	local okS2, whyS2 = Care.TrainStop(p, combat.Id)
	care(p, "TrainStop", combat.Id)
	advance(0.3)
	T.check(okS2 == false and tostring(whyS2):find("is not training", 1, true) ~= nil and cashOf(p) == cash0, "care train: a second stop refunds nothing ('... is not training'): the refund is paid once", tostring(whyS2))
	T.check(growthOf(p, combat.Id).Speed == 0, "care train: a stopped job gives no rank")

	-- a due job that is stopped finishes instead (the race between a stop and the completion): no refund, one rank
	local okD = DataS.MutateGrowth(p, function(gr)
		gr[combat.Id] = gr[combat.Id] or {}
		gr[combat.Id].Job = { Stat = "Speed", Ends = os.time() - 1, Rank = 1, Slot = 2, From = "Free", Paid = cost1 }
	end)
	cash0 = cashOf(p)
	local nDone = #done
	local okRace, refundRace = Care.TrainStop(p, combat.Id)
	T.check(okD and okRace == true and refundRace == 0 and cashOf(p) == cash0 and growthOf(p, combat.Id).Speed == 1 and growthOf(p, combat.Id).Job == nil and #done == nDone + 1,
		"care train: stopping a job whose time is up completes it instead: the rank is earned, nothing is refunded (X11)", tostring(refundRace) .. " speed " .. tostring(growthOf(p, combat.Id).Speed))
	advance(1.2)
	T.check(#done == nDone + 1 and growthOf(p, combat.Id).Speed == 1, "care train: ...and the tick does not complete it a second time")

	-- completion by the 1 s tick: the rank, the return to the Garden place, TrainingDone, the toast
	mark = K.logSize()
	nDone = #done
	advance(secs1 + 2)
	g = growthOf(p, eco.Id)
	T.check(g.Physique == 1 and g.Job == nil and DataS.TrainingKeys(p)[eco.Id] == nil, "care train: after 60 s the tick finishes the job: Physique rank 1, the job gone, the lock lifted", jobText(g) .. " P" .. tostring(g.Physique))
	T.check(#done == nDone + 1 and done[#done][1] == eco.Id and done[#done][2] == "Physique" and done[#done][3] == 1, "care train: TrainingDone(player, key, 'Physique', 1) fired once")
	T.check(toasted(p, eco.Name .. " finished Physique training: Rank 1!", "good", mark) and toasts(p, "finished Physique training", nil, mark) == 1, "care train: toast 'Rocky finished Physique training: Rank 3!' once", toastsSince(p, mark))
	T.check(homeOf(p).Garden[1] == eco.Id and equippedCount(p, eco.Id) == 0, "care train: the pet goes back to Garden place 1 by itself (From 'Garden:1'), not onto the player")
	T.eq(info.Folder:GetAttribute("TrainingPets"), "", "care train: TrainingPets is empty again")
	-- rank 2 costs TrainCost(def, 2) and takes 120 s; a taken Garden place -> the first free open place
	Ty.GardenSet(p, 1, nil)
	Ty.GardenSet(p, 2, eco.Id)
	Ty.GardenSet(p, 3, combat.Id)
	advance(0.3)
	cash0 = cashOf(p)
	local okR2, job2 = Care.Train(p, eco.Id, "Physique")
	T.check(okR2 and job2.Rank == 2 and job2.Cost == Cat.TrainCost(eco, 2) and job2.Ends - os.time() == Cat.TrainSeconds(2) and job2.From == "Garden:2" and cash0 - cashOf(p) == Cat.TrainCost(eco, 2),
		"care train: rank 2 costs TrainCost(def, 2) = $" .. tostring(Cat.TrainCost(eco, 2)) .. " and takes " .. tostring(Cat.TrainSeconds(2)) .. " s; From 'Garden:2'", okR2 and (job2.Rank .. "/" .. job2.Cost .. "/" .. job2.From) or tostring(job2))
	Ty.GardenSet(p, 2, rare.Id) -- its place is taken meanwhile
	advance(0.3)
	advance(Cat.TrainSeconds(2) + 2)
	local h = homeOf(p)
	T.check(growthOf(p, eco.Id).Physique == 2 and h.Garden[2] == rare.Id and h.Garden[1] == eco.Id, "care train: its place taken, the finished pet goes to the first free open place (1)", tostring(h.Garden[1]) .. "," .. tostring(h.Garden[2]) .. "," .. tostring(h.Garden[3]))
	-- no free place: it stays in the list; From Follow -> re-equipped
	Ty.GardenSet(p, 1, nil)
	advance(0.2)
	local okR3 = Care.Train(p, eco.Id, "Speed") -- From "Garden:..."? no: it is free now
	local fromFree = growthOf(p, eco.Id).Job and growthOf(p, eco.Id).Job.From
	T.check(okR3 and fromFree == "Free", "care train: a pet neither equipped nor in the Garden trains with From 'Free'", tostring(fromFree))
	Ty.GardenSet(p, 1, combat.Id .. "")
	advance(0.3)
	Care.TrainStop(p, eco.Id)
	Pets.Equip(p, eco.Id)
	advance(0.2)
	local okR4, job4 = Care.Train(p, eco.Id, "Ability")
	T.check(okR4 and job4.From == "Follow" and equippedCount(p, eco.Id) == 0, "care train: an equipped pet trains with From 'Follow'", okR4 and job4.From or tostring(job4))
	Pets.Equip(p, combat.Id)
	Pets.Equip(p, rare.Id)
	local third = pickPet("Combat", "Uncommon") or pickPet("Economy", "Uncommon")
	givePet(p, third.Id)
	Pets.Equip(p, third.Id)
	T.eq(#equipped(p), 3, "care train: (setup) every follow slot is taken while it trains")
	advance(Cat.TrainSeconds(1) + 2)
	T.check(growthOf(p, eco.Id).Ability == 1 and equippedCount(p, eco.Id) == 0, "care train: a follower whose slots are all taken when it finishes stays in the list")
	Pets.Unequip(p, third.Id)
	Pets.Equip(p, eco.Id)
	local okR5, job5 = Care.Train(p, eco.Id, "Defense")
	T.check(okR5 == true and job5.From == "Follow" and equippedCount(p, eco.Id) == 0, "care train: (setup) Defense rank 1 started from the player (From 'Follow')", okR5 and job5.From or tostring(job5))
	advance(Cat.TrainSeconds(1) + 2)
	T.check(growthOf(p, eco.Id).Defense == 1 and equippedCount(p, eco.Id) == 1, "care train: a follower is re-equipped when a slot is free at the end")

	-- the EquippedInfo attribute: level:stage per entry, no entry for the training pet
	setLevel(p, eco.Id, 12)
	advance(0.6)
	local infoAttr = p:GetAttribute(Config.Attr.EquippedInfo) or ""
	local eq = equipped(p)
	local parts = {}
	for i, k in ipairs(eq) do
		parts[i] = tostring((DataS.GetPetLevel(p, k))) .. ":" .. tostring(DataS.GetEvolution(p, k))
	end
	Pets.Refresh(p)
	advance(0.6)
	infoAttr = p:GetAttribute(Config.Attr.EquippedInfo) or ""
	T.eq(infoAttr, table.concat(parts, ","), "care train: EquippedInfo = 'level:stage' per EquippedPets entry (" .. table.concat(eq, ",") .. ")")
	-- UnequipKey takes every copy
	Pets.Unequip(p, combat.Id)
	Pets.Unequip(p, rare.Id)
	Pets.Equip(p, eco.Id)
	Pets.Equip(p, eco.Id)
	T.eq(equippedCount(p, eco.Id), 3, "care train: (setup) three copies equipped")
	T.check(Pets.UnequipKey(p, eco.Id) == 3 and equippedCount(p, eco.Id) == 0 and Pets.UnequipKey(p, eco.Id) == 0, "care train: PetService.UnequipKey takes every copy off (3) and answers 0 when none is equipped")

	-- the remote: Train (key, stat), TrainStop (key), 0.25 s cooldown
	mark = K.logSize()
	cash0 = cashOf(p)
	local nextRank = growthOf(p, eco.Id).Speed + 1
	care(p, "Train", eco.Id, "Attack Speed")
	care(p, "Train", eco.Id, "Speed")
	advance(0.3)
	T.check(growthOf(p, eco.Id).Job ~= nil and growthOf(p, eco.Id).Job.Stat == "Speed" and growthOf(p, eco.Id).Job.Rank == nextRank and cash0 - cashOf(p) == Cat.TrainCost(eco, nextRank), "care train: the remote starts one job ('Attack Speed' reads as Speed; the second request is within the cooldown)", jobText(growthOf(p, eco.Id)))
	care(p, "TrainStop", eco.Id)
	advance(0.3)
	T.check(growthOf(p, eco.Id).Job == nil and cashOf(p) == cash0, "care train: the remote TrainStop refunds")

	c1:Disconnect()
	c2:Disconnect()
	leave(p)
	advance(0.5)
	T.check(info.Folder:GetAttribute("TrainingPets") == nil, "care train: leaving clears TrainingPets from the plot")
	K.flushErrors("p4care_train")
	K.flushWarnings("p4care_train", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- p4care_load: rejoins, two servers, prestige, the retired Gym, ClearSessions
----------------------------------------------------------------------------------------------------
S.p4care_load = guarded("p4care_load", function()
	if not K.needBoot() then
		return
	end
	local Care, Ty, Cat, PCat = PCS(), TS(), TC(), PC()
	if not Care or not Ty or not Cat or not PCat then
		T.fail("care load: PetCareService, TycoonService, TycoonCatalog and PetCatalog load")
		return
	end
	local DataS, Pets = DS(), PS()
	local Config = config()
	local eco = pickPet("Economy", "Common")
	local combat = pickPet("Combat", "Common")
	local done = {}
	local c2 = Care.TrainingDone:Connect(function(pl, key, stat, rank)
		done[#done + 1] = { pl.UserId, key, stat, rank }
	end)
	local function doneFor(uid)
		local n = 0
		for _, d in ipairs(done) do
			if d[1] == uid then
				n = n + 1
			end
		end
		return n
	end

	-- 1) leave mid-training, the time passes, rejoin: the job finishes on load, the pet comes back, one toast
	local uid = newUserId()
	local p = join("CareRejoin", uid)
	local index = claimFree(p)
	if not T.check(index ~= nil, "care load: (precondition) a plot was claimed") then
		leave(p)
		return
	end
	setStations(p, { Garden = 1, Press1 = 1, Kitchen = 1, Gym = 1 })
	DataS.AddCash(p, 100000)
	givePet(p, eco.Id)
	givePet(p, combat.Id)
	Pets.Equip(p, eco.Id)
	Pets.Equip(p, combat.Id)
	local okT, job = Care.Train(p, eco.Id, "Speed")
	T.check(okT == true and job.From == "Follow", "care load: (setup) the follower started Speed training")
	local cashAfter = cashOf(p)
	leave(p)
	advance(1)
	local rec = stored(uid) or {}
	T.check(type(rec.PetGrowth) == "table" and type(rec.PetGrowth[eco.Id]) == "table" and type(rec.PetGrowth[eco.Id].Job) == "table" and rec.PetGrowth[eco.Id].Job.Ends == job.Ends and rec.Cash == cashAfter,
		"care load: the leave save holds the running job and the paid Cash", jobText(rec.PetGrowth and rec.PetGrowth[eco.Id]))
	advance(Cat.TrainSeconds(1) + 5) -- the job ends while the player is away
	local mark = K.logSize()
	local back = join("CareRejoin", uid)
	local g = growthOf(back, eco.Id)
	T.check(g.Speed == 1 and g.Job == nil, "care load: on the rejoin the job that ended meanwhile completes at once: Speed rank 1, no job", jobText(g) .. " S" .. tostring(g.Speed))
	T.check(doneFor(uid) == 1, "care load: TrainingDone fired once for it")
	T.check(equippedCount(back, eco.Id) == 1 and equippedCount(back, combat.Id) == 1, "care load: the pet is re-equipped (From 'Follow') next to the other follower")
	T.check(cashOf(back) == cashAfter, "care load: no refund on a completed job")
	advance(LOAD_TOAST_DELAY + 1.5)
	T.check(toasts(back, "Training done while you were away! " .. eco.Name .. ": Attack Speed Rank 1", "good", mark) == 1, "care load: one toast 'Training done while you were away! ...' after the client is ready", toastsSince(back, mark))
	-- the stored save agrees (idempotent across rejoins)
	leave(back)
	advance(1)
	rec = stored(uid) or {}
	T.check(type(rec.PetGrowth) == "table" and rec.PetGrowth[eco.Id].Speed == 1 and rec.PetGrowth[eco.Id].Job == nil, "care load: the save holds rank 1 and no job")
	local again = join("CareRejoin", uid)
	advance(2)
	T.check(growthOf(again, eco.Id).Speed == 1 and doneFor(uid) == 1 and cashOf(again) == cashAfter, "care load: a third session changes nothing (no second rank, no refund, no second TrainingDone)")
	leave(again)

	-- 2) two servers complete the same job: ONE rank (the rank is a target value), one refund never
	local B, cloneB, releaseB = secondServer("DataServiceCareServerB")
	if T.check(B ~= nil and type(B.MutateGrowth) == "function", "care load: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		local uid2 = newUserId()
		local okRun, errRun = pcall(function()
			local a = join("CareTwo", uid2)
			local idx = claimFree(a)
			T.check(idx ~= nil, "care load: (precondition) a plot for the two-server player")
			setStations(a, { Garden = 1, Press1 = 1, Kitchen = 1, Gym = 1 })
			DataS.AddCash(a, 100000)
			givePet(a, combat.Id)
			local okA, jobA = Care.Train(a, combat.Id, "Defense")
			T.check(okA == true and jobA.Rank == 1, "care load: (setup) server A started Defense 0 -> 1")
			T.eq(DataS.Save(a), true, "care load: (setup) server A saved")
			B.Load(a)
			advance(0.5)
			T.check(B.GetGrowth(a, combat.Id).Job ~= nil and B.GetGrowth(a, combat.Id).Job.Rank == 1, "care load: server B holds the same running job")
			-- the clock passes Ends: B completes it (its own PetCareService would use the same recipe), A's tick completes it too.
			-- B writes its completion only after A's tick: A's autosave (every 90 s) may fall inside the job's minute, and
			-- adopting B's saved completion first would leave A's tick nothing to complete
			local okB = B.MutateGrowth(a, function(gr)
				gr[combat.Id].Defense = gr[combat.Id].Job.Rank
				gr[combat.Id].Job = nil
			end)
			local cashA = cashOf(a)
			advance(Cat.TrainSeconds(1) + 2)
			local ga = growthOf(a, combat.Id)
			T.check(ga.Defense == 1 and ga.Job == nil and doneFor(uid2) == 1 and cashOf(a) == cashA, "care load: server A's tick completes it as well: rank 1 (the target), one TrainingDone, no refund", jobText(ga) .. " D" .. tostring(ga.Defense) .. " done " .. tostring(doneFor(uid2)) .. " cash " .. tostring(cashOf(a)) .. "/" .. tostring(cashA))
			T.check(okB == true and B.Save(a) == true, "care load: server B completes the job and saves")
			T.eq(DataS.Save(a), true, "care load: server A saves")
			local st = (stored(uid2) or {}).PetGrowth or {}
			T.check(type(st[combat.Id]) == "table" and st[combat.Id].Defense == 1 and st[combat.Id].Job == nil, "care load: the store holds Defense 1 exactly once (not 2) and no job (X11)", st[combat.Id] and ("D" .. tostring(st[combat.Id].Defense)) or "nil")
			-- a stop on A after B completed (a stale server): A's stop clears a job B already ended: at most one refund, the rank stays
			local okA2, jobA2 = Care.Train(a, combat.Id, "Defense")
			T.check(okA2 == true and jobA2.Rank == 2 and DataS.Save(a) == true, "care load: (setup) A starts Defense 1 -> 2 and saves")
			B.AddTokens(a, 1)
			T.check(B.Save(a) == true and B.GetGrowth(a, combat.Id).Job ~= nil and B.GetGrowth(a, combat.Id).Job.Rank == 2, "care load: (setup) B adopts the rank-2 job through its save")
			T.check(B.MutateGrowth(a, function(gr)
				gr[combat.Id].Defense = 2
				gr[combat.Id].Job = nil
			end) == true and B.Save(a) == true, "care load: B completes rank 2 (its clock passed Ends) and saves")
			local cashBefore = cashOf(a)
			local okStop, refund = Care.TrainStop(a, combat.Id)
			T.check(okStop == true and refund == jobA2.Cost and cashOf(a) == cashBefore + refund, "care load: A (stale: still holding the job) stops it and refunds once")
			T.eq(DataS.Save(a), true, "care load: A saves")
			st = (stored(uid2) or {}).PetGrowth or {}
			T.check(type(st[combat.Id]) == "table" and st[combat.Id].Defense == 2 and st[combat.Id].Job == nil, "care load: the store keeps B's rank 2 (the max merge) with no job: one rank plus at most one refund in the rollout minutes, never two ranks", st[combat.Id] and ("D" .. tostring(st[combat.Id].Defense)) or "nil")
			leave(a)
		end)
		T.check(releaseB() == true, "care load: server B is released without leaked connections")
		if not okRun then
			error(errRun, 0)
		end
	end

	-- 3) a prestige keeps the running job; the station reset blocks new jobs until it is rebuilt
	local PRESTIGE_READY = { Press1 = 10, Press2 = 10, Collector = 5, Garden = 8, Kitchen = 5, Gym = 5, Vault = 5, House = 4 }
	local pp = join("CarePrestige")
	local idx3 = claimFree(pp)
	if T.check(idx3 ~= nil, "care load: (precondition) a plot for the prestige case") then
		setStations(pp, PRESTIGE_READY)
		DataS.AddCash(pp, 100000)
		givePet(pp, eco.Id)
		local okP1, jobP = Care.Train(pp, eco.Id, "Ability")
		T.check(okP1 == true and Cat.CanPrestige(homeOf(pp)), "care load: (setup) a job runs and the home is ready to prestige")
		local okPr, whyPr = Ty.Prestige(pp)
		advance(1.5)
		local hp = homeOf(pp)
		T.check(okPr == true and hp.Prestige == 1 and (hp.Stations.Gym or 0) == 0, "care load: the prestige resets the Training Place", tostring(whyPr))
		local gp = growthOf(pp, eco.Id)
		T.check(type(gp.Job) == "table" and gp.Job.Ends == jobP.Ends and DataS.TrainingKeys(pp)[eco.Id] == true, "care load: ...the running job survives the prestige", jobText(gp))
		local okNew, whyNew = Care.Train(pp, eco.Id, "Speed")
		T.check(okNew == false and (whyNew == "Build the Training Place at home first" or tostring(whyNew):find("already training", 1, true) ~= nil), "care load: a new job waits for the rebuilt station", tostring(whyNew))
		givePet(pp, combat.Id)
		local okNew2, whyNew2 = Care.Train(pp, combat.Id, "Speed")
		T.check(okNew2 == false and whyNew2 == "Build the Training Place at home first", "care load: ...('Build the Training Place at home first')", tostring(whyNew2))
		advance(Cat.TrainSeconds(1) + 2)
		T.check(growthOf(pp, eco.Id).Ability == 1 and growthOf(pp, eco.Id).Job == nil, "care load: the job finishes after the prestige all the same")
	end
	leave(pp)

	-- 4) Home.Gym is retired: emptied on load with one toast (a migrated save with a stale Phase 3 write, and a Phase 3
	--    save the migration empties)
	local PETS = { [eco.Id] = 2, [combat.Id] = 1 }
	local function oldRecord(userId, gym, migrated)
		local r = {
			Version = 2, Tokens = 0, Pets = PETS, Equipped = {}, Items = {}, Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Discovered = {}, IndexClaimed = {}, Tutorial = { Step = 9, Done = true, Gifted = true }, Cash = 0, Gems = 0, PetLevels = {},
			Home = { Level = 7, Prestige = 0, Stations = { Press1 = 2, Collector = 1, Garden = 1, Kitchen = 1, Gym = 2 }, Garden = {}, Gym = gym, CollectorCash = 0, LastSeen = 0 },
		}
		if migrated then
			r.Migrations = { P4 = true }
		end
		Mock.DataStore.Data[storeKey(userId)] = r
	end
	for _, case in ipairs({ { "migrated save with a Gym pet written by a Phase 3 server", true }, { "Phase 3 save (the migration empties it)", false } }) do
		local uidG = newUserId()
		oldRecord(uidG, { combat.Id, "", eco.Id }, case[2])
		local markG = K.logSize()
		local gp = join("CareGym", uidG)
		advance(0.5)
		local hg = homeOf(gp)
		T.check(hg ~= nil and count(hg.Gym) == 0, "care load: " .. case[1] .. ": Home.Gym is empty after the load", hg and tostring(count(hg.Gym)) or "no home")
		T.check(DataS.FieldableKeys(gp) and listHas(DataS.FieldableKeys(gp), combat.Id), "care load: ...the old gym pet is free again (fieldable)")
		advance(LOAD_TOAST_DELAY + 2)
		T.eq(toasts(gp, "The Gym is now the Training Place: your gym pets are back with you", "info", markG), 1, "care load: ...one toast 'The Gym is now the Training Place: your gym pets are back with you'")
		advance(3)
		T.eq(toasts(gp, "The Gym is now the Training Place", nil, markG), 1, "care load: ...and never a second one in the session")
		leave(gp)
	end
	local uidN = newUserId()
	oldRecord(uidN, {}, true)
	local markN = K.logSize()
	local gn = join("CareGymNone", uidN)
	advance(LOAD_TOAST_DELAY + 2)
	T.eq(toasts(gn, "The Gym is now the Training Place", nil, markN), 0, "care load: a save with an empty Gym gets no toast")

	-- 5) ClearSessions (the developer reset)
	local idxN = claimFree(gn)
	if idxN then
		setStations(gn, { Garden = 1, Press1 = 1, Kitchen = 1, Gym = 1 })
		DataS.AddCash(gn, 10000)
		local okC = Care.Train(gn, combat.Id, "Speed")
		advance(1.2)
		local infoN = spots()[idxN]
		T.check(okC == true and (infoN.Folder:GetAttribute("TrainingPets") or "") ~= "", "care load: (setup) a job runs and TrainingPets is published")
		T.check(Care.ClearSessions(gn) == true, "care load: ClearSessions(player) answers true")
		T.check(infoN.Folder:GetAttribute("TrainingPets") == nil, "care load: ...and drops the published TrainingPets (DevService wipes the saved growth itself)")
		T.check(Care.ClearSessions(nil) == false, "care load: ClearSessions(nil) answers false")
	end
	leave(gn)

	c2:Disconnect()
	K.flushErrors("p4care_load")
	K.flushWarnings("p4care_load", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- p4care_exploits
----------------------------------------------------------------------------------------------------
S.p4care_exploits = guarded("p4care_exploits", function()
	if not K.needBoot() then
		return
	end
	local Care, Cat = PCS(), TC()
	if not Care or not Cat then
		T.fail("care exploits: PetCareService and TycoonCatalog load")
		return
	end
	local DataS = DS()
	local p, index = readyPlayer("CareHack", { Garden = 1, Press1 = 1, Kitchen = 2, Gym = 1 }, 0)
	if not T.check(index ~= nil, "care exploits: (precondition) the player claims a plot") then
		leave(p)
		return
	end
	local combat = pickPet("Combat", "Common")
	givePet(p, combat.Id)
	DataS.AddCash(p, 5000)
	DataS.AddFood(p, "Snack", 200)
	advance(0.5)
	local cash0, snack0, xp0 = cashOf(p), foodOf(p, "Snack"), totalXp(p, combat.Id)
	local errors0 = #Mock.Errors
	local nan, inf = 0 / 0, 1 / 0
	local long = string.rep("S", 5000)
	local junk = {
		{}, { 123 }, { nil, "Snack" }, { long }, { "feed", combat.Id }, { "Prestige" }, { "Collect" }, { "Cook" },
		{ "Feed" }, { "Feed", nil, "Snack" }, { "Feed", 42, "Snack" }, { "Feed", combat.Id, 7 }, { "Feed", {}, {} },
		{ "Feed", long, "Snack" }, { "Feed", "hyb:nope", "Snack" }, { "Feed", combat.Id .. "@Diamond", "Snack" },
		{ "Feed", combat.Id .. "@Normal", "Snack" }, { "Feed", combat.Id, long }, { "Feed", { Key = {}, FoodId = 1 } },
		{ "Feed", combat.Id, { Count = nan } }, { "Feed", combat.Id, { Count = inf } }, { "Feed", combat.Id, { Count = -inf } }, { "Feed", combat.Id, { Count = 0 } },
		{ "Feed", combat.Id, { Count = 11 } }, { "Feed", combat.Id, { Count = 1e9 } }, { "Feed", combat.Id, { Count = "5" } }, { "Feed", combat.Id, { Food = {} } },
		{ "Feed", combat.Id, { Food = "snack" } }, { "Feed", combat.Id, { Count = 2, Food = "Cake" } },
		{ "Evolve" }, { "Evolve", 5 }, { "Evolve", {} }, { "Evolve", long }, { "Evolve", combat.Id }, { "Evolve", { Key = combat.Id, Stage = 2 } },
		{ "Train" }, { "Train", combat.Id }, { "Train", combat.Id, 5 }, { "Train", combat.Id, {} }, { "Train", combat.Id, long }, { "Train", combat.Id, "Luck" },
		{ "Train", 5, "Speed" }, { "Train", long, "Speed" }, { "Train", { Key = {}, Stat = {} } }, { "Train", "hyb:nope", "Speed" },
		{ "TrainStop" }, { "TrainStop", 5 }, { "TrainStop", {} }, { "TrainStop", long }, { "TrainStop", combat.Id },
		{ "GymSet", 1, combat.Id }, { "GymSet", nan, combat.Id }, { "Cook", "Snack", nan }, { "Cook", long, 1 },
	}
	for _, args in ipairs(junk) do
		care(p, args[1], args[2], args[3])
		advance(1.1) -- past every cooldown: each junk request is really evaluated
	end
	local h = homeOf(p)
	T.check(cashOf(p) == cash0 and foodOf(p, "Snack") == snack0 and totalXp(p, combat.Id) == xp0 and DataS.GetEvolution(p, combat.Id) == 0 and count(DataS.GetGrowthMap(p)) == 0 and next(h.Gym) == nil,
		"care exploits: " .. #junk .. " junk / NaN / inf / negative / wrong-type / oversized PetCare requests change nothing (Cash, Food, XP, stage, growth, Gym)",
		"cash " .. cashOf(p) .. " food " .. foodOf(p, "Snack") .. " xp " .. totalXp(p, combat.Id))
	T.eq(#Mock.Errors, errors0, "care exploits: ...and raise no script error")

	-- spam: one Feed per cooldown, the burst budget, every paid feed gives exactly its XP
	DataS.SpendFood(p, "Snack", foodOf(p, "Snack"))
	DataS.AddCash(p, 10000000)
	advance(2)
	local c = cashOf(p)
	local x = totalXp(p, combat.Id)
	local lv = DataS.GetPetLevel(p, combat.Id)
	for _ = 1, 40 do
		care(p, "Feed", combat.Id)
	end
	advance(0.05)
	T.check(c - cashOf(p) == Cat.FeedPrice(combat, lv) and totalXp(p, combat.Id) - x == Cat.FeedXp(lv, 2), "care exploits: 40 Feed requests in one frame feed exactly once (cooldown)", "cash -" .. (c - cashOf(p)))
	advance(3) -- refill the budget
	local sent, t0 = 0, os.clock()
	local before, startLevel, startXp = totalXp(p, combat.Id)
	local cashBefore = cashOf(p)
	local fedN = 0
	local conn = Care.Fed:Connect(function(pl, key)
		if pl == p and key == combat.Id then
			fedN = fedN + 1
		end
	end)
	for _ = 1, 80 do
		care(p, "Feed", combat.Id)
		sent = sent + 1
		advance(0.11)
	end
	conn:Disconnect()
	local elapsed = os.clock() - t0
	T.check(fedN >= 1 and fedN < sent and fedN <= 12 + 6 * elapsed + 1, "care exploits: a steady flood of Feed requests is held to the burst budget (" .. fedN .. " of " .. sent .. " in " .. string.format("%.1f", elapsed) .. " s)")
	-- replay the accepted feeds along the curve: the Cash and XP taken equal the sum of the per-feed prices / XP
	local cashW, xpW = planBatch(combat, startLevel, startXp, fedN, 2, 100)
	T.check(cashBefore - cashOf(p) == cashW and totalXp(p, combat.Id) - before == xpW, "care exploits: every accepted feed was paid at the level it was eaten at and gave exactly its XP (no XP for free, no Cash lost)",
		"cash -" .. (cashBefore - cashOf(p)) .. " want " .. cashW .. ", xp +" .. (totalXp(p, combat.Id) - before) .. " want " .. xpW)

	-- someone else's pets, prompts and plot
	local q = join("CareHack2")
	DataS.AddCash(q, 1000)
	local qc, pc = cashOf(q), cashOf(p)
	local px = totalXp(p, combat.Id)
	advance(0.3)
	care(q, "Feed", combat.Id)
	care(q, "Evolve", combat.Id)
	advance(0.3)
	care(q, "Train", combat.Id, "Speed")
	advance(0.3)
	T.check(cashOf(q) == qc and cashOf(p) == pc and totalXp(p, combat.Id) == px and count(DataS.GetGrowthMap(p)) == 0, "care exploits: feeding / evolving / training a pet you do not own does nothing (not even to its owner's copy)")
	local kitchen = stationOf(index, "Kitchen")
	local gym = stationOf(index, "Gym")
	local feedPrompt, trainPrompt = promptIn(kitchen, "FeedPrompt"), promptIn(gym, "TrainPrompt")
	if feedPrompt and trainPrompt then
		local mark = K.logSize()
		Mock.Trigger(feedPrompt, q)
		Mock.Trigger(trainPrompt, q)
		advance(0.5)
		T.check(#panels(q, mark) == 0 and #panels(p, mark) == 0 and cashOf(q) == qc and cashOf(p) == pc, "care exploits: another player's presses on the owner's prompts open nothing and spend nothing")
		-- a stray prompt that only looks like ours
		local fake = Instance.new("ProximityPrompt")
		fake.Name = "FeedPrompt"
		fake:SetAttribute("OwnerUserId", q.UserId)
		fake:SetAttribute("CareMade", true)
		fake.Parent = kitchen.PrimaryPart or kitchen:FindFirstChildWhichIsA("BasePart", true)
		mark = K.logSize()
		Mock.Trigger(fake, q)
		advance(0.5)
		T.eq(#panels(q, mark), 0, "care exploits: a FeedPrompt the service did not make on someone else's plot is ignored")
		fake:Destroy()
	end
	leave(q)
	T.check(cashOf(p) >= 0, "care exploits: Cash never goes negative")
	leave(p)
	K.flushErrors("p4care_exploits")
	K.flushWarnings("p4care_exploits", { "[DataService]" })
end)

return S
