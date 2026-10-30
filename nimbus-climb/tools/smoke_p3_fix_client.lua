-- smoke_p3_fix_client.lua: regression checks for the Phase 3 review fixes on the client (BattleController, MenuController,
-- NotifyController, TutorialController). Loaded by tools/smoke.py in the client worlds (desktop 1920x1080 and the
-- 390x844 touch phone). A real BattleSim is stepped at 10 Hz here and sent through BattleState in the wire form
-- BattleService uses (BattleSim:SnapshotDelta); the client's BattleCommand calls are forwarded into the sim.
--   client_p3fixcli_telegraph  (#7) a boss telegraph's fill completes at the dodge DEADLINE on the render clock
--                              (impact - render delay - round trip - run-out), not at the impact: SafeAt is that far
--                              before At, the shape is not "late" before it and flashes ("late") between it and the
--                              impact; Phase 5: while a telegraph that has not hit covers my fighter, DASH glows (Cue
--                              "Dash": dash through it) and the cue stops once it has hit; every boss telegraph leaves
--                              >= 1 s of fill
--   client_p3fixcli_retreat    (#8; Phase 5: RETREAT is gone) the SPECIAL button follows the energy: dim and refused
--                              (a shake, nothing sent) while it charges, gold at 100, and the press sends Special; Practice
--                              / Tier None / Void results read as such
--   client_p3fixcli_landscape  (#9) an 844x390 window: the fighter card + helper portraits sit at the top-left edge
--                              (TeamPlace TopLeft) where the menu tiles step aside (the column frame keeps its place),
--                              nothing of the battle HUD contains or sits in the screen centre, the fighter block covers
--                              no top card / action button / vitals / hotbar; the tiles come back after the battle; a
--                              portrait phone hides them too, 1920x1080 keeps them; Phase 4: between two Champion Ring
--                              rounds the side card sits at the right edge (off the centre, over no button / fighter
--                              card / vitals / hotbar / currency, texts >= 14 px), the run's card replaces it and the
--                              tiles come back
--   client_p3fixcli_devhelp    (extra) the two /devhelp toasts on an 844x390 screen: the one pushed out for room waits
--                              and is shown (whole, readable, at the right edge) after the other one
--   client_p3fixcli_tutorial   (extra) with a party panel up (a match is about to start) an opened tutorial card never
--                              covers the vitals card or the hotbar (beside the panel or not; 844x390 / 1280x720 /
--                              1024x600 / 390x844), in the plain lobby it still opens; the panel hides while compact
--                              battle cards hold the top / left of the screen and comes back after the battle
--   client_p3fixcli_mobile     (phone world) the same landscape battle checks on an 844x390 touch phone (RUN / DASH,
--                              thumbstick side), then back to portrait
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local KC = _G.KC
local S = {}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local abs, floor, max, min = math.abs, math.floor, math.max, math.min

local function fmt(v, n)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return string.format("%." .. (n or 2) .. "f", v)
end

local function moduleAt(top, rest)
	local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	return ok and type(result) == "table" and result or nil
end

local function step(n, dt)
	for _ = 1, n or 1 do
		Mock.Step(dt)
	end
end

local function playerGui()
	return LocalPlayer:FindFirstChild("PlayerGui")
end

local function shown(obj)
	if not obj then
		return false
	end
	local cur = obj
	while cur and not cur:IsA("ScreenGui") do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	return cur ~= nil and cur.Enabled
end

local function find(path)
	local pg = playerGui()
	local cur = pg and pg:FindFirstChild("NimbusBattle")
	for name in string.gmatch(path, "[^%.]+") do
		if not cur then
			return nil
		end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

-- screen rect of a GuiObject (the inset added for ScreenGuis that do not ignore it)
local function screenRect(obj)
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	local gui = obj:FindFirstAncestorOfClass("ScreenGui")
	local dy = (gui and gui.IgnoreGuiInset == false) and (Mock.TopInset or 36) or 0
	return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
end

local function overlap(a, b)
	return a.x0 < b.x1 - 1 and b.x0 < a.x1 - 1 and a.y0 < b.y1 - 1 and b.y0 < a.y1 - 1
end

local function rectText(r)
	return fmt(r.x0, 0) .. "," .. fmt(r.y0, 0) .. "-" .. fmt(r.x1, 0) .. "," .. fmt(r.y1, 0)
end

local function commandsSince(index)
	local out = {}
	for _, e in ipairs(KC.serverCalls("BattleCommand", index)) do
		out[#out + 1] = { action = e.args[1], arg = e.args[2] }
	end
	return out
end

local function battleWarnings(fromIndex)
	for i = fromIndex + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and o.text:find("BattleController", 1, true) then
			return o.text
		end
	end
	return nil
end

-- the phone world boots its own client
local function ensureClient()
	local pg = playerGui()
	if pg and pg:FindFirstChild("NimbusHud") then
		return
	end
	local main = Mock.GetPath(ROOTS["client"] .. "/Main")
	local Config = moduleAt("shared", "Config")
	local RS = game:GetService("ReplicatedStorage")
	if Config and not RS:FindFirstChild("Remotes") then
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, n in ipairs(Config.Remotes) do
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = folder
		end
		folder.Parent = RS
	end
	if main then
		Mock.RunScript(main)
		Mock.Advance(8)
	end
end

----------------------------------------------------------------------------------------------------
-- the battle driver: a real BattleSim sent the way BattleService sends it (wire-form snapshots)
----------------------------------------------------------------------------------------------------
local function catalogTeam(count, level)
	local PC = moduleAt("shared", "PetCatalog")
	local out, kinds = {}, {}
	for _, def in ipairs(PC and PC.Pets or {}) do
		local sp = type(def.Special) == "table" and def.Special.Kind or nil
		if sp and def.Role == "Combat" and not kinds[sp] and def.Rarity ~= "Secret" and not def.EventOnly then
			kinds[sp] = true
			out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = level or 10, Tier = "Normal", Slot = #out + 1 }
			if #out >= count then
				break
			end
		end
	end
	return out
end

local Driver = {}
Driver.__index = Driver

local function newDriver(opts)
	local Sim = moduleAt("shared", "BattleSim")
	if not Sim then
		return nil
	end
	local id = "fixcli_" .. tostring(opts.Mode) .. "_" .. tostring(math.random(100000, 999999))
	local sim = Sim.new({ Mode = opts.Mode, Seed = opts.Seed or 5, Id = id, Teams = opts.Teams, Boss = opts.Boss, Round = opts.Round, Zone = opts.Zone or (opts.Mode == "Dungeon" and { X = 44, Z = 44 } or nil), TimeLimit = opts.TimeLimit or (opts.Mode == "Dungeon" and 120 or nil) })
	if not sim then
		return nil
	end
	if opts.Wave then
		sim:SpawnEnemies(opts.Wave, { Wave = 1, Anchor = { 0, 10 } })
	end
	local d = setmetatable({ sim = sim, id = id, logIndex = #Mock.RemoteLog, events = {}, last = nil, ring = opts.Ring }, Driver)
	d.me = LocalPlayer.UserId
	return d
end

function Driver:start()
	local p = self.sim:Describe()
	p.BattleId = self.id
	p.Zone = { CFrame = CFrame.new(0, 220, 0), Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
	p.Names = { [tostring(self.me)] = LocalPlayer.Name }
	p.Side = 1
	p.Spectator = false
	p.T = self.sim:Time()
	p.Ring = self.ring -- Phase 4: a Champion Ring round's Start.Ring
	local team = self.sim:TeamOf(self.me) -- Phase 5: the receiver's own team (BattleService.startPayload)
	if team then
		p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed, Cooldowns = { Element = 0, Dash = 0, Swap = 0, Buff = {} } }
	end
	LocalPlayer:SetAttribute("InBattle", self.id)
	KC.toClient("BattleState", "Start", p, self.id)
end

function Driver:forward()
	for _, c in ipairs(commandsSince(self.logIndex)) do
		pcall(self.sim.Command, self.sim, self.me, c.action, c.arg)
	end
	self.logIndex = #Mock.RemoteLog
end

-- one 0.1 s server step, drawn at 30 fps; returns the step's events
function Driver:step()
	self:forward()
	local evs = self.sim:Step(0.1)
	for _, e in ipairs(evs) do
		self.events[#self.events + 1] = e
	end
	if #evs > 0 then
		KC.toClient("BattleState", "Events", evs, self.id)
	end
	self.last = self.last or {} -- the receiver's baseline (SnapshotDelta updates it in place, like BattleService)
	local payload = self.sim:SnapshotDelta(self.last)
	if type(payload) == "table" then
		payload.BattleId = self.id
		KC.toClient("BattleState", "Snapshot", payload, self.id)
	end
	step(3, 0.1 / 3)
	return evs
end

function Driver:finish(payload)
	payload = payload or {}
	payload.BattleId = self.id
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.toClient("BattleState", "End", payload, self.id)
end

function Driver:myUnits()
	local out = {}
	for _, u in ipairs(self.sim.units or {}) do
		if u.owner == self.me then
			out[#out + 1] = u
		end
	end
	return out
end

-- Phase 5: a dungeon room (my team vs a wave of wild pets) replaces the Trials of these checks
local function roomDriver(level, n)
	local wave = {}
	for i, e in ipairs(catalogTeam(n or 3, 6)) do
		e.Slot = nil
		e.Wild = true
		wave[i] = e
	end
	return newDriver({ Mode = "Dungeon", Seed = 4, Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = catalogTeam(3, level or 14) } }, Wave = wave })
end

local function cleanup(BC)
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(14)
	return BC.GetBattle() == nil
end

----------------------------------------------------------------------------------------------------
-- #7 telegraph deadline
----------------------------------------------------------------------------------------------------
S.client_p3fixcli_telegraph = guarded("client_p3fixcli_telegraph", function()
	local BC = moduleAt("client", "Controllers/BattleController")
	local BCat = moduleAt("shared", "BattleCatalog")
	if not (BC and BCat and type(BC.GetTelegraphs) == "function") then
		T.fail("#7: BattleController.GetTelegraphs missing")
		return
	end
	-- every boss telegraph leaves at least a second of fill before its deadline (render delay + ping + run-out)
	local shortest = math.huge
	for _, boss in pairs(BCat.Bosses or {}) do
		for _, a in ipairs(boss.Attacks or {}) do
			shortest = min(shortest, tonumber(a.Telegraph) or 0)
		end
	end
	T.check(shortest >= 2.2, "#7: every boss telegraph lasts >= 2.2 s (the client's deadline leaves time to react)", fmt(shortest, 1) .. " s")
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	local d = newDriver({ Mode = "Raid", Boss = "storm_titan", Seed = 7, Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = catalogTeam(3, 12) } } })
	if not d then
		T.fail("#7: battle driver")
		return
	end
	d:start()
	local tele = nil
	for _ = 1, 400 do
		local evs = d:step()
		for _, e in ipairs(evs) do
			if e.type == "Telegraph" and not tele then
				tele = e
			end
		end
		if tele then
			break
		end
	end
	if not T.check(tele ~= nil, "#7: the boss telegraphs within 40 s") then
		d:finish({ Mode = "Raid", Outcome = "Loss", Won = false, Spectator = false, Reason = "Ended", Rewards = {} })
		cleanup(BC)
		return
	end
	local list = BC.GetTelegraphs()
	local tl = nil
	for _, t in ipairs(list) do
		if t.Id == tele.id then
			tl = t
		end
	end
	if not T.check(tl ~= nil, "#7: the client draws the telegraph", #list .. " drawn") then
		return
	end
	local b = BC.GetBattle()
	local ping = 0.05
	pcall(function()
		ping = LocalPlayer:GetNetworkPing()
	end)
	local lead = tl.At - tl.SafeAt
	local want = (b.InterpDelay or 0.12) + ping + 0.8
	T.check(type(tl.SafeAt) == "number" and abs(lead - want) < 0.02,
		"#7: the fill completes at the dodge deadline: impact - (render delay + round trip + 0.8 s run-out)",
		"lead " .. fmt(lead) .. " s, want " .. fmt(want) .. " s")
	T.check(tl.SafeAt - tl.From >= 1.0 and tl.SafeAt < tl.At, "#7: ...leaving >= 1 s of fill before the deadline", fmt(tl.SafeAt - tl.From) .. " s")
	T.check(tl.Late == false, "#7: a fresh telegraph is not past its deadline")
	-- step until the render clock passes the deadline (before the impact): the shape flashes
	local sawLate, lateBeforeDeadline, threatSeen, dashCue = false, false, false, false
	local cues = {}
	for _ = 1, 40 do
		d:step()
		local bb = BC.GetBattle()
		local now = nil
		for _, t in ipairs(BC.GetTelegraphs()) do
			if t.Id == tele.id then
				now = t
			end
		end
		if not now or not bb then
			break
		end
		if now.Late then
			sawLate = true
			if bb.RenderT < now.SafeAt - 0.001 then
				lateBeforeDeadline = true
			end
		end
		if bb.Threat then
			threatSeen = true
			local db = find("Root.Commands.DashButton")
			local glow = db and db:FindFirstChild("Glow")
			cues[#cues + 1] = tostring(bb.Cue)
			if bb.Cue == "Dash" and glow and glow.BackgroundTransparency < 0.95 then
				dashCue = true
			end
		end
	end
	T.check(sawLate and not lateBeforeDeadline, "#7: past the deadline the shape flashes until the impact (never before the deadline)")
	-- a cluster slam aims at my fighter: the HUD calls DASH (dash through it) while it covers it
	T.check(threatSeen, "#7: the slam covers my fighter (Threat)")
	T.check(dashCue, "#7: ...and DASH glows (Cue Dash)", table.concat(cues, "|"))
	-- once the telegraph has hit, the cue goes away
	local cleared = false
	for _ = 1, 40 do
		d:step()
		local gone = true
		for _, t in ipairs(BC.GetTelegraphs()) do
			if t.Id == tele.id then
				gone = false
			end
		end
		if gone and BC.GetBattle() and BC.GetBattle().Cue == nil then
			cleared = true
			break
		end
	end
	T.check(cleared, "#7: after the hit the DASH cue stops")
	d:finish({ Mode = "Raid", Outcome = "Loss", Won = false, Spectator = false, Reason = "Ended", Rewards = {} })
	T.check(cleanup(BC), "#7: everything freed afterwards")
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, "#7: no errors or warnings", tostring(battleWarnings(outBefore)))
	KC.flushErrors("client_p3fixcli_telegraph")
end)

----------------------------------------------------------------------------------------------------
-- #8 retreat cues + auto resume
----------------------------------------------------------------------------------------------------
local function textFits(lbl)
	if not lbl then
		return false, "nil"
	end
	local b, s = lbl.TextBounds, lbl.AbsoluteSize
	return b.X <= s.X + 1 and b.Y <= s.Y + 1, fmt(b.X, 0) .. "x" .. fmt(b.Y, 0) .. " in " .. fmt(s.X, 0) .. "x" .. fmt(s.Y, 0)
end

S.client_p3fixcli_retreat = guarded("client_p3fixcli_retreat", function()
	local BC = moduleAt("client", "Controllers/BattleController")
	if not BC then
		T.fail("#8: modules missing")
		return
	end
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	Mock.SetViewport(1920, 1080)
	step(2)
	local d = roomDriver(14, 3)
	if not d then
		T.fail("#8: battle driver")
		return
	end
	d:start()
	for _ = 1, 10 do
		d:step()
	end
	local special = find("Root.Commands.SpecialButton")
	local fighter = BC.GetBattle() and BC.GetBattle().FighterId
	local f = nil
	for _, u in ipairs(d:myUnits()) do
		if u.id == fighter then
			f = u
		end
	end
	if not T.check(special ~= nil and f ~= nil, "#8: the SPECIAL button and my fighter") then
		return
	end
	f.meter = 20
	d:step()
	d:step()
	T.check(special:GetAttribute("Disabled") == true, "#8: SPECIAL is dim while the energy charges")
	local idx = #Mock.RemoteLog
	local shakes = special:GetAttribute("Shakes") or 0
	Mock.Click(special)
	T.check(#commandsSince(idx) == 0 and (special:GetAttribute("Shakes") or 0) > shakes, "#8: ...a press then sends nothing and shakes it")
	d.logIndex = #Mock.RemoteLog
	f.meter = 100
	d:step()
	d:step()
	step(4, 0.05)
	local ring = find("Root.Commands.SpecialButton.Ring.R.Disc")
	T.check(special:GetAttribute("Disabled") ~= true and ring and ring.BackgroundColor3.R > 0.9 and ring.BackgroundColor3.G > 0.6 and ring.BackgroundColor3.B < 0.4, "#8: at 100 SPECIAL lights up gold")
	idx = #Mock.RemoteLog
	Mock.Click(special)
	local cmds = commandsSince(idx)
	T.check(#cmds == 1 and cmds[1].action == "Special" and cmds[1].arg == nil, "#8: ...and the press sends Special", #cmds > 0 and cmds[1].action or "none")
	d:step()
	d:step()
	-- result lines of the new reward records
	d:finish({ Mode = "Dungeon", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe", Rewards = { Dungeon = true } })
	step(3)
	T.check(cleanup(BC), "#8: everything freed afterwards")
	local function resultFor(mode, payload, want, label)
		local dd = newDriver(mode == "Raid" and { Mode = "Raid", Boss = "storm_titan", Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = catalogTeam(2) } } }
			or { Mode = "Duel", Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = catalogTeam(2) }, { Owner = 78, Side = 2, Pets = catalogTeam(2) } } })
		if not dd then
			T.fail(label .. ": driver")
			return
		end
		dd:start()
		dd:step()
		payload.Mode = mode
		dd:finish(payload)
		step(3)
		local res = find("Root.ResultCard")
		local all = {}
		for _, x in ipairs(res and res:GetDescendants() or {}) do
			if (x:IsA("TextLabel") or x:IsA("TextButton")) and x.Text ~= "" then
				all[#all + 1] = x.Text
			end
		end
		local joined = table.concat(all, " | ")
		local ok = true
		for _, w in ipairs(want) do
			if not joined:find(w, 1, true) then
				ok = false
			end
		end
		T.check(ok, label, joined)
		cleanup(BC)
	end
	resultFor("Duel", { Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe", Rewards = { Practice = true, Tokens = 0, Xp = 0, Trophies = 0 } }, { "Practice duel: no rewards" }, "#0 (client): a practice duel says so (no '+0 Trophies')")
	resultFor("Raid", { Outcome = "Win", Won = true, Spectator = false, Reason = "BossDown", Rewards = { Tier = "None", Share = 0, Tokens = 0 } }, { "No hits on the boss: no reward" }, "#1 (client): a raider with no hits reads 'no reward', not 'None tier'")
	resultFor("Duel", { Outcome = "Draw", Won = false, Spectator = false, Reason = "Void", Rewards = { Void = true } }, { "does not count" }, "#3 (client): a void duel says it does not count")
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, "#8: no errors or warnings", tostring(battleWarnings(outBefore)))
	KC.flushErrors("client_p3fixcli_retreat")
end)

----------------------------------------------------------------------------------------------------
-- #9 landscape phone layout
----------------------------------------------------------------------------------------------------
local function menuTilesShown()
	local pg = playerGui()
	local menu = pg and pg:FindFirstChild("NimbusMenu")
	local column = menu and menu:FindFirstChild("MenuColumn", true)
	local n = 0
	for _, d in ipairs(column and column:GetDescendants() or {}) do
		if d:IsA("GuiButton") and d.Name:find("^MenuButton_") and shown(d) then
			n = n + 1
		end
	end
	return n, column
end

local function namedRect(guiName, path)
	local pg = playerGui()
	local cur = pg and pg:FindFirstChild(guiName)
	for name in string.gmatch(path, "[^%.]+") do
		cur = cur and cur:FindFirstChild(name)
	end
	if cur and cur:IsA("GuiObject") and shown(cur) and cur.AbsoluteSize.X > 0 then
		return screenRect(cur), cur
	end
	return nil
end

local function landscapeChecks(BC, label, pets)
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	Mock.SetViewport(844, 390)
	step(4)
	local tilesBefore = menuTilesShown()
	local d = newDriver({ Mode = "Raid", Boss = "storm_titan", Seed = 3, Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = catalogTeam(min(pets, 3), 10) } } })
	if not d then
		T.fail(label .. ": driver")
		return
	end
	d:start()
	for _ = 1, 15 do
		d:step()
	end
	KC.advance(1) -- the HUD / menu re-measure their neighbours
	local b = BC.GetBattle()
	T.check(b and b.Layout == "Compact" and b.TeamPlace == "TopLeft", label .. ": the fighter card + portraits go to the top-left edge (TeamPlace TopLeft)", b and tostring(b.TeamPlace) or "nil")
	local team = find("Root.Team")
	local tr = team and screenRect(team)
	local cx, cy = 844 / 2, 390 / 2
	T.check(tr ~= nil and not (tr.x0 <= cx and cx <= tr.x1 and tr.y0 <= cy and cy <= tr.y1) and tr.x1 < 844 * 0.3,
		label .. ": the team block keeps clear of the screen centre (left 30%)", tr and rectText(tr) or "nil")
	local tiles, column = menuTilesShown()
	T.check(tilesBefore > 0 and tiles == 0, label .. ": the menu tiles step aside during the battle", tilesBefore .. " -> " .. tiles)
	T.check(column ~= nil and shown(column) and column.AbsoluteSize.X > 0, label .. ": ...while the column frame keeps its place (the HUD measures it)")
	-- no card on the top card, the commands, the vitals, the hotbar or any other button
	local others = {}
	for _, p in ipairs({ { "NimbusBattle", "Root.TopCard" }, { "NimbusBattle", "Root.Commands.AttackButton" }, { "NimbusBattle", "Root.Commands.SpecialButton" }, { "NimbusBattle", "Root.Commands.ElementButton" }, { "NimbusBattle", "Root.Commands.DashButton" }, { "NimbusHud", "BottomLeft.Vitals" }, { "NimbusHud", "TopRight.Currency" } }) do
		local r = namedRect(p[1], p[2])
		if r then
			others[#others + 1] = { p[1] .. "." .. p[2], r }
		end
	end
	local pg = playerGui()
	for _, g in ipairs(pg and pg:GetChildren() or {}) do
		if g:IsA("ScreenGui") and g.Name ~= "NimbusBattle" and g.Enabled then
			for _, o in ipairs(g:GetDescendants()) do
				if o:IsA("GuiButton") and shown(o) and o.AbsoluteSize.X > 20 and o.AbsoluteSize.X < 300 then
					others[#others + 1] = { o:GetFullName(), screenRect(o) }
				end
			end
		end
	end
	local clash = nil
	for _, path in ipairs({ "Root.Team.Fighter", "Root.Team.Helpers.Helper1", "Root.Team.Helpers.Helper2" }) do
		local row = find(path)
		if row and shown(row) then
			local r = screenRect(row)
			for _, o in ipairs(others) do
				if overlap(r, o[2]) then
					clash = path .. " over " .. o[1]
				end
			end
		end
	end
	T.check(#others >= 4 and clash == nil, label .. ": the fighter block covers no top card, action button, vitals, hotbar or other button", tostring(clash))
	local centred = {}
	for _, c in ipairs(KC.centredTexts(0.1)) do
		if c.path:find("NimbusBattle", 1, true) then
			centred[#centred + 1] = c
		end
	end
	T.check(#centred == 0, label .. ": nothing of the battle HUD in the screen centre", KC.describeCentred(centred))
	local scale = find("Root.ReadScale")
	local f = scale and scale.Scale or 1
	local small = nil
	for _, t in ipairs(team and team:GetDescendants() or {}) do
		if (t:IsA("TextLabel") or t:IsA("TextButton")) and shown(t) and t.Text ~= "" and t.TextSize * f < 13.99 then
			small = t:GetFullName()
		end
	end
	T.check(small == nil, label .. ": team card texts stay >= 14 px", tostring(small))
	-- the SPECIAL button casts with a full energy bar
	for _, u in ipairs(d:myUnits()) do
		u.meter = 100
	end
	d:step()
	d:step()
	local idx = #Mock.RemoteLog
	local hit = find("Root.Commands.SpecialButton")
	if hit then
		Mock.Click(hit)
	end
	local cmds = commandsSince(idx)
	T.check(#cmds == 1 and cmds[1].action == "Special", label .. ": the SPECIAL button casts with a full energy bar")
	-- the result card hides the team: the tiles come back
	d:finish({ Mode = "Raid", Outcome = "Win", Won = true, Spectator = false, Reason = "BossDown", Rewards = { Tier = "Gold", Share = 0.5, Tokens = 50 } })
	step(4)
	T.check(menuTilesShown() == tilesBefore, label .. ": the menu tiles are back with the result card", menuTilesShown() .. "/" .. tilesBefore)
	cleanup(BC)
	-- a portrait phone: the fighter block at the top left too, the menu tiles step aside (contract 4.7)
	Mock.SetViewport(390, 844)
	step(4)
	local d2 = roomDriver(10, 2)
	if d2 then
		d2:start()
		for _ = 1, 8 do
			d2:step()
		end
		b = BC.GetBattle()
		T.check(b and b.TeamPlace == "TopLeft" and menuTilesShown() == 0, label .. ": portrait keeps the fighter block top left, the menu tiles step aside", b and tostring(b.TeamPlace) or "nil")
		d2:finish({ Mode = "Dungeon", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe", Rewards = { Dungeon = true } })
		cleanup(BC)
	end
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, label .. ": no errors or warnings", tostring(battleWarnings(outBefore)))
end

-- Phase 4: between two Champion Ring rounds on an 844x390 screen the side card "Round n won! ... Round n+1 in 3" sits
-- at the right edge (where the commands were), off the screen centre, over no button, team card, vitals or hotbar;
-- the team grid keeps the left edge (the menu tiles stay aside) until the run's result card
local function ringLandscape(BC, label)
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	local BCat = moduleAt("shared", "BattleCatalog")
	if not (BCat and type(BCat.ChampionTeam) == "function") then
		T.fail(label .. ": BattleCatalog.ChampionTeam missing")
		return
	end
	Mock.SetViewport(844, 390)
	step(4)
	local tilesBefore = menuTilesShown()
	local spec = BCat.ChampionTeam(6, 3)
	local ch = spec.Champion or {}
	local d = newDriver({ Mode = "Ring", Round = 6, Zone = { X = 44, Z = 44 }, TimeLimit = 90, Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = catalogTeam(3, 30) }, spec },
		Ring = { Round = 6, Best = 9, Start = 1, Champion = { PetId = ch.PetId, Level = ch.Level, Tier = ch.Tier, Boss = ch.Boss == true, Name = ch.Name } } })
	if not d then
		T.fail(label .. ": ring driver")
		return
	end
	d:start()
	for _ = 1, 8 do
		d:step()
	end
	KC.toClient("BattleState", "End", { BattleId = d.id, Mode = "Ring", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
		Rewards = { Won = true, Next = 7, Round = 6, Cash = 32, Xp = 56, Tokens = 0, Record = false } }, d.id)
	step(4)
	local b = BC.GetBattle()
	local nr, nc = namedRect("NimbusBattle", "Root.NextRoundCard")
	T.check(b and b.Next == 7 and nr ~= nil and b.TeamPlace == "TopLeft" and menuTilesShown() == 0, label .. ": between rounds the side card shows, the fighter block keeps the left edge, the tiles stay aside",
		b and (tostring(b.Next) .. " " .. tostring(b.TeamPlace)) or "nil")
	if nr then
		local cx, cy = 844 / 2, 390 / 2
		T.check(not (nr.x0 <= cx and cx <= nr.x1 and nr.y0 <= cy and cy <= nr.y1) and nr.x1 <= 845 and nr.y0 >= 0, label .. ": the side card stays off the screen centre and on the screen", rectText(nr))
		local others = {}
		for _, p in ipairs({ { "NimbusBattle", "Root.TopCard" }, { "NimbusBattle", "Root.Team.Fighter" }, { "NimbusBattle", "Root.Team.Helpers" }, { "NimbusHud", "BottomLeft.Vitals" }, { "NimbusHud", "TopRight.Currency" } }) do
			local r = namedRect(p[1], p[2])
			if r then
				others[#others + 1] = { p[1] .. "." .. p[2], r }
			end
		end
		local pg = playerGui()
		for _, g in ipairs(pg and pg:GetChildren() or {}) do
			if g:IsA("ScreenGui") and g.Name ~= "NimbusBattle" and g.Enabled then
				for _, o in ipairs(g:GetDescendants()) do
					if o:IsA("GuiButton") and shown(o) and o.AbsoluteSize.X > 20 and o.AbsoluteSize.X < 300 then
						others[#others + 1] = { o:GetFullName(), screenRect(o) }
					end
				end
			end
		end
		local clash = nil
		for _, o in ipairs(others) do
			if overlap(nr, o[2]) then
				clash = o[1]
			end
		end
		T.check(#others >= 3 and clash == nil, label .. ": the side card covers no button, team card, vitals, hotbar or currency pill", tostring(clash))
		local scale = nc and nc:FindFirstAncestorOfClass("ScreenGui") and nc:FindFirstAncestorOfClass("ScreenGui"):FindFirstChild("ReadScale", true)
		local f = scale and scale.Scale or 1
		local small = nil
		for _, t in ipairs(nc:GetDescendants()) do
			if (t:IsA("TextLabel") or t:IsA("TextButton")) and shown(t) and t.Text ~= "" and t.TextSize * f < 13.99 then
				small = t.Name .. " " .. fmt(t.TextSize * f)
			end
		end
		T.check(small == nil, label .. ": the side card's texts stay >= 14 px", tostring(small))
	end
	KC.toClient("BattleState", "End", { BattleId = d.id, Mode = "Ring", Outcome = "Left", Won = false, Spectator = false, Reason = "Forfeit", Round = 6,
		Rewards = { Won = false, Final = true, Round = 6, Cash = 0, Xp = 0, Run = { Wins = 6, Cash = 210, Xp = 216, Tokens = 0, Round = 6, Start = 1, Best = 9 } } }, d.id)
	step(4)
	T.check(not shown(BC and find("Root.NextRoundCard")) and shown(find("Root.ResultCard")) and menuTilesShown() == tilesBefore, label .. ": the run's card replaces the side card and the menu tiles come back",
		menuTilesShown() .. "/" .. tilesBefore)
	cleanup(BC)
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, label .. ": no errors or warnings (ring)", tostring(battleWarnings(outBefore)))
end

S.client_p3fixcli_landscape = guarded("client_p3fixcli_landscape", function()
	local BC = moduleAt("client", "Controllers/BattleController")
	local Menu = moduleAt("client", "Controllers/MenuController")
	if not (BC and Menu and type(Menu.SetColumnHidden) == "function") then
		T.fail("#9: BattleController / MenuController.SetColumnHidden missing")
		return
	end
	landscapeChecks(BC, "#9 844x390 window", 3)
	ringLandscape(BC, "#9 844x390 window, Champion Ring")
	-- a wide screen: the fighter card top left, the menu tiles stay
	Mock.SetViewport(1920, 1080)
	step(4)
	local d = roomDriver(10, 2)
	if d then
		d:start()
		for _ = 1, 8 do
			d:step()
		end
		local b = BC.GetBattle()
		T.check(b and b.Layout == "Wide" and b.TeamPlace == "TopLeft" and menuTilesShown() > 0, "#9: 1920x1080: the fighter card top left, the menu tiles stay", b and tostring(b.TeamPlace) or "nil")
		-- ...and the fighter card + portraits start right of the tile column (no portrait under a tile)
		local _, column = menuTilesShown()
		local covered = nil
		for _, path in ipairs({ "Root.Team.Fighter", "Root.Team.Helpers.Helper1", "Root.Team.Helpers.Helper2" }) do
			local r = namedRect("NimbusBattle", path)
			for _, t in ipairs(column and column:GetDescendants() or {}) do
				if r and t:IsA("GuiButton") and t.Name:find("^MenuButton_") and shown(t) and overlap(r, screenRect(t)) then
					covered = path .. " over " .. t.Name
				end
			end
		end
		T.check(covered == nil, "#9: 1920x1080: the fighter card and portraits cover no menu tile", tostring(covered))
		d:finish({ Mode = "Dungeon", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe", Rewards = { Dungeon = true } })
		cleanup(BC)
	end
	Mock.SetViewport(1920, 1080)
	step(4)
	KC.flushErrors("client_p3fixcli_landscape")
end)

S.client_p3fixcli_mobile = guarded("client_p3fixcli_mobile", function()
	ensureClient()
	local BC = moduleAt("client", "Controllers/BattleController")
	if not BC then
		T.fail("#9 phone: BattleController missing")
		return
	end
	landscapeChecks(BC, "#9 phone 844x390 (touch)", 3)
	landscapeChecks(BC, "#9 phone 844x390, a 1-pet team", 1)
	ringLandscape(BC, "#9 phone 844x390 (touch), Champion Ring")
	Mock.SetViewport(390, 844)
	step(4)
	KC.flushErrors("client_p3fixcli_mobile")
end)

----------------------------------------------------------------------------------------------------
-- extra: /devhelp toasts on a landscape phone
----------------------------------------------------------------------------------------------------
S.client_p3fixcli_devhelp = guarded("client_p3fixcli_devhelp", function()
	local texts = {
		"DEV: /pet <name> [0-2]  /pets [0-2]  /evolve <name|all> [1-2]  /clearpets",
		"DEV: /allpets /tokens N /cash N /gems N /reset /tutorial /skiptutorial /raid /devhelp",
	}
	local pg = playerGui()
	local function visible(t)
		local notify = pg and pg:FindFirstChild("NimbusNotify")
		for _, d in ipairs(notify and notify:GetDescendants() or {}) do
			if d:IsA("TextLabel") and d.Name == "Text" and d.Text == t and shown(d) and d.TextTransparency < 0.5 then
				return d
			end
		end
		return nil
	end
	for _, size in ipairs({ { 844, 390 }, { 1920, 1080 } }) do
		Mock.SetViewport(size[1], size[2])
		KC.advance(1)
		for _, t in ipairs(texts) do
			KC.toClient("Notify", t, "info", 8)
		end
		local seen, at = {}, {}
		for i = 1, 40 do
			KC.advance(0.5)
			for j, t in ipairs(texts) do
				local lbl = visible(t)
				if lbl and not seen[j] then
					local b, s = lbl.TextBounds, lbl.AbsoluteSize
					local c = lbl.AbsolutePosition.X + s.X / 2
					seen[j] = { fits = b.X <= s.X + 1 and b.Y <= s.Y + 1, right = c > size[1] * 0.6, px = lbl.TextSize * ((lbl.Parent and lbl:FindFirstAncestorOfClass("Frame")) and 1 or 1) }
					at[j] = i * 0.5
				end
			end
		end
		local label = size[1] .. "x" .. size[2]
		for j = 1, 2 do
			T.check(seen[j] ~= nil and seen[j].fits and seen[j].right, "devhelp " .. label .. ": help toast " .. j .. " is shown whole at the right edge", seen[j] and ("at " .. fmt(at[j], 1) .. " s") or "never")
		end
		KC.advance(10)
	end
	KC.flushErrors("client_p3fixcli_devhelp")
end)

----------------------------------------------------------------------------------------------------
-- extra: the tutorial card never covers the vitals / hotbar; it hides behind compact battle cards
----------------------------------------------------------------------------------------------------
local function tutorialPayload(step)
	local Steps = moduleAt("shared", "TutorialSteps")
	local list = Steps and Steps.Steps or {}
	local index = max(1, min(#list, step))
	local s = list[index] or {}
	return {
		Step = index, Total = #list, Id = s.Id, Title = s.Title, Text = tostring(s.Text or ""):gsub("{%w+}", "20"), Target = s.Target,
		CompleteOn = s.CompleteOn, Hint = s.Hint, Button = s.Button, Gift = false,
		Done = false, Completed = false, Skipped = false, Reward = 0,
	}
end

S.client_p3fixcli_tutorial = guarded("client_p3fixcli_tutorial", function()
	local TC = moduleAt("client", "Controllers/TutorialController")
	local BC = moduleAt("client", "Controllers/BattleController")
	local pg = playerGui()
	local tut = pg and pg:FindFirstChild("NimbusTutorial")
	if not (TC and BC and tut) then
		T.fail("tutorial: TutorialController / NimbusTutorial missing")
		return
	end
	local saved = TC.GetState()
	local function card()
		local main = tut:FindFirstChild("Main", true)
		if main and shown(main) and main.AbsoluteSize.X > 0 then
			return screenRect(main)
		end
		return nil
	end
	local function toggle()
		local t = tut:FindFirstChild("Toggle", true)
		if t then
			Mock.Click(t)
		end
	end
	local Steps = moduleAt("shared", "TutorialSteps")
	local trialStep = 1
	for i, s in ipairs(Steps and Steps.Steps or {}) do
		if s.Id == "trial" then
			trialStep = i
		end
	end
	local checked = 0
	for _, party in ipairs({ false, true }) do
		for _, size in ipairs({ { 844, 390 }, { 1280, 720 }, { 1024, 600 }, { 390, 844 } }) do
			Mock.SetViewport(size[1], size[2])
			if party then
				KC.toClient("PartyState", { PortalId = "Medium", DifficultyName = "Medium", Color = Color3.fromRGB(255, 190, 80),
					Players = { { UserId = LocalPlayer.UserId, Name = LocalPlayer.Name }, { UserId = 77, Name = "Buddy" } }, Max = 4, Countdown = 30 })
			end
			KC.toClient("TutorialState", tutorialPayload(3))
			KC.advance(2)
			if not card() then
				toggle() -- open the folded card (the player asks for it)
				KC.advance(1.5)
			end
			local r = card()
			local label = size[1] .. "x" .. size[2] .. (party and " + party panel" or "")
			if not party then
				-- the plain lobby: the card the player asks for opens (it may lie over the idle vitals card there)
				T.check(r ~= nil, "tutorial " .. label .. ": the card opens in the plain lobby")
			elseif r then
				checked = checked + 1
				local hits = {}
				for _, p in ipairs({ { "NimbusHud", "BottomLeft.Vitals" } }) do
					local o = namedRect(p[1], p[2])
					if o and overlap(r, o) then
						hits[#hits + 1] = p[2] .. " " .. rectText(o)
					end
				end
				T.check(#hits == 0, "tutorial " .. label .. ": the opened card covers neither the vitals nor the hotbar", rectText(r) .. " " .. table.concat(hits, "; "))
			else
				T.info("*tutorial " .. label .. ": no room for the card here: the bubble stays")
			end
			if party then
				KC.toClient("PartyState", nil)
			end
			KC.advance(1)
		end
	end
	T.check(checked >= 2, "tutorial: with a party panel up the card still opens where there is room", checked .. " of 4")
	-- a battle on a phone-sized screen: compact cards at the top / left, Nimbus waits
	for _, size in ipairs({ { 844, 390 }, { 390, 844 } }) do
		Mock.SetViewport(size[1], size[2])
		KC.toClient("TutorialState", tutorialPayload(trialStep))
		KC.advance(2)
		local d = roomDriver(10, 2)
		if d then
			d:start()
			for _ = 1, 12 do
				d:step()
			end
			KC.advance(0.6)
			local root = tut:FindFirstChild("Root") or tut:FindFirstChildWhichIsA("Frame")
			local anyShown = false
			for _, x in ipairs(tut:GetDescendants()) do
				if (x:IsA("TextLabel") or x:IsA("ImageLabel") or x:IsA("ViewportFrame")) and shown(x) and x.AbsoluteSize.X > 0 then
					local rr = screenRect(x)
					if rr.x1 > 0 and rr.x0 < size[1] then
						anyShown = true
					end
				end
			end
			T.check(not anyShown, "tutorial " .. size[1] .. "x" .. size[2] .. ": the panel hides while compact battle cards hold the screen", tostring(root))
			d:finish({ Mode = "Dungeon", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe", Rewards = { Dungeon = true } })
			step(3)
			BC.GetBattle()
			cleanup(BC)
			KC.advance(1.5)
			local back = false
			for _, x in ipairs(tut:GetDescendants()) do
				if x:IsA("ViewportFrame") and shown(x) then
					back = true
				end
			end
			T.check(back, "tutorial " .. size[1] .. "x" .. size[2] .. ": Nimbus is back after the battle")
		end
	end
	-- restore
	if saved then
		KC.toClient("TutorialState", saved)
	else
		local p = tutorialPayload(1)
		p.Done = true
		KC.toClient("TutorialState", p)
	end
	Mock.SetViewport(1920, 1080)
	KC.advance(2)
	KC.flushErrors("client_p3fixcli_tutorial")
end)

return S
