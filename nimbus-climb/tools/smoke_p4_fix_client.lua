-- smoke_p4_fix_client.lua: regression checks for the Phase 4 review fixes on the client (MenuController's Home window).
-- Loaded by tools/smoke.py in the client worlds (desktop 1920x1080 and the 390x844 touch phone):
--   client_p4fix_home_rows    the My Home window on landscape phone sizes (740x360, 812x375, 667x375): the list column
--                             is too slim for one-line station rows, so every row stacks like portrait (row height
--                             STATION_ROW_H_TALL): each station name fits on one line at its smallest text size, the
--                             info line keeps >= 200 design px, the name / info never run under the price + Upgrade
--                             box and the level pips never touch the price; the summary column stays (two columns);
--                             at 844x390 the rows read either way; at 1280x720 and 1920x1080 they stay one line
--                             (STATION_ROW_H)
--   client_p4fix_mobile       (phone world) the same at 740x360 and 667x375 on the touch phone, then back to portrait
--   client_p4fix_leave        a Champion Ring run / a Trial can be left (BattleCommand "Forfeit", BattleService takes it
--                             in a fight and in the ring intermission): BattleController's LEAVE beside ATTACK / RETREAT
--                             and on the next-round card, two presses (the first says "Sure? Tap again" and sends
--                             nothing; it falls back to LEAVE after ~3 s; the second sends exactly one Forfeit), a
--                             Forfeit between two rounds passes Command while the won round has ended (Attack does
--                             not); no LEAVE in duels; off the screen centre, clear of the other battle controls,
--                             Theme's Button font, >= 14 px at 1920x1080 / 1280x720 / 390x844 / 844x390
--   client_p4fix_leave_mobile (phone world) the same layout checks on the touch phone (390x844, 844x390, 740x360,
--                             667x375): LEAVE covers no other button (RUN / DASH, menu, hotbar), no team card, no
--                             top card and stays on the screen
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local KC = _G.KC

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function advance(seconds)
	if KC and KC.advance then
		KC.advance(seconds)
	else
		Mock.Advance(seconds)
	end
end

local function moduleAt(top, rest)
	local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	return ok and type(result) == "table" and result or nil
end

local Config = moduleAt("shared", "Config")
local PetCatalog = moduleAt("shared", "PetCatalog")
local Theme = moduleAt("shared", "Theme")

local function pg()
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function menu()
	return (KC and KC.M and KC.M.MenuController) or moduleAt("client", "Controllers/MenuController")
end

local function shown(obj)
	local cur = obj
	while cur and cur ~= game do
		if cur:IsA("LayerCollector") then
			if cur.Enabled == false then
				return false
			end
		elseif cur:IsA("GuiObject") and cur.Visible == false then
			return false
		end
		cur = cur.Parent
	end
	return true
end

local function find(root, name)
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local function bootIfNeeded()
	if not ReplicatedStorage:FindFirstChild("Remotes") then
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, n in ipairs(Config.Remotes) do
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
	if not (pg() and pg():FindFirstChild("NimbusMenu")) then
		Mock.RunScript(Mock.GetPath(ROOTS["client"] .. "/Main"))
		advance(3)
	end
end

local plot = nil
local function setPlot()
	local lobby = workspace:FindFirstChild("NimbusLobby")
	if not lobby then
		lobby = Instance.new("Folder")
		lobby.Name = "NimbusLobby"
		lobby.Parent = workspace
	end
	if not plot or not plot.Parent then
		plot = Instance.new("Folder")
		plot.Name = "Spot_07"
		plot:SetAttribute("SpotIndex", 7)
		plot.Parent = lobby
	end
	local attrs = { CollectorCash = 1840, IncomePerSecond = 38.5, GardenSlots = 4, HomeLevel = 22, Prestige = 1 }
	for _, k in ipairs({ "CollectorCash", "IncomePerSecond", "GardenSlots", "HomeLevel", "Prestige" }) do
		plot:SetAttribute(k, attrs[k])
	end
	LocalPlayer:SetAttribute(Config.Attr.SpotIndex, 7)
end

local function firstPet()
	for _, def in ipairs(PetCatalog.Pets) do
		if not def.EventOnly and def.Rarity == "Common" then
			return def.Id
		end
	end
	return PetCatalog.Pets[1].Id
end

-- a home in the middle of Phase 4 with stations below their max (so the price + Upgrade box is shown)
local function sync()
	setPlot()
	local id = firstPet()
	local snap = {
		Tokens = 900,
		Pets = { [id] = 1 },
		Equipped = { id },
		Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
		Discovered = { [id] = true },
		IndexClaimed = {},
		Tutorial = { Step = 99, Done = true, Gifted = true },
		Cash = 250000,
		Gems = 50,
		Home = {
			Level = 22,
			Prestige = 1,
			Stations = { Garden = 2, Press1 = 5, Press2 = 3, Collector = 2, Kitchen = 2, Gym = 2, Vault = 1, House = 3 },
			Garden = { id, "", "", "" },
			Gym = {},
			CollectorCash = 1840,
		},
		Food = {},
		PetLevels = { [id] = { Level = 12, Xp = 300 } },
		PetGrowth = {},
		Ring = { Best = 0, Runs = 0 },
	}
	LocalPlayer:SetAttribute(Config.Attr.Cash, snap.Cash)
	LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
	Mock.ToClient(ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("ProfileSync"), snap)
	advance(0.4)
end

local function cleanup()
	local M = menu()
	if M and M.Close then
		M.Close()
	end
	advance(0.3)
	LocalPlayer:SetAttribute(Config.Attr.SpotIndex, nil)
	if plot then
		plot:Destroy()
		plot = nil
	end
	advance(0.3)
end

local function design(inst)
	local b = Mock.GuiBox(inst)
	local s = (b.scale and b.scale > 0) and b.scale or 1
	return { x = b.x / s, y = b.y / s, w = b.w / s, h = b.h / s, r = (b.x + b.w) / s, b = (b.y + b.h) / s }
end

-- tol: design px two boxes may share (the one-line rows' name box ends 2 px into the price box by design)
local function overlap(a, b, tol)
	tol = tol or 0.5
	return a.x < b.r - tol and b.x < a.r - tol and a.y < b.b - tol and b.y < a.b - tol
end

local function minSize(label)
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	if label.TextScaled and c then
		return c.MinTextSize
	end
	return label.TextSize
end

-- the station rows of the open Home window at the current viewport: a list of problems (empty = fine)
local function rowProblems(win, wantStacked)
	-- MenuController's K.STATION_ROW_H_TALL / K.STATION_ROW_H (wantStacked nil: either, as long as the rows read)
	local wantH = (wantStacked == true and 132) or (wantStacked == false and 96) or nil
	local out, rows = {}, 0
	local list = {}
	for _, d in ipairs(win:GetDescendants()) do
		if d:IsA("GuiObject") and d.Name:sub(1, 8) == "Station_" and shown(d) then
			list[#list + 1] = d
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	for _, row in ipairs(list) do
		rows = rows + 1
		local id = row.Name:sub(9)
		local name, info, right = find(row, "Name"), find(row, "Info"), find(row, "Action")
		local price, pips = find(row, "Price"), find(row, "Pips")
		local fb = design(row)
		if wantH and math.abs(fb.h - wantH) > 0.5 then
			out[#out + 1] = string.format("%s row h=%.0f (want %d)", id, fb.h, wantH)
		end
		if name then
			local nb = design(name)
			local need = #tostring(name.Text) * 0.5 * minSize(name)
			if nb.w + 0.5 < need then
				out[#out + 1] = string.format("%s name '%s' w=%.0f < %.0f", id, name.Text, nb.w, need)
			end
			if right and shown(right) and overlap(nb, design(right), 4) then
				out[#out + 1] = id .. " name under the price box"
			end
		end
		if info and info.Text ~= "" then
			local ib = design(info)
			if ib.w < 200 then
				out[#out + 1] = string.format("%s info w=%.0f < 200", id, ib.w)
			end
			if right and shown(right) and overlap(ib, design(right), 4) then
				out[#out + 1] = id .. " info under the price box"
			end
		end
		if price and pips and shown(price) and shown(pips) and price.Text ~= "" and overlap(design(price), design(pips)) then
			out[#out + 1] = id .. " price on the level pips"
		end
	end
	if rows < 4 then
		out[#out + 1] = "only " .. rows .. " station rows shown"
	end
	return out
end

local function checkSizes(tag, sizes)
	local M = menu()
	local before = Mock.Viewport
	for _, sz in ipairs(sizes) do
		M.Close()
		Mock.SetViewport(sz[1], sz[2])
		advance(0.4)
		M.Open("Home")
		advance(0.8)
		local win = pg():FindFirstChild("NimbusMenu") and pg().NimbusMenu:FindFirstChild("Window_Home")
		if T.check(win ~= nil and win.Visible, string.format("p4fix %s %dx%d: the Home window opens", tag, sz[1], sz[2])) then
			local probs = rowProblems(win, sz[3])
			local how = (sz[3] == true and "stack like portrait") or (sz[3] == false and "stay one line") or "read"
			T.check(#probs == 0, string.format("p4fix %s %dx%d: station rows %s (whole names, info line, price clear of the pips)",
				tag, sz[1], sz[2], how), string.format("list w=%.0f; ", design(find(win, "Stations")).w) .. table.concat(probs, "; "))
			if sz[4] then
				local summary = find(win, "Summary")
				local cw = find(win, "CoinsWaiting")
				T.check(summary ~= nil and shown(summary) and cw ~= nil and shown(cw) and cw:IsDescendantOf(summary),
					string.format("p4fix %s %dx%d: the summary column stays beside the list (two columns)", tag, sz[1], sz[2]))
			end
		end
	end
	M.Close()
	Mock.SetViewport(before.X, before.Y)
	advance(0.4)
end

S.client_p4fix_home_rows = guarded("client_p4fix_home_rows", function()
	bootIfNeeded()
	local M = menu()
	if not T.check(type(M) == "table" and type(M.Open) == "function", "p4fix: MenuController loads with Open") then
		return
	end
	if M.Init then
		M.Init()
	end
	sync()
	-- { w, h, stacked rows?, two columns? }
	checkSizes("home", {
		{ 740, 360, true, true },
		{ 812, 375, true, true },
		{ 667, 375, true, true },
		{ 844, 390, nil, true },
		{ 1280, 720, false, true },
		{ 1920, 1080, false, true },
	})
	cleanup()
end)

S.client_p4fix_mobile = guarded("client_p4fix_mobile", function()
	bootIfNeeded()
	local M = menu()
	if not T.check(type(M) == "table" and type(M.Open) == "function", "p4fix phone: MenuController loads with Open") then
		return
	end
	if M.Init then
		M.Init()
	end
	sync()
	checkSizes("phone", {
		{ 740, 360, true, true },
		{ 667, 375, true, true },
	})
	cleanup()
end)

----------------------------------------------------------------------------------------------------
-- LEAVE in the battle HUD (a ring run / a trial can be stopped: BattleCommand "Forfeit")
----------------------------------------------------------------------------------------------------
local function battleGui()
	return pg() and pg():FindFirstChild("NimbusBattle")
end

local function at(path)
	local cur = battleGui()
	for name in string.gmatch(path, "[^%.]+") do
		cur = cur and cur:FindFirstChild(name)
	end
	return cur
end

local function rect(obj)
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	local gui = obj:FindFirstAncestorOfClass("ScreenGui")
	local dy = (gui and gui.IgnoreGuiInset == false) and (Mock.TopInset or 36) or 0
	return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
end

local function hits(a, b)
	return a.x0 < b.x1 - 1 and b.x0 < a.x1 - 1 and a.y0 < b.y1 - 1 and b.y0 < a.y1 - 1
end

local function forfeits(from)
	local n = 0
	for _, e in ipairs(_G.KC.serverCalls("BattleCommand", from)) do
		if e.args[1] == "Forfeit" then
			n = n + 1
		end
	end
	return n
end

local function team(count)
	local out, kinds = {}, {}
	for _, def in ipairs(PetCatalog.Pets) do
		local sp = type(def.Special) == "table" and def.Special.Kind or nil
		if sp and def.Role == "Combat" and not kinds[sp] and def.Rarity ~= "Secret" and not def.EventOnly then
			kinds[sp] = true
			out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = 30, Tier = "Normal", Slot = #out + 1, Xp = 100, XpNext = 6000 }
			if #out >= count then
				break
			end
		end
	end
	return out
end

-- a battle sent the way BattleService sends it (Start / Snapshot / End through BattleState)
local function newBattle(mode, round)
	local Sim = moduleAt("shared", "BattleSim")
	local BCat = moduleAt("shared", "BattleCatalog")
	if not Sim or not BCat then
		return nil
	end
	local me = LocalPlayer.UserId
	local id = "p4fix_" .. mode .. "_" .. tostring(math.random(100000, 999999))
	local opts = { Mode = mode, Seed = 5, Id = id, Zone = { X = 44, Z = 44 }, TimeLimit = 90 }
	local ring = nil
	if mode == "Ring" then
		local spec = BCat.ChampionTeam(round, 7)
		local ch = spec.Champion or {}
		opts.Round = round
		opts.Teams = { { Owner = me, Side = 1, Pets = team(3) }, spec }
		ring = { Round = round, Best = 12, Start = 1, Champion = { PetId = ch.PetId, Level = ch.Level, Tier = ch.Tier, Boss = ch.Boss == true, Name = ch.Name } }
	elseif mode == "Trial" then
		opts.Trial = 3
		opts.Teams = { { Owner = me, Side = 1, Pets = team(3) } }
	else
		opts.Teams = { { Owner = me, Side = 1, Pets = team(2) }, { Owner = 78, Side = 2, Pets = team(2) } }
	end
	local sim = Sim.new(opts)
	if not sim then
		return nil
	end
	local d = { sim = sim, id = id }
	function d.start()
		local p = sim:Describe()
		p.BattleId = id
		p.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
		p.Names = { [tostring(me)] = LocalPlayer.Name, ["78"] = "Rival" }
		p.Side = 1
		p.Spectator = false
		p.T = sim:Time()
		p.Ring = ring
		LocalPlayer:SetAttribute("InBattle", id)
		_G.KC.toClient("BattleState", "Start", p, id)
		for _ = 1, 3 do
			sim:Step(0.1)
			local snap = sim:Snapshot()
			snap.BattleId = id
			_G.KC.toClient("BattleState", "Snapshot", snap, id)
			Mock.Step(1 / 30)
			Mock.Step(1 / 30)
		end
	end
	function d.finish(payload)
		payload.BattleId = id
		_G.KC.toClient("BattleState", "End", payload, id)
		Mock.Step(1 / 30)
		Mock.Step(1 / 30)
	end
	return d
end

local function ringWon(round)
	return { Mode = "Ring", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
		Rewards = { Won = true, Next = round + 1, Round = round, Cash = 40, Xp = 20 + 6 * round, Tokens = 0, Record = false, Seconds = 1.6, LevelUps = 0 } }
end

local function ringFinal(round)
	return { Mode = "Ring", Outcome = "Left", Won = false, Spectator = false, Reason = "Forfeit", Round = round,
		Rewards = { Won = false, Final = true, Round = round, Cash = 0, Xp = 0, Run = { Wins = 1, Cash = 40, Xp = 50, Tokens = 0, Round = round, Start = 1, Best = 12 } } }
end

local function closeBattle()
	LocalPlayer:SetAttribute("InBattle", nil)
	advance(4)
	local ok = at("Root.ResultCard.OkButton")
	if ok then
		Mock.Click(ok)
	end
	Mock.Step(1 / 30)
	Mock.Step(1 / 30)
end

-- layout problems of a shown LEAVE at this viewport (nil = fine); others = rects of things it must not cover
local function leaveProblem(b, w, h, others)
	if not b or not shown(b) then
		return "not shown"
	end
	local r = rect(b)
	local scale = at("Root.ReadScale")
	local px = b.TextSize * (scale and scale.Scale or 1)
	if px < 13.99 then
		return "text " .. string.format("%.1f", px) .. " px"
	end
	if b.Font ~= Theme.Fonts.Button then
		return "font " .. tostring(b.Font) .. " is not Theme's Button role"
	end
	if r.x1 - r.x0 < 40 or r.y1 - r.y0 < 30 then
		return string.format("too small to tap (%.0fx%.0f px)", r.x1 - r.x0, r.y1 - r.y0)
	end
	if r.x0 < -1 or r.y0 < -1 or r.x1 > w + 1 or r.y1 > h + 1 then
		return "off the screen"
	end
	local cx, cy = w / 2, h / 2
	if r.x0 <= cx and cx <= r.x1 and r.y0 <= cy and cy <= r.y1 then
		return "in the screen centre"
	end
	local mx, my = (r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2
	if math.abs(mx - cx) < 0.1 * w and math.abs(my - cy) < 0.1 * h then
		return "its text sits in the middle of the screen"
	end
	for _, o in ipairs(others) do
		if hits(r, o[2]) then
			return string.format("covers %s (LEAVE %.0f,%.0f-%.0f,%.0f; it %.0f,%.0f-%.0f,%.0f)", o[1], r.x0, r.y0, r.x1, r.y1, o[2].x0, o[2].y0, o[2].x1, o[2].y1)
		end
	end
	return nil
end

-- what LEAVE must keep clear of: the battle HUD's other parts + every other GUI's buttons
local function obstacles(card)
	local out = {}
	for _, path in ipairs({ "Root.TopCard", "Root.Commands.AttackButton", "Root.Commands.RetreatButton", "Root.ResultCard" }) do
		local o = at(path)
		if o and shown(o) then
			out[#out + 1] = { path, rect(o) }
		end
	end
	if not card then
		local nc = at("Root.NextRoundCard")
		if nc and shown(nc) then
			out[#out + 1] = { "Root.NextRoundCard", rect(nc) }
		end
	end
	for i = 1, 4 do
		local o = at("Root.Team.Row" .. i)
		if o and shown(o) then
			out[#out + 1] = { "Row" .. i, rect(o) }
		end
	end
	local back = at("Root.Team.Back")
	if back and shown(back) then
		out[#out + 1] = { "Root.Team.Back", rect(back) }
	end
	for _, g in ipairs(pg() and pg():GetChildren() or {}) do
		if g:IsA("ScreenGui") and g.Name ~= "NimbusBattle" and g.Enabled then
			for _, o in ipairs(g:GetDescendants()) do
				if o:IsA("GuiButton") and shown(o) and o.AbsoluteSize.X > 20 and o.AbsoluteSize.X < 300 then
					out[#out + 1] = { o:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", ""), rect(o) }
				end
			end
			for _, path in ipairs({ "Vitals", "Currency", "Hotbar" }) do
				local o = g:FindFirstChild(path, true)
				if o and o:IsA("GuiObject") and shown(o) then
					out[#out + 1] = { g.Name .. "." .. path, rect(o) }
				end
			end
		end
	end
	return out
end

-- the fight's LEAVE and the next-round card's LEAVE at each size: shown, readable, clear of everything
local function checkLeaveLayout(tag, sizes)
	for _, size in ipairs(sizes) do
		local w, h = size[1], size[2]
		local name = tag .. " " .. w .. "x" .. h
		Mock.SetViewport(w, h)
		advance(0.5)
		local d = newBattle("Ring", 4)
		if not T.check(d ~= nil, name .. ": a ring round to lay out") then
			return
		end
		d.start()
		advance(0.3)
		local b = at("Root.Commands.LeaveButton")
		local why = leaveProblem(b, w, h, obstacles(false))
		T.check(why == nil, name .. ": the fight's LEAVE is readable, off the centre and covers no control / card / button", tostring(why) .. (b and string.format(" [%.0f,%.0f %.0fx%.0f]", b.AbsolutePosition.X, b.AbsolutePosition.Y, b.AbsoluteSize.X, b.AbsoluteSize.Y) or ""))
		d.finish(ringWon(4))
		advance(0.3)
		local nb = at("Root.NextRoundCard.LeaveButton")
		why = leaveProblem(nb, w, h, obstacles(true))
		T.check(why == nil and not shown(b), name .. ": the next-round card's LEAVE is readable and covers nothing (the fight's LEAVE went with the commands)", tostring(why))
		d.finish(ringFinal(4))
		closeBattle()
	end
end

S.client_p4fix_leave = guarded("client_p4fix_leave", function()
	bootIfNeeded()
	local BC = moduleAt("client", "Controllers/BattleController")
	if not T.check(BC ~= nil and type(BC.Command) == "function", "p4fix leave: BattleController loads") then
		return
	end
	local errBefore = #Mock.Errors
	Mock.SetViewport(1920, 1080)
	advance(0.5)
	-- a ring round: LEAVE beside ATTACK / RETREAT
	local d = newBattle("Ring", 3)
	if not T.check(d ~= nil, "p4fix leave: a ring round (BattleSim + ChampionTeam)") then
		return
	end
	d.start()
	local b = at("Root.Commands.LeaveButton")
	T.check(b and shown(b) and b.Text == "LEAVE", "p4fix leave: a ring fight shows LEAVE beside ATTACK / RETREAT", b and tostring(b.Text) or "missing")
	local mark = #Mock.RemoteLog
	if b then
		Mock.Click(b)
	end
	advance(0.1)
	T.check(b and b.Text == "Sure? Tap again" and forfeits(mark) == 0, "p4fix leave: the first tap only asks (Sure? Tap again), nothing is sent", b and b.Text or "")
	advance(3.3)
	T.check(b and b.Text == "LEAVE" and forfeits(mark) == 0, "p4fix leave: without a second tap it goes back to LEAVE after ~3 s", b and b.Text or "")
	if b then
		Mock.Click(b)
		advance(0.4)
		Mock.Click(b)
	end
	advance(0.1)
	T.check(forfeits(mark) == 1, "p4fix leave: two taps send exactly one BattleCommand('Forfeit')", forfeits(mark) .. " sent")
	T.check(b and b.Text ~= "Sure? Tap again", "p4fix leave: ...and the button stops asking", b and b.Text or "")
	-- the server ends the run (BattleService: Forfeit -> the run's final End)
	d.finish(ringFinal(3))
	advance(0.3)
	T.check(shown(at("Root.ResultCard")) and not shown(at("Root.Commands.LeaveButton")), "p4fix leave: the run's End after a Forfeit in a fight: the result card, no LEAVE left")
	closeBattle()
	-- between two rounds: the next-round card has its own LEAVE, and Forfeit passes Command while the round has ended
	d = newBattle("Ring", 3)
	d.start()
	b = at("Root.Commands.LeaveButton")
	T.check(b and b.Text == "LEAVE", "p4fix leave: the next run's round starts with a plain LEAVE", b and b.Text or "missing")
	if b then
		Mock.Click(b) -- armed in the fight ...
	end
	d.finish(ringWon(3)) -- ... and the round is won: the card starts unarmed
	advance(0.3)
	local nb = at("Root.NextRoundCard.LeaveButton")
	T.check(nb and shown(nb) and nb.Text == "LEAVE" and not shown(b), "p4fix leave: the next-round card shows LEAVE (the commands are gone)", nb and tostring(nb.Text) or "missing")
	T.check(BC.Command("Attack", nil) == false, "p4fix leave: between rounds ATTACK is still refused locally")
	mark = #Mock.RemoteLog
	if nb then
		Mock.Click(nb)
		advance(0.3)
		T.check(nb.Text == "Sure? Tap again" and forfeits(mark) == 0, "p4fix leave: the card's first tap only asks", nb.Text)
		Mock.Click(nb)
	end
	advance(0.1)
	T.check(forfeits(mark) == 1, "p4fix leave: the card's second tap sends Forfeit during the intermission (Command lets it through)", forfeits(mark) .. " sent")
	d.finish(ringFinal(3))
	advance(0.3)
	T.check(shown(at("Root.ResultCard")) and not shown(at("Root.NextRoundCard")) and not shown(at("Root.Commands.LeaveButton")), "p4fix leave: the run's End shows the result card, no LEAVE left")
	closeBattle()
	-- a trial has LEAVE, a duel never does (a forfeited duel costs trophies)
	local tr = newBattle("Trial")
	if tr then
		tr.start()
		T.check(shown(at("Root.Commands.LeaveButton")), "p4fix leave: a Trial shows LEAVE")
		tr.finish({ Mode = "Trial", Outcome = "Loss", Won = false, Spectator = false, Reason = "Forfeit", Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0, Level = 3 } })
		closeBattle()
	end
	local du = newBattle("Duel")
	if du then
		du.start()
		T.check(shown(at("Root.Commands.AttackButton")) and not shown(at("Root.Commands.LeaveButton")), "p4fix leave: a duel has no LEAVE")
		du.finish({ Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe", Rewards = { Tokens = 60, Gems = 0, Xp = 60, Trophies = 25, LevelUps = 0 } })
		closeBattle()
	end
	-- the layout at the four render sizes (this world is a desktop: the small sizes use the compact HUD)
	checkLeaveLayout("desktop", { { 1920, 1080 }, { 1280, 720 }, { 390, 844 }, { 844, 390 } })
	Mock.SetViewport(1920, 1080)
	advance(0.5)
	T.check(BC.GetBattle() == nil and #Mock.Errors == errBefore, "p4fix leave: everything freed, no errors", tostring(Mock.Errors[#Mock.Errors]))
	_G.KC.flushErrors("client_p4fix_leave")
end)

S.client_p4fix_leave_mobile = guarded("client_p4fix_leave_mobile", function()
	bootIfNeeded()
	local BC = moduleAt("client", "Controllers/BattleController")
	if not T.check(BC ~= nil, "p4fix leave phone: BattleController loads") then
		return
	end
	local errBefore = #Mock.Errors
	checkLeaveLayout("phone", { { 390, 844 }, { 844, 390 }, { 740, 360 }, { 667, 375 } })
	Mock.SetViewport(390, 844)
	advance(0.5)
	T.check(BC.GetBattle() == nil and #Mock.Errors == errBefore, "p4fix leave phone: everything freed, no errors", tostring(Mock.Errors[#Mock.Errors]))
	_G.KC.flushErrors("client_p4fix_leave_mobile")
end)

return S
