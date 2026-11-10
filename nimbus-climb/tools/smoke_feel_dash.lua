-- smoke_feel_dash.lua: the battle feel, Task 2 "Melee dash, standoff 8 and the flurry"
-- (docs/superpowers/specs/2026-11-10-battle-feel-design.md decisions 1-3; plan docs/superpowers/plans/2026-11-10-battle-feel.md
-- Task 2). Loaded by tools/smoke.py in BOTH worlds (ARGS.context picks the half).
-- Server world, pure (a real BattleSim, white-box on battle.units / battle.teams):
--   feel_standoff_rest   a melee unit rests BattleCatalog.Damage.Standoff (8) farther out: the harness fighter at reach + 8 - 0.5,
--                        an NPC melee pet at reach + 8 - 0.5 of my standing fighter; Standoff = 0 gives today's reach - 0.5; a
--                        ranged NPC holds at reach - 0.3 at both settings
--   feel_standoff_dps    the same fights at Standoff 8 and 0: the melee unit's hit count differs by at most 1, its first hit is
--                        no later at 8 (a shorter walk), every NPC hit lands within reach + 8 + EngageSlack + 1.0
--   feel_standoff_zone   three NPC melee pets from one side on a 44 x 44 floor: every rest spot on the floor, >= 2.4 studs apart,
--                        all three winding up by 8 s
--   feel_standoff_wire   Validate holds; Standoff -1 / "x" / 25 fails it; the Windup event carries only type / unit / target / at
-- Client world (AttackFx on a fake clock; BattleController fed by a real BattleSim the way BattleService sends it):
--   client_feel_dash_npc     an enemy melee pet's Windup dashes it: AttackFx.Dash lands on ev.at, the pose is DashIn and at the
--                            edge at the landing, its Hit plays Dashed (no Strike), my pet flinches, DashBack from landAt + 0.20,
--                            "out" by landAt + 0.60; a dash with no hit after it returns all the same
--   client_feel_dash_mine    my melee fighter's Hit (no Windup): dashed, its impact and its number 0.30 later (fxLate); Melee.Dash =
--                            false: no dash, today's Strike, the number at the event
--   client_feel_dash_flurry  attacks 0.64 s apart stay in and bite in place (Strike Reach = Lunge on Forward = the edge), DashBack
--                            0.75 s after the last landing; attacks 1.1 s apart make a full round trip each time
--   client_feel_dash_off     a gap under MinGap (1.5): no dash (false); Melee.Dash = false: false; Low graphics: the dash runs, no streak
--   client_feel_dash_rejoin  (review fix) a dash caught on the hop back with its run starting later: the DashIn starts where the hop is AT t0
--   client_feel_dash_hop     (gate fix) Melee.Hop reaches PetPoses' DashIn: the hop peaks at the knob's studs (0.5 / 1.2 / 0; 9 clamps to 3)
--   client_feel_dash_gap     (review fix) at the shipped Standoff 0 a melee pet at the server's rest spot dashes at every raid boss with
--                            room in its box (the Shadow Hydra's box reaches past it: today's Strike) and at a pet
--   client_feel_dash_budget  eight melee pets dash at a boss in one frame: 4 streaks at most (mine kept), no new Instance between two
--                            Updates mid-dash, every kit back in its pool (keep size) after
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, min, sqrt, floor, huge = math.abs, math.max, math.min, math.sqrt, math.floor, math.huge
local fmt = string.format

local function dist(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	return sqrt(dx * dx + dz * dz)
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function req(name)
		local inst = K.moduleInstance("shared/" .. name)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	local function load(tag)
		local BC, BS = req("BattleCatalog"), req("BattleSim")
		if not T.check(BC ~= nil and BS ~= nil and type(BC.Damage) == "table", tag .. ": BattleCatalog + BattleSim load") then
			return nil
		end
		return BC, BS
	end

	-- a Duel: my team (`mine` pet keys, Auto or a standing fighter) vs NPC pets at the given spots
	local function duel(BS, mine, auto, foes, spots, seed, zone)
		local foeList = {}
		for i = 1, #foes do
			foeList[i] = { Key = foes[i], Level = 18, NoSpecial = true, Slot = i }
		end
		local b = BS.new({ Mode = "Duel", Seed = seed or 7, Zone = zone or { X = 160, Z = 160 }, TimeLimit = 300,
			Teams = { { Owner = 1, Side = 1, Pets = { { Key = mine, Level = 20, Slot = 1 } }, Auto = auto },
				{ Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = foeList } } })
		if not b then
			return nil
		end
		local tm = b.teams[1]
		local f = tm.fighter
		f.x, f.z, f.px, f.pz = 0, 0, 0, 0
		f.maxHp, f.hp = 1e9, 1e9
		tm.wantX, tm.wantZ = 0, 0
		tm.elementReadyAt = huge
		if not auto then
			tm.noEngage = true -- (my fighter stands: the NPC walks)
		end
		local on = {}
		for _, u in ipairs(b.units) do
			if u.side == 2 then
				on[#on + 1] = u
				local p = spots[#on]
				u.x, u.z, u.px, u.pz = p[1], p[2], p[1], p[2]
				u.maxHp, u.hp = 1e9, 1e9
			end
		end
		return b, tm, f, on
	end

	-- steps `seconds` at 10 Hz; my fighter never casts (meter 0) and, standing, never swings unless `swing`
	local function run(b, tm, f, seconds, swing, onStep)
		for _ = 1, floor(seconds / 0.1 + 0.5) do
			f.meter = 0
			if not tm.auto and not swing then
				f.nextAttack = huge
				tm.wantX, tm.wantZ = 0, 0
			end
			local evs = b:Step(0.1)
			if onStep then
				onStep(evs, b:Time())
			end
		end
	end

	local function withStandoff(BC, so, fn)
		local keep = BC.Damage.Standoff
		BC.Damage.Standoff = so
		local ok, err = pcall(fn)
		BC.Damage.Standoff = keep
		if not ok then
			error(err, 0)
		end
	end

	S.feel_standoff_rest = guarded("feel_standoff_rest", function()
		local BC, BS = load("feel standoff rest")
		if not BC then
			return
		end
		local Config = req("Config")
		local knob = Config and Config.Battle and Config.Battle.Feel and Config.Battle.Feel.Melee and Config.Battle.Feel.Melee.Standoff
		T.check(type(knob) == "number" and BC.Damage.Standoff == knob, fmt("feel standoff: BattleCatalog.Damage.Standoff = Config.Battle.Feel.Melee.Standoff (%s / %s)", tostring(BC.Damage.Standoff), tostring(knob)))
		local so8 = 8
		for _, so in ipairs({ so8, 0 }) do
			withStandoff(BC, so, function()
				-- (a) the harness fighter (Auto, melee) walks to a standing bear
				local b, tm, f, on = duel(BS, "storm_tabby", true, { "biscuit_bear" }, { { 0, 30 } })
				local bear = on[1]
				bear.moveSpeed, bear.nextAttack = 0, huge
				run(b, tm, f, 6)
				local want = f.range + bear.radius + so - 0.5
				local d = dist(f.x, f.z, bear.x, bear.z)
				T.check(not f.ranged and abs(d - want) <= 0.3, fmt("feel standoff (Standoff %d): the harness melee fighter rests at reach + %d - 0.5 of a standing bear (%.2f, want %.2f)", so, so, d, want))
				-- (b) an NPC melee pet walks to my standing fighter
				local b2, tm2, f2, on2 = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } })
				local npc = on2[1]
				run(b2, tm2, f2, 6)
				-- (an NPC stops walking once inside its reach: it rests between the orbit's reach - 0.5 and reach)
				local want2 = npc.range + f2.radius + so
				local d2 = dist(f2.x, f2.z, npc.x, npc.z)
				T.check(not npc.ranged and d2 >= want2 - 0.8 and d2 <= want2 + 0.05, fmt("feel standoff (Standoff %d): an NPC melee pet rests at reach + %d (- 0.5 .. 0) of my standing fighter (%.2f, want %.2f)", so, so, d2, want2))
				-- (c) a ranged NPC holds at the edge of its range as today
				local b3, tm3, f3, on3 = duel(BS, "storm_tabby", false, { "puddle_frog" }, { { 0, 40 } })
				local frog = on3[1]
				run(b3, tm3, f3, 6)
				local want3 = frog.range + f3.radius - 0.3
				local d3 = dist(f3.x, f3.z, frog.x, frog.z)
				T.check(frog.ranged and abs(d3 - want3) <= 0.3, fmt("feel standoff (Standoff %d): a ranged NPC holds at reach - 0.3 (no standoff) (%.2f, want %.2f)", so, d3, want3))
			end)
		end
	end)

	S.feel_standoff_dps = guarded("feel_standoff_dps", function()
		local BC, BS = load("feel standoff dps")
		if not BC then
			return
		end
		local D = BC.Damage
		local function fighterFight(so)
			local hits, first = 0, nil
			withStandoff(BC, so, function()
				local b, tm, f, on = duel(BS, "storm_tabby", true, { "biscuit_bear" }, { { 0, 30 } }, 11)
				local bear = on[1]
				bear.moveSpeed, bear.nextAttack = 0, huge
				local t0 = b:Time()
				run(b, tm, f, 30, true, function(evs, t)
					for _, ev in ipairs(evs) do
						if ev.type == "Hit" and ev.from == f.id and not ev.miss and not ev.special and not ev.element then
							hits = hits + 1
							first = first or (t - t0)
						end
					end
				end)
			end)
			return hits, first
		end
		local function npcFight(so)
			local hits, first, worst, reachMax = 0, nil, 0, 0
			withStandoff(BC, so, function()
				local b, tm, f, on = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } }, 11)
				local bear = on[1]
				reachMax = bear.range + f.radius + so + D.EngageSlack + 1.0
				local t0 = b:Time()
				run(b, tm, f, 30, false, function(evs, t)
					for _, ev in ipairs(evs) do
						if ev.type == "Hit" and ev.from == bear.id and not ev.miss and not ev.special then
							hits = hits + 1
							first = first or (t - t0)
							worst = max(worst, dist(bear.x, bear.z, f.x, f.z))
						end
					end
				end)
			end)
			return hits, first, worst, reachMax
		end
		local h8, f8 = fighterFight(8)
		local h0, f0 = fighterFight(0)
		T.check(h8 > 5 and h0 > 5 and abs(h8 - h0) <= 1, fmt("feel standoff dps: the harness melee fighter lands as many hits in 30 s at Standoff 8 as at 0 (%d vs %d)", h8, h0))
		T.check(f8 ~= nil and f0 ~= nil and f8 <= f0 + 1e-6, fmt("feel standoff dps: ... its first hit no later at 8 (a shorter walk) (%s vs %s s)", tostring(f8), tostring(f0)))
		local n8, g8, w8, r8 = npcFight(8)
		local n0, g0 = npcFight(0)
		T.check(n8 > 5 and n0 > 5 and abs(n8 - n0) <= 1, fmt("feel standoff dps: an NPC melee pet lands as many hits in 30 s at Standoff 8 as at 0 (%d vs %d)", n8, n0))
		T.check(g8 ~= nil and g0 ~= nil and g8 <= g0 + 1e-6, fmt("feel standoff dps: ... its first hit no later at 8 (%s vs %s s)", tostring(g8), tostring(g0)))
		T.check(w8 <= r8 + 1e-6, fmt("feel standoff dps: every NPC hit lands within reach + 8 + EngageSlack + 1.0 (worst %.2f, max %.2f)", w8, r8))
	end)

	S.feel_standoff_zone = guarded("feel_standoff_zone", function()
		local BC, BS = load("feel standoff zone")
		if not BC then
			return
		end
		local b, tm, f, on
		local wound = {}
		withStandoff(BC, 8, function()
			b, tm, f, on = duel(BS, "puddle_frog", false, { "biscuit_bear", "biscuit_bear", "biscuit_bear" }, { { -6, 20 }, { 0, 20 }, { 6, 20 } }, 5, { X = 44, Z = 44 })
			if b and #on == 3 then
				run(b, tm, f, 8, false, function(evs)
					for _, ev in ipairs(evs) do
						if ev.type == "Windup" then
							wound[ev.unit] = true
						end
					end
				end)
			end
		end)
		if not T.check(b ~= nil and #on == 3, "feel standoff zone: (Standoff 8) a 44 x 44 floor, three NPC melee pets") then
			return
		end
		local inside, apart, all = true, huge, true
		for i, u in ipairs(on) do
			inside = inside and abs(u.x) <= 22 + 1e-6 and abs(u.z) <= 22 + 1e-6
			all = all and wound[u.id] == true
			for j = i + 1, #on do
				apart = min(apart, dist(u.x, u.z, on[j].x, on[j].z))
			end
		end
		T.check(inside, "feel standoff zone: every rest spot is on the floor")
		T.check(apart >= 2.4, fmt("feel standoff zone: the three rest at least 2.4 studs apart (closest %.2f)", apart))
		T.check(all, "feel standoff zone: all three wind up (attack) by 8 s")
	end)

	S.feel_standoff_wire = guarded("feel_standoff_wire", function()
		local BC, BS = load("feel standoff wire")
		if not BC then
			return
		end
		T.check(select(1, BC.Validate()) == true, "feel standoff wire: BattleCatalog.Validate passes")
		local keep = BC.Damage.Standoff
		local bad = {}
		for _, v in ipairs({ -1, "x", 25 }) do
			BC.Damage.Standoff = v
			if BC.Validate() ~= false then
				bad[#bad + 1] = tostring(v)
			end
		end
		BC.Damage.Standoff = keep
		T.check(#bad == 0, "feel standoff wire: Validate catches a Standoff of -1 / \"x\" / 25 (a number 0..20)", table.concat(bad, ", "))
		-- nothing new on the wire: the Windup event is type / unit / target / at as before
		local b, tm, f = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } })
		local extra = {}
		run(b, tm, f, 6, false, function(evs)
			for _, ev in ipairs(evs) do
				if ev.type == "Windup" then
					for k in pairs(ev) do
						if k ~= "type" and k ~= "unit" and k ~= "target" and k ~= "at" then
							extra[#extra + 1] = k
						end
					end
				end
			end
		end)
		T.check(#extra == 0 and BS.Events.Windup == "Windup", "feel standoff wire: the Windup event carries type / unit / target / at only", table.concat(extra, ", "))
	end)

	------------------------------------------------------------------------------------------------
	-- (feel-balance, plan docs/superpowers/plans/2026-11-10-feel-balance.md Task 1) the body point: a melee unit with a
	-- standoff counts at its bite point while it strikes (the dash the client draws), at its rest spot otherwise
	------------------------------------------------------------------------------------------------
	-- the body point (white-box: BattleSim keeps the offset from the rest spot in bdx / bdz while a window is open)
	local function body(u)
		if u.bdx then
			return u.x + u.bdx, u.z + u.bdz, true
		end
		return u.x, u.z, false
	end

	-- a Raid on the real modules: `specs` = { { pets = { key... }, auto = bool }... }; the boss pinned (no attack, no
	-- telegraph, no wave) unless `live`; -> b, boss, teams
	local function raid(BS, bossId, tier, specs, seed, live)
		local teams = {}
		for i, spec in ipairs(specs) do
			local pets = {}
			for j, key in ipairs(spec.pets) do
				pets[j] = { Key = key, Level = spec.level or 20, Slot = j }
			end
			teams[i] = { Owner = i, Side = 1, Pets = pets, Auto = spec.auto }
		end
		local b = BS.new({ Mode = "Raid", Boss = bossId, RaidTier = tier, Seed = seed or 7, Teams = teams })
		if not b then
			return nil
		end
		local boss = b.boss
		boss.maxHp, boss.hp = 2e6, 2e6
		if not live then
			boss.nextAttack = huge
			for _, e in ipairs(boss.attacks) do
				e.nextAt = huge
			end
		end
		local tms = {}
		for i = 1, #specs do
			tms[i] = b.teamByOwner[i]
		end
		return b, boss, tms
	end

	-- a standing fighter of a raid team at (x, z): it never walks (noEngage), swings at what is in reach
	local function stand(tm, x, z)
		local f = tm.fighter
		f.x, f.z, f.px, f.pz = x, z, x, z
		f.maxHp, f.hp = 1e9, 1e9
		tm.wantX, tm.wantZ = x, z
		tm.noEngage = true
		tm.elementReadyAt = huge
		return f
	end

	local function stepRaid(b, tms, seconds, onStep)
		for _ = 1, floor(seconds / 0.1 + 0.5) do
			for _, tm in ipairs(tms) do
				local f = tm.fighter
				f.meter = 0
				tm.wantX, tm.wantZ = f.x, f.z
			end
			local evs = b:Step(0.1)
			if onStep and onStep(evs, b:Time()) == true then
				return true
			end
		end
		return false
	end

	S.feel_strike_body = guarded("feel_strike_body", function()
		local BC, BS = load("feel strike body")
		if not BC then
			return
		end
		local seen = {}
		local windAt, rest, target = nil, nil, nil
		withStandoff(BC, 8, function()
			-- my standing ranged frog (no standoff of its own) widened to a radius-6 body; an NPC bear winds up at it
			local b, tm, f, on = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } })
			f.radius = 6
			local bear = on[1]
			local d0 = bear.range + f.radius + 8 - 0.3
			bear.x, bear.z, bear.px, bear.pz = 0, d0, 0, d0
			bear.moveSpeed, bear.interval, bear.nextAttack = 0, 2.0, 0
			target = f
			run(b, tm, f, 1.6, false, function(evs, t)
				for _, ev in ipairs(evs) do
					if ev.type == "Windup" and ev.unit == bear.id and not windAt then
						windAt = bear.windAt -- (the exact time: the event's `at` is rounded to 0.1)
					end
				end
				local bx, bz, on2 = body(bear)
				seen[#seen + 1] = { t = t, on = on2, nearer = dist(bear.x, bear.z, f.x, f.z) - dist(bx, bz, f.x, f.z), same = (bx == bear.x and bz == bear.z) }
			end)
			rest = bear
		end)
		if not T.check(windAt ~= nil and #seen > 0, "feel strike body: (setup) the bear winds up at my radius-6 fighter (Standoff 8)") then
			return
		end
		local early, inside, after, bad = true, 0, true, {}
		for _, s in ipairs(seen) do
			if s.t <= windAt - 0.2 + 1e-6 then
				early = early and s.same and not s.on
			elseif s.t >= windAt - 0.15 - 1e-6 and s.t <= windAt + 0.40 + 1e-6 then
				if s.on and abs(s.nearer - 8) <= 0.1 then
					inside = inside + 1
				else
					bad[#bad + 1] = fmt("t %.2f on %s nearer %.2f", s.t, tostring(s.on), s.nearer)
				end
			elseif s.t >= windAt + 0.5 - 1e-6 and s.t <= windAt + 1.0 then
				after = after and s.same and not s.on
			end
		end
		T.check(early, fmt("feel strike body: 0.2 s before the wind-up lands (at %.2f) the body point is the rest spot", windAt))
		T.check(inside >= 5 and #bad == 0, fmt("feel strike body: from at - 0.15 to at + 0.40 the body is 8.0 +- 0.1 studs nearer the target's centre (%d steps)", inside), table.concat(bad, "; "))
		T.check(after, "feel strike body: from at + 0.5 the body point is the rest spot again")
	end)

	S.feel_strike_area = guarded("feel_strike_area", function()
		local BC, BS = load("feel strike area")
		if not BC then
			return
		end
		local eruption = BC.Bosses.lava_golem.Attacks[2]
		if not T.check(type(eruption) == "table" and eruption.Target == "Self" and eruption.Radius == 15, "feel strike area: (setup) the Lava Golem's Eruption is a Self circle of radius 15") then
			return
		end
		local hitIn, hitOut, rangedHit, restD, ok = nil, nil, 0, nil, false
		withStandoff(BC, 8, function()
			local b, boss, tms = raid(BS, "lava_golem", "Max", { { pets = { "storm_tabby" } }, { pets = { "puddle_frog" } } })
			if not b then
				return
			end
			boss.x, boss.z, boss.px, boss.pz = 0, 0, 0, 0
			local melee = tms[1].fighter
			local ranged = tms[2].fighter
			restD = melee.range + boss.radius + 8 - 0.5
			stand(tms[1], 0, restD)
			stand(tms[2], 21.7, 0)
			ranged.nextAttack = huge
			stepRaid(b, tms, 2, function()
				melee.nextAttack = huge -- (no window during the warm-up: the wait below finds a window's first step)
			end)
			melee.nextAttack = 0
			local nextId = 900
			local function erupt()
				nextId = nextId + 1
				b.telegraphs[#b.telegraphs + 1] = { id = nextId, boss = boss, attack = eruption, at = b:Time() + 0.05, shape = "Circle", x = boss.x, z = boss.z, r = eruption.Radius }
				local id = nextId
				local n, nr = 0, 0
				stepRaid(b, tms, 0.1, function(evs)
					for _, ev in ipairs(evs) do
						if ev.type == "Hit" and ev.tele == id and not ev.miss then
							if ev.to == melee.id then
								n = n + 1
							elseif ev.to == ranged.id then
								nr = nr + 1
							end
						end
					end
				end)
				return n, nr
			end
			-- wait for a window (the melee pet's plain hit on the boss), then the eruption resolves inside it
			local open = stepRaid(b, tms, 6, function()
				return melee.bdx ~= nil
			end)
			if not open then
				return
			end
			local nr1
			hitIn, nr1 = erupt()
			-- no more attacks: the window closes; 0.3 s after it the same eruption
			melee.nextAttack = huge
			stepRaid(b, tms, 3, function()
				melee.nextAttack = huge
				return melee.bdx == nil
			end)
			stepRaid(b, tms, 0.3, function()
				melee.nextAttack = huge
			end)
			local nr2
			hitOut, nr2 = erupt()
			rangedHit = nr1 + nr2
			ok = true
		end)
		if not T.check(ok, "feel strike area: (setup) a lava golem Max raid, my melee fighter at its rest spot strikes the boss (a window opens)") then
			return
		end
		T.check(hitIn == 1, fmt("feel strike area: an Eruption resolved while my melee pet strikes (rest %.1f studs out) hits it once (%s)", restD, tostring(hitIn)))
		T.check(hitOut == 0, fmt("feel strike area: the same Eruption 0.3 s after the window closed hits nothing (%s)", tostring(hitOut)))
		T.check(rangedHit == 0, fmt("feel strike area: a ranged pet at 21.7 studs is hit by neither (%d)", rangedHit))
	end)

	S.feel_strike_flurry = guarded("feel_strike_flurry", function()
		local BC, BS = load("feel strike flurry")
		if not BC then
			return
		end
		local fast, slowOut, slowIn = 0, 0, 0
		local fastSteps = 0
		withStandoff(BC, 8, function()
			local b, tm, f, on = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } })
			local bear = on[1]
			local d0 = bear.range + f.radius + 8 - 0.3
			bear.x, bear.z, bear.px, bear.pz = 0, d0, 0, d0
			bear.moveSpeed, bear.interval, bear.nextAttack = 0, 0.53, 0
			run(b, tm, f, 2)
			run(b, tm, f, 5, false, function()
				fastSteps = fastSteps + 1
				if bear.bdx ~= nil then
					fast = fast + 1
				end
			end)
			-- slowed: interval / slow = 0.9 (over FlurryBelow 0.75): per-attack windows, back at rest between them
			bear.slowMult, bear.slowUntil = 0.53 / 0.9, huge
			run(b, tm, f, 2)
			run(b, tm, f, 5, false, function()
				if bear.bdx ~= nil then
					slowIn = slowIn + 1
				else
					slowOut = slowOut + 1
				end
			end)
		end)
		T.check(fastSteps == 50 and fast == 50, fmt("feel strike flurry: interval 0.53 s (under FlurryBelow 0.75): the body is in on every one of 50 steps (%d of %d)", fast, fastSteps))
		T.check(slowIn >= 15 and slowOut >= 10, fmt("feel strike flurry: interval / slow 0.9: per-attack windows, the body back at rest between attacks (%d steps in, %d out of 50)", slowIn, slowOut))
	end)

	S.feel_strike_fighter = guarded("feel_strike_fighter", function()
		local BC, BS = load("feel strike fighter")
		if not BC then
			return
		end
		local h, rows = nil, {}
		withStandoff(BC, 8, function()
			-- my standing melee fighter at its rest spot off a standing ranged frog (no standoff of its own: the full 8)
			local b, tm, f, on = duel(BS, "storm_tabby", false, { "puddle_frog" }, { { 0, 30 } })
			local frog = on[1]
			local d0 = f.range + frog.radius + 8 - 0.5
			frog.x, frog.z, frog.px, frog.pz = 0, d0, 0, d0
			run(b, tm, f, 2.5, true, function(evs, t)
				for _, ev in ipairs(evs) do
					if ev.type == "Hit" and ev.from == f.id and not h then
						h = t
					end
				end
				if h then
					f.nextAttack = huge
					local bx, bz, inn = body(f)
					rows[#rows + 1] = { t = t, on = inn, nearer = dist(f.x, f.z, frog.x, frog.z) - dist(bx, bz, frog.x, frog.z) }
				end
			end)
		end)
		if not T.check(h ~= nil, "feel strike fighter: (setup) my melee fighter's plain Hit (Standoff 8)") then
			return
		end
		local bad, n = {}, 0
		for _, r in ipairs(rows) do
			local want = (r.t >= h + 0.15 - 1e-6 and r.t <= h + 0.70 + 1e-6)
			if want then
				n = n + 1
			end
			if r.on ~= want or (want and abs(r.nearer - 8) > 0.1) then
				bad[#bad + 1] = fmt("h+%.2f on %s nearer %.2f", r.t - h, tostring(r.on), r.nearer)
			end
		end
		T.check(n >= 5 and #bad == 0, fmt("feel strike fighter: a fighter's plain Hit at h: the body 8 studs in from h + 0.15 to h + 0.70, at rest before and after (%d steps in)", n), table.concat(bad, "; "))
	end)

	S.feel_strike_gone = guarded("feel_strike_gone", function()
		local BC, BS = load("feel strike gone")
		if not BC then
			return
		end
		local was, after = false, true
		withStandoff(BC, 8, function()
			local b, tm, f, on = duel(BS, "storm_tabby", false, { "puddle_frog" }, { { 0, 30 } })
			local frog = on[1]
			local d0 = f.range + frog.radius + 8 - 0.5
			frog.x, frog.z, frog.px, frog.pz = 0, d0, 0, d0
			run(b, tm, f, 3, true, function()
				if f.bdx ~= nil and not was then
					was = true
					frog.alive, frog.hp = false, 0 -- (knockOut's fields: the target is down mid-window)
				elseif was then
					return
				end
			end)
			after = (f.bdx == nil)
		end)
		T.check(was, "feel strike gone: (setup) my fighter strikes (a window opens)")
		T.check(after, "feel strike gone: the target KO'd mid-window: on the next step the body point is the rest spot")
	end)

	S.feel_strike_dash = guarded("feel_strike_dash", function()
		local BC, BS = load("feel strike dash")
		if not BC then
			return
		end
		local F = BC.Fighter
		local function dashCase(so)
			local res = {}
			withStandoff(BC, so, function()
				local b, tm, f, on = duel(BS, "storm_tabby", false, { "puddle_frog" }, { { 0, 30 } })
				local frog = on[1]
				local d0 = f.range + frog.radius + so - 0.5
				frog.x, frog.z, frog.px, frog.pz = 0, d0, 0, d0
				local hitAt = nil
				run(b, tm, f, 3, true, function(evs, t)
					for _, ev in ipairs(evs) do
						if ev.type == "Hit" and ev.from == f.id and not hitAt then
							hitAt = t
						end
					end
				end)
				-- the next hit's window: step until it is open (Standoff 8) or 0.3 s after a hit (Standoff 0)
				hitAt = nil
				local ready = false
				for _ = 1, 40 do
					f.meter = 0
					tm.wantX, tm.wantZ = 0, 0
					for _, ev in ipairs(b:Step(0.1)) do
						if ev.type == "Hit" and ev.from == f.id then
							hitAt = b:Time()
						end
					end
					if hitAt and b:Time() >= hitAt + 0.3 - 1e-6 then
						ready = true
						break
					end
				end
				res.ready = ready
				res.before = f.bdx ~= nil
				local t = b:Time()
				res.ok = b:Command(1, "Dash")
				res.after = f.bdx ~= nil
				res.iframes = (f.iframesUntil or 0) - t
				res.snapBx = b:Snapshot().Units[f.id].bx
			end)
			return res
		end
		local r8, r0 = dashCase(8), dashCase(0)
		T.check(r8.ready and r8.before and r8.ok == true, "feel strike dash: (setup) Standoff 8: my fighter mid-window presses a legal Dash")
		T.check(not r8.after and r8.snapBx == nil, "feel strike dash: the same step the body point is the rest spot (no bx in the snapshot)")
		T.check(r0.ok == true and abs(r8.iframes - r0.iframes) < 1e-9 and abs(r8.iframes - F.DashIFrames) < 1e-9,
			fmt("feel strike dash: the i-frames end at the same time as at Standoff 0 (%.3f vs %.3f s)", r8.iframes or -1, r0.iframes or -1))
	end)

	S.feel_strike_mirror = guarded("feel_strike_mirror", function()
		local BC, BS = load("feel strike mirror")
		if not BC then
			return
		end
		local got, want, dot = nil, nil, nil
		withStandoff(BC, 8, function()
			-- my standing melee fighter and an NPC melee tabby, rest spots 13 studs apart, both striking
			local b, tm, f, on = duel(BS, "storm_tabby", false, { "storm_tabby" }, { { 0, 13 } })
			local foe = on[1]
			foe.moveSpeed, foe.nextAttack = 0, 0
			local function adv(u, v)
				local gap = dist(u.x, u.z, v.x, v.z) - (u.range + v.radius - 0.5)
				return min(8, max(0, gap) * 0.5)
			end
			run(b, tm, f, 6, true, function()
				if not got and f.bdx ~= nil and foe.bdx ~= nil then
					local ax, az = body(f)
					local bx, bz = body(foe)
					got = dist(ax, az, bx, bz)
					want = 13 - adv(f, foe) - adv(foe, f)
					dot = (bx - ax) * (foe.x - f.x) + (bz - az) * (foe.z - f.z)
				end
			end)
		end)
		if not T.check(got ~= nil, "feel strike mirror: (setup) two melee units striking each other at the same step (Standoff 8)") then
			return
		end
		-- (two storm_tabbies: they meet at the Standoff-0 rest distance, range + radius - 0.5 = 5.8; the plan's 5.0 was its estimate)
		T.check(abs(got - want) <= 0.05 and got > 3, fmt("feel strike mirror: each advances half the free gap: the body points %.2f studs apart (want %.2f, the Standoff-0 rest distance)", got, want))
		T.check(dot > 0, fmt("feel strike mirror: the body points have not crossed (dot %.2f)", dot))
	end)

	S.feel_strike_nearest = guarded("feel_strike_nearest", function()
		local BC, BS = load("feel strike nearest")
		if not BC then
			return
		end
		local inPick, outPick, ids, ok = nil, nil, {}, false
		withStandoff(BC, 8, function()
			local b, boss, tms = raid(BS, "lava_golem", "Max", { { pets = { "storm_tabby" } }, { pets = { "puddle_frog" } } })
			if not b then
				return
			end
			boss.x, boss.z, boss.px, boss.pz = 0, 0, 0, 0
			local melee = stand(tms[1], 0, 21.9)
			local ranged = stand(tms[2], 21.7, 0)
			ranged.nextAttack = huge
			ids.melee, ids.ranged = melee.id, ranged.id
			-- out of a window: the ranged pet (21.7) is nearer than the resting melee one (21.9)
			melee.nextAttack = huge
			stepRaid(b, tms, 1.5, function()
				melee.nextAttack = huge
			end)
			boss.nextAttack = 0
			stepRaid(b, tms, 0.1, function()
				melee.nextAttack = huge
			end)
			outPick = boss.target and boss.target.id
			-- in a window: the melee pet bites at ~14 studs
			boss.nextAttack = huge
			melee.nextAttack = 0
			local open = stepRaid(b, tms, 3, function()
				return melee.bdx ~= nil
			end)
			if not open then
				return
			end
			boss.nextAttack = 0
			stepRaid(b, tms, 0.1)
			inPick = boss.target and boss.target.id
			ok = true
		end)
		if not T.check(ok, "feel strike nearest: (setup) a lava golem Max raid, a melee pet resting at 21.9 studs and a ranged one at 21.7") then
			return
		end
		T.check(outPick == ids.ranged, fmt("feel strike nearest: no window: the boss's basic picks the ranged pet (21.7 < 21.9) (%s)", tostring(outPick)))
		T.check(inPick == ids.melee, fmt("feel strike nearest: while the melee pet strikes, the boss's basic picks it (%s, melee %s)", tostring(inPick), tostring(ids.melee)))
	end)

	-- (feel-balance, the Task 1 measurement) a boss aims its circles where it sees the pet: a Cluster circle started while my
	-- melee pet strikes stands on its bite point, one started while it rests on its rest spot
	S.feel_strike_aim = guarded("feel_strike_aim", function()
		local BC, BS = load("feel strike aim")
		if not BC then
			return
		end
		local rows, ok = {}, false
		withStandoff(BC, 8, function()
			local b, boss, tms = raid(BS, "lava_golem", "Max", { { pets = { "storm_tabby" } } })
			if not b then
				return
			end
			boss.x, boss.z, boss.px, boss.pz = 0, 0, 0, 0
			local melee = tms[1].fighter
			local restD = melee.range + boss.radius + 8 - 0.5
			stand(tms[1], 0, restD)
			local pool = boss.attacks[1]
			local function cast()
				pool.nextAt = 0
				local tele = nil
				stepRaid(b, tms, 0.1, function(evs)
					for _, ev in ipairs(evs) do
						if ev.type == "Telegraph" and ev.attack == "pool" then
							tele = ev
						end
					end
				end)
				pool.nextAt = huge
				b.telegraphs = {}
				return tele
			end
			-- resting (no attack): on the rest spot
			stepRaid(b, tms, 1, function()
				melee.nextAttack = huge
			end)
			local bx, bz = body(melee)
			local t1 = cast()
			rows.rest = t1 and dist(t1.x, t1.z, bx, bz)
			rows.restOn = melee.bdx ~= nil
			-- striking: on the bite point
			melee.nextAttack = 0
			stepRaid(b, tms, 3, function()
				return melee.bdx ~= nil
			end)
			local sx, sz = body(melee)
			local t2 = cast()
			rows.strike = t2 and dist(t2.x, t2.z, sx, sz)
			rows.strikeOn = melee.bdx ~= nil
			rows.fromRest = t2 and dist(t2.x, t2.z, melee.x, melee.z)
			ok = t1 ~= nil and t2 ~= nil
		end)
		if not T.check(ok, "feel strike aim: (setup) a lava golem Max raid, its Magma Pool (Cluster) cast at my melee pet twice") then
			return
		end
		T.check(not rows.restOn and rows.rest <= 0.11, fmt("feel strike aim: my pet resting: the circle stands on its rest spot (%.2f studs off)", rows.rest))
		T.check(rows.strikeOn and rows.strike <= 0.11 and rows.fromRest >= 7.5, fmt("feel strike aim: my pet striking: the circle stands on its bite point (%.2f off; %.2f from the rest spot)", rows.strike, rows.fromRest))
	end)

	S.feel_strike_zone = guarded("feel_strike_zone", function()
		local BC, BS = load("feel strike zone")
		if not BC then
			return
		end
		local ticksIn, ticksOut, ok = 0, 0, false
		withStandoff(BC, 8, function()
			local b, tm, f, on = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } })
			local bear = on[1]
			local d0 = bear.range + f.radius + 8 - 0.3
			bear.x, bear.z, bear.px, bear.pz = 0, d0, 0, d0
			bear.moveSpeed, bear.interval, bear.nextAttack = 0, 2.0, 0
			-- my side's damage zone (radius 2) on the bear's bite point: 8 studs nearer my fighter than its rest spot
			local zx, zz = 0, d0 - 8
			b.zones[#b.zones + 1] = { x = zx, z = zz, r = 2, dps = 10, untilT = b:Time() + 20, nextTick = b:Time() + 0.1, side = 1, from = f, kind = "Linger" }
			run(b, tm, f, 8, false, function(evs)
				for _, ev in ipairs(evs) do
					if ev.type == "Hit" and ev.zone and ev.to == bear.id then
						if bear.bdx ~= nil then
							ticksIn = ticksIn + 1
						else
							ticksOut = ticksOut + 1
						end
					end
				end
			end)
			ok = true
		end)
		T.check(ok and ticksIn >= 1, fmt("feel strike zone: a zone under the bite point ticks the striking pet (%d ticks)", ticksIn))
		T.check(ticksOut == 0, fmt("feel strike zone: ... and never the resting one (%d ticks at rest)", ticksOut))
	end)

	-- the event log of a 60 s seeded raid as one string hash (sorted keys, every value): storm_titan Starter, 3 Auto teams
	local function logHash(BS)
		local b = BS.new({ Mode = "Raid", Boss = "storm_titan", RaidTier = "Starter", Seed = 7, Teams = {
			{ Owner = 1, Side = 1, Auto = true, Pets = { { Key = "aurora_fox", Level = 18, Slot = 1 }, { Key = "moonlit_owl", Level = 17, Slot = 2 }, { Key = "ember_phoenix", Level = 16, Slot = 3 } } },
			{ Owner = 2, Side = 1, Auto = true, Pets = { { Key = "storm_tabby", Level = 18, Slot = 1 }, { Key = "moonlit_owl", Level = 17, Slot = 2 }, { Key = "ember_phoenix", Level = 16, Slot = 3 } } },
			{ Owner = 3, Side = 1, Auto = true, Pets = { { Key = "biscuit_bear", Level = 18, Slot = 1 }, { Key = "aurora_fox", Level = 17, Slot = 2 }, { Key = "puddle_frog", Level = 16, Slot = 3 } } } } })
		if not b then
			return nil
		end
		b.boss.maxHp, b.boss.hp = 2e6, 2e6 -- (pinned: the fit's HP knobs never move this log)
		local parts = {}
		local function ser(v)
			local tv = type(v)
			if tv == "table" then
				local keys = {}
				for k in pairs(v) do
					keys[#keys + 1] = k
				end
				table.sort(keys, function(a, c)
					return tostring(a) < tostring(c)
				end)
				parts[#parts + 1] = "{"
				for _, k in ipairs(keys) do
					parts[#parts + 1] = tostring(k) .. "="
					ser(v[k])
					parts[#parts + 1] = ","
				end
				parts[#parts + 1] = "}"
			elseif tv == "number" then
				parts[#parts + 1] = fmt("%.10g", v)
			else
				parts[#parts + 1] = tostring(v)
			end
		end
		local n, bxSeen = 0, 0
		for _ = 1, 600 do
			for _, ev in ipairs(b:Step(0.1)) do
				n = n + 1
				ser(ev)
				parts[#parts + 1] = ";"
			end
			for _, s in pairs(b:Snapshot().Units) do
				if s.bx ~= nil or s.bz ~= nil then
					bxSeen = bxSeen + 1
				end
			end
		end
		local str = table.concat(parts)
		local h = 0
		for i = 1, #str do
			h = (h * 31 + string.byte(str, i)) % 2147483647
		end
		return h, n, bxSeen, #str
	end

	-- recorded from 163a2f4 (battle-feel: Standoff 0, RealCast off), before the body point existed
	local OFF_HASH, OFF_EVENTS = 792611972, 324

	S.feel_strike_off = guarded("feel_strike_off", function()
		local BC, BS = load("feel strike off")
		if not BC then
			return
		end
		local keepCast = BC.Damage.SpecialCast
		BC.Damage.SpecialCast = nil
		local h, n, bxSeen, len
		local ok, err = pcall(function()
			withStandoff(BC, 0, function()
				h, n, bxSeen, len = logHash(BS)
			end)
		end)
		BC.Damage.SpecialCast = keepCast
		if not T.check(ok and h ~= nil, "feel strike off: (setup) a 60 s seeded raid at Standoff 0, the real cast off", tostring(err)) then
			return
		end
		T.info("feel strike off: the event log", fmt("hash %d, %d events, %d chars", h, n, len))
		T.check(OFF_HASH ~= nil and h == OFF_HASH and n == OFF_EVENTS, fmt("feel strike off: Standoff 0: the event log is 163a2f4's (hash %d / %s, %d / %s events)", h, tostring(OFF_HASH), n, tostring(OFF_EVENTS)))
		T.check(bxSeen == 0, fmt("feel strike off: ... and no snapshot unit carries bx / bz (%d)", bxSeen))
	end)

	S.feel_strike_wire = guarded("feel_strike_wire", function()
		local BC, BS = load("feel strike wire")
		if not BC then
			return
		end
		local St = BC.Damage.Strike
		if not T.check(type(St) == "table", "feel strike wire: BattleCatalog.Damage.Strike exists") then
			return
		end
		local Config = req("Config")
		local M = Config.Battle.Feel.Melee
		T.check(St.In == M.In and St.Bite == M.Bite and St.Hold == M.Hold and St.Back == M.Back and St.FlurryBelow == M.FlurryBelow and St.Out == M.Out and St.Out ~= nil,
			"feel strike wire: Damage.Strike = Config.Battle.Feel.Melee's In / Bite / Hold / Back / FlurryBelow / Out")
		T.check(select(1, BC.Validate()) == true, "feel strike wire: BattleCatalog.Validate passes")
		local bad = {}
		for _, case in ipairs({ { "Out", 0.1 }, { "Out", 1.5 }, { "In", -1 }, { "FlurryBelow", 4 }, { "Back", "x" } }) do
			local keep = St[case[1]]
			St[case[1]] = case[2]
			if BC.Validate() ~= false then
				bad[#bad + 1] = case[1] .. " " .. tostring(case[2])
			end
			St[case[1]] = keep
		end
		local keep = { St.In, St.Bite, St.Hold, St.Back }
		St.In, St.Bite, St.Hold, St.Back = 0.1, 0.02, 0.02, 0.1
		if BC.Validate() ~= false then
			bad[#bad + 1] = "a window under 0.3 s"
		end
		St.In, St.Bite, St.Hold, St.Back = keep[1], keep[2], keep[3], keep[4]
		T.check(#bad == 0, "feel strike wire: Validate catches Out 0.1 / 1.5, In -1, FlurryBelow 4, Back \"x\" and a window under 0.3 s (the 10 Hz tick)", table.concat(bad, ", "))
		local inSnap, outSnap, match = nil, nil, false
		withStandoff(BC, 8, function()
			local b, tm, f, on = duel(BS, "puddle_frog", false, { "biscuit_bear" }, { { 0, 30 } })
			local bear = on[1]
			local d0 = bear.range + f.radius + 8 - 0.3
			bear.x, bear.z, bear.px, bear.pz = 0, d0, 0, d0
			bear.moveSpeed, bear.interval, bear.nextAttack = 0, 2.0, 0
			run(b, tm, f, 2, false, function()
				local s = b:Snapshot().Units[bear.id]
				if bear.bdx ~= nil and not inSnap then
					inSnap = s
					local bx, bz = body(bear)
					match = s.bx ~= nil and abs(s.bx - bx) <= 0.051 and abs(s.bz - bz) <= 0.051
				elseif bear.bdx == nil and inSnap and not outSnap then
					outSnap = s
				end
			end)
		end)
		T.check(inSnap ~= nil and match, "feel strike wire: Snapshot carries bx / bz (0.1 steps) for a unit in a window")
		T.check(outSnap ~= nil and outSnap.bx == nil and outSnap.bz == nil, "feel strike wire: ... and omits them otherwise")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local LocalPlayer = game:GetService("Players").LocalPlayer
	local V3 = Vector3.new
	local G = 3

	local function moduleAt(path)
		local ok, inst = pcall(Mock.GetPath, path)
		if not ok or not inst then
			return nil
		end
		local ok2, mod = pcall(require, inst)
		return ok2 and type(mod) == "table" and mod or nil
	end

	local function fakeMeshLibrary()
		return {
			IsReady = function(key)
				return type(key) == "string" and string.sub(key, 1, 4) == "vfx_"
			end,
			Assemble = function(spec)
				local key = type(spec) == "string" and spec or (type(spec) == "table" and spec.Key) or "?"
				local m = Instance.new("Model")
				m.Name = key
				local p = Instance.new("MeshPart")
				p.Name = "Core"
				p.Size = V3(2, 2, 2)
				p.Anchored = true
				p.Parent = m
				return m
			end,
		}
	end

	local function unitModel(parent, name, pos, size)
		local m = Instance.new("Model")
		m.Name = name
		local root = Instance.new("Part")
		root.Name = "Body"
		root.Anchored = true
		root.Size = size or V3(2, 2, 2)
		root.CFrame = CFrame.new(pos)
		root.Parent = m
		m.PrimaryPart = root
		m.Parent = parent
		return m
	end

	-- a pose's whole forward offset (pose studs): the PetPoses body's -Z plus the held edge (Forward)
	local function fwdOf(PP, pose)
		if type(pose) ~= "table" or type(pose.Name) ~= "string" then
			return 0
		end
		local s = PP.Sample(pose.Name, pose.P, pose.Ranged, pose.Amp, pose.Reach)
		return -s.Body.Position.Z + (tonumber(pose.Forward) or 0)
	end

	-- the AttackFx world on a fake clock (smoke_feel_aim's)
	local function setup(tag)
		local env = {}
		env.AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		env.Config = moduleAt(ROOTS.shared .. "/Config")
		env.PP = moduleAt(ROOTS.shared .. "/PetPoses")
		env.BB = moduleAt(ROOTS.shared .. "/BossBuilder")
		local AF = env.AF
		if not T.check(AF ~= nil and env.Config ~= nil and env.PP ~= nil, tag .. ": AttackFx, Config, PetPoses load") then
			return nil
		end
		local M = env.Config.Battle and env.Config.Battle.Feel and env.Config.Battle.Feel.Melee
		if not T.check(type(M) == "table" and type(AF.Dash) == "function" and type(AF.DashState) == "function",
			tag .. ": Config.Battle.Feel.Melee, AttackFx.Dash and AttackFx.DashState exist") then
			return nil
		end
		env.M = M
		env.saved = {}
		for k, v in pairs(M) do
			env.saved[k] = v
		end
		AF.ClearAll()
		AF._Deps({ MeshLibrary = fakeMeshLibrary() })
		AF.SetQuality("High")
		local cb = workspace:FindFirstChild("ClientBattle")
		if not cb then
			cb = Instance.new("Folder")
			cb.Name = "ClientBattle"
			cb.Parent = workspace
		end
		env.holder = Instance.new("Folder")
		env.holder.Name = "SmokeFeelDash_" .. tag
		env.holder.Parent = cb
		env.clock = 9000
		env.DT = 1 / 30
		AF.Update(env.clock)
		function env.run(seconds, each)
			local n = math.ceil(seconds / env.DT - 1e-9)
			for _ = 1, n do
				env.clock = env.clock + env.DT
				AF.Update(env.clock)
				if each then
					each(env.clock)
				end
			end
		end
		function env.runTo(at, each)
			while env.clock + env.DT <= at + 1e-9 do
				env.clock = env.clock + env.DT
				AF.Update(env.clock)
				if each then
					each(env.clock)
				end
			end
		end
		function env.fwd(unit)
			return fwdOf(env.PP, AF.Pose(unit))
		end
		function env.done()
			AF.ClearAll()
			AF._Deps({ MeshLibrary = false })
			AF.SetQuality(nil)
			for k, v in pairs(env.saved) do
				M[k] = v
			end
			pcall(env.holder.Destroy, env.holder)
		end
		return env
	end

	-- two pet stand-ins 12 studs apart: the gap = 12 - 1 - 1 - LEAP_MARGIN 0.3
	local function pair(env, x, unit)
		local a = unitModel(env.holder, "A" .. unit, V3(x, G + 1.5, 0))
		local b = unitModel(env.holder, "B" .. unit, V3(x, G + 1.5, -12))
		return { Unit = unit, Model = a, Pos = V3(x, G + 1.5, 0) }, { Unit = unit + 1000, Model = b, Pos = V3(x, G + 1.5, -12) }
	end

	----------------------------------------------------------------------------------------------
	S.client_feel_dash_flurry = guarded("client_feel_dash_flurry", function()
		local env = setup("flurry")
		if not env then
			return
		end
		local AF, M = env.AF, env.M
		local ok, err = pcall(function()
			local src, tgt = pair(env, 0, 1)
			local edge = AF.LeapReach({ Model = src.Model, Last = src.Pos }, { Model = tgt.Model, Last = tgt.Pos })
			T.check(edge ~= nil and abs(edge - 9.7) < 0.05, fmt("feel dash flurry: (setup) the gap to the edge is 9.7 studs (%s)", tostring(edge)))
			-- three attacks 0.64 s apart (a Storm pet's Charge tempo); the windup lands each 0.45 s after its request
			local starts = { env.clock + 0.05, env.clock + 0.69, env.clock + 1.33 }
			local tempos = { nil, 0.64, 0.64 }
			local results, states = {}, {}
			for i = 1, 3 do
				env.runTo(starts[i])
				states[i] = AF.DashState(1)
				results[i] = AF.Dash(1, src, tgt, starts[i] + 0.45, env.clock, { Tempo = tempos[i] })
			end
			T.check(results[1] and results[2] and results[3] and states[1] == "out", fmt("feel dash flurry: three Dash calls taken (%s %s %s), the first from \"out\"", tostring(results[1]), tostring(results[2]), tostring(results[3])))
			T.check(states[3] == "in", fmt("feel dash flurry: the third attack (0.64 s after the second) finds the pet still in (%s)", tostring(states[3])))
			local land3 = starts[3] + 0.45
			env.runTo(land3)
			local pose = AF.Pose(1)
			T.check(pose ~= nil and pose.Name == "Strike" and pose.Reach ~= nil and abs(pose.Reach - M.Lunge) < 1e-6 and abs((pose.Forward or 0) - edge) < 0.05,
				fmt("feel dash flurry: the flurry bites in place: a Strike lunge of Lunge 0.6 on Forward = the edge (%s, reach %s, forward %s)",
					tostring(pose and pose.Name), tostring(pose and pose.Reach), tostring(pose and pose.Forward)))
			local backAt = land3 + M.FlurryBelow
			env.runTo(backAt - 0.05)
			T.check(AF.DashState(1) == "in", fmt("feel dash flurry: still in until FlurryBelow 0.75 s after the last landing (%s)", AF.DashState(1)))
			env.runTo(backAt + 0.1)
			T.check(AF.DashState(1) == "back" and AF.Pose(1) ~= nil and AF.Pose(1).Name == "DashBack", fmt("feel dash flurry: ... then the hop back (%s)", AF.DashState(1)))
			env.runTo(backAt + M.Back + 0.05)
			T.check(AF.DashState(1) == "out" and AF.Pose(1) == nil, fmt("feel dash flurry: ... and back at the rest spot (%s)", AF.DashState(1)))
			-- attacks 1.1 s apart: a full round trip each time
			local trips, sawBack = 0, 0
			local nextAt = env.clock + 0.05
			for _ = 1, 3 do
				env.runTo(nextAt)
				local now = env.clock
				local before = AF.DashState(1)
				local land = now + 0.45
				if AF.Dash(1, src, tgt, land, now, { Tempo = 1.1 }) and before == "out" then
					trips = trips + 1
				end
				env.runTo(land + M.Bite + M.Hold + 0.1)
				if AF.DashState(1) == "back" then
					sawBack = sawBack + 1
				end
				nextAt = now + 1.1
			end
			T.check(trips == 3 and sawBack == 3, fmt("feel dash flurry: attacks 1.1 s apart: a full round trip each time (%d from out, %d hops back)", trips, sawBack))
		end)
		env.done()
		T.check(ok, "feel dash flurry: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	S.client_feel_dash_off = guarded("client_feel_dash_off", function()
		local env = setup("off")
		if not env then
			return
		end
		local AF, M = env.AF, env.M
		local ok, err = pcall(function()
			-- a pet already at the edge (gap 1.2 < MinGap 1.5): no dash
			local a = unitModel(env.holder, "Near", V3(0, G + 1.5, 0))
			local b = unitModel(env.holder, "NearT", V3(0, G + 1.5, -3.5))
			local r = AF.Dash(1, { Unit = 1, Model = a, Pos = V3(0, G + 1.5, 0) }, { Unit = 2, Model = b, Pos = V3(0, G + 1.5, -3.5) }, env.clock + 0.45, env.clock, {})
			T.check(r == false and AF.Pose(1) == nil and AF.DashState(1) == "out", "feel dash off: a gap under MinGap 1.5 studs: Dash returns false (today's Strike), no pose")
			-- Melee.Dash = false: false
			local src, tgt = pair(env, 20, 3)
			M.Dash = false
			T.check(AF.Dash(3, src, tgt, env.clock + 0.45, env.clock, {}) == false and AF.Pose(3) == nil, "feel dash off: Melee.Dash = false: Dash returns false")
			M.Dash = true
			-- "no hit": a dash whose hit never comes still bites and returns; no unit is left held in
			local errors0 = AF.Stats().Errors
			local land = env.clock + 0.45
			T.check(AF.Dash(3, src, tgt, land, env.clock, {}) == true, "feel dash off: a dash with no hit after it is taken")
			local streaks = AF.Stats().Streaks
			T.check(streaks == 1, fmt("feel dash off: High: one speed streak rides it (%s)", tostring(streaks)))
			local sawIn = false
			env.runTo(land - 0.1, function()
				local p = AF.Pose(3)
				sawIn = sawIn or (p ~= nil and p.Name == "DashIn")
			end)
			env.runTo(land + M.Bite + M.Hold + M.Back + 0.02)
			T.check(sawIn and AF.DashState(3) == "out" and AF.Pose(3) == nil and AF.Stats().Errors == errors0,
				fmt("feel dash off: no hit: DashIn, then out by landAt + 0.60, no error (%s)", AF.DashState(3)))
			T.check(AF.Stats().Streaks == 0, "feel dash off: ... and its streak is back in the pool")
			-- Low graphics: the dash runs, no streak
			AF.SetQuality("Low")
			AF.Update(env.clock)
			local land2 = env.clock + 0.45
			T.check(AF.Dash(3, src, tgt, land2, env.clock, { Low = true }) == true and AF.Stats().Streaks == 0, "feel dash off: Low graphics: the dash runs, no Trail kit taken")
			env.runTo(land2)
			T.check(AF.DashState(3) == "in" and abs(env.fwd(3) - 9.7) < 0.1, fmt("feel dash off: Low: at the edge at the landing (%.2f)", env.fwd(3)))
			AF.SetQuality("High")
			env.run(1)
		end)
		env.done()
		T.check(ok, "feel dash off: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	-- (review fix) a Dash caught on the hop back whose run starts later (t0 = land - In > now): the DashIn starts where the
	-- hop has got to AT t0 (the old DashBack plays on until then), not where it was at the call: no forward snap
	S.client_feel_dash_rejoin = guarded("client_feel_dash_rejoin", function()
		local env = setup("rejoin")
		if not env then
			return
		end
		local AF, M, PP = env.AF, env.M, env.PP
		local ok, err = pcall(function()
			local unit = 5
			local src, tgt = pair(env, 40, unit)
			local land1 = env.clock + 0.45
			T.check(AF.Dash(unit, src, tgt, land1, env.clock, { Tempo = 0.9 }) == true, "feel dash rejoin: the first dash is taken")
			local _, d1 = AF.DashState(unit)
			if not T.check(type(d1) == "table" and type(d1.BackAt) == "number", "feel dash rejoin: (setup) the dash record") then
				return
			end
			local backAt, backDur, edge = d1.BackAt, d1.BackDur, d1.Reach
			env.runTo(backAt + 0.05)
			T.check(AF.DashState(unit) == "back", fmt("feel dash rejoin: (setup) on the hop back (%s)", AF.DashState(unit)))
			-- an NPC Windup lands 0.45 s ahead: the run starts at land - In = now + 0.15
			local now = env.clock
			local land2 = now + 0.45
			local t0 = land2 - M.In
			T.check(AF.Dash(unit, src, tgt, land2, now, { Tempo = 0.9 }) == true, "feel dash rejoin: the dash caught on the hop back is taken")
			local p0 = math.max(0, math.min(1, (t0 - backAt) / backDur))
			local smp = PP.Sample("DashBack", p0, false, 1, edge)
			local want = -smp.Body.Position.Z
			local prevFwd, first = env.fwd(unit), nil
			env.runTo(t0 + 0.2, function()
				local pose = AF.Pose(unit)
				if not first and pose and pose.Name == "DashIn" then
					first = { Forward = pose.Forward or 0, Prev = prevFwd, Fwd = env.fwd(unit) }
				end
				prevFwd = env.fwd(unit)
			end)
			if not T.check(first ~= nil, "feel dash rejoin: the DashIn starts") then
				return
			end
			T.check(abs(first.Forward - want) < 0.05,
				fmt("feel dash rejoin: the DashIn starts where the hop back is at its run's start t0 (Forward %.2f, the hop at t0 %.2f)", first.Forward, want))
			T.check(first.Fwd - first.Prev < 1.5,
				fmt("feel dash rejoin: no forward snap from the last hop-back frame to the first DashIn frame (%.2f -> %.2f)", first.Prev, first.Fwd))
		end)
		env.done()
		T.check(ok, "feel dash rejoin: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	-- (gate fix) Melee.Hop is a real knob: AttackFx.Dash hands it to PetPoses' DashIn (it was a fixed 0.5 there, so the
	-- owner's number did nothing); the hop's peak over the run (p 0 .. DASH_RUN 0.78) is the knob's studs, clamped 0..3
	S.client_feel_dash_hop = guarded("client_feel_dash_hop", function()
		local env = setup("hop")
		if not env then
			return
		end
		local AF, M, PP = env.AF, env.M, env.PP
		local ok, err = pcall(function()
			local function peak()
				local best = -1
				for i = 0, 156 do -- p 0 .. 0.78 (the bite's squash starts after the run)
					local s = PP.Sample("DashIn", i / 200, false, 1, 9.7)
					if s.Body.Position.Y > best then
						best = s.Body.Position.Y
					end
				end
				return best
			end
			T.check(env.saved.Hop == 0.5, fmt("feel dash hop: (setup) the shipped Melee.Hop is 0.5 (%s)", tostring(env.saved.Hop)))
			for i, case in ipairs({ { 0.5, 0.5 }, { 1.2, 1.2 }, { 0, 0 }, { 9, 3 } }) do
				M.Hop = case[1]
				local unit = 20 + 2 * i
				local src, tgt = pair(env, 60 + 20 * i, unit)
				T.check(AF.Dash(unit, src, tgt, env.clock + 0.45, env.clock, {}) == true, fmt("feel dash hop: a dash at Hop %s is taken", tostring(case[1])))
				local got = peak()
				T.check(abs(got - case[2]) < 0.02, fmt("feel dash hop: Melee.Hop %s -> the DashIn hop peaks at %.2f studs (%.2f)", tostring(case[1]), case[2], got))
			end
		end)
		PP.DashHop = nil -- the next dash sets it again; other pose checks read the default
		env.done()
		T.check(ok, "feel dash hop: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	-- (review fix) at the shipped knob (Standoff 0) a melee pet rests where the server orbits it: reach - 0.5 from the
	-- target's centre. The dash + hop back must still play there: vs a raid boss and vs a pet (MinGap under those gaps)
	S.client_feel_dash_gap = guarded("client_feel_dash_gap", function()
		local env = setup("gap")
		if not env then
			return
		end
		local AF = env.AF
		local BCat = moduleAt(ROOTS.shared .. "/BattleCatalog")
		local PC = moduleAt(ROOTS.shared .. "/PetCatalog")
		local PB = moduleAt(ROOTS.shared .. "/PetBuilder")
		local ok, err = pcall(function()
			if not T.check(BCat ~= nil and PC ~= nil and PB ~= nil and env.BB ~= nil, "feel dash gap: (setup) BattleCatalog, PetCatalog, PetBuilder, BossBuilder load") then
				return
			end
			local so = tonumber(BCat.Damage.Standoff) or 0
			local def = PC.Get("storm_tabby")
			local st = BCat.UnitStats(def, 20)
			local range = st and st.Range
			if not T.check(type(range) == "number" and not st.Ranged, fmt("feel dash gap: (setup) storm_tabby is melee, range %s", tostring(range))) then
				return
			end
			local function restDash(unit, targetModel, targetRadius, z0, x)
				local m = PB.Build(def, { Detail = "Low", Scale = 1.3 }) -- (BattleController K.PET_SCALE: battle pets are drawn x1.3)
				m.Parent = env.holder
				local d = range + targetRadius + so - 0.5 -- the server's rest spot (BattleSim's orbit / harness stop)
				local pos = V3(x, G + 1.5, z0 + d)
				m:PivotTo(CFrame.lookAt(pos, V3(x, G + 1.5, z0)))
				local tp = targetModel:GetPivot().Position
				local r = AF.Dash(unit, { Unit = unit, Model = m, Pos = pos }, { Unit = unit + 1000, Model = targetModel, Pos = tp }, env.clock + 0.45, env.clock, {})
				local gap = AF.LeapReach({ Model = m, Last = pos }, { Model = targetModel, Last = tp })
				return r, d, gap
			end
			local ids = {}
			for id in pairs(BCat.Bosses) do
				ids[#ids + 1] = id
			end
			table.sort(ids)
			local missed, gaps, unit = {}, {}, 1
			for i, id in ipairs(ids) do
				local boss = env.BB.Build(id, { Detail = "Low", CFrame = CFrame.new(i * 120, G, -30) })
				if boss then
					boss.Parent = env.holder
					local rb, db, gb = restDash(unit, boss, BCat.Bosses[id].Radius, -30, i * 120)
					gaps[#gaps + 1] = fmt("%s %.1f off, gap %.2f pose studs, dash %s", id, db, gb or -1, tostring(rb))
					-- (a box that reaches past the rest spot, the Shadow Hydra's spread necks: no room, today's Strike)
					if rb ~= true and (gb or 0) > 0 then
						missed[#missed + 1] = id
					end
					unit = unit + 1
				end
			end
			T.info("feel dash gap: the bosses", table.concat(gaps, "; "))
			T.check(#ids >= 4 and #missed == 0, fmt("feel dash gap: at the shipped Standoff %s a melee pet at the server's rest spot dashes in and hops back vs every raid boss (%d bosses)", tostring(so), #ids),
				table.concat(missed, ", "))
			local bear = PB.Build(PC.Get("biscuit_bear"), { Detail = "Low", Scale = 1.3 })
			bear.Parent = env.holder
			bear:PivotTo(CFrame.new(60, G + 1.5, -30))
			local bearR = BCat.UnitStats(PC.Get("biscuit_bear"), 18).Radius
			local rp, dp, gp = restDash(100, bear, bearR, -30, 60)
			T.check(rp == true, fmt("feel dash gap: ... and vs a pet (a bear, %.1f studs off its centre, gap %s)", dp, tostring(gp)))
			T.check(type(env.M.MinGap) == "number" and env.M.MinGap >= 1, fmt("feel dash gap: MinGap stays at least 1 stud (no twitch dashes) (%s)", tostring(env.M.MinGap)))
		end)
		env.done()
		T.check(ok, "feel dash gap: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	S.client_feel_dash_budget = guarded("client_feel_dash_budget", function()
		local env = setup("budget")
		if not env then
			return
		end
		local AF = env.AF
		local ok, err = pcall(function()
			local boss = env.BB and env.BB.Build("lava_golem", { Detail = "Low", CFrame = CFrame.new(0, G, -30) })
			if not T.check(boss ~= nil, "feel dash budget: (setup) a lava golem") then
				return
			end
			boss.Parent = env.holder
			local tgt = { Unit = 900, Model = boss, Pos = boss:GetPivot().Position }
			local land = env.clock + 0.45
			local taken = 0
			for i = 1, 8 do
				local x = (i - 4.5) * 4
				local m = unitModel(env.holder, "Pet" .. i, V3(x, G + 1.5, 0))
				if AF.Dash(i, { Unit = i, Model = m, Pos = V3(x, G + 1.5, 0) }, tgt, land, env.clock, { Mine = (i == 8) }) then
					taken = taken + 1
				end
			end
			local s = AF.Stats()
			local _, mine = AF.DashState(8)
			T.check(taken == 8 and s.Streaks == 4, fmt("feel dash budget: eight dashes in one frame: all taken, %d streaks (StreakMax 4)", s.Streaks or -1))
			T.check(type(mine) == "table" and mine.Streak == true, "feel dash budget: my pet's dash keeps a streak at the cap (mine first)")
			env.runTo(land - 0.15)
			local n1 = #workspace:GetDescendants()
			env.run(env.DT)
			local n2 = #workspace:GetDescendants()
			T.check(n1 == n2, fmt("feel dash budget: no new Instance between two Updates mid-dash (%d vs %d)", n1, n2))
			env.runTo(land + 1)
			local s2 = AF.Stats()
			local folder = AF.Folder()
			T.check(s2.Streaks == 0 and s2.Trails == 0 and s2.Pooled <= AF.POOL_KEEP_TOTAL and s2.PoolInstances == #folder:GetDescendants(),
				fmt("feel dash budget: after: no streak live, every kit pooled within the keep (%d pooled / %d, %d instances vs folder %d)", s2.Pooled, AF.POOL_KEEP_TOTAL, s2.PoolInstances, #folder:GetDescendants()))
			local allOut = true
			for i = 1, 8 do
				allOut = allOut and AF.DashState(i) == "out"
			end
			T.check(allOut, "feel dash budget: all eight back out")
		end)
		env.done()
		T.check(ok, "feel dash budget: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	-- the BattleController half: a real BattleSim stepped at 10 Hz, sent the way BattleService sends it
	----------------------------------------------------------------------------------------------
	local function driver(BS, myKey, foeKey, auto)
		local me = LocalPlayer.UserId
		local id = "feel_dash_" .. tostring(math.random(100000, 999999))
		local sim = BS.new({ Mode = "Duel", Seed = 13, Id = id, Zone = { X = 60, Z = 60 }, TimeLimit = 120,
			Teams = { { Owner = me, Side = 1, Pets = { { Key = myKey, PetId = myKey, Level = 20, Tier = "Normal", Slot = 1 } }, Auto = auto },
				{ Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = { { Key = foeKey, Level = 18, NoSpecial = true, Slot = 1 } } } } })
		if not sim then
			return nil
		end
		local d = { sim = sim, id = id, me = me, last = {} }
		local tm = sim.teams[1]
		d.tm, d.f = tm, tm.fighter
		d.f.x, d.f.z, d.f.px, d.f.pz = 0, -8, 0, -8
		d.f.maxHp, d.f.hp = 1e9, 1e9
		tm.wantX, tm.wantZ = 0, -8
		tm.elementReadyAt = huge
		for _, u in ipairs(sim.units) do
			if u.side == 2 then
				d.foe = u
				u.x, u.z, u.px, u.pz = 0, 14, 0, 14
				u.maxHp, u.hp = 1e9, 1e9
			end
		end
		local p = sim:Describe()
		p.BattleId = id
		p.Zone = { CFrame = CFrame.new(0, 200, 0), Size = V3(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
		p.Names = { [tostring(me)] = LocalPlayer.Name }
		p.Side, p.Spectator, p.T = 1, false, sim:Time()
		local team = sim:TeamOf(me)
		if team then
			p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
				Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = {} } }
		end
		LocalPlayer:SetAttribute("InBattle", id)
		KC.toClient("BattleState", "Start", p, id)
		function d.step(each)
			d.f.meter = 0
			local evs = sim:Step(0.1)
			if #evs > 0 then
				KC.toClient("BattleState", "Events", evs, id)
			end
			local snap = sim:SnapshotDelta(d.last)
			snap.BattleId = id
			KC.toClient("BattleState", "Snapshot", snap, id)
			for _ = 1, 3 do
				Mock.Step(0.1 / 3)
				if each then
					each()
				end
			end
			return evs
		end
		function d.finish()
			KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }, id)
			LocalPlayer:SetAttribute("InBattle", nil)
			KC.advance(15)
			Mock.Step(0.1)
		end
		return d
	end

	-- spies on AttackFx.Dash / Play / Update and BattleController's damage numbers; undo() puts them back
	local function spies(AF, BC, PP, watch)
		local sp = { dash = {}, play = {}, frames = {}, numbers = {} }
		local realDash, realPlay, realUpdate = AF.Dash, AF.Play, AF.Update
		local Fx = BC._Fx
		local realNumber = Fx and Fx.Number
		AF.Dash = function(unit, src, tgt, landAt, now, opts)
			local r = realDash(unit, src, tgt, landAt, now, opts)
			sp.dash[#sp.dash + 1] = { Unit = unit, LandAt = landAt, Now = now, At = os.clock(), Result = r, Mine = type(opts) == "table" and opts.Mine or nil }
			return r
		end
		AF.Play = function(ctx)
			local c = { Attack = ctx.Attack, From = type(ctx.From) == "table" and ctx.From.Unit or nil, DueAt = ctx.DueAt, Dashed = ctx.Dashed == true, At = os.clock() }
			c.Result = realPlay(ctx)
			sp.play[#sp.play + 1] = c
			return c.Result
		end
		AF.Update = function(now)
			realUpdate(now)
			for _, unit in ipairs(watch) do
				local pose = AF.Pose(unit)
				sp.frames[#sp.frames + 1] = { Unit = unit, T = now, Name = pose and pose.Name or nil, Fwd = fwdOf(PP, pose), State = AF.DashState(unit) }
			end
		end
		if Fx and realNumber then
			Fx.Number = function(adornee, height, text, color, px, life)
				sp.numbers[#sp.numbers + 1] = { Text = tostring(text), At = os.clock() }
				return realNumber(adornee, height, text, color, px, life)
			end
		end
		function sp.undo()
			AF.Dash, AF.Play, AF.Update = realDash, realPlay, realUpdate
			if Fx and realNumber then
				Fx.Number = realNumber
			end
		end
		return sp
	end

	local function frameAt(sp, unit, t)
		local best, bd = nil, huge
		for _, f in ipairs(sp.frames) do
			if f.Unit == unit and abs(f.T - t) < bd then
				best, bd = f, abs(f.T - t)
			end
		end
		return best
	end

	local function loadBattle(tag)
		local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
		local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local BS = moduleAt(ROOTS.shared .. "/BattleSim")
		local PP = moduleAt(ROOTS.shared .. "/PetPoses")
		local Config = moduleAt(ROOTS.shared .. "/Config")
		local M = Config and Config.Battle and Config.Battle.Feel and Config.Battle.Feel.Melee
		if not T.check(BC ~= nil and AF ~= nil and BS ~= nil and PP ~= nil and type(M) == "table" and type(AF.Dash) == "function" and type(AF.DashState) == "function",
			tag .. ": BattleController, AttackFx (Dash, DashState), BattleSim, PetPoses, Config.Battle.Feel.Melee load") then
			return nil
		end
		AF.SetQuality("High")
		return BC, AF, BS, PP, M
	end

	-- the client world's BattleCatalog (the driver's sim reads it) at Standoff `so` for fn, put back after
	local function atStandoff(so, fn)
		local BCat = moduleAt(ROOTS.shared .. "/BattleCatalog")
		local keep = BCat and BCat.Damage.Standoff
		if BCat then
			BCat.Damage.Standoff = so
		end
		local ok, err = pcall(fn)
		if BCat then
			BCat.Damage.Standoff = keep
		end
		if not ok then
			error(err, 0)
		end
	end

	S.client_feel_dash_npc = guarded("client_feel_dash_npc", function()
		local BC, AF, BS, PP, M = loadBattle("feel dash npc")
		if not BC then
			return
		end
		atStandoff(8, function()
		local d = driver(BS, "puddle_frog", "biscuit_bear", false)
		if not T.check(d ~= nil and d.foe ~= nil, "feel dash npc: (setup) a Duel at Standoff 8: my standing frog vs an NPC bear") then
			return
		end
		d.tm.noEngage = true
		local foe, mine = d.foe.id, d.f.id
		local sp = spies(AF, BC, PP, { foe, mine })
		local ok, err = pcall(function()
			local windAt = nil
			for _ = 1, 100 do
				d.f.nextAttack = huge
				d.tm.wantX, d.tm.wantZ = 0, -8
				local evs = d.step()
				for _, ev in ipairs(evs) do
					if ev.type == "Windup" and ev.unit == foe and not windAt then
						windAt = ev.at
					end
				end
				local got = false
				for _, c in ipairs(sp.dash) do
					got = got or (c.Unit == foe and c.Result == true)
				end
				if got then
					break
				end
			end
			local call = nil
			for _, c in ipairs(sp.dash) do
				if c.Unit == foe and c.Result == true then
					call = c
					break
				end
			end
			if not T.check(windAt ~= nil and call ~= nil, fmt("feel dash npc: the bear's Windup dashes it (AttackFx.Dash taken; Windup at %s)", tostring(windAt))) then
				return
			end
			local _, info = AF.DashState(foe)
			local edge = type(info) == "table" and info.Reach or nil
			T.check(call.LandAt - call.At > 0.25 and call.LandAt - call.At < 0.6, fmt("feel dash npc: the dash lands on ev.at on the render clock (%.2f s after the Windup played)", call.LandAt - call.At))
			for _ = 1, 12 do
				d.step()
			end
			local fl = frameAt(sp, foe, call.LandAt)
			T.check(fl ~= nil and fl.Name == "DashIn" and edge ~= nil and abs(fl.Fwd - edge) < 0.35,
				fmt("feel dash npc: at the landing the bear is in DashIn at the edge (%s, %.2f of %s studs)", tostring(fl and fl.Name), fl and fl.Fwd or -1, tostring(edge)))
			local before = frameAt(sp, foe, call.LandAt - 0.12)
			T.check(before ~= nil and before.Name == "DashIn" and before.Fwd > 0.5, fmt("feel dash npc: ... running in before the hit (%s, %.2f)", tostring(before and before.Name), before and before.Fwd or -1))
			local hit = nil
			for _, c in ipairs(sp.play) do
				if c.From == foe and c.Attack == "Melee" and c.At >= call.At - 1e-6 then
					hit = c
					break
				end
			end
			T.check(hit ~= nil and hit.Result == true and hit.Dashed == true and abs(hit.DueAt - call.LandAt) < 0.2,
				fmt("feel dash npc: its Hit plays Dashed, the impact on the landing (due %s vs land %.2f)", tostring(hit and hit.DueAt), call.LandAt))
			local strike, hurt = false, false
			for _, f in ipairs(sp.frames) do
				if f.Unit == foe and f.T >= call.At and f.T <= call.LandAt + 0.6 and f.Name == "Strike" then
					strike = true
				end
				if f.Unit == mine and f.T >= call.LandAt - 0.2 and f.T <= call.LandAt + 0.5 and f.Name == "Hurt" then
					hurt = true
				end
			end
			T.check(not strike, "feel dash npc: ... with NO Strike segment (the dash is the attack)")
			T.check(hurt, "feel dash npc: my pet flinches (Hurt) at the impact")
			local back = frameAt(sp, foe, call.LandAt + M.Bite + M.Hold + 0.08)
			T.check(back ~= nil and back.Name == "DashBack", fmt("feel dash npc: DashBack from landAt + 0.20 (%s)", tostring(back and back.Name)))
			local out = frameAt(sp, foe, call.LandAt + M.Bite + M.Hold + M.Back + 0.06)
			T.check(out ~= nil and out.State == "out", fmt("feel dash npc: out by landAt + 0.60 (%s)", tostring(out and out.State)))
		end)
		sp.undo()
		d.finish()
		T.check(ok, "feel dash npc: no error", tostring(err))
		end)
	end)

	S.client_feel_dash_mine = guarded("client_feel_dash_mine", function()
		local BC, AF, BS, PP, M = loadBattle("feel dash mine")
		if not BC then
			return
		end
		local function fight(dashOn)
			M.Dash = dashOn
			local d = driver(BS, "storm_tabby", "biscuit_bear", false)
			if not d then
				M.Dash = true
				return nil
			end
			d.foe.moveSpeed, d.foe.nextAttack = 0, huge
			local mine = d.f.id
			local sp = spies(AF, BC, PP, { mine })
			local res = {}
			local ok, err = pcall(function()
				for _ = 1, 90 do
					d.foe.nextAttack = huge
					d.step()
					local n = 0
					for _, c in ipairs(sp.play) do
						if c.From == mine and c.Attack == "Melee" then
							n = n + 1
						end
					end
					if n >= 2 then
						break
					end
				end
				for _ = 1, 8 do
					d.step()
				end
				for _, c in ipairs(sp.play) do
					if c.From == mine and c.Attack == "Melee" then
						res.play = c
						break
					end
				end
				for _, c in ipairs(sp.dash) do
					if c.Unit == mine then
						res.dash = c
						break
					end
				end
				if res.play then
					-- the first number after the play's arrival (my hit on the bear)
					for _, n in ipairs(sp.numbers) do
						if n.At >= res.play.At - 1e-6 and tonumber(n.Text) then
							res.number = n
							break
						end
					end
				end
				local strike, dashIn = false, false
				for _, f in ipairs(sp.frames) do
					strike = strike or f.Name == "Strike"
					dashIn = dashIn or f.Name == "DashIn"
				end
				res.strike, res.dashIn = strike, dashIn
			end)
			sp.undo()
			d.finish()
			M.Dash = true
			if not ok then
				error(err, 0)
			end
			return res
		end
		local on, off
		atStandoff(8, function()
			on = fight(true)
			off = fight(false)
		end)
		if not T.check(on ~= nil and on.play ~= nil, "feel dash mine: my melee fighter attacks the bear (a Melee play)") then
			return
		end
		T.check(on.dash ~= nil and on.dash.Result == true and on.play.Dashed and abs(on.dash.LandAt - on.play.DueAt) < 1e-6 and on.dash.Mine == true,
			fmt("feel dash mine: my fighter's Hit (no Windup) dashes it: Dash lands at the play's DueAt (%s vs %s), Dashed, Mine",
				tostring(on.dash and on.dash.LandAt), tostring(on.play.DueAt)))
		T.check(on.play.DueAt - on.play.At >= M.In - 1e-6, fmt("feel dash mine: the impact is held In 0.30 s past the event (%.2f s after its arrival)", on.play.DueAt - on.play.At))
		T.check(on.number ~= nil and on.number.At >= on.play.DueAt - 0.06, fmt("feel dash mine: the damage number plays with the impact, 0.30 s late (fxLate) (number %.2f vs impact %.2f)",
			on.number and on.number.At or -1, on.play.DueAt))
		T.check(on.dashIn, "feel dash mine: my pet's pose is DashIn")
		if not T.check(off ~= nil and off.play ~= nil, "feel dash mine: (Melee.Dash = false) my fighter attacks") then
			return
		end
		T.check((off.dash == nil or off.dash.Result == false) and not off.play.Dashed and not off.dashIn and off.strike,
			"feel dash mine: Melee.Dash = false: no dash, today's Strike")
		T.check(off.play.DueAt - off.play.At < M.In - 0.05 and off.number ~= nil and off.number.At <= off.play.DueAt + 0.06,
			fmt("feel dash mine: ... the impact and the number at the event (fxLate 0) (due +%.2f, number %.2f vs %.2f)", off.play.DueAt - off.play.At, off.number and off.number.At or -1, off.play.DueAt))
		-- the shipped knob (Config.Battle.Feel.Melee.Standoff, 0 in sleep mode): the pet rests at today's spot and dashes only
		-- across a gap of MinGap; either way the impact and the number agree (held In when dashed, at the event when not)
		local def = fight(true)
		if T.check(def ~= nil and def.play ~= nil, "feel dash mine: (the shipped Standoff) my fighter attacks") then
			local held = def.play.DueAt - def.play.At
			local agree = def.number ~= nil and abs(def.number.At - def.play.DueAt) < 0.07
			T.check(agree and ((def.play.Dashed and def.dashIn and held >= M.In - 1e-6) or (not def.play.Dashed and def.strike and held < M.In - 0.05)),
				fmt("feel dash mine: at the shipped Standoff the bite is a dash (held %.2f) or today's Strike, the number with the impact (dashed %s)", held, tostring(def.play.Dashed)))
		end
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
