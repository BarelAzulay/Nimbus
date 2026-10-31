-- smoke_tb_loss.lua: a loss feels like progress (team-balance plan, Task 6; spec 2026-10-31 s.7). Loaded by tools/smoke.py in the
-- server world and the client worlds:
--   tb_loss_levels_ring     (server, booted) the final End of a lost run (Wipe, Timeout, Fainted) carries Rewards.Pets
--                           { Key, PetId, Before, After, XpFrac, XpBefore } in team order, after the loss XP, and Rewards.Start; a
--                           forfeit carries neither; from where the return teleport drops you, the same (boss) start is free again
--   tb_loss_levels_dungeon  (server, booted) a Wipe / Timeout End carries Pets, Solo only for a one-member run; a Quit carries
--                           neither; Solo again right after the return, without walking back
--   tb_loss_tutorial_room   (server, booted) TutorialService.IsOnStep; DungeonService.RoomCleared; the first room completes
--                           "Into the Dungeon!", Best and the first clear stay untouched; an old save past the step does not move
--   tb_loss_eased           (server, booted) run.Eased: room 1 of a solo tutorial run is the eased wave, room 2 is not, a party
--                           or a late joiner gets the normal room, a player past the step too; the normal reward is paid
--   client_tb_loss_screen   (client) a lost run shows the screen in place of the result card (the three ways a Ring End arrives,
--                           a Dungeon wipe); L1 -> L3 + one Reward sound, an XP bar for a pet without a level-up; a forfeit, a
--                           cleared floor and a quit keep today's cards; Edit team hands ReturnTo { Window = "Loss" } and comes back
--   client_tb_loss_fight_again  (client) Fight again waits while InBattle is set (Review Focus 5), fires once, a refusal re-arms it,
--                           the next battle closes the screen; Dungeon: DungeonRequest("Solo", floor), a party gets no Fight again
--   client_tb_loss_phone    (phone world) inside 16 px gutters, under the top bar, every button >= 44 px, on 844x390 and 390x844
-- PetsController (Task 4) is stubbed when the tree does not have it yet: the stub's Close does what the plan's router does.
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local advance = K.advance

	local K1, K2, K3 = "mallow_kitten", "puddle_frog", "pebble_pup"
	local TEAM = { K1, K2, K3 }
	local seq = 0

	local function req(path)
		local inst = K.moduleInstance(path)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end
	local function BS() return req("server/Services/BattleService") end
	local function DS() return req("server/Services/DataService") end
	local function DGS() return req("server/Services/DungeonService") end
	local function TS() return req("server/Services/TutorialService") end
	local function BC() return req("shared/BattleCatalog") end
	local function TC() return req("shared/TycoonCatalog") end

	local function newPlayer(prefix, level)
		seq = seq + 1
		-- (979000+: smoke_p5_tutorial.lua uses 975000+, smoke_ring_noheal.lua 971000+)
		local p = Mock.AddPlayer(prefix .. seq, 979000 + seq)
		advance(1.0)
		local data = DS()
		local prof = data.GetProfile(p)
		for _, id in ipairs(TEAM) do
			prof.Pets[id] = 1
			prof.PetLevels[id] = { Level = level or 1, Xp = 0 }
		end
		data.MarkDirty(p)
		data.SetTeam(p, 1, TEAM)
		return p
	end

	local function claimHome(p)
		local Ty = req("server/Services/TycoonService")
		local SS = req("server/Services/SpotService")
		local spots = (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
		for i = 1, K.config().Lobby.SpotCount do
			if spots[i] and not (SS and SS.GetOwner(i)) and Ty.Claim(p, i) then
				advance(0.6)
				return i
			end
		end
		return nil
	end

	------------------------------------------------------------------------------------------------ the Ring
	local function svcState()
		local f = BS() and BS().IsInBattle
		for i = 1, 80 do
			local name, v = debug.getupvalue(f, i)
			if not name then
				break
			end
			if name == "St" and type(v) == "table" and type(v.battles) == "table" then
				return v
			end
		end
		return nil
	end

	local function battleOf(p)
		local St = svcState()
		local id = p:GetAttribute("InBattle")
		return St and type(id) == "string" and St.battles[id] or nil
	end

	local function toRing(p)
		local portal = workspace:FindFirstChild("Portal_Ring", true)
		local pos = portal and (portal:IsA("BasePart") and portal.Position or portal:GetPivot().Position)
		if pos then
			Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 6)))
			advance(0.05)
		end
	end

	local function lastSent(p, kind)
		local log = Mock.RemoteLog
		for i = #log, 1, -1 do
			local e = log[i]
			if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and e.args[1] == kind then
				return e.args[2]
			end
		end
		return nil
	end

	-- white-box: the champion cannot be hurt and does not hurt
	local function stall(b)
		for _, u in ipairs(b.Sim.units) do
			if u.side == 2 then
				u.maxHp, u.hp, u.hit = 1e9, 1e9, 0
			end
		end
	end

	-- white-box: the climber's side is knocked out (the round is lost by a Wipe)
	local function knockOutClimber(b)
		for _, u in ipairs(b.Sim.units) do
			if u.side == 1 then
				u.hp = 0
				u.alive = false
				u.state = 5
			end
		end
	end

	local function knockOutChampion(b)
		for _, u in ipairs(b.Sim.units) do
			if u.side == 2 then
				u.hp = 0
				u.alive = false
				u.state = 5
			end
		end
	end

	-- white-box: the round is won with nobody left standing (the run ends "Fainted" between two rounds)
	local function winFainted(b, p)
		local team = b.Sim.teamByOwner[p.UserId]
		for _, u in ipairs(team and team.units or {}) do
			u.hp = 0
		end
		knockOutChampion(b)
	end

	local function findPet(list, key)
		for _, row in ipairs(type(list) == "table" and list or {}) do
			if row.Key == key then
				return row
			end
		end
		return nil
	end

	S.tb_loss_levels_ring = guarded("tb_loss_levels_ring", function()
		if not K.needBoot() then
			return
		end
		local bs, data, tc = BS(), DS(), TC()
		local realRaid = bs.StartRaid
		bs.StartRaid = function()
			return false, "A raid is already running"
		end
		local a = newPlayer("TbLossRing", 1)
		T.check(claimHome(a) ~= nil, "tb loss: (setup) the climber claims a home")
		local need1 = tc.XpToNext(1)
		data.GetProfile(a).PetLevels[K1] = { Level = 1, Xp = need1 - 1 }
		data.MarkDirty(a)

		-- a run lost in round 2, after a real loss (>= 20 s)
		toRing(a)
		local ok, id = bs.StartRing(a)
		if not T.check(ok == true, "tb loss: (setup) the run starts", tostring(id)) then
			bs.StartRaid = realRaid
			K.removePlayers({ a })
			return
		end
		knockOutChampion(battleOf(a).Sim and battleOf(a))
		advance(BC().Ring.Intermission + 0.8)
		local b2 = battleOf(a)
		T.check(b2 and b2.Round == 2, "tb loss: (setup) round 2 runs", tostring(b2 and b2.Round))
		stall(b2)
		advance(21)
		knockOutClimber(b2)
		advance(0.5)
		local e = lastSent(a, "End")
		local rw = e and e.Rewards or {}
		T.check(rw.Final == true and type(rw.Pets) == "table" and #rw.Pets == 3 and rw.Start == 1, "tb loss: the final End carries Pets and Start",
			fmt("%s / %s / %s", tostring(rw.Final), tostring(type(rw.Pets)), tostring(rw.Start)))
		local p1, p3 = findPet(rw.Pets, K1), findPet(rw.Pets, K3)
		T.check(type(rw.Pets) == "table" and rw.Pets[1] and rw.Pets[1].Key == K1 and rw.Pets[2].Key == K2 and rw.Pets[3].Key == K3, "tb loss: Pets are in team order")
		local level1 = data.GetPetLevel(a, K1)
		T.check(p1 and p1.PetId == K1 and p1.Before == 1 and p1.After == level1 and p1.After >= 2, "tb loss: Before = the run's start level, After = the level now (server-computed)",
			p1 and fmt("%s -> %s", tostring(p1.Before), tostring(p1.After)) or "no row")
		local level3, xp3 = data.GetPetLevel(a, K3)
		T.check(p3 and p3.XpBefore == 0 and p3.XpFrac >= 0 and p3.XpFrac < 1 and math.abs(p3.XpFrac - xp3 / tc.XpToNext(level3)) < 1e-6,
			"tb loss: XpFrac is the XP now, after the loss XP was granted; XpBefore the fraction at the start", p3 and tostring(p3.XpFrac) or "no row")
		T.check(p1 and math.abs(p1.XpBefore - (need1 - 1) / need1) < 1e-6, "tb loss: XpBefore of a pet that started with XP", p1 and tostring(p1.XpBefore) or "no row")
		T.check((tonumber(rw.Xp) or 0) > 0, "tb loss: the lost round paid its loss XP", tostring(rw.Xp))
		advance(5)
		T.check(a:GetAttribute("InBattle") == nil, "tb loss: (setup) released after the return")

		-- a timeout
		toRing(a)
		ok = bs.StartRing(a)
		T.check(ok == true, "tb loss: (setup) a second run")
		stall(battleOf(a))
		advance((tonumber(BC().Ring.TimeLimit) or 90) + 1)
		e = lastSent(a, "End")
		T.check(e and e.Reason == "Timeout" and e.Rewards.Final == true and type(e.Rewards.Pets) == "table" and #e.Rewards.Pets == 3, "tb loss: a Timeout carries Pets", e and tostring(e.Reason) or "no End")
		advance(5)

		-- a forfeit: not a loss screen
		toRing(a)
		ok = bs.StartRing(a)
		T.check(ok == true, "tb loss: (setup) a third run")
		bs.Forfeit(a)
		advance(0.5)
		e = lastSent(a, "End")
		T.check(e and e.Rewards.Final == true and e.Rewards.Pets == nil and e.Rewards.Start == nil, "tb loss: a forfeit carries no Pets (it is not a loss screen)", e and tostring(e.Reason) or "no End")
		advance(5)

		-- a boss start, lost by fainting (the End between two rounds): the start is kept and free again without walking back
		data.MutateRing(a, function(ring)
			ring.Best = 20
		end)
		toRing(a)
		ok = bs.StartRing(a, 20)
		T.check(ok == true, "tb loss: (setup) a boss start")
		winFainted(battleOf(a), a)
		advance(0.5)
		e = lastSent(a, "End")
		T.check(e and e.Reason == "Fainted" and e.Rewards.Final == true and type(e.Rewards.Pets) == "table" and #e.Rewards.Pets == 3 and e.Rewards.Start == 20,
			"tb loss: a run that fainted between two rounds carries Pets and its boss Start", e and fmt("%s, Start %s", tostring(e.Reason), tostring(e.Rewards.Start)) or "no End")
		advance(5)
		T.check(a:GetAttribute("InBattle") == nil, "tb loss: (setup) released")
		local okAgain, whyAgain = bs.StartRing(a, 20)
		T.check(okAgain == true, "tb loss: Fight again's request works from where the return teleport put the player (no walking back)", tostring(whyAgain))
		if bs.IsInBattle(a) then
			bs.Forfeit(a)
		end
		advance(5.5)
		bs.StartRaid = realRaid
		K.flushErrors("tb_loss_levels_ring")
		K.flushWarnings("tb_loss_levels_ring", { "[BattleService]", "[DataService]", "[TycoonService]", "[PetCareService]", "[MeshLibrary]" })
		local St = svcState()
		if St and type(St.ringBoard) == "table" then
			St.ringBoard[a.UserId] = nil
		end
		K.removePlayers({ a })
		advance(1)
	end)

	------------------------------------------------------------------------------------------------ the Dungeon
	local function dungeonInfo()
		local db = req("server/Services/DungeonBuilder")
		return db and db.GetInfo and db.GetInfo() or nil
	end

	local function toPad(p, dx)
		local i = dungeonInfo()
		local pad = i and (i.Pad or i.PromptPart)
		if pad then
			Mock.Teleport(p, CFrame.new(pad.Position + Vector3.new(dx or 0, 3.5, 0)))
		end
		advance(0.05)
	end

	local function request(p, action, a, b)
		local folder = K.remoteFolder()
		Mock.FromClient(folder:FindFirstChild("DungeonRequest"), p, action, a, b)
		advance(0.05)
	end

	local function runOf(p)
		return DGS().St.runOf[p]
	end

	local function lastState(p, kind, fromIndex)
		local out = nil
		for _, e in ipairs(K.remotesFor("DungeonState", p.UserId, fromIndex or 0)) do
			if e.args[1] == kind then
				out = e.args[2]
			end
		end
		return out
	end

	local function startSolo(p, floorIndex)
		toPad(p)
		request(p, "Solo", floorIndex or 1)
		local run = runOf(p)
		if run then
			advance(0.6)
		end
		return run
	end

	-- every member presses E at the open door: from the Hall to room 1's entrance
	local function pressDoor(run)
		local dg = DGS().Dg
		local t0 = Mock.Clock.now
		local prompt = dg.nextDoor(run)
		while not prompt and Mock.Clock.now - t0 < 6 do
			advance(0.25)
			prompt = dg.nextDoor(run)
		end
		for _, uid in ipairs(run.Order) do
			local m = run.Members[uid]
			if m and not m.Left and prompt then
				Mock.Teleport(m.Player, CFrame.new(prompt.Parent.Position))
				Mock.Trigger(prompt, m.Player)
			end
		end
		advance(0.6)
	end

	local function crossThreshold(run, p)
		local ri = run.Pocket and run.Pocket.Rooms[run.Room]
		if ri and ri.Threshold then
			Mock.Teleport(p, CFrame.new(ri.Threshold.Position))
		end
		advance(1.2)
	end

	local function intoRoom(run, p, room)
		if run.State == "Hall" then
			pressDoor(run)
		end
		if room and room ~= run.Room then
			DGS().Dg.enterRoom(run, room)
			advance(0.3)
		end
		crossThreshold(run, p)
		return run.State == "Fight"
	end

	local function encounterOf(run)
		local St = svcState()
		return St and run.Battle and St.battles[run.Battle] or nil
	end

	local function tuneEnemies(run, fn)
		local b = encounterOf(run)
		for _, u in ipairs(b and b.Sim and b.Sim.units or {}) do
			if u.side == 2 and u.alive then
				fn(u)
			end
		end
	end

	local function endDungeon()
		local dgs = DGS()
		for _, id in ipairs({ unpack(dgs.St.runOrder) }) do
			local run = dgs.St.runs[id]
			if run then
				dgs.Dg.endRun(run, false, "Abandoned", true)
			end
		end
		for leaderId in pairs(dgs.St.parties) do
			local party = dgs.St.parties[leaderId]
			if party and party.Leader then
				dgs.LeaveParty(party.Leader)
			end
		end
		advance(0.2)
	end

	local function cleanup(list)
		endDungeon()
		advance(0.3)
		K.removePlayers(list)
		advance(1)
	end

	S.tb_loss_levels_dungeon = guarded("tb_loss_levels_dungeon", function()
		if not K.needBoot() then
			return
		end
		local data = DS()
		-- a solo wipe in room 2 of floor 1, after a real loss: the third of the XP is in the numbers
		local a = newPlayer("TbLossDgn", 1)
		local run = startSolo(a, 1)
		if not T.check(run ~= nil, "tb loss: (setup) a solo run") then
			cleanup({ a })
			return
		end
		T.check(intoRoom(run, a, 2) and run.Room == 2, "tb loss: (setup) the fight in room 2 runs", tostring(run.State))
		tuneEnemies(run, function(u)
			u.maxHp, u.hp, u.hit = 1e9, 1e9, 0
		end)
		advance(21)
		local mark = K.logSize()
		tuneEnemies(run, function(u)
			u.hit = 1e6
		end)
		local t0 = Mock.Clock.now
		while run.State == "Fight" and Mock.Clock.now - t0 < 60 do
			advance(0.5)
		end
		local e = lastState(a, "End", mark)
		T.check(e and e.Reason == "Wipe" and e.Solo == true and type(e.Pets) == "table" and #e.Pets == 3, "tb loss: the dungeon End carries Pets and Solo", e and tostring(e.Reason) or "no End")
		local level1, xp1 = data.GetPetLevel(a, K1)
		local row = e and findPet(e.Pets, K1)
		T.check(row and row.PetId == K1 and row.Before == 1 and row.After == level1 and row.XpBefore == 0 and math.abs(row.XpFrac - xp1 / TC().XpToNext(level1)) < 1e-6,
			"tb loss: the row comes from the run's start level to now", row and fmt("%s -> %s", tostring(row.Before), tostring(row.After)) or "no row")
		T.check(e and type(e.Pets) == "table" and e.Pets[1].Key == K1 and e.Pets[3].Key == K3, "tb loss: the dungeon's Pets are in team order")
		advance(5)
		T.check(a:GetAttribute("InBattle") == nil and runOf(a) == nil, "tb loss: (setup) released after the return")
		-- Fight again: from where the return teleport put the player, without walking back
		mark = K.logSize()
		request(a, "Solo", 1)
		local again = runOf(a)
		T.check(again ~= nil, "tb loss: DungeonRequest('Solo', floor) works right after the return (no walking back)")
		-- a Quit: not a loss screen
		mark = K.logSize()
		if again then
			advance(0.6)
			request(a, "Quit")
			advance(0.3)
			local q = lastState(a, "End", mark)
			T.check(q and q.Pets == nil and q.Solo == nil, "tb loss: a Quit carries no Pets", q and tostring(q.Reason) or "no End")
		end
		advance(5)

		-- a party: Pets, but no Solo
		local b = newPlayer("TbLossDgn", 1)
		toPad(a, 0)
		toPad(b, 2)
		request(a, "Create", 1)
		request(b, "Join", a.UserId)
		request(b, "Ready", true)
		request(a, "Start")
		advance(6)
		local partyRun = runOf(a)
		if T.check(partyRun ~= nil and #partyRun.Order == 2, "tb loss: (setup) a party run", partyRun and tostring(#partyRun.Order) or "no run") then
			mark = K.logSize()
			DGS().Dg.endRun(partyRun, false, "Timeout")
			advance(0.2)
			local pe = lastState(b, "End", mark)
			T.check(pe and pe.Reason == "Timeout" and pe.Solo == nil and type(pe.Pets) == "table" and #pe.Pets == 3, "tb loss: a party member's End has Pets and no Solo flag", pe and tostring(pe.Solo) or "no End")
		end
		advance(5)
		cleanup({ a, b })
		K.flushErrors("tb_loss_levels_dungeon")
		K.flushWarnings("tb_loss_levels_dungeon", { "[BattleService]", "[DataService]", "[DungeonService]", "[DungeonBuilder]", "[TycoonService]", "[PetCareService]", "[MeshLibrary]" })
	end)

	------------------------------------------------------------------------------------------------ the tutorial
	local function resume(p, step)
		DS().SetTutorial(p, { Step = step, Done = true, Gifted = true })
		TS().Reload(p)
		advance(0.4)
	end

	local function stepId(p)
		local st = TS().GetState(p)
		return st and not st.Done and st.Id or (st and st.Done and "done!") or nil
	end

	S.tb_loss_tutorial_room = guarded("tb_loss_tutorial_room", function()
		if not K.needBoot() then
			return
		end
		local ts, dgs, data = TS(), DGS(), DS()
		if not T.check(type(ts.IsOnStep) == "function" and dgs.RoomCleared ~= nil, "tb loss: TutorialService.IsOnStep and DungeonService.RoomCleared exist") then
			return
		end
		local p = newPlayer("TbLossStep", 1)
		resume(p, 17)
		T.check(stepId(p) == "dungeon", "tb loss: (setup) a player on 'dungeon'", tostring(stepId(p)))
		T.check(ts.IsOnStep(p, "dungeon") == true and ts.IsOnStep(p, "ring") == false, "tb loss: IsOnStep answers for the current step only")
		local fired = {}
		local conn = dgs.RoomCleared:Connect(function(pl, f, r)
			fired[#fired + 1] = { pl, f, r }
		end)
		-- a room on another floor is not the step's
		dgs.RoomCleared:Fire(p, 2, 1)
		advance(0.6)
		T.check(stepId(p) == "dungeon", "tb loss: a room of another floor completes nothing", tostring(stepId(p)))
		fired = {}
		local run = startSolo(p, 1)
		if T.check(run ~= nil and intoRoom(run, p), "tb loss: (setup) the fight in room 1 runs") then
			BS().FinishEncounter(run.Battle, "Cleared")
			advance(0.6)
			T.check(#fired == 1 and fired[1][1] == p and fired[1][2] == 1 and fired[1][3] == 1, "tb loss: RoomCleared(p, 1, 1) fires for the live member", tostring(#fired))
			T.check(stepId(p) == "raid", "tb loss: the first room completes 'Into the Dungeon!'", tostring(stepId(p)))
			local rec = data.GetDungeon(p)
			T.check(rec.Best == 0 and rec.Cleared[1] == nil and run.Cleared ~= true, "tb loss: Best and the first clear are untouched until the floor is really cleared", tostring(rec.Best))
			T.check(ts.IsOnStep(p, "dungeon") == false, "tb loss: IsOnStep is false once the step is done")
		end
		conn:Disconnect()
		-- an old save past the step: nothing moves
		local v = newPlayer("TbLossStep", 1)
		resume(v, 19)
		local before = stepId(v)
		dgs.RoomCleared:Fire(v, 1, 1)
		advance(0.6)
		T.check(before == "train" and stepId(v) == before, "tb loss: an old save past the step is unaffected", tostring(stepId(v)))
		-- a skipped tutorial
		ts.HandleEvent(v, "Skip")
		advance(0.3)
		T.check(ts.IsOnStep(v, "train") == false and ts.IsOnStep("junk", "train") == false, "tb loss: IsOnStep is false when the tutorial is skipped or the player unknown")
		cleanup({ p, v })
		K.flushErrors("tb_loss_tutorial_room")
		K.flushWarnings("tb_loss_tutorial_room", { "[BattleService]", "[DataService]", "[DungeonService]", "[DungeonBuilder]", "[TycoonService]", "[PetCareService]", "[MeshLibrary]" })
	end)

	S.tb_loss_eased = guarded("tb_loss_eased", function()
		if not K.needBoot() then
			return
		end
		local bc, dgs = BC(), DGS()
		-- every wave the service asks for: the arguments and the Power it got
		local realWave = bc.DungeonWave
		local waves = {}
		bc.DungeonWave = function(f, room, wave, n, seed, opts)
			local plan = realWave(f, room, wave, n, seed, opts)
			waves[#waves + 1] = { Floor = f, Room = room, Wave = wave, N = n, Seed = seed, Opts = opts, Power = plan.Power }
			return plan
		end
		local function restore()
			bc.DungeonWave = realWave
		end
		local function lastWave()
			return waves[#waves]
		end

		-- a solo run by a player on the step: room 1 is eased, room 2 is not
		local p = newPlayer("TbLossEase", 1)
		resume(p, 17)
		local run = startSolo(p, 1)
		if not T.check(run ~= nil and run.Eased == true, "tb loss: the solo tutorial run has the Eased flag", run and tostring(run.Eased) or "no run") then
			restore()
			cleanup({ p })
			return
		end
		T.check(intoRoom(run, p), "tb loss: (setup) room 1 fights")
		local w1 = lastWave()
		T.check(w1 and w1.Room == 1 and type(w1.Opts) == "table" and w1.Opts.Eased == true and w1.Power == realWave(1, 1, w1.Wave, 1, run.Seed, { Eased = true }).Power,
			"tb loss: the wave of room 1 is the eased one", w1 and tostring(w1.Power) or "no wave")
		T.check(w1 and w1.Power < realWave(1, 1, w1.Wave, 1, run.Seed).Power, "tb loss: ...and weaker than the plain wave")
		-- the room pays the normal reward, whatever the wave was
		local income = req("server/Services/TycoonService").IncomePerSecond(p)
		local rewards = bc.DungeonRewards(1, 1, run.Waves, income, false)
		local xp0 = DS().GetPetLevel(p, K1) and select(2, DS().GetPetLevel(p, K1))
		dgs.Dg.payRoom(run, 1, { Reason = "Cleared", Duration = 30, Fighters = { p.UserId }, Hp = { [2] = 0 } })
		local level1, xp1 = DS().GetPetLevel(p, K1)
		T.check(rewards.Xp > 0 and (level1 > 1 or xp1 - xp0 == rewards.Xp), "tb loss: the eased room pays the normal room reward", fmt("level %d, xp %d -> %d, reward %d", level1, xp0, xp1, rewards.Xp))
		BS().FinishEncounter(run.Battle, "Cleared")
		advance(0.6)
		local rec = DS().GetDungeon(p)
		T.check(rec.Best == 0 and rec.Cleared[1] == nil, "tb loss: Best stays untouched by the eased room")
		T.check(intoRoom(run, p, 2) and run.Room == 2, "tb loss: (setup) room 2 fights", tostring(run.State))
		local w2 = lastWave()
		T.check(w2 and w2.Room == 2 and w2.Opts == nil, "tb loss: room 2 is the plain wave", w2 and tostring(w2.Room) or "no wave")
		cleanup({ p })

		-- a player past the step: the plain room
		local vet = newPlayer("TbLossEase", 1)
		resume(vet, 19)
		local vetRun = startSolo(vet, 1)
		T.check(vetRun ~= nil and vetRun.Eased ~= true, "tb loss: a player past the step gets the normal room")
		cleanup({ vet })

		-- a party on the step: the normal room (nobody farms it)
		local a = newPlayer("TbLossEase", 1)
		local b = newPlayer("TbLossEase", 1)
		resume(a, 17)
		resume(b, 17)
		toPad(a, 0)
		toPad(b, 2)
		request(a, "Create", 1)
		request(b, "Join", a.UserId)
		request(b, "Ready", true)
		request(a, "Start")
		advance(6)
		local partyRun = runOf(a)
		if T.check(partyRun ~= nil and #partyRun.Order == 2, "tb loss: (setup) a party run") then
			T.check(partyRun.Eased ~= true, "tb loss: a party never gets the eased flag", tostring(partyRun.Eased))
			T.check(intoRoom(partyRun, a), "tb loss: (setup) the party's room 1 fights")
			local w = lastWave()
			T.check(w and w.Room == 1 and w.N == 2 and w.Opts == nil, "tb loss: a party never gets the eased room (no farming)", w and tostring(w.N) or "no wave")
		end
		cleanup({ a, b })

		-- a late joiner in the Hall of a solo tutorial run drops the flag before the room spawns
		local c = newPlayer("TbLossEase", 1)
		local j = newPlayer("TbLossEase", 1)
		resume(c, 17)
		local soloRun = startSolo(c, 1)
		if T.check(soloRun ~= nil and soloRun.Eased == true, "tb loss: (setup) a solo tutorial run") then
			toPad(j, 2)
			local okJ, whyJ = dgs.Dg.lateJoin(soloRun, j)
			T.check(okJ == true and soloRun.Eased ~= true, "tb loss: a late joiner drops the eased flag", tostring(whyJ))
			T.check(intoRoom(soloRun, c), "tb loss: (setup) room 1 with the joiner")
			local w = lastWave()
			T.check(w and w.Room == 1 and w.Opts == nil, "tb loss: ...and the room is the plain wave")
		end
		cleanup({ c, j })
		restore()
		K.flushErrors("tb_loss_eased")
		K.flushWarnings("tb_loss_eased", { "[BattleService]", "[DataService]", "[DungeonService]", "[DungeonBuilder]", "[TycoonService]", "[PetCareService]", "[MeshLibrary]" })
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
	local LocalPlayer = Players.LocalPlayer
	local H = {}

	local K1, K2, K3 = "mallow_kitten", "puddle_frog", "pebble_pup"
	local ROWS = {
		{ Key = K1, PetId = K1, Before = 1, After = 3, XpFrac = 0.1, XpBefore = 0 },
		{ Key = K2, PetId = K2, Before = 1, After = 1, XpFrac = 0.6, XpBefore = 0.2 },
		{ Key = K3, PetId = K3, Before = 4, After = 4, XpFrac = 0.5, XpBefore = 0.5 },
	}

	function H.req(path)
		local root, rest = path:match("^(%a+)/(.+)$")
		local inst = Mock.GetPath(ROOTS[root] .. "/" .. rest)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end
	function H.mod(name)
		if KC.M and KC.M[name] then
			return KC.M[name]
		end
		return H.req("client/Controllers/" .. name)
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.find(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	function H.shown(obj)
		return obj ~= nil and KC.isShown(obj)
	end
	function H.card()
		local gui = H.pg():FindFirstChild("NimbusLoss")
		return gui and gui:FindFirstChild("LossCard", true)
	end
	function H.widget(name)
		return H.find(H.card(), name)
	end
	function H.resultCard()
		return H.find(H.pg(), "ResultCard")
	end
	-- the stub of Task 4's window: Close does what the plan's router does with ReturnTo { Window = "Loss" }
	function H.pets()
		local folder = Mock.GetPath(ROOTS.client .. "/Controllers")
		if not folder:FindFirstChild("PetsController") then
			Mock.Mount(folder, { name = "PetsController", class = "ModuleScript", source = [[
				local P = { Opens = {}, Stub = true }
				local open, back = false, nil
				function P.Open(args)
					P.Opens[#P.Opens + 1] = args
					open, back = true, type(args) == "table" and args.ReturnTo or nil
				end
				function P.IsOpen()
					return open
				end
				function P.Close()
					open = false
					if type(back) == "table" and back.Window == "Loss" then
						require(script.Parent.LossScreen).Reopen()
					end
				end
				return P
			]], children = {} })
		end
		return H.req("client/Controllers/PetsController")
	end
	function H.reset()
		local LS = H.req("client/Controllers/LossScreen")
		if LS then
			LS.Hide()
		end
		local BC = H.mod("BattleController")
		if BC and BC.HideResult then
			BC.HideResult()
		end
		LocalPlayer:SetAttribute(KC.env().Attr.InBattle, nil)
		KC.advance(0.1)
	end
	function H.feed()
		KC.toClient("ProfileSync", {
			Tokens = 0, Pets = { [K1] = 1, [K2] = 1, [K3] = 1 }, Equipped = { K1, K2, K3 }, Items = {},
			PetLevels = { [K1] = { Level = 3, Xp = 0 }, [K2] = { Level = 1, Xp = 0 }, [K3] = { Level = 4, Xp = 0 } },
			Teams = { Presets = { { K1, K2, K3 }, {}, {} }, Active = 1, Slots = 3 },
		})
		KC.advance(0.1)
	end
	function H.start(id, mode)
		local p = { BattleId = id, Mode = mode, Side = 1, Spectator = false, T = 0, Units = {}, Zone = { CFrame = CFrame.new(0, 400, 0), X = 40, Z = 40 } }
		if mode == "Ring" then
			p.Ring = { Round = 2, Best = 0, Start = 1 }
		else
			p.Dungeon = { Floor = 3, Room = 2 }
		end
		LocalPlayer:SetAttribute(KC.env().Attr.InBattle, id)
		H.mod("BattleController").HandleState("Start", p, id)
		KC.advance(0.2)
	end
	function H.ringLoss(id, reason, over)
		local p = { BattleId = id, Mode = "Ring", Outcome = "Loss", Won = false, Spectator = false, Reason = reason or "Wipe",
			Rewards = { Won = false, Final = true, Round = 2, Cash = 0, Xp = 9, Start = 1, Pets = ROWS,
				Run = { Wins = 1, Cash = 40, Xp = 35, Tokens = 0, Round = 2, Start = 1, Best = 1 } } }
		for k, v in pairs(over or {}) do
			p[k] = v
		end
		return p
	end
	function H.dungeonWipe(solo, reason)
		return { Floor = 3, Name = "Flooded Vaults", Cleared = false, Reason = reason or "Wipe", Room = 2,
			Totals = { Cash = 10, Tokens = 4, Xp = 30, Gems = 0 }, NewBest = false, Solo = solo and true or nil, Pets = ROWS }
	end
	function H.requests(remote, mark)
		return KC.serverCalls(remote, mark)
	end

	S.client_tb_loss_screen = guarded("client_tb_loss_screen", function()
		local LS = H.req("client/Controllers/LossScreen")
		local BC = H.mod("BattleController")
		if not T.check(type(LS) == "table" and type(LS.Show) == "function" and type(LS.Reopen) == "function" and type(LS.Hide) == "function" and type(LS.IsOpen) == "function",
			"tb loss: client/Controllers/LossScreen loads (Show, Reopen, Hide, IsOpen)") then
			return
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		H.feed()
		H.reset()
		local SF = H.req("client/SoundFx")
		local played, realPlay = {}, SF.Play
		SF.Play = function(name, ...)
			played[#played + 1] = name
			return realPlay(name, ...)
		end

		-- a lost round
		H.start("tb_loss1", "Ring")
		BC.HandleState("End", H.ringLoss("tb_loss1"), "tb_loss1")
		KC.advance(0.1)
		T.check(LS.IsOpen() and H.shown(H.card()), "tb loss: a lost run shows the loss screen")
		T.check(not H.shown(H.resultCard()), "tb loss: ...the plain card is not shown")
		local row1, row2 = H.widget("PetRow1"), H.widget("PetRow2")
		T.check(row1 and H.find(row1, "Levels").Text == "L1 -> L3" and not H.shown(H.find(row1, "XpBar")), "tb loss: L1 -> L3 for a pet that gained levels", row1 and H.find(row1, "Levels").Text or "no row")
		T.check(row2 and H.find(row2, "Levels").Text == "L1" and H.shown(H.find(row2, "XpBar")), "tb loss: the XP bar for a pet without a level-up")
		T.check(H.find(row1, "Face") ~= nil and H.find(row1, "Name").Text ~= "", "tb loss: each row has the pet's face and name")
		T.check(H.widget("Title").Text == "RUN OVER" and tostring(H.widget("Sub").Text):find("champion won round 2", 1, true) ~= nil, "tb loss: the Ring's title and line", tostring(H.widget("Sub").Text))
		T.check(H.shown(H.widget("FightAgain")) and H.widget("FightAgain").Text == "Fight again" and H.shown(H.widget("EditTeam")) and H.widget("EditTeam").Text == "Edit team" and H.shown(H.widget("CloseButton")),
			"tb loss: Fight again + Edit team + Close")
		local fill = H.find(H.find(row2, "XpBar"), "Fill")
		KC.advance(0.5)
		local rewards = 0
		for _, name in ipairs(played) do
			rewards = rewards + (name == "Reward" and 1 or 0)
		end
		T.check(rewards == 1, "tb loss: the level-up moment plays once", tostring(rewards))
		KC.advance(1.5)
		T.check(fill and math.abs(fill.Size.X.Scale - 0.6) < 0.01, "tb loss: the XP bar moved to XpFrac", fill and tostring(fill.Size.X.Scale) or "no fill")
		local lines = H.widget("Lines")
		local sawCash = false
		for _, c in ipairs(lines and lines:GetChildren() or {}) do
			sawCash = sawCash or (c:IsA("TextLabel") and tostring(c.Text):find("Cash", 1, true) ~= nil)
		end
		T.check(sawCash, "tb loss: the run's lines are on the card")

		-- Edit team goes to the Pets window and comes back
		local PC = H.pets()
		LocalPlayer:SetAttribute(KC.env().Attr.InBattle, nil) -- (the return teleport is over)
		Mock.Click(H.widget("EditTeam"))
		KC.advance(0.2)
		T.check(PC.IsOpen() and not LS.IsOpen(), "tb loss: Edit team opens the Pets window")
		if PC.Stub then
			T.check(PC.Opens[#PC.Opens].ReturnTo and PC.Opens[#PC.Opens].ReturnTo.Window == "Loss", "tb loss: ...with ReturnTo { Window = 'Loss' }")
		end
		local rewardsBefore = rewards
		PC.Close()
		KC.advance(0.6)
		T.check(LS.IsOpen() and H.find(H.widget("PetRow1"), "Levels").Text == "L1 -> L3", "tb loss: ...and returns here")
		rewards = 0
		for _, name in ipairs(played) do
			rewards = rewards + (name == "Reward" and 1 or 0)
		end
		T.check(rewards == rewardsBefore, "tb loss: coming back does not replay the level-up sound", tostring(rewards))
		Mock.Click(H.widget("CloseButton"))
		KC.advance(0.1)
		T.check(not LS.IsOpen() and not H.shown(H.card()), "tb loss: Close hides it")
		KC.advance(20)
		H.reset()

		-- a forfeit keeps the plain card: the server sends no Pets
		H.start("tb_loss2", "Ring")
		BC.HandleState("End", H.ringLoss("tb_loss2", "Forfeit", { Rewards = { Won = false, Final = true, Round = 2, Run = { Wins = 1, Round = 2, Start = 1, Best = 1 } } }), "tb_loss2")
		KC.advance(0.1)
		T.check(not LS.IsOpen() and H.shown(H.resultCard()), "tb loss: a forfeit keeps today's result card")
		KC.advance(20)
		H.reset()

		-- the run ended between two rounds (a won round, then the final End): the side card's way
		H.start("tb_loss3", "Ring")
		BC.HandleState("End", { BattleId = "tb_loss3", Mode = "Ring", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
			Rewards = { Won = true, Next = 3, Round = 2, Cash = 5, Xp = 32, Tokens = 0, Record = false, Seconds = 1, LevelUps = 0 } }, "tb_loss3")
		KC.advance(0.1)
		T.check(not LS.IsOpen(), "tb loss: a won round shows no loss screen")
		BC.HandleState("End", H.ringLoss("tb_loss3", "Fainted", { Outcome = "Left" }), "tb_loss3")
		KC.advance(0.1)
		T.check(LS.IsOpen() and not H.shown(H.resultCard()) and tostring(H.widget("Sub").Text):find("your whole team fainted after round 2", 1, true) ~= nil,
			"tb loss: the Fainted loss shows the screen, with the team's fate as its line", H.widget("Sub") and tostring(H.widget("Sub").Text) or "no Sub")
		LS.Hide()
		H.reset()
		KC.advance(20)

		-- ...after the last round's floor was already freed
		H.start("tb_loss4", "Ring")
		BC.HandleState("End", { BattleId = "tb_loss4", Mode = "Ring", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
			Rewards = { Won = true, Next = 3, Round = 2, Cash = 5, Xp = 32, Tokens = 0, Record = false, Seconds = 1, LevelUps = 0 } }, "tb_loss4")
		KC.advance(20)
		T.check(BC.GetBattle() == nil, "tb loss: (setup) the floor is freed")
		BC.HandleState("End", H.ringLoss("tb_loss4", "Fainted", { Outcome = "Left" }), "tb_loss4")
		KC.advance(0.1)
		T.check(LS.IsOpen() and not H.shown(H.resultCard()), "tb loss: the final End after the floor was freed shows the screen too")
		LS.Hide()
		H.reset()

		-- a Dungeon wipe: BattleState's End first (the plain card), the run's End replaces it
		H.start("tb_loss5", "Dungeon")
		BC.HandleState("End", { BattleId = "tb_loss5", Mode = "Dungeon", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe", Rewards = { Dungeon = true, Extra = { Floor = 3, Room = 2 } } }, "tb_loss5")
		KC.toClient("DungeonState", "End", H.dungeonWipe(true))
		KC.advance(0.1)
		T.check(LS.IsOpen() and H.widget("Title").Text == "KNOCKED OUT" and tostring(H.widget("Sub").Text):find("Flooded Vaults", 1, true) ~= nil, "tb loss: a dungeon wipe shows the screen", H.widget("Sub") and tostring(H.widget("Sub").Text) or "no Sub")
		T.check(not H.shown(H.resultCard()), "tb loss: ...the KNOCKED OUT card does not stay under it")
		local DC = H.mod("DungeonController")
		T.check(DC.GetState().End == nil, "tb loss: ...and the End card stays closed")
		KC.advance(20)
		LS.Hide()
		H.reset()

		-- a cleared floor and a quit keep today's End card
		KC.toClient("DungeonState", "End", { Floor = 3, Name = "Flooded Vaults", Cleared = true, Reason = "Cleared", Room = 4, Totals = { Cash = 10, Tokens = 4, Xp = 30, Gems = 0 }, NewBest = true })
		KC.advance(0.3)
		T.check(not LS.IsOpen() and DC.GetState().End ~= nil, "tb loss: a cleared floor keeps today's End card")
		KC.advance(16)
		KC.toClient("DungeonState", "End", { Floor = 3, Name = "Flooded Vaults", Cleared = false, Reason = "Quit", Room = 2, Totals = { Cash = 0, Tokens = 0, Xp = 0, Gems = 0 } })
		KC.advance(0.3)
		T.check(not LS.IsOpen() and DC.GetState().End ~= nil, "tb loss: a quit keeps today's End card")
		KC.advance(16)

		SF.Play = realPlay
		H.reset()
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.3)
		KC.flushErrors("client_tb_loss_screen")
	end)

	S.client_tb_loss_fight_again = guarded("client_tb_loss_fight_again", function()
		local LS = H.req("client/Controllers/LossScreen")
		local BC = H.mod("BattleController")
		if not T.check(type(LS) == "table", "tb loss: client/Controllers/LossScreen loads") then
			return
		end
		local Attr = KC.env().Attr.InBattle
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		H.feed()
		H.reset()
		KC.advance(2)

		-- a boss start, pressed twice during the return delay
		H.start("tb_again1", "Ring")
		local boss = H.ringLoss("tb_again1")
		boss.Rewards.Start = 20
		BC.HandleState("End", boss, "tb_again1")
		KC.advance(0.1)
		local n0 = #Mock.RemoteLog
		Mock.Click(H.widget("FightAgain"))
		Mock.Click(H.widget("FightAgain"))
		KC.advance(1)
		T.check(#H.requests("BattleRequest", n0) == 0 and H.widget("FightAgain").Text == "Returning...", "tb loss: Fight again waits while InBattle is set (Review Focus 5)", tostring(#H.requests("BattleRequest", n0)))
		LocalPlayer:SetAttribute(Attr, nil)
		KC.advance(0.5)
		local calls = H.requests("BattleRequest", n0)
		T.check(#calls == 1 and calls[1].args[1] == "Ring" and calls[1].args[2] == 20, "tb loss: ...then fires Ring(Start) exactly once (a boss start kept)", tostring(#calls))
		-- the server refused: no InBattle comes; the screen stays and the button works again
		T.check(LS.IsOpen(), "tb loss: the screen waits for the next battle")
		KC.advance(3)
		T.check(LS.IsOpen() and H.widget("FightAgain").Text == "Fight again", "tb loss: a refusal leaves the screen, the button re-armed", H.widget("FightAgain").Text)
		KC.advance(1.1)
		n0 = #Mock.RemoteLog
		Mock.Click(H.widget("FightAgain"))
		KC.advance(0.3)
		T.eq(#H.requests("BattleRequest", n0), 1, "tb loss: ...a second try sends one request")
		-- accepted: InBattle set by the new run closes the screen
		LocalPlayer:SetAttribute(Attr, "R9")
		KC.advance(0.3)
		T.check(not LS.IsOpen(), "tb loss: the next battle closes the screen")
		H.reset()
		KC.advance(20)

		-- the attribute never clears: the press gives up, sends nothing, never says "Finish your battle first"
		H.start("tb_again2", "Ring")
		BC.HandleState("End", H.ringLoss("tb_again2"), "tb_again2")
		KC.advance(0.1)
		n0 = #Mock.RemoteLog
		Mock.Click(H.widget("FightAgain"))
		KC.advance(8)
		T.check(#H.requests("BattleRequest", n0) == 0 and H.widget("FightAgain").Text == "Fight again", "tb loss: a player stuck in the battle gets the button back, no request", H.widget("FightAgain").Text)
		LS.Hide()
		H.reset()
		KC.advance(20)

		-- the Dungeon: solo
		LocalPlayer:SetAttribute(Attr, "D7")
		KC.toClient("DungeonState", "End", H.dungeonWipe(true))
		KC.advance(0.1)
		n0 = #Mock.RemoteLog
		T.check(H.shown(H.widget("FightAgain")), "tb loss: a solo wipe offers Fight again")
		Mock.Click(H.widget("FightAgain"))
		KC.advance(1)
		T.check(#H.requests("DungeonRequest", n0) == 0 and H.widget("FightAgain").Text == "Returning...", "tb loss: the Dungeon's Fight again waits for the run attribute too")
		LocalPlayer:SetAttribute(Attr, nil)
		KC.advance(0.5)
		local solo = H.requests("DungeonRequest", n0)
		T.check(#solo == 1 and solo[1].args[1] == "Solo" and solo[1].args[2] == 3, "tb loss: ...then DungeonRequest('Solo', floor) once", tostring(#solo))
		LS.Hide()
		H.reset()
		KC.advance(3)

		-- a party member: no Fight again
		LocalPlayer:SetAttribute(Attr, "D8")
		KC.toClient("DungeonState", "End", H.dungeonWipe(false, "Timeout"))
		KC.advance(0.1)
		T.check(LS.IsOpen() and not H.shown(H.widget("FightAgain")) and H.shown(H.widget("EditTeam")) and H.shown(H.widget("CloseButton")), "tb loss: a party member gets no Fight again, only Edit team and Close")
		LS.Hide()
		H.reset()
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.3)
		KC.flushErrors("client_tb_loss_fight_again")
	end)

	S.client_tb_loss_phone = guarded("client_tb_loss_phone", function()
		local LS = H.req("client/Controllers/LossScreen")
		if not T.check(type(LS) == "table", "tb loss phone: client/Controllers/LossScreen loads") then
			return
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		local GuiService = game:GetService("GuiService")
		H.feed()
		H.reset()
		for _, size in ipairs({ { 844, 390 }, { 390, 844 } }) do
			local w, h = size[1], size[2]
			local tag = fmt("tb loss phone %dx%d", w, h)
			Mock.SetViewport(w, h)
			KC.advance(0.1)
			LS.Show({ Mode = "Ring", Title = "RUN OVER", Sub = "Champion Ring: the champion won round 2", Pets = ROWS,
				Lines = { { "Rounds won: 1" }, { "+$40 Cash" }, { "+35 Pet XP" }, { "Best: round 1" } }, Start = 1, OnFightAgain = function() end })
			KC.advance(0.6)
			local card = H.card()
			local x, y = card.AbsolutePosition.X, card.AbsolutePosition.Y
			local cw, ch = card.AbsoluteSize.X, card.AbsoluteSize.Y
			T.check(x >= 16 - 0.5 and x + cw <= w - 16 + 0.5, tag .. ": the card is within 16 px gutters", fmt("x %d..%d", x, x + cw))
			local inset = GuiService:GetGuiInset()
			T.check(y >= inset.Y - 0.5 and y + ch <= h + 0.5, tag .. ": nothing under the top bar, nothing off the screen", fmt("y %d..%d, inset %d", y, y + ch, inset.Y))
			for _, name in ipairs({ "FightAgain", "EditTeam", "CloseButton" }) do
				local b = H.widget(name)
				T.check(b and b.AbsoluteSize.Y >= 44, tag .. ": " .. name .. " >= 44 px", b and tostring(b.AbsoluteSize.Y) or "missing")
				local inside = b and b.AbsolutePosition.X >= x - 0.5 and b.AbsolutePosition.X + b.AbsoluteSize.X <= x + cw + 0.5 and b.AbsolutePosition.Y >= y - 0.5 and b.AbsolutePosition.Y + b.AbsoluteSize.Y <= y + ch + 0.5
				T.check(inside, tag .. ": " .. name .. " is inside the card")
			end
			for i = 1, 3 do
				local row = H.widget("PetRow" .. i)
				T.check(row and row.AbsolutePosition.Y + row.AbsoluteSize.Y <= y + ch + 0.5 and row.AbsolutePosition.X + row.AbsoluteSize.X <= x + cw + 0.5, tag .. ": PetRow" .. i .. " is inside the card")
			end
			local small = {}
			for _, d in ipairs(card:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and KC.isShown(d) then
					local scale = card.AbsoluteSize.X / math.max(1, card.Size.X.Offset)
					if d.TextSize * scale < 14 - 0.01 then
						small[#small + 1] = d.Name .. "=" .. fmt("%.1f", d.TextSize * scale)
					end
				end
			end
			T.check(#small == 0, tag .. ": every text >= 14 px", table.concat(small, ", "))
			LS.Hide()
		end
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.3)
		KC.flushErrors("client_tb_loss_phone")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
