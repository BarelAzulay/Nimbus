-- smoke_hud_pill.lua: HUD cleanup, Task 1 (the owner's picks on the HUD cleanup pitch: slot 1 "B" the top-left pill,
-- slot 3 "A" Quick Travel). Loaded by tools/smoke.py in the server world and the client worlds:
--   hudpill_travel     (server, booted) the pill's Travel behind GateService.Travel(player, dest): "Plaza" is the one
--                      destination; it opens the home portal and moves nobody (the whole portal: hudtools_portal in
--                      smoke_hud_tools.lua); the Court is gone; the spawn sits outside the Arena / Altar islands' boxes;
--                      the QuickTravel remote: garbage never errors, a press opens the portal
--   client_hudpill     (client, 1920x1080) the NimbusTopBar ScreenGui (IgnoreGuiInset, order 21) and its Pill in Roblox's
--                      top-bar band right of Roblox's buttons (GuiService.TopbarInset.Min.X + 8, fallback 212) and left
--                      of its right-side buttons; PillButton_Shop / Travel / Settings; PillRight / PillBottom; Shop opens
--                      the Cloud Shop and is refused in a match with the hint; Settings opens MainMenuController's
--                      panel; a tap on Travel fires QuickTravel("Plaza") once with no drop-down and no fade; Travel
--                      hides in a battle and a match, and shows on the Arena island and at home; the menu column keeps
--                      Pets, Index, Home, Stats (no gear, Team or Items tile)
--   client_hudpill_mobile (phone world, 844x390 / 740x360 / 667x375 in a battle) the HUD's TopBand currency row
--                      starts right of the pill (not at BAND_LEFT 150), they do not overlap, the pill ends left of
--                      Roblox's right-side buttons and stays tappable (>= 32 px)
-- Deterministic: mock clock only. The viewport, the attributes and the players are restored at the end.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format

-- an island's bounding box (+ 40 studs Y slack)
local function insideBox(model, pos)
	if not (model and model:IsA("Model")) then
		return false
	end
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or typeof(cf) ~= "CFrame" then
		return false
	end
	local rel = cf:PointToObjectSpace(pos)
	local half = size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and math.abs(rel.Y) <= half.Y + 40
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	S.hudpill_travel = guarded("hudpill_travel", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local GS = K.mod("GateService")
		local PlayerService = K.mod("PlayerService")
		if not T.check(type(GS) == "table" and type(GS.Travel) == "function", "hudpill: GateService.Travel exists") then
			return
		end
		T.eq(GS.CourtCFrame, nil, "hudpill: the Gate Court destination is gone")
		local info = K.W.lobbyInfo
		local players = K.freshPlayers(2, "Trav")
		local a, b = players[1], players[2]
		K.advance(3.5)

		local where = K.root(a).Position
		T.eq(select(1, GS.Travel(a, "Plaza")), true, "hudpill: Travel(Plaza) works")
		T.check(type(a:GetAttribute(Config.Attr.HomePortal)) == "string", "hudpill: ...it opens the home portal (the HomePortal attribute)")
		T.check(K.planar(K.root(a).Position, where) < 1, "hudpill: ...and moves nobody until they walk in")
		T.eq(select(2, GS.Travel(a, "Court")), "junk", "hudpill: the Court is no destination any more")
		T.eq(select(2, GS.Travel(a, "Home")), "junk", "hudpill: unknown destinations are junk")
		T.eq(select(2, GS.Travel(a, 5)), "junk", "hudpill: non-string destinations are junk")
		T.eq(select(2, GS.Travel(nil, "Plaza")), "junk", "hudpill: a nil player is junk")

		-- the landing is outside the island boxes
		local spawn = PlayerService.GetLobbySpawnCFrame()
		local arena = workspace:FindFirstChild("BattleArena")
		local altar = info.Folder and info.Folder:FindFirstChild("StormAltar")
		T.check(not insideBox(arena, spawn.Position) and not insideBox(altar, spawn.Position), "hudpill: the spawn is outside the Arena / Altar island boxes",
			tostring(arena ~= nil) .. " / " .. tostring(altar ~= nil))

		-- the remote: garbage never errors, a press opens the portal
		local remote = K.remoteFolder() and K.remoteFolder():FindFirstChild("QuickTravel")
		if T.check(remote ~= nil, "hudpill: the QuickTravel remote exists") then
			local errs = #Mock.Errors
			Mock.FromClient(remote, b, nil)
			for _, junk in ipairs({ 1, {}, "Court", "Court\0", string.rep("x", 100), true }) do
				Mock.FromClient(remote, b, junk)
			end
			K.advance(0.1)
			T.eq(#Mock.Errors, errs, "hudpill: QuickTravel with garbage raises no errors")
			T.eq(b:GetAttribute(Config.Attr.HomePortal), nil, "hudpill: ...and opens nothing")
			Mock.FromClient(remote, b, "Plaza")
			K.advance(0.1)
			T.check(type(b:GetAttribute(Config.Attr.HomePortal)) == "string", "hudpill: QuickTravel('Plaza') opens the portal")
		end
		K.removePlayers(players)
		K.flushErrors("hudpill_travel")
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
	local GuiService = game:GetService("GuiService")
	local LocalPlayer = Players.LocalPlayer
	local H = {}

	function H.mod(name)
		if KC.M and KC.M[name] then
			return KC.M[name]
		end
		local inst = Mock.GetPath(ROOTS["client"] .. "/Controllers/" .. name)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.menu()
		return H.pg():FindFirstChild("NimbusMenu")
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
	-- screen rect (the top bar included) of a GuiObject
	function H.rect(obj)
		local gui = obj:FindFirstAncestorOfClass("ScreenGui")
		local dy = (gui and not gui.IgnoreGuiInset) and (Mock.TopInset or 0) or 0
		local p, s = obj.AbsolutePosition, obj.AbsoluteSize
		return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + dy + s.Y }
	end
	function H.overlap(a, b)
		return a.x0 < b.x1 - 0.5 and b.x0 < a.x1 - 0.5 and a.y0 < b.y1 - 0.5 and b.y0 < a.y1 - 0.5
	end
	function H.fmt(r)
		return r and fmt("%.0f,%.0f - %.0f,%.0f", r.x0, r.y0, r.x1, r.y1) or "none"
	end
	function H.hintText()
		local hint = H.menu() and H.menu():FindFirstChild("MenuHint")
		local label = hint and hint:FindFirstChild("Text")
		return (hint and hint.Visible and label) and tostring(label.Text) or ""
	end
	function H.calls(name, mark)
		return KC.serverCalls(name, mark)
	end
	function H.parts()
		local gui = H.pg():FindFirstChild("NimbusTopBar")
		local pill = gui and gui:FindFirstChild("Pill")
		return gui, pill
	end
	function H.button(pill, name)
		return pill and pill:FindFirstChild("PillButton_" .. name, true)
	end

	S.client_hudpill = guarded("client_hudpill", function()
		local TB = H.mod("TopBarController")
		local MC = H.mod("MenuController")
		local MMC = H.mod("MainMenuController")
		local Config = KC.env()
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		KC.advance(0.6)
		if not T.check(type(TB) == "table" and type(TB.GetRect) == "function" and type(TB.TravelAllowed) == "function" and type(TB.Refresh) == "function",
			"hudpill: TopBarController loads (Init, GetRect, TravelAllowed, Refresh)") then
			return
		end
		local gui, pill = H.parts()
		if not T.check(gui ~= nil and gui:IsA("ScreenGui") and gui.IgnoreGuiInset == true and gui.DisplayOrder == 21 and pill ~= nil,
			"hudpill: NimbusTopBar ScreenGui (IgnoreGuiInset, order 21) with its Pill") then
			return
		end
		local inset = GuiService:GetGuiInset().Y
		local r = H.rect(pill)
		T.check(r.x0 >= 212 - 1, "hudpill: the pill starts right of Roblox's top-bar buttons (TopbarInset.Min.X + 8, fallback 212)", H.fmt(r))
		T.check(r.y0 >= 0 and r.y1 <= inset, "hudpill: ...inside the top-bar band", H.fmt(r) .. " inset " .. inset)
		for _, n in ipairs({ "Shop", "Travel", "Settings" }) do
			local btn = H.button(pill, n)
			T.check(btn ~= nil and btn:IsA("TextButton") and H.shown(btn), "hudpill: button PillButton_" .. n .. " shows")
		end
		T.check(math.abs((tonumber(gui:GetAttribute("PillRight")) or -1) - r.x1) < 0.5 and math.abs((tonumber(gui:GetAttribute("PillBottom")) or -1) - r.y1) < 0.5,
			"hudpill: attributes PillRight / PillBottom = the pill's right / bottom edge", tostring(gui:GetAttribute("PillRight")) .. " / " .. H.fmt(r))
		T.check(r.x1 < 1920 - 72, "hudpill: the pill ends left of Roblox's right-side buttons", H.fmt(r))
		local gr = TB.GetRect()
		T.check(type(gr) == "table" and math.abs(gr.X0 - r.x0) < 0.5 and math.abs(gr.X1 - r.x1) < 0.5 and math.abs(gr.Y1 - r.y1) < 0.5,
			"hudpill: GetRect() = the pill's screen rect")
		-- the real inset (GuiService.TopbarInset) wins over the fallback
		Mock.TopbarInset = Rect.new(240, 0, 1700, 58)
		TB.Refresh()
		KC.advance(0.1)
		local r2 = H.rect(pill)
		T.check(math.abs(r2.x0 - 248) < 0.5 and r2.x1 <= 1700, "hudpill: with GuiService.TopbarInset the pill starts at Min.X + 8 and ends left of Max.X", H.fmt(r2))
		Mock.TopbarInset = Rect.new(240, 0, 520, 58)
		TB.Refresh()
		KC.advance(0.1)
		local r3 = H.rect(pill)
		T.check(r3.x1 <= 520 and r3.x0 >= 248 - 0.5 and H.button(pill, "Settings").AbsoluteSize.X >= 30, "hudpill: a narrow free band drops the labels (icons only) and still fits", H.fmt(r3))
		Mock.TopbarInset = nil
		TB.Refresh()
		KC.advance(0.1)

		-- Shop
		MC.Close()
		KC.advance(0.3)
		Mock.Click(H.button(pill, "Shop"))
		KC.advance(0.5)
		T.check(H.shown(H.menu():FindFirstChild("Window_Shop")), "hudpill: Shop opens the Cloud Shop window")
		LocalPlayer:SetAttribute(Config.Attr.InMatch, true)
		KC.advance(0.1)
		Mock.Click(H.button(pill, "Shop"))
		KC.advance(0.3)
		T.check(not H.shown(H.menu():FindFirstChild("Window_Shop")) and H.hintText():find("closed during a match", 1, true) ~= nil,
			"hudpill: Shop is refused in a match with the hint", H.hintText())
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		KC.advance(0.6)

		-- Settings
		Mock.Click(H.button(pill, "Settings"))
		KC.advance(0.5)
		local holder = MMC and MMC.Window and MMC.Window()
		T.check(holder ~= nil and holder.Parent ~= nil, "hudpill: Settings opens MainMenuController's settings panel")
		if MMC and MMC.CloseWindows then
			MMC.CloseWindows()
		end
		KC.advance(0.5)

		-- Travel: one tap, one press of the server's portal; no menu, no fade
		local travel = H.button(pill, "Travel")
		T.check(travel and travel.Visible and TB.TravelAllowed() == true, "hudpill: Travel shows in the lobby")
		local mark = #Mock.RemoteLog
		Mock.Click(travel)
		KC.advance(0.1)
		local calls = H.calls("QuickTravel", mark)
		T.check(#calls == 1 and calls[1].args[1] == "Plaza", "hudpill: a tap on Travel fires QuickTravel('Plaza')", tostring(#calls))
		T.check(gui:FindFirstChild("TravelMenu", true) == nil and gui:FindFirstChild("TravelPortals", true) == nil and gui:FindFirstChild("TravelLobby", true) == nil,
			"hudpill: there is no Travel drop-down")
		T.eq(gui:FindFirstChild("TravelFade", true), nil, "hudpill: ...and no black fade")
		Mock.Click(travel)
		KC.advance(0.1)
		T.eq(#H.calls("QuickTravel", mark), 1, "hudpill: a double tap sends one press")
		KC.advance(1)
		Mock.Click(travel)
		KC.advance(0.1)
		T.eq(#H.calls("QuickTravel", mark), 2, "hudpill: a later tap sends another (the server's cooldown decides)")

		LocalPlayer:SetAttribute(Config.Attr.InBattle, "B1")
		KC.advance(0.1)
		T.check(not travel.Visible and TB.TravelAllowed() == false, "hudpill: Travel hides in a battle (InBattle)")
		mark = #Mock.RemoteLog
		Mock.Click(travel)
		KC.advance(0.1)
		T.eq(#H.calls("QuickTravel", mark), 0, "hudpill: ...and sends nothing")
		T.check(H.button(pill, "Shop").Visible and H.button(pill, "Settings").Visible, "hudpill: ...Shop and Settings stay")
		T.check(math.abs((tonumber(gui:GetAttribute("PillRight")) or -1) - H.rect(pill).x1) < 0.5 and H.rect(pill).x1 < r.x1,
			"hudpill: ...the pill narrows and PillRight follows it")
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, true)
		KC.advance(0.1)
		T.check(not travel.Visible, "hudpill: ...and in a match")
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		KC.advance(0.1)
		T.check(travel.Visible, "hudpill: back outside a match it shows again")
		-- getting back to the lobby is the point: it shows on the islands and at home
		local hrp = KC.root()
		if workspace:FindFirstChild("BattleArena") == nil and hrp then
			local fake = Instance.new("Model")
			fake.Name = "BattleArena"
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.Size = Vector3.new(200, 60, 200)
			p.CFrame = hrp.CFrame
			p.Parent = fake
			fake.Parent = workspace
			KC.advance(0.6)
			T.check(travel.Visible and TB.TravelAllowed() == true, "hudpill: ...it shows on the Arena island too (inside workspace.BattleArena's box)")
			fake:Destroy()
			KC.advance(0.1)
		else
			T.info("*hudpill: arena island check skipped (a BattleArena already exists or no character)")
		end

		-- the column
		local column = H.menu() and H.menu():FindFirstChild("MenuColumn")
		local ids = {}
		for _, e in ipairs(column and column:GetChildren() or {}) do
			if e.Name:find("^Entry_") then
				ids[#ids + 1] = e.Name
			end
		end
		table.sort(ids)
		T.check(#ids == 4 and ids[1] == "Entry_Index" and ids[2] == "Entry_Pets" and ids[3] == "Entry_Spot" and ids[4] == "Entry_Stats",
			"hudpill: the column keeps Pets, Index, Home, Stats only", table.concat(ids, ","))
		T.check(column and column:FindFirstChild("Gear_Settings") == nil and column:FindFirstChild("Entry_Team") == nil and column:FindFirstChild("Entry_Inventory") == nil
			and column:FindFirstChild("Entry_Shop") == nil, "hudpill: no gear, Team, Items or Shop tile")
		-- MenuController.OpenSettings is public; Open("Settings") goes there too
		T.check(type(MC.OpenSettings) == "function", "hudpill: MenuController.OpenSettings is public")
		MC.Open("Settings", {})
		KC.advance(0.4)
		holder = MMC and MMC.Window and MMC.Window()
		T.check(holder ~= nil and holder.Parent ~= nil, "hudpill: MenuController.Open('Settings') opens the settings panel")
		if MMC and MMC.CloseWindows then
			MMC.CloseWindows()
		end
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.5)
		KC.flushErrors("client_hudpill")
	end)

	S.client_hudpill_mobile = guarded("client_hudpill_mobile", function()
		local TB = H.mod("TopBarController")
		local HC = H.mod("HudController")
		local Config = KC.env()
		if not T.check(type(TB) == "table" and type(HC) == "table" and type(HC.GetLayout) == "function", "hudpill phone: TopBarController + HudController load") then
			return
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		local oldCash, oldGems = LocalPlayer:GetAttribute(Config.Attr.Cash), LocalPlayer:GetAttribute(Config.Attr.Gems)
		for _, case in ipairs({ { 844, 390, 1 }, { 844, 390, 3 }, { 740, 360, 3 }, { 667, 375, 3 } }) do -- (667x375: three strips still fit right of the pill, BAND_MIN_W)
			local w, h, n = case[1], case[2], case[3]
			local label = fmt("hudpill phone %dx%d, %d strip%s", w, h, n, n == 1 and "" or "s")
			LocalPlayer:SetAttribute(Config.Attr.Cash, n > 1 and 1200 or nil)
			LocalPlayer:SetAttribute(Config.Attr.Gems, n > 1 and 45 or nil)
			Mock.SetViewport(w, h)
			KC.advance(1.2)
			LocalPlayer:SetAttribute(Config.Attr.InBattle, "B930")
			KC.advance(0.6)
			local gui, pill = H.parts()
			local hud = H.pg():FindFirstChild("NimbusHud")
			local band = hud and hud:FindFirstChild("TopRight") and hud.TopRight:FindFirstChild("Currency")
			if T.check(gui and pill and band, label .. ": the pill and the HUD's currency row exist") then
				local pr, br = H.rect(pill), H.rect(band)
				T.check(HC.GetLayout().CurrencyMode == "TopBand", label .. ": in a battle the strips are in the top band", tostring(HC.GetLayout().CurrencyMode))
				T.check(br.x0 >= pr.x1 + 6 - 0.5, label .. ": the currency row starts right of the pill (not at BAND_LEFT 150)", H.fmt(pr) .. " vs " .. H.fmt(br))
				T.check(not H.overlap(pr, br), label .. ": the pill and the currency row do not overlap")
				T.check(pr.x1 <= w - 72 and br.x1 <= w - 60, label .. ": the pill and the row end left of Roblox's right-side buttons", H.fmt(pr) .. " / " .. H.fmt(br))
				T.check(pill.AbsoluteSize.Y >= 32 and pr.y1 <= GuiService:GetGuiInset().Y, label .. ": the pill stays tappable (>= 32 px) inside the band", H.fmt(pr))
			end
			LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
			KC.advance(0.6)
		end
		LocalPlayer:SetAttribute(Config.Attr.Cash, oldCash)
		LocalPlayer:SetAttribute(Config.Attr.Gems, oldGems)
		Mock.SetViewport(old[1], old[2])
		KC.advance(1)
		KC.flushErrors("client_hudpill_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
