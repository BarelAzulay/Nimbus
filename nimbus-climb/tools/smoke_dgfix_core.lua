-- smoke_dgfix_core.lua: dungeon fixes, battle-core (docs/dungeon-fixes/plan.md decisions 3, 4, 5, 7 server side:
-- shared/BattleSim.lua + shared/BattleCatalog.lua), loaded by tools/smoke.py in the SERVER world as pure scenarios.
--   dgfixcore_auto      a player's fighter AUTO-ATTACKS in Duel (both PvP fighters), Ring, Raid and Dungeon; it never
--                       moves the unit; no swing while Stunned / Casting / Dashing; the NPC AI is unchanged
--   dgfixcore_direct    ATTACK directs: Attack(id) locks, Attack() locks the nearest and KEEPS it on repeated presses
--                       (bug #16: no cycle; the engage rule is held off here, smoke_fight.lua pins it); a far
--                       lock is accepted with "OutOfReach" (the pet hits the nearest in reach meanwhile); the Order echo
--                       only when the lock changes; refusals (BadTarget / NoTarget / Down)
--   dgfixcore_arrive    enemies spawned after the start (SpawnEnemies waves, AddTeam, raid minions) arrive for
--                       Fighter.ArriveSeconds 1.2: Arrive in the Wave / Spawn unit infos, no acting, no damage from any
--                       path, never the nearest target; then they fight normally; a Dungeon wave pushes the time limit
--                       back (Wave.timeLimit); the start teams (Ring champion, duel side 2) do not arrive
--   dgfixcore_dash      the Dash event { unit, dir, target } toward the lock / the nearest enemy, else the facing;
--                       cooldown + i-frames unchanged; no Move feed needed (the fighter stays where it is)
--   dgfixcore_heal      no passive bench regen during a fight or a dungeon wave gap; a player's Heal special heals the
--                       fighter AND the benched pets; the Heal buff heals the fighter and the OTHER benched pet; element
--                       regen buffs still tick; an NPC healer still heals only its pets on the floor
--   dgfixcore_determinism  the same setup + command stream (auto-attack, waves, arrival, directs) replays exactly
-- White-box: a few checks reach into battle.units / battle.teams (same Lua state). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local abs, huge = math.abs, math.huge
local fmt = string.format

local S = {}

local function loadModule(name)
	local inst = K.moduleInstance("shared/" .. name)
	if not inst then
		return nil, "no ModuleScript shared/" .. name
	end
	local ok, result = pcall(require, inst)
	if not ok then
		return nil, tostring(result)
	end
	if type(result) ~= "table" then
		return nil, "returned " .. type(result)
	end
	return result
end

local function pet(key, level, extra)
	local p = { Key = key, Level = level or 1 }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local function team(owner, side, pets, flags)
	local list = {}
	for i, p in ipairs(pets) do
		local e = {}
		for k, v in pairs(p) do
			e[k] = v
		end
		e.Slot = e.Slot or i
		list[i] = e
	end
	local spec = { Owner = owner, Side = side, Pets = list }
	for k, v in pairs(flags or {}) do
		spec[k] = v
	end
	return spec
end

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= tol
end

local function find(events, kind, pred)
	for _, ev in ipairs(events) do
		if ev.type == kind and (pred == nil or pred(ev)) then
			return ev
		end
	end
	return nil
end

local function count(events, kind, pred)
	local n = 0
	for _, ev in ipairs(events) do
		if ev.type == kind and (pred == nil or pred(ev)) then
			n = n + 1
		end
	end
	return n
end

local function enemies(b, side)
	local out = {}
	for _, u in ipairs(b.units) do
		if u.side ~= (side or 1) and u.alive and not u.gone and not u.benched then
			out[#out + 1] = u
		end
	end
	return out
end

-- put a unit somewhere (white-box) incl. its start-of-step position
local function put(u, x, z)
	u.x, u.z, u.px, u.pz = x, z, x, z
end

-- the fighter at a point, its wanted point synced (no Move feed needed afterwards)
local function putFighter(tm, x, z)
	put(tm.fighter, x, z)
	tm.wantX, tm.wantZ = x, z
end

-- steps until `pred(events)` or `n` steps; returns all events
local function stepFor(b, n, pred)
	local all = {}
	for _ = 1, n do
		local evs = b:Step(0.1)
		for _, ev in ipairs(evs) do
			all[#all + 1] = ev
		end
		if pred and pred(evs) then
			break
		end
	end
	return all
end

local function hitBy(events, fromId, toId)
	return find(events, "Hit", function(ev)
		return ev.from == fromId and (toId == nil or ev.to == toId) and not ev.miss
	end)
end

-- a passive tank enemy that never swings (white-box) and never falls during a check
local function passive(u)
	u.nextAttack = huge
	u.windAt = nil
	u.hit = 0
end

----------------------------------------------------------------------------------------------------
-- dgfixcore_auto
----------------------------------------------------------------------------------------------------
S.dgfixcore_auto = guarded("dgfixcore_auto", function()
	local BC = loadModule("BattleCatalog")
	local BS = loadModule("BattleSim")
	if not T.check(BC and BS, "modules load") then
		return
	end
	local F = BC.Fighter
	T.check(F.AutoRepeat == false and F.AttackSlack == 3 and F.AttackTolerance == 0.85, "Fighter.AutoRepeat false (the server auto-attacks), AttackSlack 3, AttackTolerance 0.85")
	-- DUEL (PvP): both players' fighters swing by themselves, nobody presses anything
	local b = BS.new({ Mode = "Duel", Seed = 3, Teams = { team(1, 1, { pet("biscuit_bear", 10) }), team(2, 2, { pet("biscuit_bear", 10) }) } })
	local t1, t2 = b.teams[1], b.teams[2]
	putFighter(t1, 0, 0)
	putFighter(t2, 0, 3)
	local evs = stepFor(b, 30)
	T.check(hitBy(evs, t1.fighter.id, t2.fighter.id) ~= nil and hitBy(evs, t2.fighter.id, t1.fighter.id) ~= nil, "Duel: BOTH players' fighters auto-attack each other (no command sent)")
	T.check(near(t1.fighter.x, 0, 1e-9) and near(t1.fighter.z, 0, 1e-9) and near(t2.fighter.z, 3, 1e-9), "Duel: the auto-attack never moves a fighter (the character stays the body)")
	-- RING: the champion (an NPC team of the start) is hit; the NPC still winds up before its hits
	local champ = BC.ChampionTeam(1, 5)
	local br = BS.new({ Mode = "Ring", Round = 1, Seed = 5, Teams = { team(1, 1, { pet("aurora_fox", 12) }), champ } })
	local tr = br.teams[1]
	local ce = enemies(br)[1]
	putFighter(tr, 0, 0)
	put(ce, 0, 3)
	evs = stepFor(br, 30)
	T.check(hitBy(evs, tr.fighter.id, ce.id) ~= nil, "Ring: the fighter auto-attacks the champion")
	T.check(find(evs, "Windup", function(ev)
		return ev.unit == ce.id
	end) ~= nil and ce.arriveUntil == nil, "Ring: the champion (a start team) keeps its AI: a Windup before its hits; it never 'arrives'")
	-- RAID: the boss in reach is hit
	local bR = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 2, Teams = { team(1, 1, { pet("cloudy_dragon", 20) }) } })
	local tR = bR.teams[1]
	local boss = bR.boss
	putFighter(tR, boss.x, boss.z - boss.radius - 1)
	evs = stepFor(bR, 25)
	T.check(hitBy(evs, tR.fighter.id, boss.id) ~= nil, "Raid: the fighter auto-attacks the boss in reach")
	-- DUNGEON: a spawned wave is hit once it has arrived
	local bD = BS.new({ Mode = "Dungeon", Seed = 4, Teams = { team(1, 1, { pet("storm_tabby", 12) }) } })
	local tD = bD.teams[1]
	bD:SpawnEnemies({ pet("pebble_pup", 3) }, { Wave = 1, Anchor = { 0, 4 } })
	local de = enemies(bD)[1]
	putFighter(tD, 0, 0)
	put(de, 0, 3)
	passive(de)
	de.maxHp, de.hp = 1e9, 1e9
	evs = stepFor(bD, 30, function(e)
		return hitBy(e, tD.fighter.id, de.id) ~= nil
	end)
	local hit = hitBy(evs, tD.fighter.id, de.id)
	T.check(hit ~= nil and bD:Time() >= F.ArriveSeconds - 1e-6, "Dungeon: the fighter auto-attacks the wave enemy once it has arrived", fmt("t %.1f", bD:Time()))
	-- out of reach: no swing, no step toward the enemy (the auto-attack itself never walks; white-box: the wave 6 engage
	-- rule, which does walk the pet to any enemy on the floor, is held off and pinned by smoke_fight.lua)
	tD.noEngage = true
	put(de, 0, 18)
	tD.fighter.nextAttack = 0
	evs = stepFor(bD, 5)
	T.check(hitBy(evs, tD.fighter.id) == nil and near(tD.fighter.z, 0, 1e-9), "nothing in reach: no swing and the fighter does not walk to it")
	-- busy states: Stunned / Casting / Dashing never swing
	put(de, 0, 3)
	local f = tD.fighter
	local function noSwingWhile(label, set)
		f.nextAttack = 0
		set()
		local e2 = stepFor(bD, 2)
		T.check(hitBy(e2, f.id) == nil, "no auto-attack while " .. label)
	end
	noSwingWhile("Stunned", function()
		f.stunUntil = bD:Time() + 0.5
	end)
	stepFor(bD, 5)
	noSwingWhile("Casting", function()
		f.castUntil = bD:Time() + 0.5
	end)
	stepFor(bD, 5)
	noSwingWhile("Dashing", function()
		tD.dashReadyAt = 0
		bD:Command(1, "Dash")
	end)
	stepFor(bD, 5)
	f.nextAttack = 0
	evs = stepFor(bD, 2)
	T.check(hitBy(evs, f.id) ~= nil, "...and it swings again as soon as it is free")
	-- an NPC-only floor (no player team) never auto-attacks: the AI path is untouched
	local bN = BS.new({ Mode = "Duel", Seed = 6, Teams = { team("a", 1, { pet("biscuit_bear", 5) }, { Npc = true }), team("b", 2, { pet("biscuit_bear", 5) }, { Npc = true }) } })
	local na, nb = bN.units[1], bN.units[2]
	put(na, 0, 0)
	put(nb, 0, 3)
	evs = stepFor(bN, 20)
	local hitsNoWind = 0
	for _, ev in ipairs(evs) do
		if ev.type == "Hit" and not ev.miss and not ev.special and not ev.element then
			local w = find(evs, "Windup", function(x)
				return x.unit == ev.from
			end)
			if not w then
				hitsNoWind = hitsNoWind + 1
			end
		end
	end
	T.check(count(evs, "Windup") >= 2 and hitsNoWind == 0, "NPC units keep the AI: every basic hit comes after a Windup")
end)

----------------------------------------------------------------------------------------------------
-- dgfixcore_direct
----------------------------------------------------------------------------------------------------
S.dgfixcore_direct = guarded("dgfixcore_direct", function()
	local BC = loadModule("BattleCatalog")
	local BS = loadModule("BattleSim")
	if not T.check(BC and BS, "modules load") then
		return
	end
	local F = BC.Fighter
	local b = BS.new({ Mode = "Dungeon", Seed = 8, Teams = { team(1, 1, { pet("storm_tabby", 12), pet("pebble_pup", 5) }) } })
	local tm = b.teams[1]
	local f = tm.fighter
	putFighter(tm, 0, 0)
	-- white-box: FOLLOW only (the pet stays put; the engage rule of wave 6 is pinned by smoke_fight.lua)
	tm.noEngage = true
	local okN, whyN = b:Command(1, "Attack")
	T.check(okN == false and whyN == "NoTarget", "Attack() with no enemy on the floor -> NoTarget", tostring(whyN))
	b:SpawnEnemies({ pet("biscuit_bear", 20), pet("biscuit_bear", 20), pet("biscuit_bear", 20) }, { Wave = 1, Anchor = { 0, 10 } })
	local list = enemies(b)
	local okA, whyA = b:Command(1, "Attack")
	T.check(okA == false and whyA == "NoTarget", "Attack() while every enemy is still arriving -> NoTarget (arriving enemies are not targetable)", tostring(whyA))
	stepFor(b, 13)
	for i, e in ipairs(list) do
		passive(e)
		e.maxHp, e.hp = 1e9, 1e9
		put(e, 0, 2 + 4 * i) -- e1 at 6 (in reach of a 4.5-range tabby + slack), e2 at 10, e3 at 14
	end
	-- Attack(): the nearest; repeated presses KEEP the live lock (bug #16: the old cycle walked the pet off its enemy)
	local ok1, id1 = b:Command(1, "Attack")
	local ok2, id2 = b:Command(1, "Attack")
	local ok3, id3 = b:Command(1, "Attack")
	local ok4, id4 = b:Command(1, "Attack")
	T.check(ok1 and id1 == list[1].id and ok2 and id2 == list[1].id and ok3 and id3 == list[1].id and ok4 and id4 == list[1].id and tm.lock == list[1],
		"Attack() locks the nearest; further presses keep that live lock (no cycle)", fmt("%s %s %s %s", tostring(id1), tostring(id2), tostring(id3), tostring(id4)))
	-- Attack(id): a lock; far = accepted with OutOfReach, and the pet keeps hitting what IS in reach meanwhile
	local okF, idF, extraF = b:Command(1, "Attack", list[3].id)
	f.nextAttack = 0
	local evs = stepFor(b, 3)
	T.check(okF and idF == list[3].id and extraF == "OutOfReach" and tm.lock == list[3], "Attack(id) beyond range + radius + AttackSlack is accepted as a lock with extra OutOfReach (the Too far! toast)")
	T.check(hitBy(evs, f.id, list[1].id) ~= nil and hitBy(evs, f.id, list[3].id) == nil, "a lock out of reach: the auto-attack hits the nearest enemy in reach instead")
	T.check(find(evs, "Order", function(ev)
		return ev.order == "Attack" and ev.target == list[3].id and ev.owner == 1
	end) ~= nil, "a new lock echoes Order { owner, order = Attack, target }")
	-- the lock in reach wins over a nearer enemy
	put(list[2], 0, 4)
	put(list[1], 0, 3)
	local okL = b:Command(1, "Attack", list[2].id)
	f.nextAttack = 0
	evs = stepFor(b, 2)
	T.check(okL and hitBy(evs, f.id, list[2].id) ~= nil and hitBy(evs, f.id, list[1].id) == nil, "the lock in reach is hit even with a nearer enemy")
	-- the same order again: accepted, no second echo (no traffic for a held button)
	local okS = b:Command(1, "Attack", list[2].id)
	evs = stepFor(b, 1)
	T.check(okS and count(evs, "Order") == 0, "repeating the order on the current lock sends no Order echo")
	-- the command never swings: the cooldown is not ready -> no hit, however often it is pressed
	f.nextAttack = b:Time() + 5
	for _ = 1, 5 do
		b:Command(1, "Attack", list[1].id)
		b:Command(1, "Attack")
	end
	evs = stepFor(b, 2)
	T.check(hitBy(evs, f.id) == nil, "pressing ATTACK never swings by itself (10 presses, interval not ready -> no Hit)")
	-- refusals
	local okB, whyB = b:Command(1, "Attack", f.id)
	local okJ, whyJ = b:Command(1, "Attack", 0.5)
	T.check(okB == false and whyB == "BadTarget" and okJ == false and whyJ == "BadTarget", "Attack on an ally / a junk id -> BadTarget")
	-- the lock dies -> it clears, the next Attack() picks the nearest again (the presses above left list[1] locked: Attack()
	-- keeps a live lock now, bug #16; lock list[2] by id)
	b:Command(1, "Attack", list[2].id)
	list[2].hp = 1
	list[2].maxHp = 100
	list[2].defense = 0
	f.nextAttack = 0
	stepFor(b, 3)
	T.check(not list[2].alive and b:TeamOf(1).Lock == nil, "a lock that falls is cleared")
	local okR, idR = b:Command(1, "Attack")
	T.check(okR and idR == list[1].id, "...and Attack() locks the nearest again")
	-- a downed team cannot direct
	for _, u in ipairs(tm.units) do
		u.hp = 0
		u.alive = false
	end
	local okD, whyD = b:Command(1, "Attack")
	T.check(okD == false and (whyD == "Down" or whyD == "Finished"), "a team with no living fighter cannot direct (Down)", tostring(whyD))
	T.check(F.AttackSlack > 0, "Fighter.AttackSlack is the reach margin of the auto-attack")
end)

----------------------------------------------------------------------------------------------------
-- dgfixcore_arrive
----------------------------------------------------------------------------------------------------
S.dgfixcore_arrive = guarded("dgfixcore_arrive", function()
	local BC = loadModule("BattleCatalog")
	local BS = loadModule("BattleSim")
	if not T.check(BC and BS, "modules load") then
		return
	end
	local F = BC.Fighter
	T.check(F.ArriveSeconds == 1.2, "BattleCatalog.Fighter.ArriveSeconds = 1.2", tostring(F.ArriveSeconds))
	local b = BS.new({ Mode = "Dungeon", Seed = 9, TimeLimit = 100, Teams = { team(1, 1, { pet("ember_phoenix", 20) }) } })
	local tm = b.teams[1]
	local f = tm.fighter
	putFighter(tm, 0, 0)
	stepFor(b, 5)
	local limit0 = b.timeLimit
	local infos = b:SpawnEnemies({ pet("biscuit_bear", 15), pet("biscuit_bear", 15) }, { Wave = 1, Anchor = { 0, 6 } })
	T.check(type(infos) == "table" and #infos == 2 and near(infos[1].Arrive, F.ArriveSeconds, 1e-9) and near(infos[2].Arrive, F.ArriveSeconds, 1e-9),
		"SpawnEnemies: every unit info carries Arrive = ArriveSeconds", infos and infos[1] and tostring(infos[1].Arrive))
	local evs = b:Step(0.1)
	local wave = find(evs, "Wave")
	T.check(wave and #wave.units == 2 and near(wave.units[1].Arrive, F.ArriveSeconds, 1e-9) and near(wave.timeLimit, limit0 + F.ArriveSeconds, 1e-9) and near(b.timeLimit, limit0 + F.ArriveSeconds, 1e-9),
		"the Wave event units carry Arrive; a Dungeon wave pushes the time limit back by the arrival (Wave.timeLimit)", wave and tostring(wave.timeLimit))
	local list = enemies(b)
	local e1, e2 = list[1], list[2]
	put(e1, 0, 2)
	put(e2, 2, 2)
	local statics = b:StaticUnits()
	local stArrive = nil
	for _, u in ipairs(statics) do
		if u.id == e1.id then
			stArrive = u.Arrive
		end
	end
	T.check(stArrive and stArrive > 0 and stArrive < F.ArriveSeconds, "StaticUnits (a late Start) carries the seconds of arrival left", tostring(stArrive))
	-- while arriving: no acting, no damage from any path, not the nearest target
	f.nextAttack = 0
	f.meter = 100
	local hp1, hp2 = e1.hp, e2.hp
	local okEl = b:Command(1, "Element", e1.id)
	local okSp = b:Command(1, "Special")
	local during = stepFor(b, 9)
	T.check(e1.hp == hp1 and e2.hp == hp2 and hitBy(during, f.id) == nil, "arriving enemies take no damage (auto-attack, ELEMENT, SPECIAL)", fmt("element %s special %s", tostring(okEl), tostring(okSp)))
	T.check(find(during, "Windup", function(ev)
		return ev.unit == e1.id or ev.unit == e2.id
	end) == nil and near(e1.x, 0, 1.0) and e1.state == BS.States.Idle, "arriving enemies do not act (no Windup, they stand where they appeared)")
	T.check(count(during, "Hit", function(ev)
		return ev.to == e1.id or ev.to == e2.id
	end) == 0, "...and no Hit / miss event is sent for them (the client draws the entrance)")
	-- after the arrival: they fight and can be hit
	f.nextAttack = 0
	local after = stepFor(b, 30, function(e)
		return hitBy(e, f.id) ~= nil
	end)
	T.check(hitBy(after, f.id) ~= nil and b:Time() > e1.arriveUntil, "after ArriveSeconds the enemies can be hit")
	local acted = stepFor(b, 30, function(e)
		return find(e, "Windup") ~= nil
	end)
	T.check(find(acted, "Windup") ~= nil, "...and they act (a Windup)")
	-- AddTeam after the start (an escort) arrives too; a mid-fight player team does not
	local esc = b:AddTeam(team("escort", 2, { pet("pebble_pup", 5) }, { Npc = true }))
	T.check(esc and esc[1] and near(esc[1].Arrive, F.ArriveSeconds, 1e-9), "AddTeam of an enemy team after the start: Arrive too (escorts)")
	-- raid minions: Spawn event units carry Arrive
	local bR = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 2, Teams = { team(1, 1, { pet("cloudy_dragon", 25) }) } })
	local mine = bR:AddTeam(team(2, 1, { pet("cloudy_dragon", 25) }))
	T.check(mine and mine[1] and mine[1].Arrive == nil, "a raid joiner (side 1) never arrives")
	bR.boss.hp = bR.boss.maxHp * 0.69
	local spawn = nil
	local seen = stepFor(bR, 40, function(e)
		spawn = find(e, "Spawn", function(ev)
			return ev.boss ~= nil
		end)
		return spawn ~= nil
	end)
	T.check(spawn and spawn.units[1] and near(spawn.units[1].Arrive, F.ArriveSeconds, 1e-9), "raid minions (a boss wave) carry Arrive in the Spawn event", spawn and tostring(spawn.units[1] and spawn.units[1].Arrive) or tostring(#seen))
	-- the teams of the start do not arrive (the duel / ring opponents are drawn by Start)
	local bD = BS.new({ Mode = "Duel", Seed = 1, Teams = { team(1, 1, { pet("pebble_pup", 3) }), team(2, 2, { pet("pebble_pup", 3) }) } })
	local anyArrive = false
	for _, u in ipairs(bD:StaticUnits()) do
		if u.Arrive then
			anyArrive = true
		end
	end
	T.check(not anyArrive, "the teams of the start never arrive (no Arrive in Start)")
end)

----------------------------------------------------------------------------------------------------
-- dgfixcore_dash
----------------------------------------------------------------------------------------------------
S.dgfixcore_dash = guarded("dgfixcore_dash", function()
	local BC = loadModule("BattleCatalog")
	local BS = loadModule("BattleSim")
	if not T.check(BC and BS, "modules load") then
		return
	end
	local F = BC.Fighter
	local b = BS.new({ Mode = "Dungeon", Seed = 2, Teams = { team(1, 1, { pet("aurora_fox", 10) }) } })
	local tm = b.teams[1]
	local f = tm.fighter
	putFighter(tm, 0, 0)
	-- no enemy: the facing
	tm.faceX, tm.faceZ = 1, 0
	local ok = b:Command(1, "Dash")
	local evs = b:Step(0.1)
	local d = find(evs, "Dash")
	-- wave 6: the dash is a SIDESTEP; no enemy and no threat = the facing turned 90 degrees
	T.check(ok and d and d.unit == f.id and type(d.dir) == "table" and near(d.dir[1], 0, 0.011) and near(abs(d.dir[2]), 1, 0.011) and d.target == nil, "Dash with no enemy: dir = the facing turned 90 degrees (the sidestep), no target", d and d.dir and fmt("%.2f %.2f", d.dir[1], d.dir[2]))
	T.check(f.iframesUntil > b:Time() and near(b:TeamOf(1).Cooldowns.Dash, F.DashCooldown - 0.1, 0.11), "Dash: i-frames and the DashCooldown unchanged")
	local ok2, why2 = b:Command(1, "Dash")
	T.check(ok2 == false and why2 == "Cooldown", "a second Dash is refused Cooldown")
	-- the nearest enemy, then the lock
	b:SpawnEnemies({ pet("pebble_pup", 3), pet("pebble_pup", 3) }, { Wave = 1, Anchor = { 0, 10 } })
	stepFor(b, 13)
	local list = enemies(b)
	put(list[1], 0, 6)
	put(list[2], -8, 0)
	for _, e in ipairs(list) do
		passive(e)
	end
	tm.dashReadyAt = 0
	b:Command(1, "Dash")
	d = find(b:Step(0.1), "Dash")
	T.check(d and d.target == nil and near(abs(d.dir[1]), 1, 0.011) and near(d.dir[2], 0, 0.011), "Dash: no threat = perpendicular to the nearest enemy (wave 6: never into it), no target", d and d.dir and fmt("%.2f %.2f", d.dir[1], d.dir[2]))
	b:Command(1, "Attack", list[2].id)
	tm.dashReadyAt = 0
	b:Command(1, "Dash")
	d = find(b:Step(0.1), "Dash")
	T.check(d and d.target == nil and near(d.dir[1], 0, 0.011) and near(abs(d.dir[2]), 1, 0.011), "Dash: no threat = perpendicular to the LOCK when there is one", d and d.dir and fmt("%.2f %.2f", d.dir[1], d.dir[2]))
	-- no character / Move dependency: without a Move feed the fighter sidesteps along the dir (wave 6) and stays there
	tm.noEngage = true -- (white-box: the engage rule would walk it back to its enemy after the dash)
	local x0, z0 = f.x, f.z
	tm.dashReadyAt = 0
	b:Command(1, "Dash")
	local dd = nil
	for _, ev in ipairs(b.pending) do
		if ev.type == "Dash" then
			dd = ev
		end
	end
	stepFor(b, 3)
	local mx, mz = f.x - x0, f.z - z0
	local ml = math.sqrt(mx * mx + mz * mz)
	T.check(dd and ml >= 3.9 and (mx * dd.dir[1] + mz * dd.dir[2]) / ml > 0.99, "the server fighter sidesteps along the Dash dir (>= 4 studs, no Move feed needed)", fmt("%.2f studs", ml))
	local n = 0
	for k in pairs(d) do
		n = n + 1
	end
	T.check(n <= 4, "the Dash event stays small on the wire ({ type, unit, dir, target })", tostring(n) .. " fields")
end)

----------------------------------------------------------------------------------------------------
-- dgfixcore_heal
----------------------------------------------------------------------------------------------------
S.dgfixcore_heal = guarded("dgfixcore_heal", function()
	local BC = loadModule("BattleCatalog")
	local BS = loadModule("BattleSim")
	local PC = loadModule("PetCatalog")
	if not T.check(BC and BS and PC, "modules load") then
		return
	end
	local F = BC.Fighter
	T.check(F.BenchRegenPerSecond == 0 and (F.BenchRegenCap or 0) == 0 and BC.Validate and select(1, BC.Validate()) ~= false, "Fighter.BenchRegenPerSecond 0 (and the cap 0); Validate passes")
	-- the healing pets of the plan are Heal-special pets
	local healers = { "honey_bunny", "sleepy_owl", "blossom_bunny", "cherry_panda", "starlight_unicorn" }
	local allHeal = true
	for _, id in ipairs(healers) do
		local def = PC.Get(id)
		if not (def and def.Special and def.Special.Kind == "Heal") then
			allHeal = false
		end
	end
	T.check(allHeal, "honey_bunny / sleepy_owl / blossom_bunny / cherry_panda / starlight_unicorn have Special.Kind Heal")
	-- no regen during a fight and in a dungeon wave gap
	local b = BS.new({ Mode = "Dungeon", Seed = 3, Teams = { team(1, 1, { pet("storm_tabby", 15), pet("pebble_pup", 5), pet("mallow_kitten", 5) }) } })
	local tm = b.teams[1]
	putFighter(tm, 0, 0)
	local b2, b3 = tm.bySlot[2], tm.bySlot[3]
	b2.hp, b3.hp = b2.maxHp * 0.3, b3.maxHp * 0.5
	tm.fighter.hp = tm.fighter.maxHp * 0.4
	stepFor(b, 50) -- 5 s with no enemy at all: the wave gap
	T.check(b2.hp == b2.maxHp * 0.3 and b3.hp == b3.maxHp * 0.5 and tm.fighter.hp == tm.fighter.maxHp * 0.4, "a dungeon wave gap (no enemy, 5 s): nobody heals by themselves")
	b:SpawnEnemies({ pet("pebble_pup", 1, { Handicap = 0.3 }) }, { Wave = 1, Anchor = { 0, 18 } })
	for _, e in ipairs(enemies(b)) do
		passive(e)
	end
	stepFor(b, 50)
	T.check(b2.hp == b2.maxHp * 0.3 and b3.hp == b3.maxHp * 0.5, "during a fight the benched pets do not regenerate")
	-- the Heal special of a player's healer: the fighter AND the benched pets
	local bH = BS.new({ Mode = "Dungeon", Seed = 4, Teams = { team(1, 1, { pet("honey_bunny", 10), pet("pebble_pup", 5), pet("mallow_kitten", 5) }) } })
	local tH = bH.teams[1]
	local fh = tH.fighter
	fh.hp = fh.maxHp * 0.3
	local h2, h3 = tH.bySlot[2], tH.bySlot[3]
	h2.hp, h3.hp = h2.maxHp * 0.2, h3.maxHp * 0.25
	fh.meter = 100
	local okS = bH:Command(1, "Special")
	local sp = find(bH:Step(0.1), "Special")
	local ids = {}
	for _, h in ipairs(sp and sp.heals or {}) do
		ids[h[1]] = h[2]
	end
	T.check(okS and sp and sp.kind == "Heal" and ids[fh.id] and ids[h2.id] and ids[h3.id] and fh.hp > fh.maxHp * 0.3 and h2.hp > h2.maxHp * 0.2 and h3.hp > h3.maxHp * 0.25,
		"a player's Heal special heals the fighter AND both benched pets (Special.heals lists all three)", sp and sp.heals and (#sp.heals .. " heals") or "no Special")
	-- the Heal buff of a benched healer: the fighter and the OTHER benched pet, 30% of each one's max HP
	local bB = BS.new({ Mode = "Dungeon", Seed = 5, Teams = { team(1, 1, { pet("storm_tabby", 10), pet("honey_bunny", 10), pet("pebble_pup", 5) }) } })
	local tB = bB.teams[1]
	local fb, healer, other = tB.fighter, tB.bySlot[2], tB.bySlot[3]
	fb.hp = fb.maxHp * 0.2
	healer.hp = healer.maxHp * 0.5
	other.hp = other.maxHp * 0.1
	local okB, kind = bB:Command(1, "Buff", 2)
	local bev = find(bB:Step(0.1), "Buff")
	local v = BC.Buffs.Heal.Value * (healer.specialBoost or 1)
	T.check(okB and kind == "Heal" and near(fb.hp, fb.maxHp * (0.2 + v), fb.maxHp * 0.01) and near(other.hp, other.maxHp * (0.1 + v), other.maxHp * 0.01) and near(healer.hp, healer.maxHp * 0.5, 1e-6),
		"the Heal buff heals the fighter and the other benched pet by Value x their max HP (not the healer itself)", fmt("%.2f / %.2f", fb.hp / fb.maxHp, other.hp / other.maxHp))
	T.check(bev and type(bev.heals) == "table" and #bev.heals == 2 and bev.target == fb.id, "the Buff event lists heals { { fighter, hp }, { other, hp } }")
	-- a regen element buff still ticks (an active skill)
	local bW = BS.new({ Mode = "Dungeon", Seed = 6, Teams = { team(1, 1, { pet("storm_tabby", 10), pet("bubble_axolotl", 8) }) } })
	local tW = bW.teams[1]
	tW.fighter.hp = tW.fighter.maxHp * 0.3
	local okW, kindW = bW:Command(1, "Buff", 2)
	stepFor(bW, 20)
	T.check(okW and kindW == "Water" and tW.fighter.hp > tW.fighter.maxHp * 0.3 + 0.05 * tW.fighter.maxHp, "the Water Tide Mend regen buff still heals the fighter over time", kindW)
	-- an NPC healer heals its pets on the floor (unchanged)
	local bN = BS.new({ Mode = "Duel", Seed = 7, Teams = { team(1, 1, { pet("pebble_pup", 1) }), team("npc", 2, { pet("honey_bunny", 10), pet("biscuit_bear", 10) }, { Npc = true }) } })
	local nh, nb = bN.units[2], bN.units[3]
	nb.hp = nb.maxHp * 0.3
	nh.hp = nh.maxHp * 0.5
	nh.meter = 100
	nh.autoCastAt = bN:Time()
	local spN = nil
	stepFor(bN, 10, function(e)
		spN = find(e, "Special", function(ev)
			return ev.unit == nh.id
		end)
		return spN ~= nil
	end)
	T.check(spN and spN.kind == "Heal" and nb.hp > nb.maxHp * 0.3, "an NPC healer still heals its pets on the floor")
end)

----------------------------------------------------------------------------------------------------
-- dgfixcore_determinism
----------------------------------------------------------------------------------------------------
S.dgfixcore_determinism = guarded("dgfixcore_determinism", function()
	local BS = loadModule("BattleSim")
	if not T.check(BS ~= nil, "BattleSim loads") then
		return
	end
	local function script(seed)
		local b = BS.new({ Mode = "Dungeon", Seed = seed, TimeLimit = 60, Teams = { team(1, 1, { pet("storm_tabby", 10), pet("honey_bunny", 8), pet("pebble_pup", 8) }), team(2, 1, { pet("aurora_fox", 9) }) } })
		local log = {}
		local wave = 0
		for step = 1, 500 do
			if b:IsFinished() then
				break
			end
			if b:LivingEnemies() == 0 and wave < 3 then
				wave = wave + 1
				b:SpawnEnemies({ pet("maple_fox", 6), pet("pebble_pup", 6) }, { Wave = wave })
			end
			b:Command(1, "Move", math.sin(step * 0.05) * 8, -6 + step * 0.01)
			b:Command(2, "Move", -4, -4)
			if step % 23 == 0 then
				b:Command(1, "Attack")
			end
			if step % 61 == 0 then
				b:Command(2, "Dash")
			end
			if step % 70 == 0 then
				b:Command(1, "Element")
			end
			local events = b:Step(0.1)
			for _, ev in ipairs(events) do
				local keys = {}
				for k in pairs(ev) do
					keys[#keys + 1] = k
				end
				table.sort(keys)
				local parts = {}
				for _, k in ipairs(keys) do
					local val = ev[k]
					if type(val) == "table" then
						val = "#" .. #val
					end
					parts[#parts + 1] = k .. "=" .. tostring(val)
				end
				log[#log + 1] = table.concat(parts, ",")
			end
		end
		local units = {}
		for _, u in ipairs(b.units) do
			units[#units + 1] = fmt("%d:%.3f:%.3f:%.3f", u.id, u.hp, u.x, u.z)
		end
		return table.concat(log, "|") .. "||" .. table.concat(units, ";"), #log
	end
	local a, n = script(11)
	local a2 = script(11)
	local c = script(12)
	T.check(n > 50 and a == a2, "the same setup + commands replay the exact same events and end state (auto-attack, waves, arrival)", n .. " events")
	T.check(a ~= c, "another seed plays out differently")
end)

return S
