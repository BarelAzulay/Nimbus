-- smoke_ring_noheal.lua: the Champion Ring no-heal rule (HUD cleanup plan, Task 4; spec 2026-10-30 decision 5), loaded
-- by tools/smoke.py in the SERVER world. The first two scenarios are pure (no boot), the third drives a booted run.
--   ringnh_catalog  champions on the PLAYER stat formula: BattleCatalog.ChampionLevel / ChampionTier / ChampionCount
--                   follow Ring.LevelAnchors (linear between anchors, floored, + BossLevelBump on BossEvery rounds, held
--                   at MaxPetLevel) / TierFrom / Helpers; ChampionTeam(round, seed) is 1..3 pets with no Boss / Handicap
--                   / Boost, levels 1..100, never EventOnly; RingPower never drops; a champion's MaxHp is PetCatalog.
--                   BattleStatsOf x role x HpScale at the stage its level allows; Champion.Boss is a flag only; the old
--                   target solver knobs are gone; Validate passes
--   ringnh_sim_hp   BattleSim: a player entry's HpFraction sets its starting HP (>= 1 HP, junk / > 1 = full);
--                   Result().Units lists every player team's pets { Key, Hp, MaxHp, Alive } (no NPC teams); 0 HP after
--                   a won fight is fainted; the fraction carries across a level-up
--   ringnh_service  BattleService: the run keeps every pet's HP share from round to round, a fainted pet sits out the
--                   rest of the run (recorded in run.Fainted), a won round that leaves nobody standing ends the run with
--                   reason "Fainted" and the toast (the wins stay paid), a new run starts at full HP, TeamSpec's hpByKey
-- White-box: the sim checks set battle.units HP; the service checks reach BattleService's St (an upvalue of IsInBattle)
-- to set the running round's HP and knock the champion out. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local abs, floor = math.abs, math.floor
local fmt = string.format

local S = {}

local function req(path)
	local inst = K.moduleInstance(path)
	if not inst then
		return nil
	end
	local ok, m = pcall(require, inst)
	if ok and type(m) == "table" then
		return m
	end
	return nil
end

local function pet(key, level, tier, extra)
	local p = { Key = key, Level = level or 1, Tier = tier }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

-- the curve of Ring.LevelAnchors (linear between anchors, floored, the last anchor holds), without the boss bump
local function curve(anchors, r)
	if r <= anchors[1][1] then
		return anchors[1][2]
	end
	for i = 2, #anchors do
		local a, b = anchors[i - 1], anchors[i]
		if r <= b[1] then
			return floor(a[2] + (b[2] - a[2]) * (r - a[1]) / (b[1] - a[1]))
		end
	end
	return anchors[#anchors][2]
end

-- the evolution stage a PLAYER pet of `level` can hold (PetCatalog.EvolutionLevels), clamped to the species' top
local function stageFor(PC, def, level)
	local stage = 0
	for s, need in ipairs(PC.EvolutionLevels or {}) do
		if level >= need then
			stage = s
		end
	end
	return PC.EvolutionStage(def, level, stage)
end

local function runToEnd(b, maxSteps)
	local steps = 0
	while not b:IsFinished() and steps < (maxSteps or 2000) do
		b:Step(0.1)
		steps = steps + 1
	end
	return b:Result()
end

-- knocks every side-2 unit out (white-box) and steps once: the fight is won by side 1
local function knockOutSide2(b)
	for _, u in ipairs(b.units) do
		if u.side == 2 then
			u.hp = 0
			u.alive = false
			u.state = 5
		end
	end
end

----------------------------------------------------------------------------------------------------
-- ringnh_catalog
----------------------------------------------------------------------------------------------------
S.ringnh_catalog = guarded("ringnh_catalog", function()
	local BC, PC = req("shared/BattleCatalog"), req("shared/PetCatalog")
	if not T.check(BC and PC and type(BC.ChampionLevel) == "function" and type(BC.ChampionTier) == "function" and type(BC.ChampionCount) == "function", "ring no-heal: BattleCatalog.ChampionLevel / ChampionTier / ChampionCount exist") then
		return
	end
	local R = BC.Ring
	local top = PC.MaxPetLevel()
	local t1 = T.tally("ring no-heal: ChampionTeam(1..120, seeds 1..8) is a team spec of 1..3 pets")
	local t2 = T.tally("ring no-heal: no champion pet carries Boss / Handicap / Boost; levels 1..100")
	local t3 = T.tally("ring no-heal: RingPower(r) >= RingPower(r - 1) (rounds 2..120, seeds 1..8)")
	local t4 = T.tally("ring no-heal: the crowned champion is never an EventOnly pet")
	local t6 = T.tally("ring no-heal: every champion pet's Evo is the stage its level allows, Power = TeamPower(Pets)")
	-- review fix: the shown level follows the curve (a species is picked only when it matches the round before within
	-- MaxLevelRaise levels), never L42 one round and L26 the next
	local t7 = T.tally("ring no-heal: every champion's level is within Ring.MaxLevelRaise of ChampionLevel(r) (the curve the HUD shows)")
	local raise = R.MaxLevelRaise
	for r = 1, 120 do
		for s = 1, 8 do
			local spec = BC.ChampionTeam(r, s)
			t1:case(type(spec) == "table" and type(spec.Pets) == "table" and #spec.Pets >= 1 and #spec.Pets <= 3, r .. "/" .. s)
			if type(spec) == "table" and type(spec.Pets) == "table" and spec.Pets[1] then
				for _, p in ipairs(spec.Pets) do
					t2:case(p.Boss == nil and p.Handicap == nil and p.Boost == nil and p.Level <= top and p.Level >= 1, r .. ":" .. tostring(p.PetId) .. " L" .. tostring(p.Level))
					local def = PC.Get(p.PetId)
					t6:case(def ~= nil and p.Evo == stageFor(PC, def, p.Level), r .. ":" .. tostring(p.PetId) .. " L" .. tostring(p.Level) .. " evo " .. tostring(p.Evo))
					t7:case(type(raise) == "number" and raise >= 0 and raise <= 6 and p.Level >= BC.ChampionLevel(r) and p.Level <= BC.ChampionLevel(r) + raise, fmt("%d/%d: %s L%d (curve L%d)", r, s, tostring(p.PetId), p.Level, BC.ChampionLevel(r)))
				end
				t6:case(spec.Power == BC.TeamPower(spec.Pets), r .. "/" .. s .. " power")
				if r > 1 then
					t3:case(BC.RingPower(r, s) >= BC.RingPower(r - 1, s), r .. "/" .. s .. ": " .. tostring(BC.RingPower(r - 1, s)) .. " -> " .. tostring(BC.RingPower(r, s)))
				end
				t4:case(not PC.IsEventOnly(spec.Pets[1].PetId), spec.Pets[1].PetId)
			end
		end
	end
	t1:report()
	t2:report()
	t3:report()
	t4:report()
	t6:report()
	t7:report()
	-- the curve
	local A = R.LevelAnchors
	T.check(type(A) == "table" and A[1][1] == 1 and A[1][2] == 1 and A[#A][2] == top, "ring no-heal: Ring.LevelAnchors starts at round 1 / level 1 and ends at MaxPetLevel " .. top)
	local curveOk, curveBad = true, {}
	for r = 1, 130 do
		local want = curve(A, r)
		if r % R.BossEvery == 0 then
			want = want + R.BossLevelBump
		end
		if want > top then
			want = top
		end
		if BC.ChampionLevel(r) ~= want then
			curveOk = false
			curveBad[#curveBad + 1] = r .. "=" .. tostring(BC.ChampionLevel(r)) .. " (want " .. want .. ")"
		end
	end
	T.check(curveOk, "ring no-heal: ChampionLevel follows LevelAnchors (linear between anchors, floored, + BossLevelBump on BossEvery rounds, held at 100)", table.concat(curveBad, ", "))
	T.check(BC.ChampionLevel(1) == 1 and BC.ChampionLevel(3) == 1 and BC.ChampionLevel(A[#A][1] + 1) == top and BC.ChampionLevel(120) == top and BC.ChampionLevel(100000) == top, "ring no-heal: rounds 1-3 are level 1; past the last anchor the champion stays at 100")
	T.check(BC.ChampionLevel(10) == curve(A, 10) + R.BossLevelBump and BC.ChampionLevel(11) == curve(A, 11), "ring no-heal: a boss round (BossEvery) adds BossLevelBump levels, the next round does not")
	T.check(BC.ChampionTier(1) == "Normal" and BC.ChampionTier(R.TierFrom.Golden - 1) == "Normal" and BC.ChampionTier(R.TierFrom.Golden) == "Golden" and BC.ChampionTier(R.TierFrom.Rainbow - 1) == "Golden" and BC.ChampionTier(R.TierFrom.Rainbow) == "Rainbow" and BC.ChampionTier(500) == "Rainbow", "ring no-heal: ChampionTier by TierFrom (Normal -> Golden -> Rainbow)")
	local h = R.Helpers
	T.check(BC.ChampionCount(1) == 1 and BC.ChampionCount(h[1].From - 1) == 1 and BC.ChampionCount(h[1].From) == h[1].Count and BC.ChampionCount(h[#h].From) == R.MaxChampions and BC.ChampionCount(1000) == R.MaxChampions and R.MaxChampions == 3, "ring no-heal: helpers join at Helpers.From (1 -> 2 -> 3 champions)")
	local full = true
	for s = 1, 8 do
		if #BC.ChampionTeam(100, s).Pets ~= 3 then
			full = false
		end
	end
	T.check(full, "ring no-heal: round 100 fields three champions (every seed)")
	-- round 1: a plain level-1 Common
	local c1 = BC.ChampionTeam(1, 5).Pets[1]
	local d1 = PC.Get(c1.PetId)
	T.check(c1.Level == 1 and c1.Tier == "Normal" and d1 and d1.Rarity == "Common" and c1.Crowned == true and c1.MeterStart == BC.Damage.LateMeterStart, "ring no-heal: round 1 is a plain level-1 Common (crowned, MeterStart = LateMeterStart)", fmt("%s L%s %s", tostring(c1.PetId), tostring(c1.Level), tostring(d1 and d1.Rarity)))
	-- the player formula: a champion's stats are BattleCatalog.BattleStatsOf x role x HpScale at its level / tier / stage
	local spec40 = BC.ChampionTeam(40, 2)
	local e40 = spec40.Pets[1]
	local def40 = PC.Get(e40.PetId)
	local us = BC.UnitStats(e40)
	local stage = stageFor(PC, def40, e40.Level)
	local want = BC.BattleStatsOf(def40, e40.Level, e40.Tier, stage)
	T.check(e40.Level >= BC.ChampionLevel(40) and e40.Tier == BC.ChampionTier(40), "ring no-heal: round 40's champion is at least at the curve level, at the round's tier", fmt("L%d (curve %d) %s", e40.Level, BC.ChampionLevel(40), tostring(e40.Tier)))
	T.check(us and abs(us.MaxHp - want.Health * BC.Roles[BC.RoleOf(def40)].Health * BC.Damage.HpScale) < 1e-6, "ring no-heal: a champion's MaxHp is the PLAYER formula (BattleStatsOf x role x HpScale, evolved as its level allows)", us and fmt("%.3f vs %.3f", us.MaxHp, want.Health * BC.Roles[BC.RoleOf(def40)].Health * BC.Damage.HpScale) or "no stats")
	T.check(e40.Evo == stage, "ring no-heal: ...and its Evo is the stage its level allows", fmt("evo %s, stage %d", tostring(e40.Evo), stage))
	-- same level = same strength: the champion unit and a player unit of the same pet / level / tier / stage
	local BS = req("shared/BattleSim")
	local twin = { Owner = 1, Side = 1, Pets = { pet(e40.PetId, e40.Level, e40.Tier, { Evo = e40.Evo }) } }
	local solo = { Owner = "npc", Side = 2, Npc = true, Pets = { e40 } }
	local bt = BS.new({ Mode = "Ring", Seed = 1, Round = 40, Teams = { twin, solo } })
	T.check(bt and abs(bt.units[1].maxHp - bt.units[2].maxHp) < 1e-6 and abs(bt.units[1].hit - bt.units[2].hit) < 1e-6, "ring no-heal: in BattleSim a champion and a player's pet of the same level / tier / stage have the same MaxHp and hit", bt and fmt("%.1f / %.1f HP, %.2f / %.2f hit", bt.units[1].maxHp, bt.units[2].maxHp, bt.units[1].hit, bt.units[2].hit) or "no battle")
	T.check(BC.ChampionTeam(10, 1).Champion.Boss == true and BC.ChampionTeam(11, 1).Champion.Boss == nil, "ring no-heal: Champion.Boss stays a flag on BossEvery rounds (rewards / crowd), not a stat multiplier")
	T.check(spec40.Champion.PetId == e40.PetId and spec40.Champion.Level == e40.Level and spec40.Champion.Count == #spec40.Pets and spec40.Champion.Power == spec40.Power and spec40.Round == 40, "ring no-heal: ChampionTeam.Champion = { PetId, Level, Tier, Evo, Count, Boss, Name, Power }")
	T.check(BC.RingTarget == nil and R.FirstPower == nil and R.Growth == nil and R.EasyRounds == nil and R.BossBump == nil and R.MinHandicap == nil and R.ChampionMaxLevel == nil, "ring no-heal: the old target solver knobs are gone (RingTarget, FirstPower, Growth, BossBump, MinHandicap, ChampionMaxLevel, EasyRounds)")
	T.check(type(BC.SolveEnemy) == "function" and BC.SolveEnemy("maple_fox", 20) ~= nil, "ring no-heal: SolveEnemy stays for the Dungeon")
	local okV, problems = BC.Validate()
	T.check(okV == true, "ring no-heal: BattleCatalog.Validate passes", table.concat(problems or {}, "; "))
end)

----------------------------------------------------------------------------------------------------
-- ringnh_sim_hp
----------------------------------------------------------------------------------------------------
S.ringnh_sim_hp = guarded("ringnh_sim_hp", function()
	local BC, BS = req("shared/BattleCatalog"), req("shared/BattleSim")
	if not T.check(BC and BS and type(BC.ChampionLevel) == "function", "ring no-heal sim: the modules load (ChampionLevel present)") then
		return
	end
	local team = { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 5, nil, { HpFraction = 0.25 }), pet("puddle_frog", 5), pet("mallow_kitten", 5) } }
	local b = BS.new({ Mode = "Ring", Seed = 1, Round = 1, Teams = { team, BC.ChampionTeam(1, 1) } })
	local u = b.units
	T.check(abs(u[1].hp / u[1].maxHp - 0.25) < 1e-6 and u[2].hp == u[2].maxHp and u[3].hp == u[3].maxHp, "ring no-heal sim: HpFraction sets the starting HP; pets without it start full", fmt("%.3f", u[1].hp / u[1].maxHp))
	local tiny = BS.new({ Mode = "Ring", Seed = 1, Round = 1, Teams = { { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 1, nil, { HpFraction = 1e-9 }) } }, BC.ChampionTeam(1, 1) } })
	T.check(tiny.units[1].hp >= 1, "ring no-heal sim: a tiny fraction still starts with >= 1 HP (never a dead unit at the bell)")
	local junk = BS.new({ Mode = "Ring", Seed = 1, Round = 1, Teams = { { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 1, nil, { HpFraction = 7 }), pet("puddle_frog", 1, nil, { HpFraction = "x" }), pet("mallow_kitten", 1, nil, { HpFraction = 0 / 0 }) } }, BC.ChampionTeam(1, 1) } })
	local ju = junk.units
	T.check(ju[1].hp == ju[1].maxHp and ju[2].hp == ju[2].maxHp and ju[3].hp == ju[3].maxHp, "ring no-heal sim: fractions above 1, NaN or junk mean full HP")
	local npcFrac = BS.new({ Mode = "Ring", Seed = 1, Round = 1, Teams = { { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 1) } }, { Owner = "npc", Side = 2, Npc = true, Pets = { pet("puddle_frog", 1, nil, { HpFraction = 0.5 }) } } } })
	T.check(npcFrac.units[2].hp == npcFrac.units[2].maxHp, "ring no-heal sim: HpFraction is for player teams only (an NPC entry starts full)")
	local res = runToEnd(b)
	T.check(type(res) == "table" and type(res.Units) == "table" and type(res.Units[1]) == "table" and #res.Units[1] == 3, "ring no-heal sim: Result().Units lists the player team's pets")
	local t5 = T.tally("ring no-heal sim: Units rows are { Key, Hp, MaxHp, Alive } with 0 <= Hp <= MaxHp and Alive == (Hp > 0)")
	for _, r in ipairs(res and res.Units and res.Units[1] or {}) do
		t5:case(type(r.Key) == "string" and r.Hp >= 0 and r.Hp <= r.MaxHp and r.Hp == floor(r.Hp) and (r.Alive == (r.Hp > 0)), tostring(r.Key))
	end
	t5:report()
	T.check(res and res.Units and res.Units[1][1].Key == "pebble_pup" and res.Units[1][2].Key == "puddle_frog", "ring no-heal sim: ...in slot order")
	T.check(res and res.Units and res.Units.npc == nil, "ring no-heal sim: ...NPC teams are not listed")
	-- a pet at 0 HP when the last blow lands is fainted, not revived by the win
	local b2 = BS.new({ Mode = "Ring", Seed = 2, Round = 1, Teams = { { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 5), pet("puddle_frog", 5), pet("mallow_kitten", 5) } }, BC.ChampionTeam(1, 2) } })
	b2.units[2].hp = 0
	b2.units[1].hp = b2.units[1].maxHp * 0.6
	knockOutSide2(b2)
	local killed = runToEnd(b2, 5)
	T.check(killed and killed.WinnerSide == 1 and killed.Units[1][2].Alive == false and killed.Units[1][2].Hp == 0, "ring no-heal sim: 0 HP = fainted, never revived by the win")
	T.check(killed and killed.Units[1][1].Alive == true and abs(killed.Units[1][1].Hp / killed.Units[1][1].MaxHp - 0.6) < 0.02 and killed.Units[1][3].Hp == killed.Units[1][3].MaxHp, "ring no-heal sim: the others report their HP (the fighter 60%, the untouched pet full)")
	-- the fraction carries across a level-up: 40% of a L5 max becomes 40% of a L6 max
	local f = 0.4
	local l5, l6 = BC.UnitStats("pebble_pup", 5).MaxHp, BC.UnitStats("pebble_pup", 6).MaxHp
	local n = BS.new({ Mode = "Ring", Seed = 1, Round = 2, Teams = { { Owner = 1, Side = 1, Pets = { pet("pebble_pup", 6, nil, { HpFraction = f }) } }, BC.ChampionTeam(2, 1) } })
	T.check(abs(n.units[1].hp - l6 * f) < 1e-6 and l6 > l5, "ring no-heal sim: a level-up between rounds keeps the FRACTION (no heal beyond the share)", fmt("%.2f of %.2f", n.units[1].hp, l6))
end)

----------------------------------------------------------------------------------------------------
-- ringnh_service (booted)
----------------------------------------------------------------------------------------------------
local seq = 0
local KEYS = { "maple_fox", "puddle_frog", "mallow_kitten" }

local function BSvc()
	return req("server/Services/BattleService")
end
local function DS()
	return req("server/Services/DataService")
end

-- BattleService's St (the upvalue of IsInBattle; white-box, tests only)
local function svcState()
	local f = BSvc() and BSvc().IsInBattle
	if type(f) ~= "function" then
		return nil
	end
	for i = 1, 80 do
		local name, v = debug.getupvalue(f, i)
		if not name then
			break
		end
		if name == "St" and type(v) == "table" and type(v.battles) == "table" then
			return v
		end
	end
	return nil
end

local function runOf(p)
	local St = svcState()
	return St and St.ringRuns and St.ringRuns[p] or nil
end

local function battleOf(p)
	local St = svcState()
	local id = p:GetAttribute("InBattle")
	return St and type(id) == "string" and St.battles[id] or nil
end

-- the player's sim units of a battle record, slot order: { key, hp, maxHp, unit }
local function unitsOf(b, p)
	local out = {}
	local team = b and b.Sim and b.Sim.teamByOwner and b.Sim.teamByOwner[p.UserId]
	for _, u in ipairs(team and team.units or {}) do
		out[#out + 1] = { key = u.key, hp = u.hp, maxHp = u.maxHp, unit = u }
	end
	return out
end

-- white-box: the climber's pets at these HP shares (key -> fraction), then the champion knocked out (the round is won)
local function winWith(b, p, shares)
	for _, u in ipairs(unitsOf(b, p)) do
		if shares[u.key] then
			u.unit.hp = u.maxHp * shares[u.key]
		end
	end
	knockOutSide2(b.Sim)
end

local function lastSent(p, kind)
	local log = Mock.RemoteLog
	for i = #log, 1, -1 do
		local e = log[i]
		if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and e.args[1] == kind then
			return e.args[2]
		end
	end
	return nil
end

local function toastsOf(p, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		out[#out + 1] = tostring(e.args[1])
	end
	return out
end

local function ringPortalPos()
	local AB = req("server/Services/ArenaBuilder")
	local info = AB and AB.GetInfo and AB.GetInfo()
	local portal = info and info.RingPortal
	if type(portal) == "table" then
		portal = portal.Model or portal.Pad or portal.Part
	end
	if typeof(portal) ~= "Instance" then
		portal = workspace:FindFirstChild("Portal_Ring", true)
	end
	if typeof(portal) ~= "Instance" then
		return nil
	end
	if portal:IsA("BasePart") then
		return portal.Position
	end
	return portal:GetPivot().Position
end

local function toRing(p)
	local pos = ringPortalPos()
	if pos then
		Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 6)))
		K.advance(0.05)
	end
end

local function claimHome(p)
	local Ty = req("server/Services/TycoonService")
	local SS = req("server/Services/SpotService")
	local spots = (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
	for i = 1, K.config().Lobby.SpotCount do
		if spots[i] and not (SS and SS.GetOwner(i)) then
			if Ty.Claim(p, i) then
				K.advance(0.6)
				Ty.Buy(p, "Garden")
				K.advance(0.3)
				return i
			end
		end
	end
	return nil
end

S.ringnh_service = guarded("ringnh_service", function()
	if not K.needBoot() then
		return
	end
	local bs, data, BC = BSvc(), DS(), req("shared/BattleCatalog")
	if not T.check(bs and data and BC and type(bs.StartRing) == "function" and svcState() ~= nil, "ring no-heal service: BattleService (StartRing, St) loaded") then
		return
	end
	local realRaid = bs.StartRaid
	bs.StartRaid = function()
		return false, "A raid is already running"
	end
	seq = seq + 1
	local a = Mock.AddPlayer("RingNoHeal" .. seq, 971000 + seq) -- (971000+: smoke_p3_ui.lua's tutorial players use 968000 + seq)
	K.advance(1.0)
	local prof = data.GetProfile(a)
	for _, id in ipairs(KEYS) do
		prof.Pets[id] = 1
		prof.PetLevels[id] = { Level = 5, Xp = 0 }
	end
	data.MarkDirty(a)
	data.SetTeam(a, 1, KEYS)
	T.check(claimHome(a) ~= nil, "ring no-heal service: (setup) the climber claims a home")
	toRing(a)
	local mark = K.logSize()
	local okR, id = bs.StartRing(a)
	if not T.check(okR == true and type(id) == "string", "ring no-heal service: the run starts", tostring(id)) then
		bs.StartRaid = realRaid
		K.removePlayers({ a })
		return
	end
	local run = runOf(a)
	T.check(run and type(run.Hp) == "table" and type(run.Fainted) == "table" and next(run.Hp) == nil and next(run.Fainted) == nil, "ring no-heal service: the run record carries Hp = {} and Fainted = {}")
	-- round 1 won with the fighter at 30%, the first helper at 0 HP
	winWith(battleOf(a), a, { [KEYS[1]] = 0.3, [KEYS[2]] = 0 })
	K.advance(0.3)
	T.check(run.Fainted[KEYS[2]] == true and run.Hp[KEYS[2]] == 0 and abs((run.Hp[KEYS[1]] or 0) - 0.3) < 0.02 and run.Hp[KEYS[3]] == 1, "ring no-heal service: after the win the run records the HP shares (30% / fainted / full)")
	T.check(run.Wins == 1 and run.State == "Intermission", "ring no-heal service: ...and waits for round 2 (the win paid)")
	K.advance(BC.Ring.Intermission + 0.5)
	local b2 = battleOf(a)
	local units = unitsOf(b2, a)
	T.check(b2 and b2.Round == 2 and #units == 2 and units[1].key == KEYS[1] and abs(units[1].hp / units[1].maxHp - 0.3) < 0.02, "ring no-heal service: round 2 fields the two live pets; the hurt fighter keeps its 30% HP", fmt("%d units, %s", #units, units[1] and fmt("%.3f", units[1].hp / units[1].maxHp) or "-"))
	T.check(units[2] and units[2].key == KEYS[3] and units[2].hp == units[2].maxHp, "ring no-heal service: ...the untouched pet is still full")
	local start = lastSent(a, "Start")
	local mine = 0
	for _, u in ipairs(start and start.Units or {}) do
		if u.owner == a.UserId then
			mine = mine + 1
		end
	end
	T.check(start and start.Round == 2 and mine == 2, "ring no-heal service: the client's round-2 Start payload lists 2 fighters", tostring(mine))
	local keysIn = bs.KeysInBattle(a)
	T.check(keysIn[KEYS[1]] and keysIn[KEYS[2]] and keysIn[KEYS[3]], "ring no-heal service: the fainted pet stays locked for the run (KeysInBattle keeps every run key)")
	-- round 2 won with the fighter down to 0 and the last helper at 5%
	winWith(b2, a, { [KEYS[1]] = 0, [KEYS[3]] = 0.05 })
	K.advance(BC.Ring.Intermission + 0.8)
	local u3 = unitsOf(battleOf(a), a)
	T.check(battleOf(a) and battleOf(a).Round == 3 and #u3 == 1 and u3[1].key == KEYS[3] and abs(u3[1].hp / u3[1].maxHp - 0.05) < 0.02, "ring no-heal service: round 3 fields only the last pet, at its 5%", fmt("%d units", #u3))
	-- round 3 won as the last pet drops to 0: nobody is left -> the run ends with reason Fainted
	local mark3 = K.logSize()
	winWith(battleOf(a), a, { [KEYS[3]] = 0 })
	K.advance(0.5)
	local final = lastSent(a, "End")
	local toasts = toastsOf(a, mark3)
	T.check(final and final.Reason == "Fainted" and type(final.Rewards) == "table" and final.Rewards.Final == true and final.Rewards.Run and final.Rewards.Run.Wins == 3, "ring no-heal service: a win with no pet left ends the run: the final End has Reason Fainted and the result card (3 wins)", final and tostring(final.Reason) or "no End")
	T.check(#toasts > 0 and toasts[#toasts]:find("whole team fainted", 1, true) ~= nil, "ring no-heal service: ...and the toast 'Your whole team fainted: the run is over'", table.concat(toasts, " | "))
	K.advance(5)
	T.check(runOf(a) == nil and a:GetAttribute("InBattle") == nil, "ring no-heal service: the run is gone after the return")
	local ring = data.GetRing(a)
	T.check(ring and ring.Best == 3 and ring.Runs == 1, "ring no-heal service: ...the three wins stayed paid (Best 3, Runs 1)", ring and fmt("Best %s Runs %s", tostring(ring.Best), tostring(ring.Runs)) or "no ring")
	-- a new run heals (a new run = a new Hp table)
	toRing(a)
	local ok2 = bs.StartRing(a)
	local u2 = unitsOf(battleOf(a), a)
	T.check(ok2 == true and #u2 == 3 and u2[1].hp == u2[1].maxHp and u2[2].hp == u2[2].maxHp and u2[3].hp == u2[3].maxHp, "ring no-heal service: a new run starts with every pet at full HP", tostring(#u2))
	if bs.IsInBattle(a) then
		bs.Forfeit(a)
	end
	K.advance(5.5)
	-- TeamSpec(player, keys, hpByKey)
	local spec = bs.TeamSpec(a, KEYS, { [KEYS[1]] = 0, [KEYS[2]] = 0.5 })
	T.check(spec and #spec.Pets == 2 and spec.Pets[1].Key == KEYS[2] and spec.Pets[1].HpFraction == 0.5 and spec.Pets[2].Key == KEYS[3] and spec.Pets[2].HpFraction == nil, "ring no-heal service: TeamSpec(player, keys, hpByKey) skips 0-HP keys and carries the others' HpFraction")
	local plain = bs.TeamSpec(a, KEYS)
	T.check(plain and #plain.Pets == 3 and plain.Pets[1].HpFraction == nil, "ring no-heal service: without hpByKey every pet starts full")
	bs.StartRaid = realRaid
	K.flushErrors("ringnh_service")
	K.flushWarnings("ringnh_service", { "[BattleService]", "[DataService]", "[TycoonService]", "[PetCareService]", "[MeshLibrary]" })
	K.removePlayers({ a })
	K.advance(5)
	-- this test climber leaves the server's RingBoard to the p4ring scenarios that follow (it keeps the best 3)
	local St = svcState()
	if St and type(St.ringBoard) == "table" then
		St.ringBoard[971000 + seq] = nil
	end
end)

return S
