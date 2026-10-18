-- smoke_p4_garden.lua: Phase 4 rainbow coins (ARCHITECTURE_V3.md "Phase 4 build contract" 3.1-3.3, 5.3, 7 X1-X6 / X20,
-- 8.1). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half:
--   SERVER (wave 2, tycoon): every scenario runs on the booted game (Main.server.lua) through TycoonService:
--   p4garden_coins   the free Pet Garden; an Economy pet eats a meal every Coins.MealSeconds and pops a coin worth
--                    Food x PetPower x 1.25^stars (a NEW placement's first coin after a full meal); a Combat pet earns
--                    1/1.6 of an Economy pet of the same rarity (PetPower); IncomePerSecond / GardenPets / GardenInfo /
--                    GardenSlots / CoinPiles / CollectorCash attributes; the invariant sum(piles) + Welcome ==
--                    CollectorCash while coins flow; no Lucky coin at Garden L1, Lucky coins (x5, '*') at Garden L8;
--                    the pile cap (PileSeconds x the pet's rate) -> 'F', the pet naps, the bank stops; no Instance per
--                    coin on the server; the stored evolution stage multiplies the coin
--   p4garden_scoop   the owner within ScoopRadius (6 studs without a Magnet, 9 with Coin Magnet L1) and 10 studs
--                    vertically is paid exactly once (Cash + CollectorCash constant, CoinsScooped(player, amount),
--                    whole Cash only, fractions stay), a second player on the lawn scoops nothing (touch, Collect,
--                    their own plot's Collect), HomeAction 'Collect' = scoop in range (old clients); GardenSet for any
--                    role / a training key refused with the time left / a key in a running battle refused / the X5
--                    timer rule (remove + re-place keeps the meal; a new placement waits a full meal); resting keys above
--                    the open count keep their place but do not eat (X20); LegacySlots open more places; a training pet
--                    in the Garden stops eating until its job ends
--   p4garden_ledger  exactly once across the session edges (X4 / X6): leave + rejoin -> the coins left on the lawn wait
--                    in the Welcome-back pile (W=5) and pay once; the Vault's offline coins go INTO the bank with
--                    LastSeen (Cash untouched, paid once, the 'Welcome back! Your pets made' toast); a rebase (the
--                    ProfileRebased signal) rebuilds the ledger from the merged bank; a provisional load (DataStore
--                    outage) claims nothing until the recovery, then the stored bank waits as the Welcome-back pile; a
--                    DataStore outage during scoops loses nothing (the orphan save carries Cash and the bank); a
--                    Prestige mid-pile zeroes bank + piles, keeps the Garden at L1, opens place 4 and clears LegacySlots;
--                    the one-time welcome toast of a migrated veteran (P4Veteran -> P4Welcome, never twice);
--                    ClearCoins (the developer reset)
--   CLIENT (wave 3, homefx): client_p4garden_* scenarios are added to this file by the homefx engineer (heaps follow
--   CoinPiles, the zip and "+$" only for the owner and at the pile, others' piles dimmed, pools <= 40).
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor = math.abs, math.floor

local S = {}
if CONTEXT ~= "server" then
	return S -- the client half (client_p4garden_*) lands in wave 3
end

local advance, config, mod = K.advance, K.config, K.mod

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

local function TS()
	return requireAt("server/Services/TycoonService")
end
local function TC()
	return requireAt("shared/TycoonCatalog")
end
local function PK()
	return requireAt("shared/PetKeys")
end

local userSeq = 0
local function join(prefix)
	userSeq = userSeq + 1
	local p = Mock.AddPlayer(prefix .. userSeq, 964000 + userSeq)
	advance(1.0)
	return p
end

local function rejoin(name, userId)
	local p = Mock.AddPlayer(name, userId)
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

local function freeIndex(skip)
	local SS = mod("SpotService")
	for i = 1, config().Lobby.SpotCount do
		if spots()[i] and not SS.GetOwner(i) and i ~= skip then
			return i
		end
	end
	return nil
end

local function claimPromptOf(index)
	local info = spots()[index]
	if info and info.Folder then
		for _, d in ipairs(info.Folder:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
				return d
			end
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" and d:GetAttribute("SpotIndex") == index then
			return d
		end
	end
	return nil
end

-- walks to the gate (just outside it, like a player) and presses E on its ClaimPrompt
local function claim(p, index)
	local prompt = claimPromptOf(index)
	local SS = mod("SpotService")
	local gate = SS.GateCFrame(spots()[index])
	if gate and p.Character then
		Mock.Teleport(p, gate * CFrame.new(0, 3, -5))
	end
	if prompt then
		Mock.Trigger(prompt, p)
	end
	advance(0.6)
	return prompt ~= nil
end

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

local function homeAction(p, action, arg)
	Mock.FromClient(remote("HomeAction"), p, action, arg)
end

local function cashOf(p)
	return mod("DataService").GetCash(p)
end

local function bankOf(p)
	local home = mod("DataService").GetHome(p)
	return home and home.CollectorCash or 0
end

local function givePet(p, key, n)
	local DataS = mod("DataService")
	local prof = DataS.GetProfile(p)
	local ok = PK().Add(prof, key, n or 1)
	DataS.MarkDirty(p)
	return ok
end

-- an Economy and a Combat pet of the SAME rarity (the 1/1.6 rule reads exactly), plus a Legendary-or-better Economy
local function petPair()
	local PC = K.M["shared/PetCatalog"]
	local byRarity = {}
	for _, def in ipairs(PC.Pets) do
		if def.Rarity ~= "Secret" and not def.EventOnly then
			local r = byRarity[def.Rarity]
			if not r then
				r = {}
				byRarity[def.Rarity] = r
			end
			if def.Role == "Economy" and not r.Eco then
				r.Eco = def
			elseif def.Role == "Combat" and not r.Combat then
				r.Combat = def
			end
		end
	end
	for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }) do
		local r = byRarity[rarity]
		if r and r.Eco and r.Combat then
			return r.Eco, r.Combat
		end
	end
	return nil, nil
end

-- the first Epic-or-rarer Economy pet (it evolves twice)
local function epicEco()
	local PC = K.M["shared/PetCatalog"]
	for _, rarity in ipairs({ "Epic", "Legendary", "Mythic" }) do
		for _, def in ipairs(PC.Pets) do
			if def.Rarity == rarity and def.Role == "Economy" and not def.EventOnly then
				return def
			end
		end
	end
	return nil
end

-- the owner stands at a world point (the root ~3 studs over it)
local function standAt(p, pos, dx, dz)
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(dx or 0, 3, dz or 0)))
end

-- far from every garden (the plaza, where players spawn)
local function away(p)
	Mock.Teleport(p, config().Lobby.Origin + Vector3.new(0, 4, 0))
end

local function pileOf(Ty, p, slot)
	local piles = Ty.Piles(p)
	return piles and piles[slot] or nil
end

local function liveSum(Ty, p)
	local piles = Ty.Piles(p)
	if not piles then
		return 0, 0
	end
	local total, count = 0, 0
	for slot, pile in pairs(piles) do
		if slot ~= "W" then
			total = total + pile.Value
			count = count + pile.Coins
		end
	end
	return total, count, piles.W and piles.W.Value or 0
end

local function entryOf(p, def, key)
	local DataS = mod("DataService")
	return { Def = def, Level = DataS.GetPetLevel(p, key or def.Id) or 1, Tier = "Normal", Stage = DataS.GetEvolution(p, key or def.Id) or 0, Key = key or def.Id }
end

-- a new home with the free Pet Garden built (the only pad of a fresh home)
local function startHome(Ty, p)
	local index = freeIndex()
	claim(p, index)
	local ok, lvl = Ty.Buy(p, "Garden")
	advance(0.3)
	return index, spots()[index], ok, lvl
end

----------------------------------------------------------------------------------------------------
-- p4garden_coins
----------------------------------------------------------------------------------------------------
S.p4garden_coins = guarded("p4garden_coins", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local Ty, Cat = TS(), TC()
	if not Ty or not Cat then
		T.fail("p4 garden: TycoonService and TycoonCatalog load")
		return
	end
	for _, fn in ipairs({ "PileSeconds", "CollectorCap", "CoinsWaiting", "GardenSet", "GoHome", "OpenHomePortal", "ClearCoins", "Collect", "Piles" }) do
		T.check(type(Ty[fn]) == "function", "p4 garden: TycoonService." .. fn .. " is a function")
	end
	for _, sig in ipairs({ "CoinsScooped", "PortalUsed" }) do
		T.check(type(Ty[sig]) == "table" and type(Ty[sig].Connect) == "function", "p4 garden: signal TycoonService." .. sig)
	end
	local Eco, Combat = petPair()
	if not T.check(Eco ~= nil and Combat ~= nil, "p4 garden: (precondition) an Economy and a Combat pet of one rarity") then
		return
	end
	local meal = Cat.Coins.MealSeconds
	local p = join("GardCoin")
	local cash0 = cashOf(p)
	local index, info, okGarden = startHome(Ty, p)
	local home = Ty.GetHome(p)
	T.check(okGarden == true and home and home.Stations.Garden == 1 and cashOf(p) == cash0 and home.Level == 1,
		"p4 garden: the Pet Garden is the free first station (Home Level 1)")
	T.eq(info.Folder:GetAttribute("GardenSlots"), 3, "p4 garden: the plot replicates GardenSlots = 3 (3 + 0 stars)")
	T.eq(info.Folder:GetAttribute("CollectorCash"), 0, "p4 garden: ...CollectorCash 0")
	T.eq(info.Folder:GetAttribute("IncomePerSecond"), 0, "p4 garden: ...IncomePerSecond 0: no pet in the garden = no coins")
	T.check((info.Folder:GetAttribute("CoinPiles") or "") == "", "p4 garden: ...and no coin pile yet")
	away(p)
	advance(12)
	T.eq(bankOf(p), 0, "p4 garden: an empty garden makes nothing (12 s)")

	-- an Economy pet: no coin before a full meal, one coin worth Food x PetPower after it
	givePet(p, Eco.Id, 1)
	givePet(p, Combat.Id, 1)
	local mark = K.logSize()
	local okSet, whySet = Ty.GardenSet(p, 1, Eco.Id)
	T.check(okSet == true, "p4 garden: GardenSet(1, Economy) places the pet", tostring(whySet))
	T.check(K.notified(p, "working in your Garden", "good", mark), "p4 garden: ...with a toast")
	home = Ty.GetHome(p)
	T.eq(home.Garden[1], Eco.Id, "p4 garden: Home.Garden[1] holds the key")
	T.eq(info.Folder:GetAttribute("GardenPets"), "1=" .. Eco.Id, "p4 garden: GardenPets replicates the placed key")
	T.eq(info.Folder:GetAttribute("GardenInfo"), "1=1:0", "p4 garden: GardenInfo replicates level:stage (1:0)")
	local coinE = Cat.CoinValue(home, Cat.PetPower(entryOf(p, Eco)), 0)
	local foodNow = Cat.FoodOf(home)
	T.check(near(coinE, Cat.Coins.GrassFood * Cat.PetPower(entryOf(p, Eco)), 1e-6) and foodNow == Cat.Coins.GrassFood,
		"p4 garden: a Garden L1 coin = GrassFood 12 x PetPower (" .. string.format("%.2f", coinE) .. ")")
	local incomeE = Cat.IncomePerSecond(home, { [1] = entryOf(p, Eco) }, 0)
	T.check(near(Ty.IncomePerSecond(p), incomeE, 1e-6) and near(info.Folder:GetAttribute("IncomePerSecond"), incomeE, 0.051),
		"p4 garden: IncomePerSecond = Food / 8 x PetPower (" .. string.format("%.3f", incomeE) .. "/s), replicated")
	advance(meal - 0.5)
	T.eq(bankOf(p), 0, "p4 garden: a NEW placement's first coin waits a full meal (nothing at 7.5 s)")
	T.check((info.Folder:GetAttribute("CoinPiles") or "") == "", "p4 garden: ...no pile yet")
	advance(1.6)
	T.check(near(bankOf(p), coinE, 1e-6), "p4 garden: one coin popped after the meal (bank = the coin)", tostring(bankOf(p)))
	local pile1 = pileOf(Ty, p, 1)
	T.check(pile1 ~= nil and pile1.Coins == 1 and near(pile1.Value, coinE, 1e-6) and not pile1.Lucky and not pile1.Full,
		"p4 garden: the coin sits in place 1's pile (1 coin, its value)")
	T.eq(info.Folder:GetAttribute("CoinPiles"), "1=1", "p4 garden: CoinPiles '1=1' (heap stage 1 for one coin)")
	T.eq(info.Folder:GetAttribute("CollectorCash"), floor(coinE), "p4 garden: CollectorCash replicates the whole bank")
	local point = Cat.CoinPoint(1)
	local gardenDef = Cat.Get("Garden")
	local want = (info.PlotCFrame * gardenDef.Slot.CFrame):PointToWorldSpace(point)
	T.check(pile1 and typeof(pile1.Pos) == "Vector3" and (pile1.Pos - want).Magnitude < 1e-3,
		"p4 garden: the pile's world point = plot frame x Garden station frame x CoinPoint(1)")

	-- a Combat pet of the same rarity: 1/1.6 of the Economy coin
	local okC = Ty.GardenSet(p, 2, Combat.Id)
	T.check(okC == true, "p4 garden: GardenSet accepts a Combat pet (any role works)")
	home = Ty.GetHome(p)
	local coinC = Cat.CoinValue(home, Cat.PetPower(entryOf(p, Combat)), 0)
	T.check(near(coinC * 1.6, coinE, 1e-6), "p4 garden: a Combat pet's coin is 1/1.6 of an Economy pet's at the same rarity / level",
		string.format("%.3f vs %.3f", coinC, coinE))
	local bankBefore = bankOf(p)
	advance(meal + 1.1)
	local pile2 = pileOf(Ty, p, 2)
	T.check(pile2 ~= nil and pile2.Coins == 1 and near(pile2.Value, coinC, 1e-6), "p4 garden: the Combat pet popped its smaller coin after its meal", pile2 and tostring(pile2.Value) or "no pile")
	T.check(near(bankOf(p), bankBefore + coinC + coinE, 1e-6) or near(bankOf(p), bankBefore + coinC, 1e-6),
		"p4 garden: the bank took exactly the new coins", tostring(bankOf(p) - bankBefore))
	T.check(near(Ty.IncomePerSecond(p), Cat.IncomePerSecond(home, { [1] = entryOf(p, Eco), [2] = entryOf(p, Combat) }, 0), 1e-6),
		"p4 garden: IncomePerSecond sums both pets")
	T.eq(info.Folder:GetAttribute("GardenPets"), "1=" .. Eco.Id .. ";2=" .. Combat.Id, "p4 garden: GardenPets lists both (slot order)")
	T.eq(info.Folder:GetAttribute("GardenInfo"), "1=1:0;2=1:0", "p4 garden: GardenInfo lists both")

	-- the invariant while coins flow: sum(piles) + Welcome == CollectorCash, every coin is a plain coin at Garden L1
	local parts0 = #info.Folder:GetDescendants()
	local okInv, okPlain = true, true
	for _ = 1, 5 do
		advance(meal)
		local live, count, welcome = liveSum(Ty, p)
		if not near(live + welcome, bankOf(p), 1e-6) then
			okInv = false
		end
		local p1, p2 = pileOf(Ty, p, 1), pileOf(Ty, p, 2)
		if (p1 and (p1.Lucky or not near(p1.Value, p1.Coins * coinE, 1e-6))) or (p2 and (p2.Lucky or not near(p2.Value, p2.Coins * coinC, 1e-6))) then
			okPlain = false
		end
	end
	T.check(okInv, "p4 garden: sum(live piles) + Welcome-back == CollectorCash at every check while coins flow (X4 invariant)")
	T.check(okPlain, "p4 garden: at Garden L1 (Lucky 0) every coin is a plain coin (value = coins x coin, no '*')")
	T.eq(#info.Folder:GetDescendants(), parts0, "p4 garden: no Instance per coin on the server (the plot's descendants did not grow)")
	local p1 = pileOf(Ty, p, 1)
	T.check(p1 and p1.Coins >= 6 and info.Folder:GetAttribute("CoinPiles"):match("^1=" .. Cat.HeapStage(p1.Coins) .. ";2=%d$") ~= nil,
		"p4 garden: CoinPiles follows the heap stages (" .. tostring(info.Folder:GetAttribute("CoinPiles")) .. ")")

	-- the stored evolution stage multiplies the coin (never the level alone)
	local evoDef = epicEco()
	if evoDef then
		givePet(p, evoDef.Id, 1)
		DataS.SetPetLevel(p, evoDef.Id, 20)
		Ty.GardenSet(p, 3, evoDef.Id)
		home = Ty.GetHome(p)
		local plain = Cat.CoinValue(home, Cat.PetPower(entryOf(p, evoDef)), 0)
		T.check(near(plain, Cat.Coins.GrassFood * Cat.PetPower({ Def = evoDef, Level = 20, Tier = "Normal", Stage = 0 }), 1e-6),
			"p4 garden: a level-20 pet that has not pressed EVOLVE earns the plain level-20 coin")
		T.eq(DataS.SetEvolution(p, evoDef.Id, 1), true, "p4 garden: (precondition) SetEvolution stage 1")
		advance(0.1)
		local evolved = Cat.CoinValue(Ty.GetHome(p), Cat.PetPower(entryOf(p, evoDef)), 0)
		T.check(near(evolved, plain * 1.25, 1e-6), "p4 garden: the STORED stage 1 multiplies the coin by 1.25", string.format("%.3f vs %.3f", evolved, plain))
		advance(meal + 1.1)
		local p3 = pileOf(Ty, p, 3)
		T.check(p3 ~= nil and near(p3.Value, evolved, 1e-6) and info.Folder:GetAttribute("GardenInfo") == "1=1:0;2=1:0;3=20:1",
			"p4 garden: ...its first coin is the evolved coin and GardenInfo says 20:1", tostring(info.Folder:GetAttribute("GardenInfo")))
		Ty.GardenSet(p, 3, nil)
	else
		T.info("*evolution coin check skipped: no Epic+ Economy pet")
	end

	-- Lucky coins at Garden L8 (Lucky 0.15): three Economy copies, 24 meals
	Ty.GardenSet(p, 2, nil)
	givePet(p, Eco.Id, 2)
	DataS.MutateHome(p, function(h)
		h.Stations.Garden = 8
		h.Stations.Press1 = 1
		h.Stations.Collector = 1 -- Coin Magnet L1: PileSeconds 300 (no pile fills during the 24 meals)
		h.Level = Cat.HomeLevelOf(h)
	end)
	advance(1.2)
	T.check(Cat.LuckyChance(Ty.GetHome(p)) >= 0.15 - 1e-9, "p4 garden: (precondition) Garden L8 rolls Lucky coins at 15%")
	Ty.ClearCoins(p)
	Ty.GardenSet(p, 2, Eco.Id)
	Ty.GardenSet(p, 3, Eco.Id)
	home = Ty.GetHome(p)
	local coin8 = Cat.CoinValue(home, Cat.PetPower(entryOf(p, Eco)), 0)
	advance(24 * meal + 1.5)
	local live, count = liveSum(Ty, p)
	local luckies = (live - count * coin8) / ((Cat.Coins.LuckyMult - 1) * coin8)
	T.check(count >= 60 and near(luckies, floor(luckies + 0.5), 1e-6) and luckies >= 1 and luckies <= count * 0.5,
		"p4 garden: Lucky coins are worth x5 (over " .. count .. " coins: " .. string.format("%.0f", luckies) .. " Lucky)")
	local piles = Ty.Piles(p)
	local starsOk, anyStar = true, false
	local text = info.Folder:GetAttribute("CoinPiles") or ""
	for slot = 1, 3 do
		local pile = piles[slot]
		local hasLucky = pile and pile.Lucky == true
		local inText = text:find(tostring(slot) .. "=%d%*") ~= nil
		if hasLucky ~= inText then
			starsOk = false
		end
		if hasLucky and not near(pile.Value, pile.Coins * coin8, 1e-6) then
			anyStar = true
		end
	end
	T.check(starsOk and anyStar, "p4 garden: a pile with a Lucky coin inside shows '*' in CoinPiles (" .. text .. ")")
	T.check(near(live, bankOf(p), 1e-6), "p4 garden: ...and the bank still equals the piles")

	-- the pile cap: one pet, PileSeconds (Magnet L1 300 s) of its coins, then 'F' and the pet naps until scooped
	Ty.GardenSet(p, 2, nil)
	Ty.GardenSet(p, 3, nil)
	Ty.ClearCoins(p)
	home = Ty.GetHome(p)
	local pileSeconds = Cat.PileSeconds(home)
	T.eq(Ty.PileSeconds(p), pileSeconds, "p4 garden: TycoonService.PileSeconds(player) = TycoonCatalog.PileSeconds(home) (" .. pileSeconds .. ")")
	T.eq(Ty.CollectorCap(p), pileSeconds, "p4 garden: ...CollectorCap is its alias")
	local cap = pileSeconds * coin8 / meal * Cat.LuckyEV(home)
	advance(pileSeconds + 4 * meal)
	local full = pileOf(Ty, p, 1)
	T.check(full ~= nil and full.Full == true and full.Value >= cap - 1e-6 and full.Value <= cap + Cat.Coins.LuckyMult * coin8 + 1e-6,
		"p4 garden: the pile fills to PileSeconds x the pet's rate and is marked Full", full and string.format("%.1f of %.1f", full.Value, cap) or "no pile")
	T.check((info.Folder:GetAttribute("CoinPiles") or ""):match("^1=5F%*?$") ~= nil, "p4 garden: CoinPiles '1=5F' (24+ coins, full)", tostring(info.Folder:GetAttribute("CoinPiles")))
	local bankFull = bankOf(p)
	advance(3 * meal)
	T.check(near(bankOf(p), bankFull, 1e-6), "p4 garden: a napping pet eats nothing: the bank stops growing", tostring(bankOf(p) - bankFull))
	T.check(near(Ty.CoinsWaiting(p), floor(bankFull), 1e-6), "p4 garden: CoinsWaiting = the whole Cash on the lawn")
	local cashBefore = cashOf(p)
	standAt(p, full.Pos)
	advance(0.4)
	T.eq(cashOf(p) - cashBefore, floor(bankFull), "p4 garden: scooping the full pile pays its whole Cash")
	T.check((info.Folder:GetAttribute("CoinPiles") or ""):find("F", 1, true) == nil, "p4 garden: ...the 'F' is gone")
	away(p)
	advance(meal + 1.5)
	local again = pileOf(Ty, p, 1)
	T.check(again ~= nil and again.Coins >= 1 and not again.Full, "p4 garden: ...and the pet eats again within a meal")
	leave(p)
	K.flushErrors("p4garden_coins")
	K.flushWarnings("p4garden_coins", { "HomeBuilder is missing" })
end)

----------------------------------------------------------------------------------------------------
-- p4garden_scoop
----------------------------------------------------------------------------------------------------
S.p4garden_scoop = guarded("p4garden_scoop", function()
	if not K.needBoot() then
		return
	end
	local DataS, SS = mod("DataService"), mod("SpotService")
	local Ty, Cat = TS(), TC()
	if not Ty or not Cat then
		T.fail("p4 garden: TycoonService and TycoonCatalog load")
		return
	end
	local Eco, Combat = petPair()
	if not Eco then
		T.fail("p4 garden scoop: (precondition) pets")
		return
	end
	local meal = Cat.Coins.MealSeconds
	local p = join("GardScoop")
	local index, info = startHome(Ty, p)
	givePet(p, Eco.Id, 3)
	givePet(p, Combat.Id, 1)
	away(p)
	Ty.GardenSet(p, 1, Eco.Id)
	Ty.GardenSet(p, 2, Eco.Id)
	advance(3 * meal + 1.5)
	-- freeze production: the pets leave the garden, their piles stay on the lawn
	Ty.GardenSet(p, 1, nil)
	Ty.GardenSet(p, 2, nil)
	advance(1.1)
	local pile1, pile2 = pileOf(Ty, p, 1), pileOf(Ty, p, 2)
	if not T.check(pile1 and pile2 and pile1.Coins >= 2 and pile2.Coins >= 2, "p4 garden scoop: (precondition) two piles on the lawn") then
		leave(p)
		return
	end
	local total0 = cashOf(p) + bankOf(p)
	T.check(near(pile1.Value + pile2.Value, bankOf(p), 1e-6), "p4 garden scoop: the piles equal the bank")
	local radius = Cat.ScoopRadius(Ty.GetHome(p))
	T.eq(radius, Cat.Coins.BaseRadius, "p4 garden scoop: ScoopRadius without a Coin Magnet = 6 studs")

	-- a second player on the lawn: nothing (X2), also with HomeAction Collect from their position / their own plot
	local stranger = join("GardStranger")
	local cashS = cashOf(stranger)
	standAt(stranger, pile1.Pos)
	advance(1.0)
	local mark = K.logSize()
	homeAction(stranger, "Collect")
	advance(0.3)
	T.check(cashOf(stranger) == cashS and near(bankOf(p), pile1.Value + pile2.Value, 1e-6) and pileOf(Ty, p, 1) ~= nil,
		"p4 garden scoop: another player standing on the owner's coins scoops nothing (touch or Collect)")
	T.check(K.notified(stranger, "Claim a home first", nil, mark), "p4 garden scoop: ...their Collect answers 'Claim a home first'")
	local otherIndex = freeIndex(index)
	claim(stranger, otherIndex)
	standAt(stranger, pile1.Pos)
	mark = K.logSize()
	homeAction(stranger, "Collect")
	advance(0.5)
	T.check(cashOf(stranger) == cashS and near(bankOf(p), pile1.Value + pile2.Value, 1e-6),
		"p4 garden scoop: a plot owner standing in someone else's garden scoops nothing of theirs")
	T.check(K.notified(stranger, "Nothing to scoop yet", nil, mark), "p4 garden scoop: ...'Nothing to scoop yet' (their own lawn is empty)")

	-- the owner just outside the radius: nothing; inside: paid exactly once, whole Cash, fractions stay
	local awayDir = pile1.Pos - pile2.Pos
	awayDir = Vector3.new(awayDir.X, 0, awayDir.Z).Unit -- away from pile 2, so only pile 1's distance counts
	standAt(p, pile1.Pos, awayDir.X * (radius + 1.5), awayDir.Z * (radius + 1.5))
	advance(0.6)
	T.check(near(bankOf(p), pile1.Value + pile2.Value, 1e-6), "p4 garden scoop: the owner 7.5 studs from the pile (radius 6) scoops nothing")
	Mock.Teleport(p, CFrame.new(pile1.Pos + Vector3.new(0, 11.5, 0)))
	advance(0.6)
	T.check(near(bankOf(p), pile1.Value + pile2.Value, 1e-6), "p4 garden scoop: ...nor 11.5 studs above it (10 studs of vertical reach)")
	local scooped = {}
	local conn = Ty.CoinsScooped:Connect(function(pl, amount)
		scooped[#scooped + 1] = { pl, amount }
	end)
	local cashBefore, bankBefore = cashOf(p), bankOf(p)
	local inRange = pile1.Value
	local d12 = K.planar(pile1.Pos, pile2.Pos)
	if d12 <= radius then
		inRange = inRange + pile2.Value
	end
	standAt(p, pile1.Pos)
	advance(0.3)
	local paid = cashOf(p) - cashBefore
	T.eq(paid, floor(inRange), "p4 garden scoop: the owner within the radius is paid the whole Cash of the piles in range (" .. floor(inRange) .. ")")
	T.check(near(bankOf(p), bankBefore - paid, 1e-6), "p4 garden scoop: ...the bank lost exactly that (MutateHome then AddCash)")
	T.check(near(cashOf(p) + bankOf(p), total0, 1e-6), "p4 garden scoop: Cash + CollectorCash is constant across the scoop (paid once)")
	T.check(#scooped == 1 and scooped[1][1] == p and scooped[1][2] == paid, "p4 garden scoop: CoinsScooped(player, amount) fired once with the amount", tostring(#scooped))
	local frac = inRange - floor(inRange)
	local left1 = pileOf(Ty, p, 1)
	T.check((frac < 1e-6 and left1 == nil) or (frac >= 1e-6 and left1 ~= nil and near(left1.Value, frac, 1e-6) and left1.Coins == 0),
		"p4 garden scoop: whole Cash only: the fraction below one Cash stays on the lawn (" .. string.format("%.3f", frac) .. ")")
	advance(1.0)
	T.eq(cashOf(p) - cashBefore, paid, "p4 garden scoop: standing still pays nothing more (the piles are gone)")
	T.eq(#scooped, 1, "p4 garden scoop: ...and CoinsScooped stays at one")
	conn:Disconnect()

	-- HomeAction "Collect" (old clients / tests) = scoop in range
	if d12 > radius and pileOf(Ty, p, 2) then
		local p2v = pileOf(Ty, p, 2).Value
		away(p)
		homeAction(p, "Collect")
		advance(0.3)
		T.check(near(bankOf(p), p2v + (left1 and left1.Value or 0), 1e-6), "p4 garden scoop: HomeAction 'Collect' far from the coins scoops nothing")
		cashBefore = cashOf(p)
		standAt(p, pile2.Pos)
		mark = K.logSize()
		homeAction(p, "Collect")
		advance(0.1)
		T.eq(cashOf(p) - cashBefore, floor(p2v), "p4 garden scoop: HomeAction 'Collect' at a pile scoops it (the 0.25 s loop would too)")
		T.check(K.notified(p, "scooped", "good", mark), "p4 garden scoop: ...with a '+$ scooped!' toast")
	end
	T.check(near(cashOf(p) + bankOf(p), total0, 1e-6), "p4 garden scoop: Cash + CollectorCash still constant")

	-- the Coin Magnet: radius 9 at L1
	DataS.AddCash(p, 1000)
	Ty.Buy(p, "Press1")
	local okMag = Ty.Buy(p, "Collector")
	T.check(okMag == true and Cat.ScoopRadius(Ty.GetHome(p)) == 9, "p4 garden scoop: Coin Magnet L1 -> ScoopRadius 9")
	Ty.ClearCoins(p)
	away(p)
	Ty.GardenSet(p, 1, Eco.Id)
	advance(2 * meal + 1.5)
	Ty.GardenSet(p, 1, nil)
	advance(1.1)
	local pm = pileOf(Ty, p, 1)
	if T.check(pm ~= nil and pm.Coins >= 1, "p4 garden scoop: (precondition) a pile for the Magnet check") then
		cashBefore = cashOf(p)
		standAt(p, pm.Pos, 7.5, 0)
		advance(0.4)
		T.eq(cashOf(p) - cashBefore, floor(pm.Value), "p4 garden scoop: with the Magnet the owner scoops from 7.5 studs")
	end
	away(p) -- out of the Magnet's reach: the checks below count coins on the lawn

	-- GardenSet rules: the training lock (DataService.TrainingKeys) with the time left; a key in a running battle
	local prof = DataS.GetProfile(p)
	local okJob = DataS.MutateGrowth(p, function(g)
		g[Combat.Id] = g[Combat.Id] or {}
		g[Combat.Id].Job = { Stat = "Speed", Ends = os.time() + 130, Rank = 1, Slot = 1, Paid = 0 }
	end)
	T.check(okJob == true and DataS.TrainingKeys(p)[Combat.Id] == true, "p4 garden scoop: (precondition) a training job on the Combat pet")
	local okT, whyT = Ty.GardenSet(p, 2, Combat.Id)
	local cName = tostring(Combat.DisplayName or Combat.Name)
	T.check(okT == false and tostring(whyT):find(cName, 1, true) ~= nil and tostring(whyT):find("is training", 1, true) ~= nil and tostring(whyT):find("%(2:%d%d left%)") ~= nil
		and Ty.GetHome(p).Garden[2] == nil, "p4 garden scoop: a training pet cannot be placed: '<name> is training (2:xx left)'", tostring(whyT))
	-- a training pet already in the garden stops eating (its slot is kept for PetCareService to clear)
	Ty.GardenSet(p, 1, Eco.Id)
	advance(0.3)
	T.check(near(Ty.IncomePerSecond(p), Cat.IncomePerSecond(Ty.GetHome(p), { [1] = entryOf(p, Eco) }, 0), 1e-6), "p4 garden scoop: (precondition) the Economy pet earns in place 1")
	DataS.MutateGrowth(p, function(g)
		g[Eco.Id] = g[Eco.Id] or {}
		g[Eco.Id].Job = { Stat = "Physique", Ends = os.time() + 60, Rank = 1, Slot = 2, Paid = 0 }
	end)
	advance(1.2)
	T.check(Ty.IncomePerSecond(p) == 0 and Ty.GetHome(p).Garden[1] == Eco.Id and (info.Folder:GetAttribute("GardenPets") or "") == "",
		"p4 garden scoop: a garden pet that starts training stops earning (its key stays in Home.Garden, GardenPets drops it)")
	DataS.MutateGrowth(p, function(g)
		g[Eco.Id].Job = nil
		g[Combat.Id].Job = nil
	end)
	advance(1.2)
	T.check(Ty.IncomePerSecond(p) > 0 and info.Folder:GetAttribute("GardenPets") == "1=" .. Eco.Id, "p4 garden scoop: ...and earns again when the job is gone")
	local BS = requireAt("server/Services/BattleService")
	if BS then
		local hadFn = BS.KeysInBattle
		BS.KeysInBattle = function(pl)
			if pl == p then
				return { [Combat.Id] = true }
			end
			return {}
		end
		local okB, whyB = Ty.GardenSet(p, 2, Combat.Id)
		T.check(okB == false and whyB == "Finish your battle first!" and Ty.GetHome(p).Garden[2] == nil,
			"p4 garden scoop: a key in the caller's running battle (BattleService.KeysInBattle) is refused", tostring(whyB))
		BS.KeysInBattle = hadFn
	end
	local okC2 = Ty.GardenSet(p, 2, Combat.Id)
	T.check(okC2 == true, "p4 garden scoop: ...and accepted once the battle is over")
	Ty.GardenSet(p, 2, nil)

	-- X5: remove + re-place within one meal keeps the timer; a new placement waits a full meal
	Ty.GardenSet(p, 1, nil)
	Ty.ClearCoins(p)
	advance(1.1)
	Ty.GardenSet(p, 1, Eco.Id)
	advance(meal - 2)
	Ty.GardenSet(p, 1, nil)
	advance(0.5)
	Ty.GardenSet(p, 1, Eco.Id)
	T.eq(bankOf(p), 0, "p4 garden scoop: (X5) nothing yet 6.5 s after the first placement")
	advance(2.6)
	T.check(bankOf(p) > 0, "p4 garden scoop: (X5) the same key back within one meal keeps its timer: the coin comes at the original time, not later")
	local b1 = bankOf(p)
	Ty.GardenSet(p, 1, nil)
	advance(meal + 2)
	Ty.GardenSet(p, 1, Eco.Id)
	advance(meal - 1.5)
	T.check(near(bankOf(p), b1, 1e-6), "p4 garden scoop: (X5) a placement after more than a meal away starts over: no coin before a full meal")
	advance(2.6)
	T.check(bankOf(p) > b1, "p4 garden scoop: (X5) ...then the coin")
	-- churn spam: 40 remove / place pairs in one frame never make a coin (the first request passes, the rest wait)
	local b2 = bankOf(p)
	for _ = 1, 40 do
		homeAction(p, "GardenSet", { 1 })
		homeAction(p, "GardenSet", { 1, Eco.Id })
	end
	advance(0.3)
	T.check(near(bankOf(p), b2, 1e-6), "p4 garden scoop: 80 GardenSet requests in one frame make no coin (cooldown + burst budget)")
	Ty.GardenSet(p, 1, Eco.Id)
	advance(0.3)
	T.check(Ty.GetHome(p).Garden[1] == Eco.Id and near(bankOf(p), b2, 1e-6), "p4 garden scoop: ...and the pet is back in place 1 without a coin")

	-- resting keys above the open count (X20) and LegacySlots
	Ty.ClearCoins(p)
	DataS.MutateHome(p, function(h)
		h.Garden[2] = Eco.Id
		h.Garden[4] = Eco.Id -- a 4th key (an old Garden L8 after a prestige that ended LegacySlots): it rests
	end)
	advance(1.2)
	T.eq(Cat.GardenSlots(Ty.GetHome(p)), 3, "p4 garden scoop: (precondition) 3 open places")
	T.eq(info.Folder:GetAttribute("GardenPets"), "1=" .. Eco.Id .. ";2=" .. Eco.Id .. ";4=" .. Eco.Id, "p4 garden scoop: GardenPets lists the resting key too (nothing is deleted)")
	T.check((info.Folder:GetAttribute("GardenInfo") or ""):find("4=1:0", 1, true) ~= nil, "p4 garden scoop: ...GardenInfo too")
	T.check(near(Ty.IncomePerSecond(p), Cat.IncomePerSecond(Ty.GetHome(p), { [1] = entryOf(p, Eco), [2] = entryOf(p, Eco) }, 0), 1e-6),
		"p4 garden scoop: IncomePerSecond counts only the open places")
	advance(2 * meal + 1.5)
	T.check(pileOf(Ty, p, 4) == nil and pileOf(Ty, p, 2) ~= nil, "p4 garden scoop: the resting key makes no coins while places 1-2 do")
	local okLocked, whyLocked = Ty.GardenSet(p, 5, Eco.Id)
	T.check(okLocked == false and tostring(whyLocked):find("locked", 1, true) ~= nil, "p4 garden scoop: GardenSet above the open count is refused ('locked')", tostring(whyLocked))
	local okClear = Ty.GardenSet(p, 4, nil)
	T.check(okClear == true and Ty.GetHome(p).Garden[4] == nil, "p4 garden scoop: ...but a resting key can always be taken out")
	DataS.MutateHome(p, function(h)
		h.LegacySlots = 5
	end)
	advance(1.2)
	T.eq(Cat.GardenSlots(Ty.GetHome(p)), 5, "p4 garden scoop: LegacySlots 5 opens 5 places")
	T.eq(info.Folder:GetAttribute("GardenSlots"), 5, "p4 garden scoop: ...GardenSlots replicates 5")
	local ok5 = Ty.GardenSet(p, 5, Eco.Id)
	local ok6, why6 = Ty.GardenSet(p, 6, Eco.Id)
	T.check(ok5 == true and ok6 == false and tostring(why6):find("locked", 1, true) ~= nil, "p4 garden scoop: place 5 opens, place 6 stays locked")
	advance(0.3)
	T.check(pileOf(Ty, p, 5) == nil, "p4 garden scoop: the newly opened place owes no backlog (no coin at once)")
	advance(meal + 1.5)
	T.check(pileOf(Ty, p, 5) ~= nil and pileOf(Ty, p, 5).Coins == 1, "p4 garden scoop: ...its first coin comes after a full meal",
		"garden5 " .. tostring(Ty.GetHome(p).Garden[5]) .. " income " .. tostring(Ty.IncomePerSecond(p)) .. " pets " .. tostring(info.Folder:GetAttribute("GardenPets")) .. " piles " .. tostring(info.Folder:GetAttribute("CoinPiles")) .. " open " .. tostring(Cat.GardenSlots(Ty.GetHome(p))))
	T.check(cashOf(p) >= 0 and cashOf(stranger) >= 0, "p4 garden scoop: Cash never goes negative")
	leave(stranger)
	leave(p)
	K.flushErrors("p4garden_scoop")
	K.flushWarnings("p4garden_scoop", { "HomeBuilder is missing" })
end)

----------------------------------------------------------------------------------------------------
-- p4garden_ledger
----------------------------------------------------------------------------------------------------
S.p4garden_ledger = guarded("p4garden_ledger", function()
	if not K.needBoot() then
		return
	end
	local DataS, SS = mod("DataService"), mod("SpotService")
	local Ty, Cat = TS(), TC()
	if not Ty or not Cat then
		T.fail("p4 garden: TycoonService and TycoonCatalog load")
		return
	end
	local Eco = petPair()
	if not Eco then
		T.fail("p4 garden ledger: (precondition) pets")
		return
	end
	local meal = Cat.Coins.MealSeconds
	local name, userId = "GardLedger", 964501
	local storeKey = config().Tokens.DataStoreName .. "/u_" .. userId
	local p = rejoin(name, userId)
	local first, info = startHome(Ty, p)
	givePet(p, Eco.Id, 2)
	DataS.MutateHome(p, function(h)
		h.Stations.Press1 = 1
		h.Stations.Press2 = 2
		h.Stations.Vault = 1
		h.Level = Cat.HomeLevelOf(h)
	end)
	away(p)
	Ty.GardenSet(p, 1, Eco.Id)
	Ty.GardenSet(p, 2, Eco.Id)
	advance(4 * meal + 1.5)
	local income = Ty.IncomePerSecond(p)
	local bankLeave = bankOf(p)
	T.check(bankLeave > 0 and income > 0, "p4 garden ledger: (precondition) coins on the lawn, a Vault home that earns")

	-- leave + rejoin: the coins left on the lawn wait in the Welcome-back pile and pay once
	leave(p)
	advance(1.0)
	local rec = Mock.DataStore.Data[storeKey]
	-- (the store keeps whole Cash: the bank is saved floored, like the Cash balance)
	if not T.check(rec ~= nil and type(rec.Home) == "table" and abs((rec.Home.CollectorCash or 0) - bankLeave) < 1 and (rec.Home.LastSeen or 0) > 0,
		"p4 garden ledger: the leave save holds the bank (CollectorCash, whole Cash) and LastSeen", rec and tostring(rec.Home and rec.Home.CollectorCash) or "no save") then
		return
	end
	bankLeave = rec.Home.CollectorCash
	rec.Home.LastSeen = os.time() -- just left: no offline pay on this rejoin
	local cashStored = rec.Cash or 0
	p = rejoin(name, userId)
	advance(3)
	T.check(near(bankOf(p), bankLeave, 1e-6) and cashOf(p) == cashStored, "p4 garden ledger: a rejoin within 120 s pays no offline coins and banks nothing by itself",
		tostring(bankOf(p)) .. " vs " .. tostring(bankLeave))
	local blocker = join("GardBlock")
	claim(blocker, first)
	local second = freeIndex(first)
	claim(p, second)
	local info2 = spots()[second]
	local piles = Ty.Piles(p)
	T.check(piles ~= nil and piles.W ~= nil and near(piles.W.Value, bankLeave, 1e-6) and piles[1] == nil and piles[2] == nil,
		"p4 garden ledger: on the claim the whole bank waits in the Welcome-back pile (no live pile)")
	T.check((info2.Folder:GetAttribute("CoinPiles") or ""):find("W=5", 1, true) ~= nil, "p4 garden ledger: CoinPiles carries 'W=5' while the Welcome-back pile holds anything")
	local wantW = (info2.PlotCFrame):PointToWorldSpace(Cat.Get("Garden").Slot.WelcomePile)
	T.check(piles.W and typeof(piles.W.Pos) == "Vector3" and (piles.W.Pos - wantW).Magnitude < 1e-3, "p4 garden ledger: the Welcome-back pile stands at the plot-local WelcomePile point")
	T.eq(info2.Folder:GetAttribute("GardenPets"), "1=" .. Eco.Id .. ";2=" .. Eco.Id, "p4 garden ledger: the garden pets are back in their places")
	local cashBefore = cashOf(p)
	standAt(p, piles.W.Pos)
	advance(0.4)
	T.eq(cashOf(p) - cashBefore, floor(bankLeave), "p4 garden ledger: scooping the Welcome-back pile pays the whole stored bank once (" .. floor(bankLeave) .. ")")
	local live, _, welcome = liveSum(Ty, p)
	T.check(welcome < 1 and near(live + welcome, bankOf(p), 1e-6), "p4 garden ledger: ...the Welcome-back pile is empty and the bank equals the new live piles")
	advance(1.0)
	T.eq(cashOf(p) - cashBefore, floor(bankLeave), "p4 garden ledger: ...and nothing is paid twice")

	-- offline coins: into the bank in the same write as LastSeen; Cash untouched; paid once
	away(p)
	advance(2 * meal)
	local homeBefore = Ty.GetHome(p)
	income = Ty.IncomePerSecond(p)
	leave(p)
	advance(1.0)
	rec = Mock.DataStore.Data[storeKey]
	local away2h = 2 * 3600
	rec.Home.LastSeen = os.time() - away2h
	local storedBank = rec.Home.CollectorCash or 0
	local want = Cat.OfflineEarnings(homeBefore, away2h, income)
	cashStored = rec.Cash or 0
	local mark = K.logSize()
	p = rejoin(name, userId)
	advance(4.0)
	T.check(want > 0 and cashOf(p) == cashStored, "p4 garden ledger: offline coins never go to the Cash balance (" .. tostring(want) .. " owed)")
	T.check(near(bankOf(p), storedBank + floor(want), 1e-6), "p4 garden ledger: ...they go INTO the bank (CollectorCash + " .. floor(want) .. ")",
		string.format("%.2f vs %.2f", bankOf(p), storedBank + floor(want)))
	T.check(K.notified(p, "Welcome back! Your pets made", "good", mark), "p4 garden ledger: the 'Welcome back! Your pets made $X while you were away: scoop it in your garden!' toast")
	local bankPaid = bankOf(p)
	advance(20)
	T.check(near(bankOf(p), bankPaid, 1e-6), "p4 garden ledger: paid once (LastSeen moved on with the same write)")
	local seen = DataS.GetHome(p).LastSeen or 0
	T.check(os.time() - seen <= 25, "p4 garden ledger: ...LastSeen is fresh", tostring(os.time() - seen))
	claim(p, freeIndex())
	local pl = Ty.Piles(p)
	T.check(pl and pl.W and near(pl.W.Value, bankPaid, 1e-6), "p4 garden ledger: the offline coins wait in the Welcome-back pile on the claim")
	cashBefore = cashOf(p)
	standAt(p, pl.W.Pos)
	advance(0.4)
	T.eq(cashOf(p) - cashBefore, floor(bankPaid), "p4 garden ledger: ...and are scooped once")

	-- a rebase while the plot is held: the ledger is rebuilt from the merged bank, nothing is paid twice
	away(p)
	advance(2 * meal + 1.5)
	local liveBefore = liveSum(Ty, p)
	T.check(liveBefore > 0, "p4 garden ledger: (precondition) live piles before the rebase")
	DataS.MutateHome(p, function(h)
		h.CollectorCash = h.CollectorCash + 20 -- what a merge with another server's coins would bring
	end)
	DataS.ProfileRebased:Fire(p, DataS.GetProfile(p))
	advance(0.3)
	local merged = bankOf(p)
	pl = Ty.Piles(p)
	T.check(pl and pl.W and near(pl.W.Value, merged, 1e-6) and pl[1] == nil and pl[2] == nil,
		"p4 garden ledger: ProfileRebased rebuilds the ledger: the whole merged bank waits in the Welcome-back pile", pl and tostring(pl.W and pl.W.Value) or "nil")
	cashBefore = cashOf(p)
	standAt(p, pl.W.Pos)
	advance(0.4)
	T.eq(cashOf(p) - cashBefore, floor(merged), "p4 garden ledger: ...scooped once for exactly the merged bank")
	T.check(bankOf(p) < 1 + 3 * income, "p4 garden ledger: ...the bank is down to the fraction and the newest coins", tostring(bankOf(p)))

	-- a provisional load (DataStore outage): nothing can be claimed from stand-in data; after the recovery the stored
	-- bank waits as the Welcome-back pile
	local vetId = 964502
	local vetKey = config().Tokens.DataStoreName .. "/u_" .. vetId
	local function deepCopy(t)
		if type(t) ~= "table" then
			return t
		end
		local out = {}
		for k, v in pairs(t) do
			out[k] = deepCopy(v)
		end
		return out
	end
	local copy = deepCopy(Mock.DataStore.Data[storeKey])
	copy.Home.CollectorCash = 30
	copy.Home.LastSeen = 0
	copy.Home.Garden = { Eco.Id }
	copy.Cash = 100
	copy.SpotIndex = nil
	Mock.DataStore.Data[vetKey] = copy
	Mock.DataStore.Fail = true
	local v = rejoin("GardOutage", vetId)
	advance(4)
	T.check(DataS.IsProvisional(v) == true, "p4 garden ledger: (precondition) the outage makes the profile provisional")
	local okProv, whyProv = Ty.Claim(v, freeIndex())
	T.check(okProv == false and tostring(whyProv):find("still loading", 1, true) ~= nil and SS.GetSpot(v) == nil,
		"p4 garden ledger: a provisional profile claims nothing ('Your home is still loading...')", tostring(whyProv))
	T.eq(Ty.CoinsWaiting(v), 0, "p4 garden ledger: ...and CoinsWaiting answers 0 (no decision from stand-in data)")
	Mock.DataStore.Fail = false
	local recovered = K.waitFor(function()
		return not DataS.IsProvisional(v)
	end, 40)
	T.check(recovered, "p4 garden ledger: (the recovery reads the real save)")
	advance(1)
	T.check(near(bankOf(v), 30, 1e-6) and cashOf(v) == 100, "p4 garden ledger: after the recovery the stored bank and Cash are intact (30 / 100)", tostring(bankOf(v)) .. " / " .. tostring(cashOf(v)))
	claim(v, freeIndex())
	local pv = Ty.Piles(v)
	T.check(pv and pv.W and near(pv.W.Value, 30, 1e-6), "p4 garden ledger: ...the claim puts the stored 30 in the Welcome-back pile")
	cashBefore = cashOf(v)
	standAt(v, pv.W.Pos)
	advance(0.4)
	T.eq(cashOf(v) - cashBefore, 30, "p4 garden ledger: ...scooped once")
	leave(v)

	-- an outage during scoops: the leave save fails, the orphan retry writes Cash and the bank; nothing is lost or doubled
	away(p)
	Ty.ClearCoins(p)
	advance(3 * meal + 1.5)
	Mock.DataStore.Fail = true
	advance(2 * meal)
	local pl1 = pileOf(Ty, p, 1)
	cashBefore = cashOf(p)
	standAt(p, pl1.Pos)
	advance(0.4)
	local paidOut = cashOf(p) - cashBefore
	T.check(paidOut >= floor(pl1.Value) and paidOut >= 1, "p4 garden ledger: scoops keep working during a DataStore outage", tostring(paidOut))
	away(p)
	advance(0.5)
	local cashLeave, bankLeave2 = cashOf(p), bankOf(p)
	leave(p)
	advance(1.0)
	Mock.DataStore.Fail = false
	local written = K.waitFor(function()
		local r = Mock.DataStore.Data[storeKey]
		return r ~= nil and r.Cash == cashLeave
	end, 120)
	rec = Mock.DataStore.Data[storeKey]
	T.check(written and rec and rec.Cash == cashLeave and abs((rec.Home.CollectorCash or 0) - bankLeave2) < 1,
		"p4 garden ledger: the orphan save after the outage carries the scooped Cash and the remaining bank (nothing lost, nothing doubled)",
		rec and (tostring(rec.Cash) .. " / " .. tostring(rec.Home.CollectorCash) .. " vs " .. tostring(cashLeave) .. " / " .. tostring(bankLeave2)) or "no save")
	rec.Home.LastSeen = os.time()
	p = rejoin(name, userId)
	advance(2)
	T.check(cashOf(p) == cashLeave and near(bankOf(p), rec.Home.CollectorCash, 1e-6), "p4 garden ledger: ...and the rejoin sees exactly them")

	-- Prestige mid-pile: bank + piles to 0, the Garden stays at L1, +1 place, LegacySlots cleared, pets kept
	claim(p, freeIndex())
	local idx = SS.GetSpot(p) and SS.GetSpot(p).Index
	local pinfo = spots()[idx]
	DataS.MutateHome(p, function(h)
		for _, def in ipairs(Cat.Stations) do
			if not def.KeepOnPrestige then
				h.Stations[def.Id] = def.MaxLevel
			end
		end
		h.Stations.FusionMachine = 0
		h.Stations.ArenaGate = 0
		h.LegacySlots = 6
		h.Level = Cat.HomeLevelOf(h)
	end)
	advance(1.2)
	local ready = Cat.CanPrestige(Ty.GetHome(p))
	T.check(ready == true and Cat.GardenSlots(Ty.GetHome(p)) == 6, "p4 garden ledger: (precondition) prestige-ready, 6 legacy places")
	away(p)
	advance(2 * meal + 1.5)
	T.check(bankOf(p) > 0 and liveSum(Ty, p) > 0, "p4 garden ledger: (precondition) coins on the lawn before the Prestige")
	DataS.AddCash(p, 500)
	mark = K.logSize()
	local okP, stars = Ty.Prestige(p)
	advance(0.3)
	local after = Ty.GetHome(p)
	T.check(okP == true and stars == 1 and after.Prestige == 1, "p4 garden ledger: Prestige -> 1 star")
	T.check(after.CollectorCash == 0 and Ty.CoinsWaiting(p) == 0 and cashOf(p) == 0, "p4 garden ledger: ...the bank, the coins on the lawn and the Cash are zero")
	local pp = Ty.Piles(p)
	local count = 0
	for slot in pairs(pp or {}) do
		if slot ~= "W" then
			count = count + 1
		end
	end
	T.check(pp and count == 0 and (pp.W == nil or pp.W.Value == 0) and (pinfo.Folder:GetAttribute("CoinPiles") or "") == "", "p4 garden ledger: ...every pile is gone (CoinPiles empty)")
	T.eq(after.Stations.Garden, 1, "p4 garden ledger: ...the Garden stays built at level 1 (StationsAfterPrestige)")
	T.check((after.Stations.Press1 or 0) == 0 and (after.Stations.Collector or 0) == 0, "p4 garden ledger: ...the other stations reset")
	T.check(after.LegacySlots == nil and Cat.GardenSlots(after) == 4, "p4 garden ledger: ...LegacySlots are gone: 4 places (3 + 1 star)")
	T.eq(pinfo.Folder:GetAttribute("GardenSlots"), 4, "p4 garden ledger: ...GardenSlots replicates 4")
	T.check(K.notified(p, "Garden place 4 unlocked", "good", mark), "p4 garden ledger: the 'Garden place 4 unlocked!' toast")
	T.check(after.Garden[1] == Eco.Id and after.Garden[2] == Eco.Id, "p4 garden ledger: ...the garden pets keep their places")
	advance(meal + 1.5)
	T.check(bankOf(p) > 0, "p4 garden ledger: ...and the coins never stop (x1.25 now)")
	local coin1 = Cat.CoinValue(Ty.GetHome(p), Cat.PetPower(entryOf(p, Eco)), 1)
	local p1 = pileOf(Ty, p, 1) or pileOf(Ty, p, 2)
	T.check(p1 ~= nil and near(p1.Value / p1.Coins, coin1, 1e-6) and near(coin1, Cat.FoodOf(Ty.GetHome(p)) * Cat.PetPower(entryOf(p, Eco)) * 1.25, 1e-6),
		"p4 garden ledger: ...each coin carries the x1.25 star multiplier")

	-- star prices through PriceAt; a veteran's LegacyPrices (the one-time migration) pays base prices until the next Prestige
	local h1 = Ty.GetHome(p)
	local starPrice = Cat.PriceAt("Press1", 1, h1)
	T.check(starPrice == floor(Cat.PriceFor("Press1", 1) * 1.5), "p4 garden ledger: at 1 star a pad costs PriceAt = x1.5 (" .. tostring(starPrice) .. ")")
	DataS.AddCash(p, starPrice - 1)
	local okPoor, whyPoor = Ty.Buy(p, "Press1")
	T.check(okPoor == false and tostring(whyPoor):find("Not enough Cash", 1, true) ~= nil and tostring(whyPoor):find(tostring(starPrice), 1, true) ~= nil,
		"p4 garden ledger: ...the Upgrade is refused below the star price (the toast names it)", tostring(whyPoor))
	DataS.MutateHome(p, function(h)
		h.LegacyPrices = true
	end)
	local okLegacy = Ty.Buy(p, "Press1")
	T.check(okLegacy == true and cashOf(p) == starPrice - 1 - Cat.PriceFor("Press1", 1), "p4 garden ledger: with Home.LegacyPrices the same pad costs the base price (" .. tostring(Cat.PriceFor("Press1", 1)) .. ")",
		tostring(cashOf(p)))
	DataS.MutateHome(p, function(h)
		h.LegacyPrices = nil
	end)

	-- ClearCoins (the developer reset)
	T.eq(Ty.ClearCoins(p), true, "p4 garden ledger: ClearCoins(player) answers true")
	T.check(bankOf(p) == 0 and liveSum(Ty, p) == 0 and (pinfo.Folder:GetAttribute("CoinPiles") or "") == "", "p4 garden ledger: ...bank and piles are zero")

	-- the one-time welcome toast of a migrated veteran (P4Veteran -> P4Welcome)
	local vet = rejoin("GardVeteran", 964503)
	advance(1)
	T.eq(DataS.MarkMigrated(vet, "P4Veteran"), true, "p4 garden ledger: (precondition) a veteran marker")
	mark = K.logSize()
	claim(vet, freeIndex())
	T.check(K.notified(vet, "Welcome to the new home", "good", mark), "p4 garden ledger: the first claim of a migrated veteran shows the welcome toast")
	T.eq(DataS.IsMigrated(vet, "P4Welcome"), true, "p4 garden ledger: ...and marks P4Welcome")
	leave(vet)
	vet = rejoin("GardVeteran", 964503)
	mark = K.logSize()
	claim(vet, freeIndex())
	T.check(not K.notified(vet, "Welcome to the new home", nil, mark), "p4 garden ledger: ...never twice (a union across sessions and servers)")
	local newbie = join("GardNew")
	mark = K.logSize()
	claim(newbie, freeIndex())
	T.check(not K.notified(newbie, "Welcome to the new home", nil, mark), "p4 garden ledger: a new player never sees the veteran toast")
	leave(newbie)
	leave(vet)
	leave(blocker)
	leave(p)
	K.flushErrors("p4garden_ledger")
	K.flushWarnings("p4garden_ledger", { "HomeBuilder is missing", "[DataService]" })
end)

return S
