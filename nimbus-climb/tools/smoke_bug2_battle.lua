-- smoke_bug2_battle.lua: bug batch 2, lane battle-balance (shared/BattleCatalog.lua + the BattleSim meterStart hook), loaded
-- by tools/smoke.py in the SERVER world as pure scenarios.
--   bug2bat_npc_specials  #27 enemy NPCs use specials: Damage.MeterOnHit 8 / MeterPerSecond 5 (NPC units only; the
--                         fighter keeps Fighter.MeterPerSecond 6 / MeterOnHit 4 and Damage.MeterStart 20-50),
--                         BattleCatalog.MeterStart (NPC 45-75, the Ring champion + dungeon waves 2+ at 80, players
--                         20-50), the champion entry carries MeterStart 80; a 20 s Ring fight (round 15 vs a Lv 6 team,
--                         the screenshot) shows an NPC special on every seed; most dungeon enemies cast before they
--                         die; raid minions never cast; BattleSim.meterStart rolls the start meter from
--                         BattleCatalog.MeterStart (integration hook): the champion starts at 80, NPC duel units at
--                         45-75 with an NPC special within 20 s on every seed, dungeon wave 1 at 45-75 and wave 2 at 80,
--                         raid minions still never cast over 90 s
--   bug2bat_raid_balance  #2 a boss raid is not soloable by a weak player: BossHp >= HpPerPlayer x BaselineDps(boss)
--                         (the ExpectedDps of BossRules.Baseline, a Lv 25 evolved ember_phoenix), DamageGroup.Min 0.7,
--                         MinHp 2500, GroupExponent 0.2; a strong solo / a group keep their own DPS-based HP; idle alts
--                         never lower it; the sim: a Lv 5 solo loses, a Lv 40 solo and eight Lv 5 teams win; balance-5:
--                         lava_golem HpPerPlayer 85, a solo M5 loses to it and eight M5 teams win >= 5 of 8 seeds
-- White-box: a few checks read battle.units (same Lua state). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local abs = math.abs
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

-- tools/sim_battle.lua as a library (the scripted dodging player, team specs)
local SIMLIB = nil
local function simLib()
	if SIMLIB then
		return SIMLIB
	end
	local src = nil
	for _, candidate in ipairs({ "tools/sim_battle.lua", "sim_battle.lua", "../tools/sim_battle.lua" }) do
		local fh = io.open(candidate, "r")
		if fh then
			src = fh:read("*a")
			fh:close()
			break
		end
	end
	if not src then
		return nil, "tools/sim_battle.lua not found from the working directory"
	end
	_G.SIM_BATTLE_LIBRARY = true
	local load_ = loadstring or load
	local chunk, err = load_(src, "=tools/sim_battle.lua")
	if not chunk then
		_G.SIM_BATTLE_LIBRARY = nil
		return nil, err
	end
	local ok, lib = pcall(chunk)
	_G.SIM_BATTLE_LIBRARY = nil
	if not ok or type(lib) ~= "table" then
		return nil, tostring(lib)
	end
	lib.print = function() end
	SIMLIB = lib
	return lib
end

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= tol
end

-- steps a battle (a scripted player for `owner` when given) for up to `seconds`; -> the Special events of side 2
local function npcSpecials(SIM, b, owner, seconds)
	local side = {}
	for _, info in ipairs(b:StaticUnits()) do
		side[info.id] = info.side
	end
	local player = owner and SIM.Player.new(b, owner, 7) or nil
	local list = {}
	local steps = 0
	while not b:IsFinished() and steps < seconds * 10 do
		local events = b:Step(0.1)
		steps = steps + 1
		for _, ev in ipairs(events) do
			if ev.type == "Spawn" or ev.type == "Wave" then
				for _, info in ipairs(ev.units) do
					side[info.id] = info.side
				end
			elseif ev.type == "Special" and side[ev.unit] == 2 then
				ev.at = ev.at or b:Time() -- the sim time of the step that fired it
				list[#list + 1] = ev
			end
		end
		if player then
			player:step(events, b:Snapshot())
		end
	end
	return list, b:Time()
end

----------------------------------------------------------------------------------------------------
-- bug2bat_npc_specials (#27)
----------------------------------------------------------------------------------------------------
S.bug2bat_npc_specials = guarded("bug2bat_npc_specials", function()
	local BC, e1 = loadModule("BattleCatalog")
	local BS, e2 = loadModule("BattleSim")
	if not T.check(BC ~= nil and BS ~= nil, "BattleCatalog + BattleSim load", tostring(e1 or e2)) then
		return
	end
	local SIM, e3 = simLib()
	if not T.check(SIM ~= nil, "tools/sim_battle.lua loads as a library", tostring(e3)) then
		return
	end
	local D, F = BC.Damage, BC.Fighter
	-- the numbers: NPC units charge faster, the fighter keeps its own kit numbers
	T.check(D.MeterOnHit == 8 and D.MeterPerSecond == 5 and D.MeterOnHurt == 2 and D.MeterMax == 100, "#27 NPC meter: MeterOnHit 4 -> 8, MeterPerSecond 2 -> 5 (MeterOnHurt 2, MeterMax 100 kept)",
		fmt("OnHit %s, PerSecond %s", tostring(D.MeterOnHit), tostring(D.MeterPerSecond)))
	T.check(F.MeterPerSecond == 6 and F.MeterOnHit == 4 and F.MeterOnHurt == 2 and F.SpecialMeterMax == 100, "#27 the player's fighter keeps Fighter.MeterPerSecond 6 / MeterOnHit 4 / MeterOnHurt 2")
	T.check(type(D.MeterStart) == "table" and D.MeterStart[1] == 20 and D.MeterStart[2] == 50, "#27 a player team's units keep MeterStart 20-50")
	-- BattleCatalog.MeterStart
	if T.check(type(BC.MeterStart) == "function", "#27 BattleCatalog.MeterStart(entry, npc, wave) exists") then
		local lo, hi = BC.MeterStart({ Key = "maple_fox" }, false, nil)
		T.check(lo == 20 and hi == 50, "#27 MeterStart: a player's pet 20-50", fmt("%s-%s", tostring(lo), tostring(hi)))
		lo, hi = BC.MeterStart({ Key = "maple_fox" }, true, 1)
		T.check(lo == 45 and hi == 75, "#27 MeterStart: an NPC unit (dungeon wave 1, duel / ring NPC) 45-75", fmt("%s-%s", tostring(lo), tostring(hi)))
		lo, hi = BC.MeterStart({ Key = "maple_fox" }, true, 2)
		local lo3, hi3 = BC.MeterStart({ Key = "maple_fox" }, true, 3)
		T.check(lo == 80 and hi == 80 and lo3 == 80 and hi3 == 80, "#27 MeterStart: dungeon waves 2+ start at 80", fmt("%s-%s / %s-%s", tostring(lo), tostring(hi), tostring(lo3), tostring(hi3)))
		local champ = BC.ChampionTeam(15, 1)
		local entry = champ and champ.Pets and champ.Pets[1]
		lo, hi = BC.MeterStart(entry, true, nil)
		T.check(entry and entry.MeterStart == 80 and lo == 80 and hi == 80, "#27 the Ring champion's entry carries MeterStart 80 -> MeterStart 80", fmt("%s-%s", tostring(lo), tostring(hi)))
		lo, hi = BC.MeterStart({ MeterStart = 500 }, true, nil)
		local lo4, hi4 = BC.MeterStart(nil, false, 99)
		T.check(lo == 100 and hi == 100 and lo4 == 20 and hi4 == 50, "#27 MeterStart clamps to 0..MeterMax and ignores the wave for a player team")
	end
	-- a 20 s Ring fight: round 15's champion vs a Lv 6 team (the screenshot) casts on every seed
	local fights, withSpecial, total = 0, 0, 0
	for seed = 1, 6 do
		local b = BS.new({ Mode = "Ring", Seed = seed, Round = 15, Teams = { SIM.team(1, 1, SIM.Stages[3].Pets), BC.ChampionTeam(15, seed) } })
		if b then
			local list = npcSpecials(SIM, b, 1, 20)
			fights = fights + 1
			total = total + #list
			if #list > 0 then
				withSpecial = withSpecial + 1
			end
		end
	end
	T.check(fights == 6 and withSpecial == 6, "#27 a 20 s Ring fight (round 15 champion vs a Lv 6 team) shows an NPC special on every seed (before: 5 of 6)",
		fmt("%d of %d fights, %.2f specials per fight", withSpecial, fights, total / math.max(1, fights)))
	-- dungeon floor 3 (a solo S3 team, every wave room): most enemies cast before they die (before: 23%)
	local enemies, casters = 0, 0
	for seed = 1, 3 do
		for room = 1, 3 do
			local b = BS.new({ Mode = "Dungeon", Seed = seed, Teams = { SIM.team(1, 1, SIM.Stages[3].Pets) } })
			local player = SIM.Player.new(b, 1, 7)
			local cast = {}
			for w = 1, BC.Dungeon.Waves[room] do
				local plan = BC.DungeonWave(3, room, w, 1, seed)
				local infos = b:SpawnEnemies(plan.Pets, { Wave = w }) or {}
				local mine = {}
				for _, info in ipairs(infos) do
					mine[info.id] = true
				end
				enemies = enemies + #infos
				local steps = 0
				while not b:IsFinished() and b:LivingEnemies() > 0 and steps < 600 do
					local events = b:Step(0.1)
					steps = steps + 1
					for _, ev in ipairs(events) do
						if ev.type == "Special" and mine[ev.unit] then
							cast[ev.unit] = true
						end
					end
					player:step(events, b:Snapshot())
				end
			end
			for _ in pairs(cast) do
				casters = casters + 1
			end
		end
	end
	T.check(enemies > 20 and casters >= enemies * 0.5, "#27 dungeon floor 3 (solo S3 team): at least half of the enemies cast a special before they die (before: 23%)",
		fmt("%d of %d enemies cast", casters, enemies))
	-- raid minions stay NoSpecial
	local b = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = 3, Teams = { SIM.team(1, 1, SIM.Stages[5].Pets) } })
	local minions, minionSpecials = 0, 0
	if b and b.boss then
		b.boss.hp = b.boss.maxHp * 0.6
		local kindOf = {}
		local steps = 0
		while not b:IsFinished() and steps < 300 do
			local events = b:Step(0.1)
			steps = steps + 1
			for _, ev in ipairs(events) do
				if ev.type == "Spawn" or ev.type == "Wave" then
					for _, info in ipairs(ev.units) do
						kindOf[info.id] = info.kind
					end
				elseif ev.type == "Special" and kindOf[ev.unit] == "Minion" then
					minionSpecials = minionSpecials + 1
				end
			end
		end
		for _, u in ipairs(b.units) do
			if u.kind == "Minion" then
				minions = minions + 1
				if u.specialKind ~= nil then
					minionSpecials = minionSpecials + 1
				end
			end
		end
	end
	T.check(minions > 0 and minionSpecials == 0, "#27 raid minions stay NoSpecial (no special kind, no Special event over 30 s)", fmt("%d minions, %d specials", minions, minionSpecials))
	-- the start meter: BattleSim rolls it from BattleCatalog.MeterStart (the integration hook in meterStart)
	local ring = BS.new({ Mode = "Ring", Seed = 1, Round = 15, Teams = { SIM.team(1, 1, SIM.Stages[3].Pets), BC.ChampionTeam(15, 1) } })
	local champMeter, fighterMeter = nil, nil
	for _, u in ipairs(ring and ring.units or {}) do
		if u.side == 2 then
			champMeter = u.meter
		elseif ring.teams[1] and u == ring.teams[1].fighter then
			fighterMeter = u.meter
		end
	end
	T.check(fighterMeter and fighterMeter >= 20 and fighterMeter <= 50, "#27 the player's fighter starts at 20-50 meter", tostring(fighterMeter))
	T.check(near(champMeter, 80, 1e-6), "#27 BattleSim starts the Ring champion at 80 meter (the BattleCatalog.MeterStart hook in meterStart)", fmt("%.1f", champMeter or -1))

	-- integration (the hook): a sim duel vs two NPC foxes. The NPC units start at 45-75, the player's pets at 20-50, and
	-- an NPC special fires within 20 s on every seed
	local duelSeeds, duelCast, npcLo, npcHi, slowest = 0, 0, math.huge, -math.huge, 0
	local playerStartOk = true
	for seed = 1, 6 do
		local npcTeam = SIM.team("foxes", 2, { SIM.pet("maple_fox", 6), SIM.pet("maple_fox", 6) }, { Npc = true })
		local duel = BS.new({ Mode = "Duel", Seed = seed, Teams = { SIM.team(1, 1, SIM.Stages[3].Pets), npcTeam } })
		if duel then
			duelSeeds = duelSeeds + 1
			for _, u in ipairs(duel.units or {}) do
				if u.side == 2 then
					npcLo, npcHi = math.min(npcLo, u.meter), math.max(npcHi, u.meter)
				elseif u.meter < 20 or u.meter > 50 then
					playerStartOk = false
				end
			end
			local list = npcSpecials(SIM, duel, 1, 20)
			if #list > 0 then
				duelCast = duelCast + 1
				local first = duel:Time()
				for _, ev in ipairs(list) do
					first = math.min(first, ev.at or first)
				end
				slowest = math.max(slowest, first)
			end
		end
	end
	T.check(duelSeeds == 6 and npcLo >= 45 and npcHi <= 75, "#27 hook: NPC duel units start at 45-75 meter", fmt("%.1f-%.1f over %d fights", npcLo, npcHi, duelSeeds))
	T.check(playerStartOk, "#27 hook: the player team's units still start at 20-50 meter")
	T.check(duelSeeds == 6 and duelCast == 6, "#27 hook: a 20 s sim duel vs two NPC foxes shows an NPC special on every seed", fmt("%d of %d fights (latest first special by %.1f s)", duelCast, duelSeeds, slowest))

	-- integration (the hook): dungeon wave 2+ enemies start at 80, wave 1 at 45-75
	local dg = BS.new({ Mode = "Dungeon", Seed = 4, Teams = { SIM.team(1, 1, SIM.Stages[3].Pets) } })
	local w1 = dg and dg:SpawnEnemies(BC.DungeonWave(3, 1, 1, 1, 4).Pets, { Wave = 1 }) or {}
	local w1ok, w2ok = #w1 > 0, false
	local byId = {}
	for _, u in ipairs(dg and dg.units or {}) do
		byId[u.id] = u
	end
	for _, info in ipairs(w1) do
		local u = byId[info.id]
		w1ok = w1ok and u ~= nil and u.meter >= 45 and u.meter <= 75
	end
	local w2 = dg and dg:SpawnEnemies(BC.DungeonWave(3, 1, 2, 1, 4).Pets, { Wave = 2 }) or {}
	for _, u in ipairs(dg and dg.units or {}) do
		byId[u.id] = u
	end
	w2ok = #w2 > 0
	for _, info in ipairs(w2) do
		local u = byId[info.id]
		w2ok = w2ok and u ~= nil and near(u.meter, 80, 1e-6)
	end
	T.check(w1ok, "#27 hook: dungeon wave 1 enemies start at 45-75 meter", #w1 .. " enemies")
	T.check(w2ok, "#27 hook: dungeon wave 2 enemies start at 80 meter", #w2 .. " enemies")

	-- integration (the hook): raid minions still never cast now that BattleSim rolls start meters from the catalog (90 s, 3 seeds)
	local rMinions, rSpecials, rKinds = 0, 0, 0
	for seed = 1, 3 do
		local raid = BS.new({ Mode = "Raid", Boss = "storm_titan", Seed = seed, Teams = { SIM.team(1, 1, SIM.Stages[5].Pets) } })
		if raid and raid.boss then
			raid.boss.hp = raid.boss.maxHp * 0.6
			local seen = {}
			local steps = 0
			while not raid:IsFinished() and steps < 900 do
				local events = raid:Step(0.1)
				steps = steps + 1
				for _, u in ipairs(raid.units) do
					if u.kind == "Minion" and not seen[u] then
						seen[u] = true
						rMinions = rMinions + 1
						if u.specialKind ~= nil then
							rKinds = rKinds + 1
						end
					end
				end
				for _, ev in ipairs(events) do
					if ev.type == "Special" then
						for _, u in ipairs(raid.units) do
							if u.id == ev.unit and u.kind == "Minion" then
								rSpecials = rSpecials + 1
							end
						end
					end
				end
			end
		end
	end
	T.check(rMinions > 0 and rKinds == 0 and rSpecials == 0, "#27 hook: raid minions never cast (no special kind, no Special event over 90 s on 3 seeds)", fmt("%d minions, %d with a special kind, %d minion specials", rMinions, rKinds, rSpecials))
end)

----------------------------------------------------------------------------------------------------
-- bug2bat_raid_balance (#2)
----------------------------------------------------------------------------------------------------
S.bug2bat_raid_balance = guarded("bug2bat_raid_balance", function()
	local BC, e1 = loadModule("BattleCatalog")
	local BS, e2 = loadModule("BattleSim")
	if not T.check(BC ~= nil and BS ~= nil, "BattleCatalog + BattleSim load", tostring(e1 or e2)) then
		return
	end
	local SIM, e3 = simLib()
	if not T.check(SIM ~= nil, "tools/sim_battle.lua loads as a library", tostring(e3)) then
		return
	end
	local R = BC.BossRules
	T.check(R.DamageGroup.Min == 0.7 and R.DamageGroup.FullAt == 8 and R.MinHp == 2500 and R.GroupExponent == 0.2, "#2 BossRules: DamageGroup.Min 0.35 -> 0.7, MinHp 600 -> 2500, GroupExponent 0.2 kept",
		fmt("Min %s, MinHp %s, exp %s", tostring(R.DamageGroup.Min), tostring(R.MinHp), tostring(R.GroupExponent)))
	-- BaselineDps = the ExpectedDps of a Lv 25 evolved (stage 1) fighter, for every boss
	local ref = R.Baseline or {}
	local want = BC.ExpectedDps({ Pets = { { PetId = ref.PetId, Key = ref.PetId, Level = ref.Level, Evo = ref.Evo } } })
	local allSame = type(BC.BaselineDps) == "function"
	for _, id in ipairs(BC.BossOrder) do
		allSame = allSame and near(BC.BaselineDps(id), want, 1e-6)
	end
	T.check(ref.Level == 25 and ref.Evo == 1 and want > 100 and allSame, "#2 BaselineDps(boss) = ExpectedDps of the Lv 25 evolved (stage 1) baseline fighter for every boss", fmt("%s %.1f", tostring(ref.PetId), want))
	-- BossHp: a weak solo meets the floor; a strong solo keeps its own; a weak group adds up past it; alts never lower it
	local lv5 = { SIM.pet("maple_fox", 5), SIM.pet("bubble_axolotl", 5), SIM.pet("storm_tabby", 5) }
	local lv40 = { SIM.pet("cloudy_dragon", 40, "Golden", { Evo = 1 }), SIM.pet("stormfang", 35, nil, { Evo = 1 }), SIM.pet("eclipse_dragon", 35, nil, { Evo = 1 }) }
	local boss = BC.Bosses.storm_titan
	local floorHp = boss.HpPerPlayer * (BC.BaselineDps and BC.BaselineDps("storm_titan") or 0)
	local soloWeak = BC.BossHp("storm_titan", { { Pets = lv5 } })
	local soloStrong = BC.BossHp("storm_titan", { { Pets = lv40 } })
	local ownStrong = boss.HpPerPlayer * BC.ExpectedDps({ Pets = lv40 })
	T.check(abs(soloWeak - floorHp) <= 1, "#2 a Lv 5 solo's boss HP is the floor HpPerPlayer x BaselineDps (before: 100 s of its own DPS, ~2000)", fmt("%d vs floor %.0f", soloWeak, floorHp))
	T.check(abs(soloStrong - ownStrong) <= 1 and soloStrong > floorHp, "#2 a Lv 40 solo's boss HP is still 100 s of its own DPS (above the floor)", fmt("%d vs own %.0f", soloStrong, ownStrong))
	local alts = { { Pets = lv5 } }
	for i = 2, 8 do
		alts[i] = { Pets = { SIM.pet("biscuit_bear", 1) } }
	end
	T.check(BC.BossHp("storm_titan", alts) >= soloWeak, "#2 idle alt teams never lower the floor")
	local group = {}
	for i = 1, 8 do
		group[i] = { Pets = lv40 }
	end
	local g8 = BC.BossHp("storm_titan", group)
	T.check(near(g8, 8 * ownStrong * 8 ^ 0.2, g8 * 0.01), "#2 a group above the floor keeps HpPerPlayer x sum of DPS x teams ^ 0.2", fmt("%d", g8))
	local hp, shares = BC.BossHp("storm_titan", { { Pets = lv5 }, { Pets = lv5 } })
	T.check(type(shares) == "table" and #shares == 2 and near((shares[1] + shares[2]) * BC.GroupFactor(2), hp, hp * 0.01), "#2 the shares scale up with the floor (shares x GroupFactor = the HP)")
	-- the sim: dodging scripted players, 2 seeds per cell
	local function raid(bossId, pets, players, seeds)
		local policies = {}
		for i = 1, players do
			policies[100 + i] = "player"
		end
		return SIM.series(function(seed)
			local teams = {}
			for i = 1, players do
				teams[i] = SIM.team(100 + i, 1, pets)
			end
			return { Mode = "Raid", Boss = bossId, Seed = seed, Teams = teams }
		end, policies, seeds)
	end
	local soloWins, soloRuns, strongWins, strongRuns, groupWins, groupRuns = 0, 0, 0, 0, 0, 0
	local detail = {}
	for _, id in ipairs({ "storm_titan", "frost_wyrm" }) do
		local a = raid(id, lv5, 1, 2)
		local c = raid(id, lv40, 1, 2)
		local g = raid(id, lv5, 8, 1)
		soloWins, soloRuns = soloWins + a.wins[1], soloRuns + a.n
		strongWins, strongRuns = strongWins + c.wins[1], strongRuns + c.n
		groupWins, groupRuns = groupWins + g.wins[1], groupRuns + g.n
		detail[#detail + 1] = fmt("%s Lv5x1 %d/%d, Lv40x1 %d/%d in %.0f s, Lv5x8 %d/%d in %.0f s", id, a.wins[1], a.n, c.wins[1], c.n, c.avgDur, g.wins[1], g.n, g.avgDur)
	end
	T.check(soloRuns == 4 and soloWins == 0, "#2 a Lv 5 solo cannot beat a raid boss inside the 330 s window (before: won in ~50-100 s)", table.concat(detail, "; "))
	T.check(strongRuns == 4 and strongWins == 4, "#2 a Lv 40 solo still beats the raid boss", table.concat(detail, "; "))
	T.check(groupRuns == 2 and groupWins == 2, "#2 eight Lv 5 teams together still beat the raid boss", table.concat(detail, "; "))
	-- balance-5: the Lava Golem counters the Frost-heavy mid team (M5) and the bug #22 engaged pets (EngagePull 7) cost
	-- that group time: 8 x M5 won 44% of 32 seeds at HpPerPlayer 90. At 85: 84% of 32 (6 of seeds 1-8), a solo M5 still
	-- loses with ~65% of the boss left, and the other bosses keep HpPerPlayer 100
	T.check(BC.Bosses.lava_golem.HpPerPlayer == 85 and BC.Bosses.storm_titan.HpPerPlayer == 100 and BC.Bosses.frost_wyrm.HpPerPlayer == 100 and BC.Bosses.shadow_hydra.HpPerPlayer == 100,
		"balance-5: lava_golem HpPerPlayer 90 -> 85, the other bosses 100", tostring(BC.Bosses.lava_golem.HpPerPlayer))
	local lavaSolo = SIM.midGroup("lava_golem", 1, 2)
	local lavaGroup = SIM.midGroup("lava_golem", 8, 8)
	T.check(lavaSolo.n == 2 and lavaSolo.wins[1] == 0, "balance-5 (#2): a solo mid (M5) team still loses to the Lava Golem", fmt("%d of %d", lavaSolo.wins[1], lavaSolo.n))
	T.check(lavaGroup.n == 8 and lavaGroup.wins[1] >= 5 and lavaGroup.avgDur <= 240, "balance-5 (#2): eight mid (M5) teams win a fair share against the Lava Golem (>= 5 of 8 seeds, before the enrage on average)", fmt("%d of %d, %.0f s", lavaGroup.wins[1], lavaGroup.n, lavaGroup.avgDur))
end)

return S
