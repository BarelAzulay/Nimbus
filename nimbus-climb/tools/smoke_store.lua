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

	----------------------------------------------------------------------------------------------------
	-- W2-money (Task 9): the receipt router, the pass cache, Multipliers at the five sites, StoreRequest
	----------------------------------------------------------------------------------------------------
	local MPS = game:GetService("MarketplaceService")
	local function SS()
		return requireAt("server/Services/StoreService")
	end
	local function MU()
		return requireAt("server/Services/Multipliers")
	end
	local function GS()
		return requireAt("server/Services/GemService")
	end
	local function CARE()
		return requireAt("server/Services/PetCareService")
	end
	local function TY()
		return requireAt("server/Services/TycoonService")
	end
	local function BS()
		return requireAt("server/Services/BattleService")
	end
	local function DEV()
		return requireAt("server/Services/DevService")
	end
	local function TC()
		return K.M["shared/TycoonCatalog"] or requireAt("shared/TycoonCatalog")
	end
	local function PK()
		return K.M["shared/PetKeys"] or requireAt("shared/PetKeys")
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
	local function storeKey(uid)
		return K.config().Tokens.DataStoreName .. "/u_" .. uid
	end
	local function stored(uid)
		return Mock.DataStore.Data[storeKey(uid)]
	end
	-- a stored record the next join loads (the smoke_p7_data shape)
	local function storedRecord(extra)
		local rec = { Version = 2, Tokens = 5, Pets = {}, Equipped = {}, Items = {}, Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} } }
		for k, v in pairs(extra or {}) do
			rec[k] = v
		end
		return rec
	end
	-- runs fn(...) in its own thread (it may yield): box.done / box.ok / box.result (the smoke_p2_gems shape)
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
	-- Notify toasts to p since the log mark whose text holds `needle` (a plain find: the lines carry parentheses)
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
	local function spots()
		return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
	end
	local function freeIndex()
		local SpotS = K.mod("SpotService")
		for i = 1, K.config().Lobby.SpotCount do
			if spots()[i] and not SpotS.GetOwner(i) then
				return i
			end
		end
		return nil
	end
	local function standAt(p, pos)
		Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 0)))
	end
	local function givePet(p, key, n)
		local prof = DS().GetProfile(p)
		local ok = PK().Add(prof, key, n or 1)
		DS().MarkDirty(p)
		return ok
	end
	local function totalXp(p, key)
		local level, xp = DS().GetPetLevel(p, key)
		return TC().XpForLevel(level) + xp
	end
	local function commonPet()
		for _, def in ipairs(K.M["shared/PetCatalog"].Pets) do
			if def.Rarity == "Common" and def.EventOnly ~= true and def.ExclusiveTo == nil then
				return def
			end
		end
		return nil
	end
	-- the engine's "the player just bought that pass" event
	local function ownPass(p, id)
		Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p, id, true)
		K.advance(0.2)
	end
	local function sourceOf(key)
		local inst = K.moduleInstance(key)
		return (inst and inst.Source) or ""
	end
	local function leaveAll(list)
		for _, p in ipairs(list) do
			if p and p.Parent then
				Mock.RemovePlayer(p)
			end
		end
		K.advance(0.8)
	end

	S.store_router = guarded("store_router", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local Store, Gems = SS(), GS()
		if not T.check(type(Store) == "table" and type(Store.ApplyGrant) == "function" and type(Gems) == "table", "store router: StoreService (ApplyGrant) and GemService load") then
			return
		end
		local cb = type(MPS.ProcessReceipt) == "function" and MPS.ProcessReceipt or Gems.ProcessReceipt
		local GRANTED, NOT_YET = Enum.ProductPurchaseDecision.PurchaseGranted, Enum.ProductPurchaseDecision.NotProcessedYet
		local DSt = Mock.DataStore
		local saved = { Ids = savedIds(), Studio = Mock.Options.Studio, Fail = DSt.Fail }
		local players, purchased = {}, {}
		local conn = Store.Purchased:Connect(function(player, key, granted, purchaseId)
			purchased[#purchased + 1] = { Player = player, Key = key, Granted = granted, PurchaseId = purchaseId }
		end)
		local function purchasesOf(id)
			local n = 0
			for _, e in ipairs(purchased) do
				if e.PurchaseId == id then
					n = n + 1
				end
			end
			return n
		end
		local function run(info)
			return runReceipt(cb, info)
		end
		local okRun, errRun = pcall(function()
			setId("Starter", 6001)
			setId("XpPotion1", 6002)
			setId("Tokens1", 6003)
			setId("Pro", 6004)
			local p = join("Router", newUserId())
			players[#players + 1] = p
			T.check(loaded(p), "store router: (precondition) the buyer's profile is loaded")
			local cash0, tok0 = DS().GetCash(p), DS().GetTokens(p)
			T.eq(run(receipt(p, 6003, "r-tok-1")), GRANTED, "store router: a Tokens pack is granted")
			T.eq(DS().GetTokens(p), tok0 + 500, "store router: +500 Tokens")
			T.check(purchasesOf("r-tok-1") == 1 and purchased[1] and purchased[1].Player == p and purchased[1].Key == "Tokens1" and type(purchased[1].Granted) == "table" and purchased[1].Granted.Tokens == 500,
				"store router: Purchased fired once (player, key, granted, purchaseId)")
			T.eq(run(receipt(p, 6003, "r-tok-1")), GRANTED, "store router: the same purchase id again grants nothing more")
			T.eq(DS().GetTokens(p), tok0 + 500, "store router: ...still +500")
			T.eq(purchasesOf("r-tok-1"), 1, "store router: ...and Purchased stays at one")
			local tPot = os.time()
			local a, b = spawnCall(cb, receipt(p, 6002, "r-pot-1")), spawnCall(cb, receipt(p, 6002, "r-pot-1"))
			K.waitFor(function()
				return a.done and b.done
			end, 60)
			T.check(a.result == GRANTED and b.result == GRANTED, "store router: two calls at once for one id both answer PurchaseGranted", tostring(a.result) .. " / " .. tostring(b.result))
			T.near(Store.BoostEnds(p, "XpPotion"), tPot + 3600, 2, "store router: two calls at once for one id = one potion hour (K.waitFor advances the clock while ProcessReceipt saves: compare with the time captured before the grant)")
			T.eq(purchasesOf("r-pot-1"), 1, "store router: ...Purchased once for the pair")
			local mark = K.logSize()
			T.eq(run(receipt(p, 6001, "r-start-1")), GRANTED, "store router: the Starter in one save")
			local prof = DS().GetProfile(p)
			T.check(prof.Pets.storm_tabby == 1 and select(1, DS().GetPetLevel(p, "storm_tabby")) == 5 and DS().GetCash(p) == cash0 + 1000 and math.abs(Store.BoostEnds(p, "XpPotion") - (tPot + 7200)) <= 2 and DS().GetStore(p).Bought.Starter ~= nil,
				"store router: pet L5 + $1,000 + the potion stacked in time onto the running hour + Bought",
				string.format("tabby %s L%s cash +%s potion %s bought %s", tostring(prof.Pets.storm_tabby), tostring(select(1, DS().GetPetLevel(p, "storm_tabby"))), tostring(DS().GetCash(p) - cash0), tostring(Store.BoostEnds(p, "XpPotion") - tPot), tostring(DS().GetStore(p).Bought.Starter)))
			T.check(toastCount(p, "Thank you", mark) == 1 and toastCount(p, "1x Storm Tabby (Lv 5)", mark) == 1 and toastCount(p, "$1,000 Cash", mark) == 1 and toastCount(p, "1 h x2 Pet XP", mark) == 1,
				"store router: one thank-you toast with the literal lines", toastsSince(p, mark))
			T.check(stored(p.UserId) ~= nil and type(stored(p.UserId).Store) == "table" and stored(p.UserId).Store.Bought.Starter ~= nil and stored(p.UserId).Pets.storm_tabby == 1, "store router: saved before PurchaseGranted")
			T.eq(run(receipt(p, 6001, "r-start-2")), GRANTED, "store router: a second Starter receipt (Roblox sold it again) is granted again with a warn (Z7)")
			T.eq(DS().GetProfile(p).Pets.storm_tabby, 2, "store router: ...2 copies")
			T.eq(run(receipt(p, 9999, "r-unk")), NOT_YET, "store router: an unknown id stays pending")
			T.eq(run({ PlayerId = 1, ProductId = 6003, PurchaseId = "r-nothere" }), NOT_YET, "store router: a buyer who is not here stays pending")
			T.eq(run({ PlayerId = p.UserId, ProductId = 6003 }), NOT_YET, "store router: a malformed receipt stays pending")

			-- a rejoin (spec 11 / Z14): the save fails, the grant waits in the live profile, the player leaves (the orphan
			-- retry saves it), rejoins the same server, and Roblox's retry grants nothing more: +500 ONCE for that id
			Mock.Options.Studio = false
			local tokR = DS().GetTokens(p)
			DSt.Fail = true
			T.eq(run(receipt(p, 6003, "r-rejoin")), NOT_YET, "store router: (rejoin) a failed save answers NotProcessedYet")
			DSt.Fail = saved.Fail
			local uid = p.UserId
			leave(p)
			K.advance(1)
			p = join("Router", uid)
			players[#players + 1] = p
			T.check(loaded(p), "store router: (rejoin) the profile loads again")
			T.eq(run(receipt(p, 6003, "r-rejoin")), GRANTED, "store router: (rejoin) Roblox's retry answers PurchaseGranted")
			T.eq(DS().GetTokens(p), tokR + 500, "store router: (rejoin) +500 Tokens ONCE for that id across the failed save and the rejoin")
			T.eq(run(receipt(p, 6003, "r-rejoin")), GRANTED, "store router: (rejoin) a repeat grants nothing more")
			T.eq(DS().GetTokens(p), tokR + 500, "store router: (rejoin) ...still +500")

			-- a failed save on a live server: NotProcessedYet, then the retry GRANTED once (Purchased after the save that lands)
			DSt.Fail = true
			local tokF = DS().GetTokens(p)
			T.eq(run(receipt(p, 6003, "r-fail-1")), NOT_YET, "store router: (live) a failed save answers NotProcessedYet")
			T.check(DS().GetTokens(p) == tokF + 500 and purchasesOf("r-fail-1") == 0, "store router: (live) ...the Tokens wait in the session, Purchased not yet")
			DSt.Fail = saved.Fail
			T.eq(run(receipt(p, 6003, "r-fail-1")), GRANTED, "store router: (live) the retry saves and answers PurchaseGranted")
			T.check(DS().GetTokens(p) == tokF + 500 and purchasesOf("r-fail-1") == 1, "store router: (live) ...granted once, Purchased once after the save that landed")
			Mock.Options.Studio = true
			DSt.Fail = true
			T.eq(run(receipt(p, 6003, "r-studio")), GRANTED, "store router: (Studio) a failed save still answers PurchaseGranted")
			T.eq(purchasesOf("r-studio"), 1, "store router: (Studio) ...Purchased fired once")
			DSt.Fail = saved.Fail
			Mock.Options.Studio = saved.Studio

			-- provisional (Z13): never decided from stand-in defaults; granted after the recovery
			DSt.Fail = true
			local prov = join("RouterProv", newUserId())
			players[#players + 1] = prov
			T.check(K.waitFor(function()
				return DS().IsProvisional(prov) == true
			end, 10), "store router: (precondition) a load during an outage leaves a provisional profile")
			local boxP = spawnCall(cb, receipt(prov, 6003, "r-prov"))
			K.waitFor(function()
				return boxP.done
			end, Gems.ProfileWaitSeconds + 5)
			T.check(boxP.done and boxP.result == NOT_YET, "store router: a provisional profile: NotProcessedYet after the wait", tostring(boxP.result))
			DSt.Fail = saved.Fail
			T.check(K.waitFor(function()
				return DS().IsProvisional(prov) ~= true
			end, 60), "store router: (precondition) the recovery reads the real save")
			local tokP = DS().GetTokens(prov)
			T.eq(run(receipt(prov, 6003, "r-prov")), GRANTED, "store router: after the recovery the purchase is granted")
			T.eq(run(receipt(prov, 6003, "r-prov")), GRANTED, "store router: ...(a retry)")
			T.eq(DS().GetTokens(prov), tokP + 500, "store router: ...exactly once")

			-- Review Focus 1: a late receipt in a match is granted (StoreRequest is refused, ProcessReceipt never checks InMatch)
			p:SetAttribute(Config.Attr.InMatch, true)
			local tokM = DS().GetTokens(p)
			T.eq(run(receipt(p, 6003, "r-tok-match")), GRANTED, "store router: a late receipt in a match is granted (Review Focus 1)")
			T.eq(DS().GetTokens(p), tokM + 500, "store router: ...+500")
			p:SetAttribute(Config.Attr.InMatch, nil)

			-- Z7: a Pro pack on a full Crown Phoenix stack pays the Index Legendary Tokens instead, never pends
			DS().GetProfile(p).Pets.crown_phoenix = 99
			local tokB = DS().GetTokens(p)
			mark = K.logSize()
			T.eq(run(receipt(p, 6004, "r-pro-full")), GRANTED, "store router: the Pro pack on a full stack is granted")
			T.check(DS().GetProfile(p).Pets.crown_phoenix == 99 and DS().GetTokens(p) == tokB + 5000 + 2000 and toastCount(p, "Stack full: +2,000 Tokens instead", 0) == 1 and DS().GetStore(p).Bought.Pro ~= nil,
				"store router: ...Tokens substitute (Index Legendary 2,000) + the toast + Bought", "tokens +" .. tostring(DS().GetTokens(p) - tokB) .. " | " .. toastsSince(p, mark))
			T.check(toastCount(p, "Thank you", mark) == 1 and toastCount(p, "7,000 Cloud Tokens", mark) == 1, "store router: ...the thank-you names what was REALLY granted (7,000 Cloud Tokens)", toastsSince(p, mark))
			local last = purchased[#purchased]
			T.check(last and last.PurchaseId == "r-pro-full" and last.Granted.Tokens == 7000 and type(last.Granted.Substitute) == "table" and last.Granted.Substitute.crown_phoenix == 2000 and last.Granted.Pets == nil,
				"store router: ...Purchased's granted = { Tokens 7000, Substitute = { crown_phoenix = 2000 } }")

			-- Z7: a potion past the 7-day cap is granted and extends past the cap
			DS().AddBoost(p, "XpPotion", 7 * 86400)
			local ends = Store.BoostEnds(p, "XpPotion")
			T.eq(run(receipt(p, 6002, "r-pot-cap")), GRANTED, "store router: a potion past the 7-day cap is granted")
			T.eq(Store.BoostEnds(p, "XpPotion"), ends + 3600, "store router: ...and extends past the cap")

			-- a gem pack still goes the old way: the gem toast, GemsPurchased AND Purchased
			local gemPack = Config.Gems.Products[2]
			local savedGem = gemPack.Id
			gemPack.Id = 6090
			local gems0 = DS().GetGems(p)
			local gemFires = 0
			local gconn = Gems.GemsPurchased:Connect(function(player, gems, productId, purchaseId)
				if player == p and purchaseId == "r-gems" then
					gemFires = gemFires + 1
				end
			end)
			mark = K.logSize()
			T.eq(run(receipt(p, 6090, "r-gems")), GRANTED, "store router: a gem pack is granted")
			gconn:Disconnect()
			gemPack.Id = savedGem
			T.check(DS().GetGems(p) == gems0 + gemPack.Gems and gemFires == 1 and purchasesOf("r-gems") == 1 and toastCount(p, "Gems! Thank you for your support!", mark) == 1,
				"store router: ...+" .. gemPack.Gems .. " Gems, GemsPurchased once, Purchased once, the gem toast as before", toastsSince(p, mark))
		end)
		conn:Disconnect()
		restoreIds(saved.Ids)
		Mock.Options.Studio = saved.Studio
		DSt.Fail = saved.Fail
		leaveAll(players)
		if not okRun then
			error(errRun, 0)
		end
	end)

	S.store_passes = guarded("store_passes", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local Store, Mult = SS(), MU()
		if not T.check(type(Store) == "table" and type(Store.PassState) == "function" and type(Mult) == "table", "store passes: StoreService and Multipliers load") then
			return
		end
		local saved = { Ids = savedIds(), Trust = Config.Store.TrustLedgerAfter }
		local players = {}
		local calls = {} -- [uid .. ":" .. passId] = lookups
		local modes = {} -- [uid] = true (owns VIP) | false | "error"
		MPS.UserOwnsGamePassAsync = function(_, uid, id)
			local k = tostring(uid) .. ":" .. tostring(id)
			calls[k] = (calls[k] or 0) + 1
			local mode = modes[uid]
			if mode == "error" then
				error("HTTP 503 (smoke: pass lookup outage)")
			end
			return mode == true and id == 7001
		end
		local okRun, errRun = pcall(function()
			setId("VIP", 7001)
			setId("Cash2x", 7002)
			setId("PetXp2x", 7003)
			-- p1: the engine says VIP is owned
			local uid1 = newUserId()
			modes[uid1] = true
			local p1 = join("PassOwner", uid1)
			players[#players + 1] = p1
			T.check(Store.Owns(p1, "VIP") == true and Store.PassState(p1, "VIP") == "Owned", "store passes: an owned pass: Owns within 1 s of the join")
			T.eq(p1:GetAttribute(Config.Attr.OwnedPasses), "VIP", "store passes: ...OwnedPasses == 'VIP'")
			T.check(Store.PassState(p1, "Cash2x") == "NotOwned" and Store.Owns(p1, "Cash2x") == false, "store passes: a false answer = NotOwned")
			T.check(calls[uid1 .. ":7001"] == 1 and calls[uid1 .. ":7002"] == 1 and calls[uid1 .. ":7003"] == 1, "store passes: exactly 1 UserOwnsGamePassAsync call per pass per join",
				tostring(calls[uid1 .. ":7001"]) .. "/" .. tostring(calls[uid1 .. ":7002"]) .. "/" .. tostring(calls[uid1 .. ":7003"]))
			T.check(Store.PassState(p1, "Nope") == "Unavailable" and Store.PassState(p1, "Starter") == "Unavailable", "store passes: an unknown key or a product = Unavailable")
			setId("PetXp2x", 0)
			T.check(Store.PassState(p1, "PetXp2x") == "Unavailable" and Store.Owns(p1, "PetXp2x") == false, "store passes: an Id 0 pass = Unavailable")
			setId("PetXp2x", 7003)
			T.check(loaded(p1) and DS().GetStore(p1).Passes.VIP ~= nil, "store passes: ...a true answer is written to Store.Passes (MarkPassSeen)")

			-- p2: the lookup fails, then the retry 5 s later succeeds
			local uid2 = newUserId()
			modes[uid2] = "error"
			local p2 = join("PassRetry", uid2)
			players[#players + 1] = p2
			T.check(Store.PassState(p2, "VIP") == "Checking" and Store.Owns(p2, "VIP") == false, "store passes: a failing lookup = Checking, Owns false (fail closed)")
			T.check((p2:GetAttribute(Config.Attr.OwnedPasses) or "") == "", "store passes: ...OwnedPasses empty")
			modes[uid2] = true
			K.advance(5.5)
			T.check(Store.Owns(p2, "VIP") == true and Store.PassState(p2, "VIP") == "Owned", "store passes: the retry after 5 s finds the pass owned", Store.PassState(p2, "VIP"))
			T.eq(p2:GetAttribute(Config.Attr.OwnedPasses), "VIP", "store passes: ...and the attribute follows")
			T.eq(calls[uid2 .. ":7001"], 2, "store passes: ...two lookups of that pass (the failure and the retry)")

			-- p3: not owned, then bought in this session (PromptGamePassPurchaseFinished)
			local uid3 = newUserId()
			modes[uid3] = false
			local p3 = join("PassBuyer", uid3)
			players[#players + 1] = p3
			T.eq(Store.PassState(p3, "VIP"), "NotOwned", "store passes: a false answer = NotOwned")
			local mark = K.logSize()
			Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p3, 7001, true)
			T.check(Store.Owns(p3, "VIP") == true and Store.PassState(p3, "VIP") == "Owned", "store passes: PromptGamePassPurchaseFinished(player, id, true) = Owned at once")
			K.advance(0.3)
			T.check(DS().GetStore(p3).Passes.VIP ~= nil, "store passes: ...Store.Passes.VIP set")
			T.eq(p3:GetAttribute(Config.Attr.OwnedPasses), "VIP", "store passes: ...OwnedPasses == 'VIP'")
			T.check(toastCount(p3, "Thank you", mark) == 1 and toastCount(p3, "VIP: x2 daily Cash and Tokens, [VIP] in chat", mark) == 1, "store passes: ...one thank-you toast with the perk line", toastsSince(p3, mark))
			Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p3, 7002, false)
			Mock.FireSignal(MPS, "PromptGamePassPurchaseFinished", p3, 424242, true)
			T.check(Store.Owns(p3, "Cash2x") == false, "store passes: wasPurchased false / an unknown pass id change nothing")
			p3:SetAttribute(Config.Attr.OwnedPasses, "VIP,Cash2x")
			K.advance(0.5)
			T.check(Store.Owns(p3, "Cash2x") == false and Mult.Cash(p3, 100, "Scoop") == 100, "store passes: a spoofed OwnedPasses attribute is never read back (Z3)")

			-- TrustLedgerAfter (spec 5.4 / Z7): a stored ledger counts as Owned after that many seconds of failures
			Config.Store.TrustLedgerAfter = 30
			local uid4 = newUserId()
			modes[uid4] = "error"
			Mock.DataStore.Data[storeKey(uid4)] = storedRecord({ Store = { Passes = { VIP = 1767312000 } } })
			local p4 = Mock.AddPlayer("PassLedger" .. tostring(uid4 % 1000), uid4)
			players[#players + 1] = p4
			K.advance(0.3)
			T.check(loaded(p4) and DS().GetStore(p4).Passes.VIP ~= nil, "store passes: (precondition) the stored ledger holds VIP")
			T.eq(Store.PassState(p4, "VIP"), "Checking", "store passes: TrustLedgerAfter 30: Checking while the lookups fail")
			K.advance(29)
			T.check(Store.PassState(p4, "VIP") == "Checking" and Store.Owns(p4, "VIP") == false, "store passes: ...still Checking through the first 30 s of failures", Store.PassState(p4, "VIP"))
			K.advance(2)
			T.check(Store.PassState(p4, "VIP") == "Owned" and Store.Owns(p4, "VIP") == true, "store passes: ...then the ledger is trusted: Owned", Store.PassState(p4, "VIP"))
			T.eq(p4:GetAttribute(Config.Attr.OwnedPasses), "VIP", "store passes: ...OwnedPasses == 'VIP'")
			T.check(Store.Owns(p4, "Cash2x") == false and Store.PassState(p4, "Cash2x") == "Checking", "store passes: ...a pass the ledger does not hold stays Checking")
			Config.Store.TrustLedgerAfter = 0
			local uid5 = newUserId()
			modes[uid5] = "error"
			Mock.DataStore.Data[storeKey(uid5)] = storedRecord({ Store = { Passes = { VIP = 1767312000 } } })
			local p5 = Mock.AddPlayer("PassNoTrust" .. tostring(uid5 % 1000), uid5)
			players[#players + 1] = p5
			K.advance(0.3)
			T.check(loaded(p5) and DS().GetStore(p5).Passes.VIP ~= nil, "store passes: (precondition) the fifth player's ledger holds VIP")
			K.advance(600)
			T.check(Store.PassState(p5, "VIP") == "Checking" and Store.Owns(p5, "VIP") == false, "store passes: TrustLedgerAfter 0 = never trust: Checking through 600 s", Store.PassState(p5, "VIP"))
			T.check((calls[uid5 .. ":7001"] or 0) >= 4 and (calls[uid5 .. ":7001"] or 0) <= 8, "store passes: ...retried 5 / 15 / 45 / 120 s then every 300 s (4..8 lookups in 600 s)", tostring(calls[uid5 .. ":7001"]))
		end)
		MPS.UserOwnsGamePassAsync = nil
		Config.Store.TrustLedgerAfter = saved.Trust
		restoreIds(saved.Ids)
		leaveAll(players)
		if not okRun then
			error(errRun, 0)
		end
	end)

	S.store_mult = guarded("store_mult", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local Store, Mult, Care, Ty, Battle, Cat = SS(), MU(), CARE(), TY(), BS(), TC()
		if not T.check(Store and Mult and Care and Ty and Battle and Cat, "store mult: StoreService, Multipliers, PetCareService, TycoonService, BattleService and TycoonCatalog load") then
			return
		end
		local saved = { Ids = savedIds() }
		local players = {}
		local owned = {} -- [uid] = { [passId] = true }
		MPS.UserOwnsGamePassAsync = function(_, uid, id)
			return owned[uid] ~= nil and owned[uid][id] == true
		end
		local okRun, errRun = pcall(function()
			setId("VIP", 7001)
			setId("Cash2x", 7002)
			setId("PetXp2x", 7003)
			local pet = commonPet()
			T.check(pet ~= nil, "store mult: (precondition) a Common pet")
			local p = join("MultPass", newUserId())
			players[#players + 1] = p
			local q = join("MultPlain", newUserId())
			players[#players + 1] = q
			T.check(loaded(p) and loaded(q), "store mult: (precondition) both profiles loaded")

			-- Cash: the factor
			T.check(Mult.Cash(p, 100, "Scoop") == 100 and Mult.State(p).Cash == 1, "store mult: no pass: Cash x1")
			ownPass(p, 7002)
			T.check(Store.Owns(p, "Cash2x") == true and Mult.Cash(p, 100, "Scoop") == 200 and Mult.State(p).Cash == 2, "store mult: Cash2x: Cash x2")
			T.check(Mult.Cash(p, 300, "Dungeon") == 600 and Mult.Cash(p, 500, "Chest") == 1000 and Mult.Cash(p, 250, "Ring") == 500, "store mult: ...at every Cash source (Dungeon 300 -> 600, Chest 500 -> 1000, Ring 250 -> 500)")
			T.check(Mult.Cash(q, 300, "Dungeon") == 300 and Mult.Cash(q, 250, "Ring") == 250 and Mult.State(q).Cash == 1, "store mult: ...x1 for a player without the pass")

			-- the scoop (TycoonService's site): the bank waits as the Welcome-back pile of a freshly claimed home
			local function scoop(pl, bank)
				DS().MutateHome(pl, function(h)
					h.CollectorCash = bank
				end)
				local okC, whyC = Ty.Claim(pl, freeIndex())
				K.advance(0.6)
				local piles = Ty.Piles(pl)
				local pos = piles and piles.W and piles.W.Pos
				if okC ~= true or typeof(pos) ~= "Vector3" then
					return nil, tostring(whyC) .. " / " .. tostring(pos)
				end
				local before = DS().GetCash(pl)
				standAt(pl, pos)
				K.advance(0.6)
				return DS().GetCash(pl) - before, "pile " .. tostring(piles.W.Value) .. " bank now " .. tostring(DS().GetHome(pl).CollectorCash)
			end
			local got, why = scoop(q, 100)
			T.eq(got, 100, "store mult: a scoop of 100 banked Cash credits 100 without the pass", why)
			got, why = scoop(p, 100)
			T.eq(got, 200, "store mult: ...and 200 with Cash2x (the scoop site)", why)
			T.eq(DS().GetHome(p).CollectorCash, 0, "store mult: ...the bank dropped the 100 it held (the lawn never doubles)")

			-- a refund stays base: TrainStop gives Job.Paid back exactly (Z5)
			givePet(p, pet.Id, 2)
			DS().AddCash(p, 1000000)
			DS().MutateHome(p, function(h)
				h.Stations.Garden = 1
				h.Stations.Press1 = 1
				h.Stations.Kitchen = 1
				h.Stations.Gym = 1
				h.Level = Cat.HomeLevelOf(h)
			end)
			K.advance(2.1)
			local cashT = DS().GetCash(p)
			local okT, job = Care.Train(p, pet.Id, "Physique")
			K.advance(0.3)
			local okS, refund = Care.TrainStop(p, pet.Id)
			K.advance(0.3)
			T.check(okT == true and okS == true and type(job) == "table" and refund == job.Cost and DS().GetCash(p) == cashT, "store mult: a TrainStop refund is +Paid exactly with Cash2x owned (never x2)",
				tostring(okT) .. "/" .. tostring(type(job) == "table" and job.Cost or job) .. " stop " .. tostring(okS) .. "/" .. tostring(refund) .. " cash " .. tostring(DS().GetCash(p) - cashT))

			-- prestige Gems are never multiplied
			DS().MutateHome(p, function(h)
				for _, def in ipairs(Cat.Stations) do
					if not def.KeepOnPrestige then
						h.Stations[def.Id] = def.MaxLevel
					end
				end
				h.Stations.FusionMachine = 0
				h.Stations.ArenaGate = 0
				h.Level = Cat.HomeLevelOf(h)
			end)
			K.advance(1.2)
			local gems0 = DS().GetGems(p)
			local okP, stars = Ty.Prestige(p)
			K.advance(0.3)
			T.check(okP == true and DS().GetGems(p) - gems0 == math.floor(Cat.PrestigeGems(1)), "store mult: a Prestige with Cash2x owned pays the star's Gems exactly once (Multipliers never sees Gems)", tostring(stars) .. " / +" .. tostring(DS().GetGems(p) - gems0) .. " want " .. tostring(Cat.PrestigeGems(1)))

			-- XP: PetCareService's grantXp first line (GrantXp with the caller's source, a Feed through the Food Machine)
			givePet(q, pet.Id, 1)
			local function grant(pl, source, xp)
				local before = totalXp(pl, pet.Id)
				local given, _, why = Care.GrantXp(pl, pet.Id, xp or 40, source)
				return totalXp(pl, pet.Id) - before, tostring(given) .. " " .. tostring(why)
			end
			local gotXp, whyXp = grant(q, "Dungeon")
			T.eq(gotXp, 40, "store mult: no pass, no potion: a Dungeon GrantXp of 40 gives 40", whyXp)
			gotXp, whyXp = grant(p, "Dungeon")
			T.eq(gotXp, 40, "store mult: Cash2x alone never touches XP", whyXp)
			ownPass(p, 7003)
			T.check(Store.Owns(p, "PetXp2x") == true and Mult.State(p).PetXp == 2, "store mult: PetXp2x owned: State.PetXp 2")
			T.eq((grant(p, "Dungeon")), 80, "store mult: PetXp2x doubles a Dungeon GrantXp (40 -> 80)")
			T.eq((grant(p, "Feed")), 80, "store mult: ...and a Feed")
			T.eq(p:GetAttribute(Config.Attr.OwnedPasses), "Cash2x,PetXp2x", "store mult: OwnedPasses csv in Config.Store.Items order")
			-- the potion on the plain player: a real feed through the Food Machine
			DS().MutateHome(q, function(h)
				h.Stations.Garden = 1
				h.Stations.Press1 = 1
				h.Stations.Kitchen = 1
				h.Level = Cat.HomeLevelOf(h)
			end)
			K.advance(2.1)
			DS().AddBerries(q, 1000000)
			local beforeF = totalXp(q, pet.Id)
			local okF, whyF = Care.Feed(q, pet.Id)
			local feedXp = totalXp(q, pet.Id) - beforeF
			T.check(okF == true and feedXp > 0, "store mult: (precondition) a feed without a potion gives its base XP (" .. tostring(feedXp) .. ")", tostring(whyF))
			local okB, ends = DS().AddBoost(q, "XpPotion", 3600)
			Store.Refresh(q)
			K.advance(0.2)
			T.check(okB == true and Store.BoostEnds(q, "XpPotion") == ends and ends > os.time(), "store mult: (precondition) a potion hour runs (BoostEnds)")
			T.eq(q:GetAttribute(Config.Attr.XpBoostEnds), ends, "store mult: XpBoostEnds attribute == the potion end")
			T.check(Mult.State(q).PetXp == 2 and Mult.State(q).PotionEnds == ends and Mult.State(q).Cash == 1, "store mult: State: PetXp 2 by the potion, PotionEnds, Cash 1")
			beforeF = totalXp(q, pet.Id)
			okF, whyF = Care.Feed(q, pet.Id)
			T.eq(totalXp(q, pet.Id) - beforeF, feedXp * 2, "store mult: a potion doubles a feed's XP (" .. feedXp .. " -> " .. (feedXp * 2) .. ")", tostring(whyF))
			T.eq((grant(q, "Ring")), 80, "store mult: ...and a Ring GrantXp (40 -> 80)")
			-- pass + potion = x2, never x4
			DS().AddBoost(p, "XpPotion", 3600)
			Store.Refresh(p)
			K.advance(0.2)
			T.eq((grant(p, "Dungeon")), 80, "store mult: pass + potion = x2, not x4")
			-- the Pro pack: x1.5 in PvE only
			T.eq(DS().MarkBought(p, "Pro"), true, "store mult: (precondition) Bought.Pro")
			Store.Refresh(p)
			K.advance(0.2)
			T.check(Mult.State(p).PvE == 1.5 and Mult.State(p).Bought.Pro == true and Mult.State(p).Passes.Cash2x == true and Mult.State(p).Passes.PetXp2x == true, "store mult: State: PvE 1.5 with Bought.Pro, Passes, Bought")
			T.eq((grant(p, "Dungeon")), 120, "store mult: Bought.Pro: Dungeon x2 x1.5 = 120")
			T.eq((grant(p, "Raid")), 120, "store mult: ...Raid x1.5 too")
			T.eq((grant(p, "Ring")), 80, "store mult: ...Ring x1 (80)")
			T.eq((grant(p, "Duel")), 80, "store mult: ...Duel x1")
			T.eq((grant(p, "Feed")), 80, "store mult: ...Feed x1")
			T.check(Mult.State(q).PvE == 1 and (grant(q, "Dungeon")) == 80, "store mult: ...without Bought.Pro a Dungeon grant is x2 by the potion only")
			T.eq(p:GetAttribute(Config.Attr.StoreBought), "Pro", "store mult: StoreBought attribute == 'Pro'")
			T.check(Mult.PetXp(p, 0 / 0, "Dungeon") ~= Mult.PetXp(p, 0 / 0, "Dungeon") and Mult.Cash(p, nil, "Scoop") == nil, "store mult: junk amounts pass through unchanged")

			-- the dev /reset keeps Store.Bought.Pro and the pass answers (p7data_reset pins the data side)
			local Dev = DEV()
			if Dev and type(Dev.Run) == "function" then
				local savedAllowed = Dev.IsAllowed
				Dev.IsAllowed = function()
					return true
				end
				local okR, resR = pcall(Dev.Run, p, "reset")
				Dev.IsAllowed = savedAllowed
				K.advance(0.5)
				T.check(okR and DS().GetStore(p) ~= nil and DS().GetStore(p).Bought.Pro ~= nil and Store.Owns(p, "Cash2x") == true and Store.Owns(p, "PetXp2x") == true and Mult.State(p).PvE == 1.5,
					"store mult: /reset keeps Store.Bought.Pro and the pass answers", tostring(resR))
			end

			-- Double Rewards: the event doubles Tokens by itself; Multipliers has no Tokens factor and the pass stays x2 on Cash
			Battle.SetDoubleRewards(true)
			T.check(Battle.IsDoubleRewards() == true and Mult.Cash(p, 100, "Ring") == 200 and Mult.State(p).Tokens == nil, "store mult: Double Rewards on: Cash still x2 by the pass, Multipliers knows no Tokens factor (never Tokens x4)")
			Battle.SetDoubleRewards(nil)

			-- the five sites and the sites NOT multiplied, pinned in the sources (the Ring, the Dungeon and the tutorial need
			-- a whole run to reach: p4ring_rewards, p5dgn_loot and p2ui_tutorial run them at x1 in the gate)
			local bsSrc, dgSrc, tySrc, careSrc, tutSrc = sourceOf("server/Services/BattleService"), sourceOf("server/Services/DungeonService"), sourceOf("server/Services/TycoonService"), sourceOf("server/Services/PetCareService"), sourceOf("server/Services/TutorialService")
			T.check(#bsSrc > 0 and #dgSrc > 0 and #tySrc > 0 and #careSrc > 0 and #tutSrc > 0, "store mult: (precondition) the five sources are readable")
			T.check(tySrc:find('multipliers.Cash(player, paid, "Scoop")', 1, true) ~= nil and tySrc:find("dataService.AddCash(player, price)", 1, true) ~= nil, "store mult: TycoonService: the scoop credit goes through Multipliers.Cash(.., 'Scoop'); the home refund stays base")
			T.check(bsSrc:find('mult.Cash(player, cash, "Ring")', 1, true) ~= nil, "store mult: BattleService: the Ring Cash goes through Multipliers.Cash(.., 'Ring')")
			local fallback = bsSrc:match("local function grantXp%(player, keys, xp, source%)(.-)local function petName")
			T.check(type(fallback) == "string" and fallback:find('try(DS, "AddPetXp", player, key, xp)', 1, true) ~= nil and not fallback:find("Multipliers", 1, true) and not fallback:find("mult%.") , "store mult: BattleService's AddPetXp fallback hands the BASE xp to DataService (PetCareService's grantXp is the one XP site)")
			local tokensFn = bsSrc:match("local function grantTokens%(player, n%)(.-)\nend")
			T.check(type(tokensFn) == "string" and not tokensFn:find("Multipliers", 1, true) and not tokensFn:find("mult%."), "store mult: BattleService's Tokens never go through Multipliers (Double Rewards is the event's own doubling)")
			T.check(dgSrc:find('mult.Cash(m.Player, cash, "Dungeon")', 1, true) ~= nil and dgSrc:find('mult.Cash(m.Player, amount, "Chest")', 1, true) ~= nil, "store mult: DungeonService: the room and chest Cash go through Multipliers.Cash(.., 'Dungeon' / 'Chest')")
			T.check(select(2, dgSrc:gsub("mult%.Cash%(", "")) == 2 and select(2, bsSrc:gsub("mult%.Cash%(", "")) == 1 and select(2, tySrc:gsub("multipliers%.Cash%(", "")) == 1, "store mult: ...exactly four Cash sites (1 scoop, 1 Ring, 2 Dungeon)")
			T.check(careSrc:find("multipliers.PetXp(player, xp, source)", 1, true) ~= nil and select(2, careSrc:gsub("multipliers%.PetXp%(", "")) == 1, "store mult: PetCareService: ONE PetXp site, grantXp's first line")
			T.check(not tutSrc:find("Multipliers", 1, true), "store mult: TutorialService never multiplies (its home-chapter Cash and gift Tokens stay exact: p2ui_tutorial)")
			T.check(not tySrc:find("script.Parent:FindFirstChild(\"Multipliers\")", 1, true) and not bsSrc:find("FindFirstChild(\"Multipliers\")", 1, true) and not dgSrc:find("FindFirstChild(\"Multipliers\")", 1, true) and not careSrc:find("FindFirstChild(\"Multipliers\")", 1, true), "store mult: no lazy script.Parent lookup of Multipliers anywhere (Init deps only)")
		end)
		MPS.UserOwnsGamePassAsync = nil
		Battle.SetDoubleRewards(nil)
		restoreIds(saved.Ids)
		leaveAll(players)
		if not okRun then
			error(errRun, 0)
		end
	end)

	S.store_remote = guarded("store_remote", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local Store = SS()
		local folder = K.remoteFolder()
		local remote = folder and folder:FindFirstChild("StoreRequest")
		if not T.check(type(Store) == "table" and remote ~= nil, "store remote: StoreService and the StoreRequest remote exist") then
			return
		end
		local saved = { Ids = savedIds(), Studio = Mock.Options.Studio }
		local players = {}
		local prompts = {} -- { Kind, Player, Id }
		MPS.PromptGamePassPurchase = function(_, player, id)
			prompts[#prompts + 1] = { Kind = "Pass", Player = player, Id = id }
		end
		MPS.PromptProductPurchase = function(_, player, id)
			prompts[#prompts + 1] = { Kind = "Product", Player = player, Id = id }
		end
		MPS.UserOwnsGamePassAsync = function()
			return false
		end
		local Dev = DEV()
		local savedAllowed = Dev and Dev.IsAllowed
		local okRun, errRun = pcall(function()
			local errs0 = #Mock.Errors
			local p = join("Remote", newUserId())
			players[#players + 1] = p
			T.check(loaded(p), "store remote: (precondition) loaded")
			local tok0 = DS().GetTokens(p)
			local function send(...)
				Mock.FromClient(remote, p, ...)
			end
			send(nil)
			send(5)
			send({})
			send("Buy")
			send("Buy", 5)
			send("Buy", {})
			send("Sell", "Tokens1")
			K.advance(0.3)
			T.check(#prompts == 0 and #Mock.Errors == errs0, "store remote: junk on StoreRequest prompts nothing and raises nothing", tostring(#prompts) .. " prompts, " .. tostring(#Mock.Errors - errs0) .. " errors")
			setId("Tokens1", 6103)
			K.advance(1.1)
			for _ = 1, 10 do
				send("Buy", "Tokens1")
				K.advance(0.09)
			end
			K.advance(0.2)
			T.check(#prompts >= 1 and #prompts <= 2, "store remote: 10 Buy in a second = at most 2 prompts (1 req/s)", tostring(#prompts))
			local n = #prompts
			K.advance(1.1)
			p:SetAttribute(Config.Attr.InMatch, true)
			local mark = K.logSize()
			send("Buy", "Tokens1")
			K.advance(0.2)
			T.check(#prompts == n and toastCount(p, "The Store is closed during a match", mark) == 1, "store remote: in a match: the toast, no prompt", toastsSince(p, mark))
			p:SetAttribute(Config.Attr.InMatch, nil)
			K.advance(1.1)
			send("Buy", "Starter")
			K.advance(0.2)
			p:SetAttribute(Config.Attr.StorePreview, true)
			K.advance(1.1)
			send("Buy", "Starter")
			K.advance(0.2)
			T.eq(#prompts, n, "store remote: an Id 0 item is never prompted, preview or not")
			setId("VIP", 7101)
			ownPass(p, 7101)
			K.advance(1.1)
			send("Buy", "VIP")
			K.advance(0.2)
			T.eq(#prompts, n, "store remote: an owned pass key prompts nothing")
			setId("Starter", 6101)
			T.eq(DS().MarkBought(p, "Starter"), true, "store remote: (precondition) the Starter is bought")
			mark = K.logSize()
			K.advance(1.1)
			send("Buy", "Starter")
			K.advance(0.2)
			T.check(#prompts == n and toastCount(p, "You already have that!", mark) == 1, "store remote: a bought Once key: no prompt, 'You already have that!'", toastsSince(p, mark))
			setId("Cash2x", 7102)
			K.advance(1.1)
			send("Buy", "Cash2x")
			K.advance(0.2)
			T.check(#prompts == n + 1 and prompts[n + 1].Kind == "Pass" and prompts[n + 1].Id == 7102 and prompts[n + 1].Player == p, "store remote: a created pass key: PromptGamePassPurchase once", tostring(#prompts - n))
			K.advance(1.1)
			send("Buy", "Tokens1")
			K.advance(0.2)
			T.check(#prompts == n + 2 and prompts[n + 2].Kind == "Product" and prompts[n + 2].Id == 6103 and prompts[n + 2].Player == p, "store remote: a created product: PromptProductPurchase once", tostring(#prompts - n))
			T.eq(DS().GetTokens(p), tok0, "store remote: prompting grants nothing (Z1: only ProcessReceipt grants)")
			local okA, whyA = Store.PromptPurchase(p, "Nope")
			T.check(okA == false and type(whyA) == "string", "store remote: PromptPurchase refuses an unknown key", tostring(whyA))
			T.check(Store.PromptPurchase(nil, "Tokens1") == false and Store.PromptPurchase(p, 5) == false, "store remote: ...and no player / a junk key")
			T.eq(#prompts, n + 2, "store remote: ...with no prompt")
			T.eq(#Mock.Errors, errs0, "store remote: nothing raised")

			-- StorePreview: Studio or an allowed dev, set once at the join
			Mock.Options.Studio = false
			local devUid = newUserId()
			if Dev then
				Dev.IsAllowed = function(pl)
					return typeof(pl) == "Instance" and pl.UserId == devUid
				end
			end
			local dev = join("RemoteDev", devUid)
			players[#players + 1] = dev
			local plain = join("RemotePlain", newUserId())
			players[#players + 1] = plain
			T.check(dev:GetAttribute(Config.Attr.StorePreview) == true and Store.IsPreview(dev) == true, "store remote: StorePreview true for an allowed dev (DevService double)", tostring(dev:GetAttribute(Config.Attr.StorePreview)))
			T.check(plain:GetAttribute(Config.Attr.StorePreview) == false and Store.IsPreview(plain) == false, "store remote: ...false for a plain player outside Studio", tostring(plain:GetAttribute(Config.Attr.StorePreview)))
			Mock.Options.Studio = true
			local stu = join("RemoteStudio", newUserId())
			players[#players + 1] = stu
			T.check(stu:GetAttribute(Config.Attr.StorePreview) == true and Store.IsPreview(stu) == true, "store remote: ...true in Studio")
		end)
		if Dev then
			Dev.IsAllowed = savedAllowed
		end
		MPS.PromptGamePassPurchase = nil
		MPS.PromptProductPurchase = nil
		MPS.UserOwnsGamePassAsync = nil
		Mock.Options.Studio = saved.Studio
		restoreIds(saved.Ids)
		leaveAll(players)
		if not okRun then
			error(errRun, 0)
		end
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
