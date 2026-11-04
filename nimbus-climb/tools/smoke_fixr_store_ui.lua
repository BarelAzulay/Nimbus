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
		local gui = H.pg():FindFirstChild("NimbusStore")
		return gui and gui:FindFirstChild("StoreWindow", true)
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
	local ATTRS = { "InMatch", "OwnedPasses", "StoreBought", "XpBoostEnds", "StorePreview" }
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
	function H.reopen(SC)
		SC.Close()
		KC.advance(0.2)
		SC.Open()
		KC.advance(0.5)
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
		T.check(#cards >= 12, "store colors: every created pack has a card", #cards .. " cards")
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
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and tostring(d.Text) ~= "" and d.Visible and not H.textStroked(d) then
					unstroked[#unstroked + 1] = key .. "." .. d.Name
				end
			end
		end
		T.check(#missing == 0, "store colors: every card has its own UIGradient and UIStroke", table.concat(missing, ", "))
		T.check(#dull == 0, "store colors: every gradient stop and outline is saturated", table.concat(dull, "; "))
		T.check(#clash == 0, "store colors: no two packs share a colour pair (on a tab, or in the whole Store)", table.concat(clash, "; "))
		T.check(#pale == 0, "store colors: every card has a dark stop under its white text", table.concat(pale, "; "))
		T.check(#unstroked == 0, "store colors: every card text has a stroke", table.concat(unstroked, ", ", 1, math.min(#unstroked, 8)))
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
		T.check(heroes >= 3 and #dim == 0, "store colors: each tab's hero is its brightest card with the thickest outline", heroes .. " heroes; " .. table.concat(dim, "; "))
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
		H.reopen(SC)
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
		T.check(vipArt ~= nil and vipArt:FindFirstChildWhichIsA("ImageLabel") == nil and vipGlyph ~= nil and vipGlyph.Visible and vipGlyph.Text ~= "",
			"store art: no store_vip key = the VIP card keeps its glyph")
		local tab = win:FindFirstChild("Tab_Packs", true)
		local icon = tab and tab:FindFirstChild("Icon")
		T.check(icon ~= nil and icon:IsA("ImageLabel") and icon.Image == "rbxassetid://777",
			"store art: the Packs tab icon goes through NeonKit.Icon (Config.Icons.Packs swaps in an image)", icon and icon.ClassName or "no icon")
		local passes = win:FindFirstChild("Tab_Passes", true)
		local passIcon = passes and passes:FindFirstChild("Icon")
		T.check(passIcon ~= nil and passIcon:IsA("TextLabel") and passIcon:GetAttribute("IconId") == "Passes" and passIcon.Text ~= "",
			"store art: a tab without Config.Icons keeps the NeonKit glyph (IconId Passes)", passIcon and passIcon.ClassName or "no icon")
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

	return S
end

if CONTEXT == "server" then
	return {}
end
return clientScenarios()
