-- smoke_p5_looks.lua: Phase 5 careui (ARCHITECTURE_V3.md "Phase 5 build contract" 3.7, 4.8, 6.6, m17; careui W3).
-- Loaded by tools/smoke.py in the server world and the client world:
--   p5looks_podium         (server) the Pet Podium draws the owner's best pet at its STORED stage: an EVOLVE rebuilds it
--                          evolved at Low (PB_Evolved == stage, PB_Detail Low) through PetCareService.Evolved / Refresh
--   client_p5looks         every careui site that draws an OWNED pet draws its stored stage, evolved at Low: the Pets grid
--                          slot (EvolvedView) and the detail card, the Index tile + detail (State.BestStage), the Team
--                          card + picker tiles, the Fusion tiles, the Food Machine / garden / Training rows and the roulette
--                          reveal of an evolved key (+ the gold "Evolved" ribbon). (Garden pets, followers, the Ring cards
--                          and battle units belong to homefx / pets / dungeonclient / battleclient and their own tests.)
--   client_p5support_power the Pets panel detail of an Economy (Support) pet shows "Battle power N" = BattleCatalog.UnitPower
--                          (its Support role), never the raw Power 2-4 (m17)
--   client_p5team3         the Team window: 3 slot cards (no 4th), FIGHTER / HELPER / HELPER, "Set as fighter" rotates
--                          the preset so that pet leads (BattleRequest TeamSet), only on the helpers
--   client_p5menu_tiles    the menu: a 2 x 3 grid of neon tiles (Pets, Items, Team / Index, Shop, Home) + a small row (Stats,
--                          Settings), names MenuButton_<Id> kept, every window docked by NeonKit.Dock (DockMode, right of
--                          the middle / a bottom sheet), no Backdrop anywhere
-- Deterministic: fixed pets / keys, no RNG, no reliance on other scenarios. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

-- every Model carrying PB_Evolved under `root` (pet viewports hold the PetBuilder clone)
local function petModels(root)
	local out = {}
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d:IsA("Model") and d:GetAttribute("PB_Evolved") ~= nil then
			out[#out + 1] = d
		end
	end
	return out
end

local function evolvedModel(root, stage)
	for _, m in ipairs(petModels(root)) do
		if m:GetAttribute("PB_Evolved") == stage then
			return m
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local advance, mod = K.advance, K.mod

	S.p5looks_podium = guarded("p5looks_podium", function()
		local SS, DS, PC = mod("SpotService"), mod("DataService"), K.M["shared/PetCatalog"]
		if not T.check(SS and DS and type(DS.SetEvolution) == "function" and type(SS.Refresh) == "function",
			"p5looks podium: SpotService (Refresh) and DataService (SetEvolution) load") then
			return
		end
		local P = K.freshPlayers(1, "Looky")[1]
		local free = nil
		for i = 1, 16 do
			local taken = false
			for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
				local sp = SS.GetSpot(other)
				if sp and sp.Index == i then
					taken = true
				end
			end
			if not taken and SS.GetSpotByIndex(i) then
				free = i
				break
			end
		end
		local ok = free and SS.Claim(P, free)
		local spot = SS.GetSpot(P)
		if not T.check(ok and spot ~= nil, "p5looks podium: the owner claims a home") then
			K.removePlayers({ P })
			return
		end
		-- one pet that can reach Evolved II (the podium shows the owner's best pet)
		local petId = nil
		for _, def in ipairs(PC.ListByRarity("Legendary")) do
			if not def.EventOnly and (PC.MaxEvolution(def) or 0) >= 2 then
				petId = def.Id
				break
			end
		end
		local entry = DS.GetEntry and DS.GetEntry(P)
		local profile = (entry and entry.Profile) or (DS.GetProfile and DS.GetProfile(P))
		if not T.check(petId and profile, "p5looks podium: a Legendary pet with two evolutions and a loaded profile") then
			K.removePlayers({ P })
			return
		end
		profile.Pets[petId] = 1
		profile.PetLevels = profile.PetLevels or {}
		profile.PetLevels[petId] = { Level = 100, Xp = 0 }
		DS.MarkDirty(P)
		SS.Refresh(P)
		advance(1.2)
		local show = spot.Folder:FindFirstChild("ShowcasePet", true)
		T.check(show and (show:GetAttribute("PB_Evolved") or 0) == 0, "p5looks podium: a plain pet stands on the podium (PB_Evolved 0)",
			show and tostring(show:GetAttribute("PB_Evolved")) or "no pet")
		for stage = 1, 2 do
			T.check(DS.SetEvolution(P, petId, stage), "p5looks podium: the stored stage rises to " .. stage)
			SS.Refresh(P)
			advance(1.2)
			show = spot.Folder:FindFirstChild("ShowcasePet", true)
			T.check(show and show:GetAttribute("PB_Evolved") == stage and show:GetAttribute("PB_Detail") == "Low",
				"p5looks podium: ...and the podium pet is rebuilt evolved (stage " .. stage .. ") at Low",
				show and (tostring(show:GetAttribute("PB_Evolved")) .. " " .. tostring(show:GetAttribute("PB_Detail"))) or "no pet")
		end
		K.removePlayers({ P })
		advance(0.5)
		K.flushErrors("p5looks_podium")
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
	local function advance(seconds)
		if KC and KC.advance then
			KC.advance(seconds)
		else
			Mock.Advance(seconds)
		end
	end
	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end
	local function pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	local function find(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function shown(obj)
		local cur = obj
		while cur and cur ~= game do
			if cur:IsA("LayerCollector") then
				if cur.Enabled == false then
					return false
				end
			elseif cur:IsA("GuiObject") and cur.Visible == false then
				return false
			end
			cur = cur.Parent
		end
		return true
	end
	local function toClient(name, ...)
		Mock.ToClient(ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild(name), ...)
	end
	local function calls(name, mark)
		local out = {}
		for i = (mark or 0) + 1, #Mock.RemoteLog do
			local e = Mock.RemoteLog[i]
			if e.kind == "server" and e.remote == name then
				out[#out + 1] = e
			end
		end
		return out
	end

	local PetCatalog = moduleAt("shared", "PetCatalog")
	local Config = moduleAt("shared", "Config")
	local BC = moduleAt("shared", "BattleCatalog")

	-- the cast (fixed ids): E1 an Epic at stage 1, L2 a Legendary at stage 2, C a plain Common, ECO an Economy pet
	local P = {}
	local function firstOf(rarity, skip, role)
		for _, def in ipairs(PetCatalog.Pets) do
			if def.Rarity == rarity and not def.EventOnly and def.Id ~= skip and (role == nil or def.Role == role) then
				return def.Id
			end
		end
		return nil
	end
	P.E1 = firstOf("Epic")
	P.L2 = nil
	for _, def in ipairs(PetCatalog.Pets) do
		if def.Rarity == "Legendary" and not def.EventOnly and (PetCatalog.MaxEvolution(def) or 0) >= 2 and not P.L2 then
			P.L2 = def.Id
		end
	end
	P.C = firstOf("Common")
	P.ECO = firstOf("Common", P.C, "Economy") or firstOf("Uncommon", nil, "Economy")

	local plot = nil
	local function sync(extra)
		local pets, levels = {}, {}
		for _, id in pairs(P) do
			pets[id] = 1
			levels[id] = { Level = 30, Xp = 10 }
		end
		levels[P.L2] = { Level = 100, Xp = 0 }
		local lobby = workspace:FindFirstChild("NimbusLobby") or Instance.new("Folder")
		lobby.Name = "NimbusLobby"
		lobby.Parent = workspace
		if not plot or not plot.Parent then
			plot = Instance.new("Folder")
			plot.Name = "Spot_11"
			plot:SetAttribute("SpotIndex", 11)
			plot.Parent = lobby
		end
		plot:SetAttribute("IncomePerSecond", 40)
		plot:SetAttribute("GardenSlots", 4)
		plot:SetAttribute("BerryCap", 3000)
		LocalPlayer:SetAttribute(Config.Attr.SpotIndex, 11)
		LocalPlayer:SetAttribute(Config.Attr.Berries or "Berries", 2000)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		local snap = {
			Tokens = 900, Pets = pets, Equipped = { P.C }, Items = {}, Discovered = pets, IndexClaimed = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 500000, Gems = 50, Berries = 2000,
			Home = { Level = 25, Prestige = 1, Stations = { Garden = 3, Press1 = 13, Kitchen = 2, Gym = 2, Vault = 1, House = 2, FusionMachine = 1 },
				Garden = { P.E1, P.L2, "", "" }, Gym = {} },
			PetLevels = levels,
			PetGrowth = { [P.E1] = { Evo = 1 }, [P.L2] = { Evo = 2 } },
			Teams = { Presets = { { P.C, P.E1, P.L2 }, {}, {} }, Active = 1, Slots = 3 },
		}
		for k, v in pairs(extra or {}) do
			snap[k] = v
		end
		toClient("ProfileSync", snap)
		advance(0.5)
		return snap
	end

	local function mods()
		local M = KC and KC.M or {}
		return M.MenuController or moduleAt("client", "Controllers/MenuController"),
			M.CareController or moduleAt("client", "Controllers/CareController"),
			M.IndexController or moduleAt("client", "Controllers/IndexController"),
			M.FusionController or moduleAt("client", "Controllers/FusionController")
	end
	local function closeAll()
		local MC, CC, IC, FC = mods()
		for _, m in ipairs({ MC, CC, IC, FC }) do
			if m and type(m.Close) == "function" then
				pcall(m.Close)
			end
		end
		advance(0.4)
	end
	local function lowAt(m, stage)
		return m ~= nil and m:GetAttribute("PB_Evolved") == stage and m:GetAttribute("PB_Detail") == "Low"
	end

	------------------------------------------------------------------------------------------------
	S.client_p5looks = guarded("client_p5looks", function()
		local MC, CC, IC, FC = mods()
		if not T.check(MC and CC and P.E1 and P.L2 and P.C, "p5looks: MenuController, CareController and the cast load") then
			return
		end
		Mock.SetViewport(1920, 1080)
		closeAll()
		sync()
		local State = moduleAt("client", "State")
		T.check(State.PetStage(P.E1) == 1 and State.PetStage(P.L2) == 2 and State.PetStage(P.C) == 0 and State.BestStage(P.L2) == 2,
			"p5looks: State.PetStage / BestStage read the stored stages (1, 2, 0)")
		local menu = pg():FindFirstChild("NimbusMenu")
		-- the Pets grid + detail
		MC.Open("Pets", { Key = P.L2 })
		advance(2.5)
		local inv = menu:FindFirstChild("Window_Inventory")
		local s1, s2, s0 = find(inv, "Pet_" .. P.E1), find(inv, "Pet_" .. P.L2), find(inv, "Pet_" .. P.C)
		T.check(lowAt(evolvedModel(s1 and find(s1, "EvolvedView"), 1), 1) and lowAt(evolvedModel(s2 and find(s2, "EvolvedView"), 2), 2),
			"p5looks pets: the grid slots of evolved keys draw the evolved form at Low (stage 1, stage 2)")
		T.check(s0 and find(s0, "EvolvedView") == nil and evolvedModel(s0, 1) == nil and evolvedModel(s0, 2) == nil, "p5looks pets: ...a plain key keeps its normal model")
		local cnt = s1 and find(s1, "Count")
		T.check(not (cnt and shown(cnt) and cnt.Text == "x1"), "p5looks pets: an evolved single copy shows no 'x1' (like a plain one)", cnt and cnt.Text or "")
		local holder = find(inv, "ViewportHolder")
		T.check(lowAt(evolvedModel(holder, 2), 2), "p5looks pets: the detail card draws the selected pet's stage (2, Low)")
		closeAll()
		-- the Index (BestStage)
		if IC and IC.Open then
			local def = PetCatalog.Get(P.L2)
			IC.Open(def.Rarity)
			advance(2.5)
			local ig = pg():FindFirstChild("NimbusIndex")
			T.check(lowAt(evolvedModel(ig, 2), 2), "p5looks index: the tile / detail of a pet draws its best owned stage (BestStage 2, Low)")
			closeAll()
		end
		-- the Team card + picker tiles
		MC.Open("Team", {})
		advance(2.5)
		local tw = menu:FindFirstChild("Window_Team")
		local card3 = tw and find(tw, "Slot3")
		T.check(lowAt(evolvedModel(card3, 2), 2), "p5looks team: the slot card draws the evolved pet at Low")
		local tile = tw and find(tw, "Pick_" .. P.E1)
		T.check(lowAt(evolvedModel(tile, 1), 1), "p5looks team: ...and its picker tile")
		closeAll()
		-- the Fusion tiles
		if FC and FC.Open then
			FC.Open("Upgrade", {})
			advance(2.5)
			local fg = pg():FindFirstChild("NimbusFusion")
			T.check(evolvedModel(fg, 1) ~= nil and evolvedModel(fg, 2) ~= nil, "p5looks fusion: the picker tiles draw the copies' stages (1 and 2)")
			closeAll()
		end
		-- the care rows (Food Machine, garden picker, Training Place)
		for _, mode in ipairs({ "Feed", "Garden", "Train" }) do
			CC.Open(mode, { Slot = 3 })
			advance(2.5)
			local cw = pg():FindFirstChild("NimbusCare")
			T.check(lowAt(evolvedModel(cw, 1), 1) and lowAt(evolvedModel(cw, 2), 2), "p5looks care: the " .. mode .. " rows draw the evolved pets at Low")
			closeAll()
		end
		-- the roulette reveal of an evolved key: its stage + the gold ribbon
		toClient("RouletteResult", { Ok = true, PetId = P.E1, IsNew = false, Count = 2 })
		local ribbon = nil
		for _ = 1, 30 do
			advance(0.5)
			ribbon = find(menu, "EvolvedRibbon")
			if ribbon then
				break
			end
		end
		T.check(ribbon and shown(ribbon) and find(ribbon, "Text") and find(ribbon, "Text").Text:find("Evolved", 1, true),
			"p5looks reveal: rolling a copy of an evolved key shows the gold 'Evolved' ribbon")
		T.check(lowAt(evolvedModel(ribbon and ribbon.Parent, 1), 1), "p5looks reveal: ...and the evolved model (stage 1, Low)")
		closeAll()
		advance(1)
		KC.flushErrors("client_p5looks")
	end)

	------------------------------------------------------------------------------------------------
	S.client_p5support_power = guarded("client_p5support_power", function()
		local MC = mods()
		local def = P.ECO and PetCatalog.Get(P.ECO)
		if not T.check(MC and def and BC and type(BC.UnitPower) == "function", "p5support: an Economy pet and BattleCatalog.UnitPower") then
			return
		end
		closeAll()
		sync()
		MC.Open("Pets", { Key = P.ECO })
		advance(2)
		local inv = pg():FindFirstChild("NimbusMenu"):FindFirstChild("Window_Inventory")
		local pill = find(inv, "Stat_Power")
		local text = pill and (find(pill, "Text") or pill)
		text = text and (text:IsA("TextLabel") or text:IsA("TextButton")) and text.Text or ""
		if text == "" and pill then
			for _, d in ipairs(pill:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text ~= "" then
					text = d.Text
				end
			end
		end
		local want = BC.UnitPower({ Def = def, Key = P.ECO, Level = 30, Tier = "Normal", Evo = 0 })
		T.check(text:find("^Battle power ") ~= nil, "p5support: the detail shows 'Battle power' (not the raw Power)", text)
		local n = tonumber((text:gsub("^Battle power ", ""):gsub(",", "")))
		T.check(n == math.floor(want + 0.5) and n ~= def.Stats.Power, "p5support: ...= BattleCatalog.UnitPower with the Support role (" .. tostring(want) .. "), never the raw Power " .. tostring(def.Stats.Power), text)
		closeAll()
		KC.flushErrors("client_p5support_power")
	end)

	------------------------------------------------------------------------------------------------
	S.client_p5team3 = guarded("client_p5team3", function()
		local MC = mods()
		closeAll()
		sync()
		MC.Open("Team", {})
		advance(2)
		local tw = pg():FindFirstChild("NimbusMenu"):FindFirstChild("Window_Team")
		local cards = {}
		for i = 1, 4 do
			cards[i] = tw and find(tw, "Slot" .. i)
		end
		T.check(cards[1] and cards[2] and cards[3] and cards[4] == nil, "p5team3: three slot cards, no 4th slot")
		local function roleOf(card)
			local r = card and find(card, "Role")
			return r and find(r, "Text") and find(r, "Text").Text or "?"
		end
		T.eq(roleOf(cards[1]) .. "," .. roleOf(cards[2]) .. "," .. roleOf(cards[3]), "FIGHTER,HELPER,HELPER", "p5team3: slot 1 is the FIGHTER, slots 2-3 HELPERs")
		T.check(find(cards[1], "SetFighter") == nil and find(cards[2], "SetFighter") and find(cards[3], "SetFighter"),
			"p5team3: 'Set as fighter' sits on the helpers only")
		local btn = find(cards[3], "SetFighter")
		T.check(btn and shown(btn) and btn.Text == "Set as fighter", "p5team3: ...labelled 'Set as fighter'")
		local mark = #Mock.RemoteLog
		Mock.Click(btn)
		advance(1.2)
		local sent = calls("BattleRequest", mark)
		local last = sent[#sent]
		local keys = last and last.args[3] or {}
		T.check(last and last.args[1] == "TeamSet" and last.args[2] == 1 and keys[1] == P.L2 and keys[2] == P.C and keys[3] == P.E1,
			"p5team3: 'Set as fighter' on slot 3 rotates the preset {C, E1, L2} -> {L2, C, E1} (BattleRequest TeamSet)",
			table.concat(keys, ","))
		T.eq(roleOf(cards[1]), "FIGHTER", "p5team3: the labels stay with the slots")
		closeAll()
		KC.flushErrors("client_p5team3")
	end)

	------------------------------------------------------------------------------------------------
	S.client_p5menu_tiles = guarded("client_p5menu_tiles", function()
		local MC, CC, IC, FC = mods()
		closeAll()
		Mock.SetViewport(1920, 1080)
		advance(0.5)
		sync()
		local menu = pg():FindFirstChild("NimbusMenu")
		local column = menu and menu:FindFirstChild("MenuColumn")
		local function btn(id)
			local e = column and (column:FindFirstChild("Entry_" .. id) or column:FindFirstChild("Gear_" .. id))
			return e and e:FindFirstChild("MenuButton_" .. id, true)
		end
		local grid = { "Pets", "Inventory", "Team", "Index", "Shop", "Spot" }
		local okNames = true
		for _, id in ipairs(grid) do
			local b = btn(id)
			okNames = okNames and b ~= nil and b:IsA("TextButton")
		end
		T.check(okNames and btn("Stats") and btn("Settings"), "p5tiles: MenuButton_<Id> tiles kept (Pets, Items, Team, Index, Shop, Home) + Stats + the Settings gear")
		local function at(id)
			local b = btn(id)
			return b and b.AbsolutePosition or Vector2.new(-1, -1)
		end
		local a, b2, c = at("Pets"), at("Inventory"), at("Team")
		T.check(math.abs(a.Y - b2.Y) < 1 and b2.X > a.X and math.abs(c.X - a.X) < 1 and c.Y > a.Y
			and math.abs(at("Index").Y - c.Y) < 1 and at("Shop").Y > c.Y and math.abs(at("Spot").Y - at("Shop").Y) < 1,
			"p5tiles: a 2 x 3 grid (Pets | Items, Team | Index, Shop | Home)")
		T.check(at("Stats").Y > at("Shop").Y and math.abs(at("Settings").Y - at("Stats").Y) < 1, "p5tiles: the small row (Stats, Settings) under the grid")
		local pets = btn("Pets")
		T.check(pets and math.abs(pets.AbsoluteSize.X - 84) <= 2, "p5tiles: tiles are 84 px on a 1080p screen", pets and tostring(pets.AbsoluteSize) or "")
		local label = pets and pets:FindFirstChild("Label", true)
		T.check(label and label.Text == "Pets", "p5tiles: ...with their labels")
		-- every window docked by the window rule, no backdrop
		local function holders()
			local out = {
				menu:FindFirstChild("Window_Inventory"), menu:FindFirstChild("Window_Home"), menu:FindFirstChild("Window_Team"),
			}
			return out
		end
		for _, size in ipairs({ { 1920, 1080 }, { 390, 844 } }) do
			Mock.SetViewport(size[1], size[2])
			advance(0.6)
			MC.Open("Pets", {})
			advance(0.8)
			local inv = menu:FindFirstChild("Window_Inventory")
			local mode = inv and inv:GetAttribute("DockMode")
			local rect = inv and inv.AbsolutePosition
			if size[1] > size[2] then
				T.check(mode == "Side" and rect.X >= 0.5 * size[1] - 1, "p5tiles: the Pets window docks right of the middle at " .. size[1] .. "x" .. size[2], tostring(mode) .. " x " .. tostring(rect and rect.X))
			else
				T.check(mode == "Sheet", "p5tiles: ...and is a bottom sheet at " .. size[1] .. "x" .. size[2], tostring(mode))
			end
			closeAll()
		end
		Mock.SetViewport(1920, 1080)
		advance(0.6)
		local backdrops, others = {}, {}
		local mine = { NimbusMenu = true, NimbusCare = true, NimbusIndex = true, NimbusFusion = true }
		for _, d in ipairs(pg():GetDescendants()) do
			if d.Name == "Backdrop" then
				local g = d:FindFirstAncestorOfClass("ScreenGui")
				if g and mine[g.Name] then
					backdrops[#backdrops + 1] = d:GetFullName()
				else
					others[#others + 1] = d:GetFullName()
				end
			end
		end
		T.check(#backdrops == 0, "p5tiles: no full-screen Backdrop in the menu / care / Index / Fusion guis", table.concat(backdrops, ", "))
		if #others > 0 then
			T.info("p5tiles: other owners' guis still carry a Backdrop (their wave): " .. table.concat(others, ", "))
		end
		-- the gear: never an error (MainMenuController's settings, or a hint until it exists)
		local errors0 = #Mock.Errors
		Mock.Click(btn("Settings"))
		advance(0.5)
		T.check(#Mock.Errors == errors0, "p5tiles: the Settings gear opens the settings (or says they are getting ready) without errors")
		closeAll()
		local _ = holders
		KC.flushErrors("client_p5menu_tiles")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
