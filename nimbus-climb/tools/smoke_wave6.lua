-- smoke_wave6.lua: wave 6 "fight focus" (docs/superpowers/specs/2026-10-29-fight-focus-wave6-design.md, plan
-- docs/superpowers/plans/2026-10-29-fight-focus-wave6-plan.md). Loaded by tools/smoke.py in BOTH worlds (ARGS.context).
-- The engage rule itself (any enemy in the fight area, owner movement ignored) is pinned by smoke_fight.lua.
--   w6_dash_parry         (server world, pure) Dash = a sidestep out of the threat, a timed Dash = a Parry: an NPC wind-up
--                         parried 0.15 s before it lands (Parry event, 0 damage, the NPC stunned 0.4 s, +8 meter, the wind-up
--                         cancelled), too early = no parry and the hit lands; a boss circle telegraph parried (the Hit is
--                         miss + parry, the pet leaves the circle straight away from its centre, the boss starts nothing
--                         for 0.4 s, a second parry within ParryBossGap gives no new stagger), a Line telegraph =
--                         perpendicular on the pet's side; no threat = perpendicular to the aim toward the floor centre,
--                         a corner keeps it on the floor and never closer to the aim; an engaged pet moves along the
--                         sidestep, then walks back and swings; Validate rejects bad Parry numbers
--   w6_cheer_core         (server world, pure) Cheer up! in Raid and Dungeon: +5% on the fighter's plain hits (two seeded
--                         battles compared), Cooldowns.Cheer 20, no stacking, off after 5 s, ready after 20 s; Ring / Duel
--                         NoCheer, Down, an Npc team refused; Validate
--   w6_cheer_service      (server world, booted) BattleCommand("Cheer") in a party dungeon encounter: the sim boost and
--                         the Cheer event to both members; 40 calls in 1 s = ONE accepted, <= 1 rejected echo a step, ONE
--                         throttled toast, no stacking; junk refused without errors; no battle -> NoBattle; the Start
--                         payload's Team.Cooldowns.Cheer = 0; a raid accepts it, a duel refuses NoCheer
--   w6_podium_find        (server world, booted) the podium = the stand each mode teleports the trainer to: the Ring's
--                         Zone.Spawn sits on the pocket's SpawnPad (outside the 44-stud floor), each duellist's stand on a
--                         ChallengePad of its ring
--   w6_podium_lock        (server world, booted) Ring round start = root Anchored at the SpawnPad + OnPodium; a 6-stud
--                         nudge undone in one tick; Cheer = NoCheer; 12 s locked = no leash, the pet waits at the floor
--                         edge; the round's End frees it, the next round re-locks; one toast a run; death mid-round /
--                         respawn never leave an anchored character; a duel locks both, a forfeit frees both; a
--                         disconnect clears the record; Shutdown frees everyone; raid joiners / dungeon members never
--   client_w6_podium_cheer (client world) OnPodium = true loops Animate.PlayEmote("cheer") (now, again within 4.5 s),
--                         nil stops it; my own Cheer event plays once, another owner's none; not standing = retries;
--                         no PlayEmote = false, no error; no Sound instance
--   client_w6_cheer_button (client world) HudController.GetLayout().Vitals; a dungeon / raid fight shows "Cheer up!" 8 px
--                         above the vitals card, centred on it, on screen and covering nothing (1920x1080, 1366x768); a
--                         click = ONE BattleCommand("Cheer"), the Cheer event = the glow 5 s + the sweep 20 s + one emote;
--                         a click in the cooldown sends nothing and shakes; ready again after 20 s; Ring / Duel: none;
--                         End takes it away
--   client_w6_cheer_mobile (phone world) the same placement at 844x390 / 390x844 / 749x388 on a touch phone (a landscape
--                         phone: the spot above is the screen middle, so beside the card on the left, top level), >= 44x44 px,
--                         clear of the action cluster, RUN / DASH and Roblox's jump button
-- White-box: the server half reaches into battle.units / battle.teams / battle.telegraphs (same Lua state). Plain Lua 5.1
-- syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, sqrt, huge, max, min = math.abs, math.floor, math.sqrt, math.huge, math.max, math.min
local cos, sin, atan2 = math.cos, math.sin, math.atan2
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

	local function append(all, evs)
		for _, ev in ipairs(evs) do
			all[#all + 1] = ev
		end
		return all
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
	local function stepAt(b, x, z, owner)
		if x ~= nil then
			b:Command(owner or 1, "Move", x, z)
		end
		return b:Step(0.1)
	end

	-- steps while standing at (x, z) until pred(events, i) or n steps; -> all events, the step count
	local function standFor(b, n, x, z, pred)
		local all = {}
		for i = 1, n do
			local evs = stepAt(b, x, z)
			append(all, evs)
			if pred and pred(evs, i) then
				return all, i
			end
		end
		return all, n
	end

	local function engaged(b, owner)
		local tm = b:TeamOf(owner or 1)
		return tm and tm.Engaged
	end

	-- the events a command queued (they come out on the next Step); the command's own result
	local function pendingOf(b)
		local out = {}
		for _, ev in ipairs(b.pending or {}) do
			out[#out + 1] = ev
		end
		return out
	end

	-- an NPC that fights for real (no arrival), next to my fighter: steps until its wind-up on my fighter starts
	local function windupWorld(BS, seed)
		local b, tm = world(BS, "storm_tabby", 12, seed)
		local f = tm.fighter
		put(f, 0, -10)
		f.maxHp, f.hp = 1e6, 1e6
		local infos = b:SpawnEnemies({ pet("biscuit_bear", 20) }, { Wave = 1, Anchor = { 0, 20 } })
		local npc = b.units[infos[1].id]
		npc.arriveUntil, npc.iframesUntil = nil, 0
		npc.maxHp, npc.hp = 1e9, 1e9
		npc.specialKind = nil
		npc.nextAttack = 0
		put(npc, 0, -7)
		local windT = nil
		for _ = 1, 40 do
			local evs = stepAt(b, 0, -10)
			if find(evs, "Windup", function(x)
				return x.unit == npc.id and x.target == f.id
			end) then
				windT = b:Time()
				break
			end
		end
		return b, tm, f, npc, windT
	end

	------------------------------------------------------------------------------------------------
	-- w6_dash_parry
	------------------------------------------------------------------------------------------------
	S.w6_dash_parry = guarded("w6_dash_parry", function()
		local BC = loadModule("BattleCatalog")
		local BS = loadModule("BattleSim")
		if not T.check(BC and BS, "dash/parry: BattleCatalog + BattleSim load") then
			return
		end
		local F = BC.Fighter
		T.check(F.ParryWindow == 0.25 and F.ParryStagger == 0.4 and F.ParryMeter == 8 and F.ParryBossGap == 3 and F.DashIFrames == 0.35 and F.DashCooldown == 2.5
			and F.DashSeconds == 0.35 and BS.Events.Parry == "Parry", "dash/parry: Fighter.ParryWindow 0.25 / ParryStagger 0.4 / ParryMeter 8 / ParryBossGap 3; Dash numbers unchanged; Events.Parry")

		-- (a): an NPC wind-up parried 0.15 s before it lands
		do
			local b, tm, f, npc, windT = windupWorld(BS, 5)
			if T.check(windT ~= nil and npc.windAt ~= nil, "dash/parry (a): (setup) the NPC winds up on my fighter") then
				local windAt = npc.windAt
				while b:Time() < windAt - 0.15 - 1e-6 do
					stepAt(b, 0, -10)
				end
				local tPress = b:Time()
				local hp0 = f.hp
				f.meter = 50
				local ok = b:Command(1, "Dash")
				local queued = pendingOf(b)
				local parry = find(queued, "Parry")
				T.check(ok and parry ~= nil and parry.unit == f.id and parry.from == npc.id and parry.tele == nil and abs(windAt - tPress - 0.15) < 0.051,
					"dash/parry (a): a Dash 0.15 s before the wind-up lands = ONE Parry { unit = fighter, from = the NPC }", fmt("press %.2f s before", windAt - tPress))
				T.check(abs(f.meter - 58) < 1e-6, "dash/parry (a): ...the pet gains ParryMeter (+8)", fmt("%.2f", f.meter))
				T.check(npc.stunUntil >= tPress + 0.4 - 0.05 and npc.windAt == nil, "dash/parry (a): ...the NPC is staggered 0.4 s (stunned, its wind-up cancelled)", fmt("stun until +%.2f", npc.stunUntil - tPress))
				local after = {}
				while b:Time() < windAt + 0.3 do
					append(after, stepAt(b, 0, -10))
				end
				T.check(f.hp >= hp0 and find(after, "Hit", function(x)
					return x.from == npc.id and x.to == f.id
				end) == nil, "dash/parry (a): ...no damage and no DODGED miss for the cancelled wind-up", fmt("hp %.0f -> %.0f", hp0, f.hp))
			end
		end

		-- (b): too early (the wind-up's start, 0.45 s before it lands): no parry, the hit lands, the cooldown is spent
		do
			local b, tm, f, npc, windT = windupWorld(BS, 6)
			if T.check(windT ~= nil, "dash/parry (b): (setup) the NPC winds up on my fighter") then
				local windAt = npc.windAt
				local ok = b:Command(1, "Dash")
				local queued = pendingOf(b)
				local cd = b:TeamOf(1).Cooldowns.Dash
				local after = {}
				while b:Time() < windAt + 0.25 do
					append(after, stepAt(b, 0, -10))
				end
				T.check(ok and find(queued, "Parry") == nil and find(after, "Parry") == nil, "dash/parry (b): a Dash 0.45 s before the hit (outside ParryWindow) is no parry")
				T.check(find(after, "Hit", function(x)
					return x.from == npc.id and x.to == f.id and not x.miss and (x.dmg or 0) > 0
				end) ~= nil, "dash/parry (b): ...the hit lands (the i-frames ended; the wind-up hop stays in the NPC's reach)")
				T.check(cd > 2, "dash/parry (b): ...and the dash cooldown is spent", fmt("%.2f", cd))
			end
		end

		-- (c): a boss circle telegraph parried; the stagger; ParryBossGap; a Line telegraph
		do
			local b = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 3, Teams = { team(1, 1, { pet("cloudy_dragon", 20), pet("pebble_pup", 5), pet("honey_bunny", 5) }), team(2, 1, { pet("biscuit_bear", 30) }) } })
			local boss = b.boss
			local tm, t2 = b.teams[1], b.teams[2]
			local f, g = tm.fighter, t2.fighter
			tm.noEngage, t2.noEngage = true, true
			f.maxHp, f.hp, g.maxHp, g.hp = 1e7, 1e7, 1e7, 1e7
			for i = 1, 12 do
				b:Step(0.1)
			end
			for _, u in ipairs(b.units) do
				if u.side == 2 and u ~= boss then
					u.alive, u.gone = false, true -- (no minions in this check)
				end
			end
			local fx, fz = boss.x + 20, boss.z
			local gx, gz = boss.x, boss.z - boss.radius - 1
			put(f, fx, fz)
			put(g, gx, gz)
			local function both()
				b:Command(2, "Move", gx, gz)
				return stepAt(b, f.x, f.z)
			end
			boss.nextAttack = huge
			for _, entry in ipairs(boss.attacks) do
				entry.nextAt = huge
			end
			for i = #b.telegraphs, 1, -1 do
				b.telegraphs[i] = nil
			end
			both()
			local def = boss.attacks[1].def
			local cx, cz = f.x + 2, f.z
			local t0 = b:Time()
			b.telegraphs[#b.telegraphs + 1] = { id = 901, boss = boss, attack = def, at = t0 + 0.1, shape = "Circle", x = cx, z = cz, r = 8 }
			-- the boss is ready to act the moment the stagger ends
			boss.nextAttack = 0
			for _, entry in ipairs(boss.attacks) do
				entry.nextAt = 0
			end
			f.meter = 20
			local ok = b:Command(1, "Dash")
			local queued = pendingOf(b)
			local parry = find(queued, "Parry")
			local dash = find(queued, "Dash")
			T.check(ok and parry ~= nil and parry.from == boss.id and parry.tele == 901 and abs(f.meter - 28) < 1e-6, "dash/parry (c): a Dash 0.1 s before a boss circle lands = Parry { from = boss, tele = id }, +8 meter",
				fmt("meter %.1f", f.meter))
			local stag = {}
			for _ = 1, 3 do
				append(stag, both())
			end
			local hitTele = find(stag, "Hit", function(x)
				return x.tele == 901 and x.to == f.id
			end)
			T.check(hitTele ~= nil and hitTele.miss == true and hitTele.parry == true and (hitTele.dmg or 0) == 0, "dash/parry (c): ...the telegraph's Hit on the fighter is miss = true, parry = true")
			local out = d2(f.x, f.z, cx, cz)
			local ax, az = (fx - cx), (fz - cz)
			local al = sqrt(ax * ax + az * az)
			local dot = dash and (dash.dir[1] * ax / al + dash.dir[2] * az / al) or -1
			T.check(out > 8 + f.radius and dot > 0.9, "dash/parry (c): ...the pet sidesteps straight away from the circle's centre and ends outside it",
				fmt("%.2f from the centre (r 8 + radius %.1f), dot %.2f", out, f.radius, dot))
			T.check(find(stag, "Hit", function(x)
				return x.from == boss.id and x.tele == nil
			end) == nil and find(stag, "Telegraph") == nil, "dash/parry (c): ...the boss starts no basic attack and no telegraph for 0.4 s (ready, staggered)")
			local woke = {}
			for _ = 1, 10 do
				append(woke, both())
			end
			T.check(find(woke, "Hit", function(x)
				return x.from == boss.id and x.tele == nil
			end) ~= nil or find(woke, "Telegraph") ~= nil, "dash/parry (c): ...and acts again once the stagger ends")
			-- a second parry 1 s later (the cooldown reset white-box): Parry + meter, no new stagger (ParryBossGap 3)
			boss.nextAttack = huge
			for _, entry in ipairs(boss.attacks) do
				entry.nextAt = huge
			end
			for i = #b.telegraphs, 1, -1 do
				b.telegraphs[i] = nil
			end
			local firstAt, firstUntil = boss.staggerAt, boss.staggerUntil
			tm.dashReadyAt = 0
			local t1 = b:Time()
			b.telegraphs[#b.telegraphs + 1] = { id = 902, boss = boss, attack = def, at = t1 + 0.1, shape = "Circle", x = f.x, z = f.z + 1, r = 8 }
			local m1 = f.meter
			local ok2 = b:Command(1, "Dash")
			local q2 = pendingOf(b)
			T.check(ok2 and find(q2, "Parry", function(x)
				return x.tele == 902
			end) ~= nil and abs(f.meter - min(100, m1 + 8)) < 1e-6 and boss.staggerAt == firstAt and boss.staggerUntil == firstUntil and t1 - firstAt < F.ParryBossGap,
				"dash/parry (c): a second parry within ParryBossGap: Parry + meter, but no new boss stagger", fmt("%.1f s after the first", t1 - (firstAt or 0)))
			both()
			both()
			-- a Line telegraph: perpendicular to the line, on the pet's side
			for _ = 1, 30 do
				both()
			end
			tm.dashReadyAt = 0
			put(f, boss.x + 15, boss.z + 1)
			local ang = atan2(0, 1) -- the line runs +X from the boss, 1 stud beside the fighter
			local t3 = b:Time()
			b.telegraphs[#b.telegraphs + 1] = { id = 903, boss = boss, attack = def, at = t3 + 0.2, shape = "Line", x = boss.x, z = boss.z, angle = ang, length = 30, width = 6 }
			b:Command(1, "Dash")
			local q3 = pendingOf(b)
			local dl = find(q3, "Dash")
			local lineDot = dl and (dl.dir[1] * cos(ang) + dl.dir[2] * sin(ang)) or 1
			local sideDot = dl and dl.dir[2] or -1 -- the fighter is on the +Z side of the line
			T.check(dl ~= nil and abs(lineDot) < 0.1 and sideDot > 0.9 and find(q3, "Parry", function(x)
				return x.tele == 903
			end) ~= nil, "dash/parry (c): a Line telegraph: the sidestep is perpendicular to the line (|dot| < 0.1), to the side the pet is on",
				fmt("dot %.2f, side %.2f", lineDot, sideDot))
		end

		-- (d) Review Focus 3: no threat: perpendicular to the aim toward the centre; a corner stays on the floor, never closer
		do
			local b, tm = world(BS)
			local f = tm.fighter
			tm.noEngage = true
			local hx = b.zone.HalfX - f.radius
			put(f, -hx, 0)
			local e = enemiesAt(b, { { -hx, 12 } })[1]
			b:Command(1, "Target", e.id)
			stepAt(b, f.x, f.z)
			local aimX, aimZ = e.x - f.x, e.z - f.z
			local aimL = sqrt(aimX * aimX + aimZ * aimZ)
			b:Command(1, "Dash")
			local dash = find(pendingOf(b), "Dash")
			T.check(dash ~= nil and dash.dir[1] > 0.98 and abs(dash.dir[1] * aimX + dash.dir[2] * aimZ) / aimL < 0.06 and dash.target == nil, "dash/parry (d): no threat, the -X edge, the lock straight +Z: the sidestep is perpendicular to the aim, toward the centre (+X)",
				dash and fmt("dir %.2f, %.2f", dash.dir[1], dash.dir[2]) or "no Dash event")
			-- a corner, the aim diagonal (both perpendiculars run into a wall)
			local b2, tm2 = world(BS)
			local f2 = tm2.fighter
			tm2.noEngage = true
			local cxh, czh = b2.zone.HalfX - f2.radius, b2.zone.HalfZ - f2.radius
			put(f2, -cxh, -czh)
			local e2 = enemiesAt(b2, { { -cxh + 8, -czh + 8 } })[1]
			b2:Command(1, "Target", e2.id)
			stepAt(b2, f2.x, f2.z)
			local before = d2(f2.x, f2.z, e2.x, e2.z)
			b2:Command(1, "Dash")
			local worst = huge
			local onFloor = true
			for _ = 1, 3 do
				stepAt(b2, -cxh, -czh)
				worst = min(worst, d2(f2.x, f2.z, e2.x, e2.z))
				onFloor = onFloor and abs(f2.x) <= b2.zone.HalfX - f2.radius + 1e-6 and abs(f2.z) <= b2.zone.HalfZ - f2.radius + 1e-6
			end
			T.check(onFloor and worst >= before - 1e-6, "dash/parry (d): a dash in a corner stays on the floor and never ends closer to the aim", fmt("%.2f -> min %.2f", before, worst))
			-- a corner with a telegraph centred inside the floor: it still leaves the circle when possible
			local b3 = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 4, Teams = { team(1, 1, { pet("cloudy_dragon", 20) }) } })
			local boss3 = b3.boss
			local tm3 = b3.teams[1]
			local f3 = tm3.fighter
			tm3.noEngage = true
			f3.maxHp, f3.hp = 1e7, 1e7
			boss3.nextAttack = huge
			for _, entry in ipairs(boss3.attacks) do
				entry.nextAt = huge
			end
			local hx3, hz3 = b3.zone.HalfX - f3.radius, b3.zone.HalfZ - f3.radius
			put(f3, -hx3, -hz3)
			b3:Step(0.1)
			for i = #b3.telegraphs, 1, -1 do
				b3.telegraphs[i] = nil
			end
			local ccx, ccz = -hx3 + 3, -hz3 + 3 -- the centre 3 studs inward on both axes: straight away = into the walls
			b3.telegraphs[1] = { id = 904, boss = boss3, attack = boss3.attacks[1].def, at = b3:Time() + 0.3, shape = "Circle", x = ccx, z = ccz, r = 8 }
			b3:Command(1, "Dash")
			for _ = 1, 3 do
				stepAt(b3, -hx3, -hz3)
			end
			T.check(d2(f3.x, f3.z, ccx, ccz) > 8 + f3.radius, "dash/parry (d): in a corner a circle centred inside the floor is still left (along the wall)",
				fmt("%.2f from the centre", d2(f3.x, f3.z, ccx, ccz)))
		end

		-- (e): an engaged pet dashing moves along the sidestep (not toward its target), then walks back and swings again
		do
			local b, tm = world(BS)
			local f = tm.fighter
			put(f, 0, -10)
			local e = enemiesAt(b, { { 0, -4 } })[1]
			standFor(b, 20, 0, -10)
			T.check(engaged(b) == e.id, "dash/parry (e): (setup) engaged")
			local x0, z0 = f.x, f.z
			tm.dashReadyAt = 0
			b:Command(1, "Dash")
			local dash = find(pendingOf(b), "Dash")
			stepAt(b, 0, -10)
			stepAt(b, 0, -10)
			local mx, mz = f.x - x0, f.z - z0
			local ml = sqrt(mx * mx + mz * mz)
			local dot = (dash and ml > 0.01) and (mx / ml * dash.dir[1] + mz / ml * dash.dir[2]) or -1
			T.check(dash ~= nil and abs(dash.dir[1] - f.dashDX) <= 0.01 and abs(dash.dir[2] - f.dashDZ) <= 0.01, "dash/parry (e): the Dash event's dir is the sidestep vector (within 0.01)")
			T.check(ml > 1 and dot > 0.9, "dash/parry (e): during DashSeconds the engaged pet moves along the sidestep", fmt("moved %.2f, dot %.2f", ml, dot))
			local hits = standFor(b, 25, 0, -10, function(evs)
				return find(evs, "Hit", function(x)
					return x.from == f.id and x.to == e.id
				end) ~= nil
			end)
			T.check(find(hits, "Hit", function(x)
				return x.from == f.id and x.to == e.id
			end) ~= nil and engaged(b) == e.id, "dash/parry (e): ...then it walks back and swings again (still engaged)")
		end

		-- (f): Validate rejects bad Parry numbers
		do
			local function rejects(key, value)
				local old = F[key]
				F[key] = value
				local ok = BC.Validate()
				F[key] = old
				return ok == false
			end
			T.check(rejects("ParryWindow", 0.5) and rejects("ParryWindow", 0) and rejects("ParryMeter", 50) and rejects("ParryStagger", 2) and rejects("ParryBossGap", 0.1),
				"dash/parry (f): Validate rejects ParryWindow 0.5 (> DashIFrames) / 0, ParryMeter 50, ParryStagger 2, ParryBossGap < ParryStagger")
			T.check(BC.Validate() == true, "dash/parry (f): ...and passes with the shipped numbers")
		end
	end)

	------------------------------------------------------------------------------------------------
	-- w6_cheer_core
	------------------------------------------------------------------------------------------------
	S.w6_cheer_core = guarded("w6_cheer_core", function()
		local BC = loadModule("BattleCatalog")
		local BS = loadModule("BattleSim")
		if not T.check(BC and BS, "cheer core: BattleCatalog + BattleSim load") then
			return
		end
		local F = BC.Fighter
		T.check(F.CheerBoost == 0.05 and F.CheerSeconds == 5 and F.CheerCooldown == 20 and BS.Events.Cheer == "Cheer", "cheer core: Fighter.CheerBoost 0.05 / CheerSeconds 5 / CheerCooldown 20; Events.Cheer")

		-- a battle where my fighter stands next to a target that never fights back: -> battle, fighter, victim
		local function mk(mode)
			if mode == "Raid" then
				local b = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 9, Teams = { team(1, 1, { pet("storm_tabby", 12), pet("pebble_pup", 5), pet("honey_bunny", 5) }) } })
				local boss = b.boss
				boss.nextAttack = huge
				for _, entry in ipairs(boss.attacks) do
					entry.nextAt = huge
				end
				boss.wavesDone = { true, true, true, true, true, true }
				boss.maxHp, boss.hp = 1e8, 1e8
				local f = b.teams[1].fighter
				put(f, boss.x, boss.z - boss.radius - 1)
				b.teams[1].noEngage = true
				return b, f, boss
			end
			local b, tm = world(BS, "storm_tabby", 12, 9)
			local f = tm.fighter
			put(f, 0, -10)
			tm.noEngage = true
			local e = enemiesAt(b, { { 0, -7 } })[1]
			return b, f, e
		end

		-- both battles step together; -> the hp ratio (A / B) of the fighter's plain hits in those steps
		local function lockstep(A, fA, vA, B, fB, vB, n)
			local ratios = {}
			for _ = 1, n do
				local hA, hB = vA.hp, vB.hp
				local eA = stepAt(A, fA.x, fA.z)
				stepAt(B, fB.x, fB.z)
				local plain = find(eA, "Hit", function(x)
					return x.from == fA.id and x.to == vA.id and not x.special and not x.element and not x.burn and not x.miss
				end)
				if plain and hB - vB.hp > 0 then
					ratios[#ratios + 1] = { t = A:Time(), r = (hA - vA.hp) / (hB - vB.hp) }
				end
			end
			return ratios
		end
		local function allNear(list, want)
			if #list == 0 then
				return false
			end
			for _, x in ipairs(list) do
				if abs(x.r - want) > 1e-6 then
					return false
				end
			end
			return true
		end

		for _, mode in ipairs({ "Raid", "Dungeon" }) do
			local A, fA, vA = mk(mode)
			local B, fB, vB = mk(mode)
			fA.specialKind, fB.specialKind = nil, nil -- (plain hits only; the element / special keep their own paths)
			local t0 = A:Time()
			local ok, why = A:Command(1, "Cheer")
			local cheerEv = find(pendingOf(A), "Cheer")
			T.check(ok == true and cheerEv ~= nil and cheerEv.owner == 1 and cheerEv.unit == fA.id and abs(cheerEv.untilT - (t0 + 5)) < 0.06 and A:TeamOf(1).Cheering == true,
				"cheer core (" .. mode .. "): Cheer -> true, ONE Cheer { owner, unit, untilT = t + 5 }, TeamOf.Cheering", tostring(why))
			T.check(abs(A:TeamOf(1).Cooldowns.Cheer - 20) < 1e-6 and B:TeamOf(1).Cooldowns.Cheer == 0, "cheer core (" .. mode .. "): TeamOf.Cooldowns.Cheer = 20 (0 when never used)")
			local r1 = lockstep(A, fA, vA, B, fB, vB, 10)
			T.check(allNear(r1, 1.05), "cheer core (" .. mode .. "): the cheered fighter's plain hits deal exactly x1.05 of the same seed's uncheered hits",
				r1[1] and fmt("%d hits, first ratio %.6f", #r1, r1[1].r) or "no hit")
			local ok2, why2, left = A:Command(1, "Cheer")
			local r2 = lockstep(A, fA, vA, B, fB, vB, 25)
			local early = {}
			for _, x in ipairs(r2) do
				if x.t < t0 + 5 - 0.05 then
					early[#early + 1] = x
				end
			end
			T.check(ok2 == false and why2 == "Cooldown" and left and left > 18 and allNear(early, 1.05),
				"cheer core (" .. mode .. "): a second Cheer at +1 s -> false, Cooldown (the seconds left); the boost stays x1.05 (never x1.1025)", fmt("%s %s, %d hits", tostring(why2), tostring(left), #early))
			while A:Time() < t0 + 5.05 do
				lockstep(A, fA, vA, B, fB, vB, 1)
			end
			local r3 = lockstep(A, fA, vA, B, fB, vB, 20)
			T.check(allNear(r3, 1.0) and A:TeamOf(1).Cheering == false, "cheer core (" .. mode .. "): after CheerSeconds the ratio is 1.0 (Cheering false)", r3[1] and fmt("%.6f", r3[1].r) or "no hit")
			while A:Time() < t0 + 20.05 do
				lockstep(A, fA, vA, B, fB, vB, 1)
			end
			T.check(A:Command(1, "Cheer") == true, "cheer core (" .. mode .. "): at +20.05 s Cheer works again")
		end

		-- refusals: Ring / Duel (the podium cheer there is visual only), a Down fighter, an Npc team
		do
			local ring = BS.new({ Mode = "Ring", Seed = 2, Round = 1, Teams = { team(1, 1, { pet("storm_tabby", 12) }), BC.ChampionTeam(1, 2) } })
			local duel = BS.new({ Mode = "Duel", Seed = 2, Teams = { team(1, 1, { pet("storm_tabby", 12) }), team(2, 2, { pet("storm_tabby", 12) }) } })
			local okR, whyR = ring:Command(1, "Cheer")
			local okD, whyD = duel:Command(1, "Cheer")
			T.check(okR == false and whyR == "NoCheer" and okD == false and whyD == "NoCheer", "cheer core: Ring and Duel -> false, NoCheer", tostring(whyR) .. " / " .. tostring(whyD))
			local b = BS.new({ Mode = "Dungeon", Seed = 2, Teams = { team(1, 1, { pet("storm_tabby", 12) }) } })
			local infos = b:SpawnEnemies({ pet("biscuit_bear", 5) }, { Wave = 1, Anchor = { 0, 10 } })
			local okN, whyN = b:Command("wave:1", "Cheer")
			T.check(infos and okN == false and whyN ~= nil, "cheer core: an Npc (wave) team -> refused", tostring(whyN))
			b.teams[1].fighter.alive = false -- white-box: the last pet down
			local okX, whyX = b:Command(1, "Cheer")
			T.check(okX == false and whyX == "Down", "cheer core: the fighter Down -> false, Down", tostring(whyX))
		end

		-- Validate
		do
			local function rejects(key, value)
				local old = F[key]
				F[key] = value
				local ok = BC.Validate()
				F[key] = old
				return ok == false
			end
			T.check(rejects("CheerBoost", 0.2) and rejects("CheerSeconds", 20) and rejects("CheerBoost", 0) and BC.Validate() == true,
				"cheer core: Validate rejects CheerBoost 0.2 / 0 and CheerSeconds 20 (not below the cooldown); passes as shipped")
		end
	end)

	------------------------------------------------------------------------------------------------
	-- the booted half: helpers (the shape of smoke_p5_battleservice.lua)
	------------------------------------------------------------------------------------------------
	local advance = K.advance
	local ALLOWED_WARNINGS = { "[BattleService]", "[DataService]", "[TycoonService]", "[PetCareService]", "[EventService]", "[MeshLibrary]", "[DungeonService]" }
	local seq = 0
	local STRONG = { "cloudy_dragon", "ember_phoenix", "aurora_fox" }
	local MID = { "twilight_dragon", "moonlit_owl", "candy_unicorn" }

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

	local function arenaInfo()
		local ab = req("server/Services/ArenaBuilder")
		return ab and ab.GetInfo and ab.GetInfo() or nil
	end

	-- a player with a battle team (pets owned, team preset 1 = the first 3); `level` sets every pet's level
	local function newPlayer(prefix, pets, level)
		seq = seq + 1
		local p = Mock.AddPlayer(prefix .. seq, 969000 + seq)
		advance(1.0)
		local data = req("server/Services/DataService")
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

	local function toasted(p, needle, fromIndex)
		local n = 0
		for _, e in ipairs(K.remotesFor("Notify", p.UserId, fromIndex or 0)) do
			if tostring(e.args[1]):find(needle, 1, true) then
				n = n + 1
			end
		end
		return n
	end

	-- the BattleService state (white-box: St is an upvalue of IsInBattle)
	local function serviceState(bs)
		local f = bs and bs.IsInBattle
		if type(f) ~= "function" then
			return nil
		end
		for i = 1, 80 do
			local name, v = debug.getupvalue(f, i)
			if not name then
				break
			end
			if name == "St" and type(v) == "table" then
				return v
			end
		end
		return nil
	end

	local function battleRecord(bs, battleId)
		local st = serviceState(bs)
		return st and st.battles and battleId and st.battles[battleId] or nil
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

	local function cleanup(list)
		local bs = req("server/Services/BattleService")
		for _, p in ipairs(list) do
			if p.Parent and bs and bs.IsInBattle(p) then
				bs.Forfeit(p)
			end
		end
		advance(0.3)
		K.removePlayers(list)
		advance(5)
	end

	-- a dungeon encounter far out in the sky: -> battle id, the zone part, the place(p, x, z) helper
	local function encounter(bs, players, seed)
		local part = Instance.new("Part")
		part.Name = "NC_BattleZone"
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.Size = Vector3.new(60, 2, 60)
		part.CFrame = CFrame.new(5600 + 200 * (seed % 7), 640, -2700)
		part:SetAttribute("Mode", "Dungeon")
		part.Parent = workspace
		local function place(p, x, z)
			Mock.Teleport(p, CFrame.new(part.CFrame:PointToWorldSpace(Vector3.new(x, 3, z))))
		end
		local teams = {}
		for i, p in ipairs(players) do
			teams[i] = { Player = p }
			place(p, -6 + 4 * i, -10)
		end
		advance(0.05)
		local id, why = bs.OpenEncounter({ Mode = "Dungeon", Zone = part, Seed = seed, TimeLimit = 300, Label = "w6", Teams = teams,
			Extra = { Floor = 1, Room = 1, Wave = 1, Waves = 1, Name = "W6 Room" }, KeepInBattle = true })
		return id, part, place, why
	end

	------------------------------------------------------------------------------------------------
	-- w6_cheer_service (booted)
	------------------------------------------------------------------------------------------------
	S.w6_cheer_service = guarded("w6_cheer_service", function()
		if not K.needBoot() then
			return
		end
		local bs = req("server/Services/BattleService")
		if not T.check(bs and type(bs.OpenEncounter) == "function" and arenaInfo() ~= nil, "cheer svc: BattleService + the arena load") then
			return
		end
		local cmd = K.remoteFolder():FindFirstChild("BattleCommand")
		local a = newPlayer("CheerA", STRONG, 20)
		local c = newPlayer("CheerB", MID, 20)
		local mark = K.logSize()
		local id, part, place, why = encounter(bs, { a, c }, 6101)
		advance(0.3)
		local b = battleRecord(bs, id)
		local sim = b and b.Sim
		if not T.check(type(id) == "string" and sim ~= nil, "cheer svc: (setup) a dungeon encounter for a party of two", tostring(why)) then
			part:Destroy()
			cleanup({ a, c })
			return
		end
		local infos = bs.SpawnWave(id, { { PetId = "biscuit_bear", Level = 30 } }, { Wave = 1, Name = "W1" })
		local e = infos and infos[1] and sim.units[infos[1].id]
		if e then
			dummy(e, 0, 10)
		end
		advance(0.3)
		local start = battleMsgs(a, mark, "Start")[1]
		local sp = start and start.args[2]
		T.check(sp and sp.Team and sp.Team.Cooldowns and sp.Team.Cooldowns.Cheer == 0, "cheer svc: the Start payload carries Team.Cooldowns.Cheer = 0")
		-- the remote: one Cheer -> the sim boost and the Cheer event to both party members
		local m1 = K.logSize()
		Mock.FromClient(cmd, a, "Cheer")
		advance(0.3)
		local tmA = sim:TeamOf(a.UserId)
		local evA = eventsOf(a, m1, "Cheer")
		local evC = eventsOf(c, m1, "Cheer")
		T.check(tmA and tmA.Cheering == true and #evA == 1 and #evC == 1 and evA[1].owner == a.UserId, "cheer svc: BattleCommand(\"Cheer\") -> the sim boost (Cheering) and ONE Cheer event to both party members",
			fmt("Cheering %s, events %d / %d", tostring(tmA and tmA.Cheering), #evA, #evC))
		-- spam: 40 calls in 1 s from the other member -> exactly one accepted, one throttled Cooldown toast, <= 1 echo a step
		local m2 = K.logSize()
		for _ = 1, 40 do
			Mock.FromClient(cmd, c, "Cheer")
			advance(0.025)
		end
		advance(0.3)
		local accepted = 0
		for _, ev in ipairs(eventsOf(c, m2, "Cheer")) do
			if ev.owner == c.UserId then
				accepted = accepted + 1
			end
		end
		local worstEcho = 0
		for _, msg in ipairs(battleMsgs(c, m2, "Events")) do
			local n = 0
			for _, ev in ipairs(msg.args[2]) do
				if ev.type == "Order" and ev.order == "Cheer" and ev.rejected and ev.owner == c.UserId then
					n = n + 1
				end
			end
			worstEcho = max(worstEcho, n)
		end
		local nToast = toasted(c, "Not ready", m2)
		local tmC = sim:TeamOf(c.UserId)
		T.check(accepted == 1 and worstEcho <= 1 and nToast == 1 and tmC.Cheering == true and tmC.Cooldowns.Cheer > 18,
			"cheer svc: 40 Cheer calls in 1 s -> exactly ONE accepted, <= 1 rejected echo a step, ONE throttled \"Not ready\" toast",
			fmt("accepted %d, worst echo %d, toasts %d", accepted, worstEcho, nToast))
		T.check(sim.teamByOwner[c.UserId].cheerUntil - sim:Time() <= 5 + 1e-6,
			"cheer svc: ...and the boost never stacks past one window (5 s)")
		-- junk: an argument, a 200-char action, NaN -> refused, nothing breaks
		local errs0 = #Mock.Errors
		local okJ, whyJ = bs.Command(a, "Cheer", { 1, 2 })
		Mock.FromClient(cmd, a, "Cheer", { 1, 2 })
		Mock.FromClient(cmd, a, string.rep("C", 200))
		Mock.FromClient(cmd, a, "Cheer", 0 / 0)
		Mock.FromClient(cmd, a, "Cheer", "x")
		advance(0.3)
		T.check(okJ == false and whyJ == "BadArg" and #Mock.Errors == errs0, "cheer svc: junk (an argument, a 200-char action, NaN, a string) is refused without an error", tostring(whyJ))
		-- a player in no battle / a spectator
		local z = newPlayer("CheerSpec", STRONG, 5)
		place(z, 0, 0)
		advance(0.3)
		local okZ, whyZ = bs.Command(z, "Cheer")
		T.check(okZ == false and whyZ == "NoBattle", "cheer svc: a spectator / a player in no battle -> refused (NoBattle)", tostring(whyZ))
		bs.FinishEncounter(id, "Abandoned")
		advance(0.3)
		part:Destroy()
		cleanup({ a, c, z })

		-- a raid: Cheer works there too
		local startRaid = holdRaidSchedule(bs)
		if bs.GetRaidStatus() ~= nil then
			bs.EndRaid()
			advance(0.2)
		end
		local r = newPlayer("CheerRaid", STRONG, 20)
		toArena(r, 0, 6)
		local okR = startRaid("lava_golem")
		local okJR = okR and bs.JoinRaid(r)
		advance(0.5)
		local okC, whyC = bs.Command(r, "Cheer")
		T.check(okR and okJR and okC == true, "cheer svc: a raid: Cheer is accepted", tostring(whyC))
		bs.EndRaid()
		advance(0.3)
		releaseRaidSchedule(bs)
		cleanup({ r })

		-- a duel: refused NoCheer (the podium cheer there is visual only)
		local x = newPlayer("CheerDx", MID, 10)
		local y = newPlayer("CheerDy", MID, 10)
		toArena(x, 3, 0)
		toArena(y, -3, 0)
		local okD, idD = bs.StartDuel(x, y)
		advance(0.3)
		local okN, whyN = bs.Command(x, "Cheer")
		T.check(okD == true and okN == false and whyN == "NoCheer", "cheer svc: a duel -> refused NoCheer", tostring(idD) .. " / " .. tostring(whyN))
		cleanup({ x, y })
		K.flushErrors("w6_cheer_service")
		K.flushWarnings("w6_cheer_service", ALLOWED_WARNINGS)
	end)

	------------------------------------------------------------------------------------------------
	-- the podium (booted): helpers
	------------------------------------------------------------------------------------------------
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
		local Ty = req("server/Services/TycoonService")
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

	local function ringPortalPos()
		local info = arenaInfo()
		local portal = info and info.RingPortal
		if typeof(portal) == "Instance" then
			return portal:IsA("BasePart") and portal.Position or portal:GetPivot().Position
		elseif type(portal) == "table" and typeof(portal.Position) == "Vector3" then
			return portal.Position
		elseif typeof(portal) == "CFrame" then
			return portal.Position
		end
		local inst = workspace:FindFirstChild("Portal_Ring", true)
		if inst then
			return inst:IsA("BasePart") and inst.Position or inst:GetPivot().Position
		end
		return nil
	end

	local function rootOf(p)
		return Mock.GetRoot(p)
	end

	-- a Champion Ring run for a fresh level-1 climber: -> player, run record, battle record | nil
	local function ringRun(bs, prefix)
		local pos = ringPortalPos()
		if not pos then
			return nil
		end
		local p = newPlayer(prefix, { "pebble_pup" }, 1) -- (a weak climber: a round lasts long enough to look at)
		claimHome(p)
		Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 6)))
		advance(0.1)
		local ok, id = bs.StartRing(p, 1)
		advance(0.3)
		local st = serviceState(bs)
		local run = st and st.ringRuns and st.ringRuns[p]
		return p, run, ok and run and run.Battle or nil, id
	end

	-- the ring run's current round ends as a win at once (white-box: BattleSim Finish("Cleared") = side 1 wins)
	local function winRound(run)
		local b = run and run.Battle
		if b and b.Sim then
			b.Sim:Finish("Cleared")
		end
		advance(0.3)
	end

	local function padUnder(model, name, pos)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == name then
				local lp = d.CFrame:PointToObjectSpace(pos)
				if math.abs(lp.X) <= d.Size.X / 2 + 0.01 and math.abs(lp.Z) <= d.Size.Z / 2 + 0.01 then
					return d, lp.Y - d.Size.Y / 2
				end
			end
		end
		return nil
	end

	------------------------------------------------------------------------------------------------
	-- w6_podium_find (booted): the stands ARE the pads
	------------------------------------------------------------------------------------------------
	S.w6_podium_find = guarded("w6_podium_find", function()
		if not K.needBoot() then
			return
		end
		local bs = req("server/Services/BattleService")
		if not T.check(bs and arenaInfo() ~= nil and ringPortalPos() ~= nil, "podium find: BattleService, the arena and the Champion Ring portal") then
			return
		end
		local p, run, b, why = ringRun(bs, "PodRing")
		if T.check(run ~= nil and b ~= nil and typeof(run.Zone.Spawn) == "CFrame" and run.Zone.Pocket and run.Zone.Pocket.Model, "podium find: (setup) a Champion Ring run with its pocket",
			fmt("run %s, battle %s, %s, state %s, round %s, ok %s", tostring(run), tostring(b), tostring(why), tostring(run and run.State), tostring(run and run.Round), tostring(run and run.LastId))) then
			local spawn = run.Zone.Spawn
			local pad, above = padUnder(run.Zone.Pocket.Model, "SpawnPad", spawn.Position)
			local lpos = run.Zone.CFrame:PointToObjectSpace(spawn.Position)
			local x, z = lpos.X, lpos.Z
			T.check(pad ~= nil and above >= 0 and above <= 3.5 and pad.Size.X <= 7.01 and pad.Size.Z <= 7.01,
				"podium find: the Ring's stand (Zone.Spawn) is on the pocket's SpawnPad (top within 3.5 studs under it, inside its 7 x 7 footprint)",
				pad and fmt("%.2f above the pad top", above) or "no SpawnPad under the stand")
			T.check(math.abs(z) > run.Zone.Z / 2 or math.abs(x) > run.Zone.X / 2, "podium find: ...outside the 44-stud fighting floor", fmt("local %.1f, %.1f", x, z))
		end
		cleanup({ p })
		local a = newPlayer("PodDa", MID, 10)
		local c = newPlayer("PodDb", MID, 10)
		toArena(a, 3, 0)
		toArena(c, -3, 0)
		local okD, idD = bs.StartDuel(a, c)
		advance(0.3)
		local bd = okD and battleRecord(bs, idD)
		local ring = bd and arenaInfo().Rings[bd.RingIndex]
		local onPads = 0
		for _, pl in ipairs({ a, c }) do
			local root = rootOf(pl)
			for _, pad in ipairs(ring and ring.Pads or {}) do
				if pad.Name == "ChallengePad" and root then
					local lp = pad.CFrame:PointToObjectSpace(root.Position)
					if math.abs(lp.X) <= pad.Size.X / 2 + 0.5 and math.abs(lp.Z) <= pad.Size.Z / 2 + 0.5 and lp.Y >= 0 and lp.Y <= 3.6 then
						onPads = onPads + 1
						break
					end
				end
			end
		end
		T.check(okD and onPads == 2, "podium find: each duellist's stand (duelStand) is on a ChallengePad of that ring", fmt("%d of 2 on a pad", onPads))
		cleanup({ a, c })
		K.flushErrors("w6_podium_find")
		K.flushWarnings("w6_podium_find", ALLOWED_WARNINGS)
	end)

	------------------------------------------------------------------------------------------------
	-- w6_podium_lock (booted)
	------------------------------------------------------------------------------------------------
	S.w6_podium_lock = guarded("w6_podium_lock", function()
		if not K.needBoot() then
			return
		end
		local bs = req("server/Services/BattleService")
		local Config = req("shared/Config")
		if not T.check(bs and Config and Config.Attr.OnPodium == "OnPodium" and ringPortalPos() ~= nil, "podium lock: BattleService, Config.Attr.OnPodium, the ring portal") then
			return
		end
		local ATTR = Config.Attr.OnPodium
		local function locked(p)
			local root = rootOf(p)
			return root ~= nil and root.Anchored == true and p:GetAttribute(ATTR) == true
		end
		local function free(p)
			local root = rootOf(p)
			return (root == nil or root.Anchored == false) and p:GetAttribute(ATTR) == nil
		end
		-- the Ring: the round locks the climber on the SpawnPad
		local m0 = K.logSize()
		local p, run, b = ringRun(bs, "PodLock")
		if not T.check(run ~= nil and b ~= nil, "podium lock: (setup) a ring run") then
			cleanup({ p })
			return
		end
		local spawn = run.Zone.Spawn
		T.check(locked(p) and (rootOf(p).Position - spawn.Position).Magnitude < 0.5, "podium lock: a Ring round start: the root is Anchored on the SpawnPad, OnPodium = true")
		local okC, whyC = bs.Command(p, "Cheer")
		T.check(okC == false and whyC == "NoCheer", "podium lock: Cheer in the Ring -> NoCheer (the podium cheer is visual only)", tostring(whyC))
		-- a scripted move of the root 6 studs away is undone within one tick
		Mock.Teleport(p, spawn * CFrame.new(6, 0, 0))
		advance(0.05)
		T.check((rootOf(p).Position - spawn.Position).Magnitude <= 2 and locked(p), "podium lock: a root moved 6 studs off the pad is put back within one tick")
		-- the Move feed still runs: the champion untargetable, 12 s locked: no leash, the pet waits at the floor edge by the pad
		for _, u in ipairs(b.Sim.units) do
			if u.side == 2 then
				u.arriveUntil = math.huge
				u.nextAttack = math.huge
			end
		end
		advance(12)
		local f = b.Sim.teams[1].fighter
		local spos = run.Zone.CFrame:PointToObjectSpace(spawn.Position)
		local sx, sz = spos.X, spos.Z
		local hx, hz = run.Zone.X / 2 - f.radius, run.Zone.Z / 2 - f.radius
		local ex, ez = math.max(-hx, math.min(hx, sx)), math.max(-hz, math.min(hz, sz))
		T.check(bs.IsInBattle(p) and run.Battle == b and locked(p) and d2(f.x, f.z, ex, ez) < 2.5, "podium lock: 12 s locked: no leash, the pet FOLLOWs to the floor edge by the pad",
			fmt("pet %.1f from the edge point", d2(f.x, f.z, ex, ez)))
		for _, u in ipairs(b.Sim.units) do
			if u.side == 2 then
				u.arriveUntil = nil
			end
		end
		-- the round's End: free for the intermission; the next round re-locks at the pad
		winRound(run)
		T.check(free(p) and run.State == "Intermission", "podium lock: the round's End -> unanchored, OnPodium nil (the intermission is free)", tostring(run.State))
		local tWait = Mock.Clock.now
		while run.State ~= "Fighting" and Mock.Clock.now - tWait < 8 do
			advance(0.2)
		end
		advance(0.2)
		T.check(run.State == "Fighting" and locked(p) and (rootOf(p).Position - spawn.Position).Magnitude < 0.5, "podium lock: the next round re-locks the climber on the pad")
		local nToast = 0
		for _, e in ipairs(K.remotesFor("Notify", p.UserId, m0)) do
			if tostring(e.args[1]) == "You're the trainer: cheer your pet on from the podium!" then
				nToast = nToast + 1
			end
		end
		T.check(nToast == 1, "podium lock: ONE toast for the run: \"You're the trainer: cheer your pet on from the podium!\"", nToast .. " toasts")
		-- Review Focus 2: death mid-round -> the lock lets go; the new character is never anchored
		local oldRoot = rootOf(p)
		Mock.Kill(p)
		advance(0.1)
		T.check(oldRoot.Anchored == false and p:GetAttribute(ATTR) == nil, "podium lock: death mid-round: the dead root is unanchored, OnPodium nil")
		Mock.Respawn(p)
		advance(0.5)
		T.check(free(p) and rootOf(p) ~= oldRoot, "podium lock: ...and the fresh character is not anchored")
		cleanup({ p })

		-- a duel: both locked on their pads; a forfeit releases both
		local a = newPlayer("PodLa", MID, 10)
		local c = newPlayer("PodLb", MID, 10)
		toArena(a, 3, 0)
		toArena(c, -3, 0)
		local okD = bs.StartDuel(a, c)
		advance(0.3)
		T.check(okD and locked(a) and locked(c), "podium lock: a duel: both duellists are locked on their pads")
		bs.Forfeit(a)
		advance(0.5)
		T.check(free(a) and free(c), "podium lock: a forfeit releases both duellists")
		-- a disconnect clears the lock record
		toArena(a, 3, 0)
		toArena(c, -3, 0)
		advance(6)
		local okD2 = bs.StartDuel(a, c)
		advance(0.3)
		local Podium = req("server/Services/Podium")
		local wasLocked = Podium and Podium.IsLocked(a)
		K.removePlayers({ a })
		advance(1)
		T.check(okD2 and wasLocked and Podium and not Podium.IsLocked(a), "podium lock: a disconnect clears the lock record")
		advance(1)
		T.check(free(c), "podium lock: ...and the opponent is free once the duel ends")
		cleanup({ c })

		-- Shutdown releases everyone
		local q, qrun = ringRun(bs, "PodShut")
		local wasQ = qrun and locked(q)
		bs.Shutdown()
		advance(0.3)
		T.check(wasQ and free(q), "podium lock: BattleService.Shutdown() releases everyone")
		bs.SetClosing(false)
		cleanup({ q })

		-- a raid joiner and a dungeon member are never locked
		local startRaid = holdRaidSchedule(bs)
		if bs.GetRaidStatus() ~= nil then
			bs.EndRaid()
			advance(0.2)
		end
		local r = newPlayer("PodRaid", STRONG, 20)
		toArena(r, 0, 6)
		local okR = startRaid("lava_golem")
		local okJ = okR and bs.JoinRaid(r)
		advance(1)
		local raidFree = free(r)
		bs.EndRaid()
		advance(0.3)
		releaseRaidSchedule(bs)
		local dm = newPlayer("PodDgn", STRONG, 20)
		local idE, partE = encounter(bs, { dm }, 6203)
		advance(1)
		local dgnFree = free(dm)
		if idE then
			bs.FinishEncounter(idE, "Abandoned")
		end
		advance(0.3)
		if partE then
			partE:Destroy()
		end
		T.check(okJ and raidFree and idE ~= nil and dgnFree, "podium lock: a raid joiner and a dungeon member are never locked")
		cleanup({ r, dm })
		K.flushErrors("w6_podium_lock")
		K.flushWarnings("w6_podium_lock", ALLOWED_WARNINGS)
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- the client world
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Players = game:GetService("Players")
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

	function H.sounds()
		local n = 0
		for _, d in ipairs(game:GetDescendants()) do
			if d:IsA("Sound") then
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

	-- a BattleSim driven the way BattleService sends it (Start, Events + Snapshot each step); my BattleCommand calls are
	-- forwarded into the sim unless noForward. mode: "Dungeon" | "Raid" | "Duel" | "Ring"
	local Driver = {}
	Driver.__index = Driver

	function H.driver(mode)
		local Sim = H.moduleAt("shared", "BattleSim")
		local BCat = H.moduleAt("shared", "BattleCatalog")
		if not Sim or not BCat then
			return nil
		end
		mode = mode or "Dungeon"
		local id = "w6_" .. mode .. "_" .. tostring(math.random(100000, 999999))
		local me = { Owner = LocalPlayer.UserId, Side = 1, Pets = H.team(3, 0, 14) }
		local setup = { Mode = mode, Seed = 9, Id = id, Teams = { me } }
		if mode == "Dungeon" then
			setup.Zone, setup.TimeLimit = { X = 44, Z = 44 }, 300
		elseif mode == "Raid" then
			setup.Boss = "storm_titan"
		elseif mode == "Duel" then
			setup.Teams[2] = { Owner = 424242, Side = 2, Pets = H.team(3, 3, 10) }
		elseif mode == "Ring" then
			setup.Round = 1
			setup.Teams[2] = BCat.ChampionTeam(1, 1)
		end
		local sim = Sim.new(setup)
		if not sim then
			return nil
		end
		return setmetatable({ sim = sim, id = id, mode = mode, zoneCF = CFrame.new(0, 200, 0), logIndex = #Mock.RemoteLog, me = LocalPlayer.UserId,
			dungeon = (mode == "Dungeon") and { Floor = 2, Room = 1, Wave = 1, Waves = 3, Name = "Ember Hall", Element = "Flame" } or nil }, Driver)
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
			Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Cheer = team.Cooldowns.Cheer, Buff = {} } }
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

	function Driver:events(list)
		KC.toClient("BattleState", "Events", list, self.id)
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

	-- a fighting battle of `mode` with passive enemies (a dungeon gets a wave)
	function H.fighting(mode)
		local d = H.driver(mode)
		if not d then
			return nil
		end
		d:start()
		d:step(30)
		if d.mode == "Dungeon" then
			local infos = d:spawn(3)
			for _, info in ipairs(infos or {}) do
				local u = d.sim.units[info.id]
				u.nextAttack, u.hit, u.maxHp, u.hp, u.moveSpeed = huge, 0, 1e9, 1e9, 0
			end
		end
		for _, u in ipairs(d.sim.units) do
			if u.side == 2 then
				u.nextAttack, u.hit = huge, 0
				if u.kind == "Boss" then
					for _, entry in ipairs(u.attacks or {}) do
						entry.nextAt = huge
					end
				end
			end
		end
		d:run(1.6, 30)
		return d
	end

	function H.cleanup(BC, d)
		if d and BC.GetBattle() then
			KC.toClient("BattleState", "End", { BattleId = d.id, Mode = d.mode, Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }, d.id)
		end
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
		local r = H.find("Root.ResultCard.Body.OkButton")
		if r and r.Visible then
			Mock.Click(r)
		end
		Mock.Step(0.1)
	end

	-- a recording PlayEmote on my character's Animate (the default Animate script's emote hook) -> calls, restore()
	function H.fakeEmote(answer)
		local char = LocalPlayer.Character
		local calls = {}
		if not char then
			return calls, function() end
		end
		local animate = char:FindFirstChild("Animate")
		local made = false
		if not animate then
			animate = Instance.new("LocalScript")
			animate.Name = "Animate"
			animate.Parent = char
			made = true
		end
		local saved = animate:FindFirstChild("PlayEmote")
		if saved then
			saved.Name = "PlayEmote_w6saved"
		end
		local fn = Instance.new("BindableFunction")
		fn.Name = "PlayEmote"
		fn.OnInvoke = function(name)
			calls[#calls + 1] = { name = name, at = os.clock() }
			if type(answer) == "function" then
				return answer(#calls)
			end
			return true
		end
		fn.Parent = animate
		return calls, function()
			fn:Destroy()
			if saved then
				saved.Name = "PlayEmote"
			end
			if made then
				animate:Destroy()
			end
		end, fn
	end

	------------------------------------------------------------------------------------------------
	-- client_w6_podium_cheer
	------------------------------------------------------------------------------------------------
	S.client_w6_podium_cheer = guarded("client_w6_podium_cheer", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		local TC = H.moduleAt("client", "Controllers/TrainerCheer")
		if not T.check(BC ~= nil and TC ~= nil and LocalPlayer.Character ~= nil, "podium cheer: BattleController + TrainerCheer load, my character exists") then
			return
		end
		local err0 = #Mock.Errors
		local sounds0 = H.sounds()
		local calls, restore = H.fakeEmote()
		-- OnPodium = true: the cheer at once and again within 4.5 s
		LocalPlayer:SetAttribute("OnPodium", true)
		H.step(9, 1 / 30)
		local first = #calls
		H.step(135, 1 / 30)
		local second = #calls
		T.check(first >= 1 and calls[1].name == "cheer" and second >= 2, "podium cheer: OnPodium = true -> PlayEmote(\"cheer\") within 0.3 s and again within 4.5 s (the loop)",
			fmt("%d in 0.3 s, %d in 4.8 s", first, second))
		-- OnPodium nil: no more calls for 6 s
		LocalPlayer:SetAttribute("OnPodium", nil)
		H.step(3, 1 / 30)
		local stopped = #calls
		H.step(180, 1 / 30)
		T.check(#calls == stopped and not TC.IsLooping(), "podium cheer: OnPodium nil -> the loop stops (no call for 6 s)", fmt("%d more", #calls - stopped))
		-- my own Cheer event -> exactly one play; another owner's -> none
		local d = H.fighting("Dungeon")
		if T.check(d ~= nil and BC.GetBattle() ~= nil, "podium cheer: (setup) a fighting dungeon HUD") then
			local n0 = #calls
			local fid = d.sim:TeamOf(d.me).Fighter
			d:events({ { type = "Cheer", owner = d.me, unit = fid, untilT = d.sim:Time() + 5 } })
			H.step(30, 1 / 30)
			T.check(#calls - n0 == 1, "podium cheer: my own Cheer event -> exactly ONE cheer", fmt("%d plays", #calls - n0))
			local n1 = #calls
			d:events({ { type = "Cheer", owner = 515151, unit = 99, untilT = d.sim:Time() + 5 } })
			H.step(30, 1 / 30)
			T.check(#calls == n1, "podium cheer: another owner's Cheer event plays nothing here (their avatar replicates)")
			H.cleanup(BC, d)
		end
		-- not standing yet (PlayEmote answers false): a few retries, then it plays
		restore()
		local calls2, restore2 = H.fakeEmote(function(n)
			return n >= 3
		end)
		local okRetry = TC.Play(LocalPlayer.Character)
		H.step(45, 1 / 30)
		T.check(okRetry == true and #calls2 == 3, "podium cheer: while the pose is not standing it retries every 0.2 s (up to 1 s)", #calls2 .. " tries")
		restore2()
		-- no PlayEmote / no Animate: no error, false
		local model = Instance.new("Model")
		T.check(TC.Play(model) == false and TC.Play(nil) == false, "podium cheer: a rig without Animate.PlayEmote -> false, no error")
		model:Destroy()
		T.check(#Mock.Errors == err0 and H.sounds() == sounds0, "podium cheer: no script error and no Sound instance created")
		KC.flushErrors("client_w6_podium_cheer")
	end)

	------------------------------------------------------------------------------------------------
	-- client_w6_cheer_button / client_w6_cheer_mobile
	------------------------------------------------------------------------------------------------
	-- a GUI object's rect in gui-area px (an IgnoreGuiInset = true gui is shifted up by the top inset)
	local function rectOf(inst)
		local g = inst:FindFirstAncestorOfClass("ScreenGui")
		local dy = (g and g.IgnoreGuiInset) and -(Mock.TopInset or 0) or 0
		local p, s = inst.AbsolutePosition, inst.AbsoluteSize
		return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
	end

	local function overlaps(a, b)
		return a.x0 < b.x1 - 1 and b.x0 < a.x1 - 1 and a.y0 < b.y1 - 1 and b.y0 < a.y1 - 1
	end

	local function shownIn(obj)
		local cur = obj
		while cur and cur ~= game do
			if cur:IsA("LayerCollector") then
				if cur.Enabled == false then
					return false
				end
			elseif cur:IsA("GuiObject") and cur.Visible == false then
				return false
			end
			cur = cur.Parent
		end
		return cur ~= nil
	end

	local function rstr(r)
		return fmt("%.0f,%.0f-%.0f,%.0f", r.x0, r.y0, r.x1, r.y1)
	end

	-- what Cheer up! must keep clear of (gui-area px): the vitals card, the hotbar, every other gui's buttons, the battle
	-- HUD's other blocks + action buttons, and on touch screens Roblox's stick / jump button (Hud.TouchRects' numbers)
	local function cheerObstacles(touch)
		local out = {}
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		for _, g in ipairs(pg and pg:GetChildren() or {}) do
			if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "NimbusBattle" and g.Name ~= "NimbusBattleFx" then
				for _, o in ipairs(g:GetDescendants()) do
					if o:IsA("GuiButton") and shownIn(o) and o.AbsoluteSize.X > 4 and o.AbsoluteSize.X < 400 then
						out[#out + 1] = { g.Name .. "." .. o.Name, rectOf(o) }
					end
				end
				for _, name in ipairs({ "Vitals", "Hotbar" }) do
					local o = g:FindFirstChild(name, true)
					if o and o:IsA("GuiObject") and shownIn(o) and o.AbsoluteSize.X > 0 then
						out[#out + 1] = { g.Name .. "." .. name, rectOf(o) }
					end
				end
			end
		end
		local root = H.find("Root")
		for _, block in ipairs(root and root:GetChildren() or {}) do
			if block:IsA("GuiObject") and block.Name ~= "Cheer" and block.Name ~= "CheerGlow" and block.Name ~= "Commands"
				and shownIn(block) and block.AbsoluteSize.X > 0 then
				out[#out + 1] = { "Battle." .. block.Name, rectOf(block) }
			end
		end
		local cmd = H.find("Root.Commands")
		for _, b in ipairs(cmd and cmd:GetChildren() or {}) do
			if b:IsA("GuiObject") and shownIn(b) and b.AbsoluteSize.X > 0 then
				out[#out + 1] = { "Battle.Commands." .. b.Name, rectOf(b) }
			end
		end
		if touch then
			local vp = Mock.Viewport
			local areaY = vp.Y - (Mock.TopInset or 0)
			local small = min(vp.X, vp.Y) <= 500
			local j = small and 70 or 120
			local jb = small and 20 or j * 0.75
			out[#out + 1] = { "Roblox jump", { x0 = vp.X - j * 1.5 - 10, y0 = areaY - jb - j, x1 = vp.X - j * 0.5 - 10, y1 = areaY - jb } }
			local stickW = small and 110 or 190
			local stickH = small and ((vp.Y > vp.X) and 150 or 96) or 210
			out[#out + 1] = { "Roblox stick", { x0 = 0, y0 = areaY - stickH, x1 = stickW, y1 = areaY } }
		end
		return out
	end

	-- the placement rules at the current viewport -> problem | nil
	local function cheerProblem(touch)
		local HC = H.moduleAt("client", "Controllers/HudController")
		local b = H.find("Root.Cheer")
		if not b or not shownIn(b) then
			return "Cheer not shown"
		end
		local v = HC and HC.GetLayout().Vitals
		if not v then
			return "HudController.GetLayout().Vitals is nil"
		end
		local r = rectOf(b)
		local why = {}
		local vp = Mock.Viewport
		-- 8 px above the card, centred on it; where that spot is the middle of the screen (a landscape phone: the card sits
		-- high) it goes beside the card instead: its right edge 8 px left of the card, its top level with the card's top
		local cxV = v.X + v.W / 2
		local bw, bh = r.x1 - r.x0, r.y1 - r.y0
		local cyM = vp.Y / 2 - (Mock.TopInset or 0)
		local aboveInMiddle = cxV - bw / 2 < vp.X * 0.645 and cxV + bw / 2 > vp.X * 0.355 and v.Y - 8 - bh < cyM + vp.Y * 0.145 and v.Y - 8 > cyM - vp.Y * 0.145
		local above = abs((v.Y - r.y1) - 8) <= 2 and abs((r.x0 + r.x1) / 2 - cxV) <= 2
		local beside = abs((v.X - r.x1) - 8) <= 2 and abs(r.y0 - v.Y) <= 2
		if not (above or (aboveInMiddle and beside)) then
			why[#why + 1] = fmt("not 8 px above the vitals card %.0f,%.0f %.0fx%.0f, centred%s", v.X, v.Y, v.W, v.H,
				aboveInMiddle and " (that spot is the middle: then 8 px left of it, top level)" or "")
		end
		local areaY = vp.Y - (Mock.TopInset or 0)
		if r.x0 < 0 or r.y0 < 0 or r.x1 > vp.X or r.y1 > areaY then
			why[#why + 1] = "off the screen " .. rstr(r)
		end
		if touch and (r.x1 - r.x0 < 44 or r.y1 - r.y0 < 44) then
			why[#why + 1] = fmt("tap target %.0fx%.0f < 44x44", r.x1 - r.x0, r.y1 - r.y0)
		end
		-- the GetLayout rect is the real card
		local vr = { x0 = v.X, y0 = v.Y, x1 = v.X + v.W, y1 = v.Y + v.H }
		local hud = LocalPlayer.PlayerGui:FindFirstChild("NimbusHud")
		local card = hud and hud:FindFirstChild("Vitals", true)
		if card and abs(rectOf(card).y0 - vr.y0) > 2 then
			why[#why + 1] = fmt("GetLayout().Vitals.Y %.0f but the card's top is %.0f", vr.y0, rectOf(card).y0)
		end
		for _, o in ipairs(cheerObstacles(touch)) do
			if overlaps(r, o[2]) then
				why[#why + 1] = fmt("covers %s %s (Cheer %s)", o[1], rstr(o[2]), rstr(r))
			end
		end
		if overlaps(r, vr) then
			why[#why + 1] = "covers the vitals rect"
		end
		-- the middle of the screen stays free (HudController's CENTRE_TOL)
		local cx, cy = vp.X / 2, vp.Y / 2 - (Mock.TopInset or 0)
		if r.x0 < cx + vp.X * 0.145 and r.x1 > cx - vp.X * 0.145 and r.y0 < cy + vp.Y * 0.145 and r.y1 > cy - vp.Y * 0.145 then
			why[#why + 1] = "in the middle of the screen " .. rstr(r)
		end
		return #why > 0 and table.concat(why, "; ") or nil, r
	end

	local function cheerLayouts(label, sizes, touch)
		local BC = H.moduleAt("client", "Controllers/BattleController")
		for _, size in ipairs(sizes) do
			Mock.SetViewport(size[1], size[2])
			H.step(15, 1 / 30)
			local d = H.fighting("Dungeon")
			local tag = label .. " " .. size[1] .. "x" .. size[2]
			if T.check(d ~= nil and BC.GetBattle() ~= nil, tag .. ": (setup) a fighting dungeon HUD") then
				d:run(0.6, 30)
				local why, r = cheerProblem(touch)
				T.check(why == nil, tag .. ": Cheer up! sits 8 px above the vitals card, centred on it, on screen, covering nothing",
					tostring(why) .. (r and (" " .. rstr(r)) or ""))
				H.cleanup(BC, d)
			end
		end
	end

	S.client_w6_cheer_button = guarded("client_w6_cheer_button", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		local HC = H.moduleAt("client", "Controllers/HudController")
		if not T.check(BC ~= nil and HC ~= nil and type(BC.Cheer) == "function", "cheer button: BattleController (Cheer) + HudController load") then
			return
		end
		local err0 = #Mock.Errors
		local calls, restore = H.fakeEmote()
		Mock.SetViewport(1920, 1080)
		H.step(15, 1 / 30)
		local v = HC.GetLayout().Vitals
		T.check(type(v) == "table" and v.W > 0 and v.H > 0 and v.Y > 0, "cheer button: HudController.GetLayout().Vitals = the vitals card's rect",
			v and fmt("%s,%s %sx%s", tostring(v.X), tostring(v.Y), tostring(v.W), tostring(v.H)) or "nil")
		local d = H.fighting("Dungeon")
		if T.check(d ~= nil and BC.GetBattle() ~= nil, "cheer button: (setup) a fighting dungeon HUD") then
			local b = H.find("Root.Cheer")
			T.check(b ~= nil and shownIn(b) and b.Text == "Cheer up!" and b:IsA("TextButton"), "cheer button: a dungeon fight shows the TextButton \"Cheer up!\"",
				b and tostring(b.Text) or "missing")
			local why, r = cheerProblem(false)
			T.check(why == nil, "cheer button 1920x1080: 8 px above the vitals card, centred on it, on screen, covering nothing", tostring(why) .. (r and (" " .. rstr(r)) or ""))
			-- a click -> exactly one BattleCommand("Cheer"); the server's Cheer event -> the glow + the sweep
			local mark = #Mock.RemoteLog
			local n0 = #calls
			local soundsAt = H.sounds()
			Mock.Click(b)
			d:run(0.5, 30)
			local soundsAfter = H.sounds()
			local B1 = BC.GetBattle()
			T.check(H.count(mark, "Cheer") == 1, "cheer button: a click sends exactly ONE BattleCommand(\"Cheer\")", H.count(mark, "Cheer") .. " sent")
			local sweep = b and b:FindFirstChild("Sweep")
			local glowF = H.find("Root.CheerGlow")
			T.check(B1.Cheering == true and b:GetAttribute("Cheering") == true and glowF ~= nil and shownIn(glowF) and glowF.BackgroundTransparency < 0.9,
				"cheer button: the server's Cheer event starts the gold glow", fmt("Cheering %s, glow %.2f", tostring(B1.Cheering), glowF and glowF.BackgroundTransparency or -1))
			T.check(sweep ~= nil and shownIn(sweep) and abs(sweep.Size.X.Scale - B1.Cooldowns.Cheer / 20) < 0.06 and B1.Cooldowns.Cheer > 18.5,
				"cheer button: ...and the cooldown sweep over 20 s", fmt("sweep %.2f, cooldown %.1f s", sweep and sweep.Size.X.Scale or -1, B1.Cooldowns.Cheer or -1))
			T.check(#calls - n0 == 1, "cheer button: ...and my avatar cheers once (TrainerCheer)", (#calls - n0) .. " plays")
			T.check(soundsAfter == soundsAt, "cheer button: the press and the Cheer event create no Sound instance (the sound wave owns that)", soundsAt .. " -> " .. soundsAfter)
			-- a second click during the cooldown: nothing sent, the button shakes
			local shakes = b:GetAttribute("Shakes") or 0
			local mark2 = #Mock.RemoteLog
			Mock.Click(b)
			d:run(0.3, 30)
			T.check(H.count(mark2, "Cheer") == 0 and (b:GetAttribute("Shakes") or 0) == shakes + 1, "cheer button: a click during the cooldown sends nothing and shakes the button",
				fmt("%d sent, shakes %d -> %d", H.count(mark2, "Cheer"), shakes, b:GetAttribute("Shakes") or 0))
			-- the glow ends after 5 s, the sweep after 20 s
			d:run(4.6, 10)
			local B2 = BC.GetBattle()
			T.check(B2.Cheering == false and b:GetAttribute("Cheering") == false and glowF.BackgroundTransparency > 0.98 and shownIn(sweep),
				"cheer button: the glow is gone after 5 s, the sweep still runs", fmt("Cheering %s, glow %.2f", tostring(B2.Cheering), glowF.BackgroundTransparency))
			d:run(14.4, 10)
			T.check(shownIn(sweep) and BC.GetBattle().Cheering == false, "cheer button: 19.8 s after the press the sweep still shows")
			d:run(0.8, 10)
			T.check(not shownIn(sweep) and (BC.GetBattle().Cooldowns.Cheer or 1) == 0, "cheer button: after 20 s the sweep is gone (ready again)",
				fmt("cooldown %.2f", BC.GetBattle().Cooldowns.Cheer or -1))
			local mark3 = #Mock.RemoteLog
			Mock.Click(b)
			d:run(0.3, 30)
			T.check(H.count(mark3, "Cheer") == 1 and BC.GetBattle().Cheering == true, "cheer button: ready again -> the next click is sent and cheers")
			-- BattleController.Cheer() is the same command (refused locally during the cooldown)
			local mark4 = #Mock.RemoteLog
			T.check(BC.Cheer() == false and H.count(mark4, "Cheer") == 0, "cheer button: BattleController.Cheer() during the cooldown -> false, nothing sent")
			-- End -> gone
			H.cleanup(BC, d)
			T.check(not shownIn(b) and (H.find("Root.Cheer") == nil or not shownIn(H.find("Root.Cheer"))), "cheer button: the battle's End takes the button away",
				fmt("visible %s, parent %s, battle %s, gui %s", tostring(b.Visible), tostring(b.Parent and b.Parent.Name), tostring(BC.GetBattle() ~= nil),
					tostring(b:FindFirstAncestorOfClass("ScreenGui") and b:FindFirstAncestorOfClass("ScreenGui").Enabled)))
		end
		-- a raid shows it too; the Ring and a duel never
		local dr = H.fighting("Raid")
		if T.check(dr ~= nil and BC.GetBattle() ~= nil, "cheer button: (setup) a raid fight") then
			local b = H.find("Root.Cheer")
			T.check(b ~= nil and shownIn(b), "cheer button: a raid fight shows it")
			H.cleanup(BC, dr)
		end
		for _, mode in ipairs({ "Ring", "Duel" }) do
			local dm = H.fighting(mode)
			if T.check(dm ~= nil and BC.GetBattle() ~= nil, "cheer button: (setup) a " .. mode .. " fight") then
				local b = H.find("Root.Cheer")
				local mark = #Mock.RemoteLog
				T.check(not (b and shownIn(b)) and BC.Cheer() == false and H.count(mark, "Cheer") == 0,
					"cheer button: a " .. mode .. " fight has no Cheer up! (the podium cheers there) and BattleController.Cheer() sends nothing")
				H.cleanup(BC, dm)
			end
		end
		restore()
		cheerLayouts("cheer button", { { 1366, 768 } }, false)
		Mock.SetViewport(1920, 1080)
		H.step(15, 1 / 30)
		T.check(#Mock.Errors == err0, "cheer button: no script error", fmt("%d errors (%s)", #Mock.Errors - err0, tostring(Mock.Errors[#Mock.Errors])))
		KC.flushErrors("client_w6_cheer_button")
	end)

	S.client_w6_cheer_mobile = guarded("client_w6_cheer_mobile", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		if not T.check(BC ~= nil, "cheer phone: BattleController loads") then
			return
		end
		local err0 = #Mock.Errors
		cheerLayouts("cheer phone", { { 844, 390 }, { 390, 844 }, { 749, 388 } }, true)
		Mock.SetViewport(390, 844)
		H.step(15, 1 / 30)
		T.check(#Mock.Errors == err0, "cheer phone: no script error")
		KC.flushErrors("client_w6_cheer_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
