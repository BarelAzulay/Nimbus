-- BattleSim: the PURE pet battle engine of Phase 3 (ARCHITECTURE_V3.md "Phase 3 build contract" +
-- "Interfaces between the Phase 3 modules"). No Instances, no services, no yields, no wall clock: the server
-- steps it at 10 Hz and sends compact snapshots, every client draws and interpolates (Replication rule).
-- Deterministic for a seed: the same setup + the same commands at the same steps replay the same battle.
-- Plain Lua 5.1-compatible syntax only.
--
-- The floor is a 2D rectangle (x, z) in studs, centred on the zone centre of the "Start" payload (BattleService
-- adds the Zone CFrame; the floor is at the CFrame's height). Units move, pick the nearest enemy (or the focus the
-- owner tapped), attack in range (melee or ranged by species), use their special when commanded and the meter is
-- full, retreat to their owner's anchor (half damage taken, slow regen, ATTACK locked for a moment), go down and
-- stay down until the battle ends. Bosses stand on the stage and run their attack patterns: every pattern attack
-- is TELEGRAPHED (an event with the shape and the hit time) so a team can RETREAT out of it; minion waves spawn at
-- HP thresholds; an enrage timer doubles the boss's damage. Every number lives in BattleCatalog / PetCatalog.
--
-- API (the contract):
--   BattleSim.new(setup) -> battle | nil, reason
--     setup = {
--       Mode = "Trial" | "Duel" | "Raid",            -- default "Duel"
--       Seed = n,                                     -- RNG seed (default 1)
--       Id = any,                                     -- optional battle id, echoed in Snapshot / Describe
--       Zone = n | { X = w, Z = d } | { w, d },       -- floor size in studs (default BattleCatalog.Zones[Mode])
--       Teams = { team... },                          -- see AddTeam
--       Trial = level,                                -- adds BattleCatalog.TrialTeam(level) on side 2
--       Boss = bossId,                                -- adds the boss (BattleCatalog.Bosses) on side 2 (Mode "Raid")
--       TimeLimit = seconds,                          -- default BattleCatalog.TimeLimits[Mode] (Raid: the boss's)
--       Specials = false,                             -- harness: nobody can cast specials
--     }
--     team = { Owner = userId | string, Side = 1 | 2, Name, Anchor = { x, z } | nil, Npc = bool, Auto = bool,
--              Specials = false (harness: this team never casts), Pets = { { Key, PetId, Def, Level, Tier, Slot,
--              NoSpecial = true (harness: this pet never casts) }... } }
--       Def may be a PetKeys.DefOf def (hybrids need it); otherwise Key / PetId is resolved through PetCatalog and
--       PetKeys. Npc / Auto teams cast their specials on their own (NPC trial teams, the harness); a player's team
--       casts only on the owner's "Special" command.
--   battle:Command(owner, action, arg) -> ok, reason
--       "Attack" (targetUnitId | nil: focus), "Retreat", "Special" (team slot 1-4), "Forfeit"
--   battle:Step(dt) -> events      advance dt seconds (clamped 0.02..0.5; the server uses 0.1) and return the
--       events of this step: { type = BattleSim.Events.X, ... } (Hit, Special, KO, Telegraph, Spawn, Enrage, Order,
--       Zone, Leave, End); an empty table while finished.
--   battle:Snapshot() -> { BattleId?, T, Units = { [id] = { x, z, hp, state, target?, meter, shield? } } }
--       compact numbers: x / z to 0.1 stud, hp / meter / shield integers, state = BattleSim.States code
--   battle:Result() -> nil while running, else { Mode, Reason, WinnerSide, Winners = { owner... },
--       Losers = { owner... }, Draw, Forfeit, Level (Trial), BossId (Raid), Damage = { [owner] = n },
--       Shares = { [owner] = 0..1 }, Duration, Survivors = { [owner] = n }, BossHp, BossMaxHp }
--   battle:Describe() -> the static "Start" payload: { BattleId?, Mode, Seed, Zone = { X, Z }, TimeLimit, Level,
--       BossId, Sides = { [side] = { owner... } }, Units = { unitInfo... } }
--   battle:StaticUnits() -> { unitInfo... }     unitInfo = { id, side, owner, slot, kind = "Pet" | "MiniBoss" |
--       "Boss" | "Minion", key, petId, boss (bossId), name, species, look (PetBuilder Look), element, elements,
--       maxHp, level, tier, scale, ranged, range, radius, special = { Id, Name, Kind, Color } }
--   battle:AddTeam(team) -> infos | nil, reason    (raids: a player joins; queues a Spawn event)
--   battle:RemoveTeam(owner) -> ok                 (raids: a player leaves; queues a Leave event)
--   battle:SetAnchor(owner, x, z) -> ok            (where the team retreats to; clamped to the floor)
--   battle:BossStatus() -> { BossId, Hp, MaxHp, Enraged, EndsIn, Players } | nil
--   battle:Time(), battle:IsFinished(), battle:Owners(), battle:TeamOf(owner) (read-only summary)
--   BattleSim.States  = { Idle = 0, Moving = 1, Attacking = 2, Retreating = 3, Casting = 4, Down = 5, Stunned = 6 }
--   BattleSim.StateNames[code] -> "Idle" ...
--   BattleSim.Events  = { Hit, Special, KO, Telegraph, Spawn, Enrage, Order, Zone, Leave, End }  (strings)
-- Event shapes:
--   Hit       { from, to, dmg, elem (1.5 / 0.75 when not neutral), special (kind), tele (telegraph id), zone = true,
--               absorbed (shield), retreat = true }
--   Special   { unit, kind, name, x, z, tx, tz, targets = { id... }, heals = { { id, amount }... }, shields = { id... },
--               stunned = { id... } }
--   KO        { unit, by, forfeit = true }
--   Telegraph { id, boss, name, attack, shape = "Circle" | "Line", x, z, r | angle (radians) + length + width,
--               at (battle time of the hit), hits (seconds until it), freeze, linger }
--   Spawn     { units = { unitInfo... }, wave, boss, owner }
--   Enrage    { unit }
--   Order     { owner, order = "Attack" | "Retreat" | "Forfeit", target }
--   Zone      { unit, kind, x, z, r, seconds, side }
--   Leave     { owner, units = { id... } }
--   End       { reason, winnerSide }

local Shared = script.Parent

local BattleSim = {}
BattleSim.__index = BattleSim
BattleSim.Version = 1

local floor, ceil, sqrt, max, min, huge, abs = math.floor, math.ceil, math.sqrt, math.max, math.min, math.huge, math.abs
local cos, sin, atan2, pi = math.cos, math.sin, math.atan2, math.pi

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
BattleSim.States = { Idle = 0, Moving = 1, Attacking = 2, Retreating = 3, Casting = 4, Down = 5, Stunned = 6 }
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
}
BattleSim.Orders = { Attack = "Attack", Retreat = "Retreat" }
BattleSim.Modes = { "Trial", "Duel", "Raid" }

local S_IDLE, S_MOVING, S_ATTACKING, S_RETREATING, S_CASTING, S_DOWN, S_STUNNED =
	BattleSim.States.Idle, BattleSim.States.Moving, BattleSim.States.Attacking, BattleSim.States.Retreating,
	BattleSim.States.Casting, BattleSim.States.Down, BattleSim.States.Stunned
local EV = BattleSim.Events
local ORDER_ATTACK, ORDER_RETREAT = "Attack", "Retreat"

local MAX_UNITS = 128 -- a raid of 8 teams x 4 pets + boss + waves stays far below this
local MIN_DT, MAX_DT = 0.02, 0.5
local ZONE_TICK = 0.5 -- zones (Storm clouds, lingering pools) hurt every enemy inside them this often (few events)

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
	-- a few warm-up rounds so neighbouring seeds diverge quickly
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
	HpScale = 3, DamageScale = 0.6, Variance = 0.12, MinHit = 1,
	RetreatDamageTaken = 0.5, RetreatRegenPerSecond = 0.02, RetreatLock = 1.5,
	MeterMax = 100, MeterStart = { 20, 50 }, MeterOnHit = 4, MeterOnHurt = 2, MeterPerSecond = 2,
	CastSeconds = 0.5, SpecialScale = 1, SeparationRadius = 2.6, RetargetSeconds = 0.5, EngageSlack = 0.6,
	NpcSpecialDelay = { 0.4, 1.4 }, KoMeterLoss = true,
}

local function damageRules()
	local bc = catalog()
	local d = bc and bc.Damage
	if type(d) == "table" then
		return d
	end
	return FALLBACK_DAMAGE
end

local function num(v, default)
	if finite(v) then
		return v
	end
	return default
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
	local candidates = { entry.Key, entry.PetId, entry.Id }
	for _, c in ipairs(candidates) do
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

-- inside a circle (unit body counts)
local function inCircle(u, x, z, r)
	local dx, dz = u.x - x, u.z - z
	local reach = r + u.radius
	return dx * dx + dz * dz <= reach * reach
end

-- inside a line segment from (x, z) along angle for `length`, half width + body radius
local function inLine(u, x, z, angle, length, width)
	local dx, dz = u.x - x, u.z - z
	local dirX, dirZ = cos(angle), sin(angle)
	local along = dx * dirX + dz * dirZ
	if along < -u.radius or along > length + u.radius then
		return false
	end
	local perp = abs(dx * dirZ - dz * dirX)
	return perp <= width / 2 + u.radius
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------
local function parseZone(mode, zone)
	local bc = catalog()
	local default = (bc and type(bc.Zones) == "table" and bc.Zones[mode]) or { X = 56, Z = 56 }
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
		noSpecials = spec.Specials == false, -- harness: this team never casts
		units = {},
		bySlot = {},
		order = ORDER_ATTACK,
		focus = nil,
		retreatAt = -huge,
		anchorX = 0,
		anchorZ = 0,
		damage = 0,
		forfeited = false,
		left = false,
		index = #self.teams + 1,
		hpShare = 0,
		powerMult = {},
		healthMult = 1,
	}
end

-- anchor positions: duel / trial sides face each other across z; raid teams stand around the boss
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
	if self.mode == "Raid" then
		local slots = 8
		local k = (self.raidSlots or 0)
		self.raidSlots = k + 1
		local angle = -pi / 2 + (k % slots) * (2 * pi / slots) + floor(k / slots) * (pi / slots)
		local r = min(hx, hz) - 7
		team.anchorX = cos(angle) * r
		team.anchorZ = sin(angle) * r
		return
	end
	-- several teams on one side spread along x
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

-- Damage.MeterStart: a number, or { lo, hi } rolled per pet with the battle's RNG
local function meterStart(self, D)
	local ms = D.MeterStart
	if type(ms) == "table" then
		local lo, hi = num(ms[1], 0), num(ms[2], 0)
		return lo + (hi - lo) * rand(self)
	end
	return num(ms, 0)
end

local function unitFromDef(self, team, def, entry, slot, kind, powerMult)
	local bc = catalog()
	local us = bc and bc.UnitStats and bc.UnitStats(def, entry.Level, entry.Tier)
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
	if kind == "MiniBoss" then
		local mb = (bc and bc.MiniBoss) or { Hp = 3, Power = 1.3, Scale = 1.7 }
		maxHp = maxHp * mb.Hp
		hit = hit * mb.Power
		radius = radius * 1.4
		scale = mb.Scale
	end
	local special = type(def.Special) == "table" and def.Special or nil
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
		maxHp = maxHp,
		hp = maxHp,
		hit = hit,
		interval = us.Interval,
		moveSpeed = us.MoveSpeed,
		range = us.Range,
		ranged = us.Ranged,
		radius = radius,
		specialPower = us.SpecialPower,
		specialFactor = min(1, num(us.SpecialFactor, 1)),
		specialKind = (special and not entry.NoSpecial) and special.Kind or nil, -- NoSpecial: harness only
		special = special,
		powerMult = powerMult or 1,
		level = num(entry.Level, 1),
		tier = entry.Tier or def.Tier or "Normal",
		scale = scale,
		x = 0,
		z = 0,
		px = 0,
		pz = 0,
		state = S_IDLE,
		target = nil,
		nextAttack = self.t + rand(self) * us.Interval * 0.6, -- desynchronised swings: no lockstep first-strike edge
		retargetAt = 0,
		meter = meterStart(self, D),
		shield = 0,
		shieldUntil = 0,
		stunUntil = 0,
		castUntil = 0,
		autoCastAt = nil,
		alive = true,
		gone = false,
		damage = 0,
	}
	self.units[id] = u
	return u
end

-- pets stand near their anchor, offset per slot toward the floor centre
local function placeTeamUnits(self, team)
	local cx, cz = -team.anchorX, -team.anchorZ
	local len = sqrt(cx * cx + cz * cz)
	if len < 0.01 then
		cx, cz, len = 0, 1, 1
	end
	cx, cz = cx / len, cz / len -- toward the centre
	local px, pz = -cz, cx -- perpendicular
	local n = #team.units
	for i, u in ipairs(team.units) do
		local spread = (i - (n + 1) / 2) * 2.6
		u.x = team.anchorX + cx * 3 + px * spread
		u.z = team.anchorZ + cz * 3 + pz * spread
		clampToFloor(self, u)
		u.px, u.pz = u.x, u.z
	end
end

local function unitInfo(u)
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
	}
	if u.boss then
		info.boss = u.boss.Id
	end
	if u.special then
		info.special = { Id = u.special.Id, Name = u.special.Name, Kind = u.special.Kind, Color = u.special.Color }
	end
	return info
end

-- Adds a team (also used by new). Returns the unit infos, or nil + reason.
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
	local maxSize = (bc and bc.MaxTeamSize) or 4
	local pets = type(spec.Pets) == "table" and spec.Pets or {}
	-- resolve defs first (synergy needs them all)
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
	local synPower = {} -- by def index (slots may be out of order)
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
		if finite(entry.Slot) and entry.Slot >= 1 and entry.Slot <= maxSize and not team.bySlot[floor(entry.Slot)] then
			slot = floor(entry.Slot)
		end
		team.powerMult[slot] = synPower[i] or 1
		local kind = entry.Boss and "MiniBoss" or "Pet"
		local u = unitFromDef(self, team, def, entry, slot, kind, synPower[i])
		if u then
			team.units[#team.units + 1] = u
			team.bySlot[slot] = u
			infos[#infos + 1] = u
		end
	end
	if #team.units == 0 then
		-- roll back
		self.teams[#self.teams] = nil
		self.teamByOwner[spec.Owner] = nil
		return nil, "NoPets"
	end
	placeTeamUnits(self, team)
	-- expected DPS / average hp bookkeeping (raids scale the boss with it)
	if bc and bc.ExpectedDps then
		team.dps = bc.ExpectedDps({ Pets = entries })
	else
		team.dps = 0
	end
	local out = {}
	for i, u in ipairs(infos) do
		out[i] = unitInfo(u)
	end
	if self.started then
		self:_refreshRaidScale()
		local boss = self.boss
		if boss and boss.alive and not team.npc and side == 1 then
			-- the newcomer's full share joins the boss; the group factor grows with the head count
			local n = self:_playerTeams()
			local before = self:_groupFactor(n - 1)
			local after = self:_groupFactor(n)
			local share = team.dps * boss.hpSeconds
			team.hpShare = share
			boss.maxHp = boss.maxHp * after / before + share * after
			boss.hp = boss.hp * after / before + share * after
		end
		self.pending[#self.pending + 1] = { type = EV.Spawn, units = out, owner = spec.Owner }
	end
	return out
end

-- player teams still in the raid (side 1, not NPC, not left)
function BattleSim:_playerTeams()
	local n = 0
	for _, team in ipairs(self.teams) do
		if team.side == 1 and not team.npc and not team.left then
			n = n + 1
		end
	end
	return n
end

function BattleSim:_groupFactor(n)
	local bc = catalog()
	if bc and bc.GroupFactor then
		return bc.GroupFactor(n)
	end
	return 1
end

local bossBasis -- defined with the boss patterns below

-- The boss's damage yardstick: the average pet MaxHp (and level) over the player teams
function BattleSim:_refreshRaidScale()
	local total, n, levels = 0, 0, 0
	for _, team in ipairs(self.teams) do
		if team.side == 1 and not team.left then
			for _, u in ipairs(team.units) do
				if u.kind == "Pet" or u.kind == "MiniBoss" then
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
	self.playerTeamCount = self:_playerTeams()
	-- minions scale with the participants (the same head-count factor as the boss: bossBasis of an average pet)
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
	local team = {
		owner = "boss",
		side = 2,
		name = def.Name,
		npc = true,
		auto = true,
		units = {},
		bySlot = {},
		order = ORDER_ATTACK,
		retreatAt = -huge,
		anchorX = 0,
		anchorZ = 0,
		damage = 0,
		forfeited = false,
		left = false,
		index = #self.teams + 1,
		powerMult = {},
		healthMult = 1,
		dps = 0,
	}
	self.teams[#self.teams + 1] = team
	self.teamByOwner["boss"] = team
	local playerTeams = {}
	for _, t in ipairs(self.teams) do
		if t.side == 1 and not t.npc then
			playerTeams[#playerTeams + 1] = t
		end
	end
	local hp = 1000
	local shares = {}
	if bc.BossHp then
		local specs = {}
		for i, t in ipairs(playerTeams) do
			specs[i] = { Pets = {} }
			for j, u in ipairs(t.units) do
				specs[i].Pets[j] = { Def = u.def, Level = u.level, Tier = u.tier }
			end
		end
		hp, shares = bc.BossHp(bossId, specs)
	end
	for i, t in ipairs(playerTeams) do
		t.hpShare = shares[i] or 0
	end
	local attacks = {}
	for i, a in ipairs(def.Attacks or {}) do
		attacks[i] = { def = a, nextAt = num(a.First, 6 + i * 6) } -- the first telegraph a few seconds in, then on cooldown
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
		maxHp = hp,
		hp = hp,
		hpSeconds = num(def.HpPerPlayer, 150),
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
		damage = 0,
		attacks = attacks,
		wavesDone = {},
		enraged = false,
		damageMult = 1,
		cooldownMult = 1,
	}
	self.units[id] = u
	team.units[1] = u
	team.bySlot[1] = u
	self.boss = u
	self.bossId = bossId
	return u
end

function BattleSim.new(setup)
	if type(setup) ~= "table" then
		return nil, "BadSetup"
	end
	local mode = setup.Mode
	if mode ~= "Trial" and mode ~= "Duel" and mode ~= "Raid" then
		mode = (setup.Boss ~= nil and "Raid") or (setup.Trial ~= nil and "Trial") or "Duel"
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
	self.order = {} -- scratch: the shuffled unit order of the current step
	self.order2 = {} -- scratch: target candidates
	self.result = nil
	self.started = false
	self.specialsEnabled = setup.Specials ~= false
	self.elemCache = {}
	self.nextTelegraphId = 1
	self.avgPetHp = 150
	self.avgPetLevel = 1
	local limits = (bc and bc.TimeLimits) or { Trial = 90, Duel = 120, Raid = 330 }
	self.timeLimit = num(setup.TimeLimit, limits[mode] or 120)

	local teams = type(setup.Teams) == "table" and setup.Teams or {}
	for _, spec in ipairs(teams) do
		if type(spec) == "table" then
			local infos, reason = self:AddTeam(spec)
			if not infos and reason == "DuplicateOwner" then
				return nil, reason
			end
		end
	end
	if setup.Trial ~= nil then
		local level = tonumber(setup.Trial)
		local npc = bc and bc.TrialTeam and bc.TrialTeam(level)
		if not npc then
			return nil, "UnknownTrial"
		end
		self.level = level
		local trial = bc.Trials[level]
		if trial and finite(trial.TimeLimit) and setup.TimeLimit == nil then
			self.timeLimit = trial.TimeLimit
		end
		local infos, reason = self:AddTeam(npc)
		if not infos then
			return nil, reason or "BadTrial"
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
	-- both sides must exist
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
	if side2 == 0 then
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

-- nil while the battle runs; afterwards the result table (the same table every call)
function BattleSim:Result()
	return self.result
end

function BattleSim:Owners()
	local out = {}
	for _, team in ipairs(self.teams) do
		if not team.npc and not team.left then
			out[#out + 1] = team.owner
		end
	end
	return out
end

function BattleSim:StaticUnits()
	local out = {}
	for _, u in ipairs(self.units) do
		if not u.gone then
			out[#out + 1] = unitInfo(u)
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
		Level = self.level,
		BossId = self.bossId,
		Sides = sides,
		Units = self:StaticUnits(),
	}
end

function BattleSim:TeamOf(owner)
	local team = self.teamByOwner[owner]
	if not team then
		return nil
	end
	local units = {}
	for i, u in ipairs(team.units) do
		units[i] = { id = u.id, slot = u.slot, hp = u.hp, maxHp = u.maxHp, meter = u.meter, state = u.state, alive = u.alive }
	end
	return {
		Owner = team.owner,
		Side = team.side,
		Order = team.order,
		Focus = team.focus and team.focus.id or nil,
		Anchor = { x = team.anchorX, z = team.anchorZ },
		Damage = team.damage,
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
	local players = 0
	for _, team in ipairs(self.teams) do
		if team.side == 1 and not team.npc and not team.left then
			players = players + 1
		end
	end
	return {
		BossId = self.bossId,
		Name = b.name,
		Hp = max(0, floor(b.hp + 0.5)),
		MaxHp = floor(b.maxHp + 0.5),
		Enraged = b.enraged,
		EndsIn = max(0, self.timeLimit - self.t),
		Players = players,
	}
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
			local s = { x = r1(u.x), z = r1(u.z), hp = hp, state = u.state, meter = floor(u.meter + 0.5) }
			local tgt = u.target
			if tgt and tgt.alive and not tgt.gone then
				s.target = tgt.id
			end
			if u.shield > 0 then
				s.shield = floor(u.shield + 0.5)
			end
			units[u.id] = s
		end
	end
	return { BattleId = self.id, T = r1(self.t), Units = units }
end

----------------------------------------------------------------------
-- Damage
----------------------------------------------------------------------
local function elemMult(self, attacker, victim)
	local key = attacker.id * MAX_UNITS + victim.id
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

local function knockOut(self, u, by, events, forfeit)
	u.alive = false
	u.hp = 0
	u.state = S_DOWN
	u.target = nil
	u.shield = 0
	if damageRules().KoMeterLoss then
		u.meter = 0
	end
	local ev = { type = EV.KO, unit = u.id, by = by and by.id or nil }
	if forfeit then
		ev.forfeit = true
	end
	events[#events + 1] = ev
end

-- Applies `amount` of damage from `attacker` (may be nil for zones / telegraphs with a source unit in `by`) to `victim`.
-- Returns the damage dealt (after retreat reduction and shields). `extra` fields are copied into the Hit event.
local function applyDamage(self, attacker, victim, amount, events, extra, noVariance)
	if not victim.alive or victim.gone or amount <= 0 then
		return 0
	end
	local D = damageRules()
	local dmg = amount
	local mult = 1
	if attacker then
		mult = elemMult(self, attacker, victim)
		dmg = dmg * mult * (attacker.powerMult or 1)
	end
	local crit = false
	if not noVariance then
		local v = D.Variance
		dmg = dmg * (1 - v + 2 * v * rand(self))
		-- plain pet attacks (not specials, bosses or zones) land critical hits now and then: a visible swing
		local critRules = D.Crit
		if attacker and attacker.kind ~= "Boss" and extra == nil and type(critRules) == "table" and rand(self) < num(critRules.Chance, 0) then
			dmg = dmg * num(critRules.Mult, 1.5)
			crit = true
		end
	end
	local retreating = victim.team.order == ORDER_RETREAT and victim.kind ~= "Boss"
	if retreating then
		dmg = dmg * D.RetreatDamageTaken
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
	if attacker then
		attacker.damage = attacker.damage + dmg
		attacker.team.damage = attacker.team.damage + dmg
		-- only plain attacks build the meter (a special's own hits, zones and telegraphs never refund it)
		if attacker.kind ~= "Boss" and attacker.alive and extra == nil then
			attacker.meter = min(D.MeterMax, attacker.meter + D.MeterOnHit)
		end
	end
	if victim.kind ~= "Boss" then
		victim.meter = min(D.MeterMax, victim.meter + D.MeterOnHurt)
	end
	local ev = { type = EV.Hit, from = attacker and attacker.id or nil, to = victim.id, dmg = floor(dmg + 0.5) }
	if mult ~= 1 then
		ev.elem = mult
	end
	if crit then
		ev.crit = true
	end
	if absorbed > 0 then
		ev.absorbed = floor(absorbed + 0.5)
	end
	if retreating then
		ev.retreat = true
	end
	if extra then
		for k, v in pairs(extra) do
			ev[k] = v
		end
	end
	events[#events + 1] = ev
	if victim.hp <= 0 then
		knockOut(self, victim, attacker, events)
	end
	return dmg + absorbed
end

----------------------------------------------------------------------
-- Targeting
----------------------------------------------------------------------
-- nearest living enemy, judged on start-of-step positions (px / pz) so every unit picks from the same picture of
-- the floor whatever its place in the update order
local function nearestEnemy(self, u, maxDist)
	local best, bestD2 = nil, (maxDist and maxDist * maxDist) or huge
	local list = self.units
	local side = u.side
	for i = 1, #list do
		local e = list[i]
		if e.side ~= side and e.alive and not e.gone then
			local dx, dz = e.px - u.px, e.pz - u.pz
			local d2 = dx * dx + dz * dz
			if d2 < bestD2 then
				best, bestD2 = e, d2
			end
		end
	end
	return best, bestD2
end

-- A pet keeps its current target while that one is still close to the nearest enemy (sticky), otherwise it picks
-- at random among the enemies about as near as the nearest: who gets focused and who is spared varies from fight
-- to fight, so a small edge in power is not a certain win (the owner's focus command overrides all of this).
local function pickTarget(self, u)
	local focus = u.team.focus
	if focus and focus.alive and not focus.gone and focus.side ~= u.side then
		return focus
	end
	local nearest, dmin2 = nearestEnemy(self, u)
	if not nearest then
		return nil
	end
	local D = damageRules()
	local sticky = num(D.TargetSticky, 1.6)
	local cur = u.target
	if cur and cur.alive and not cur.gone and cur.side ~= u.side then
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
		if e.side ~= side and e.alive and not e.gone then
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
		if e.side ~= side and e.alive and not e.gone then
			out[#out + 1] = e
		end
	end
	return out
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
	local base = u.specialPower * D.DamageScale * num(S.Scale, 1) * num(D.SpecialScale, 1)
	local offensive = kind ~= "Heal" and kind ~= "Shield"
	local target = nil
	if offensive then
		target = pickTarget(self, u)
		if not target then
			return false, "NoTarget"
		end
		if kind == "Pounce" and dist(u.x, u.z, target.x, target.z) > num(S.Range, 30) + target.radius then
			-- too far for the dash: pounce the nearest instead
			target = nearestEnemy(self, u, num(S.Range, 30) + 3)
			if not target then
				return false, "TooFar"
			end
		end
	end
	u.meter = 0
	u.castUntil = self.t + D.CastSeconds
	u.state = S_CASTING
	if u.nextAttack < u.castUntil then
		u.nextAttack = u.castUntil
	end
	u.autoCastAt = nil
	local ev = { type = EV.Special, unit = u.id, kind = kind, name = u.special and u.special.Name or kind, x = r1(u.x), z = r1(u.z) }
	if target then
		ev.tx, ev.tz = r1(target.x), r1(target.z)
		ev.target = target.id
	end
	local position = #events + 1 -- the Special event goes before the hits it causes
	local extra = { special = kind }
	if kind == "Blast" then
		local r = num(S.Radius, 7)
		local hits = {}
		for _, e in ipairs(livingEnemies(self, u.side)) do
			if inCircle(e, target.x, target.z, r) then
				hits[#hits + 1] = e
			end
		end
		ev.targets = {}
		for _, e in ipairs(hits) do
			ev.targets[#ev.targets + 1] = e.id
			applyDamage(self, u, e, base, events, extra)
		end
	elseif kind == "Heal" then
		ev.heals = {}
		for _, a in ipairs(u.team.units) do
			if a.alive and not a.gone and a.hp < a.maxHp then
				local amount = min(base, a.maxHp - a.hp)
				a.hp = a.hp + amount
				ev.heals[#ev.heals + 1] = { a.id, floor(amount + 0.5) }
			end
		end
	elseif kind == "Shield" then
		ev.shields = {}
		for _, a in ipairs(u.team.units) do
			if a.alive and not a.gone then
				if a.shield < base then
					a.shield = base
				end
				a.shieldUntil = self.t + num(S.Seconds, 8)
				ev.shields[#ev.shields + 1] = a.id
			end
		end
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
		-- dash next to the target and strike
		local dx, dz = target.x - u.x, target.z - u.z
		local d = sqrt(dx * dx + dz * dz)
		local stop = target.radius + u.radius + 0.5
		if d > stop then
			u.x = target.x - dx / d * stop
			u.z = target.z - dz / d * stop
			clampToFloor(self, u)
		end
		ev.targets = { target.id }
		applyDamage(self, u, target, base, events, extra)
	elseif kind == "Freeze" then
		local r = num(S.Radius, 7)
		local stun = num(S.Stun, 2) * (u.specialFactor or 1)
		ev.targets, ev.stunned = {}, {}
		for _, e in ipairs(livingEnemies(self, u.side)) do
			if inCircle(e, target.x, target.z, r) then
				ev.targets[#ev.targets + 1] = e.id
				if e.kind ~= "Boss" then
					local untilT = self.t + stun
					if e.stunUntil < untilT then
						e.stunUntil = untilT
					end
					e.state = S_STUNNED
					ev.stunned[#ev.stunned + 1] = e.id
				end
				applyDamage(self, u, e, base, events, extra)
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
				applyDamage(self, u, e, base, events, extra)
			end
		end
	else
		-- unknown kind: a plain strong hit
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
			if a.alive and a.hp < a.maxHp * 0.8 then
				return true
			end
		end
		return false
	elseif kind == "Shield" then
		for _, a in ipairs(u.team.units) do
			if a.alive and a.hp < a.maxHp * 0.95 and a.shield <= 0 then
				return true
			end
		end
		return false
	end
	return true
end

----------------------------------------------------------------------
-- Boss patterns
----------------------------------------------------------------------
-- the boss's damage yardstick for one victim: a blend of its own max HP and the raid's average, scaled by the
-- head count (BossRules.DamageGroup: a lone team faces a gentler boss, a full arena the real thing)
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

-- the point where the most enemy pets stand (within r of one of them)
local function clusterPoint(self, boss, r)
	local enemies = livingEnemies(self, boss.side)
	local best, bestCount = nil, -1
	for _, p in ipairs(enemies) do
		local count = 0
		for _, q in ipairs(enemies) do
			local dx, dz = q.x - p.x, q.z - p.z
			if dx * dx + dz * dz <= r * r then
				count = count + 1
			end
		end
		if count > bestCount then
			best, bestCount = p, count
		end
	end
	return best
end

-- the points an attack lands on. Circles: one per CirclesPerTeams player teams (max MaxCircles), each on a different
-- cluster / random pet, so big raids keep everyone busy; lines always aim at one point (Count fans them).
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
		-- candidates not yet inside an earlier circle
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
		for k = 1, count do
			shapes[#shapes + 1] = { x = boss.x, z = boss.z, angle = baseAngle + (k - (count + 1) / 2) * spread, length = num(a.Length, 40), width = num(a.Width, 5) }
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
			if finite(a.Freeze) and e.kind ~= "Boss" then
				local untilT = self.t + a.Freeze
				if e.stunUntil < untilT then
					e.stunUntil = untilT
				end
				e.state = S_STUNNED
				extra.freeze = a.Freeze
			end
			applyDamage(self, boss, e, fraction * bossBasis(self, e), events, extra)
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
	local players = 0
	for _, team in ipairs(self.teams) do
		if team.side == 1 and not team.left then
			players = players + 1
		end
	end
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
		local us = bc and bc.UnitStats and bc.UnitStats(petDef, self.avgPetLevel, "Normal")
		if not us then
			break
		end
		local angle = (k - 1) * (2 * pi / count) + self.t * 0.1
		local r = boss.radius + 3.5
		local u = {
			id = id,
			side = boss.side,
			team = boss.team,
			owner = boss.team.owner,
			slot = 0,
			kind = "Minion",
			def = petDef,
			key = petDef.Id,
			petId = petDef.Id,
			name = (def.Minions and def.Minions.Name) or petDef.Name,
			species = us.Species,
			elems = us.Elements,
			maxHp = num(rules.MinionHp, 0.9) * self.avgPetHp,
			hp = 0,
			hit = num(rules.MinionDamage, 0.05) * bossBasis(self, { maxHp = self.avgPetHp }),
			interval = num(rules.MinionInterval, 1.4),
			moveSpeed = us.MoveSpeed,
			range = us.Range,
			ranged = us.Ranged,
			radius = us.Radius,
			specialPower = 0,
			specialKind = nil,
			special = nil,
			powerMult = 1,
			level = self.avgPetLevel,
			minion = true,
			tier = "Normal",
			scale = 1,
			x = boss.x + cos(angle) * r,
			z = boss.z + sin(angle) * r,
			px = 0,
			pz = 0,
			state = S_IDLE,
			target = nil,
			nextAttack = self.t + 1 + rand(self) * 0.8,
			retargetAt = 0,
			meter = 0,
			shield = 0,
			shieldUntil = 0,
			stunUntil = 0,
			castUntil = 0,
			alive = true,
			gone = false,
			damage = 0,
		}
		u.hp = u.maxHp
		clampToFloor(self, u)
		u.px, u.pz = u.x, u.z
		self.units[id] = u
		boss.team.units[#boss.team.units + 1] = u
		infos[#infos + 1] = unitInfo(u)
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
	-- enrage
	if not boss.enraged and finite(def.EnrageAt) and t >= def.EnrageAt then
		local rules = (catalog() and catalog().BossRules) or {}
		local en = type(rules.Enrage) == "table" and rules.Enrage or { Damage = 2, Cooldown = 0.7 }
		boss.enraged = true
		boss.damageMult = num(en.Damage, 2)
		boss.cooldownMult = num(en.Cooldown, 0.7)
		events[#events + 1] = { type = EV.Enrage, unit = boss.id }
	end
	-- minion waves at HP thresholds
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
	-- basic attack on the nearest pet in range
	if t >= boss.nextAttack then
		local target = nearestEnemy(self, boss, boss.range + boss.radius)
		if target then
			local basic = def.Basic or {}
			boss.target = target
			boss.state = S_ATTACKING
			applyDamage(self, boss, target, num(basic.Damage, 0.08) * boss.damageMult * bossBasis(self, target), events, { attack = basic.Name or "Basic" })
			boss.nextAttack = t + boss.interval * boss.cooldownMult
		else
			boss.state = S_IDLE
			boss.target = nearestEnemy(self, boss)
			boss.nextAttack = t + 0.5
		end
	end
	-- pattern attacks: one telegraph at a time per boss
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
					if e.side ~= zone.side and e.alive and not e.gone and inCircle(e, zone.x, zone.z, zone.r) then
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

local function unitStep(self, u, dt, events)
	local D = damageRules()
	local t = self.t
	local team = u.team
	-- timers
	if u.shield > 0 and t >= u.shieldUntil then
		u.shield = 0
	end
	if u.kind ~= "Boss" then
		u.meter = min(D.MeterMax, u.meter + D.MeterPerSecond * dt)
	end
	if t < u.stunUntil then
		u.state = S_STUNNED
		return
	end
	if t < u.castUntil then
		u.state = S_CASTING
		return
	end
	local retreating = team.order == ORDER_RETREAT
	if retreating then
		-- run home, regenerate
		if u.hp < u.maxHp then
			u.hp = min(u.maxHp, u.hp + u.maxHp * D.RetreatRegenPerSecond * dt)
		end
		local n = #team.units
		local idx = 1
		for i, v in ipairs(team.units) do
			if v == u then
				idx = i
			end
		end
		local cx, cz = -team.anchorX, -team.anchorZ
		local len = sqrt(cx * cx + cz * cz)
		if len < 0.01 then
			cx, cz, len = 0, 1, 1
		end
		local px, pz = -cz / len, cx / len
		local spread = (idx - (n + 1) / 2) * 2.4
		moveToward(u, team.anchorX + px * spread, team.anchorZ + pz * spread, u.moveSpeed * dt, 0.3)
		u.state = S_RETREATING
		u.target = nil
		return
	end
	-- auto specials (NPC / harness teams)
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
	-- targeting
	local target = u.target
	if not target or not target.alive or target.gone or t >= u.retargetAt or (team.focus and team.focus.alive and target ~= team.focus) then
		target = pickTarget(self, u)
		u.target = target
		u.retargetAt = t + D.RetargetSeconds
	end
	if not target then
		u.state = S_IDLE
		return
	end
	-- movement aims at where the target stood at the START of this step (px / pz), so the order in which units are
	-- updated gives nobody a head start; the reach test afterwards uses the real positions of both
	local reach = u.range + target.radius
	local tx, tz = target.px, target.pz
	local d = dist(u.x, u.z, tx, tz)
	if d > reach then
		if target.kind == "Boss" then
			-- orbit slot: every pet of a team approaches the boss on its own angle, so one telegraph cannot catch the
			-- whole team and the pets surround the boss instead of queueing on one line
			local ax, az = team.anchorX - tx, team.anchorZ - tz
			local base = atan2(az, ax)
			if ax == 0 and az == 0 then
				base = 0
			end
			local n = #team.units
			local idx = 1
			for i, v in ipairs(team.units) do
				if v == u then
					idx = i
				end
			end
			local angle = base + (idx - (n + 1) / 2) * (pi / 4)
			local r = reach - 0.5
			moveToward(u, tx + cos(angle) * r, tz + sin(angle) * r, u.moveSpeed * dt, 0.2)
		else
			moveToward(u, tx, tz, u.moveSpeed * dt, reach - 0.3)
		end
		u.state = S_MOVING
		d = dist(u.x, u.z, tx, tz)
	end
	-- the reach test also uses the target's start-of-step position: both sides judge range against where the
	-- other stood when the step began, so neither side swings a step earlier because it was updated later
	if d <= reach + D.EngageSlack then
		u.state = S_ATTACKING
		if t >= u.nextAttack then
			u.pendingTarget = target -- resolved with everyone else's attack after the movement phase (no first-strike bias)
		end
	elseif t >= u.nextAttack then
		-- on the way to a far target (a focus order, a kiting enemy) a ready pet still strikes whatever stands in reach
		local near, nd2 = nearestEnemy(self, u, u.range + 2.5 + D.EngageSlack)
		if near and nd2 <= (u.range + near.radius + D.EngageSlack) ^ 2 then
			u.pendingTarget = near
		end
	end
end

-- every attack that is ready lands at once, based on the positions after the whole movement phase, so neither side
-- gains from being updated first
local function resolveAttacks(self, events)
	local list = self.units
	local t = self.t
	for i = 1, #list do
		local u = list[i]
		local target = u.pendingTarget
		if target then
			u.pendingTarget = nil
			if not u.gone and target.alive and not target.gone then
				applyDamage(self, u, target, u.hit, events)
				-- swings drift +-10% so two equal units never stay in lockstep (the one updated first would
				-- otherwise land every killing blow a step early)
				u.nextAttack = t + u.interval * (0.9 + 0.2 * rand(self))
			end
		end
	end
end

-- push same-side units apart so they do not stack on one spot
local function separate(self)
	local D = damageRules()
	local r = D.SeparationRadius
	local r2 = r * r
	local list = self.units
	local n = #list
	for i = 1, n - 1 do
		local a = list[i]
		if a.alive and not a.gone and a.kind ~= "Boss" then
			for j = i + 1, n do
				local b = list[j]
				if b.alive and not b.gone and b.kind ~= "Boss" and b.side == a.side then
					local dx, dz = b.x - a.x, b.z - a.z
					local d2 = dx * dx + dz * dz
					if d2 < r2 then
						local d = sqrt(d2)
						local push
						if d < 0.001 then
							dx, dz, d = ((i % 2 == 0) and 1 or -1), 0.3, 1
						end
						push = (r - d) * 0.5
						if push > 0.6 then
							push = 0.6
						end
						dx, dz = dx / d, dz / d
						a.x, a.z = a.x - dx * push, a.z - dz * push
						b.x, b.z = b.x + dx * push, b.z + dz * push
					end
				end
			end
		end
	end
end

local function sideAlive(self, side)
	local count = 0
	local list = self.units
	for i = 1, #list do
		local u = list[i]
		if u.side == side and u.alive and not u.gone then
			count = count + 1
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

local function finish(self, winnerSide, reason, events)
	local result = {
		Mode = self.mode,
		Reason = reason,
		WinnerSide = winnerSide,
		Winners = {},
		Losers = {},
		Draw = winnerSide == nil,
		Forfeit = self.forfeitSeen == true,
		Level = self.level,
		BossId = self.bossId,
		Damage = {},
		Shares = {},
		Duration = r1(self.t),
		Survivors = {},
		Hp = { [1] = sideHpFraction(self, 1), [2] = sideHpFraction(self, 2) },
	}
	local total = 0
	for _, team in ipairs(self.teams) do
		if not team.npc then
			result.Damage[team.owner] = floor(team.damage + 0.5)
			if team.side == 1 then
				total = total + team.damage
			end
			local alive = 0
			for _, u in ipairs(team.units) do
				if u.alive and not u.gone then
					alive = alive + 1
				end
			end
			result.Survivors[team.owner] = alive
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
		if not team.npc and team.side == 1 then
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

local function checkEnd(self, events)
	local alive1 = sideAlive(self, 1)
	local alive2 = sideAlive(self, 2)
	if self.mode == "Raid" then
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
			return
		end
		if alive1 == 0 then
			finish(self, 2, "Wipe", events)
			return
		end
		if self.t >= self.timeLimit then
			finish(self, 2, "Timeout", events)
			return
		end
		return
	end
	if alive1 == 0 and alive2 == 0 then
		finish(self, nil, "Draw", events)
	elseif alive1 == 0 then
		finish(self, 2, self.forfeitSeen and "Forfeit" or "Wipe", events)
	elseif alive2 == 0 then
		finish(self, 1, self.forfeitSeen and "Forfeit" or "Wipe", events)
	elseif self.t >= self.timeLimit then
		if self.mode == "Trial" then
			finish(self, 2, "Timeout", events)
		else
			local f1, f2 = sideHpFraction(self, 1), sideHpFraction(self, 2)
			if abs(f1 - f2) < 0.001 then
				finish(self, nil, "Timeout", events)
			else
				finish(self, (f1 > f2) and 1 or 2, "Timeout", events)
			end
		end
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
	-- queued events (joins / leaves between steps)
	if #self.pending > 0 then
		for _, ev in ipairs(self.pending) do
			events[#events + 1] = ev
		end
		self.pending = {}
	end
	-- boss: patterns, basic attack, waves, enrage; then telegraphs that land now
	if self.boss then
		bossStep(self, self.boss, events)
	end
	resolveTelegraphs(self, events)
	tickZones(self, events)
	-- every other unit: timers, retreat, specials, targeting, movement (against start-of-step positions), in a
	-- seeded random order each step so no side profits from being updated first
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
			unitStep(self, u, dt, events)
		end
	end
	resolveAttacks(self, events)
	separate(self)
	for i = 1, #list do
		local u = list[i]
		if u.alive and not u.gone then
			clampToFloor(self, u)
		end
	end
	checkEnd(self, events)
	return events
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------
function BattleSim:Command(owner, action, arg)
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
	local D = damageRules()
	local t = self.t
	if action == "Attack" then
		if team.order == ORDER_RETREAT then
			local ready = team.retreatAt + D.RetreatLock
			if t < ready then
				return false, "Regrouping", r1(ready - t)
			end
		end
		local focus = nil
		if arg ~= nil then
			local id = tonumber(arg)
			if not id or id ~= floor(id) then
				return false, "BadTarget"
			end
			local unit = self.units[id]
			if not unit or unit.gone or not unit.alive or unit.side == team.side then
				return false, "BadTarget"
			end
			focus = unit
		end
		team.focus = focus
		team.order = ORDER_ATTACK
		for _, u in ipairs(team.units) do
			if u.alive then
				u.retargetAt = 0
				if u.state == S_RETREATING then
					u.state = S_IDLE
				end
			end
		end
		self.pending[#self.pending + 1] = { type = EV.Order, owner = owner, order = "Attack", target = focus and focus.id or nil }
		return true
	elseif action == "Retreat" then
		if team.order == ORDER_RETREAT then
			return false, "AlreadyRetreating"
		end
		team.order = ORDER_RETREAT
		team.retreatAt = t
		team.focus = nil
		for _, u in ipairs(team.units) do
			if u.alive then
				u.target = nil
				u.autoCastAt = nil
				if u.state ~= S_STUNNED and u.state ~= S_CASTING then
					u.state = S_RETREATING
				end
			end
		end
		self.pending[#self.pending + 1] = { type = EV.Order, owner = owner, order = "Retreat" }
		return true
	elseif action == "Special" then
		if not self.specialsEnabled or team.noSpecials then
			return false, "Disabled"
		end
		local slot = tonumber(arg)
		if not slot or slot ~= floor(slot) then
			return false, "BadSlot"
		end
		local u = team.bySlot[slot]
		if not u then
			return false, "BadSlot"
		end
		if not u.alive then
			return false, "Down"
		end
		if not u.specialKind then
			return false, "NoSpecial"
		end
		if u.meter < D.MeterMax then
			return false, "Charging", floor(u.meter + 0.5)
		end
		if t < u.stunUntil then
			return false, "Stunned"
		end
		if t < u.castUntil then
			return false, "Casting"
		end
		if team.order == ORDER_RETREAT then
			return false, "Retreating"
		end
		local events = {}
		local ok, reason = castSpecial(self, u, events)
		if not ok then
			return false, reason
		end
		for _, ev in ipairs(events) do
			self.pending[#self.pending + 1] = ev
		end
		return true, reason
	elseif action == "Forfeit" then
		if self.mode == "Raid" then
			self:RemoveTeam(owner)
			return true
		end
		team.forfeited = true
		self.forfeitSeen = true
		local events = {}
		for _, u in ipairs(team.units) do
			if u.alive then
				knockOut(self, u, nil, events, true)
			end
		end
		self.pending[#self.pending + 1] = { type = EV.Order, owner = owner, order = "Forfeit" }
		for _, ev in ipairs(events) do
			self.pending[#self.pending + 1] = ev
		end
		return true
	end
	return false, "UnknownAction"
end

-- A team leaves (raids: LeaveRaid / disconnect). Its units vanish and the boss sheds their HP share.
function BattleSim:RemoveTeam(owner)
	local team = self.teamByOwner[owner]
	if not team or team.left or team.npc then
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
	end
	-- other teams focusing one of these retarget
	for _, other in ipairs(self.teams) do
		if other.focus and other.focus.gone then
			other.focus = nil
		end
	end
	local boss = self.boss
	if boss and boss.alive and team.hpShare > 0 then
		-- the leaver's share goes (at the boss's current HP fraction) and the group factor shrinks with the head count
		local n = self:_playerTeams() -- already excludes this team
		local before = self:_groupFactor(n + 1)
		local after = self:_groupFactor(n)
		local frac = boss.hp / boss.maxHp
		local maxHp = (boss.maxHp - team.hpShare * before) * after / before
		boss.maxHp = max(1, maxHp)
		boss.hp = max(1, min(frac * boss.maxHp, boss.maxHp))
		team.hpShare = 0
	end
	self:_refreshRaidScale()
	self.pending[#self.pending + 1] = { type = EV.Leave, owner = owner, units = ids }
	return true
end

return BattleSim
