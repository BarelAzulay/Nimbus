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
