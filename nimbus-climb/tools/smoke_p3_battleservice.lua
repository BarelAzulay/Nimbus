-- smoke_p3_battleservice.lua: Phase 3 "BattleService" (ARCHITECTURE_V3.md "Phase 3 build contract": BattleService +
-- "Interfaces between the Phase 3 modules") on the booted server with 2-8 simulated players. Server world only (listed
-- in server_files of tools/smoke.py); the scenarios run before the Phase 2 care block (they advance the clock by several
-- minutes):
--   p3bs_contract  the module, its API, BattleEnded / BattleStarted created at module load, Init wired by Main (the
--                  BattleRequest remote answers), safe answers for nil players and without a raid
--   p3bs_trial     a full trial: refusals (away from the Trial Portal, locked levels), the pocket teleport, InBattle,
--                  the "Start" payload (zone CFrame + Size, slots, sides, names), ~10 Hz dense snapshots, the end, rewards
--                  exactly once (first clear: tokens + first-clear bonus, pet XP; a repeat pays the repeat amount), the
--                  battle record (TrialCleared, TrialBest), the return teleport to the portal, the pocket freed; a forfeit
--                  through the remote (a loss, nothing paid); a disconnect mid-trial; slipping off the pocket (put back) and
--                  a teleport away from it (the trial is lost)
--   p3bs_duel      challenge -> "Lobby" (Invites / Sent shapes) -> decline, expiry, accept (a challenge back is a yes);
--                  both duellists on the ring's pads, Start to both, a spectator in range gets the battle and the far
--                  player nothing; the end: trophies / tokens / XP / PvP counters once; a forfeit after 15 s (full win),
--                  an early forfeit (the winner gets no rewards), the pair limit (no trophies), a disconnect (the
--                  leaver's penalty is in the saved profile, the opponent wins)
--   p3bs_queue     the quick queue: Queue / Unqueue, "Lobby" Queued / Waiting, similar trophies pair at once, far apart
--                  only after the allowance grew, leaving the arena cancels
--   p3bs_raid      StartRaid / GetRaidStatus / JoinRaid (inside the arena, the join window) / LeaveRaid, the boss HP grows
--                  and shrinks per participant, a spectator becoming a fighter, a joiner who leaves the arena is
--                  removed, EndRaid (a timeout loss, rewards once, Double Rewards pushed), a raid nobody joined, and a
--                  full raid won by three active teams (tiers by damage share)
--   p3bs_exploits  junk remote arguments, commands for other units / bad slots / from spectators / from outside the zone,
--                  spam (token buckets, cooldowns), starting two battles, a duel player teleported out of the arena,
--                  an obby match during a battle, the portal lock, rewards once after the end
--   p3bs_net       bytes per second per client for a trial, a duel and an 8-player raid (BattleService.EstimateBytes of
--                  every BattleState payload), ~10 Hz snapshots, players far away get nothing, payload hygiene (no
--                  functions, NaN, sparse arrays or mixed tables), GetNetStats
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

local function toPortal(p)
	local info = arenaInfo()
	Mock.Teleport(p, CFrame.new(info.TrialPortal.Position + Vector3.new(0, 3, 6)))
	advance(0.05)
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

-- EventService's scheduler (when it is in the build) must not start a raid in the middle of these scenarios: while
-- they run, BattleService.StartRaid refuses (EventService waits and retries later); the tests call the real one
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

local function endAnyRaid(bs)
	if bs.GetRaidStatus() ~= nil then
		bs.EndRaid()
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

-- every scenario of this file: guarded, then the shared test switches are always put back (also after an abort), so
-- the scenarios of other files never inherit them
local function scenario(name, fn)
	local run = guarded(name, fn)
	return function(...)
		local ok = run(...)
		local bs = BS()
		if bs then
			releaseRaidSchedule(bs)
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
	for _, fn in ipairs({ "Init", "StartTrial", "Challenge", "StartRaid", "EndRaid", "GetBattle", "IsInBattle", "GetRaidStatus",
		"StartDuel", "ReplyChallenge", "Queue", "Unqueue", "JoinRaid", "LeaveRaid", "Command", "Forfeit", "SetDoubleRewards",
		"IsDoubleRewards", "GetNetStats", "EstimateBytes", "ListBattles", "StartRing", "KeysInBattle" }) do
		if type(bs[fn]) ~= "function" then
			missing[#missing + 1] = fn
		end
	end
	T.check(#missing == 0, "p3 bs: the contract API (StartTrial, Challenge, StartRaid / EndRaid, GetBattle, IsInBattle, GetRaidStatus, Phase 4 StartRing / KeysInBattle) and the extras exist", table.concat(missing, ", "))
	-- Phase 4: the mode names (BattleSim.Modes carries the Champion Ring too) and the safe answers of the new API
	local sim = req("shared/BattleSim")
	local modes = sim and sim.Modes or {}
	local modeSet = {}
	for k, v in pairs(modes) do
		modeSet[type(k) == "string" and k or v] = true
	end
	T.check(modeSet.Trial and modeSet.Duel and modeSet.Raid and modeSet.Ring, "p3 bs: the mode names are Trial / Duel / Raid / Ring (BattleSim.Modes)")
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
	T.check(bs.IsInBattle(nil) == false and bs.GetBattle(nil) == nil and bs.GetRaidStatus() == nil and bs.EndRaid() == false,
		"p3 bs: nil players and 'no raid' answer safely (IsInBattle false, GetBattle nil, GetRaidStatus nil, EndRaid false)")
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
-- scenario: a full trial, refusals, rewards once, the return, forfeits, disconnects, the pocket leash
----------------------------------------------------------------------------------------------------
S.p3bs_trial = scenario("p3bs_trial", function()
	if not ready("p3bs_trial") then
		return
	end
	local bs, data, bc = BS(), DS(), BC()
	local info = arenaInfo()
	local w = watchEnded()
	local p = newPlayer("Trialist", STRONG)
	-- Phase 4: the stored evolution stage and training ranks ride into the fight as the UnitStats extras (teamOf):
	-- the first pet is Evolved (stage 1) and trained in Physique rank 2, the second untouched
	local grew = data.MutateGrowth and data.MutateGrowth(p, function(g)
		g[STRONG[1]] = { Evo = 1, Physique = 2 }
	end)
	T.check(grew == true, "p3 trial: (setup) the first team pet is Evolved I with Physique rank 2 (DataService.MutateGrowth)")
	toLobby(p)
	local ok, why = bs.StartTrial(p, 1)
	T.check(ok == false and type(why) == "string" and why:find("Trial Portal") ~= nil, "p3 trial: refused away from the Trial Portal", tostring(why))
	toPortal(p)
	ok, why = bs.StartTrial(p, 2)
	T.check(ok == false and type(why) == "string" and why:find("Trial 1") ~= nil, "p3 trial: level 2 is locked until level 1 is cleared", tostring(why))
	local bad = {}
	for _, level in ipairs({ 0, 31, 1.5, -1, 0 / 0, math.huge, "1" }) do
		local okBad = bs.StartTrial(p, level)
		if okBad ~= false then
			bad[#bad + 1] = tostring(level)
		end
	end
	T.check(#bad == 0, "p3 trial: junk levels are refused (0, 31, 1.5, -1, nan, inf, '1')", table.concat(bad, ", "))

	local tokens0 = tokens(p)
	local mark = K.logSize()
	local id
	ok, id = bs.StartTrial(p, 1)
	if not T.check(ok == true and type(id) == "string", "p3 trial: StartTrial(1) near the portal starts a battle", tostring(id)) then
		w.stop()
		cleanup({ p })
		return
	end
	T.eq(p:GetAttribute("InBattle"), id, "p3 trial: the player attribute InBattle holds the battle id")
	T.check(bs.IsInBattle(p) and bs.GetBattle(p) and bs.GetBattle(p).Mode == "Trial" and bs.GetBattle(p).BattleId == id and bs.GetBattle(p).Level == 1,
		"p3 trial: IsInBattle / GetBattle report the trial")
	local start = lastMsg(p, "Start", mark)
	local pocketCF = start and start.Zone and start.Zone.CFrame
	T.check(type(start) == "table" and start.BattleId == id and start.Mode == "Trial" and typeof(pocketCF) == "CFrame" and typeof(start.Zone.Size) == "Vector3"
		and start.Zone.X == start.Zone.Size.X and start.Zone.Z == start.Zone.Size.Z and start.Side == 1 and start.Spectator == false,
		"p3 trial: 'Start' carries BattleId, Mode, Zone = { CFrame, Size (Vector3), X, Z }, Side 1, Spectator false")
	if type(start) == "table" then
		local slots, sides = {}, 0
		for _, u in ipairs(start.Units or {}) do
			if u.owner == p.UserId then
				slots[#slots + 1] = u.slot
			end
		end
		table.sort(slots)
		T.check(#slots == 3 and slots[1] == 1 and slots[3] == 3 and type(start.Sides) == "table" and contains(start.Sides[1], p.UserId) and #(start.Sides[2] or {}) >= 1
			and start.Names and start.Names[tostring(p.UserId)] == p.DisplayName and type(start.Trial) == "table" and start.Trial.Level == 1,
			"p3 trial: ...unit static info with the owner's slots 1-3, Sides (player vs npc), Names by userId string, Trial { Level }")
		sides = #(start.Units or {})
		T.check(sides >= 4, "p3 trial: ...both teams' units (" .. sides .. ": three pets and Trial 1's single handicapped NPC pet)")
	end
	if pocketCF then
		T.check(distanceToZone(p, pocketCF) < 40 and (K.root(p).Position - info.TrialPortal.Position).Magnitude > 500,
			"p3 trial: the player was teleported into the private pocket far out in the sky", tostring(K.root(p).Position))
	end
	ok, why = bs.StartTrial(p, 1)
	T.check(ok == false and type(why) == "string" and why:find("already") ~= nil, "p3 trial: one battle at a time (a second StartTrial is refused)", tostring(why))
	-- Phase 4: KeysInBattle = the team's keys while the trial runs; a home teleport is refused InBattle
	local inBattle = bs.KeysInBattle(p)
	local nKeys = 0
	for _ in pairs(inBattle) do
		nKeys = nKeys + 1
	end
	T.check(nKeys == 3 and inBattle[STRONG[1]] == true and inBattle[STRONG[2]] == true and inBattle[STRONG[3]] == true, "p3 trial: KeysInBattle(player) = the fighting team's keys", tostring(nKeys))
	local Ty = req("server/Services/TycoonService")
	if Ty and type(Ty.GoHome) == "function" then
		local okHome, whyHome = Ty.GoHome(p)
		T.check(okHome == false and type(whyHome) == "string" and whyHome:find("battle", 1, true) ~= nil and p:GetAttribute(K.config().Attr.HomePortal or "HomePortal") == nil,
			"p3 trial: GoHome (the home portal) is refused InBattle ('Finish your battle first!')", tostring(whyHome))
	else
		T.info("*TycoonService.GoHome not in this build: the InBattle refusal was skipped")
	end
	-- Phase 4: the evolved, trained pet fights with the UnitStats extras (evo in the static info, MaxHp x1.25 x1.10)
	if type(start) == "table" then
		local PetCatalog = req("shared/PetCatalog")
		local def = PetCatalog and PetCatalog.Get(STRONG[1])
		local level = data.GetPetLevel(p, STRONG[1]) or 1
		local plain = def and bc.UnitStats(def, level, "Normal")
		local grown = def and bc.UnitStats(def, level, "Normal", { Evo = 1, Train = { Physique = 2 } })
		-- the team's element synergy (Phase 3) multiplies every unit's HP the same way: expected = grown x HealthMult
		local synList = {}
		for i, key in ipairs(STRONG) do
			synList[i] = { Def = PetCatalog and PetCatalog.Get(key), Level = data.GetPetLevel(p, key) or 1, Tier = "Normal" }
		end
		local okSyn, syn = pcall(bc.SynergyBonus, synList)
		local healthMult = (okSyn and type(syn) == "table" and tonumber(syn.HealthMult)) or 1
		local wantHp = grown and math.floor(grown.MaxHp * healthMult + 0.5) or -1
		local u1, u2 = nil, nil
		for _, u in ipairs(start.Units or {}) do
			if u.owner == p.UserId and u.key == STRONG[1] then
				u1 = u
			elseif u.owner == p.UserId and u.key == STRONG[2] then
				u2 = u
			end
		end
		T.check(u1 and u2 and u1.evo == 1 and u2.evo == 0 and grown and plain and math.abs(u1.maxHp - wantHp) <= 1 and grown.MaxHp > plain.MaxHp * 1.3 and type(u1.xp) == "number" and type(u1.xpNext) == "number",
			"p3 trial: the evolved + trained pet's unit carries evo 1 and the boosted MaxHp (x1.25 x1.10, then the team synergy), the plain pet evo 0; own units carry xp / xpNext",
			u1 and ("evo " .. tostring(u1.evo) .. " hp " .. tostring(u1.maxHp) .. " vs " .. tostring(wantHp)) or "no unit")
	end
	-- snapshots at ~10 Hz, dense, with the battle id
	local m1 = K.logSize()
	advance(1.0)
	local snaps = battleMsgs(p, m1, "Snapshot")
	T.check(#snaps >= 8 and #snaps <= 12, "p3 trial: ~10 snapshots per second", #snaps .. " in 1 s")
	local dense, idsOk, tUp = true, true, true
	local lastT = -1
	for _, e in ipairs(snaps) do
		local s = e.args[2]
		if s.BattleId ~= id or e.args[3] ~= id then
			idsOk = false
		end
		-- the wire form: U is a flat dense array of numbers (BattleSim:SnapshotDelta; the client decodes it)
		local n = 0
		for _, v in pairs(s.U or {}) do
			n = n + 1
			if type(v) ~= "number" then
				dense = false
			end
		end
		if type(s.U) ~= "table" or n ~= #s.U or s.Units ~= nil then
			dense = false
		end
		if not (s.T > lastT) then
			tUp = false
		end
		lastT = s.T
	end
	T.check(dense and idsOk and tUp, "p3 trial: every snapshot has U as a dense number array (the wire form), the BattleId (also as the 3rd argument) and a rising T")
	-- the end
	local done = waitEnded(w, id, 130)
	local result = w.find(id)
	if not T.check(done and result ~= nil, "p3 trial: the trial ends (BattleEnded)") then
		w.stop()
		cleanup({ p })
		return
	end
	T.check(result.Mode == "Trial" and result.Level == 1 and contains(result.Winners, p.UserId) and #result.Losers == 0 and result.Forfeit == false
		and type(result.Damage) == "table" and result.RewardsPaid == true,
		"p3 trial: the result follows the contract { Mode, Winners = {userId}, Losers, Level, Damage, Forfeit }", tostring(result.Reason))
	T.eq(w.count(id), 1, "p3 trial: BattleEnded fired exactly once")
	local rw = result.Rewards and result.Rewards[p.UserId]
	local R = bc.TrialRewards(1, type(rw) == "table" and rw.Double == true)
	local expected = R.Tokens + R.FirstClear.Tokens
	T.check(type(rw) == "table" and rw.FirstClear == true and rw.Tokens == expected and rw.Xp == R.Xp and rw.Gems == R.FirstClear.Gems,
		"p3 trial: first clear pays TrialRewards(1).Tokens + FirstClear.Tokens and Xp per pet", rw and ("tokens " .. tostring(rw.Tokens) .. " xp " .. tostring(rw.Xp)) or "no rewards")
	T.eq(tokens(p) - tokens0, expected, "p3 trial: ...the token balance grew by exactly that")
	local level = data.GetPetLevel(p, STRONG[1])
	T.check(level > 1, "p3 trial: ...the team pets gained XP (level " .. tostring(level) .. ")")
	local endMsg = lastMsg(p, "End", mark)
	T.check(type(endMsg) == "table" and endMsg.BattleId == id and endMsg.Outcome == "Win" and endMsg.Won == true and type(endMsg.Rewards) == "table"
		and endMsg.Rewards.Tokens == expected and type(endMsg.Result) == "table" and type(endMsg.Result.Damage) == "table",
		"p3 trial: 'End' { BattleId, Result, Rewards, Outcome = Win } reached the player")
	if type(endMsg) == "table" and type(endMsg.Result) == "table" then
		local keysOk = true
		for k in pairs(endMsg.Result.Damage) do
			if type(k) ~= "string" then
				keysOk = false
			end
		end
		T.check(keysOk, "p3 trial: ...the public result's Damage is keyed by userId strings (remote-safe)")
	end
	local rec = record(p)
	T.check(type(rec.TrialCleared) == "table" and rec.TrialCleared[1] == true and (rec.TrialBest or 0) >= 1, "p3 trial: the battle record has TrialCleared[1] and TrialBest >= 1")
	T.eq(p:GetAttribute("InBattle"), id, "p3 trial: InBattle stays until the return teleport")
	advance(4.5)
	T.check(p:GetAttribute("InBattle") == nil and not bs.IsInBattle(p), "p3 trial: InBattle is cleared after the return")
	T.check((K.root(p).Position - info.ReturnCFrame.Position).Magnitude < 12, "p3 trial: the player is back in front of the Trial Portal (ArenaInfo.ReturnCFrame)", tostring(K.root(p).Position))
	local still = false
	for _, b in ipairs(bs.ListBattles()) do
		if b.BattleId == id then
			still = true
		end
	end
	local pockets = workspace:FindFirstChild("BattlePockets")
	T.check(not still and (pockets == nil or #pockets:GetChildren() == 0), "p3 trial: the battle is forgotten and the pocket freed (ArenaBuilder.FreePocket)")
	T.eq(tokens(p) - tokens0, expected, "p3 trial: nothing more was paid after the end (rewards exactly once)")

	-- a repeat clear pays the repeat amount only
	quietReplication()
	toPortal(p)
	local tokens1 = tokens(p)
	local ok2, id2 = bs.StartTrial(p, 1)
	waitEnded(w, id2, 130)
	local r2 = w.find(id2)
	local rw2 = r2 and r2.Rewards[p.UserId]
	local R2 = bc.TrialRewards(1, type(rw2) == "table" and rw2.Double == true)
	T.check(ok2 and rw2 and rw2.FirstClear == false and rw2.Tokens == R2.Tokens and tokens(p) - tokens1 == R2.Tokens,
		"p3 trial: a repeat clear pays TrialRewards(1).Tokens only (no second first-clear bonus)", rw2 and tostring(rw2.Tokens) or tostring(id2))
	advance(4.5)

	-- a forfeit through the remote: a loss, nothing paid
	toPortal(p)
	local tokens2 = tokens(p)
	local m2 = K.logSize()
	local ok3, id3 = bs.StartTrial(p, 2)
	T.check(ok3 == true, "p3 trial: level 2 is open after clearing level 1", tostring(id3))
	advance(0.5)
	Mock.FromClient(K.remoteFolder():FindFirstChild("BattleCommand"), p, "Forfeit")
	advance(0.5)
	local r3 = w.find(id3)
	local end3 = lastMsg(p, "End", m2)
	T.check(r3 ~= nil and r3.Forfeit == true and contains(r3.Losers, p.UserId) and #r3.Winners == 0 and end3 and end3.Outcome == "Loss",
		"p3 trial: BattleCommand('Forfeit') ends the trial as a loss (Forfeit = true)")
	T.check(tokens(p) == tokens2 and record(p).TrialCleared[2] ~= true, "p3 trial: ...nothing is paid and level 2 is not cleared")
	advance(4.5)
	T.check(p:GetAttribute("InBattle") == nil and (K.root(p).Position - info.ReturnCFrame.Position).Magnitude < 12, "p3 trial: ...and the player is back at the portal")

	-- slipping off the pocket puts the player back; a teleport away loses the trial
	toPortal(p)
	local ok4, id4 = bs.StartTrial(p, 2)
	local zoneCF = bs.GetBattle(p) and bs.GetBattle(p).Zone.CFrame
	if ok4 and zoneCF then
		Mock.Teleport(p, zoneCF * CFrame.new(10, -40, 0))
		advance(0.7)
		T.check(bs.IsInBattle(p) and (K.root(p).Position - zoneCF.Position).Magnitude < 40 and w.find(id4) == nil,
			"p3 trial: a player who slips off the pocket is put back on its spawn (the trial goes on)")
		toLobby(p)
		advance(1.5)
		local r4 = w.find(id4)
		T.check(r4 ~= nil and contains(r4.Losers, p.UserId) and not (r4.Rewards[p.UserId] and r4.Rewards[p.UserId].Tokens > 0),
			"p3 trial: a player teleported away from the pocket loses the trial (no reward)")
		advance(4.5)
		T.check(p:GetAttribute("InBattle") == nil, "p3 trial: ...and is free again")
	else
		T.fail("p3 trial: (precondition) a second level-2 trial starts", tostring(id4))
	end

	-- tier copies and fused hybrids fight with their own stats (PetKeys.DefOf + the copy's level and tier)
	local h = newPlayer("TrialTiers", nil)
	local hprof = data.GetProfile(h)
	local golden = STRONG[1] .. "@Golden"
	hprof.Tiers[STRONG[1]] = { Golden = 1 }
	hprof.Hybrids.bst1 = { Body = STRONG[2], Style = STRONG[3], Elements = {}, Name = "Testblend", Rarity = "Legendary", Tier = "Normal" }
	hprof.Pets[WEAK[1]] = 1
	hprof.PetLevels[golden] = { Level = 3, Xp = 0 }
	data.MarkDirty(h)
	local okT, whyT = data.SetTeam(h, 1, { golden, "hyb:bst1", WEAK[1] })
	toPortal(h)
	local mh = K.logSize()
	local okH, idH = bs.StartTrial(h, 1)
	local sh = lastMsg(h, "Start", mh)
	local gUnit, hUnit = nil, nil
	for _, u in ipairs(sh and sh.Units or {}) do
		if u.owner == h.UserId and u.key == golden then
			gUnit = u
		elseif u.owner == h.UserId and u.key == "hyb:bst1" then
			hUnit = u
		end
	end
	local plain = bc.UnitStats(STRONG[1], 3, "Normal")
	T.check(okT and okH and gUnit and gUnit.tier == "Golden" and gUnit.level == 3 and plain and gUnit.maxHp >= 1.4 * plain.MaxHp and hUnit and type(hUnit.look) == "table",
		"p3 trial: a Golden copy (its level and x1.5 stats) and a fused hybrid (its own look) fight in the team",
		gUnit and string.format("golden %s hp %s vs normal %.0f", tostring(gUnit.level), tostring(gUnit.maxHp), plain and plain.MaxHp or -1) or tostring(whyT or idH))
	if okH then
		bs.Forfeit(h)
		advance(4.6)
	end

	-- the fail-safe: when the end of a battle fails, nobody stays stuck (BattleService.Debug injects the failure)
	local f = newPlayer("TrialFail", STRONG)
	toPortal(f)
	bs.Debug = { FailEnd = 1 }
	local mf = K.logSize()
	local okF, idF = bs.StartTrial(f, 1)
	waitEnded(w, idF, 130)
	bs.Debug = nil
	local rf = w.find(idF)
	local endF = lastMsg(f, "End", mf)
	local pocketsF = workspace:FindFirstChild("BattlePockets")
	T.check(okF and rf ~= nil and rf.Reason == "Error" and w.count(idF) == 1 and endF and endF.Reason == "Error" and f:GetAttribute("InBattle") == nil
		and not bs.IsInBattle(f) and (K.root(f).Position - info.ReturnCFrame.Position).Magnitude < 12 and (pocketsF == nil or #pocketsF:GetChildren() == 0),
		"p3 trial: when the end of a battle fails, the fail-safe frees the player (back at the portal) and the pocket, says 'End' and fires BattleEnded once")
	K.flushWarnings("p3 trial", { "injected end failure" })

	-- a disconnect mid-trial: the battle ends once, the pocket is freed
	local q = newPlayer("TrialQuit", STRONG)
	toPortal(q)
	local ok5, id5 = bs.StartTrial(q, 1)
	advance(0.3)
	Mock.RemovePlayer(q)
	advance(0.5)
	local r5 = w.find(id5)
	T.check(ok5 and r5 ~= nil and w.count(id5) == 1 and contains(r5.Losers, q.UserId), "p3 trial: a disconnect mid-trial ends it as a loss (BattleEnded once)")
	advance(4.5)
	local left = false
	for _, b in ipairs(bs.ListBattles()) do
		if b.BattleId == id5 then
			left = true
		end
	end
	T.check(not left and (workspace:FindFirstChild("BattlePockets") == nil or #workspace.BattlePockets:GetChildren() == 0), "p3 trial: ...and its pocket is freed")
	K.flushErrors("p3 trial")
	w.stop()
	cleanup({ p })
	loudReplication()
end)

----------------------------------------------------------------------------------------------------
-- scenario: duels (invites, the ring, spectators, rewards, forfeits, the pair limit, a disconnect)
----------------------------------------------------------------------------------------------------
local function storedBattle(userId)
	local key = K.config().Tokens.DataStoreName .. "/u_" .. userId
	local rec = Mock.DataStore.Data[key]
	return type(rec) == "table" and rec.Battle or nil
end

-- keeps these players' teams RETREATing for `seconds` (a player team goes back to ATTACK by itself after
-- Damage.RetreatLock + RetreatAutoResume, so the order is given again every 2 s)
local function holdBack(bs, list, seconds)
	local left = seconds
	while left > 0 do
		for _, p in ipairs(list) do
			bs.Command(p, "Retreat")
		end
		local step = math.min(2, left)
		advance(step)
		left = left - step
	end
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
	-- a challenge back is a yes
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
	-- the end
	local mEnd = m4
	waitEnded(w, id, 130)
	local r = w.find(id)
	if T.check(r ~= nil and r.Mode == "Duel" and #r.Winners == 1 and #r.Losers == 1 and not r.Draw, "p3 duel: the duel ends with one winner and one loser", r and tostring(r.Reason) or "no end") then
		local winner = (r.Winners[1] == a.UserId) and a or b
		local loser = (winner == a) and b or a
		local rwW, rwL = r.Rewards[winner.UserId], r.Rewards[loser.UserId]
		T.check(rwW and rwW.Trophies == TR.Win and rwW.Tokens == TR.Tokens.Win * doubled(rwW) and rwW.Xp == TR.Xp.Win,
			"p3 duel: the winner gets Trophies.Win, Tokens.Win and Xp.Win", rwW and (rwW.Trophies .. " / " .. rwW.Tokens .. " / " .. rwW.Xp) or "none")
		T.check(rwL and rwL.Tokens == TR.Tokens.Loss * doubled(rwL) and rwL.Xp == TR.Xp.Loss and rwL.Trophies == 0,
			"p3 duel: the loser gets Tokens.Loss and Xp.Loss; trophies never go below 0", rwL and (rwL.Trophies .. " / " .. rwL.Tokens) or "none")
		local recW0 = winner == a and recA0 or recB0
		local recL0 = winner == a and recB0 or recA0
		T.check(record(winner).PvPWins == (recW0.PvPWins or 0) + 1 and record(loser).PvPLosses == (recL0.PvPLosses or 0) + 1 and record(winner).Trophies == TR.Win,
			"p3 duel: PvPWins / PvPLosses and the trophy total moved once")
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
	ok, id2 = bs.StartDuel(a, b)
	T.check(ok == true, "p3 duel: StartDuel(a, b) starts the next duel", tostring(id2))
	advance(0.3)
	holdBack(bs, { a }, 16) -- a holds back, b's team fights (a loser who dealt damage keeps the winner's rewards)
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
	advance(0.3)
	holdBack(bs, { a, b }, 2)
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
	holdBack(bs, { a }, 17)
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
	local okR = holdRaidSchedule(bs)("frost_wyrm")
	local m3 = K.logSize()
	local okJ = bs.JoinRaid(q5)
	local l6 = lastMsg(q5, "Lobby", m3)
	T.check(okR and okJ and l6 and l6.Queue.Queued == false and not bs.Unqueue(q5), "p3 queue: joining a raid takes the player out of the queue ('Lobby' Queued = false)")
	bs.EndRaid()
	releaseRaidSchedule(bs)
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
	-- hold the EventService schedule BEFORE ending a leftover raid: late in a full run the game clock can sit at a
	-- scheduled raid moment, and the schedule would open the next raid right away (the "no raid" check then sees it)
	local startRaid = holdRaidSchedule(bs)
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
	local okNo, whyNo = bs.JoinRaid(r1)
	T.check(bs.GetRaidStatus() == nil and okNo == false and type(whyNo) == "string", "p3 raid: no raid: GetRaidStatus nil, JoinRaid refused", tostring(whyNo))
	endAnyRaid(bs)
	T.check(startRaid("no_such_boss") == false, "p3 raid: an unknown boss is refused")
	local ok, raidId = startRaid("storm_titan")
	T.check(ok == true and type(raidId) == "string" and startRaid("lava_golem") == false, "p3 raid: StartRaid opens one raid at a time", tostring(raidId))
	local st = bs.GetRaidStatus()
	T.check(st and st.Active == true and st.Waiting == true and st.Joinable == true and st.BossId == "storm_titan" and st.Players == 0 and st.JoinEndsIn >= 59
		and st.JoinEndsIn <= 60 and st.BattleId == raidId and type(st.Name) == "string",
		"p3 raid: GetRaidStatus before anyone joined: { Active, Waiting, Joinable, BossId, Name, Players = 0, JoinEndsIn = 60 }")
	local okO, whyO = bs.JoinRaid(outsider)
	T.check(okO == false and type(whyO) == "string" and whyO:find("Battle Arena") ~= nil, "p3 raid: a player outside the arena cannot join", tostring(whyO))
	local mark = K.logSize()
	local okJ, idJ = bs.JoinRaid(r1)
	T.check(okJ == true and idJ == raidId and r1:GetAttribute("InBattle") == raidId, "p3 raid: JoinRaid inside the arena: the raid battle starts (InBattle = raid id)", tostring(idJ))
	local s1 = bs.GetRaidStatus()
	T.check(s1 and s1.Players == 1 and s1.MaxHp > 0 and s1.Hp == s1.MaxHp and s1.Waiting == false and s1.EndsIn > 300, "p3 raid: the boss HP is set for one team", s1 and (s1.Hp .. "/" .. s1.MaxHp) or "nil")
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
	bs.JoinRaid(r2)
	local s2 = bs.GetRaidStatus()
	T.check(s2.Players == 2 and s2.MaxHp > s1.MaxHp, "p3 raid: a second team raises the boss HP", s1.MaxHp .. " -> " .. s2.MaxHp)
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
	T.check(bs.JoinRaid(r2) == false, "p3 raid: joining twice is refused")
	advance(1.5)
	local spec = lastMsg(r3, "Start", m2)
	T.check(spec and spec.Spectator == true and spec.BattleId == raidId, "p3 raid: a player watching in the arena spectates the raid")
	local m3 = K.logSize()
	bs.JoinRaid(r3)
	advance(0.3)
	local st3 = lastMsg(r3, "Start", m3)
	T.check(st3 and st3.Spectator == false and st3.Side == 1 and bs.GetRaidStatus().Players == 3, "p3 raid: a spectator who joins gets a fresh 'Start' as a fighter")
	-- leaving
	local before = bs.GetRaidStatus().MaxHp
	local m4 = K.logSize()
	T.check(bs.LeaveRaid(r2) == true, "p3 raid: LeaveRaid")
	local e2 = lastMsg(r2, "End", m4)
	local s4 = bs.GetRaidStatus()
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
	local okR, whyR = bs.JoinRaid(r2)
	T.check(okR == false and type(whyR) == "string" and whyR:find("left") ~= nil, "p3 raid: a leaver cannot rejoin the same raid", tostring(whyR))
	toLobby(r3)
	advance(1.5)
	T.check(r3:GetAttribute("InBattle") == nil and bs.GetRaidStatus().Players == 1, "p3 raid: a fighter who leaves the arena is out of the raid")
	-- the join window
	local late = newPlayer("RaidLate", WEAK)
	toArena(late, 0, 8)
	advance(60)
	local okL, whyL = bs.JoinRaid(late)
	T.check(okL == false and type(whyL) == "string" and whyL:find("started") ~= nil, "p3 raid: JoinRaid is refused after the join window", tostring(whyL))
	-- EndRaid: the fighters still in it lose by timeout; rewards once; Double Rewards pushed by EventService
	bs.SetDoubleRewards(true, 600)
	T.check(bs.IsDoubleRewards() == true, "p3 raid: SetDoubleRewards(true) turns Double Rewards on")
	local tok1, tok2 = tokens(r1), tokens(r2)
	local raids0 = record(r1).Raids or 0
	T.check(bs.EndRaid() == true, "p3 raid: EndRaid ends the running raid")
	local res = w.find(raidId)
	T.check(res and res.Mode == "Raid" and res.BossId == "storm_titan" and contains(res.Losers, r1.UserId) and not contains(res.Losers, r2.UserId)
		and type(res.Damage) == "table" and (res.Damage[r1.UserId] or 0) > 0,
		"p3 raid: the result { Mode Raid, BossId, Losers = the fighters still in it, Damage = {[userId] = n} }")
	local loss = bc.RaidTier(1, false)
	local rw1 = res and res.Rewards[r1.UserId]
	T.check(rw1 and rw1.Tier == "Loss" and rw1.Tokens == loss.Tokens * 2 and tokens(r1) - tok1 == loss.Tokens * 2,
		"p3 raid: a failed raid pays the Loss tier, doubled during Double Rewards", rw1 and tostring(rw1.Tokens) or "none")
	T.check(res and res.Rewards[r2.UserId] == nil and tokens(r2) == tok2, "p3 raid: a player who left gets nothing")
	T.check(record(r1).Raids == raids0 + 1 and (record(r1).RaidBestDamage or 0) > 0, "p3 raid: Raids + 1 and RaidBestDamage in the battle record")
	T.check(bs.GetRaidStatus() == nil and bs.EndRaid() == false and w.count(raidId) == 1 and r1:GetAttribute("InBattle") == nil,
		"p3 raid: afterwards: no status, EndRaid false, BattleEnded once, InBattle cleared")
	bs.SetDoubleRewards(false)
	T.check(bs.IsDoubleRewards() == false, "p3 raid: SetDoubleRewards(false) turns it off")
	bs.SetDoubleRewards(nil)
	-- a raid nobody joined closes at the end of its join window
	endAnyRaid(bs)
	local okN, idN = startRaid("lava_golem")
	advance(61.5)
	local resN = idN and w.find(idN)
	T.check(okN and resN and resN.Reason == "NoPlayers" and #resN.Winners == 0 and #resN.Losers == 0 and bs.GetRaidStatus() == nil,
		"p3 raid: a raid nobody joined closes after the join window (BattleEnded, Reason NoPlayers)")
	cleanup({ r1, r2, r3, outsider, late })

	-- a whole raid with three active teams (specials, retreat from telegraphs): rewards follow the damage tiers
	endAnyRaid(bs)
	local heroes = {}
	local teams = { STRONG, MID, ALT }
	for i = 1, 3 do
		heroes[i] = newPlayer("Hero", teams[i], 20)
		toArena(heroes[i], i * 3 - 6, 2)
	end
	-- this raid's drops are certain (the tiers' GemChance / EventPetChance raised for the test, restored below)
	local saved = {}
	for i, tier in ipairs(bc.Raid.Tiers) do
		saved[i] = { tier.GemChance, tier.EventPetChance }
		tier.GemChance, tier.EventPetChance = 1, 1
	end
	local okW, idW = startRaid("storm_titan")
	for i = 1, 3 do
		bs.JoinRaid(heroes[i])
	end
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
		if #tele > 0 then
			for _, h in ipairs(heroes) do
				bs.Command(h, "Retreat")
			end
		end
		cursor = K.logSize()
		for _, h in ipairs(heroes) do
			bs.Command(h, "Attack")
			for slot = 1, 3 do
				bs.Command(h, "Special", slot)
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
			local tier = bc.RaidTier(share, won)
			local rw = resW.Rewards[uid]
			local paid = tokens(heroes[i]) - before0[i]
			detail[#detail + 1] = string.format("%s %.2f %s", tostring(rw and rw.Tier), share, tostring(paid))
			if not rw or rw.Tier ~= tier.Id or rw.Tokens ~= tier.Tokens * doubled(rw) or paid ~= rw.Tokens or (won and not contains(resW.Winners, uid)) then
				consistent = false
			end
		end
		T.check(consistent and math.abs(sum - 1) < 0.01, "p3 raid: each fighter got the tier of their damage share (Tokens paid once)", table.concat(detail, " | "))
		T.eq(w.count(idW), 1, "p3 raid: BattleEnded once for the full raid")
		T.check(specials > 0 and telegraphs > 0, "p3 raid: the fighters' SPECIAL commands cast specials and the boss telegraphed its attacks",
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
				local tier = bc.RaidTier(resW.Shares[h.UserId] or 0, true)
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
		elseif not won then
			T.info("*full raid lost: the event pet / gem drop check was skipped")
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
	local junk = { 0, -1, 1.5, 0 / 0, math.huge, "x", string.rep("y", 300), {}, { 1, 2 }, { foo = "bar" }, true, Vector3.new(1, 2, 3) }
	for _, action in ipairs({ "Attack", "Retreat", "Special", "Forfeit", 5, {}, string.rep("A", 100), "Teleport" }) do
		for _, arg in ipairs(junk) do
			Mock.FromClient(cmd, x, action, arg)
		end
		Mock.FromClient(cmd, x, action)
	end
	local requests = {
		{ "TeamSet", 0, { "cloudy_dragon" } }, { "TeamSet", 4, {} }, { "TeamSet", 1.5, {} }, { "TeamSet", "1", {} }, { "TeamSet", 1, "x" },
		{ "TeamSet", 1, { [9] = "cloudy_dragon" } }, { "TeamSet", 1, { 5 } }, { "TeamSet", 1, { {} } }, { "TeamSet", 1, { string.rep("k", 60) } },
		{ "TeamSet", 1, { "a", "b", "c", "d", "e", "f", "g", "h", "i" } }, { "TeamSelect", 0 }, { "TeamSelect", 9 }, { "TeamSelect", "2" },
		{ "Trial", nil }, { "Trial", 0 }, { "Trial", 31 }, { "Trial", 1.5 }, { "Trial", "1" }, { "Trial", 0 / 0 }, { "Trial", {} },
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
	advance(0.3)
	bs.Command(y, "Retreat") -- y's team holds back (the order is given again below: a player team resumes by itself)
	advance(0.2) -- (its Order event goes out before the checks below look for orders)
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
	T.check(okA == false and whyA == "BadTarget", "p3 exploits: focusing one of your own units is refused", tostring(whyA))
	local okS9, whyS9 = bs.Command(x, "Special", 9)
	local okS4, whyS4 = bs.Command(x, "Special", 4)
	T.check(okS9 == false and whyS9 == "BadSlot" and okS4 == false and whyS4 == "BadSlot", "p3 exploits: a special for a slot you do not have (9, 4 with 3 pets) is refused")
	local okI, whyI = bs.Command(x, "Attack", 999)
	T.check(okI == false and whyI == "BadTarget", "p3 exploits: a unit id out of range is refused")
	T.check(bs.Command(x, "Attack", enemyId) == true, "p3 exploits: focusing an enemy unit works")
	local m2 = K.logSize()
	bs.Command(x, "Retreat")
	advance(0.3)
	local orders = eventsOf(y, m2, "Order")
	local retreatSeen, foreign = false, false
	for _, ev in ipairs(orders) do
		if ev.owner ~= x.UserId then
			foreign = true
		elseif ev.order == "Retreat" then
			retreatSeen = true
		end
	end
	T.check(retreatSeen and not foreign, "p3 exploits: a Retreat only orders the caller's own team (Order owner = the caller)")
	advance(1.7)
	bs.Command(y, "Retreat")
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
	-- spam
	local m4 = K.logSize()
	for _ = 1, 300 do
		Mock.FromClient(cmd, x, "Attack")
	end
	advance(0.3)
	local n = 0
	for _, ev in ipairs(eventsOf(x, m4, "Order")) do
		if ev.owner == x.UserId then
			n = n + 1
		end
	end
	T.check(n >= 1 and n <= 11, "p3 exploits: 300 commands in one frame reach the battle at most ~10 times (token bucket)", n .. " orders")
	advance(0.4)
	bs.Command(x, "Retreat")
	bs.Command(y, "Retreat")
	-- two battles at once
	T.check(bs.StartTrial(x, 1) == false and bs.JoinRaid(x) == false and bs.Queue(x) == false and bs.Challenge(x, z) == false and bs.StartDuel(x, z) == false,
		"p3 exploits: a player in a battle cannot start or join another (trial, raid, queue, challenge, duel)")
	-- request spam: 50 Trial requests in one frame start one trial
	toPortal(z)
	for _ = 1, 50 do
		Mock.FromClient(reqR, z, "Trial", 1)
	end
	advance(0.3)
	local zTrials = 0
	for _, b in ipairs(bs.ListBattles()) do
		if b.Mode == "Trial" and contains(b.Players, z.UserId) then
			zTrials = zTrials + 1
		end
	end
	T.eq(zTrials, 1, "p3 exploits: 50 Trial requests in one frame start exactly one trial")
	-- an obby match during a battle loses it
	local zb = bs.GetBattle(z)
	z:SetAttribute("InMatch", true)
	advance(0.7)
	local rz = zb and w.find(zb.BattleId)
	T.check(rz ~= nil and contains(rz.Losers, z.UserId), "p3 exploits: a player pulled into an obby match loses the battle at once")
	z:SetAttribute("InMatch", false)
	advance(4.5)
	-- the portal lock
	local v = newPlayer("Locked", WEAK)
	toPortal(v)
	v:SetAttribute("PortalLocked", "Easy")
	local okP, whyP = bs.StartTrial(v, 1)
	T.check(okP == false and type(whyP) == "string" and whyP:find("portal party") ~= nil, "p3 exploits: a player locked in a portal party cannot start a trial", tostring(whyP))
	v:SetAttribute("PortalLocked", nil)
	-- teleport trick: a duellist teleported out of the arena forfeits
	toLobby(y)
	advance(1.5)
	local r = w.find(id)
	T.check(r ~= nil and contains(r.Losers, y.UserId) and contains(r.Winners, x.UserId) and r.Forfeit == true,
		"p3 exploits: a duellist who leaves the arena (teleported away) forfeits; the other wins")
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
	-- a trial
	local t1 = newPlayer("NetTrial", WEAK)
	toPortal(t1)
	bs.StartTrial(t1, 1)
	advance(0.5)
	local m = K.logSize()
	advance(5)
	local trialRate = rate(t1, m, 5)
	-- a duel
	local d1, d2 = newPlayer("NetDuel", MID), newPlayer("NetDuel", ALT)
	toArena(d1, 3, 0)
	toArena(d2, -3, 0)
	bs.StartDuel(d1, d2)
	advance(0.5)
	m = K.logSize()
	advance(5)
	local duelRate, duelHz = rate(d1, m, 5)
	-- an 8-player raid
	endAnyRaid(bs)
	local okR = holdRaidSchedule(bs)("shadow_hydra")
	local raiders = {}
	local teams = { STRONG, MID, ALT, WEAK }
	for i = 1, 8 do
		raiders[i] = newPlayer("NetRaid", teams[(i - 1) % 4 + 1], 5)
		toArena(raiders[i], (i - 4) * 3, 8)
		bs.JoinRaid(raiders[i])
	end
	local far = newPlayer("NetFar", WEAK)
	toLobby(far)
	advance(2)
	m = K.logSize()
	advance(10)
	local raidRate, raidHz = rate(raiders[1], m, 10)
	local status = bs.GetRaidStatus()
	T.info(string.format("*BattleState traffic per client (estimated): trial %.1f KB/s, duel %.1f KB/s, 8-player raid %.1f KB/s (%d teams)",
		trialRate / 1000, duelRate / 1000, raidRate / 1000, status and status.Players or 0))
	T.check(trialRate > 0 and trialRate < 8000, "p3 net: a trial stays under 8 KB/s per client", string.format("%.0f B/s", trialRate))
	T.check(duelRate > 0 and duelRate < 8000, "p3 net: a duel stays under 8 KB/s per client", string.format("%.0f B/s", duelRate))
	T.check(okR and raidRate > 0 and raidRate < 30000, "p3 net: an 8-player boss raid stays under 30 KB/s per client", string.format("%.0f B/s", raidRate))
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
	bs.EndRaid()
	K.flushErrors("p3 net")
	local all = { t1, d1, d2, far }
	for _, p in ipairs(raiders) do
		all[#all + 1] = p
	end
	cleanup(all)
	loudReplication()
end)

return S
