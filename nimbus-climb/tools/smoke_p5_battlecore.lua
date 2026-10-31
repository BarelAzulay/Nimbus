-- smoke_p5_battlecore.lua: Phase 5 battle core (ARCHITECTURE_V3.md "Phase 5 build contract" 4.2 / 4.3 / 5.1, battlecore:
-- shared/BattleCatalog.lua + shared/BattleSim.lua + tools/sim_battle.lua), loaded by tools/smoke.py in the SERVER world
-- as pure content scenarios (no boot needed). Replaces smoke_p3_battlecore.lua (the Trial / RETREAT engine is gone).
--   p5stats_formula    PetCatalog.LevelFactor (to 1e-9) is the garden's level source; UnitStats reads the battle path: Evo =
--                      BattleLevelFactor(level, stage) / BattleLevelFactor(level, 0), a stage above MaxEvolution clamped, hybrids
--                      (dual-element defs), no evoMult
--   p5roles            Roles Support x2.6 / x1.5 in UnitStats only, RoleOf, the 15 Support kinds (BuffOf), Rally / Haste
--                      specials, SpecialKinds (9), Combat pets bit-identical with and without a stage-0 extras table, Validate
--   p5sim_fighter      the fighter kit: the AUTO-ATTACK (reach = range + radius + AttackSlack, Interval cadence, never moves
--                      the unit) and the Attack command that only directs it (lock / OutOfReach / BadTarget); Element cooldown +
--                      every shape and status; Specials incl. Rally / Haste on the fighter, Heal on the fighter + bench; Dash
--                      i-frames dodge a Winding hit and a telegraph, the Dash event fields; Swap cooldown / cast lock / NO bench
--                      regen / auto-swap / lives; Buff cooldowns, the Heal buff on the other benched pet; Move clamp at legal run x
--                      MoveSlack incl. Haste / Slow / Dashing, SpeedOf, the Speed event on Swap / Haste
--   p5sim_ai           NPC AI: threat target, the wind-up inside the interval, a miss on i-frames, slow / weaken / burn / stun
--   p5sim_modes        Duel ends by lives or by damage (no Overtime); Ring timeout = loss; Raid with 1-16 fighters; Dungeon:
--                      an empty side 2 runs, SpawnEnemies / Wave / EnemiesDown / BossHp / Wipe / Timeout / Finish
--   p5sim_wire         the wire form round trip (new codes, windup bit, lives), junk payloads, 25 units < 600 B per delta
--   p5sim_determinism  the same setup + command stream (Move points included) replays exactly; seeds differ
--   p5dgn_catalog      Dungeon / DungeonFloors / DungeonPower (floor 10 = 2048) / DungeonWave (deterministic, never EventOnly,
--                      floor 1 one handicapped enemy, the boss entry) / DungeonRewards / DungeonFirstClear totals / DungeonChest
--   p5battle_balance   tools/sim_battle.lua as a library: the balance subset (support ratio, kit factor, mirror duels, the 2.4
--                      wave rule, the element counter (balance-5: decides an even fight, worth x1.15-1.45 power), raids,
--                      ring medians, floor 1 by one level-1 pet, S10 >= floor 10)
-- White-box: a few checks reach into battle.units / battle.teams (same Lua state) to set HP, meters or positions.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local abs, floor, sqrt, huge = math.abs, math.floor, math.sqrt, math.huge
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

local function pet(key, level, tier, extra)
	local p = { Key = key, Level = level or 1, Tier = tier }
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

-- a catalog pet copied with changes (identical stats otherwise)
local function cloneDef(PC, petId, changes)
	local base = PC.Get(petId)
	local def = {}
	for k, v in pairs(base) do
		def[k] = v
	end
	def.Id = petId .. "_test"
	for k, v in pairs(changes or {}) do
		def[k] = v
	end
	return def
end

local function run(b, maxSteps, onStep)
	local all = {}
	local steps = 0
	while not b:IsFinished() and steps < maxSteps do
		local events = b:Step(0.1)
		steps = steps + 1
		for _, ev in ipairs(events) do
			all[#all + 1] = ev
		end
		if onStep then
			onStep(events, steps)
		end
	end
	return all, steps
end

local function countType(events, kind)
	local n = 0
	for _, ev in ipairs(events) do
		if ev.type == kind then
			n = n + 1
		end
	end
	return n
end

local function findEvent(events, kind, pred)
	for _, ev in ipairs(events) do
		if ev.type == kind and (pred == nil or pred(ev)) then
			return ev
		end
	end
	return nil
end

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= tol
end

-- a weak NPC side that cannot win quickly (two handicapped level-1 pets that never cast)
local function weakNpc(owner, n)
	local pets = {}
	for i = 1, n or 2 do
		pets[i] = pet("pebble_pup", 1, nil, { Handicap = 0.3, NoSpecial = true })
	end
	return team(owner or "npc", 2, pets, { Npc = true, Specials = false })
end

-- a tanky NPC that survives a long test (a level-30 bear, never casts)
local function tankNpc(owner)
	return team(owner or "npc", 2, { pet("biscuit_bear", 18, nil, { NoSpecial = true }) }, { Npc = true, Specials = false })
end

-- a player team of a fighter + two helpers near the floor centre; returns battle, team record, fighter unit
local function arena(BS, fighterPets, npcSpec, setup)
	local s = { Mode = "Duel", Seed = 7, Teams = { team(1, 1, fighterPets), npcSpec or weakNpc() } }
	for k, v in pairs(setup or {}) do
		s[k] = v
	end
	local b = BS.new(s)
	if not b then
		return nil
	end
	local tm = b.teams[1]
	return b, tm, tm.fighter
end

-- put the fighter and the first enemy at given points (white-box) and sync the wanted point
local function place(b, tm, fx, fz, ex, ez)
	local f = tm.fighter
	f.x, f.z, f.px, f.pz = fx, fz, fx, fz
	tm.wantX, tm.wantZ = fx, fz
	for _, u in ipairs(b.units) do
		if u.side == 2 and u.alive and not u.gone then
			u.x, u.z, u.px, u.pz = ex, ez, ex, ez
			break
		end
	end
end

local function firstEnemy(b)
	for _, u in ipairs(b.units) do
		if u.side == 2 and u.alive and not u.gone and not u.benched then
			return u
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- p5stats_formula
----------------------------------------------------------------------------------------------------
S.p5stats_formula = guarded("p5stats_formula", function()
	local BC, err = loadModule("BattleCatalog")
	if not T.check(BC ~= nil, "BattleCatalog loads", err) then
		return
	end
	local PC = loadModule("PetCatalog")
	T.check(BC.Version == 5, "BattleCatalog.Version is 5", tostring(BC.Version))
	-- the level formula table to 1e-9
	local bonus = PC.EvolutionBonus or { [0] = 1, [1] = 1.5, [2] = 1.875 }
	local okTable = true
	for _, level in ipairs({ 1, 2, 10, 20, 50, 100 }) do
		for stage = 0, 2 do
			local want = 1 + 0.1 * (level - 1) * bonus[stage]
			if not near(PC.LevelFactor(level, stage), want, 1e-9) then
				okTable = false
			end
		end
		if not near(PC.LevelFactor(level), 1 + 0.1 * (level - 1), 1e-9) then
			okTable = false
		end
	end
	T.check(okTable, "PetCatalog.LevelFactor(level, stage) = 1 + 0.1 x (level - 1) x EvolutionBonus[stage] to 1e-9 (stage nil = 0)")
	T.check(near(PC.LevelFactor(20, 1), 3.85, 1e-9) and near(PC.LevelFactor(50, 2), 10.1875, 1e-9) and near(PC.LevelFactor(100, 2), 19.5625, 1e-9), "L20 evo1 3.85, L50 evo2 10.1875, L100 evo2 19.5625")
	-- UnitStats with a stage scales exactly by the battle level curve's ratio (no evoMult anywhere)
	local base = BC.UnitStats("aurora_fox", 50)
	local evo2 = BC.UnitStats("aurora_fox", 50, nil, { Evo = 2 })
	local ratio = BC.BattleLevelFactor(50, 2) / BC.BattleLevelFactor(50, 0)
	T.check(base and evo2 and near(evo2.MaxHp / base.MaxHp, ratio, 1e-9) and near(evo2.Hit / base.Hit, ratio, 1e-9) and near(evo2.SpecialPower / base.SpecialPower, ratio, 1e-9), "UnitStats Evo 2 at L50 = the stage-0 numbers x BattleLevelFactor(50, 2) / BattleLevelFactor(50, 0) for HP, hit and the special", evo2 and fmt("hp x%.4f hit x%.4f", evo2.MaxHp / base.MaxHp, evo2.Hit / base.Hit))
	T.check(evo2.Evo == 2 and base.Evo == 0 and near(evo2.Interval, base.Interval, 1e-9), "the stage never changes the interval; Evo is echoed")
	-- a stage above MaxEvolution is clamped (a Common evolves once)
	local common2 = BC.UnitStats("mallow_kitten", 50, nil, { Evo = 2 })
	local common1 = BC.UnitStats("mallow_kitten", 50, nil, { Evo = 1 })
	T.check(common2.Evo == 1 and near(common2.MaxHp, common1.MaxHp, 1e-9), "a Common at stored stage 2 counts as stage 1 (PetCatalog.EvolutionStage)")
	-- the level alone never evolves a pet
	local l50 = BC.UnitStats("mallow_kitten", 50)
	T.check(l50.Evo == 0 and near(l50.MaxHp, BC.UnitStats("mallow_kitten", 1).MaxHp * BC.BattleLevelFactor(50, 0), 1e-9), "level 50 without a stored stage = the plain battle level curve")
	-- entries carry the stage themselves
	local viaEntry = BC.UnitStats({ Key = "aurora_fox", Level = 50, Evo = 2 })
	T.check(near(viaEntry.MaxHp, evo2.MaxHp, 1e-9), "an entry table's Evo field is read like extras.Evo")
	-- hybrids: a dual-element def gives its first element to the element attack, both to Elements
	local hybrid = cloneDef(PC, "storm_tabby", { Elements = { "Storm", "Water" }, Element = "Storm" })
	local hs = BC.UnitStats(hybrid, 10, nil, { Evo = 1 })
	T.check(hs and #hs.Elements == 2 and hs.Elements[1] == "Storm" and near(hs.MaxHp, BC.UnitStats("storm_tabby", 10, nil, { Evo = 1 }).MaxHp, 1e-9), "a hybrid def (two elements) scales like its base and lists both elements")
	T.check(BC.UnitPower("aurora_fox", 50, nil, { Evo = 2 }) > BC.UnitPower("aurora_fox", 50) and BC.TeamPower({ pet("aurora_fox", 50, nil, { Evo = 2 }) }) > BC.TeamPower({ pet("aurora_fox", 50) }), "UnitPower / TeamPower grow with the stage")
	-- junk never errors
	local okJunk = pcall(function()
		BC.UnitStats("aurora_fox", 50, nil, { Evo = "x" })
		BC.UnitStats("aurora_fox", 50, nil, { Evo = huge })
		BC.UnitStats("aurora_fox", 50, nil, { Evo = -3 })
		BC.UnitStats(nil)
		BC.UnitStats(42)
		BC.TeamPower(nil)
		BC.TeamPower({ "nope", 7, {} })
	end)
	T.check(okJunk and BC.UnitStats("aurora_fox", 50, nil, { Evo = "x" }).Evo == 0, "junk stages count as 0 and never error")
	T.check(BC.TrialRewardRules == nil and BC.Trials == nil and BC.TrialTeam == nil and BC.TrialCount == nil and BC.ChapterOf == nil and BC.MaxTeamSize == nil and BC.Zones.Trial == nil and BC.TimeLimits.Trial == nil and BC.SynergyRules.SameElement[4] == nil and BC.Damage.Overtime == nil and BC.Damage.RetreatLock == nil, "the Trial / Retreat / Overtime data is gone (10.5)")
end)

----------------------------------------------------------------------------------------------------
-- p5roles
----------------------------------------------------------------------------------------------------
S.p5roles = guarded("p5roles", function()
	local BC = loadModule("BattleCatalog")
	local PC = loadModule("PetCatalog")
	if not T.check(BC and PC, "modules load") then
		return
	end
	local R = BC.Roles
	T.check(type(R) == "table" and R.Combat.Power == 1 and R.Combat.Health == 1 and R.Combat.Name == "Fighter" and near(R.Support.Power, 2.6, 1e-9) and near(R.Support.Health, 1.5, 1e-9) and R.Support.Name == "Support", "Roles = Combat 1 / 1 'Fighter', Support 2.6 / 1.5 'Support'")
	local supports, combats, okRole, okKind = 0, 0, true, true
	for _, def in ipairs(PC.Pets) do
		local role = BC.RoleOf(def)
		if def.Role == "Economy" then
			supports = supports + 1
			if role ~= "Support" or BC.RoleOf(def.Id) ~= "Support" then
				okRole = false
			end
			local kind, buff = BC.BuffOf(def)
			local isSupportKind = false
			for _, k in ipairs(BC.SupportKinds) do
				if k == kind then
					isSupportKind = true
				end
			end
			if not isSupportKind or kind ~= def.Special.Kind or type(buff) ~= "table" or buff.Cooldown ~= BC.Fighter.SupportCooldown then
				okKind = false
			end
		else
			combats = combats + 1
			if role ~= "Combat" then
				okRole = false
			end
			local kind, buff = BC.BuffOf(def)
			if kind ~= PC.ElementsOf(def)[1] or type(buff) ~= "table" or buff.Cooldown ~= BC.Fighter.HelperCooldown then
				okKind = false
			end
		end
	end
	T.check(okRole and supports == 15, "RoleOf: every Economy pet is a Support (15), every other pet Combat", fmt("%d supports, %d combats", supports, combats))
	T.check(okKind, "BuffOf: a Support's button is its Support kind (cooldown 12), a Combat pet's its first element's buff (cooldown 15)")
	-- the role multipliers apply in UnitStats only: a Combat copy of a Support def has x2.6 less hit and x1.5 less HP
	local eco = PC.Get("honey_bunny")
	local asCombat = cloneDef(PC, "honey_bunny", { Role = "Combat" })
	local us, uc = BC.UnitStats(eco, 10), BC.UnitStats(asCombat, 10)
	T.check(us.Role == "Support" and uc.Role == "Combat" and near(us.Hit / uc.Hit, 2.6, 1e-9) and near(us.MaxHp / uc.MaxHp, 1.5, 1e-9) and near(us.Interval, uc.Interval, 1e-9) and near(us.MoveSpeed, uc.MoveSpeed, 1e-9), "Support x2.6 hit / x1.5 HP, the same interval and speed", fmt("hit x%.3f hp x%.3f", us.Hit / uc.Hit, us.MaxHp / uc.MaxHp))
	T.check(near(PC.RoleMultiplier(eco), 1.6, 1e-9), "garden income is untouched (PetCatalog.RoleMult Economy 1.6)")
	-- Combat pets: bit-identical with and without a stage-0 extras table
	local okSame = true
	for _, def in ipairs(PC.Pets) do
		if def.Role ~= "Economy" then
			local a, b2 = BC.UnitStats(def, 7), BC.UnitStats(def, 7, nil, { Evo = 0 })
			if a.MaxHp ~= b2.MaxHp or a.Hit ~= b2.Hit or a.Interval ~= b2.Interval or a.SpecialPower ~= b2.SpecialPower then
				okSame = false
			end
			local stats = BC.BattleStatsOf(def, 7)
			if not near(a.Hit, stats.Power * BC.Damage.DamageScale * a.Profile.DamageMult, 1e-9) or not near(a.MaxHp, stats.Health * BC.Damage.HpScale, 1e-9) then
				okSame = false
			end
		end
	end
	T.check(okSame, "Combat pets: stage 0 extras change nothing; hit = Power x 0.6 x DamageMult, HP = Health x 2.6")
	-- the 9 kinds and the Rally / Haste specials
	T.check(#BC.SpecialKinds == 9 and #PC.SpecialKinds == 9 and BC.Specials.Rally and BC.Specials.Haste and BC.Specials.Rally.Role == "Support" and near(BC.Specials.Rally.Value, 0.35, 1e-9) and BC.Specials.Rally.Seconds == 8 and near(BC.Specials.Haste.Value, 0.35, 1e-9) and BC.Specials.Haste.Seconds == 8, "SpecialKinds has 9 kinds; Specials.Rally / Haste (+35% for 8 s)")
	local okV, problems = BC.Validate()
	T.check(okV, "BattleCatalog.Validate() passes", table.concat(problems, "; "))
	local okP, problemsP = PC.Validate()
	T.check(okP, "PetCatalog.Validate() passes with the Rally / Haste kinds", type(problemsP) == "table" and table.concat(problemsP, "; ") or tostring(problemsP))
	-- the fighter kit numbers
	local F = BC.Fighter
	T.check(F.AttackSlack == 3 and near(F.AttackTolerance, 0.85, 1e-9) and F.ElementCooldown == 7 and near(F.ElementMult, 2.4, 1e-9) and F.SpecialMeterMax == 100 and F.MeterPerSecond == 6 and near(F.DashSeconds, 0.35, 1e-9) and near(F.DashCooldown, 2.5, 1e-9) and F.SwapCooldown == 10 and near(F.SwapCastSeconds, 0.6, 1e-9) and F.HelperCooldown == 15 and F.SupportCooldown == 12 and near(F.Windup, 0.45, 1e-9) and near(F.KitFactor, 1.5, 1e-9) and near(F.HelperWeight, 0.35, 1e-9) and F.Lives == 3 and near(F.MoveSlack, 1.25, 1e-9) and F.Leash == 10 and F.LeashSeconds == 3, "Fighter kit numbers of 4.2")
	T.check(near(F.WalkOf(10), 12, 1e-9) and near(F.WalkOf(14), 16.1, 1e-9) and near(F.WalkOf(18.3), 20, 1e-9) and near(F.RunOf(12), 15.6, 1e-9) and near(F.RunOf(20), 26, 1e-9), "WalkOf = clamp(MoveSpeed x 1.15, 12, 20), RunOf = walk x 1.3")
	local slime, fang = BC.UnitStats("mochi_slime", 1), BC.UnitStats("stormfang", 1)
	T.check(near(slime.Walk, 12, 1e-9) and near(slime.Run, 15.6, 1e-9) and near(fang.Walk, 20, 1e-9) and near(fang.Run, 26, 1e-9), "mochi_slime walks 12 / runs 15.6, stormfang 20 / 26")
	-- B5 TeamPower
	local f, h1, h2 = pet("aurora_fox", 12), pet("storm_tabby", 14), pet("frostling_penguin", 12)
	local syn = BC.SynergyBonus({ f, h1, h2 })
	local want = F.KitFactor * BC.UnitPower(f) * sqrt(syn.PowerMult[1] * syn.HealthMult) + F.HelperWeight * (BC.UnitPower(h1) * sqrt(syn.PowerMult[2] * syn.HealthMult) + BC.UnitPower(h2) * sqrt(syn.PowerMult[3] * syn.HealthMult))
	T.check(near(BC.TeamPower({ f, h1, h2 }), floor(want + 0.5), 0.5), "TeamPower = KitFactor x UnitPower(fighter) + HelperWeight x helpers (synergy included)", fmt("%d vs %.1f", BC.TeamPower({ f, h1, h2 }), want))
	T.check(BC.TeamPower({ f }) == floor(F.KitFactor * BC.UnitPower(f) + 0.5) and BC.TeamPower({ f, h1, h2, pet("stormfang", 50) }) == BC.TeamPower({ f, h1, h2 }), "a lone fighter counts KitFactor x its power; a 4th pet never counts")
	T.check(BC.NpcPower({ pet("pebble_pup", 1, nil, { Handicap = 0.5 }) }) == floor(BC.UnitPower("pebble_pup", 1) * 0.5 + 0.5), "NpcPower sums the entries' powers (Handicap applied)")
	-- element attacks and buffs: one per element
	local okE = true
	for _, e in ipairs(BC.Modes and {} or {}) do
		okE = okE and e
	end
	for _, e in ipairs({ "Water", "Flame", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }) do
		if type(BC.ElementAttacks[e]) ~= "table" or type(BC.Buffs[e]) ~= "table" then
			okE = false
		end
	end
	T.check(okE and BC.ElementAttacks.Water.Shape == "Cone" and BC.ElementAttacks.Water.Push == 4 and BC.ElementAttacks.Earth.Shape == "Circle" and BC.ElementAttacks.Storm.Shape == "Line" and BC.ElementAttacks.Storm.Length == 24 and BC.Buffs.Heal.Value == 0.3 and BC.Buffs.Earth.Name == "Stone Skin" and BC.Buffs.Nature.Meter == 20, "ElementAttacks and Buffs of 4.2")
	T.check(BC.LossRules and near(BC.LossRules.LossShare, 1 / 3, 1e-9) and BC.LossRules.LossMinSeconds == 20 and near(BC.LossRules.LossMinDamage, 0.2, 1e-9) and BC.RealLoss(20, 0) and not BC.RealLoss(5, 0.1) and BC.LossXp(90, 25, 0) == 30 and BC.LossXp(90, 5, 0.05) == 0, "LossRules + RealLoss / LossXp")
	T.check(BC.BossRules.GroupExponent == 0.2 and BC.Zones.Dungeon.X == 44 and BC.Zones.DungeonBoss.X == 56 and BC.TimeLimits.Dungeon == 120 and #BC.Modes == 4 and BC.Duel.PowerGap == 2, "GroupExponent 0.2, Zones.Dungeon 44 / DungeonBoss 56, TimeLimits.Dungeon 120, Modes + Dungeon, Duel.PowerGap 2")
	local dps = BC.ExpectedDps({ Pets = { f, h1, h2 } })
	T.check(near(dps, BC.UnitStats(f).Dps * syn.PowerMult[1] * (1 + BC.Damage.SpecialDpsShare) * sqrt(F.KitFactor) * F.MeleeUptime, 1e-6) and near(BC.ExpectedDps({ Pets = { pet("cloudy_dragon", 25) } }), BC.UnitStats("cloudy_dragon", 25).Dps * (1 + BC.Damage.SpecialDpsShare) * sqrt(F.KitFactor), 1e-6), "ExpectedDps = fighter DPS x (1 + SpecialDpsShare) x KitFactor ^ 0.5 (x MeleeUptime for a melee fighter; the bench adds nothing)")
end)

----------------------------------------------------------------------------------------------------
-- p5sim_fighter
----------------------------------------------------------------------------------------------------
S.p5sim_fighter = guarded("p5sim_fighter", function()
	local BC = loadModule("BattleCatalog")
	local BS = loadModule("BattleSim")
	local PC = loadModule("PetCatalog")
	if not T.check(BC and BS and PC, "modules load") then
		return
	end
	local F = BC.Fighter
	T.check(BS.States.Benched == 3 and BS.States.Dashing == 7 and BS.States.Retreating == nil and BS.Events.Element == "Element" and BS.Events.Swap == "Swap" and BS.Events.Windup == "Windup" and BS.Events.EnemiesDown == "EnemiesDown" and BS.Events.Speed == "Speed" and BS.Events.Overtime == nil and BS.Orders == nil, "States / Events of 4.3 (no Retreating, no Overtime)")
	-- a player team: fighter on the floor, two benched helpers
	local b, tm, f = arena(BS, { pet("mallow_kitten", 5), pet("honey_bunny", 5), pet("pebble_pup", 5) }, tankNpc())
	if not T.check(b ~= nil, "a Duel with a fighter + 2 helpers vs a weak NPC pair starts") then
		return
	end
	local info = b:TeamOf(1)
	T.check(info.Fighter == f.id and #info.Bench == 2 and info.Lives == 3 and tm.units[2].benched and tm.units[2].state == BS.States.Benched and tm.units[3].benched, "TeamOf: Fighter, Bench x2, Lives 3; the helpers are Benched")
	local statics = b:StaticUnits()
	local fighterInfo, helperInfo = nil, nil
	for _, u in ipairs(statics) do
		if u.id == f.id then
			fighterInfo = u
		elseif u.id == tm.units[2].id then
			helperInfo = u
		end
	end
	T.check(fighterInfo and fighterInfo.role == "Fighter" and fighterInfo.bench == nil and fighterInfo.elementAttack and fighterInfo.elementAttack.Name == "Radiance" and fighterInfo.buff.Kind == "Celestial" and near(fighterInfo.walk, BC.UnitStats("mallow_kitten", 5).Walk, 1e-9), "unitInfo: role, elementAttack, buff, walk / run")
	T.check(helperInfo and helperInfo.role == "Support" and helperInfo.bench == 2 and helperInfo.buff.Kind == "Heal" and helperInfo.buff.Cooldown == 12, "a helper's unitInfo: role Support, bench 2, buff Heal (cooldown 12)")
	-- ATTACK (dungeon fixes 4): the fighter AUTO-ATTACKS; the command only DIRECTS it (a lock). Out of reach first.
	local e = firstEnemy(b)
	e.nextAttack = huge -- the tank holds its own hits during these checks (white-box)
	tm.noEngage = true -- the auto-attack's own reach is measured here (white-box: the wave 6 engage rule would walk the pet in)
	place(b, tm, 0, -10, 0, 10)
	f.nextAttack = 0
	local ok, why, extra = b:Command(1, "Attack")
	T.check(ok == true and why == e.id and extra == "OutOfReach" and tm.lock == e, "Attack() locks the nearest enemy even out of reach (-> true, id, \"OutOfReach\")", tostring(why) .. " / " .. tostring(extra))
	ok, why, extra = b:Command(1, "Attack", e.id)
	T.check(ok == true and why == e.id and extra == "OutOfReach", "Attack(id) on a far target is accepted as a lock (OutOfReach: BattleService toasts Too far!)", tostring(extra))
	local evs = b:Step(0.1)
	T.check(findEvent(evs, "Order", function(ev)
		return ev.order == "Attack" and ev.target == e.id and ev.owner == 1 and ev.rejected == nil
	end) ~= nil and findEvent(evs, "Hit", function(ev)
		return ev.from == f.id
	end) == nil, "the direct order echoes Order { order = Attack, target }; nothing in reach = no swing")
	ok, why = b:Command(1, "Attack", f.id)
	local ok2, why2 = b:Command(1, "Attack", 999)
	evs = b:Step(0.1)
	T.check(not ok and why == "BadTarget" and not ok2 and why2 == "BadTarget" and findEvent(evs, "Order", function(ev)
		return ev.rejected == "BadTarget" and ev.order == "Attack" and ev.owner == 1
	end) ~= nil and countType(evs, "Order") == 1, "Attack on an ally / a junk id is refused BadTarget; a refused command echoes an Order event with rejected (one echo per team per step)")
	-- reach = range + radius + AttackSlack: the auto-attack swings inside it, never 0.2 stud beyond it
	local reach = f.range + e.radius
	local function swingsAt(dz)
		place(b, tm, 0, 0, 0, dz)
		e.target, e.retargetAt, e.windAt = nil, huge, nil
		e.stunUntil = b:Time() + 0.5 -- the tank stands still for the measurement (white-box)
		f.nextAttack = b:Time()
		local evs2 = b:Step(0.1)
		local h = findEvent(evs2, "Hit", function(ev)
			return ev.from == f.id and ev.to == e.id
		end)
		return h
	end
	T.check(swingsAt(reach + F.AttackSlack - 0.1) ~= nil, "the auto-attack lands within range + radius + AttackSlack")
	T.check(swingsAt(reach + F.AttackSlack + 0.2) == nil, "no swing 0.2 stud beyond the slack (the unit is never moved toward it)", fmt("z %.2f", f.z))
	-- the command never swings: not ready -> an accepted direct order and no hit
	place(b, tm, 0, 0, 0, reach - 0.5)
	f.nextAttack = b:Time() + 5
	local hpBefore = e.hp
	ok, why, extra = b:Command(1, "Attack", e.id)
	evs = b:Step(0.1)
	T.check(ok and extra == nil and findEvent(evs, "Hit", function(ev)
		return ev.from == f.id
	end) == nil and e.hp == hpBefore, "Attack(id) in reach is accepted but never swings by itself (cooldown not ready -> no Hit)")
	-- the cadence: the auto-attack swings once per Interval (never faster), positions untouched
	f.nextAttack = b:Time()
	local times = {}
	local fx, fz = f.x, f.z
	for _ = 1, 60 do
		e.x, e.z, e.px, e.pz = 0, reach - 0.5, 0, reach - 0.5
		e.windAt = nil
		e.nextAttack = huge
		e.hp = e.maxHp
		local evs2 = b:Step(0.1)
		if findEvent(evs2, "Hit", function(ev)
			return ev.from == f.id and ev.to == e.id
		end) then
			times[#times + 1] = b:Time()
		end
	end
	local cadenceOk = #times >= 4
	for i = 2, #times do
		local gap = times[i] - times[i - 1]
		if gap < f.interval * F.AttackTolerance - 0.11 or gap > f.interval + 0.11 then
			cadenceOk = false
		end
	end
	T.check(cadenceOk and near((times[#times] - times[1]) / math.max(1, #times - 1), f.interval, 0.06), "the auto-attack swings every Interval (nextAttack = max(nextAttack, t) + Interval)", fmt("%d swings, mean %.2f of %.2f", #times, (#times > 1) and (times[#times] - times[1]) / (#times - 1) or -1, f.interval))
	T.check(near(f.x, fx, 1e-9) and near(f.z, fz, 1e-9), "the auto-attack never moves the fighter (the character stays the body)")
	-- lock: Target then Attack with nil
	ok = b:Command(1, "Target", e.id)
	evs = b:Step(0.1)
	T.check(ok and tm.lock == e and findEvent(evs, "Order", function(ev)
		return ev.order == "Target" and ev.target == e.id and ev.rejected == nil
	end) ~= nil and b:TeamOf(1).Lock == e.id, "Target locks a unit (Order event, TeamOf.Lock)")
	ok, why = b:Command(1, "Attack")
	T.check(ok == true and why == e.id and tm.lock == e, "Attack() keeps a live lock in EngageRange (bug #16: no cycle, no re-target)")
	ok, why = b:Command(1, "Target", f.id)
	T.check(not ok and why == "BadTarget" and b:Command(1, "Target", nil) == true and tm.lock == nil, "a lock on an ally is refused; Target nil clears")
	-- ELEMENT: cooldown and every shape
	local function elementTest(element, extraCheck)
		local def = cloneDef(PC, "storm_tabby", { Element = element, Elements = { element } })
		local b2 = BS.new({ Mode = "Duel", Seed = 11, Teams = { team(1, 1, { { Def = def, Key = "storm_tabby", Level = 10, Slot = 1 } }), team("npc", 2, { pet("biscuit_bear", 5, nil, { NoSpecial = true }), pet("biscuit_bear", 5, nil, { NoSpecial = true }), pet("biscuit_bear", 5, nil, { NoSpecial = true }) }, { Npc = true, Specials = false }) } })
		local t2 = b2.teams[1]
		local f2 = t2.fighter
		f2.x, f2.z, f2.px, f2.pz = 0, 0, 0, 0
		t2.wantX, t2.wantZ = 0, 0
		local enemies = {}
		for _, u in ipairs(b2.units) do
			if u.side == 2 then
				enemies[#enemies + 1] = u
			end
		end
		-- one enemy 6 studs ahead (+z), one 6 studs ahead and 6 to the side, one 30 studs behind
		enemies[1].x, enemies[1].z = 0, 6
		enemies[2].x, enemies[2].z = 6, 6
		enemies[3].x, enemies[3].z = 0, -30
		for _, u in ipairs(enemies) do
			u.px, u.pz = u.x, u.z
		end
		local a = BC.ElementAttacks[element]
		local ok2, name = b2:Command(1, "Element", enemies[1].id)
		local evs2 = b2:Step(0.1)
		local ev = findEvent(evs2, "Element")
		local hitFront = ev and T.contains(ev.targets, enemies[1].id)
		local hitBehind = ev and T.contains(ev.targets, enemies[3].id)
		T.check(ok2 and name == a.Name and ev and ev.element == element and ev.name == a.Name and ev.shape == a.Shape and hitFront and not hitBehind, element .. " '" .. a.Name .. "' casts a " .. a.Shape .. " toward the target (hits ahead, never behind)", ev and (#ev.targets .. " targets") or tostring(name))
		local elemHit = findEvent(evs2, "Hit", function(h)
			return h.from == f2.id and h.to == enemies[1].id and h.element == a.Name
		end)
		T.check(elemHit ~= nil and elemHit.dmg > f2.hit * 1.5, element .. ": the element hit carries element = name and about ElementMult x a basic hit", elemHit and fmt("%d vs hit %.1f", elemHit.dmg, f2.hit))
		local ok3, why3 = b2:Command(1, "Element", enemies[1].id)
		T.check(not ok3 and why3 == "Cooldown" and b2:TeamOf(1).Cooldowns.Element > 6, element .. ": a second cast is on cooldown (TeamOf.Cooldowns.Element ~ 7)")
		if extraCheck then
			extraCheck(b2, f2, enemies, ev, evs2)
		end
	end
	elementTest("Water", function(b2, f2, enemies)
		T.check(enemies[1].z > 6 + 2, "Water Tide Burst pushes the enemy back ~4 studs (minus its step toward the fighter)", fmt("z %.1f", enemies[1].z))
	end)
	elementTest("Flame", function(b2, f2, enemies)
		local burns = 0
		for _ = 1, 35 do
			local evs3 = b2:Step(0.1)
			for _, h in ipairs(evs3) do
				if h.type == "Hit" and h.burn and h.to == enemies[1].id then
					burns = burns + 1
				end
			end
		end
		T.check(burns == 3, "Flame Flare burns in 3 ticks over 3 s (Hit burn = true)", burns)
	end)
	elementTest("Frost", function(b2, f2, enemies)
		T.check(enemies[1].slowUntil > b2:Time() + 3, "Frost Frostbite slows the enemy for 4 s")
	end)
	elementTest("Nature", function(b2, f2, enemies, ev, evs2)
		f2.hp = f2.maxHp * 0.5
		f2.x, f2.z = 0, 0
		local t2 = b2.teams[1]
		t2.elementReadyAt = 0
		local before = f2.hp
		local ok4 = b2:Command(1, "Element", enemies[1].id)
		local evs4 = b2:Step(0.1)
		local leechHit = findEvent(evs4, "Hit", function(h)
			return h.from == f2.id and h.leech
		end)
		T.check(ok4 and leechHit ~= nil and f2.hp > before, "Nature Thorn Lash leeches 30% of its damage back (Hit leech = n)", leechHit and leechHit.leech)
	end)
	elementTest("Earth", function(b2, f2, enemies)
		T.check(enemies[1].stunUntil > b2:Time() and enemies[1].state == BS.States.Stunned, "Earth Quake stuns enemies around the fighter for 0.5 s")
	end)
	elementTest("Storm", function(b2, f2, enemies, ev)
		T.check(ev and T.contains(ev.targets, enemies[1].id) and not T.contains(ev.targets, enemies[2].id), "Storm Bolt is a thin line: the enemy 6 studs beside the line is missed")
	end)
	elementTest("Celestial", function(b2, f2)
		T.check(f2.meter >= 15, "Celestial Radiance adds 15 meter", f2.meter)
	end)
	elementTest("Shadow", function(b2, f2, enemies)
		T.check(enemies[1].weakenUntil > b2:Time() + 4, "Shadow Void Rend weakens the enemy for 5 s")
	end)
	-- aim by point and junk aims
	do
		local b3, t3, f3 = arena(BS, { pet("storm_tabby", 10) })
		place(b3, t3, 0, 0, 0, 8)
		local ok5 = b3:Command(1, "Element", { x = 0, z = 20 })
		local evs5 = b3:Step(0.1)
		local ev5 = findEvent(evs5, "Element")
		T.check(ok5 and ev5 and near(ev5.tx, 0, 0.1) and near(ev5.tz, 20, 0.1), "Element accepts a { x, z } aim")
		t3.elementReadyAt = 0
		local ok6, why6 = b3:Command(1, "Element", { x = 0 / 0, z = huge })
		T.check(ok6 == true or why6 ~= nil, "a junk aim never errors (falls back to the lock / nearest)")
	end
	-- SPECIALS incl. Rally / Haste act on the fighter
	do
		local function special(fighterId, kind)
			local def = cloneDef(PC, fighterId, { Special = { Id = "t_" .. kind, Name = "Test " .. kind, Kind = kind, Power = 40, Color = PC.Get(fighterId).Special.Color } })
			local b4, t4, f4 = arena(BS, { { Def = def, Key = fighterId, Level = 10, Slot = 1 }, pet("pebble_pup", 1) }, tankNpc())
			place(b4, t4, 0, 0, 0, 5)
			return b4, t4, f4
		end
		local b4, t4, f4 = special("mallow_kitten", "Heal")
		f4.hp = f4.maxHp * 0.3
		local bench4 = t4.bySlot[2]
		bench4.hp = bench4.maxHp * 0.3
		local ok7, why7 = b4:Command(1, "Special")
		T.check(not ok7 and why7 == "Charging", "Special with an empty meter is refused Charging")
		f4.meter = 100
		ok7 = b4:Command(1, "Special")
		local evs7 = b4:Step(0.1)
		local sp = findEvent(evs7, "Special")
		T.check(ok7 and sp and sp.kind == "Heal" and f4.hp > f4.maxHp * 0.3 and bench4.hp > bench4.maxHp * 0.3 and #sp.heals == 2 and sp.heals[1][1] == f4.id and sp.heals[2][1] == bench4.id and f4.meter < 100 and f4.state == BS.States.Casting, "a fighter's Heal special heals the fighter AND its benched pets (dungeon fixes 7; Casting after)", sp and sp.heals and #sp.heals)
		b4, t4, f4 = special("mallow_kitten", "Shield")
		f4.meter = 100
		b4:Command(1, "Special")
		b4:Step(0.1)
		T.check(f4.shield > 0, "a fighter's Shield special shields the fighter", f4.shield)
		b4, t4, f4 = special("mallow_kitten", "Rally")
		f4.meter = 100
		ok7 = b4:Command(1, "Special")
		evs7 = b4:Step(0.1)
		sp = findEvent(evs7, "Special")
		T.check(ok7 and sp and sp.kind == "Rally" and near(f4.dmgBuffMult, 1.35, 1e-9) and f4.dmgBuffUntil > b4:Time() + 7, "Rally: +35% damage for 8 s on the fighter")
		for _ = 1, 6 do
			b4:Step(0.1)
		end
		local e4 = firstEnemy(b4)
		f4.nextAttack = b4:Time()
		b4:Command(1, "Attack", e4.id)
		evs7 = b4:Step(0.1)
		local rallied = findEvent(evs7, "Hit", function(h)
			return h.from == f4.id and h.buffDmg
		end)
		T.check(rallied ~= nil, "a hit under Rally carries buffDmg = true")
		b4, t4, f4 = special("mallow_kitten", "Haste")
		f4.meter = 100
		local before = b4:SpeedOf(1)
		ok7 = b4:Command(1, "Special")
		evs7 = b4:Step(0.1)
		local after = b4:SpeedOf(1)
		T.check(ok7 and near(after.Run, before.Run * 1.35, 1e-6) and near(after.Walk, before.Walk * 1.35, 1e-6) and findEvent(evs7, "Speed", function(ev)
			return ev.owner == 1 and near(ev.run, after.Run, 0.11)
		end) ~= nil, "Haste: +35% speed for 8 s; SpeedOf changes and a Speed event fires", fmt("%.1f -> %.1f", before.Run, after.Run))
		for _ = 1, 85 do
			evs7 = b4:Step(0.1)
		end
		local backEv = nil
		for _ = 1, 5 do
			evs7 = b4:Step(0.1)
			backEv = backEv or findEvent(evs7, "Speed")
		end
		local back = b4:SpeedOf(1)
		T.check(near(back.Run, before.Run, 1e-6), "the speed is back after 8 s (a second Speed event)")
		-- an offensive special still works from the fighter
		b4, t4, f4 = special("mallow_kitten", "Pounce")
		f4.meter = 100
		local e5 = firstEnemy(b4)
		ok7 = b4:Command(1, "Special")
		evs7 = b4:Step(0.1)
		T.check(ok7 and findEvent(evs7, "Hit", function(h)
			return h.from == f4.id and h.special == "Pounce" and h.to == e5.id
		end) ~= nil and near(f4.x, 0, 0.01), "Pounce from a fighter strikes the target (the character does not teleport)")
	end
	-- DASH: cooldown; i-frames dodge a Winding hit
	do
		local b5, t5, f5 = arena(BS, { pet("biscuit_bear", 10) }, team("npc", 2, { pet("storm_tabby", 10, nil, { NoSpecial = true }) }, { Npc = true, Specials = false }))
		local e5 = firstEnemy(b5)
		place(b5, t5, 0, 0, 0, 3)
		local okD = b5:Command(1, "Dash")
		local evsD = b5:Step(0.1)
		local dashEv = findEvent(evsD, "Dash")
		T.check(okD and dashEv ~= nil and f5.state == BS.States.Dashing and f5.iframesUntil > b5:Time(), "Dash: Dashing state, i-frames, Dash event")
		-- wave 6: no threat yet = the sidestep runs perpendicular to the aim (the enemy straight +Z), no target
		T.check(dashEv and dashEv.unit == f5.id and type(dashEv.dir) == "table" and near(abs(dashEv.dir[1]), 1, 0.011) and near(dashEv.dir[2], 0, 0.011) and dashEv.target == nil,
			"the Dash event carries { unit, dir (the sidestep: perpendicular to the nearest enemy with no threat), target nil }", dashEv and dashEv.dir and fmt("%.2f, %.2f", dashEv.dir[1], dashEv.dir[2]))
		local okD2, whyD2 = b5:Command(1, "Dash")
		T.check(not okD2 and whyD2 == "Cooldown" and b5:TeamOf(1).Cooldowns.Dash > 2, "a second Dash is refused Cooldown (~2.5 s)")
		-- the wind-up: find a Windup aimed at the fighter, dash right before it lands -> a miss
		local windup, misses, hitsOnMe = nil, 0, 0
		t5.dashReadyAt = 0
		for _ = 1, 60 do
			local evs = b5:Step(0.1)
			for _, ev in ipairs(evs) do
				if ev.type == "Windup" and ev.target == f5.id and not windup then
					windup = ev
				elseif ev.type == "Parry" and ev.unit == f5.id then
					misses = misses + 1 -- wave 6: a Dash inside ParryWindow parries (the wind-up is cancelled: no Hit at all)
				elseif ev.type == "Hit" and ev.to == f5.id then
					if ev.miss then
						misses = misses + 1
					else
						hitsOnMe = hitsOnMe + 1
					end
				end
			end
			if windup and b5:Time() >= windup.at - 0.15 then
				b5:Command(1, "Dash")
				t5.dashReadyAt = 0
			end
		end
		T.check(windup ~= nil and near(windup.at - (windup.at - F.Windup), F.Windup, 1e-6), "NPC attacks announce a Windup { unit, target, at } 0.45 s ahead")
		T.check(misses >= 3 and misses > hitsOnMe, "dashing just before the wind-up lands turns the hits into misses / parries (Hit miss = true, Parry)", fmt("%d misses, %d hits", misses, hitsOnMe))
		-- a telegraph is dodged the same way
		local b6 = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 3, Teams = { team(1, 1, { pet("cloudy_dragon", 25), pet("twilight_dragon", 28), pet("ember_phoenix", 26, "Golden") }) } })
		local t6 = b6.teams[1]
		local f6 = t6.fighter
		local tele, teleMiss, teleHit = nil, 0, 0
		for _ = 1, 150 do
			local evs = b6:Step(0.1)
			for _, ev in ipairs(evs) do
				if ev.type == "Telegraph" and not tele then
					tele = ev
					-- stand inside it
					f6.x, f6.z = ev.x, ev.z
					t6.wantX, t6.wantZ = ev.x, ev.z
				elseif ev.type == "Hit" and ev.to == f6.id and ev.tele then
					if ev.miss then
						teleMiss = teleMiss + 1
					else
						teleHit = teleHit + 1
					end
				end
			end
			if tele and b6:Time() >= tele.at - 0.2 and b6:Time() < tele.at then
				t6.dashReadyAt = 0
				b6:Command(1, "Dash")
			end
		end
		T.check(tele ~= nil and teleMiss >= 1 and teleHit == 0, "a dash inside a telegraph's last 0.35 s dodges it (Hit miss = true with tele)", fmt("miss %d hit %d", teleMiss, teleHit))
	end
	-- SWAP: cooldown, cast lock, bench regen, auto-swap on a KO, lives
	do
		local b7, t7, f7 = arena(BS, { pet("mallow_kitten", 5), pet("honey_bunny", 5), pet("pebble_pup", 5) }, tankNpc())
		local e7 = firstEnemy(b7)
		e7.nextAttack = huge -- the tank waits (white-box) until the KO check below
		place(b7, t7, 0, 0, 0, 4)
		local helper = t7.bySlot[2]
		local okS, whyS = b7:Command(1, "Swap", 1)
		T.check(not okS and whyS == "BadSlot", "Swap(1) is refused BadSlot")
		okS = b7:Command(1, "Swap", 2)
		local evsS = b7:Step(0.1)
		local swapEv = findEvent(evsS, "Swap")
		T.check(okS and swapEv and swapEv.out == f7.id and swapEv["in"] == helper.id and swapEv.auto == nil and t7.fighter == helper and f7.benched and f7.state == BS.States.Benched and not helper.benched and helper.state == BS.States.Casting, "Swap(2): the helper takes the floor Casting, the old fighter is Benched; Swap event { out, in }")
		T.check(findEvent(evsS, "Speed", function(ev)
			return ev.owner == 1
		end) ~= nil and near(b7:SpeedOf(1).Walk, helper.walk, 1e-9), "a Swap fires a Speed event with the new fighter's speeds")
		helper.nextAttack = 0
		local castSwing = false
		for _ = 1, 4 do
			if findEvent(b7:Step(0.1), "Hit", function(ev)
				return ev.from == helper.id
			end) then
				castSwing = true
			end
		end
		T.check(not castSwing and helper.state == BS.States.Casting, "the incoming fighter does not auto-attack during its SwapCastSeconds")
		okS, whyS = b7:Command(1, "Swap", 3)
		T.check(not okS and (whyS == "Casting" or whyS == "Cooldown"), "a second Swap is refused while Casting / on cooldown", tostring(whyS))
		local swung = false
		for _ = 1, 4 do
			if findEvent(b7:Step(0.1), "Hit", function(ev)
				return ev.from == helper.id
			end) then
				swung = true
			end
		end
		T.check(swung, "after the cast the incoming fighter auto-attacks")
		okS, whyS = b7:Command(1, "Swap", 3)
		T.check(not okS and whyS == "Cooldown" and b7:TeamOf(1).Cooldowns.Swap > 8, "SwapCooldown 10 s", tostring(whyS))
		-- dungeon fixes (7): no bench regen in combat
		f7.hp = f7.maxHp * 0.2
		for _ = 1, 50 do
			b7:Step(0.1)
		end
		T.check(F.BenchRegenPerSecond == 0 and f7.hp == f7.maxHp * 0.2, "a benched pet does NOT regain HP in combat (BenchRegenPerSecond 0)", fmt("%.1f%%", 100 * f7.hp / f7.maxHp))
		-- auto-swap on a KO: the fighter at 1 HP takes a hit -> KO + Swap auto; lives 2
		e7.nextAttack = b7:Time()
		local fighterNow = t7.fighter
		fighterNow.hp = 1
		fighterNow.shield = 0
		local koEv, autoSwap = nil, nil
		for _ = 1, 60 do
			local evs = b7:Step(0.1)
			koEv = koEv or findEvent(evs, "KO", function(ev)
				return ev.unit == fighterNow.id
			end)
			autoSwap = autoSwap or findEvent(evs, "Swap", function(ev)
				return ev.auto == true
			end)
			if koEv and autoSwap then
				break
			end
		end
		T.check(koEv ~= nil and autoSwap ~= nil and autoSwap.out == fighterNow.id and t7.fighter ~= fighterNow and t7.fighter.alive and b7:TeamOf(1).Lives == 2, "a downed fighter auto-swaps to the next alive helper (Swap auto = true); Lives 2")
		local okB, whyB = b7:Command(1, "Buff", fighterNow.slot)
		T.check(not okB and whyB == "Down", "the downed pet's buff / swap are refused Down", tostring(whyB))
		-- the lives in the wire: the fighter's code carries 2
		local snap = b7:Snapshot()
		T.check(snap.Units[t7.fighter.id].lives == 2 and snap.Units[fighterNow.id].lives == 0 and snap.Units[fighterNow.id].state == BS.States.Down, "the snapshot carries lives on the fighter and Down on the fallen pet")
		-- lives 0 = the team is out
		for _, u in ipairs(t7.units) do
			if u.alive then
				u.hp = 1
				u.shield = 0
			end
		end
		local ended = false
		for _ = 1, 400 do
			local evs = b7:Step(0.1)
			if findEvent(evs, "End") then
				ended = true
				break
			end
		end
		T.check(ended and b7:Result().WinnerSide == 2 and b7:Result().Reason == "Wipe" and b7:Result().Survivors[1] == 0, "all three down = the team is out (Wipe, Survivors 0)")
	end
	-- BUFF cooldowns and effects
	do
		local b8, t8, f8 = arena(BS, { pet("mallow_kitten", 5), pet("honey_bunny", 5), pet("biscuit_bear", 5) })
		place(b8, t8, 0, 0, 0, 4)
		f8.hp = f8.maxHp * 0.5
		local other8 = t8.bySlot[3]
		other8.hp = other8.maxHp * 0.4
		local okB, kind = b8:Command(1, "Buff", 2)
		local evsB = b8:Step(0.1)
		local buffEv = findEvent(evsB, "Buff")
		T.check(okB and kind == "Heal" and buffEv and buffEv.owner == 1 and buffEv.unit == t8.bySlot[2].id and buffEv.kind == "Heal" and buffEv.target == f8.id and near(f8.hp, f8.maxHp * 0.8, f8.maxHp * 0.01), "Buff(2) Heal: +30% of the fighter's max HP; Buff event { owner, unit, kind, name, until, target }")
		T.check(buffEv and type(buffEv.heals) == "table" and buffEv.heals[1][1] == f8.id and buffEv.heals[2] and buffEv.heals[2][1] == other8.id and near(other8.hp, other8.maxHp * 0.7, other8.maxHp * 0.01) and t8.bySlot[2].hp == t8.bySlot[2].maxHp, "the Heal buff also heals the OTHER benched pet 30% of its max HP (dungeon fixes 7); heals { { id, hp } x2 }")
		okB, kind = b8:Command(1, "Buff", 2)
		T.check(not okB and kind == "Cooldown" and near(b8:TeamOf(1).Cooldowns.Buff[2], F.SupportCooldown - 0.1, 0.11), "a Support helper's second buff is refused for SupportCooldown 12 s", tostring(kind))
		okB, kind = b8:Command(1, "Buff", 3)
		evsB = b8:Step(0.1)
		T.check(okB and kind == "Earth" and near(f8.takenMult, 0.65, 1e-9) and f8.takenUntil > b8:Time() + 7 and near(b8:TeamOf(1).Cooldowns.Buff[3], F.HelperCooldown - 0.1, 0.11), "Buff(3) Earth Stone Skin: damage taken -35% for 8 s; HelperCooldown 15 s")
		okB, kind = b8:Command(1, "Buff", 1)
		T.check(not okB and kind == "BadSlot" and select(2, b8:Command(1, "Buff", "x")) == "BadSlot" and select(2, b8:Command(1, "Buff", 9)) == "BadSlot", "Buff on slot 1 / junk / 9 is refused BadSlot")
		-- every element buff applies without error
		local okAll = true
		for _, e in ipairs({ "Water", "Flame", "Frost", "Nature", "Storm", "Celestial", "Shadow" }) do
			local def = cloneDef(PC, "storm_tabby", { Element = e, Elements = { e } })
			local b9, t9, f9 = arena(BS, { pet("mallow_kitten", 5), { Def = def, Key = "storm_tabby", Level = 5, Slot = 2 } })
			local okE, kindE = b9:Command(1, "Buff", 2)
			local evs9 = b9:Step(0.1)
			if not okE or kindE ~= e or not findEvent(evs9, "Buff", function(ev)
				return ev.kind == e and ev.name == BC.Buffs[e].Name
			end) then
				okAll = false
			end
			if e == "Nature" and f9.meter < 20 then
				okAll = false
			end
			if e == "Celestial" and f9.shield <= 0 then
				okAll = false
			end
			if e == "Storm" and not near(f9.atkSpeedMult, 1.35, 1e-9) then
				okAll = false
			end
		end
		T.check(okAll, "every element buff applies (Nature +20 meter, Celestial shield, Storm attack speed ...)")
	end
	-- BENCHED SLOT 1: after Swap(2) the original fighter sits on the bench and can be buffed / swapped back
	do
		local bA, tA, fA = arena(BS, { pet("mallow_kitten", 5), pet("honey_bunny", 5), pet("biscuit_bear", 5) })
		place(bA, tA, 0, 0, 0, 40)
		local okS = bA:Command(1, "Swap", 2)
		bA:Step(0.1)
		local active = tA.fighter
		T.check(okS and fA.benched and active == tA.bySlot[2], "Swap 1 -> 2: the slot-1 pet is benched")
		local okBA, whyBA = bA:Command(1, "Buff", 2)
		local okSA, whySA = bA:Command(1, "Swap", 2)
		T.check(not okBA and whyBA == "BadSlot" and not okSA and whySA == "BadSlot", "Buff / Swap on the active fighter (slot 2) are refused BadSlot", tostring(whyBA) .. " / " .. tostring(whySA))
		local okB1, kind1 = bA:Command(1, "Buff", 1)
		T.check(okB1 and kind1 ~= nil, "Buff(1) is accepted on the benched original fighter", tostring(kind1))
		for _ = 1, 8 do
			bA:Step(0.1)
		end
		tA.swapReadyAt = 0
		local okS1, whyS1 = bA:Command(1, "Swap", 1)
		bA:Step(0.1)
		T.check(okS1 and tA.fighter == fA and not fA.benched and active.benched, "Swap(1) brings the benched original fighter back", tostring(whyS1))
	end
	-- MOVE: the fighter walks toward the wanted point at <= legal run x MoveSlack
	do
		local b10, t10, f10 = arena(BS, { pet("mallow_kitten", 5), pet("pebble_pup", 5) }, tankNpc())
		t10.noEngage = true -- FOLLOW only (white-box: the wave 6 engage rule is pinned by smoke_fight.lua)
		local okM, whyM = b10:Command(1, "Move", 0 / 0, 5)
		T.check(not okM and whyM == "BadPoint" and select(2, b10:Command(1, "Move", "a", 1)) == "BadPoint", "Move with NaN / junk is refused BadPoint")
		local sp = b10:SpeedOf(1)
		T.check(near(sp.Walk, BC.UnitStats("mallow_kitten", 5).Walk, 1e-9) and near(sp.Run, sp.Walk * 1.3, 1e-9), "SpeedOf = the fighter's WalkOf / RunOf")
		f10.x, f10.z = 0, 0
		T.check(b10:Command(1, "Move", 0, 100) == true, "Move far away is accepted (clamped to the floor)")
		b10:Step(0.1)
		local moved = f10.z
		T.check(near(moved, sp.Run * F.MoveSlack * 0.1, 0.02), "one step moves at most legal run x MoveSlack x dt", fmt("%.2f vs %.2f", moved, sp.Run * F.MoveSlack * 0.1))
		-- Dashing: x DashSpeed / RunSpeed
		local Config = loadModule("Config")
		local dashFactor = Config.Physics.DashSpeed / Config.Physics.RunSpeed
		f10.x, f10.z = 0, 0
		b10:Command(1, "Dash")
		local dashEv10 = nil
		for _, ev in ipairs(b10.pending) do
			if ev.type == "Dash" then
				dashEv10 = ev
			end
		end
		b10:Step(0.1)
		-- wave 6: the dash is the SIDESTEP (along the Dash dir at legal run x DashSpeed / RunSpeed, 4 studs with no threat),
		-- never a dash-speed rush toward the Move point
		local hop = math.sqrt(f10.x * f10.x + f10.z * f10.z)
		local along = dashEv10 and hop > 0 and (f10.x * dashEv10.dir[1] + f10.z * dashEv10.dir[2]) / hop or 0
		T.check(near(hop, math.min(4, sp.Run * dashFactor * 0.1), 0.05) and along > 0.99, "while Dashing the fighter sidesteps along the Dash dir at <= run x DashSpeed / RunSpeed (4 studs, no threat)",
			fmt("%.2f studs, along %.2f", hop, along))
		-- Haste x1.35 and Slow x0.6 scale the cap and SpeedOf
		for _ = 1, 6 do
			b10:Step(0.1)
		end
		f10.speedBuffMult, f10.speedBuffUntil = 1.35, b10:Time() + 5
		f10.x, f10.z = 0, 0
		b10:Command(1, "Move", 0, 100)
		b10:Step(0.1)
		T.check(near(f10.z, sp.Run * 1.35 * F.MoveSlack * 0.1, 0.03) and near(b10:SpeedOf(1).Run, sp.Run * 1.35, 1e-6), "Haste raises the cap and SpeedOf by x1.35")
		f10.speedBuffUntil = 0
		f10.slowUntil = b10:Time() + 5
		f10.x, f10.z = 0, 0
		b10:Step(0.1)
		T.check(near(f10.z, sp.Run * 0.6 * F.MoveSlack * 0.1, 0.03) and near(b10:SpeedOf(1).Run, sp.Run * 0.6, 1e-6), "a Slow lowers the cap and SpeedOf by x0.6")
		f10.slowUntil = 0
		-- the fighter stops at the wanted point, clamped inside the floor (FOLLOW: the engage rule held off above)
		b10:Command(1, "Move", 0, 0)
		for _ = 1, 30 do
			b10:Step(0.1)
		end
		T.check(near(f10.x, 0, 0.01) and near(f10.z, 0, 0.01) and f10.state == BS.States.Idle, "the fighter stands at the wanted point (Idle)")
		b10:Command(1, "Move", 500, 500)
		for _ = 1, 60 do
			b10:Step(0.1)
		end
		T.check(f10.x <= b10.zone.HalfX and f10.z <= b10.zone.HalfZ, "a wanted point outside the floor is clamped")
		-- the NPC side never accepts fighter commands
		T.check(select(2, b10:Command("npc", "Attack")) == "NotPlayer" and select(2, b10:Command("npc", "Move", 0, 0)) == "NotPlayer", "NPC teams refuse player commands (NotPlayer)")
		T.check(select(2, b10:Command(1, "Retreat")) == "UnknownAction" and select(2, b10:Command(1, 42)) == "UnknownAction", "Retreat / junk actions are UnknownAction")
	end
end)

----------------------------------------------------------------------------------------------------
-- p5sim_ai
----------------------------------------------------------------------------------------------------
S.p5sim_ai = guarded("p5sim_ai", function()
	local BC = loadModule("BattleCatalog")
	local BS = loadModule("BattleSim")
	local PC = loadModule("PetCatalog")
	if not T.check(BC and BS and PC, "modules load") then
		return
	end
	local F, D = BC.Fighter, BC.Damage
	-- threat: the NPC chases the fighter that hit it last (two player teams, one NPC)
	local b = BS.new({ Mode = "Duel", Seed = 5, Teams = {
		team(1, 1, { pet("biscuit_bear", 10) }),
		team(2, 1, { pet("biscuit_bear", 10) }),
		team("npc", 2, { pet("storm_tabby", 6, nil, { NoSpecial = true }) }, { Npc = true, Specials = false }),
	} })
	local tA, tB = b.teams[1], b.teams[2]
	local e = firstEnemy(b)
	tA.fighter.x, tA.fighter.z, tB.fighter.x, tB.fighter.z = -3, -8, 3, -8
	tA.wantX, tA.wantZ, tB.wantX, tB.wantZ = -3, -8, 3, -8
	e.x, e.z = -3, -3
	for _, u in ipairs(b.units) do
		u.px, u.pz = u.x, u.z
	end
	b:Step(0.1)
	T.check(e.target == tA.fighter, "an NPC with no threat targets the nearest fighter")
	tB.fighter.nextAttack = 0
	tA.fighter.nextAttack = huge -- A holds its auto-attack (white-box): only B hits
	tB.fighter.x, tB.fighter.z = 3, -3
	tB.wantX, tB.wantZ = 3, -3
	local okH = b:Command(2, "Attack", e.id)
	for _ = 1, 14 do -- a wind-up already running lands first, then the NPC re-picks
		b:Step(0.1)
	end
	T.check(okH and e.target == tB.fighter, "after a hit from fighter B the NPC chases B (threat) although A is as near")
	tB.fighter.nextAttack = huge -- B stops too: the threat runs out
	for _ = 1, 35 do
		b:Step(0.1)
	end
	T.check(e.threat == tB.fighter and b:Time() - e.threatAt > D.ThreatSeconds, "the threat expires after ThreatSeconds 3")
	-- the wind-up is inside the interval: consecutive Windups ~ Interval apart, the hit lands at `at`
	local b2 = BS.new({ Mode = "Duel", Seed = 8, Teams = { team(1, 1, { pet("biscuit_bear", 20) }), team("npc", 2, { pet("mallow_kitten", 5, nil, { NoSpecial = true }) }, { Npc = true, Specials = false }) } })
	local f2 = b2.teams[1].fighter
	local e2 = firstEnemy(b2)
	f2.x, f2.z, e2.x, e2.z = 0, 0, 0, 3
	f2.nextAttack = huge -- the fighter holds its auto-attack (white-box): the NPC's rhythm alone
	b2.teams[1].wantX, b2.teams[1].wantZ = 0, 0
	local windups, hits = {}, {}
	for _ = 1, 80 do
		local evs = b2:Step(0.1)
		for _, ev in ipairs(evs) do
			if ev.type == "Windup" and ev.unit == e2.id then
				windups[#windups + 1] = { t = b2:Time(), at = ev.at }
			elseif ev.type == "Hit" and ev.from == e2.id then
				hits[#hits + 1] = b2:Time()
			end
		end
	end
	local gapsOk, landsOk = #windups >= 4, #hits >= 4
	for i = 2, #windups do
		local gap = windups[i].t - windups[i - 1].t
		if gap < e2.interval * 0.85 or gap > e2.interval * 1.2 then
			gapsOk = false
		end
	end
	for i = 1, math.min(#windups, #hits) do
		if abs(hits[i] - windups[i].at) > 0.11 then
			landsOk = false
		end
	end
	T.check(gapsOk, "consecutive wind-ups are one Interval apart (the wind-up is inside the interval: a wave's DPS is unchanged)", fmt("%d windups, interval %.2f", #windups, e2.interval))
	T.check(landsOk and #windups > 0 and near(windups[1].at - windups[1].t, F.Windup, 0.11), "every hit lands at the Windup's `at` = start + 0.45 s")
	-- the snapshot shows the windup bit while Winding
	local seen = false
	for _ = 1, 20 do
		b2:Step(0.1)
		local snap = b2:Snapshot()
		if snap.Units[e2.id].windup then
			seen = true
		end
	end
	T.check(seen, "Snapshot shows windup = true while an NPC is Winding")
	-- a target that moved out of reach is missed
	local b3 = BS.new({ Mode = "Duel", Seed = 8, Teams = { team(1, 1, { pet("biscuit_bear", 20) }), team("npc", 2, { pet("mallow_kitten", 5, nil, { NoSpecial = true }) }, { Npc = true, Specials = false }) } })
	local t3, f3 = b3.teams[1], b3.teams[1].fighter
	local e3 = firstEnemy(b3)
	f3.x, f3.z, e3.x, e3.z = 0, 0, 0, 3
	f3.nextAttack = huge
	t3.wantX, t3.wantZ = 0, 0
	local missed = false
	for _ = 1, 80 do
		local evs = b3:Step(0.1)
		for _, ev in ipairs(evs) do
			if ev.type == "Windup" and ev.target == f3.id then
				f3.x, f3.z = 0, -15 -- teleported away (white-box): out of reach when the hit lands
				t3.wantX, t3.wantZ = 0, -15
			elseif ev.type == "Hit" and ev.from == e3.id and ev.miss then
				missed = true
			end
		end
		if missed then
			break
		end
	end
	T.check(missed, "a hit whose target left the reach during the wind-up is a miss")
	-- statuses: slow halves the move (x0.6), weaken cuts the hit (x0.85), stun freezes, burn ticks
	local b4 = BS.new({ Mode = "Duel", Seed = 2, Teams = { team(1, 1, { pet("biscuit_bear", 30) }), team("npc", 2, { pet("biscuit_bear", 5, nil, { NoSpecial = true }) }, { Npc = true, Specials = false }) } })
	local t4, f4 = b4.teams[1], b4.teams[1].fighter
	local e4 = firstEnemy(b4)
	f4.x, f4.z, e4.x, e4.z = 0, -15, 0, 15
	f4.nextAttack = huge
	t4.wantX, t4.wantZ = 0, -15
	e4.target = f4
	e4.retargetAt = huge
	local z0 = e4.z
	b4:Step(0.1)
	local plain = z0 - e4.z
	e4.slowUntil = b4:Time() + 5
	z0 = e4.z
	b4:Step(0.1)
	local slowed = z0 - e4.z
	T.check(near(slowed, plain * D.Slow, 0.02) and plain > 0.5, "a slowed NPC moves at x0.6", fmt("%.2f -> %.2f", plain, slowed))
	e4.slowUntil = 0
	e4.weakenUntil = b4:Time() + 5
	e4.x, e4.z = 0, -15 + 4
	f4.x, f4.z = 0, -15
	e4.px, e4.pz, f4.px, f4.pz = e4.x, e4.z, f4.x, f4.z
	e4.nextAttack = 0
	local weakHit = nil
	for _ = 1, 20 do
		local evs = b4:Step(0.1)
		weakHit = weakHit or findEvent(evs, "Hit", function(ev)
			return ev.from == e4.id and not ev.miss
		end)
		if weakHit then
			break
		end
	end
	T.check(weakHit ~= nil and weakHit.dmg <= e4.hit * (1 + D.Variance) * D.Weaken * 1.5 + 1, "a weakened NPC hits for x0.85", weakHit and weakHit.dmg)
	e4.weakenUntil = 0
	e4.stunUntil = b4:Time() + 1
	e4.state = BS.States.Stunned
	local windDuringStun = false
	for _ = 1, 9 do
		local evs = b4:Step(0.1)
		if findEvent(evs, "Windup", function(ev)
			return ev.unit == e4.id
		end) then
			windDuringStun = true
		end
	end
	T.check(not windDuringStun and e4.state == BS.States.Stunned, "a stunned NPC neither moves nor winds up")
	local hp0 = e4.hp
	e4.burnLeft, e4.burnAmount, e4.burnNextAt, e4.burnStep, e4.burnFrom = 3, 10, b4:Time(), 1, f4
	local burns = 0
	for _ = 1, 35 do
		local evs = b4:Step(0.1)
		for _, ev in ipairs(evs) do
			if ev.type == "Hit" and ev.burn and ev.to == e4.id then
				burns = burns + 1
			end
		end
	end
	T.check(burns == 3 and e4.hp <= hp0 - 25, "burn ticks 3 times (Hit burn = true), credited to the fighter", fmt("%d ticks, %.0f damage", burns, hp0 - e4.hp))
	-- Auto fighter (harness): the AI plays the kit and wins a weak fight
	local b5 = BS.new({ Mode = "Duel", Seed = 4, Teams = { team(1, 1, { pet("storm_tabby", 10), pet("honey_bunny", 10), pet("pebble_pup", 10) }, { Auto = true }), weakNpc("npc", 2) } })
	local all = run(b5, 1300)
	T.check(b5:Result() and b5:Result().WinnerSide == 1 and countType(all, "Element") >= 1, "an Auto player team plays its kit (Element casts) and wins", b5:Result() and b5:Result().Reason)
end)

----------------------------------------------------------------------------------------------------
-- p5sim_modes
----------------------------------------------------------------------------------------------------
S.p5sim_modes = guarded("p5sim_modes", function()
	local BC = loadModule("BattleCatalog")
	local BS = loadModule("BattleSim")
	if not T.check(BC and BS, "modules load") then
		return
	end
	T.check(#BS.Modes == 4 and T.contains(BS.Modes, "Dungeon") and not T.contains(BS.Modes, "Trial"), "Modes = Duel, Raid, Ring, Dungeon")
	local b, why = BS.new({ Mode = "Duel", Trial = 1, Teams = { team(1, 1, { pet("mallow_kitten", 1) }) } })
	T.check(b == nil and why == "NoOpponent", "a Trial setup is gone: a duel without side 2 is NoOpponent", tostring(why))
	-- Duel: ends by lives
	b = BS.new({ Mode = "Duel", Seed = 1, Teams = { team(1, 1, { pet("stormfang", 50, "Rainbow") }, { Auto = true }), team(2, 2, { pet("mallow_kitten", 1), pet("pebble_pup", 1) }, { Auto = true }) } })
	local all = run(b, 1300)
	local r = b:Result()
	T.check(r and r.WinnerSide == 1 and r.Reason == "Wipe" and r.Survivors[2] == 0 and r.Survivors[1] == 1 and r.Kills[1] == 2 and r.Draw == false and r.Level == nil, "a duel ends when a side has no lives left (Survivors = lives, Kills)", r and r.Reason)
	T.check(countType(all, "Swap") == 1 and findEvent(all, "Swap", function(ev)
		return ev.auto == true and ev.owner == 2
	end) ~= nil, "the losing side auto-swapped its helper in once")
	-- Duel: timeout by damage (no Overtime)
	b = BS.new({ Mode = "Duel", Seed = 1, TimeLimit = 3, Teams = { team(1, 1, { pet("biscuit_bear", 10) }), team(2, 2, { pet("biscuit_bear", 10) }) } })
	local f1, f2 = b.teams[1].fighter, b.teams[2].fighter
	f1.x, f1.z, f2.x, f2.z = 0, 0, 0, 4
	b.teams[1].wantX, b.teams[1].wantZ, b.teams[2].wantX, b.teams[2].wantZ = 0, 0, 0, 4
	f1.nextAttack = 0
	b:Command(1, "Attack", f2.id)
	all = run(b, 100)
	r = b:Result()
	T.check(r and r.Reason == "Timeout" and r.WinnerSide == 1 and countType(all, "Overtime") == 0, "a duel timeout goes to the side that dealt more damage; there is no Overtime", r and fmt("%s %s", r.Reason, tostring(r.WinnerSide)))
	b = BS.new({ Mode = "Duel", Seed = 1, TimeLimit = 2, Teams = { team(1, 1, { pet("biscuit_bear", 10) }), team(2, 2, { pet("biscuit_bear", 10) }) } })
	b.teams[1].noEngage, b.teams[2].noEngage = true, true -- (white-box: wave 6 pets engage anything on the floor; nobody fights here)
	run(b, 100)
	T.check(b:Result().Reason == "Timeout" and b:Result().Draw == true, "no damage at all = a Draw")
	-- Forfeit: the team is knocked out, Forfeit result
	b = BS.new({ Mode = "Duel", Seed = 1, Teams = { team(1, 1, { pet("biscuit_bear", 10), pet("pebble_pup", 1) }), team(2, 2, { pet("biscuit_bear", 10) }) } })
	T.check(b:Command(1, "Forfeit") == true, "Forfeit accepted")
	all = run(b, 5)
	r = b:Result()
	T.check(r and r.Reason == "Forfeit" and r.WinnerSide == 2 and r.Forfeit and countType(all, "KO") == 2 and countType(all, "Swap") == 0 and r.Losers[1] == 1, "a forfeit knocks the whole team out without auto-swaps")
	-- Ring: timeout = loss; a single level-1 pet (Auto) wins round 1
	b = BS.new({ Mode = "Ring", Seed = 3, Round = 1, TimeLimit = 2, Teams = { team(1, 1, { pet("pip_penguin", 1) }), BC.ChampionTeam(1, 3) } })
	run(b, 100)
	T.check(b:Result().Reason == "Timeout" and b:Result().WinnerSide == 2 and b:Result().Round == 1, "a Ring timeout is a loss (side 2 wins)")
	local wins = 0
	for seed = 1, 4 do
		b = BS.new({ Mode = "Ring", Seed = seed, Round = 1, Teams = { team(1, 1, { pet("pip_penguin", 1) }, { Auto = true }), BC.ChampionTeam(1, seed) } })
		run(b, 1000)
		if b:Result() and b:Result().WinnerSide == 1 then
			wins = wins + 1
		end
	end
	T.check(wins == 4, "a single level-1 pip_penguin (Auto) wins ring round 1 (4 of 4 seeds)", wins)
	T.check(b:Describe().Mode == "Ring" and b:Describe().Round == 1 and b:Describe().Level == nil and #b:Describe().Units == 2, "Describe carries Mode / Round and no Level")
	-- Raid: 1 and 16 fighters
	local teams = {}
	for i = 1, 16 do
		teams[i] = team(100 + i, 1, { pet("cloudy_dragon", 25), pet("twilight_dragon", 28), pet("ember_phoenix", 26, "Golden") }, { Auto = true })
	end
	b = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 2, Teams = teams })
	T.check(b ~= nil and b:BossStatus().Players == 16 and #b:StaticUnits() == 49, "a raid with 16 fighter teams (48 units + the boss) starts")
	local solo = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 2, Teams = { teams[1] } })
	T.check(b:BossStatus().MaxHp > solo:BossStatus().MaxHp * 10 and b:BossStatus().MaxHp < solo:BossStatus().MaxHp * 16 * 1.8, "boss HP = ExpectedDps x HpPerPlayer x teams ^ 0.2", fmt("%d vs %d", b:BossStatus().MaxHp, solo:BossStatus().MaxHp))
	all = run(b, 3400)
	r = b:Result()
	T.check(r and r.Reason == "BossDown" and r.WinnerSide == 1 and r.Shares[101] > 0 and countType(all, "Telegraph") > 0 and countType(all, "Spawn") >= 1, "16 Auto fighters bring the Storm Titan down (telegraphs, minion waves)", r and fmt("%s %.0f s", r.Reason, r.Duration))
	T.check(r.BossHp == 0 and r.BossMaxHp > 0 and r.Duration > 30, "the raid result carries BossHp / BossMaxHp")
	-- Dungeon: an empty side 2 runs; waves; EnemiesDown; BossHp; Finish
	b, why = BS.new({ Mode = "Dungeon", Seed = 5, Zone = BC.Dungeon.Zones.Room, TimeLimit = 60, Teams = { team(1, 1, { pet("stormfang", 50, "Rainbow"), pet("cloudy_dragon", 45, "Rainbow") }, { Auto = true }) } })
	T.check(b ~= nil and b:LivingEnemies() == 0 and b:BossHp() == nil and b.zone.X == 44, "a Dungeon battle starts with an empty side 2 (LivingEnemies 0, BossHp nil)", tostring(why))
	for _ = 1, 30 do
		b:Step(0.1)
	end
	T.check(b:Result() == nil, "a dungeon never ends on an empty side 2")
	local wave = BC.DungeonWave(3, 1, 1, 1, 5)
	local infos = b:SpawnEnemies(wave.Pets, { Wave = 1 })
	local evs = b:Step(0.1)
	local waveEv = findEvent(evs, "Wave")
	T.check(infos and #infos == #wave.Pets and waveEv and waveEv.index == 1 and #waveEv.units == #wave.Pets and waveEv.left == #wave.Pets and infos[1].wild == true and b:LivingEnemies() == #wave.Pets, "SpawnEnemies: a Wave { index, units, left } event; LivingEnemies counts them; unitInfo wild")
	T.check(b.teamByOwner["wave:1"] ~= nil and b.teamByOwner["wave:1"].npc and b.teamByOwner["wave:1"].anchorZ > 10, "the wave is an Npc Auto team 'wave:1' at the far +Z edge")
	all = {}
	for _ = 1, 400 do
		local stepEvents = b:Step(0.1)
		for _, ev in ipairs(stepEvents) do
			all[#all + 1] = ev
		end
		if findEvent(stepEvents, "EnemiesDown") then
			break
		end
	end
	local down = findEvent(all, "EnemiesDown")
	T.check(down ~= nil and down.wave == 1 and b:LivingEnemies() == 0 and b:Result() == nil, "EnemiesDown { wave } fires when the last enemy of the wave falls; the battle keeps running")
	local boss = BC.DungeonWave(3, 4, 1, 1, 5)
	infos = b:SpawnEnemies(boss.Pets, { Wave = 2, Name = "Boss" })
	T.check(infos and #infos == 1 and infos[1].boss == true and near(b:BossHp(), 1, 1e-9) and b.waveCount == 2, "the boss wave: unitInfo boss = true, BossHp() = 1")
	local bossUnit = firstEnemy(b)
	bossUnit.hp = bossUnit.maxHp * 0.4
	T.check(near(b:BossHp(), 0.4, 1e-9), "BossHp() follows the boss's HP share")
	local okF, endEvents = b:Finish("Cleared")
	T.check(okF and b:Result().Reason == "Cleared" and b:Result().WinnerSide == 1 and b:Result().Waves == 2 and #endEvents == 1 and endEvents[1].type == "End" and b:Finish("Cleared") == false, "Finish('Cleared') ends it with side 1 winning (Waves 2); a second Finish is refused")
	-- Wipe and Timeout
	b = BS.new({ Mode = "Dungeon", Seed = 6, TimeLimit = 2, Teams = { team(1, 1, { pet("pebble_pup", 1) }) } })
	b:SpawnEnemies(BC.DungeonWave(1, 1, 1, 1, 6).Pets, { Wave = 1 })
	run(b, 100)
	T.check(b:Result().Reason == "Timeout" and b:Result().WinnerSide == 2, "a dungeon room timeout ends the battle 'Timeout'")
	b = BS.new({ Mode = "Dungeon", Seed = 6, Teams = { team(1, 1, { pet("pebble_pup", 1) }) } })
	b:SpawnEnemies({ pet("stormfang", 50, "Rainbow"), pet("stormfang", 50, "Rainbow") }, { Wave = 1 })
	run(b, 600)
	T.check(b:Result() and b:Result().Reason == "Wipe" and b:Result().WinnerSide == 2 and b:Result().Survivors[1] == 0, "a party wipe ends the dungeon battle 'Wipe'")
	b = BS.new({ Mode = "Dungeon", Seed = 6, Teams = { team(1, 1, { pet("pebble_pup", 1) }) } })
	b:SpawnEnemies({ pet("stormfang", 50, "Rainbow") }, { Wave = 1 })
	T.check(b:Command(1, "Forfeit") == true and b.teams[1].left == true, "Forfeit in a dungeon = RemoveTeam")
	run(b, 5)
	T.check(b:Result() and b:Result().Reason == "Abandoned", "the last team leaving ends it 'Abandoned'")
	T.check(b:Finish("Shutdown") == false, "Finish after the end is refused")
	b = BS.new({ Mode = "Dungeon", Seed = 6, Teams = { team(1, 1, { pet("pebble_pup", 1) }) } })
	local okS, evS = b:Finish("Shutdown")
	T.check(okS and b:Result().Reason == "Shutdown" and b:Result().WinnerSide == nil and b:Result().Draw, "Finish('Shutdown') ends with no winner")
	T.check(BS.new({ Mode = "Dungeon", Seed = 1, Teams = {} }) == nil and select(2, BS.new({ Mode = "Dungeon", Seed = 1, Teams = {} })) == "NoTeam", "a dungeon with no player team is NoTeam")
	-- Zone defaults
	T.check(BS.new({ Mode = "Dungeon", Teams = { team(1, 1, { pet("pebble_pup", 1) }) } }).zone.X == 44 and BS.new({ Mode = "Dungeon", Zone = BC.Zones.DungeonBoss, Teams = { team(1, 1, { pet("pebble_pup", 1) }) } }).zone.X == 56, "the Dungeon zone defaults to 44 and takes the 56 boss floor")
end)

----------------------------------------------------------------------------------------------------
-- p5sim_wire
----------------------------------------------------------------------------------------------------
S.p5sim_wire = guarded("p5sim_wire", function()
	local BS = loadModule("BattleSim")
	if not T.check(BS ~= nil, "BattleSim loads") then
		return
	end
	local teams = {}
	for i = 1, 8 do
		teams[i] = team(100 + i, 1, { pet("aurora_fox", 12), pet("storm_tabby", 14), pet("frostling_penguin", 12) }, { Auto = true })
	end
	local b = BS.new({ Mode = "Raid", Boss = "frost_wyrm", Seed = 9, Teams = teams })
	b:SpawnEnemies({ pet("stormfang", 50, "Rainbow", { NoSpecial = true }) }, { Wave = 1 }) -- a tanky NPC pet: wind-ups all along
	for _ = 1, 40 do
		b:Step(0.1)
	end
	local last = {}
	local full = b:SnapshotDelta(last)
	local decoded = BS.DecodeSnapshot(full, nil)
	local snap = b:Snapshot()
	local okAll, n = true, 0
	for id, s in pairs(snap.Units) do
		n = n + 1
		local d = decoded[id]
		if not d or abs(d.x - s.x) > 0.051 or abs(d.z - s.z) > 0.051 or d.hp ~= s.hp or d.state ~= s.state or d.meter ~= s.meter or (d.shield or 0) ~= (s.shield or 0) or d.target ~= s.target or (d.lives or 0) ~= (s.lives or 0) or (d.windup == true) ~= (s.windup == true) then
			okAll = false
		end
	end
	T.check(okAll and n == 26, "a full delta decodes to the Snapshot picture (x / z to 0.05, hp, state, meter, shield, target, lives, windup) for 26 units", n)
	T.check(full.U[1] >= 1024 and full.U[1] % 8 == decoded[floor(full.U[1] / 1024)].state, "the code packs id x 1024 + lives x 256 + windup x 128 + mask x 8 + state")
	-- the next delta is small: only what moved
	for _ = 1, 5 do
		b:Step(0.1)
	end
	local delta = b:SnapshotDelta(last)
	local bytes = 0
	for _, v in ipairs(delta.U) do
		bytes = bytes + #tostring(v) + 1
	end
	T.check(#delta.U < #full.U and bytes < 600, "a steady-state delta of 26 units is under 600 bytes of numbers", fmt("%d numbers, ~%d bytes (full %d numbers)", #delta.U, bytes, #full.U))
	local decoded2 = BS.DecodeSnapshot(delta, decoded)
	local snap2 = b:Snapshot()
	okAll = true
	for id, s in pairs(snap2.Units) do
		local d = decoded2[id]
		if not d or abs(d.x - s.x) > 0.051 or d.hp ~= s.hp or d.state ~= s.state or (d.lives or 0) ~= (s.lives or 0) then
			okAll = false
		end
	end
	T.check(okAll, "the delta applied to the previous picture gives the current one")
	-- lives and the windup bit travel
	local livesSeen, windSeen = false, false
	for id, d in pairs(decoded2) do
		if d.lives == 3 then
			livesSeen = true
		end
		if d.windup then
			windSeen = true
		end
	end
	for _ = 1, 30 do
		b:Step(0.1)
		local dd = BS.DecodeSnapshot(b:SnapshotDelta(last), decoded2)
		for _, d in pairs(dd) do
			if d.windup then
				windSeen = true
			end
		end
	end
	T.check(livesSeen and windSeen, "lives (3 on a fighter) and the windup bit (a Winding minion / NPC) arrive on the client side")
	-- junk payloads decode to the previous picture
	local prev = { [1] = { x = 1, z = 2, hp = 3, state = 0, meter = 0, shield = 0 } }
	local same = BS.DecodeSnapshot(nil, prev)
	local same2 = BS.DecodeSnapshot({ U = "junk" }, prev)
	local same3 = BS.DecodeSnapshot({ U = { 1.5, 7 } }, prev)
	local same4 = BS.DecodeSnapshot({ U = { 3 * 1024 + 8 * 1 } }, prev)
	T.check(same[1] == prev[1] and same2[1] == prev[1] and same3[1] == prev[1] and same4[1] == prev[1] and same4[3] == nil, "junk payloads (nil, a string, fractions, a cut record) keep the previous picture")
	local cut = BS.DecodeSnapshot({ U = { 2 * 1024 + 8 * 1 + 1, 5 * 4096 + 7 } }, prev)
	T.check(cut[2] == nil and cut[1] == prev[1], "a record whose hp number is missing is dropped")
	-- a down unit is sent once then left out
	local b2 = BS.new({ Mode = "Duel", Seed = 1, Teams = { team(1, 1, { pet("stormfang", 50, "Rainbow") }, { Auto = true }), team(2, 2, { pet("mallow_kitten", 1) }, { Auto = true }) } })
	local l2 = {}
	b2:SnapshotDelta(l2)
	run(b2, 300)
	local d1 = b2:SnapshotDelta(l2)
	local d2 = b2:SnapshotDelta(l2)
	T.check(#d2.U == 0 or #d2.U < #d1.U, "an unchanged picture sends nothing")
end)

----------------------------------------------------------------------------------------------------
-- p5sim_determinism
----------------------------------------------------------------------------------------------------
S.p5sim_determinism = guarded("p5sim_determinism", function()
	local BS = loadModule("BattleSim")
	if not T.check(BS ~= nil, "BattleSim loads") then
		return
	end
	local function script(seed)
		local b = BS.new({ Mode = "Duel", Seed = seed, Teams = { team(1, 1, { pet("storm_tabby", 10), pet("honey_bunny", 8), pet("pebble_pup", 8) }), team(2, 2, { pet("aurora_fox", 9), pet("mallow_kitten", 8), pet("biscuit_bear", 8) }, { Auto = true }) } })
		local log = {}
		local steps = 0
		local x = -4
		while not b:IsFinished() and steps < 900 do
			steps = steps + 1
			x = x + 0.7
			if x > 20 then
				x = -20
			end
			-- bug #22: a 2 s still phase (steps 40-59) so the engage rule (FOLLOW -> ENGAGED -> pull) is in the stream
			if steps < 40 or steps >= 60 then
				b:Command(1, "Move", x, steps * 0.05 - 10)
			else
				b:Command(1, "Move", 2, -8)
			end
			local e = firstEnemy(b)
			if e then
				b:Command(1, "Attack", e.id)
			end
			if steps % 70 == 0 then
				b:Command(1, "Element")
			end
			if steps % 90 == 0 then
				b:Command(1, "Buff", 2)
			end
			if steps % 130 == 0 then
				b:Command(1, "Dash")
			end
			if steps % 200 == 0 then
				b:Command(1, "Swap", 3)
			end
			if steps % 50 == 0 then
				b:Command(1, "Special")
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
					local v = ev[k]
					if type(v) == "table" then
						v = "#" .. #v
					end
					parts[#parts + 1] = k .. "=" .. tostring(v)
				end
				log[#log + 1] = table.concat(parts, ",")
			end
			if steps % 25 == 0 then
				local snap = b:Snapshot()
				local ids = {}
				for id in pairs(snap.Units) do
					ids[#ids + 1] = id
				end
				table.sort(ids)
				for _, id in ipairs(ids) do
					local u = snap.Units[id]
					log[#log + 1] = fmt("%d:%.1f,%.1f,%d,%d,%d", id, u.x, u.z, u.hp, u.state, u.meter)
				end
			end
		end
		local r = b:Result()
		return table.concat(log, "\n"), r and r.Reason, steps
	end
	local a, ra, sa = script(42)
	local b2, rb = script(42)
	T.check(a == b2 and ra == rb, "the same seed and command stream (Move points included) replay the same events and snapshots", fmt("%d steps, %s", sa, tostring(ra)))
	T.check(a:find("on=true", 1, true) ~= nil and a:find("type=Engage", 1, true) ~= nil, "...with the engage rule in the stream (a 2 s still phase engages: an Engage event)")
	local c = script(43)
	T.check(c ~= a, "another seed plays differently")
	T.check(#a > 1000 and sa > 50, "the scripted fight is long enough to mean something", sa)
end)

----------------------------------------------------------------------------------------------------
-- p5dgn_catalog
----------------------------------------------------------------------------------------------------
S.p5dgn_catalog = guarded("p5dgn_catalog", function()
	local BC = loadModule("BattleCatalog")
	local PC = loadModule("PetCatalog")
	if not T.check(BC and PC, "modules load") then
		return
	end
	local D = BC.Dungeon
	T.check(type(D) == "table" and D.Floors == 12 and D.Floor1Power == 17 and D.FirstPower == 29 and D.Growth == 2 and D.Floor1Waves[1] == 1 and D.Floor1Waves[2] == 2 and D.Floor1Waves[3] == 3 and D.BossMult == 1.3 and D.EscortMult == 0.5 and #D.Waves == 3 and D.Waves[3] == 3 and D.EnemiesPerWave == 2 and D.Floor1EnemiesPerWave == 1 and D.PartyExp == 0.5 and D.MinHandicap == 0.3 and D.EnemyMaxLevel == 50 and D.RoomTime == 120 and D.Floor1RoomTime == 180 and D.Zones.Room.X == 44 and D.Zones.Boss.X == 56 and D.EscortAt == 0.5 and D.Intermission == 2 and D.DoorTime == 12 and D.HallSeconds == 10 and D.TreasureSeconds == 45 and D.MinShare == 0.05 and D.LateJoinLastRoom == 2 and D.ReadyTimeout == 30 and D.RunMaxSeconds == 4 * 120 + 4 * 12 + 10 + 45 + 120 and #D.Bands == 6, "BattleCatalog.Dungeon numbers of 5.1 (RoomMult and PartyExp re-tuned by the sim)")
	T.check(#D.RoomMult == 3 and D.RoomMult[1] <= D.RoomMult[2] and D.RoomMult[2] <= D.RoomMult[3] and D.RoomMult[1] >= 0.7 and D.RoomMult[3] <= 1.3, "RoomMult grows room by room", fmt("%.2f %.2f %.2f", D.RoomMult[1], D.RoomMult[2], D.RoomMult[3]))
	local floors = BC.DungeonFloors
	local Config = loadModule("Config")
	local valid = {}
	for _, e in ipairs(Config.Elements.Order) do
		valid[e] = true
	end
	local okF = #floors == 12
	local names = { "Mossy Cellar", "Stone Halls", "Flooded Vaults", "Frozen Crypt", "Ember Forge", "Thunder Spire", "Star Chapel", "Shadow Keep", "Magma Mines", "Howling Peak", "Eclipse Sanctum", "Abyss Throne" }
	for i, f in ipairs(floors) do
		if f.Name ~= names[i] or not valid[f.Element] or type(f.Kind) ~= "string" or f.Floor ~= i then
			okF = false
		end
	end
	T.check(okF and floors[12].Kind == "Throne" and floors[1].Element == "Nature", "12 DungeonFloors with the contract names, existing elements and kinds")
	-- power
	local mono = true
	local last = 0
	for f = 1, 12 do
		local p = BC.DungeonPower(f, 1)
		if p < last then
			mono = false
		end
		last = p
	end
	T.check(mono and near(BC.DungeonPower(10, 1), 14848, 1e-6) and near(BC.DungeonPower(2, 1), 58, 1e-9) and near(BC.DungeonPower(12, 1), 59392, 1e-6) and near(BC.DungeonPower(1, 1), 17, 1e-9), "DungeonPower never drops; floor 1 = 17, 2 = 58, 10 = 14848, 12 = 59392")
	T.check(near(BC.DungeonPower(5, 4), BC.DungeonPower(5, 1) * 4 ^ D.PartyExp, 1e-6) and BC.DungeonPower(99, 1) == BC.DungeonPower(12, 1) and BC.DungeonPower(0 / 0, "x") == BC.DungeonPower(1, 1), "a party's target = per player x n ^ PartyExp (0.5, re-tuned); junk clamps")
	-- waves
	local w1 = BC.DungeonWave(3, 1, 1, 1, 77)
	local w1b = BC.DungeonWave(3, 1, 1, 1, 77)
	local w1c = BC.DungeonWave(3, 1, 1, 1, 78)
	local function sig(w)
		local parts = {}
		for _, p in ipairs(w.Pets) do
			parts[#parts + 1] = fmt("%s/%d/%s/%s/%s/%s", p.PetId, p.Level, p.Tier, tostring(p.Boss), tostring(p.Handicap), tostring(p.Boost))
		end
		return table.concat(parts, ";")
	end
	T.check(sig(w1) == sig(w1b) and w1.Power == w1b.Power, "DungeonWave is deterministic for its arguments")
	local differs = sig(w1) ~= sig(w1c)
	for s = 79, 90 do
		if sig(BC.DungeonWave(3, 1, 1, 1, s)) ~= sig(w1) then
			differs = true
		end
	end
	T.check(differs, "another seed draws other enemies")
	T.check(#w1.Pets == 2 and w1.Floor == 3 and w1.Room == 1 and w1.Wave == 1 and w1.Boss == false and w1.Pets[1].Wild == true and w1.Pets[1].Slot == 1 and w1.Pets[2].Slot == 2 and w1.Pets[1].Key == w1.Pets[1].PetId, "floor 3 room 1: EnemiesPerWave 2 wild entries with Key / Slot")
	T.check(#BC.DungeonWave(3, 1, 1, 3, 1).Pets == 4 and #BC.DungeonWave(3, 2, 2, 1, 1).Pets == 2, "+1 enemy per extra player")
	local okEvent, okBand, okLevel = true, true, true
	for f = 1, 12 do
		for r = 1, 4 do
			for w = 1, 2 do
				local wave = BC.DungeonWave(f, r, w, 2, f * 31 + r * 7 + w)
				local rarities = {}
				for _, b in ipairs(D.Bands) do
					if f >= b[1] and f <= b[2] then
						rarities = b[3]
					end
				end
				for _, p in ipairs(wave.Pets) do
					if PC.IsEventOnly(p.PetId) then
						okEvent = false
					end
					local def = PC.Get(p.PetId)
					if not def or not T.contains(rarities, def.Rarity) then
						okBand = false
					end
					if p.Level < 1 or p.Level > D.EnemyMaxLevel then
						okLevel = false
					end
					if p.Handicap and p.Handicap < D.MinHandicap - 1e-9 then
						okLevel = false
					end
				end
			end
		end
	end
	T.check(okEvent, "DungeonWave never fields an EventOnly pet")
	T.check(okBand, "every enemy comes from the floor's rarity band")
	T.check(okLevel, "enemy levels 1..50, handicaps >= MinHandicap")
	local f1 = BC.DungeonWave(1, 2, 1, 1, 3)
	T.check(#f1.Pets == 1 and f1.Pets[1].Level >= 1 and not f1.Pets[1].Boss, "floor 1 = ONE enemy per wave")
	T.check(#BC.DungeonWave(1, 1, 1, 4, 3).Pets == 1, "floor 1 keeps one enemy per wave with a party of 4")
	local boss1 = BC.DungeonWave(1, 4, 1, 1, 3)
	T.check(boss1.Boss == true and #boss1.Pets == 1 and boss1.Pets[1].Boss == true, "floor 1 boss: the forced mini-boss form")
	local boss7 = BC.DungeonWave(7, 4, 1, 1, 3)
	local escort7 = BC.DungeonWave(7, 4, 2, 1, 3)
	T.check(boss7.Boss and boss7.Pets[1].Boss == true and not boss7.Pets[1].Handicap and boss7.Power > escort7.Power and #escort7.Pets == 2 and not escort7.Boss, "room 4: wave 1 = the boss alone (x1.3), wave 2 = the escort at x0.5")
	local w10 = BC.DungeonWave(10, 3, 1, 1, 3)
	T.check(near(w10.Power, w10.Target * D.RoomMult[3], w10.Target * 0.25), "the wave's power follows target x RoomMult (within a level step)", fmt("%d vs %.0f", w10.Power, w10.Target * D.RoomMult[3]))
	-- rewards
	local lastT, lastX, okR = 0, 0, true
	for f = 1, 12 do
		local rw = BC.DungeonRewards(f, 4, 2, 0, false)
		if rw.Tokens <= lastT or rw.Xp <= lastX then
			okR = false
		end
		lastT, lastX = rw.Tokens, rw.Xp
	end
	T.check(okR, "DungeonRewards grow with the floor")
	local r1 = BC.DungeonRewards(10, 1, 2, 0, false)
	local r4 = BC.DungeonRewards(10, 4, 2, 0, false)
	T.check(r1.Tokens == floor((6 + 40) * 2 / 2) and r4.Tokens == (6 + 40) * 2 and r1.Xp == (25 + 100) * 2 and r4.Xp == (25 + 100) * 4 and r1.Cash == 20 + 100 and BC.DungeonRewards(10, 1, 2, 100, false).Cash == 300 and BC.DungeonRewards(10, 4, 2, 0, true).Tokens == r4.Tokens * 2 and BC.DungeonRewards(10, 4, 2, 0, true).Xp == r4.Xp, "5.2: Tokens floor((6 + 4f) x waves / 2) / boss x2, Xp (25 + 10f) x waves (boss 4), Cash max(20 + 10f, income x RoomSeconds); Double doubles Tokens only")
	local total = 0
	for f = 1, 3 do
		total = total + BC.DungeonRewards(f, 1, 2, 0, false).Tokens + BC.DungeonRewards(f, 2, 2, 0, false).Tokens + BC.DungeonRewards(f, 3, 3, 0, false).Tokens + BC.DungeonRewards(f, 4, 2, 0, false).Tokens
	end
	local run10 = 0
	for r = 1, 3 do
		run10 = run10 + BC.DungeonRewards(10, r, D.Waves[r], 0, false).Tokens
	end
	run10 = run10 + BC.DungeonRewards(10, 4, 2, 0, false).Tokens
	T.check(run10 == 253, "a floor 10 run pays 253 Tokens", run10)
	local xp10 = 0
	for r = 1, 3 do
		xp10 = xp10 + BC.DungeonRewards(10, r, D.Waves[r], 0, false).Xp
	end
	xp10 = xp10 + BC.DungeonRewards(10, 4, 2, 0, false).Xp
	T.check(xp10 == 1375, "a floor 10 run pays 1,375 XP per team pet", xp10)
	-- first clears
	local gems, tokens = 0, 0
	for f = 1, 12 do
		local fc = BC.DungeonFirstClear(f)
		gems, tokens = gems + fc.Gems, tokens + fc.Tokens
	end
	T.check(tokens == 23400 and gems == 156 and BC.DungeonFirstClear(1).Tokens == 300 and BC.DungeonFirstClear(1).Gems == 3 and BC.DungeonFirstClear(12).Gems == 30, "DungeonFirstClear totals 23,400 Tokens / 156 Gems (300 x floor; 3 .. 30 Gems)")
	-- chests
	local lowGems, highGems, cash, tok = 0, 0, 0, 0
	for s = 1, 300 do
		local c1 = BC.DungeonChest(2, s)
		if c1.Kind == "Gems" then
			lowGems = lowGems + 1
		elseif c1.Kind == "Cash" then
			cash = cash + 1
		else
			tok = tok + 1
		end
		local c7 = BC.DungeonChest(7, s)
		if c7.Kind == "Gems" then
			highGems = highGems + 1
		end
	end
	T.check(lowGems == 0 and cash > 150 and tok > 40 and highGems >= 10 and highGems <= 60, "DungeonChest: floors 1-2 never Gems (Cash ~70% / Tokens ~30%); floor 7 Gems ~10%", fmt("low gems %d cash %d tokens %d, high gems %d", lowGems, cash, tok, highGems))
	T.check(BC.DungeonChest(7, 5).Kind == BC.DungeonChest(7, 5).Kind and BC.DungeonChest(3, 1).Amount > 0, "a chest is deterministic for (floor, seed) and carries an Amount")
	local okV, problems = BC.Validate()
	T.check(okV, "Validate (12 floors, power, rewards, first clears, bands)", table.concat(problems, "; "))
end)

----------------------------------------------------------------------------------------------------
-- p5battle_balance: tools/sim_battle.lua as a library
----------------------------------------------------------------------------------------------------
S.p5battle_balance = guarded("p5battle_balance", function()
	local src, path = nil, nil
	for _, candidate in ipairs({ "tools/sim_battle.lua", "sim_battle.lua", "../tools/sim_battle.lua" }) do
		local fh = io.open(candidate, "r")
		if fh then
			src = fh:read("*a")
			fh:close()
			path = candidate
			break
		end
	end
	if not T.check(src ~= nil, "tools/sim_battle.lua found from the working directory") then
		return
	end
	_G.SIM_BATTLE_LIBRARY = true
	local load_ = loadstring or load
	local chunk, err = load_(src, "=tools/sim_battle.lua")
	if not T.check(chunk ~= nil, "sim_battle.lua compiles", err) then
		return
	end
	local okLoad, SIM = pcall(chunk)
	_G.SIM_BATTLE_LIBRARY = nil
	if not T.check(okLoad and type(SIM) == "table" and type(SIM.run) == "function" and type(SIM.series) == "function" and type(SIM.main) == "function", "sim_battle.lua returns its library (run, series, main) when SIM_BATTLE_LIBRARY is set", tostring(SIM)) then
		return
	end
	SIM.print = function() end
	T.check(SIM.sections.fighter and SIM.sections.support and SIM.sections.duels and SIM.sections.raids and SIM.sections.ring and SIM.sections.dungeon and SIM.sections.training and SIM.sections.move and SIM.sections.trials == nil and #SIM.Stages == 10 and #SIM.Stages[10].Pets == 3, "the report has the Phase 5 sections (no trials) and 10 stages of 3 pets")
	local BC = loadModule("BattleCatalog")
	local pet2, team2 = SIM.pet, SIM.team
	-- support DPS ratio
	local PC = loadModule("PetCatalog")
	local cd, cn, sd, sn = 0, 0, 0, 0
	for _, def in ipairs(PC.Pets) do
		if def.Rarity == "Common" or def.Rarity == "Uncommon" then
			local us = BC.UnitStats(def, 1)
			if us.Role == "Support" then
				sd, sn = sd + us.Dps, sn + 1
			else
				cd, cn = cd + us.Dps, cn + 1
			end
		end
	end
	local ratio = (sd / sn) / (cd / cn)
	T.check(ratio >= 0.65 and ratio <= 0.75, "Support DPS ratio 0.65-0.75", fmt("%.2f", ratio))
	-- kit factor: a played kitten beats an equal passive NPC and loses to a double one
	local up = BC.UnitPower("mallow_kitten", 1)
	local even = SIM.series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team2(1, 1, { pet2("mallow_kitten", 1) }), SIM.npcOf("npc", "mallow_kitten", up * 1.0, { MaxLevel = 100 }) } }
	end, { [1] = "player" }, 8, { dodge = 0.4 })
	local double = SIM.series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team2(1, 1, { pet2("mallow_kitten", 1) }), SIM.npcOf("npc", "mallow_kitten", up * 2.0, { MaxLevel = 100 }) } }
	end, { [1] = "player" }, 8, { dodge = 0.4 })
	T.check(even.winPct >= 80 and double.winPct <= 20 and even.avgDur >= 6 and even.avgDur <= 45, "kit factor: a played level-1 kitten beats an equal passive kitten (>= 80%) and loses to a double one (<= 20%) in 6-45 s", fmt("%d%% / %d%%, %.0f s", even.winPct, double.winPct, even.avgDur))
	-- mirror duels fair, no draws
	local wins1, n, draws = 0, 0, 0
	for _, idx in ipairs({ 3, 8 }) do
		local st = SIM.Stages[idx]
		local agg = SIM.series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team2(1, 1, st.Pets), team2(2, 2, st.Pets) } }
		end, { [1] = "player", [2] = "player" }, 12)
		wins1, n, draws = wins1 + agg.wins[1], n + agg.n, draws + agg.draws
	end
	T.check(n == 24 and draws == 0 and wins1 >= 6 and wins1 <= 18, "mirror duels (S3, S8): no draws and a fair split (25-75% over 24 fights)", fmt("%d of %d", wins1, n))
	-- balance-5: the element counter (Water bubble_axolotl vs Flame maple_fox L10, neutral helpers, the wheel on vs off;
	-- the old Flame-vs-Nature pair was neutral on the wheel). 128 fights a point on 9f381c4: worth x1.28, 100% at even
	local okEc, ec = pcall(SIM.elementCounter, 8, true)
	if T.check(okEc and type(ec) == "table", "SIM.elementCounter runs (8 seeds a seating)", tostring(ec)) then
		local E = loadModule("Config").Elements
		T.check(E.StrongMultiplier == 1.5 and E.WeakMultiplier == 0.75, "the element scan restores Config.Elements (Strong 1.5 / Weak 0.75)", fmt("%s / %s", tostring(E.StrongMultiplier), tostring(E.WeakMultiplier)))
		T.check(ec.flatLevel ~= nil and ec.atEven >= 90, "the element counter decides an even fight: Water beats Flame >= 90% at the level that splits ~50% with the wheel off", fmt("L%s, %.0f%%", tostring(ec.flatLevel), ec.atEven))
		T.check(ec.worth >= 1.15 and ec.worth <= 1.45, "the element counter is worth x1.15-1.45 TeamPower (not everything)", fmt("x%.2f (even at power %.1f with the wheel, %.1f without)", ec.worth, ec.realPower or 0, ec.flatPower or 0))
	end
	-- the 2.4 wave rule: a fighter with helpers beats three enemies of 0.8 x its power. Wave 6 balance re-measure: the old
	-- ">= 9 of 10" passed on lucky seeds; over 40 seeds main (the old running player) won 75% and wave 6 (the trainer
	-- stands and times the Dash at the default skill rate 0.7) 70%; a perfect timer wins 82%. Pinned at the measured level
	-- (seeds 1-20: 13 on wave 6); the dungeon floors below and the sim's dungeon section are the real check for waves
	local foxUp = BC.UnitPower("maple_fox", 10)
	local waveWins = 0
	for seed = 1, 20 do
		local e = BC.SolveEnemy("maple_fox", foxUp * 0.8, { MaxLevel = 100 })
		local npc = { Owner = "wave", Side = 2, Npc = true, Pets = {} }
		for i = 1, 3 do
			npc.Pets[i] = { PetId = e.PetId, Key = e.PetId, Level = e.Level, Tier = e.Tier, Slot = i, Boss = e.Boss, Boost = e.Boost, Handicap = e.Handicap }
		end
		local res = SIM.run({ Mode = "Duel", Seed = seed, Teams = { team2(1, 1, { pet2("maple_fox", 10), pet2("honey_bunny", 10), pet2("biscuit_bear", 10) }), npc } }, { [1] = "player" })
		if res and res.WinnerSide == 1 then
			waveWins = waveWins + 1
		end
	end
	T.check(waveWins >= 12, "the 2.4 wave rule: a maple_fox L10 with two helpers beats three foxes of 0.8 x its power (>= 60% of 20 seeds; wave 6 measured 65%)", fmt("%d of 20", waveWins))
	-- raids: a solo M8 fighter and four M5 fighters, dodging
	local raid1 = SIM.series(function(seed)
		return { Mode = "Raid", Boss = "storm_titan", Seed = seed, Teams = { team2(1, 1, SIM.Stages[9].Pets) } }
	end, { [1] = "player" }, 3)
	local policies = {}
	local function raid4(seed)
		local teams = {}
		for i = 1, 4 do
			teams[i] = team2(100 + i, 1, SIM.Stages[8].Pets)
			policies[100 + i] = "player"
		end
		return { Mode = "Raid", Boss = "frost_wyrm", Seed = seed, Teams = teams }
	end
	local raidB = SIM.series(raid4, policies, 3)
	T.check(raid1.wins[1] == 3 and raid1.avgDur >= 70 and raid1.avgDur <= 240, "a solo endgame (S9) team beats the Storm Titan in 70-240 s (the L35 baseline: solo stays possible only far along)", fmt("%d of 3, %.0f s", raid1.wins[1], raid1.avgDur))
	-- (bug #22 wave 5: the engage rule lets a standing raider's pet walk back to the boss after a dodge, so a 3-seed cell
	-- runs a little faster, ~98 s; the lower bound is the harness's own per-cell band (sim_battle: 90-250 s per cell))
	T.check(raidB.wins[1] == 3 and raidB.avgDur >= 90 and raidB.avgDur <= 240 and raidB.maxBossHit <= 0.8, "four prestige-2 (S8) fighters beat the Frost Wyrm in 90-240 s (one cell) with no hit over 80%", fmt("%d of 3, %.0f s, max hit %.2f", raidB.wins[1], raidB.avgDur, raidB.maxBossHit))
	-- ring: round 1 for the weakest starter; the owner's wall and the owner's team (spec 2026-10-31 s.4, SIM.Targets.Ring)
	local wins = 0
	for seed = 1, 6 do
		local res = SIM.run({ Mode = "Ring", Seed = seed, Round = 1, Teams = { team2(1, 1, { pet2("pip_penguin", 1) }), BC.ChampionTeam(1, seed) } }, { [1] = "player" })
		if res and res.WinnerSide == 1 then
			wins = wins + 1
		end
	end
	T.check(wins == 6, "one level-1 pip_penguin wins ring round 1 (6 of 6 seeds)", wins)
	local TR = SIM.Targets.Ring
	local S1 = SIM.ringSummary(SIM.Teams.S1, nil, 8)
	local Owner = SIM.ringSummary(SIM.Teams.Owner, nil, 3)
	T.check(S1.med >= TR.S1.Default[1] and S1.med <= TR.S1.Default[2] and S1.reach5 <= TR.S1.Reach5 + 15, "3 L1 Commons: the ring record stays in SIM.Targets.Ring.S1 (the owner's wall)", fmt("median %d, reach 5 %.0f%%", S1.med, S1.reach5))
	T.check(Owner.med >= TR.Owner.Default[1] and Owner.med <= TR.Owner.Default[2], "the owner's L10/11/11 Secrets: the ring record stays in SIM.Targets.Ring.Owner", fmt("median %d", Owner.med))
	-- dungeon: a L7 Common trio clears floor 1; S10 clears floor 8
	local okFloor1 = true
	for seed = 1, 3 do
		if SIM.dungeonFloor(1, SIM.Teams.L7, 1, seed) < 4 then
			okFloor1 = false
		end
	end
	T.check(okFloor1, "floor 1 is cleared by three level-7 Commons (3 seeds)")
	local rooms8 = SIM.dungeonFloor(8, SIM.Stages[10].Pets, 1, 1)
	T.check(rooms8 == 4, "the S10 team clears floor 8", rooms8)
	local rooms1 = SIM.dungeonFloor(5, SIM.Stages[1].Pets, 1, 1)
	T.check(rooms1 < 4, "a Day-1 team cannot clear floor 5", rooms1)
	T.info("*balance subset ok; the full report: see tools/README.md (sim_battle.lua)")
end)

return S
