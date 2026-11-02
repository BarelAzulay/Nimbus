-- smoke_evo_sim.lua: evolved special forms in the sim (docs/superpowers/specs/2026-11-01-evolved-forms-design.md; plan Task 1), loaded by
-- tools/smoke.py in the server world, pure:
--   evo_forms_table    BattleCatalog.Forms / FormNames / FormOf / FormNameOf, every name of the spec's tables, Validate catches a gap
--   evo_stage0_pinned  a frozen Duel replay of unmoved pets (recorded BEFORE any forms code): stage 0 plays byte for byte as it did
--   evo_pounce         the charge line (8 behind the pet, through the target, 3 past it; the drawn area IS the real area), Landing
--   evo_blast          Aftershock at the original point, Burning ground (replaces its own, stacks with another pet's)
--   evo_storm          Dragging winds (slow, zone damage unchanged), Last strike at the zone's end (not for a fallen caster)
--   evo_beam           Mark (strongest wins, multiplied with the ally Taken buff), Twin from where the caster stands THEN
--   evo_freeze         Chill at the thaw, Shatter at the ORIGINAL point
--   evo_heal           Lingering ticks, Overflow's shield
--   evo_shield         Thorns (a Thorns hit never reflects), Burst (once: break / expiry / KO / a recast)
--   evo_rally          War pace (keep-larger Speed), Fired up, the 80% uptime pin
--   evo_haste          Quick hands on the cooldowns set while on, Double strike's chance
--   evo_boss_twists    a boss keeps its immunities: a bonus hit instead; every timed twist still lands on it
--   evo_slow_mark      slowMult / markMult: strongest wins, the three readers of the slow, stage 0's numbers
--   evo_delayed        a queued hit whose caster fell, left or was benched is dropped; two pets' hits both fire
--   evo_wire           the Special / Twist / Zone fields, unitInfo.special, a hybrid stays at stage 0
-- White-box: reaches into battle.units / battle.teams (same Lua state). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local abs, floor, huge, atan2 = math.abs, math.floor, math.huge, math.atan2
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

-- every landed Hit on unit `id` (optionally filtered)
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

-- steps `seconds` at 0.05 s, gathering every event into `into`
local function run(b, seconds, into)
	into = into or {}
	for _ = 1, floor(seconds / 0.05 + 0.5) do
		for _, ev in ipairs(b:Step(0.05)) do
			into[#into + 1] = ev
		end
	end
	return into
end

-- a unit that stands, hits nothing by itself, and has HP past every cap (the Duel's MaxHit share, a KO)
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

-- a Duel on a wide floor: my fighter (`entry`) at the origin, one standing bear per spot. opts: Seed, Zone, Bench (entries), Ally
-- (an entry of a second player team on side 1, at { 0, 40 })
local function field(BS, entry, spots, opts)
	opts = opts or {}
	local foes = {}
	for i = 1, #spots do
		foes[i] = { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = i }
	end
	entry.Slot = 1
	local mine = { entry }
	for i, extra in ipairs(opts.Bench or {}) do
		extra.Slot = i + 1
		mine[#mine + 1] = extra
	end
	local teams = { { Owner = 1, Side = 1, Pets = mine }, { Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = foes } }
	if opts.Ally then
		opts.Ally.Slot = 1
		teams[3] = { Owner = 2, Side = 1, Pets = { opts.Ally } }
	end
	local b = BS.new({ Mode = "Duel", Seed = opts.Seed or 7, Zone = opts.Zone or { X = 160, Z = 160 }, TimeLimit = 300, Teams = teams })
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

-- a Raid: my fighter at the origin, the boss at { 20, 0 }, its own attacks off and its HP past every wave and the enrage. opts: Bench,
-- Minion (a standing bear on side 2 at { 12, 0 })
local function raid(BS, entry, opts)
	opts = opts or {}
	entry.Slot = 1
	local mine = { entry }
	for i, extra in ipairs(opts.Bench or {}) do
		extra.Slot = i + 1
		mine[#mine + 1] = extra
	end
	local teams = { { Owner = 1, Side = 1, Pets = mine } }
	if opts.Minion then
		teams[2] = { Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = { { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = 1 } } }
	end
	local b = BS.new({ Mode = "Raid", Seed = 7, Boss = "storm_titan", RaidTier = "High", Zone = { X = 160, Z = 160 }, TimeLimit = 600, Teams = teams })
	if not b then
		return nil
	end
	local f = standFighter(b.teams[1], 0, 0)
	local boss = b.boss
	boss.x, boss.z, boss.px, boss.pz = 20, 0, 20, 0
	boss.maxHp, boss.hp = 1e9, 1e9
	boss.attacks, boss.lethal, boss.nextAttack = {}, nil, huge
	local minion = nil
	for _, u in ipairs(b.units) do
		if u.side == 2 and u.kind ~= "Boss" then
			minion = u
			stand(u, 12, 0)
		end
	end
	return b, f, boss, minion
end

-- my team's fighter casts its Special at `foe`: the Special event, every event, the battle time before the cast
local function special(b, f, foe, owner)
	owner = owner or 1
	f.meter = 100
	if foe then
		b:Command(owner, "Target", foe.id)
	end
	local t0 = b:Time()
	local ok, why = b:Command(owner, "Special")
	local evs = b:Step(0.05)
	return findEvent(evs, "Special", function(ev)
		return ev.unit == f.id
	end), evs, t0, ok, why
end

-- a real knockout through applyDamage: a one-tick hostile zone on the fighter (the bear's hit, no variance)
local function zap(b, f, foe, dps)
	b.zones[#b.zones + 1] = { x = f.x, z = f.z, r = 1, dps = dps or 1e7, untilT = b:Time() + 0.3, nextTick = b:Time(), side = foe.side, from = foe, kind = "Linger" }
end

-- `base` of castSpecial and the variance-free number it deals on `foe`
local function baseOf(BC, f, kind)
	local D = BC.Damage
	return f.specialPower * D.DamageScale * (BC.Specials[kind].Scale or 1) * (D.SpecialScale or 1)
end

local function onFoe(amount, foe, hit)
	return amount * ((hit and hit.elem) or 1) * (1 - (foe.defense or 0))
end

local LEG = "ember_phoenix" -- a Legendary: evolves twice

local function fighter(PC, kind, evo)
	return { Def = withSpecial(PC, LEG, kind), Key = LEG, Level = 50, Evo = evo }
end

local function benchPet()
	return { Key = "biscuit_bear", Level = 18, NoSpecial = true }
end

local function modules()
	local BC, BS, PC = req("BattleCatalog"), req("BattleSim"), req("PetCatalog")
	return BC, BS, PC, BC ~= nil and BS ~= nil and PC ~= nil and type(BC.FormOf) == "function" and BS.Events.Twist == "Twist"
end

----------------------------------------------------------------------------------------------------
-- the catalog
----------------------------------------------------------------------------------------------------
-- the spec's "Every pet's forms" tables, verbatim
local SPEC_NAMES = {
	pebble_pup = { "Boulder Fetch" }, mallow_kitten = { "Marshmallow Stampede" }, puddle_frog = { "Puddle Geyser" },
	honey_bunny = { "Honey Rain" }, biscuit_bear = { "Crumble Guard" }, pip_penguin = { "Snowspike Wall" },
	maple_fox = { "Burning Leaf Rush" }, bamboo_panda = { "Bamboo Quake" }, mochi_slime = { "Sticky Rebound" },
	sleepy_owl = { "Dream Lullaby" }, waffle_corgi = { "Golden Howl" }, bubble_axolotl = { "Popping Barrier" },
	blossom_bunny = { "Petal Gale" }, shroomie_frog = { "Spore Surge" }, frostling_penguin = { "Blizzard Burst" },
	storm_tabby = { "Static Snare" }, cherry_panda = { "Cherry Downpour" },
	aurora_fox = { "Aurora Mark", "Twin Aurora" }, moonlit_owl = { "Crescent Ward", "Full Moon Ward" }, nebula_axolotl = { "Nebula Swirl", "Supernova Swirl" },
	ember_phoenix = { "Phoenix Burst", "Phoenix Rebirth" }, sunbeam_bear = { "Solar Aegis", "Sunburst Aegis" },
	twilight_dragon = { "Nightfall Storm", "Dusk's End" }, candy_unicorn = { "Candy Rush", "Sugar Frenzy" },
	cloudy_dragon = { "Thunderhead Breath", "Twin Storm Breath" }, starlight_unicorn = { "Falling Wishes", "Wish Upon the Stars" },
	magma_cub = { "Magma Rift", "Volcano Slam" }, hydralotl = { "Void Chorus", "Hydra's Hunger" },
	stormfang = { "Shadow Pack", "Thunder Pack" }, eclipse_dragon = { "Black Sun Nova", "Total Eclipse" }, obsidian_phoenix = { "Cinder Wings", "Obsidian Rain" },
	phantom_kitsune = { "Nine-Tail Ward", "Phantom Foxfire" }, rime_wyrmling = { "Ice Prison", "Glacier Shatter" },
}

S.evo_forms_table = guarded("evo_forms_table", function()
	local BC, PC = req("BattleCatalog"), req("PetCatalog")
	if not T.check(BC ~= nil and type(BC.FormOf) == "function" and type(BC.FormNameOf) == "function" and type(BC.Forms) == "table" and type(BC.FormNames) == "table", "evo forms: Forms / FormNames / FormOf / FormNameOf exist") then
		return
	end
	T.check(BC.FormOf("Blast", 0) == nil and BC.FormOf("Nope", 2) == nil and BC.FormOf("Blast", "x") == nil and BC.FormOf("BossBonus", 1) == nil and BC.FormOf(nil, 1) == nil and BC.FormOf("Blast", 0 / 0) == nil and BC.FormOf("Blast", 0.9) == nil, "evo forms: stage 0 / junk = nil")
	T.check(BC.FormOf("Blast", 1).Aftershock.Share == 0.3 and BC.FormOf("Blast", 1).Patch == nil, "evo forms: stage 1 = the first twist only")
	T.check(BC.FormOf("Blast", 2).Aftershock.Share == 0.3 and BC.FormOf("Blast", 2).Patch.Seconds == 3, "evo forms: stage 2 keeps stage 1")
	T.check(BC.FormOf("Blast", 7).Patch ~= nil and BC.FormOf("Blast", 1.9).Patch == nil, "evo forms: the stage is floored and clamped to 2")
	T.check(BC.FormNameOf("stormfang", "Pounce", 1) == "Shadow Pack" and BC.FormNameOf("stormfang", "Pounce", 2) == "Thunder Pack" and BC.FormNameOf("pebble_pup", "Haste", 2) == nil and BC.FormNameOf("pebble_pup", "Haste", 0) == nil, "evo forms: the spec's names; a once-evolver has no second name")
	T.check(BC.FormNameOf("nope", "Pounce", 1) == "Charge" and BC.FormNameOf("nope", "Pounce", 2) == "Landing" and BC.FormNameOf("nope", "Pounce", 0) == nil and BC.FormNameOf("nope", "Nope", 1) == nil, "evo forms: an unknown pet gets the kind's generic twist name")
	-- the numbers of the spec's tables
	local F = BC.Forms
	T.check(F.BossBonus == 0.1, "evo forms: BossBonus 0.1", tostring(F.BossBonus))
	T.check(F.Pounce[1].Id == "Charge" and F.Pounce[1].Share == 0.5 and F.Pounce[1].Back == 8 and F.Pounce[1].Past == 3 and F.Pounce[2].Id == "Landing" and F.Pounce[2].Share == 0.5 and F.Pounce[2].Radius == 5, "evo forms: Pounce's numbers")
	T.check(F.Blast[1].Delay == 0.6 and F.Blast[2].Id == "Patch" and F.Blast[2].Share == 0.5, "evo forms: Blast's numbers")
	T.check(F.Storm[1].Id == "Winds" and F.Storm[1].Slow == 0.7 and F.Storm[2].Id == "LastStrike" and F.Storm[2].Share == 0.4, "evo forms: Storm's numbers")
	T.check(F.Beam[1].Id == "Mark" and F.Beam[1].Mark == 1.15 and F.Beam[1].Seconds == 4 and F.Beam[2].Id == "Twin" and F.Beam[2].Share == 0.5 and F.Beam[2].Delay == 0.5, "evo forms: Beam's numbers")
	T.check(F.Freeze[1].Id == "Chill" and F.Freeze[1].Slow == 0.6 and F.Freeze[1].Seconds == 3 and F.Freeze[2].Id == "Shatter" and F.Freeze[2].Share == 0.6, "evo forms: Freeze's numbers")
	T.check(F.Heal[1].Id == "Lingering" and F.Heal[1].Share == 0.3 and F.Heal[1].Seconds == 4 and F.Heal[1].Ticks == 4 and F.Heal[2].Id == "Overflow" and F.Heal[2].Cap == 0.5 and F.Heal[2].Seconds == 6, "evo forms: Heal's numbers")
	T.check(F.Shield[1].Id == "Thorns" and F.Shield[1].Share == 0.2 and F.Shield[2].Id == "Burst" and F.Shield[2].Share == 0.6 and F.Shield[2].Radius == 6, "evo forms: Shield's numbers")
	T.check(F.Rally[1].Id == "WarPace" and F.Rally[1].Speed == 0.15 and F.Rally[2].Id == "FiredUp" and F.Rally[2].Meter <= 10, "evo forms: Rally's numbers (Fired up at most 10)")
	T.check(F.Haste[1].Id == "QuickHands" and F.Haste[1].Recharge == 0.75 and F.Haste[2].Id == "DoubleStrike" and F.Haste[2].Chance == 0.2, "evo forms: Haste's numbers")
	-- every catalog pet: Common / Uncommon / Rare exactly one name, Epic+ exactly two, each the spec's
	local tally = T.tally("evo forms: every pet has the spec's form names, one per evolution it can make")
	local pets = 0
	for _, def in ipairs(PC.Pets) do
		pets = pets + 1
		local names, want = BC.FormNames[def.Id], SPEC_NAMES[def.Id]
		local count = PC.EvolveTwice[def.Rarity] and 2 or 1
		tally:case(names ~= nil and want ~= nil and #names == count and names[1] == want[1] and names[2] == want[2], tostring(def.Id))
	end
	tally:report()
	local known = 0
	for _ in pairs(BC.FormNames) do
		known = known + 1
	end
	T.check(pets == 33 and known == 33, "evo forms: 33 pets, 33 FormNames entries", fmt("%d, %d", pets, known))
	T.check(BC.Validate() == true, "evo forms: Validate passes", select(2, BC.Validate()) and tostring(select(2, BC.Validate())[1]))
	-- Validate catches a gap
	local function caught(mutate, restore)
		mutate()
		local ok = BC.Validate()
		restore()
		return ok == false
	end
	local keepName = BC.FormNames.stormfang
	T.check(caught(function()
		BC.FormNames.stormfang = nil
	end, function()
		BC.FormNames.stormfang = keepName
	end), "evo forms: Validate catches a pet with no names")
	T.check(caught(function()
		BC.FormNames.stormfang = { "Only One" }
	end, function()
		BC.FormNames.stormfang = keepName
	end), "evo forms: Validate catches a twice-evolver with one name")
	local keepOnce = BC.FormNames.pebble_pup
	T.check(caught(function()
		BC.FormNames.pebble_pup = { "One", "Two" }
	end, function()
		BC.FormNames.pebble_pup = keepOnce
	end), "evo forms: Validate catches a once-evolver with two names")
	T.check(caught(function()
		BC.FormNames.not_a_pet = { "Ghost" }
	end, function()
		BC.FormNames.not_a_pet = nil
	end), "evo forms: Validate catches a name for no catalog pet")
	local keepTwist = F.Beam[2]
	T.check(caught(function()
		F.Beam[2] = nil
	end, function()
		F.Beam[2] = keepTwist
	end), "evo forms: Validate catches a kind with a missing form")
	T.check(caught(function()
		F.BossBonus = 0.9
	end, function()
		F.BossBonus = 0.1
	end), "evo forms: Validate catches a BossBonus past 0.5")
end)

----------------------------------------------------------------------------------------------------
-- the stage-0 pin: a Duel of unmoved pets, recorded BEFORE any evolved-forms code (Seed 7, 600 steps of 0.1 s); every task keeps it
----------------------------------------------------------------------------------------------------
local DMG1, DMG2, KO_STEPS, REASON = 2499, 2455, "455,461,487,493,499", "Wipe"

S.evo_stage0_pinned = guarded("evo_stage0_pinned", function()
	local BS = req("BattleSim")
	if not T.check(BS ~= nil, "evo stage 0: BattleSim loads") then
		return
	end
	local function side(owner, s)
		return { Owner = owner, Side = s, Auto = true, Pets = {
			{ Key = "aurora_fox", Level = 12, Slot = 1 },
			{ Key = "storm_tabby", Level = 14, Slot = 2 },
			{ Key = "frostling_penguin", Level = 12, Slot = 3 },
		} }
	end
	local b = BS.new({ Mode = "Duel", Seed = 7, Zone = { X = 60, Z = 60 }, Teams = { side(1, 1), side(2, 2) } })
	local koSteps = {}
	for step = 1, 600 do
		for _, ev in ipairs(b:Step(0.1)) do
			if ev.type == "KO" then
				koSteps[#koSteps + 1] = step
			end
		end
	end
	local result = b:Result()
	local d1, d2, ko, reason = floor(b.teams[1].damage), floor(b.teams[2].damage), table.concat(koSteps, ","), result and result.Reason or "none"
	T.check(d1 == DMG1 and d2 == DMG2 and ko == KO_STEPS and reason == REASON, "evo stage 0: the pinned Duel replays byte for byte (damage, KO steps, reason)", fmt("%d %d [%s] %s", d1, d2, ko, tostring(reason)))
end)

----------------------------------------------------------------------------------------------------
-- Pounce
----------------------------------------------------------------------------------------------------
S.evo_pounce = guarded("evo_pounce", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo pounce: the modules load, with FormOf and the Twist event") then
		return
	end
	-- the target, on the way, beside the line, behind the pet (inside the drawn line's start), past the line's end at 15 (a bear's radius
	-- is 2.4: the body's edge rule, so 18)
	local b, f, foes = field(BS, fighter(PC, "Pounce", 1), { { 12, 0 }, { 6, 0 }, { 6, 7.5 }, { -5, 0 }, { 18, 0 } })
	local ev, evs = special(b, f, foes[1])
	T.check(ev ~= nil and ev.form == 1 and near(ev.x0, -8, 0.6) and near(ev.z0, 0, 1e-6) and near(ev.angle, 0, 1e-3) and near(ev.length, 8 + 12 + 3, 0.6) and near(ev.width, 4 * 1.15, 1e-6),
		"evo pounce: the charge line is drawn from 8 behind the pet through the target to 3 past it, Beam width x reach",
		ev and fmt("x0 %s z0 %s angle %s length %s width %s", tostring(ev.x0), tostring(ev.z0), tostring(ev.angle), tostring(ev.length), tostring(ev.width)))
	local function count(i)
		return #hitsOn(evs, foes[i].id)
	end
	T.check(count(1) == 1 and count(2) == 1 and count(3) == 0 and count(4) == 1 and count(5) == 0, "evo pounce: the target, the enemy on the way and the one behind the pet inside the line are hit; beside the line and past its end are not",
		fmt("%d %d %d %d %d", count(1), count(2), count(3), count(4), count(5)))
	local full, half = dealt(hitsOn(evs, foes[1].id)), dealt(hitsOn(evs, foes[2].id))
	T.check(half < full and near(half / full, 0.5, 0.25), "evo pounce: the on-the-way enemy takes half (within variance)", fmt("%d / %d", half, full))
	local charge = hitsOn(evs, foes[2].id)[1]
	T.check(charge ~= nil and charge.twist == "Charge" and has(ev.targets, foes[2].id) and has(ev.targets, foes[4].id) and ev.targets[1] == foes[1].id and not has(ev.targets, foes[3].id), "evo pounce: Hit.twist Charge, targets = the target first then the line")
	T.check(hitsOn(evs, foes[1].id)[1].twist == nil, "evo pounce: the target keeps today's plain full hit")
	T.check(f.x == 0 and f.z == 0, "evo pounce: a PLAYER fighter does not move", fmt("%.2f, %.2f", f.x, f.z))
	T.check(ev.x == 0 and ev.z == 0 and ev.tx == 12, "evo pounce: the event still names the caster and the target")

	-- the floor's edge: the start is clamped, the line still reaches 3 past the target
	b, f, foes = field(BS, fighter(PC, "Pounce", 1), { { 5, 0 }, { -9.5, 0 } }, { Zone = { X = 20, Z = 60 } })
	f.x, f.px = -9, -9
	ev, evs = special(b, f, foes[1])
	T.check(ev ~= nil and ev.x0 >= -10 + f.radius - 0.05 and near(ev.x0 + ev.length, 8, 0.1), "evo pounce: the start is clamped to the floor, the line still reaches 3 past the target", ev and fmt("x0 %s length %s", tostring(ev.x0), tostring(ev.length)))
	T.check(#hitsOn(evs, foes[2].id) == 1, "evo pounce: ...and a bear behind the clamped start, its body inside the line, is hit")
	-- clamped on one axis, off the target's axis: the line is re-aimed, it still runs through the target
	b, f, foes = field(BS, fighter(PC, "Pounce", 1), { { 5, 3 } }, { Zone = { X = 20, Z = 60 } })
	f.x, f.px = -9, -9
	ev = special(b, f, foes[1])
	if T.check(ev ~= nil and ev.x0 ~= nil, "evo pounce: the off-axis clamped cast has a line") then
		local dirX, dirZ = math.cos(ev.angle), math.sin(ev.angle)
		local dx, dz = 5 - ev.x0, 3 - ev.z0
		local along, perp = dx * dirX + dz * dirZ, abs(dx * dirZ - dz * dirX)
		T.check(perp <= 0.2 and near(ev.length - along, 3, 0.3), "evo pounce: a clamped line is re-aimed through the target and ends 3 past it", fmt("perp %.2f, past %.2f", perp, ev.length - along))
	end

	-- Evo 2: the landing burst
	b, f, foes = field(BS, fighter(PC, "Pounce", 2), { { 12, 0 }, { 15, 0 } })
	ev, evs = special(b, f, foes[1])
	local landing = twistHits(evs, foes[2].id, "Landing")
	T.check(ev ~= nil and ev.form == 2 and ev.burstR == r1(5 * 1.3) and has(ev.burstTargets, foes[2].id) and not has(ev.burstTargets, foes[1].id), "evo pounce: Evo 2 names its burst radius and targets", ev and tostring(ev.burstR))
	T.check(#landing == 1 and near(landing[1].dmg / dealt(hitsOn(evs, foes[1].id)), 0.5, 0.25), "evo pounce: a bear 3 past the target takes a Landing hit near half", landing[1] and tostring(landing[1].dmg))
	T.check(#hitsOn(evs, foes[1].id) == 1, "evo pounce: the target itself takes ONE hit (no Landing on it)")
	T.check(#twistHits(evs, foes[2].id, "Charge") == 1, "evo pounce: stage 2 keeps the Charge")
	-- outside the burst and the line
	b, f, foes = field(BS, fighter(PC, "Pounce", 2), { { 12, 0 }, { 12, 9.5 } })
	ev, evs = special(b, f, foes[1])
	T.check(#hitsOn(evs, foes[2].id) == 0 and not has(ev.burstTargets, foes[2].id), "evo pounce: a bear past the burst's edge is not hit")

	-- Evo 0: today
	b, f, foes = field(BS, fighter(PC, "Pounce", 0), { { 12, 0 }, { 6, 0 }, { -5, 0 } })
	ev, evs = special(b, f, foes[1])
	T.check(ev ~= nil and ev.x0 == nil and ev.z0 == nil and ev.form == nil and ev.burstR == nil and ev.angle == nil and ev.length == nil and ev.width == nil, "evo pounce: Evo 0 has no x0 / form / burstR on the event")
	T.check(#hitsOn(evs, foes[1].id) == 1 and #hitsOn(evs, foes[2].id) == 0 and #hitsOn(evs, foes[3].id) == 0 and #ev.targets == 1, "evo pounce: Evo 0 hits only the target (today)")

	-- an NPC Pounce still moves (today); its line starts behind where it stood
	local npc = { Def = withSpecial(PC, LEG, "Pounce"), Key = LEG, Level = 50, Evo = 1, Slot = 1 }
	local nb = BS.new({ Mode = "Duel", Seed = 9, Zone = { X = 160, Z = 160 }, TimeLimit = 300,
		Teams = { { Owner = 1, Side = 1, Pets = { { Key = "biscuit_bear", Level = 40, NoSpecial = true, Slot = 1 } } }, { Owner = "npc", Side = 2, Npc = true, Pets = { npc } } } })
	local me = standFighter(nb.teams[1], 0, 0)
	local cast, enemy = nil, nil
	for _, u in ipairs(nb.units) do
		if u.side == 2 then
			enemy = u
			u.x, u.z, u.px, u.pz = 20, 0, 20, 0
		end
	end
	for _ = 1, 100 do
		enemy.meter = 100
		enemy.x, enemy.z = cast and enemy.x or 20, cast and enemy.z or 0
		cast = findEvent(nb:Step(0.1), "Special")
		if cast then
			break
		end
	end
	T.check(cast ~= nil and cast.form == 1 and near(enemy.x, 0, me.radius + enemy.radius + 1), "evo pounce: an NPC Pounce still moves to its target", cast and fmt("%.1f", enemy.x))
	T.check(cast ~= nil and near(cast.x0, cast.x + 8, 0.2), "evo pounce: ...and its line starts 8 behind where it stood", cast and fmt("x0 %s, x %s", tostring(cast.x0), tostring(cast.x)))
end)

----------------------------------------------------------------------------------------------------
-- Blast
----------------------------------------------------------------------------------------------------
S.evo_blast = guarded("evo_blast", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo blast: the modules load") then
		return
	end
	local b, f, foes = field(BS, fighter(PC, "Blast", 1), { { 20, 0 }, { 20, 4 }, { 60, 0 } })
	local ev, evs = special(b, f, foes[1])
	local base = baseOf(BC, f, "Blast")
	local first = hitsOn(evs, foes[1].id)[1]
	T.check(ev ~= nil and ev.form == 1 and first ~= nil and first.twist == nil and near(first.dmg / onFoe(base, foes[1], first), 1, 0.21), "evo blast: the first hit's number is unchanged", first and fmt("%d of %.1f", first.dmg, onFoe(base, foes[1], first)))
	T.check(#twists(evs, "Aftershock") == 0, "evo blast: no Aftershock at the cast")
	local later = run(b, 0.7)
	local tw = twists(later, "Aftershock")
	T.check(#tw == 1 and tw[1].kind == "Blast" and tw[1].unit == f.id and tw[1].x == 20 and tw[1].z == 0 and near(tw[1].r, 7 * 1.15, 0.06) and has(tw[1].targets, foes[1].id) and has(tw[1].targets, foes[2].id) and not has(tw[1].targets, foes[3].id),
		"evo blast: a Twist Aftershock at the original point, 0.6 s later", tw[1] and fmt("%s, %s, r %s", tostring(tw[1].x), tostring(tw[1].z), tostring(tw[1].r)))
	local a1, a2 = twistHits(later, foes[1].id, "Aftershock"), twistHits(later, foes[2].id, "Aftershock")
	T.check(#a1 == 1 and #a2 == 1 and near(a1[1].dmg / first.dmg, 0.3, 0.13) and #hitsOn(later, foes[3].id) == 0, "evo blast: a second Hit near 0.3 x on every bear in the circle", a1[1] and fmt("%d after %d", a1[1].dmg, first.dmg))
	T.check(#twists(later, "Patch") == 0 and findEvent(later, "Zone") == nil and findEvent(evs, "Zone") == nil, "evo blast: Evo 1 leaves no patch")

	-- Evo 2: burning ground
	b, f, foes = field(BS, fighter(PC, "Blast", 2), { { 20, 0 }, { 60, 0 } })
	ev, evs = special(b, f, foes[1])
	base = baseOf(BC, f, "Blast")
	local zoneEv = findEvent(evs, "Zone")
	T.check(zoneEv ~= nil and zoneEv.kind == "Patch" and zoneEv.special == "Blast" and zoneEv.seconds == 3 and near(zoneEv.r, 7 * 1.3, 0.051) and zoneEv.side == 1 and zoneEv.unit == f.id and zoneEv.x == 20, "evo blast: Evo 2 sends a Zone kind Patch", zoneEv and fmt("%s %s %s", tostring(zoneEv.kind), tostring(zoneEv.special), tostring(zoneEv.r)))
	local rest = run(b, 3.4)
	local ticks = hitsOn(rest, foes[1].id, function(h)
		return h.zone == true
	end)
	T.check(#ticks >= 5 and #ticks <= 6, "evo blast: zone Hits for 3 s", tostring(#ticks))
	T.check(near(dealt(ticks) / onFoe(base * 0.5, foes[1], ticks[1]), 1, 0.2), "evo blast: ...total near 0.5 x", fmt("%d of %.1f", dealt(ticks), onFoe(base * 0.5, foes[1], ticks[1])))
	T.check(#hitsOn(rest, foes[2].id) == 0, "evo blast: nothing on a bear away from the patch")
	T.check(#b.zones == 0 and #hitsOn(run(b, 1), foes[1].id) == 0, "evo blast: none after")
	T.check(#twists(rest, "Aftershock") == 1, "evo blast: stage 2 keeps the Aftershock")

	-- a second Blast 1 s later replaces the pet's patch
	local function patches(battle, unit)
		local n = 0
		for _, z in ipairs(battle.zones) do
			if z.kind == "Patch" and (unit == nil or z.from == unit) then
				n = n + 1
			end
		end
		return n
	end
	b, f, foes = field(BS, fighter(PC, "Blast", 2), { { 20, 0 } })
	special(b, f, foes[1])
	run(b, 1)
	special(b, f, foes[1])
	T.check(patches(b, f) == 1, "evo blast: a second Blast replaces the pet's own last patch", tostring(patches(b, f)))
	-- another pet's patch stacks: a bear in both takes both
	b, f, foes = field(BS, fighter(PC, "Blast", 2), { { 20, 0 } }, { Ally = fighter(PC, "Blast", 2) })
	local ally = b.teams[3].fighter
	special(b, f, foes[1])
	special(b, ally, foes[1], 2)
	T.check(patches(b) == 2, "evo blast: another pet's patch stacks", tostring(patches(b)))
	local both = run(b, 0.6)
	local mine, theirs = 0, 0
	for _, h in ipairs(hitsOn(both, foes[1].id, function(h)
		return h.zone == true
	end)) do
		mine = mine + ((h.from == f.id) and 1 or 0)
		theirs = theirs + ((h.from == ally.id) and 1 or 0)
	end
	T.check(mine >= 1 and theirs >= 1, "evo blast: a bear in both patches takes both", fmt("%d, %d", mine, theirs))
end)

----------------------------------------------------------------------------------------------------
-- Storm
----------------------------------------------------------------------------------------------------
S.evo_storm = guarded("evo_storm", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo storm: the modules load") then
		return
	end
	local b, f, foes = field(BS, fighter(PC, "Storm", 1), { { 20, 0 }, { 60, 0 } })
	local _, evs, t0 = special(b, f, foes[1])
	local base = baseOf(BC, f, "Storm")
	local zone = b.zones[#b.zones]
	T.check(zone ~= nil and near(zone.dps, base / 4, 1e-6), "evo storm: the zone's damage per tick is today's", zone and fmt("%.2f / %.2f", zone.dps, base / 4))
	run(b, 0.6, evs)
	T.check(foes[1].slowMult == 0.7 and foes[1].slowUntil > b:Time(), "evo storm: a bear inside the zone is 30% slower within 0.6 s", fmt("%s until %.2f at %.2f", tostring(foes[1].slowMult), foes[1].slowUntil, b:Time()))
	T.check(foes[2].slowMult == 1 and foes[2].slowUntil == 0, "evo storm: a bear outside keeps its speed")
	-- it wears off soon after the bear leaves
	foes[1].x, foes[1].px = 60, 60
	foes[1].z, foes[1].pz = 40, 40
	run(b, 0.8, evs)
	T.check(foes[1].slowMult == 1 and foes[1].slowUntil <= b:Time(), "evo storm: the slow ends once the bear is out", tostring(foes[1].slowMult))
	T.check(#twists(evs, "LastStrike") == 0, "evo storm: Evo 1 has no Last strike")
	run(b, 4, evs)
	T.check(#twists(evs, "LastStrike") == 0, "evo storm: ...nor at the zone's end")

	-- Evo 2: the last strike on all still inside
	b, f, foes = field(BS, fighter(PC, "Storm", 2), { { 20, 0 }, { 20, 5 }, { 60, 0 } })
	_, evs, t0 = special(b, f, foes[1])
	base = baseOf(BC, f, "Storm")
	run(b, 2, evs)
	foes[2].x, foes[2].px = 60, 60
	foes[2].z, foes[2].pz = 30, 30
	run(b, 1.5, evs)
	T.check(#twists(evs, "LastStrike") == 0, "evo storm: no Last strike before the zone's end")
	run(b, 0.7, evs)
	local tw = twists(evs, "LastStrike")
	T.check(#tw == 1 and tw[1].kind == "Storm" and near(tw[1].r, 6 * 1.3, 0.051) and tw[1].x == 20 and has(tw[1].targets, foes[1].id) and not has(tw[1].targets, foes[2].id), "evo storm: at the zone's end a Twist LastStrike", tw[1] and tostring(tw[1].r))
	local strike = twistHits(evs, foes[1].id, "LastStrike")
	T.check(#strike == 1 and near(strike[1].dmg / onFoe(base * 0.4, foes[1], strike[1]), 1, 0.21), "evo storm: one Hit near 0.4 x the Storm's WHOLE damage", strike[1] and fmt("%d of %.1f", strike[1].dmg, onFoe(base * 0.4, foes[1], strike[1])))
	T.check(#twistHits(evs, foes[2].id, "LastStrike") == 0 and #twistHits(evs, foes[3].id, "LastStrike") == 0, "evo storm: none on one that left or never was inside")
	T.check(foes[1].slowUntil > t0, "evo storm: stage 2 keeps the Dragging winds")
	-- a fallen caster's Last strike is dropped; a benched one's too
	b, f, foes = field(BS, fighter(PC, "Storm", 2), { { 20, 0 } }, { Bench = { benchPet() } })
	_, evs = special(b, f, foes[1])
	f.hp = 1
	zap(b, f, foes[1])
	run(b, 4.5, evs)
	T.check(f.alive == false and #twists(evs, "LastStrike") == 0, "evo storm: a caster KO'd before the end: no LastStrike")
	b, f, foes = field(BS, fighter(PC, "Storm", 2), { { 20, 0 } }, { Bench = { benchPet() } })
	_, evs = special(b, f, foes[1])
	run(b, 0.6, evs)
	local swapped = b:Command(1, "Swap", 2)
	run(b, 4, evs)
	T.check(swapped == true and #twists(evs, "LastStrike") == 0, "evo storm: a caster swapped to the bench: no LastStrike")
end)

----------------------------------------------------------------------------------------------------
-- Beam
----------------------------------------------------------------------------------------------------
S.evo_beam = guarded("evo_beam", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo beam: the modules load") then
		return
	end
	local b, f, foes = field(BS, fighter(PC, "Beam", 1), { { 5, 0 }, { 12, 0 }, { 12, 20 } })
	local ev, evs, t0 = special(b, f, foes[1])
	T.check(ev ~= nil and ev.form == 1, "evo beam: Evo 1 on the event")
	T.check(foes[1].markMult == 1.15 and foes[2].markMult == 1.15 and near(foes[1].markUntil, t0 + 4, 1e-6) and near(foes[2].markUntil, t0 + 4, 1e-6), "evo beam: each bear in the line has markMult 1.15 for 4 s", fmt("%s until %.2f", tostring(foes[1].markMult), foes[1].markUntil))
	T.check(foes[3].markMult == 1 and foes[3].markUntil == 0, "evo beam: a bear off the line has no mark")
	run(b, 1, evs)
	local _, _, t1 = special(b, f, foes[1])
	T.check(foes[1].markMult == 1.15 and near(foes[1].markUntil, t1 + 4, 1e-6), "evo beam: a second Beam does not stack (1.15, the later until)", tostring(foes[1].markMult))
	T.check(#twists(evs, "Twin") == 0 and #twists(run(b, 1), "Twin") == 0, "evo beam: Evo 1 has no Twin")
	-- Mark x Stone Skin (the ally Taken buff): neither overwrites the other. One no-variance zone over three identical bears
	b, f, foes = field(BS, fighter(PC, "Beam", 0), { { 20, -10 }, { 20, 0 }, { 20, 10 } })
	local now = b:Time()
	foes[2].markMult, foes[2].markUntil = 1.15, now + 5
	foes[3].markMult, foes[3].markUntil = 1.15, now + 5
	foes[3].takenMult, foes[3].takenUntil = 0.65, now + 5
	b.zones[#b.zones + 1] = { x = 20, z = 0, r = 12, dps = 20000, untilT = now + 0.3, nextTick = now, side = 1, from = f, kind = "Storm" }
	evs = b:Step(0.05)
	local plain, marked, both = hitsOn(evs, foes[1].id)[1], hitsOn(evs, foes[2].id)[1], hitsOn(evs, foes[3].id)[1]
	T.check(plain ~= nil and marked ~= nil and near(marked.dmg / plain.dmg, 1.15, 0.01), "evo beam: a hit on a marked bear deals x1.15", marked and fmt("%d / %d", marked.dmg, plain.dmg))
	T.check(both ~= nil and near(both.dmg / plain.dmg, 1.15 * 0.65, 0.01), "evo beam: a marked, Stone-Skinned bear: x0.65 x 1.15, neither overwrites the other", both and fmt("%d / %d", both.dmg, plain.dmg))

	-- Evo 2: the Twin, from where the caster stands THEN, along the original angle
	b, f, foes = field(BS, fighter(PC, "Beam", 2), { { 10, 0 }, { 10, 20 }, { -10, 20 } })
	ev, evs = special(b, f, foes[1])
	f.x, f.z, f.px, f.pz = 0, 20, 0, 20
	b.teams[1].wantX, b.teams[1].wantZ = 0, 20
	local before = dealt(hitsOn(evs, foes[1].id))
	T.check(#twists(evs, "Twin") == 0, "evo beam: no Twin at the cast")
	local later = run(b, 0.5)
	local tw = twists(later, "Twin")
	T.check(#tw == 1 and tw[1].kind == "Beam" and tw[1].angle == ev.angle and tw[1].x == 0 and tw[1].z == 20 and tw[1].length == r1(26 * 1.3) and tw[1].width == r1(4 * 1.3), "evo beam: 0.5 s after the cast a Twist Twin from the caster's position THEN, along the original angle",
		tw[1] and fmt("%s %s %s %s %s", tostring(tw[1].x), tostring(tw[1].z), tostring(tw[1].angle), tostring(tw[1].length), tostring(tw[1].width)))
	local twin = twistHits(later, foes[2].id, "Twin")
	T.check(#twin == 1 and has(tw[1].targets, foes[2].id) and near(twin[1].dmg / before, 0.5, 0.25), "evo beam: 0.5 x on every bear in the new line", twin[1] and fmt("%d / %d", twin[1].dmg, before))
	T.check(#twistHits(later, foes[1].id, "Twin") == 0 and #twistHits(later, foes[3].id, "Twin") == 0, "evo beam: the old line's bear and the one behind the caster are not hit")
	T.check(foes[1].markMult == 1.15, "evo beam: stage 2 keeps the Mark")
	-- an aimed angle off the axis: three decimals on the wire
	b, f, foes = field(BS, fighter(PC, "Beam", 2), { { 10, 7 } })
	special(b, f, foes[1])
	tw = twists(run(b, 0.6), "Twin")
	T.check(#tw == 1 and tw[1].angle == floor(atan2(7, 10) * 1000 + 0.5) / 1000, "evo beam: the Twin's angle has three decimals", tw[1] and tostring(tw[1].angle))
end)

----------------------------------------------------------------------------------------------------
-- Freeze
----------------------------------------------------------------------------------------------------
S.evo_freeze = guarded("evo_freeze", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo freeze: the modules load") then
		return
	end
	local b, f, foes = field(BS, fighter(PC, "Freeze", 1), { { 20, 0 }, { 20, 5 }, { 60, 0 } })
	local ev, evs, t0 = special(b, f, foes[1])
	local stun = 0.8 * (f.specialFactor or 1)
	T.check(ev ~= nil and ev.form == 1 and near(foes[1].stunUntil - t0, stun, 1e-6) and has(ev.stunned, foes[2].id) and foes[1].slowMult == 1, "evo freeze: the bears are stunned for today's 0.8, not slowed yet", fmt("%.2f", foes[1].stunUntil - t0))
	local later = run(b, stun + 0.05)
	local tw = twists(later, "Chill")
	T.check(#tw == 1 and tw[1].kind == "Freeze" and has(tw[1].targets, foes[1].id) and has(tw[1].targets, foes[2].id) and not has(tw[1].targets, foes[3].id), "evo freeze: at the thaw a Twist Chill")
	T.check(foes[1].slowMult == 0.6 and foes[2].slowMult == 0.6 and foes[3].slowMult == 1 and near(foes[1].slowUntil - t0, stun + 3, 0.11), "evo freeze: each thawed bear is 40% slower for 3 s", fmt("%s until +%.2f", tostring(foes[1].slowMult), foes[1].slowUntil - t0))
	T.check(#twists(later, "Shatter") == 0, "evo freeze: Evo 1 has no Shatter")
	run(b, 3.1)
	T.check(foes[1].slowMult == 1, "evo freeze: the chill ends", tostring(foes[1].slowMult))

	-- Evo 2: the shatter at the ORIGINAL point
	b, f, foes = field(BS, fighter(PC, "Freeze", 2), { { 20, 0 }, { 20, 5 }, { 26, 0 } })
	ev, evs, t0 = special(b, f, foes[1])
	local base = baseOf(BC, f, "Freeze")
	local stunned = has(ev.stunned, foes[3].id)
	foes[2].x, foes[2].px = 60, 60 -- pushed out of it before the thaw
	foes[1].x, foes[1].px = 21, 21 -- moved a little: still within r of the original point
	later = run(b, stun + 0.05)
	tw = twists(later, "Shatter")
	T.check(#tw == 1 and tw[1].kind == "Freeze" and tw[1].x == 20 and tw[1].z == 0 and near(tw[1].r, 6 * 1.3, 0.051) and stunned, "evo freeze: at t + 0.8 a Twist Shatter at the original point", tw[1] and fmt("%s %s %s", tostring(tw[1].x), tostring(tw[1].z), tostring(tw[1].r)))
	local sh = twistHits(later, foes[1].id, "Shatter")
	T.check(#sh == 1 and near(sh[1].dmg / onFoe(base * 0.6, foes[1], sh[1]), 1, 0.21), "evo freeze: 0.6 x on a bear within r of the original point", sh[1] and fmt("%d of %.1f", sh[1].dmg, onFoe(base * 0.6, foes[1], sh[1])))
	T.check(#twistHits(later, foes[2].id, "Shatter") == 0, "evo freeze: a bear pushed out of it before: not hit")
	T.check(#twists(later, "Chill") == 1, "evo freeze: stage 2 keeps the Chill")
end)

----------------------------------------------------------------------------------------------------
-- Heal
----------------------------------------------------------------------------------------------------
S.evo_heal = guarded("evo_heal", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo heal: the modules load") then
		return
	end
	local function healer(evo)
		local b, f, foes = field(BS, fighter(PC, "Heal", evo), { { 40, 0 } }, { Bench = { benchPet() } })
		local mate = nil
		for _, u in ipairs(b.teams[1].units) do
			if u ~= f then
				mate = u
			end
		end
		mate.maxHp, mate.hp = 1e7, 1e7
		return b, f, mate, foes
	end
	local function healOf(heals, id)
		for _, h in ipairs(heals or {}) do
			if h[1] == id then
				return h[2]
			end
		end
		return nil
	end
	-- Evo 1, hurt: the cast heals H, then 4 ticks of 0.3 x H / 4 on the fighter AND the bench
	local b, f, mate = healer(1)
	f.hp, mate.hp = 3e6, 3e6
	local ev, evs = special(b, f, nil)
	local H = baseOf(BC, f, "Heal") * BC.Specials.Heal.Solo
	T.check(ev ~= nil and ev.form == 1 and near(healOf(ev.heals, f.id), H, 1) and near(healOf(ev.heals, mate.id), H, 1), "evo heal: the cast heals today's amount", ev and tostring(healOf(ev.heals, f.id)))
	T.check(#twists(evs, "Lingering") == 0, "evo heal: no tick at the cast")
	run(b, 0.9, evs)
	T.check(#twists(evs, "Lingering") == 0, "evo heal: ...nor under a second later")
	run(b, 3.2, evs)
	local ticks = twists(evs, "Lingering")
	T.check(#ticks == 4, "evo heal: 4 Lingering ticks", tostring(#ticks))
	local tick = H * 0.3 / 4
	T.check(ticks[1] ~= nil and ticks[1].kind == "Heal" and near(healOf(ticks[1].heals, f.id), tick, 1) and near(healOf(ticks[1].heals, mate.id), tick, 1), "evo heal: each tick near 0.3 x H / 4 on the fighter AND the bench", ticks[1] and tostring(healOf(ticks[1].heals, f.id)))
	T.check(near(f.hp, 3e6 + H * 1.3, 2), "evo heal: 30% more healing in all", fmt("%.1f", f.hp - 3e6 - H * 1.3))
	run(b, 1.5, evs)
	T.check(#twists(evs, "Lingering") == 4, "evo heal: none after 4")
	T.check(#twists(evs, "Overflow") == 0 and f.shield == 0, "evo heal: Evo 1 has no Overflow")
	-- ticks are capped by the unit's own missing health
	b, f, mate = healer(1)
	f.hp, mate.hp = 3e6, 3e6
	special(b, f, nil)
	f.hp = f.maxHp - 1
	local capped = run(b, 1.1)
	T.check(f.hp <= f.maxHp and near(healOf(twists(capped, "Lingering")[1].heals, f.id), 1, 1), "evo heal: a tick never heals past max")
	-- a KO'd or benched caster's ticks stop
	b, f, mate = healer(1)
	f.hp, mate.hp = 3e6, 3e6
	local foes = {}
	for _, u in ipairs(b.units) do
		if u.side == 2 then
			foes[#foes + 1] = u
		end
	end
	evs = select(2, special(b, f, nil))
	f.hp = 1
	zap(b, f, foes[1])
	run(b, 5, evs)
	T.check(f.alive == false and #twists(evs, "Lingering") == 0, "evo heal: a KO'd caster: ticks stop", tostring(#twists(evs, "Lingering")))
	b, f, mate = healer(1)
	f.hp, mate.hp = 3e6, 3e6
	evs = select(2, special(b, f, nil))
	run(b, 0.6, evs)
	local swapped = b:Command(1, "Swap", 2)
	run(b, 5, evs)
	T.check(swapped == true and #twists(evs, "Lingering") == 0, "evo heal: a caster swapped to the bench: ticks stop", tostring(#twists(evs, "Lingering")))
	-- a fighter at full health: Evo 1 has nothing to tick
	b, f, mate = healer(1)
	evs = select(2, special(b, f, nil))
	run(b, 5, evs)
	T.check(#twists(evs, "Lingering") == 0, "evo heal: nobody healed, no ticks")

	-- Evo 2: Overflow
	b, f, mate = healer(2)
	local t0 = b:Time()
	f.hp = f.maxHp - 10
	ev, evs = special(b, f, nil)
	H = baseOf(BC, f, "Heal") * BC.Specials.Heal.Solo
	local over = twists(evs, "Overflow")
	T.check(near(f.shield, math.min(H - 10, H * 0.5), 1e-6) and near(f.shieldUntil, t0 + 6, 1e-6), "evo heal: 10 HP under max: the wasted part becomes a shield, at most half the heal, 6 s", fmt("%.1f of %.1f until %.2f", f.shield, H, f.shieldUntil))
	T.check(#over == 1 and over[1].kind == "Heal" and has(over[1].shields, f.id) and near(over[1].amount, H * 0.5, 1), "evo heal: Twist Overflow { shields, amount }", over[1] and tostring(over[1].amount))
	b, f, mate = healer(2)
	f.hp = f.maxHp - H * 0.8
	special(b, f, nil)
	T.check(near(f.shield, H * 0.2, 1), "evo heal: only the wasted part: under the cap it is the waste", fmt("%.1f of %.1f", f.shield, H))
	b, f, mate = healer(2)
	special(b, f, nil)
	T.check(near(f.shield, H * 0.5, 1e-6) and near(mate.shield, H * 0.5, 1e-6), "evo heal: at full HP: shield = 0.5 x H (the bench's heal too)", fmt("%.1f", f.shield))
	b, f, mate = healer(2)
	f.shield, f.shieldUntil = H, b:Time() + 2
	local keepUntil = f.shieldUntil
	special(b, f, nil)
	T.check(f.shield == H and f.shieldUntil == keepUntil, "evo heal: a larger shield stands")
	b, f, mate = healer(2)
	f.hp, mate.hp = 3e6, 3e6
	evs = select(2, special(b, f, nil))
	T.check(f.shield == 0 and #twists(evs, "Overflow") == 0, "evo heal: a heal that all lands leaves no shield and no Twist")
	run(b, 1.1, evs)
	T.check(#twists(evs, "Lingering") == 1, "evo heal: stage 2 keeps the Lingering")
end)

----------------------------------------------------------------------------------------------------
-- Shield
----------------------------------------------------------------------------------------------------
S.evo_shield = guarded("evo_shield", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo shield: the modules load") then
		return
	end
	-- a bear in reach lands one hit on the fighter (its wind-up is 0.45 s): every event of those steps
	local function bearHits(b, f, bear)
		bear.hit = 1000
		bear.target, bear.retargetAt, bear.nextAttack = f, huge, 0
		local evs = run(b, 0.6)
		bear.nextAttack = huge
		return evs
	end
	local b, f, foes = field(BS, fighter(PC, "Shield", 1), { { 4, 0 } })
	local ev, evs = special(b, f, foes[1])
	T.check(ev ~= nil and ev.form == 1 and f.shield > 0 and f.thorns ~= nil and f.shieldForm == nil, "evo shield: Evo 1 gives Thorns", f.shield and tostring(f.shield))
	f.shield = 1e6
	local later = bearHits(b, f, foes[1])
	local blocked = hitsOn(later, f.id)[1]
	local thorn = hitsOn(later, foes[1].id, function(h)
		return h.thorns == true
	end)[1]
	T.check(blocked ~= nil and blocked.absorbed ~= nil and blocked.absorbed > 0, "evo shield: the bear's hit is absorbed", blocked and tostring(blocked.absorbed))
	T.check(thorn ~= nil and thorn.from == f.id and near(thorn.dmg, onFoe(blocked.absorbed * 0.2, foes[1], thorn), 1.5), "evo shield: a Hit { thorns = true, from = the fighter } of 0.2 x the absorbed amount, no variance",
		thorn and fmt("%d of %.1f", thorn.dmg, onFoe(blocked.absorbed * 0.2, foes[1], thorn)))
	T.check(thorn ~= nil and thorn.crit == nil, "evo shield: Thorns never crit")
	-- a Thorns hit absorbed by a Thorns shield reflects nothing
	b, f, foes = field(BS, fighter(PC, "Shield", 1), { { 4, 0 } })
	special(b, f, foes[1])
	f.shield = 1e6
	foes[1].shield, foes[1].shieldUntil, foes[1].thorns = 1e6, b:Time() + 60, { from = foes[1], share = 0.2 }
	later = bearHits(b, f, foes[1])
	T.check(#hitsOn(later, foes[1].id, function(h)
		return h.thorns == true
	end) == 1 and #hitsOn(later, f.id, function(h)
		return h.thorns == true
	end) == 0, "evo shield: a Thorns hit never reflects a Thorns hit")
	-- Thorns end with the shield: run out, or broken
	b, f, foes = field(BS, fighter(PC, "Shield", 1), { { 4, 0 } })
	special(b, f, foes[1])
	run(b, 6.1)
	T.check(f.shield == 0 and f.thorns == nil, "evo shield: Thorns end with a shield that ran out")
	later = bearHits(b, f, foes[1])
	T.check(#hitsOn(later, f.id) >= 1 and #hitsOn(later, foes[1].id) == 0, "evo shield: ...and a hit after it reflects nothing")
	b, f, foes = field(BS, fighter(PC, "Shield", 1), { { 4, 0 } })
	special(b, f, foes[1])
	f.shield = 1
	later = bearHits(b, f, foes[1])
	T.check(f.shield == 0 and f.thorns == nil and #twists(later, "Burst") == 0, "evo shield: Thorns end with a broken shield; Evo 1 never bursts")

	-- Evo 2: Burst, on the break
	b, f, foes = field(BS, fighter(PC, "Shield", 2), { { 4, 0 }, { 7, 4 }, { 30, 0 } })
	ev, evs = special(b, f, foes[1])
	local base = baseOf(BC, f, "Shield")
	T.check(ev ~= nil and ev.form == 2 and f.shieldForm ~= nil and f.thorns ~= nil, "evo shield: Evo 2 keeps Thorns and adds the Burst")
	f.shield = 1
	later = bearHits(b, f, foes[1])
	local tw = twists(later, "Burst")
	T.check(#tw == 1 and tw[1].kind == "Shield" and near(tw[1].r, 6 * 1.3, 0.051) and tw[1].x == 0 and tw[1].z == 0, "evo shield: the shield breaks under a hit: ONE Twist Burst", tw[1] and tostring(tw[1].r))
	local burst = twistHits(later, foes[2].id, "Burst")
	T.check(#burst == 1 and near(burst[1].dmg / onFoe(base * 0.6, foes[2], burst[1]), 1, 0.21) and has(tw[1].targets, foes[1].id) and has(tw[1].targets, foes[2].id), "evo shield: 0.6 x base on every bear within r", burst[1] and fmt("%d of %.1f", burst[1].dmg, onFoe(base * 0.6, foes[2], burst[1])))
	T.check(#twistHits(later, foes[3].id, "Burst") == 0, "evo shield: a bear past r is not hit")
	T.check(f.shieldForm == nil and f.thorns == nil and #twists(run(b, 7), "Burst") == 0, "evo shield: it fires once")
	-- on the end, unbroken
	b, f, foes = field(BS, fighter(PC, "Shield", 2), { { 9, 0 } })
	local _, _, t0 = special(b, f, foes[1])
	later = run(b, 5.8)
	T.check(#twists(later, "Burst") == 0, "evo shield: no burst while the shield holds")
	run(b, 0.3, later)
	T.check(#twists(later, "Burst") == 1 and #twistHits(later, foes[1].id, "Burst") == 1 and near(f.shieldUntil, t0 + 6, 1e-6), "evo shield: a shield that expires unbroken bursts at shieldUntil")
	-- a KO'd shielded unit never bursts
	b, f, foes = field(BS, fighter(PC, "Shield", 2), { { 4, 0 } }, { Bench = { benchPet() } })
	evs = select(2, special(b, f, foes[1]))
	f.shield, f.hp = 1, 1
	zap(b, f, foes[1])
	run(b, 0.2, evs)
	T.check(f.alive == false and f.shieldForm == nil and f.thorns == nil and #twists(evs, "Burst") == 0, "evo shield: a hit that breaks the shield AND knocks the unit out: no burst")
	-- a shield that breaks and expires in the same step bursts once (either order: the step's order is seeded)
	local tally = T.tally("evo shield: a shield that breaks and expires in the same step bursts once")
	for seed = 1, 8 do
		b, f, foes = field(BS, fighter(PC, "Shield", 2), { { 4, 0 } }, { Seed = seed })
		special(b, f, foes[1])
		run(b, 1)
		local now = b:Time()
		f.shield, f.shieldUntil = 1, now + 0.05
		foes[1].hit, foes[1].windAt, foes[1].windTarget = 1000, now + 0.05, f
		later = b:Step(0.05)
		tally:case(#twists(later, "Burst") == 1 and f.shield == 0, fmt("seed %d: %d bursts", seed, #twists(later, "Burst")))
	end
	tally:report()
	-- a new Shield cast replaces shieldForm: one burst later, not two
	b, f, foes = field(BS, fighter(PC, "Shield", 2), { { 9, 0 } })
	special(b, f, foes[1])
	run(b, 1)
	local firstForm = f.shieldForm
	later = select(2, special(b, f, foes[1]))
	T.check(f.shieldForm ~= nil and f.shieldForm ~= firstForm, "evo shield: a new Shield cast replaces shieldForm")
	run(b, 7, later)
	T.check(#twists(later, "Burst") == 1, "evo shield: ...one burst later, not two", tostring(#twists(later, "Burst")))
	-- a benched pet's shield runs out on the bench: nothing bursts from there
	b, f, foes = field(BS, fighter(PC, "Shield", 2), { { 9, 0 } }, { Bench = { benchPet() } })
	later = select(2, special(b, f, foes[1]))
	run(b, 0.6, later)
	local swapped = b:Command(1, "Swap", 2)
	run(b, 6.5, later)
	T.check(swapped == true and #twists(later, "Burst") == 0 and f.shieldForm == nil and f.thorns == nil, "evo shield: a shield that runs out on the bench bursts nothing")
end)

----------------------------------------------------------------------------------------------------
-- Rally
----------------------------------------------------------------------------------------------------
S.evo_rally = guarded("evo_rally", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo rally: the modules load") then
		return
	end
	local b, f, foes = field(BS, fighter(PC, "Rally", 1), { { 9, 0 } })
	local ev = special(b, f, foes[1])
	T.check(ev ~= nil and ev.form == 1 and near(f.speedBuffMult, 1.15, 1e-6) and near(f.speedBuffUntil, f.dmgBuffUntil, 1e-9) and near(f.dmgBuffMult, 1.35, 1e-6), "evo rally: War pace: +15% speed, as long as the +35% damage", fmt("%.2f until %.2f / %.2f", f.speedBuffMult, f.speedBuffUntil, f.dmgBuffUntil))
	T.check(near(b:SpeedOf(1).Run, f.run * 1.15, 1e-6), "evo rally: the legal speed follows it")
	-- with the Haste helper buff on first, War pace keeps the larger and the later until
	b, f, foes = field(BS, fighter(PC, "Rally", 1), { { 9, 0 } })
	local later = b:Time() + 20
	f.speedBuffMult, f.speedBuffUntil = 1.35, later
	special(b, f, foes[1])
	T.check(near(f.speedBuffMult, 1.35, 1e-9) and f.speedBuffUntil == later, "evo rally: on the Haste helper buff (1.35) War pace keeps 1.35 and the later until", fmt("%.2f", f.speedBuffMult))
	-- an expired buff does not hold it up
	b, f, foes = field(BS, fighter(PC, "Rally", 1), { { 9, 0 } })
	f.speedBuffMult, f.speedBuffUntil = 1.35, -1
	special(b, f, foes[1])
	T.check(near(f.speedBuffMult, 1.15, 1e-6), "evo rally: ...an expired one does not", fmt("%.2f", f.speedBuffMult))
	-- the meter after the cast
	local function meterAfter(evo)
		local battle, u, on = field(BS, fighter(PC, "Rally", evo), { { 9, 0 } })
		u.meter = 100
		battle:Command(1, "Target", on[1].id)
		battle:Command(1, "Special")
		return u.meter
	end
	local meter = BC.Forms.Rally[2].Meter
	T.check(meterAfter(2) == meter and meterAfter(1) == 0 and meterAfter(0) == 0, "evo rally: Evo 2: Fired up fills the meter right after the cast (0 at Evo 0 / 1)", fmt("%s %s %s", tostring(meterAfter(2)), tostring(meterAfter(1)), tostring(meterAfter(0))))
	-- Evo 0: nothing of it
	b, f, foes = field(BS, fighter(PC, "Rally", 0), { { 9, 0 } })
	ev = special(b, f, foes[1])
	T.check(ev ~= nil and ev.form == nil and f.speedBuffMult == 1, "evo rally: Evo 0 keeps its speed")

	-- the pin: a stage-2 Rally fighter (Auto, hitting a tank for 120 s) is buffed at most 80% of the time. The plan's standing tank: the
	-- fighter's own hits and the clock fill the meter. A tank that chases and hits back adds MeterOnHurt: reported, the sim's lone-boss
	-- bands judge a real fight (Task 2)
	local function uptime(entry, chases)
		entry.Slot = 1
		local battle = BS.new({ Mode = "Duel", Seed = 11, Zone = { X = 60, Z = 60 }, TimeLimit = 300,
			Teams = { { Owner = 1, Side = 1, Auto = true, Pets = { entry } }, { Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = { { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = 1 } } } } })
		local u = battle.teams[1].fighter
		u.maxHp, u.hp = 1e9, 1e9
		for _, e in ipairs(battle.units) do
			if e.side == 2 then
				e.maxHp, e.hp = 1e9, 1e9
				if not chases then
					e.moveSpeed = 0
				end
			end
		end
		local on = 0
		for _ = 1, 1200 do
			battle:Step(0.1)
			if battle:Time() < u.dmgBuffUntil then
				on = on + 1
			end
		end
		return on / 1200
	end
	local function hydra(evo)
		return { Key = "hydralotl", Level = 50, Evo = evo }
	end
	local up = uptime(hydra(2))
	T.check(up <= 0.80, "evo rally: a stage-2 Rally fighter (Hydra's Hunger, Auto, hitting a tank for 120 s) is buffed at most 80% of the time", fmt("%.3f", up))
	T.info("evo rally: uptime", fmt("Evo 2 %.3f, Evo 0 %.3f; a tank that hits back: Evo 2 %.3f, Evo 0 %.3f", up, uptime(hydra(0)), uptime(hydra(2), true), uptime(hydra(0), true)))
	-- the pin's reach: every pet that can hold a stage-2 Rally is ranged. A melee one swings faster and fills the meter faster: it would need its own look at the number
	local melee = T.tally("evo rally: every Rally pet that evolves twice is ranged (the uptime pin covers them)")
	for _, def in ipairs(PC.Pets) do
		if def.Special.Kind == "Rally" and PC.EvolveTwice[def.Rarity] then
			melee:case(BC.ProfileOf(def).Attack == "Ranged", tostring(def.Id))
		end
	end
	melee:report()
end)

----------------------------------------------------------------------------------------------------
-- Haste
----------------------------------------------------------------------------------------------------
S.evo_haste = guarded("evo_haste", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo haste: the modules load") then
		return
	end
	local b, f, foes = field(BS, fighter(PC, "Haste", 1), { { 5, 0 } })
	local tm = b.teams[1]
	local F = BC.Fighter
	local ev = special(b, f, foes[1])
	T.check(ev ~= nil and ev.form == 1 and near(f.quickUntil, f.speedBuffUntil, 1e-9), "evo haste: Quick hands lasts as long as the Haste")
	run(b, 0.6)
	local ok, why = b:Command(1, "Element", foes[1].id)
	T.check(ok == true and near(tm.elementReadyAt, b:Time() + 7 * 0.75, 1e-6), "evo haste: an Element cast while Haste is on sets its cooldown x0.75", fmt("%s %s, %.2f", tostring(ok), tostring(why), tm.elementReadyAt - b:Time()))
	ok = b:Command(1, "Dash")
	T.check(ok == true and near(tm.dashReadyAt, b:Time() + 2.5 * 0.75, 1e-6), "evo haste: a Dash too", fmt("%.2f", tm.dashReadyAt - b:Time()))
	T.check(F.ElementCooldown == 7 and F.DashCooldown == 2.5, "evo haste: the catalog's cooldowns stand")
	run(b, 8.5)
	ok = b:Command(1, "Element", foes[1].id)
	T.check(ok == true and near(tm.elementReadyAt, b:Time() + 7, 1e-6), "evo haste: after Haste ends the Element is the full cooldown", fmt("%.2f", tm.elementReadyAt - b:Time()))
	ok = b:Command(1, "Dash")
	T.check(ok == true and near(tm.dashReadyAt, b:Time() + 2.5, 1e-6), "evo haste: ...and the Dash", fmt("%.2f", tm.dashReadyAt - b:Time()))
	-- Evo 0: the full cooldowns
	b, f, foes = field(BS, fighter(PC, "Haste", 0), { { 5, 0 } })
	tm = b.teams[1]
	special(b, f, foes[1])
	run(b, 0.6)
	b:Command(1, "Element", foes[1].id)
	T.check(near(tm.elementReadyAt, b:Time() + 7, 1e-6) and f.quickUntil == 0, "evo haste: Evo 0 keeps the full cooldown")

	-- a bench helper's button is the plain buff: forms change the fighter's own special only
	local helper = { Def = withSpecial(PC, LEG, "Haste", { Role = "Economy" }), Key = LEG, Level = 50, Evo = 2 }
	b, f, foes = field(BS, fighter(PC, "Blast", 0), { { 5, 0 } }, { Bench = { helper } })
	ok, why = b:Command(1, "Buff", 2)
	T.check(ok == true and near(f.speedBuffMult, 1.35, 1e-6) and f.quickUntil == 0 and f.doubleUntil == 0, "evo haste: a stage-2 helper's Haste button stays the plain buff", fmt("%s %s", tostring(ok), tostring(why)))

	-- Evo 2: Double strike. Swings on a tank (a short interval: 400 swings in few steps)
	local function swings(evo, n, on)
		local battle, u, on2 = field(BS, fighter(PC, "Haste", evo), { { 5, 0 } })
		special(battle, u, on2[1])
		u.speedBuffUntil = huge
		u.doubleUntil = on and huge or 0
		u.interval = 0.3
		u.nextAttack = 0
		local landed, double = 0, 0
		for _ = 1, n * 20 do
			for _, h in ipairs(battle:Step(0.1)) do
				if h.type == "Hit" and h.from == u.id and not h.miss then
					if h.double then
						double = double + 1
					else
						landed = landed + 1
					end
				end
			end
			if landed >= n then
				break
			end
		end
		return landed, double
	end
	local landed, double = swings(2, 400, true)
	T.check(landed >= 400 and double >= 0.12 * landed and double <= 0.28 * landed, "evo haste: Evo 2: Hit { double = true } on 12-28% of the landed swings", fmt("%d of %d", double, landed))
	landed, double = swings(2, 100, false)
	T.check(landed >= 100 and double == 0, "evo haste: 0 with Haste off", fmt("%d of %d", double, landed))
	landed, double = swings(1, 100, true)
	T.check(landed >= 100 and double == 0, "evo haste: 0 at Evo 1", fmt("%d of %d", double, landed))
	b, f, foes = field(BS, fighter(PC, "Haste", 2), { { 5, 0 } })
	special(b, f, foes[1])
	T.check(near(f.doubleUntil, f.speedBuffUntil, 1e-9) and near(f.quickUntil, f.speedBuffUntil, 1e-9), "evo haste: a real cast: Double strike and Quick hands last as long as the Haste")
end)

----------------------------------------------------------------------------------------------------
-- Bosses
----------------------------------------------------------------------------------------------------
S.evo_boss_twists = guarded("evo_boss_twists", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo boss: the modules load") then
		return
	end
	-- Storm: no slow, ONE bonus per zone, the Last strike lands
	local b, f, boss = raid(BS, fighter(PC, "Storm", 2))
	local ev, evs = special(b, f, boss)
	local base = baseOf(BC, f, "Storm")
	run(b, 4.3, evs)
	local bonus = hitsOn(evs, boss.id, function(h)
		return h.bonus == true
	end)
	T.check(ev ~= nil and boss.slowUntil == 0 and boss.slowMult == 1, "evo boss: Dragging winds: no slow on the boss")
	T.check(#bonus == 1 and bonus[1].special == "Storm" and near(bonus[1].dmg / (base * 0.1 * (bonus[1].elem or 1)), 1, 0.21), "evo boss: ...ONE bonus Hit per zone near 0.1 x", fmt("%d hits, %s", #bonus, bonus[1] and tostring(bonus[1].dmg)))
	T.check(#twistHits(evs, boss.id, "LastStrike") == 1 and #twists(evs, "LastStrike") == 1, "evo boss: Last strike still fires on its timer")
	-- a second zone pays its own bonus
	b, f, boss = raid(BS, fighter(PC, "Storm", 1))
	evs = select(2, special(b, f, boss))
	run(b, 1, evs)
	local second = select(2, special(b, f, boss))
	run(b, 1, second)
	T.check(#hitsOn(evs, boss.id, function(h)
		return h.bonus == true
	end) == 1 and #hitsOn(second, boss.id, function(h)
		return h.bonus == true
	end) == 1, "evo boss: ...one per zone")

	-- Freeze: no stun, a bonus at the cast, no slow at the thaw, Shatter lands
	b, f, boss = raid(BS, fighter(PC, "Freeze", 2))
	ev, evs = special(b, f, boss)
	base = baseOf(BC, f, "Freeze")
	bonus = hitsOn(evs, boss.id, function(h)
		return h.bonus == true
	end)
	T.check(ev ~= nil and boss.stunUntil == 0 and not has(ev.stunned, boss.id), "evo boss: Freeze: no stun (today)")
	T.check(#bonus == 1 and near(bonus[1].dmg / (base * 0.1 * (bonus[1].elem or 1)), 1, 0.21), "evo boss: Chill: one bonus Hit near 0.1 x at the cast", bonus[1] and tostring(bonus[1].dmg))
	run(b, 1, evs)
	T.check(boss.slowUntil == 0 and #twistHits(evs, boss.id, "Shatter") == 1, "evo boss: no chill at the thaw; Shatter damages the boss")
	T.check(#hitsOn(evs, boss.id, function(h)
		return h.bonus == true
	end) == 1, "evo boss: Evo 2's Freeze pays one bonus in all")

	-- Beam: the Mark is not an immunity; the Twin lands
	b, f, boss = raid(BS, fighter(PC, "Beam", 2))
	evs = select(2, special(b, f, boss))
	T.check(boss.markMult == 1.15 and boss.markUntil > b:Time(), "evo boss: Beam Mark: markMult 1.15 ON the boss")
	run(b, 0.6, evs)
	T.check(#twistHits(evs, boss.id, "Twin") == 1, "evo boss: the Twin damages the boss")
	T.check(#hitsOn(evs, boss.id, function(h)
		return h.bonus == true
	end) == 0, "evo boss: ...no bonus: the Mark works")

	-- Blast: Aftershock and the patch
	b, f, boss = raid(BS, fighter(PC, "Blast", 2))
	evs = select(2, special(b, f, boss))
	run(b, 1.2, evs)
	T.check(#twistHits(evs, boss.id, "Aftershock") == 1, "evo boss: the Aftershock damages the boss")
	T.check(#hitsOn(evs, boss.id, function(h)
		return h.zone == true and h.kind == "Patch"
	end) >= 1, "evo boss: a Patch hurts the boss")

	-- Pounce: the boss on the line and in the burst, a minion locked; the boss as the target takes one hit
	local minion
	b, f, boss, minion = raid(BS, fighter(PC, "Pounce", 2), { Minion = true })
	evs = select(2, special(b, f, minion))
	T.check(minion ~= nil and #twistHits(evs, boss.id, "Landing") == 1 and #twistHits(evs, boss.id, "Charge") == 1, "evo boss: Charge and Landing damage the boss")
	b, f, boss = raid(BS, fighter(PC, "Pounce", 2))
	evs = select(2, special(b, f, boss))
	T.check(#hitsOn(evs, boss.id) == 1, "evo boss: a Pounce aimed at the boss is one hit")

	-- Shield: Thorns and Burst hit the boss
	b, f, boss = raid(BS, fighter(PC, "Shield", 2))
	evs = select(2, special(b, f, nil))
	boss.x, boss.px = 10, 10 -- within the Burst's reach
	f.shield = 100
	zap(b, f, boss, 10000)
	run(b, 0.2, evs)
	T.check(#hitsOn(evs, boss.id, function(h)
		return h.thorns == true
	end) >= 1, "evo boss: Thorns hit the boss")
	T.check(#twists(evs, "Burst") == 1 and #twistHits(evs, boss.id, "Burst") == 1, "evo boss: the Burst damages the boss")
	-- the enraged boss's lethal on a shielded pet: the whole HP + shield, past applyDamage: a KO'd unit never bursts
	b, f, boss = raid(BS, fighter(PC, "Shield", 2), { Bench = { benchPet() } })
	evs = select(2, special(b, f, nil))
	boss.x, boss.px = 10, 10
	b.telegraphs[#b.telegraphs + 1] = { id = 99, boss = boss, attack = { Id = "TestLethal" }, at = b:Time(), shape = "Circle", x = f.x, z = f.z, r = 3, lethal = true }
	run(b, 0.2, evs)
	T.check(f.alive == false and f.shieldForm == nil and f.thorns == nil and #twists(evs, "Burst") == 0, "evo boss: the lethal knocks a shielded pet out: no burst")
end)

----------------------------------------------------------------------------------------------------
-- slowMult / markMult
----------------------------------------------------------------------------------------------------
S.evo_slow_mark = guarded("evo_slow_mark", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo slow: the modules load") then
		return
	end
	local function frost(evo)
		return { Def = cloneDef(PC, LEG, { Element = "Frost", Elements = { "Frost" } }), Key = LEG, Level = 50, Evo = evo }
	end
	-- the Frost element at Evo 0: today's number
	local b, f, foes = field(BS, frost(0), { { 5, 0 } })
	local ok = b:Command(1, "Element", foes[1].id)
	T.check(ok == true and foes[1].slowMult == BC.Damage.Slow and foes[1].slowMult == 0.6 and near(foes[1].slowUntil, b:Time() + 4, 1e-6), "evo slow: a Frost element at Evo 0 sets 0.6 for 4 s", tostring(foes[1].slowMult))
	-- strongest wins, the later until
	local function winds(battle, u, slow, x, z)
		battle.zones[#battle.zones + 1] = { x = x, z = z, r = 4, dps = 1, untilT = battle:Time() + 2, nextTick = battle:Time(), side = 1, from = u, kind = "Storm", slow = slow, base = 1, bonusDone = {} }
	end
	foes[1].slowUntil = b:Time() + 0.2
	winds(b, f, 0.8, foes[1].x, foes[1].z)
	b:Step(0.05)
	T.check(foes[1].slowMult == 0.6 and foes[1].slowUntil > b:Time() + 0.2, "evo slow: 0.6 then 0.8 for longer -> 0.6 (strongest wins), the later until", fmt("%s until +%.2f", tostring(foes[1].slowMult), foes[1].slowUntil - b:Time()))
	-- after slowUntil a weaker slow is its own number, and with none the mult reads 1
	b.zones = {}
	run(b, 0.7)
	T.check(foes[1].slowMult == 1, "evo slow: after slowUntil slowMult reads 1", tostring(foes[1].slowMult))
	winds(b, f, 0.8, foes[1].x, foes[1].z)
	b:Step(0.05)
	T.check(foes[1].slowMult == 0.8, "evo slow: an expired slow does not hold a weaker one down", tostring(foes[1].slowMult))
	-- the Chill buff: the fighter's plain hits
	b, f, foes = field(BS, fighter(PC, "Blast", 0), { { 5, 0 } })
	f.chillUntil, f.nextAttack = b:Time() + 5, 0
	local evs = b:Step(0.1)
	f.nextAttack = huge
	T.check(#hitsOn(evs, foes[1].id) == 1 and foes[1].slowMult == 0.6 and foes[1].slowUntil > b:Time(), "evo slow: the Chill buff's hit sets 0.6", tostring(foes[1].slowMult))
	-- the three readers
	b, f, foes = field(BS, fighter(PC, "Blast", 0), { { 40, 0 } })
	f.slowMult, f.slowUntil = 0.7, b:Time() + 5
	T.check(near(b:SpeedOf(1).Run, f.run * 0.7, 1e-6) and near(b:SpeedOf(1).Walk, f.walk * 0.7, 1e-6), "evo slow: legalSpeeds reads the unit's slowMult", fmt("%.2f", b:SpeedOf(1).Run))
	b, f, foes = field(BS, fighter(PC, "Blast", 0), { { 5, 0 } })
	f.slowMult, f.slowUntil = 0.5, b:Time() + 5
	f.nextAttack = 0
	b:Step(0.1)
	T.check(near(f.nextAttack - b:Time(), f.interval / 0.5, 1e-6), "evo slow: attackInterval reads it", fmt("%.2f", f.nextAttack - b:Time()))
	b, f, foes = field(BS, fighter(PC, "Blast", 0), { { 40, 0 } })
	local bear = foes[1]
	bear.moveSpeed, bear.target, bear.retargetAt = 10, f, huge
	local x0 = bear.x
	b:Step(0.1)
	local plain = x0 - bear.x
	bear.slowMult, bear.slowUntil = 0.5, b:Time() + 5
	x0 = bear.x
	b:Step(0.1)
	T.check(plain > 0.5 and near((x0 - bear.x) / plain, 0.5, 0.02), "evo slow: an NPC's move reads it", fmt("%.2f -> %.2f", plain, x0 - bear.x))
	-- a stage-0 unit no longer reads the global when nothing set a slow
	T.check(BC.Damage.Slow == 0.6 and BC.Damage.Weaken == 0.85, "evo slow: the catalog's Slow / Weaken stand")
	-- Weaken: the same shape, today's number
	b, f, foes = field(BS, { Def = cloneDef(PC, LEG, { Element = "Shadow", Elements = { "Shadow" } }), Key = LEG, Level = 50, Evo = 0 }, { { 5, 0 } })
	b:Command(1, "Element", foes[1].id)
	T.check(foes[1].weakenMult == 0.85 and foes[1].weakenUntil > b:Time(), "evo slow: Void Rend at Evo 0 sets weakenMult 0.85", tostring(foes[1].weakenMult))
	-- the mark: strongest wins, no stacking; an expired one does not hold
	b, f, foes = field(BS, fighter(PC, "Beam", 1), { { 5, 0 } })
	local until1 = b:Time() + 1
	foes[1].markMult, foes[1].markUntil = 1.3, until1
	special(b, f, foes[1])
	T.check(foes[1].markMult == 1.3 and foes[1].markUntil > until1, "evo mark: a stronger mark stands, the later until", tostring(foes[1].markMult))
	b, f, foes = field(BS, fighter(PC, "Beam", 1), { { 5, 0 } })
	foes[1].markMult, foes[1].markUntil = 1.3, -1
	special(b, f, foes[1])
	T.check(foes[1].markMult == 1.15, "evo mark: an expired mark does not", tostring(foes[1].markMult))
	run(b, 4.1)
	T.check(foes[1].markMult == 1, "evo mark: after markUntil markMult reads 1", tostring(foes[1].markMult))
	b, f, foes = field(BS, fighter(PC, "Beam", 0), { { 5, 0 } })
	special(b, f, foes[1])
	T.check(foes[1].markMult == 1 and foes[1].markUntil == 0, "evo mark: a stage-0 Beam marks nothing")
	-- a boss never slows
	local boss
	b, f, boss = raid(BS, fighter(PC, "Blast", 0))
	f.chillUntil, f.nextAttack = b:Time() + 5, 0
	winds(b, f, 0.5, boss.x, boss.z)
	run(b, 1.5)
	T.check(boss.slowMult == 1 and boss.slowUntil == 0, "evo slow: a boss never slows", tostring(boss.slowMult))
end)

----------------------------------------------------------------------------------------------------
-- The delayed-hit queue
----------------------------------------------------------------------------------------------------
S.evo_delayed = guarded("evo_delayed", function()
	local BC, BS, PC, ready = modules()
	if not T.check(ready, "evo delayed: the modules load") then
		return
	end
	-- alive: fires once
	local b, f, foes = field(BS, fighter(PC, "Beam", 2), { { 10, 0 } }, { Bench = { benchPet() } })
	local evs = select(2, special(b, f, foes[1]))
	T.check(#b.delayed == 1, "evo delayed: the Twin is queued on self.delayed, not in the event queue", tostring(#b.delayed))
	run(b, 1, evs)
	T.check(#twists(evs, "Twin") == 1 and #b.delayed == 0, "evo delayed: alive -> fires once", tostring(#twists(evs, "Twin")))
	-- KO'd
	b, f, foes = field(BS, fighter(PC, "Beam", 2), { { 10, 0 } }, { Bench = { benchPet() } })
	evs = select(2, special(b, f, foes[1]))
	f.hp = 1
	zap(b, f, foes[1])
	run(b, 1, evs)
	T.check(f.alive == false and #twists(evs, "Twin") == 0 and #b.delayed == 0, "evo delayed: the caster KO'd -> nothing fires, the entry is gone")
	-- swapped to the bench (alive, not gone, off the floor)
	b, f, foes = field(BS, fighter(PC, "Blast", 1), { { 10, 0 } }, { Bench = { benchPet() } })
	evs = select(2, special(b, f, foes[1]))
	b.teams[1].swapReadyAt = 0
	f.castUntil = 0
	local swapped = b:Command(1, "Swap", 2)
	run(b, 1, evs)
	T.check(swapped == true and f.benched == true and f.alive == true and #twists(evs, "Aftershock") == 0, "evo delayed: swapped to the bench -> nothing fires from the bench's position")
	-- left
	b, f, foes = field(BS, fighter(PC, "Beam", 2), { { 10, 0 } }, { Ally = fighter(PC, "Beam", 2) })
	evs = select(2, special(b, f, foes[1]))
	b:RemoveTeam(1)
	run(b, 1, evs)
	T.check(#twists(evs, "Twin") == 0, "evo delayed: left (RemoveTeam) -> nothing")
	-- two pets' Twins both fire
	b, f, foes = field(BS, fighter(PC, "Beam", 2), { { 10, 0 } }, { Ally = fighter(PC, "Beam", 2) })
	local ally = b.teams[3].fighter
	evs = select(2, special(b, f, foes[1]))
	local more = select(2, special(b, ally, foes[1], 2))
	run(b, 1, evs)
	for _, ev in ipairs(more) do
		evs[#evs + 1] = ev
	end
	local tw = twists(evs, "Twin")
	T.check(#tw == 2 and tw[1].unit ~= tw[2].unit, "evo delayed: two Twins from two pets both fire", tostring(#tw))
	-- an enemy dodging in its i-frames is missed, not struck
	b, f, foes = field(BS, fighter(PC, "Blast", 1), { { 20, 0 } })
	evs = select(2, special(b, f, foes[1]))
	foes[1].iframesUntil = b:Time() + 2
	run(b, 1, evs)
	T.check(#twistHits(evs, foes[1].id, "Aftershock") == 0 and findEvent(evs, "Hit", function(h)
		return h.miss == true and h.to == foes[1].id and h.twist == "Aftershock"
	end) ~= nil, "evo delayed: a body in its dash i-frames dodges a delayed hit")
	-- a stage-0 caster queues nothing
	b, f, foes = field(BS, fighter(PC, "Beam", 0), { { 10, 0 } })
	special(b, f, foes[1])
	T.check(#b.delayed == 0, "evo delayed: a stage-0 Beam queues nothing")
end)

----------------------------------------------------------------------------------------------------
-- The wire
----------------------------------------------------------------------------------------------------
S.evo_wire = guarded("evo_wire", function()
	local _, BS, PC, ready = modules()
	if not T.check(ready, "evo wire: the modules load") then
		return
	end
	T.check(BS.Events.Twist == "Twist", "evo wire: BattleSim.Events.Twist")
	local b, f, foes = field(BS, fighter(PC, "Pounce", 0), { { 12, 0 } })
	local ev = special(b, f, foes[1])
	T.check(ev ~= nil and ev.form == nil and ev.x0 == nil and ev.angle == nil, "evo wire: the Special event of an Evo 0 Pounce has no form / x0 / angle")
	b, f, foes = field(BS, fighter(PC, "Pounce", 1), { { 12, 0 } })
	ev = special(b, f, foes[1])
	T.check(ev ~= nil and ev.form == 1, "evo wire: of Evo 1 has form 1")
	-- a Twist event's numbers are r1-rounded
	b, f, foes = field(BS, fighter(PC, "Blast", 1), { { 20.37, 3.21 } })
	local evs = select(2, special(b, f, foes[1]))
	run(b, 0.7, evs)
	local tw = twists(evs, "Aftershock")[1]
	T.check(tw ~= nil and tw.x == 20.4 and tw.z == 3.2 and tw.r == r1(tw.r) and tw.unit == f.id and tw.kind == "Blast" and type(tw.targets) == "table" and tw.targets[1] == foes[1].id, "evo wire: a Twist's numbers are r1-rounded", tw and fmt("%s %s %s", tostring(tw.x), tostring(tw.z), tostring(tw.r)))
	-- a Patch Zone event carries special; a Storm's does not
	b, f, foes = field(BS, fighter(PC, "Blast", 2), { { 20, 0 } })
	evs = select(2, special(b, f, foes[1]))
	local z = findEvent(evs, "Zone")
	T.check(z ~= nil and z.kind == "Patch" and z.special == "Blast" and z.r == r1(z.r) and z.x == 20 and z.z == 0 and z.seconds == 3 and z.side == 1 and z.unit == f.id, "evo wire: a Patch Zone event carries special")
	b, f, foes = field(BS, fighter(PC, "Storm", 2), { { 20, 0 } })
	z = findEvent(select(2, special(b, f, foes[1])), "Zone")
	T.check(z ~= nil and z.kind == "Storm" and z.special == nil, "evo wire: a Storm Zone event stays as it was")
	-- unitInfo.special
	local function infoOf(battle, u)
		for _, i in ipairs(battle:StaticUnits()) do
			if i.id == u.id then
				return i
			end
		end
		return nil
	end
	b, f, foes = field(BS, { Key = "stormfang", Level = 50, Evo = 1 }, { { 12, 0 } })
	local info = infoOf(b, f)
	T.check(info.special.Name == "Shadow Pack" and info.special.Base == "Storm Pounce" and info.special.Form == 1 and info.special.Kind == "Pounce" and info.special.Id ~= nil and info.special.Color ~= nil, "evo wire: unitInfo.special of a stormfang at Evo 1", tostring(info.special.Name))
	ev = special(b, f, foes[1])
	T.check(ev ~= nil and ev.name == "Shadow Pack", "evo wire: the Special event names the form (the callout reads it)", ev and tostring(ev.name))
	b, f = field(BS, { Key = "stormfang", Level = 50, Evo = 2 }, { { 12, 0 } })
	info = infoOf(b, f)
	T.check(info.special.Name == "Thunder Pack" and info.special.Form == 2, "evo wire: ...at Evo 2", tostring(info.special.Name))
	b, f, foes = field(BS, { Key = "stormfang", Level = 50, Evo = 0 }, { { 12, 0 } })
	info = infoOf(b, f)
	T.check(info.special.Form == 0 and info.special.Name == info.special.Base and info.special.Name == "Storm Pounce", "evo wire: Form 0 / Name == Base at Evo 0", tostring(info.special.Name))
	ev = special(b, f, foes[1])
	T.check(ev ~= nil and ev.name == "Storm Pounce", "evo wire: ...and the event keeps the base name")
	-- a tier copy is the same pet
	b, f = field(BS, { Key = "stormfang@Golden", Level = 50, Evo = 1 }, { { 12, 0 } })
	info = infoOf(b, f)
	T.check(info.special.Name == "Shadow Pack" and info.special.Form == 1, "evo wire: a Golden copy has the pet's own form name", tostring(info.special.Name))
	-- a once-evolver clamps: a Common with a stored 2 is its form 1
	b, f = field(BS, { Key = "pebble_pup", Level = 60, Evo = 2 }, { { 12, 0 } })
	info = infoOf(b, f)
	T.check(info.special.Form == 1 and info.special.Name == "Boulder Fetch", "evo wire: a Common with a stored Evo 2 is at its top form", tostring(info.special.Name))
	-- a hybrid def stays at stage 0
	local hybrid = withSpecial(PC, LEG, "Blast", { Look = { Species = "Phoenix", BodyId = LEG, StyleId = "stormfang" } })
	b, f, foes = field(BS, { Def = hybrid, Key = LEG, Level = 50, Evo = 2 }, { { 20, 0 } })
	info = infoOf(b, f)
	T.check(info.special.Form == 0 and info.special.Name == "Test Blast", "evo wire: a hybrid def (Look.BodyId set) at Evo 2: Form 0", tostring(info.special.Form))
	ev, evs = special(b, f, foes[1])
	run(b, 1, evs)
	T.check(ev ~= nil and ev.form == nil and findEvent(evs, "Zone") == nil and #twists(evs, "Aftershock") == 0 and #b.delayed == 0, "evo wire: ...no twist on its cast")
	local real = withSpecial(PC, LEG, "Blast", { IsHybrid = true })
	b, f, foes = field(BS, { Def = real, Key = LEG, Level = 50, Evo = 2 }, { { 20, 0 } })
	T.check(infoOf(b, f).special.Form == 0, "evo wire: ...PetKeys' own IsHybrid too")
	-- no wire noise for a stage-0 fight: no Twist event, no new key on a Hit
	b, f, foes = field(BS, fighter(PC, "Blast", 0), { { 20, 0 } })
	evs = select(2, special(b, f, foes[1]))
	run(b, 4, evs)
	local clean = true
	for _, e in ipairs(evs) do
		if e.type == "Twist" or e.twist ~= nil or e.bonus ~= nil or e.thorns ~= nil or e.double ~= nil or e.form ~= nil then
			clean = false
		end
	end
	T.check(clean, "evo wire: a stage-0 fight sends none of it")
end)

return S
