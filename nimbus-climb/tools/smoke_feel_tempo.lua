-- smoke_feel_tempo.lua: the battle feel, Task 3 "Weighty specials, the real server cast"
-- (docs/superpowers/specs/2026-11-10-battle-feel-design.md decisions 5-6; plan docs/superpowers/plans/2026-11-10-battle-feel.md
-- Task 3). Loaded by tools/smoke.py in BOTH worlds (ARGS.context picks the half).
-- Server world, pure (a real BattleSim, white-box on battle.units / battle.teams / battle.delayed):
--   feel_cast_queue        a special press is a real cast: a Cast event { at = t0 + SpecialCast[kind] } and no Special / Hit
--                          yet, the caster Casting with its meter full until `at`, then the Special (+ at = the start) and its
--                          effects for every kind (hits, the Storm zone, the Freeze stun, the heal / shield / buff); the caster is
--                          not blocked past `at`; SpecialCast = nil = today's instant special + CastSeconds
--   feel_cast_dodge        an NPC's Blast at my fighter: a dash just before `at` = a miss (special = Blast, no damage); walking
--                          out of the circle before `at` = no hit at all (the aim was fixed at the start)
--   feel_cast_break        a stun mid-cast: the entry gone, a CastBreak, the meter still full, nothing lands; a KO mid-cast: the
--                          entry dropped, no CastBreak, no hit; a Rally caster KO'd mid-cast: no buff
--   feel_cast_wire         Events.Cast / CastBreak; every Cast / Special / CastBreak field a number or a string, `at` in 0.1 steps;
--                          Validate holds, SpecialCast.Blast = 5 fails it
--   feel_cast_determinism  two Duels with specials on, seed 23, 40 s: the same event stream
-- Client world:
--   client_feel_tempo_beats    AttackFxCatalog's Weighty beats (charge x1.4 capped 1.1, travel at 0.7 speed capped 0.7, impact
--                              0.25, afterglow x1.5); Weighty = false: today's; basics unchanged at both settings
--   client_feel_tempo_hold     the fit keeps a special's travel; a taken-over charge with a LateMax gets the cut travel back
--                              (ImpactLate = min(0.30, the cut)); the caster's Cast and the victim's Hurt freeze 0.08 s at the impact
--   client_feel_tempo_cast     BattleController on a real BattleSim: an enemy's Cast starts its charge for me, its Special takes it
--                              over (late <= 0.3); my press waits for its cast (PRESS_WAIT extended); a CastBreak shatters it; a
--                              Cast with no Special fades after its end + CAST_WAIT; old events (no Cast, no at): today's LATE_MAX
--   client_feel_tempo_callout  the Special's name callout lives 1.6 s
--   client_feel_tempo_low      Graphics Low: the same beats, no afterglow, the freeze kept
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, min, floor, huge = math.abs, math.max, math.min, math.floor, math.huge
local fmt = string.format

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
end

local function findEvent(events, kind, pred)
	for _, ev in ipairs(events or {}) do
		if ev.type == kind and (pred == nil or pred(ev)) then
			return ev
		end
	end
	return nil
end

local function countEvents(events, kind, pred)
	local n = 0
	for _, ev in ipairs(events or {}) do
		if ev.type == kind and (pred == nil or pred(ev)) then
			n = n + 1
		end
	end
	return n
end

local function has(list, id)
	for _, v in ipairs(list or {}) do
		if v == id then
			return true
		end
	end
	return false
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
		local BC, BS, PC = req("BattleCatalog"), req("BattleSim"), req("PetCatalog")
		if not T.check(BC ~= nil and BS ~= nil and PC ~= nil and type(BC.Damage) == "table", tag .. ": BattleCatalog + BattleSim + PetCatalog load") then
			return nil
		end
		return BC, BS, PC
	end

	local function cloneDef(PC, petId, changes)
		local def = {}
		for k, v in pairs(PC.Get(petId)) do
			def[k] = v
		end
		def.Id = petId .. "_feel"
		for k, v in pairs(changes or {}) do
			def[k] = v
		end
		return def
	end

	local function withSpecial(PC, petId, kind)
		return cloneDef(PC, petId, { Special = { Id = "t_" .. kind, Name = "Test " .. kind, Kind = kind, Power = 40, Color = PC.Get(petId).Special.Color } })
	end

	-- a Duel on a wide floor (smoke_afx_reach's field): my fighter `entry` at the origin, one standing bear per spot
	local function field(BS, entry, spots, seed)
		local foes = {}
		for i = 1, #spots do
			foes[i] = { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = i }
		end
		entry.Slot = 1
		local b = BS.new({ Mode = "Duel", Seed = seed or 7, Zone = { X = 160, Z = 160 }, TimeLimit = 300,
			Teams = { { Owner = 1, Side = 1, Pets = { entry } }, { Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = foes } } })
		if not b then
			return nil
		end
		local tm = b.teams[1]
		local f = tm.fighter
		f.x, f.z, f.px, f.pz = 0, 0, 0, 0
		tm.wantX, tm.wantZ = 0, 0
		tm.noEngage = true
		f.maxHp, f.hp = 1e7, 1e7
		local on = {}
		for _, u in ipairs(b.units) do
			if u.side == 2 then
				on[#on + 1] = u
				local p = spots[#on]
				u.x, u.z, u.px, u.pz, u.moveSpeed = p[1], p[2], p[1], p[2], 0
				u.maxHp, u.hp = 1e7, 1e7
				u.nextAttack = huge
			end
		end
		return b, f, on, tm
	end

	local LEG = "ember_phoenix" -- a Legendary
	local function fighter(PC, kind, evo)
		return { Def = withSpecial(PC, LEG, kind), Key = LEG, Level = 50, Evo = evo or 0 }
	end

	-- my fighter presses its Special at foes[1]; -> the events of the press's step, t0 (the time of the press), ok
	local function press(b, f, foes)
		f.meter = 100
		if foes and foes[1] then
			b:Command(1, "Target", foes[1].id)
		end
		local t0 = b:Time()
		local ok, why = b:Command(1, "Special")
		local evs = b:Step(0.05)
		return evs, t0, ok, why
	end

	-- steps 0.05 s at a time until `untilT`, the events in one list (each tagged with its step's time)
	local function stepTo(b, untilT, each)
		local all = {}
		local guard = 0
		while b:Time() < untilT - 1e-9 and guard < 400 do
			guard = guard + 1
			for _, ev in ipairs(b:Step(0.05)) do
				ev._t = b:Time()
				all[#all + 1] = ev
			end
			if each then
				each()
			end
		end
		return all
	end

	S.feel_cast_queue = guarded("feel_cast_queue", function()
		local BC, BS, PC = load("feel cast queue")
		if not BC then
			return
		end
		local SC = BC.Damage.SpecialCast
		if not T.check(type(SC) == "table" and near(SC.Blast, 0.9) and near(SC.Beam, 0.8) and near(SC.Storm, 0.95) and near(SC.Freeze, 0.7) and near(SC.Pounce, 0.6)
			and near(SC.Heal, 0.55) and near(SC.Shield, 0.5) and near(SC.Rally, 0.55) and near(SC.Haste, 0.5),
			"feel cast: BattleCatalog.Damage.SpecialCast = the spec's seconds per kind (Config.Battle.Feel.Special.Cast, RealCast on)") then
			return
		end
		T.check(BS.Events.Cast == "Cast" and BS.Events.CastBreak == "CastBreak", "feel cast: BattleSim.Events has Cast and CastBreak")
		-- Blast in full
		local b, f, foes = field(BS, fighter(PC, "Blast"), { { 20, 0 }, { 20, 3 }, { -40, 40 } })
		local evs, t0, ok = press(b, f, foes)
		local cast = findEvent(evs, "Cast")
		T.check(ok and cast ~= nil and cast.unit == f.id and cast.kind == "Blast" and near(cast.at, t0 + 0.9, 0.051) and cast.target == foes[1].id and near(cast.tx, 20, 0.051) and near(cast.tz, 0, 0.051),
			"feel cast queue: the press sends Cast { kind, at = t0 + 0.9, target, tx / tz = its spot }",
			cast and fmt("at %s (t0 %.2f), target %s, tx %s tz %s", tostring(cast.at), t0, tostring(cast.target), tostring(cast.tx), tostring(cast.tz)) or "no Cast")
		T.check(findEvent(evs, "Special") == nil and findEvent(evs, "Hit") == nil, "feel cast queue: ... and no Special / Hit in that step")
		local casting, full = true, true
		local before = stepTo(b, t0 + 0.85, function()
			casting = casting and f.state == BS.States.Casting
			full = full and f.meter >= 100 - 1e-6
		end)
		T.check(casting and full and findEvent(before, "Special") == nil and findEvent(before, "Hit") == nil,
			"feel cast queue: the caster is Casting with its meter full until at, nothing lands before it")
		local meterAtFire = nil
		local after = stepTo(b, t0 + 0.95, function()
			if meterAtFire == nil and f.meter < 50 then
				meterAtFire = f.meter
			end
		end)
		local sp = findEvent(after, "Special")
		local hits = countEvents(after, "Hit", function(ev)
			return ev.from == f.id and ev.special == "Blast" and not ev.miss
		end)
		T.check(sp ~= nil and sp.at ~= nil and near(sp.at, floor(t0 * 10 + 0.5) / 10, 1e-9) and has(sp.targets, foes[1].id) and has(sp.targets, foes[2].id) and not has(sp.targets, foes[3].id),
			"feel cast queue: at `at` the Special lands (at = r1(the start)) on the bears inside the area",
			sp and fmt("at %s, %d targets", tostring(sp.at), #(sp.targets or {})) or "no Special")
		T.check(hits == 2 and meterAtFire ~= nil and meterAtFire < 10 and near(f.castUntil, t0 + 0.9, 0.051), "feel cast queue: one Hit per target (special = Blast), the meter spent, castUntil = at (no extra 0.5 s block)",
			fmt("%d hits, meter at the fire %s, castUntil - t0 %.2f", hits, tostring(meterAtFire), f.castUntil - t0))

		-- every kind: nothing before its own cast time, its effect at it
		local function kindCase(kind, secs, check)
			local bb, ff, fs = field(BS, fighter(PC, kind), { { 12, 0 } })
			ff.hp = ff.maxHp * 0.5
			local e0, s0 = press(bb, ff, fs)
			local c = findEvent(e0, "Cast")
			local pre = stepTo(bb, s0 + secs - 0.06)
			local early = findEvent(pre, "Special") or findEvent(pre, "Zone") or findEvent(pre, "Buff")
			local snap = { hp = ff.hp, shield = ff.shield, stun = fs[1].stunUntil, fx = fs[1].x }
			local post = stepTo(bb, s0 + secs + 0.06)
			local spe = findEvent(post, "Special")
			T.check(c ~= nil and near(c.at, s0 + secs, 0.051) and early == nil and spe ~= nil and spe.at ~= nil,
				fmt("feel cast queue: %s casts %.2f s (Cast at %s), nothing before, its Special at the end", kind, secs, tostring(c and c.at)))
			if spe then
				check(bb, ff, fs, post, snap, spe)
			end
		end
		kindCase("Beam", 0.8, function(bb, ff, fs, post)
			T.check(findEvent(post, "Hit", function(ev) return ev.special == "Beam" and ev.to == fs[1].id end) ~= nil, "feel cast queue: Beam's hit lands at at")
		end)
		kindCase("Storm", 0.95, function(bb, ff, fs, post, snap, spe)
			local z = findEvent(post, "Zone")
			local zone = bb.zones[#bb.zones]
			T.check(z ~= nil and zone ~= nil and near(zone.untilT - (z._t or 0), 4, 0.06), "feel cast queue: Storm's zone starts at at (and lasts its 4 s from then)")
		end)
		kindCase("Freeze", 0.7, function(bb, ff, fs, post, snap)
			T.check(snap.stun <= bb:Time() - 0.2 and fs[1].stunUntil > bb:Time(), "feel cast queue: Freeze's stun from at (none before)")
		end)
		kindCase("Pounce", 0.6, function(bb, ff, fs, post)
			T.check(findEvent(post, "Hit", function(ev) return ev.special == "Pounce" and ev.to == fs[1].id end) ~= nil, "feel cast queue: Pounce's strike lands at at")
		end)
		kindCase("Heal", 0.55, function(bb, ff, fs, post, snap, spe)
			T.check(ff.hp > snap.hp and type(spe.heals) == "table" and #spe.heals >= 1, "feel cast queue: Heal heals at at (the allies alive then)")
		end)
		kindCase("Shield", 0.5, function(bb, ff, fs, post, snap)
			T.check((snap.shield or 0) <= 0 and ff.shield > 0, "feel cast queue: Shield's shield lands at at")
		end)
		kindCase("Rally", 0.55, function(bb, ff, fs, post, snap, spe)
			T.check(spe["until"] ~= nil, "feel cast queue: Rally's buff starts at at (the Special carries its until)")
		end)
		kindCase("Haste", 0.5, function(bb, ff, fs, post, snap, spe)
			T.check(spe["until"] ~= nil, "feel cast queue: Haste's buff starts at at")
		end)

		-- the off switch: SpecialCast = nil = today's instant special
		local keep = BC.Damage.SpecialCast
		BC.Damage.SpecialCast = nil
		local okOff, errOff = pcall(function()
			local b2, f2, foes2 = field(BS, fighter(PC, "Blast"), { { 20, 0 } })
			local e2, s2 = press(b2, f2, foes2)
			local sp2 = findEvent(e2, "Special")
			T.check(sp2 ~= nil and sp2.at == nil and findEvent(e2, "Cast") == nil and findEvent(e2, "Hit", function(ev) return ev.special == "Blast" end) ~= nil
				and near(f2.castUntil, s2 + 0.5, 1e-6),
				"feel cast queue: SpecialCast = nil: today's path (the Special and its Hits in the press's own step, castUntil = t0 + 0.5, no Cast, no at)")
		end)
		BC.Damage.SpecialCast = keep
		T.check(okOff, "feel cast queue: the off switch runs", tostring(errOff))
	end)

	-- an NPC with a Blast at my standing fighter; -> b, f, npc
	local function npcBlast(BS, PC, BC)
		local b = BS.new({ Mode = "Duel", Seed = 9, Zone = { X = 160, Z = 160 }, TimeLimit = 300,
			Teams = { { Owner = 1, Side = 1, Pets = { { Key = "biscuit_bear", Level = 30, Slot = 1 } } },
				{ Owner = "npc", Side = 2, Npc = true, Pets = { { Def = withSpecial(PC, "biscuit_bear", "Blast"), Key = "biscuit_bear", Level = 30, Slot = 1 } } } } })
		if not b then
			return nil
		end
		local tm = b.teams[1]
		local f = tm.fighter
		f.x, f.z, f.px, f.pz = 0, 0, 0, 0
		tm.wantX, tm.wantZ = 0, 0
		tm.noEngage = true
		f.maxHp, f.hp = 1e7, 1e7
		f.nextAttack = huge
		local npc = nil
		for _, u in ipairs(b.units) do
			if u.side == 2 then
				npc = u
				u.x, u.z, u.px, u.pz, u.moveSpeed = 0, 12, 0, 12, 0
				u.maxHp, u.hp = 1e7, 1e7
				u.nextAttack = huge
				u.meter = 100
			end
		end
		return b, f, npc, tm
	end

	local function withDelay(BC, fn)
		local keep = BC.Damage.NpcSpecialDelay
		BC.Damage.NpcSpecialDelay = { 0, 0 }
		local ok, err = pcall(fn)
		BC.Damage.NpcSpecialDelay = keep
		if not ok then
			error(err, 0)
		end
	end

	-- steps until the NPC's Cast event; -> it, the events so far
	local function untilCast(b, npc, f)
		for _ = 1, 60 do
			f.meter = 0
			npc.meter = 100
			local evs = b:Step(0.05)
			local c = findEvent(evs, "Cast", function(ev) return ev.unit == npc.id end)
			if c then
				return c
			end
		end
		return nil
	end

	S.feel_cast_dodge = guarded("feel_cast_dodge", function()
		local BC, BS, PC = load("feel cast dodge")
		if not BC then
			return
		end
		withDelay(BC, function()
			-- a dash 0.1 s before `at`: its i-frames cover the fire
			local b, f, npc = npcBlast(BS, PC, BC)
			local c = untilCast(b, npc, f)
			if not T.check(c ~= nil and c.target == f.id, "feel cast dodge: the NPC casts its Blast at my fighter (a Cast event)") then
				return
			end
			stepTo(b, c.at - 0.1)
			local hp0 = f.hp
			local okDash = b:Command(1, "Dash")
			local evs = stepTo(b, c.at + 0.15)
			local miss = findEvent(evs, "Hit", function(ev) return ev.to == f.id and ev.special == "Blast" end)
			T.check(okDash and miss ~= nil and miss.miss == true and miss.dmg == 0 and f.hp >= hp0 - 1e-6,
				"feel cast dodge: my dash 0.1 s before at: the Blast is a miss (special = Blast, no damage)",
				miss and fmt("miss %s, dmg %s", tostring(miss.miss), tostring(miss.dmg)) or "no Hit")
			-- out of the circle before `at`: no hit at all (the aim was fixed at the cast's start)
			local b2, f2, npc2 = npcBlast(BS, PC, BC)
			local c2 = untilCast(b2, npc2, f2)
			if not T.check(c2 ~= nil, "feel cast dodge: (2) the NPC casts again") then
				return
			end
			stepTo(b2, c2.at - 0.3)
			f2.x, f2.px = 18, 18
			b2.teams[1].wantX = 18
			local evs2 = stepTo(b2, c2.at + 0.15)
			T.check(findEvent(evs2, "Special", function(ev) return ev.unit == npc2.id end) ~= nil and findEvent(evs2, "Hit", function(ev) return ev.to == f2.id and ev.special == "Blast" end) == nil,
				"feel cast dodge: my fighter out of the circle before at: the Blast lands where it was aimed, no hit on me")
		end)
	end)

	S.feel_cast_break = guarded("feel_cast_break", function()
		local BC, BS, PC = load("feel cast break")
		if not BC then
			return
		end
		-- a stun 0.3 s into the 0.9 s cast
		local b, f, foes = field(BS, fighter(PC, "Blast"), { { 20, 0 } })
		local _, t0 = press(b, f, foes)
		stepTo(b, t0 + 0.3)
		f.stunUntil = b:Time() + 1.5
		f.state = BS.States.Stunned
		local evs = stepTo(b, t0 + 2)
		local br = findEvent(evs, "CastBreak")
		T.check(#b.delayed == 0 and br ~= nil and br.unit == f.id and br.kind == "Blast", "feel cast break: a stun mid-cast: the entry is gone, a CastBreak { unit, kind }",
			fmt("%d entries, break %s", #b.delayed, tostring(br ~= nil)))
		T.check(f.meter >= 100 - 1e-6 and findEvent(evs, "Special") == nil and findEvent(evs, "Hit", function(ev) return ev.from == f.id and ev.special ~= nil end) == nil,
			"feel cast break: ... the meter still full, no Special / Hit later", fmt("meter %.1f", f.meter))
		-- a KO mid-cast: dropped, no CastBreak, no hit
		local b2, f2, foes2 = field(BS, fighter(PC, "Blast"), { { 20, 0 } })
		local _, s2 = press(b2, f2, foes2)
		stepTo(b2, s2 + 0.3)
		f2.alive = false
		local evs2 = stepTo(b2, s2 + 1.5)
		T.check(#b2.delayed == 0 and findEvent(evs2, "CastBreak") == nil and findEvent(evs2, "Special") == nil and findEvent(evs2, "Hit", function(ev) return ev.from == f2.id and ev.special ~= nil end) == nil,
			"feel cast break: a caster KO'd mid-cast: its entry dropped, no CastBreak, no Special / Hit")
		-- a Rally caster KO'd mid-cast: no buff
		local b3, f3 = field(BS, fighter(PC, "Rally"), { { 20, 0 } })
		local _, s3 = press(b3, f3, nil)
		stepTo(b3, s3 + 0.2)
		f3.alive = false
		local evs3 = stepTo(b3, s3 + 1.5)
		T.check(findEvent(evs3, "Buff") == nil and findEvent(evs3, "Special") == nil and (f3.dmgBuffUntil or 0) <= b3:Time(), "feel cast break: a Rally caster KO'd mid-cast: no buff")
	end)

	S.feel_cast_wire = guarded("feel_cast_wire", function()
		local BC, BS, PC = load("feel cast wire")
		if not BC then
			return
		end
		T.check(BS.Events.Cast == "Cast" and BS.Events.CastBreak == "CastBreak", "feel cast wire: BattleSim.Events.Cast / CastBreak")
		T.check(select(1, BC.Validate()) == true, "feel cast wire: BattleCatalog.Validate passes")
		local keep = BC.Damage.SpecialCast.Blast
		BC.Damage.SpecialCast.Blast = 5
		local bad = BC.Validate()
		BC.Damage.SpecialCast.Blast = keep
		T.check(bad == false, "feel cast wire: Validate catches SpecialCast.Blast = 5 (0.3..2)")
		local junk = {}
		local function scan(ev)
			for k, v in pairs(ev) do
				if k ~= "_t" and k ~= "targets" and k ~= "heals" and k ~= "shields" and k ~= "stunned" and k ~= "burstTargets" and type(v) ~= "number" and type(v) ~= "string" then
					junk[#junk + 1] = ev.type .. "." .. tostring(k)
				end
			end
			if type(ev.at) == "number" and not near(ev.at * 10, floor(ev.at * 10 + 0.5), 1e-6) then
				junk[#junk + 1] = ev.type .. ".at not in 0.1 steps (" .. tostring(ev.at) .. ")"
			end
		end
		local seen = { Cast = 0, Special = 0, CastBreak = 0 }
		for _, kind in ipairs({ "Blast", "Storm", "Heal", "Pounce" }) do
			local b, f, foes = field(BS, fighter(PC, kind, 2), { { 15, 0 } })
			local evs, t0 = press(b, f, foes)
			for _, ev in ipairs(evs) do
				if ev.type == "Cast" then
					seen.Cast = seen.Cast + 1
					scan(ev)
				end
			end
			if kind == "Pounce" then
				stepTo(b, t0 + 0.2)
				f.stunUntil = b:Time() + 1
			end
			for _, ev in ipairs(stepTo(b, t0 + 1.2)) do
				if seen[ev.type] then
					seen[ev.type] = seen[ev.type] + 1
					scan(ev)
				end
			end
		end
		T.check(seen.Cast == 4 and seen.Special == 3 and seen.CastBreak == 1 and #junk == 0,
			fmt("feel cast wire: Cast (%d) / Special (%d) / CastBreak (%d): numbers and strings only (lists of ids aside), at in 0.1 steps", seen.Cast, seen.Special, seen.CastBreak),
			table.concat(junk, ", "))
	end)

	S.feel_cast_determinism = guarded("feel_cast_determinism", function()
		local BC, BS, PC = load("feel cast determinism")
		if not BC then
			return
		end
		local function ser(v)
			if type(v) ~= "table" then
				return tostring(v)
			end
			local keys = {}
			for k in pairs(v) do
				keys[#keys + 1] = tostring(k)
			end
			table.sort(keys)
			local out = {}
			for _, k in ipairs(keys) do
				local val = v[k]
				if val == nil then
					val = v[tonumber(k)]
				end
				out[#out + 1] = k .. "=" .. ser(val)
			end
			return "{" .. table.concat(out, ",") .. "}"
		end
		local function run()
			local b = BS.new({ Mode = "Duel", Seed = 23, Zone = { X = 60, Z = 60 }, TimeLimit = 300,
				Teams = { { Owner = 1, Side = 1, Auto = true, Pets = { { Def = withSpecial(PC, LEG, "Blast"), Key = LEG, Level = 40, Slot = 1 } } },
					{ Owner = "npc", Side = 2, Npc = true, Pets = { { Def = withSpecial(PC, "biscuit_bear", "Freeze"), Key = "biscuit_bear", Level = 40, Slot = 1 },
						{ Def = withSpecial(PC, "biscuit_bear", "Heal"), Key = "biscuit_bear", Level = 40, Slot = 2 } } } } })
			if not b then
				return nil
			end
			for _, u in ipairs(b.units) do
				u.maxHp, u.hp = u.maxHp * 20, u.maxHp * 20
			end
			local lines, casts = {}, 0
			for _ = 1, 400 do
				for _, ev in ipairs(b:Step(0.1)) do
					lines[#lines + 1] = ser(ev)
					if ev.type == "Cast" then
						casts = casts + 1
					end
				end
			end
			return table.concat(lines, "\n"), casts
		end
		local a, ca = run()
		local c, cc = run()
		T.check(a ~= nil and a == c and ca >= 2 and ca == cc, fmt("feel cast determinism: two Duels (seed 23, 40 s, specials on): the same event stream (%d casts each)", ca or -1))
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

	local function unitModel(parent, name, pos)
		local m = Instance.new("Model")
		m.Name = name
		local root = Instance.new("Part")
		root.Name = "Body"
		root.Anchored = true
		root.Size = V3(2, 2, 2)
		root.CFrame = CFrame.new(pos)
		root.Parent = m
		m.PrimaryPart = root
		m.Parent = parent
		return m
	end

	----------------------------------------------------------------------------------------------
	S.client_feel_tempo_beats = guarded("client_feel_tempo_beats", function()
		local AFC = moduleAt(ROOTS.shared .. "/AttackFxCatalog")
		local Config = moduleAt(ROOTS.shared .. "/Config")
		local F = Config and Config.Battle and Config.Battle.Feel and Config.Battle.Feel.Special
		if not T.check(AFC ~= nil and type(F) == "table" and type(AFC.Reload) == "function" and type(AFC.SpecialAfterglow) == "table",
			"feel tempo beats: AttackFxCatalog (Reload, SpecialAfterglow) and Config.Battle.Feel.Special load") then
			return
		end
		local function res(attack, kind, rarity, d)
			return AFC.Resolve({ Element = "Flame", Attack = attack, Kind = kind, Rarity = rarity, Stage = 0, Distance = d })
		end
		local B = AFC.Beats
		T.check(near(B.SpecialTempo, 1.4) and near(B.SpecialChargeMax, 1.1) and near(B.SpecialSpeed, 0.7) and near(B.SpecialTravelMax, 0.7) and near(B.SpecialImpact, 0.25),
			"feel tempo beats: Beats = SpecialTempo 1.4, SpecialChargeMax 1.1, SpecialSpeed 0.7, SpecialTravelMax 0.7, SpecialImpact 0.25 (Weighty)")
		local ag = AFC.SpecialAfterglow
		T.check(near(ag[1], 1.2, 1e-9) and near(ag[2], 1.8, 1e-9) and near(ag[3], 2.4, 1e-9) and near(ag[4], 3.0, 1e-9), "feel tempo beats: SpecialAfterglow = 1.2 / 1.8 / 2.4 / 3.0")
		local blast = res("Special", "Blast", "Legendary", 14)
		T.check(blast ~= nil and near(blast.Beats.Charge, min(1.1, 0.55 * 1.4 + 0.05 * 2)) and near(blast.Beats.Travel, min(0.7, 14 / 42)) and near(blast.Beats.Impact, 0.25) and near(blast.Afterglow, 2.4, 1e-9),
			"feel tempo beats: a Legendary Blast at 14 studs: charge 0.87, travel 14 / 42, impact 0.25, afterglow 2.4",
			blast and fmt("charge %.3f, travel %.3f, impact %.3f, afterglow %.3f", blast.Beats.Charge, blast.Beats.Travel, blast.Beats.Impact, blast.Afterglow) or "nil")
		local storm = res("Special", "Storm", "Secret", 14)
		T.check(storm ~= nil and near(storm.Beats.Charge, min(1.1, 0.6 * 1.4 + 0.05 * 3)) and near(storm.Beats.Travel, min(0.7, 0.45 / 0.7)),
			"feel tempo beats: a Secret Storm: charge 0.6 x 1.4 + 0.15, travel 0.45 / 0.7", storm and fmt("charge %.3f, travel %.3f", storm.Beats.Charge, storm.Beats.Travel) or "nil")
		local far = res("Special", "Blast", "Secret", 80)
		T.check(far ~= nil and near(far.Beats.Charge, min(1.1, 0.55 * 1.4 + 0.05 * 3)) and near(far.Beats.Travel, 0.7), "feel tempo beats: a Secret Blast at 80 studs: charge 0.92, the travel cap 0.7",
			far and fmt("%.3f / %.3f", far.Beats.Charge, far.Beats.Travel) or "nil")
		-- the charge cap: a long authored charge stops at 1.1
		local keepC = AFC.Specials.Blast.Beats.Charge
		AFC.Specials.Blast.Beats.Charge = 0.9
		local capped = res("Special", "Blast", "Secret", 14)
		AFC.Specials.Blast.Beats.Charge = keepC
		T.check(capped ~= nil and near(capped.Beats.Charge, 1.1), "feel tempo beats: the charge cap: 0.9 x 1.4 + 0.15 stops at 1.1", capped and fmt("%.3f", capped.Beats.Charge) or "nil")
		local melee, ranged = res("Melee", nil, "Legendary", 6), res("Ranged", nil, "Legendary", 14)
		-- Weighty = false: today's numbers
		local keep = F.Weighty
		F.Weighty = false
		local ok, err = pcall(function()
			AFC.Reload()
			local b0 = res("Special", "Blast", "Legendary", 14)
			T.check(b0 ~= nil and near(b0.Beats.Charge, 0.65) and near(b0.Beats.Travel, 14 / 60) and near(b0.Beats.Impact, 0.15) and near(b0.Afterglow, 1.6),
				"feel tempo beats: Weighty = false: today's Blast (charge 0.65, travel 14 / 60, impact 0.15, afterglow 1.6)",
				b0 and fmt("charge %.3f, travel %.3f, impact %.3f, afterglow %.3f", b0.Beats.Charge, b0.Beats.Travel, b0.Beats.Impact, b0.Afterglow) or "nil")
			T.check(near(AFC.Beats.SpecialChargeMax, 0.8) and near(AFC.Beats.SpecialTravelMax, 0.5) and near(AFC.SpecialAfterglow[4], 2.0), "feel tempo beats: ... the caps 0.8 / 0.5, afterglow x1")
			local m0, r0 = res("Melee", nil, "Legendary", 6), res("Ranged", nil, "Legendary", 14)
			local same = true
			for _, k in ipairs({ "Charge", "Release", "Travel", "Impact", "Linger" }) do
				same = same and near(m0.Beats[k], melee.Beats[k]) and near(r0.Beats[k], ranged.Beats[k])
			end
			T.check(same and near(m0.Afterglow, melee.Afterglow) and near(r0.Afterglow, ranged.Afterglow), "feel tempo beats: a Melee / Ranged basic: the same beats and afterglow at both settings")
		end)
		F.Weighty = keep
		AFC.Reload()
		T.check(ok, "feel tempo beats: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	-- the AttackFx world on a fake clock
	local function setup(tag)
		local env = {}
		env.AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		env.AFC = moduleAt(ROOTS.shared .. "/AttackFxCatalog")
		env.Config = moduleAt(ROOTS.shared .. "/Config")
		local AF = env.AF
		if not T.check(AF ~= nil and env.AFC ~= nil and type(AF.Precharge) == "function" and type(AF._Live) == "function", tag .. ": AttackFx (Precharge, _Live), AttackFxCatalog load") then
			return nil
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
		env.holder.Name = "SmokeFeelTempo_" .. tag
		env.holder.Parent = cb
		env.clock = 11000
		env.DT = 1 / 60
		AF.Update(env.clock)
		function env.runTo(at, each)
			while env.clock + env.DT <= at + 1e-9 do
				env.clock = env.clock + env.DT
				AF.Update(env.clock)
				if each then
					each(env.clock)
				end
			end
		end
		function env.pair(x, unit)
			local a = unitModel(env.holder, "A" .. unit, V3(x, G + 1.5, 0))
			local b = unitModel(env.holder, "B" .. unit, V3(x, G + 1.5, -14))
			return { Unit = unit, Model = a }, { Unit = unit + 1000, Model = b }
		end
		function env.ctx(src, tgt, over)
			local c = { Attack = "Special", Kind = "Blast", Element = "Flame", Rarity = "Legendary", Stage = 0, Mine = true, Ground = G, Now = env.clock, From = src, To = { tgt } }
			for k, v in pairs(over or {}) do
				c[k] = v
			end
			return c
		end
		function env.live(unit)
			local found = nil
			for _, e in ipairs(AF._Live()) do
				if e.Unit == unit and e.Recipe.Attack == "Special" and not e.Pre and not e.Retired then
					found = e
				end
			end
			return found
		end
		function env.done()
			AF.ClearAll()
			AF._Deps({ MeshLibrary = false })
			AF.SetQuality(nil)
			pcall(env.holder.Destroy, env.holder)
		end
		return env
	end

	-- the pose's p of `unit` across [at, at + span]: -> p at at + 0.01, at at + span - 0.01, at at + span + 0.03
	local function frozen(env, unit, at, span)
		local ps = {}
		for i, t in ipairs({ at + 0.01, at + span - 0.01, at + span + 0.03 }) do
			env.runTo(t)
			local p = env.AF.Pose(unit)
			ps[i] = p and p.P or nil
			ps[i .. "n"] = p and p.Name or nil
		end
		return ps
	end

	-- one weighty Blast played with its DueAt `dueIn` s away (0.78: the fit cuts the charge, keeps the travel; 1.4: the whole
	-- charge) and its caster's pose across the impact; -> facts
	local function playHold(env, unitBase, dueIn)
		local AF = env.AF
		local out = {}
		local src, tgt = env.pair(unitBase * 10, unitBase)
		local ctx = env.ctx(src, tgt, { DueAt = env.clock + (dueIn or 0.78) })
		out.played = AF.Play(ctx)
		local eff = env.live(unitBase)
		out.late = ctx.ImpactLate
		out.eff = eff
		if eff then
			out.times = { Release = eff.Times.Release, Travel = eff.Times.Travel, Impact = eff.Times.Impact }
			out.afterglow = eff.Afterglow
			local impactAt = eff.Start + eff.Times.Impact
			out.impactAt = impactAt
			out.cast = frozen(env, unitBase, impactAt, AF.SPECIAL_HIT_STOP)
		end
		return out, src, tgt
	end

	S.client_feel_tempo_hold = guarded("client_feel_tempo_hold", function()
		local env = setup("hold")
		if not env then
			return
		end
		local AF, AFC = env.AF, env.AFC
		local ok, err = pcall(function()
			T.check(near(AF.SPECIAL_HIT_STOP, 0.08), fmt("feel tempo hold: AttackFx.SPECIAL_HIT_STOP = 0.08 (%s)", tostring(AF.SPECIAL_HIT_STOP)))
			local r = AFC.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", Rarity = "Legendary", Stage = 0, Distance = 14 })
			local Cb, Rb, Tb = r.Beats.Charge, r.Beats.Release, r.Beats.Travel
			-- (a) the fit: a DueAt 0.78 s away cuts the charge and keeps the travel, no lateness
			local h = playHold(env, 1)
			local tr = h.times and (h.times.Impact - h.times.Travel) or -1
			T.check(h.played and h.times ~= nil and near(tr, Tb, 1e-6) and near(h.times.Release, 0.78 - Rb - Tb, 1e-6) and (h.late or 0) == 0,
				"feel tempo hold: a Blast due 0.78 s away: the charge is cut to fit, the travel kept, no lateness",
				h.times and fmt("charge %.3f (want %.3f), travel %.3f (want %.3f), late %s", h.times.Release, 0.78 - Rb - Tb, tr, Tb, tostring(h.late)) or "no effect")
			-- a cut charge's Cast has played out before the impact: it holds its last frame through the freeze
			local c0 = h.cast or {}
			T.check(c0["1n"] == "Cast" and c0["2n"] == "Cast" and near(c0[1], 1, 1e-6) and near(c0[2], 1, 1e-6),
				"feel tempo hold: (a cut charge) the caster holds its Cast's last frame through the impact's freeze",
				fmt("%s p %s / %s", tostring(c0["1n"]), tostring(c0[1]), tostring(c0[2])))
			AF.ClearAll()
			-- the freeze: the whole charge (due 1.4 s away): the caster's Cast p flat across the impact's 0.08 s, moving after
			local hf = playHold(env, 5, 1.4)
			local c = hf.cast or {}
			T.check(c["1n"] == "Cast" and c[1] ~= nil and c[2] ~= nil and near(c[1], c[2], 1e-6) and c[3] ~= nil and c[3] > c[2] + 1e-4,
				"feel tempo hold: the caster's Cast pose freezes 0.08 s at the impact", fmt("%s p %s / %s / %s", tostring(c["1n"]), tostring(c[1]), tostring(c[2]), tostring(c[3])))
			AF.ClearAll()
			-- the victim's Hurt the same
			local src2, tgt2 = env.pair(40, 2)
			local ctx2 = env.ctx(src2, tgt2, { DueAt = env.clock + 0.78 })
			AF.Play(ctx2)
			local e2 = env.live(2)
			if T.check(e2 ~= nil, "feel tempo hold: (2) a second Blast plays") then
				local hv = frozen(env, tgt2.Unit, e2.Start + e2.Times.Impact, AF.SPECIAL_HIT_STOP)
				T.check(hv["1n"] == "Hurt" and hv[1] ~= nil and near(hv[1], hv[2], 1e-6) and hv[3] ~= nil and hv[3] > hv[2] + 1e-4,
					"feel tempo hold: the victim's Hurt pose freezes 0.08 s at the impact", fmt("%s p %s / %s / %s", tostring(hv["1n"]), tostring(hv[1]), tostring(hv[2]), tostring(hv[3])))
			end
			AF.ClearAll()
			-- (b) the cast hand-over: the charge 0.5 s old, the Special due 0.12 s away with a LateMax 0.3: the travel the fit
			-- cut comes back (<= 0.3), the charge stays backdated
			local src3, tgt3 = env.pair(80, 3)
			local p0 = env.clock
			T.check(AF.Precharge(env.ctx(src3, tgt3, { Seconds = 0.9 })) == true and AF.Precharging(3) ~= nil, "feel tempo hold: (b) a cast's charge starts (Precharge)")
			env.runTo(p0 + 0.5)
			local now = env.clock
			local ctx3 = env.ctx(src3, tgt3, { DueAt = now + 0.12, Precharged = true, LateMax = 0.3, Now = now })
			AF.Play(ctx3)
			local e3 = env.live(3)
			-- fitTimes0 with 0.12 s: the charge goes first, then the travel
			local cut = (Cb + Rb + Tb) - 0.12
			local trCut = max(0, min(Tb, cut - Cb))
			local want = min(0.3, trCut)
			T.check(e3 ~= nil and near(e3.Start, p0, 1e-6) and near(ctx3.ImpactLate, want, 1e-6) and ctx3.ImpactLate <= 0.3 + 1e-9,
				"feel tempo hold: the hand-over keeps the charge backdated and gives the cut travel back: ImpactLate = min(0.30, the cut)",
				fmt("start %.3f vs %.3f, late %s (want %.3f)", e3 and e3.Start or -1, p0, tostring(ctx3.ImpactLate), want))
			T.check(e3 ~= nil and near(e3.Times.Impact - e3.Times.Travel, Tb - trCut + want, 1e-6), "feel tempo hold: ... the travel is back to its length",
				e3 and fmt("travel %.3f", e3.Times.Impact - e3.Times.Travel) or "nil")
		end)
		env.done()
		T.check(ok, "feel tempo hold: no error", tostring(err))
	end)

	S.client_feel_tempo_low = guarded("client_feel_tempo_low", function()
		local env = setup("low")
		if not env then
			return
		end
		local AF = env.AF
		local ok, err = pcall(function()
			local hi = playHold(env, 1, 1.4)
			AF.ClearAll()
			AF.SetQuality("Low")
			AF.Update(env.clock)
			local lo = playHold(env, 2, 1.4)
			local same = hi.times ~= nil and lo.times ~= nil
			if same then
				for k, v in pairs(hi.times) do
					same = same and near(lo.times[k], v, 1e-6)
				end
			end
			T.check(lo.played and same, "feel tempo low: Graphics Low: the same beats as High")
			T.check(hi.afterglow ~= nil and hi.afterglow > 0 and lo.afterglow == 0, fmt("feel tempo low: ... no afterglow on Low (High %s, Low %s)", tostring(hi.afterglow), tostring(lo.afterglow)))
			local c = lo.cast or {}
			T.check(c["1n"] == "Cast" and near(c[1], c[2], 1e-6) and c[3] ~= nil and c[3] > (c[2] or 0) + 1e-4, "feel tempo low: ... the hit freeze kept")
			T.check((AF.Stats().Streaks or 0) == 0, "feel tempo low: ... no streak")
		end)
		env.done()
		T.check(ok, "feel tempo low: no error", tostring(err))
	end)

	----------------------------------------------------------------------------------------------
	-- BattleController on a real BattleSim, sent the way BattleService sends it
	----------------------------------------------------------------------------------------------
	local FRAME = 1 / 30

	local function loadBattle(tag)
		local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
		local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
		local BS = moduleAt(ROOTS.shared .. "/BattleSim")
		local BCat = moduleAt(ROOTS.shared .. "/BattleCatalog")
		if not T.check(BC ~= nil and AF ~= nil and BS ~= nil and BCat ~= nil and BC._Fx ~= nil and type(BC._Casts) == "function" and type(BC._Pre) == "function",
			tag .. ": BattleController (+ _Casts / _Pre), AttackFx, BattleSim, BattleCatalog load") then
			return nil
		end
		return BC, AF, BS, BCat
	end

	-- a Duel: my `myPet` vs NPC `bots` (specials on); -> the driver
	local function driver(BS, myPet, bots, seed)
		local me = LocalPlayer.UserId
		local id = "feel_tempo_" .. tostring(math.random(100000, 999999))
		local foes = {}
		for i, p in ipairs(bots) do
			foes[i] = { PetId = p, Key = p, Level = 20, Tier = "Normal", Slot = i }
		end
		local sim = BS.new({ Mode = "Duel", Seed = seed or 41, Id = id, Zone = { X = 60, Z = 60 }, TimeLimit = 900,
			Teams = { { Owner = me, Side = 1, Pets = { { PetId = myPet, Key = myPet, Level = 20, Tier = "Normal", Slot = 1 } } },
				{ Owner = "bots", Side = 2, Npc = true, Pets = foes } } })
		if not sim then
			return nil
		end
		local d = { sim = sim, id = id, me = me, last = {}, bots = {}, extra = nil }
		for _, u in ipairs(sim.units) do
			u.maxHp, u.hp = 1e6, 1e6
			u.nextAttack = 1e9
			if u.side == 1 then
				d.mine = u
			else
				d.bots[#d.bots + 1] = u
				u.moveSpeed = 0
				u.meter = 0
			end
		end
		d.tm = sim.teams[1]
		d.tm.noEngage = true
		d.mine.x, d.mine.z = 0, 0
		for i, u in ipairs(d.bots) do
			u.x, u.z = 6, (i - 1) * 3
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
			for _, u in ipairs(sim.units) do
				u.nextAttack = 1e9
			end
			local evs = sim:Step(0.1)
			local list = {}
			for _, e in ipairs(evs) do
				list[#list + 1] = e
			end
			for _, e in ipairs(d.extra or {}) do
				list[#list + 1] = e
			end
			d.extra = nil
			if #list > 0 then
				KC.toClient("BattleState", "Events", list, id)
			end
			local snap = sim:SnapshotDelta(d.last)
			snap.BattleId = id
			KC.toClient("BattleState", "Snapshot", snap, id)
			for _ = 1, 3 do
				Mock.Step(FRAME)
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

	local function spyPlays(AF)
		local plays = {}
		local real = AF.Play
		AF.Play = function(ctx)
			local r = real(ctx)
			plays[#plays + 1] = { ctx = ctx, r = r, at = os.clock() }
			return r
		end
		return plays, function()
			AF.Play = real
		end
	end

	local function playOf(plays, uid, since, pre)
		for _, p in ipairs(plays) do
			local c = p.ctx
			if p.at >= since and c.Attack == "Special" and c.From and c.From.Unit == uid and (c.Pre == true) == (pre == true) then
				return p
			end
		end
		return nil
	end

	S.client_feel_tempo_cast = guarded("client_feel_tempo_cast", function()
		local BC, AF, BS, BCat = loadBattle("feel tempo cast")
		if not BC then
			return
		end
		local err0 = #Mock.Errors
		local keepDelay = BCat.Damage.NpcSpecialDelay
		BCat.Damage.NpcSpecialDelay = { 0, 0 }
		AF.ClearAll()
		AF.SetQuality("High")
		local plays, undo = spyPlays(AF)
		local shatters = {}
		BC.FxHooks()
		local realShatter = AF.Hooks.Shatter
		AF.Hooks.Shatter = function(mine, unit)
			shatters[#shatters + 1] = { mine = mine, at = os.clock() }
			return realShatter and realShatter(mine, unit)
		end
		local d = nil
		local ok, err = pcall(function()
			d = driver(BS, "puddle_frog", { "puddle_frog", "puddle_frog" })
			if not T.check(d ~= nil and d.mine ~= nil and #d.bots == 2, "feel tempo cast: (setup) my Blast frog vs two NPC Blast frogs") then
				return
			end
			local sim, mine, bot = d.sim, d.mine, d.bots[1]
			for _ = 1, 5 do
				d.step()
			end
			-- 1) an enemy's cast: its charge starts on the Cast's arrival, its Special takes it over
			bot.meter = 100
			local cast = nil
			for _ = 1, 20 do
				local evs = d.step()
				cast = cast or findEvent(evs, "Cast", function(ev) return ev.unit == bot.id end)
				if cast then
					break
				end
			end
			if not T.check(cast ~= nil, "feel tempo cast: the NPC frog casts (a Cast event)") then
				return
			end
			local preNow = AF.Precharging(bot.id)
			local rec = BC._Casts() and BC._Casts()[bot.id]
			T.check(preNow ~= nil and rec ~= nil and rec.Kind == "Blast", "feel tempo cast: on Cast the enemy's charge starts on my screen (AttackFx.Precharge, a B.casts record)")
			local since = os.clock()
			local sp = nil
			for _ = 1, 14 do
				local evs = d.step()
				sp = sp or findEvent(evs, "Special", function(ev) return ev.unit == bot.id end)
				if sp then
					d.step()
					break
				end
			end
			local p = playOf(plays, bot.id, since, false)
			T.check(sp ~= nil and sp.at ~= nil and p ~= nil and p.r == true and p.ctx.Precharged == true and near(p.ctx.LateMax, 0.3, 1e-9),
				"feel tempo cast: its Special (with at) takes the charge over (Precharged, LateMax = TravelHold 0.3)",
				p and fmt("precharged %s, late max %s", tostring(p.ctx.Precharged), tostring(p.ctx.LateMax)) or "no play")
			T.check(p ~= nil and (p.ctx.ImpactLate or 0) <= 0.3 + 1e-9 and AF.Precharging(bot.id) == nil and (BC._Casts() or {})[bot.id] == nil,
				"feel tempo cast: ... the impact at most 0.3 s late, the charge handed over, the record gone", p and fmt("late %s", tostring(p.ctx.ImpactLate)) or "")
			for _ = 1, 15 do
				d.step()
			end

			-- 2) my press: the prediction waits for the cast (PRESS_WAIT extended), the Special takes it over
			mine.meter = 100
			bot.meter, d.bots[2].meter = 0, 0
			for _ = 1, 3 do
				d.step()
			end
			sim:Command(d.me, "Target", bot.id)
			local P = os.clock()
			local sent = BC.Command("Special")
			local pre0 = BC._Pre()
			T.check(sent and pre0 ~= nil and AF.Precharging(mine.id) ~= nil, "feel tempo cast: my press shows its charge at once (the prediction)")
			d.step()
			sim:Command(d.me, "Special")
			local myCast = nil
			for _ = 1, 3 do
				local evs = d.step()
				myCast = myCast or findEvent(evs, "Cast", function(ev) return ev.unit == mine.id end)
			end
			local pre1 = BC._Pre()
			local rec1 = (BC._Casts() or {})[mine.id]
			T.check(myCast ~= nil and pre1 ~= nil and rec1 ~= nil and near(pre1.untilT, rec1.DueAt + 0.5, 1e-6),
				"feel tempo cast: my Cast extends the press's wait to the cast's end + CAST_WAIT 0.5", pre1 and rec1 and fmt("until %.3f, due %.3f", pre1.untilT, rec1.DueAt) or "nil")
			-- no shatter at the old PRESS_WAIT 0.7 s
			local n0 = #shatters
			while os.clock() < P + 0.75 do
				d.step()
			end
			T.check(#shatters == n0 and AF.Precharging(mine.id) ~= nil, "feel tempo cast: ... no shatter at 0.7 s (the cast is still running)")
			local since2 = os.clock()
			local mySp = nil
			for _ = 1, 12 do
				local evs = d.step()
				mySp = mySp or findEvent(evs, "Special", function(ev) return ev.unit == mine.id end)
				if mySp then
					d.step()
					break
				end
			end
			local p2 = playOf(plays, mine.id, since2, false)
			T.check(mySp ~= nil and p2 ~= nil and p2.r == true and p2.ctx.Precharged == true and #shatters == n0 and BC._Pre() == nil and (p2.ctx.ImpactLate or 0) <= 0.3 + 1e-9,
				"feel tempo cast: my Special takes the press's charge over at the cast's end (no shatter, late <= 0.3)",
				p2 and fmt("late %s", tostring(p2.ctx.ImpactLate)) or "no play")
			for _ = 1, 15 do
				d.step()
			end

			-- 3) "break": a CastBreak shatters that unit's charge (an enemy's quietly), the record goes
			bot.meter = 100
			local c3 = nil
			for _ = 1, 20 do
				local evs = d.step()
				c3 = c3 or findEvent(evs, "Cast", function(ev) return ev.unit == bot.id end)
				if c3 then
					break
				end
			end
			if T.check(c3 ~= nil and AF.Precharging(bot.id) ~= nil, "feel tempo cast: (break) the enemy casts again, its charge shows") then
				local n3 = #shatters
				bot.stunUntil = sim:Time() + 2
				local brk = nil
				for _ = 1, 3 do
					local evs = d.step()
					brk = brk or findEvent(evs, "CastBreak", function(ev) return ev.unit == bot.id end)
				end
				d.step()
				T.check(brk ~= nil and AF.Precharging(bot.id) == nil and (BC._Casts() or {})[bot.id] == nil and #shatters == n3,
					"feel tempo cast: a CastBreak shatters the enemy's charge quietly (no 'interrupted' cue), the record gone")
			end
			for _ = 1, 25 do
				d.step()
			end

			-- 4) a Cast with no Special by its end + 0.5: a quiet fade, no error
			local fake = { type = "Cast", unit = d.bots[2].id, kind = "Blast", name = "Test", at = sim:Time() + 0.6, target = mine.id, tx = 0, tz = 0 }
			d.extra = { fake }
			d.step()
			T.check(AF.Precharging(d.bots[2].id) ~= nil and (BC._Casts() or {})[d.bots[2].id] ~= nil, "feel tempo cast: (no Special) a Cast starts the charge")
			local n4 = #shatters
			for _ = 1, 14 do
				d.step()
			end
			T.check(AF.Precharging(d.bots[2].id) == nil and (BC._Casts() or {})[d.bots[2].id] == nil and #shatters == n4,
				"feel tempo cast: ... no Special by its end + CAST_WAIT: the charge fades quietly, the record gone")

			-- 5) "old events": no Cast and a Special without at (RealCast off on this sim): today's LATE_MAX path
			local keepSC = BCat.Damage.SpecialCast
			BCat.Damage.SpecialCast = nil
			local ok5, err5 = pcall(function()
				bot.meter = 100
				bot.stunUntil = 0
				local since5 = os.clock()
				local s5, c5 = nil, nil
				for _ = 1, 30 do
					local evs = d.step()
					c5 = c5 or findEvent(evs, "Cast", function(ev) return ev.unit == bot.id end)
					s5 = s5 or findEvent(evs, "Special", function(ev) return ev.unit == bot.id end)
					if s5 then
						d.step()
						break
					end
				end
				local p5 = playOf(plays, bot.id, since5, false)
				T.check(c5 == nil and s5 ~= nil and s5.at == nil and p5 ~= nil and p5.ctx.Precharged == nil and near(p5.ctx.LateMax, 0.35, 1e-9) and (p5.ctx.ImpactLate or 0) <= 0.35 + 1e-9,
					"feel tempo cast: old events (no Cast, a Special without at): today's path (no hand-over, LateMax = LATE_MAX 0.35)",
					p5 and fmt("precharged %s, late max %s, late %s", tostring(p5.ctx.Precharged), tostring(p5.ctx.LateMax), tostring(p5.ctx.ImpactLate)) or "no play")
			end)
			BCat.Damage.SpecialCast = keepSC
			T.check(ok5, "feel tempo cast: (old events) no error", tostring(err5))
		end)
		undo()
		AF.Hooks.Shatter = realShatter
		BCat.Damage.NpcSpecialDelay = keepDelay
		if d then
			d.finish()
		end
		T.check(ok and #Mock.Errors == err0, "feel tempo cast: no error", tostring(err))
		KC.flushErrors("client_feel_tempo_cast")
	end)

	S.client_feel_tempo_callout = guarded("client_feel_tempo_callout", function()
		local BC, AF, BS, BCat = loadBattle("feel tempo callout")
		if not BC then
			return
		end
		local calls = {}
		local realNumber = BC._Fx.Number
		BC._Fx.Number = function(adornee, height, text, color, px, life)
			calls[#calls + 1] = { text = tostring(text), life = life }
			return realNumber(adornee, height, text, color, px, life)
		end
		local d = nil
		local ok, err = pcall(function()
			d = driver(BS, "puddle_frog", { "biscuit_bear" })
			if not T.check(d ~= nil, "feel tempo callout: (setup) a Duel") then
				return
			end
			for _ = 1, 3 do
				d.step()
			end
			d.mine.meter = 100
			d.sim:Command(d.me, "Target", d.bots[1].id)
			d.sim:Command(d.me, "Special")
			for _ = 1, 16 do
				d.step()
			end
			local callout = nil
			for _, c in ipairs(calls) do
				if string.sub(c.text, -1) == "!" and c.text ~= "KO!" and string.upper(c.text) == c.text and string.find(c.text, "%a") then
					callout = c
				end
			end
			T.check(callout ~= nil and near(callout.life, 1.6, 1e-9), "feel tempo callout: the Special's name callout lives 1.6 s",
				callout and fmt("%s: %s s", callout.text, tostring(callout.life)) or "no callout")
		end)
		BC._Fx.Number = realNumber
		if d then
			d.finish()
		end
		T.check(ok, "feel tempo callout: no error", tostring(err))
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
