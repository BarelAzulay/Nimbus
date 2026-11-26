-- smoke_store_switch.lua: release step 1, gate 1: the Store off switch (Config.Store.Enabled).
-- The shipped Config has Enabled = false. tools/smoke_common.lua turns it ON for every other list (they pin the Store's
-- own behaviour, exactly as before this gate) and keeps the shipped value in SmokeCommon.StoreShipped; the scenarios
-- here set the switch themselves and put the harness value back.
-- Server world (booted):
--   store_switch_shipped  the shipped line is exactly false; StoreCatalog.Enabled() is true only for an explicit true
--   store_switch_off      off + every Store item CREATED (non-zero Ids, so the refusal is the switch and not "Id 0"):
--                         StoreRequest "Buy" / PromptPurchase of a pack, a pass, a potion and a token pack prompt
--                         nothing; "GemBuy" / BuyWithGems charge nothing and add no potion; no toast; StorePreview is
--                         false even in Studio. What main already sells keeps working: a created gem pack is prompted.
--                         Receipts and passes stay ON: a paid token pack, potion, Starter Pack and gem pack are granted,
--                         an owned pass is Owned (UserOwnsGamePassAsync). PromptGamePassPurchaseFinished(true) alone
--                         grants nothing (a forged signal): Owned, the ledger and the thank-you wait for the engine's
--                         UserOwnsGamePassAsync to confirm (retried), in both switch states.
--   store_switch_on       on: the same requests prompt / charge as they did before this gate, the preview flag is back
-- Client world (1920x1080) and phone world:
--   client_store_switch          off: the Shop opens on Eggs with ONE rail tab, no divider, no cards, no PREVIEW /
--                                "Coming soon" / "opens soon" text (a Studio dev with StorePreview too), a hidden tab
--                                asked by name lands on Eggs, no GetProductInfo, no StoreRequest. Off + created gem
--                                packs: Eggs + Gems in the first two slots, only the gem packs on the Gems page (no
--                                potion, no token packs, no dead scroll space), Buy -> StoreRequest("Buy", "Gems1").
--                                On: the five tabs, the divider, the potion and the token packs are back.
--   client_store_switch_mobile   off at 390x844 and 844x390: one tab (two with gem packs) inside the window, finite
--                                positions, the Gems row holds the gem packs only
--   (combined release, kit-b's restyle: H.offAt) off at 1920x1080, 1024x600 (kit-b's Short rail under the Fast toggle),
--   1280x720, 1366x768, 390x844 and 844x390 with a Studio dev's preview flag: one rail tab, no "ROBUX ITEMS" rule (the
--   captioned divider, its label and dotted rules), no Starter square, no "opens soon", no card, no Store text (matched
--   without case: "ROBUX ITEMS", a "Preview" Buy, the items' names) in the Shop window or anywhere in the PlayerGui, the
--   Fast toggle in the rail clear of the tab; then on at the same size: the five tabs
-- Every scenario restores the switch, the Config ids, the attributes and the doubles. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"
local fmt = string.format

----------------------------------------------------------------------------------------------------
-- server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local MPS = game:GetService("MarketplaceService")

	local function requireAt(key)
		local inst = K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
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
	local function SC()
		return K.M["shared/StoreCatalog"] or requireAt("shared/StoreCatalog")
	end
	local userSeq = 0
	local function newUserId()
		userSeq = userSeq + 1
		return 995300 + userSeq
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
	local function itemOf(key)
		for _, it in ipairs(K.config().Store.Items) do
			if it.Key == key then
				return it
			end
		end
		return nil
	end
	local function saveIds()
		local out = { Items = {}, Gems = {} }
		for _, it in ipairs(K.config().Store.Items) do
			out.Items[it.Key] = it.Id
		end
		for i, p in ipairs(K.config().Gems.Products) do
			out.Gems[i] = p.Id
		end
		return out
	end
	local function restoreIds(saved)
		for _, it in ipairs(K.config().Store.Items) do
			it.Id = saved.Items[it.Key] or 0
		end
		for i, p in ipairs(K.config().Gems.Products) do
			p.Id = saved.Gems[i] or 0
		end
	end
	local function spawnCall(fn, ...)
		local box = { done = false }
		local args = { n = select("#", ...), ... }
		task.spawn(function()
			local ok, result = pcall(fn, unpack(args, 1, args.n))
			box.ok, box.result, box.done = ok, result, true
		end)
		return box
	end
	local function receipt(p, productId, purchaseId)
		return { PlayerId = p.UserId, ProductId = productId, PurchaseId = purchaseId, CurrencySpent = 49, PlaceIdWherePurchased = 1 }
	end
	local function runReceipt(cb, info)
		local box = spawnCall(cb, info)
		K.waitFor(function()
			return box.done
		end, 60)
		if not box.done then
			return "unfinished"
		end
		if not box.ok then
			return "error: " .. tostring(box.result)
		end
		return box.result
	end
	-- the STORE's toasts to p since the mark: every line StoreService can say (its TEXT table). Other systems toast a fresh
	-- player too ("Pick a free home: press E at its gate!"), which is not the Store answering, so only these count.
	local STORE_SAYS = { "Store", "not on sale", "already have", "still loading", "wait a moment", "purchase window", "Stack full", "Checking", "otion", "Not enough gems",
		"Token packs", "Thank you" }
	local function toasts(p, mark)
		local out = {}
		for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
			local text = tostring(e.args[1])
			for _, needle in ipairs(STORE_SAYS) do
				if string.find(text, needle, 1, true) then
					out[#out + 1] = text
					break
				end
			end
		end
		return out
	end
	-- the ids every scenario uses: every Store item and every gem pack CREATED
	local IDS = { Starter = 8101, Pro = 8102, VIP = 8201, Cash2x = 8202, PetXp2x = 8203, XpPotion1 = 8103, XpPotion3 = 8104, Tokens1 = 8105, Tokens2 = 8106, Tokens3 = 8107 }
	local GEM_IDS = { 8301, 8302, 8303, 8304 }
	local function createAll()
		for key, id in pairs(IDS) do
			local it = itemOf(key)
			if it then
				it.Id = id
			end
		end
		for i, p in ipairs(K.config().Gems.Products) do
			p.Id = GEM_IDS[i] or (8300 + i)
		end
	end

	S.store_switch_shipped = guarded("store_switch_shipped", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local Catalog = SC()
		T.check(SmokeCommon.StoreShipped == false, "store switch: the shipped Config.Store.Enabled is exactly false (one Config line turns the Store on later)",
			"shipped value: " .. tostring(SmokeCommon.StoreShipped))
		if not T.check(type(Catalog) == "table" and type(Catalog.Enabled) == "function", "store switch: StoreCatalog.Enabled exists (the one reading of the switch)") then
			return
		end
		local saved = Config.Store.Enabled
		local ok, err = pcall(function()
			Config.Store.Enabled = true
			T.eq(Catalog.Enabled(), true, "store switch: Enabled = true -> on")
			Config.Store.Enabled = false
			T.eq(Catalog.Enabled(), false, "store switch: Enabled = false -> off")
			Config.Store.Enabled = nil
			T.eq(Catalog.Enabled(), false, "store switch: a missing line is OFF (fail closed), never on by accident")
			Config.Store.Enabled = "yes"
			T.eq(Catalog.Enabled(), false, "store switch: anything but true is off")
		end)
		Config.Store.Enabled = saved
		T.check(ok, "store switch: the shipped-line scenario ran to its end", tostring(err))
	end)

	-- one body for both states, so "on" proves the very requests "off" refuses
	local function run(on)
		local tag = on and "store switch on: " or "store switch off: "
		local Config = K.config()
		local Store, Gems, Catalog = SS(), GS(), SC()
		local folder = K.remoteFolder()
		local remote = folder and folder:FindFirstChild("StoreRequest")
		if not T.check(type(Store) == "table" and type(Gems) == "table" and type(Catalog) == "table" and remote ~= nil, tag .. "StoreService, GemService, StoreCatalog and StoreRequest exist") then
			return
		end
		local saved = { Ids = saveIds(), Enabled = Config.Store.Enabled, Studio = Mock.Options.Studio, Policy = Gems.PolicyState }
		local players, prompts = {}, {}
		MPS.PromptProductPurchase = function(_, player, id)
			prompts[#prompts + 1] = { Kind = "Product", Player = player, Id = id }
		end
		MPS.PromptGamePassPurchase = function(_, player, id)
			prompts[#prompts + 1] = { Kind = "Pass", Player = player, Id = id }
		end
		local owners = {} -- [uid] = pass id the engine says is owned
		-- what the engine answers for one pass id from now on (release step 1 follow-up): { [passId] = true | false |
		-- "error" | { answer, answer... } (one per call, the last one stays) }
		local engine, lookups = {}, {}
		MPS.UserOwnsGamePassAsync = function(_, uid, id)
			lookups[id] = (lookups[id] or 0) + 1
			local answer = engine[id]
			if type(answer) == "table" then
				answer = answer[math.min(lookups[id] - (answer.From or 0), #answer)]
			end
			if answer == "error" then
				error("HTTP 503 (smoke: pass lookup outage)")
			end
			return owners[uid] == id or answer == true
		end
		-- the token packs are prompted only for an "Allowed" account (lobby-shop 16.1): answered here, so a refusal below
		-- is the switch and nothing else
		Gems.PolicyState = function()
			return "Allowed"
		end
		local okRun, errRun = pcall(function()
			createAll()
			Config.Store.Enabled = on
			Mock.Options.Studio = true
			local uid = newUserId()
			owners[uid] = IDS.VIP
			local p = join("Switch", uid)
			players[#players + 1] = p
			T.check(loaded(p), tag .. "(precondition) the profile is loaded")
			T.check(DS()._SettleForTest(p) == true and DS().AddGems(p, 1000) == true, tag .. "(setup) settled, +1000 gems")
			K.advance(1.1)

			-- the preview flag (Studio: every dev would see PREVIEW cards)
			T.eq(p:GetAttribute(Config.Attr.StorePreview), on, tag .. "StorePreview in Studio is " .. tostring(on))
			T.eq(Store.IsPreview(p), on, tag .. "StoreService.IsPreview is " .. tostring(on))

			-- the Robux items quick-wins added: a pack, a pass, a potion, a token pack
			local mark = K.logSize()
			local asked = { "Starter", "Cash2x", "XpPotion1", "Tokens1" }
			for _, key in ipairs(asked) do
				local n = #prompts
				local ok, why = Store.PromptPurchase(p, key)
				if on then
					T.check(ok == true and #prompts == n + 1 and prompts[#prompts].Id == IDS[key], tag .. "PromptPurchase('" .. key .. "') prompts id " .. IDS[key], tostring(ok) .. " / " .. tostring(why))
				else
					T.check(ok == false and #prompts == n, tag .. "PromptPurchase('" .. key .. "') is refused, no prompt", tostring(ok) .. " / " .. tostring(why) .. ", prompts " .. (#prompts - n))
				end
				K.advance(1.1)
			end
			local before = #prompts
			for _, key in ipairs(asked) do
				Mock.FromClient(remote, p, "Buy", key)
				K.advance(1.1)
			end
			if on then
				T.eq(#prompts - before, #asked, tag .. "a hand-sent StoreRequest('Buy') of each prompts once")
			else
				T.eq(#prompts - before, 0, tag .. "a hand-sent StoreRequest('Buy') of each prompts nothing")
				T.check(#toasts(p, mark) == 0, tag .. "...and says nothing (no toast for an item that is not shown)", table.concat(toasts(p, mark), " | "))
			end

			-- the gem item quick-wins added: the 30-minute XP Potion for gems
			local price = Config.Store.GemItems[1].Gems
			local gems0, ends0 = DS().GetGems(p), Store.BoostEnds(p, "XpPotion")
			mark = K.logSize()
			Mock.FromClient(remote, p, "GemBuy", "XpPotionGems")
			K.advance(1.1)
			if on then
				T.check(DS().GetGems(p) == gems0 - price and Store.BoostEnds(p, "XpPotion") > ends0, tag .. "StoreRequest('GemBuy') charges " .. price .. " gems and starts the potion")
			else
				T.check(DS().GetGems(p) == gems0 and Store.BoostEnds(p, "XpPotion") == ends0, tag .. "StoreRequest('GemBuy') charges nothing and adds no potion",
					fmt("gems %s -> %s, ends %s -> %s", tostring(gems0), tostring(DS().GetGems(p)), tostring(ends0), tostring(Store.BoostEnds(p, "XpPotion"))))
				T.check(#toasts(p, mark) == 0, tag .. "...and says nothing", table.concat(toasts(p, mark), " | "))
				local okBuy, why = Store.BuyWithGems(p, "XpPotionGems")
				T.check(okBuy == false and DS().GetGems(p) == gems0, tag .. "BuyWithGems is refused for any caller", tostring(okBuy) .. " / " .. tostring(why))
			end

			-- what main already sells: a created gem pack is prompted in both states
			K.advance(1.1)
			local n = #prompts
			Mock.FromClient(remote, p, "Buy", "Gems1")
			K.advance(0.3)
			T.check(#prompts == n + 1 and prompts[#prompts].Id == GEM_IDS[1] and prompts[#prompts].Kind == "Product", tag .. "a created gem pack (main sells these) is still prompted",
				"prompts " .. (#prompts - n))

			-- receipts are ALWAYS granted (a product bought while the Store was on, a retry Roblox sends later)
			local cb = type(MPS.ProcessReceipt) == "function" and MPS.ProcessReceipt or Gems.ProcessReceipt
			local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
			local tok0 = DS().GetTokens(p)
			T.eq(runReceipt(cb, receipt(p, IDS.Tokens1, "sw-tok-" .. tostring(on))), GRANTED, tag .. "a paid token pack receipt answers PurchaseGranted")
			T.eq(DS().GetTokens(p), tok0 + itemOf("Tokens1").Grants.Tokens, tag .. "...and the Tokens arrive")
			local endsA = Store.BoostEnds(p, "XpPotion")
			T.eq(runReceipt(cb, receipt(p, IDS.XpPotion1, "sw-pot-" .. tostring(on))), GRANTED, tag .. "a paid potion receipt answers PurchaseGranted")
			T.check(Store.BoostEnds(p, "XpPotion") >= math.max(endsA, os.time()) + 3600 - 5, tag .. "...and the potion hour arrives")
			T.eq(runReceipt(cb, receipt(p, IDS.Starter, "sw-start-" .. tostring(on))), GRANTED, tag .. "a paid Starter Pack receipt answers PurchaseGranted")
			local store = DS().GetStore(p)
			T.check(type(store) == "table" and type(store.Bought) == "table" and store.Bought.Starter ~= nil, tag .. "...and it is recorded in Store.Bought")
			local g0 = DS().GetGems(p)
			T.eq(runReceipt(cb, receipt(p, GEM_IDS[1], "sw-gem-" .. tostring(on))), GRANTED, tag .. "a paid gem pack receipt answers PurchaseGranted")
			T.eq(DS().GetGems(p), g0 + Config.Gems.Products[1].Gems, tag .. "...and the gems arrive")

			-- an owned pass stays owned (the join lookup and a finished pass purchase)
			T.check(Store.Owns(p, "VIP") == true, tag .. "a pass the engine says is owned is Owned", tostring(Store.PassState(p, "VIP")))
			T.check(string.find(tostring(p:GetAttribute(Config.Attr.OwnedPasses)), "VIP", 1, true) ~= nil, tag .. "...and OwnedPasses lists it (its perk still applies)", tostring(p:GetAttribute(Config.Attr.OwnedPasses)))
			-- release step 1 follow-up: PromptGamePassPurchaseFinished(wasPurchased = true) is only a hint. An exploit client
			-- can fire that signal itself, so it alone never marks a pass Owned, never writes the saved ledger and never
			-- thanks: the server asks UserOwnsGamePassAsync (a few tries), then leaves it to the normal ownership check.
			-- (This replaces "a finished pass purchase is Owned at once", which pinned the unsafe behaviour.)
			local function ledger(key)
				local st = DS().GetStore(p)
				return type(st) == "table" and type(st.Passes) == "table" and st.Passes[key] or nil
			end
			local function thanks(from)
				local n = 0
				for _, text in ipairs(toasts(p, from)) do
					if string.find(text, "Thank you", 1, true) then
						n = n + 1
					end
				end
				return n
			end
			-- 1. a FORGED signal: the engine says the pass is not owned
			engine[IDS.PetXp2x] = false
			local seen = lookups[IDS.PetXp2x] or 0
			mark = K.logSize()
			Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p, IDS.PetXp2x, true)
			K.advance(0.3)
			T.check(Store.Owns(p, "PetXp2x") == false and Store.PassState(p, "PetXp2x") ~= "Owned", tag .. "a forged 'pass purchase finished' signal does NOT make the pass Owned", tostring(Store.PassState(p, "PetXp2x")))
			for _ = 1, 20 do
				Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p, IDS.PetXp2x, true)
			end
			K.advance(180) -- past every confirmation retry
			T.check(Store.Owns(p, "PetXp2x") == false and Store.PassState(p, "PetXp2x") == "NotOwned", tag .. "...not after every retry either, however often it is fired", tostring(Store.PassState(p, "PetXp2x")))
			T.check(string.find(tostring(p:GetAttribute(Config.Attr.OwnedPasses)), "PetXp2x", 1, true) == nil, tag .. "...OwnedPasses does not list it (no perk)", tostring(p:GetAttribute(Config.Attr.OwnedPasses)))
			T.check(ledger("PetXp2x") == nil, tag .. "...nothing is written to the saved ledger (Store.Passes)", tostring(ledger("PetXp2x")))
			T.eq(thanks(mark), 0, tag .. "...and nobody is thanked")
			local asked = (lookups[IDS.PetXp2x] or 0) - seen
			T.check(asked >= 2 and asked <= 8, tag .. "...the 21 forged signals cost a few UserOwnsGamePassAsync calls, not one each (2..8)", tostring(asked))
			-- 2. a REAL purchase the engine confirms at once
			engine[IDS.PetXp2x] = true
			mark = K.logSize()
			Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p, IDS.PetXp2x, true)
			K.advance(0.5)
			T.check(Store.Owns(p, "PetXp2x") == true, tag .. "a finished pass purchase the engine confirms is Owned within half a second", tostring(Store.PassState(p, "PetXp2x")))
			T.check(ledger("PetXp2x") ~= nil and thanks(mark) == 1, tag .. "...the ledger is written and the player is thanked once", tostring(ledger("PetXp2x")) .. " / " .. thanks(mark))
			-- 3. a REAL purchase the engine only confirms late (its ownership cache), with an outage in between
			engine[IDS.Cash2x] = { false, "error", false, true, From = lookups[IDS.Cash2x] or 0 }
			mark = K.logSize()
			Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p, IDS.Cash2x, true)
			K.advance(0.5)
			T.check(Store.Owns(p, "Cash2x") == false and thanks(mark) == 0, tag .. "a finished purchase the engine does not confirm yet is not Owned and not thanked yet", tostring(Store.PassState(p, "Cash2x")))
			K.advance(120)
			T.check(Store.Owns(p, "Cash2x") == true and ledger("Cash2x") ~= nil, tag .. "...the retries find it Owned once the engine confirms (a false, an outage, a false, then true)", tostring(Store.PassState(p, "Cash2x")))
			T.eq(thanks(mark), 1, tag .. "...and the player is thanked once")
			-- 4. wasPurchased = false and an unknown pass id ask nothing
			seen = lookups[IDS.VIP] or 0
			Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p, IDS.VIP, false)
			Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p, 424242, true)
			K.advance(5)
			T.check((lookups[IDS.VIP] or 0) == seen and (lookups[424242] or 0) == 0, tag .. "wasPurchased = false and an unknown pass id start no lookup")
		end)
		Config.Store.Enabled = saved.Enabled
		Mock.Options.Studio = saved.Studio
		Gems.PolicyState = saved.Policy
		MPS.PromptProductPurchase = nil
		MPS.PromptGamePassPurchase = nil
		MPS.UserOwnsGamePassAsync = nil
		leaveAll(players)
		restoreIds(saved.Ids)
		T.check(okRun, tag .. "the scenario ran to its end", tostring(errRun))
	end

	-- release step 1 follow-up (the owner's pick, 2026-11-23): the PolicyService lock on TOKEN spins (lobby-shop 16.12)
	-- belongs to a Store that sells Tokens for Robux. While the Store is off nothing sells Tokens, so a restricted account,
	-- an account whose PolicyService lookup errors and one with no PolicyService answer at all spin with Tokens exactly as
	-- on origin/main (which has no such lock). On: the 16.12 lock, unchanged. Gem spins keep main's own lock in both states.
	local function runSpins(on)
		local tag = on and "store switch on, token spins: " or "store switch off, token spins: "
		local TOKEN_LOCK, CHECKING = "Token spins are not available on your account", "Checking your account, try again in a moment"
		local Config = K.config()
		local Gems, PS = GS(), K.mod("PetService")
		local PolS = game:GetService("PolicyService")
		local folder = K.remoteFolder()
		local remote = folder and folder:FindFirstChild("BuyRoulette")
		local cloud = Config.Roulettes[1]
		if not T.check(type(Gems) == "table" and type(Gems.TokenSpinLock) == "function" and type(PS) == "table" and type(PS.BuyRoulette) == "function" and remote ~= nil and type(cloud) == "table",
			tag .. "GemService.TokenSpinLock, PetService.BuyRoulette and the BuyRoulette remote exist") then
			return
		end
		local saved = { Enabled = Config.Store.Enabled, Lock = Gems.TokenSpinLock }
		local players, modes = {}, {}
		local function install()
			PolS.GetPolicyInfoForPlayerAsync = function(_, player)
				if modes[player.UserId] == "error" then
					error("smoke: PolicyService is down")
				end
				return { ArePaidRandomItemsRestricted = modes[player.UserId] == "restrict", IsPaidItemTradingAllowed = true }
			end
		end
		local function joinAs(prefix, mode)
			local uid = newUserId()
			modes[uid] = mode
			local p = join(prefix, uid)
			players[#players + 1] = p
			T.check(loaded(p), tag .. "(precondition) " .. prefix .. "'s profile is loaded")
			DS()._SettleForTest(p)
			DS().AddTokens(p, 100000)
			DS().AddGems(p, 5000)
			return p
		end
		local okRun, errRun = pcall(function()
			Config.Store.Enabled = on
			install()
			local allowed = joinAs("SpinAllow", "allow")
			local restricted = joinAs("SpinRestr", "restrict")
			local failing = joinAs("SpinFail", "error")
			PolS.GetPolicyInfoForPlayerAsync = false -- (the mock: no PolicyService API at all, so no answer ever comes)
			local absent = joinAs("SpinNoApi", "allow")
			K.advance(1.1)
			T.eq(Gems.PolicyState(allowed), "Allowed", tag .. "(precondition) the allowed account's policy answer is 'Allowed'")
			T.eq(Gems.PolicyState(restricted), "Restricted", tag .. "(precondition) the restricted account's policy answer is 'Restricted'")
			T.eq(Gems.PolicyState(failing), "Checking", tag .. "(precondition) a failing PolicyService leaves the answer unknown ('Checking')")
			T.eq(Gems.PolicyState(absent), "Checking", tag .. "(precondition) without a PolicyService API the answer stays unknown ('Checking')")
			-- (the account without an answer goes first, while the API is still absent: a refused spin asks PolicyService
			-- again, so the API comes back only after its case)
			local cases = { { absent, "no PolicyService answer yet", CHECKING }, { restricted, "restricted", TOKEN_LOCK }, { failing, "PolicyService failing", CHECKING } }
			for _, case in ipairs(cases) do
				local p, name, lockText = case[1], case[2], case[3]
				local t0, g0 = DS().GetTokens(p), DS().GetGems(p)
				local lock = Gems.TokenSpinLock(p)
				local ok1, why1 = PS.BuyRoulette(p, cloud.Id)
				if on then
					T.check(lock == lockText, tag .. name .. ": GemService.TokenSpinLock answers '" .. lockText .. "' (16.12, unchanged)", tostring(lock))
					T.check(ok1 == false and why1 == lockText and DS().GetTokens(p) == t0, tag .. name .. ": a token spin is refused with that text, nothing charged", tostring(ok1) .. " / " .. tostring(why1))
				else
					T.check(lock == nil, tag .. name .. ": GemService.TokenSpinLock answers nil (no lock while nothing sells Tokens)", tostring(lock))
					T.check(ok1 == true and DS().GetTokens(p) == t0 - cloud.Price, tag .. name .. ": a token spin goes through and charges " .. cloud.Price .. " Tokens, as on main",
						tostring(ok1) .. " / " .. tostring(why1) .. ", tokens " .. tostring(t0) .. " -> " .. tostring(DS().GetTokens(p)))
					local t1 = DS().GetTokens(p)
					local ok3, why3 = PS.BuyRoulette(p, cloud.Id, "Tokens", 3)
					T.check(ok3 == true and DS().GetTokens(p) == t1 - 3 * cloud.Price, tag .. name .. ": x3 with Tokens goes through too", tostring(ok3) .. " / " .. tostring(why3))
					K.advance(0.4)
					local t2 = DS().GetTokens(p)
					local mark = K.logSize()
					Mock.FromClient(remote, p, cloud.Id, "Tokens", 1)
					K.advance(0.3)
					local ans = K.lastRemote("RouletteResult", p.UserId, mark)
					local a1 = ans and ans.args[1]
					T.check(type(a1) == "table" and a1.Ok == true and DS().GetTokens(p) == t2 - cloud.Price, tag .. name .. ": the BuyRoulette remote answers Ok = true and charges once",
						"Ok " .. tostring(type(a1) == "table" and a1.Ok) .. ", reason " .. tostring(type(a1) == "table" and a1.Reason))
				end
				T.eq(DS().GetGems(p), g0, tag .. name .. ": no Gems are touched by a token spin")
				if p == absent then
					T.eq(Gems.PolicyState(absent), "Checking", tag .. name .. ": (the answer was unknown through the whole case)")
					install()
				end
			end
			-- an account PolicyService allows spins in both states
			local ta = DS().GetTokens(allowed)
			local okA, whyA = PS.BuyRoulette(allowed, cloud.Id)
			T.check(okA == true and DS().GetTokens(allowed) == ta - cloud.Price, tag .. "an allowed account spins with Tokens", tostring(okA) .. " / " .. tostring(whyA))
			-- main's own lock (gem-priced spins) does not follow the switch
			local tr, gr = DS().GetTokens(restricted), DS().GetGems(restricted)
			local okG, whyG = PS.BuyRoulette(restricted, cloud.Id, "Gems")
			T.check(okG == false and whyG == "Gem roulettes are not available on your account" and DS().GetGems(restricted) == gr and DS().GetTokens(restricted) == tr,
				tag .. "a restricted account's GEM spin is still refused (main's lock, in both states), nothing charged", tostring(okG) .. " / " .. tostring(whyG))
			if not on then
				-- PetService never asks for the lock while the Store is off: a GemService that cannot answer changes nothing
				Gems.TokenSpinLock = function()
					error("smoke: TokenSpinLock must not be asked while the Store is off")
				end
				local tb = DS().GetTokens(restricted)
				local okB, whyB = PS.BuyRoulette(restricted, cloud.Id)
				T.check(okB == true and DS().GetTokens(restricted) == tb - cloud.Price, tag .. "PetService does not ask GemService for the token lock at all", tostring(okB) .. " / " .. tostring(whyB))
			end
		end)
		Gems.TokenSpinLock = saved.Lock
		Config.Store.Enabled = saved.Enabled
		PolS.GetPolicyInfoForPlayerAsync = nil
		leaveAll(players)
		T.check(okRun, tag .. "the scenario ran to its end", tostring(errRun))
	end

	S.store_switch_spins_off = guarded("store_switch_spins_off", function()
		if K.needBoot() then
			runSpins(false)
		end
	end)
	S.store_switch_spins_on = guarded("store_switch_spins_on", function()
		if K.needBoot() then
			runSpins(true)
		end
	end)

	S.store_switch_off = guarded("store_switch_off", function()
		if K.needBoot() then
			run(false)
		end
	end)
	S.store_switch_on = guarded("store_switch_on", function()
		if K.needBoot() then
			run(true)
		end
	end)
	return S
end

----------------------------------------------------------------------------------------------------
-- client and phone worlds
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local MPS = game:GetService("MarketplaceService")
	local LocalPlayer = Players.LocalPlayer
	local H = {}
	local STORE_IDS = { Starter = 8101, Pro = 8102, VIP = 8201, Cash2x = 8202, PetXp2x = 8203, XpPotion1 = 8103, XpPotion3 = 8104, Tokens1 = 8105, Tokens2 = 8106, Tokens3 = 8107 }
	local ATTRS = { "InMatch", "OwnedPasses", "StoreBought", "XpBoostEnds", "StorePreview", "PaidRandomItemsRestricted", "GemsSettled", "XpPassState", "CloudTokens", "Gems" }
	-- matched without case (combined release, kit-b's restyle): kit-b writes the rail's caption "ROBUX ITEMS" and a card's
	-- Buy "Preview" (sentence case), which a case-sensitive "Robux" / "PREVIEW" read past; the Store items' own names too
	local BAD_TEXTS = { "preview", "coming soon", "opens soon", "robux", "xp potion", "cloud tokens", "starter pack", "pro pack",
		"x2 cash", "x2 pet xp", "token pack" }

	function H.moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end
	function H.ctrl(name)
		return H.moduleAt("client", "Controllers/" .. name)
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.shownIn(obj)
		local node = obj
		while node and not node:IsA("ScreenGui") do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return node ~= nil and node.Enabled ~= false
	end
	function H.win()
		local gui = H.pg():FindFirstChild("NimbusShop")
		return gui and gui:FindFirstChild("ShopWindow", true)
	end
	function H.find(name)
		local win = H.win()
		return win and win:FindFirstChild(name, true)
	end
	function H.shown(name)
		local obj = H.find(name)
		return obj ~= nil and H.shownIn(obj)
	end
	-- the names of the rail tabs shown, top to bottom / left to right
	function H.tabs()
		local list = {}
		local win = H.win()
		for _, d in ipairs(win and win:GetDescendants() or {}) do
			if d:IsA("TextButton") and d.Name:sub(1, 4) == "Tab_" and H.shownIn(d) then
				list[#list + 1] = d
			end
		end
		table.sort(list, function(a, b)
			local pa, pb = a.AbsolutePosition, b.AbsolutePosition
			if math.abs(pa.Y - pb.Y) > 1 then
				return pa.Y < pb.Y
			end
			return pa.X < pb.X
		end)
		local names = {}
		for i, d in ipairs(list) do
			names[i] = d.Name:sub(5)
		end
		return table.concat(names, ","), list
	end
	function H.cardCount()
		local n = 0
		local win = H.win()
		for _, d in ipairs(win and win:GetDescendants() or {}) do
			if d:IsA("GuiObject") and d.Name:sub(1, 5) == "Card_" then
				n = n + 1
			end
		end
		return n
	end
	-- the shown texts of the Shop window (or of `root`: the whole PlayerGui) that a Store-off player must never read
	function H.badTexts(root)
		local out = {}
		local win = root or H.win()
		for _, d in ipairs(win and win:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and H.shownIn(d) then
				local text = tostring(d.Text)
				local low = string.lower(text)
				for _, bad in ipairs(BAD_TEXTS) do
					if string.find(low, bad, 1, true) then
						out[#out + 1] = d.Name .. " '" .. text .. "'"
						break
					end
				end
			end
		end
		return out
	end
	function H.calls(name, mark, a1, a2)
		local n = 0
		for _, e in ipairs(KC.serverCalls(name, mark)) do
			if (a1 == nil or e.args[1] == a1) and (a2 == nil or e.args[2] == a2) then
				n = n + 1
			end
		end
		return n
	end
	function H.inside(obj, host)
		local p, s, hp, hs = obj.AbsolutePosition, obj.AbsoluteSize, host.AbsolutePosition, host.AbsoluteSize
		local finite = T.finite(p.X) and T.finite(p.Y) and T.finite(s.X) and T.finite(s.Y)
		return finite and s.X > 0 and s.Y > 0 and p.X >= hp.X - 1 and p.Y >= hp.Y - 1 and p.X + s.X <= hp.X + hs.X + 1 and p.Y + s.Y <= hp.Y + hs.Y + 1
	end
	-- two boxes that do not overlap (touching edges allowed)
	function H.apart(a, b)
		local pa, sa, pb, sb = a.AbsolutePosition, a.AbsoluteSize, b.AbsolutePosition, b.AbsoluteSize
		return pa.X + sa.X <= pb.X + 1 or pb.X + sb.X <= pa.X + 1 or pa.Y + sa.Y <= pb.Y + 1 or pb.Y + sb.Y <= pa.Y + 1
	end
	-- (combined release) the Store-off rule at one window size, the shipped ids (every Id 0) and a Studio dev's preview
	-- flag: one rail tab (Eggs), none of the Store's parts kit-b restyled (the "ROBUX ITEMS" rule, the Starter's red
	-- square, the "opens soon" line, a card), no Store text in the window or anywhere in the PlayerGui, the Fast toggle in
	-- the rail clear of the tab. Then the same size ON: the five tabs, so the off rail is the switch's only change.
	function H.offAt(w, h, expectLayout)
		local Shop = H.ctrl("ShopController")
		local Config = KC.env()
		local tag = fmt("store switch ui: (off, %dx%d) ", w, h)
		Mock.SetViewport(w, h)
		KC.advance(0.5)
		Config.Store.Enabled = false
		LocalPlayer:SetAttribute("StorePreview", true)
		H.setIds(false, false)
		Shop._S.Tab = nil
		T.check(H.reopen() == true and H.win().Visible == true, tag .. "the Shop opens")
		if expectLayout then
			T.eq(Shop.Layout(), expectLayout, tag .. "(precondition) the " .. expectLayout .. " layout")
		end
		local names, list = H.tabs()
		T.eq(names, "Eggs", tag .. "one rail tab, Eggs (layout " .. tostring(Shop.Layout()) .. ")")
		T.check(list[1] ~= nil and H.inside(list[1], H.win()), tag .. "the Eggs tab sits inside the window")
		local div = H.find("RobuxDivider")
		local divShown = div ~= nil and H.shownIn(div)
		for _, part in ipairs({ "Label", "RuleL", "RuleR", "Line", "Glyph" }) do
			local child = div and div:FindFirstChild(part)
			divShown = divShown or (child ~= nil and H.shownIn(child))
		end
		T.check(div ~= nil and not divShown, tag .. "no 'ROBUX ITEMS' rule (kit-b's captioned divider: its label and dotted rules)")
		T.check(not H.shown("Soon") and not H.shown("Dot") and H.cardCount() == 0, tag .. "no 'opens soon', no Starter square, no card")
		local bad = H.badTexts()
		T.check(#bad == 0, tag .. "no Store text in the Shop window", table.concat(bad, " | "))
		bad = H.badTexts(H.pg())
		T.check(#bad == 0, tag .. "no Store text anywhere in the PlayerGui", table.concat(bad, " | "))
		if Shop.Layout() ~= "Phone" and Shop.Layout() ~= "Portrait" then
			local fast, rail = H.find("FastHatch"), H.find("Rail")
			T.check(fast ~= nil and rail ~= nil and list[1] ~= nil and H.shown("FastHatch") and H.inside(fast, rail) and H.apart(fast, list[1]),
				tag .. "the Fast hatch toggle sits in the rail, clear of the Eggs tab")
		end
		Config.Store.Enabled = true
		Shop._S.Tab = nil
		H.reopen()
		T.eq((H.tabs()), "Eggs,Gems,Packs,Passes,Boosts", fmt("store switch ui: (on, %dx%d) ", w, h) .. "the five tabs (only the switch hides them)")
		Config.Store.Enabled = false
	end
	function H.setIds(store, gems)
		local Config = KC.env()
		for _, it in ipairs(Config.Store.Items) do
			it.Id = store and (STORE_IDS[it.Key] or 0) or 0
		end
		for i, p in ipairs(Config.Gems.Products) do
			-- (8390 + i: ids no other client list uses. ShopController asks each id's price once per SESSION, and the
			-- shop lists that run before this one in a whole run create gem packs 8301..8304: with those ids the "prices
			-- are asked for the gem packs" check below found nothing left to ask and failed in any run that had them first.)
			p.Id = (type(gems) == "table" and gems[i]) or (gems == true and (8390 + i)) or 0
		end
	end
	function H.begin()
		local Config = KC.env()
		local saved = { Ids = {}, Gems = {}, Attrs = {}, Enabled = Config.Store.Enabled, Viewport = { Mock.Viewport.X, Mock.Viewport.Y }, Info = {} }
		for _, it in ipairs(Config.Store.Items) do
			saved.Ids[it.Key] = it.Id
		end
		for i, p in ipairs(Config.Gems.Products) do
			saved.Gems[i] = p.Id
		end
		for _, name in ipairs(ATTRS) do
			saved.Attrs[name] = LocalPlayer:GetAttribute(name)
		end
		LocalPlayer:SetAttribute("InMatch", false)
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
		LocalPlayer:SetAttribute("OwnedPasses", "")
		LocalPlayer:SetAttribute("StoreBought", "")
		LocalPlayer:SetAttribute("XpBoostEnds", 0)
		LocalPlayer:SetAttribute("GemsSettled", true)
		LocalPlayer:SetAttribute("XpPassState", "NotOwned")
		-- a Studio dev: the preview flag is ON, and the off switch must still hide everything
		LocalPlayer:SetAttribute("StorePreview", true)
		MPS.GetProductInfo = function(_, id)
			saved.Info[#saved.Info + 1] = id
			return { PriceInRobux = 49 }
		end
		H.setIds(false, false)
		local Shop, MC = H.ctrl("ShopController"), H.ctrl("MenuController")
		if Shop then
			Shop.Close()
			if type(Shop._S) == "table" then
				Shop._S.Tab = nil
			end
		end
		if MC then
			MC.Close()
		end
		KC.advance(0.6)
		return saved
	end
	function H.finish(saved)
		local Config = KC.env()
		local Shop, MC = H.ctrl("ShopController"), H.ctrl("MenuController")
		if Shop then
			Shop.Close()
			if type(Shop._S) == "table" then
				Shop._S.Tab = nil
			end
		end
		if MC then
			MC.Close()
		end
		Config.Store.Enabled = saved.Enabled
		for _, it in ipairs(Config.Store.Items) do
			it.Id = saved.Ids[it.Key] or 0
		end
		for i, p in ipairs(Config.Gems.Products) do
			p.Id = saved.Gems[i] or 0
		end
		for _, name in ipairs(ATTRS) do
			LocalPlayer:SetAttribute(name, saved.Attrs[name])
		end
		MPS.GetProductInfo = nil
		Mock.SetViewport(saved.Viewport[1], saved.Viewport[2])
		KC.advance(0.6)
	end
	-- (re)opens the Shop from closed, so the shown set is read fresh
	function H.reopen(args)
		local Shop = H.ctrl("ShopController")
		Shop.Close()
		KC.advance(0.3)
		local ok = Shop.Open(args)
		KC.advance(0.6)
		return ok
	end

	S.client_store_switch = guarded("client_store_switch", function()
		local Shop, MC = H.ctrl("ShopController"), H.ctrl("MenuController")
		local Catalog = H.moduleAt("shared", "StoreCatalog")
		if not T.check(type(Shop) == "table" and type(Shop.Open) == "function" and type(MC) == "table" and type(Catalog) == "table", "store switch ui: ShopController, MenuController and StoreCatalog load") then
			return
		end
		local Config = KC.env()
		local saved = H.begin()
		local okRun, errRun = pcall(function()
			Mock.SetViewport(1920, 1080)
			KC.advance(0.5)

			-- ON first: where the first two tabs sit (the slots the off rail must reuse)
			Config.Store.Enabled = true
			LocalPlayer:SetAttribute("StorePreview", nil)
			T.check(H.reopen() == true and H.win() ~= nil and H.win().Visible == true, "store switch ui: (on) the Shop opens")
			local names, list = H.tabs()
			T.eq(names, "Eggs,Gems,Packs,Passes,Boosts", "store switch ui: (on) the five rail tabs, as before this gate")
			local slot1 = list[1] and list[1].AbsolutePosition
			local slot2 = list[2] and list[2].AbsolutePosition
			T.check(H.shown("RobuxDivider"), "store switch ui: (on) the 'Robux items' divider shows")
			Shop.Open({ Tab = "Packs" })
			KC.advance(0.4)
			T.check(Shop.Tab() == "Packs" and H.shown("Soon"), "store switch ui: (on) Packs with every Id 0 reads 'The Shop opens soon!', as before")
			Shop.Open({ Tab = "Gems" })
			KC.advance(0.4)
			T.check(Shop.Tab() == "Gems" and H.shown("GemPotion") and H.shown("TokenPack_1") and H.shown("GemPack_1"), "store switch ui: (on) the Gems page shows its packs, the potion and the token packs, as before")

			-- OFF, every Id 0 (today's Config), a Studio dev with the preview flag
			Config.Store.Enabled = false
			LocalPlayer:SetAttribute("StorePreview", true)
			Shop._S.Tab = nil
			local infoMark, callMark = #saved.Info, #Mock.RemoteLog
			T.check(H.reopen() == true and H.win().Visible == true, "store switch ui: (off) the Shop still opens (the Eggs are not the Store)")
			names, list = H.tabs()
			T.eq(names, "Eggs", "store switch ui: (off) ONE rail tab, Eggs: no Gems / Packs / Passes / Boosts tab")
			T.check(list[1] ~= nil and slot1 ~= nil and math.abs(list[1].AbsolutePosition.Y - slot1.Y) < 1 and math.abs(list[1].AbsolutePosition.X - slot1.X) < 1, "store switch ui: (off) Eggs keeps the first slot")
			T.check(Shop.Tab() == "Eggs" and H.shown("Page_Eggs"), "store switch ui: (off) the Eggs page shows")
			T.check(not H.shown("RobuxDivider"), "store switch ui: (off) no 'Robux items' divider")
			T.check(not H.shown("Soon"), "store switch ui: (off) no 'The Shop opens soon!'")
			T.check(not H.shown("Dot"), "store switch ui: (off) no Starter dot")
			T.eq(H.cardCount(), 0, "store switch ui: (off) no Store card is built, preview flag or not")
			local bad = H.badTexts()
			T.check(#bad == 0, "store switch ui: (off) no PREVIEW / Coming soon / opens soon / Robux / potion / token-pack text is shown", table.concat(bad, " | "))
			T.check(H.shown("FastHatch") and H.inside(H.find("FastHatch"), H.find("Rail")), "store switch ui: (off) the Fast hatch toggle still sits in the rail")
			local n = 0
			for _ in pairs(Shop.Cards()) do
				n = n + 1
			end
			T.eq(n, 0, "store switch ui: (off) ShopController.Cards() is empty")
			for _, tab in ipairs({ "Gems", "Currency", "Tokens", "Packs", "Passes", "Boosts" }) do
				Shop.Open({ Tab = tab })
				KC.advance(0.3)
				T.check(Shop.Tab() == "Eggs" and H.shown("Page_Eggs") and not H.shown("Page_Gems") and not H.shown("Soon"), "store switch ui: (off) Open({ Tab = '" .. tab .. "' }) lands on Eggs", tostring(Shop.Tab()))
			end
			MC.Open("Store", { Tab = "Currency" })
			KC.advance(0.4)
			T.check(Shop.IsOpen() and Shop.Tab() == "Eggs", "store switch ui: (off) OpenPanel('Store', { Tab = 'Currency' }) lands on Eggs")
			KC.advance(12) -- past Config.Store.PriceRetrySeconds: no late price lookup either
			T.eq(#saved.Info - infoMark, 0, "store switch ui: (off) no GetProductInfo lookup")
			T.eq(#KC.serverCalls("StoreRequest", callMark), 0, "store switch ui: (off) no StoreRequest is sent")

			-- OFF, every Store item AND every gem pack created: only what main sells (the gem packs) shows
			H.setIds(true, true)
			Shop._S.Tab = nil
			infoMark = #saved.Info
			T.check(H.reopen() == true, "store switch ui: (off, created) the Shop opens")
			names, list = H.tabs()
			T.eq(names, "Eggs,Gems", "store switch ui: (off, created) Eggs and Gems only (the gem packs are main's)")
			T.check(list[2] ~= nil and slot2 ~= nil and math.abs(list[2].AbsolutePosition.Y - slot2.Y) < 1, "store switch ui: (off, created) Gems sits in the second slot: no gap in the rail")
			T.check(not H.shown("RobuxDivider"), "store switch ui: (off, created) still no divider")
			T.eq(H.cardCount(), 0, "store switch ui: (off, created) still no Store card")
			Shop.Open({ Tab = "Passes" })
			KC.advance(0.3)
			T.eq(Shop.Tab(), "Eggs", "store switch ui: (off, created) a hidden tab still lands on Eggs")
			Shop.Open({ Tab = "Gems" })
			KC.advance(0.6)
			T.check(Shop.Tab() == "Gems" and H.shown("Page_Gems"), "store switch ui: (off, created) the Gems tab opens")
			local allPacks = true
			for i = 1, #Config.Gems.Products do
				allPacks = allPacks and H.shown("GemPack_" .. i)
			end
			T.check(allPacks and H.shown("GemHero"), "store switch ui: (off, created) the gem packs and their hero show")
			T.check(not H.shown("GemPotion") and not H.shown("TokensTitle") and not H.shown("TokenPack_1") and not H.shown("TokenPack_2") and not H.shown("TokenPack_3"),
				"store switch ui: (off, created) no gem potion, no 'Cloud Tokens' title, no token pack")
			bad = H.badTexts()
			T.check(#bad == 0, "store switch ui: (off, created) no PREVIEW / Coming soon / potion / token-pack text", table.concat(bad, " | "))
			local scroll = H.find("Page_Gems"):FindFirstChild("Scroll")
			local lowest = 0
			for _, d in ipairs(scroll:GetChildren()) do
				if d:IsA("GuiObject") and d.Visible then
					lowest = math.max(lowest, d.Position.Y.Offset + d.Size.Y.Offset)
				end
			end
			T.check(scroll.CanvasSize.Y.Offset <= lowest + 32, "store switch ui: (off, created) the Gems page ends under its last pack (no empty scroll where the potion and the tokens were)",
				fmt("canvas %d, lowest %d", scroll.CanvasSize.Y.Offset, lowest))
			KC.advance(1.2)
			callMark = #Mock.RemoteLog
			Mock.Click(H.find("GemPack_1"):FindFirstChild("Buy", true))
			KC.advance(0.3)
			T.eq(H.calls("StoreRequest", callMark, "Buy", "Gems1"), 1, "store switch ui: (off, created) a gem pack's Buy sends StoreRequest('Buy', 'Gems1')")
			KC.advance(12)
			local wrong = {}
			for i = infoMark + 1, #saved.Info do
				if saved.Info[i] < 8300 then
					wrong[#wrong + 1] = tostring(saved.Info[i])
				end
			end
			T.check(#saved.Info > infoMark and #wrong == 0, "store switch ui: (off, created) prices are asked for the gem packs only", table.concat(wrong, ","))
			for key in pairs(Shop.Cards()) do
				T.check(key:sub(1, 4) == "Gems", "store switch ui: (off, created) Cards() lists gem packs only", key)
			end

			-- OFF, one gem pack created: it takes the first place, the uncreated ones are not shown as dead buttons
			H.setIds(true, { 0, 8302, 0, 0 })
			H.reopen({ Tab = "Gems" })
			T.check(H.shown("GemPack_2") and not H.shown("GemPack_1") and not H.shown("GemPack_3") and not H.shown("GemPack_4") and not H.shown("GemHero"),
				"store switch ui: (off, one pack) only the created pack shows (no hero for an uncreated Chest, no dead 'Coming soon' button)")
			T.check(H.find("GemPack_2").Position.X.Offset < 1, "store switch ui: (off, one pack) ...in the first place", tostring(H.find("GemPack_2").Position.X.Offset))

			-- (combined release) kit-b's window sizes: 1920x1080, the short rail of the owner's ~1024x600 (kit-b's Short tab
			-- metrics under the Fast toggle), 1280x720 and 1366x768 (the look reviews' PC sizes)
			for _, vp in ipairs({ { 1920, 1080 }, { 1024, 600 }, { 1280, 720 }, { 1366, 768 } }) do
				H.offAt(vp[1], vp[2])
			end
			Mock.SetViewport(1920, 1080)
			KC.advance(0.5)

			-- ON again, created: everything is back
			Config.Store.Enabled = true
			H.setIds(true, true)
			Shop._S.Tab = nil
			H.reopen({ Tab = "Gems" })
			names = H.tabs()
			T.eq(names, "Eggs,Gems,Packs,Passes,Boosts", "store switch ui: (on again) the five tabs are back")
			T.check(H.shown("GemPotion") and H.shown("TokenPack_1") and H.shown("TokensTitle") and H.shown("RobuxDivider"), "store switch ui: (on again) the potion, the token packs and the divider are back")
			Shop.Open({ Tab = "Packs" })
			KC.advance(0.5)
			T.check(Shop.Tab() == "Packs" and H.cardCount() > 0, "store switch ui: (on again) the Packs tab shows its cards")

			-- release step 1 follow-up (the owner's pick, 2026-11-23): the policy lock on TOKEN spins (lobby-shop 16.12) is the
			-- Store's. Off: a restricted account and one with no answer yet see live token Spin / x3 buttons and the request
			-- is sent, exactly as on main; the gem buttons and the Secret card keep main's own lock. On: 16.12, unchanged.
			local SE, ES = H.moduleAt("client", "UI/ShopEggs"), H.moduleAt("client", "UI/EggStage")
			if T.check(type(SE) == "table" and type(SE.CardState) == "function" and type(ES) == "table" and type(ES.Request) == "function", "store switch ui: ShopEggs.CardState and EggStage.Request exist") then
				LocalPlayer:SetAttribute(Config.Attr.Tokens, 50000)
				LocalPlayer:SetAttribute(Config.Attr.Gems, 50000)
				local function tokenBtn(name)
					local card = H.find("ShopCard_Cloud")
					return card and card:FindFirstChild(name, true)
				end
				local function btnOff(b)
					return b == nil or b:GetAttribute("Disabled") == true or b.Active == false
				end
				local function btnTexts(b)
					local out = {}
					for _, d in ipairs(b and b:GetDescendants() or {}) do
						if (d:IsA("TextLabel") or d:IsA("TextButton")) and H.shownIn(d) and tostring(d.Text) ~= "" then
							out[#out + 1] = tostring(d.Text)
						end
					end
					return table.concat(out, " | ")
				end
				for _, case in ipairs({ { true, "restricted" }, { nil, "unknown" } }) do
					local tag = "store switch ui: token spins, policy " .. case[2] .. ": "
					LocalPlayer:SetAttribute("PaidRandomItemsRestricted", case[1])
					Config.Store.Enabled = false
					Shop._S.Tab = nil
					H.reopen()
					T.check(SE.CardState("Cloud", "Spin") == "Ready" and SE.CardState("Cloud", "Spin3") == "Ready", tag .. "(off) CardState of the token Spin and x3 is Ready, as on main",
						tostring(SE.CardState("Cloud", "Spin")) .. " / " .. tostring(SE.CardState("Cloud", "Spin3")))
					for _, name in ipairs({ "Spin", "Spin3" }) do
						local b = tokenBtn(name)
						T.check(b ~= nil and not btnOff(b) and string.find(btnTexts(b), "Locked", 1, true) == nil, tag .. "(off) the Cloud card's " .. name .. " button is live, no 'Locked'", btnTexts(b))
					end
					T.check(SE.CardState("Cloud", "SpinGems") == "Locked" and SE.CardState("Secret") == "Locked", tag .. "(off) the gem button and the Secret card keep main's lock",
						tostring(SE.CardState("Cloud", "SpinGems")) .. " / " .. tostring(SE.CardState("Secret")))
					KC.advance(0.5)
					local mark = #Mock.RemoteLog
					local sentGem = ES.Request("Cloud", "Gems", 1)
					T.check(sentGem == false and H.calls("BuyRoulette", mark) == 0, tag .. "(off) a gem spin request is still refused on the client, nothing sent")
					local sent = ES.Request("Cloud", "Tokens", 1)
					T.check(sent == true and H.calls("BuyRoulette", mark, "Cloud", "Tokens") == 1, tag .. "(off) EggStage.Request(Cloud, Tokens) sends BuyRoulette", tostring(sent))
					ES._Answer({ Ok = false, Reason = "smoke probe", RouletteId = "Cloud", Currency = "Tokens", Spins = 1 })
					KC.advance(0.6)

					Config.Store.Enabled = true
					Shop._S.Tab = nil
					H.reopen()
					T.check(SE.CardState("Cloud", "Spin") == "Locked" and SE.CardState("Cloud", "Spin3") == "Locked", tag .. "(on) CardState of the token Spin and x3 is Locked (16.12, unchanged)",
						tostring(SE.CardState("Cloud", "Spin")) .. " / " .. tostring(SE.CardState("Cloud", "Spin3")))
					T.check(btnOff(tokenBtn("Spin")) and string.find(btnTexts(tokenBtn("Spin")), "Locked", 1, true) ~= nil, tag .. "(on) the Cloud card's Spin button reads 'Locked', inactive", btnTexts(tokenBtn("Spin")))
					mark = #Mock.RemoteLog
					local sentOn = ES.Request("Cloud", "Tokens", 1)
					T.check(sentOn == false and H.calls("BuyRoulette", mark) == 0, tag .. "(on) EggStage.Request(Cloud, Tokens) sends nothing (16.12, unchanged)", tostring(sentOn))
					KC.advance(0.5)
				end
			end
		end)
		H.finish(saved)
		T.check(okRun, "store switch ui: the scenario ran to its end", tostring(errRun))
		KC.flushErrors("client store switch")
	end)

	S.client_store_switch_mobile = guarded("client_store_switch_mobile", function()
		local Shop = H.ctrl("ShopController")
		if not T.check(type(Shop) == "table" and type(Shop.Open) == "function", "store switch phone: ShopController loads") then
			return
		end
		local Config = KC.env()
		local saved = H.begin()
		local okRun, errRun = pcall(function()
			Config.Store.Enabled = false
			for _, view in ipairs({ { 390, 844, "Portrait" }, { 844, 390, "Phone" } }) do
				local tag = fmt("store switch phone %dx%d: ", view[1], view[2])
				-- (combined release) kit-b's phone rail: the one tab, no "ROBUX ITEMS" rule, no Starter square on the tab's
				-- corner, no Store text anywhere in the PlayerGui
				H.offAt(view[1], view[2], view[3])
				Config.Store.Enabled = false
				Mock.SetViewport(view[1], view[2])
				KC.advance(0.5)
				H.setIds(false, false)
				Shop._S.Tab = nil
				T.check(H.reopen() == true and H.win().Visible == true, tag .. "(off) the Shop opens")
				T.eq(Shop.Layout(), view[3], tag .. "(precondition) the " .. view[3] .. " layout")
				local names, list = H.tabs()
				T.eq(names, "Eggs", tag .. "(off) one tab, Eggs")
				T.check(list[1] ~= nil and H.inside(list[1], H.win()), tag .. "(off) the tab sits inside the window (finite, on screen)")
				T.check(not H.shown("RobuxDivider") and not H.shown("Soon") and H.cardCount() == 0, tag .. "(off) no divider, no 'opens soon', no card")
				local bad = H.badTexts()
				T.check(#bad == 0, tag .. "(off) no Store text", table.concat(bad, " | "))
				Shop.Open({ Tab = "Boosts" })
				KC.advance(0.3)
				T.eq(Shop.Tab(), "Eggs", tag .. "(off) a hidden tab lands on Eggs")

				H.setIds(true, true)
				Shop._S.Tab = nil
				H.reopen({ Tab = "Gems" })
				names, list = H.tabs()
				T.eq(names, "Eggs,Gems", tag .. "(off, created) Eggs and Gems")
				local okTabs = #list == 2
				for _, b in ipairs(list) do
					okTabs = okTabs and H.inside(b, H.win())
				end
				if okTabs then
					local a, b = list[1], list[2]
					local apart = (a.AbsolutePosition.X + a.AbsoluteSize.X <= b.AbsolutePosition.X + 1) or (a.AbsolutePosition.Y + a.AbsoluteSize.Y <= b.AbsolutePosition.Y + 1)
					okTabs = apart
				end
				T.check(okTabs, tag .. "(off, created) both tabs inside the window, not overlapping")
				T.check(Shop.Tab() == "Gems" and H.shown("GemPack_1") and H.shown("GemPack_4") and not H.shown("GemPotion") and not H.shown("TokenPack_1") and not H.shown("TokensTitle"),
					tag .. "(off, created) the Gems page holds the gem packs only")
				local scroll = H.find("Page_Gems"):FindFirstChild("Scroll")
				local far = 0
				for _, d in ipairs(scroll:GetChildren()) do
					if d:IsA("GuiObject") and d.Visible then
						if view[3] == "Phone" then
							far = math.max(far, d.Position.X.Offset + d.Size.X.Offset)
						else
							far = math.max(far, d.Position.Y.Offset + d.Size.Y.Offset)
						end
					end
				end
				local canvas = view[3] == "Phone" and scroll.CanvasSize.X.Offset or scroll.CanvasSize.Y.Offset
				T.check(canvas <= far + 32, tag .. "(off, created) the Gems page ends at its last pack", fmt("canvas %d, last %d", canvas, far))
			end
		end)
		H.finish(saved)
		T.check(okRun, "store switch phone: the scenario ran to its end", tostring(errRun))
		KC.flushErrors("client store switch mobile")
	end)
	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
