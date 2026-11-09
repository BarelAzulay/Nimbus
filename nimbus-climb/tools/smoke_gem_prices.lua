-- smoke_gem_prices.lua: the lobby-shop gem shop (docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.3, 5.8, 7,
-- 16.1; plan docs/superpowers/plans/2026-11-07-lobby-shop.md Task 7; Task 16 adds the owner's prices here). Server world
-- only (booted):
--   gem_potion_buy  StoreRequest("GemBuy", key) -> StoreService.BuyWithGems(player, key): Config.Store.GemItems (the one
--                   XP Potion for 100 gems since Task 16), StoreCatalog.GemItems / GemItem (copies) and Validate over them;
--                   a buy spends 100 gems and adds 1,800 s of potion time (max(BoostEnds, now) + 1800, stacking), one good
--                   toast "XP Potion: +30 minutes", StoreService.Changed once, XpBoostEnds follows; each refusal toasts its
--                   text (bad) and leaves gems and BoostEnds unchanged: in a match, the save loading, provisional, not
--                   settled, the x2 Pet XP pass Owned / Checking, the potion bank full (the 7-day cap, with its exact edge),
--                   99 gems (one short); the pass NotOwned / Unavailable and a restricted account (PolicyService) buy; the
--                   shared 1 s gap of "Buy" (the XpPotion1 Robux product: Task 16 locks the token packs for restricted
--                   accounts) and "GemBuy" (both orders); junk actions / keys dropped silently (and never use the gap);
--                   the XpPassState attribute equals StoreService.PassState(player, "PetXp2x") after every pass change
--   gem_prices      (Task 16, spec 16.1) every owner's number read from Config / TycoonCatalog / StoreCatalog (gem spins 20 /
--                   40 / 60 / 180, the Secret Roulette 500 at Mythic 60 / Secret 40 with the pity at 7, Celestial Epic 43 /
--                   Legendary 40 / Mythic 15 / Secret 2 with AllowSecret, the Cloud / Storm / Sky odds and every token price
--                   unchanged, gem packs 200 / 670 / 1,950 / 5,300 with Robux 49 / 149 / 399 / 999, token packs 1,500 /
--                   7,500 / 30,000 with their names, Mix 40 / 100, the potion 100, List() gem items carry Robux), the
--                   IndexController Secret line; booted, settled, allowed: GemService.Quote 20 / 40 / 60 / 180 / 500 with
--                   each roulette's own AllowSecret, every gem spin charged its price once (the Secret Roulette's on the Storm
--                   Altar's deck, shop-area 16.17.3), a Mythic Mix 40 and a Secret Mix 100 gems, the potion 100
-- White-box: the booted helpers of smoke_store.lua (join / setId / savedIds / restoreIds / toasts); the MarketplaceService
-- and PolicyService doubles are props (nil restores them). Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local K = _G.K
local MPS = game:GetService("MarketplaceService")
local KEY = "XpPotionGems"
local POTION = "XpPotion"
local PASS = "PetXp2x"
local PASS_ID = 7203
local POTION1_ID = 6203 -- XpPotion1, a Robux product no account lock touches (Task 16: token packs are policy-locked)
local PRICE = 100 -- the gem XP Potion's price (Task 16, spec 16.1; was 75)
-- the mock has no asset store: MeshLibrary's lazy loads (the dungeon kit) warn whenever the clock runs, in any scenario
local ALLOWED_WARNINGS = { "[DataService]", "[StoreService] UserOwnsGamePassAsync failed", "[MeshLibrary]" }
local TEXT = {
	Got = "XP Potion: +30 minutes",
	Match = "The Store is closed during a match",
	Loading = "Your save is still loading",
	Settling = "Your data is still loading",
	Have = "You already have x2 Pet XP",
	Checking = "Checking your passes...",
	Full = "Your potion time is full",
	Poor = "Not enough gems",
}

----------------------------------------------------------------------------------------------------
-- helpers (the smoke_store.lua shapes)
----------------------------------------------------------------------------------------------------
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
local function DS()
	return K.mod("DataService")
end
local function SS()
	return requireAt("server/Services/StoreService")
end
local function GS()
	return requireAt("server/Services/GemService")
end
local userSeq = 0
local function newUserId()
	userSeq = userSeq + 1
	return 994400 + userSeq
end
local function join(prefix, uid)
	local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
	K.advance(1.2)
	return p
end
local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	K.advance(0.8)
end
local function loaded(p)
	return K.waitFor(function()
		return DS().GetProfile(p) ~= nil and DS().IsProvisional(p) ~= true
	end, 10)
end
local function itemOf(key)
	for _, it in ipairs(K.config().Store.Items) do
		if it.Key == key then
			return it
		end
	end
	return nil
end
local function setId(key, id)
	local it = itemOf(key)
	if it then
		it.Id = id
	end
end
local function savedIds()
	local out = {}
	for _, it in ipairs(K.config().Store.Items) do
		out[it.Key] = it.Id
	end
	return out
end
local function restoreIds(saved)
	for _, it in ipairs(K.config().Store.Items) do
		it.Id = saved[it.Key] or 0
	end
end
-- the Notify toasts p got since `mark`: { { text, kind }... }
local function toasts(p, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		out[#out + 1] = { text = tostring(e.args[1]), kind = e.args[2] }
	end
	return out
end
local function toastText(p, mark)
	local out = {}
	for _, t in ipairs(toasts(p, mark)) do
		out[#out + 1] = t.text .. " (" .. tostring(t.kind) .. ")"
	end
	return #out == 0 and "no toast" or table.concat(out, " | ")
end
-- exactly one toast since mark, with this text and kind
local function oneToast(p, text, kind, mark)
	local list = toasts(p, mark)
	return #list == 1 and list[1].text == text and list[1].kind == kind
end
-- counts signal:Fire(player) for one player until stop()
local function countFires(signal, player)
	local box = { n = 0 }
	local conn = signal:Connect(function(who)
		if who == player then
			box.n = box.n + 1
		end
	end)
	box.stop = function()
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	return box
end
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
local function count(map)
	local n = 0
	for _ in pairs(type(map) == "table" and map or {}) do
		n = n + 1
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- gem_potion_buy
----------------------------------------------------------------------------------------------------
S.gem_potion_buy = guarded("gem_potion_buy", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local D, Store, SC = DS(), SS(), requireAt("shared/StoreCatalog")

	------------------------------------------------------------------------------------------------
	-- part 1: the data (Config.Store.GemItems, Config.Attr.XpPassState) and StoreCatalog over it
	------------------------------------------------------------------------------------------------
	local items = Config.Store.GemItems
	local first = type(items) == "table" and items[1] or nil
	T.check(type(items) == "table" and #items == 1 and type(first) == "table" and first.Key == KEY and first.Gems == PRICE and first.Name == "XP Potion (30 min)"
		and type(first.Grants) == "table" and count(first.Grants) == 1 and type(first.Grants.Boost) == "table" and count(first.Grants.Boost) == 1 and first.Grants.Boost.XpPotion == 1800 and count(first) == 4,
		"gem potion config: Config.Store.GemItems = { { Key = 'XpPotionGems', Gems = 100, Name = 'XP Potion (30 min)', Grants = { Boost = { XpPotion = 1800 } } } }")
	T.eq(Config.Attr.XpPassState, "XpPassState", "gem potion config: Config.Attr.XpPassState = 'XpPassState'")
	local catalogOk = T.check(type(SC) == "table" and type(SC.GemItems) == "function" and type(SC.GemItem) == "function", "gem potion catalog: StoreCatalog.GemItems / GemItem exist")
	if catalogOk and first then
		local list = SC.GemItems()
		local it = list[1]
		T.check(#list == 1 and type(it) == "table" and it.Key == KEY and it.Gems == PRICE and it.Name == "XP Potion (30 min)" and it.Grants.Boost.XpPotion == 1800, "gem potion catalog: GemItems() lists the potion { Key, Gems, Name, Grants }")
		T.check(it ~= first and it.Grants ~= first.Grants and it.Grants.Boost ~= first.Grants.Boost, "gem potion catalog: ...as a copy (its Grants too)")
		it.Gems, it.Grants.Boost.XpPotion = 1, 60
		T.check(first.Gems == PRICE and first.Grants.Boost.XpPotion == 1800, "gem potion catalog: ...changing the copy leaves Config alone")
		local one = SC.GemItem(KEY)
		T.check(type(one) == "table" and one.Key == KEY and one.Gems == PRICE and one ~= first and one.Grants ~= first.Grants, "gem potion catalog: GemItem(key) answers a copy")
		T.check(SC.GemItem("Nope") == nil and SC.GemItem(nil) == nil and SC.GemItem(5) == nil and SC.GemItem("Tokens1") == nil, "gem potion catalog: GemItem answers nil for an unknown key, junk, or a Robux item's key")
		T.eq(SC.Item(KEY), nil, "gem potion catalog: Item(key) never answers a gem item (it is not a Robux item)")
		T.check(select(1, SC.Validate()) == true, "gem potion catalog: Validate passes on the shipped Config", table.concat(select(2, SC.Validate()) or {}, "; "))
		-- Validate refusals: a deep copy of Config.Store.GemItems mutated, then restored; each a false naming the key
		local function refused(label, key, mutate)
			local saved = Config.Store.GemItems
			Config.Store.GemItems = deepCopy(saved)
			mutate(Config.Store.GemItems)
			local ok, problems = SC.Validate()
			Config.Store.GemItems = saved
			local named = false
			for _, pr in ipairs(problems or {}) do
				if string.find(pr, key, 1, true) then
					named = true
				end
			end
			T.check(ok == false and named, "gem potion catalog: Validate refuses " .. label .. " (naming " .. key .. ")", table.concat(problems or {}, "; "))
		end
		refused("Gems 0", KEY, function(c) c[1].Gems = 0 end)
		refused("fractional Gems", KEY, function(c) c[1].Gems = 7.5 end)
		refused("an empty Name", KEY, function(c) c[1].Name = "" end)
		refused("a Cash grant", KEY, function(c) c[1].Grants.Cash = 5 end)
		refused("a boost other than XpPotion", KEY, function(c) c[1].Grants.Boost.Speed = 60 end)
		refused("a potion past CapSeconds", KEY, function(c) c[1].Grants.Boost.XpPotion = Config.Store.Potion.CapSeconds + 1 end)
		refused("a potion under 60 s", KEY, function(c) c[1].Grants.Boost.XpPotion = 30 end)
		refused("a duplicate Key", KEY, function(c) c[2] = deepCopy(c[1]) end)
		refused("a Key a Robux item uses", "Tokens1", function(c) c[1].Key = "Tokens1" end)
		refused("an empty Key", "gem item 1", function(c) c[1].Key = "" end)
	end

	------------------------------------------------------------------------------------------------
	-- part 2: the buys (booted)
	------------------------------------------------------------------------------------------------
	local folder = K.remoteFolder()
	local remote = folder and folder:FindFirstChild("StoreRequest")
	if not T.check(type(Store) == "table" and type(Store.BuyWithGems) == "function" and remote ~= nil and type(D._SettleForTest) == "function",
		"gem potion: StoreService.BuyWithGems, the StoreRequest remote and DataService._SettleForTest exist") then
		return
	end
	local ATTR = Config.Attr.XpPassState or "XpPassState"
	local ENDS_ATTR = Config.Attr.XpBoostEnds
	local CAP = Config.Store.Potion.CapSeconds
	local DSt = Mock.DataStore
	local PolS = game:GetService("PolicyService")
	local saved = { Ids = savedIds(), Fail = DSt.Fail, Latency = DSt.Latency }
	local players, boxes = {}, {}
	local modes = {} -- [uid] = true (owns PetXp2x) | false | "error"
	local prompts = 0
	MPS.UserOwnsGamePassAsync = function(_, uid, id)
		if modes[uid] == "error" then
			error("HTTP 503 (smoke: pass lookup outage)")
		end
		return modes[uid] == true and id == PASS_ID
	end
	MPS.PromptProductPurchase = function()
		prompts = prompts + 1
	end
	MPS.PromptGamePassPurchase = function()
		prompts = prompts + 1
	end
	-- every account in this scenario is a restricted account (no paid random items): the potion is not random, it sells
	PolS.GetPolicyInfoForPlayerAsync = function()
		return { ArePaidRandomItemsRestricted = true, IsPaidItemTradingAllowed = false }
	end
	local okRun, errRun = pcall(function()
		local errs0 = #Mock.Errors
		local function track(p)
			players[#players + 1] = p
			return p
		end
		local function setGems(p, n)
			D.SpendGems(p, D.GetGems(p))
			if n > 0 then
				D.AddGems(p, n)
			end
			return D.GetGems(p) == n
		end
		local function ends(p)
			return Store.BoostEnds(p, POTION)
		end
		local function passAttrOk(p, want, label)
			T.check(p:GetAttribute(ATTR) == want and Store.PassState(p, PASS) == want, "gem potion pass attr: " .. label .. ": XpPassState = PassState = '" .. want .. "'",
				"attribute " .. tostring(p:GetAttribute(ATTR)) .. ", PassState " .. tostring(Store.PassState(p, PASS)))
		end
		-- a refusal: false + the text, one bad toast with it, gems and BoostEnds unchanged
		local function refusedWith(p, text, label)
			local gems0, ends0, mark = D.GetGems(p), ends(p), K.logSize()
			local ok, why = Store.BuyWithGems(p, KEY)
			K.advance(0.2)
			T.check(ok == false and why == text, "gem potion refused: " .. label .. " -> '" .. text .. "'", tostring(ok) .. " / " .. tostring(why))
			T.check(oneToast(p, text, "bad", mark), "gem potion refused: " .. label .. ": one bad toast with the text", toastText(p, mark))
			T.check(D.GetGems(p) == gems0 and ends(p) == ends0, "gem potion refused: " .. label .. ": gems and BoostEnds unchanged",
				tostring(gems0) .. " -> " .. tostring(D.GetGems(p)) .. " gems, " .. tostring(ends0) .. " -> " .. tostring(ends(p)))
		end
		-- a buy: true, one good toast, -PRICE gems, max(BoostEnds, now) + 1800, Changed once, XpBoostEnds follows
		local function boughtOne(p, label, viaRemote)
			local gems0, ends0, now, mark = D.GetGems(p), ends(p), os.time(), K.logSize()
			local fires = countFires(Store.Changed, p)
			boxes[#boxes + 1] = fires
			local ok, why = true, nil
			if viaRemote then
				Mock.FromClient(remote, p, "GemBuy", KEY)
			else
				ok, why = Store.BuyWithGems(p, KEY)
			end
			K.advance(0.2)
			fires.stop()
			T.check(ok == true, "gem potion buy: " .. label .. ": BuyWithGems answers true", tostring(why))
			T.check(D.GetGems(p) == gems0 - PRICE, "gem potion buy: " .. label .. ": " .. PRICE .. " gems spent", tostring(gems0) .. " -> " .. tostring(D.GetGems(p)))
			T.check(ends(p) == math.max(ends0, now) + 1800, "gem potion buy: " .. label .. ": BoostEnds = max(BoostEnds, now) + 1,800 s",
				tostring(ends0) .. " -> " .. tostring(ends(p)) .. " (now " .. now .. ")")
			T.check(oneToast(p, TEXT.Got, "good", mark), "gem potion buy: " .. label .. ": one good toast '" .. TEXT.Got .. "'", toastText(p, mark))
			T.eq(fires.n, 1, "gem potion buy: " .. label .. ": StoreService.Changed fired once")
			T.eq(p:GetAttribute(ENDS_ATTR), ends(p), "gem potion buy: " .. label .. ": XpBoostEnds updated")
		end

		-- the pass is Unavailable (Id 0, as shipped): the potion sells
		setId(PASS, 0)
		local u = track(join("PotionUnavail", newUserId()))
		T.check(loaded(u) and D._SettleForTest(u) == true and setGems(u, PRICE), "gem potion: (setup) a loaded, settled player with " .. PRICE .. " gems")
		passAttrOk(u, "Unavailable", "the pass has no Id")
		boughtOne(u, "pass Unavailable", false)
		leave(u)

		setId(PASS, PASS_ID)
		setId("XpPotion1", POTION1_ID)
		-- a: NotOwned, the restricted main buyer
		local uidA = newUserId()
		modes[uidA] = false
		local a = track(join("PotionBuyer", uidA))
		T.check(loaded(a) and D._SettleForTest(a) == true and setGems(a, 1000), "gem potion: (setup) the main buyer is loaded, settled, 1,000 gems")
		local Gems = GS()
		T.check(Gems and Gems.IsRestricted(a) == true and Gems.PolicyState(a) == "Restricted", "gem potion: (precondition) the main buyer is a restricted account (PolicyService double)",
			tostring(Gems and Gems.PolicyState(a)))
		passAttrOk(a, "NotOwned", "a false lookup")
		K.advance(1.1)
		boughtOne(a, "the remote, a restricted account, pass NotOwned", true)
		T.eq(prompts, 0, "gem potion buy: ...a GemBuy prompts nothing")
		boughtOne(a, "a second potion stacks on the first", false)

		-- refusals of the main buyer, in the order of the checks
		a:SetAttribute(Config.Attr.InMatch, true)
		refusedWith(a, TEXT.Match, "in a match")
		a:SetAttribute(Config.Attr.InMatch, nil)
		T.check(setGems(a, PRICE - 1), "gem potion: (setup) " .. (PRICE - 1) .. " gems (one gem short)")
		refusedWith(a, TEXT.Poor, (PRICE - 1) .. " gems (one gem short)")
		T.check(setGems(a, 1000), "gem potion: (setup) 1,000 gems again")
		local target = os.time() + CAP - 1000
		local okFill = D.AddBoost(a, POTION, target - math.max(ends(a), os.time()))
		T.check(okFill == true and ends(a) == target, "gem potion: (setup) the potion bank ends at now + 7 d - 1,000 s", tostring(ends(a) - os.time()))
		refusedWith(a, TEXT.Full, "the bank full (now + 7 d - 1,000 s)")

		-- the pass bought in this session: Owned
		Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", a, PASS_ID, true)
		K.advance(0.2)
		passAttrOk(a, "Owned", "PromptGamePassPurchaseFinished")
		refusedWith(a, TEXT.Have, "pass Owned")

		-- e: the cap's edge: a bank of 7 d - 1,800 s takes one more potion (exactly 7 d), then refuses
		local uidE = newUserId()
		modes[uidE] = false
		local e = track(join("PotionEdge", uidE))
		T.check(loaded(e) and D._SettleForTest(e) == true and setGems(e, 300), "gem potion: (setup) the edge player is loaded, settled, 300 gems")
		-- Task 16: measured from the setup's clock (boughtOne's short advance can cross a whole second of os.time; the bank
		-- then reads 7 d - 1 s from the later clock, which is not the edge under test)
		local tEdge = os.time()
		T.check(D.AddBoost(e, POTION, CAP - 1800) == true and ends(e) == tEdge + CAP - 1800, "gem potion: (setup) a bank of 7 d - 1,800 s")
		boughtOne(e, "a bank of 7 d - 1,800 s (exactly 7 d after)", false)
		T.eq(ends(e) - tEdge, CAP, "gem potion buy: ...the bank is exactly 7 d (from the setup's clock)")
		refusedWith(e, TEXT.Full, "a bank of exactly 7 d")

		-- c: the pass lookup fails (Checking), then a retry answers false (NotOwned)
		local uidC = newUserId()
		modes[uidC] = "error"
		local c = track(join("PotionCheck", uidC))
		T.check(loaded(c) and D._SettleForTest(c) == true and setGems(c, PRICE), "gem potion: (setup) the Checking player is loaded, settled, " .. PRICE .. " gems")
		passAttrOk(c, "Checking", "a failing lookup")
		refusedWith(c, TEXT.Checking, "pass Checking")
		modes[uidC] = false
		K.advance(5.5)
		passAttrOk(c, "NotOwned", "the retry 5 s later answers false")
		boughtOne(c, "pass NotOwned after the retry", false)
		-- o: the engine says the pass is owned at the join
		local uidO = newUserId()
		modes[uidO] = true
		local o = track(join("PotionOwner", uidO))
		T.check(loaded(o) and D._SettleForTest(o) == true and setGems(o, PRICE), "gem potion: (setup) the pass owner is loaded, settled, " .. PRICE .. " gems")
		passAttrOk(o, "Owned", "a true lookup at the join")
		refusedWith(o, TEXT.Have, "pass Owned at the join")

		-- n: not settled. Session lock (2026-11-10): the 15 s settle hold is retired and GemsSettled is OwnsSave, so a
		-- normal join is settled at once; a loaded, non-provisional player is unsettled only while this server does not
		-- hold the save's lock: a rejoin that raced its own leave's release write uses the cached entry, the release lands
		-- after it, and the next save takes the lock back
		local uidN = newUserId()
		modes[uidN] = false
		local n0 = join("PotionNotSettled", uidN)
		T.check(loaded(n0) and D.GemsSettled(n0) == true and D.Save(n0) == true, "gem potion: (setup) a normal join is settled at once (no _SettleForTest)")
		DSt.Latency = 1
		Mock.RemovePlayer(n0)
		K.advance(0.3) -- the leave's release write is in flight (it lands at 1 s)
		local n = track(Mock.AddPlayer("PotionNotSettled" .. tostring(uidN % 1000), uidN))
		K.advance(1.5)
		DSt.Latency = saved.Latency
		T.check(loaded(n) and D.GemsSettled(n) == false and setGems(n, PRICE), "gem potion: (setup) a loaded player whose save's lock this server does not hold yet (not settled), " .. PRICE .. " gems")
		refusedWith(n, TEXT.Settling, "not settled")
		T.check(D.Save(n) == true and D.GemsSettled(n) == true, "gem potion: ...the next save takes the lock back: settled")

		-- l: the save still loading (a slow store)
		DSt.Latency = 2
		local uidL = newUserId()
		modes[uidL] = false
		local l = track(Mock.AddPlayer("PotionLoading" .. tostring(uidL % 1000), uidL))
		K.advance(0.5)
		T.eq(D.GetProfile(l), nil, "gem potion: (precondition) the save is still loading")
		refusedWith(l, TEXT.Loading, "the save loading")
		DSt.Latency = saved.Latency
		T.check(loaded(l), "gem potion: (setup) the slow load lands")

		-- v: provisional (a load during an outage)
		DSt.Fail = true
		local uidV = newUserId()
		modes[uidV] = false
		local v = track(join("PotionProv", uidV))
		local isProv = K.waitFor(function()
			return D.IsProvisional(v) == true
		end, 10)
		if T.check(isProv, "gem potion: (precondition) a load during an outage leaves a provisional profile") then
			D.AddGems(v, PRICE)
			refusedWith(v, TEXT.Loading, "provisional")
		end
		DSt.Fail = saved.Fail
		K.waitFor(function()
			return D.IsProvisional(v) ~= true
		end, 60)

		------------------------------------------------------------------------------------------------
		-- the remote: junk dropped silently, the shared 1 s gap of "Buy" and "GemBuy"
		------------------------------------------------------------------------------------------------
		local uidR = newUserId()
		modes[uidR] = false
		local r = track(join("PotionRemote", uidR))
		T.check(loaded(r) and D._SettleForTest(r) == true and setGems(r, 1000), "gem potion remote: (setup) loaded, settled, 1,000 gems")
		K.advance(1.1)
		local function send(...)
			Mock.FromClient(remote, r, ...)
		end
		local gems0, ends0, mark, prompts0 = D.GetGems(r), ends(r), K.logSize(), prompts
		send("GemBuy", 5)
		send("GemBuy")
		send("GemBuy", {})
		send("Sell", "x")
		send("Sell", KEY)
		send(nil, KEY)
		K.advance(0.2)
		T.check(#toasts(r, mark) == 0 and D.GetGems(r) == gems0 and ends(r) == ends0 and prompts == prompts0 and #Mock.Errors == errs0,
			"gem potion remote: junk (GemBuy 5 / nil / {}, Sell x, Sell <key>, nil <key>) is dropped silently: no toast, nothing spent, nothing raised", toastText(r, mark))
		mark = K.logSize()
		send("GemBuy", KEY)
		K.advance(0.2)
		T.check(D.GetGems(r) == gems0 - PRICE and oneToast(r, TEXT.Got, "good", mark), "gem potion remote: ...and junk never uses the 1 s gap: a GemBuy right after it buys", toastText(r, mark))
		-- GemBuy then Buy 0.5 s apart: the Buy is dropped; a Buy a second later prompts
		K.advance(0.3)
		mark = K.logSize()
		send("Buy", "XpPotion1")
		K.advance(0.2)
		T.check(prompts == prompts0 and #toasts(r, mark) == 0, "gem potion remote: GemBuy then Buy 0.5 s later: the Buy is dropped (one 1 s gap for both)", tostring(prompts - prompts0) .. " prompts")
		K.advance(1.1)
		send("Buy", "XpPotion1")
		K.advance(0.2)
		T.eq(prompts, prompts0 + 1, "gem potion remote: ...a Buy a second later prompts")
		-- Buy then GemBuy 0.5 s apart: the GemBuy is dropped; a GemBuy a second later buys
		K.advance(0.3)
		local gems1, ends1 = D.GetGems(r), ends(r)
		mark = K.logSize()
		send("GemBuy", KEY)
		K.advance(0.2)
		T.check(D.GetGems(r) == gems1 and ends(r) == ends1 and #toasts(r, mark) == 0, "gem potion remote: Buy then GemBuy 0.5 s later: the GemBuy is dropped (nothing spent, no toast)", toastText(r, mark))
		K.advance(1.1)
		mark = K.logSize()
		send("GemBuy", KEY)
		K.advance(0.2)
		T.check(D.GetGems(r) == gems1 - PRICE and ends(r) == ends1 + 1800 and oneToast(r, TEXT.Got, "good", mark), "gem potion remote: ...a GemBuy a second later buys", toastText(r, mark))
		-- an unknown gem key and the public function's junk: false, silent
		K.advance(1.1)
		mark = K.logSize()
		send("GemBuy", "Nope")
		K.advance(0.2)
		T.check(#toasts(r, mark) == 0 and D.GetGems(r) == gems1 - PRICE, "gem potion remote: GemBuy with an unknown key: silent, nothing spent", toastText(r, mark))
		local okNil = Store.BuyWithGems(nil, KEY)
		local okNope = Store.BuyWithGems(r, "Nope")
		local okNum = Store.BuyWithGems(r, 5)
		local okRobux = Store.BuyWithGems(r, "Tokens1")
		K.advance(0.2)
		T.check(okNil == false and okNope == false and okNum == false and okRobux == false and #toasts(r, mark) == 0 and D.GetGems(r) == gems1 - PRICE,
			"gem potion: BuyWithGems(nil / unknown key / 5 / a Robux item's key) -> false, silent, nothing spent", toastText(r, mark))
		T.eq(prompts, prompts0 + 1, "gem potion: no gem buy ever prompts a Robux purchase")
		T.eq(#Mock.Errors, errs0, "gem potion: nothing raised")
	end)
	for _, box in ipairs(boxes) do
		box.stop()
	end
	MPS.UserOwnsGamePassAsync = nil
	MPS.PromptProductPurchase = nil
	MPS.PromptGamePassPurchase = nil
	PolS.GetPolicyInfoForPlayerAsync = nil
	DSt.Fail = saved.Fail
	DSt.Latency = saved.Latency
	restoreIds(saved.Ids)
	for _, p in ipairs(players) do
		if p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(0.8)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("gem_potion_buy")
	K.flushWarnings("gem_potion_buy", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- gem_prices (Task 16, spec 16.1): the owner's prices, read from Config / TycoonCatalog / StoreCatalog, quoted and charged
----------------------------------------------------------------------------------------------------
local OWNER = {
	Spins = { Cloud = 20, Storm = 40, Sky = 60, Celestial = 180 },
	Secret = 500,
	SecretOdds = { Mythic = 60, Secret = 40 },
	PityAt = 7,
	Packs = {
		{ Gems = 200, Robux = 49, Name = "Pouch of Gems" },
		{ Gems = 670, Robux = 149, Name = "Bag of Gems" },
		{ Gems = 1950, Robux = 399, Name = "Chest of Gems" },
		{ Gems = 5300, Robux = 999, Name = "Vault of Gems" },
	},
	TokenPacks = {
		{ Key = "Tokens1", Tokens = 1500, Robux = 49, Name = "1,500 Cloud Tokens" },
		{ Key = "Tokens2", Tokens = 7500, Robux = 149, Name = "7,500 Cloud Tokens" },
		{ Key = "Tokens3", Tokens = 30000, Robux = 399, Name = "30,000 Cloud Tokens" },
	},
	Mix = { Mythic = 40, Secret = 100 },
	Potion = 100,
	-- the token roulettes: the token prices and the Cloud / Storm / Sky odds unchanged; Celestial's odds the owner's
	Roulettes = {
		{ Id = "Cloud", Price = 50, Odds = { Common = 60, Uncommon = 28, Rare = 10, Epic = 2 } },
		{ Id = "Storm", Price = 250, Odds = { Uncommon = 35, Rare = 40, Epic = 20, Legendary = 5 } },
		{ Id = "Sky", Price = 1000, Odds = { Rare = 35, Epic = 45, Legendary = 17, Mythic = 3 } },
		{ Id = "Celestial", Price = 5000, Odds = { Epic = 43, Legendary = 40, Mythic = 15, Secret = 2 }, AllowSecret = true },
	},
	IndexLine = "A Secret pet. Summon it at the Storm Altar, or hatch it from the Celestial Roulette.",
}

-- a table holds exactly these keys with these values (no extra key)
local function exactly(t, want)
	if type(t) ~= "table" then
		return false
	end
	for k, v in pairs(want) do
		if t[k] ~= v then
			return false
		end
	end
	return count(t) == count(want)
end

local function show(t)
	if type(t) ~= "table" then
		return tostring(t)
	end
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		out[#out + 1] = k .. " = " .. tostring(t[k])
	end
	return "{ " .. table.concat(out, ", ") .. " }"
end

-- a file of the repo (smoke.py runs from the repo root; the smoke_p4_economy readRepoFile shape)
local function readRepoFile(rel)
	for _, path in ipairs({ rel, "../" .. rel }) do
		local fh = io.open(path, "r")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src
		end
	end
	return nil
end

S.gem_prices = guarded("gem_prices", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local D, Store, Gems = DS(), SS(), GS()
	local SC = requireAt("shared/StoreCatalog")
	local TC = requireAt("shared/TycoonCatalog")
	local PK = requireAt("shared/PetKeys")
	local F = K.mod("FusionService") or requireAt("server/Services/FusionService")
	local PetS = K.mod("PetService") or requireAt("server/Services/PetService")
	if not T.check(type(D) == "table" and type(Store) == "table" and type(Gems) == "table" and type(SC) == "table" and type(TC) == "table" and type(PK) == "table"
		and type(F) == "table" and type(PetS) == "table", "gem prices: DataService, StoreService, GemService, StoreCatalog, TycoonCatalog, PetKeys, FusionService and PetService load") then
		return
	end

	------------------------------------------------------------------------------------------------
	-- part 1: the numbers (Config, TycoonCatalog, StoreCatalog)
	------------------------------------------------------------------------------------------------
	local G = Config.Gems
	T.check(exactly(G.RouletteGemPrices, OWNER.Spins), "gem prices: Config.Gems.RouletteGemPrices = Cloud 20 / Storm 40 / Sky 60 / Celestial 180", show(G.RouletteGemPrices))
	local sr = G.SecretRoulette
	T.check(sr.GemPrice == OWNER.Secret and exactly(sr.Odds, OWNER.SecretOdds) and sr.PityAt == OWNER.PityAt and sr.AllowSecret == true,
		"gem prices: the Secret Roulette costs 500 gems at Mythic 60 / Secret 40, the pity at 7 kept, AllowSecret", tostring(sr.GemPrice) .. " " .. show(sr.Odds) .. " pity " .. tostring(sr.PityAt))
	local packs = T.tally("gem prices: Config.Gems.Products = 200 / 670 / 1,950 / 5,300 gems at the suggested 49 / 149 / 399 / 999 R$ (Id 0, names kept)")
	T.eq(#G.Products, #OWNER.Packs, "gem prices: four gem packs")
	for i, want in ipairs(OWNER.Packs) do
		local p = G.Products[i] or {}
		packs:case(p.Gems == want.Gems and p.Robux == want.Robux and p.Name == want.Name and p.Id == 0, i .. ": " .. show(p))
	end
	packs:report()
	local tok = T.tally("gem prices: Tokens1 / 2 / 3 grant 1,500 / 7,500 / 30,000 Cloud Tokens (names follow, Robux 49 / 149 / 399 kept)")
	for _, want in ipairs(OWNER.TokenPacks) do
		local it = itemOf(want.Key) or {}
		tok:case(exactly(it.Grants, { Tokens = want.Tokens }) and it.Name == want.Name and it.Robux == want.Robux, want.Key .. ": " .. tostring(it.Name) .. " " .. show(it.Grants) .. " " .. tostring(it.Robux))
	end
	tok:report()
	local potion = Config.Store.GemItems[1] or {}
	T.check(potion.Key == KEY and potion.Gems == OWNER.Potion and potion.Grants.Boost.XpPotion == 1800, "gem prices: the gem XP Potion (30 min) costs 100 gems", tostring(potion.Gems))
	local rows = T.tally("gem prices: the token roulettes keep their token prices and Cloud / Storm / Sky odds; Celestial is Epic 43 / Legendary 40 / Mythic 15 / Secret 2 with AllowSecret")
	T.eq(#Config.Roulettes, #OWNER.Roulettes, "gem prices: four token roulettes")
	for i, want in ipairs(OWNER.Roulettes) do
		local r = Config.Roulettes[i] or {}
		rows:case(r.Id == want.Id and r.Price == want.Price and exactly(r.Odds, want.Odds) and (r.AllowSecret == true) == (want.AllowSecret == true),
			tostring(r.Id) .. ": " .. tostring(r.Price) .. " " .. show(r.Odds) .. " AllowSecret " .. tostring(r.AllowSecret))
	end
	rows:report()
	local mix = TC.Fusion.Mix
	T.check(exactly(mix.Mythic, { Gems = OWNER.Mix.Mythic }) and exactly(mix.Secret, { Gems = OWNER.Mix.Secret }), "gem prices: TycoonCatalog.Fusion.Mix Mythic 40 / Secret 100 gems",
		show(mix.Mythic) .. " / " .. show(mix.Secret))
	T.check((TC.FusionCost("Mix", "Mythic", nil, 1) or {}).Gems == OWNER.Mix.Mythic and (TC.FusionCost("Mix", "Secret", nil, 1) or {}).Gems == OWNER.Mix.Secret,
		"gem prices: ...and FusionCost('Mix', rarity) answers them", show(TC.FusionCost("Mix", "Mythic", nil, 1)) .. " / " .. show(TC.FusionCost("Mix", "Secret", nil, 1)))
	-- StoreCatalog: the gem items carry Robux, the token items their new amounts
	local listed = T.tally("gem prices: StoreCatalog.List() gem items Gems1..4 carry Gems and Robux from Config")
	local byKey = {}
	for _, it in ipairs(SC.List()) do
		byKey[it.Key] = it
	end
	for i, want in ipairs(OWNER.Packs) do
		local it = byKey["Gems" .. i] or {}
		listed:case(it.Gem == true and type(it.Grants) == "table" and it.Grants.Gems == want.Gems and it.Robux == want.Robux and it.Name == want.Name, "Gems" .. i .. ": " .. show(it.Grants) .. " Robux " .. tostring(it.Robux))
	end
	listed:report()
	local tlist = T.tally("gem prices: StoreCatalog.Item(Tokens1..3) grants the new amounts with their names")
	for _, want in ipairs(OWNER.TokenPacks) do
		local it = SC.Item(want.Key) or {}
		tlist:case(type(it.Grants) == "table" and it.Grants.Tokens == want.Tokens and it.Name == want.Name and it.Robux == want.Robux, want.Key)
	end
	tlist:report()
	T.check((SC.GemItem(KEY) or {}).Gems == OWNER.Potion, "gem prices: StoreCatalog.GemItem('XpPotionGems').Gems == 100")
	T.check(select(1, SC.Validate()) == true, "gem prices: StoreCatalog.Validate passes on the new Config", table.concat(select(2, SC.Validate()) or {}, "; "))
	-- the client's Pet Index line for an undiscovered Secret pet (spec 16.1: Secret pets now hatch from Celestial too)
	local indexSrc = readRepoFile("src/client/Controllers/IndexController.lua")
	T.check(type(indexSrc) == "string" and indexSrc:find(OWNER.IndexLine, 1, true) ~= nil and indexSrc:find("It will be summoned at the Storm Altar with Gems", 1, true) == nil,
		"gem prices: IndexController's undiscovered Secret line reads '" .. OWNER.IndexLine .. "'", indexSrc and "" or "IndexController.lua not readable")

	------------------------------------------------------------------------------------------------
	-- part 2 (booted, settled, an allowed account): GemService.Quote, the charged spins, the Mixes, the potion
	------------------------------------------------------------------------------------------------
	local PolS = game:GetService("PolicyService")
	local players = {}
	PolS.GetPolicyInfoForPlayerAsync = function()
		return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = true }
	end
	local okRun, errRun = pcall(function()
		local errs0 = #Mock.Errors
		local p = join("GemPrices", newUserId())
		players[1] = p
		T.check(loaded(p) and D._SettleForTest(p) == true, "gem prices: (setup) a loaded, settled player")
		T.check(K.waitFor(function()
			return Gems.PolicyState(p) == "Allowed"
		end, 10), "gem prices: (setup) an allowed account (PolicyService double)", tostring(Gems.PolicyState(p)))
		local function setGems(n)
			D.SpendGems(p, D.GetGems(p))
			if n > 0 then
				D.AddGems(p, n)
			end
			return D.GetGems(p) == n
		end
		-- Quote: the owner's price and the roulette's own AllowSecret
		local quotes = T.tally("gem prices: GemService.Quote answers 20 / 40 / 60 / 180 / 500 (Secret allowed only by Celestial and the Secret Roulette)")
		local wantQuote = { { "Cloud", 20, false }, { "Storm", 40, false }, { "Sky", 60, false }, { "Celestial", 180, true }, { sr.Id, 500, true } }
		for _, w in ipairs(wantQuote) do
			local ok, q = Gems.Quote(p, w[1])
			quotes:case(ok == true and type(q) == "table" and q.Price == w[2] and q.AllowSecret == w[3], w[1] .. ": " .. tostring(ok) .. " " .. (type(q) == "table" and (tostring(q.Price) .. " AllowSecret " .. tostring(q.AllowSecret)) or tostring(q)))
		end
		quotes:report()
		-- every gem spin is charged its price once (shop-area 16.17.3: the Secret Roulette spins at the Storm Altar only,
		-- PetService's distance rule on the player's own character, so that row stands on the altar deck first)
		local SA = requireAt("server/Services/StormAltar")
		local altarCF = SA and type(SA.GetCFrame) == "function" and SA.GetCFrame() or nil
		local charged = T.tally("gem prices: a gem spin of every roulette is charged exactly its price (one charge, no tokens)")
		for _, w in ipairs(wantQuote) do
			if w[1] == sr.Id then
				T.check(typeof(altarCF) == "CFrame" and Mock.Teleport(p, altarCF * CFrame.new(0, 3, -8)) == true, "gem prices: (setup) the player stands on the Storm Altar's deck for the Secret Roulette")
			end
			K.advance(0.3)
			setGems(w[2] + 7)
			local t0 = D.GetTokens(p)
			local ok, res = PetS.BuyRoulette(p, w[1], "Gems")
			local sub = (ok == true and type(res) == "table" and type(res.Pulls) == "table" and res.Pulls[1] and type(res.Pulls[1].Substitute) == "table") and res.Pulls[1].Substitute.Tokens or 0
			charged:case(ok == true and D.GetGems(p) == 7 and D.GetTokens(p) == t0 + sub, w[1] .. ": " .. tostring(ok) .. " " .. (type(res) == "table" and tostring(res.Reason or res.Price) or tostring(res)) .. ", gems left " .. tostring(D.GetGems(p)))
		end
		charged:report()
		-- a Mythic Mix with gems charges 40, a Secret Mix 100
		D.MutateHome(p, function(h)
			h.Prestige = math.max(h.Prestige or 0, TC.Prestige.FusionUnlock or 1)
			h.Stations.FusionMachine = math.max(h.Stations.FusionMachine or 0, 1)
		end)
		local prof = D.GetProfile(p)
		for _, id in ipairs({ "pebble_pup", "cloudy_dragon", "pip_penguin", "stormfang", "maple_fox" }) do
			PK.Add(prof, id, 1)
		end
		D.MarkDirty(p)
		T.check(PK.DefOf("cloudy_dragon").Rarity == "Mythic" and PK.DefOf("stormfang").Rarity == "Secret", "gem prices: (setup) Cloudy Dragon is Mythic, Stormfang Secret")
		setGems(OWNER.Mix.Mythic + 5)
		local okM, keyM = F.Mix(p, "pebble_pup", "cloudy_dragon")
		T.check(okM == true and D.GetGems(p) == 5, "gem prices: a Mythic Mix with gems charges 40", tostring(keyM) .. ", gems left " .. tostring(D.GetGems(p)))
		setGems(OWNER.Mix.Secret + 5)
		local okS, keyS = F.Mix(p, "pip_penguin", "stormfang")
		T.check(okS == true and D.GetGems(p) == 5, "gem prices: a Secret Mix with gems charges 100", tostring(keyS) .. ", gems left " .. tostring(D.GetGems(p)))
		-- the XP Potion: 100 gems
		K.advance(1.1)
		setGems(OWNER.Potion + 3)
		local okP, whyP = Store.BuyWithGems(p, KEY)
		T.check(okP == true and D.GetGems(p) == 3, "gem prices: the gem XP Potion charges 100", tostring(whyP) .. ", gems left " .. tostring(D.GetGems(p)))
		T.eq(#Mock.Errors, errs0, "gem prices: nothing raised")
	end)
	PolS.GetPolicyInfoForPlayerAsync = nil
	for _, p in ipairs(players) do
		if p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(0.8)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("gem_prices")
	K.flushWarnings("gem_prices", ALLOWED_WARNINGS)
end)

return S
