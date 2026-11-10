-- tools/sim_measure.lua: instrumented raid cells on the REAL modules, read-only (the feel-balance fit, 2026-11-10).
-- Run from the repo root: py -3.12 tools/sim_measure.py "raid <boss> <tier> <players> <seeds> <standoff> <on|off>[;...]"
-- (standoff overrides BattleCatalog.Damage.Standoff for the run, on|off the real cast). Globals in: SIM, MEASURE_ARGS.
local Shared = Mock.GetPath(ROOTS.shared)
local BC = require(Shared.BattleCatalog)
local BS = require(Shared.BattleSim)
local Config = require(Shared.Config)
local DT = 0.1
local fmt, sqrt, floor, max = string.format, math.sqrt, math.floor, math.max
local lines = {}
local function out(s)
	lines[#lines + 1] = s
end

local function newAgg()
	return { n = 0, wins = 0, dur = 0, tele = {}, teleHit = {}, teleMiss = {}, lethal = 0, zone = 0, basic = 0, minion = 0, dmgIn = 0, kos = 0,
		elem = 0, elemWhiff = 0, elemBoss = 0, specials = 0, casts = 0, breaks = 0, dmgOut = 0, dmgElem = 0, plainHits = 0,
		cls = { melee = { steps = 0, moving = 0, stunned = 0, out = 0, inBasic = 0, inTele = 0, inMinion = 0, inZone = 0, kos = 0, hits = 0, elem = 0 }, ranged = { steps = 0, moving = 0, stunned = 0, out = 0, inBasic = 0, inTele = 0, inMinion = 0, inZone = 0, kos = 0, hits = 0, elem = 0 } }, sMelee = 0, dMelee = 0, sRanged = 0, dRanged = 0, pairs = 0, pairD = 0, pairNear = 0, fsteps = 0, fsum = 0, dodges = 0, timeouts = 0, specDmg = 0 }
end

local function runOne(setup, owners, playerOpts, A)
	local b = BS.new(setup)
	local players = {}
	for _, owner in ipairs(owners) do
		players[#players + 1] = SIM.Player.new(b, owner, (setup.Seed or 1) * 31 + owner, playerOpts)
	end
	table.sort(players, function(a, c)
		return tostring(a.owner) < tostring(c.owner)
	end)
	local kindOf, sideOf, clsOf = {}, {}, {}
	for _, info in ipairs(b:StaticUnits()) do
		kindOf[info.id], sideOf[info.id] = info.kind, info.side
		clsOf[info.id] = info.ranged and "ranged" or "melee"
	end
	local steps = 0
	local maxSteps = floor((b.timeLimit + 5) / DT) + 10
	local specialNow = {}
	while not b:IsFinished() and steps < maxSteps do
		local events = b:Step(DT)
		steps = steps + 1
		for _, ev in ipairs(events) do
			if ev.type == "Spawn" or ev.type == "Wave" then
				for _, info in ipairs(ev.units) do
					kindOf[info.id], sideOf[info.id] = info.kind, info.side
				end
			end
		end
		for k in pairs(specialNow) do
			specialNow[k] = nil
		end
		for _, ev in ipairs(events) do
			local t = ev.type
			if t == "Special" and sideOf[ev.unit] == 1 then
				A.specials = A.specials + 1
			end
		end
		for _, ev in ipairs(events) do
			local t = ev.type
			if t == "Hit" then
				local fromBoss = ev.from and kindOf[ev.from] == "Boss"
				if sideOf[ev.to] == 1 then
					if ev.miss then
						if ev.tele then
							local k = ev.attack or "?"
							A.teleMiss[k] = (A.teleMiss[k] or 0) + 1
						end
					elseif ev.lethal then
						A.lethal = A.lethal + 1
					elseif ev.tele then
						local k = ev.attack or "?"
						A.teleHit[k] = (A.teleHit[k] or 0) + 1
						A.dmgIn = A.dmgIn + ev.dmg
						A.cls[clsOf[ev.to]].inTele = A.cls[clsOf[ev.to]].inTele + ev.dmg
					elseif ev.zone then
						A.zone = A.zone + 1
						A.dmgIn = A.dmgIn + ev.dmg
						A.cls[clsOf[ev.to]].inZone = A.cls[clsOf[ev.to]].inZone + ev.dmg
					elseif fromBoss then
						A.basic = A.basic + 1
						A.dmgIn = A.dmgIn + ev.dmg
						A.cls[clsOf[ev.to]].inBasic = A.cls[clsOf[ev.to]].inBasic + ev.dmg
					else
						A.minion = A.minion + 1
						A.dmgIn = A.dmgIn + ev.dmg
						A.cls[clsOf[ev.to]].inMinion = A.cls[clsOf[ev.to]].inMinion + ev.dmg
					end
				elseif ev.from and sideOf[ev.from] == 1 and not ev.miss then
					A.dmgOut = A.dmgOut + ev.dmg
					local c = A.cls[clsOf[ev.from] or "ranged"]
					c.out = c.out + ev.dmg
					if ev.element then
						c.elem = c.elem + ev.dmg
					elseif not (ev.special or ev.kind) then
						c.hits = c.hits + 1
					end
					if ev.element then
						A.dmgElem = A.dmgElem + ev.dmg
					elseif ev.special or ev.kind then
						A.specDmg = A.specDmg + ev.dmg
					else
						A.plainHits = A.plainHits + 1
					end
				end
			elseif t == "Telegraph" then
				local k = ev.attack or "?"
				A.tele[k] = (A.tele[k] or 0) + 1
			elseif t == "Element" and sideOf[ev.unit] == 1 then
				A.elem = A.elem + 1
				local n, boss = 0, false
				for _, id in ipairs(ev.targets or {}) do
					n = n + 1
					if kindOf[id] == "Boss" then
						boss = true
					end
				end
				if n == 0 then
					A.elemWhiff = A.elemWhiff + 1
				end
				if boss then
					A.elemBoss = A.elemBoss + 1
				end
			elseif t == "Cast" and sideOf[ev.unit] == 1 then
				A.casts = A.casts + 1
			elseif t == "CastBreak" and sideOf[ev.unit] == 1 then
				A.breaks = A.breaks + 1
			elseif t == "KO" and sideOf[ev.unit] == 1 then
				A.kos = A.kos + 1
				A.cls[clsOf[ev.unit]].kos = A.cls[clsOf[ev.unit]].kos + 1
			end
		end
		-- positions: the player fighters on the floor
		local boss = b.boss
		local fl = {}
		for _, u in ipairs(b.units) do
			if u.side == 1 and u.alive and not u.gone and not u.benched and u.team and u.team.player and u == u.team.fighter then
				fl[#fl + 1] = u
				local c = A.cls[u.ranged and "ranged" or "melee"]
				c.steps = c.steps + 1
				if u.state == 1 then
					c.moving = c.moving + 1
				elseif u.state == 6 then
					c.stunned = c.stunned + 1
				end
			end
		end
		if boss and boss.alive and steps > 80 then -- after the walk in
			A.fsteps = A.fsteps + 1
			A.fsum = A.fsum + #fl
			for i, u in ipairs(fl) do
				local d = sqrt((u.x - boss.x) ^ 2 + (u.z - boss.z) ^ 2)
				if u.ranged then
					A.sRanged, A.dRanged = A.sRanged + 1, A.dRanged + d
				else
					A.sMelee, A.dMelee = A.sMelee + 1, A.dMelee + d
				end
				for j = i + 1, #fl do
					local v = fl[j]
					local pd = sqrt((u.x - v.x) ^ 2 + (u.z - v.z) ^ 2)
					A.pairs, A.pairD = A.pairs + 1, A.pairD + pd
					if pd <= 9 then
						A.pairNear = A.pairNear + 1
					end
				end
			end
		end
		if #players > 0 then
			local snap = b:Snapshot()
			local np = #players
			local first = steps % np
			for k = 0, np - 1 do
				players[1 + (first + k) % np]:step(events, snap)
			end
		end
	end
	local result = b:Result() or { Duration = b:Time() }
	A.n = A.n + 1
	if result.WinnerSide == 1 then
		A.wins = A.wins + 1
	end
	if result.Reason == "Timeout" then
		A.timeouts = A.timeouts + 1
	end
	A.dur = A.dur + (result.Duration or b:Time())
	for _, p in ipairs(players) do
		A.dodges = A.dodges + p.dodges
	end
end

local function sumOf(t)
	local s = 0
	for _, v in pairs(t) do
		s = s + v
	end
	return s
end

local function report(label, A)
	local n = max(1, A.n)
	local secs = max(1, A.dur)
	local parts = {}
	local keys = {}
	for k in pairs(A.tele) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		parts[#parts + 1] = fmt("%s %d tele / %d hit / %d dodged (%.2f hit per tele)", k, A.tele[k], A.teleHit[k] or 0, A.teleMiss[k] or 0, (A.teleHit[k] or 0) / max(1, A.tele[k]))
	end
	out(fmt("%s: win %d/%d, avg %.1f s, timeouts %d", label, A.wins, A.n, A.dur / n, A.timeouts))
	out("    boss areas: " .. table.concat(parts, "; "))
	out(fmt("    per fight: tele hits %.1f, lethal hits %.1f, zone ticks %.1f, boss basic hits %.1f, minion hits %.1f, player KOs %.1f, dashes %.1f; damage taken per s %.0f",
		sumOf(A.teleHit) / n, A.lethal / n, A.zone / n, A.basic / n, A.minion / n, A.kos / n, A.dodges / n, A.dmgIn / secs))
	out(fmt("    floor: %.2f fighters; melee share %.0f%% at %.1f studs from the boss centre, ranged at %.1f; fighter pairs %.1f studs apart, %.0f%% within 9",
		A.fsum / max(1, A.fsteps), 100 * A.sMelee / max(1, A.sMelee + A.sRanged), A.dMelee / max(1, A.sMelee), A.dRanged / max(1, A.sRanged), A.pairD / max(1, A.pairs), 100 * A.pairNear / max(1, A.pairs)))
	for _, name in ipairs({ "melee", "ranged" }) do
		local c = A.cls[name]
		local fs = max(1, c.steps * DT)
		out(fmt("    %s fighters: %.0f floor-s per fight (moving %.1f%%, stunned %.1f%%); deal %.0f per floor-s (element %.0f%%, %.2f plain hits per s); take per floor-s: boss basic %.0f, areas %.0f, minions %.0f, zones %.0f; KOs %.2f per fight",
			name, fs / n, 100 * c.moving / max(1, c.steps), 100 * c.stunned / max(1, c.steps), c.out / fs, 100 * c.elem / max(1, c.out), c.hits / fs, c.inBasic / fs, c.inTele / fs, c.inMinion / fs, c.inZone / fs, c.kos / n))
	end
	out(fmt("    offence: damage out per s %.0f (element %.1f%%), ELEMENT casts %.1f per fight, %.0f%% hit nothing, %.0f%% hit the boss; specials %.1f per fight (per fighter-minute %.2f), casts %d, breaks %d, plain hits %.0f per fight",
		A.dmgOut / secs, 100 * A.dmgElem / max(1, A.dmgOut), A.elem / n, 100 * A.elemWhiff / max(1, A.elem), 100 * A.elemBoss / max(1, A.elem), A.specials / n,
		A.specials / max(1, A.fsum * DT / 60), A.casts, A.breaks, A.plainHits / n))
end

local function withKnobs(so, cast, fn)
	local keepSo, keepCast = BC.Damage.Standoff, BC.Damage.SpecialCast
	BC.Damage.Standoff = so
	BC.Damage.SpecialCast = cast and Config.Battle.Feel.Special.Cast or nil
	local ok, err = pcall(fn)
	BC.Damage.Standoff, BC.Damage.SpecialCast = keepSo, keepCast
	if not ok then
		error(err, 0)
	end
end

local function raid(boss, tier, players, seeds, so, cast, pets)
	local A = newAgg()
	withKnobs(so, cast, function()
		for seed = 1, seeds do
			local teams, owners = {}, {}
			for i = 1, players do
				teams[i] = SIM.team(100 + i, 1, pets or SIM.RaidTeams[tier])
				owners[i] = 100 + i
			end
			runOne({ Mode = "Raid", Boss = boss, RaidTier = tier, Seed = seed, Teams = teams }, owners, nil, A)
		end
	end)
	report(fmt("%s %s %dp x%d seeds, Standoff %d, cast %s", boss, tier, players, seeds, so, cast and "ON" or "off"), A)
	return A
end

-- MEASURE_ARGS: "raid boss tier players seeds so cast" lines separated by ";"
for spec in tostring(MEASURE_ARGS or ""):gmatch("[^;]+") do
	local w = {}
	for word in spec:gmatch("%S+") do
		w[#w + 1] = word
	end
	if w[1] == "raid" then
		raid(w[2], w[3], tonumber(w[4]), tonumber(w[5]), tonumber(w[6]), w[7] == "on")
	end
end
return table.concat(lines, "\n")
