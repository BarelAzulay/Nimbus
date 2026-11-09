-- smoke_p3_battleservice.lua: Phase 3 "BattleService" (ARCHITECTURE_V3.md "Phase 3 build contract": BattleService +
-- "Interfaces between the Phase 3 modules") on the booted server with 2-8 simulated players. Server world only (listed
-- in server_files of tools/smoke.py); the scenarios run before the Phase 2 care block (they advance the clock by several
-- minutes):
--   p3bs_contract  the module, its API (Phase 5: the encounter API, no StartTrial), BattleEnded / BattleStarted created at
--                  module load, Init wired by Main (the BattleRequest remote answers), safe answers for nil players and
--                  without a raid; the mode names Duel / Raid / Ring / Dungeon
--   p3bs_duel      challenge -> "Lobby" (Invites / Sent shapes) -> decline, expiry, accept (a challenge back is a yes);
--                  both duellists on the ring's pads, Start to both, a spectator in range gets the battle and the far
--                  player nothing; both PLAY (the character walks in, ATTACK): the end pays trophies / tokens / XP / PvP
--                  counters once; a forfeit after 15 s (full win), an early forfeit (the winner gets no rewards), the pair
--                  limit (no trophies), a disconnect (the leaver's penalty is in the saved profile, the opponent wins)
--   p3bs_queue     the quick queue: Queue / Unqueue, "Lobby" Queued / Waiting, similar trophies pair at once, far apart
--                  only after the allowance grew, leaving the arena cancels
--   p3bs_raid      SetRaidBoss / GetRaidStatus / EnterRaid (inside the arena, a late joiner) / LeaveRaid, the boss HP grows
--                  and shrinks per participant, a spectator becoming a fighter, a joiner who leaves the arena is
--                  removed, EndRaids (a timeout loss, rewards once, Double Rewards pushed), the boss waiting with nobody
--                  in, and a full raid fought by three active fighters (medals by damage share)
--   p3bs_exploits  junk remote arguments, commands for other units / bad slots / from spectators / from outside the zone,
--                  spam (token buckets, cooldowns), starting two battles, a duel player teleported out of the arena,
--                  an obby match during a battle, the portal lock, rewards once after the end
--   p3bs_net       bytes per second per client for a duel and an 8-player raid (BattleService.EstimateBytes of
--                  every BattleState payload), ~10 Hz snapshots, players far away get nothing, payload hygiene (no
--                  functions, NaN, sparse arrays or mixed tables), GetNetStats
--   (p3bs_trial was deleted with the Trials: Phase 5 contract 10.5)
-- Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance = K.advance

local S = {}

local seq = 0
local STRONG = { "cloudy_dragon", "ember_phoenix", "aurora_fox" }
local MID = { "twilight_dragon", "moonlit_owl", "candy_unicorn" }
local WEAK = { "pebble_pup", "honey_bunny", "puddle_frog" }
local ALT = { "starlight_unicorn", "sunbeam_bear", "nebula_axolotl" }

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
local function AB()
	return req("server/Services/ArenaBuilder")
end
local function BC()
	return req("shared/BattleCatalog")
end

local function arenaInfo()
	local ab = AB()
	return ab and ab.GetInfo and ab.GetInfo() or nil
end

-- everything a battle scenario needs; one clear failure instead of a cascade
local function ready(label)
	if not K.needBoot() then
		return false
	end
	if not BS() then
		T.fail(label .. ": skipped, server/Services/BattleService did not load")
		return false
	end
	if not arenaInfo() then
		T.fail(label .. ": skipped, ArenaBuilder.GetInfo() returned nothing (no arena in this build)")
		return false
	end
	return true
end

-- a player with a battle team (pets owned, team preset 1); `level` sets every pet's level
local function newPlayer(prefix, pets, level)
	seq = seq + 1
	local p = Mock.AddPlayer(prefix .. seq, 961000 + seq)
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

local function toArena(p, dx, dz)
	local info = arenaInfo()
	Mock.Teleport(p, info.Spawn * CFrame.new(dx or 0, 0, dz or 0))
	advance(0.05)
end

local function toLobby(p)
	Mock.Teleport(p, CFrame.new(K.config().Lobby.Origin + Vector3.new(10, 4, 10)))
	advance(0.05)
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

local function lastMsg(p, kind, fromIndex)
	local list = battleMsgs(p, fromIndex, kind)
	local e = list[#list]
	return e and e.args[2] or nil, e
end

local function toasts(p, fromIndex)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, fromIndex or 0)) do
		out[#out + 1] = tostring(e.args[1])
	end
	return out
end

local function toasted(p, pattern, fromIndex)
	for _, text in ipairs(toasts(p, fromIndex)) do
		if text:find(pattern) then
			return true
		end
	end
	return false
end

-- toasted with a plain (non-pattern) search: texts that hold "+" or "."
local function toastedPlain(p, text, fromIndex)
	for _, shown in ipairs(toasts(p, fromIndex)) do
		if shown:find(text, 1, true) then
			return true
		end
	end
	return false
end

local function watchEnded()
	local list = {}
	local conn = BS().BattleEnded:Connect(function(id, result)
		list[#list + 1] = { id = id, result = result }
	end)
	return {
		list = list,
		find = function(id)
			for _, e in ipairs(list) do
				if e.id == id then
					return e.result
				end
			end
			return nil
		end,
		count = function(id)
			local n = 0
			for _, e in ipairs(list) do
				if e.id == id then
					n = n + 1
				end
			end
			return n
		end,
		stop = function()
			conn:Disconnect()
		end,
	}
end

local function waitEnded(w, id, seconds)
	return K.waitFor(function()
		return w.find(id) ~= nil
	end, seconds or 130)
end

-- the token factor a reward was paid with (Double Rewards may run during the test: EventService's hour)
local function doubled(rw)
	if type(rw) == "table" and rw.Double == true then
		local events = BC() and BC().Events
		return (events and tonumber(events.DoubleRewardsMultiplier)) or 2
	end
	return 1
end

local function contains(list, value)
	for _, v in ipairs(type(list) == "table" and list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

local function tokens(p)
	return DS().GetTokens(p)
end

local function record(p)
	return DS().GetBattle(p) or {}
end

-- paths of functions, NaN / inf, sparse arrays and mixed tables inside a remote payload
local function badTables(value, path, out, depth)
	out = out or {}
	depth = depth or 0
	local kind = typeof(value)
	if kind == "function" or kind == "thread" then
		out[#out + 1] = path .. " (" .. kind .. ")"
		return out
	end
	if type(value) == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			out[#out + 1] = path .. " (nan / inf)"
		end
		return out
	end
	if type(value) ~= "table" or depth > 14 then
		return out
	end
	local numeric, other, top = 0, 0, 0
	for k in pairs(value) do
		if type(k) == "number" then
			numeric = numeric + 1
			if k > top then
				top = k
			end
		else
			other = other + 1
		end
	end
	if numeric > 0 and (other > 0 or top ~= numeric) then
		out[#out + 1] = path .. " (sparse or mixed)"
	end
	for k, v in pairs(value) do
		badTables(v, path .. "." .. tostring(k), out, depth + 1)
	end
	return out
end

-- BattleState traffic of the heavy scenarios stays out of the client replay log (thousands of snapshots); the short
-- first trial stays in it so the client replays a real battle
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
	advance(5) -- trial pockets / rings come free
end

local function distanceToZone(p, zoneCF)
	local root = K.root(p)
	if not root then
		return math.huge
	end
	return (root.Position - zoneCF.Position).Magnitude
end

-- the sim of a running battle (white-box: St is an upvalue of IsInBattle, as in smoke_raid_service.lua)
local function simOf(id)
	local f = BS().IsInBattle
	for i = 1, 80 do
		local name, v = debug.getupvalue(f, i)
		if not name then
			break
		end
		if name == "St" and type(v) == "table" and type(v.battles) == "table" then
			return v.battles[id] and v.battles[id].Sim or nil
		end
	end
	return nil
end

local function endAnyRaid(bs)
	if bs.EndRaids("Ended") > 0 then
		advance(0.2)
	end
end

local function eventsOf(p, fromIndex, evType)
	local out = {}
	for _, e in ipairs(battleMsgs(p, fromIndex, "Events")) do
		for _, ev in ipairs(e.args[2]) do
			if evType == nil or ev.type == evType then
				out[#out + 1] = ev
			end
		end
	end
	return out
end

local function planarTo(p, cf)
	local pos = K.root(p).Position
	return math.sqrt((pos.X - cf.Position.X) ^ 2 + (pos.Z - cf.Position.Z) ^ 2)
end

----------------------------------------------------------------------------------------------------
-- [Phase 5 driver] the client-side picture of a battle (BattleSim.DecodeSnapshot of the player's own messages) and a
-- fighter that walks its CHARACTER toward the nearest enemy at the legal run speed and presses ATTACK (B1: the
-- character is the fighter's body; a passive player deals no damage any more)
----------------------------------------------------------------------------------------------------
local DRV_DOWN, DRV_BENCHED = 5, 3

local function drvTracker(p, mark)
	return { p = p, cursor = mark or K.logSize(), static = {}, units = {}, ends = {}, ticks = 0, zone = nil, side = nil, fighter = nil, id = nil, start = nil, speed = nil }
end

local function drvPump(tr)
	local Sm = req("shared/BattleSim")
	local log = Mock.RemoteLog
	local uid = tr.p.UserId
	for i = tr.cursor + 1, #log do
		local e = log[i]
		if e.remote == "BattleState" and e.kind == "client" and e.userId == uid then
			local kind, payload = e.args[1], e.args[2]
			if kind == "Start" and type(payload) == "table" and payload.Spectator ~= true then
				tr.start, tr.id = payload, payload.BattleId
				tr.zone = payload.Zone and payload.Zone.CFrame
				tr.side = payload.Side
				tr.static, tr.units = {}, {}
				for _, u in ipairs(payload.Units or {}) do
					tr.static[u.id] = u
				end
				tr.fighter = payload.Team and payload.Team.Fighter
				tr.speed = payload.Team and payload.Team.Speed
			elseif kind == "Snapshot" and type(payload) == "table" and payload.BattleId == tr.id and Sm then
				tr.units = Sm.DecodeSnapshot(payload, tr.units)
			elseif kind == "Events" and type(payload) == "table" and e.args[3] == tr.id then
				for _, ev in ipairs(payload) do
					if (ev.type == "Spawn" or ev.type == "Wave") and type(ev.units) == "table" then
						for _, u in ipairs(ev.units) do
							tr.static[u.id] = u
						end
					elseif ev.type == "Swap" and ev.owner == uid then
						tr.fighter = ev["in"]
					elseif ev.type == "Speed" and ev.owner == uid then
						tr.speed = { Walk = ev.walk, Run = ev.run }
					elseif ev.type == "Telegraph" then
						tr.telegraphAt = Mock.Clock.now
					end
				end
			elseif kind == "End" and type(payload) == "table" and payload.Spectator ~= true and payload.BattleId == tr.id then
				tr.ends[#tr.ends + 1] = payload
			end
		end
	end
	tr.cursor = #log
end

local function drvMyPos(tr)
	local u = tr.fighter and tr.units[tr.fighter]
	if u then
		return u.x, u.z
	end
	return nil
end

local function drvNearest(tr)
	local fx, fz = drvMyPos(tr)
	if not fx then
		return nil
	end
	local best, bestD, bestS = nil, math.huge, nil
	for id, u in pairs(tr.units) do
		local s = tr.static[id]
		if s and s.side ~= tr.side and u.state ~= DRV_DOWN and u.state ~= DRV_BENCHED and (u.hp == nil or u.hp > 0) then
			local d = math.sqrt((u.x - fx) ^ 2 + (u.z - fz) ^ 2)
			if d < bestD then
				best, bestD, bestS = id, d, s
			end
		end
	end
	return best, bestD, bestS
end

-- one 0.1 s tick: walk toward the nearest enemy (stop inside the reach), press ATTACK every `every` ticks (3 = ~3/s),
-- Element + Special once per second when opts.kit
local function drvTick(tr, opts)
	opts = opts or {}
	local bs = BS()
	drvPump(tr)
	if not tr.id or not tr.p.Parent then
		return nil
	end
	local id, dist, s = drvNearest(tr)
	if not id then
		return nil
	end
	tr.ticks = tr.ticks + 1
	local run = (tr.speed and tr.speed.Run) or 16
	local mine = tr.static[tr.fighter] or {}
	local reach = (tonumber(mine.range) or 4.5) + (tonumber(s.radius) or 1) + 1
	local u = tr.units[id]
	local root = K.root(tr.p)
	if opts.move ~= false and root and tr.zone and dist > reach - 1 then
		local rel = tr.zone:PointToObjectSpace(root.Position)
		local dx, dz = u.x - rel.X, u.z - rel.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 0.01 then
			local travel = math.min(run * 0.1, d)
			Mock.Teleport(tr.p, CFrame.new(tr.zone:PointToWorldSpace(Vector3.new(rel.X + dx / d * travel, 3, rel.Z + dz / d * travel))))
		end
	end
	if opts.attack ~= false and tr.ticks % (opts.every or 3) == 0 then
		bs.Command(tr.p, "Attack", id)
	end
	if tr.telegraphAt and Mock.Clock.now - tr.telegraphAt < 0.25 and opts.dodge ~= false then
		bs.Command(tr.p, "Dash") -- a boss telegraph: the i-frames dodge it
	end
	if opts.kit ~= false and tr.ticks % 10 == 0 then
		bs.Command(tr.p, "Element")
		bs.Command(tr.p, "Special")
	end
	return id
end

-- plays every tracked fighter (a list of trackers) until `seconds` pass or stopFn(trs) is true; -> true when stopped early
local function drvPlay(trs, seconds, stopFn, opts)
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < seconds do
		advance(0.1)
		for _, tr in ipairs(trs) do
			drvTick(tr, opts)
		end
		if stopFn and stopFn(trs) then
			return true
		end
	end
	return false
end

-- every scenario of this file: guarded, then the shared test switches are always put back (also after an abort), so
-- the scenarios of other files never inherit them
local function scenario(name, fn)
	local run = guarded(name, fn)
	return function(...)
		local ok = run(...)
		local bs = BS()
		if bs then
			bs.Debug = nil
			if bs.SetDoubleRewards then
				bs.SetDoubleRewards(nil)
			end
		end
		loudReplication()
		return ok
	end
end

----------------------------------------------------------------------------------------------------
-- scenario: the module and its API
----------------------------------------------------------------------------------------------------
S.p3bs_contract = scenario("p3bs_contract", function()
	if not K.needBoot() then
		return
	end
	local bs = BS()
	if not T.check(bs ~= nil, "p3 bs: server/Services/BattleService loads") then
		return
	end
	local missing = {}
	for _, fn in ipairs({ "Init", "Challenge", "EnterRaid", "EndRaids", "SetRaidBoss", "RaidTierFor", "RaidRewardStatus", "GetBattle", "IsInBattle", "GetRaidStatus",
		"StartDuel", "ReplyChallenge", "Queue", "Unqueue", "LeaveRaid", "Command", "Forfeit", "SetDoubleRewards",
		"IsDoubleRewards", "GetNetStats", "EstimateBytes", "ListBattles", "StartRing", "KeysInBattle",
		"OpenEncounter", "SpawnWave", "FinishEncounter", "RemoveEncounterTeam", "EncounterStatus", "TeamSpec", "SetRunProvider" }) do
		if type(bs[fn]) ~= "function" then
			missing[#missing + 1] = fn
		end
	end
	T.check(#missing == 0, "p3 bs: the contract API (Challenge, EnterRaid / EndRaids, GetBattle, IsInBattle, GetRaidStatus, StartRing / KeysInBattle, the Phase 5 encounter API) and the extras exist", table.concat(missing, ", "))
	T.check(bs.StartRaid == nil and bs.EndRaid == nil and bs.JoinRaid == nil, "p3 bs: StartRaid / EndRaid / JoinRaid are gone (the boss is always there)")
	T.check(bs.StartTrial == nil, "p3 bs: StartTrial is gone (Phase 5 contract 10.5)")
	-- the mode names (Phase 5: Duel / Raid / Ring / Dungeon, no Trial) and the safe answers of the new API
	local sim = req("shared/BattleSim")
	local modes = sim and sim.Modes or {}
	local modeSet = {}
	for k, v in pairs(modes) do
		modeSet[type(k) == "string" and k or v] = true
	end
	T.check(not modeSet.Trial and modeSet.Duel and modeSet.Raid and modeSet.Ring and modeSet.Dungeon, "p3 bs: the mode names are Duel / Raid / Ring / Dungeon (BattleSim.Modes)")
	local keysNil = bs.KeysInBattle(nil)
	T.check(type(keysNil) == "table" and next(keysNil) == nil, "p3 bs: KeysInBattle(nil) is an empty set")
	local okRingNil, whyRingNil = bs.StartRing(nil, 1)
	T.check(okRingNil == false and type(whyRingNil) == "string", "p3 bs: StartRing(nil) refuses with a reason")
	local sig = bs.BattleEnded
	T.check(type(sig) == "table" and type(sig.Connect) == "function" and type(sig.Fire) == "function", "p3 bs: BattleEnded is a Util.Signal")
	local inst = K.moduleInstance("server/Services/BattleService")
	local source = inst and inst.Source or ""
	T.check(string.find("\n" .. source, "\nBattleService%.BattleEnded = Util%.Signal%(%)") ~= nil, "p3 bs: ...created at module load (other services connect before Init)")
	T.check(string.find(source, "[^%.%w_]wait%(") == nil and string.find(source, "[^%.%w_]spawn%(") == nil and string.find(source, "[^%.%w_]delay%(") == nil,
		"p3 bs: task.* only (no wait / spawn / delay globals)")
	if bs.EndRaids("test") > 0 then -- a fight of an earlier scenario may be live at this point of the full run
		advance(0.5)
	end
	local idle = bs.GetRaidStatus()
	T.check(bs.IsInBattle(nil) == false and bs.GetBattle(nil) == nil and idle ~= nil and idle.Active == false and next(idle.Fights) == nil and bs.EndRaids() == 0 and bs.EnterRaid(nil) == false,
		"p3 bs: nil players and 'no fight' answer safely (IsInBattle false, GetBattle nil, the boss waits with no fight, EndRaids 0, EnterRaid(nil) false)")
	-- Init ran through Main: the BattleRequest remote answers (a queue request away from the arena is refused with a toast)
	local p = newPlayer("BsApi", STRONG)
	toLobby(p)
	local mark = K.logSize()
	Mock.FromClient(K.remoteFolder():FindFirstChild("BattleRequest"), p, "Queue")
	advance(0.1)
	T.check(toasted(p, "Battle Arena", mark), "p3 bs: Main wired BattleRequest (a Queue request away from the arena gets a side toast)", table.concat(toasts(p, mark), " | "))
	T.check(p:GetAttribute("InBattle") == nil, "p3 bs: a player starts without the InBattle attribute")
	local okInit = pcall(bs.Init, {})
	T.check(okInit, "p3 bs: a second Init is harmless")
	K.removePlayers({ p })
end)

----------------------------------------------------------------------------------------------------
-- scenario: duels (invites, the ring, spectators, rewards, forfeits, the pair limit, a disconnect)
----------------------------------------------------------------------------------------------------
local function storedBattle(userId)
	local key = K.config().Tokens.DataStoreName .. "/u_" .. userId
	local rec = Mock.DataStore.Data[key]
	return type(rec) == "table" and rec.Battle or nil
end

S.p3bs_duel = scenario("p3bs_duel", function()
	if not ready("p3bs_duel") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	local info = arenaInfo()
	local TR = bc.Trophies
	local w = watchEnded()
	local a = newPlayer("DuelA", STRONG, 10)
	local b = newPlayer("DuelB", MID, 10)
	local c = newPlayer("DuelSpec", MID)
	local far = newPlayer("DuelFar", MID)
	toLobby(far)
	toLobby(a)
	local ok, why = bs.Challenge(a, b)
	T.check(ok == false and type(why) == "string" and why:find("Battle Arena") ~= nil, "p3 duel: a challenge from outside the arena is refused", tostring(why))
	toArena(a, 3, 0)
	toArena(b, -3, 0)
	toArena(c, 0, 4)
	-- the invite
	local mark = K.logSize()
	ok, why = bs.Challenge(a, b)
	T.check(ok == true, "p3 duel: Challenge(a, b) inside the arena sends an invite", tostring(why))
	local lobbyB = lastMsg(b, "Lobby", mark)
	local inv = lobbyB and lobbyB.Invites and lobbyB.Invites[1]
	T.check(type(inv) == "table" and inv.FromUserId == a.UserId and inv.FromName == a.DisplayName and type(inv.Trophies) == "number" and type(inv.Power) == "number"
		and inv.Power > 0 and inv.ExpiresIn == 30, "p3 duel: b's 'Lobby' lists the invite { FromUserId, FromName, Trophies, Power, ExpiresIn = 30 }")
	local lobbyA = lastMsg(a, "Lobby", mark)
	T.check(type(lobbyA) == "table" and type(lobbyA.Sent) == "table" and lobbyA.Sent.ToUserId == b.UserId and lobbyA.Sent.ToName == b.DisplayName and lobbyA.Sent.ExpiresIn == 30
		and type(lobbyA.Queue) == "table" and lobbyA.Queue.Queued == false and type(lobbyA.Queue.Waiting) == "number",
		"p3 duel: a's 'Lobby' shows Sent { ToUserId, ToName, ExpiresIn } and Queue { Queued, Waiting }")
	T.check(toasted(b, "challenges you", mark), "p3 duel: b gets a side toast about the challenge")
	T.check(bs.Challenge(a, b) == false, "p3 duel: the same challenge twice is refused")
	-- decline
	local m2 = K.logSize()
	ok = bs.ReplyChallenge(b, a.UserId, false)
	local lb, la = lastMsg(b, "Lobby", m2), lastMsg(a, "Lobby", m2)
	T.check(ok == true and lb and #lb.Invites == 0 and la and la.Sent == nil and toasted(a, "declined", m2), "p3 duel: a decline clears the invite on both sides and tells the challenger")
	-- expiry
	bs.Challenge(a, b)
	local m3 = K.logSize()
	advance(31.5)
	lb = lastMsg(b, "Lobby", m3)
	T.check(lb and #lb.Invites == 0 and toasted(a, "expired", m3) and bs.ReplyChallenge(b, a.UserId, true) == false,
		"p3 duel: an invite expires after 30 s (cleared, the challenger is told, accepting it is refused)")
	-- a challenge back is a yes (lobby-shop 16.12: both hold trophies, or the winner of a 0-trophy player gets none)
	data.AddTrophies(a, 50)
	data.AddTrophies(b, 50)
	local recA0, recB0 = record(a), record(b)
	local ta0, tb0 = tokens(a), tokens(b)
	local m4 = K.logSize()
	bs.Challenge(a, b)
	local id
	ok, id = bs.Challenge(b, a)
	if not T.check(ok == true and type(id) == "string" and a:GetAttribute("InBattle") == id and b:GetAttribute("InBattle") == id,
		"p3 duel: challenging back someone who challenged you accepts: the duel starts (InBattle on both)", tostring(id)) then
		w.stop()
		cleanup({ a, b, c, far })
		loudReplication()
		return
	end
	local ga, gb = bs.GetBattle(a), bs.GetBattle(b)
	T.check(ga and gb and ga.Mode == "Duel" and ga.Side == 1 and gb.Side == 2, "p3 duel: the challenger fights from side 1, the other from side 2")
	local zoneCF = ga.Zone.CFrame
	local ra, rb = zoneCF:PointToObjectSpace(K.root(a).Position), zoneCF:PointToObjectSpace(K.root(b).Position)
	T.check(ra.Z < -15 and rb.Z > 15 and math.abs(ra.X) < 6 and math.abs(rb.X) < 6, "p3 duel: both stand on their ring pads (side 1 at -Z, side 2 at +Z)",
		string.format("a %.1f,%.1f  b %.1f,%.1f", ra.X, ra.Z, rb.X, rb.Z))
	local onRing = false
	for _, ring in ipairs(info.Rings) do
		if (ring.CFrame.Position - zoneCF.Position).Magnitude < 0.5 then
			onRing = true
		end
	end
	T.check(onRing, "p3 duel: the duel runs on one of the arena's duel rings (ArenaInfo.Rings)")
	local sa, sb = lastMsg(a, "Start", m4), lastMsg(b, "Start", m4)
	T.check(sa and sb and sa.Mode == "Duel" and sa.Side == 1 and sb.Side == 2 and contains(sa.Sides[1], a.UserId) and contains(sa.Sides[2], b.UserId),
		"p3 duel: 'Start' to both duellists with their sides")
	T.check(lastMsg(a, "Lobby", m4) ~= nil and #lastMsg(b, "Lobby", m4).Invites == 0, "p3 duel: the 'Lobby' of both is refreshed when the duel starts")
	advance(2.2)
	local sc = lastMsg(c, "Start", m4)
	T.check(sc and sc.BattleId == id and sc.Spectator == true and sc.Side == 0 and #battleMsgs(c, m4, "Snapshot") > 0,
		"p3 duel: a player in the arena near the ring gets the battle as a spectator ('Start' Spectator = true, snapshots)")
	T.check(#battleMsgs(far, m4) == 0, "p3 duel: a player far away gets no battle traffic")
	local okC, whyC = bs.Command(c, "Attack")
	T.check(okC == false and whyC == "NoBattle", "p3 duel: a spectator cannot command anything", tostring(whyC))
	-- the end: both play (the characters walk in, ATTACK + the kit); a passive loser would make the win unpaid
	local mEnd = m4
	local ta, tb = drvTracker(a, m4), drvTracker(b, m4)
	drvPlay({ ta, tb }, 130, function()
		return w.find(id) ~= nil
	end)
	local r = w.find(id)
	if T.check(r ~= nil and r.Mode == "Duel" and #r.Winners == 1 and #r.Losers == 1 and not r.Draw, "p3 duel: the duel ends with one winner and one loser", r and tostring(r.Reason) or "no end") then
		local winner = (r.Winners[1] == a.UserId) and a or b
		local loser = (winner == a) and b or a
		local rwW, rwL = r.Rewards[winner.UserId], r.Rewards[loser.UserId]
		T.check(rwW and rwW.Trophies == TR.Win and rwW.Tokens == TR.Tokens.Win * doubled(rwW) and rwW.Xp == TR.Xp.Win,
			"p3 duel: the winner gets Trophies.Win, Tokens.Win and Xp.Win", rwW and (rwW.Trophies .. " / " .. rwW.Tokens .. " / " .. rwW.Xp) or "none")
		T.check(rwL and rwL.Tokens == TR.Tokens.Loss * doubled(rwL) and rwL.Xp == TR.Xp.Loss and rwL.Trophies == TR.Loss,
			"p3 duel: the loser gets Tokens.Loss, Xp.Loss and Trophies.Loss", rwL and (rwL.Trophies .. " / " .. rwL.Tokens) or "none")
		local recW0 = winner == a and recA0 or recB0
		local recL0 = winner == a and recB0 or recA0
		T.check(record(winner).PvPWins == (recW0.PvPWins or 0) + 1 and record(loser).PvPLosses == (recL0.PvPLosses or 0) + 1 and record(winner).Trophies == recW0.Trophies + TR.Win
			and record(loser).Trophies == recL0.Trophies + TR.Loss,
			"p3 duel: PvPWins / PvPLosses and the trophy totals moved once")
		local dW = tokens(winner) - (winner == a and ta0 or tb0)
		local dL = tokens(loser) - (winner == a and tb0 or ta0)
		T.check(dW == TR.Tokens.Win * doubled(rwW) and dL == TR.Tokens.Loss * doubled(rwL), "p3 duel: token balances moved by exactly the rewards", dW .. " / " .. dL)
		local endW = lastMsg(winner, "End", mEnd)
		T.check(endW and endW.Outcome == "Win" and endW.Rewards and endW.Rewards.Tokens == rwW.Tokens, "p3 duel: 'End' tells the winner (Outcome Win + Rewards)")
	end
	T.eq(w.count(id), 1, "p3 duel: BattleEnded fired exactly once")
	local endC = lastMsg(c, "End", mEnd)
	T.check(endC and endC.Spectator == true and endC.Rewards == nil, "p3 duel: the spectator gets 'End' (Spectator = true, no rewards)")
	T.check(a:GetAttribute("InBattle") == nil and b:GetAttribute("InBattle") == nil and not bs.IsInBattle(a), "p3 duel: InBattle is cleared for both at the end")
	advance(4.5)

	-- a forfeit after 15 s: the forfeiter loses Trophies.Forfeit, the winner gets the full win
	data.AddTrophies(b, 100)
	local tb100 = record(b).Trophies
	local id2
	local m4b = K.logSize()
	ok, id2 = bs.StartDuel(a, b)
	T.check(ok == true, "p3 duel: StartDuel(a, b) starts the next duel", tostring(id2))
	advance(0.3)
	-- both fight for 16 s (b deals damage: a loser who dealt damage keeps the winner's rewards), then b forfeits
	drvPlay({ drvTracker(a, m4b), drvTracker(b, m4b) }, 16, function()
		return w.find(id2) ~= nil
	end, { every = 6 })
	if w.find(id2) then
		T.info("*p3 duel: the 16 s fight ended by itself before the forfeit (" .. tostring(w.find(id2).Reason) .. ")")
	end
	local ta1 = tokens(a)
	Mock.FromClient(K.remoteFolder():FindFirstChild("BattleCommand"), b, "Forfeit")
	advance(0.5)
	local r2 = w.find(id2)
	T.check(r2 ~= nil and r2.Forfeit == true and contains(r2.Winners, a.UserId) and contains(r2.Losers, b.UserId),
		"p3 duel: BattleCommand('Forfeit') after 16 s: the forfeiter loses, the other wins (Forfeit = true)")
	local rwA2, rwB2 = r2 and r2.Rewards[a.UserId], r2 and r2.Rewards[b.UserId]
	T.check(rwA2 and rwA2.Trophies == TR.Win and rwA2.Tokens == TR.Tokens.Win * doubled(rwA2) and tokens(a) - ta1 == rwA2.Tokens, "p3 duel: ...a forfeit after 15 s pays the winner in full")
	T.check(rwB2 and rwB2.Forfeit == true and rwB2.Trophies == TR.Forfeit and record(b).Trophies == tb100 + TR.Forfeit and (rwB2.Tokens or 0) == 0,
		"p3 duel: ...the forfeiter loses Trophies.Forfeit and gets no tokens", rwB2 and tostring(rwB2.Trophies) or "none")
	advance(4.5)

	-- an early forfeit: the win counts, but pays nothing (no farming with an alt that quits at once)
	local id3
	ok, id3 = bs.StartDuel(a, b)
	advance(2.3) -- nobody moves: an early forfeit
	local ta2, tra2, wins2 = tokens(a), record(a).Trophies, record(a).PvPWins
	bs.Forfeit(b)
	advance(0.5)
	local r3 = w.find(id3)
	local rwA3 = r3 and r3.Rewards[a.UserId]
	T.check(ok and r3 and contains(r3.Winners, a.UserId) and rwA3 and rwA3.Trophies == 0 and rwA3.Tokens == 0 and rwA3.Xp == 0 and tokens(a) == ta2
		and record(a).Trophies == tra2 and record(a).PvPWins == wins2 + 1,
		"p3 duel: a forfeit within 15 s: the win counts (PvPWins) but pays no trophies, tokens or XP")
	T.check(r3 and r3.Rewards[b.UserId] and r3.Rewards[b.UserId].Trophies == TR.Forfeit, "p3 duel: ...the early quitter still loses Trophies.Forfeit")
	advance(4.5)

	-- the pair limit + a disconnect: the 4th duel of the same two pays no trophies; the leaver's penalty is saved
	local m5 = K.logSize()
	local id4
	ok, id4 = bs.StartDuel(a, b)
	T.check(ok and toasted(a, "no trophies", m5), "p3 duel: the 4th duel of the same two players within 30 min is announced as trophy-free")
	advance(0.3)
	drvPlay({ drvTracker(a, m5), drvTracker(b, m5) }, 17, function()
		return w.find(id4) ~= nil
	end, { every = 6 })
	local tbBefore = record(b).Trophies
	local traBefore = record(a).Trophies
	local bUser = b.UserId
	Mock.DataStore.Latency = 0.2 -- a real DataStore call takes a moment: the leave save is still running when the penalty is written
	Mock.RemovePlayer(b)
	advance(0.5)
	local r4 = w.find(id4)
	T.check(r4 ~= nil and contains(r4.Winners, a.UserId) and contains(r4.Losers, bUser) and r4.Forfeit == true, "p3 duel: a disconnect mid-duel: the leaver loses, the other wins")
	T.check(r4 and r4.Rewards[a.UserId] and r4.Rewards[a.UserId].Trophies == 0 and record(a).Trophies == traBefore and r4.Rewards[a.UserId].Tokens == 0 and r4.Rewards[a.UserId].Xp == 0,
		"p3 duel: ...past the pair limit the winner gets no trophies, tokens or XP")
	advance(13) -- the leave save, then DataService's retry of the entry that changed meanwhile
	Mock.DataStore.Latency = 0
	local st = storedBattle(bUser)
	T.check(type(st) == "table" and st.Trophies == tbBefore + TR.Forfeit, "p3 duel: ...the leaver's Trophies.Forfeit penalty is in the saved profile (written before the save on leave)",
		st and tostring(st.Trophies) or "nothing stored")
	T.eq(w.count(id4), 1, "p3 duel: ...BattleEnded once")
	T.check(a:GetAttribute("InBattle") == nil, "p3 duel: the winner is free again")
	K.flushErrors("p3 duel")
	w.stop()
	cleanup({ a, c, far })
	loudReplication()
end)

----------------------------------------------------------------------------------------------------
-- scenario: lobby-shop 16.12, Trophies cannot be farmed across servers
----------------------------------------------------------------------------------------------------
S.p3bs_pair_hop = scenario("p3bs_pair_hop", function()
	if not ready("p3bs_pair_hop") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	local TR = bc.Trophies
	local w = watchEnded()
	local players = {}
	local okRun, errRun = pcall(function()
		if not T.check(type(data.DuelsWith) == "function" and type(data.RecordDuel) == "function" and type(bs._ClearPairsForTest) == "function",
			"pair hop: DataService.DuelsWith / RecordDuel and BattleService._ClearPairsForTest exist") then
			return
		end
		local a = newPlayer("HopA", STRONG, 10)
		local b = newPlayer("HopB", MID, 10)
		players = { a, b }
		local aId, bId = a.UserId, b.UserId
		data.AddTrophies(a, 100)
		data.AddTrophies(b, 100)
		local fresh = data.GetBattle(a)
		T.check(type(fresh) == "table" and type(fresh.Duels) == "table" and #fresh.Duels == 0, "pair hop: a save without the record reads Battle.Duels = {} (the migration-safe default)")
		toArena(a, 3, 0)
		toArena(b, -3, 0)
		-- three real duels (each quit at once: the pair counts at the start, like the in-server limit)
		for i = 1, 3 do
			local m = K.logSize()
			local ok, id = bs.StartDuel(a, b)
			T.check(ok == true and not toasted(a, "no trophies", m), "pair hop: duel " .. i .. " of a and b starts with rewards", tostring(id))
			advance(0.3)
			bs.Forfeit(b)
			advance(4.5)
			toArena(a, 3, 0)
			toArena(b, -3, 0)
		end
		local since = os.time() - 1800
		T.check(data.DuelsWith(a, bId, since) == 3 and data.DuelsWith(b, aId, since) == 3, "pair hop: both saves hold the three duels with the other (DuelsWith 3 / 3)",
			tostring(data.DuelsWith(a, bId, since)) .. " / " .. tostring(data.DuelsWith(b, aId, since)))
		-- a server hop: both leave (the saves carry the record), this server forgets its pair list, both join again
		K.removePlayers({ a, b })
		advance(13)
		local stA = storedBattle(aId)
		T.check(type(stA) == "table" and type(stA.Duels) == "table" and #stA.Duels == 3, "pair hop: the stored Battle record holds the duels (Battle.Duels, 3 entries)",
			stA and tostring(stA.Duels and #stA.Duels) or "nothing stored")
		bs._ClearPairsForTest()
		a = Mock.AddPlayer("HopA2", aId)
		b = Mock.AddPlayer("HopB2", bId)
		players = { a, b }
		advance(1.0)
		data.SetTeam(a, 1, STRONG)
		data.SetTeam(b, 1, MID)
		toArena(a, 3, 0)
		toArena(b, -3, 0)
		local m4 = K.logSize()
		local ok4, id4 = bs.StartDuel(a, b)
		T.check(ok4 == true and toasted(a, "no trophies", m4) and toasted(b, "no trophies", m4),
			"pair hop: after the hop the 4th duel within 30 min is trophy-free (the limit read from the saves)", tostring(id4))
		advance(0.3)
		bs.Forfeit(b)
		advance(4.5)
		-- one side's save is enough (the other's record lost): b's record alone still holds the limit
		toArena(a, 3, 0)
		toArena(b, -3, 0)
		bs._ClearPairsForTest()
		data.MutateBattle(a, function(rec)
			rec.Duels = {}
		end)
		local m5 = K.logSize()
		local ok5 = bs.StartDuel(a, b)
		T.check(ok5 == true and toasted(a, "no trophies", m5), "pair hop: ...even when only one of the two saves remembers the pair")
		advance(0.3)
		bs.Forfeit(b)
		advance(4.5)
		-- 30 minutes later (the Unix clock moved on) the pair is rewarded again
		bs._ClearPairsForTest()
		local base = os.time()
		bs.Debug = { RaidNow = function()
			return base + 1801
		end }
		toArena(a, 3, 0)
		toArena(b, -3, 0)
		local m6 = K.logSize()
		local ok6 = bs.StartDuel(a, b)
		T.check(ok6 == true and not toasted(a, "no trophies", m6), "pair hop: 30 min after the last duels the pair earns again")
		advance(0.3)
		bs.Forfeit(b)
		advance(4.5)
		bs.Debug = nil
		-- the record is bounded (review fix 6): every entry inside the 30-minute window is kept, plus at most 32 older ones,
		-- and never more than 64 in all (the newest first); junk dropped. ~30 other duels in the window cannot flush a pair.
		data.MutateBattle(a, function(r)
			r.Duels = {}
		end)
		local now = os.time()
		data.RecordDuel(a, bId, now - 1500) -- the pair, inside the window
		for i = 1, 40 do
			data.RecordDuel(a, 7000000 + i, now - 3000 - i) -- older than the window
		end
		for i = 1, 40 do
			data.RecordDuel(a, 7100000 + i, now - 1000 + i) -- other opponents inside the window, all newer than the pair's entry
		end
		data.RecordDuel(a, -5, now)
		data.RecordDuel(a, 0 / 0, now)
		data.RecordDuel(a, 7200000, 0 / 0)
		local rec = data.GetBattle(a)
		local list = rec and rec.Duels or {}
		local young, old, oldest = 0, 0, nil
		for _, e in ipairs(list) do
			if e.T >= now - 1800 then
				young = young + 1
			else
				old = old + 1
				oldest = e
			end
		end
		T.check(young == 41 and old == 23 and #list == 64 and list[1].U == 7100040 and data.DuelsWith(a, bId, now - 1799) == 1,
			"pair hop: Battle.Duels keeps all 41 entries of the window (the pair's too, under 40 newer ones) and fills up to 64 with the newest older ones; junk dropped",
			#list .. " entries: " .. young .. " in the window, " .. old .. " older; pair count " .. tostring(data.DuelsWith(a, bId, now - 1799)))
		-- fewer in the window: up to 32 older ones join them
		data.MutateBattle(a, function(r)
			r.Duels = {}
		end)
		for i = 1, 40 do
			data.RecordDuel(a, 7000000 + i, now - 3000 - i)
		end
		for i = 1, 5 do
			data.RecordDuel(a, 7100000 + i, now - 100 + i)
		end
		rec = data.GetBattle(a)
		list = rec and rec.Duels or {}
		young, old, oldest = 0, 0, nil
		for _, e in ipairs(list) do
			if e.T >= now - 1800 then
				young = young + 1
			else
				old = old + 1
				oldest = e
			end
		end
		T.check(#list == 37 and young == 5 and old == 32 and oldest and oldest.U == 7000032, "pair hop: ...5 in the window + the newest 32 older ones (37)",
			#list .. " entries, oldest kept " .. tostring(oldest and oldest.U))
		-- a flood inside the window: the hard limit of 64 (the newest kept)
		for i = 1, 70 do
			data.RecordDuel(a, 7300000 + i, now - 90 + i) -- (newer than every entry above)
		end
		rec = data.GetBattle(a)
		list = rec and rec.Duels or {}
		T.check(#list == 64 and list[1].U == 7300070 and list[64].U == 7300007, "pair hop: ...never more than 64 entries (70 in the window: the newest 64)",
			#list .. " entries, last " .. tostring(list[64] and list[64].U))
		K.flushErrors("pair hop")
	end)
	w.stop()
	cleanup(players)
	if not okRun then
		error(errRun, 0)
	end
end)

----------------------------------------------------------------------------------------------------
-- scenario: lobby-shop 16.12 / 16.13, a smaller Trophy prize for beating a player who has none
-- (the owner's answer of 2026-11-08: floor(Config.Battle.ZeroTrophyShare x the normal win), at least 1)
----------------------------------------------------------------------------------------------------
S.p3bs_zero_trophy = scenario("p3bs_zero_trophy", function()
	if not ready("p3bs_zero_trophy") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	local Config = req("shared/Config")
	local TR = bc.Trophies
	local w = watchEnded()
	local a = newPlayer("ZeroA", STRONG, 10)
	local z = newPlayer("ZeroZ", MID, 10)
	-- one full duel a vs z: both fight 16 s (z deals damage), then z forfeits (a full win). Returns r, rwA, tokens gained, mark
	local function fullWin(label)
		toArena(a, 3, 0)
		toArena(z, -3, 0)
		local m = K.logSize()
		local ok, id = bs.StartDuel(a, z)
		if not T.check(ok == true, "zero trophy: " .. label .. ": the duel starts", tostring(id)) then
			return nil
		end
		advance(0.3)
		drvPlay({ drvTracker(a, m), drvTracker(z, m) }, 16, function()
			return w.find(id) ~= nil
		end, { every = 6 })
		local ta = tokens(a)
		if not w.find(id) then
			bs.Forfeit(z)
			advance(0.5)
		end
		local r = w.find(id)
		advance(5) -- the ring's cooldown before the next duel
		return r, r and r.Rewards[a.UserId], tokens(a) - ta, m
	end
	local okRun, errRun = pcall(function()
		-- the factor lives in Config, and the prize rule itself (pure)
		local share = type(Config.Battle) == "table" and Config.Battle.ZeroTrophyShare or nil
		T.check(share == 0.25, "zero trophy: Config.Battle.ZeroTrophyShare = 0.25", tostring(share))
		local prize = bs.ZeroTrophyPrize
		if T.check(type(prize) == "function", "zero trophy: BattleService.ZeroTrophyPrize exists") then
			local rule = T.tally("zero trophy: ZeroTrophyPrize = floor(share x the normal win), at least 1; nothing stays nothing")
			for _, c in ipairs({ { 20, 0.25, 5 }, { 21, 0.25, 5 }, { 3, 0.25, 1 }, { 1, 0.25, 1 }, { 0, 0.25, 0 }, { -10, 0.25, -10 }, { 20, 0.1, 2 }, { 20, 0.01, 1 }, { 20, 1, 20 } }) do
				local got = prize(c[1], c[2])
				rule:case(got == c[3], c[1] .. " x " .. c[2] .. " -> " .. tostring(got) .. " (want " .. c[3] .. ")")
			end
			for _, junk in ipairs({ "x", -1, 0, 2, 0 / 0, math.huge }) do
				local got = prize(20, junk)
				rule:case(got == 5, "junk share " .. tostring(junk) .. " -> " .. tostring(got) .. " (the 0.25 default)")
			end
			rule:case(prize(20) == math.max(1, math.floor(20 * share)), "no share argument reads Config (" .. tostring(prize(20)) .. ")")
			rule:report()
		end
		-- review fix 1: "low" = fewer Trophies at the start than a normal loss takes (|Trophies.Loss| = 10), not only 0;
		-- review fix 5: an unknown total (nil, junk) is never "low"
		local lossAmount = math.abs(TR.Loss)
		local low = bs.LowTrophyOpponent
		if T.check(type(low) == "function", "zero trophy: BattleService.LowTrophyOpponent exists") then
			local rule = T.tally("zero trophy: LowTrophyOpponent(trophies at the start) = a known total below |Trophies.Loss| (" .. lossAmount .. ")")
			for _, c in ipairs({ { 0, true }, { 5, true }, { 9, true }, { lossAmount - 1, true }, { lossAmount, false }, { 10, false }, { 50, false }, { nil, false }, { 0 / 0, false }, { "3", false }, { math.huge, false }, { -1, true } }) do
				local got = low(c[1])
				rule:case(got == c[2], tostring(c[1]) .. " -> " .. tostring(got) .. " (want " .. tostring(c[2]) .. ")")
			end
			rule:report()
		end
		local LOW_TOAST = "Victory! Low-trophy opponent: smaller trophy prize."

		data.AddTrophies(a, 100)
		T.eq(record(z).Trophies or 0, 0, "zero trophy: (setup) the opponent has 0 Trophies")
		local small = math.max(1, math.floor(TR.Win * 0.25))
		local r, rwA, gained, m = fullWin("vs a new player")
		if T.check(r ~= nil and contains(r.Winners, a.UserId), "zero trophy: a wins against the 0-trophy player", r and tostring(r.Reason) or "no end") then
			T.check(rwA and rwA.Trophies == small and record(a).Trophies == 100 + small and rwA.LowTrophyOpponent == true and rwA.NewOpponent == nil and rwA.NoTrophies == nil,
				"zero trophy: ...and gets the smaller prize: floor(1/4 x " .. TR.Win .. ") = " .. small .. " Trophies (LowTrophyOpponent on the reward)",
				rwA and (tostring(rwA.Trophies) .. " / total " .. tostring(record(a).Trophies)) or "none")
			T.check(rwA and rwA.Tokens == TR.Tokens.Win * doubled(rwA) and rwA.Xp == TR.Xp.Win and gained == rwA.Tokens,
				"zero trophy: ...the win's tokens and XP are paid in full", rwA and (rwA.Tokens .. " / " .. rwA.Xp) or "none")
			T.check(toastedPlain(a, LOW_TOAST .. " +" .. small .. " trophies", m) and not toasted(a, "no trophies to win", m) and not toasted(a, "was new", m),
				"zero trophy: ...and the toast says so ('" .. LOW_TOAST .. " +" .. small .. " trophies')", table.concat(toasts(a, m), " | "))
			local rwZ = r.Rewards[z.UserId]
			T.check(rwZ and (rwZ.Trophies or 0) == 0 and (record(z).Trophies or 0) == 0, "zero trophy: the loser's trophies never go below 0",
				rwZ and tostring(rwZ.Trophies) or "none")
		end
		-- review fix 1: an alt holding a few Trophies (5, less than the 10 a loss takes) is no full prize either
		data.AddTrophies(z, 5)
		T.eq(record(z).Trophies, 5, "zero trophy: (setup) the opponent now holds 5 Trophies")
		local beforeLow = record(a).Trophies
		local rL, rwL, _, mL = fullWin("vs a player with 5 Trophies")
		if T.check(rL ~= nil and contains(rL.Winners, a.UserId), "zero trophy: a beats the opponent who holds 5 Trophies", rL and tostring(rL.Reason) or "no end") then
			T.check(rwL and rwL.Trophies == small and record(a).Trophies == beforeLow + small and rwL.LowTrophyOpponent == true,
				"zero trophy: ...the smaller prize too (+" .. small .. ", not +" .. TR.Win .. ": 5 is below the " .. lossAmount .. " a loss takes)",
				rwL and (tostring(rwL.Trophies) .. " / total " .. tostring(record(a).Trophies)) or "none")
			T.check(toastedPlain(a, LOW_TOAST, mL), "zero trophy: ...with the low-trophy toast", table.concat(toasts(a, mL), " | "))
			T.eq(record(z).Trophies or 0, 0, "zero trophy: ...the loser drops to 0 (never below)")
		end
		-- a normal opponent (one who holds Trophies) is unchanged: the full win
		data.AddTrophies(z, 50)
		local before = record(a).Trophies
		local r2, rw2, _, m2 = fullWin("vs a player with Trophies")
		if T.check(r2 ~= nil and contains(r2.Winners, a.UserId), "zero trophy: a beats the opponent who now holds 50 Trophies", r2 and tostring(r2.Reason) or "no end") then
			T.check(rw2 and rw2.Trophies == TR.Win and record(a).Trophies == before + TR.Win and rw2.LowTrophyOpponent == nil,
				"zero trophy: ...the normal win: +" .. TR.Win .. " Trophies, no LowTrophyOpponent", rw2 and (tostring(rw2.Trophies) .. " / total " .. tostring(record(a).Trophies)) or "none")
			T.check(toastedPlain(a, "Victory! +" .. TR.Win .. " trophies", m2) and not toasted(a, "smaller trophy prize", m2),
				"zero trophy: ...with the normal toast", table.concat(toasts(a, m2), " | "))
		end
		-- review fix 5: an opponent whose record cannot be read at the start (a provisional save: GetBattle nil) is not
		-- treated as 0: the winner gets the full prize (z really holds 40 here)
		bs._ClearPairsForTest()
		for _, p in ipairs({ a, z }) do
			data.MutateBattle(p, function(rec)
				rec.Duels = {}
			end)
		end
		T.check((record(z).Trophies or 0) >= lossAmount, "zero trophy: (setup) the opponent holds " .. tostring(record(z).Trophies) .. " Trophies")
		local realGetBattle = data.GetBattle
		local zId = z.UserId
		data.GetBattle = function(p, ...)
			if p == z or (type(p) == "userdata" or type(p) == "table") and p.UserId == zId then
				return nil
			end
			return realGetBattle(p, ...)
		end
		local okU, rU, rwU, _, mU = pcall(function()
			toArena(a, 3, 0)
			toArena(z, -3, 0)
			local m = K.logSize()
			local ok, id = bs.StartDuel(a, z)
			data.GetBattle = realGetBattle -- only the start reads the unknown record
			if not T.check(ok == true, "zero trophy: unknown record: the duel starts", tostring(id)) then
				return nil
			end
			advance(0.3)
			drvPlay({ drvTracker(a, m), drvTracker(z, m) }, 16, function()
				return w.find(id) ~= nil
			end, { every = 6 })
			if not w.find(id) then
				bs.Forfeit(z)
				advance(0.5)
			end
			local res = w.find(id)
			advance(5)
			return res, res and res.Rewards[a.UserId], nil, m
		end)
		data.GetBattle = realGetBattle
		if T.check(okU, "zero trophy: unknown record: ran", tostring(rU)) and T.check(rU ~= nil and contains(rU.Winners, a.UserId), "zero trophy: a beats the opponent whose record was unknown at the start") then
			T.check(rwU and rwU.Trophies == TR.Win and rwU.LowTrophyOpponent == nil and not toasted(a, "smaller trophy prize", mU),
				"zero trophy: ...an unknown total is not 0: the full +" .. TR.Win .. " (no smaller prize)", rwU and tostring(rwU.Trophies) or "none")
		end
		K.flushErrors("zero trophy")
	end)
	w.stop()
	cleanup({ a, z })
	if not okRun then
		error(errRun, 0)
	end
end)

----------------------------------------------------------------------------------------------------
-- scenario: the quick queue
----------------------------------------------------------------------------------------------------
S.p3bs_queue = scenario("p3bs_queue", function()
	if not ready("p3bs_queue") then
		return
	end
	quietReplication()
	local bs, data = BS(), DS()
	local q1 = newPlayer("Queue", MID)
	local q2 = newPlayer("Queue", ALT)
	local q3 = newPlayer("Queue", WEAK)
	local q4 = newPlayer("Queue", WEAK)
	local q5 = newPlayer("Queue", WEAK)
	data.AddTrophies(q1, 100)
	data.AddTrophies(q2, 120)
	data.AddTrophies(q3, 900)
	data.AddTrophies(q4, 400)
	for i, p in ipairs({ q1, q2, q3, q4, q5 }) do
		toArena(p, i * 3 - 9, 6)
	end
	local mark = K.logSize()
	local ok = bs.Queue(q1)
	local l1 = lastMsg(q1, "Lobby", mark)
	T.check(ok == true and l1 and l1.Queue.Queued == true and l1.Queue.Waiting == 1, "p3 queue: Queue puts the player in the queue ('Lobby' Queued = true, Waiting = 1)")
	T.check(bs.Queue(q1) == false, "p3 queue: queueing twice is refused")
	bs.Queue(q3)
	l1 = lastMsg(q1, "Lobby", mark)
	T.check(l1 and l1.Queue.Waiting == 2, "p3 queue: everybody queued sees the new Waiting count")
	advance(2.2)
	T.check(not bs.IsInBattle(q1) and not bs.IsInBattle(q3), "p3 queue: 100 vs 900 trophies do not pair at once")
	bs.Queue(q2)
	advance(1.5)
	local b1, b2 = bs.GetBattle(q1), bs.GetBattle(q2)
	T.check(b1 and b2 and b1.BattleId == b2.BattleId and b1.Mode == "Duel", "p3 queue: 100 and 120 trophies pair within a second or two (a duel on a ring)")
	local l3 = lastMsg(q3, "Lobby", mark)
	T.check(not bs.IsInBattle(q3) and l3 and l3.Queue.Queued == true and l3.Queue.Waiting == 1, "p3 queue: the one left over stays queued (Waiting = 1)")
	T.check(bs.Unqueue(q3) == true and lastMsg(q3, "Lobby", mark).Queue.Queued == false and bs.Unqueue(q3) == false, "p3 queue: Unqueue leaves the queue (once)")
	-- far apart: only once the allowance has grown with the wait
	bs.Queue(q3)
	bs.Queue(q4)
	advance(15)
	T.check(not bs.IsInBattle(q3) and not bs.IsInBattle(q4), "p3 queue: 400 vs 900 trophies still wait after 15 s")
	advance(17)
	local b3, b4 = bs.GetBattle(q3), bs.GetBattle(q4)
	T.check(b3 and b4 and b3.BattleId == b4.BattleId, "p3 queue: ...and pair after ~30 s, when the allowance covers the gap")
	-- leaving the arena cancels the queue
	local m2 = K.logSize()
	bs.Queue(q5)
	toLobby(q5)
	advance(1.5)
	local l5 = lastMsg(q5, "Lobby", m2)
	T.check(l5 and l5.Queue.Queued == false and toasted(q5, "queue cancelled", m2), "p3 queue: leaving the arena cancels the queue (side toast)")
	-- joining a battle takes the player out of the queue, and their 'Lobby' says so
	toArena(q5, 0, 10)
	bs.Queue(q5)
	endAnyRaid(bs)
	local m3 = K.logSize()
	local okJ = bs.EnterRaid(q5)
	local l6 = lastMsg(q5, "Lobby", m3)
	T.check(okJ and l6 and l6.Queue.Queued == false and not bs.Unqueue(q5), "p3 queue: entering a boss fight takes the player out of the queue ('Lobby' Queued = false)")
	endAnyRaid(bs)
	K.flushErrors("p3 queue")
	cleanup({ q1, q2, q3, q4, q5 })
	loudReplication()
end)

----------------------------------------------------------------------------------------------------
-- scenario: boss raids
----------------------------------------------------------------------------------------------------
S.p3bs_raid = scenario("p3bs_raid", function()
	if not ready("p3bs_raid") then
		return
	end
	quietReplication()
	local bs, bc = BS(), BC()
	local info = arenaInfo()
	local w = watchEnded()
	endAnyRaid(bs)
	local r1 = newPlayer("Raid", STRONG, 10)
	local r2 = newPlayer("Raid", MID, 10)
	local r3 = newPlayer("Raid", ALT, 10)
	local outsider = newPlayer("RaidOut", WEAK)
	toArena(r1, -6, 0)
	toArena(r2, 0, 0)
	Mock.Teleport(r3, info.Floor.CFrame * CFrame.new(0, 3, 62)) -- inside the colosseum, off the fighting floor
	advance(0.05)
	toLobby(outsider)
	T.check(bs.SetRaidBoss("no_such_boss") == false, "p3 raid: an unknown boss is refused")
	-- Phase 5: one fighter alone does not outlive the boss for a whole minute (its basics are a share of the fighter's HP),
	-- so the solo stretch below lasts 25 s
	-- team balance: this scenario watches the boss HP move with its level-10 teams; the baseline's floor would hold it flat
	local savedFloor = bc.BossRules.FloorSeconds
	bc.BossRules.FloorSeconds = 5
	local window = 25
	T.check(bs.SetRaidBoss("storm_titan") == true, "p3 raid: (the boss is Storm Titan)")
	local st = bs.GetRaidStatus()
	T.check(st and st.Active == false and st.BossId == "storm_titan" and next(st.Fights) == nil and st.BattleId == nil and type(st.Name) == "string",
		"p3 raid: GetRaidStatus before anyone walks in: { Active = false, BossId, Name, no fights }")
	local okO, whyO = bs.EnterRaid(outsider)
	T.check(okO == false and type(whyO) == "string" and whyO:find("Battle Arena") ~= nil, "p3 raid: a player outside the arena cannot enter", tostring(whyO))
	local mark = K.logSize()
	local okJ, raidId = bs.EnterRaid(r1)
	T.check(okJ == true and type(raidId) == "string" and r1:GetAttribute("InBattle") == raidId, "p3 raid: EnterRaid inside the arena: the raid battle starts (InBattle = raid id)", tostring(raidId))
	local function fight()
		return bs.GetRaidStatus().Fights.Starter
	end
	local s1 = fight()
	T.check(s1 and s1.Players == 1 and s1.MaxHp > 0 and s1.Hp == s1.MaxHp and s1.EndsIn > 300 and s1.BattleId == raidId, "p3 raid: the boss HP is set for one team", s1 and (s1.Hp .. "/" .. s1.MaxHp) or "nil")
	local start1 = lastMsg(r1, "Start", mark)
	local bossUnit = nil
	for _, u in ipairs(start1 and start1.Units or {}) do
		if u.kind == "Boss" then
			bossUnit = u
		end
	end
	T.check(start1 and start1.Mode == "Raid" and start1.BossId == "storm_titan" and bossUnit and bossUnit.boss == "storm_titan",
		"p3 raid: 'Start' with Mode Raid, BossId and the boss unit")
	local rim = planarTo(r1, info.Floor.CFrame)
	T.check(rim > 46 and rim < 62, "p3 raid: the joiner stands on the floor's rim", string.format("%.1f studs from the centre", rim))
	local m2 = K.logSize()
	bs.EnterRaid(r2)
	local s2 = fight()
	-- bug batch 2 #2: two level-10 teams can sit on the boss's BaselineDps floor (FloorSeconds x BaselineDps): then the HP holds
	local floorHp = bc.BaselineDps and (bc.BossRules.FloorSeconds * bc.BaselineDps("storm_titan", "Starter")) or 0
	T.check(s2.Players == 2 and (s2.MaxHp > s1.MaxHp or (s1.MaxHp <= floorHp + 1 and s2.MaxHp == s1.MaxHp)), "p3 raid: a second team raises the boss HP (or both sit on the BaselineDps floor)",
		s1.MaxHp .. " -> " .. s2.MaxHp .. string.format(" (floor %.0f)", floorHp))
	advance(0.3)
	local spawnToR1, spawnToR2 = false, false
	for _, ev in ipairs(eventsOf(r1, m2, "Spawn")) do
		if ev.owner == r2.UserId then
			spawnToR1 = true
		end
	end
	for _, ev in ipairs(eventsOf(r2, m2, "Spawn")) do
		if ev.owner == r2.UserId then
			spawnToR2 = true
		end
	end
	local firstR2 = battleMsgs(r2, m2)[1]
	T.check(spawnToR1 and firstR2 and firstR2.args[1] == "Start" and not spawnToR2,
		"p3 raid: the fighters see the newcomer's units arrive (Spawn); the newcomer gets one 'Start' instead")
	T.check(bs.EnterRaid(r2) == false, "p3 raid: joining twice is refused")
	advance(1.5)
	local spec = lastMsg(r3, "Start", m2)
	T.check(spec and spec.Spectator == true and spec.BattleId == raidId, "p3 raid: a player watching in the arena spectates the raid")
	local m3 = K.logSize()
	bs.EnterRaid(r3)
	advance(0.3)
	local st3 = lastMsg(r3, "Start", m3)
	T.check(st3 and st3.Spectator == false and st3.Side == 1 and fight().Players == 3, "p3 raid: a spectator who joins gets a fresh 'Start' as a fighter")
	-- leaving
	local before = fight().MaxHp
	local m4 = K.logSize()
	T.check(bs.LeaveRaid(r2) == true, "p3 raid: LeaveRaid")
	local e2 = lastMsg(r2, "End", m4)
	local s4 = fight()
	T.check(e2 and e2.Outcome == "Left" and r2:GetAttribute("InBattle") == nil and s4.Players == 2 and s4.MaxHp < before,
		"p3 raid: the leaver gets 'End' (Outcome Left), InBattle is cleared, the boss sheds that share", before .. " -> " .. s4.MaxHp)
	advance(0.3)
	local leaveSeen = false
	for _, ev in ipairs(eventsOf(r1, m4, "Leave")) do
		if ev.owner == r2.UserId then
			leaveSeen = true
		end
	end
	T.check(leaveSeen, "p3 raid: the others get a Leave event")
	local okR, whyR = bs.EnterRaid(r2)
	T.check(okR == false and type(whyR) == "string" and whyR:find("left") ~= nil, "p3 raid: a leaver cannot rejoin the same raid", tostring(whyR))
	toLobby(r3)
	advance(8) -- (bug batch 6: r3 joined 0.6 s ago: the rest of the 2 s teleport grace, 0.5 s out, the warning, the 5 s countdown, two 0.5 s monitor ticks; was 1.5)
	T.check(r3:GetAttribute("InBattle") == nil and fight().Players == 1, "p3 raid: a fighter who leaves the arena is out of the raid")
	-- a late joiner (r1 fights meanwhile: the boss must be hit for the Loss tier)
	local late = newPlayer("RaidLate", WEAK)
	toArena(late, 0, 8)
	drvPlay({ drvTracker(r1, mark) }, window, nil, { every = 20 }) -- r1 fights on (a hit every 2 s) and dodges the telegraphs
	local okL, idL = bs.EnterRaid(late)
	T.check(okL == true and idL == raidId and fight().Players == 2, "p3 raid: no join window: a late joiner gets into the running fight", tostring(idL))
	T.check(bs.LeaveRaid(late) == true, "p3 raid: (the late joiner leaves again)")
	-- EndRaids: the fighters still in it lose by timeout; rewards once; Double Rewards pushed by EventService
	bs.SetDoubleRewards(true, 600)
	T.check(bs.IsDoubleRewards() == true, "p3 raid: SetDoubleRewards(true) turns Double Rewards on")
	local tok1, tok2 = tokens(r1), tokens(r2)
	local raids0 = record(r1).Raids or 0
	T.eq(bs.EndRaids("Ended"), 1, "p3 raid: EndRaids ends the running fight")
	local res = w.find(raidId)
	T.check(res and res.Mode == "Raid" and res.BossId == "storm_titan" and contains(res.Losers, r1.UserId) and not contains(res.Losers, r2.UserId)
		and type(res.Damage) == "table" and (res.Damage[r1.UserId] or 0) > 0,
		"p3 raid: the result { Mode Raid, BossId, Losers = the fighters still in it, Damage = {[userId] = n} }")
	local loss = bc.RaidTier(1, false, "Starter")
	local rw1 = res and res.Rewards[r1.UserId]
	T.check(rw1 and rw1.Tier == "Loss" and rw1.Tokens == loss.Tokens * 2 and tokens(r1) - tok1 == loss.Tokens * 2,
		"p3 raid: a failed raid pays the Loss tier, doubled during Double Rewards", rw1 and tostring(rw1.Tokens) or "none")
	T.check(res and res.Rewards[r2.UserId] == nil and tokens(r2) == tok2, "p3 raid: a player who left gets nothing")
	T.check(record(r1).Raids == raids0 + 1 and (record(r1).RaidBestDamage or 0) > 0, "p3 raid: Raids + 1 and RaidBestDamage in the battle record")
	local afterEnd = bs.GetRaidStatus()
	T.check(afterEnd.Active == false and next(afterEnd.Fights) == nil and next(afterEnd.Closed) == nil and bs.EndRaids("Ended") == 0 and w.count(raidId) == 1 and r1:GetAttribute("InBattle") == nil,
		"p3 raid: afterwards: no fight, no closure (a timeout is no kill), EndRaids 0, BattleEnded once, InBattle cleared")
	bs.SetDoubleRewards(false)
	T.check(bs.IsDoubleRewards() == false, "p3 raid: SetDoubleRewards(false) turns it off")
	bs.SetDoubleRewards(nil)
	-- with nobody in, the boss just waits: no fight opens, nothing ends
	advance(window + 1.5)
	local waiting = bs.GetRaidStatus()
	T.check(waiting.Active == false and waiting.BossId == "storm_titan" and next(waiting.Fights) == nil and bs.EndRaids("Ended") == 0, "p3 raid: with nobody in the boss waits (no fight, no end)")
	bc.BossRules.FloorSeconds = savedFloor
	cleanup({ r1, r2, r3, outsider, late })

	-- a whole raid with three active teams at High (specials, retreat from telegraphs): rewards follow the damage medals. A boss
	-- still standing after 90 s of real play is nearly gone, so the win's drops are always checked (a group's chance is about 40%
	-- on purpose; the balance itself is tools/sim_battle.lua's job)
	endAnyRaid(bs)
	local heroes = {}
	local teams = { STRONG, MID, ALT }
	for i = 1, 3 do
		heroes[i] = newPlayer("Hero", teams[i], 60)
		toArena(heroes[i], i * 3 - 6, 2)
	end
	-- this raid's drops are certain (the tiers' GemChance / EventPetChance raised for the test, restored below)
	local saved = {}
	for i, tier in ipairs(bc.Raid.Tiers) do
		saved[i] = { tier.GemChance, tier.EventPetChance }
		tier.GemChance, tier.EventPetChance = 1, 1
	end
	local idW = nil
	local heroTrs = {}
	for i = 1, 3 do
		heroTrs[i] = drvTracker(heroes[i])
		local _, id = bs.EnterRaid(heroes[i])
		idW = idW or id
	end
	local okW = type(idW) == "string" and bs.GetRaidStatus().Fights.High ~= nil and bs.GetRaidStatus().Fights.High.Players == 3
	local before0, gems0 = {}, {}
	for i = 1, 3 do
		before0[i] = tokens(heroes[i])
		gems0[i] = DS().GetGems(heroes[i])
	end
	local cursor = K.logSize()
	local t0 = os.clock()
	local specials, telegraphs = 0, 0
	while okW and w.find(idW) == nil and os.clock() - t0 < 345 do
		advance(0.5)
		specials = specials + #eventsOf(heroes[1], cursor, "Special")
		local tele = eventsOf(heroes[1], cursor, "Telegraph")
		telegraphs = telegraphs + #tele
		cursor = K.logSize()
		if os.clock() - t0 > 90 and simOf(idW) then
			local boss = simOf(idW).boss
			boss.hp = math.min(boss.hp, 1)
		end
		for _, tr in ipairs(heroTrs) do
			drvTick(tr, { every = 1 })
			if #tele > 0 then
				bs.Command(tr.p, "Dash")
			end
		end
	end
	local resW = idW and w.find(idW)
	if T.check(resW ~= nil, "p3 raid: the full raid ends", string.format("%.0f s", os.clock() - t0)) then
		local won = resW.Reason == "BossDown"
		T.info("*full raid: " .. tostring(resW.Reason) .. " after " .. tostring(resW.Duration) .. " s")
		local consistent, sum = true, 0
		local detail = {}
		for i = 1, 3 do
			local uid = heroes[i].UserId
			local share = resW.Shares[uid] or 0
			sum = sum + share
			local tier = bc.RaidTier(share, won, "High")
			local rw = resW.Rewards[uid]
			local paid = tokens(heroes[i]) - before0[i]
			detail[#detail + 1] = string.format("%s %.2f %s", tostring(rw and rw.Tier), share, tostring(paid))
			if not rw or rw.Tier ~= tier.Id or rw.Tokens ~= tier.Tokens * doubled(rw) or paid ~= rw.Tokens or (won and not contains(resW.Winners, uid)) then
				consistent = false
			end
		end
		T.check(consistent and math.abs(sum - 1) < 0.01, "p3 raid: each fighter got the tier of their damage share (Tokens paid once)", table.concat(detail, " | "))
		T.eq(w.count(idW), 1, "p3 raid: BattleEnded once for the full raid")
		T.check(specials > 0 and telegraphs > 0, "p3 raid: the fighters' SPECIAL presses cast specials and the boss telegraphed its attacks",
			specials .. " specials, " .. telegraphs .. " telegraphs")
		local eventIds = {}
		for _, petId in ipairs(bc.EventPets()) do
			eventIds[petId] = true
		end
		if won and next(eventIds) ~= nil then
			local good, why = true, {}
			for i = 1, 3 do
				local h = heroes[i]
				local rw = resW.Rewards[h.UserId]
				local pet = rw and rw.EventPet
				local tier = bc.RaidTier(resW.Shares[h.UserId] or 0, true, "High")
				local prof = DS().GetProfile(h)
				local owned = pet and prof and (prof.Pets[pet] or 0) >= 1
				local marked = pet and record(h).EventPets and record(h).EventPets[pet] == true
				local gemsPaid = DS().GetGems(h) - gems0[i]
				if not (pet and eventIds[pet] and owned and marked and rw.Gems == tier.Gems and gemsPaid == tier.Gems) then
					good = false
					why[#why + 1] = tostring(pet) .. " owned " .. tostring(owned) .. " marked " .. tostring(marked) .. " gems " .. tostring(gemsPaid)
				end
			end
			T.check(good, "p3 raid: a winning tier's gem chance pays its Gems and its event-pet chance gives a new event pet (owned, in Battle.EventPets)",
				table.concat(why, " | "))
		else
			T.fail("p3 raid: the full raid ends in a win, so the drops are checked", tostring(resW.Reason))
		end
	end
	for i, tier in ipairs(bc.Raid.Tiers) do
		tier.GemChance, tier.EventPetChance = saved[i][1], saved[i][2]
	end
	K.flushErrors("p3 raid")
	w.stop()
	cleanup(heroes)
	loudReplication()
end)

----------------------------------------------------------------------------------------------------
-- scenario: exploit attempts
----------------------------------------------------------------------------------------------------
S.p3bs_exploits = scenario("p3bs_exploits", function()
	if not ready("p3bs_exploits") then
		return
	end
	quietReplication()
	local bs, data = BS(), DS()
	local w = watchEnded()
	local cmd = K.remoteFolder():FindFirstChild("BattleCommand")
	local reqR = K.remoteFolder():FindFirstChild("BattleRequest")
	local x = newPlayer("Hacker", MID)
	local y = newPlayer("Victim", ALT)
	local z = newPlayer("Bystander", STRONG)
	toArena(x, 3, 0)
	toArena(y, -3, 0)
	toArena(z, 0, 6)
	local errs0 = #Mock.Errors
	local teamBefore = table.concat(data.GetTeams(x).Presets[1], ",")
	local junk = { 0, -1, 1.5, 0 / 0, math.huge, "x", string.rep("y", 300), {}, { 1, 2 }, { 1, 2, 3 }, { x = 0 / 0, z = 1 }, { foo = "bar" }, true, Vector3.new(1, 2, 3) }
	for _, action in ipairs({ "Attack", "Element", "Special", "Dash", "Target", "Buff", "Swap", "Forfeit", "Retreat", 5, {}, string.rep("A", 100), "Teleport", "Move" }) do
		for _, arg in ipairs(junk) do
			Mock.FromClient(cmd, x, action, arg)
		end
		Mock.FromClient(cmd, x, action)
	end
	local requests = {
		{ "TeamSet", 0, { "cloudy_dragon" } }, { "TeamSet", 4, {} }, { "TeamSet", 1.5, {} }, { "TeamSet", "1", {} }, { "TeamSet", 1, "x" },
		{ "TeamSet", 1, { [9] = "cloudy_dragon" } }, { "TeamSet", 1, { 5 } }, { "TeamSet", 1, { {} } }, { "TeamSet", 1, { string.rep("k", 60) } },
		{ "TeamSet", 1, { "a", "b", "c", "d", "e", "f", "g", "h", "i" } }, { "TeamSelect", 0 }, { "TeamSelect", 9 }, { "TeamSelect", "2" },
		{ "Trial", 1 }, { "Ring", 0 / 0 }, { "Ring", {} }, { "Ring", "1" },
		{ "Challenge", nil }, { "Challenge", -1 }, { "Challenge", 1.5 }, { "Challenge", "id" }, { "Challenge", x.UserId }, { "Challenge", 123456789 },
		{ "ChallengeReply", nil, true }, { "ChallengeReply", y.UserId, "yes" }, { "ChallengeReply", "x", true }, { "ChallengeReply", y.UserId, nil },
		{ "Nope", 1 }, { 7, 1 }, { string.rep("Q", 40) },
	}
	for round = 1, 3 do
		for _, r in ipairs(requests) do
			Mock.FromClient(reqR, x, r[1], r[2], r[3])
		end
		advance(1.1)
	end
	advance(0.5)
	T.check(#Mock.Errors == errs0 and not bs.IsInBattle(x) and table.concat(data.GetTeams(x).Presets[1], ",") == teamBefore and data.GetTeams(x).Active == 1,
		"p3 exploits: junk through BattleCommand / BattleRequest breaks nothing, starts nothing and changes no team")
	-- a duel to poke at
	local mark = K.logSize()
	local ok, id = bs.StartDuel(x, y)
	if not T.check(ok == true, "p3 exploits: (precondition) a duel x vs y starts", tostring(id)) then
		w.stop()
		cleanup({ x, y, z })
		loudReplication()
		return
	end
	advance(0.5)
	local start = lastMsg(x, "Start", mark)
	local ownId, enemyId = nil, nil
	for _, u in ipairs(start and start.Units or {}) do
		if u.owner == x.UserId then
			ownId = ownId or u.id
		elseif u.owner == y.UserId then
			enemyId = enemyId or u.id
		end
	end
	local okA, whyA = bs.Command(x, "Attack", ownId)
	T.check(okA == false and whyA == "BadTarget", "p3 exploits: attacking one of your own units is refused", tostring(whyA))
	local okS9, whyS9 = bs.Command(x, "Buff", 9)
	local okS4, whyS4 = bs.Command(x, "Swap", 4)
	T.check(okS9 == false and whyS9 == "BadSlot" and okS4 == false and whyS4 == "BadSlot", "p3 exploits: a Buff / Swap for a slot you do not have (9, 4 with 3 pets) is refused")
	local okI, whyI = bs.Command(x, "Attack", 999)
	T.check(okI == false and whyI == "BadTarget", "p3 exploits: a unit id out of range is refused")
	T.check(bs.Command(x, "Target", enemyId) == true, "p3 exploits: locking an enemy unit works")
	local m2 = K.logSize()
	bs.Command(x, "Target", enemyId)
	advance(0.3)
	local orders = eventsOf(y, m2, "Order")
	local targetSeen, foreign = false, false
	for _, ev in ipairs(orders) do
		if ev.owner ~= x.UserId then
			foreign = true
		elseif ev.order == "Target" then
			targetSeen = true
		end
	end
	T.check(targetSeen and not foreign, "p3 exploits: a command only orders the caller's own team (Order owner = the caller)")
	-- outside the zone (still inside the arena)
	local padCF = K.root(x).CFrame
	toArena(x, 0, 0)
	local okZ, whyZ = bs.Command(x, "Attack")
	local m3 = K.logSize()
	Mock.FromClient(cmd, x, "Attack")
	advance(0.1)
	T.check(okZ == false and whyZ == "NotInZone" and toasted(x, "battle zone", m3), "p3 exploits: commands from outside the battle zone are refused (side toast)", tostring(whyZ))
	Mock.Teleport(x, padCF)
	advance(0.1)
	-- spam: 300 Target commands in one frame reach the sim at most 12 times (the cmd bucket; accepted Targets echo an Order)
	advance(1.0)
	local m4 = K.logSize()
	for _ = 1, 300 do
		Mock.FromClient(cmd, x, "Target", enemyId)
	end
	advance(0.3)
	local n = 0
	for _, ev in ipairs(eventsOf(x, m4, "Order")) do
		if ev.owner == x.UserId and ev.order == "Target" and not ev.rejected then
			n = n + 1
		end
	end
	T.check(n >= 1 and n <= 12, "p3 exploits: 300 commands in one frame reach the battle at most 12 times (token bucket)", n .. " orders")
	advance(0.4)
	-- two battles at once
	T.check(bs.EnterRaid(x) == false and bs.Queue(x) == false and bs.Challenge(x, z) == false and bs.StartDuel(x, z) == false and bs.StartRing(x, 1) == false,
		"p3 exploits: a player in a battle cannot start or join another (raid, queue, challenge, duel, ring)")
	-- the portal lock (canBattle)
	local v = newPlayer("Locked", WEAK)
	toArena(v, 0, 10)
	v:SetAttribute("PortalLocked", "Easy")
	local okP, whyP = bs.Queue(v)
	T.check(okP == false and type(whyP) == "string" and whyP:find("portal party") ~= nil, "p3 exploits: a player locked in a portal party cannot start a battle", tostring(whyP))
	v:SetAttribute("PortalLocked", nil)
	-- teleport trick: a duellist teleported out of the arena forfeits
	toLobby(y)
	advance(1.5)
	local r = w.find(id)
	T.check(r ~= nil and contains(r.Losers, y.UserId) and contains(r.Winners, x.UserId) and r.Forfeit == true,
		"p3 exploits: a duellist who leaves the arena (teleported away) forfeits; the other wins")
	-- an obby match during a battle loses it (a second duel x vs z)
	advance(4.6)
	toArena(x, 3, 0)
	toArena(z, -3, 0)
	local okZ2, idZ2 = bs.StartDuel(x, z)
	advance(0.3)
	z:SetAttribute("InMatch", true)
	-- the 2 Hz monitor drops z, the next 10 Hz tick ends the duel and sends End: wait two monitor ticks
	advance(1.2)
	local rz = idZ2 and w.find(idZ2)
	T.check(okZ2 and rz ~= nil and contains(rz.Losers, z.UserId) and contains(rz.Winners, x.UserId), "p3 exploits: a player pulled into an obby match loses the battle at once")
	z:SetAttribute("InMatch", false)
	advance(4.5)
	-- rewards once after the end
	local tx, ty = tokens(x), tokens(y)
	local trx = record(x).Trophies
	bs.Forfeit(x)
	Mock.FromClient(cmd, x, "Forfeit")
	Mock.FromClient(cmd, y, "Forfeit")
	Mock.FromClient(cmd, x, "Attack")
	advance(1)
	T.check(tokens(x) == tx and tokens(y) == ty and record(x).Trophies == trx and w.count(id) == 1,
		"p3 exploits: after the end, forfeits and commands pay or change nothing (BattleEnded once)")
	T.eq(#Mock.Errors, errs0, "p3 exploits: no script errors")
	K.flushErrors("p3 exploits")
	w.stop()
	cleanup({ x, y, z, v })
	loudReplication()
end)

----------------------------------------------------------------------------------------------------
-- scenario: bandwidth, snapshot rate, ranges, payload hygiene
----------------------------------------------------------------------------------------------------
S.p3bs_net = scenario("p3bs_net", function()
	if not ready("p3bs_net") then
		return
	end
	quietReplication()
	local bs = BS()
	local mark0 = K.logSize()
	local function rate(p, fromIndex, seconds)
		local bytes, snaps, first, last = 0, 0, nil, nil
		for _, e in ipairs(battleMsgs(p, fromIndex)) do
			bytes = bytes + bs.EstimateBytes(e.args[2]) + 4 + #tostring(e.args[1]) + #tostring(e.args[3] or "")
			if e.args[1] == "Snapshot" then
				snaps = snaps + 1
				first = first or e.time
				last = e.time
			end
		end
		local hz = 0
		if snaps > 1 and last > first then
			hz = (snaps - 1) / (last - first)
		end
		return bytes / seconds, hz
	end
	-- a duel (both play)
	local d1, d2 = newPlayer("NetDuel", MID), newPlayer("NetDuel", ALT)
	toArena(d1, 3, 0)
	toArena(d2, -3, 0)
	local mD = K.logSize()
	bs.StartDuel(d1, d2)
	advance(0.5)
	local m = K.logSize()
	drvPlay({ drvTracker(d1, mD), drvTracker(d2, mD) }, 5)
	local duelRate, duelHz = rate(d1, m, 5)
	-- an 8-player raid
	endAnyRaid(bs)
	local okR = bs.SetRaidBoss("shadow_hydra")
	local raiders, raidTrs = {}, {}
	local teams = { STRONG, MID, ALT, WEAK }
	for i = 1, 8 do
		raiders[i] = newPlayer("NetRaid", teams[(i - 1) % 4 + 1], 5)
		toArena(raiders[i], (i - 4) * 3, 8)
		raidTrs[i] = drvTracker(raiders[i])
		bs.EnterRaid(raiders[i])
	end
	local far = newPlayer("NetFar", WEAK)
	toLobby(far)
	advance(2)
	m = K.logSize()
	drvPlay(raidTrs, 10)
	local raidRate, raidHz = rate(raiders[1], m, 10)
	local status = bs.GetRaidStatus().Fights.Starter
	T.info(string.format("*BattleState traffic per client (estimated): duel %.1f KB/s, 8-player raid %.1f KB/s (%d teams)",
		duelRate / 1000, raidRate / 1000, status and status.Players or 0))
	T.check(duelRate > 0 and duelRate < 6000, "p3 net: a played duel stays under 6 KB/s per client", string.format("%.0f B/s", duelRate))
	T.check(okR and raidRate > 0 and raidRate < 6000, "p3 net: an 8-player boss raid with everyone playing stays under 6 KB/s per client (10.3)", string.format("%.0f B/s", raidRate))
	T.check(duelHz >= 9 and duelHz <= 11 and raidHz >= 9 and raidHz <= 11, "p3 net: participants get ~10 snapshots per second", string.format("duel %.1f, raid %.1f", duelHz, raidHz))
	T.check(#battleMsgs(far, mark0) == 0, "p3 net: a player far from every battle gets no battle traffic")
	local stats = bs.GetNetStats()
	local mine = stats and stats.Clients and stats.Clients[raiders[1].UserId]
	T.check(type(mine) == "table" and mine.Rate > 0 and stats.Max >= mine.Rate, "p3 net: GetNetStats reports bytes per second per client")
	-- payload hygiene over every BattleState message of this scenario
	local problems, lookProblems, checked = {}, {}, 0
	for i = mark0 + 1, K.logSize() do
		local e = Mock.RemoteLog[i]
		if e.remote == "BattleState" and checked < 4000 then
			checked = checked + 1
			for _, path in ipairs(badTables(e.args[2], tostring(e.args[1]))) do
				if path:find("%.look") then
					if #lookProblems < 3 then
						lookProblems[#lookProblems + 1] = path
					end
				elseif #problems < 5 then
					problems[#problems + 1] = path
				end
			end
		end
	end
	T.check(#problems == 0, "p3 net: BattleState payloads have no functions, NaN, sparse arrays or mixed tables (" .. checked .. " checked)", table.concat(problems, " | "))
	if #lookProblems > 0 then
		T.warn("p3 net: unit looks (catalog data) contain sparse / mixed tables: " .. table.concat(lookProblems, " | "))
	end
	bs.EndRaids("Ended")
	K.flushErrors("p3 net")
	local all = { d1, d2, far }
	for _, p in ipairs(raiders) do
		all[#all + 1] = p
	end
	cleanup(all)
	loudReplication()
end)

return S
