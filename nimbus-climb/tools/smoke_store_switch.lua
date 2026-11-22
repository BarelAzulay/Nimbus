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
--                         an owned pass is Owned (UserOwnsGamePassAsync and PromptGamePassPurchaseFinished).
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
		MPS.UserOwnsGamePassAsync = function(_, uid, id)
			return owners[uid] == id
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
			Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p, IDS.PetXp2x, true)
			K.advance(0.3)
			T.check(Store.Owns(p, "PetXp2x") == true, tag .. "a finished pass purchase is Owned at once")
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
	local ATTRS = { "InMatch", "OwnedPasses", "StoreBought", "XpBoostEnds", "StorePreview", "PaidRandomItemsRestricted", "GemsSettled", "XpPassState" }
	local BAD_TEXTS = { "PREVIEW", "Coming soon", "opens soon", "Robux", "XP Potion", "Cloud Tokens" }

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
	-- the shown texts of the Shop window that a Store-off player must never read
	function H.badTexts()
		local out = {}
		local win = H.win()
		for _, d in ipairs(win and win:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and H.shownIn(d) then
				local text = tostring(d.Text)
				for _, bad in ipairs(BAD_TEXTS) do
					if string.find(text, bad, 1, true) then
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
	function H.setIds(store, gems)
		local Config = KC.env()
		for _, it in ipairs(Config.Store.Items) do
			it.Id = store and (STORE_IDS[it.Key] or 0) or 0
		end
		for i, p in ipairs(Config.Gems.Products) do
			p.Id = (type(gems) == "table" and gems[i]) or (gems == true and (8300 + i)) or 0
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
