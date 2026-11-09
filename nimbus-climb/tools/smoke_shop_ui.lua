-- smoke_shop_ui.lua: lobby-shop Tasks 21-23 (spec 16.3 "Who owns it", "Tabs and items", "Window", "Eggs tab", "Gems tab",
-- "Packs, Passes, Boosts", "Hooks and every opener"; 16.1 ribbons, BEST VALUE, the Chest line, the token-grant lock): the
-- Shop window A (client/Controllers/ShopController, moved from StoreController), its Eggs page (client/UI/ShopEggs) and its
-- Gems page (client/UI/ShopGems). Loaded by tools/smoke.py in the CLIENT and PHONE worlds (Task 23 extends this file):
--   client_shop_window   (1920x1080) NimbusShop (order 19, IgnoreGuiInset, not reset on spawn) > ShopWindow = NeonKit.BigRect
--                        1540x910; the rail's five tabs in order at x 18, y 16 + i * 92 (+44 from Tab_Packs) under the
--                        header, 224 x 80, the RobuxDivider between Gems and Packs; the header (Title "Shop", Balance_Gems
--                        a GemIcon.Amount, Balance_Tokens, CloseButton, no Cash pill); NormalizeTab for every alias; Open
--                        { Tab = "Currency" } -> Gems, { Tab = "Passes" } -> Passes; the first open shows Eggs (Task 22), a
--                        re-open the last tab; Packs / Passes / Boosts hold every StoreCatalog card of their tab inside the
--                        content box (x 262, width 1240); Tab_Packs.Dot while the Starter Pack is on sale and unbought;
--                        Tab_Eggs is the real Eggs page (Task 22); WindowOpened("Shop") once per open; SetTouchHidden("Shop",
--                        true) on a touch device; the cursor free with mouse lock on; Esc closes; NimbusShopBack only while
--                        open, above NimbusDash, B closes and returns Sink
--   client_shop_eggs     (1920x1080, Task 22) ShopCard_Secret (the hero: 1240 x 240 at (0, 16), "Secret Roulette", its odds
--                        = GetRarityOdds("Secret"), the PityChip from SecretPityLeft, SPIN + GemIcon + 500, the hint); the
--                        four machine cards at (i * 314, 276) 298 x 550 with their Odds_* rows = GetRarityOdds(id), Spin /
--                        Spin3 / SpinGems prices; NoOdds; every button's BuyRoulette through EggStage.Request; Pending /
--                        failure / Short / Locked / Loading states; Open({ RouletteId }) focus; Currency alone keeps the
--                        tab; texts >= 18 px; the rail's Fast hatch; MenuController.IsOpen(); closes on MenuController.Close()
--                        and InMatch; WindowOpened("Shop") once per open; the tutorial card folds
--   client_shop_gems     (1920x1080, 1280x720, 844x390, 390x844) the gem packs and names from Config; the ribbons and BEST
--                        VALUE computed from the prices shown (Config Robux, a changed Robux, a live PriceInRobux); Id 0 =
--                        the Config Robux on an inactive button with "Coming soon" ("PREVIEW" under StorePreview); a created
--                        pack buys through StoreRequest("Buy", "Gems<i>"); the hero's ChestLine; every PotionState; the
--                        token packs with the computed BEST VALUE and no % ribbon; the token-grant lock (TokenPack_1..3 and
--                        Card_Pro) while PaidRandomItemsRestricted is not false; 1280x720 reachability; the phone row of
--                        eight tiles with its Fade; the portrait list; no gem glyph text
--   client_shop_sizes    (1280x720, 1366x768, 1920x1080, 2560x1440) ShopWindow = NeonKit.BigRect (design 1296 x 759,
--                        1383 x 810, 1540 x 910, 1540 x 910 at 1.25); the Compact rail at the first two, PC at the others;
--                        every card of Eggs, Gems, Packs, Passes and Boosts reachable inside Body by scrolling; the Eggs
--                        page's fit rule (Task 22: the reference layout at 1920x1080, the shrunk one scrolling vertically at
--                        1280x720 / 1366x768)
--   client_shop_mobile   (phone world: 844x390, 740x360, 667x375, 640x360) ShopWindow = BigRect; rail 104 wide; tabs by body
--                        (104 x 48 at 6 + i * 54 with a 280 body, 104 x 44 at 4 + i * 49 under 276); RedoGeom.check on every
--                        tab; the Eggs row (Task 22: the Secret card 200 wide, then four 166 wide at 208 + i * 174, every
--                        card min(266, body - 12) tall, Spin3's short total, odds eggs >= 30 px); big balances (Review
--                        Focus 6); resize while open (Review Focus 1)
--   client_shop_portrait (phone world: 390x844, 360x640) two header rows, the rail as one row of five 64 x 56 tabs, a
--                        vertical list on every tab (Eggs: full-width cards, the odds a 2 x 2 grid), RedoGeom.check
--   client_shop_openers  (1920x1080, Task 23: spec 16.3 "Openers", "Tutorial") a server OpenPanel("Shop", { Tab = "Eggs" })
--                        -> Eggs; { Tab = "Roulette", RouletteId = "Storm" } -> ShopCard_Storm focused; { RouletteId =
--                        "Secret", Currency = "Gems" } -> ShopCard_Secret focused; OpenPanel("Store", { Tab = "Passes" }) ->
--                        Passes; PillButton_Shop: the first press of a session -> Eggs, then the last tab, a press while
--                        open closes it; PetsController's OpenShop -> Eggs; with the tutorial's shop step active the pill and
--                        OpenPanel("Shop", ...) each complete ShopOpened once, the world arrow unchanged, no ring on the pill
--   client_shop_secret_lock (shop-area spec 16.17.3; 1920x1080, 1280x720, 844x390, 640x360, 360x640) the Secret card away
--                        from the Storm Altar: CardState "Altar", SPIN hidden and a blue TRAVEL (compass glyph, no price) in
--                        its box, the AltarChip "Available at the Storm Altar" ("At the Storm Altar" on a phone) in the pity
--                        chip's place, the Dim over the card (under the chip / TRAVEL / hint), the hint "Secret rolls happen at
--                        the Storm Altar", no pulse; a TRAVEL mash sends one QuickTravel("Altar") and closes the Shop; at the
--                        altar today's card; FromAltar unlocks until Close; walking to / away from the island follows on the
--                        next Shop tick; Locked wins, Altar before Loading; RedoGeom on every size
-- shop-area 16.17.3: G.begin pins ShopEggs._AtAltar = true (the older scenarios test the card as it reads at the altar).
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
	"XpPassState", "Gems", "CloudTokens", "SecretPityLeft" }
local MACHINES = { "Cloud", "Storm", "Sky", "Celestial" }
local EGG_LOCK = "Gem roulettes are not available on this account right now."
local EGG_CHECKING = "Checking your account..."

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
-- scrolls every ScrollingFrame between o and `within` (the inner one first; clamped to its canvas, like Roblox) until o's
-- top-left is in view; true when o then lies inside `within` (Task 22: the Eggs page's card row scrolls inside its page)
function G.reach(o, within)
	local list = {}
	local sc = o.Parent
	while sc and sc ~= within do
		if sc:IsA("ScrollingFrame") then
			list[#list + 1] = sc
		end
		sc = sc.Parent
	end
	for _, s0 in ipairs(list) do
		local b, s, cp = G.box(o), G.box(s0), s0.CanvasPosition
		local k = G.scaleOf(s0)
		local maxX = math.max(0, s0.CanvasSize.X.Offset * k - s.w)
		local maxY = math.max(0, s0.CanvasSize.Y.Offset * k - s.h)
		local x = math.max(0, math.min(maxX, b.x - s.x + cp.X - 2))
		local y = math.max(0, math.min(maxY, b.y - s.y + cp.Y - 2))
		s0.CanvasPosition = Vector2.new(x, y)
		G.advance(0.05)
	end
	local ok = G.inside(G.box(o), G.box(within), 1.5)
	for _, s0 in ipairs(list) do
		s0.CanvasPosition = Vector2.new(0, 0)
	end
	if #list > 0 then
		G.advance(0.05)
	end
	return ok
end
-- the cards / tiles a page shows (Card_* on Packs / Passes / Boosts; the gem page's tiles)
function G.pageItems(page)
	local out = {}
	for _, d in ipairs(page and page:GetDescendants() or {}) do
		local n = d.Name
		if d:IsA("GuiObject") and (n:match("^Card_") or n:match("^ShopCard_") or n:match("^GemPack_%d$") or n:match("^TokenPack_%d$") or n == "GemPotion" or n == "GemHero") and G.shown(d) then
			out[#out + 1] = d
		end
	end
	return out
end

-- the egg stage closed and no request pending (a scenario never inherits another's spin)
function G.calmStage()
	local ES = G.req("client/UI/EggStage")
	if ES and type(ES.Close) == "function" then
		pcall(ES.Close)
		if type(ES._S) == "table" then
			ES._S.Pending = false
			ES._S.PendToken = (ES._S.PendToken or 0) + 1
			ES._S.LastFire = -10
		end
	end
end
-- the Eggs page's cards
function G.eggCard(id)
	return G.find(G.win(), "ShopCard_" .. id)
end
function G.eggBtn(id, name)
	local card = G.eggCard(id)
	return card and card:FindFirstChild(name, true) or nil
end
-- a spin button's price text (its "Price" label)
function G.priceOf(b)
	local p = b and b:FindFirstChild("Price", true)
	return p and tostring(p.Text) or nil
end
-- (review round 3) every spin button's row (Word, the currency icon, Price) inside its button with Roblox's real font widths:
-- RedoGeom.realWidth (Montserrat Black for the GothamBlack Button role) through ShopEggs.Metrics.MEASURE, the hook the live game
-- leaves to TextService. The mock's flat 0.5 em hid Sky's phone x3 "3,000" running ~11 px past its 74 px button onto the gem
-- button. -> { problems }, the number of prices checked. The page is repainted with the mock's measure again afterwards.
function G.spinRowsReal()
	local SE = G.req("client/UI/ShopEggs")
	local page = G.body() and G.body():FindFirstChild("Page_Eggs")
	if not (type(SE) == "table" and type(SE.Metrics) == "table" and page) then
		return { "no ShopEggs / Page_Eggs" }, 0
	end
	local saved = SE.Metrics.MEASURE
	SE.Metrics.MEASURE = function(text, size, font)
		return RedoGeom.realWidth(text, size, font)
	end
	local bad, prices = {}, 0
	local ok, err = pcall(function()
		SE.Refresh(page)
		for _, id in ipairs({ "Secret", "Cloud", "Storm", "Sky", "Celestial" }) do
			for _, name in ipairs({ "Spin", "Spin3", "SpinGems" }) do
				local b = G.eggBtn(id, name)
				if b then
					local bw = G.rel(b, b).w
					for _, part in ipairs({ "Word", "TokenIcon", "GemIcon", "Price" }) do
						local o = b:FindFirstChild(part)
						if o and o.Visible then
							prices = prices + (part == "Price" and 1 or 0)
							local r = G.rel(o, b)
							if r.x < -0.5 or r.x + r.w > bw + 0.5 then
								bad[#bad + 1] = fmt("%s.%s.%s '%s' %.1f..%.1f of %.0f", id, name, part, o:IsA("TextLabel") and tostring(o.Text) or "", r.x, r.x + r.w, bw)
							end
						end
					end
				end
			end
		end
	end)
	SE.Metrics.MEASURE = saved
	pcall(SE.Refresh, page)
	if not ok then
		bad[#bad + 1] = "error: " .. tostring(err)
	end
	return bad, prices
end
function G.spinRowsCheck(label)
	local bad, prices = G.spinRowsReal()
	T.check(#bad == 0 and prices >= 13, label .. ": Eggs: every spin button's word + currency icon + price lies inside it with the real font widths (" .. prices .. " prices)", table.concat(bad, "; "))
end
-- "60%" style: the whole percent, else one decimal
function G.pct(chance)
	local v = chance * 100
	if math.abs(v - math.floor(v + 0.5)) < 1e-6 then
		return tostring(math.floor(v + 0.5)) .. "%"
	end
	return fmt("%.1f%%", v)
end
-- the card's Odds_<Rarity> rows in order: { "Common 60%", ... } (row name, its Pct text)
function G.oddsRows(card)
	local rows = {}
	for _, d in ipairs(card and card:GetDescendants() or {}) do
		local r = d.Name:match("^Odds_(%a+)$")
		if r and d:IsA("GuiObject") and G.shown(d) then
			local pct = d:FindFirstChild("Pct", true)
			rows[#rows + 1] = { Rarity = r, Pct = pct and tostring(pct.Text) or "?", Order = d.LayoutOrder, X = d.AbsolutePosition.X, Y = d.AbsolutePosition.Y, Row = d }
		end
	end
	table.sort(rows, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		if math.abs(a.Y - b.Y) > 0.5 then
			return a.Y < b.Y
		end
		return a.X < b.X
	end)
	return rows
end
function G.wantRows(PC, id)
	local out = {}
	for _, e in ipairs(PC.GetRarityOdds(id)) do
		out[#out + 1] = e.Rarity .. " " .. G.pct(e.Chance)
	end
	return table.concat(out, ", ")
end
function G.gotRows(card)
	local out = {}
	for _, r in ipairs(G.oddsRows(card)) do
		out[#out + 1] = r.Rarity .. " " .. r.Pct
	end
	return table.concat(out, ", ")
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
	G.calmStage()
	-- shop-area 16.17.3: the scenarios written before the Secret roll moved to the Storm Altar test the card as it reads AT
	-- the altar (SPIN, the pity chip); client_shop_secret_lock sets ShopEggs._AtAltar itself. G.finish puts nil back.
	local SE = G.req("client/UI/ShopEggs")
	if SE then
		saved.AtAltar = SE._AtAltar
		SE._AtAltar = true
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
	G.calmStage()
	local SE = G.req("client/UI/ShopEggs")
	if SE then
		SE._AtAltar = saved.AtAltar
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
-- (review round 1) across ScreenGuis: the HUD Gifts button (NimbusDaily, the same DisplayOrder 19) is shown with the Shop
-- closed, hidden while it is open (it sat over Balance_Tokens / the X), and back after Close
function G.giftsCheck(Shop, tag)
	local daily = G.pg():FindFirstChild("NimbusDaily")
	local gifts = daily and daily:FindFirstChild("GiftsButton", true)
	Shop.Close()
	G.advance(0.4)
	local before = gifts ~= nil and G.shown(gifts)
	Shop.Open({ Tab = "Gems" })
	G.advance(0.4)
	local during = gifts ~= nil and G.shown(gifts)
	local over = {}
	if during then
		for _, name in ipairs({ "Balance_Tokens", "Balance_Gems", "CloseButton" }) do
			local o = G.find(G.win(), name)
			local a, b = o and G.box(o), G.box(gifts)
			if a and G.shown(o) and a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then
				over[#over + 1] = name
			end
		end
	end
	Shop.Close()
	G.advance(0.4)
	local after = gifts ~= nil and G.shown(gifts)
	T.check(before and not during and after, tag .. ": the HUD Gifts button hides while the Shop is open and is back after Close",
		fmt("before %s, during %s (over %s), after %s", tostring(before), tostring(during), table.concat(over, ", "), tostring(after)))
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
	T.eq(Shop.Tab(), "Eggs", "shop window: the first open shows Eggs (Task 22)")
	T.eq(G.count(saved.Opened, "Shop", from), 1, "shop window: WindowOpened fired 'Shop' once for the open")
	T.eq(G.count(saved.Opened, "Store", from), 0, "shop window: ...and never 'Store'")
	G.giftsCheck(Shop, "shop window 1920x1080")
	Mock.SetViewport(1366, 768)
	G.advance(0.4)
	G.giftsCheck(Shop, "shop window 1366x768")
	Mock.SetViewport(1920, 1080)
	G.advance(0.4)
	Shop.Open({ Tab = "Eggs" })
	G.advance(0.5)
	gui, win = G.gui(), G.win()
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
	T.eq(G.count(saved.Opened, "Shop", from), 1, "shop window: ...and fires WindowOpened('Shop') once")
	Shop.Open()
	G.advance(0.2)
	T.eq(G.count(saved.Opened, "Shop", from), 1, "shop window: Open() on the open Shop fires nothing more")
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
	-- Tab_Eggs is the real page (Task 22): the Shop stays open, Page_Eggs shows, MenuController has no Cloud Shop any more
	from = #saved.Opened
	G.tapTab("Eggs")
	G.advance(0.4)
	local pe = body:FindFirstChild("Page_Eggs")
	local menuGui = G.pg():FindFirstChild("NimbusMenu")
	T.check(Shop.IsOpen() and Shop.Tab() == "Eggs" and G.shown(pe) and not G.shown(body:FindFirstChild("Page_Packs")) and #saved.Opened == from,
		"shop window: Tab_Eggs shows the Shop's own Eggs page (the Shop stays open, nothing else opens)", tostring(Shop.IsOpen()) .. " / " .. tostring(Shop.Tab()))
	T.check(menuGui == nil or menuGui:FindFirstChild("Window_Shop") == nil, "shop window: MenuController has no Window_Shop any more")
	Shop.Close()
	G.advance(0.4)
	Shop.Open({ Tab = "Roulettes" })
	G.advance(0.4)
	T.check(Shop.IsOpen() and Shop.Tab() == "Eggs" and G.shown(pe), "shop window: Open({ Tab = 'Roulettes' }) opens the Shop on Eggs")
	Shop.Close()
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
-- client_shop_eggs (Task 22)
----------------------------------------------------------------------------------------------------
local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

S.client_shop_eggs = guarded("client_shop_eggs", function()
	local KC = G.KC()
	local Config = KC.env()
	local Shop = G.req("client/Controllers/ShopController")
	local SE = G.req("client/UI/ShopEggs")
	local ES = G.req("client/UI/EggStage")
	local PC = G.req("shared/PetCatalog")
	local CS = G.req("client/ClientSettings")
	local MC = G.req("client/Controllers/MenuController")
	local okApi = type(Shop) == "table" and type(SE) == "table" and type(ES) == "table" and type(PC) == "table" and type(CS) == "table" and type(MC) == "table"
	for _, fn in ipairs({ "Build", "Layout", "Refresh", "Focus", "CardState" }) do
		okApi = okApi and type(SE[fn]) == "function"
	end
	if not T.check(okApi, "shop eggs: client/UI/ShopEggs loads with its API (Build, Layout, Refresh, Focus, CardState)") then
		return
	end
	local saved = G.begin()
	G.setAttr("Gems", 5000)
	G.setAttr("CloudTokens", 50000)
	G.setAttr("SecretPityLeft", 3)
	CS.Set("FastHatch", false)
	Mock.SetViewport(1920, 1080)
	G.advance(0.8)
	local hints = {}
	local realHint = MC.Hint
	MC.Hint = function(text)
		hints[#hints + 1] = tostring(text)
	end
	local realOdds = PC.GetRarityOdds
	local roulettes = {}
	for _, r in ipairs(Config.Roulettes) do
		roulettes[r.Id] = r
	end
	local gemPrices = Config.Gems.RouletteGemPrices
	local function buys(mark)
		local out = {}
		for _, e in ipairs(KC.serverCalls("BuyRoulette", mark)) do
			out[#out + 1] = tostring(e.args[1]) .. "/" .. tostring(e.args[2]) .. "/" .. tostring(e.args[3])
		end
		return out
	end
	local function clearPending(reason)
		KC.toClient("RouletteResult", { Ok = false, Reason = reason or "Probe reason", RouletteId = "Cloud", Currency = "Tokens", Spins = 1 })
		G.advance(0.4)
	end
	local ok, err = pcall(function()
		local from = #saved.Opened
		if type(Shop._S) == "table" then
			Shop._S.Tab = nil
		end
		Shop.Open()
		G.advance(0.6)
		T.check(Shop.IsOpen() and Shop.Tab() == "Eggs", "shop eggs: a fresh session's first open shows Eggs", tostring(Shop.Tab()))
		T.eq(G.count(saved.Opened, "Shop", from), 1, "shop eggs: WindowOpened fired 'Shop' once for the open")
		local body = G.body()
		local page = body and body:FindFirstChild("Page_Eggs")
		T.check(G.shown(page), "shop eggs: Page_Eggs shows")

		-- the Secret hero
		local hero = G.eggCard("Secret")
		local hb = hero and G.rel(hero, body)
		T.check(hero ~= nil and G.shown(hero) and hero:GetAttribute("Hero") == true and G.near(hb.x, 0) and G.near(hb.y, 16) and G.near(hb.w, 1240) and G.near(hb.h, 240),
			"shop eggs: ShopCard_Secret (attribute Hero) is 1240 x 240 at (0, 16) of the content box", hero and G.d(hero) or "missing")
		T.eq(G.text(hero, "Title"), "Secret Roulette", "shop eggs: the hero reads 'Secret Roulette'")
		T.eq(G.gotRows(hero), G.wantRows(PC, "Secret"), "shop eggs: the hero's odds = PetCatalog.GetRarityOdds('Secret'), in order")
		T.eq(G.gotRows(hero), "Mythic 60%, Secret 40%", "shop eggs: ...Mythic 60%, Secret 40%")
		T.eq(G.text(hero, "PityChip"), "Secret for sure in 3 more spins", "shop eggs: PityChip for SecretPityLeft 3")
		G.setAttr("SecretPityLeft", 1)
		G.advance(0.3)
		T.eq(G.text(hero, "PityChip"), "Secret for sure on the next spin", "shop eggs: PityChip for SecretPityLeft 1")
		G.setAttr("SecretPityLeft", nil)
		G.advance(0.3)
		T.eq(G.text(hero, "PityChip"), "Loading...", "shop eggs: PityChip without SecretPityLeft reads 'Loading...'")
		G.setAttr("SecretPityLeft", 3)
		G.advance(0.3)
		local hs = G.eggBtn("Secret", "Spin")
		T.check(hs ~= nil and hs:FindFirstChild("GemIcon", true) ~= nil and G.priceOf(hs) == commas(Config.Gems.SecretRoulette.GemPrice) and G.priceOf(hs) == "500" and not G.disabled(hs),
			"shop eggs: the hero's Spin is a GemIcon + '500'", hs and tostring(G.priceOf(hs)) or "no button")
		-- shop-area 16.17.3 (rewritten): the hint was "Also at the Storm Altar"; the Secret roll happens there only now
		T.eq(G.text(hero, "Hint"), "Secret rolls happen at the Storm Altar", "shop eggs: the hero's hint")
		local hintFits, hintWhy = RedoGeom.fits(G.part(hero, "Hint"))
		T.check(hintFits, "shop eggs: ...on one line inside its box with the real font widths", hintWhy)
		T.check(G.eggBtn("Secret", "Spin3") == nil and G.eggBtn("Secret", "SpinGems") == nil, "shop eggs: the Secret card is x1 only")

		-- the four machine cards
		local bad = {}
		for i, id in ipairs(MACHINES) do
			local card = G.eggCard(id)
			local b = card and G.rel(card, body)
			if not (card and G.shown(card) and G.near(b.x, (i - 1) * 314) and G.near(b.y, 276) and G.near(b.w, 298) and G.near(b.h, 550)) then
				bad[#bad + 1] = id .. ": " .. (b and fmt("%.0f,%.0f %.0fx%.0f", b.x, b.y, b.w, b.h) or "missing")
			end
		end
		T.check(#bad == 0, "shop eggs: the four cards at (i * 314, 276) of the content box, 298 x 550", table.concat(bad, "; "))
		local rows, prices = {}, {}
		for _, id in ipairs(MACHINES) do
			local card = G.eggCard(id)
			if G.gotRows(card) ~= G.wantRows(PC, id) then
				rows[#rows + 1] = id .. ": " .. G.gotRows(card) .. " (want " .. G.wantRows(PC, id) .. ")"
			end
			local r = roulettes[id]
			local spin, s3, sg = G.eggBtn(id, "Spin"), G.eggBtn(id, "Spin3"), G.eggBtn(id, "SpinGems")
			local want = { commas(r.Price), commas(3 * r.Price), tostring(gemPrices[id]) }
			local got = { G.priceOf(spin), G.priceOf(s3), G.priceOf(sg) }
			if got[1] ~= want[1] or got[2] ~= want[2] or got[3] ~= want[3] or not (spin and spin:FindFirstChild("TokenIcon", true)) or not (s3 and s3:FindFirstChild("TokenIcon", true))
				or not (sg and sg:FindFirstChild("GemIcon", true)) then
				prices[#prices + 1] = fmt("%s: %s / %s / %s (want %s / %s / %s)", id, tostring(got[1]), tostring(got[2]), tostring(got[3]), want[1], want[2], want[3])
			end
		end
		T.check(#rows == 0, "shop eggs: every card's Odds_* rows = GetRarityOdds(id), in order and value", table.concat(rows, "; "))
		T.check(G.gotRows(G.eggCard("Celestial")):match("Secret 2%%$") ~= nil and #G.oddsRows(G.eggCard("Celestial")) == 4, "shop eggs: Celestial has four rows, the last Secret 2%",
			G.gotRows(G.eggCard("Celestial")))
		T.check(#prices == 0, "shop eggs: Spin = token icon + the price, Spin3 = token icon + 3x, SpinGems = GemIcon + 20 / 40 / 60 / 180", table.concat(prices, "; "))
		T.check(G.eggBtn("Cloud", "Spin3") and tostring(G.texts(G.eggBtn("Cloud", "Spin3"))):find("x3", 1, true) ~= nil, "shop eggs: Spin3 reads 'x3'")
		local hints1 = {}
		for _, id in ipairs(MACHINES) do
			hints1[#hints1 + 1] = tostring(G.text(G.eggCard(id), "Hint"))
		end
		T.eq(table.concat(hints1, " | "), "Gems: same odds | Gems: same odds | Gems: same odds | Gems: same odds", "shop eggs: every machine card's hint reads 'Gems: same odds'")

		-- a card without odds cannot spin
		PC.GetRarityOdds = function(id)
			if id == "Storm" then
				return {}
			end
			return realOdds(id)
		end
		G.advance(1.2)
		local storm = G.eggCard("Storm")
		local stB = { G.eggBtn("Storm", "Spin"), G.eggBtn("Storm", "Spin3"), G.eggBtn("Storm", "SpinGems") }
		T.check(G.text(storm, "NoOdds") == "Odds unavailable" and G.disabled(stB[1]) and G.disabled(stB[2]) and G.disabled(stB[3]) and SE.CardState("Storm") == "NoOdds",
			"shop eggs: GetRarityOdds('Storm') empty -> 'Odds unavailable', its buttons inactive, CardState NoOdds", tostring(G.text(storm, "NoOdds")) .. " / " .. tostring(SE.CardState("Storm")))
		local m0 = #Mock.RemoteLog
		G.tap(stB[1])
		T.eq(#buys(m0), 0, "shop eggs: ...and a tap sends nothing")
		PC.GetRarityOdds = realOdds
		G.advance(1.2)
		T.check(not G.shown(storm:FindFirstChild("NoOdds", true)) and #G.oddsRows(storm) == 4 and not G.disabled(G.eggBtn("Storm", "Spin")) and SE.CardState("Storm") == "Ready",
			"shop eggs: ...and the odds come back with the catalog")

		-- every button sends its BuyRoulette once through EggStage.Request; pending dims everything; a failure re-enables
		local cases = {
			{ "Cloud", "Spin", "Cloud/Tokens/1" }, { "Cloud", "Spin3", "Cloud/Tokens/3" }, { "Celestial", "SpinGems", "Celestial/Gems/1" }, { "Secret", "Spin", "Secret/Gems/1" },
		}
		for n, c in ipairs(cases) do
			local mark = #Mock.RemoteLog
			local btn = G.eggBtn(c[1], c[2])
			G.tap(btn)
			local sent = buys(mark)
			T.check(#sent == 1 and sent[1] == c[3], "shop eggs: " .. c[1] .. " " .. c[2] .. " -> one BuyRoulette(" .. c[3]:gsub("/", ", ") .. ")", table.concat(sent, "; "))
			if n == 1 then
				local states, lit = {}, {}
				for _, id in ipairs({ "Secret", "Cloud", "Storm", "Sky", "Celestial" }) do
					states[#states + 1] = tostring(SE.CardState(id))
					for _, name in ipairs({ "Spin", "Spin3", "SpinGems" }) do
						local b = G.eggBtn(id, name)
						if b and not G.disabled(b) then
							lit[#lit + 1] = id .. "." .. name
						end
					end
				end
				T.eq(table.concat(states, " "), "Pending Pending Pending Pending Pending", "shop eggs: while pending every CardState is Pending")
				T.check(#lit == 0, "shop eggs: ...and every spin button is dimmed", table.concat(lit, ", "))
				G.tap(G.eggBtn("Storm", "Spin"))
				T.eq(#buys(mark), 1, "shop eggs: ...a second tap while pending sends nothing")
				local h0 = #hints
				clearPending("You need more Cloud Tokens.")
				local states2 = {}
				for _, id in ipairs({ "Secret", "Cloud", "Storm", "Sky", "Celestial" }) do
					states2[#states2 + 1] = tostring(SE.CardState(id))
				end
				T.check(table.concat(states2, " ") == "Ready Ready Ready Ready Ready" and not G.disabled(G.eggBtn("Cloud", "Spin")) and #hints == h0 + 1 and hints[#hints] == "You need more Cloud Tokens.",
					"shop eggs: a failure answer re-enables every card at once, with one toast of the reason", table.concat(states2, " ") .. " / " .. tostring(hints[#hints]))
			else
				clearPending()
			end
			G.advance(0.4)
		end
		T.eq(saved.Prompts, 0, "shop eggs: the client never prompts a purchase")

		-- Short: the price kept, the amount red, a tap toasts "not enough" and sends nothing
		G.setAttr("CloudTokens", 4000)
		G.advance(1.2)
		local cel = G.eggBtn("Celestial", "Spin")
		local celPrice = cel and cel:FindFirstChild("Price", true)
		T.check(SE.CardState("Celestial") == "Short" and G.priceOf(cel) == "5,000" and celPrice and celPrice.TextColor3.R > 0.8 and celPrice.TextColor3.G < 0.5 and not G.disabled(cel),
			"shop eggs: Short (4,000 tokens, Celestial 5,000): the price kept, drawn red, the button still taps", tostring(SE.CardState("Celestial")) .. " / " .. tostring(G.priceOf(cel)))
		T.eq(SE.CardState("Cloud"), "Ready", "shop eggs: ...while Cloud (50) stays Ready")
		local mS, hS = #Mock.RemoteLog, #hints
		G.tap(cel)
		T.check(#buys(mS) == 0 and #hints == hS + 1 and hints[#hints]:find("You need", 1, true) ~= nil, "shop eggs: a Short tap shows the 'not enough' toast and sends nothing", tostring(hints[#hints]))
		G.setAttr("CloudTokens", 50000)
		G.advance(1.2)

		-- Locked (restricted / unknown): the gem buttons and the whole Secret card
		local function lockCase(value, text, tag)
			G.setAttr("PaidRandomItemsRestricted", value)
			G.advance(1.2)
			local lockedGems = {}
			for _, id in ipairs(MACHINES) do
				local sg = G.eggBtn(id, "SpinGems")
				if not (sg and G.disabled(sg) and tostring(G.texts(sg)):find("Locked", 1, true)) or SE.CardState(id, "SpinGems") ~= "Locked" then
					lockedGems[#lockedGems + 1] = id .. ": " .. (sg and G.texts(sg) or "none") .. " " .. tostring(SE.CardState(id, "SpinGems"))
				end
			end
			T.check(#lockedGems == 0, "shop eggs: " .. tag .. ": every SpinGems reads 'Locked', inactive (CardState Locked)", table.concat(lockedGems, "; "))
			local hsp = G.eggBtn("Secret", "Spin")
			T.check(G.disabled(hsp) and SE.CardState("Secret") == "Locked" and G.texts(G.eggCard("Secret")):find(text, 1, true) ~= nil,
				"shop eggs: " .. tag .. ": the Secret card shows '" .. text .. "' and its Spin is inactive", G.texts(G.eggCard("Secret")))
			T.check(not G.disabled(G.eggBtn("Cloud", "Spin")) and not G.disabled(G.eggBtn("Sky", "Spin3")) and SE.CardState("Cloud") == "Ready", "shop eggs: " .. tag .. ": the token spins stay open")
			local mL = #Mock.RemoteLog
			G.tap(hsp)
			G.tap(G.eggBtn("Cloud", "SpinGems"))
			T.eq(#buys(mL), 0, "shop eggs: " .. tag .. ": a tap on a locked gem button sends nothing")
		end
		lockCase(true, EGG_LOCK, "restricted")
		lockCase(nil, EGG_CHECKING, "unknown")
		G.setAttr("PaidRandomItemsRestricted", false)
		G.advance(1.2)

		-- Loading (no GemsSettled): the gem buttons and the Secret card
		G.setAttr("GemsSettled", nil)
		G.advance(1.2)
		local loading = {}
		for _, id in ipairs(MACHINES) do
			local sg = G.eggBtn(id, "SpinGems")
			if not (sg and G.disabled(sg) and tostring(G.texts(sg)):find("Loading...", 1, true)) then
				loading[#loading + 1] = id .. ": " .. (sg and G.texts(sg) or "none")
			end
		end
		T.check(#loading == 0, "shop eggs: no GemsSettled: every SpinGems reads 'Loading...', inactive", table.concat(loading, "; "))
		T.check(SE.CardState("Secret") == "Loading" and G.disabled(G.eggBtn("Secret", "Spin")) and G.texts(G.eggBtn("Secret", "Spin")):find("Loading...", 1, true) ~= nil
			and G.text(hero, "PityChip") == "Loading...", "shop eggs: ...the Secret card reads 'Loading...' (its Spin and its chip)", G.texts(G.eggCard("Secret")))
		T.check(not G.disabled(G.eggBtn("Cloud", "Spin")), "shop eggs: ...the token spins are not held")
		G.setAttr("GemsSettled", true)
		G.advance(1.2)

		-- (review round 1, spec 16.3) the Secret SPIN's pulse: a tween toward Scale 1.04 every 2.5 s on High while that button
		-- can be tapped; never while it is Locked or Loading (the scale rests at 1); none on Low; Scale 1 after Close
		local GQ = G.req("client/GraphicsQuality")
		local realEffective = GQ and GQ.Effective
		local function pulseScale()
			return SE.HeroPulse(page) or SE.HeroPulse()
		end
		local function pulsesWithin(seconds)
			local frames, t = 0, 0
			local target = pulseScale()
			while t < seconds - 1e-6 do
				G.advance(0.05)
				t = t + 0.05
				for tw in pairs(Mock.ActiveTweens) do
					local goal = Mock.TweenGoals(tw).Scale
					if target ~= nil and tw.Instance == target and type(goal) == "number" and abs(goal - 1.04) < 1e-6 then
						frames = frames + 1
						break
					end
				end
			end
			return frames
		end
		local function reopen()
			Shop.Close()
			G.advance(0.3)
			Shop.Open({ Tab = "Eggs" })
			G.advance(0.3)
		end
		reopen()
		T.check(pulseScale() ~= nil and SE.CardState("Secret") == "Ready" and pulsesWithin(3) > 0, "shop eggs pulse: High, the Secret SPIN ready: it pulses toward Scale 1.04 within 3 s")
		G.setAttr("PaidRandomItemsRestricted", true)
		G.advance(0.8)
		local lockedFrames = pulsesWithin(3)
		T.check(lockedFrames == 0 and pulseScale().Scale == 1, "shop eggs pulse: ...never while the Secret SPIN is Locked (Scale rests at 1)", lockedFrames .. " frames, Scale " .. tostring(pulseScale().Scale))
		G.setAttr("PaidRandomItemsRestricted", false)
		G.setAttr("GemsSettled", nil)
		G.advance(0.8)
		local loadingFrames = pulsesWithin(3)
		T.check(loadingFrames == 0 and pulseScale().Scale == 1, "shop eggs pulse: ...never while it reads Loading...", loadingFrames .. " frames")
		G.setAttr("GemsSettled", true)
		G.advance(0.3)
		T.check(pulsesWithin(3) > 0, "shop eggs pulse: ...and it starts again by itself once the hold ends")
		if GQ then
			GQ.Effective = function()
				return "Low"
			end
			reopen()
			local lowFrames = pulsesWithin(3)
			T.check(lowFrames == 0 and pulseScale().Scale == 1, "shop eggs pulse: Low graphics: no pulse", lowFrames .. " frames")
			GQ.Effective = realEffective
		end
		reopen()
		G.advance(2.6)
		Shop.Close()
		G.advance(0.4)
		T.check(pulseScale().Scale == 1, "shop eggs pulse: after Close the Secret SPIN's scale is 1", tostring(pulseScale().Scale))
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.6)

		-- Open({ RouletteId }) focuses the card: inside the window, outlined for 2.6 s; Currency alone keeps the tab
		Shop.Open({ Tab = "Packs" })
		G.advance(0.4)
		Shop.Open({ RouletteId = "Secret", Currency = "Gems" })
		G.advance(0.3)
		T.check(Shop.Tab() == "Eggs" and hero:GetAttribute("Focused") == true and G.inside(G.box(hero), G.box(G.win()), 1), "shop eggs: Open({ RouletteId = 'Secret', Currency = 'Gems' }) -> Eggs, ShopCard_Secret inside the window and outlined",
			tostring(Shop.Tab()) .. " / " .. tostring(hero:GetAttribute("Focused")))
		G.advance(2.5)
		T.check(hero:GetAttribute("Focused") ~= true, "shop eggs: ...the outline is gone after 2.6 s")
		Shop.Open({ RouletteId = "Celestial" })
		G.advance(0.3)
		local celCard = G.eggCard("Celestial")
		T.check(celCard:GetAttribute("Focused") == true and G.inside(G.box(celCard), G.box(G.body()), 1), "shop eggs: Open({ RouletteId = 'Celestial' }) outlines the Celestial card, fully inside the body")
		G.advance(2.8)
		Shop.Open({ Tab = "Packs" })
		G.advance(0.3)
		Shop.Open({ Currency = "Gems" })
		G.advance(0.3)
		T.eq(Shop.Tab(), "Packs", "shop eggs: { Currency = 'Gems' } alone keeps the tab")
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.4)

		-- every text >= 18 px, every target >= 44 px, inside the screen
		RedoGeom.check(G.win(), "shop eggs 1920x1080", { MinText = 18, MinTarget = 44, NoOverlap = G.noOverlapNames() })
		T.eq(#G.glyphs(G.gui()), 0, "shop eggs: no gem glyph text in NimbusShop")

		-- the rail's Fast hatch (PC, Eggs only)
		local fast = G.find(G.win():FindFirstChild("Rail"), "FastHatch")
		local fb = fast and G.rel(fast, G.win())
		T.check(fast ~= nil and G.shown(fast) and G.near(fb.x, 18) and G.near(fb.w, 224) and G.near(fb.h, 52), "shop eggs: the rail's FastHatch toggle (224 x 52 at x 18) shows on Eggs", fast and G.d(fast) or "none")
		local c0 = #KC.serverCalls("SettingsSet")
		G.tap(fast)
		T.eq(#KC.serverCalls("SettingsSet") - c0, 0, "shop eggs: the toggle sends nothing at once")
		G.advance(0.4)
		local sets = KC.serverCalls("SettingsSet")
		T.check(#sets - c0 == 1 and sets[#sets].args[1] == "FastHatch" and sets[#sets].args[2] == true and CS.Get("FastHatch") == true and fast:GetAttribute("On") == true,
			"shop eggs: ...then one SettingsSet('FastHatch', true) 0.4 s later", (#sets - c0) .. " calls")
		G.tapTab("Gems")
		T.check(not G.shown(fast), "shop eggs: the toggle is not on the Gems tab")
		G.tapTab("Eggs")
		CS.Set("FastHatch", false)
		G.advance(0.6)

		-- MenuController.IsOpen(): the Shop and the stage; MenuController.Close() and InMatch close it
		T.check(MC.IsOpen() == true, "shop eggs: MenuController.IsOpen() is true while the Shop is open")
		KC.toClient("RouletteResult", { Ok = true, RouletteId = "Cloud", Currency = "Tokens", Spins = 1, PetId = PC.RarityPool("Cloud", "Common")[1].Id, IsNew = false, Count = 2,
			Pulls = { { PetId = PC.RarityPool("Cloud", "Common")[1].Id, Rarity = "Common", IsNew = false, Count = 2, PoolSize = 1 } } })
		G.advance(0.3)
		T.check(ES.IsShowing() and MC.IsOpen() == true, "shop eggs: ...and while the egg stage shows")
		ES.Close()
		G.advance(0.3)
		MC.Close()
		G.advance(0.3)
		T.check(not Shop.IsOpen() and MC.IsOpen() == false, "shop eggs: MenuController.Close() closes the Shop")
		Shop.Open()
		G.advance(0.3)
		G.setAttr("InMatch", true)
		G.advance(0.3)
		T.check(not Shop.IsOpen(), "shop eggs: InMatch closes the Shop")
		G.setAttr("InMatch", false)
		G.advance(0.4)

		-- the tutorial card folds while the Shop is open
		local TC = G.req("client/Controllers/TutorialController")
		local Steps = G.req("shared/TutorialSteps")
		local index = nil
		for i, st in ipairs(Steps and Steps.Steps or {}) do
			if st.Id == "shop" then
				index = i
			end
		end
		if T.check(TC ~= nil and index ~= nil, "shop eggs: (setup) the tutorial's shop step exists") then
			local tutSaved = type(TC.GetState) == "function" and TC.GetState() or nil
			local step = Steps.Steps[index]
			KC.toClient("TutorialState", {
				Step = index, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = tostring(step.Text), Target = step.Target,
				CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, AlsoNext = step.AlsoNext == true,
				Chapter = step.Chapter, Done = false, Completed = false, Skipped = false, Reward = 0,
			})
			G.advance(2.5) -- (the card's first show waits TutorialController's FIRST_SHOW_DELAY, 1.2 s)
			local tut = G.pg():FindFirstChild("NimbusTutorial")
			local main = tut and G.find(tut, "Main")
			local before = main ~= nil and G.shown(main)
			Shop.Open()
			G.advance(0.8)
			local during = main ~= nil and G.shown(main)
			T.check(before and not during, "shop eggs: the tutorial card folds while the Shop is open", "before " .. tostring(before) .. ", during " .. tostring(during))
			Shop.Close()
			G.advance(0.6)
			if tutSaved then
				KC.toClient("TutorialState", tutSaved)
			else
				KC.toClient("TutorialState", { Done = true, Step = #Steps.Steps, Total = #Steps.Steps })
			end
			G.advance(0.6)
		end
	end)
	if not ok then
		T.fail("shop eggs: scenario error", tostring(err))
	end
	PC.GetRarityOdds = realOdds
	MC.Hint = realHint
	CS.Set("FastHatch", false)
	G.finish(saved)
	KC.flushErrors("client_shop_eggs")
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
		-- the Eggs page's fit rule (Task 22): the reference layout while the body holds 826 px, else the shrunk one, scrolling
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.3)
		local eggsPage = G.body():FindFirstChild("Page_Eggs")
		local eggScroll = eggsPage and G.find(eggsPage, "Scroll")
		local hero, cloud = G.eggCard("Secret"), G.eggCard("Cloud")
		if T.check(hero ~= nil and cloud ~= nil and eggScroll ~= nil and eggScroll:IsA("ScrollingFrame"), label .. ": Eggs: the hero, the cards and the page's Scroll exist") then
			local bodyH = G.rel(G.body(), win).h
			local heroH, cardH = G.rel(hero, win).h, G.rel(cloud, win).h
			local canvasH = eggScroll.CanvasSize.Y.Offset
			if sz[5] == "PC" then
				T.check(G.near(heroH, 240) and G.near(cardH, 550) and canvasH <= bodyH + 0.5 and G.near(G.rel(cloud, G.body()).y, 276),
					label .. ": Eggs: the reference layout (hero 240, cards 550 at y 276), no vertical scroll", fmt("hero %.0f, card %.0f, canvas %.0f, body %.0f", heroH, cardH, canvasH, bodyH))
			else
				T.check(G.near(heroH, 200) and G.near(cardH, 516) and canvasH > bodyH + 0.5,
					label .. ": Eggs: the shrunk layout (hero 200, cards 516) and the page scrolls vertically", fmt("hero %.0f, card %.0f, canvas %.0f, body %.0f", heroH, cardH, canvasH, bodyH))
			end
		end
		G.spinRowsCheck(label)
		local unreached, count = {}, 0
		for _, page in ipairs({ "Eggs", "Gems", "Packs", "Passes", "Boosts" }) do
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
		T.check(count >= 21 and #unreached == 0, label .. ": every card on Eggs, Gems, Packs, Passes and Boosts is reachable inside Body", count .. " cards; " .. table.concat(unreached, "; "))
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.3)
		RedoGeom.check(win, label .. " Eggs", { MinText = 14, MinTarget = 44, NoOverlap = G.noOverlapNames() })
		Shop.Open({ Tab = "Boosts" })
		G.advance(0.3)
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
			if sz[1] == 844 then
				G.giftsCheck(Shop, label) -- (review round 1: the Gifts button covered Balance_Tokens here)
			end
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
			for _, tab in ipairs({ "Eggs", "Gems", "Packs", "Passes", "Boosts" }) do
				Shop.Open({ Tab = tab })
				G.advance(0.3)
				RedoGeom.check(win, label .. " " .. tab, { MinText = 15, MinTarget = 44, NoOverlap = G.noOverlapNames() })
			end
			-- the Eggs row (Task 22): the Secret card 200 wide first, then four cards 166 wide at x = 208 + i * 174, every card
			-- min(266, body - 12) tall; Spin3's short total; every odds egg >= 30 px
			Shop.Open({ Tab = "Eggs" })
			G.advance(0.3)
			local th = math.min(266, bodyH - 12)
			local row = {}
			local hero = G.eggCard("Secret")
			local hb = hero and G.rel(hero, body)
			if not (hb and G.near(hb.x, 0) and G.near(hb.w, 200) and G.near(hb.h, th)) then
				row[#row + 1] = "Secret " .. (hb and fmt("%.0f,%.0f %.0fx%.0f", hb.x, hb.y, hb.w, hb.h) or "missing")
			end
			local y0 = hb and hb.y
			local shortTotals, smallEggs = {}, {}
			-- (review round 3) the phone's x3 total is Theme.ShortNumber(3 * price, 1000): "3K", not "3,000", which ran past the
			-- 74 px button in Roblox's Montserrat Black
			local wantShort = { Cloud = "150", Storm = "750", Sky = "3K", Celestial = "15K" }
			for i, id in ipairs(MACHINES) do
				local card = G.eggCard(id)
				local b = card and G.rel(card, body)
				if not (b and G.near(b.x, 208 + (i - 1) * 174) and G.near(b.w, 166) and G.near(b.h, th) and (y0 == nil or G.near(b.y, y0))) then
					row[#row + 1] = id .. " " .. (b and fmt("%.0f,%.0f %.0fx%.0f", b.x, b.y, b.w, b.h) or "missing")
				end
				local s3 = G.eggBtn(id, "Spin3")
				local txt = s3 and G.texts(s3) or ""
				if not (txt:find("x3", 1, true) and G.priceOf(s3) == wantShort[id] and s3:FindFirstChild("TokenIcon", true)) then
					shortTotals[#shortTotals + 1] = id .. ": " .. txt
				end
			end
			for _, id in ipairs({ "Secret", "Cloud", "Storm", "Sky", "Celestial" }) do
				for _, r in ipairs(G.oddsRows(G.eggCard(id))) do
					local egg = r.Row:FindFirstChild("Egg", true)
					if not (egg and egg.AbsoluteSize.Y >= 30 - 0.5) then
						smallEggs[#smallEggs + 1] = id .. "." .. r.Rarity .. " " .. (egg and fmt("%.1f", egg.AbsoluteSize.Y) or "no egg")
					end
				end
			end
			T.check(#row == 0, fmt("%s: Eggs: the Secret card 200 wide, then four cards 166 wide at x = 208 + i * 174, all %d tall", label, th), table.concat(row, "; "))
			T.check(#shortTotals == 0, label .. ": Eggs: Spin3 reads 'x3' + token icon + Theme.ShortNumber(3 * price, 1000) (150, 750, 3K, 15K)", table.concat(shortTotals, "; "))
			G.spinRowsCheck(label)
			T.check(#smallEggs == 0, label .. ": Eggs: every odds egg is at least 30 px", table.concat(smallEggs, "; "))
			if sz[1] == 844 then
				local fade = G.find(G.find(body, "Page_Eggs"), "Fade")
				T.check(fade ~= nil and G.shown(fade), label .. ": Eggs: the right Fade shows while more of the row is to the right", fade and G.d(fade) or "none")
				Shop.Open({ RouletteId = "Celestial" })
				G.advance(0.3)
				local cel = G.eggCard("Celestial")
				T.check(cel ~= nil and cel:GetAttribute("Focused") == true and G.inside(G.box(cel), G.box(body), 1), label .. ": Eggs: Open({ RouletteId = 'Celestial' }) scrolls the card fully into view, outlined",
					cel and G.d(cel) or "none")
				G.advance(2.8)
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
			-- the Eggs list (Task 22): full-width cards (the Secret card 200 tall on top, the machines 250), the odds a 2 x 2 grid
			Shop.Open({ Tab = "Eggs" })
			G.advance(0.3)
			local listBad = {}
			local bw = G.rel(G.body(), G.body()).w
			local lastY = -1
			for _, id in ipairs({ "Secret", "Cloud", "Storm", "Sky", "Celestial" }) do
				local card = G.eggCard(id)
				local b = card and G.rel(card, G.body())
				local wantH = id == "Secret" and 200 or 250
				if not (b and b.y > lastY and b.w >= bw - 16 and G.near(b.h, wantH)) then
					listBad[#listBad + 1] = id .. " " .. (b and fmt("%.0f,%.0f %.0fx%.0f", b.x, b.y, b.w, b.h) or "missing")
				end
				lastY = b and b.y or lastY
			end
			T.check(#listBad == 0, label .. ": Eggs: full-width cards in a vertical list (Secret 200 tall first, the machines 250)", table.concat(listBad, "; "))
			G.spinRowsCheck(label)
			local grid = G.oddsRows(G.eggCard("Cloud"))
			local xs, ys = {}, {}
			for _, r in ipairs(grid) do
				xs[math.floor(r.X + 0.5)] = true
				ys[math.floor(r.Y + 0.5)] = true
			end
			local nx, ny = 0, 0
			for _ in pairs(xs) do
				nx = nx + 1
			end
			for _ in pairs(ys) do
				ny = ny + 1
			end
			T.check(#grid == 4 and nx == 2 and ny == 2, label .. ": Eggs: Cloud's four odds as a 2 x 2 grid", #grid .. " rows, " .. nx .. " columns x " .. ny .. " rows")
			-- spec 16.3: each portrait odds cell is the egg 30 + the percent 15 (no rarity word: it would not fit the cell)
			local cellBad = {}
			for _, id in ipairs({ "Secret", "Cloud", "Storm", "Sky", "Celestial" }) do
				for _, r in ipairs(G.oddsRows(G.eggCard(id))) do
					local egg, word, pct = r.Row:FindFirstChild("Egg"), r.Row:FindFirstChild("Word"), r.Row:FindFirstChild("Pct")
					local eb, pb, cb = egg and G.rel(egg, r.Row), pct and G.rel(pct, r.Row), G.rel(r.Row, r.Row)
					if not (egg and pct and G.near(eb.h, 30) and pct.TextSize == 15 and not G.shown(word) and pb.x >= eb.x + eb.w - 1 and pb.x + pb.w <= cb.w + 1) then
						cellBad[#cellBad + 1] = id .. "/" .. r.Rarity .. (word and G.shown(word) and " (word shown)" or "")
					end
				end
			end
			T.check(#cellBad == 0, label .. ": Eggs: every odds cell is the egg 30 + the percent 15, no rarity word", table.concat(cellBad, ", "))
			-- the PityChip keeps to one line: "Secret for sure in N more spins" while it fits the chip, else "Secret in N"
			G.setAttr("GemsSettled", true)
			G.setAttr("PaidRandomItemsRestricted", false)
			G.setAttr("SecretPityLeft", 23)
			G.advance(0.3)
			local chip = G.eggCard("Secret") and G.eggCard("Secret"):FindFirstChild("PityChip", true)
			local chipText = chip and tostring(chip.Text) or ""
			local chipW = chip and chip.Size.X.Offset or 0
			local Text = game:GetService("TextService")
			local need = chip and Text:GetTextSize(chipText, chip.TextSize, chip.Font, Vector2.new(10000, 1000)).X + 16 or math.huge
			local longFits = chip and Text:GetTextSize("Secret for sure in 23 more spins", chip.TextSize, chip.Font, Vector2.new(10000, 1000)).X + 16 <= chipW
			T.check(chip ~= nil and G.shown(chip) and need <= chipW and chipText == (longFits and "Secret for sure in 23 more spins" or "Secret in 23"),
				label .. ": Eggs: the PityChip reads the long line when it fits its " .. chipW .. " px, else 'Secret in 23'", chipText .. " (" .. tostring(need) .. " px)")
			for _, tab in ipairs({ "Eggs", "Gems", "Packs", "Passes", "Boosts" }) do
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

----------------------------------------------------------------------------------------------------
-- client_shop_openers (Task 23, spec 16.3 "Openers", "Tutorial")
----------------------------------------------------------------------------------------------------
-- a press on the top bar's pill button (NimbusTopBar.PillButton_<name>)
function G.pill(name)
	local bar = G.pg():FindFirstChild("NimbusTopBar")
	local button = bar and bar:FindFirstChild("PillButton_" .. name, true)
	if button then
		Mock.Click(button)
	end
	G.advance(0.4)
	return button ~= nil
end
-- the tutorial's menu ring is shown (NimbusTutorialPointer.Ring) / its world guide is out (workspace.ClientFx.TutorialGuide)
function G.tutRing()
	local ptr = G.pg():FindFirstChild("NimbusTutorialPointer")
	local ring = ptr and ptr:FindFirstChild("Ring")
	return ring ~= nil and ring.Visible == true and G.shown(ring)
end
function G.tutGuide()
	local fx = workspace:FindFirstChild("ClientFx")
	return fx ~= nil and fx:FindFirstChild("TutorialGuide") ~= nil
end

S.client_shop_openers = guarded("client_shop_openers", function()
	local KC = G.KC()
	local Shop = G.req("client/Controllers/ShopController")
	local MC = G.req("client/Controllers/MenuController")
	if not T.check(Shop ~= nil and MC ~= nil and type(Shop.Open) == "function" and type(MC.Open) == "function", "shop openers: ShopController and MenuController load") then
		return
	end
	local saved = G.begin()
	Mock.SetViewport(1920, 1080)
	G.advance(0.5)
	local ok, err = pcall(function()
		-- a server OpenPanel (the walk-up prompt, a machine's prompt, the altar's Summon, an old Store caller)
		Shop.Open({ Tab = "Gems" })
		G.advance(0.3)
		Shop.Close()
		G.advance(0.3)
		KC.toClient("OpenPanel", "Shop", { Tab = "Eggs" })
		G.advance(0.4)
		T.check(Shop.IsOpen() and Shop.Tab() == "Eggs" and G.shown(G.find(G.win(), "Page_Eggs")), "shop openers: OpenPanel('Shop', { Tab = 'Eggs' }) (the walk-up prompt) -> the Shop on Eggs",
			tostring(Shop.IsOpen()) .. " / " .. tostring(Shop.Tab()))
		G.tapTab("Gems")
		KC.toClient("OpenPanel", "Shop", { Tab = "Roulette", RouletteId = "Storm" })
		G.advance(0.3)
		local storm = G.eggCard("Storm")
		T.check(Shop.Tab() == "Eggs" and storm ~= nil and storm:GetAttribute("Focused") == true, "shop openers: OpenPanel('Shop', { Tab = 'Roulette', RouletteId = 'Storm' }) -> Eggs with ShopCard_Storm focused",
			tostring(Shop.Tab()) .. " / " .. tostring(storm and storm:GetAttribute("Focused")))
		G.advance(2.8)
		G.tapTab("Packs")
		KC.toClient("OpenPanel", "Shop", { RouletteId = "Secret", Currency = "Gems" })
		G.advance(0.3)
		local hero = G.eggCard("Secret")
		T.check(Shop.Tab() == "Eggs" and hero ~= nil and hero:GetAttribute("Focused") == true, "shop openers: OpenPanel('Shop', { RouletteId = 'Secret', Currency = 'Gems' }) (the altar's Summon) -> ShopCard_Secret focused",
			tostring(Shop.Tab()) .. " / " .. tostring(hero and hero:GetAttribute("Focused")))
		G.advance(2.8)
		KC.toClient("OpenPanel", "Store", { Tab = "Passes" })
		G.advance(0.3)
		T.check(Shop.IsOpen() and Shop.Tab() == "Passes" and G.shown(G.find(G.win(), "Page_Passes")), "shop openers: OpenPanel('Store', { Tab = 'Passes' }) -> the Shop on Passes",
			tostring(Shop.IsOpen()) .. " / " .. tostring(Shop.Tab()))
		Shop.Close()
		G.advance(0.4)

		-- the top bar's Shop: the last tab of this session (the first time Eggs); a second press closes it
		if type(Shop._S) == "table" then
			Shop._S.Tab = nil -- (a fresh session)
		end
		T.check(G.pill("Shop") and Shop.IsOpen() and Shop.Tab() == "Eggs", "shop openers: PillButton_Shop's first press of a session -> the Shop on Eggs", tostring(Shop.Tab()))
		G.tapTab("Gems")
		G.tap(G.find(G.win(), "CloseButton"))
		G.advance(0.3)
		T.check(not Shop.IsOpen(), "shop openers: (setup) the X closes the Shop")
		G.pill("Shop")
		T.check(Shop.IsOpen() and Shop.Tab() == "Gems", "shop openers: ...the next press -> the last tab (Gems)", tostring(Shop.Tab()))
		G.pill("Shop")
		T.check(not Shop.IsOpen(), "shop openers: ...a press while it is open closes it")

		-- the Pets window's Open Shop button (no pets yet) -> Eggs, not the last tab
		MC.Open("Pets")
		G.advance(0.6)
		local openShop = nil
		for _, d in ipairs(G.pg():GetDescendants()) do
			if d.Name == "OpenShop" and (d:IsA("TextButton") or d:IsA("ImageButton")) then
				openShop = d
			end
		end
		if T.check(openShop ~= nil, "shop openers: (setup) the Pets window's OpenShop button exists") then
			Mock.Click(openShop)
			G.advance(0.5)
			T.check(Shop.IsOpen() and Shop.Tab() == "Eggs", "shop openers: PetsController's OpenShop -> the Shop on Eggs (the last tab was Gems)", tostring(Shop.IsOpen()) .. " / " .. tostring(Shop.Tab()))
		end
		Shop.Close()
		MC.Close()
		G.advance(0.4)

		-- the tutorial's shop step: any opener completes ShopOpened once (WINDOW_EVENTS); its world arrow stays, no ring on the pill
		local TC = G.req("client/Controllers/TutorialController")
		local Steps = G.req("shared/TutorialSteps")
		local index = nil
		for i, st in ipairs(Steps and Steps.Steps or {}) do
			if st.Id == "shop" then
				index = i
			end
		end
		if T.check(TC ~= nil and index ~= nil, "shop openers: (setup) the tutorial's shop step exists") then
			local tutSaved = type(TC.GetState) == "function" and TC.GetState() or nil
			local step = Steps.Steps[index]
			T.check(type(step.Target) == "table" and step.Target.Kind ~= "Menu" and step.CompleteOn == "ShopOpened", "shop openers: the shop step has a world target and waits for ShopOpened",
				tostring(step.Target and step.Target.Kind) .. " / " .. tostring(step.CompleteOn))
			-- the step's own target, plus the server's Position (the controller's fallback: this world has no NimbusLobby)
			local target = {}
			for k, v in pairs(step.Target or {}) do
				target[k] = v
			end
			local Config = KC.env()
			target.Position = target.Position or (Config.Lobby.Origin + Config.Lobby.ShopOffset)
			KC.toClient("TutorialState", {
				Step = index, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = tostring(step.Text), Target = target,
				CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, AlsoNext = step.AlsoNext == true,
				Chapter = step.Chapter, Done = false, Completed = false, Skipped = false, Reward = 0,
			})
			G.advance(2.5)
			local guide0, ring0 = G.tutGuide(), G.tutRing()
			T.check(guide0 and not ring0, "shop openers: (setup) the shop step shows its world arrow (workspace.ClientFx.TutorialGuide), no menu ring",
				"guide " .. tostring(guide0) .. ", ring " .. tostring(ring0))
			local mark = #Mock.RemoteLog
			G.pill("Shop")
			G.advance(0.4)
			T.check(Shop.IsOpen() and G.calls("TutorialEvent", mark, "ShopOpened") == 1, "shop openers: with the shop step active, PillButton_Shop completes ShopOpened once",
				G.calls("TutorialEvent", mark, "ShopOpened") .. " sent")
			local ringOpen = G.tutRing()
			Shop.Close()
			G.advance(0.8)
			T.check(not ringOpen and not G.tutRing() and G.tutGuide() == guide0, "shop openers: ...no ring shows on the pill, and the step keeps its world arrow",
				"ring while open " .. tostring(ringOpen) .. ", guide after " .. tostring(G.tutGuide()))
			mark = #Mock.RemoteLog
			KC.toClient("OpenPanel", "Shop", { Tab = "Roulette", RouletteId = "Cloud" })
			G.advance(0.6)
			T.check(Shop.IsOpen() and G.calls("TutorialEvent", mark, "ShopOpened") == 1, "shop openers: ...and OpenPanel('Shop', ...) completes it once too",
				G.calls("TutorialEvent", mark, "ShopOpened") .. " sent")
			ringOpen = G.tutRing()
			Shop.Close()
			G.advance(0.8)
			T.check(not ringOpen and not G.tutRing() and G.tutGuide() == guide0, "shop openers: ...still no ring, the world arrow unchanged")
			G.advance(0.4)
			if tutSaved then
				KC.toClient("TutorialState", tutSaved)
			else
				KC.toClient("TutorialState", { Done = true, Step = #Steps.Steps, Total = #Steps.Steps })
			end
			G.advance(0.6)
		end
	end)
	if not ok then
		T.fail("shop openers: scenario error", tostring(err))
	end
	G.finish(saved)
	KC.flushErrors("client_shop_openers")
end)

----------------------------------------------------------------------------------------------------
-- client_shop_secret_lock (shop-area spec 16.17.3): the Secret card away from the Storm Altar
----------------------------------------------------------------------------------------------------
local ALTAR = { Lock = "Available at the Storm Altar", Short = "At the Storm Altar", Hint = "Secret rolls happen at the Storm Altar", Word = "TRAVEL" }

-- the hero's widgets: Spin, Travel (the button), AltarChip, PityChip, Dim, Hint, Lock
function G.heroKit()
	local hero = G.eggCard("Secret")
	return {
		Hero = hero,
		Spin = G.eggBtn("Secret", "Spin"),
		Travel = G.eggBtn("Secret", "Travel"),
		Chip = G.part(hero, "AltarChip"),
		Pity = G.part(hero, "PityChip"),
		Dim = G.part(hero, "Dim"),
		Hint = G.part(hero, "Hint"),
		Lock = G.part(hero, "Lock"),
	}
end
-- "shown" flags of the altar look in one line (debug detail)
function G.heroLook(k)
	local function f(o)
		return o and (G.shown(o) and "1" or "0") or "-"
	end
	return fmt("spin %s travel %s chip %s pity %s dim %s lock %s", f(k.Spin), f(k.Travel), f(k.Chip), f(k.Pity), f(k.Dim), f(k.Lock))
end

S.client_shop_secret_lock = guarded("client_shop_secret_lock", function()
	local KC = G.KC()
	local Config = KC.env()
	local Shop = G.req("client/Controllers/ShopController")
	local SE = G.req("client/UI/ShopEggs")
	local NK = G.req("client/UI/NeonKit")
	local okApi = type(Shop) == "table" and type(SE) == "table" and type(NK) == "table" and type(SE.AtAltar) == "function" and type(SE.SetFromAltar) == "function"
		and type(SE.Metrics) == "table" and type(SE.Metrics.TEXT) == "table"
	if not T.check(okApi, "secret lock: ShopEggs.AtAltar / SetFromAltar and ShopController load") then
		return
	end
	local K = SE.Metrics
	T.check(K.TEXT.AltarLock == ALTAR.Lock and K.TEXT.AltarLockShort == ALTAR.Short and K.TEXT.HeroHint == ALTAR.Hint and K.TEXT.Travel == ALTAR.Word
		and K.TRAVEL_GAP == 0.4 and K.DIM == 0.35, "secret lock: ShopEggs.Metrics: the texts, TRAVEL_GAP 0.4, DIM 0.35",
		fmt("%s / %s / %s / %s / %s / %s", tostring(K.TEXT.AltarLock), tostring(K.TEXT.AltarLockShort), tostring(K.TEXT.HeroHint), tostring(K.TEXT.Travel), tostring(K.TRAVEL_GAP), tostring(K.DIM)))
	local saved = G.begin()
	local attrName = Config.Lobby.ZoneAltarAttr
	local site0 = workspace:GetAttribute(attrName)
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local root0 = root and root.CFrame
	G.setAttr("Gems", 5000)
	G.setAttr("CloudTokens", 50000)
	G.setAttr("SecretPityLeft", 3)
	local function pulseFrames(seconds)
		local target = SE.HeroPulse()
		local frames, t = 0, 0
		while t < seconds - 1e-6 do
			G.advance(0.05)
			t = t + 0.05
			for tw in pairs(Mock.ActiveTweens) do
				local goal = Mock.TweenGoals(tw).Scale
				if target ~= nil and tw.Instance == target and type(goal) == "number" and goal > 1.001 then
					frames = frames + 1
					break
				end
			end
		end
		return frames
	end
	local function fitsAll(label, list)
		local bad = {}
		for _, o in ipairs(list) do
			if o and G.shown(o) then
				local okF, why = RedoGeom.fits(o)
				if not okF then
					bad[#bad + 1] = why
				end
			end
		end
		T.check(#bad == 0, label .. ": the lock chip, the hint and TRAVEL fit their boxes with the real font widths", table.concat(bad, "; "))
	end
	local ok, err = pcall(function()
		------------------------------------------------------------------ 1920x1080, away from the altar
		Mock.SetViewport(1920, 1080)
		G.advance(0.6)
		SE._AtAltar = false
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.6)
		T.eq(SE.AtAltar(), false, "secret lock: ShopEggs._AtAltar = false -> AtAltar() false")
		T.eq(SE.CardState("Secret"), "Altar", "secret lock: away from the altar CardState('Secret') is 'Altar'")
		local k = G.heroKit()
		local hb = k.Hero and G.rel(k.Hero, k.Hero)
		if not T.check(k.Hero and k.Spin and k.Travel and k.Chip and k.Dim and k.Hint, "secret lock: the hero has Spin, Travel, AltarChip, Dim and Hint", G.heroLook(k)) then
			return
		end
		local tb = G.rel(k.Travel, k.Hero)
		T.check(not G.shown(k.Spin) and G.shown(k.Travel) and G.near(tb.x, hb.w - 320) and G.near(tb.y, 66) and G.near(tb.w, 290) and G.near(tb.h, 100),
			"secret lock: SPIN hidden; a 290 x 100 TRAVEL button exactly where SPIN sits (w - 320, 66)", G.heroLook(k) .. "; " .. fmt("%.0f,%.0f %.0fx%.0f", tb.x, tb.y, tb.w, tb.h))
		local icon = k.Travel:FindFirstChild("Icon")
		T.check(k.Travel:GetAttribute("Style") == "Blue" and G.text(k.Travel, "Word") == ALTAR.Word and icon ~= nil and G.shown(icon) and icon.Text == NK.Glyphs.Travel
			and k.Travel:FindFirstChild("Price", true) == nil and k.Travel:FindFirstChild("GemIcon", true) == nil and not G.disabled(k.Travel),
			"secret lock: ...blue (Style 'Blue'), 'TRAVEL' with the compass glyph, no price, active", G.texts(k.Travel))
		local cb, pb = G.rel(k.Chip, k.Hero), k.Pity and G.rel(k.Pity, k.Hero)
		T.check(G.shown(k.Chip) and k.Chip.Text == ALTAR.Lock and k.Pity and not G.shown(k.Pity) and G.near(cb.x, 360) and G.near(cb.y, 132) and G.near(cb.h, 48) and cb.w >= 400 - 1
			and k.Chip.TextSize == 22 and pb and G.near(pb.x, cb.x) and G.near(pb.y, cb.y),
			"secret lock: AltarChip 'Available at the Storm Altar' in the pity chip's place (360, 132, >= 400 x 48, 22 px), the PityChip hidden", G.heroLook(k) .. "; " .. fmt("%.0f,%.0f %.0fx%.0f", cb.x, cb.y, cb.w, cb.h))
		local db = G.rel(k.Dim, k.Hero)
		local egg = G.part(k.Hero, "HeroEgg")
		local sparks = G.part(k.Hero, "Sparks")
		local holder = k.Travel.Parent
		T.check(G.shown(k.Dim) and G.near(db.x, 0) and G.near(db.y, 0) and G.near(db.w, hb.w) and G.near(db.h, hb.h) and abs(k.Dim.BackgroundTransparency - 0.35) < 1e-6
			and k.Dim.BackgroundTransparency < 1 and k.Dim.Parent == k.Chip.Parent,
			"secret lock: Dim (K.NAVY at 0.35) covers the card body", fmt("%.0f,%.0f %.0fx%.0f t %.2f", db.x, db.y, db.w, db.h, k.Dim.BackgroundTransparency))
		T.check(k.Dim.ZIndex > (egg and egg.ZIndex or 0) and k.Dim.ZIndex > (sparks and sparks.ZIndex or 0) and k.Dim.ZIndex < k.Chip.ZIndex and holder and k.Dim.ZIndex < holder.ZIndex and k.Dim.ZIndex < k.Hint.ZIndex,
			"secret lock: ...over the machine, the big egg and its sparks, under the chip, the TRAVEL button and the hint",
			fmt("dim %d, egg %s, sparks %s, chip %d, holder %s, hint %d", k.Dim.ZIndex, tostring(egg and egg.ZIndex), tostring(sparks and sparks.ZIndex), k.Chip.ZIndex, tostring(holder and holder.ZIndex), k.Hint.ZIndex))
		T.eq(G.text(k.Hero, "Hint"), ALTAR.Hint, "secret lock: the hint reads 'Secret rolls happen at the Storm Altar'")
		fitsAll("secret lock 1920x1080", { k.Chip, k.Hint, k.Travel:FindFirstChild("Word") })
		local states = {}
		for _, id in ipairs(MACHINES) do
			states[#states + 1] = tostring(SE.CardState(id))
		end
		T.eq(table.concat(states, " "), "Ready Ready Ready Ready", "secret lock: the four machine cards stay Ready (only the Secret card moved)")
		local frames = pulseFrames(3)
		T.check(frames == 0 and SE.HeroPulse() and SE.HeroPulse().Scale == 1, "secret lock: the hero's pulse stays off while Altar (Scale 1 for 3 s)", frames .. " frames")
		RedoGeom.check(G.win(), "secret lock 1920x1080", { MinText = 18, MinTarget = 44, NoOverlap = G.noOverlapNames() })

		------------------------------------------------------------------ the TRAVEL mash: one QuickTravel("Altar"), the Shop closes
		local mark = #Mock.RemoteLog
		Mock.Click(k.Travel)
		Mock.Click(k.Travel)
		Mock.Click(k.Travel)
		G.advance(0.1)
		local qt = KC.serverCalls("QuickTravel", mark)
		T.check(#qt == 1 and qt[1].args[1] == "Altar" and not Shop.IsOpen(), "secret lock: three TRAVEL taps within 0.1 s -> exactly one QuickTravel('Altar'), and the Shop closes",
			#qt .. " sends, open " .. tostring(Shop.IsOpen()))
		G.advance(0.5)
		Mock.Click(k.Travel)
		G.advance(0.1)
		T.eq(#KC.serverCalls("QuickTravel", mark), 1, "secret lock: ...a TRAVEL tap with the Shop closed sends nothing")

		------------------------------------------------------------------ at the altar: today's card
		SE._AtAltar = true
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.6)
		k = G.heroKit()
		T.check(SE.CardState("Secret") == "Ready" and G.shown(k.Spin) and not G.disabled(k.Spin) and not G.shown(k.Travel) and not G.shown(k.Chip) and G.shown(k.Pity) and not G.shown(k.Dim)
			and G.text(k.Hero, "Hint") == ALTAR.Hint,
			"secret lock: at the altar the card is Ready: SPIN shown, TRAVEL / AltarChip / Dim hidden, the PityChip back, the same hint", tostring(SE.CardState("Secret")) .. "; " .. G.heroLook(k))
		T.check(pulseFrames(3) > 0, "secret lock: ...and the hero's SPIN pulses again (High)")

		------------------------------------------------------------------ FromAltar (the altar prompt's OpenPanel) stands in only
		-- while there is no live reading (no AltarIslandAt replicated yet / no HumanoidRootPart); a live reading wins (review
		-- round 1: opened at the altar, then walked away with the Shop open, the card locks again on the next tick)
		SE._AtAltar = nil
		workspace:SetAttribute(attrName, nil)
		Shop.Close()
		G.advance(0.3)
		Shop.Open({ RouletteId = "Secret", FromAltar = true })
		G.advance(0.4)
		k = G.heroKit()
		T.check(SE.AtAltar() == true and SE.CardState("Secret") == "Ready" and G.shown(k.Spin) and k.Hero:GetAttribute("Focused") == true,
			"secret lock: Open({ RouletteId = 'Secret', FromAltar = true }) (the altar's prompt) with no live reading yet (no AltarIslandAt) -> Ready and the Secret card focused", tostring(SE.CardState("Secret")))
		Shop.Close()
		G.advance(0.3)
		T.eq(SE.AtAltar(), false, "secret lock: ...Close clears FromAltar")
		Shop.Open({})
		G.advance(0.4)
		T.eq(SE.CardState("Secret"), "Altar", "secret lock: ...and the next plain open is locked again")
		Shop.Close()
		G.advance(0.3)
		local siteA = Vector3.new(600, 300, 40)
		workspace:SetAttribute(attrName, siteA)
		if T.check(root ~= nil, "secret lock: (setup) the local character has a HumanoidRootPart for the FromAltar walk") then
			Mock.Teleport(LocalPlayer, CFrame.new(siteA + Vector3.new(0, 3, -10)))
			Shop.Open({ RouletteId = "Secret", FromAltar = true })
			G.advance(0.4)
			T.eq(SE.CardState("Secret"), "Ready", "secret lock: opened by the altar's prompt on the deck: Ready")
			Mock.Teleport(LocalPlayer, CFrame.new(siteA + Vector3.new(0, 3, -60)))
			G.advance(1.1)
			k = G.heroKit()
			T.check(SE.AtAltar() == false and SE.CardState("Secret") == "Altar" and not G.shown(k.Spin) and G.shown(k.Travel),
				"secret lock: ...then walked 60 studs off with the Shop open: the card locks on the next tick (TRAVEL), the live reading wins over FromAltar",
				tostring(SE.CardState("Secret")) .. "; " .. G.heroLook(k))
			Shop.Close()
			G.advance(0.3)
		end

		------------------------------------------------------------------ walk to / away from the altar: the card follows on the next tick
		local site = Vector3.new(600, 300, 40)
		workspace:SetAttribute(attrName, site)
		if T.check(root ~= nil, "secret lock: (setup) the local character has a HumanoidRootPart") then
			Mock.Teleport(LocalPlayer, CFrame.new(site + Vector3.new(0, 3, -80)))
			Shop.Open({ Tab = "Eggs" })
			G.advance(0.4)
			T.eq(SE.CardState("Secret"), "Altar", "secret lock walk: 80 studs from the island: Altar")
			Mock.Teleport(LocalPlayer, CFrame.new(site + Vector3.new(0, 3, -10)))
			G.advance(1.1)
			k = G.heroKit()
			T.check(SE.CardState("Secret") == "Ready" and G.shown(k.Spin) and not G.shown(k.Travel), "secret lock walk: on the deck the card unlocks on the next Shop tick", tostring(SE.CardState("Secret")) .. "; " .. G.heroLook(k))
			Mock.Teleport(LocalPlayer, CFrame.new(site + Vector3.new(0, 3, -40)))
			G.advance(1.1)
			k = G.heroKit()
			T.check(SE.CardState("Secret") == "Altar" and not G.shown(k.Spin) and G.shown(k.Travel), "secret lock walk: 40 studs out (no client slack) it locks again on the next tick",
				tostring(SE.CardState("Secret")) .. "; " .. G.heroLook(k))
			Shop.Close()
			G.advance(0.3)
		end

		------------------------------------------------------------------ Locked wins over Altar; Altar before Loading
		SE._AtAltar = false
		G.setAttr("PaidRandomItemsRestricted", true)
		Shop.Open({ Tab = "Eggs" })
		G.advance(1.2)
		k = G.heroKit()
		T.check(SE.CardState("Secret") == "Locked" and G.shown(k.Lock) and k.Lock.Text == EGG_LOCK and not G.shown(k.Chip) and not G.shown(k.Travel) and G.shown(k.Spin) and G.disabled(k.Spin)
			and G.text(k.Spin, "Word") == "Locked" and not G.shown(k.Dim),
			"secret lock: a restricted account: Locked wins (the Lock line, SPIN shown but 'Locked' and inactive; no chip, no TRAVEL, no Dim)", tostring(SE.CardState("Secret")) .. "; " .. G.heroLook(k))
		G.setAttr("PaidRandomItemsRestricted", false)
		G.setAttr("GemsSettled", nil)
		G.advance(1.2)
		T.eq(SE.CardState("Secret"), "Altar", "secret lock: not settled yet and away from the altar: Altar (before Loading)")
		SE._AtAltar = true
		G.advance(1.2)
		T.eq(SE.CardState("Secret"), "Loading", "secret lock: ...at the altar it reads Loading as before")
		G.setAttr("GemsSettled", true)
		G.advance(1.2)
		Shop.Close()
		G.advance(0.3)

		------------------------------------------------------------------ 1280x720 (Compact, shrunk), the phones, portrait
		for _, sz in ipairs({ { 1280, 720, false, 14 }, { 844, 390, true, 15 }, { 640, 360, true, 15 }, { 360, 640, true, 15 } }) do
			local label = fmt("secret lock %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], sz[3], label, function()
				SE._AtAltar = false
				Shop.Open({ Tab = "Eggs" })
				G.advance(0.6)
				local kk = G.heroKit()
				local phone = sz[3]
				local want = phone and ALTAR.Short or ALTAR.Lock
				local trb = kk.Travel and G.rel(kk.Travel, kk.Travel)
				local spinAt = kk.Spin and G.rel(kk.Spin, kk.Hero)
				local travelAt = kk.Travel and G.rel(kk.Travel, kk.Hero)
				T.check(SE.CardState("Secret") == "Altar" and kk.Chip and G.shown(kk.Chip) and kk.Chip.Text == want and not G.shown(kk.Spin) and kk.Travel and G.shown(kk.Travel) and G.shown(kk.Dim)
					and spinAt and travelAt and G.near(spinAt.x, travelAt.x) and G.near(spinAt.y, travelAt.y) and G.near(spinAt.w, travelAt.w) and G.near(spinAt.h, travelAt.h),
					label .. ": the AltarChip reads '" .. want .. "', TRAVEL in SPIN's box, the Dim over the card", G.heroLook(kk))
				if phone then
					T.check(trb and G.near(trb.h, 44) and trb.w >= 44, label .. ": TRAVEL is 44 tall and at least 44 wide", trb and fmt("%.0fx%.0f", trb.w, trb.h) or "none")
				else
					T.check(kk.Chip.TextSize >= 18 and kk.Hint.TextSize >= 18 and kk.Travel:FindFirstChild("Word").TextSize >= 18, label .. ": PC texts >= 18 design px")
				end
				fitsAll(label, { kk.Chip, kk.Hint, kk.Travel and kk.Travel:FindFirstChild("Word") })
				RedoGeom.check(G.win(), label, { MinText = sz[4], MinTarget = 44, NoOverlap = G.noOverlapNames() })
				Shop.Close()
				G.advance(0.3)
			end)
		end
	end)
	if not ok then
		T.fail("secret lock: scenario error", tostring(err))
	end
	workspace:SetAttribute(attrName, site0)
	if root and root0 and root.Parent then
		Mock.Teleport(LocalPlayer, root0)
	end
	G.finish(saved)
	KC.flushErrors("client_shop_secret_lock")
end)

return S
