-- smoke_lb_ui.lua: lobby-shop Task 24 (spec 5.10 "Client", pages per section 15: Trophies / Pets found / Ring best): the lobby
-- board's SurfaceGui (client/Controllers/LeaderboardController). Loaded by tools/smoke.py in the CLIENT world:
--   client_leaderboard   (client, 1920x1080)
--     starts from a cold controller (G.cold through LeaderboardController._S: earlier client scenarios leave it warm)
--     an untagged stand-in board -> nothing (review round 1: the board is found by its Face's Config.Tags.LeaderboardFace)
--     a stand-in board (Model LobbyLeaderboard > Part Face 16 x 13 x 0.4, tagged; the client world has no lobby) -> a SurfaceGui
--       LobbyLeaderboard in PlayerGui adorned to that Face: Face Front, PixelsPerStud 50 (800 x 650 px), MaxDistance 80,
--       ResetOnSpawn false, LightInfluence 0 > Board > Title, Tabs > Tab_<stat> per Config.Leaderboard.Pages (their Labels),
--       Scope, Rows > Row1..10 (Rank, Head 34 px ImageLabel, Name, Value), YouRow, Footer, Status
--     before any LeaderboardState: Status "Loading scores...", no row shown
--     a state with ten rows and You = { Rank 37, Value 1240 }: Row1..10 filled (ranks, names, values with commas,
--       Theme.ShortNumber from 1e6), ranks 1-3 gold / silver / bronze, the headshots fetched once per user
--       (Players:GetUserThumbnailAsync HeadShot 48x48, cached), YouRow "You . 1,240 . #37"; Rank nil -> "not in the top
--       100"; Value nil -> "You . ..."; Scope "Server" -> "This server only"; NextAt = now + 220 -> the footer starts
--       "Refreshes in 3:40"; an empty page -> "No scores yet. Be the first!"
--     tabs: SetPage("Pets") -> "TOP PETS FOUND"; a tap on a tab switches; the page turns by itself after 15 s and a tap
--       at 10 s moves the turn to 25 s
--     every text >= 30 px (0.6 stud at 50 px per stud, no TextScaled) and every shown object inside the 800 x 650 canvas
--     long names (Review Focus 6): a 20-character name and a value of 1e12 -> the name fits its box (or truncates), the
--       value reads "1T", no size changes
--     a headshot call that fails (Mock.ThumbnailFail) -> the head stays blank, no error, not asked again
--     lobby rebuilt (Review Focus 4): the board destroyed and built again -> Adornee is the new Face within 1 s, the same
--       SurfaceGui, the rows still show the last state; a new board built before the old one goes -> the new Face wins
-- Deterministic: mock clock only. The stand-in boards are destroyed at the end. Plain Lua 5.1 syntax.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format
local abs = math.abs

local S = {}

local DOT = "\194\183"
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local LocalPlayer = Players.LocalPlayer

local G = {}
function G.req(key)
	local inst = Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", ""))
	if not inst then
		return nil
	end
	local ok, mod = pcall(require, inst)
	return ok and type(mod) == "table" and mod or nil
end
function G.rgb(c, r, g, b)
	return c ~= nil and abs(c.R * 255 - r) < 1.5 and abs(c.G * 255 - g) < 1.5 and abs(c.B * 255 - b) < 1.5
end
-- a stand-in for LobbyBoardBuilder's board: the model and its 16 x 13 x 0.4 Face (front -Z), at x; the Face tagged
-- Config.Tags.LeaderboardFace like the builder's (review round 1: the controller finds it by that tag), unless `untagged`
function G.board(x, untagged)
	local model = Instance.new("Model")
	model.Name = "LobbyLeaderboard"
	local face = Instance.new("Part")
	face.Name = "Face"
	face.Size = Vector3.new(16, 13, 0.4)
	face.Anchored = true
	face.CanCollide = false
	face.CFrame = CFrame.new(x or 20, 9.5, -43.5)
	if not untagged then
		local Config = _G.KC.env()
		game:GetService("CollectionService"):AddTag(face, (Config.Tags and Config.Tags.LeaderboardFace) or "NC_LeaderboardFace")
	end
	face.Parent = model
	model.Parent = workspace
	return model, face
end
-- a cold controller, as in a fresh session. In the whole suite earlier client scenarios leave it warm: client_replay
-- replays the server run's LeaderboardState broadcasts (State set, an empty page), and client_pets' Storm Altar showcase
-- (smoke_client_v2.lua) builds a whole lobby, board included, whose SurfaceGui stays in the PlayerGui after that lobby is
-- destroyed (by design: a rebuilt board re-adorns the same gui). Through the controller's _S test hook: the gui destroyed,
-- the face, state, page and headshot cache dropped. Returns the tagged Faces still in the workspace (there should be none)
function G.cold(LC)
	local st = LC._S
	if type(st) ~= "table" then
		return nil
	end
	for _, g in ipairs(G.guis()) do
		g:Destroy()
	end
	if st.Gui then
		pcall(function()
			st.Gui:Destroy()
		end)
	end
	st.Gui, st.Face, st.Ui, st.State, st.Page, st.Icon = nil, nil, nil, nil, nil, nil
	st.Heads, st.HeadCount, st.TurnAt = {}, 0, 0
	local Config = _G.KC.env()
	local left = 0
	for _, f in ipairs(game:GetService("CollectionService"):GetTagged((Config.Tags and Config.Tags.LeaderboardFace) or "NC_LeaderboardFace")) do
		if f:IsDescendantOf(workspace) then
			left = left + 1
		end
	end
	return left
end
-- every SurfaceGui named LobbyLeaderboard in the PlayerGui
function G.guis()
	local out = {}
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	for _, c in ipairs(pg and pg:GetChildren() or {}) do
		if c.Name == "LobbyLeaderboard" and c:IsA("SurfaceGui") then
			out[#out + 1] = c
		end
	end
	return out
end
function G.find(root, name)
	if not root then
		return nil
	end
	if root.Name == name then
		return root
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
	return nil
end
-- shown inside `gui` (it and every GuiObject up to the gui are Visible)
function G.shown(obj, gui)
	local cur = obj
	while cur and cur ~= gui do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	return cur == gui and gui.Enabled ~= false
end
function G.text(gui, name)
	local o = G.find(gui, name)
	return o and o.Text or nil
end
function G.row(gui, i)
	local rows = G.find(gui, "Rows")
	return rows and rows:FindFirstChild("Row" .. i) or nil
end
-- a row's Name label (row.Name is the Instance's own name, so the child is looked up)
function G.nm(row)
	return row and row:FindFirstChild("Name") or nil
end
function G.shownRows(gui)
	local n = 0
	for i = 1, 10 do
		local r = G.row(gui, i)
		if r and G.shown(r, gui) then
			n = n + 1
		end
	end
	return n
end
local NAMES = { "CloudHopper22", "MiaSkye", "xXStormFangXx", "PebblePup_99", "NimbusNinja", "LunaLeaf", "sky_rider07", "BiscuitBear", "ZoomyFoxx", "AuroraAce" }
-- ten rows: user ids 970001.., values from `top` down by `step`
function G.rows(top, step, base)
	local out = {}
	for i = 1, 10 do
		out[i] = { UserId = (base or 970000) + i, Name = NAMES[i], Value = top - (i - 1) * step }
	end
	return out
end
function G.state(opts)
	opts = opts or {}
	local now = workspace:GetServerTimeNow()
	local trophies = opts.Trophies or G.rows(4812, 300)
	local you = opts.You or { Rank = 37, Value = 1240 }
	return {
		Stats = {
			Trophies = { Top = trophies, You = you },
			Pets = { Top = opts.Pets or G.rows(34, 1, 971000), You = { Rank = 5, Value = 31 } },
			Ring = { Top = opts.Ring or {}, You = { Rank = nil, Value = 0 } },
		},
		Scope = opts.Scope or "Global",
		NextAt = now + (opts.NextIn or 220),
		UpdatedAt = now,
	}
end

S.client_leaderboard = guarded("client_leaderboard", function()
	local KC = _G.KC
	local Config, _, Theme = KC.env()
	local LC = G.req("client/Controllers/LeaderboardController")
	if not T.check(type(LC) == "table" and type(LC.Init) == "function" and type(LC.Page) == "function" and type(LC.SetPage) == "function" and type(LC.State) == "function",
		"leaderboard: client/Controllers/LeaderboardController loads (Init, Page, SetPage, State)") then
		return
	end
	local LB = Config.Leaderboard
	local PAGES = LB.Pages
	if not T.check(type(PAGES) == "table" and #PAGES == 3 and PAGES[1] == "Trophies" and PAGES[2] == "Pets" and PAGES[3] == "Ring", "leaderboard: Config pages Trophies / Pets / Ring (section 15)") then
		return
	end
	local left = G.cold(LC)
	if not T.check(left == 0, "leaderboard: (setup) a cold controller (_S) and no tagged board left in the workspace by an earlier scenario", tostring(left)) then
		return
	end
	Mock.ThumbnailCalls = {}
	local oldVp = { Mock.Viewport.X, Mock.Viewport.Y }
	Mock.SetViewport(1920, 1080)
	local boards = {}
	local ok, err = pcall(function()
		T.check(LC.State() == nil, "leaderboard: State() is nil before any LeaderboardState")

		------------------------------------------------------------------ the SurfaceGui on the board's Face
		-- (review round 1) found by the Face's tag through CollectionService, not by name through workspace.DescendantAdded
		local plain = G.board(12, true)
		boards[#boards + 1] = plain
		KC.advance(0.6)
		T.eq(#G.guis(), 0, "leaderboard: an untagged stand-in board is not adopted (the board is found by Config.Tags.LeaderboardFace)")
		local model, face = G.board(20)
		boards[#boards + 1] = model
		KC.advance(0.6)
		local guis = G.guis()
		local gui = guis[1]
		if not T.check(#guis == 1 and gui ~= nil, "leaderboard: one SurfaceGui LobbyLeaderboard in the PlayerGui", tostring(#guis)) then
			return
		end
		T.check(gui.Adornee == face, "leaderboard: Adornee = the board's Face", tostring(gui.Adornee and gui.Adornee:GetFullName()))
		T.check(gui.Face == Enum.NormalId.Front and gui.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud and gui.PixelsPerStud == 50,
			"leaderboard: Face Front, PixelsPerStud 50 (800 x 650 px)", fmt("%s %s %s", tostring(gui.Face), tostring(gui.SizingMode), tostring(gui.PixelsPerStud)))
		T.check(gui.MaxDistance == 80 and gui.ResetOnSpawn == false and gui.LightInfluence == 0, "leaderboard: MaxDistance 80, ResetOnSpawn false, LightInfluence 0",
			fmt("max %s, reset %s, light %s", tostring(gui.MaxDistance), tostring(gui.ResetOnSpawn), tostring(gui.LightInfluence)))
		local board = gui:FindFirstChild("Board")
		local missing = {}
		for _, name in ipairs({ "Title", "Tabs", "Scope", "Rows", "YouRow", "Footer", "Status" }) do
			if not (board and board:FindFirstChild(name)) then
				missing[#missing + 1] = name
			end
		end
		T.check(board ~= nil and #missing == 0, "leaderboard: Board > Title, Tabs, Scope, Rows, YouRow, Footer, Status", table.concat(missing, ", "))
		if not board then
			return
		end
		local bs = board.AbsoluteSize
		T.check(bs.X == 800 and bs.Y == 650, "leaderboard: the Board fills the 800 x 650 canvas", fmt("%dx%d", bs.X, bs.Y))
		local tabs = board:FindFirstChild("Tabs")
		local tabOk = tabs ~= nil
		for _, stat in ipairs(PAGES) do
			local tab = tabs and tabs:FindFirstChild("Tab_" .. stat)
			tabOk = tabOk and tab ~= nil and tab:IsA("TextButton") and tab.Text == LB.Labels[stat]
		end
		T.check(tabOk and #tabs:GetChildren() >= 3, "leaderboard: three tabs Tab_Trophies / Tab_Pets / Tab_Ring (TextButtons with the Labels)")
		local rowsOk = true
		for i = 1, 10 do
			local r = G.row(gui, i)
			local head = r and r:FindFirstChild("Head")
			rowsOk = rowsOk and r ~= nil and r:FindFirstChild("Rank") ~= nil and head ~= nil and head:IsA("ImageLabel") and r:FindFirstChild("Name") ~= nil and r:FindFirstChild("Value") ~= nil
				and head.AbsoluteSize.X == 34 and head.AbsoluteSize.Y == 34
		end
		T.check(rowsOk, "leaderboard: Rows > Row1..10, each with Rank, a 34 px Head ImageLabel, Name, Value")

		------------------------------------------------------------------ before any state
		local status = board:FindFirstChild("Status")
		T.check(status.Text == "Loading scores..." and G.shown(status, gui), "leaderboard: before any state Status reads 'Loading scores...'", tostring(status.Text))
		T.eq(G.shownRows(gui), 0, "leaderboard: no row shows before any state")

		------------------------------------------------------------------ a state with ten rows
		local st = G.state()
		st.Stats.Trophies.Top[4].Value = 1234567 -- Theme.ShortNumber from 1e6
		KC.toClient("LeaderboardState", st)
		KC.advance(0.2)
		LC.SetPage("Trophies")
		KC.advance(0.3)
		T.check(type(LC.State()) == "table" and LC.State().Scope == "Global", "leaderboard: State() returns the last payload")
		T.eq(LC.Page(), "Trophies", "leaderboard: Page() after SetPage('Trophies')")
		T.eq(G.text(board, "Title"), LB.Titles.Trophies, "leaderboard: the title reads " .. LB.Titles.Trophies)
		T.check(not G.shown(status, gui), "leaderboard: Status hidden while rows show")
		T.eq(G.shownRows(gui), 10, "leaderboard: ten rows show")
		local fillOk, fillWhy = true, ""
		for i = 1, 10 do
			local r = G.row(gui, i)
			local want = st.Stats.Trophies.Top[i]
			local value = (i == 4) and "1.23M" or Theme.ShortNumber(want.Value, 1e6)
			if not (r.Rank.Text == tostring(i) and G.nm(r).Text == want.Name and r.Value.Text == value) then
				fillOk, fillWhy = false, fmt("row %d: %s / %s / %s", i, r.Rank.Text, G.nm(r).Text, r.Value.Text)
				break
			end
		end
		T.check(fillOk, "leaderboard: Row1..10 hold rank, name and value (commas; 1.23M from 1e6)", fillWhy)
		T.eq(G.row(gui, 1).Value.Text, "4,812", "leaderboard: 4812 reads 4,812")
		local medals = { { 255, 201, 60 }, { 217, 224, 238 }, { 224, 149, 90 } }
		local medalOk = true
		for i = 1, 3 do
			local c = G.row(gui, i).Rank.BackgroundColor3
			medalOk = medalOk and G.rgb(c, medals[i][1], medals[i][2], medals[i][3]) and G.row(gui, i).Rank.BackgroundTransparency < 0.5
		end
		local c4 = G.row(gui, 4).Rank
		local plain4 = c4.BackgroundTransparency > 0.5
		for i = 1, 3 do
			plain4 = plain4 and not G.rgb(c4.BackgroundColor3, medals[i][1], medals[i][2], medals[i][3])
		end
		T.check(medalOk and plain4, "leaderboard: ranks 1-3 gold, silver, bronze; rank 4 plain")
		KC.advance(0.4)
		local heads = 0
		for i = 1, 10 do
			if G.row(gui, i).Head.Image ~= "" then
				heads = heads + 1
			end
		end
		T.eq(heads, 10, "leaderboard: ten headshots set (Players:GetUserThumbnailAsync)")
		T.eq(G.text(board, "YouRow"), "You " .. DOT .. " 1,240 " .. DOT .. " #37", "leaderboard: YouRow 'You . 1,240 . #37'")
		T.eq(G.text(board, "Scope"), "All players " .. DOT .. " all time", "leaderboard: Global scope line")
		local foot = G.text(board, "Footer") or ""
		T.check(foot:sub(1, 17) == "Refreshes in 3:40", "leaderboard: NextAt = now + 220 -> the footer starts 'Refreshes in 3:40'", foot)
		T.check(foot:find("tap a tab, or it turns in 0:1", 1, true) ~= nil, "leaderboard: the footer counts the turn ('tap a tab, or it turns in 0:ss')", foot)

		------------------------------------------------------------------ the You row both ways, the Server scope
		KC.toClient("LeaderboardState", G.state({ You = { Rank = nil, Value = 1240 } }))
		KC.advance(0.2)
		T.eq(G.text(board, "YouRow"), "You " .. DOT .. " 1,240 " .. DOT .. " not in the top 100", "leaderboard: Rank nil -> 'not in the top 100'")
		KC.toClient("LeaderboardState", G.state({ You = { Rank = nil, Value = nil } }))
		KC.advance(0.2)
		T.eq(G.text(board, "YouRow"), "You " .. DOT .. " ...", "leaderboard: Value nil (loading / provisional) -> 'You . ...'")
		KC.toClient("LeaderboardState", G.state({ Scope = "Server" }))
		KC.advance(0.2)
		T.eq(G.text(board, "Scope"), "This server only", "leaderboard: Scope 'Server' -> 'This server only'")
		KC.toClient("LeaderboardState", G.state())
		KC.advance(0.4)
		local cached = true
		for i = 1, 10 do
			cached = cached and (Mock.ThumbnailCalls[970000 + i] or 0) == 1
		end
		T.check(cached, "leaderboard: each headshot fetched once per user (cached across states)", fmt("calls for row 1: %s", tostring(Mock.ThumbnailCalls[970001])))

		------------------------------------------------------------------ tabs
		LC.SetPage("Pets")
		KC.advance(0.2)
		T.check(LC.Page() == "Pets" and G.text(board, "Title") == "TOP PETS FOUND", "leaderboard: SetPage('Pets') -> 'TOP PETS FOUND'", tostring(G.text(board, "Title")))
		T.eq(G.nm(G.row(gui, 1)).Text, "CloudHopper22", "leaderboard: the Pets page shows its own rows")
		Mock.Click(tabs:FindFirstChild("Tab_Ring"))
		KC.advance(0.2)
		T.check(LC.Page() == "Ring" and G.text(board, "Title") == LB.Titles.Ring, "leaderboard: a tap on Tab_Ring -> " .. LB.Titles.Ring, tostring(LC.Page()))
		T.check(G.shown(status, gui) and status.Text == "No scores yet. Be the first!" and G.shownRows(gui) == 0, "leaderboard: an empty page -> 'No scores yet. Be the first!'", tostring(status.Text))

		------------------------------------------------------------------ the page turns every 15 s; a tap restarts the count
		LC.SetPage("Trophies")
		KC.advance(0.1)
		local foot0 = G.text(board, "Footer") or ""
		T.check(foot0:find("it turns in 0:15", 1, true) ~= nil, "leaderboard: a page change restarts the turn at 0:15", foot0)
		KC.advance(14.3)
		T.eq(LC.Page(), "Trophies", "leaderboard: still Trophies at 14.4 s")
		KC.advance(1)
		T.eq(LC.Page(), "Pets", "leaderboard: the page turns by itself after 15 s (Trophies -> Pets)")
		LC.SetPage("Trophies")
		KC.advance(10)
		Mock.Click(tabs:FindFirstChild("Tab_Pets"))
		KC.advance(5.5)
		T.eq(LC.Page(), "Pets", "leaderboard: a tap at 10 s -> no turn at 15 s")
		KC.advance(9)
		T.eq(LC.Page(), "Pets", "leaderboard: ...still Pets at 24.5 s")
		KC.advance(1)
		T.eq(LC.Page(), "Ring", "leaderboard: ...the turn moved to 25 s (Pets -> Ring)")

		------------------------------------------------------------------ every text >= 30 px, everything inside the canvas
		LC.SetPage("Trophies")
		KC.advance(0.2)
		local small, scaled, outside = {}, {}, {}
		local texts = 0
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				texts = texts + 1
				if d.TextSize < 30 or d.TextSize / gui.PixelsPerStud < 0.6 then
					small[#small + 1] = d.Name .. " " .. tostring(d.TextSize)
				end
				if d.TextScaled then
					scaled[#scaled + 1] = d.Name
				end
			end
			if d:IsA("GuiObject") and G.shown(d, gui) then
				local p, s = d.AbsolutePosition, d.AbsoluteSize
				if p.X < -0.5 or p.Y < -0.5 or p.X + s.X > 800.5 or p.Y + s.Y > 650.5 then
					outside[#outside + 1] = fmt("%s %d,%d %dx%d", d.Name, p.X, p.Y, s.X, s.Y)
				end
			end
		end
		T.check(texts >= 38 and #small == 0 and #scaled == 0, "leaderboard: every board text >= 30 px (0.6 stud at 50 px per stud), none TextScaled",
			fmt("%d texts; small: %s; scaled: %s", texts, table.concat(small, ", "), table.concat(scaled, ", ")))
		T.check(#outside == 0, "leaderboard: every shown object inside the 800 x 650 canvas", table.concat(outside, "; "))

		------------------------------------------------------------------ long names and huge numbers (Review Focus 6)
		local r1 = G.row(gui, 1)
		local before = { G.nm(r1).TextSize, r1.Value.TextSize, r1.AbsoluteSize.X, r1.AbsoluteSize.Y, G.nm(r1).AbsoluteSize.X }
		local long = G.rows(4812, 300)
		long[1].Name = "ABCDEFGHIJKLMNOPQRST"
		long[1].Value = 1e12
		KC.toClient("LeaderboardState", G.state({ Trophies = long }))
		KC.advance(0.2)
		local nameL = G.nm(r1)
		-- (kit-b U6) a Nunito face reads .Font = Unknown, which GetTextSize refuses: Theme.MeasureLabel knows the face
		local w = Theme.MeasureLabel(nameL).X
		T.check(nameL.Text == long[1].Name and (w <= nameL.AbsoluteSize.X or nameL.TextTruncate ~= Enum.TextTruncate.None), "leaderboard: a 20-character name fits its box (or truncates)",
			fmt("text %d px in a %d px box", w, nameL.AbsoluteSize.X))
		T.eq(r1.Value.Text, "1T", "leaderboard: a value of 1e12 reads 1T")
		T.check(G.nm(r1).TextSize == before[1] and r1.Value.TextSize == before[2] and r1.AbsoluteSize.X == before[3] and r1.AbsoluteSize.Y == before[4] and G.nm(r1).AbsoluteSize.X == before[5],
			"leaderboard: long names and big numbers change no size")

		------------------------------------------------------------------ a headshot call that fails: blank, asked once, no error
		Mock.ThumbnailFail = true
		KC.toClient("LeaderboardState", G.state({ Trophies = G.rows(4812, 300, 972000) }))
		KC.advance(0.6)
		Mock.ThumbnailFail = nil
		KC.toClient("LeaderboardState", G.state({ Trophies = G.rows(4812, 300, 972000) }))
		KC.advance(0.6)
		T.check(G.row(gui, 1).Head.Image == "" and (Mock.ThumbnailCalls[972001] or 0) == 1, "leaderboard: a failed headshot stays blank and is not asked again",
			fmt("image '%s', calls %s", G.row(gui, 1).Head.Image, tostring(Mock.ThumbnailCalls[972001])))

		------------------------------------------------------------------ the lobby rebuilt (Review Focus 4)
		local lastName = G.nm(r1).Text
		model:Destroy()
		KC.advance(0.3)
		local model2, face2 = G.board(24)
		boards[#boards + 1] = model2
		KC.advance(1)
		T.check(gui.Adornee == face2, "leaderboard: lobby rebuilt -> Adornee is the new Face within 1 s", tostring(gui.Adornee and gui.Adornee:GetFullName()))
		T.check(#G.guis() == 1 and G.guis()[1] == gui, "leaderboard: lobby rebuilt -> the same SurfaceGui (re-adorned, not doubled)")
		T.check(G.nm(r1).Text == lastName and G.shownRows(gui) == 10, "leaderboard: lobby rebuilt -> the rows still show the last state", G.nm(r1).Text)
		local model3, face3 = G.board(28)
		boards[#boards + 1] = model3
		KC.advance(0.5)
		model2:Destroy()
		KC.advance(1)
		T.check(gui.Adornee == face3, "leaderboard: a new board built before the old one goes -> the new Face wins")

		KC.flushErrors("client_leaderboard")
		KC.flushWarnings("client_leaderboard")
	end)
	Mock.ThumbnailFail = nil
	for _, m in ipairs(boards) do
		pcall(function()
			m:Destroy()
		end)
	end
	Mock.SetViewport(oldVp[1], oldVp[2])
	KC.advance(0.3)
	if not ok then
		error(err, 0)
	end
end)

return S
