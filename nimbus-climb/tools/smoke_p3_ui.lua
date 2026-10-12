-- smoke_p3_ui.lua: Phase 3 UI (ARCHITECTURE_V3.md "Phase 3 build contract": "ArenaController + Team screen (ui)" and the
-- "Interfaces between the Phase 3 modules"): the Team window + trophies of client/Controllers/MenuController.lua, the
-- Trial window / Arena panel / side cards of client/Controllers/ArenaController.lua, tutorial chapter 3
-- (shared/TutorialSteps.lua, server/Services/TutorialService.lua) and the battle tips of shared/NpcDialog.lua. Loaded by
-- tools/smoke.py in BOTH worlds; ARGS.context picks the half:
--   p3ui_content        (server, content) chapter 3 is appended after the home chapter (arena, team, trial, raid; chapter
--                       3, the raid step ends it, known CompleteOn, Arena targets with a Place, short texts, the raid
--                       minutes placeholder); NPC tips: every NPC keeps 3-5 lines that fit the dialog, and the battle
--                       controls (Sparky Fox), Boss Raids with the real schedule (Captain Penguin), the Trial Portal,
--                       battle teams and trophies (Coach Corgi), elements and synergy in battle (Professor Axolotl) are
--                       explained with the numbers of BattleCatalog
--   p3ui_tutorial       (server, booted) a player who finished the home chapter resumes at "arena": the arrow points at
--                       the arena's forum (ArenaInfo.Spawn); walking in -> "team" (the Team menu tile); a battle team ->
--                       "trial" (the arrow at the Trial Portal, none while fighting); Trial 1 cleared -> "raid" (a hint
--                       with the raid countdown); standing in the arena while a raid runs ends the chapter: Done, the
--                       token reward paid once; a BattleEnded trial win completes "trial" by itself
--   client_p3ui         (client) the Team tile (MenuButton_Team) and window: slot cards (pet, level, element, power),
--                       slot 4 locked before Prestige 1 and open after, live synergy + matchups, the element wheel, the
--                       team power and trophies, the picker (every owned copy, busy ones dimmed); remove / add / swap
--                       send BattleRequest TeamSet (preset, keys) after a short pause, Use Team N sends TeamSelect, a full
--                       team or a busy pet sends nothing; the Stats window's battle record; ArenaController: OpenPanel /
--                       prompts (OpenPanel + OpenPanelTab / RingIndex) open the Trial window (30 levels: cleared checks,
--                       locks, BOSS tags; START only for an open level: BattleRequest Trial) and the Arena panel (Duels:
--                       Queue / Challenge; Raid: JOIN; Leaders: ArenaState.Leaderboard with the player's row), one
--                       window at a time with the menu; side cards: a duel invite (Accept -> ChallengeReply), the queue
--                       (Leave -> Unqueue), the raid card (JOIN -> JoinRaid), the event countdown; hidden while
--                       fighting; every text >= 18 design px; no script errors
--   client_p3ui_mobile  (phone 390x844) the Team window, the Trial window and the Arena tabs keep every text >= 14 px;
--                       (844x390) the seven-tile menu stays two labelled columns above the thumbstick
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

-- this file's folder ("tools/") from the chunk name smoke.py gives it ("=tools/smoke_p3_ui.lua")
local HERE = (debug.getinfo(1, "S").source or ""):match("^=(.*)smoke_p3_ui%.lua$") or ""

-- a source file of the project as text (nil when it cannot be read)
local function sourceOf(key)
	local rel = "src/" .. key .. ".lua"
	for _, path in ipairs({ rel, HERE .. "../" .. rel, "../" .. rel }) do
		local fh = io.open(path, "r")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src
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
	local advance, config, mod, waitFor = K.advance, K.config, K.mod, K.waitFor

	local function requireAt(key)
		local inst = K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		if ok and type(result) == "table" then
			return result
		end
		return nil
	end

	------------------------------------------------------------------------------------------------
	-- p3ui_content
	------------------------------------------------------------------------------------------------
	S.p3ui_content = guarded("p3ui_content", function()
		local Steps = requireAt("shared/TutorialSteps")
		local ND = requireAt("shared/NpcDialog")
		local BC = requireAt("shared/BattleCatalog")
		local Config = config()
		if not T.check(type(Steps) == "table" and type(Steps.Steps) == "table" and type(ND) == "table", "p3ui: TutorialSteps and NpcDialog load") then
			return
		end
		-- chapter 3
		local start = Steps.ChapterStart and Steps.ChapterStart[3]
		local home = Steps.ChapterStart and Steps.ChapterStart[2]
		if not T.check(type(start) == "number" and type(home) == "number" and start > home, "p3ui: chapter 3 (pet battles) is appended after the home chapter", tostring(start)) then
			return
		end
		local ids = {}
		for i = start, #Steps.Steps do
			ids[#ids + 1] = Steps.Steps[i].Id
		end
		T.eq(table.concat(ids, ","), "arena,team,trial,raid", "p3ui: chapter 3 = go to the Arena, set your team, win Trial 1, see a Boss Raid")
		local byId = {}
		for _, step in ipairs(Steps.Steps) do
			byId[step.Id] = step
		end
		local bad = {}
		local placed = { Gate = true, Trials = true, Floor = true }
		for i = start, #Steps.Steps do
			local step = Steps.Steps[i]
			if step.Chapter ~= 3 then
				bad[#bad + 1] = step.Id .. " chapter " .. tostring(step.Chapter)
			end
			if type(step.Text) ~= "string" or #step.Text < 20 or #step.Text > 200 or step.Text:find("[<>&]") then
				bad[#bad + 1] = step.Id .. " text"
			end
			if type(step.Title) ~= "string" or step.Title == "" or type(step.Hint) ~= "string" then
				bad[#bad + 1] = step.Id .. " title / hint"
			end
			local t = step.Target
			if t and t.Kind == "Arena" and not placed[t.Place] then
				bad[#bad + 1] = step.Id .. " arena target without a Place"
			end
		end
		T.check(#bad == 0, "p3ui: every chapter 3 step has chapter 3, a title, a hint and a short plain text", table.concat(bad, "; "))
		T.check(byId.arena and byId.arena.CompleteOn == "ArenaReached" and byId.arena.Target and byId.arena.Target.Kind == "Arena"
			and byId.arena.Target.Place == "Gate", "p3ui: 'arena' points at the arena (Place Gate) and completes on ArenaReached")
		T.check(byId.team and byId.team.CompleteOn == "TeamSet" and byId.team.Target and byId.team.Target.Kind == "Menu" and byId.team.Target.Id == "Team",
			"p3ui: 'team' rings the Team menu tile and completes on TeamSet")
		T.check(byId.trial and byId.trial.CompleteOn == "TrialWon" and byId.trial.Target and byId.trial.Target.Place == "Trials",
			"p3ui: 'trial' points at the Trial Portal and completes on TrialWon")
		local minutes = BC and BC.Events and BC.Events.Schedule and BC.Events.Schedule[1] and BC.Events.Schedule[1].EveryMinutes or 20
		T.check(byId.raid and byId.raid.CompleteOn == "RaidSeen" and byId.raid.ChapterEnd == true and byId.raid.Target and byId.raid.Target.Place == "Floor"
			and tostring(byId.raid.Text):find("Every " .. tostring(minutes) .. " minutes", 1, true) ~= nil and not tostring(byId.raid.Text):find("{", 1, true),
			"p3ui: 'raid' ends the chapter (ChapterEnd), points at the colosseum floor and quotes the raid schedule (every " .. tostring(minutes) .. " minutes)")
		local ends = 0
		for i = start, #Steps.Steps do
			if Steps.Steps[i].ChapterEnd then
				ends = ends + 1
			end
		end
		T.eq(ends, 1, "p3ui: chapter 3 has exactly one ChapterEnd step")
		local src = sourceOf("server/Services/TutorialService")
		if type(src) == "string" then
			for _, kind in ipairs({ "ArenaReached", "TeamSet", "TrialWon", "RaidSeen" }) do
				T.check(src:find(kind .. " = true", 1, true) ~= nil, "p3ui: TutorialService knows CompleteOn " .. kind)
			end
		end

		-- NPC tips
		T.eq(#ND.Npcs, 6, "p3ui: still six NPCs")
		local long, counts, all = {}, {}, {}
		for _, npc in ipairs(ND.Npcs) do
			local n = #(npc.Lines or {})
			if n < 3 or n > 5 then
				counts[#counts + 1] = npc.Id .. "=" .. n
			end
			for i, line in ipairs(npc.Lines or {}) do
				if #line > 125 or line:find("[<>&]") then
					long[#long + 1] = npc.Id .. "#" .. i .. " (" .. #line .. ")"
				end
				all[npc.Id] = (all[npc.Id] or "") .. " " .. line
			end
		end
		T.check(#counts == 0, "p3ui: every NPC keeps 3-5 lines", table.concat(counts, ", "))
		T.check(#long == 0, "p3ui: every NPC line fits the dialog (<= 125 bytes, no rich-text characters)", table.concat(long, ", "))
		local function says(id, ...)
			local text = all[id] or ""
			for _, needle in ipairs({ ... }) do
				if not text:find(needle, 1, true) then
					return false
				end
			end
			return true
		end
		local raidMinutes = BC and BC.Events and BC.Events.Schedule and BC.Events.Schedule[1] and BC.Events.Schedule[1].EveryMinutes or 20
		local trials = BC and BC.TrialCount or 30
		local win = BC and BC.Trophies and BC.Trophies.Win or 20
		T.check(says("sparky_fox", "ATTACK", "RETREAT", "SPECIAL", "F = ", "R = "), "p3ui: Sparky Fox explains the battle controls (F ATTACK, R RETREAT, SPECIAL)")
		T.check(says("captain_penguin", "Boss Raid", "every " .. tostring(raidMinutes) .. " minutes", "RETREAT"),
			"p3ui: Captain Penguin explains Boss Raids (every " .. tostring(raidMinutes) .. " minutes) and dodging telegraphs")
		T.check(says("coach_corgi", "Trial Portal", tostring(trials) .. " levels", "Team", "+" .. tostring(win) .. " trophies"),
			"p3ui: Coach Corgi explains the Trial Portal, battle teams and trophies (+" .. tostring(win) .. ")")
		local strong = Config.Elements and Config.Elements.StrongMultiplier or 1.5
		T.check(says("professor_axolotl", "battles", "x" .. tostring(strong), "Power"), "p3ui: Professor Axolotl explains elements and synergy in battle")
		-- the Phase 2 tips stay
		T.check(says("coach_corgi", "Gym", "Train in Gym") and says("granny_owl", "Kitchen", "Feed", "Gems")
			and says("professor_axolotl", "Fusion Machine", "Storm Altar"), "p3ui: the Phase 2 tips (Gym, Kitchen, Fusion, Storm Altar) are still there")
	end)

	------------------------------------------------------------------------------------------------
	-- p3ui_tutorial
	------------------------------------------------------------------------------------------------
	local userSeq = 0
	local function join(prefix)
		userSeq = userSeq + 1
		local p = Mock.AddPlayer(prefix .. userSeq, 968000 + userSeq)
		advance(1.0)
		return p
	end

	local function leave(p)
		if p and p.Parent then
			Mock.RemovePlayer(p)
		end
		advance(0.6)
	end

	S.p3ui_tutorial = guarded("p3ui_tutorial", function()
		if not K.needBoot() then
			return
		end
		local TSv = mod("TutorialService")
		local DataS = mod("DataService")
		local BS = requireAt("server/Services/BattleService")
		local AB = requireAt("server/Services/ArenaBuilder")
		local Steps = requireAt("shared/TutorialSteps")
		local info = AB and AB.GetInfo and AB.GetInfo() or nil
		if not T.check(TSv and DataS and BS and info and Steps and type(TSv.Reload) == "function",
			"p3ui tutorial: TutorialService, DataService, BattleService and the arena (ArenaBuilder.GetInfo) are there") then
			return
		end
		local errors0 = #Mock.Errors
		local start = Steps.ChapterStart[3]
		local function state(p)
			return TSv.GetState(p)
		end
		local function stepId(p)
			local st = state(p)
			return st and not st.Done and st.Id or (st and st.Done and "done!") or nil
		end
		local function near(a, b, d)
			return typeof(a) == "Vector3" and typeof(b) == "Vector3" and (a - b).Magnitude <= (d or 1)
		end

		local p = join("ArenaTut")
		local prof = DataS.GetProfile(p)
		prof.Pets.pebble_pup = (prof.Pets.pebble_pup or 0) + 1
		prof.Pets.honey_bunny = (prof.Pets.honey_bunny or 0) + 1
		DataS.MarkDirty(p)
		DataS.SetTeam(p, 1, {})
		T.check(DataS.SetTutorial(p, { Step = start, Done = true, Gifted = true }) == true, "p3ui tutorial: a finished home chapter is stored (Step " .. start .. ", Done)")
		Mock.Teleport(p, CFrame.new(config().Lobby.Origin + Vector3.new(12, 4, 12)))
		TSv.Reload(p)
		advance(0.6)
		T.eq(stepId(p), "arena", "p3ui tutorial: a finished home chapter resumes at 'arena'")
		local st = state(p)
		T.check(st and st.Chapter == 3 and st.Step == start and st.Total == #Steps.Steps, "p3ui tutorial: ...as chapter 3, step " .. start .. "/" .. #Steps.Steps)
		T.check(st and st.Target and st.Target.Kind == "Spot" and near(st.Target.Position, info.Spawn.Position),
			"p3ui tutorial: the 'arena' arrow points at the arena's forum (ArenaInfo.Spawn, sent as a Spot target)")

		-- walking in
		Mock.Teleport(p, info.Spawn * CFrame.new(0, 3, 0))
		waitFor(function()
			return stepId(p) ~= "arena"
		end, 3)
		T.eq(stepId(p), "team", "p3ui tutorial: walking into the Battle Arena completes 'arena'")
		st = state(p)
		T.check(st and st.Target and st.Target.Kind == "Menu" and st.Target.Id == "Team", "p3ui tutorial: 'team' rings the Team tile (Menu Team)")
		advance(1)
		T.eq(stepId(p), "team", "p3ui tutorial: an empty team keeps 'team' waiting")

		-- a team
		local okTeam = DataS.SetTeam(p, 1, { "pebble_pup", "honey_bunny" })
		advance(0.6)
		T.check(okTeam == true, "p3ui tutorial: (setup) the team is saved")
		T.eq(stepId(p), "trial", "p3ui tutorial: a battle team completes 'team' (DataService.TeamsChanged)")
		st = state(p)
		T.check(st and st.Target and st.Target.Kind == "Spot" and near(st.Target.Position, info.TrialPortal.Position),
			"p3ui tutorial: 'trial' points at the Trial Portal (ArenaInfo.TrialPortal)")
		p:SetAttribute("InBattle", "test-battle")
		advance(1.2)
		st = state(p)
		T.check(st and st.Id == "trial" and st.Target == nil, "p3ui tutorial: no guide arrow while the player fights (InBattle)")
		p:SetAttribute("InBattle", nil)
		advance(1.2)
		st = state(p)
		T.check(st and st.Target ~= nil, "p3ui tutorial: ...and it comes back after the battle")

		-- Trial 1 cleared (the saved record, as BattleService writes it before BattleEnded)
		DataS.MutateBattle(p, function(b)
			b.TrialCleared = b.TrialCleared or {}
			b.TrialCleared[1] = true
			if (b.TrialBest or 0) < 1 then
				b.TrialBest = 1
			end
		end)
		waitFor(function()
			return stepId(p) ~= "trial"
		end, 3)
		T.eq(stepId(p), "raid", "p3ui tutorial: clearing Trial 1 completes 'trial'")
		st = state(p)
		T.check(st and st.Target and near(st.Target.Position, info.Floor.CFrame.Position), "p3ui tutorial: 'raid' points at the colosseum floor")
		T.check(st and tostring(st.Hint):find("Boss Raid", 1, true) ~= nil, "p3ui tutorial: 'raid' hints at the next Boss Raid", st and tostring(st.Hint))
		T.check(st and not tostring(st.Text):find("{", 1, true), "p3ui tutorial: the raid text has its minutes filled in", st and tostring(st.Text))
		advance(1)
		T.eq(stepId(p), "raid", "p3ui tutorial: no raid yet: 'raid' waits")

		-- a raid runs while the player stands in the arena
		local tokens0 = DataS.GetTokens(p)
		local okRaid = BS.StartRaid(nil)
		waitFor(function()
			return stepId(p) ~= "raid"
		end, 3)
		T.check(okRaid == true, "p3ui tutorial: (setup) a raid opens")
		st = state(p)
		T.check(st and st.Done == true and st.Completed == true, "p3ui tutorial: being in the arena during a Boss Raid ends the battle chapter")
		local paid = DataS.GetTokens(p) - tokens0
		local src = sourceOf("server/Services/TutorialService")
		local reward = type(src) == "string" and tonumber(src:match("local ARENA_FINISH_TOKENS = (%d+)")) or 500
		T.eq(paid, reward, "p3ui tutorial: ...and pays its token reward (" .. tostring(reward) .. ") once")
		TSv.HandleEvent(p, "Next")
		advance(0.6)
		T.eq(DataS.GetTokens(p) - tokens0, reward, "p3ui tutorial: nothing is paid twice")
		T.eq(DataS.GetTutorial(p).Step, #Steps.Steps + 1, "p3ui tutorial: the stored Step is one past the end")
		pcall(BS.EndRaid)
		waitFor(function()
			return BS.GetRaidStatus() == nil
		end, 20)
		leave(p)

		-- a trial win reported by BattleService completes 'trial' even before the record is read
		local q = join("TrialTut")
		DataS.SetTeam(q, 1, {})
		DataS.SetTutorial(q, { Step = Steps.IndexOf.trial, Done = true, Gifted = true })
		TSv.Reload(q)
		advance(0.4)
		T.eq(stepId(q), "trial", "p3ui tutorial: (setup) a player on 'trial'")
		BS.BattleEnded:Fire("ui-test", { Mode = "Trial", Winners = { q.UserId }, Losers = {}, Level = 1 })
		advance(0.6)
		T.eq(stepId(q), "raid", "p3ui tutorial: BattleService.BattleEnded (a trial the player won) completes 'trial'")
		BS.BattleEnded:Fire("ui-test-2", { Mode = "Raid", Winners = {}, Losers = {}, Participants = { q.UserId } })
		advance(0.6)
		T.eq(stepId(q), "done!", "p3ui tutorial: a raid the player fought in completes 'raid'")
		leave(q)

		local mine = 0
		for i = errors0 + 1, #Mock.Errors do
			if tostring(Mock.Errors[i].msg):find("Tutorial", 1, true) then
				mine = mine + 1
			end
		end
		T.eq(mine, 0, "p3ui tutorial: no script errors from TutorialService")
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
	local advance = KC and KC.advance or function(s)
		Mock.Advance(s)
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

	local function bootIfNeeded()
		if not ReplicatedStorage:FindFirstChild("Remotes") then
			local Config = moduleAt("shared", "Config")
			local folder = Instance.new("Folder")
			folder.Name = "Remotes"
			for _, n in ipairs(Config.Remotes) do
				local r = Instance.new("RemoteEvent")
				r.Name = n
				r.Parent = folder
			end
			folder.Parent = ReplicatedStorage
		end
		if not (pg() and pg():FindFirstChild("NimbusMenu")) then
			Mock.RunScript(Mock.GetPath(ROOTS["client"] .. "/Main"))
			advance(3)
		end
	end

	-- BattleRequest sends since `mark`: { {action, a, b}... }
	local function requests(mark)
		local out = {}
		for i = (mark or 0) + 1, #Mock.RemoteLog do
			local e = Mock.RemoteLog[i]
			if e.kind == "server" and e.remote == "BattleRequest" then
				local args = e.args or {}
				out[#out + 1] = { args[1], args[2], args[3] }
			end
		end
		return out
	end

	local function lastRequest(mark, action)
		local found = nil
		for _, r in ipairs(requests(mark)) do
			if r[1] == action then
				found = r
			end
		end
		return found
	end

	local function disabled(button)
		return button == nil or button:GetAttribute("Disabled") == true or button.Active == false
	end

	local function smallTexts(root, floorPx)
		local out = {}
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) then
				local size = d.TextSize
				if d.TextScaled then
					local c = d:FindFirstChildOfClass("UITextSizeConstraint")
					size = c and c.MinTextSize or size
				end
				if size < floorPx - 0.01 then
					out[#out + 1] = d.Name .. "=" .. tostring(size)
				end
			end
		end
		return out
	end

	local function smallOnScreen(root, floorPx)
		local out = {}
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) then
				local box = Mock.GuiBox(d)
				local scale = (box and box.scale) or 1
				local size = d.TextSize
				if d.TextScaled then
					local c = d:FindFirstChildOfClass("UITextSizeConstraint")
					size = c and c.MinTextSize or ((box and scale > 0) and box.h / scale or 0)
				end
				if size * scale < floorPx - 0.05 then
					out[#out + 1] = string.format("%s=%.1f", d.Name, size * scale)
				end
			end
		end
		return out
	end

	-- a profile with pets, levels, a 3-pet team (two Earth pets: a synergy), trophies and trials 1-6 cleared
	local TEAM = { "biscuit_bear", "ember_phoenix", "sunbeam_bear" }
	local OWNED = { "biscuit_bear", "ember_phoenix", "sunbeam_bear", "pebble_pup", "honey_bunny", "cloudy_dragon", "bubble_axolotl" }
	local function snapshot(prestige, presets)
		local pets, levels, discovered = {}, {}, {}
		for i, id in ipairs(OWNED) do
			pets[id] = 1
			levels[id] = { Level = 2 + i, Xp = 0 }
			discovered[id] = true
		end
		local cleared = {}
		for level = 1, 6 do
			cleared[level] = true
		end
		return {
			Tokens = 900,
			Pets = pets,
			Equipped = {},
			Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = discovered,
			IndexClaimed = {},
			Tutorial = { Step = 1000, Done = true, Gifted = true },
			Cash = 0, Gems = 0,
			Home = { Level = 5, Prestige = prestige or 0, Stations = {}, Garden = { "bubble_axolotl" }, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = {}, Hybrids = {},
			PetLevels = levels,
			Teams = { Presets = presets or { TEAM, { "pebble_pup" }, {} }, Active = 1, Slots = (prestige or 0) >= 1 and 4 or 3 },
			Battle = { Trophies = 340, TrialBest = 6, TrialCleared = cleared, Raids = 1, RaidBestDamage = 100, PvPWins = 9, PvPLosses = 4, EventPets = {} },
		}
	end

	local function arenaState(over)
		local s = {
			Next = { Kind = "BossRaid", BossId = "storm_titan", Name = "Storm Titan", StartsIn = 90, Announced = true },
			Raid = nil,
			Double = { Active = false },
			Leaderboard = {
				{ UserId = 501, Name = "StormChaser", Trophies = 1210 },
				{ UserId = LocalPlayer.UserId, Name = LocalPlayer.Name, Trophies = 340 },
				{ UserId = 503, Name = "PuddleFan", Trophies = 220 },
			},
		}
		for k, v in pairs(over or {}) do
			s[k] = v
		end
		return s
	end

	S.client_p3ui = guarded("client_p3ui", function()
		bootIfNeeded()
		local MC = (KC and KC.M and KC.M.MenuController) or moduleAt("client", "Controllers/MenuController")
		local AC = (KC and KC.M and KC.M.ArenaController) or moduleAt("client", "Controllers/ArenaController")
		local Config = moduleAt("shared", "Config")
		local PC = moduleAt("shared", "PetCatalog")
		if not T.check(type(MC) == "table" and type(MC.Open) == "function" and type(AC) == "table" and type(AC.OpenTrials) == "function",
			"p3ui: MenuController and ArenaController (OpenTrials / OpenArena / Close) load") then
			return
		end
		MC.Init()
		AC.Init()
		local errors0 = #Mock.Errors
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute("InBattle", nil)
		toClient("ProfileSync", snapshot(0))
		advance(0.5)

		------------------------------------------------------------ the Team tile + window
		local tile = MC.GetButton("Team")
		local label = tile and tile:FindFirstChild("Label")
		T.check(tile ~= nil and tile.Name == "MenuButton_Team" and label and label.Text == "Team", "p3ui team: the menu has a Team tile (MenuButton_Team)")
		Mock.Click(tile)
		advance(0.8)
		local menu = pg():FindFirstChild("NimbusMenu")
		local win = menu and menu:FindFirstChild("Window_Team")
		if not T.check(win ~= nil and shown(win), "p3ui team: the Team tile opens the Team window") then
			return
		end
		local slots = {}
		for i = 1, 4 do
			slots[i] = find(win, "Slot" .. i)
		end
		local first = PC and PC.Get(TEAM[1])
		local name1 = slots[1] and find(slots[1], "PetName")
		T.check(name1 and first and name1.Text == first.Name and shown(name1), "p3ui team: slot 1 shows the first team pet's name", name1 and name1.Text)
		local info1 = slots[1] and find(slots[1], "Info")
		T.check(info1 and info1.Text:find("Lv 3", 1, true) ~= nil, "p3ui team: ...its level", info1 and info1.Text)
		T.check(slots[1] and find(slots[1], "Element_Earth") ~= nil, "p3ui team: ...its element badge")
		local stats1 = slots[1] and find(slots[1], "Stats")
		T.check(stats1 and stats1.Text:find("%d") ~= nil, "p3ui team: ...and its battle stats (power, health)", stats1 and stats1.Text)
		local lock = slots[4] and find(slots[4], "Caption")
		T.check(lock and shown(lock) and lock.Text:find("Prestige", 1, true) ~= nil, "p3ui team: slot 4 is locked before Prestige 1", lock and lock.Text)
		local power = find(win, "PowerChip")
		local powerValue = power and find(power, "Value")
		T.check(powerValue and tonumber((powerValue.Text:gsub("[^%d]", ""))) and tonumber((powerValue.Text:gsub("[^%d]", ""))) > 0,
			"p3ui team: the team power is shown", powerValue and powerValue.Text)
		local trophy = find(win, "TrophyChip")
		T.check(trophy and find(trophy, "Value") and find(trophy, "Value").Text:find("340", 1, true) ~= nil, "p3ui team: the trophies are shown (340)")
		local synergy = find(win, "Synergy")
		local hasPair = false
		for _, d in ipairs(synergy and synergy:GetDescendants() or {}) do
			if d:IsA("TextLabel") and d.Text:find("Power for 2", 1, true) then
				hasPair = true
			end
		end
		T.check(hasPair, "p3ui team: the synergy panel shows the live Earth pair bonus (+10% Power for 2 Earth pets)")
		T.check(synergy and find(synergy, "StrongTitle") ~= nil and find(synergy, "WeakTitle") ~= nil, "p3ui team: ...and the team's matchups (hits hard / watch out)")
		local wheel = find(win, "ElementWheel")
		local nodes = 0
		for _, e in ipairs(Config.Elements.Order) do
			if wheel and find(wheel, "Element_" .. e) then
				nodes = nodes + 1
			end
		end
		T.eq(nodes, #Config.Elements.Order, "p3ui team: the element wheel shows all " .. #Config.Elements.Order .. " elements")
		local grid = find(win, "PickerGrid")
		local picks = {}
		for _, c in ipairs(grid and grid:GetChildren() or {}) do
			if c:IsA("TextButton") then
				picks[c.Name] = c
			end
		end
		local n = 0
		for _ in pairs(picks) do
			n = n + 1
		end
		T.eq(n, #OWNED, "p3ui team: the picker lists every owned pet copy")
		local busy = picks.Pick_bubble_axolotl
		T.check(busy and find(busy, "Dim") and shown(find(busy, "Dim")), "p3ui team: a pet working in the Garden is dimmed in the picker")
		local inTeam = picks["Pick_" .. TEAM[2]]
		T.check(inTeam and find(inTeam, "InTeam") and shown(find(inTeam, "InTeam")), "p3ui team: team pets carry their slot number in the picker")
		local small = smallTexts(win, 18)
		T.check(#small == 0, "p3ui team: every text of the Team window is >= 18 design px", table.concat(small, ", "))

		-- editing: a full team refuses, remove -> TeamSet, add -> TeamSet, busy refuses
		local mark = #Mock.RemoteLog
		Mock.Click(picks.Pick_pebble_pup)
		advance(0.8)
		T.check(lastRequest(mark, "TeamSet") == nil, "p3ui team: adding a 4th pet to a full 3-slot team sends nothing")
		mark = #Mock.RemoteLog
		Mock.Click(find(slots[3], "Remove"))
		advance(0.8)
		local r = lastRequest(mark, "TeamSet")
		T.check(r and r[2] == 1 and type(r[3]) == "table" and #r[3] == 2 and r[3][1] == TEAM[1] and r[3][2] == TEAM[2],
			"p3ui team: removing slot 3 sends BattleRequest('TeamSet', 1, {the other two})", r and tostring(r[3] and #r[3]))
		T.check(slots[3] and find(slots[3], "EmptyFace") and shown(find(slots[3], "EmptyFace")), "p3ui team: ...and slot 3 shows empty at once")
		mark = #Mock.RemoteLog
		Mock.Click(picks.Pick_pebble_pup)
		advance(0.8)
		r = lastRequest(mark, "TeamSet")
		T.check(r and r[2] == 1 and #r[3] == 3 and r[3][3] == "pebble_pup", "p3ui team: tapping a pet adds it to the free slot (TeamSet with 3 keys)")
		mark = #Mock.RemoteLog
		Mock.Click(busy)
		advance(0.8)
		T.check(lastRequest(mark, "TeamSet") == nil, "p3ui team: a pet busy in the Garden is not added")
		-- swap: tap slot 1, then a pet
		mark = #Mock.RemoteLog
		Mock.Click(slots[1])
		advance(0.1)
		Mock.Click(picks.Pick_cloudy_dragon)
		advance(0.8)
		r = lastRequest(mark, "TeamSet")
		T.check(r and r[3][1] == "cloudy_dragon" and #r[3] == 3, "p3ui team: tapping a slot, then a pet, swaps it in")
		-- the server's answer arrives
		toClient("ProfileSync", snapshot(0))
		advance(5)
		-- presets: Team 2 + Use Team 2
		mark = #Mock.RemoteLog
		Mock.Click(find(win, "Preset2"))
		advance(0.3)
		local name2 = find(slots[1], "PetName")
		T.check(name2 and name2.Text == ((PC.Get("pebble_pup") or {}).Name or "?"), "p3ui team: the Team 2 tab shows preset 2", name2 and name2.Text)
		local use = find(win, "UseTeam")
		T.check(use and shown(use) and not disabled(use), "p3ui team: a preset that is not the battle team offers 'Use Team 2'")
		Mock.Click(use)
		advance(0.4)
		r = lastRequest(mark, "TeamSelect")
		T.check(r and r[2] == 2, "p3ui team: 'Use Team 2' sends BattleRequest('TeamSelect', 2)")
		-- Prestige 1: four slots
		toClient("ProfileSync", snapshot(1))
		advance(4.5)
		Mock.Click(find(win, "Preset1"))
		advance(0.3)
		local face4 = find(slots[4], "Caption")
		T.check(face4 and face4.Text:find("Prestige", 1, true) == nil, "p3ui team: at Prestige 1 slot 4 opens", face4 and face4.Text)
		MC.Close()
		advance(0.4)

		-- the Stats window's battle record
		MC.Open("Stats")
		advance(0.6)
		local stats = menu:FindFirstChild("Window_Stats")
		local record = stats and find(stats, "Battle")
		local lines = record and find(record, "Lines")
		T.check(lines and lines.Text:find("340", 1, true) and lines.Text:find("Trial best: 6", 1, true), "p3ui stats: the Stats window shows trophies and the trial best", lines and lines.Text)
		MC.Close()
		advance(0.4)

		------------------------------------------------------------ the Trial window
		local arena = pg():FindFirstChild("NimbusArena")
		T.check(arena ~= nil, "p3ui arena: ArenaController builds the ScreenGui NimbusArena")
		toClient("OpenPanel", "Trials", { Level = 3 })
		advance(0.8)
		local trialsWin = arena and arena:FindFirstChild("Window_Trials")
		if not T.check(trialsWin and shown(trialsWin) and AC.IsOpen(), "p3ui trials: OpenPanel('Trials') opens the Trial window") then
			return
		end
		local tiles = 0
		for level = 1, 30 do
			if find(trialsWin, "Level" .. level) then
				tiles = tiles + 1
			end
		end
		T.eq(tiles, 30, "p3ui trials: 30 level tiles")
		local function tilePart(level, part)
			local t = find(trialsWin, "Level" .. level)
			local p = t and t:FindFirstChild(part)
			return p and shown(p)
		end
		T.check(tilePart(1, "Cleared") and tilePart(6, "Cleared") and not tilePart(7, "Cleared"), "p3ui trials: cleared levels carry the first-clear check (1-6)")
		T.check(not tilePart(7, "Lock") and tilePart(8, "Lock") and tilePart(30, "Lock"), "p3ui trials: the next level is open, later ones locked")
		T.check(tilePart(5, "Boss") and tilePart(10, "Boss") and not tilePart(7, "Boss"), "p3ui trials: mini-boss levels are tagged BOSS")
		local levelLabel = find(trialsWin, "Level")
		T.check(levelLabel and levelLabel.Text == "LEVEL 3", "p3ui trials: OpenPanel's Level selects it", levelLabel and levelLabel.Text)
		local enemies = find(trialsWin, "Enemies")
		local enemyCount = 0
		for _, c in ipairs(enemies and enemies:GetChildren() or {}) do
			if c:IsA("Frame") then
				enemyCount = enemyCount + 1
			end
		end
		T.check(enemyCount >= 3, "p3ui trials: the enemy team is shown", tostring(enemyCount))
		T.check(find(trialsWin, "RecValue") and find(trialsWin, "TeamValue") and find(trialsWin, "Verdict").Text ~= "", "p3ui trials: recommended power vs. the team's power, with a verdict")
		local start = find(trialsWin, "Start")
		mark = #Mock.RemoteLog
		AC.SelectLevel(8)
		advance(0.3)
		T.check(disabled(start) and find(trialsWin, "Why").Text:find("level 7", 1, true), "p3ui trials: START is off for a locked level (beat level 7 first)", find(trialsWin, "Why").Text)
		Mock.Click(start)
		advance(0.6)
		T.check(lastRequest(mark, "Trial") == nil, "p3ui trials: ...and sends nothing")
		AC.SelectLevel(7)
		advance(0.3)
		T.check(not disabled(start), "p3ui trials: START is on for the next level")
		Mock.Click(start)
		advance(0.6)
		r = lastRequest(mark, "Trial")
		T.check(r and r[2] == 7, "p3ui trials: START sends BattleRequest('Trial', 7)")
		local small2 = smallTexts(trialsWin, 18)
		T.check(#small2 == 0, "p3ui trials: every text of the Trial window is >= 18 design px", table.concat(small2, ", "))
		-- one window at a time
		MC.Open("Team")
		advance(0.5)
		T.check(not AC.IsOpen(), "p3ui arena: a menu window closes the Trial window")
		MC.Close()
		advance(0.4)

		------------------------------------------------------------ prompts + the Arena panel
		toClient("ArenaState", arenaState())
		advance(0.2)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BoardPrompt"
		prompt:SetAttribute("OpenPanel", "Arena")
		prompt:SetAttribute("OpenPanelTab", "Leaderboard")
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.Parent = workspace
		prompt.Parent = holder
		Mock.Trigger(prompt, LocalPlayer)
		advance(0.8)
		local arenaWin = arena:FindFirstChild("Window_Arena")
		T.check(arenaWin and shown(arenaWin) and AC.GetState().Tab == "Leaderboard", "p3ui arena: a board prompt (OpenPanel Arena, OpenPanelTab Leaderboard) opens the leaders tab")
		local rows = 0
		local mine = nil
		for i = 1, 10 do
			local row = find(arenaWin, "Rank" .. i)
			if row then
				rows = rows + 1
				local nm = row:FindFirstChild("Name")
				if nm and nm.Text:find("(you)", 1, true) then
					mine = i
				end
			end
		end
		T.eq(rows, 3, "p3ui arena: one leaderboard row per ArenaState.Leaderboard entry")
		T.eq(mine, 2, "p3ui arena: the player's own row is marked (you)")
		local small3 = smallTexts(arenaWin, 18)
		T.check(#small3 == 0, "p3ui arena: every text of the leaders tab is >= 18 design px", table.concat(small3, ", "))
		-- a duel pad prompt (RingIndex) opens the Duels tab
		local pad = Instance.new("ProximityPrompt")
		pad.Name = "DuelPrompt"
		pad:SetAttribute("OpenPanel", "Arena")
		pad:SetAttribute("RingIndex", 1)
		pad:SetAttribute("PadIndex", 1)
		pad.Parent = holder
		Mock.Trigger(pad, LocalPlayer)
		advance(0.6)
		T.eq(AC.GetState().Tab, "Duels", "p3ui arena: a duel pad prompt opens the Duels tab")
		mark = #Mock.RemoteLog
		Mock.Click(find(arenaWin, "Queue"))
		advance(0.3)
		T.check(lastRequest(mark, "Queue") ~= nil, "p3ui arena: 'Find a match' sends BattleRequest('Queue')")
		local small4 = smallTexts(arenaWin, 18)
		T.check(#small4 == 0, "p3ui arena: every text of the Duels tab is >= 18 design px", table.concat(small4, ", "))
		AC.OpenArena("Raid")
		toClient("ArenaState", arenaState({ Raid = { Active = true, BossId = "lava_golem", Name = "Lava Golem", Hp = 500, MaxHp = 1000, Players = 2, EndsIn = 200, Joinable = true, JoinEndsIn = 40, Waiting = false, BattleId = "raid-1" } }))
		advance(0.5)
		mark = #Mock.RemoteLog
		local join = find(arenaWin, "JoinRaid")
		T.check(join and shown(join) and not disabled(join), "p3ui arena: the Raid tab offers JOIN RAID while the raid can be joined")
		Mock.Click(join)
		advance(0.3)
		T.check(lastRequest(mark, "JoinRaid") ~= nil, "p3ui arena: JOIN RAID sends BattleRequest('JoinRaid')")
		local small5 = smallTexts(arenaWin, 18)
		T.check(#small5 == 0, "p3ui arena: every text of the Raid tab is >= 18 design px", table.concat(small5, ", "))
		AC.Close()
		advance(0.4)

		------------------------------------------------------------ side cards
		local side = pg():FindFirstChild("NimbusArenaSide")
		toClient("BattleState", "Lobby", {
			Queue = { Queued = true, Waiting = 2, Seconds = 5 },
			Invites = { { FromUserId = 501, FromName = "StormChaser", Trophies = 1210, Power = 900, ExpiresIn = 25 } },
		})
		advance(0.6)
		local stack = side and side:FindFirstChild("SideStack")
		local invite = stack and stack:FindFirstChild("Invite1")
		T.check(invite and shown(invite), "p3ui side: a duel invite shows as a side card")
		if stack then
			local cx = stack.AbsolutePosition.X + stack.AbsoluteSize.X / 2
			T.check(cx > Mock.Viewport.X * 0.6, "p3ui side: the side cards sit at the right edge, never in the screen centre", tostring(cx))
		end
		mark = #Mock.RemoteLog
		Mock.Click(invite and find(invite, "Accept"))
		advance(0.3)
		r = lastRequest(mark, "ChallengeReply")
		T.check(r and r[2] == 501 and r[3] == true, "p3ui side: Accept sends BattleRequest('ChallengeReply', 501, true)")
		local queue = stack and stack:FindFirstChild("Queue")
		mark = #Mock.RemoteLog
		Mock.Click(queue and find(queue, "Leave"))
		advance(0.3)
		T.check(lastRequest(mark, "Unqueue") ~= nil, "p3ui side: the queue card's Leave sends BattleRequest('Unqueue')")
		local raidCard = stack and stack:FindFirstChild("Raid")
		T.check(raidCard and shown(raidCard), "p3ui side: an open raid shows the raid join card")
		mark = #Mock.RemoteLog
		Mock.Click(raidCard and find(raidCard, "Join"))
		advance(0.3)
		T.check(lastRequest(mark, "JoinRaid") ~= nil, "p3ui side: the raid card's JOIN sends BattleRequest('JoinRaid')")
		toClient("ArenaState", arenaState({ Next = { Kind = "BossRaid", BossId = "frost_wyrm", Name = "Frost Wyrm", StartsIn = 75 } }))
		toClient("BattleState", "Lobby", { Queue = { Queued = false, Waiting = 0 }, Invites = {} })
		advance(0.6)
		local chip = stack and stack:FindFirstChild("Countdown")
		local clock = chip and find(chip, "Clock")
		T.check(chip and shown(chip) and clock and clock.Text:match("^1:1%d$"), "p3ui side: an announced raid shows the countdown chip (1:1x)", clock and clock.Text)
		local small6 = smallTexts(side, 18)
		T.check(#small6 == 0, "p3ui side: every side card text is >= 18 design px", table.concat(small6, ", "))
		LocalPlayer:SetAttribute("InBattle", "some-battle")
		advance(0.6)
		T.check(stack and not shown(stack), "p3ui side: the side cards hide while the player fights")
		LocalPlayer:SetAttribute("InBattle", nil)
		advance(0.6)
		T.check(stack and shown(stack), "p3ui side: ...and come back afterwards")
		holder:Destroy()

		local errs = {}
		for i = errors0 + 1, #Mock.Errors do
			local msg = tostring(Mock.Errors[i].msg)
			if msg:find("ArenaController", 1, true) or msg:find("MenuController", 1, true) then
				errs[#errs + 1] = msg:sub(1, 160)
			end
		end
		T.check(#errs == 0, "p3ui: no script errors from ArenaController / MenuController", table.concat(errs, " | "))
		if KC and KC.flushErrors then
			KC.flushErrors("client_p3ui")
		end
	end)

	S.client_p3ui_mobile = guarded("client_p3ui_mobile", function()
		bootIfNeeded()
		local MC = moduleAt("client", "Controllers/MenuController")
		local AC = moduleAt("client", "Controllers/ArenaController")
		if not T.check(type(MC) == "table" and type(AC) == "table", "p3ui phone: MenuController and ArenaController load") then
			return
		end
		MC.Init()
		AC.Init()
		toClient("ProfileSync", snapshot(1))
		toClient("ArenaState", arenaState({ Raid = { Active = true, BossId = "storm_titan", Name = "Storm Titan", Hp = 900, MaxHp = 1000, Players = 3, EndsIn = 120, Joinable = true, JoinEndsIn = 30 } }))
		advance(0.5)
		local function check(label, root)
			local small = smallOnScreen(root, 14)
			T.check(root ~= nil and #small == 0, "p3ui phone 390x844: every text of " .. label .. " is >= 14 px on screen", table.concat(small, ", "))
		end
		MC.Open("Team")
		advance(0.8)
		check("the Team window", pg():FindFirstChild("NimbusMenu"):FindFirstChild("Window_Team"))
		MC.Close()
		advance(0.3)
		AC.OpenTrials(12)
		advance(0.8)
		local arena = pg():FindFirstChild("NimbusArena")
		check("the Trial window", arena and arena:FindFirstChild("Window_Trials"))
		for _, tab in ipairs({ "Duels", "Raid", "Leaderboard" }) do
			AC.OpenArena(tab)
			advance(0.6)
			check("the Arena panel (" .. tab .. ")", arena and arena:FindFirstChild("Window_Arena"))
		end
		AC.Close()
		advance(0.4)
		toClient("BattleState", "Lobby", { Queue = { Queued = true, Waiting = 1, Seconds = 3 }, Invites = { { FromUserId = 9, FromName = "Buddy", Trophies = 10, Power = 50, ExpiresIn = 20 } } })
		advance(0.6)
		check("the side cards", pg():FindFirstChild("NimbusArenaSide"))
		toClient("BattleState", "Lobby", { Queue = { Queued = false, Waiting = 0 }, Invites = {} })
		advance(0.3)

		-- the seven-tile menu (Team added) on a landscape phone: still two labelled columns above Roblox's thumbstick
		-- (the "SmallGrid": smaller tiles, labels >= 14 px) instead of icon-only tiles, and about as wide as the
		-- six-tile grid it replaced (the HUD's party panel, the tutorial card and the home pad signs lay out around it)
		Mock.SetViewport(844, 390)
		advance(0.8)
		local column = pg():FindFirstChild("NimbusMenu") and pg().NimbusMenu:FindFirstChild("MenuColumn")
		if T.check(column ~= nil and shown(column), "p3ui phone 844x390: the menu column is shown") then
			local xs, labels, small, entries = {}, 0, {}, 0
			for _, entry in ipairs(column:GetChildren()) do
				if entry:IsA("GuiObject") and entry.Name:find("^Entry_") then
					entries = entries + 1
					local box = Mock.GuiBox(entry)
					if box then
						xs[math.floor(box.x + 0.5)] = true
					end
					local label = entry:FindFirstChild("Label", true)
					if label and shown(label) then
						labels = labels + 1
						local c = label:FindFirstChildOfClass("UITextSizeConstraint")
						local lb = Mock.GuiBox(label)
						local px = (c and c.MaxTextSize or label.TextSize) * ((lb and lb.scale) or 1)
						if px < 14 - 0.05 then
							small[#small + 1] = string.format("%s %.1f px", entry.Name, px)
						end
					end
				end
			end
			local cols = 0
			for _ in pairs(xs) do
				cols = cols + 1
			end
			local cb = Mock.GuiBox(column)
			T.check(entries == 7 and cols == 2, "p3ui phone 844x390: seven tiles (Team included) in two columns", entries .. " tiles, " .. cols .. " columns")
			T.check(labels == 7 and #small == 0, "p3ui phone 844x390: every tile keeps its label, >= 14 px", labels .. " labels; " .. table.concat(small, ", "))
			T.check(cb ~= nil and cb.w >= 150 and cb.w <= 185, "p3ui phone 844x390: the column is about as wide as the six-tile grid was (150-185 px)", cb and string.format("%.0f px", cb.w) or "no box")
			-- gui-area pixels, like MenuController's own band (the classic stick's top is 96 px above the area's bottom)
			local area = Mock.GuiLayerSize(column)
			local bottom = column.AbsolutePosition.Y + column.AbsoluteSize.Y
			T.check(area ~= nil and bottom <= area.Y - 96 + 0.5, "p3ui phone 844x390: the column ends above Roblox's thumbstick",
				area and string.format("bottom %.0f vs stick top %.0f", bottom, area.Y - 96) or "?")
		end
		Mock.SetViewport(390, 844)
		advance(0.6)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
