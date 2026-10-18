-- smoke_p3_battlecore.lua: Phase 3 battle core (ARCHITECTURE_V3.md "Phase 3 build contract", battlecore:
-- shared/BattleCatalog.lua + shared/BattleSim.lua + tools/sim_battle.lua), loaded by tools/smoke.py in the SERVER
-- world as pure content scenarios (no boot needed):
--   p3battle_catalog  BattleCatalog loads with the contract API (Profiles for every species, Damage, Specials for every
--                     kind, UnitPower / TeamPower / Synergy / SynergyBonus, Trials 1-30 with growing power and rewards,
--                     a mini-boss every 5 levels, TrialTeam specs, the 4 bosses with telegraphed attacks, BossOrder /
--                     NextBoss / BossHp / GroupFactor, Events, Raid tiers, Trophies), Validate() passes, junk never errors
--   p3battle_sim      BattleSim: setup validation, States / Events constants, static unit info with slot, determinism
--                     for a seed, compact rounded snapshots, commands (Attack focus, Retreat + lock, Special meter rules,
--                     Forfeit, junk), retreat behaviour (half damage, regen, running to the anchor), every special kind,
--                     elements on hits (x1.5 / x0.75), synergy in the sim, results of trials / duels / raids (timeouts,
--                     forfeits, shares), boss telegraphs that a retreating team escapes, minion waves, enrage, join /
--                     leave, performance of a full raid (8 x 4 pets + boss + waves) at 10 Hz
--   p4battle_catalog  Phase 4 BattleCatalog: Zones / TimeLimits Ring, Training, the loss-XP gate (LossShare, RealLoss,
--                     LossXp), UnitStats extras (Evo / Train / Boost: each training effect, nothing = the Phase 3 numbers
--                     bit for bit, the cached def untouched), UnitPower with Defense, TeamPower gains, ExpectedDps /
--                     BossHp / AverageMaxHp honest, Trials 1-30 unchanged, Ring data, ChampionTeam (easy rounds, spec
--                     shape, deterministic per seed in any call order, power never drops to round 120, no ceiling, bands,
--                     the giant boss every 10th round, Boost from rounds 38-50, junk), RingRewards
--   p4battle_sim      Phase 4 BattleSim: Modes + Ring (describe, unit info evo / boss / crowned / xp, timeout = loss,
--                     a single level-1 pet wins round 1), entry Boost / Evo / Train in the units, Defense in applyDamage
--                     (and after the RETREAT halving), the meter rate, the raid boss with trained teams, overtime, the
--                     duel hit cap and the double knock-out rule (no stalls, no one-shots, no draws), determinism,
--                     performance
--   p3battle_balance  tools/sim_battle.lua as a library: a short balance subset (mirror fairness, trial 1 for a day-1
--                     team, the maxed team at trial 30, a solo raid with the scripted dodger; Phase 4: ring rounds 1-3 and
--                     a Day-1 record, a trained mirror duel)
-- White-box: a few checks reach into battle.units / battle.teams (same Lua state) to set a meter or an HP value.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local abs, floor, huge, sqrt = math.abs, math.floor, math.huge, math.sqrt
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

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
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

-- a catalog pet copied with another element and / or special (identical stats otherwise)
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

----------------------------------------------------------------------------------------------------
-- p3battle_catalog
----------------------------------------------------------------------------------------------------
S.p3battle_catalog = guarded("p3battle_catalog", function()
	local BC, err = loadModule("BattleCatalog")
	if not T.check(BC ~= nil, "BattleCatalog loads", err) then
		return
	end
	local PC = loadModule("PetCatalog")
	local Config = loadModule("Config")
	T.check(loadModule("BattleCatalog") == BC, "BattleCatalog requires to the same table")
	local ok, problems = BC.Validate()
	T.check(ok, "BattleCatalog.Validate() passes", table.concat(problems or {}, " | "))

	-- profiles
	local t = T.tally("every species has a combat profile (Melee | Ranged, Range, MoveSpeed, Interval, HitRadius, DamageMult)")
	for _, species in ipairs(PC.Species) do
		local p = BC.Profiles[species]
		t:case(type(p) == "table" and (p.Attack == "Melee" or p.Attack == "Ranged") and p.Range > 0 and p.MoveSpeed > 0 and p.Interval > 0 and p.HitRadius > 0 and p.DamageMult > 0, species)
	end
	t:report()
	T.check(BC.ProfileOf("NoSuchSpecies") == BC.DefaultProfile and BC.ProfileOf(PC.Get("stormfang")) == BC.Profiles.Stormfang, "ProfileOf: def or species name, Default for unknown")
	local melee, ranged = 0, 0
	for _, p in pairs(BC.Profiles) do
		if p.Attack == "Melee" then
			melee = melee + 1
		else
			ranged = ranged + 1
		end
	end
	T.check(melee >= 5 and ranged >= 5, "both melee and ranged species exist", melee .. " melee, " .. ranged .. " ranged")

	-- damage constants
	local D = BC.Damage
	T.check(type(D) == "table" and D.HpScale > 1 and D.DamageScale > 0 and D.Variance >= 0 and D.Variance < 0.5 and D.RetreatDamageTaken < 1 and D.RetreatRegenPerSecond > 0 and D.RetreatLock > 0 and D.MeterMax == 100 and D.MeterOnHit > 0 and D.MeterPerSecond > 0, "Damage constants: HpScale, DamageScale, Variance, Retreat rules, meter rules")

	-- specials for every kind
	t = T.tally("Specials[Kind] = { Name, Text, Scale ... } for every PetCatalog.SpecialKinds entry")
	for _, kind in ipairs(PC.SpecialKinds) do
		local sp = BC.Specials[kind]
		t:case(type(sp) == "table" and type(sp.Name) == "string" and type(sp.Text) == "string" and #sp.Text > 10 and type(sp.Scale) == "number" and sp.Scale > 0, kind)
	end
	t:report()
	T.check(BC.Specials.Storm.Text:find("Retreat") ~= nil, "the Storm text tells the player to retreat out of it")

	-- unit power / stats
	local us = BC.UnitStats("mallow_kitten", 1)
	T.check(us and us.MaxHp > 0 and us.Hit > 0 and us.Interval > 0 and us.Dps > 0 and us.MoveSpeed > 0 and us.Range > 0 and us.Radius > 0 and us.Species == "Cat" and us.Elements[1] == "Celestial" and us.Ranged == false, "UnitStats of a catalog pet")
	local stats = PC.GetStats("mallow_kitten", 1)
	T.near(us.MaxHp, stats.Health * D.HpScale, 0.01, "MaxHp = Health x HpScale")
	T.near(us.Hit, stats.Power * D.DamageScale * BC.Profiles.Cat.DamageMult, 0.01, "Hit = Power x DamageScale x DamageMult")
	local p1, p10, p10g, p10r = BC.UnitPower("mallow_kitten", 1), BC.UnitPower("mallow_kitten", 10), BC.UnitPower("mallow_kitten", 10, "Golden"), BC.UnitPower("mallow_kitten@Rainbow", 10)
	T.check(p1 > 0 and p10 > p1 and p10g > p10 and p10r > p10g, "UnitPower grows with level and tier (key tiers understood)", fmt("%d %d %d %d", p1, p10, p10g, p10r))
	T.near(p10 / p1, PC.LevelFactor(10), 0.15, "UnitPower scales linearly with the level factor (sqrt(dps x hp))")
	T.check(BC.UnitPower("stormfang", 1) > BC.UnitPower("cloudy_dragon", 1) and BC.UnitPower("cloudy_dragon", 1) > BC.UnitPower("mallow_kitten", 1), "rarer pets are stronger")
	T.check(BC.UnitPower("honey_bunny", 1) < BC.UnitPower("mallow_kitten", 1) * 0.6, "economy pets are weak fighters")
	T.check(BC.UnitPower("nope") == 0 and BC.UnitPower(nil) == 0 and BC.UnitPower({}) == 0 and BC.UnitStats("nope") == nil, "unknown pets have power 0 / nil stats")
	T.check(BC.UnitPower(PC.Get("mallow_kitten"), 1) == p1 and BC.UnitPower({ PetId = "mallow_kitten", Level = 1 }) == p1, "UnitPower accepts defs and entry tables")
	local eco = BC.UnitStats("honey_bunny", 1)
	T.check(eco.SpecialFactor < 0.7 and us.SpecialFactor > 0.85, "specials are powered by the pet's Power stat (economy pets cast weaker)", fmt("%.2f vs %.2f", eco.SpecialFactor, us.SpecialFactor))

	-- synergy
	local syn = BC.SynergyBonus({ "storm_tabby", "cloudy_dragon", "puddle_frog" })
	T.check(syn.PowerMult[1] == 1.1 and syn.PowerMult[2] == 1.1 and syn.PowerMult[3] == 1 and syn.HealthMult == 1, "2 Storm pets: +10% Power for them, no Balanced (2 elements)")
	syn = BC.SynergyBonus({ "storm_tabby", "cloudy_dragon", "stormfang" })
	T.check(syn.PowerMult[1] == 1.2 and syn.PowerMult[3] == 1.2 and syn.HealthMult == 1, "3 Storm pets: +20% Power")
	syn = BC.SynergyBonus({ "storm_tabby", "cloudy_dragon", "stormfang", "sleepy_owl" })
	T.check(abs(syn.PowerMult[4] - 1.3) < 1e-9, "4 Storm pets: +30% Power")
	syn = BC.SynergyBonus({ "storm_tabby", "puddle_frog", "biscuit_bear" })
	T.check(syn.HealthMult == 1.1 and syn.PowerMult[1] == 1 and count(syn.Groups) == 3, "3 different elements: Balanced +10% Health, no Power bonus")
	local entries = BC.Synergy({ "storm_tabby", "cloudy_dragon", "puddle_frog", "biscuit_bear" })
	local ids = {}
	for _, e in ipairs(entries) do
		ids[e.Id] = e
		T.check(type(e.Name) == "string" and type(e.Text) == "string" and e.Text:find("%%") ~= nil, "synergy entry " .. tostring(e.Id) .. " has Name and Text with the bonus")
	end
	T.check(ids.Storm2 ~= nil and ids.Balanced ~= nil, "Synergy lists the Storm pair and Balanced")
	local hybrid = cloneDef(PC, "storm_tabby", { Elements = { "Storm", "Water" }, Element = "Storm" })
	syn = BC.SynergyBonus({ hybrid, "puddle_frog", "cloudy_dragon" })
	T.check(syn.PowerMult[1] == 1.1 and syn.PowerMult[2] == 1.1 and syn.PowerMult[3] == 1.1 and syn.HealthMult == 1, "a dual-element hybrid counts for both groups (Storm pair + Water pair), best bonus once")
	T.check(#BC.Synergy({}) == 0 and #BC.Synergy(nil) == 0 and BC.TeamPower(nil) == 0 and BC.TeamPower({}) == 0, "junk synergy / team power never errors")
	local tp3 = BC.TeamPower({ "storm_tabby", "cloudy_dragon", "stormfang" })
	local tpMixed = BC.TeamPower({ "storm_tabby", "frostling_penguin", "aurora_fox" })
	T.check(tp3 > BC.UnitPower("storm_tabby") + BC.UnitPower("cloudy_dragon") + BC.UnitPower("stormfang"), "TeamPower includes the synergy bonus")
	T.check(tpMixed > 0 and BC.TeamPower({ { PetId = "storm_tabby", Level = 10 }, { Key = "aurora_fox@Golden", Level = 10 } }) > 0, "TeamPower accepts entries with levels and tier keys")
	T.check(BC.TeamPower({ "storm_tabby", "storm_tabby" }) > 2 * BC.UnitPower("storm_tabby") * 1.0, "a pair's TeamPower reflects focus fire (size exponent) and the pair bonus")

	-- trials
	T.eq(#BC.Trials, 30, "30 trials")
	T.eq(BC.TrialCount, 30, "TrialCount")
	t = T.tally("Trials[level]: Level, Name, RecommendedPower, MiniBoss, Team, Rewards { Tokens, Xp, FirstClear { Tokens, Gems } }")
	local lastPower, lastTokens = 0, 0
	for lv = 1, 30 do
		local tr = BC.Trials[lv]
		local okRow = tr.Level == lv and type(tr.Name) == "string" and tr.RecommendedPower >= lastPower and type(tr.Team) == "table" and #tr.Team >= (lv == 1 and 1 or 3) and #tr.Team <= 4
			and type(tr.Rewards) == "table" and tr.Rewards.Tokens > lastTokens and tr.Rewards.Xp > 0 and type(tr.Rewards.FirstClear) == "table" and tr.Rewards.FirstClear.Tokens > 0
			and (tr.MiniBoss == (lv % 5 == 0)) and ((tr.Rewards.FirstClear.Gems > 0) == (lv % 5 == 0)) and tr.TimeLimit > 0
		for _, e in ipairs(tr.Team) do
			if not PC.Get(e.PetId) or e.Level < 1 or (e.Boss and not tr.MiniBoss) then
				okRow = false
			end
		end
		t:case(okRow, "trial " .. lv)
		lastPower, lastTokens = tr.RecommendedPower, tr.Rewards.Tokens
	end
	t:report()
	T.check(BC.Trials[1].RecommendedPower < BC.TeamPower({ "mallow_kitten", "puddle_frog", "pebble_pup" }), "trial 1 is below a brand-new team of three level-1 Commons")
	T.check(BC.Trials[30].RecommendedPower >= 2000 and BC.Trials[30].RecommendedPower <= 3200, "trial 30 needs a prestiged Mythic team (power 2000-3200)", BC.Trials[30].RecommendedPower)
	T.check(BC.Trials[30].Boss == "stormfang" and BC.Trials[30].Name:find("Stormfang") ~= nil, "trial 30 is Stormfang's challenge")
	local spec = BC.TrialTeam(7)
	T.check(spec and spec.Owner == "npc" and spec.Side == 2 and spec.Npc == true and #spec.Pets == #BC.Trials[7].Team and spec.Pets[1].Slot == 1 and spec.Trial == 7, "TrialTeam(level) is a BattleSim team spec for the NPC side")
	T.check(BC.TrialTeam(0) == nil and BC.TrialTeam(31) == nil and BC.TrialTeam("x") == nil, "TrialTeam of unknown levels is nil")
	local r = BC.TrialRewards(10, true)
	T.check(r.Tokens == BC.Trials[10].Rewards.Tokens * 2 and r.FirstClear.Tokens == BC.Trials[10].Rewards.FirstClear.Tokens * 2 and r.FirstClear.Gems == BC.Trials[10].Rewards.FirstClear.Gems, "TrialRewards(level, double) doubles Tokens, never Gems")
	T.check(BC.ChapterOf(1).Name == "Cloud Meadow" and BC.ChapterOf(30).Name == "Eclipse" and BC.ChapterOf(31) == nil, "chapters")

	-- bosses
	T.eq(#BC.BossOrder, 4, "4 bosses in the roster")
	t = T.tally("Bosses[id]: Name, Element, HpPerPlayer, Radius, Basic, telegraphed Attacks, Minions, EnrageAt < TimeLimit")
	local validElements = {}
	for _, e in ipairs(Config.Elements.Order) do
		validElements[e] = true
	end
	for _, id in ipairs(BC.BossOrder) do
		local b = BC.Bosses[id]
		local okRow = b and b.Id == id and type(b.Name) == "string" and validElements[b.Element] and b.HpPerPlayer > 0 and b.Radius > 0 and type(b.Basic) == "table" and #b.Attacks >= 2 and b.EnrageAt < b.TimeLimit and PC.Get(b.MinionPet) ~= nil and #b.Minions.Waves >= 2
		for _, a in ipairs(b and b.Attacks or {}) do
			if not ((a.Shape == "Circle" and a.Radius) or (a.Shape == "Line" and a.Width and a.Length)) or a.Telegraph < 1 or a.Damage > 0.6 or a.Cooldown < a.Telegraph then
				okRow = false
			end
		end
		t:case(okRow, id)
	end
	t:report()
	local names = {}
	for _, id in ipairs(BC.BossOrder) do
		names[BC.Bosses[id].Name] = true
	end
	T.check(names["Storm Titan"] and names["Lava Golem"] and names["Frost Wyrm"] and names["Shadow Hydra"], "the roster is Storm Titan, Lava Golem, Frost Wyrm, Shadow Hydra")
	T.check(BC.NextBoss(1) == BC.BossOrder[1] and BC.NextBoss(4) == BC.BossOrder[4] and BC.NextBoss(5) == BC.BossOrder[1] and BC.NextBoss(0) == BC.BossOrder[4] and BC.NextBoss("junk") == BC.BossOrder[1], "NextBoss rotates and wraps")
	local one = { Pets = { pet("storm_tabby", 10), pet("frostling_penguin", 10), pet("aurora_fox", 10) } }
	local hp1 = BC.BossHp("storm_titan", { one })
	local hp3 = BC.BossHp("storm_titan", { one, one, one })
	local hp8 = BC.BossHp("storm_titan", { one, one, one, one, one, one, one, one })
	T.check(hp1 >= BC.BossRules.MinHp and hp3 > hp1 * 2.5 and hp8 > hp3 * 2 and hp8 < hp1 * 8 * 2, "BossHp grows with the participants (x GroupFactor), at least MinHp", fmt("%d %d %d", hp1, hp3, hp8))
	T.near(hp1, BC.ExpectedDps(one) * BC.Bosses.storm_titan.HpPerPlayer, 1, "one team: boss HP = HpPerPlayer seconds of its expected DPS")
	T.check(BC.GroupFactor(1) == 1 and BC.GroupFactor(8) > BC.GroupFactor(3) and BC.GroupFactor(3) > 1, "GroupFactor")
	T.check(BC.BossHp("unknown", {}) >= BC.BossRules.MinHp, "BossHp of an unknown boss / no teams is the floor")

	-- events, raid tiers, trophies
	T.check(type(BC.Events.Schedule) == "table" and BC.Events.Schedule[1].Kind == "BossRaid" and BC.Events.Schedule[1].EveryMinutes == 20 and BC.Events.Schedule[1].AnnounceSeconds == 120 and BC.Events.Schedule[2].Kind == "DoubleRewards" and BC.Events.DoubleRewardsMultiplier == 2, "event schedule: a Boss Raid every 20 min announced 2 min ahead, a Double Rewards hour")
	local tiers = BC.Raid.Tiers
	T.check(#tiers >= 3 and tiers[1].MinShare > tiers[#tiers].MinShare and tiers[#tiers].MinShare >= BC.Raid.MinShare and BC.Raid.MinShare >= 0 and tiers[1].Tokens > tiers[#tiers].Tokens,
		"raid reward tiers sorted by damage share; the lowest tier needs no more than Raid.MinShare")
	T.check(BC.RaidTier(0.5).Id == tiers[1].Id and BC.RaidTier(0.001).Id == tiers[#tiers].Id and BC.RaidTier(0.001, false).Id == "Loss" and BC.RaidTier(0.3, false).Id == "Loss"
		and BC.RaidTier(0) == nil and BC.RaidTier(0, false) == nil and BC.RaidTier("junk") == nil,
		"RaidTier picks by share, any hit earns at least the lowest tier (Loss when the raid failed), nil (no reward) for no damage")
	T.check(BC.Trophies.Win > 0 and BC.Trophies.Loss < 0 and BC.Trophies.Floor == 0 and BC.Trophies.Forfeit <= BC.Trophies.Loss and BC.Trophies.Tokens.Win > BC.Trophies.Tokens.Loss, "PvP trophies: win +, loss -, floor 0, forfeit counts as a loss")
	T.check(type(BC.EventPets()) == "table", "EventPets() lists EventOnly catalog pets")
	T.check(BC.Zones.Trial.X > 0 and BC.Zones.Duel.X > 0 and BC.Zones.Raid.X > BC.Zones.Duel.X and BC.TimeLimits.Raid > BC.TimeLimits.Duel, "default zone sizes and time limits per mode")
end)

----------------------------------------------------------------------------------------------------
-- p3battle_sim
----------------------------------------------------------------------------------------------------
S.p3battle_sim = guarded("p3battle_sim", function()
	local BS, err = loadModule("BattleSim")
	if not T.check(BS ~= nil, "BattleSim loads", err) then
		return
	end
	local BC = loadModule("BattleCatalog")
	local PC = loadModule("PetCatalog")
	local D = BC.Damage

	-- constants
	T.check(BS.States.Idle == 0 and BS.States.Moving == 1 and BS.States.Attacking == 2 and BS.States.Retreating == 3 and BS.States.Casting == 4 and BS.States.Down == 5 and BS.States.Stunned == 6, "BattleSim.States codes")
	T.check(BS.StateNames[5] == "Down" and BS.StateNames[3] == "Retreating", "BattleSim.StateNames")
	for _, k in ipairs({ "Hit", "Special", "KO", "Telegraph", "Spawn", "Enrage", "Order", "Zone", "Leave", "End" }) do
		T.check(BS.Events[k] == k, "BattleSim.Events." .. k)
	end

	-- setup validation
	local commons = { pet("mallow_kitten", 1), pet("puddle_frog", 1), pet("biscuit_bear", 1) }
	local b, reason = BS.new(nil)
	T.check(b == nil and reason == "BadSetup", "new(nil) -> nil, BadSetup")
	b, reason = BS.new({ Mode = "Duel", Teams = {} })
	T.check(b == nil and reason == "NoTeam", "new without teams -> NoTeam")
	b, reason = BS.new({ Mode = "Duel", Teams = { team(1, 1, commons) } })
	T.check(b == nil and reason == "NoOpponent", "a duel needs an opponent")
	b, reason = BS.new({ Mode = "Trial", Trial = 99, Teams = { team(1, 1, commons) } })
	T.check(b == nil and reason == "UnknownTrial", "unknown trial level refused")
	b, reason = BS.new({ Mode = "Raid", Boss = "nope", Teams = { team(1, 1, commons) } })
	T.check(b == nil and reason == "UnknownBoss", "unknown boss refused")
	b, reason = BS.new({ Mode = "Duel", Teams = { team(1, 1, commons), team(1, 2, commons) } })
	T.check(b == nil and reason == "DuplicateOwner", "duplicate owners refused")
	b, reason = BS.new({ Mode = "Duel", Teams = { team(1, 1, { pet("nope", 1), { Key = 5 } }), team(2, 2, commons) } })
	T.check(b == nil and reason == "NoTeam", "a team of unknown pets is dropped -> NoTeam")

	-- a trial: static info with slots, Describe
	b = BS.new({ Mode = "Trial", Trial = 5, Seed = 3, Id = "b1", Teams = { team(1001, 1, { pet("mallow_kitten", 4), pet("puddle_frog", 3), pet("biscuit_bear", 3) }) } })
	T.check(b ~= nil, "a trial battle starts")
	local desc = b:Describe()
	T.check(desc.BattleId == "b1" and desc.Mode == "Trial" and desc.Level == 5 and desc.Seed == 3 and desc.Zone.X == BC.Zones.Trial.X and desc.TimeLimit == BC.Trials[5].TimeLimit and #desc.Sides[1] == 1 and desc.Sides[1][1] == 1001 and #desc.Sides[2] == 1, "Describe: id, mode, level, seed, zone, time limit, sides")
	local units = b:StaticUnits()
	T.eq(#units, 6, "6 static units (3 + 3)")
	local t = T.tally("static unit info: id, side, owner, slot, kind, key, petId, name, species, look, element(s), maxHp, level, tier, scale, range, radius, special")
	local miniBoss = 0
	for _, u in ipairs(units) do
		t:case(type(u.id) == "number" and (u.side == 1 or u.side == 2) and u.owner ~= nil and type(u.slot) == "number" and u.slot >= 1 and u.slot <= 4 and (u.kind == "Pet" or u.kind == "MiniBoss")
			and type(u.key) == "string" and PC.Get(u.petId) ~= nil and type(u.name) == "string" and type(u.species) == "string" and type(u.look) == "table" and type(u.element) == "string" and type(u.elements) == "table"
			and u.maxHp == floor(u.maxHp) and u.maxHp > 0 and u.level >= 1 and type(u.tier) == "string" and u.scale > 0 and u.range > 0 and u.radius > 0 and type(u.special) == "table" and type(u.special.Kind) == "string", "unit " .. tostring(u.id))
		if u.kind == "MiniBoss" then
			miniBoss = miniBoss + 1
			T.check(u.scale > 1 and u.maxHp > BC.UnitStats(u.petId, u.level).MaxHp * 2, "the mini-boss is bigger and tankier")
		end
	end
	t:report()
	T.eq(miniBoss, 1, "trial 5 fields one mini-boss")
	T.check(units[1].slot == 1 and units[2].slot == 2 and units[3].slot == 3 and units[1].owner == 1001 and units[4].owner == "npc", "slots 1-3 map the owner's pets; NPC pets belong to 'npc'")
	T.check(b:Result() == nil and not b:IsFinished() and b:Time() == 0 and #b:Owners() == 1 and b:Owners()[1] == 1001, "fresh battle: no result, time 0, owners")

	-- snapshot shape
	local snap = b:Snapshot()
	T.check(snap.BattleId == "b1" and snap.T == 0 and count(snap.Units) == 6, "Snapshot: BattleId, T, one entry per unit")
	t = T.tally("snapshot entries are compact: x / z to 0.1, hp / meter integers, state code, optional target / shield only")
	for id, u in pairs(snap.Units) do
		local okRow = type(id) == "number" and u.x == floor(u.x * 10 + 0.5) / 10 and u.z == floor(u.z * 10 + 0.5) / 10 and u.hp == floor(u.hp) and u.hp >= 1 and u.meter == floor(u.meter) and u.meter >= 0 and u.meter <= 100 and BS.StateNames[u.state] ~= nil
		for k in pairs(u) do
			if k ~= "x" and k ~= "z" and k ~= "hp" and k ~= "state" and k ~= "meter" and k ~= "target" and k ~= "shield" then
				okRow = false
			end
		end
		t:case(okRow, "unit " .. tostring(id))
	end
	t:report()
	for id, u in pairs(snap.Units) do
		T.check(abs(u.x) <= BC.Zones.Trial.X / 2 and abs(u.z) <= BC.Zones.Trial.Z / 2, "unit " .. id .. " starts inside the floor")
	end

	-- the fight runs and ends with a result
	local events, steps = run(b, 1500)
	local res = b:Result()
	T.check(res ~= nil and b:IsFinished(), "the trial finishes within the time limit", steps)
	T.check(countType(events, "Hit") > 20 and countType(events, "KO") >= 3 and countType(events, "End") == 1, "events: hits, KOs and one End", fmt("%d hits %d KOs", countType(events, "Hit"), countType(events, "KO")))
	T.check(res.Mode == "Trial" and res.Level == 5 and (res.WinnerSide == 1 or res.WinnerSide == 2) and type(res.Winners) == "table" and type(res.Losers) == "table" and type(res.Damage) == "table" and res.Damage[1001] ~= nil and res.Duration > 0 and type(res.Reason) == "string", "result shape: Mode, Level, WinnerSide, Winners, Losers, Damage, Duration, Reason")
	T.check(#b:Step(0.1) == 0 and b:Result() == res, "stepping a finished battle returns no events and the same result")
	local okCmd, why = b:Command(1001, "Attack")
	T.check(okCmd == false and why == "Finished", "commands after the end are refused: Finished")
	local hitOk = true
	for _, ev in ipairs(events) do
		if ev.type == "Hit" and (type(ev.dmg) ~= "number" or ev.dmg ~= floor(ev.dmg) or ev.dmg < 0 or type(ev.to) ~= "number") then
			hitOk = false
		end
	end
	T.check(hitOk, "Hit events carry integer dmg and a target id")

	-- determinism
	local function setupDuel(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, { pet("storm_tabby", 10), pet("frostling_penguin", 10), pet("aurora_fox", 8) }, { Auto = true }), team(2, 2, { pet("maple_fox", 12), pet("bamboo_panda", 12), pet("moonlit_owl", 8) }, { Auto = true }) } }
	end
	local b1, b2 = BS.new(setupDuel(77)), BS.new(setupDuel(77))
	local same, differentSeed = true, false
	local b3 = BS.new(setupDuel(78))
	for _ = 1, 400 do
		local e1, e2 = b1:Step(0.1), b2:Step(0.1)
		b3:Step(0.1)
		local s1, s2, s3 = b1:Snapshot(), b2:Snapshot(), b3:Snapshot()
		if #e1 ~= #e2 then
			same = false
		end
		for i, ev in ipairs(e1) do
			local ev2 = e2[i]
			if not ev2 or ev.type ~= ev2.type or ev.dmg ~= ev2.dmg or ev.to ~= ev2.to or ev.from ~= ev2.from then
				same = false
			end
		end
		for id, u in pairs(s1.Units) do
			local v = s2.Units[id]
			if not v or v.x ~= u.x or v.z ~= u.z or v.hp ~= u.hp or v.state ~= u.state or v.meter ~= u.meter or v.target ~= u.target or v.shield ~= u.shield then
				same = false
			end
			local w = s3.Units[id]
			if w and (w.hp ~= u.hp or w.x ~= u.x) then
				differentSeed = true
			end
		end
	end
	T.check(same, "the same seed replays the same snapshots and events step for step")
	T.check(differentSeed, "another seed gives a different battle")
	T.check(b1:Result() ~= nil and b2:Result() ~= nil and b1:Result().WinnerSide == b2:Result().WinnerSide and b1:Result().Duration == b2:Result().Duration, "the same seed ends the same way")

	-- commands: Attack focus / Retreat lock / Special rules / Forfeit / junk
	b = BS.new({ Mode = "Duel", Seed = 5, Teams = { team(1, 1, { pet("storm_tabby", 10), pet("frostling_penguin", 10), pet("biscuit_bear", 10) }), team(2, 2, { pet("maple_fox", 10), pet("bamboo_panda", 10), pet("moonlit_owl", 10) }, { Auto = true }) } })
	T.check(b:Command(1, "Attack", 4) == true, "Attack with an enemy focus is accepted")
	T.check(b:TeamOf(1).Focus == 4 and b:TeamOf(1).Order == "Attack", "TeamOf reports the focus and order")
	okCmd, why = b:Command(1, "Attack", 2)
	T.check(okCmd == false and why == "BadTarget", "focusing your own pet is refused")
	okCmd, why = b:Command(1, "Attack", "junk")
	T.check(okCmd == false and why == "BadTarget", "focusing junk is refused")
	okCmd, why = b:Command(1, "Attack", 99)
	T.check(okCmd == false and why == "BadTarget", "focusing a missing unit is refused")
	T.check(b:Command(1, "Attack", nil) == true and b:TeamOf(1).Focus == nil, "Attack without a target clears the focus")
	okCmd, why = b:Command(2, "Attack")
	T.check(okCmd == true, "NPC-less owners (team 2) may be commanded too")
	okCmd, why = b:Command(999, "Attack")
	T.check(okCmd == false and why == "NoTeam", "unknown owners get NoTeam")
	okCmd, why = b:Command(1, "Dance")
	T.check(okCmd == false and why == "UnknownAction", "unknown actions are refused")
	okCmd, why = b:Command(1, "Special", 1)
	T.check(okCmd == false and why == "Charging", "Special with an empty meter: Charging")
	okCmd, why = b:Command(1, "Special", 9)
	T.check(okCmd == false and why == "BadSlot", "Special on a missing slot: BadSlot")
	okCmd, why = b:Command(1, "Special", "x")
	T.check(okCmd == false and why == "BadSlot", "Special with junk: BadSlot")
	-- retreat
	run(b, 15)
	T.check(b:Command(1, "Retreat") == true, "Retreat accepted")
	okCmd, why = b:Command(1, "Retreat")
	T.check(okCmd == false and why == "AlreadyRetreating", "a second Retreat: AlreadyRetreating")
	local okAtk, whyAtk, remaining = b:Command(1, "Attack")
	T.check(okAtk == false and whyAtk == "Regrouping" and type(remaining) == "number" and remaining > 0 and remaining <= D.RetreatLock, "Attack right after Retreat is locked: Regrouping + seconds left")
	okCmd, why = b:Command(1, "Special", 1)
	T.check(okCmd == false and (why == "Charging" or why == "Retreating"), "no specials while retreating / charging")
	local before = b:Snapshot()
	local anchor = b:TeamOf(1).Anchor
	local distBefore = 0
	for _, id in ipairs({ 1, 2, 3 }) do
		local u = before.Units[id]
		distBefore = distBefore + sqrt((u.x - anchor.x) ^ 2 + (u.z - anchor.z) ^ 2)
	end
	local retreatEvents = run(b, 10)
	local after = b:Snapshot()
	local distAfter, retreating = 0, true
	for _, id in ipairs({ 1, 2, 3 }) do
		local u = after.Units[id]
		distAfter = distAfter + sqrt((u.x - anchor.x) ^ 2 + (u.z - anchor.z) ^ 2)
		if u.hp > 0 and u.state ~= BS.States.Retreating then
			retreating = false
		end
	end
	T.check(retreating, "retreating pets are in the Retreating state")
	T.check(distAfter < distBefore, "retreating pets run toward their owner's anchor", fmt("%.1f -> %.1f", distBefore, distAfter))
	local halfOk, retreatHits = true, 0
	for _, ev in ipairs(retreatEvents) do
		if ev.type == "Hit" and ev.to <= 3 then
			retreatHits = retreatHits + 1
			if not ev.retreat then
				halfOk = false
			end
		end
	end
	T.check(halfOk, "hits on a retreating team are flagged retreat (half damage)", retreatHits .. " hits")
	run(b, 10)
	T.check(b:Command(1, "Attack") == true, "Attack accepted once the retreat lock is over")
	-- forfeit
	T.check(b:Command(1, "Forfeit") == true, "Forfeit accepted")
	local forfeitEvents = b:Step(0.1)
	local koForfeit = 0
	for _, ev in ipairs(forfeitEvents) do
		if ev.type == "KO" and ev.forfeit then
			koForfeit = koForfeit + 1
		end
	end
	res = b:Result()
	T.check(res ~= nil and res.Forfeit == true and res.WinnerSide == 2 and res.Winners[1] == 2 and res.Losers[1] == 1 and res.Reason == "Forfeit", "a forfeit ends the duel for the other side (Forfeit flag, Winners / Losers)")
	T.check(koForfeit >= 1, "forfeited pets are knocked out with forfeit = true")

	-- retreat regen (white-box: a wounded pet far from the enemy heals while retreating)
	b = BS.new({ Mode = "Duel", Seed = 8, Zone = 80, Teams = { team(1, 1, { pet("biscuit_bear", 10), pet("bamboo_panda", 10), pet("mochi_slime", 10) }), team(2, 2, { pet("biscuit_bear", 10), pet("bamboo_panda", 10), pet("mochi_slime", 10) }, { Auto = true }) } })
	local wounded = b.units[1]
	wounded.hp = wounded.maxHp * 0.4
	b:Command(1, "Retreat")
	run(b, 10)
	T.check(wounded.hp > wounded.maxHp * 0.4 and wounded.hp <= wounded.maxHp * 0.4 + wounded.maxHp * D.RetreatRegenPerSecond * 1.0 + 1e-6, "a retreating pet regains ~2% of its max HP per second", fmt("%.0f -> %.0f of %.0f", wounded.maxHp * 0.4, wounded.hp, wounded.maxHp))

	-- the Special command and every kind (white-box meters)
	local function castTest(kind, casterPet, enemies, prepare)
		local caster = cloneDef(PC, casterPet, { Special = { Id = "test_" .. kind, Name = "Test " .. kind, Kind = kind, Power = 40, Color = PC.Get(casterPet).Special.Color } })
		local bt = BS.new({ Mode = "Duel", Seed = 11, Teams = { team(1, 1, { { Key = casterPet, Def = caster, Level = 10 }, pet("bubble_axolotl", 10), pet("waffle_corgi", 10) }), team(2, 2, enemies, { Auto = true, Specials = false }) } })
		run(bt, 12)
		local u = bt.units[1]
		u.meter = 100
		u.castUntil = 0
		u.stunUntil = 0
		if prepare then
			prepare(bt)
		end
		local okCast, kindBack = bt:Command(1, "Special", 1)
		local evs = bt:Step(0.1)
		return bt, okCast, kindBack, evs
	end
	local enemies3 = { pet("maple_fox", 10), pet("bamboo_panda", 10), pet("mallow_kitten", 10) }
	local bt, okCast, kindBack, evs = castTest("Blast", "puddle_frog", enemies3)
	local special = nil
	for _, ev in ipairs(evs) do
		if ev.type == "Special" then
			special = ev
		end
	end
	T.check(okCast == true and kindBack == "Blast" and special and special.kind == "Blast" and special.unit == 1 and type(special.targets) == "table" and #special.targets >= 2, "Blast: cast accepted, Special event with several targets", special and #special.targets)
	local blastHits = 0
	for _, ev in ipairs(evs) do
		if ev.type == "Hit" and ev.special == "Blast" then
			blastHits = blastHits + 1
		end
	end
	T.check(blastHits >= 2 and bt.units[1].meter < 5 and bt.units[1].state == BS.States.Casting, "Blast hits several enemies; the meter resets and the caster is Casting", fmt("%d hits, meter %.1f, state %s", blastHits, bt.units[1].meter, tostring(BS.StateNames[bt.units[1].state])))
	okCmd, why = bt:Command(1, "Special", 1)
	T.check(okCmd == false and why == "Charging", "no second cast until the meter refills")

	bt, okCast, kindBack, evs = castTest("Heal", "honey_bunny", enemies3, function(x)
		x.units[2].hp = x.units[2].maxHp * 0.3
	end)
	special = nil
	for _, ev in ipairs(evs) do
		if ev.type == "Special" then
			special = ev
		end
	end
	T.check(okCast == true and special and special.kind == "Heal" and type(special.heals) == "table" and #special.heals >= 1 and bt.units[2].hp > bt.units[2].maxHp * 0.3, "Heal: heals the wounded ally (heals list in the event)")

	bt, okCast, kindBack, evs = castTest("Shield", "biscuit_bear", enemies3)
	special = nil
	for _, ev in ipairs(evs) do
		if ev.type == "Special" then
			special = ev
		end
	end
	snap = bt:Snapshot()
	T.check(okCast == true and special and special.kind == "Shield" and #special.shields == 3 and snap.Units[1].shield > 0 and snap.Units[2].shield > 0, "Shield: every ally gets a shield (snapshot shield field)")
	local absorbed = 0
	for _, ev in ipairs(run(bt, 30)) do
		if ev.type == "Hit" and ev.absorbed then
			absorbed = absorbed + 1
		end
	end
	T.check(absorbed > 0, "shields absorb damage (Hit.absorbed)")

	bt, okCast, kindBack, evs = castTest("Storm", "storm_tabby", enemies3)
	T.check(okCast == true and countType(evs, "Zone") == 1 and evs[1] and (evs[1].type == "Special" or evs[1].type == "Zone"), "Storm: a Zone event")
	local zoneHits = 0
	for _, ev in ipairs(run(bt, 45)) do
		if ev.type == "Hit" and ev.zone then
			zoneHits = zoneHits + 1
		end
	end
	T.check(zoneHits >= 2, "the storm zone keeps hurting enemies inside it for a few seconds", zoneHits)

	bt, okCast, kindBack, evs = castTest("Pounce", "mallow_kitten", { pet("sleepy_owl", 10), pet("pip_penguin", 10), pet("candy_unicorn", 10) })
	special = nil
	for _, ev in ipairs(evs) do
		if ev.type == "Special" then
			special = ev
		end
	end
	local pounceHit = nil
	for _, ev in ipairs(evs) do
		if ev.type == "Hit" and ev.special == "Pounce" then
			pounceHit = ev
		end
	end
	T.check(okCast == true and special and special.target and pounceHit and pounceHit.to == special.target, "Pounce: one heavy strike on the target")
	if special and special.target then
		local caster, target = bt.units[1], bt.units[special.target]
		local d = sqrt((caster.x - target.x) ^ 2 + (caster.z - target.z) ^ 2)
		T.check(d <= caster.radius + target.radius + 1.5, "the pouncing pet dashes next to its target", fmt("%.1f studs", d))
		T.check(pounceHit.dmg > bt.units[1].hit * 1.5, "a Pounce hits much harder than a plain attack")
	end

	bt, okCast, kindBack, evs = castTest("Freeze", "frostling_penguin", enemies3)
	special = nil
	for _, ev in ipairs(evs) do
		if ev.type == "Special" then
			special = ev
		end
	end
	T.check(okCast == true and special and type(special.stunned) == "table" and #special.stunned >= 1, "Freeze: stuns enemies around the target")
	if special and #special.stunned >= 1 then
		local sid = special.stunned[1]
		snap = bt:Snapshot()
		T.check(snap.Units[sid].state == BS.States.Stunned, "a frozen pet is in the Stunned state")
		local stunnedHit = false
		for _, ev in ipairs(run(bt, 5)) do
			if ev.type == "Hit" and ev.from == sid then
				stunnedHit = true
			end
		end
		T.check(not stunnedHit, "a frozen pet does not attack while stunned")
	end

	bt, okCast, kindBack, evs = castTest("Beam", "aurora_fox", enemies3, function(x)
		-- line the enemies up behind the first one, in the beam's path
		local caster = x.units[1]
		local first = x.units[4]
		local dx, dz = first.x - caster.x, first.z - caster.z
		local d = sqrt(dx * dx + dz * dz)
		dx, dz = dx / d, dz / d
		x.units[5].x, x.units[5].z = first.x + dx * 4, first.z + dz * 4
		x.units[6].x, x.units[6].z = first.x + dx * 8, first.z + dz * 8
		caster.target = first
		x.teams[1].focus = first
	end)
	special = nil
	for _, ev in ipairs(evs) do
		if ev.type == "Special" then
			special = ev
		end
	end
	T.check(okCast == true and special and special.kind == "Beam" and type(special.angle) == "number" and #special.targets >= 2, "Beam: hits every enemy lined up behind the target", special and #special.targets)

	-- elements on hits
	local water = cloneDef(PC, "storm_tabby", { Element = "Water" })
	local flame = cloneDef(PC, "storm_tabby", { Element = "Flame" })
	bt = BS.new({ Mode = "Duel", Seed = 13, Specials = false, Teams = { team(1, 1, { { Key = "storm_tabby", Def = water, Level = 10 }, { Key = "storm_tabby", Def = water, Level = 10 } }, { Auto = true }), team(2, 2, { { Key = "storm_tabby", Def = flame, Level = 10 }, { Key = "storm_tabby", Def = flame, Level = 10 } }, { Auto = true }) } })
	local strong, weak, strongSum, weakSum, strongN, weakN = true, true, 0, 0, 0, 0
	for _, ev in ipairs(run(bt, 150)) do
		if ev.type == "Hit" then
			if ev.from <= 2 then
				if ev.elem ~= 1.5 then
					strong = false
				end
				if not ev.crit then
					strongSum, strongN = strongSum + ev.dmg, strongN + 1
				end
			else
				if ev.elem ~= 0.75 then
					weak = false
				end
				if not ev.crit then
					weakSum, weakN = weakSum + ev.dmg, weakN + 1
				end
			end
		end
	end
	T.check(strong and weak and strongN > 5 and weakN > 5, "Hit events carry elem 1.5 for the counter and 0.75 for the countered")
	if strongN > 5 and weakN > 5 then
		T.near((strongSum / strongN) / (weakSum / weakN), 2, 0.4, "Water hits Flame for about twice what Flame hits Water")
	end
	T.check(bt:Result() == nil or bt:Result().WinnerSide == 1, "the counter team wins the mirror")
	local neutral = BS.new({ Mode = "Duel", Seed = 13, Specials = false, Teams = { team(1, 1, { pet("storm_tabby", 10) }, { Auto = true }), team(2, 2, { pet("bamboo_panda", 10) }, { Auto = true }) } })
	local anyElem = false
	for _, ev in ipairs(run(neutral, 60)) do
		if ev.type == "Hit" and ev.elem then
			anyElem = true
		end
	end
	T.check(not anyElem, "neutral matchups carry no elem field")

	-- synergy in the sim
	bt = BS.new({ Mode = "Duel", Seed = 2, Teams = { team(1, 1, { pet("storm_tabby", 10), pet("cloudy_dragon", 10), pet("stormfang", 10) }), team(2, 2, { pet("storm_tabby", 10), pet("puddle_frog", 10), pet("biscuit_bear", 10) }) } })
	T.check(bt.units[1].powerMult == 1.2 and bt.units[3].powerMult == 1.2 and bt.teams[1].healthMult == 1, "3 Storm pets fight with +20% Power")
	T.check(bt.units[4].powerMult == 1 and bt.teams[2].healthMult == 1.1, "a Balanced team has +10% Health")
	T.near(bt.units[4].maxHp, BC.UnitStats("storm_tabby", 10).MaxHp * 1.1, 0.5, "Balanced max HP in the static info")

	-- duel timeout decides by HP, draw when equal
	bt = BS.new({ Mode = "Duel", Seed = 2, TimeLimit = 3, Teams = { team(1, 1, { pet("biscuit_bear", 10) }, { Auto = true }), team(2, 2, { pet("biscuit_bear", 10) }, { Auto = true }) } })
	run(bt, 100)
	res = bt:Result()
	T.check(res and res.Reason == "Timeout" and res.Duration <= 3.2 and (res.WinnerSide == 1 or res.WinnerSide == 2 or res.Draw), "a duel at the time limit is decided by the HP left (or drawn)")
	bt = BS.new({ Mode = "Trial", Trial = 1, Seed = 2, TimeLimit = 2, Teams = { team(1, 1, { pet("mallow_kitten", 1) }) } })
	bt:Command(1, "Retreat")
	run(bt, 100)
	res = bt:Result()
	T.check(res and res.Reason == "Timeout" and res.WinnerSide == 2 and #res.Winners == 0 and res.Losers[1] == 1, "a trial at the time limit is lost")

	-- raid: telegraphs, dodging, waves, join / leave, shares
	local mid = { pet("aurora_fox", 12), pet("storm_tabby", 14), pet("bamboo_panda", 14) }
	bt = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 21, Teams = { team(1, 1, mid), team(2, 1, mid, { Auto = true }) } })
	T.check(bt ~= nil and bt:Describe().BossId == "storm_titan" and bt:Describe().Zone.X == BC.Zones.Raid.X, "a raid starts with the boss on side 2")
	local bossInfo = nil
	for _, u in ipairs(bt:StaticUnits()) do
		if u.kind == "Boss" then
			bossInfo = u
		end
	end
	T.check(bossInfo and bossInfo.boss == "storm_titan" and bossInfo.side == 2 and bossInfo.element == "Storm" and bossInfo.maxHp >= BC.BossRules.MinHp and bossInfo.radius >= 5 and bossInfo.name == "Storm Titan", "boss static info: kind Boss, boss id, element, radius")
	local status = bt:BossStatus()
	T.check(status and status.BossId == "storm_titan" and status.Hp == status.MaxHp and status.Players == 2 and status.EndsIn == BC.Bosses.storm_titan.TimeLimit, "BossStatus: HP, players, EndsIn")
	-- telegraph: the same seeded raid twice; in one the team RETREATs on the first telegraph, in the other it stands
	local function firstTelegraphRun(dodge)
		local raid = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 21, Teams = { team(1, 1, mid) } })
		local first, hitsOnUs, early, landedAt = nil, 0, false, nil
		run(raid, 400, function(stepEvents)
			for _, ev in ipairs(stepEvents) do
				if ev.type == "Telegraph" and not first then
					first = ev
					first.seen = raid:Time()
					if dodge then
						first.retreated = raid:Command(1, "Retreat")
					end
				end
				if ev.type == "Hit" and first and ev.tele == first.id then
					hitsOnUs = hitsOnUs + 1
					landedAt = landedAt or raid:Time()
					if raid:Time() < first.at - 0.15 then
						early = true
					end
				end
			end
			if first and raid:Time() > first.at + 1 then
				return
			end
		end)
		return first, hitsOnUs, early, landedAt
	end
	local firstTele, standHits, early1, landedAt = firstTelegraphRun(false)
	T.check(firstTele ~= nil and (firstTele.shape == "Circle" or firstTele.shape == "Line") and type(firstTele.boss) == "number" and type(firstTele.name) == "string" and firstTele.at > firstTele.seen and abs((firstTele.at - firstTele.seen) - firstTele.hits) < 0.15, "Telegraph events: shape, boss, name, hit time ahead of the warning")
	T.check(firstTele and firstTele.hits >= 1, "telegraphs give at least a second of warning", firstTele and firstTele.hits)
	T.check(standHits >= 1 and not early1 and landedAt and abs(landedAt - firstTele.at) < 0.15, "a team that stands still is hit exactly when the telegraph lands", fmt("%d hits at %s (announced %s)", standHits, tostring(landedAt), tostring(firstTele and firstTele.at)))
	local firstTele2, dodgeHits = firstTelegraphRun(true)
	T.check(firstTele2 and firstTele2.retreated and firstTele2.id == firstTele.id and dodgeHits == 0, "the same team RETREATing on the warning escapes the telegraph entirely", fmt("%d hits", dodgeHits))

	-- a strong team: minion waves, BossDown, shares
	local strongTeam = { pet("cloudy_dragon", 25), pet("twilight_dragon", 28), pet("ember_phoenix", 26, "Golden"), pet("aurora_fox", 24, "Golden") }
	bt = BS.new({ Mode = "Raid", Boss = "frost_wyrm", Seed = 4, Teams = { team(10, 1, strongTeam, { Auto = true }), team(11, 1, strongTeam, { Auto = true }) } })
	local spawnWaves, minionInfoOk = 0, true
	local raidEvents = run(bt, 3400, function(stepEvents)
		for _, ev in ipairs(stepEvents) do
			if ev.type == "Spawn" then
				spawnWaves = spawnWaves + 1
				for _, info in ipairs(ev.units) do
					if info.kind ~= "Minion" or info.side ~= 2 or not PC.Get(info.petId) or info.maxHp <= 0 then
						minionInfoOk = false
					end
				end
			end
		end
	end)
	res = bt:Result()
	T.check(res and res.Reason == "BossDown" and res.WinnerSide == 1 and #res.Winners == 2 and res.BossId == "frost_wyrm" and res.Duration < BC.Bosses.frost_wyrm.EnrageAt, "two strong teams bring the Frost Wyrm down before the enrage", res and (res.Reason .. " " .. res.Duration))
	T.check(spawnWaves >= 2 and minionInfoOk, "minion waves spawn at the HP thresholds with static infos (kind Minion)", spawnWaves)
	T.check(res and abs((res.Shares[10] or 0) + (res.Shares[11] or 0) - 1) < 1e-6 and res.Damage[10] > 0 and res.Damage[11] > 0, "damage shares of the participants sum to 1")
	T.check(countType(raidEvents, "KO") >= 1, "minions and / or pets go down during the raid")

	-- join and leave while a raid runs; abandoned raid
	bt = BS.new({ Mode = "Raid", Boss = "shadow_hydra", Seed = 6, Teams = { team(20, 1, mid, { Auto = true }) } })
	local max0 = bt:BossStatus().MaxHp
	run(bt, 20)
	local infos, joinReason = bt:AddTeam(team(21, 1, mid, { Auto = true }))
	T.check(type(infos) == "table" and #infos == 3 and infos[1].owner == 21 and infos[1].slot == 1, "AddTeam during a raid returns the new unit infos", joinReason)
	local joinEvents = bt:Step(0.1)
	T.check(countType(joinEvents, "Spawn") == 1 and joinEvents[1].owner == 21, "a Spawn event announces the joining team")
	local max1 = bt:BossStatus().MaxHp
	T.check(max1 > max0 * 1.8 and bt:BossStatus().Players == 2, "the boss grows by the newcomer's share", fmt("%d -> %d", max0, max1))
	local infos2, dupReason = bt:AddTeam(team(21, 1, mid))
	T.check(infos2 == nil and dupReason == "DuplicateOwner", "the same owner cannot join twice")
	T.check(bt:RemoveTeam(21) == true and bt:RemoveTeam(21) == false and bt:RemoveTeam("boss") == false, "RemoveTeam once; NPC / boss teams cannot leave")
	local leaveEvents = bt:Step(0.1)
	T.check(countType(leaveEvents, "Leave") == 1 and leaveEvents[1].owner == 21 and #leaveEvents[1].units == 3, "a Leave event lists the leaving units")
	T.check(abs(bt:BossStatus().MaxHp - max0) <= max0 * 0.05 and bt:BossStatus().Players == 1, "the boss sheds the leaver's share", bt:BossStatus().MaxHp)
	snap = bt:Snapshot()
	T.check(snap.Units[infos[1].id] == nil and snap.Units[1] ~= nil and snap.Units[bt.boss.id] ~= nil, "left units vanish from the snapshot (the boss and the other team stay)")
	okCmd, why = bt:Command(21, "Attack")
	T.check(okCmd == false and why == "Left", "a team that left cannot command")
	T.check(bt:Command(20, "Forfeit") == true, "Forfeit in a raid = leave")
	bt:Step(0.1)
	res = bt:Result()
	T.check(res and res.Reason == "Abandoned" and res.WinnerSide == nil and #res.Winners == 0, "a raid everyone left ends Abandoned")

	-- enrage: a team that hides until the timer runs out sees the Enrage event (an Auto team keeps its RETREAT order;
	-- a player team would go back to attacking by itself after Damage.RetreatLock + RetreatAutoResume)
	bt = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 9, Teams = { team(30, 1, strongTeam, { Auto = true }) } })
	bt:Command(30, "Retreat")
	local enrage, enrageAt = nil, nil
	local bossUnit = bt.boss
	run(bt, floor(BC.Bosses.storm_titan.EnrageAt / 0.1) + 30, function(stepEvents)
		for _, ev in ipairs(stepEvents) do
			if ev.type == "Enrage" then
				enrage, enrageAt = ev, bt:Time()
			end
		end
	end)
	T.check(enrage ~= nil and enrage.unit == bossUnit.id and enrageAt and abs(enrageAt - BC.Bosses.storm_titan.EnrageAt) < 0.2, "the boss enrages at EnrageAt (Enrage event)", enrageAt)
	T.check(bossUnit.enraged == true and bossUnit.damageMult > 1 and bt:BossStatus().Enraged == true, "an enraged boss hits harder (BossStatus.Enraged)")
	T.check(bt:Result() == nil or bt:Result().Reason == "Timeout" or bt:Result().Reason == "Wipe", "hiding is not a win")

	-- SetAnchor
	bt = BS.new({ Mode = "Duel", Seed = 1, Teams = { team(1, 1, commons), team(2, 2, commons) } })
	T.check(bt:SetAnchor(1, 10, -10) == true and bt:TeamOf(1).Anchor.x == 10 and bt:TeamOf(1).Anchor.z == -10, "SetAnchor moves the retreat point")
	T.check(bt:SetAnchor(1, 999, 0) == true and abs(bt:TeamOf(1).Anchor.x) <= BC.Zones.Duel.X / 2, "anchors are clamped to the floor")
	T.check(bt:SetAnchor(1, "x", 0) == false and bt:SetAnchor(9, 0, 0) == false, "junk anchors refused")
	T.check(bt:Step("junk") ~= nil and bt:Time() > 0 and bt:Step(100) ~= nil and bt:Time() < 1, "Step clamps junk / huge dt")

	-- performance: 8 teams x 4 pets + boss + waves at 10 Hz
	local teams = {}
	for i = 1, 8 do
		teams[i] = team(100 + i, 1, strongTeam, { Auto = true })
	end
	bt = BS.new({ Mode = "Raid", Boss = "shadow_hydra", Seed = 5, Teams = teams })
	local clock = Mock.RealClock or os.clock
	local t0 = clock()
	local perfSteps, perfEvents = 0, 0
	while not bt:IsFinished() and perfSteps < 3000 do
		local e = bt:Step(0.1)
		bt:Snapshot()
		perfSteps = perfSteps + 1
		perfEvents = perfEvents + #e
	end
	local ms = (clock() - t0) / math.max(1, perfSteps) * 1000
	T.check(perfSteps > 300 and ms < 1.0, "a full raid (8 x 4 pets + boss + waves) steps + snapshots in under 1 ms (LuaJIT)", fmt("%.3f ms/step over %d steps, %d units", ms, perfSteps, #bt.units))
	T.check(perfEvents / math.max(1, perfSteps) < 12, "a full raid emits a handful of events per step", fmt("%.1f", perfEvents / math.max(1, perfSteps)))
	T.info("*raid of 32 pets: " .. fmt("%.3f ms per step, %.1f events per step, %s after %.0f s", ms, perfEvents / math.max(1, perfSteps), bt:Result() and bt:Result().Reason or "running", bt:Time()))
end)

----------------------------------------------------------------------------------------------------
-- p4battle_catalog (Phase 4: training, evolution, the loss-XP gate, the Champion Ring data and solver)
----------------------------------------------------------------------------------------------------
-- the Phase 3 RecommendedPower of trials 1-30: NPC pets never evolve or train, so these never move
local TRIAL_POWER = { 2, 18, 22, 24, 36, 36, 41, 48, 56, 78, 78, 93, 112, 136, 180, 188, 225, 268, 313, 429, 430, 509, 609, 726, 981, 1020, 1208, 1430, 1715, 2300 }

local function allRanks(r)
	return { Speed = r, Physique = r, Ability = r, Defense = r }
end

S.p4battle_catalog = guarded("p4battle_catalog", function()
	local BC, err = loadModule("BattleCatalog")
	if not T.check(BC ~= nil, "BattleCatalog loads", err) then
		return
	end
	local PC = loadModule("PetCatalog")
	local D = BC.Damage

	-- zones, time limits, training data, the loss-XP gate
	T.check(BC.Zones.Ring and BC.Zones.Ring.X == 44 and BC.Zones.Ring.Z == 44 and BC.TimeLimits.Ring == 90 and BC.Ring.TimeLimit == 90, "Zones.Ring = 44 x 44, TimeLimits.Ring = Ring.TimeLimit = 90")
	T.check(BC.Zones.Trial.X == 56 and BC.Zones.Duel.X == 44 and BC.Zones.Raid.X == 96 and BC.TimeLimits.Trial == 120 and BC.TimeLimits.Duel == 120 and BC.TimeLimits.Raid == 330, "the Phase 3 zones and time limits are unchanged")
	local TR = BC.Training
	T.check(TR.MaxRank == 10 and TR.Speed == 0.04 and TR.Physique == 0.05 and TR.Ability == 0.04 and TR.AbilityMeter == 0.04 and TR.Defense == 0.03, "Training = { MaxRank 10, Speed .04, Physique .05, Ability .04, AbilityMeter .04, Defense .03 }")
	local skillIds = {}
	for i, sk in ipairs(BC.TrainingSkills) do
		skillIds[i] = sk.Id
		T.check(type(sk.Name) == "string" and type(sk.Text) == "string" and #sk.Text > 5, "TrainingSkills[" .. i .. "] has Id, Name, Text")
	end
	T.eq(table.concat(skillIds, ","), "Speed,Physique,Ability,Defense", "TrainingSkills order: Speed, Physique, Ability, Defense")
	local R = BC.TrialRewardRules
	T.check(abs(R.LossShare - 1 / 3) < 1e-12 and R.LossMinSeconds == 20 and R.LossMinDamage == 0.2, "TrialRewardRules: LossShare 1/3, LossMinSeconds 20, LossMinDamage 0.2")
	T.check(R.Xp.Base == 20 and R.Xp.PerLevel == 6 and R.Tokens.Base == 10, "the trial win rewards are unchanged")
	T.check(BC.RealLoss(20, 0) and BC.RealLoss(5, 0.2) and not BC.RealLoss(19.9, 0.19) and not BC.RealLoss(nil, nil) and not BC.RealLoss("x", "y"), "RealLoss: >= 20 s or >= 20% of the enemy HP dealt")
	T.check(BC.LossXp(26, 25, 0) == 9 and BC.LossXp(200, 3, 0.5) == 67 and BC.LossXp(200, 3, 0.1) == 0 and BC.LossXp(0, 60, 1) == 0 and BC.LossXp(nil, 60, 1) == 0, "LossXp = a third of the win XP for a real loss, 0 otherwise")

	-- UnitStats extras: none = the Phase 3 numbers exactly
	local t = T.tally("UnitStats with no extras / empty extras / an untrained entry = the Phase 3 numbers bit for bit")
	for _, id in ipairs({ "mallow_kitten", "storm_tabby", "aurora_fox", "stormfang", "honey_bunny" }) do
		for _, lv in ipairs({ 1, 20, 50, 100 }) do
			local a = BC.UnitStats(id, lv)
			local b = BC.UnitStats(id, lv, nil, {})
			local c = BC.UnitStats({ PetId = id, Level = lv })
			local same = a.MaxHp == b.MaxHp and a.Hit == b.Hit and a.Interval == b.Interval and a.SpecialPower == b.SpecialPower and a.MaxHp == c.MaxHp and a.Hit == c.Hit and a.Interval == c.Interval
			t:case(same and a.Defense == 0 and a.MeterRate == 1 and a.Evo == 0 and a.Boost == 1 and a.Train == nil, id .. " L" .. lv)
		end
	end
	t:report()
	local stats = PC.GetStats("storm_tabby", 10)
	local base = BC.UnitStats("storm_tabby", 10)
	T.near(base.MaxHp, stats.Health * D.HpScale, 1e-6, "UnitStats MaxHp still = Health x HpScale (GetStats untouched)")

	-- evolution
	local e1 = BC.UnitStats("storm_tabby", 20, nil, { Evo = 1 })
	local base20 = BC.UnitStats("storm_tabby", 20)
	T.check(e1.Evo == 1 and abs(e1.MaxHp / base20.MaxHp - 1.25) < 1e-9 and abs(e1.Hit / base20.Hit - 1.25) < 1e-9 and abs(e1.SpecialPower / base20.SpecialPower - 1.25) < 1e-9 and e1.Interval == base20.Interval, "Evolved I: x1.25 HP, hits and special (interval unchanged)")
	local epic = BC.UnitStats("aurora_fox", 50, nil, { Evo = 2 })
	local epicBase = BC.UnitStats("aurora_fox", 50)
	T.check(epic.Evo == 2 and abs(epic.MaxHp / epicBase.MaxHp - 1.5) < 1e-9 and abs(epic.Hit / epicBase.Hit - 1.5) < 1e-9, "Evolved II (an Epic pet): x1.5")
	T.check(BC.UnitStats("mallow_kitten", 60, nil, { Evo = 2 }).Evo == 1 and BC.UnitStats("mallow_kitten", 60, nil, { Evo = 9 }).Evo == 1 and BC.UnitStats("mallow_kitten", 60, nil, { Evo = -3 }).Evo == 0 and BC.UnitStats("mallow_kitten", 60, nil, { Evo = "x" }).Evo == 0, "a Common counts at most Evolved I; junk stages count 0")
	T.near(BC.UnitPower({ PetId = "storm_tabby", Level = 20, Evo = 1 }) / BC.UnitPower("storm_tabby", 20), 1.25, 0.03, "UnitPower x1.25 for Evolved I (read from the entry table)")

	-- training effects (one skill at a time), the cached def never mutated
	local def = PC.Get("storm_tabby")
	local speedBefore = def.Stats.Speed
	local sp = BC.UnitStats("storm_tabby", 10, nil, { Train = { Speed = 10 } })
	T.check(abs(base.Interval / sp.Interval - 1.4) < 1e-9 and sp.MaxHp == base.MaxHp and sp.Hit == base.Hit and abs(sp.Dps / base.Dps - 1.4) < 1e-9 and def.Stats.Speed == speedBefore, "Attack Speed rank 10: interval / 1.4 (def.Stats.Speed untouched)")
	local ph = BC.UnitStats("storm_tabby", 10, nil, { Train = { Physique = 4 } })
	T.check(abs(ph.MaxHp / base.MaxHp - 1.2) < 1e-9 and ph.SpecialPower == base.SpecialPower and ph.Hit == base.Hit, "Physique rank 4: max HP x1.2, the special does not grow with it")
	local ab = BC.UnitStats("storm_tabby", 10, nil, { Train = { Ability = 5 } })
	T.check(abs(ab.SpecialPower / base.SpecialPower - 1.2) < 1e-9 and abs(ab.MeterRate - 1.2) < 1e-9 and ab.Hit == base.Hit and ab.MaxHp == base.MaxHp, "Ability rank 5: special x1.2, MeterRate 1.2")
	local de = BC.UnitStats("storm_tabby", 10, nil, { Train = { Defense = 10 } })
	T.check(abs(de.Defense - 0.3) < 1e-9 and de.MaxHp == base.MaxHp, "Defense rank 10: Defense 0.30 (30% cap)")
	T.check(abs(BC.UnitStats("storm_tabby", 10, nil, { Train = { Defense = 25, Speed = 10.7 } }).Defense - 0.3) < 1e-9 and BC.UnitStats("storm_tabby", 10, nil, { Train = { Defense = -2, Physique = "x" } }).Train == nil, "ranks are whole numbers clamped to 0..10 (junk counts 0)")
	local flat = BC.UnitStats("storm_tabby", 10, nil, { Evo = 1, Speed = 3, Physique = 3, Ability = 3, Defense = 3, Job = { Stat = "Speed" } })
	local nested = BC.UnitStats("storm_tabby", 10, nil, { Evo = 1, Train = allRanks(3) })
	T.check(flat.MaxHp == nested.MaxHp and flat.Interval == nested.Interval and flat.Defense == nested.Defense and flat.Evo == 1, "a flat PetGrowth record works as extras too")
	local entry = { PetId = "storm_tabby", Level = 10, Evo = 1, Train = allRanks(3) }
	local fromEntry = BC.UnitStats(entry)
	T.check(fromEntry.MaxHp == nested.MaxHp and fromEntry.Hit == nested.Hit and fromEntry.Train.Speed == 3, "extras are read from an entry table")
	local over = BC.UnitStats(entry, nil, nil, { Evo = 0 })
	T.check(over.Evo == 0 and over.Train.Speed == 3, "explicit extras win over the entry's own fields")
	-- Boost (ring champions)
	local bo = BC.UnitStats("cloudy_dragon", 50, "Rainbow", { Boost = 3 })
	local boBase = BC.UnitStats("cloudy_dragon", 50, "Rainbow")
	T.check(abs(bo.MaxHp / boBase.MaxHp - 3) < 1e-9 and abs(bo.Hit / boBase.Hit - 3) < 1e-9 and abs(bo.SpecialPower / boBase.SpecialPower - 3) < 1e-9 and bo.Boost == 3, "Boost 3: HP, hits and the special x3")
	T.check(BC.UnitStats("cloudy_dragon", 50, nil, { Boost = 0.5 }).Boost == 1 and BC.UnitStats("cloudy_dragon", 50, nil, { Boost = 0 / 0 }).Boost == 1 and BC.UnitStats("cloudy_dragon", 50, nil, { Boost = math.huge }).MaxHp < math.huge, "a Boost <= 1 or junk is ignored; a huge Boost stays finite")
	T.near(BC.UnitPower({ PetId = "cloudy_dragon", Level = 50, Tier = "Rainbow", Boost = 3 }) / BC.UnitPower("cloudy_dragon", 50, "Rainbow"), 3, 0.01, "UnitPower x Boost")

	-- UnitPower honours Defense; TeamPower gains; ExpectedDps / BossHp / AverageMaxHp
	local tr10 = BC.UnitStats("storm_tabby", 10, nil, { Train = allRanks(10) })
	T.eq(BC.UnitPower("storm_tabby", 10, nil, { Train = allRanks(10) }), math.max(1, floor(sqrt(tr10.Dps * tr10.MaxHp / (1 - tr10.Defense)) * BC.PowerScale + 0.5)), "UnitPower = sqrt(Dps x MaxHp / (1 - Defense)) x PowerScale")
	local mid = { { PetId = "aurora_fox", Level = 12 }, { PetId = "storm_tabby", Level = 14 }, { PetId = "frostling_penguin", Level = 12 } }
	local function trained(list, ranks, evo)
		local out = {}
		for i, e in ipairs(list) do
			out[i] = { PetId = e.PetId, Level = e.Level, Tier = e.Tier, Train = ranks, Evo = evo }
		end
		return out
	end
	local p0 = BC.TeamPower(mid)
	local r5, r10 = BC.TeamPower(trained(mid, allRanks(5))) / p0, BC.TeamPower(trained(mid, allRanks(10))) / p0
	T.check(r5 >= 1.25 and r5 <= 1.4 and r10 >= 1.6 and r10 <= 1.85, "TeamPower: all four skills rank 5 x1.25-1.4, rank 10 x1.6-1.85", fmt("x%.2f / x%.2f", r5, r10))
	local dps0 = BC.ExpectedDps({ Pets = mid })
	local manual = 0
	local syn = BC.SynergyBonus(mid)
	for i, e in ipairs(mid) do
		manual = manual + BC.UnitStats(e).Dps * (syn.PowerMult[i] or 1)
	end
	T.near(dps0, manual, 1e-9, "ExpectedDps of an untrained team = the Phase 3 sum (boss HP unchanged)")
	local dpsAb = BC.ExpectedDps({ Pets = trained(mid, { Ability = 10 }) })
	T.near(dpsAb / dps0, 1 + D.SpecialDpsShare * (1.4 * 1.4 - 1), 1e-9, "ExpectedDps counts Ability's stronger, faster specials (Damage.SpecialDpsShare)")
	T.check(BC.BossHp("storm_titan", { { Pets = trained(mid, allRanks(10), 1) } }) > BC.BossHp("storm_titan", { { Pets = mid } }) * 1.5, "a trained + evolved team faces a bigger raid boss")
	T.near(BC.AverageMaxHp({ Pets = trained(mid, { Physique = 10 }) }) / BC.AverageMaxHp({ Pets = mid }), 1.5, 1e-9, "AverageMaxHp counts Physique")

	-- the trial numbers never move (NPC pets never evolve or train)
	t = T.tally("Trials 1-30 keep their Phase 3 RecommendedPower and their NPC entries carry no Evo / Train / Boost")
	for lv = 1, 30 do
		local trial = BC.Trials[lv]
		local clean = true
		for _, e in ipairs(BC.TrialTeam(lv).Pets) do
			if e.Evo ~= nil or e.Train ~= nil or e.Boost ~= nil then
				clean = false
			end
		end
		t:case(trial.RecommendedPower == TRIAL_POWER[lv] and clean, "trial " .. lv .. ": " .. tostring(trial.RecommendedPower))
	end
	t:report()

	-- the Champion Ring data
	local Ring = BC.Ring
	T.check(#Ring.EasyRounds == 3 and Ring.EasyRounds[1].PetId == "pebble_pup" and Ring.EasyRounds[1].Handicap == 0.45 and Ring.EasyRounds[2].PetId == "pip_penguin" and Ring.EasyRounds[2].Handicap == 0.55 and Ring.EasyRounds[3].PetId == "honey_bunny" and Ring.EasyRounds[3].Handicap == 0.65,
		"Ring.EasyRounds: pebble_pup 0.45, pip_penguin 0.55, honey_bunny 0.65")
	T.check(Ring.FirstPower == 3.0 and Ring.Growth == 1.18 and Ring.BossEvery == 10 and Ring.BossBump == 1.15 and Ring.MinHandicap == 0.3 and Ring.ChampionMaxLevel == 50, "Ring curve: FirstPower 3.0, Growth 1.18, BossEvery 10, BossBump 1.15, MinHandicap 0.3, ChampionMaxLevel 50")
	T.check(Ring.CashFloorBase == 20 and Ring.CashFloorPerRound == 2 and Ring.SecondsBase == 1.5 and Ring.SecondsPerRound == 0.1 and Ring.SecondsMax == 9 and Ring.RecordMult == 3 and Ring.BossTokens == 100 and Ring.XpBase == 20 and Ring.XpPerRound == 6 and Ring.Intermission == 3,
		"Ring rewards: floor 20 + 2r, seconds min(9, 1.5 + 0.1r), record x3, boss Tokens 100, XP 20 + 6r, 3 s between rounds")
	local bandOk = #Ring.Bands == 7 and Ring.Bands[1].From == 4 and Ring.Bands[1].To == 9 and Ring.Bands[7].From == 42 and Ring.Bands[7].To == nil and Ring.Bands[7].Rarities[1] == "Mythic" and Ring.Bands[7].Rarities[2] == "Secret"
	T.check(bandOk, "Ring.Bands: 4-9 Common ... 42+ Mythic / Secret")
	T.check(BC.RingTarget(1) == 0 and BC.RingTarget(3) == 0 and abs(BC.RingTarget(4) - 3) < 1e-9 and abs(BC.RingTarget(5) - 3.54) < 1e-9 and abs(BC.RingTarget(10) - 3 * 1.18 ^ 6 * 1.15) < 1e-9, "RingTarget: 0 for rounds 1-3, 3.0 x 1.18^(r-4), x1.15 on every 10th")

	-- ChampionTeam: the easy rounds, the spec shape
	for r = 1, 3 do
		local spec = BC.ChampionTeam(r, 7)
		local e = spec.Pets[1]
		T.check(#spec.Pets == 1 and e.PetId == Ring.EasyRounds[r].PetId and e.Level == 1 and e.Handicap == Ring.EasyRounds[r].Handicap and e.Boost == nil and PC.Get(e.PetId).Rarity == "Common", "round " .. r .. ": one handicapped level-1 Common (" .. e.PetId .. ")")
	end
	local spec = BC.ChampionTeam(12, 5)
	local e = spec.Pets[1]
	T.check(spec.Owner == "npc" and spec.Side == 2 and spec.Npc == true and spec.Round == 12 and type(spec.Name) == "string" and spec.Name:find("Champion") and #spec.Pets == 1 and e.Slot == 1 and e.Crowned == true and e.Key == e.PetId and type(e.Level) == "number" and type(e.Tier) == "string",
		"ChampionTeam is a BattleSim team spec: npc, side 2, one crowned pet in slot 1")
	T.check(type(spec.Champion) == "table" and spec.Champion.PetId == e.PetId and spec.Champion.Level == e.Level and spec.Champion.Tier == e.Tier and type(spec.Champion.Boss) == "boolean" and type(spec.Champion.Name) == "string" and spec.Champion.Power == spec.Power and spec.TargetPower > 0,
		"ChampionTeam.Champion = { PetId, Level, Tier, Boss, Name, Power } for the Start payload")
	spec.Pets[1].Level = 999
	T.check(BC.ChampionTeam(12, 5).Pets[1].Level ~= 999, "ChampionTeam returns fresh tables")
	T.check(BC.ChampionTeam(nil, nil) ~= nil and BC.ChampionTeam("x", "y") ~= nil and BC.ChampionTeam(-5, 3).Round == 1 and BC.ChampionTeam(1e12, 3).Round == Ring.MaxRound and BC.ChampionTeam(4.7, 3).Round == 4, "junk rounds / seeds never error (rounds clamp to 1..MaxRound)")
	T.check(BC.RingPower(25, 9) == BC.ChampionTeam(25, 9).Power, "RingPower = ChampionTeam(...).Power")

	-- deterministic per seed, the ladder rules (monotonic, endless, bands, boss rounds, level cap, never EventOnly)
	local function sig(sp)
		local x = sp.Pets[1]
		return table.concat({ x.PetId, x.Level, x.Tier, tostring(x.Boss), tostring(x.Handicap), tostring(x.Boost), tostring(sp.Power) }, "|")
	end
	local first = {}
	for r = 1, 60 do
		first[r] = sig(BC.ChampionTeam(r, 4242))
	end
	for seed = 1, 80 do
		BC.ChampionTeam(40, seed) -- churn the per-seed history
	end
	local same, differs = true, false
	for r = 60, 1, -1 do
		if sig(BC.ChampionTeam(r, 4242)) ~= first[r] then
			same = false
		end
		if sig(BC.ChampionTeam(r, 4243)) ~= first[r] then
			differs = true
		end
	end
	T.check(same, "ChampionTeam is deterministic per (round, seed), whatever was asked before (any order)")
	T.check(differs, "another run seed draws other champions")
	local mono = T.tally("the champion's power never drops from a round to the next (rounds 3-120, seeds 1-20)")
	local rules = T.tally("every champion: a band rarity, level <= ChampionMaxLevel, never an EventOnly pet, the giant mini-boss form on every 10th round")
	local boostTally = T.tally("Boost > 1 starts around rounds 38-50 and every champion from round 55 on is boosted")
	local rarityOf = {}
	for _, b in ipairs(Ring.Bands) do
		for r = b.From, b.To or 200 do
			rarityOf[r] = {}
			for _, rar in ipairs(b.Rarities) do
				rarityOf[r][rar] = true
			end
		end
	end
	for seed = 1, 20 do
		local last, firstBoost = 0, nil
		for r = 1, 120 do
			local sp = BC.ChampionTeam(r, seed)
			local x = sp.Pets[1]
			if r > 3 then
				mono:case(sp.Power >= last, fmt("seed %d round %d: %.2f < %.2f", seed, r, sp.Power, last))
			end
			last = sp.Power
			local d = PC.Get(x.PetId)
			if r > 3 then
				local okRule = d ~= nil and not d.EventOnly and rarityOf[r][d.Rarity] and x.Level >= 1 and x.Level <= Ring.ChampionMaxLevel and (r % 10 ~= 0 or x.Boss == true)
				rules:case(okRule, fmt("seed %d round %d: %s %s L%d boss %s", seed, r, x.PetId, d and d.Rarity or "?", x.Level, tostring(x.Boss)))
			end
			if x.Boost and not firstBoost then
				firstBoost = r
			end
			if r >= 55 then
				boostTally:case(x.Boost ~= nil and x.Boost > 1 and x.Level == Ring.ChampionMaxLevel and x.Tier == "Rainbow" and x.Boss == true, fmt("seed %d round %d not boosted", seed, r))
			end
		end
		boostTally:case(firstBoost ~= nil and firstBoost >= 38 and firstBoost <= 50, fmt("seed %d: first Boost at round %s", seed, tostring(firstBoost)))
	end
	mono:report()
	rules:report()
	boostTally:report()
	T.check(BC.RingPower(120, 1) > BC.RingPower(100, 1) and BC.RingPower(100, 1) > BC.RingPower(80, 1) and BC.RingPower(80, 1) > BC.RingPower(60, 1), "no ceiling: rounds 60 < 80 < 100 < 120")
	T.check(BC.ChampionTeam(200, 3).Power < math.huge and BC.RingPower(Ring.MaxRound, 3) < math.huge, "far rounds stay finite")

	-- RingRewards
	local rw = BC.RingRewards(1, 0, false)
	T.check(rw.Cash == 22 and rw.Xp == 26 and rw.Tokens == 0 and rw.Record == false and rw.Boss == false, "round 1, no garden income: the $22 floor and 26 XP")
	rw = BC.RingRewards(12, 300, false)
	T.check(rw.Cash == floor(300 * 2.7) and rw.Xp == 92 and abs(rw.Seconds - 2.7) < 1e-9, "round 12 at $300/s: 2.7 s of income ($810), 92 XP")
	T.check(BC.RingRewards(12, 300, true).Cash == 3 * 810 and BC.RingRewards(12, 300, true).Tokens == 0, "a new record pays x3 Cash (no Tokens off a boss round)")
	T.check(BC.RingRewards(20, 300, true).Tokens == 100 and BC.RingRewards(20, 300, false).Tokens == 0 and BC.RingRewards(20, 300, false).Boss == true, "the first win of a boss round (a record on a 10th round) pays 100 Tokens, once")
	T.check(abs(BC.RingSeconds(200) - 9) < 1e-9 and BC.RingRewards(200, 1000, false).Cash == 9000, "RingSeconds caps at 9 s")
	T.check(BC.RingRewards(5, -100, "yes").Cash == 30 and BC.RingRewards(5, 0 / 0, nil).Cash == 30 and BC.RingRewards("x", nil, nil).Xp == 26, "junk income / record flags pay the floor, no x3")
end)

----------------------------------------------------------------------------------------------------
-- p4battle_sim (Phase 4 BattleSim: the Ring mode, entry Evo / Train / Boost, Defense, the meter rate, unit info,
-- overtime and the duel hit cap, determinism and performance)
----------------------------------------------------------------------------------------------------
S.p4battle_sim = guarded("p4battle_sim", function()
	local BS, err = loadModule("BattleSim")
	if not T.check(BS ~= nil, "BattleSim loads", err) then
		return
	end
	local BC = loadModule("BattleCatalog")
	local D = BC.Damage

	local modes = {}
	for _, m in ipairs(BS.Modes) do
		modes[m] = true
	end
	T.check(modes.Trial and modes.Duel and modes.Raid and modes.Ring and #BS.Modes == 4, "BattleSim.Modes = Trial, Duel, Raid, Ring")
	T.check(BS.Events.Overtime == "Overtime", "BattleSim.Events.Overtime")

	-- a ring round: setup, describe, unit info
	local me = team(77, 1, { pet("maple_fox", 5, nil, { Evo = 0, Xp = 40, XpNext = 115 }) })
	local b = BS.new({ Mode = "Ring", Seed = 3, Round = 10, Teams = { me, BC.ChampionTeam(10, 3) } })
	T.check(b ~= nil, "a Ring battle starts with ChampionTeam on side 2")
	local desc = b:Describe()
	T.check(desc.Mode == "Ring" and desc.Zone.X == 44 and desc.Zone.Z == 44 and desc.TimeLimit == 90 and desc.Round == 10 and #desc.Sides[1] == 1 and desc.Sides[2][1] == "npc", "Describe: Mode Ring, 44 x 44, 90 s, Round 10")
	local mine, champ = nil, nil
	for _, u in ipairs(desc.Units) do
		if u.side == 1 then
			mine = u
		else
			champ = u
		end
	end
	T.check(mine and mine.evo == 0 and mine.xp == 40 and mine.xpNext == 115 and mine.crowned == nil and mine.boss == nil, "own unit info: evo, xp / xpNext from the entry")
	T.check(champ and champ.crowned == true and champ.boss == true and champ.kind == "MiniBoss" and champ.xp == nil and champ.evo == 0 and champ.scale > 1, "the round-10 champion: crowned, the giant mini-boss form (boss = true), no XP")
	local raw = BS.new({ Mode = "Duel", Seed = 1, Teams = { team(1, 1, { pet("maple_fox", 5, nil, { Xp = 10, XpNext = 1 / 0 }) }), team(2, 2, { pet("maple_fox", 5) }) } })
	T.check(raw:StaticUnits()[1].xp == 10 and raw:StaticUnits()[1].xpNext == nil and raw:StaticUnits()[2].xp == nil, "a non-finite XpNext (the level cap) is left out; entries without Xp send none")
	local snap = b:Snapshot()
	local keysOk = true
	for _, s in pairs(snap.Units) do
		for k in pairs(s) do
			if k ~= "x" and k ~= "z" and k ~= "hp" and k ~= "state" and k ~= "meter" and k ~= "target" and k ~= "shield" then
				keysOk = false
			end
		end
	end
	T.check(keysOk, "the snapshot wire format is unchanged (x, z, hp, state, meter, target, shield)")

	-- a single level-1 pet wins round 1; a ring timeout is a loss
	local t = T.tally("a single level-1 pet (any starter) wins ring round 1 (auto-battle)")
	for _, id in ipairs({ "pebble_pup", "honey_bunny", "pip_penguin", "mochi_slime", "sleepy_owl" }) do
		for seed = 1, 3 do
			local rb = BS.new({ Mode = "Ring", Seed = seed, Round = 1, Teams = { team(1, 1, { pet(id, 1) }, { Auto = true }), BC.ChampionTeam(1, seed) } })
			run(rb, 1000)
			local res = rb:Result()
			t:case(res and res.WinnerSide == 1 and res.Round == 1 and res.Mode == "Ring", id .. " seed " .. seed .. ": " .. tostring(res and res.Reason))
		end
	end
	t:report()
	local slow = BS.new({ Mode = "Ring", Seed = 2, Round = 4, TimeLimit = 2, Teams = { team(1, 1, { pet("mallow_kitten", 1) }), BC.ChampionTeam(4, 2) } })
	slow:Command(1, "Retreat")
	run(slow, 100)
	local res = slow:Result()
	T.check(res and res.Reason == "Timeout" and res.WinnerSide == 2 and res.Losers[1] == 1 and res.Round == 4, "a ring round at the time limit is lost (like a Trial)")
	T.check(type(res.Hp) == "table" and res.Hp[2] > 0, "results carry the HP share left per side (the loss-XP gate's damage dealt = 1 - Hp[enemy])")

	-- Boost: HP and hits x Boost in the sim
	local plain = BS.new({ Mode = "Ring", Seed = 1, Teams = { team(1, 1, { pet("maple_fox", 5) }), { Owner = "npc", Side = 2, Npc = true, Pets = { { PetId = "cloudy_dragon", Key = "cloudy_dragon", Level = 50, Tier = "Rainbow", Slot = 1, Boss = true } } } } })
	local boosted = BS.new({ Mode = "Ring", Seed = 1, Teams = { team(1, 1, { pet("maple_fox", 5) }), { Owner = "npc", Side = 2, Npc = true, Pets = { { PetId = "cloudy_dragon", Key = "cloudy_dragon", Level = 50, Tier = "Rainbow", Slot = 1, Boss = true, Boost = 4 } } } } })
	T.check(abs(boosted.units[2].maxHp / plain.units[2].maxHp - 4) < 1e-9 and abs(boosted.units[2].hit / plain.units[2].hit - 4) < 1e-9 and abs(boosted.units[2].specialPower / plain.units[2].specialPower - 4) < 1e-9, "entry.Boost: the champion's HP, hits and special x Boost (on top of the mini-boss form)")

	-- evolution / training in the sim (entry fields)
	local evoB = BS.new({ Mode = "Duel", Seed = 1, Teams = { team(1, 1, { pet("storm_tabby", 20, nil, { Evo = 1, Train = { Speed = 10, Physique = 10, Ability = 5, Defense = 10 } }) }), team(2, 2, { pet("storm_tabby", 20) }) } })
	local u1, u2 = evoB.units[1], evoB.units[2]
	T.check(abs(u1.maxHp / u2.maxHp - 1.25 * 1.5) < 1e-9 and abs(u1.hit / u2.hit - 1.25) < 1e-9 and abs(u2.interval / u1.interval - 1.4) < 1e-9 and abs(u1.defense - 0.3) < 1e-9 and abs(u1.meterRate - 1.2) < 1e-9 and u2.defense == 0 and u2.meterRate == 1,
		"entry Evo / Train reach the unit: HP x1.25 x1.5, hits x1.25, interval / 1.4, defense 0.3, meter rate 1.2")
	T.check(evoB:StaticUnits()[1].evo == 1 and evoB:StaticUnits()[2].evo == 0, "unit info evo")

	-- Defense: every hit on the defender x0.7, after the RETREAT halving (two identical duels, only the Defense differs)
	local function defenseDuel(defRank)
		local side2 = { pet("biscuit_bear", 15, nil, { Train = { Defense = defRank } }), pet("bamboo_panda", 15, nil, { Train = { Defense = defRank } }) }
		return BS.new({ Mode = "Duel", Seed = 31, Specials = false, Teams = { team(1, 1, { pet("storm_tabby", 15), pet("maple_fox", 15) }, { Auto = true }), team(2, 2, side2, { Auto = true }) } })
	end
	local function firstHitsOnSide2(bt, steps)
		local list = {}
		run(bt, steps, function(events)
			for _, ev in ipairs(events) do
				if ev.type == "Hit" and ev.to >= 3 and ev.dmg > 0 then
					list[#list + 1] = ev
				end
			end
		end)
		return list
	end
	local d0, d10 = defenseDuel(0), defenseDuel(10)
	local h0, h10 = firstHitsOnSide2(d0, 60), firstHitsOnSide2(d10, 60)
	local sum0, sum10, n = 0, 0, math.min(#h0, #h10, 8)
	for i = 1, n do
		sum0, sum10 = sum0 + h0[i].dmg, sum10 + h10[i].dmg
	end
	T.check(n >= 4 and abs(sum10 / sum0 - 0.7) < 0.05, "Defense rank 10: the same hits deal x0.7 (applyDamage)", fmt("%d hits: %d vs %d", n, sum10, sum0))
	d0, d10 = defenseDuel(0), defenseDuel(10)
	d0:Command(2, "Retreat")
	d10:Command(2, "Retreat")
	h0, h10 = firstHitsOnSide2(d0, 60), firstHitsOnSide2(d10, 60)
	sum0, sum10, n = 0, 0, 0
	for i = 1, math.min(#h0, #h10, 8) do
		if h0[i].retreat and h10[i].retreat then
			sum0, sum10, n = sum0 + h0[i].dmg, sum10 + h10[i].dmg, n + 1
		end
	end
	T.check(n >= 2 and abs(sum10 / sum0 - 0.7) < 0.06, "Defense stacks with the RETREAT halving (x0.5 x0.7)", fmt("%d hits: %d vs %d", n, sum10, sum0))

	-- the meter rate: Ability speeds up every meter gain (passive gain checked before anyone is in reach)
	local function meterDuel(ability)
		return BS.new({ Mode = "Duel", Seed = 9, Zone = 120, Specials = false, Teams = { team(1, 1, { pet("storm_tabby", 10, nil, { Train = { Ability = ability } }) }), team(2, 2, { pet("storm_tabby", 10) }) } })
	end
	local m0, m10 = meterDuel(0), meterDuel(10)
	local start0, start10 = m0.units[1].meter, m10.units[1].meter
	run(m0, 10)
	run(m10, 10)
	T.check(abs(start0 - start10) < 1e-9 and abs((m10.units[1].meter - start10) / (m0.units[1].meter - start0) - 1.4) < 1e-6, "Ability rank 10: the passive meter fills x1.4", fmt("%.2f vs %.2f", m10.units[1].meter - start10, m0.units[1].meter - start0))

	-- raids: the boss grows with a trained team (BossHp over the units' Evo / Train)
	local midPets = { pet("aurora_fox", 12), pet("storm_tabby", 14), pet("bamboo_panda", 14) }
	local trainedPets = {}
	for i, p in ipairs(midPets) do
		trainedPets[i] = pet(p.Key, p.Level, nil, { Evo = 1, Train = allRanks(10) })
	end
	local raidPlain = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 2, Teams = { team(1, 1, midPets) } })
	local raidTrained = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 2, Teams = { team(1, 1, trainedPets) } })
	T.near(raidTrained:BossStatus().MaxHp / raidPlain:BossStatus().MaxHp, BC.ExpectedDps({ Pets = trainedPets }) / BC.ExpectedDps({ Pets = midPets }), 0.02, "a trained team's raid boss grows with its expected DPS")
	raidTrained:AddTeam(team(2, 1, midPets))
	raidTrained:RemoveTeam(2)
	T.near(raidTrained:BossStatus().MaxHp / raidPlain:BossStatus().MaxHp, BC.ExpectedDps({ Pets = trainedPets }) / BC.ExpectedDps({ Pets = midPets }), 0.02, "the boss HP recomputed on a join / leave keeps the training")

	-- overtime + the duel hit cap: a trained Shield mirror (it would stall forever) ends before the time limit
	local stall = { pet("bubble_axolotl", 20, nil, { Train = allRanks(10) }) }
	local ot = BS.new({ Mode = "Duel", Seed = 4, Teams = { team(1, 1, stall, { Auto = true }), team(2, 2, stall, { Auto = true }) } })
	local otEvents = run(ot, 1300)
	local otRes = ot:Result()
	local otEv = nil
	for _, ev in ipairs(otEvents) do
		if ev.type == "Overtime" then
			otEv = otEv and "twice" or ev
		end
	end
	T.check(type(otEv) == "table" and otEv.at == D.Overtime.At and otEv.perSecond == D.Overtime.PerSecond, "one Overtime event at Damage.Overtime.At", tostring(otEv))
	T.check(otRes and otRes.Reason ~= "Timeout" and otRes.Duration < BC.TimeLimits.Duel and otRes.Duration > D.Overtime.At, "a trained Shield mirror ends in overtime, not at the time limit", otRes and (otRes.Reason .. " " .. otRes.Duration))
	local trialOt = BS.new({ Mode = "Trial", Trial = 3, Seed = 1, Teams = { team(1, 1, stall) } })
	local ringOt = BS.new({ Mode = "Ring", Seed = 1, Teams = { team(1, 1, stall), BC.ChampionTeam(30, 1) } })
	T.check(trialOt.overtimeAt == nil and ringOt.overtimeAt == nil and trialOt.maxHitShare == nil and ringOt.maxHitShare == nil and ot.overtimeAt == D.Overtime.At and ot.maxHitShare == D.MaxHit.Share, "overtime and the hit cap are duel rules (trials, raids and the ring unchanged)")
	local big = BS.new({ Mode = "Duel", Seed = 2, Teams = { team(1, 1, { pet("stormfang", 100, "Rainbow", { Evo = 2, Train = { Ability = 10, Speed = 10 } }) }, { Auto = true }), team(2, 2, { pet("mallow_kitten", 1) }, { Auto = true }) } })
	local maxShare = 0
	run(big, 300, function(events)
		for _, ev in ipairs(events) do
			if ev.type == "Hit" and ev.to == 2 then
				maxShare = math.max(maxShare, (ev.dmg + (ev.absorbed or 0)) / big.units[2].maxHp)
			end
		end
	end)
	T.check(maxShare > 0 and maxShare <= D.MaxHit.Share + 0.01, "in a duel no single hit takes more than Damage.MaxHit.Share of a pet (no one-shots, even L100 vs L1)", fmt("%.2f", maxShare))

	-- a duel's double knock-out (both last pets fall in the same step) goes to the team that dealt more damage;
	-- a forfeit or a trial keeps the draw (white-box: two adjacent pets on 1 HP that swing in the same step)
	local function doubleKo(mode, forfeit)
		local setup = { Mode = mode, Seed = 3, Specials = false, Teams = { team(1, 1, { pet("storm_tabby", 10) }, { Auto = true }), team(2, 2, { pet("storm_tabby", 10) }, { Auto = true }) } }
		local bt = BS.new(setup)
		local a, z = bt.units[1], bt.units[2]
		a.x, a.z, z.x, z.z = 0, -1.5, 0, 1.5
		a.hp, z.hp = 1, 1
		a.nextAttack, z.nextAttack = 0, 0
		bt.teams[1].damage, bt.teams[2].damage = 120, 80
		if forfeit then
			bt.forfeitSeen = true
		end
		bt:Step(0.1)
		return bt:Result()
	end
	local ko = doubleKo("Duel", false)
	T.check(ko and ko.WinnerSide == 1 and ko.Draw == false and ko.Reason == "Wipe" and ko.Winners[1] == 1, "a duel double knock-out goes to the team that dealt more damage (no draw)", ko and tostring(ko.Reason))
	ko = doubleKo("Duel", true)
	T.check(ko and ko.Draw == true and ko.WinnerSide == nil, "a double knock-out after a forfeit stays a draw", ko and tostring(ko.Reason))
	ko = doubleKo("Ring", false)
	T.check(ko and ko.Draw == true and ko.Reason == "Draw", "outside duels a double knock-out stays a draw (Phase 3 rule)", ko and tostring(ko.Reason))

	-- determinism with the new fields
	local function ringSetup(seed)
		return { Mode = "Ring", Seed = seed, Round = 15, Teams = { team(1, 1, { pet("storm_tabby", 8, nil, { Evo = 0, Train = { Speed = 3, Ability = 2 } }), pet("maple_fox", 7) }, { Auto = true }), BC.ChampionTeam(15, seed) } }
	end
	local ra, rb2 = BS.new(ringSetup(5)), BS.new(ringSetup(5))
	local sameRun = true
	for _ = 1, 400 do
		local e1, e2 = ra:Step(0.1), rb2:Step(0.1)
		if #e1 ~= #e2 then
			sameRun = false
		end
		for i, ev in ipairs(e1) do
			local ev2 = e2[i]
			if not ev2 or ev.type ~= ev2.type or ev.dmg ~= ev2.dmg or ev.to ~= ev2.to then
				sameRun = false
			end
		end
	end
	T.check(sameRun and ra:Result() ~= nil and ra:Result().WinnerSide == rb2:Result().WinnerSide and ra:Result().Duration == rb2:Result().Duration, "a ring round with trained pets replays the same for a seed")

	-- performance: a raid of 8 trained + evolved teams, ChampionTeam solves
	local teams = {}
	for i = 1, 8 do
		teams[i] = team(100 + i, 1, { pet("cloudy_dragon", 60, "Golden", { Evo = 2, Train = allRanks(10) }), pet("twilight_dragon", 60, nil, { Evo = 2, Train = allRanks(7) }), pet("ember_phoenix", 55, "Golden", { Evo = 2 }), pet("aurora_fox", 50, "Golden", { Evo = 1, Train = allRanks(4) }) }, { Auto = true })
	end
	local perf = BS.new({ Mode = "Raid", Boss = "shadow_hydra", Seed = 5, Teams = teams })
	local clock = Mock.RealClock or os.clock
	local t0 = clock()
	local steps = 0
	while not perf:IsFinished() and steps < 2000 do
		perf:Step(0.1)
		perf:Snapshot()
		steps = steps + 1
	end
	local ms = (clock() - t0) / math.max(1, steps) * 1000
	T.check(steps > 300 and ms < 1.0, "a raid of 8 trained + evolved teams steps in under 1 ms (LuaJIT)", fmt("%.3f ms over %d steps", ms, steps))
	t0 = clock()
	for seed = 5000, 5049 do
		BC.ChampionTeam(60, seed)
	end
	local solveMs = (clock() - t0) * 1000 / 50
	T.check(solveMs < 10, "ChampionTeam for a fresh run seed at round 60 takes a few ms at most", fmt("%.2f ms", solveMs))
	T.info("*Phase 4 battle core: " .. fmt("trained raid %.3f ms/step, cold ChampionTeam(60) %.2f ms", ms, solveMs))
end)

----------------------------------------------------------------------------------------------------
-- p3battle_balance: tools/sim_battle.lua as a library
----------------------------------------------------------------------------------------------------
S.p3battle_balance = guarded("p3battle_balance", function()
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
	T.check(#SIM.order >= 8 and SIM.sections.trials ~= nil and SIM.sections.raids ~= nil and #SIM.Stages == 10, "the report has its sections and 10 progression stages")
	local pet, team = SIM.pet, SIM.team
	-- mirror fairness
	local commons = { pet("mallow_kitten", 1), pet("puddle_frog", 1), pet("biscuit_bear", 1) }
	local agg = SIM.series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, commons, { Auto = true }), team(2, 2, commons, { Auto = true }) } }
	end, { [1] = "auto", [2] = "auto" }, 24)
	T.check(agg.n == 24 and agg.winPct >= 25 and agg.winPct <= 75 and agg.timeouts == 0, "mirror duel of Commons: fair (25-75%) and never stalls", fmt("%d%%, dur %.1f s", agg.winPct, agg.avgDur))
	T.check(agg.avgDur >= 20 and agg.avgDur <= 80, "a Commons duel lasts 20-80 s", fmt("%.1f", agg.avgDur))
	-- a day-1 team beats trial 1
	agg = SIM.series(function(seed)
		return { Mode = "Trial", Trial = 1, Seed = seed, Teams = { team(1, 1, SIM.Stages[1].Pets) } }
	end, { [1] = "player" }, 10)
	T.check(agg.winPct >= 80, "a brand-new team (3 level-1 pets) wins trial 1", fmt("%d%%", agg.winPct))
	-- the maxed team clears trial 30
	agg = SIM.series(function(seed)
		return { Mode = "Trial", Trial = 30, Seed = seed, Teams = { team(1, 1, SIM.Stages[10].Pets) } }
	end, { [1] = "player" }, 4)
	T.check(agg.winPct == 100, "the maxed team clears trial 30", fmt("%d%%", agg.winPct))
	-- a mid team cannot clear trial 30
	agg = SIM.series(function(seed)
		return { Mode = "Trial", Trial = 30, Seed = seed, Teams = { team(1, 1, SIM.Stages[5].Pets) } }
	end, { [1] = "player" }, 3)
	T.check(agg.winPct == 0, "a mid-game team cannot clear trial 30", fmt("%d%%", agg.winPct))
	-- a solo scripted dodger beats a raid
	local result, stats = SIM.run({ Mode = "Raid", Boss = "storm_titan", Seed = 3, Teams = { team(1, 1, SIM.Stages[8].Pets) } }, { [1] = "player" })
	T.check(result and result.Reason == "BossDown" and result.Duration >= 60 and result.Duration <= 240 and stats.dodges >= 3, "a solo prestige-2 team with a dodging player wins a Storm Titan raid in 1-4 minutes", result and fmt("%s %.0f s, %d dodges", result.Reason, result.Duration, stats.dodges))
	-- Phase 4 subset (the full sections: training, ring, level100)
	T.check(SIM.sections.training ~= nil and SIM.sections.ring ~= nil and SIM.sections.level100 ~= nil and SIM.sections.progression ~= nil, "the report has the Phase 4 sections (training, ring, level100, progression)")
	local BC = loadModule("BattleCatalog")
	local wins = 0
	for seed = 1, 6 do
		local res = SIM.run({ Mode = "Ring", Seed = seed, Round = 3, Teams = { team(1, 1, { pet("pip_penguin", 1) }), BC.ChampionTeam(3, seed) } }, { [1] = "player" })
		if res and res.WinnerSide == 1 then
			wins = wins + 1
		end
	end
	T.check(wins == 6, "one level-1 pip_penguin (the weakest starter) wins ring round 3 with a scripted player", fmt("%d of 6", wins))
	local stage1 = SIM.Stages[1].Pets
	local r = 1
	while r <= 30 do
		local res = SIM.run({ Mode = "Ring", Seed = 50 + r, Round = r, Teams = { team(1, 1, stage1), BC.ChampionTeam(r, 50) } }, { [1] = "player" })
		if not res or res.WinnerSide ~= 1 then
			break
		end
		r = r + 1
	end
	T.check(r - 1 >= 12 and r - 1 <= 21, "a Day-1 team (three level-1 Commons) sets a ring record around 13-19", r - 1)
	local mirror = {}
	for i, p in ipairs(SIM.Stages[5].Pets) do
		mirror[i] = pet(p.Key, p.Level, p.Tier, { Evo = 1, Train = { Speed = 10, Physique = 10, Ability = 10, Defense = 10 } })
	end
	agg = SIM.series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, mirror), team(2, 2, mirror) } }
	end, { [1] = "player", [2] = "player" }, 8)
	T.check(agg.n == 8 and agg.draws == 0 and agg.timeouts == 0 and agg.winPct >= 25 and agg.winPct <= 75, "a trained + evolved mirror duel (S5, rank 10) is fair and never stalls", fmt("%d%%, %.1f s", agg.winPct, agg.avgDur))
	T.info("*balance subset ok; the full report: see tools/README.md (sim_battle.lua)")
end)

return S
