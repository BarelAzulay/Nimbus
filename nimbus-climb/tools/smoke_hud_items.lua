-- smoke_hud_items.lua: HUD cleanup, Task 3 (the owner's pick on the HUD cleanup pitch: slot 4 "C", items removed).
-- Loaded by tools/smoke.py in the server world and the client world:
--   huditems_gone        (server, booted) shared/ItemCatalog and server/Services/ItemService are gone, no BuyItem /
--                        UseItem remotes and no Config.Items; the item stall keeps its sculpt but has no prompt, is
--                        boarded up (Model Boards: two planks beside the mesh-tagged Stall model) and its sign says
--                        Closed; the roulette prompts are the only prompts of the shop; no NPC line names an item or
--                        the hotbar (<= 125 bytes, 3-5 lines), the Movement Trainer's keywords name the checkpoint
--   huditems_refund      (server, booted; DataStore mock seeded with v2 saves) the one-time B3ItemsRefund: 30 / 45 / 150
--                        Tokens per heal_cloud / shield_bubble / phoenix_feather, counts clamped to 5, unknown ids pay 0,
--                        Items cleared and the marker set, Migrated fired once, MigratedNow answers it, one "token" toast
--                        naming the amount; a second load pays nothing; an empty Items table sets the marker with no
--                        toast; a provisional (outage) load pays nothing until the recovery, which pays once and saves
--                        once; two servers refunding one save pay once (the twin merge); ProfileSync has no Items key
--   client_huditems_gone (client, 1920x1080) no NimbusHotbar, State has no Items / ItemCount (a stray Items key in a
--                        sync is dropped), the Pets window tabs are Pets + Team, the Shop tabs are Roulettes + Gems, an
--                        OpenPanel with Tab "Items" lands on Roulettes / Pets, the HP card sits above the hotbar's old
--                        footprint, keys 1-4 do nothing
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format
local REFUND = { heal_cloud = 30, shield_bubble = 45, phoenix_feather = 150 }

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function req(path)
		local inst = K.moduleInstance(path)
		local ok, m = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(m) == "table" and m or nil
	end
	local function find(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function storeKey(userId)
		return K.config().Tokens.DataStoreName .. "/u_" .. userId
	end
	local function store(userId, record)
		Mock.DataStore.Data[storeKey(userId)] = record
	end
	local function stored(userId)
		return Mock.DataStore.Data[storeKey(userId)]
	end
	local function tokenToasts(player, mark)
		local out = {}
		for _, e in ipairs(K.remotesFor("Notify", player.UserId, mark)) do
			if e.args[2] == "token" then
				out[#out + 1] = tostring(e.args[1])
			end
		end
		return out
	end
	local function join(name, userId)
		local p = Mock.AddPlayer(name, userId)
		K.advance(1)
		return p
	end

	S.huditems_gone = guarded("huditems_gone", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local RS = game:GetService("ReplicatedStorage")
		T.check(K.moduleInstance("shared/ItemCatalog") == nil and K.moduleInstance("server/Services/ItemService") == nil
			and K.moduleInstance("client/Controllers/HotbarController") == nil, "huditems: ItemCatalog, ItemService and HotbarController are gone")
		T.check(not T.contains(Config.Remotes, "BuyItem") and not T.contains(Config.Remotes, "UseItem") and Config.Items == nil,
			"huditems: no BuyItem / UseItem remotes in Config, no Config.Items")
		local folder = RS:FindFirstChild("Remotes")
		T.check(folder ~= nil and folder:FindFirstChild("BuyItem") == nil and folder:FindFirstChild("UseItem") == nil, "huditems: Remotes.Init made no BuyItem / UseItem remote")

		local info = K.W.lobbyInfo
		local stall = info and info.Shop and info.Shop.ItemShop
		if not T.check(type(stall) == "table" and stall.Model and stall.PromptPart and typeof(stall.Center) == "Vector3",
			"huditems: LobbyInfo.Shop.ItemShop keeps { PromptPart, Center, Model }") then
			return
		end
		local prompts = 0
		for _, d in ipairs(stall.Model:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				prompts = prompts + 1
			end
		end
		T.eq(prompts, 0, "huditems: the item stall has no prompt")
		local boards = stall.Model:FindFirstChild("Boards")
		local planks = 0
		for _, c in ipairs(boards and boards:GetChildren() or {}) do
			if c:IsA("BasePart") then
				planks = planks + 1
			end
		end
		T.check(boards ~= nil and boards:IsA("Model") and planks >= 2, "huditems: ...it is boarded up (Model Boards, two planks)", tostring(planks))
		local sculpt = stall.Model:FindFirstChild("Stall")
		T.check(boards ~= nil and boards.Parent == stall.Model and (sculpt == nil or not boards:IsDescendantOf(sculpt)),
			"huditems: ...the boards sit beside the mesh-tagged Stall, not inside it")
		local sub = find(stall.Model, "SubLabel")
		T.check(sub ~= nil and sub.Text == "Closed", "huditems: ...its sign says Closed", sub and sub.Text)
		local shopFolder = stall.Model.Parent
		local shopPrompts = 0
		for _, d in ipairs(shopFolder and shopFolder:GetDescendants() or {}) do
			if d:IsA("ProximityPrompt") then
				shopPrompts = shopPrompts + 1
			end
		end
		T.eq(shopPrompts, #Config.Roulettes, "huditems: PetService's roulette prompts are the only shop prompts")

		local NpcDialog = req("shared/NpcDialog")
		if T.check(NpcDialog and type(NpcDialog.Npcs) == "table", "huditems: NpcDialog loads") then
			local bad = {}
			for _, npc in ipairs(NpcDialog.Npcs) do
				for i, l in ipairs(npc.Lines) do
					if l:find("Heal Cloud", 1, true) or l:find("Phoenix Feather", 1, true) or l:find("Shield Bubble", 1, true) or l:lower():find("hotbar", 1, true)
						or l:find("items", 1, true) or #l > 125 then
						bad[#bad + 1] = npc.Id .. "#" .. i .. " (" .. #l .. ")"
					end
				end
				T.check(#npc.Lines >= 3 and #npc.Lines <= 5, "huditems: " .. npc.Id .. " keeps 3-5 lines", tostring(#npc.Lines))
				if npc.Title == "Movement Trainer" then
					T.check(T.contains(npc.Keywords, "checkpoint") and not T.contains(npc.Keywords, "Heal Cloud") and not T.contains(npc.Keywords, "1 to 4"),
						"huditems: the trainer's keywords name the checkpoint, not the items")
				end
				T.check(not T.contains(npc.Keywords, "Phoenix Feather") and not T.contains(npc.Keywords, "Heal Cloud"), "huditems: " .. npc.Id .. "'s keywords name no item")
			end
			T.check(#bad == 0, "huditems: no NPC line names an item or the hotbar, every line <= 125 bytes", table.concat(bad, ", "))
		end
		K.flushErrors("huditems_gone")
	end)

	S.huditems_refund = guarded("huditems_refund", function()
		if not K.needBoot() then
			return
		end
		local DS = req("server/Services/DataService")
		if not T.check(DS and type(DS.MigratedNow) == "function" and DS.Migrated, "huditems refund: DataService loads (MigratedNow, Migrated)") then
			return
		end
		local DSt = Mock.DataStore
		local UA, UB, UC, UD, UE = 952001, 952002, 952003, 952004, 952005
		local fired = {}
		local conn = DS.Migrated:Connect(function(p, name, info)
			if name == "B3ItemsRefund" then
				fired[#fired + 1] = { UserId = p.UserId, Info = info }
			end
		end)

		-- a v2 save with one of each (2 heal clouds): 2 * 30 + 45 + 150 = 255
		store(UA, { Version = 2, Tokens = 100, Pets = {}, Equipped = {}, Items = { heal_cloud = 2, shield_bubble = 1, phoenix_feather = 1 } })
		local mark = K.logSize()
		local a = join("RefundA", UA)
		local prof = DS.GetProfile(a)
		T.eq(prof and prof.Tokens, 100 + 2 * REFUND.heal_cloud + REFUND.shield_bubble + REFUND.phoenix_feather, "huditems refund: the refund pays 30 / 45 / 150 per item (255)")
		T.check(prof and next(prof.Items or {}) == nil and type(prof.Migrations) == "table" and prof.Migrations.B3ItemsRefund == true,
			"huditems refund: ...clears Items and sets the marker Migrations.B3ItemsRefund")
		T.eq(a:GetAttribute("CloudTokens"), 355, "huditems refund: ...and the CloudTokens attribute shows the new balance")
		local mine = {}
		for _, f in ipairs(fired) do
			if f.UserId == UA then
				mine[#mine + 1] = f.Info
			end
		end
		T.check(#mine == 1 and type(mine[1]) == "table" and mine[1].Tokens == 255 and type(mine[1].Items) == "table" and mine[1].Items.heal_cloud == 2,
			"huditems refund: ...Migrated('B3ItemsRefund') fired once with { Tokens = 255, Items }", tostring(#mine))
		local now = DS.MigratedNow(a, "B3ItemsRefund")
		T.check(now and now.Tokens == 255, "huditems refund: ...MigratedNow answers it this session")
		local toasts = tokenToasts(a, mark)
		T.check(#toasts == 1 and toasts[1]:find("+255 Tokens", 1, true) ~= nil and toasts[1]:find("Items are gone from Nimbus", 1, true) ~= nil,
			"huditems refund: ...one token toast names the amount", table.concat(toasts, " | "))
		local sync = K.lastRemote("ProfileSync", UA, mark)
		T.check(sync ~= nil and type(sync.args[1]) == "table" and sync.args[1].Items == nil, "huditems refund: ProfileSync carries no Items key")
		K.removePlayers({ a })
		K.advance(1)
		T.check(stored(UA) and stored(UA).Tokens == 355 and next(stored(UA).Items or {}) == nil and stored(UA).Migrations and stored(UA).Migrations.B3ItemsRefund == true,
			"huditems refund: the store holds 355 Tokens, no Items and the marker", stored(UA) and tostring(stored(UA).Tokens))
		mark = K.logSize()
		a = join("RefundA", UA)
		T.eq(DS.GetProfile(a).Tokens, 355, "huditems refund: a second load pays nothing more")
		T.eq(#tokenToasts(a, mark), 0, "huditems refund: ...and shows no toast")
		T.eq(DS.MigratedNow(a, "B3ItemsRefund"), nil, "huditems refund: ...MigratedNow is nil in that session")
		K.removePlayers({ a })

		-- clamp to 5, unknown ids pay 0
		store(UB, { Version = 2, Tokens = 0, Pets = {}, Equipped = {}, Items = { heal_cloud = 99, mystery_box = 3 } })
		local b = join("RefundB", UB)
		T.eq(DS.GetProfile(b).Tokens, 5 * REFUND.heal_cloud, "huditems refund: counts clamp to 5 per item and unknown ids pay 0")
		K.removePlayers({ b })

		-- an empty Items table: the marker, no toast, no signal
		store(UC, { Version = 2, Tokens = 10, Pets = {}, Equipped = {}, Items = {} })
		local n0 = #fired
		mark = K.logSize()
		local c = join("RefundC", UC)
		T.check(DS.GetProfile(c).Migrations.B3ItemsRefund == true and DS.GetProfile(c).Tokens == 10 and #tokenToasts(c, mark) == 0 and #fired == n0,
			"huditems refund: an empty Items table: marker set, no toast, no signal")
		K.removePlayers({ c })

		-- provisional: an outage load pays nothing; the recovery pays once and saves once
		store(UD, { Version = 2, Tokens = 0, Pets = {}, Equipped = {}, Items = { phoenix_feather = 1 } })
		DSt.Fail = true
		mark = K.logSize()
		local d = join("RefundD", UD)
		K.advance(1)
		T.check(DS.IsProvisional(d) == true and DS.GetProfile(d).Tokens == 0 and #tokenToasts(d, mark) == 0, "huditems refund: a provisional profile waits (no refund yet)")
		DSt.Fail = false
		local recovered = K.waitFor(function()
			return not DS.IsProvisional(d)
		end, 40)
		K.advance(1)
		T.check(recovered and DS.GetProfile(d).Tokens == REFUND.phoenix_feather, "huditems refund: ...the recovered profile is paid once", tostring(DS.GetProfile(d).Tokens))
		T.eq(#tokenToasts(d, mark), 1, "huditems refund: ...with one toast")
		K.removePlayers({ d })
		K.advance(1)
		T.eq(stored(UD) and stored(UD).Tokens, REFUND.phoenix_feather, "huditems refund: ...and saved once")
		T.check(stored(UD) and next(stored(UD).Items or {}) == nil, "huditems refund: ...with Items cleared in the store")

		-- the twin: another server refunded the same save first (its marker and balance are in the store when this
		-- session saves): this session's own refund is left out of the merge, so the save is paid once
		store(UE, { Version = 2, Tokens = 20, Pets = {}, Equipped = {}, Items = { shield_bubble = 2 } })
		local e = join("RefundE", UE)
		T.eq(DS.GetProfile(e).Tokens, 20 + 2 * REFUND.shield_bubble, "huditems refund: twin: this session refunded (110)")
		local other = stored(UE)
		other.Tokens = 20 + 2 * REFUND.shield_bubble + 7 -- the other server's refund + 7 Tokens earned there
		other.Items = {}
		other.Migrations = other.Migrations or {}
		other.Migrations.B3ItemsRefund = true
		DS.AddTokens(e, 5)
		K.removePlayers({ e })
		K.advance(1)
		T.eq(stored(UE) and stored(UE).Tokens, 20 + 2 * REFUND.shield_bubble + 7 + 5, "huditems refund: twin: two servers refunding one save pay once (117 + 5)")
		conn:Disconnect()
		K.flushErrors("huditems_refund")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local LocalPlayer = Players.LocalPlayer
	local H = {}

	function H.req(path)
		local root, rest = path:match("^(%a+)/(.+)$")
		local inst = Mock.GetPath(ROOTS[root] .. "/" .. rest)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end
	function H.mod(name)
		if KC.M and KC.M[name] then
			return KC.M[name]
		end
		return H.req("client/Controllers/" .. name)
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.menu()
		return H.pg():FindFirstChild("NimbusMenu")
	end
	function H.find(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	function H.snapshot(over)
		local snap = {
			Tokens = 900,
			Pets = { biscuit_bear = 1, pebble_pup = 1 },
			Equipped = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = { biscuit_bear = true, pebble_pup = true },
			IndexClaimed = {},
			Tutorial = { Step = 1000, Done = true, Gifted = true },
			Cash = 0, Gems = 0,
			Home = { Level = 5, Prestige = 0, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = {}, Hybrids = {},
			PetLevels = { biscuit_bear = { Level = 4, Xp = 0 }, pebble_pup = { Level = 2, Xp = 0 } },
			Teams = { Presets = { { "biscuit_bear" }, {}, {} }, Active = 1, Slots = 3 },
			Battle = { Trophies = 0, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
			PetGrowth = {},
			Ring = { Best = 0, Runs = 0 },
		}
		for k, v in pairs(over or {}) do
			snap[k] = v
		end
		return snap
	end
	local function press(keyName)
		Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput(keyName, "Keyboard", "Begin"), false)
		Mock.FireSignal(UserInputService, "InputEnded", Mock.NewInput(keyName, "Keyboard", "End"), false)
	end

	S.client_huditems_gone = guarded("client_huditems_gone", function()
		local Config = KC.env()
		local MC = H.mod("MenuController")
		local State = H.req("client/State")
		if not T.check(type(MC) == "table" and type(MC.Open) == "function" and type(State) == "table", "huditems client: MenuController and State load") then
			return
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		pcall(MC.Close)
		KC.advance(0.5)

		T.check(H.pg():FindFirstChild("NimbusHotbar") == nil, "huditems client: no NimbusHotbar ScreenGui")
		T.check(H.mod("HotbarController") == nil, "huditems client: no HotbarController module")
		KC.toClient("ProfileSync", H.snapshot())
		KC.advance(0.3)
		T.check(State.Get().Items == nil and State.ItemCount == nil, "huditems client: State has no Items / ItemCount")
		KC.toClient("ProfileSync", H.snapshot({ Items = { heal_cloud = 2 } }))
		KC.advance(0.3)
		T.check(State.Get().Items == nil, "huditems client: a stray Items key in a sync is dropped")

		MC.Open("Pets", {})
		KC.advance(0.5)
		local inv = H.menu() and H.menu():FindFirstChild("Window_Inventory")
		T.check(inv ~= nil and H.find(inv, "Tab_Items") == nil and H.find(inv, "Page_Items") == nil and H.find(inv, "Tab_Team") ~= nil and H.find(inv, "Tab_Pets") ~= nil,
			"huditems client: the Pets window tabs are Pets + Team")
		MC.Open("Shop", {})
		KC.advance(0.5)
		local shop = H.menu() and H.menu():FindFirstChild("Window_Shop")
		T.check(shop ~= nil and H.find(shop, "Tab_Items") == nil and H.find(shop, "Page_Items") == nil and H.find(shop, "Tab_Roulettes") ~= nil and H.find(shop, "Tab_Gems") ~= nil,
			"huditems client: the Shop tabs are Roulettes + Gems")
		KC.toClient("OpenPanel", "Shop", { Tab = "Items" })
		KC.advance(0.5)
		local pr = H.find(shop, "Page_Roulettes")
		T.check(pr ~= nil and pr.Visible and KC.isShown(shop), "huditems client: OpenPanel('Shop', { Tab = 'Items' }) lands on Roulettes")
		KC.toClient("OpenPanel", "Inventory", { Tab = "Items" })
		KC.advance(0.5)
		local pp = H.find(inv, "Page_Pets")
		T.check(pp ~= nil and pp.Visible and KC.isShown(inv), "huditems client: OpenPanel('Inventory', { Tab = 'Items' }) lands on Pets")
		MC.Open("items", {})
		KC.advance(0.5)
		T.check(pp ~= nil and pp.Visible and KC.isShown(inv), "huditems client: Open('items') opens the Pets window on Pets")
		pcall(MC.Close)
		KC.advance(0.5)

		-- the vitals card: the bottom-centre slot it had above the hotbar, with nothing below it now
		local hud = H.pg():FindFirstChild("NimbusHud")
		local vit = hud and H.find(hud, "Vitals")
		if T.check(vit ~= nil, "huditems client: the HUD has its vitals card") then
			local bottom = vit.AbsolutePosition.Y + vit.AbsoluteSize.Y
			T.check(bottom <= Mock.Viewport.Y - 78, "huditems client: the HP card sits above the hotbar's old footprint (HOTBAR_FALLBACK)", fmt("bottom %.0f of %d", bottom, Mock.Viewport.Y))
		end

		local errs0 = #Mock.Errors
		local mark = #Mock.RemoteLog
		LocalPlayer:SetAttribute(Config.Attr.InMatch, true)
		KC.advance(0.2)
		for _, key in ipairs({ "One", "Two", "Three", "Four" }) do
			press(key)
			KC.advance(0.2)
		end
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		KC.advance(0.2)
		T.eq(#KC.serverCalls("UseItem", mark), 0, "huditems client: keys 1-4 in a match send nothing")
		T.eq(#Mock.Errors, errs0, "huditems client: ...and raise nothing")
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.5)
		KC.flushErrors("client_huditems_gone")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
