-- smoke_dgfix_client.lua: the dungeon fixes, client half (docs/dungeon-fixes/plan.md decisions 1, 3, 4, 5 and the E rule
-- of 6; owner: battle-client). Loaded by tools/smoke.py in the client world (desktop 1920x1080). A real BattleSim is
-- stepped at 10 Hz and sent the way BattleService sends it, in SERVER order: "Start" first (a dungeon room opens with
-- NO enemies), the enemies in a later Wave event (BattleService.SpawnWave); the client's BattleCommand calls are
-- forwarded into the sim.
--   client_dgfix_waves    server order draws every enemy: a dungeon room's wave 1 after Start, wave 2, a boss room's
--                         mini-boss + its escort (rows, models, Wild look on the wild ones); a Champion Ring round's
--                         champion (in Start) and a second ring round; a Boss Raid's boss + a raider who joins later
--                         (a Spawn event)
--   client_dgfix_arrive   a Wave unit with Arrive > 0 plays EvolutionFx.Arrive at its spot, its model stays out of the
--                         world until the flash and then pops in with a hop; a wave of 5 stays within the kit cap; the
--                         effects are cleaned up (kits pooled, nothing live, no part left visible); GraphicsQuality Low:
--                         only the flash + the shock ring (<= 13 parts each)
--   client_dgfix_attack   F / the ATTACK button / a click send ONE "Attack" order (nil = nearest / next; a click on an
--                         enemy = its id; with the mouse locked the enemy under the screen centre), holding repeats
--                         nothing, no predicted swing, the arrow marks the enemy the pet attacks (picked = solid, its
--                         own pick = see-through), the ATTACK caption "ATTACK" (bug #16; a tap of F, the hold-to-cycle
--                         is pinned by smoke_fight.lua client_fight_attack)
--   client_dgfix_dash     Shift / RightShift in a battle send "Dash" only: no character velocity, no stamina change, no
--                         character dash cooldown; RUN on Ctrl; the DASH button sends the same; the Dash event draws my
--                         OWN pet's dash (out and back) and another pet's; after the battle Shift runs and Q dashes
--   client_dgfix_prompt   E passes through (ContextActionResult.Pass, no "Element") while a ProximityPrompt is shown
--                         to me, and fires ELEMENT again once it is hidden / gone; gamepad Y always fires ELEMENT;
--                         MouseLock holds "BattleResult" while the result card shows and "BattleLeave" while the ring's
--                         LEAVE asks "Sure? Tap again" (released afterwards)
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local KC = _G.KC
local S = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local abs, floor, max = math.abs, math.floor, math.max

local H = {}

function H.fmt(v, n)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return string.format("%." .. (n or 2) .. "f", v)
end

function H.moduleAt(top, rest)
	local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	return ok and type(result) == "table" and result or nil
end

function H.step(n, dt)
	for _ = 1, n or 1 do
		Mock.Step(dt)
	end
end

function H.gui()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	return pg and pg:FindFirstChild("NimbusBattle")
end

function H.find(path)
	local cur = H.gui()
	for name in string.gmatch(path, "[^%.]+") do
		if not cur then
			return nil
		end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

function H.shown(obj)
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

function H.commands(index)
	local out = {}
	for _, e in ipairs(KC.serverCalls("BattleCommand", index)) do
		out[#out + 1] = { action = e.args[1], arg = e.args[2] }
	end
	return out
end

function H.count(index, action)
	local n = 0
	for _, c in ipairs(H.commands(index)) do
		if c.action == action then
			n = n + 1
		end
	end
	return n
end

function H.warnings(fromIndex)
	for i = fromIndex + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and (o.text:find("BattleController", 1, true) or o.text:find("EvolutionFx", 1, true) or o.text:find("MovementController", 1, true)) then
			return o.text
		end
	end
	return nil
end

function H.rows()
	local n = 0
	for i = 1, 12 do
		if H.shown(H.find("Root.Enemies.Row" .. i)) then
			n = n + 1
		end
	end
	return n
end

-- combat pets of the catalog with different specials (skipping `skip`)
function H.team(count, skip, level)
	local PC = H.moduleAt("shared", "PetCatalog")
	local out, kinds = {}, {}
	skip = skip or 0
	for _, def in ipairs(PC and PC.Pets or {}) do
		local sp = type(def.Special) == "table" and def.Special.Kind or nil
		if sp and def.Role == "Combat" and not kinds[sp] and def.Rarity ~= "Secret" and not def.EventOnly then
			if skip > 0 then
				skip = skip - 1
			else
				kinds[sp] = true
				out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = level or 12, Tier = "Normal", Slot = #out + 1 }
				if #out >= count then
					break
				end
			end
		end
	end
	return out
end

function H.wild(n, skip, level, boss)
	local wave = H.team(n, skip or 3, level or 10)
	for _, p in ipairs(wave) do
		p.Slot = nil
		p.Wild = true
	end
	if boss and wave[1] then
		wave[1].Boss = true
	end
	return wave
end

----------------------------------------------------------------------------------------------------
-- the driver (server order): Start, then SpawnEnemies (the Wave event goes out with the next step)
----------------------------------------------------------------------------------------------------
local Driver = {}
Driver.__index = Driver

function H.driver(opts)
	local Sim = H.moduleAt("shared", "BattleSim")
	if not Sim then
		return nil, "shared/BattleSim.lua missing"
	end
	local id = "dgfix_" .. tostring(opts.Mode) .. "_" .. tostring(math.random(100000, 999999))
	local sim, why = Sim.new({ Mode = opts.Mode, Seed = opts.Seed or 9, Id = id, Teams = opts.Teams, Boss = opts.Boss, Round = opts.Round,
		Zone = { X = 44, Z = 44 }, TimeLimit = opts.TimeLimit or 120 })
	if not sim then
		return nil, why
	end
	local d = setmetatable({ sim = sim, id = id, zoneCF = CFrame.new(0, 200, 0), logIndex = #Mock.RemoteLog, opts = opts, me = LocalPlayer.UserId }, Driver)
	return d
end

function Driver:startPayload()
	local p = self.sim:Describe()
	p.BattleId = self.id
	p.Zone = { CFrame = self.zoneCF, Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
	p.Names = { [tostring(self.me)] = LocalPlayer.Name, ["77"] = "Buddy" }
	p.Side = 1
	p.Spectator = false
	p.T = self.sim:Time()
	p.Ring = self.opts.Ring
	p.Dungeon = self.opts.Dungeon
	local team = self.sim:TeamOf(self.me)
	if team then
		p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
			Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = {} } }
	end
	return p
end

function Driver:start()
	LocalPlayer:SetAttribute("InBattle", self.id)
	KC.toClient("BattleState", "Start", self:startPayload(), self.id)
end

-- BattleService.SpawnWave: the wave after Start (opts.Arrive forces Arrive = n in the event's infos when the sim does
-- not send it yet)
function Driver:spawn(list, index, arrive)
	self.arrive = arrive
	return self.sim:SpawnEnemies(list, { Wave = index, Anchor = { 0, 10 } })
end

function Driver:forward()
	if self.noForward then
		self.logIndex = #Mock.RemoteLog
		return
	end
	for _, c in ipairs(H.commands(self.logIndex)) do
		pcall(self.sim.Command, self.sim, self.me, c.action, c.arg)
	end
	self.logIndex = #Mock.RemoteLog
end

function Driver:step(fps)
	self:forward()
	local evs = self.sim:Step(0.1)
	if #evs > 0 then
		for _, e in ipairs(evs) do
			if (e.type == "Wave" or e.type == "Spawn") and self.arrive and type(e.units) == "table" then
				for _, info in ipairs(e.units) do
					if info.side ~= 1 and info.Arrive == nil then
						info.Arrive = self.arrive
					end
				end
			end
		end
		KC.toClient("BattleState", "Events", evs, self.id)
	end
	self.last = self.last or {}
	local snap = self.sim:SnapshotDelta(self.last)
	snap.BattleId = self.id
	KC.toClient("BattleState", "Snapshot", snap, self.id)
	local frames = max(1, floor((fps or 30) * 0.1 + 0.5))
	H.step(frames, 0.1 / frames)
	return evs
end

function Driver:run(seconds, fps)
	for _ = 1, floor(seconds / 0.1 + 0.5) do
		self:step(fps)
		if self.sim:IsFinished() then
			break
		end
	end
end

function Driver:unit(id)
	for _, u in ipairs(self.sim.units or {}) do
		if u.id == id then
			return u
		end
	end
	return nil
end

function Driver:enemyIds()
	local out = {}
	for _, u in ipairs(self.sim.units or {}) do
		if u.side ~= 1 and u.alive and not u.gone then
			out[#out + 1] = u.id
		end
	end
	table.sort(out)
	return out
end

function Driver:finish(payload)
	payload = payload or {}
	payload.BattleId = self.id
	KC.toClient("BattleState", "End", payload, self.id)
end

-- the enemies of `ids` that have a model in the world
function H.drawn(BC, ids)
	local n = 0
	for _, id in ipairs(ids) do
		local gu = BC.GetUnit(id)
		if gu and gu.Model and gu.Model.Parent and not gu.Hidden then
			n = n + 1
		end
	end
	return n
end

function H.dungeon(extra)
	local opts = { Mode = "Dungeon", Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = H.team(3, 0, 14) } },
		Dungeon = { Floor = 2, Room = 1, Wave = 1, Waves = 3, Name = "Ember Hall", Element = "Flame" } }
	for k, v in pairs(extra or {}) do
		opts[k] = v
	end
	return H.driver(opts)
end

function H.cleanup(BC, d)
	if d and BC.GetBattle() then
		d:finish({ Mode = d.opts.Mode, Outcome = "Left", Won = false, Spectator = false, Reason = "Left" })
	end
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(15)
	local r = H.find("Root.ResultCard.Body.OkButton")
	if r and H.shown(r) then
		Mock.Click(r)
	end
	Mock.Step(0.1)
end

function H.load()
	local BC = H.moduleAt("client", "Controllers/BattleController")
	T.check(BC ~= nil, "dgfix: client/Controllers/BattleController.lua loads")
	return BC
end

----------------------------------------------------------------------------------------------------
-- client_dgfix_waves
----------------------------------------------------------------------------------------------------
S.client_dgfix_waves = guarded("client_dgfix_waves", function()
	local BC = H.load()
	if not BC then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	-- a dungeon room: Start has no enemies, wave 1 comes in a Wave event
	local d = H.dungeon()
	if not T.check(d ~= nil, "dgfix waves: a dungeon room driver") then
		return
	end
	d:start()
	d:step(30)
	local b = BC.GetBattle()
	T.check(b and b.Fighter and #d:enemyIds() == 0 and H.rows() == 0, "dgfix waves: the room opens with no enemies (server order)")
	d:spawn(H.wild(3), 1)
	d:run(1.6, 30)
	local ids = d:enemyIds()
	T.check(#ids == 3 and H.rows() == 3 and H.drawn(BC, ids) == 3, "dgfix waves: wave 1's Wave event draws all 3 enemies (rows + models)",
		#ids .. " enemies, " .. H.rows() .. " rows, " .. H.drawn(BC, ids) .. " drawn")
	local gu = BC.GetUnit(ids[1])
	T.check(gu and gu.Wild and gu.Model and gu.Model:GetAttribute("PB_Wild") == true, "dgfix waves: a wild enemy wears the Wild look (PB_Wild)")
	T.check(gu and gu.Detail == "Low", "dgfix waves: enemies are built Low", gu and tostring(gu.Detail) or "nil")
	-- wave 2 while wave 1 still stands (Waves {2, 2, 3}: the next wave arrives the same way)
	d:spawn(H.wild(2, 5), 2)
	d:run(1.6, 30)
	ids = d:enemyIds()
	T.check(#ids == 5 and H.drawn(BC, ids) == 5 and BC.GetBattle().Wave == 2, "dgfix waves: wave 2 is drawn too (5 on the floor, Wave 2)",
		#ids .. " / " .. H.drawn(BC, ids) .. " / wave " .. tostring(BC.GetBattle().Wave))
	H.cleanup(BC, d)
	-- the boss room: the mini-boss, then its escort
	d = H.dungeon({ Dungeon = { Floor = 2, Room = 4, Wave = 1, Waves = 2, Name = "Ember Hall", Element = "Flame", Boss = true } })
	d:start()
	d:step(30)
	d:spawn(H.wild(1, 3, 14, true), 1)
	d:run(1.6, 30)
	local bossIds = d:enemyIds()
	T.check(#bossIds == 1 and H.drawn(BC, bossIds) == 1, "dgfix waves: the boss room's mini-boss is drawn", #bossIds .. " / " .. H.drawn(BC, bossIds))
	T.check(H.shown(H.find("Root.TopCard.BossBar")), "dgfix waves: ... with the boss bar")
	d:spawn(H.wild(2, 6), 2)
	d:run(1.6, 30)
	ids = d:enemyIds()
	T.check(#ids == 3 and H.drawn(BC, ids) == 3 and H.rows() == 3, "dgfix waves: the escort arrives and is drawn next to the boss", #ids .. " / " .. H.drawn(BC, ids))
	H.cleanup(BC, d)
	-- a Champion Ring round (the champion is in Start), then the next round in the same pocket
	local BCat = H.moduleAt("shared", "BattleCatalog")
	if BCat and type(BCat.ChampionTeam) == "function" then
		for round = 1, 2 do
			local spec = BCat.ChampionTeam(round, 7)
			local ch = spec.Champion or {}
			local rd = H.driver({ Mode = "Ring", Round = round, Seed = round, TimeLimit = 90,
				Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = H.team(3, 0, 30) }, spec },
				Ring = { Round = round, Best = 0, Start = 1, Champion = { PetId = ch.PetId, Level = ch.Level, Tier = ch.Tier, Boss = ch.Boss == true, Name = ch.Name } } })
			if T.check(rd ~= nil, "dgfix waves: ring round " .. round .. " driver") then
				rd:start()
				rd:run(0.8, 30)
				local rids = rd:enemyIds()
				T.check(#rids >= 1 and H.drawn(BC, rids) == #rids and H.rows() == #rids, "dgfix waves: ring round " .. round .. ": the champion is drawn", #rids .. " / " .. H.drawn(BC, rids))
				H.cleanup(BC, rd)
			end
		end
	end
	-- a Boss Raid: the boss in Start, a raider who joins later arrives in a Spawn event
	local rr = H.driver({ Mode = "Raid", Boss = "storm_titan", Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = H.team(3, 0, 20) } } })
	if T.check(rr ~= nil, "dgfix waves: a raid driver") then
		rr:start()
		rr:run(0.6, 30)
		local raidIds = rr:enemyIds()
		local bossDrawn = false
		for _, id in ipairs(raidIds) do
			local u = BC.GetUnit(id)
			if u and u.Kind == "Boss" and u.Model and u.Model.Parent then
				bossDrawn = true
			end
		end
		T.check(bossDrawn, "dgfix waves: the raid boss is drawn")
		local before = BC.GetBattle().Units
		rr.sim:AddTeam({ Owner = 77, Side = 1, Name = "Buddy", Auto = true, Pets = H.team(3, 3, 20) })
		rr:run(0.8, 30)
		local after = BC.GetBattle().Units
		local buddy = nil
		for _, u in ipairs(rr.sim.units) do
			if u.team and u.team.owner == 77 and u.slot == 1 then
				buddy = u
			end
		end
		local bu = buddy and BC.GetUnit(buddy.id)
		T.check(after >= before + 1 and bu and bu.Model and bu.Model.Parent, "dgfix waves: a raider who joins later (Spawn event) is drawn", before .. " -> " .. after .. " units")
		H.cleanup(BC, rr)
	end
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "dgfix waves: no errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_dgfix_waves")
end)

----------------------------------------------------------------------------------------------------
-- client_dgfix_arrive
----------------------------------------------------------------------------------------------------
S.client_dgfix_arrive = guarded("client_dgfix_arrive", function()
	local BC = H.load()
	local Fx = H.moduleAt("client", "Controllers/EvolutionFx")
	if not BC or not T.check(Fx ~= nil and type(Fx.Arrive) == "function", "dgfix arrive: EvolutionFx.Arrive exists") then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local BCat = H.moduleAt("shared", "BattleCatalog")
	local arrive = (BCat and BCat.Fighter and tonumber(BCat.Fighter.ArriveSeconds)) or 1.2
	T.check(abs(arrive - 1.2) < 0.01, "dgfix arrive: BattleCatalog.Fighter.ArriveSeconds is 1.2 (else 1.2 is assumed)", tostring(BCat and BCat.Fighter and BCat.Fighter.ArriveSeconds))
	local d = H.dungeon()
	d:start()
	d:step(30)
	local stats0 = BC.GetStats().Arrivals
	d:spawn(H.wild(3), 1, arrive)
	d:step(30) -- the Wave event arrives (played on the render clock a little later)
	local ids = d:enemyIds()
	local hiddenSeen, liveSeen, peakParts = 0, 0, 0
	local shownAt = {}
	local t = 0
	for _ = 1, 16 do
		d:step(30)
		t = t + 0.1
		local st = Fx.ArriveStats()
		liveSeen = max(liveSeen, st.Live + st.LiveLow)
		peakParts = max(peakParts, st.Parts)
		for _, id in ipairs(ids) do
			local gu = BC.GetUnit(id)
			if gu and gu.Hidden then
				hiddenSeen = hiddenSeen + 1
			elseif gu and gu.Model and gu.Model.Parent and not shownAt[id] then
				shownAt[id] = t
			end
		end
	end
	T.check(BC.GetStats().Arrivals - stats0 == 3 and liveSeen == 3, "dgfix arrive: one arrival effect per arriving enemy (EvolutionFx.Arrive)",
		(BC.GetStats().Arrivals - stats0) .. " started, " .. liveSeen .. " live at once")
	T.check(hiddenSeen > 0, "dgfix arrive: the model stays out of the world until the flash", hiddenSeen .. " hidden frames")
	local allShown = true
	for _, id in ipairs(ids) do
		if not shownAt[id] then
			allShown = false
		end
	end
	T.check(allShown and H.drawn(BC, ids) == 3, "dgfix arrive: ... then every model pops in", tostring(allShown))
	T.check(peakParts > 13 and peakParts <= 3 * 45, "dgfix arrive: the full effect (rune ring, pillar, flash, shock ring, sparks) stays small", peakParts .. " parts for 3")
	local st = Fx.ArriveStats()
	T.check(st.Live == 0 and st.LiveLow == 0 and st.Parts == 0 and st.Pooled >= 3, "dgfix arrive: the effects end and their kits go back to the pool",
		st.Live .. " live, " .. st.Pooled .. " pooled")
	-- nothing of an ended arrival is left visible
	local visible = 0
	local holder = workspace:FindFirstChild("ClientBattle")
	for _, p in ipairs(holder and holder:GetDescendants() or {}) do
		if p:IsA("BasePart") and p.Name:sub(1, 6) == "Arrive" and p.Transparency < 1 then
			visible = visible + 1
		end
	end
	T.eq(visible, 0, "dgfix arrive: no arrival part is left visible")
	-- a wave of 5 at once
	d:spawn(H.wild(5, 4), 2, arrive)
	local maxLive, maxFull = 0, 0
	for _ = 1, 16 do
		d:step(30)
		local s2 = Fx.ArriveStats()
		maxLive = max(maxLive, s2.Live + s2.LiveLow)
		maxFull = max(maxFull, s2.Live)
	end
	T.check(maxLive == 5 and maxFull <= 6, "dgfix arrive: a wave of 5 arrives at once within the cap of 6 full effects", maxLive .. " live, " .. maxFull .. " full")
	H.cleanup(BC, d)
	-- GraphicsQuality Low: the flash + the ring only
	local GQ = H.moduleAt("client", "GraphicsQuality")
	if GQ and type(GQ.Apply) == "function" then
		GQ.Apply("Low")
		local h = Fx.Arrive(CFrame.new(0, 205, 0), { Height = 3, Radius = 1.8, Parent = workspace })
		local s3 = Fx.ArriveStats()
		T.check(h.Low == true and s3.LiveLow == 1 and s3.Parts <= 13, "dgfix arrive: Low graphics = the flash + the shock ring (cheap)", s3.Parts .. " parts")
		local flashed = false
		for _ = 1, 50 do
			Mock.Step(1 / 30)
			if h.Flashed then
				flashed = true
			end
		end
		T.check(flashed and h.Done and Fx.ArriveStats().LiveLow == 0, "dgfix arrive: ... it flashes and ends in about 1.2 s")
		GQ.Apply("High")
	else
		T.info("dgfix arrive: no GraphicsQuality module (the Low case was skipped)")
	end
	-- Stop: ends at once and still runs OnFlash once (the pet appears)
	local calls = 0
	local h = Fx.Arrive(CFrame.new(0, 205, 0), { Quality = "High", OnFlash = function()
		calls = calls + 1
	end })
	h.Stop()
	h.Stop()
	T.check(h.Done and calls == 1 and Fx.ArriveStats().Live == 0, "dgfix arrive: Stop ends it at once, OnFlash runs exactly once", calls .. " calls")
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "dgfix arrive: no errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_dgfix_arrive")
end)

----------------------------------------------------------------------------------------------------
-- client_dgfix_attack
----------------------------------------------------------------------------------------------------
S.client_dgfix_attack = guarded("client_dgfix_attack", function()
	local BC = H.load()
	if not BC then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local d = H.dungeon()
	d:start()
	d:step(30)
	d:spawn(H.wild(3), 1)
	d:run(1.6, 30)
	local ids = d:enemyIds()
	local function isEnemy(id)
		for _, e in ipairs(ids) do
			if e == id then
				return true
			end
		end
		return false
	end
	local simF = d:unit(BC.GetBattle().FighterId)
	if simF and simF.target and simF.target.alive then
		local fo = BC.GetStats().Focus
		T.check(fo ~= nil and fo.Auto and fo.Id == simF.target.id, "dgfix attack: without a pick the arrow marks the enemy my pet attacks by itself (see-through)",
			fo and tostring(fo.Id) or "nil")
	else
		T.check(BC.GetStats().Focus == nil, "dgfix attack: no pick and no target of its own: no arrow")
	end
	-- F: one order (a tap; bug #16: a hold of 0.4 s adds ONE Target(next), smoke_fight.lua), no repeat
	local idx = #Mock.RemoteLog
	d.noForward = true
	Mock.TriggerAction("NimbusBattleAttack", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
	H.step(6, 1 / 30)
	Mock.TriggerAction("NimbusBattleAttack", "End", Mock.NewInput("F", "Keyboard", "End"))
	H.step(54, 1 / 30)
	local cmds = H.commands(idx)
	T.check(#cmds == 1 and cmds[1].action == "Attack" and cmds[1].arg == nil, "dgfix attack: F sends ONE Attack (nil = keep the live lock / the nearest), nothing repeats",
		#cmds .. " sent")
	local f = BC.GetUnit(BC.GetBattle().FighterId)
	T.check(f and f.Drawn ~= nil, "dgfix attack: my fighter is drawn")
	-- the ATTACK button: one order per press
	H.step(10, 0.05)
	idx = #Mock.RemoteLog
	local btn = H.find("Root.Commands.AttackButton")
	if btn then
		Mock.Click(btn)
	end
	H.step(30, 1 / 30)
	cmds = H.commands(idx)
	T.check(btn and #cmds == 1 and cmds[1].action == "Attack", "dgfix attack: the ATTACK button sends one Attack order", #cmds .. " sent")
	local cap = H.find("Root.Commands.AttackButton.Caption")
	T.check(cap and cap.Text == "ATTACK", "dgfix attack: the ATTACK caption says ATTACK (bug #16)", cap and cap.Text or "nil")
	-- a click on an enemy (the mock camera projects every unit to the screen centre): Attack(its id), the arrow on it
	H.step(10, 0.05)
	local vp = Mock.Viewport
	idx = #Mock.RemoteLog
	Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin", { Position = Vector3.new(vp.X / 2, vp.Y / 2 - 36, 0) }), false)
	Mock.FireSignal(UserInputService, "InputEnded", Mock.NewInput("Unknown", "MouseButton1", "End", { Position = Vector3.new(vp.X / 2, vp.Y / 2 - 36, 0) }))
	H.step(30, 1 / 30)
	cmds = H.commands(idx)
	local picked = cmds[1] and cmds[1].arg
	T.check(#cmds == 1 and cmds[1].action == "Attack" and isEnemy(picked), "dgfix attack: a click on an enemy sends Attack(its id), once", #cmds .. " sent, arg " .. tostring(picked))
	local focus = BC.GetStats().Focus
	T.check(focus and focus.Id == picked and focus.Auto == false, "dgfix attack: ... and the arrow marks it (solid: picked)", focus and tostring(focus.Id) or "nil")
	-- a click on empty ground: Attack() (the server picks the nearest / next)
	H.step(10, 0.05)
	idx = #Mock.RemoteLog
	Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin", { Position = Vector3.new(30, 60, 0) }), false)
	H.step(5, 1 / 30)
	cmds = H.commands(idx)
	T.check(#cmds == 1 and cmds[1].action == "Attack" and cmds[1].arg == nil, "dgfix attack: a click on nothing sends Attack() once", #cmds .. " sent")
	-- the mouse locked at the centre (MouseLock): the same click targets the enemy under the screen centre
	H.step(10, 0.05)
	local okLock = pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end)
	idx = #Mock.RemoteLog
	Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin", { Position = Vector3.new(30, 60, 0) }), false)
	H.step(5, 1 / 30)
	cmds = H.commands(idx)
	T.check(okLock and #cmds == 1 and cmds[1].action == "Attack" and isEnemy(cmds[1].arg), "dgfix attack: with the mouse locked a click targets the enemy under the screen centre",
		#cmds .. " sent, arg " .. tostring(cmds[1] and cmds[1].arg))
	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)
	-- no predicted swing: nothing lunges on a press without a server Hit
	d.noForward = false
	d.logIndex = #Mock.RemoteLog
	-- the pet keeps attacking by itself (battle-core auto-attack): Hits from my fighter arrive without a press
	local hits = 0
	local fid = BC.GetBattle().FighterId
	local root = Mock.GetRoot(LocalPlayer)
	for _ = 1, 40 do
		if root then
			local fu = d:unit(fid)
			local e = d:unit(d:enemyIds()[1] or -1)
			if fu and e then
				local p = d.zoneCF:PointToWorldSpace(Vector3.new(e.x, 0, e.z + 2))
				root.CFrame = CFrame.new(p + Vector3.new(0, 3, 0))
			end
		end
		for _, ev in ipairs(d:step(30)) do
			if ev.type == "Hit" and ev.from == fid and not ev.special and not ev.element then
				hits = hits + 1
			end
		end
	end
	if hits > 0 then
		T.check(true, "dgfix attack: my pet attacks by itself (" .. hits .. " hits without a press)")
	else
		T.info("dgfix attack: no auto-attack Hit in 4 s (BattleSim auto-attack not in this build yet)")
	end
	H.cleanup(BC, d)
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "dgfix attack: no errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_dgfix_attack")
end)

----------------------------------------------------------------------------------------------------
-- client_dgfix_dash
----------------------------------------------------------------------------------------------------
S.client_dgfix_dash = guarded("client_dgfix_dash", function()
	local BC = H.load()
	local MC = H.moduleAt("client", "Controllers/MovementController")
	if not BC or not T.check(MC ~= nil and type(MC.SetPetDash) == "function", "dgfix dash: MovementController.SetPetDash exists") then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local function hasKey(action, key)
		local a = Mock.BoundActions[action]
		for _, k in ipairs(a and a.inputs or {}) do
			if typeof(k) == "EnumItem" and k.Name == key then
				return true
			end
		end
		return false
	end
	KC.advance(3) -- (no obby dash cooldown left over)
	local d = H.dungeon()
	d:start()
	d:step(30)
	d:spawn(H.wild(2), 1)
	d:run(1.6, 30)
	local st = MC.GetSpeedState()
	T.check(st.PetDash == true and hasKey("NimbusDash", "LeftShift") and hasKey("NimbusDash", "RightShift") and hasKey("NimbusDash", "ButtonB")
		and hasKey("NimbusRun", "LeftControl") and not hasKey("NimbusRun", "LeftShift"), "dgfix dash: in battle Shift / RightShift / B = the pet's dash, RUN on Ctrl")
	local root = Mock.GetRoot(LocalPlayer)
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end
	local stamina0 = st.Stamina
	local idx = #Mock.RemoteLog
	local r = Mock.TriggerAction("NimbusDash", "Begin", Mock.NewInput("LeftShift", "Keyboard", "Begin"))
	local vel = root and root.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
	Mock.TriggerAction("NimbusDash", "End", Mock.NewInput("LeftShift", "Keyboard", "End"))
	local cmds = H.commands(idx)
	T.check(#cmds == 1 and cmds[1].action == "Dash" and r == Enum.ContextActionResult.Sink, "dgfix dash: Shift sends ONE BattleCommand Dash", #cmds .. " sent")
	T.check(Vector3.new(vel.X, 0, vel.Z).Magnitude < 0.01, "dgfix dash: ... the character gets no velocity impulse", H.fmt(vel.Magnitude))
	H.step(3, 1 / 30)
	st = MC.GetSpeedState()
	T.check(abs(st.Stamina - stamina0) < 0.01 and MC.GetDashCooldownFraction() == 0, "dgfix dash: ... spends no stamina and starts no character dash (the vitals ring stays ready)",
		H.fmt(stamina0) .. " -> " .. H.fmt(st.Stamina) .. ", ring " .. H.fmt(MC.GetDashCooldownFraction()))
	T.check(MC.TryDash() == false, "dgfix dash: MovementController.TryDash refuses a character dash in battle")
	-- the Dash event draws MY pet's dash (out and back)
	local fid = BC.GetBattle().FighterId
	local before = BC.GetUnit(fid).Drawn
	local dashes0 = BC.GetStats().Dashes
	d:step(30) -- (the command reaches the sim: its Dash event comes back)
	local far = 0
	for _ = 1, 3 do
		H.step(1, 1 / 30)
		local now = BC.GetUnit(fid).Drawn
		far = max(far, (now - before).Magnitude)
	end
	T.check(BC.GetStats().Dashes > dashes0 and far > 1.5, "dgfix dash: the Dash event draws my own pet dashing", H.fmt(far) .. " studs")
	H.step(15, 1 / 30)
	T.check(BC.GetUnit(fid).DashAt == nil, "dgfix dash: ... and back within 0.35 s")
	-- the DASH button sends the same command (no character dash)
	d.noForward = true
	d:run(3, 30)
	idx = #Mock.RemoteLog
	local db = H.find("Root.Commands.DashButton")
	if db then
		Mock.Click(db)
	end
	cmds = H.commands(idx)
	T.check(db and #cmds == 1 and cmds[1].action == "Dash" and MC.GetDashCooldownFraction() == 0, "dgfix dash: the DASH button sends Dash (no character dash)", #cmds .. " sent")
	-- another pet's Dash is drawn too
	d.noForward = false
	d.logIndex = #Mock.RemoteLog
	d:step(30)
	local other = d:enemyIds()[1]
	local d0 = BC.GetStats().Dashes
	KC.toClient("BattleState", "Events", { { type = "Dash", unit = other, dir = 0 } }, d.id)
	d:run(0.4, 30)
	T.check(BC.GetStats().Dashes > d0, "dgfix dash: another pet's Dash event is drawn", BC.GetStats().Dashes .. " / " .. d0)
	d:finish({ Mode = "Dungeon", Outcome = "Win", Won = true, Spectator = false, Reason = "Cleared", Rewards = { Dungeon = true } })
	H.step(5, 0.05)
	st = MC.GetSpeedState()
	T.check(st.PetDash == false and hasKey("NimbusDash", "Q") and hasKey("NimbusRun", "LeftShift"), "dgfix dash: after the battle Q dashes and Shift runs again")
	H.cleanup(BC, d)
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "dgfix dash: no errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_dgfix_dash")
end)

----------------------------------------------------------------------------------------------------
-- client_dgfix_prompt
----------------------------------------------------------------------------------------------------
S.client_dgfix_prompt = guarded("client_dgfix_prompt", function()
	local BC = H.load()
	if not BC then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local d = H.dungeon()
	d:start()
	d:step(30)
	d:spawn(H.wild(2), 1)
	d:run(1.6, 30)
	local part = Instance.new("Part")
	part.Anchored = true
	part.Parent = workspace
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter"
	prompt.Parent = part
	Mock.ShowPrompt(prompt)
	local idx = #Mock.RemoteLog
	local r = Mock.TriggerAction("NimbusBattleElement", "Begin", Mock.NewInput("E", "Keyboard", "Begin"))
	T.check(r == Enum.ContextActionResult.Pass and H.count(idx, "Element") == 0, "dgfix prompt: E passes through to a shown prompt (no ELEMENT)", tostring(r))
	r = Mock.TriggerAction("NimbusBattleElement", "Begin", Mock.NewInput("ButtonY", "Gamepad1", "Begin"))
	T.check(r == Enum.ContextActionResult.Sink and H.count(idx, "Element") == 1, "dgfix prompt: gamepad Y still fires ELEMENT", tostring(r))
	H.step(10, 0.05)
	-- (the cooldown from Y: reset the client's ring by waiting it out)
	d:run(8, 30)
	Mock.HidePrompt(prompt)
	idx = #Mock.RemoteLog
	r = Mock.TriggerAction("NimbusBattleElement", "Begin", Mock.NewInput("E", "Keyboard", "Begin"))
	T.check(r == Enum.ContextActionResult.Sink and H.count(idx, "Element") == 1, "dgfix prompt: with no prompt shown E fires ELEMENT", tostring(r))
	-- a prompt that is destroyed while shown no longer swallows E
	d:run(8, 30)
	Mock.ShowPrompt(prompt)
	part:Destroy()
	idx = #Mock.RemoteLog
	r = Mock.TriggerAction("NimbusBattleElement", "Begin", Mock.NewInput("E", "Keyboard", "Begin"))
	T.check(H.count(idx, "Element") == 1, "dgfix prompt: a prompt destroyed while shown gives E back to ELEMENT", tostring(r))
	-- MouseLock holds: the result card (a wipe) frees the cursor while it shows
	local ML = H.moduleAt("client", "MouseLock")
	if ML and type(ML.Holds) == "function" then
		d:finish({ Mode = "Dungeon", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe", Rewards = { Dungeon = true, Extra = { Floor = 2, Room = 1 } } })
		H.step(4, 0.05)
		T.check(H.shown(H.find("Root.ResultCard")) and ML.Holds().BattleResult == 1, "dgfix prompt: the result card holds MouseLock (BattleResult)", tostring(ML.Holds().BattleResult))
		KC.advance(15)
		H.step(3, 0.1)
		T.check(not H.shown(H.find("Root.ResultCard")) and ML.Holds().BattleResult == nil, "dgfix prompt: ... and releases it when the card goes")
		-- the ring's LEAVE confirm
		local BCat = H.moduleAt("shared", "BattleCatalog")
		local spec = BCat.ChampionTeam(1, 7)
		local ch = spec.Champion or {}
		local rd = H.driver({ Mode = "Ring", Round = 1, Seed = 1, TimeLimit = 90, Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = H.team(3, 0, 30) }, spec },
			Ring = { Round = 1, Best = 0, Start = 1, Champion = { PetId = ch.PetId, Level = ch.Level, Tier = ch.Tier, Name = ch.Name } } })
		rd:start()
		rd:run(0.5, 30)
		local leave = H.find("Root.LeaveButton")
		if leave then
			Mock.Click(leave)
		end
		T.check(leave and ML.Holds().BattleLeave == 1, "dgfix prompt: LEAVE's 'Sure? Tap again' holds MouseLock (BattleLeave)", tostring(ML.Holds().BattleLeave))
		rd.noForward = true
		rd:run(3.5, 30)
		T.check(ML.Holds().BattleLeave == nil, "dgfix prompt: ... released when the confirm runs out")
		H.cleanup(BC, rd)
		T.check(ML.Holds().BattleResult == nil and ML.Holds().BattleLeave == nil, "dgfix prompt: no battle hold is left behind")
	else
		T.info("dgfix prompt: no client/MouseLock module (the hold checks were skipped)")
	end
	H.cleanup(BC, d)
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "dgfix prompt: no errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_dgfix_prompt")
end)

return S
