-- smoke_raid_service.lua: boss raids, Task 2 (docs/superpowers/specs/2026-11-01-raid-boss-design.md: the fight service in
-- server/Services/BattleService.lua, the rotation in EventService, the reward clocks in DataService). Server world only
-- (listed in server_files of tools/smoke.py), booted, before shutdown:
--   raid_svc_enter  no JoinRaid / StartRaid / EndRaid, the boss waits at boot, the tier read from the active team (a busy pet does
--                   not count), the first fight takes the floor, another tier a pocket, a late joiner, the ninth raider
--   raid_svc_dare   own / lower / junk tiers refused, the remote: spam and junk away from the gate start nothing, a dare at the
--                   gate fights the dared tier with its HP floor
--   raid_svc_gate   the walk-through: inside the gate = in the fight, next to it = not, a ring run = not, the 3 s after a release, a
--                   refusal toasts once per cooldown
--   raid_svc_ends   a kill closes that tier 60 s and hides the idle boss, everyone leaving closes nothing, a teammate leaving
--                   keeps the fight, a pocket raider comes back to the gate and the pocket is freed, the rotation waits
--   raid_svc_floor  the floor fight ends while a pocket fight runs: the next NEW fight takes the floor, BattleEnded carries RaidTier /
--                   RaidFloor, EventStarted / EventEnded only for the floor fight
--   raid_rewards    the reward clocks: a win stamps, a second win pays nothing and says when, a loss never touches the win clock,
--                   a second loss pays nothing, a won dare pays the dared tier, Double Rewards still double
--   raid_svc_cost   4 fights x 8 raiders: the sim step time and the pockets' parts (for the report)
-- The real gate is Task 3's: until it exists this file installs a stand-in ArenaInfo.Gate. White-box: the kills write the sim's boss
-- (St is an upvalue of IsInBattle, as in smoke_p5_battleservice.lua). Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance = K.advance
local Workspace = game:GetService("Workspace")

local S = {}

local seq = 0
local COMMON = { "pebble_pup", "honey_bunny", "puddle_frog" }
local RETURN_DELAY = 4 -- BattleService's C.RETURN_DELAY

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
local function ES()
	return req("server/Services/EventService")
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

-- the service's St (white-box, tests only)
local function svcState()
	local f = BS().IsInBattle
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

local function battleOf(id)
	local St = svcState()
	return St and id and St.battles[id] or nil
end

-- a player with a battle team: `level` on every pet of `pets`
local function newPlayer(prefix, level, pets)
	seq = seq + 1
	local p = Mock.AddPlayer(prefix .. seq, 983000 + seq)
	advance(0.2)
	local data = DS()
	local prof = data.GetProfile(p)
	pets = pets or COMMON
	if prof and level then
		for _, id in ipairs(pets) do
			prof.Pets[id] = (prof.Pets[id] or 0) + 1
			prof.PetLevels[id] = { Level = level, Xp = 0 }
		end
		data.MarkDirty(p)
		local ok, why = data.SetTeam(p, 1, pets)
		if not ok then
			T.fail("(setup) SetTeam for " .. p.Name .. " failed", tostring(why))
		end
	end
	return p
end

local function arenaInfo()
	return AB().GetInfo()
end

local function toArena(p, dx, dz)
	Mock.Teleport(p, arenaInfo().Spawn * CFrame.new(dx or 0, 0, dz or 0))
	advance(0.05)
end

local function toLobby(p)
	Mock.Teleport(p, CFrame.new(K.config().Lobby.Origin + Vector3.new(10, 4, 10)))
	advance(0.05)
end

local function lastMsg(p, kind, fromIndex)
	local log = Mock.RemoteLog
	local found = nil
	for i = (fromIndex or 0) + 1, #log do
		local e = log[i]
		if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and e.args[1] == kind then
			found = e.args[2]
		end
	end
	return found
end

local function toastCount(p, pattern, fromIndex)
	local log = Mock.RemoteLog
	local n = 0
	for i = (fromIndex or 0) + 1, #log do
		local e = log[i]
		if e.remote == "Notify" and e.kind == "client" and e.userId == p.UserId and type(e.args[1]) == "string" and e.args[1]:find(pattern) then
			n = n + 1
		end
	end
	return n
end

local function planarTo(p, cf)
	local pos = K.root(p).Position
	return math.sqrt((pos.X - cf.Position.X) ^ 2 + (pos.Z - cf.Position.Z) ^ 2)
end

-- white-box: the fight's boss falls on the next step (the fighter has dealt `damage`)
local function killBoss(id, damageBy, damage)
	local b = battleOf(id)
	if not b then
		T.fail("(setup) no battle " .. tostring(id))
		return
	end
	if damageBy then
		local team = b.Sim.teamByOwner[damageBy.UserId]
		team.damage = team.damage + (damage or 1000)
	end
	b.Sim.boss.hp = 0
	b.Sim.boss.alive = false
end

-- every team of the fight forfeits: lives 0 on the next step = "Wipe"
local function wipe(id, damageBy, damage)
	local b = battleOf(id)
	if not b then
		T.fail("(setup) no battle " .. tostring(id))
		return
	end
	if damageBy then
		local team = b.Sim.teamByOwner[damageBy.UserId]
		team.damage = team.damage + (damage or 1000)
	end
	for _, part in ipairs(b.PartList) do
		if not part.Left then
			b.Sim:Command(part.UserId, "Forfeit")
		end
	end
end

local function pocketCount()
	local holder = Workspace:FindFirstChild("BattlePockets")
	return holder and #holder:GetChildren() or 0
end

-- no fights, the first boss, the 20 minute rotation restarted from now, the stand-in gate, the fake reward clock
local fakeNow = 1000
local fakeGate = false
local function setUp()
	local bs = BS()
	bs.EndRaids("Ended")
	advance(0.2)
	local info = arenaInfo()
	fakeGate = false
	if not info.Gate then
		fakeGate = true
		info.Gate = {
			CFrame = info.Floor.CFrame * CFrame.new(0, 0, 78),
			Size = Vector3.new(11, 8, 6),
			Return = info.Floor.CFrame * CFrame.new(0, 3, 68),
		}
	end
	local St = svcState()
	if St and not St.arenaInfo.Gate then
		St.arenaInfo.Gate = info.Gate -- (a copy of the info table: same stand-in)
	end
	fakeNow = 1000
	bs.Debug = { RaidNow = function()
		return fakeNow
	end }
	bs.SetDoubleRewards(nil)
	ES().StartNow("BossRaid", BC().BossOrder[1])
	advance(0.1)
	local closed = St and St.raidClosed
	if closed then
		for tier in pairs(closed) do
			closed[tier] = nil
		end
	end
	if St then
		St.raidFloorHiddenUntil = nil
	end
	return bs, BC(), info, info.Gate
end

local function tearDown(players)
	local bs = BS()
	bs.EndRaids("Ended")
	advance(0.2)
	bs.Debug = nil
	if fakeGate then
		arenaInfo().Gate = nil
		local St = svcState()
		if St and St.arenaInfo then
			St.arenaInfo.Gate = nil
		end
	end
	K.removePlayers(players)
	advance(RETURN_DELAY + 1)
	local St = svcState()
	if St then
		for tier in pairs(St.raidClosed or {}) do
			St.raidClosed[tier] = nil
		end
		St.raidFloorHiddenUntil = nil
	end
end

local function ready(label)
	if not K.needBoot() then
		return false
	end
	if not BS() or not arenaInfo() or not ES() then
		T.fail(label .. ": skipped, no BattleService / ArenaBuilder / EventService in this build")
		return false
	end
	return true
end

-- the scenario's players are always taken out again, whatever failed
local function scenario(name, fn)
	return guarded(name, function()
		if not ready(name) then
			return
		end
		local players = {}
		local function add(p)
			players[#players + 1] = p
			return p
		end
		local ok, err = pcall(fn, add)
		tearDown(players)
		if not ok then
			error(err, 0)
		end
		K.flushErrors(name)
	end)
end

----------------------------------------------------------------------------------------------------
-- raid_svc_enter
----------------------------------------------------------------------------------------------------
S.raid_svc_enter = scenario("raid_svc_enter", function(add)
	local bs = BS()
	T.check(type(bs.JoinRaid) ~= "function" and type(bs.StartRaid) ~= "function" and type(bs.EndRaid) ~= "function", "raid service: JoinRaid / StartRaid / EndRaid are gone")
	if type(bs.EnterRaid) ~= "function" or type(bs.EndRaids) ~= "function" then
		T.fail("raid service: no EnterRaid / EndRaids")
		return
	end
	local _, BCatalog, info = setUp()
	local lobbyPlayer = add(newPlayer("RaidLobby", 5))
	local starter19 = add(newPlayer("RaidS", 19))
	local starter5 = add(newPlayer("RaidS", 5))
	local mid20 = add(newPlayer("RaidM", 20))
	local starters = {}
	for i = 1, 7 do
		starters[i] = add(newPlayer("RaidX", 3))
	end
	-- a L60 pet training in a team with two L25 pets: only the pets that can fight count
	local busyHigh = add(newPlayer("RaidB", 25))
	local prof = DS().GetProfile(busyHigh)
	prof.Pets.cloudy_dragon = 1
	prof.PetLevels.cloudy_dragon = { Level = 60, Xp = 0 }
	DS().SetTeam(busyHigh, 1, { "cloudy_dragon", "pebble_pup", "honey_bunny" })
	DS().MutateGrowth(busyHigh, function(g)
		g.cloudy_dragon = g.cloudy_dragon or {}
		g.cloudy_dragon.Job = { Stat = "Speed", Ends = os.time() + 3000, Rank = 1, Slot = 1, From = "Free", Paid = 0 }
	end)
	for i, p in ipairs({ starter19, starter5, mid20, busyHigh }) do
		toArena(p, i * 2, 0)
	end
	for i, p in ipairs(starters) do
		toArena(p, -i * 2, 0)
	end
	toLobby(lobbyPlayer)

	local st = bs.GetRaidStatus()
	T.check(st and st.Active == false and st.BossId == BCatalog.BossOrder[1] and next(st.Fights) == nil and st.FloorTier == nil and st.FloorHiddenIn == 0,
		"raid service: the boss waits, no fight, Active = false")
	T.check(select(1, bs.RaidTierFor(starter19)) == "Starter" and select(2, bs.RaidTierFor(starter19)) == 19 and select(1, bs.RaidTierFor(mid20)) == "Mid",
		"raid service: the tier is read from the active team now (L19 Starter, L20 Mid)")
	T.check(select(1, bs.RaidTierFor(busyHigh)) == "Mid", "raid service: a busy L60 pet does not count", tostring(select(1, bs.RaidTierFor(busyHigh))))
	local okL, whyL = bs.EnterRaid(lobbyPlayer)
	T.check(okL == false and tostring(whyL):find("Battle Arena") ~= nil, "raid service: outside the arena: refused", tostring(whyL))
	T.check(next(bs.GetRaidStatus().Fights) == nil, "raid service: ...and starts no fight")

	local mark = K.logSize()
	local joined = {}
	local conn = bs.RaidJoined:Connect(function(p, id, tier)
		joined[#joined + 1] = { p, id, tier }
	end)
	local ok1, id1 = bs.EnterRaid(starter19)
	T.check(ok1 == true and type(id1) == "string" and starter19:GetAttribute("InBattle") == id1, "raid service: the first Starter walks in: a fight starts (InBattle)", tostring(id1))
	st = bs.GetRaidStatus()
	T.check(st.Active == true and st.BattleId == id1 and st.FloorTier == "Starter" and st.Fights.Starter and st.Fights.Starter.Floor == true and st.Fights.Starter.Players == 1
		and st.Fights.Starter.Tier == "Starter" and st.Fights.Starter.BattleId == id1 and st.Fights.Starter.MaxHp > 0,
		"raid service: the first fight takes the floor")
	T.check(#joined == 1 and joined[1][1] == starter19 and joined[1][2] == id1 and joined[1][3] == "Starter", "raid service: RaidJoined(player, battleId, tierId)")
	local start1 = lastMsg(starter19, "Start", mark)
	T.check(start1 and start1.Mode == "Raid" and start1.Raid and start1.Raid.Tier == "Starter" and start1.Raid.Pocket == false and start1.BossId == st.BossId and start1.Raid.BossId == st.BossId,
		"raid service: 'Start' carries Raid = { Tier, Pocket = false, BossId }")
	local rim = planarTo(starter19, info.Floor.CFrame)
	T.check(rim > 46 and rim < 62, "raid service: the floor fighter stands on the floor's rim", string.format("%.1f", rim))
	T.check(toastCount(starter19, "You fight .+ %(Starter tier%)", mark) == 1, "raid service: the toast names the boss and the tier")

	local ok2, id2 = bs.EnterRaid(mid20)
	st = bs.GetRaidStatus()
	T.check(ok2 == true and id2 ~= id1 and st.Fights.Mid and st.Fights.Mid.Floor == false and st.Fights.Mid.Players == 1 and st.BattleId == id1 and st.FloorTier == "Starter",
		"raid service: a Mid player gets a second fight in a pocket; the floor stays Starter's")
	T.check(K.root(mid20).Position.Y > 1000 and planarTo(mid20, info.Floor.CFrame) > 1000, "raid service: the Mid fighter stands at the pocket, far out in the sky (POCKET_ORIGIN y 1500)")
	advance(0.3)
	local midStart = lastMsg(mid20, "Start", mark)
	T.check(midStart and midStart.Raid and midStart.Raid.Tier == "Mid" and midStart.Raid.Pocket == true, "raid service: a pocket fight's 'Start' says Pocket = true")
	advance(1.2)
	T.check(mid20:GetAttribute("InBattle") == id2, "raid service: the pocket fighter is not thrown out by the arena check (the pocket is where they belong)")

	local mark2 = K.logSize()
	local ok3, id3 = bs.EnterRaid(starter5)
	T.check(ok3 == true and id3 == id1 and bs.GetRaidStatus().Fights.Starter.Players == 2, "raid service: a second Starter joins the running Starter fight (late joiner)", tostring(id3))
	advance(0.3)
	T.check(lastMsg(starter5, "Start", mark2) ~= nil and lastMsg(starter19, "Start", mark2) == nil, "raid service: the late joiner gets a fresh Start, the others do not")
	local again, whyAgain = bs.EnterRaid(starter5)
	T.check(again == false and tostring(whyAgain):find("already") ~= nil, "raid service: already fighting: refused", tostring(whyAgain))

	for i = 1, 6 do
		bs.EnterRaid(starters[i])
	end
	local okF, whyF = bs.EnterRaid(starters[7])
	T.check(okF == false and whyF == "This fight is full" and bs.GetRaidStatus().Fights.Starter.Players == 8, "raid service: the ninth raider is refused", tostring(whyF))
	conn:Disconnect()
end)

----------------------------------------------------------------------------------------------------
-- raid_svc_dare
----------------------------------------------------------------------------------------------------
S.raid_svc_dare = scenario("raid_svc_dare", function(add)
	local bs, BCat, _, gate = setUp()
	local gateCF = gate.CFrame
	local starter19 = add(newPlayer("DareS", 19))
	local high60 = add(newPlayer("DareH", 60))
	toArena(starter19, 2, 0)
	toArena(high60, -2, 0)
	local ok, why = bs.EnterRaid(starter19, "Starter")
	T.check(ok == false and why == "You can only dare a higher tier", "raid dare: your own tier is not a dare", tostring(why))
	ok, why = bs.EnterRaid(high60, "Mid")
	T.check(ok == false and why == "You can only dare a higher tier", "raid dare: a lower tier is refused", tostring(why))
	for _, junk in ipairs({ "Gold", 7, {}, true, "" }) do
		ok = bs.EnterRaid(starter19, junk)
		T.check(ok == false, "raid dare: junk tier " .. tostring(junk) .. " refused")
	end
	T.check(next(bs.GetRaidStatus().Fights) == nil, "raid dare: ...nothing started")
	Mock.Teleport(starter19, gateCF * CFrame.new(0, 3, -40)) -- 40 studs from the gate
	advance(0.05)
	local rq = K.remoteFolder():FindFirstChild("BattleRequest")
	local recBefore = DS().GetBattle(starter19)
	local mark = K.logSize()
	for _ = 1, 20 do
		Mock.FromClient(rq, starter19, "RaidDare", "Max")
	end
	advance(0.1)
	T.check(next(bs.GetRaidStatus().Fights) == nil and starter19:GetAttribute("InBattle") == nil, "raid dare: 20 dares in a second from away from the gate start nothing")
	for _, junk in ipairs({ false, 7, {}, "Mid", "Starter" }) do
		Mock.FromClient(rq, starter19, "RaidDare", junk)
	end
	advance(1.1)
	T.check(next(bs.GetRaidStatus().Fights) == nil, "raid dare: junk / far tiers through the remote start nothing")
	-- at the gate: nil / own / lower / junk through the remote are refused too (nil is NOT "my own tier" on the remote)
	Mock.Teleport(starter19, gateCF * CFrame.new(0, 3, -6))
	advance(1.1)
	for _, junk in ipairs({ "nil", "Starter", "Gold", 7 }) do
		if junk == "nil" then
			Mock.FromClient(rq, starter19, "RaidDare")
		else
			Mock.FromClient(rq, starter19, "RaidDare", junk)
		end
		advance(1.1)
		T.check(next(bs.GetRaidStatus().Fights) == nil, "raid dare: at the gate " .. tostring(junk) .. " starts nothing")
	end
	local recAfter = DS().GetBattle(starter19)
	T.check(recAfter.Raids == recBefore.Raids and recAfter.RaidRewardAt == recBefore.RaidRewardAt, "raid dare: a refused dare writes nothing")
	advance(1.1)
	mark = K.logSize()
	Mock.FromClient(rq, starter19, "RaidDare", "Max")
	advance(0.1)
	local st = bs.GetRaidStatus()
	T.check(st.Fights.Max and st.Fights.Max.Players == 1 and starter19:GetAttribute("InBattle") == st.Fights.Max.BattleId, "raid dare: a dare at the gate starts a Max fight for a Starter")
	T.check(st.Fights.Max and st.Fights.Max.MaxHp >= BCat.BossRules.FloorSeconds * BCat.BaselineDps(st.BossId, "Max") - 1, "raid dare: the dared boss has the Max tier's HP floor")
	advance(0.2)
	local start = lastMsg(starter19, "Start", mark)
	T.check(start and start.Raid and start.Raid.Tier == "Max", "raid dare: the Start names the dared tier")
	local sim = st.Fights.Max and battleOf(st.Fights.Max.BattleId)
	T.check(sim and sim.Sim:BossStatus().Tier == "Max", "raid dare: the sim's boss is the Max tier's")
	-- a join request of the old build does nothing
	local before = K.logSize()
	Mock.FromClient(rq, high60, "JoinRaid")
	advance(0.1)
	T.check(high60:GetAttribute("InBattle") == nil and toastCount(high60, ".", before) == 0, "raid dare: a stale JoinRaid request: no fight, no toast")
end)

----------------------------------------------------------------------------------------------------
-- raid_svc_gate
----------------------------------------------------------------------------------------------------
S.raid_svc_gate = scenario("raid_svc_gate", function(add)
	local bs, _, _, gate = setUp()
	local walker = add(newPlayer("GateW", 10))
	local ringer = add(newPlayer("GateR", 10))
	local empty = add(newPlayer("GateE"))
	toArena(walker, 2, 0)
	toArena(ringer, -2, 0)
	toArena(empty, 4, 0)
	Mock.Teleport(walker, gate.CFrame * CFrame.new(0, 3, -6))
	advance(0.6)
	T.check(walker:GetAttribute("InBattle") == nil, "raid gate: standing next to the gate does not take you in (the dare prompt is here)")
	Mock.Teleport(walker, gate.CFrame)
	advance(0.6)
	T.check(type(walker:GetAttribute("InBattle")) == "string" and bs.GetRaidStatus().Fights.Starter ~= nil, "raid gate: walking into the gate puts you in your tier's fight")
	T.check(planarTo(walker, gate.CFrame) > 10, "raid gate: ...teleported to the fight's rim, out of the gate")
	-- a ring run at the gate: no fight (white-box: a run record the monitor leaves alone)
	local St = svcState()
	St.ringRuns[ringer] = { State = "Ended", Keys = {} }
	Mock.Teleport(ringer, gate.CFrame)
	advance(0.6)
	T.check(ringer:GetAttribute("InBattle") == nil and bs.GetRaidStatus().Fights.Starter.Players == 1, "raid gate: a player in a ring run stays out")
	St.ringRuns[ringer] = nil
	toArena(ringer, -2, 0)
	-- leaving: standing in the gate does not re-enter for 3 s
	bs.LeaveRaid(walker)
	Mock.Teleport(walker, gate.CFrame)
	advance(0.6)
	T.check(walker:GetAttribute("InBattle") == nil and bs.GetRaidStatus().Fights.Starter == nil, "raid gate: after leaving, standing in the gate does not re-enter at once")
	advance(3)
	T.check(type(walker:GetAttribute("InBattle")) == "string", "raid gate: ...3 s later it does")
	bs.LeaveRaid(walker)
	toArena(walker, 2, 0)
	advance(0.3)
	-- a refusal toasts once per cooldown
	local mark = K.logSize()
	Mock.Teleport(empty, gate.CFrame)
	advance(2.5)
	T.check(empty:GetAttribute("InBattle") == nil and toastCount(empty, "team", mark) == 1, "raid gate: a refused player gets one toast, not one per poll", tostring(toastCount(empty, "team", mark)))
end)

----------------------------------------------------------------------------------------------------
-- raid_svc_ends
----------------------------------------------------------------------------------------------------
S.raid_svc_ends = scenario("raid_svc_ends", function(add)
	local bs, _, info = setUp()
	local starterA = add(newPlayer("EndS", 10))
	local starter5 = add(newPlayer("EndS", 5))
	local midA = add(newPlayer("EndM", 30))
	local midB = add(newPlayer("EndM", 31))
	local high60 = add(newPlayer("EndH", 60))
	for i, p in ipairs({ starterA, starter5, midA, midB, high60 }) do
		toArena(p, i * 2, 0)
	end
	-- a floor kill
	local _, idS = bs.EnterRaid(starterA)
	killBoss(idS, starterA)
	advance(0.3)
	local st = bs.GetRaidStatus()
	T.check(st.Fights.Starter == nil and st.Closed.Starter and st.Closed.Starter > 58 and st.Closed.Starter <= 60 and st.FloorHiddenIn > 58 and st.Active == false and st.FloorTier == nil and st.BattleId == nil,
		"raid ends: a floor kill closes Starter for 60 s, hides the idle boss 60 s, frees the floor")
	local ok, why = bs.EnterRaid(starter5)
	T.check(ok == false and tostring(why):find("back in") ~= nil, "raid ends: entering a closed tier says when the boss is back", tostring(why))
	T.check(select(1, bs.EnterRaid(midA)) == true and bs.GetRaidStatus().Fights.Mid.Floor == true, "raid ends: another tier is unaffected (and takes the free floor)")
	bs.LeaveRaid(midA)
	advance(RETURN_DELAY + 0.5)
	toArena(midA, 6, 0)
	advance(61)
	st = bs.GetRaidStatus()
	T.check(st.Closed.Starter == nil and st.FloorHiddenIn == 0, "raid ends: after 60 s the tier is open and the idle boss is back")
	T.check(select(1, bs.EnterRaid(starter5)) == true, "raid ends: ...and a Starter can fight again")
	-- everyone leaving: no closure
	bs.LeaveRaid(starter5)
	advance(0.3)
	st = bs.GetRaidStatus()
	T.check(st.Fights.Starter == nil and st.Closed.Starter == nil and st.FloorHiddenIn == 0 and st.Active == false, "raid ends: everyone leaving ends the fight with no closure")
	local reenter = bs.EnterRaid(starter5)
	T.check(reenter == true, "raid ends: ...and the boss is there again at once")
	-- starter5 now holds the floor; Mid goes to a pocket
	local _, idM = bs.EnterRaid(midA)
	bs.EnterRaid(midB)
	st = bs.GetRaidStatus()
	T.check(st.Fights.Mid and st.Fights.Mid.Floor == false and st.Fights.Mid.Players == 2, "raid ends: (two Mid raiders in a pocket)")
	-- a teammate leaving keeps the other fighting, and the leaver is taken back
	bs.LeaveRaid(midA)
	advance(0.3)
	st = bs.GetRaidStatus()
	T.check(st.Fights.Mid and st.Fights.Mid.Players == 1 and midB:GetAttribute("InBattle") == idM and midA:GetAttribute("InBattle") == nil, "raid ends: a teammate leaving leaves the fight running for the other")
	local okBack, whyBack = bs.EnterRaid(midA)
	T.check(okBack == false, "raid ends: a leaver cannot rejoin the fight they left", tostring(whyBack))
	advance(RETURN_DELAY + 0.5)
	T.check(planarTo(midA, info.Floor.CFrame) < 90 and K.root(midA).Position.Y < 1000, "raid ends: the pocket raider who left is back at the gate after RETURN_DELAY", string.format("%.1f studs, y %.1f (floor y %.1f)", planarTo(midA, info.Floor.CFrame), K.root(midA).Position.Y, info.Floor.CFrame.Position.Y))
	local okRe, whyRe = bs.EnterRaid(midA)
	T.check(okRe == false and tostring(whyRe):find("left") ~= nil, "raid ends: ...and still cannot rejoin that running fight", tostring(whyRe))
	-- the pocket raider comes back and the pocket is freed
	local pockets = pocketCount()
	T.check(pockets >= 1, "raid ends: (the pocket stands)", tostring(pockets))
	killBoss(idM, midB)
	advance(0.3)
	st = bs.GetRaidStatus()
	T.check(st.Fights.Mid == nil and st.Closed.Mid and st.FloorHiddenIn == 0 and st.FloorTier == "Starter", "raid ends: a pocket kill closes that tier, the idle boss / the floor are untouched")
	T.check(K.root(midB).Position.Y > 1000, "raid ends: the pocket raider stays RETURN_DELAY for the result card")
	advance(RETURN_DELAY + 0.5)
	T.check(planarTo(midB, info.Floor.CFrame) < 90 and K.root(midB).Position.Y < 1000, "raid ends: a pocket raider is back at the gate after RETURN_DELAY")
	T.check(pocketCount() == pockets - 1, "raid ends: the pocket is freed", tostring(pocketCount()))
	-- the rotation waits for the last fight
	bs.LeaveRaid(starter5)
	advance(0.3)
	local _, idH = bs.EnterRaid(high60)
	local before = bs.GetRaidStatus().BossId
	local okS, how = bs.SetRaidBoss("lava_golem")
	T.check(okS == true and how == "queued" and bs.GetRaidStatus().BossId == before, "raid rotation: a boss change is queued while a fight runs", tostring(how))
	wipe(idH, high60)
	advance(0.3)
	st = bs.GetRaidStatus()
	T.check(st.BossId == "lava_golem" and st.Closed.High == nil and st.Fights.High == nil, "raid rotation: applied when the last fight ends; a wipe closes nothing", tostring(st.BossId))
	local setNow, howNow = bs.SetRaidBoss("frost_wyrm")
	T.check(setNow == true and howNow == "set" and bs.GetRaidStatus().BossId == "frost_wyrm", "raid rotation: set at once with no fight", tostring(howNow))
	T.check(bs.SetRaidBoss("nope") == false and bs.GetRaidStatus().BossId == "frost_wyrm", "raid rotation: an unknown boss is refused")
	-- a running fight keeps its boss
	local _, idK = bs.EnterRaid(high60)
	bs.SetRaidBoss("storm_titan")
	T.check(battleOf(idK).BossId == "frost_wyrm" and battleOf(idK).Sim:BossStatus().BossId == "frost_wyrm", "raid rotation: a running fight keeps its own boss")
	-- EndRaids
	T.eq(bs.EndRaids("Ended"), 1, "raid ends: EndRaids ends every running fight and counts them")
	advance(0.3)
	st = bs.GetRaidStatus()
	T.check(next(st.Fights) == nil and st.Closed.High == nil and st.BossId == "storm_titan", "raid ends: ...a timeout closes nothing; the queued boss applies")
	T.eq(bs.EndRaids("Ended"), 0, "raid ends: EndRaids with nothing running = 0")
	-- a pocket raider who walks off (teleports away): out of the fight, and not pulled back to the gate
	bs.EnterRaid(starter5)
	local _, idA = bs.EnterRaid(high60)
	T.check(battleOf(idA) and battleOf(idA).RaidFloor == false, "raid ends: (a High fight in a pocket)")
	toLobby(high60)
	local lobbyAt = K.root(high60).Position
	advance(1.3)
	T.check(high60:GetAttribute("InBattle") == nil, "raid ends: leaving the pocket takes a pocket raider out of the fight")
	advance(RETURN_DELAY + 0.5)
	T.check((K.root(high60).Position - lobbyAt).Magnitude < 5, "raid ends: ...and nobody pulls them back to the gate")
	T.check(bs.GetRaidStatus().Fights.High == nil, "raid ends: ...the emptied pocket fight is over")
	-- the fail-safe: a pocket fight whose end fails still frees everything, at once
	toArena(high60, 2, 0)
	local pocketsNow = pocketCount()
	local _, idF = bs.EnterRaid(high60)
	T.check(pocketCount() == pocketsNow + 1, "raid ends: (a new pocket)")
	local results = {}
	local conn = bs.BattleEnded:Connect(function(id, result)
		results[id] = result
	end)
	bs.Debug.FailEnd = 1
	killBoss(idF, high60)
	advance(0.3)
	conn:Disconnect()
	local st2 = bs.GetRaidStatus()
	T.check(results[idF] and results[idF].Reason == "Error" and st2.Fights.High == nil and st2.Closed.High == nil and high60:GetAttribute("InBattle") == nil, "raid ends: a failed end frees the fight (Reason Error, no closure)")
	T.check(pocketCount() == pocketsNow and planarTo(high60, info.Floor.CFrame) < 90, "raid ends: ...the pocket is freed and the raider is back at the gate at once")
end)

----------------------------------------------------------------------------------------------------
-- raid_svc_floor
----------------------------------------------------------------------------------------------------
S.raid_svc_floor = scenario("raid_svc_floor", function(add)
	local bs = setUp()
	local es = ES()
	local starter = add(newPlayer("FloorS", 10))
	local mid = add(newPlayer("FloorM", 30))
	local high = add(newPlayer("FloorH", 60))
	for i, p in ipairs({ starter, mid, high }) do
		toArena(p, i * 2, 0)
	end
	local started, ended, results = {}, {}, {}
	local c1 = es.EventStarted:Connect(function(kind, info)
		if kind == "BossRaid" then
			started[#started + 1] = info
		end
	end)
	local c2 = es.EventEnded:Connect(function(kind, info)
		if kind == "BossRaid" then
			ended[#ended + 1] = info
		end
	end)
	local c3 = bs.BattleEnded:Connect(function(id, result)
		results[id] = result
	end)
	local _, idS = bs.EnterRaid(starter)
	local _, idM = bs.EnterRaid(mid)
	T.check(#started == 1 and started[1].Tier == "Starter" and started[1].BattleId == idS and started[1].Source == "floor" and started[1].BossId == bs.GetRaidStatus().BossId,
		"raid floor: EventStarted BossRaid fires for the floor fight only", tostring(#started))
	wipe(idS, starter)
	advance(0.3)
	local st = bs.GetRaidStatus()
	T.check(st.Active == false and st.BattleId == nil and st.FloorTier == nil and st.Fights.Mid and st.Fights.Mid.Floor == false, "raid floor: the floor fight ended, the pocket fight runs on, Active = false")
	T.check(#ended == 1 and ended[1].BattleId == idS, "raid floor: EventEnded BossRaid for the floor fight, once", tostring(#ended))
	local rs = results[idS]
	T.check(rs and rs.RaidTier == "Starter" and rs.RaidFloor == true, "raid floor: BattleEnded carries RaidTier and RaidFloor")
	local _, idH = bs.EnterRaid(high)
	st = bs.GetRaidStatus()
	T.check(st.Fights.High and st.Fights.High.Floor == true and st.FloorTier == "High" and st.BattleId == idH and st.Active == true, "raid floor: the next NEW fight takes the free floor")
	T.check(st.Fights.Mid and st.Fights.Mid.Floor == false, "raid floor: a running pocket fight stays in its pocket")
	T.check(#started == 2 and started[2].Tier == "High", "raid floor: ...and EventStarted fires for it")
	wipe(idM, mid)
	advance(0.3)
	st = bs.GetRaidStatus()
	T.check(st.Active == true and st.BattleId == idH and #ended == 1, "raid floor: a pocket fight's end changes nothing on the floor; no EventEnded")
	local rm = results[idM]
	T.check(rm and rm.RaidTier == "Mid" and rm.RaidFloor == false, "raid floor: a pocket result says RaidFloor = false")
	c1:Disconnect()
	c2:Disconnect()
	c3:Disconnect()
end)

----------------------------------------------------------------------------------------------------
-- raid_rewards
----------------------------------------------------------------------------------------------------
S.raid_rewards = scenario("raid_rewards", function(add)
	local bs = setUp()
	local p = add(newPlayer("Rew", 10))
	toArena(p, 2, 0)
	local data = DS()
	local rec0 = data.GetBattle(p)
	T.check(rec0.RaidRewardAt == 0 and rec0.RaidLossAt == 0 and bs.RaidRewardStatus(p).WinIn == 0 and bs.RaidRewardStatus(p).LossIn == 0, "raid rewards: a new record has no limit")
	local function win(tierId)
		local mark = K.logSize()
		local ok, id = bs.EnterRaid(p, tierId)
		if not ok then
			T.fail("(setup) could not enter: " .. tostring(id))
			return {}, id
		end
		killBoss(id, p)
		advance(0.3)
		local msg = lastMsg(p, "End", mark)
		advance(61) -- the tier's closure
		toArena(p, 2, 0)
		return msg and msg.Rewards or {}, id
	end
	local function lose()
		local mark = K.logSize()
		local ok, id = bs.EnterRaid(p)
		if not ok then
			T.fail("(setup) could not enter: " .. tostring(id))
			return {}
		end
		wipe(id, p)
		advance(0.3)
		toArena(p, 2, 0)
		local msg = lastMsg(p, "End", mark)
		return msg and msg.Rewards or {}
	end
	fakeNow = 1000
	local tokens0 = data.GetTokens(p)
	local rw = win()
	T.check(rw.Tier == "Gold" and rw.Tokens == 200 and rw.Xp == 160, "raid rewards: a Starter Gold win pays x0.4", tostring(rw.Tier) .. " " .. tostring(rw.Tokens) .. " " .. tostring(rw.Xp))
	T.eq(data.GetTokens(p), tokens0 + 200, "raid rewards: ...into the player's tokens")
	T.check(data.GetBattle(p).RaidRewardAt == 1000 and bs.RaidRewardStatus(p).WinIn == 1200, "raid rewards: the win stamps RaidRewardAt; 20 minutes to the next", tostring(bs.RaidRewardStatus(p).WinIn))
	local raids1 = data.GetBattle(p).Raids
	fakeNow = 1600
	local tokens1 = data.GetTokens(p)
	local mark = K.logSize()
	rw = win()
	T.check(rw.Tier == "Cooldown" and rw.Tokens == 0 and rw.AgainIn == 600 and data.GetTokens(p) == tokens1, "raid rewards: a second win 10 minutes later pays nothing and says when", tostring(rw.Tier) .. " " .. tostring(rw.AgainIn))
	T.check(toastCount(p, "Rewards again in 10:00", mark) == 1, "raid rewards: ...the toast says it too")
	T.check(data.GetBattle(p).RaidRewardAt == 1000 and data.GetBattle(p).Raids == raids1 + 1, "raid rewards: ...the clock is not restarted; the fight counts")
	fakeNow = 1700
	rw = lose()
	T.check(rw.Tier == "Loss" and rw.Tokens == 10 and rw.Xp == 8 and data.GetBattle(p).RaidLossAt == 1700 and data.GetBattle(p).RaidRewardAt == 1000,
		"raid rewards: a loss pays the small reward x0.4 and never touches the win clock", tostring(rw.Tier) .. " " .. tostring(rw.Tokens))
	fakeNow = 1800
	local tokens2 = data.GetTokens(p)
	rw = lose()
	T.check(rw.Tokens == 0 and rw.Xp == 0 and data.GetTokens(p) == tokens2 and data.GetBattle(p).RaidLossAt == 1700, "raid rewards: a second loss inside 5 minutes pays nothing", tostring(rw.Tokens))
	fakeNow = 2001
	rw = lose()
	T.check(rw.Tokens == 10, "raid rewards: 5 minutes after the last paid loss it pays again", tostring(rw.Tokens))
	fakeNow = 2300
	rw = win()
	T.check(rw.Tier == "Gold" and rw.Tokens == 200 and data.GetBattle(p).RaidRewardAt == 2300, "raid rewards: 20 minutes later a win pays again", tostring(rw.Tier))
	-- a dare pays the dared tier
	fakeNow = 9000
	rw = win("Max")
	T.check(rw.Tier == "Gold" and rw.Tokens == 650, "raid rewards: a won dare pays the dared tier's medal", tostring(rw.Tokens))
	-- Double Rewards double the tokens
	fakeNow = 12000
	bs.SetDoubleRewards(true, 600)
	rw = win()
	T.check(rw.Tokens == 400 and rw.Double == true, "raid rewards: Double Rewards still double the tokens", tostring(rw.Tokens))
	bs.SetDoubleRewards(nil)
	-- leaving pays nothing and stamps nothing; a fighter who never hit pays nothing either
	fakeNow = 20000
	local okL, idL = bs.EnterRaid(p)
	local before = data.GetBattle(p)
	T.check(okL == true, "raid rewards: (entered)", tostring(idL))
	bs.LeaveRaid(p)
	advance(0.3)
	local after = data.GetBattle(p)
	T.check(after.RaidRewardAt == before.RaidRewardAt and after.RaidLossAt == before.RaidLossAt and after.Raids == before.Raids, "raid rewards: leaving stamps and pays nothing")
	toArena(p, 2, 0)
	local mark2 = K.logSize()
	local _, idN = bs.EnterRaid(p)
	battleOf(idN).Sim.teamByOwner[p.UserId].damage = 0
	wipe(idN)
	advance(0.3)
	local msgN = lastMsg(p, "End", mark2)
	T.check(msgN and msgN.Rewards and msgN.Rewards.Tier == "None" and data.GetBattle(p).RaidLossAt == before.RaidLossAt, "raid rewards: no damage: tier None, no stamp")
	-- a shutdown pays like a loss, whatever the share so far (no medal, no win clock)
	toArena(p, 2, 0)
	fakeNow = 30000
	local mark3 = K.logSize()
	local _, idS = bs.EnterRaid(p)
	battleOf(idS).Sim.teamByOwner[p.UserId].damage = 5000
	local winAt = data.GetBattle(p).RaidRewardAt
	bs.Shutdown()
	bs.SetClosing(false)
	advance(0.2)
	local msgS = lastMsg(p, "End", mark3)
	T.check(msgS and msgS.Rewards and msgS.Rewards.Tier == "Loss" and msgS.Rewards.Tokens == 10 and data.GetBattle(p).RaidLossAt == 30000 and data.GetBattle(p).RaidRewardAt == winAt,
		"raid rewards: a shutdown pays the Loss medal and leaves the win clock", msgS and msgS.Rewards and tostring(msgS.Rewards.Tier) or "no End")
end)

----------------------------------------------------------------------------------------------------
-- raid_svc_cost
----------------------------------------------------------------------------------------------------
S.raid_svc_cost = scenario("raid_svc_cost", function(add)
	local bs, BCat = setUp()
	local levels = { Starter = 10, Mid = 30, High = 60, Max = 90 }
	local spent, steps = 0, 0
	local clock = Mock.RealClock
	for _, tierId in ipairs(BCat.RaidTierOrder) do
		for i = 1, 8 do
			local p = add(newPlayer("Cost" .. tierId, levels[tierId]))
			toArena(p, i * 2, 0)
			local ok, why = bs.EnterRaid(p)
			if not ok then
				T.fail("raid cost: " .. tierId .. " raider " .. i .. " refused", tostring(why))
			end
		end
	end
	local st = bs.GetRaidStatus()
	local fights = 0
	for _, f in pairs(st.Fights) do
		fights = fights + 1
		T.check(f.Players == 8, "raid cost: 8 raiders in the " .. tostring(f.Tier) .. " fight", tostring(f.Players))
		local sim = battleOf(f.BattleId).Sim
		local step = sim.Step
		sim.Step = function(...)
			local t0 = clock()
			local a, b, c = step(...)
			spent = spent + (clock() - t0)
			steps = steps + 1
			return a, b, c
		end
	end
	T.eq(fights, 4, "raid cost: four fights at once")
	advance(5)
	local stepMs = steps > 0 and 1000 * spent / steps or math.huge
	local holder = Workspace:FindFirstChild("BattlePockets")
	local pockets, parts = 0, 0
	for _, model in ipairs(holder and holder:GetChildren() or {}) do
		pockets = pockets + 1
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n = n + 1
			end
		end
		parts = math.max(parts, n)
	end
	T.info(string.format("*raid cost: 4 fights x 8 raiders: %.2f ms per sim step (%d steps), %d pockets, largest %d parts", stepMs, steps, pockets, parts))
	T.check(stepMs < 2 and parts <= 250 and pockets == 3, "raid cost: a sim step under 2 ms, 3 pockets within 250 parts", string.format("%.2f ms, %d pockets, %d parts", stepMs, pockets, parts))
end)

return S
