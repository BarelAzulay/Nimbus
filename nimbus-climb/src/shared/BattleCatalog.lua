-- BattleCatalog: every number of the pet battles (ARCHITECTURE_V3.md "Phase 5 build contract" 4.2 / 5.1 on top of the
-- Phase 3 / 4 data): species combat profiles, the damage formula constants, the special effects per Special.Kind, the
-- FIGHTER kit (Phase 5: the player's character is the fighter's body, two helpers press buffs from the bench), the
-- element attacks and helper buffs, roles (Support = Economy pets), team synergy, the Champion Ring ladder, the boss
-- roster, the event schedule, raid reward tiers, PvP trophies and the Dungeon (12 floors). Pure data + pure functions:
-- no Instances, no services, no yields; safe on the server and the client. Plain Lua 5.1-compatible syntax only.
--
-- BALANCE: tuned with tools/sim_battle.lua (lupa, see tools/README.md): Support DPS ratio ~0.7, mirror duels 40-60%
-- with no timeouts, raids 100-240 s for 1 / 4 / 8 / 16 fighters, the no-heal Ring stage medians (S1 13 .. S10 51),
-- the dungeon ladder (floor 1 for any single level-1 pet, S10 >= floor 10). Change a number -> re-run the sim; the
-- smoke scenarios (tools/smoke_p5_battlecore.lua) check the basics.
--
-- Stat sources: BattleStatsOf(subject, level, tier, stage), the battle-only path (2026-10-31: level beats rarity), scales
-- Power / Health by BattleStats.RarityScale, BattleLevelFactor(level, stage) and tier. PetCatalog.GetStats stays the garden's
-- (coins, Speed and the other non-battle numbers) and is never patched.
-- The Speed stat is the BASE value (species tempo rating): it sets the attack tempo and the NPC move speed. Damage =
-- Power x Roles.Power x Damage.DamageScale x profile DamageMult x element x (1 +- Variance) x synergy; HP = Health x
-- Roles.Health x Damage.HpScale.
--
-- API (the contract; 4.2 / 5.1):
--   BattleCatalog.Profiles[species] / ProfileOf(def|species)       { Attack = "Melee"|"Ranged", Range, MoveSpeed, Interval, HitRadius, DamageMult }
--   BattleCatalog.Damage                                           HpScale 2.6, DamageScale 0.6, Variance 0.2, Crit, MinHit, MaxHit (duels 0.6),
--                                                                  DoubleKoByDamage { Duel }, Meter* (NPC units), SpecialDpsShare ... (no Overtime, no Retreat*)
--   BattleCatalog.MeterStart(entry, npc, wave) -> lo, hi           a unit's start meter range: players MeterStart 20-50, NPC units NpcMeterStart
--                                                                  45-75, the Ring champion (entry.MeterStart) and dungeon waves 2+ LateMeterStart 80
--   BattleCatalog.Specials[Kind]                                   { Name, Role, Text, Scale, ... } for Blast, Heal, Shield, Storm, Pounce, Freeze, Beam,
--                                                                  Rally (fighter damage +35% 8 s), Haste (attack + move speed +35% 8 s); SpecialKinds (9)
--   BattleCatalog.Roles = { Combat = { Power 1, Health 1, Name "Fighter" }, Support = { Power 2.6, Health 1.5, Name "Support" } }
--   BattleCatalog.RoleOf(def|petId|key) -> "Combat" | "Support"    (Support when def.Role == "Economy")
--   BattleCatalog.Fighter                                          the kit: AttackSlack 3.0, AttackTolerance 0.85, AutoRepeat false, ElementCooldown 7, ElementMult 2.4,
--                                                                  ElementRange 14, SpecialMeterMax 100, MeterPerSecond 6, MeterOnHit 4, MeterOnHurt 2,
--                                                                  DashSeconds 0.35, DashCooldown 2.5, DashIFrames 0.35, SwapCooldown 10, SwapCastSeconds 0.6,
--                                                                  BenchRegenPerSecond 0 (no passive heal in combat), DownAutoSwap, HelperCooldown 15,
--                                                                  SupportCooldown 12, Windup 0.45, ArriveSeconds 1.2 (a spawned enemy's entrance),
--                                                                  KitFactor 1.5, HelperWeight 0.35, Lives 3, WalkMult 1.15, WalkMin 12, WalkMax 20, RunMult 1.3,
--                                                                  MoveSlack 1.25, Leash 10, LeashSeconds 3, ParryWindow 0.25, ParryStagger
--                                                                  0.4, ParryMeter 8, ParryBossGap 3, CheerBoost 0.05, CheerSeconds 5, CheerCooldown 20
--                                                                  (wave 6: a timed Dash parries; Cheer up!; no Engage*
--                                                                  numbers: the pet fights any enemy in the fight area whatever the character
--                                                                  does; BattleSim "ENGAGE")
--   BattleCatalog.Fighter.WalkOf(moveSpeed) -> walk (12..20); Fighter.RunOf(walk) -> walk x RunMult; Fighter.SpeedsOf(moveSpeed) -> walk, run
--   BattleCatalog.ElementAttacks[element]                          { Name, Shape = "Cone"|"Circle"|"Line", Angle, Length, Radius, Width, Push, Burn, Slow, Leech,
--                                                                  Stun, MeterGain, Weaken } one per Config.Elements.Order
--   BattleCatalog.Buffs[kind]                                      { Name, Seconds, Value, Text, Cooldown, Kind, Effect } for Heal / Shield / Rally / Haste (Support,
--                                                                  cooldown 12) and Water / Flame / Frost / Nature / Earth / Storm / Celestial / Shadow (element, 15)
--   BattleCatalog.BuffOf(def|petId|key) -> kind, buff             a helper's button: its Support kind, else its FIRST element's buff
--   BattleCatalog.BattleStats                                     the ONLY tunables of the battle path: RarityScale { Common 1 .. Secret 5 }, Level { Linear, Quadratic, Cubic }
--   BattleCatalog.BattleLevelFactor(level, stage) -> n            1 + (Linear x + Quadratic x^2 + Cubic x^3) x EvolutionBonus[stage], x = level - 1 (level clamped 1..MaxPetLevel, junk stage 0)
--   BattleCatalog.BattleStatsOf(subject, level, tier, stage)      { Power, Health, Speed } | nil: base x RarityScale x BattleLevelFactor x tier (Speed unscaled, no Income);
--                                                                  subject = def | pet id | key, tier nil = its own, stage = the STORED stage
--   BattleCatalog.UnitStats(subject, level, tier, extras)         { MaxHp, Hit, Interval, Dps, MoveSpeed, Walk, Run, Range, Ranged, Radius, SpecialPower,
--                                                                  SpecialFactor, Profile, Species, Elements, Scale, Defense, MeterRate, SpecialBoost, Evo, Boost,
--                                                                  Train, Role, Level, Tier } | nil; extras = { Evo, Train, Boost } (or the entry itself);
--                                                                  stats = BattleStatsOf(def, level, tier, Evo) x Roles (no evoMult: the level formula carries it)
--   BattleCatalog.UnitPower(subject, level, tier, extras) -> n   sqrt(DPS x HP / (1 - Defense)) x PowerScale (a Common level-1 fighter ~ 10)
--   BattleCatalog.TeamPower(list) -> n                            B5: KitFactor x UnitPower(fighter = list[1]) + HelperWeight x (UnitPower(h2) + UnitPower(h3)),
--                                                                  synergy included (a list of 1 is the fighter alone)
--   BattleCatalog.NpcPower(list) -> n                             the sum of the units' powers (Boss / Handicap / Boost applied): enemy waves and champions
--   BattleCatalog.Synergy(list) / SynergyBonus(list)              as before (pairs / trios; Balanced health); SynergyRules.SameElement = { [2], [3] }
--   BattleCatalog.ExpectedDps(team) -> n                          fighter DPS x (1 + SpecialDpsShare) x KitFactor ^ 0.5 (x Fighter.MeleeUptime for a melee
--                                                                  fighter; the bench adds nothing)
--   BattleCatalog.AverageMaxHp(team) -> n                         the fighter's MaxHp (Balanced bonus included)
--   BattleCatalog.LossRules = { LossShare 1/3, LossMinSeconds 20, LossMinDamage 0.2 }; RealLoss(seconds, dealtShare); LossXp(winXp, seconds, dealtShare)
--   BattleCatalog.Ring / ChampionTeam(round, seed) / RingPower / RingSeconds / RingRewards(round, incomePerSecond, isRecord)   (Phase 4;
--       HUD cleanup 2026-10-30: the no-heal climb, champions on the player formula; RingTarget is gone)
--   BattleCatalog.ChampionLevel(round) -> 1..MaxPetLevel   Ring.LevelAnchors (+ BossLevelBump on boss rounds)
--   BattleCatalog.ChampionTier(round) -> "Normal" | "Golden" | "Rainbow"   Ring.TierFrom
--   BattleCatalog.ChampionCount(round) -> 1..3   Ring.Helpers
--   ChampionTeam -> { Owner "npc", Side 2, Npc, Name, Round, Seed, Power = TeamPower(Pets), Champion = { PetId, Level, Tier, Evo,
--       Count, Boss (flag), Name, Power }, Pets = { { PetId, Key, Level, Tier, Evo, Slot, Crowned, MeterStart }... } }
--   BattleCatalog.Bosses / BossOrder / NextBoss / BossHp(bossId, teams) / WeightedTeams / GroupFactor / BossRules (GroupExponent 0.2)
--   BattleCatalog.BaselineDps(bossId) -> n                        the boss HP floor's DPS (HpPerPlayer x it): BossRules.Baseline's ExpectedDps
--   BattleCatalog.Events / Raid / RaidTier(share, won) / EventPets() / Trophies / Duel (PowerGap 2, the quick queue band)
--   BattleCatalog.Zones { Duel, Raid, Ring, Dungeon 44, DungeonBoss 56 x 72 }, TimeLimits { Duel 120, Raid 330, Ring 90, Dungeon 120 (fallback) }, Modes
--   BattleCatalog.Dungeon / DungeonFloors (5.1); DungeonPower(floor, partySize); DungeonWave(floor, room, wave, partySize, seed) ->
--       { Pets = { { PetId, Key, Level, Tier, Slot, Boss, Boost, Handicap, Wild = true }... }, Boss = bool, Power, Target, Floor, Room, Wave };
--       DungeonRewards(floor, room, waves, incomePerSecond, double) -> { Cash, Tokens, Xp }; DungeonFirstClear(floor) -> { Tokens, Gems };
--       DungeonChest(floor, seed) -> { Kind, Amount }
--   BattleCatalog.Validate() -> ok, { problem... }
-- Deleted in Phase 5 (10.5): Trials, TrialCount, TrialCurve, TrialChapters, TrialRewardRules (-> LossRules), TrialTeam, TrialRewards, ChapterOf,
--   Zones.Trial, TimeLimits.Trial, MaxTeamSize 4, SynergyRules.SameElement[4], evoMult, Damage.Retreat* / Overtime.

local Shared = script.Parent
local Config = require(Shared.Config)

local BattleCatalog = {}

local floor, sqrt, max, min, huge, abs = math.floor, math.sqrt, math.max, math.min, math.huge, math.abs

BattleCatalog.Version = 5

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

local function num(v, default)
	if finite(v) then
		return v
	end
	return default
end

local function elementOrder()
	return (type(Config.Elements) == "table" and type(Config.Elements.Order) == "table") and Config.Elements.Order
		or { "Water", "Flame", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }
end

----------------------------------------------------------------------
-- Zones / time limits / modes
----------------------------------------------------------------------
BattleCatalog.Zones = {
	Duel = { X = 44, Z = 44 }, -- a duel ring
	Raid = { X = 96, Z = 96 }, -- the colosseum floor
	Ring = { X = 44, Z = 44 }, -- the Champion Ring pocket (one champion per round)
	Dungeon = { X = 44, Z = 44 }, -- a dungeon wave room
	DungeonBoss = { X = 56, Z = 72 }, -- the boss room (the whole Throne floor: dais and throne inside, so nobody is dropped out there)
}
-- Dungeon 120 is the FALLBACK only: DungeonService always passes TimeLimit from Dungeon.RoomTime / Floor1RoomTime
BattleCatalog.TimeLimits = { Duel = 120, Raid = 330, Ring = 90, Dungeon = 120 }
BattleCatalog.Modes = { "Duel", "Raid", "Ring", "Dungeon" }
BattleCatalog.StepSeconds = 0.1 -- the server simulates at 10 Hz
BattleCatalog.TeamSize = 3 -- a fighter and two helpers (Teams of 3, 4.8)
BattleCatalog.BaseTeamSize = 3

----------------------------------------------------------------------
-- Species combat profiles: melee pets walk up and bite, ranged pets stop at Range and shoot. Interval is the attack
-- cadence (seconds) at Speed 11; HitRadius is the body radius (studs); MoveSpeed in studs/s at Speed 11 (NPC units;
-- a player's fighter walks at Fighter.WalkOf(MoveSpeed)). Melee pets carry DamageMult 1.1 for the walk they must do.
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
	HpScale = 2.6, -- MaxHp = Health (BattleStatsOf x Roles.Health) x HpScale
	DamageScale = 0.6, -- hit = Power x Roles.Power x DamageScale x DamageMult x element x variance x synergy
	Variance = 0.2, -- every hit rolls x(1 - V .. 1 + V)
	Crit = { Chance = 0.1, Mult = 1.5 }, -- plain pet attacks (never specials, bosses or zones) crit; Hit events carry crit = true
	TargetSticky = 1.6, -- an NPC keeps its target while it is within this x the nearest enemy's distance ...
	TargetSpread = 1.35, -- ... else picks at random among the enemies within this x the nearest distance
	ThreatSeconds = 3, -- an NPC chases the fighter that hit it within the last ThreatSeconds (threat), else the nearest
	MinHit = 1, -- a hit never deals less (before shields)
	Rate = { Base = 0.62, PerSpeed = 0.035 }, -- attacks per Interval: Base + PerSpeed x Speed  (7 -> 0.87, 15 -> 1.15)
	Move = { Base = 0.75, PerSpeed = 0.025 }, -- NPC move speed factor: Base + PerSpeed x Speed    (7 -> 0.93, 15 -> 1.13)
	MeterMax = 100, -- NPC units: SPECIAL at MeterMax (the fighter uses Fighter.SpecialMeterMax / MeterPerSecond / MeterOnHit / MeterOnHurt)
	MeterStart = { 20, 50 }, -- a PLAYER team's unit starts a battle with a random meter in this range (first casts spread out)
	-- bug batch 2 (#27): enemy NPCs never cast before they died (a dungeon enemy gained ~30 meter in its ~10 s). NPC
	-- units start higher and charge faster; the fighter keeps its own Fighter.Meter* numbers (only NPC units read these)
	NpcMeterStart = { 45, 75 }, -- an NPC team's unit starts here (BattleCatalog.MeterStart) ...
	LateMeterStart = 80, -- ... the Ring champion and dungeon waves 2+ at this (raid minions stay NoSpecial)
	MeterOnHit = 8, -- NPC meter gained per hit dealt (4 -> 8, #27)
	MeterOnHurt = 2, -- NPC meter gained per hit taken
	MeterPerSecond = 5, -- NPC passive meter gain while alive (2 -> 5, #27: a 20 s fight sees an NPC special)
	CastSeconds = 0.5, -- a unit is Casting (no attacks) this long after a special
	SpecialScale = 1, -- global multiplier on every special effect
	-- a special is powered by its pet's own Power stat (x Roles.Power): effect x (base Power / Reference) ^ Exponent
	SpecialPowerCurve = { Reference = 10, Exponent = 0.5 },
	SeparationRadius = 3.2, -- same-side NPC units closer than this are pushed apart a little
	RetargetSeconds = 0.5, -- how often an NPC re-picks its target
	EngageSlack = 0.6, -- extra studs of reach so moving targets still get hit
	NpcSpecialDelay = { 0.4, 1.4 }, -- NPC teams cast a full special after this random delay (never while Winding)
	KoMeterLoss = true, -- a downed pet's meter is lost
	-- NO ONE-SHOTS in PvP: in a duel a single pet hit never takes more than Share of the victim's max HP
	MaxHit = { Modes = { Duel = true }, Share = 0.6 },
	-- NO DRAWS in PvP: a double knock-out or a duel timeout goes to the side that dealt more damage (forfeits stay a draw)
	DoubleKoByDamage = { Duel = true },
	-- ExpectedDps (boss HP, raid head counts): about this share of a fighter's damage comes from its ELEMENT + SPECIAL
	SpecialDpsShare = 0.3,
	-- NPC statuses (element attacks of the fighter): Slow x move + attack rate, Weaken x damage, Burn ticks
	Slow = 0.6,
	Weaken = 0.85,
	BurnTicks = 3,
}

-- The starting SPECIAL meter range of one unit (#27) -> lo, hi: a player team's unit MeterStart; an NPC unit
-- NpcMeterStart, or LateMeterStart for an entry that carries MeterStart (the Ring champion) or a dungeon wave >= 2.
-- BattleSim rolls lo + (hi - lo) x rand (one roll per unit, so the RNG stream is the same for every case).
function BattleCatalog.MeterStart(entry, npc, wave)
	local D = BattleCatalog.Damage
	local top = num(D.MeterMax, 100)
	local function range(r)
		if type(r) == "table" then
			local lo, hi = num(r[1], 0), num(r[2], 0)
			return max(0, min(top, lo)), max(0, min(top, max(lo, hi)))
		end
		local v = max(0, min(top, num(r, 0)))
		return v, v
	end
	if npc ~= true then
		return range(D.MeterStart)
	end
	if type(entry) == "table" and finite(entry.MeterStart) then
		return range(entry.MeterStart)
	end
	if finite(wave) and wave >= 2 and D.LateMeterStart ~= nil then
		return range(D.LateMeterStart)
	end
	return range(D.NpcMeterStart or D.MeterStart)
end

----------------------------------------------------------------------
-- Special effects per Special.Kind (PetCatalog.SpecialKinds). "Scale" multiplies the pet's scaled Special.Power x
-- DamageScale; Role is for the UI. Every special resets the meter and puts the pet in the Casting state briefly.
-- Phase 5: Heal / Shield / Rally / Haste cast by a FIGHTER act on the fighter itself (the helpers are not on the floor);
-- cast by an NPC pet they act on its wave (Heal / Shield) or itself (Rally / Haste).
----------------------------------------------------------------------
BattleCatalog.Specials = {
	Blast = { Name = "Blast", Role = "Area", Text = "Explodes on the target: damage to every enemy nearby.", Radius = 7, Scale = 0.55 },
	Heal = { Name = "Heal", Role = "Support", Text = "Restores a big chunk of health.", Scale = 0.7, Solo = 3 },
	Shield = { Name = "Shield", Role = "Support", Text = "A shield soaks up damage for a few seconds.", Scale = 0.7, Seconds = 6, Solo = 3 },
	Storm = { Name = "Storm", Role = "Zone", Text = "A storm cloud rains damage on an area for a few seconds. Step out of it!", Radius = 6, Seconds = 4, Scale = 0.9 },
	Pounce = { Name = "Pounce", Role = "Burst", Text = "Dashes to the target for one heavy strike.", Scale = 2.0, Range = 30 },
	Freeze = { Name = "Freeze", Role = "Control", Text = "Freezes enemies around the target: they cannot move or attack.", Radius = 6, Stun = 0.8, Scale = 0.4 },
	Beam = { Name = "Beam", Role = "Line", Text = "Fires a beam through the target that hits every enemy in its line.", Length = 26, Width = 4, Scale = 0.8 },
	Rally = { Name = "Rally", Role = "Support", Text = "A battle cry: +35% damage for 8 seconds.", Scale = 0.5, Seconds = 8, Value = 0.35 },
	Haste = { Name = "Haste", Role = "Support", Text = "A burst of speed: attacks and moves 35% faster for 8 seconds.", Scale = 0.5, Seconds = 8, Value = 0.35 },
}
BattleCatalog.SpecialKinds = { "Blast", "Heal", "Shield", "Storm", "Pounce", "Freeze", "Beam", "Rally", "Haste" }
BattleCatalog.SupportKinds = { "Heal", "Shield", "Rally", "Haste" }

----------------------------------------------------------------------
-- Team synergy (teams of 3): 2 pets of the same element -> +10% Power for them, 3 -> +20%; 3 different elements ->
-- "Balanced", +10% Health for the whole team. Applied to the fighter (and the helpers when they swap in).
----------------------------------------------------------------------
BattleCatalog.SynergyRules = {
	SameElement = { [2] = 0.10, [3] = 0.20 },
	BalancedElements = 3,
	BalancedHealth = 0.10,
}

----------------------------------------------------------------------
-- Roles (3.2): Economy pets fight as Supports (x2.6 Power / x1.5 Health in UnitStats only: measured DPS ratio ~0.7,
-- HP 0.72-0.80 of a Combat pet). Garden income is untouched (PetCatalog.RoleMult).
----------------------------------------------------------------------
BattleCatalog.Roles = {
	Combat = { Power = 1, Health = 1, Name = "Fighter" },
	Support = { Power = 2.6, Health = 1.5, Name = "Support" },
}

----------------------------------------------------------------------
-- The fighter kit (4.2): the player's character is the fighter's body (B1); one small command per button (B2)
----------------------------------------------------------------------
BattleCatalog.Fighter = {
	AttackSlack = 3.0, -- studs of extra reach (the fighter's auto-attack and the old latency margin: run 20 x 0.15 s)
	AttackTolerance = 0.85, -- an attack swings >= Interval x this after the last (the auto-attack re-times it)
	AutoRepeat = false, -- dungeon fixes (4): the fighter AUTO-ATTACKS on the server; ATTACK only directs it (one order per press)
	ElementCooldown = 7,
	ElementMult = 2.4, -- x a basic hit
	ElementRange = 14,
	SpecialMeterMax = 100,
	MeterPerSecond = 6,
	MeterOnHit = 4,
	MeterOnHurt = 2,
	DashSeconds = 0.35,
	DashCooldown = 2.5,
	DashIFrames = 0.35,
	SwapCooldown = 10,
	SwapCastSeconds = 0.6, -- the incoming pet arrives Casting (no free hit in)
	BenchRegenPerSecond = 0, -- dungeon fixes (7): no passive heal in combat (wave gaps too); only a healing pet's skill heals
	BenchRegenCap = 0, -- (the bench regen is gone: a fresh battle per room / round starts at full HP)
	ArriveSeconds = 1.2, -- dungeon fixes (3): a spawned enemy (wave, escort, raid minions) arrives this long: no acting, no hits
	DownAutoSwap = true, -- a downed fighter is replaced by the next alive helper at once (no cooldown) = 3 lives
	HelperCooldown = 15, -- an element buff button
	SupportCooldown = 12, -- a Support pet's buff button
	Windup = 0.45, -- NPC attacks: Winding this long before the hit (the dash i-frames dodge it)
	KitFactor = 1.5, -- TeamPower: a played fighter is worth this x its UnitPower
	MeleeUptime = 0.75, -- ExpectedDps (boss HP): a melee fighter runs out of Eruptions and circles more than a ranged one (sim raids)
	HelperWeight = 0.35, -- TeamPower: each helper's UnitPower counts this much (lives + buffs)
	Lives = 3,
	WalkMult = 1.15, -- walk = clamp(MoveSpeed x WalkMult, WalkMin, WalkMax)
	WalkMin = 12,
	WalkMax = 20,
	RunMult = 1.3, -- run = walk x RunMult (15.6 .. 26 studs/s; the obby run is 27)
	MoveSlack = 1.25, -- the server fighter's cap OVER THE LEGAL RUN SPEED (latency + a cheat margin)
	Leash = 10, -- a gap > Leash for LeashSeconds between the character and the server fighter = out (BattleService)
	LeashSeconds = 3,
	-- wave 6: Dash = a sidestep out of the threat; a Dash pressed within ParryWindow of a timed hit (an NPC wind-up on the pet,
	-- a boss telegraph over it) PARRIES it (BattleSim "Dash")
	ParryWindow = 0.25, -- seconds before the hit lands (<= DashIFrames: the i-frames always cover a parried hit)
	ParryStagger = 0.4, -- the parried attacker: an NPC stunned this long, a boss starts nothing new this long
	ParryMeter = 8, -- special meter per parried threat
	ParryBossGap = 3, -- a boss is staggered at most once per this many seconds (a 16-raid of parries must not perma-lock it)
	-- wave 6: "Cheer up!" (raids and dungeons): the cheering trainer's fighter deals +5% for 5 s, a 20 s cooldown, no stacking
	CheerBoost = 0.05,
	CheerSeconds = 5,
	CheerCooldown = 20,
	-- wave 6 (the engage rule, BattleSim fighterStep): the pet fights any targetable enemy on the floor (the fight area) and
	-- the character's movement never pulls it off: EngageRange / EngageLeash / EngagePull / EngageStillSeconds /
	-- EngageCooldown are gone (the floor is the bound)
}

function BattleCatalog.Fighter.WalkOf(moveSpeed)
	local F = BattleCatalog.Fighter
	local m = num(moveSpeed, 14)
	return max(num(F.WalkMin, 12), min(num(F.WalkMax, 20), m * num(F.WalkMult, 1.15)))
end

function BattleCatalog.Fighter.RunOf(walk)
	return num(walk, 12) * num(BattleCatalog.Fighter.RunMult, 1.3)
end

-- walk, run of a pet's MoveSpeed (UnitStats.MoveSpeed), before speed buffs
function BattleCatalog.Fighter.SpeedsOf(moveSpeed)
	local walk = BattleCatalog.Fighter.WalkOf(moveSpeed)
	return walk, BattleCatalog.Fighter.RunOf(walk)
end

----------------------------------------------------------------------
-- Element attacks (one per Config.Elements.Order): the fighter's ELEMENT button, cast from the SERVER fighter position
-- toward the target / aim / lock; damage = a basic hit x Fighter.ElementMult on every enemy inside the shape
----------------------------------------------------------------------
BattleCatalog.ElementAttacks = {
	Water = { Name = "Tide Burst", Shape = "Cone", Angle = 70, Length = 14, Push = 4 },
	Flame = { Name = "Flare", Shape = "Cone", Angle = 60, Length = 14, Burn = { Seconds = 3, Share = 0.25 } },
	Frost = { Name = "Frostbite", Shape = "Cone", Angle = 70, Length = 14, Slow = { Seconds = 4, Mult = 0.6 } },
	Nature = { Name = "Thorn Lash", Shape = "Cone", Angle = 60, Length = 14, Leech = 0.3 },
	Earth = { Name = "Quake", Shape = "Circle", Radius = 8, Stun = 0.5 },
	Storm = { Name = "Bolt", Shape = "Line", Length = 24, Width = 4 },
	Celestial = { Name = "Radiance", Shape = "Circle", Radius = 8, MeterGain = 15 },
	Shadow = { Name = "Void Rend", Shape = "Cone", Angle = 60, Length = 14, Weaken = { Seconds = 5, Mult = 0.85 } },
}
for element, a in pairs(BattleCatalog.ElementAttacks) do
	a.Element = element
end

----------------------------------------------------------------------
-- Helper buffs: the two helpers' buttons. A Support pet's button is its Support kind (cooldown SupportCooldown 12);
-- any other helper presses its FIRST element's buff (HelperCooldown 15). Values are shares of the FIGHTER's max HP /
-- damage / speed; Ability training multiplies Value by 1 + 0.04 x rank.
--   Effect: "Heal" (now), "Shield" (Value x max HP for Seconds), "Damage" (+Value for Seconds), "Speed" (+Value attack
--   + move for Seconds), "Regen" (Value of max HP per second for Seconds), "Chill" (the fighter's hits slow enemies by
--   Value for Seconds), "Taken" (damage taken x (1 - Value) for Seconds), "AttackSpeed" (+Value for Seconds),
--   "Lifesteal" (Value of damage dealt heals, Seconds); Meter = meter added at once
----------------------------------------------------------------------
BattleCatalog.Buffs = {
	Heal = { Kind = "Heal", Name = "Heal", Effect = "Heal", Seconds = 0, Value = 0.30, Cooldown = 12, Text = "Heals 30% of the fighter's and the other helper's health." },
	Shield = { Kind = "Shield", Name = "Shield", Effect = "Shield", Seconds = 6, Value = 0.35, Cooldown = 12, Text = "A shield of 35% health for 6 seconds." },
	Rally = { Kind = "Rally", Name = "Rally", Effect = "Damage", Seconds = 8, Value = 0.35, Cooldown = 12, Text = "+35% damage for 8 seconds." },
	Haste = { Kind = "Haste", Name = "Haste", Effect = "Speed", Seconds = 8, Value = 0.35, Cooldown = 12, Text = "+35% attack and move speed for 8 seconds." },
	Water = { Kind = "Water", Name = "Tide Mend", Effect = "Regen", Seconds = 5, Value = 0.04, Cooldown = 15, Text = "Heals 4% health per second for 5 seconds." },
	Flame = { Kind = "Flame", Name = "Blaze", Effect = "Damage", Seconds = 8, Value = 0.25, Cooldown = 15, Text = "+25% damage for 8 seconds." },
	Frost = { Kind = "Frost", Name = "Chill", Effect = "Chill", Seconds = 8, Value = 0.4, Cooldown = 15, Text = "Your hits slow enemies by 40% for 8 seconds." },
	Nature = { Kind = "Nature", Name = "Bloom", Effect = "Regen", Seconds = 10, Value = 0.02, Cooldown = 15, Meter = 20, Text = "Heals 2% per second for 10 seconds and charges the special." },
	Earth = { Kind = "Earth", Name = "Stone Skin", Effect = "Taken", Seconds = 8, Value = 0.35, Cooldown = 15, Text = "Damage taken -35% for 8 seconds." },
	Storm = { Kind = "Storm", Name = "Charge", Effect = "AttackSpeed", Seconds = 8, Value = 0.35, Cooldown = 15, Text = "+35% attack speed for 8 seconds." },
	Celestial = { Kind = "Celestial", Name = "Halo", Effect = "Shield", Seconds = 6, Value = 0.25, Cooldown = 15, Text = "A shield of 25% health for 6 seconds." },
	Shadow = { Kind = "Shadow", Name = "Leech", Effect = "Lifesteal", Seconds = 8, Value = 0.30, Cooldown = 15, Text = "Your hits heal you for 30% of the damage for 8 seconds." },
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

----------------------------------------------------------------------
-- The battle-only stat path (spec 2026-10-31 s.5): a level means more than a rarity, on both sides of every battle. Player pets,
-- champions, dungeon enemies, bosses and duels all read it through UnitStats. Garden income, coins, speed, feeding and
-- training prices keep PetCatalog.GetStats (Config.PetStats.RarityScale x LevelFactor).
----------------------------------------------------------------------
BattleCatalog.BattleStats = {
	RarityScale = { Common = 1, Uncommon = 1.25, Rare = 1.6, Epic = 2.1, Legendary = 2.8, Mythic = 3.7, Secret = 5 },
	Level = { Linear = 0.12, Quadratic = 0.0035, Cubic = 0.0002 },
}

-- 1 + (Linear x + Quadratic x^2 + Cubic x^3) x the evolution bonus, x = level - 1. Level: a whole number in 1..MaxPetLevel()
-- (junk counts as 1); stage: junk / nil counts as 0.
function BattleCatalog.BattleLevelFactor(level, stage)
	local pc = petCatalog()
	local lv = tonumber(level)
	if not finite(lv) or lv < 1 then
		lv = 1
	end
	lv = floor(lv)
	local bonus = 1
	if pc and pc.MaxPetLevel then
		lv = min(lv, pc.MaxPetLevel())
		bonus = pc.EvolutionBonusOf(stage)
	end
	local x = lv - 1
	local curve = BattleCatalog.BattleStats.Level
	return 1 + (curve.Linear * x + curve.Quadratic * x ^ 2 + curve.Cubic * x ^ 3) * bonus
end

-- a pet's battle numbers: { Power, Health, Speed } (no Income) at a level, tier and STORED evolution stage, or nil for an
-- unknown pet. tier nil = the key's / def's own tier.
function BattleCatalog.BattleStatsOf(subject, level, tier, stage)
	local def = BattleCatalog.StatsOf(subject)
	local pc = petCatalog()
	if not def or type(def.Stats) ~= "table" or not pc then
		return nil
	end
	local mult = pc.TierMultiplier(tier == nil and def or tier)
	local cleanStage = stage ~= nil and pc.EvolutionStage(def, level, stage) or 0
	local factor = num(BattleCatalog.BattleStats.RarityScale[def.Rarity], 1) * BattleCatalog.BattleLevelFactor(level, cleanStage) * mult
	return { Power = num(def.Stats.Power, 0) * factor, Health = num(def.Stats.Health, 0) * factor, Speed = def.Stats.Speed }
end

-- "Combat" | "Support" of a def / id / key / entry (Support = PetCatalog Role "Economy"); unknown -> "Combat"
function BattleCatalog.RoleOf(subject)
	local def = BattleCatalog.StatsOf(subject)
	if type(def) == "table" and def.Role == "Economy" then
		return "Support"
	end
	return "Combat"
end

-- a helper's button: kind, buff table (its Support special kind, else its first element's buff); nil for unknown pets
function BattleCatalog.BuffOf(subject)
	local def = BattleCatalog.StatsOf(subject)
	if not def then
		return nil
	end
	if BattleCatalog.RoleOf(def) == "Support" and type(def.Special) == "table" and BattleCatalog.Buffs[def.Special.Kind] then
		return def.Special.Kind, BattleCatalog.Buffs[def.Special.Kind]
	end
	local pc = petCatalog()
	local elems = (pc and pc.ElementsOf) and pc.ElementsOf(def) or { def.Element }
	local e = elems[1]
	if type(e) == "string" and BattleCatalog.Buffs[e] then
		return e, BattleCatalog.Buffs[e]
	end
	return nil
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
-- Training (Phase 4 3.7, kept): per rank Attack Speed +4% attacks, Physique +5% max health, Ability +4% special power
-- and charge (+ x helper buff values), Defense -3% damage taken. Ranks 0..MaxRank.
----------------------------------------------------------------------
BattleCatalog.Training = { MaxRank = 10, Speed = 0.04, Physique = 0.05, Ability = 0.04, AbilityMeter = 0.04, Defense = 0.03 }
BattleCatalog.TrainingSkills = {
	{ Id = "Speed", Name = "Attack Speed", Text = "+4% attacks per rank" },
	{ Id = "Physique", Name = "Physique", Text = "+5% max health per rank" },
	{ Id = "Ability", Name = "Ability", Text = "+4% special power and charge per rank" },
	{ Id = "Defense", Name = "Defense", Text = "-3% damage taken per rank" },
}

-- helpers (one table)
local P4 = {}
P4.SKILLS = { "Speed", "Physique", "Ability", "Defense" }
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
-- -> the stored evo stage (cleaned by PetCatalog.EvolutionStage), ranks (table or nil when untrained), boost (>= 1)
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
	local evo = 0
	local stored = field("Evo")
	if finite(stored) and stored >= 1 then
		local pc = petCatalog()
		if pc and pc.EvolutionStage then
			local ok, result = pcall(pc.EvolutionStage, def, level, stored)
			evo = (ok and finite(result)) and result or 0
		else
			evo = min(floor(stored), 2)
		end
	end
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
	local boost = 1
	local b = field("Boost")
	if finite(b) and b > 1 then
		boost = min(b, P4.MAX_BOOST)
	end
	return evo, ranks, boost
end

-- MaxHp, average hit, interval, DPS ... of one pet copy at a level, tier and evolution stage (+ training, the ring
-- Boost, the Role multipliers). The battle level curve (BattleLevelFactor x the evolution bonus) is the only level /
-- evolution source: no evoMult here.
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
	do
		local ok, result = pcall(BattleCatalog.BattleStatsOf, def, level, tier, evo > 0 and evo or nil)
		if ok then
			stats = result
		end
	end
	if type(stats) ~= "table" then
		-- no catalog (should never happen in the game): raw base stats
		stats = { Power = def.Stats.Power or 1, Health = def.Stats.Health or 1, Speed = def.Stats.Speed or 11 }
	end
	local D = BattleCatalog.Damage
	local F = BattleCatalog.Fighter
	local roleName = BattleCatalog.RoleOf(def)
	local role = BattleCatalog.Roles[roleName] or BattleCatalog.Roles.Combat
	local rolePower, roleHealth = num(role.Power, 1), num(role.Health, 1)
	local profile = BattleCatalog.ProfileOf(def)
	local speed = speedOf(def)
	local power = (finite(stats.Power) and max(stats.Power, 0) or 0) * rolePower
	local health = (finite(stats.Health) and max(stats.Health, 1) or 1) * roleHealth
	local scale = 1
	if finite(def.Stats.Health) and def.Stats.Health > 0 then
		scale = health / (def.Stats.Health * roleHealth)
	end
	local interval = profile.Interval / rateFactor(speed) / speedMult
	local hit = power * D.DamageScale * profile.DamageMult * boost
	local specialPower, specialFactor = 0, 1
	if type(def.Special) == "table" and finite(def.Special.Power) then
		local curve = D.SpecialPowerCurve
		if type(curve) == "table" and finite(def.Stats.Power) and def.Stats.Power > 0 then
			specialFactor = (def.Stats.Power * rolePower / num(curve.Reference, 10)) ^ num(curve.Exponent, 0.5)
		end
		-- `scale` is the level / rarity / tier / evolution growth only: Physique never feeds the special
		specialPower = def.Special.Power * rolePower * scale * specialFactor * abilityMult * boost
	end
	local elements = {}
	if pc and pc.ElementsOf then
		elements = pc.ElementsOf(def)
	elseif type(def.Element) == "string" then
		elements = { def.Element }
	end
	local moveSpeed = profile.MoveSpeed * moveFactor(speed)
	local walk, run = BattleCatalog.Fighter.SpeedsOf(moveSpeed)
	return {
		MaxHp = health * D.HpScale * hpMult * boost,
		Hit = hit,
		Interval = interval,
		Dps = hit / interval,
		Defense = defense, -- 0..0.3: the share of every hit taken that Defense blocks (BattleSim.applyDamage)
		MeterRate = meterRate, -- x every SPECIAL meter gain (Ability)
		SpecialBoost = abilityMult, -- the Ability factor on the special (already inside SpecialPower) and on helper buffs
		Evo = evo, -- the evolution stage that counts (0 / 1 / 2)
		Boost = boost, -- 1, or a ring champion's Boost
		Train = ranks, -- { Speed, Physique, Ability, Defense } (whole ranks) or nil when untrained
		Role = roleName, -- "Combat" | "Support"
		MoveSpeed = moveSpeed, -- NPC units walk at this
		Walk = walk, -- a player's fighter: Fighter.WalkOf(MoveSpeed) ...
		Run = run, -- ... and its run speed
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
BattleCatalog.MiniBoss = { Hp = 3, Power = 1.3, Scale = 1.7 }

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

-- an NPC entry's power: UnitPower x the mini-boss factor (Boss) x Handicap x Boost (what the Ring / Dungeon solvers aim)
function BattleCatalog.EntryPower(entry)
	local p = BattleCatalog.UnitPower(entry)
	if type(entry) == "table" then
		if entry.Boss then
			local mb = BattleCatalog.MiniBoss
			p = p * sqrt(mb.Hp * mb.Power)
		end
		if finite(entry.Handicap) and entry.Handicap > 0 and entry.Handicap < 1 then
			p = p * entry.Handicap
		end
		-- a Boost is already inside UnitStats (P4.extras) when the entry carries it
	end
	return p
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
	for _, e in ipairs(elementOrder()) do
		local count = out.Groups[e] or 0
		local bonus = rules.SameElement[min(count, 3)]
		if count >= 2 and bonus then
			local label = (count == 2 and "Pair") or "Trio"
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

-- B5: a player's team = the fighter (list[1]) played with the kit + two helpers (lives + buffs):
-- KitFactor x UnitPower(fighter) + HelperWeight x (UnitPower(h2) + UnitPower(h3)), each x sqrt(synergy power x health)
function BattleCatalog.TeamPower(list)
	if type(list) ~= "table" then
		return 0
	end
	local F = BattleCatalog.Fighter
	local size = num(BattleCatalog.TeamSize, 3)
	local trimmed = list
	if #list > size then
		trimmed = {}
		for i = 1, size do
			trimmed[i] = list[i]
		end
	end
	local syn = BattleCatalog.SynergyBonus(trimmed)
	local total = 0
	for i, entry in ipairs(trimmed) do
		local up = BattleCatalog.UnitPower(entry) * sqrt((syn.PowerMult[i] or 1) * syn.HealthMult)
		if i == 1 then
			total = total + up * num(F.KitFactor, 1.5)
		else
			total = total + up * num(F.HelperWeight, 0.35)
		end
	end
	return floor(total + 0.5)
end

-- the power of an NPC list (every pet on the floor): the sum of EntryPower (synergy included)
function BattleCatalog.NpcPower(list)
	if type(list) ~= "table" then
		return 0
	end
	local syn = BattleCatalog.SynergyBonus(list)
	local total = 0
	for i, entry in ipairs(list) do
		total = total + BattleCatalog.EntryPower(entry) * sqrt((syn.PowerMult[i] or 1) * syn.HealthMult)
	end
	return floor(total + 0.5)
end

-- Expected DPS of a player's team spec ({ Pets = { entry... } } or a plain list): the FIGHTER's DPS x (1 +
-- SpecialDpsShare: element + special) x KitFactor ^ 0.5 (the played kit); the bench adds nothing. Ability training
-- grows the special share by SpecialBoost x MeterRate.
function BattleCatalog.ExpectedDps(team)
	local list = type(team) == "table" and (team.Pets or team) or {}
	local syn = BattleCatalog.SynergyBonus(list)
	local D = BattleCatalog.Damage
	local F = BattleCatalog.Fighter
	local us = BattleCatalog.UnitStats(list[1])
	if not us then
		return 0
	end
	local share = num(D.SpecialDpsShare, 0.3)
	local gain = num(us.SpecialBoost, 1) * num(us.MeterRate, 1)
	local dps = us.Dps * (syn.PowerMult[1] or 1) * (1 + share * gain)
	if not us.Ranged then
		dps = dps * num(F.MeleeUptime, 1)
	end
	return dps * sqrt(num(F.KitFactor, 1.5))
end

-- the fighter's MaxHp (Balanced bonus included): the raid boss's damage yardstick
function BattleCatalog.AverageMaxHp(team)
	local list = type(team) == "table" and (team.Pets or team) or {}
	local syn = BattleCatalog.SynergyBonus(list)
	local us = BattleCatalog.UnitStats(list[1])
	if not us then
		return 0
	end
	return us.MaxHp * syn.HealthMult
end

----------------------------------------------------------------------
-- The loss-XP gate (Phase 4 3.5, kept for the Ring and the Dungeon): a REAL loss (the fight lasted >= LossMinSeconds
-- or the team dealt >= LossMinDamage of the enemy side's HP; never a forfeit / leave / disconnect / shutdown, which
-- the services rule out) pays LossShare of the win XP.
----------------------------------------------------------------------
BattleCatalog.LossRules = { LossShare = 1 / 3, LossMinSeconds = 20, LossMinDamage = 0.2 }

function BattleCatalog.RealLoss(seconds, dealtShare)
	local R = BattleCatalog.LossRules
	if finite(seconds) and seconds >= num(R.LossMinSeconds, 20) then
		return true
	end
	return finite(dealtShare) and dealtShare >= num(R.LossMinDamage, 0.2)
end

function BattleCatalog.LossXp(winXp, seconds, dealtShare)
	if not finite(winXp) or winXp <= 0 or not BattleCatalog.RealLoss(seconds, dealtShare) then
		return 0
	end
	return floor(winXp * num(BattleCatalog.LossRules.LossShare, 1 / 3) + 0.5)
end

----------------------------------------------------------------------
-- The Champion Ring (Phase 4 3.8, kept; HUD cleanup 2026-10-30, spec decision 5: the no-heal climb). The climber's pets
-- keep their HP from round to round and a fainted pet sits out the run (BattleService RingRun). Champions are built
-- with the PLAYER pet formula (BattleStatsOf through UnitStats: level, rarity, tier, the evolution stage the level
-- allows, training ranks) with no Boss / Handicap / Boost, so a level means the same strength on both sides. The round
-- sets the level (LevelAnchors: linear between the anchors, floored, + BossLevelBump on every BossEvery-th round,
-- capped at PetCatalog.MaxPetLevel()), the tier (TierFrom), the number of champions (Helpers: 1 -> 2 -> 3, all on the
-- floor, one species: a pack, so the synergy rule gives it the Pair / Trio bonus like a player's team) and, past the
-- level cap, training (Training: all four skills, rank 0 -> 10). The species comes from the run seed and the round's
-- rarity band (never EventOnly; a band's lower rarity in the first half of its rounds, the higher one in the second
-- half; the open band its last rarity from From + 6): a seeded pick among the species that match the round before
-- within MaxLevelRaise levels of the curve (none there: the strongest one). The team's TeamPower never drops
-- below the round before: the level is raised, then the tier, then a champion joins, then a training rank; at the very
-- top the stronger team of the round before stays. Rounds 1-3 (OpeningRounds) are the three weakest level-1 Commons that do not heal.
-- Tuned 2026-10-30 with tools/sim_battle.lua (section ring, no heal, 12 seeds; re-measured with MaxLevelRaise 5): stage
-- record medians S1 13, S2 15, S3 19, S4 25, S5 25, S6 30, S7 33, S8 35, S9 42, S10 51 (the fresh-HP ladder before was
-- 14 .. 49), three L100 Rainbow evo-2 fully trained pets 67; rounds 1-3 100% for every single level-1 starter; a team
-- beats champions 10+ levels below it 24 of 24; round 100's champions beat the maxed team 24 of 24 fresh fights; a
-- champion's level is never more than 5 above the curve (64 seeds x 400 rounds).
----------------------------------------------------------------------
BattleCatalog.Ring = {
	-- { round, level } anchors of the champion level curve (the last anchor holds)
	LevelAnchors = { { 1, 1 }, { 3, 1 }, { 10, 3 }, { 14, 4 }, { 20, 11 }, { 27, 23 }, { 33, 33 }, { 42, 46 }, { 49, 58 }, { 60, 80 }, { 70, 100 } },
	BossEvery = 10, -- every 10th round: the boss round (BossLevelBump levels more), the first win pays BossTokens
	BossLevelBump = 3,
	TierFrom = { Golden = 36, Rainbow = 51 }, -- the champions' tier from these rounds on
	Evolve = true, -- champions hold the evolution stage their level allows (PetCatalog.EvolutionLevels), like a player's pet
	Helpers = { { From = 56, Count = 2 }, { From = 66, Count = 3 } }, -- more champions on the floor from these rounds on
	MaxChampions = 3,
	-- the top: past the level cap the champions train like a player's pets (all four skills, rank 0 -> MaxRank over From..To)
	Training = { From = 70, To = 100 },
	-- rounds 1..OpeningRounds: the weakest level-1 Commons that do not heal, weakest first (every single level-1 starter
	-- wins each of them; the opening never needs a level raise)
	OpeningRounds = 3,
	-- the species of a round: a seeded pick among the band's species that match the round before within MaxLevelRaise
	-- levels of the curve (so the shown level follows the curve instead of jumping L42 -> L26 -> ...)
	MaxLevelRaise = 5,
	Bands = { -- the champions' rarity by round; the last band is open-ended
		{ From = 1, To = 9, Rarities = { "Common" } },
		{ From = 10, To = 15, Rarities = { "Common", "Uncommon" } },
		{ From = 16, To = 21, Rarities = { "Uncommon", "Rare" } },
		{ From = 22, To = 27, Rarities = { "Rare", "Epic" } },
		{ From = 28, To = 33, Rarities = { "Epic", "Legendary" } },
		{ From = 34, To = 41, Rarities = { "Legendary", "Mythic" } },
		{ From = 42, Rarities = { "Mythic", "Secret" } },
	},
	CashFloorBase = 20,
	CashFloorPerRound = 2,
	SecondsBase = 1.5,
	SecondsPerRound = 0.1,
	SecondsMax = 9,
	RecordMult = 3,
	BossTokens = 100,
	XpBase = 20,
	XpPerRound = 6,
	TimeLimit = 90, -- = TimeLimits.Ring; a timeout is a loss
	Intermission = 3,
	MaxRound = 100000,
}
P4.RING_M = 2147483647
P4.MAX_POWER = 1e15
P4.RING_MEMO_SEEDS = 64
P4.RING_FLAT = 400 -- past this round every champion team is the round-400 one (a run's history stays short)
P4.TIERS = { "Normal", "Golden", "Rainbow" }
P4.baseCache = {} -- "petId|level|tier" -> UnitPower of that single plain pet
P4.ringMemo = {}
P4.ringOrder = {}

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

function P4.seed(seed)
	local s = tonumber(seed)
	if not finite(s) then
		s = 1
	end
	return floor(abs(s)) % (P4.RING_M - 1)
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

-- the champions' rarity of round r: the band's lower rarity in the first half of its rounds, the higher one in the
-- second half (the open-ended band: its last rarity from From + 6 on)
function P4.bandRarity(r)
	local bands = BattleCatalog.Ring.Bands
	local band = bands[#bands]
	for _, b in ipairs(bands) do
		if r >= num(b.From, 1) and (b.To == nil or r <= b.To) then
			band = b
			break
		end
	end
	local list = band.Rarities
	if #list < 2 then
		return list[1]
	end
	local from = num(band.From, 1)
	local split = from + 6
	if band.To then
		split = from + floor((band.To - from + 1) / 2)
	end
	return (r >= split) and list[#list] or list[1]
end

-- a small deterministic integer stream (Lehmer steps, exact in doubles)
function P4.stream(x)
	local M = P4.RING_M
	x = (x * 7919 + 104729) % M
	if x == 0 then
		x = 1
	end
	return function(n)
		x = (x * 48271) % M
		return 1 + (x % n)
	end
end

-- the species of round r in the run with seed s: one draw of the seeded stream from the rarity's pool (Common when empty)
function P4.pickSpecies(r, s, rarity)
	local nextInt = P4.stream(((s % P4.RING_M) * 1000 + r) % P4.RING_M)
	local pools = P4.pools()
	local list = pools[rarity]
	if not list or #list == 0 then
		list = pools.Common
	end
	if not list or #list == 0 then
		return nil
	end
	return list[nextInt(#list)]
end

-- the species of round r (seed s) when the round before had power `goal`: one seeded draw (P4.pickSpecies' stream)
-- among the rarity's species whose `count` x (level + MaxLevelRaise, tier, rank) team reaches goal, so the level
-- raise in P4.champion stays within MaxLevelRaise of the curve; none there: the strongest one. goal 0: P4.pickSpecies.
function P4.pickChampion(r, s, rarity, count, level, tier, rank, goal)
	if not (goal and goal > 0) then
		return P4.pickSpecies(r, s, rarity)
	end
	local pools = P4.pools()
	local list = pools[rarity]
	if not list or #list == 0 then
		list = pools.Common
	end
	if not list or #list == 0 then
		return nil
	end
	local reach = min(P4.maxLevel(), level + max(0, floor(num(BattleCatalog.Ring.MaxLevelRaise, 5))))
	local fits, best, bestPower = {}, nil, -1
	for _, id in ipairs(list) do
		local p = BattleCatalog.TeamPower(P4.entries(id, count, reach, tier, rank))
		if p >= goal then
			fits[#fits + 1] = id
		end
		if p > bestPower then
			best, bestPower = id, p
		end
	end
	if #fits == 0 then
		return best
	end
	local nextInt = P4.stream(((s % P4.RING_M) * 1000 + r) % P4.RING_M)
	return fits[nextInt(#fits)]
end

function P4.basePower(petId, level, tier)
	local key = petId .. "|" .. level .. "|" .. tier
	local p = P4.baseCache[key]
	if p == nil then
		p = BattleCatalog.UnitPower({ PetId = petId, Level = level, Tier = tier })
		P4.baseCache[key] = p
	end
	return p
end

-- an NPC entry's power from the cache: the plain pet's, x the mini-boss factor, x Handicap, x Boost
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

-- the generic NPC solver (dungeon enemies): the entry of species petId closest above `goal`.
-- Order: a level-1 plain pet above the goal is handicapped down (>= minHandicap; forceBoss: the level-1 mini-boss
-- form); else the lowest level 1..topLevel of the plain pet; else the mini-boss form Normal -> Golden -> Rainbow; else
-- the top Rainbow mini-boss with Boost = goal / power. Returns entry, power.
function P4.solveEntry(petId, goal, topLevel, minHandicap, forceBoss)
	local function at(level, tier, boss)
		return { PetId = petId, Level = level, Tier = tier, Boss = boss or nil }
	end
	local first = at(1, "Normal", forceBoss)
	local p1 = P4.power(first)
	if p1 > goal then
		local h = goal / p1
		if h < minHandicap then
			first.Handicap = minHandicap
			return first, p1 * minHandicap
		end
		first.Handicap = h
		return first, goal
	end
	local forms = { { false, "Normal" }, { true, "Normal" }, { true, "Golden" }, { true, "Rainbow" } }
	for i, form in ipairs(forms) do
		if (i > 1 or not forceBoss) and P4.power(at(topLevel, form[2], form[1])) >= goal then
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
			return e, P4.power(e)
		end
	end
	local top = at(topLevel, "Rainbow", true)
	local tp = P4.power(top)
	if tp > 0 and goal > tp then
		top.Boost = goal / tp
		return top, goal
	end
	return top, tp
end

-- the NPC solver for harnesses and services: the entry of `petId` closest above `goal` (UnitPower units; Handicap /
-- level / mini-boss / Boost), opts = { MaxLevel = 50, MinHandicap = 0.3, Boss = false }. Returns entry, power.
function BattleCatalog.SolveEnemy(petId, goal, opts)
	opts = type(opts) == "table" and opts or {}
	if type(petId) ~= "string" or not finite(goal) or goal <= 0 then
		return nil
	end
	local e, p = P4.solveEntry(petId, goal, max(1, floor(num(opts.MaxLevel, 50))), num(opts.MinHandicap, 0.3), opts.Boss == true)
	if e then
		e.Key = e.PetId
	end
	return e, p
end

-- the curve level of round r (LevelAnchors: linear between the anchors, floored; the last anchor holds)
function P4.curveLevel(r)
	local A = BattleCatalog.Ring.LevelAnchors
	if r <= A[1][1] then
		return A[1][2]
	end
	for i = 2, #A do
		local a, b = A[i - 1], A[i]
		if r <= b[1] then
			return floor(a[2] + (b[2] - a[2]) * (r - a[1]) / (b[1] - a[1]))
		end
	end
	return A[#A][2]
end

function P4.maxLevel()
	local pc = petCatalog()
	local top = pc and pc.MaxPetLevel and pc.MaxPetLevel()
	if finite(top) and top >= 1 then
		return floor(top)
	end
	return 100
end

-- the champions' level of a round: the curve, + BossLevelBump on a boss round, 1..MaxPetLevel()
function BattleCatalog.ChampionLevel(round)
	local R = BattleCatalog.Ring
	local r = P4.round(round)
	local level = P4.curveLevel(r)
	if r % R.BossEvery == 0 then
		level = level + num(R.BossLevelBump, 0)
	end
	return max(1, min(P4.maxLevel(), floor(level)))
end

-- "Normal" | "Golden" | "Rainbow" by Ring.TierFrom
function BattleCatalog.ChampionTier(round)
	local r = P4.round(round)
	local from = BattleCatalog.Ring.TierFrom or {}
	if finite(from.Rainbow) and r >= from.Rainbow then
		return "Rainbow"
	end
	if finite(from.Golden) and r >= from.Golden then
		return "Golden"
	end
	return "Normal"
end

function P4.maxChampions()
	return max(1, min(floor(num(BattleCatalog.Ring.MaxChampions, 3)), num(BattleCatalog.TeamSize, 3)))
end

-- how many champions take the floor (1..MaxChampions) by Ring.Helpers
function BattleCatalog.ChampionCount(round)
	local r = P4.round(round)
	local n = 1
	for _, h in ipairs(BattleCatalog.Ring.Helpers or {}) do
		if finite(h.From) and finite(h.Count) and r >= h.From then
			n = max(n, floor(h.Count))
		end
	end
	return min(n, P4.maxChampions())
end

-- the evolution stage a player's pet of `level` can hold (EvolutionLevels), clamped to the species' top
function P4.evoFor(def, level)
	local pc = petCatalog()
	if BattleCatalog.Ring.Evolve ~= true or not pc or not pc.EvolutionStage then
		return 0
	end
	local stage = 0
	for s, need in ipairs(pc.EvolutionLevels or {}) do
		if finite(need) and level >= need then
			stage = s
		end
	end
	local ok, v = pcall(pc.EvolutionStage, def, level, stage)
	return (ok and finite(v)) and v or 0
end

-- the champions' training rank of round r (Ring.Training: 0 before From, MaxRank from To, linear between)
function P4.trainRank(r)
	local tr = BattleCatalog.Ring.Training
	local top = floor(num(BattleCatalog.Training.MaxRank, 10))
	if type(tr) ~= "table" or not finite(tr.From) or not finite(tr.To) or r < tr.From then
		return 0
	end
	if r >= tr.To or tr.To <= tr.From then
		return top
	end
	return min(top, floor(top * (r - tr.From + 1) / (tr.To - tr.From + 1)))
end

-- `count` champions of one species (a pack: one element, so the player's synergy rule gives it the Pair / Trio bonus)
function P4.entries(petId, count, level, tier, rank)
	local pc = petCatalog()
	local def = pc and pc.Get and pc.Get(petId)
	local evo = def and P4.evoFor(def, level) or 0
	local list = {}
	for i = 1, count do
		local e = { PetId = petId, Level = level, Tier = tier, Evo = evo }
		if rank and rank > 0 then
			e.Train = { Speed = rank, Physique = rank, Ability = rank, Defense = rank }
		end
		list[i] = e
	end
	return list
end

-- the opening's species: the OpeningRounds weakest level-1 Commons (UnitPower, then id) that do not heal themselves
-- (a Heal special drags a level-1 fight out), weakest first; the same for every run
function P4.opening()
	if P4.openingList and P4.openingSig == P4.ringSig then
		return P4.openingList
	end
	local pc = petCatalog()
	local pool = {}
	for _, id in ipairs(P4.pools().Common or {}) do
		local def = pc and pc.Get and pc.Get(id)
		local special = def and type(def.Special) == "table" and def.Special.Kind or nil
		if special ~= "Heal" then
			pool[#pool + 1] = { Id = id, Power = P4.basePower(id, 1, "Normal") }
		end
	end
	table.sort(pool, function(a, b)
		if a.Power ~= b.Power then
			return a.Power < b.Power
		end
		return a.Id < b.Id
	end)
	local out = {}
	for i = 1, min(#pool, max(0, floor(num(BattleCatalog.Ring.OpeningRounds, 3)))) do
		out[i] = pool[i].Id
	end
	P4.openingList, P4.openingSig = out, P4.ringSig
	return out
end

-- one round's champion team: entries, power (TeamPower). prev = the round before ({ Power, Pets }, nil on round 1):
-- below it the level is raised (up to MaxPetLevel), then the tier, then a champion joins, then a training rank; still
-- below it at the very top, the round before's team stays
function P4.champion(r, s, prev)
	local maxCount = P4.maxChampions()
	local top = P4.maxLevel()
	local level = BattleCatalog.ChampionLevel(r)
	local count = BattleCatalog.ChampionCount(r)
	local tierName = BattleCatalog.ChampionTier(r)
	local tier = 1
	for i, name in ipairs(P4.TIERS) do
		if name == tierName then
			tier = i
		end
	end
	local rank = P4.trainRank(r)
	local maxRank = floor(num(BattleCatalog.Training.MaxRank, 10))
	local goal = prev and prev.Power or 0
	local petId = (r <= num(BattleCatalog.Ring.OpeningRounds, 0)) and P4.opening()[r] or P4.pickChampion(r, s, P4.bandRarity(r), count, level, P4.TIERS[tier], rank, goal)
	if not petId then
		return nil, 0
	end
	local entries = P4.entries(petId, count, level, P4.TIERS[tier], rank)
	local power = BattleCatalog.TeamPower(entries)
	while power < goal do
		if level < top then
			level = level + 1
		elseif tier < #P4.TIERS then
			tier = tier + 1
		elseif count < maxCount then
			count = count + 1
		elseif rank < maxRank then
			rank = rank + 1
		else
			break
		end
		entries = P4.entries(petId, count, level, P4.TIERS[tier], rank)
		power = BattleCatalog.TeamPower(entries)
	end
	if power < goal then
		return prev.Pets, prev.Power
	end
	return entries, power
end

-- the per-seed history ({ Power, Pets } per round); reset whenever a Ring knob changes (the sim tunes them)
function P4.memoFor(s)
	local R = BattleCatalog.Ring
	local parts = { tostring(R.BossEvery), tostring(R.BossLevelBump), tostring(R.Evolve), tostring(R.MaxChampions), tostring(BattleCatalog.Fighter.KitFactor), tostring(BattleCatalog.Fighter.HelperWeight), tostring(BattleCatalog.Roles.Support.Power) }
	for _, a in ipairs(R.LevelAnchors) do
		parts[#parts + 1] = tostring(a[1]) .. ":" .. tostring(a[2])
	end
	local from = R.TierFrom or {}
	parts[#parts + 1] = tostring(from.Golden) .. "/" .. tostring(from.Rainbow)
	local tr = R.Training or {}
	parts[#parts + 1] = "T" .. tostring(tr.From) .. "-" .. tostring(tr.To) .. "/" .. tostring(R.OpeningRounds) .. "/" .. tostring(R.MaxLevelRaise)
	for _, h in ipairs(R.Helpers or {}) do
		parts[#parts + 1] = tostring(h.From) .. "x" .. tostring(h.Count)
	end
	for _, b in ipairs(R.Bands) do
		parts[#parts + 1] = tostring(b.From) .. "-" .. tostring(b.To) .. "=" .. table.concat(b.Rarities or {}, ",")
	end
	local sig = table.concat(parts, "|")
	if sig ~= P4.ringSig then
		P4.ringSig = sig
		P4.ringMemo = {}
		P4.ringOrder = {}
		P4.baseCache = {}
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
		local entries, power = P4.champion(j, s, prev)
		if entries then
			prev = { Power = power, Pets = entries }
		end
		memo[j] = prev
	end
	return memo[k]
end

function P4.ring(r, s)
	return P4.history(min(r, P4.RING_FLAT), s, P4.memoFor(s))
end

-- A BattleSim team spec for the champions of `round` in the run with `seed` (fresh tables; pure and deterministic)
function BattleCatalog.ChampionTeam(round, seed)
	local r = P4.round(round)
	local s = P4.seed(seed)
	local h = P4.ring(r, s)
	if not h or not h.Pets[1] then
		return nil
	end
	local pets = {}
	for i, e in ipairs(h.Pets) do
		pets[i] = {
			PetId = e.PetId,
			Key = e.PetId,
			Level = e.Level,
			Tier = e.Tier,
			Evo = e.Evo,
			Train = e.Train and { Speed = e.Train.Speed, Physique = e.Train.Physique, Ability = e.Train.Ability, Defense = e.Train.Defense } or nil,
			Slot = i,
			Crowned = (i == 1) or nil,
			MeterStart = BattleCatalog.Damage.LateMeterStart, -- #27: the champions open with a special almost ready
		}
	end
	local first = pets[1]
	local pc = petCatalog()
	local def = pc and pc.Get and pc.Get(first.PetId)
	local name = (def and (def.DisplayName or def.Name)) or first.PetId
	return {
		Owner = "npc",
		Side = 2,
		Npc = true,
		Name = "Champion " .. name,
		Round = r,
		Seed = s,
		Power = h.Power,
		Champion = {
			PetId = first.PetId,
			Level = first.Level,
			Tier = first.Tier,
			Evo = first.Evo,
			Count = #pets,
			Boss = (r % BattleCatalog.Ring.BossEvery == 0) or nil, -- the boss round's flag (rewards, the crowd), no stat change
			Name = name,
			Power = h.Power,
		},
		Pets = pets,
	}
end

function BattleCatalog.RingPower(round, seed)
	local h = P4.ring(P4.round(round), P4.seed(seed))
	return h and h.Power or 0
end

function BattleCatalog.RingSeconds(round)
	local R = BattleCatalog.Ring
	return min(R.SecondsMax, R.SecondsBase + R.SecondsPerRound * P4.round(round))
end

-- The rewards of one round WON: Cash = max(floor, seconds of the climber's own garden income) (x RecordMult on a new
-- record), Xp per team pet, Tokens = BossTokens for the first win of a boss round.
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
-- Duels (4.2): the practice gap and the quick queue band (BattleService reads these)
----------------------------------------------------------------------
BattleCatalog.Duel = {
	PowerGap = 2, -- a duel whose TeamPowers differ by more than this pays nothing (a practice duel)
	QueueGap = 1.6, -- the quick queue pairs within QUEUE_GAP and x QueueGap TeamPower ...
	QueueGapPerWait = 0.1, -- ... + this per QueueWaitStep seconds waiting ...
	QueueWaitStep = 10,
	QueueGapMax = 3, -- ... up to this
	PracticeInvite = 2, -- a challenge more than this apart carries Practice = true in the invite
}

----------------------------------------------------------------------
-- The boss roster (Phase 3, kept). Boss damage is a fraction of the fighters' HP (DamageBasis blends each victim's own
-- max HP with the raid's average); boss HP lasts HpPerPlayer seconds of every team's expected DPS (BossHp), but never
-- less than HpPerPlayer seconds of BaselineDps (#2: a weak solo cannot finish inside the 330 s raid window). Telegraph
-- shapes: Circle { Radius } at a target point, Line { Width, Length } from the boss through a target point. The dash's
-- i-frames and a step out of the shape both dodge a telegraph.
----------------------------------------------------------------------
BattleCatalog.BossRules = {
	DamageBasis = { Own = 0.6, Average = 0.4 },
	MinHp = 2500, -- #2: 600 -> 2500
	-- #2: the boss HP floor = HpPerPlayer x BaselineDps(bossId): the ExpectedDps of this fighter (a level-25 evolved
	-- (stage 1) Legendary, the Prestige-1 fighter of tools/sim_battle.lua), unless the boss sets its own BaselineDps
	Baseline = { PetId = "ember_phoenix", Level = 25, Evo = 1 },
	MinionHp = 0.7,
	MinionDamage = 0.035,
	GroupExponent = 0.2, -- boss HP x teams ^ GroupExponent (Phase 5: 0.25 -> 0.2, so 8 fighters finish in ~220 s)
	DamageGroup = { Min = 0.7, FullAt = 8 }, -- dungeon fixes (7): 0.55 -> 0.35 (no bench regen); #2: 0.35 -> 0.7 (a solo raid is meant to be hard)
	MinionInterval = 1.4,
	MinionLevelOf = "average",
	Enrage = { Damage = 2, Cooldown = 0.7 },
	WaveMin = 2,
	WaveMax = 8,
	CirclesPerTeams = 2,
	MaxCircles = 4,
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
		HpPerPlayer = 100, -- seconds of each team's expected DPS (dodging and dashing cost about a third of the uptime)
		Radius = 7,
		Scale = 1,
		Basic = { Name = "Zap", Interval = 2.4, Damage = 0.05, Range = 20 },
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
		HpPerPlayer = 90, -- its Eruption sends every melee fighter running, so its HP is a little lower (balance-5: 90 -> 85,
		-- the bug #22 engaged pets (EngagePull 7) cost the Frost-heavy mid group time: 8 x M5 won 44% of 32 seeds, then 84%).
		-- Wave 6: 85 -> 90 again: pets that never retreat + the parrying trainer made it fast (M8 4p 88 s, the M8 stage
		-- average 97 s); at 90: M8 93-115 s a cell, 8 x M5 84% of 32 seeds (225 s), a solo M5 / Lv 5 still loses
		Radius = 8,
		Scale = 1,
		Basic = { Name = "Magma Fist", Interval = 2.8, Damage = 0.05, Range = 20 },
		Attacks = {
			attack("pool", "Magma Pool", "Circle", { Radius = 7, Telegraph = 2.2, Cooldown = 18, Damage = 0.15, Target = "Cluster", Linger = 5, LingerDamage = 0.015, First = 8 }), -- dungeon fixes (7): LingerDamage 0.03 -> 0.015
			attack("eruption", "Eruption", "Circle", { Radius = 15, Telegraph = 2.4, Cooldown = 30, Damage = 0.2, Target = "Self", First = 18 }),
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
		Basic = { Name = "Ice Spit", Interval = 2.2, Damage = 0.045, Range = 20 },
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
		Basic = { Name = "Shadow Bite", Interval = 1.8, Damage = 0.04, Range = 20 },
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

-- The weighted head count of a list of team DPS values: every team counts min(1, dps / the strongest dps)
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

-- The DPS a boss's HP floor is measured against (#2): the boss's own BaselineDps, else the ExpectedDps of the
-- BossRules.Baseline fighter (so it follows the stat formulas)
function BattleCatalog.BaselineDps(bossId)
	local boss = BattleCatalog.Bosses[bossId]
	if boss and finite(boss.BaselineDps) and boss.BaselineDps > 0 then
		return boss.BaselineDps
	end
	local ref = BattleCatalog.BossRules.Baseline
	if type(ref) ~= "table" then
		return 0
	end
	local ok, dps = pcall(BattleCatalog.ExpectedDps, { Pets = { { PetId = ref.PetId, Key = ref.PetId, Level = ref.Level, Tier = ref.Tier, Evo = ref.Evo } } })
	return (ok and finite(dps) and dps > 0) and dps or 0
end

-- Boss HP for a list of team specs (each { Pets = {...} }): HpPerPlayer seconds of every team's expected DPS, each
-- team's share weighted like the head count, x GroupFactor; never below HpPerPlayer seconds of BaselineDps (#2: the
-- floor is for the whole raid, so a weak group still adds up past it while a weak solo cannot), nor MinHp.
-- Returns the total and the shares (scaled up with the floor, so they still add up to the total before GroupFactor).
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
	local floorHp = seconds * BattleCatalog.BaselineDps(bossId)
	if total > 0 and total < floorHp then
		local scale = floorHp / total
		for i = 1, #shares do
			shares[i] = shares[i] * scale
		end
		total = floorHp
	elseif total <= 0 then
		total = floorHp
	end
	local minHp = BattleCatalog.BossRules.MinHp
	if total < minHp then
		total = minHp
	end
	return floor(total + 0.5), shares
end

function BattleCatalog.GroupFactor(teams)
	local n = max(1, num(teams, 1))
	return n ^ (BattleCatalog.BossRules.GroupExponent or 0)
end

----------------------------------------------------------------------
-- Event schedule + raid rewards + trophies (Phase 3, kept)
----------------------------------------------------------------------
BattleCatalog.Events = {
	Schedule = {
		{ Kind = "BossRaid", EveryMinutes = 20, AnnounceSeconds = 120, DurationSeconds = 330 },
		{ Kind = "DoubleRewards", EveryMinutes = 180, AnnounceSeconds = 120, DurationSeconds = 3600 },
	},
	FirstAfterSeconds = 300,
	DoubleRewardsMultiplier = 2,
	JoinWindowSeconds = 60,
}

BattleCatalog.Raid = {
	Tiers = {
		{ Id = "Gold", MinShare = 0.25, Tokens = 500, Xp = 400, Gems = 10, GemChance = 0.25, EventPetChance = 0.05 },
		{ Id = "Silver", MinShare = 0.10, Tokens = 300, Xp = 250, Gems = 5, GemChance = 0.15, EventPetChance = 0.03 },
		{ Id = "Bronze", MinShare = 0.02, Tokens = 150, Xp = 120, Gems = 3, GemChance = 0.08, EventPetChance = 0.015 },
		{ Id = "Helper", MinShare = 0, Tokens = 60, Xp = 50, Gems = 0, GemChance = 0, EventPetChance = 0.005 },
	},
	MinShare = 0,
	LossTokens = 25,
	LossXp = 20,
}

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

BattleCatalog.Trophies = {
	Win = 20,
	Loss = -10,
	Draw = 0,
	Forfeit = -10,
	Floor = 0,
	Tokens = { Win = 40, Loss = 10, Draw = 15 },
	Xp = { Win = 60, Loss = 25 },
}

----------------------------------------------------------------------
-- The Dungeon (5.1): 12 floors x 3 wave rooms + a boss room; the enemy of every wave is solved like a champion
-- (the same solver) to the floor's target per player. Floor 1 is the tutorial floor: ONE handicapped enemy per wave.
----------------------------------------------------------------------
BattleCatalog.Dungeon = {
	Floors = 12,
	Floor1Power = 1.5, -- floor 1's target per player (one handicapped Common: any single level-1 pet wins)
	FirstPower = 4, -- floor f >= 2 targets FirstPower x Growth ^ (f - 1) TeamPower per player (floor 2 = 8, floor 10 = 2048, floor 12 = 8192)
	Growth = 2.0,
	RoomMult = { 1.0, 1.1, 1.25 }, -- wave rooms 1-3 (re-tuned by sim_battle for the fighter engine: S1 clears floor 2, S10 floor 11)
	BossMult = 1.3, -- the boss (room 4, wave 1)
	EscortMult = 0.5, -- the boss's escort (room 4, wave 2, at EscortAt of its HP)
	Waves = { 2, 2, 3 },
	Floor1Waves = { 1, 1, 1 },
	EnemiesPerWave = 2, -- + 1 per extra player
	Floor1EnemiesPerWave = 1,
	PartyExp = 0.5, -- the party's target = per player x partySize ^ PartyExp (0.85 in the design assumed 3-4 pets per player on the floor; with ONE fighter per player sim_battle measures +1 floor for a party of 4 at 0.5)
	MinHandicap = 0.3,
	EnemyMaxLevel = 50,
	RoomTime = 120,
	Floor1RoomTime = 180,
	Zones = { Room = { X = 44, Z = 44 }, Boss = { X = 56, Z = 72 } }, -- Boss = the whole 60 x 72 Throne floor (W5: the dais was outside the 56 x 56 zone)
	EscortAt = 0.5,
	Intermission = 2,
	DoorTime = 12,
	HallSeconds = 10,
	TreasureSeconds = 45,
	MinShare = 0.05,
	LateJoinLastRoom = 2,
	ReadyTimeout = 30,
	RunMaxSeconds = 4 * 120 + 4 * 12 + 10 + 45 + 120,
	Bands = {
		{ 1, 2, { "Common" } },
		{ 3, 4, { "Common", "Uncommon" } },
		{ 5, 6, { "Uncommon", "Rare" } },
		{ 7, 8, { "Rare", "Epic" } },
		{ 9, 10, { "Epic", "Legendary" } },
		{ 11, 12, { "Legendary", "Mythic", "Secret" } },
	},
	-- loot (5.2)
	RoomSeconds = { 3, 4, 5, 12 }, -- Cash = max(CashBase + CashPerFloor x floor, income x RoomSeconds[room])
	CashBase = 20,
	CashPerFloor = 10,
	TokenBase = 6, -- wave rooms floor((TokenBase + TokenPerFloor x f) x waves / 2); the boss room (TokenBase + TokenPerFloor x f) x 2
	TokenPerFloor = 4,
	XpBase = 25, -- XP per team pet = (XpBase + XpPerFloor x f) x waves (the boss room counts BossRoomWaves)
	XpPerFloor = 10,
	BossRoomWaves = 4,
	FirstClearTokens = 300, -- x floor
	FirstClearGems = { 3, 4, 5, 6, 8, 10, 12, 15, 18, 20, 25, 30 },
	-- the boss chest: floors 1-2 Cash 70% / Tokens 30% (never Gems); floor >= 3 Cash 60% / Tokens 30% / Gems 2 8% / Gems 5 2%
	ChestLowFloors = 2,
	ChestCashSeconds = 30, -- Cash = this many seconds of income (at least ChestCashMin)
	ChestCashMin = 50,
	ChestTokens = { Base = 20, PerFloor = 10 },
}

BattleCatalog.DungeonFloors = {
	{ Name = "Mossy Cellar", Element = "Nature", Kind = "Cellar" },
	{ Name = "Stone Halls", Element = "Earth", Kind = "Hall" },
	{ Name = "Flooded Vaults", Element = "Water", Kind = "Cave" },
	{ Name = "Frozen Crypt", Element = "Frost", Kind = "Cellar" },
	{ Name = "Ember Forge", Element = "Flame", Kind = "Hall" },
	{ Name = "Thunder Spire", Element = "Storm", Kind = "Bridge" },
	{ Name = "Star Chapel", Element = "Celestial", Kind = "Hall" },
	{ Name = "Shadow Keep", Element = "Shadow", Kind = "Cave" },
	{ Name = "Magma Mines", Element = "Earth", Kind = "Cave" },
	{ Name = "Howling Peak", Element = "Frost", Kind = "Bridge" },
	{ Name = "Eclipse Sanctum", Element = "Celestial", Kind = "Hall" },
	{ Name = "Abyss Throne", Element = "Shadow", Kind = "Throne" },
}
for i, f in ipairs(BattleCatalog.DungeonFloors) do
	f.Floor = i
end

local D5 = {}

function D5.floor(f)
	f = tonumber(f)
	if not finite(f) or f < 1 then
		return 1
	end
	return min(floor(f), num(BattleCatalog.Dungeon.Floors, 12))
end

function D5.party(n)
	n = tonumber(n)
	if not finite(n) or n < 1 then
		return 1
	end
	return min(floor(n), 16)
end

function D5.rarities(f)
	for _, b in ipairs(BattleCatalog.Dungeon.Bands) do
		if f >= b[1] and f <= b[2] then
			return b[3]
		end
	end
	local last = BattleCatalog.Dungeon.Bands[#BattleCatalog.Dungeon.Bands]
	return last and last[3] or { "Common" }
end

-- element -> rarity -> { petId... } (never EventOnly), cached once the catalog is there
function D5.pools()
	if D5.poolCache then
		return D5.poolCache
	end
	local byElement = {}
	local pc = petCatalog()
	if pc and type(pc.Pets) == "table" then
		for _, def in ipairs(pc.Pets) do
			if def.EventOnly ~= true and type(def.Id) == "string" and type(def.Rarity) == "string" then
				local elems = pc.ElementsOf and pc.ElementsOf(def) or { def.Element }
				for _, e in ipairs(elems) do
					byElement[e] = byElement[e] or {}
					byElement[e][def.Rarity] = byElement[e][def.Rarity] or {}
					table.insert(byElement[e][def.Rarity], def.Id)
				end
			end
		end
		D5.poolCache = byElement
	end
	return byElement
end

-- the candidates of a floor: the floor's element in the band (< 2 candidates -> any element in the band)
function D5.candidates(f)
	local info = BattleCatalog.DungeonFloors[f]
	local element = info and info.Element
	local rarities = D5.rarities(f)
	local pools = D5.pools()
	local list = {}
	local seen = {}
	local function add(id)
		if not seen[id] then
			seen[id] = true
			list[#list + 1] = id
		end
	end
	if element and pools[element] then
		for _, r in ipairs(rarities) do
			for _, id in ipairs(pools[element][r] or {}) do
				add(id)
			end
		end
	end
	if #list < 2 then
		for _, r in ipairs(rarities) do
			for _, list2 in pairs(P4.pools()) do
				for _, id in ipairs(list2) do
					local def = petCatalog() and petCatalog().Get(id)
					if def and def.Rarity == r then
						add(id)
					end
				end
			end
		end
	end
	table.sort(list)
	return list
end

-- the party's target power of a floor (per player x partySize ^ PartyExp)
function BattleCatalog.DungeonPower(floorIndex, partySize)
	local D = BattleCatalog.Dungeon
	local f = D5.floor(floorIndex)
	local n = D5.party(partySize)
	local per
	if f == 1 then
		per = num(D.Floor1Power, 1.5)
	else
		per = num(D.FirstPower, 4) * num(D.Growth, 2) ^ (f - 1)
	end
	return per * n ^ num(D.PartyExp, 0.85)
end

-- One wave's enemies: { Pets = { entry... }, Boss, Power, Target, Floor, Room, Wave, Count }; deterministic for its
-- arguments. Room 4 wave 1 = the boss alone (forced mini-boss form, handicapped on floors 1-2), wave 2 = the escort at
-- EscortMult; floor 1 = ONE handicapped enemy per wave. Rooms 1-3: EnemiesPerWave (+1 per extra player) at RoomMult.
function BattleCatalog.DungeonWave(floorIndex, room, wave, partySize, seed)
	local D = BattleCatalog.Dungeon
	local f = D5.floor(floorIndex)
	local n = D5.party(partySize)
	local r = max(1, min(4, floor(num(tonumber(room), 1))))
	local w = max(1, floor(num(tonumber(wave), 1)))
	local s = P4.seed(seed)
	local total = BattleCatalog.DungeonPower(f, n)
	local count, goalEach, forceBoss
	local isBoss = false
	if r == 4 then
		if w == 1 then
			count = 1
			goalEach = total * num(D.BossMult, 1.3)
			forceBoss = true
			isBoss = true
		else
			count = (f == 1) and 1 or (num(D.EnemiesPerWave, 2) + (n - 1))
			goalEach = total * num(D.EscortMult, 0.5) / count
		end
	else
		count = (f == 1) and num(D.Floor1EnemiesPerWave, 1) or (num(D.EnemiesPerWave, 2) + (n - 1))
		local mult = D.RoomMult[r] or 1
		goalEach = total * mult / count
	end
	count = max(1, min(12, floor(count)))
	local candidates = D5.candidates(f)
	local nextInt = P4.stream((s * 131 + f * 10007 + r * 1009 + w * 101) % P4.RING_M)
	local pets = {}
	local power = 0
	local topLevel = max(1, floor(num(D.EnemyMaxLevel, 50)))
	local minH = num(D.MinHandicap, 0.3)
	for i = 1, count do
		local petId = (#candidates > 0) and candidates[nextInt(#candidates)] or "pebble_pup"
		local e, p = P4.solveEntry(petId, goalEach, topLevel, minH, forceBoss)
		pets[i] = {
			PetId = e.PetId,
			Key = e.PetId,
			Level = e.Level,
			Tier = e.Tier,
			Slot = i,
			Boss = e.Boss,
			Boost = e.Boost,
			Handicap = e.Handicap,
			Wild = true,
		}
		power = power + p
	end
	return { Pets = pets, Boss = isBoss, Power = floor(power + 0.5), Target = total, Floor = f, Room = r, Wave = w, Count = count, Name = (isBoss and "Boss" or ("Wave " .. w)) }
end

-- Loot of one room (5.2): Cash = max(20 + 10f, income x RoomSeconds[room]); Tokens wave rooms floor((6 + 4f) x waves / 2),
-- boss room (6 + 4f) x 2, x2 under Double Rewards (Cash / XP not); Xp per team pet (25 + 10f) x waves (boss room 4)
function BattleCatalog.DungeonRewards(floorIndex, room, waves, incomePerSecond, double)
	local D = BattleCatalog.Dungeon
	local f = D5.floor(floorIndex)
	local r = max(1, min(4, floor(num(tonumber(room), 1))))
	local wv = max(1, floor(num(tonumber(waves), 1)))
	local ips = tonumber(incomePerSecond)
	if not finite(ips) or ips < 0 then
		ips = 0
	end
	local mult = double and (BattleCatalog.Events.DoubleRewardsMultiplier or 2) or 1
	local seconds = D.RoomSeconds[r] or 5
	local cash = max(num(D.CashBase, 20) + num(D.CashPerFloor, 10) * f, floor(ips * seconds))
	local tokenBase = num(D.TokenBase, 6) + num(D.TokenPerFloor, 4) * f
	local tokens
	if r == 4 then
		tokens = tokenBase * 2
		wv = num(D.BossRoomWaves, 4)
	else
		tokens = floor(tokenBase * wv / 2)
	end
	return {
		Cash = floor(cash),
		Tokens = floor(tokens * mult + 0.5),
		Xp = (num(D.XpBase, 25) + num(D.XpPerFloor, 10) * f) * wv,
		Seconds = seconds,
	}
end

function BattleCatalog.DungeonFirstClear(floorIndex)
	local D = BattleCatalog.Dungeon
	local f = D5.floor(floorIndex)
	return { Tokens = num(D.FirstClearTokens, 300) * f, Gems = D.FirstClearGems[f] or 0 }
end

-- the boss chest of a run, rolled from (floor, seed): { Kind = "Cash"|"Tokens"|"Gems", Amount | Seconds }. Cash is
-- paid as Seconds of the opener's own income (DungeonService multiplies; Amount = the ChestCashMin floor).
function BattleCatalog.DungeonChest(floorIndex, seed)
	local D = BattleCatalog.Dungeon
	local f = D5.floor(floorIndex)
	local s = P4.seed(seed)
	local nextInt = P4.stream((s * 977 + f * 7) % P4.RING_M)
	local roll = nextInt(100)
	local tokens = num(D.ChestTokens.Base, 20) + num(D.ChestTokens.PerFloor, 10) * f
	if f <= num(D.ChestLowFloors, 2) then
		if roll <= 70 then
			return { Kind = "Cash", Amount = num(D.ChestCashMin, 50), Seconds = num(D.ChestCashSeconds, 30) }
		end
		return { Kind = "Tokens", Amount = tokens }
	end
	if roll <= 60 then
		return { Kind = "Cash", Amount = num(D.ChestCashMin, 50), Seconds = num(D.ChestCashSeconds, 30) }
	elseif roll <= 90 then
		return { Kind = "Tokens", Amount = tokens }
	elseif roll <= 98 then
		return { Kind = "Gems", Amount = 2 }
	end
	return { Kind = "Gems", Amount = 5 }
end

----------------------------------------------------------------------
-- Self-check
----------------------------------------------------------------------
function BattleCatalog.Validate()
	local problems = {}
	local function bad(msg)
		table.insert(problems, msg)
	end
	local pc = petCatalog()
	local validElements = {}
	for _, e in ipairs(elementOrder()) do
		validElements[e] = true
	end
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
	-- specials for every kind (the catalog's list and ours)
	local kinds = (pc and pc.SpecialKinds) or BattleCatalog.SpecialKinds
	for _, list in ipairs({ kinds, BattleCatalog.SpecialKinds }) do
		for _, kind in ipairs(list) do
			local s = BattleCatalog.Specials[kind]
			if type(s) ~= "table" then
				bad("no special effect for kind " .. tostring(kind))
			elseif type(s.Name) ~= "string" or type(s.Text) ~= "string" or not finite(s.Scale) then
				bad("special " .. kind .. " needs Name, Text and Scale")
			end
		end
	end
	for _, kind in ipairs(BattleCatalog.SupportKinds) do
		if not BattleCatalog.Buffs[kind] or BattleCatalog.Specials[kind] == nil then
			bad("Support kind " .. kind .. " needs a Buff and a Special")
		end
	end
	-- roles, the fighter kit
	local R = BattleCatalog.Roles
	if not (R.Combat and R.Support and R.Support.Power > 1 and R.Support.Health > 1 and R.Combat.Power == 1 and R.Combat.Health == 1) then
		bad("Roles: Combat 1 / 1, Support above 1")
	end
	local F = BattleCatalog.Fighter
	for _, key in ipairs({ "AttackSlack", "AttackTolerance", "ElementCooldown", "ElementMult", "ElementRange", "SpecialMeterMax", "MeterPerSecond", "MeterOnHit", "MeterOnHurt", "DashSeconds", "DashCooldown", "DashIFrames", "SwapCooldown", "SwapCastSeconds", "HelperCooldown", "SupportCooldown", "Windup", "KitFactor", "HelperWeight", "Lives", "WalkMult", "WalkMin", "WalkMax", "RunMult", "MoveSlack", "Leash", "LeashSeconds" }) do
		if not finite(F[key]) or F[key] <= 0 then
			bad("Fighter." .. key .. " must be a positive number")
		end
	end
	if not finite(F.ArriveSeconds) or F.ArriveSeconds < 0 or F.ArriveSeconds > 3 then
		bad("Fighter.ArriveSeconds must be 0..3 s")
	end
	if (F.BenchRegenPerSecond or 0) ~= 0 then
		bad("Fighter.BenchRegenPerSecond must be 0 (no passive heal in combat)")
	end
	if F.Windup <= F.DashIFrames * 0.8 then
		bad("Fighter.Windup must leave the dash i-frames room to dodge")
	end
	-- wave 6: the parry (a timed Dash)
	if not finite(F.ParryWindow) or F.ParryWindow <= 0 or F.ParryWindow > F.DashIFrames then
		bad("Fighter.ParryWindow must be above 0 and <= DashIFrames")
	end
	if not finite(F.ParryStagger) or F.ParryStagger < 0 or F.ParryStagger > 1 then
		bad("Fighter.ParryStagger must be 0..1 s")
	end
	if not finite(F.ParryMeter) or F.ParryMeter < 0 or F.ParryMeter > 30 then
		bad("Fighter.ParryMeter must be 0..30")
	end
	if not finite(F.ParryBossGap) or not finite(F.ParryStagger) or F.ParryBossGap < F.ParryStagger then
		bad("Fighter.ParryBossGap must be >= ParryStagger")
	end
	-- wave 6: Cheer up! is a really small boost with a cooldown (never a must-spam meta)
	if not finite(F.CheerBoost) or F.CheerBoost <= 0 or F.CheerBoost > 0.1 then
		bad("Fighter.CheerBoost must be above 0 and <= 0.1")
	end
	if not finite(F.CheerSeconds) or not finite(F.CheerCooldown) or F.CheerSeconds <= 0 or F.CheerSeconds >= F.CheerCooldown then
		bad("Fighter.CheerSeconds must be above 0 and below CheerCooldown")
	end
	-- wave 6: the stand-still engage rule is gone; a stray Engage* number means a half-reverted catalog
	for _, key in ipairs({ "EngageRange", "EngageLeash", "EngagePull", "EngageStillSeconds", "EngageCooldown" }) do
		if F[key] ~= nil then
			bad("Fighter." .. key .. " was removed in wave 6 (the pet fights anything in the fight area)")
		end
	end
	if F.WalkMin > F.WalkMax or F.RunMult < 1 or F.MoveSlack < 1 or F.Lives ~= 3 then
		bad("Fighter: WalkMin <= WalkMax, RunMult >= 1, MoveSlack >= 1, Lives 3")
	end
	if abs(F.WalkOf(10) - 12) > 1e-9 or abs(F.WalkOf(17.4) - 20) > 1e-9 or abs(F.RunOf(12) - 15.6) > 1e-9 then
		bad("Fighter.WalkOf / RunOf: clamp(MoveSpeed x 1.15, 12, 20) and x1.3")
	end
	-- element attacks / buffs: one per element
	for _, e in ipairs(elementOrder()) do
		local a = BattleCatalog.ElementAttacks[e]
		if type(a) ~= "table" or type(a.Name) ~= "string" then
			bad("no element attack for " .. e)
		elseif a.Shape == "Cone" and (not finite(a.Angle) or not finite(a.Length)) then
			bad("element attack " .. e .. ": a Cone needs Angle and Length")
		elseif a.Shape == "Circle" and not finite(a.Radius) then
			bad("element attack " .. e .. ": a Circle needs Radius")
		elseif a.Shape == "Line" and (not finite(a.Length) or not finite(a.Width)) then
			bad("element attack " .. e .. ": a Line needs Length and Width")
		elseif a.Shape ~= "Cone" and a.Shape ~= "Circle" and a.Shape ~= "Line" then
			bad("element attack " .. e .. ": unknown shape " .. tostring(a.Shape))
		end
		local b = BattleCatalog.Buffs[e]
		if type(b) ~= "table" or type(b.Name) ~= "string" or not finite(b.Value) or not finite(b.Seconds) or b.Cooldown ~= F.HelperCooldown then
			bad("no element buff for " .. e .. " (Name, Value, Seconds, Cooldown = HelperCooldown)")
		end
	end
	for kind, b in pairs(BattleCatalog.Buffs) do
		if b.Kind ~= kind or type(b.Text) ~= "string" or type(b.Effect) ~= "string" then
			bad("Buffs." .. kind .. " needs Kind, Effect and Text")
		end
		if not validElements[kind] and b.Cooldown ~= F.SupportCooldown then
			bad("Buffs." .. kind .. ": a Support buff's Cooldown is SupportCooldown")
		end
	end
	-- every Economy pet has a Support kind with a buff; every pet an element with a buff
	if pc and type(pc.Pets) == "table" then
		for _, def in ipairs(pc.Pets) do
			local kind = BattleCatalog.BuffOf(def)
			if kind == nil then
				bad("pet " .. tostring(def.Id) .. " has no helper buff")
			end
			if def.Role == "Economy" and (type(def.Special) ~= "table" or not BattleCatalog.Buffs[def.Special.Kind] or BattleCatalog.RoleOf(def) ~= "Support") then
				bad("Economy pet " .. tostring(def.Id) .. " is not a Support with a Support kind")
			end
		end
	end
	-- bosses
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
			if BattleCatalog.BaselineDps(id) <= 0 then
				bad("boss " .. id .. ": BaselineDps must be positive (BossRules.Baseline names a real pet)")
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
						bad("boss " .. id .. " attack " .. tostring(a.Id) .. ": Telegraph must be >= 1 s (players need time to step out)")
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
	if BattleCatalog.BossRules.GroupExponent ~= 0.2 then
		bad("BossRules.GroupExponent is 0.2 in Phase 5")
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
		bad("Raid.MinShare must be 0 or more and no higher than the lowest tier's MinShare")
	end
	if BattleCatalog.Trophies.Loss >= 0 or BattleCatalog.Trophies.Win <= 0 or BattleCatalog.Trophies.Floor ~= 0 then
		bad("Trophies: Win must be positive, Loss negative, Floor 0")
	end
	-- training, the loss rules, the Ring
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
	local LR = BattleCatalog.LossRules
	if not finite(LR.LossShare) or LR.LossShare <= 0 or LR.LossShare >= 1 or not finite(LR.LossMinSeconds) or not finite(LR.LossMinDamage) then
		bad("LossRules: LossShare in (0, 1), LossMinSeconds, LossMinDamage")
	end
	local RG = BattleCatalog.Ring
	if BattleCatalog.Zones.Ring == nil or BattleCatalog.TimeLimits.Ring ~= RG.TimeLimit then
		bad("Ring: Zones.Ring and TimeLimits.Ring = Ring.TimeLimit")
	end
	local topLevel = P4.maxLevel()
	local A = RG.LevelAnchors
	local anchorsOk = type(A) == "table" and #A >= 2 and type(A[1]) == "table" and A[1][1] == 1 and A[1][2] >= 1
	for i = 2, anchorsOk and #A or 0 do
		if not (type(A[i]) == "table" and finite(A[i][1]) and finite(A[i][2]) and A[i][1] > A[i - 1][1] and A[i][2] >= A[i - 1][2]) then
			anchorsOk = false
		end
	end
	if not anchorsOk or A[#A][2] ~= topLevel then
		bad("Ring.LevelAnchors: { round, level } pairs from { 1, >= 1 }, rounds strictly increasing, levels never falling, ending at MaxPetLevel()")
	end
	if not (finite(RG.BossLevelBump) and RG.BossLevelBump >= 0 and finite(RG.BossEvery) and RG.BossEvery >= 2) then
		bad("Ring: BossEvery >= 2 and BossLevelBump >= 0")
	end
	local from = type(RG.TierFrom) == "table" and RG.TierFrom or {}
	if not (finite(from.Golden) and finite(from.Rainbow) and from.Golden >= 1 and from.Rainbow > from.Golden and from.Rainbow <= RG.MaxRound) then
		bad("Ring.TierFrom: 1 <= Golden < Rainbow <= MaxRound")
	end
	local lastHelp = 0
	for i, h in ipairs(type(RG.Helpers) == "table" and RG.Helpers or {}) do
		if not (finite(h.From) and finite(h.Count) and h.From >= 1 and h.From <= RG.MaxRound and h.From > lastHelp and h.Count >= 2 and h.Count <= P4.maxChampions()) then
			bad("Ring.Helpers[" .. i .. "]: From in 1..MaxRound (increasing), Count 2..MaxChampions")
		end
		lastHelp = num(h.From, lastHelp)
	end
	if RG.MaxChampions ~= BattleCatalog.TeamSize then
		bad("Ring.MaxChampions = TeamSize (3)")
	end
	local tr = type(RG.Training) == "table" and RG.Training or {}
	if not (finite(tr.From) and finite(tr.To) and tr.From >= 1 and tr.To > tr.From and tr.To <= RG.MaxRound) then
		bad("Ring.Training: 1 <= From < To <= MaxRound")
	end
	if not (finite(RG.OpeningRounds) and RG.OpeningRounds >= 0 and RG.OpeningRounds <= (RG.Bands[1] and RG.Bands[1].To or 0) and RG.Bands[1].Rarities[1] == "Common") then
		bad("Ring.OpeningRounds: inside the first band (Common)")
	end
	if not (finite(RG.MaxLevelRaise) and RG.MaxLevelRaise >= 0) then
		bad("Ring.MaxLevelRaise: >= 0 (how far above the curve a picked species may be raised)")
	end
	local nextFrom = 1
	for i, b in ipairs(RG.Bands) do
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
		-- the climb (rounds 1..120, seeds 1..4): 1..3 plain pets (no Boss / Handicap / Boost), levels 1..MaxPetLevel, never
		-- EventOnly, the power never drops, three champions by round 100
		for seed = 1, 4 do
			local last = 0
			for round = 1, 120 do
				local spec = BattleCatalog.ChampionTeam(round, seed)
				if type(spec) ~= "table" or type(spec.Pets) ~= "table" or #spec.Pets < 1 or #spec.Pets > P4.maxChampions() then
					bad("ChampionTeam(" .. round .. ", " .. seed .. ") must be a team spec of 1.." .. P4.maxChampions() .. " pets")
					break
				end
				if spec.Power < last then
					bad("ChampionTeam: round " .. round .. " is weaker than round " .. (round - 1) .. " (seed " .. seed .. ")")
				end
				last = spec.Power
				for _, e in ipairs(spec.Pets) do
					if e.Boss or e.Handicap or e.Boost then
						bad("ChampionTeam: round " .. round .. " carries Boss / Handicap / Boost (champions use the player formula)")
					end
					if not (finite(e.Level) and e.Level >= 1 and e.Level <= topLevel) then
						bad("ChampionTeam: round " .. round .. " has a level outside 1..MaxPetLevel")
					end
					if pc.IsEventOnly and pc.IsEventOnly(e.PetId) then
						bad("ChampionTeam: round " .. round .. " fields an EventOnly pet")
					end
				end
				if round == 100 and #spec.Pets ~= P4.maxChampions() then
					bad("ChampionTeam: round 100 must field " .. P4.maxChampions() .. " champions")
				end
			end
		end
	end
	local rw = BattleCatalog.RingRewards(1, 0, false)
	if rw.Cash ~= RG.CashFloorBase + RG.CashFloorPerRound or rw.Xp ~= RG.XpBase + RG.XpPerRound or rw.Tokens ~= 0 then
		bad("RingRewards(1, 0, false) must pay the floor Cash and round-1 XP")
	end
	-- the Dungeon: 12 floors with existing elements, power never drops, rewards grow, first-clear tables complete, bands with pets
	local DG = BattleCatalog.Dungeon
	if DG.Floors ~= 12 or #BattleCatalog.DungeonFloors ~= 12 then
		bad("Dungeon: 12 floors")
	end
	local lastPower, lastTokens, lastXp = 0, 0, 0
	local gemTotal, tokenTotal = 0, 0
	for f = 1, #BattleCatalog.DungeonFloors do
		local info = BattleCatalog.DungeonFloors[f]
		if type(info.Name) ~= "string" or not validElements[info.Element] or type(info.Kind) ~= "string" then
			bad("DungeonFloors[" .. f .. "] needs Name, a Config element and a Kind")
		end
		local p = BattleCatalog.DungeonPower(f, 1)
		if not finite(p) or p < lastPower then
			bad("DungeonPower drops at floor " .. f)
		end
		lastPower = p
		local rw1 = BattleCatalog.DungeonRewards(f, 4, 2, 0, false)
		if rw1.Tokens <= lastTokens or rw1.Xp <= lastXp or rw1.Cash <= 0 then
			bad("DungeonRewards must grow with the floor (floor " .. f .. ")")
		end
		lastTokens, lastXp = rw1.Tokens, rw1.Xp
		local fc = BattleCatalog.DungeonFirstClear(f)
		if not finite(fc.Tokens) or fc.Tokens <= 0 or not finite(fc.Gems) or fc.Gems <= 0 then
			bad("DungeonFirstClear(" .. f .. ") incomplete")
		end
		gemTotal = gemTotal + fc.Gems
		tokenTotal = tokenTotal + fc.Tokens
		if pc and #D5.candidates(f) == 0 then
			bad("Dungeon floor " .. f .. ": no catalog pets in its band")
		end
	end
	if gemTotal ~= 156 or tokenTotal ~= 23400 then
		bad("DungeonFirstClear totals must be 23,400 Tokens / 156 Gems")
	end
	if #DG.Bands ~= 6 or DG.Bands[1][1] ~= 1 or DG.Bands[#DG.Bands][2] ~= DG.Floors then
		bad("Dungeon.Bands must cover floors 1-12")
	end
	if abs(BattleCatalog.DungeonPower(10, 1) - 2048) > 2048 * 0.01 then
		bad("DungeonPower(10, 1) must be 2048 +-1% (the old Trial 30)")
	end
	if pc then
		local w = BattleCatalog.DungeonWave(1, 1, 1, 1, 1)
		if #w.Pets ~= 1 or not (w.Pets[1].Handicap and w.Pets[1].Handicap < 1) then
			bad("DungeonWave floor 1 = one handicapped enemy")
		end
		local b = BattleCatalog.DungeonWave(3, 4, 1, 1, 1)
		if not b.Boss or #b.Pets ~= 1 or not b.Pets[1].Boss then
			bad("DungeonWave room 4 wave 1 = the boss alone in the mini-boss form")
		end
	end
	return #problems == 0, problems
end

return BattleCatalog
