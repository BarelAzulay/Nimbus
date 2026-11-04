-- smoke_fixr_store.lua: review fix A of the Robux Store build (docs/superpowers/specs/2026-11-04-shop-retention-design.md 7 Z6;
-- plan docs/superpowers/plans/2026-11-04-store.md Task 9 and the GetStore line "nil until loaded and while provisional"):
-- a bought Once pack is never prompted while the save is undecidable, and StoreBought is written only from a real record.
-- Server world only (booted):
--   fixr_store_prompt_provisional  a Once pack (Starter / Pro with non-zero Ids, so the refusal is the Once guard and not the
--                                  Created check) is refused with "Your save is still loading" while the save loads (a slow
--                                  DataStore) and while the profile is provisional (an outage), bought or not, by
--                                  PromptPurchase and by a hand-sent StoreRequest; a consumable is still prompted (its
--                                  receipt waits for the recovery, Z13); after the recovery the bought Starter answers "You
--                                  already have that!" and the unbought Pro is prompted
--   fixr_store_bought_attr         Multipliers' StoreBought attribute: absent while the save loads and while provisional (a
--                                  Refresh too), the csv after the recovery (ProfileRebased), "" on a loaded empty record,
--                                  and back to absent when GetStore answers nil again (a DataService.GetStore double)
--   fixr_store_boost_attr          (re-review 1, n2) XpBoostEnds follows the same rule: absent while the save loads and
--                                  while provisional (a Refresh too), the stored potion end once the record lands (the
--                                  load, the recovery), 0 on a loaded record with no potion, absent again when GetStore
--                                  answers nil (so the client's first XpBoostEnds is the real one, never a stand-in 0)
-- White-box: the booted helpers of smoke_store.lua (join / setId / savedIds / restoreIds / storeKey / storedRecord /
-- toastCount); the MarketplaceService prompt doubles are props (nil restores). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local MPS = game:GetService("MarketplaceService")
local LOADING = "Your save is still loading"
local HAVE = "You already have that!"

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
local function MU()
	return requireAt("server/Services/Multipliers")
end
local userSeq = 0
local function newUserId()
	userSeq = userSeq + 1
	return 991700 + userSeq
end
local function join(prefix, uid)
	local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
	K.advance(1.2)
	return p
end
local function leaveAll(list)
	for _, p in ipairs(list) do
		if p and p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(0.8)
end
local function loaded(p)
	return K.waitFor(function()
		return DS().GetProfile(p) ~= nil and DS().IsProvisional(p) ~= true
	end, 10)
end
local function provisional(p)
	return K.waitFor(function()
		return DS().IsProvisional(p) == true
	end, 10)
end
local function recovered(p)
	return K.waitFor(function()
		return DS().IsProvisional(p) ~= true and DS().GetStore(p) ~= nil
	end, 60)
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
local function storeKey(uid)
	return K.config().Tokens.DataStoreName .. "/u_" .. uid
end
-- a stored record the next join loads (the smoke_p7_data shape), here with Store.Bought
local function seedBought(uid, bought)
	Mock.DataStore.Data[storeKey(uid)] = {
		Version = 2, Tokens = 5, Pets = {}, Equipped = {}, Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		Store = { Bought = bought },
	}
end
-- a stored record with a Store record (Boosts / Bought / Passes maps of clocks)
local function seedStore(uid, store)
	Mock.DataStore.Data[storeKey(uid)] = {
		Version = 2, Tokens = 5, Pets = {}, Equipped = {}, Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		Store = store,
	}
end
-- Notify toasts to p since the log mark whose text holds `needle` (a plain find)
local function toastCount(p, needle, mark)
	local n = 0
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		if type(e.args[1]) == "string" and string.find(e.args[1], needle, 1, true) then
			n = n + 1
		end
	end
	return n
end
local function toastsSince(p, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		out[#out + 1] = tostring(e.args[1])
	end
	return table.concat(out, " | ")
end

----------------------------------------------------------------------------------------------------
-- fixr_store_prompt_provisional
----------------------------------------------------------------------------------------------------
S.fixr_store_prompt_provisional = guarded("fixr_store_prompt_provisional", function()
	if not K.needBoot() then
		return
	end
	local Store = SS()
	local SC = K.M["shared/StoreCatalog"] or requireAt("shared/StoreCatalog")
	local folder = K.remoteFolder()
	local remote = folder and folder:FindFirstChild("StoreRequest")
	if not T.check(type(Store) == "table" and type(Store.PromptPurchase) == "function" and type(SC) == "table" and remote ~= nil, "fixr store prompt: StoreService, StoreCatalog and the StoreRequest remote exist") then
		return
	end
	local DSt = Mock.DataStore
	local saved = { Ids = savedIds(), Fail = DSt.Fail, Latency = DSt.Latency }
	local players, prompts = {}, {}
	MPS.PromptProductPurchase = function(_, player, id)
		prompts[#prompts + 1] = { Kind = "Product", Player = player, Id = id }
	end
	MPS.PromptGamePassPurchase = function(_, player, id)
		prompts[#prompts + 1] = { Kind = "Pass", Player = player, Id = id }
	end
	local function promptsOf(p)
		local n = 0
		for _, e in ipairs(prompts) do
			if e.Player == p then
				n = n + 1
			end
		end
		return n
	end
	local okRun, errRun = pcall(function()
		-- Starter / Pro ship with Id 0 (refused by the Created check, "not on sale yet"): non-zero Ids put the refusal on the
		-- Once guard itself
		setId("Starter", 6301)
		setId("Pro", 6302)
		setId("Tokens1", 6303)
		T.check(SC.Item("Starter").Created == true and SC.Item("Starter").Once == true and SC.Item("Pro").Created == true and SC.Item("Pro").Once == true and SC.Item("Tokens1").Once ~= true,
			"fixr store prompt: (precondition) Starter / Pro are created Once packs, Tokens1 a consumable")

		-- the load window (1-3 s on Roblox): a slow DataStore keeps the save in flight
		DSt.Latency = 2
		local uidL = newUserId()
		seedBought(uidL, { Starter = os.time() - 86400 })
		local pl = Mock.AddPlayer("FixrLoad" .. tostring(uidL % 1000), uidL)
		players[#players + 1] = pl
		K.advance(0.5)
		T.check(DS().GetProfile(pl) == nil and DS().GetStore(pl) == nil, "fixr store prompt: (precondition) the save is still loading")
		local ok, why = Store.PromptPurchase(pl, "Starter")
		T.check(ok == false and why == LOADING and promptsOf(pl) == 0, "fixr store prompt: loading: the bought Starter is refused with 'Your save is still loading', no prompt", tostring(ok) .. " / " .. tostring(why))
		local mark = K.logSize()
		Mock.FromClient(remote, pl, "Buy", "Pro")
		K.advance(0.2)
		T.check(promptsOf(pl) == 0 and toastCount(pl, LOADING, mark) == 1, "fixr store prompt: loading: a hand-sent StoreRequest('Buy', 'Pro') prompts nothing, the loading toast", tostring(promptsOf(pl)) .. " prompts | " .. toastsSince(pl, mark))
		DSt.Latency = saved.Latency
		T.check(loaded(pl), "fixr store prompt: (precondition) the load lands")
		K.advance(1.1)
		ok, why = Store.PromptPurchase(pl, "Starter")
		T.check(ok == false and why == HAVE and promptsOf(pl) == 0, "fixr store prompt: loaded: the bought Starter answers 'You already have that!'", tostring(ok) .. " / " .. tostring(why))

		-- provisional (an outage at the load): ProfileLoaded is true, the Store opens, GetStore answers nil
		DSt.Fail = true
		local uidP = newUserId()
		seedBought(uidP, { Starter = os.time() - 86400 })
		local prov = join("FixrProv", uidP)
		players[#players + 1] = prov
		T.check(provisional(prov), "fixr store prompt: (precondition) a load during an outage leaves a provisional profile")
		T.check(prov:GetAttribute(K.config().Attr.ProfileLoaded) == true and DS().GetStore(prov) == nil, "fixr store prompt: (precondition) ProfileLoaded is true for the stand-in and GetStore answers nil")
		ok, why = Store.PromptPurchase(prov, "Starter")
		T.check(ok == false and why == LOADING and promptsOf(prov) == 0, "fixr store prompt: provisional: the Starter bought yesterday is refused (no second 99 R$ charge)", tostring(ok) .. " / " .. tostring(why))
		ok, why = Store.PromptPurchase(prov, "Pro")
		T.check(ok == false and why == LOADING and promptsOf(prov) == 0, "fixr store prompt: provisional: an unbought Once pack is refused too (undecidable, not unbought)", tostring(ok) .. " / " .. tostring(why))
		mark = K.logSize()
		Mock.FromClient(remote, prov, "Buy", "Starter")
		K.advance(0.2)
		T.check(promptsOf(prov) == 0 and toastCount(prov, LOADING, mark) == 1, "fixr store prompt: provisional: StoreRequest('Buy', 'Starter') prompts nothing, the loading toast", tostring(promptsOf(prov)) .. " prompts | " .. toastsSince(prov, mark))
		K.advance(1.1)
		ok, why = Store.PromptPurchase(prov, "Tokens1")
		T.check(ok == true and promptsOf(prov) == 1 and prompts[#prompts].Id == 6303, "fixr store prompt: provisional: a consumable is still prompted (its receipt waits for the recovery, Z13)", tostring(ok) .. " / " .. tostring(why))
		DSt.Fail = saved.Fail
		T.check(recovered(prov), "fixr store prompt: (precondition) the recovery reads the real save")
		T.check(DS().GetStore(prov) ~= nil and DS().GetStore(prov).Bought.Starter ~= nil, "fixr store prompt: (precondition) the recovered record holds Bought.Starter")
		K.advance(1.1)
		ok, why = Store.PromptPurchase(prov, "Starter")
		T.check(ok == false and why == HAVE and promptsOf(prov) == 1, "fixr store prompt: recovered: the Starter answers 'You already have that!'", tostring(ok) .. " / " .. tostring(why))
		K.advance(1.1)
		ok, why = Store.PromptPurchase(prov, "Pro")
		T.check(ok == true and promptsOf(prov) == 2 and prompts[#prompts].Kind == "Product" and prompts[#prompts].Id == 6302, "fixr store prompt: recovered: the unbought Pro is prompted (PromptProductPurchase 6302)", tostring(ok) .. " / " .. tostring(why))
	end)
	MPS.PromptProductPurchase = nil
	MPS.PromptGamePassPurchase = nil
	DSt.Latency = saved.Latency
	DSt.Fail = saved.Fail
	restoreIds(saved.Ids)
	leaveAll(players)
	if not okRun then
		error(errRun, 0)
	end
end)

----------------------------------------------------------------------------------------------------
-- fixr_store_bought_attr
----------------------------------------------------------------------------------------------------
S.fixr_store_bought_attr = guarded("fixr_store_bought_attr", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local Store, Mult, D = SS(), MU(), DS()
	local ATTR = Config.Attr and Config.Attr.StoreBought
	if not T.check(type(Store) == "table" and type(Mult) == "table" and type(Mult.Refresh) == "function" and type(D) == "table" and ATTR == "StoreBought", "fixr store attr: StoreService, Multipliers, DataService and Config.Attr.StoreBought") then
		return
	end
	local DSt = Mock.DataStore
	local saved = { Fail = DSt.Fail, Latency = DSt.Latency, GetStore = D.GetStore }
	local players = {}
	local okRun, errRun = pcall(function()
		-- the load window: no record yet, no attribute
		DSt.Latency = 2
		local uidL = newUserId()
		seedBought(uidL, { Starter = os.time() - 86400 })
		local pl = Mock.AddPlayer("FixrAttrLoad" .. tostring(uidL % 1000), uidL)
		players[#players + 1] = pl
		K.advance(0.5)
		T.check(D.GetProfile(pl) == nil, "fixr store attr: (precondition) the save is still loading")
		T.eq(pl:GetAttribute(ATTR), nil, "fixr store attr: StoreBought is absent while the save loads")
		DSt.Latency = saved.Latency
		T.check(loaded(pl), "fixr store attr: (precondition) the load lands")
		K.advance(0.2)
		T.eq(pl:GetAttribute(ATTR), "Starter", "fixr store attr: ...the csv once it lands (ProfileLoaded)")

		-- provisional: absent (not "": the client would draw a bought Starter as Buy), a Refresh too
		DSt.Fail = true
		local uidP = newUserId()
		seedBought(uidP, { Starter = os.time() - 86400 })
		local prov = join("FixrAttrProv", uidP)
		players[#players + 1] = prov
		T.check(provisional(prov), "fixr store attr: (precondition) a load during an outage leaves a provisional profile")
		T.check(prov:GetAttribute(Config.Attr.ProfileLoaded) == true, "fixr store attr: (precondition) ProfileLoaded is true for the stand-in (the Store opens)")
		T.eq(prov:GetAttribute(ATTR), nil, "fixr store attr: StoreBought is absent while provisional")
		Store.Refresh(prov)
		K.advance(0.2)
		T.eq(prov:GetAttribute(ATTR), nil, "fixr store attr: ...still absent after StoreService.Refresh (Changed -> Multipliers.Refresh)")
		DSt.Fail = saved.Fail
		T.check(recovered(prov), "fixr store attr: (precondition) the recovery reads the real save")
		K.advance(0.2)
		T.eq(prov:GetAttribute(ATTR), "Starter", "fixr store attr: the csv after the recovery (ProfileRebased -> Refresh)")

		-- a loaded empty record: ""
		local fresh = join("FixrAttrNew", newUserId())
		players[#players + 1] = fresh
		T.check(loaded(fresh), "fixr store attr: (precondition) a new player's empty record loads")
		K.advance(0.2)
		T.eq(fresh:GetAttribute(ATTR), "", "fixr store attr: '' on a loaded empty record (nothing bought)")

		-- the record turns undecidable again (a GetStore double answering nil): set back to absent, then "" once it answers
		D.GetStore = function()
			return nil
		end
		Mult.Refresh(fresh)
		T.eq(fresh:GetAttribute(ATTR), nil, "fixr store attr: set back to absent when GetStore answers nil")
		D.GetStore = saved.GetStore
		Mult.Refresh(fresh)
		T.eq(fresh:GetAttribute(ATTR), "", "fixr store attr: ...and '' again once it answers")
	end)
	D.GetStore = saved.GetStore
	DSt.Latency = saved.Latency
	DSt.Fail = saved.Fail
	leaveAll(players)
	if not okRun then
		error(errRun, 0)
	end
end)

----------------------------------------------------------------------------------------------------
-- fixr_store_boost_attr (re-review round 1, open item n2)
----------------------------------------------------------------------------------------------------
S.fixr_store_boost_attr = guarded("fixr_store_boost_attr", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local Store, Mult, D = SS(), MU(), DS()
	local ATTR = Config.Attr and Config.Attr.XpBoostEnds
	if not T.check(type(Store) == "table" and type(Mult) == "table" and type(Mult.Refresh) == "function" and type(D) == "table" and ATTR == "XpBoostEnds", "fixr store boost attr: StoreService, Multipliers, DataService and Config.Attr.XpBoostEnds") then
		return
	end
	local DSt = Mock.DataStore
	local saved = { Fail = DSt.Fail, Latency = DSt.Latency, GetStore = D.GetStore }
	local players = {}
	local okRun, errRun = pcall(function()
		-- the load window: no record yet, no attribute (not a stand-in 0)
		DSt.Latency = 2
		local uidL = newUserId()
		local endsL = os.time() + 1800
		seedStore(uidL, { Boosts = { XpPotion = endsL } })
		local pl = Mock.AddPlayer("FixrBoostLoad" .. tostring(uidL % 1000), uidL)
		players[#players + 1] = pl
		K.advance(0.5)
		T.check(D.GetProfile(pl) == nil, "fixr store boost attr: (precondition) the save is still loading")
		T.eq(pl:GetAttribute(ATTR), nil, "fixr store boost attr: XpBoostEnds is absent while the save loads")
		DSt.Latency = saved.Latency
		T.check(loaded(pl), "fixr store boost attr: (precondition) the load lands")
		K.advance(0.2)
		T.eq(pl:GetAttribute(ATTR), endsL, "fixr store boost attr: ...the stored potion end once it lands (ProfileLoaded)")

		-- provisional: absent, a Refresh too
		DSt.Fail = true
		local uidP = newUserId()
		local endsP = os.time() + 3000
		seedStore(uidP, { Boosts = { XpPotion = endsP } })
		local prov = join("FixrBoostProv", uidP)
		players[#players + 1] = prov
		T.check(provisional(prov), "fixr store boost attr: (precondition) a load during an outage leaves a provisional profile")
		T.eq(prov:GetAttribute(ATTR), nil, "fixr store boost attr: XpBoostEnds is absent while provisional")
		Store.Refresh(prov)
		K.advance(0.2)
		T.eq(prov:GetAttribute(ATTR), nil, "fixr store boost attr: ...still absent after StoreService.Refresh (Changed -> Multipliers.Refresh)")
		DSt.Fail = saved.Fail
		T.check(recovered(prov), "fixr store boost attr: (precondition) the recovery reads the real save")
		K.advance(0.2)
		T.eq(prov:GetAttribute(ATTR), endsP, "fixr store boost attr: the stored end after the recovery (ProfileRebased -> Refresh)")

		-- a loaded record with no potion: 0
		local fresh = join("FixrBoostNew", newUserId())
		players[#players + 1] = fresh
		T.check(loaded(fresh), "fixr store boost attr: (precondition) a new player's empty record loads")
		K.advance(0.2)
		T.eq(fresh:GetAttribute(ATTR), 0, "fixr store boost attr: 0 on a loaded record with no potion")

		-- the record turns undecidable again (a GetStore double answering nil): absent, then 0 once it answers
		D.GetStore = function()
			return nil
		end
		Mult.Refresh(fresh)
		T.eq(fresh:GetAttribute(ATTR), nil, "fixr store boost attr: set back to absent when GetStore answers nil")
		D.GetStore = saved.GetStore
		Mult.Refresh(fresh)
		T.eq(fresh:GetAttribute(ATTR), 0, "fixr store boost attr: ...and 0 again once it answers")
	end)
	D.GetStore = saved.GetStore
	DSt.Latency = saved.Latency
	DSt.Fail = saved.Fail
	leaveAll(players)
	if not okRun then
		error(errRun, 0)
	end
end)

return S
