-- smoke_tb_stats.lua: the battle-only stat path (team-balance plan, Task 1; spec 2026-10-31 s.5). Loaded by tools/smoke.py in
-- the server world (pure, no boot) and the client world:
--   tb_stats_formula      BattleCatalog.BattleStats / BattleLevelFactor / BattleStatsOf: the battle rarity scale and level
--                         curve, the tier and evolution rules; PetCatalog.GetStats, LevelFactor and Config.PetStats.RarityScale
--                         untouched (the garden); UnitStats, UnitPower and the champions read the battle path: a L30 Common
--                         out-powers a L1 Secret, a L100 evolved Common an unevolved L50 Secret, a Secret still leads at any
--                         equal level and stage
--   client_tb_stats_rows  one window never shows two answers: the Index and the Pets detail show the battle Power / Health, and
--                         keep the garden Coins (and Speed)
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local floor, abs = math.floor, math.abs

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
end

-- 12,345: the way the windows write a whole number
local function commas(n)
	local text = tostring(floor(n))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

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

	-- the same pairs as tools/sim_battle.lua's SIM.Commons / SIM.Secrets
	local SIM_COMMONS = { "mallow_kitten", "puddle_frog", "biscuit_bear", "pebble_pup", "pip_penguin", "honey_bunny" }
	local SIM_SECRETS = { "stormfang", "eclipse_dragon", "obsidian_phoenix", "phantom_kitsune" }

	S.tb_stats_formula = guarded("tb_stats_formula", function()
		local BC, PC, Config = req("shared/BattleCatalog"), req("shared/PetCatalog"), req("shared/Config")
		if not T.check(type(BC.BattleLevelFactor) == "function" and type(BC.BattleStatsOf) == "function" and type(BC.BattleStats) == "table", "tb stats: BattleLevelFactor / BattleStatsOf / BattleStats exist") then
			return
		end
		T.check(near(BC.BattleLevelFactor(1), 1, 1e-9) and near(BC.BattleLevelFactor(30), 1 + 0.12 * 29 + 0.0035 * 29 ^ 2 + 0.0002 * 29 ^ 3, 1e-9), "tb stats: L1 = 1, L30 = 1 + 0.12x + 0.0035x^2 + 0.0002x^3 (x = 29)")
		T.check(near(BC.BattleLevelFactor(100, 2), 1 + (0.12 * 99 + 0.0035 * 99 ^ 2 + 0.0002 * 99 ^ 3) * PC.EvolutionBonusOf(2), 1e-9), "tb stats: the evolution bonus multiplies the level part")
		T.check(near(BC.BattleLevelFactor(0), 1, 1e-9) and near(BC.BattleLevelFactor(1e9), BC.BattleLevelFactor(PC.MaxPetLevel()), 1e-9) and near(BC.BattleLevelFactor(5, "junk"), BC.BattleLevelFactor(5, 0), 1e-9), "tb stats: level clamped 1..MaxPetLevel, junk stage = 0")
		local scale = BC.BattleStats.RarityScale
		T.check(scale.Common == 1 and scale.Uncommon == 1.25 and scale.Rare == 1.6 and scale.Epic == 2.1 and scale.Legendary == 2.8 and scale.Mythic == 3.7 and scale.Secret == 5, "tb stats: the battle rarity scale 1 / 1.25 / 1.6 / 2.1 / 2.8 / 3.7 / 5")
		local s = BC.BattleStatsOf("stormfang", 1)
		local def = PC.Get("stormfang")
		T.check(s and near(s.Power, def.Stats.Power * 5, 1e-9) and near(s.Health, def.Stats.Health * 5, 1e-9) and s.Income == nil and s.Speed == def.Stats.Speed, "tb stats: a L1 Secret = base x 5 (battle scale), no Income, Speed unscaled")
		T.check(near(BC.BattleStatsOf("mallow_kitten@Golden", 1).Power, PC.Get("mallow_kitten").Stats.Power * 1.5, 1e-9), "tb stats: the key's tier multiplier applies")
		T.check(near(BC.BattleStatsOf("mallow_kitten", 1, "Rainbow").Power, PC.Get("mallow_kitten").Stats.Power * 2.5, 1e-9), "tb stats: an explicit tier applies")
		T.check(near(BC.BattleStatsOf("mallow_kitten", 50, nil, 2).Health, BC.BattleStatsOf("mallow_kitten", 50, nil, 1).Health, 1e-9), "tb stats: a Common at stored stage 2 counts as stage 1")
		T.check(BC.BattleStatsOf("no_such_pet", 1) == nil, "tb stats: an unknown pet = nil")
		-- garden numbers untouched
		T.check(near(PC.GetStats("stormfang", 10).Income, def.Stats.Income * Config.PetStats.RarityScale.Secret * PC.LevelFactor(10), 1e-9), "tb stats: PetCatalog.GetStats still uses RarityScale x LevelFactor (garden)")
		T.check(near(PC.LevelFactor(20, 1), 3.85, 1e-9) and Config.PetStats.RarityScale.Secret == 13, "tb stats: LevelFactor and Config.PetStats.RarityScale unchanged")
		-- UnitStats takes the battle path
		local us = BC.UnitStats("mallow_kitten", 30)
		T.check(near(us.MaxHp, BC.BattleStatsOf("mallow_kitten", 30).Health * BC.Damage.HpScale, 1e-6), "tb stats: UnitStats MaxHp = BattleStatsOf Health x HpScale")
		T.check(BC.UnitPower("mallow_kitten", 30) > BC.UnitPower("stormfang", 1), "tb stats: a L30 Common out-powers a L1 Secret")
		T.check(BC.UnitPower({ PetId = "mallow_kitten", Key = "mallow_kitten", Level = 100, Evo = 1 }) > BC.UnitPower("stormfang", 50), "tb stats: a L100 evolved Common out-powers an unevolved L50 Secret")
		for _, l in ipairs({ 1, 20, 50, 100 }) do
			for _, c in ipairs(SIM_COMMONS) do
				for _, sId in ipairs(SIM_SECRETS) do
					T.check(BC.UnitPower({ PetId = sId, Key = sId, Level = l, Evo = 2 }) > BC.UnitPower({ PetId = c, Key = c, Level = l, Evo = 2 }), "tb stats: a Secret stays stronger at equal level and stage (" .. sId .. " vs " .. c .. " L" .. l .. ")")
				end
			end
		end
		local champ = BC.ChampionTeam(20, 1).Pets[1]
		local role = BC.Roles[BC.RoleOf(champ.PetId)]
		T.check(near(BC.UnitStats(champ).MaxHp, BC.BattleStatsOf(champ.PetId, champ.Level, champ.Tier, champ.Evo).Health * role.Health * BC.Damage.HpScale, 1e-6), "tb stats: champions use the same path (a level means the same on both sides)")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = Players.LocalPlayer

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end
	local function find(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function pillText(pill)
		if pill and (pill:IsA("TextLabel") or pill:IsA("TextButton")) and pill.Text ~= "" then
			return pill.Text
		end
		for _, d in ipairs(pill and pill:GetDescendants() or {}) do
			if d:IsA("TextLabel") and d.Text ~= "" then
				return d.Text
			end
		end
		return ""
	end

	local function sync()
		local Config = moduleAt("shared", "Config")
		local pets = { stormfang = 1, mallow_kitten = 1 }
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		Mock.ToClient(ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("ProfileSync"), {
			Tokens = 900, Pets = pets, Equipped = { "mallow_kitten" }, Items = {}, Discovered = pets, IndexClaimed = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 500000, Gems = 50, Berries = 2000,
			PetLevels = { stormfang = { Level = 10, Xp = 0 }, mallow_kitten = { Level = 1, Xp = 0 } },
			PetGrowth = {},
			Teams = { Presets = { { "mallow_kitten" }, {}, {} }, Active = 1, Slots = 3 },
		})
		KC.advance(0.5)
	end

	S.client_tb_stats_rows = guarded("client_tb_stats_rows", function()
		local BC, PC = moduleAt("shared", "BattleCatalog"), moduleAt("shared", "PetCatalog")
		local IC = (KC.M and KC.M.IndexController) or moduleAt("client", "Controllers/IndexController")
		local MC = (KC.M and KC.M.MenuController) or moduleAt("client", "Controllers/MenuController")
		if not T.check(type(BC.BattleStatsOf) == "function", "tb stats: BattleCatalog.BattleStatsOf exists (client)") then
			return
		end
		sync()
		-- the Index: level 1 numbers of the catalog
		IC.Open("Secret")
		KC.advance(1.2)
		local indexGui = LocalPlayer.PlayerGui:FindFirstChild("NimbusIndex")
		local tile = find(indexGui, "IndexPet_stormfang")
		if not T.check(tile ~= nil, "tb stats: the Secret group lists stormfang") then
			IC.Close()
			return
		end
		Mock.Click(tile)
		KC.advance(0.5)
		local function indexRow(name)
			local row = find(indexGui, "Stat_" .. name)
			return { Value = row and find(row, "Value"), Fill = row and find(row, "Fill") }
		end
		local battle1, garden1 = BC.BattleStatsOf("stormfang", 1), PC.GetStats("stormfang", 1)
		T.check(indexRow("Power").Value.Text == commas(floor(battle1.Power + 0.5)), "tb stats: the Index Power row shows the battle number", indexRow("Power").Value.Text)
		T.check(indexRow("Health").Value.Text == commas(floor(battle1.Health + 0.5)), "tb stats: the Index Health row shows the battle number", indexRow("Health").Value.Text)
		T.check(indexRow("Income").Value.Text == commas(floor(garden1.Income + 0.5)), "tb stats: the Index Coins row keeps the garden number", indexRow("Income").Value.Text)
		T.check(indexRow("Speed").Value.Text == commas(floor(garden1.Speed + 0.5)), "tb stats: the Index Speed row keeps the garden number", indexRow("Speed").Value.Text)
		local top = 1
		for _, def in ipairs(PC.Pets) do
			top = math.max(top, BC.BattleStatsOf(def.Id, 1).Power)
		end
		T.check(near(indexRow("Power").Fill.Size.X.Scale, math.max(0.04, battle1.Power / top), 1e-6), "tb stats: the Index Power bar is relative to the top battle number", tostring(indexRow("Power").Fill.Size.X.Scale))
		IC.Close()
		KC.advance(0.4)
		-- the Pets detail: the pet's own level
		MC.Open("Pets", { Key = "stormfang" })
		KC.advance(2)
		local inv = LocalPlayer.PlayerGui:FindFirstChild("NimbusMenu"):FindFirstChild("Window_Inventory")
		local function detailRow(name)
			return pillText(find(inv, "Stat_" .. name))
		end
		local battle10 = BC.BattleStatsOf("stormfang", 10)
		-- the Power pill is "Battle power N" = UnitPower (m17, client_p5support_power), which reads the battle path
		local want = commas(floor(BC.UnitPower({ Def = PC.Get("stormfang"), Key = "stormfang", Level = 10, Tier = "Normal", Evo = 0 }) + 0.5))
		T.check(detailRow("Power") == "Battle power " .. want, "tb stats: the pet detail's Power row shows the battle number", detailRow("Power"))
		T.check(detailRow("Health") == "Health " .. commas(floor(battle10.Health + 0.5)), "tb stats: the pet detail's Health row shows the battle number", detailRow("Health"))
		T.check(detailRow("Speed") == "Speed " .. commas(floor(PC.GetStats("stormfang", 10).Speed + 0.5)), "tb stats: ...Speed keeps the garden number", detailRow("Speed"))
		T.check(detailRow("Income"):find("^Coins ") ~= nil, "tb stats: ...Coins keeps its garden pill", detailRow("Income"))
		MC.Close()
		KC.advance(0.4)
		KC.flushErrors("client_tb_stats_rows")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
