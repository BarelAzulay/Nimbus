-- BattleSim: the PURE pet battle engine (ARCHITECTURE_V3.md "Phase 5 build contract" 4.3, rewritten core on the Phase 3
-- floor). No Instances, no services, no yields, no wall clock: the server steps it at 10 Hz and sends compact snapshots,
-- every client draws and interpolates. Deterministic for a seed: the same setup + the same commands (Move points
-- included) at the same steps replay the same battle. Plain Lua 5.1-compatible syntax only.
--
-- The floor is a 2D rectangle (x, z) in studs, centred on the zone centre. Phase 5: every PLAYER team is ONE FIGHTER
-- unit on the floor (the player's character is its body: BattleService feeds "Move" from the character every step)
-- plus two BENCHED helpers (not on the floor: lives, buff buttons, swaps). The player presses Attack / Element /
-- Special / Dash / Buff / Swap; the server owns reach, cooldowns, meter, lives and damage (Y1). NPC teams (side 2,
-- enemy waves, the Ring champion, raid minions) have every pet on the floor, driven by the AI: threat target, melee
-- orbit, a WIND-UP (Winding, 0.45 s) before every hit so the 0.35 s dash i-frames can dodge it. Bosses keep their
-- telegraphed patterns, minion waves and enrage. Every number lives in BattleCatalog / PetCatalog.
--
-- API (the contract):
--   BattleSim.new(setup) -> battle | nil, reason
--     setup = { Mode = "Duel" | "Raid" | "Ring" | "Dungeon" (default Duel), Seed, Id, Zone = n | { X, Z } | { w, d },
--               Teams = { team... }, Boss = bossId (Raid), Round (Ring), TimeLimit (nil = BattleCatalog.TimeLimits[Mode]),
--               Specials = false (harness: nobody casts) }
--     team  = { Owner, Side = 1 | 2, Name, Npc = bool, Auto = bool, Anchor = { x, z }, Specials = false, Wave = n,
--               Pets = { entry x 1..3 } }   entry: Key, PetId, Def, Level, Tier, Slot, Evo, Train, Boost, Handicap, Boss,
--               Wild, Xp, XpNext, Crowned, NoSpecial.  A PLAYER team (not Npc): Pets[1] = the fighter, 2-3 the bench
--               (3 lives). Npc teams: every pet is on the floor. Auto (harness): the AI plays the fighter's kit.
--               Mode Dungeon: side 2 may start empty (SpawnEnemies fills it).
--   battle:Command(owner, action, arg) -> ok, reason, extra
--     "Attack" (targetId | nil)       DIRECTS the fighter (dungeon fixes 4; it never swings by itself): Attack(id) locks that enemy,
--                                     Attack() locks the nearest targetable enemy (a press while the lock IS that one cycles to the
--                                     next nearest, by distance then id); -> true, lockId, "OutOfReach" | nil (the lock is beyond
--                                     range + radius + AttackSlack: BattleService toasts "Too far!"); refused: Down / BadTarget /
--                                     NoTarget. Echo: Order { owner, order = "Attack", target } when the lock changes.
--                                     THE AUTO-ATTACK: every step a player's fighter that is not Stunned / Casting / Dashing /
--                                     arriving, with t >= nextAttack - Interval x (1 - AttackTolerance), hits the lock when it is
--                                     targetable and within range + radius + AttackSlack, else the nearest targetable enemy in that
--                                     reach (applyDamage; nextAttack = max(nextAttack, t) + Interval). It never moves the unit.
--     "Element" (id | { x, z } | nil) cooldown Fighter.ElementCooldown; the shape of ElementAttacks[fighter.elems[1]] from the SERVER
--                                     fighter position toward the target / aim / lock / facing
--     "Special" ()                    meter >= SpecialMeterMax; offensive kinds as before; Heal / Shield / Rally / Haste act on the fighter
--     "Dash" ()                       cooldown DashCooldown -> Dashing for DashSeconds, i-frames until t + DashIFrames; the Dash event
--                                     carries the direction the client draws the PET's dash (lock / nearest enemy, else facing)
--     "Target" (unitId | nil)         lock-on; Attack / Element default to it
--     "Buff" (2 | 3)                  that helper's buff on the fighter; cooldown per helper (SupportCooldown / HelperCooldown)
--     "Swap" (2 | 3)                  fighter <-> helper; SwapCooldown; the incoming pet arrives Casting for SwapCastSeconds; refused
--                                     while Casting / Stunned
--     "Move" (x, z)                   the fighter's wanted floor point (the CHARACTER position; never from a remote): the fighter walks
--                                     toward it at <= legal run x MoveSlack (x DashSpeed / RunSpeed while Dashing), clamped to the floor
--     "Forfeit" ()                    Duel / Ring: the team is knocked out; Raid / Dungeon: RemoveTeam
--   battle:Step(dt) -> events;  battle:Snapshot();  battle:SnapshotDelta(last);  BattleSim.DecodeSnapshot(payload, prev)
--   battle:AddTeam(team) -> infos | nil, reason;  battle:RemoveTeam(owner) -> ok
--   battle:SpawnEnemies(list, opts) -> infos | nil, reason    (Dungeon / Raid: a side-2 Npc Auto team { Owner = "wave:"..n }; opts =
--                                     { Wave = n, Anchor = { x, z } (default the far +Z edge), Name, Owner })
--   battle:LivingEnemies() -> n;  battle:BossHp() -> 0..1 | nil;  battle:Finish(reason) -> ok, events  ("Cleared" = side 1 wins,
--                                     "Abandoned" / "Shutdown" / ... = no winner);  battle:Abort(reason) = Finish
--   battle:TeamOf(owner) -> { Owner, Side, Fighter = id, Bench = { id, id }, Lives, Speed = { Walk, Run }, Cooldowns = { Element, Dash,
--                                     Swap, Buff = { [slot] = seconds } }, Lock, Damage, Kills, Left, Forfeited, Units = { {id, slot, hp,
--                                     maxHp, meter, state, alive, bench}... } }
--   battle:SpeedOf(owner) -> { Walk, Run }   the fighter's current legal speeds (speed buffs / slows included)
--   battle:Result() -> nil while running, else { Mode, Reason, WinnerSide, Winners, Losers, Draw, Forfeit, BossId, Round, Damage =
--                                     { [owner] = n }, Shares, Duration, Survivors = { [owner] = lives }, Hp = { [side] = share }, Kills =
--                                     { [owner] = n }, Waves, BossHp, BossMaxHp }
--   battle:Describe() -> { BattleId, Mode, Seed, Zone = { X, Z }, TimeLimit, BossId, Round, Sides, Units = { unitInfo... } }
--   battle:StaticUnits() -> { unitInfo... }   unitInfo = { id, side, owner, slot, kind, key, petId, boss, name, species, look,
--                                     element, elements, maxHp, level, tier, scale, ranged, range, radius, special, evo, xp, xpNext,
--                                     crowned, role ("Fighter" | "Support"), buff = { Kind, Name, Seconds, Value, Cooldown },
--                                     elementAttack = { Name, Shape, Element }, bench = 2 | 3 | nil, wild, walk, run }
--   battle:Time(), IsFinished(), Owners(), BossStatus(), SetAnchor(owner, x, z)
--   BattleSim.States = { Idle 0, Moving 1, Attacking 2, Benched 3, Casting 4, Down 5, Stunned 6, Dashing 7 }  (Winding = Attacking + windup bit)
--   BattleSim.Events = { Hit, Special, KO, Telegraph, Spawn, Enrage, Order, Zone, Leave, End, Element, Dash, Buff, Swap, Windup, Wave,
--                        EnemiesDown, Speed }
-- Event shapes:
--   Hit        { from, to, dmg, elem, crit, absorbed, miss = true (dodged), burn = true, leech = n, element = name, special = kind,
--                tele, zone, attack, buffDmg = true }
--   Special    { unit, kind, name, x, z, tx, tz, target, targets, heals, shields, stunned, angle }
--   KO         { unit, by, forfeit }          Telegraph { id, boss, name, attack, shape, x, z, r | angle + length + width, at, hits, freeze, linger }
--   Spawn      { units, wave, boss, owner }   Enrage { unit }      Zone { unit, kind, x, z, r, seconds, side }     Leave { owner, units }
--   Order      { owner, order, target, rejected }   (every refused command echoes `rejected`; Attack / Target / Forfeit echo when accepted)
--   Element    { unit, element, name, x, z, angle | tx, tz, targets }
--   Dash       { unit, dir = { dx, dz } (unit vector in floor space, 0.01 steps), target (the enemy it points at | nil) }
--   Buff       { owner, unit (the helper), kind, name, until, target (the fighter), amount, heals = { { id, hp }... } (Heal:
--                the fighter + the other benched pet) }     Swap { owner, out, in, auto }
--   Speed      { owner, walk, run }   (whenever the fighter's legal speeds change: Swap, Haste / Slow start and end)
--   Windup     { unit, target, at }   Wave { index, units, left, timeLimit }   EnemiesDown { wave }   End { reason, winnerSide }
--   ARRIVAL (dungeon fixes 3): every enemy added after the start (AddTeam / SpawnEnemies waves + escorts, raid minions) arrives for
--   BattleCatalog.Fighter.ArriveSeconds (1.2): it does not act, cannot be hit (i-frames) and is never picked as the nearest target;
--   its unit info (Wave / Spawn units, StaticUnits while it lasts) carries Arrive = seconds left. A Dungeon wave added after the
--   start pushes the time limit back by the arrival (Wave.timeLimit = the new limit).
--   HEALING (dungeon fixes 7): no passive bench regen; a player's Heal special heals the fighter AND its benched pets; the Heal
--   helper buff heals the fighter and the other benched pet.
-- Wire form (SnapshotDelta / DecodeSnapshot): per changed unit the numbers  code, pos [, hp] [, meter] [, shield] [, target]
--   code = id x 1024 + lives x 256 + windup x 128 + mask x 8 + state (mask bits: 1 hp, 2 meter, 4 shield, 8 target; lives 0..3 =
--   the fighter's team lives; windup 1 while Winding), pos = (x + 200) x 10 x 4096 + (z + 200) x 10 (0.1 stud steps).
-- End rules: Duel: a side with no lives loses; both at once or the 120 s timeout -> DoubleKoByDamage (more damage dealt wins;
--   equal = Draw). Ring: no lives = loss, timeout = loss. Raid: BossDown / Wipe / Timeout / Abandoned. Dungeon: side-1 wipe ->
--   "Wipe", timeout -> "Timeout", never ends on an empty side 2 (Finish does).
-- Deleted (10.5): ATTACK / RETREAT orders, Retreating, Damage.Retreat*, the per-slot Special command, the Trial setup, Overtime,
--   Result.Level, Describe.Level.

local Shared = script.Parent

local BattleSim = {}
BattleSim.__index = BattleSim
BattleSim.Version = 5

local floor, ceil, sqrt, max, min, huge, abs = math.floor, math.ceil, math.sqrt, math.max, math.min, math.huge, math.abs
local cos, sin, atan2, pi = math.cos, math.sin, math.atan2, math.pi

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
BattleSim.States = { Idle = 0, Moving = 1, Attacking = 2, Benched = 3, Casting = 4, Down = 5, Stunned = 6, Dashing = 7 }
BattleSim.StateNames = {}
for name, code in pairs(BattleSim.States) do
	BattleSim.StateNames[code] = name
end
BattleSim.Events = {
	Hit = "Hit",
	Special = "Special",
	KO = "KO",
	Telegraph = "Telegraph",
	Spawn = "Spawn",
	Enrage = "Enrage",
	Order = "Order",
	Zone = "Zone",
	Leave = "Leave",
	End = "End",
	Element = "Element",
	Dash = "Dash",
	Buff = "Buff",
	Swap = "Swap",
	Windup = "Windup",
	Wave = "Wave",
	EnemiesDown = "EnemiesDown",
	Speed = "Speed",
}
BattleSim.Actions = { "Attack", "Element", "Special", "Dash", "Target", "Buff", "Swap", "Move", "Forfeit" }
BattleSim.Modes = { "Duel", "Raid", "Ring", "Dungeon" }
local MODE_OK = {}
for _, m in ipairs(BattleSim.Modes) do
	MODE_OK[m] = true
end
BattleSim.LineOvershoot = 6 -- studs a Line telegraph runs past the pet it is aimed at

local S_IDLE, S_MOVING, S_ATTACKING, S_BENCHED, S_CASTING, S_DOWN, S_STUNNED, S_DASHING =
	BattleSim.States.Idle, BattleSim.States.Moving, BattleSim.States.Attacking, BattleSim.States.Benched,
	BattleSim.States.Casting, BattleSim.States.Down, BattleSim.States.Stunned, BattleSim.States.Dashing
local EV = BattleSim.Events

local MAX_UNITS = 127 -- the wire code packs the id below 128 (a 16-raid is ~16 x 3 + boss + waves)
local MIN_DT, MAX_DT = 0.02, 0.5
local ZONE_TICK = 0.5
local ATTACK_POSE = 0.3 -- seconds a fighter shows Attacking after a hit
-- the wire snapshot: positions at 0.1 stud over a floor of at most 400 studs
local POS_OFFSET, POS_STEPS, POS_BASE = 200, 10, 4096
local MASK_HP, MASK_METER, MASK_SHIELD, MASK_TARGET = 1, 2, 4, 8
local CODE_WINDUP, CODE_LIVES, CODE_ID = 128, 256, 1024

----------------------------------------------------------------------
-- Lazy modules
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

local function catalog()
	return lazy("BattleCatalog")
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

local function r1(n)
	return floor(n * 10 + 0.5) / 10
end

local function num(v, default)
	if finite(v) then
		return v
	end
	return default
end

----------------------------------------------------------------------
-- Deterministic RNG (Lehmer / Park-Miller: exact in doubles, the same on every platform)
----------------------------------------------------------------------
local RNG_M = 2147483647
local RNG_A = 48271

local function seedState(seed)
	local s = tonumber(seed) or 1
	if s ~= s or s == huge or s == -huge then
		s = 1
	end
	s = floor(abs(s)) % (RNG_M - 1) + 1
	for _ = 1, 4 do
		s = (s * RNG_A) % RNG_M
	end
	return s
end

local function rand(self)
	local s = (self.rngState * RNG_A) % RNG_M
	self.rngState = s
	return s / RNG_M
end

local function randInt(self, lo, hi)
	return lo + floor(rand(self) * (hi - lo + 1))
end

----------------------------------------------------------------------
-- Catalog access with safe fallbacks (the engine must never error at runtime)
----------------------------------------------------------------------
local FALLBACK_DAMAGE = {
	HpScale = 2.6, DamageScale = 0.6, Variance = 0.2, MinHit = 1, TargetSticky = 1.6, TargetSpread = 1.35, ThreatSeconds = 3,
	MeterMax = 100, MeterStart = { 20, 50 }, MeterOnHit = 4, MeterOnHurt = 2, MeterPerSecond = 2,
	CastSeconds = 0.5, SpecialScale = 1, SeparationRadius = 3.2, RetargetSeconds = 0.5, EngageSlack = 0.6,
	NpcSpecialDelay = { 0.4, 1.4 }, KoMeterLoss = true, Slow = 0.6, Weaken = 0.85, BurnTicks = 3,
}
local FALLBACK_FIGHTER = {
	AttackSlack = 3.0, AttackTolerance = 0.85, ElementCooldown = 7, ElementMult = 2.4, ElementRange = 14, SpecialMeterMax = 100,
	MeterPerSecond = 6, MeterOnHit = 4, MeterOnHurt = 2, DashSeconds = 0.35, DashCooldown = 2.5, DashIFrames = 0.35, SwapCooldown = 10,
	SwapCastSeconds = 0.6, BenchRegenPerSecond = 0, ArriveSeconds = 1.2, DownAutoSwap = true, HelperCooldown = 15, SupportCooldown = 12, Windup = 0.45,
	KitFactor = 1.5, HelperWeight = 0.35, Lives = 3, WalkMult = 1.15, WalkMin = 12, WalkMax = 20, RunMult = 1.3, MoveSlack = 1.25,
}

local function damageRules()
	local bc = catalog()
	local d = bc and bc.Damage
	if type(d) == "table" then
		return d
	end
	return FALLBACK_DAMAGE
end

local function fighterRules()
	local bc = catalog()
	local f = bc and bc.Fighter
	if type(f) == "table" then
		return f
	end
	return FALLBACK_FIGHTER
end

local function dashSpeedFactor()
	local cfg = lazy("Config")
	local phys = cfg and cfg.Physics
	if type(phys) == "table" and finite(phys.DashSpeed) and finite(phys.RunSpeed) and phys.RunSpeed > 0 then
		return max(1, phys.DashSpeed / phys.RunSpeed)
	end
	return 85 / 27
end

local function resolveDef(entry)
	if type(entry) ~= "table" then
		return nil
	end
	if type(entry.Def) == "table" and type(entry.Def.Stats) == "table" then
		return entry.Def
	end
	local pc = petCatalog()
	local pk = petKeys()
	for k = 1, 3 do
		local c = (k == 1 and entry.Key) or (k == 2 and entry.PetId) or (k == 3 and entry.Id) or nil
		if type(c) == "string" then
			if pc and pc.Get then
				local def = pc.Get(c)
				if def then
					return def
				end
			end
			if pk and pk.DefOf then
				local ok, def = pcall(pk.DefOf, c, nil)
				if ok and type(def) == "table" and type(def.Stats) == "table" then
					return def
				end
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Geometry helpers
----------------------------------------------------------------------
local function dist(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	return sqrt(dx * dx + dz * dz)
end

local function clampToFloor(self, u)
	local hx, hz = self.zone.HalfX - u.radius, self.zone.HalfZ - u.radius
	if hx < 0.5 then
		hx = 0.5
	end
	if hz < 0.5 then
		hz = 0.5
	end
	if u.x < -hx then
		u.x = -hx
	elseif u.x > hx then
		u.x = hx
	end
	if u.z < -hz then
		u.z = -hz
	elseif u.z > hz then
		u.z = hz
	end
end

local function clampPoint(self, x, z, margin)
	local hx, hz = max(0.5, self.zone.HalfX - (margin or 1)), max(0.5, self.zone.HalfZ - (margin or 1))
	return max(-hx, min(hx, x)), max(-hz, min(hz, z))
end

local function pointInCircle(px, pz, radius, x, z, r)
	local dx, dz = px - x, pz - z
	local reach = r + radius
	return dx * dx + dz * dz <= reach * reach
end

local function pointInLine(px, pz, radius, x, z, angle, length, width)
	local dx, dz = px - x, pz - z
	local dirX, dirZ = cos(angle), sin(angle)
	local along = dx * dirX + dz * dirZ
	if along < -radius or along > length + radius then
		return false
	end
	local perp = abs(dx * dirZ - dz * dirX)
	return perp <= width / 2 + radius
end

local function inCircle(u, x, z, r)
	return pointInCircle(u.x, u.z, u.radius, x, z, r)
end

local function inLine(u, x, z, angle, length, width)
	return pointInLine(u.x, u.z, u.radius, x, z, angle, length, width)
end

-- a body inside a cone from (x, z) along `angle`, half-angle `half` (radians), `length` studs
local function inCone(u, x, z, angle, half, length)
	local dx, dz = u.x - x, u.z - z
	local d = sqrt(dx * dx + dz * dz)
	if d > length + u.radius then
		return false
	end
	if d <= u.radius + 0.5 then
		return true
	end
	local a = atan2(dz, dx) - angle
	while a > pi do
		a = a - 2 * pi
	end
	while a < -pi do
		a = a + 2 * pi
	end
	-- the body's radius widens the cone a little at its distance
	local extra = (d > 0.01) and (u.radius / d) or 0
	return abs(a) <= half + extra
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------
local function parseZone(mode, zone)
	local bc = catalog()
	local default = (bc and type(bc.Zones) == "table" and bc.Zones[mode]) or { X = 44, Z = 44 }
	local x, z = default.X, default.Z
	if finite(zone) and zone > 0 then
		x, z = zone, zone
	elseif type(zone) == "table" then
		local zx = zone.X or zone.x or zone[1]
		local zz = zone.Z or zone.z or zone[2]
		if type(zone.Size) == "table" then
			zx = zone.Size.X or zone.Size.x or zone.Size[1] or zx
			zz = zone.Size.Z or zone.Size.z or zone.Size[2] or zz
		elseif finite(zone.Size) then
			zx, zz = zone.Size, zone.Size
		end
		if finite(zx) and zx > 0 then
			x = zx
		end
		if finite(zz) and zz > 0 then
			z = zz
		end
	end
	x = max(16, min(400, x))
	z = max(16, min(400, z))
	return { X = x, Z = z, HalfX = x / 2, HalfZ = z / 2 }
end

local function newTeamRecord(self, spec, side)
	return {
		owner = spec.Owner,
		side = side,
		name = type(spec.Name) == "string" and spec.Name or nil,
		npc = spec.Npc == true,
		auto = spec.Npc == true or spec.Auto == true,
		player = spec.Npc ~= true, -- a fighter + bench team
		noSpecials = spec.Specials == false,
		units = {},
		bySlot = {},
		fighter = nil,
		lock = nil,
		wantX = nil,
		wantZ = nil,
		faceX = 0,
		faceZ = 1,
		anchorX = 0,
		anchorZ = 0,
		damage = 0,
		kills = 0,
		forfeited = false,
		left = false,
		index = #self.teams + 1,
		powerMult = {},
		healthMult = 1,
		elementReadyAt = 0,
		dashReadyAt = 0,
		swapReadyAt = 0,
		lastWalk = nil,
		lastRun = nil,
		wave = finite(spec.Wave) and floor(spec.Wave) or nil,
		alive = 0,
	}
end

-- anchor positions: duel / ring sides face each other across z; raid teams stand around the boss; dungeon waves at +Z
local function placeAnchor(self, team, spec)
	local hx, hz = self.zone.HalfX, self.zone.HalfZ
	if type(spec.Anchor) == "table" then
		local ax = spec.Anchor.x or spec.Anchor.X or spec.Anchor[1]
		local az = spec.Anchor.z or spec.Anchor.Z or spec.Anchor[2]
		if finite(ax) and finite(az) then
			team.anchorX = max(-hx + 2, min(hx - 2, ax))
			team.anchorZ = max(-hz + 2, min(hz - 2, az))
			return
		end
	end
	if self.mode == "Raid" and team.side == 1 then
		local slots = 8
		local k = (self.raidSlots or 0)
		self.raidSlots = k + 1
		local angle = -pi / 2 + (k % slots) * (2 * pi / slots) + floor(k / slots) * (pi / slots)
		local r = min(hx, hz) - 7
		team.anchorX = cos(angle) * r
		team.anchorZ = sin(angle) * r
		return
	end
	local sideTeams = 0
	for _, t in ipairs(self.teams) do
		if t.side == team.side and t ~= team then
			sideTeams = sideTeams + 1
		end
	end
	team.anchorX = (sideTeams % 2 == 0) and (sideTeams * 5) or (-(sideTeams + 1) * 5)
	team.anchorX = max(-hx + 3, min(hx - 3, team.anchorX))
	if team.side == 1 then
		team.anchorZ = -hz + 5
	else
		team.anchorZ = hz - 5
	end
end

local function meterStart(self, D, team, entry)
	-- bug batch 2 #27: BattleCatalog.MeterStart(entry, npc, wave) picks the range (players 20-50, NPC units 45-75, the
	-- Ring champion and dungeon waves 2+ at 80); one rand draw either way, so seeded fights keep their RNG order
	local bc = catalog()
	if bc and bc.MeterStart then
		local lo, hi = bc.MeterStart(entry, team and team.npc, team and team.wave)
		if finite(lo) and finite(hi) then
			return lo + (hi - lo) * rand(self)
		end
	end
	local ms = D.MeterStart
	if type(ms) == "table" then
		local lo, hi = num(ms[1], 0), num(ms[2], 0)
		return lo + (hi - lo) * rand(self)
	end
	return num(ms, 0)
end

local function unitFromDef(self, team, def, entry, slot, kind)
	local bc = catalog()
	local us = bc and bc.UnitStats and bc.UnitStats(def, entry.Level, entry.Tier, entry)
	if not us then
		return nil
	end
	local D = damageRules()
	local id = #self.units + 1
	if id > MAX_UNITS then
		return nil
	end
	local maxHp = us.MaxHp * (team.healthMult or 1)
	local hit = us.Hit
	local radius = us.Radius
	local scale = 1
	local specialPower = us.SpecialPower
	if kind == "MiniBoss" then
		local mb = (bc and bc.MiniBoss) or { Hp = 3, Power = 1.3, Scale = 1.7 }
		maxHp = maxHp * mb.Hp
		hit = hit * mb.Power
		radius = radius * 1.4
		scale = mb.Scale
	end
	if finite(entry.Handicap) and entry.Handicap > 0 and entry.Handicap < 1 then
		maxHp = maxHp * entry.Handicap
		hit = hit * entry.Handicap
		specialPower = specialPower * entry.Handicap
	end
	local special = type(def.Special) == "table" and def.Special or nil
	local buffKind, buffDef = nil, nil
	if bc and bc.BuffOf then
		buffKind, buffDef = bc.BuffOf(def)
	end
	local u = {
		id = id,
		side = team.side,
		team = team,
		owner = team.owner,
		slot = slot,
		kind = kind,
		def = def,
		key = entry.Key or def.Key or def.Id,
		petId = entry.PetId or def.PetId or def.Id,
		name = def.DisplayName or def.Name or tostring(def.Id),
		species = us.Species,
		elems = us.Elements,
		role = us.Role or "Combat",
		maxHp = maxHp,
		hp = maxHp,
		hit = hit,
		interval = us.Interval,
		moveSpeed = us.MoveSpeed,
		walk = us.Walk,
		run = us.Run,
		range = us.Range,
		ranged = us.Ranged,
		radius = radius,
		specialPower = specialPower,
		specialFactor = min(1, num(us.SpecialFactor, 1)),
		specialKind = (special and not entry.NoSpecial) and special.Kind or nil,
		special = special,
		specialBoost = num(us.SpecialBoost, 1),
		buffKind = buffKind,
		buffDef = buffDef,
		powerMult = team.powerMult[slot] or 1,
		level = num(entry.Level, 1),
		tier = entry.Tier or def.Tier or "Normal",
		scale = scale,
		evo = num(us.Evo, 0),
		train = us.Train,
		boost = (finite(us.Boost) and us.Boost > 1) and us.Boost or nil,
		defense = max(0, min(0.9, num(us.Defense, 0))),
		meterRate = max(0.1, num(us.MeterRate, 1)),
		xp = (finite(entry.Xp) and entry.Xp >= 0) and floor(entry.Xp) or nil,
		xpNext = (finite(entry.XpNext) and entry.XpNext >= 0) and floor(entry.XpNext) or nil,
		crowned = entry.Crowned == true or nil,
		wild = entry.Wild == true or nil,
		x = 0,
		z = 0,
		px = 0,
		pz = 0,
		state = S_IDLE,
		target = nil,
		nextAttack = self.t + rand(self) * us.Interval * 0.6,
		retargetAt = 0,
		meter = meterStart(self, D, team, entry),
		shield = 0,
		shieldUntil = 0,
		stunUntil = 0,
		castUntil = 0,
		autoCastAt = nil,
		alive = true,
		gone = false,
		benched = false,
		damage = 0,
		kills = 0,
		-- the fighter kit
		attackUntil = 0,
		dashUntil = 0,
		iframesUntil = 0,
		buffReadyAt = 0,
		-- statuses
		slowUntil = 0,
		weakenUntil = 0,
		burnLeft = 0,
		burnAmount = 0,
		burnNextAt = 0,
		burnFrom = nil,
		dmgBuffUntil = 0,
		dmgBuffMult = 1,
		speedBuffUntil = 0,
		speedBuffMult = 1,
		atkSpeedUntil = 0,
		atkSpeedMult = 1,
		takenUntil = 0,
		takenMult = 1,
		regenUntil = 0,
		regenRate = 0,
		chillUntil = 0,
		chillValue = 0,
		leechUntil = 0,
		leechValue = 0,
		-- NPC wind-up
		windAt = nil,
		windTarget = nil,
		threat = nil,
		threatAt = -huge,
	}
	self.units[id] = u
	return u
end

-- NPC pets stand near their anchor, offset per slot toward the floor centre; a player's fighter stands at its anchor
local function placeTeamUnits(self, team)
	local cx, cz = -team.anchorX, -team.anchorZ
	local len = sqrt(cx * cx + cz * cz)
	if len < 0.01 then
		cx, cz, len = 0, 1, 1
	end
	cx, cz = cx / len, cz / len
	local px, pz = -cz, cx
	local n = #team.units
	for i, u in ipairs(team.units) do
		local spread = team.player and 0 or (i - (n + 1) / 2) * 2.6
		u.x = team.anchorX + cx * 3 + px * spread
		u.z = team.anchorZ + cz * 3 + pz * spread
		clampToFloor(self, u)
		u.px, u.pz = u.x, u.z
	end
	team.faceX, team.faceZ = cx, cz
end

local function unitInfo(u, t)
	local info = {
		id = u.id,
		side = u.side,
		owner = u.owner,
		slot = u.slot,
		kind = u.kind,
		key = u.key,
		petId = u.petId,
		name = u.name,
		species = u.species,
		look = type(u.def) == "table" and u.def.Look or nil,
		element = u.elems[1],
		elements = u.elems,
		maxHp = floor(u.maxHp + 0.5),
		level = u.level,
		tier = u.tier,
		scale = u.scale,
		ranged = u.ranged,
		range = u.range,
		radius = u.radius,
		role = (u.role == "Support") and "Support" or "Fighter",
		walk = u.walk,
		run = u.run,
	}
	if u.boss then
		info.boss = u.boss.Id
	elseif u.kind == "MiniBoss" then
		info.boss = true
	end
	info.evo = u.evo or 0
	if u.xp then
		info.xp = u.xp
		info.xpNext = u.xpNext
	end
	if u.crowned then
		info.crowned = true
	end
	if u.wild then
		info.wild = true
	end
	if t and u.arriveUntil and t < u.arriveUntil then
		info.Arrive = r1(u.arriveUntil - t)
	end
	if u.team and u.team.player and u.slot and u.slot >= 2 then
		info.bench = u.slot
	end
	if u.special then
		info.special = { Id = u.special.Id, Name = u.special.Name, Kind = u.special.Kind, Color = u.special.Color }
	end
	if u.buffDef then
		info.buff = { Kind = u.buffKind, Name = u.buffDef.Name, Seconds = u.buffDef.Seconds, Value = u.buffDef.Value, Cooldown = u.buffDef.Cooldown }
	end
	local bc = catalog()
	local ea = bc and type(bc.ElementAttacks) == "table" and u.elems[1] and bc.ElementAttacks[u.elems[1]]
	if ea then
		info.elementAttack = { Name = ea.Name, Shape = ea.Shape, Element = u.elems[1] }
	end
	return info
end

-- the lives of a team = its living pets (fighter + bench; NPC: every pet still up)
local function teamLives(team)
	local n = 0
	for _, u in ipairs(team.units) do
		if u.alive and not u.gone then
			n = n + 1
		end
	end
	return n
end

local function onFloor(u)
	return u.alive and not u.gone and not u.benched
end

-- dungeon fixes (3): the entrance of an enemy added after the start: no acting, no hits (i-frames), not the nearest target
local function arriveSeconds()
	local s = num(fighterRules().ArriveSeconds, 1.2)
	return max(0, min(3, s))
end

local function markArrival(self, u, seconds)
	if seconds > 0 then
		u.arriveUntil = self.t + seconds
		if (u.iframesUntil or 0) < u.arriveUntil then
			u.iframesUntil = u.arriveUntil
		end
		u.nextAttack = max(u.nextAttack, u.arriveUntil)
	end
end

local function arriving(self, u)
	return u.arriveUntil ~= nil and self.t < u.arriveUntil
end

-- a living enemy on the floor that may be chosen as a target (not arriving)
local function targetable(self, e)
	return e.alive and not e.gone and not e.benched and not (e.arriveUntil and self.t < e.arriveUntil)
end

-- Adds a team (also used by new / SpawnEnemies). Returns the unit infos, or nil + reason.
function BattleSim:AddTeam(spec)
	if self.result then
		return nil, "Finished"
	end
	if type(spec) ~= "table" or spec.Owner == nil then
		return nil, "BadTeam"
	end
	if self.teamByOwner[spec.Owner] then
		return nil, "DuplicateOwner"
	end
	local side = spec.Side
	if side ~= 1 and side ~= 2 then
		side = 1
	end
	local bc = catalog()
	local player = spec.Npc ~= true
	local maxSize = player and ((bc and bc.TeamSize) or 3) or 12
	local pets = type(spec.Pets) == "table" and spec.Pets or {}
	local defs, entries = {}, {}
	for i = 1, min(#pets, maxSize) do
		local entry = pets[i]
		local def = resolveDef(entry)
		if def then
			defs[#defs + 1] = def
			entries[#entries + 1] = entry
		end
	end
	if #defs == 0 then
		return nil, "NoPets"
	end
	local team = newTeamRecord(self, spec, side)
	local synPower = {}
	if bc and bc.SynergyBonus then
		local syn = bc.SynergyBonus(defs)
		team.healthMult = syn.HealthMult or 1
		for i = 1, #defs do
			synPower[i] = syn.PowerMult[i] or 1
		end
	end
	self.teams[#self.teams + 1] = team
	self.teamByOwner[spec.Owner] = team
	placeAnchor(self, team, spec)
	local infos = {}
	for i, def in ipairs(defs) do
		local entry = entries[i]
		local slot = i
		if player then
			slot = i -- a player's slots are the list order: 1 = the fighter, 2-3 the bench
		elseif finite(entry.Slot) and entry.Slot >= 1 and entry.Slot <= maxSize and not team.bySlot[floor(entry.Slot)] then
			slot = floor(entry.Slot)
		end
		team.powerMult[slot] = synPower[i] or 1
		local kind = entry.Boss and "MiniBoss" or "Pet"
		local u = unitFromDef(self, team, def, entry, slot, kind)
		if u then
			team.units[#team.units + 1] = u
			team.bySlot[slot] = u
			infos[#infos + 1] = u
			if player then
				if i == 1 then
					team.fighter = u
				else
					u.benched = true
					u.state = S_BENCHED
				end
			end
		end
	end
	if #team.units == 0 then
		self.teams[#self.teams] = nil
		self.teamByOwner[spec.Owner] = nil
		return nil, "NoPets"
	end
	placeTeamUnits(self, team)
	if player and team.fighter then
		for _, u in ipairs(team.units) do
			u.x, u.z, u.px, u.pz = team.fighter.x, team.fighter.z, team.fighter.x, team.fighter.z
		end
	end
	if bc and bc.ExpectedDps then
		team.dps = player and bc.ExpectedDps({ Pets = entries }) or 0
	else
		team.dps = 0
	end
	-- an enemy team added after the start (waves, escorts, mid-fight adds) arrives first
	local arrive = 0
	if self.started and side == 2 and not player then
		arrive = arriveSeconds()
		for _, u in ipairs(infos) do
			markArrival(self, u, arrive)
		end
	end
	local out = {}
	for i, u in ipairs(infos) do
		out[i] = unitInfo(u, self.t)
	end
	if team.wave then
		self.waveCount = max(self.waveCount or 0, team.wave)
	end
	if self.started then
		local boss = self.boss
		if boss and boss.alive and player and side == 1 then
			local before = boss.maxHp
			boss.maxHp = self:_bossMaxHp()
			boss.hp = max(1, boss.hp + (boss.maxHp - before))
		end
		self:_refreshRaidScale()
		if team.wave then
			local left = 0
			for _, v in ipairs(self.units) do
				if v.side == 2 and onFloor(v) then
					left = left + 1
				end
			end
			-- a dungeon room's clock does not run down while its new wave cannot be hit
			if self.mode == "Dungeon" and arrive > 0 then
				self.timeLimit = self.timeLimit + arrive
			end
			self.pending[#self.pending + 1] = { type = EV.Wave, index = team.wave, units = out, left = left, owner = spec.Owner, timeLimit = self.timeLimit }
		else
			self.pending[#self.pending + 1] = { type = EV.Spawn, units = out, owner = spec.Owner }
		end
	end
	return out
end

-- Dungeon / Raid: an enemy wave as a side-2 Npc Auto team
function BattleSim:SpawnEnemies(list, opts)
	opts = type(opts) == "table" and opts or {}
	local index = finite(opts.Wave) and floor(opts.Wave) or ((self.waveCount or 0) + 1)
	local anchor = opts.Anchor
	if type(anchor) ~= "table" then
		anchor = { 0, self.zone.HalfZ - 5 }
	end
	local pets = type(list) == "table" and (list.Pets or list) or {}
	local owner = opts.Owner or ("wave:" .. index)
	return self:AddTeam({ Owner = owner, Side = 2, Npc = true, Auto = true, Name = opts.Name or ("Wave " .. index), Anchor = anchor, Wave = index, Pets = pets })
end

-- BattleCatalog.BossHp over the player teams still in the raid
function BattleSim:_bossMaxHp()
	local bc = catalog()
	local specs = {}
	for _, t in ipairs(self.teams) do
		if t.side == 1 and t.player and not t.left then
			local pets = {}
			for j, u in ipairs(t.units) do
				pets[j] = { Def = u.def, Level = u.level, Tier = u.tier, Evo = u.evo, Train = u.train, Boost = u.boost }
			end
			specs[#specs + 1] = { Pets = pets }
		end
	end
	if bc and bc.BossHp then
		local hp = bc.BossHp(self.bossId, specs)
		if finite(hp) and hp > 0 then
			return hp
		end
	end
	return 1000
end

function BattleSim:_playerTeams()
	local n = 0
	for _, team in ipairs(self.teams) do
		if team.side == 1 and team.player and not team.left then
			n = n + 1
		end
	end
	return n
end

function BattleSim:_effectiveTeams(excluding)
	local dpsList = {}
	for _, team in ipairs(self.teams) do
		if team.side == 1 and team.player and not team.left and team ~= excluding then
			dpsList[#dpsList + 1] = num(team.dps, 0)
		end
	end
	local bc = catalog()
	if bc and bc.WeightedTeams then
		return bc.WeightedTeams(dpsList)
	end
	return #dpsList
end

local bossBasis

-- The boss's damage yardstick: the average FIGHTER MaxHp (and level) over the player teams
function BattleSim:_refreshRaidScale()
	local total, n, levels = 0, 0, 0
	for _, team in ipairs(self.teams) do
		if team.side == 1 and not team.left then
			for _, u in ipairs(team.units) do
				if (u.kind == "Pet" or u.kind == "MiniBoss") and (not team.player or u == team.fighter) then
					total = total + u.maxHp
					levels = levels + (u.level or 1)
					n = n + 1
				end
			end
		end
	end
	if n > 0 then
		self.avgPetHp = total / n
		self.avgPetLevel = floor(levels / n + 0.5)
	end
	if not self.avgPetHp or self.avgPetHp <= 0 then
		self.avgPetHp = 150
		self.avgPetLevel = 1
	end
	self.playerTeamCount = self:_effectiveTeams()
	for _, u in ipairs(self.units) do
		if u.kind == "Minion" and u.alive then
			local rules = (catalog() and catalog().BossRules) or {}
			u.hit = num(rules.MinionDamage, 0.05) * bossBasis(self, { maxHp = self.avgPetHp })
		end
	end
end

local function makeBoss(self, bossId)
	local bc = catalog()
	local def = bc and type(bc.Bosses) == "table" and bc.Bosses[bossId]
	if not def then
		return nil, "UnknownBoss"
	end
	local id = #self.units + 1
	local team = newTeamRecord(self, { Owner = "boss", Name = def.Name, Npc = true, Auto = true }, 2)
	team.dps = 0
	self.teams[#self.teams + 1] = team
	self.teamByOwner["boss"] = team
	self.bossId = bossId
	local hp = self:_bossMaxHp()
	local attacks = {}
	for i, a in ipairs(def.Attacks or {}) do
		attacks[i] = { def = a, nextAt = num(a.First, 6 + i * 6) }
	end
	local u = {
		id = id,
		side = 2,
		team = team,
		owner = "boss",
		slot = 1,
		kind = "Boss",
		def = def,
		boss = def,
		key = bossId,
		petId = nil,
		name = def.Name,
		species = nil,
		elems = { def.Element },
		role = "Combat",
		maxHp = hp,
		hp = hp,
		hit = 0,
		interval = num(def.Basic and def.Basic.Interval, 2.5),
		moveSpeed = 0,
		range = num(def.Basic and def.Basic.Range, 14),
		ranged = true,
		radius = num(def.Radius, 7),
		specialPower = 0,
		special = nil,
		powerMult = 1,
		level = 1,
		tier = "Boss",
		scale = num(def.Scale, 1),
		x = 0,
		z = 0,
		px = 0,
		pz = 0,
		state = S_IDLE,
		target = nil,
		nextAttack = 3,
		retargetAt = 0,
		meter = 0,
		shield = 0,
		shieldUntil = 0,
		stunUntil = 0,
		castUntil = 0,
		alive = true,
		gone = false,
		benched = false,
		damage = 0,
		kills = 0,
		attacks = attacks,
		wavesDone = {},
		enraged = false,
		damageMult = 1,
		cooldownMult = 1,
		attackUntil = 0,
		dashUntil = 0,
		iframesUntil = 0,
		buffReadyAt = 0,
		slowUntil = 0,
		weakenUntil = 0,
		burnLeft = 0,
		burnAmount = 0,
		burnNextAt = 0,
		dmgBuffUntil = 0,
		dmgBuffMult = 1,
		speedBuffUntil = 0,
		speedBuffMult = 1,
		atkSpeedUntil = 0,
		atkSpeedMult = 1,
		takenUntil = 0,
		takenMult = 1,
		regenUntil = 0,
		regenRate = 0,
		chillUntil = 0,
		chillValue = 0,
		leechUntil = 0,
		leechValue = 0,
		threatAt = -huge,
	}
	self.units[id] = u
	team.units[1] = u
	team.bySlot[1] = u
	self.boss = u
	return u
end

function BattleSim.new(setup)
	if type(setup) ~= "table" then
		return nil, "BadSetup"
	end
	local mode = setup.Mode
	if not MODE_OK[mode] then
		mode = (setup.Boss ~= nil and "Raid") or "Duel"
	end
	local bc = catalog()
	local self = setmetatable({}, BattleSim)
	self.id = setup.Id
	self.mode = mode
	self.seed = tonumber(setup.Seed) or 1
	self.rngState = seedState(self.seed)
	self.t = 0
	self.stepCount = 0
	self.zone = parseZone(mode, setup.Zone)
	self.teams = {}
	self.teamByOwner = {}
	self.units = {}
	self.telegraphs = {}
	self.zones = {}
	self.pending = {}
	self.order = {}
	self.order2 = {}
	self.result = nil
	self.started = false
	self.specialsEnabled = setup.Specials ~= false
	self.elemCache = {}
	self.nextTelegraphId = 1
	self.avgPetHp = 150
	self.avgPetLevel = 1
	self.waveCount = 0
	local limits = (bc and bc.TimeLimits) or { Duel = 120, Raid = 330, Ring = 90, Dungeon = 120 }
	self.timeLimit = num(setup.TimeLimit, limits[mode] or 120)
	if mode == "Ring" and finite(setup.Round) then
		self.round = floor(setup.Round)
	end
	local mh = damageRules().MaxHit
	if type(mh) == "table" and type(mh.Modes) == "table" and mh.Modes[mode] and finite(mh.Share) and mh.Share > 0 then
		self.maxHitShare = mh.Share
	end
	local teams = type(setup.Teams) == "table" and setup.Teams or {}
	for _, spec in ipairs(teams) do
		if type(spec) == "table" then
			local infos, reason = self:AddTeam(spec)
			if not infos and reason == "DuplicateOwner" then
				return nil, reason
			end
		end
	end
	if setup.Boss ~= nil then
		local boss, reason = makeBoss(self, setup.Boss)
		if not boss then
			return nil, reason
		end
		if setup.TimeLimit == nil and finite(boss.boss.TimeLimit) then
			self.timeLimit = boss.boss.TimeLimit
		end
	end
	local side1, side2 = 0, 0
	for _, team in ipairs(self.teams) do
		if team.side == 1 then
			side1 = side1 + #team.units
		else
			side2 = side2 + #team.units
		end
	end
	if side1 == 0 then
		return nil, "NoTeam"
	end
	if side2 == 0 and mode ~= "Dungeon" then
		return nil, "NoOpponent"
	end
	self:_refreshRaidScale()
	self.started = true
	return self
end

----------------------------------------------------------------------
-- Read-only accessors
----------------------------------------------------------------------
function BattleSim:Time()
	return self.t
end

function BattleSim:IsFinished()
	return self.result ~= nil
end

function BattleSim:Result()
	return self.result
end

function BattleSim:Owners()
	local out = {}
	for _, team in ipairs(self.teams) do
		if team.player and not team.left then
			out[#out + 1] = team.owner
		end
	end
	return out
end

function BattleSim:StaticUnits()
	local out = {}
	for _, u in ipairs(self.units) do
		if not u.gone then
			out[#out + 1] = unitInfo(u, self.t)
		end
	end
	return out
end

function BattleSim:Describe()
	local sides = { [1] = {}, [2] = {} }
	for _, team in ipairs(self.teams) do
		if not team.left then
			local list = sides[team.side]
			list[#list + 1] = team.owner
		end
	end
	return {
		BattleId = self.id,
		Mode = self.mode,
		Seed = self.seed,
		Zone = { X = self.zone.X, Z = self.zone.Z },
		TimeLimit = self.timeLimit,
		BossId = self.bossId,
		Round = self.round,
		Sides = sides,
		Units = self:StaticUnits(),
	}
end

-- the fighter's current legal speeds (walk, run) with Haste / Slow applied
local function legalSpeeds(self, team)
	local f = team.fighter
	if not f then
		return 0, 0
	end
	local mult = 1
	if self.t < f.speedBuffUntil then
		mult = mult * f.speedBuffMult
	end
	if self.t < f.slowUntil then
		mult = mult * num(damageRules().Slow, 0.6)
	end
	return num(f.walk, 12) * mult, num(f.run, 15.6) * mult
end

function BattleSim:SpeedOf(owner)
	local team = self.teamByOwner[owner]
	if not team or not team.fighter then
		return nil
	end
	local walk, run = legalSpeeds(self, team)
	return { Walk = walk, Run = run }
end

function BattleSim:TeamOf(owner)
	local team = self.teamByOwner[owner]
	if not team then
		return nil
	end
	local t = self.t
	local units = {}
	local bench = {}
	local buffs = {}
	for i, u in ipairs(team.units) do
		units[i] = { id = u.id, slot = u.slot, hp = u.hp, maxHp = u.maxHp, meter = u.meter, state = u.state, alive = u.alive, bench = u.benched or nil }
		if team.player and u ~= team.fighter then
			bench[#bench + 1] = u.id
			buffs[u.slot] = max(0, u.buffReadyAt - t)
		end
	end
	local walk, run = legalSpeeds(self, team)
	return {
		Owner = team.owner,
		Side = team.side,
		Fighter = team.fighter and team.fighter.id or nil,
		Bench = bench,
		Lives = teamLives(team),
		Speed = { Walk = walk, Run = run },
		Cooldowns = {
			Element = max(0, team.elementReadyAt - t),
			Dash = max(0, team.dashReadyAt - t),
			Swap = max(0, team.swapReadyAt - t),
			Buff = buffs,
		},
		Lock = team.lock and team.lock.id or nil,
		Damage = team.damage,
		Kills = team.kills,
		Left = team.left,
		Forfeited = team.forfeited,
		Units = units,
	}
end

function BattleSim:BossStatus()
	local b = self.boss
	if not b then
		return nil
	end
	return {
		BossId = self.bossId,
		Name = b.name,
		Hp = max(0, floor(b.hp + 0.5)),
		MaxHp = floor(b.maxHp + 0.5),
		Enraged = b.enraged,
		EndsIn = max(0, self.timeLimit - self.t),
		Players = self:_playerTeams(),
	}
end

-- the side-2 boss's HP share (the raid boss, else a side-2 unit in the mini-boss form), nil without one
function BattleSim:BossHp()
	local b = self.boss
	if not b then
		for _, u in ipairs(self.units) do
			if u.side == 2 and u.kind == "MiniBoss" and not u.gone then
				b = u
				break
			end
		end
	end
	if not b or b.maxHp <= 0 then
		return nil
	end
	return max(0, min(1, b.hp / b.maxHp))
end

function BattleSim:LivingEnemies()
	local n = 0
	for _, u in ipairs(self.units) do
		if u.side == 2 and onFloor(u) then
			n = n + 1
		end
	end
	return n
end

function BattleSim:SetAnchor(owner, x, z)
	local team = self.teamByOwner[owner]
	if not team or not finite(x) or not finite(z) then
		return false
	end
	local hx, hz = self.zone.HalfX, self.zone.HalfZ
	team.anchorX = max(-hx + 2, min(hx - 2, x))
	team.anchorZ = max(-hz + 2, min(hz - 2, z))
	return true
end

----------------------------------------------------------------------
-- Snapshot
----------------------------------------------------------------------
local function unitLives(u)
	if u.team and u.team.player and u == u.team.fighter then
		return min(3, teamLives(u.team))
	end
	return 0
end

local function isWinding(self, u)
	return u.windAt ~= nil and self.t < u.windAt
end

function BattleSim:Snapshot()
	local units = {}
	local list = self.units
	for i = 1, #list do
		local u = list[i]
		if not u.gone then
			local hp = 0
			if u.alive then
				hp = ceil(u.hp - 0.0001)
				if hp < 1 then
					hp = 1
				end
			end
			local s = { x = r1(u.x), z = r1(u.z), hp = hp, state = u.state, meter = floor(u.meter + 0.5), lives = unitLives(u) }
			local tgt = u.target
			if tgt and tgt.alive and not tgt.gone then
				s.target = tgt.id
			end
			if u.shield > 0 then
				s.shield = floor(u.shield + 0.5)
			end
			if isWinding(self, u) then
				s.windup = true
			end
			units[u.id] = s
		end
	end
	return { BattleId = self.id, T = r1(self.t), Units = units }
end

function BattleSim:SnapshotDelta(last)
	if type(last) ~= "table" then
		last = {}
	end
	local U = {}
	local n = 0
	local list = self.units
	for i = 1, #list do
		local u = list[i]
		if not u.gone then
			local hp = 0
			if u.alive then
				hp = ceil(u.hp - 0.0001)
				if hp < 1 then
					hp = 1
				end
			end
			local x, z = r1(u.x), r1(u.z)
			local meter = floor(u.meter + 0.5)
			local shield = u.shield > 0 and floor(u.shield + 0.5) or 0
			local tgt = u.target
			local target = (tgt and tgt.alive and not tgt.gone) and tgt.id or 0
			local lives = unitLives(u)
			local windup = isWinding(self, u) and 1 or 0
			local l = last[u.id]
			local mask = 0
			if not l then
				l = {}
				last[u.id] = l
				mask = MASK_HP + MASK_METER + MASK_SHIELD + MASK_TARGET
			else
				if l.hp ~= hp then
					mask = mask + MASK_HP
				end
				if l.meter ~= meter then
					mask = mask + MASK_METER
				end
				if l.shield ~= shield then
					mask = mask + MASK_SHIELD
				end
				if (l.target or 0) ~= target then
					mask = mask + MASK_TARGET
				end
			end
			if mask > 0 or l.x ~= x or l.z ~= z or l.state ~= u.state or (l.lives or 0) ~= lives or ((l.windup and 1 or 0) ~= windup) then
				l.x, l.z, l.hp, l.state, l.meter, l.shield, l.lives = x, z, hp, u.state, meter, shield, lives
				l.windup = (windup == 1) or nil
				l.target = (target ~= 0) and target or nil
				local xi = floor((max(-POS_OFFSET, min(POS_OFFSET, x)) + POS_OFFSET) * POS_STEPS + 0.5)
				local zi = floor((max(-POS_OFFSET, min(POS_OFFSET, z)) + POS_OFFSET) * POS_STEPS + 0.5)
				U[n + 1] = u.id * CODE_ID + lives * CODE_LIVES + windup * CODE_WINDUP + mask * 8 + u.state
				U[n + 2] = xi * POS_BASE + zi
				n = n + 2
				if mask % (MASK_HP * 2) >= MASK_HP then
					n = n + 1
					U[n] = hp
				end
				if mask % (MASK_METER * 2) >= MASK_METER then
					n = n + 1
					U[n] = meter
				end
				if mask % (MASK_SHIELD * 2) >= MASK_SHIELD then
					n = n + 1
					U[n] = shield
				end
				if mask % (MASK_TARGET * 2) >= MASK_TARGET then
					n = n + 1
					U[n] = target
				end
			end
		end
	end
	return { BattleId = self.id, T = r1(self.t), U = U }
end

function BattleSim.DecodeSnapshot(payload, previous)
	local out = {}
	if type(previous) == "table" then
		for id, rec in pairs(previous) do
			out[id] = rec
		end
	end
	local U = type(payload) == "table" and payload.U
	if type(U) ~= "table" then
		return out
	end
	local i = 1
	local n = #U
	while i + 1 <= n do
		local code, pos = U[i], U[i + 1]
		if not finite(code) or not finite(pos) or code ~= floor(code) or code < CODE_ID or pos ~= floor(pos) or pos < 0 then
			break
		end
		local state = code % 8
		local mask = floor(code / 8) % 16
		local windup = floor(code / CODE_WINDUP) % 2
		local lives = floor(code / CODE_LIVES) % 4
		local id = floor(code / CODE_ID)
		local xi = floor(pos / POS_BASE)
		local zi = pos % POS_BASE
		local prev = out[id]
		local rec = {
			x = xi / POS_STEPS - POS_OFFSET,
			z = zi / POS_STEPS - POS_OFFSET,
			state = state,
			lives = lives,
			windup = (windup == 1) or nil,
			hp = prev and prev.hp or nil,
			meter = prev and prev.meter or 0,
			shield = prev and prev.shield or 0,
			target = prev and prev.target or nil,
		}
		i = i + 2
		if mask % (MASK_HP * 2) >= MASK_HP then
			rec.hp = tonumber(U[i])
			i = i + 1
		end
		if mask % (MASK_METER * 2) >= MASK_METER then
			rec.meter = tonumber(U[i]) or 0
			i = i + 1
		end
		if mask % (MASK_SHIELD * 2) >= MASK_SHIELD then
			rec.shield = tonumber(U[i]) or 0
			i = i + 1
		end
		if mask % (MASK_TARGET * 2) >= MASK_TARGET then
			local target = tonumber(U[i]) or 0
			rec.target = (target > 0) and target or nil
			i = i + 1
		end
		if i > n + 1 then
			break
		end
		out[id] = rec
	end
	return out
end

----------------------------------------------------------------------
-- Damage
----------------------------------------------------------------------
local function elemMult(self, attacker, victim)
	local key = attacker.id * 256 + victim.id
	local m = self.elemCache[key]
	if m == nil then
		m = 1
		local pc = petCatalog()
		if pc and pc.ElementMultiplier and #attacker.elems > 0 and #victim.elems > 0 then
			local ok, result = pcall(pc.ElementMultiplier, attacker.elems, victim.elems)
			if ok and finite(result) then
				m = result
			end
		end
		self.elemCache[key] = m
	end
	return m
end

local swapIn -- forward (the auto-swap on a fighter's KO)

local function knockOut(self, u, by, events, forfeit)
	u.alive = false
	u.hp = 0
	u.state = S_DOWN
	u.target = nil
	u.shield = 0
	u.windAt = nil
	u.windTarget = nil
	u.burnLeft = 0
	if damageRules().KoMeterLoss then
		u.meter = 0
	end
	if by and by.alive then
		by.kills = by.kills + 1
		by.team.kills = by.team.kills + 1
	end
	local ev = { type = EV.KO, unit = u.id, by = by and by.id or nil }
	if forfeit then
		ev.forfeit = true
	end
	events[#events + 1] = ev
	local team = u.team
	-- a downed fighter is replaced by the next alive helper at once (3 lives)
	if team.player and u == team.fighter and not forfeit and fighterRules().DownAutoSwap ~= false then
		for _, v in ipairs(team.units) do
			if v.alive and not v.gone and v.benched then
				swapIn(self, team, v, events, true)
				break
			end
		end
	end
	-- the last enemy of a spawned wave fell
	if team.wave and not team.left then
		local left = 0
		for _, v in ipairs(team.units) do
			if v.alive and not v.gone then
				left = left + 1
			end
		end
		if left == 0 then
			events[#events + 1] = { type = EV.EnemiesDown, wave = team.wave, owner = team.owner }
		end
	end
end

-- the attacker's damage multiplier from its buffs / statuses (Rally / Blaze, Weaken)
local function attackMult(self, attacker)
	local m = 1
	if attacker.dmgBuffUntil and self.t < attacker.dmgBuffUntil then
		m = m * attacker.dmgBuffMult
	end
	if attacker.weakenUntil and self.t < attacker.weakenUntil then
		m = m * num(damageRules().Weaken, 0.85)
	end
	return m
end

-- Applies `amount` of damage from `attacker` (may be nil for zones) to `victim`. Returns the damage dealt (after
-- shields). `extra` fields are copied into the Hit event; extra == nil marks a plain attack (crits, meter, chill, leech).
local function applyDamage(self, attacker, victim, amount, events, extra, noVariance)
	if not victim.alive or victim.gone or amount <= 0 then
		return 0
	end
	if victim.arriveUntil and self.t < victim.arriveUntil then
		-- an arriving enemy cannot be hit by any path (specials, zones, burns); no event (the client draws its entrance)
		return 0
	end
	local D = damageRules()
	local F = fighterRules()
	local dmg = amount
	local mult = 1
	if attacker then
		mult = elemMult(self, attacker, victim)
		dmg = dmg * mult * (attacker.powerMult or 1) * attackMult(self, attacker)
	end
	local crit = false
	if not noVariance then
		local v = D.Variance
		dmg = dmg * (1 - v + 2 * v * rand(self))
		local critRules = D.Crit
		if attacker and attacker.kind ~= "Boss" and extra == nil and type(critRules) == "table" and rand(self) < num(critRules.Chance, 0) then
			dmg = dmg * num(critRules.Mult, 1.5)
			crit = true
		end
	end
	local defense = victim.defense
	if defense and defense > 0 then
		dmg = dmg * (1 - defense)
	end
	if victim.takenUntil and self.t < victim.takenUntil then
		dmg = dmg * victim.takenMult
	end
	local cap = self.maxHitShare
	if cap and attacker and attacker.kind ~= "Boss" and dmg > victim.maxHp * cap then
		dmg = victim.maxHp * cap
	end
	if dmg < D.MinHit then
		dmg = D.MinHit
	end
	local absorbed = 0
	if victim.shield > 0 then
		absorbed = min(victim.shield, dmg)
		victim.shield = victim.shield - absorbed
		dmg = dmg - absorbed
	end
	victim.hp = victim.hp - dmg
	local ev = { type = EV.Hit, from = attacker and attacker.id or nil, to = victim.id, dmg = floor(dmg + 0.5) }
	if attacker then
		attacker.damage = attacker.damage + dmg
		attacker.team.damage = attacker.team.damage + dmg
		local isFighter = attacker.team.player and attacker == attacker.team.fighter
		if attacker.kind ~= "Boss" and attacker.alive and extra == nil then
			local gain = isFighter and num(F.MeterOnHit, 4) or num(D.MeterOnHit, 4)
			local top = isFighter and num(F.SpecialMeterMax, 100) or num(D.MeterMax, 100)
			attacker.meter = min(top, attacker.meter + gain * (attacker.meterRate or 1))
			-- Chill: the fighter's plain hits slow its enemies
			if attacker.chillUntil and self.t < attacker.chillUntil and victim.kind ~= "Boss" then
				victim.slowUntil = max(victim.slowUntil or 0, self.t + 2)
				ev.slow = true
			end
		end
		-- Leech / Thorn Lash lifesteal
		local leech = 0
		if attacker.leechUntil and self.t < attacker.leechUntil then
			leech = attacker.leechValue
		end
		if extra and finite(extra.leech) then
			leech = leech + extra.leech
		end
		if leech > 0 and attacker.alive and attacker.hp < attacker.maxHp then
			local heal = min(dmg * leech, attacker.maxHp - attacker.hp)
			attacker.hp = attacker.hp + heal
			ev.leech = floor(heal + 0.5)
		end
		if attacker.dmgBuffUntil and self.t < attacker.dmgBuffUntil then
			ev.buffDmg = true
		end
		-- threat: an NPC chases who hit it last
		victim.threat = attacker
		victim.threatAt = self.t
	end
	if victim.kind ~= "Boss" then
		local isFighter = victim.team.player and victim == victim.team.fighter
		local gain = isFighter and num(F.MeterOnHurt, 2) or num(D.MeterOnHurt, 2)
		local top = isFighter and num(F.SpecialMeterMax, 100) or num(D.MeterMax, 100)
		victim.meter = min(top, victim.meter + gain * (victim.meterRate or 1))
	end
	if mult ~= 1 then
		ev.elem = mult
	end
	if crit then
		ev.crit = true
	end
	if absorbed > 0 then
		ev.absorbed = floor(absorbed + 0.5)
	end
	if extra then
		for k, v in pairs(extra) do
			if k ~= "leech" then
				ev[k] = v
			end
		end
	end
	events[#events + 1] = ev
	if victim.hp <= 0 then
		knockOut(self, victim, attacker, events)
	end
	return dmg + absorbed
end

-- a hit that lands on a unit inside its dash i-frames: a miss (DODGED)
local function missEvent(self, attacker, victim, events, extra)
	local ev = { type = EV.Hit, from = attacker and attacker.id or nil, to = victim.id, dmg = 0, miss = true }
	if extra then
		for k, v in pairs(extra) do
			ev[k] = v
		end
	end
	events[#events + 1] = ev
end

local function inIFrames(self, u)
	return self.t < (u.iframesUntil or 0)
end

----------------------------------------------------------------------
-- Statuses
----------------------------------------------------------------------
local function applyStun(self, e, seconds)
	if e.kind == "Boss" or seconds <= 0 then
		return false
	end
	local untilT = self.t + seconds
	if e.stunUntil < untilT then
		e.stunUntil = untilT
	end
	e.state = S_STUNNED
	e.windAt = nil
	e.windTarget = nil
	return true
end

local function applyBurn(self, from, e, total, seconds)
	if e.kind == "Boss" or total <= 0 then
		return
	end
	local ticks = max(1, floor(num(damageRules().BurnTicks, 3)))
	e.burnLeft = ticks
	e.burnAmount = total / ticks
	e.burnNextAt = self.t + seconds / ticks
	e.burnStep = seconds / ticks
	e.burnFrom = from
end

----------------------------------------------------------------------
-- Targeting
----------------------------------------------------------------------
-- nearest living enemy on the floor, judged on start-of-step positions (px / pz)
local function nearestEnemy(self, u, maxDist)
	local best, bestD2 = nil, (maxDist and maxDist * maxDist) or huge
	local list = self.units
	local side = u.side
	for i = 1, #list do
		local e = list[i]
		if e.side ~= side and targetable(self, e) then
			local dx, dz = e.px - u.px, e.pz - u.pz
			local d2 = dx * dx + dz * dz
			if d2 < bestD2 then
				best, bestD2 = e, d2
			end
		end
	end
	return best, bestD2
end

-- the NPC target: the threat (who hit it within ThreatSeconds), else sticky nearest / a random near one
local function pickTarget(self, u)
	local D = damageRules()
	local threat = u.threat
	if threat and threat.alive and not threat.gone and not threat.benched and threat.side ~= u.side and self.t - u.threatAt <= num(D.ThreatSeconds, 3) then
		return threat
	end
	local nearest, dmin2 = nearestEnemy(self, u)
	if not nearest then
		return nil
	end
	local sticky = num(D.TargetSticky, 1.6)
	local cur = u.target
	if cur and cur.alive and not cur.gone and not cur.benched and cur.side ~= u.side then
		local dx, dz = cur.px - u.px, cur.pz - u.pz
		if dx * dx + dz * dz <= dmin2 * sticky * sticky then
			return cur
		end
	end
	local spread = num(D.TargetSpread, 1.35)
	local limit = dmin2 * spread * spread
	local count = 0
	local list = self.units
	local side = u.side
	for i = 1, #list do
		local e = list[i]
		if e.side ~= side and targetable(self, e) then
			local dx, dz = e.px - u.px, e.pz - u.pz
			if dx * dx + dz * dz <= limit then
				count = count + 1
				self.order2[count] = e
			end
		end
	end
	if count <= 1 then
		return nearest
	end
	return self.order2[randInt(self, 1, count)]
end

local function livingEnemies(self, side)
	local out = {}
	local list = self.units
	for i = 1, #list do
		local e = list[i]
		if e.side ~= side and targetable(self, e) then -- an arriving enemy is not in any shape yet
			out[#out + 1] = e
		end
	end
	return out
end

-- a player team's current lock, if still a living enemy on the floor
local function lockOf(team)
	local l = team.lock
	if l and l.alive and not l.gone and not l.benched and l.side ~= team.side then
		return l
	end
	team.lock = nil
	return nil
end

----------------------------------------------------------------------
-- Buffs (helper buttons, Rally / Haste specials)
----------------------------------------------------------------------
-- applies a buff table to `target`; value x `mult` (Ability training of the caster); returns the until time
local function applyBuff(self, target, buff, mult, events, ev)
	local t = self.t
	local value = num(buff.Value, 0) * num(mult, 1)
	local seconds = num(buff.Seconds, 0)
	local untilT = t + seconds
	local effect = buff.Effect
	if effect == "Heal" then
		local amount = min(target.maxHp * value, max(0, target.maxHp - target.hp))
		target.hp = target.hp + amount
		ev.amount = floor(amount + 0.5)
	elseif effect == "Shield" then
		local amount = target.maxHp * value
		if target.shield < amount then
			target.shield = amount
		end
		target.shieldUntil = max(target.shieldUntil, untilT)
		ev.amount = floor(amount + 0.5)
	elseif effect == "Damage" then
		target.dmgBuffMult = 1 + value
		target.dmgBuffUntil = untilT
	elseif effect == "Speed" then
		target.speedBuffMult = 1 + value
		target.speedBuffUntil = untilT
	elseif effect == "Regen" then
		target.regenRate = value
		target.regenUntil = untilT
	elseif effect == "Chill" then
		target.chillValue = value
		target.chillUntil = untilT
	elseif effect == "Taken" then
		target.takenMult = max(0.1, 1 - value)
		target.takenUntil = untilT
	elseif effect == "AttackSpeed" then
		target.atkSpeedMult = 1 + value
		target.atkSpeedUntil = untilT
	elseif effect == "Lifesteal" then
		target.leechValue = value
		target.leechUntil = untilT
	end
	if finite(buff.Meter) and buff.Meter > 0 then
		local top = num(fighterRules().SpecialMeterMax, 100)
		target.meter = min(top, target.meter + buff.Meter)
	end
	ev["until"] = r1(untilT)
	return untilT
end

----------------------------------------------------------------------
-- Specials
----------------------------------------------------------------------
local function specialRules(kind)
	local bc = catalog()
	local s = bc and type(bc.Specials) == "table" and bc.Specials[kind]
	if type(s) == "table" then
		return s
	end
	return nil
end

local function castSpecial(self, u, events)
	local kind = u.specialKind
	local S = kind and specialRules(kind)
	if not S then
		return false, "NoSpecial"
	end
	local D = damageRules()
	local team = u.team
	local isFighter = team.player and u == team.fighter
	local base = u.specialPower * D.DamageScale * num(S.Scale, 1) * num(D.SpecialScale, 1)
	local offensive = kind ~= "Heal" and kind ~= "Shield" and kind ~= "Rally" and kind ~= "Haste"
	local target = nil
	if offensive then
		target = isFighter and lockOf(team) or nil
		if not target then
			target = pickTarget(self, u)
		end
		if not target then
			return false, "NoTarget"
		end
		if kind == "Pounce" and dist(u.x, u.z, target.x, target.z) > num(S.Range, 30) + target.radius then
			target = nearestEnemy(self, u, num(S.Range, 30) + 3)
			if not target then
				return false, "TooFar"
			end
		end
	end
	u.meter = 0
	u.castUntil = self.t + D.CastSeconds
	u.state = S_CASTING
	u.windAt = nil
	u.windTarget = nil
	if u.nextAttack < u.castUntil then
		u.nextAttack = u.castUntil
	end
	u.autoCastAt = nil
	local ev = { type = EV.Special, unit = u.id, kind = kind, name = u.special and u.special.Name or kind, x = r1(u.x), z = r1(u.z) }
	if target then
		ev.tx, ev.tz = r1(target.x), r1(target.z)
		ev.target = target.id
	end
	local position = #events + 1
	local extra = { special = kind }
	if kind == "Blast" then
		local r = num(S.Radius, 7)
		ev.targets = {}
		for _, e in ipairs(livingEnemies(self, u.side)) do
			if inCircle(e, target.x, target.z, r) then
				ev.targets[#ev.targets + 1] = e.id
				applyDamage(self, u, e, base, events, extra)
			end
		end
	elseif kind == "Heal" then
		ev.heals = {}
		local amount = base
		if isFighter then
			amount = base * num(S.Solo, 3) -- a fighter's heal: x Solo on the fighter and on each benched pet
		end
		-- dungeon fixes (7): a player's healer heals its fighter AND the benched pets (an NPC: its pets on the floor)
		for _, a in ipairs(team.units) do
			if a.alive and not a.gone and a.hp < a.maxHp and (isFighter or not a.benched) then
				local got = min(amount, a.maxHp - a.hp)
				a.hp = a.hp + got
				ev.heals[#ev.heals + 1] = { a.id, floor(got + 0.5) }
			end
		end
	elseif kind == "Shield" then
		ev.shields = {}
		local amount = base
		if isFighter then
			amount = base * num(S.Solo, 3)
		end
		for _, a in ipairs(team.units) do
			if a.alive and not a.gone and (not isFighter or a == u) and (isFighter or not a.benched) then
				if a.shield < amount then
					a.shield = amount
				end
				a.shieldUntil = self.t + num(S.Seconds, 6)
				ev.shields[#ev.shields + 1] = a.id
			end
		end
	elseif kind == "Rally" or kind == "Haste" then
		local bc = catalog()
		local buff = bc and type(bc.Buffs) == "table" and bc.Buffs[kind] or { Effect = (kind == "Rally") and "Damage" or "Speed", Value = num(S.Value, 0.35), Seconds = num(S.Seconds, 8) }
		local b = { Effect = buff.Effect, Value = num(S.Value, buff.Value), Seconds = num(S.Seconds, buff.Seconds) }
		applyBuff(self, u, b, u.specialBoost, events, ev)
		ev.targets = { u.id }
	elseif kind == "Storm" then
		local seconds = num(S.Seconds, 4)
		local zone = {
			x = target.x,
			z = target.z,
			r = num(S.Radius, 6),
			dps = base / seconds,
			untilT = self.t + seconds,
			nextTick = self.t + ZONE_TICK,
			side = u.side,
			from = u,
			kind = kind,
		}
		self.zones[#self.zones + 1] = zone
		events[#events + 1] = { type = EV.Zone, unit = u.id, kind = kind, x = r1(zone.x), z = r1(zone.z), r = zone.r, seconds = seconds, side = u.side }
	elseif kind == "Pounce" then
		local dx, dz = target.x - u.x, target.z - u.z
		local d = sqrt(dx * dx + dz * dz)
		local stop = target.radius + u.radius + 0.5
		if d > stop and not isFighter then
			u.x = target.x - dx / d * stop
			u.z = target.z - dz / d * stop
			clampToFloor(self, u)
		end
		ev.targets = { target.id }
		if inIFrames(self, target) then
			missEvent(self, u, target, events, extra)
		else
			applyDamage(self, u, target, base, events, extra)
		end
	elseif kind == "Freeze" then
		local r = num(S.Radius, 7)
		local stun = num(S.Stun, 2) * (u.specialFactor or 1)
		ev.targets, ev.stunned = {}, {}
		for _, e in ipairs(livingEnemies(self, u.side)) do
			if inCircle(e, target.x, target.z, r) then
				ev.targets[#ev.targets + 1] = e.id
				if inIFrames(self, e) then
					missEvent(self, u, e, events, extra)
				else
					if applyStun(self, e, stun) then
						ev.stunned[#ev.stunned + 1] = e.id
					end
					applyDamage(self, u, e, base, events, extra)
				end
			end
		end
	elseif kind == "Beam" then
		local dx, dz = target.x - u.x, target.z - u.z
		local angle = atan2(dz, dx)
		if dx == 0 and dz == 0 then
			angle = 0
		end
		ev.angle = r1(angle)
		ev.targets = {}
		for _, e in ipairs(livingEnemies(self, u.side)) do
			if inLine(e, u.x, u.z, angle, num(S.Length, 26), num(S.Width, 4)) then
				ev.targets[#ev.targets + 1] = e.id
				if inIFrames(self, e) then
					missEvent(self, u, e, events, extra)
				else
					applyDamage(self, u, e, base, events, extra)
				end
			end
		end
	else
		ev.targets = { target.id }
		applyDamage(self, u, target, base, events, extra)
	end
	table.insert(events, position, ev)
	return true, kind
end

-- NPC / Auto teams decide when to use a full meter
local function autoSpecialWanted(self, u)
	local kind = u.specialKind
	if kind == "Heal" then
		for _, a in ipairs(u.team.units) do
			if a.alive and not a.benched and a.hp < a.maxHp * 0.8 then
				return true
			end
		end
		return false
	elseif kind == "Shield" then
		for _, a in ipairs(u.team.units) do
			if a.alive and not a.benched and a.hp < a.maxHp * 0.95 and a.shield <= 0 then
				return true
			end
		end
		return false
	end
	return true
end

----------------------------------------------------------------------
-- The element attack
----------------------------------------------------------------------
-- aim: a unit (target) or a point; returns angle, tx, tz
local function aimOf(self, team, u, arg)
	local target = nil
	local tx, tz = nil, nil
	if type(arg) == "table" then
		local ax = arg.x or arg.X or arg[1]
		local az = arg.z or arg.Z or arg[2]
		if finite(ax) and finite(az) then
			tx, tz = clampPoint(self, ax, az, 0)
		end
	elseif arg ~= nil then
		local id = tonumber(arg)
		local unit = id and self.units[id]
		if unit and onFloor(unit) and unit.side ~= u.side then
			target = unit
		end
	end
	if not target and not tx then
		target = lockOf(team)
	end
	if not target and not tx then
		target = nearestEnemy(self, u)
	end
	if target then
		tx, tz = target.x, target.z
	end
	if not tx then
		tx, tz = u.x + team.faceX * 5, u.z + team.faceZ * 5
	end
	local dx, dz = tx - u.x, tz - u.z
	local angle = (dx == 0 and dz == 0) and atan2(team.faceZ, team.faceX) or atan2(dz, dx)
	return angle, tx, tz, target
end

local function castElement(self, team, u, arg, events)
	local bc = catalog()
	local F = fighterRules()
	local element = u.elems[1]
	local a = bc and type(bc.ElementAttacks) == "table" and element and bc.ElementAttacks[element]
	if not a then
		return false, "NoElement"
	end
	local angle, tx, tz = aimOf(self, team, u, arg)
	local ev = { type = EV.Element, unit = u.id, element = element, name = a.Name, x = r1(u.x), z = r1(u.z), angle = floor(angle * 1000 + 0.5) / 1000, tx = r1(tx), tz = r1(tz), shape = a.Shape, targets = {} }
	local hits = {}
	local enemies = livingEnemies(self, u.side)
	-- a ranged fighter reaches out to its own range at least (the design's "ranged pets use max(Range, 14)")
	local reachOut = u.ranged and num(u.range, 0) or 0
	if a.Shape == "Cone" then
		local half = num(a.Angle, 60) * pi / 360
		local length = max(num(a.Length, num(F.ElementRange, 14)), reachOut)
		for _, e in ipairs(enemies) do
			if inCone(e, u.x, u.z, angle, half, length) then
				hits[#hits + 1] = e
			end
		end
	elseif a.Shape == "Line" then
		for _, e in ipairs(enemies) do
			if inLine(e, u.x, u.z, angle, max(num(a.Length, 24), reachOut), num(a.Width, 4)) then
				hits[#hits + 1] = e
			end
		end
	else
		local r = max(num(a.Radius, 8), reachOut)
		for _, e in ipairs(enemies) do
			if inCircle(e, u.x, u.z, r) then
				hits[#hits + 1] = e
			end
		end
	end
	team.elementReadyAt = self.t + num(F.ElementCooldown, 7)
	team.faceX, team.faceZ = cos(angle), sin(angle)
	u.attackUntil = self.t + ATTACK_POSE
	events[#events + 1] = ev
	local dmg = u.hit * num(F.ElementMult, 2.4)
	local extra = { element = a.Name }
	if finite(a.Leech) then
		extra.leech = a.Leech
	end
	for _, e in ipairs(hits) do
		ev.targets[#ev.targets + 1] = e.id
		if inIFrames(self, e) then
			missEvent(self, u, e, events, { element = a.Name })
		else
			local dealt = applyDamage(self, u, e, dmg, events, extra)
			if e.alive then
				if finite(a.Push) and e.kind ~= "Boss" then
					local dx, dz = e.x - u.x, e.z - u.z
					local d = sqrt(dx * dx + dz * dz)
					if d > 0.01 then
						e.x, e.z = e.x + dx / d * a.Push, e.z + dz / d * a.Push
						clampToFloor(self, e)
					end
				end
				if type(a.Burn) == "table" then
					applyBurn(self, u, e, dealt * num(a.Burn.Share, 0.25), num(a.Burn.Seconds, 3))
				end
				if type(a.Slow) == "table" and e.kind ~= "Boss" then
					e.slowUntil = max(e.slowUntil, self.t + num(a.Slow.Seconds, 4))
				end
				if type(a.Weaken) == "table" then
					e.weakenUntil = max(e.weakenUntil, self.t + num(a.Weaken.Seconds, 5))
				end
				if finite(a.Stun) then
					applyStun(self, e, a.Stun)
				end
			end
		end
	end
	if finite(a.MeterGain) then
		u.meter = min(num(F.SpecialMeterMax, 100), u.meter + a.MeterGain)
	end
	return true, a.Name
end

----------------------------------------------------------------------
-- Swaps
----------------------------------------------------------------------
-- `incoming` (a benched, alive unit) takes the floor; the fighter (if alive) goes to the bench
function swapIn(self, team, incoming, events, auto)
	local F = fighterRules()
	local out = team.fighter
	local x, z = team.anchorX, team.anchorZ
	if out then
		x, z = out.x, out.z
		if out.alive then
			out.benched = true
			out.state = S_BENCHED
		end
		out.target = nil
		out.windAt = nil
	end
	incoming.benched = false
	incoming.x, incoming.z, incoming.px, incoming.pz = x, z, x, z
	incoming.castUntil = self.t + num(F.SwapCastSeconds, 0.6)
	incoming.state = S_CASTING
	incoming.nextAttack = max(incoming.nextAttack, incoming.castUntil)
	incoming.iframesUntil = 0
	incoming.dashUntil = 0
	team.fighter = incoming
	events[#events + 1] = { type = EV.Swap, owner = team.owner, out = out and out.id or nil, ["in"] = incoming.id, auto = auto or nil }
end

----------------------------------------------------------------------
-- Boss patterns (Phase 3, kept; the dash i-frames dodge a telegraph)
----------------------------------------------------------------------
function bossBasis(self, victim)
	local rules = (catalog() and catalog().BossRules) or {}
	local basis = type(rules.DamageBasis) == "table" and rules.DamageBasis or { Own = 0.6, Average = 0.4 }
	local group = type(rules.DamageGroup) == "table" and rules.DamageGroup or nil
	local factor = 1
	if group then
		local teams = self.playerTeamCount or 1
		local fullAt = max(2, num(group.FullAt, 8))
		local lo = num(group.Min, 0.6)
		factor = lo + (1 - lo) * min(1, (teams - 1) / (fullAt - 1))
	end
	return (num(basis.Own, 0.6) * victim.maxHp + num(basis.Average, 0.4) * self.avgPetHp) * factor
end

local function telegraphPoints(self, boss, a)
	local mode = a.Target or "Cluster"
	if mode == "Self" then
		return { { x = boss.x, z = boss.z } }
	end
	local enemies = livingEnemies(self, boss.side)
	if #enemies == 0 then
		return nil
	end
	local count = 1
	if a.Shape ~= "Line" then
		local rules = (catalog() and catalog().BossRules) or {}
		local teams = 0
		for _, team in ipairs(self.teams) do
			if team.side ~= boss.side and not team.left then
				teams = teams + 1
			end
		end
		count = max(1, min(num(rules.MaxCircles, 4), ceil(teams / num(rules.CirclesPerTeams, 2))))
	end
	local r = num(a.Radius, num(a.Width, 6))
	local points = {}
	local covered = {}
	for _ = 1, count do
		local pool = {}
		for _, e in ipairs(enemies) do
			if not covered[e] then
				pool[#pool + 1] = e
			end
		end
		if #pool == 0 then
			break
		end
		local p
		if mode == "Random" then
			p = pool[randInt(self, 1, #pool)]
		elseif mode == "Nearest" then
			p = pool[1]
			local bestD2 = huge
			for _, e in ipairs(pool) do
				local dx, dz = e.x - boss.x, e.z - boss.z
				local d2 = dx * dx + dz * dz
				if d2 < bestD2 then
					p, bestD2 = e, d2
				end
			end
		else
			local bestCount = -1
			for _, c in ipairs(pool) do
				local n = 0
				for _, q in ipairs(pool) do
					local dx, dz = q.x - c.x, q.z - c.z
					if dx * dx + dz * dz <= r * r then
						n = n + 1
					end
				end
				if n > bestCount then
					p, bestCount = c, n
				end
			end
		end
		points[#points + 1] = { x = p.x, z = p.z }
		for _, e in ipairs(pool) do
			local dx, dz = e.x - p.x, e.z - p.z
			if dx * dx + dz * dz <= (r + e.radius) * (r + e.radius) then
				covered[e] = true
			end
		end
	end
	return points
end

local function startTelegraph(self, boss, entry, events)
	local a = entry.def
	local points = telegraphPoints(self, boss, a)
	if not points or #points == 0 then
		return false
	end
	local delay = num(a.Telegraph, 2)
	local at = self.t + delay
	local shapes = {}
	if a.Shape == "Line" then
		local count = max(1, floor(num(a.Count, 1)))
		local spread = num(a.Spread, 0) * pi / 180
		local dx, dz = points[1].x - boss.x, points[1].z - boss.z
		if dx == 0 and dz == 0 then
			dz = 1
		end
		local baseAngle = atan2(dz, dx)
		local length = min(num(a.Length, 40), sqrt(dx * dx + dz * dz) + BattleSim.LineOvershoot)
		for k = 1, count do
			shapes[#shapes + 1] = { x = boss.x, z = boss.z, angle = baseAngle + (k - (count + 1) / 2) * spread, length = r1(length), width = num(a.Width, 5) }
		end
	else
		for _, p in ipairs(points) do
			shapes[#shapes + 1] = { x = p.x, z = p.z, r = num(a.Radius, 8) }
		end
	end
	for _, shape in ipairs(shapes) do
		local id = self.nextTelegraphId
		self.nextTelegraphId = id + 1
		local tele = { id = id, boss = boss, attack = a, at = at, shape = a.Shape, x = shape.x, z = shape.z, angle = shape.angle, length = shape.length, width = shape.width, r = shape.r }
		self.telegraphs[#self.telegraphs + 1] = tele
		local ev = {
			type = EV.Telegraph,
			id = id,
			boss = boss.id,
			name = a.Name,
			attack = a.Id,
			shape = a.Shape,
			x = r1(tele.x),
			z = r1(tele.z),
			at = r1(at),
			hits = r1(delay),
		}
		if a.Shape == "Line" then
			ev.angle = floor(tele.angle * 1000 + 0.5) / 1000
			ev.length = tele.length
			ev.width = tele.width
		else
			ev.r = tele.r
		end
		if finite(a.Freeze) then
			ev.freeze = a.Freeze
		end
		if finite(a.Linger) then
			ev.linger = a.Linger
		end
		events[#events + 1] = ev
	end
	return true
end

local function resolveTelegraph(self, tele, events)
	local boss = tele.boss
	local a = tele.attack
	if not boss.alive then
		return
	end
	local extra = { tele = tele.id, attack = a.Id }
	local fraction = num(a.Damage, 0.3) * boss.damageMult
	for _, e in ipairs(livingEnemies(self, boss.side)) do
		local inside
		if tele.shape == "Line" then
			inside = inLine(e, tele.x, tele.z, tele.angle, tele.length, tele.width)
		else
			inside = inCircle(e, tele.x, tele.z, tele.r)
		end
		if inside then
			if inIFrames(self, e) then
				missEvent(self, boss, e, events, extra)
			else
				if finite(a.Freeze) then
					if applyStun(self, e, a.Freeze) then
						extra.freeze = a.Freeze
					end
				end
				applyDamage(self, boss, e, fraction * bossBasis(self, e), events, extra)
			end
		end
	end
	if finite(a.Linger) and tele.shape ~= "Line" then
		local perSecond = num(a.LingerDamage, 0.08) * self.avgPetHp * boss.damageMult
		self.zones[#self.zones + 1] = {
			x = tele.x,
			z = tele.z,
			r = tele.r,
			dps = perSecond,
			untilT = self.t + a.Linger,
			nextTick = self.t + ZONE_TICK,
			side = boss.side,
			from = boss,
			kind = "Linger",
		}
		events[#events + 1] = { type = EV.Zone, unit = boss.id, kind = "Linger", attack = a.Id, x = r1(tele.x), z = r1(tele.z), r = tele.r, seconds = a.Linger, side = boss.side }
	end
end

local function spawnMinions(self, boss, wave, waveIndex, events)
	local bc = catalog()
	local def = boss.boss
	local rules = (bc and bc.BossRules) or {}
	local players = self:_playerTeams()
	local count = ceil(num(wave.PerPlayer, 0.5) * players)
	count = max(num(rules.WaveMin, 2), min(num(rules.WaveMax, 8), count))
	local pc = petCatalog()
	local petDef = pc and pc.Get and def.MinionPet and pc.Get(def.MinionPet)
	if not petDef then
		return
	end
	local infos = {}
	for k = 1, count do
		local id = #self.units + 1
		if id > MAX_UNITS then
			break
		end
		local u = unitFromDef(self, boss.team, petDef, { Level = self.avgPetLevel, Tier = "Normal", NoSpecial = true }, 0, "Pet")
		if not u then
			break
		end
		local angle = (k - 1) * (2 * pi / count) + self.t * 0.1
		local r = boss.radius + 3.5
		u.kind = "Minion"
		u.minion = true
		u.name = (def.Minions and def.Minions.Name) or petDef.Name
		u.maxHp = num(rules.MinionHp, 0.9) * self.avgPetHp
		u.hp = u.maxHp
		u.hit = num(rules.MinionDamage, 0.05) * bossBasis(self, { maxHp = self.avgPetHp })
		u.interval = num(rules.MinionInterval, 1.4)
		u.specialPower = 0
		u.specialKind = nil
		u.special = nil
		u.powerMult = 1
		u.x = boss.x + cos(angle) * r
		u.z = boss.z + sin(angle) * r
		clampToFloor(self, u)
		u.px, u.pz = u.x, u.z
		u.nextAttack = self.t + 1 + rand(self) * 0.8
		u.meter = 0
		markArrival(self, u, arriveSeconds())
		boss.team.units[#boss.team.units + 1] = u
		infos[#infos + 1] = unitInfo(u, self.t)
	end
	if #infos > 0 then
		events[#events + 1] = { type = EV.Spawn, units = infos, wave = waveIndex, boss = boss.id, owner = boss.team.owner }
	end
end

local function bossStep(self, boss, events)
	if not boss.alive then
		return
	end
	local def = boss.boss
	local t = self.t
	if not boss.enraged and finite(def.EnrageAt) and t >= def.EnrageAt then
		local rules = (catalog() and catalog().BossRules) or {}
		local en = type(rules.Enrage) == "table" and rules.Enrage or { Damage = 2, Cooldown = 0.7 }
		boss.enraged = true
		boss.damageMult = num(en.Damage, 2)
		boss.cooldownMult = num(en.Cooldown, 0.7)
		events[#events + 1] = { type = EV.Enrage, unit = boss.id }
	end
	local waves = def.Minions and def.Minions.Waves
	if type(waves) == "table" then
		local frac = boss.hp / boss.maxHp
		for i, wave in ipairs(waves) do
			if not boss.wavesDone[i] and frac <= num(wave.At, 0) then
				boss.wavesDone[i] = true
				spawnMinions(self, boss, wave, i, events)
			end
		end
	end
	-- the basic attack on the nearest fighter in range (a dash dodges it)
	if t >= boss.nextAttack then
		local target = nearestEnemy(self, boss, boss.range + boss.radius)
		if target then
			local basic = def.Basic or {}
			boss.target = target
			boss.state = S_ATTACKING
			if inIFrames(self, target) then
				missEvent(self, boss, target, events, { attack = basic.Name or "Basic" })
			else
				applyDamage(self, boss, target, num(basic.Damage, 0.08) * boss.damageMult * bossBasis(self, target), events, { attack = basic.Name or "Basic" })
			end
			boss.nextAttack = t + boss.interval * boss.cooldownMult
		else
			boss.state = S_IDLE
			boss.target = nearestEnemy(self, boss)
			boss.nextAttack = t + 0.5
		end
	end
	local pendingForBoss = false
	for _, tele in ipairs(self.telegraphs) do
		if tele.boss == boss then
			pendingForBoss = true
			break
		end
	end
	if not pendingForBoss then
		for _, entry in ipairs(boss.attacks) do
			if not pendingForBoss and t >= entry.nextAt then
				if startTelegraph(self, boss, entry, events) then
					boss.state = S_CASTING
					pendingForBoss = true
				end
				entry.nextAt = t + num(entry.def.Cooldown, 10) * boss.cooldownMult
			end
		end
	end
end

----------------------------------------------------------------------
-- The step
----------------------------------------------------------------------
local function tickZones(self, events)
	local zones = self.zones
	local i = 1
	while i <= #zones do
		local zone = zones[i]
		if self.t >= zone.untilT or (zone.from and zone.from.gone) then
			zones[i] = zones[#zones]
			zones[#zones] = nil
		else
			if self.t >= zone.nextTick then
				zone.nextTick = zone.nextTick + ZONE_TICK
				local amount = zone.dps * ZONE_TICK
				local list = self.units
				for k = 1, #list do
					local e = list[k]
					if e.side ~= zone.side and onFloor(e) and inCircle(e, zone.x, zone.z, zone.r) and not inIFrames(self, e) then
						applyDamage(self, zone.from, e, amount, events, { zone = true, kind = zone.kind }, true)
					end
				end
			end
			i = i + 1
		end
	end
end

local function resolveTelegraphs(self, events)
	local list = self.telegraphs
	local i = 1
	while i <= #list do
		local tele = list[i]
		if self.t >= tele.at then
			resolveTelegraph(self, tele, events)
			table.remove(list, i)
		else
			i = i + 1
		end
	end
end

local function moveToward(u, tx, tz, step, stop)
	local dx, dz = tx - u.x, tz - u.z
	local d = sqrt(dx * dx + dz * dz)
	if d <= stop then
		return d
	end
	local travel = min(step, d - stop)
	u.x = u.x + dx / d * travel
	u.z = u.z + dz / d * travel
	return d - travel
end

local function teamIndex(team, u)
	local idx, n = 1, 0
	for _, v in ipairs(team.units) do
		if onFloor(v) then
			n = n + 1
			if v == u then
				idx = n
			end
		end
	end
	return idx, max(1, n)
end

-- timers and statuses shared by every unit: shields, burn ticks, regen, meter, the Speed event bookkeeping
local function tickStatuses(self, u, dt, events)
	local t = self.t
	if u.shield > 0 and t >= u.shieldUntil then
		u.shield = 0
	end
	if u.burnLeft > 0 and t >= u.burnNextAt then
		u.burnLeft = u.burnLeft - 1
		u.burnNextAt = t + (u.burnStep or 1)
		local from = u.burnFrom
		if from and from.gone then
			from = nil
		end
		applyDamage(self, from, u, u.burnAmount, events, { burn = true }, true)
		if not u.alive then
			return
		end
	end
	if u.regenUntil > t and u.regenRate > 0 and u.hp < u.maxHp then
		u.hp = min(u.maxHp, u.hp + u.maxHp * u.regenRate * dt)
	end
end

-- the NPC pet / minion AI: threat target, melee orbit, a wind-up before every hit
local function npcStep(self, u, dt, events)
	local D = damageRules()
	local F = fighterRules()
	local t = self.t
	local team = u.team
	if u.arriveUntil and t < u.arriveUntil then
		-- arriving (dungeon fixes 3): it stands where it appeared and does nothing yet
		u.state = S_IDLE
		return
	end
	u.meter = min(D.MeterMax, u.meter + D.MeterPerSecond * dt * (u.meterRate or 1))
	if t < u.stunUntil then
		u.state = S_STUNNED
		u.windAt = nil
		return
	end
	if t < u.castUntil then
		u.state = S_CASTING
		return
	end
	local slow = (t < u.slowUntil) and num(D.Slow, 0.6) or 1
	-- a wind-up in progress: the hit lands at windAt if the target is still in reach and not dodging
	if u.windAt then
		if t >= u.windAt then
			local target = u.windTarget
			u.windAt = nil
			u.windTarget = nil
			if target and target.alive and not target.gone and not target.benched then
				local reach = u.range + target.radius + D.EngageSlack + 1.0
				if dist(u.x, u.z, target.x, target.z) <= reach and not inIFrames(self, target) then
					applyDamage(self, u, target, u.hit, events)
				else
					missEvent(self, u, target, events)
				end
			end
			u.state = S_ATTACKING
		else
			u.state = S_ATTACKING
			return
		end
	end
	-- auto specials (never while winding)
	if team.auto and self.specialsEnabled and not team.noSpecials and u.specialKind and u.meter >= D.MeterMax and u.kind ~= "Minion" then
		if u.autoCastAt == nil then
			local lo, hi = D.NpcSpecialDelay[1] or 0.4, D.NpcSpecialDelay[2] or 1.4
			u.autoCastAt = t + lo + (hi - lo) * rand(self)
		elseif t >= u.autoCastAt then
			if autoSpecialWanted(self, u) then
				local ok = castSpecial(self, u, events)
				if ok then
					return
				end
				u.autoCastAt = t + 1
			else
				u.autoCastAt = t + 0.5
			end
		end
	end
	local target = u.target
	if not target or not target.alive or target.gone or target.benched or t >= u.retargetAt then
		target = pickTarget(self, u)
		u.target = target
		u.retargetAt = t + D.RetargetSeconds
	end
	if not target then
		u.state = S_IDLE
		return
	end
	local reach = u.range + target.radius
	local tx, tz = target.px, target.pz
	local d = dist(u.x, u.z, tx, tz)
	local moved = false
	if d > reach then
		local step = u.moveSpeed * slow * dt
		if target.kind == "Boss" or not u.ranged then
			-- orbit slot: every pet of a wave approaches on its own angle (surround, not a queue)
			local idx, n = teamIndex(team, u)
			local ax, az = u.x - tx, u.z - tz
			local base = atan2(az, ax)
			if ax == 0 and az == 0 then
				base = 0
			end
			local angle = base + (idx - (n + 1) / 2) * (pi / 6) * ((d > reach * 2) and 1 or 0)
			local r = reach - 0.5
			moveToward(u, tx + cos(angle) * r, tz + sin(angle) * r, step, 0.2)
		else
			moveToward(u, tx, tz, step, reach - 0.3)
		end
		moved = true
		d = dist(u.x, u.z, tx, tz)
	end
	if d <= reach + D.EngageSlack then
		u.state = S_ATTACKING
		if t >= u.nextAttack then
			-- the wind-up is INSIDE the interval: nextAttack counts from its start
			local windup = num(F.Windup, 0.45)
			u.windAt = t + windup
			u.windTarget = target
			u.nextAttack = t + u.interval / slow * (0.9 + 0.2 * rand(self))
			events[#events + 1] = { type = EV.Windup, unit = u.id, target = target.id, at = r1(u.windAt) }
		end
	elseif moved then
		u.state = S_MOVING
	else
		u.state = S_IDLE
	end
end

-- the fighter of a player team: Move toward the character's point at the legal cap; timers; the Auto kit
local autoFighter
local fighterSwing

-- the fighter's attack interval now (Charge / Haste speed it up, a Slow drags it)
local function attackInterval(self, f)
	local t = self.t
	local interval = f.interval
	if t < f.atkSpeedUntil then
		interval = interval / f.atkSpeedMult
	end
	if t < f.speedBuffUntil then
		interval = interval / f.speedBuffMult
	end
	if t < f.slowUntil then
		interval = interval / num(damageRules().Slow, 0.6)
	end
	return interval
end

-- current positions: within the fighter's range + the target's radius + slack
local function inReach(f, e, slack)
	local dx, dz = e.x - f.x, e.z - f.z
	local reach = f.range + e.radius + slack
	return dx * dx + dz * dz <= reach * reach
end

-- the auto-attack's target: the lock when targetable and in reach, else the nearest targetable enemy in reach (by id on ties)
local function autoTarget(self, team, f, slack)
	local lock = lockOf(team)
	if lock and targetable(self, lock) and inReach(f, lock, slack) then
		return lock
	end
	local best, bestD2 = nil, huge
	local list = self.units
	local side = f.side
	for i = 1, #list do
		local e = list[i]
		if e.side ~= side and targetable(self, e) then
			local dx, dz = e.x - f.x, e.z - f.z
			local d2 = dx * dx + dz * dz
			local reach = f.range + e.radius + slack
			if d2 <= reach * reach and d2 < bestD2 then
				best, bestD2 = e, d2
			end
		end
	end
	return best
end

-- one auto-attack swing when the fighter can (not Stunned / Casting / Dashing / arriving, the interval ready) -> hit?
function fighterSwing(self, team, f, events)
	local t = self.t
	if not f.alive or f.gone or f.benched or t < f.stunUntil or t < f.castUntil or t < f.dashUntil or arriving(self, f) then
		return false
	end
	local F = fighterRules()
	local interval = attackInterval(self, f)
	if t < f.nextAttack - interval * (1 - num(F.AttackTolerance, 0.85)) then
		return false
	end
	local target = autoTarget(self, team, f, num(F.AttackSlack, 3))
	if not target then
		return false
	end
	f.nextAttack = max(f.nextAttack, t) + interval
	f.attackUntil = t + ATTACK_POSE
	local dx, dz = target.x - f.x, target.z - f.z
	local d = sqrt(dx * dx + dz * dz)
	if d > 0.01 then
		team.faceX, team.faceZ = dx / d, dz / d
	end
	if inIFrames(self, target) then
		missEvent(self, f, target, events)
	else
		applyDamage(self, f, target, f.hit, events)
	end
	return true
end

local function fighterStep(self, team, dt, events)
	local f = team.fighter
	if not f or not f.alive or f.gone or f.benched then
		return
	end
	local F = fighterRules()
	local D = damageRules()
	local t = self.t
	f.meter = min(num(F.SpecialMeterMax, 100), f.meter + num(F.MeterPerSecond, 6) * dt * (f.meterRate or 1))
	if team.auto and not team.npc then
		autoFighter(self, team, f, dt, events)
	end
	-- movement toward the wanted point at <= legal run x MoveSlack (x the dash factor while Dashing)
	if team.wantX ~= nil then
		local _, run = legalSpeeds(self, team)
		local cap = run * num(F.MoveSlack, 1.25)
		if t < f.dashUntil then
			cap = cap * dashSpeedFactor()
		end
		if t < f.stunUntil then
			cap = 0
		end
		if cap > 0 then
			local dx, dz = team.wantX - f.x, team.wantZ - f.z
			local d = sqrt(dx * dx + dz * dz)
			if d > 0.01 then
				local travel = min(cap * dt, d)
				f.x = f.x + dx / d * travel
				f.z = f.z + dz / d * travel
				team.faceX, team.faceZ = dx / d, dz / d
				f.moving = travel > 0.05
			else
				f.moving = false
			end
		end
	end
	clampToFloor(self, f)
	-- the auto-attack (dungeon fixes 4): the pet swings by itself; the character stays the body (never moved here)
	fighterSwing(self, team, f, events)
	-- the state
	if t < f.stunUntil then
		f.state = S_STUNNED
	elseif t < f.castUntil then
		f.state = S_CASTING
	elseif t < f.dashUntil then
		f.state = S_DASHING
	elseif t < f.attackUntil then
		f.state = S_ATTACKING
	elseif f.moving then
		f.state = S_MOVING
	else
		f.state = S_IDLE
	end
	-- the lock is the drawn target
	f.target = lockOf(team)
	-- dungeon fixes (7): no passive bench regen in combat (only a healing pet's Heal special / Heal buff heals the bench)
end

local doCommand -- forward

-- the harness / Auto fighter: approaches its target at the legal run speed and presses the kit (no dodging: the
-- scripted player of tools/sim_battle.lua does that)
function autoFighter(self, team, f, dt, events)
	local target = lockOf(team) or nearestEnemy(self, f)
	if not target then
		return
	end
	local _, run = legalSpeeds(self, team)
	local reach = f.range + target.radius
	local dx, dz = target.x - f.x, target.z - f.z
	local d = sqrt(dx * dx + dz * dz)
	local wantX, wantZ = f.x, f.z
	if d > reach - 0.5 and d > 0.01 then
		local travel = min(run * dt, d - (reach - 0.5))
		wantX, wantZ = f.x + dx / d * travel, f.z + dz / d * travel
	end
	team.wantX, team.wantZ = clampPoint(self, wantX, wantZ, f.radius)
	local t = self.t
	if t >= f.castUntil and t >= f.stunUntil then
		if f.meter >= num(fighterRules().SpecialMeterMax, 100) then
			doCommand(self, team, "Special", nil, events)
		end
		-- (the swing itself is the auto-attack of fighterStep)
		if t >= team.elementReadyAt and d <= num(fighterRules().ElementRange, 14) + target.radius then
			doCommand(self, team, "Element", target.id, events)
		end
		for _, u in ipairs(team.units) do
			if u.benched and u.alive and t >= u.buffReadyAt then
				local kind = u.buffKind
				local wanted = true
				if kind == "Heal" or (u.buffDef and u.buffDef.Effect == "Regen") then
					wanted = f.hp < f.maxHp * 0.6
				end
				if wanted then
					doCommand(self, team, "Buff", u.slot, events)
				end
			end
		end
		if f.hp < f.maxHp * 0.2 and t >= team.swapReadyAt then
			for _, u in ipairs(team.units) do
				if u.benched and u.alive and u.hp > u.maxHp * 0.5 then
					doCommand(self, team, "Swap", u.slot, events)
					break
				end
			end
		end
	end
end

-- same-side NPC units are pushed apart so they do not stack
local function separate(self)
	local D = damageRules()
	local r = D.SeparationRadius
	local r2 = r * r
	local list = self.units
	local n = #list
	for i = 1, n - 1 do
		local a = list[i]
		if onFloor(a) and a.kind ~= "Boss" and not (a.team.player and a == a.team.fighter) then
			for j = i + 1, n do
				local b = list[j]
				if onFloor(b) and b.kind ~= "Boss" and b.side == a.side and not (b.team.player and b == b.team.fighter) then
					local dx, dz = b.x - a.x, b.z - a.z
					local d2 = dx * dx + dz * dz
					if d2 < r2 then
						local d = sqrt(d2)
						if d < 0.001 then
							dx, dz, d = ((i % 2 == 0) and 1 or -1), 0.3, 1
						end
						local push = min(0.6, (r - d) * 0.5)
						dx, dz = dx / d, dz / d
						a.x, a.z = a.x - dx * push, a.z - dz * push
						b.x, b.z = b.x + dx * push, b.z + dz * push
					end
				end
			end
		end
	end
end

-- living pets of a side (bench included: the lives)
local function sideLives(self, side)
	local count = 0
	for _, team in ipairs(self.teams) do
		if team.side == side and not team.left then
			count = count + teamLives(team)
		end
	end
	return count
end

local function sideHpFraction(self, side)
	local hp, maxHp = 0, 0
	for _, u in ipairs(self.units) do
		if u.side == side and not u.gone and u.kind ~= "Minion" then
			hp = hp + max(0, u.hp)
			maxHp = maxHp + u.maxHp
		end
	end
	if maxHp <= 0 then
		return 0
	end
	return hp / maxHp
end

local function sideDamage(self, side)
	local d = 0
	for _, team in ipairs(self.teams) do
		if team.side == side then
			d = d + team.damage
		end
	end
	return d
end

local function finish(self, winnerSide, reason, events)
	local result = {
		Mode = self.mode,
		Reason = reason,
		WinnerSide = winnerSide,
		Winners = {},
		Losers = {},
		Draw = winnerSide == nil,
		Forfeit = self.forfeitSeen == true,
		BossId = self.bossId,
		Round = self.round,
		Damage = {},
		Shares = {},
		Duration = r1(self.t),
		Survivors = {},
		Kills = {},
		Waves = self.waveCount or 0,
		Hp = { [1] = sideHpFraction(self, 1), [2] = sideHpFraction(self, 2) },
	}
	local total = 0
	for _, team in ipairs(self.teams) do
		if team.player then
			result.Damage[team.owner] = floor(team.damage + 0.5)
			result.Kills[team.owner] = team.kills
			if team.side == 1 then
				total = total + team.damage
			end
			result.Survivors[team.owner] = teamLives(team)
			if not team.left then
				if winnerSide ~= nil and team.side == winnerSide and not team.forfeited then
					result.Winners[#result.Winners + 1] = team.owner
				elseif winnerSide ~= nil then
					result.Losers[#result.Losers + 1] = team.owner
				end
			end
		end
	end
	for _, team in ipairs(self.teams) do
		if team.player and team.side == 1 then
			result.Shares[team.owner] = (total > 0) and (team.damage / total) or 0
		end
	end
	if self.boss then
		result.BossHp = max(0, floor(self.boss.hp + 0.5))
		result.BossMaxHp = floor(self.boss.maxHp + 0.5)
	end
	self.result = result
	events[#events + 1] = { type = EV.End, reason = reason, winnerSide = winnerSide }
end

local function byDamage(self)
	local d1, d2 = sideDamage(self, 1), sideDamage(self, 2)
	if d1 > d2 then
		return 1
	elseif d2 > d1 then
		return 2
	end
	return nil
end

local function checkEnd(self, events)
	local lives1 = sideLives(self, 1)
	local mode = self.mode
	if mode == "Raid" then
		local boss = self.boss
		if boss and not boss.alive then
			finish(self, 1, "BossDown", events)
			return
		end
		local activeTeams = 0
		for _, team in ipairs(self.teams) do
			if team.side == 1 and not team.left then
				activeTeams = activeTeams + 1
			end
		end
		if activeTeams == 0 then
			finish(self, nil, "Abandoned", events)
		elseif lives1 == 0 then
			finish(self, 2, "Wipe", events)
		elseif self.t >= self.timeLimit then
			finish(self, 2, "Timeout", events)
		end
		return
	end
	if mode == "Dungeon" then
		local activeTeams = 0
		for _, team in ipairs(self.teams) do
			if team.side == 1 and not team.left then
				activeTeams = activeTeams + 1
			end
		end
		if activeTeams == 0 then
			finish(self, nil, "Abandoned", events)
		elseif lives1 == 0 then
			finish(self, 2, "Wipe", events)
		elseif self.t >= self.timeLimit then
			finish(self, 2, "Timeout", events)
		end
		return
	end
	local lives2 = sideLives(self, 2)
	if lives1 == 0 and lives2 == 0 then
		local rule = damageRules().DoubleKoByDamage
		local winner = nil
		if type(rule) == "table" and rule[mode] and not self.forfeitSeen then
			winner = byDamage(self)
		end
		if winner then
			finish(self, winner, "Wipe", events)
		else
			finish(self, nil, "Draw", events)
		end
	elseif lives1 == 0 then
		finish(self, 2, self.forfeitSeen and "Forfeit" or "Wipe", events)
	elseif lives2 == 0 then
		finish(self, 1, self.forfeitSeen and "Forfeit" or "Wipe", events)
	elseif self.t >= self.timeLimit then
		if mode == "Ring" then
			finish(self, 2, "Timeout", events)
		else
			local rule = damageRules().DoubleKoByDamage
			local winner = nil
			if type(rule) == "table" and rule[mode] then
				winner = byDamage(self)
			else
				local f1, f2 = sideHpFraction(self, 1), sideHpFraction(self, 2)
				if abs(f1 - f2) >= 0.001 then
					winner = (f1 > f2) and 1 or 2
				end
			end
			finish(self, winner, "Timeout", events)
		end
	end
end

-- ends a running battle now: "Cleared" = side 1 wins (the dungeon's last room), anything else = no winner
function BattleSim:Finish(reason)
	if self.result then
		return false
	end
	local events = {}
	reason = type(reason) == "string" and reason or "Aborted"
	finish(self, (reason == "Cleared") and 1 or nil, reason, events)
	return true, events
end

function BattleSim:Abort(reason)
	return self:Finish(reason)
end

-- the Speed event when a fighter's legal speeds change
local function checkSpeeds(self, team, events)
	if not team.player or not team.fighter or team.left then
		return
	end
	local walk, run = legalSpeeds(self, team)
	walk, run = r1(walk), r1(run)
	if team.lastWalk ~= walk or team.lastRun ~= run then
		team.lastWalk, team.lastRun = walk, run
		events[#events + 1] = { type = EV.Speed, owner = team.owner, walk = walk, run = run }
	end
end

function BattleSim:Step(dt)
	local events = {}
	if self.result then
		return events
	end
	dt = tonumber(dt) or 0.1
	if dt ~= dt or dt < MIN_DT then
		dt = MIN_DT
	elseif dt > MAX_DT then
		dt = MAX_DT
	end
	self.t = self.t + dt
	self.stepCount = self.stepCount + 1
	if #self.pending > 0 then
		for _, ev in ipairs(self.pending) do
			events[#events + 1] = ev
		end
		self.pending = {}
	end
	if self.boss then
		bossStep(self, self.boss, events)
	end
	resolveTelegraphs(self, events)
	tickZones(self, events)
	local list = self.units
	local n = #list
	local order = self.order
	for i = 1, n do
		local u = list[i]
		u.px, u.pz = u.x, u.z
		order[i] = i
	end
	for i = n, 2, -1 do
		local j = 1 + floor(rand(self) * i)
		order[i], order[j] = order[j], order[i]
	end
	for i = 1, n do
		local u = list[order[i]]
		if u.alive and not u.gone and u.kind ~= "Boss" then
			tickStatuses(self, u, dt, events)
			if u.alive and not u.benched and not (u.team.player and u == u.team.fighter) then
				npcStep(self, u, dt, events)
			end
		end
	end
	-- the fighters (incl. their auto-attack): the team order alternates every step, so in a mirror race no side always
	-- swings first (deterministic: it follows the step count)
	local teams = self.teams
	local nTeams = #teams
	local reverse = self.stepCount % 2 == 0
	for k = 1, nTeams do
		local team = teams[reverse and (nTeams + 1 - k) or k]
		if team.player and not team.left then
			fighterStep(self, team, dt, events)
		end
	end
	separate(self)
	for i = 1, #list do
		local u = list[i]
		if onFloor(u) then
			clampToFloor(self, u)
		end
	end
	for _, team in ipairs(self.teams) do
		checkSpeeds(self, team, events)
	end
	checkEnd(self, events)
	return events
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------
local function unitArg(self, team, arg)
	local id = tonumber(arg)
	if not id or id ~= floor(id) then
		return nil
	end
	local unit = self.units[id]
	if not unit or not onFloor(unit) or unit.side == team.side then
		return nil
	end
	return unit
end

-- Attack() with no id: the nearest targetable enemy, or the next one by distance after the current lock (repeated presses
-- cycle; ties by id so it is deterministic)
local function cycleTarget(self, team, f)
	local list = {}
	for _, e in ipairs(self.units) do
		if e.side ~= team.side and targetable(self, e) then
			local dx, dz = e.x - f.x, e.z - f.z
			list[#list + 1] = { e = e, d2 = dx * dx + dz * dz }
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		if a.d2 ~= b.d2 then
			return a.d2 < b.d2
		end
		return a.e.id < b.e.id
	end)
	local lock = lockOf(team)
	if lock then
		for i, entry in ipairs(list) do
			if entry.e == lock then
				return list[(i % #list) + 1].e
			end
		end
	end
	return list[1].e
end

-- the direction the client draws the PET's dash: toward the lock / the nearest enemy, else the fighter's facing
local function dashDirection(self, team, f)
	local aim = lockOf(team)
	if aim and not targetable(self, aim) then
		aim = nil
	end
	aim = aim or nearestEnemy(self, f)
	local dx, dz = team.faceX or 0, team.faceZ or 1
	if aim then
		local ax, az = aim.x - f.x, aim.z - f.z
		local d = sqrt(ax * ax + az * az)
		if d > 0.01 then
			dx, dz = ax / d, az / d
		end
	end
	local len = sqrt(dx * dx + dz * dz)
	if len < 0.01 then
		dx, dz, len = 0, 1, 1
	end
	return floor(dx / len * 100 + 0.5) / 100, floor(dz / len * 100 + 0.5) / 100, aim
end

-- the body of Command; `events` collects what the command causes (the caller queues them)
function doCommand(self, team, action, arg, events)
	local F = fighterRules()
	local t = self.t
	local f = team.fighter
	if action == "Forfeit" then
		if self.mode == "Raid" or self.mode == "Dungeon" then
			self:RemoveTeam(team.owner)
			return true
		end
		team.forfeited = true
		self.forfeitSeen = true
		for _, u in ipairs(team.units) do
			if u.alive then
				knockOut(self, u, nil, events, true)
			end
		end
		events[#events + 1] = { type = EV.Order, owner = team.owner, order = "Forfeit" }
		return true
	end
	if not team.player then
		return false, "NotPlayer"
	end
	if not f or not f.alive then
		return false, "Down"
	end
	if action == "Target" then
		if arg == nil then
			team.lock = nil
			events[#events + 1] = { type = EV.Order, owner = team.owner, order = "Target" }
			return true
		end
		local unit = unitArg(self, team, arg)
		if not unit then
			return false, "BadTarget"
		end
		team.lock = unit
		events[#events + 1] = { type = EV.Order, owner = team.owner, order = "Target", target = unit.id }
		return true
	end
	local busy = nil
	if t < f.stunUntil then
		busy = "Stunned"
	elseif t < f.castUntil then
		busy = "Casting"
	end
	if action == "Attack" then
		-- dungeon fixes (4): ATTACK directs the auto-attacking pet (a lock); it never swings by itself
		local target = nil
		if arg ~= nil then
			target = unitArg(self, team, arg)
			if not target then
				return false, "BadTarget"
			end
		else
			target = cycleTarget(self, team, f)
			if not target then
				return false, "NoTarget"
			end
		end
		-- the echo only when the lock changes (a repeated order on the same enemy sends nothing: no traffic amplification)
		if team.lock ~= target then
			events[#events + 1] = { type = EV.Order, owner = team.owner, order = "Attack", target = target.id }
		end
		team.lock = target
		f.target = target
		if not inReach(f, target, num(F.AttackSlack, 3)) then
			return true, target.id, "OutOfReach"
		end
		return true, target.id
	elseif action == "Element" then
		if busy then
			return false, busy
		end
		if t < team.elementReadyAt then
			return false, "Cooldown", r1(team.elementReadyAt - t)
		end
		return castElement(self, team, f, arg, events)
	elseif action == "Special" then
		if not self.specialsEnabled or team.noSpecials then
			return false, "Disabled"
		end
		if busy then
			return false, busy
		end
		if not f.specialKind then
			return false, "NoSpecial"
		end
		if f.meter < num(F.SpecialMeterMax, 100) then
			return false, "Charging", floor(f.meter + 0.5)
		end
		return castSpecial(self, f, events)
	elseif action == "Dash" then
		if t < f.stunUntil then
			return false, "Stunned"
		end
		if t < team.dashReadyAt then
			return false, "Cooldown", r1(team.dashReadyAt - t)
		end
		f.dashUntil = t + num(F.DashSeconds, 0.35)
		f.iframesUntil = t + num(F.DashIFrames, 0.35)
		team.dashReadyAt = t + num(F.DashCooldown, 2.5)
		f.state = S_DASHING
		local dx, dz, aim = dashDirection(self, team, f)
		-- small on the wire (16-raid budget): the position comes from the snapshot, the timings from BattleCatalog.Fighter
		events[#events + 1] = { type = EV.Dash, unit = f.id, dir = { dx, dz }, target = aim and aim.id or nil }
		return true
	elseif action == "Buff" then
		local slot = tonumber(arg)
		if not slot or slot ~= floor(slot) or slot < 1 then
			return false, "BadSlot"
		end
		local helper = team.bySlot[slot]
		if not helper then
			return false, "BadSlot"
		end
		if not helper.alive then
			return false, "Down"
		end
		if not helper.benched then
			return false, "BadSlot"
		end
		if not helper.buffDef then
			return false, "NoBuff"
		end
		if t < helper.buffReadyAt then
			return false, "Cooldown", r1(helper.buffReadyAt - t)
		end
		local buff = helper.buffDef
		local cooldown = (helper.role == "Support") and num(F.SupportCooldown, 12) or num(F.HelperCooldown, 15)
		helper.buffReadyAt = t + cooldown
		local ev = { type = EV.Buff, owner = team.owner, unit = helper.id, kind = helper.buffKind, name = buff.Name, target = f.id }
		applyBuff(self, f, buff, helper.specialBoost, events, ev)
		if buff.Effect == "Heal" then
			-- dungeon fixes (7): a healing helper heals the fighter AND the other benched pet
			ev.heals = { { f.id, ev.amount or 0 } }
			for _, other in ipairs(team.units) do
				if other ~= helper and other ~= f and other.benched and other.alive and not other.gone then
					local tmp = {}
					applyBuff(self, other, buff, helper.specialBoost, events, tmp)
					ev.heals[#ev.heals + 1] = { other.id, tmp.amount or 0 }
				end
			end
		end
		events[#events + 1] = ev
		return true, helper.buffKind
	elseif action == "Swap" then
		local slot = tonumber(arg)
		if not slot or slot ~= floor(slot) or slot < 1 then
			return false, "BadSlot"
		end
		local helper = team.bySlot[slot]
		if not helper then
			return false, "BadSlot"
		end
		if not helper.alive then
			return false, "Down"
		end
		if not helper.benched then
			return false, "BadSlot"
		end
		if busy then
			return false, busy
		end
		if t < team.swapReadyAt then
			return false, "Cooldown", r1(team.swapReadyAt - t)
		end
		team.swapReadyAt = t + num(F.SwapCooldown, 10)
		swapIn(self, team, helper, events, false)
		return true, helper.id
	end
	return false, "UnknownAction"
end

function BattleSim:Command(owner, action, arg, arg2)
	if self.result then
		return false, "Finished"
	end
	local team = self.teamByOwner[owner]
	if not team then
		return false, "NoTeam"
	end
	if team.left then
		return false, "Left"
	end
	if team.forfeited then
		return false, "Forfeited"
	end
	if action == "Move" then
		if not team.player then
			return false, "NotPlayer"
		end
		local x, z = arg, arg2
		if type(arg) == "table" then
			x, z = arg.x or arg.X or arg[1], arg.z or arg.Z or arg[2]
		end
		if not finite(x) or not finite(z) then
			return false, "BadPoint"
		end
		local f = team.fighter
		team.wantX, team.wantZ = clampPoint(self, x, z, f and f.radius or 1)
		return true
	end
	if type(action) ~= "string" then
		return false, "UnknownAction"
	end
	local events = {}
	local ok, reason, extra = doCommand(self, team, action, arg, events)
	if not ok then
		if reason == "UnknownAction" then
			return false, reason
		end
		-- one rejected echo per team per step (a held ATTACK button must not flood the clients)
		if team.rejectStep ~= self.stepCount then
			team.rejectStep = self.stepCount
			self.pending[#self.pending + 1] = { type = EV.Order, owner = owner, order = action, target = tonumber(arg), rejected = reason }
		end
		return false, reason, extra
	end
	for _, ev in ipairs(events) do
		self.pending[#self.pending + 1] = ev
	end
	return true, reason, extra
end

-- A team leaves (raids / dungeons: leave / disconnect). Its units vanish and the boss sheds their HP share.
function BattleSim:RemoveTeam(owner)
	local team = self.teamByOwner[owner]
	if not team or team.left then
		return false
	end
	team.left = true
	local ids = {}
	for _, u in ipairs(team.units) do
		ids[#ids + 1] = u.id
		u.alive = false
		u.gone = true
		u.state = S_DOWN
		u.target = nil
		u.windAt = nil
	end
	for _, other in ipairs(self.teams) do
		if other.lock and other.lock.gone then
			other.lock = nil
		end
	end
	local boss = self.boss
	if boss and boss.alive and team.side == 1 and team.player then
		local frac = boss.hp / boss.maxHp
		boss.maxHp = max(1, self:_bossMaxHp())
		boss.hp = max(1, min(frac * boss.maxHp, boss.maxHp))
	end
	self:_refreshRaidScale()
	self.pending[#self.pending + 1] = { type = EV.Leave, owner = owner, units = ids }
	return true
end

return BattleSim
