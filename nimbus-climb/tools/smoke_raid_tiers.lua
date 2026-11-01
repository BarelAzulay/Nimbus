-- smoke_raid_tiers.lua: boss raids, Task 1 (docs/superpowers/specs/2026-11-01-raid-boss-design.md: shared/BattleCatalog.lua +
-- shared/BattleSim.lua), loaded by tools/smoke.py in the SERVER world as pure scenarios.
--   raid_tiers   the four fight tiers (the level bands, the team's highest pet, the dare rule), the spec's numbers, the
--                rewards scaled per tier, Raid / Events rules, every boss: no EnrageAt / HpPerPlayer, one lethal attack;
--                BossHp + BaselineDps per tier; Validate (and a broken lethal fails it)
--   raid_lethal  BattleSim RaidTier (size, hits, minions, BossStatus Tier / Lethal), the enrage at 30% health instead of on a
--                clock, the lethal telegraph: >= 3 s of warning, kills a fighter that stands in it whatever its HP / shield /
--                Defense, never one that dashes, never lands within the dash cooldown of the previous telegraph
-- White-box: a few checks read battle.units / battle.boss (same Lua state). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K

local abs = math.abs
local fmt = string.format

local S = {}

local DT = 0.1

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

-- a pet entry the way the server's copy of an active team looks
local function entry(petId, level, tier, evo, train)
	local key = (tier and tier ~= "Normal") and (petId .. "@" .. tier) or petId
	return { Key = key, PetId = petId, Level = level, Tier = tier, Evo = evo, Train = train }
end

local SIM_STARTER = { entry("aurora_fox", 18), entry("moonlit_owl", 17), entry("ember_phoenix", 16) }
local SIM_MID = { entry("ember_phoenix", 47, nil, 1), entry("twilight_dragon", 46, nil, 1), entry("aurora_fox", 45, "Golden", 1) }
local SIM_HIGH = { entry("cloudy_dragon", 77, "Golden", 2), entry("stormfang", 76, nil, 2), entry("eclipse_dragon", 75, nil, 2) }
local SIM_S1 = { entry("mallow_kitten", 1), entry("puddle_frog", 1), entry("pebble_pup", 1) }

local function team(owner, pets, flags)
	local list = {}
	for i, p in ipairs(pets) do
		local e = {}
		for k, v in pairs(p) do
			e[k] = v
		end
		e.Slot = i
		list[i] = e
	end
	local spec = { Owner = owner, Side = 1, Pets = list }
	for k, v in pairs(flags or {}) do
		spec[k] = v
	end
	return spec
end

local function firstEvent(events, kind, pred)
	for _, ev in ipairs(events) do
		if ev.type == kind and (pred == nil or pred(ev)) then
			return ev
		end
	end
	return nil
end

local function isLethal(ev)
	return ev.lethal == true
end

S.raid_tiers = guarded("raid_tiers", function()
	local BC, e1 = loadModule("BattleCatalog")
	if not T.check(BC ~= nil, "BattleCatalog loads", tostring(e1)) then
		return
	end
	if not T.check(type(BC.RaidTiers) == "table" and #BC.RaidTiers == 4 and BC.RaidTierOrder[4] == "Max", "raid tiers: four tiers Starter / Mid / High / Max") then
		return
	end
	for _, c in ipairs({ { 1, "Starter" }, { 19, "Starter" }, { 20, "Mid" }, { 49, "Mid" }, { 50, "High" }, { 79, "High" }, { 80, "Max" }, { 100, "Max" }, { 0, "Starter" }, { 250, "Max" }, { "junk", "Starter" } }) do
		T.eq(BC.RaidTierOf(c[1]).Id, c[2], "raid tiers: level " .. tostring(c[1]) .. " -> " .. c[2])
	end
	T.eq(BC.RaidTierOf(0 / 0).Id, "Starter", "raid tiers: a NaN level -> Starter")
	local tier, lvl = BC.RaidTierOfTeam({ { Level = 3 }, { Level = 52 }, { Level = 20 } })
	T.check(tier.Id == "High" and lvl == 52, "raid tiers: a team is tiered by its highest pet")
	T.check(BC.RaidTierOfTeam({}).Id == "Starter" and BC.RaidTierOfTeam(nil).Id == "Starter" and select(2, BC.RaidTierOfTeam({})) == 1 and BC.RaidTierOfTeam({ { Level = "x" }, 7 }).Id == "Starter", "raid tiers: an empty / junk team is Starter, level 1")
	T.check(BC.RaidTierById("Mid").Id == "Mid" and BC.RaidTierById("Gold") == nil and BC.RaidTierById(7) == nil and BC.RaidTierById(nil) == nil, "raid tiers: RaidTierById knows the four ids only")
	T.check(BC.RaidTierIndex("Starter") == 1 and BC.RaidTierIndex("Max") == 4 and BC.RaidTierIndex("Gold") == nil, "raid tiers: RaidTierIndex is 1..4 | nil")
	T.check(BC.RaidCanDare("Starter", "Mid") and BC.RaidCanDare("Mid", "Max") and not BC.RaidCanDare("Mid", "Mid") and not BC.RaidCanDare("High", "Mid") and not BC.RaidCanDare("Mid", "Gold") and not BC.RaidCanDare(nil, "Max"), "raid tiers: a dare is a strictly higher known tier")
	local want = { Starter = { 15, 0.6, 0.4, 0.5 }, Mid = { 40, 0.8, 0.7, 0.5 }, High = { 70, 1, 1, 1 }, Max = { 95, 1.3, 1.3, 1 } }
	for id, w in pairs(want) do
		local t = BC.RaidTierById(id)
		T.check(t.BossLevel == w[1] and t.Hit == w[2] and t.Reward == w[3] and t.EventScale == w[4], "raid tiers: " .. id .. " boss level / hit / reward / event scale per the spec")
	end
	T.check(BC.RaidTierById("Max").Crown == true and BC.RaidTierById("Max").Scale > BC.RaidTierById("Starter").Scale, "raid tiers: Max wears the crown and tiers grow in size")
	-- rewards by tier
	local gold = BC.RaidTier(0.5, true, "Starter")
	T.check(gold.Id == "Gold" and gold.Tokens == 200 and gold.Xp == 160 and gold.Gems == 4 and abs(gold.GemChance - 0.125) < 1e-9 and abs(gold.EventPetChance - 0.025) < 1e-9 and gold.FightTier == "Starter" and gold.Scale == 0.4, "raid rewards: Starter Gold = 500/400/10 x0.4, chances x0.5")
	local maxGold = BC.RaidTier(0.5, true, "Max")
	T.check(maxGold.Tokens == 650 and maxGold.Xp == 520 and maxGold.Gems == 13 and abs(maxGold.GemChance - 0.25) < 1e-9, "raid rewards: Max Gold = x1.3, chances x1")
	T.check(BC.RaidTier(0.5, true).Tokens == 500 and BC.Raid.Tiers[1].Tokens == 500 and BC.RaidTier(0.5, true).FightTier == "High", "raid rewards: no tier = High (x1); the medal table itself is untouched")
	T.check(BC.RaidTier(0.5, true, "Gold").FightTier == "High", "raid rewards: a junk tier = High")
	local loss = BC.RaidTier(0.1, false, "Mid")
	T.check(loss.Id == "Loss" and loss.Tokens == 18 and loss.Xp == 14, "raid rewards: the Mid loss reward = 25/20 x0.7 (rounded)", loss and fmt("%s %s", tostring(loss.Tokens), tostring(loss.Xp)))
	T.check(BC.RaidTier(0, true, "Max") == nil, "raid rewards: no damage, no medal")
	T.check(BC.Raid.ReturnSeconds == 60 and BC.Raid.RewardMinutes == 20 and BC.Raid.LossMinutes == 5 and BC.Raid.MaxRaiders == 8, "raid rules: return 60 s, rewards 20 min, loss 5 min, 8 raiders")
	T.check(BC.Events.JoinWindowSeconds == nil and BC.Events.Schedule[1].Kind == "BossRaid" and BC.Events.Schedule[1].EveryMinutes == 20 and BC.Events.Schedule[1].AnnounceSeconds == nil and BC.Events.Schedule[2].Kind == "DoubleRewards", "raid events: no join window, the BossRaid row is the 20 minute rotation, Double Rewards keeps its row")
	-- boss numbers
	for _, id in ipairs(BC.BossOrder) do
		local b = BC.Bosses[id]
		T.check(b.EnrageAt == nil and b.HpPerPlayer == nil and type(b.Lethal) == "table" and b.Lethal.Lethal == true and b.Lethal.Telegraph >= 3 and (b.Lethal.Count or 1) == 1 and b.Lethal.Damage == nil and b.Lethal.Cooldown >= 18, "raid boss " .. id .. ": no EnrageAt / HpPerPlayer, one lethal attack with >= 3 s of warning")
		T.check((b.Lethal.Shape == "Circle" and b.Lethal.Radius <= 10 and b.Lethal.Target == "Cluster") or (b.Lethal.Shape == "Line" and b.Lethal.Width <= 12), "raid boss " .. id .. ": the lethal's shape is small enough for the dash's sidestep")
		local hpHigh = BC.BossHp(id, { { Pets = SIM_HIGH } }, "High")
		local hpStart = BC.BossHp(id, { { Pets = SIM_STARTER } }, "Starter")
		T.check(hpStart < hpHigh and BC.BaselineDps(id, "Starter") < BC.BaselineDps(id, "Max"), "raid boss " .. id .. ": a Starter boss is smaller than a High one, the HP floor grows per tier")
		T.check(BC.BossHp(id, { { Pets = SIM_S1 } }, "Mid") >= BC.BossRules.FloorSeconds * BC.BaselineDps(id, "Mid") - 1, "raid boss " .. id .. ": a dare meets the dared tier's HP floor")
		T.check(BC.BossHp(id, { { Pets = SIM_HIGH } }) == hpHigh and BC.BaselineDps(id) == BC.BaselineDps(id, "High"), "raid boss " .. id .. ": no tier = High")
		local own = BC.RaidTierById("Mid").HpSeconds * b.HpFactor * BC.ExpectedDps({ Pets = SIM_MID })
		local hpMid = BC.BossHp(id, { { Pets = SIM_MID } }, "Mid")
		T.check(hpMid == BC.BossHp(id, { { Pets = SIM_S1 } }, "Mid") or abs(hpMid - own) <= 1, "raid boss " .. id .. ": a solo above the floor keeps HpSeconds x HpFactor seconds of its own DPS", fmt("%d vs %.0f", hpMid, own))
	end
	T.check(BC.Bosses.lava_golem.HpFactor < BC.Bosses.storm_titan.HpFactor, "raid boss: the Lava Golem keeps its lower HP (HpFactor)")
	T.check(BC.BossRules.EnrageAt == 0.3 and BC.BossRules.Baseline == nil and BC.BossRules.Enrage.LethalFirst == 4, "raid boss rules: enrage at 30% health, no single baseline")
	local ok, problems = BC.Validate()
	T.check(ok, "raid catalog: Validate passes", ok and "" or table.concat(problems, "; "))
	-- Validate catches a lethal that breaks the promise of a warning
	local lethal = BC.Bosses.storm_titan.Lethal
	local savedTelegraph, savedDamage = lethal.Telegraph, lethal.Damage
	lethal.Telegraph = 2
	local okShort = BC.Validate()
	lethal.Telegraph = savedTelegraph
	lethal.Damage = 0.5
	local okDamage = BC.Validate()
	lethal.Damage = savedDamage
	T.check(okShort == false and okDamage == false, "raid catalog: Validate refuses a lethal with a short warning or a Damage field")
	local band = BC.RaidTiers[2].Level[1]
	BC.RaidTiers[2].Level[1] = 21
	local okBand = BC.Validate()
	BC.RaidTiers[2].Level[1] = band
	T.check(okBand == false, "raid catalog: Validate refuses a gap in the tier levels")
end)

-- a Mid raid stepped by hand; drive(b, events) runs after every step, stop(b, events) ends it
local function runRaid(BS, setup, steps, drive)
	local b = BS.new(setup)
	local all = {}
	for i = 1, steps do
		local evs = b:Step(DT)
		for _, ev in ipairs(evs) do
			all[#all + 1] = ev
		end
		if drive and drive(b, evs, i) == true then
			break
		end
		if b:IsFinished() then
			break
		end
	end
	return b, all
end

-- keeps a fight going: the boss stays at `frac` and the fighter never falls to anything but a lethal
local function hold(b, owner, frac)
	b.boss.hp = frac * b.boss.maxHp
	local f = b.teamByOwner[owner].fighter
	if f and f.alive then
		f.maxHp = 1e7
		f.hp = 1e7
	end
end

S.raid_lethal = guarded("raid_lethal", function()
	local BC, e1 = loadModule("BattleCatalog")
	local BS, e2 = loadModule("BattleSim")
	if not T.check(BC ~= nil and BS ~= nil, "BattleCatalog + BattleSim load", tostring(e1 or e2)) then
		return
	end
	if not T.check(type(BC.RaidTierById) == "function", "raid lethal: the tiers exist") then
		return
	end
	-- RaidTier on the boss unit
	local function raidOf(tierId, bossId)
		return BS.new({ Mode = "Raid", Boss = bossId or "storm_titan", RaidTier = tierId, Seed = 3, Specials = false, Teams = { team(1, SIM_MID) } })
	end
	local bMax, bHigh, bStart, bJunk = raidOf("Max"), raidOf(nil), raidOf("Starter"), raidOf("Gold")
	T.check(bMax:BossStatus().Tier == "Max" and bHigh:BossStatus().Tier == "High" and bStart:BossStatus().Tier == "Starter" and bJunk:BossStatus().Tier == "High", "raid tier: BossStatus().Tier; no tier or a junk one = High")
	T.check(bMax:BossStatus().Lethal == false and bMax:BossStatus().Enraged == false, "raid tier: BossStatus().Lethal starts false")
	local def = BC.Bosses.storm_titan
	T.check(abs(bMax.boss.radius - def.Radius * BC.RaidTierById("Max").Scale) < 1e-9 and abs(bStart.boss.radius - def.Radius * BC.RaidTierById("Starter").Scale) < 1e-9, "raid tier: the boss's radius grows with the tier's Scale")
	T.check(bMax.boss.damageMult == 1.3 and bHigh.boss.damageMult == 1 and bStart.boss.damageMult == 0.6, "raid tier: the boss hits x the tier's Hit")
	T.check(bMax:BossStatus().MaxHp == BC.BossHp("storm_titan", { { Pets = SIM_MID } }, "Max") and bStart:BossStatus().MaxHp == BC.BossHp("storm_titan", { { Pets = SIM_MID } }, "Starter"), "raid tier: the sim's boss HP is BossHp for that tier")
	bMax:AddTeam(team(2, SIM_MID))
	T.check(bMax:BossStatus().MaxHp == BC.BossHp("storm_titan", { { Pets = SIM_MID }, { Pets = SIM_MID } }, "Max"), "raid tier: a join keeps the tier's boss HP")
	-- minions hit x the tier's Hit
	local minionHit = {}
	for _, id in ipairs({ "High", "Max" }) do
		local b = raidOf(id)
		b.boss.hp = 0.69 * b.boss.maxHp
		local evs = b:Step(DT)
		local spawn = firstEvent(evs, "Spawn")
		local u = spawn and b.units[spawn.units[1].id]
		minionHit[id] = u and u.hit or 0
	end
	T.check(minionHit.High > 0 and abs(minionHit.Max / minionHit.High - 1.3) < 1e-6, "raid tier: minion hits x the tier's Hit", fmt("%.2f / %.2f", minionHit.Max, minionHit.High))
	-- ... and a join's rescale keeps it
	local bJoin = raidOf("Max")
	bJoin.boss.hp = 0.69 * bJoin.boss.maxHp
	local spawnJoin = firstEvent(bJoin:Step(DT), "Spawn")
	bJoin:AddTeam(team(2, SIM_MID))
	local joined = spawnJoin and bJoin.units[spawnJoin.units[1].id]
	local groupLo = BC.BossRules.DamageGroup.Min
	T.check(joined and abs(joined.hit / minionHit.Max - (groupLo + (1 - groupLo) / 7) / groupLo) < 1e-6, "raid tier: a join's rescale of the minions keeps the tier's Hit", joined and fmt("%.2f vs %.2f", joined.hit, minionHit.Max) or "no minion")

	-- no enrage on a clock: 260 s (past the old EnrageAt 240) above 30% health
	local enragedEarly = false
	local bClock = runRaid(BS, { Mode = "Raid", Boss = "storm_titan", RaidTier = "Mid", Seed = 3, Specials = false, Teams = { team(1, SIM_MID) } }, 2600, function(b, evs)
		hold(b, 1, 0.31)
		enragedEarly = enragedEarly or firstEvent(evs, "Enrage") ~= nil or b:BossStatus().Enraged
	end)
	T.check(not enragedEarly and bClock.timeLimit == 330, "raid lethal: no enrage before 30% (330 s limit untouched)", tostring(bClock.timeLimit))

	-- the enrage + the first lethal telegraph
	local enrageT, sawEnrageBefore, lethalPending, standHit, standKo, tele, status = nil, false, false, nil, false, nil, nil
	local fighterId = nil
	runRaid(BS, { Mode = "Raid", Boss = "storm_titan", RaidTier = "Mid", Seed = 3, Specials = false, Teams = { team(1, SIM_MID) } }, 400, function(b, evs, i)
		if firstEvent(evs, "Enrage") then
			if i <= 50 then
				sawEnrageBefore = true
			end
			enrageT = enrageT or b:Time()
			status = b:BossStatus()
		end
		if i == 50 then
			b.boss.hp = 0.29 * b.boss.maxHp
		elseif i < 50 then
			b.boss.hp = b.boss.maxHp
		end
		local f = b.teamByOwner[1].fighter
		if not tele then
			tele = firstEvent(evs, "Telegraph", isLethal)
			if tele then
				lethalPending = b:BossStatus().Lethal
				fighterId = f.id
				f.maxHp, f.hp, f.shield, f.shieldUntil = 1e6, 1e6, 500, 1e6 -- whole HP + shield: the kill ignores them
				f.defense = 0.3
			elseif f.alive then
				f.hp = f.maxHp
			end
		else
			local hit = firstEvent(evs, "Hit", function(e)
				return e.lethal == true and e.to == fighterId
			end)
			standHit = standHit or hit
			if firstEvent(evs, "KO", function(e)
				return e.unit == fighterId
			end) then
				standKo = true
				return true
			end
		end
	end)
	T.check(enrageT ~= nil and status and status.Enraged == true, "raid lethal: the boss enrages at 30% health, not on a clock")
	T.check(not sawEnrageBefore, "raid lethal: no enrage before 30%")
	T.check(tele ~= nil and tele.hits >= 3 and tele.at - tele.hits - (enrageT or 0) >= BC.BossRules.Enrage.LethalFirst - 0.11, "raid lethal: the lethal telegraph comes LethalFirst s after the enrage with >= 3 s of warning", tele and fmt("%.1f after the enrage, %.1f s warning", tele.at - tele.hits - (enrageT or 0), tele.hits) or "none")
	T.check(lethalPending == true, "raid lethal: BossStatus().Lethal is true while the lethal telegraph is pending")
	T.check(standKo and standHit and standHit.lethal == true and standHit.dmg >= 5e5, "raid lethal: a fighter that stands in it is knocked out by one lethal Hit, whatever its HP, shield and Defense", standHit and tostring(standHit.dmg) or "no hit")

	-- every boss: a standing fighter falls, a dashing one lives (a Dash 0.15 s before the hit: the i-frames / the sidestep)
	for _, bossId in ipairs(BC.BossOrder) do
		for _, dash in ipairs({ false, true }) do
			local lethal, ko, miss, dashed = nil, false, nil, false
			local fid = nil
			runRaid(BS, { Mode = "Raid", Boss = bossId, RaidTier = "Mid", Seed = 5, Specials = false, Teams = { team(1, SIM_MID) } }, 700, function(b, evs)
				local f = b.teamByOwner[1].fighter
				if not lethal then
					hold(b, 1, 0.29)
					lethal = firstEvent(evs, "Telegraph", isLethal)
					fid = f.id
				else
					b.boss.hp = 0.29 * b.boss.maxHp
					if dash and not dashed and b:Time() >= lethal.at - 0.16 then
						dashed = b:Command(1, "Dash")
					end
					miss = miss or firstEvent(evs, "Hit", function(e)
						return e.to == fid and e.miss == true and e.attack == lethal.attack
					end)
					if firstEvent(evs, "KO", function(e)
						return e.unit == fid
					end) then
						ko = true
					end
					if b:Time() >= lethal.at + 0.3 then
						return true
					end
				end
			end)
			if dash then
				T.check(lethal ~= nil and dashed and not ko, "raid lethal " .. bossId .. ": a Dash timed into the i-frames / out of the shape escapes it", fmt("dashed %s, ko %s, miss %s", tostring(dashed), tostring(ko), tostring(miss ~= nil)))
			else
				T.check(lethal ~= nil and ko, "raid lethal " .. bossId .. ": a fighter that stands still is knocked out", fmt("lethal %s, ko %s", tostring(lethal ~= nil), tostring(ko)))
			end
		end
	end

	-- 200 s of enraged play: the lethal comes back, never right after another telegraph's hit, and nothing overlaps it
	for _, bossId in ipairs(BC.BossOrder) do
		local list, noneWithin, overlap = {}, true, false
		local nextDash = {}
		local bLong, _ = runRaid(BS, { Mode = "Raid", Boss = bossId, RaidTier = "High", Seed = 9, Specials = false, TimeLimit = 400, Teams = { team(1, SIM_MID) } }, 2000, function(b, evs)
			hold(b, 1, 0.29)
			for _, ev in ipairs(evs) do
				if ev.type == "Telegraph" then
					local prev = list[#list]
					if prev and ev.at ~= prev.at then
						local gap = ev.at - prev.at
						if ev.lethal and gap < BC.Fighter.DashCooldown + 0.1 then
							noneWithin = false
						end
						if prev.at > b:Time() and (ev.lethal or prev.lethal) then
							overlap = true
						end
					end
					list[#list + 1] = ev
					if ev.lethal then
						nextDash[#nextDash + 1] = ev.at - 0.15
					end
				end
			end
			if nextDash[1] and b:Time() >= nextDash[1] then
				table.remove(nextDash, 1)
				b:Command(1, "Dash")
			end
		end)
		local casts = 0
		for _, ev in ipairs(list) do
			if ev.lethal then
				casts = casts + 1
			end
		end
		local alive = bLong.teamByOwner[1].fighter.alive
		T.check(casts >= 4 and noneWithin and not overlap and alive, "raid lethal " .. bossId .. ": no lethal lands within DashCooldown + 0.1 s of the previous telegraph's hit, nothing overlaps it, a fighter that dashes each one lives", fmt("%d casts, alive %s", casts, tostring(alive)))
	end

	-- the same seed + commands replay the same lethal
	local function replay()
		local _, all = runRaid(BS, { Mode = "Raid", Boss = "frost_wyrm", RaidTier = "Max", Seed = 11, Specials = false, Teams = { team(1, SIM_MID) } }, 200, function(b, _, i)
			if i == 20 then
				b.boss.hp = 0.2 * b.boss.maxHp
			end
		end)
		local parts = {}
		for _, ev in ipairs(all) do
			parts[#parts + 1] = ev.type .. ":" .. tostring(ev.dmg)
		end
		return table.concat(parts, ",")
	end
	T.check(replay() == replay(), "raid lethal: the same setup replays the same fight")
end)

return S
