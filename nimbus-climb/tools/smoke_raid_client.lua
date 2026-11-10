-- smoke_raid_client.lua: boss raids, Task 4 (docs/superpowers/specs/2026-11-01-raid-boss-design.md: the client side). Loaded by tools/smoke.py in
-- the CLIENT worlds (desktop and the phone world), with the world's gate and floor stood in by a small stub (the client world has no server):
--   client_raid_gate    RaidGateController: the idle boss (dressed for my tier, only within range, gone during a floor fight and after a floor
--                       win, its head follows me, none of that on Low), the gate tag (boss, tier, rewards, the way in, the World text rule)
--   client_raid_dare    the dare panel: from the gate's prompt, the tiers above mine, Dare sends BattleRequest("RaidDare", tier) and closes, the
--                       top tier has nothing to dare, an empty team sends nothing, a fight's Start closes it
--   client_raid_panel   the Arena panel's Raid page: no Join, my tier, the reward state, the running fights, the next boss, the medals at my tier's
--                       numbers; no raid side card; the countdown chip is Double Rewards only
--   client_raid_enrage  BattleController fed by a real BattleSim: the local sky of a pocket fight, the tier in the mode line and on the boss, the red
--                       edges, the lethal telegraph (rim, pill, DASH! callout) on the sim's own Enrage and lethal Telegraph, the warning by the
--                       server's own hit test (the whole body counts, on either shape), a late joiner, Low
--   client_raid_sky     SkyController.SetLocalEvent: the local sky blends in and out like the server's, and hands over to the server's
--   client_raid_mobile  (phone world, 844x390) the dare buttons >= 44 px, under the top bar, no nested scrolling on the Raid page, the tag >= 14 px
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
if game:GetService("RunService"):IsServer() then
	return S
end

local KC = _G.KC
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local function req(path)
	local root, rest = path:match("^(%a+)/(.+)$")
	local inst = Mock.GetPath(ROOTS[root] .. "/" .. rest)
	local ok, result = pcall(function()
		return inst and require(inst)
	end)
	return ok and type(result) == "table" and result or nil
end

local function mod(name)
	return (KC.M and KC.M[name]) or req("client/Controllers/" .. name)
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

local function textOf(root)
	local out = {}
	if root and (root:IsA("TextLabel") or root:IsA("TextButton")) then
		out[#out + 1] = tostring(root.Text)
	end
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and KC.isShown(d) then
			out[#out + 1] = tostring(d.Text)
		end
	end
	return table.concat(out, " | ")
end

-- a text inside a BillboardGui (KC.isShown walks up to a ScreenGui)
local function tagText(gui)
	local out = {}
	for _, d in ipairs(gui and gui:GetDescendants() or {}) do
		if d:IsA("TextLabel") then
			out[#out + 1] = tostring(d.Text)
		end
	end
	return table.concat(out, " | ")
end

local function requests(mark, action)
	local out = {}
	for _, c in ipairs(KC.serverCalls("BattleRequest", mark)) do
		if c.args[1] == action then
			out[#out + 1] = c
		end
	end
	return out
end

local TEAM_MID = { ember_phoenix = 30, biscuit_bear = 20, sunbeam_bear = 10 }
local TEAM_MAX = { ember_phoenix = 90, biscuit_bear = 20, sunbeam_bear = 10 }

-- a ProfileSync snapshot (the shape of smoke_tb_panels' H.snapshot): `pets` = { key = level } is the whole active team
local function snapshot(pets, battle)
	local owned, levels, discovered, team = {}, {}, {}, {}
	for key, level in pairs(pets) do
		owned[key] = 1
		levels[key] = { Level = level, Xp = 0 }
		discovered[key] = true
		team[#team + 1] = key
	end
	table.sort(team)
	local record = { Trophies = 120, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} }
	for k, v in pairs(battle or {}) do
		record[k] = v
	end
	return {
		Tokens = 900,
		Pets = owned,
		Equipped = team,
		Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
		Discovered = discovered,
		IndexClaimed = {},
		Tutorial = { Step = 1000, Done = true, Gifted = true },
		Cash = 0, Gems = 0,
		Home = { Level = 5, Prestige = 0, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0 },
		Food = {}, Tiers = {}, Hybrids = {},
		PetLevels = levels,
		Teams = { Presets = { team, {}, {} }, Active = 1, Slots = 3, Busy = {} },
		Battle = record,
		PetGrowth = {},
		Ring = { Best = 0, Runs = 0 },
	}
end

local function syncProfile(pets, battle)
	KC.toClient("ProfileSync", snapshot(pets, battle))
	KC.advance(0.3)
end

local function pushArena(raid, over)
	local state = { Raid = raid, Double = { Active = false }, Leaderboard = {} }
	for k, v in pairs(over or {}) do
		state[k] = v
	end
	KC.toClient("ArenaState", state)
end

local function waiting(extra)
	local raid = { BossId = "frost_wyrm", Name = "Frost Wyrm", Active = false, FloorHiddenIn = 0, Fights = {}, Closed = {}, NextBossIn = 300 }
	for k, v in pairs(extra or {}) do
		raid[k] = v
	end
	return raid
end

----------------------------------------------------------------------------------------------------
-- the world's floor and gate as the client sees them (ArenaBuilder's parts, far from anything else)
----------------------------------------------------------------------------------------------------
local BASE = CFrame.new(5000, 200, 5000)
local ZONE_H = 60

local function part(parent, name, cf, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

local function stubWorld()
	local folder = Instance.new("Folder")
	folder.Name = "RaidClientStub"
	folder.Parent = Workspace
	local zone = part(folder, "BattleZone_Arena", BASE * CFrame.new(0, ZONE_H / 2 - 4, 0), Vector3.new(150, ZONE_H, 150))
	zone:SetAttribute("Mode", "Raid")
	zone:SetAttribute("ZoneId", "Arena")
	zone:SetAttribute("FloorY", BASE.Position.Y)
	CollectionService:AddTag(zone, "NC_BattleZone")
	-- a pocket's zone must never be taken for the floor
	local pocket = part(folder, "BattleZone_Raid", CFrame.new(5000, 1500, 9000), Vector3.new(150, ZONE_H, 150))
	pocket:SetAttribute("Mode", "Raid")
	pocket:SetAttribute("ZoneId", "Raid")
	pocket:SetAttribute("FloorY", 1500)
	CollectionService:AddTag(pocket, "NC_BattleZone")
	local gate = part(folder, "RaidGate", BASE * CFrame.new(0, 4, 70), Vector3.new(11, 8, 8))
	CollectionService:AddTag(gate, "NC_RaidGate")
	local crest = part(folder, "Gold", BASE * CFrame.new(0, 12, 72), Vector3.new(4, 2, 1))
	CollectionService:AddTag(crest, "NC_RaidGateCrest")
	local pillar = part(folder, "DarePillar", BASE * CFrame.new(-8, 4, 68), Vector3.new(2, 8, 2))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DarePrompt"
	prompt:SetAttribute("OpenPanel", "Dare")
	prompt.Parent = pillar
	return { Folder = folder, Zone = zone, Crest = crest, Prompt = prompt }
end

-- runs fn at the stub floor with the controller going; puts the player, the profile and the world back
local function atGate(label, fn)
	local RG = mod("RaidGateController")
	if not T.check(RG ~= nil and type(RG.Init) == "function" and type(RG.OpenDare) == "function", label .. ": client/Controllers/RaidGateController loads") then
		return
	end
	pcall(RG.Init)
	local char = LocalPlayer.Character
	local rootPart = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))
	local home = rootPart and rootPart.CFrame
	local stub = stubWorld()
	LocalPlayer:SetAttribute("InBattle", nil)
	Mock.Teleport(LocalPlayer, BASE * CFrame.new(0, 3, 50))
	syncProfile(TEAM_MID)
	local ok, err = pcall(fn, RG, stub)
	T.check(ok, label .. " ran without errors", tostring(err))
	local GQ = req("client/GraphicsQuality")
	if GQ then
		pcall(GQ.Apply, "High")
	end
	pcall(RG.Close)
	pushArena(nil)
	KC.advance(0.4)
	if home then
		Mock.Teleport(LocalPlayer, home)
	end
	stub.Folder:Destroy()
	pcall(RG.Refresh)
	KC.flushErrors(label)
end

local function idleBoss(id)
	local folder = Workspace:FindFirstChild("ClientRaidGate")
	return folder and folder:FindFirstChild("Boss_" .. (id or "frost_wyrm"))
end

local function collidingParts(model)
	local n = 0
	for _, d in ipairs(model and model:GetDescendants() or {}) do
		if d:IsA("BasePart") and d.CanCollide then
			n = n + 1
		end
	end
	return n
end

local newFight -- a real BattleSim's fight on this client (below, with the battle scenarios)

----------------------------------------------------------------------------------------------------
-- client_raid_gate
----------------------------------------------------------------------------------------------------
S.client_raid_gate = guarded("client_raid_gate", function()
	atGate("client_raid_gate", function(RG, stub)
		local GQ = req("client/GraphicsQuality")
		pushArena(waiting())
		KC.advance(0.5)
		local idle = idleBoss()
		T.check(idle ~= nil and idle:GetAttribute("Tier") == "Mid", "raid gate client: the idle boss stands on the floor, dressed for my tier (a L30 team = Mid)")
		if not idle then
			return
		end
		local rel = BASE:PointToObjectSpace(idle.PrimaryPart.Position)
		T.check(math.abs(rel.X) < 0.5 and math.abs(rel.Y) < 0.5 and math.abs(rel.Z) < 0.5, "raid gate client: ...at the floor's centre, on its surface", tostring(rel))
		T.check(idle.PrimaryPart.CFrame.LookVector:Dot(BASE.LookVector) > 0.99, "raid gate client: ...facing the lobby, its back to the gate")
		T.check(collidingParts(idle) == 0, "raid gate client: ...and nobody bumps into it", tostring(collidingParts(idle)))

		local tag = find(Workspace, "RaidGateTag")
		local text = tagText(tag)
		T.check(tag ~= nil and tag:IsA("BillboardGui") and tag.Adornee == stub.Crest, "raid gate client: the tag stands on the gate's crest")
		T.check(text:find("Frost Wyrm", 1, true) and text:find("your tier: Mid", 1, true) and text:find("L40", 1, true) and text:find("Rewards ready", 1, true) and text:find("Walk through", 1, true),
			"raid gate client: the tag names the boss, my tier, the boss level, the reward state and the walk-through", text)
		-- the World text rule (the census of smoke_polish_worldtext runs before this fight's world exists)
		T.check(tag.Size.X.Scale == 0 and tag.Size.Y.Scale == 0 and tag.MaxDistance == 120 and tag.LightInfluence == 0, "raid gate client: the tag is pixel-sized, seen within 120 studs")
		local plated, smallest = true, math.huge
		for _, d in ipairs(tag:GetDescendants()) do
			if d:IsA("TextLabel") then
				smallest = math.min(smallest, d.TextSize)
				local stroke = d:FindFirstChildOfClass("UIStroke")
				local outlined = d.TextStrokeTransparency <= 0.5 or (stroke ~= nil and stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and stroke.Thickness >= 1)
				plated = plated and outlined and d.TextTruncate == Enum.TextTruncate.None and not d.TextScaled and d.Parent:IsA("Frame") and d.Parent.BackgroundTransparency <= 0.25
			end
		end
		local biggest = find(tag, "Line1").TextSize
		T.check(plated and smallest >= 18 and biggest >= 22, "raid gate client: its lines sit on a solid plate, outlined, >= 18 px, the name >= 22 px", tostring(smallest))

		syncProfile(TEAM_MID, { RaidRewardAt = os.time() - 300 })
		KC.advance(1.1)
		text = tagText(tag)
		T.check(text:find("Rewards again in 1[45]:") ~= nil, "raid gate client: the tag counts down the 20 minute limit from the saved stamp", text)
		syncProfile(TEAM_MID, { RaidRewardAt = os.time() - 1300 })
		KC.advance(1.1)
		T.check(tagText(tag):find("Rewards ready", 1, true) ~= nil, "raid gate client: ...and says ready when it has passed", tagText(tag))
		syncProfile(TEAM_MID)

		pushArena(waiting({ Closed = { Mid = 42 } }))
		KC.advance(0.3)
		T.check(tagText(tag):find("back in 42 s", 1, true) ~= nil and not tagText(tag):find("Walk through", 1, true), "raid gate client: the tag shows my tier's return countdown", tagText(tag))
		pushArena(waiting({ Closed = { High = 42 } }))
		KC.advance(0.3)
		T.check(tagText(tag):find("Walk through", 1, true) ~= nil, "raid gate client: another tier's return is not mine", tagText(tag))

		-- a floor fight, a floor win
		pushArena(waiting({ Active = true, BattleId = "R9", FloorTier = "High", Fights = { High = { Tier = "High", Floor = true, Players = 2, Hp = 1, MaxHp = 2, EndsIn = 100 } } }))
		KC.advance(0.3)
		T.check(idleBoss() == nil, "raid gate client: the idle boss is gone while a floor fight runs")
		pushArena(waiting({ FloorHiddenIn = 50, Closed = { High = 50 } }))
		KC.advance(0.3)
		T.check(idleBoss() == nil, "raid gate client: ...and for the 60 s after a floor win")
		pushArena(waiting({ Fights = { Mid = { Tier = "Mid", Floor = false, Players = 2, Hp = 1, MaxHp = 2, EndsIn = 100 } } }))
		KC.advance(0.3)
		idle = idleBoss()
		T.check(idle ~= nil, "raid gate client: a pocket fight leaves the idle boss on the floor")

		-- my own floor fight starts: the idle boss steps aside at once, before the next ArenaState
		KC.toClient("BattleState", "Start", { Mode = "Raid", BattleId = "R10", Side = 0, Spectator = true, Raid = { Tier = "Mid", Pocket = false, BossId = "frost_wyrm" }, Units = {}, Zone = { CFrame = BASE, Size = Vector3.new(96, 30, 96), X = 96, Z = 96 }, Names = {} }, "R10")
		KC.advance(0.3)
		T.check(idleBoss() == nil, "raid gate client: a floor fight's Start takes the idle boss away at once")
		KC.toClient("BattleState", "End", { BattleId = "R10", Mode = "Raid", Spectator = true, Reason = "OutOfRange" }, "R10")
		pushArena(waiting())
		KC.advance(0.3)

		-- a floor fight lost: its boss stays drawn for the linger, the idle boss waits (a kill has FloorHiddenIn, a loss has nothing)
		KC.toClient("BattleState", "Start", { Mode = "Raid", BattleId = "R11", Side = 0, Spectator = true, Raid = { Tier = "Mid", Pocket = false, BossId = "frost_wyrm" }, Units = {}, Zone = { CFrame = BASE, Size = Vector3.new(96, 30, 96), X = 96, Z = 96 }, Names = {} }, "R11")
		KC.advance(0.3)
		KC.toClient("BattleState", "End", { BattleId = "R11", Mode = "Raid", Spectator = true, Reason = "Wipe" }, "R11")
		pushArena(waiting())
		KC.advance(0.5)
		T.check(idleBoss() == nil, "raid gate client: a spectator: the idle boss waits while the lost fight's boss is still drawn on the floor")
		KC.advance(1.5)
		T.check(idleBoss() ~= nil, "raid gate client: ...and stands there once the linger is over")
		-- the raider's own lost floor fight (the longer linger), a pocket fight's linger holds nothing back
		local floorFight = newFight({ Tier = "Mid", Pocket = false, BossId = "frost_wyrm" }, "frost_wyrm")
		floorFight.step()
		KC.advance(0.3)
		T.check(idleBoss() == nil, "raid gate client: (my floor fight's Start took the idle boss away)")
		floorFight.finish()
		pushArena(waiting())
		KC.advance(0.5)
		T.check(idleBoss() == nil, "raid gate client: a raider: the idle boss waits behind the result card's linger, no second boss on top of the first")
		KC.advance(2)
		T.check(idleBoss() == nil, "raid gate client: ...for all of it")
		KC.advance(1.5)
		T.check(idleBoss() ~= nil, "raid gate client: ...and stands there once the linger is over")
		local pocketFight = newFight({ Tier = "Mid", Pocket = true, BossId = "frost_wyrm" }, "frost_wyrm")
		pocketFight.step()
		pocketFight.finish()
		KC.advance(0.5)
		T.check(idleBoss() ~= nil, "raid gate client: a pocket fight's linger leaves the idle boss alone")
		KC.advance(4)

		-- range
		Mock.Teleport(LocalPlayer, BASE * CFrame.new(0, 3, -900))
		KC.advance(0.4)
		T.check(idleBoss() == nil, "raid gate client: nothing is built while the player is over 400 studs away")
		Mock.Teleport(LocalPlayer, BASE * CFrame.new(0, 3, 50))
		KC.advance(0.4)
		T.check(idleBoss() ~= nil, "raid gate client: ...and it is back when they come close")

		-- my tier moves: dressed and sized for the new one
		local midScale = idleBoss():GetAttribute("Scale")
		syncProfile(TEAM_MAX)
		KC.advance(0.4)
		idle = idleBoss()
		T.check(idle ~= nil and idle:GetAttribute("Tier") == "Max" and idle:GetAttribute("Scale") > midScale and idle:FindFirstChild("TierCrown") ~= nil, "raid gate client: a Max team sees the crowned, bigger boss")
		T.check(tagText(tag):find("your tier: Max", 1, true) ~= nil, "raid gate client: ...and the tag follows", tagText(tag))
		syncProfile(TEAM_MID)
		KC.advance(0.4)

		-- the head follows me
		idle = idleBoss()
		local head = idle:FindFirstChild("Head", true)
		local bit = head:GetChildren()[1]
		Mock.Teleport(LocalPlayer, idle.PrimaryPart.CFrame * CFrame.new(0, 3, -40))
		KC.advance(1.5)
		local look0 = bit.CFrame.LookVector
		Mock.Teleport(LocalPlayer, idle.PrimaryPart.CFrame * CFrame.new(40, 3, -30))
		KC.advance(0.1)
		local early = (bit.CFrame.LookVector - look0).Magnitude
		KC.advance(1.5)
		local late = (bit.CFrame.LookVector - look0).Magnitude
		T.check(late > 0.05, "raid gate client: the idle boss turns its head to follow me", string.format("%.3f", late))
		T.check(early < late, "raid gate client: ...slowly, not in one snap", string.format("%.3f -> %.3f", early, late))

		-- Graphics Low
		T.check(idle:FindFirstChild("TierAura", true) ~= nil, "raid gate client: (High) the Mid boss has its aura")
		GQ.Apply("Low")
		KC.advance(0.5)
		idle = idleBoss()
		T.check(idle ~= nil and idle:GetAttribute("Detail") == "Low" and idle:FindFirstChild("TierAura", true) == nil, "raid gate client: Graphics Low: the Low model, no aura")
		head = idle and idle:FindFirstChild("Head", true)
		bit = head and head:GetChildren()[1]
		local lookLow = bit and bit.CFrame.LookVector
		Mock.Teleport(LocalPlayer, idle.PrimaryPart.CFrame * CFrame.new(-40, 3, -30))
		KC.advance(1.5)
		T.check(bit ~= nil and (bit.CFrame.LookVector - lookLow).Magnitude < 0.01, "raid gate client: Graphics Low: no head tracking")
		GQ.Apply("High")
		KC.advance(0.5)
		T.check(idleBoss() ~= nil and idleBoss():GetAttribute("Detail") == "High", "raid gate client: back on High: the High model")

		-- fighting: the tag steps aside
		Mock.Teleport(LocalPlayer, BASE * CFrame.new(0, 3, 50))
		LocalPlayer:SetAttribute("InBattle", "B1")
		KC.advance(0.4)
		T.check(tag.Enabled == false, "raid gate client: the tag hides while I fight")
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(0.4)
		T.check(tag.Enabled == true, "raid gate client: ...and comes back")

		-- junk
		pushArena("junk")
		pushArena({ BossId = 7, Fights = "x", Closed = 3 })
		KC.advance(0.4)
		T.check(idleBoss() == nil, "raid gate client: a junk state builds nothing and breaks nothing")
	end)
end)

----------------------------------------------------------------------------------------------------
-- client_raid_dare
----------------------------------------------------------------------------------------------------
S.client_raid_dare = guarded("client_raid_dare", function()
	atGate("client_raid_dare", function(RG, stub)
		local AC, PC = mod("ArenaController"), mod("PetsController")
		pcall(AC.Init)
		pushArena(waiting())
		KC.advance(0.3)
		-- through the world's prompt: ArenaController routes OpenPanel = "Dare"
		Mock.Teleport(LocalPlayer, BASE * CFrame.new(-8, 3, 60))
		Mock.Trigger(stub.Prompt, LocalPlayer)
		KC.advance(0.2)
		local win = find(pg(), "Dare")
		T.check(win ~= nil and win:IsA("Frame") and RG.IsOpen() and KC.isShown(win), "raid dare client: the dare panel opens from the gate prompt")
		if not win then
			return
		end
		T.check(find(win, "Dare_High") and find(win, "Dare_Max") and find(win, "Dare_Mid") == nil and find(win, "Dare_Starter") == nil, "raid dare client: a Mid team sees High and Max only")
		local high, max = textOf(find(win, "Row_High")), textOf(find(win, "Row_Max"))
		T.check(high:find("L70", 1, true) and high:find("hits x1", 1, true) and high:find("rewards x1", 1, true) and max:find("L95", 1, true) and max:find("x1.3", 1, true), "raid dare client: rows name the boss level, the hit and the reward scale", high .. " / " .. max)

		-- the Arena panel takes over one side panel at a time, both ways
		AC.OpenArena("Raid")
		KC.advance(0.3)
		T.check(not RG.IsOpen() and AC.IsOpen(), "raid dare client: opening the Arena panel closes the dare panel")
		RG.OpenDare(stub.Prompt)
		KC.advance(0.3)
		T.check(RG.IsOpen() and not AC.IsOpen(), "raid dare client: opening the dare panel closes the Arena panel")

		local mark = #Mock.RemoteLog
		Mock.Click(find(win, "Dare_Max"))
		KC.advance(0.2)
		local sent = requests(mark, "RaidDare")
		T.check(#sent == 1 and sent[1].args[2] == "Max" and not RG.IsOpen(), "raid dare client: Dare sends BattleRequest('RaidDare', 'Max') and closes")
		KC.advance(0.3)

		-- walking away closes a panel opened at the pillar (the server would refuse the dare from there)
		RG.OpenDare(stub.Prompt)
		KC.advance(0.1)
		Mock.Teleport(LocalPlayer, BASE * CFrame.new(0, 3, 0))
		KC.advance(0.5)
		T.check(not RG.IsOpen(), "raid dare client: walking away from the pillar closes it")
		Mock.Teleport(LocalPlayer, BASE * CFrame.new(-8, 3, 60))

		-- my fight's Start closes it
		RG.OpenDare(stub.Prompt)
		KC.advance(0.1)
		KC.toClient("BattleState", "Start", { Mode = "Raid", BattleId = "R11", Side = 1, Raid = { Tier = "Mid", Pocket = true, BossId = "frost_wyrm" }, Units = {}, Zone = { CFrame = BASE, Size = Vector3.new(96, 30, 96), X = 96, Z = 96 }, Names = {} }, "R11")
		KC.advance(0.2)
		T.check(not RG.IsOpen(), "raid dare client: a Start closes it")
		KC.toClient("BattleState", "End", { BattleId = "R11", Mode = "Raid", Outcome = "Left", Reason = "Left", Spectator = true }, "R11")
		KC.advance(0.3)

		-- fighting: no panel
		LocalPlayer:SetAttribute("InBattle", "B1")
		T.check(RG.OpenDare(stub.Prompt) == false and not RG.IsOpen(), "raid dare client: no dare panel while I fight")
		LocalPlayer:SetAttribute("InBattle", nil)

		-- the top tier
		syncProfile(TEAM_MAX)
		RG.OpenDare(stub.Prompt)
		KC.advance(0.1)
		win = find(pg(), "Dare")
		T.check(textOf(win):find("already at the top", 1, true) ~= nil and find(win, "Dare_Max") == nil and find(win, "Dare_High") == nil, "raid dare client: a Max team has nothing to dare", textOf(win))
		RG.Close()
		KC.advance(0.3)

		-- an empty team: the Pets window in pick mode, nothing sent
		KC.toClient("ProfileSync", (function()
			local snap = snapshot(TEAM_MID)
			snap.Equipped = {}
			snap.Teams.Presets = { {}, {}, {} }
			return snap
		end)())
		KC.advance(0.3)
		RG.OpenDare(stub.Prompt)
		KC.advance(0.1)
		win = find(pg(), "Dare")
		T.check(find(win, "Dare_Mid") ~= nil, "raid dare client: an empty team reads as Starter: Mid can be dared")
		mark = #Mock.RemoteLog
		Mock.Click(find(win, "Dare_Mid"))
		KC.advance(0.3)
		T.check(#requests(mark, "RaidDare") == 0 and not RG.IsOpen(), "raid dare client: an empty team sends nothing")
		T.check(PC.IsOpen and PC.IsOpen() == true, "raid dare client: ...the Pets window opens instead")
		pcall(PC.Close, true)
		KC.advance(0.3)
	end)
end)

----------------------------------------------------------------------------------------------------
-- client_raid_panel
----------------------------------------------------------------------------------------------------
S.client_raid_panel = guarded("client_raid_panel", function()
	atGate("client_raid_panel", function()
		local AC = mod("ArenaController")
		pcall(AC.Init)
		pushArena(waiting({ Active = true, BattleId = "R9", FloorTier = "High", Fights = {
			High = { Tier = "High", Floor = true, Players = 2, Hp = 500, MaxHp = 1000, EndsIn = 100 },
			Starter = { Tier = "Starter", Floor = false, Players = 1, Hp = 300, MaxHp = 1000, EndsIn = 100 },
		} }))
		KC.advance(0.1)
		AC.OpenArena("Raid")
		KC.advance(0.5)
		local arena = pg():FindFirstChild("NimbusArena")
		local win = arena and arena:FindFirstChild("Window_Arena")
		if not T.check(win ~= nil and KC.isShown(win), "raid panel client: the Raid page opens") then
			return
		end
		T.check(find(win, "JoinRaid") == nil and find(win, "Why") == nil, "raid panel client: no Join button, no join reason")
		local tier = find(win, "TierLine")
		T.check(tier and KC.isShown(tier) and tier.Text:find("Your tier: Mid", 1, true) and tier.Text:find("L40", 1, true) and tier.Text:find("x0.8", 1, true) and tier.Text:find("x0.7", 1, true), "raid panel client: my tier, its boss level, hits and rewards", tier and tier.Text)
		local reward = find(win, "RewardLine")
		T.check(reward and reward.Text == "Rewards ready", "raid panel client: the reward state", reward and reward.Text)
		local fights = find(win, "Fights")
		local list = fights and textOf(fights) or ""
		T.check(list:find("High - 2 fighting - HP 50%", 1, true) and list:find("(floor)", 1, true) and list:find("Starter - 1 fighting - HP 30%", 1, true), "raid panel client: one row per running fight, the floor one marked", list)
		T.check(not textOf(find(fights, "Fight_Starter")):find("(floor)", 1, true), "raid panel client: ...a pocket fight is not marked")
		local nextBoss = find(win, "NextBoss")
		T.check(nextBoss and KC.isShown(nextBoss) and nextBoss.Text:find("5:00", 1, true) ~= nil or (nextBoss and nextBoss.Text:find("4:5", 1, true) ~= nil), "raid panel client: when the boss changes", nextBoss and nextBoss.Text)
		local name = find(win, "BossBlurb") or find(win, "Name")
		T.check(textOf(find(win, "Boss")):find("Frost Wyrm", 1, true) ~= nil, "raid panel client: the boss's name", name and name.Text)
		T.check(textOf(find(win, "Tips")):find("350", 1, true) ~= nil and find(win, "TiersTitle") ~= nil, "raid panel client: the medal rows show my tier's numbers (Gold 500 x0.7)", textOf(find(win, "Tips")))
		T.check(not textOf(find(win, "Tips")):find("RETREAT", 1, true) and textOf(find(win, "Tips")):find("DASH", 1, true) ~= nil, "raid panel client: the tips say DASH")

		-- my tier's boss is down
		pushArena(waiting({ Closed = { Mid = 30 } }))
		KC.advance(0.3)
		T.check(textOf(find(win, "Boss")):find("back in 30 s", 1, true) ~= nil or textOf(find(win, "Boss")):find("back in 29 s", 1, true) ~= nil, "raid panel client: my tier's return countdown", textOf(find(win, "Boss")))
		T.check(not KC.isShown(fights), "raid panel client: no fights, no list")

		-- the saved limit
		syncProfile(TEAM_MID, { RaidRewardAt = os.time() - 300 })
		KC.advance(0.3)
		T.check(reward.Text:find("Rewards again in 1[45]:") ~= nil, "raid panel client: the saved limit shows here too", reward.Text)
		syncProfile(TEAM_MID)

		-- a dared tier's numbers change with my team
		syncProfile(TEAM_MAX)
		KC.advance(0.3)
		T.check(tier.Text:find("Your tier: Max", 1, true) ~= nil and textOf(find(win, "Tips")):find("650", 1, true) ~= nil, "raid panel client: a Max team reads Max numbers", textOf(find(win, "Tips")))
		syncProfile(TEAM_MID)
		AC.Close()
		KC.advance(0.4)

		-- the side cards: never a raid card; the chip is Double Rewards only
		local side = pg():FindFirstChild("NimbusArenaSide")
		local stack = side and side:FindFirstChild("SideStack")
		pushArena(waiting(), { Next = { Kind = "BossRaid", BossId = "frost_wyrm", Name = "Frost Wyrm", StartsIn = 60 } })
		KC.advance(0.6)
		T.check(stack ~= nil and stack:FindFirstChild("Raid") == nil, "raid panel client: no raid side card")
		T.check(stack:FindFirstChild("Countdown") == nil, "raid panel client: no countdown chip for the boss rotation")
		pushArena(waiting(), { Next = { Kind = "DoubleRewards", StartsIn = 60 } })
		KC.advance(0.6)
		T.check(stack:FindFirstChild("Countdown") ~= nil and textOf(stack:FindFirstChild("Countdown")):find("Rewards in", 1, true) ~= nil, "raid panel client: the chip announces Double Rewards")
		pushArena(waiting(), { Double = { Active = true, EndsIn = 100 } })
		KC.advance(0.6)
		T.check(stack:FindFirstChild("Countdown") ~= nil, "raid panel client: ...and counts it down while it runs")
		pushArena(waiting())
		KC.advance(0.6)
		T.check(stack:FindFirstChild("Countdown") == nil, "raid panel client: ...and it goes")
	end)
end)

----------------------------------------------------------------------------------------------------
-- client_raid_enrage: a real BattleSim, sent the way BattleService sends it (smoke_p3_battleclient's driver)
----------------------------------------------------------------------------------------------------
local fightSeq = 0

function newFight(raid, bossId, keys)
	local Sim = req("shared/BattleSim")
	fightSeq = fightSeq + 1
	local id = "smoke_raidc_" .. fightSeq
	local me = LocalPlayer.UserId
	local pets = {}
	for i, key in ipairs(keys or { "ember_phoenix", "biscuit_bear", "sunbeam_bear" }) do
		pets[i] = { Key = key, PetId = key, Level = 60, Tier = "Normal", Slot = i }
	end
	local sim = Sim.new({ Mode = "Raid", Seed = 3, Id = id, Boss = bossId or "storm_titan", RaidTier = raid.Tier, Specials = false, Teams = { { Owner = me, Side = 1, Pets = pets } } })
	local d = { sim = sim, id = id, last = {}, me = me }
	local p = sim:Describe()
	p.BattleId = id
	p.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
	p.Names = { [tostring(me)] = LocalPlayer.Name }
	p.Side = 1
	p.Spectator = false
	p.T = sim:Time()
	p.Raid = raid
	local team = sim:TeamOf(me)
	p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed, Cooldowns = { Element = 0, Dash = 0, Swap = 0, Buff = {} } }
	LocalPlayer:SetAttribute("InBattle", id)
	KC.toClient("BattleState", "Start", p, id)
	function d.step(fps)
		local evs = sim:Step(0.1)
		if d.pin then
			d.pin()
		end
		if #evs > 0 then
			KC.toClient("BattleState", "Events", evs, id)
		end
		local snap = sim:SnapshotDelta(d.last)
		if type(snap) ~= "table" then
			snap = { T = sim:Time(), Units = {} }
		end
		snap.BattleId = id
		KC.toClient("BattleState", "Snapshot", snap, id)
		local frames = math.max(1, math.floor((fps or 20) * 0.1 + 0.5))
		for _ = 1, frames do
			Mock.Step(0.1 / frames)
		end
		return evs
	end
	function d.run(seconds, each)
		for _ = 1, math.floor(seconds / 0.1 + 0.5) do
			local evs = d.step()
			if each and each(evs) then
				return true
			end
		end
		return false
	end
	function d.finish()
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.toClient("BattleState", "End", { BattleId = id, Mode = "Raid", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe" }, id)
	end
	return d
end

local function battleGui()
	return pg():FindFirstChild("NimbusBattle")
end

local function hudHas(pattern)
	for _, d in ipairs(battleGui() and battleGui():GetDescendants() or {}) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and KC.isShown(d) and tostring(d.Text):find(pattern) then
			return true
		end
	end
	return false
end

local function teleById(BC, id)
	for _, tl in ipairs(BC.GetTelegraphs()) do
		if tl.Id == id then
			return tl
		end
	end
	return nil
end

local function lethalTele(BC)
	for _, tl in ipairs(BC.GetTelegraphs()) do
		if tl.Lethal then
			return tl
		end
	end
	return nil
end

local function bossModelOf(BC, d)
	local info = BC.GetUnit(d.sim.boss.id)
	return info and info.Model
end

-- a "DASH!" callout on screen right now (the battle's pixel-sized numbers live in ClientBattle.Fx)
local function calloutShown()
	local folder = Workspace:FindFirstChild("ClientBattle")
	for _, d in ipairs(folder and folder:GetDescendants() or {}) do
		if d:IsA("TextLabel") and d.Text == "DASH!" then
			local gui = d:FindFirstAncestorOfClass("BillboardGui")
			if gui and gui.Enabled then
				return true
			end
		end
	end
	return false
end

S.client_raid_enrage = guarded("client_raid_enrage", function()
	local BC, SC, GQ = mod("BattleController"), mod("SkyController"), req("client/GraphicsQuality")
	local errBefore = #Mock.Errors
	local d = newFight({ Tier = "High", Pocket = true, BossId = "storm_titan" })
	d.run(1.2)
	T.check(type(SC.State) == "function" and SC.State().Local == "storm_titan", "raid battle client: a pocket fight puts up the raid sky locally")
	T.check(hudHas("BOSS RAID %- High"), "raid battle client: the mode line names the tier")
	local model = bossModelOf(BC, d)
	T.check(model ~= nil and model:GetAttribute("Tier") == "High" and model:FindFirstChild("TierAura", true) ~= nil, "raid battle client: the fight's boss wears its tier")
	local plainScale = req("shared/BossBuilder").Build("storm_titan", { Detail = "Low" }):GetAttribute("Scale")
	T.check(model ~= nil and model:GetAttribute("Scale") > plainScale, "raid battle client: ...and its size (High grows the boss, as the sim's radius does)")

	-- a plain telegraph first (no lethal before the enrage)
	local plainId = 90006
	KC.toClient("BattleState", "Events", { { type = "Telegraph", id = plainId, boss = d.sim.boss.id, name = "Zap", attack = "slam", shape = "Circle", x = 40, z = 40, r = 7, at = d.sim:Time() + 2.2, hits = 2.2 } }, d.id)
	d.run(0.5)
	local plain = teleById(BC, plainId)
	T.check(plain ~= nil and plain.Lethal == false, "raid battle client: a plain telegraph is not lethal")

	-- the sim's own enrage at 30% health
	d.sim.boss.hp = d.sim.boss.maxHp * 0.29
	local fx
	local sawEnrage = d.run(1.5, function(evs)
		for _, e in ipairs(evs) do
			if e.type == "Enrage" then
				return true
			end
		end
		return false
	end)
	T.check(sawEnrage, "raid battle client: (setup) the sim enraged at 30% health")
	d.run(0.6)
	fx = pg():FindFirstChild("NimbusBattleFx")
	local edge = fx and fx:FindFirstChild("Edge1")
	T.check(edge ~= nil and edge.Visible and edge.BackgroundTransparency < 0.6 and edge.BackgroundColor3.R > 0.8 and edge.BackgroundColor3.G < 0.4, "raid battle client: enrage holds red screen edges", edge and tostring(edge.BackgroundTransparency))
	local seen = {}
	for _ = 1, 10 do
		d.step()
		seen[#seen + 1] = edge and edge.BackgroundTransparency or 0
	end
	local low, high = math.huge, -math.huge
	for _, v in ipairs(seen) do
		low, high = math.min(low, v), math.max(high, v)
	end
	T.check(low >= 0.34 and high <= 0.56 and high - low > 0.03, "raid battle client: ...pulsing between 0.35 and 0.55", string.format("%.2f - %.2f", low, high))
	-- another glow (a Secret pet's hit) does not take the hold away
	if BC._Me and BC._Me.Glow then
		BC._Me.Glow(Color3.new(1, 1, 1), 0.2)
		d.run(0.5)
		T.check(edge.Visible and edge.BackgroundColor3.G < 0.4, "raid battle client: a pet's glow on top gives the red edges back")
	end

	-- the sim's lethal telegraph
	local tele = nil
	d.run(8, function()
		tele = lethalTele(BC)
		return tele ~= nil
	end)
	T.check(tele ~= nil, "raid battle client: the sim's lethal Telegraph arrives and is drawn as lethal")
	if tele then
		T.check(hudHas("ENRAGED %- DASH!"), "raid battle client: the enrage pill says DASH! while the lethal is pending")
		T.check(plain ~= nil and tele.RimWidth >= 2 * plain.RimWidth, "raid battle client: a thicker rim", tostring(tele.RimWidth) .. " vs " .. tostring(plain and plain.RimWidth))
		T.check(tele.RimColor ~= nil and tele.RimColor.R > 0.9 and tele.RimColor.G < 0.4, "raid battle client: ...in the late colour from the start")
		local inside = false
		d.run(1, function()
			inside = calloutShown()
			return inside
		end)
		T.check(inside, "raid battle client: a floating DASH! over my fighter standing in it")
		local landed = d.run(6, function()
			return lethalTele(BC) == nil
		end)
		T.check(landed, "raid battle client: the lethal telegraph resolves")
		d.run(0.3)
		T.check(hudHas("ENRAGED") and not hudHas("DASH!"), "raid battle client: ...and plain ENRAGED after it lands")
	end
	d.finish()
	for _ = 1, 8 do
		Mock.Step(0.05)
	end
	T.check(SC.State().Local == nil and edge ~= nil and not edge.Visible, "raid battle client: the end drops the local sky and the red edges")
	KC.advance(14)
	T.check(BC.GetBattle() == nil, "raid battle client: freed after the end")

	-- a floor fight: the server-wide sky, no local one
	d = newFight({ Tier = "Starter", Pocket = false, BossId = "storm_titan" })
	d.run(1)
	T.check(SC.State().Local == nil, "raid battle client: a floor fight leaves the sky to the server")
	T.check(hudHas("BOSS RAID %- Starter"), "raid battle client: a floor fight names its tier too")
	d.finish()
	KC.advance(14)

	-- the warning goes by the server's own hit test: the sim hits a body whose edge reaches the shape (shape + the unit's radius, on a
	-- Circle and along a Line), so the client warns that body; a shape that misses it warns nothing. A Bear held still, the boss kept
	-- from casting; the sim's own telegraphs, so the server's Hit says what really lands.
	-- (feel-balance) at Melee.Standoff 8 a held Bear still strikes the boss, and while it strikes the server tests its bite
	-- point, not the pinned spot (smoke_feel_dash feel_strike_*): this probe pins the shape + radius rule on a still body, so
	-- it runs at Standoff 0 (restored after)
	local Cat = req("shared/BattleCatalog")
	local keepSo = Cat.Damage.Standoff
	Cat.Damage.Standoff = 0
	d = newFight({ Tier = "High", Pocket = true, BossId = "frost_wyrm" }, "frost_wyrm", { "biscuit_bear" })
	d.run(1)
	local bear = d.sim.teamByOwner[d.me].fighter
	local bearX, bearZ = bear.x, bear.z
	d.sim.boss.staggerUntil = math.huge
	function d.pin()
		bear.x, bear.z = bearX, bearZ
		if bear.alive then
			bear.hp = bear.maxHp
		end
	end
	d.run(0.6)
	local drawn = BC.GetUnit(bear.id)
	T.check(bear.radius == 2.4 and drawn ~= nil and math.abs(drawn.X - bearX) < 0.01 and math.abs(drawn.Z - bearZ) < 0.01, "raid battle client: (setup) a Bear, radius 2.4, drawn where the sim holds it", drawn and string.format("radius %s, drawn %.2f, %.2f, sim %.2f, %.2f", tostring(bear.radius), drawn.X, drawn.Z, bearX, bearZ) or "no unit")
	local absoluteZero = d.sim.boss.boss.Lethal
	local probeId = 90100
	-- one telegraph of the sim's: true while it counts down: the HUD's threat, the floating DASH!; and the server's Hit on the Bear
	local function probe(tele)
		probeId = probeId + 1
		local hits = 1
		tele.id, tele.boss, tele.attack, tele.at = probeId, d.sim.boss, absoluteZero, d.sim:Time() + hits
		d.sim.telegraphs[#d.sim.telegraphs + 1] = tele
		d.sim.pending[#d.sim.pending + 1] = { type = "Telegraph", id = tele.id, boss = d.sim.boss.id, name = absoluteZero.Name, attack = absoluteZero.Id, shape = tele.shape, x = tele.x, z = tele.z, r = tele.r, angle = tele.angle, length = tele.length, width = tele.width, at = tele.at, hits = hits, lethal = tele.lethal }
		local warned, called, struck = false, false, false
		d.run(hits + 0.8, function(evs)
			warned = warned or BC.GetBattle().Threat
			called = called or calloutShown()
			for _, e in ipairs(evs) do
				if e.type == "Hit" and e.tele == tele.id and e.to == bear.id then
					struck = true
				end
			end
			return struck
		end)
		return warned, called, struck
	end
	local R, LEN, WIDTH = 10, 30, 5
	local rim = 1.95 -- the body overlaps the edge (a pad of 1.5 would call it safe)
	local past = bear.radius + 0.3 -- the body clears the edge
	local warned, called, struck = probe({ shape = "Circle", x = bearX + R + past, z = bearZ, r = R, lethal = true })
	T.check(not struck and not warned and not called, "raid battle client: a lethal circle that misses the body warns nothing", string.format("warned %s, called %s, struck %s", tostring(warned), tostring(called), tostring(struck)))
	warned, called, struck = probe({ shape = "Line", x = bearX - LEN / 2, z = bearZ - WIDTH / 2 - past, angle = 0, length = LEN, width = WIDTH })
	T.check(not struck and not warned, "raid battle client: a line that misses the body warns nothing", string.format("warned %s, struck %s", tostring(warned), tostring(struck)))
	warned, called, struck = probe({ shape = "Line", x = bearX - LEN / 2, z = bearZ - WIDTH / 2 - rim, angle = 0, length = LEN, width = WIDTH })
	T.check(struck and warned, "raid battle client: a line whose side overlaps the body warns it, as the server hits it", string.format("warned %s, struck %s", tostring(warned), tostring(struck)))
	warned, called, struck = probe({ shape = "Line", x = bearX - LEN - rim, z = bearZ, angle = 0, length = LEN, width = WIDTH })
	T.check(struck and warned, "raid battle client: ...and a line whose tip overlaps it", string.format("warned %s, struck %s", tostring(warned), tostring(struck)))
	warned, called, struck = probe({ shape = "Circle", x = bearX + R + rim, z = bearZ, r = R, lethal = true })
	T.check(struck and warned and called, "raid battle client: a lethal circle whose rim overlaps the body warns it and floats DASH!, as the server knocks it out", string.format("warned %s, called %s, struck %s", tostring(warned), tostring(called), tostring(struck)))
	d.finish()
	Cat.Damage.Standoff = keepSo
	KC.advance(14)

	-- a late joiner into an enraged fight
	d = newFight({ Tier = "High", Pocket = false, BossId = "storm_titan", Enraged = true })
	d.run(0.6)
	fx = pg():FindFirstChild("NimbusBattleFx")
	edge = fx and fx:FindFirstChild("Edge1")
	T.check(edge ~= nil and edge.Visible and edge.BackgroundColor3.G < 0.4 and hudHas("ENRAGED"), "raid battle client: a late joiner in an enraged fight sees the red edges and the pill at once")
	d.finish()
	KC.advance(14)

	-- Graphics Low
	GQ.Apply("Low")
	d = newFight({ Tier = "Max", Pocket = true, BossId = "storm_titan" })
	d.run(1)
	model = bossModelOf(BC, d)
	T.check(model ~= nil and model:GetAttribute("Tier") == "Max" and model:FindFirstChild("TierAura", true) == nil, "raid battle client: Low: the boss has no aura")
	d.sim.boss.hp = d.sim.boss.maxHp * 0.29
	d.run(1.5)
	fx = pg():FindFirstChild("NimbusBattleFx")
	edge = fx and fx:FindFirstChild("Edge1")
	local a0 = edge and edge.BackgroundTransparency
	d.run(0.3)
	T.check(edge ~= nil and edge.Visible and edge.BackgroundTransparency == 0.5 and a0 == 0.5, "raid battle client: Low keeps the edges, steady at 0.5", tostring(a0))
	tele = nil
	local called = false
	d.run(8, function()
		tele = tele or lethalTele(BC)
		called = called or calloutShown()
		return tele ~= nil and called
	end)
	T.check(tele ~= nil and tele.RimWidth > 1 and called, "raid battle client: Low keeps the lethal rim and the callout")
	d.finish()
	KC.advance(14)
	GQ.Apply("High")
	T.check(#Mock.Errors == errBefore, "raid battle client: no script errors", #Mock.Errors > errBefore and tostring(Mock.Errors[#Mock.Errors].msg) or "")
	KC.flushErrors("client_raid_enrage")
end)

----------------------------------------------------------------------------------------------------
-- client_raid_sky: SetLocalEvent on the real clock attributes (smoke_sky's publish)
----------------------------------------------------------------------------------------------------
S.client_raid_sky = guarded("client_raid_sky", function()
	local SC = mod("SkyController")
	local Cfg = req("shared/Config")
	local A = Cfg.Sky.Attr
	local LS = req("client/LightingStack")
	if not T.check(type(SC.SetLocalEvent) == "function", "raid sky client: SkyController.SetLocalEvent") then
		return
	end
	local saved = LS.Value("Lighting", "Brightness", "Dungeon")
	local savedClock = LS.Value("Lighting", "ClockTime", "Dungeon")
	local now = Workspace:GetServerTimeNow()
	Workspace:SetAttribute(A.Epoch, now)
	Workspace:SetAttribute(A.Speed, 1)
	Workspace:SetAttribute(A.Offset, 100)
	Workspace:SetAttribute(A.Event, "")
	Workspace:SetAttribute(A.EventAt, now - 100)
	local ok, err = pcall(function()
		SC.Start()
		local function near(a, b)
			return type(a) == "number" and math.abs(a - b) < 0.1
		end
		-- (the transitions start from what shows at their real moment: the clock has to move, not only Refresh's argument)
		local function after(seconds)
			KC.advance(seconds)
			SC.Refresh(Workspace:GetServerTimeNow())
			return SC.State()
		end
		local st = after(1)
		T.check(st.Event == nil and st.Local == nil, "raid sky client: no local event: the plain cycle")
		T.check(SC.SetLocalEvent("storm_titan") == true, "raid sky client: a boss with a raid sky is taken")
		st = after(1.5)
		T.check(st.Local == "storm_titan" and st.Event == "storm_titan" and near(st.EventBlend, 0.5), "raid sky client: it blends in like the server's raid sky", tostring(st.EventBlend))
		st = after(1.7)
		T.check(near(st.EventBlend, 1) and Workspace:GetAttribute(A.Event) == "", "raid sky client: ...fully on, for this client only (no attribute written)", tostring(st.EventBlend))
		T.check(SC.SetLocalEvent("no_such_boss") == false and SC.State().Local == "storm_titan", "raid sky client: a junk id is refused")
		SC.SetLocalEvent(nil)
		T.check(SC.State().Local == nil, "raid sky client: nil takes it off")
		st = after(1.5)
		T.check(st.Event == "storm_titan" and near(st.EventBlend, 0.5), "raid sky client: it blends back out over the same 3 s", tostring(st.EventBlend))
		st = after(1.7)
		T.check(st.Event == nil and st.EventBlend == 0, "raid sky client: ...back on the cycle", tostring(st.Event))
		-- a floor raid starts while the local sky leaves: the server's takes over
		SC.SetLocalEvent("storm_titan")
		after(3.2)
		SC.SetLocalEvent(nil)
		after(0.5)
		Workspace:SetAttribute(A.Event, "lava_golem")
		Workspace:SetAttribute(A.EventAt, Workspace:GetServerTimeNow())
		st = after(3.5)
		T.check(st.Event == "lava_golem" and near(st.EventBlend, 1), "raid sky client: the server's raid sky takes over from the local one", tostring(st.Event))
		-- ...and a local sky stands over a server sky while I fight in a pocket
		SC.SetLocalEvent("frost_wyrm")
		st = after(3.5)
		T.check(st.Event == "frost_wyrm" and st.Local == "frost_wyrm", "raid sky client: my pocket's sky wins over the floor fight's", tostring(st.Event))
		-- ...and back to the floor fight's when mine ends
		SC.SetLocalEvent(nil)
		st = after(3.5)
		T.check(st.Event == "lava_golem" and near(st.EventBlend, 1), "raid sky client: my fight's end leaves the floor fight's sky up", tostring(st.Event))
	end)
	T.check(ok, "raid sky client ran without errors", tostring(err))
	pcall(SC.Stop)
	for _, key in pairs(A) do
		Workspace:SetAttribute(key, nil)
	end
	pcall(SC.Refresh)
	KC.advance(2.2)
	pcall(LS.SetBase, { Lighting = { Brightness = saved, ClockTime = savedClock } }, 0)
	KC.flushErrors("client_raid_sky")
end)

----------------------------------------------------------------------------------------------------
-- client_raid_mobile (phone world, 844x390)
----------------------------------------------------------------------------------------------------
S.client_raid_mobile = guarded("client_raid_mobile", function()
	local old = { Mock.Viewport.X, Mock.Viewport.Y }
	Mock.SetViewport(844, 390)
	KC.advance(0.6)
	atGate("client_raid_mobile", function(RG, stub)
		local AC = mod("ArenaController")
		pcall(AC.Init)
		pushArena(waiting({ Fights = { High = { Tier = "High", Floor = true, Players = 2, Hp = 1, MaxHp = 2, EndsIn = 100 } } }))
		KC.advance(0.3)
		-- the longest list: a Starter team has three tiers to dare
		syncProfile({ ember_phoenix = 5, biscuit_bear = 3, sunbeam_bear = 1 })
		RG.OpenDare(stub.Prompt)
		KC.advance(0.3)
		local win = find(pg(), "Dare")
		if T.check(win ~= nil, "raid mobile: the dare panel opens") then
			-- (a ScreenGui that keeps the inset starts below the top bar: AbsolutePosition counts from there)
			local inset = GuiService:GetGuiInset()
			local gui = win:FindFirstAncestorOfClass("ScreenGui")
			local screenY = win.AbsolutePosition.Y + (gui.IgnoreGuiInset and 0 or inset.Y)
			T.check(screenY >= inset.Y, "raid mobile: the window sits under Roblox's top bar", string.format("%.1f >= %.1f", screenY, inset.Y))
			local bottom = win.AbsolutePosition.Y + win.AbsoluteSize.Y
			for _, id in ipairs({ "Mid", "High", "Max" }) do
				local b = find(win, "Dare_" .. id)
				if T.check(b ~= nil, "raid mobile: Dare_" .. id .. " is there") then
					T.check(b.AbsoluteSize.Y >= 44 and b.AbsoluteSize.X >= 44, "raid mobile: Dare_" .. id .. " >= 44 px", string.format("%.1f x %.1f", b.AbsoluteSize.X, b.AbsoluteSize.Y))
					T.check(b.AbsolutePosition.Y + b.AbsoluteSize.Y <= bottom + 0.5, "raid mobile: Dare_" .. id .. " is inside the window, no scrolling", string.format("%.1f <= %.1f", b.AbsolutePosition.Y + b.AbsoluteSize.Y, bottom))
				end
			end
			local small = {}
			for _, d in ipairs(win:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and KC.isShown(d) then
					local box = Mock.GuiBox(d)
					local px = d.TextSize * ((box and box.scale) or 1)
					if px < 14 - 0.05 then
						small[#small + 1] = string.format("%s=%.1f", d.Name, px)
					end
				end
			end
			T.check(#small == 0, "raid mobile: every text of the dare panel is >= 14 px on screen", table.concat(small, ", "))
		end
		RG.Close()
		KC.advance(0.3)
		syncProfile(TEAM_MID)
		AC.OpenArena("Raid")
		KC.advance(0.6)
		local arena = find(pg(), "Window_Arena")
		local scroll = arena and find(find(arena, "Page_Raid"), "Scroll")
		if T.check(scroll ~= nil, "raid mobile: the Raid page's scroller") then
			local nested = 0
			for _, d in ipairs(scroll:GetDescendants()) do
				if d:IsA("ScrollingFrame") then
					nested = nested + 1
				end
			end
			T.check(nested == 0, "raid mobile: no nested scrolling on the Raid page", tostring(nested))
		end
		AC.Close()
		KC.advance(0.3)
		local tag = find(Workspace, "RaidGateTag")
		local smallest = math.huge
		for _, d in ipairs(tag and tag:GetDescendants() or {}) do
			if d:IsA("TextLabel") then
				smallest = math.min(smallest, d.TextSize)
			end
		end
		T.check(tag ~= nil and smallest >= 14, "raid mobile: the gate tag's text >= 14 px", tostring(smallest))
	end)
	Mock.SetViewport(old[1], old[2])
	KC.advance(0.6)
end)

return S
