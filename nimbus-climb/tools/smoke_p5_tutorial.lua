-- smoke_p5_tutorial.lua: Phase 5 tutorial + NPC tips (ARCHITECTURE_V3.md "Phase 5 build contract" 8, owner tutorial W4):
-- shared/TutorialSteps.lua, server/Services/TutorialService.lua, client/Controllers/TutorialController.lua (the UiGate
-- wait, Portal_Obby) and shared/NpcDialog.lua. Loaded by tools/smoke.py in BOTH worlds (the client half is empty):
--   p5ui_content        (server, pure) the index rule (21 steps; chapters start at 1 / 10 / 15 / 19; step 17 is
--                       "dungeon"), every step text 97-125 bytes once its placeholders are filled, plain text, no
--                       Trial / RETREAT / rainbow coins; the contract texts of chapter 2 and the dungeon step; the targets
--                       (portal -> Obby, coins, machine = Berry Farm pad then the Food Machine pad, feed, dungeon ->
--                       Place Dungeon / DungeonWon); TutorialService knows DungeonWon (not TrialWon), FloorCleared,
--                       StartSolo, the berries top-up; TutorialController waits for UiGate.WaitForPlay and finds
--                       Portal_Obby; NPC lines <= 125 bytes, 3-5 per NPC, the Phase 5 needles with the catalogs' numbers
--                       (Berry Farm, Food Bowl, Cloud Cash, Berry Basket, Dungeon floors, a fighter + 2 helpers, the
--                       battle keys, the Obby portal, EvolutionBonusOf), no stale words
--   p5ui_portal_obby    (server, booted) the chapter-1 portal step points at lobby.Portals.Obby; stepping on the Obby
--                       pad starts a match and completes it
--   p5ui_tutorial_ch2   (server, booted) steps 10-14 against a Phase 5 home: claim -> garden (the Pet Garden pad, then a
--                       bed) -> coins (the Garden until the first poop, then the biggest TycoonService.Drops drop; scooping
--                       completes it) -> machine (the Berry Farm pad, then the Food Machine pad) -> feed (the Hopper; the
--                       berries are topped up to 500 once, a real Feed completes chapter 2 and pays $1,000 once); resume
--                       from every index 1-21 lands on that step (8 'finish' passes at once outside a match)
--   p5dgn_tutorial      (server, booted) chapter 3: team -> dungeon with the arrow at the Dungeon gate's pad (none
--                       while fighting), standing on the pad opens OpenPanel("Dungeon", { Floor = 1 }) once, floor 1
--                       cleared (DungeonService.FloorCleared) -> raid; the saved Dungeon record and a legacy
--                       TrialCleared[1] skip the step; an old Mode "Trial" BattleEnded completes nothing
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

-- this file's folder ("tools/") from the chunk name smoke.py gives it ("=tools/smoke_p5_tutorial.lua")
local HERE = (debug.getinfo(1, "S").source or ""):match("^=(.*)smoke_p5_tutorial%.lua$") or ""

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

local IDS = "welcome,home,shop,spin,equip,index,portal,finish,done,claim,garden,coins,machine,feed,arena,team,dungeon,raid,train,ring,portal"

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
	-- p5ui_content
	------------------------------------------------------------------------------------------------
	S.p5ui_content = guarded("p5ui_content", function()
		local Steps = requireAt("shared/TutorialSteps")
		local ND = requireAt("shared/NpcDialog")
		local PC = requireAt("shared/PetCatalog")
		local BC = requireAt("shared/BattleCatalog")
		local Config = config()
		if not T.check(type(Steps) == "table" and type(Steps.Steps) == "table" and type(ND) == "table", "p5ui: TutorialSteps and NpcDialog load") then
			return
		end
		local s = Steps.Steps
		local ids = {}
		for i, step in ipairs(s) do
			ids[i] = step.Id
		end
		T.eq(table.concat(ids, ","), IDS, "p5ui: 21 steps, indices never move (17 'trial' -> 'dungeon')")
		local st = Steps.ChapterStart or {}
		T.check(st[1] == 1 and st[2] == 10 and st[3] == 15 and st[4] == 19, "p5ui: chapters start at 1 / 10 / 15 / 19")
		T.eq(Steps.IndexOf and Steps.IndexOf.dungeon, 17, "p5ui: IndexOf.dungeon = 17 (a saved Step 17 lands on it)")
		T.check(Steps.IndexOf and Steps.IndexOf.trial == nil, "p5ui: no 'trial' step any more")

		-- texts: 97-125 bytes with the placeholders filled, plain text, no stale words
		local gift = tostring(Config.Tutorial.GiftTokens)
		local finish = tostring(Config.Tutorial.FinishReward and Config.Tutorial.FinishReward.Tokens or Config.Tutorial.FinishReward)
		local bad, stale = {}, {}
		for i, step in ipairs(s) do
			local text = tostring(step.Text):gsub("{GiftTokens}", gift):gsub("{FinishTokens}", finish)
			if #text < 97 or #text > 125 or text:find("[<>&{}]") then
				bad[#bad + 1] = i .. ":" .. step.Id .. " (" .. #text .. ")"
			end
			for _, word in ipairs({ "Trial", "RETREAT", "rainbow", "Easy portal", "4th", "Collector", "Carrot", "Magnet" }) do
				if text:find(word, 1, true) or tostring(step.Hint or ""):find(word, 1, true) then
					stale[#stale + 1] = step.Id .. ":" .. word
				end
			end
		end
		T.check(#bad == 0, "p5ui: every step text is 97-125 bytes of plain text once its placeholders are filled", table.concat(bad, ", "))
		T.check(#stale == 0, "p5ui: no step talks about Trials, RETREAT, rainbow coins, the Easy portal, a 4th slot, the Collector, plants or the Magnet", table.concat(stale, ", "))

		-- the contract texts (section 8)
		local evo = PC and PC.EvolutionLevels and PC.EvolutionLevels[1] or 20
		local floorOne = BC and BC.DungeonFloors and BC.DungeonFloors[1] and BC.DungeonFloors[1].Name or "Mossy Cellar"
		T.eq(s[11].Text, "Your pets make the money! Build your free Pet Garden, then press E on a pet bed to put a pet in it.", "p5ui: 11 'garden' text")
		T.eq(s[12].Text, "Garden pets roam your yard, eat at the Food Bowl and poop Cloud Cash. Only you can scoop it: walk over it!", "p5ui: 12 'coins' text")
		T.eq(s[13].Text, "Build the Berry Farm, then the Food Machine: the farm grows berries and the machine turns them into XP!", "p5ui: 13 'machine' text")
		T.eq(s[14].Text, "Press E at the Food Machine and press Feed: your berries become XP. At level " .. evo .. " your pet can EVOLVE!", "p5ui: 14 'feed' text (level " .. evo .. ")")
		T.check(s[16].Text:find("(a fighter + 2 helpers)", 1, true) ~= nil, "p5ui: 16 'team' says (a fighter + 2 helpers)")
		T.check(s[17].Title == "Into the Dungeon!" and s[17].Hint == "Clear Dungeon floor 1" and s[17].Text:find("Floor 1: the " .. floorOne, 1, true) ~= nil
			and s[17].Text:find("helpers buff", 1, true) ~= nil, "p5ui: 17 'dungeon' = Into the Dungeon!, Floor 1: the " .. floorOne .. ", helpers buff")

		-- targets
		local function t(i)
			return type(s[i].Target) == "table" and s[i].Target or {}
		end
		T.check(t(7).Kind == "Portal" and t(7).Id == "Obby" and t(7).Label == "Obby portal" and s[7].CompleteOn == "MatchStarted"
			and s[7].Hint == "Stand on the Obby pad", "p5ui: 7 'portal' -> { Portal, Obby, 'Obby portal' } -> MatchStarted")
		T.check(t(11).GardenSpot == true and s[11].CompleteOn == "GardenPlaced", "p5ui: 11 'garden' -> the first empty open bed -> GardenPlaced")
		T.check(t(12).Coins == true and s[12].CompleteOn == "CoinsScooped", "p5ui: 12 'coins' -> the biggest drop -> CoinsScooped")
		T.check(t(13).Pad == "Kitchen" and t(13).Path == true and s[13].CompleteOn == "Built" and s[13].Station == "Kitchen"
			and tostring(s[13].Hint):find("Berry Farm", 1, true) ~= nil, "p5ui: 13 'machine' -> the Farm pad, then the Kitchen pad -> Built Kitchen")
		T.check(t(14).Food == true and s[14].CompleteOn == "Fed" and s[14].ChapterEnd == true, "p5ui: 14 'feed' -> the machine -> Fed (ChapterEnd)")
		T.check(t(17).Kind == "Arena" and t(17).Place == "Dungeon" and t(17).Label == "Dungeon portal" and s[17].CompleteOn == "DungeonWon",
			"p5ui: 17 'dungeon' -> { Arena, Place Dungeon } -> DungeonWon")
		T.check(t(20).Place == "Ring" and s[18].ChapterEnd == true and s[21].ChapterEnd == true, "p5ui: 20 'ring' keeps Place Ring; 18 / 21 end their chapters")

		-- the server and the client
		local src = sourceOf("server/Services/TutorialService") or ""
		T.check(src:find("DungeonWon = true", 1, true) ~= nil and not src:find("TrialWon = true", 1, true) and not src:find("trialOneCleared", 1, true)
			and src:find("dungeonOneCleared", 1, true) ~= nil and src:find("FloorCleared", 1, true) ~= nil and src:find("StartSolo", 1, true) ~= nil
			and not src:find("TrialPortal", 1, true) and not src:find('Mode == "Trial"', 1, true),
			"p5ui: TutorialService: KNOWN_COMPLETE_ON - TrialWon + DungeonWon, dungeonOneCleared, FloorCleared, impossible() reads StartSolo, no Trial branch")
		T.check(src:find("AddBerries", 1, true) ~= nil and src:match("local FEED_BERRIES = (%d+)") == "500" and src:find("TycoonService.Drops", 1, true) ~= nil,
			"p5ui: TutorialService tops the berries up (FEED_BERRIES 500, DataService.AddBerries) and reads TycoonService.Drops")
		local csrc = sourceOf("client/Controllers/TutorialController") or ""
		T.check(csrc:find("WaitForPlay", 1, true) ~= nil and csrc:find('"Obby"', 1, true) ~= nil and not csrc:find('"Easy"', 1, true),
			"p5ui: TutorialController waits for UiGate.WaitForPlay and finds Portal_Obby")

		-- NPC tips
		local long, counts, said, all = {}, {}, {}, ""
		for _, npc in ipairs(ND.Npcs or {}) do
			local n = #(npc.Lines or {})
			if n < 3 or n > 5 then
				counts[#counts + 1] = npc.Id .. "=" .. n
			end
			for i, line in ipairs(npc.Lines or {}) do
				if #line > 125 or line:find("[<>&]") then
					long[#long + 1] = npc.Id .. "#" .. i .. " (" .. #line .. ")"
				end
				said[npc.Id] = (said[npc.Id] or "") .. " " .. line
				all = all .. " " .. line
			end
		end
		T.eq(#(ND.Npcs or {}), 6, "p5ui: six NPCs")
		T.check(#counts == 0, "p5ui: every NPC has 3-5 lines", table.concat(counts, ", "))
		T.check(#long == 0, "p5ui: every NPC line is <= 125 bytes without < > &", table.concat(long, ", "))
		local function says(id, ...)
			local text = said[id] or ""
			local miss = {}
			for _, needle in ipairs({ ... }) do
				if not text:find(needle, 1, true) then
					miss[#miss + 1] = needle
				end
			end
			return #miss == 0, table.concat(miss, " | ")
		end
		local function lineOf(id, i)
			local npc = ND.Get and ND.Get(id)
			return npc and npc.Lines and npc.Lines[i] or ""
		end
		T.eq(lineOf("mayor_panda", 2), "Your garden pets roam your yard, eat at the Food Bowl and poop Cloud Cash. Only you can scoop it: walk over it!", "p5ui: Mayor Panda 2")
		T.eq(lineOf("mayor_panda", 3), "Level up your Berry Farm: bigger berries make bigger Cloud Cash, and more berries for the Food Machine!", "p5ui: Mayor Panda 3")
		T.eq(lineOf("granny_owl", 4), "Your farm fills the Berry Basket. Press E at the Food Machine, pick a pet and press Feed: berries become XP!", "p5ui: Granny Owl 4")
		T.eq(lineOf("coach_corgi", 5), "Your team is a fighter and two helpers: ATTACK, ELEMENT, SPECIAL and DASH; tap a helper for its buff!", "p5ui: Coach Corgi 5")
		local bonus = PC and type(PC.EvolutionBonusOf) == "function" and tonumber(PC.EvolutionBonusOf(1)) or 1.5
		local faster = tostring(math.floor((bonus - 1) * 100 + 0.5)) .. "%"
		local floors = BC and BC.Dungeon and tonumber(BC.Dungeon.Floors) or 12
		local okA, whyA = says("granny_owl", "Berry Basket", "EVOLVE", "new look", "grow " .. faster .. " faster per level")
		T.check(okA, "p5ui: Granny Owl: the Berry Basket, EVOLVE's new look, evolved pets grow " .. faster .. " faster (EvolutionBonusOf)", whyA)
		local okB, whyB = says("coach_corgi", "Dungeon portal", tostring(floors) .. " floors", "Gems", "Team", "+" .. tostring(BC and BC.Trophies and BC.Trophies.Win or 20) .. " trophies")
		T.check(okB, "p5ui: Coach Corgi: the Dungeon (" .. floors .. " floors from BattleCatalog.Dungeon), Team and trophies", whyB)
		local okC, whyC = says("sparky_fox", "F = ATTACK", "E = ELEMENT", "Q = SPECIAL", "Shift = DASH", "helper", "SWAP")
		T.check(okC, "p5ui: Sparky Fox: the battle keys (F / E / Q / Shift, helpers 1 / 2, SWAP)", whyC)
		local okD, whyD = says("captain_penguin", "Obby portal", "level", "DASH", "safe zone", "Dungeon")
		T.check(okD, "p5ui: Captain Penguin: the Obby portal's levels, DASH out of telegraphs, safe zones", whyD)
		local staleNpc = {}
		for _, word in ipairs({ "Trial", "RETREAT", "rainbow coins", "Berry Bush", "Carrot Patch", "Magnet", "4th", "R = " }) do
			if all:find(word, 1, true) then
				staleNpc[#staleNpc + 1] = word
			end
		end
		T.check(#staleNpc == 0, "p5ui: no NPC talks about Trials, RETREAT, rainbow coins, the four plants, the Coin Magnet or a 4th team pet", table.concat(staleNpc, ", "))
		local kw = {}
		for _, npc in ipairs(ND.Npcs or {}) do
			for _, word in ipairs(npc.Keywords or {}) do
				kw[word] = true
			end
		end
		T.check(kw["Berry Farm"] and kw["Food Bowl"] and kw["Cloud Cash"] and kw["Berry Basket"] and kw["Dungeon"] and not kw["Trial Portal"]
			and not kw["rainbow coins"] and not kw["Berry Bush"] and not kw["RETREAT"],
			"p5ui: NPC keywords: Berry Farm, Food Bowl, Cloud Cash, Berry Basket, Dungeon replace Trial Portal, rainbow coins, Berry Bush, RETREAT")
		-- the p3ui needles stay
		local okE = says("coach_corgi", "Team", "+20 trophies") and says("granny_owl", "Gems") and says("professor_axolotl", "Fusion Machine", "Storm Altar")
		T.check(okE, "p5ui: the kept p3ui needles (Coach Corgi Team / +20 trophies, Granny Owl Gems, Professor Axolotl Fusion Machine / Storm Altar)")
	end)

	------------------------------------------------------------------------------------------------
	-- booted helpers
	------------------------------------------------------------------------------------------------
	local userSeq = 0
	local function join(prefix)
		userSeq = userSeq + 1
		local p = Mock.AddPlayer(prefix .. userSeq, 975000 + userSeq)
		advance(1.0)
		return p
	end

	local function leave(p)
		if p and p.Parent then
			Mock.RemovePlayer(p)
		end
		advance(0.6)
	end

	local function TSv()
		return mod("TutorialService")
	end

	local function state(p)
		return TSv().GetState(p)
	end

	local function stepId(p)
		local st = state(p)
		return st and not st.Done and st.Id or (st and st.Done and "done!") or nil
	end

	local function resume(p, step, done)
		mod("DataService").SetTutorial(p, { Step = step, Done = done ~= false, Gifted = true })
		TSv().Reload(p)
		advance(0.4)
	end

	local function near(a, b, d)
		return typeof(a) == "Vector3" and typeof(b) == "Vector3" and (a - b).Magnitude <= (d or 1)
	end

	local function tutorialErrors(from)
		local n = 0
		for i = from + 1, #Mock.Errors do
			if tostring(Mock.Errors[i].msg):find("Tutorial", 1, true) then
				n = n + 1
			end
		end
		return n
	end

	local function spots()
		return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
	end

	-- walks to a free gate and presses E on its ClaimPrompt; returns the plot index
	local function claimFree(p)
		local SS = mod("SpotService")
		local suggestion = SS.SuggestSpot(p)
		local index = suggestion and suggestion.Index
		if not index then
			for i = 1, #spots() do
				if SS.GetOwner(i) == nil then
					index = i
					break
				end
			end
		end
		if not index then
			return nil
		end
		local gate = SS.GateCFrame(spots()[index])
		if gate and p.Character then
			Mock.Teleport(p, gate * CFrame.new(0, 3, -5))
		end
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" and (d:GetAttribute("SpotIndex") == index
				or (spots()[index].Folder and d:IsDescendantOf(spots()[index].Folder))) then
				Mock.Trigger(d, p)
				break
			end
		end
		advance(0.8)
		return SS.GetSpot(p) and index or nil
	end

	local function padPosition(HB, TC, info, id)
		local model = HB and HB.GetPad and HB.GetPad(info, id)
		if model then
			local ok, cf = pcall(function()
				return model:GetPivot()
			end)
			if ok and cf then
				return cf.Position
			end
		end
		local def = TC.Get(id)
		if def and def.Slot and def.Slot.Pad and info.PlotCFrame then
			return (info.PlotCFrame * def.Slot.Pad).Position
		end
		return nil
	end

	------------------------------------------------------------------------------------------------
	-- p5ui_portal_obby
	------------------------------------------------------------------------------------------------
	S.p5ui_portal_obby = guarded("p5ui_portal_obby", function()
		if not K.needBoot() then
			return
		end
		local errors0 = #Mock.Errors
		local obby = K.W.lobbyInfo and K.W.lobbyInfo.Portals and K.W.lobbyInfo.Portals.Obby
		if not T.check(obby ~= nil and TSv() ~= nil, "p5ui portal: lobby.Portals.Obby and TutorialService are there") then
			return
		end
		local p = join("ObbyTut")
		resume(p, 7, false)
		T.eq(stepId(p), "portal", "p5ui portal: (setup) a player on chapter 1's 'portal'")
		local st = state(p)
		T.check(st and st.Target and st.Target.Kind == "Portal" and st.Target.Id == "Obby" and near(st.Target.Position, obby.Center),
			"p5ui portal: the target is the Obby portal (Kind Portal, Id Obby, lobby.Portals.Obby.Center)")
		K.enterPortal(p)
		waitFor(function()
			return stepId(p) ~= "portal"
		end, 30)
		T.eq(stepId(p), "finish", "p5ui portal: standing on the Obby pad starts a match and completes 'portal'")
		K.endAllMatches()
		advance(1)
		leave(p)
		T.eq(tutorialErrors(errors0), 0, "p5ui portal: no script errors from TutorialService")
	end)

	------------------------------------------------------------------------------------------------
	-- p5ui_tutorial_ch2
	------------------------------------------------------------------------------------------------
	S.p5ui_tutorial_ch2 = guarded("p5ui_tutorial_ch2", function()
		if not K.needBoot() then
			return
		end
		local DataS = mod("DataService")
		local SS = mod("SpotService")
		local Ty = requireAt("server/Services/TycoonService")
		local Care = requireAt("server/Services/PetCareService")
		local HB = requireAt("server/Services/HomeBuilder")
		local TC = requireAt("shared/TycoonCatalog")
		local PK = requireAt("shared/PetKeys")
		local Steps = requireAt("shared/TutorialSteps")
		if not T.check(TSv() and DataS and SS and Ty and Ty.Drops and Care and HB and TC and PK and Steps,
			"p5ui ch2: TutorialService, TycoonService.Drops, PetCareService, HomeBuilder and the catalogs are loaded") then
			return
		end
		local errors0 = #Mock.Errors
		local p = join("BerryTut")
		resume(p, 10)
		T.eq(stepId(p), "claim", "p5ui ch2: a finished chapter 1 resumes at 'claim'")
		local index = claimFree(p)
		waitFor(function()
			return stepId(p) ~= "claim"
		end, 3)
		T.check(index ~= nil and stepId(p) == "garden", "p5ui ch2: E at a free gate completes 'claim'")
		local info = SS.GetSpot(p)
		PK.Add(DataS.GetProfile(p), "pebble_pup", 1)
		DataS.MarkDirty(p)
		advance(1.2)
		local st = state(p)
		local gardenPad = info and padPosition(HB, TC, info, "Garden")
		T.check(st and st.Target and near(st.Target.Position, gardenPad), "p5ui ch2: 'garden' points at the free Pet Garden pad")
		Ty.Buy(p, "Garden")
		advance(0.6)
		st = state(p)
		local station = HB.GetStation(info, "Garden")
		local bed = station and station:FindFirstChild("Spot1", true)
		local bedPos = bed and (bed:IsA("Attachment") and bed.WorldPosition or bed.Position) or nil
		T.check(st and st.Target and bedPos and near(st.Target.Position, bedPos), "p5ui ch2: ...then at the first empty bed (Spot1)", st and tostring(st.Hint))
		Ty.GardenSet(p, 1, "pebble_pup")
		advance(0.6)
		T.eq(stepId(p), "coins", "p5ui ch2: a pet on a bed completes 'garden'")

		-- coins: the Garden until the first poop, then the biggest drop
		st = state(p)
		T.check(st and st.Target and st.Target.Label == "Pet Garden" and tostring(st.Hint):find("roaming", 1, true) ~= nil,
			"p5ui ch2: before the first poop the arrow points at the Pet Garden ('roaming')", st and tostring(st.Hint))
		local function biggest()
			local best = nil
			for _, d in ipairs(Ty.Drops(p) or {}) do
				if (tonumber(d.Value) or 0) >= 1 and (d.Poops == nil or d.Poops >= 1) and (not best or d.Value > best.Value) then
					best = d
				end
			end
			return best
		end
		waitFor(function()
			return biggest() ~= nil
		end, 45)
		advance(0.6)
		local drop = biggest()
		st = state(p)
		T.check(drop ~= nil and st and st.Id == "coins" and st.Target and near(st.Target.Position, drop.Position)
			and st.Target.Label == "Cloud Cash" and st.Hint == "Walk over your Cloud Cash",
			"p5ui ch2: then at the biggest Cloud Cash drop (TycoonService.Drops)", st and tostring(st.Hint))
		if drop then
			Mock.Teleport(p, CFrame.new(drop.Position + Vector3.new(0, 3, 0)))
		end
		waitFor(function()
			return stepId(p) ~= "coins"
		end, 3)
		T.eq(stepId(p), "machine", "p5ui ch2: scooping the Cloud Cash completes 'coins'")
		Mock.Teleport(p, (SS.GateCFrame(info) or CFrame.new()) * CFrame.new(0, 3, -5))
		DataS.AddCash(p, 100000)
		advance(0.8)

		-- machine: the Berry Farm pad first, then the Food Machine pad
		st = state(p)
		local farmPad = padPosition(HB, TC, info, "Press1")
		T.check(st and st.Target and near(st.Target.Position, farmPad, 0.5) and tostring(st.Target.Label):find("Berry Farm", 1, true) ~= nil,
			"p5ui ch2: 'machine' points at the Berry Farm pad first", st and st.Target and tostring(st.Target.Label))
		Ty.Buy(p, "Press1")
		advance(0.6)
		st = state(p)
		local kitchenPad = padPosition(HB, TC, info, "Kitchen")
		T.check(stepId(p) == "machine" and st and st.Target and near(st.Target.Position, kitchenPad, 0.5),
			"p5ui ch2: ...then at the Food Machine pad", st and st.Target and tostring(st.Target.Label))
		local berries0 = DataS.GetBerries(p) or 0
		Ty.Buy(p, "Kitchen")
		advance(0.8)
		T.eq(stepId(p), "feed", "p5ui ch2: building the Food Machine completes 'machine'")

		-- feed: the berries are topped up to 500 (once), a real feed ends chapter 2
		local berries1 = DataS.GetBerries(p) or 0
		T.check(berries1 >= 500 and (berries0 >= 500 or berries1 == 500), "p5ui ch2: entering 'feed' tops the berries up to 500",
			tostring(berries0) .. " -> " .. tostring(berries1))
		st = state(p)
		local kitchen = HB.GetStation(info, "Kitchen")
		local hopper = kitchen and kitchen:FindFirstChild("Hopper", true)
		T.check(st and st.Target and hopper and near(st.Target.Position, hopper.Position, 0.5), "p5ui ch2: 'feed' points at the Food Machine's Hopper")
		TSv().Reload(p)
		advance(0.4)
		T.eq(DataS.GetBerries(p), berries1, "p5ui ch2: re-entering 'feed' with berries adds none")
		local cash0 = DataS.GetCash(p)
		local okFeed, fed = Care.Feed(p, "pebble_pup")
		advance(0.6)
		T.check(okFeed == true, "p5ui ch2: the feed works with the topped-up berries", tostring(fed))
		st = state(p)
		T.check(st and st.Id == "arena" and st.Step == 15, "p5ui ch2: the feed ends chapter 2 (on to 'arena', step 15)")
		T.eq(DataS.GetCash(p), cash0 + 1000, "p5ui ch2: ...and pays the home chapter's $1,000 once")
		TSv().HandleEvent(p, "Next")
		advance(0.4)
		T.eq(DataS.GetCash(p), cash0 + 1000, "p5ui ch2: nothing is paid twice")
		leave(p)

		-- resume from every index 1-21 (a player without a home, pets or records)
		local r = join("Resumer")
		local landed, want = {}, {}
		for i = 1, 21 do
			resume(r, i, i > 9)
			local now = state(r)
			landed[#landed + 1] = i .. ">" .. tostring(now and not now.Done and now.Step or "done")
			want[#want + 1] = i .. ">" .. tostring(i == 8 and 9 or i)
		end
		T.eq(table.concat(landed, " "), table.concat(want, " "),
			"p5ui ch2: a saved Step 1-21 resumes on that step (8 'finish' passes at once outside a match)")
		leave(r)
		T.eq(tutorialErrors(errors0), 0, "p5ui ch2: no script errors from TutorialService")
	end)

	------------------------------------------------------------------------------------------------
	-- p5dgn_tutorial
	------------------------------------------------------------------------------------------------
	S.p5dgn_tutorial = guarded("p5dgn_tutorial", function()
		if not K.needBoot() then
			return
		end
		local DataS = mod("DataService")
		local DB = requireAt("server/Services/DungeonBuilder")
		local DGS = requireAt("server/Services/DungeonService")
		local BS = requireAt("server/Services/BattleService")
		local PK = requireAt("shared/PetKeys")
		local dInfo = DB and DB.GetInfo and DB.GetInfo() or nil
		local pad = type(dInfo) == "table" and dInfo.Pad or nil
		if not T.check(TSv() and DataS and DGS and DGS.FloorCleared and BS and PK and pad and pad:IsA("BasePart"),
			"p5dgn tutorial: TutorialService, DungeonService.FloorCleared and the Dungeon gate's pad (DungeonBuilder.GetInfo().Pad)") then
			return
		end
		local errors0 = #Mock.Errors
		local p = join("DungeonKid")
		local prof = DataS.GetProfile(p)
		PK.Add(prof, "pebble_pup", 1)
		PK.Add(prof, "honey_bunny", 1)
		DataS.MarkDirty(p)
		DataS.SetTeam(p, 1, {})
		Mock.Teleport(p, CFrame.new(config().Lobby.Origin + Vector3.new(12, 4, 12)))
		resume(p, 16)
		T.eq(stepId(p), "team", "p5dgn tutorial: (setup) a player on 'team'")
		DataS.SetTeam(p, 1, { "pebble_pup", "honey_bunny" })
		advance(0.6)
		T.eq(stepId(p), "dungeon", "p5dgn tutorial: a team completes 'team' -> 'dungeon'")
		local st = state(p)
		T.check(st and st.Chapter == 3 and st.Step == 17 and st.Target and st.Target.Kind == "Spot" and near(st.Target.Position, pad.Position)
			and st.Target.Label == "Dungeon portal", "p5dgn tutorial: the arrow points at the Dungeon gate's pad (DungeonInfo.Pad)")
		p:SetAttribute("InBattle", "test-battle")
		advance(1.2)
		st = state(p)
		T.check(st and st.Id == "dungeon" and st.Target == nil, "p5dgn tutorial: no arrow while the player fights")
		p:SetAttribute("InBattle", nil)
		advance(1.2)

		-- standing on the pad opens the Dungeon window on floor 1, once
		local function openPanels(from)
			local out = {}
			for i = from + 1, #Mock.RemoteLog do
				local e = Mock.RemoteLog[i]
				if e.remote == "OpenPanel" and e.kind == "client" and e.userId == p.UserId and e.args[1] == "Dungeon" then
					out[#out + 1] = e
				end
			end
			return out
		end
		local mark = #Mock.RemoteLog
		Mock.Teleport(p, pad.CFrame * CFrame.new(0, 3, 0))
		advance(1.5)
		local opened = openPanels(mark)
		T.check(#opened == 1 and type(opened[1].args[2]) == "table" and opened[1].args[2].Floor == 1,
			"p5dgn tutorial: standing on the pad sends OpenPanel('Dungeon', { Floor = 1 })", tostring(#opened))
		Mock.Teleport(p, CFrame.new(config().Lobby.Origin + Vector3.new(12, 4, 12)))
		advance(1.2)
		Mock.Teleport(p, pad.CFrame * CFrame.new(0, 3, 0))
		advance(1.5)
		T.eq(#openPanels(mark), 1, "p5dgn tutorial: ...only once")
		T.eq(stepId(p), "dungeon", "p5dgn tutorial: the window alone completes nothing")
		BS.BattleEnded:Fire("p5-old-trial", { Mode = "Trial", Winners = { p.UserId }, Losers = {}, Level = 1 })
		advance(0.6)
		T.eq(stepId(p), "dungeon", "p5dgn tutorial: an old Mode 'Trial' BattleEnded completes nothing")
		DGS.FloorCleared:Fire(p, 1)
		advance(0.6)
		T.eq(stepId(p), "raid", "p5dgn tutorial: floor 1 cleared (DungeonService.FloorCleared) marks DungeonWon -> 'raid'")
		leave(p)

		-- the saved Dungeon record and a legacy Trial 1 skip the step
		local q = join("DungeonVet")
		DataS.MutateDungeon(q, function(d)
			d.Cleared = d.Cleared or {}
			d.Cleared[1] = true
			if (d.Best or 0) < 1 then
				d.Best = 1
			end
		end)
		advance(0.3)
		resume(q, 17)
		-- (past 'dungeon': 'raid', or further when a raid of another scenario happens to run)
		T.check(state(q) and (state(q).Done or state(q).Step >= 18), "p5dgn tutorial: a saved Dungeon.Best >= 1 passes 'dungeon' at once", tostring(stepId(q)))
		leave(q)
		local v = join("TrialVet")
		DataS.MutateBattle(v, function(b)
			b.TrialCleared = b.TrialCleared or {}
			b.TrialCleared[1] = true
		end)
		advance(0.3)
		resume(v, 17)
		T.check(state(v) and (state(v).Done or state(v).Step >= 18), "p5dgn tutorial: a Phase 4 veteran with TrialCleared[1] skips 'dungeon'", tostring(stepId(v)))
		leave(v)
		T.eq(tutorialErrors(errors0), 0, "p5dgn tutorial: no script errors from TutorialService")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half (none: the panel and the arrows are covered by smoke_client / smoke_p4_ui / smoke_p5_menu)
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	return {}
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
