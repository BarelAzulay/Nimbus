-- smoke_bug2_gui.lua: bug batch 2, lane-gui (player report #1 "Game gui needs a compact+improve", option A "Split &
-- shift"). Loaded by tools/smoke.py in the client world and the phone world:
--   client_bug2gui_layout (client, 1920x1080 + 1280x720 desktop) the menu is ONE slim column at the left edge,
--                         vertically centred, top to bottom Pets, Items, Team, Index, Shop, Home, Stats, the gear, 56 px
--                         tiles at 1080p; the arrow tab (MenuColumn.Toggle) sits beside the last tile; the currencies are
--                         thin strips stacked top-right under Roblox's top bar, right-aligned; the vitals card sits
--                         bottom-centre right above the hotbar, compact; the HUD publishes BottomLeftTop /
--                         BottomCentreTop at the card and TopRightBottom under the strips; none of them overlap. The
--                         tab folds the column against the left edge (tiles hidden, only the tab at x 0, MenuCollapsed),
--                         the fold survives a relayout, the tab repeats a tile's red dot while folded, a second click
--                         brings the column back and the Pets tile still opens the Pets window; a tutorial step that
--                         points at a tile unfolds a folded column
--   client_bug2gui_mobile (phone world, touch) at 844x390, 740x360, 667x375, 390x844 and 1024x768: the tiles stay
--                         >= 44 px (wrapping into two columns where one does not fit) and end above Roblox's thumbstick
--                         zone; the tab is a thumb-sized target; the vitals card stays clear of the thumbstick zone, the
--                         jump button, the RUN / DASH buttons, the hotbar, the column and the strips; the strips sit
--                         top-right with readable numbers (>= 14 px) and touch nothing else (one row on the portrait
--                         phone); the dungeon End card never covers them (they step aside, and come back); in a battle
--                         on a landscape phone they move into Roblox's top band (CurrencyMode "TopBand") and back
-- Studio check of #1 (wave 4a phone fixes):
--   client_bug2gui_stickemu (client, keyboard + touch like Studio's device emulator / a touch laptop) a TouchGui with
--                         a visible DynamicThumbstickFrame (built like PlayerModule's DynamicThumbstick) puts the
--                         column into its touch layout: at 749x388 (iPhone 14), 800x360 (Galaxy A06), 667x375
--                         (iPhone 7), 844x390 and 740x360 it ends >= 10 px above ThumbstickStart's top with tiles
--                         >= 44 px; the stick going away gives back the desktop column
--   client_bug2gui_stick_mobile (phone world) the same rule against the same TouchGui on a touch-only phone
--   client_bug2gui_empty / client_bug2gui_empty_mobile the "No pets yet!" empty state of the Pets page and the Team
--                         picker's (one helper, P5.emptyState): the Open Shop button's left and right edges inside its
--                         column, the title / body / button text fits its box (TextFits, and the mock's text extent
--                         at the label's scale), the block inside the grid well, at desktop and phone sizes
-- Deterministic: mock clock only, no RNG; the viewport, the fold and the tutorial state are restored at the end.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local KC = _G.KC
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local H = {}

function H.client(name)
	return require(Mock.GetPath(ROOTS["client"] .. "/" .. name))
end
function H.shared(name)
	return require(Mock.GetPath(ROOTS["shared"] .. "/" .. name))
end
function H.mod(name)
	return (KC.M and KC.M[name]) or H.client("Controllers/" .. name)
end
function H.pg()
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end
-- screen rect (the top bar included) of a GuiObject
function H.rect(obj)
	local gui = obj:FindFirstAncestorOfClass("ScreenGui")
	local dy = (gui and not gui.IgnoreGuiInset) and (Mock.TopInset or 0) or 0
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + dy + s.Y }
end
function H.shown(obj)
	local node = obj
	while node and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node ~= nil and node.Enabled ~= false and obj.AbsoluteSize.X > 0
end
function H.overlap(a, b)
	return a.x0 < b.x1 - 0.5 and b.x0 < a.x1 - 0.5 and a.y0 < b.y1 - 0.5 and b.y0 < a.y1 - 0.5
end
function H.fmt(r)
	return r and string.format("%.0f,%.0f - %.0f,%.0f", r.x0, r.y0, r.x1, r.y1) or "none"
end
function H.path(root, dotted)
	local node = root
	for part in string.gmatch(dotted, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end
function H.parts()
	local pg = H.pg()
	local column = H.path(pg, "NimbusMenu.MenuColumn")
	return {
		Menu = pg:FindFirstChild("NimbusMenu"),
		Hud = pg:FindFirstChild("NimbusHud"),
		Column = column,
		Tab = column and column:FindFirstChild("Toggle"),
		Currency = H.path(pg, "NimbusHud.TopRight.Currency"),
		Vitals = H.path(pg, "NimbusHud.BottomLeft.Vitals"),
		Hotbar = H.path(pg, "NimbusHotbar.Hotbar"),
	}
end
H.ORDER = { "Pets", "Inventory", "Team", "Index", "Shop", "Spot", "Stats", "Settings" }
function H.tile(id)
	local column = H.parts().Column
	local e = column and (column:FindFirstChild("Entry_" .. id) or column:FindFirstChild("Gear_" .. id))
	return e and e:FindFirstChild("MenuButton_" .. id, true)
end
-- Roblox's touch controls at the screen's bottom (screen px), like HudController / MenuController model them
function H.robloxTouch(w, h)
	local small = math.min(w, h) <= 500
	local j = small and 70 or 120
	local jumpBottom = small and 20 or j * 0.75
	return {
		Stick = { x0 = 0, y0 = h - (small and 96 or 210), x1 = small and 110 or 190, y1 = h },
		Jump = { x0 = w - (1.5 * j + 10), y0 = h - jumpBottom - j, x1 = w - (0.5 * j + 10), y1 = h - jumpBottom },
	}
end
function H.closeAll()
	local MC = H.mod("MenuController")
	if MC and type(MC.Close) == "function" then
		pcall(MC.Close)
	end
	KC.advance(0.5)
end
function H.unfold()
	local MC = H.mod("MenuController")
	if MC and type(MC.SetColumnCollapsed) == "function" then
		MC.SetColumnCollapsed(false, false)
	end
	KC.advance(0.4)
end

----------------------------------------------------------------------------------------------------
-- desktop
----------------------------------------------------------------------------------------------------
S.client_bug2gui_layout = guarded("client_bug2gui_layout", function()
	local MC = H.mod("MenuController")
	local old = { Mock.Viewport.X, Mock.Viewport.Y }
	KC.toClient("MatchState", nil)
	KC.toClient("PartyState", nil)
	LocalPlayer:SetAttribute("InMatch", false)
	local Config = H.shared("Config")
	local oldCash, oldGems = LocalPlayer:GetAttribute(Config.Attr.Cash), LocalPlayer:GetAttribute(Config.Attr.Gems)
	LocalPlayer:SetAttribute(Config.Attr.Cash, 97100)
	LocalPlayer:SetAttribute(Config.Attr.Gems, 3)
	H.closeAll()
	H.unfold()
	local inset = Mock.TopInset or 58

	for _, size in ipairs({ { 1920, 1080 }, { 1280, 720 } }) do
		Mock.SetViewport(size[1], size[2])
		KC.advance(1.2)
		local W, Hh = size[1], size[2]
		local label = string.format("bug2gui %dx%d", W, Hh)
		local p = H.parts()
		if not T.check(p.Column and p.Tab and p.Currency and p.Vitals and p.Hotbar, label .. ": the column, its tab, the strips, the vitals and the hotbar exist") then
			break
		end
		-- 1. one slim column at the left edge, vertically centred
		local rects, oneColumn = {}, true
		for i, id in ipairs(H.ORDER) do
			local b = H.tile(id)
			rects[i] = b and H.shown(b) and H.rect(b) or nil
			oneColumn = oneColumn and rects[i] ~= nil
			if oneColumn and i > 1 then
				oneColumn = math.abs(rects[i].x0 - rects[i - 1].x0) < 1 and rects[i].y0 >= rects[i - 1].y1
			end
		end
		T.check(oneColumn, label .. ": ONE column of eight tiles, Pets .. Settings top to bottom")
		local want = (W == 1920) and 56 or 44.8
		local sizeOk = oneColumn
		for _, r in ipairs(rects) do
			sizeOk = sizeOk and math.abs((r.x1 - r.x0) - want) <= 2 and (r.x1 - r.x0) >= 44
		end
		T.check(sizeOk, label .. ": tiles are " .. want .. " px (>= 44)", rects[1] and string.format("%.1f px", rects[1].x1 - rects[1].x0) or "none")
		local col = H.rect(p.Column)
		local mid = inset + (Hh - inset) / 2
		T.check(col.x0 >= 0 and col.x0 <= 16 and math.abs((col.y0 + col.y1) / 2 - mid) < 6, label .. ": the column hugs the left edge, vertically centred", H.fmt(col))
		T.check(col.x1 - col.x0 <= 100, label .. ": ...and is slim (<= 100 px wide with its tab)", H.fmt(col))
		-- 2. the arrow tab beside the last tile (the gear)
		local tab = H.rect(p.Tab)
		local gear = rects[8]
		T.check(H.shown(p.Tab) and gear ~= nil and tab.x0 >= gear.x1 and tab.y0 >= gear.y0 - 1 and tab.y1 <= gear.y1 + 1 and (tab.x1 - tab.x0) >= 16,
			label .. ": the hide arrow tab sits right of the gear tile", H.fmt(tab))
		local arrow = p.Tab:FindFirstChild("Arrow")
		T.check(arrow ~= nil and arrow.Text == "<", label .. ": ...pointing left ('<') while the column is out", arrow and arrow.Text or "none")
		-- 3. the currencies: thin strips top-right under the top bar
		local cur = H.rect(p.Currency)
		local strips, stripOk = 0, true
		for _, c in ipairs(p.Currency:GetChildren()) do
			if c:IsA("GuiObject") and c.Name:find("^Currency_") and H.shown(c) then
				strips = strips + 1
				local r = H.rect(c)
				stripOk = stripOk and (r.y1 - r.y0) <= 36 and (r.x1 - r.x0) <= 180 and math.abs(r.x1 - cur.x1) < 1
			end
		end
		T.check(strips == 3 and stripOk and cur.y0 >= inset - 0.5 and cur.x1 >= W - 16 and cur.y1 <= inset + 140,
			label .. ": three thin strips (<= 180 x 36 px) stacked top-right, right-aligned, under the top bar", H.fmt(cur))
		-- 4. the vitals bottom-centre above the hotbar, compact
		local v, hb = H.rect(p.Vitals), H.rect(p.Hotbar)
		-- (centred on the hotbar: the bar itself is centred unless a side panel pushes it left, and the card follows it)
		T.check(v.y1 <= hb.y0 + 1 and hb.y0 - v.y1 <= 24 and math.abs((v.x0 + v.x1) / 2 - (hb.x0 + hb.x1) / 2) < 4 and math.abs((v.x0 + v.x1) / 2 - W / 2) < W * 0.2,
			label .. ": the vitals sit bottom-centre right above the hotbar, centred on it", H.fmt(v) .. " / bar " .. H.fmt(hb))
		local k = W == 1920 and 1 or 0.8
		T.check(v.x1 - v.x0 <= 320 * k, label .. ": ...compact (<= 320 design px wide)", string.format("%.0f px", v.x1 - v.x0))
		-- 5. what the HUD tells its neighbours (gui-area px)
		local hud = p.Hud
		local blt, bct, trb = hud:GetAttribute("BottomLeftTop"), hud:GetAttribute("BottomCentreTop"), hud:GetAttribute("TopRightBottom")
		T.check(type(blt) == "number" and math.abs(blt - (v.y0 - inset)) <= 1 and bct == blt, label .. ": BottomLeftTop / BottomCentreTop = the vitals' top",
			tostring(blt) .. " vs " .. tostring(v.y0 - inset))
		T.check(type(trb) == "number" and trb >= cur.y1 - inset - 1 and hud:GetAttribute("CurrencyMode") == "TopRight", label .. ": TopRightBottom under the strips (toasts start there)", tostring(trb))
		-- 6. nothing overlaps
		local named = { { "column", col }, { "strips", cur }, { "vitals", v }, { "hotbar", hb } }
		local clash = {}
		for i = 1, #named do
			for j = i + 1, #named do
				if H.overlap(named[i][2], named[j][2]) then
					clash[#clash + 1] = named[i][1] .. " x " .. named[j][1]
				end
			end
		end
		T.check(#clash == 0, label .. ": the column, the strips, the vitals and the hotbar never overlap", table.concat(clash, ", "))
	end

	-- 7. the fold: the tab slides the column against the edge, remembered across a relayout
	Mock.SetViewport(1920, 1080)
	KC.advance(1)
	local p = H.parts()
	local pets = H.tile("Pets")
	Mock.Click(p.Tab)
	KC.advance(0.6)
	T.check(MC.IsColumnCollapsed() == true and p.Menu:GetAttribute("MenuCollapsed") == true, "bug2gui fold: a click on the tab folds the column (MenuCollapsed)")
	local tab = H.rect(p.Tab)
	T.check(pets ~= nil and not H.shown(pets) and H.shown(p.Tab) and tab.x0 <= 1 and tab.x0 >= -1, "bug2gui fold: ...the tiles are gone, only the tab shows, flush with the left edge", H.fmt(tab))
	T.check(p.Tab.Arrow.Text == ">", "bug2gui fold: ...its arrow points right ('>')", p.Tab.Arrow.Text)
	Mock.SetViewport(1280, 720)
	KC.advance(0.8)
	Mock.SetViewport(1920, 1080)
	KC.advance(0.8)
	tab = H.rect(p.Tab)
	T.check(MC.IsColumnCollapsed() == true and not H.shown(pets) and tab.x0 <= 1, "bug2gui fold: the fold is remembered through a relayout (screen resize)", H.fmt(tab))
	local hud = p.Hud
	local v = H.rect(p.Vitals)
	local hb = H.rect(p.Hotbar)
	T.check(math.abs((v.x0 + v.x1) / 2 - (hb.x0 + hb.x1) / 2) < 4 and v.y1 <= hb.y0 + 1, "bug2gui fold: the vitals stay above the hotbar while folded", H.fmt(v))
	-- the tab repeats a tile's red dot while folded
	local dot = pets and pets:FindFirstChild("Badge", true)
	local tabDot = p.Tab:FindFirstChild("Badge")
	if T.check(dot ~= nil and tabDot ~= nil, "bug2gui fold: the Pets tile and the tab both have a badge dot") then
		-- (earlier scenarios may have left a tile's dot on: clear them all first, put them back after)
		local saved = {}
		for _, id in ipairs(H.ORDER) do
			local t = H.tile(id)
			local d = t and t:FindFirstChild("Badge", true)
			if d then
				saved[d] = d.Visible
				d.Visible = false
			end
		end
		KC.advance(0.6)
		T.check(not tabDot.Visible, "bug2gui fold: (no tile badge: no dot on the tab)")
		dot.Visible = true
		KC.advance(0.6)
		T.check(tabDot.Visible, "bug2gui fold: a red dot on a tile (new pets) shows on the folded tab")
		dot.Visible = false
		KC.advance(0.6)
		T.check(not tabDot.Visible, "bug2gui fold: ...and goes with it")
		for d, was in pairs(saved) do
			d.Visible = was
		end
	end
	-- unfold with the tab: the tiles come back and still open their windows
	Mock.Click(p.Tab)
	KC.advance(0.6)
	T.check(MC.IsColumnCollapsed() == false and H.shown(pets) and H.rect(pets).x0 >= 10, "bug2gui fold: a second click brings the column back", pets and H.fmt(H.rect(pets)))
	Mock.Click(pets)
	KC.advance(0.8)
	local inv = p.Menu:FindFirstChild("Window_Inventory")
	T.check(inv ~= nil and inv.Visible, "bug2gui fold: the Pets tile still opens the Pets window")
	H.closeAll()

	-- 8. a tutorial step that points at a tile unfolds a folded column
	local TC = H.mod("TutorialController")
	local Steps = H.shared("TutorialSteps")
	local index = nil
	for i, step in ipairs(Steps.Steps or {}) do
		if type(step.Target) == "table" and step.Target.Kind == "Menu" then
			index = i
			break
		end
	end
	if T.check(type(TC) == "table" and type(TC.GetState) == "function" and index ~= nil, "bug2gui tutorial: TutorialController and a Menu step are there") then
		local saved = TC.GetState()
		local step = Steps.Steps[index]
		local payload = {
			Step = index, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = "Open your pets", Target = step.Target,
			CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, AlsoNext = step.AlsoNext == true,
			Chapter = step.Chapter, Done = false, Completed = false, Skipped = false, Reward = 0,
		}
		KC.toClient("TutorialState", { Done = true, Step = #Steps.Steps, Total = #Steps.Steps })
		KC.advance(0.6)
		MC.SetColumnCollapsed(true, false)
		KC.advance(0.6)
		T.check(MC.IsColumnCollapsed() == true, "bug2gui tutorial: (setup) the column is folded")
		KC.toClient("TutorialState", payload)
		KC.advance(1.2)
		T.check(MC.IsColumnCollapsed() == false and H.shown(H.tile(step.Target.Id == "Home" and "Spot" or step.Target.Id)),
			"bug2gui tutorial: a step pointing at the " .. tostring(step.Target.Id) .. " tile unfolds the column")
		if saved then
			KC.toClient("TutorialState", saved)
		else
			KC.toClient("TutorialState", { Done = true, Step = #Steps.Steps, Total = #Steps.Steps })
		end
		KC.advance(1.2)
	end

	H.unfold()
	LocalPlayer:SetAttribute(Config.Attr.Cash, oldCash)
	LocalPlayer:SetAttribute(Config.Attr.Gems, oldGems)
	Mock.SetViewport(old[1], old[2])
	KC.advance(1)
	KC.flushErrors("client_bug2gui_layout")
end)

----------------------------------------------------------------------------------------------------
-- phones and tablets (the phone world: touch at boot)
----------------------------------------------------------------------------------------------------
S.client_bug2gui_mobile = guarded("client_bug2gui_mobile", function()
	local UIS = game:GetService("UserInputService")
	T.check(UIS.TouchEnabled == true, "bug2gui phone: (precondition) a touch device")
	local old = { Mock.Viewport.X, Mock.Viewport.Y }
	KC.toClient("MatchState", nil)
	KC.toClient("PartyState", nil)
	LocalPlayer:SetAttribute("InMatch", false)
	local Config = H.shared("Config")
	local oldCash, oldGems = LocalPlayer:GetAttribute(Config.Attr.Cash), LocalPlayer:GetAttribute(Config.Attr.Gems)
	LocalPlayer:SetAttribute(Config.Attr.Cash, 97100)
	LocalPlayer:SetAttribute(Config.Attr.Gems, 3)
	H.closeAll()
	H.unfold()
	local inset = Mock.TopInset or 58
	for _, size in ipairs({ { 844, 390 }, { 740, 360 }, { 667, 375 }, { 390, 844 }, { 1024, 768 } }) do
		local W, Hh = size[1], size[2]
		Mock.SetViewport(W, Hh)
		KC.advance(1.5)
		local label = string.format("bug2gui phone %dx%d", W, Hh)
		local p = H.parts()
		if not T.check(p.Column and p.Tab and p.Currency and p.Vitals and p.Hotbar, label .. ": the column, its tab, the strips, the vitals and the hotbar exist") then
			break
		end
		local touch = H.robloxTouch(W, Hh)
		-- the tiles: >= 44 px, inside the screen, ending above the thumbstick zone
		local minTile, lowest, inside = math.huge, 0, true
		for _, id in ipairs(H.ORDER) do
			local b = H.tile(id)
			if b and H.shown(b) then
				local r = H.rect(b)
				minTile = math.min(minTile, r.x1 - r.x0, r.y1 - r.y0)
				lowest = math.max(lowest, r.y1)
				inside = inside and r.x0 >= 0 and r.y0 >= inset - 0.5
			else
				minTile = 0
			end
		end
		T.check(minTile >= 44 and inside, label .. ": every tile is shown, >= 44 px, inside the screen", string.format("%.1f px", minTile))
		T.check(lowest <= touch.Stick.y0, label .. ": the tiles end above the thumbstick zone", string.format("bottom %.0f, stick top %.0f", lowest, touch.Stick.y0))
		local tab = H.rect(p.Tab)
		T.check(H.shown(p.Tab) and tab.x1 - tab.x0 >= 20 and tab.y1 - tab.y0 >= 44 and tab.y1 <= touch.Stick.y0, label .. ": the arrow tab is a thumb target (>= 20 x 44 px) above the stick", H.fmt(tab))
		-- the tab right after the gear (the last row's last tile), no empty tile slot between them (3 columns on
		-- 740x360-class phones leave the last row with 2 tiles)
		local gearB = H.tile("Settings")
		local gear = gearB and H.shown(gearB) and H.rect(gearB)
		T.check(gear and tab.x0 >= gear.x1 - 0.5 and tab.x0 - gear.x1 <= 8 and tab.y0 >= gear.y0 - 1 and tab.y1 <= gear.y1 + 1,
			label .. ": the arrow tab sits right after the gear tile (no empty slot)", H.fmt(tab) .. " vs gear " .. (gear and H.fmt(gear) or "none"))
		if W == 740 then
			-- folded, the tab still ends flush with the left edge (the fold offset follows the tab, not the tiles' width)
			local MC = H.mod("MenuController")
			MC.SetColumnCollapsed(true, false)
			KC.advance(0.4)
			local ft = H.rect(p.Tab)
			T.check(MC.IsColumnCollapsed() == true and H.shown(p.Tab) and ft.x0 >= -1 and ft.x0 <= 1 and not H.shown(H.tile("Pets")),
				label .. ": folded, only the tab shows, flush with the left edge", H.fmt(ft))
			H.unfold()
		end
		-- the column never reaches into the middle of the screen (the layout rule: |dx| < 14.5% of the width)
		local col = H.rect(p.Column)
		T.check(col.x1 <= W * 0.355, label .. ": the column stays out of the middle of the screen", H.fmt(col))
		-- the vitals: clear of Roblox's stick / jump button, the touch buttons and every other block
		local v = H.rect(p.Vitals)
		local others = { { "the thumbstick zone", touch.Stick }, { "the jump button", touch.Jump }, { "the hotbar", H.rect(p.Hotbar) },
			{ "the menu column", H.rect(p.Column) }, { "the currency strips", H.rect(p.Currency) } }
		local mobile = H.pg():FindFirstChild("MobileControls")
		for _, d in ipairs(mobile and mobile:GetDescendants() or {}) do
			if (d:IsA("TextButton") or d:IsA("ImageButton")) and H.shown(d) then
				others[#others + 1] = { "the " .. d.Name, H.rect(d) }
			end
		end
		local hit = {}
		for _, o in ipairs(others) do
			if H.overlap(v, o[2]) then
				hit[#hit + 1] = o[1] .. " " .. H.fmt(o[2])
			end
		end
		T.check(#hit == 0 and v.x0 >= 0 and v.x1 <= W and v.y1 <= Hh, label .. ": the vitals card touches nothing (stick, jump, RUN / DASH, hotbar, column, strips)",
			H.fmt(v) .. (#hit > 0 and (" vs " .. table.concat(hit, "; ")) or ""))
		-- the strips: top-right, readable, clear of the column and the jump / touch buttons
		local cur = H.rect(p.Currency)
		local small = {}
		local ui = p.Currency:FindFirstChildOfClass("UIScale")
		for _, d in ipairs(p.Currency:GetDescendants()) do
			if d:IsA("TextLabel") and H.shown(d) and d.Text ~= "" then
				local px = d.TextSize * (ui and ui.Scale or 1)
				if px < 14 - 0.01 then
					small[#small + 1] = d.Name .. string.format(" %.1f px", px)
				end
			end
		end
		T.check(cur.x1 >= W - 24 and cur.y0 >= inset - 0.5 and cur.y1 <= inset + 0.45 * (Hh - inset) and #small == 0,
			label .. ": the strips sit top-right under the top bar, numbers >= 14 px", H.fmt(cur) .. " " .. table.concat(small, ", "))
		T.check(not H.overlap(cur, H.rect(p.Column)) and not H.overlap(cur, touch.Jump), label .. ": ...clear of the column and the jump button")
		-- a dungeon run's End card takes the top-right corner of a phone for a moment: the strips step out of its way
		local run = H.pg():FindFirstChild("NimbusDungeonRun")
		if (W == 844 or W == 390) and run then
			KC.toClient("DungeonState", "End", { Floor = 1, Name = "Mossy Cellar", Cleared = true, Reason = "Cleared", Room = 4,
				Totals = { Cash = 100, Tokens = 10, Xp = 20, Gems = 0 } })
			KC.advance(1.2)
			local card = run:FindFirstChild("EndCard")
			if T.check(card ~= nil and H.shown(card), label .. ": (setup) the dungeon End card shows") then
				local covered = H.shown(p.Currency) and H.overlap(H.rect(card), H.rect(p.Currency))
				T.check(not covered, label .. ": the dungeon End card never sits on the currency strips", H.fmt(H.rect(card)) .. " vs " .. H.fmt(cur))
				-- the card starts below the strips (DungeonController reads TopRightBottom), so they stay in view
				local cr = H.rect(card)
				T.check(H.shown(p.Currency) and cr.y0 >= H.rect(p.Currency).y1 and cr.y1 <= Hh and not H.overlap(cr, touch.Jump),
					label .. ": ...it starts below them (the strips stay in view), on screen and clear of the jump button", H.fmt(cr))
				local ok = card:FindFirstChild("OkButton", true)
				if ok then
					Mock.Click(ok)
				end
				KC.advance(1.2)
				T.check(not H.shown(card) and H.shown(p.Currency), label .. ": ...and the strips are back once it closes")
			end
		end
	end
	-- in a battle / dungeon run on a landscape phone the battle HUD owns the right edge: the strips move into Roblox's
	-- top band (one row) at once, and back to the corner when it ends
	Mock.SetViewport(844, 390)
	KC.advance(1.2)
	local hud = H.pg():FindFirstChild("NimbusHud")
	local cur = H.path(H.pg(), "NimbusHud.TopRight.Currency")
	LocalPlayer:SetAttribute(Config.Attr.InBattle or "InBattle", "B901")
	KC.advance(0.1)
	local band = cur and H.rect(cur)
	T.check(hud:GetAttribute("CurrencyMode") == "TopBand" and band and (band.y0 + band.y1) / 2 < inset and band.x0 >= 150 - 0.5 and band.x1 <= 844 - 60,
		"bug2gui phone 844x390: in a battle the strips sit in one row inside Roblox's top band", H.fmt(band))
	LocalPlayer:SetAttribute(Config.Attr.InBattle or "InBattle", nil)
	KC.advance(0.1)
	band = cur and H.rect(cur)
	T.check(hud:GetAttribute("CurrencyMode") == "TopRight" and band and band.y0 >= inset - 0.5, "bug2gui phone 844x390: ...and back to the top-right corner after it", H.fmt(band))
	-- a portrait phone: one row of strips out of a battle, the narrow stack in one (the fighter card narrows beside it)
	Mock.SetViewport(390, 844)
	KC.advance(1.2)
	local row = cur and H.rect(cur)
	LocalPlayer:SetAttribute(Config.Attr.InBattle or "InBattle", "B902")
	KC.advance(0.1)
	local stack = cur and H.rect(cur)
	LocalPlayer:SetAttribute(Config.Attr.InBattle or "InBattle", nil)
	KC.advance(0.1)
	local back = cur and H.rect(cur)
	T.check(row and stack and back and (stack.y1 - stack.y0) > 1.5 * (row.y1 - row.y0) and (stack.x1 - stack.x0) < (row.x1 - row.x0)
		and math.abs((back.y1 - back.y0) - (row.y1 - row.y0)) < 1,
		"bug2gui phone 390x844: the strips are one row out of a battle, a stack in one, and a row again after",
		(row and H.fmt(row) or "") .. " / " .. (stack and H.fmt(stack) or "") .. " / " .. (back and H.fmt(back) or ""))
	LocalPlayer:SetAttribute(Config.Attr.Cash, oldCash)
	LocalPlayer:SetAttribute(Config.Attr.Gems, oldGems)
	Mock.SetViewport(old[1], old[2])
	KC.advance(1)
	KC.flushErrors("client_bug2gui_mobile")
end)

----------------------------------------------------------------------------------------------------
-- Studio check of #1: the column vs Roblox's real thumbstick ring, and the empty states on phones
----------------------------------------------------------------------------------------------------
-- A TouchGui like PlayerModule's (TouchControlFrame > DynamicThumbstickFrame > ThumbstickStart, the idle ring): the
-- frame is 0.4 x 2/3 of the gui area (+ a 100 px safe inset) from 1/3 down, the ring 3.7 x 20 px (40 on screens
-- whose gui area's short side is > 500) centred 3.3 rings in and 2.8 rings up from the frame's inset corner. In
-- Studio's iPhone 14 emulation (749x388) this gives ThumbstickStart (29,237) 74 px and the frame (-100,110) 400x320,
-- the values measured in Studio.
function H.touchGui(W, Hh)
	local pg = H.pg()
	local old = pg:FindFirstChild("TouchGui")
	if old then
		old:Destroy()
	end
	local inset = Mock.TopInset or 58
	local areaW, areaH = W, Hh - inset
	local ring = (math.min(areaW, areaH) > 500) and 40 or 20
	local safe = 100
	local g = Instance.new("ScreenGui")
	g.Name = "TouchGui"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = false
	local frame = Instance.new("Frame")
	frame.Name = "TouchControlFrame"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Parent = g
	local stick = Instance.new("Frame")
	stick.Name = "DynamicThumbstickFrame"
	stick.BackgroundTransparency = 1
	if areaW >= areaH then
		stick.Size = UDim2.new(0.4, safe, 2 / 3, safe)
		stick.Position = UDim2.new(0, -safe, 1 / 3, 0)
	else
		stick.Size = UDim2.new(1, safe, 0.4, safe)
		stick.Position = UDim2.new(0, -safe, 0.6, 0)
	end
	stick.Parent = frame
	local start = Instance.new("ImageLabel")
	start.Name = "ThumbstickStart"
	start.BackgroundTransparency = 1
	start.AnchorPoint = Vector2.new(0.5, 0.5)
	start.Position = UDim2.new(0, ring * 3.3 + safe, 1, -ring * 2.8 - safe)
	start.Size = UDim2.fromOffset(ring * 3.7, ring * 3.7)
	start.Parent = stick
	g.Parent = pg
	return g, start
end

-- the column against the ring: shown tiles >= 44 px, under the top bar, the column (tab included) ending >= 10 px
-- above ThumbstickStart's top
function H.checkStick(label, start)
	local inset = Mock.TopInset or 58
	local p = H.parts()
	local ring = H.rect(start)
	local minTile, lowest, inside = math.huge, 0, true
	for _, id in ipairs(H.ORDER) do
		local b = H.tile(id)
		if b and H.shown(b) then
			local r = H.rect(b)
			minTile = math.min(minTile, r.x1 - r.x0, r.y1 - r.y0)
			lowest = math.max(lowest, r.y1)
			inside = inside and r.x0 >= 0 and r.y0 >= inset - 0.5
		else
			minTile = 0
		end
	end
	lowest = math.max(lowest, H.rect(p.Column).y1)
	T.check(minTile >= 44 and inside, label .. ": every tile is shown, >= 44 px, under the top bar", string.format("%.1f px", minTile))
	T.check(lowest <= ring.y0 - 10, label .. ": the column ends >= 10 px above Roblox's thumbstick ring (ThumbstickStart)",
		string.format("column bottom %.0f, ring top %.0f (gap %.0f)", lowest, ring.y0, ring.y0 - lowest))
end

H.STICK_SIZES = { { 749, 388 }, { 800, 360 }, { 667, 375 }, { 844, 390 }, { 740, 360 } }

S.client_bug2gui_stickemu = guarded("client_bug2gui_stickemu", function()
	local UIS = game:GetService("UserInputService")
	local oldTouch, oldKeys = UIS.TouchEnabled, UIS.KeyboardEnabled
	local old = { Mock.Viewport.X, Mock.Viewport.Y }
	KC.toClient("MatchState", nil)
	KC.toClient("PartyState", nil)
	LocalPlayer:SetAttribute("InMatch", false)
	H.closeAll()
	H.unfold()
	-- Studio's device emulator / a touch laptop: touch AND a keyboard (MenuController's touchDevice stays false)
	UIS.TouchEnabled = true
	UIS.KeyboardEnabled = true
	local gui = nil
	for _, size in ipairs(H.STICK_SIZES) do
		local W, Hh = size[1], size[2]
		Mock.SetViewport(W, Hh)
		local start
		gui, start = H.touchGui(W, Hh)
		KC.advance(1.2) -- the menu polls for the stick 4x a second
		H.checkStick(string.format("bug2gui emulator %dx%d", W, Hh), start)
	end
	-- the stick goes away (the player types / clicks on a hybrid device): the desktop column comes back, centred
	if gui then
		gui:Destroy()
	end
	Mock.SetViewport(1280, 720)
	KC.advance(1.2)
	local col = H.rect(H.parts().Column)
	local inset = Mock.TopInset or 58
	local pets = H.tile("Pets")
	local pr = pets and H.rect(pets)
	T.check(pets ~= nil and H.shown(pets) and math.abs((col.y0 + col.y1) / 2 - (inset + (720 - inset) / 2)) < 6 and pr.x1 - pr.x0 <= 46,
		"bug2gui emulator: without the thumbstick the desktop column is back (44.8 px tiles, vertically centred)", H.fmt(col))
	UIS.TouchEnabled, UIS.KeyboardEnabled = oldTouch, oldKeys
	Mock.SetViewport(old[1], old[2])
	KC.advance(1)
	KC.flushErrors("client_bug2gui_stickemu")
end)

S.client_bug2gui_stick_mobile = guarded("client_bug2gui_stick_mobile", function()
	local old = { Mock.Viewport.X, Mock.Viewport.Y }
	KC.toClient("MatchState", nil)
	KC.toClient("PartyState", nil)
	LocalPlayer:SetAttribute("InMatch", false)
	H.closeAll()
	H.unfold()
	local gui = nil
	for _, size in ipairs(H.STICK_SIZES) do
		local W, Hh = size[1], size[2]
		Mock.SetViewport(W, Hh)
		local start
		gui, start = H.touchGui(W, Hh)
		KC.advance(1.2)
		H.checkStick(string.format("bug2gui phone stick %dx%d", W, Hh), start)
	end
	if gui then
		gui:Destroy()
	end
	Mock.SetViewport(old[1], old[2])
	KC.advance(1)
	KC.flushErrors("client_bug2gui_stick_mobile")
end)

-- product of the UIScales from obj up to its ScreenGui (text sizes and the mock's text extent are unscaled px)
function H.scaleOf(obj)
	local s, node = 1, obj
	while node and not node:IsA("ScreenGui") do
		local u = node:FindFirstChildOfClass("UIScale")
		if u then
			s = s * u.Scale
		end
		node = node.Parent
	end
	return s
end
-- TextFits, and its equivalent from the mock's text extent at the label's scale (wrapped to the box's width)
function H.textFits(lbl)
	local s = H.scaleOf(lbl)
	local abs = lbl.AbsoluteSize
	local w, h = Mock.TextExtent(lbl, lbl.TextWrapped and (abs.X / math.max(s, 0.01)) or nil)
	local ok = lbl.TextFits ~= false and w * s <= abs.X + 1 and h * s <= abs.Y + 1
	return ok, string.format("'%s' needs %.0fx%.0f in %.0fx%.0f", lbl.Text, w * s, h * s, abs.X, abs.Y)
end

-- one empty state: the button's edges (and its 4 px glow) inside the column, every text fits, the block inside its
-- column vertically too (a fixed well; a scrolling list may grow)
function H.checkEmpty(label, empty, fixed)
	if not T.check(empty ~= nil and H.shown(empty), label .. ": (setup) the empty state shows") then
		return
	end
	local column = H.rect(empty.Parent)
	local button = nil
	for _, d in ipairs(empty:GetChildren()) do
		if d:IsA("TextButton") then
			button = d
		end
	end
	if T.check(button ~= nil and H.shown(button), label .. ": the Open Shop button shows") then
		local b = H.rect(button)
		T.check(b.x0 - 4 >= column.x0 - 0.5 and b.x1 + 4 <= column.x1 + 0.5 and b.x1 - b.x0 >= 60,
			label .. ": the button's left and right edges (and its glow) stay inside its column", H.fmt(b) .. " in " .. H.fmt(column))
		local ok, why = H.textFits(button)
		T.check(ok, label .. ": the button's text fits", why)
	end
	local bad, lowest, highest = {}, -math.huge, math.huge
	for _, d in ipairs(empty:GetChildren()) do
		if d:IsA("GuiObject") and H.shown(d) then
			local r = H.rect(d)
			lowest, highest = math.max(lowest, r.y1), math.min(highest, r.y0)
			if r.x0 < column.x0 - 0.5 or r.x1 > column.x1 + 0.5 then
				bad[#bad + 1] = d.Name .. " out of the column " .. H.fmt(r)
			end
			if d:IsA("TextLabel") then
				local ok, why = H.textFits(d)
				if not ok then
					bad[#bad + 1] = d.Name .. ": " .. why
				end
			end
		end
	end
	T.check(#bad == 0, label .. ": the title and the body wrap inside the column and their text fits", table.concat(bad, "; "))
	if fixed then
		T.check(highest >= column.y0 - 0.5 and lowest <= column.y1 + 0.5, label .. ": the whole block fits in the grid's well",
			string.format("%.0f..%.0f in %s", highest, lowest, H.fmt(column)))
	end
end

function H.emptyRun(world, sizes)
	local State = H.client("State")
	local oldKeys, oldLoaded = State.Keys, State.IsLoaded
	local old = { Mock.Viewport.X, Mock.Viewport.Y }
	KC.toClient("MatchState", nil)
	KC.toClient("PartyState", nil)
	LocalPlayer:SetAttribute("InMatch", false)
	H.closeAll()
	H.unfold()
	State.Keys = function()
		return {} -- no pets yet
	end
	State.IsLoaded = function()
		return true -- (not "Loading...": the Open Shop button shows)
	end
	local ok, err = pcall(function()
		for _, size in ipairs(sizes) do
			local W, Hh = size[1], size[2]
			Mock.SetViewport(W, Hh)
			KC.advance(1)
			local label = string.format("bug2gui %s %dx%d", world, W, Hh)
			H.closeAll()
			Mock.Click(H.tile("Pets"))
			KC.advance(1)
			local inv = H.parts().Menu:FindFirstChild("Window_Inventory")
			local well = inv and inv:FindFirstChild("GridWell", true)
			H.checkEmpty(label .. " Pets", well and well:FindFirstChild("Empty"), true)
			-- the helper itself: squeezed into a 150 design px column the button still takes only the column's width
			local left = well and well.Parent
			if left and left:IsA("GuiObject") then
				local was = left.Size
				left.Size = UDim2.new(0, 150, 1, 0)
				KC.advance(0.2)
				H.checkEmpty(label .. " Pets squeezed to a 150 px column", well:FindFirstChild("Empty"), false)
				left.Size = was
				KC.advance(0.2)
			end
			H.closeAll()
			Mock.Click(H.tile("Team"))
			KC.advance(1)
			local team = H.parts().Menu:FindFirstChild("Window_Team")
			local empty = nil
			for _, d in ipairs(team and team:GetDescendants() or {}) do
				if d.Name == "Empty" and d:FindFirstChild("GoShop") then
					empty = d
				end
			end
			H.checkEmpty(label .. " Team", empty, false)
			H.closeAll()
		end
	end)
	State.Keys, State.IsLoaded = oldKeys, oldLoaded
	if not ok then
		T.fail("bug2gui " .. world .. " empty states: " .. tostring(err))
	end
	Mock.SetViewport(old[1], old[2])
	KC.advance(1)
end

S.client_bug2gui_empty = guarded("client_bug2gui_empty", function()
	H.emptyRun("empty", { { 1920, 1080 }, { 1280, 720 }, { 749, 388 } })
	KC.flushErrors("client_bug2gui_empty")
end)

S.client_bug2gui_empty_mobile = guarded("client_bug2gui_empty_mobile", function()
	H.emptyRun("phone empty", { { 749, 388 }, { 844, 390 }, { 800, 360 }, { 667, 375 }, { 740, 360 }, { 390, 844 } })
	KC.flushErrors("client_bug2gui_empty_mobile")
end)

return S
