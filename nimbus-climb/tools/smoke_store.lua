-- smoke_store.lua: the Robux Store build (docs/superpowers/specs/2026-11-04-shop-retention-design.md; plan
-- docs/superpowers/plans/2026-11-04-store.md, Tasks 1-4 by the W0 lead and Task 9 by W2-money), loaded by tools/smoke.py in
-- BOTH worlds (ARGS.context picks the half):
--   store_doubles        (server world, pure) the mock's engine doubles are PROPS: Enum.GroupMembershipStatus is a closed list,
--                        Player:IsInGroupAsync / GroupService:PromptJoinAsync / MarketplaceService's pass + product functions,
--                        GetProductInfo, ProcessReceipt and TextChatService.OnIncomingMessage take a per-test function and nil
--                        restores the default (the smoke_p2_gems removeDoubles shape)
--   store_config         (server world, pure) Config.Store (13 items, the four perks, the potion cap, the three disabled Cash
--                        packs with their Prestige line), Config.Daily (the streak and play numbers), Config.Trove (two asks),
--                        the five remotes, the four attributes, the lid tag, Theme.Category and the four audio keys
--   store_exclusive      (server world, pure) Week Wisp (Epic, Daily) and Crown Phoenix (Legendary, Store): ExclusiveTo /
--                        IsExclusive, in no pool, no roulette odds, no Index group, not an event pet, not rollable, TotalCount 35,
--                        both catalogs Validate, the form names, 2000 rolls of every roulette never give one
--   store_catalog        (server world, pure) shared/StoreCatalog: Validate on the shipped Config, List (the enabled items + the
--                        gem packs), Item, ProductById / PassById (a gem pack resolves as a product, a pass never as a product),
--                        GrantLines' literal lines, Validate's refusals
--   store_grantpet       (server world, booted) PetService.GrantPet: one copy at a level, discovered and auto-equipped as the
--                        first pet, no spin counted, more copies never lower the level, a full stack refused with nothing
--                        written, unknown pet / junk count refused, a provisional save refused
--   store_router         (server world, booted; W2-money) GemService's ProcessReceipt routed through StoreCatalog.ProductById
--                        and StoreService.ApplyGrant: Tokens, potions, the Starter pack, Once twice, substitutes for a full
--                        stack, a late receipt in a match granted, gem packs as before
--   store_passes         (server world, booted; W2-money) the pass cache: UserOwnsGamePassAsync once per pass per join, the
--                        retry ladder, PromptGamePassPurchaseFinished, attributes written never read, TrustLedgerAfter
--   store_mult           (server world, booted; W2-money) Multipliers at the five earning sites: x2 Cash at the scoop, the Ring
--                        and the Dungeon; x2 Pet XP by pass or potion (never x4), ProXp x1.5 in PvE only; the sites NOT
--                        multiplied pinned exactly
--   store_remote         (server world, booted; W2-money) StoreRequest: junk, the 1 req/s limit, in a match, hidden / owned /
--                        bought keys, one prompt per created key, the StorePreview attribute
--   client_store_bigrect (client world) NeonKit.BigRect answers PetsController's H.rect numbers (820x330 Phone on 844x390,
--                        1260x900 PC on 1920x1080) and the new glyph ids exist
-- White-box: the doubles are written straight onto the service / player (props, never methods). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

----------------------------------------------------------------------------------------------------
-- server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	-- the booted helpers (the smoke_fix_server.lua shape)
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
	local function PS()
		return requireAt("server/Services/PetService")
	end
	local userSeq = 0
	local function newUserId()
		userSeq = userSeq + 1
		return 983100 + userSeq
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

	S.store_doubles = guarded("store_doubles", function()
		local p = Mock.AddPlayer("Doubles", 983001)
		T.check(Enum.GroupMembershipStatus.Joined ~= nil and Enum.GroupMembershipStatus.JoinRequestPending ~= nil and Enum.GroupMembershipStatus.AlreadyMember ~= nil and Enum.GroupMembershipStatus.None ~= nil, "store doubles: Enum.GroupMembershipStatus has the four members")
		T.check(not pcall(function() return Enum.GroupMembershipStatus.Nope end), "store doubles: ...and is a closed list")
		T.eq(p:IsInGroupAsync(12345), false, "store doubles: Player:IsInGroupAsync answers false by default")
		T.eq(game:GetService("GroupService"):PromptJoinAsync(12345), Enum.GroupMembershipStatus.None, "store doubles: GroupService:PromptJoinAsync answers None by default")
		local MPS = game:GetService("MarketplaceService")
		T.eq(MPS:UserOwnsGamePassAsync(p.UserId, 777), false, "store doubles: UserOwnsGamePassAsync false by default")
		T.check(pcall(MPS.PromptGamePassPurchase, MPS, p, 777) and pcall(MPS.PromptProductPurchase, MPS, p, 777), "store doubles: the prompt functions exist and do nothing")
		local info = MPS:GetProductInfo(777, Enum.InfoType.Product)
		T.check(type(info) == "table" and info.PriceInRobux == 0, "store doubles: GetProductInfo answers a table with PriceInRobux 0")
		T.check(pcall(function() return MPS.PromptGamePassPurchaseFinished:Connect(function() end) end), "store doubles: PromptGamePassPurchaseFinished is an event")
		T.check(pcall(function() game:GetService("TextChatService").OnIncomingMessage = function() end end), "store doubles: TextChatService.OnIncomingMessage is assignable")
		game:GetService("TextChatService").OnIncomingMessage = nil
		-- every double is a prop: a per-test function replaces the default, nil restores it (the smoke_p2_gems removeDoubles shape)
		local calls = 0
		MPS.UserOwnsGamePassAsync = function(_, uid, id) calls = calls + 1; return id == 777 end
		T.check(MPS:UserOwnsGamePassAsync(p.UserId, 777) == true and calls == 1, "store doubles: a per-test double replaces UserOwnsGamePassAsync")
		MPS.UserOwnsGamePassAsync = nil
		T.check(MPS:UserOwnsGamePassAsync(p.UserId, 777) == false and calls == 1, "store doubles: ...and nil restores the default")
		p.IsInGroupAsync = function(_, gid) return gid == 777 end
		T.check(p:IsInGroupAsync(777) == true, "store doubles: Player.IsInGroupAsync takes a double"); p.IsInGroupAsync = nil
		T.eq(p:IsInGroupAsync(777), false, "store doubles: ...and nil restores false")
		local GroupS = game:GetService("GroupService")
		GroupS.PromptJoinAsync = function() return Enum.GroupMembershipStatus.JoinRequestPending end
		T.eq(GroupS:PromptJoinAsync(1), Enum.GroupMembershipStatus.JoinRequestPending, "store doubles: GroupService.PromptJoinAsync takes a double"); GroupS.PromptJoinAsync = nil
		T.eq(GroupS:PromptJoinAsync(1), Enum.GroupMembershipStatus.None, "store doubles: ...and nil restores None")
		-- the same assign-then-nil pair for the two prompts (a call counter each) and GetProductInfo
		local prompts = 0
		MPS.PromptProductPurchase = function() prompts = prompts + 1 end
		MPS:PromptProductPurchase(p, 777)
		T.check(prompts == 1, "store doubles: PromptProductPurchase takes a double"); MPS.PromptProductPurchase = nil
		T.check(pcall(MPS.PromptProductPurchase, MPS, p, 777) and prompts == 1, "store doubles: ...and nil restores the no-op")
		MPS.PromptGamePassPurchase = function() prompts = prompts + 1 end
		MPS:PromptGamePassPurchase(p, 777)
		T.check(prompts == 2, "store doubles: PromptGamePassPurchase takes a double"); MPS.PromptGamePassPurchase = nil
		T.check(pcall(MPS.PromptGamePassPurchase, MPS, p, 777) and prompts == 2, "store doubles: ...and nil restores the no-op")
		MPS.GetProductInfo = function(_, id) return { Name = "Double " .. tostring(id), PriceInRobux = 99, ProductId = id } end
		T.eq(MPS:GetProductInfo(777, Enum.InfoType.Product).PriceInRobux, 99, "store doubles: GetProductInfo takes a double (PriceInRobux 99)"); MPS.GetProductInfo = nil
		T.eq(MPS:GetProductInfo(777, Enum.InfoType.Product).PriceInRobux, 0, "store doubles: ...and nil restores PriceInRobux 0")
		MPS.ProcessReceipt = function() return Enum.ProductPurchaseDecision.PurchaseGranted end
		T.check(type(MPS.ProcessReceipt) == "function", "store doubles: ProcessReceipt is assignable"); MPS.ProcessReceipt = nil
		T.eq(MPS.ProcessReceipt, nil, "store doubles: ...and nil again (GemService's boot writes it)")
		Mock.RemovePlayer(p)
	end)

	S.store_config = guarded("store_config", function()
		local Config, Theme = K.config(), K.M["shared/Theme"]
		T.check(type(Config.Store) == "table" and #Config.Store.Items == 13 and Config.Store.Potion.CapSeconds == 604800 and Config.Store.Potion.WarnSeconds == 300 and Config.Store.TrustLedgerAfter == 0 and Config.Store.PriceRetrySeconds == 10, "store config: Config.Store (13 items, Potion, TrustLedgerAfter 0, PriceRetrySeconds 10)")
		if type(Config.Store) ~= "table" then
			return
		end
		T.check(Config.Store.Perks.CashX2.Cash == 2 and Config.Store.Perks.XpX2.PetXp == 2 and Config.Store.Perks.ProXp.PetXpPvE == 1.5 and Config.Store.Perks.Vip.DailyMult == 2, "store config: the four perks")
		local byKey = {}
		for _, it in ipairs(Config.Store.Items) do byKey[it.Key] = it end
		T.check(byKey.Starter.Once == true and byKey.Starter.Hero == true and byKey.Starter.Grants.Pets.storm_tabby.Level == 5 and byKey.Starter.Grants.Cash == 1000 and byKey.Starter.Grants.Boost.XpPotion == 3600 and byKey.Starter.Robux == 99, "store config: Starter = Storm Tabby L5 + $1,000 + 1 h potion, Once, Hero, 99 R$")
		T.check(byKey.Pro.Grants.Pets.crown_phoenix.Level == 10 and byKey.Pro.Grants.Tokens == 5000 and byKey.Pro.Grants.Perks[1] == "ProXp" and byKey.Pro.Robux == 799, "store config: Pro = Crown Phoenix L10 + 5,000 Tokens + ProXp, 799 R$")
		T.check(byKey.VIP.Kind == "Pass" and byKey.VIP.Hero == true and byKey.Cash2x.Robux == 399 and byKey.PetXp2x.Robux == 450 and byKey.XpPotion3.Grants.Boost.XpPotion == 10800 and byKey.Tokens3.Grants.Tokens == 10000, "store config: passes and potions as the spec table")
		T.check(byKey.Cash1.Enabled == false and byKey.Cash2.Enabled == false and byKey.Cash3.Enabled == false and byKey.Cash3.Grants.Cash > byKey.Cash2.Grants.Cash and byKey.Cash2.Grants.Cash > byKey.Cash1.Grants.Cash and byKey.Cash1.Line ~= nil, "store config: the three Cash packs exist, Enabled = false, with their Prestige line (13b.1)")
		for _, it in ipairs(Config.Store.Items) do T.eq(it.Id, 0, "store config: " .. it.Key .. " ships with Id 0") end
		T.check(Config.Daily.ReadySeconds == 72000 and Config.Daily.KeepSeconds == 172800 and Config.Daily.PipDelaySeconds == 20 and Config.Daily.FutureClockSlack == 300 and #Config.Daily.Days == 7 and Config.Daily.Days[7].Pet == "week_wisp" and Config.Daily.Days[7].Else.Gems == 40 and Config.Daily.Days[1].Cash.Minutes == 2 and Config.Daily.Days[1].Cash.Min == 400, "store config: Config.Daily streak numbers")
		T.check(Config.Daily.Play.DaySeconds == 72000 and Config.Daily.Play.TickSeconds == 10 and Config.Daily.Play.ActiveWindow == 180 and Config.Daily.Play.MoveStuds == 2 and Config.Daily.Play.MaxDaySeconds == 36000 and #Config.Daily.Play.Tiers == 7 and Config.Daily.Play.Tiers[6].Berries == "Basket" and Config.Daily.Play.Tiers[7].Min == 180 and #Config.Daily.Play.ActiveRemotes == 7, "store config: Config.Daily.Play numbers")
		T.check(Config.Trove.GroupId == 0 and Config.Trove.PromptRange == 10 and Config.Trove.Slack == 6 and Config.Trove.Cooldown == 5 and #Config.Trove.Asks == 2 and Config.Trove.Asks[1].Reward.Cash == 2000 and Config.Trove.Asks[1].Reward.Tokens == 200 and Config.Trove.Asks[2].Id == "Like", "store config: Config.Trove (two asks, 13b.5)")
		for _, name in ipairs({ "StoreRequest", "DailyRequest", "DailyState", "TroveRequest", "TroveState" }) do T.check(table.find(Config.Remotes, name) ~= nil, "store config: remote " .. name .. " listed") end
		T.check(Config.Attr.OwnedPasses == "OwnedPasses" and Config.Attr.StoreBought == "StoreBought" and Config.Attr.XpBoostEnds == "XpBoostEnds" and Config.Attr.StorePreview == "StorePreview" and Config.Tags.TroveLid == "NC_TroveLid", "store config: the attributes and the lid tag")
		T.check(Theme.Category.Store == "Gold" and Theme.Category.Daily == "Gold" and Theme.Category.Trove == "Green", "store config: Theme.Category Store / Daily / Trove")
		for _, k in ipairs({ "StorePop", "StoreBuy", "TroveOpen", "DailyWeek" }) do T.check(Config.Audio.Keys.Sfx[k] == k and type(Config.Audio.Volume[k]) == "number", "store config: audio key " .. k) end
	end)

	S.store_exclusive = guarded("store_exclusive", function()
		local PC, BC, Config = K.M["shared/PetCatalog"], K.M["shared/BattleCatalog"], K.config()
		local wisp, crown = PC.Get("week_wisp"), PC.Get("crown_phoenix")
		T.check(wisp ~= nil and wisp.Rarity == "Epic" and wisp.ExclusiveTo == "Daily" and crown ~= nil and crown.Rarity == "Legendary" and crown.ExclusiveTo == "Store", "store exclusive: the two pets exist with ExclusiveTo")
		if not wisp or not crown or type(PC.IsExclusive) ~= "function" then
			return
		end
		T.check(PC.IsExclusive("week_wisp") and PC.IsExclusive("crown_phoenix") and not PC.IsExclusive("storm_tabby") and not PC.IsExclusive("nope"), "store exclusive: IsExclusive")
		local function inList(list, id)
			for _, d in ipairs(list) do
				if d.Id == id then
					return true
				end
			end
			return false
		end
		T.check(not inList(PC.ListByRarity("Epic"), "week_wisp") and not inList(PC.ListByRarity("Epic", true), "week_wisp") and not inList(PC.ListByRarity("Legendary", true), "crown_phoenix"), "store exclusive: in no pool, not even with includeEvent")
		for _, roulette in ipairs(Config.Roulettes) do
			T.check(not inList(PC.PossiblePets(roulette.Id), "week_wisp") and not inList(PC.PossiblePets(roulette.Id), "crown_phoenix"), "store exclusive: not in " .. roulette.Id .. "'s odds")
		end
		local inGroup = false
		for _, g in ipairs(PC.IndexGroups()) do
			if inList(g.Pets, "week_wisp") or inList(g.Pets, "crown_phoenix") then
				inGroup = true
			end
		end
		T.check(not inGroup, "store exclusive: NO Index group lists them")
		T.check(not table.find(BC.EventPets(), "week_wisp") and not table.find(BC.EventPets(), "crown_phoenix"), "store exclusive: BattleCatalog.EventPets reads EventOnly only")
		T.check(not PC.IsRollable("week_wisp") and not PC.IsRollable("crown_phoenix"), "store exclusive: IsRollable false")
		T.eq(PC.TotalCount(), 35, "store exclusive: TotalCount 35")
		T.check(select(1, PC.Validate()) == true and select(1, BC.Validate()) == true, "store exclusive: both catalogs Validate", table.concat(select(2, PC.Validate()) or {}, "; "))
		T.check(BC.FormNames.week_wisp[2] == "Tempest Crown" and BC.FormNames.crown_phoenix[2] == "Sovereign Flare", "store exclusive: form names")
		-- 2000 rolls of every roulette with Util.NewRng(seed): never an exclusive id (the smoke_p2_gems loop shape)
		local Util = K.M["shared/Util"]
		local rng = Util.NewRng(20261104)
		local leaks = T.tally("store exclusive: 2000 rolls of every roulette never give an exclusive pet")
		for _, r in ipairs(Config.Roulettes) do
			local found = nil
			for _ = 1, 2000 do
				local id = PC.RollPet(r.Id, rng)
				if id == nil or PC.IsExclusive(id) then
					found = tostring(id)
				end
			end
			leaks:case(found == nil, r.Id .. ": " .. tostring(found))
		end
		leaks:report()
	end)

	S.store_catalog = guarded("store_catalog", function()
		local inst = K.moduleInstance("shared/StoreCatalog")
		local SC = K.M["shared/StoreCatalog"] or (inst and select(2, pcall(require, inst)))
		local Config = K.config()
		T.check(type(SC) == "table" and type(SC.Validate) == "function", "store catalog: shared/StoreCatalog loads")
		if type(SC) ~= "table" or type(SC.Validate) ~= "function" then
			return
		end
		T.check(select(1, SC.Validate()) == true, "store catalog: Validate passes on the shipped Config", table.concat(select(2, SC.Validate()) or {}, "; "))
		T.check(#SC.Tabs == #Config.Store.Tabs and SC.Tabs[1] == "Packs" and SC.Tabs[5] == "Roulettes" and SC.Tabs ~= Config.Store.Tabs, "store catalog: Tabs is a copy of Config.Store.Tabs")
		local list = SC.List()
		T.eq(#list, 10 + #Config.Gems.Products, "store catalog: List = the 10 enabled items + the gem packs (Cash packs Enabled = false left out)")
		T.check(list[1].Key == "Starter" and list[10].Key == "Tokens3" and list[11].Key == "Gems1" and list[11].Kind == "Product" and list[11].Tab == "Currency" and list[11].Index == 1 and list[11].Name == "Pouch of Gems" and list[11].Grants.Gems == 100 and list[11].Gem == true, "store catalog: Config order, then the gem packs as Currency products")
		T.check(list[1].Created == false and list[1].Robux == 99 and list[1].Id == 0 and list[1].Once == true and list[1].Hero == true and SC.Created(list[1]) == false, "store catalog: a List item is a cleaned copy (Id 0, Created false, Robux, Once, Hero)")
		T.check(SC.Item("Cash1") == nil and SC.Item("Starter").Grants.Cash == 1000 and SC.Item("Gems2").Grants.Gems == 550 and SC.Item("Gems2").Hero == true and SC.Item("Gems1").Hero ~= true, "store catalog: Item by key; the Bag is the Currency hero")
		T.check(SC.Item("nope") == nil and SC.Item(nil) == nil and SC.Item(5) == nil, "store catalog: Item answers nil for junk keys")
		T.check(SC.ProductById(0) == nil and SC.PassById(0) == nil and SC.ProductById(nil) == nil and SC.ProductById("1") == nil and SC.PassById(-1) == nil, "store catalog: Id 0 (and junk) resolves to nothing on both sides")
		T.check(SC.Perk("CashX2").Cash == 2 and SC.Perk("Vip").DailyMult == 2 and SC.Perk("Nope") == nil and SC.Perk(nil) == nil, "store catalog: Perk reads Config.Store.Perks")
		local pro, gems = Config.Store.Items[2], Config.Gems.Products[3]
		local savedPro, savedGems = pro.Id, gems.Id
		pro.Id, gems.Id = 4411, 4412
		T.check(SC.ProductById(4411).Key == "Pro" and SC.ProductById(4412).Gem == true and SC.ProductById(4412).Grants.Gems == 1200 and SC.PassById(4411) == nil, "store catalog: a product id resolves (a gem pack too), never as a pass")
		T.check(SC.Item("Pro").Created == true and SC.Created(SC.Item("Pro")) == true and SC.Item("Gems3").Created == true, "store catalog: Created follows the Id")
		Config.Store.Items[3].Id = 4413
		T.check(SC.PassById(4413).Key == "VIP" and SC.ProductById(4413) == nil, "store catalog: a pass id resolves, never as a product")
		Config.Store.Items[3].Id, pro.Id, gems.Id = 0, savedPro, savedGems
		T.check(SC.ProductById(4411) == nil and SC.PassById(4413) == nil, "store catalog: Config.Store.Items is read on every call (the ids put back resolve to nothing)")
		local lines = SC.GrantLines(SC.Item("Starter").Grants)
		T.check(#lines == 3 and lines[1] == "1x Storm Tabby (Lv 5)" and lines[2] == "$1,000 Cash" and lines[3] == "1 h x2 Pet XP", "store catalog: the Starter's literal lines", table.concat(lines, " | "))
		lines = SC.GrantLines(SC.Item("Pro").Grants)
		T.check(#lines == 3 and lines[1] == "1x Crown Phoenix (Lv 10)" and lines[2] == "5,000 Cloud Tokens", "store catalog: the Pro's pet and Tokens lines", table.concat(lines, " | "))
		T.eq(lines[3], "x1.5 Pet XP in Dungeons and raids", "store catalog: the Pro perk line")
		T.check(SC.GrantLines(SC.Item("XpPotion3").Grants)[1] == "3 h x2 Pet XP" and SC.GrantLines({ Boost = { XpPotion = 1500 } })[1] == "25 min x2 Pet XP", "store catalog: potion lines (3 h, 25 min)")
		T.check(SC.GrantLines(SC.Item("Gems2").Grants)[1] == "550 Gems" and SC.GrantLines(SC.Item("VIP").Grants)[1] == "VIP: x2 daily Cash and Tokens, [VIP] in chat" and SC.GrantLines(SC.Item("Cash2x").Grants)[1] == "x2 Cash forever" and SC.GrantLines(SC.Item("PetXp2x").Grants)[1] == "x2 Pet XP forever", "store catalog: the Gems and perk lines")
		T.check(SC.GrantLines({ Pets = { storm_tabby = { Count = 2 } } })[1] == "2x Storm Tabby" and #SC.GrantLines(nil) == 0 and #SC.GrantLines({}) == 0, "store catalog: no (Lv n) without a Level; junk grants = no lines")
		-- Validate refusals: a deep copy of Config.Store.Items mutated, then restored; each a false with a problem naming the key
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
		local function refused(label, key, mutate)
			local saved, savedGemId = Config.Store.Items, Config.Gems.Products[1].Id
			Config.Store.Items = deepCopy(saved)
			mutate(Config.Store.Items)
			local ok, problems = SC.Validate()
			Config.Store.Items, Config.Gems.Products[1].Id = saved, savedGemId
			local named = false
			for _, pr in ipairs(problems or {}) do
				if string.find(pr, key, 1, true) then
					named = true
				end
			end
			T.check(ok == false and named, "store catalog: Validate refuses " .. label .. " (naming " .. key .. ")", table.concat(problems or {}, "; "))
		end
		refused("a duplicate Key", "Tokens1", function(c) c[9].Key = "Tokens1" end)
		refused("two items with Id 5", "Tokens2", function(c) c[8].Id = 5; c[9].Id = 5 end)
		refused("an Id shared with a gem product", "Tokens1", function(c) c[8].Id = 77; Config.Gems.Products[1].Id = 77 end)
		refused("a Pass granting Cash", "VIP", function(c) c[3].Grants.Cash = 5 end)
		refused("an unknown pet", "Starter", function(c) c[1].Grants.Pets = { nope = { Count = 1 } } end)
		refused("Level 0", "Starter", function(c) c[1].Grants.Pets.storm_tabby.Level = 0 end)
		refused("Count 100", "Starter", function(c) c[1].Grants.Pets.storm_tabby.Count = 100 end)
		refused("a potion past CapSeconds", "XpPotion3", function(c) c[7].Grants.Boost.XpPotion = Config.Store.Potion.CapSeconds + 1 end)
		refused("a perk name Nope", "Pro", function(c) c[2].Grants.Perks = { "Nope" } end)
		refused("Tab Gifts", "Tokens1", function(c) c[8].Tab = "Gifts" end)
		refused("Kind Thing", "Tokens1", function(c) c[8].Kind = "Thing" end)
		refused("a second Hero in Packs", "Pro", function(c) c[2].Hero = true end)
		refused("a Cash pack without its Line", "Cash1", function(c) c[11].Line = nil end)
		refused("Robux -1", "Tokens1", function(c) c[8].Robux = -1 end)
		refused("Tokens 0", "Tokens1", function(c) c[8].Grants.Tokens = 0 end)
		refused("a fractional Cash", "Starter", function(c) c[1].Grants.Cash = 10.5 end)
		refused("Once on a Pass", "VIP", function(c) c[3].Once = true end)
		refused("an empty Key", "item 8", function(c) c[8].Key = "" end)
	end)

	S.store_grantpet = guarded("store_grantpet", function()
		K.needBoot()
		local p = join("Grant", newUserId())
		K.waitFor(function() return DS().GetProfile(p) ~= nil end, 10)
		T.check(type(PS().GrantPet) == "function", "grantpet: PetService.GrantPet exists")
		if type(PS().GrantPet) ~= "function" then
			leave(p)
			return
		end
		local ok, res = PS().GrantPet(p, "storm_tabby", { Count = 1, Level = 5 })
		T.check(ok == true and type(res) == "table" and res.Granted == 1 and res.Count == 1 and res.IsNew == true and res.Level == 5, "grantpet: one Storm Tabby at level 5", tostring(res) .. (type(res) == "table" and (" granted " .. tostring(res.Granted) .. " count " .. tostring(res.Count)) or ""))
		T.eq(select(1, DS().GetPetLevel(p, "storm_tabby")), 5, "grantpet: the level was written")
		T.eq(DS().GetProfile(p).Stats.Spins, 0, "grantpet: no spin counted")
		T.check(DS().IsDiscovered(p, "storm_tabby") and PS().GetEquipped(p)[1] == "storm_tabby", "grantpet: discovered and auto-equipped as the first pet", table.concat(PS().GetEquipped(p), ","))
		ok, res = PS().GrantPet(p, "storm_tabby", { Count = 2, Level = 3 })
		T.check(ok and res.Granted == 2 and res.Count == 3 and select(1, DS().GetPetLevel(p, "storm_tabby")) == 5, "grantpet: +2 copies, the level never goes down")
		T.check(res.IsNew == false and res.PetId == "storm_tabby" and res.Key == "storm_tabby", "grantpet: the second grant is not new; PetId / Key answered")
		DS().GetProfile(p).Pets.storm_tabby = 99
		ok, res = PS().GrantPet(p, "storm_tabby", { Count = 1 })
		T.check(ok == false and res == "Stack full" and DS().GetProfile(p).Pets.storm_tabby == 99, "grantpet: a full stack is refused, nothing written", tostring(res))
		DS().GetProfile(p).Pets.storm_tabby = 98
		ok, res = PS().GrantPet(p, "storm_tabby", { Count = 5 })
		T.check(ok == true and res.Granted == 1 and res.Count == 99, "grantpet: a stack with room for one grants min(Count, room)")
		T.check(not PS().GrantPet(p, "nope") and not PS().GrantPet(p, "storm_tabby", { Count = 0 }) and not PS().GrantPet(p, "storm_tabby", { Count = 1.5 }) and not PS().GrantPet(p, "storm_tabby", { Count = "2" }), "grantpet: unknown pet / junk count refused")
		ok, res = PS().GrantPet(p, "crown_phoenix", { Count = 1, Level = 10 })
		T.check(ok == true and res.Granted == 1 and res.Level == 10 and res.NewDiscovery == true and DS().IsDiscovered(p, "crown_phoenix"), "grantpet: an exclusive pet is granted like any other (Crown Phoenix L10, discovered)")
		ok, res = PS().GrantPet(p, "week_wisp")
		T.check(ok == true and res.Granted == 1 and res.Level == nil and select(1, DS().GetPetLevel(p, "week_wisp")) == 1, "grantpet: no Level given = the level is left alone (1)")
		T.eq(DS().GetProfile(p).Stats.Spins, 0, "grantpet: still no spin counted")
		leave(p)
		-- a provisional player (the Mock.DataStore.Fail pattern of smoke_p2_gems): GrantPet answers false, "Your save is still loading"
		local savedFail = Mock.DataStore.Fail
		Mock.DataStore.Fail = true
		local prov = join("GrantOutage", newUserId())
		local isProv = K.waitFor(function() return DS().IsProvisional(prov) == true end, 10)
		T.check(isProv, "grantpet: (precondition) a load during an outage leaves a provisional profile")
		ok, res = PS().GrantPet(prov, "storm_tabby", { Count = 1, Level = 5 })
		T.check(ok == false and res == "Your save is still loading" and (DS().GetProfile(prov) == nil or (DS().GetProfile(prov).Pets.storm_tabby or 0) == 0), "grantpet: a provisional save is refused, nothing written", tostring(res))
		Mock.DataStore.Fail = savedFail
		K.waitFor(function() return DS().IsProvisional(prov) ~= true end, 60)
		leave(prov)
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client world
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}

	-- a module of the client build (the H.moduleAt shape of smoke_evo_retreat.lua; ROOTS is smoke.py's)
	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	-- the expectations were checked by hand against PetsController H.rect: 844x390 / inset 36 gives x 12, y 48, 820x330,
	-- scale 1, Phone; 1920x1080 gives x 330, 1260x900, PC
	S.client_store_bigrect = guarded("client_store_bigrect", function()
		local NK = moduleAt("client", "UI/NeonKit")
		T.check(type(NK) == "table" and type(NK.BigRect) == "function", "store bigrect: NeonKit.BigRect exists")
		if type(NK) ~= "table" or type(NK.BigRect) ~= "function" then
			return
		end
		local KP = { RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1260, Y1 = 900 }, MARGIN = 12, PHONE_W = 900, SHORT = 560, PC_MIN_H = 600, PC_MAX_W = 0.76 }
		local r = NK.BigRect(KP, { Width = 844, Height = 390, Inset = 36 })
		T.check(r.mode == "Phone" and r.scale == 1 and r.w == 820 and math.abs(r.h - 330) < 1 and r.x == 12 and r.y >= 36, "store bigrect: 844x390 = 820x330 at scale 1, Phone, under the inset", string.format("%s %sx%s at %s,%s scale %s", tostring(r.mode), tostring(r.w), tostring(r.h), tostring(r.x), tostring(r.y), tostring(r.scale)))
		r = NK.BigRect(KP, { Width = 1920, Height = 1080, Inset = 58 })
		T.check(r.mode == "PC" and math.abs(r.w - 1260) < 1 and math.abs(r.h - 900) < 1 and math.abs(r.x - 330) < 1, "store bigrect: 1920x1080 = 1260x900 centred, PC", string.format("%s %sx%s at %s,%s scale %s", tostring(r.mode), tostring(r.w), tostring(r.h), tostring(r.x), tostring(r.y), tostring(r.scale)))
		T.check(r.portrait == false, "store bigrect: a landscape window is not portrait")
		T.check(NK.Glyphs.Store ~= nil and NK.Glyphs.Gifts ~= nil and NK.Glyphs.Packs ~= nil and NK.Glyphs.Roulettes ~= nil and NK.Glyphs.VipCrown ~= nil and NK.Glyphs.Trove ~= nil, "store bigrect: the new glyph ids")
		T.check(NK.Glyphs.Passes ~= nil and NK.Glyphs.Boosts ~= nil and NK.Glyphs.Currency ~= nil, "store bigrect: the tab glyph ids")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
