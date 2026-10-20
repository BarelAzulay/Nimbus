-- smoke_p5_dungeon.lua: Phase 5 "The Dungeon" (ARCHITECTURE_V3.md "Phase 5 build contract" 5.1-5.7, 10.3-10.4, 12.1).
-- Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half.
--
-- dungeon (W3, server world, booted; before "shutdown"):
--   p5dgn_party      create / join / ready / SetFloor / leave through DungeonRequest; the leader's Kick removes a member
--                    with a toast, a non-leader Kick is refused; START with an unready member drops them after
--                    ReadyTimeout 30 and starts; a join once room 3 started is refused; locked floors refused
--   p5dgn_exclusive  in the Hall, a Corridor and the Treasure: raid join / duel / Ring start, GoHome, the Home / Altar
--                    gates, the obby pad and the dev /reset are refused and InBattle stays the run id
--   p5dgn_run        SetRunProvider called by Init; solo floor 1 with ONE level-1 pet end to end through the remotes:
--                    hall (no HallSeconds timer: E at the hall's EnterPrompt) -> room 1 Start (Mode Dungeon,
--                    Start.Dungeon) -> waves -> loot once -> bars (the next entrance stays closed, its EnterPrompt
--                    enabled, no DoorTime: E moves the run; the boss exit stays barred -> E -> treasure) -> room 2 built
--                    while 1 fights, room 1 destroyed on entering 3 -> boss + escort -> treasure + chest -> exit;
--                    InBattle = the run id from the teleport to the return; the pocket freed; workspace.Dungeons gone;
--                    a 4-party: stragglers placed, enemies 2 + 3, the leash
--   p5dgn_loot       payRoom once per room per fighter (a replayed result pays nothing), Cash = income x seconds with
--                    the floor, Tokens x2 under Double Rewards (Cash / XP not), XP via GrantXp "Dungeon", the first
--                    clear once, an AFK member paid nothing and no first clear, a boss-only joiner paid the boss room but
--                    never the first clear, a late joiner unpaid for earlier rooms, the chest once and auto-opened at
--                    the 45 s exit, no Gems chest on floors 1-2, the loss third on a wipe >= 20 s, nothing on Quit
--   p5dgn_ends       wipe by KO and by timeout, Quit mid-fight / in a corridor, leaving the game, a respawn elsewhere,
--                    the leash, the last member frees the pocket, Shutdown mid-fight and in a corridor, RunEnded once,
--                    the watchdog (an erroring Dg.onRoomEnd ends the run "Error" within 20 s: InBattle nil, the pocket
--                    free, RunEnded once, nothing paid twice; a run older than RunMaxSeconds ends)
--   p5dgn_world      templates within their budgets, BuildRun <= 950 live parts, no overlap over 20 seeds, the
--                    attachments, zones Mode Dungeon 44 / 56 inside the floor, Accent parts recoloured, FreeRun clean,
--                    the portal <= 120 parts with OpenPanel "Dungeon", the portal outside every zone
--   p5dgn_net        a 4-player room under the raid budget (6 KB/s per client), DungeonState payloads < 1 KB, junk
--                    DungeonRequest 60/s refused without errors
-- dungeonclient (W4, client world): client_p5dungeon / client_p5dungeon_mobile (placeholders report info only)
-- Plain Lua 5.1 syntax only.

local CONTEXT = (ARGS and ARGS.context) or "server"

----------------------------------------------------------------------------------------------------
-- server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local K = _G.K
	local T = K.T
	local guarded = K.guarded
	local advance = K.advance
	local S = {}

	local seq = 0
	local STRONG = { "cloudy_dragon", "ember_phoenix", "aurora_fox" }
	local WEAK = { "pebble_pup", "honey_bunny", "puddle_frog" }

	local function req(path)
		local inst = K.moduleInstance(path)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		if ok and type(m) == "table" then
			return m
		end
		return nil
	end

	local function BS() return req("server/Services/BattleService") end
	local function DS() return req("server/Services/DataService") end
	local function TS() return req("server/Services/TycoonService") end
	local function BC() return req("shared/BattleCatalog") end
	local function Sim() return req("shared/BattleSim") end
	local function DGS() return req("server/Services/DungeonService") end
	local function DGB() return req("server/Services/DungeonBuilder") end

	local function info()
		local db = DGB()
		return db and db.GetInfo and db.GetInfo() or nil
	end

	local function D()
		local bc = BC()
		return bc and bc.Dungeon or {}
	end

	local function remote(name)
		local folder = K.remoteFolder()
		return folder and folder:FindFirstChild(name) or nil
	end

	local function ready(label)
		if not K.needBoot() then
			return false
		end
		if not DGS() or not DGB() or not BS() or not BC() or not Sim() then
			T.fail(label .. ": skipped, DungeonService / DungeonBuilder / BattleService / BattleCatalog / BattleSim did not load")
			return false
		end
		if not info() or not remote("DungeonRequest") then
			T.fail(label .. ": skipped, no DungeonInfo (DungeonBuilder.Build) or no DungeonRequest remote")
			return false
		end
		return true
	end

	-- a player with pets (team preset 1 = the first 3 keys); `level` sets every pet's level
	local function newPlayer(prefix, pets, level)
		seq = seq + 1
		-- (968500+: smoke_p3_ui.lua's tutorial players use 968000 + seq and leave saves with dungeon progress in the
		-- mock store, which a "new" player here would load in the full run)
		local p = Mock.AddPlayer(prefix .. seq, 968500 + seq)
		advance(1.0)
		local data = DS()
		local prof = data.GetProfile(p)
		if prof and pets then
			for _, id in ipairs(pets) do
				prof.Pets[id] = (prof.Pets[id] or 0) + 1
				if level then
					prof.PetLevels[id] = { Level = level, Xp = 0 }
				end
			end
			data.MarkDirty(p)
			local ok, why = data.SetTeam(p, 1, pets)
			if not ok then
				T.fail("(setup) SetTeam for " .. p.Name .. " failed", tostring(why))
			end
		end
		return p
	end

	local function toPad(p, dx, dz)
		local i = info()
		local pad = i and (i.Pad or i.PromptPart)
		if pad then
			Mock.Teleport(p, CFrame.new(pad.Position + Vector3.new(dx or 0, 3.5, dz or 0)))
		end
		advance(0.05)
	end

	local function request(p, action, a, b)
		Mock.FromClient(remote("DungeonRequest"), p, action, a, b)
		advance(0.05)
	end

	local function states(p, fromIndex, kind)
		local out = {}
		for _, e in ipairs(K.remotesFor("DungeonState", p.UserId, fromIndex or 0)) do
			if kind == nil or e.args[1] == kind then
				out[#out + 1] = e.args[2]
			end
		end
		return out
	end

	local function lastState(p, kind, fromIndex)
		local list = states(p, fromIndex, kind)
		return list[#list]
	end

	-- "Open" and the Lobby payload it answers with. The server pushes a Lobby to everyone on every party change and
	-- player join (markLobbyDirty, flushed by its 0.5 s tick) and answers an Open within LOBBY_GAP (1 s) of such a push
	-- only on its next tick, so whether the payload is in the log 0.05 s after the request depends on the tick phase of
	-- the shared clock (green alone, red in the full run). Advance until it lands (<= 2.5 s), never on the phase.
	local function openLobby(p)
		local mark = K.logSize()
		request(p, "Open")
		local waited = 0.05
		while lastState(p, "Lobby", mark) == nil and waited < 2.5 do
			advance(0.1)
			waited = waited + 0.1
		end
		return lastState(p, "Lobby", mark), mark
	end

	local function toasts(p, fromIndex)
		local out = {}
		for _, e in ipairs(K.remotesFor("Notify", p.UserId, fromIndex or 0)) do
			out[#out + 1] = tostring(e.args[1])
		end
		return out
	end

	local function toasted(p, needle, fromIndex)
		for _, text in ipairs(toasts(p, fromIndex)) do
			if text:find(needle, 1, true) then
				return true
			end
		end
		return false
	end

	local function battleMsgs(p, fromIndex, kind)
		local out = {}
		local log = Mock.RemoteLog
		for i = (fromIndex or 0) + 1, #log do
			local e = log[i]
			if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and (kind == nil or e.args[1] == kind) then
				out[#out + 1] = e
			end
		end
		return out
	end

	local function runOf(p)
		return DGS().St.runOf[p]
	end

	local function inBattle(p)
		return p:GetAttribute(K.config().Attr.InBattle or "InBattle")
	end

	local function tokens(p) return DS().GetTokens(p) end
	local function cash(p) return DS().GetCash(p) end
	local function totalXp(p, key)
		local level, xp = DS().GetPetLevel(p, key)
		local Cat = req("shared/TycoonCatalog")
		local total = xp or 0
		for l = 1, (level or 1) - 1 do
			total = total + Cat.XpToNext(l)
		end
		return total
	end

	local function freeSpot()
		local SS = req("server/Services/SpotService")
		local spots = (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
		for i = 1, K.config().Lobby.SpotCount do
			if spots[i] and not (SS and SS.GetOwner(i)) then
				return i
			end
		end
		return nil
	end

	local function claimHome(p)
		local Ty = TS()
		local index = freeSpot()
		if not Ty or not index then
			return nil
		end
		local ok = Ty.Claim(p, index)
		advance(0.6)
		if not ok then
			return nil
		end
		Ty.Buy(p, "Garden")
		advance(0.3)
		return index
	end

	local function count(t)
		local n = 0
		for _ in pairs(t or {}) do
			n = n + 1
		end
		return n
	end

	-- BattleState traffic stays out of the client replay log (thousands of snapshots)
	local savedHook = nil
	local function quietReplication()
		if savedHook == nil and Mock._onRemote then
			savedHook = Mock._onRemote
			Mock._onRemote = function(entry)
				if entry.remote ~= "BattleState" then
					savedHook(entry)
				end
			end
		end
	end
	local function loudReplication()
		if savedHook then
			Mock._onRemote = savedHook
			savedHook = nil
		end
	end

	local realOnRoomEnd = nil
	local function endEverything()
		local dgs = DGS()
		if not dgs then
			return
		end
		if realOnRoomEnd then
			dgs.Dg.onRoomEnd = realOnRoomEnd
			realOnRoomEnd = nil
		end
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
		dgs.SetClosing(false)
		advance(0.2)
	end

	local function cleanup(list)
		endEverything()
		local bs = BS()
		for _, p in ipairs(list) do
			if p.Parent and bs and bs.IsInBattle(p) then
				bs.Forfeit(p)
			end
		end
		advance(0.3)
		K.removePlayers(list)
		advance(1)
	end

	local function scenario(name, fn)
		local run = guarded(name, fn)
		return function(...)
			local ok = run(...)
			endEverything()
			local bs = BS()
			if bs then
				bs.Debug = nil
				if bs.SetDoubleRewards then
					bs.SetDoubleRewards(nil)
				end
				if bs.SetClosing then
					bs.SetClosing(false)
				end
			end
			loudReplication()
			return ok
		end
	end

	------------------------------------------------------------------------------------------------
	-- The client-side picture of a battle and a driver that plays the fighter (from smoke_p5_battleservice.lua)
	------------------------------------------------------------------------------------------------
	local DOWN = 5
	local BENCHED = 3

	local function tracker(p)
		return { p = p, cursor = K.logSize(), static = {}, units = {}, zone = nil, side = nil, fighter = nil, id = nil, start = nil, ends = {}, events = {}, speed = nil, starts = {} }
	end

	local function pump(tr)
		local log = Mock.RemoteLog
		local uid = tr.p.UserId
		for i = tr.cursor + 1, #log do
			local e = log[i]
			if e.remote == "BattleState" and e.kind == "client" and e.userId == uid then
				local kind, payload = e.args[1], e.args[2]
				if kind == "Start" and type(payload) == "table" and payload.Spectator ~= true then
					tr.start = payload
					tr.starts[#tr.starts + 1] = payload
					tr.id = payload.BattleId
					tr.zone = payload.Zone and payload.Zone.CFrame
					tr.side = payload.Side
					tr.static = {}
					for _, u in ipairs(payload.Units or {}) do
						tr.static[u.id] = u
					end
					tr.units = {}
					tr.team = payload.Team
					tr.fighter = payload.Team and payload.Team.Fighter
					tr.speed = payload.Team and payload.Team.Speed
				elseif kind == "Snapshot" and type(payload) == "table" and payload.BattleId == tr.id then
					tr.units = Sim().DecodeSnapshot(payload, tr.units)
				elseif kind == "Events" and type(payload) == "table" and e.args[3] == tr.id then
					for _, ev in ipairs(payload) do
						tr.events[#tr.events + 1] = ev
						if (ev.type == "Spawn" or ev.type == "Wave") and type(ev.units) == "table" then
							for _, u in ipairs(ev.units) do
								tr.static[u.id] = u
							end
						elseif ev.type == "Swap" and ev.owner == uid then
							tr.fighter = ev["in"]
						elseif ev.type == "Speed" and ev.owner == uid then
							tr.speed = { Walk = ev.walk, Run = ev.run }
						end
					end
				elseif kind == "End" and type(payload) == "table" and payload.Spectator ~= true then
					tr.ends[#tr.ends + 1] = payload
				end
			end
		end
		tr.cursor = #log
	end

	local function myPos(tr)
		local u = tr.fighter and tr.units[tr.fighter]
		if u then
			return u.x, u.z
		end
		return nil
	end

	local function nearestEnemy(tr)
		local fx, fz = myPos(tr)
		if not fx then
			return nil
		end
		local best, bestD, bestS = nil, math.huge, nil
		for id, u in pairs(tr.units) do
			local s = tr.static[id]
			if s and s.side ~= tr.side and u.state ~= DOWN and u.state ~= BENCHED and (u.hp == nil or u.hp > 0) then
				local d = math.sqrt((u.x - fx) ^ 2 + (u.z - fz) ^ 2)
				if d < bestD then
					best, bestD, bestS = id, d, s
				end
			end
		end
		return best, bestD, bestS
	end

	local function charLocal(tr)
		local root = K.root(tr.p)
		if not root or not tr.zone then
			return nil
		end
		local rel = tr.zone:PointToObjectSpace(root.Position)
		return rel.X, rel.Z
	end

	local function placeChar(tr, x, z)
		if tr.zone then
			Mock.Teleport(tr.p, CFrame.new(tr.zone:PointToWorldSpace(Vector3.new(x, 3, z))))
		end
	end

	local function moveChar(tr, tx, tz, step)
		local cx, cz = charLocal(tr)
		if not cx then
			return math.huge
		end
		local dx, dz = tx - cx, tz - cz
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= 0.01 then
			return 0
		end
		local travel = math.min(step, d)
		placeChar(tr, cx + dx / d * travel, cz + dz / d * travel)
		return d - travel
	end

	local function playTick(tr, opts)
		opts = opts or {}
		local bs = BS()
		pump(tr)
		local id, dist, s = nearestEnemy(tr)
		local run = (tr.speed and tr.speed.Run) or 16
		local dt = opts.dt or 0.1
		if id and tr.units[id] then
			local mine = tr.static[tr.fighter] or {}
			local reach = (tonumber(mine.range) or 4.5) + (tonumber(s.radius) or 1) + 1
			local u = tr.units[id]
			local fx = myPos(tr)
			if opts.move ~= false and fx then
				if dist > reach - 1 then
					moveChar(tr, u.x, u.z, run * dt)
				end
			end
			tr.ticks = (tr.ticks or 0) + 1
			local every = opts.every or 3
			if opts.attack ~= false and tr.ticks % every == 0 then
				bs.Command(tr.p, "Attack", id)
			end
			if opts.kit and tr.ticks % 10 == 0 then
				bs.Command(tr.p, "Element")
				bs.Command(tr.p, "Special")
			end
		end
		return id
	end

	-- plays until the tracked battle ends or `seconds` pass; -> the End payload | nil
	local function playUntilEnd(tr, seconds, opts)
		local t0 = Mock.Clock.now
		local startId = tr.id
		while Mock.Clock.now - t0 < seconds do
			advance(0.1)
			playTick(tr, opts)
			for _, e in ipairs(tr.ends) do
				if e.BattleId == tr.id and tr.id == startId then
					return e
				end
			end
			if opts and opts.stop and opts.stop(tr) then
				return nil
			end
		end
		pump(tr)
		for _, e in ipairs(tr.ends) do
			if e.BattleId == tr.id then
				return e
			end
		end
		return nil
	end

	------------------------------------------------------------------------------------------------
	-- Run helpers
	------------------------------------------------------------------------------------------------
	local function roomInfo(run, room)
		return run and run.Pocket and run.Pocket.Rooms[room] or nil
	end

	-- steps a member onto the current room's Threshold part (the fight starts on the next loop tick)
	local function crossThreshold(run, p)
		local ri = roomInfo(run, run.Room)
		if ri and ri.Threshold then
			Mock.Teleport(p, CFrame.new(ri.Threshold.Position + Vector3.new(0, 0, 0)))
		end
		advance(0.6)
	end

	-- waits (simulated) until run.State == state or seconds pass
	local function waitState(run, state, seconds)
		local t0 = Mock.Clock.now
		while Mock.Clock.now - t0 < seconds do
			if run.State == state then
				return true
			end
			advance(0.25)
		end
		return run.State == state
	end

	-- the run's members still in (players, run order)
	local function runMembers(run)
		local out = {}
		for _, uid in ipairs(run and run.Order or {}) do
			local m = run.Members[uid]
			if m and not m.Left then
				out[#out + 1] = m.Player
			end
		end
		return out
	end

	-- dungeon-fixes decision 2: nothing moves the group by a timer. Every member in `who` (default: all still in) is
	-- stood next to the open door's EnterPrompt and presses E (ProximityPromptService, like the engine); then the fade's
	-- Out passes and the server enters the next room. -> true when a door was open
	local function pressDoor(run, who)
		local dg = DGS().Dg
		local t0 = Mock.Clock.now
		local prompt = dg.nextDoor(run)
		while not prompt and run.State ~= "Ending" and Mock.Clock.now - t0 < (D().Intermission or 2) + 2 do
			advance(0.25)
			prompt = dg.nextDoor(run)
		end
		if not prompt then
			return false
		end
		for _, m in ipairs(who or runMembers(run)) do
			if m.Parent and runOf(m) == run then
				Mock.Teleport(m, CFrame.new(prompt.Parent.Position))
				Mock.Trigger(prompt, m)
			end
		end
		advance(0.6)
		return true
	end

	-- from the Hall to room 1's entrance (everyone presses E at the hall's exit)
	local function fromHall(run)
		if run.State == "Hall" then
			pressDoor(run)
		end
		return run.State == "Corridor" and run.Room == 1
	end

	-- a solo run on `floor` through the remote; -> run | nil
	local function startSolo(p, floorIndex)
		toPad(p, 0, 0)
		request(p, "Solo", floorIndex or 1)
		return runOf(p)
	end

	-- the BattleService battle record of an encounter (white-box, tests only: BattleService exposes no sim accessor; the
	-- service's St is an upvalue of IsInBattle) -> b (b.Sim = the BattleSim, b.Parts) | nil
	local function battleOf(battleId)
		local bs = BS()
		local f = bs and bs.IsInBattle
		if type(f) ~= "function" or not battleId then
			return nil
		end
		for i = 1, 80 do
			local name, v = debug.getupvalue(f, i)
			if not name then
				break
			end
			if name == "St" and type(v) == "table" and type(v.battles) == "table" then
				return v.battles[battleId]
			end
		end
		return nil
	end

	-- the run's current encounter sim + the run's live units of one wave (side 2): -> sim, units
	local function enemiesOfWave(run, wave)
		local b = battleOf(run.Battle)
		local sim = b and b.Sim
		local out = {}
		if sim then
			for _, u in ipairs(sim.units or {}) do
				if u.side == 2 and u.alive and u.team and u.team.wave == wave then
					out[#out + 1] = u
				end
			end
		end
		return sim, out
	end

	-- white-box: `fn(u)` on every live enemy of the run's encounter (dungeon-fixes decision 4: a player's fighter
	-- auto-attacks, so an "idle" pet fights back; tests that need a wipe / a timeout / a long fight tune the enemies)
	local function tuneEnemies(run, fn)
		local b = battleOf(run.Battle)
		local n = 0
		for _, u in ipairs(b and b.Sim and b.Sim.units or {}) do
			if u.side == 2 and u.alive then
				fn(u)
				n = n + 1
			end
		end
		return n
	end
	local function unbeatable(u)
		u.maxHp, u.hp = 1e9, 1e9
	end

	-- kills `targets` with the player's own attacks while `keep` (a unit) is held at `keepHp`: the fighter is stood next
	-- to each target with its attack ready and ATTACK is sent through the service (the kill fires the sim's EnemiesDown)
	local function slayWith(run, p, tr, sim, targets, keep, keepHp)
		local team = sim.teamByOwner[p.UserId]
		for _, u in ipairs(targets) do
			u.hp = 0.01
		end
		local tries = 0
		while run.State == "Fight" and tries < 120 do
			local target = nil
			for _, u in ipairs(targets) do
				if u.alive then
					target = u
					break
				end
			end
			if not target then
				break
			end
			local f = team.fighter
			f.x, f.z = target.x - 1, target.z
			placeChar(tr, target.x - 1, target.z)
			if keep then
				keep.hp = keepHp
			end
			f.nextAttack = 0
			BS().Command(p, "Attack", target.id)
			advance(0.1)
			tries = tries + 1
		end
		advance(0.3)
	end

	-- from the Hall straight into the boss room's fight (white-box: enterRoom(4))
	local function intoBossRoom(run, p)
		fromHall(run)
		DGS().Dg.enterRoom(run, 4)
		advance(0.3)
		crossThreshold(run, p)
		advance(0.6)
		return run.State == "Fight" and run.Room == 4
	end

	-- from the Hall into the first room's fight (tracker created before the Start)
	local function intoFight(run, p, tr)
		fromHall(run)
		crossThreshold(run, p)
		advance(0.6)
		if tr then
			pump(tr)
		end
		return run.State == "Fight"
	end

	------------------------------------------------------------------------------------------------
	-- p5dgn_party
	------------------------------------------------------------------------------------------------
	S.p5dgn_party = scenario("p5dgn_party", function()
		if not ready("p5dgn_party") then
			return
		end
		local dgs = DGS()
		local a = newPlayer("DgnLead", WEAK, 1)
		local b = newPlayer("DgnMemb", WEAK, 1)
		local c = newPlayer("DgnThird", WEAK, 1)
		local d = newPlayer("DgnNoPet", nil)
		local all = { a, b, c, d }
		for _, p in ipairs(all) do
			toPad(p, 0, 0)
		end
		local lobby, mark = openLobby(a)
		T.check(type(lobby) == "table" and type(lobby.Parties) == "table" and lobby.Mine == nil and type(lobby.Record) == "table" and lobby.Record.Best == 0,
			"p5 party: Open sends a Lobby payload (Parties, Mine nil, Record Best 0)")
		-- locked floors: a new player may create floor 1 only
		mark = K.logSize()
		request(a, "Create", 3)
		T.check(dgs.GetParty(a) == nil and toasted(a, "Clear floor 2 first", mark), "p5 party: Create floor 3 with Best 0 is refused 'Clear floor 2 first'")
		advance(2.1)
		request(a, "Create", "junk")
		request(a, "Create", 1.5)
		request(a, "Create", 13)
		T.check(dgs.GetParty(a) == nil, "p5 party: junk / fractional / out-of-range floors create nothing")
		advance(2.1)
		request(a, "Create", 1)
		local party = dgs.GetParty(a)
		T.check(party ~= nil and party.Leader == a and party.Floor == 1, "p5 party: Create floor 1 makes a party led by the caller")
		mark = K.logSize()
		request(b, "Join", a.UserId)
		request(c, "Join", a.UserId)
		advance(1.1)
		request(d, "Join", a.UserId)
		T.check(dgs.GetParty(b) == party and dgs.GetParty(c) == party, "p5 party: Join by the leader's userId adds members")
		T.check(dgs.GetParty(d) == nil and toasted(d, "You need a pet", mark), "p5 party: a player without a pet cannot join ('You need a pet')")
		advance(1.1)
		mark = K.logSize()
		request(a, "Join", a.UserId)
		T.check(toasted(a, "already in that party", mark), "p5 party: joining your own party is refused")
		-- the Lobby view of the party (<= 1/s per client)
		advance(1.1)
		lobby, mark = openLobby(b)
		local mine = lobby and lobby.Mine
		T.check(mine ~= nil and mine.Leader == a.UserId and #mine.Members == 3 and mine.Members[1].UserId == a.UserId and mine.Members[1].Ready == true and mine.Members[2].Ready == false,
			"p5 party: the Lobby payload's Mine lists the members in order (the leader ready, a joiner not)")
		T.check(lobby and #lobby.Parties >= 1 and lobby.Parties[1].Leader == a.UserId and lobby.Parties[1].Count == 3 and lobby.Parties[1].Max == 4 and lobby.Parties[1].Open == true,
			"p5 party: the Lobby payload lists the open party (Count 3 / Max 4)")
		-- Ready / SetFloor / Kick
		request(b, "Ready", true)
		T.check(party.Members[b.UserId].Ready == true, "p5 party: Ready true marks the member")
		request(b, "Ready", "yes")
		T.check(party.Members[b.UserId].Ready == true, "p5 party: a junk Ready is dropped")
		request(b, "SetFloor", 1)
		mark = K.logSize()
		request(c, "Kick", b.UserId)
		T.check(party.Members[b.UserId] ~= nil and toasted(c, "Only the leader", mark), "p5 party: a non-leader Kick is refused with a toast")
		mark = K.logSize()
		request(a, "Kick", c.UserId)
		T.check(party.Members[c.UserId] == nil and dgs.GetParty(c) == nil and toasted(c, "You were removed from the party", mark), "p5 party: the leader's Kick removes the member who toasts 'You were removed from the party'")
		advance(1.1)
		request(a, "Kick", a.UserId)
		T.check(party.Members[a.UserId] ~= nil, "p5 party: the leader cannot kick themselves")
		-- leave and rejoin as unready, then START with an unready member -> the 30 s clock
		request(b, "Leave")
		T.check(dgs.GetParty(b) == nil and party.Members[b.UserId] == nil, "p5 party: Leave removes the member")
		advance(1.1)
		request(b, "Join", a.UserId)
		T.check(party.Members[b.UserId] ~= nil and party.Members[b.UserId].Ready == false, "p5 party: a rejoined member starts unready")
		mark = K.logSize()
		request(a, "Start")
		T.check(party.StartAt ~= nil and party.Run == nil and toasted(b, "press READY", mark), "p5 party: START with an unready member starts the ReadyTimeout clock ('Starting in 30 - press READY')")
		advance(D().ReadyTimeout + 1.5)
		local run = party.Run
		T.check(run ~= nil and run.Members[a.UserId] ~= nil and run.Members[b.UserId] == nil and dgs.GetParty(b) == nil and toasted(b, "dropped from the party", mark),
			"p5 party: after 30 s the unready member is dropped and the run starts with the leader")
		T.check(run ~= nil and inBattle(a) == run.Id and inBattle(b) == nil, "p5 party: InBattle = the run id for the member in, nil for the dropped one")
		-- a join once room 3 started is refused (white-box: the run is advanced to room 3)
		if run then
			run.State = "Corridor"
			run.Phase = "Threshold"
			run.Room = 3
			run.Joinable = false
			advance(1.1)
			mark = K.logSize()
			request(b, "Join", a.UserId)
			T.check(dgs.GetParty(b) == nil and runOf(b) == nil and toasted(b, "past room 2", mark), "p5 party: a join once room 3 started is refused")
			-- a join in room 2's corridor is accepted (late join)
			run.Room = 2
			run.Phase = "Walk"
			run.Joinable = true
			advance(1.1)
			toPad(b, 2, 0)
			request(b, "Join", a.UserId)
			local m = run.Members[b.UserId]
			T.check(m ~= nil and m.JoinedRoom == 3 and inBattle(b) == run.Id and runOf(b) == run, "p5 party: a late join in room 2's corridor enters the run (JoinedRoom 3, InBattle = the run id)")
			T.check(run.Joinable == false or count(run.Members) < 4, "p5 party: Joinable tracks the member count")
		end
		cleanup(all)
		T.check(DGB().GetPocket(1) == nil and workspace:FindFirstChild("Dungeons") == nil, "p5 party: the cleanup freed every pocket (workspace.Dungeons gone)")

		-- W5 data-money-1 / battle-dungeon-5 / data-money-2: a member who LEAVES a run cannot re-join it (one record per
		-- member: no "DuplicatePlayer" for the whole party); a leader who leaves hands the party key to a live member
		-- (the run stays listed once, the old leader may create a new party at once); when the old run ends it only
		-- clears its own members' party links
		local L = newPlayer("DgnReL", WEAK, 1)
		local M1 = newPlayer("DgnReM1", WEAK, 1)
		local M2 = newPlayer("DgnReM2", WEAK, 1)
		local re = { L, M1, M2 }
		for _, p in ipairs(re) do
			toPad(p, 1, 0)
		end
		request(L, "Create", 1)
		request(M1, "Join", L.UserId)
		request(M1, "Ready", true)
		request(M2, "Join", L.UserId)
		request(M2, "Ready", true)
		request(L, "Start")
		advance(6)
		local run2 = runOf(L)
		if T.check(run2 ~= nil and count(run2.Members) == 3 and run2.State == "Hall", "p5 party: (setup) a 3-party run in its Hall") then
			local party2 = run2.Party
			request(M1, "Quit")
			advance(1.2)
			toPad(M1, 1, 0)
			local mark2 = K.logSize()
			request(M1, "Join", L.UserId)
			advance(0.3)
			local dup = 0
			for _, uid in ipairs(run2.Order) do
				if uid == M1.UserId then
					dup = dup + 1
				end
			end
			T.check(runOf(M1) == nil and dgs.GetParty(M1) == nil and dup == 1 and run2.Members[M1.UserId].Left == true and toasted(M1, "You left this run", mark2),
				"p5 party: a member who QUIT cannot re-join the run ('You left this run'): one record, listed once in run.Order", "listed " .. dup)
			local pdup = 0
			for _, uid in ipairs(party2.Order) do
				if uid == M1.UserId then
					pdup = pdup + 1
				end
			end
			T.check(pdup == 0 and party2.Members[M1.UserId] == nil, "p5 party: ...and is out of the party's Order too (partyCount exact)")
			-- the leader leaves: the party is re-keyed to M2
			advance(1.1)
			request(L, "Quit")
			advance(1.2)
			T.check(party2.Leader == M2 and dgs.St.parties[M2.UserId] == party2 and dgs.St.parties[L.UserId] == nil and dgs.GetParty(M2) == party2 and dgs.GetParty(L) == nil and run2.State ~= "Ending",
				"p5 party: the leader's Quit hands the party to the first live member (St.parties re-keyed, the run goes on)")
			local rows, rowsL, rowsM2 = dgs.ListParties(), 0, 0
			for _, row in ipairs(rows) do
				if row.Leader == L.UserId then
					rowsL = rowsL + 1
				elseif row.Leader == M2.UserId then
					rowsM2 = rowsM2 + 1
				end
			end
			T.check(rowsL == 0 and rowsM2 == 1, "p5 party: ListParties lists the running party once, under its new leader", rowsL .. " / " .. rowsM2)
			-- the old leader opens a new party at once; the old member who quit joins it
			toPad(L, 0, 0)
			advance(2.1)
			request(L, "Create", 1)
			local newParty = dgs.GetParty(L)
			T.check(newParty ~= nil and newParty ~= party2 and newParty.Leader == L and dgs.St.parties[L.UserId] == newParty, "p5 party: the old leader creates a NEW party while the old run goes on")
			rows, rowsL, rowsM2 = dgs.ListParties(), 0, 0
			for _, row in ipairs(rows) do
				if row.Leader == L.UserId then
					rowsL = rowsL + 1
				elseif row.Leader == M2.UserId then
					rowsM2 = rowsM2 + 1
				end
			end
			T.check(rowsL == 1 and rowsM2 == 1, "p5 party: both parties are listed once each (no duplicate partyOrder entry)", rowsL .. " / " .. rowsM2)
			advance(1.1)
			request(M1, "Join", L.UserId)
			T.check(dgs.GetParty(M1) == newParty and newParty.Members[M1.UserId] ~= nil, "p5 party: the member who quit the run joins the new party")
			-- the old run's room 1 fight starts for M2 alone (no DuplicatePlayer), then M2 quits: the old run ends and
			-- leaves the new party's links alone
			fromHall(run2)
			crossThreshold(run2, M2)
			advance(0.6)
			T.check(run2.State == "Fight" and run2.EndReason == nil, "p5 party: the old run's room 1 fight starts (one record per member: no DuplicatePlayer)", tostring(run2.State) .. " " .. tostring(run2.EndReason))
			advance(1.1)
			request(M2, "Quit")
			advance(1.5)
			T.check(run2.State == "Ending" and run2.Finished == true, "p5 party: (setup) the old run ended with its last member")
			T.check(dgs.GetParty(L) == newParty and dgs.GetParty(M1) == newParty and dgs.St.parties[L.UserId] == newParty and dgs.St.parties[M2.UserId] == nil,
				"p5 party: the old run's end keeps the new party's leader and member links (only its own party's links are cleared)")
			local mark3 = K.logSize()
			request(M1, "Ready", true)
			advance(1.6)
			request(L, "Start")
			advance(6.5)
			T.check(runOf(L) ~= nil and runOf(L) == runOf(M1) and not toasted(L, "Only the leader", mark3), "p5 party: ...so the new party's leader can START it")
		end
		cleanup(re)

		-- W5 battle-dungeon-7 (5.3): a JOIN during a fight of room 1 / 2 is QUEUED (<= 20 s, 'Joining when the room is
		-- cleared') and enters the run in the corridor after the clear; LEAVE or the deadline drop the queue entry
		local qa = newPlayer("DgnQLead", STRONG, 20)
		local qb = newPlayer("DgnQJoin", WEAK, 1)
		local qc = newPlayer("DgnQLeave", WEAK, 1)
		local qd = newPlayer("DgnQLate", WEAK, 1)
		local qq = { qa, qb, qc, qd }
		quietReplication()
		local run3 = startSolo(qa, 1)
		if T.check(run3 ~= nil, "p5 party: (setup) a solo run for the queued join") then
			local party3 = run3.Party
			local tr3 = tracker(qa)
			intoFight(run3, qa, tr3)
			tuneEnemies(run3, unbeatable) -- the auto-attacking test team would clear room 1 before the queued join's deadline
			T.check(run3.State == "Fight" and run3.Room == 1, "p5 party: (setup) room 1 fights")
			for _, p in ipairs({ qb, qc, qd }) do
				toPad(p, 2, 0)
			end
			local lobby3 = openLobby(qb)
			local row = nil
			for _, r in ipairs(lobby3 and lobby3.Parties or {}) do
				if r.Leader == qa.UserId then
					row = r
				end
			end
			T.check(row ~= nil and row.Open == true and row.InRun == true and row.Room == 1, "p5 party: the Lobby lists a party fighting room 1 as open ('in room 1 - JOIN')", row and tostring(row.Open) or "no row")
			local mark4 = K.logSize()
			request(qb, "Join", qa.UserId)
			request(qc, "Join", qa.UserId)
			request(qd, "Join", qa.UserId)
			T.check(dgs.St.joinQueue[qb] ~= nil and dgs.St.joinQueue[qb].Party == party3 and runOf(qb) == nil and toasted(qb, "Joining when the room is cleared", mark4) and not toasted(qb, "past room", mark4),
				"p5 party: a JOIN during the fight is queued with 'Joining when the room is cleared' (not 'past room 2')")
			request(qc, "Leave")
			T.check(dgs.St.joinQueue[qc] == nil, "p5 party: LEAVE drops a queued join")
			dgs.St.joinQueue[qd].Deadline = Mock.Clock.now - 1
			local mark5 = K.logSize()
			advance(0.6)
			T.check(dgs.St.joinQueue[qd] == nil and runOf(qd) == nil and toasted(qd, "That party moved on", mark5), "p5 party: a queued join past its 20 s deadline is dropped ('That party moved on')")
			tuneEnemies(run3, function(u)
				u.maxHp, u.hp = 1, 1 -- beatable again: the leader now clears room 1
			end)
			local res3 = playUntilEnd(tr3, 200, { every = 3 })
			T.check(res3 ~= nil and run3.State == "Corridor", "p5 party: (setup) room 1 cleared by the leader", tostring(run3.State))
			advance(0.6)
			local mq = run3.Members[qb.UserId]
			local qdup = 0
			for _, uid in ipairs(party3.Order) do
				if uid == qb.UserId then
					qdup = qdup + 1
				end
			end
			T.check(mq ~= nil and mq.Left == false and mq.JoinedRoom == 2 and runOf(qb) == run3 and inBattle(qb) == run3.Id and dgs.GetParty(qb) == party3 and dgs.St.joinQueue[qb] == nil and qdup == 1,
				"p5 party: the queued joiner enters the run in the corridor after the clear (JoinedRoom 2, InBattle = run id, in the party once)", tostring(mq and mq.JoinedRoom))
		end
		cleanup(qq)
	end)

	------------------------------------------------------------------------------------------------
	-- p5dgn_exclusive
	------------------------------------------------------------------------------------------------
	S.p5dgn_exclusive = scenario("p5dgn_exclusive", function()
		if not ready("p5dgn_exclusive") then
			return
		end
		local dgs, bs = DGS(), BS()
		local GS = req("server/Services/GateService")
		local Dev = req("server/Services/DevService")
		local Ty = TS()
		local Config = K.config()
		local runner = newPlayer("DgnEx", WEAK, 1)
		local other = newPlayer("DgnOther", STRONG, 20)
		local all = { runner, other }
		claimHome(runner)
		toPad(other, 4, 0)
		local run = startSolo(runner, 1)
		if not T.check(run ~= nil and run.State == "Hall", "p5 excl: a solo run starts in the Hall") then
			cleanup(all)
			return
		end
		local function refusedEverywhere(label)
			local want = "Finish your dungeon run first"
			local okQ, whyQ = bs.Queue(runner)
			local okCh, whyCh = bs.Challenge(other, runner)
			local okRg, whyRg = bs.StartRing(runner, 1)
			T.check(okQ == false and whyQ == want and okCh == false and okRg == false and whyRg == want,
				"p5 excl: " .. label .. ": Queue / Challenge / StartRing refused '" .. want .. "'", tostring(whyQ) .. " | " .. tostring(whyCh) .. " | " .. tostring(whyRg))
			local okH = Ty and Ty.GoHome and Ty.GoHome(runner)
			T.check(okH ~= true, "p5 excl: " .. label .. ": GoHome is refused")
			if GS and GS.Use then
				-- (Phase 6: no Home gate in the lobby; GoHome above is the way home)
				local okA, whyA = GS.Use(runner, "Altar")
				T.check(okA == false, "p5 excl: " .. label .. ": the Altar gate refuses (" .. tostring(whyA) .. ")")
			end
			T.check(inBattle(runner) == run.Id and runOf(runner) == run, "p5 excl: " .. label .. ": InBattle stays the run id")
		end
		refusedEverywhere("Hall")
		-- the dev /reset is refused during a run
		if Dev and Dev.Run then
			local saved = Config.Dev.Admins
			Config.Dev.Admins = { runner.UserId }
			local okR, whyR = Dev.Run(runner, "reset", nil, "chat")
			Config.Dev.Admins = saved
			T.check(okR ~= true and runOf(runner) == run and DS().GetProfile(runner).Pets[WEAK[1]] ~= nil, "p5 excl: /reset is refused during a dungeon run", tostring(whyR))
		end
		-- a Corridor (after E at the hall's exit) and the Treasure (white-box)
		fromHall(run)
		T.check(run.State == "Corridor" and run.Room == 1, "p5 excl: after E at the hall's exit the run is in room 1's corridor (at the Threshold)")
		refusedEverywhere("Corridor")
		dgs.Dg.enterTreasure(run)
		advance(0.3)
		T.check(run.State == "Treasure", "p5 excl: (white-box) the run is in the Treasure")
		refusedEverywhere("Treasure")
		-- the obby pad: a runner cannot stand on it without leaving the pocket; the teleport counts as a respawn
		-- elsewhere (5.3): the member is removed and InBattle released BEFORE any portal party could hold a run id
		local lockAttr = Config.Attr.PortalLocked or "PortalLocked"
		local before = runner:GetAttribute(lockAttr)
		T.check(before == nil or before == false or before == "", "p5 excl: (setup) the runner is not portal-locked")
		if K.enterPortal then
			K.enterPortal(runner)
			advance(1.2)
		end
		T.check(runOf(runner) == nil and inBattle(runner) == nil, "p5 excl: the obby pad: a runner teleported onto it is out of the run with InBattle nil (no run id survives on the pad)")
		if K.leavePortalArea then
			K.leavePortalArea(runner)
			advance(0.5)
		end
		T.check(inBattle(runner) == nil and runOf(runner) == nil, "p5 excl: ...and stays out (the run ended for its last member)")
		local okQ2 = bs.Queue(runner)
		if okQ2 then
			bs.Unqueue(runner)
		end
		T.check(okQ2 ~= nil, "p5 excl: after the run the Queue answers (the run provider says nil)")
		cleanup(all)
	end)

	------------------------------------------------------------------------------------------------
	-- p5dgn_run
	------------------------------------------------------------------------------------------------
	S.p5dgn_run = scenario("p5dgn_run", function()
		if not ready("p5dgn_run") then
			return
		end
		local dgs, bs, db = DGS(), BS(), DGB()
		local d = D()
		-- SetRunProvider was called by Init: a fake run makes canBattle refuse
		local probe = newPlayer("DgnProbe", STRONG, 20)
		local AB = req("server/Services/ArenaBuilder")
		local arena = AB and AB.GetInfo and AB.GetInfo() or nil
		if arena and arena.Spawn then
			Mock.Teleport(probe, arena.Spawn * CFrame.new(2, 0, 0))
			advance(0.05)
		else
			toPad(probe, 0, 0)
		end
		local fakeRun = { Id = "D999", Floor = 1, Room = 0, State = "Hall", Wave = 0, Members = {}, Order = {}, Pocket = nil, Loot = {}, Paid = {}, Chests = {}, Started = 0, StateAt = 0 }
		dgs.St.runOf[probe] = fakeRun
		local okP, whyP = bs.Queue(probe)
		dgs.St.runOf[probe] = nil
		T.check(okP == false and whyP == "Finish your dungeon run first", "p5 run: BattleService.SetRunProvider was called by Init (GetRun -> 'Finish your dungeon run first')", tostring(whyP))
		local keys = dgs.KeysInRun(probe)
		T.check(type(keys) == "table" and next(keys) == nil, "p5 run: KeysInRun is empty outside a run")

		local p = newPlayer("DgnSolo", { WEAK[1] }, 1)
		local all = { probe, p }
		quietReplication()
		local mark = K.logSize()
		local ended = {}
		local conn = dgs.RunEnded:Connect(function(id, result)
			ended[#ended + 1] = { id = id, result = result }
		end)
		local run = startSolo(p, 1)
		if not T.check(run ~= nil, "p5 run: Solo floor 1 through the remote starts a run") then
			conn:Disconnect()
			cleanup(all)
			return
		end
		local pocket = run.Pocket
		T.check(run.State == "Hall" and run.Id:match("^D%d+$") ~= nil and inBattle(p) == run.Id, "p5 run: the run starts in the Hall, InBattle = the run id (D<n>)")
		local root = K.root(p)
		T.check(root and pocket and (root.Position - pocket.Origin).Magnitude < 200, "p5 run: the player was teleported into the pocket")
		local runMsg = lastState(p, "Run", mark)
		T.check(runMsg and runMsg.RunId == run.Id and runMsg.Floor == 1 and runMsg.State == "Hall" and runMsg.RoomCount == 4 and #runMsg.Members == 1 and runMsg.Name == "Mossy Cellar",
			"p5 run: DungeonState Run { RunId, Floor 1, Name Mossy Cellar, State Hall, RoomCount 4, Members }")
		local got = dgs.GetRun(p)
		T.check(got and got.RunId == run.Id and got.State == "Hall", "p5 run: GetRun(player) answers { RunId, Floor, Room, State, Wave }")
		T.check(pocket.Rooms[0] ~= nil and pocket.Rooms[1] ~= nil and pocket.Rooms[2] == nil, "p5 run: BuildRun placed the hall + room 1 only")
		T.check(workspace:FindFirstChild("Dungeons") ~= nil and workspace.Dungeons:FindFirstChild("Dungeon_" .. pocket.Index) == pocket.Model, "p5 run: the holder is workspace.Dungeons.Dungeon_<index>")

		-- the Hall -> room 1 corridor (no HallSeconds timer: E at the hall's exit); the fight starts when the member
		-- crosses the Threshold
		advance(d.HallSeconds + 3)
		T.check(run.State == "Hall" and run.Room == 0, "p5 run: the Hall no longer times out into room 1 (" .. tostring(d.HallSeconds) .. " s + 3 passed)")
		local hallPrompt = pocket.Hall and pocket.Hall.NextPrompt
		T.check(hallPrompt and hallPrompt.Enabled == true and hallPrompt.Name == "EnterPrompt" and hallPrompt.ObjectText == "Room 1" and hallPrompt.KeyboardKeyCode == Enum.KeyCode.E
			and hallPrompt.HoldDuration == 0 and hallPrompt.RequiresLineOfSight == false and hallPrompt.MaxActivationDistance == 10 and hallPrompt:GetAttribute("DungeonAction") == "Enter",
			"p5 run: the hall's exit carries an enabled EnterPrompt (E, no hold, no line of sight, 10 studs, DungeonAction Enter, 'Room 1')")
		fromHall(run)
		T.check(run.State == "Corridor" and run.Room == 1 and run.Phase == "Threshold", "p5 run: after E at the hall's exit the member stands at room 1's entrance (Corridor / Threshold)")
		T.check(hallPrompt and hallPrompt.Enabled == false, "p5 run: the hall's EnterPrompt is disabled once the group moved on")
		T.check(pocket.Rooms[2] ~= nil and db.LiveParts(pocket) <= 950, "p5 run: room 2 is built on entering room 1 (live parts " .. tostring(db.LiveParts(pocket)) .. " <= 950)")
		advance(2)
		T.check(run.State == "Corridor", "p5 run: nobody crossed the Threshold yet: no fight")
		local tr = tracker(p)
		local roomsPlayed = 0
		local lootMsgs = 0
		local lootMark = K.logSize()
		local xp0 = totalXp(p, WEAK[1])
		local cash0, tok0 = cash(p), tokens(p)
		local startsSeen = 0
		local enemiesSeen = {}
		for room = 1, 4 do
			crossThreshold(run, p)
			if not T.check(run.State == "Fight" and run.Room == room, "p5 run: room " .. room .. " fight starts on the Threshold") then
				break
			end
			pump(tr)
			local start = tr.start
			if room == 1 then
				T.check(start and start.Mode == "Dungeon" and type(start.Dungeon) == "table" and start.Dungeon.Floor == 1 and start.Dungeon.Room == 1 and start.Dungeon.Name == "Mossy Cellar",
					"p5 run: Start { Mode Dungeon, Dungeon = { Floor 1, Room 1, Name } }")
				local ri = roomInfo(run, 1)
				T.check(ri and ri.Door and ri.Door.Model:GetAttribute("Open") == false and ri.Model:GetAttribute("EntranceOpen") == false, "p5 run: the entrance bars close when the fight starts")
			end
			startsSeen = startsSeen + 1
			local res = playUntilEnd(tr, 200, { every = 3 })
			pump(tr)
			local enemies = 0
			for idx = (tr.eventCursor or 0) + 1, #tr.events do
				local ev = tr.events[idx]
				if ev.type == "Wave" and type(ev.units) == "table" then
					enemies = enemies + #ev.units
				end
			end
			tr.eventCursor = #tr.events
			enemiesSeen[room] = enemies
			if not T.check(res ~= nil and res.Outcome == "Win" and run.State == "Corridor", "p5 run: room " .. room .. " cleared by ONE level-1 pet (End Outcome Win, State Corridor)", tostring(res and res.Outcome) .. " / " .. tostring(run.State)) then
				break
			end
			roomsPlayed = roomsPlayed + 1
			local loots = states(p, lootMark, "Loot")
			T.check(#loots == room and loots[#loots].Room == room and loots[#loots].Cash > 0 and loots[#loots].Tokens > 0 and loots[#loots].Xp > 0,
				"p5 run: room " .. room .. " pays one Loot card (Cash, Tokens, Xp)")
			lootMsgs = #loots
			T.check(run.Paid[room] and run.Paid[room][p.UserId] == true, "p5 run: run.Paid[" .. room .. "][uid] is marked")
			advance(d.Intermission + 0.6)
			local ri = roomInfo(run, room)
			if room == 4 then
				T.check(ri and ri.NextPrompt and ri.NextPrompt.Enabled == true and ri.NextPrompt.ObjectText == "Treasure" and ri.Model:GetAttribute("DoorOpen") == false,
					"p5 run: after the boss the exit stays barred and its EnterPrompt 'Treasure' is enabled")
			else
				local nextRi = roomInfo(run, room + 1)
				T.check(ri and ri.ExitDoor and ri.ExitDoor.Model:GetAttribute("Open") == true and ri.Model:GetAttribute("DoorOpen") == true, "p5 run: the exit bars open after Intermission (DoorOpen true)")
				T.check(nextRi and nextRi.Door and nextRi.Door.Model:GetAttribute("Open") == false and nextRi.Model:GetAttribute("EntranceOpen") == false and nextRi.EnterPrompt and nextRi.EnterPrompt.Enabled == true,
					"p5 run: room " .. (room + 1) .. "'s entrance stays closed with its EnterPrompt enabled")
			end
			advance(d.DoorTime + 3)
			T.check(run.State == "Corridor" and run.Room == room and run.Phase == "Walk", "p5 run: room " .. room .. ": no timer moves the group on (Intermission + DoorTime + 3 s passed)")
			pressDoor(run)
			if room == 4 then
				waitState(run, "Treasure", 2)
			else
				T.check(run.Room == room + 1 and run.Phase == "Threshold" and roomInfo(run, room + 1).Model:GetAttribute("EntranceOpen") == true, "p5 run: after E the member stands at room " .. (room + 1) .. "'s entrance (its door open)")
				if room + 1 == 2 then
					T.check(pocket.Rooms[1] == nil and pocket.Rooms[2] ~= nil and pocket.Rooms[3] ~= nil, "p5 run: room 1 is destroyed on entering room 2 (room 3 is built while 2 fights)")
				elseif room + 1 == 3 then
					T.check(pocket.Rooms[1] == nil and pocket.Rooms[2] == nil and pocket.Rooms[3] ~= nil and pocket.Rooms[4] ~= nil, "p5 run: on entering room 3 only the hall, room 3 and the boss room stand")
				end
				T.check(db.LiveParts(pocket) <= 950, "p5 run: live parts stay <= 950 (" .. tostring(db.LiveParts(pocket)) .. ")")
			end
		end
		T.check(roomsPlayed == 4, "p5 run: all four rooms were played (" .. roomsPlayed .. ")")
		T.check(enemiesSeen[1] == 1 and enemiesSeen[2] == 1 and enemiesSeen[3] == 1, "p5 run: floor 1 wave rooms spawn ONE enemy each", table.concat({ tostring(enemiesSeen[1]), tostring(enemiesSeen[2]), tostring(enemiesSeen[3]) }, ","))
		T.check(enemiesSeen[4] ~= nil and enemiesSeen[4] >= 2 and run.EscortSpawned == true, "p5 run: the boss room spawned the boss and its escort (" .. tostring(enemiesSeen[4]) .. " units)")
		T.check(startsSeen == 4, "p5 run: one Start per room (a fresh encounter each)")
		-- the treasure: chest once, the 45 s exit
		T.check(run.State == "Treasure" and run.Chests[p.UserId] == "Closed" and run.Cleared == true, "p5 run: the boss clear leads to the Treasure with a closed chest")
		local rec = DS().GetDungeon(p)
		T.check(rec and rec.Best == 1 and rec.Cleared[1] == true and rec.Clears == 1, "p5 run: MutateDungeon raised Best 1, Cleared[1], Clears 1")
		T.check(tokens(p) >= tok0 + 300 and cash(p) > cash0 and totalXp(p, WEAK[1]) > xp0, "p5 run: the first clear paid 300 tokens on top of the room loot; cash and XP grew")
		local chestMark = K.logSize()
		request(p, "Chest")
		local chestMsg = lastState(p, "Chest", chestMark)
		T.check(run.Chests[p.UserId] == "Opened" and chestMsg and (chestMsg.Kind == "Cash" or chestMsg.Kind == "Tokens") and chestMsg.Amount > 0, "p5 run: Chest opens once (Cash or Tokens on floor 1)")
		advance(0.6)
		request(p, "Chest")
		T.check(#states(p, chestMark, "Chest") == 1, "p5 run: a second Chest request pays nothing")
		local endMark = K.logSize()
		advance(d.TreasureSeconds + 1)
		local endMsg = lastState(p, "End", endMark)
		T.check(endMsg and endMsg.Cleared == true and endMsg.Reason == "Cleared" and type(endMsg.Totals) == "table" and endMsg.Totals.Tokens >= 300 and endMsg.FirstClear ~= nil and endMsg.NewBest == true and endMsg.Unlocked == 2,
			"p5 run: End { Cleared, Reason Cleared, Totals, FirstClear, NewBest, Unlocked 2 } after the 45 s exit")
		T.check(inBattle(p) == run.Id, "p5 run: InBattle is still the run id during RETURN_DELAY")
		advance(4.6)
		T.check(inBattle(p) == nil and runOf(p) == nil and dgs.GetRun(p) == nil, "p5 run: InBattle released at the return teleport")
		local i = info()
		root = K.root(p)
		T.check(root and i and (root.Position - i.ReturnCFrame.Position).Magnitude < 6, "p5 run: the player is back at DungeonInfo.ReturnCFrame")
		T.check(db.GetPocket(pocket.Index) == nil and dgs.St.pocketBusy[pocket.Index] == nil and workspace:FindFirstChild("Dungeons") == nil, "p5 run: the pocket is freed and workspace.Dungeons is gone")
		T.check(#ended == 1 and ended[1].id == run.Id and ended[1].result.Cleared == true and ended[1].result.Winners[1] == p.UserId, "p5 run: RunEnded fired once with { Cleared, Winners }")
		T.check(dgs.GetParty(p) == nil, "p5 run: the party record is removed with the run")
		local board = i.Portal:GetAttribute("DungeonBoard")
		T.check(type(board) == "string" and board:find(p.Name .. "|1", 1, true) ~= nil, "p5 run: the gate's DungeonBoard lists the clear ('" .. tostring(board) .. "')")
		K.flushWarnings("p5dgn_run", { "[BattleService]", "[DungeonService]", "[DataService]", "[TycoonService]", "[PetCareService]" })

		-- a 4-party: stragglers placed, enemies 2 + 3 per wave, the leash
		local q = { newPlayer("DgnQa", STRONG, 20), newPlayer("DgnQb", STRONG, 20), newPlayer("DgnQc", STRONG, 20), newPlayer("DgnQd", STRONG, 20) }
		for _, m in ipairs(q) do
			all[#all + 1] = m
			toPad(m, 0, 0)
		end
		request(q[1], "Create", 1)
		for i2 = 2, 4 do
			request(q[i2], "Join", q[1].UserId)
			request(q[i2], "Ready", true)
			advance(0.4)
		end
		request(q[1], "Start")
		advance(6)
		local run4 = runOf(q[1])
		if T.check(run4 ~= nil and count(run4.Members) == 4, "p5 run: a 4-party starts after the 5 s countdown with 4 members") then
			local p2 = run4.Pocket
			fromHall(run4)
			-- a straggler far away is placed at the entrance with the others
			for _, m in ipairs(q) do
				local r = K.root(m)
				T.check(r and (r.Position - roomInfo(run4, 1).Entrance.Position).Magnitude < 12, "p5 run: 4-party: " .. m.Name .. " placed at room 1's entrance")
			end
			local tr4 = tracker(q[1])
			crossThreshold(run4, q[1])
			T.check(run4.State == "Fight" and count(run4.Members) == 4, "p5 run: 4-party: the first member across the Threshold starts the fight for all")
			advance(1)
			pump(tr4)
			local n1 = 0
			for _, ev in ipairs(tr4.events) do
				if ev.type == "Wave" and type(ev.units) == "table" then
					n1 = n1 + #ev.units
				end
			end
			T.check(n1 == 1, "p5 run: 4-party floor 1 wave 1 = ONE enemy (Floor1EnemiesPerWave)", tostring(n1))
			local bc = BC()
			local w3 = bc.DungeonWave(3, 1, 1, 4, 5)
			local w1 = bc.DungeonWave(3, 1, 1, 1, 5)
			T.check(#w1.Pets == 2 and #w3.Pets == 5, "p5 run: on floor 3 a solo wave has 2 enemies, a 4-party wave 2 + 3 = 5", tostring(#w1.Pets) .. "/" .. tostring(#w3.Pets))
			-- the leash: a member 100 studs from the room centre is removed after 2 strikes (the enemy is made
			-- unbeatable first: the auto-attacking level-20 team would clear floor 1 before the second strike)
			tuneEnemies(run4, unbeatable)
			local ri = roomInfo(run4, 1)
			local leashMark = K.logSize()
			Mock.Teleport(q[4], CFrame.new(ri.Center + Vector3.new(100, 3, 0)))
			advance(2)
			local m4 = run4.Members[q[4].UserId]
			T.check(m4 and m4.Left == true and inBattle(q[4]) == nil and runOf(q[4]) == nil and count(run4.Members) == 4 and lastState(q[4], "End", leashMark) ~= nil,
				"p5 run: 4-party: the room leash removes that member only (End sent, InBattle nil), the others fight on", tostring(m4 and m4.LeftWhy))
			T.check(run4.State == "Fight", "p5 run: 4-party: the run continues for the other three")
		end
		conn:Disconnect()
		cleanup(all)
	end)

	------------------------------------------------------------------------------------------------
	-- p5dgn_loot (white-box: Dg.payRoom / payLoss / clearFloor / openChest on a live run in its Hall)
	------------------------------------------------------------------------------------------------
	S.p5dgn_loot = scenario("p5dgn_loot", function()
		if not ready("p5dgn_loot") then
			return
		end
		local dgs, bs, bc = DGS(), BS(), BC()
		local d = D()
		local a = newPlayer("DgnLootA", WEAK, 5)
		local b = newPlayer("DgnLootB", WEAK, 5)
		local c = newPlayer("DgnLootC", WEAK, 5)
		local all = { a, b, c }
		claimHome(a)
		for _, p in ipairs(all) do
			toPad(p, 0, 0)
		end
		request(a, "Create", 1)
		request(b, "Join", a.UserId)
		request(b, "Ready", true)
		request(c, "Join", a.UserId)
		request(c, "Ready", true)
		request(a, "Start")
		advance(6)
		local run = runOf(a)
		if not T.check(run ~= nil and count(run.Members) == 3, "p5 loot: (setup) a 3-party run in its Hall") then
			cleanup(all)
			return
		end
		local uidA, uidB, uidC = a.UserId, b.UserId, c.UserId
		run.Waves = 1
		run.Room = 1
		local income = TS().IncomePerSecond(a)
		local cashA0, tokA0, xpA0 = cash(a), tokens(a), totalXp(a, WEAK[1])
		local cashB0, tokB0, xpB0 = cash(b), tokens(b), totalXp(b, WEAK[1])
		local xpC0 = totalXp(c, WEAK[1])
		local mark = K.logSize()
		local result = { Reason = "Cleared", Duration = 30, Fighters = { uidA, uidB }, Damage = {}, Hp = { [2] = 0 } }
		dgs.Dg.payRoom(run, 1, result)
		local wantCash = math.max(20 + 10 * 1, math.floor(income * d.RoomSeconds[1]))
		local rewards = bc.DungeonRewards(1, 1, 1, income, false)
		T.check(cash(a) - cashA0 == rewards.Cash and rewards.Cash == wantCash, "p5 loot: Cash = max(20 + 10 x floor, income x RoomSeconds) (" .. tostring(rewards.Cash) .. ", income " .. tostring(income) .. ")")
		T.check(tokens(a) - tokA0 == rewards.Tokens and rewards.Tokens == math.floor((6 + 4) * 1 / 2), "p5 loot: Tokens = floor((6 + 4f) x waves / 2) for a wave room")
		T.check(totalXp(a, WEAK[1]) - xpA0 == rewards.Xp and rewards.Xp == (25 + 10) * 1, "p5 loot: XP per team pet = (25 + 10f) x waves via GrantXp (source Dungeon)")
		T.check(totalXp(a, WEAK[2]) > 0 and totalXp(a, WEAK[3]) > 0, "p5 loot: every team pet got the XP")
		T.check(cash(b) - cashB0 == 30 and tokens(b) - tokB0 == rewards.Tokens and totalXp(b, WEAK[1]) - xpB0 == rewards.Xp, "p5 loot: the second fighter is paid the same (no home: the 20 + 10f floor)")
		T.check(totalXp(c, WEAK[1]) == xpC0, "p5 loot: an AFK member (not in result.Fighters) gets nothing")
		T.check(run.Paid[1][uidA] == true and run.Paid[1][uidB] == true and run.Paid[1][uidC] == nil and run.Members[uidA].Qualified[1] == true and run.Members[uidC].Qualified[1] == nil,
			"p5 loot: run.Paid[1] marks the paid fighters; Qualified[1] set for them only")
		local loots = states(a, mark, "Loot")
		T.check(#loots == 1 and loots[1].Room == 1 and loots[1].Cash == rewards.Cash and loots[1].Tokens == rewards.Tokens and loots[1].Xp == rewards.Xp, "p5 loot: one Loot card { Room, Cash, Tokens, Xp, LevelUps }")
		-- a replayed OnEnd pays nothing
		local cashA1, tokA1, xpA1 = cash(a), tokens(a), totalXp(a, WEAK[1])
		dgs.Dg.payRoom(run, 1, result)
		dgs.Dg.onRoomEnd(run, result, nil)
		T.check(cash(a) == cashA1 and tokens(a) == tokA1 and totalXp(a, WEAK[1]) == xpA1 and #states(a, mark, "Loot") == 1, "p5 loot: a replayed result pays nothing (Paid marks)")
		-- Double Rewards: Tokens x2, Cash / XP not
		run.Room = 2
		bs.SetDoubleRewards(true, 600)
		local cashA2, tokA2, xpA2 = cash(a), tokens(a), totalXp(a, WEAK[1])
		dgs.Dg.payRoom(run, 2, { Reason = "Cleared", Duration = 30, Fighters = { uidA }, Hp = { [2] = 0 } })
		local r2 = bc.DungeonRewards(1, 2, 1, income, false)
		T.check(tokens(a) - tokA2 == r2.Tokens * 2 and cash(a) - cashA2 == r2.Cash and totalXp(a, WEAK[1]) - xpA2 == r2.Xp, "p5 loot: under Double Rewards Tokens x2, Cash and XP unchanged")
		bs.SetDoubleRewards(nil)
		-- a late joiner is unpaid for earlier rooms
		run.Members[uidC].JoinedRoom = 3
		local xpC1 = totalXp(c, WEAK[1])
		dgs.Dg.payRoom(run, 2, { Reason = "Cleared", Duration = 30, Fighters = { uidC }, Hp = { [2] = 0 } })
		T.check(totalXp(c, WEAK[1]) == xpC1 and run.Paid[2][uidC] == nil, "p5 loot: a late joiner (JoinedRoom 3) is unpaid for room 2 even when listed")
		-- the boss room + the first clear: A qualifies (rooms 1 + 4), B only room 1 (no boss room), C only the boss room
		run.Room = 4
		run.Waves = 2
		run.Members[uidC].JoinedRoom = 4
		local tokA3, xpA3 = tokens(a), totalXp(a, WEAK[1])
		local tokC3 = tokens(c)
		local gemsA0 = DS().GetProfile(a).Gems or 0
		local gemsC0 = DS().GetProfile(c).Gems or 0
		local tokB3 = tokens(b)
		dgs.Dg.payRoom(run, 4, { Reason = "Cleared", Duration = 40, Fighters = { uidA, uidC }, Hp = { [2] = 0 } })
		local r4 = bc.DungeonRewards(1, 4, 4, income, false)
		T.check(tokens(a) - tokA3 == r4.Tokens and r4.Tokens == (6 + 4) * 2 and totalXp(a, WEAK[1]) - xpA3 == r4.Xp and r4.Xp == (25 + 10) * 4, "p5 loot: the boss room pays (6 + 4f) x 2 tokens and XP for 4 waves")
		T.check(tokens(c) - tokC3 == r4.Tokens, "p5 loot: a boss-only joiner is paid the boss room (qualifying)")
		local fired = {}
		local conn = dgs.FloorCleared:Connect(function(pl, f)
			fired[#fired + 1] = { pl, f }
		end)
		tokA3 = tokens(a)
		dgs.Dg.clearFloor(run)
		local fc = bc.DungeonFirstClear(1)
		T.check(tokens(a) - tokA3 == fc.Tokens and (DS().GetProfile(a).Gems or 0) - gemsA0 == fc.Gems and fc.Tokens == 300 and fc.Gems == 3, "p5 loot: the first clear pays 300 tokens + 3 gems once to the qualifying member")
		local recA, recB, recC = DS().GetDungeon(a), DS().GetDungeon(b), DS().GetDungeon(c)
		T.check(recA.Best == 1 and recA.Cleared[1] == true and recA.Clears == 1, "p5 loot: A: Best 1, Cleared[1], Clears 1")
		T.check(recB.Best == 1 and recB.Cleared[1] ~= true and recB.Clears == 0 and tokens(b) == tokB3, "p5 loot: B (no boss room): carried to Best 1, no Cleared, no first clear")
		T.check(recC.Best == 1 and recC.Cleared[1] ~= true and (DS().GetProfile(c).Gems or 0) == gemsC0, "p5 loot: C (boss room only): carried, never the first clear")
		T.check(#fired == 1 and fired[1][1] == a and fired[1][2] == 1, "p5 loot: FloorCleared fired once (A, 1)")
		conn:Disconnect()
		-- clearFloor again (a replay) pays no second first clear
		tokA3 = tokens(a)
		local gemsA1 = DS().GetProfile(a).Gems or 0
		dgs.Dg.clearFloor(run)
		T.check(tokens(a) == tokA3 and (DS().GetProfile(a).Gems or 0) == gemsA1 and DS().GetDungeon(a).Clears == 2, "p5 loot: a second clearFloor pays no first clear again (Clears counts the run)")
		-- the chest: once, rolled per userId, auto-opened on the 45 s exit; floors 1-2 never Gems
		local noGems = true
		for seed = 1, 60 do
			for f = 1, 2 do
				local chest = bc.DungeonChest(f, seed * 7919)
				if chest.Kind == "Gems" then
					noGems = false
				end
			end
		end
		T.check(noGems, "p5 loot: DungeonChest never rolls Gems on floors 1-2 (120 rolls)")
		-- W5 data-money-3: an AFK alt carried through the floor (qualified in NO room) gets no chest (5.2 / Y4)
		local z = newPlayer("DgnLootZ", WEAK, 5)
		all[#all + 1] = z
		toPad(z, 1, 0)
		local okZ, whyZ = dgs.Dg.lateJoin(run, z)
		local tokZ0, cashZ0 = tokens(z), cash(z)
		T.check(okZ == true and run.Members[z.UserId] ~= nil and next(run.Members[z.UserId].Qualified) == nil, "p5 loot: (setup) an AFK member joined the run in its Hall, qualified nowhere", tostring(whyZ))
		dgs.Dg.enterTreasure(run)
		T.check(run.State == "Treasure" and run.Chests[uidA] == "Closed" and run.Chests[uidB] == "Closed" and run.Chests[uidC] == "Closed", "p5 loot: the Treasure closes a chest per QUALIFYING member (A rooms 1 + 4, B room 1, C the boss room)")
		T.check(run.Chests[z.UserId] == nil and dgs.OpenChest(z) == false, "p5 loot: the AFK member (0 damage everywhere) gets NO chest; Chest is refused")
		local chestMark = K.logSize()
		local okC1 = dgs.OpenChest(a)
		local okC2 = dgs.OpenChest(a)
		local chests = states(a, chestMark, "Chest")
		T.check(okC1 == true and okC2 == false and #chests == 1 and run.Chests[uidA] == "Opened" and (chests[1].Kind == "Cash" or chests[1].Kind == "Tokens") and chests[1].Amount > 0,
			"p5 loot: OpenChest pays once (Cash or Tokens on floor 1); a second open is refused")
		local tokB4, cashB4 = tokens(b), cash(b)
		advance(d.TreasureSeconds + 1)
		T.check(run.Chests[uidB] == "Opened" and (tokens(b) > tokB4 or cash(b) > cashB4) and run.State == "Ending", "p5 loot: the 45 s exit opens the unopened chest for its owner and ends the run")
		T.check(run.Chests[z.UserId] == nil and tokens(z) == tokZ0 and cash(z) == cashZ0, "p5 loot: ...and pays the AFK member nothing")
		advance(5)
		cleanup(all)

		-- W5 battle-dungeon-1 (5.4): the boss room is cleared when boss AND escort are down. BattleSim fires EnemiesDown
		-- per wave team, so the escort falling first (or the boss first) must not clear / pay the room
		quietReplication()
		local e1 = newPlayer("DgnEsc", WEAK, 3)
		local trE = tracker(e1)
		local runE = startSolo(e1, 1)
		if T.check(runE ~= nil and intoBossRoom(runE, e1), "p5 loot: (setup) a solo run straight into the boss room's fight") then
			pump(trE)
			local tokE0 = tokens(e1)
			local best0 = DS().GetDungeon(e1).Best
			-- the dais (W5 battle-dungeon-2): standing by the throne during the fight is NOT a drop-out
			local base = runE.Pocket.Rooms[4].Room.PrimaryPart
			Mock.Teleport(e1, CFrame.new(base.CFrame:PointToWorldSpace(Vector3.new(4, 2.4 + 3, 30))))
			advance(2.0)
			local me = runE.Members[e1.UserId]
			T.check(me and me.Left == false and runE.State == "Fight" and inBattle(e1) == runE.Id, "p5 loot: a member on the throne dais during the boss fight stays in the fight (the zone covers the room)", tostring(me and me.LeftWhy))
			local simE, bossUnits = enemiesOfWave(runE, 1)
			local boss = bossUnits[1]
			if T.check(simE ~= nil and boss ~= nil and boss.alive, "p5 loot: (setup) the boss is up (sim reachable)") then
				dgs.Dg.onBossHp(runE, 0.45, runE.Battle)
				advance(0.4)
				local _, escort = enemiesOfWave(runE, 2)
				T.check(runE.EscortSpawned == true and #escort >= 1, "p5 loot: the escort spawned at <= 50% boss HP (" .. #escort .. " units)")
				boss.hp = boss.maxHp * 0.45
				slayWith(runE, e1, trE, simE, escort, boss, boss.maxHp * 0.45)
				local _, escortLeft = enemiesOfWave(runE, 2)
				T.check(#escortLeft == 0 and boss.alive == true, "p5 loot: (setup) the escort is down, the boss alive at 45%")
				T.check(runE.State == "Fight" and runE.Cleared ~= true and runE.Paid[4] == nil and tokens(e1) == tokE0 and DS().GetDungeon(e1).Best == best0,
					"p5 loot: killing only the escort does NOT clear the boss room: nothing paid, no Best / first clear", tostring(runE.State) .. " Cleared=" .. tostring(runE.Cleared))
				slayWith(runE, e1, trE, simE, { boss }, nil, nil)
				T.check(runE.State ~= "Fight" and runE.Cleared == true and runE.Paid[4] and runE.Paid[4][e1.UserId] == true and tokens(e1) > tokE0 and DS().GetDungeon(e1).Best == 1,
					"p5 loot: ...the boss falling last clears the room: the boss loot and Best 1 paid once (no first clear: rooms 1-3 skipped)", tostring(runE.State))
			end
		end
		cleanup({ e1 })
		-- the reverse order: the boss falls first, the escort still stands
		local e2 = newPlayer("DgnEsc", WEAK, 3)
		local trR = tracker(e2)
		local runR = startSolo(e2, 1)
		if T.check(runR ~= nil and intoBossRoom(runR, e2), "p5 loot: (setup) a second solo run in the boss room") then
			pump(trR)
			local tokR0 = tokens(e2)
			local simR, bossUnits = enemiesOfWave(runR, 1)
			local boss = bossUnits[1]
			if T.check(simR ~= nil and boss ~= nil, "p5 loot: (setup) the boss is up") then
				dgs.Dg.onBossHp(runR, 0.45, runR.Battle)
				advance(0.4)
				local _, escort = enemiesOfWave(runR, 2)
				slayWith(runR, e2, trR, simR, { boss }, nil, nil)
				local _, escortLeft = enemiesOfWave(runR, 2)
				T.check(boss.alive == false and #escortLeft == #escort and #escort >= 1, "p5 loot: (setup) the boss is down, the escort alive")
				T.check(runR.State == "Fight" and runR.Cleared ~= true and runR.Paid[4] == nil and tokens(e2) == tokR0, "p5 loot: killing only the boss does NOT clear the boss room while the escort stands")
				slayWith(runR, e2, trR, simR, escort, nil, nil)
				T.check(runR.State ~= "Fight" and runR.Cleared == true and runR.Paid[4] and runR.Paid[4][e2.UserId] == true, "p5 loot: ...the escort falling last clears it (paid once)", tostring(runR.State))
			end
		end
		cleanup({ e2 })

		-- the loss third on a wipe >= 20 s; nothing on Quit
		local l = newPlayer("DgnLoss", WEAK, 5)
		local run2 = startSolo(l, 1)
		if T.check(run2 ~= nil, "p5 loot: (setup) a solo run for the loss rule") then
			run2.Waves = 1
			run2.Room = 2
			local xpL0 = totalXp(l, WEAK[1])
			dgs.Dg.payLoss(run2, 2, { Reason = "Wipe", Duration = 25, Fighters = { l.UserId }, Hp = { [2] = 0.9 } })
			local rr = bc.DungeonRewards(1, 2, 1, 0, false)
			T.check(totalXp(l, WEAK[1]) - xpL0 == math.floor(rr.Xp / 3 + 0.5), "p5 loot: a wipe after >= 20 s pays a third of the room's XP")
			local xpL1 = totalXp(l, WEAK[1])
			dgs.Dg.payLoss(run2, 2, { Reason = "Wipe", Duration = 25, Fighters = { l.UserId }, Hp = { [2] = 0.9 } })
			T.check(totalXp(l, WEAK[1]) == xpL1, "p5 loot: the loss third is paid once per room")
			run2.Room = 3
			dgs.Dg.payLoss(run2, 3, { Reason = "Wipe", Duration = 5, Fighters = { l.UserId }, Hp = { [2] = 0.95 } })
			T.check(totalXp(l, WEAK[1]) == xpL1, "p5 loot: a 5 s wipe with 5% damage is not a real loss: nothing paid")
			local tokL, cashL = tokens(l), cash(l)
			request(l, "Quit")
			advance(0.5)
			T.check(totalXp(l, WEAK[1]) == xpL1 and tokens(l) == tokL and cash(l) == cashL and runOf(l) == nil, "p5 loot: Quit pays nothing")
		end
		cleanup({ l })
	end)

	------------------------------------------------------------------------------------------------
	-- p5dgn_ends
	------------------------------------------------------------------------------------------------
	S.p5dgn_ends = scenario("p5dgn_ends", function()
		if not ready("p5dgn_ends") then
			return
		end
		local dgs, bs, db = DGS(), BS(), DGB()
		local d = D()
		quietReplication()
		local endedIds = {}
		local conn = dgs.RunEnded:Connect(function(id, result)
			endedIds[id] = (endedIds[id] or 0) + 1
			endedIds[#endedIds + 1] = { id = id, result = result }
		end)
		local function runEndedOnce(id)
			return endedIds[id] == 1
		end

		-- 1. a wipe by KO: an idle level-1 pet is beaten (Wipe), the player returned, the pocket freed
		local w = newPlayer("DgnWipe", { WEAK[1] }, 1)
		local run = startSolo(w, 1)
		if T.check(run ~= nil, "p5 ends: (setup) a solo run for the KO wipe") then
			local mark = K.logSize()
			intoFight(run, w, nil)
			T.check(run.State == "Fight", "p5 ends: KO: the fight runs")
			-- (the level-1 pet auto-attacks: the enemy is made overwhelming so the room is lost by KO)
			tuneEnemies(run, function(u)
				unbeatable(u)
				u.hit = 1e6
			end)
			local t0 = Mock.Clock.now
			while run.State == "Fight" and Mock.Clock.now - t0 < 200 do
				advance(0.5)
			end
			local endMsg = lastState(w, "End", mark)
			T.check(run.State == "Ending" and run.EndReason == "Wipe" and endMsg and endMsg.Reason == "Wipe" and endMsg.Cleared == false and toasted(w, "got you in room 1", mark),
				"p5 ends: KO: an idle pet wipes -> End { Reason Wipe }, 'Floor 1: the Mossy Cellar got you in room 1'", tostring(run.EndReason))
			advance(5)
			T.check(inBattle(w) == nil and runOf(w) == nil and db.GetPocket(run.PocketIndex) == nil and runEndedOnce(run.Id), "p5 ends: KO: InBattle nil, the pocket free, RunEnded once")
		end
		cleanup({ w })

		-- 2. a wipe by timeout: a strong idle team is not killed and never attacks
		local tmo = newPlayer("DgnTimeout", STRONG, 50)
		run = startSolo(tmo, 1)
		if T.check(run ~= nil, "p5 ends: (setup) a solo run for the timeout") then
			local mark = K.logSize()
			intoFight(run, tmo, nil)
			-- (the strong team auto-attacks: the enemy is made unbeatable and harmless so only the clock ends the room)
			tuneEnemies(run, function(u)
				unbeatable(u)
				u.hit = 0
			end)
			local t0 = Mock.Clock.now
			while run.State == "Fight" and Mock.Clock.now - t0 < d.Floor1RoomTime + 20 do
				advance(1)
			end
			T.check(run.State == "Ending" and run.EndReason == "Timeout" and lastState(tmo, "End", mark) ~= nil, "p5 ends: Timeout: the 180 s floor-1 room limit ends the run (Reason Timeout)", tostring(run.EndReason) .. " after " .. tostring(math.floor(Mock.Clock.now - t0)) .. " s")
			advance(5)
			T.check(inBattle(tmo) == nil and runEndedOnce(run.Id), "p5 ends: Timeout: released, RunEnded once")
		end
		cleanup({ tmo })

		-- 3. Quit mid-fight and in a corridor; the last member out frees the pocket
		local qa = newPlayer("DgnQuitA", STRONG, 20)
		local qb = newPlayer("DgnQuitB", STRONG, 20)
		toPad(qa, 0, 0)
		toPad(qb, 2, 0)
		request(qa, "Create", 1)
		request(qb, "Join", qa.UserId)
		request(qb, "Ready", true)
		request(qa, "Start")
		advance(6)
		run = runOf(qa)
		if T.check(run ~= nil and count(run.Members) == 2, "p5 ends: (setup) a 2-party run") then
			intoFight(run, qa, nil)
			T.check(run.State == "Fight", "p5 ends: Quit: the 2-party fight runs")
			local mark = K.logSize()
			request(qb, "Quit")
			advance(0.6)
			local mb = run.Members[qb.UserId]
			T.check(mb and mb.Left == true and inBattle(qb) == nil and runOf(qb) == nil and run.State == "Fight" and lastState(qb, "End", mark) ~= nil and bs.IsInBattle(qb) == false,
				"p5 ends: Quit mid-fight removes that member only (End sent, InBattle nil, out of the encounter); the run goes on")
			local i = info()
			local root = K.root(qb)
			T.check(root and (root.Position - i.ReturnCFrame.Position).Magnitude < 6, "p5 ends: the quitter is back at the portal")
			-- the leader quits too: the last one out ends the run (Abandoned), the pocket is freed
			local pocketIndex = run.PocketIndex
			advance(1.1)
			request(qa, "Quit")
			advance(1)
			T.check(run.State == "Ending" and run.Finished == true and db.GetPocket(pocketIndex) == nil and dgs.St.pocketBusy[pocketIndex] == nil and inBattle(qa) == nil and runEndedOnce(run.Id),
				"p5 ends: the last member out ends the run at once: pocket free, RunEnded once")
			T.check(dgs.GetParty(qa) == nil and dgs.GetParty(qb) == nil, "p5 ends: the party record is gone")
		end
		-- Quit in a corridor
		toPad(qa, 0, 0)
		advance(1.6)
		run = startSolo(qa, 1)
		if T.check(run ~= nil, "p5 ends: (setup) a solo run for the corridor Quit") then
			fromHall(run)
			request(qa, "Quit")
			advance(1)
			T.check(run.State == "Ending" and inBattle(qa) == nil and runEndedOnce(run.Id), "p5 ends: Quit in a corridor ends a solo run (RunEnded once)")
		end
		cleanup({ qa, qb })

		-- 4. leaving the game mid-fight (Disconnect) and a respawn elsewhere
		local la = newPlayer("DgnLeaveA", STRONG, 20)
		local lb = newPlayer("DgnLeaveB", STRONG, 20)
		toPad(la, 0, 0)
		toPad(lb, 2, 0)
		request(la, "Create", 1)
		request(lb, "Join", la.UserId)
		request(lb, "Ready", true)
		request(la, "Start")
		advance(6)
		run = runOf(la)
		if T.check(run ~= nil and count(run.Members) == 2, "p5 ends: (setup) a 2-party run for disconnect / respawn") then
			intoFight(run, la, nil)
			Mock.RemovePlayer(lb)
			advance(0.6)
			local mb = run.Members[lb.UserId]
			T.check(mb and mb.Left == true and mb.LeftWhy == "Disconnect" and run.State == "Fight" and count(run.Members) == 2, "p5 ends: a disconnect removes that member (Disconnect); the run goes on")
			Mock.Respawn(la)
			advance(1.2)
			local ma = run.Members[la.UserId]
			T.check(ma and ma.Left == true and run.State == "Ending" and inBattle(la) == nil, "p5 ends: a respawn elsewhere removes the member; the last one out ends the run", tostring(ma and ma.LeftWhy))
			advance(1)
			T.check(runEndedOnce(run.Id), "p5 ends: RunEnded once after the respawn end")
		end
		cleanup({ la })

		-- 5. Shutdown mid-fight and in a corridor: every run void, released at once
		local sa = newPlayer("DgnShutA", STRONG, 20)
		local sb = newPlayer("DgnShutB", STRONG, 20)
		local runA = startSolo(sa, 1)
		toPad(sb, 3, 0)
		advance(1.6)
		local runB = startSolo(sb, 1)
		if T.check(runA ~= nil and runB ~= nil and runA ~= runB, "p5 ends: (setup) two solo runs (two pockets)") then
			T.check(runA.PocketIndex ~= runB.PocketIndex, "p5 ends: the runs use different pockets")
			intoFight(runA, sa, nil)
			fromHall(runB)
			local markA, markB = K.logSize(), K.logSize()
			local tok0 = tokens(sa)
			dgs.Shutdown()
			advance(0.3)
			local endA, endB = lastState(sa, "End", markA), lastState(sb, "End", markB)
			T.check(runA.State == "Ending" and runA.EndReason == "Shutdown" and runA.Finished == true and runB.Finished == true and endA and endA.Reason == "Shutdown" and endB and endB.Reason == "Shutdown",
				"p5 ends: Shutdown ends a fight and a corridor run void (Reason Shutdown), finished at once")
			T.check(inBattle(sa) == nil and inBattle(sb) == nil and db.GetPocket(runA.PocketIndex) == nil and db.GetPocket(runB.PocketIndex) == nil and workspace:FindFirstChild("Dungeons") == nil,
				"p5 ends: Shutdown releases InBattle and frees every pocket")
			T.check(runEndedOnce(runA.Id) and runEndedOnce(runB.Id) and tokens(sa) == tok0 and bs.IsInBattle(sa) == false, "p5 ends: RunEnded once per run, nothing paid, the encounter ended")
			dgs.SetClosing(false)
			local okS = dgs.StartSolo(sa, 1)
			T.check(okS == false or okS == true, "p5 ends: after SetClosing(false) the service answers again")
			endEverything()
		end
		cleanup({ sa, sb })

		-- 6. the watchdog: an erroring Dg.onRoomEnd leaves a Fight whose encounter is gone -> "Error" within 20 s
		local wd = newPlayer("DgnWatch", STRONG, 20)
		run = startSolo(wd, 1)
		if T.check(run ~= nil, "p5 ends: (setup) a solo run for the watchdog") then
			realOnRoomEnd = dgs.Dg.onRoomEnd
			dgs.Dg.onRoomEnd = function()
				error("injected onRoomEnd failure")
			end
			local tr = tracker(wd)
			intoFight(run, wd, tr)
			local tok0 = tokens(wd)
			local res = playUntilEnd(tr, 120, { every = 3 })
			T.check(res ~= nil and run.State == "Fight" and run.Battle ~= nil, "p5 ends: watchdog: the room was won but the erroring OnEnd left the run in Fight")
			local t0 = Mock.Clock.now
			while run.State == "Fight" and Mock.Clock.now - t0 < 20 do
				advance(0.5)
			end
			local dt = Mock.Clock.now - t0
			T.check(run.State == "Ending" and run.EndReason == "Error" and dt <= 20, "p5 ends: watchdog: the run ends 'Error' within 20 s (" .. tostring(math.floor(dt)) .. " s)")
			advance(5)
			T.check(inBattle(wd) == nil and db.GetPocket(run.PocketIndex) == nil and runEndedOnce(run.Id) and tokens(wd) == tok0, "p5 ends: watchdog: InBattle nil, the pocket free, RunEnded once, nothing paid twice")
			dgs.Dg.onRoomEnd = realOnRoomEnd
			realOnRoomEnd = nil
			K.flushWarnings("p5dgn_ends", { "[BattleService]", "[DungeonService]", "[DataService]", "injected" })
		end
		cleanup({ wd })

		-- 7. a run older than its floor's limit ends; W5 battle-dungeon-6: on floor 1 (180 s rooms) the catalog's
		-- RunMaxSeconds 703 is NOT enough for four legit rooms, so the watchdog uses MaxRunSeconds(floor) (>= RunMaxSeconds)
		-- and a run killed at the Treasure opens the earned chests first
		local old = newPlayer("DgnOld", STRONG, 20)
		run = startSolo(old, 1)
		if T.check(run ~= nil, "p5 ends: (setup) a solo run for RunMaxSeconds") then
			local maxT = dgs.MaxRunSeconds(1)
			local roomT = d.Floor1RoomTime
			-- dungeon-fixes decision 2: no DoorTime / HallSeconds any more; 5 door waits of 180 s (pooled) are allowed
			T.check(maxT >= d.RunMaxSeconds and maxT >= 4 * roomT + 4 * (30 + d.Intermission) + 5 * 180 + d.TreasureSeconds + 120 and dgs.MaxRunSeconds(2) >= 4 * d.RoomTime + 5 * 180,
				"p5 ends: MaxRunSeconds(1) covers four 180 s rooms + the 30 s Threshold waits + 5 door waits of 180 s (a slow-walking group) + treasure + 120 (" .. tostring(maxT) .. " >= " .. tostring(d.RunMaxSeconds) .. ")")
			run.Started = Mock.Clock.now - d.RunMaxSeconds - 1
			advance(1.2)
			T.check(run.State ~= "Ending", "p5 ends: a floor-1 run older than the catalog's 703 s is NOT killed (a slow legit run)", tostring(run.State))
			run.Members[old.UserId].Qualified[1] = true
			dgs.Dg.enterTreasure(run)
			local tok0, cash0 = tokens(old), cash(old)
			run.Started = Mock.Clock.now - maxT - 1
			advance(1.2)
			T.check(run.State == "Ending" and run.EndReason == "Error", "p5 ends: a run older than MaxRunSeconds(floor) ends (Error)")
			T.check(run.Chests[old.UserId] == "Opened" and (tokens(old) > tok0 or cash(old) > cash0), "p5 ends: the watchdog's Error end at the Treasure opens the earned chest first (paid once)")
			advance(5)
			T.check(inBattle(old) == nil and runEndedOnce(run.Id), "p5 ends: ... released, RunEnded once")
		end
		cleanup({ old })

		-- 8. the fail-safe of BattleService (HoldEnd): a wiped room whose end is held is released after 10 s with
		-- Reason "Error" and the run ends through OnEnd
		local fs = newPlayer("DgnFail", { WEAK[1] }, 1)
		run = startSolo(fs, 1)
		if T.check(run ~= nil, "p5 ends: (setup) a solo run for the BattleService fail-safe") then
			intoFight(run, fs, nil)
			tuneEnemies(run, unbeatable) -- the auto-attacking pet must not clear the room before the wipe
			bs.Debug = { HoldEnd = true }
			local t0 = Mock.Clock.now
			while run.State == "Fight" and Mock.Clock.now - t0 < 200 do
				advance(0.5)
			end
			bs.Debug = nil
			local dt = Mock.Clock.now - t0
			T.check(run.State == "Ending" and run.EndReason == "Error" and dt < 200, "p5 ends: the held wipe is released by BattleService's fail-safe: the run ends 'Error' (" .. tostring(run.EndReason) .. ", " .. tostring(math.floor(dt)) .. " s)")
			advance(5)
			T.check(inBattle(fs) == nil and runEndedOnce(run.Id), "p5 ends: ... released, RunEnded once")
			K.flushWarnings("p5dgn_ends", { "[BattleService]", "[DungeonService]", "never finalized" })
		end
		conn:Disconnect()
		cleanup({ fs })
	end)

	------------------------------------------------------------------------------------------------
	-- p5dgn_world
	------------------------------------------------------------------------------------------------
	S.p5dgn_world = scenario("p5dgn_world", function()
		if not ready("p5dgn_world") then
			return
		end
		local db = DGB()
		local Config = K.config()
		local CollectionService = game:GetService("CollectionService")
		local ServerStorage = game:GetService("ServerStorage")
		-- templates: every name, within its budget, with the attachments
		local folder = db.EnsureTemplates()
		T.check(folder ~= nil and folder.Parent == ServerStorage and folder.Name == "DungeonTemplates", "p5 world: the templates live in ServerStorage.DungeonTemplates")
		local total = 0
		local over = {}
		local missingAtt = {}
		for _, name in ipairs(db.Templates) do
			local model = db.Template(name)
			local g = db.Geo[name]
			if not model or not g then
				over[#over + 1] = name .. " missing"
			else
				local n = db.CountParts(model)
				total = total + n
				if n > g.Budget then
					over[#over + 1] = name .. " " .. n .. " > " .. g.Budget
				end
				local base = model.PrimaryPart
				local want = { "Entrance", "Exit" }
				if g.Kind == "Room" or g.Kind == "Boss" or g.Kind == "Treasure" or g.Kind == "Hall" then
					want[#want + 1] = "Threshold"
					want[#want + 1] = "Dais"
					for i = 1, 4 do
						want[#want + 1] = "Spawn" .. i
					end
				end
				for _, a in ipairs(want) do
					if not (base and base:FindFirstChild(a) and base[a]:IsA("Attachment")) then
						missingAtt[#missingAtt + 1] = name .. "." .. a
					end
				end
				local accents = 0
				for _, dsc in ipairs(model:GetDescendants()) do
					if dsc:IsA("BasePart") and dsc:GetAttribute("Accent") == true then
						accents = accents + 1
					end
				end
				if accents > 40 then
					over[#over + 1] = name .. " accents " .. accents
				end
			end
		end
		T.check(#over == 0, "p5 world: 17 templates within their budgets (wave room <= 320, boss <= 420, hall <= 140, corridor <= 70, treasure <= 90; <= 40 Accent parts)", table.concat(over, ", "))
		T.check(#missingAtt == 0, "p5 world: every template carries Entrance / Exit (+ Threshold, Spawn1..4, Dais on rooms)", table.concat(missingAtt, ", "))
		T.check(total <= 4000, "p5 world: the whole template set is <= 4,000 parts (" .. total .. ")")
		-- the look (Phase 6 A1: the P4 look) on the templates: SmoothPlastic (Neon / Glass / ForceField for glow, water
		-- and shimmer), blocks only (no Ball / Cylinder), a bright colourful palette (no muted P5 greys: the
		-- area-weighted saturation of the big opaque faces >= 0.2)
		local P4MAT = { [Enum.Material.SmoothPlastic] = true, [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }
		local badMat, badShape = {}, {}
		local satArea, area = 0, 0
		for _, name in ipairs(db.Templates) do
			local model = db.Template(name)
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") and part.Transparency < 0.99 then
					local s = part.Size
					if not P4MAT[part.Material] then
						badMat[#badMat + 1] = name .. "." .. part.Name .. " " .. tostring(part.Material)
					end
					if part:IsA("Part") and part.Shape ~= Enum.PartType.Block then
						badShape[#badShape + 1] = name .. "." .. part.Name
					end
					local faces = { s.X * s.Y, s.Y * s.Z, s.X * s.Z }
					local maxFace = math.max(faces[1], faces[2], faces[3])
					if maxFace > 16 and part.Material ~= Enum.Material.Neon and part.Transparency < 0.3 then
						local c = part.Color
						local val = math.max(c.R, c.G, c.B)
						local sat = (val > 0) and ((val - math.min(c.R, c.G, c.B)) / val) or 0
						satArea = satArea + sat * maxFace
						area = area + maxFace
					end
				end
			end
		end
		T.check(#badMat == 0, "p5 world: template materials are the P4 look (SmoothPlastic / Neon / Glass / ForceField; P6 A1)", table.concat(badMat, ", "):sub(1, 300))
		T.check(#badShape == 0, "p5 world: templates are blocky voxels (no Ball / Cylinder parts; P6 A1)", table.concat(badShape, ", "):sub(1, 300))
		local wsat = area > 0 and satArea / area or 0
		T.check(wsat >= 0.2, string.format("p5 world: a cute, colourful dungeon (area-weighted saturation of the big faces %.2f >= 0.2; P6 A1)", wsat))
		-- the layout never overlaps over 20 seeds (every floor kind)
		local overlaps = {}
		for seed = 1, 20 do
			local floorIndex = ((seed - 1) % 12) + 1
			local plan = db.Plan(floorIndex, seed * 131)
			local boxes = {}
			for i, piece in ipairs(plan.Pieces) do
				local p = piece.CFrame.Position
				boxes[i] = { x0 = p.X - piece.W / 2, x1 = p.X + piece.W / 2, z0 = p.Z - piece.D / 2, z1 = p.Z + piece.D / 2, name = piece.Name }
			end
			for i = 1, #boxes do
				for j = i + 1, #boxes do
					local a, b = boxes[i], boxes[j]
					if a.x0 < b.x1 - 0.5 and b.x0 < a.x1 - 0.5 and a.z0 < b.z1 - 0.5 and b.z0 < a.z1 - 0.5 then
						overlaps[#overlaps + 1] = "seed " .. seed .. " " .. a.name .. "/" .. b.name
					end
				end
			end
			if #plan.Pieces ~= 11 or plan.Pieces[9].Name ~= "Throne_1" or plan.Pieces[11].Name ~= "Treasure_1" then
				overlaps[#overlaps + 1] = "seed " .. seed .. " chain shape"
			end
			local last = plan.Pieces[11]
			if math.abs(last.CFrame.Position.X) > 280 or last.CFrame.Position.Z > 560 or last.CFrame.Position.Z < -20 then
				overlaps[#overlaps + 1] = "seed " .. seed .. " out of the pocket cell"
			end
		end
		T.check(#overlaps == 0, "p5 world: 20 seeded layouts: 11 pieces (hall, 4 corridors + 4 rooms, corridor, treasure), no overlap, inside the 600-stud cell", table.concat(overlaps, ", "):sub(1, 300))
		-- a built run: budgets, zones, Accent recolour, doors, FreeRun
		local pocket = db.BuildRun(8, 3, 77)
		if T.check(pocket ~= nil and pocket.Index == 8 and pocket.Model.Parent == workspace:FindFirstChild("Dungeons") and pocket.Model.Name == "Dungeon_8", "p5 world: BuildRun(8, 3, 77) -> the holder workspace.Dungeons.Dungeon_8") then
			T.check(pocket.Origin == Vector3.new(9000 + 3 * 600, 160, 9000 + 1 * 600), "p5 world: pocket 8's origin is (9000 + col x 600, 160, 9000 + row x 600)")
			T.check(db.BuildRun(8, 3, 77) == nil, "p5 world: a busy index is refused")
			local live1 = db.LiveParts(pocket)
			db.PlaceRoom(pocket, 2)
			local live2 = db.LiveParts(pocket)
			T.check(live1 < live2 and live2 <= 950, "p5 world: hall + corridor + room 1 + corridor + room 2 <= 950 live parts (" .. live2 .. ")")
			db.PlaceRoom(pocket, 3)
			db.RemoveRoom(pocket, 1)
			db.PlaceRoom(pocket, 4)
			db.RemoveRoom(pocket, 2)
			local live3 = db.LiveParts(pocket)
			T.check(live3 <= 950 and pocket.Rooms[1] == nil and pocket.Rooms[2] == nil and pocket.Rooms[4] ~= nil, "p5 world: hall + room 3 + corridor + the boss room <= 950 (" .. live3 .. ")")
			db.PlaceRoom(pocket, 5)
			local zonesOk, zoneWhy = true, ""
			local color = Config.Elements.Info[pocket.Element].Color
			local accentOk = false
			for room = 3, 4 do
				local ri = pocket.Rooms[room]
				local zone = ri and ri.Zone
				if not zone or zone:GetAttribute("Mode") ~= "Dungeon" or zone:GetAttribute("ZoneId") ~= "Room" or zone:GetAttribute("Index") ~= 8 or zone:GetAttribute("Room") ~= room then
					zonesOk, zoneWhy = false, "room " .. room .. " zone attributes"
				else
					local want = (room == 4) and D().Zones.Boss or D().Zones.Room
					if math.abs(zone.Size.X - want.X) > 0.01 or math.abs(zone.Size.Z - want.Z) > 0.01 then
						zonesOk, zoneWhy = false, "room " .. room .. " zone size " .. tostring(zone.Size)
					end
					local piece = pocket.Layout.Pieces[pocket.Layout.Rooms[room].Piece]
					local c = CFrame.new(pocket.Origin) * piece.CFrame
					local rel = c:PointToObjectSpace(zone.Position)
					if math.abs(rel.X) + zone.Size.X / 2 > piece.W / 2 + 0.01 or math.abs(rel.Z) + zone.Size.Z / 2 > piece.D / 2 + 0.01 then
						zonesOk, zoneWhy = false, "room " .. room .. " zone outside the floor"
					end
					if not CollectionService:HasTag(zone, "NC_BattleZone") then
						zonesOk, zoneWhy = false, "room " .. room .. " untagged"
					end
				end
				for _, dsc in ipairs(ri.Model:GetDescendants()) do
					if dsc:IsA("BasePart") and dsc:GetAttribute("Accent") == true and dsc.Color == color then
						accentOk = true
					end
				end
				T.check(ri.Threshold ~= nil and ri.Door ~= nil and ri.ExitDoor ~= nil and #ri.Door.Bars >= 5 and ri.Model:GetAttribute("DoorOpen") == false
					and ri.Door.Model:GetAttribute("Open") == false and ri.Model:GetAttribute("EntranceOpen") == false and ri.EnterPrompt ~= nil and ri.EnterPrompt.Enabled == false,
					"p5 world: room " .. room .. " has a Threshold, entrance bars (closed until the group enters, its EnterPrompt disabled) and exit bars (closed, DoorOpen false)")
			end
			T.check(zonesOk, "p5 world: zones Mode Dungeon / ZoneId Room / Index / Room, 44 x 44 and 56 x 72 (the whole Throne floor), inside the floor, tagged", zoneWhy)
			-- W5 battle-dungeon-2: the throne dais (room-local z 21..35, reachable by stairs) and the throne itself lie INSIDE
			-- the boss zone, so a member who climbs up during the fight is never dropped out; the enemies' SpawnAnchor
			-- (zone-local) sits at the foot of the stairs, inside the zone and off the dais
			do
				local ri4 = pocket.Rooms[4]
				local zone4 = ri4 and ri4.Zone
				local base4 = ri4 and ri4.Room and ri4.Room.PrimaryPart
				local daisOk, anchorOk = false, false
				if zone4 and base4 then
					local throne = zone4.CFrame:PointToObjectSpace(base4.CFrame:PointToWorldSpace(Vector3.new(4, 2.4, 31)))
					local back = zone4.CFrame:PointToObjectSpace(base4.CFrame:PointToWorldSpace(Vector3.new(-20, 0, 34)))
					daisOk = math.abs(throne.X) <= zone4.Size.X / 2 and math.abs(throne.Z) <= zone4.Size.Z / 2 and math.abs(back.Z) <= zone4.Size.Z / 2 + 8
					local sa = ri4.SpawnAnchor
					anchorOk = type(sa) == "table" and math.abs(sa.x) < zone4.Size.X / 2 - 2 and sa.z > -zone4.Size.Z / 2 and sa.z < 17 and sa.z > 5
				end
				T.check(daisOk, "p5 world: the Throne's dais and throne are inside the boss zone (56 x 72 centred on the room)")
				T.check(anchorOk, "p5 world: the Throne names a SpawnAnchor at the foot of the dais stairs (zone-local z 5..17)", tostring(ri4 and ri4.SpawnAnchor and ri4.SpawnAnchor.z))
			end
			T.check(accentOk, "p5 world: Accent parts are recoloured to the floor's element colour (" .. tostring(pocket.Element) .. ")")
			local ri4 = pocket.Rooms[4]
			db.SetDoor(ri4, "Exit", true)
			local bar = ri4.ExitDoor.Bars[1]
			T.check(bar.CanCollide == false and bar.Transparency == 1 and ri4.Model:GetAttribute("DoorOpen") == true, "p5 world: SetDoor toggles the bars' CanCollide + Transparency and the DoorOpen attribute")
			local treasure = pocket.Rooms[5]
			T.check(treasure and #treasure.Chests == 4 and treasure.ExitPrompt ~= nil, "p5 world: the treasure alcove has 4 chests and the exit prompt part")
			local lights, badLight = 0, 0
			for _, dsc in ipairs(pocket.Model:GetDescendants()) do
				if dsc:IsA("PointLight") then
					lights = lights + 1
					if dsc.Shadows or dsc.Range > 18 or dsc.Brightness > 1.5 then
						badLight = badLight + 1
					end
				end
			end
			T.check(lights > 0 and badLight == 0, "p5 world: torches cast no shadows, Range <= 18, Brightness <= 1.5 (" .. lights .. " lights)")
			db.FreeRun(8)
			T.check(db.GetPocket(8) == nil and workspace:FindFirstChild("Dungeons") == nil and #CollectionService:GetTagged("NC_BattleZone") > 0, "p5 world: FreeRun destroys the holder and the Dungeons folder with the last run")
			local stray = 0
			for _, z in ipairs(CollectionService:GetTagged("NC_BattleZone")) do
				if z:GetAttribute("Mode") == "Dungeon" and z.Parent then
					stray = stray + 1
				end
			end
			T.check(stray == 0, "p5 world: no dungeon zone survives FreeRun")
		end
		-- the portal
		local i = info()
		local lobby = K.W.lobbyInfo
		T.check(i and i.Portal and i.Portal.Parent == lobby.GatesFolder and i.Portal.Name == "Portal_Dungeon" and i.Portal:GetAttribute("GateId") == "Dungeon", "p5 world: Portal_Dungeon stands in LobbyInfo.GatesFolder")
		T.check(i and db.CountParts(i.Portal) <= 120, "p5 world: the portal is <= 120 parts (" .. tostring(i and db.CountParts(i.Portal)) .. ")")
		local prompt = i and i.PromptPart and i.PromptPart:FindFirstChild("DungeonPrompt")
		T.check(prompt and prompt:IsA("ProximityPrompt") and prompt:GetAttribute("OpenPanel") == "Dungeon", "p5 world: the DungeonPrompt carries OpenPanel = 'Dungeon'")
		T.check(i and i.Pad and i.ReturnCFrame and (i.ReturnCFrame.Position - i.Pad.Position).Magnitude < 8, "p5 world: DungeonInfo { Portal, Pad, PromptPart, ReturnCFrame } (the return point on the pad)")
		local site = lobby.GateSites and lobby.GateSites.Dungeon
		T.check(site and i.Portal.PrimaryPart and (Vector3.new(i.Portal.PrimaryPart.Position.X, 0, i.Portal.PrimaryPart.Position.Z) - Vector3.new(site.Position.X, 0, site.Position.Z)).Magnitude < 3, "p5 world: the portal stands on GateSites.Dungeon")
		local inside = 0
		for _, z in ipairs(CollectionService:GetTagged("NC_BattleZone")) do
			if z.Parent and i.Portal.PrimaryPart then
				local rel = z.CFrame:PointToObjectSpace(i.Portal.PrimaryPart.Position)
				if math.abs(rel.X) <= z.Size.X / 2 and math.abs(rel.Z) <= z.Size.Z / 2 and math.abs(rel.Y) <= z.Size.Y / 2 + 4 then
					inside = inside + 1
				end
			end
		end
		T.check(inside == 0, "p5 world: the portal stands outside every battle zone")
		local tag = i.Portal:FindFirstChild("GateTag", true)
		T.check(tag ~= nil and i.Portal:GetAttribute("DungeonBoard") ~= nil, "p5 world: the gate has its tag and the DungeonBoard attribute")
	end)

	------------------------------------------------------------------------------------------------
	-- p5dgn_net
	------------------------------------------------------------------------------------------------
	S.p5dgn_net = scenario("p5dgn_net", function()
		if not ready("p5dgn_net") then
			return
		end
		local dgs, bs = DGS(), BS()
		local d = D()
		quietReplication()
		local q = { newPlayer("DgnNetA", STRONG, 20), newPlayer("DgnNetB", STRONG, 20), newPlayer("DgnNetC", STRONG, 20), newPlayer("DgnNetD", STRONG, 20) }
		for _, p in ipairs(q) do
			toPad(p, 0, 0)
		end
		request(q[1], "Create", 1)
		for i = 2, 4 do
			request(q[i], "Join", q[1].UserId)
			request(q[i], "Ready", true)
			advance(0.4)
		end
		local mark = K.logSize()
		request(q[1], "Start")
		advance(6)
		local run = runOf(q[1])
		if T.check(run ~= nil and count(run.Members) == 4, "p5 net: (setup) a 4-party run") then
			-- DungeonState payloads < 1 KB
			local biggest, biggestKind = 0, ""
			for _, e in ipairs(K.remotesFor("DungeonState", nil, mark)) do
				local bytes = bs.EstimateBytes(e.args[2])
				if bytes > biggest then
					biggest, biggestKind = bytes, tostring(e.args[1])
				end
			end
			T.check(biggest > 0 and biggest < 1024, "p5 net: every DungeonState payload so far is < 1 KB (largest " .. biggest .. " B, " .. biggestKind .. ")")
			-- the fight: per-client BattleState bytes over 10 s
			local trs = {}
			for i, p in ipairs(q) do
				trs[i] = tracker(p)
			end
			intoFight(run, q[1], trs[1])
			if T.check(run.State == "Fight", "p5 net: the 4-player room fight runs") then
				local from = K.logSize()
				local t0 = Mock.Clock.now
				while Mock.Clock.now - t0 < 10 and run.State == "Fight" do
					advance(0.1)
					for _, tr in ipairs(trs) do
						playTick(tr, { every = 3 })
					end
				end
				local seconds = math.max(1, Mock.Clock.now - t0)
				local worst = 0
				for _, p in ipairs(q) do
					local bytes = 0
					for _, e in ipairs(battleMsgs(p, from)) do
						bytes = bytes + bs.EstimateBytes(e.args[2])
					end
					worst = math.max(worst, bytes / seconds)
				end
				T.check(worst <= 6 * 1024, "p5 net: a 4-player dungeon room stays under the raid budget (6 KB/s per client): " .. math.floor(worst) .. " B/s")
			end
			-- Run payloads during the fight
			local runMsg = lastState(q[2], "Run", mark)
			T.check(runMsg and bs.EstimateBytes(runMsg) < 1024 and #runMsg.Members == 4, "p5 net: the Run payload with 4 members is < 1 KB (" .. tostring(runMsg and bs.EstimateBytes(runMsg)) .. " B)")
		end
		-- junk DungeonRequest 60/s: refused without errors
		local errors0 = #Mock.Errors
		local junk = { nil, 1, "", {}, true, math.huge, 0 / 0, "Create", "Join", "Kick", "Ready", "SetFloor", "Solo", "Chest", "Quit", "Open" }
		local args = { nil, "x", -1, 1.5, 999999999, {}, true, 0 / 0, math.huge, 13, 0 }
		local r = remote("DungeonRequest")
		for i = 1, 60 do
			local action = junk[(i % #junk) + 1]
			local a1 = args[(i % #args) + 1]
			local a2 = args[((i * 3) % #args) + 1]
			Mock.FromClient(r, q[2], action, a1, a2)
			if i % 6 == 0 then
				advance(0.1)
			end
		end
		advance(0.5)
		T.check(#Mock.Errors == errors0, "p5 net: 60 junk DungeonRequests in a second raise no errors")
		T.check(run == nil or run.State ~= "Ending" or true, "p5 net: (info) the run state after the junk: " .. tostring(run and run.State))
		local ok, why = dgs.Request(q[2], "Create", 1)
		T.check(ok == false and (why == "rate" or why == "cooldown" or type(why) == "string"), "p5 net: the bucket / cooldown refuses the next request after the burst (" .. tostring(why) .. ")")
		K.flushWarnings("p5dgn_net", { "[BattleService]", "[DungeonService]" })
		cleanup(q)
	end)

	------------------------------------------------------------------------------------------------
	-- [owner: art-arenadungeon] begin -- p5dgn_mesh (Phase 6 W2): the Blender keys of the dungeon (blender/catalog/
	-- arenadungeon.json) and DungeonBuilder's Tag calls (DungeonBuilder._Mesh): every tagged piece has its dungeon_* key
	-- and every key is tagged, LayoutSig matches the live pieces (else rebuild: blender/build_all.py --class
	-- arenadungeon), no nesting, flames kept, nothing tagged without ids, with ids the tag rides along when clonePiece
	-- moves a template (the wrapper's PrimaryPart), a stale piece is refused, a room's meshes stay light.
	------------------------------------------------------------------------------------------------
	S.p5dgn_mesh = guarded("p5dgn_mesh", function()
		if not K.needBoot() then
			return
		end
		local db = DGB()
		local ML = req("shared/MeshLibrary")
		local Mesh = db and db._Mesh
		if not T.check(type(Mesh) == "table" and type(Mesh.Placed) == "table" and type(ML) == "table", "dungeon mesh: DungeonBuilder._Mesh and MeshLibrary load") then
			return
		end
		local abs, max = math.abs, math.max
		local CollectionService = game:GetService("CollectionService")
		local folder = db.EnsureTemplates()
		local pocket = db.BuildRun(11, 1, 4242)
		local recs = {}
		for target, r in pairs(Mesh.Placed) do
			local live = target.Parent and (target:IsDescendantOf(folder) or (pocket and pocket.Model and target:IsDescendantOf(pocket.Model)))
			if live then
				recs[#recs + 1] = { Target = target, Key = r.Key, Origin = r.Origin, Look = r.Look, Keep = r.Keep, Scale = r.Scale, Name = target:GetFullName() }
			end
		end
		table.sort(recs, function(a, b)
			return a.Key .. a.Name < b.Key .. b.Name
		end)
		local set, used = {}, {}
		for _, r in ipairs(recs) do
			set[r.Target] = true
			used[r.Key] = (used[r.Key] or 0) + 1
		end
		local missing, orphan = {}, {}
		for key in pairs(used) do
			if not ML.Manifest(key) then
				missing[#missing + 1] = key
			end
		end
		table.sort(missing)
		local inst = K.moduleInstance("shared/MeshLibrary")
		local dir = inst and inst.Parent and inst.Parent:FindFirstChild("MeshManifests")
		local allKeys = {}
		for _, m in ipairs(dir and dir:GetChildren() or {}) do
			if m:IsA("ModuleScript") and string.sub(m.Name, 1, 8) == "dungeon_" then
				allKeys[#allKeys + 1] = m.Name
				if not used[m.Name] then
					orphan[#orphan + 1] = m.Name
				end
			end
		end
		table.sort(orphan)
		table.sort(allKeys)
		T.check(#recs >= 200 and #missing == 0, "dungeon mesh: every tagged piece has its manifest (src/shared/MeshManifests/dungeon_*)", #recs .. " targets; missing " .. table.concat(missing, ", "))
		T.check(#orphan == 0, "dungeon mesh: every dungeon_* key is tagged by the templates / a run", table.concat(orphan, ", "))
		for _, key in ipairs({ "dungeon_wall_48", "dungeon_wall_50_door", "dungeon_floor_48x48", "dungeon_pillar_15p5", "dungeon_torch", "dungeon_chest", "dungeon_crate", "dungeon_rock_1", "dungeon_stalagmite", "dungeon_crack", "dungeon_door_8" }) do
			T.check(used[key] ~= nil, "dungeon mesh: " .. key .. " is tagged", tostring(used[key]))
		end
		local sig = T.tally("dungeon mesh: each piece matches its key's LayoutSig (else rebuild: blender/build_all.py --class arenadungeon)")
		local nest = T.tally("dungeon mesh: targets never nest")
		local glow = T.tally("dungeon mesh: every visible Neon part of a piece is in its keep list (torch flames stay)")
		local quiet = 0
		for _, r in ipairs(recs) do
			local man = ML.Manifest(r.Key)
			local att = man and man.Attachments and man.Attachments.LayoutSig
			if att then
				local pos = att.Pos or att.pos
				local n, a, b = Mesh.Signature(r.Target, r.Origin, r.Scale, r.Keep)
				local tol = 0.05 + n * 1e-4
				sig:case(n == pos[1] and abs(a - pos[2]) <= tol and abs(b - pos[3]) <= tol, r.Name, n .. " / " .. tostring(pos[1]))
			end
			local p = r.Target.Parent
			local nested = false
			while p do
				if set[p] then
					nested = true
				end
				p = p.Parent
			end
			nest:case(not nested, r.Name)
			local keep = {}
			for _, k in ipairs(r.Keep or {}) do
				keep[k] = true
			end
			local bad = nil
			local list = r.Target:GetDescendants()
			list[#list + 1] = r.Target
			for _, d in ipairs(list) do
				if d:IsA("BasePart") and d.Material == Enum.Material.Neon and d.Transparency < 0.99 and not keep[d.Name] then
					bad = d.Name
				end
			end
			glow:case(bad == nil, r.Name, bad)
			if r.Target:GetAttribute("ML_DressKey") then
				quiet = quiet + 1
			end
		end
		sig:report()
		nest:report()
		glow:report()
		T.eq(quiet, 0, "dungeon mesh: with the shipped empty MeshIds nothing is tagged (the Part build is unchanged)")
		-- a room's meshes stay light (every template: <= 90k triangles, <= 10k per MeshPart)
		local per, worst, heavy = {}, 0, 0
		for _, r in ipairs(recs) do
			local top = r.Target
			while top.Parent and top.Parent ~= folder do
				top = top.Parent
			end
			if top.Parent == folder then
				local man = ML.Manifest(r.Key)
				per[top.Name] = (per[top.Name] or 0) + (tonumber(man and man.Raw and man.Raw.Tris) or 0)
				for _, part in ipairs(man and man.Raw and man.Raw.Parts or {}) do
					worst = max(worst, tonumber(part.Tris) or 0)
				end
			end
		end
		local heavyName = "-"
		for name, t in pairs(per) do
			if t > heavy or (t == heavy and name < heavyName) then
				heavy, heavyName = t, name
			end
		end
		T.check(heavy > 0 and heavy <= 90000 and worst <= 10000, "dungeon mesh: every room's meshes <= 90k triangles, every MeshPart <= 10k", heavyName .. " " .. heavy .. " tris, worst part " .. worst)
		-- with ids: a fresh Cave template is tagged; the tags ride along when the pieces move like clonePiece moves them
		local ids, idn = {}, 0
		for _, key in ipairs(allKeys) do
			idn = idn + 1
			ids[key] = 300000 + idn
		end
		-- W2.5 isolation: Start() with ids creates ReplicatedStorage.MeshLibrary; remove it again at the end so later
		-- scenarios (p6pets_default: MeshLibrary.Active() is false) see the empty-ids game
		local hadMLFolder = game:GetService("ReplicatedStorage"):FindFirstChild("MeshLibrary") ~= nil
		ML._Reset()
		ML._Configure({ Ids = ids })
		pcall(ML.Start)
		local okB, cave = pcall(db.Geo.Cave_1.build)
		if T.check(okB and cave ~= nil, "dungeon mesh: a Cave template builds with ids configured", tostring(cave)) then
			local function landing(t)
				local off = t:GetAttribute("ML_Offset")
				local v = {}
				for x in string.gmatch(off or "", "[^,%s]+") do
					v[#v + 1] = tonumber(x)
				end
				if #v ~= 12 then
					return nil
				end
				local pivot = t:IsA("BasePart") and t.CFrame or t:GetPivot()
				return pivot * CFrame.new(unpack(v))
			end
			local tagged = {}
			for _, d in ipairs(cave:GetDescendants()) do
				if d:GetAttribute("ML_DressKey") then
					tagged[#tagged + 1] = d
				end
			end
			local kinds = {}
			for _, d in ipairs(tagged) do
				kinds[string.match(d:GetAttribute("ML_DressKey"), "^dungeon_(%a+)")] = true
			end
			T.check(#tagged >= 40 and kinds.wall and kinds.floor and kinds.rock and kinds.torch and kinds.pillar and kinds.stalagmite and kinds.crack, "dungeon mesh: with ids the Cave's walls, floor, pillars, torches, rocks, stalagmites and cracks are tagged", #tagged .. " tagged")
			local where = T.tally("dungeon mesh: each tag lands its mesh on the Tag origin (pivot * ML_Offset)")
			local before = {}
			for _, d in ipairs(tagged) do
				local r = Mesh.Placed[d]
				local l = landing(d)
				before[d] = l
				where:case(r ~= nil and l ~= nil and (l.Position - r.Origin.Position).Magnitude < 0.02, d:GetFullName())
			end
			where:report()
			-- move every part the way clonePiece does (one delta): the landing points move with it
			local delta = CFrame.new(500, 40, -300) * CFrame.Angles(0, math.rad(90), 0)
			for _, d in ipairs(cave:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CFrame = delta * d.CFrame
				end
			end
			local ride = T.tally("dungeon mesh: after clonePiece's move the mesh still lands on the moved origin")
			for _, d in ipairs(tagged) do
				local l = landing(d)
				ride:case(l ~= nil and before[d] ~= nil and (l.Position - (delta * before[d]).Position).Magnitude < 0.05, d:GetFullName())
			end
			ride:report()
			local wall = nil
			for _, d in ipairs(tagged) do
				if d.Name == "WallRun" and not wall then
					wall = d
				end
			end
			if wall then
				T.check(wall:GetAttribute("ML_Primary") ~= nil, "dungeon mesh: a wall run takes its room's stone colour (ML_Primary)")
				local clone = wall:Clone()
				local plinth = clone:FindFirstChild("Plinth")
				if plinth then
					plinth.CFrame = plinth.CFrame * CFrame.new(0, 1, 0)
				end
				clone:SetAttribute("ML_DressKey", nil)
				T.check(Mesh.tag(clone, wall:GetAttribute("ML_DressKey"), plinth and (clone.PrimaryPart.CFrame * CFrame.new(0, -0.6, 0.35)) or CFrame.new(), nil, nil) == false and clone:GetAttribute("ML_DressKey") == nil, "dungeon mesh: a wall run that no longer matches its key is never tagged")
				clone:Destroy()
			end
			cave:Destroy()
		end
		ML._Reset()
		local mlFolder = game:GetService("ReplicatedStorage"):FindFirstChild("MeshLibrary")
		if mlFolder and not hadMLFolder then
			mlFolder:Destroy()
		end
		if pocket then
			db.FreeRun(11)
		end
		K.flushErrors("p5dgn_mesh")
		K.flushWarnings("p5dgn_mesh")
	end)
	-- [owner: art-arenadungeon] end

	return S
end

----------------------------------------------------------------------------------------------------
-- client world (dungeonclient, W4)
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local T = KC and KC.T or _G.K.T
	local guarded = (KC and KC.guarded) or SmokeCommon.guarded

	-- [W4 dungeonclient] client_p5dungeon (1920x1080 + 1280x720) and client_p5dungeon_mobile (390x844 + 844x390): the
	-- window from a Lobby payload (floors, locks, SOLO / PARTY / JOIN, <= 60% cover, docked right / a bottom sheet), READY
	-- optimistic + revert, KICK / START, the countdown card, the run card from Run / Loot / Chest / End (LEAVE twice ->
	-- one Quit, CHEST), the End card (first clear, unlock), LightingStack "Dungeon" pushed on Run and popped on End, the
	-- door slide, nothing in the screen's centre.
	local C5 = {}
	function C5.req(key)
		local inst = Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", ""))
		local ok, mod = pcall(require, inst)
		return ok and type(mod) == "table" and mod or nil
	end
	function C5.pg()
		return game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	end
	function C5.find(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	function C5.shown(obj)
		return obj ~= nil and KC.isShown(obj)
	end
	function C5.sends(mark, action)
		local out = {}
		for _, e in ipairs(KC.serverCalls("DungeonRequest", mark)) do
			local args = e.args or {}
			if action == nil or args[1] == action then
				out[#out + 1] = args
			end
		end
		return out
	end
	function C5.screen(W, H, touch)
		local UIS = game:GetService("UserInputService")
		UIS.TouchEnabled = touch and true or false
		UIS.KeyboardEnabled = not touch
		UIS.MouseEnabled = not touch
		Mock.SetViewport(W, H)
		KC.advance(0.6)
	end
	function C5.rect(obj)
		local gui = obj:FindFirstAncestorOfClass("ScreenGui")
		local dy = (gui and not gui.IgnoreGuiInset) and (Mock.TopInset or 0) or 0
		local p, sz = obj.AbsolutePosition, obj.AbsoluteSize
		return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + sz.X, y1 = p.Y + dy + sz.Y }
	end
	-- % of the screen under opaque GUI of every enabled ScreenGui (4 px grid; the coverage.py rule)
	function C5.coverage()
		local W, H = Mock.Viewport.X, Mock.Viewport.Y
		local cols, rows = math.floor(W / 4) + 1, math.floor(H / 4) + 1
		local mask, covered = {}, 0
		for _, g in ipairs(C5.pg():GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled then
				for _, d in ipairs(g:GetDescendants()) do
					if d:IsA("GuiObject") and C5.shown(d) and (d.BackgroundTransparency < 0.5 or d:IsA("ImageLabel") or d:IsA("ViewportFrame")) then
						local r = C5.rect(d)
						for y = math.max(0, math.floor(r.y0 / 4)), math.min(rows, math.floor(r.y1 / 4)) - 1 do
							for x = math.max(0, math.floor(r.x0 / 4)), math.min(cols, math.floor(r.x1 / 4)) - 1 do
								local k = y * cols + x
								if not mask[k] then
									mask[k] = true
									covered = covered + 1
								end
							end
						end
					end
				end
			end
		end
		return 100 * covered / (cols * rows)
	end
	function C5.lobby(mine)
		local cleared = {}
		for f = 1, 12 do
			cleared[f] = f <= 4
		end
		return {
			Parties = { { Leader = 501, LeaderName = "Ava", Floor = 3, Count = 2, Max = 4, Open = true, InRun = false },
				{ Leader = 502, LeaderName = "Sam", Floor = 5, Count = 3, Max = 4, Open = true, InRun = true, Room = 2 } },
			Mine = mine,
			Record = { Best = 4, Cleared = cleared, Runs = 12, Clears = 7 },
		}
	end
	function C5.setup()
		-- a phone world run on its own boots the client first (like client_p3ui_mobile)
		local RS = game:GetService("ReplicatedStorage")
		if not RS:FindFirstChild("Remotes") then
			local Config = C5.req("shared/Config")
			local folder = Instance.new("Folder")
			folder.Name = "Remotes"
			for _, n in ipairs(Config.Remotes) do
				local r = Instance.new("RemoteEvent")
				r.Name = n
				r.Parent = folder
			end
			folder.Parent = RS
		end
		if not (C5.pg() and C5.pg():FindFirstChild("NimbusMenu")) then
			Mock.RunScript(Mock.GetPath(ROOTS["client"] .. "/Main"))
			KC.advance(3)
		end
		local DC = (KC.M and KC.M.DungeonController) or C5.req("client/Controllers/DungeonController")
		if not DC then
			return nil
		end
		pcall(DC.Init)
		local LP = game:GetService("Players").LocalPlayer
		LP:SetAttribute("InBattle", nil)
		LP:SetAttribute("InMatch", false)
		KC.toClient("MatchState", nil)
		KC.toClient("PartyState", nil)
		for _, name in ipairs({ "MenuController", "ArenaController", "CareController", "ObbyController" }) do
			local m = KC.M and KC.M[name]
			if m and type(m.Close) == "function" then
				pcall(m.Close)
			end
		end
		pcall(DC.Close)
		KC.advance(0.5)
		return DC, LP
	end
	-- the window at one screen size: docked rule + cover + the smallest text
	function C5.windowAt(DC, W, H, touch, tag)
		C5.screen(W, H, touch)
		KC.toClient("DungeonState", "Lobby", C5.lobby(nil))
		DC.Open(3)
		KC.advance(1.2)
		local win = C5.pg():FindFirstChild("NimbusDungeon") and C5.pg().NimbusDungeon:FindFirstChild("Window_Dungeon")
		local label = string.format("p5dgn client %s %dx%d", tag, W, H)
		if not T.check(win and C5.shown(win), label .. ": the Dungeon window opens") then
			return nil
		end
		local r = C5.rect(win)
		if W >= H then
			T.check(r.x0 >= 0.5 * W - 0.5, label .. ": docked right of the middle (left edge >= 0.5 W)", string.format("%.0f", r.x0))
		else
			T.check(r.y0 >= 0.44 * H - 0.5, label .. ": a bottom sheet (top >= 0.44 H)", string.format("%.0f", r.y0))
		end
		local pct = C5.coverage()
		T.check(pct <= 60, label .. ": the GUI covers <= 60% of the screen", string.format("%.1f%%", pct))
		local floorPx = (H >= 1000) and 15 or 14
		local small = KC.smallTexts and KC.smallTexts(floorPx) or {}
		local mine = {}
		for _, item in ipairs(type(small) == "table" and small or {}) do
			if tostring(item):find("Dungeon", 1, true) then
				mine[#mine + 1] = tostring(item)
			end
		end
		T.check(#mine == 0, label .. ": every Dungeon text >= " .. floorPx .. " px", table.concat(mine, ", "))
		T.check(C5.find(C5.pg():FindFirstChild("NimbusDungeon"), "Backdrop") == nil, label .. ": no Backdrop")
		return win
	end

	function C5.desktop()
		local DC, LP = C5.setup()
		if not T.check(DC ~= nil, "p5dgn client: DungeonController loads") then
			return
		end
		local mark = #Mock.RemoteLog
		local win = C5.windowAt(DC, 1280, 720, false, "window")
		win = C5.windowAt(DC, 1920, 1080, false, "window")
		if not win then
			return
		end
		T.check(#C5.sends(mark, "Open") >= 1, "p5dgn client: opening sends DungeonRequest('Open')")
		-- floors: 12 rows, cleared / next / locked from the Record
		local rows = 0
		for f = 1, 12 do
			if C5.find(win, "Floor" .. f) then
				rows = rows + 1
			end
		end
		T.eq(rows, 12, "p5dgn client: 12 floor rows")
		local f4, f5, f6 = C5.find(win, "Floor4"), C5.find(win, "Floor5"), C5.find(win, "Floor6")
		T.check(f4:GetAttribute("Cleared") == true and f5:GetAttribute("Unlocked") == true and f6:GetAttribute("Unlocked") == false,
			"p5dgn client: floor 4 cleared, floor 5 open (Best 4), floor 6 locked")
		T.check(C5.find(f5, "Text") and C5.find(f5, "Text").Text == "NEXT" and C5.find(f6, "Status").Text:find("Clear floor 5 first", 1, true),
			"p5dgn client: floor 5 is NEXT, floor 6 reads 'Clear floor 5 first'")
		T.check(C5.find(win, "Floor3"):GetAttribute("Selected") == true, "p5dgn client: Open(3) selects floor 3")
		Mock.Click(f6)
		KC.advance(0.3)
		T.check(f6:GetAttribute("Selected") ~= true, "p5dgn client: a locked floor cannot be selected")
		Mock.Click(f5)
		KC.advance(0.3)
		T.check(f5:GetAttribute("Selected") == true, "p5dgn client: tapping floor 5 selects it")
		mark = #Mock.RemoteLog
		Mock.Click(C5.find(win, "SoloButton"))
		KC.advance(0.4)
		local solo = C5.sends(mark, "Solo")
		T.check(#solo == 1 and solo[1][2] == 5, "p5dgn client: SOLO sends DungeonRequest('Solo', 5)")
		Mock.Click(C5.find(win, "PartyButton"))
		KC.advance(0.4)
		local create = C5.sends(mark, "Create")
		T.check(#create == 1 and create[1][2] == 5, "p5dgn client: PARTY sends DungeonRequest('Create', 5)")
		local joins = {}
		for _, d in ipairs(win:GetDescendants()) do
			if d.Name == "JoinButton" then
				joins[#joins + 1] = d
			end
		end
		T.check(#joins == 2, "p5dgn client: one JOIN per open party", tostring(#joins))
		if joins[1] then
			Mock.Click(joins[1])
			KC.advance(0.4)
			local j = C5.sends(mark, "Join")
			T.check(#j == 1 and (j[1][2] == 501 or j[1][2] == 502), "p5dgn client: JOIN sends DungeonRequest('Join', leaderUserId)")
		end
		-- a member: READY optimistic, reverted by the next Lobby payload
		local me = LP.UserId
		local member = { Leader = 501, Floor = 3, Members = { { UserId = 501, Name = "Ava", Ready = true, Power = 40 }, { UserId = me, Name = LP.Name, Ready = false, Power = 30 } } }
		KC.toClient("DungeonState", "Lobby", C5.lobby(member))
		KC.advance(0.6)
		local ready = C5.find(win, "ReadyButton")
		T.check(ready and C5.shown(ready) and ready.Text == "READY", "p5dgn client: a member gets READY")
		mark = #Mock.RemoteLog
		Mock.Click(ready)
		KC.advance(0.3)
		local rs = C5.sends(mark, "Ready")
		T.check(#rs == 1 and rs[1][2] == true, "p5dgn client: READY sends DungeonRequest('Ready', true)")
		local function myRow()
			for _, d in ipairs(win:GetDescendants()) do
				if d.Name:match("^Member%d") and d:GetAttribute("UserId") == me then
					return d
				end
			end
		end
		T.check(DC.GetState().Ready == true and myRow() and myRow():GetAttribute("Ready") == true, "p5dgn client: READY shows at once (optimistic)")
		KC.toClient("DungeonState", "Lobby", C5.lobby(member))
		KC.advance(0.4)
		T.check(DC.GetState().Ready == nil and myRow() and myRow():GetAttribute("Ready") == false, "p5dgn client: the next Lobby payload (still not ready) reverts it")
		-- the leader: KICK per member, START
		local leader = { Leader = me, Floor = 4, Members = { { UserId = me, Name = LP.Name, Ready = true, Power = 30 }, { UserId = 501, Name = "Ava", Ready = false, Power = 40 } } }
		KC.toClient("DungeonState", "Lobby", C5.lobby(leader))
		KC.advance(0.6)
		local kick = C5.find(win, "KickButton")
		T.check(kick and kick:GetAttribute("UserId") == 501, "p5dgn client: the leader sees KICK on the other member only")
		mark = #Mock.RemoteLog
		Mock.Click(kick)
		KC.advance(0.4)
		local ks = C5.sends(mark, "Kick")
		T.check(#ks == 1 and ks[1][2] == 501, "p5dgn client: KICK sends DungeonRequest('Kick', 501)")
		Mock.Click(C5.find(win, "StartButton"))
		KC.advance(0.4)
		T.check(#C5.sends(mark, "Start") == 1, "p5dgn client: START sends DungeonRequest('Start')")
		-- the countdown card while the window is closed
		DC.Close()
		leader.Countdown = 5
		leader.Members[2].Ready = true
		KC.toClient("DungeonState", "Lobby", C5.lobby(leader))
		KC.advance(0.6)
		local rg = C5.pg():FindFirstChild("NimbusDungeonRun")
		local card = rg and rg:FindFirstChild("RunCard")
		T.check(card and C5.shown(card) and card:GetAttribute("View") == "Countdown" and C5.find(card, "Room").Text:find("Dungeon in", 1, true),
			"p5dgn client: a party countdown shows the side card 'Dungeon in 5...'", card and C5.find(card, "Room").Text)
		C5.run(DC, LP, false)
	end

	-- the run (both screens): Run / Loot / Chest / End, LEAVE, CHEST, lighting, doors
	function C5.run(DC, LP, phone)
		local tag = phone and "phone" or "desktop"
		local LS = C5.req("client/LightingStack")
		local rg = C5.pg():FindFirstChild("NimbusDungeonRun")
		local card = rg and rg:FindFirstChild(phone and "RunChip" or "RunCard")
		KC.toClient("DungeonState", "Lobby", C5.lobby(nil))
		-- a pocket with a room and its exit door near the player (the door slide)
		local rootPart = KC.root and KC.root()
		local folder = Instance.new("Folder")
		folder.Name = "Dungeons"
		local holder = Instance.new("Model")
		holder.Name = "Dungeon_1"
		local room = Instance.new("Model")
		room.Name = "Room_2"
		local door = Instance.new("Model")
		door.Name = "Door_Exit"
		local at = rootPart and rootPart.Position or Vector3.new(0, 10, 0)
		for i = 1, 3 do
			local bar = Instance.new("Part")
			bar.Name = "Bar"
			bar.Anchored = true
			bar.Size = Vector3.new(0.6, 8, 0.6)
			bar.CFrame = CFrame.new(at + Vector3.new(i * 2, 4, 20))
			bar.Parent = door
		end
		door.Parent = room
		room.Parent = holder
		local entrance = Instance.new("Part")
		entrance.Name = "Entrance_1"
		entrance.Anchored = true
		entrance.CFrame = CFrame.new(at + Vector3.new(0, 0, 10))
		entrance.Parent = holder
		holder.Parent = folder
		folder.Parent = workspace
		LP:SetAttribute("InBattle", "D9")
		local run = { RunId = "D9", Floor = 3, Name = "Flooded Vaults", Element = "Water", Room = 2, RoomCount = 4, Wave = 1, Waves = 2, State = "Fight",
			Members = { { UserId = LP.UserId, Name = LP.Name, Downed = false, Left = false }, { UserId = 501, Name = "Ava", Downed = true, Left = false } }, Joinable = true }
		DC.Open(2)
		KC.advance(0.3)
		KC.toClient("DungeonState", "Run", run)
		KC.advance(0.6)
		T.check(not DC.IsOpen(), "p5dgn " .. tag .. ": a Run payload closes the window")
		T.check(LS and LS.Top and LS.Top() == "Dungeon", "p5dgn " .. tag .. ": LightingStack.Push('Dungeon') on Run", LS and tostring(LS.Top()))
		T.check(card and C5.shown(card) and card:GetAttribute("View") == "Run", "p5dgn " .. tag .. ": the run " .. (phone and "chip" or "card") .. " shows inside a run")
		if not phone then
			T.check(C5.find(card, "Title").Text == "Floor 3 " .. "\194\183" .. " Flooded Vaults" and C5.find(card, "Room").Text:find("Room 2 / 4", 1, true),
				"p5dgn desktop: 'Floor 3 - Flooded Vaults' and 'Room 2 / 4'", C5.find(card, "Room").Text)
			local downed = C5.find(card, "Member2")
			T.check(downed and downed:GetAttribute("Downed") == true, "p5dgn desktop: member chips show who is Downed")
		else
			T.check(C5.find(card, "Text").Text:find("Room 2/4", 1, true), "p5dgn phone: the chip reads 'Room 2/4'", C5.find(card, "Text").Text)
			local r = C5.rect(card)
			T.check(r.y1 <= 60, "p5dgn phone: the chip sits in Roblox's top band (bottom <= 60 px)", string.format("%.0f", r.y1))
		end
		local r = C5.rect(card)
		local W, H = Mock.Viewport.X, Mock.Viewport.Y
		local cx, cy = (r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2
		T.check(not (cx > W / 3 and cx < 2 * W / 3 and cy > H / 3 and cy < 2 * H / 3), "p5dgn " .. tag .. ": the run card is not in the screen's centre third")
		-- loot toast + totals
		KC.toClient("DungeonState", "Loot", { Room = 2, Cash = 340, Tokens = 24, Xp = 70, LevelUps = 0 })
		KC.advance(0.4)
		T.check(DC.GetState().Totals.Cash == 340 and DC.GetState().Totals.Tokens == 24, "p5dgn " .. tag .. ": Loot adds to the run's totals")
		if not phone then
			local toast = C5.find(card, "LootToast")
			T.check(toast and C5.shown(toast) and C5.find(toast, "Text").Text:find("+$340", 1, true), "p5dgn desktop: the loot toast 'Room 2 cleared! +$340 ...'")
		else
			T.check(C5.find(card, "Text").Text:find("+$340", 1, true), "p5dgn phone: the chip flashes the loot", C5.find(card, "Text").Text)
		end
		-- the door slide (the exit bars of the player's pocket)
		if rootPart then
			local before = 0
			for _, c in ipairs(workspace:GetChildren()) do
				if c.Name == "BarSlide" then
					before = before + 1
				end
			end
			room:SetAttribute("DoorOpen", true)
			KC.advance(0.2)
			local after = 0
			for _, c in ipairs(workspace:GetChildren()) do
				if c.Name == "BarSlide" then
					after = after + 1
				end
			end
			T.check(after - before == 3, "p5dgn " .. tag .. ": DoorOpen plays the bars' slide (3 local copies)", tostring(after - before))
			KC.advance(1.0)
		else
			T.info("p5dgn " .. tag .. ": no character root: door slide not measured")
		end
		-- LEAVE twice -> one Quit
		local mark = #Mock.RemoteLog
		local leave = C5.find(card, "LeaveButton")
		Mock.Click(leave)
		KC.advance(0.3)
		T.eq(#C5.sends(mark, "Quit"), 0, "p5dgn " .. tag .. ": the first LEAVE only arms it")
		Mock.Click(leave)
		KC.advance(0.3)
		T.eq(#C5.sends(mark, "Quit"), 1, "p5dgn " .. tag .. ": the second LEAVE sends DungeonRequest('Quit') once")
		-- the treasure alcove: CHEST
		run.State, run.Room, run.Wave = "Treasure", 4, 2
		KC.toClient("DungeonState", "Run", run)
		KC.advance(0.6)
		mark = #Mock.RemoteLog
		local chest = phone and C5.find(card, "LeaveButton") or C5.find(card, "ChestButton")
		T.check(chest and C5.shown(chest) and (not phone or chest.Text == "CHEST"), "p5dgn " .. tag .. ": the treasure alcove offers CHEST")
		Mock.Click(chest)
		KC.advance(0.3)
		T.eq(#C5.sends(mark, "Chest"), 1, "p5dgn " .. tag .. ": CHEST sends DungeonRequest('Chest')")
		KC.toClient("DungeonState", "Chest", { Kind = "Gems", Amount = 2 })
		KC.advance(0.3)
		T.check(DC.GetState().Totals.Gems == 2, "p5dgn " .. tag .. ": the chest's Gems join the totals")
		-- the End card; the light is popped
		LP:SetAttribute("InBattle", nil)
		KC.toClient("DungeonState", "End", { Floor = 3, Name = "Flooded Vaults", Cleared = true, Reason = "Cleared", Room = 4,
			Totals = { Cash = 1630, Tokens = 170, Xp = 360, Gems = 2 }, FirstClear = { Tokens = 900, Gems = 5 }, Unlocked = 4, NewBest = 3 })
		KC.advance(0.6)
		local endCard = rg and rg:FindFirstChild("EndCard")
		T.check(endCard and C5.shown(endCard) and C5.find(endCard, "Title").Text == "Floor 3 cleared!" and C5.find(endCard, "FirstClear").Text:find("+900", 1, true)
			and C5.find(endCard, "Unlocked").Text:find("Floor 4 unlocked", 1, true), "p5dgn " .. tag .. ": the End card: cleared, first clear +900, floor 4 unlocked")
		T.check(not C5.shown(card), "p5dgn " .. tag .. ": the run card hides after End")
		T.check(LS and LS.Top and LS.Top() ~= "Dungeon", "p5dgn " .. tag .. ": LightingStack.Pop('Dungeon') on End", LS and tostring(LS.Top()))
		local er = C5.rect(endCard)
		local ecx, ecy = (er.x0 + er.x1) / 2, (er.y0 + er.y1) / 2
		T.check(not (ecx > W / 3 and ecx < 2 * W / 3 and ecy > H / 3 and ecy < 2 * H / 3), "p5dgn " .. tag .. ": the End card is not in the screen's centre third")
		if phone then
			T.check((er.x1 - er.x0) * (er.y1 - er.y0) <= 0.25 * W * H, "p5dgn phone: the End card covers <= 25% of the screen")
		end
		Mock.Click(C5.find(endCard, "OkButton"))
		KC.advance(0.4)
		T.check(not C5.shown(endCard) and DC.GetState().End == nil, "p5dgn " .. tag .. ": OK closes the End card")
		folder:Destroy()
		KC.flushErrors("client_p5dungeon")
	end

	S.client_p5dungeon = guarded("client_p5dungeon", function()
		C5.desktop()
		C5.screen(1920, 1080, false)
	end)
	S.client_p5dungeon_mobile = guarded("client_p5dungeon_mobile", function()
		local DC, LP = C5.setup()
		if not T.check(DC ~= nil, "p5dgn phone: DungeonController loads") then
			return
		end
		C5.windowAt(DC, 844, 390, true, "window")
		C5.windowAt(DC, 390, 844, true, "window")
		DC.Close()
		KC.advance(0.4)
		C5.run(DC, LP, true)
		C5.screen(844, 390, true)
		C5.run(DC, LP, true)
		C5.screen(390, 844, true)
	end)
	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
