-- smoke_p3_fixcheck.lua: the skeptic's re-checks of the Phase 3 review fixes (fixcheck). Both worlds (ARGS.context
-- picks the half); the server scenarios run booted, before the care block (they advance the clock by minutes).
--   p3fixchk_practice  a practice duel (#0: a huge power gap) counts for nothing either way: the weak player who
--                      forfeits it (or leaves) loses no trophies and gets no PvP loss; the strong one is not paid
--   p3fixchk_wire      the delta snapshot protocol (#4) against the sim's own picture: a raid with fighters, a
--                      spectator who walks in late, a raider who joins late (after spectating) and one who leaves;
--                      every receiver's decoded stream (BattleSim.DecodeSnapshot, the client's way: the picture is
--                      kept across a second "Start" of the same battle) equals BattleSim:Snapshot() at the same T for
--                      every unit still in the battle, minion waves included; spectators ~5 Hz, fighters ~10 Hz, and
--                      a fighter stays under 20 KB/s through the waves of a 16-raider raid
--   client_p3fixchk_join (client world) BattleController as a raid spectator who then joins (a second "Start" for the
--                      same battle, a full snapshot, then deltas), a team leaving (Leave event) and a minion wave: the
--                      drawn units follow the sim (position, HP, state); the leavers' units are gone
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, max, min = math.abs, math.floor, math.max, math.min
local fmt = string.format

local function pet(key, level, tier)
	return { Key = key, Level = level or 1, Tier = tier }
end

local function team(owner, side, pets, flags)
	local list = {}
	for i, p in ipairs(pets) do
		list[i] = { Key = p.Key, Level = p.Level, Tier = p.Tier, Slot = i }
	end
	local spec = { Owner = owner, Side = side, Pets = list }
	for k, v in pairs(flags or {}) do
		spec[k] = v
	end
	return spec
end

-- the decoded record matches the sim's Snapshot() entry
local function sameUnit(d, s)
	return d ~= nil and abs(d.x - s.x) < 0.051 and abs(d.z - s.z) < 0.051 and d.hp == s.hp and d.state == s.state and d.meter == s.meter
		and (d.shield or 0) == (s.shield or 0) and d.target == s.target
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	S.client_p3fixchk_join = guarded("client_p3fixchk_join", function()
		local BC = moduleAt("client", "Controllers/BattleController")
		local Sim = moduleAt("shared", "BattleSim")
		if not T.check(BC ~= nil and Sim ~= nil and type(Sim.DecodeSnapshot) == "function", "join: BattleController and BattleSim load") then
			return
		end
		local me = LocalPlayer.UserId
		local id = "smoke_join_" .. tostring(math.random(100000, 999999))
		local strong = { pet("aurora_fox", 14), pet("storm_tabby", 14), pet("bamboo_panda", 14) }
		local sim = Sim.new({ Mode = "Raid", Boss = "storm_titan", Seed = 7, Id = id, Teams = { team(501, 1, strong), team(502, 1, strong) } })
		if not T.check(sim ~= nil, "join: a BattleSim raid") then
			return
		end
		local function startPayload(side)
			local d = sim:Describe()
			d.BattleId = id
			d.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(d.Zone.X, 30, d.Zone.Z), X = d.Zone.X, Z = d.Zone.Z }
			d.Names = { [tostring(me)] = LocalPlayer.Name }
			d.Side, d.Spectator, d.T = side, side == 0, sim:Time()
			return d
		end
		local errs0 = #Mock.Errors
		-- the stream one receiver gets: a baseline of its own, every `every` steps
		local last = {}
		local steps = 0
		local function run(seconds, every)
			for _ = 1, floor(seconds * 10 + 0.5) do
				local evs = sim:Step(0.1)
				steps = steps + 1
				if #evs > 0 then
					BC.HandleState("Events", evs, id)
				end
				if steps % every == 0 then
					local snap = sim:SnapshotDelta(last)
					snap.BattleId = id
					BC.HandleState("Snapshot", snap, id)
				end
				KC.advance(0.1)
			end
		end
		local function full()
			last = {}
			local snap = sim:SnapshotDelta(last)
			snap.BattleId = id
			BC.HandleState("Snapshot", snap, id)
		end
		local function compare(label)
			KC.advance(0.4) -- the render clock catches up with the last snapshot
			local picture = sim:Snapshot().Units
			local tally = T.tally(label)
			local n = 0
			for uid, s in pairs(picture) do
				local u = BC.GetUnit(uid)
				n = n + 1
				local ok = u ~= nil and abs(u.X - s.x) <= 0.3 and abs(u.Z - s.z) <= 0.3 and u.Hp == s.hp and u.State == s.state
				tally:case(ok, uid .. ": " .. (u and fmt("x %.1f/%.1f z %.1f/%.1f hp %s/%s st %s/%s", u.X, s.x, u.Z, s.z, tostring(u.Hp), tostring(s.hp), tostring(u.State), tostring(s.state)) or "no unit"))
			end
			tally:report(n .. " units")
		end
		-- a spectator first (5 Hz), the raid already 20 s in
		for _ = 1, 200 do
			sim:Step(0.1)
		end
		BC.HandleState("Start", startPayload(0), id)
		full()
		KC.advance(0.1)
		run(4, 2)
		compare("join: as a spectator who arrived 20 s in (5 Hz deltas) every unit follows the sim")
		local g = BC.GetBattle()
		T.check(g and g.InterpDelay and g.InterpDelay > 0.2, "join: a spectator draws further behind (5 Hz)", g and tostring(g.InterpDelay))
		-- joins: the server adds the team, sends a second "Start" for the same battle and a full snapshot
		LocalPlayer:SetAttribute("InBattle", id)
		local infos = sim:AddTeam(team(me, 1, strong))
		T.check(type(infos) == "table" and #infos == 3, "join: (setup) the team joins the running raid")
		BC.HandleState("Start", startPayload(1), id)
		full()
		KC.advance(0.1)
		run(4, 1)
		compare("join: after joining (second Start, full snapshot, 10 Hz deltas) every unit follows the sim")
		g = BC.GetBattle()
		local mineDrawn = 0
		for _, info in ipairs(infos) do
			local u = BC.GetUnit(info.id)
			if u and u.Mine then
				mineDrawn = mineDrawn + 1
			end
		end
		T.check(mineDrawn == 3 and g and g.InterpDelay < 0.2, "join: my three pets are drawn as mine and the fighter's delay is back to 10 Hz", tostring(mineDrawn))
		-- a team leaves (its units are no longer in the snapshots: the Leave event removes them)
		local gone = {}
		for _, u in ipairs(sim:StaticUnits()) do
			if u.owner == 502 then
				gone[#gone + 1] = u.id
			end
		end
		sim:RemoveTeam(502)
		run(3, 1)
		local stillDrawn = 0
		for _, uid in ipairs(gone) do
			if BC.GetUnit(uid) then
				stillDrawn = stillDrawn + 1
			end
		end
		T.check(#gone == 3 and stillDrawn == 0, "join: the units of a team that left are removed (they are no longer sent)", stillDrawn .. " of " .. #gone .. " still drawn")
		-- a minion wave: hurry the boss down to the first wave and let it spawn
		if sim.boss then
			sim.boss.hp = sim.boss.maxHp * 0.6
		end
		run(3, 1)
		local minions = 0
		for uid in pairs(sim:Snapshot().Units) do
			local u = BC.GetUnit(uid)
			if u and u.Kind == "Minion" then
				minions = minions + 1
			end
		end
		T.check(minions > 0, "join: (setup) a minion wave spawned and is drawn", tostring(minions))
		compare("join: with a minion wave on the floor every unit still follows the sim")
		T.eq(#Mock.Errors, errs0, "join: no script errors")
		LocalPlayer:SetAttribute("InBattle", nil)
		BC.HandleState("End", { BattleId = id, Mode = "Raid", Spectator = true, Reason = "OutOfRange" }, id)
		KC.advance(1)
		T.check(BC.GetBattle() == nil, "join: the battle is cleaned up afterwards")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local advance = K.advance

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
	local function BS()
		return req("server/Services/BattleService")
	end
	local function DS()
		return req("server/Services/DataService")
	end
	local function arenaInfo()
		local ab = req("server/Services/ArenaBuilder")
		return ab and ab.GetInfo and ab.GetInfo() or nil
	end

	local STRONG = { "cloudy_dragon", "ember_phoenix", "aurora_fox" }
	local MID = { "twilight_dragon", "moonlit_owl", "candy_unicorn" }
	local ALT = { "starlight_unicorn", "sunbeam_bear", "nebula_axolotl" }
	local WEAK = { "pebble_pup", "honey_bunny", "puddle_frog" }

	local seq = 0
	local function newPlayer(prefix, pets, level)
		seq = seq + 1
		local p = Mock.AddPlayer(prefix .. seq, 964000 + seq)
		advance(1.0)
		local data = DS()
		local prof = data.GetProfile(p)
		if prof and pets then
			for _, petId in ipairs(pets) do
				prof.Pets[petId] = (prof.Pets[petId] or 0) + 1
				if level then
					prof.PetLevels[petId] = { Level = level, Xp = 0 }
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
	local function toArena(p, dx, dz)
		local info = arenaInfo()
		Mock.Teleport(p, info.Spawn * CFrame.new(dx or 0, 0, dz or 0))
		advance(0.05)
	end
	local function battleMsgs(p, fromIndex)
		local out = {}
		local log = Mock.RemoteLog
		for i = (fromIndex or 0) + 1, #log do
			local e = log[i]
			if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId then
				out[#out + 1] = e
			end
		end
		return out
	end
	local function contains(list, value)
		for _, v in ipairs(type(list) == "table" and list or {}) do
			if v == value then
				return true
			end
		end
		return false
	end
	local function record(p)
		return DS().GetBattle(p) or {}
	end
	local function tokens(p)
		return DS().GetTokens(p)
	end
	local function watchEnded()
		local list = {}
		local conn = BS().BattleEnded:Connect(function(id, result)
			list[#list + 1] = { id = id, result = result }
		end)
		return {
			find = function(id)
				for _, e in ipairs(list) do
					if e.id == id then
						return e.result
					end
				end
				return nil
			end,
			stop = function()
				conn:Disconnect()
			end,
		}
	end
	local realStartRaid = nil
	local function holdRaidSchedule(bs)
		if realStartRaid == nil then
			realStartRaid = bs.StartRaid
			bs.StartRaid = function()
				return false, "A raid is already running"
			end
		end
		return realStartRaid
	end
	local function releaseRaidSchedule(bs)
		if realStartRaid then
			bs.StartRaid = realStartRaid
			realStartRaid = nil
		end
	end
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
	local function cleanup(list)
		local bs = BS()
		for _, p in ipairs(list) do
			if p.Parent and bs and bs.IsInBattle(p) then
				bs.Forfeit(p)
			end
		end
		advance(0.3)
		K.removePlayers(list)
		advance(5)
	end
	local function ready(label)
		if not K.needBoot() then
			return false
		end
		if not BS() or not arenaInfo() then
			T.fail(label .. ": skipped, BattleService or the arena is missing")
			return false
		end
		return true
	end
	local function scenario(name, fn)
		local run = guarded(name, fn)
		return function(...)
			local ok = run(...)
			local bs = BS()
			if bs then
				releaseRaidSchedule(bs)
				if bs.SetClosing then
					bs.SetClosing(false)
				end
			end
			loudReplication()
			return ok
		end
	end

	------------------------------------------------------------------------------------------------
	-- p3fixchk_practice
	------------------------------------------------------------------------------------------------
	S.p3fixchk_practice = scenario("p3fixchk_practice", function()
		if not ready("p3fixchk_practice") then
			return
		end
		quietReplication()
		local bs, data = BS(), DS()
		local w = watchEnded()
		local strong = newPlayer("PracStrong", STRONG, 20)
		local weak = newPlayer("PracWeak", { "pebble_pup" }, 1)
		data.AddTrophies(strong, 60)
		data.AddTrophies(weak, 60)
		toArena(strong, 3, 0)
		toArena(weak, -3, 0)
		local recS0, recW0 = record(strong), record(weak)
		local tS0 = tokens(strong)
		local ok, id = bs.StartDuel(strong, weak)
		T.check(ok == true, "practice forfeit: (setup) a practice duel starts", tostring(id))
		advance(0.2)
		bs.Forfeit(weak) -- "they are far stronger": the weak player walks away at once
		K.waitFor(function()
			return w.find(id) ~= nil
		end, 10)
		local r = w.find(id)
		local recW, recS = record(weak), record(strong)
		local rwW = r and r.Rewards and r.Rewards[weak.UserId]
		T.check(r ~= nil and r.Forfeit == true and contains(r.Losers, weak.UserId), "practice forfeit: (setup) the duel ended by the weak player's forfeit", r and tostring(r.Reason) or "no end")
		T.check(r ~= nil and recW.Trophies == recW0.Trophies and (recW.PvPLosses or 0) == (recW0.PvPLosses or 0),
			"practice forfeit: leaving a practice duel costs no trophies and no PvP loss (#0: practice counts for nothing)",
			fmt("trophies %s -> %s, losses %s -> %s", tostring(recW0.Trophies), tostring(recW.Trophies), tostring(recW0.PvPLosses or 0), tostring(recW.PvPLosses or 0)))
		T.check(rwW and rwW.Practice == true and (rwW.Trophies or 0) == 0, "practice forfeit: the leaver's rewards record says Practice, 0 trophies", rwW and tostring(rwW.Trophies) or "none")
		T.check(recS.Trophies == recS0.Trophies and tokens(strong) == tS0 and (recS.PvPWins or 0) == (recS0.PvPWins or 0), "practice forfeit: ...and the strong player is not paid either")
		-- both leave a practice duel in one frame: still nothing for anyone (the refund does not take a loss away)
		advance(5)
		ok, id = bs.StartDuel(strong, weak)
		T.check(ok == true, "practice double leave: (setup) a second practice duel starts", tostring(id))
		advance(0.2)
		local recW1 = record(weak)
		bs.Forfeit(weak)
		bs.Forfeit(strong)
		K.waitFor(function()
			return w.find(id) ~= nil
		end, 10)
		local recW2 = record(weak)
		local r2 = w.find(id)
		T.check(r2 ~= nil and #r2.Winners == 0, "practice double leave: (setup) both left before the end: void", r2 and tostring(r2.Reason) or "no end")
		T.check(w.find(id) ~= nil and recW2.Trophies == recW1.Trophies and (recW2.PvPLosses or 0) == (recW1.PvPLosses or 0),
			"practice double leave: no trophies moved and the PvP losses stay as they were (no refund below the real count)",
			fmt("losses %s -> %s", tostring(recW1.PvPLosses or 0), tostring(recW2.PvPLosses or 0)))
		K.flushErrors("p3fixchk_practice")
		w.stop()
		cleanup({ strong, weak })
	end)

	------------------------------------------------------------------------------------------------
	-- p3fixchk_wire
	------------------------------------------------------------------------------------------------
	S.p3fixchk_wire = scenario("p3fixchk_wire", function()
		if not ready("p3fixchk_wire") then
			return
		end
		quietReplication()
		local bs = BS()
		local Sm = req("shared/BattleSim")
		local info = arenaInfo()
		if bs.GetRaidStatus() ~= nil then
			bs.EndRaid()
			advance(0.2)
		end
		-- the sim's own picture at every T a snapshot was built (ground truth), recorded beside the wire form
		local truth = {}
		local raidSim = nil
		local realDelta = Sm.SnapshotDelta
		Sm.SnapshotDelta = function(self, last)
			local snap = realDelta(self, last)
			if self.mode == "Raid" then
				raidSim = self
				truth[snap.T] = self:Snapshot().Units
			end
			return snap
		end
		local okSetup, err = pcall(function()
			local mark0 = K.logSize()
			local okR, raidId = holdRaidSchedule(bs)("frost_wyrm")
			local rosters = { STRONG, MID, ALT, WEAK }
			local raiders = {}
			for i = 1, 15 do
				raiders[i] = newPlayer("Wire", rosters[(i - 1) % 4 + 1], 12)
				toArena(raiders[i], (i - 8) * 2, 8)
				bs.JoinRaid(raiders[i])
			end
			local late = newPlayer("WireLate", MID, 12) -- watches from the stands first, joins later
			Mock.Teleport(late, info.Floor.CFrame * CFrame.new(-6, 3, 62))
			local watcher = newPlayer("WireWatch", WEAK) -- walks into the stands later
			local mark = K.logSize()
			advance(2)
			T.check(okR and bs.GetRaidStatus() and bs.GetRaidStatus().Players == 15, "wire: (setup) a 15-raider Frost Wyrm raid runs", tostring(raidId))
			local function fight(seconds)
				for _ = 1, floor(seconds * 2 + 0.5) do
					for i, p in ipairs(raiders) do
						if p.Parent then
							bs.Command(p, "Attack")
							bs.Command(p, "Special", (i % 3) + 1)
						end
					end
					advance(0.5)
				end
			end
			fight(3)
			Mock.Teleport(watcher, info.Floor.CFrame * CFrame.new(6, 3, 62))
			fight(3)
			local okJ = bs.JoinRaid(late) -- the 16th raider, after spectating
			raiders[#raiders + 1] = late
			fight(2)
			bs.LeaveRaid(raiders[2]) -- one leaves (its units stop being sent)
			fight(2)
			-- the boss down to its first minion wave (frost_wyrm: 70%), then fight through the wave
			if raidSim and raidSim.boss then
				raidSim.boss.hp = raidSim.boss.maxHp * 0.66
			end
			local waveMark = K.logSize()
			fight(8)
			if raidSim and raidSim.boss then
				raidSim.boss.hp = min(raidSim.boss.hp, raidSim.boss.maxHp * 0.33)
			end
			fight(8)
			T.check(okJ == true, "wire: (setup) the spectator joins as the 16th raider", tostring(okJ))
			local units = 0
			for _ in pairs(raidSim and raidSim:Snapshot().Units or {}) do
				units = units + 1
			end
			T.check(units >= 50, "wire: (setup) the waves are on the floor", units .. " units")
			-- every receiver decodes its own stream like BattleController (one picture per battle, kept across a
			-- second "Start" of the same battle) and must equal the sim's picture at the same T
			local function check(p, label)
				local picture, battle = nil, nil
				local compared, bad, firstBad = 0, 0, nil
				local snaps, firstT, lastT = 0, nil, nil
				for _, e in ipairs(battleMsgs(p, mark0)) do
					local kind, payload = e.args[1], e.args[2]
					local bid = type(payload) == "table" and payload.BattleId or e.args[3]
					if kind == "Start" then
						if bid ~= battle then
							picture, battle = nil, bid
						end
					elseif kind == "Snapshot" and bid == battle and bid == raidId then
						picture = Sm.DecodeSnapshot(payload, picture)
						snaps = snaps + 1
						firstT = firstT or e.time
						lastT = e.time
						local want = truth[payload.T]
						if want then
							for uid, s in pairs(want) do
								compared = compared + 1
								if not sameUnit(picture[uid], s) then
									bad = bad + 1
									if not firstBad then
										local d = picture[uid]
										firstBad = fmt("T %s unit %d: %s vs %s", tostring(payload.T), uid,
											d and fmt("%.1f,%.1f hp %s st %s m %s t %s", d.x, d.z, tostring(d.hp), tostring(d.state), tostring(d.meter), tostring(d.target)) or "missing",
											fmt("%.1f,%.1f hp %s st %s m %s t %s", s.x, s.z, tostring(s.hp), tostring(s.state), tostring(s.meter), tostring(s.target)))
									end
								end
							end
						end
					end
				end
				T.check(compared > 0 and bad == 0, "wire: " .. label .. ": the decoded stream equals the sim's picture at every snapshot (" .. compared .. " unit checks)", firstBad or "")
				return snaps, firstT, lastT
			end
			check(raiders[1], "a raider from the start")
			check(late, "a late joiner who spectated first")
			local ws, wf, wl = check(watcher, "a spectator who walked in late")
			local hz = (ws > 1 and wl > wf) and (ws - 1) / (wl - wf) or 0
			T.check(hz >= 4 and hz <= 6, "wire: the late spectator gets ~5 snapshots per second", fmt("%.1f", hz))
			-- bandwidth through the waves (16 raiders, 50+ units): a fighter stays under 20 KB/s
			local bytes, t0, t1 = 0, nil, nil
			for _, e in ipairs(battleMsgs(raiders[1], waveMark)) do
				bytes = bytes + bs.EstimateBytes(e.args[2]) + 4 + #tostring(e.args[1]) + #tostring(e.args[3] or "")
				t0 = t0 or e.time
				t1 = e.time
			end
			local rate = (t0 and t1 and t1 > t0) and bytes / (t1 - t0) or 0
			T.info(fmt("*wire: fighter during the minion waves of a 16-raider raid: %.1f KB/s", rate / 1000))
			T.check(rate > 0 and rate < 20000, "wire: a fighter stays under 20 KB/s through the minion waves of a 16-raider raid (#4)", fmt("%.0f B/s", rate))
			bs.EndRaid()
			advance(0.5)
			local all = { watcher }
			for _, p in ipairs(raiders) do
				all[#all + 1] = p
			end
			cleanup(all)
		end)
		Sm.SnapshotDelta = realDelta
		if not okSetup then
			T.fail("wire: the scenario failed", tostring(err))
		end
		K.flushErrors("p3fixchk_wire")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
