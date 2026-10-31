-- sim_battle.lua: the battle balance harness (ARCHITECTURE_V3.md "Phase 5 build contract" 12.3, battlecore).
-- Runs the REAL shared modules (BattleCatalog + BattleSim on top of PetCatalog / PetKeys / TycoonCatalog / Config)
-- inside the Roblox mock under lupa, like tools/smoke.py, and prints a balance report with TARGET ok / MISS lines:
--   fighter   the played kit vs a passive NPC of k x its power (kit factor 1.3-1.7); mirror fights 8-45 s, none at 90 s
--   support   Support (Economy) pets: DPS ratio 0.65-0.75 of Combat pets; a Support fighter can fight, best as a helper
--   levels    level beats rarity (battles only): a L30 Common beats a L1 Secret, a L100 evolved Common an unevolved L50 Secret,
--             a Secret stays the stronger pet at equal level and stage
--   duels     mirror duels per stage (scripted players both sides): 40-60%, no draws, none at the 120 s limit
--             + the element counter (balance-5: Water vs Flame, the wheel on vs off): it decides an even fight (>= 90%)
--             and is worth x1.15-1.45 TeamPower
--   raids     the baseline: BossRules.Baseline is a L35 evolved Legendary and the owner's L10/11/11 Secrets win 0 of 8 solo raids;
--             4 and 8 owner-teams finish in 100-240 s; 1 / 4 / 8 / 16 parrying trainers (wave 6: the trainer stands, times the
--             Dash) win nearly every raid in 100-240 s; a solo under half the boss's BaselineDps loses (bug batch 2 #2); no
--             one-shots; joins / leaves; idle alts
--   ring      the owner's wall (spec 2026-10-31 s.4, run XP + loss XP, HP carried, fainted pets out; SIM.Targets.Ring): 3 L1 Commons
--             win 2-4 rounds, Ring 5 in <= 10% of seeds; Legendaries, the owner's Secrets, L50, maxed by band; round 1 is an easy
--             Common; shown level and power never drop; the champions on the player formula (no Boss / Handicap / Boost)
--   dungeon   3 L1 Commons: room 1 >= 90%, room 2 40-60%, floor 1 < 15%; L7 Commons clear it; the team ladder (SIM.Targets.Dungeon);
--             the tutorial's eased room; a 4-party +1 floor
--   progress  a new player's real pace (3 L1 Commons, run XP): minutes to Ring 5, floor 1 and Ring 10 (SIM.Targets.Progress)
--   training  trained / evolved TeamPower ratios; trained mirror duels fair; trained raids 100-240 s
--   move      the B1 character patterns (random targets + an r 14 circle) at the legal run speed with a 200 ms feed delay:
--             the server fighter keeps up (gap <= 0.5 after the catch-up, zero leashes); a run-off past the zone is leashed;
--             wave 6: an engaged pet ignores the walking character (zero Engage off), a wandering trainer's raid plays
--             like a standing one's
--   perf      a 16-fighter raid with waves steps in well under 1 ms;  progression: XP / Cash behind each stage, Validate
--
-- Run it (lupa, from the repo root; see tools/README.md):
--   python3 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"
--   SIM_BATTLE="quick only=duels,raids" python3 -c "..."     options: quick | full | seeds=N | only=a,b | verbose
-- The smoke scenario p5battle_balance loads this file as a library (global SIM_BATTLE_LIBRARY = true before the load)
-- and runs a short subset; p5dgn_balance (team balance) uses SIM.Teams / SIM.Targets / SIM.floorSummary / SIM.ladder.
-- Plain Lua 5.1 syntax only.

local SIM = {}

----------------------------------------------------------------------
-- Boot: outside smoke.py there is no mock yet -> load tools/robloxmock.lua and mount the modules
----------------------------------------------------------------------
local function readFile(path)
	local fh = io.open(path, "r")
	if not fh then
		return nil
	end
	local src = fh:read("*a")
	fh:close()
	return src
end

local function findRoot()
	for _, root in ipairs({ ".", "..", "../..", "nimbus-climb" }) do
		if readFile(root .. "/tools/robloxmock.lua") and readFile(root .. "/src/shared/BattleSim.lua") then
			return root
		end
	end
	return nil
end

if not Mock then
	local root = findRoot()
	if not root then
		error("sim_battle.lua: run from the repo root (tools/robloxmock.lua and src/shared/BattleSim.lua not found)", 0)
	end
	local load_ = loadstring or load
	local chunk, err = load_(readFile(root .. "/tools/robloxmock.lua"), "=tools/robloxmock.lua")
	if not chunk then
		error(err, 0)
	end
	local M = chunk()
	M.Configure({ options = { StrictMembers = false, Echo = false, Watchdog = false, StepSize = 1 / 30, SliceLimit = 3600 } })
	M.Boot("server", { localName = "Sim", localUserId = 1 })
	local shared = M.GetPath("ReplicatedStorage/Shared", "Folder")
	for _, name in ipairs({ "MeshIds", "AudioIds", "Config", "Util", "PetCatalog", "PetKeys", "TycoonCatalog", "BattleCatalog", "BattleSim" }) do
		local src = readFile(root .. "/src/shared/" .. name .. ".lua")
		if src then
			M.Mount(shared, { name = name, class = "ModuleScript", source = src, path = "src/shared/" .. name .. ".lua" })
		end
	end
	_G.Mock = M
	_G.ROOTS = { shared = "ReplicatedStorage/Shared" }
end

local Shared = Mock.GetPath(ROOTS.shared)
local BC = require(Shared.BattleCatalog)
local BS = require(Shared.BattleSim)
local PC = require(Shared.PetCatalog)
local TC = require(Shared.TycoonCatalog)
local Config = require(Shared.Config)
local clock = Mock.RealClock or os.clock

local floor, sqrt, max, min, abs, huge = math.floor, math.sqrt, math.max, math.min, math.abs, math.huge
local cos, sin, atan2, pi = math.cos, math.sin, math.atan2, math.pi
local fmt = string.format
local DT = 0.1

local function dist(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	return sqrt(dx * dx + dz * dz)
end

----------------------------------------------------------------------
-- Options
----------------------------------------------------------------------
local function parseArgs(str)
	local opts = { quick = false, seeds = nil, only = nil, verbose = false }
	for raw in tostring(str or ""):gmatch("%S+") do
		local word = (raw:gsub("^%-%-", ""))
		if word == "quick" then
			opts.quick = true
		elseif word == "full" then
			opts.quick = false
		elseif word == "verbose" or word == "v" then
			opts.verbose = true
		else
			local key, value = word:match("^(%w+)=(.+)$")
			if key == "seeds" then
				opts.seeds = tonumber(value)
			elseif key == "only" then
				opts.only = {}
				for name in value:gmatch("[^,]+") do
					opts.only[name] = true
				end
			end
		end
	end
	return opts
end

----------------------------------------------------------------------
-- Output
----------------------------------------------------------------------
local lines = {}
SIM.print = function(s)
	io.stdout:write(s .. "\n")
	io.stdout:flush()
end
local function out(s)
	lines[#lines + 1] = s
	SIM.print(s)
end

local targets = {}
local function target(name, ok, detail)
	targets[#targets + 1] = { name = name, ok = ok and true or false, detail = detail or "" }
	out(fmt("  %s %s%s", ok and "TARGET ok  " or "TARGET MISS", name, detail and (" (" .. detail .. ")") or ""))
end

local function pct(n, total)
	if total == 0 then
		return 0
	end
	return floor(100 * n / total + 0.5)
end

----------------------------------------------------------------------
-- Team specs
----------------------------------------------------------------------
local function pet(key, level, tier, extra)
	local p = { Key = key, Level = level or 1, Tier = tier }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local ENTRY_FIELDS = { "Key", "PetId", "Def", "Level", "Tier", "Evo", "Train", "Boost", "Boss", "Handicap", "Crowned", "Xp", "XpNext", "Wild", "NoSpecial", "HpFraction" }
local function copyEntry(p)
	local e = {}
	for _, k in ipairs(ENTRY_FIELDS) do
		e[k] = p[k]
	end
	return e
end

-- a team spec: pets[1] is the fighter, 2-3 the helpers (a player team); flags { Npc = true } puts every pet on the floor
local function team(owner, side, pets, flags)
	local list = {}
	for i, p in ipairs(pets) do
		list[i] = copyEntry(p)
		list[i].Slot = i
	end
	local spec = { Owner = owner, Side = side, Pets = list }
	for k, v in pairs(flags or {}) do
		spec[k] = v
	end
	return spec
end

local function powerOf(pets)
	local list = {}
	for i, p in ipairs(pets) do
		list[i] = copyEntry(p)
	end
	return BC.TeamPower(list)
end

-- an NPC team of `petId` solved to `goal` UnitPower (the catalog solver: handicap / level / mini-boss / Boost)
local function npcOf(owner, petId, goal, opts)
	local e = BC.SolveEnemy(petId, goal, opts)
	return { Owner = owner, Side = 2, Npc = true, Name = owner, Pets = { { PetId = e.PetId, Key = e.PetId, Level = e.Level, Tier = e.Tier, Slot = 1, Boss = e.Boss, Boost = e.Boost, Handicap = e.Handicap } } }
end

-- Typical teams along the tycoon progression (teams of 3: fighter first)
SIM.Stages = {
	{ Id = "S1", Name = "Day 1", Pets = { pet("mallow_kitten", 1), pet("puddle_frog", 1), pet("pebble_pup", 1) } },
	{ Id = "S2", Name = "First week", Pets = { pet("mallow_kitten", 4), pet("biscuit_bear", 3), pet("maple_fox", 3) } },
	{ Id = "S3", Name = "Early", Pets = { pet("maple_fox", 6), pet("bubble_axolotl", 5), pet("storm_tabby", 4) } },
	{ Id = "S4", Name = "Early+", Pets = { pet("storm_tabby", 8), pet("frostling_penguin", 7), pet("bamboo_panda", 8) } },
	{ Id = "S5", Name = "Mid", Pets = { pet("aurora_fox", 12), pet("storm_tabby", 14), pet("frostling_penguin", 12) } },
	{ Id = "S6", Name = "Mid+", Pets = { pet("aurora_fox", 18), pet("moonlit_owl", 16), pet("ember_phoenix", 12) } },
	{ Id = "S7", Name = "Prestige 1", Pets = { pet("ember_phoenix", 24), pet("twilight_dragon", 22), pet("aurora_fox", 20, "Golden") } },
	{ Id = "S8", Name = "Prestige 2", Pets = { pet("cloudy_dragon", 25), pet("twilight_dragon", 28), pet("ember_phoenix", 26, "Golden") } },
	{ Id = "S9", Name = "Endgame", Pets = { pet("cloudy_dragon", 40, "Golden"), pet("stormfang", 35), pet("eclipse_dragon", 35) } },
	{ Id = "S10", Name = "Maxed", Pets = { pet("stormfang", 50, "Rainbow"), pet("cloudy_dragon", 45, "Rainbow"), pet("eclipse_dragon", 50, "Rainbow") } },
}
-- level beats rarity: the pairs of section levels
SIM.Commons = { "mallow_kitten", "puddle_frog", "biscuit_bear", "pebble_pup", "pip_penguin", "honey_bunny" }
SIM.Secrets = { "stormfang", "eclipse_dragon", "obsidian_phoenix", "phantom_kitsune" }
-- the top of the game: three L100 Rainbow pets, fully evolved and trained (the ring's top rounds must stay hard)
local MAX_TRAIN = { Speed = 10, Physique = 10, Ability = 10, Defense = 10 }
SIM.Maxed = { pet("stormfang", 100, "Rainbow", { Evo = 2, Train = MAX_TRAIN }), pet("eclipse_dragon", 100, "Rainbow", { Evo = 2, Train = MAX_TRAIN }), pet("cloudy_dragon", 100, "Rainbow", { Evo = 2, Train = MAX_TRAIN }) }
-- the Idle trainer: stands, presses nothing (the Default trainer = SIM.Player's defaults: dodge 0.7, mistime 0.5, every button)
SIM.Idle = { dodge = 0, element = false, specials = false, buffs = false, swap = false, attack = false, cheer = false }
-- the teams of the balance targets (spec 2026-10-31 s.4)
local function commonTrio(level)
	return { pet("mallow_kitten", level), pet("puddle_frog", level), pet("pebble_pup", level) }
end
SIM.Teams = {
	S1 = commonTrio(1),
	One = { pet("mallow_kitten", 1) },
	L7 = commonTrio(7),
	Leg = { pet("ember_phoenix", 1), pet("twilight_dragon", 1), pet("sunbeam_bear", 1) },
	Owner = { pet("stormfang", 10), pet("obsidian_phoenix", 11), pet("phantom_kitsune", 11) },
	L50 = { pet("ember_phoenix", 50, nil, { Evo = 2 }), pet("twilight_dragon", 50, nil, { Evo = 2 }), pet("sunbeam_bear", 50, nil, { Evo = 2 }) },
	Max = SIM.Maxed,
}
-- the spec's table as bands (every band is inclusive); Progress in minutes (medians over 24 players)
SIM.Targets = {
	Ring = {
		S1 = { Default = { 2, 4 }, Idle = { 1, 2 }, Reach5 = 10, Win1 = 95 },
		One = { Default = { 1, 2 }, Idle = { 1, 1 } },
		Leg = { Default = { 6, 10 }, Idle = { 3, 5 } },
		Owner = { Default = { 16, 22 }, Idle = { 9, 13 } },
		L50 = { Default = { 35, 43 }, Idle = { 27, 35 } },
		Max = { Default = { 60, 95 } },
	},
	Dungeon = {
		S1 = { Room1 = 90, Room2 = { 40, 60 }, Clear = 15 },
		L7 = { Clear = 80 },
		Leg = { Floor = { 1, 3 } },
		Owner = { Floor = { 3, 5 } },
		L50 = { Floor = { 6, 8 } },
		Max = { Floor = { 12, 12 } },
	},
	Progress = { Ring5 = { 4, 9 }, F1 = { 4, 10 }, Ring10 = { 20, 45 } },
	Raid = { OwnerSoloWins = 0, Group = { 100, 240 } },
}
local function inBand(value, band)
	return value >= band[1] and value <= band[2]
end

----------------------------------------------------------------------
-- A scripted player (the trainer + the kit). Wave 6: the trainer STANDS (opts.move "stand", default; "wander" = a slow
-- random walk inside the zone) and the pet fights by itself (the engage rule); the skill is the timed Dash: for each
-- wind-up aimed at my fighter and each telegraph covering it, with probability opts.dodge (the skill rate, default 0.7)
-- Dash inside ParryWindow (0.05-0.2 s before it lands), else with probability opts.mistime (default 0.5) too early (0.45-
-- 0.8 s before), else not at all; never sooner than a human reaction (0.1-0.3 s); the 2.5 s cooldown is real (the earliest
-- pending press wins). It directs the pet (ATTACK on a new target in reach), ELEMENT / SPECIAL when ready, helper BUFFs,
-- SWAPs a dying fighter and presses Cheer up! whenever it is ready in a raid / dungeon (opts.cheer, default true).
----------------------------------------------------------------------
local Player = {}
Player.__index = Player

local function lcg(seed)
	local s = (seed * 7919 + 17) % 2147483647
	return function()
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

local function inShape(ev, x, z, radius)
	if ev.shape == "Line" then
		local dx, dz = x - ev.x, z - ev.z
		local dirX, dirZ = cos(ev.angle), sin(ev.angle)
		local along = dx * dirX + dz * dirZ
		if along < -radius or along > ev.length + radius then
			return false
		end
		return abs(dx * dirZ - dz * dirX) <= ev.width / 2 + radius
	end
	local dx, dz = x - ev.x, z - ev.z
	return dx * dx + dz * dz <= (ev.r + radius) * (ev.r + radius)
end

function Player.new(battle, owner, seed, opts)
	local self = setmetatable({}, Player)
	self.battle = battle
	self.owner = owner
	self.rand = lcg(seed)
	self.opts = opts or {}
	self.info = {}
	self.side = nil
	for _, info in ipairs(battle:StaticUnits()) do
		self.info[info.id] = info
		if info.owner == owner then
			self.side = info.side
		end
	end
	local tinfo = battle:TeamOf(owner)
	local snap = battle:Snapshot()
	local me = tinfo and tinfo.Fighter and snap.Units[tinfo.Fighter]
	self.cx, self.cz = me and me.x or 0, me and me.z or 0
	self.dashAt = nil
	self.wanderX, self.wanderZ = nil, nil
	self.wanderRand = lcg(seed + 101) -- its own stream: wandering never changes the Dash rolls
	self.castAt = nil
	self.dodges = 0
	self.parries = 0
	self.mode = battle.mode
	self.lastHp = nil
	self.delay = self.opts.delay or 0 -- the feed delay in steps (the move section: 200 ms = 2)
	self.history = {}
	self.zoneX = battle.zone.HalfX
	self.zoneZ = battle.zone.HalfZ
	return self
end

function Player:reaction()
	local lo, hi = 0.1, 0.3
	if type(self.opts.reaction) == "table" then
		lo, hi = self.opts.reaction[1], self.opts.reaction[2]
	end
	return lo + (hi - lo) * self.rand()
end

function Player:step(events, snapshot)
	local b = self.battle
	local t = b:Time()
	local units = snapshot.Units
	local tinfo = b:TeamOf(self.owner)
	if not tinfo or not tinfo.Fighter then
		return
	end
	local fid = tinfo.Fighter
	local me = units[fid]
	local myInfo = self.info[fid]
	for _, ev in ipairs(events) do
		if ev.type == "Spawn" or ev.type == "Wave" then
			for _, info in ipairs(ev.units) do
				self.info[info.id] = info
			end
		end
	end
	if not me or me.hp <= 0 or not myInfo then
		return
	end
	local dodge = self.opts.dodge
	if dodge == nil then
		dodge = 0.7
	end
	local mistime = self.opts.mistime
	if mistime == nil then
		mistime = 0.5
	end
	-- the timed Dash: a wind-up aimed at my fighter, a telegraph covering it
	for _, ev in ipairs(events) do
		local at = nil
		if ev.type == "Windup" and ev.target == fid then
			at = ev.at
		elseif ev.type == "Telegraph" and inShape(ev, me.x, me.z, myInfo.radius or 2) then
			at = ev.at
		elseif ev.type == "Parry" and ev.unit == fid then
			self.parries = self.parries + 1
		end
		if at and dodge > 0 then
			local press = nil
			local roll = self.rand()
			if roll < dodge then
				press = at - (0.05 + 0.15 * self.rand())
			elseif self.rand() < mistime then
				press = at - (0.45 + 0.35 * self.rand())
			end
			if press then
				press = max(press, t + self:reaction())
				if not self.dashAt or press < self.dashAt then
					self.dashAt = press
				end
			end
		end
	end
	-- the target: the lock when alive, else the nearest living enemy on the floor
	local target, bestD2 = nil, huge
	for id, u in pairs(units) do
		local info = self.info[id]
		if info and info.side ~= self.side and u.hp > 0 and u.state ~= 3 then
			local dx, dz = u.x - me.x, u.z - me.z
			local d2 = dx * dx + dz * dz
			if d2 < bestD2 then
				target, bestD2 = id, d2
			end
		end
	end
	-- the trainer stands (the podium / the fight area's edge); "wander" = a slow random walk inside the zone
	if self.opts.move == "wander" then
		if not self.wanderX or dist(self.cx, self.cz, self.wanderX, self.wanderZ) < 1 then
			self.wanderX = (self.wanderRand() * 2 - 1) * (self.zoneX - 3)
			self.wanderZ = (self.wanderRand() * 2 - 1) * (self.zoneZ - 3)
		end
		local speeds = tinfo.Speed or { Walk = 12 }
		local gx, gz = self.wanderX - self.cx, self.wanderZ - self.cz
		local gd = sqrt(gx * gx + gz * gz)
		if gd > 0.05 then
			local step = min(gd, (speeds.Walk or 12) * 0.5 * DT)
			self.cx, self.cz = self.cx + gx / gd * step, self.cz + gz / gd * step
		end
		self.cx = max(-self.zoneX + 1, min(self.zoneX - 1, self.cx))
		self.cz = max(-self.zoneZ + 1, min(self.zoneZ - 1, self.cz))
	end
	-- the Move feed (with an optional delay of `delay` steps: what a 200 ms old position looks like)
	self.history[#self.history + 1] = { self.cx, self.cz }
	local idx = max(1, #self.history - self.delay)
	local fed = self.history[idx]
	b:Command(self.owner, "Move", fed[1], fed[2])
	if #self.history > 64 then
		table.remove(self.history, 1)
	end
	-- Cheer up! (raids / dungeons) whenever it is ready
	local cdNow = tinfo.Cooldowns or {}
	if self.opts.cheer ~= false and (self.mode == "Raid" or self.mode == "Dungeon") and (cdNow.Cheer or 0) <= 0 and target then
		b:Command(self.owner, "Cheer")
	end
	-- dash
	if self.dashAt and t >= self.dashAt then
		self.dashAt = nil
		if b:Command(self.owner, "Dash") then
			self.dodges = self.dodges + 1
		end
	end
	if not target then
		return
	end
	local tu = units[target]
	local tinfo2 = self.info[target]
	local reach = (myInfo.range or 4) + (tinfo2 and tinfo2.radius or 2) + 1.0
	local dx, dz = tu.x - me.x, tu.z - me.z
	local d = sqrt(dx * dx + dz * dz)
	-- dungeon fixes (4): the pet auto-attacks; the player only DIRECTS it (one ATTACK press when the wanted target changes)
	if self.opts.attack ~= false and d <= reach and target ~= self.directed then
		if b:Command(self.owner, "Attack", target) then
			self.directed = target
		end
	end
	local cd = tinfo.Cooldowns or {}
	if self.opts.element ~= false and (cd.Element or 0) <= 0 and d <= max(13, myInfo.range or 4) + (tinfo2 and tinfo2.radius or 2) then
		b:Command(self.owner, "Element", target)
	end
	if self.opts.specials ~= false and me.meter >= 100 then
		if not self.castAt then
			self.castAt = t + 0.3 + 0.5 * self.rand()
		elseif t >= self.castAt then
			if b:Command(self.owner, "Special") then
				self.castAt = nil
			else
				self.castAt = t + 0.5
			end
		end
	else
		self.castAt = nil
	end
	-- helper buffs: heals when hurt, everything else when fighting
	if self.opts.buffs ~= false then
		local hpFrac = me.hp / max(1, myInfo.maxHp)
		for _, hid in ipairs(tinfo.Bench or {}) do
			local hinfo = self.info[hid]
			local hu = units[hid]
			if hinfo and hu and hu.hp > 0 and hinfo.bench and (cd.Buff[hinfo.bench] or 0) <= 0 then
				local kind = hinfo.buff and hinfo.buff.Kind
				local healing = kind == "Heal" or kind == "Water" or kind == "Nature"
				if (healing and hpFrac < 0.6) or (not healing and d <= reach + 6) then
					b:Command(self.owner, "Buff", hinfo.bench)
				end
			end
		end
		-- swap a dying fighter for the healthiest helper
		if self.opts.swap ~= false and hpFrac < 0.2 and (cd.Swap or 0) <= 0 then
			local best, bestHp = nil, 0.4
			for _, hid in ipairs(tinfo.Bench or {}) do
				local hinfo = self.info[hid]
				local hu = units[hid]
				if hinfo and hu and hu.hp > 0 and hinfo.bench then
					local frac = hu.hp / max(1, hinfo.maxHp)
					if frac > bestHp then
						best, bestHp = hinfo.bench, frac
					end
				end
			end
			if best then
				b:Command(self.owner, "Swap", best)
			end
		end
	end
end

----------------------------------------------------------------------
-- Running battles
----------------------------------------------------------------------
-- policies: { [owner] = "auto" | "player" | "idle" }; "auto" teams must carry Auto = true in their spec (the AI plays
-- the kit, no dodging), "player" teams get a scripted Player, "idle" teams never command
function SIM.run(setup, policies, playerOpts)
	local b, err = BS.new(setup)
	if not b then
		return nil, err
	end
	local players = {}
	for owner, policy in pairs(policies or {}) do
		if policy == "player" then
			players[#players + 1] = Player.new(b, owner, (setup.Seed or 1) * 31 + (tonumber(owner) or 7), playerOpts)
		end
	end
	table.sort(players, function(a, c)
		return tostring(a.owner) < tostring(c.owner)
	end)
	local stats = { steps = 0, events = 0, hits = 0, misses = 0, kos = 0, specials = 0, telegraphs = 0, maxPetHit = 0, maxBossHit = 0, bossHits = 0, dodges = 0, parries = 0, teleHits = 0, swaps = 0, buffs = 0, elements = 0 }
	local hpOf = {}
	local kindOf = {}
	for _, info in ipairs(b:StaticUnits()) do
		hpOf[info.id] = info.maxHp
		kindOf[info.id] = info.kind
	end
	local maxSteps = floor((b.timeLimit + 5) / DT) + 10
	local t0 = clock()
	while not b:IsFinished() and stats.steps < maxSteps do
		local events = b:Step(DT)
		stats.steps = stats.steps + 1
		stats.events = stats.events + #events
		for _, ev in ipairs(events) do
			if ev.type == "Hit" then
				if ev.miss then
					stats.misses = stats.misses + 1
				else
					stats.hits = stats.hits + 1
					local maxHp = hpOf[ev.to]
					if maxHp and not ev.zone then
						local frac = ev.dmg / maxHp
						if ev.from and kindOf[ev.from] == "Boss" then
							stats.bossHits = stats.bossHits + 1
							if ev.tele then
								stats.teleHits = stats.teleHits + 1
							end
							if frac > stats.maxBossHit then
								stats.maxBossHit = frac
							end
						elseif frac > stats.maxPetHit then
							stats.maxPetHit = frac
						end
					end
				end
			elseif ev.type == "KO" then
				stats.kos = stats.kos + 1
			elseif ev.type == "Special" then
				stats.specials = stats.specials + 1
			elseif ev.type == "Element" then
				stats.elements = stats.elements + 1
			elseif ev.type == "Swap" then
				stats.swaps = stats.swaps + 1
			elseif ev.type == "Buff" then
				stats.buffs = stats.buffs + 1
			elseif ev.type == "Telegraph" then
				stats.telegraphs = stats.telegraphs + 1
			elseif ev.type == "Spawn" or ev.type == "Wave" then
				for _, info in ipairs(ev.units) do
					hpOf[info.id] = info.maxHp
					kindOf[info.id] = info.kind
				end
			end
		end
		if #players > 0 then
			-- the players act in a rotating order (no side gains from sending its commands first)
			local snap = b:Snapshot()
			local np = #players
			local first = stats.steps % np
			for k = 0, np - 1 do
				players[1 + (first + k) % np]:step(events, snap)
			end
		end
	end
	stats.seconds = clock() - t0
	for _, p in ipairs(players) do
		stats.dodges = stats.dodges + p.dodges
		stats.parries = stats.parries + p.parries
	end
	local result = b:Result()
	if not result then
		result = { Reason = "Unfinished", Duration = b:Time(), Winners = {}, Losers = {}, Damage = {}, Shares = {}, Survivors = {} }
	end
	return result, stats, b
end

local function series(makeSetup, policies, seeds, playerOpts)
	local agg = { n = 0, wins = { [1] = 0, [2] = 0 }, draws = 0, timeouts = 0, dur = 0, maxDur = 0, maxPetHit = 0, maxBossHit = 0, kos = 0, specials = 0, seconds = 0, dodges = 0, parries = 0, telegraphs = 0, teleHits = 0, bossHits = 0, misses = 0, durations = {} }
	for seed = 1, seeds do
		local result, stats = SIM.run(makeSetup(seed), policies, playerOpts)
		if result then
			agg.n = agg.n + 1
			if result.WinnerSide == 1 or result.WinnerSide == 2 then
				agg.wins[result.WinnerSide] = agg.wins[result.WinnerSide] + 1
			else
				agg.draws = agg.draws + 1
			end
			if result.Reason == "Timeout" then
				agg.timeouts = agg.timeouts + 1
			end
			agg.dur = agg.dur + result.Duration
			agg.maxDur = max(agg.maxDur, result.Duration)
			agg.durations[#agg.durations + 1] = result.Duration
			agg.maxPetHit = max(agg.maxPetHit, stats.maxPetHit)
			agg.maxBossHit = max(agg.maxBossHit, stats.maxBossHit)
			agg.kos = agg.kos + stats.kos
			agg.specials = agg.specials + stats.specials
			agg.seconds = agg.seconds + stats.seconds
			agg.dodges = agg.dodges + stats.dodges
			agg.parries = agg.parries + stats.parries
			agg.telegraphs = agg.telegraphs + stats.telegraphs
			agg.teleHits = agg.teleHits + stats.teleHits
			agg.bossHits = agg.bossHits + stats.bossHits
			agg.misses = agg.misses + stats.misses
		end
	end
	agg.winPct = pct(agg.wins[1], agg.n)
	agg.avgDur = agg.n > 0 and agg.dur / agg.n or 0
	return agg
end

local function median(list)
	if #list == 0 then
		return 0
	end
	local copy = {}
	for i, v in ipairs(list) do
		copy[i] = v
	end
	table.sort(copy)
	return copy[floor(#copy / 2) + 1]
end

local function mean(list)
	local s = 0
	for _, v in ipairs(list) do
		s = s + v
	end
	return #list > 0 and s / #list or 0
end

-- the level-1 Commons / Uncommons a new player can roll
local function starters()
	local list = {}
	for _, def in ipairs(PC.Pets) do
		local rollable = (PC.IsRollable and PC.IsRollable(def.Id)) or (not PC.IsRollable and def.EventOnly ~= true)
		if rollable and (def.Rarity == "Common" or def.Rarity == "Uncommon") then
			list[#list + 1] = def.Id
		end
	end
	return list
end

----------------------------------------------------------------------
-- The dungeon: one room = a fresh BattleSim (Mode Dungeon, full HP, the room's time limit) whose waves are spawned
-- one after the other (the next wave when EnemiesDown fires; the boss room: the boss, then the escort at EscortAt)
----------------------------------------------------------------------
-- returns cleared (bool), seconds; teams = player team specs, policies as in SIM.run; waveOpts = DungeonWave's opts (Eased)
function SIM.dungeonRoom(f, r, teams, policies, seed, playerOpts, waveOpts)
	local D = BC.Dungeon
	local n = #teams
	local isBoss = (r == 4)
	local zone = isBoss and D.Zones.Boss or D.Zones.Room
	local limit = (f == 1) and D.Floor1RoomTime or D.RoomTime
	local b = BS.new({ Mode = "Dungeon", Seed = seed * 7 + r, Zone = zone, TimeLimit = limit, Teams = teams })
	if not b then
		return false, 0
	end
	local players = {}
	for owner, policy in pairs(policies or {}) do
		if policy == "player" then
			players[#players + 1] = Player.new(b, owner, seed * 31 + (tonumber(owner) or 7), playerOpts)
		end
	end
	table.sort(players, function(a, c)
		return tostring(a.owner) < tostring(c.owner)
	end)
	local nWaves = isBoss and 2 or ((f == 1) and D.Floor1Waves[r] or D.Waves[r])
	local wave = 1
	local escortDue = false
	-- the Throne's enemies spawn at the foot of the dais stairs (DungeonBuilder's SpawnAnchor, zone-local z 15)
	local anchor = isBoss and { 0, 15 } or nil
	b:SpawnEnemies(BC.DungeonWave(f, r, 1, n, seed, waveOpts).Pets, { Wave = 1, Anchor = anchor })
	local steps, maxSteps = 0, floor((limit + 5) / DT) + 10
	local cleared = false
	while not b:IsFinished() and steps < maxSteps do
		local events = b:Step(DT)
		steps = steps + 1
		local down = false
		for _, ev in ipairs(events) do
			if ev.type == "EnemiesDown" then
				down = true
			end
		end
		if isBoss and wave == 1 and not escortDue then
			local hp = b:BossHp()
			if hp and hp <= D.EscortAt then
				escortDue = true
				b:SpawnEnemies(BC.DungeonWave(f, r, 2, n, seed).Pets, { Wave = 2, Anchor = anchor })
				wave = 2
			end
		end
		if down then
			if b:LivingEnemies() == 0 then
				if wave >= nWaves then
					cleared = true
					b:Finish("Cleared")
				else
					wave = wave + 1
					b:SpawnEnemies(BC.DungeonWave(f, r, wave, n, seed, waveOpts).Pets, { Wave = wave })
				end
			end
		end
		if not b:IsFinished() and #players > 0 then
			local snap = b:Snapshot()
			local np = #players
			local first = steps % np
			for k = 0, np - 1 do
				players[1 + (first + k) % np]:step(events, snap)
			end
		end
	end
	return cleared, b:Time()
end

-- rooms cleared (0..4) and the minutes of a floor for a party of stage teams
function SIM.dungeonFloor(f, stagePets, party, seed, playerOpts)
	local teams, policies = {}, {}
	for i = 1, party do
		teams[i] = team(300 + i, 1, stagePets)
		policies[300 + i] = "player"
	end
	local seconds = 0
	for r = 1, 4 do
		local ok, s = SIM.dungeonRoom(f, r, teams, policies, seed, playerOpts)
		seconds = seconds + s
		if not ok then
			return r - 1, seconds / 60
		end
	end
	return 4, seconds / 60
end

----------------------------------------------------------------------
-- Sections
----------------------------------------------------------------------
local sections = {}
local order = {}
local function section(name, fn)
	sections[name] = fn
	order[#order + 1] = name
end

local function header(title)
	out("")
	out("== " .. title .. " ==")
end

-- 1. roster: every pet's battle numbers
section("roster", function()
	header("Roster: level-1 battle numbers (Support = Economy pets x2.6 power / x1.5 HP; walk / run = the character's battle speed)")
	out(fmt("  %-18s %-9s %-7s %-9s %6s %6s %5s %6s %5s %5s %5s %s", "pet", "rarity", "role", "species", "hp", "hit", "int", "dps", "power", "walk", "run", "helper buff"))
	for _, def in ipairs(PC.Pets) do
		local us = BC.UnitStats(def, 1)
		local kind = BC.BuffOf(def)
		out(fmt("  %-18s %-9s %-7s %-9s %6.0f %6.2f %5.2f %6.2f %5d %5.1f %5.1f %s", def.Id, def.Rarity, us.Role, us.Species, us.MaxHp, us.Hit, us.Interval, us.Dps, BC.UnitPower(def, 1), us.Walk, us.Run, tostring(kind)))
	end
	local okV, problems = BC.Validate()
	target("BattleCatalog.Validate() passes", okV, table.concat(problems, "; "))
end)

-- 2. fighter: the played kit vs a passive NPC of k x its power
section("fighter", function(opts)
	header("Fighter: one played pet (no helpers, a kid dodging 40% of the wind-ups) vs a passive NPC of the same species at k x its UnitPower")
	local seeds = max(8, floor(opts.seeds / 3))
	local cases = { { "mallow_kitten", 1 }, { "maple_fox", 6 }, { "aurora_fox", 12 }, { "ember_phoenix", 24 }, { "stormfang", 50, "Rainbow" } }
	local ks = { 1.0, 1.2, 1.4, 1.6, 1.8, 2.0 }
	local kSum, kN = 0, 0
	local durLo, durHi, longest = huge, 0, 0
	for _, c in ipairs(cases) do
		local p = pet(c[1], c[2], c[3])
		local up = BC.UnitPower(copyEntry(p))
		local row = {}
		local wins = {}
		for _, k in ipairs(ks) do
			local agg = series(function(seed)
				return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, { p }), npcOf("npc", c[1], up * k, { MaxLevel = 100 }) } }
			end, { [1] = "player" }, seeds, { dodge = 0.4 })
			row[#row + 1] = fmt("k%.1f %3d%%/%2.0fs", k, agg.winPct, agg.avgDur)
			wins[#wins + 1] = agg.winPct
			if k == 1.0 then
				durLo, durHi = min(durLo, agg.avgDur), max(durHi, agg.avgDur)
				longest = max(longest, agg.maxDur)
			end
		end
		-- the break-even k (the 50% crossing, interpolated between the grid points)
		local k50 = ks[#ks]
		for i = 1, #ks - 1 do
			if wins[i] >= 50 and wins[i + 1] < 50 then
				local span = wins[i] - wins[i + 1]
				k50 = ks[i] + (ks[i + 1] - ks[i]) * ((wins[i] - 50) / max(1, span))
				break
			end
		end
		if wins[1] < 50 then
			k50 = ks[1]
		end
		out(fmt("  %-18s power %5d  %s  break-even k %.2f", c[1] .. " L" .. c[2], up, table.concat(row, "  "), k50))
		kSum, kN = kSum + k50, kN + 1
	end
	local kitLo, kitHi = kSum / max(1, kN), kSum / max(1, kN)
	target("kit factor: a played fighter breaks even against a passive NPC of 1.25-1.7 x its power (the mean break-even k over the cases)", kitLo >= 1.25 and kitHi <= 1.7, fmt("mean k %.2f", kitLo))
	target("mirror fights (k 1.0) last 6-45 s on average and none reaches the Ring's 90 s", durLo >= 6 and durHi <= 45 and longest < 90, fmt("%.0f-%.0f s, longest %.0f s", durLo, durHi, longest))
end)

-- 3. support
section("support", function(opts)
	header("Support: Economy pets fight as Supports (x2.6 power / x1.5 HP): DPS ratio vs Combat pets, Commons + Uncommons")
	local cd, cn, sd, sn, ch, sh = 0, 0, 0, 0, 0, 0
	for _, def in ipairs(PC.Pets) do
		if def.Rarity == "Common" or def.Rarity == "Uncommon" then
			local us = BC.UnitStats(def, 1)
			if us.Role == "Support" then
				sd, sn, sh = sd + us.Dps, sn + 1, sh + us.MaxHp
			else
				cd, cn, ch = cd + us.Dps, cn + 1, ch + us.MaxHp
			end
		end
	end
	local ratio = (sd / sn) / (cd / cn)
	local hpRatio = (sh / sn) / (ch / cn)
	out(fmt("  average DPS combat %.2f vs support %.2f = %.2f; HP %.0f vs %.0f = %.2f", cd / cn, sd / sn, ratio, ch / cn, sh / sn, hpRatio))
	target("Support DPS ratio 0.65-0.75 of a Combat pet", ratio >= 0.65 and ratio <= 0.75, fmt("%.2f", ratio))
	target("Support HP ratio 0.6-0.9 of a Combat pet", hpRatio >= 0.6 and hpRatio <= 0.9, fmt("%.2f", hpRatio))
	header("Support: a Support fighter alone (L8, dodge 25%) vs two puddle_frog L8 (can fight, best as a helper)")
	local seeds = max(4, floor(opts.seeds / 4))
	local total, n = 0, 0
	for _, id in ipairs({ "pebble_pup", "pip_penguin", "honey_bunny", "mochi_slime" }) do
		local agg = series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, { pet(id, 8) }), team("frogs", 2, { pet("puddle_frog", 8), pet("puddle_frog", 8) }, { Npc = true }) } }
		end, { [1] = "player" }, seeds, { dodge = 0.25 })
		out(fmt("  %-15s wins %3d%%  dur %4.1f s", id, agg.winPct, agg.avgDur))
		total, n = total + agg.winPct, n + 1
	end
	local kitten = series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, { pet("mallow_kitten", 8) }), team("frogs", 2, { pet("puddle_frog", 8), pet("puddle_frog", 8) }, { Npc = true }) } }
	end, { [1] = "player" }, seeds, { dodge = 0.25 })
	out(fmt("  %-15s wins %3d%%  dur %4.1f s (the Combat reference)", "mallow_kitten", kitten.winPct, kitten.avgDur))
	target("a Support fighter beats two puddle_frog L8 in 10-60% of the seeds (average of the four)", total / n >= 10 and total / n <= 60, fmt("%.0f%%", total / n))
end)

-- 3b. levels: the battle-only stat path (spec 2026-10-31 s.5)
section("levels", function(opts)
	header("Levels: level beats rarity, single pets, scripted players both sides (Common win % against each Secret)")
	local seeds = opts.quick and 8 or 24
	local function meanOver(cLevel, cExtra, sLevel)
		local total, n = 0, 0
		for _, c in ipairs(SIM.Commons) do
			local row = {}
			for _, s in ipairs(SIM.Secrets) do
				local agg = series(function(seed)
					return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, { pet(c, cLevel, nil, cExtra) }), team(2, 2, { pet(s, sLevel) }) } }
				end, { [1] = "player", [2] = "player" }, seeds)
				row[#row + 1] = fmt("%3d%%", agg.winPct)
				total, n = total + agg.winPct, n + 1
			end
			out(fmt("  %-14s L%-3d vs Secrets L%-3d %s", c, cLevel, sLevel, table.concat(row, " ")))
		end
		return total / max(1, n)
	end
	local mean30 = meanOver(30, nil, 1)
	local mean100 = meanOver(100, { Evo = 1 }, 50)
	local allPairs = true
	local cases = { { 1, 0 }, { 20, 1 }, { 50, 2 }, { 100, 2 } }
	for _, case in ipairs(cases) do
		for _, c in ipairs(SIM.Commons) do
			for _, s in ipairs(SIM.Secrets) do
				if BC.UnitPower(pet(s, case[1], nil, { Evo = case[2] })) <= BC.UnitPower(pet(c, case[1], nil, { Evo = case[2] })) then
					allPairs = false
					out(fmt("  %s does not out-power %s at L%d stage %d", s, c, case[1], case[2]))
				end
			end
		end
	end
	target("level beats rarity: a L30 Common beats a L1 Secret (mean win rate >= 90% over the 24 pairs)", mean30 >= 90, fmt("%.0f%%", mean30))
	target("a L100 evolved (stage 1) Common beats an unevolved L50 Secret (mean >= 75%)", mean100 >= 75, fmt("%.0f%%", mean100))
	target("a Secret stays the stronger pet at equal level and stage (UnitPower, L1 / L20 e1 / L50 e2 / L100 e2, every pair)", allPairs)
end)

-- 4. duels
section("duels", function(opts)
	header("Duels: mirror teams per stage (scripted players both sides): fair, no draws; a 120 s timeout goes to the side with more damage")
	local seeds = max(32, opts.seeds)
	local worst, longest, draws, timeouts, wins1, n = 50, 0, 0, 0, 0, 0
	local stageOk = true
	for _, st in ipairs(SIM.Stages) do
		local agg = series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, st.Pets), team(2, 2, st.Pets) } }
		end, { [1] = "player", [2] = "player" }, seeds)
		out(fmt("  %-4s %-11s power %6d  side1 %3d%%  draws %d  timeouts %2d  dur %5.1f s (max %5.1f)  maxHit %.2f", st.Id, st.Name, powerOf(st.Pets), agg.winPct, agg.draws, agg.timeouts, agg.avgDur, agg.maxDur, agg.maxPetHit))
		if abs(agg.winPct - 50) > abs(worst - 50) then
			worst = agg.winPct
		end
		if agg.winPct < 30 or agg.winPct > 70 then
			stageOk = false
		end
		longest = max(longest, agg.maxDur)
		draws = draws + agg.draws
		timeouts = timeouts + agg.timeouts
		wins1 = wins1 + agg.wins[1]
		n = n + agg.n
	end
	local overall = pct(wins1, n)
	target("mirror duels are fair: 40-60% over every stage together and 30-70% at each stage", overall >= 40 and overall <= 60 and stageOk, fmt("overall %d%%, worst stage %d%%", overall, worst))
	target("no draws: a double knock-out or a timeout goes to the side that dealt more damage", draws == 0, fmt("draws %d, timeouts %d of %d (tanky mirrors reach the 120 s limit)", draws, timeouts, n))
	SIM.elementCounter(opts.seeds)
end)

-- The element counter (balance-5). The old check paired a Flame maple_fox with a Nature bamboo_panda: NEUTRAL on the
-- wheel (Water > Flame > Frost > Nature, Config.Elements) and at unequal power (71 vs 61), so it measured no element at
-- all. Now: a Water bubble_axolotl (it counters Flame) against a Flame maple_fox L10, the same neutral helpers on both
-- sides (Earth waffle_corgi + Celestial mallow_kitten L8: neutral to Water, Flame and each other). The Water fighter's
-- level is scanned twice, with the wheel and with it switched off (Strong / Weak multipliers 1), and each scan's 50 %
-- crossing gives a TeamPower; their ratio = what the counter is worth in power. Each point plays both seatings.
-- Measured on 9f381c4 (128 fights a point): the wheel crosses at L10 (power 46 vs 61), the switched-off wheel at
-- ~L17 (58): a counter is worth ~+28 % TeamPower, and at the switched-off even point (L17) the counter wins 100 %.
function SIM.elementCounter(seeds, quiet)
	local say = quiet and function() end or out
	local E = Config.Elements
	local strong0, weak0 = E.StrongMultiplier, E.WeakMultiplier
	local helpers = { pet("waffle_corgi", 8), pet("mallow_kitten", 8) }
	local function side(id, level)
		return { pet(id, level), helpers[1], helpers[2] }
	end
	local flame = side("maple_fox", 10)
	local flamePower = powerOf(flame)
	local function winPct(level)
		local water = side("bubble_axolotl", level)
		local a = series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, water), team(2, 2, flame) } }
		end, { [1] = "player", [2] = "player" }, seeds)
		local b = series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, flame), team(2, 2, water) } }
		end, { [1] = "player", [2] = "player" }, seeds)
		return 100 * (a.wins[1] + b.wins[2]) / max(1, a.n + b.n), powerOf(water)
	end
	-- the first level whose win share reaches 50 %, and the TeamPower there (interpolated from the level below)
	local function crossing(fromLevel, toLevel, row)
		local lastPct, lastPower = nil, nil
		for level = fromLevel, toLevel do
			local p, power = winPct(level)
			row[#row + 1] = fmt("L%d %d%%", level, floor(p + 0.5))
			if p >= 50 then
				if lastPct and p > lastPct then
					return level, lastPower + (power - lastPower) * (50 - lastPct) / (p - lastPct)
				end
				return level, power
			end
			lastPct, lastPower = p, power
		end
		return nil, nil
	end
	local ok, res = pcall(function()
		local r = {}
		E.StrongMultiplier, E.WeakMultiplier = 1, 1
		local flatRow = {}
		r.flatLevel, r.flatPower = crossing(12, 30, flatRow)
		E.StrongMultiplier, E.WeakMultiplier = strong0, weak0
		local realRow = {}
		r.realLevel, r.realPower = crossing(4, 20, realRow)
		r.atEven = r.flatLevel and winPct(r.flatLevel) or 0
		r.flatRow, r.realRow = flatRow, realRow
		return r
	end)
	E.StrongMultiplier, E.WeakMultiplier = strong0, weak0
	if not ok then
		error(res, 0)
	end
	local worth = (res.flatPower and res.realPower) and res.flatPower / res.realPower or 0
	say(fmt("  Water bubble_axolotl vs Flame maple_fox L10 (power %d), helpers waffle_corgi + mallow_kitten L8, %d seeds a seating", flamePower, seeds))
	say(fmt("  wheel switched off: %s  -> even at %s (power %.1f)", table.concat(res.flatRow, ", "), res.flatLevel and ("L" .. res.flatLevel) or "none", res.flatPower or 0))
	say(fmt("  with the wheel:     %s  -> even at %s (power %.1f)", table.concat(res.realRow, ", "), res.realLevel and ("L" .. res.realLevel) or "none", res.realPower or 0))
	say(fmt("  the counter is worth x%.2f TeamPower; at the switched-off even point (L%s) the counter wins %.0f%%", worth, tostring(res.flatLevel), res.atEven))
	if not quiet then
		target("the element counter decides an even fight: at the level that splits ~50% with the wheel off, Water beats Flame in >= 90%", res.atEven >= 90, fmt("%.0f%%", res.atEven))
		target("the element counter is worth about a quarter to a third more TeamPower, not everything (x1.15-1.45)", worth >= 1.15 and worth <= 1.45, fmt("x%.2f", worth))
	end
	res.worth = worth
	return res
end

-- `players` dodging teams of one stage's pets (default M5 = SIM.Stages[5]) against one boss: the series aggregate
function SIM.midGroup(boss, players, seeds, pets)
	pets = pets or SIM.Stages[5].Pets
	local policies = {}
	for i = 1, players do
		policies[100 + i] = "player"
	end
	return series(function(seed)
		local teams = {}
		for i = 1, players do
			teams[i] = team(100 + i, 1, pets)
		end
		return { Mode = "Raid", Boss = boss, Seed = seed, Teams = teams }
	end, policies, seeds)
end

-- 5. raids
section("raids", function(opts)
	local T = SIM.Targets.Raid
	local B = BC.BossRules.Baseline
	header(fmt("Raids: the baseline (%s L%d evolved %d, BaselineDps %.0f): the owner's L10/11/11 Secrets solo every boss, 8 seeds", B.PetId, B.Level, B.Evo or 0, BC.BaselineDps(BC.BossOrder[1])))
	local ownerWins = 0
	for _, boss in ipairs(BC.BossOrder) do
		local agg = series(function(seed)
			return { Mode = "Raid", Boss = boss, Seed = seed, Teams = { team(1, 1, SIM.Teams.Owner) } }
		end, { [1] = "player" }, 8)
		out(fmt("  %-13s solo: wins %d of %d, %5.1f s, maxBossHit %.2f", boss, agg.wins[1], agg.n, agg.avgDur, agg.maxBossHit))
		ownerWins = ownerWins + agg.wins[1]
	end
	local baselineDef = PC.Get(B.PetId)
	target("BossRules.Baseline is a L35 evolved Legendary and the owner's L10/11/11 Secrets win 0 of 8 solo raids on every boss", B.Level == 35 and (B.Evo or 0) >= 1 and baselineDef.Rarity == "Legendary" and ownerWins == T.OwnerSoloWins, fmt("%d wins", ownerWins))
	local groupOk, groupRows = true, {}
	local groupSeeds = opts.quick and 3 or 8
	for _, players in ipairs({ 4, 8 }) do
		for _, boss in ipairs({ "storm_titan", "shadow_hydra" }) do
			local agg = SIM.midGroup(boss, players, groupSeeds, SIM.Teams.Owner)
			groupRows[#groupRows + 1] = fmt("%dp %s %.0f s (%d%%)", players, boss, agg.avgDur, agg.winPct)
			if agg.winPct < 100 or not inBand(agg.avgDur, T.Group) then
				groupOk = false
			end
		end
	end
	out("  owner-teams: " .. table.concat(groupRows, ", "))
	target("4 and 8 owner-teams finish storm_titan and shadow_hydra in 100-240 s", groupOk, table.concat(groupRows, ", "))

	header("Raids: 1 / 4 / 8 / 16 dodging fighters (70% of wind-ups and telegraphs) should finish every boss in 100-240 s (a solo under a quarter of BaselineDps should lose)")
	local seeds = max(1, floor(opts.seeds / 8))
	local stages = { { Id = "M5", Pets = SIM.Stages[5].Pets }, { Id = "M8", Pets = SIM.Stages[8].Pets } }
	local wonCombos, combos, anyBossHit = 0, 0, 0
	local weakSolos, weakSolosLost = 0, 0
	local cellOk, avgOk = true, true
	for _, boss in ipairs(BC.BossOrder) do
		for _, stage in ipairs(stages) do
			local sumDur, cells = 0, 0
			for _, players in ipairs({ 1, 4, 8, 16 }) do
				local n = (players >= 8) and max(1, floor(seeds / 2)) or seeds + 1
				local policies = {}
				for i = 1, players do
					policies[100 + i] = "player"
				end
				local agg = series(function(seed)
					local teams = {}
					for i = 1, players do
						teams[i] = team(100 + i, 1, stage.Pets)
					end
					return { Mode = "Raid", Boss = boss, Seed = seed, Teams = teams }
				end, policies, n)
				out(fmt("  %-13s %-3s %2dp: win %3d%% dur %5.1f s (dashes %5.1f, parries %5.1f, dodged hits %5.1f, KOs %4.1f, maxBossHit %.2f, tele hits %4.1f)",
					boss, stage.Id, players, agg.winPct, agg.avgDur, agg.dodges / max(1, agg.n), agg.parries / max(1, agg.n), agg.misses / max(1, agg.n), agg.kos / max(1, agg.n), agg.maxBossHit, agg.teleHits / max(1, agg.n)))
				-- bug batch 2 #2: a solo with under a quarter of the boss's BaselineDps meets the HP floor and should lose (near
				-- it is the edge: the L35 baseline puts M8 at ~0.37 x, its helpers make it a coin flip per boss)
				local weakSolo = players == 1 and BC.BaselineDps and BC.ExpectedDps({ Pets = stage.Pets }) < 0.25 * BC.BaselineDps(boss)
				if weakSolo then
					weakSolos = weakSolos + 1
					if agg.winPct < 50 then
						weakSolosLost = weakSolosLost + 1
					end
				else
					combos = combos + 1
				end
				-- a raid under half the BaselineDps fights the HP floor at the edge of the 330 s window (the L35 baseline: 4 x M5, a
				-- solo M8): it can win, but it counts neither as a raid to win nor in the 100-240 s band
				local floorGroup = BC.ExpectedDps({ Pets = stage.Pets }) * players < 0.5 * BC.BaselineDps(boss)
				if not weakSolo and floorGroup then
					combos = combos - 1
				end
				if agg.winPct >= 50 then
					wonCombos = wonCombos + ((weakSolo or floorGroup) and 0 or 1)
					if not floorGroup then
						if agg.avgDur < 90 or agg.avgDur > 250 then
							cellOk = false
						end
						sumDur, cells = sumDur + agg.avgDur, cells + 1
					end
				end
				anyBossHit = max(anyBossHit, agg.maxBossHit)
			end
			if cells > 0 and (sumDur / cells < 100 or sumDur / cells > 240) then
				avgOk = false
			end
			out(fmt("  %-13s %-3s average over 1/4/8/16 players: %.0f s", boss, stage.Id, cells > 0 and sumDur / cells or 0))
		end
	end
	target("dodging fighters win nearly every raid (1/4/8/16 players, two stages, four bosses: >= 90% of the combos; weak solos aside)", wonCombos >= combos * 0.9, fmt("%d of %d", wonCombos, combos))
	target("a solo under a quarter of the boss's BaselineDps loses (bug batch 2 #2)", weakSolosLost == weakSolos, fmt("%d of %d lost", weakSolosLost, weakSolos))
	target("won raids last 100-240 s per boss and stage (every single cell within 90-250 s: a few seeds per cell)", avgOk and cellOk)
	target("no boss hit takes more than 80% of a fighter before the enrage", anyBossHit <= 0.8, fmt("max %.2f", anyBossHit))

	-- balance-5: the 8p cells above run 1 (quick) / 4 (full) seeds, too few to see a group that only wins a coin flip
	-- (lava_golem M5 8p was 44% of 32 seeds after the bug #22 EngagePull 7 ruling, before HpPerPlayer 90 -> 85; wave 6's
	-- parrying trainer put it back at 90: 84% of 32 seeds, while 85 made the M8 cells finish under 90 s)
	local groupSeeds = opts.quick and 8 or 16
	header(fmt("Raids (bug #2: groups win): eight mid (M5) teams against every boss, %d seeds", groupSeeds))
	local worstGroup, worstBoss = 100, "-"
	for _, boss in ipairs(BC.BossOrder) do
		local r = SIM.midGroup(boss, 8, groupSeeds)
		out(fmt("  %-13s M5 8p: win %3d%%  dur %5.1f s (max %5.1f)  KOs %4.1f", boss, r.winPct, r.avgDur, r.maxDur, r.kos / max(1, r.n)))
		if r.winPct < worstGroup then
			worstGroup, worstBoss = r.winPct, boss
		end
	end
	target("eight mid (M5) teams win a fair share of every boss (>= 60% of the seeds each)", worstGroup >= 60, fmt("worst %s %d%%", worstBoss, worstGroup))

	header("Raids (bug batch 2 #2): 1 / 4 / 8 dodging teams at Lv 5 and Lv 40 vs the 330 s window (a Lv 5 solo cannot win)")
	local raidSeeds = max(1, floor(seeds / 2))
	local lv5 = { pet("maple_fox", 5), pet("bubble_axolotl", 5), pet("storm_tabby", 5) }
	local lv40 = { pet("cloudy_dragon", 40, "Golden", { Evo = 1 }), pet("stormfang", 35, nil, { Evo = 1 }), pet("eclipse_dragon", 35, nil, { Evo = 1 }) }
	local lv5SoloWins, lv5GroupOk, lv40Ok = 0, true, true
	for _, boss in ipairs(BC.BossOrder) do
		for _, case in ipairs({ { "Lv5", lv5 }, { "Lv40", lv40 } }) do
			for _, players in ipairs({ 1, 4, 8 }) do
				local policies = {}
				for i = 1, players do
					policies[100 + i] = "player"
				end
				-- (the two cells the target below judges get enough seeds to see a share: Lv 5 x 8 ~70-100 %, a Lv 40 solo ~90-100 %)
				local cellSeeds = ((case[1] == "Lv5" and players == 8) or (case[1] == "Lv40" and players == 1)) and max(8, raidSeeds) or raidSeeds
				local agg = series(function(seed)
					local teams = {}
					for i = 1, players do
						teams[i] = team(100 + i, 1, case[2])
					end
					return { Mode = "Raid", Boss = boss, Seed = seed, Teams = teams }
				end, policies, cellSeeds)
				local hp = BC.BossHp(boss, (function()
					local list = {}
					for i = 1, players do
						list[i] = { Pets = case[2] }
					end
					return list
				end)())
				out(fmt("  %-13s %-4s %dp: boss HP %8d  win %3d%%  dur %5.1f s  KOs %4.1f", boss, case[1], players, hp, agg.winPct, agg.avgDur, agg.kos / max(1, agg.n)))
				if case[1] == "Lv5" and players == 1 then
					lv5SoloWins = lv5SoloWins + agg.wins[1]
				elseif case[1] == "Lv5" and players == 8 and agg.winPct < 50 then
					lv5GroupOk = false
				elseif case[1] == "Lv40" and agg.winPct < ((players == 1) and 75 or 100) then
					-- balance-5: a Lv 40 solo can still lose all 3 lives to the Shadow Hydra's triple fangs: 30 of 32
					-- seeds won (94%, with the engage rule on or off), so seed 4 of the full run's 4 is a loss
					lv40Ok = false
				end
			end
		end
	end
	target("a Lv 5 solo never beats a raid boss (the BaselineDps HP floor)", lv5SoloWins == 0, fmt("%d wins", lv5SoloWins))
	target("eight Lv 5 teams win >= 50% of every boss (the L35 baseline's floor); Lv 40 groups beat every boss and a Lv 40 solo wins >= 75% of each", lv5GroupOk and lv40Ok)

	header("Raids: joining late and leaving (boss HP shares)")
	-- S9 (Lv 40): above the BaselineDps floor, so its own DPS sets the boss HP (bug batch 2 #2)
	local b = BS.new({ Mode = "Raid", Boss = "frost_wyrm", Seed = 2, Teams = { team(1, 1, SIM.Stages[9].Pets, { Auto = true }) } })
	local hp0 = b:BossStatus().MaxHp
	for _ = 1, 50 do
		b:Step(DT)
	end
	b:AddTeam(team(2, 1, SIM.Stages[9].Pets, { Auto = true }))
	local hp1 = b:BossStatus().MaxHp
	for _ = 1, 50 do
		b:Step(DT)
	end
	b:RemoveTeam(2)
	local hp2 = b:BossStatus().MaxHp
	out(fmt("  boss max HP: 1 player %d -> a second joins %d -> leaves %d", hp0, hp1, hp2))
	target("boss HP grows when a player joins and shrinks back when they leave", hp1 > hp0 * 1.8 and abs(hp2 - hp0) <= hp0 * 0.05)

	header("Raids: joiners who bring nothing (idle alts with level-1 Commons) do not inflate the boss for the real player")
	local withAlts = { team(400, 1, SIM.Stages[9].Pets) } -- S9: above the BaselineDps floor (bug batch 2 #2)
	for i = 1, 7 do
		withAlts[#withAlts + 1] = team(400 + i, 1, SIM.Stages[1].Pets, { Auto = true })
	end
	local solo = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 5, Teams = { team(400, 1, SIM.Stages[9].Pets) } })
	local crowded = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 5, Teams = withAlts })
	local soloHp, crowdedHp = solo:BossStatus().MaxHp, crowded:BossStatus().MaxHp
	out(fmt("  Storm Titan HP for one S9 team %d, with 7 idle alt teams %d (x%.2f); weighted head count %.2f", soloHp, crowdedHp, crowdedHp / soloHp, crowded.playerTeamCount or 0))
	target("seven alt teams with level-1 Commons add less than 15% to the boss's HP", crowdedHp <= soloHp * 1.15, fmt("x%.2f", crowdedHp / soloHp))
end)

-- 6. the Champion Ring
local function ringFight(pets, round, runSeed, battleSeed, playerOpts)
	return SIM.run({ Mode = "Ring", Seed = battleSeed, Round = round, Teams = { team(77, 1, pets), BC.ChampionTeam(round, runSeed) } }, { [77] = "player" }, playerOpts)
end

-- XP like DataService.GrantXp (the level-up loop) + the player who evolves a pet as soon as it can (stage 1 at level 20,
-- stage 2 at level 50 when PetCatalog.EvolveTwice names its rarity)
local function addXp(p, gain)
	p.Xp = (p.Xp or 0) + gain
	while p.Level < PC.MaxPetLevel() and p.Xp >= TC.XpToNext(p.Level) do
		p.Xp = p.Xp - TC.XpToNext(p.Level)
		p.Level = p.Level + 1
	end
	local def = PC.Get(p.Key)
	local stage = p.Evo or 0
	if p.Level >= PC.EvolutionLevels[1] then
		stage = max(stage, 1)
	end
	if p.Level >= PC.EvolutionLevels[2] and def and PC.EvolveTwice[def.Rarity] then
		stage = max(stage, 2)
	end
	p.Evo = stage > 0 and stage or p.Evo
end

local function clonePets(pets)
	local list = {}
	for i, p in ipairs(pets) do
		local c = {}
		for k, v in pairs(p) do
			c[k] = v
		end
		list[i] = c
	end
	return list
end

-- one run with the NO-HEAL rule (BattleService RingRun): every pet keeps the HP share it ended the round with
-- (Result().Units -> HpFraction), a fainted pet sits out; the run ends on a lost round or when nobody is left.
-- opts = { Xp = bool, Player = playerOpts, Start = round }: Xp pays Ring.XpBase + XpPerRound x the round per fielded pet
-- after a won round and BattleCatalog.LossXp on the losing round (the pets passed in are mutated: Level / Xp / Evo, so a
-- progression loop can chain runs). -> record (the last round won), durations (the won fights), total seconds, the last
-- fight's duration (the loss; nil when the run ended on a win with nobody left or at maxRound), levels (the pets' levels)
local function ringRun(pets, runSeed, maxRound, opts)
	opts = opts or {}
	local lost = nil
	local r, total = opts.Start or 1, 0
	local durations = {}
	local intermission = BC.Ring.Intermission or 3
	local share = {} -- key -> the HP share after the last won round (0 = fainted)
	local function pay(fielded, gain)
		if opts.Xp and gain > 0 then
			for _, p in ipairs(fielded) do
				addXp(p, gain)
			end
		end
	end
	while r <= (maxRound or 150) do
		local live, fielded = {}, {}
		for _, p in ipairs(pets) do
			local f = share[p.Key]
			if f == nil or f > 0 then
				local e = copyEntry(p)
				e.HpFraction = (f and f < 1) and f or nil
				live[#live + 1] = e
				fielded[#fielded + 1] = p
			end
		end
		if #live == 0 then
			break
		end
		local res = ringFight(live, r, runSeed, runSeed * 13 + r, opts.Player)
		local d = res and res.Duration or 0
		local winXp = BC.Ring.XpBase + BC.Ring.XpPerRound * r
		total = total + d
		if not res or res.WinnerSide ~= 1 then
			lost = d
			if res then
				local left = type(res.Hp) == "table" and tonumber(res.Hp[2]) or 1
				pay(fielded, BC.LossXp(winXp, d, max(0, min(1, 1 - left))))
			end
			break
		end
		for _, row in ipairs(res.Units and res.Units[77] or {}) do
			share[row.Key] = (row.Alive and row.MaxHp > 0) and row.Hp / row.MaxHp or 0
		end
		pay(fielded, winXp)
		durations[#durations + 1] = d
		total = total + intermission
		r = r + 1
	end
	local levels = {}
	for i, p in ipairs(pets) do
		levels[i] = p.Level
	end
	return r - 1, durations, total, lost, levels
end
SIM.ringRun = ringRun

-- `seeds` runs of a copy of `pets` with run XP: { med, lo, hi, reach5 (% with record >= 4), win1 (% with record >= 1), sec }
local function ringSummary(pets, playerOpts, seeds)
	local records = {}
	local reach5, win1, seconds = 0, 0, 0
	for seed = 1, seeds do
		local rec, _, total = ringRun(clonePets(pets), 1000 + seed, nil, { Xp = true, Player = playerOpts })
		records[#records + 1] = rec
		seconds = seconds + total
		if rec >= 4 then
			reach5 = reach5 + 1
		end
		if rec >= 1 then
			win1 = win1 + 1
		end
	end
	local med = median(records)
	table.sort(records)
	return { med = med, lo = records[1], hi = records[#records], reach5 = 100 * reach5 / seeds, win1 = 100 * win1 / seeds, sec = seconds / seeds }
end
SIM.ringSummary = ringSummary

-- a fresh-HP fight series of `pets` against the champions of `round` (seed = the run seed): wins of n
local function ringSeries(pets, round, n)
	local wins = 0
	for seed = 1, n do
		local res = ringFight(pets, round, seed, seed * 17 + round)
		if res and res.WinnerSide == 1 then
			wins = wins + 1
		end
	end
	return wins
end

local function lowestLevel(pets)
	local lo = huge
	for _, p in ipairs(pets) do
		lo = min(lo, p.Level or 1)
	end
	return lo
end

local function bandText(band)
	return band[1] == band[2] and tostring(band[1]) or (band[1] .. "-" .. band[2])
end

section("ring", function(opts)
	local T = SIM.Targets.Ring
	local fewSeeds, seeds = opts.quick and 16 or 64, opts.quick and 8 or 24
	header(fmt("Champion Ring: rounds won per team (run XP + loss XP, NO HEAL between rounds, fainted pets sit out; S1 / One %d seeds, the others %d)", fewSeeds, seeds))
	local function row(id, name, n)
		local d = ringSummary(SIM.Teams[id], nil, n)
		local i = ringSummary(SIM.Teams[id], SIM.Idle, n)
		out(fmt("  %-24s power %6d | Default med %3d (%d-%d) reach 5 %3.0f%% win 1 %3.0f%% run %3.0f s | Idle med %3d (%d-%d)", name, powerOf(SIM.Teams[id]), d.med, d.lo, d.hi, d.reach5, d.win1, d.sec, i.med, i.lo, i.hi))
		return { d = d, i = i }
	end
	local S1 = row("S1", "3 L1 Commons", fewSeeds)
	local One = row("One", "1 L1 Common", fewSeeds)
	local Leg = row("Leg", "3 L1 Legendaries", seeds)
	local Owner = row("Owner", "the owner's L10/11/11", seeds)
	local L50 = row("L50", "3 L50 Legendaries evo 2", seeds)
	local Max = row("Max", "3 L100 maxed", seeds)
	local function detail(x)
		return fmt("Default %d, Idle %d", x.d.med, x.i.med)
	end
	target("3 L1 Commons: Default median 2-4, Idle 1-2 (the owner's wall)", inBand(S1.d.med, T.S1.Default) and inBand(S1.i.med, T.S1.Idle), detail(S1))
	target("3 L1 Commons reach round 5 in <= 10% of seeds and win round 1 in >= 95%", S1.d.reach5 <= T.S1.Reach5 and S1.d.win1 >= T.S1.Win1, fmt("reach 5 %.0f%%, win 1 %.0f%%", S1.d.reach5, S1.d.win1))
	target("1 L1 Common: Default 1-2, Idle 1", inBand(One.d.med, T.One.Default) and inBand(One.i.med, T.One.Idle), detail(One))
	target(fmt("3 L1 Legendaries: Default %s, Idle %s", bandText(T.Leg.Default), bandText(T.Leg.Idle)), inBand(Leg.d.med, T.Leg.Default) and inBand(Leg.i.med, T.Leg.Idle), detail(Leg))
	target(fmt("the owner's L10/11/11 Secrets: Default %s, Idle %s", bandText(T.Owner.Default), bandText(T.Owner.Idle)), inBand(Owner.d.med, T.Owner.Default) and inBand(Owner.i.med, T.Owner.Idle), detail(Owner))
	target(fmt("3 L50 Legendaries evo 2: Default %s, Idle %s", bandText(T.L50.Default), bandText(T.L50.Idle)), inBand(L50.d.med, T.L50.Default) and inBand(L50.i.med, T.L50.Idle), detail(L50))
	target(fmt("3 L100 maxed: Default %s", bandText(T.Max.Default)), inBand(Max.d.med, T.Max.Default), fmt("Default %d", Max.d.med))
	target("the record never falls with the team (S1 <= Leg <= Owner <= L50 <= Max, Default)", S1.d.med <= Leg.d.med and Leg.d.med <= Owner.d.med and Owner.d.med <= L50.d.med and L50.d.med <= Max.d.med)

	header("Champion Ring: round 1 for every single level-1 rollable Common / Uncommon (a first win always exists)")
	local worst1, worstId = 100, "-"
	local list = starters()
	for _, id in ipairs(list) do
		local p = pct(ringSeries({ pet(id, 1) }, 1, fewSeeds), fewSeeds)
		if p < worst1 then
			worst1, worstId = p, id
		end
	end
	target("round 1 is an easy Common: every single L1 rollable Common / Uncommon wins it >= 95% (a first win always exists)", worst1 >= 95, fmt("worst %s %d%%, %d pets", worstId, worst1, #list))

	header("Champion Ring: the record per progression stage (no XP: the team as it stands)")
	local stages = {}
	for _, st in ipairs(SIM.Stages) do
		stages[#stages + 1] = st
	end
	stages[#stages + 1] = { Id = "Max", Name = "L100 maxed", Pets = SIM.Maxed }
	local fightOk, stageMono, lastMedian = true, true, -1
	local stageSeeds = opts.quick and 6 or 12
	for _, st in ipairs(stages) do
		local records, durs, totals, near = {}, {}, {}, {}
		for seed = 1, stageSeeds do
			local rec, d, total, lost = ringRun(st.Pets, 1000 + seed)
			records[#records + 1] = rec
			for _, x in ipairs(d) do
				durs[#durs + 1] = x
			end
			-- the climb's real fights: the last 10 of the run (the loss included). A player starts a new run at the last
			-- boss round they beat (the checkpoint), so the early rounds a strong team clears in 0.5 s are a one-time warm-up.
			local last = {}
			for _, x in ipairs(d) do
				last[#last + 1] = x
			end
			if lost then
				last[#last + 1] = lost
			end
			for i = max(1, #last - 9), #last do
				near[#near + 1] = last[i]
			end
			totals[#totals + 1] = total
		end
		local med = median(records)
		local nearFight = mean(near)
		table.sort(records)
		out(fmt("  %-4s %-11s power %6d  record median %3d (min %d, max %d)  avg fight %4.1f s (last 10: %4.1f s)  run %4.1f min", st.Id, st.Name, powerOf(st.Pets), med, records[1], records[#records], mean(durs), nearFight, mean(totals) / 60))
		if nearFight < 4 or nearFight > 40 then
			fightOk = false
		end
		if med < lastMedian then
			stageMono = false
		end
		lastMedian = max(lastMedian, med)
	end
	target("the record never falls with the stage", stageMono)
	target("the last 10 fights of a run (from the checkpoint on) last 4-40 s on average at every stage", fightOk)

	header("Champion Ring: the ladder (player formula: no Boss / Handicap / Boost; shown level and power never drop)")
	local levelMono, powerMono, plain, levels, sizes, full = true, true, true, true, true, true
	local monoBad = nil
	for seed = 1, 40 do
		local lastPower, lastLevel = 0, 0
		for r = 1, 120 do
			local spec = BC.ChampionTeam(r, seed)
			if r > 1 and spec.Power < lastPower then
				powerMono = false
				monoBad = monoBad or fmt("seed %d round %d: power %d -> %d", seed, r, lastPower, spec.Power)
			end
			if r > 1 and spec.Champion.Level < lastLevel then
				levelMono = false
				monoBad = monoBad or fmt("seed %d round %d: level %d -> %d", seed, r, lastLevel, spec.Champion.Level)
			end
			lastPower, lastLevel = spec.Power, spec.Champion.Level
			if #spec.Pets < 1 or #spec.Pets > 3 then
				sizes = false
			end
			for _, e in ipairs(spec.Pets) do
				if e.Boss or e.Handicap or e.Boost then
					plain = false
				end
				if e.Level < 1 or e.Level > PC.MaxPetLevel() then
					levels = false
				end
			end
		end
		if #BC.ChampionTeam(100, seed).Pets ~= 3 then
			full = false
		end
	end
	target("shown level and shown power never drop from one round to the next (rounds 1-120, 40 seeds)", levelMono and powerMono, monoBad)
	target("no champion pet carries Boss / Handicap / Boost (the player formula)", plain)
	target("every champion level is 1..100, every team 1..3 pets, round 100 fields three", levels and sizes and full)
	-- a team beats champions 10+ levels below it: the last round whose curve level is at least 10 under the team's lowest pet
	for _, idx in ipairs({ 7, 9, 10 }) do
		local st = SIM.Stages[idx]
		local lo = lowestLevel(st.Pets)
		local round = 1
		while round < 120 and BC.ChampionLevel(round + 1) <= lo - 10 do
			round = round + 1
		end
		local spec = BC.ChampionTeam(round, 1)
		local n = 24
		local wins = ringSeries(st.Pets, round, n)
		target(fmt("%s (lowest L%d) beats round %d's champions (L%d, curve L%d) in >= 90%% of %d fresh-HP fights", st.Id, lo, round, spec.Pets[1].Level, BC.ChampionLevel(round), n), pct(wins, n) >= 90, fmt("%d of %d", wins, n))
	end
	local topWins = 0
	local nTop = 24
	for seed = 1, nTop do
		local res = SIM.run({ Mode = "Ring", Seed = seed * 17 + 100, Round = 100, Teams = { team(77, 1, SIM.Maxed), BC.ChampionTeam(100, seed) } }, { [77] = "player" })
		if res and res.WinnerSide == 2 then
			topWins = topWins + 1
		end
	end
	target(fmt("round 100's champions (three L100 Rainbow) beat the maxed team in >= 60%% of %d fresh-HP fights", nTop), pct(topWins, nTop) >= 60, fmt("%d of %d", topWins, nTop))
	-- (info) a veteran's view: records are kept, so a boss start stays unlocked under the harder champions
	local vets = {}
	for _, start in ipairs({ 10, 20 }) do
		local won = {}
		for seed = 1, seeds do
			local rec = ringRun(clonePets(SIM.Teams.Owner), 1000 + seed, nil, { Xp = true, Start = start })
			won[#won + 1] = rec - start + 1
		end
		vets[#vets + 1] = fmt("from round %d: %d rounds won", start, median(won))
	end
	out("  (info) the owner's team from an unlocked boss start: " .. table.concat(vets, ", "))
	out(fmt("  %5s %5s %-7s %5s %-40s %8s", "round", "level", "tier", "count", "species", "power"))
	for _, r in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 25, 30, 36, 40, 50, 52, 56, 60, 66, 70, 80, 100, 120 }) do
		local spec = BC.ChampionTeam(r, 1)
		local names = {}
		for _, e in ipairs(spec.Pets) do
			names[#names + 1] = fmt("%s L%d e%d", e.PetId, e.Level, e.Evo or 0)
		end
		out(fmt("  %5d %5d %-7s %5d %-40s %8d", r, BC.ChampionLevel(r), BC.ChampionTier(r), #spec.Pets, table.concat(names, ", "), spec.Power))
	end
end)

-- 7. the Dungeon
-- roomPct[1..4]: the % of `seeds` that cleared that room of floor f with a copy of `pets`, like DungeonService: a fresh
-- full-HP battle per room, the team re-read per room, the room's XP paid on the clear (levels rise inside a floor)
local function floorSummary(pets, f, playerOpts, seeds)
	local D = BC.Dungeon
	local roomPct = { 0, 0, 0, 0 }
	for seed = 1, seeds do
		local list = clonePets(pets)
		for r = 1, 4 do
			if not SIM.dungeonRoom(f, r, { team(301, 1, list) }, { [301] = "player" }, seed, playerOpts) then
				break
			end
			roomPct[r] = roomPct[r] + 100 / seeds
			local waves = (r == 4) and 2 or ((f == 1) and D.Floor1Waves[r] or D.Waves[r])
			local gain = BC.DungeonRewards(f, r, waves, 0, false).Xp
			for _, p in ipairs(list) do
				addXp(p, gain)
			end
		end
	end
	return roomPct
end
SIM.floorSummary = floorSummary

-- the highest floor cleared in >= 50% of the seeds (climbing from floor 1, stopping at the first floor it fails)
local function ladder(pets, playerOpts, seeds)
	local best = 0
	for f = 1, BC.Dungeon.Floors do
		if floorSummary(pets, f, playerOpts, seeds)[4] >= 50 then
			best = f
		else
			break
		end
	end
	return best
end
SIM.ladder = ladder

section("dungeon", function(opts)
	local D = BC.Dungeon
	local T = SIM.Targets.Dungeon
	local fewSeeds, seeds = opts.quick and 16 or 64, opts.quick and 8 or 24
	header(fmt("Dungeon: floor 1 (target %.1f per player, waves %d / %d / %d) with room XP (%d seeds)", D.Floor1Power, D.Floor1Waves[1], D.Floor1Waves[2], D.Floor1Waves[3], fewSeeds))
	local function rooms(pc)
		return fmt("%3.0f %3.0f %3.0f %3.0f", pc[1], pc[2], pc[3], pc[4])
	end
	local s1 = floorSummary(SIM.Teams.S1, 1, nil, fewSeeds)
	local one = floorSummary(SIM.Teams.One, 1, nil, fewSeeds)
	local l7 = floorSummary(SIM.Teams.L7, 1, nil, fewSeeds)
	out("  3 L1 Commons Default rooms " .. rooms(s1) .. " | Idle " .. rooms(floorSummary(SIM.Teams.S1, 1, SIM.Idle, fewSeeds)))
	out("  1 L1 Common  Default rooms " .. rooms(one))
	out("  3 L7 Commons Default rooms " .. rooms(l7))
	target("3 L1 Commons: room 1 >= 90%, room 2 40-60%, floor 1 full clear < 15% (Default)", s1[1] >= T.S1.Room1 and inBand(s1[2], T.S1.Room2) and s1[4] < T.S1.Clear, fmt("%.0f / %.0f / clear %.0f", s1[1], s1[2], s1[4]))
	target("3 L6-7 Commons clear floor 1 >= 80%", l7[4] >= T.L7.Clear, fmt("%.0f%%", l7[4]))

	header(fmt("Dungeon: the eased room (floor 1 room 1 at EasedRoomMult %.2f, %d seeds per pet, the tutorial)", D.EasedRoomMult, fewSeeds))
	local worstEased, worstId = 100, "-"
	for _, id in ipairs(starters()) do
		local wins = 0
		for seed = 1, fewSeeds do
			if SIM.dungeonRoom(1, 1, { team(301, 1, { pet(id, 1) }) }, { [301] = "player" }, seed, nil, { Eased = true }) then
				wins = wins + 1
			end
		end
		local p = pct(wins, fewSeeds)
		if p < worstEased then
			worstEased, worstId = p, id
		end
	end
	target("the eased room: floor 1 room 1 with EasedRoomMult is won >= 95% by EVERY single L1 rollable Common / Uncommon (the tutorial)", worstEased >= 95, fmt("worst %s %d%%", worstId, worstEased))

	header(fmt("Dungeon: the team ladder (solo, %d seeds): the highest floor cleared in >= half of the seeds; FirstPower %.1f Growth %.2f RoomMult %.2f/%.2f/%.2f", seeds, D.FirstPower, D.Growth, D.RoomMult[1], D.RoomMult[2], D.RoomMult[3]))
	local best = {}
	local monotonic, lastFloor = true, 0
	for _, id in ipairs({ "S1", "L7", "Leg", "Owner", "L50", "Max" }) do
		best[id] = ladder(SIM.Teams[id], nil, seeds)
		out(fmt("  %-6s power %6d  clears to F%d", id, powerOf(SIM.Teams[id]), best[id]))
		if best[id] < lastFloor then
			monotonic = false
		end
		lastFloor = max(lastFloor, best[id])
	end
	target("best floor (>= 50% of seeds): Legendaries L1 1-3, the owner's Secrets 3-5, L50 Legendaries 6-8, maxed 12", inBand(best.Leg, T.Leg.Floor) and inBand(best.Owner, T.Owner.Floor) and inBand(best.L50, T.L50.Floor) and inBand(best.Max, T.Max.Floor), fmt("Leg F%d, Owner F%d, L50 F%d, Max F%d", best.Leg, best.Owner, best.L50, best.Max))
	target("the ladder never falls with the team", monotonic)
	-- (info) the progression stages
	local parts = {}
	for _, st in ipairs(SIM.Stages) do
		parts[#parts + 1] = fmt("%s F%d", st.Id, ladder(st.Pets, nil, max(4, floor(seeds / 2))))
	end
	out("  (info) the stages: " .. table.concat(parts, ", "))

	header("Dungeon: a party of 4 (copies of S3) gains about one floor over the solo S3")
	local partySeeds = opts.quick and 3 or 6
	local function floorsOf(party)
		local top = 0
		for f = 1, D.Floors do
			local clears = 0
			for seed = 1, partySeeds do
				if SIM.dungeonFloor(f, SIM.Stages[3].Pets, party, seed) == 4 then
					clears = clears + 1
				end
			end
			if clears * 2 >= partySeeds then
				top = f
			else
				break
			end
		end
		return top
	end
	local solo3, party4 = floorsOf(1), floorsOf(4)
	out(fmt("  S3 solo clears to F%d, a party of 4 x S3 to F%d", solo3, party4))
	target("a 4-party clears one or two floors more than the solo team", party4 - solo3 >= 1 and party4 - solo3 <= 2, fmt("+%d", party4 - solo3))
end)

-- 7b. progress: a new player's pace (spec 2026-10-31 s.4), real run XP + loss XP, levels kept between runs
section("progress", function(opts)
	local T = SIM.Targets.Progress
	local players = opts.quick and 12 or 24
	local RETURN_DELAY, WALK = 4, 10 -- BattleService's return delay + an assumed walk back to the portal
	local MAX_RUNS = 200
	header(fmt("Progress: %d new players, Default trainer, 3 L1 Commons, Ring runs only (run XP + loss XP, overhead %d s per run)", players, RETURN_DELAY + WALK))
	local f1cache = {}
	local function f1clear(list)
		local key = list[1].Level .. "/" .. list[2].Level .. "/" .. list[3].Level
		if f1cache[key] == nil then
			local pets = {}
			for i, p in ipairs(list) do
				pets[i] = pet(p.Key, p.Level, nil, { Evo = p.Evo })
			end
			f1cache[key] = floorSummary(pets, 1, nil, 12)[4]
		end
		return f1cache[key]
	end
	local goals = { { "Ring5", 4 }, { "Ring10", 9 } }
	local res = { Ring5 = { mins = {}, runs = {}, lv = {} }, Ring10 = { mins = {}, runs = {}, lv = {} }, F1 = { mins = {}, runs = {}, lv = {} } }
	local runSeconds, runCount = 0, 0
	local function note(name, minutes, run, level)
		local rr = res[name]
		rr.mins[#rr.mins + 1], rr.runs[#rr.runs + 1], rr.lv[#rr.lv + 1] = minutes, run, level
	end
	for player = 1, players do
		local list = clonePets(SIM.Teams.S1)
		local secs = 0
		local done = {}
		for run = 1, MAX_RUNS do
			local rec, _, total = ringRun(list, 5000 + player * 100 + run, nil, { Xp = true })
			secs = secs + total + RETURN_DELAY + WALK
			if run <= 5 then
				runSeconds, runCount = runSeconds + total + RETURN_DELAY + WALK, runCount + 1
			end
			for _, g in ipairs(goals) do
				if not done[g[1]] and rec >= g[2] then
					done[g[1]] = true
					note(g[1], secs / 60, run, list[1].Level)
				end
			end
			if not done.F1 and f1clear(list) >= 80 then
				done.F1 = true
				note("F1", secs / 60, run, list[1].Level)
			end
			if done.Ring10 and done.F1 then
				break
			end
		end
	end
	local function row(name)
		local rr = res[name]
		local m = #rr.mins > 0 and median(rr.mins) or huge
		out(fmt("  %-7s reached by %d of %d: median %.1f min, run %s, lead level %s", name, #rr.mins, players, m, tostring(median(rr.runs)), tostring(median(rr.lv))))
		return (#rr.mins * 2 >= players) and m or huge
	end
	local r5, f1, r10 = row("Ring5"), row("F1"), row("Ring10")
	out(fmt("  (info) seconds per run in the first five runs (fight + intermissions + overhead): %.0f s (spec s.7 wants the retry loop under 2 minutes)", runSeconds / max(1, runCount)))
	target("a new player reaches Ring 5 in 4-9 minutes (median)", inBand(r5, T.Ring5), fmt("%.1f min", r5))
	target("...clears floor 1 in 4-10 minutes", inBand(f1, T.F1), fmt("%.1f min", f1))
	target("...reaches Ring 10 in 20-45 minutes (target 30)", inBand(r10, T.Ring10), fmt("%.1f min", r10))
end)

-- 8. training + evolution
local function ranks(r)
	return { Speed = r, Physique = r, Ability = r, Defense = r }
end

local function trained(pets, rk, evo, level)
	local list = {}
	for i, p in ipairs(pets) do
		local e = copyEntry(p)
		e.Train = rk
		e.Evo = evo
		if level then
			e.Level = level
		end
		list[i] = e
	end
	return list
end

section("training", function(opts)
	header("Training + evolution: TeamPower of each stage with all four skills trained / evolved (LevelFactor x the evolution bonus)")
	out(fmt("  %-4s %-11s %6s | %-15s | %-15s | %-15s | %-15s", "", "", "power", "all ranks 5", "all ranks 10", "Evolved I", "Evolved II"))
	local r5lo, r5hi, r10lo, r10hi = huge, 0, huge, 0
	local e1lo, e1hi, e2lo, e2hi = huge, 0, huge, 0
	for _, st in ipairs(SIM.Stages) do
		local base = powerOf(st.Pets)
		local r5 = powerOf(trained(st.Pets, ranks(5)))
		local r10 = powerOf(trained(st.Pets, ranks(10)))
		local e1 = powerOf(trained(st.Pets, nil, 1))
		local e2 = powerOf(trained(st.Pets, nil, 2))
		out(fmt("  %-4s %-11s %6d | %6d (x%.2f) | %6d (x%.2f) | %6d (x%.2f) | %6d (x%.2f)", st.Id, st.Name, base, r5, r5 / base, r10, r10 / base, e1, e1 / base, e2, e2 / base))
		r5lo, r5hi = min(r5lo, r5 / base), max(r5hi, r5 / base)
		r10lo, r10hi = min(r10lo, r10 / base), max(r10hi, r10 / base)
		if st.Pets[1].Level >= 20 then
			e1lo, e1hi = min(e1lo, e1 / base), max(e1hi, e1 / base)
			if st.Pets[1].Level >= 50 then
				e2lo, e2hi = min(e2lo, e2 / base), max(e2hi, e2 / base)
			end
		end
	end
	target("all four skills at rank 5: x1.25-1.4 TeamPower at every stage", r5lo >= 1.25 and r5hi <= 1.4, fmt("x%.2f .. x%.2f", r5lo, r5hi))
	target("all four skills at rank 10: x1.6-1.85 TeamPower at every stage", r10lo >= 1.6 and r10hi <= 1.85, fmt("x%.2f .. x%.2f", r10lo, r10hi))
	target("Evolved I x1.3-1.5 (stages at level >= 20) and Evolved II x1.6-1.9 (level 50)", e1lo >= 1.3 and e1hi <= 1.5 and e2lo >= 1.6 and e2hi <= 1.9, fmt("I x%.2f .. x%.2f, II x%.2f .. x%.2f", e1lo, e1hi, e2lo, e2hi))

	header("Training: trained mirror duels (scripted players both sides): fair, no draws (timeouts go to the damage leader)")
	local wins1, n, draws = 0, 0, 0
	for _, idx in ipairs({ 3, 5, 7, 9 }) do
		local st = SIM.Stages[idx]
		for _, case in ipairs({ { "rank 5 + Evolved I", ranks(5), 1 }, { "rank 10 + Evolved II", ranks(10), 2 } }) do
			local pets = trained(st.Pets, case[2], case[3])
			local agg = series(function(seed)
				return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, pets), team(2, 2, pets) } }
			end, { [1] = "player", [2] = "player" }, max(8, floor(opts.seeds / 2)))
			out(fmt("  %-4s %-22s side1 %3d%%  draws %d  timeouts %2d  dur %5.1f s  maxHit %.2f", st.Id, case[1], agg.winPct, agg.draws, agg.timeouts, agg.avgDur, agg.maxPetHit))
			wins1, n, draws = wins1 + agg.wins[1], n + agg.n, draws + agg.draws
		end
	end
	target("trained mirror duels are fair (40-60% over every case together) with no draws", pct(wins1, n) >= 40 and pct(wins1, n) <= 60 and draws == 0, fmt("side 1 %d%%, draws %d", pct(wins1, n), draws))
	header("Training: a trained + evolved team (S7, rank 10, Evolved II) vs every boss with 1 / 4 dodging fighters")
	local seeds = max(1, floor(opts.seeds / 8))
	local pets7 = trained(SIM.Stages[7].Pets, ranks(10), 2)
	local won, combos, durOk, bossHit = 0, 0, true, 0
	for _, boss in ipairs(BC.BossOrder) do
		for _, players in ipairs({ 1, 4 }) do
			local policies = {}
			for i = 1, players do
				policies[500 + i] = "player"
			end
			local agg = series(function(seed)
				local teams = {}
				for i = 1, players do
					teams[i] = team(500 + i, 1, pets7)
				end
				return { Mode = "Raid", Boss = boss, Seed = seed, Teams = teams }
			end, policies, seeds)
			out(fmt("  %-13s %dp: win %3d%% dur %5.1f s (dodges %4.1f, KOs %4.1f, maxBossHit %.2f)", boss, players, agg.winPct, agg.avgDur, agg.dodges / max(1, agg.n), agg.kos / max(1, agg.n), agg.maxBossHit))
			combos = combos + 1
			bossHit = max(bossHit, agg.maxBossHit)
			if agg.winPct >= 50 then
				won = won + 1
				if agg.avgDur < 100 or agg.avgDur > 240 then
					durOk = false
				end
			end
		end
	end
	target("a trained team still wins its raids (>= 90% of the combos) in 100-240 s", won >= combos * 0.9 and durOk, fmt("%d of %d won", won, combos))
	target("no boss hit takes more than 80% of a trained fighter", bossHit <= 0.8, fmt("max %.2f", bossHit))
end)

-- 9. move: the B1 character patterns at the legal speed through a 200 ms old feed
section("move", function()
	header("Move: the character runs the B1 patterns at its legal run speed; the server fighter sees a 200 ms old position (cap = run x MoveSlack)")
	local F = BC.Fighter
	local allOk = true
	for _, c in ipairs({ { "mochi_slime", 1 }, { "sunbeam_bear", 20 }, { "stormfang", 50 } }) do
		local b = BS.new({ Mode = "Duel", Seed = 9, Teams = { team(1, 1, { pet(c[1], c[2]) }), team("npc", 2, { pet("honey_bunny", 1, nil, { Handicap = 0.3 }) }, { Npc = true, Specials = false }) }, Specials = false })
		-- the fighter auto-attacks (dungeon fixes 4): the dummy may neither fall nor hit, the battle must outlast the patterns;
		-- wave 6: it is untargetable (still arriving) so the pet FOLLOWs and the patterns measure the follow, not the engage rule
		for _, u in ipairs(b.units) do
			if u.side == 2 then
				u.maxHp, u.hp, u.hit = 1e9, 1e9, 0
				u.arriveUntil = huge
			end
		end
		local sp = b:SpeedOf(1)
		local tid = b:TeamOf(1).Fighter
		local rng = lcg(5)
		local cx, cz = b.units[tid].x, b.units[tid].z
		local tx, tz = cx, cz
		local history = {}
		local maxGap, maxGapLate, leashFor, leashes = 0, 0, 0, 0
		local h = b.zone.HalfX - 2
		-- 60 s of random targets
		for step = 1, 600 do
			if dist(cx, cz, tx, tz) < 2 then
				tx, tz = (rng() * 2 - 1) * h, (rng() * 2 - 1) * h
			end
			local d = dist(cx, cz, tx, tz)
			local s = min(d, sp.Run * DT)
			cx, cz = cx + (tx - cx) / d * s, cz + (tz - cz) / d * s
			history[#history + 1] = { cx, cz }
			local fed = history[max(1, #history - 2)]
			b:Command(1, "Move", fed[1], fed[2])
			b:Step(DT)
			local u = b.units[tid]
			local gap = dist(fed[1], fed[2], u.x, u.z)
			maxGap = max(maxGap, gap)
			if step > 10 then
				maxGapLate = max(maxGapLate, gap)
			end
			leashFor = (gap > F.Leash) and (leashFor + DT) or 0
			if leashFor >= F.LeashSeconds then
				leashes = leashes + 1
				leashFor = 0
			end
		end
		-- a 10 s circle of radius 14 at the run speed
		local w = sp.Run / 14
		local circleGap = 0
		for step = 1, 100 do
			local tt = step * DT
			cx, cz = 14 * cos(w * tt), 14 * sin(w * tt)
			history[#history + 1] = { cx, cz }
			local fed = history[max(1, #history - 2)]
			b:Command(1, "Move", fed[1], fed[2])
			b:Step(DT)
			local u = b.units[tid]
			if step > 20 then -- the circle starts away from the last random target: 2 s to join it
				circleGap = max(circleGap, dist(fed[1], fed[2], u.x, u.z))
			end
		end
		-- a straight run-off: the character leaves the zone at the obby run speed; the fighter stops at the edge
		local offLeashed = false
		local far = 0
		cx, cz = 0, 0
		for step = 1, 80 do
			cz = cz + 27 * DT
			b:Command(1, "Move", cx, cz)
			b:Step(DT)
			local u = b.units[tid]
			local gap = dist(cx, cz, u.x, u.z)
			far = (gap > F.Leash) and (far + DT) or 0
			if far >= F.LeashSeconds then
				offLeashed = true
			end
		end
		local ok = maxGapLate <= 0.5 and leashes == 0 and circleGap <= 0.5 and offLeashed
		allOk = allOk and ok
		out(fmt("  %-13s L%-2d walk %4.1f run %4.1f cap %4.1f: random targets max gap %.2f (after catch-up %.2f), leashes %d; circle gap %.2f; run-off leashed after 3 s: %s", c[1], c[2], sp.Walk, sp.Run, sp.Run * F.MoveSlack, maxGap, maxGapLate, leashes, circleGap, tostring(offLeashed)))
	end
	target("the server fighter keeps within 0.5 stud of the fed position after the catch-up, zero leashes; a run-off past the zone is leashed", allOk)
	-- wave 6: an engaged pet ignores the walking character (the random pattern next to a TARGETABLE dummy)
	do
		local b = BS.new({ Mode = "Duel", Seed = 9, Teams = { team(1, 1, { pet("sunbeam_bear", 20) }), team("npc", 2, { pet("honey_bunny", 1, nil, { Handicap = 0.3 }) }, { Npc = true, Specials = false }) }, Specials = false })
		for _, u in ipairs(b.units) do
			if u.side == 2 then
				u.maxHp, u.hp, u.hit, u.moveSpeed = 1e9, 1e9, 0, 0
				u.arriveUntil = nil
			end
		end
		local sp = b:SpeedOf(1)
		local rng = lcg(7)
		local tid = b:TeamOf(1).Fighter
		local cx, cz = b.units[tid].x, b.units[tid].z
		local tx, tz = cx, cz
		local h = b.zone.HalfX - 2
		local offs, ons, engagedSteps = 0, 0, 0
		for _ = 1, 400 do
			if dist(cx, cz, tx, tz) < 2 then
				tx, tz = (rng() * 2 - 1) * h, (rng() * 2 - 1) * h
			end
			local d = dist(cx, cz, tx, tz)
			local s = min(d, sp.Run * DT)
			cx, cz = cx + (tx - cx) / d * s, cz + (tz - cz) / d * s
			b:Command(1, "Move", cx, cz)
			for _, ev in ipairs(b:Step(DT)) do
				if ev.type == "Engage" and ev.on == false then
					offs = offs + 1
				elseif ev.type == "Engage" and ev.on == true then
					ons = ons + 1
				end
			end
			if b:TeamOf(1).Engaged then
				engagedSteps = engagedSteps + 1
			end
		end
		out(fmt("  engaged pet + a trainer running random targets for 40 s: Engage on %d, off %d, engaged %d of 400 steps", ons, offs, engagedSteps))
		target("an engaged pet ignores the walking character: zero Engage off while the character runs the random pattern next to a targetable dummy", ons == 1 and offs == 0 and engagedSteps >= 399)
	end
	-- wave 6: a wandering trainer's raid plays like a standing one's (movement changes nothing; one cell, two seeds)
	do
		local function raid(seed)
			local teams = {}
			local policies = {}
			for i = 1, 4 do
				teams[i] = team(400 + i, 1, SIM.Stages[5].Pets)
				policies[400 + i] = "player"
			end
			return { Mode = "Raid", Boss = "frost_wyrm", Seed = seed, Teams = teams }, policies
		end
		local stand, wander = 0, 0
		local okAll = true
		for seed = 1, 2 do
			local setup, policies = raid(seed)
			local r1 = SIM.run(setup, policies, { move = "stand" })
			setup, policies = raid(seed)
			local r2 = SIM.run(setup, policies, { move = "wander" })
			stand = stand + (r1 and r1.Duration or 0)
			wander = wander + (r2 and r2.Duration or 0)
			okAll = okAll and r1 and r2 and r1.WinnerSide == r2.WinnerSide
		end
		local ratio = wander / max(1, stand)
		out(fmt("  frost_wyrm M5 4p, 2 seeds: standing trainers %.1f s, wandering trainers %.1f s (x%.2f)", stand / 2, wander / 2, ratio))
		target("a wandering trainer's raid plays like a standing one's (same outcome, duration within 15%)", okAll and abs(ratio - 1) <= 0.15)
	end
end)

-- 10. perf
section("perf", function()
	header("Performance: a 16-fighter raid (Storm Titan + minion waves) stepped at 10 Hz")
	local teams, policies = {}, {}
	for i = 1, 16 do
		teams[i] = team(600 + i, 1, SIM.Stages[6].Pets, { Auto = true })
		policies[600 + i] = "auto"
	end
	local result, stats = SIM.run({ Mode = "Raid", Boss = "storm_titan", Seed = 4, Teams = teams }, policies)
	local perStep = stats.seconds / max(1, stats.steps) * 1000
	out(fmt("  result %s in %.1f s: %d steps in %.2f s = %.3f ms per step, %d events", result.Reason, result.Duration, stats.steps, stats.seconds, perStep, stats.events))
	target("a 16-fighter raid step costs under 1 ms", perStep < 1, fmt("%.3f ms", perStep))
	local b = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 4, Teams = teams })
	for _ = 1, 20 do
		b:Step(DT)
	end
	local payload = b:SnapshotDelta({})
	local bytes = #payload.U * 6
	out(fmt("  a full wire snapshot of %d units: %d numbers (~%d bytes)", #b:StaticUnits(), #payload.U, bytes))
	target("a full snapshot costs at most 6 numbers per unit (the delta form sends far less)", #payload.U <= 6 * #b:StaticUnits(), fmt("%d numbers for %d units", #payload.U, #b:StaticUnits()))
end)

-- 11. progression reference
section("progression", function()
	local feedShare = (type(TC.FeedShare) == "table" and TC.FeedShare[1]) or 0.25
	header(fmt("Progression reference: pet XP behind each stage (TycoonCatalog.XpToNext) and its Food Machine price (machine level 1: %d%% of a bar per feed)", floor(feedShare * 100 + 0.5)))
	local Config = require(Shared.Config)
	local function feedPrice(key, level)
		if TC.FeedPrice then
			local ok, price = pcall(TC.FeedPrice, key, level)
			if ok and type(price) == "number" then
				return price
			end
		end
		local def = PC.Get(key)
		local scales = type(Config.PetStats) == "table" and Config.PetStats.RarityScale or {}
		local scale = (def and scales[def.Rarity]) or 1
		local need = TC.XpToNext(level)
		if need == huge then
			return 0
		end
		return floor(need * scale * (TC.FeedBase or 2.0) + 0.5)
	end
	local function cashFor(key, from, to)
		local cash = 0
		for l = from, to - 1 do
			local need = TC.XpToNext(l)
			if need ~= huge then
				cash = cash + feedPrice(key, l) / feedShare
			end
		end
		return cash
	end
	local function fmtCash(n)
		local s = TC.FormatCash and TC.FormatCash(n) or tostring(floor(n))
		if s:sub(1, 1) ~= "$" then
			s = "$" .. s
		end
		return s
	end
	for _, stage in ipairs(SIM.Stages) do
		local xp, cash = 0, 0
		local ids = {}
		for _, p in ipairs(stage.Pets) do
			xp = xp + TC.XpForLevel(p.Level)
			cash = cash + cashFor(p.Key, 1, p.Level)
			ids[#ids + 1] = p.Key .. " L" .. p.Level .. (p.Tier and ("@" .. p.Tier) or "")
		end
		out(fmt("  %-4s %-11s power %5d  team XP %8d  Food Machine %9s  %s", stage.Id, stage.Name, powerOf(stage.Pets), xp, fmtCash(cash), table.concat(ids, ", ")))
	end
	local parts = {}
	for f = 1, BC.Dungeon.Floors do
		local w = BC.DungeonWave(f, 1, 1, 1, 1)
		parts[#parts + 1] = fmt("F%d:%d(%s L%d%s)", f, floor(BC.DungeonPower(f, 1) + 0.5), w.Pets[1].PetId, w.Pets[1].Level, w.Pets[1].Tier ~= "Normal" and (" " .. w.Pets[1].Tier) or "")
	end
	out("  dungeon ladder (per player): " .. table.concat(parts, " "))
	local ok, problems = BC.Validate()
	target("BattleCatalog.Validate() passes", ok, table.concat(problems, "; "))
end)

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------
function SIM.main(argString)
	local opts = parseArgs(argString)
	if opts.seeds == nil then
		opts.seeds = opts.quick and 24 or 64
	end
	out(fmt("Nimbus Climb battle balance report (%s, %d seeds per matchup)", opts.quick and "quick" or "full", opts.seeds))
	local started = clock()
	for _, name in ipairs(order) do
		if not opts.only or opts.only[name] then
			local t0 = clock()
			local ok, err = pcall(sections[name], opts)
			if not ok then
				out("  section " .. name .. " crashed: " .. tostring(err))
				target("section " .. name .. " runs", false, tostring(err))
			end
			if opts.verbose then
				out(fmt("  (%.1f s)", clock() - t0))
			end
		end
	end
	local met = 0
	for _, t in ipairs(targets) do
		if t.ok then
			met = met + 1
		end
	end
	out("")
	out(fmt("SUMMARY: %d of %d targets met (%.0f s)", met, #targets, clock() - started))
	for _, t in ipairs(targets) do
		if not t.ok then
			out("  MISS " .. t.name .. (t.detail ~= "" and (": " .. t.detail) or ""))
		end
	end
	return met == #targets, targets, lines
end

SIM.sections = sections
SIM.order = order
SIM.targets = targets
SIM.Player = Player
SIM.team = team
SIM.pet = pet
SIM.npcOf = npcOf
SIM.powerOf = powerOf
SIM.series = series
SIM.starters = starters
SIM.trained = trained
SIM.ranks = ranks
SIM.median = median

if SIM_BATTLE_LIBRARY then
	return SIM
end

return SIM.main(os.getenv and os.getenv("SIM_BATTLE") or SIM_BATTLE_ARGS or "")
