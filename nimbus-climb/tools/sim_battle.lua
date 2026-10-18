-- sim_battle.lua: the Phase 3 battle balance harness (ARCHITECTURE_V3.md "Phase 3 build contract", battlecore).
-- Runs the REAL shared modules (BattleCatalog + BattleSim on top of PetCatalog / PetKeys / TycoonCatalog / Config)
-- inside the Roblox mock under lupa, like tools/smoke.py, and prints a balance report with pass / miss lines for
-- the targets of the contract:
--   * the Trial curve 1-30 against typical teams along the tycoon progression (early players clear ~1-8, mid game
--     ~10-20, prestiged players reach 30), and "equal power is a fair fight"
--   * PvP: equal teams win ~50%, an element counter ~60-65%, melee vs ranged compositions stay close
--   * boss raids with 1 / 3 / 8 players (dodging players) finish in ~2-4 minutes, non-dodgers see several telegraphs
--   * dodge: a timely RETREAT escapes nearly every telegraph, Lines and Circles alike (>= 85% of threatened pets
--     for a perfect dodger; a RETREAT one second after the warning still escapes most)
--   * every special is useful (and none is an auto-win), no one-shots, no unkillable sustain teams, no stalemates;
--     a team that only RETREATs returns to the fight by itself (Damage.RetreatAutoResume)
--   * performance: a raid of 8 teams x 4 pets + boss + minions steps in well under 1 ms
--   Phase 4 ("Phase 4 build contract" 8.3):
--   * training: all four skills rank 5 x1.25-1.4 / rank 10 x1.6-1.85 TeamPower, Evolved x1.25 / x1.5, trained mirror
--     duels 35-65% with no draws or timeouts (Damage.Overtime), trained raids still 100-240 s with dodging players
--   * ring: the Champion Ring (rounds 1-3 for every single level-1 starter, the single-pet slope, the median record per
--     stage, fights 4-40 s, the power never dropping and never stopping, Boost from rounds 40-50)
--   * level100: a maxed level-100 team (raids 100-240 s, no one-shots, fair mirrors, the duel practice gap)
--   * progression: the XP behind each stage and its Food Machine price
--
-- Run it (lupa, from the repo root; see tools/README.md):
--   python3 -c "import lupa.luajit21 as L; L.LuaRuntime().execute(open('tools/sim_battle.lua').read())"
--   SIM_BATTLE="quick only=trials,raids" python3 -c "..."     options: quick | full | seeds=N | only=a,b | verbose
--   sections: roster, duels, elements, trials, raids, dodge, specials, extremes, perf, training, ring, level100,
--   progression
-- The smoke scenario p3battle_balance loads this file as a library (global SIM_BATTLE_LIBRARY = true before the
-- load) and runs a short subset. Plain Lua 5.1 syntax only.

local SIM = {}

----------------------------------------------------------------------
-- Boot: outside smoke.py / render_model.py there is no mock yet -> load tools/robloxmock.lua and mount the modules
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
	for _, name in ipairs({ "Config", "Util", "PetCatalog", "PetKeys", "TycoonCatalog", "BattleCatalog", "BattleSim" }) do
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
local fmt = string.format

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
-- the mock swallows print() (it records game output), so the report goes straight to stdout; the smoke test
-- replaces SIM.print with its own sink
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

-- the entry fields a team spec carries (Phase 4: Evo / Train / Boost / Boss / Handicap / Crowned / Xp go along)
local ENTRY_FIELDS = { "Key", "PetId", "Def", "Level", "Tier", "Evo", "Train", "Boost", "Boss", "Handicap", "Crowned", "Xp", "XpNext" }
local function copyEntry(p)
	local e = {}
	for _, k in ipairs(ENTRY_FIELDS) do
		e[k] = p[k]
	end
	return e
end

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

-- the same pets at the levels that land closest to `wanted` TeamPower: one uniform level first, then single pets
-- are nudged up or down a level while that gets closer (1..maxLevel)
local function atPower(pets, wanted, maxLevel)
	local top = maxLevel or 50
	local best, bestDiff = nil, huge
	for lv = 1, top do
		local copy = {}
		for i, p in ipairs(pets) do
			copy[i] = pet(p.Key, lv, p.Tier)
		end
		local diff = abs(powerOf(copy) - wanted)
		if diff < bestDiff then
			best, bestDiff = copy, diff
		end
	end
	local improved = true
	while improved do
		improved = false
		for i = 1, #best do
			for _, delta in ipairs({ 1, -1 }) do
				local lv = best[i].Level + delta
				if lv >= 1 and lv <= top then
					local copy = {}
					for k, p in ipairs(best) do
						copy[k] = pet(p.Key, p.Level, p.Tier)
					end
					copy[i].Level = lv
					local diff = abs(powerOf(copy) - wanted)
					if diff < bestDiff then
						best, bestDiff, improved = copy, diff, true
					end
				end
			end
		end
	end
	return best
end

-- bring two rosters to the same TeamPower: the weaker one is levelled up to the stronger; when its level cap
-- cannot reach that, the stronger one is levelled down to meet it instead
local function balance(a, b)
	local pa, pb = powerOf(a), powerOf(b)
	if pa < pb then
		a, b, pa, pb = b, a, pb, pa
	end
	local raised = atPower(b, pa)
	if abs(powerOf(raised) - pa) <= pa * 0.05 then
		return a, raised
	end
	local topB = powerOf(raised)
	return atPower(a, topB), raised
end

-- Typical teams along the tycoon progression (levels from feeding / Gym XP, tiers from the Fusion Machine)
SIM.Stages = {
	{ Id = "S1", Name = "Day 1", Clear = { 1, 3 }, Pets = { pet("mallow_kitten", 1), pet("puddle_frog", 1), pet("pebble_pup", 1) } },
	{ Id = "S2", Name = "First week", Clear = { 3, 6 }, Pets = { pet("mallow_kitten", 4), pet("biscuit_bear", 3), pet("maple_fox", 3) } },
	{ Id = "S3", Name = "Early", Clear = { 5, 9 }, Pets = { pet("maple_fox", 6), pet("bubble_axolotl", 5), pet("storm_tabby", 4) } },
	{ Id = "S4", Name = "Early+", Clear = { 7, 11 }, Pets = { pet("storm_tabby", 8), pet("frostling_penguin", 7), pet("bamboo_panda", 8) } },
	{ Id = "S5", Name = "Mid", Clear = { 10, 15 }, Pets = { pet("aurora_fox", 12), pet("storm_tabby", 14), pet("frostling_penguin", 12) } },
	{ Id = "S6", Name = "Mid+", Clear = { 13, 19 }, Pets = { pet("aurora_fox", 18), pet("moonlit_owl", 16), pet("ember_phoenix", 12) } },
	{ Id = "S7", Name = "Prestige 1", Clear = { 18, 24 }, Pets = { pet("ember_phoenix", 24), pet("twilight_dragon", 22), pet("aurora_fox", 20, "Golden"), pet("moonlit_owl", 20) } },
	{ Id = "S8", Name = "Prestige 2", Clear = { 22, 27 }, Pets = { pet("cloudy_dragon", 25), pet("twilight_dragon", 28), pet("ember_phoenix", 26, "Golden"), pet("aurora_fox", 24, "Golden") } },
	{ Id = "S9", Name = "Endgame", Clear = { 26, 30 }, Pets = { pet("cloudy_dragon", 40, "Golden"), pet("stormfang", 35), pet("eclipse_dragon", 35), pet("twilight_dragon", 40, "Rainbow") } },
	{ Id = "S10", Name = "Maxed", Clear = { 30, 30 }, Pets = { pet("stormfang", 50, "Rainbow"), pet("cloudy_dragon", 45, "Rainbow"), pet("eclipse_dragon", 50, "Rainbow"), pet("obsidian_phoenix", 50, "Rainbow") } },
}

----------------------------------------------------------------------
-- A scripted player: presses SPECIAL when a meter is full, focuses the weakest enemy, RETREATs out of telegraphs
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

function Player.new(battle, owner, seed, opts)
	local self = setmetatable({}, Player)
	self.battle = battle
	self.owner = owner
	self.rand = lcg(seed)
	self.opts = opts or {}
	self.radius = {}
	self.side = nil
	self.mine = {}
	for _, info in ipairs(battle:StaticUnits()) do
		self.radius[info.id] = info.radius
		if info.owner == owner then
			self.mine[#self.mine + 1] = info.id
			self.side = info.side
		end
	end
	self.retreatAt = nil
	self.attackAt = nil
	self.nextFocus = 0
	self.castAt = {}
	self.retreating = false
	self.dodges = 0
	return self
end

local function inShape(ev, x, z, radius)
	if ev.shape == "Line" then
		local dx, dz = x - ev.x, z - ev.z
		local dirX, dirZ = math.cos(ev.angle), math.sin(ev.angle)
		local along = dx * dirX + dz * dirZ
		if along < -radius or along > ev.length + radius then
			return false
		end
		return abs(dx * dirZ - dz * dirX) <= ev.width / 2 + radius
	end
	local dx, dz = x - ev.x, z - ev.z
	return dx * dx + dz * dz <= (ev.r + radius) * (ev.r + radius)
end

function Player:step(events, snapshot)
	local b = self.battle
	local t = b:Time()
	local units = snapshot.Units
	-- new units (minion waves) need radii
	for _, ev in ipairs(events) do
		if ev.type == "Spawn" then
			for _, info in ipairs(ev.units) do
				self.radius[info.id] = info.radius
			end
		end
	end
	-- dodge telegraphs that would hit one of my pets
	if self.opts.dodge ~= false then
		for _, ev in ipairs(events) do
			if ev.type == "Telegraph" then
				local threatened = false
				for _, id in ipairs(self.mine) do
					local u = units[id]
					if u and u.hp > 0 and inShape(ev, u.x, u.z, self.radius[id] or 2) then
						threatened = true
					end
				end
				if threatened then
					local reaction = 0.4 + 0.5 * self.rand()
					local at = t + reaction
					if not self.retreatAt or at < self.retreatAt then
						self.retreatAt = at
					end
					local back = ev.at + 0.1
					if not self.attackAt or back > self.attackAt then
						self.attackAt = back
					end
				end
			end
		end
	end
	if self.retreatAt and t >= self.retreatAt then
		self.retreatAt = nil
		if b:Command(self.owner, "Retreat") then
			self.retreating = true
			self.dodges = self.dodges + 1
		end
	end
	if self.retreating and self.attackAt and t >= self.attackAt then
		local ok = b:Command(self.owner, "Attack")
		if ok then
			self.retreating = false
			self.attackAt = nil
		end
	end
	-- focus the enemy with the least HP left (duels / trials); raids leave the pets on the nearest target
	if not self.retreating and self.opts.focus ~= false and b.mode ~= "Raid" and t >= self.nextFocus then
		self.nextFocus = t + 2
		-- finish off a wounded enemy (below half); otherwise leave the pets on their own targets
		local bestId, bestFrac = nil, 0.5
		for _, info in ipairs(b:StaticUnits()) do
			local u = units[info.id]
			if info.side ~= self.side and u and u.hp > 0 and info.maxHp > 0 then
				local frac = u.hp / info.maxHp
				if frac < bestFrac then
					bestId, bestFrac = info.id, frac
				end
			end
		end
		if bestId ~= self.focused then
			b:Command(self.owner, "Attack", bestId)
			self.focused = bestId
		end
	end
	-- specials when the meter is full (after a human-ish reaction)
	if not self.retreating and self.opts.specials ~= false then
		for slot, id in ipairs(self.mine) do
			local u = units[id]
			if u and u.hp > 0 and u.meter >= 100 then
				if not self.castAt[slot] then
					self.castAt[slot] = t + 0.3 + 0.5 * self.rand()
				elseif t >= self.castAt[slot] then
					local ok = b:Command(self.owner, "Special", slot)
					if ok then
						self.castAt[slot] = nil
					else
						self.castAt[slot] = t + 0.5
					end
				end
			else
				self.castAt[slot] = nil
			end
		end
	end
end

----------------------------------------------------------------------
-- Running battles
----------------------------------------------------------------------
-- policies: { [owner] = "auto" | "player" | "idle" }; "auto" teams get Auto = true in their spec (the harness caller
-- sets it), "player" teams get a scripted Player, "idle" teams never command (pure auto-battle without specials)
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
	local stats = { steps = 0, events = 0, hits = 0, kos = 0, specials = 0, telegraphs = 0, maxPetHit = 0, maxBossHit = 0, bossHits = 0, dodges = 0, teleHits = 0 }
	local hpOf = {}
	local kindOf = {}
	for _, info in ipairs(b:StaticUnits()) do
		hpOf[info.id] = info.maxHp
		kindOf[info.id] = info.kind
	end
	local maxSteps = floor((b.timeLimit + 5) / 0.1) + 10
	local t0 = clock()
	while not b:IsFinished() and stats.steps < maxSteps do
		local events = b:Step(0.1)
		stats.steps = stats.steps + 1
		stats.events = stats.events + #events
		for _, ev in ipairs(events) do
			if ev.type == "Hit" then
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
			elseif ev.type == "KO" then
				stats.kos = stats.kos + 1
			elseif ev.type == "Special" then
				stats.specials = stats.specials + 1
			elseif ev.type == "Telegraph" then
				stats.telegraphs = stats.telegraphs + 1
			elseif ev.type == "Spawn" then
				for _, info in ipairs(ev.units) do
					hpOf[info.id] = info.maxHp
					kindOf[info.id] = info.kind
				end
			end
		end
		if #players > 0 then
			local snap = b:Snapshot()
			for _, p in ipairs(players) do
				p:step(events, snap)
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

-- many seeds of one matchup -> win counts and averages
local function series(makeSetup, policies, seeds, playerOpts)
	local agg = { n = 0, wins = { [1] = 0, [2] = 0 }, draws = 0, timeouts = 0, dur = 0, maxPetHit = 0, maxBossHit = 0, kos = 0, specials = 0, seconds = 0, dodges = 0, telegraphs = 0, teleHits = 0, bossHits = 0, durations = {} }
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
		end
	end
	agg.winPct = pct(agg.wins[1], agg.n)
	agg.avgDur = agg.n > 0 and agg.dur / agg.n or 0
	return agg
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
section("roster", function(opts)
	header("Roster: battle stats at level 1 (UnitPower = sqrt(DPS x HP) / 3)")
	out(fmt("  %-20s %-10s %-7s %-9s %5s %7s %6s %5s %5s  %s", "pet", "rarity", "role", "element", "power", "hp", "hit", "int", "move", "special"))
	local economy, combat = {}, {}
	for _, def in ipairs(PC.Pets) do
		local us = BC.UnitStats(def.Id, 1)
		local p = BC.UnitPower(def.Id, 1)
		out(fmt("  %-20s %-10s %-7s %-9s %5d %7.0f %6.1f %5.2f %5.1f  %s %s", def.Id, def.Rarity, def.Role, def.Element, p, us.MaxHp, us.Hit, us.Interval, us.MoveSpeed, def.Special.Kind, us.Ranged and "(ranged)" or "(melee)"))
		local scale = (PC.GetStats(def.Id, 1).Health / def.Stats.Health)
		local norm = p / scale -- per rarity scale
		if def.Role == "Economy" then
			economy[#economy + 1] = norm
		else
			combat[#combat + 1] = norm
		end
	end
	local function mean(list)
		local s = 0
		for _, v in ipairs(list) do
			s = s + v
		end
		return #list > 0 and s / #list or 0
	end
	local ratio = mean(economy) / max(0.001, mean(combat))
	out(fmt("  economy pets fight at %.0f%% of a combat pet of the same rarity", ratio * 100))
	target("economy pets are clearly weaker fighters than combat pets (30-60%)", ratio >= 0.3 and ratio <= 0.6, fmt("%.0f%%", ratio * 100))
	out(fmt("  stormfang L50 Rainbow power %d; a maxed Rainbow team ~%d", BC.UnitPower("stormfang", 50, "Rainbow"), powerOf(SIM.Stages[10].Pets)))
end)

-- 2. duels: mirrors at several tiers, compositions, durations
section("duels", function(opts)
	header("Duels: equal teams (win% of side 1 should be ~50), durations 25-70 s")
	local seeds = opts.seeds
	local tiers = {
		{ "Commons L1", { pet("mallow_kitten", 1), pet("puddle_frog", 1), pet("biscuit_bear", 1) } },
		{ "Rares L10", { pet("storm_tabby", 10), pet("frostling_penguin", 10), pet("shroomie_frog", 10) } },
		{ "Legendary L25", { pet("ember_phoenix", 25), pet("twilight_dragon", 25), pet("sunbeam_bear", 25) } },
		{ "Mythic+ L40 Golden x4", { pet("cloudy_dragon", 40, "Golden"), pet("obsidian_phoenix", 40, "Golden"), pet("stormfang", 40, "Golden"), pet("eclipse_dragon", 40, "Golden") } },
	}
	local allOk, durOk = true, true
	local worst = 50
	for _, tier in ipairs(tiers) do
		for _, policy in ipairs({ "auto", "player" }) do
			local flags = policy == "auto" and { Auto = true } or {}
			local agg = series(function(seed)
				return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, tier[2], flags), team(2, 2, tier[2], flags) } }
			end, { [1] = policy, [2] = policy }, seeds * 2)
			out(fmt("  %-24s %-6s side1 %3d%%  draws %d  timeouts %d  dur %5.1f s  maxHit %.2f  specials/fight %.1f", tier[1], policy, agg.winPct, agg.draws, agg.timeouts, agg.avgDur, agg.maxPetHit, agg.specials / max(1, agg.n)))
			if abs(agg.winPct - 50) > abs(worst - 50) then
				worst = agg.winPct
			end
			if agg.avgDur < 25 or agg.avgDur > 70 then
				durOk = false
			end
			if agg.timeouts > 0 then
				allOk = false
			end
		end
	end
	target("mirror duels are fair (every side-1 win rate within 50 +- 14)", abs(worst - 50) <= 14, fmt("worst %d%%", worst))
	target("equal duels last 25-70 s on average at every tier (compositions differ)", durOk)
	target("no equal duel ever stalls to the time limit", allOk)

	header("Duels: compositions at equal TeamPower (informational: specials and roles decide these; none may be a sure win)")
	local comps = {
		{ "melee trio vs ranged trio", { pet("maple_fox", 10), pet("mallow_kitten", 10), pet("bamboo_panda", 10) }, { pet("puddle_frog", 10), pet("sleepy_owl", 10), pet("pip_penguin", 10) } },
		{ "tanks vs speedsters", { pet("biscuit_bear", 10), pet("bamboo_panda", 10), pet("bubble_axolotl", 10) }, { pet("maple_fox", 10), pet("mallow_kitten", 10), pet("storm_tabby", 10) } },
		{ "3 big vs 4 small of one pet (same power)", { pet("storm_tabby", 20), pet("storm_tabby", 20), pet("storm_tabby", 20) }, { pet("storm_tabby", 12), pet("storm_tabby", 12), pet("storm_tabby", 12), pet("storm_tabby", 12) } },
	}
	local compOk = true
	for _, comp in ipairs(comps) do
		local a, b = balance(comp[2], comp[3])
		local agg = series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, a, { Auto = true }), team(2, 2, b, { Auto = true }) } }
		end, { [1] = "auto", [2] = "auto" }, seeds)
		out(fmt("  %-32s power %4d vs %4d  side1 %3d%%  dur %5.1f s", comp[1], powerOf(a), powerOf(b), agg.winPct, agg.avgDur))
		if agg.winPct < 5 or agg.winPct > 95 then
			compOk = false
		end
	end
	target("no composition is a sure win at equal power (every matchup within 5-95%)", compOk)
end)

-- a copy of a catalog pet with another element (identical stats, special and look): isolates the element effect
local function withElement(petId, element, level)
	local base = PC.Get(petId)
	local def = {}
	for k, v in pairs(base) do
		def[k] = v
	end
	def.Id = petId .. "_" .. element
	def.Element = element
	def.Elements = nil
	return { Key = petId, Def = def, Level = level or 12 }
end

-- 3. elements
section("elements", function(opts)
	header("Elements: the same pets, only the element differs (one counter pet in three: target 60-65%; whole trios)")
	local seeds = opts.seeds
	local function duel(a, b)
		return series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, a, { Auto = true }), team(2, 2, b, { Auto = true }) } }
		end, { [1] = "auto", [2] = "auto" }, seeds * 2)
	end
	local counterOk, mutualOk = true, true
	local counterSum, counterN = 0, 0
	local cases = {
		{ "Water vs Flame", "Water", "Flame" }, { "Flame vs Frost", "Flame", "Frost" }, { "Earth vs Storm", "Earth", "Storm" }, { "Celestial vs Shadow (mutual)", "Celestial", "Shadow" },
	}
	for _, c in ipairs(cases) do
		for _, species in ipairs({ { "storm_tabby", "melee" }, { "frostling_penguin", "ranged" } }) do
			local a = { withElement(species[1], c[2]), withElement("bamboo_panda", "Nature"), withElement("moonlit_owl", "Celestial") }
			local b = { withElement(species[1], c[3]), withElement("bamboo_panda", "Nature"), withElement("moonlit_owl", "Celestial") }
			if c[2] == "Celestial" then
				a[3] = withElement("moonlit_owl", "Earth")
				b[3] = withElement("moonlit_owl", "Earth")
			end
			local agg = duel(a, b)
			out(fmt("  %-30s %-7s counter pet's side wins %3d%%  dur %5.1f s", c[1], species[2], agg.winPct, agg.avgDur))
			if c[1]:find("mutual") then
				if agg.winPct < 35 or agg.winPct > 65 then
					mutualOk = false
				end
			else
				counterSum = counterSum + agg.winPct
				counterN = counterN + 1
				if agg.winPct < 55 or agg.winPct > 75 then
					counterOk = false
				end
			end
		end
	end
	target("one counter pet in three wins ~60-65% on average over the cases (55-75 accepted)", counterSum >= 55 * counterN and counterSum <= 75 * counterN, fmt("mean %d%%", floor(counterSum / max(1, counterN) + 0.5)))
	target("Celestial and Shadow (strong against each other) stay even (35-65%)", mutualOk)
	local trioMin = 100
	for _, c in ipairs({ { "Water trio vs Flame trio", "Water", "Flame" }, { "Nature trio vs Earth trio", "Nature", "Earth" } }) do
		local a = { withElement("storm_tabby", c[2]), withElement("frostling_penguin", c[2]), withElement("bamboo_panda", c[2]) }
		local b = { withElement("storm_tabby", c[3]), withElement("frostling_penguin", c[3]), withElement("bamboo_panda", c[3]) }
		local agg = duel(a, b)
		out(fmt("  %-30s         counter trio wins %3d%%  dur %5.1f s", c[1], agg.winPct, agg.avgDur))
		trioMin = min(trioMin, agg.winPct)
	end
	target("a whole counter trio is clearly favoured (>= 75%)", trioMin >= 75, fmt("min %d%%", trioMin))
	local a, b = balance({ pet("maple_fox", 12), pet("storm_tabby", 12), pet("frostling_penguin", 12) }, { pet("mallow_kitten", 12), pet("bamboo_panda", 12), pet("bubble_axolotl", 12) })
	local agg = duel(a, b)
	out(fmt("  %-30s power %4d vs %4d  side1 %3d%%", "mixed neutral elements", powerOf(a), powerOf(b), agg.winPct))
	out(fmt("  ElementMultiplier Water->Flame %.2f, Flame->Water %.2f, Water->Earth %.2f", PC.ElementMultiplier("Water", "Flame"), PC.ElementMultiplier("Flame", "Water"), PC.ElementMultiplier("Water", "Earth")))
end)

-- 4. trials
section("trials", function(opts)
	header("Trials: win% of each progression stage (scripted player) against levels 1-30")
	local seeds = max(2, floor(opts.seeds / 3))
	local levels = {}
	for lv = 1, BC.TrialCount do
		levels[#levels + 1] = lv
	end
	local head = "  stage      power | "
	for _, lv in ipairs(levels) do
		head = head .. fmt("%3d", lv)
	end
	out(head)
	local clears = {}
	for _, stage in ipairs(SIM.Stages) do
		local row = fmt("  %-10s %5d | ", stage.Id, powerOf(stage.Pets))
		local clear = 0
		local durations = {}
		for _, lv in ipairs(levels) do
			local rec = BC.Trials[lv].RecommendedPower
			local power = powerOf(stage.Pets)
			local winPct
			if power > rec * 2.5 then
				winPct = 100 -- far above: skip the fights (saves minutes)
			elseif power < rec * 0.4 then
				winPct = 0
			else
				local agg = series(function(seed)
					return { Mode = "Trial", Trial = lv, Seed = seed, Teams = { team(1, 1, stage.Pets) } }
				end, { [1] = "player" }, seeds)
				winPct = agg.winPct
				if winPct >= 50 then
					durations[#durations + 1] = agg.avgDur
				end
			end
			if winPct >= 50 and clear == lv - 1 then
				clear = lv
			end
			row = row .. fmt("%3s", winPct >= 100 and " ##" or (winPct <= 0 and "  ." or tostring(winPct)))
		end
		clears[stage.Id] = clear
		out(row .. fmt("  -> clears %d", clear))
	end
	out("  (## = far above the recommended power, . = far below; numbers are win%)")
	local function within(id, lo, hi)
		return clears[id] >= lo and clears[id] <= hi
	end
	local early = within("S1", 1, 4) and within("S2", 2, 7) and within("S3", 4, 10) and within("S4", 6, 12)
	local mid = within("S5", 9, 16) and within("S6", 12, 20)
	local late = clears["S7"] >= 17 and clears["S8"] >= 21 and clears["S9"] >= 26 and clears["S10"] >= 30
	target("early players clear ~1-8 (S1 1-4, S2 2-7, S3 4-10, S4 6-12)", early, fmt("S1 %d S2 %d S3 %d S4 %d", clears.S1, clears.S2, clears.S3, clears.S4))
	target("mid game clears ~10-20 (S5 9-16, S6 12-20)", mid, fmt("S5 %d S6 %d", clears.S5, clears.S6))
	target("prestiged players reach 30 (S7 >= 17, S8 >= 21, S9 >= 26, S10 = 30)", late, fmt("S7 %d S8 %d S9 %d S10 %d", clears.S7, clears.S8, clears.S9, clears.S10))
	local monotonic = true
	local lastClear = 0
	for _, stage in ipairs(SIM.Stages) do
		if clears[stage.Id] < lastClear then
			monotonic = false
		end
		lastClear = max(lastClear, clears[stage.Id])
	end
	target("a stronger stage never clears less than a weaker one", monotonic)

	header("Trials: a team with exactly the recommended power (auto-battle, no commands) is a fair fight")
	local fairOk = true
	local durOk = true
	for _, lv in ipairs({ 2, 4, 7, 9, 12, 14, 17, 19, 22, 24, 27, 29 }) do
		local trial = BC.Trials[lv]
		local mirror = {}
		for i, e in ipairs(trial.Team) do
			mirror[i] = pet(e.PetId, e.Level, e.Tier)
		end
		local agg = series(function(seed)
			return { Mode = "Trial", Trial = lv, Seed = seed, Teams = { team(1, 1, mirror, { Auto = true }) } }
		end, { [1] = "auto" }, opts.seeds)
		local aggPlayer = series(function(seed)
			return { Mode = "Trial", Trial = lv, Seed = seed, Teams = { team(1, 1, mirror) } }
		end, { [1] = "player" }, opts.seeds)
		out(fmt("  trial %2d %-20s rec %4d: mirror auto wins %3d%% (dur %4.1f s), scripted player wins %3d%% (dur %4.1f s), timeouts %d", lv, trial.Name, trial.RecommendedPower, agg.winPct, agg.avgDur, aggPlayer.winPct, aggPlayer.avgDur, agg.timeouts + aggPlayer.timeouts))
		if agg.winPct < 30 or agg.winPct > 70 then
			fairOk = false
		end
		if agg.avgDur < 20 or agg.avgDur > 90 then
			durOk = false
		end
	end
	target("equal-power trial fights are fair (auto mirror within 30-70%)", fairOk)
	target("equal-power trial fights last 20-90 s (Shield + Freeze mirrors are the slow ones)", durOk)

	header("Trials: how steep is the power curve? (mirror of trial 12 / 22 scaled to a power ratio)")
	for _, lv in ipairs({ 12, 22 }) do
		local trial = BC.Trials[lv]
		local base = {}
		for i, e in ipairs(trial.Team) do
			base[i] = pet(e.PetId, e.Level, e.Tier)
		end
		local row = fmt("  trial %2d:", lv)
		for _, ratio in ipairs({ 0.8, 0.9, 1.0, 1.1, 1.2 }) do
			local scaled = atPower(base, trial.RecommendedPower * ratio)
			local agg = series(function(seed)
				return { Mode = "Trial", Trial = lv, Seed = seed, Teams = { team(1, 1, scaled) } }
			end, { [1] = "player" }, seeds)
			row = row .. fmt("  x%.2f (pow %4d) -> %3d%%", ratio, powerOf(scaled), agg.winPct)
		end
		out(row)
	end
end)

-- 5. raids
section("raids", function(opts)
	header("Raids: 1 / 3 / 8 dodging players (scripted) should finish in 2-4 minutes; non-dodgers see several telegraphs")
	local seeds = max(1, floor(opts.seeds / 6))
	-- mixed-element rosters (a whole team of the boss's prey element is a different fight: see the Lava Golem vs Frost)
	local stages = {
		{ Id = "M5", Pets = { pet("aurora_fox", 12), pet("storm_tabby", 14), pet("bamboo_panda", 14) } },
		{ Id = "M8", Pets = { pet("cloudy_dragon", 25), pet("twilight_dragon", 28), pet("ember_phoenix", 26, "Golden"), pet("aurora_fox", 24, "Golden") } },
	}
	local wonCombos, combos, anyBossHit = 0, 0, 0
	local durOk = true
	local durations = {}
	for _, boss in ipairs(BC.BossOrder) do
		for _, stage in ipairs(stages) do
			for _, players in ipairs({ 1, 3, 8 }) do
				local function setup(seed, flags)
					local teams = {}
					for i = 1, players do
						teams[i] = team(100 + i, 1, stage.Pets, flags)
					end
					return { Mode = "Raid", Boss = boss, Seed = seed, Teams = teams }
				end
				local policies = {}
				for i = 1, players do
					policies[100 + i] = "player"
				end
				local agg = series(function(seed)
					return setup(seed, {})
				end, policies, seeds)
				local autoPolicies = {}
				for i = 1, players do
					autoPolicies[100 + i] = "auto"
				end
				local aggAuto = series(function(seed)
					return setup(seed, { Auto = true })
				end, autoPolicies, seeds)
				out(fmt("  %-13s %-4s %dp: dodging win %3d%% dur %5.1f s (dodges %4.1f, KOs %4.1f, maxBossHit %.2f, tele hits %3.1f) | no dodge: win %3d%% dur %5.1f s KOs %4.1f telegraphs seen %4.1f",
					boss, stage.Id, players, agg.winPct, agg.avgDur, agg.dodges / max(1, agg.n), agg.kos / max(1, agg.n), agg.maxBossHit, agg.teleHits / max(1, agg.n),
					aggAuto.winPct, aggAuto.avgDur, aggAuto.kos / max(1, aggAuto.n), aggAuto.telegraphs / max(1, aggAuto.n)))
				combos = combos + 1
				if agg.winPct >= 50 then
					wonCombos = wonCombos + 1
					if agg.avgDur < 100 or agg.avgDur > 240 then
						durOk = false
					end
				end
				durations[#durations + 1] = agg.avgDur
				anyBossHit = max(anyBossHit, agg.maxBossHit)
			end
		end
	end
	target("dodging players win nearly every raid (1/3/8 players, two stages, four bosses: >= 90% of the combos)", wonCombos >= combos * 0.9, fmt("%d of %d", wonCombos, combos))
	target("won raids last 100-240 s", durOk)
	target("no boss hit takes more than 80% of a pet before the enrage (x1.5 element hits included)", anyBossHit <= 0.8, fmt("max %.2f", anyBossHit))

	header("Raids: a mixed group of 8 (stages S3..S9) with the Storm Titan; damage shares")
	local mixed = { SIM.Stages[3], SIM.Stages[5], SIM.Stages[5], SIM.Stages[6], SIM.Stages[7], SIM.Stages[7], SIM.Stages[8], SIM.Stages[9] }
	local teams, policies = {}, {}
	for i, stage in ipairs(mixed) do
		teams[i] = team(200 + i, 1, stage.Pets)
		policies[200 + i] = "player"
	end
	local result, stats = SIM.run({ Mode = "Raid", Boss = "storm_titan", Seed = 11, Teams = teams }, policies)
	out(fmt("  result %s in %.1f s, KOs %d, telegraphs %d", result.Reason, result.Duration, stats.kos, stats.telegraphs))
	local shareOk = true
	for i, stage in ipairs(mixed) do
		local share = result.Shares[200 + i] or 0
		local tier = BC.RaidTier(share, result.WinnerSide == 1)
		out(fmt("    %-4s power %5d  damage share %5.1f%%  tier %-6s  survivors %d", stage.Id, powerOf(stage.Pets), share * 100, tier.Id, result.Survivors[200 + i] or 0))
	end
	if (result.Shares[208] or 0) < (result.Shares[201] or 0) then
		shareOk = false
	end
	target("mixed raid: the strongest team out-damages the weakest and the raid is won", shareOk and result.WinnerSide == 1)

	header("Raids: joining late and leaving (boss HP shares)")
	local b = BS.new({ Mode = "Raid", Boss = "frost_wyrm", Seed = 2, Teams = { team(1, 1, SIM.Stages[5].Pets, { Auto = true }) } })
	local hp0 = b:BossStatus().MaxHp
	for _ = 1, 50 do
		b:Step(0.1)
	end
	b:AddTeam(team(2, 1, SIM.Stages[5].Pets, { Auto = true }))
	local hp1 = b:BossStatus().MaxHp
	for _ = 1, 50 do
		b:Step(0.1)
	end
	b:RemoveTeam(2)
	local hp2 = b:BossStatus().MaxHp
	out(fmt("  boss max HP: 1 player %d -> a second joins %d -> leaves %d", hp0, hp1, hp2))
	target("boss HP grows when a player joins and shrinks back when they leave", hp1 > hp0 * 1.8 and abs(hp2 - hp0) <= hp0 * 0.05)

	header("Raids: joiners who bring nothing (idle alts with level-1 Commons) do not inflate the boss for the real player")
	local alts = {}
	for i = 1, 7 do
		alts[i] = team(400 + i, 1, SIM.Stages[1].Pets, { Auto = true })
	end
	local solo = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 5, Teams = { team(400, 1, SIM.Stages[7].Pets) } })
	local withAlts = { team(400, 1, SIM.Stages[7].Pets) }
	for i = 1, 7 do
		withAlts[#withAlts + 1] = alts[i]
	end
	local crowded = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 5, Teams = withAlts })
	local soloHp, crowdedHp = solo:BossStatus().MaxHp, crowded:BossStatus().MaxHp
	out(fmt("  Storm Titan HP for one S7 team %d, for the same team plus 7 idle alt teams %d (x%.2f); weighted head count %.2f",
		soloHp, crowdedHp, crowdedHp / soloHp, crowded.playerTeamCount or 0))
	target("seven alt teams with level-1 Commons add less than 15% to the boss's HP", crowdedHp <= soloHp * 1.15, fmt("x%.2f", crowdedHp / soloHp))
end)

-- 5b. dodge: does a timely RETREAT get a team out of every telegraph shape?
local function inShape(ev, x, z, radius)
	if ev.shape == "Line" then
		local dx, dz = x - ev.x, z - ev.z
		local dirX, dirZ = math.cos(ev.angle), math.sin(ev.angle)
		local along = dx * dirX + dz * dirZ
		if along < -radius or along > ev.length + radius then
			return false
		end
		return abs(dx * dirZ - dz * dirX) <= ev.width / 2 + radius
	end
	local dx, dz = x - ev.x, z - ev.z
	return dx * dx + dz * dz <= (ev.r + radius) * (ev.r + radius)
end

-- one raid: RETREAT `reaction` seconds after every telegraph that threatens a pet, ATTACK right after it lands;
-- returns per shape { threatened, hit } (pets inside the shape at the warning / still hit at impact)
local function dodgeRun(boss, pets, seed, reaction)
	local b = BS.new({ Mode = "Raid", Boss = boss, Seed = seed, Teams = { team(101, 1, pets) } })
	local radius, mine = {}, {}
	for _, info in ipairs(b:StaticUnits()) do
		radius[info.id] = info.radius
		if info.owner == 101 then
			mine[info.id] = true
		end
	end
	local pending = {}
	local tally = { Line = { threatened = 0, hit = 0 }, Circle = { threatened = 0, hit = 0 } }
	local retreatAt, attackAt = nil, nil
	local steps = 0
	while not b:IsFinished() and steps < 3400 do
		local events = b:Step(0.1)
		steps = steps + 1
		local t = b:Time()
		local snap = b:Snapshot()
		for _, ev in ipairs(events) do
			if ev.type == "Telegraph" then
				local threatened = {}
				local any = false
				for id in pairs(mine) do
					local u = snap.Units[id]
					if u and u.hp > 0 and inShape(ev, u.x, u.z, radius[id] or 2) then
						threatened[id] = true
						any = true
					end
				end
				if any then
					pending[ev.id] = { shape = ev.shape, threatened = threatened, hit = {} }
					local at = t + reaction - 0.1 + 1e-6
					if not retreatAt or at < retreatAt then
						retreatAt = at
					end
					if not attackAt or ev.at + 0.1 > attackAt then
						attackAt = ev.at + 0.1
					end
				end
			elseif ev.type == "Hit" and ev.tele and pending[ev.tele] and mine[ev.to] then
				pending[ev.tele].hit[ev.to] = true
			end
		end
		if retreatAt and t >= retreatAt then
			retreatAt = nil
			b:Command(101, "Retreat")
		end
		if attackAt and t >= attackAt and not retreatAt and b:Command(101, "Attack") then
			attackAt = nil
		end
	end
	for _, p in pairs(pending) do
		local row = tally[p.shape]
		for id in pairs(p.threatened) do
			row.threatened = row.threatened + 1
			if p.hit[id] then
				row.hit = row.hit + 1
			end
		end
	end
	return tally
end

section("dodge", function(opts)
	header("Dodge: share of threatened pets a RETREAT gets out of each telegraph shape (every boss, an M5 team)")
	local seeds = max(2, floor(opts.seeds / 8))
	local pets = { pet("aurora_fox", 12), pet("storm_tabby", 14), pet("bamboo_panda", 14) }
	local escaped = {}
	for _, reaction in ipairs({ 0.1, 0.6, 1.0 }) do
		local total = { Line = { threatened = 0, hit = 0 }, Circle = { threatened = 0, hit = 0 } }
		for _, boss in ipairs(BC.BossOrder) do
			for seed = 1, seeds do
				local tally = dodgeRun(boss, pets, seed, reaction)
				for shape, row in pairs(tally) do
					total[shape].threatened = total[shape].threatened + row.threatened
					total[shape].hit = total[shape].hit + row.hit
				end
			end
		end
		escaped[reaction] = {}
		local parts = {}
		for _, shape in ipairs({ "Line", "Circle" }) do
			local row = total[shape]
			escaped[reaction][shape] = row.threatened > 0 and (row.threatened - row.hit) / row.threatened or 1
			parts[#parts + 1] = fmt("%s %d threatened, %d hit, %d%% escaped", shape, row.threatened, row.hit, floor(escaped[reaction][shape] * 100 + 0.5))
		end
		out(fmt("  RETREAT %.1f s after the warning: %s", reaction, table.concat(parts, "; ")))
	end
	target("a perfect dodger (RETREAT 0.1 s after the warning) escapes >= 85% of Line hits", escaped[0.1].Line >= 0.85, fmt("%d%%", floor(escaped[0.1].Line * 100 + 0.5)))
	target("...and >= 85% of Circle hits", escaped[0.1].Circle >= 0.85, fmt("%d%%", floor(escaped[0.1].Circle * 100 + 0.5)))
	target("a RETREAT 1.0 s after the warning (render delay + ping + run-out of a 2.2 s telegraph) still escapes >= 75% of both shapes",
		escaped[1.0].Line >= 0.75 and escaped[1.0].Circle >= 0.75, fmt("Line %d%%, Circle %d%%", floor(escaped[1.0].Line * 100 + 0.5), floor(escaped[1.0].Circle * 100 + 0.5)))
	local shortest = huge
	for _, boss in ipairs(BC.BossOrder) do
		for _, a in ipairs(BC.Bosses[boss].Attacks) do
			shortest = min(shortest, a.Telegraph)
		end
	end
	target("every boss telegraph lasts at least 2.2 s (the client fills toward the dodge deadline)", shortest >= 2.2, fmt("%.1f s", shortest))
end)

-- 6. specials
section("specials", function(opts)
	header("Specials: one caster (plus two silent fillers) vs the same team that never casts (useful: >= 55%, no auto-win: <= 95%)")
	local seeds = opts.seeds
	local kinds = {
		{ "Blast", "puddle_frog" }, { "Heal", "honey_bunny" }, { "Shield", "biscuit_bear" }, { "Storm", "storm_tabby" },
		{ "Pounce", "mallow_kitten" }, { "Freeze", "frostling_penguin" }, { "Beam", "aurora_fox" },
	}
	local allOk = true
	local results = {}
	for _, k in ipairs(kinds) do
		-- side 1: the caster plus two fillers that never cast; side 2: the same three, nobody casts
		local function roster(casterCasts)
			local list = { pet(k[2], 10), pet("waffle_corgi", 10), pet("mochi_slime", 10) }
			list[1].NoSpecial = not casterCasts
			list[2].NoSpecial = true
			list[3].NoSpecial = true
			return list
		end
		local function withFlags(list)
			local spec = team(1, 1, list, { Auto = true })
			for i, p in ipairs(list) do
				spec.Pets[i].NoSpecial = p.NoSpecial
			end
			return spec
		end
		local agg = series(function(seed)
			local a, b = withFlags(roster(true)), withFlags(roster(false))
			b.Owner, b.Side = 2, 2
			return { Mode = "Duel", Seed = seed, Teams = { a, b } }
		end, { [1] = "auto", [2] = "auto" }, seeds)
		results[k[1]] = agg.winPct
		out(fmt("  %-7s (%-18s) one caster wins %3d%%  dur %5.1f s  specials/fight %.1f  %s", k[1], k[2], agg.winPct, agg.avgDur, agg.specials / max(1, agg.n), BC.Specials[k[1]].Text))
		if agg.winPct < 55 or agg.winPct > 95 then
			allOk = false
		end
	end
	target("every special kind is useful but not an auto-win (one caster among three: 55-95%)", allOk)
	header("Specials: a scripted player (presses SPECIAL) vs an idle auto-battler with the same team")
	local pets = { pet("storm_tabby", 12), pet("frostling_penguin", 12), pet("aurora_fox", 12) }
	local agg = series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, pets), team(2, 2, pets) } }
	end, { [1] = "player", [2] = "idle" }, seeds)
	out(fmt("  pressing the buttons wins %3d%% against an idle twin (dur %.1f s)", agg.winPct, agg.avgDur))
	target("pressing SPECIAL / focusing beats idling with the same team (>= 65%)", agg.winPct >= 65, fmt("%d%%", agg.winPct))
end)

-- 7. extremes
section("extremes", function(opts)
	header("Extremes: sustain vs burst at equal power, one-shots, stalemates")
	local seeds = opts.seeds
	local sustain, burst = balance({ pet("biscuit_bear", 12), pet("bubble_axolotl", 12), pet("moonlit_owl", 12), pet("honey_bunny", 12) }, { pet("maple_fox", 12), pet("mallow_kitten", 12), pet("aurora_fox", 12), pet("ember_phoenix", 12) })
	local agg = series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, sustain, { Auto = true }), team(2, 2, burst, { Auto = true }) } }
	end, { [1] = "auto", [2] = "auto" }, seeds)
	out(fmt("  Shield+Heal sustain team (power %d) vs burst team (power %d): sustain wins %d%%, dur %.1f s, timeouts %d", powerOf(sustain), powerOf(burst), agg.winPct, agg.avgDur, agg.timeouts))
	target("no unkillable sustain build: the Shield+Heal team wins at most 80% and nothing times out", agg.winPct <= 80 and agg.timeouts == 0)
	-- biggest single pet hit across a spread of duels
	local worst = 0
	for _, tier in ipairs({ { pet("stormfang", 50, "Rainbow"), pet("obsidian_phoenix", 50, "Rainbow"), pet("eclipse_dragon", 50, "Rainbow") }, { pet("ember_phoenix", 30), pet("twilight_dragon", 30), pet("sunbeam_bear", 30) }, { pet("mallow_kitten", 1), pet("puddle_frog", 1), pet("biscuit_bear", 1) } }) do
		local agg2 = series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, tier, { Auto = true }), team(2, 2, tier, { Auto = true }) } }
		end, { [1] = "auto", [2] = "auto" }, max(2, floor(seeds / 2)))
		worst = max(worst, agg2.maxPetHit)
	end
	out(fmt("  biggest single pet hit (fraction of the victim's max HP) in same-rarity mirrors: %.2f", worst))
	target("a pet never one-shots a pet of its own rarity: biggest hit <= 60% of max HP", worst <= 0.6, fmt("%.2f", worst))
	-- a huge power gap is still a fast, clean result (no stalemate)
	local result = SIM.run({ Mode = "Duel", Seed = 1, Teams = { team(1, 1, { pet("stormfang", 50, "Rainbow") }, { Auto = true }), team(2, 2, { pet("mallow_kitten", 1) }, { Auto = true }) } }, { [1] = "auto", [2] = "auto" })
	out(fmt("  maxed Stormfang vs a level-1 kitten: %s in %.1f s", result.Reason, result.Duration))
	target("a hopeless mismatch ends quickly (< 15 s)", result.Duration < 15 and result.WinnerSide == 1)
	-- retreat is not a stall: a player team that RETREATs and never presses ATTACK returns to the fight by itself
	-- (Damage.RetreatLock + RetreatAutoResume after the RETREAT, once every pet is parked), so the duel still ends
	local b = BS.new({ Mode = "Duel", Seed = 4, Teams = { team(1, 1, { pet("biscuit_bear", 10), pet("bubble_axolotl", 10), pet("moonlit_owl", 10) }), team(2, 2, { pet("biscuit_bear", 10), pet("bubble_axolotl", 10), pet("moonlit_owl", 10) }, { Auto = true }) } })
	b:Command(1, "Retreat")
	local steps = 0
	local resumedAt = nil
	while not b:IsFinished() and steps < 2000 do
		for _, ev in ipairs(b:Step(0.1)) do
			if ev.type == "Order" and ev.owner == 1 and ev.order == "Attack" and ev.auto and not resumedAt then
				resumedAt = b:Time()
			end
		end
		steps = steps + 1
	end
	local r = b:Result()
	local D = BC.Damage
	out(fmt("  a team that only RETREATs: back to ATTACK by itself at %s s (lock %.1f + %.1f), %s, winner side %s after %.1f s", tostring(resumedAt), D.RetreatLock, D.RetreatAutoResume, r.Reason, tostring(r.WinnerSide), r.Duration))
	target("a retreating player team resumes attacking by itself after the lock + RetreatAutoResume (no stall, no timeout)",
		resumedAt ~= nil and resumedAt >= D.RetreatLock + D.RetreatAutoResume and resumedAt <= D.RetreatLock + D.RetreatAutoResume + 4 and r.Reason ~= "Timeout")
	-- an Npc / Auto team keeps its order: hiding forever still loses
	local hide = BS.new({ Mode = "Duel", Seed = 4, Teams = { team(1, 1, { pet("biscuit_bear", 10), pet("bubble_axolotl", 10), pet("moonlit_owl", 10) }, { Auto = true }), team(2, 2, { pet("biscuit_bear", 10), pet("bubble_axolotl", 10), pet("moonlit_owl", 10) }, { Auto = true }) } })
	hide:Command(1, "Retreat")
	steps = 0
	while not hide:IsFinished() and steps < 2000 do
		hide:Step(0.1)
		steps = steps + 1
	end
	local rh = hide:Result()
	out(fmt("  an Auto team that retreats forever: %s, winner side %s after %.1f s", rh.Reason, tostring(rh.WinnerSide), rh.Duration))
	target("retreating forever loses (no stall)", rh.WinnerSide == 2)
end)

-- 8. performance
section("perf", function(opts)
	header("Performance: a raid of 8 teams x 4 pets + boss + minion waves at 10 Hz (Step + Snapshot)")
	local teams, policies = {}, {}
	for i = 1, 8 do
		teams[i] = team(300 + i, 1, SIM.Stages[7].Pets, { Auto = true })
		policies[300 + i] = "auto"
	end
	local b = BS.new({ Mode = "Raid", Boss = "shadow_hydra", Seed = 9, Teams = teams })
	local steps, events, units = 0, 0, 0
	local t0 = clock()
	while not b:IsFinished() and steps < 4000 do
		local evs = b:Step(0.1)
		events = events + #evs
		b:Snapshot()
		steps = steps + 1
	end
	local seconds = clock() - t0
	units = #b:StaticUnits()
	local ms = seconds / max(1, steps) * 1000
	out(fmt("  %d steps, %d units at the end, %.1f events/step, %.3f ms per step (%s after %.1f s)", steps, units, events / max(1, steps), ms, b:Result() and b:Result().Reason or "unfinished", b:Time()))
	target("a full raid steps in well under 1 ms (LuaJIT; Luau is a few times slower)", ms < 0.4, fmt("%.3f ms", ms))
	-- snapshot size: the full picture vs the wire form (SnapshotDelta: only what changed since the last one)
	local snap = b:Snapshot()
	local n, fields = 0, 0
	for _, u in pairs(snap.Units) do
		n = n + 1
		for _ in pairs(u) do
			fields = fields + 1
		end
	end
	local last = {}
	local full = #b:SnapshotDelta(last).U
	b:Step(0.1)
	local delta = #b:SnapshotDelta(last).U
	out(fmt("  snapshot: %d units, %.1f fields per unit; wire form: %d numbers for the full picture, %d one step later", n, fields / max(1, n), full, delta))
	target("the wire snapshot of a step is well under 4 numbers per unit", delta <= 4 * max(1, n), fmt("%d numbers for %d units", delta, n))
end)

----------------------------------------------------------------------
-- Phase 4 helpers: trained / evolved copies, the ring runs, the duel practice gap
----------------------------------------------------------------------
local P4 = {}

function P4.ranks(r)
	return { Speed = r, Physique = r, Ability = r, Defense = r }
end

-- copies of `pets` with Train (a ranks table or nil), Evo (0..2 or nil) and a level override (nil = keep)
function P4.trained(pets, ranks, evo, level)
	local list = {}
	for i, p in ipairs(pets) do
		local e = copyEntry(p)
		e.Train = ranks
		e.Evo = evo
		if level then
			e.Level = level
		end
		list[i] = e
	end
	return list
end

function P4.median(list)
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

function P4.mean(list)
	local s = 0
	for _, v in ipairs(list) do
		s = s + v
	end
	return #list > 0 and s / #list or 0
end

-- every team pet can reach the second evolution (Epic and rarer)
function P4.allTwice(pets)
	for _, p in ipairs(pets) do
		if not PC.MaxEvolution or PC.MaxEvolution(p.Key) < 2 then
			return false
		end
	end
	return true
end

-- the practice-duel factor of BattleService (C.DUEL_POWER_GAP), read from its source; 3 if it cannot be found
function P4.duelGap()
	for _, root in ipairs({ ".", "..", "nimbus-climb" }) do
		local src = readFile(root .. "/src/server/Services/BattleService.lua")
		if src then
			local v = tonumber(src:match("DUEL_POWER_GAP%s*=%s*([%d%.]+)"))
			if v then
				return v
			end
		end
	end
	return 3
end

-- one Champion Ring round: the player's team (scripted player) vs ChampionTeam(round, runSeed)
function P4.ringFight(pets, round, runSeed, battleSeed)
	local setup = { Mode = "Ring", Seed = battleSeed, Round = round, Teams = { team(77, 1, pets), BC.ChampionTeam(round, runSeed) } }
	return SIM.run(setup, { [77] = "player" })
end

-- one ring run from round 1 (fresh HP every round) -> record, { fight durations }, total seconds incl. intermissions
function P4.ringRun(pets, runSeed, maxRound)
	local r, total = 1, 0
	local durations = {}
	local intermission = BC.Ring.Intermission or 3
	while r <= (maxRound or 150) do
		local res = P4.ringFight(pets, r, runSeed, runSeed * 13 + r)
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

-- the level-1 Commons / Uncommons a new player can roll
function P4.starters()
	local list = {}
	for _, def in ipairs(PC.Pets) do
		local rollable = (PC.IsRollable and PC.IsRollable(def.Id)) or (not PC.IsRollable and def.EventOnly ~= true)
		if rollable and (def.Rarity == "Common" or def.Rarity == "Uncommon") then
			list[#list + 1] = def.Id
		end
	end
	return list
end

-- 9. training + evolution (Phase 4)
section("training", function(opts)
	header("Training + evolution (Phase 4, 3.6 / 3.7): TeamPower of each stage with all four skills trained / evolved")
	out(fmt("  %-4s %-11s %6s | %-15s | %-15s | %-15s | %-15s | %s", "", "", "power", "all ranks 5", "all ranks 10", "Evolved I", "Evolved II", "Evolved II + rank 10"))
	local r5lo, r5hi, r10lo, r10hi = huge, 0, huge, 0
	local e1lo, e1hi, e2lo, e2hi = huge, 0, huge, 0
	for _, st in ipairs(SIM.Stages) do
		local base = powerOf(st.Pets)
		local r5 = powerOf(P4.trained(st.Pets, P4.ranks(5)))
		local r10 = powerOf(P4.trained(st.Pets, P4.ranks(10)))
		local e1 = powerOf(P4.trained(st.Pets, nil, 1))
		local e2 = powerOf(P4.trained(st.Pets, nil, 2))
		local both = powerOf(P4.trained(st.Pets, P4.ranks(10), 2))
		local twice = P4.allTwice(st.Pets)
		out(fmt("  %-4s %-11s %6d | %6d (x%.2f) | %6d (x%.2f) | %6d (x%.2f) | %6d (x%.2f)%s | %6d (x%.2f)", st.Id, st.Name, base, r5, r5 / base, r10, r10 / base, e1, e1 / base, e2, e2 / base, twice and " " or "*", both, both / base))
		r5lo, r5hi = min(r5lo, r5 / base), max(r5hi, r5 / base)
		r10lo, r10hi = min(r10lo, r10 / base), max(r10hi, r10 / base)
		-- the tiny Day-1 numbers round to whole powers: the evolution ratio is judged from the first week on
		if base >= 40 then
			e1lo, e1hi = min(e1lo, e1 / base), max(e1hi, e1 / base)
			if twice then
				e2lo, e2hi = min(e2lo, e2 / base), max(e2hi, e2 / base)
			end
		end
	end
	out("  (* = not every pet of the team evolves twice: Common / Uncommon / Rare stop at Evolved I)")
	target("all four skills at rank 5: x1.25-1.4 TeamPower at every stage", r5lo >= 1.25 and r5hi <= 1.4, fmt("x%.2f .. x%.2f", r5lo, r5hi))
	target("all four skills at rank 10: x1.6-1.85 TeamPower at every stage", r10lo >= 1.6 and r10hi <= 1.85, fmt("x%.2f .. x%.2f", r10lo, r10hi))
	target("Evolved I is x1.25 and Evolved II x1.5 TeamPower (+-0.03)", e1lo >= 1.22 and e1hi <= 1.28 and e2lo >= 1.47 and e2hi <= 1.53, fmt("I x%.2f .. x%.2f, II x%.2f .. x%.2f", e1lo, e1hi, e2lo, e2hi))
	local us0 = BC.UnitStats("storm_tabby", 10)
	local us1 = BC.UnitStats("storm_tabby", 10, nil, { Train = P4.ranks(10) })
	out(fmt("  storm_tabby L10 rank 10: interval %.2f -> %.2f s, max HP %d -> %d, special %d -> %d, damage taken x%.2f, meter x%.2f", us0.Interval, us1.Interval, us0.MaxHp, us1.MaxHp, us0.SpecialPower, us1.SpecialPower, 1 - us1.Defense, us1.MeterRate))

	header("Training: trained mirror duels (scripted players both sides): fair, no draws, no timeouts")
	local mirrorOk, worst = true, 50
	for _, idx in ipairs({ 3, 5, 7, 9 }) do
		local st = SIM.Stages[idx]
		for _, case in ipairs({ { "untrained", nil, nil }, { "rank 5", P4.ranks(5), 1 }, { "rank 10 + Evolved II", P4.ranks(10), 2 } }) do
			local pets = P4.trained(st.Pets, case[2], case[3])
			local agg = series(function(seed)
				return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, pets), team(2, 2, pets) } }
			end, { [1] = "player", [2] = "player" }, opts.seeds)
			out(fmt("  %-4s %-22s side1 %3d%%  draws %d  timeouts %d  dur %5.1f s  maxHit %.2f", st.Id, case[1], agg.winPct, agg.draws, agg.timeouts, agg.avgDur, agg.maxPetHit))
			if case[2] then
				if abs(agg.winPct - 50) > abs(worst - 50) then
					worst = agg.winPct
				end
				if agg.winPct < 35 or agg.winPct > 65 or agg.draws > 0 or agg.timeouts > 0 then
					mirrorOk = false
				end
			end
		end
	end
	target("trained mirror duels are fair (35-65%) with no draws and no timeouts", mirrorOk, fmt("worst %d%%", worst))
	local st5 = SIM.Stages[5]
	for _, r in ipairs({ 2, 5, 10 }) do
		local agg = series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, P4.trained(st5.Pets, P4.ranks(r))), team(2, 2, st5.Pets) } }
		end, { [1] = "player", [2] = "player" }, max(8, floor(opts.seeds / 2)))
		out(fmt("  S5 all ranks %2d vs the same team untrained: trained wins %3d%%  dur %5.1f s", r, agg.winPct, agg.avgDur))
	end

	header("Training: a trained + evolved team (S7, rank 10, Evolved II) vs every boss with 1 / 3 dodging players")
	local seeds = max(1, floor(opts.seeds / 8))
	local pets7 = P4.trained(SIM.Stages[7].Pets, P4.ranks(10), 2)
	local won, combos, durOk, bossHit = 0, 0, true, 0
	for _, boss in ipairs(BC.BossOrder) do
		for _, players in ipairs({ 1, 3 }) do
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
	target("a trained team still wins its raids by dodging (>= 90% of the combos) in 100-240 s", won >= combos * 0.9 and durOk, fmt("%d of %d won", won, combos))
	target("no boss hit takes more than 80% of a trained pet", bossHit <= 0.8, fmt("max %.2f", bossHit))
end)

-- 10. the Champion Ring (Phase 4)
section("ring", function(opts)
	local R = BC.Ring
	header(fmt("Champion Ring (3.8): single level-1 pets vs the first rounds (scripted player; FirstPower %.2f, Growth %.2f)", R.FirstPower, R.Growth))
	local seeds1 = opts.quick and 24 or 48
	local starters = P4.starters()
	local NR = 8
	local worst, avg = {}, {}
	for r = 1, NR do
		worst[r], avg[r] = 100, 0
	end
	for _, id in ipairs(starters) do
		local row = {}
		for r = 1, NR do
			local wins, dur = 0, 0
			for seed = 1, seeds1 do
				local res = P4.ringFight({ pet(id, 1) }, r, seed, seed * 7 + r)
				if res and res.WinnerSide == 1 then
					wins = wins + 1
				end
				dur = dur + (res and res.Duration or 0)
			end
			local p = pct(wins, seeds1)
			worst[r] = min(worst[r], p)
			avg[r] = avg[r] + p / #starters
			row[#row + 1] = fmt("r%d %3d%%/%2.0fs", r, p, dur / seeds1)
		end
		out(fmt("  %-15s %s", id, table.concat(row, " ")))
	end
	local w, a = {}, {}
	for r = 1, NR do
		w[#w + 1] = fmt("r%d %d%%", r, worst[r])
		a[#a + 1] = fmt("r%d %.0f%%", r, avg[r])
	end
	out("  worst single pet: " .. table.concat(w, "  "))
	out("  average        : " .. table.concat(a, "  "))
	target(fmt("rounds 1-3 are won >= 95%% by EVERY single level-1 rollable Common / Uncommon (%d pets, %d seeds)", #starters, seeds1), worst[1] >= 95 and worst[2] >= 95 and worst[3] >= 95, fmt("worst r1 %d%%, r2 %d%%, r3 %d%%", worst[1], worst[2], worst[3]))
	target("the single-pet average stays >= 85% at rounds 4-5 and >= 50% at round 8 (no cliff)", avg[4] >= 85 and avg[5] >= 85 and avg[8] >= 50, fmt("r4 %.0f%%, r5 %.0f%%, r8 %.0f%%", avg[4], avg[5], avg[8]))

	header("Champion Ring: the record (the last round won, fresh HP every round) per progression stage")
	local seeds2 = opts.quick and 8 or 16
	local medians, fightOk, lastMedian, monotonic = {}, true, -1, true
	local runMinutes = {}
	for _, st in ipairs(SIM.Stages) do
		local records, durs, totals = {}, {}, {}
		for seed = 1, seeds2 do
			local rec, d, total = P4.ringRun(st.Pets, 1000 + seed)
			records[#records + 1] = rec
			for _, x in ipairs(d) do
				durs[#durs + 1] = x
			end
			totals[#totals + 1] = total
		end
		local med = P4.median(records)
		medians[st.Id] = med
		local avgFight = P4.mean(durs)
		runMinutes[st.Id] = P4.mean(totals) / 60
		table.sort(records)
		local xp = 0
		for r = 1, med do
			xp = xp + BC.RingRewards(r, 0, false).Xp
		end
		out(fmt("  %-4s %-11s power %6d  record median %3d (min %d, max %d)  avg fight %4.1f s  run %4.1f min  XP per pet %5d", st.Id, st.Name, powerOf(st.Pets), med, records[1], records[#records], avgFight, runMinutes[st.Id], xp))
		if avgFight < 4 or avgFight > 40 then
			fightOk = false
		end
		if med < lastMedian then
			monotonic = false
		end
		lastMedian = max(lastMedian, med)
	end
	local function within(id, lo, hi)
		return medians[id] >= lo and medians[id] <= hi
	end
	target("median records: S1 13-19, S3 20-26, S5 25-31, S7 33-39, S9 41-47, S10 48-54", within("S1", 13, 19) and within("S3", 20, 26) and within("S5", 25, 31) and within("S7", 33, 39) and within("S9", 41, 47) and within("S10", 48, 54),
		fmt("S1 %d S3 %d S5 %d S7 %d S9 %d S10 %d", medians.S1, medians.S3, medians.S5, medians.S7, medians.S9, medians.S10))
	target("the record never falls with the stage", monotonic)
	target("ring fights last 4-40 s on average at every stage", fightOk)

	header("Champion Ring: the ladder (power never drops, never ends; Boost past the level-50 Rainbow boss)")
	local mono, firstBoost, lateOk = true, {}, true
	for seed = 1, 60 do
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
			if r >= 52 and not (boost and boost > 1) then
				lateOk = false
			end
		end
		firstBoost[#firstBoost + 1] = first or 999
	end
	table.sort(firstBoost)
	local medBoost = P4.median(firstBoost)
	local p120, p100 = BC.RingPower(120, 1), BC.RingPower(100, 1)
	target("the champion's power never drops from a round to the next (rounds 3-120, 60 seeds)", mono)
	target("no ceiling: round 120 is stronger than round 100", p120 > p100, fmt("%.0f vs %.0f", p120, p100))
	target("Boost > 1 starts at rounds 40-50 (median first boosted round) and every champion from round 52 on is boosted", medBoost >= 40 and medBoost <= 50 and lateOk, fmt("first boosted round: min %d, median %d, max %d", firstBoost[1], medBoost, firstBoost[#firstBoost]))
	for _, r in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 100, 120 }) do
		local spec = BC.ChampionTeam(r, 1)
		local e = spec.Pets[1]
		local rw = BC.RingRewards(r, 300, false)
		out(fmt("  round %3d  target %10.1f  power %10.1f  %-18s L%-2d %-7s%s%s%s   win: $%d at 300/s ($%d floor), %d XP", r, BC.RingTarget(r), spec.Power, e.PetId, e.Level, e.Tier, e.Boss and " BOSS" or "", e.Boost and fmt(" x%.2f", e.Boost) or "", e.Handicap and fmt(" h%.2f", e.Handicap) or "", rw.Cash, rw.Floor, rw.Xp))
	end
end)

-- 11. the level-100 stage (the player's later rule: pets level up to 100; champions keep their level-50 ladder)
section("level100", function(opts)
	header("Level 100 (the player's rule): the S10 pets at level 100, Evolved II, every skill at rank 10")
	local s10 = SIM.Stages[10].Pets
	local l100 = P4.trained(s10, nil, nil, 100)
	local l100max = P4.trained(s10, P4.ranks(10), 2, 100)
	local s10max = P4.trained(s10, P4.ranks(10), 2)
	local gap = P4.duelGap()
	local p50, p50max, p100, p100max = powerOf(s10), powerOf(s10max), powerOf(l100), powerOf(l100max)
	out(fmt("  TeamPower: S10 (L45-50 Rainbow) %d, S10 trained + evolved %d, the same pets at L100 %d, L100 trained + evolved %d (x%.2f of S10)", p50, p50max, p100, p100max, p100max / p50))
	out(fmt("  BattleService practice rule: a duel whose powers differ by more than x%.1f pays nothing", gap))
	out(fmt("    L100 maxed vs S10: x%.2f (%s); L100 maxed vs S10 maxed: x%.2f (%s); L100 vs S10, both untrained: x%.2f (%s)", p100max / p50, p100max > p50 * gap and "practice" or "ranked",
		p100max / p50max, p100max > p50max * gap and "practice" or "ranked", p100 / p50, p100 > p50 * gap and "practice" or "ranked"))
	target("the duel practice gap catches a maxed L100 team vs an L50 team (S10)", p100max > p50 * gap, fmt("x%.2f > x%.1f", p100max / p50, gap))
	local agg = series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, l100max), team(2, 2, s10) } }
	end, { [1] = "player", [2] = "player" }, max(8, floor(opts.seeds / 4)))
	out(fmt("  L100 maxed vs S10 (L50): L100 wins %3d%%  dur %5.1f s  maxHit %.2f", agg.winPct, agg.avgDur, agg.maxPetHit))

	header("Level 100: mirror duels (fair, no draws / timeouts, no one-shots)")
	local mirrorOk, hitMax, worst = true, 0, 50
	local builds = {
		{ "untrained L100", l100 },
		{ "L100 rank 10 + Evolved II", l100max },
		{ "L100 attack build (Speed + Ability 10, Evolved II)", P4.trained(s10, { Speed = 10, Ability = 10 }, 2, 100) },
	}
	for _, b in ipairs(builds) do
		local m = series(function(seed)
			return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, b[2]), team(2, 2, b[2]) } }
		end, { [1] = "player", [2] = "player" }, opts.seeds)
		out(fmt("  %-52s side1 %3d%%  draws %d  timeouts %d  dur %5.1f s  maxHit %.2f", b[1], m.winPct, m.draws, m.timeouts, m.avgDur, m.maxPetHit))
		hitMax = max(hitMax, m.maxPetHit)
		if abs(m.winPct - 50) > abs(worst - 50) then
			worst = m.winPct
		end
		if m.winPct < 35 or m.winPct > 65 or m.draws > 0 or m.timeouts > 0 then
			mirrorOk = false
		end
	end
	local glass = series(function(seed)
		return { Mode = "Duel", Seed = seed, Teams = { team(1, 1, P4.trained(s10, { Speed = 10, Ability = 10 }, 2, 100)), team(2, 2, l100) } }
	end, { [1] = "player", [2] = "player" }, max(8, floor(opts.seeds / 2)))
	out(fmt("  %-52s attack build wins %3d%%  dur %5.1f s  maxHit %.2f", "L100 attack build vs the same pets untrained", glass.winPct, glass.avgDur, glass.maxPetHit))
	target("L100 trained mirror duels are fair (35-65%) with no draws and no timeouts", mirrorOk, fmt("worst %d%%", worst))
	local cap = (type(BC.Damage.MaxHit) == "table" and BC.Damage.MaxHit.Share) or 1
	local worstHit = max(hitMax, glass.maxPetHit, agg.maxPetHit)
	target(fmt("no one-shot builds at level 100: no duel hit takes more than %d%% of a pet (mirrors, the attack build, L100 vs L50)", floor(cap * 100 + 0.5)), worstHit <= cap + 0.005 and worstHit < 1,
		fmt("mirrors %.2f, attack build vs untrained %.2f, L100 vs L50 %.2f", hitMax, glass.maxPetHit, agg.maxPetHit))

	header("Level 100: the maxed L100 team vs every boss with 1 / 3 dodging players")
	local seeds = max(1, floor(opts.seeds / 8))
	local won, combos, durOk, bossHit = 0, 0, true, 0
	for _, boss in ipairs(BC.BossOrder) do
		for _, players in ipairs({ 1, 3 }) do
			local policies = {}
			for i = 1, players do
				policies[600 + i] = "player"
			end
			local raid = series(function(seed)
				local teams = {}
				for i = 1, players do
					teams[i] = team(600 + i, 1, l100max)
				end
				return { Mode = "Raid", Boss = boss, Seed = seed, Teams = teams }
			end, policies, seeds)
			out(fmt("  %-13s %dp: win %3d%% dur %5.1f s (dodges %4.1f, KOs %4.1f, maxBossHit %.2f)", boss, players, raid.winPct, raid.avgDur, raid.dodges / max(1, raid.n), raid.kos / max(1, raid.n), raid.maxBossHit))
			combos = combos + 1
			bossHit = max(bossHit, raid.maxBossHit)
			if raid.winPct >= 50 then
				won = won + 1
				if raid.avgDur < 100 or raid.avgDur > 240 then
					durOk = false
				end
			end
		end
	end
	target("a maxed L100 team still wins its raids by dodging (>= 90% of the combos) in 100-240 s", won >= combos * 0.9 and durOk, fmt("%d of %d won", won, combos))
	target("no boss hit takes more than 80% of a maxed L100 pet", bossHit <= 0.8, fmt("max %.2f", bossHit))
	local records = {}
	for seed = 1, opts.quick and 4 or 8 do
		records[#records + 1] = P4.ringRun(l100max, 2000 + seed)
	end
	out(fmt("  Champion Ring record of the maxed L100 team: median %d (the champions stop at level 50 and grow by Boost)", P4.median(records)))
end)

-- 12. progression reference
section("progression", function(opts)
	local feedShare = (type(TC.FeedShare) == "table" and TC.FeedShare[1]) or 0.25
	header(fmt("Progression reference: pet XP behind each stage (TycoonCatalog.XpToNext) and its Food Machine price (machine level 1: %d%% of a bar per feed)", floor(feedShare * 100 + 0.5)))
	local Config = require(Shared.Config)
	-- one machine feed's price: TycoonCatalog.FeedPrice, else the contract formula XpToNext x RarityScale x FeedBase
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
	-- Cash to grow a pet from level `from` to `to` with machine feeds (fractional feeds: leftover XP carries over)
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
	local xp100, cash100 = 0, 0
	for _, p in ipairs(SIM.Stages[10].Pets) do
		xp100 = xp100 + TC.XpForLevel(100) - TC.XpForLevel(p.Level)
		cash100 = cash100 + cashFor(p.Key, p.Level, 100)
	end
	out(fmt("  L100 the S10 pets from their levels to 100: team XP %d, Food Machine %s (or ring rounds: round 50 pays %d XP per pet)", xp100, fmtCash(cash100), BC.RingRewards(50, 0, false).Xp))
	out("  trial ladder: " .. (function()
		local parts = {}
		for lv = 1, BC.TrialCount, 1 do
			local t = BC.Trials[lv]
			parts[#parts + 1] = fmt("%d:%d(L%d%s)", lv, t.RecommendedPower, t.PetLevel, t.Tier ~= "Normal" and (" " .. t.Tier) or "")
		end
		return table.concat(parts, " ")
	end)())
	local ok, problems = BC.Validate()
	target("BattleCatalog.Validate() passes", ok, table.concat(problems, "; "))
end)

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------
function SIM.main(argString)
	local opts = parseArgs(argString)
	if opts.seeds == nil then
		opts.seeds = opts.quick and 32 or 100
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
SIM.powerOf = powerOf
SIM.atPower = atPower
SIM.series = series

if SIM_BATTLE_LIBRARY then
	return SIM
end

return SIM.main(os.getenv and os.getenv("SIM_BATTLE") or SIM_BATTLE_ARGS or "")
