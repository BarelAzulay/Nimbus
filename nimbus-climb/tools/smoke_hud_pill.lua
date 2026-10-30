-- smoke_hud_pill.lua: HUD cleanup, Task 1 (the owner's picks on the HUD cleanup pitch: slot 1 "B" the top-left pill,
-- slot 3 "A" Quick Travel). Loaded by tools/smoke.py in the server world and the client worlds:
--   hudpill_travel     (server, booted) GateService.Travel(player, dest) and GateService.CourtCFrame(): the Gate Court
--                      landing is 16 studs in front of the Ring gate, 3 up, facing the gates, on no portal pad; Court /
--                      Plaza teleports from the plaza, one per 2 s (cooldown), junk destinations, refusals in a match, a
--                      battle / dungeon run (InBattle), while locked on a portal pad in its party countdown (the
--                      countdown is untouched), outside the lobby world (the Y band) and inside a battle zone
--                      (ArenaBuilder.ZoneAt: a zone on the plaza and the arena floor); both landings sit outside the
--                      Arena and Altar islands' boxes (the client shows Travel there); the QuickTravel remote: garbage
--                      never errors, once per 2 s, Teleported fires (player, "Court")
--   client_hudpill     (client, 1920x1080) the NimbusTopBar ScreenGui (IgnoreGuiInset, order 21) and its Pill in Roblox's
--                      top-bar band right of Roblox's buttons (GuiService.TopbarInset.Min.X + 8, fallback 212) and left
--                      of its right-side buttons; PillButton_Shop / Travel / Settings; PillRight / PillBottom; Shop opens
--                      the Cloud Shop and is refused in a match with the hint; Settings opens MainMenuController's
--                      panel; Travel's drop-down (TravelPortals / TravelLobby) under the button fires QuickTravel
--                      ("Court" / "Plaza") with a short fade; Travel hides in a battle, a match and on the Arena island;
--                      the menu column keeps Pets, Index, Home, Stats (no gear, Team or Items tile)
--   client_hudpill_mobile (phone world, 844x390 in a battle) the HUD's TopBand currency row starts right of the pill (not
--                      at BAND_LEFT 150), they do not overlap, the pill ends left of Roblox's right-side buttons and
--                      stays tappable (>= 32 px)
-- Deterministic: mock clock only. The viewport, the attributes and the players are restored at the end.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format

-- the island boxes the client hides Travel in (TopBarController.TravelAllowed: GetBoundingBox + 40 studs Y slack)
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
		local PortalService = K.mod("PortalService")
		local AB = K.mod("ArenaBuilder")
		if not T.check(type(GS) == "table" and type(GS.Travel) == "function" and type(GS.CourtCFrame) == "function",
			"hudpill: GateService.Travel / CourtCFrame exist") then
			return
		end
		local info = K.W.lobbyInfo
		local site = info.GateSites and info.GateSites.Ring
		local court = GS.CourtCFrame()
		if not T.check(typeof(site) == "CFrame" and typeof(court) == "CFrame", "hudpill: CourtCFrame() is a CFrame (the Ring gate site exists)") then
			return
		end
		local want = site.Position + site.LookVector * 16 + Vector3.new(0, 3, 0)
		T.check((court.Position - want).Magnitude < 0.5, "hudpill: CourtCFrame = 16 studs in front of the Ring gate, 3 up",
			fmt("%.2f studs off", (court.Position - want).Magnitude))
		T.check(court.LookVector:Dot((site.Position + Vector3.new(0, 3, 0) - court.Position).Unit) > 0.9, "hudpill: ...facing the gates")

		local players = K.freshPlayers(2, "Trav")
		local a, b = players[1], players[2]
		local function root(p)
			return K.root(p)
		end
		K.advance(0.5)

		T.eq(select(1, GS.Travel(a, "Court")), true, "hudpill: Travel(Court) from the plaza works")
		T.check(root(a) and (root(a).Position - court.Position).Magnitude < 2, "hudpill: ...the character stands at the court",
			root(a) and fmt("%.2f", (root(a).Position - court.Position).Magnitude) or "no root")
		T.eq(select(2, GS.Travel(a, "Plaza")), "cooldown", "hudpill: a second travel inside 2 s is refused (cooldown)")
		K.advance(1)
		T.check(not PortalService.IsLocked(a) and root(a) and (root(a).Position - court.Position).Magnitude < 2,
			"hudpill: the court landing is on no portal pad (nothing locks or moves the player there)")
		K.advance(1.1)
		T.eq(select(1, GS.Travel(a, "Plaza")), true, "hudpill: Travel(Plaza) works after the cooldown")
		local spawn = PlayerService.GetLobbySpawnCFrame()
		T.check(root(a) and (root(a).Position - spawn.Position).Magnitude < 2, "hudpill: ...at the lobby spawn",
			root(a) and fmt("%.2f", (root(a).Position - spawn.Position).Magnitude) or "no root")
		T.eq(select(2, GS.Travel(a, "Home")), "junk", "hudpill: unknown destinations are junk")
		T.eq(select(2, GS.Travel(a, 5)), "junk", "hudpill: non-string destinations are junk")
		T.eq(select(2, GS.Travel(nil, "Court")), "junk", "hudpill: a nil player is junk")

		-- both landings are outside the island boxes (the client's Travel button shows there)
		local arena = workspace:FindFirstChild("BattleArena")
		local altar = info.Folder and info.Folder:FindFirstChild("StormAltar")
		T.check(not insideBox(arena, court.Position) and not insideBox(arena, spawn.Position) and not insideBox(altar, court.Position)
			and not insideBox(altar, spawn.Position), "hudpill: the court and the spawn are outside the Arena / Altar island boxes",
			tostring(arena ~= nil) .. " / " .. tostring(altar ~= nil))

		a:SetAttribute(Config.Attr.InMatch, true)
		K.advance(2.1)
		T.eq(select(2, GS.Travel(a, "Court")), "match", "hudpill: refused in an obby match")
		a:SetAttribute(Config.Attr.InMatch, false)
		a:SetAttribute(Config.Attr.InBattle, "D7")
		T.eq(select(2, GS.Travel(a, "Court")), "battle", "hudpill: refused in a battle / dungeon run (InBattle)")
		a:SetAttribute(Config.Attr.InBattle, nil)

		-- locked on the Obby pad in its party countdown
		K.enterPortal(a)
		K.advance(0.6)
		if T.check(PortalService.IsLocked(a), "hudpill: (setup) standing on the Obby pad locks the player in its countdown") then
			local party = PortalService.GetParty("Obby")
			local countdown = party and party.Countdown
			T.eq(select(2, GS.Travel(a, "Court")), "locked", "hudpill: refused while locked on a portal pad (party countdown)")
			party = PortalService.GetParty("Obby")
			T.check(PortalService.IsLocked(a) and party and #party.Players == 1 and party.Countdown == countdown,
				"hudpill: ...and the countdown is untouched")
		end
		PortalService.CancelParty("Obby")
		K.leavePortalArea(a)
		K.advance(1)

		-- outside the lobby world / inside a battle zone (no accepted travel since the Plaza one: no cooldown in the way)
		K.advance(2.1)
		Mock.Teleport(a, CFrame.new(Config.Lobby.Origin + Vector3.new(0, -120, 0)))
		T.eq(select(2, GS.Travel(a, "Court")), "zone", "hudpill: refused outside the lobby world (below the Y band)")
		Mock.Teleport(a, CFrame.new(Config.Lobby.Origin + Vector3.new(Config.Lobby.SpotRingRadius + 200, 0, 0)))
		T.eq(select(2, GS.Travel(a, "Court")), "zone", "hudpill: refused outside the lobby world (beyond the home ring)")
		local zone = Instance.new("Part")
		zone.Name = "HudPillFakeZone"
		zone.Anchored = true
		zone.CanCollide = false
		zone.Transparency = 1
		zone.Size = Vector3.new(16, 16, 16)
		zone.CFrame = spawn * CFrame.new(0, 0, -20)
		zone.Parent = workspace
		game:GetService("CollectionService"):AddTag(zone, "NC_BattleZone")
		Mock.Teleport(a, zone.CFrame)
		T.check(AB == nil or AB.ZoneAt(zone.Position) == zone, "hudpill: (setup) ArenaBuilder.ZoneAt finds the zone")
		T.eq(select(2, GS.Travel(a, "Court")), "zone", "hudpill: refused inside a battle zone on the plaza (ArenaBuilder.ZoneAt)")
		zone:Destroy()
		local ainfo = AB and AB.GetInfo and AB.GetInfo()
		if ainfo and ainfo.Floor and typeof(ainfo.Floor.CFrame) == "CFrame" then
			Mock.Teleport(a, ainfo.Floor.CFrame * CFrame.new(0, 3, 0))
			T.eq(select(2, GS.Travel(a, "Court")), "zone", "hudpill: refused on the arena's raid floor")
		end
		K.leavePortalArea(a)
		K.advance(0.5)

		-- the remote: garbage never errors, one travel per 2 s, Teleported fires (player, dest)
		local remote = K.remoteFolder() and K.remoteFolder():FindFirstChild("QuickTravel")
		if T.check(remote ~= nil, "hudpill: the QuickTravel remote exists") then
			local errs = #Mock.Errors
			Mock.FromClient(remote, b, nil)
			for _, junk in ipairs({ 1, {}, "Court\0", string.rep("x", 100), true }) do
				Mock.FromClient(remote, b, junk)
			end
			K.advance(0.1)
			T.eq(#Mock.Errors, errs, "hudpill: QuickTravel with garbage raises no errors")
			local fired = {}
			local conn = GS.Teleported:Connect(function(p, id)
				if p == b then
					fired[#fired + 1] = id
				end
			end)
			Mock.FromClient(remote, b, "Court")
			Mock.FromClient(remote, b, "Plaza")
			K.advance(0.1)
			T.check(#fired == 1 and fired[1] == "Court", "hudpill: the remote travels once per 2 s and Teleported fires (player, 'Court')", table.concat(fired, ","))
			T.check(root(b) and (root(b).Position - court.Position).Magnitude < 2, "hudpill: ...the remote's traveller stands at the court")
			conn:Disconnect()
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

		-- Travel
		local travel = H.button(pill, "Travel")
		T.check(travel and travel.Visible and TB.TravelAllowed() == true, "hudpill: Travel shows in the lobby")
		Mock.Click(travel)
		KC.advance(0.2)
		local tm = gui:FindFirstChild("TravelMenu", true)
		local portals = tm and tm:FindFirstChild("TravelPortals", true)
		local lobby = tm and tm:FindFirstChild("TravelLobby", true)
		if T.check(tm and tm.Visible and portals and lobby, "hudpill: Travel opens a drop-down with Portals and Lobby") then
			local mr = H.rect(tm)
			T.check(mr.y0 >= inset - 1 and mr.x0 >= r.x0 - 1 and mr.x1 <= 1920, "hudpill: ...under the button, never over Roblox's buttons", H.fmt(mr))
			local mark = #Mock.RemoteLog
			Mock.Click(portals)
			KC.advance(0.1)
			local calls = H.calls("QuickTravel", mark)
			T.check(#calls == 1 and calls[1].args[1] == "Court", "hudpill: Portals fires QuickTravel('Court')", tostring(#calls))
			local fade = gui:FindFirstChild("TravelFade")
			T.check(fade and fade.Visible and fade.BackgroundTransparency < 0.5 and not tm.Visible, "hudpill: ...the menu closes and a short fade shows",
				fade and tostring(fade.BackgroundTransparency) or "no fade")
			KC.advance(1.0)
			T.check(fade and not fade.Visible, "hudpill: ...gone within a second")
			mark = #Mock.RemoteLog
			Mock.Click(travel)
			KC.advance(0.1)
			Mock.Click(lobby)
			KC.advance(0.1)
			calls = H.calls("QuickTravel", mark)
			T.check(#calls == 1 and calls[1].args[1] == "Plaza", "hudpill: Lobby fires QuickTravel('Plaza')", tostring(#calls))
			KC.advance(1.0)
			-- a second click on Travel closes the open drop-down
			Mock.Click(travel)
			KC.advance(0.1)
			Mock.Click(travel)
			KC.advance(0.1)
			T.check(not tm.Visible, "hudpill: a second tap on Travel closes the drop-down")
			Mock.Click(travel)
			KC.advance(0.1)
		end

		LocalPlayer:SetAttribute(Config.Attr.InBattle, "B1")
		KC.advance(0.6)
		T.check(not travel.Visible and not (tm and tm.Visible) and TB.TravelAllowed() == false, "hudpill: Travel hides in a battle (InBattle), its drop-down closes")
		T.check(H.button(pill, "Shop").Visible and H.button(pill, "Settings").Visible, "hudpill: ...Shop and Settings stay")
		T.check(math.abs((tonumber(gui:GetAttribute("PillRight")) or -1) - H.rect(pill).x1) < 0.5 and H.rect(pill).x1 < r.x1,
			"hudpill: ...the pill narrows and PillRight follows it")
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, true)
		KC.advance(0.6)
		T.check(not travel.Visible, "hudpill: ...and in a match")
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		KC.advance(0.6)
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
			T.check(not travel.Visible, "hudpill: ...and on the Arena island (inside workspace.BattleArena's box)")
			fake:Destroy()
			KC.advance(0.6)
		else
			T.info("*hudpill: arena island check skipped (a BattleArena already exists or no character)")
		end
		T.check(travel.Visible, "hudpill: ...back in the lobby it shows again")

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
		for _, case in ipairs({ { 844, 390, 1 }, { 844, 390, 3 }, { 740, 360, 3 } }) do
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
