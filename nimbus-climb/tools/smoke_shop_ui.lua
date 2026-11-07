-- smoke_shop_ui.lua: lobby-shop Task 21 (spec 16.3 "Who owns it", "Tabs and items", "Window", "Gems tab", "Packs, Passes,
-- Boosts", "Hooks" (the Task 21 step); 16.1 ribbons, BEST VALUE, the Chest line, the token-grant lock): the Shop window A
-- (client/Controllers/ShopController, moved from StoreController) and its Gems page (client/UI/ShopGems). Loaded by
-- tools/smoke.py in the CLIENT and PHONE worlds (Tasks 22 / 23 extend this file):
--   client_shop_window   (1920x1080) NimbusShop (order 19, IgnoreGuiInset, not reset on spawn) > ShopWindow = NeonKit.BigRect
--                        1540x910; the rail's five tabs in order at x 18, y 16 + i * 92 (+44 from Tab_Packs) under the
--                        header, 224 x 80, the RobuxDivider between Gems and Packs; the header (Title "Shop", Balance_Gems
--                        a GemIcon.Amount, Balance_Tokens, CloseButton, no Cash pill); NormalizeTab for every alias; Open
--                        { Tab = "Currency" } -> Gems, { Tab = "Passes" } -> Passes; the first open shows Packs, a re-open the
--                        last tab; Packs / Passes / Boosts hold every StoreCatalog card of their tab inside the content box
--                        (x 262, width 1240); Tab_Packs.Dot while the Starter Pack is on sale and unbought; Tab_Eggs hops to
--                        MenuController's Cloud Shop; WindowOpened("Store") once per open; SetTouchHidden("Shop", true) on a
--                        touch device; the cursor free with mouse lock on; Esc closes; NimbusShopBack only while open,
--                        above NimbusDash, B closes and returns Sink
--   client_shop_gems     (1920x1080, 1280x720, 844x390, 390x844) the gem packs and names from Config; the ribbons and BEST
--                        VALUE computed from the prices shown (Config Robux, a changed Robux, a live PriceInRobux); Id 0 =
--                        the Config Robux on an inactive button with "Coming soon" ("PREVIEW" under StorePreview); a created
--                        pack buys through StoreRequest("Buy", "Gems<i>"); the hero's ChestLine; every PotionState; the
--                        token packs with the computed BEST VALUE and no % ribbon; the token-grant lock (TokenPack_1..3 and
--                        Card_Pro) while PaidRandomItemsRestricted is not false; 1280x720 reachability; the phone row of
--                        eight tiles with its Fade; the portrait list; no gem glyph text
--   client_shop_sizes    (1280x720, 1366x768, 1920x1080, 2560x1440) ShopWindow = NeonKit.BigRect (design 1296 x 759,
--                        1383 x 810, 1540 x 910, 1540 x 910 at 1.25); the Compact rail at the first two, PC at the others;
--                        every card of Gems, Packs, Passes and Boosts reachable inside Body by scrolling
--   client_shop_mobile   (phone world: 844x390, 740x360, 667x375, 640x360) ShopWindow = BigRect; rail 104 wide; tabs by body
--                        (104 x 48 at 6 + i * 54 with a 280 body, 104 x 44 at 4 + i * 49 under 276); RedoGeom.check on every
--                        tab; big balances (Review Focus 6); resize while open (Review Focus 1)
--   client_shop_portrait (phone world: 390x844, 360x640) two header rows, the rail as one row of five 64 x 56 tabs, a
--                        vertical list on every tab, RedoGeom.check
-- Every scenario puts back the Config ids / prices it touched, the attributes, the MarketplaceService doubles and the
-- viewport. Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format
local abs = math.abs

local S = {}

local GLYPH = "\226\151\134"
local TABS = { "Eggs", "Gems", "Packs", "Passes", "Boosts" }
local LOCK = "Token packs are not available on your account"
local CHECKING = "Checking your account..."
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ATTRS = { "InMatch", "OwnedPasses", "StoreBought", "XpBoostEnds", "StorePreview", "PaidRandomItemsRestricted", "GemsSettled",
	"XpPassState", "Gems", "CloudTokens" }

local G = {}
function G.KC()
	return _G.KC
end
function G.req(key)
	local inst = Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", ""))
	if not inst then
		return nil
	end
	local ok, mod = pcall(require, inst)
	return ok and type(mod) == "table" and mod or nil
end
function G.advance(seconds)
	Mock.Advance(seconds)
end
function G.pg()
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end
function G.gui()
	local pg = G.pg()
	return pg and pg:FindFirstChild("NimbusShop") or nil
end
function G.win()
	local gui = G.gui()
	return gui and gui:FindFirstChild("ShopWindow") or nil
end
function G.body()
	local win = G.win()
	return win and win:FindFirstChild("Body") or nil
end
function G.find(root, name)
	return RedoGeom.find(root, name)
end
function G.box(o)
	local p, s = o.AbsolutePosition, o.AbsoluteSize
	return { x = p.X, y = p.Y, w = s.X, h = s.Y }
end
function G.shown(o)
	return o ~= nil and G.KC().isShown(o)
end
function G.scale()
	local win = G.win()
	local fit = win and win:FindFirstChild("Fit")
	return fit and fit.Scale or 1
end
-- o's box relative to `ref` in design px (the window's Fit scale taken out)
function G.rel(o, ref)
	local a, b, s = G.box(o), G.box(ref), G.scale()
	return { x = (a.x - b.x) / s, y = (a.y - b.y) / s, w = a.w / s, h = a.h / s }
end
function G.near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1)
end
function G.inside(a, b, slack)
	slack = slack or 1
	return a.x >= b.x - slack and a.y >= b.y - slack and a.x + a.w <= b.x + b.w + slack and a.y + a.h <= b.y + b.h + slack
end
function G.d(o)
	return RedoGeom.desc(o)
end
function G.setAttr(name, v)
	LocalPlayer:SetAttribute(name, v)
end
function G.item(key)
	local Config = G.KC().env()
	for _, it in ipairs(Config.Store.Items) do
		if it.Key == key then
			return it
		end
	end
	return nil
end
function G.setId(key, id)
	local Config = G.KC().env()
	local i = key:match("^Gems(%d)$")
	if i then
		Config.Gems.Products[tonumber(i)].Id = id
		return
	end
	local it = G.item(key)
	if it then
		it.Id = id
	end
end
function G.calls(name, mark, a1, a2)
	local n = 0
	for _, e in ipairs(G.KC().serverCalls(name, mark)) do
		if (a1 == nil or e.args[1] == a1) and (a2 == nil or e.args[2] == a2) then
			n = n + 1
		end
	end
	return n
end
function G.texts(root)
	local out = {}
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and G.shown(d) and tostring(d.Text) ~= "" then
			out[#out + 1] = tostring(d.Text)
		end
	end
	return table.concat(out, " | ")
end
function G.glyphs(root)
	local out = {}
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and tostring(d.Text):find(GLYPH, 1, true) then
			out[#out + 1] = d:GetFullName()
		end
	end
	return out
end
function G.tile(name)
	return G.find(G.win(), name)
end
function G.part(tile, name)
	return tile and tile:FindFirstChild(name, true) or nil
end
function G.text(tile, name)
	local p = G.part(tile, name)
	return (p and G.shown(p)) and tostring(p.Text) or nil
end
function G.disabled(b)
	return b ~= nil and (b:GetAttribute("Disabled") == true or b.Active == false)
end
function G.tap(b)
	if b then
		Mock.Click(b)
	end
	G.advance(0.2)
end
function G.tapTab(name)
	G.tap(G.find(G.win(), "Tab_" .. name))
	G.advance(0.2)
end
-- the UIScale chain of o (the window's Fit)
function G.scaleOf(o)
	local s, node = 1, o
	while node and not node:IsA("ScreenGui") do
		for _, ch in ipairs(node:GetChildren()) do
			if ch:IsA("UIScale") and ch.Name ~= "FxScale" and ch.Name ~= "Pop" then
				s = s * ch.Scale
			end
		end
		node = node.Parent
	end
	return s
end
-- scrolls o's nearest ScrollingFrame (clamped to its canvas, like Roblox) until o's top-left is in view; true when o then
-- lies inside `within`
function G.reach(o, within)
	local sc = o.Parent
	while sc and not sc:IsA("ScrollingFrame") and sc ~= within do
		sc = sc.Parent
	end
	if sc and sc:IsA("ScrollingFrame") then
		local b, s, cp = G.box(o), G.box(sc), sc.CanvasPosition
		local k = G.scaleOf(sc)
		local maxX = math.max(0, sc.CanvasSize.X.Offset * k - s.w)
		local maxY = math.max(0, sc.CanvasSize.Y.Offset * k - s.h)
		local x = math.max(0, math.min(maxX, b.x - s.x + cp.X - 2))
		local y = math.max(0, math.min(maxY, b.y - s.y + cp.Y - 2))
		sc.CanvasPosition = Vector2.new(x, y)
		G.advance(0.05)
	end
	local ok = G.inside(G.box(o), G.box(within), 1.5)
	if sc and sc:IsA("ScrollingFrame") then
		sc.CanvasPosition = Vector2.new(0, 0)
		G.advance(0.05)
	end
	return ok
end
-- the cards / tiles a page shows (Card_* on Packs / Passes / Boosts; the gem page's tiles)
function G.pageItems(page)
	local out = {}
	for _, d in ipairs(page and page:GetDescendants() or {}) do
		local n = d.Name
		if d:IsA("GuiObject") and (n:match("^Card_") or n:match("^GemPack_%d$") or n:match("^TokenPack_%d$") or n == "GemPotion" or n == "GemHero") and G.shown(d) then
			out[#out + 1] = d
		end
	end
	return out
end

function G.begin()
	local KC = G.KC()
	local Config = KC.env()
	local saved = { Ids = {}, Gems = {}, Robux = {}, Attrs = {}, Viewport = { Mock.Viewport.X, Mock.Viewport.Y }, Secret = Config.Gems.SecretRoulette.GemPrice }
	for _, it in ipairs(Config.Store.Items) do
		saved.Ids[it.Key] = it.Id
	end
	for i, p in ipairs(Config.Gems.Products) do
		saved.Gems[i] = p.Id
		saved.Robux[i] = p.Robux
	end
	for _, name in ipairs(ATTRS) do
		saved.Attrs[name] = LocalPlayer:GetAttribute(name)
	end
	G.setAttr("InMatch", false)
	G.setAttr("OwnedPasses", "")
	G.setAttr("StoreBought", "")
	G.setAttr("XpBoostEnds", 0)
	G.setAttr("StorePreview", nil)
	G.setAttr("PaidRandomItemsRestricted", false)
	G.setAttr("GemsSettled", true)
	G.setAttr("XpPassState", "NotOwned")
	G.setAttr("Gems", 1250)
	G.setAttr("CloudTokens", 4000)
	for _, it in ipairs(Config.Store.Items) do
		it.Id = 0
	end
	for _, p in ipairs(Config.Gems.Products) do
		p.Id = 0
	end
	local MPS = game:GetService("MarketplaceService")
	saved.Prompts = 0
	MPS.PromptProductPurchase = function()
		saved.Prompts = saved.Prompts + 1
	end
	MPS.PromptGamePassPurchase = function()
		saved.Prompts = saved.Prompts + 1
	end
	local Shop = G.req("client/Controllers/ShopController")
	local MC = G.req("client/Controllers/MenuController")
	if Shop and Shop.Close then
		Shop.Close()
	end
	if MC and MC.Close then
		MC.Close()
	end
	saved.Opened = {}
	if MC and MC.WindowOpened then
		saved.Conn = MC.WindowOpened:Connect(function(id)
			saved.Opened[#saved.Opened + 1] = id
		end)
	end
	G.advance(0.6)
	return saved
end
function G.finish(saved)
	local KC = G.KC()
	local Config = KC.env()
	local Shop = G.req("client/Controllers/ShopController")
	local MC = G.req("client/Controllers/MenuController")
	if Shop and Shop.Close then
		Shop.Close()
	end
	if MC and MC.Close then
		MC.Close()
	end
	for _, it in ipairs(Config.Store.Items) do
		it.Id = saved.Ids[it.Key] or 0
	end
	for i, p in ipairs(Config.Gems.Products) do
		p.Id = saved.Gems[i] or 0
		p.Robux = saved.Robux[i]
	end
	Config.Gems.SecretRoulette.GemPrice = saved.Secret
	for _, name in ipairs(ATTRS) do
		G.setAttr(name, saved.Attrs[name])
	end
	local MPS = game:GetService("MarketplaceService")
	MPS.PromptProductPurchase = nil
	MPS.PromptGamePassPurchase = nil
	MPS.GetProductInfo = nil
	if saved.Conn then
		saved.Conn:Disconnect()
	end
	Mock.SetViewport(saved.Viewport[1], saved.Viewport[2])
	G.advance(0.6)
end
function G.createAll()
	local Config = G.KC().env()
	for i, it in ipairs(Config.Store.Items) do
		it.Id = 8200 + i
	end
	for i, p in ipairs(Config.Gems.Products) do
		p.Id = 8300 + i
	end
end
function G.count(list, value, from)
	local n = 0
	for i = (from or 0) + 1, #list do
		if list[i] == value then
			n = n + 1
		end
	end
	return n
end
-- the Shop's RECT (spec 16.3) through NeonKit.BigRect
function G.rect(NK)
	return NK.BigRect({ RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1540, Y1 = 910 }, MARGIN = 12, PHONE_W = 900, SHORT = 560, PC_MIN_H = 600, PC_MAX_W = 0.81 })
end
function G.noOverlapNames()
	return { "Tab_Eggs", "Tab_Gems", "Tab_Packs", "Tab_Passes", "Tab_Boosts", "Balance_Gems", "Balance_Tokens", "CloseButton" }
end

----------------------------------------------------------------------------------------------------
-- client_shop_window
----------------------------------------------------------------------------------------------------
S.client_shop_window = guarded("client_shop_window", function()
	local KC = G.KC()
	local Shop = G.req("client/Controllers/ShopController")
	local MC = G.req("client/Controllers/MenuController")
	local NK = G.req("client/UI/NeonKit")
	local SCat = G.req("shared/StoreCatalog")
	local UIS = game:GetService("UserInputService")
	local okApi = type(Shop) == "table"
	for _, fn in ipairs({ "Init", "Open", "Close", "IsOpen", "NormalizeTab", "Tab", "Layout", "Portrait", "Cards", "Palette", "RobuxGlyph" }) do
		okApi = okApi and type(Shop[fn]) == "function"
	end
	if not T.check(okApi, "shop window: client/Controllers/ShopController loads with its API") then
		return
	end
	local saved = G.begin()
	Mock.SetViewport(1920, 1080)
	G.advance(0.5)
	if type(Shop._S) == "table" then
		Shop._S.Tab = nil -- (a fresh session: the first open)
	end
	local from = #saved.Opened
	Shop.Open()
	G.advance(0.5)
	local gui, win = G.gui(), G.win()
	T.check(Shop.IsOpen() and gui ~= nil and gui:IsA("ScreenGui") and gui.DisplayOrder == 19 and gui.IgnoreGuiInset == true and gui.ResetOnSpawn == false,
		"shop window: NimbusShop is a ScreenGui at DisplayOrder 19, IgnoreGuiInset, not reset on spawn")
	if not T.check(win ~= nil and G.shown(win), "shop window: ShopWindow is shown") then
		G.finish(saved)
		return
	end
	local r = G.rect(NK)
	local wb = G.box(win)
	T.check(G.near(wb.w, 1540) and G.near(wb.h, 910) and G.near(wb.x, r.x) and G.near(wb.y, r.y) and Shop.Layout() == "PC",
		"shop window: ShopWindow 1540 x 910 at NeonKit.BigRect's place (PC)", fmt("%s; rect %.0f,%.0f", G.d(win), r.x, r.y))
	T.eq(Shop.Tab(), "Packs", "shop window: the first open shows Packs (the Task 21 step)")
	T.eq(G.count(saved.Opened, "Store", from), 1, "shop window: WindowOpened fired 'Store' once for the open")
	-- the rail
	local body = G.body()
	local rail = win:FindFirstChild("Rail")
	local bad = {}
	for i, name in ipairs(TABS) do
		local tab = rail and rail:FindFirstChild("Tab_" .. name)
		if not (tab and G.shown(tab)) then
			bad[#bad + 1] = name .. " missing"
		else
			local rw, rb = G.rel(tab, win), G.rel(tab, body)
			local wantY = 16 + (i - 1) * 92 + (i >= 3 and 44 or 0)
			if not (G.near(rw.x, 18) and G.near(rb.y, wantY) and G.near(rw.w, 224) and G.near(rw.h, 80)) then
				bad[#bad + 1] = fmt("%s at %.0f,%.0f %.0fx%.0f (want 18,%d 224x80)", name, rw.x, rb.y, rw.w, rw.h, wantY)
			end
		end
	end
	T.check(#bad == 0, "shop window: the rail's five tabs in order at x 18, y 16 + i * 92 (+44 from Tab_Packs), 224 x 80", table.concat(bad, "; "))
	local div = rail and rail:FindFirstChild("RobuxDivider")
	local tg, tp = rail and rail:FindFirstChild("Tab_Gems"), rail and rail:FindFirstChild("Tab_Packs")
	T.check(div ~= nil and G.shown(div) and tg and tp and G.box(div).y >= G.box(tg).y + G.box(tg).h - 0.5 and G.box(div).y + G.box(div).h <= G.box(tp).y + 0.5,
		"shop window: the RobuxDivider sits between Gems and Packs", div and G.d(div) or "none")
	T.check(div ~= nil and (div:FindFirstChild("Label", true) and tostring(div:FindFirstChild("Label", true).Text) == "Robux items"),
		"shop window: PC: the divider reads 'Robux items'")
	-- the header
	local header = win:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	local gemsPill = header and header:FindFirstChild("Balance_Gems")
	T.check(title ~= nil and tostring(title.Text) == "Shop", "shop window: the header's Title reads 'Shop'")
	T.check(gemsPill ~= nil and gemsPill:FindFirstChild("GemAmount", true) ~= nil and header:FindFirstChild("Balance_Tokens") ~= nil and header:FindFirstChild("CloseButton") ~= nil,
		"shop window: Balance_Gems (a GemIcon.Amount), Balance_Tokens and CloseButton")
	T.check(win:FindFirstChild("Balance_Cash", true) == nil, "shop window: no Cash pill")
	T.check(G.near(G.rel(body, win).x, 262) and G.near(G.rel(body, win).w, 1240), "shop window: the content box (Body) at x 262, 1240 wide", G.d(body))
	-- NormalizeTab
	local cases = {
		{ "Eggs", "Eggs" }, { "eggs", "Eggs" }, { "Egg", "Eggs" }, { "Roulette", "Eggs" }, { "Roulettes", "Eggs" }, { "roulettes", "Eggs" },
		{ "Items", "Eggs" }, { "Shop", "Eggs" }, { "Gems", "Gems" }, { "gem", "Gems" }, { "Currency", "Gems" }, { "Tokens", "Gems" },
		{ "Packs", "Packs" }, { "packs", "Packs" }, { "PASSES", "Passes" }, { "boosts", "Boosts" }, { "Store", nil }, { "nope", nil }, { 5, nil },
	}
	local wrong = {}
	for _, c in ipairs(cases) do
		local got = Shop.NormalizeTab(c[1])
		if got ~= c[2] then
			wrong[#wrong + 1] = fmt("%s -> %s (want %s)", tostring(c[1]), tostring(got), tostring(c[2]))
		end
	end
	T.check(#wrong == 0, "shop window: NormalizeTab maps every alias of spec 16.3", table.concat(wrong, "; "))
	Shop.Open({ Tab = "Currency" })
	G.advance(0.3)
	local pg = body and body:FindFirstChild("Page_Gems")
	T.check(Shop.Tab() == "Gems" and G.shown(pg), "shop window: Open({ Tab = 'Currency' }) -> the Gems tab", tostring(Shop.Tab()))
	Shop.Open({ Tab = "Passes" })
	G.advance(0.3)
	T.check(Shop.Tab() == "Passes" and G.shown(body:FindFirstChild("Page_Passes")) and not G.shown(pg), "shop window: Open({ Tab = 'Passes' }) -> Passes", tostring(Shop.Tab()))
	Shop.Close()
	G.advance(0.3)
	from = #saved.Opened
	Shop.Open()
	G.advance(0.4)
	T.eq(Shop.Tab(), "Passes", "shop window: a re-open shows the last tab")
	T.eq(G.count(saved.Opened, "Store", from), 1, "shop window: ...and fires WindowOpened('Store') once")
	Shop.Open()
	G.advance(0.2)
	T.eq(G.count(saved.Opened, "Store", from), 1, "shop window: Open() on the open Shop fires nothing more")
	-- every created card of Packs / Passes / Boosts in its page, inside the content box
	Shop.Close()
	G.createAll()
	G.advance(0.2)
	Shop.Open({ Tab = "Packs" })
	G.advance(0.5)
	local missing, outside = {}, {}
	local bb = G.box(body)
	for _, tab in ipairs({ "Packs", "Passes", "Boosts" }) do
		G.tapTab(tab)
		local page = body:FindFirstChild("Page_" .. tab)
		for _, it in ipairs(SCat.List()) do
			if it.Tab == tab then
				local card = page and page:FindFirstChild("Card_" .. it.Key, true)
				if not (card and G.shown(card)) then
					missing[#missing + 1] = tab .. "/" .. it.Key
				elseif not G.reach(card, body) then
					outside[#outside + 1] = G.d(card) .. " (body " .. G.d(body) .. ")"
				end
			end
		end
		for _, it in ipairs(SCat.List()) do
			if it.Tab ~= tab and page and page:FindFirstChild("Card_" .. it.Key, true) then
				missing[#missing + 1] = it.Key .. " also on " .. tab
			end
		end
	end
	T.check(#missing == 0, "shop window: Packs / Passes / Boosts hold every StoreCatalog card of their tab (Card_<key>)", table.concat(missing, "; "))
	T.check(#outside == 0 and bb.w > 0, "shop window: ...each inside the content box (x 262, width 1240)", table.concat(outside, "; "))
	-- the Starter dot
	local dot = rail:FindFirstChild("Tab_Packs") and rail.Tab_Packs:FindFirstChild("Dot")
	T.check(dot ~= nil and G.shown(dot), "shop window: Tab_Packs.Dot shows while the Starter Pack is on sale and unbought")
	G.setAttr("StoreBought", "Starter")
	G.advance(0.4)
	T.check(dot ~= nil and not G.shown(dot), "shop window: ...and hides once StoreBought has it")
	G.setAttr("StoreBought", "")
	G.setId("Starter", 0)
	G.advance(1.2)
	T.check(dot ~= nil and not G.shown(dot), "shop window: ...and while the Starter Pack is not on sale (Id 0, no preview)")
	G.setAttr("StorePreview", true)
	G.advance(1.2)
	T.check(dot ~= nil and G.shown(dot), "shop window: ...and shows under StorePreview")
	G.setAttr("StorePreview", nil)
	G.advance(1.2)
	-- Tab_Eggs hops to the Cloud Shop (the old one still lives in MenuController)
	from = #saved.Opened
	G.tapTab("Eggs")
	G.advance(0.4)
	T.check(not Shop.IsOpen() and MC.IsOpen() and saved.Opened[#saved.Opened] == "Shop", "shop window: Tab_Eggs closes the Shop and opens MenuController's Cloud Shop",
		tostring(Shop.IsOpen()) .. " / " .. tostring(saved.Opened[#saved.Opened]))
	MC.Close()
	G.advance(0.4)
	Shop.Open({ Tab = "Roulettes" })
	G.advance(0.4)
	T.check(not Shop.IsOpen() and MC.IsOpen(), "shop window: Open({ Tab = 'Roulettes' }) hops the same way")
	MC.Close()
	G.advance(0.4)
	-- touch: SetTouchHidden("Shop", true) while open, false after
	local realHide = MC.SetTouchHidden
	local hides = {}
	MC.SetTouchHidden = function(who, on)
		hides[#hides + 1] = tostring(who) .. "=" .. tostring(on)
		return realHide(who, on)
	end
	local flags = { UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
	UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = true, false, false
	Shop.Open()
	G.advance(0.4)
	Shop.Close()
	G.advance(0.4)
	UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = flags[1], flags[2], flags[3]
	MC.SetTouchHidden = realHide
	local joined = table.concat(hides, ",")
	T.check(joined:find("Shop=true", 1, true) ~= nil and joined:find("Shop=false", 1, true) ~= nil, "shop window: SetTouchHidden('Shop', true) on a touch device, false on close", joined)
	-- the cursor: free over the open Shop with mouse lock on
	local ML = G.req("client/MouseLock")
	if T.check(type(ML) == "table" and type(ML.SetEnabled) == "function", "shop window: client/MouseLock loads") then
		local was = ML.IsEnabled()
		pcall(ML.Start)
		ML.SetEnabled(true)
		G.advance(0.2)
		Shop.Open()
		G.advance(0.4)
		local held = false
		for key in pairs(ML.Holds()) do
			if tostring(key):find("Shop", 1, true) then
				held = true
			end
		end
		T.check(not ML.IsLocked() and held, "shop window: with mouse lock on the cursor is free while the Shop is open (a 'Shop' hold)")
		Shop.Close()
		G.advance(0.4)
		T.check(ML.IsLocked(), "shop window: ...and locks again once it closes")
		ML.SetEnabled(was)
		G.advance(0.2)
	end
	-- Esc
	Shop.Open()
	G.advance(0.3)
	Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Escape", "Keyboard", "Begin"), false)
	G.advance(0.3)
	T.check(not Shop.IsOpen(), "shop window: Esc closes the Shop")
	-- gamepad B
	T.check(Mock.BoundActions.NimbusShopBack == nil, "shop window: NimbusShopBack is not bound while closed")
	Shop.Open()
	G.advance(0.3)
	local bound, dash = Mock.BoundActions.NimbusShopBack, Mock.BoundActions.NimbusDash
	local high, default = Enum.ContextActionPriority.High.Value, Enum.ContextActionPriority.Default.Value
	T.check(bound ~= nil and bound.priority == high, "shop window: gamepad B is 'NimbusShopBack' at High while open", bound and tostring(bound.priority) or "not bound")
	-- (the mock's enum Values are not Roblox's numbers: compare by name. In the lobby MovementController binds the dash at
	-- Default, under High; in a battle, at High, the Shop is closed by InMatch)
	T.check(dash == nil or dash.priority == default, "shop window: ...above NimbusDash (the lobby dash is at Default)", dash and tostring(dash.priority) or "no dash")
	local res = Mock.TriggerAction("NimbusShopBack", "Begin")
	G.advance(0.3)
	T.check(res == Enum.ContextActionResult.Sink and not Shop.IsOpen(), "shop window: B closes the Shop and returns Sink", tostring(res))
	T.check(Mock.BoundActions.NimbusShopBack == nil, "shop window: ...and NimbusShopBack is unbound after")
	-- a match closes it and refuses it
	Shop.Open()
	G.advance(0.3)
	G.setAttr("InMatch", true)
	G.advance(0.3)
	T.check(not Shop.IsOpen(), "shop window: a match start closes the Shop")
	T.check(Shop.Open() == false and not Shop.IsOpen(), "shop window: Open() is refused in a match")
	G.setAttr("InMatch", false)
	G.finish(saved)
	KC.flushErrors("client_shop_window")
end)

----------------------------------------------------------------------------------------------------
-- client_shop_gems
----------------------------------------------------------------------------------------------------
S.client_shop_gems = guarded("client_shop_gems", function()
	local KC = G.KC()
	local Config = KC.env()
	local Shop = G.req("client/Controllers/ShopController")
	local SG = G.req("client/UI/ShopGems")
	local MPS = game:GetService("MarketplaceService")
	local okApi = type(Shop) == "table" and type(SG) == "table"
	for _, fn in ipairs({ "Build", "Layout", "Refresh", "PackRibbons", "BestValue", "ChestLine", "PotionState" }) do
		okApi = okApi and type(SG[fn]) == "function"
	end
	if not T.check(okApi, "shop gems: client/UI/ShopGems loads with its API") then
		return
	end
	local saved = G.begin()
	Mock.SetViewport(1920, 1080)
	G.advance(0.5)
	Shop.Open({ Tab = "Gems" })
	G.advance(0.6)
	local function ribbons()
		local out = {}
		for i = 1, 4 do
			out[i] = G.text(G.tile("GemPack_" .. i), "Ribbon") or "-"
		end
		return table.concat(out, " ")
	end
	local function bests(prefix, n)
		local out = {}
		for i = 1, n do
			if G.text(G.tile(prefix .. i), "Best") == "BEST VALUE" then
				out[#out + 1] = tostring(i)
			end
		end
		return table.concat(out, ",")
	end
	-- the packs
	local amounts, names = {}, {}
	for i = 1, 4 do
		local tile = G.tile("GemPack_" .. i)
		amounts[i] = G.text(tile, "Amount") or "?"
		names[i] = G.text(tile, "Name") == Config.Gems.Products[i].Name and "ok" or tostring(G.text(tile, "Name"))
	end
	T.eq(table.concat(amounts, " "), "200 670 1,950 5,300", "shop gems: the packs read 200 / 670 / 1,950 / 5,300")
	T.eq(table.concat(names, " "), "ok ok ok ok", "shop gems: ...with the Config names")
	T.eq(ribbons(), "- +10% +20% +30%", "shop gems: the ribbons computed from the prices shown: none / +10% / +20% / +30%")
	T.eq(bests("GemPack_", 4), "4", "shop gems: BEST VALUE on pack 4")
	local rb = SG.PackRibbons({ { Amount = 200, Robux = 49 }, { Amount = 670, Robux = 149 }, { Amount = 1950, Robux = 399 }, { Amount = 5300, Robux = 999 } })
	T.check(rb[1] == nil and rb[2] == "+10%" and rb[3] == "+20%" and rb[4] == "+30%", "shop gems: PackRibbons -> nil / +10% / +20% / +30%")
	T.eq(SG.BestValue({ { Amount = 200, Robux = 49 }, { Amount = 670, Robux = 149 }, { Amount = 1950, Robux = 399 }, { Amount = 5300, Robux = 999 } }), 4, "shop gems: BestValue -> 4")
	T.eq(SG.BestValue({ { Amount = 100, Robux = 10 }, { Amount = 200, Robux = 20 } }), nil, "shop gems: BestValue -> nil when no pack gains over the first")
	T.eq(SG.BestValue({ { Amount = 100, Robux = 10 }, { Amount = 300, Robux = 20 }, { Amount = 450, Robux = 30 } }), 3, "shop gems: BestValue ties go to the bigger pack")
	-- a changed Robux moves both (computed, never typed)
	Config.Gems.Products[4].Robux = 1999
	G.advance(1.2)
	T.eq(ribbons(), "- +10% +20% -", "shop gems: the Vault at 1,999 R$: no ribbon on pack 4 (its gain is negative)")
	T.eq(bests("GemPack_", 4), "3", "shop gems: ...and BEST VALUE moves to the Chest (pack 3)")
	Config.Gems.Products[4].Robux = saved.Robux[4]
	G.advance(1.2)
	T.eq(ribbons(), "- +10% +20% +30%", "shop gems: ...and back")
	-- a live PriceInRobux that differs from Config moves them the same way
	MPS.GetProductInfo = function(_, id)
		if id == 9104 then
			return { PriceInRobux = 1999 }
		end
		if id == 123 then
			return { PriceInRobux = 59 }
		end
		return { PriceInRobux = 49 }
	end
	G.setId("Gems4", 9104)
	G.advance(1.4)
	T.eq(ribbons(), "- +10% +20% -", "shop gems: a live PriceInRobux of 1,999 on pack 4 drops its ribbon")
	T.eq(bests("GemPack_", 4), "3", "shop gems: ...and moves BEST VALUE to the Chest")
	local buy4 = G.part(G.tile("GemPack_4"), "Buy")
	T.check(buy4 ~= nil and tostring(buy4.Text):find("1,999", 1, true) ~= nil and not G.disabled(buy4), "shop gems: the live price reads on pack 4's Buy", buy4 and buy4.Text or "no buy")
	G.setId("Gems4", 0)
	G.advance(1.2)
	-- Id 0: the Config Robux on an inactive button, "Coming soon" (PREVIEW under StorePreview)
	local tile1 = G.tile("GemPack_1")
	local buy1 = G.part(tile1, "Buy")
	T.check(buy1 ~= nil and tostring(buy1.Text):find("49", 1, true) ~= nil and G.disabled(buy1) and G.text(tile1, "Note") == "Coming soon",
		"shop gems: Id 0 -> the Config Robux (49) on an inactive Buy, 'Coming soon'", buy1 and (buy1.Text .. " / " .. tostring(G.text(tile1, "Note"))) or "no buy")
	G.setAttr("StorePreview", true)
	G.advance(1.2)
	T.eq(G.text(tile1, "Note"), "PREVIEW", "shop gems: ...'PREVIEW' under StorePreview")
	local mark = #Mock.RemoteLog
	G.tap(buy1)
	T.eq(G.calls("StoreRequest", mark), 0, "shop gems: a preview pack sends nothing")
	G.setAttr("StorePreview", nil)
	-- a created pack: the live price, one StoreRequest("Buy", "Gems2") per tap
	G.setId("Gems2", 123)
	G.advance(1.4)
	local tile2 = G.tile("GemPack_2")
	local buy2 = G.part(tile2, "Buy")
	T.check(buy2 ~= nil and tostring(buy2.Text):find("59", 1, true) ~= nil and not G.disabled(buy2) and G.text(tile2, "Note") == nil,
		"shop gems: Id 123 -> the live price 59 on an active Buy", buy2 and buy2.Text or "no buy")
	mark = #Mock.RemoteLog
	G.tap(buy2)
	G.tap(buy2)
	T.eq(G.calls("StoreRequest", mark, "Buy", "Gems2"), 1, "shop gems: a tap sends one StoreRequest('Buy', 'Gems2') (a second inside 1 s nothing)")
	G.advance(1.2)
	G.tap(buy2)
	T.eq(G.calls("StoreRequest", mark, "Buy", "Gems2"), 2, "shop gems: ...one per tap after the gap")
	T.eq(saved.Prompts, 0, "shop gems: the client never prompts a purchase")
	-- the hero
	local hero = G.tile("GemHero")
	T.eq(SG.ChestLine(), "Chest: 1,950 gems buys 3 Secret spins + 2 Celestial spins", "shop gems: ChestLine() with the owner's prices")
	T.eq(G.text(hero, "Line2"), SG.ChestLine(), "shop gems: the hero's Line2 is ChestLine()")
	Config.Gems.SecretRoulette.GemPrice = 600
	G.advance(1.2)
	T.eq(SG.ChestLine(), "Chest: 1,950 gems buys 3 Secret spins", "shop gems: with the Secret Roulette at 600 the Celestial part drops")
	T.eq(G.text(hero, "Line2"), "Chest: 1,950 gems buys 3 Secret spins", "shop gems: ...on the hero too")
	Config.Gems.SecretRoulette.GemPrice = saved.Secret
	G.advance(1.2)
	-- the potion: every state from its attributes
	local potion = G.tile("GemPotion")
	local pbuy = G.part(potion, "Buy")
	local function potionShows()
		local amount = pbuy and pbuy:FindFirstChild("GemAmount", true)
		local value = amount and amount:FindFirstChild("Value", true)
		if amount and G.shown(amount) and value then
			return "gem:" .. tostring(value.Text), value
		end
		return pbuy and tostring(pbuy.Text) or "?", nil
	end
	mark = #Mock.RemoteLog
	local states = {
		{ "Loading", function() G.setAttr("GemsSettled", nil) end, "Loading..." },
		{ "Owned", function() G.setAttr("GemsSettled", true); G.setAttr("XpPassState", "Owned") end, "You have x2 Pet XP" },
		{ "Checking", function() G.setAttr("XpPassState", "Checking") end, "Checking your passes..." },
		{ "Full", function() G.setAttr("XpPassState", "NotOwned"); G.setAttr("XpBoostEnds", os.time() + 7 * 86400 - 600) end, "Potion time is full" },
		{ "Short", function() G.setAttr("XpBoostEnds", 0); G.setAttr("Gems", 99) end, "gem:100" },
	}
	for _, st in ipairs(states) do
		st[2]()
		G.advance(1.2)
		local got = SG.PotionState()
		local shows = potionShows()
		T.check(got == st[1] and shows == st[3], "shop gems: PotionState " .. st[1] .. " reads '" .. st[3] .. "'", tostring(got) .. " / " .. tostring(shows))
		G.tap(pbuy)
		G.advance(1.1)
	end
	local _, value = potionShows()
	G.setAttr("Gems", 99)
	G.advance(1.2)
	_, value = potionShows()
	T.check(value ~= nil and value.TextColor3.R > 0.8 and value.TextColor3.G < 0.5, "shop gems: Short keeps the price, the amount red")
	T.eq(G.calls("StoreRequest", mark, "GemBuy"), 0, "shop gems: no GemBuy outside Ready")
	G.setAttr("Gems", 100)
	G.advance(1.2)
	T.check(SG.PotionState() == "Ready" and potionShows() == "gem:100", "shop gems: Ready at 100 gems, '100' on the button", tostring(SG.PotionState()))
	G.tap(pbuy)
	T.eq(G.calls("StoreRequest", mark, "GemBuy", "XpPotionGems"), 1, "shop gems: only Ready sends StoreRequest('GemBuy', 'XpPotionGems')")
	G.setAttr("Gems", 1250)
	G.advance(1.2)
	-- the token packs
	local tAmounts, tribbons = {}, {}
	for i = 1, 3 do
		local tile = G.tile("TokenPack_" .. i)
		tAmounts[i] = G.text(tile, "Amount") or "?"
		if G.text(tile, "Ribbon") then
			tribbons[#tribbons + 1] = i
		end
	end
	T.eq(table.concat(tAmounts, " "), "1,500 7,500 30,000", "shop gems: the token packs read 1,500 / 7,500 / 30,000")
	T.eq(bests("TokenPack_", 3), "3", "shop gems: the computed BEST VALUE on token pack 3")
	T.eq(#tribbons, 0, "shop gems: no % ribbon on a token pack")
	-- the token-grant lock (spec 16.1)
	for i = 1, 3 do
		G.setId("Tokens" .. i, 9200 + i)
	end
	G.setId("Pro", 9210)
	local function lockCase(value, text, tag)
		G.setAttr("PaidRandomItemsRestricted", value)
		G.advance(1.4)
		local m = #Mock.RemoteLog
		local bad = {}
		for i = 1, 3 do
			local tile = G.tile("TokenPack_" .. i)
			local b = G.part(tile, "Buy")
			if not (G.texts(tile):find(text, 1, true) and G.disabled(b)) then
				bad[#bad + 1] = "TokenPack_" .. i .. ": " .. G.texts(tile)
			end
			G.tap(b)
			G.advance(1.1)
		end
		T.check(#bad == 0, "shop gems: " .. tag .. ": TokenPack_1..3 show '" .. text .. "' on an inactive Buy", table.concat(bad, "; "))
		T.eq(G.calls("StoreRequest", m), 0, "shop gems: " .. tag .. ": a tap on a locked token pack sends nothing")
		G.tapTab("Packs")
		G.advance(0.3)
		local pro = G.find(G.win(), "Card_Pro")
		local pb = G.part(pro, "Buy")
		T.check(pro ~= nil and G.texts(pro):find(text, 1, true) ~= nil and G.disabled(pb), "shop gems: " .. tag .. ": Card_Pro shows the lock on an inactive Buy", pro and G.texts(pro) or "no card")
		G.tap(pb)
		T.eq(G.calls("StoreRequest", m), 0, "shop gems: " .. tag .. ": a tap on the locked Pro Pack sends nothing")
		G.tapTab("Gems")
		G.advance(1.1)
		local g2 = G.part(G.tile("GemPack_2"), "Buy")
		T.check(not G.disabled(g2), "shop gems: " .. tag .. ": the gem packs are unaffected")
	end
	lockCase(true, LOCK, "restricted")
	lockCase(nil, CHECKING, "unknown")
	G.setAttr("PaidRandomItemsRestricted", false)
	G.advance(1.4)
	mark = #Mock.RemoteLog
	for i = 1, 3 do
		local b = G.part(G.tile("TokenPack_" .. i), "Buy")
		T.check(not G.disabled(b), "shop gems: allowed: TokenPack_" .. i .. " is buyable")
		G.tap(b)
		G.advance(1.1)
	end
	T.check(G.calls("StoreRequest", mark, "Buy", "Tokens1") == 1 and G.calls("StoreRequest", mark, "Buy", "Tokens3") == 1, "shop gems: allowed: each token pack sends its StoreRequest('Buy', 'Tokens<i>')")
	T.eq(#G.glyphs(G.gui()), 0, "shop gems: no gem glyph text in NimbusShop")
	-- 1280x720: the token packs are reachable inside Body
	Mock.SetViewport(1280, 720)
	G.advance(0.6)
	local unreached = {}
	for i = 1, 3 do
		local tile = G.tile("TokenPack_" .. i)
		if not (tile and G.reach(tile, G.body())) then
			unreached[#unreached + 1] = tile and G.d(tile) or ("TokenPack_" .. i .. " missing")
		end
	end
	T.check(#unreached == 0, "shop gems: 1280x720: the token packs are reachable inside Body", table.concat(unreached, "; ") .. " / body " .. G.d(G.body()))
	Shop.Close()
	G.advance(0.3)
	-- phone: one sideways row of eight tiles with the right Fade
	RedoGeom.at(844, 390, true, "shop gems 844x390", function()
		Shop.Open({ Tab = "Gems" })
		G.advance(0.6)
		local names = { "GemPack_1", "GemPack_2", "GemPack_3", "GemPack_4", "GemPotion", "TokenPack_1", "TokenPack_2", "TokenPack_3" }
		local body = G.body()
		local bh = G.rel(body, G.win()).h
		local th = math.min(266, bh - 12)
		local bad, lastX, y0 = {}, nil, nil
		for _, n in ipairs(names) do
			local t = G.tile(n)
			if not (t and G.shown(t)) then
				bad[#bad + 1] = n .. " missing"
			else
				local b = G.rel(t, body)
				if not (G.near(b.w, 166) and G.near(b.h, th)) then
					bad[#bad + 1] = fmt("%s %.0fx%.0f", n, b.w, b.h)
				end
				if lastX and not G.near(b.x - lastX, 174) then
					bad[#bad + 1] = fmt("%s step %.0f", n, b.x - lastX)
				end
				if y0 and not G.near(b.y, y0) then
					bad[#bad + 1] = fmt("%s y %.0f", n, b.y)
				end
				lastX, y0 = b.x, y0 or b.y
			end
		end
		T.check(#bad == 0 and G.near(th, 266), "shop gems: phone: one sideways row of eight 166 x min(266, body - 12) tiles (266 at 844x390)", table.concat(bad, "; "))
		T.check(not G.shown(G.tile("GemHero")), "shop gems: phone: no hero (its Chest is pack 3)")
		local fade = G.find(G.find(body, "Page_Gems"), "Fade")
		T.check(fade ~= nil and G.shown(fade) and G.near(G.rel(fade, body).w, 48) and G.near(G.rel(fade, body).x + 48, G.rel(body, body).w + G.rel(body, body).x, 2),
			"shop gems: phone: the 48 px right Fade shows while more is to the right", fade and G.d(fade) or "none")
		local scroll = G.find(G.find(body, "Page_Gems"), "Scroll")
		if scroll then
			scroll.CanvasPosition = Vector2.new(5000, 0)
			G.advance(0.2)
			T.check(not G.shown(fade), "shop gems: phone: ...and hides at the row's end")
			scroll.CanvasPosition = Vector2.new(0, 0)
			G.advance(0.2)
		end
		RedoGeom.check(G.win(), "shop gems 844x390", { MinText = 15, MinTarget = 44, NoOverlap = G.noOverlapNames() })
		Shop.Close()
		G.advance(0.3)
	end)
	RedoGeom.at(390, 844, true, "shop gems 390x844", function()
		Shop.Open({ Tab = "Gems" })
		G.advance(0.6)
		local order = { "GemHero", "GemPack_1", "GemPack_2", "GemPack_3", "GemPack_4", "GemPotion", "TokenPack_1", "TokenPack_2", "TokenPack_3" }
		local bad, lastY = {}, -1
		local body = G.body()
		for _, n in ipairs(order) do
			local t = G.tile(n)
			if not (t and G.shown(t)) then
				bad[#bad + 1] = n .. " missing"
			else
				local b = G.rel(t, body)
				if b.y <= lastY or b.w < G.rel(body, body).w - 16 then
					bad[#bad + 1] = fmt("%s at y %.0f w %.0f", n, b.y, b.w)
				end
				lastY = b.y
			end
		end
		T.check(#bad == 0, "shop gems: portrait: the vertical list, hero on top, full-width rows", table.concat(bad, "; "))
		RedoGeom.check(G.win(), "shop gems 390x844", { MinText = 15, MinTarget = 44, NoOverlap = G.noOverlapNames() })
		Shop.Close()
		G.advance(0.3)
	end)
	G.finish(saved)
	KC.flushErrors("client_shop_gems")
end)

----------------------------------------------------------------------------------------------------
-- client_shop_sizes
----------------------------------------------------------------------------------------------------
S.client_shop_sizes = guarded("client_shop_sizes", function()
	local KC = G.KC()
	local Shop = G.req("client/Controllers/ShopController")
	local NK = G.req("client/UI/NeonKit")
	if not T.check(type(Shop) == "table" and type(Shop.Open) == "function", "shop sizes: ShopController loads") then
		return
	end
	local saved = G.begin()
	G.createAll()
	local SIZES = {
		{ 1280, 720, 1296, 759, "Compact" }, { 1366, 768, 1383, 810, "Compact" }, { 1920, 1080, 1540, 910, "PC" }, { 2560, 1440, 1540, 910, "PC" },
	}
	for _, sz in ipairs(SIZES) do
		local label = fmt("shop sizes %dx%d", sz[1], sz[2])
		Mock.SetViewport(sz[1], sz[2])
		G.advance(0.6)
		Shop.Open({ Tab = "Gems" })
		G.advance(0.6)
		local win = G.win()
		local r = G.rect(NK)
		local s = G.scale()
		T.check(win ~= nil and G.near(win.AbsoluteSize.X, r.w, 1.5) and G.near(win.AbsoluteSize.Y, r.h, 1.5) and G.near(win.AbsoluteSize.X / s, sz[3], 1.5) and G.near(win.AbsoluteSize.Y / s, sz[4], 1.5),
			label .. ": ShopWindow = NeonKit.BigRect (design " .. sz[3] .. " x " .. sz[4] .. ")", win and fmt("%.0fx%.0f at scale %.2f", win.AbsoluteSize.X, win.AbsoluteSize.Y, s) or "no window")
		T.eq(Shop.Layout(), sz[5], label .. ": the " .. sz[5] .. " layout")
		local rail = win and win:FindFirstChild("Rail")
		local tab = rail and rail:FindFirstChild("Tab_Packs")
		local icon, lbl = tab and tab:FindFirstChild("Icon"), tab and tab:FindFirstChild("Label")
		if sz[5] == "Compact" then
			T.check(tab ~= nil and G.near(G.rel(tab, win).w, 112) and icon and lbl and G.box(icon).y + G.box(icon).h <= G.box(lbl).y + 1,
				label .. ": the Compact rail: 112 wide, the icon over the label", tab and G.d(tab) or "no tab")
			T.check(G.near(G.rel(G.body(), win).x, 128), label .. ": Compact content box at x 128", G.d(G.body()))
		else
			T.check(tab ~= nil and G.near(G.rel(tab, win).w, 224) and icon and lbl and G.box(icon).x + G.box(icon).w <= G.box(lbl).x + 1,
				label .. ": the PC rail: 224 wide, the icon left of the label", tab and G.d(tab) or "no tab")
		end
		local unreached, count = {}, 0
		for _, page in ipairs({ "Gems", "Packs", "Passes", "Boosts" }) do
			Shop.Open({ Tab = page })
			G.advance(0.3)
			local p = G.body():FindFirstChild("Page_" .. page)
			for _, item in ipairs(G.pageItems(p)) do
				count = count + 1
				if not G.reach(item, G.body()) then
					unreached[#unreached + 1] = page .. "/" .. G.d(item)
				end
			end
		end
		T.check(count >= 16 and #unreached == 0, label .. ": every card on Gems, Packs, Passes and Boosts is reachable inside Body", count .. " cards; " .. table.concat(unreached, "; "))
		RedoGeom.check(win, label, { MinText = 14, MinTarget = 44, NoOverlap = G.noOverlapNames() })
		Shop.Close()
		G.advance(0.3)
	end
	G.finish(saved)
	KC.flushErrors("client_shop_sizes")
end)

----------------------------------------------------------------------------------------------------
-- client_shop_mobile (phone world)
----------------------------------------------------------------------------------------------------
S.client_shop_mobile = guarded("client_shop_mobile", function()
	local KC = G.KC()
	local Shop = G.req("client/Controllers/ShopController")
	local NK = G.req("client/UI/NeonKit")
	if not T.check(type(Shop) == "table" and type(Shop.Open) == "function", "shop phone: ShopController loads") then
		return
	end
	local saved = G.begin()
	G.createAll()
	local SIZES = { { 844, 390, 820, 330 }, { 740, 360, 716, 300 }, { 667, 375, 643, 315 }, { 640, 360, 616, 300 } }
	for _, sz in ipairs(SIZES) do
		local label = fmt("shop phone %dx%d", sz[1], sz[2])
		RedoGeom.at(sz[1], sz[2], true, label, function()
			Shop.Open({ Tab = "Gems" })
			G.advance(0.6)
			local win = G.win()
			local r = G.rect(NK)
			T.check(win ~= nil and G.near(win.AbsoluteSize.X, sz[3], 1.5) and G.near(win.AbsoluteSize.Y, sz[4], 1.5) and G.near(r.w, sz[3], 1.5) and Shop.Layout() == "Phone",
				label .. ": ShopWindow = NeonKit.BigRect " .. sz[3] .. " x " .. sz[4] .. " (Phone)", win and G.d(win) or "no window")
			local body = G.body()
			local bodyH = G.rel(body, win).h
			local rail = win:FindFirstChild("Rail")
			local big = bodyH >= 276
			local tabH, y0, step = big and 48 or 44, big and 6 or 4, big and 54 or 49
			local bad = {}
			for i, name in ipairs(TABS) do
				local tab = rail and rail:FindFirstChild("Tab_" .. name)
				local rb = tab and G.rel(tab, body)
				if not (rb and G.near(rb.w, 104) and G.near(rb.h, tabH) and G.near(rb.y, y0 + (i - 1) * step) and G.near(G.rel(tab, win).x, 8)) then
					bad[#bad + 1] = rb and fmt("%s %.0f,%.0f %.0fx%.0f", name, G.rel(tab, win).x, rb.y, rb.w, rb.h) or (name .. " missing")
				end
			end
			T.check(#bad == 0, fmt("%s: body %.0f: tabs 104 x %d at x 8, y %d + i * %d", label, bodyH, tabH, y0, step), table.concat(bad, "; "))
			local boosts = rail and rail:FindFirstChild("Tab_Boosts")
			T.check(boosts ~= nil and G.inside(G.box(boosts), G.box(win), 0.5) and G.box(boosts).y + G.box(boosts).h <= sz[2] + 0.5, label .. ": Tab_Boosts inside the window and the screen", boosts and G.d(boosts) or "none")
			for _, tab in ipairs({ "Gems", "Packs", "Passes", "Boosts" }) do
				Shop.Open({ Tab = tab })
				G.advance(0.3)
				RedoGeom.check(win, label .. " " .. tab, { MinText = 15, MinTarget = 44, NoOverlap = G.noOverlapNames() })
			end
			-- big balances (Review Focus 6)
			G.setAttr("Gems", 12345678)
			G.setAttr("CloudTokens", 12345678)
			G.advance(1.2)
			local header = win:FindFirstChild("Header")
			local gemsText, tokText = G.texts(header and header:FindFirstChild("Balance_Gems")), G.texts(header and header:FindFirstChild("Balance_Tokens"))
			T.check(gemsText:find("12.3M", 1, true) ~= nil and tokText:find("12.3M", 1, true) ~= nil, label .. ": big balances read Theme.ShortNumber (12.3M)", gemsText .. " / " .. tokText)
			RedoGeom.check(win, label .. " big balances", { MinText = 15, MinTarget = 44, NoOverlap = G.noOverlapNames() })
			G.setAttr("Gems", 1250)
			G.setAttr("CloudTokens", 4000)
			Shop.Close()
			G.advance(0.3)
		end)
	end
	-- resize while open (Review Focus 1): 844x390 -> 390x844 -> 844x390
	RedoGeom.at(844, 390, true, "shop phone resize", function()
		Shop.Open({ Tab = "Packs" })
		G.advance(0.6)
		RedoGeom.check(G.win(), "shop phone resize: 844x390", { MinText = 15, MinTarget = 44, NoOverlap = G.noOverlapNames() })
		Mock.SetViewport(390, 844)
		G.advance(0.6)
		T.check(Shop.IsOpen() and Shop.Portrait(), "shop phone resize: still open, now portrait")
		RedoGeom.check(G.win(), "shop phone resize: 390x844", { MinText = 15, MinTarget = 44, NoOverlap = G.noOverlapNames() })
		Mock.SetViewport(844, 390)
		G.advance(0.6)
		T.check(Shop.IsOpen() and not Shop.Portrait() and Shop.Layout() == "Phone", "shop phone resize: back to the landscape phone layout")
		RedoGeom.check(G.win(), "shop phone resize: 844x390 again", { MinText = 15, MinTarget = 44, NoOverlap = G.noOverlapNames() })
		Shop.Close()
		G.advance(0.3)
	end)
	G.finish(saved)
	KC.flushErrors("client_shop_mobile")
end)

----------------------------------------------------------------------------------------------------
-- client_shop_portrait (phone world)
----------------------------------------------------------------------------------------------------
S.client_shop_portrait = guarded("client_shop_portrait", function()
	local KC = G.KC()
	local Shop = G.req("client/Controllers/ShopController")
	if not T.check(type(Shop) == "table" and type(Shop.Open) == "function", "shop portrait: ShopController loads") then
		return
	end
	local saved = G.begin()
	G.createAll()
	for _, sz in ipairs({ { 390, 844 }, { 360, 640 } }) do
		local label = fmt("shop portrait %dx%d", sz[1], sz[2])
		RedoGeom.at(sz[1], sz[2], true, label, function()
			Shop.Open({ Tab = "Packs" })
			G.advance(0.6)
			local win = G.win()
			T.check(Shop.IsOpen() and Shop.Portrait() and Shop.Layout() == "Portrait", label .. ": the Portrait layout", tostring(Shop.Layout()))
			local header = win and win:FindFirstChild("Header")
			local title, gems, tok = header and header:FindFirstChild("Title"), header and header:FindFirstChild("Balance_Gems"), header and header:FindFirstChild("Balance_Tokens")
			T.check(title and gems and tok and G.box(gems).y >= G.box(title).y + G.box(title).h - 1 and G.near(G.box(gems).y, G.box(tok).y),
				label .. ": two header rows (icon, Shop, X; then both balances)", title and gems and (G.d(title) .. " / " .. G.d(gems)) or "missing")
			local rail = win and win:FindFirstChild("Rail")
			local bad, y = {}, nil
			for _, name in ipairs(TABS) do
				local tab = rail and rail:FindFirstChild("Tab_" .. name)
				local b = tab and G.rel(tab, win)
				if not (b and G.near(b.w, 64) and G.near(b.h, 56) and (y == nil or G.near(b.y, y))) then
					bad[#bad + 1] = b and fmt("%s %.0f,%.0f %.0fx%.0f", name, b.x, b.y, b.w, b.h) or (name .. " missing")
				end
				y = y or (b and b.y)
			end
			T.check(#bad == 0, label .. ": the rail is one row of five 64 x 56 tabs", table.concat(bad, "; "))
			for _, tab in ipairs({ "Gems", "Packs", "Passes", "Boosts" }) do
				Shop.Open({ Tab = tab })
				G.advance(0.3)
				local page = G.body():FindFirstChild("Page_" .. tab)
				local items = G.pageItems(page)
				local list, prev = true, nil
				for _, it in ipairs(items) do
					local b = G.rel(it, G.body())
					if prev and not (b.y > prev.y and G.near(b.x, prev.x, 2)) and it.Parent == items[1].Parent then
						list = false
					end
					if it.Parent == items[1].Parent then
						prev = b
					end
				end
				T.check(#items >= 1 and list, label .. " " .. tab .. ": a vertical list", #items .. " items")
				RedoGeom.check(win, label .. " " .. tab, { MinText = 15, MinTarget = 44, NoOverlap = G.noOverlapNames() })
			end
			Shop.Close()
			G.advance(0.3)
		end)
	end
	G.finish(saved)
	KC.flushErrors("client_shop_portrait")
end)

return S
