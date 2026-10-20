-- sim_battle.lua: the battle balance harness (ARCHITECTURE_V3.md "Phase 5 build contract" 12.3, battlecore).
-- Runs the REAL shared modules (BattleCatalog + BattleSim on top of PetCatalog / PetKeys / TycoonCatalog / Config)
-- inside the Roblox mock under lupa, like tools/smoke.py, and prints a balance report with TARGET ok / MISS lines:
--   fighter   the played kit vs a passive NPC of k x its power (kit factor 1.3-1.7); mirror fights 8-45 s, none at 90 s
--   support   Support (Economy) pets: DPS ratio 0.65-0.75 of Combat pets; a Support fighter can fight, best as a helper
--   duels     mirror duels per stage (scripted players both sides): 40-60%, no draws, none at the 120 s limit
--   raids     1 / 4 / 8 / 16 dodging fighters finish every boss in 100-240 s; no one-shots; joins / leaves; idle alts
--   ring      rounds 1-3 >= 95% for every single level-1 rollable pet; the stage medians S1 16 .. S10 51 (+-2)
--   dungeon   floor 1 for the 12 single level-1 pets (100%); the stage ladder (monotonic, S10 >= floor 10); a 4-party +1 floor
--   training  trained / evolved TeamPower ratios; trained mirror duels fair; trained raids 100-240 s
--   move      the B1 character patterns (random targets + an r 14 circle) at the legal run speed with a 200 ms feed delay:
--             the server fighter keeps up (gap <= 0.5 after the catch-up, zero leashes); a run-off past the zone is leashed
--   perf      a 16-fighter raid with waves steps in well under 1 ms;  progression: XP / Cash behind each stage, Validate
--
-- Run it (lupa, from the repo root; see tools/README.md):
--   python3 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"
--   SIM_BATTLE="quick only=duels,raids" python3 -c "..."     options: quick | full | seeds=N | only=a,b | verbose
-- The smoke scenario p5battle_balance loads this file as a library (global SIM_BATTLE_LIBRARY = true before the load)
-- and runs a short subset; p5dgn_balance (dungeon W3) uses SIM.Stages / SIM.team / SIM.Player / SIM.dungeonFloor.
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
	for _, name in ipairs({ "MeshIds", "Config", "Util", "PetCatalog", "PetKeys", "TycoonCatalog", "BattleCatalog", "BattleSim" }) do
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

local ENTRY_FIELDS = { "Key", "PetId", "Def", "Level", "Tier", "Evo", "Train", "Boost", "Boss", "Handicap", "Crowned", "Xp", "XpNext", "Wild", "NoSpecial" }
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
-- the Phase 4 ring medians per stage (the W1 gate: within +-2 after the re-tune)
SIM.RingMedians = { S1 = 16, S3 = 23, S5 = 28, S7 = 36, S9 = 44, S10 = 51 }

----------------------------------------------------------------------
-- A scripted player (the character + the kit): walks the character at the legal run speed toward its target, keeps its
-- range, directs the auto-attacking pet (ATTACK on a new target), ELEMENT / SPECIAL when ready, helper BUFFs, SWAPs a dying fighter, and DASHes out
-- of a wind-up or a telegraph with probability opts.dodge (default 0.7) after a human reaction (0.1-0.3 s)
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
	self.escape = nil
	self.escapeUntil = 0
	self.castAt = nil
	self.dodges = 0
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
	-- threats: a wind-up aimed at me, a telegraph covering my character
	for _, ev in ipairs(events) do
		if ev.type == "Windup" and ev.target == fid and dodge > 0 then
			if self.rand() < dodge then
				local at = ev.at - 0.05 - 0.1 * self.rand()
				if at < t + 0.05 then
					at = t + 0.05
				end
				if not self.dashAt or at < self.dashAt then
					self.dashAt = at
				end
			end
		elseif ev.type == "Telegraph" and dodge > 0 and inShape(ev, me.x, me.z, myInfo.radius or 2) then
			if self.rand() < dodge then
				-- run out of the shape (the shortest way), and dash just before it lands as a backup
				local ex, ez
				if ev.shape == "Line" then
					local dirX, dirZ = cos(ev.angle), sin(ev.angle)
					local side = ((me.x - ev.x) * dirZ - (me.z - ev.z) * dirX) >= 0 and 1 or -1
					ex, ez = me.x + side * dirZ * (ev.width + 4), me.z - side * dirX * (ev.width + 4)
				else
					local dx, dz = me.x - ev.x, me.z - ev.z
					local d = sqrt(dx * dx + dz * dz)
					if d < 0.01 then
						dx, dz, d = 1, 0, 1
					end
					ex, ez = ev.x + dx / d * (ev.r + 4), ev.z + dz / d * (ev.r + 4)
				end
				self.escape = { x = max(-self.zoneX + 2, min(self.zoneX - 2, ex)), z = max(-self.zoneZ + 2, min(self.zoneZ - 2, ez)) }
				self.escapeUntil = ev.at + 0.3
				local at = ev.at - 0.1 - 0.1 * self.rand()
				if not self.dashAt or at < self.dashAt then
					self.dashAt = max(at, t + self:reaction())
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
	-- the character walks: to the escape point, else toward the target to its reach
	local speeds = tinfo.Speed or { Run = 16 }
	local run = speeds.Run or 16
	local goalX, goalZ = self.cx, self.cz
	if self.escape and t < self.escapeUntil then
		goalX, goalZ = self.escape.x, self.escape.z
	elseif target then
		local tu = units[target]
		local tinfo2 = self.info[target]
		local want = (myInfo.range or 4) + (tinfo2 and tinfo2.radius or 2) - 0.8
		local dx, dz = tu.x - self.cx, tu.z - self.cz
		local d = sqrt(dx * dx + dz * dz)
		if d > want and d > 0.01 then
			goalX, goalZ = tu.x - dx / d * want, tu.z - dz / d * want
		elseif d < want - 2 and d > 0.01 and myInfo.ranged then
			goalX, goalZ = tu.x - dx / d * want, tu.z - dz / d * want
		end
	else
		self.escape = nil
	end
	local gx, gz = goalX - self.cx, goalZ - self.cz
	local gd = sqrt(gx * gx + gz * gz)
	if gd > 0.05 then
		local step = min(gd, run * DT)
		self.cx, self.cz = self.cx + gx / gd * step, self.cz + gz / gd * step
	end
	self.cx = max(-self.zoneX + 1, min(self.zoneX - 1, self.cx))
	self.cz = max(-self.zoneZ + 1, min(self.zoneZ - 1, self.cz))
	-- the Move feed (with an optional delay of `delay` steps: what a 200 ms old position looks like)
	self.history[#self.history + 1] = { self.cx, self.cz }
	local idx = max(1, #self.history - self.delay)
	local fed = self.history[idx]
	b:Command(self.owner, "Move", fed[1], fed[2])
	if #self.history > 64 then
		table.remove(self.history, 1)
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
	local stats = { steps = 0, events = 0, hits = 0, misses = 0, kos = 0, specials = 0, telegraphs = 0, maxPetHit = 0, maxBossHit = 0, bossHits = 0, dodges = 0, teleHits = 0, swaps = 0, buffs = 0, elements = 0 }
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
	end
	local result = b:Result()
	if not result then
		result = { Reason = "Unfinished", Duration = b:Time(), Winners = {}, Losers = {}, Damage = {}, Shares = {}, Survivors = {} }
	end
	return result, stats, b
end

local function series(makeSetup, policies, seeds, playerOpts)
	local agg = { n = 0, wins = { [1] = 0, [2] = 0 }, draws = 0, timeouts = 0, dur = 0, maxDur = 0, maxPetHit = 0, maxBossHit = 0, kos = 0, specials = 0, seconds = 0, dodges = 0, telegraphs = 0, teleHits = 0, bossHits = 0, misses = 0, durations = {} }
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
-- returns cleared (bool), seconds; teams = player team specs, policies as in SIM.run
function SIM.dungeonRoom(f, r, teams, policies, seed, playerOpts)
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
	b:SpawnEnemies(BC.DungeonWave(f, r, 1, n, seed).Pets, { Wave = 1, Anchor = anchor })
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
					b:SpawnEnemies(BC.DungeonWave(f, r, wave, n, seed).Pets, { Wave = wave })
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
	header("Duels: an element counter (Flame fighter vs a Nature fighter of equal power)")
	local flame = { pet("maple_fox", 10), pet("bubble_axolotl", 8), pet("storm_tabby", 8) }
	local nature = { pet("bamboo_panda", 10), pet("bubble_axolotl", 8), pet("storm_tabby", 8) }
	local agg = series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, flame), team(2, 2, nature) } }
	end, { [1] = "player", [2] = "player" }, opts.seeds)
	out(fmt("  Flame maple_fox vs Nature bamboo_panda (powers %d vs %d): Flame wins %3d%%  dur %5.1f s", powerOf(flame), powerOf(nature), agg.winPct, agg.avgDur))
	target("the element counter wins more than half but not everything (55-90%)", agg.winPct >= 55 and agg.winPct <= 90, fmt("%d%%", agg.winPct))
end)

-- 5. raids
section("raids", function(opts)
	header("Raids: 1 / 4 / 8 / 16 dodging fighters (70% of wind-ups and telegraphs) should finish every boss in 100-240 s")
	local seeds = max(1, floor(opts.seeds / 8))
	local stages = { { Id = "M5", Pets = SIM.Stages[5].Pets }, { Id = "M8", Pets = SIM.Stages[8].Pets } }
	local wonCombos, combos, anyBossHit = 0, 0, 0
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
				out(fmt("  %-13s %-3s %2dp: win %3d%% dur %5.1f s (dodges %5.1f, dodged hits %5.1f, KOs %4.1f, maxBossHit %.2f, tele hits %4.1f)",
					boss, stage.Id, players, agg.winPct, agg.avgDur, agg.dodges / max(1, agg.n), agg.misses / max(1, agg.n), agg.kos / max(1, agg.n), agg.maxBossHit, agg.teleHits / max(1, agg.n)))
				combos = combos + 1
				if agg.winPct >= 50 then
					wonCombos = wonCombos + 1
					if agg.avgDur < 90 or agg.avgDur > 250 then
						cellOk = false
					end
					sumDur, cells = sumDur + agg.avgDur, cells + 1
				end
				anyBossHit = max(anyBossHit, agg.maxBossHit)
			end
			if cells > 0 and (sumDur / cells < 100 or sumDur / cells > 240) then
				avgOk = false
			end
			out(fmt("  %-13s %-3s average over 1/4/8/16 players: %.0f s", boss, stage.Id, cells > 0 and sumDur / cells or 0))
		end
	end
	target("dodging fighters win nearly every raid (1/4/8/16 players, two stages, four bosses: >= 90% of the combos)", wonCombos >= combos * 0.9, fmt("%d of %d", wonCombos, combos))
	target("won raids last 100-240 s per boss and stage (every single cell within 90-250 s: a few seeds per cell)", avgOk and cellOk)
	target("no boss hit takes more than 80% of a fighter before the enrage", anyBossHit <= 0.8, fmt("max %.2f", anyBossHit))

	header("Raids: joining late and leaving (boss HP shares)")
	local b = BS.new({ Mode = "Raid", Boss = "frost_wyrm", Seed = 2, Teams = { team(1, 1, SIM.Stages[5].Pets, { Auto = true }) } })
	local hp0 = b:BossStatus().MaxHp
	for _ = 1, 50 do
		b:Step(DT)
	end
	b:AddTeam(team(2, 1, SIM.Stages[5].Pets, { Auto = true }))
	local hp1 = b:BossStatus().MaxHp
	for _ = 1, 50 do
		b:Step(DT)
	end
	b:RemoveTeam(2)
	local hp2 = b:BossStatus().MaxHp
	out(fmt("  boss max HP: 1 player %d -> a second joins %d -> leaves %d", hp0, hp1, hp2))
	target("boss HP grows when a player joins and shrinks back when they leave", hp1 > hp0 * 1.8 and abs(hp2 - hp0) <= hp0 * 0.05)

	header("Raids: joiners who bring nothing (idle alts with level-1 Commons) do not inflate the boss for the real player")
	local withAlts = { team(400, 1, SIM.Stages[7].Pets) }
	for i = 1, 7 do
		withAlts[#withAlts + 1] = team(400 + i, 1, SIM.Stages[1].Pets, { Auto = true })
	end
	local solo = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 5, Teams = { team(400, 1, SIM.Stages[7].Pets) } })
	local crowded = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 5, Teams = withAlts })
	local soloHp, crowdedHp = solo:BossStatus().MaxHp, crowded:BossStatus().MaxHp
	out(fmt("  Storm Titan HP for one S7 team %d, with 7 idle alt teams %d (x%.2f); weighted head count %.2f", soloHp, crowdedHp, crowdedHp / soloHp, crowded.playerTeamCount or 0))
	target("seven alt teams with level-1 Commons add less than 15% to the boss's HP", crowdedHp <= soloHp * 1.15, fmt("x%.2f", crowdedHp / soloHp))
end)

-- 6. the Champion Ring
local function ringFight(pets, round, runSeed, battleSeed)
	return SIM.run({ Mode = "Ring", Seed = battleSeed, Round = round, Teams = { team(77, 1, pets), BC.ChampionTeam(round, runSeed) } }, { [77] = "player" })
end

local function ringRun(pets, runSeed, maxRound)
	local r, total = 1, 0
	local durations = {}
	local intermission = BC.Ring.Intermission or 3
	while r <= (maxRound or 150) do
		local res = ringFight(pets, r, runSeed, runSeed * 13 + r)
		local d = res and res.Duration or 0
		total = total + d
		if not res or res.WinnerSide ~= 1 then
			break
		end
		durations[#durations + 1] = d
		total = total + intermission
		r = r + 1
	end
	return r - 1, durations, total
end
SIM.ringRun = ringRun

section("ring", function(opts)
	local R = BC.Ring
	header(fmt("Champion Ring: single level-1 pets vs the first rounds (scripted player; FirstPower %.2f, Growth %.3f)", R.FirstPower, R.Growth))
	local seeds1 = opts.quick and 12 or 32
	local list = starters()
	local NR = 6
	local worst, avg = {}, {}
	for r = 1, NR do
		worst[r], avg[r] = 100, 0
	end
	for _, id in ipairs(list) do
		local row = {}
		for r = 1, NR do
			local wins, dur = 0, 0
			for seed = 1, seeds1 do
				local res = ringFight({ pet(id, 1) }, r, seed, seed * 7 + r)
				if res and res.WinnerSide == 1 then
					wins = wins + 1
				end
				dur = dur + (res and res.Duration or 0)
			end
			local p = pct(wins, seeds1)
			worst[r] = min(worst[r], p)
			avg[r] = avg[r] + p / #list
			row[#row + 1] = fmt("r%d %3d%%/%2.0fs", r, p, dur / seeds1)
		end
		out(fmt("  %-15s %s", id, table.concat(row, " ")))
	end
	target(fmt("rounds 1-3 are won >= 95%% by EVERY single level-1 rollable Common / Uncommon (%d pets, %d seeds)", #list, seeds1), worst[1] >= 95 and worst[2] >= 95 and worst[3] >= 95, fmt("worst r1 %d%%, r2 %d%%, r3 %d%%", worst[1], worst[2], worst[3]))
	target("the single-pet average stays >= 80% at rounds 4-5 (no cliff)", avg[4] >= 80 and avg[5] >= 80, fmt("r4 %.0f%%, r5 %.0f%%, r6 %.0f%%", avg[4], avg[5], avg[6]))

	header("Champion Ring: the record (the last round won, fresh HP every round) per progression stage")
	local seeds2 = opts.quick and 6 or 12
	local medians, fightOk, lastMedian, monotonic = {}, true, -1, true
	for _, st in ipairs(SIM.Stages) do
		local records, durs, totals = {}, {}, {}
		for seed = 1, seeds2 do
			local rec, d, total = ringRun(st.Pets, 1000 + seed)
			records[#records + 1] = rec
			for _, x in ipairs(d) do
				durs[#durs + 1] = x
			end
			totals[#totals + 1] = total
		end
		local med = median(records)
		medians[st.Id] = med
		local avgFight = mean(durs)
		table.sort(records)
		out(fmt("  %-4s %-11s power %6d  record median %3d (min %d, max %d)  avg fight %4.1f s  run %4.1f min", st.Id, st.Name, powerOf(st.Pets), med, records[1], records[#records], avgFight, mean(totals) / 60))
		if avgFight < 4 or avgFight > 40 then
			fightOk = false
		end
		if med < lastMedian then
			monotonic = false
		end
		lastMedian = max(lastMedian, med)
	end
	local allOk, detail = true, {}
	for _, id in ipairs({ "S1", "S3", "S5", "S7", "S9", "S10" }) do
		local want = SIM.RingMedians[id]
		detail[#detail + 1] = fmt("%s %d (want %d)", id, medians[id], want)
		if abs(medians[id] - want) > 2 then
			allOk = false
		end
	end
	target("median records within +-2 of the Phase 4 stages: S1 16, S3 23, S5 28, S7 36, S9 44, S10 51", allOk, table.concat(detail, ", "))
	target("the record never falls with the stage", monotonic)
	target("ring fights last 4-40 s on average at every stage", fightOk)

	header("Champion Ring: the ladder (power never drops, never ends; Boost past the level-50 Rainbow boss)")
	local mono, firstBoost, lateOk = true, {}, true
	for seed = 1, 40 do
		local last = 0
		local first = nil
		for r = 1, 120 do
			local spec = BC.ChampionTeam(r, seed)
			if r > #R.EasyRounds and spec.Power < last then
				mono = false
			end
			last = spec.Power
			local boost = spec.Pets[1].Boost
			if boost and boost > 1 and not first then
				first = r
			end
			if r >= 80 and not (boost and boost > 1) then
				lateOk = false
			end
		end
		firstBoost[#firstBoost + 1] = first or 999
	end
	table.sort(firstBoost)
	local p120, p100 = BC.RingPower(120, 1), BC.RingPower(100, 1)
	target("the champion's power never drops from a round to the next (rounds 3-120, 40 seeds)", mono)
	target("no ceiling: round 120 is stronger than round 100, and every champion from round 80 on is boosted", p120 > p100 and lateOk, fmt("%.0f vs %.0f; first boosted round median %d", p120, p100, median(firstBoost)))
	for _, r in ipairs({ 1, 2, 3, 4, 5, 8, 10, 15, 20, 25, 30, 40, 50, 60, 80, 100 }) do
		local spec = BC.ChampionTeam(r, 1)
		local e = spec.Pets[1]
		out(fmt("  round %3d  target %10.1f  power %10.1f  %-18s L%-2d %-7s%s%s%s", r, BC.RingTarget(r), spec.Power, e.PetId, e.Level, e.Tier, e.Boss and " BOSS" or "", e.Boost and fmt(" x%.2f", e.Boost) or "", e.Handicap and fmt(" h%.2f", e.Handicap) or ""))
	end
end)

-- 7. the Dungeon
section("dungeon", function(opts)
	local D = BC.Dungeon
	header(fmt("Dungeon: floor 1 (target %.1f per player, ONE handicapped enemy per wave) solo with ONE level-1 pet (the tutorial floor)", D.Floor1Power))
	local seeds = opts.quick and 3 or 6
	local worst = 100
	for _, id in ipairs(starters()) do
		local wins, minutes = 0, 0
		for seed = 1, seeds do
			local rooms, m = SIM.dungeonFloor(1, { pet(id, 1) }, 1, seed)
			if rooms == 4 then
				wins = wins + 1
			end
			minutes = minutes + m
		end
		local p = pct(wins, seeds)
		worst = min(worst, p)
		out(fmt("  %-15s floor 1 cleared %3d%%  avg %.1f min", id, p, minutes / seeds))
	end
	target("floor 1 is cleared by every single level-1 rollable Common / Uncommon (100%)", worst == 100, fmt("worst %d%%", worst))

	header(fmt("Dungeon: the stage ladder (solo, %d seeds): the highest floor cleared in >= half of the seeds; FirstPower %.1f Growth %.2f RoomMult %.2f/%.2f/%.2f", seeds, D.FirstPower, D.Growth, D.RoomMult[1], D.RoomMult[2], D.RoomMult[3]))
	local ladder = {}
	local lastFloor = 0
	local monotonic = true
	for _, st in ipairs(SIM.Stages) do
		local f = max(1, lastFloor - 1)
		local best = 0
		local parts = {}
		while f <= D.Floors do
			local clears, rooms, minutes = 0, 0, 0
			for seed = 1, seeds do
				local r, m = SIM.dungeonFloor(f, st.Pets, 1, seed)
				rooms = rooms + r
				minutes = minutes + m
				if r == 4 then
					clears = clears + 1
				end
			end
			parts[#parts + 1] = fmt("F%d:%d%%/%.1fm", f, pct(clears, seeds), minutes / seeds)
			if clears * 2 >= seeds then
				best = f
				f = f + 1
			else
				break
			end
		end
		ladder[st.Id] = best
		if best < lastFloor then
			monotonic = false
		end
		lastFloor = max(lastFloor, best)
		out(fmt("  %-4s %-11s power %6d  clears to F%-2d  %s", st.Id, st.Name, powerOf(st.Pets), best, table.concat(parts, " ")))
	end
	target("the ladder never falls with the stage", monotonic)
	target("S10 (the maxed team) clears floor 10 or higher", ladder.S10 >= 10, fmt("F%d", ladder.S10))
	target("S1 clears floor 1-2 and S5 reaches floors 4-6 (the middle of the ladder)", ladder.S1 >= 1 and ladder.S1 <= 2 and ladder.S5 >= 4 and ladder.S5 <= 6, fmt("S1 F%d, S5 F%d", ladder.S1, ladder.S5))

	header("Dungeon: a party of 4 (copies of S3) gains about one floor over the solo S3")
	local party4 = 0
	for f = max(1, ladder.S3), D.Floors do
		local clears = 0
		for seed = 1, seeds do
			local r = SIM.dungeonFloor(f, SIM.Stages[3].Pets, 4, seed)
			if r == 4 then
				clears = clears + 1
			end
		end
		if clears * 2 >= seeds then
			party4 = f
		else
			break
		end
	end
	out(fmt("  S3 solo clears to F%d, a party of 4 x S3 to F%d", ladder.S3, party4))
	target("a 4-party clears one or two floors more than the solo team", party4 - ladder.S3 >= 1 and party4 - ladder.S3 <= 2, fmt("+%d", party4 - ladder.S3))
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
		-- the fighter auto-attacks (dungeon fixes 4): the dummy may neither fall nor hit, the battle must outlast the patterns
		for _, u in ipairs(b.units) do
			if u.side == 2 then
				u.maxHp, u.hp, u.hit = 1e9, 1e9, 0
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
