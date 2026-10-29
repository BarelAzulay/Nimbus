-- smoke_fight.lua: wave 5 "fight" lane, bugs #16 (F re-targeted the pet off its enemy, the caption read "PIC...", the
-- DEV tile sat on the action cluster) and #22 (the pet stayed glued to a standing player instead of fighting).
-- Spec: .superpowers/bugs-2026-10-24/wave5-fight-spec.md. Loaded by tools/smoke.py in BOTH worlds (ARGS.context).
--   fight_engage_core     (server world, pure) BattleSim's engage rule: FOLLOW -> ENGAGED after the Move point stood
--                         EngageStillSeconds with an enemy within EngageRange of the stand point (the Engage event,
--                         TeamOf.Engaged), the approach at the HONEST legal run (no MoveSlack), the hit lands; a small
--                         sway keeps it, a step > EngagePull drops it the same step (FOLLOW at run x MoveSlack again);
--                         no re-engage while walking, only after EngageCooldown + the still time; a far lock + a near
--                         enemy (engages the near one, the lock kept); a ranged fighter holds at the edge of its range;
--                         a KO'd target -> the next one with no command, none left -> back to the Move point (and the
--                         snapshot target bit = the engaged enemy); EngageLeash; Stunned = no move, still engaged;
--                         Attack() keeps a live lock with NO echo (no cycle), a dead lock -> the nearest, Attack(id) /
--                         Target(id) switch; no Move at all (a dead character) engages from the fighter's point; Swap
--                         drops it, the incoming pet re-engages after its cast; Validate rejects bad Engage numbers;
--                         determinism with a still phase
--   fight_engage_service  (server world, booted) a dungeon encounter: the pet engages an enemy 13 studs from the standing
--                         character, the gap stays > Fighter.Leash for > LeashSeconds + 1 and nobody is leashed (the
--                         leash is off while engaged); the Engage event reaches the client; Attack(id) on a far enemy
--                         still toasts "Too far!" once; a jump + run-off drops the engage (Engage on = false) and the
--                         player is removed within LeashSeconds + 3
--   client_fight_attack   (client world) F tap = ONE Attack(nil) and no Target; F held 0.4 s = exactly one Target(next)
--                         and nothing on release; the ATTACK button (mouse / touch) and ButtonX the same; a held world
--                         click = one Attack(id), never a Target; the caption ATTACK, NEXT for 0.6 s after a hold-cycle;
--                         my fighter's Engage { on = true } hops it and builds no Instance; Me.FighterTarget draws a pet
--                         8 studs out where the server has it (and on the shoulder at my side), on High and Low
--   client_fight_dev      (client world) NC_Dev + a fighting battle HUD: the DEV tile touches none of NimbusBattle.Root's
--   client_fight_dev_mobile (phone world)  visible blocks (>= 4 px clear) and the ATTACK caption is whole on screen
--                         and not under it: 1920x1080, 1366x768, 844x390, 390x844, 749x388 (the phone: 390x844, 844x390,
--                         749x388 with touch)
-- White-box: the server half reaches into battle.units / battle.teams (same Lua state). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, sqrt, huge, max, min = math.abs, math.floor, math.sqrt, math.huge, math.max, math.min
local fmt = string.format

----------------------------------------------------------------------------------------------------
-- the server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function loadModule(name)
		local inst = K.moduleInstance("shared/" .. name)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		if ok and type(result) == "table" then
			return result
		end
		return nil
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

	local function d2(ax, az, bx, bz)
		return sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	local function put(u, x, z)
		u.x, u.z, u.px, u.pz = x, z, x, z
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

	-- a passive, immobile, unkillable enemy that is already on the floor (no arrival)
	local function dummy(u, x, z)
		put(u, x, z)
		u.arriveUntil = nil
		u.iframesUntil = 0
		u.nextAttack = huge
		u.windAt = nil
		u.hit = 0
		u.moveSpeed = 0
		u.maxHp, u.hp = 1e9, 1e9
		u.defense = 0
		return u
	end

	-- a Dungeon sim with my team (owner 1): `key` the fighter, two helpers
	local function world(BS, key, level, seed)
		local b = BS.new({ Mode = "Dungeon", Seed = seed or 5, Zone = 60, Teams = { team(1, 1, { pet(key or "storm_tabby", level or 12), pet("pebble_pup", 5), pet("honey_bunny", 5) }) } })
		return b, b.teams[1]
	end

	-- `n` enemies spawned as one wave, then made dummies at the given points
	local function enemiesAt(b, points, key, level)
		local list = {}
		for i = 1, #points do
			list[i] = pet(key or "biscuit_bear", level or 20)
		end
		local infos = b:SpawnEnemies(list, { Wave = (b.waveCount or 0) + 1, Anchor = { 0, 20 } })
		local out = {}
		for i, info in ipairs(infos or {}) do
			out[i] = dummy(b.units[info.id], points[i][1], points[i][2])
		end
		return out
	end

	-- one 10 Hz step with the Move point (x, z) fed first (BattleService.feedMoves); nil x = no Move (no character)
	local function stepAt(b, x, z)
		if x ~= nil then
			b:Command(1, "Move", x, z)
		end
		return b:Step(0.1)
	end

	-- steps while standing at (x, z) until pred(events, i) or n steps; -> all events, the step count
	local function standFor(b, n, x, z, pred)
		local all = {}
		for i = 1, n do
			local evs = stepAt(b, x, z)
			for _, ev in ipairs(evs) do
				all[#all + 1] = ev
			end
			if pred and pred(evs, i) then
				return all, i
			end
		end
		return all, n
	end

	local function engaged(b)
		local tm = b:TeamOf(1)
		return tm and tm.Engaged
	end

	------------------------------------------------------------------------------------------------
	-- fight_engage_core
	------------------------------------------------------------------------------------------------
	S.fight_engage_core = guarded("fight_engage_core", function()
		local BC = loadModule("BattleCatalog")
		local BS = loadModule("BattleSim")
		if not T.check(BC and BS, "fight core: BattleCatalog + BattleSim load") then
			return
		end
		local F = BC.Fighter
		T.check(F.EngageRange == 14 and F.EngageLeash == 18 and F.EngagePull == 7 and F.EngageStillSeconds == 0.5 and F.EngageCooldown == 0.5
			and BS.Events.Engage == "Engage", "fight core: Fighter.EngageRange 14 / EngageLeash 18 / EngagePull 7 / EngageStillSeconds 0.5 / EngageCooldown 0.5, Events.Engage")

		-- (1) + (2): stand 12 studs from an enemy: engaged after the still time, the approach at the legal run, a hit
		do
			local b, tm = world(BS)
			local f = tm.fighter
			put(f, 0, -10)
			local e = enemiesAt(b, { { 0, 2 } })[1]
			-- walking first (the Move point moves > 0.3 stud a step): no engage
			local walkEngaged = false
			for i = 1, 8 do
				stepAt(b, (i % 2 == 0) and 0.6 or -0.6, -10)
				walkEngaged = walkEngaged or engaged(b) ~= nil
			end
			T.check(not walkEngaged, "fight core (1): while the character walks the pet does not engage (FOLLOW)")
			local t0 = b:Time()
			local evs = standFor(b, 15, 0, -10, function()
				return engaged(b) ~= nil
			end)
			local tEng = b:Time() - t0
			local ev = find(evs, "Engage", function(x)
				return x.on == true
			end)
			T.check(engaged(b) == e.id and tEng >= F.EngageStillSeconds - 0.05 and tEng <= F.EngageStillSeconds + 0.2,
				"fight core (1): standing EngageStillSeconds with an enemy 12 studs off: TeamOf.Engaged = that enemy", fmt("after %.2f s, Engaged %s", tEng, tostring(engaged(b))))
			T.check(ev ~= nil and ev.owner == 1 and ev.unit == f.id and ev.target == e.id, "fight core (1): ...with the Engage { owner, unit, on = true, target } event")
			local run = b:SpeedOf(1).Run
			local reach = f.range + e.radius
			local maxStep, sawFull, hit = 0, false, false
			local lastX, lastZ = f.x, f.z
			for _ = 1, 20 do
				local s = stepAt(b, 0, -10)
				local travel = d2(lastX, lastZ, f.x, f.z)
				lastX, lastZ = f.x, f.z
				maxStep = max(maxStep, travel)
				if travel >= run * 0.1 * 0.9 then
					sawFull = true
				end
				if find(s, "Hit", function(x)
					return x.from == f.id and x.to == e.id and not x.miss
				end) then
					hit = true
				end
			end
			local gap = d2(f.x, f.z, e.x, e.z)
			T.check(gap <= reach + 0.2 and gap >= reach - 0.8, "fight core (1): the pet walks to the enemy (melee: reach - 0.5)", fmt("gap %.2f, reach %.2f", gap, reach))
			T.check(hit, "fight core (1): ...and its auto-attack lands within 2 s")
			T.check(maxStep <= run * 0.1 + 0.02 and sawFull, "fight core (2): the engaged approach runs at the HONEST legal run (<= run x dt per step, no MoveSlack)",
				fmt("max %.3f vs run x dt %.3f", maxStep, run * 0.1))
			T.check(b:Snapshot().Units[f.id].target == e.id, "fight core (1): the snapshot's target bit shows the enemy the pet fights")

			-- (3): a 1 stud sway keeps it; a 6 stud reposition keeps it (player ruling 2026-10-28, EngagePull 7); a walk of
			-- ~7.5 studs = the pull: back to FOLLOW the same step, at run x MoveSlack
			local sway = false
			for _ = 1, 5 do
				stepAt(b, 1, -10)
				sway = sway or engaged(b) ~= e.id
			end
			T.check(not sway, "fight core (3): a Move point 1 stud from the stand point keeps the engage")
			local repos = false
			for i = 1, 10 do
				stepAt(b, 1 + 0.5 * i, -10) -- walks out to 6 studs from the stand point
				repos = repos or engaged(b) ~= e.id
			end
			for _ = 1, 5 do
				stepAt(b, 6, -10)
				repos = repos or engaged(b) ~= e.id
			end
			T.check(not repos, "fight core (3): walking 6 studs from the stand point (< EngagePull 7) keeps the pet in the fight")
			local fx, fz = f.x, f.z
			local pullEvs = stepAt(b, 7.2, -8) -- ~7.5 studs from the stand point (0, -10)
			T.check(engaged(b) == nil and find(pullEvs, "Engage", function(x)
				return x.on == false and x.unit == f.id
			end) ~= nil, "fight core (3): a walk > EngagePull (~7.5 studs) drops it the same step (Engage on = false)")
			local moved = d2(fx, fz, f.x, f.z)
			T.check(moved > run * 0.1 * 1.05 and moved <= run * F.MoveSlack * 0.1 + 0.02, "fight core (3): ...and the pet walks back toward the Move point at today's FOLLOW cap (run x MoveSlack)",
				fmt("%.3f (run x dt %.3f, cap %.3f)", moved, run * 0.1, run * F.MoveSlack * 0.1))

			-- (4): walking keeps FOLLOW (no re-engage while the Move point moves); standing re-engages after cooldown + still
			local walkAgain = false
			for i = 1, 15 do
				stepAt(b, 7.2 + ((i % 2 == 0) and 0.5 or -0.5), -8)
				walkAgain = walkAgain or engaged(b) ~= nil
			end
			T.check(not walkAgain, "fight core (4): no re-engage while the character keeps walking (the still gate)")
			local t1 = b:Time()
			standFor(b, 15, 7.2, -8, function()
				return engaged(b) ~= nil
			end)
			local tRe = b:Time() - t1
			T.check(engaged(b) == e.id and tRe >= F.EngageStillSeconds - 0.05, "fight core (4): standing again re-engages after the still time", fmt("%.2f s", tRe))
			-- the cooldown: a pull and an immediate stand wait EngageCooldown before the next engage
			stepAt(b, 0, -10) -- ~7.5 studs from the stand point (7.2, -8); the enemy stays in EngageRange of the new point
			local tPull = b:Time()
			local coolEarly = false
			for _ = 1, 3 do
				stepAt(b, 0, -10)
				if engaged(b) ~= nil and b:Time() - tPull < F.EngageCooldown - 0.05 then
					coolEarly = true
				end
			end
			T.check(not coolEarly, "fight core (4): no re-engage within EngageCooldown of a disengage")
		end

		-- (5): a far lock and a near enemy: it engages the near one, the lock stays the player's
		do
			local b, tm = world(BS)
			put(tm.fighter, 0, -10)
			local list = enemiesAt(b, { { 0, 10 }, { 0, -4 } }) -- 20 and 6 studs from the stand point
			b:Command(1, "Target", list[1].id)
			standFor(b, 10, 0, -10)
			T.check(engaged(b) == list[2].id and b:TeamOf(1).Lock == list[1].id, "fight core (5): a lock 20 studs off + an enemy 6 studs off: engages the near one, TeamOf.Lock unchanged",
				tostring(engaged(b)) .. " / lock " .. tostring(b:TeamOf(1).Lock))
		end

		-- (6): a ranged fighter holds at the edge of its range
		do
			local b, tm = world(BS, "puddle_frog", 12)
			local f = tm.fighter
			put(f, 0, -10)
			local e = enemiesAt(b, { { 0, 4 } })[1] -- 14 studs
			local edge = f.range + e.radius
			local minGap = huge
			for _ = 1, 30 do
				stepAt(b, 0, -10)
				minGap = min(minGap, d2(f.x, f.z, e.x, e.z))
			end
			T.check(f.ranged and engaged(b) == e.id and minGap >= edge - 1.5 and minGap <= edge, "fight core (6): a ranged fighter engages and holds at its range (never closer than range + radius - 1.5)",
				fmt("ranged %s, min gap %.2f, range + radius %.2f", tostring(f.ranged), minGap, edge))
		end

		-- (7): the engaged target KO'd -> the next one in range with no command; none left -> back to the Move point
		do
			local b, tm = world(BS)
			local f = tm.fighter
			put(f, 0, -10)
			local list = enemiesAt(b, { { 0, -2 }, { 4, -1 } }) -- 8 and ~9.8 studs
			standFor(b, 10, 0, -10)
			T.check(engaged(b) == list[1].id, "fight core (7): (setup) engaged on the nearest", tostring(engaged(b)))
			local e1, e2 = list[1], list[2]
			e1.maxHp, e1.hp = 100, 1
			f.nextAttack = 0
			standFor(b, 15, 0, -10, function()
				return not e1.alive
			end)
			stepAt(b, 0, -10)
			T.check(not e1.alive and engaged(b) == e2.id and b:TeamOf(1).Lock == nil, "fight core (7): the target falls: the pet takes the next enemy in range by itself (no command)",
				tostring(engaged(b)))
			T.check(b:Snapshot().Units[f.id].target == e2.id, "fight core (7): ...and the snapshot target (no lock) is the engaged enemy")
			e2.maxHp, e2.hp = 100, 1
			f.nextAttack = 0
			standFor(b, 30, 0, -10, function()
				return not e2.alive
			end)
			standFor(b, 20, 0, -10)
			T.check(not e2.alive and engaged(b) == nil and d2(f.x, f.z, 0, -10) < 0.5, "fight core (7): none left in range: Engaged nil and the pet is back at the Move point",
				fmt("%.2f studs off", d2(f.x, f.z, 0, -10)))
		end

		-- (8): EngageLeash: a pet > 18 studs from the stand point drops the engage (the target still in range)
		do
			local b, tm = world(BS)
			local f = tm.fighter
			put(f, 0, -2)
			local e = enemiesAt(b, { { 0, 11 } })[1] -- 13 studs
			standFor(b, 8, 0, -2)
			T.check(engaged(b) == e.id, "fight core (8): (setup) engaged")
			put(f, 0, -21) -- 19 studs from the stand point (white-box)
			local evs = stepAt(b, 0, -2)
			T.check(engaged(b) == nil and find(evs, "Engage", function(x)
				return x.on == false
			end) ~= nil, "fight core (8): beyond EngageLeash from the stand point the pet drops the engage (Engage on = false)")
		end

		-- (9): Stunned: no move, still engaged
		do
			local b, tm = world(BS)
			local f = tm.fighter
			put(f, 0, -10)
			enemiesAt(b, { { 0, 2 } })
			standFor(b, 15, 0, -10, function()
				return engaged(b) ~= nil
			end)
			f.stunUntil = b:Time() + 0.5
			local x0, z0 = f.x, f.z
			for _ = 1, 4 do
				stepAt(b, 0, -10)
			end
			T.check(engaged(b) ~= nil and d2(x0, z0, f.x, f.z) < 1e-6, "fight core (9): a stunned engaged pet stands (cap 0) and stays engaged")
			standFor(b, 6, 0, -10)
			T.check(d2(x0, z0, f.x, f.z) > 0.5, "fight core (9): ...and walks on when the stun ends")
		end

		-- (10): Attack() keeps a live lock in EngageRange (no echo); a dead lock -> the nearest; Attack(id) / Target(id) switch
		do
			local b, tm = world(BS)
			local f = tm.fighter
			put(f, 0, -10)
			tm.wantX, tm.wantZ = 0, -10
			local list = enemiesAt(b, { { 0, -4 }, { 0, 0 }, { 6, -10 } }) -- 6, 10, 6 studs (ids break the tie)
			b:Step(0.1)
			local ok1, id1 = b:Command(1, "Attack")
			local e1 = b:Step(0.1)
			local ok2, id2 = b:Command(1, "Attack")
			local e2 = b:Step(0.1)
			T.check(ok1 and ok2 and id1 == id2 and tm.lock and tm.lock.id == id1 and count(e1, "Order", function(x)
				return x.order == "Attack"
			end) == 1, "fight core (10): Attack() locks the nearest (one echo)", tostring(id1) .. " / " .. tostring(id2))
			T.check(count(e2, "Order") == 0, "fight core (10): a second Attack() on the live lock keeps it and sends NO Order echo (no cycle, no traffic)")
			local ok3, id3 = b:Command(1, "Attack")
			T.check(ok3 and id3 == id1, "fight core (10): ...a third press too (the lock never cycles)", tostring(id3))
			-- the lock falls -> Attack() locks the nearest of the rest
			local lock = tm.lock
			lock.alive, lock.hp = false, 0
			local okN, idN = b:Command(1, "Attack")
			local nearest, nd = nil, huge
			for _, e in ipairs(list) do
				if e.alive then
					local dd = d2(f.x, f.z, e.x, e.z)
					if dd < nd or (dd == nd and e.id < nearest.id) then
						nearest, nd = e, dd
					end
				end
			end
			T.check(okN and nearest and idN == nearest.id, "fight core (10): a dead lock: Attack() locks the nearest living enemy", tostring(idN))
			local other = nil
			for _, e in ipairs(list) do
				if e.alive and e.id ~= idN then
					other = e
				end
			end
			local okI, idI = b:Command(1, "Attack", other.id)
			T.check(okI and idI == other.id and tm.lock == other, "fight core (10): Attack(id) switches the lock (the deliberate path)")
			local okT = b:Command(1, "Target", idN)
			T.check(okT and tm.lock and tm.lock.id == idN, "fight core (10): Target(id) switches it too (Tab / RT / hold-F)")
			-- a lock beyond EngageRange of the fighter: Attack() takes the nearest instead
			put(other, 0, 26)
			b:Command(1, "Target", other.id)
			local okF, idF = b:Command(1, "Attack")
			T.check(okF and idF ~= other.id, "fight core (10): a lock beyond EngageRange: Attack() locks the nearest", tostring(idF))
		end

		-- (11): no Move at all (a dead character): engages from the fighter's own point
		do
			local b, tm = world(BS)
			local f = tm.fighter
			put(f, 0, 0)
			tm.wantX, tm.wantZ = nil, nil
			local e = enemiesAt(b, { { 0, 8 } })[1]
			standFor(b, 10, nil, nil)
			T.check(engaged(b) == e.id and tm.engage and abs(tm.engage.standX) < 1e-6 and abs(tm.engage.standZ) < 1e-6, "fight core (11): no Move ever (no character): the pet engages from its own point")
		end

		-- (12): Swap drops the engage; the incoming pet re-engages after its cast + the still time
		do
			local b, tm = world(BS)
			put(tm.fighter, 0, -10)
			local e = enemiesAt(b, { { 0, -2 } })[1]
			standFor(b, 10, 0, -10)
			T.check(engaged(b) == e.id, "fight core (12): (setup) engaged")
			tm.swapReadyAt = 0
			b:Command(1, "Swap", 2)
			local tSwap = b:Time()
			local evs = stepAt(b, 0, -10)
			T.check(engaged(b) == nil and find(evs, "Engage", function(x)
				return x.on == false
			end) ~= nil and find(evs, "Swap") ~= nil, "fight core (12): Swap drops the engage (Engage on = false)")
			standFor(b, 20, 0, -10, function()
				return engaged(b) ~= nil
			end)
			local tRe = b:Time() - tSwap
			T.check(engaged(b) == e.id and tm.engage.unit == tm.fighter.id and tRe >= F.SwapCastSeconds - 0.05 and tRe <= F.SwapCastSeconds + F.EngageStillSeconds + 0.3,
				"fight core (12): ...the incoming pet re-engages after its cast", fmt("%.2f s", tRe))
		end

		-- (13): Validate rejects bad Engage numbers
		do
			local function rejects(key, value)
				local old = F[key]
				F[key] = value
				local ok = BC.Validate()
				F[key] = old
				return ok == false
			end
			T.check(rejects("EngageRange", 0) and rejects("EngageLeash", 10) and rejects("EngagePull", 14) and rejects("EngageStillSeconds", 3) and rejects("EngageCooldown", -1),
				"fight core (13): Validate rejects EngageRange 0, EngageLeash < EngageRange, EngagePull >= EngageRange, EngageStillSeconds > 2, a negative cooldown")
			T.check(BC.Validate() == true, "fight core (13): ...and passes with the shipped numbers")
		end

		-- (14): determinism with a still phase
		do
			local function play(seed)
				local b = BS.new({ Mode = "Dungeon", Seed = seed, Zone = 60, Teams = { team(1, 1, { pet("storm_tabby", 12), pet("pebble_pup", 5), pet("honey_bunny", 5) }) } })
				b:SpawnEnemies({ pet("biscuit_bear", 8), pet("honey_bunny", 8), pet("puddle_frog", 8) }, { Wave = 1, Anchor = { 0, 8 } })
				local log = {}
				for i = 1, 220 do
					local x, z = -6 + (i % 40) * 0.3, -12
					if (i >= 30 and i < 50) or (i >= 120 and i < 160) then
						x, z = 0, -6 -- standing: the engage rule plays
					end
					b:Command(1, "Move", x, z)
					if i % 37 == 0 then
						b:Command(1, "Attack")
					end
					local evs = b:Step(0.1)
					for _, ev in ipairs(evs) do
						log[#log + 1] = tostring(ev.type) .. ":" .. tostring(ev.unit or ev.from) .. ":" .. tostring(ev.on) .. ":" .. tostring(ev.target or ev.to)
					end
					local snap = b:Snapshot()
					local ids = {}
					for id in pairs(snap.Units) do
						ids[#ids + 1] = id
					end
					table.sort(ids)
					for _, id in ipairs(ids) do
						local u = snap.Units[id]
						log[#log + 1] = fmt("%d:%.1f,%.1f,%d,%d,%s", id, u.x, u.z, u.hp, u.state, tostring(u.target))
					end
					if b:IsFinished() then
						break
					end
				end
				return table.concat(log, "\n")
			end
			local a, a2, c = play(77), play(77), play(78)
			T.check(a == a2 and a:find("Engage:", 1, true) ~= nil, "fight core (14): the same seed + Move stream (still phases included) replays identical events and snapshots, with Engage flips")
			T.check(a ~= c, "fight core (14): another seed plays differently")
		end
	end)

	------------------------------------------------------------------------------------------------
	-- fight_engage_service (booted)
	------------------------------------------------------------------------------------------------
	local ALLOWED_WARNINGS = { "[BattleService]", "[DataService]", "[TycoonService]", "[PetCareService]", "[EventService]", "[MeshLibrary]" }
	local seq = 0

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

	-- the BattleService battle record (white-box: the service's St is an upvalue of IsInBattle)
	local function battleOf(bs, battleId)
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

	local function eventsOf(p, fromIndex, evType)
		local out = {}
		local log = Mock.RemoteLog
		for i = (fromIndex or 0) + 1, #log do
			local e = log[i]
			if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and e.args[1] == "Events" then
				for _, ev in ipairs(e.args[2]) do
					if evType == nil or ev.type == evType then
						out[#out + 1] = ev
					end
				end
			end
		end
		return out
	end

	S.fight_engage_service = guarded("fight_engage_service", function()
		if not K.needBoot() then
			return
		end
		local bs, data, bc = req("server/Services/BattleService"), req("server/Services/DataService"), req("shared/BattleCatalog")
		if not T.check(bs and data and bc and type(bs.OpenEncounter) == "function", "fight svc: BattleService / DataService / BattleCatalog load") then
			return
		end
		local F = bc.Fighter
		local advance = K.advance
		seq = seq + 1
		local pets = { "pebble_pup", "honey_bunny", "maple_fox" }
		local p = Mock.AddPlayer("FightSvc" .. seq, 968100 + seq)
		advance(1.0)
		local prof = data.GetProfile(p)
		for _, id in ipairs(pets) do
			prof.Pets[id] = (prof.Pets[id] or 0) + 1
			prof.PetLevels[id] = { Level = 20, Xp = 0 }
		end
		data.MarkDirty(p)
		data.SetTeam(p, 1, pets)
		-- a 160 zone far out in the sky (the run-off below stays inside it)
		local part = Instance.new("Part")
		part.Name = "NC_BattleZone"
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.Size = Vector3.new(160, 2, 160)
		part.CFrame = CFrame.new(5200, 600, -2500)
		part:SetAttribute("Mode", "Dungeon")
		part.Parent = workspace
		local left = {}
		local spec = { Mode = "Dungeon", Zone = part, Seed = 4343, TimeLimit = 300, Label = "fight", Teams = { { Player = p } }, Extra = { Floor = 1, Room = 1, Wave = 1, Waves = 1, Name = "Fight Room" },
			KeepInBattle = true, OnLeave = function(...)
				left[#left + 1] = { ... }
			end }
		local function place(x, z)
			Mock.Teleport(p, CFrame.new(part.CFrame:PointToWorldSpace(Vector3.new(x, 3, z))))
		end
		place(0, -10)
		advance(0.05)
		local mark = K.logSize()
		local id, why = bs.OpenEncounter(spec)
		advance(0.3)
		local b = battleOf(bs, id)
		local sim = b and b.Sim
		local tm = sim and sim.teamByOwner and sim.teamByOwner[p.UserId]
		if not T.check(type(id) == "string" and tm ~= nil, "fight svc: (setup) a solo dungeon encounter, its sim reachable", tostring(why)) then
			part:Destroy()
			K.removePlayers({ p })
			return
		end
		local f = tm.fighter
		-- the pet joins the standing character, then one immobile, passive enemy 13 studs away
		local t0 = Mock.Clock.now
		while Mock.Clock.now - t0 < 6 and d2(f.x, f.z, 0, -10) > 1 do
			advance(0.2)
		end
		local infos = bs.SpawnWave(id, { { PetId = "biscuit_bear", Level = 30 } }, { Wave = 1, Name = "W1" })
		local e = infos and infos[1] and sim.units[infos[1].id]
		if not T.check(e ~= nil, "fight svc: (setup) SpawnWave") then
			bs.FinishEncounter(id, "Abandoned")
			part:Destroy()
			K.removePlayers({ p })
			return
		end
		dummy(e, 0, 3)
		f.range = 1 -- white-box: a short reach, so the engaged pet stands > Leash (10) from its standing owner
		local mark1 = K.logSize()
		local maxGap, wasEngaged, engagedTicks = 0, false, 0
		local tStand = Mock.Clock.now
		while Mock.Clock.now - tStand < F.LeashSeconds + 2 do
			place(0, -10)
			advance(0.1)
			if type(tm.engage) == "table" then
				wasEngaged = true
				engagedTicks = engagedTicks + 1
				maxGap = max(maxGap, d2(f.x, f.z, 0, -10))
			end
		end
		T.check(wasEngaged and maxGap > F.Leash, "fight svc: standing 13 studs from an enemy, the pet engages and fights > Leash from its owner", fmt("max gap %.1f", maxGap))
		T.check(#left == 0 and bs.IsInBattle(p) and engagedTicks * 0.1 > F.LeashSeconds + 1, "fight svc: ...for > LeashSeconds + 1 and NOBODY is leashed (the leash is off while engaged)",
			fmt("%d OnLeave, engaged %.1f s", #left, engagedTicks * 0.1))
		local evOn = nil
		for _, ev in ipairs(eventsOf(p, mark, "Engage")) do
			if ev.on == true and ev.owner == p.UserId and ev.target == e.id then
				evOn = ev
			end
		end
		T.check(evOn ~= nil, "fight svc: the Engage { on = true, target } event reaches the client's Events")
		-- Attack(id) on a far enemy still answers "Too far!" once
		local infos2 = bs.SpawnWave(id, { { PetId = "honey_bunny", Level = 5 } }, { Wave = 2, Name = "W2" })
		local far = infos2 and infos2[1] and sim.units[infos2[1].id]
		if T.check(far ~= nil, "fight svc: (setup) a second wave far away") then
			dummy(far, 60, 60)
			advance(0.2)
			advance(3.2) -- (the refusal toasts share a 3 s throttle)
			local mT = K.logSize()
			Mock.FromClient(K.remoteFolder():FindFirstChild("BattleCommand"), p, "Attack", far.id)
			advance(0.3)
			local n = 0
			for _, en in ipairs(K.remotesFor("Notify", p.UserId, mT)) do
				if tostring(en.args[1]):find("Too far", 1, true) then
					n = n + 1
				end
			end
			T.check(n == 1, "fight svc: Attack(id) on a far enemy still toasts \"Too far!\" once", n .. " toasts")
		end
		-- a jump + a run-off: the pull drops the engage, then the FOLLOW leash removes the player
		local mark2 = K.logSize()
		local run = (sim:SpeedOf(p.UserId) or { Run = 16 }).Run
		local fx, fz = f.x, f.z
		local leftAt = nil
		local t1 = Mock.Clock.now
		for i = 1, 80 do
			place(fx + 45 + run * 0.1 * i * 0.5, fz)
			advance(0.1)
			if #left > 0 then
				leftAt = Mock.Clock.now - t1
				break
			end
		end
		local off = nil
		for _, ev in ipairs(eventsOf(p, mark2, "Engage")) do
			if ev.on == false then
				off = ev
			end
		end
		T.check(off ~= nil, "fight svc: the character's jump drops the engage (Engage on = false reaches the client)")
		local cause = left[1] and left[1][3]
		T.check(leftAt ~= nil and leftAt <= F.LeashSeconds + 3 and not bs.IsInBattle(p) and (cause == "Leash" or cause == "Left"),
			"fight svc: ...and the FOLLOW leash removes a run-off within LeashSeconds + 3 (anti-teleport kept)", fmt("after %.1f s, cause %s", leftAt or -1, tostring(cause)))
		bs.FinishEncounter(id, "Abandoned")
		advance(0.3)
		part:Destroy()
		K.removePlayers({ p })
		advance(3)
		K.flushErrors("fight_engage_service")
		K.flushWarnings("fight_engage_service", ALLOWED_WARNINGS)
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- the client worlds
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local LocalPlayer = Players.LocalPlayer

	local H = {}

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

	-- combat pets of the catalog with different specials
	function H.team(n, skip, level)
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
					if #out >= n then
						break
					end
				end
			end
		end
		return out
	end

	-- a BattleSim driven the way BattleService sends it (Start, then the Wave, Events + Snapshot each step); my
	-- BattleCommand calls are forwarded into the sim unless noForward
	local Driver = {}
	Driver.__index = Driver

	function H.dungeon()
		local Sim = H.moduleAt("shared", "BattleSim")
		if not Sim then
			return nil
		end
		local id = "fight_" .. tostring(math.random(100000, 999999))
		local sim = Sim.new({ Mode = "Dungeon", Seed = 9, Id = id, Zone = { X = 44, Z = 44 }, TimeLimit = 300,
			Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = H.team(3, 0, 14) } } })
		if not sim then
			return nil
		end
		return setmetatable({ sim = sim, id = id, zoneCF = CFrame.new(0, 200, 0), logIndex = #Mock.RemoteLog, me = LocalPlayer.UserId,
			dungeon = { Floor = 2, Room = 1, Wave = 1, Waves = 3, Name = "Ember Hall", Element = "Flame" } }, Driver)
	end

	function Driver:start()
		local p = self.sim:Describe()
		p.BattleId = self.id
		p.Zone = { CFrame = self.zoneCF, Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
		p.Names = { [tostring(self.me)] = LocalPlayer.Name }
		p.Side = 1
		p.Spectator = false
		p.T = self.sim:Time()
		p.Dungeon = self.dungeon
		local team = self.sim:TeamOf(self.me)
		p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
			Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = {} } }
		LocalPlayer:SetAttribute("InBattle", self.id)
		KC.toClient("BattleState", "Start", p, self.id)
	end

	function Driver:spawn(n)
		local wave = H.team(n, 3, 10)
		for _, e in ipairs(wave) do
			e.Slot = nil
			e.Wild = true
		end
		return self.sim:SpawnEnemies(wave, { Wave = 1, Anchor = { 0, 10 } })
	end

	function Driver:step(fps)
		if self.noForward then
			self.logIndex = #Mock.RemoteLog
		else
			for _, c in ipairs(H.commands(self.logIndex)) do
				pcall(self.sim.Command, self.sim, self.me, c.action, c.arg)
			end
			self.logIndex = #Mock.RemoteLog
		end
		local evs = self.sim:Step(0.1)
		if #evs > 0 then
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

	function H.cleanup(BC, d)
		if d and BC.GetBattle() then
			KC.toClient("BattleState", "End", { BattleId = d.id, Mode = "Dungeon", Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }, d.id)
		end
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
		local r = H.find("Root.ResultCard.Body.OkButton")
		if r and r.Visible then
			Mock.Click(r)
		end
		Mock.Step(0.1)
	end

	local function contains(list, v)
		for _, x in ipairs(list) do
			if x == v then
				return true
			end
		end
		return false
	end

	-- a fighting dungeon HUD with 3 enemies on the floor (they stay passive and unkillable)
	local function fighting(BC)
		local d = H.dungeon()
		if not d then
			return nil
		end
		d:start()
		d:step(30)
		local infos = d:spawn(3)
		for _, info in ipairs(infos or {}) do
			local u = d.sim.units[info.id]
			u.nextAttack, u.hit, u.maxHp, u.hp, u.moveSpeed = huge, 0, 1e9, 1e9, 0
		end
		d:run(1.6, 30)
		return d
	end

	------------------------------------------------------------------------------------------------
	-- client_fight_attack
	------------------------------------------------------------------------------------------------
	S.client_fight_attack = guarded("client_fight_attack", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		if not T.check(BC ~= nil, "fight client: BattleController loads") then
			return
		end
		local err0 = #Mock.Errors
		local d = fighting(BC)
		if not T.check(d ~= nil and BC.GetBattle() ~= nil, "fight client: (setup) a fighting dungeon HUD") then
			return
		end
		local ids = d:enemyIds()
		local function press(name, key, kind, seconds)
			Mock.TriggerAction(name, "Begin", Mock.NewInput(key, kind, "Begin"))
			H.step(max(1, floor(seconds * 30 + 0.5)), 1 / 30)
			Mock.TriggerAction(name, "End", Mock.NewInput(key, kind, "End"))
		end
		-- a tap of F: ONE Attack(nil), no Target
		d.noForward = true
		local idx = #Mock.RemoteLog
		press("NimbusBattleAttack", "F", "Keyboard", 0.2)
		H.step(30, 1 / 30)
		local cmds = H.commands(idx)
		T.check(#cmds == 1 and cmds[1].action == "Attack" and cmds[1].arg == nil and H.count(idx, "Target") == 0, "fight client: a tap of F sends ONE Attack() and no Target", #cmds .. " sent")
		-- forward it: the server locks the nearest and echoes it (the client's lock)
		d.noForward = false
		d.logIndex = idx
		d:run(0.4, 30)
		local lock = BC.GetBattle().Lock
		T.check(lock ~= nil and contains(ids, lock), "fight client: (setup) the echo sets my lock", tostring(lock))
		-- F held 0.5 s: the Attack at once + exactly ONE Target(next) at 0.4 s, nothing on release
		d.noForward = true
		H.step(10, 1 / 30)
		idx = #Mock.RemoteLog
		Mock.TriggerAction("NimbusBattleAttack", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
		H.step(9, 1 / 30) -- 0.3 s: not yet
		local early = H.count(idx, "Target")
		H.step(5, 1 / 30) -- 0.47 s
		local cap = H.find("Root.Commands.AttackButton.Caption")
		local capHold = cap and cap.Text
		Mock.TriggerAction("NimbusBattleAttack", "End", Mock.NewInput("F", "Keyboard", "End"))
		local idxRel = #Mock.RemoteLog
		H.step(30, 1 / 30)
		cmds = H.commands(idx)
		local target = nil
		for _, c in ipairs(cmds) do
			if c.action == "Target" then
				target = c.arg
			end
		end
		T.check(early == 0 and H.count(idx, "Attack") == 1 and H.count(idx, "Target") == 1 and target ~= nil and target ~= lock and contains(ids, target),
			"fight client: F held >= 0.4 s = ONE Attack + exactly ONE Target(the NEXT enemy), none before 0.4 s", fmt("%d cmds, early %d, target %s (lock %s)", #cmds, early, tostring(target), tostring(lock)))
		T.check(#H.commands(idxRel) == 0, "fight client: ...and nothing on the release")
		T.check(capHold == "NEXT", "fight client: the caption flashes NEXT after a hold-cycle", tostring(capHold))
		H.step(15, 1 / 30)
		T.check(cap and cap.Text == "ATTACK", "fight client: ...and reads ATTACK again after NEXT_FLASH", cap and cap.Text or "nil")
		-- the ATTACK button (mouse and touch) and the gamepad X: the same gesture
		local btn = H.find("Root.Commands.AttackButton")
		local function onBtn()
			local a, s = btn.AbsolutePosition, btn.AbsoluteSize
			return Vector3.new(a.X + s.X / 2, a.Y + s.Y / 2, 0)
		end
		local function buttonHold(kind, seconds)
			Mock.FireSignal(btn, "InputBegan", Mock.NewInput("Unknown", kind, "Begin", { Position = onBtn() }), false)
			H.step(max(1, floor(seconds * 30 + 0.5)), 1 / 30)
			Mock.FireSignal(btn, "InputEnded", Mock.NewInput("Unknown", kind, "End", { Position = onBtn() }), false)
			H.step(20, 1 / 30)
		end
		local okButtons = btn ~= nil
		local detail = {}
		for _, kind in ipairs({ "MouseButton1", "Touch" }) do
			if btn then
				idx = #Mock.RemoteLog
				buttonHold(kind, 0.15)
				local a1, t1 = H.count(idx, "Attack"), H.count(idx, "Target")
				H.step(10, 1 / 30)
				idx = #Mock.RemoteLog
				buttonHold(kind, 0.6)
				local a2, t2 = H.count(idx, "Attack"), H.count(idx, "Target")
				detail[#detail + 1] = fmt("%s tap %d/%d hold %d/%d", kind, a1, t1, a2, t2)
				okButtons = okButtons and a1 == 1 and t1 == 0 and a2 == 1 and t2 == 1
				H.step(10, 1 / 30)
			end
		end
		T.check(okButtons, "fight client: the ATTACK button: a tap = one Attack, a 0.4 s hold = one Attack + one Target (mouse and touch)", table.concat(detail, "; "))
		-- a slide off the ATTACK button within 0.4 s: no re-target (the button's own InputEnded never fires)
		local slideOk, slideDetail = btn ~= nil, {}
		for _, kind in ipairs({ "Touch", "MouseButton1" }) do
			if btn then
				-- (a) the thumb slides off and stays down past 0.4 s
				idx = #Mock.RemoteLog
				local inp = Mock.NewInput("Unknown", kind, "Begin", { Position = onBtn() })
				Mock.FireSignal(btn, "InputBegan", inp, false)
				H.step(4, 1 / 30)
				inp.Position = onBtn() + Vector3.new(-260, -220, 0)
				inp.UserInputState = Enum.UserInputState.Change
				H.step(20, 1 / 30)
				local tA = H.count(idx, "Target")
				inp.UserInputState = Enum.UserInputState.End
				Mock.FireSignal(UserInputService, "InputEnded", inp, false)
				H.step(10, 1 / 30)
				-- (b) it slides off and lifts off the button at 0.2 s (only the global InputEnded fires); then 0.6 s more
				idx = #Mock.RemoteLog
				inp = Mock.NewInput("Unknown", kind, "Begin", { Position = onBtn() })
				Mock.FireSignal(btn, "InputBegan", inp, false)
				H.step(6, 1 / 30)
				inp.UserInputState = Enum.UserInputState.End
				Mock.FireSignal(UserInputService, "InputEnded", inp, false)
				H.step(20, 1 / 30)
				local tB = H.count(idx, "Target")
				slideDetail[#slideDetail + 1] = fmt("%s stay-down %d, lift-off %d", kind, tA, tB)
				slideOk = slideOk and tA == 0 and tB == 0
				H.step(10, 1 / 30)
			end
		end
		T.check(slideOk, "fight client: a touch / click slid off the ATTACK button within 0.4 s never re-targets (held off it, or released off it)", table.concat(slideDetail, "; "))
		idx = #Mock.RemoteLog
		press("NimbusBattleAttack", "ButtonX", "Gamepad1", 0.15)
		H.step(20, 1 / 30)
		local xa, xt = H.count(idx, "Attack"), H.count(idx, "Target")
		H.step(10, 1 / 30)
		idx = #Mock.RemoteLog
		press("NimbusBattleAttack", "ButtonX", "Gamepad1", 0.6)
		H.step(20, 1 / 30)
		T.check(xa == 1 and xt == 0 and H.count(idx, "Attack") == 1 and H.count(idx, "Target") == 1, "fight client: gamepad X: tap = Attack, hold = Attack + Target(next)",
			fmt("tap %d/%d hold %d/%d", xa, xt, H.count(idx, "Attack"), H.count(idx, "Target")))
		-- a held world click on an enemy: one Attack(id), never a Target
		local vp = Mock.Viewport
		idx = #Mock.RemoteLog
		Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin", { Position = Vector3.new(vp.X / 2, vp.Y / 2 - 36, 0) }), false)
		H.step(24, 1 / 30)
		Mock.FireSignal(UserInputService, "InputEnded", Mock.NewInput("Unknown", "MouseButton1", "End", { Position = Vector3.new(vp.X / 2, vp.Y / 2 - 36, 0) }))
		H.step(10, 1 / 30)
		cmds = H.commands(idx)
		T.check(#cmds == 1 and cmds[1].action == "Attack" and contains(ids, cmds[1].arg), "fight client: a world click held 0.8 s = ONE Attack(its id), never a Target", #cmds .. " sent")
		-- my fighter's Engage { on = true }: the hop, no Instance
		d.noForward = false
		d.logIndex = #Mock.RemoteLog
		local fid = BC.GetBattle().FighterId
		-- (white-box: the sim's pets hold their swings and the pet stays put, so the window below carries no Hit / effect)
		local simTeam = d.sim.teams[1]
		for _, su in ipairs(simTeam.units) do
			su.nextAttack = huge
		end
		simTeam.disengagedAt = huge
		simTeam.engage = nil
		d:run(1.5, 30)
		local u = BC._Unit(fid)
		if u then
			u.hopAt = nil
		end
		local function instances()
			local n = #workspace:GetDescendants()
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			return n + (pg and #pg:GetDescendants() or 0)
		end
		local n0 = instances()
		-- the server's Engage arrives with the next step's events (render clock), like BattleService sends it
		local realStep = d.sim.Step
		local injected = false
		d.sim.Step = function(self, dt)
			local evs = realStep(self, dt)
			if not injected then
				injected = true
				evs[#evs + 1] = { type = "Engage", owner = LocalPlayer.UserId, unit = fid, on = true, target = ids[1] }
			end
			return evs
		end
		local hopped = false
		for _ = 1, 8 do
			d:step(30)
			local uu = BC._Unit(fid)
			if uu and uu.hopAt ~= nil then
				hopped = true
			end
		end
		d.sim.Step = nil -- (back to the metatable's Step)
		T.check(hopped and instances() <= n0, "fight client: my fighter's Engage { on = true } plays the arrival hop and builds no Instance", fmt("hop %s, instances %d -> %d", tostring(hopped), n0, instances()))
		-- Me.FighterTarget: an engaged pet 8 studs out is drawn where the server has it; at my side on the shoulder
		local Me = BC._Me
		local root = Mock.GetRoot(LocalPlayer)
		local GQ = H.moduleAt("client", "GraphicsQuality")
		if T.check(Me and type(Me.FighterTarget) == "function" and root ~= nil, "fight client: (setup) Me.FighterTarget + my character") then
			local K = { SHOULDER = Vector3.new(1.8, 0.5, 0.6) }
			local fakeB = { basis = { 0, 200, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 } }
			local fakeU = { centerY = 1.5 }
			for _, quality in ipairs({ "High", "Low" }) do
				if GQ and type(GQ.Apply) == "function" then
					GQ.Apply(quality)
				end
				root.CFrame = CFrame.new(0, 203, 0)
				local far = Me.FighterTarget(fakeB, fakeU, 8, 0)
				local side = Me.FighterTarget(fakeB, fakeU, 0, 0)
				local shoulder = root.CFrame:PointToWorldSpace(K.SHOULDER)
				local farOff = sqrt((far.X - 8) ^ 2 + far.Z ^ 2)
				T.check(farOff <= 0.3 and abs(far.Y - 201.5) <= 0.3, "fight client (" .. quality .. "): the server point 8 studs out is drawn there (xz within 0.3)", fmt("%.2f studs off, y %.2f", farOff, far.Y))
				T.check((side - shoulder).Magnitude <= 0.01, "fight client (" .. quality .. "): at my side the pet sits on the shoulder as before", fmt("%.3f", (side - shoulder).Magnitude))
				-- halfway into the blend (BLEND_DIST 2: 1 stud out, k = 0.5) the height is server + (root + shoulder - server) x k
				local half = Me.FighterTarget(fakeB, fakeU, 1, 0)
				local wantY = 201.5 + (203 + K.SHOULDER.Y - 201.5) * 0.5
				T.check(abs(half.Y - wantY) <= 0.02, "fight client (" .. quality .. "): halfway (k = 0.5) the shoulder height is scaled by k once, not k^2", fmt("y %.3f, want %.3f", half.Y, wantY))
			end
			if GQ and type(GQ.Apply) == "function" then
				GQ.Apply("High")
			end
		end
		H.cleanup(BC, d)
		T.check(#Mock.Errors == err0, "fight client: no script errors", tostring(#Mock.Errors - err0))
		KC.flushErrors("client_fight_attack")
	end)

	------------------------------------------------------------------------------------------------
	-- client_fight_dev / client_fight_dev_mobile
	------------------------------------------------------------------------------------------------
	local function rectOf(inst)
		local g = inst:FindFirstAncestorOfClass("ScreenGui")
		local dy = (g and g.IgnoreGuiInset) and -(Mock.TopInset or 0) or 0
		local p, s = inst.AbsolutePosition, inst.AbsoluteSize
		return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
	end

	local function touches(a, b, gap)
		return a.x0 < b.x1 + gap and a.x1 > b.x0 - gap and a.y0 < b.y1 + gap and a.y1 > b.y0 - gap
	end

	local function named(root, name)
		for _, dsc in ipairs(root and root:GetDescendants() or {}) do
			if dsc.Name == name then
				return dsc
			end
		end
		return nil
	end

	local function shownIn(obj)
		local cur = obj
		while cur and not cur:IsA("ScreenGui") do
			if cur:IsA("GuiObject") and not cur.Visible then
				return false
			end
			cur = cur.Parent
		end
		return cur ~= nil and cur.Enabled
	end

	local function devCheck(label, sizes, restore)
		local BC = H.moduleAt("client", "Controllers/BattleController")
		local Dev = H.moduleAt("client", "Controllers/DevController")
		if not T.check(BC ~= nil and Dev ~= nil and type(Dev.Relayout) == "function", label .. ": BattleController + DevController load") then
			return
		end
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		pg:SetAttribute("NC_Dev", true)
		Mock.Advance(1)
		local d = fighting(BC)
		if not T.check(d ~= nil and BC.GetBattle() ~= nil, label .. ": (setup) a fighting battle HUD") then
			pg:SetAttribute("NC_Dev", nil)
			return
		end
		for _, size in ipairs(sizes) do
			Mock.SetViewport(size[1], size[2])
			d:run(0.6, 30)
			Dev.Relayout()
			H.step(2, 1 / 30)
			local tag = label .. " " .. size[1] .. "x" .. size[2]
			local tile = named(pg:FindFirstChild("NimbusDev"), "DevTile")
			local root = H.find("Root")
			if T.check(tile ~= nil and shownIn(tile) and root ~= nil, tag .. ": (setup) the DEV tile and the battle HUD are shown") then
				local tr = rectOf(tile)
				local hits = {}
				for _, block in ipairs(root:GetChildren()) do
					if block:IsA("GuiObject") and shownIn(block) and block.AbsoluteSize.X > 0 and block.AbsoluteSize.Y > 0 then
						local br = rectOf(block)
						if touches(tr, br, 4) then
							hits[#hits + 1] = fmt("%s %d,%d-%d,%d (tile %d,%d-%d,%d)", block.Name, br.x0, br.y0, br.x1, br.y1, tr.x0, tr.y0, tr.x1, tr.y1)
						end
					end
				end
				if size[3] == "cluster" then
					-- a desktop window of phone size: the currency pill, the enemy list and the cluster fill the whole right
					-- edge, so only the hard rule is asserted (the tile never covers the action cluster)
					T.info(tag .. ": (desktop window of phone size) battle HUD blocks under the DEV tile: " .. (#hits > 0 and table.concat(hits, ", ") or "none"))
				else
					T.check(#hits == 0, tag .. ": the DEV tile touches none of the battle HUD's blocks (>= 4 px clear)", table.concat(hits, ", "))
				end
				local cmd = H.find("Root.Commands")
				local clear = cmd ~= nil and shownIn(cmd) and not touches(tr, rectOf(cmd), 4)
				for _, b in ipairs(cmd and cmd:GetChildren() or {}) do
					if b:IsA("GuiObject") and shownIn(b) and touches(tr, rectOf(b), 4) then
						clear = false
					end
				end
				T.check(clear, tag .. ": ...in particular not the action cluster (its frame and every button, >= 4 px clear)")
				if size[4] == "hidden" and cmd then
					-- a Commands button laid exactly over the tile: visible = the tile moves off it; hidden = it reserves nothing
					local tilePos = tile.AbsolutePosition
					local ca = cmd.AbsolutePosition
					local decoy = Instance.new("Frame")
					decoy.Name = "W5DecoyButton"
					decoy.AnchorPoint = Vector2.new(0, 0)
					decoy.Position = UDim2.fromOffset(tr.x0 - ca.X, tr.y0 - ca.Y)
					decoy.Size = UDim2.fromOffset(tr.x1 - tr.x0, tr.y1 - tr.y0)
					decoy.Visible = true
					decoy.Parent = cmd
					Dev.Relayout()
					H.step(2, 1 / 30)
					local movedVisible = (tile.AbsolutePosition - tilePos).Magnitude > 4
					decoy.Visible = false
					Dev.Relayout()
					H.step(2, 1 / 30)
					local back = (tile.AbsolutePosition - tilePos).Magnitude < 1
					decoy:Destroy()
					Dev.Relayout()
					H.step(2, 1 / 30)
					T.check(movedVisible and back, tag .. ": a VISIBLE Commands button blocks the tile, a HIDDEN one reserves no slot",
						fmt("visible moved %s, hidden back %s", tostring(movedVisible), tostring(back)))
				end
				local cap = H.find("Root.Commands.AttackButton.Caption")
				if cap and shownIn(cap) then
					local cr = rectOf(cap)
					local vp = Mock.Viewport
					local inset = Mock.TopInset or 0
					T.check(cr.x0 >= 0 and cr.y0 >= -inset and cr.x1 <= vp.X and cr.y1 <= vp.Y - inset and not touches(tr, cr, 0) and cap.Text == "ATTACK",
						tag .. ": the ATTACK caption is whole on screen, reads ATTACK and is not under the tile", fmt("%s %d,%d-%d,%d", tostring(cap.Text), cr.x0, cr.y0, cr.x1, cr.y1))
				end
			end
		end
		H.cleanup(BC, d)
		pg:SetAttribute("NC_Dev", nil)
		Mock.SetViewport(restore[1], restore[2])
		Mock.Advance(0.6)
		KC.flushErrors(label)
	end

	S.client_fight_dev = guarded("client_fight_dev", function()
		devCheck("fight dev", { { 1920, 1080 }, { 1366, 768 }, { 844, 390, "cluster" }, { 390, 844 }, { 749, 388, "cluster" }, { 1920, 1080, nil, "hidden" } }, { 1920, 1080 })
	end)

	S.client_fight_dev_mobile = guarded("client_fight_dev_mobile", function()
		devCheck("fight dev (phone)", { { 390, 844 }, { 844, 390 }, { 749, 388 } }, { 390, 844 })
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
