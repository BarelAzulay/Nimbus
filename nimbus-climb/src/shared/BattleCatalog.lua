-- BattleCatalog: every number of the Phase 3 pet battles (ARCHITECTURE_V3.md "Phase 3: Pet battles" + the
-- "Phase 3 build contract", section 11 for elements / teams / synergy): species combat profiles, the damage formula
-- constants, the special effects per Special.Kind, team synergy, the 30 Trial levels, the boss roster, the event
-- schedule, raid reward tiers and the PvP trophy rules. Pure data + pure functions: no Instances, no services, no
-- yields; safe on the server and the client. Plain Lua 5.1-compatible syntax only.
--
-- BALANCE: the numbers below were tuned with tools/sim_battle.lua (run it with lupa, see tools/README.md): trial
-- curve vs typical teams along the tycoon progression, ~50% PvP win rate between equal teams and ~60-65% for an
-- element counter, boss raids with 1 / 3 / 8 players ending in 2-4 minutes, every special useful, no one-shots.
-- Change a number here -> re-run the sim; the smoke scenarios (tools/smoke_p3_battlecore.lua) check the basics.
--
-- Stat sources (never duplicated here): PetCatalog.GetStats(def|petId|key, level, tier) scales Power / Health by
-- rarity, level (+10% per level, TycoonCatalog XP curve) and tier (PetKeys.StatMultiplier: Golden 1.5, Rainbow 2.5).
-- The Speed stat is the BASE value (species tempo rating, not scaled): it sets the attack tempo and the move speed,
-- so a Secret pet hits 13x harder than a Common one but does not run 13x faster. The special's Power scales exactly
-- like the Stats. Damage = Power x Damage.DamageScale x profile DamageMult x PetCatalog.ElementMultiplier x
-- (1 +- Variance) x synergy; HP = Health x Damage.HpScale.
--
-- API (the contract):
--   BattleCatalog.Profiles[species]           { Attack = "Melee"|"Ranged", Range, MoveSpeed, Interval, HitRadius, DamageMult }
--   BattleCatalog.ProfileOf(def|species)       -> profile (the Default profile for unknown species)
--   BattleCatalog.Damage                       the formula constants (HpScale, DamageScale, Variance, Retreat*, Meter*, ...)
--   BattleCatalog.Specials[Kind]               { Name, Text, Role, ...effect numbers } for Blast, Heal, Shield, Storm,
--                                              Pounce, Freeze, Beam
--   BattleCatalog.UnitStats(def|petId|key|entry, level, tier, extras) -> { MaxHp, Hit, Interval, Dps, MoveSpeed, Range,
--                                              Ranged, Radius, SpecialPower, SpecialFactor, Profile, Species, Elements,
--                                              Scale, Defense, MeterRate, Evo, Boost, Train } | nil
--                                              Phase 4: extras = { Evo = 0..2 (the STORED stage, PetGrowth[key].Evo),
--                                              Train = { Speed, Physique, Ability, Defense } (ranks 0..10; the flat
--                                              PetGrowth record works too), Boost = > 1 (ring champions) }; read from
--                                              the entry table itself when extras is nil. Evolution x Power, Health and
--                                              the special (PetCatalog.EvolutionMultiplier); Training (section 3.7):
--                                              Interval / (1 + 0.04 Speed), MaxHp x (1 + 0.05 Physique) (the special
--                                              does not grow with it), special x (1 + 0.04 Ability), MeterRate = 1 +
--                                              0.04 Ability, Defense = 0.03 x rank (BattleSim.applyDamage); Boost x HP,
--                                              hits and the special. No extras = the Phase 3 numbers bit for bit (NPC
--                                              trial teams never evolve or train).
--   BattleCatalog.UnitPower(petId, level, tier, extras) -> n    a single number for the UI: sqrt(DPS x HP / (1 -
--                                              Defense)) / 3; petId may be a pet id, a pet key, a def (PetKeys.DefOf)
--                                              or an entry table (its Evo / Train / Boost count)
--   BattleCatalog.TeamPower(list)              -> n    list of { PetId | Key | Def, Level, Tier } (or plain ids / keys),
--                                              synergy included, x (3 / pets) ^ SizeExponent (focus fire favours fewer, bigger pets)
--   BattleCatalog.Synergy(list of petIds)      -> { { Id, Name, Text }... }   the active bonuses (ids / keys / defs)
--   BattleCatalog.SynergyBonus(list)           -> { PowerMult = { [i] = 1 | 1.1 | 1.2 | 1.3 }, HealthMult = 1 | 1.1,
--                                              Entries = Synergy(list), Groups = { [element] = count } }
--   BattleCatalog.Trials[level]                { Level, Name, Chapter, RecommendedPower, MiniBoss = bool, Boss = petId|nil,
--                                              Team = { { PetId, Level, Tier, Boss = bool, Handicap = 0..1|nil }... },
--                                              TimeLimit, Rewards = { Tokens, Xp, FirstClear = { Tokens, Gems } } }   (1..30;
--                                              level 1 is one handicapped pet: a sure first win for any single pet)
--   BattleCatalog.TrialCount                   30
--   BattleCatalog.TrialTeam(level)             -> a BattleSim team spec { Owner = "npc", Side = 2, Npc = true, Name, Pets }
--   BattleCatalog.Bosses[id]                   { Id, Name, Element, Blurb, HpPerPlayer, Radius, Basic, Attacks, Minions,
--                                              EnrageAt, TimeLimit, MinionPet, Scale }
--   BattleCatalog.BossOrder                    { "storm_titan", "lava_golem", "frost_wyrm", "shadow_hydra" }
--   BattleCatalog.NextBoss(index)              -> bossId (rotating roster, 1-based, wraps)
--   BattleCatalog.BossHp(bossId, teams)        -> hp, perTeam   HP that lasts HpPerPlayer seconds of every team's DPS
--   BattleCatalog.WeightedTeams(dpsList)       -> n   the head count behind GroupFactor / DamageGroup: min(1, dps / top dps)
--                                              per team, so joiners who deal nothing do not inflate the boss
--   BattleCatalog.Events                       { Schedule = { {Kind, EveryMinutes, AnnounceSeconds, DurationSeconds}... },
--                                              FirstAfterSeconds, DoubleRewardsMultiplier }
--   BattleCatalog.Raid                         reward tiers by damage share, event pet chance, gems chance
--   BattleCatalog.RaidTier(share, won)         -> tier table (Tiers[i], the Loss tier when won == false) for a damage
--                                              share 0..1, nil for a share of 0 (pets that never hit the boss earn nothing)
--   BattleCatalog.Trophies                     { Win, Loss, Draw, Floor, Forfeit, Tokens = { Win, Loss } }
--   BattleCatalog.Zones                        default floor sizes (studs) per mode, BattleCatalog.TimeLimits per mode
--                                              (Trial, Duel, Raid, Ring = 44 x 44 / 90 s)
--   BattleCatalog.Validate()                   -> ok, { problem... }
-- Extras: ExpectedDps(team spec), AverageMaxHp(team spec), StatsOf(entry), EventPets(), ChapterOf(level), TrialRewards(level, double)
--
-- Phase 4 ("Phase 4 build contract" 3.5-3.8, 5.4):
--   BattleCatalog.Training                     { MaxRank 10, Speed 0.04, Physique 0.05, Ability 0.04, AbilityMeter 0.04,
--                                              Defense 0.03 } (per rank); TrainingSkills = { { Id, Name, Text }... } in
--                                              the order Speed, Physique, Ability, Defense
--   BattleCatalog.TrialRewardRules             + LossShare 1/3, LossMinSeconds 20, LossMinDamage 0.2: a REAL loss (the fight
--                                              lasted >= 20 s or the team dealt >= 20% of the enemy team's HP; never a
--                                              forfeit / leave / disconnect / shutdown, which BattleService rules out)
--                                              pays a third of the win XP. LossXp(winXp, seconds, dealtShare) -> xp (0
--                                              when the gate is not met); RealLoss(seconds, dealtShare) -> bool
--   BattleCatalog.Ring                         the Champion Ring numbers (EasyRounds, FirstPower, Growth, BossEvery,
--                                              BossBump, MinHandicap, ChampionMaxLevel, Bands, cash / XP / token rules,
--                                              TimeLimit, Intermission)
--   BattleCatalog.ChampionTeam(round, seed)    -> a BattleSim team spec { Owner = "npc", Side = 2, Npc = true, Name, Round,
--                                              Seed, TargetPower, Power, Champion = { PetId, Level, Tier, Boss, Boost,
--                                              Handicap, Name, Power }, Pets = { { PetId, Key, Level, Tier, Slot = 1,
--                                              Boss, Handicap, Boost, Crowned = true } } }   pure and deterministic for
--                                              (round, seed); one crowned pet per round; the power never drops from a
--                                              round to the next and never stops growing (Boost past level 50 Rainbow)
--   BattleCatalog.RingPower(round, seed)       -> the champion's power of that round (ChampionTeam(...).Power)
--   BattleCatalog.RingTarget(round)            -> the curve's target power (0 for the easy rounds 1-3)
--   BattleCatalog.RingSeconds(round)           -> min(SecondsMax, SecondsBase + SecondsPerRound x round)
--   BattleCatalog.RingRewards(round, incomePerSecond, isRecord) -> { Cash, Xp, Tokens, Seconds, Floor, Record, Boss }

local Shared = script.Parent
local Config = require(Shared.Config)

local BattleCatalog = {}

local floor, sqrt, max, min, huge = math.floor, math.sqrt, math.max, math.min, math.huge

BattleCatalog.Version = 1

----------------------------------------------------------------------
-- Lazy modules (load order must never matter; builds without one still get the local fallbacks)
----------------------------------------------------------------------
local lazyCache = {}
local function lazy(name)
	local entry = lazyCache[name]
	if entry == nil then
		entry = false
		local inst = Shared:FindFirstChild(name)
		if inst then
			local ok, result = pcall(require, inst)
			if ok and type(result) == "table" then
				entry = result
			end
		end
		lazyCache[name] = entry
	end
	return entry or nil
end

local function petCatalog()
	return lazy("PetCatalog")
end

local function petKeys()
	return lazy("PetKeys")
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= huge and n ~= -huge
end

local function round(n, decimals)
	local m = 10 ^ (decimals or 0)
	return floor(n * m + 0.5) / m
end

local function num(v, default)
	if finite(v) then
		return v
	end
	return default
end

----------------------------------------------------------------------
-- Zones / time limits per mode (Config.Battle does not exist yet: local constants, see the deviations list)
----------------------------------------------------------------------
BattleCatalog.Zones = {
	Trial = { X = 56, Z = 56 }, -- a private pocket in the sky
	Duel = { X = 44, Z = 44 }, -- a duel ring
	Raid = { X = 96, Z = 96 }, -- the colosseum floor
	Ring = { X = 44, Z = 44 }, -- Phase 4: the Champion Ring pocket (one champion per round)
}
BattleCatalog.TimeLimits = { Trial = 120, Duel = 120, Raid = 330, Ring = 90 } -- Ring: a timeout is a loss, like a Trial
BattleCatalog.StepSeconds = 0.1 -- the server simulates at 10 Hz
BattleCatalog.MaxTeamSize = 4
BattleCatalog.BaseTeamSize = 3 -- the 4th slot unlocks at Prestige 1 (TycoonCatalog.Prestige.TeamSlotUnlock)

----------------------------------------------------------------------
-- Species combat profiles: melee pets walk up and bite, ranged pets stop at Range and shoot. Interval is the
-- attack cadence (seconds) at Speed 11; HitRadius is the body radius (studs) used for "in range" and area hits;
-- MoveSpeed in studs/s at Speed 11. Melee pets carry DamageMult 1.1 for the walk they must do.
----------------------------------------------------------------------
local function P(attack, range, move, interval, radius, mult)
	return { Attack = attack, Range = range, MoveSpeed = move, Interval = interval, HitRadius = radius, DamageMult = mult }
end

BattleCatalog.Profiles = {
	Cat = P("Melee", 4.5, 15, 1.1, 1.8, 1.1),
	Dog = P("Melee", 4.5, 14, 1.2, 1.8, 1.1),
	Fox = P("Melee", 5, 16, 1.0, 1.8, 1.1),
	Bunny = P("Melee", 4, 16, 1.0, 1.6, 1.1),
	Bear = P("Melee", 5, 11, 1.4, 2.4, 1.1),
	Panda = P("Melee", 5, 11, 1.35, 2.4, 1.1),
	Slime = P("Melee", 4, 10, 1.2, 1.8, 1.1),
	Stormfang = P("Melee", 5, 17, 1.0, 2.0, 1.1),
	Dragon = P("Ranged", 16, 13, 1.5, 2.2, 1.0), -- breath
	Owl = P("Ranged", 18, 14, 1.4, 1.6, 1.0), -- feather darts
	Unicorn = P("Ranged", 15, 15, 1.4, 2.0, 1.0), -- horn sparkles
	Phoenix = P("Ranged", 17, 15, 1.3, 2.0, 1.0), -- embers
	Frog = P("Ranged", 12, 13, 1.2, 1.6, 1.0), -- tongue / bubbles
	Penguin = P("Ranged", 13, 12, 1.3, 1.6, 1.0), -- snowballs
	Axolotl = P("Ranged", 12, 12, 1.3, 1.6, 1.0), -- water jets
}
BattleCatalog.DefaultProfile = P("Melee", 4.5, 14, 1.2, 1.8, 1.1)

function BattleCatalog.ProfileOf(subject)
	local species = subject
	if type(subject) == "table" then
		species = type(subject.Look) == "table" and subject.Look.Species or subject.Species
	end
	if type(species) == "string" and BattleCatalog.Profiles[species] then
		return BattleCatalog.Profiles[species]
	end
	return BattleCatalog.DefaultProfile
end

----------------------------------------------------------------------
-- The damage formula constants
----------------------------------------------------------------------
BattleCatalog.Damage = {
	HpScale = 2.6, -- MaxHp = Health (PetCatalog.GetStats) x HpScale
	DamageScale = 0.6, -- hit = Power x DamageScale x DamageMult x element x variance x synergy
	Variance = 0.2, -- every hit rolls x(1 - V .. 1 + V)
	Crit = { Chance = 0.1, Mult = 1.5 }, -- plain pet attacks (never specials, bosses or zones) crit; Hit events carry crit = true
	TargetSticky = 1.6, -- a pet keeps its target while it is within this x the nearest enemy's distance ...
	TargetSpread = 1.35, -- ... else picks at random among the enemies within this x the nearest distance
	MinHit = 1, -- a hit never deals less (before shields)
	Rate = { Base = 0.62, PerSpeed = 0.035 }, -- attacks per Interval: Base + PerSpeed x Speed  (7 -> 0.87, 15 -> 1.15)
	Move = { Base = 0.75, PerSpeed = 0.025 }, -- move speed factor: Base + PerSpeed x Speed    (7 -> 0.93, 15 -> 1.13)
	RetreatDamageTaken = 0.5, -- a retreating team takes half damage ...
	RetreatRegenPerSecond = 0.02, -- ... and regains 2% of max HP per second
	RetreatLock = 1.5, -- seconds after RETREAT before ATTACK is accepted again
	RetreatAutoResume = 3, -- a PLAYER team parked at its anchor goes back to attacking by itself this long after the lock
	TelegraphMargin = 1.5, -- studs of clearance a retreating pet keeps beyond the edge of a telegraph it steps out of
	MeterMax = 100, -- SPECIAL lights up at MeterMax
	MeterStart = { 20, 50 }, -- every pet starts a battle with a random meter in this range (first casts spread out)
	MeterOnHit = 4, -- meter gained per hit dealt (a pet trading blows fills its meter in ~12 s)
	MeterOnHurt = 2, -- meter gained per hit taken
	MeterPerSecond = 2, -- passive meter gain while alive
	CastSeconds = 0.5, -- a pet is Casting (no attacks) this long after a special
	SpecialScale = 1, -- global multiplier on every special effect
	-- a special is powered by its pet's own Power stat: effect x (base Power / Reference) ^ Exponent, so an Economy pet
	-- (Power 2-4) casts at about half strength while Combat pets (8-13) cast at full strength; Freeze stuns scale too
	SpecialPowerCurve = { Reference = 10, Exponent = 0.5 },
	SeparationRadius = 3.2, -- allies closer than this are pushed apart a little (a line telegraph should not catch a whole team)
	RetargetSeconds = 0.5, -- how often a pet re-picks its nearest enemy
	EngageSlack = 0.6, -- extra studs of reach so moving targets still get hit
	NpcSpecialDelay = { 0.4, 1.4 }, -- NPC teams cast a full special after this random delay
	KoMeterLoss = true, -- a downed pet's meter is lost
	-- Phase 4 OVERTIME (no stalemates): a trained Shield / Heal pet (Ability + Defense) can out-sustain its own mirror
	-- forever, so past At seconds every hit of a DUEL grows by PerSecond x the seconds past At (x2.5 at +10 s, x4 at
	-- +20 s) and the duel ends well before its time limit. Trials, raids and the ring keep their own endings (a
	-- timeout loses / the boss enrages); short custom time limits never reach it. BattleSim sends one Overtime event.
	Overtime = { Modes = { Duel = true }, At = 75, PerSecond = 0.15 },
	-- Phase 4 NO ONE-SHOTS in PvP: in a duel a single pet hit never takes more than Share of the victim's max HP (a
	-- trained + evolved level-100 Pounce would otherwise delete a full-health pet). Trials, raids and the ring: unchanged.
	MaxHit = { Modes = { Duel = true }, Share = 0.6 },
	-- Phase 4 NO DRAWS in PvP: when the last pets of both duel teams fall in the same step (a double knock-out, more
	-- likely in overtime), the team that dealt more damage in the fight wins; forfeits / leaves stay a draw
	DoubleKoByDamage = { Duel = true },
	-- ExpectedDps (boss HP, raid head counts): about this share of a pet's damage comes from its SPECIAL, so Ability
	-- training (special power x meter speed) adds to the expected damage and raids stay 100-240 s for trained teams
	SpecialDpsShare = 0.3,
}

----------------------------------------------------------------------
-- Special effects per Special.Kind (PetCatalog.SpecialKinds). "Scale" multiplies the pet's scaled Special.Power x
-- DamageScale; Role is for the UI. Every special resets the meter and puts the pet in the Casting state briefly.
----------------------------------------------------------------------
BattleCatalog.Specials = {
	Blast = { Name = "Blast", Role = "Area", Text = "Explodes on the target: damage to every enemy nearby.", Radius = 7, Scale = 0.55 },
	Heal = { Name = "Heal", Role = "Support", Text = "Restores health to the whole team.", Scale = 0.7 },
	Shield = { Name = "Shield", Role = "Support", Text = "Shields the whole team for a few seconds.", Scale = 0.7, Seconds = 6 },
	Storm = { Name = "Storm", Role = "Zone", Text = "A storm cloud rains damage on an area for a few seconds. Retreat to leave it!", Radius = 6, Seconds = 4, Scale = 0.9 },
	Pounce = { Name = "Pounce", Role = "Burst", Text = "Dashes to the target for one heavy strike.", Scale = 2.0, Range = 30 },
	Freeze = { Name = "Freeze", Role = "Control", Text = "Freezes enemies around the target: they cannot move or attack.", Radius = 6, Stun = 0.8, Scale = 0.4 },
	Beam = { Name = "Beam", Role = "Line", Text = "Fires a beam through the target that hits every enemy in its line.", Length = 26, Width = 4, Scale = 0.8 },
}
BattleCatalog.SpecialKinds = { "Blast", "Heal", "Shield", "Storm", "Pounce", "Freeze", "Beam" }

----------------------------------------------------------------------
-- Team synergy (section 11): 2 pets of the same element -> +10% Power for them, 3 -> +20%, 4 -> +30%;
-- 3+ different elements -> "Balanced", +10% Health for the whole team.
----------------------------------------------------------------------
BattleCatalog.SynergyRules = {
	SameElement = { [2] = 0.10, [3] = 0.20, [4] = 0.30 },
	BalancedElements = 3,
	BalancedHealth = 0.10,
}

----------------------------------------------------------------------
-- Resolving what a list entry means: a pet id, a pet key ("cat@Golden", "hyb:..."), a def table (PetKeys.DefOf),
-- or { PetId | Key | Def, Level, Tier }. Returns def, level, tier (tier nil = the def's own tier).
----------------------------------------------------------------------
local function resolveDef(subject)
	if type(subject) == "table" and type(subject.Stats) == "table" then
		return subject
	end
	if type(subject) ~= "string" then
		return nil
	end
	local pc = petCatalog()
	local def = pc and pc.Get and pc.Get(subject)
	if def then
		return def
	end
	local pk = petKeys()
	if pk and pk.DefOf then
		local ok, result = pcall(pk.DefOf, subject, nil)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

function BattleCatalog.StatsOf(entry)
	if entry == nil then
		return nil
	end
	local def, level, tier
	if type(entry) == "table" and type(entry.Stats) ~= "table" then
		def = resolveDef(entry.Def or entry.Key or entry.PetId or entry.Id)
		level = entry.Level
		tier = entry.Tier
	else
		def = resolveDef(entry)
	end
	if not def then
		return nil
	end
	return def, level, tier
end

-- attacks per second factor and move factor from the base Speed stat
local function speedOf(def)
	local s = type(def.Stats) == "table" and def.Stats.Speed
	if not finite(s) or s <= 0 then
		return 11
	end
	return s
end

local function rateFactor(speed)
	local r = BattleCatalog.Damage.Rate
	return max(0.4, r.Base + r.PerSpeed * speed)
end

local function moveFactor(speed)
	local m = BattleCatalog.Damage.Move
	return max(0.5, m.Base + m.PerSpeed * speed)
end

----------------------------------------------------------------------
-- Phase 4: the Training Place (section 3.7). Per rank: Attack Speed +4% attacks, Physique +5% max health, Ability +4%
-- special power and +4% special charge, Defense -3% damage taken (BattleSim.applyDamage, after the RETREAT halving and
-- before MinHit / shields). Ranks 0..MaxRank; at rank 10 an all-round trained team has ~x1.73 TeamPower.
----------------------------------------------------------------------
BattleCatalog.Training = { MaxRank = 10, Speed = 0.04, Physique = 0.05, Ability = 0.04, AbilityMeter = 0.04, Defense = 0.03 }
BattleCatalog.TrainingSkills = {
	{ Id = "Speed", Name = "Attack Speed", Text = "+4% attacks per rank" },
	{ Id = "Physique", Name = "Physique", Text = "+5% max health per rank" },
	{ Id = "Ability", Name = "Ability", Text = "+4% special power and charge per rank" },
	{ Id = "Defense", Name = "Defense", Text = "-3% damage taken per rank" },
}

-- Phase 4 helpers (one table: contract section 6)
local P4 = {}
P4.SKILLS = { "Speed", "Physique", "Ability", "Defense" }
P4.EVO_FALLBACK = { 1.25, 1.5 }
P4.MAX_BOOST = 1e12 -- a junk Boost never turns into inf / NaN HP

-- a rank as a whole number 0..MaxRank (junk -> 0)
function P4.rank(v)
	if not finite(v) or v < 1 then
		return 0
	end
	local top = num(BattleCatalog.Training.MaxRank, 10)
	v = floor(v)
	if v > top then
		return top
	end
	return v
end

-- the extras of a UnitStats call: explicit extras win field by field, else the entry table's own fields
-- -> evo stage (counted), ranks (table or nil when untrained), boost (>= 1)
function P4.extras(def, level, subject, extras)
	local entry = (type(subject) == "table" and type(subject.Stats) ~= "table") and subject or nil
	local function field(name)
		local v = nil
		if type(extras) == "table" then
			v = extras[name]
		end
		if v == nil and entry then
			v = entry[name]
		end
		return v
	end
	-- evolution: the stored stage, clamped to what the pet can reach (PetCatalog.EvolutionStage)
	local evo = 0
	local stored = field("Evo")
	if finite(stored) and stored >= 1 then
		local pc = petCatalog()
		if pc and pc.EvolutionStage then
			local ok, result = pcall(pc.EvolutionStage, def, level, stored)
			evo = (ok and finite(result)) and result or 0
		else
			evo = min(floor(stored), #P4.EVO_FALLBACK)
		end
	end
	-- training: Train = { Speed, Physique, Ability, Defense }, or the flat PetGrowth record itself
	local ranks = nil
	local train = field("Train")
	local source = type(train) == "table" and train or nil
	if not source and type(extras) == "table" then
		source = extras
	end
	if source then
		for _, skill in ipairs(P4.SKILLS) do
			local r = P4.rank(source[skill])
			if r > 0 then
				ranks = ranks or { Speed = 0, Physique = 0, Ability = 0, Defense = 0 }
				ranks[skill] = r
			end
		end
	end
	-- ring champions: x Boost (> 1 only; Handicap covers < 1)
	local boost = 1
	local b = field("Boost")
	if finite(b) and b > 1 then
		boost = min(b, P4.MAX_BOOST)
	end
	return evo, ranks, boost
end

function P4.evoMult(stage)
	if stage < 1 then
		return 1
	end
	local pc = petCatalog()
	if pc and pc.EvolutionMultiplier then
		local ok, m = pcall(pc.EvolutionMultiplier, stage)
		if ok and finite(m) and m > 0 then
			return m
		end
	end
	return P4.EVO_FALLBACK[min(stage, #P4.EVO_FALLBACK)] or 1
end

-- MaxHp, average hit, interval, DPS ... of one pet copy at a level and tier (+ Phase 4 extras: evolution, training,
-- the ring Boost; none of them -> exactly the Phase 3 numbers)
function BattleCatalog.UnitStats(subject, level, tier, extras)
	local def, entryLevel, entryTier = BattleCatalog.StatsOf(subject)
	if not def then
		return nil
	end
	if level == nil then
		level = entryLevel
	end
	if tier == nil then
		tier = entryTier
	end
	local evo, ranks, boost = P4.extras(def, level, subject, extras)
	local evoMult = P4.evoMult(evo)
	local TR = BattleCatalog.Training
	local speedMult, hpMult, abilityMult, meterRate, defense = 1, 1, 1, 1, 0
	if ranks then
		speedMult = 1 + num(TR.Speed, 0) * ranks.Speed
		hpMult = 1 + num(TR.Physique, 0) * ranks.Physique
		abilityMult = 1 + num(TR.Ability, 0) * ranks.Ability
		meterRate = 1 + num(TR.AbilityMeter, 0) * ranks.Ability
		defense = min(0.9, num(TR.Defense, 0) * ranks.Defense)
	end
	local pc = petCatalog()
	local stats = nil
	if pc and pc.GetStats then
		local ok, result = pcall(pc.GetStats, def, level, tier)
		if ok then
			stats = result
		end
	end
	if type(stats) ~= "table" then
		-- no catalog (should never happen in the game): raw base stats
		stats = { Power = def.Stats.Power or 1, Health = def.Stats.Health or 1, Speed = def.Stats.Speed or 11 }
	end
	local D = BattleCatalog.Damage
	local profile = BattleCatalog.ProfileOf(def)
	local speed = speedOf(def)
	local power = finite(stats.Power) and max(stats.Power, 0) or 0
	local health = finite(stats.Health) and max(stats.Health, 1) or 1
	local scale = 1
	if finite(def.Stats.Health) and def.Stats.Health > 0 then
		scale = health / def.Stats.Health
	end
	-- Attack Speed divides the interval (the cached def.Stats.Speed is never touched)
	local interval = profile.Interval / rateFactor(speed) / speedMult
	local hit = power * D.DamageScale * profile.DamageMult * evoMult * boost
	local specialPower, specialFactor = 0, 1
	if type(def.Special) == "table" and finite(def.Special.Power) then
		local curve = D.SpecialPowerCurve
		if type(curve) == "table" and finite(def.Stats.Power) and def.Stats.Power > 0 then
			specialFactor = (def.Stats.Power / num(curve.Reference, 10)) ^ num(curve.Exponent, 0.5)
		end
		-- `scale` is the level / rarity / tier growth only: Physique never feeds the special
		specialPower = def.Special.Power * scale * specialFactor * evoMult * abilityMult * boost
	end
	local elements = {}
	if pc and pc.ElementsOf then
		elements = pc.ElementsOf(def)
	elseif type(def.Element) == "string" then
		elements = { def.Element }
	end
	return {
		MaxHp = health * D.HpScale * evoMult * hpMult * boost,
		Hit = hit,
		Interval = interval,
		Dps = hit / interval,
		Defense = defense, -- 0..0.3: the share of every hit taken that Defense blocks (BattleSim.applyDamage)
		MeterRate = meterRate, -- x every SPECIAL meter gain (Ability)
		SpecialBoost = abilityMult, -- the Ability factor on the special (already inside SpecialPower)
		Evo = evo, -- the evolution stage that counts (0 / 1 / 2)
		Boost = boost, -- 1, or a ring champion's Boost
		Train = ranks, -- { Speed, Physique, Ability, Defense } (whole ranks) or nil when untrained
		MoveSpeed = profile.MoveSpeed * moveFactor(speed),
		Range = profile.Range,
		Ranged = profile.Attack == "Ranged",
		Radius = profile.HitRadius,
		SpecialPower = specialPower,
		SpecialFactor = specialFactor, -- the Power-curve factor (Freeze stuns scale with min(1, factor))
		Profile = profile,
		Species = (type(def.Look) == "table" and def.Look.Species) or "Cat",
		Elements = elements,
		Scale = scale,
		Level = level,
		Tier = tier,
	}
end

BattleCatalog.PowerScale = 1 / 3 -- UnitPower = sqrt(DPS x MaxHp / (1 - Defense)) x PowerScale (a Common level-1 fighter ~ 10)
-- TeamPower x (BaseTeamSize / pets) ^ SizeExponent: focus fire favours fewer, bigger pets (measured by tools/sim_battle.lua:
-- 3 pets beat 4 pets of the same summed power ~90% of the time; this takes ~5% off a 4-pet team and adds ~8% to a pair)
BattleCatalog.SizeExponent = 0.2

local function sizeFactor(n)
	if n < 1 then
		return 1
	end
	return (BattleCatalog.BaseTeamSize / n) ^ BattleCatalog.SizeExponent
end

-- Defense counts as effective HP (MaxHp / (1 - Defense)), so TeamPower, ExpectedDps-based boss HP and the duel practice
-- gap see trained pets as they really fight
function BattleCatalog.UnitPower(subject, level, tier, extras)
	local us = BattleCatalog.UnitStats(subject, level, tier, extras)
	if not us then
		return 0
	end
	local defense = num(us.Defense, 0)
	if defense > 0 then
		return max(1, floor(sqrt(us.Dps * us.MaxHp / (1 - defense)) * BattleCatalog.PowerScale + 0.5))
	end
	return max(1, floor(sqrt(us.Dps * us.MaxHp) * BattleCatalog.PowerScale + 0.5))
end

----------------------------------------------------------------------
-- Synergy
----------------------------------------------------------------------
local function elementsOfEntry(entry)
	local def = BattleCatalog.StatsOf(entry)
	if not def then
		return {}
	end
	local pc = petCatalog()
	if pc and pc.ElementsOf then
		return pc.ElementsOf(def)
	end
	if type(def.Element) == "string" then
		return { def.Element }
	end
	return {}
end

-- PowerMult[i] for each entry, HealthMult for the team, Entries (display list) and Groups (element -> count).
-- A dual-element hybrid counts for both of its elements; its Power bonus is the best group it belongs to.
function BattleCatalog.SynergyBonus(list)
	local out = { PowerMult = {}, HealthMult = 1, Entries = {}, Groups = {} }
	if type(list) ~= "table" then
		return out
	end
	local rules = BattleCatalog.SynergyRules
	local perEntry = {}
	local distinct = 0
	local n = 0
	for i, entry in ipairs(list) do
		n = i
		out.PowerMult[i] = 1
		local elems = elementsOfEntry(entry)
		perEntry[i] = elems
		for _, e in ipairs(elems) do
			if not out.Groups[e] then
				out.Groups[e] = 0
				distinct = distinct + 1
			end
			out.Groups[e] = out.Groups[e] + 1
		end
	end
	if n == 0 then
		return out
	end
	-- same-element groups, in Config.Elements.Order for a stable display order
	local order = (type(Config.Elements) == "table" and Config.Elements.Order) or {}
	for _, e in ipairs(order) do
		local count = out.Groups[e] or 0
		local bonus = rules.SameElement[min(count, 4)]
		if count >= 2 and bonus then
			local label = (count == 2 and "Pair") or (count == 3 and "Trio") or "Quartet"
			table.insert(out.Entries, {
				Id = e .. count,
				Name = e .. " " .. label,
				Element = e,
				Count = count,
				Text = string.format("+%d%% Power for %d %s pets", floor(bonus * 100 + 0.5), count, e),
			})
			for i = 1, n do
				for _, pe in ipairs(perEntry[i]) do
					if pe == e and out.PowerMult[i] < 1 + bonus then
						out.PowerMult[i] = 1 + bonus
					end
				end
			end
		end
	end
	if distinct >= rules.BalancedElements then
		out.HealthMult = 1 + rules.BalancedHealth
		table.insert(out.Entries, {
			Id = "Balanced",
			Name = "Balanced",
			Count = distinct,
			Text = string.format("+%d%% Health for the team (%d elements)", floor(rules.BalancedHealth * 100 + 0.5), distinct),
		})
	end
	return out
end

function BattleCatalog.Synergy(list)
	return BattleCatalog.SynergyBonus(list).Entries
end

-- Sum of UnitPower x sqrt(power bonus x health bonus); entries: { PetId | Key | Def, Level, Tier } or plain ids / keys
function BattleCatalog.TeamPower(list)
	if type(list) ~= "table" then
		return 0
	end
	local syn = BattleCatalog.SynergyBonus(list)
	local total = 0
	for i, entry in ipairs(list) do
		local up = BattleCatalog.UnitPower(entry)
		total = total + up * sqrt((syn.PowerMult[i] or 1) * syn.HealthMult)
	end
	return floor(total * sizeFactor(#list) + 0.5)
end

-- Expected DPS of a team spec ({ Pets = { entry... } } or a plain list), synergy Power included, elements ignored.
-- Phase 4: Ability training speeds up and powers up the specials, which carry about Damage.SpecialDpsShare of a pet's
-- damage: that part grows by SpecialBoost x MeterRate (exactly 1 without training: the Phase 3 boss HP is unchanged)
function BattleCatalog.ExpectedDps(team)
	local list = type(team) == "table" and (team.Pets or team) or {}
	local syn = BattleCatalog.SynergyBonus(list)
	local share = num(BattleCatalog.Damage.SpecialDpsShare, 0)
	local total = 0
	for i, entry in ipairs(list) do
		local us = BattleCatalog.UnitStats(entry)
		if us then
			local dps = us.Dps * (syn.PowerMult[i] or 1)
			local gain = num(us.SpecialBoost, 1) * num(us.MeterRate, 1)
			if gain > 1 and share > 0 then
				dps = dps * (1 + share * (gain - 1))
			end
			total = total + dps
		end
	end
	return total
end

-- Average MaxHp of a team spec's pets (Balanced bonus included)
function BattleCatalog.AverageMaxHp(team)
	local list = type(team) == "table" and (team.Pets or team) or {}
	local syn = BattleCatalog.SynergyBonus(list)
	local total, n = 0, 0
	for _, entry in ipairs(list) do
		local us = BattleCatalog.UnitStats(entry)
		if us then
			total = total + us.MaxHp * syn.HealthMult
			n = n + 1
		end
	end
	if n == 0 then
		return 0
	end
	return total / n
end

----------------------------------------------------------------------
-- The 30 Trials: NPC teams built from catalog pets. Six chapters of five levels, a mini-boss on every 5th level
-- (one pet of the team grown big: Boss = true -> HP x MiniBossHp, Power x MiniBossPower, model scale MiniBossScale).
-- The NPC pet level of each trial is solved at load so the team's power follows the target curve below.
----------------------------------------------------------------------
BattleCatalog.TrialCount = 30
BattleCatalog.MiniBoss = { Hp = 3, Power = 1.3, Scale = 1.7 }
BattleCatalog.TrialCurve = {
	FirstPower = 14, -- the curve's level-1 anchor (level 2 aims at ~17, a brand-new team of three level-1 Commons has ~23)
	FirstTrialPower = 2, -- level 1 itself: a sure first win for ANY single level-1 pet (one Cloud spin, no SPECIAL pressed)
	LastPower = 2000, -- level 30 target TeamPower (x BossBump): a level grows ~17%, so the power never drops
	BossBump = 1.15, -- mini-boss levels aim a step higher
	MaxPetLevel = 45, -- the NPC pet level the solver may use before stepping the team up a tier
}
BattleCatalog.TrialChapters = {
	{ Name = "Cloud Meadow", From = 1, To = 5 },
	{ Name = "Maple Grove", From = 6, To = 10 },
	{ Name = "Tidewater", From = 11, To = 15 },
	{ Name = "Thunderhead", From = 16, To = 20 },
	{ Name = "Twilight Peak", From = 21, To = 25 },
	{ Name = "Eclipse", From = 26, To = 30 },
}

-- { name, { petIds }, Boss = petId | nil, Handicap = 0..1 | nil (every NPC pet's HP, hits and special scaled down) }
local TRIAL_ROSTER = {
	-- Cloud Meadow (Common pets). Level 1 is the tutorial's first fight: one sleepy pebble pup at half strength, so a
	-- player who owns a single level-1 pet (any rarity, Economy or Combat) wins it without pressing anything.
	{ "Puddle Patrol", { "pebble_pup" }, Handicap = 0.5 },
	{ "Kitten Club", { "mallow_kitten", "pip_penguin", "honey_bunny" } },
	{ "Biscuit Brigade", { "biscuit_bear", "pebble_pup", "puddle_frog" } },
	{ "Frosty Friends", { "pip_penguin", "mallow_kitten", "biscuit_bear" } },
	{ "Meadow Guardian", { "biscuit_bear", "mallow_kitten", "puddle_frog" }, Boss = "biscuit_bear" },
	-- Maple Grove (Uncommon)
	{ "Maple Scouts", { "maple_fox", "waffle_corgi", "sleepy_owl" } },
	{ "Bamboo Band", { "bamboo_panda", "mochi_slime", "bubble_axolotl" } },
	{ "Night Owls", { "sleepy_owl", "maple_fox", "bubble_axolotl" } },
	{ "Bubble Trouble", { "bubble_axolotl", "mochi_slime", "maple_fox" } },
	{ "Grove Keeper", { "bamboo_panda", "maple_fox", "sleepy_owl" }, Boss = "bamboo_panda" },
	-- Tidewater (Rare; four pets from level 12)
	{ "Blossom Brigade", { "blossom_bunny", "storm_tabby", "shroomie_frog" } },
	{ "Storm Chasers", { "storm_tabby", "frostling_penguin", "maple_fox", "sleepy_owl" } },
	{ "Shroom Circle", { "shroomie_frog", "cherry_panda", "storm_tabby", "frostling_penguin" } },
	{ "Frost Line", { "frostling_penguin", "storm_tabby", "bamboo_panda", "bubble_axolotl" } },
	{ "Tide Warden", { "frostling_penguin", "storm_tabby", "cherry_panda", "shroomie_frog" }, Boss = "frostling_penguin" },
	-- Thunderhead (Epic + Legendary)
	{ "Aurora Pack", { "aurora_fox", "moonlit_owl", "storm_tabby", "frostling_penguin" } },
	{ "Nebula Drift", { "nebula_axolotl", "candy_unicorn", "aurora_fox", "moonlit_owl" } },
	{ "Moonlit Watch", { "moonlit_owl", "aurora_fox", "candy_unicorn", "ember_phoenix" } },
	{ "Ember Flight", { "ember_phoenix", "aurora_fox", "nebula_axolotl", "storm_tabby" } },
	{ "Thunder Lord", { "twilight_dragon", "ember_phoenix", "moonlit_owl", "aurora_fox" }, Boss = "twilight_dragon" },
	-- Twilight Peak (Legendary + Mythic)
	{ "Sunbeam Court", { "sunbeam_bear", "ember_phoenix", "twilight_dragon", "moonlit_owl" } },
	{ "Dusk Riders", { "twilight_dragon", "ember_phoenix", "aurora_fox", "candy_unicorn" } },
	{ "Starlight Choir", { "starlight_unicorn", "sunbeam_bear", "twilight_dragon", "ember_phoenix" } },
	{ "Cloud Guard", { "cloudy_dragon", "twilight_dragon", "ember_phoenix", "moonlit_owl" } },
	{ "Twilight Sovereign", { "cloudy_dragon", "starlight_unicorn", "twilight_dragon", "ember_phoenix" }, Boss = "cloudy_dragon" },
	-- Eclipse (Mythic + Secret)
	{ "Eclipse Vanguard", { "eclipse_dragon", "cloudy_dragon", "twilight_dragon", "ember_phoenix" } },
	{ "Obsidian Flames", { "obsidian_phoenix", "eclipse_dragon", "cloudy_dragon", "starlight_unicorn" } },
	{ "Phantom Court", { "phantom_kitsune", "obsidian_phoenix", "eclipse_dragon", "cloudy_dragon" } },
	{ "Storm Legion", { "stormfang", "eclipse_dragon", "obsidian_phoenix", "cloudy_dragon" } },
	{ "Stormfang's Challenge", { "stormfang", "eclipse_dragon", "obsidian_phoenix", "phantom_kitsune" }, Boss = "stormfang" },
}

-- Rewards: repeat Tokens / pet Xp grow with the level; the first clear pays a big token bonus and, on mini-boss
-- levels, Gems. Double Rewards hour doubles Tokens (TrialRewards(level, true)).
BattleCatalog.TrialRewardRules = {
	Tokens = { Base = 10, PerLevel = 3 }, -- 13 .. 100 per win
	Xp = { Base = 20, PerLevel = 6 }, -- pet XP per team pet per win: 26 .. 200
	FirstClearTokens = { PerLevel = 40, BossMult = 2 }, -- 40 .. 1200 (x2 on mini-boss levels)
	FirstClearGems = { [5] = 5, [10] = 8, [15] = 12, [20] = 16, [25] = 20, [30] = 30 },
	-- Phase 4 (section 3.5): a REAL loss pays a third of the win XP to every team pet. Real = the fight lasted at least
	-- LossMinSeconds OR the team dealt at least LossMinDamage of the enemy team's HP, and it was not a forfeit, a leave, a
	-- disconnect or a shutdown (BattleService rules those out). The same gate pays the round that ends a ring run.
	LossShare = 1 / 3,
	LossMinSeconds = 20,
	LossMinDamage = 0.2,
}

-- the loss-XP gate (section 3.5): seconds the fight lasted, dealtShare = the share of the enemy team's max HP the team
-- took off (0..1; BattleSim's result.Hp[enemySide] is what was LEFT, so dealtShare = 1 - that)
function BattleCatalog.RealLoss(seconds, dealtShare)
	local R = BattleCatalog.TrialRewardRules
	if finite(seconds) and seconds >= num(R.LossMinSeconds, 20) then
		return true
	end
	return finite(dealtShare) and dealtShare >= num(R.LossMinDamage, 0.2)
end

-- the XP a real loss pays per team pet: round(winXp x LossShare), 0 when the gate is not met (forfeits, leaves,
-- disconnects and shutdowns are the caller's to rule out before calling)
function BattleCatalog.LossXp(winXp, seconds, dealtShare)
	if not finite(winXp) or winXp <= 0 or not BattleCatalog.RealLoss(seconds, dealtShare) then
		return 0
	end
	return floor(winXp * num(BattleCatalog.TrialRewardRules.LossShare, 1 / 3) + 0.5)
end

function BattleCatalog.ChapterOf(level)
	for _, ch in ipairs(BattleCatalog.TrialChapters) do
		if level >= ch.From and level <= ch.To then
			return ch
		end
	end
	return nil
end

function BattleCatalog.TrialRewards(level, double)
	local lv = tonumber(level) or 1
	local R = BattleCatalog.TrialRewardRules
	local isBoss = (lv % 5 == 0)
	local mult = double and (BattleCatalog.Events.DoubleRewardsMultiplier or 2) or 1
	local firstTokens = R.FirstClearTokens.PerLevel * lv
	if isBoss then
		firstTokens = firstTokens * R.FirstClearTokens.BossMult
	end
	return {
		Tokens = floor((R.Tokens.Base + R.Tokens.PerLevel * lv) * mult + 0.5),
		Xp = R.Xp.Base + R.Xp.PerLevel * lv,
		FirstClear = {
			Tokens = floor(firstTokens * mult + 0.5),
			Gems = R.FirstClearGems[lv] or 0,
		},
	}
end

local function miniBossPower(entry)
	local base = BattleCatalog.UnitPower(entry)
	local mb = BattleCatalog.MiniBoss
	return floor(base * sqrt(mb.Hp * mb.Power) + 0.5)
end

-- TeamPower of a trial team (the mini-boss counts with its multipliers, a handicap scales every pet down)
local function trialTeamPower(team)
	local syn = BattleCatalog.SynergyBonus(team)
	local total = 0
	for i, entry in ipairs(team) do
		local up = entry.Boss and miniBossPower(entry) or BattleCatalog.UnitPower(entry)
		total = total + up * num(entry.Handicap, 1) * sqrt((syn.PowerMult[i] or 1) * syn.HealthMult)
	end
	return floor(total * sizeFactor(#team) + 0.5)
end

local function targetPower(level)
	local c = BattleCatalog.TrialCurve
	if level == 1 and finite(c.FirstTrialPower) then
		return c.FirstTrialPower
	end
	local n = BattleCatalog.TrialCount
	local t = (level - 1) / (n - 1)
	local p = c.FirstPower * (c.LastPower / c.FirstPower) ^ t
	if level % 5 == 0 then
		p = p * c.BossBump
	end
	return p
end

local function buildTrials()
	local trials = {}
	local pc = petCatalog()
	local maxLevel = (pc and pc.MaxPetLevel and pc.MaxPetLevel()) or 50
	local solverTop = min(BattleCatalog.TrialCurve.MaxPetLevel or 45, maxLevel)
	local lastPower = 0
	for level = 1, BattleCatalog.TrialCount do
		local row = TRIAL_ROSTER[level] or TRIAL_ROSTER[#TRIAL_ROSTER]
		local target = max(targetPower(level), lastPower) -- integer pet levels overshoot: never drop below the last level
		local handicap = nil
		if finite(row.Handicap) and row.Handicap > 0 and row.Handicap < 1 then
			handicap = row.Handicap
		end
		local function teamAt(lv, tr)
			local team = {}
			for i, petId in ipairs(row[2]) do
				team[i] = { PetId = petId, Level = lv, Tier = tr, Boss = (row.Boss == petId) or nil, Handicap = handicap }
			end
			return team
		end
		-- the lowest tier (Normal, then Golden, then Rainbow) whose level 1..MaxPetLevel reaches the target, at the
		-- smallest such level (binary search: power grows with the level)
		local tier = "Normal"
		local chosen = teamAt(1, tier)
		local power = trialTeamPower(chosen)
		if power < target then
			local done = false
			for _, tr in ipairs({ "Normal", "Golden", "Rainbow" }) do
				if not done then
					local lo, hi = 1, solverTop
					local topPower = trialTeamPower(teamAt(hi, tr))
					if topPower >= target then
						while lo < hi do
							local mid = floor((lo + hi) / 2)
							if trialTeamPower(teamAt(mid, tr)) >= target then
								hi = mid
							else
								lo = mid + 1
							end
						end
						chosen = teamAt(lo, tr)
						power, tier = trialTeamPower(chosen), tr
						done = true
					else
						chosen, power, tier = teamAt(hi, tr), topPower, tr -- best this tier can do; try the next
					end
				end
			end
		end
		lastPower = power
		local chapter = BattleCatalog.ChapterOf(level)
		trials[level] = {
			Level = level,
			Name = row[1],
			Chapter = chapter and chapter.Name or "",
			RecommendedPower = power,
			TargetPower = floor(target + 0.5),
			MiniBoss = (level % 5 == 0),
			Boss = row.Boss,
			Tier = tier,
			PetLevel = chosen[1] and chosen[1].Level or 1,
			Team = chosen,
			TimeLimit = BattleCatalog.TimeLimits.Trial,
			Rewards = BattleCatalog.TrialRewards(level, false),
		}
	end
	return trials
end

BattleCatalog.Trials = buildTrials()

-- A BattleSim team spec for the NPC side of a trial (fresh table; nil for unknown levels)
function BattleCatalog.TrialTeam(level)
	local trial = BattleCatalog.Trials[tonumber(level) or 0]
	if not trial then
		return nil
	end
	local pets = {}
	for i, entry in ipairs(trial.Team) do
		pets[i] = { PetId = entry.PetId, Key = entry.PetId, Level = entry.Level, Tier = entry.Tier, Slot = i, Boss = entry.Boss, Handicap = entry.Handicap }
	end
	return { Owner = "npc", Side = 2, Npc = true, Name = trial.Name, Pets = pets, Trial = trial.Level }
end

----------------------------------------------------------------------
-- Phase 4: the Champion Ring (section 3.8). One crowned champion pet per round, a stronger one every round. Rounds 1-3
-- are one handicapped level-1 Common (a sure win for any single level-1 pet). From round 4 the champion aims at the
-- target TeamPower FirstPower x Growth ^ (round - 4) (x BossBump on every BossEvery-th round), with a species drawn
-- with the run's seed from the round's rarity band (never an EventOnly pet), solved in this order: a plain level-1
-- pet above the target is handicapped down to it (Handicap >= MinHandicap); else the lowest level 1..ChampionMaxLevel
-- of the plain pet; else the mini-boss form (BattleCatalog.MiniBoss: HP x3, hits x1.3, model x1.7) at the lowest
-- level, Normal -> Golden -> Rainbow; else the level-ChampionMaxLevel Rainbow mini-boss with Boost = target / power
-- (HP, hits and the special x Boost), so the ladder never ends. Every BossEvery-th round is a "giant boss" round:
-- its champion always takes the mini-boss form (the plain-pet step is skipped). The target of a round is never below
-- the power of the round before (the trial builder's rule: integer levels overshoot a little), so the power never
-- drops from one round to the next. Champions keep the proven level-50 ladder after the player's level-100 rule.
----------------------------------------------------------------------
BattleCatalog.Ring = {
	EasyRounds = {
		{ PetId = "pebble_pup", Handicap = 0.45 },
		{ PetId = "pip_penguin", Handicap = 0.55 },
		{ PetId = "honey_bunny", Handicap = 0.65 },
	},
	FirstPower = 3.0, -- round 4's target TeamPower (one weak Common)
	Growth = 1.18, -- x per round
	BossEvery = 10, -- every 10th round: a giant boss champion, x BossBump, first win pays BossTokens
	BossBump = 1.15,
	MinHandicap = 0.3,
	ChampionMaxLevel = 50, -- champions never level past 50 (the Boost covers the rest)
	Bands = { -- the champion's rarity by round (rounds 1-3 are the EasyRounds); the last band is open-ended
		{ From = 4, To = 9, Rarities = { "Common" } },
		{ From = 10, To = 15, Rarities = { "Common", "Uncommon" } },
		{ From = 16, To = 21, Rarities = { "Uncommon", "Rare" } },
		{ From = 22, To = 27, Rarities = { "Rare", "Epic" } },
		{ From = 28, To = 33, Rarities = { "Epic", "Legendary" } },
		{ From = 34, To = 41, Rarities = { "Legendary", "Mythic" } },
		{ From = 42, Rarities = { "Mythic", "Secret" } },
	},
	-- Cash per round won = max(CashFloorBase + CashFloorPerRound x r, IncomePerSecond x RingSeconds(r)), x RecordMult on
	-- a new record; RingSeconds(r) = min(SecondsMax, SecondsBase + SecondsPerRound x r)
	CashFloorBase = 20,
	CashFloorPerRound = 2,
	SecondsBase = 1.5,
	SecondsPerRound = 0.1,
	SecondsMax = 9,
	RecordMult = 3,
	BossTokens = 100, -- the first win of a boss round (a new record on a BossEvery-th round)
	XpBase = 20, -- XP per team pet per round won: XpBase + XpPerRound x r (the run's last round: LossXp's third)
	XpPerRound = 6,
	TimeLimit = 90, -- = TimeLimits.Ring; a timeout is a loss
	Intermission = 3, -- seconds between two rounds
	MaxRound = 100000, -- rounds are clamped to 1..MaxRound
}

P4.RING_M = 2147483647
P4.MAX_POWER = 1e15 -- the target curve flattens out here (far past any record) instead of overflowing
P4.RING_MEMO_SEEDS = 64 -- the per-seed history kept for the "never drops" rule (oldest seed forgotten first)
P4.baseCache = {} -- "petId|level|tier" -> TeamPower of that single plain pet
P4.ringMemo = {} -- [seed] = { [round] = champion power } for the rounds before the saturation round
P4.ringOrder = {}

-- a whole round 1..MaxRound (junk -> 1)
function P4.round(r)
	r = tonumber(r)
	if not finite(r) or r < 1 then
		return 1
	end
	r = floor(r)
	local top = num(BattleCatalog.Ring.MaxRound, 100000)
	if r > top then
		return top
	end
	return r
end

-- a whole seed 0..RING_M - 2 (junk -> 1)
function P4.seed(seed)
	local s = tonumber(seed)
	if not finite(s) then
		s = 1
	end
	return floor(math.abs(s)) % (P4.RING_M - 1)
end

-- rarity -> { petId... } in catalog order, never the EventOnly raid pets (cached once PetCatalog is there)
function P4.pools()
	if P4.poolCache then
		return P4.poolCache
	end
	local pools = {}
	local pc = petCatalog()
	if pc and type(pc.Pets) == "table" then
		for _, def in ipairs(pc.Pets) do
			if def.EventOnly ~= true and type(def.Id) == "string" and type(def.Rarity) == "string" then
				pools[def.Rarity] = pools[def.Rarity] or {}
				table.insert(pools[def.Rarity], def.Id)
			end
		end
		P4.poolCache = pools
	end
	return pools
end

function P4.band(r)
	local bands = BattleCatalog.Ring.Bands
	for _, b in ipairs(bands) do
		if r >= num(b.From, 1) and (b.To == nil or r <= b.To) then
			return b.Rarities
		end
	end
	return bands[#bands].Rarities
end

-- the round's species, drawn with the run seed (Lehmer steps, exact in doubles: every value stays below 2^53)
function P4.pickSpecies(r, s)
	local M = P4.RING_M
	local x = ((s % M) * 1000 + r) % M
	x = (x * 7919 + 104729) % M
	if x == 0 then
		x = 1
	end
	local function nextInt(n)
		x = (x * 48271) % M
		return 1 + (x % n)
	end
	local pools = P4.pools()
	local rarities = P4.band(r)
	local list = pools[rarities[nextInt(#rarities)]]
	if not list or #list == 0 then
		for _, rarity in ipairs(rarities) do
			if pools[rarity] and #pools[rarity] > 0 then
				list = pools[rarity]
				break
			end
		end
		list = list or pools.Common
	end
	if not list or #list == 0 then
		return nil
	end
	return list[nextInt(#list)]
end

function P4.basePower(petId, level, tier)
	local key = petId .. "|" .. level .. "|" .. tier
	local p = P4.baseCache[key]
	if p == nil then
		p = BattleCatalog.TeamPower({ { PetId = petId, Level = level, Tier = tier } })
		P4.baseCache[key] = p
	end
	return p
end

-- a champion entry's TeamPower: the plain pet's, x the mini-boss factor, x Handicap, x Boost
function P4.power(e)
	local p = P4.basePower(e.PetId, e.Level, e.Tier)
	if e.Boss then
		local mb = BattleCatalog.MiniBoss
		p = p * sqrt(mb.Hp * mb.Power)
	end
	if e.Handicap then
		p = p * e.Handicap
	end
	if e.Boost then
		p = p * e.Boost
	end
	return p
end

function BattleCatalog.RingTarget(round)
	local R = BattleCatalog.Ring
	local r = P4.round(round)
	local easy = #R.EasyRounds
	if r <= easy then
		return 0
	end
	local p = R.FirstPower * R.Growth ^ (r - easy - 1)
	if r % R.BossEvery == 0 then
		p = p * R.BossBump
	end
	if not finite(p) or p > P4.MAX_POWER then
		return P4.MAX_POWER
	end
	return p
end

-- one round's champion entry for a goal: entry, goal, power (see the solve order above)
function P4.solve(r, s, prevPower)
	local R = BattleCatalog.Ring
	local easy = R.EasyRounds[r]
	if easy then
		local e = { PetId = easy.PetId, Level = 1, Tier = "Normal", Handicap = easy.Handicap }
		return e, 0, P4.power(e)
	end
	local goal = BattleCatalog.RingTarget(r)
	if prevPower and prevPower > goal then
		goal = prevPower
	end
	local petId = P4.pickSpecies(r, s)
	if not petId then
		return nil, goal, goal
	end
	local bossRound = (r % R.BossEvery == 0)
	local topLevel = max(1, floor(num(R.ChampionMaxLevel, 50)))
	local function at(level, tier, boss)
		return { PetId = petId, Level = level, Tier = tier, Boss = boss or nil }
	end
	-- a level-1 pet (the mini-boss form on boss rounds) above the goal is handicapped down to it
	local first = at(1, "Normal", bossRound)
	local p1 = P4.power(first)
	if p1 > goal then
		local h = goal / p1
		if h < R.MinHandicap then
			first.Handicap = R.MinHandicap
			return first, goal, p1 * R.MinHandicap
		end
		first.Handicap = h
		return first, goal, goal
	end
	-- the lowest level that reaches the goal: the plain pet, then the mini-boss form Normal -> Golden -> Rainbow
	local forms = { { false, "Normal" }, { true, "Normal" }, { true, "Golden" }, { true, "Rainbow" } }
	for i, form in ipairs(forms) do
		if (i > 1 or not bossRound) and P4.power(at(topLevel, form[2], form[1])) >= goal then
			local lo, hi = 1, topLevel
			while lo < hi do
				local mid = floor((lo + hi) / 2)
				if P4.power(at(mid, form[2], form[1])) >= goal then
					hi = mid
				else
					lo = mid + 1
				end
			end
			local e = at(lo, form[2], form[1])
			return e, goal, P4.power(e)
		end
	end
	-- the level-ChampionMaxLevel Rainbow mini-boss, x Boost: endless
	local top = at(topLevel, "Rainbow", true)
	local tp = P4.power(top)
	if tp > 0 and goal > tp then
		top.Boost = goal / tp
		return top, goal, goal
	end
	return top, goal, tp
end

-- the per-seed history; reset whenever a Ring knob changes (the sim tunes them)
function P4.memoFor(s)
	local R = BattleCatalog.Ring
	local sig = table.concat({ tostring(R.FirstPower), tostring(R.Growth), tostring(R.BossEvery), tostring(R.BossBump), tostring(R.MinHandicap), tostring(R.ChampionMaxLevel), tostring(#R.EasyRounds), tostring(#R.Bands) }, "|")
	if sig ~= P4.ringSig then
		P4.ringSig = sig
		P4.ringMemo = {}
		P4.ringOrder = {}
		P4.ringSat = nil
	end
	local m = P4.ringMemo[s]
	if not m then
		m = {}
		P4.ringMemo[s] = m
		P4.ringOrder[#P4.ringOrder + 1] = s
		if #P4.ringOrder > P4.RING_MEMO_SEEDS then
			P4.ringMemo[table.remove(P4.ringOrder, 1)] = nil
		end
	end
	return m
end

-- the saturation round: from here on the target is above every species' level-ChampionMaxLevel Rainbow mini-boss, so
-- every champion takes a Boost and its power is exactly max(target, the power before the saturation round)
function P4.saturation()
	if P4.ringSat then
		return P4.ringSat
	end
	local R = BattleCatalog.Ring
	local topLevel = max(1, floor(num(R.ChampionMaxLevel, 50)))
	local mb = BattleCatalog.MiniBoss
	local maxTop = 0
	for _, list in pairs(P4.pools()) do
		for _, id in ipairs(list) do
			maxTop = max(maxTop, P4.basePower(id, topLevel, "Rainbow") * sqrt(mb.Hp * mb.Power))
		end
	end
	local r = #R.EasyRounds + 1
	local top = num(R.MaxRound, 100000)
	while r < top and BattleCatalog.RingTarget(r) < maxTop do
		r = r + 1
	end
	P4.ringSat = r
	return r
end

-- the champion power of round k < saturation for seed s (memoized, computed forward from the last known round)
function P4.history(k, s, memo)
	if k < 1 then
		return nil
	end
	if memo[k] then
		return memo[k]
	end
	local start = k
	while start > 1 and not memo[start - 1] do
		start = start - 1
	end
	local prev = (start > 1) and memo[start - 1] or nil
	for j = start, k do
		local _, _, p = P4.solve(j, s, prev)
		memo[j] = p
		prev = p
	end
	return memo[k]
end

-- entry, goal, power of round r for seed s, with the "never drops" rule
function P4.ring(r, s)
	local memo = P4.memoFor(s)
	local sat = P4.saturation()
	if r >= sat then
		return P4.solve(r, s, P4.history(sat - 1, s, memo))
	end
	return P4.solve(r, s, P4.history(r - 1, s, memo))
end

-- A BattleSim team spec for the champion of `round` in the run with `seed` (fresh tables; pure and deterministic)
function BattleCatalog.ChampionTeam(round, seed)
	local r = P4.round(round)
	local s = P4.seed(seed)
	local entry, goal, power = P4.ring(r, s)
	if not entry then
		return nil
	end
	local pc = petCatalog()
	local def = pc and pc.Get and pc.Get(entry.PetId)
	local name = (def and (def.DisplayName or def.Name)) or entry.PetId
	local pet = {
		PetId = entry.PetId,
		Key = entry.PetId,
		Level = entry.Level,
		Tier = entry.Tier,
		Slot = 1,
		Boss = entry.Boss,
		Handicap = entry.Handicap,
		Boost = entry.Boost,
		Crowned = true,
	}
	return {
		Owner = "npc",
		Side = 2,
		Npc = true,
		Name = "Champion " .. name,
		Round = r,
		Seed = s,
		TargetPower = goal,
		Power = power,
		Champion = {
			PetId = entry.PetId,
			Level = entry.Level,
			Tier = entry.Tier,
			Boss = entry.Boss == true,
			Boost = entry.Boost,
			Handicap = entry.Handicap,
			Name = name,
			Power = power,
		},
		Pets = { pet },
	}
end

-- the champion's power of a round (the same number as ChampionTeam(round, seed).Power)
function BattleCatalog.RingPower(round, seed)
	local _, _, power = P4.ring(P4.round(round), P4.seed(seed))
	return power
end

function BattleCatalog.RingSeconds(round)
	local R = BattleCatalog.Ring
	return min(R.SecondsMax, R.SecondsBase + R.SecondsPerRound * P4.round(round))
end

-- The rewards of one round WON: Cash = max(floor, seconds of the climber's own garden income) (x RecordMult on a new
-- record), Xp per team pet, Tokens = BossTokens for the first win of a boss round (= a new record on a BossEvery-th
-- round). incomePerSecond: TycoonService.IncomePerSecond(player) (0 without garden pets: the floor only).
function BattleCatalog.RingRewards(round, incomePerSecond, isRecord)
	local R = BattleCatalog.Ring
	local r = P4.round(round)
	local ips = tonumber(incomePerSecond)
	if not finite(ips) or ips < 0 then
		ips = 0
	end
	local record = isRecord == true
	local seconds = BattleCatalog.RingSeconds(r)
	local cashFloor = floor(R.CashFloorBase + R.CashFloorPerRound * r)
	local cash = max(cashFloor, floor(ips * seconds))
	if record then
		cash = cash * R.RecordMult
	end
	local boss = (r % R.BossEvery == 0)
	return {
		Cash = cash,
		Xp = R.XpBase + R.XpPerRound * r,
		Tokens = (record and boss) and R.BossTokens or 0,
		Seconds = seconds,
		Floor = cashFloor,
		Record = record,
		Boss = boss,
	}
end

----------------------------------------------------------------------
-- The boss roster. Boss damage is a fraction of the participants' pet HP (DamageBasis blends each victim's own
-- max HP with the raid's average) so a raid stays about dodging telegraphs at every progression stage; boss HP
-- lasts HpPerPlayer seconds of every participating team's expected DPS (BossHp), so 1 / 3 / 8 players all
-- finish in about the same time. Telegraph shapes: Circle { Radius } at a target point, Line { Width, Length }
-- from the boss through a target point, cut short a little past that point (BattleSim.LineOvershoot), so a team
-- running home leaves it (Count > 1 fans several lines Spread degrees apart). Target: "Cluster" (where most pets
-- stand), "Random" (a random pet), "Nearest", "Self" (centred on the boss). Every Telegraph lasts >= 2.2 s: the
-- client's fill ends at the DODGE DEADLINE (render delay + ping + the run out), so a shorter warning would read as
-- "too late" while it still looks half full.
----------------------------------------------------------------------
BattleCatalog.BossRules = {
	DamageBasis = { Own = 0.6, Average = 0.4 }, -- boss hit = fraction x (Own x victim MaxHp + Average x raid average MaxHp)
	MinHp = 600,
	MinionHp = 0.7, -- minion MaxHp = this x the raid's average pet MaxHp
	MinionDamage = 0.035, -- minion hit = this x the average pet MaxHp
	-- the head count behind GroupExponent / DamageGroup is WEIGHTED: a team counts min(1, its DPS / the strongest team's
	-- DPS), so joiners who bring nothing (idle alts with level-1 pets) do not inflate the boss for everyone else
	GroupExponent = 0.25, -- boss HP x teams ^ GroupExponent: big groups spread the boss's attention and dodge less (3 teams x1.32, 8 teams x1.68)
	DamageGroup = { Min = 0.55, FullAt = 8 }, -- boss (and minion) damage x Min for one team, rising to x1 at FullAt teams
	MinionInterval = 1.4,
	MinionLevelOf = "average", -- minions are built from a catalog pet at the raid's average pet level (looks only)
	Enrage = { Damage = 2, Cooldown = 0.7 },
	WaveMin = 2,
	WaveMax = 8,
	CirclesPerTeams = 2, -- a Circle attack lands one circle per 2 player teams (different clusters) ...
	MaxCircles = 4, -- ... up to this many
	TelegraphShapes = { "Circle", "Line" },
	Targets = { "Cluster", "Random", "Nearest", "Self" },
}

local function attack(id, name, shape, fields)
	local a = { Id = id, Name = name, Shape = shape }
	for k, v in pairs(fields) do
		a[k] = v
	end
	return a
end

BattleCatalog.Bosses = {
	storm_titan = {
		Id = "storm_titan",
		Name = "Storm Titan",
		Element = "Storm",
		Blurb = "A thunderhead given arms. Earth pets ground its lightning.",
		HpPerPlayer = 100, -- seconds of each team's expected DPS (dodging telegraphs costs about a third of the uptime)
		Radius = 7,
		Scale = 1,
		Basic = { Name = "Zap", Interval = 2.4, Damage = 0.05, Range = 16 },
		Attacks = {
			attack("slam", "Thunder Slam", "Circle", { Radius = 7, Telegraph = 2.2, Cooldown = 18, Damage = 0.2, Target = "Cluster", First = 8 }),
			attack("chain", "Chain Lightning", "Line", { Width = 4, Length = 48, Telegraph = 2.2, Cooldown = 22, Damage = 0.35, Target = "Random", First = 17 }),
		},
		MinionPet = "storm_tabby",
		Minions = { Name = "Spark Tabby", Waves = { { At = 0.7, PerPlayer = 0.5 }, { At = 0.35, PerPlayer = 0.75 } } },
		EnrageAt = 240,
		TimeLimit = 330,
	},
	lava_golem = {
		Id = "lava_golem",
		Name = "Lava Golem",
		Element = "Flame",
		Blurb = "A walking volcano. Water pets cool it down.",
		HpPerPlayer = 85, -- its Eruption sends every melee pet running, so its HP is a little lower
		Radius = 8,
		Scale = 1,
		Basic = { Name = "Magma Fist", Interval = 2.8, Damage = 0.05, Range = 12 },
		Attacks = {
			attack("pool", "Magma Pool", "Circle", { Radius = 7, Telegraph = 2.2, Cooldown = 18, Damage = 0.15, Target = "Cluster", Linger = 5, LingerDamage = 0.03, First = 8 }),
			attack("eruption", "Eruption", "Circle", { Radius = 15, Telegraph = 2.4, Cooldown = 30, Damage = 0.25, Target = "Self", First = 18 }),
		},
		MinionPet = "maple_fox",
		Minions = { Name = "Cinder Fox", Waves = { { At = 0.65, PerPlayer = 0.5 }, { At = 0.3, PerPlayer = 0.75 } } },
		EnrageAt = 240,
		TimeLimit = 330,
	},
	frost_wyrm = {
		Id = "frost_wyrm",
		Name = "Frost Wyrm",
		Element = "Frost",
		Blurb = "A serpent of living ice. Flame pets melt its armour.",
		HpPerPlayer = 100,
		Radius = 7,
		Scale = 1,
		Basic = { Name = "Ice Spit", Interval = 2.2, Damage = 0.045, Range = 18 },
		Attacks = {
			attack("breath", "Frost Breath", "Line", { Width = 5, Length = 44, Telegraph = 2.2, Cooldown = 20, Damage = 0.3, Target = "Random", Freeze = 2.0, First = 8 }),
			attack("blizzard", "Blizzard", "Circle", { Radius = 8, Telegraph = 2.2, Cooldown = 22, Damage = 0.15, Target = "Cluster", Freeze = 2.5, First = 18 }),
		},
		MinionPet = "frostling_penguin",
		Minions = { Name = "Ice Shard", Waves = { { At = 0.7, PerPlayer = 0.5 }, { At = 0.35, PerPlayer = 0.75 } } },
		EnrageAt = 240,
		TimeLimit = 330,
	},
	shadow_hydra = {
		Id = "shadow_hydra",
		Name = "Shadow Hydra",
		Element = "Shadow",
		Blurb = "Three heads, one grudge. Celestial pets shine through its dark.",
		HpPerPlayer = 100,
		Radius = 7,
		Scale = 1,
		Basic = { Name = "Shadow Bite", Interval = 1.8, Damage = 0.04, Range = 14 },
		Attacks = {
			attack("fangs", "Void Fangs", "Line", { Width = 4, Length = 44, Count = 3, Spread = 30, Telegraph = 2.2, Cooldown = 20, Damage = 0.3, Target = "Random", First = 8 }),
			attack("pulse", "Shadow Pulse", "Circle", { Radius = 8, Telegraph = 2.2, Cooldown = 20, Damage = 0.2, Target = "Cluster", First = 18 }),
		},
		MinionPet = "twilight_dragon",
		Minions = { Name = "Shade Hatchling", Waves = { { At = 0.75, PerPlayer = 0.5 }, { At = 0.5, PerPlayer = 0.5 }, { At = 0.25, PerPlayer = 0.75 } } },
		EnrageAt = 240,
		TimeLimit = 330,
	},
}
BattleCatalog.BossOrder = { "storm_titan", "lava_golem", "frost_wyrm", "shadow_hydra" }

function BattleCatalog.NextBoss(index)
	local order = BattleCatalog.BossOrder
	local i = tonumber(index) or 1
	i = floor(i)
	local n = #order
	i = ((i - 1) % n) + 1
	if i < 1 then
		i = i + n
	end
	return order[i]
end

-- The weighted head count of a list of team DPS values: every team counts min(1, dps / the strongest dps), so eight
-- equal teams count 8 and one real team with seven idle alts counts a little over 1.
function BattleCatalog.WeightedTeams(dpsList)
	local top = 0
	for _, dps in ipairs(type(dpsList) == "table" and dpsList or {}) do
		if finite(dps) and dps > top then
			top = dps
		end
	end
	local n = 0
	for _, dps in ipairs(type(dpsList) == "table" and dpsList or {}) do
		if top > 0 and finite(dps) and dps > 0 then
			n = n + min(1, dps / top)
		end
	end
	return n
end

-- Boss HP for a list of team specs (each { Pets = {...} }): HpPerPlayer seconds of every team's expected DPS, each
-- team's share weighted like the head count (min(1, dps / the strongest dps): a team that brings nothing adds nothing).
-- Returns the total (x GroupFactor(weighted team count), at least BossRules.MinHp) and the list of each team's share
-- (BattleSim recomputes the whole figure when players join or leave).
function BattleCatalog.BossHp(bossId, teams)
	local boss = BattleCatalog.Bosses[bossId]
	local seconds = boss and boss.HpPerPlayer or 150
	local dpsList = {}
	local top = 0
	for i, team in ipairs(type(teams) == "table" and teams or {}) do
		dpsList[i] = BattleCatalog.ExpectedDps(team)
		top = max(top, dpsList[i])
	end
	local total = 0
	local shares = {}
	for i, dps in ipairs(dpsList) do
		local weight = (top > 0) and min(1, dps / top) or 0
		shares[i] = dps * seconds * weight
		total = total + shares[i]
	end
	total = total * BattleCatalog.GroupFactor(BattleCatalog.WeightedTeams(dpsList))
	local minHp = BattleCatalog.BossRules.MinHp
	if total < minHp then
		total = minHp
	end
	return floor(total + 0.5), shares
end

-- teams ^ GroupExponent: the multiplier on the summed shares for a raid of `teams` (weighted, may be fractional) teams
function BattleCatalog.GroupFactor(teams)
	local n = max(1, num(teams, 1))
	return n ^ (BattleCatalog.BossRules.GroupExponent or 0)
end

----------------------------------------------------------------------
-- Event schedule + raid rewards
----------------------------------------------------------------------
BattleCatalog.Events = {
	Schedule = {
		{ Kind = "BossRaid", EveryMinutes = 20, AnnounceSeconds = 120, DurationSeconds = 330 },
		{ Kind = "DoubleRewards", EveryMinutes = 180, AnnounceSeconds = 120, DurationSeconds = 3600 },
	},
	FirstAfterSeconds = 300, -- the first raid of a fresh server
	DoubleRewardsMultiplier = 2,
	JoinWindowSeconds = 60, -- players may join a raid during its first minute
}

BattleCatalog.Raid = {
	-- by damage share (fraction of the boss's total HP a player dealt); the first tier that fits wins
	Tiers = {
		{ Id = "Gold", MinShare = 0.25, Tokens = 500, Xp = 400, Gems = 10, GemChance = 0.25, EventPetChance = 0.05 },
		{ Id = "Silver", MinShare = 0.10, Tokens = 300, Xp = 250, Gems = 5, GemChance = 0.15, EventPetChance = 0.03 },
		{ Id = "Bronze", MinShare = 0.02, Tokens = 150, Xp = 120, Gems = 3, GemChance = 0.08, EventPetChance = 0.015 },
		{ Id = "Helper", MinShare = 0, Tokens = 60, Xp = 50, Gems = 0, GemChance = 0, EventPetChance = 0.005 }, -- any hit
	},
	-- everyone who fights gets rewarded (the player's design: "everyone gets in this fight for the reward"): a raider
	-- whose pets hit the boss at all earns at least Helper (Loss when the raid fails); only a share of 0 (an idle joiner
	-- whose pets never hit it) earns nothing. Joiners who deal little cannot inflate the boss (WeightedTeams).
	MinShare = 0,
	LossTokens = 25, -- everyone who really fought a raid that failed
	LossXp = 20,
}

-- the reward tier for a damage share (0..1): nil for no damage (share 0, or below Raid.MinShare), the Loss tier when
-- the raid failed
function BattleCatalog.RaidTier(share, won)
	local s = tonumber(share) or 0
	if s ~= s or s <= 0 or s < BattleCatalog.Raid.MinShare then
		return nil
	end
	if won == false then
		return { Id = "Loss", MinShare = BattleCatalog.Raid.MinShare, Tokens = BattleCatalog.Raid.LossTokens, Xp = BattleCatalog.Raid.LossXp, Gems = 0, GemChance = 0, EventPetChance = 0 }
	end
	local tiers = BattleCatalog.Raid.Tiers
	for _, tier in ipairs(tiers) do
		if s >= tier.MinShare then
			return tier
		end
	end
	return tiers[#tiers]
end

-- Catalog pets marked EventOnly = true (the events agent adds them): raid exclusive drops
function BattleCatalog.EventPets()
	local out = {}
	local pc = petCatalog()
	if pc and type(pc.Pets) == "table" then
		for _, def in ipairs(pc.Pets) do
			if def.EventOnly == true then
				table.insert(out, def.Id)
			end
		end
	end
	return out
end

----------------------------------------------------------------------
-- PvP trophies
----------------------------------------------------------------------
BattleCatalog.Trophies = {
	Win = 20,
	Loss = -10,
	Draw = 0,
	Forfeit = -10, -- a leaver / forfeit counts as a loss
	Floor = 0,
	Tokens = { Win = 40, Loss = 10, Draw = 15 },
	Xp = { Win = 60, Loss = 25 }, -- pet XP per team pet
}

----------------------------------------------------------------------
-- Self-check
----------------------------------------------------------------------
function BattleCatalog.Validate()
	local problems = {}
	local function bad(msg)
		table.insert(problems, msg)
	end
	local pc = petCatalog()
	-- profiles for every species
	if pc and type(pc.Species) == "table" then
		for _, species in ipairs(pc.Species) do
			if not BattleCatalog.Profiles[species] then
				bad("no combat profile for species " .. tostring(species))
			end
		end
	end
	for species, profile in pairs(BattleCatalog.Profiles) do
		if profile.Attack ~= "Melee" and profile.Attack ~= "Ranged" then
			bad(species .. ": Attack must be Melee or Ranged")
		end
		for _, key in ipairs({ "Range", "MoveSpeed", "Interval", "HitRadius", "DamageMult" }) do
			if not finite(profile[key]) or profile[key] <= 0 then
				bad(species .. ": " .. key .. " must be a positive number")
			end
		end
	end
	-- specials for every kind
	local kinds = (pc and pc.SpecialKinds) or BattleCatalog.SpecialKinds
	for _, kind in ipairs(kinds) do
		local s = BattleCatalog.Specials[kind]
		if type(s) ~= "table" then
			bad("no special effect for kind " .. tostring(kind))
		elseif type(s.Name) ~= "string" or type(s.Text) ~= "string" or not finite(s.Scale) then
			bad("special " .. kind .. " needs Name, Text and Scale")
		end
	end
	-- trials: 30 levels, pets exist, mini-boss every 5 levels, power never drops, rewards grow
	local trials = BattleCatalog.Trials
	if #trials ~= BattleCatalog.TrialCount then
		bad("expected " .. BattleCatalog.TrialCount .. " trials, got " .. #trials)
	end
	local lastPower = 0
	local lastTokens = 0
	for level = 1, #trials do
		local t = trials[level]
		if t.Level ~= level then
			bad("trial " .. level .. " has Level " .. tostring(t.Level))
		end
		if type(t.Name) ~= "string" or t.Name == "" then
			bad("trial " .. level .. " has no name")
		end
		if (level % 5 == 0) ~= (t.MiniBoss == true) then
			bad("trial " .. level .. ": MiniBoss must be true exactly every 5 levels")
		end
		if t.MiniBoss and not t.Boss then
			bad("trial " .. level .. ": a mini-boss level names no Boss pet")
		end
		if #t.Team < (level == 1 and 1 or 3) or #t.Team > BattleCatalog.MaxTeamSize then
			bad("trial " .. level .. ": team of " .. #t.Team .. " pets")
		end
		local bossSeen = false
		for _, entry in ipairs(t.Team) do
			if pc and pc.Get and not pc.Get(entry.PetId) then
				bad("trial " .. level .. ": unknown pet " .. tostring(entry.PetId))
			end
			if entry.Boss then
				bossSeen = true
			end
		end
		if t.Boss and not bossSeen then
			bad("trial " .. level .. ": Boss pet " .. tostring(t.Boss) .. " is not in the team")
		end
		if not finite(t.RecommendedPower) or t.RecommendedPower < lastPower then
			bad("trial " .. level .. ": RecommendedPower " .. tostring(t.RecommendedPower) .. " drops below level " .. (level - 1))
		end
		lastPower = t.RecommendedPower
		if t.RecommendedPower < t.TargetPower * 0.9 then
			bad("trial " .. level .. ": the roster cannot reach the target power " .. t.TargetPower .. " (got " .. t.RecommendedPower .. ")")
		end
		local r = t.Rewards
		if type(r) ~= "table" or not finite(r.Tokens) or r.Tokens <= lastTokens or type(r.FirstClear) ~= "table" then
			bad("trial " .. level .. ": rewards must grow with the level")
		else
			lastTokens = r.Tokens
			if t.MiniBoss and (r.FirstClear.Gems or 0) <= 0 then
				bad("trial " .. level .. ": a mini-boss first clear pays no Gems")
			end
		end
	end
	-- bosses
	local validElements = {}
	for _, e in ipairs((type(Config.Elements) == "table" and Config.Elements.Order) or {}) do
		validElements[e] = true
	end
	for _, id in ipairs(BattleCatalog.BossOrder) do
		local b = BattleCatalog.Bosses[id]
		if not b then
			bad("BossOrder names unknown boss " .. tostring(id))
		else
			if b.Id ~= id then
				bad("boss " .. id .. " has Id " .. tostring(b.Id))
			end
			if not validElements[b.Element] then
				bad("boss " .. id .. ": Element " .. tostring(b.Element) .. " is not in Config.Elements.Order")
			end
			if not finite(b.HpPerPlayer) or b.HpPerPlayer <= 0 then
				bad("boss " .. id .. ": HpPerPlayer must be positive")
			end
			if type(b.Attacks) ~= "table" or #b.Attacks < 1 then
				bad("boss " .. id .. ": needs attacks")
			else
				for _, a in ipairs(b.Attacks) do
					if a.Shape ~= "Circle" and a.Shape ~= "Line" then
						bad("boss " .. id .. " attack " .. tostring(a.Id) .. ": unknown shape " .. tostring(a.Shape))
					end
					if a.Shape == "Circle" and not finite(a.Radius) then
						bad("boss " .. id .. " attack " .. tostring(a.Id) .. ": Circle needs Radius")
					end
					if a.Shape == "Line" and (not finite(a.Width) or not finite(a.Length)) then
						bad("boss " .. id .. " attack " .. tostring(a.Id) .. ": Line needs Width and Length")
					end
					if not finite(a.Telegraph) or a.Telegraph < 1 then
						bad("boss " .. id .. " attack " .. tostring(a.Id) .. ": Telegraph must be >= 1 s (players need time to RETREAT)")
					end
					if not finite(a.Damage) or a.Damage <= 0 or a.Damage > 0.6 then
						bad("boss " .. id .. " attack " .. tostring(a.Id) .. ": Damage must be a fraction in (0, 0.6] (no one-shots)")
					end
					if not finite(a.Cooldown) or a.Cooldown < a.Telegraph then
						bad("boss " .. id .. " attack " .. tostring(a.Id) .. ": Cooldown must cover the Telegraph")
					end
				end
			end
			if type(b.Basic) ~= "table" or not finite(b.Basic.Damage) or b.Basic.Damage > 0.2 then
				bad("boss " .. id .. ": Basic attack damage must be a small fraction")
			end
			if pc and pc.Get and b.MinionPet and not pc.Get(b.MinionPet) then
				bad("boss " .. id .. ": unknown minion pet " .. tostring(b.MinionPet))
			end
			if not finite(b.EnrageAt) or not finite(b.TimeLimit) or b.TimeLimit <= b.EnrageAt then
				bad("boss " .. id .. ": TimeLimit must come after EnrageAt")
			end
		end
	end
	-- raid tiers sorted by share, nothing paid for no damage, trophies floor
	local lastShare = 2
	for _, tier in ipairs(BattleCatalog.Raid.Tiers) do
		if tier.MinShare >= lastShare then
			bad("Raid.Tiers must be sorted by descending MinShare")
		end
		lastShare = tier.MinShare
	end
	if not finite(BattleCatalog.Raid.MinShare) or BattleCatalog.Raid.MinShare < 0 or lastShare < BattleCatalog.Raid.MinShare then
		bad("Raid.MinShare must be 0 or more and no higher than the lowest tier's MinShare (a raider with no damage earns nothing)")
	end
	if BattleCatalog.Trophies.Loss >= 0 or BattleCatalog.Trophies.Win <= 0 or BattleCatalog.Trophies.Floor ~= 0 then
		bad("Trophies: Win must be positive, Loss negative, Floor 0")
	end
	-- Phase 4: training, the loss-XP gate, the Champion Ring
	local TR = BattleCatalog.Training
	if TR.MaxRank ~= 10 or not finite(TR.Defense) or TR.Defense * TR.MaxRank > 0.3 + 1e-9 then
		bad("Training: MaxRank 10 and Defense capped at 30% at rank 10")
	end
	for _, skill in ipairs({ "Speed", "Physique", "Ability", "AbilityMeter", "Defense" }) do
		if not finite(TR[skill]) or TR[skill] <= 0 or TR[skill] > 0.1 then
			bad("Training." .. skill .. " must be a small positive share per rank")
		end
	end
	if #BattleCatalog.TrainingSkills ~= 4 then
		bad("TrainingSkills lists the four skills")
	end
	local TRR = BattleCatalog.TrialRewardRules
	if not finite(TRR.LossShare) or TRR.LossShare <= 0 or TRR.LossShare >= 1 or not finite(TRR.LossMinSeconds) or not finite(TRR.LossMinDamage) then
		bad("TrialRewardRules: LossShare in (0, 1), LossMinSeconds, LossMinDamage")
	end
	local R = BattleCatalog.Ring
	if BattleCatalog.Zones.Ring == nil or BattleCatalog.TimeLimits.Ring ~= R.TimeLimit then
		bad("Ring: Zones.Ring and TimeLimits.Ring = Ring.TimeLimit")
	end
	if not (R.Growth > 1 and R.Growth > R.BossBump and R.BossBump >= 1 and R.FirstPower > 0 and R.MinHandicap > 0 and R.MinHandicap < 1) then
		bad("Ring: Growth > BossBump >= 1 (the target never drops), FirstPower > 0, MinHandicap in (0, 1)")
	end
	for i, easy in ipairs(R.EasyRounds) do
		local def = pc and pc.Get and pc.Get(easy.PetId)
		if pc and (not def or def.Rarity ~= "Common") then
			bad("Ring.EasyRounds[" .. i .. "] must be a Common catalog pet")
		end
		if not finite(easy.Handicap) or easy.Handicap <= 0 or easy.Handicap >= 1 then
			bad("Ring.EasyRounds[" .. i .. "] needs a Handicap in (0, 1)")
		end
	end
	local nextFrom = #R.EasyRounds + 1
	for i, b in ipairs(R.Bands) do
		if b.From ~= nextFrom or type(b.Rarities) ~= "table" or #b.Rarities == 0 then
			bad("Ring.Bands[" .. i .. "] must start at round " .. nextFrom .. " and name rarities")
		end
		nextFrom = (b.To or huge) + 1
		for _, rarity in ipairs(b.Rarities or {}) do
			local pool = P4.pools()[rarity]
			if pc and (not pool or #pool == 0) then
				bad("Ring.Bands[" .. i .. "]: no catalog pets of rarity " .. tostring(rarity))
			end
		end
	end
	if nextFrom ~= huge then
		bad("Ring.Bands: the last band must be open-ended (no To)")
	end
	if pc then
		local last = 0
		local boosted = nil
		for round = 1, 80 do
			local spec = BattleCatalog.ChampionTeam(round, 1)
			if type(spec) ~= "table" or #spec.Pets ~= 1 then
				bad("ChampionTeam(" .. round .. ", 1) must be a one-pet team spec")
				break
			end
			-- rounds 1-3 are the fixed easy rounds; from the first solved round on the power never drops
			if round > #R.EasyRounds and spec.Power < last then
				bad("ChampionTeam: round " .. round .. " is weaker than round " .. (round - 1))
			end
			last = spec.Power
			if spec.Pets[1].Boost and not boosted then
				boosted = round
			end
			if pc.IsEventOnly and pc.IsEventOnly(spec.Pets[1].PetId) then
				bad("ChampionTeam: round " .. round .. " fields an EventOnly pet")
			end
			if spec.Pets[1].Level > R.ChampionMaxLevel then
				bad("ChampionTeam: round " .. round .. " is above ChampionMaxLevel")
			end
		end
		if not boosted then
			bad("ChampionTeam: no Boost by round 80 (the ladder must never end)")
		end
	end
	local rw = BattleCatalog.RingRewards(1, 0, false)
	if rw.Cash ~= R.CashFloorBase + R.CashFloorPerRound or rw.Xp ~= R.XpBase + R.XpPerRound or rw.Tokens ~= 0 then
		bad("RingRewards(1, 0, false) must pay the floor Cash and round-1 XP")
	end
	return #problems == 0, problems
end

return BattleCatalog
