-- smoke_store_ui.lua: the Robux Store window (store plan Task 7, W1-store-ui; docs/superpowers/specs/2026-11-04-shop-retention-design.md
-- 5.1 / 8 / 13b). Loaded by tools/smoke.py in the client and phone worlds only (client_files):
-- (lobby-shop Task 21: the Store is the one Shop window now, ShopController behind the StoreController forwarder; these
-- scenarios keep their names and pin the Store's rules inside it: NimbusShop / ShopWindow, five rail tabs always shown.)
--   client_store_window  (1920x1080) the pill opens the Shop (NimbusShop, order 19), not the Cloud Shop; 1540x910;
--                        WindowOpened("Store"); every Id 0 = the five tabs + "The Shop opens soon!" on Packs; created
--                        Robux items = cards (a token pack is a Gems-tab tile); the Starter hero; "..." until
--                        GetProductInfo answers (the retry after 10 s), then the Robux glyph (or R$) + 99; literal Gets-you
--                        lines; Buy -> StoreRequest("Buy", key), never a prompt; Tab_Eggs -> the Cloud Shop; its Gems tab
--                        has one Robux Store button (no pack cards) -> the Shop's Gems tab; ShopOpened only from the Cloud
--                        Shop; refused in a match
--   client_store_states  Owned / Claimed / HaveIt (x2 Pet XP forever, a full potion bank) / Active ("58 m left") / Preview
--                        (StorePreview: Id 0 renders, PREVIEW disabled, prompts nothing; without the flag it hides)
--   client_store_shine   High: the hero's HeroSpin gradient turns, the Starter card turns its pet in a viewport; Low:
--                        static, no viewport, no tween; no tween under NimbusShop after Close; sounds StorePop (Click)
--                        on a card tap, StoreBuy (Reward) on the "Thank you" toast
--   client_store_bridge  OpenPanel("Store", { Tab = "Passes" }) opens once on Passes; a second pill tap, Esc and
--                        MenuController.Close() close it; the top bar still answers; Store / Pets / menu windows never overlap
--   client_store_mobile  (phone world, 844x390) 820x330 at scale 1, texts >= 15 px, tabs 104x48, Buy 150x48, touch
--                        controls off while open and back after, the Store adds no text to the middle of the screen
-- Every scenario restores the Config ids, the attributes, the doubles and the swapped functions it touched.
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format

local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local GuiService = game:GetService("GuiService")
	local UIS = game:GetService("UserInputService")
	local MPS = game:GetService("MarketplaceService")
	local LocalPlayer = Players.LocalPlayer
	local H = {}

	-- a module of the client build (the H.moduleAt shape of smoke_evo_retreat.lua; ROOTS is smoke.py's)
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
	function H.setAttr(name, v)
		LocalPlayer:SetAttribute(name, v)
	end
	function H.findItem(key)
		local Config = KC.env()
		for _, it in ipairs(Config.Store.Items) do
			if it.Key == key then
				return it
			end
		end
		return nil
	end
	function H.setId(key, id)
		local it = H.findItem(key)
		if it then
			it.Id = id
		end
	end
	function H.hintText()
		local menu = H.pg():FindFirstChild("NimbusMenu")
		local hint = menu and menu:FindFirstChild("MenuHint")
		local text = hint and hint:FindFirstChild("Text")
		return (hint and hint.Visible and text) and tostring(text.Text) or ""
	end
	function H.win()
		local gui = H.pg():FindFirstChild("NimbusShop")
		return gui and gui:FindFirstChild("ShopWindow", true)
	end
	function H.pressPill(name)
		local bar = H.pg():FindFirstChild("NimbusTopBar")
		local button = bar and bar:FindFirstChild("PillButton_" .. name, true)
		if button then
			Mock.Click(button)
		end
		KC.advance(0.4)
		return button ~= nil
	end
	function H.tabCount(win)
		local n = 0
		for _, d in ipairs(win:GetDescendants()) do
			if d:IsA("TextButton") and d.Name:sub(1, 4) == "Tab_" and d.Visible then
				n = n + 1
			end
		end
		return n
	end
	function H.cardCount(win)
		local n = 0
		for _, d in ipairs(win:GetDescendants()) do
			if d:IsA("GuiObject") and d.Name:sub(1, 5) == "Card_" then
				n = n + 1
			end
		end
		return n
	end
	function H.card(win, key)
		return win and win:FindFirstChild("Card_" .. key, true)
	end
	function H.heroKey(win)
		for _, d in ipairs(win:GetDescendants()) do
			if d:IsA("GuiObject") and d.Name:sub(1, 5) == "Card_" and d:GetAttribute("Hero") == true and H.shownIn(d) then
				return d:GetAttribute("Key")
			end
		end
		return nil
	end
	function H.cardLines(win, key)
		local out = {}
		local card = H.card(win, key)
		local i = 1
		while card and card:FindFirstChild("Line" .. i, true) do
			out[i] = card:FindFirstChild("Line" .. i, true).Text
			i = i + 1
		end
		return out
	end
	function H.cardText(win, key)
		local parts = {}
		local card = H.card(win, key)
		for _, d in ipairs(card and card:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
				parts[#parts + 1] = tostring(d.Text)
			end
		end
		return table.concat(parts, " | ")
	end
	function H.bodyText(win)
		local parts = {}
		for _, d in ipairs(win:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and H.shownIn(d) and tostring(d.Text) ~= "" then
				parts[#parts + 1] = tostring(d.Text)
			end
		end
		return table.concat(parts, " | ")
	end
	function H.buyButton(win, key)
		local card = H.card(win, key)
		return card and card:FindFirstChild("Buy", true)
	end
	function H.tapBuy(win, key)
		local b = H.buyButton(win, key)
		if b then
			Mock.Click(b)
		end
		KC.advance(0.2)
	end
	function H.tapTab(win, name)
		local b = win and win:FindFirstChild("Tab_" .. name, true)
		if b then
			Mock.Click(b)
		end
		KC.advance(0.4)
	end
	function H.activeTab(win)
		for _, d in ipairs(win:GetDescendants()) do
			if d:IsA("TextButton") and d.Name:sub(1, 4) == "Tab_" and d:GetAttribute("Selected") == true then
				return d.Name:sub(5)
			end
		end
		return nil
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
	-- live tweens whose target is under the NimbusShop gui
	function H.storeTweens()
		local gui = H.pg():FindFirstChild("NimbusShop")
		local n = 0
		for tw in pairs(Mock.ActiveTweens) do
			local ok, target = pcall(function()
				return tw.Instance
			end)
			if ok and target and gui and target:IsDescendantOf(gui) then
				n = n + 1
			end
		end
		return n
	end
	function H.near(a, b)
		return math.abs(a - b) < 2
	end

	-- every scenario starts from the same place and puts everything back (Config ids, attributes, doubles)
	function H.begin()
		local Config = KC.env()
		local saved = { Ids = {}, Gems = {}, Attrs = {}, Viewport = { Mock.Viewport.X, Mock.Viewport.Y } }
		for _, it in ipairs(Config.Store.Items) do
			saved.Ids[it.Key] = it.Id
		end
		for i, p in ipairs(Config.Gems.Products) do
			saved.Gems[i] = p.Id
		end
		for _, name in ipairs({ "InMatch", "OwnedPasses", "StoreBought", "XpBoostEnds", "StorePreview", "PaidRandomItemsRestricted" }) do
			saved.Attrs[name] = LocalPlayer:GetAttribute(name)
		end
		H.setAttr("InMatch", false)
		H.setAttr("PaidRandomItemsRestricted", false) -- (lobby-shop 16.1: the token packs are buyable on an allowed account)
		H.setAttr("OwnedPasses", "")
		H.setAttr("StoreBought", "")
		H.setAttr("XpBoostEnds", 0)
		H.setAttr("StorePreview", nil)
		for _, it in ipairs(Config.Store.Items) do
			it.Id = 0
		end
		for _, p in ipairs(Config.Gems.Products) do
			p.Id = 0
		end
		saved.Prompts = 0
		MPS.PromptProductPurchase = function()
			saved.Prompts = saved.Prompts + 1
		end
		MPS.PromptGamePassPurchase = function()
			saved.Prompts = saved.Prompts + 1
		end
		local MC = H.ctrl("MenuController")
		local SC = H.ctrl("StoreController")
		if SC then
			SC.Close()
		end
		if MC then
			MC.Close()
		end
		-- a fresh session: the Shop's first open shows Packs (lobby-shop Task 21)
		local Shop = H.ctrl("ShopController")
		if Shop and type(Shop._S) == "table" then
			Shop._S.Tab = nil
		end
		saved.Opened = {}
		if MC and MC.WindowOpened then
			saved.Conn = MC.WindowOpened:Connect(function(id)
				saved.Opened[#saved.Opened + 1] = id
			end)
		end
		KC.advance(0.6)
		return saved
	end
	function H.finish(saved)
		local Config = KC.env()
		local SC = H.ctrl("StoreController")
		local MC = H.ctrl("MenuController")
		if SC then
			SC.Close()
		end
		if MC then
			MC.Close()
		end
		for _, it in ipairs(Config.Store.Items) do
			it.Id = saved.Ids[it.Key] or 0
		end
		for i, p in ipairs(Config.Gems.Products) do
			p.Id = saved.Gems[i] or 0
		end
		for name, v in pairs(saved.Attrs) do
			H.setAttr(name, v)
		end
		for _, name in ipairs({ "InMatch", "OwnedPasses", "StoreBought", "XpBoostEnds", "StorePreview", "PaidRandomItemsRestricted" }) do
			if saved.Attrs[name] == nil then
				H.setAttr(name, nil)
			end
		end
		MPS.PromptProductPurchase = nil
		MPS.PromptGamePassPurchase = nil
		MPS.GetProductInfo = nil
		if saved.Conn then
			saved.Conn:Disconnect()
		end
		Mock.SetViewport(saved.Viewport[1], saved.Viewport[2])
		KC.advance(0.6)
	end
	function H.last(list)
		return list[#list]
	end
	function H.count(list, value, from)
		local n = 0
		for i = (from or 0) + 1, #list do
			if list[i] == value then
				n = n + 1
			end
		end
		return n
	end

	S.client_store_window = guarded("client_store_window", function()
		local SC = H.ctrl("StoreController")
		local MC = H.ctrl("MenuController")
		local TC = H.ctrl("TutorialController")
		local Steps = H.moduleAt("shared", "TutorialSteps")
		if not T.check(type(SC) == "table" and type(SC.Open) == "function" and type(SC.Cards) == "function" and type(SC.RobuxGlyph) == "function",
			"store window: StoreController loads (Open, Close, IsOpen, Cards, Layout, RobuxGlyph)") then
			return
		end
		local saved = H.begin()
		Mock.SetViewport(1920, 1080)
		KC.advance(0.5)
		H.pressPill("Shop")
		local gui = H.pg():FindFirstChild("NimbusShop")
		T.check(SC.IsOpen() and gui ~= nil and gui.DisplayOrder == 19 and gui.IgnoreGuiInset == true and not MC.IsOpen(),
			"store window: the pill opens the Shop (NimbusShop, order 19), not the Cloud Shop", tostring(SC.IsOpen()) .. " / menu " .. tostring(MC.IsOpen()))
		local win = H.win()
		if not T.check(win ~= nil, "store window: the ShopWindow frame exists") then
			H.finish(saved)
			return
		end
		T.check(H.near(win.AbsoluteSize.X, 1540) and H.near(win.AbsoluteSize.Y, 910) and SC.Layout() == "PC", "store window: 1540x910 at 1080p (PC)",
			fmt("%.0fx%.0f %s", win.AbsoluteSize.X, win.AbsoluteSize.Y, tostring(SC.Layout())))
		T.eq(H.last(saved.Opened), "Store", "store window: fires MenuController.WindowOpened(\"Store\")")
		T.check(H.bodyText(win):find("The Shop opens soon!", 1, true) ~= nil and H.tabCount(win) == 5 and H.activeTab(win) == "Packs",
			"store window: the five rail tabs always show; with every Id 0 and no preview the Packs page says the Shop opens soon", H.tabCount(win) .. " tabs: " .. H.bodyText(win))
		H.setId("Starter", 5001)
		H.setId("VIP", 5002)
		H.setId("Tokens1", 5003)
		SC.Close()
		KC.advance(0.2)
		H.pressPill("Shop")
		local cards = SC.Cards()
		T.check(H.tabCount(win) == 5 and H.cardCount(win) == 2 and cards.Starter ~= nil and cards.Starter.State == "Buy" and cards.Starter.Tab == "Packs"
			and cards.Tokens1 ~= nil and cards.Tokens1.Tab == "Gems" and win:FindFirstChild("TokenPack_1", true) ~= nil,
			"store window: card count = created Robux items (Packs, Passes); the token pack is a Gems-tab tile", H.tabCount(win) .. " tabs, " .. H.cardCount(win) .. " cards")
		T.eq(H.heroKey(win), "Starter", "store window: the hero is the Starter while unbought and created")
		T.eq(H.activeTab(win), "Packs", "store window: it re-opens on the last tab (Packs, the first open's)")
		T.eq(cards.Starter and cards.Starter.Price, "...", "store window: \"...\" until the price arrives")
		MPS.GetProductInfo = function(_, id)
			return { PriceInRobux = (id == 5001) and 99 or 399 }
		end
		KC.advance(11)
		local price = SC.Cards().Starter and SC.Cards().Starter.Price
		T.check(price == SC.RobuxGlyph() .. "99" and (SC.RobuxGlyph() == "\238\128\130" or SC.RobuxGlyph() == "R$"),
			"store window: the retry after 10 s shows the price as the Robux glyph (or its R$ fallback) + 99", tostring(price))
		local lines = H.cardLines(win, "Starter")
		T.check(lines[1] == "1x Storm Tabby (Lv 5)" and lines[2] == "$1,000 Cash" and lines[3] == "1 h x2 Pet XP", "store window: literal Gets-you lines, no ribbon",
			table.concat(lines, " / "))
		local mark = #Mock.RemoteLog
		H.tapBuy(win, "Starter")
		local sent = KC.serverCalls("StoreRequest", mark)
		T.check(#sent == 1 and sent[1].args[1] == "Buy" and sent[1].args[2] == "Starter" and saved.Prompts == 0,
			"store window: Buy -> StoreRequest(\"Buy\", key); the client never prompts", #sent .. " sends, " .. saved.Prompts .. " prompts")
		H.tapBuy(win, "Starter")
		T.eq(#KC.serverCalls("StoreRequest", mark), 1, "store window: a second Buy inside 1 s sends nothing")
		H.tapTab(win, "Eggs")
		T.check(not SC.IsOpen() and MC.IsOpen() and H.last(saved.Opened) == "Shop", "store window: the Eggs tab closes the Shop and opens the Cloud Shop (lobby-shop Task 21 step)",
			tostring(SC.IsOpen()) .. " / " .. tostring(H.last(saved.Opened)))
		local menu = H.pg():FindFirstChild("NimbusMenu")
		local getGems = menu and menu:FindFirstChild("RobuxStore", true)
		T.check(getGems ~= nil and menu:FindFirstChild("Pack_1", true) == nil and menu:FindFirstChild("PacksSoon", true) == nil,
			"store window: the Gems tab has the Robux Store button and no pack cards")
		-- the tutorial's shop step waits for ShopOpened: only the Cloud Shop sends it
		local tutSaved = TC and type(TC.GetState) == "function" and TC.GetState() or nil
		local index = nil
		for i, st in ipairs(Steps and Steps.Steps or {}) do
			if st.Id == "shop" then
				index = i
			end
		end
		if index then
			local step = Steps.Steps[index]
			KC.toClient("TutorialState", {
				Step = index, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = tostring(step.Text), Target = step.Target,
				CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, AlsoNext = step.AlsoNext == true,
				Chapter = step.Chapter, Done = false, Completed = false, Skipped = false, Reward = 0,
			})
			KC.advance(0.8)
		end
		local tutMark = #Mock.RemoteLog
		if getGems then
			Mock.Click(getGems)
		end
		KC.advance(0.5)
		T.check(SC.IsOpen() and H.activeTab(win) == "Gems" and not MC.IsOpen(), "store window: Robux Store ({ Tab = \"Currency\" }) -> the Shop's Gems tab",
			tostring(SC.IsOpen()) .. " / " .. tostring(H.activeTab(win)) .. " / menu " .. tostring(MC.IsOpen()))
		T.eq(H.calls("TutorialEvent", tutMark, "ShopOpened"), 0, "store window: opening the Store never sends ShopOpened")
		MC.Open("Shop")
		KC.advance(0.6)
		T.check(H.calls("TutorialEvent", tutMark, "ShopOpened") == (index and 1 or 0) and index ~= nil and not SC.IsOpen(),
			"store window: the Cloud Shop still sends ShopOpened and closes the Store", H.calls("TutorialEvent", tutMark, "ShopOpened") .. " sent")
		if tutSaved then
			KC.toClient("TutorialState", tutSaved)
		else
			KC.toClient("TutorialState", { Done = true, Step = #Steps.Steps, Total = #Steps.Steps })
		end
		MC.Close()
		KC.advance(0.6)
		H.setAttr("InMatch", true)
		KC.advance(0.2)
		H.pressPill("Shop")
		T.check(not SC.IsOpen() and H.hintText():find("closed during a match", 1, true) ~= nil, "store window: refused in a match", H.hintText())
		SC.Open()
		KC.advance(0.2)
		T.check(not SC.IsOpen(), "store window: Open() itself is refused in a match")
		H.setAttr("InMatch", false)
		KC.advance(0.6)
		H.pressPill("Shop")
		H.setAttr("InMatch", true)
		KC.advance(0.2)
		T.check(not SC.IsOpen(), "store window: a match starting closes the Store")
		H.setAttr("InMatch", false)
		H.finish(saved)
		KC.flushErrors("client_store_window")
	end)

	S.client_store_states = guarded("client_store_states", function()
		local SC = H.ctrl("StoreController")
		if not T.check(type(SC) == "table" and type(SC.Cards) == "function", "store states: StoreController loads") then
			return
		end
		local saved = H.begin()
		Mock.SetViewport(1920, 1080)
		local function open()
			SC.Close()
			SC.Open()
			KC.advance(0.4)
		end
		local function refresh()
			KC.advance(0.3)
		end
		H.setId("Starter", 5001)
		H.setId("VIP", 5002)
		H.setAttr("OwnedPasses", "VIP,PetXp2x")
		H.setAttr("StoreBought", "Starter")
		H.setAttr("XpBoostEnds", 0)
		H.setId("XpPotion1", 5004)
		H.setId("PetXp2x", 5005)
		open()
		SC.Open({ Tab = "Passes" }) -- (the Shop opens on its last tab: the hero shows on its own tab, VIP's Passes)
		KC.advance(0.4)
		local win = H.win()
		local c = SC.Cards()
		T.check(c.VIP and c.VIP.State == "Owned" and c.Starter and c.Starter.State == "Claimed" and c.XpPotion1 and c.XpPotion1.State == "HaveIt" and H.heroKey(win) == "VIP",
			"store states: Owned / Claimed! / Have-it (x2 Pet XP forever); the hero moves to VIP once the Starter is bought",
			fmt("%s %s %s hero %s", tostring(c.VIP and c.VIP.State), tostring(c.Starter and c.Starter.State), tostring(c.XpPotion1 and c.XpPotion1.State), tostring(H.heroKey(win))))
		T.check(H.buyButton(win, "VIP").Text == "Owned" and H.buyButton(win, "Starter").Text == "Claimed!" and H.buyButton(win, "VIP"):GetAttribute("Disabled") == true,
			"store states: Owned / Claimed! read on the Buy button, disabled")
		T.check(H.cardText(win, "XpPotion1"):find("You already have x2 Pet XP forever!", 1, true) ~= nil and H.buyButton(win, "XpPotion1"):GetAttribute("Disabled") == true,
			"store states: the potion card says you already have x2 Pet XP forever, dimmed", H.cardText(win, "XpPotion1"))
		H.setAttr("OwnedPasses", "")
		H.setAttr("XpBoostEnds", os.time() + 58 * 60)
		refresh()
		c = SC.Cards()
		T.check(c.XpPotion1.State == "Active" and H.cardText(win, "XpPotion1"):find("58 m left", 1, true) ~= nil and H.buyButton(win, "XpPotion1"):GetAttribute("Disabled") ~= true,
			"store states: Active with the time left (still buyable: potions stack in time)", H.cardText(win, "XpPotion1"))
		T.eq(c.VIP.State, "Buy", "store states: a pass not in OwnedPasses is Buy again")
		H.setAttr("XpBoostEnds", os.time() + 7 * 86400 + 5)
		refresh()
		c = SC.Cards()
		T.check(c.XpPotion1.State == "HaveIt" and H.cardText(win, "XpPotion1"):find("Your potion is full!", 1, true) ~= nil, "store states: a full potion bank dims the card",
			H.cardText(win, "XpPotion1"))
		H.setAttr("StorePreview", true)
		H.setId("Pro", 0)
		refresh()
		c = SC.Cards()
		local proBuy = H.buyButton(win, "Pro")
		T.check(c.Pro ~= nil and c.Pro.State == "Preview" and proBuy ~= nil and proBuy.Text == "PREVIEW" and proBuy:GetAttribute("Disabled") == true and H.tabCount(win) == 5,
			"store states: under StorePreview every item renders, Id 0 included, PREVIEW disabled", H.tabCount(win) .. " tabs")
		T.check(c.Gems2 ~= nil and c.Gems2.State == "Preview" and c.Tokens3 ~= nil and c.Cash1 == nil, "store states: the preview lists the gem packs too, never a disabled Cash pack")
		local mark = #Mock.RemoteLog
		H.tapBuy(win, "Pro")
		T.eq(H.calls("StoreRequest", mark, "Buy", "Pro"), 0, "store states: PREVIEW prompts nothing")
		T.eq(saved.Prompts, 0, "store states: ...and the client never prompts")
		H.setAttr("StorePreview", nil)
		refresh()
		T.check(SC.Cards().Pro == nil, "store states: without the flag Id 0 hides as before")
		H.finish(saved)
		KC.flushErrors("client_store_states")
	end)

	S.client_store_shine = guarded("client_store_shine", function()
		local SC = H.ctrl("StoreController")
		local GQ = H.moduleAt("client", "GraphicsQuality")
		local SFX = H.moduleAt("client", "SoundFx")
		if not T.check(type(SC) == "table" and type(GQ) == "table" and type(SFX) == "table", "store shine: StoreController, GraphicsQuality, SoundFx load") then
			return
		end
		local saved = H.begin()
		Mock.SetViewport(1920, 1080)
		local realEffective, realPlay = GQ.Effective, SFX.Play
		local sounds = {}
		SFX.Play = function(name)
			sounds[#sounds + 1] = name
			return nil
		end
		H.setId("Starter", 5001)
		GQ.Effective = function()
			return "High"
		end
		SC.Open({ Tab = "Packs" })
		KC.advance(0.5)
		local win = H.win()
		local hero = H.card(win, "Starter")
		local grad = hero and hero:FindFirstChild("HeroSpin", true)
		local r0 = grad and grad.Rotation
		KC.advance(1)
		T.check(grad ~= nil and grad:IsA("UIGradient") and grad.Rotation ~= r0, "store shine: High: the hero's gradient turns",
			tostring(r0) .. " -> " .. tostring(grad and grad.Rotation))
		T.check(hero ~= nil and hero:FindFirstChildWhichIsA("ViewportFrame", true) ~= nil, "store shine: High: the Starter card turns its pet in a viewport")
		KC.advance(3)
		T.check(hero ~= nil and hero:FindFirstChild("Sheen", true) ~= nil and hero:FindFirstChild("Pulse", true) ~= nil, "store shine: High: the sheen and the Buy pulse are there")
		SC.Close()
		KC.advance(0.5)
		T.eq(H.storeTweens(), 0, "store shine: no tween under NimbusShop after Close")
		T.check(hero:FindFirstChild("HeroSpin", true) == nil and hero:FindFirstChildWhichIsA("ViewportFrame", true) == nil, "store shine: the shine is torn down on close")
		GQ.Effective = function()
			return "Low"
		end
		SC.Open()
		KC.advance(0.6)
		grad = hero:FindFirstChild("HeroSpin", true)
		r0 = grad and grad.Rotation
		KC.advance(1)
		T.check(grad ~= nil and grad.Rotation == r0, "store shine: Low: a static gradient", tostring(r0) .. " -> " .. tostring(grad and grad.Rotation))
		T.check(hero:FindFirstChildWhichIsA("ViewportFrame", true) == nil and H.storeTweens() == 0, "store shine: Low: no viewport, no tween", H.storeTweens() .. " tweens")
		KC.advance(3)
		T.eq(H.storeTweens(), 0, "store shine: Low: still no tween after the pulse time")
		-- sounds (spec 5.1)
		local from = #sounds
		Mock.Click(hero)
		KC.advance(0.2)
		local pop = SFX.Id("Sfx", "StorePop") and "StorePop" or "Click"
		T.eq(H.count(sounds, pop, from), 1, "store shine: a card tap plays " .. pop)
		from = #sounds
		KC.toClient("Notify", "Thank you! Your Starter Pack is here.", "good", 4)
		KC.advance(0.3)
		local buy = SFX.Id("Sfx", "StoreBuy") and "StoreBuy" or "Reward"
		T.check(H.count(sounds, buy, from) >= 1, "store shine: the Thank you toast plays " .. buy, table.concat(sounds, ",", from + 1))
		from = #sounds
		KC.toClient("Notify", "Something else happened.", "info", 4)
		KC.advance(0.3)
		T.eq(H.count(sounds, "StoreBuy", from), 0, "store shine: another toast plays no StoreBuy")
		GQ.Effective = realEffective
		SFX.Play = realPlay
		H.finish(saved)
		KC.flushErrors("client_store_shine")
	end)

	S.client_store_bridge = guarded("client_store_bridge", function()
		local SC = H.ctrl("StoreController")
		local MC = H.ctrl("MenuController")
		local TB = H.ctrl("TopBarController")
		local PC = H.ctrl("PetsController")
		if not T.check(type(SC) == "table" and type(MC) == "table" and type(TB) == "table" and type(PC) == "table", "store bridge: the four controllers load") then
			return
		end
		local saved = H.begin()
		Mock.SetViewport(1920, 1080)
		H.setId("Starter", 5001)
		H.setId("VIP", 5002)
		KC.advance(0.3)
		local from = #saved.Opened
		KC.toClient("OpenPanel", "Store", { Tab = "Passes" })
		KC.advance(0.5)
		local guis = 0
		for _, g in ipairs(H.pg():GetChildren()) do
			if g.Name == "NimbusShop" then
				guis = guis + 1
			end
		end
		local win = H.win()
		T.check(SC.IsOpen() and win ~= nil and H.activeTab(win) == "Passes" and H.count(saved.Opened, "Store", from) == 1 and guis == 1,
			"store bridge: OpenPanel(\"Store\", { Tab = \"Passes\" }) opens on Passes once", fmt("%s tab %s, %d opens, %d guis", tostring(SC.IsOpen()), tostring(win and H.activeTab(win)), H.count(saved.Opened, "Store", from), guis))
		H.pressPill("Shop")
		T.check(not SC.IsOpen() and not MC.IsOpen(), "store bridge: a second pill tap closes the Store")
		H.pressPill("Shop")
		T.check(SC.IsOpen(), "store bridge: the pill opens it again")
		Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Escape", "Keyboard", "Begin"), false)
		KC.advance(0.3)
		T.check(not SC.IsOpen(), "store bridge: Esc closes the Store")
		H.pressPill("Shop")
		MC.Close()
		KC.advance(0.3)
		T.check(not SC.IsOpen(), "store bridge: MenuController.Close() closes the Store")
		H.pressPill("Shop")
		local r = TB.GetRect and TB.GetRect()
		T.check(SC.IsOpen() and type(r) == "table" and r.X1 > r.X0, "store bridge: the top bar still answers while the Store is open")
		SC.Close()
		KC.advance(0.3)
		-- the window rule (spec 8): the Store, the Pets window and the menu's windows never overlap
		PC.Open()
		KC.advance(0.4)
		H.pressPill("Shop")
		T.check(PC.IsOpen() == false and SC.IsOpen(), "store bridge: the Store closes the Pets window", tostring(PC.IsOpen()) .. " / " .. tostring(SC.IsOpen()))
		PC.Open()
		KC.advance(0.4)
		T.check(SC.IsOpen() == false and PC.IsOpen(), "store bridge: the Pets window closes the Store")
		PC.Close(true)
		KC.advance(0.4)
		SC.Open()
		KC.advance(0.3)
		MC.Open("Home")
		KC.advance(0.4)
		T.check(SC.IsOpen() == false, "store bridge: a menu window (Home) closes the Store")
		MC.Close()
		KC.advance(0.3)
		SC.Open()
		KC.advance(0.3)
		MC.Open("Index")
		KC.advance(0.5)
		T.check(SC.IsOpen() == false, "store bridge: the Pet Index closes the Store")
		H.finish(saved)
		KC.flushErrors("client_store_bridge")
	end)

	S.client_store_mobile = guarded("client_store_mobile", function()
		local SC = H.ctrl("StoreController")
		if not T.check(type(SC) == "table" and type(SC.Open) == "function", "store mobile: StoreController loads") then
			return
		end
		local saved = H.begin()
		Mock.SetViewport(844, 390)
		KC.advance(0.5)
		H.setId("Starter", 5001)
		H.setId("VIP", 5002)
		H.setId("Tokens1", 5003)
		H.setId("XpPotion1", 5004)
		H.setAttr("XpBoostEnds", os.time() + 20 * 60)
		local tol = CONTRACT.v2.centreTolerance
		local before = {}
		for _, e in ipairs(KC.centredTexts(tol)) do
			before[e.path] = true
		end
		SC.Open()
		KC.advance(0.6)
		local win = H.win()
		if not T.check(SC.IsOpen() and win ~= nil, "store mobile: the Store opens on a phone") then
			H.finish(saved)
			return
		end
		T.check(H.near(win.AbsoluteSize.X, 820) and H.near(win.AbsoluteSize.Y, 330) and SC.Layout() == "Phone", "store mobile: 820x330 at scale 1 (Phone)",
			fmt("%.0fx%.0f %s", win.AbsoluteSize.X, win.AbsoluteSize.Y, tostring(SC.Layout())))
		local small = {}
		if KC.smallTexts then
			for _, line in ipairs(KC.smallTexts(15)) do
				if line:find("NimbusShop", 1, true) then
					small[#small + 1] = line
				end
			end
		end
		T.check(KC.smallTexts ~= nil and #small == 0, "store mobile: every Shop text is >= 15 px", table.concat(small, "; ", 1, math.min(#small, 5)))
		local tab = win:FindFirstChild("Tab_Packs", true)
		T.check(tab ~= nil and H.near(tab.AbsoluteSize.X, 104) and H.near(tab.AbsoluteSize.Y, 48), "store mobile: rail tabs 104x48 (the 280 px body at 844x390, lobby-shop 16.3)",
			tab and fmt("%.0fx%.0f", tab.AbsoluteSize.X, tab.AbsoluteSize.Y) or "none")
		local buy = H.buyButton(win, "Starter")
		T.check(buy ~= nil and H.near(buy.AbsoluteSize.X, 150) and H.near(buy.AbsoluteSize.Y, 48), "store mobile: Buy 150x48",
			buy and fmt("%.0fx%.0f", buy.AbsoluteSize.X, buy.AbsoluteSize.Y) or "none")
		local hero = H.card(win, "Starter")
		T.check(hero ~= nil and H.near(hero.AbsoluteSize.Y, 150) and H.card(win, "XpPotion1") ~= nil and H.near(H.card(win, "XpPotion1").AbsoluteSize.Y, 108),
			"store mobile: hero 150 and cards 108 tall")
		T.eq(GuiService.TouchControlsEnabled, false, "store mobile: Roblox's touch controls go while the Store is up")
		-- (the window itself fills a phone: what is pinned is that the Store announces nothing else in the middle)
		local extra = {}
		for _, e in ipairs(KC.centredTexts(tol)) do
			if not before[e.path] and not e.path:find("NimbusShop", 1, true) then
				extra[#extra + 1] = e.path .. " '" .. e.text .. "'"
			end
		end
		T.check(#extra == 0, "store mobile: opening the Store puts no other text in the middle of the screen", table.concat(extra, "; "))
		SC.Close()
		KC.advance(0.5)
		T.eq(GuiService.TouchControlsEnabled, true, "store mobile: ...and they come back after Close")
		local left = {}
		for _, e in ipairs(KC.centredTexts(tol)) do
			if e.path:find("NimbusShop", 1, true) then
				left[#left + 1] = e.path
			end
		end
		T.check(#left == 0, "store mobile: no Store text is left in the middle band after Close", table.concat(left, "; "))
		H.finish(saved)
		KC.flushErrors("client_store_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return {}
end
return clientScenarios()
