-- smoke_fixr_store_ui.lua: the Store window's review fixes (review E, the client half; docs/superpowers/specs/2026-11-04-shop-retention-design.md
-- 5.1 / 7 Z6 / 9, plan Task 7). Loaded by tools/smoke.py in the client world only (client_files):
--   client_fixr_store_colors      every card its own saturated gradient (UIGradient) and outline (UIStroke): no two packs share a
--                                 colour pair (on a tab or in the whole Store), every card text has a stroke and every card a dark
--                                 stop under it, the tab's hero is the brightest card of its tab with the thickest outline; a
--                                 Have-it card greys out and gets its colours back
--   client_fixr_store_loading     StoreBought absent (the record still loading / provisional): the Once cards read "..."
--                                 disabled and send nothing, the hero never promotes a Once pack (VIP leads); the record
--                                 arriving ("") makes them Buy with the Starter hero, "Starter" makes it Claimed!
--   client_fixr_store_art         TextureIds store_<key> draws the card's art as an image (the glyph hides), no key = the
--                                 glyph; the tab icons go through NeonKit.Icon (Config.Icons[tab] swaps in an image)
--   client_fixr_store_gem_thanks  the gem pack thank-you toast ("+550 Gems! Thank you for your support!") plays StoreBuy
--                                 (Reward) like the Store's "Thank you! ..."; another gem toast plays nothing
--   client_fixr_store_portrait    (re-review 1, finding 6) 360x640 portrait phone, every item created at the widest price,
--                                 nothing / everything owned: the title under no balance pill, the pills and the X inside
--                                 the window, every tab on screen >= 44 px with its label fitting, every card full width
--                                 with every text fitting its box (real font widths: TextService measures them for the
--                                 scenario) inside the card, Buy >= 44 px; 844x390 is the landscape layout again
-- (lobby-shop Task 21: the Store is the one Shop window, NimbusShop / ShopWindow, behind the StoreController forwarder; the
-- gem and token packs are Gems-tab tiles, so the card counts are the 7 Packs / Passes / Boosts items, the heroes 2+, and
-- the portrait header is Header > Title, Balance_Gems, Balance_Tokens, CloseButton.)
-- Every scenario restores the Config ids, the attributes, TextureIds / Config.Icons and the swapped functions it touched.
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format

local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local MPS = game:GetService("MarketplaceService")
	local LocalPlayer = Players.LocalPlayer
	local H = {}

	-- a module of the client build (the H.moduleAt shape of smoke_store_ui.lua; ROOTS is smoke.py's)
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
	function H.win()
		local gui = H.pg():FindFirstChild("NimbusShop")
		return gui and gui:FindFirstChild("ShopWindow", true)
	end
	function H.card(win, key)
		return win and win:FindFirstChild("Card_" .. key, true)
	end
	function H.cards(win)
		local out = {}
		for _, d in ipairs(win and win:GetDescendants() or {}) do
			if d:IsA("GuiObject") and d.Name:sub(1, 5) == "Card_" then
				out[#out + 1] = d
			end
		end
		return out
	end
	function H.heroKey(win)
		for _, d in ipairs(H.cards(win)) do
			if d:GetAttribute("Hero") == true and H.shownIn(d) then
				return d:GetAttribute("Key")
			end
		end
		return nil
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
	function H.calls(name, mark, a1, a2)
		local n = 0
		for _, e in ipairs(KC.serverCalls(name, mark)) do
			if (a1 == nil or e.args[1] == a1) and (a2 == nil or e.args[2] == a2) then
				n = n + 1
			end
		end
		return n
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

	-- colours: relative luminance (sRGB), HSV saturation, a hex key
	function H.lum(c)
		local function lin(v)
			return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * lin(c.R) + 0.7152 * lin(c.G) + 0.0722 * lin(c.B)
	end
	function H.sat(c)
		local hi = math.max(c.R, c.G, c.B)
		local lo = math.min(c.R, c.G, c.B)
		return hi > 0 and (hi - lo) / hi or 0
	end
	function H.hex(c)
		return fmt("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end
	-- the card's paint: its own UIGradient (the most saturated one on the card or a direct child frame, never inside the
	-- Body's texts) and its outline (the card's direct UIStroke)
	function H.paint(card)
		local best, bestSat = nil, -1
		local stroke = nil
		local pool = {}
		for _, ch in ipairs(card:GetChildren()) do
			pool[#pool + 1] = ch
			if ch:IsA("GuiObject") and ch.Name ~= "Body" then
				for _, g in ipairs(ch:GetChildren()) do
					if g:IsA("UIGradient") then
						pool[#pool + 1] = g
					end
				end
			end
		end
		for _, ch in ipairs(pool) do
			if ch:IsA("UIGradient") then
				local s = 0
				for _, kp in ipairs(ch.Color.Keypoints) do
					s = math.max(s, H.sat(kp.Value))
				end
				if s > bestSat then
					best, bestSat = ch, s
				end
			elseif ch:IsA("UIStroke") and stroke == nil then
				stroke = ch
			end
		end
		if not best then
			return nil
		end
		local kps = best.Color.Keypoints
		local peak, dark, vivid, darkSat = 0, 1, 0, 0
		for _, kp in ipairs(kps) do
			peak = math.max(peak, H.lum(kp.Value))
			vivid = math.max(vivid, H.sat(kp.Value))
			if H.lum(kp.Value) < dark then
				dark, darkSat = H.lum(kp.Value), H.sat(kp.Value)
			end
		end
		return {
			Gradient = best, Stroke = stroke, Top = kps[1].Value, Bottom = kps[#kps].Value, Peak = peak, Dark = dark, Vivid = vivid, DarkSat = darkSat,
			Edge = stroke and stroke.Color or nil, Thick = stroke and stroke.Thickness or 0,
		}
	end
	-- a text has a stroke: TextStroke on, or a Contextual UIStroke (Theme.TextOutline)
	function H.textStroked(obj)
		if (tonumber(obj.TextStrokeTransparency) or 1) < 0.95 then
			return true
		end
		for _, ch in ipairs(obj:GetChildren()) do
			if ch:IsA("UIStroke") and ch.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and ch.Transparency < 0.95 then
				return true
			end
		end
		return false
	end

	-- every scenario starts from the same place and puts everything back (the smoke_store_ui.lua H.begin / H.finish shape)
	local ATTRS = { "InMatch", "OwnedPasses", "StoreBought", "XpBoostEnds", "StorePreview", "PaidRandomItemsRestricted" }
	function H.begin()
		local Config = KC.env()
		local saved = { Ids = {}, Gems = {}, Attrs = {}, Viewport = { Mock.Viewport.X, Mock.Viewport.Y } }
		for _, it in ipairs(Config.Store.Items) do
			saved.Ids[it.Key] = it.Id
		end
		for i, p in ipairs(Config.Gems.Products) do
			saved.Gems[i] = p.Id
		end
		for _, name in ipairs(ATTRS) do
			saved.Attrs[name] = LocalPlayer:GetAttribute(name)
		end
		H.setAttr("InMatch", false)
		H.setAttr("OwnedPasses", "")
		H.setAttr("StoreBought", "")
		H.setAttr("XpBoostEnds", 0)
		H.setAttr("StorePreview", nil)
		H.setAttr("PaidRandomItemsRestricted", false) -- (lobby-shop 16.1: an allowed account)
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
		local SC = H.ctrl("StoreController")
		local MC = H.ctrl("MenuController")
		if SC then
			SC.Close()
		end
		if MC then
			MC.Close()
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
		for _, name in ipairs(ATTRS) do
			H.setAttr(name, saved.Attrs[name])
		end
		MPS.PromptProductPurchase = nil
		MPS.PromptGamePassPurchase = nil
		MPS.GetProductInfo = nil
		Mock.SetViewport(saved.Viewport[1], saved.Viewport[2])
		KC.advance(0.6)
	end
	-- every listed item created (the disabled Cash packs stay unlisted), the gem packs too
	function H.createAll()
		local Config = KC.env()
		for i, it in ipairs(Config.Store.Items) do
			it.Id = 6000 + i
		end
		for i, p in ipairs(Config.Gems.Products) do
			p.Id = 6100 + i
		end
	end
	-- (the Shop opens on its last tab; `tab` picks one: a tab's hero shows on its own page)
	function H.reopen(SC, tab)
		SC.Close()
		KC.advance(0.2)
		SC.Open(tab and { Tab = tab } or nil)
		KC.advance(0.5)
	end

	-- Real text widths (the mock measures a flat 0.5 em per character): the advance widths (1/1000 em) of ASCII 32..126 in
	-- Roblox's shipped FredokaOne-Regular.ttf (Display), BuilderSans-Bold.otf (Body / Label) and Montserrat-Black.ttf (the
	-- metric stand-in for GothamBlack, a cloud font: Title / Heading / Button / Toast); any other character counts 0.6 em
	local ADVANCE = {
		Fredoka = { 253, 267, 429, 749, 475, 838, 748, 208, 384, 384, 503, 527, 238, 433, 237, 526, 608, 407, 609, 608, 592, 530, 560, 561, 582, 560, 238, 237, 627, 478, 627, 512, 908, 765, 646, 679, 704, 638, 637, 714, 699, 257, 549, 639, 587, 870, 720, 775, 632, 830, 631, 583, 731, 726, 783, 999, 741, 686, 643, 348, 528, 348, 526, 826, 482, 596, 592, 517, 598, 573, 450, 585, 605, 255, 252, 536, 327, 851, 606, 600, 582, 582, 457, 489, 449, 606, 638, 793, 567, 604, 586, 381, 217, 381, 651 },
		Gotham = { 300, 314, 489, 740, 657, 917, 777, 254, 381, 381, 473, 620, 304, 390, 304, 440, 692, 418, 608, 614, 712, 619, 661, 645, 678, 661, 304, 304, 620, 620, 620, 606, 1037, 806, 773, 744, 826, 673, 644, 769, 804, 350, 574, 765, 617, 954, 804, 848, 743, 848, 745, 657, 654, 784, 786, 1206, 762, 710, 687, 410, 440, 410, 620, 500, 600, 639, 700, 615, 705, 653, 426, 711, 702, 326, 334, 713, 326, 1040, 702, 678, 700, 700, 456, 565, 460, 698, 644, 977, 645, 644, 570, 438, 320, 438, 620 },
		Builder = { 250, 278, 458, 685, 580, 894, 704, 268, 366, 366, 431, 518, 264, 350, 264, 424, 646, 407, 585, 587, 612, 589, 615, 528, 632, 615, 292, 292, 518, 518, 518, 541, 919, 704, 635, 677, 702, 576, 574, 693, 720, 280, 505, 649, 566, 894, 720, 745, 627, 745, 641, 574, 556, 690, 716, 960, 658, 642, 559, 377, 424, 377, 476, 422, 276, 566, 613, 533, 613, 567, 405, 616, 601, 260, 255, 531, 260, 879, 601, 590, 613, 613, 415, 483, 403, 591, 574, 806, 536, 574, 465, 478, 294, 478, 600 },
	}
	local FACE = { FredokaOne = "Fredoka", BuilderSansBold = "Builder", BuilderSans = "Builder", BuilderSansMedium = "Builder", BuilderSansExtraBold = "Builder" }
	function H.realWidth(text, size, font)
		local name = (typeof(font) == "EnumItem" and font.Name) or tostring(font)
		local adv = ADVANCE[FACE[name] or "Gotham"]
		local em = 0
		for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			local b = ch:byte()
			if #ch == 1 then
				if b >= 32 and b <= 126 then
					em = em + adv[b - 31] / 1000
				end
			else
				em = em + 0.6
			end
		end
		return em * (tonumber(size) or 14)
	end
	-- the word-wrapped rows of `text` in `width` px with the real widths (math.huge: one word alone is wider than the box)
	function H.realRows(text, size, font, width)
		local rows, cur = 0, 0
		local space = H.realWidth(" ", size, font)
		for word in tostring(text):gmatch("%S+") do
			local w = H.realWidth(word, size, font)
			if w > width + 0.5 then
				return math.huge
			end
			if cur > 0 and cur + space + w <= width + 0.5 then
				cur = cur + space + w
			else
				rows = rows + 1
				cur = w
			end
		end
		return math.max(rows, 1)
	end
	-- TextService:GetTextSize measures with the real widths while a scenario runs (Roblox measures its real fonts; the
	-- mock's flat 0.5 em would let a layout pick a text that only fits in the mock). Answers the restore function.
	function H.realMeasure()
		game:GetService("TextService") -- the class is finalized once the service exists
		local methods = Mock.Classes.TextService.methods
		local old = methods.GetTextSize
		methods.GetTextSize = function(_, text, size, font, frame)
			local w = H.realWidth(text, size, font)
			local limit = (typeof(frame) == "Vector2" and frame.X > 0) and frame.X or math.huge
			if w <= limit then
				return Vector2.new(w, size)
			end
			local rows = H.realRows(text, size, font, limit)
			return Vector2.new(limit, (rows == math.huge and 99 or rows) * size)
		end
		return function()
			methods.GetTextSize = old
		end
	end
	-- the product of the UIScales on and above a gui object (the window's Scale / Fit, a cell's Pop)
	function H.scaleOf(o)
		local s, node = 1, o
		while node and not node:IsA("ScreenGui") do
			for _, ch in ipairs(node:GetChildren()) do
				if ch:IsA("UIScale") then
					s = s * ch.Scale
				end
			end
			node = node.Parent
		end
		return s
	end
	-- does a text object's text fit its box with the real widths? One line unless TextWrapped (then the rows by words);
	-- a TextScaled text always fits. Answers ok, detail.
	function H.fits(o)
		local text = tostring(o.Text)
		if text:gsub("%s", "") == "" or o.TextScaled then
			return true, ""
		end
		local s = math.max(0.01, H.scaleOf(o))
		local boxW, boxH = o.AbsoluteSize.X / s, o.AbsoluteSize.Y / s
		local pad = o:FindFirstChildOfClass("UIPadding")
		if pad then
			boxW = boxW - pad.PaddingLeft.Offset - pad.PaddingRight.Offset
			boxH = boxH - pad.PaddingTop.Offset - pad.PaddingBottom.Offset
		end
		local size = o.TextSize
		-- (kit-b U1 review) a Nunito label reads .Font = Enum.Font.Unknown, as in Roblox: measure it with its role's Enum fallback
		local font = o.Font
		if font == Enum.Font.Unknown then
			local okT, Theme = pcall(require, Mock.GetPath(ROOTS.shared .. "/Theme"))
			font = okT and Theme.FontOf(o) or font
		end
		local w = H.realWidth(text, size, font)
		local detail = fmt("%s '%s' %.1f px at %d (%s) in %.0fx%.0f", o.Name, (text:gsub("[\128-\255]+", "?")), w, size, font.Name, boxW, boxH)
		if w <= boxW + 0.5 then
			return true, detail
		end
		if not o.TextWrapped then
			return false, detail
		end
		local rows = H.realRows(text, size, font, boxW)
		return rows * size * (o.LineHeight or 1) <= boxH + 1, detail .. " rows " .. tostring(rows)
	end
	-- every shown text under `root` that does not fit (a list of details)
	function H.unfit(root)
		local bad = {}
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and KC.isShown(d) then
				local ok, detail = H.fits(d)
				if not ok then
					bad[#bad + 1] = detail
				end
			end
		end
		return bad
	end

	S.client_fixr_store_colors = guarded("client_fixr_store_colors", function()
		local SC = H.ctrl("StoreController")
		if not T.check(type(SC) == "table" and type(SC.Open) == "function" and type(SC.Cards) == "function", "store colors: StoreController loads") then
			return
		end
		local saved = H.begin()
		Mock.SetViewport(1920, 1080)
		H.createAll()
		H.reopen(SC)
		local win = H.win()
		local cards = H.cards(win)
		-- (lobby-shop Task 21: the gem and token packs are Gems-tab tiles now; the Packs / Passes / Boosts cards are 7)
		T.check(#cards >= 7, "store colors: every created Robux pack has a card", #cards .. " cards")
		local missing, dull, pale, unstroked = {}, {}, {}, {}
		local seenTab, seenAll, clash = {}, {}, {}
		local byTab = {}
		for _, card in ipairs(cards) do
			local key = card:GetAttribute("Key")
			local tab = SC.Cards()[key] and SC.Cards()[key].Tab or "?"
			local p = H.paint(card)
			if not (p and p.Stroke) then
				missing[#missing + 1] = tostring(key)
			else
				-- (the most saturated stop and the darkest one: a hero also carries a near-white highlight stop)
				if p.Vivid < 0.6 or p.DarkSat < 0.4 or H.sat(p.Edge) < 0.3 then
					dull[#dull + 1] = fmt("%s top %s bottom %s edge %s", key, H.hex(p.Top), H.hex(p.Bottom), H.hex(p.Edge))
				end
				if p.Dark > 0.2 then
					pale[#pale + 1] = fmt("%s darkest %.2f", key, p.Dark)
				end
				local pair = H.hex(p.Top) .. "/" .. H.hex(p.Bottom) .. "/" .. H.hex(p.Edge)
				seenTab[tab] = seenTab[tab] or {}
				if seenTab[tab][pair] then
					clash[#clash + 1] = fmt("%s = %s on %s", key, seenTab[tab][pair], tab)
				end
				seenTab[tab][pair] = key
				local pairAll = H.hex(p.Top) .. "/" .. H.hex(p.Edge)
				if seenAll[pairAll] then
					clash[#clash + 1] = fmt("%s = %s (store)", key, seenAll[pairAll])
				end
				seenAll[pairAll] = key
				byTab[tab] = byTab[tab] or {}
				byTab[tab][#byTab[tab] + 1] = { Key = key, Hero = card:GetAttribute("Hero") == true, Paint = p }
			end
			for _, d in ipairs(card:GetDescendants()) do
				-- kit-b U6 (a deliberate change): the card's dark stop carries its white text, so no card text has a stroke
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and tostring(d.Text) ~= "" and d.Visible and H.textStroked(d) then
					unstroked[#unstroked + 1] = key .. "." .. d.Name
				end
			end
		end
		T.check(#missing == 0, "store colors: every card has its own UIGradient and UIStroke", table.concat(missing, ", "))
		T.check(#dull == 0, "store colors: every gradient stop and outline is saturated", table.concat(dull, "; "))
		T.check(#clash == 0, "store colors: no two packs share a colour pair (on a tab, or in the whole Store)", table.concat(clash, "; "))
		T.check(#pale == 0, "store colors: every card has a dark stop under its white text", table.concat(pale, "; "))
		T.check(#unstroked == 0, "store colors: no card text has a stroke (kit-b U6: it sits on the card's dark stop)", table.concat(unstroked, ", ", 1, math.min(#unstroked, 8)))
		local heroes, dim = 0, {}
		for tab, list in pairs(byTab) do
			local hero = nil
			for _, e in ipairs(list) do
				if e.Hero then
					hero = e
				end
			end
			if hero then
				heroes = heroes + 1
				for _, e in ipairs(list) do
					if e ~= hero and (e.Paint.Peak >= hero.Paint.Peak or e.Paint.Thick >= hero.Paint.Thick) then
						dim[#dim + 1] = fmt("%s: %s peak %.2f / %.1f px >= hero %s %.2f / %.1f px", tab, e.Key, e.Paint.Peak, e.Paint.Thick, hero.Key, hero.Paint.Peak, hero.Paint.Thick)
					end
				end
			end
		end
		T.check(heroes >= 2 and #dim == 0, "store colors: each tab's hero is its brightest card with the thickest outline", heroes .. " heroes; " .. table.concat(dim, "; "))
		-- a Have-it card greys out (x2 Pet XP owned) and gets its own colours back
		local before = H.paint(H.card(win, "XpPotion1"))
		H.setAttr("OwnedPasses", "PetXp2x")
		KC.advance(0.4)
		local greyed = H.paint(H.card(win, "XpPotion1"))
		T.check(SC.Cards().XpPotion1.State == "HaveIt" and greyed ~= nil and H.sat(greyed.Edge) < 0.2,
			"store colors: a Have-it card greys out", greyed and H.hex(greyed.Edge) or "no paint")
		H.setAttr("OwnedPasses", "")
		KC.advance(0.4)
		local back = H.paint(H.card(win, "XpPotion1"))
		T.check(before ~= nil and back ~= nil and H.hex(back.Edge) == H.hex(before.Edge) and H.hex(back.Top) == H.hex(before.Top),
			"store colors: ...and gets its own colours back", back and (H.hex(back.Top) .. "/" .. H.hex(back.Edge)) or "no paint")
		H.finish(saved)
		KC.flushErrors("client_fixr_store_colors")
	end)

	S.client_fixr_store_loading = guarded("client_fixr_store_loading", function()
		local SC = H.ctrl("StoreController")
		if not T.check(type(SC) == "table" and type(SC.Cards) == "function", "store loading: StoreController loads") then
			return
		end
		local saved = H.begin()
		Mock.SetViewport(1920, 1080)
		H.setId("Starter", 5001)
		H.setId("Pro", 5006)
		H.setId("VIP", 5002)
		H.setAttr("StoreBought", nil) -- the record is still loading (or provisional): the server writes no StoreBought
		H.reopen(SC, "Passes")
		local win = H.win()
		local c = SC.Cards()
		local starterBuy, proBuy = H.buyButton(win, "Starter"), H.buyButton(win, "Pro")
		T.check(c.Starter and c.Starter.State == "Loading" and c.Pro and c.Pro.State == "Loading",
			"store loading: no StoreBought = the Once cards are Loading, not Buy", fmt("%s / %s", tostring(c.Starter and c.Starter.State), tostring(c.Pro and c.Pro.State)))
		T.check(starterBuy ~= nil and starterBuy.Text == "..." and starterBuy:GetAttribute("Disabled") == true and proBuy ~= nil and proBuy.Text == "..." and proBuy:GetAttribute("Disabled") == true,
			"store loading: their Buy reads \"...\", disabled", starterBuy and (starterBuy.Text .. " " .. tostring(starterBuy:GetAttribute("Disabled"))) or "none")
		T.check(c.VIP and c.VIP.State == "Buy", "store loading: a pass card is not held back (OwnedPasses decides it)")
		local mark = #Mock.RemoteLog
		H.tapBuy(win, "Starter")
		KC.advance(1.2)
		H.tapBuy(win, "Pro")
		T.check(H.calls("StoreRequest", mark, "Buy") == 0 and saved.Prompts == 0, "store loading: a Loading card sends no Buy and prompts nothing",
			H.calls("StoreRequest", mark, "Buy") .. " sends")
		local starterCard = H.card(win, "Starter")
		T.check(H.heroKey(win) == "VIP" and starterCard ~= nil and starterCard:GetAttribute("Hero") ~= true,
			"store loading: the hero never promotes a Once pack while loading (VIP leads)", tostring(H.heroKey(win)))
		-- the real record arrives (nothing bought): Buy, the Starter hero
		H.setAttr("StoreBought", "")
		KC.advance(0.4)
		c = SC.Cards()
		starterCard = H.card(win, "Starter")
		T.check(c.Starter.State == "Buy" and c.Pro.State == "Buy" and H.buyButton(win, "Starter").Text == "Buy" and H.buyButton(win, "Starter"):GetAttribute("Disabled") ~= true,
			"store loading: the record arriving (\"\") makes them Buy", tostring(c.Starter.State))
		T.check(starterCard ~= nil and starterCard:GetAttribute("Hero") == true, "store loading: ...and the Starter becomes the hero while the window is open")
		mark = #Mock.RemoteLog
		KC.advance(1.2)
		H.tapBuy(win, "Starter")
		T.eq(H.calls("StoreRequest", mark, "Buy", "Starter"), 1, "store loading: Buy sends once the record is known")
		-- a record with the Starter bought: Claimed!, the hero moves off it
		H.setAttr("StoreBought", "Starter")
		KC.advance(0.4)
		starterCard = H.card(win, "Starter")
		T.check(SC.Cards().Starter.State == "Claimed" and H.buyButton(win, "Starter").Text == "Claimed!" and starterCard:GetAttribute("Hero") ~= true,
			"store loading: \"Starter\" makes it Claimed! and no longer the hero", tostring(SC.Cards().Starter.State))
		-- the record going away again (a provisional rebase) holds the Once cards back again
		H.setAttr("StoreBought", nil)
		KC.advance(0.4)
		T.check(SC.Cards().Starter.State == "Loading" and SC.Cards().Pro.State == "Loading", "store loading: StoreBought removed again = Loading again")
		H.finish(saved)
		KC.flushErrors("client_fixr_store_loading")
	end)

	S.client_fixr_store_art = guarded("client_fixr_store_art", function()
		local SC = H.ctrl("StoreController")
		local ids = H.moduleAt("shared", "TextureIds")
		local GQ = H.moduleAt("client", "GraphicsQuality")
		local Config = KC.env()
		if not T.check(type(SC) == "table" and type(ids) == "table" and type(GQ) == "table", "store art: StoreController, TextureIds, GraphicsQuality load") then
			return
		end
		local saved = H.begin()
		-- Low: the render (or glyph) itself; High swaps a pet card's art for its turning viewport (client_store_shine)
		local realEffective = GQ.Effective
		GQ.Effective = function()
			return "Low"
		end
		Mock.SetViewport(1920, 1080)
		local hadArt, hadIcons = ids.store_starter, Config.Icons
		ids.store_starter = 4242
		Config.Icons = Config.Icons or {}
		local hadPacks = Config.Icons.Packs
		Config.Icons.Packs = "rbxassetid://777"
		H.setId("Starter", 5001)
		H.setId("VIP", 5002)
		H.reopen(SC)
		local win = H.win()
		local starter = H.card(win, "Starter")
		local art = starter and starter:FindFirstChild("Art", true)
		local image = art and art:FindFirstChildWhichIsA("ImageLabel")
		local glyph = art and art:FindFirstChild("Glyph")
		T.check(image ~= nil and image.Image == "rbxassetid://4242" and image.Visible and (glyph == nil or not glyph.Visible),
			"store art: TextureIds.store_starter draws the Starter's art as an image, the glyph hides", image and image.Image or "no image")
		local vip = H.card(win, "VIP")
		local vipArt = vip and vip:FindFirstChild("Art", true)
		local vipGlyph = vipArt and vipArt:FindFirstChild("Glyph")
		T.check(vipArt ~= nil and vipArt:FindFirstChildWhichIsA("ImageLabel") == nil and vipGlyph ~= nil and vipGlyph.Visible and vipGlyph:GetAttribute("PixelIcon") == "crown" and vipGlyph:FindFirstChild("Icon") ~= nil,
			"store art: no store_vip key = the VIP card keeps its icon (kit-b U7a: the pixel crown)")
		local tab = win:FindFirstChild("Tab_Packs", true)
		local icon = tab and tab:FindFirstChild("Icon")
		T.check(icon ~= nil and icon:IsA("ImageLabel") and icon.Image == "rbxassetid://777",
			"store art: the Packs tab icon goes through NeonKit.Icon (Config.Icons.Packs swaps in an image)", icon and icon.ClassName or "no icon")
		local passes = win:FindFirstChild("Tab_Passes", true)
		local passIcon = passes and passes:FindFirstChild("Icon")
		T.check(passIcon ~= nil and passIcon:IsA("TextLabel") and passIcon:GetAttribute("IconId") == "Passes" and passIcon:GetAttribute("PixelIcon") == "ticket",
			"store art: a tab with a PixelIcon in Config.Icons keeps it (kit-b U7a; IconId Passes: the ticket)", passIcon and passIcon.ClassName or "no icon")
		-- the image goes away again: the next open draws the glyph
		Config.Icons.Packs = hadPacks
		ids.store_starter = hadArt
		H.setId("Starter", 5011) -- (a new id: the cards rebuild)
		H.reopen(SC)
		starter = H.card(win, "Starter")
		art = starter and starter:FindFirstChild("Art", true)
		glyph = art and art:FindFirstChild("Glyph")
		icon = tab and tab:FindFirstChild("Icon")
		T.check(art ~= nil and art:FindFirstChildWhichIsA("ImageLabel") == nil and glyph ~= nil and glyph.Visible, "store art: without the key the Starter is a glyph again")
		T.check(icon ~= nil and icon:IsA("TextLabel") and #tab:GetChildren() > 0, "store art: ...and the Packs tab is a glyph again", icon and icon.ClassName or "no icon")
		local icons = 0
		for _, ch in ipairs(tab and tab:GetChildren() or {}) do
			if ch.Name == "Icon" then
				icons = icons + 1
			end
		end
		T.eq(icons, 1, "store art: the tab holds one icon after the swap")
		Config.Icons = hadIcons
		GQ.Effective = realEffective
		H.finish(saved)
		KC.flushErrors("client_fixr_store_art")
	end)

	S.client_fixr_store_gem_thanks = guarded("client_fixr_store_gem_thanks", function()
		local SC = H.ctrl("StoreController")
		local SFX = H.moduleAt("client", "SoundFx")
		if not T.check(type(SC) == "table" and type(SFX) == "table", "store gem thanks: StoreController and SoundFx load") then
			return
		end
		local saved = H.begin()
		local realPlay = SFX.Play
		local sounds = {}
		SFX.Play = function(name)
			sounds[#sounds + 1] = name
			return nil
		end
		local buy = SFX.Id("Sfx", "StoreBuy") and "StoreBuy" or "Reward"
		local from = #sounds
		-- GemService.sendThanks's text for a gem pack (GemService.lua: "+" .. commas(gems) .. " Gems! Thank you for your support!")
		KC.toClient("Notify", "+550 Gems! Thank you for your support!", "good", 4)
		KC.advance(0.3)
		T.eq(H.count(sounds, buy, from), 1, "store gem thanks: the gem pack toast plays " .. buy)
		from = #sounds
		KC.toClient("Notify", "+6,500 Gems! Thank you for your support!", "good", 4)
		KC.advance(0.3)
		T.eq(H.count(sounds, buy, from), 1, "store gem thanks: ...with commas too")
		from = #sounds
		KC.toClient("Notify", "Thank you! 500 Cloud Tokens", "good", 4)
		KC.advance(0.3)
		T.eq(H.count(sounds, buy, from), 1, "store gem thanks: the Store's \"Thank you! ...\" still plays it")
		from = #sounds
		KC.toClient("Notify", "+5 Gems from the chest!", "good", 4)
		KC.advance(0.3)
		T.eq(H.count(sounds, buy, from), 0, "store gem thanks: another gem toast plays nothing")
		SFX.Play = realPlay
		H.finish(saved)
		KC.flushErrors("client_fixr_store_gem_thanks")
	end)

	-- the rect of a gui object { x0, y0, x1, y1 }; two rects overlap (by more than a pixel); a inside b (1 px slack)
	function H.box(o)
		local p, s = o.AbsolutePosition, o.AbsoluteSize
		return { x0 = p.X, y0 = p.Y, x1 = p.X + s.X, y1 = p.Y + s.Y }
	end
	function H.overlap(a, b)
		return a.x0 < b.x1 - 1 and b.x0 < a.x1 - 1 and a.y0 < b.y1 - 1 and b.y0 < a.y1 - 1
	end
	function H.within(a, b)
		return a.x0 >= b.x0 - 1 and a.y0 >= b.y0 - 1 and a.x1 <= b.x1 + 1 and a.y1 <= b.y1 + 1
	end
	function H.desc(o)
		local b = H.box(o)
		return fmt("%s %d,%d %dx%d", o.Name, b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0)
	end

	S.client_fixr_store_portrait = guarded("client_fixr_store_portrait", function()
		local SC = H.ctrl("StoreController")
		if not T.check(type(SC) == "table" and type(SC.Open) == "function", "store portrait: StoreController loads") then
			return
		end
		local Config = KC.env()
		local UIS = game:GetService("UserInputService")
		local saved = H.begin()
		local touch = { UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
		local restoreMeasure = H.realMeasure()
		local okRun, errRun = pcall(function()
			UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = true, false, false
			Mock.SetViewport(360, 640)
			KC.advance(0.5)
			H.createAll()
			MPS.GetProductInfo = function(_, id)
				return { Name = "Product " .. tostring(id), PriceInRobux = 1999, ProductId = id } -- the widest price
			end
			local passes = {
				{ Tag = "nothing owned", Owned = "", Bought = "" },
				{ Tag = "everything owned", Owned = "VIP,Cash2x,PetXp2x", Bought = "Starter,Pro" },
			}
			for _, pass in ipairs(passes) do
				H.setAttr("OwnedPasses", pass.Owned)
				H.setAttr("StoreBought", pass.Bought)
				H.reopen(SC)
				KC.advance(0.5)
				local tag = "store portrait: 360x640 (" .. pass.Tag .. ")"
				local win = H.win()
				local gui = H.pg():FindFirstChild("NimbusShop")
				local wb = win and H.box(win)
				T.check(win ~= nil and SC.IsOpen() and SC.Layout() == "Phone" and H.within(wb, H.box(gui)) and (wb.x1 - wb.x0) >= 300,
					tag .. " (setup) the Shop opens inside the screen", win and H.desc(win) or "no window")
				-- the header: the title under no balance pill, the pills and the X inside the window, the X >= 44 (lobby-shop
				-- Task 21: Header, CloseButton, two pills: no Cash item is on sale)
				local bar = win:FindFirstChild("Header", true)
				local title = bar and bar:FindFirstChild("Title")
				local clash, outside = {}, {}
				for _, id in ipairs({ "Tokens", "Gems" }) do
					local pill = bar and bar:FindFirstChild("Balance_" .. id)
					if not pill or not H.shownIn(pill) then
						outside[#outside + 1] = "Balance_" .. id .. " missing"
					else
						if title and H.overlap(H.box(title), H.box(pill)) then
							clash[#clash + 1] = H.desc(pill) .. " over " .. H.desc(title)
						end
						if not H.within(H.box(pill), wb) then
							outside[#outside + 1] = H.desc(pill)
						end
					end
				end
				T.check(title ~= nil and #clash == 0, tag .. " the title sits under no balance pill", table.concat(clash, "; "))
				local okTitle, dTitle = H.fits(title)
				T.check(okTitle, tag .. " ...and its text fits", dTitle)
				T.check(#outside == 0, tag .. " the two balance pills inside the window", table.concat(outside, "; "))
				local close = bar and bar:FindFirstChild("CloseButton")
				T.check(close ~= nil and H.within(H.box(close), wb) and close.AbsoluteSize.X >= 43.5 and close.AbsoluteSize.Y >= 43.5, tag .. " the X inside the window, >= 44 px", close and H.desc(close) or "no X")
				-- the tabs: each inside the window, >= 44 px, its label fits, no two overlap
				local tabs, badTabs = {}, {}
				for _, tabName in ipairs(Config.Store.Tabs) do
					local tb = win:FindFirstChild("Tab_" .. tabName, true)
					if tb and H.shownIn(tb) then
						tabs[#tabs + 1] = tb
						local okL, dL = H.fits(tb:FindFirstChild("Label"))
						if not (H.within(H.box(tb), wb) and tb.AbsoluteSize.Y >= 43.5 and tb.AbsoluteSize.X >= 43.5 and okL) then
							badTabs[#badTabs + 1] = H.desc(tb) .. " " .. dL
						end
					end
				end
				for i = 1, #tabs do
					for j = i + 1, #tabs do
						if H.overlap(H.box(tabs[i]), H.box(tabs[j])) then
							badTabs[#badTabs + 1] = tabs[i].Name .. " overlaps " .. tabs[j].Name
						end
					end
				end
				T.check(#tabs >= 5 and #badTabs == 0, tag .. " every tab on screen inside the window, >= 44 px, its label fits, none overlap", #tabs .. " tabs; " .. table.concat(badTabs, "; "))
				-- every page: full-width cards whose every text fits its box and sits inside its card, Buy >= 44 px
				local checked, badCards, sizes = 0, {}, {}
				for _, tabName in ipairs(Config.Store.Tabs) do
					local tb = win:FindFirstChild("Tab_" .. tabName, true)
					local page = win:FindFirstChild("Page_" .. tabName, true)
					-- (the Eggs and Gems pages hold their own cards / tiles, checked by client_shop_portrait)
					if tabName ~= "Eggs" and tabName ~= "Gems" and tb and H.shownIn(tb) and page then
						Mock.Click(tb)
						KC.advance(0.3)
						local pb = H.box(page)
						for _, card in ipairs(page:GetChildren()) do
							if card.Name:sub(1, 5) == "Card_" and H.shownIn(card) then
								checked = checked + 1
								local cb = H.box(card)
								sizes[#sizes + 1] = fmt("%s %dx%d", card.Name:sub(6), cb.x1 - cb.x0, cb.y1 - cb.y0)
								if cb.x1 - cb.x0 < (pb.x1 - pb.x0) - 12 then
									badCards[#badCards + 1] = card.Name .. " not full width " .. H.desc(card)
								end
								for _, d in ipairs(card:GetDescendants()) do
									if (d:IsA("TextLabel") or d:IsA("TextButton")) and KC.isShown(d) and tostring(d.Text):gsub("%s", "") ~= "" then
										local okF, dF = H.fits(d)
										if not okF then
											badCards[#badCards + 1] = card.Name .. ": " .. dF
										elseif not H.within(H.box(d), cb) then
											badCards[#badCards + 1] = card.Name .. ": " .. H.desc(d) .. " outside " .. H.desc(card)
										end
									end
								end
								local buy = card:FindFirstChild("Buy", true)
								if not (buy and buy.AbsoluteSize.Y >= 43.5 and H.within(H.box(buy), cb)) then
									badCards[#badCards + 1] = card.Name .. ": Buy " .. (buy and H.desc(buy) or "missing")
								end
							end
						end
					end
				end
				T.check(checked >= 7 and #badCards == 0, tag .. " every card full width, every card text fits its box (real font widths) inside the card, Buy >= 44 px",
					checked .. " cards; " .. table.concat(badCards, "; "))
				local pf = win:FindFirstChild("Body", true)
				T.info("*" .. tag .. ": window " .. H.desc(win) .. ", pages " .. (pf and H.desc(pf) or "?") .. ", cards " .. table.concat(sizes, ", "))
			end
			-- back to a landscape phone: the cards go back to one-line texts and the side tab column
			Mock.SetViewport(844, 390)
			KC.advance(0.5)
			T.check(SC.IsOpen() and SC.Layout() == "Phone" and not (SC.Portrait and SC.Portrait()), "store portrait: 844x390 is the landscape phone layout again")
		end)
		restoreMeasure()
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = touch[1], touch[2], touch[3]
		H.finish(saved)
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_fixr_store_portrait")
		KC.flushWarnings("client_fixr_store_portrait")
	end)

	return S
end

if CONTEXT == "server" then
	return {}
end
return clientScenarios()
