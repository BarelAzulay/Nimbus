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

	return S
end

----------------------------------------------------------------------------------------------------
-- client world
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
