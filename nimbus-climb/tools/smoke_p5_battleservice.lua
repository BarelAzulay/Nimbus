-- smoke_p5_battleservice.lua: Phase 5 "BattleService" (ARCHITECTURE_V3.md "Phase 5 build contract" 4.4-4.6, 4.8, 10.3-10.5,
-- 12.1) on the booted server with simulated players whose CHARACTERS are the fighters' bodies (B1). Server world only
-- (server_files of tools/smoke.py); the scenarios run before the care block (they advance the clock by minutes).
--   p5svc_commands        the validation ladder: junk types through the remote break nothing, NaN / huge aims and bad
--                         slots / targets refused, the cmd bucket (12 / 8 per s), NotInZone + the throttled toasts
--                         (NotInZone / OutOfReach "Too far!" / Charging / Cooldown), every refusal echoes Order { rejected },
--                         a spectator cannot command, Element with an aim point, unknown actions (Retreat is gone)
--   p5svc_position        a character teleported across the floor: the server fighter walks at <= legal run x 1.25; a
--                         gap > Leash 10 for LeashSeconds 3 = a leaver in a duel / a RemoveTeam in a raid; Start.Team.Speed
--                         = Fighter.SpeedsOf(MoveSpeed); Speed events on Swap
--   p5svc_position_legit  mochi_slime L1 and stormfang L50 replay lead-fix/leash_fix.py: random targets at exactly
--                         RunOf(WalkOf(MoveSpeed)) with a 200 ms feed delay and the r 14 circle, 20 s each: zero leashes;
--                         every ATTACK on a target within the server fighter's reach is never OutOfReach; a straight run-off
--                         past the zone edge IS leashed after ~3 s
--   p5svc_duel_fair       Duel.PowerGap 2 (practice beyond it: nothing paid, Practice in the invite), the queue's power
--                         band, MaxHit 0.6 in duels, a passive duel ends at 120 s (no overtime: DoubleKoByDamage / Draw),
--                         a played duel pays once, a leaver loses
--   p5svc_raid            16 fighters + the boss: BossHp(bossId, teams) with ExpectedDps, ~25 units, every client under
--                         6 KB/s (p5battle_net16), a leaver removed, tiers paid once at the end
--   p5svc_ring            rounds 1-3 won by ONE level-10 pet pressing ATTACK once per second (moving toward the champion;
--                         HUD cleanup Task 4: no heal between rounds, plain level-1 champions), XP once per round, Start.Team / Ring info, the loss third on the natural end
--   p5svc_encounter       the encounter API with NO run provider (KeysInBattle / canBattle work), OpenEncounter 1 and 4
--                         teams with KeepInBattle (the InBattle attribute untouched on add, release, leave, force release),
--                         SpawnWave + Wave events, OnWave / OnBossHp / OnDown / OnLeave, EncounterStatus, FinishEncounter
--                         idempotent, "End" with Rewards.Dungeon, BattleEnded (Mode Dungeon) BEFORE OnEnd, Fighters by the
--                         5% share (a 0-damage team dropped, a solo 1-damage team kept), RemoveEncounterTeam mid-fight, a KO
--                         wipe, a Timeout, erroring callbacks pcall-ed, Forfeit refused ("Use LEAVE"), the 10 s fail-safe,
--                         forceRelease (Debug.FailEnd), SetRunProvider -> raid / duel / ring refused "Finish your dungeon run
--                         first" (and with the "D" attribute alone), nothing paid by BattleService
--   p5svc_shutdown        Shutdown() voids a duel and a ring round, pays the raid shares, ends the encounter "Shutdown";
--                         nothing twice; SetClosing(false) reopens
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
local ALLOWED_WARNINGS = { "[BattleService]", "[DataService]", "[TycoonService]", "[PetCareService]", "[EventService]" }

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
local function Sim()
	return req("shared/BattleSim")
end
local function TS()
	return req("server/Services/TycoonService")
end
local function PC()
	return req("shared/PetCatalog")
end

local function arenaInfo()
	local ab = AB()
	return ab and ab.GetInfo and ab.GetInfo() or nil
end

local function ready(label)
	if not K.needBoot() then
		return false
	end
	if not BS() or not Sim() or not BC() then
		T.fail(label .. ": skipped, BattleService / BattleSim / BattleCatalog did not load")
		return false
	end
	if not arenaInfo() then
		T.fail(label .. ": skipped, ArenaBuilder.GetInfo() returned nothing (no arena in this build)")
		return false
	end
	return true
end

-- a player with a battle team (pets owned, team preset 1 = the first 3); `level` sets every pet's level
local function newPlayer(prefix, pets, level)
	seq = seq + 1
	local p = Mock.AddPlayer(prefix .. seq, 967000 + seq)
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

local function toasts(p, fromIndex)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, fromIndex or 0)) do
		out[#out + 1] = tostring(e.args[1])
	end
	return out
end

local function toasted(p, needle, fromIndex)
	local n = 0
	for _, text in ipairs(toasts(p, fromIndex)) do
		if text:find(needle, 1, true) then
			n = n + 1
		end
	end
	return n > 0, n
end

local function watchEnded()
	local list = {}
	local conn = BS().BattleEnded:Connect(function(id, result)
		list[#list + 1] = { id = id, result = result, at = Mock.Clock.now }
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
		at = function(id)
			for _, e in ipairs(list) do
				if e.id == id then
					return e.at
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

local function contains(list, value)
	for _, v in ipairs(type(list) == "table" and list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

local function count(t)
	local n = 0
	for _ in pairs(type(t) == "table" and t or {}) do
		n = n + 1
	end
	return n
end

local function tokens(p)
	return DS().GetTokens(p)
end

local function cash(p)
	local DSv = DS()
	return (DSv.GetCash and DSv.GetCash(p)) or 0
end

local function totalXp(p, key)
	local level, xp = DS().GetPetLevel(p, key)
	local Cat = req("shared/TycoonCatalog")
	local total = xp or 0
	for l = 1, (level or 1) - 1 do
		total = total + Cat.XpToNext(l)
	end
	return total
end

-- EventService's scheduler must not open a raid in the middle of these scenarios
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

local function endAnyRaid(bs)
	if bs.GetRaidStatus() ~= nil then
		bs.EndRaid()
		advance(0.2)
	end
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

local function cleanup(list)
	local bs = BS()
	for _, p in ipairs(list) do
		if p.Parent and bs and bs.IsInBattle(p) then
			bs.Forfeit(p)
		end
	end
	advance(0.3)
	K.removePlayers(list)
	advance(5) -- rings / pockets come free
end

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
			if bs.SetClosing then
				bs.SetClosing(false)
			end
			if bs.SetRunProvider then
				-- give the booted game its real provider back (DungeonService.Init set it; later scenarios rely on it)
				local dgs = req("server/Services/DungeonService")
				if dgs and type(dgs.KeysInRun) == "function" and type(dgs.GetRun) == "function" then
					bs.SetRunProvider({ KeysInRun = dgs.KeysInRun, GetRun = dgs.GetRun })
				else
					bs.SetRunProvider(nil)
				end
			end
		end
		loudReplication()
		return ok
	end
end

----------------------------------------------------------------------------------------------------
-- The client-side picture of a battle (what BattleController decodes) and a driver that plays the fighter: the
-- character walks toward the nearest enemy at the legal run speed and presses ATTACK.
----------------------------------------------------------------------------------------------------
local DOWN = 5
local BENCHED = 3

local function tracker(p)
	return { p = p, cursor = K.logSize(), static = {}, units = {}, zone = nil, side = nil, fighter = nil, id = nil, start = nil, ends = {}, events = {}, speed = nil }
end

-- consumes the player's BattleState messages since the last pump
local function pump(tr)
	local log = Mock.RemoteLog
	local uid = tr.p.UserId
	for i = tr.cursor + 1, #log do
		local e = log[i]
		if e.remote == "BattleState" and e.kind == "client" and e.userId == uid then
			local kind, payload = e.args[1], e.args[2]
			if kind == "Start" and type(payload) == "table" and payload.Spectator ~= true then
				tr.start = payload
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

-- the nearest living enemy unit (id, record, static) from the server fighter's position
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

-- zone-local x, z of the character
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

-- moves the character toward (tx, tz) by at most `step` studs; -> the distance left
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

-- one 0.1 s tick of a playing fighter: walk toward the nearest enemy (stop inside reach) and press ATTACK (opts.attack
-- false = stand still and watch; opts.dt the tick)
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
		local fx, fz = myPos(tr)
		if opts.move ~= false and fx then
			-- walk toward the enemy, stopping a stud inside the reach measured from the server fighter
			if dist > reach - 1 then
				moveChar(tr, u.x, u.z, run * dt)
			end
		end
		tr.ticks = (tr.ticks or 0) + 1
		local every = opts.every or 3 -- ticks between ATTACK presses (3 = a frantic ~3 per second)
		if opts.attack ~= false and tr.ticks % every == 0 then
			local ok, why = bs.Command(tr.p, "Attack", id)
			tr.lastAttack = { ok = ok, why = why, dist = dist, reach = reach }
			if opts.onAttack then
				opts.onAttack(ok, why, dist, reach)
			end
		end
		if opts.kit and tr.ticks % 10 == 0 then
			bs.Command(tr.p, "Element")
			bs.Command(tr.p, "Special")
		end
	end
	return id
end

-- plays until the battle ends (a non-spectator End for the tracked id) or `seconds` pass; -> the End payload | nil
local function playUntilEnd(tr, seconds, opts)
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < seconds do
		advance(0.1)
		playTick(tr, opts)
		for _, e in ipairs(tr.ends) do
			if e.BattleId == tr.id then
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

----------------------------------------------------------------------------------------------------
-- Encounter fixtures: a zone part far out in the sky, a spec with recording callbacks
----------------------------------------------------------------------------------------------------
local zoneSeq = 0
-- the BattleService battle record of a battle id (white-box, tests only: the service's St is an upvalue of IsInBattle)
-- -> b (b.Sim = the BattleSim, b.Parts[userId]) | nil
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

-- wave 6: every pet fights any enemy in the fight area by itself; a test that needs a pet that only FOLLOWs its character
-- holds the engage rule off (white-box: the sim team's noEngage), and a duellist the podium lock holds is let go
local function holdEngage(battleId, userId)
	local b = battleOf(battleId)
	local team = b and b.Sim and b.Sim.teamByOwner and b.Sim.teamByOwner[userId]
	if team then
		team.noEngage = true
	end
	return team ~= nil
end

local function freePodium(p)
	local podium = req("server/Services/Podium")
	if podium then
		podium.Release(p)
	end
end

-- dungeon fixes (4): fighters auto-attack; a test that needs a PASSIVE player holds every pet's swing (white-box)
local function holdAttacks(battleId, userId)
	local b = battleOf(battleId)
	local team = b and b.Sim and b.Sim.teamByOwner and b.Sim.teamByOwner[userId]
	for _, u in ipairs(team and team.units or {}) do
		u.nextAttack = math.huge
	end
	return team ~= nil
end

local function makeZone(size)
	zoneSeq = zoneSeq + 1
	local part = Instance.new("Part")
	part.Name = "NC_BattleZone"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(size or 44, 2, size or 44)
	part.CFrame = CFrame.new(3000 + zoneSeq * 200, 600, -2500)
	part:SetAttribute("Mode", "Dungeon")
	part.Parent = workspace
	return part
end

-- a spec whose callbacks record every call: calls.OnEnd = { { id, result }... } etc.
local function encounterSpec(zone, players, extra)
	local calls = { OnEnd = {}, OnWave = {}, OnBossHp = {}, OnDown = {}, OnLeave = {} }
	local spec = {
		Mode = "Dungeon",
		Zone = zone,
		Seed = 4242,
		TimeLimit = 120,
		Label = "test",
		Teams = {},
		Extra = extra or { Floor = 3, Room = 2, Wave = 1, Waves = 2, Name = "Test Room" },
		KeepInBattle = true,
	}
	for _, p in ipairs(players) do
		spec.Teams[#spec.Teams + 1] = { Player = p }
	end
	for name in pairs(calls) do
		spec[name] = function(...)
			calls[name][#calls[name] + 1] = { ... }
		end
	end
	return spec, calls
end

-- places every player on the zone (spread along x), -> nothing
local function placeOnZone(zone, players)
	for i, p in ipairs(players) do
		Mock.Teleport(p, zone.CFrame * CFrame.new((i - 1) * 4 - 6, 3, -14))
	end
	advance(0.05)
end

local function wave(list)
	local out = {}
	for i, e in ipairs(list) do
		out[i] = { PetId = e[1], Level = e[2] or 1, Handicap = e[3], Boss = e[4] }
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- p5svc_commands
----------------------------------------------------------------------------------------------------
S.p5svc_commands = scenario("p5svc_commands", function()
	if not ready("p5svc_commands") then
		return
	end
	quietReplication()
	local bs, data = BS(), DS()
	local w = watchEnded()
	local cmd = K.remoteFolder():FindFirstChild("BattleCommand")
	local x = newPlayer("CmdX", MID, 10)
	local y = newPlayer("CmdY", ALT, 10)
	local z = newPlayer("CmdSpec", STRONG)
	toArena(x, 3, 0)
	toArena(y, -3, 0)
	toArena(z, 0, 6)
	local errs0 = #Mock.Errors
	local teamBefore = table.concat(data.GetTeams(x).Presets[1], ",")
	-- junk before any battle: every action with every junk argument, through the remote
	local junk = { 0, -1, 1.5, 0 / 0, math.huge, -math.huge, "x", string.rep("y", 300), {}, { 1, 2 }, { 1, 2, 3 }, { x = 0 / 0, z = 1 }, { x = 1e300, z = -1e300 },
		{ foo = "bar" }, { 1, "2" }, true, Vector3.new(1, 2, 3), CFrame.new() }
	local actions = { "Attack", "Element", "Special", "Dash", "Target", "Buff", "Swap", "Forfeit", "Retreat", 5, {}, string.rep("A", 100), "Teleport", "Move" }
	for _, action in ipairs(actions) do
		for _, arg in ipairs(junk) do
			Mock.FromClient(cmd, x, action, arg)
		end
		Mock.FromClient(cmd, x, action)
	end
	advance(0.5)
	T.check(#Mock.Errors == errs0 and not bs.IsInBattle(x) and table.concat(data.GetTeams(x).Presets[1], ",") == teamBefore,
		"p5 cmd: junk through BattleCommand before a battle breaks nothing and starts nothing")
	T.check(bs.Command(x, "Attack") == false and select(2, bs.Command(x, "Attack")) == "NoBattle", "p5 cmd: Command without a battle -> NoBattle")
	local okR, whyR = bs.Command(x, "Retreat")
	T.check(okR == false and whyR == "UnknownAction", "p5 cmd: 'Retreat' is gone (UnknownAction)", tostring(whyR))

	-- a duel to poke at: x on side 1, y on side 2 (both on their pads, outside the floor but inside the zone margin)
	local mark = K.logSize()
	local ok, id = bs.StartDuel(x, y)
	if not T.check(ok == true, "p5 cmd: (precondition) a duel x vs y starts", tostring(id)) then
		w.stop()
		cleanup({ x, y, z })
		return
	end
	advance(0.3)
	holdEngage(id, x.UserId) -- (the command ladder is measured here; wave 6 pets would fight on their own)
	holdEngage(id, y.UserId)
	local tx = tracker(x)
	tx.cursor = mark
	pump(tx)
	T.check(tx.start and tx.start.Mode == "Duel" and type(tx.start.Team) == "table" and type(tx.start.Team.Fighter) == "number" and #tx.start.Team.Bench == 2
		and tx.start.Team.Lives == 3 and type(tx.start.Team.Speed) == "table" and type(tx.start.Team.Speed.Walk) == "number" and type(tx.start.Team.Cooldowns) == "table",
		"p5 cmd: 'Start'.Team = { Fighter, Bench (2), Lives 3, Speed { Walk, Run }, Cooldowns }", tx.start and K.plainText and K.plainText(tx.start.Team) or "")
	-- the same junk during the battle: nothing breaks, the team is intact
	for _, action in ipairs(actions) do
		for _, arg in ipairs(junk) do
			Mock.FromClient(cmd, x, action, arg)
		end
	end
	advance(1.5)
	T.check(#Mock.Errors == errs0 and bs.IsInBattle(x) and bs.IsInBattle(y), "p5 cmd: junk during a battle breaks nothing (both still in)")
	-- Charging: a SPECIAL with an empty meter (2 s in: the meter is at ~12 of 100; the first refusal toast of this player)
	local m4 = K.logSize()
	local okS, whyS, meterS = bs.Command(x, "Special")
	Mock.FromClient(cmd, x, "Special")
	advance(0.1)
	T.check(okS == false and whyS == "Charging" and toasted(x, "charging", m4), "p5 cmd: SPECIAL with an empty meter -> Charging + a toast", tostring(whyS) .. " " .. tostring(meterS))
	-- the ladder's direct refusals
	local ownId, enemyId = nil, nil
	for _, u in ipairs(tx.start.Units or {}) do
		if u.owner == x.UserId and u.slot == 1 then
			ownId = u.id
		elseif u.owner == y.UserId and u.slot == 1 then
			enemyId = u.id
		end
	end
	local okA, whyA = bs.Command(x, "Attack", ownId)
	T.check(okA == false and whyA == "BadTarget", "p5 cmd: attacking your own unit is refused (BadTarget)", tostring(whyA))
	local okT9, whyT9 = bs.Command(x, "Target", 999)
	T.check(okT9 == false and whyT9 == "BadTarget", "p5 cmd: a unit id out of range is refused (BadTarget)", tostring(whyT9))
	local okB1, whyB1 = bs.Command(x, "Buff", 1)
	local okB4, whyB4 = bs.Command(x, "Swap", 4)
	local okBn, whyBn = bs.Command(x, "Buff")
	T.check(okB1 == false and whyB1 == "BadSlot" and okB4 == false and whyB4 == "BadSlot" and okBn == false and whyBn == "BadSlot",
		"p5 cmd: Buff / Swap take a BENCHED team slot 1..3 only (BadSlot for the fighter's own slot 1, slot 4, nil)", tostring(whyB1) .. " " .. tostring(whyB4) .. " " .. tostring(whyBn))
	local okE, whyE = bs.Command(x, "Element", { x = 0 / 0, z = 0 })
	local okE2, whyE2 = bs.Command(x, "Element", { x = 1e9, z = 0 })
	T.check(okE == false and whyE == "BadPoint" and okE2 == false and whyE2 == "BadPoint", "p5 cmd: a NaN / huge aim point is refused (BadPoint)", tostring(whyE) .. " " .. tostring(whyE2))
	T.check(select(2, bs.Command(x, "Attack", 1.5)) == "BadTarget" and select(2, bs.Command(x, "Nope")) == "UnknownAction" and select(2, bs.Command(x, string.rep("A", 20))) == "UnknownAction",
		"p5 cmd: a fractional id -> BadTarget, unknown / long actions -> UnknownAction")
	-- every refusal echoes Order { rejected } (the sim's refusals and the ladder's own; one echo per step)
	advance(0.3)
	local m2 = K.logSize()
	-- dungeon fixes (4): ATTACK directs the auto-attacking pet: a far enemy is LOCKED (accepted, extra "OutOfReach")
	local okFar, lockFar, extraFar = bs.Command(x, "Attack", enemyId) -- y is on the far pad
	bs.Command(x, "Attack", ownId) -- the sim refuses it: BadTarget
	advance(0.3)
	local rejected, directed = {}, false
	for _, ev in ipairs(eventsOf(x, m2, "Order")) do
		if ev.owner == x.UserId and ev.rejected then
			rejected[tostring(ev.rejected)] = true
		elseif ev.owner == x.UserId and ev.order == "Attack" and ev.target == enemyId then
			directed = true
		end
	end
	T.check(okFar == true and lockFar == enemyId and extraFar == "OutOfReach" and directed, "p5 cmd: ATTACK on a far enemy locks it (true, id, OutOfReach) and echoes Order { order = Attack, target }", tostring(okFar) .. " " .. tostring(extraFar))
	T.check(rejected.BadTarget == true, "p5 cmd: a refused command is echoed by the sim with Order { rejected = BadTarget }", table.concat((function()
		local l = {}
		for k in pairs(rejected) do
			l[#l + 1] = k
		end
		return l
	end)(), ","))
	-- the toasts: OutOfReach "Too far!" once per 3 s through the remote (the refusal toasts share one 3 s throttle)
	advance(3.1)
	local m3 = K.logSize()
	for _ = 1, 5 do
		Mock.FromClient(cmd, x, "Attack", enemyId)
		advance(0.15)
	end
	local hadFar, nFar = toasted(x, "Too far", m3)
	T.check(hadFar and nFar == 1, "p5 cmd: 'Too far!' toast once per 3 s (5 far ATTACK orders in 0.75 s -> 1 toast)", tostring(nFar))
	advance(3.2)
	Mock.FromClient(cmd, x, "Attack", enemyId)
	advance(0.1)
	local _, nFar2 = toasted(x, "Too far", m3)
	T.check(nFar2 == 2, "p5 cmd: ...and again after 3 s", tostring(nFar2))
	-- Dash: accepted once, then Cooldown with the seconds left (toast "Not ready")
	advance(3.1)
	local m5 = K.logSize()
	local okD = bs.Command(x, "Dash")
	local okD2, whyD2, extraD = bs.Command(x, "Dash")
	Mock.FromClient(cmd, x, "Dash")
	advance(0.1)
	T.check(okD == true and okD2 == false and whyD2 == "Cooldown" and type(extraD) == "number" and extraD > 0 and toasted(x, "Not ready", m5),
		"p5 cmd: Dash accepted, a second Dash -> Cooldown with the seconds left + a 'Not ready' toast", tostring(whyD2) .. " " .. tostring(extraD))
	local dashEv = eventsOf(x, m5, "Dash")
	T.check(#dashEv >= 1, "p5 cmd: ...the Dash event reached the client")
	-- Element with an aim point is accepted (cooldown afterwards)
	advance(3.1)
	local m6 = K.logSize()
	local okEl, whyEl = bs.Command(x, "Element", { x = 0, z = 10 })
	local okEl2, whyEl2 = bs.Command(x, "Element", { 0, 10 })
	advance(0.2)
	T.check(okEl == true and #eventsOf(x, m6, "Element") >= 1 and okEl2 == false and whyEl2 == "Cooldown",
		"p5 cmd: Element toward an aim point is accepted (Element event), the next one is on cooldown", tostring(whyEl) .. " / " .. tostring(whyEl2))
	-- the cmd bucket: 300 Target commands in one frame reach the sim at most 12 times (accepted Targets echo an Order)
	advance(1.0)
	local m7 = K.logSize()
	for _ = 1, 300 do
		Mock.FromClient(cmd, x, "Target", enemyId)
	end
	advance(0.3)
	local n = 0
	for _, ev in ipairs(eventsOf(x, m7, "Order")) do
		if ev.owner == x.UserId and ev.order == "Target" and not ev.rejected then
			n = n + 1
		end
	end
	T.check(n >= 1 and n <= 12, "p5 cmd: 300 commands in one frame reach the sim at most 12 times (bucket burst 12)", n .. " accepted Targets")
	advance(2.0)
	-- the refill: 8 per second (after 2 s the bucket is full again: 12 more land, not 20)
	local m8 = K.logSize()
	for _ = 1, 40 do
		Mock.FromClient(cmd, x, "Target", enemyId)
	end
	advance(0.3)
	local n2 = 0
	for _, ev in ipairs(eventsOf(x, m8, "Order")) do
		if ev.owner == x.UserId and ev.order == "Target" and not ev.rejected then
			n2 = n2 + 1
		end
	end
	T.check(n2 >= 8 and n2 <= 12, "p5 cmd: ...the bucket refills at 8 / s (full again after 2 s)", n2 .. " accepted")
	-- a spectator cannot command; outside the zone: NotInZone + toast + the Order echo
	advance(2.2)
	local okC, whyC = bs.Command(z, "Attack")
	T.check(okC == false and whyC == "NoBattle", "p5 cmd: a spectator cannot command anything", tostring(whyC))
	local padCF = K.root(x).CFrame
	toArena(x, 0, 0)
	local m9 = K.logSize()
	local okZ, whyZ = bs.Command(x, "Attack")
	for _ = 1, 4 do
		Mock.FromClient(cmd, x, "Attack")
		advance(0.1)
	end
	local hadZone, nZone = toasted(x, "battle zone", m9)
	local echo = false
	for _, ev in ipairs(eventsOf(x, m9, "Order")) do
		if ev.owner == x.UserId and ev.rejected == "NotInZone" then
			echo = true
		end
	end
	T.check(okZ == false and whyZ == "NotInZone" and hadZone and nZone == 1 and echo,
		"p5 cmd: commands from outside the zone are refused (NotInZone), one toast per 3 s, Order { rejected = NotInZone } echoed", tostring(whyZ) .. " toasts " .. tostring(nZone))
	Mock.Teleport(x, padCF)
	advance(0.1)
	-- W5 battle-dungeon-4: after Swap(2) the ORIGINAL fighter sits on the bench as team slot 1 (the client sends u.slot):
	-- Buff(1) and Swap(1) pass the ladder (the sim decides), so the benched original can buff and come back
	advance(1.0)
	local m10 = K.logSize()
	local okS2, whyS2 = bs.Command(x, "Swap", 2)
	advance((BC().Fighter.SwapCastSeconds or 0.6) + 0.3)
	local okB1b, whyB1b = bs.Command(x, "Buff", 1)
	local okS1a, whyS1a = bs.Command(x, "Swap", 1)
	T.check(okS2 == true and okB1b == true and okS1a == false and whyS1a == "Cooldown",
		"p5 cmd: after Swap(2) the benched original fighter (slot 1) can BUFF; Swap(1) is only on the swap cooldown (not BadSlot)",
		tostring(whyS2) .. " / Buff(1) " .. tostring(okB1b) .. " " .. tostring(whyB1b) .. " / Swap(1) " .. tostring(okS1a) .. " " .. tostring(whyS1a))
	local bx = battleOf(id)
	local teamX = bx and bx.Sim and bx.Sim.teamByOwner and bx.Sim.teamByOwner[x.UserId]
	if T.check(teamX ~= nil, "p5 cmd: (white-box) the duel's sim team is reachable") then
		teamX.swapReadyAt = 0
		local okS1b, whyS1b = bs.Command(x, "Swap", 1)
		advance(0.3)
		local back = false
		for _, ev in ipairs(eventsOf(x, m10, "Swap")) do
			if ev.owner == x.UserId and ev["in"] == ownId then
				back = true
			end
		end
		T.check(okS1b == true and back and teamX.fighter and teamX.fighter.id == ownId, "p5 cmd: Swap(1) brings the original fighter back (Swap event in = its unit id)", tostring(whyS1b))
	end
	-- Forfeit still works from anywhere; afterwards commands pay or change nothing
	bs.Forfeit(x)
	advance(0.5)
	local r = w.find(id)
	T.check(r ~= nil and r.Forfeit == true and contains(r.Losers, x.UserId) and w.count(id) == 1, "p5 cmd: Forfeit ends the duel (the forfeiter loses), BattleEnded once")
	T.eq(#Mock.Errors, errs0, "p5 cmd: no script errors")
	K.flushErrors("p5svc_commands")
	K.flushWarnings("p5svc_commands", ALLOWED_WARNINGS)
	w.stop()
	cleanup({ x, y, z })
end)

----------------------------------------------------------------------------------------------------
-- p5svc_position
----------------------------------------------------------------------------------------------------
S.p5svc_position = scenario("p5svc_position", function()
	if not ready("p5svc_position") then
		return
	end
	quietReplication()
	local bs, bc = BS(), BC()
	local F = bc.Fighter
	local w = watchEnded()
	local a = newPlayer("PosA", MID, 10)
	local b = newPlayer("PosB", ALT, 10)
	toArena(a, 3, 0)
	toArena(b, -3, 0)
	local mark = K.logSize()
	local ok, id = bs.StartDuel(a, b)
	if not T.check(ok == true, "p5 pos: (precondition) a duel starts", tostring(id)) then
		w.stop()
		cleanup({ a, b })
		return
	end
	advance(0.5)
	-- (the FOLLOW cap and the FOLLOW leash are measured here: the wave 6 engage rule and the podium lock held off)
	holdEngage(id, a.UserId)
	holdEngage(id, b.UserId)
	freePodium(a)
	freePodium(b)
	local ta = tracker(a)
	ta.cursor = mark
	pump(ta)
	-- Start.Team.Speed = Fighter.SpeedsOf(the fighter's MoveSpeed)
	local mine = ta.static[ta.fighter]
	local def = PC().Get(MID[1])
	local stats = bc.UnitStats(def, 10, "Normal")
	local walk, run = F.SpeedsOf(stats.MoveSpeed)
	T.check(mine and ta.speed and math.abs(ta.speed.Walk - walk) < 0.05 and math.abs(ta.speed.Run - run) < 0.05 and walk >= F.WalkMin and walk <= F.WalkMax,
		"p5 pos: Start.Team.Speed = { Walk = WalkOf(MoveSpeed), Run = x1.3 } (the legal battle speeds)",
		ta.speed and string.format("%.1f / %.1f vs %.1f / %.1f", ta.speed.Walk, ta.speed.Run, walk, run) or "no speed")
	-- the server fighter follows the character at <= legal run x MoveSlack: teleport the character 30 studs along the floor
	local fx0, fz0 = myPos(ta)
	local cx, cz = charLocal(ta)
	placeChar(ta, cx, cz + 30)
	local t0 = Mock.Clock.now
	advance(0.5)
	pump(ta)
	local fx1, fz1 = myPos(ta)
	local moved = math.sqrt((fx1 - fx0) ^ 2 + (fz1 - fz0) ^ 2)
	local cap = run * F.MoveSlack * (Mock.Clock.now - t0) + 1.5
	T.check(moved > 3 and moved <= cap, "p5 pos: the server fighter walks toward the character at <= legal run x MoveSlack (" .. string.format("%.1f in %.1f s, cap %.1f", moved, Mock.Clock.now - t0, cap) .. ")")
	-- back to the fighter: the gap closes, no leash
	placeChar(ta, fx1, fz1)
	advance(1.0)
	pump(ta)
	T.check(#ta.ends == 0 and bs.IsInBattle(a), "p5 pos: a character that comes back is never leashed")
	-- a teleport far across the arena (inside InArena, > Leash from the fighter): a leaver after LeashSeconds
	local m2 = K.logSize()
	local info = arenaInfo()
	Mock.Teleport(a, info.Floor.CFrame * CFrame.new(40, 3, 40)) -- the raid floor: inside the arena, far from the ring
	local leashedAt = nil
	local tStart = Mock.Clock.now
	for _ = 1, 60 do
		advance(0.1)
		if w.find(id) then
			leashedAt = Mock.Clock.now - tStart
			break
		end
	end
	local r = w.find(id)
	T.check(r ~= nil and leashedAt and leashedAt >= F.LeashSeconds - 0.3 and leashedAt <= F.LeashSeconds + 1.6 and contains(r.Losers, a.UserId) and r.Forfeit == true
		and toasted(a, "ran off", m2),
		"p5 pos: a duellist whose character stays > Leash from the server fighter for LeashSeconds is a leaver ('You ran off', the duel is lost)",
		string.format("after %.1f s (want ~%d)", leashedAt or -1, F.LeashSeconds))
	T.check(a:GetAttribute("InBattle") == nil and b:GetAttribute("InBattle") == nil, "p5 pos: ...InBattle cleared for both")
	advance(4.5)

	-- a raid: a raider teleported far is REMOVED (the others fight on); Speed events on Swap
	endAnyRaid(bs)
	local startRaid = holdRaidSchedule(bs)
	local r1 = newPlayer("PosRaid", STRONG, 10)
	local r2 = newPlayer("PosRaid", MID, 10)
	toArena(r1, -6, 0)
	toArena(r2, 6, 0)
	local okR, raidId = startRaid("storm_titan")
	bs.JoinRaid(r1)
	bs.JoinRaid(r2)
	advance(0.5)
	do
		-- (the FOLLOW leash: wave 6 skips it while the pet fights, the floor bounds the pet; held off here)
		local stR = bs.GetRaidStatus()
		holdEngage(stR and stR.BattleId, r1.UserId)
	end
	local tr1 = tracker(r1)
	tr1.cursor = mark
	pump(tr1)
	local m3 = K.logSize()
	local okSw = bs.Command(r1, "Swap", 2)
	advance(0.3)
	local speedEv, swapEv = nil, nil
	for _, ev in ipairs(eventsOf(r1, m3)) do
		if ev.type == "Speed" and ev.owner == r1.UserId then
			speedEv = ev
		elseif ev.type == "Swap" and ev.owner == r1.UserId then
			swapEv = ev
		end
	end
	local def2 = PC().Get(STRONG[2])
	local w2, run2 = F.SpeedsOf(bc.UnitStats(def2, 10, "Normal").MoveSpeed)
	T.check(okR and okSw == true and swapEv and speedEv and math.abs(speedEv.walk - w2) < 0.1 and math.abs(speedEv.run - run2) < 0.1,
		"p5 pos: a Swap relays a Speed event with the incoming pet's legal speeds", speedEv and string.format("%.1f / %.1f vs %.1f / %.1f", speedEv.walk, speedEv.run, w2, run2) or "no Speed event")
	local m4 = K.logSize()
	Mock.Teleport(r1, info.Floor.CFrame * CFrame.new(0, 3, -44 - 6 - 40)) -- the far rim, well inside InArena's disc (the fighter is clamped to the floor)
	local removedAt = nil
	local t1 = Mock.Clock.now
	for _ = 1, 60 do
		advance(0.1)
		local e = lastMsg(r1, "End", m4)
		if e then
			removedAt = Mock.Clock.now - t1
			break
		end
	end
	local e1 = lastMsg(r1, "End", m4)
	local st = bs.GetRaidStatus()
	-- (wave 6: the FOLLOW leash counts from the teleport's first tick, no engage to drop first: -0.4 s tick slack)
	T.check(e1 and e1.Outcome == "Left" and removedAt and removedAt >= F.LeashSeconds - 0.4 and removedAt <= F.LeashSeconds + 1.6 and st and st.Players == 1 and bs.IsInBattle(r2)
		and r1:GetAttribute("InBattle") == nil and toasted(r1, "ran off", m4),
		"p5 pos: a raider leashed out is removed from the raid (End Outcome Left, the others fight on)", string.format("after %.1f s, players %s", removedAt or -1, st and tostring(st.Players) or "nil"))
	bs.EndRaid()
	advance(0.3)

	-- W5 battle-dungeon-3 (4.4 / B1 / C15): a STUNNED / frozen fighter stands (the sim caps its move at 0) while the
	-- character keeps running, so the gap grows past Leash 10 through no fault of the player: no leash while the stun
	-- lasts nor during the catch-up after it; afterwards a real run-off is still removed
	local s = newPlayer("PosFrozen", MID, 10)
	local zoneS = makeZone(160)
	placeOnZone(zoneS, { s })
	local specS, callsS = encounterSpec(zoneS, { s })
	local markS = K.logSize()
	local idS, whyS = bs.OpenEncounter(specS)
	advance(0.3)
	local trS = tracker(s)
	trS.cursor = markS
	pump(trS)
	local bS = battleOf(idS)
	local teamS = bS and bS.Sim and bS.Sim.teamByOwner and bS.Sim.teamByOwner[s.UserId]
	if T.check(type(idS) == "string" and teamS ~= nil and trS.zone ~= nil and trS.speed ~= nil, "p5 pos: (setup) a solo dungeon encounter on a 160 zone, its sim reachable", tostring(whyS)) then
		local fS = teamS.fighter
		local runS = trS.speed.Run
		-- the fighter follows the character to the zone centre first (the circles below stay inside the zone)
		placeChar(trS, 0, 0)
		local t0 = Mock.Clock.now
		while Mock.Clock.now - t0 < 8 and math.abs(fS.x) + math.abs(fS.z) > 1 do
			advance(0.2)
		end
		T.check(math.abs(fS.x) + math.abs(fS.z) <= 1 and #callsS.OnLeave == 0, "p5 pos: (setup) the fighter stands at the centre, nothing leashed")
		-- a 2.5 s freeze (Blizzard) while the character circles at r 30 at the legal run speed for 9 s (without the
		-- stun rule the leash fires at ~4.3 s)
		fS.stunUntil = bS.Sim:Time() + 2.5
		local theta = 0
		for _ = 1, 90 do
			theta = theta + runS * 0.1 / 30
			placeChar(trS, 30 * math.cos(theta), 30 * math.sin(theta))
			advance(0.1)
		end
		local partS = bS.Parts[s.UserId]
		T.check(#callsS.OnLeave == 0 and bs.IsInBattle(s) and partS ~= nil and (partS.LeashGraceUntil or 0) > 2.5,
			"p5 pos: a fighter frozen 2.5 s whose character keeps circling at r 30 at the legal run speed is NEVER leashed (the stun + its catch-up are exempt)",
			string.format("OnLeave %d, grace until %.1f", #callsS.OnLeave, partS and partS.LeashGraceUntil or -1))
		-- after the catch-up the leash is back: a 45 stud jump + a run-off at the legal speed is removed (the leash or
		-- the zone's presence check, whichever comes first)
		local waited = 0
		while partS and bS.Sim:Time() < (partS.LeashGraceUntil or 0) + 0.2 and waited < 30 do
			advance(0.5)
			waited = waited + 0.5
		end
		T.check(#callsS.OnLeave == 0 and bs.IsInBattle(s), "p5 pos: ...and still in the fight once the grace has run out", tostring(#callsS.OnLeave))
		local fx, fz = fS.x, fS.z
		local leftAt = nil
		local t1 = Mock.Clock.now
		for i = 1, 60 do
			placeChar(trS, fx + 45 + runS * 0.1 * i, fz)
			advance(0.1)
			if #callsS.OnLeave > 0 then
				leftAt = Mock.Clock.now - t1
				break
			end
		end
		local whyLeft = callsS.OnLeave[1] and callsS.OnLeave[1][3]
		T.check(leftAt ~= nil and leftAt <= F.LeashSeconds + 1.6 and not bs.IsInBattle(s) and (whyLeft == "Leash" or whyLeft == "Left"),
			"p5 pos: a real run-off after the grace is still removed within LeashSeconds (OnLeave Leash / Left)", string.format("after %.1f s, why %s", leftAt or -1, tostring(whyLeft)))
	end
	bs.FinishEncounter(idS, "Abandoned")
	advance(0.3)
	zoneS:Destroy()
	K.flushErrors("p5svc_position")
	K.flushWarnings("p5svc_position", ALLOWED_WARNINGS)
	w.stop()
	cleanup({ a, b, r1, r2, s })
end)

----------------------------------------------------------------------------------------------------
-- p5svc_position_legit: leash_fix.py replayed on the service (random targets + the circle at exactly the legal run)
----------------------------------------------------------------------------------------------------
S.p5svc_position_legit = scenario("p5svc_position_legit", function()
	if not ready("p5svc_position_legit") then
		return
	end
	quietReplication()
	local bs, bc = BS(), BC()
	local F = bc.Fighter
	local LAT_TICKS = 2 -- 200 ms feed delay at 0.1 s ticks
	local cases = { { "mochi_slime", 1 }, { "stormfang", 50 } }
	for _, case in ipairs(cases) do
		local petId, level = case[1], case[2]
		local p = newPlayer("Legit", { petId }, level)
		local zone = makeZone(44)
		placeOnZone(zone, { p })
		local spec, calls = encounterSpec(zone, { p })
		local mark = K.logSize()
		local id, why = bs.OpenEncounter(spec)
		if not T.check(type(id) == "string", "p5 legit: (precondition) an encounter opens for " .. petId .. " L" .. level, tostring(why)) then
			cleanup({ p })
			zone:Destroy()
			return
		end
		advance(0.3)
		local tr = tracker(p)
		tr.cursor = mark
		pump(tr)
		local def = PC().Get(petId)
		local walk, run = F.SpeedsOf(bc.UnitStats(def, level, "Normal").MoveSpeed)
		T.check(tr.speed and math.abs(tr.speed.Run - run) < 0.05, "p5 legit: " .. petId .. " runs at " .. string.format("%.1f", run) .. " studs/s (RunOf(WalkOf(MoveSpeed)))",
			tr.speed and tostring(tr.speed.Run) or "no speed")
		-- phase A: 20 s of random targets inside the floor at exactly the legal run, the server seeing the position
		-- 200 ms late (the character is placed where the "real" character was LAT_TICKS ticks ago)
		local rng = Random.new(7)
		local h = 22 - 2
		local rx, rz = 0, -14 -- the "real" character
		local tx, tz = rx, rz
		local hist = {}
		local maxGap, leashes = 0, 0
		local function feed()
			hist[#hist + 1] = { rx, rz }
			local seen = hist[math.max(1, #hist - LAT_TICKS)]
			placeChar(tr, seen[1], seen[2])
		end
		local function tick(dt)
			advance(dt)
			pump(tr)
			local fx, fz = myPos(tr)
			if fx then
				local gap = math.sqrt((rx - fx) ^ 2 + (rz - fz) ^ 2)
				if gap > maxGap then
					maxGap = gap
				end
			end
			for _, e in ipairs(tr.ends) do
				if e.BattleId == tr.id then
					leashes = leashes + 1
				end
			end
		end
		for _ = 1, 200 do
			if math.sqrt((tx - rx) ^ 2 + (tz - rz) ^ 2) < 2 then
				tx, tz = rng:NextNumber(-h, h), rng:NextNumber(-h, h)
			end
			local dx, dz = tx - rx, tz - rz
			local d = math.sqrt(dx * dx + dz * dz)
			local step = math.min(d, run * 0.1)
			rx, rz = rx + dx / d * step, rz + dz / d * step
			feed()
			tick(0.1)
		end
		T.check(leashes == 0 and bs.IsInBattle(p), "p5 legit: " .. petId .. ": 20 s of random targets at the legal run with 200 ms latency: zero leashes",
			string.format("max real gap %.1f", maxGap))
		T.check(maxGap <= F.Leash, "p5 legit: " .. petId .. ": ...the real gap never exceeds Leash " .. F.Leash .. " (prototype: <= 5.2)", string.format("%.1f", maxGap))
		-- phase B: the r 14 circle for 10 s, then enemies for the reach check (10 s)
		local wc = run / 14
		local t = 0
		for _ = 1, 100 do
			t = t + 0.1
			rx, rz = 14 * math.cos(wc * t), 14 * math.sin(wc * t)
			feed()
			tick(0.1)
		end
		T.check(leashes == 0 and bs.IsInBattle(p), "p5 legit: " .. petId .. ": the r 14 circle at the legal run: zero leashes", string.format("max real gap %.1f", maxGap))
		-- a wave of weak enemies: every ATTACK on a target within the server fighter's reach is never OutOfReach
		local okW = bs.SpawnWave(id, wave({ { "honey_bunny", 1, 0.3 }, { "puddle_frog", 1, 0.3 } }), { Wave = 1, Name = "Reach" })
		advance(0.2)
		local inReach, farRefused, accepted, respawns = 0, 0, 0, 0
		for i = 1, 100 do
			advance(0.1)
			pump(tr)
			local eid, dist, s = nearestEnemy(tr)
			if not eid then
				if respawns < 4 and bs.EncounterStatus(id) and bs.EncounterStatus(id).Enemies == 0 then
					respawns = respawns + 1
					bs.SpawnWave(id, wave({ { "honey_bunny", 1, 0.3 } }), { Wave = 1 + respawns })
				end
			else
				local u = tr.units[eid]
				local mine = tr.static[tr.fighter] or {}
				local reach = (tonumber(mine.range) or 4.5) + (tonumber(s.radius) or 1) + (tonumber(F.AttackSlack) or 3)
				-- the character runs at the enemy (feed through the latency buffer)
				local dx, dz = u.x - rx, u.z - rz
				local d = math.sqrt(dx * dx + dz * dz)
				if d > 1 then
					local step = math.min(d - 1, run * 0.1)
					rx, rz = rx + dx / d * step, rz + dz / d * step
				end
				feed()
				if i % 5 == 0 then
					local okA, whyA = bs.Command(p, "Attack", eid)
					if dist <= reach - 0.5 then
						inReach = inReach + 1
						if okA then
							accepted = accepted + 1
						elseif whyA == "OutOfReach" then
							farRefused = farRefused + 1
						end
					end
				end
			end
		end
		T.check(okW ~= nil and inReach >= 3 and farRefused == 0 and accepted >= 1,
			"p5 legit: " .. petId .. ": every ATTACK on a target within the server fighter's reach is accepted (never OutOfReach)",
			string.format("%d in reach, %d accepted, %d OutOfReach, %d respawns", inReach, accepted, farRefused, respawns))
		pump(tr)
		T.check(count(calls.OnEnd) == 0 and bs.IsInBattle(p), "p5 legit: " .. petId .. ": still fighting (no End, OnEnd never called)")
		-- a straight run-off past the zone edge: the fighter stops at the floor, the gap grows: leashed after ~3 s
		local m2 = K.logSize()
		local leftAt = nil
		local t1 = Mock.Clock.now
		rx, rz = 0, 0
		for _ = 1, 80 do
			rz = rz + run * 0.1
			feed()
			advance(0.1)
			local e = lastMsg(p, "End", m2)
			if e then
				leftAt = Mock.Clock.now - t1
				break
			end
		end
		local e = lastMsg(p, "End", m2)
		-- (in a dungeon room the presence check (zone part + 8 studs, 2 strikes) and the leash (gap > 10 for 3 s) both watch
		-- the run-off; whichever fires first puts the player out: the duel / raid leash is proven by p5svc_position)
		T.check(e and e.Outcome == "Left" and leftAt and leftAt >= 22 / run and leftAt <= 22 / run + F.LeashSeconds + 10 / (run * F.MoveSlack) + 1.5 and #calls.OnLeave == 1
			and (calls.OnLeave[1][3] == "Leash" or calls.OnLeave[1][3] == "Left"),
			"p5 legit: " .. petId .. ": a straight run-off past the zone edge puts the player out within ~3 s (End Outcome Left, OnLeave)",
			string.format("after %.1f s (%s)", leftAt or -1, tostring(calls.OnLeave[1] and calls.OnLeave[1][3])))
		advance(0.5)
		T.check(#calls.OnEnd == 1 and calls.OnEnd[1][2].Reason == "Abandoned", "p5 legit: " .. petId .. ": the last team out ends the encounter 'Abandoned' (OnEnd once)",
			calls.OnEnd[1] and tostring(calls.OnEnd[1][2].Reason) or "no OnEnd")
		cleanup({ p })
		zone:Destroy()
	end
	K.flushErrors("p5svc_position_legit")
	K.flushWarnings("p5svc_position_legit", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- p5svc_duel_fair
----------------------------------------------------------------------------------------------------
S.p5svc_duel_fair = scenario("p5svc_duel_fair", function()
	if not ready("p5svc_duel_fair") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	local D = bc.Duel or {}
	local TR = bc.Trophies
	local w = watchEnded()
	T.check(D.PowerGap == 2 and D.QueueGap == 1.6 and D.PracticeInvite == 2 and D.QueueGapMax == 3, "p5 duel fair: BattleCatalog.Duel = { PowerGap 2, QueueGap 1.6, PracticeInvite 2, QueueGapMax 3 }")
	local strong = newPlayer("FairStrong", STRONG, 50)
	local weak = newPlayer("FairWeak", WEAK, 1)
	toArena(strong, 3, 0)
	toArena(weak, -3, 0)
	-- the invite says practice beyond x2
	local mark = K.logSize()
	local okC = bs.Challenge(strong, weak)
	local lobbyW = lastMsg(weak, "Lobby", mark)
	local inv = lobbyW and lobbyW.Invites and lobbyW.Invites[1]
	T.check(okC == true and inv and inv.Practice == true and toasted(weak, "practice", mark), "p5 duel fair: a challenge > x2 TeamPower apart carries Practice = true in the invite (+ the toast)",
		inv and tostring(inv.Practice) or "no invite")
	bs.ReplyChallenge(weak, strong.UserId, false)
	-- a practice duel pays nothing and counts nothing, however it ends; MaxHit caps every hit at 60% of the victim's HP
	local t0, tw0 = tokens(strong), tokens(weak)
	local rec0 = data.GetBattle(strong) or {}
	local m2 = K.logSize()
	local ok, id = bs.StartDuel(strong, weak)
	T.check(ok == true and toasted(strong, "Practice duel", m2), "p5 duel fair: a duel > PowerGap apart starts as a PRACTICE duel (toast)", tostring(id))
	local ts = tracker(strong)
	ts.cursor = m2
	local tw = tracker(weak)
	tw.cursor = m2
	pump(tw)
	local endS = playUntilEnd(ts, 60, {})
	pump(tw)
	local maxHitShare = 0
	for _, ev in ipairs(tw.events) do
		local victim = ev.type == "Hit" and tw.static[ev.to]
		if victim and victim.owner == weak.UserId and type(ev.dmg) == "number" and (victim.maxHp or 0) > 0 then
			maxHitShare = math.max(maxHitShare, ev.dmg / victim.maxHp)
		end
	end
	local r = w.find(id)
	T.check(endS and r and contains(r.Winners, strong.UserId) and r.Rewards[strong.UserId] and r.Rewards[strong.UserId].Practice == true and r.Rewards[strong.UserId].Trophies == 0
		and tokens(strong) == t0 and tokens(weak) == tw0 and (data.GetBattle(strong).PvPWins or 0) == (rec0.PvPWins or 0),
		"p5 duel fair: the strong team wins the practice duel: no trophies, tokens, XP or PvP counters for anyone", r and tostring(r.Reason) or "no end")
	T.check(maxHitShare > 0 and maxHitShare <= (bc.Damage.MaxHit.Share or 0.6) + 0.02, "p5 duel fair: no duel hit above MaxHit 0.6 of the victim's HP", string.format("max %.2f", maxHitShare))
	advance(4.5)
	-- the queue's power band: equal trophies, powers ~x2.5 apart: not paired within QueueGap, paired once the band grew
	local function midPower(level)
		local list = {}
		for i, key in ipairs(MID) do
			list[i] = { Def = PC().Get(key), Level = level, Tier = "Normal" }
		end
		return bc.TeamPower(list)
	end
	local base = midPower(1)
	local pick = 2
	for level = 2, 60 do
		pick = level
		if midPower(level) / base >= D.QueueGap + 0.4 then
			break
		end
	end
	local q1 = newPlayer("FairQ", MID, pick)
	local q2 = newPlayer("FairQ", MID, 1)
	toArena(q1, 0, 6)
	toArena(q2, 0, 9)
	local s1 = bs.TeamSpec(q1)
	local s2 = bs.TeamSpec(q2)
	local p1, p2 = bc.TeamPower(s1.Pets), bc.TeamPower(s2.Pets)
	local ratio = math.max(p1, p2) / math.max(1, math.min(p1, p2))
	T.check(ratio > D.QueueGap + 0.3 and ratio < D.QueueGapMax, "p5 duel fair: (setup) the two queued teams are x" .. string.format("%.2f", ratio) .. " apart (between QueueGap and QueueGapMax)")
	bs.Queue(q1)
	bs.Queue(q2)
	advance(12)
	T.check(not bs.IsInBattle(q1) and not bs.IsInBattle(q2), "p5 duel fair: the quick queue does not pair teams more than x1.6 TeamPower apart at once")
	local needWait = math.ceil((ratio - D.QueueGap) / D.QueueGapPerWait) * D.QueueWaitStep
	advance(needWait + 5)
	local g1, g2 = bs.GetBattle(q1), bs.GetBattle(q2)
	T.check(g1 and g2 and g1.BattleId == g2.BattleId, "p5 duel fair: ...and pairs them once the band grew by x0.1 per 10 s (after ~" .. needWait .. " s)")
	bs.Forfeit(q1)
	advance(4.6)
	-- a passive duel ends at exactly TimeLimit (no overtime) as a Draw by damage; a played duel pays once
	local a = newPlayer("FairA", MID, 12)
	local b = newPlayer("FairB", ALT, 10)
	toArena(a, 3, 0)
	toArena(b, -3, 0)
	local m3 = K.logSize()
	local ok2, id2 = bs.StartDuel(a, b)
	holdEngage(id2, a.UserId) -- (passive: wave 6 pets would fight by themselves)
	holdEngage(id2, b.UserId)
	local tStart = Mock.Clock.now
	K.waitFor(function()
		return w.find(id2) ~= nil
	end, 140)
	local r2 = w.find(id2)
	local dur = Mock.Clock.now - tStart
	T.check(ok2 and r2 and r2.Reason == "Timeout" and r2.Draw == true and #r2.Winners == 0 and dur >= 119 and dur <= 123,
		"p5 duel fair: two passive duellists: the duel ends at the 120 s limit as a Draw (no overtime)", r2 and (tostring(r2.Reason) .. string.format(" after %.0f s", dur)) or "no end")
	local rwA = r2 and r2.Rewards[a.UserId]
	T.check(rwA and rwA.Trophies == (TR.Draw or 0) and rwA.Tokens == (TR.Tokens.Draw or 0) * (rwA.Double and 2 or 1), "p5 duel fair: ...both get the Draw rewards", rwA and tostring(rwA.Tokens) or "none")
	advance(4.5)
	local tok0 = { [a] = tokens(a), [b] = tokens(b) }
	local m4 = K.logSize()
	local ok3, id3 = bs.StartDuel(a, b)
	local ta, tb = tracker(a), tracker(b)
	ta.cursor, tb.cursor = m4, m4
	local t3 = Mock.Clock.now
	while Mock.Clock.now - t3 < 125 and not w.find(id3) do
		advance(0.1)
		playTick(ta, {})
		playTick(tb, {})
	end
	local r3 = w.find(id3)
	local winner = r3 and r3.Winners[1] == b.UserId and b or a
	local loser = winner == a and b or a
	local rwW = r3 and r3.Rewards[winner.UserId]
	local rwL = r3 and r3.Rewards[loser.UserId]
	pump(ta)
	pump(tb)
	local endW = (winner == a and ta or tb).ends[1]
	T.check(ok3 and r3 and #r3.Winners == 1 and r3.Reason ~= "Timeout" and rwW and rwW.Trophies == TR.Win and tokens(winner) - tok0[winner] == rwW.Tokens and rwW.Tokens == TR.Tokens.Win * (rwW.Double and 2 or 1)
		and rwL and tokens(loser) - tok0[loser] == (rwL.Tokens or 0) and endW and endW.Outcome == "Win" and w.count(id3) == 1,
		"p5 duel fair: a duel both PLAY (ATTACK + walking in) is decided by lives and paid once (Trophies.Win, the tokens)", r3 and (tostring(r3.Reason) .. " " .. tostring(rwW and rwW.Trophies)) or "no end")
	K.flushErrors("p5svc_duel_fair")
	K.flushWarnings("p5svc_duel_fair", ALLOWED_WARNINGS)
	w.stop()
	cleanup({ strong, weak, q1, q2, a, b })
end)

----------------------------------------------------------------------------------------------------
-- p5svc_raid: 16 fighters + the boss
----------------------------------------------------------------------------------------------------
S.p5svc_raid = scenario("p5svc_raid", function()
	if not ready("p5svc_raid") then
		return
	end
	quietReplication()
	local bs, bc = BS(), BC()
	local w = watchEnded()
	local startRaid = holdRaidSchedule(bs)
	endAnyRaid(bs)
	local teams = { STRONG, MID, ALT, WEAK }
	local raiders = {}
	for i = 1, 16 do
		raiders[i] = newPlayer("Raid16", teams[(i - 1) % 4 + 1], 20)
		toArena(raiders[i], (i - 8) * 3, 6)
	end
	local ok, raidId = startRaid("lava_golem")
	local mark = K.logSize()
	local specs = {}
	for i = 1, 16 do
		local okJ = bs.JoinRaid(raiders[i])
		if not okJ then
			T.fail("p5 raid: (setup) raider " .. i .. " could not join")
		end
		specs[i] = bs.TeamSpec(raiders[i])
	end
	advance(0.3)
	local st = bs.GetRaidStatus()
	local want = bc.BossHp("lava_golem", specs)
	T.check(ok and st and st.Players == 16 and math.abs(st.MaxHp - want) <= math.max(2, want * 0.005), "p5 raid: 16 raiders joined; the boss HP = BattleCatalog.BossHp(bossId, teams) (ExpectedDps of the fighters)",
		st and string.format("%d vs %d", st.MaxHp, want) or "no status")
	local trs = {}
	for i = 1, 16 do
		trs[i] = tracker(raiders[i])
		trs[i].cursor = mark
	end
	advance(0.5)
	pump(trs[16])
	local onFloor, total = 0, 0
	for id, u in pairs(trs[16].units) do
		total = total + 1
		if u.state ~= BENCHED and u.state ~= DOWN then
			onFloor = onFloor + 1
		end
	end
	T.check(onFloor >= 17 and onFloor <= 21 and total == 49, "p5 raid: 17 units on the floor (16 fighters + the boss; the 32 helpers are benched)", onFloor .. " of " .. total)
	-- everybody plays for 10 s: bytes per client under 6 KB/s (p5battle_net16)
	local m2 = K.logSize()
	local t0 = Mock.Clock.now
	for _ = 1, 100 do
		advance(0.1)
		for i = 1, 16 do
			playTick(trs[i], { kit = true })
		end
	end
	local seconds = Mock.Clock.now - t0
	local worst, worstHz, worstSnap, worstEv = 0, 0, 0, 0
	for i = 1, 16 do
		local bytes, snaps, snapBytes, evBytes = 0, 0, 0, 0
		for _, e in ipairs(battleMsgs(raiders[i], m2)) do
			local n = bs.EstimateBytes(e.args[2]) + 4 + #tostring(e.args[1]) + #tostring(e.args[3] or "")
			bytes = bytes + n
			if e.args[1] == "Snapshot" then
				snaps = snaps + 1
				snapBytes = snapBytes + n
			elseif e.args[1] == "Events" then
				evBytes = evBytes + n
			end
		end
		if bytes / seconds > worst then
			worst, worstSnap, worstEv = bytes / seconds, snapBytes / seconds, evBytes / seconds
		end
		worstHz = math.max(worstHz, snaps / seconds)
	end
	local st2 = bs.GetRaidStatus()
	T.info(string.format("*16-raid traffic: worst client %.0f B/s (snapshots %.0f, events %.0f) over %.1f s, %.1f snapshots/s, boss %d/%d", worst, worstSnap, worstEv, seconds, worstHz, st2 and st2.Hp or -1, st2 and st2.MaxHp or -1))
	T.check(worst > 0 and worst < 6000, "p5 raid: every client stays under 6 KB/s in a 16-fighter raid (p5battle_net16)", string.format("%.0f B/s", worst))
	T.check(st2 and st2.Hp < st2.MaxHp, "p5 raid: the played fighters damage the boss")
	-- a leaver (arena) is removed; a disconnect too
	local m3 = K.logSize()
	toLobby(raiders[16])
	advance(1.5)
	local e16 = lastMsg(raiders[16], "End", m3)
	Mock.RemovePlayer(raiders[15])
	advance(0.5)
	local st3 = bs.GetRaidStatus()
	T.check(e16 and e16.Outcome == "Left" and st3 and st3.Players == 14 and raiders[16]:GetAttribute("InBattle") == nil, "p5 raid: a raider who leaves the arena and one who disconnects are removed (14 left)",
		st3 and tostring(st3.Players) or "nil")
	-- the end: tiers paid once
	local before = {}
	for i = 1, 14 do
		before[i] = tokens(raiders[i])
	end
	bs.EndRaid()
	local res = w.find(raidId)
	local consistent = res ~= nil
	for i = 1, 14 do
		local rw = res and res.Rewards[raiders[i].UserId]
		local paid = tokens(raiders[i]) - before[i]
		if not rw or paid ~= (rw.Tokens or 0) then
			consistent = false
		end
	end
	T.check(consistent and res and res.Rewards[raiders[16].UserId] == nil and w.count(raidId) == 1, "p5 raid: EndRaid pays every fighter still in the tier of their share once; leavers nothing; BattleEnded once")
	K.flushErrors("p5svc_raid")
	K.flushWarnings("p5svc_raid", ALLOWED_WARNINGS)
	w.stop()
	local list = {}
	for i = 1, 14 do
		list[#list + 1] = raiders[i]
	end
	list[#list + 1] = raiders[16]
	cleanup(list)
end)

----------------------------------------------------------------------------------------------------
-- p5svc_ring: one level-1 pet, ATTACK once per second, rounds 1-3
----------------------------------------------------------------------------------------------------
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

local function positionOf(thing)
	if type(thing) == "table" then
		if typeof(thing.Position) == "Vector3" then
			return thing.Position
		elseif typeof(thing.CFrame) == "CFrame" then
			return thing.CFrame.Position
		end
		return positionOf(thing.Pad or thing.Part or thing.Model)
	end
	if typeof(thing) ~= "Instance" then
		return nil
	end
	if thing:IsA("BasePart") then
		return thing.Position
	end
	local ok, cf = pcall(function()
		return thing:GetPivot()
	end)
	return ok and cf.Position or nil
end

local function ringPortalPos()
	local info = arenaInfo()
	return positionOf(info and info.RingPortal) or positionOf(workspace:FindFirstChild("Portal_Ring", true))
end

S.p5svc_ring = scenario("p5svc_ring", function()
	if not ready("p5svc_ring") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	local w = watchEnded()
	local pos = ringPortalPos()
	if not T.check(pos ~= nil, "p5 ring: (precondition) a Champion Ring portal exists (ArenaInfo.RingPortal / Portal_Ring)") then
		w.stop()
		return
	end
	local p = newPlayer("RingOne", { "pebble_pup" }, 10)
	T.check(claimHome(p) ~= nil, "p5 ring: (setup) the climber claimed a home")
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 6)))
	advance(0.1)
	local xp0 = totalXp(p, "pebble_pup")
	local cash0 = cash(p)
	local mark = K.logSize()
	local ok, id = bs.StartRing(p, 1)
	if not T.check(ok == true, "p5 ring: StartRing(1) at the portal with ONE level-10 pet", tostring(id)) then
		w.stop()
		cleanup({ p })
		return
	end
	local tr = tracker(p)
	tr.cursor = mark
	advance(0.2)
	pump(tr)
	T.check(tr.start and tr.start.Mode == "Ring" and type(tr.start.Ring) == "table" and tr.start.Ring.Round == 1 and type(tr.start.Team) == "table" and #tr.start.Team.Bench == 0
		and tr.start.Team.Lives == 1, "p5 ring: 'Start' carries Ring { Round 1 } and Team { Fighter, Bench {}, Lives 1 } for a one-pet team")
	-- rounds 1-3: walk toward the champion, ATTACK once per second
	local wins, rounds = 0, {}
	local lastEnd = nil
	local seenEnds = 0
	local t0 = Mock.Clock.now
	local sinceAttack = 1
	while Mock.Clock.now - t0 < 400 do
		advance(0.1)
		sinceAttack = sinceAttack + 0.1
		pump(tr)
		local eid = nearestEnemy(tr)
		if eid then
			local u = tr.units[eid]
			local mine = tr.static[tr.fighter] or {}
			local reach = (tonumber(mine.range) or 4.5) + (tonumber((tr.static[eid] or {}).radius) or 1) + 1
			local fx, fz = myPos(tr)
			if fx and math.sqrt((u.x - fx) ^ 2 + (u.z - fz) ^ 2) > reach - 1 then
				moveChar(tr, u.x, u.z, (tr.speed and tr.speed.Run or 15) * 0.1)
			end
			if sinceAttack >= 1 then
				sinceAttack = 0
				bs.Command(p, "Attack", eid)
			end
		end
		for i = seenEnds + 1, #tr.ends do
			local e = tr.ends[i]
			seenEnds = i
			if type(e.Rewards) == "table" then
				lastEnd = e
				if e.Rewards.Next then
					wins = wins + 1
					rounds[wins] = e
				end
			end
		end
		if wins >= 3 or (lastEnd and lastEnd.Rewards and lastEnd.Rewards.Final) then
			break
		end
	end
	T.check(wins >= 3, "p5 ring: ONE level-10 pet pressing ATTACK once per second wins rounds 1-3 (HP carried)", wins .. " wins in " .. string.format("%.0f s", Mock.Clock.now - t0))
	local R = bc.Ring
	local xpWant = 0
	for r = 1, math.min(3, wins) do
		xpWant = xpWant + (R.XpBase + R.XpPerRound * r)
	end
	local gained = totalXp(p, "pebble_pup") - xp0
	T.check(wins >= 3 and gained == xpWant, "p5 ring: XP paid exactly once per round (20 + 6r each: " .. xpWant .. ")", tostring(gained))
	T.check(cash(p) > cash0 and rounds[1] and rounds[1].Rewards.Cash > 0 and rounds[1].Rewards.Round == 1 and rounds[2] and rounds[2].Rewards.Round == 2,
		"p5 ring: every won round's End carries Rewards.Next / Cash / Round; Cash was paid")
	T.check(bs.IsInBattle(p) and p:GetAttribute("InBattle") ~= nil, "p5 ring: the run goes on (InBattle never nil between rounds)")
	-- the run's natural end: stand still from now on; the round that ends the run pays the loss third (a real loss >= 20 s)
	local xp3 = totalXp(p, "pebble_pup")
	local final = nil
	local t1 = Mock.Clock.now
	while Mock.Clock.now - t1 < 700 do
		holdAttacks(p:GetAttribute("InBattle"), p.UserId) -- passive: the pet no longer auto-attacks either
		advance(0.5)
		pump(tr)
		for _, e in ipairs(tr.ends) do
			if type(e.Rewards) == "table" and e.Rewards.Final then
				final = e
			end
		end
		if final then
			break
		end
	end
	T.check(final ~= nil and final.Rewards.Run and final.Rewards.Run.Wins >= 3, "p5 ring: a passive climber loses a later round: the final End carries Rewards.Final + Run { Wins >= 3 }",
		final and tostring(final.Reason) or "no final End")
	local lastRes = final and w.find(final.BattleId)
	if final and lastRes then
		local round = final.Rewards.Round or (final.Rewards.Run and final.Rewards.Run.Round) or 4
		local dealt = 1 - ((lastRes.Hp and lastRes.Hp[2]) or 1)
		local want = bc.LossXp(R.XpBase + R.XpPerRound * round, lastRes.Duration, dealt)
		T.check(totalXp(p, "pebble_pup") - xp3 == want and (want == 0 or lastRes.Duration >= bc.LossRules.LossMinSeconds or dealt >= bc.LossRules.LossMinDamage),
			"p5 ring: the round that ended the run paid BattleCatalog.LossXp (the real-loss gate) = " .. tostring(want), tostring(totalXp(p, "pebble_pup") - xp3))
	end
	advance(4.6)
	T.check(not bs.IsInBattle(p) and p:GetAttribute("InBattle") == nil and (K.root(p).Position - pos).Magnitude < 40, "p5 ring: the run is over: InBattle cleared, back near the portal")
	K.flushErrors("p5svc_ring")
	K.flushWarnings("p5svc_ring", ALLOWED_WARNINGS)
	w.stop()
	cleanup({ p })
end)

----------------------------------------------------------------------------------------------------
-- p5svc_encounter
----------------------------------------------------------------------------------------------------
S.p5svc_encounter = scenario("p5svc_encounter", function()
	if not ready("p5svc_encounter") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	local w = watchEnded()
	local errs0 = #Mock.Errors
	-- the API exists and works with NO run provider
	local missing = {}
	for _, fn in ipairs({ "OpenEncounter", "SpawnWave", "FinishEncounter", "RemoveEncounterTeam", "EncounterStatus", "TeamSpec", "SetRunProvider" }) do
		if type(bs[fn]) ~= "function" then
			missing[#missing + 1] = fn
		end
	end
	T.check(#missing == 0, "p5 enc: the encounter API exists (OpenEncounter, SpawnWave, FinishEncounter, RemoveEncounterTeam, EncounterStatus, TeamSpec, SetRunProvider)", table.concat(missing, ", "))
	T.check(bs.StartTrial == nil and bs.FinishEncounter("nope") == nil and bs.EncounterStatus("nope") == nil and bs.RemoveEncounterTeam("nope", nil) == false and select(2, bs.OpenEncounter(nil)) ~= nil,
		"p5 enc: StartTrial is gone; the API answers safely for unknown ids / junk")
	bs.SetRunProvider(nil)
	local solo = newPlayer("EncSolo", STRONG, 20)
	T.check(count(bs.KeysInBattle(solo)) == 0 and bs.IsInBattle(solo) == false, "p5 enc: with no run provider KeysInBattle is empty and nothing is in battle")
	local specT, whyT = bs.TeamSpec(solo)
	T.check(type(specT) == "table" and specT.Owner == solo.UserId and #specT.Pets == 3 and specT.Pets[1].Slot == 1 and specT.Pets[1].Key == STRONG[1], "p5 enc: TeamSpec(player) = the active team (slot 1 = the fighter)", tostring(whyT))
	local specK = bs.TeamSpec(solo, { STRONG[3] })
	T.check(type(specK) == "table" and #specK.Pets == 1 and specK.Pets[1].Key == STRONG[3], "p5 enc: TeamSpec(player, keys) uses the given keys")
	local tokens0, cash0, xp0 = tokens(solo), cash(solo), totalXp(solo, STRONG[1])

	-- one team, KeepInBattle: the attribute is never touched (the RUN owns it)
	local zone = makeZone(44)
	placeOnZone(zone, { solo })
	solo:SetAttribute("InBattle", "D7")
	local spec, calls = encounterSpec(zone, { solo })
	local mark = K.logSize()
	local id, why = bs.OpenEncounter(spec)
	if not T.check(type(id) == "string", "p5 enc: OpenEncounter with one team opens a Mode Dungeon battle", tostring(why)) then
		w.stop()
		cleanup({ solo })
		return
	end
	T.check(solo:GetAttribute("InBattle") == "D7" and bs.IsInBattle(solo) and count(bs.KeysInBattle(solo)) == 3, "p5 enc: KeepInBattle: the attribute stays the run id after add; IsInBattle / KeysInBattle work")
	local g = bs.GetBattle(solo)
	T.check(g and g.Mode == "Dungeon" and g.BattleId == id and g.Floor == 3 and g.Room == 2, "p5 enc: GetBattle reports Mode Dungeon with Floor / Room from Extra")
	advance(0.2)
	local tr = tracker(solo)
	tr.cursor = mark
	pump(tr)
	T.check(tr.start and tr.start.Mode == "Dungeon" and type(tr.start.Dungeon) == "table" and tr.start.Dungeon.Floor == 3 and tr.start.Dungeon.Name == "Test Room"
		and type(tr.start.Team) == "table" and tr.start.Side == 1 and #(tr.start.Sides[2] or {}) == 0,
		"p5 enc: 'Start' at once with Mode Dungeon, Dungeon = spec.Extra, Team, an empty side 2")
	-- every other battle is refused while in the encounter / run
	local okF, whyF = bs.Forfeit(solo)
	T.check(okF == false and whyF == "Use LEAVE" and bs.IsInBattle(solo), "p5 enc: Forfeit is refused in a dungeon ('Use LEAVE')", tostring(whyF))
	local st0 = bs.EncounterStatus(id)
	T.check(st0 and st0.Enemies == 0 and st0.Wave == 0 and st0.BossHp == nil and st0.Players[solo.UserId] and st0.Players[solo.UserId].Lives == 3 and st0.Players[solo.UserId].Down == false
		and st0.Players[solo.UserId].MaxHp > 0, "p5 enc: EncounterStatus before a wave: Enemies 0, Wave 0, no boss, Players[uid] = { Lives 3, Hp, MaxHp, Down false }")
	-- SpawnWave: infos + the Wave event; junk refused
	local okJ, whyJ = bs.SpawnWave(id, {})
	local okJ2 = bs.SpawnWave(id, { { PetId = "nope_pet" } })
	local big = {}
	for i = 1, 13 do
		big[i] = { PetId = "honey_bunny" }
	end
	local okJ3, whyJ3 = bs.SpawnWave(id, big)
	T.check(okJ == nil and whyJ == "BadEntries" and okJ2 == nil and okJ3 == nil and whyJ3 == "BadEntries", "p5 enc: SpawnWave refuses an empty list, an unknown pet, 13 entries", tostring(whyJ) .. " " .. tostring(whyJ3))
	local m2 = K.logSize()
	local infos, whyS = bs.SpawnWave(id, wave({ { "honey_bunny", 1, 0.3 }, { "puddle_frog", 1, 0.3 } }), { Wave = 1, Name = "Wave 1" })
	advance(0.2)
	local waveEv = eventsOf(solo, m2, "Wave")[1]
	T.check(type(infos) == "table" and #infos == 2 and infos[1].side == 2 and waveEv and waveEv.index == 1 and #waveEv.units == 2 and waveEv.left == 2,
		"p5 enc: SpawnWave -> 2 infos (side 2) and the Wave { index 1, units, left 2 } event", tostring(whyS))
	local st1 = bs.EncounterStatus(id)
	T.check(st1 and st1.Enemies == 2 and st1.Wave == 1, "p5 enc: EncounterStatus after the wave: Enemies 2, Wave 1")
	-- the fighter clears it: OnWave fires once with the wave index
	local cleared = playUntilEnd(tr, 60, { stop = function()
		return #calls.OnWave >= 1
	end })
	T.check(cleared == nil and #calls.OnWave == 1 and calls.OnWave[1][1] == id and calls.OnWave[1][2] == 1 and bs.EncounterStatus(id).Enemies == 0,
		"p5 enc: OnWave(battleId, 1) fires when the spawned wave is gone; the encounter goes on", tostring(#calls.OnWave))
	-- a boss wave: OnBossHp on every 5% step; the status shows BossHp
	local m3 = K.logSize()
	bs.SpawnWave(id, wave({ { "cloudy_dragon", 20, nil, true } }), { Wave = 2, Name = "Boss" })
	advance(0.2)
	local st2 = bs.EncounterStatus(id)
	T.check(st2 and st2.Enemies == 1 and st2.Wave == 2 and st2.BossHp and math.abs(st2.BossHp - 1) < 1e-6, "p5 enc: a Boss entry shows BossHp 1.0 in the status")
	playUntilEnd(tr, 8, { stop = function()
		return #calls.OnBossHp >= 2
	end })
	local steps = true
	for i, c in ipairs(calls.OnBossHp) do
		if c[1] ~= id or type(c[2]) ~= "number" or c[2] >= 1 or (i > 1 and c[2] > calls.OnBossHp[i - 1][2]) then
			steps = false
		end
	end
	T.check(#calls.OnBossHp >= 1 and steps, "p5 enc: OnBossHp(battleId, frac) fires as the boss loses 5% steps (fractions < 1, falling)", tostring(#calls.OnBossHp))
	-- FinishEncounter("Cleared"): the result, "End" with Rewards.Dungeon, BattleEnded (Mode Dungeon) BEFORE OnEnd, idempotent, nothing paid
	local order = {}
	local conn = bs.BattleEnded:Connect(function(bid)
		if bid == id then
			order[#order + 1] = "BattleEnded"
		end
	end)
	spec.OnEnd = function(bid, result)
		calls.OnEnd[#calls.OnEnd + 1] = { bid, result }
		order[#order + 1] = "OnEnd"
	end
	local m4 = K.logSize()
	local result = bs.FinishEncounter(id, "Cleared")
	local again = bs.FinishEncounter(id, "Cleared")
	conn:Disconnect()
	T.check(type(result) == "table" and result.Reason == "Cleared" and result.Mode == "Dungeon" and again == nil, "p5 enc: FinishEncounter('Cleared') -> the result (Reason Cleared); the second call returns nil")
	T.check(result and contains(result.Fighters, solo.UserId) and type(result.Damage) == "table" and (result.Damage[solo.UserId] or 0) > 0 and type(result.Hp) == "table" and type(result.Survivors) == "table"
		and result.Waves == 2 and type(result.BossHp) == "number" and result.Extra and result.Extra.Floor == 3 and type(result.Duration) == "number",
		"p5 enc: result = { Reason, Duration, Fighters (the solo team), Damage, Hp, Survivors, Waves 2, BossHp, Extra }")
	T.check(order[1] == "BattleEnded" and order[2] == "OnEnd" and #calls.OnEnd == 1 and calls.OnEnd[1][1] == id and calls.OnEnd[1][2] == result,
		"p5 enc: BattleEnded fires, THEN spec.OnEnd(battleId, result) with the same result", table.concat(order, ","))
	local res = w.find(id)
	T.check(res and res.Mode == "Dungeon" and res.Reason == "Cleared" and w.count(id) == 1 and res.RewardsPaid == true, "p5 enc: BattleEnded carried Mode Dungeon once")
	local endMsg = lastMsg(solo, "End", m4)
	T.check(endMsg and endMsg.Mode == "Dungeon" and type(endMsg.Rewards) == "table" and endMsg.Rewards.Dungeon == true and endMsg.Rewards.Extra and endMsg.Rewards.Extra.Room == 2
		and endMsg.Rewards.Tokens == nil and endMsg.Rewards.Xp == nil and endMsg.Rewards.Cash == nil and endMsg.Outcome == "Win",
		"p5 enc: 'End' with Rewards = { Dungeon = true, Extra } (no Cash / Tokens / XP lines)")
	T.check(tokens(solo) == tokens0 and cash(solo) == cash0 and totalXp(solo, STRONG[1]) == xp0, "p5 enc: BattleService paid NOTHING (tokens, cash, XP unchanged)")
	T.check(solo:GetAttribute("InBattle") == "D7" and not bs.IsInBattle(solo) and zone.Parent == workspace and (K.root(solo).Position - zone.Position).Magnitude < 60,
		"p5 enc: after the end the attribute is untouched, the participant released, the zone and the player left where they are (no teleport)")
	solo:SetAttribute("InBattle", nil)

	-- four teams: 0-damage team dropped from Fighters, RemoveEncounterTeam mid-fight (OnLeave), a disconnect (OnLeave), the others fight on
	local party = { solo, newPlayer("EncP", MID, 20), newPlayer("EncP", ALT, 20), newPlayer("EncP", WEAK, 20) }
	for i = 2, 4 do
		party[i]:SetAttribute("InBattle", "D8")
	end
	placeOnZone(zone, party)
	local spec4, calls4 = encounterSpec(zone, party, { Floor = 1, Room = 1 })
	local m5 = K.logSize()
	local id4, why4 = bs.OpenEncounter(spec4)
	T.check(type(id4) == "string" and party[2]:GetAttribute("InBattle") == "D8", "p5 enc: OpenEncounter with four teams (attributes untouched)", tostring(why4))
	local okDup, whyDup = bs.OpenEncounter(encounterSpec(zone, { solo }))
	T.check(okDup == nil and type(whyDup) == "string", "p5 enc: a player already in an encounter cannot be opened into a second one", tostring(whyDup))
	local trs = {}
	for i = 1, 4 do
		trs[i] = tracker(party[i])
		trs[i].cursor = m5
		pump(trs[i])
	end
	local startsOk = true
	for i = 1, 4 do
		if not (trs[i].start and trs[i].start.Mode == "Dungeon" and trs[i].start.Side == 1 and #trs[i].start.Sides[1] == 4) then
			startsOk = false
		end
	end
	T.check(startsOk, "p5 enc: everyone gets 'Start' at once (Sides[1] lists the four)")
	bs.SpawnWave(id4, wave({ { "honey_bunny", 3, 0.5 }, { "puddle_frog", 3, 0.5 }, { "pebble_pup", 3, 0.5 } }), { Wave = 1 })
	advance(0.2)
	-- players 1 and 2 fight, 3 stands idle (0 damage), 4 is removed at once (OnLeave "Quit"); then 3 disconnects
	T.check(bs.RemoveEncounterTeam(id4, party[4]) == true and bs.RemoveEncounterTeam(id4, party[4]) == false and #calls4.OnLeave == 1 and calls4.OnLeave[1][2] == party[4] and calls4.OnLeave[1][3] == "Quit",
		"p5 enc: RemoveEncounterTeam removes a team once (OnLeave(battleId, player, 'Quit'))")
	T.check(party[4]:GetAttribute("InBattle") == "D8" and not bs.IsInBattle(party[4]) and lastMsg(party[4], "End", m5) and lastMsg(party[4], "End", m5).Outcome == "Left",
		"p5 enc: ...the removed player keeps the run attribute, gets End Outcome Left, is no longer in a battle")
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < 60 and #calls4.OnWave == 0 do
		advance(0.1)
		playTick(trs[1], {})
		playTick(trs[2], {})
		pump(trs[3])
	end
	T.check(#calls4.OnWave == 1 and bs.IsInBattle(party[1]) and bs.IsInBattle(party[2]) and bs.IsInBattle(party[3]), "p5 enc: the two fighters clear the wave while the idle one watches (OnWave once, all three still in)")
	local p3uid = party[3].UserId
	Mock.RemovePlayer(party[3])
	advance(0.5)
	T.check(#calls4.OnLeave == 2 and calls4.OnLeave[2][3] == "Disconnect" and bs.IsInBattle(party[1]), "p5 enc: a disconnect = OnLeave 'Disconnect'; the others fight on")
	local res4 = bs.FinishEncounter(id4, "Cleared")
	T.check(res4 and contains(res4.Fighters, party[1].UserId) and contains(res4.Fighters, party[2].UserId) and not contains(res4.Fighters, p3uid) and not contains(res4.Fighters, party[4].UserId)
		and #res4.Participants == 4, "p5 enc: result.Fighters = the members with >= 5% of the party's damage (the idle member and the leavers dropped; Participants = 4)")
	T.check(#calls4.OnEnd == 1 and calls4.OnEnd[1][2].Reason == "Cleared" and party[1]:GetAttribute("InBattle") == nil and party[2]:GetAttribute("InBattle") == "D8",
		"p5 enc: OnEnd once; attributes untouched on release (nil stays nil, the run id stays)")
	for i = 1, 4 do
		if party[i].Parent then
			party[i]:SetAttribute("InBattle", nil)
		end
	end
	-- a solo team with 1 damage qualifies; a team of two with 0 damage does not (Fighters empty)
	local duo = { party[1], party[2] }
	placeOnZone(zone, duo)
	local specD, callsD = encounterSpec(zone, duo, { Floor = 1, Room = 2 })
	local idD = bs.OpenEncounter(specD)
	bs.SpawnWave(idD, wave({ { "honey_bunny", 1, 0.3 } }), { Wave = 1 })
	advance(1.0)
	local resD = bs.FinishEncounter(idD, "Abandoned")
	T.check(resD and resD.Reason == "Abandoned" and #resD.Fighters == 0 and #callsD.OnEnd == 1, "p5 enc: a team of two with 0 damage: Fighters empty (Reason Abandoned)")
	placeOnZone(zone, { party[1] })
	local specS, callsS = encounterSpec(zone, { party[1] }, { Floor = 1, Room = 3 })
	local trS = tracker(party[1])
	local idS = bs.OpenEncounter(specS)
	bs.SpawnWave(idS, wave({ { "cloudy_dragon", 30, nil, true } }), { Wave = 1 })
	advance(0.2)
	pump(trS)
	local hitOnce = false
	local t2 = Mock.Clock.now
	while Mock.Clock.now - t2 < 20 and not hitOnce do
		advance(0.1)
		playTick(trS, {})
		pump(trS)
		for _, ev in ipairs(trS.events) do
			if ev.type == "Hit" and ev.from == trS.fighter and (ev.dmg or 0) > 0 then
				hitOnce = true
			end
		end
	end
	local resS = bs.FinishEncounter(idS, "Abandoned")
	T.check(hitOnce and resS and contains(resS.Fighters, party[1].UserId), "p5 enc: a solo team with any damage > 0 qualifies (Fighters = { the solo })")

	-- a KO wipe: weak level-1 pets vs a strong boss: Reason Wipe by the sim, OnDown, OnEnd
	local victim = newPlayer("EncWipe", WEAK, 1)
	placeOnZone(zone, { victim })
	local specW, callsW = encounterSpec(zone, { victim }, { Floor = 9, Room = 4 })
	local trW = tracker(victim)
	local idW = bs.OpenEncounter(specW)
	bs.SpawnWave(idW, wave({ { "cloudy_dragon", 50, nil, true }, { "ember_phoenix", 50 } }), { Wave = 1 })
	local endW = playUntilEnd(trW, 90, { move = false, attack = false })
	local resW = w.find(idW)
	T.check(endW and endW.Outcome == "Loss" and resW and resW.Reason == "Wipe" and #callsW.OnEnd == 1 and callsW.OnEnd[1][2].Reason == "Wipe" and #callsW.OnDown == 1
		and callsW.OnDown[1][2] == victim and callsW.OnDown[1][3] == 0, "p5 enc: a KO wipe ends the sim by itself: End Outcome Loss, OnDown(player, 0) once, OnEnd Reason Wipe",
		resW and tostring(resW.Reason) or "no end")
	T.check(not bs.IsInBattle(victim) and tokens(victim) == DS().GetTokens(victim), "p5 enc: ...the participant is released, nothing paid")
	-- a Timeout: TimeLimit 3
	placeOnZone(zone, { victim })
	local specTO, callsTO = encounterSpec(zone, { victim }, { Floor = 1, Room = 1 })
	specTO.TimeLimit = 3
	local idTO = bs.OpenEncounter(specTO)
	advance(4.0)
	local resTO = w.find(idTO)
	T.check(resTO and resTO.Reason == "Timeout" and #callsTO.OnEnd == 1 and callsTO.OnEnd[1][2].Reason == "Timeout" and bs.FinishEncounter(idTO, "Cleared") == nil,
		"p5 enc: a Timeout ends the sim by itself (OnEnd Reason Timeout); FinishEncounter afterwards is nil", resTO and tostring(resTO.Reason) or "no end")
	-- erroring callbacks are pcall-ed: OnWave / OnEnd throw, finalizeBody still completes ("End" + BattleEnded)
	placeOnZone(zone, { party[1] })
	local specE = encounterSpec(zone, { party[1] }, { Floor = 2, Room = 1 })
	specE.OnWave = function()
		error("boom wave")
	end
	specE.OnEnd = function()
		error("boom end")
	end
	local m6 = K.logSize()
	local idE = bs.OpenEncounter(specE)
	bs.SpawnWave(idE, wave({ { "honey_bunny", 1, 0.3 } }), { Wave = 1 })
	local trE = tracker(party[1])
	trE.cursor = m6
	local t3 = Mock.Clock.now
	while Mock.Clock.now - t3 < 40 and (bs.EncounterStatus(idE) or {}).Enemies ~= 0 do
		advance(0.1)
		playTick(trE, {})
	end
	local resE = bs.FinishEncounter(idE, "Cleared")
	local endE = lastMsg(party[1], "End", m6)
	T.check(resE and resE.Reason == "Cleared" and w.find(idE) and endE and endE.Rewards and endE.Rewards.Dungeon == true and not bs.IsInBattle(party[1]),
		"p5 enc: erroring OnWave / OnEnd are pcall-ed: the end still completes (result, BattleEnded, 'End', the player released)")
	K.flushWarnings("p5svc_encounter", { "boom wave", "boom end", "[BattleService]" })
	-- the force-release path (Debug.FailEnd): nobody stays stuck; OnEnd gets Reason "Error"; nothing paid
	placeOnZone(zone, { party[1] })
	local specF, callsF = encounterSpec(zone, { party[1] }, { Floor = 2, Room = 2 })
	local idF = bs.OpenEncounter(specF)
	bs.Debug = { FailEnd = 1 }
	local m7 = K.logSize()
	local resF = bs.FinishEncounter(idF, "Cleared")
	bs.Debug = nil
	local endF = lastMsg(party[1], "End", m7)
	local rF = w.find(idF)
	T.check(resF == nil and rF and rF.Reason == "Error" and w.count(idF) == 1 and endF and endF.Reason == "Error" and not bs.IsInBattle(party[1]) and #callsF.OnEnd == 1
		and callsF.OnEnd[1][2].Reason == "Error", "p5 enc: when the end fails, forceRelease frees the player, sends 'End' (Error), fires BattleEnded once and OnEnd with Reason Error")
	K.flushWarnings("p5svc_encounter", { "injected end failure", "[BattleService]" })
	-- the 10 s fail-safe: a finished sim (Timeout) whose end is held back is finalized by the service ("Error")
	placeOnZone(zone, { party[1] })
	local specH, callsH = encounterSpec(zone, { party[1] }, { Floor = 2, Room = 3 })
	specH.TimeLimit = 2
	local idH = bs.OpenEncounter(specH)
	bs.Debug = { HoldEnd = true }
	advance(5)
	T.check(w.find(idH) == nil and bs.IsInBattle(party[1]) and #callsH.OnEnd == 0, "p5 enc: (setup) the held encounter is finished but not yet finalized after 3 s")
	advance(10.5)
	bs.Debug = nil
	local rH = w.find(idH)
	T.check(rH and rH.Reason == "Error" and w.count(idH) == 1 and #callsH.OnEnd == 1 and callsH.OnEnd[1][2].Reason == "Error" and not bs.IsInBattle(party[1]),
		"p5 enc: the 10 s fail-safe finalizes an encounter whose end never came (Reason Error, OnEnd once, the player released)")
	K.flushWarnings("p5svc_encounter", { "never finalized", "[BattleService]" })

	-- SetRunProvider: GetRun -> every other battle refused "Finish your dungeon run first"; KeysInRun OR-ed into KeysInBattle
	local runner = party[1]
	local other = party[2]
	claimHome(runner) -- StartRing checks the home before canBattle (Phase 4 order): a homeless runner would stop there
	bs.SetRunProvider({
		KeysInRun = function(pl)
			if pl == runner then
				return { ["hyb:run"] = true, [MID[1]] = true }
			end
			return {}
		end,
		GetRun = function(pl)
			if pl == runner then
				return { Id = "D9" }
			end
			return nil
		end,
	})
	toArena(runner, 3, 0)
	toArena(other, -3, 0)
	local keysR = bs.KeysInBattle(runner)
	T.check(keysR["hyb:run"] == true and keysR[MID[1]] == true, "p5 enc: KeysInBattle ORs the run provider's KeysInRun")
	local okQ, whyQ = bs.Queue(runner)
	local okCh, whyCh = bs.Challenge(runner, other)
	local okCh2, whyCh2 = bs.Challenge(other, runner)
	endAnyRaid(bs)
	local startRaid = holdRaidSchedule(bs)
	startRaid("storm_titan")
	local okJR, whyJR = bs.JoinRaid(runner)
	local okRg, whyRg = bs.StartRing(runner, 1)
	bs.EndRaid()
	local want = "Finish your dungeon run first"
	T.check(okQ == false and whyQ == want and okCh == false and whyCh == want and okJR == false and whyJR == want and okRg == false and whyRg == want and okCh2 == false,
		"p5 enc: with GetRun set, Queue / Challenge / JoinRaid / StartRing are refused 'Finish your dungeon run first' (and nobody can challenge the runner)",
		tostring(whyQ) .. " | " .. tostring(whyJR) .. " | " .. tostring(whyRg) .. " | " .. tostring(whyCh2))
	bs.SetRunProvider(nil)
	other:SetAttribute("InBattle", "D12")
	local okA2, whyA2 = bs.Queue(other)
	other:SetAttribute("InBattle", nil)
	T.check(okA2 == false and whyA2 == want, "p5 enc: the 'D' run id in the InBattle attribute alone refuses too (no provider)", tostring(whyA2))
	T.check(bs.Queue(other) == true, "p5 enc: ...and without it the player may battle again")
	bs.Unqueue(other)
	T.eq(#Mock.Errors, errs0, "p5 enc: no script errors")
	K.flushErrors("p5svc_encounter")
	K.flushWarnings("p5svc_encounter", ALLOWED_WARNINGS)
	w.stop()
	zone:Destroy()
	cleanup({ solo, party[2], party[4], victim })
end)

----------------------------------------------------------------------------------------------------
-- p5svc_shutdown
----------------------------------------------------------------------------------------------------
S.p5svc_shutdown = scenario("p5svc_shutdown", function()
	if not ready("p5svc_shutdown") then
		return
	end
	quietReplication()
	local bs, data, bc = BS(), DS(), BC()
	local w = watchEnded()
	local startRaid = holdRaidSchedule(bs)
	endAnyRaid(bs)
	-- a duel, a raid, a ring run and an encounter all running
	local a = newPlayer("ShutA", MID, 10)
	local b = newPlayer("ShutB", ALT, 10)
	toArena(a, 3, 0)
	toArena(b, -3, 0)
	local okD, duelId = bs.StartDuel(a, b)
	local r1 = newPlayer("ShutR", STRONG, 20)
	toArena(r1, 0, 8)
	startRaid("frost_wyrm")
	local tr1 = tracker(r1)
	local okJ, raidId = bs.JoinRaid(r1)
	for _ = 1, 40 do
		advance(0.1)
		playTick(tr1, {})
	end
	local pos = ringPortalPos()
	local climber = newPlayer("ShutC", { "pebble_pup" }, 30)
	claimHome(climber)
	Mock.Teleport(climber, CFrame.new(pos + Vector3.new(0, 3, 6)))
	advance(0.1)
	local okR, ringId = bs.StartRing(climber, 1)
	advance(0.5)
	local zone = makeZone(44)
	local e1 = newPlayer("ShutE", MID, 10)
	placeOnZone(zone, { e1 })
	e1:SetAttribute("InBattle", "D3")
	local spec, calls = encounterSpec(zone, { e1 }, { Floor = 1, Room = 1 })
	local encId = bs.OpenEncounter(spec)
	bs.SpawnWave(encId, wave({ { "honey_bunny", 1 } }), { Wave = 1 })
	advance(0.5)
	T.check(okD and okJ and okR and type(encId) == "string", "p5 shutdown: (setup) a duel, a raid, a ring round and an encounter run", tostring(duelId) .. " " .. tostring(raidId) .. " " .. tostring(ringId) .. " " .. tostring(encId))
	local trA, trB = data.GetBattle(a).Trophies or 0, data.GetBattle(b).Trophies or 0
	local tokR = tokens(r1)
	local runs0 = (data.GetRing(climber) or {}).Runs or 0
	local mark = K.logSize()
	T.check(bs.Shutdown() == true, "p5 shutdown: Shutdown() runs")
	advance(0.2)
	local rd = w.find(duelId)
	T.check(rd and rd.Reason == "Shutdown" and #rd.Winners == 0 and (data.GetBattle(a).Trophies or 0) == trA and (data.GetBattle(b).Trophies or 0) == trB and rd.Rewards[a.UserId] and rd.Rewards[a.UserId].Void == true,
		"p5 shutdown: the duel is void (Reason Shutdown, no winner, no trophies moved, Rewards Void)")
	local rr = w.find(raidId)
	local rwR = rr and rr.Rewards[r1.UserId]
	T.check(rr and rr.Reason == "Shutdown" and rwR and rwR.Tier ~= nil and tokens(r1) - tokR == (rwR.Tokens or 0), "p5 shutdown: the raid pays the tier of each fighter's share so far (once)",
		rwR and tostring(rwR.Tier) or "none")
	local rg = w.find(ringId)
	local endC = lastMsg(climber, "End", mark)
	T.check(rg and rg.Reason == "Shutdown" and rg.Won == false and endC and endC.Rewards and endC.Rewards.Void == true and endC.Rewards.Final == true,
		"p5 shutdown: the running ring round is void (Won false, Rewards Void + Final)")
	local re = w.find(encId)
	T.check(re and re.Reason == "Shutdown" and re.Mode == "Dungeon" and #calls.OnEnd == 1 and calls.OnEnd[1][2].Reason == "Shutdown" and e1:GetAttribute("InBattle") == "D3" and not bs.IsInBattle(e1),
		"p5 shutdown: the encounter ends 'Shutdown' (OnEnd once, nothing paid, the run attribute untouched)")
	T.check(bs.FinishEncounter(encId, "Cleared") == nil and select(2, bs.OpenEncounter(encounterSpec(zone, { e1 }))) ~= nil and bs.StartDuel(a, b) == false,
		"p5 shutdown: afterwards nothing can be finished twice and no new battle starts")
	advance(4.6)
	T.check(a:GetAttribute("InBattle") == nil and b:GetAttribute("InBattle") == nil and r1:GetAttribute("InBattle") == nil and climber:GetAttribute("InBattle") == nil,
		"p5 shutdown: every InBattle is cleared (the dungeon's run id excepted)")
	T.check((data.GetRing(climber) or {}).Runs == runs0 + 1, "p5 shutdown: the ring run counted Runs + 1 once")
	T.check(w.count(duelId) == 1 and w.count(raidId) == 1 and w.count(ringId) == 1 and w.count(encId) == 1, "p5 shutdown: BattleEnded once per battle")
	e1:SetAttribute("InBattle", nil)
	bs.SetClosing(false)
	toArena(a, 3, 0)
	toArena(b, -3, 0)
	local okAgain, idAgain = bs.StartDuel(a, b)
	T.check(okAgain == true, "p5 shutdown: SetClosing(false) reopens battles", tostring(idAgain))
	bs.Forfeit(a)
	advance(0.5)
	K.flushErrors("p5svc_shutdown")
	K.flushWarnings("p5svc_shutdown", ALLOWED_WARNINGS)
	w.stop()
	zone:Destroy()
	cleanup({ a, b, r1, climber, e1 })
end)

return S
