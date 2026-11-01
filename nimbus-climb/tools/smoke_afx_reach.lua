-- smoke_afx_reach.lua: real reach (docs/superpowers/specs/2026-11-01-attack-fx-design.md "What reach covers"; plan Task 1), loaded
-- by tools/smoke.py in both worlds. Server world, pure:
--   afx_reach_table    BattleCatalog.Reach 1 / 1.15 / 1.3, ReachOf (junk = 1, clamped 0..2, floored), Validate catches a bad table
--   afx_reach_sim      an evolved fighter's Blast / Storm / Freeze / Beam / Pounce and its element Cone / Line / Circle really reach
--                      x1.15 / x1.3 (the body's edge rule of inCircle / inLine / inCone), the event carries the number; Evo 0 hits at
--                      the catalog's number and sends none (the traffic budget: p3fixsrv_net16), a ranged fighter still reaches out
--                      to its own range, unitInfo.reach
--   afx_reach_npc      a wild pet, a hybrid, a low Common, a junk Evo = x1 and no error; a Common clamps to its top stage; a Ring
--                      champion at Evo 2 reaches x1.3 like a player's pet
--   afx_reach_timers   every Seconds / Stun / Cooldown of Specials, ElementAttacks and Buffs is the frozen literal: visuals last
--                      longer in this spec, ability timers never move
--   afx_docs           README.md says Reach +15% / +30% in its Evolution section and names the camera kick; tools/README.md names the
--                      three smoke_afx_*.lua files
-- Client world:
--   client_afx_reach_draw    the event's numbers reach the drawing: the Blast ground ring peaks at r, the Beam stretches to its real
--                            length and width, the element shapes; an old event with no numbers draws catalog x the unit's stage
--                            (never nil, never 0); a real evolved Storm's effect lands on exactly the enemies its 7.8 zone hits; the
--                            cube fallbacks draw the same numbers
--   client_afx_reach_detail  the Pets detail says "Reach +15%" / "Reach +30%" for an evolved pet, nothing at stage 0
-- White-box: the server half reaches into battle.units / battle.teams (same Lua state). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, cos, sin = math.abs, math.max, math.cos, math.sin
local fmt = string.format

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
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

	-- a catalog pet copied with changes (identical stats otherwise), smoke_p5_battlecore's cloneDef
	local function cloneDef(PC, petId, changes)
		local def = {}
		for k, v in pairs(PC.Get(petId)) do
			def[k] = v
		end
		def.Id = petId .. "_test"
		for k, v in pairs(changes or {}) do
			def[k] = v
		end
		return def
	end

	local function withSpecial(PC, petId, kind, changes)
		local all = { Special = { Id = "t_" .. kind, Name = "Test " .. kind, Kind = kind, Power = 40, Color = PC.Get(petId).Special.Color } }
		for k, v in pairs(changes or {}) do
			all[k] = v
		end
		return cloneDef(PC, petId, all)
	end

	local function findEvent(events, kind, pred)
		for _, ev in ipairs(events) do
			if ev.type == kind and (pred == nil or pred(ev)) then
				return ev
			end
		end
		return nil
	end

	local function has(list, id)
		for _, v in ipairs(list or {}) do
			if v == id then
				return true
			end
		end
		return false
	end

	-- a Duel on a wide floor: my fighter (`entry`, a Legendary by default) at the origin, one standing bear per spot
	local function field(BS, entry, spots)
		local foes = {}
		for i = 1, #spots do
			foes[i] = { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = i }
		end
		entry.Slot = 1
		local b = BS.new({ Mode = "Duel", Seed = 7, Zone = { X = 160, Z = 160 }, TimeLimit = 300,
			Teams = { { Owner = 1, Side = 1, Pets = { entry } }, { Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = foes } } })
		if not b then
			return nil
		end
		local tm = b.teams[1]
		local f = tm.fighter
		f.x, f.z, f.px, f.pz = 0, 0, 0, 0
		tm.wantX, tm.wantZ = 0, 0
		local on = {}
		for _, u in ipairs(b.units) do
			if u.side == 2 then
				on[#on + 1] = u
				local p = spots[#on]
				u.x, u.z, u.px, u.pz, u.moveSpeed = p[1], p[2], p[1], p[2], 0
			end
		end
		return b, f, on
	end

	-- my fighter casts its Special at foes[1]: the Special event, every event, the battle time before the cast
	local function special(b, f, foes)
		f.meter = 100
		b:Command(1, "Target", foes[1].id)
		local t0 = b:Time()
		local ok, why = b:Command(1, "Special")
		local evs = b:Step(0.05)
		return findEvent(evs, "Special"), evs, t0, ok, why
	end

	S.afx_reach_table = guarded("afx_reach_table", function()
		local BC = req("BattleCatalog")
		if not T.check(BC ~= nil and type(BC.ReachOf) == "function" and type(BC.Reach) == "table", "afx reach: BattleCatalog.Reach + ReachOf exist") then
			return
		end
		T.check(BC.ReachOf(0) == 1 and near(BC.ReachOf(1), 1.15, 1e-9) and near(BC.ReachOf(2), 1.3, 1e-9), "afx reach: the table is 1 / 1.15 / 1.3")
		T.check(BC.ReachOf(nil) == 1 and BC.ReachOf("x") == 1 and BC.ReachOf(-3) == 1 and near(BC.ReachOf(7), 1.3, 1e-9) and near(BC.ReachOf(1.9), 1.15, 1e-9) and BC.ReachOf(0 / 0) == 1 and near(BC.ReachOf(math.huge), 1, 1e-9),
			"afx reach: junk = 1 (nil, a word, NaN, inf), clamped 0..2, floored")
		T.check(select(1, BC.Validate()) == true, "afx reach: Validate still passes")
		local keep = BC.Reach[2]
		BC.Reach[2] = 1.1
		local ok = BC.Validate()
		BC.Reach[2] = keep
		T.check(ok == false, "afx reach: Validate catches a table that falls with the stage")
	end)

	S.afx_reach_sim = guarded("afx_reach_sim", function()
		local BC, BS, PC = req("BattleCatalog"), req("BattleSim"), req("PetCatalog")
		if not T.check(BC ~= nil and BS ~= nil and PC ~= nil and type(BC.ReachOf) == "function", "afx reach sim: the modules load, with ReachOf") then
			return
		end
		local LEG = "ember_phoenix" -- a Legendary: evolves twice
		local function fighter(kind, evo)
			return { Def = withSpecial(PC, LEG, kind), Key = LEG, Level = 50, Evo = evo }
		end

		-- Blast: the second bear stands d off the aimed one
		local function blast(evo, d)
			local b, f, foes = field(BS, fighter("Blast", evo), { { 20, 0 }, { 20, d } })
			local sp = special(b, f, foes)
			return sp, sp and has(sp.targets, foes[2].id), foes[2].radius
		end
		local sp, _, rad = blast(2, 1)
		T.check(sp ~= nil and sp.kind == "Blast" and near(sp.r, 9.1, 1e-6), "afx reach: Blast r = 7 x 1.3 = 9.1 on the event", sp and tostring(sp.r))
		local _, inside = blast(2, 9.1 + 0.6 * rad)
		local _, outside = blast(2, 9.1 + rad + 0.5)
		local _, oldEdge = blast(0, 9.1 + 0.6 * rad)
		T.check(inside == true and outside == false and oldEdge == false,
			"afx reach: an enemy in by its edge (centre at r + 0.6 x its radius) is hit, one past r + its radius + 0.5 is not; the same spot is out of an unevolved Blast")
		local sp1 = blast(1, 1)
		local _, in1 = blast(1, 7 * 1.15 + 0.6 * rad)
		local _, out1 = blast(1, 7 * 1.15 + rad + 0.5)
		T.check(sp1 ~= nil and near(sp1.r, 8.05, 0.051) and in1 == true and out1 == false, "afx reach: Evo 1 Blast x1.15 (the sim 8.05, the event within its 0.1 rounding)", sp1 and tostring(sp1.r))
		local sp0 = blast(0, 1)
		local _, in0 = blast(0, 7 + 0.6 * rad)
		local _, out0 = blast(0, 7 + rad + 0.5)
		T.check(sp0 ~= nil and sp0.r == nil and in0 == true and out0 == false, "afx reach: Evo 0 Blast hits at the catalog's 7, no number on the wire", sp0 and tostring(sp0.r))

		-- Storm
		do
			local b, f, foes = field(BS, fighter("Storm", 2), { { 20, 0 } })
			local _, evs, t0 = special(b, f, foes)
			local zone = b.zones[#b.zones]
			local zoneEv = findEvent(evs, "Zone")
			local stormEv = findEvent(evs, "Special")
			T.check(zone ~= nil and zone.r == 6 * 1.3 and zoneEv ~= nil and zoneEv.r == zone.r and near(zone.untilT - t0, 4, 0.06) and zoneEv.seconds == 4,
				"afx reach: the Storm zone is 7.8 wide and still lasts 4 s", zone and fmt("r %s, %.2f s", tostring(zone.r), zone.untilT - t0))
			T.check(stormEv ~= nil and near(stormEv.r, 7.8, 1e-6), "afx reach: the Storm's Special event names its radius", stormEv and tostring(stormEv.r))
			b, f, foes = field(BS, fighter("Storm", 0), { { 20, 0 } })
			_, evs = special(b, f, foes)
			T.check(findEvent(evs, "Zone").r == 6 and findEvent(evs, "Special").r == nil, "afx reach: Evo 0 Storm is the catalog's 6 (the Zone event names it, as ever)")
		end

		-- Freeze
		do
			local b, f, foes = field(BS, fighter("Freeze", 2), { { 20, 0 }, { 20, 7.8 + 0.6 * rad } })
			local frz, _, t0 = special(b, f, foes)
			local want = 0.8 * (f.specialFactor or 1)
			T.check(frz ~= nil and near(frz.r, 7.8, 1e-6) and near(foes[1].stunUntil - t0, want, 0.06), "afx reach: Freeze r 7.8, the stun time unchanged",
				frz and fmt("r %s, stun %.2f (want %.2f)", tostring(frz.r), foes[1].stunUntil - t0, want))
			T.check(has(frz and frz.targets, foes[2].id), "afx reach: Freeze catches an enemy at the wider edge")
			b, f, foes = field(BS, fighter("Freeze", 0), { { 20, 0 }, { 20, 6 + 0.6 * rad } })
			frz = special(b, f, foes)
			T.check(frz ~= nil and frz.r == nil and has(frz.targets, foes[2].id), "afx reach: Evo 0 Freeze hits at the catalog's 6, no number on the wire")
			b, f, foes = field(BS, fighter("Freeze", 0), { { 20, 0 }, { 20, 6 + rad + 0.5 } })
			T.check(not has(special(b, f, foes).targets, foes[2].id), "afx reach: ...and not past its own edge, where the evolved one still reaches")
		end

		-- Beam: along +X through a near bear; the second bear farther down the line
		do
			local function beam(evo, along, side)
				local b, f, foes = field(BS, fighter("Beam", evo), { { 5, 0 }, { along, side or 0 } })
				local ev = special(b, f, foes)
				return ev, ev and has(ev.targets, foes[2].id), foes[2].radius
			end
			local ev, _, r2 = beam(2, 10)
			local length, width = 26 * 1.3, 4 * 1.3
			T.check(ev ~= nil and near(ev.length, 33.8, 1e-6) and near(ev.width, 5.2, 1e-6), "afx reach: Beam 26 x 1.3 long, 4 x 1.3 wide on the event", ev and fmt("%s x %s", tostring(ev.length), tostring(ev.width)))
			local _, hitLong = beam(2, length + 0.6 * r2)
			local _, missLong = beam(2, length + r2 + 0.5)
			T.check(hitLong == true and missLong == false, "afx reach: the Beam hits to its real end (the body's edge rule of inLine), not past it")
			local _, hitWide = beam(2, 15, width / 2 + r2 - 0.1)
			local _, missWide = beam(2, 15, width / 2 + r2 + 0.5)
			local _, oldWide = beam(0, 15, width / 2 + r2 - 0.1)
			T.check(hitWide == true and missWide == false and oldWide == false, "afx reach: ...and to its real width")
			local ev1 = beam(1, 10)
			local ev0 = beam(0, 10)
			local _, in0 = beam(0, 26 + 0.6 * r2)
			local _, out0 = beam(0, 26 + r2 + 0.5)
			T.check(ev1 ~= nil and near(ev1.length, 29.9, 1e-6) and near(ev1.width, 4.6, 1e-6) and ev0 ~= nil and ev0.length == nil and ev0.width == nil and in0 == true and out0 == false, "afx reach: Evo 1 = 29.9 x 4.6, Evo 0 hits at the catalog's 26, no number on the wire")
		end

		-- Pounce: the fighter strikes its lock from afar; past Range + radius it takes the nearest within Range + 3, else TooFar
		do
			local function pounce(evo, d)
				local b, f, foes = field(BS, fighter("Pounce", evo), { { d, 0 } })
				local ev, _, _, ok, why = special(b, f, foes)
				return ev, ok, why, foes[1].radius
			end
			local ev, ok = pounce(2, 38)
			T.check(ok == true and ev ~= nil and near(ev.range, 39, 1e-6), "afx reach: Pounce range 39 on the event, a target 38 off is struck", ev and tostring(ev.range))
			local _, _, _, r3 = pounce(2, 10)
			local _, okFar, whyFar = pounce(2, 39 + 3 + r3 + 0.5)
			T.check(okFar == false and whyFar == "TooFar", "afx reach: Pounce refuses TooFar past its range + the nearest-target margin", tostring(whyFar))
			local ev0, ok0 = pounce(0, 10)
			local _, okOld, whyOld = pounce(0, 38)
			T.check(ok0 == true and ev0 ~= nil and ev0.range == nil and okOld == false and whyOld == "TooFar", "afx reach: Evo 0 Pounce keeps 30: the same 38 is TooFar", tostring(whyOld))
		end

		-- element attacks
		do
			local function element(el, evo, spots, tweak)
				local entry = { Def = cloneDef(PC, LEG, { Element = el, Elements = { el } }), Key = LEG, Level = 50, Evo = evo }
				local b, f, foes = field(BS, entry, spots)
				f.ranged = false -- (the phoenix is ranged: its own range is the last check here)
				if tweak then
					tweak(f)
				end
				local ok, why = b:Command(1, "Element", foes[1].id)
				local evs = b:Step(0.05)
				return findEvent(evs, "Element"), foes, ok, why
			end
			-- Cone: the aimed bear straight ahead, the second one down the axis
			local el, foes = element("Flame", 2, { { 5, 0 }, { 10, 0 } })
			local rad2 = foes[2].radius
			T.check(el ~= nil and near(el.length, 18.2, 1e-6) and el.shape == "Cone", "afx reach: Cone length 14 x 1.3 on the event", el and tostring(el.length))
			local coneIn = element("Flame", 2, { { 5, 0 }, { 18.2 + 0.6 * rad2, 0 } })
			local coneOut = element("Flame", 2, { { 5, 0 }, { 18.2 + rad2 + 0.5, 0 } })
			local coneOld = element("Flame", 0, { { 5, 0 }, { 18.2 + 0.6 * rad2, 0 } })
			T.check(has(coneIn.targets, foes[2].id) and not has(coneOut.targets, foes[2].id) and not has(coneOld.targets, foes[2].id), "afx reach: the Cone hits to its real end, past the unevolved one")
			-- the Angle does not grow: a bear just outside 30 degrees + the body's widening stays out at Evo 2 as at Evo 0
			local d = 12
			local half = BC.ElementAttacks.Flame.Angle * math.pi / 360
			local off = half + rad2 / d + 0.05
			local wide = element("Flame", 2, { { 5, 0 }, { cos(off) * d, sin(off) * d } })
			local onEdge = half - 0.02
			local narrow = element("Flame", 2, { { 5, 0 }, { cos(onEdge) * d, sin(onEdge) * d } })
			T.check(BC.ElementAttacks.Flame.Angle == 60 and not has(wide.targets, foes[2].id) and has(narrow.targets, foes[2].id), "afx reach: the Cone's Angle is unchanged")
			local coneIn0 = element("Flame", 0, { { 5, 0 }, { 14 + 0.6 * rad2, 0 } })
			T.check(coneIn0.length == nil and has(coneIn0.targets, foes[2].id), "afx reach: Evo 0 Cone hits at the catalog's 14, no number on the wire")
			-- Circle round the caster
			local circle = element("Earth", 2, { { 5, 0 } })
			T.check(circle ~= nil and near(circle.r, 10.4, 1e-6) and circle.shape == "Circle", "afx reach: Circle radius 8 x 1.3", circle and tostring(circle.r))
			local circleIn = element("Earth", 2, { { 5, 0 }, { 0, 10.4 + 0.6 * rad2 } })
			local circleOut = element("Earth", 2, { { 5, 0 }, { 0, 10.4 + rad2 + 0.5 } })
			T.check(has(circleIn.targets, foes[2].id) and not has(circleOut.targets, foes[2].id), "afx reach: the Circle hits to its real edge")
			local circleIn0 = element("Earth", 0, { { 5, 0 }, { 0, 8 + 0.6 * rad2 } })
			local circleOut0 = element("Earth", 0, { { 5, 0 }, { 0, 10.4 + 0.6 * rad2 } })
			T.check(circleIn0.r == nil and has(circleIn0.targets, foes[2].id) and not has(circleOut0.targets, foes[2].id), "afx reach: Evo 0 Circle hits at the catalog's 8, no number on the wire")
			-- Line
			local line = element("Storm", 2, { { 5, 0 } })
			T.check(line ~= nil and near(line.length, 31.2, 1e-6) and near(line.width, 5.2, 1e-6) and line.shape == "Line", "afx reach: Line 24 x 1.3 by 4 x 1.3", line and fmt("%s x %s", tostring(line.length), tostring(line.width)))
			local lineIn = element("Storm", 2, { { 5, 0 }, { 24 * 1.3 + 0.6 * rad2, 0 } })
			local lineOut = element("Storm", 2, { { 5, 0 }, { 24 * 1.3 + rad2 + 0.5, 0 } })
			T.check(has(lineIn.targets, foes[2].id) and not has(lineOut.targets, foes[2].id), "afx reach: the Line hits to its real end")
			local line0 = element("Storm", 0, { { 5, 0 } })
			local lineIn0 = element("Storm", 0, { { 5, 0 }, { 24 + 0.6 * rad2, 0 } })
			T.check(line0.length == nil and line0.width == nil and has(lineIn0.targets, foes[2].id), "afx reach: Evo 0 Line hits at the catalog's 24, no number on the wire")
			-- a ranged fighter reaches out to its own range at least
			local far = element("Flame", 2, { { 5, 0 } }, function(f)
				f.ranged, f.range = true, 25
			end)
			local short = element("Flame", 2, { { 5, 0 } }, function(f)
				f.ranged, f.range = true, 5
			end)
			T.check(far.length == max(18.2, 25) and near(short.length, 18.2, 1e-6), "afx reach: a ranged fighter still reaches out to its own range at least", fmt("%s, %s", tostring(far.length), tostring(short.length)))
			local far0 = element("Flame", 0, { { 5, 0 }, { 25 + 0.6 * rad2, 0 } }, function(f)
				f.ranged, f.range = true, 25
			end)
			T.check(far0.length == nil and has(far0.targets, foes[2].id), "afx reach: ...an unevolved one too, its range off the wire (the client has it)")
		end

		-- unitInfo
		do
			local b, f = field(BS, fighter("Blast", 2), { { 20, 0 } })
			local info = nil
			for _, u in ipairs(b:StaticUnits()) do
				if u.id == f.id then
					info = u
				end
			end
			T.check(info ~= nil and info.reach == 1.3, "afx reach: unitInfo.reach", info and tostring(info.reach))
			b, f = field(BS, fighter("Blast", 0), { { 20, 0 } })
			info = nil
			for _, u in ipairs(b:StaticUnits()) do
				if u.id == f.id then
					info = u
				end
			end
			T.check(info ~= nil and info.reach == nil, "afx reach: ...nil at x1, off the wire", info and tostring(info.reach))
		end
	end)

	S.afx_reach_npc = guarded("afx_reach_npc", function()
		local BC, BS, PC = req("BattleCatalog"), req("BattleSim"), req("PetCatalog")
		if not T.check(BC ~= nil and BS ~= nil and PC ~= nil, "afx reach npc: the modules load") then
			return
		end
		-- an NPC's own full meter: its Blast at my standing fighter
		local function npcBlast(entry)
			entry.Slot = 1
			local b = BS.new({ Mode = "Duel", Seed = 9, Zone = { X = 160, Z = 160 }, TimeLimit = 300,
				Teams = { { Owner = 1, Side = 1, Pets = { { Key = "biscuit_bear", Level = 40, NoSpecial = true, Slot = 1 } } }, { Owner = "npc", Side = 2, Npc = true, Pets = { entry } } } })
			if not b then
				return nil
			end
			for _ = 1, 200 do
				for _, u in ipairs(b.units) do
					if u.side == 2 then
						u.meter = 100
					end
				end
				local ev = findEvent(b:Step(0.1), "Special", function(e)
					return e.kind == "Blast"
				end)
				if ev then
					return ev
				end
			end
			return nil
		end
		local function blastDef(id, changes)
			return withSpecial(PC, id, "Blast", changes)
		end
		local wild = npcBlast({ Def = blastDef("ember_phoenix"), Key = "ember_phoenix", Level = 50, Wild = true })
		local hybridNoEvo = npcBlast({ Def = blastDef("ember_phoenix", { Elements = { "Flame", "Storm" } }), Key = "ember_phoenix", Level = 50 })
		local junkEvo = npcBlast({ Def = blastDef("ember_phoenix"), Key = "ember_phoenix", Level = 50, Evo = "x" })
		local lowCommon = npcBlast({ Def = blastDef("mallow_kitten"), Key = "mallow_kitten", Level = 3 })
		T.check(wild ~= nil and wild.r == nil and hybridNoEvo ~= nil and hybridNoEvo.r == nil and junkEvo ~= nil and junkEvo.r == nil and lowCommon ~= nil and lowCommon.r == nil,
			"afx reach: a wild pet / a hybrid / Evo 'x' / a Level 3 Common = x1 (no number on the wire), no error",
			fmt("%s %s %s %s", tostring(wild and wild.r), tostring(hybridNoEvo and hybridNoEvo.r), tostring(junkEvo and junkEvo.r), tostring(lowCommon and lowCommon.r)))
		-- a Common's top stage is 1: a stored 2 reads as x1.15 (PetCatalog.EvolutionStage cleans it)
		local topCommon = npcBlast({ Def = blastDef("mallow_kitten"), Key = "mallow_kitten", Level = 60, Evo = 2 })
		T.check(topCommon ~= nil and near(topCommon.r, 8.05, 0.051), "afx reach: a Common with a stored Evo 2 reaches x1.15, its top stage", topCommon and tostring(topCommon.r))
		-- a Ring champion that ChampionTeam evolves
		local champ, entry = nil, nil
		for seed = 1, 40 do
			local c = BC.ChampionTeam(60, seed)
			if c and c.Pets[1] and c.Pets[1].Evo == 2 then
				champ, entry = c, c.Pets[1]
				break
			end
		end
		if T.check(champ ~= nil, "afx reach: Ring round 60 has a champion at Evo 2 (an Epic+ species at ChampionLevel >= 50)") then
			local e = {}
			for k, v in pairs(entry) do
				e[k] = v
			end
			e.Def = blastDef(entry.PetId)
			e.Key = entry.PetId
			local npcCast = npcBlast(e)
			T.check(npcCast ~= nil and npcCast.r == 9.1, "afx reach: a Ring champion at Evo 2 casts a 9.1 Blast (NPC pets follow their own stage)", npcCast and tostring(npcCast.r))
		end
	end)

	-- the frozen table, every value a literal (spec "Lasting longer: visuals only")
	S.afx_reach_timers = guarded("afx_reach_timers", function()
		local BC = req("BattleCatalog")
		if not T.check(BC ~= nil, "afx timers: BattleCatalog loads") then
			return
		end
		local SP, EA, BU = BC.Specials, BC.ElementAttacks, BC.Buffs
		local specials = {
			{ "Shield.Seconds", SP.Shield.Seconds, 6 }, { "Storm.Seconds", SP.Storm.Seconds, 4 }, { "Freeze.Stun", SP.Freeze.Stun, 0.8 },
			{ "Rally.Seconds", SP.Rally.Seconds, 8 }, { "Haste.Seconds", SP.Haste.Seconds, 8 },
		}
		for _, row in ipairs(specials) do
			T.check(row[2] == row[3], "afx timers: Specials." .. row[1] .. " unchanged", tostring(row[2]))
		end
		local elements = {
			{ "Flame.Burn.Seconds", EA.Flame.Burn.Seconds, 3 }, { "Frost.Slow.Seconds", EA.Frost.Slow.Seconds, 4 },
			{ "Earth.Stun", EA.Earth.Stun, 0.5 }, { "Shadow.Weaken.Seconds", EA.Shadow.Weaken.Seconds, 5 },
		}
		for _, row in ipairs(elements) do
			T.check(row[2] == row[3], "afx timers: ElementAttacks." .. row[1] .. " unchanged", tostring(row[2]))
		end
		-- { Seconds, Cooldown }
		local buffs = {
			Heal = { 0, 12 }, Shield = { 6, 12 }, Rally = { 8, 12 }, Haste = { 8, 12 }, Water = { 5, 15 }, Flame = { 8, 15 },
			Frost = { 8, 15 }, Nature = { 10, 15 }, Earth = { 8, 15 }, Storm = { 8, 15 }, Celestial = { 6, 15 }, Shadow = { 8, 15 },
		}
		for kind, want in pairs(buffs) do
			T.check(BU[kind].Seconds == want[1] and BU[kind].Cooldown == want[2], "afx timers: Buffs." .. kind .. " unchanged", fmt("%s / %s", tostring(BU[kind].Seconds), tostring(BU[kind].Cooldown)))
		end
		T.check(BC.Damage.CastSeconds == 0.5, "afx timers: Damage.CastSeconds unchanged", tostring(BC.Damage.CastSeconds))
		T.check(BC.Fighter.ElementCooldown == 7, "afx timers: Fighter.ElementCooldown unchanged", tostring(BC.Fighter.ElementCooldown))
	end)

	-- "rb": Windows text mode stops at byte 0x1A
	local function readFile(rel)
		for _, prefix in ipairs({ "", "../", "nimbus-climb/" }) do
			local fh = io.open(prefix .. rel, "rb")
			if fh then
				local src = fh:read("*a")
				fh:close()
				return src
			end
		end
		return nil
	end

	-- the player's guide and the tools guide say what this spec changed
	S.afx_docs = guarded("afx_docs", function()
		local readme = readFile("README.md")
		local tools = readFile("tools/README.md")
		if not T.check(readme ~= nil and tools ~= nil, "afx docs: README.md and tools/README.md load") then
			return
		end
		local from = readme:find("### Evolution: the EVOLVE button", 1, true)
		local to = from and readme:find("\n### ", from + 1, true)
		local evolution = from and readme:sub(from, to or #readme) or ""
		T.check(evolution:find("Reach +15%", 1, true) ~= nil and evolution:find("+30%", 1, true) ~= nil, "afx docs: the README's Evolution section says Reach +15% and +30%")
		T.check(readme:find("camera kick", 1, true) ~= nil, "afx docs: the README names the camera kick")
		for _, name in ipairs({ "smoke_afx_reach.lua", "smoke_afx_impact.lua", "smoke_afx_linger.lua" }) do
			T.check(tools:find(name, 1, true) ~= nil, "afx docs: tools/README.md names " .. name)
		end
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

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	-- a MeshLibrary stand-in whose vfx_* cores are all ready (smoke_p7vfx_client's fakeMeshLibrary)
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
				p.Size = Vector3.new(2, 2, 2)
				p.Anchored = true
				p.Parent = m
				return m
			end,
		}
	end

	-- a recorded Duel fed to the client, the client_p7vfx_storm fixture: my pet (`petId` at `evo`) against standing frogs at `spots`
	local function duel(Sim, id, petId, evo, spots)
		local me = LocalPlayer.UserId
		local frogs = {}
		for i = 1, #spots do
			frogs[i] = { PetId = "puddle_frog", Key = "puddle_frog", Level = 20, Tier = "Normal", Slot = i }
		end
		local sim = Sim.new({ Mode = "Duel", Seed = 23, Id = id, Zone = { X = 90, Z = 90 }, TimeLimit = 300,
			Teams = { { Owner = me, Side = 1, Pets = { { PetId = petId, Key = petId, Level = 50, Tier = "Normal", Slot = 1, Evo = evo } } },
				{ Owner = "frogs", Side = 2, Npc = true, Specials = false, Pets = frogs } } })
		local mine, foes = nil, {}
		for _, u in ipairs(sim.units) do
			u.maxHp, u.hp = 1e7, 1e7
			if u.side == 1 then
				mine = u
				u.x, u.z = 0, 0
			else
				foes[#foes + 1] = u
				local p = spots[#foes]
				u.x, u.z, u.moveSpeed = p[1], p[2], 0
			end
		end
		local start = sim:Describe()
		start.BattleId = id
		start.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(start.Zone.X, 30, start.Zone.Z), X = start.Zone.X, Z = start.Zone.Z }
		start.Names = { [tostring(me)] = LocalPlayer.Name }
		start.Side, start.Spectator, start.T = 1, false, sim:Time()
		local team = sim:TeamOf(me)
		if team then
			start.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
				Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = {} } }
		end
		LocalPlayer:SetAttribute("InBattle", id)
		KC.toClient("BattleState", "Start", start, id)
		local last = {}
		local function step(dt)
			local evs = sim:Step(dt)
			if #evs > 0 then
				KC.toClient("BattleState", "Events", evs, id)
			end
			local snap = sim:SnapshotDelta(last)
			snap.BattleId = id
			KC.toClient("BattleState", "Snapshot", snap, id)
			for _ = 1, math.max(1, math.floor(dt * 30 + 0.5)) do
				Mock.Step(1 / 30)
			end
			return evs
		end
		for _ = 1, 10 do
			step(0.1)
		end
		return sim, mine, foes, step
	end

	local function endDuel(id)
		KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
			Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0 } }, id)
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
	end

	-- a melee Epic+ fighter with no signature of its own (a signature re-points the kind's layers): evolves twice
	local function plainPet(PC, Cat, BCat)
		for _, def in ipairs(PC.Pets) do
			if def.Rarity == "Epic" and not Cat.Signatures[def.Id] and def.Role ~= "Economy" and not def.EventOnly and BCat.ProfileOf(def).Attack == "Melee" then
				return def.Id
			end
		end
		return nil
	end

	S.client_afx_reach_draw = guarded("client_afx_reach_draw", function()
		local BC = moduleAt("client", "Controllers/BattleController")
		local AF = moduleAt("client", "Controllers/AttackFx")
		local Sim = moduleAt("shared", "BattleSim")
		local BCat = moduleAt("shared", "BattleCatalog")
		local PC = moduleAt("shared", "PetCatalog")
		local Cat = moduleAt("shared", "AttackFxCatalog")
		if not T.check(BC ~= nil and AF ~= nil and Sim ~= nil and BCat ~= nil and PC ~= nil and Cat ~= nil, "afx draw: the modules load") then
			return
		end
		local petId = plainPet(PC, Cat, BCat)
		if not T.check(petId ~= nil, "afx draw: a melee Epic fighter with no signature") then
			return
		end
		local err0 = #Mock.Errors
		AF.ClearAll()
		AF._Deps({ MeshLibrary = fakeMeshLibrary() })
		AF.SetQuality("High")

		local function battle(id, evo, spots)
			return duel(Sim, id, petId, evo, spots)
		end
		-- send one event, run frames until the caster's effect plays: the live effect
		local function played(id, mine, ev)
			AF.ClearAll()
			KC.toClient("BattleState", "Events", { ev }, id)
			for _ = 1, 60 do
				Mock.Step(1 / 30)
				for _, e in ipairs(AF._Live()) do
					if e.Unit == mine.id and (e.Recipe.Attack == "Special" or e.Recipe.Attack == "Element") then
						return e
					end
				end
			end
			return nil
		end
		local function itemOf(eff, pred)
			for _, it in ipairs(eff and eff.Items or {}) do
				if pred(it) then
					return it
				end
			end
			return nil
		end
		local function ringLayer(name)
			return function(it)
				return it.Layer ~= nil and it.Layer.Id == name
			end
		end
		local function peak(it)
			return it and it.To * it.Base.X * it.S / 2 or nil
		end
		local function special(mine, foe, kind, extra)
			local ev = { type = "Special", unit = mine.id, kind = kind, name = kind, x = mine.x, z = mine.z, tx = foe.x, tz = foe.z, target = foe.id, targets = { foe.id } }
			for k, v in pairs(extra or {}) do
				ev[k] = v
			end
			return ev
		end

		local id = "afx_reach_draw_2"
		local _, mine2, foes2, step2 = battle(id, 2, { { 10, 0 } })
		-- a) Blast
		local eff = played(id, mine2, special(mine2, foes2[1], "Blast", { r = 9.1 }))
		local wave = itemOf(eff, ringLayer("Blastwave"))
		T.check(eff ~= nil and near(eff.Reach, 9.1, 1e-6), "afx draw: a Blast's effect reaches the event's r", eff and tostring(eff.Reach))
		T.check(wave ~= nil and near(peak(wave), 9.1, 0.05) and wave.From <= wave.To * 0.3 + 1e-6, "afx draw: the Blastwave ground ring peaks at 9.1 studs", wave and tostring(peak(wave)))
		-- the dome stays ~1.5 x a pet (the target stays visible inside it)
		local dome = itemOf(eff, ringLayer("Dome"))
		T.check(dome ~= nil and near(dome.To, 1.5, 1e-6), "afx draw: the Blast dome keeps its Grow", dome and tostring(dome.To))
		-- Freeze: the ground ring shows the real radius
		eff = played(id, mine2, special(mine2, foes2[1], "Freeze", { r = 7.8 }))
		local frost = itemOf(eff, ringLayer("FrostReach"))
		T.check(eff ~= nil and near(eff.Reach, 7.8, 1e-6) and frost ~= nil and near(peak(frost), 7.8, 0.05), "afx draw: Freeze's FrostReach ring peaks at its 7.8 radius", frost and tostring(peak(frost)))
		-- b) Beam
		eff = played(id, mine2, special(mine2, foes2[1], "Beam", { length = 29.9, width = 4.6, angle = 0 }))
		local core = itemOf(eff, function(it)
			return it.Line ~= nil and it.Thick ~= nil
		end)
		T.check(eff ~= nil and core ~= nil and core.Line == true and near(eff.Reach, 29.9, 1e-6) and near(eff.WidthScale, 1.15, 1e-6), "afx draw: the Beam core stretches as a Line to the event's length, wider by the event's width",
			eff and fmt("reach %s, width scale %s", tostring(eff.Reach), tostring(eff.WidthScale)))
		local plainThick = core and core.Thick / 1.15
		eff = played(id, mine2, special(mine2, foes2[1], "Beam", { length = 26, width = 4, angle = 0 }))
		core = itemOf(eff, function(it)
			return it.Line ~= nil and it.Thick ~= nil
		end)
		T.check(core ~= nil and near(core.Thick, plainThick, 1e-6) and near(eff.WidthScale, 1, 1e-6), "afx draw: ...and an unevolved Beam's width scale is 1", core and tostring(core.Thick))
		-- the drawn end is really at the reach, past the target 10 studs off: the core's part, stepped through the beam's hold
		eff = played(id, mine2, special(mine2, foes2[1], "Beam", { length = 29.9, width = 4.6, angle = 0 }))
		core = itemOf(eff, function(it)
			return it.Line ~= nil and it.Thick ~= nil
		end)
		local farthest = 0
		for _ = 1, 45 do
			Mock.Step(1 / 30)
			local part = core and core.Kit and core.Kit.Root
			if part and part.Transparency < 1 then
				local tip = part.Position + part.CFrame.LookVector * (part.Size.Z / 2)
				local gap = tip - eff.S
				farthest = max(farthest, (gap.X * gap.X + gap.Z * gap.Z) ^ 0.5)
			end
		end
		T.check(near(farthest, 29.9, 0.3), "afx draw: the Beam's drawn end is its real length from the caster, through the target", tostring(farthest))
		-- c) Elements
		local function element(mine, foe, name, shape, extra)
			local ev = { type = "Element", unit = mine.id, element = name, name = name, x = mine.x, z = mine.z, angle = 0, tx = foe.x, tz = foe.z, shape = shape, targets = { foe.id } }
			for k, v in pairs(extra or {}) do
				ev[k] = v
			end
			return ev
		end
		eff = played(id, mine2, element(mine2, foes2[1], "Flame", "Cone", { length = 18.2 }))
		T.check(eff ~= nil and near(eff.Reach, 18.2, 1e-6) and eff.Area == "Cone", "afx draw: an Element Cone reaches the event's length", eff and tostring(eff.Reach))
		eff = played(id, mine2, element(mine2, foes2[1], "Earth", "Circle", { r = 10.4 }))
		T.check(eff ~= nil and near(eff.Reach, 10.4, 1e-6) and eff.Area == "Circle", "afx draw: an Element Circle reaches the event's r", eff and tostring(eff.Reach))
		eff = played(id, mine2, element(mine2, foes2[1], "Storm", "Line", { length = 31.2, width = 5.2 }))
		T.check(eff ~= nil and near(eff.Reach, 31.2, 1e-6) and eff.Area == "Line" and near(eff.WidthScale, 1.3, 1e-6), "afx draw: an Element Line reaches the event's length and width", eff and fmt("%s, %s", tostring(eff.Reach), tostring(eff.WidthScale)))
		-- d) Review Focus 2: an old event with no numbers on a unit at Evo 2: catalog x reach, never nil, never a 0 ring
		eff = played(id, mine2, special(mine2, foes2[1], "Blast"))
		wave = itemOf(eff, ringLayer("Blastwave"))
		T.check(eff ~= nil and near(eff.Reach, 7 * 1.3, 1e-6) and wave ~= nil and near(peak(wave), 7 * 1.3, 0.05), "afx draw: an old Blast event with no r on an Evo 2 unit draws 7 x 1.3", eff and tostring(eff.Reach))
		eff = played(id, mine2, special(mine2, foes2[1], "Beam", { angle = 0 }))
		T.check(eff ~= nil and near(eff.Reach, 26 * 1.3, 1e-6) and near(eff.WidthScale, 1.3, 1e-6), "afx draw: ...an old Beam 26 x 1.3 by 4 x 1.3", eff and tostring(eff.Reach))
		eff = played(id, mine2, element(mine2, foes2[1], "Flame", "Cone"))
		T.check(eff ~= nil and near(eff.Reach, 14 * 1.3, 1e-6), "afx draw: ...an old Cone 14 x 1.3", eff and tostring(eff.Reach))
		eff = played(id, mine2, element(mine2, foes2[1], "Storm", "Line"))
		T.check(eff ~= nil and near(eff.Reach, 24 * 1.3, 1e-6), "afx draw: ...an old Line 24 x 1.3", eff and tostring(eff.Reach))
		eff = played(id, mine2, element(mine2, foes2[1], "Earth", "Circle"))
		T.check(eff ~= nil and near(eff.Reach, 8 * 1.3, 1e-6), "afx draw: ...an old Circle 8 x 1.3", eff and tostring(eff.Reach))
		eff = played(id, mine2, special(mine2, foes2[1], "Blast", { r = 0 }))
		T.check(eff ~= nil and near(eff.Reach, 7 * 1.3, 1e-6), "afx draw: ...a 0 r on an event is no ring: catalog x reach", eff and tostring(eff.Reach))
		endDuel(id)

		id = "afx_reach_draw_0"
		local _, mine0, foes0 = battle(id, 0, { { 10, 0 } })
		eff = played(id, mine0, special(mine0, foes0[1], "Blast"))
		T.check(eff ~= nil and eff.Reach == 7, "afx draw: ...on an Evo 0 unit, the catalog's 7", eff and tostring(eff.Reach))
		eff = played(id, mine0, special(mine0, foes0[1], "Pounce", { range = 30 }))
		T.check(eff ~= nil and eff.Reach == 9, "afx draw: a Pounce has no drawn area: Reach keeps its default", eff and tostring(eff.Reach))
		endDuel(id)

		-- a real unevolved cast with no numbers on its events: drawn at the catalog's; a ranged fighter's element at its own range
		id = "afx_reach_draw_ranged"
		local _, mine5, foes5 = duel(Sim, id, "ember_phoenix", 0, { { 10, 0 } })
		eff = played(id, mine5, element(mine5, foes5[1], "Flame", "Cone"))
		T.check(mine5.ranged == true and eff ~= nil and near(eff.Reach, max(14, mine5.range), 1e-6), "afx draw: an unevolved ranged fighter's Cone with no number is drawn out to its own range", eff and tostring(eff.Reach))
		endDuel(id)

		-- e) the cube path (AF.Play forced false)
		id = "afx_reach_draw_cube"
		local _, mine3, foes3, step3 = battle(id, 2, { { 10, 0 } })
		AF._Deps({ TextureIds = {} })
		-- (the cubes play on the render clock: the snapshots carry it on)
		local function settle()
			for _ = 1, 30 do
				step3(1 / 30)
			end
		end
		local function cubeRing(size, ev)
			local fx = workspace:FindFirstChild("ClientBattle") and workspace.ClientBattle:FindFirstChild("Fx")
			KC.toClient("BattleState", "Events", { ev }, id)
			local best = 0
			for _ = 1, 45 do
				step3(1 / 30)
				local parts = {}
				for _, d in ipairs(fx and fx:GetDescendants() or {}) do
					if d:IsA("BasePart") and d.Transparency < 1 and near(d.Size.X, size, 1e-6) and near(d.Size.Y, size * 0.6, 1e-6) and near(d.Size.Z, size, 1e-6) then
						parts[#parts + 1] = d.Position
					end
				end
				if #parts >= 8 then
					local cx, cz = 0, 0
					for _, p in ipairs(parts) do
						cx, cz = cx + p.X / #parts, cz + p.Z / #parts
					end
					for _, p in ipairs(parts) do
						local dx, dz = p.X - cx, p.Z - cz
						best = max(best, (dx * dx + dz * dz) ^ 0.5)
					end
				end
			end
			return best
		end
		local function cubeBeam(ev)
			local fx = workspace:FindFirstChild("ClientBattle") and workspace.ClientBattle:FindFirstChild("Fx")
			KC.toClient("BattleState", "Events", { ev }, id)
			local long, thick = 0, 0
			for _ = 1, 12 do
				step3(1 / 30)
				for _, d in ipairs(fx and fx:GetDescendants() or {}) do
					if d:IsA("BasePart") and d.Transparency < 1 and d.Size.Z >= long then
						long, thick = d.Size.Z, max(d.Size.X, thick) -- (its glow part is the wide one)
					end
				end
			end
			return long, thick
		end
		-- (a part of the Blast's cube ring: Fx.Ring(c, r, color, 20, 0.8, ...); the Freeze's 0.7)
		local wide = cubeRing(0.8, special(mine3, foes3[1], "Blast", { r = 9.1 }))
		T.check(near(wide, 9.1, 0.5), "afx draw: the cube Blast ring for an event r = 9.1 runs out to 9.1 (18.2 wide)", tostring(wide))
		settle()
		wide = cubeRing(0.8, special(mine3, foes3[1], "Blast"))
		T.check(near(wide, 7 * 1.3, 0.5), "afx draw: ...an old Blast event on an Evo 2 unit: 7 x 1.3", tostring(wide))
		settle()
		wide = cubeRing(0.7, special(mine3, foes3[1], "Freeze", { r = 7.8, stunned = {} }))
		T.check(near(wide, 7.8, 0.5), "afx draw: the cube Freeze ring runs out to its 7.8", tostring(wide))
		settle()
		local long, thick = cubeBeam(special(mine3, foes3[1], "Beam", { length = 29.9, width = 4.6, angle = 0 }))
		T.check(near(long, 29.9, 1e-6) and thick > 4 * 0.7, "afx draw: the cube Beam draws the event's length and width", fmt("%s x %s", tostring(long), tostring(thick)))
		settle()
		wide = cubeRing(0.8, { type = "Element", unit = mine3.id, element = "Earth", name = "Quake", x = mine3.x, z = mine3.z, angle = 0, tx = foes3[1].x, tz = foes3[1].z, shape = "Circle", targets = { foes3[1].id }, r = 10.4 })
		T.check(near(wide, 10.4, 0.5), "afx draw: the cube element Circle runs out to the event's r", tostring(wide))
		settle()
		long = cubeBeam({ type = "Element", unit = mine3.id, element = "Storm", name = "Bolt", x = mine3.x, z = mine3.z, angle = 0, tx = foes3[1].x, tz = foes3[1].z, shape = "Line", targets = { foes3[1].id }, length = 31.2, width = 5.2 })
		T.check(near(long, 31.2, 1e-6), "afx draw: the cube element Line draws the event's length", tostring(long))
		AF._Deps({ TextureIds = false })
		endDuel(id)

		-- f) a REAL evolved Storm: the sim's own events; the effect lands on exactly the enemies the wider zone hits, and the
		-- effect's targets are gathered at the real radius (one frog in by its edge of the 7.8 zone, out of a 6 one)
		id = "afx_reach_draw_storm"
		local sim, mine, foes, step = duel(Sim, id, "obsidian_phoenix", 2, { { 12, 0 }, { 12, 7.8 }, { 12, -(7.8 + 3 + 1.5) } })
		local rad = foes[1].radius
		foes[2].z = 7.8 + 0.6 * rad
		foes[3].z = -(7.8 + rad + 1.5)
		mine.meter, mine.castUntil, mine.nextAttack = 100, 0, 0
		sim:Command(LocalPlayer.UserId, "Target", foes[1].id)
		sim:Command(LocalPlayer.UserId, "Special")
		local fx, hit, zoneEv = nil, {}, nil
		local evs = step(0.1)
		for _ = 1, 8 do
			for _, ev in ipairs(evs) do
				if ev.type == "Hit" and ev.zone and ev.from == mine.id then
					hit[tonumber(ev.to)] = true
				elseif ev.type == "Zone" then
					zoneEv = ev
				end
			end
			for _, e in ipairs(AF._Live()) do
				if e.Unit == mine.id and e.Recipe.Attack == "Special" then
					fx = e
				end
			end
			evs = step(0.1)
		end
		local units = {}
		for _, side in ipairs(fx and fx.Targets or {}) do
			units[side.Unit] = true
		end
		T.check(zoneEv ~= nil and near(zoneEv.r, 7.8, 1e-6) and fx ~= nil and near(fx.Reach, 7.8, 1e-6), "afx draw: a real Evo 2 Storm: Zone r and the effect's Reach are 7.8", fx and tostring(fx.Reach))
		T.check(units[foes[1].id] == true and units[foes[2].id] == true and units[foes[3].id] == nil and hit[foes[2].id] == true and hit[foes[3].id] == nil,
			"afx draw: the effect lands on exactly the frogs the zone hits: the one in by its edge of 7.8, not the one past it")
		-- the rain of a plain Storm covers the real zone: the falling pieces spread over eff.Reach
		endDuel(id)
		id = "afx_reach_draw_rain"
		local _, mine4, foes4 = battle(id, 2, { { 10, 0 } })
		eff = played(id, mine4, special(mine4, foes4[1], "Storm", { r = 7.8 }))
		local widest = 0
		for _, it in ipairs(eff and eff.Items or {}) do
			if it.OffR and it.OffD and it.Drop then
				widest = max(widest, (it.OffR * it.OffR + it.OffD * it.OffD) ^ 0.5)
			end
		end
		T.check(eff ~= nil and widest > 0 and widest <= 7.8 + 1e-6 and widest > (0.4 + 2.6) * eff.Size, "afx draw: a Storm's falling pieces spread over its real radius", tostring(widest))
		endDuel(id)

		AF._Deps({ MeshLibrary = false })
		AF.SetQuality(nil)
		T.check(#Mock.Errors == err0 and AF.Stats().Live == 0, "afx draw: no errors, nothing left live")
		KC.flushErrors("client_afx_reach_draw")
	end)

	S.client_afx_reach_detail = guarded("client_afx_reach_detail", function()
		local PCtl = (KC.M and KC.M.PetsController) or moduleAt("client", "Controllers/PetsController")
		local MC = (KC.M and KC.M.MenuController) or moduleAt("client", "Controllers/MenuController")
		if not T.check(PCtl ~= nil and MC ~= nil, "afx detail: PetsController and MenuController load") then
			return
		end
		-- pip_penguin L25 stage 1 (the smoke_tb_pets fixture), stormfang stage 2, pebble_pup stage 0
		local EVOLVED, TWICE, PLAIN = "pip_penguin", "stormfang", "pebble_pup"
		local Config = moduleAt("shared", "Config")
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		local pets = { [EVOLVED] = 1, [TWICE] = 1, [PLAIN] = 1 }
		KC.toClient("ProfileSync", {
			Tokens = 900, Pets = pets, Equipped = { PLAIN }, Items = {}, Discovered = pets, IndexClaimed = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 500000, Gems = 50, Berries = 2000,
			PetLevels = { [EVOLVED] = { Level = 25, Xp = 0 }, [TWICE] = { Level = 60, Xp = 0 }, [PLAIN] = { Level = 2, Xp = 0 } },
			PetGrowth = { [EVOLVED] = { Evo = 1 }, [TWICE] = { Evo = 2 } },
			Teams = { Presets = { { PLAIN }, {}, {} }, Active = 1, Slots = 3 },
		})
		KC.advance(0.5)
		local function perkText(key)
			MC.Open("Pets", { Key = key })
			KC.advance(1.5)
			local gui = LocalPlayer.PlayerGui:FindFirstChild("NimbusPets")
			local perks = nil
			for _, d in ipairs(gui and gui:GetDescendants() or {}) do
				if d.Name == "Perks" then
					perks = d
				end
			end
			local text = perks and tostring(perks.Text) or ""
			MC.Close()
			KC.advance(0.4)
			return text
		end
		local one, two, none = perkText(EVOLVED), perkText(TWICE), perkText(PLAIN)
		T.check(one:find("Reach +15%", 1, true) ~= nil, "afx reach: the Pets detail of an evolved pet says Reach +15%", one)
		T.check(two:find("Reach +30%", 1, true) ~= nil, "afx reach: ...of a pet evolved twice, Reach +30%", two)
		T.check(none:find("Reach", 1, true) == nil, "afx reach: ...and nothing at stage 0", none)
		-- the Reach line sits right after the special's line
		T.check(one:find("^Special: [^\n]+\nReach %+15%%") ~= nil, "afx reach: the Reach line comes right after the Special line", one)
		KC.flushErrors("client_afx_reach_detail")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
