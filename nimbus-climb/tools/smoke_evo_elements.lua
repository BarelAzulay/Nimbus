-- smoke_evo_elements.lua: every element attack's evolved forms in the sim (docs/superpowers/specs/2026-11-01-evolved-forms-design.md; plan Task 2), loaded
-- by tools/smoke.py in the server world, pure:
--   evo_el_names          BattleCatalog.ElementAttacks[e].Forms / ElementFormOf (later field wins, stage 2 keeps stage 1), the names on unitInfo and the event
--   evo_el_water          Riptide's slow, Maelstrom: the same cone again at the original point
--   evo_el_flame          Wildfire's burn, Inferno's burning ground (never past the cone's own end)
--   evo_el_frost          Deep Frost's slow, Ice Snare's mark (one status with the Beam's: strongest wins)
--   evo_el_nature         Bramble Lash's leech, Worldroot's root
--   evo_el_earth          Fissure at 0.5 s, Rockspire's ring at 1.0 s, the Quake's stun unchanged
--   evo_el_storm          Forked Bolt's jump, a lone enemy struck again ONCE, Thunder Lance's second jump and meter
--   evo_el_celestial      Halo's meter, Starfall's heal
--   evo_el_shadow         Hollow Rend's weaken (the strongest stands), Soul Rend's leech
--   evo_el_ranged_circle  a ranged pet's Circle on its aim point, at stage 0 too (at most its range away); melee, Cones and Lines keep today's rule
--   evo_el_boss           a boss keeps its immunities: a bonus hit instead; every timed twist lands on it, Ice Snare marks it
--   evo_el_form_dps       what a boss's HP counts for a fighter's forms (BattleCatalog.FormDps): x1 at stage 0; a hybrid counts by
--                         its real stage, exactly like the plain pet (the owner's answer of 2026-11-02)
-- White-box: reaches into battle.units / battle.teams (same Lua state). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local abs, floor, huge, sqrt = math.abs, math.floor, math.huge, math.sqrt
local fmt = string.format

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

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
end

local function r1(n)
	return floor(n * 10 + 0.5) / 10
end

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

local function hitsOn(events, id, pred)
	local out = {}
	for _, ev in ipairs(events) do
		if ev.type == "Hit" and ev.to == id and not ev.miss and (pred == nil or pred(ev)) then
			out[#out + 1] = ev
		end
	end
	return out
end

local function twistHits(events, id, name)
	return hitsOn(events, id, function(ev)
		return ev.twist == name
	end)
end

local function bonusHits(events, id)
	return hitsOn(events, id, function(ev)
		return ev.bonus == true
	end)
end

local function dealt(list)
	local sum = 0
	for _, ev in ipairs(list) do
		sum = sum + ev.dmg + (ev.absorbed or 0)
	end
	return sum
end

local function twists(events, name)
	local out = {}
	for _, ev in ipairs(events) do
		if ev.type == "Twist" and ev.twist == name then
			out[#out + 1] = ev
		end
	end
	return out
end

local function run(b, seconds, into)
	into = into or {}
	for _ = 1, floor(seconds / 0.05 + 0.5) do
		for _, ev in ipairs(b:Step(0.05)) do
			into[#into + 1] = ev
		end
	end
	return into
end

-- a unit that stands, hits nothing by itself, and has HP past every cap
local function stand(u, x, z)
	u.x, u.z, u.px, u.pz, u.moveSpeed = x, z, x, z, 0
	u.maxHp, u.hp = 1e7, 1e7
	u.nextAttack = huge
end

local function standFighter(team, x, z)
	local f = team.fighter
	stand(f, x, z)
	team.wantX, team.wantZ = x, z
	team.noEngage = true
	return f
end

-- a Duel on a wide floor: my fighter at the origin, one standing bear per spot. opts: Ally (an entry of a second player team on side 1, at { 0, 40 })
local function field(BS, entry, spots, opts)
	opts = opts or {}
	local foes = {}
	for i = 1, #spots do
		foes[i] = { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = i }
	end
	entry.Slot = 1
	local teams = { { Owner = 1, Side = 1, Pets = { entry } }, { Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = foes } }
	if opts.Ally then
		opts.Ally.Slot = 1
		teams[3] = { Owner = 2, Side = 1, Pets = { opts.Ally } }
	end
	local b = BS.new({ Mode = "Duel", Seed = opts.Seed or 7, Zone = { X = 160, Z = 160 }, TimeLimit = 300, Teams = teams })
	if not b then
		return nil
	end
	local f = standFighter(b.teams[1], 0, 0)
	if opts.Ally then
		standFighter(b.teams[3], 0, 40)
	end
	local on = {}
	for _, u in ipairs(b.units) do
		if u.side == 2 then
			on[#on + 1] = u
			local p = spots[#on]
			stand(u, p[1], p[2])
		end
	end
	return b, f, on
end

-- a Raid: my fighter at the origin, the boss at { x, 0 }, its own attacks off and its HP past every wave and the enrage
local function raid(BS, entry, x)
	entry.Slot = 1
	local b = BS.new({ Mode = "Raid", Seed = 7, Boss = "storm_titan", RaidTier = "High", Zone = { X = 160, Z = 160 }, TimeLimit = 600, Teams = { { Owner = 1, Side = 1, Pets = { entry } } } })
	if not b then
		return nil
	end
	local f = standFighter(b.teams[1], 0, 0)
	local boss = b.boss
	boss.x, boss.z, boss.px, boss.pz = x, 0, x, 0
	boss.maxHp, boss.hp = 1e9, 1e9
	boss.attacks, boss.lethal, boss.nextAttack = {}, nil, huge
	return b, f, boss
end

-- my team's fighter casts its element attack at `aim`: the Element event, every event, the battle time before the cast
local function cast(b, f, aim, owner)
	local t0 = b:Time()
	local ok, why = b:Command(owner or 1, "Element", aim)
	local evs = b:Step(0.05)
	return findEvent(evs, "Element", function(ev)
		return ev.unit == f.id
	end), evs, t0, ok, why
end

-- the element hit before variance and the wheel
local function hitOf(BC, f)
	return f.hit * BC.Fighter.ElementMult
end

local function onFoe(amount, foe, hit)
	return amount * ((hit and hit.elem) or 1) * (1 - (foe.defense or 0))
end

-- a variance-free share of one element hit lands near `share`: within the variance when a hit carries it
local function landed(BC, f, foe, hit, share, tol)
	return hit ~= nil and near((hit.dmg + (hit.absorbed or 0)) / onFoe(hitOf(BC, f) * share, foe, hit), 1, tol or 0.25)
end

local MELEE, RANGED = "sunbeam_bear", "ember_phoenix" -- Legendaries: both evolve twice
local RANGED_SHORT = "nebula_axolotl" -- evolves twice, range 12: its Circle's radius is its range at every stage (max(8 x 1.3, 12))

local function melee(PC, element, evo)
	return { Def = cloneDef(PC, MELEE, { Element = element, Elements = { element } }), Key = MELEE, Level = 50, Evo = evo }
end

local function ranged(PC, element, evo, petId)
	petId = petId or RANGED
	return { Def = cloneDef(PC, petId, { Element = element, Elements = { element } }), Key = petId, Level = 50, Evo = evo }
end

local function modules()
	local BC, BS, PC = req("BattleCatalog"), req("BattleSim"), req("PetCatalog")
	return BC, BS, PC, BC ~= nil and BS ~= nil and PC ~= nil and type(BC.ElementFormOf) == "function"
end

local function infoOf(b, f)
	for _, info in ipairs(b:StaticUnits()) do
		if info.id == f.id then
			return info
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- the catalog
----------------------------------------------------------------------------------------------------
-- the spec's "Normal abilities" table, verbatim
local SPEC_NAMES = {
	Water = { "Tide Burst", "Riptide", "Maelstrom" },
	Flame = { "Flare", "Wildfire", "Inferno" },
	Frost = { "Frostbite", "Deep Frost", "Ice Snare" },
	Nature = { "Thorn Lash", "Bramble Lash", "Worldroot" },
	Earth = { "Quake", "Fissure", "Rockspire" },
	Storm = { "Bolt", "Forked Bolt", "Thunder Lance" },
	Celestial = { "Radiance", "Halo", "Starfall" },
	Shadow = { "Void Rend", "Hollow Rend", "Soul Rend" },
}

S.evo_el_names = guarded("evo_el_names", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el: ElementFormOf exists") then
		return
	end
	local tally = T.tally("evo el: every element's forms carry the spec's names, stage 0 keeps today's")
	for element, names in pairs(SPEC_NAMES) do
		local a = BC.ElementAttacks[element]
		tally:case(a.Name == names[1] and #a.Forms == 2 and a.Forms[1].Name == names[2] and a.Forms[2].Name == names[3] and type(a.Forms[1].Id) == "string" and type(a.Forms[2].Id) == "string", element)
		tally:case(BC.ElementFormOf(element, 0) == nil and BC.ElementFormOf(element, 1).Name == names[2] and BC.ElementFormOf(element, 2).Name == names[3], element .. " by stage")
	end
	tally:report()
	T.check(BC.ElementFormOf("Nope", 1) == nil and BC.ElementFormOf("Water", "x") == nil and BC.ElementFormOf(nil, 1) == nil and BC.ElementFormOf("Water", 0 / 0) == nil and BC.ElementFormOf("Water", 0.9) == nil, "evo el: stage 0 / junk = nil")
	T.check(BC.ElementFormOf("Water", 1).Maelstrom == nil and BC.ElementFormOf("Water", 7).Maelstrom ~= nil and BC.ElementFormOf("Water", 1.9).Maelstrom == nil, "evo el: the stage is floored and clamped to 2")
	-- field-wise merge: a later stage's same field wins, stage 2 keeps stage 1
	local water = BC.ElementFormOf("Water", 2)
	T.check(water.Slow == 0.8 and water.Seconds == 2 and water.Share == 0.5 and water.Delay == 0.5 and water.Riptide ~= nil and water.Maelstrom ~= nil, "evo el: Water at stage 2 keeps Riptide's slow and adds the wave")
	T.check(BC.ElementFormOf("Storm", 1).Jumps == 1 and BC.ElementFormOf("Storm", 2).Jumps == 2 and BC.ElementFormOf("Storm", 2).Share == 0.3 and BC.ElementFormOf("Storm", 2).Meter == 3, "evo el: the later field wins (Thunder Lance's two jumps)")
	local earth = BC.ElementFormOf("Earth", 2)
	T.check(earth.Fissure.Delay == 0.5 and earth.Rockspire.Delay == 1.0 and earth.Rockspire.Band == 4, "evo el: each twist keeps its own numbers (Earth's two delays)")
	local ids = BC.ElementFormOf("Frost", 2).Ids
	T.check(type(ids) == "table" and #ids == 2 and ids[1] == "DeepFrost" and ids[2] == "IceSnare", "evo el: Ids lists the twists in order", ids and table.concat(ids, ","))
	-- the numbers of the spec's table
	local F = function(element, stage)
		return BC.ElementAttacks[element].Forms[stage]
	end
	T.check(F("Water", 1).Slow == 0.8 and F("Water", 1).Seconds == 2 and F("Water", 2).Share == 0.5 and F("Water", 2).Delay == 0.5, "evo el: Water's numbers")
	T.check(F("Flame", 1).BurnShare == 0.35 and F("Flame", 2).Share == 0.45 and F("Flame", 2).Seconds == 2 and F("Flame", 2).Radius == 5, "evo el: Flame's numbers")
	T.check(F("Frost", 1).Slow == 0.5 and F("Frost", 2).Mark == 1.10, "evo el: Frost's numbers")
	T.check(F("Nature", 1).Leech == 0.4 and F("Nature", 2).Root == 0.4, "evo el: Nature's numbers")
	T.check(F("Earth", 1).Share == 0.4 and F("Earth", 1).Delay == 0.5 and F("Earth", 2).Share == 0.4 and F("Earth", 2).Delay == 1.0 and F("Earth", 2).Band == 4, "evo el: Earth's numbers")
	T.check(F("Storm", 1).Share == 0.3 and F("Storm", 1).Jumps == 1 and F("Storm", 1).Reach == 10 and F("Storm", 2).Jumps == 2 and F("Storm", 2).Meter == 3, "evo el: Storm's numbers")
	T.check(F("Celestial", 1).MeterGain == 20 and F("Celestial", 2).Heal == 0.08, "evo el: Celestial's numbers")
	T.check(F("Shadow", 1).Weaken == 0.8 and F("Shadow", 2).Leech == 0.15, "evo el: Shadow's numbers")
	-- stage 0's base numbers never moved
	T.check(BC.ElementAttacks.Flame.Burn.Share == 0.25 and BC.ElementAttacks.Frost.Slow.Mult == 0.6 and BC.ElementAttacks.Frost.Slow.Seconds == 4 and BC.ElementAttacks.Nature.Leech == 0.3 and BC.ElementAttacks.Celestial.MeterGain == 15 and BC.ElementAttacks.Shadow.Weaken.Mult == 0.85 and BC.ElementAttacks.Earth.Stun == 0.5, "evo el: the base attacks' numbers stay")
	T.check(BC.Validate() == true, "evo el: Validate passes", select(2, BC.Validate()) and tostring(select(2, BC.Validate())[1]))
	local keep = BC.ElementAttacks.Earth.Forms
	BC.ElementAttacks.Earth.Forms = { keep[1] }
	local gap = BC.Validate()
	BC.ElementAttacks.Earth.Forms = { keep[1], { Id = "NoName" } }
	local noName = BC.Validate()
	BC.ElementAttacks.Earth.Forms = keep
	T.check(gap == false and noName == false, "evo el: Validate catches a missing form and a form with no name")

	-- the names on the wire: unitInfo and the Element event, by the stored stage
	local b, f, foes = field(BS, melee(PC, "Frost", 1), { { 5, 0 } })
	T.check(infoOf(b, f).elementAttack.Name == "Deep Frost" and infoOf(b, f).elementAttack.Element == "Frost" and infoOf(b, f).elementAttack.Shape == "Cone", "evo el: unitInfo.elementAttack.Name at Evo 1", tostring(infoOf(b, f).elementAttack.Name))
	local ev, _, _, ok, name = cast(b, f, foes[1].id)
	T.check(ev ~= nil and ev.name == "Deep Frost" and ev.form == 1 and ok == true and name == "Deep Frost", "evo el: the Element event names the form", ev and tostring(ev.name))
	b, f, foes = field(BS, melee(PC, "Frost", 0), { { 5, 0 } })
	T.check(infoOf(b, f).elementAttack.Name == "Frostbite", "evo el: ...Frostbite at Evo 0", tostring(infoOf(b, f).elementAttack.Name))
	ev = cast(b, f, foes[1].id)
	T.check(ev ~= nil and ev.name == "Frostbite" and ev.form == nil, "evo el: ...and the Evo 0 event has no form field", ev and tostring(ev.name))
	-- a once-evolver with a stored 2 is at its top form; a hybrid evolves too: its element attack takes the element's form name
	b, f, foes = field(BS, { Key = "pebble_pup", Level = 60, Evo = 2 }, { { 5, 0 } })
	T.check(infoOf(b, f).elementAttack.Name == "Fissure", "evo el: a Common with a stored Evo 2 is at its top form", tostring(infoOf(b, f).elementAttack.Name))
	local hybrid = cloneDef(PC, MELEE, { Element = "Water", Elements = { "Water" }, Look = { Species = "Bear", BodyId = MELEE, StyleId = "stormfang" } })
	b, f, foes = field(BS, { Def = hybrid, Key = MELEE, Level = 50, Evo = 1 }, { { 5, 0 } })
	T.check(infoOf(b, f).elementAttack.Name == "Riptide", "evo el: a hybrid at Evo 1 takes the element's form name (Riptide)", tostring(infoOf(b, f).elementAttack.Name))
	b, f, foes = field(BS, { Def = hybrid, Key = MELEE, Level = 50, Evo = 2 }, { { 5, 0 } })
	T.check(infoOf(b, f).elementAttack.Name == "Maelstrom", "evo el: ...at Evo 2: Maelstrom", tostring(infoOf(b, f).elementAttack.Name))
	local evs
	ev, evs = cast(b, f, foes[1].id)
	local slowed = foes[1].slowMult == 0.8 and foes[1].slowUntil > 0
	run(b, 1, evs)
	T.check(ev ~= nil and ev.name == "Maelstrom" and ev.form == 2 and slowed and #twists(evs, "Maelstrom") == 1, "evo el: ...and its cast carries the forms (Riptide's slow, the Maelstrom wave)", ev and fmt("%s %s %d", tostring(ev.name), tostring(ev.form), #twists(evs, "Maelstrom")))
end)

----------------------------------------------------------------------------------------------------
-- Water
----------------------------------------------------------------------------------------------------
S.evo_el_water = guarded("evo_el_water", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el water: the modules load") then
		return
	end
	-- Evo 1: pushed 4 (today) AND slowed
	local b, f, foes = field(BS, melee(PC, "Water", 1), { { 8, 0 } })
	local ev, evs, t0 = cast(b, f, foes[1].id)
	T.check(ev ~= nil and near(foes[1].x, 12, 0.01), "evo el water: the bear is pushed 4 (today)", tostring(foes[1].x))
	T.check(foes[1].slowMult == 0.8 and near(foes[1].slowUntil, t0 + 2, 1e-6), "evo el water: Riptide: 20% slower for 2 s", fmt("%s until +%.2f", tostring(foes[1].slowMult), foes[1].slowUntil - t0))
	run(b, 1, evs)
	T.check(#twists(evs, "Maelstrom") == 0, "evo el water: Evo 1 has no Maelstrom")
	-- Evo 0: no slow
	b, f, foes = field(BS, melee(PC, "Water", 0), { { 8, 0 } })
	cast(b, f, foes[1].id)
	T.check(foes[1].slowUntil == 0 and foes[1].slowMult == 1, "evo el water: Evo 0 pushes, no slow")
	-- Evo 2: the wave comes back in the ORIGINAL cone, the caster having moved
	b, f, foes = field(BS, melee(PC, "Water", 2), { { 6, 0 }, { 6, 3 }, { -8, 0 } })
	ev, evs = cast(b, f, foes[1].id)
	local first = hitsOn(evs, foes[1].id)[1]
	T.check(has(ev.targets, foes[2].id) and not has(ev.targets, foes[3].id), "evo el water: two bears in the cone, one behind")
	T.check(#twists(evs, "Maelstrom") == 0, "evo el water: no wave at the cast")
	f.x, f.z, f.px, f.pz = 0, 30, 0, 30
	b.teams[1].wantX, b.teams[1].wantZ = 0, 30
	foes[2].x, foes[2].px = -40, -40 -- out of the cone before the wave
	local later = run(b, 0.5)
	local tw = twists(later, "Maelstrom")
	T.check(#tw == 1 and tw[1].kind == "Water" and tw[1].x == 0 and tw[1].z == 0 and tw[1].angle == ev.angle and tw[1].length == r1(14 * 1.3) and has(tw[1].targets, foes[1].id), "evo el water: 0.5 s later a Twist Maelstrom at the ORIGINAL point and angle", tw[1] and fmt("%s %s %s %s", tostring(tw[1].x), tostring(tw[1].z), tostring(tw[1].angle), tostring(tw[1].length)))
	local wave = twistHits(later, foes[1].id, "Maelstrom")
	T.check(#wave == 1 and first ~= nil and landed(BC, f, foes[1], wave[1], 0.5) and wave[1].element ~= nil, "evo el water: a second Hit near 0.5 x on the bear still in the cone", wave[1] and tostring(wave[1].dmg))
	T.check(#twistHits(later, foes[2].id, "Maelstrom") == 0 and #twistHits(later, foes[3].id, "Maelstrom") == 0, "evo el water: not on the one that left, nor behind")
	T.check(foes[1].slowMult == 0.8, "evo el water: stage 2 keeps the slow")
	-- the wave pushes nothing: it is the second hit, the first one pushed
	local pushed = foes[1].x
	T.check(near(pushed, 10, 0.01), "evo el water: the wave pushes nothing more", tostring(pushed))
end)

----------------------------------------------------------------------------------------------------
-- Flame
----------------------------------------------------------------------------------------------------
S.evo_el_flame = guarded("evo_el_flame", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el flame: the modules load") then
		return
	end
	-- the burn's whole against the hit: variance-free in the ratio
	local function burnShare(evo)
		local b, f, foes = field(BS, melee(PC, "Flame", evo), { { 5, 0 } })
		local _, evs = cast(b, f, foes[1].id)
		run(b, 3.3, evs)
		local hit = hitsOn(evs, foes[1].id, function(h)
			return h.element ~= nil
		end)[1]
		local burn = hitsOn(evs, foes[1].id, function(h)
			return h.burn == true
		end)
		return dealt(burn) / hit.dmg / (hit.elem or 1), #burn
	end
	local share0, ticks0 = burnShare(0)
	local share1, ticks1 = burnShare(1)
	T.check(near(share0, 0.25, 0.01) and ticks0 == 3, "evo el flame: Evo 0 burns 25% of the hit", fmt("%.3f, %d ticks", share0, ticks0))
	T.check(near(share1, 0.35, 0.01) and ticks1 == 3, "evo el flame: Wildfire burns 35% of the hit, same ticks", fmt("%.3f, %d ticks", share1, ticks1))
	-- Evo 2: the burning ground at the aim point
	local b, f, foes = field(BS, melee(PC, "Flame", 2), { { 10, 0 }, { 40, 0 } })
	local ev, evs = cast(b, f, { x = 10, z = 0 })
	local zone = findEvent(evs, "Zone", function(z)
		return z.kind == "Patch"
	end)
	T.check(zone ~= nil and zone.special == "Flame" and zone.seconds == 2 and zone.r == r1(5 * 1.3) and zone.x == ev.tx and zone.z == ev.tz and zone.x == 10 and zone.z == 0, "evo el flame: a Zone kind Patch { special = Flame, seconds = 2, r = 5 x 1.3 } at (tx, tz)", zone and fmt("%s %s %s %s", tostring(zone.special), tostring(zone.seconds), tostring(zone.r), tostring(zone.x)))
	run(b, 2.1, evs)
	local ticks = hitsOn(evs, foes[1].id, function(h)
		return h.zone == true and h.kind == "Patch"
	end)
	local hit = hitsOn(evs, foes[1].id, function(h)
		return h.element ~= nil
	end)[1]
	T.check(#ticks >= 3 and hit ~= nil and near(dealt(ticks) / onFoe(hitOf(BC, f) * 0.45, foes[1], ticks[1]), 1, 0.3), "evo el flame: zone Hits for 2 s, near 0.45 x the hit in all", fmt("%d ticks, %d", #ticks, dealt(ticks)))
	T.check(#hitsOn(evs, foes[2].id) == 0, "evo el flame: nothing outside it")
	local after = run(b, 1)
	T.check(#hitsOn(after, foes[1].id, function(h)
		return h.zone == true
	end) == 0, "evo el flame: none after")
	T.check(foes[1].burnLeft ~= nil and #hitsOn(evs, foes[1].id, function(h)
		return h.burn == true
	end) >= 1, "evo el flame: stage 2 keeps the burn")
	-- it lands inside the attack's own reach: a far aim falls at the cone's end, the event says so
	b, f, foes = field(BS, melee(PC, "Flame", 2), { { 6, 0 } })
	ev, evs = cast(b, f, { x = 70, z = 0 })
	zone = findEvent(evs, "Zone", function(z)
		return z.kind == "Patch"
	end)
	T.check(zone ~= nil and near(zone.x, 18.2, 0.051) and zone.z == 0, "evo el flame: a far aim's ground falls at the cone's end (a client can't place it across the floor)", zone and tostring(zone.x))
	-- the pet's next Inferno replaces its own patch
	b, f, foes = field(BS, melee(PC, "Flame", 2), { { 10, 0 } })
	cast(b, f, { x = 10, z = 0 })
	b.teams[1].elementReadyAt = 0
	cast(b, f, { x = 10, z = 5 })
	local patches = 0
	for _, zn in ipairs(b.zones) do
		if zn.kind == "Patch" then
			patches = patches + 1
		end
	end
	T.check(patches == 1, "evo el flame: the next Inferno replaces its own patch", tostring(patches))
end)

----------------------------------------------------------------------------------------------------
-- Frost
----------------------------------------------------------------------------------------------------
S.evo_el_frost = guarded("evo_el_frost", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el frost: the modules load") then
		return
	end
	local b, f, foes = field(BS, melee(PC, "Frost", 1), { { 5, 0 } })
	local _, _, t0 = cast(b, f, foes[1].id)
	T.check(foes[1].slowMult == 0.5 and near(foes[1].slowUntil, t0 + 4, 1e-6) and foes[1].markMult == 1, "evo el frost: Deep Frost: 50% slower for 4 s, no mark yet", fmt("%s until +%.2f", tostring(foes[1].slowMult), foes[1].slowUntil - t0))
	b, f, foes = field(BS, melee(PC, "Frost", 0), { { 5, 0 } })
	_, _, t0 = cast(b, f, foes[1].id)
	T.check(foes[1].slowMult == 0.6 and near(foes[1].slowUntil, t0 + 4, 1e-6) and foes[1].markUntil == 0, "evo el frost: Evo 0: 40% slower", tostring(foes[1].slowMult))
	-- Evo 2: the slowed bears are marked for the slow's seconds
	b, f, foes = field(BS, melee(PC, "Frost", 2), { { 5, 0 }, { -9, 0 } })
	_, _, t0 = cast(b, f, foes[1].id)
	T.check(foes[1].slowMult == 0.5 and foes[1].markMult == 1.10 and near(foes[1].markUntil, t0 + 4, 1e-6), "evo el frost: Ice Snare: markMult 1.10 on a slowed bear for 4 s", fmt("%s until +%.2f", tostring(foes[1].markMult), foes[1].markUntil - t0))
	T.check(foes[2].markMult == 1 and foes[2].slowMult == 1, "evo el frost: a bear outside the cone: neither")
	-- one status with the Beam's: a Beam-marked bear keeps 1.15
	b, f, foes = field(BS, melee(PC, "Frost", 2), { { 5, 0 } })
	foes[1].markMult, foes[1].markUntil = 1.15, b:Time() + 2
	_, _, t0 = cast(b, f, foes[1].id)
	T.check(foes[1].markMult == 1.15 and near(foes[1].markUntil, t0 + 4, 1e-6), "evo el frost: a Beam-marked (1.15) bear keeps 1.15, the later until", tostring(foes[1].markMult))
	-- a dodged cone slows and marks nobody
	b, f, foes = field(BS, melee(PC, "Frost", 2), { { 5, 0 } })
	foes[1].iframesUntil = b:Time() + 1
	cast(b, f, foes[1].id)
	T.check(foes[1].slowUntil == 0 and foes[1].markUntil == 0, "evo el frost: a bear in its dash i-frames is neither slowed nor marked")
end)

----------------------------------------------------------------------------------------------------
-- Nature
----------------------------------------------------------------------------------------------------
S.evo_el_nature = guarded("evo_el_nature", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el nature: the modules load") then
		return
	end
	local function leech(evo)
		local b, f, foes = field(BS, melee(PC, "Nature", evo), { { 5, 0 } })
		f.hp = 5e6
		local _, evs = cast(b, f, foes[1].id)
		local hit = hitsOn(evs, foes[1].id, function(h)
			return h.element ~= nil
		end)[1]
		return hit.leech / hit.dmg
	end
	T.check(near(leech(0), 0.3, 0.01), "evo el nature: Evo 0: 30% of the hit", fmt("%.3f", leech(0)))
	T.check(near(leech(1), 0.4, 0.01), "evo el nature: Bramble Lash: 40% of the hit", fmt("%.3f", leech(1)))
	T.check(near(leech(2), 0.4, 0.01), "evo el nature: stage 2 keeps it", fmt("%.3f", leech(2)))
	-- Evo 2: rooted 0.4 s; Evo 1: not
	local b, f, foes = field(BS, melee(PC, "Nature", 1), { { 5, 0 } })
	cast(b, f, foes[1].id)
	T.check(foes[1].stunUntil == 0, "evo el nature: Evo 1 roots nothing")
	b, f, foes = field(BS, melee(PC, "Nature", 2), { { 5, 0 } })
	local t0 = b:Time()
	b:Command(1, "Element", foes[1].id)
	T.check(foes[1].state == BS.States.Stunned and near(foes[1].stunUntil, t0 + 0.4, 1e-6), "evo el nature: Worldroot: Stunned for 0.4 s", fmt("state %s until +%.2f", tostring(foes[1].state), foes[1].stunUntil - t0))
end)

----------------------------------------------------------------------------------------------------
-- Earth
----------------------------------------------------------------------------------------------------
S.evo_el_earth = guarded("evo_el_earth", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el earth: the modules load") then
		return
	end
	-- Evo 1: the crack erupts again 0.5 s later on every bear in the circle, at the ORIGINAL centre
	local b, f, foes = field(BS, melee(PC, "Earth", 1), { { 5, 0 }, { 0, 6 }, { 40, 0 } })
	local ev, evs, t0 = cast(b, f, foes[1].id)
	T.check(has(ev.targets, foes[1].id) and has(ev.targets, foes[2].id) and near(foes[1].stunUntil, t0 + 0.5, 1e-6), "evo el earth: the Quake hits round the pet, stun 0.5 unchanged", fmt("+%.2f", foes[1].stunUntil - t0))
	T.check(#twists(evs, "Fissure") == 0, "evo el earth: no crack at the cast")
	f.x, f.z, f.px, f.pz = 0, 30, 0, 30
	b.teams[1].wantX, b.teams[1].wantZ = 0, 30
	local later = run(b, 0.5)
	local tw = twists(later, "Fissure")
	T.check(#tw == 1 and tw[1].kind == "Earth" and tw[1].x == 0 and tw[1].z == 0 and tw[1].r == r1(8 * 1.15), "evo el earth: 0.5 s later a Twist Fissure at the original centre", tw[1] and fmt("%s %s %s", tostring(tw[1].x), tostring(tw[1].z), tostring(tw[1].r)))
	local crack = twistHits(later, foes[1].id, "Fissure")
	T.check(#crack == 1 and landed(BC, f, foes[1], crack[1], 0.4) and #twistHits(later, foes[2].id, "Fissure") == 1 and #twistHits(later, foes[3].id, "Fissure") == 0, "evo el earth: 0.4 x on every bear in the circle", crack[1] and tostring(crack[1].dmg))
	run(b, 1, later)
	T.check(#twists(later, "Rockspire") == 0, "evo el earth: Evo 1 has no Rockspire")
	-- Evo 2: the ring at 1.0 s, the crack kept at 0.5 s
	local r = 8 * 1.3
	local band = 4 * 1.3
	b, f, foes = field(BS, melee(PC, "Earth", 2), { { r / 2, 0 }, { 0, r + 2 }, { -(r + band + 3), 0 } })
	local bearRadius = foes[1].radius
	foes[3].x, foes[3].px = -(r + band + bearRadius + 0.5), -(r + band + bearRadius + 0.5)
	ev, evs, t0 = cast(b, f, foes[1].id)
	run(b, 0.5, evs)
	T.check(#twists(evs, "Fissure") == 1 and #twists(evs, "Rockspire") == 0, "evo el earth: stage 2 keeps the crack at 0.5 s; no ring yet")
	run(b, 0.5, evs)
	tw = twists(evs, "Rockspire")
	T.check(#tw == 1 and tw[1].kind == "Earth" and tw[1].x == 0 and tw[1].z == 0 and tw[1].r == r1(r) and tw[1].band == r1(band), "evo el earth: at 1.0 s a Twist Rockspire: the ring round the area", tw[1] and fmt("%s %s", tostring(tw[1].r), tostring(tw[1].band)))
	local spike = twistHits(evs, foes[2].id, "Rockspire")
	T.check(#spike == 1 and landed(BC, f, foes[2], spike[1], 0.4), "evo el earth: a bear in the ring (r + 2) is hit 0.4 x", spike[1] and tostring(spike[1].dmg))
	T.check(#twistHits(evs, foes[1].id, "Rockspire") == 0, "evo el earth: one inside the area (r / 2) is NOT")
	T.check(#twistHits(evs, foes[3].id, "Rockspire") == 0, "evo el earth: one past the ring's outer edge is NOT")
	-- a body counts by its edge, as in every shape: a big body round the middle reaches the ring
	b, f, foes = field(BS, melee(PC, "Earth", 2), { { r - 1, 0 } })
	foes[1].radius = 3
	evs = select(2, cast(b, f, foes[1].id))
	run(b, 1.1, evs)
	T.check(#twistHits(evs, foes[1].id, "Rockspire") == 1, "evo el earth: a body whose edge reaches the ring is struck")
end)

----------------------------------------------------------------------------------------------------
-- Storm
----------------------------------------------------------------------------------------------------
S.evo_el_storm = guarded("evo_el_storm", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el storm: the modules load") then
		return
	end
	-- Evo 1: A in the line, B 6 studs from A off the line, C 18 from A
	local b, f, foes = field(BS, melee(PC, "Storm", 1), { { 10, 0 }, { 10, 6.5 }, { 10, 18 } })
	f.meter = 0
	local ev, evs = cast(b, f, foes[1].id)
	T.check(has(ev.targets, foes[1].id) and not has(ev.targets, foes[2].id), "evo el storm: the line hits A only")
	local onA, onB = hitsOn(evs, foes[1].id), hitsOn(evs, foes[2].id)
	T.check(#onA == 1 and onA[1].twist == nil and landed(BC, f, foes[1], onA[1], 1), "evo el storm: A takes the full hit, once", tostring(#onA))
	T.check(#onB == 1 and onB[1].twist == "Forked" and landed(BC, f, foes[2], onB[1], 0.3), "evo el storm: B takes 0.3 x with twist Forked", onB[1] and tostring(onB[1].dmg))
	T.check(#hitsOn(evs, foes[3].id) == 0, "evo el storm: C (18 from A) is not reached")
	local tw = twists(evs, "Forked")
	T.check(#tw == 1 and tw[1].kind == "Storm" and tw[1].x == 10 and tw[1].z == 0 and tw[1].tx == 10 and tw[1].tz == 6.5 and has(tw[1].targets, foes[2].id), "evo el storm: a Twist Forked from the last struck to the next", tw[1] and fmt("%s %s %s %s", tostring(tw[1].x), tostring(tw[1].z), tostring(tw[1].tx), tostring(tw[1].tz)))
	T.check(near(f.meter, 0, 0.31), "evo el storm: Evo 1 adds no meter (a step's tick aside)", tostring(f.meter))
	-- a lone bear in the line: hit twice (full, then 0.3 x), never three times; Evo 1 and Evo 2 alike
	for _, evo in ipairs({ 1, 2 }) do
		b, f, foes = field(BS, melee(PC, "Storm", evo), { { 10, 0 } })
		evs = select(2, cast(b, f, foes[1].id))
		run(b, 1, evs)
		local on = hitsOn(evs, foes[1].id)
		T.check(#on == 2 and on[1].twist == nil and on[2].twist == "Forked" and landed(BC, f, foes[1], on[2], 0.3), "evo el storm: a lone bear is struck again ONCE at Evo " .. evo, tostring(#on))
	end
	-- two bears in the line, no third: no strike again (the line didn't hit exactly one)
	b, f, foes = field(BS, melee(PC, "Storm", 2), { { 8, 0 }, { 14, 0 } })
	evs = select(2, cast(b, f, foes[1].id))
	T.check(#hitsOn(evs, foes[1].id) == 1 and #hitsOn(evs, foes[2].id) == 1, "evo el storm: two in the line and nobody near: one hit each")
	-- Evo 2: A, B, then D (within 10 of B, 14 from A): three strikes, and +3 meter
	b, f, foes = field(BS, melee(PC, "Storm", 2), { { 10, 0 }, { 10, 6.5 }, { 10, 14 }, { 10, 40 } })
	f.meter = 0
	evs = select(2, cast(b, f, foes[1].id))
	onA, onB = hitsOn(evs, foes[1].id), hitsOn(evs, foes[2].id)
	local onD = hitsOn(evs, foes[3].id)
	T.check(#onA == 1 and #onB == 1 and #onD == 1 and onB[1].twist == "Forked" and onD[1].twist == "Forked", "evo el storm: Thunder Lance jumps twice: A, B, then D", fmt("%d %d %d", #onA, #onB, #onD))
	T.check(#hitsOn(evs, foes[4].id) == 0, "evo el storm: ...no further")
	T.check(#twists(evs, "Forked") == 2 and twists(evs, "Forked")[2].x == 10 and twists(evs, "Forked")[2].z == 6.5, "evo el storm: ...each jump from the last struck")
	T.check(near(f.meter, 3, 0.31), "evo el storm: +3 meter (a step's tick aside)", tostring(f.meter))
	-- the jump goes from the LAST body the line struck, to the nearest not yet hit
	b, f, foes = field(BS, melee(PC, "Storm", 1), { { 6, 0 }, { 16, 0 }, { 16, 6.5 }, { 16, 8 } })
	evs = select(2, cast(b, f, foes[1].id))
	T.check(#hitsOn(evs, foes[3].id) == 1 and #hitsOn(evs, foes[4].id) == 0, "evo el storm: one jump: the nearest to the last struck")
	-- a dodged line jumps nowhere
	b, f, foes = field(BS, melee(PC, "Storm", 1), { { 10, 0 }, { 10, 6.5 } })
	foes[1].iframesUntil = b:Time() + 1
	evs = select(2, cast(b, f, foes[1].id))
	T.check(#hitsOn(evs, foes[2].id) == 0, "evo el storm: a dodged line jumps nowhere")
end)

----------------------------------------------------------------------------------------------------
-- Celestial
----------------------------------------------------------------------------------------------------
S.evo_el_celestial = guarded("evo_el_celestial", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el celestial: the modules load") then
		return
	end
	local function meter(evo)
		local b, f, foes = field(BS, melee(PC, "Celestial", evo), { { 5, 0 } })
		f.meter = 0
		cast(b, f, foes[1].id)
		return f.meter
	end
	T.check(near(meter(0), 15, 0.31) and near(meter(1), 20, 0.31) and near(meter(2), 20, 0.31), "evo el celestial: meter + 15 / Halo + 20 / kept (a step's tick aside)", fmt("%s %s %s", tostring(meter(0)), tostring(meter(1)), tostring(meter(2))))
	-- Evo 2: heals 8% of its max
	local b, f, foes = field(BS, melee(PC, "Celestial", 2), { { 5, 0 } })
	f.hp = f.maxHp * 0.5
	local _, evs = cast(b, f, foes[1].id)
	local tw = twists(evs, "Starfall")
	T.check(near(f.hp, f.maxHp * 0.58, 1) and #tw == 1 and tw[1].kind == "Celestial" and tw[1].heals[1][1] == f.id and near(tw[1].heals[1][2], f.maxHp * 0.08, 1), "evo el celestial: Starfall: a fighter at 50% HP heals 8% of its max", fmt("%.3f", f.hp / f.maxHp))
	-- at full HP nothing to say; capped at its max
	b, f, foes = field(BS, melee(PC, "Celestial", 2), { { 5, 0 } })
	evs = select(2, cast(b, f, foes[1].id))
	T.check(f.hp == f.maxHp and #twists(evs, "Starfall") == 0, "evo el celestial: at full HP no Twist")
	b, f, foes = field(BS, melee(PC, "Celestial", 2), { { 5, 0 } })
	f.hp = f.maxHp * 0.98
	cast(b, f, foes[1].id)
	T.check(f.hp == f.maxHp, "evo el celestial: never past its max")
	b, f, foes = field(BS, melee(PC, "Celestial", 1), { { 5, 0 } })
	f.hp = f.maxHp * 0.5
	evs = select(2, cast(b, f, foes[1].id))
	T.check(near(f.hp, f.maxHp * 0.5, 1) and #twists(evs, "Starfall") == 0, "evo el celestial: Evo 1 doesn't heal")
end)

----------------------------------------------------------------------------------------------------
-- Shadow
----------------------------------------------------------------------------------------------------
S.evo_el_shadow = guarded("evo_el_shadow", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el shadow: the modules load") then
		return
	end
	-- a bear's variance-free zone tick on my fighter, after the cast (or none)
	local function tickAfter(evo)
		local b, f, foes = field(BS, melee(PC, "Shadow", evo), { { 5, 0 } })
		if evo then
			cast(b, f, foes[1].id)
		end
		b.zones[#b.zones + 1] = { x = f.x, z = f.z, r = 2, dps = 20000, untilT = b:Time() + 0.3, nextTick = b:Time(), side = 2, from = foes[1], kind = "Linger" }
		local evs = b:Step(0.05)
		return hitsOn(evs, f.id, function(h)
			return h.zone == true
		end)[1].dmg, foes[1], b
	end
	local plain = tickAfter(nil)
	local d0, foe0, b0 = tickAfter(0)
	local d1, foe1, b1 = tickAfter(1)
	T.check(near(d0 / plain, 0.85, 0.01) and foe0.weakenMult == 0.85 and near(foe0.weakenUntil - b0:Time(), 5 - 0.1, 0.11), "evo el shadow: Evo 0: enemies deal 15% less for 5 s", fmt("%.3f, +%.2f", d0 / plain, foe0.weakenUntil - b0:Time()))
	T.check(near(d1 / plain, 0.8, 0.01) and foe1.weakenMult == 0.8 and near(foe1.weakenUntil - b1:Time(), 5 - 0.1, 0.11), "evo el shadow: Hollow Rend: 20% less", fmt("%.3f", d1 / plain))
	-- two raiders: the strongest stands while both last
	local b, f, foes = field(BS, melee(PC, "Shadow", 1), { { 5, 0 } }, { Ally = melee(PC, "Shadow", 0) })
	local ally = b.teams[3].fighter
	cast(b, f, foes[1].id)
	ally.x, ally.z, ally.px, ally.pz = 0, 3, 0, 3
	b.teams[3].wantX, b.teams[3].wantZ = 0, 3
	cast(b, ally, foes[1].id, 2)
	T.check(foes[1].weakenMult == 0.8, "evo el shadow: a weaker Void Rend does not overwrite Hollow Rend", tostring(foes[1].weakenMult))
	run(b, 7.1)
	cast(b, ally, foes[1].id, 2)
	T.check(foes[1].weakenMult == 0.85, "evo el shadow: ...after it ended, the new one stands", tostring(foes[1].weakenMult))
	-- the leech: Evo 2 only
	local function leech(evo)
		local bb, ff, ffoes = field(BS, melee(PC, "Shadow", evo), { { 5, 0 } })
		ff.hp = 5e6
		local evs = select(2, cast(bb, ff, ffoes[1].id))
		local hit = hitsOn(evs, ffoes[1].id, function(h)
			return h.element ~= nil
		end)[1]
		return hit.leech and hit.leech / hit.dmg or 0
	end
	T.check(leech(0) == 0 and leech(1) == 0 and near(leech(2), 0.15, 0.01), "evo el shadow: Soul Rend: Hit.leech near 0.15 x", fmt("%.3f", leech(2)))
end)

----------------------------------------------------------------------------------------------------
-- A ranged pet's Circle
----------------------------------------------------------------------------------------------------
S.evo_el_ranged_circle = guarded("evo_el_ranged_circle", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el ranged: the modules load") then
		return
	end
	T.check(BC.ProfileOf(PC.Get(RANGED_SHORT)).Attack == "Ranged" and BC.ProfileOf(PC.Get(MELEE)).Attack == "Melee", "evo el ranged: the fixture's pets are what they say")
	local range = BC.ProfileOf(PC.Get(RANGED_SHORT)).Range
	T.check(range == 12, "evo el ranged: the short fixture's range is 12", tostring(range))
	local function short(element, evo)
		return ranged(PC, element, evo, RANGED_SHORT)
	end
	for _, element in ipairs({ "Earth", "Celestial" }) do
		for _, evo in ipairs({ 0, 2 }) do
			-- standing 10 from a bear: the bear at the aim, one 6 behind the pet (today's circle round the pet hit it), one 6 past the aim (today's missed it)
			local b, f, foes = field(BS, short(element, evo), { { 10, 0 }, { -6, 0 }, { 16, 0 } })
			local ev, evs = cast(b, f, foes[1].id)
			T.check(ev ~= nil and ev.tx == 10 and ev.tz == 0 and ev.x == 0 and ev.z == 0, "evo el ranged: x, z stay the caster, tx, tz the aim", ev and fmt("%s %s", tostring(ev.tx), tostring(ev.tz)))
			T.check(has(ev.targets, foes[1].id) and #hitsOn(evs, foes[1].id) >= 1, element .. " Evo " .. evo .. ": the bear at the aim is hit")
			T.check(not has(ev.targets, foes[2].id) and #hitsOn(evs, foes[2].id) == 0, element .. " Evo " .. evo .. ": one 6 behind the pet is NOT")
			T.check(has(ev.targets, foes[3].id), element .. " Evo " .. evo .. ": one 6 past the aim is (the circle sits on the enemy's area)")
			if evo == 0 then
				T.check(ev.r == nil, element .. " Evo 0: no number on the wire")
			else
				T.check(near(ev.r, 12, 1e-6), element .. " Evo 2: the radius is today's, max(the catalog's x reach, its range)", tostring(ev.r))
			end
		end
		-- a melee pet: centred on itself (today)
		for _, evo in ipairs({ 0, 2 }) do
			local b, f, foes = field(BS, melee(PC, element, evo), { { 5, 0 }, { 0, 2 }, { 14, 0 } })
			local ev = cast(b, f, foes[1].id)
			T.check(has(ev.targets, foes[1].id) and has(ev.targets, foes[2].id) and not has(ev.targets, foes[3].id), element .. " Evo " .. evo .. ": a melee pet's Circle is round itself")
		end
		-- the centre is at most its range away: a far lock or point falls short, never across the floor
		local b, f, foes = field(BS, short(element, 0), { { 60, 0 } })
		local ev = cast(b, f, foes[1].id)
		T.check(ev ~= nil and near(ev.tx, range, 0.051) and ev.tz == 0 and not has(ev.targets, foes[1].id), element .. ": a far aimed enemy: the centre falls at its range, nothing is hit", ev and tostring(ev.tx))
		b, f, foes = field(BS, short(element, 0), { { 60, 0 } })
		ev = cast(b, f, { x = 70, z = 0 })
		T.check(ev ~= nil and near(ev.tx, range, 0.051) and not has(ev.targets, foes[1].id), element .. ": a far aimed point too", ev and tostring(ev.tx))
		-- a point within range is the centre
		b, f, foes = field(BS, short(element, 0), { { 10, 5 } })
		ev = cast(b, f, { x = 10, z = 5 })
		T.check(ev ~= nil and ev.tx == 10 and ev.tz == 5 and has(ev.targets, foes[1].id), element .. ": an aimed point in range is the centre")
		-- an enemy at the edge of its fighting reach still takes it: what reached before still does
		b, f, foes = field(BS, short(element, 0), { { range + 2, 0 } })
		ev = cast(b, f, foes[1].id)
		T.check(ev ~= nil and has(ev.targets, foes[1].id), element .. ": an enemy just past its range is still in the circle", ev and tostring(ev.tx))
	end
	-- Earth's stun lands where the circle does
	local b, f, foes = field(BS, short("Earth", 0), { { 10, 0 }, { -6, 0 } })
	local _, _, t0 = cast(b, f, foes[1].id)
	T.check(near(foes[1].stunUntil, t0 + 0.5, 1e-6) and foes[2].stunUntil == 0, "evo el ranged: the Quake's stun lands in the aimed circle")
	-- a real ranged Celestial pet (range 18): 8 behind it is out of a circle of 18 on an aim 14 ahead
	b, f, foes = field(BS, { Key = "moonlit_owl", Level = 50, Evo = 2 }, { { 14, 0 }, { -8, 0 } })
	local ev = cast(b, f, foes[1].id)
	T.check(f.ranged == true and ev ~= nil and ev.name == "Starfall" and has(ev.targets, foes[1].id) and not has(ev.targets, foes[2].id), "evo el ranged: Moonlit Owl's Starfall lands on its aim")
	-- Evo 1 Fissure at the aimed centre, the same for Rockspire: the crack's circle is 12, the ring 12 to 17.2
	b, f, foes = field(BS, short("Earth", 2), { { 10, 0 }, { 10, 15 }, { -6, 0 } })
	local evs = select(2, cast(b, f, foes[1].id))
	run(b, 1.1, evs)
	T.check(twists(evs, "Fissure")[1] ~= nil and twists(evs, "Fissure")[1].x == 10 and #twistHits(evs, foes[1].id, "Fissure") == 1 and #twistHits(evs, foes[3].id, "Fissure") == 0, "evo el ranged: the crack erupts at the aimed centre")
	T.check(twists(evs, "Rockspire")[1] ~= nil and twists(evs, "Rockspire")[1].x == 10 and #twistHits(evs, foes[2].id, "Rockspire") == 1, "evo el ranged: the ring rings the aimed centre")
	-- a ranged Cone / Line keeps today's rule: from the pet, max(Length x reach, its range)
	b, f, foes = field(BS, ranged(PC, "Flame", 0), { { 16, 0 }, { 8, 1 } })
	ev = cast(b, f, foes[1].id)
	T.check(ev ~= nil and ev.shape == "Cone" and has(ev.targets, foes[1].id) and has(ev.targets, foes[2].id) and ev.length == nil, "evo el ranged: a ranged Cone: from the pet out to its own range")
	b, f, foes = field(BS, ranged(PC, "Storm", 2), { { 20, 0 }, { 8, 1 } })
	ev = cast(b, f, foes[1].id)
	T.check(ev ~= nil and ev.shape == "Line" and has(ev.targets, foes[1].id) and has(ev.targets, foes[2].id) and near(ev.length, 24 * 1.3, 1e-6), "evo el ranged: a ranged Line: from the pet", ev and tostring(ev.length))
end)

----------------------------------------------------------------------------------------------------
-- Bosses
----------------------------------------------------------------------------------------------------
S.evo_el_boss = guarded("evo_el_boss", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo el boss: the modules load") then
		return
	end
	local function onBoss(element, evo, x, seconds)
		local b, f, boss = raid(BS, melee(PC, element, evo), x or 8)
		local ev, evs, t0 = cast(b, f, boss.id)
		run(b, seconds or 0, evs)
		return b, f, boss, evs, ev, t0
	end
	local function oneBonus(what, element, evo)
		local b, f, boss, evs = onBoss(element, evo)
		local bonus = bonusHits(evs, boss.id)
		T.check(#bonus == 1 and landed(BC, f, boss, bonus[1], 0.07) and bonus[1].element ~= nil, "evo el boss: " .. what .. ": one bonus Hit near 0.07 x the element hit", fmt("%d hits, %s", #bonus, bonus[1] and tostring(bonus[1].dmg)))
		T.check(boss.slowUntil == 0 and boss.slowMult == 1 and boss.stunUntil == 0 and boss.burnLeft == 0, "evo el boss: " .. what .. ": no slow, stun or burn")
		return b, f, boss, evs
	end
	oneBonus("Riptide", "Water", 1)
	oneBonus("Deep Frost", "Frost", 1)
	oneBonus("Worldroot", "Nature", 2)
	oneBonus("Wildfire", "Flame", 1) -- burn is in the immunity list: it never does nothing
	-- the other stage: no bonus where nothing is lost
	local _, _, boss, evs = onBoss("Nature", 1)
	T.check(#bonusHits(evs, boss.id) == 0, "evo el boss: Bramble Lash needs no bonus: its leech works")
	_, _, boss, evs = onBoss("Water", 0)
	T.check(#bonusHits(evs, boss.id) == 0 and near(boss.x, 8, 1e-6), "evo el boss: Evo 0 pays no bonus, the boss is not pushed")
	_, _, boss, evs = onBoss("Frost", 0)
	T.check(#bonusHits(evs, boss.id) == 0 and boss.slowUntil == 0, "evo el boss: Evo 0's Frostbite: nothing (today)")
	_, _, boss, evs = onBoss("Flame", 0)
	T.check(#bonusHits(evs, boss.id) == 0 and boss.burnLeft == 0, "evo el boss: Evo 0's Flare: nothing (today)")
	-- every timed twist lands on it
	_, _, boss, evs = onBoss("Water", 2, 8, 0.6)
	T.check(#twistHits(evs, boss.id, "Maelstrom") == 1 and #bonusHits(evs, boss.id) == 1, "evo el boss: Maelstrom damages the boss; Riptide's bonus stays one")
	_, _, boss, evs = onBoss("Earth", 1, 8, 0.6)
	T.check(#twistHits(evs, boss.id, "Fissure") == 1, "evo el boss: Fissure damages the boss")
	_, _, boss, evs = onBoss("Earth", 2, 8, 1.1)
	T.check(#twistHits(evs, boss.id, "Rockspire") == 1, "evo el boss: Rockspire damages the boss (its body reaches the ring)")
	_, _, boss, evs = onBoss("Storm", 1)
	T.check(#twistHits(evs, boss.id, "Forked") == 1, "evo el boss: Forked Bolt strikes a lone boss again")
	_, _, boss, evs = onBoss("Flame", 2, 8, 1)
	T.check(#hitsOn(evs, boss.id, function(h)
		return h.zone == true and h.kind == "Patch"
	end) >= 1, "evo el boss: Inferno's ground hurts the boss")
	-- Ice Snare's mark is not an immunity
	local t0
	_, _, boss, evs, _, t0 = onBoss("Frost", 2)
	T.check(boss.markMult == 1.10 and near(boss.markUntil, t0 + 4, 1e-6), "evo el boss: Ice Snare marks it", tostring(boss.markMult))
	-- Hollow Rend weakens it, as today's Void Rend does
	_, _, boss = onBoss("Shadow", 1)
	T.check(boss.weakenMult == 0.8, "evo el boss: Hollow Rend weakens it", tostring(boss.weakenMult))
	-- a bonus dodges nothing: a boss has no i-frames, but a dead caster's queue still drops
	local b, f
	b, f, boss = raid(BS, melee(PC, "Earth", 2), 8)
	cast(b, f, boss.id)
	b.teams[1].fighter.alive = false
	evs = run(b, 1.2)
	T.check(#twists(evs, "Fissure") == 0 and #twists(evs, "Rockspire") == 0, "evo el boss: a fallen caster's crack and ring are dropped")
end)

----------------------------------------------------------------------------------------------------
-- What a boss's HP counts for a fighter's forms
----------------------------------------------------------------------------------------------------
S.evo_el_form_dps = guarded("evo_el_form_dps", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready and type(BC.FormDps) == "table" and type(BC.FormDpsOf) == "function" and type(BC.FormStageOf) == "function", "evo form dps: the catalog has it") then
		return
	end
	local D = BC.FormDps
	T.check(D[0] == 1 and D[1] >= 1 and D[2] >= D[1], "evo form dps: stage 0 counts x1, never falling with the stage", fmt("%s %s", tostring(D[1]), tostring(D[2])))
	local bear, hybrid = PC.Get(MELEE), cloneDef(PC, MELEE, { Look = { Species = "Bear", BodyId = MELEE, StyleId = "stormfang" } })
	T.check(BC.FormStageOf(bear, 0) == 0 and BC.FormStageOf(bear, 1) == 1 and BC.FormStageOf(bear, 2) == 2 and BC.FormStageOf(bear, 7) == 2, "evo form dps: FormStageOf is the stored stage, at most 2")
	T.check(BC.FormStageOf(PC.Get("pebble_pup"), BC.UnitStats({ Key = "pebble_pup", Level = 60, Evo = 2 }).Evo) == 1, "evo form dps: ...a once-evolver with a stored 2 is at its top form (UnitStats' stage that counts)")
	T.check(BC.FormStageOf(hybrid, 2) == 2 and BC.FormStageOf(hybrid, 1) == 1 and BC.FormStageOf(hybrid, 0) == 0 and BC.FormStageOf({ IsHybrid = true }, 2) == 2, "evo form dps: ...a hybrid reads its real stage (Look.BodyId or IsHybrid)")
	T.check(BC.FormStageOf(hybrid, nil) == 0 and BC.FormStageOf(hybrid, 0 / 0) == 0 and BC.FormStageOf(hybrid, -1) == 0 and BC.FormStageOf(nil, 1) == 1, "evo form dps: ...junk (nil / NaN / negative) is stage 0")
	-- the factor: stage x kind x element, on the fighter alone
	local function factor(def, evo)
		return BC.FormDpsOf(def, { Evo = evo, Elements = def.Elements or { def.Element } })
	end
	local storm = PC.Get("stormfang")
	local mid = PC.Get("ember_phoenix")
	T.check(factor(mid, 0) == 1 and factor(storm, 0) == 1 and factor(hybrid, 0) == 1, "evo form dps: x1 at stage 0, a hybrid's too")
	T.check(factor(hybrid, 2) > 1 and near(factor(hybrid, 2), factor(bear, 2), 1e-9) and near(factor(hybrid, 1), factor(bear, 1), 1e-9), "evo form dps: a hybrid's factor is the plain pet's at its stage", fmt("%s vs %s", tostring(factor(hybrid, 2)), tostring(factor(bear, 2))))
	T.check(near(factor(mid, 1), D[1], 1e-9), "evo form dps: a Blast + Flame fighter at stage 1 is the stage's alone", tostring(factor(mid, 1)))
	T.check(near(factor(storm, 2), D[2] * D.Pounce * D.Storm, 1e-9), "evo form dps: a Pounce + Storm fighter at stage 2: stage x kind x element", tostring(factor(storm, 2)))
	-- ExpectedDps follows it, stage 0 not at all
	local function dps(entry)
		return BC.ExpectedDps({ entry })
	end
	local keep1, keep2 = D[1], D[2]
	local e0, e1, e2, eh = dps({ Key = MELEE, Level = 50, Evo = 0 }), dps({ Key = MELEE, Level = 50, Evo = 1 }), dps({ Key = MELEE, Level = 50, Evo = 2 }), dps({ Def = hybrid, Key = MELEE, Level = 50, Evo = 2 })
	D[1], D[2] = keep1 * 2, keep2 * 3
	local n0, n1, n2, nh = dps({ Key = MELEE, Level = 50, Evo = 0 }), dps({ Key = MELEE, Level = 50, Evo = 1 }), dps({ Key = MELEE, Level = 50, Evo = 2 }), dps({ Def = hybrid, Key = MELEE, Level = 50, Evo = 2 })
	D[1], D[2] = keep1, keep2
	T.check(n0 == e0, "evo form dps: a stage-0 team's expected damage does not move", fmt("%s -> %s", tostring(e0), tostring(n0)))
	T.check(near(nh / eh, 3, 1e-9) and near(nh / eh, n2 / e2, 1e-9), "evo form dps: a hybrid team's at Evo 2 moves exactly like a stage-2 team's", fmt("x%.3f vs x%.3f", nh / eh, n2 / e2))
	T.check(near(n1 / e1, 2, 1e-9) and near(n2 / e2, 3, 1e-9), "evo form dps: an evolved team's follows its stage", fmt("x%.3f, x%.3f", n1 / e1, n2 / e2))
	-- Validate
	T.check(BC.Validate() == true, "evo form dps: Validate passes")
	D[0] = 1.1
	local zero = BC.Validate()
	D[0], D[1] = 1, 0.9
	local low = BC.Validate()
	D[1], D[2] = keep1, keep1 - 0.01
	local falling = BC.Validate()
	D[1], D[2] = keep1, keep2
	T.check(zero == false and low == false and falling == false and BC.Validate() == true, "evo form dps: Validate catches a stage 0 past x1, a form that lowers it, a stage 2 under stage 1")
end)

return S
