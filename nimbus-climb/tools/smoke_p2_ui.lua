-- smoke_p2_ui.lua: Phase 2 UI (ARCHITECTURE_V3.md "Phase 2 build contract", UI): the Home tile + Home window, the Pets
-- panel actions (Feed picker, Place in Garden, Train in Gym, tier / hybrid badges, levels, scaled stats), the Shop's
-- Gems tab, the Index Fusions tab (client/Controllers/MenuController.lua, IndexController.lua), the appended home
-- chapter of the tutorial (shared/TutorialSteps.lua, server/Services/TutorialService.lua) and the NPC tips
-- (shared/NpcDialog.lua). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half:
-- (Phase 5, owner tutorial W4 for the chapter-2 ids / texts and the p2ui_tutorial flow: roaming pets poop Cloud Cash,
-- the arrow finds the biggest drop (TycoonService.Drops), the Berry Farm pad comes before the Food Machine pad, the
-- feed step tops the berries up; Mayor Panda / Granny Owl speak of Cloud Cash, the Food Bowl and the Berry Basket)
--   p2ui_content        (server, content) the home chapter follows the nine basics (Phase 4 ids claim, garden, coins,
--                       machine, feed; chapters, ChapterEnd, known CompleteOn incl. the Phase 4 ones, Station of every
--                       "Built" step, home targets, no Collector / Kitchen / cooking left); NPC tips: every NPC has 3-5
--                       lines that fit the dialog (<= 125 bytes, no rich-text characters), Granny Owl explains the Food
--                       Machine (FeedShare[1]) and EVOLVE, Coach Corgi the Training Place and the Champion Ring, Mayor
--                       Panda the Pet Garden's rainbow coins and Prestige, Fusion and Gems with the real numbers of
--                       TycoonCatalog / Config.Gems; nobody talks about the Collector / Kitchen / Gym
--   p2ui_tutorial       (server, booted) Phase 4 chapter 2 (contract section 9): a player who finished the basics
--                       resumes at "claim": the arrow points at a free gate, E claims (-> "garden": the arrow points at
--                       the Shop without a pet, then at the free Pet Garden pad, then at a place in the built Garden), a
--                       pet put in the Garden
--                       (-> "coins": the arrow points at the coin pile its meals make), walking over the coins
--                       (-> "machine": the arrow walks the pads on the way to the Food Machine, each one buyable),
--                       the Food Machine (-> "feed": the arrow points at the machine), a feed ends the chapter: Done
--                       or on to chapter 3, the Cash reward paid once, kept after a rejoin; a skipped tutorial never
--                       resumes; a new player's "home" step completes by claiming a plot; events of another step are
--                       refused
--   client_p2ui         (client) the Home tile (MenuButton_Spot, "Home"): GoToSpot + a side hint without a home, the
--                       Home window with one: every station row, live Collector / income numbers from the plot folder,
--                       Upgrade / Collect / Go home / a confirmed Prestige send HomeAction, locked stations show why;
--                       Pets: per-copy slots with tier / hybrid chips and levels, the Feed picker (Feed / Cook ->
--                       PetCare), Place in Garden / Leave Garden (HomeAction GardenSet), Train in Gym (PetCare GymSet);
--                       Shop Gems tab: the Secret roulette with its odds, a gem spin sends BuyRoulette(id, "Gems"), the
--                       paid-random-items policy hides gem roulettes; the Index Fusions tab lists the fused copies and
--                       is not a reward group; every text of these windows is >= 18 design px; no script errors
--   client_p2ui_mobile  (phone 390x844) the same windows keep every text >= 14 px on screen
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, max, min = math.abs, math.floor, math.max, math.min

local function countKeys(map)
	local n = 0
	for _ in pairs(type(map) == "table" and map or {}) do
		n = n + 1
	end
	return n
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
	-- p2ui_content
	------------------------------------------------------------------------------------------------
	S.p2ui_content = guarded("p2ui_content", function()
		local Steps = requireAt("shared/TutorialSteps")
		local TC = requireAt("shared/TycoonCatalog")
		local ND = requireAt("shared/NpcDialog")
		local Config = config()
		if not T.check(type(Steps) == "table" and type(Steps.Steps) == "table", "p2ui: shared/TutorialSteps loads") then
			return
		end
		local ids = {}
		for i, step in ipairs(Steps.Steps) do
			ids[i] = step.Id
		end
		-- (Phase 3 appends chapter 3, the pet battles, and Phase 4 chapter 4 after these: smoke_p3_ui / smoke_p4_ui check them)
		-- Phase 4 rewrote chapter 2 IN PLACE (contract section 9: saved progress is the step index, so it keeps 5 steps)
		T.eq(table.concat(ids, ",", 1, math.min(#ids, 14)), "welcome,home,shop,spin,equip,index,portal,finish,done,claim,garden,coins,machine,feed",
			"p2ui: the home chapter (claim, garden, coins, machine, feed) follows the nine basics")
		local start = Steps.ChapterStart and Steps.ChapterStart[2]
		T.eq(start, 10, "p2ui: chapter 2 starts at step 10 (a finished Phase 1 tutorial stored Step = 10)")
		local known = { Next = true, NearSpot = true, ShopOpened = true, Rolled = true, Equipped = true, IndexOpened = true,
			MatchStarted = true, MatchEnded = true, Claimed = true, Built = true, Collected = true, Fed = true,
			ArenaReached = true, TeamSet = true, DungeonWon = true, RaidSeen = true, -- (Phase 3, chapter 3; Phase 5 DungeonWon)
			GardenPlaced = true, CoinsScooped = true, TrainingStarted = true, RingWon = true, PortalUsed = true } -- (Phase 4)
		local bad, ends = {}, {}
		for i, step in ipairs(Steps.Steps) do
			if not known[step.CompleteOn] then
				bad[#bad + 1] = step.Id .. ":" .. tostring(step.CompleteOn)
			end
			if step.CompleteOn == "Built" and not (TC and TC.Get(step.Station)) then
				bad[#bad + 1] = step.Id .. " builds unknown station " .. tostring(step.Station)
			end
			if (step.Chapter or 1) == 2 and i < start then
				bad[#bad + 1] = step.Id .. " is a chapter 2 step inside chapter 1"
			end
			if step.ChapterEnd then
				ends[#ends + 1] = step.Id
			end
			if type(step.Text) ~= "string" or #step.Text < 20 or #step.Text > 200 then
				bad[#bad + 1] = step.Id .. " text length " .. tostring(step.Text and #step.Text)
			end
		end
		T.check(#bad == 0, "p2ui: every step has a known CompleteOn, a real station and a short text", table.concat(bad, "; "))
		T.eq(table.concat(ends, ",", 1, math.min(#ends, 2)), "done,feed", "p2ui: each chapter ends on one ChapterEnd step (done, feed)")
		local byId = {}
		for _, step in ipairs(Steps.Steps) do
			byId[step.Id] = step
		end
		T.check(byId.home and byId.home.CompleteOn == "Claimed" and byId.home.Target and byId.home.Target.Gate == true,
			"p2ui: the basics' 'home' step now leads to a free gate and completes on a claim (E at the gate)")
		local function target(id)
			return byId[id] and type(byId[id].Target) == "table" and byId[id].Target or {}
		end
		T.check(byId.claim and byId.claim.CompleteOn == "Claimed" and target("claim").Gate == true,
			"p2ui: 'claim' points at a free gate and completes on a claim")
		T.check(byId.garden and byId.garden.CompleteOn == "GardenPlaced" and target("garden").GardenSpot == true
			and (target("garden").Station == "Garden" or target("garden").Pad == "Garden"),
			"p2ui: 'garden' (the free Pet Garden, then a garden spot) completes on GardenPlaced")
		T.check(byId.coins and byId.coins.CompleteOn == "CoinsScooped" and target("coins").Coins == true,
			"p2ui: 'coins' points at the coins and completes on CoinsScooped")
		T.check(byId.machine and byId.machine.CompleteOn == "Built" and byId.machine.Station == "Kitchen" and target("machine").Path == true,
			"p2ui: 'machine' follows the pad path to the Food Machine (Built, Station Kitchen)")
		T.check(byId.feed and byId.feed.CompleteOn == "Fed" and target("feed").Food == true and byId.feed.ChapterEnd == true,
			"p2ui: 'feed' (the Food Machine) completes on Fed and ends the chapter")
		local text = tostring(byId.feed and byId.feed.Text or "") .. " " .. tostring(byId.garden and byId.garden.Text or "")
		T.check(text:find("Food Machine", 1, true) and text:find("Garden", 1, true), "p2ui: the chapter talks about the Pet Garden and the Food Machine")
		local all2 = ""
		for i = start, math.min(#Steps.Steps, start + 4) do
			all2 = all2 .. " " .. tostring(Steps.Steps[i].Text)
		end
		T.check(not all2:find("Collector", 1, true) and not all2:find("Kitchen", 1, true) and not all2:find("Cook", 1, true),
			"p2ui: chapter 2 no longer mentions the Collector, the Kitchen or cooking")

		-- NPC tips
		if not T.check(type(ND) == "table" and type(ND.Npcs) == "table" and #ND.Npcs == 6, "p2ui: shared/NpcDialog has the six NPCs") then
			return
		end
		local long, lineCounts = {}, {}
		local all = {}
		for _, npc in ipairs(ND.Npcs) do
			local n = #(npc.Lines or {})
			if n < 3 or n > 5 then
				lineCounts[#lineCounts + 1] = npc.Id .. "=" .. n
			end
			for i, line in ipairs(npc.Lines or {}) do
				if #line > 125 or line:find("[<>&]") then
					long[#long + 1] = npc.Id .. "#" .. i .. " (" .. #line .. ")"
				end
				all[npc.Id] = (all[npc.Id] or "") .. " " .. line
			end
		end
		T.check(#lineCounts == 0, "p2ui: every NPC has 3-5 lines", table.concat(lineCounts, ", "))
		T.check(#long == 0, "p2ui: every NPC line fits the dialog well (<= 125 bytes, no rich-text characters)", table.concat(long, ", "))
		local function says(id, ...)
			local text = all[id] or ""
			for _, needle in ipairs({ ... }) do
				if not text:find(needle, 1, true) then
					return false, needle
				end
			end
			return true
		end
		-- Phase 4 tips (contract section 9): numbers read from the catalogs
		T.check(says("granny_owl", "Berry Basket", "Food Machine", "Feed", "EVOLVE"),
			"p2ui: Granny Owl explains the Berry Basket, the Food Machine, feeding and EVOLVE")
		T.check(says("coach_corgi", "Training Place", "Champion Ring"), "p2ui: Coach Corgi explains the Training Place and the Champion Ring")
		local P = TC and TC.Prestige or {}
		T.check(says("mayor_panda", "free gate", "Food Bowl", "Cloud Cash", "Berry Farm", "Prestige", "Home Level " .. tostring(P.HomeLevel or 40),
			tostring(P.GemReward or 100) .. " Gems"),
			"p2ui: Mayor Panda explains claiming a home, the Food Bowl's Cloud Cash, the Berry Farm and Prestige (Home Level " .. tostring(P.HomeLevel) .. ", the Gems reward)")
		local npcAll = ""
		for _, t in pairs(all) do
			npcAll = npcAll .. t
		end
		T.check(not npcAll:find("Collector", 1, true) and not npcAll:find("Kitchen", 1, true) and not npcAll:find("Gym", 1, true),
			"p2ui: no NPC talks about the Collector, the Kitchen or the Gym any more")
		local Util = requireAt("shared/Util")
		local secret = Config.Gems and Config.Gems.SecretRoulette
		local secretPrice = (secret and Util and Util.Commas) and Util.Commas(secret.GemPrice) or "1,500"
		T.check(says("professor_axolotl", "Fusion Machine", "Golden", "Rainbow", "hybrid", "Storm Altar", secretPrice .. " Gems"),
			"p2ui: Professor Axolotl explains the Fusion Machine and the Secret roulette's Gem price")
		T.check(says("granny_owl", "Gems"), "p2ui: Granny Owl mentions spinning roulettes with Gems")
	end)

	------------------------------------------------------------------------------------------------
	-- p2ui_tutorial
	------------------------------------------------------------------------------------------------
	local userSeq = 0
	local function join(prefix)
		userSeq = userSeq + 1
		local p = Mock.AddPlayer(prefix .. userSeq, 967000 + userSeq)
		advance(1.0)
		return p
	end

	local function leave(p)
		if p and p.Parent then
			Mock.RemovePlayer(p)
		end
		advance(0.6)
	end

	local function spots()
		return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
	end

	local function claimPromptOf(index)
		local info = spots()[index]
		if info and info.Folder then
			for _, d in ipairs(info.Folder:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
					return d
				end
			end
		end
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" and d:GetAttribute("SpotIndex") == index then
				return d
			end
		end
		return nil
	end

	-- walks to the gate (just outside it) and presses E on its ClaimPrompt
	local function claim(p, index)
		local SS = mod("SpotService")
		local gate = SS.GateCFrame(spots()[index])
		if gate and p.Character then
			Mock.Teleport(p, gate * CFrame.new(0, 3, -5))
		end
		local prompt = claimPromptOf(index)
		if prompt then
			Mock.Trigger(prompt, p)
		end
		advance(0.6)
		return prompt ~= nil
	end

	-- the world position of a pad on a plot (HomeBuilder's model, else the catalog slot)
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

	S.p2ui_tutorial = guarded("p2ui_tutorial", function()
		if not K.needBoot() then
			return
		end
		local Config = config()
		local TSv = mod("TutorialService")
		local DataS = mod("DataService")
		local SS = mod("SpotService")
		local Ty = requireAt("server/Services/TycoonService")
		local Care = requireAt("server/Services/PetCareService")
		local HB = requireAt("server/Services/HomeBuilder")
		local Steps = requireAt("shared/TutorialSteps")
		local TC = requireAt("shared/TycoonCatalog")
		local PK = requireAt("shared/PetKeys")
		if not T.check(TSv and DataS and SS and Ty and Care and Steps and TC and PK and type(TSv.Reload) == "function",
			"p2ui tutorial: TutorialService (Reload), TycoonService, PetCareService, TycoonCatalog and PetKeys are loaded") then
			return
		end
		local errors0 = #Mock.Errors
		local start = Steps.ChapterStart[2]
		local function state(p)
			return TSv.GetState(p)
		end
		local function stepId(p)
			local st = state(p)
			return st and not st.Done and st.Id or (st and st.Done and "done!") or nil
		end

		-- a player who finished the basics resumes at the home chapter
		local p = join("HomeTut")
		T.check(DataS.SetTutorial(p, { Step = start, Done = true, Gifted = true }) == true, "p2ui tutorial: the finished-basics progress is stored")
		TSv.Reload(p)
		advance(0.3)
		T.eq(stepId(p), "claim", "p2ui tutorial: a finished Phase 1 tutorial (Step 10, Done) resumes at 'claim'")
		local st = state(p)
		T.check(st and st.Chapter == 2 and st.Step == start and st.Total == #Steps.Steps, "p2ui tutorial: ...as chapter 2, step " .. start .. "/" .. #Steps.Steps)
		local target = st and st.Target
		local suggestion = SS.SuggestSpot(p)
		local gate = suggestion and SS.GateCFrame(suggestion)
		T.check(type(target) == "table" and target.Kind == "Spot" and typeof(target.Position) == "Vector3" and gate ~= nil
			and (target.Position - gate.Position).Magnitude < 1 and type(target.SpotIndex) == "number",
			"p2ui tutorial: the 'claim' arrow points at the gate of a free plot (Kind Spot, Position, SpotIndex)")
		local index = target and target.SpotIndex
		if not T.check(index ~= nil and SS.GetOwner(index) == nil, "p2ui tutorial: the suggested plot is free") then
			leave(p)
			return
		end
		claim(p, index)
		waitFor(function()
			return stepId(p) ~= "claim"
		end, 3)
		T.eq(stepId(p), "garden", "p2ui tutorial: E at the gate completes 'claim'")
		local info = SS.GetSpot(p)
		st = state(p)
		T.check(st and st.Target and st.Target.Kind == "Shop", "p2ui tutorial: without a pet the 'garden' arrow points at the Shop first",
			st and st.Target and tostring(st.Target.Kind) .. " / " .. tostring(st.Hint))
		local prof = DataS.GetProfile(p)
		PK.Add(prof, "pebble_pup", 1)
		DataS.MarkDirty(p)
		advance(1.2)
		st = state(p)
		local gardenPad = info and padPosition(HB, TC, info, "Garden")
		T.check(st and st.Target and st.Target.Kind == "Spot" and st.Target.SpotIndex == index and typeof(st.Target.Position) == "Vector3"
			and gardenPad ~= nil and (st.Target.Position - gardenPad).Magnitude < 1,
			"p2ui tutorial: the 'garden' arrow points at the free Pet Garden pad of the claimed plot")
		local okBuy = Ty.Buy(p, "Garden")
		advance(0.6)
		T.check(okBuy == true, "p2ui tutorial: the Pet Garden is built (free)")
		T.eq(stepId(p), "garden", "p2ui tutorial: building the Garden alone does not complete 'garden'")
		st = state(p)
		local station = HB.GetStation and HB.GetStation(info, "Garden")
		local okPivot, gardenCf = pcall(function()
			return station:GetPivot()
		end)
		T.check(st and st.Target and typeof(st.Target.Position) == "Vector3" and okPivot and gardenCf
			and (st.Target.Position - gardenCf.Position).Magnitude < 16 and (st.Target.Position - gardenPad).Magnitude > 0.5,
			"p2ui tutorial: ...then at a place in the built Garden", st and tostring(st.Hint))
		local okPlace = Ty.GardenSet(p, 1, "pebble_pup")
		advance(0.6)
		T.check(okPlace == true, "p2ui tutorial: a pet is put in garden place 1")
		T.eq(stepId(p), "coins", "p2ui tutorial: a pet in the Garden completes 'garden'")
		-- coins (Phase 5): the pet roams, eats at the Food Bowl and poops Cloud Cash (the first poop lands 23-35 s after
		-- the placement); walking over it scoops it
		st = state(p)
		T.check(st and st.Id == "coins" and st.Target and typeof(st.Target.Position) == "Vector3",
			"p2ui tutorial: before the first poop the 'coins' arrow points at the Pet Garden", st and tostring(st.Hint))
		local drop = nil
		waitFor(function()
			local drops = Ty.Drops and Ty.Drops(p) or {}
			for _, d in ipairs(drops) do
				if (tonumber(d.Value) or 0) >= 1 and (d.Poops == nil or d.Poops >= 1) and (not drop or d.Value > drop.Value) then
					drop = d
				end
			end
			return drop ~= nil
		end, 45)
		T.check(drop ~= nil and typeof(drop.Position) == "Vector3", "p2ui tutorial: the garden pet pooped Cloud Cash (TycoonService.Drops)")
		advance(0.6)
		st = state(p)
		T.check(st and st.Id == "coins" and st.Target and typeof(st.Target.Position) == "Vector3" and drop and (st.Target.Position - drop.Position).Magnitude < 1,
			"p2ui tutorial: the 'coins' arrow points at the biggest drop", st and tostring(st.Hint))
		if drop then
			Mock.Teleport(p, CFrame.new(drop.Position + Vector3.new(0, 3, 0)))
		end
		waitFor(function()
			return stepId(p) ~= "coins"
		end, 3)
		T.eq(stepId(p), "machine", "p2ui tutorial: scooping the coins completes 'coins'")
		Mock.Teleport(p, (SS.GateCFrame(info) or CFrame.new()) * CFrame.new(0, 3, -5))
		advance(0.5)

		-- machine: the arrow names the next pad on the way, every one of them buyable
		DataS.AddCash(p, 5000000)
		advance(0.6)
		local path, lost = {}, nil
		for _ = 1, 40 do
			if stepId(p) ~= "machine" then
				break
			end
			st = state(p)
			local padId = nil
			for _, pad in ipairs(TC.AvailablePads(DataS.GetHome(p))) do
				local pos = padPosition(HB, TC, info, pad.StationId)
				if not pad.Locked and pos and st.Target and typeof(st.Target.Position) == "Vector3" and (pos - st.Target.Position).Magnitude < 0.5 then
					padId = pad.StationId
				end
			end
			if not padId then
				lost = tostring(st and st.Hint)
				break
			end
			path[#path + 1] = padId
			Ty.Buy(p, padId)
			advance(0.5)
		end
		T.check(lost == nil and #path >= 1 and path[#path] == "Kitchen", "p2ui tutorial: following the 'machine' arrow from pad to pad builds the Food Machine",
			table.concat(path, " > ") .. (lost and (" (lost at: " .. lost .. ")") or ""))
		T.eq(stepId(p), "feed", "p2ui tutorial: building the Food Machine completes 'machine'")
		st = state(p)
		local machinePos = nil
		local kitchen = HB.GetStation and HB.GetStation(info, "Kitchen")
		if kitchen then
			local okK, kcf = pcall(function()
				return kitchen:GetPivot()
			end)
			machinePos = okK and kcf and kcf.Position or nil
		end
		T.check(st and st.Target and st.Target.Kind == "Spot" and typeof(st.Target.Position) == "Vector3" and machinePos
			and (st.Target.Position - machinePos).Magnitude < 12,
			"p2ui tutorial: 'feed' points at the Food Machine", st and tostring(st.Hint))
		T.check((DataS.GetBerries(p) or 0) >= 40, "p2ui tutorial: entering 'feed' tops the berries up for the first feed", tostring(DataS.GetBerries(p)))
		local cash0 = DataS.GetCash(p)
		local okFeed, fed = Care.Feed(p, "pebble_pup", nil)
		advance(0.6)
		T.check(okFeed == true, "p2ui tutorial: the pet is fed at the Food Machine", tostring(fed))
		local paid = (type(fed) == "table" and tonumber(fed.Paid)) or 0
		st = state(p)
		-- (Phase 3: the pet-battle chapter follows the home chapter; without it the tutorial is Done here)
		local chapter3 = Steps.ChapterStart and Steps.ChapterStart[3]
		T.check(st and ((st.Done == true and st.Completed == true) or (chapter3 ~= nil and st.Chapter == 3 and st.Step == chapter3)),
			"p2ui tutorial: feeding a pet ends the home chapter (Done, or on to the battle chapter)")
		T.eq(DataS.GetCash(p), cash0 - paid + 1000, "p2ui tutorial: ...and pays the home chapter's Cash reward once")
		T.eq(DataS.GetTutorial(p).Step, chapter3 or (#Steps.Steps + 1), "p2ui tutorial: the stored Step is one past the home chapter (a later chapter resumes there)")
		TSv.HandleEvent(p, "Next")
		TSv.HandleEvent(p, "Skip")
		T.eq(DataS.GetCash(p), cash0 - paid + 1000, "p2ui tutorial: nothing is paid twice")
		local userId, name = p.UserId, p.Name
		leave(p)
		advance(1.5)
		p = Mock.AddPlayer(name, userId)
		advance(1.2)
		T.check(state(p) and (state(p).Done == true or (state(p).Chapter or 0) >= 3), "p2ui tutorial: the finished chapter stays finished after a rejoin")
		leave(p)

		-- a skipped tutorial never resumes
		local q = join("Skipper")
		DataS.SetTutorial(q, { Step = 1000, Done = true, Gifted = false })
		TSv.Reload(q)
		advance(0.3)
		T.check(state(q) and state(q).Done == true, "p2ui tutorial: a skipped tutorial (Step 1000) does not start the home chapter")
		leave(q)

		-- a new player: the basics' "home" step completes by claiming a plot at its gate
		local n = join("Newbie")
		T.eq(stepId(n), "welcome", "p2ui tutorial: a new player starts at 'welcome'")
		T.eq(TSv.HandleEvent(n, "ShopOpened"), false, "p2ui tutorial: an event of another step is refused")
		TSv.HandleEvent(n, "Next")
		advance(0.3)
		T.eq(stepId(n), "home", "p2ui tutorial: Next -> 'home'")
		st = state(n)
		T.check(st and st.Target and st.Target.Kind == "Spot" and typeof(st.Target.Position) == "Vector3" and type(st.Target.SpotIndex) == "number",
			"p2ui tutorial: 'home' points at a free gate")
		if st and st.Target and st.Target.SpotIndex then
			claim(n, st.Target.SpotIndex)
			waitFor(function()
				return stepId(n) ~= "home"
			end, 3)
		end
		T.eq(stepId(n), "shop", "p2ui tutorial: claiming the plot completes 'home'")
		leave(n)

		local mine = 0
		for i = errors0 + 1, #Mock.Errors do
			if tostring(Mock.Errors[i].msg):find("Tutorial", 1, true) then
				mine = mine + 1
			end
		end
		T.eq(mine, 0, "p2ui tutorial: no script errors from TutorialService")
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

	-- the phone world's first scenario boots the client; run on its own (--only), this one does it
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

	local function disabled(button)
		return button == nil or button:GetAttribute("Disabled") == true or button.Active == false
	end

	-- a profile in the middle of the tycoon (or the castle variant ready to prestige)
	local function snapshot(variant)
		local home
		if variant == "castle" then
			home = {
				Level = 41, Prestige = 1,
				Stations = { Press1 = 40, Garden = 8, Kitchen = 5, Gym = 5, Vault = 5, House = 4, FusionMachine = 3, ArenaGate = 1, DecorFence = 3, DecorFountain = 3, DecorPodium = 3 },
				Garden = { "honey_bunny", "" }, Gym = {}, CollectorCash = 500,
			}
		else
			home = {
				Level = 20, Prestige = 1,
				Stations = { Press1 = 5, Garden = 2, Kitchen = 2, Gym = 1, Vault = 1, House = 2 },
				Garden = { "honey_bunny", "" }, Gym = {}, CollectorCash = 1840,
			}
		end
		return {
			Tokens = 12450,
			Pets = { pebble_pup = 3, honey_bunny = 1, pip_penguin = 1, mallow_kitten = 1, maple_fox = 1, cloudy_dragon = 1, sleepy_owl = 1 },
			Equipped = { "cloudy_dragon" },
			Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = { pebble_pup = true, honey_bunny = true, pip_penguin = true },
			IndexClaimed = {},
			Tutorial = { Step = 15, Done = true, Gifted = true },
			Cash = 48250, Gems = 1820,
			Home = home,
			Food = {},
			Berries = 99999,
			Tiers = { pebble_pup = { Golden = 2 }, maple_fox = { Rainbow = 1 } },
			Hybrids = { hc1 = { Body = "pip_penguin", Style = "maple_fox", Elements = { "Frost", "Flame" }, Name = "Pipfox", Rarity = "Uncommon", Tier = "Normal", Seed = 3 } },
			PetLevels = { ["pebble_pup@Golden"] = { Level = 12, Xp = 300 }, cloudy_dragon = { Level = 18, Xp = 100 }, ["maple_fox@Rainbow"] = { Level = 20, Xp = 40 } },
			-- Phase 4: sleepy_owl is training (it cannot be equipped), cloudy_dragon evolved once
			PetGrowth = {
				cloudy_dragon = { Evo = 1 },
				sleepy_owl = { Physique = 1, Job = { Stat = "Physique", Ends = os.time() + 130, Rank = 2, Slot = 1, From = "Free", Paid = 1200 } },
			},
		}
	end

	local plot = nil
	local function setHome(variant)
		local Config = moduleAt("shared", "Config")
		local lobby = workspace:FindFirstChild("NimbusLobby")
		if not lobby then
			lobby = Instance.new("Folder")
			lobby.Name = "NimbusLobby"
			lobby.Parent = workspace
		end
		if not plot then
			plot = Instance.new("Folder")
			plot.Name = "Spot_07"
			plot:SetAttribute("SpotIndex", 7)
			plot.Parent = lobby
		end
		plot:SetAttribute("CollectorCash", 1840)
		plot:SetAttribute("IncomePerSecond", 38.5)
		plot:SetAttribute("GardenSlots", 4)
		LocalPlayer:SetAttribute(Config.Attr.SpotIndex, 7)
		LocalPlayer:SetAttribute(Config.Attr.Cash, 48250)
		LocalPlayer:SetAttribute(Config.Attr.Gems, 1820)
		LocalPlayer:SetAttribute(Config.Attr.Berries or "Berries", 99999)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		toClient("ProfileSync", snapshot(variant))
		advance(0.4)
	end

	-- texts under `root` smaller than `floorPx` design px (TextScaled ones by their UITextSizeConstraint minimum, or
	-- their box height when they have none)
	local function smallTexts(root, floorPx)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) then
				local size = d.TextSize
				if d.TextScaled then
					local c = d:FindFirstChildOfClass("UITextSizeConstraint")
					if c then
						size = c.MinTextSize
					else
						local box = Mock.GuiBox(d)
						size = (box and box.scale and box.scale > 0) and (box.h / box.scale) or 0
					end
				end
				if size < floorPx - 0.01 then
					out[#out + 1] = d.Name .. "=" .. tostring(size)
				end
			end
		end
		return out
	end

	-- texts under `root` smaller than `floorPx` ON SCREEN (design size x the cumulative UIScale)
	local function smallOnScreen(root, floorPx)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
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

	S.client_p2ui = guarded("client_p2ui", function()
		local MC = (KC and KC.M and KC.M.MenuController) or moduleAt("client", "Controllers/MenuController")
		local IC = (KC and KC.M and KC.M.IndexController) or moduleAt("client", "Controllers/IndexController")
		local Config = moduleAt("shared", "Config")
		local TC = moduleAt("shared", "TycoonCatalog")
		if not T.check(type(MC) == "table" and type(MC.Open) == "function" and type(MC.GetButton) == "function" and TC ~= nil,
			"p2ui menu: MenuController (Open / GetButton) and TycoonCatalog load") then
			return
		end
		MC.Init()
		if IC and IC.Init then
			IC.Init()
		end
		local errors0 = #Mock.Errors
		local menu = pg():FindFirstChild("NimbusMenu")

		-- the Home tile
		local tile = MC.GetButton("Home")
		local label = tile and tile:FindFirstChild("Label", true)
		T.check(tile ~= nil and tile.Name == "MenuButton_Spot" and label and label.Text == "Home",
			"p2ui menu: the Home tile is MenuButton_Spot labelled 'Home' (GetButton('Home'))")
		LocalPlayer:SetAttribute(Config.Attr.SpotIndex, nil)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		advance(0.2)
		local mark = #Mock.RemoteLog
		Mock.Click(tile)
		advance(0.3)
		local hint = menu and menu:FindFirstChild("MenuHint")
		T.check(#calls("GoToSpot", mark) == 1 and hint and hint.Visible and tostring(find(hint, "Text") and find(hint, "Text").Text):find("Press E", 1, true),
			"p2ui menu: without a home the Home tile walks to a free gate (GoToSpot) with a side hint 'Press E at the gate'")
		local win = menu and menu:FindFirstChild("Window_Home")
		T.check(win == nil or not win.Visible, "p2ui menu: ...and opens no window")

		-- the Home window
		setHome("mid")
		local opened = {}
		local conn = MC.WindowOpened:Connect(function(id)
			opened[#opened + 1] = id
		end)
		Mock.Click(tile)
		advance(0.6)
		win = menu:FindFirstChild("Window_Home")
		T.check(win and win.Visible and table.concat(opened, ",") == "Home", "p2ui menu: with a claimed home the tile opens the Home window (WindowOpened 'Home')", table.concat(opened, ","))
		conn:Disconnect()
		local missing = {}
		for _, def in ipairs(TC.Stations) do
			if not find(win, "Station_" .. def.Id) then
				missing[#missing + 1] = def.Id
			end
		end
		T.check(#missing == 0, "p2ui menu: the Home window lists every station of TycoonCatalog", table.concat(missing, ", "))
		local houseName = find(win, "Tier")
		local homeLevel = find(win, "HomeLevel")
		local wantLevel = TC.HomeLevelOf(snapshot("mid").Home)
		T.check(houseName and houseName.Text == "Villa" and homeLevel and homeLevel.Text == "Home Level " .. wantLevel,
			"p2ui menu: the house tier and the Home Level show", (houseName and houseName.Text or "?") .. " / " .. (homeLevel and homeLevel.Text or "?"))
		-- Phase 5: income per second from the plot folder (live), the garden places in its parts line
		local income = find(win, "PerSecond")
		T.check(income and income.Text:find("38.5", 1, true), "p2ui menu: income per second comes from the plot folder", income and income.Text or "?")
		plot:SetAttribute("IncomePerSecond", 41.5)
		advance(0.5)
		T.check(income and income.Text:find("41.5", 1, true), "p2ui menu: ...and follows its live attribute", income and income.Text or "")
		local parts = find(win, "Parts")
		T.check(parts and parts.Text:find("Garden 4/12 places", 1, true), "p2ui menu: the income card names the garden places (the plot's GardenSlots)", parts and parts.Text or "")
		plot:SetAttribute("IncomePerSecond", 38.5)
		advance(0.3)
		local mult = find(win, "Multiplier")
		T.check(mult and mult.Visible and mult.Text == "x1.25", "p2ui menu: the prestige multiplier tag shows x1.25 for one star")
		-- Upgrade / Build / locks (Station_Press1 is the Berry Bush now)
		local press1 = find(win, "Station_Press1")
		local upgrade = press1 and find(press1, "Upgrade")
		local berry = TC.Get("Press1")
		T.check(press1 and find(press1, "Name") and find(press1, "Name").Text == berry.Name, "p2ui menu: Station_Press1 is the " .. tostring(berry.Name))
		mark = #Mock.RemoteLog
		T.check(upgrade and upgrade.Visible and not disabled(upgrade), "p2ui menu: an affordable upgrade is enabled")
		if upgrade then
			Mock.Click(upgrade)
			advance(0.2)
		end
		local hc = calls("HomeAction", mark)
		T.check(#hc == 1 and hc[1].args[1] == "Upgrade" and hc[1].args[2] == "Press1", "p2ui menu: Upgrade sends HomeAction('Upgrade', stationId)")
		-- (Phase 5: whichever stations are locked / too dear for this home)
		local lock, lockedRow, dear = nil, nil, nil
		for _, def in ipairs(TC.Stations) do
			local row = find(win, "Station_" .. def.Id)
			local l = row and find(row, "Locked")
			local b = row and find(row, "Upgrade")
			if not lock and l and l.Visible and l.Text ~= "" then
				lock, lockedRow = l, row
			end
			if not dear and b and b.Visible and disabled(b) then
				dear = b
			end
		end
		T.check(lock and not (find(lockedRow, "Upgrade") and find(lockedRow, "Upgrade").Visible),
			"p2ui menu: a locked station shows why instead of a button", lock and lock.Text or "")
		T.check(dear ~= nil, "p2ui menu: an upgrade the player cannot afford is disabled")
		T.check(find(win, "Collect") == nil and find(win, "CollectorCard") == nil, "p2ui menu: no Collect button and no Collector card (kids walk over their coins)")
		local prestige = find(win, "Prestige")
		T.check(prestige and disabled(prestige), "p2ui menu: Prestige is disabled before Home Level 40 + the Sky Castle")
		-- castle: the confirmed prestige
		setHome("castle")
		advance(0.3)
		T.check(prestige and not disabled(prestige), "p2ui menu: Prestige is enabled once the home is ready")
		Mock.Click(prestige)
		advance(0.3)
		local confirm = find(win, "PrestigeConfirm")
		local gain = confirm and find(confirm, "Line_Gain")
		T.check(confirm and confirm.Visible and gain and find(gain, "Text").Text:find("Star 2", 1, true) and find(gain, "Text").Text:find("garden place 5", 1, true),
			"p2ui menu: Prestige asks first (what resets, what stays, star 2 with garden place 5)", gain and find(gain, "Text").Text or "")
		mark = #Mock.RemoteLog
		Mock.Click(find(confirm, "ConfirmPrestige"))
		advance(0.2)
		hc = calls("HomeAction", mark)
		T.check(#hc == 1 and hc[1].args[1] == "Prestige" and not confirm.Visible, "p2ui menu: confirming sends HomeAction('Prestige')")
		-- Go home (in the title bar)
		setHome("mid")
		mark = #Mock.RemoteLog
		Mock.Click(find(win, "GoHome"))
		advance(0.4)
		hc = calls("HomeAction", mark)
		T.check(#hc == 1 and hc[1].args[1] == "GoHome" and not MC.IsOpen(), "p2ui menu: Go home sends HomeAction('GoHome') and closes the window")
		MC.Open("Home")
		advance(0.5)
		local small = smallTexts(win, 18)
		T.check(#small == 0, "p2ui menu: every text of the Home window is >= 18 design px", table.concat(small, ", "))

		-- Pets panel
		MC.Open("Pets", { Key = "pebble_pup@Golden" })
		advance(0.8)
		local inv = menu:FindFirstChild("Window_Inventory")
		local goldSlot = find(inv, "Pet_pebble_pup@Golden")
		local hybSlot = find(inv, "Pet_hyb:hc1")
		local rainbow = find(inv, "Pet_maple_fox@Rainbow")
		local function chipText(slot)
			local chip = slot and find(slot, "TierBadge")
			return chip and chip.Visible and find(chip, "Mark") and find(chip, "Mark").Text or ""
		end
		T.check(chipText(goldSlot) == "G" and chipText(hybSlot) == "H" and chipText(rainbow) == "R",
			"p2ui pets: one slot per copy key with tier / hybrid chips (G, R, H)")
		local levelTag = goldSlot and find(goldSlot, "LevelTag")
		T.check(levelTag and levelTag.Visible and levelTag.Text == "Lv 12", "p2ui pets: the slot shows the copy's level")
		local nameLabel = find(inv, "Detail") and find(find(inv, "Detail"), "Name")
		T.check(nameLabel and nameLabel.Text == "Golden Pebble Pup", "p2ui pets: the detail card shows the selected copy", nameLabel and nameLabel.Text or "")
		local tierPill = find(inv, "Tier_Golden")
		local xpBar = find(find(inv, "Detail"), "XpBar")
		T.check(tierPill ~= nil and xpBar ~= nil and find(xpBar, "Text") and find(xpBar, "Text").Text:find("300", 1, true),
			"p2ui pets: the tier pill and the XP bar (300 / next) show")
		local levelText = find(find(inv, "Detail"), "Level")
		T.check(levelText and levelText.Text == "Lv 12 / 100", "p2ui pets: the detail card shows 'Lv 12 / 100' (the cap read from PetCatalog)", levelText and levelText.Text or "")
		-- Phase 4: the coins it makes in the Garden (PetPower x food x stars / meal x the Lucky EV)
		local home = snapshot("mid").Home
		local food = TC.FoodOf(home)
		if food <= 0 then
			food = TC.Coins.GrassFood
		end
		local rate = TC.PetPower("pebble_pup@Golden", 12, nil, 0) * food * TC.PrestigeMultiplier(1) * TC.LuckyEV(home) / TC.Coins.MealSeconds
		local want = rate < 100 and ((string.format("%.1f", floor(rate * 10 + 0.5) / 10)):gsub("%.0$", "")) or nil
		local coinsPill = find(inv, "Stat_Income")
		T.check(coinsPill and coinsPill.Text:find("Coins", 1, true) and (want == nil or coinsPill.Text:find("$" .. want, 1, true)),
			"p2ui pets: the Coins $/s pill shows what the pet makes in the Garden", (coinsPill and coinsPill.Text or "") .. " want $" .. tostring(want))
		-- Feed -> the Food Machine list (CareController), this pet first
		local Care = moduleAt("client", "Controllers/CareController")
		mark = #Mock.RemoteLog
		Mock.Click(find(inv, "FeedPet"))
		advance(0.6)
		local careGui = pg():FindFirstChild("NimbusCare")
		local careWin = careGui and careGui:FindFirstChild("Window_Care")
		T.check(Care and Care.Mode and Care.Mode() == "Feed" and careWin and careWin.Visible and not (inv and inv.Visible and MC.IsOpen()),
			"p2ui pets: Feed opens the Food Machine list (CareController) instead of the old picker")
		local row = careWin and find(careWin, "Feed_pebble_pup@Golden")
		T.check(row and row.LayoutOrder == 1, "p2ui pets: ...with that pet first")
		if row then
			Mock.Click(find(row, "Feed"))
			advance(0.4)
		end
		local pc = calls("PetCare", mark)
		T.check(#pc == 1 and pc[1].args[1] == "Feed" and pc[1].args[2] == "pebble_pup@Golden", "p2ui pets: its Feed sends PetCare('Feed', key)")
		T.check(find(inv, "FeedPicker") == nil, "p2ui pets: the old Feed picker is gone")
		if Care then
			Care.Close()
		end
		advance(0.3)
		-- Garden (any role) / Train / EVOLVE
		MC.Open("Pets", { Key = "honey_bunny" })
		advance(0.4)
		local work = find(inv, "WorkPet")
		mark = #Mock.RemoteLog
		T.check(work and work.Text == "Leave Garden", "p2ui pets: a pet working in the Garden offers 'Leave Garden'", work and work.Text or "")
		Mock.Click(work)
		advance(0.3)
		hc = calls("HomeAction", mark)
		T.check(#hc == 1 and hc[1].args[1] == "GardenSet" and type(hc[1].args[2]) == "table" and hc[1].args[2].Slot == 1 and hc[1].args[2].Key == nil,
			"p2ui pets: ...which clears its place (HomeAction GardenSet {Slot = 1})")
		MC.Open("Pets", { Key = "mallow_kitten" })
		advance(0.3)
		mark = #Mock.RemoteLog
		T.check(work.Text == "Garden" and not disabled(work), "p2ui pets: a Combat pet can go to the Garden too ('Garden')")
		Mock.Click(work)
		advance(0.3)
		hc = calls("HomeAction", mark)
		T.check(#hc == 1 and hc[1].args[1] == "GardenSet" and hc[1].args[2].Slot == 2 and hc[1].args[2].Key == "mallow_kitten",
			"p2ui pets: ...into the first free place (GardenSet {Slot = 2, Key})")
		-- a pet in training: no Equip, its timer
		MC.Open("Pets", { Key = "sleepy_owl" })
		advance(0.3)
		local status = find(find(inv, "Detail"), "Work")
		T.check(disabled(find(inv, "Equip")) and status and status.Text:find("Training Physique", 1, true),
			"p2ui pets: a pet in training cannot be equipped and shows its training", status and status.Text or "")
		Mock.Click(find(inv, "TrainPet"))
		advance(0.5)
		T.check(Care and Care.Mode() == "Train", "p2ui pets: Train opens the Training Place window")
		if Care then
			Care.Close()
		end
		advance(0.3)
		-- EVOLVE (the Rainbow maple fox copy is level 20)
		MC.Open("Pets", { Key = "cloudy_dragon" })
		advance(0.3)
		local evoPill = find(inv, "Evolution")
		T.check(evoPill and evoPill.Visible and evoPill.Text:find("Evolved", 1, true), "p2ui pets: an evolved pet shows its evolution pill")
		T.check(not find(inv, "EvolvePet").Visible, "p2ui pets: no EVOLVE button below the next evolution level")
		MC.Open("Pets", { Key = "maple_fox@Rainbow" })
		advance(0.3)
		local evolve = find(inv, "EvolvePet")
		T.check(evolve and evolve.Visible and not disabled(evolve), "p2ui pets: a level-20 pet shows EVOLVE!")
		mark = #Mock.RemoteLog
		Mock.Click(evolve)
		advance(0.4)
		local yes = careGui and find(careGui, "ConfirmYes")
		T.check(yes and find(careGui, "CareConfirm").Visible, "p2ui pets: EVOLVE asks first")
		Mock.Click(yes)
		advance(0.3)
		pc = calls("PetCare", mark)
		T.check(#pc == 1 and pc[1].args[1] == "Evolve" and pc[1].args[2] == "maple_fox@Rainbow", "p2ui pets: ...then sends PetCare('Evolve', key)")
		MC.Open("Pets", { Key = "pebble_pup@Golden" })
		advance(0.3)
		local small = smallTexts(inv, 18)
		T.check(#small == 0, "p2ui pets: every text of the Pets page is >= 18 design px", table.concat(small, ", "))

		-- Shop Gems tab
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
		MC.Open("Shop", { Tab = "Gems" })
		advance(0.6)
		local shop = menu:FindFirstChild("Window_Shop")
		local page = find(shop, "Page_Gems")
		local secret = page and find(page, "GemRoulette_Secret")
		T.check(page and page.Visible and secret and secret.Visible, "p2ui shop: OpenPanel('Shop', {Tab = 'Gems'}) shows the Gems tab with the Secret roulette")
		local chances = secret and find(secret, "Chances")
		local mythic = chances and find(chances, "Chance_Mythic")
		local secretChance = chances and find(chances, "Chance_Secret")
		T.check(mythic and secretChance and mythic.Text:find("85%", 1, true) and secretChance.Text:find("15%", 1, true),
			"p2ui shop: the Secret roulette shows its odds (Mythic 85%, Secret 15%)")
		mark = #Mock.RemoteLog
		Mock.Click(find(secret, "Spin"))
		advance(0.3)
		local br = calls("BuyRoulette", mark)
		T.check(#br == 1 and br[1].args[1] == "Secret" and br[1].args[2] == "Gems", "p2ui shop: a gem spin sends BuyRoulette('Secret', 'Gems')")
		toClient("RouletteResult", { Ok = false, Reason = "test" })
		advance(0.3)
		local cloudGem = find(page, "GemRoulette_Cloud")
		T.check(cloudGem ~= nil, "p2ui shop: token roulettes with a gem price are offered for Gems too")
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", true)
		advance(0.3)
		local notice = find(page, "GemNotice")
		T.check(not secret.Visible and notice and notice.Visible, "p2ui shop: where paid random items are restricted the gem roulettes hide behind a notice")
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
		advance(0.2)
		small = smallTexts(page, 18)
		T.check(#small == 0, "p2ui shop: every text of the Gems tab is >= 18 design px", table.concat(small, ", "))
		MC.Close()
		advance(0.3)
		MC.Open("Shop", { RouletteId = "Secret" })
		advance(0.5)
		T.check(page.Visible, "p2ui shop: OpenPanel('Shop', {RouletteId = 'Secret'}) (the Storm Altar) opens the Gems tab")
		MC.Close()
		advance(0.3)

		-- Index Fusions tab
		if T.check(IC ~= nil and type(IC.Open) == "function", "p2ui index: IndexController loads") then
			local claimable = IC.ClaimableCount()
			IC.Open("Fusions")
			advance(0.6)
			local index = pg():FindFirstChild("NimbusIndex")
			local tileF = index and find(index, "Group_Fusions")
			local grid = index and find(index, "PetGrid")
			local keys = {}
			for _, d in ipairs(grid and grid:GetChildren() or {}) do
				local key = d.Name:match("^IndexPet_(.+)$")
				if key then
					keys[#keys + 1] = key
				end
			end
			table.sort(keys)
			T.check(tileF ~= nil and table.concat(keys, ",") == "hyb:hc1,maple_fox@Rainbow,pebble_pup@Golden",
				"p2ui index: Open('Fusions') lists the fused copies (hybrids, Golden, Rainbow)", table.concat(keys, ","))
			local title = index and find(index, "GroupTitle")
			T.check(title and title.Text:find("Fusions", 1, true), "p2ui index: ...under a 'Fusions' header")
			T.eq(IC.ClaimableCount(), claimable, "p2ui index: fusions are not part of the group rewards")
			local claimButton = index and find(index, "Claim")
			T.check(claimButton and not disabled(claimButton) and claimButton.Text ~= "CLAIM", "p2ui index: the rewards box leads to the Fusion Machine / the Home window instead of a claim")
			small = smallTexts(index, 18)
			T.check(#small == 0, "p2ui index: every text of the Index is >= 18 design px", table.concat(small, ", "))
			IC.Close()
			advance(0.3)
		end

		-- clean up for the scenarios after this one
		MC.Close()
		LocalPlayer:SetAttribute(Config.Attr.SpotIndex, nil)
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", nil)
		if plot then
			plot:Destroy()
			plot = nil
		end
		advance(0.3)
		local mine = {}
		for i = errors0 + 1, #Mock.Errors do
			local msg = tostring(Mock.Errors[i].msg)
			if msg:find("MenuController", 1, true) or msg:find("IndexController", 1, true) then
				mine[#mine + 1] = msg:sub(1, 160)
			end
		end
		T.check(#mine == 0, "p2ui: no script errors from MenuController / IndexController", table.concat(mine, " | "))
		if KC and KC.flushErrors then
			KC.flushErrors("client_p2ui")
		end
	end)

	S.client_p2ui_mobile = guarded("client_p2ui_mobile", function()
		local MC = moduleAt("client", "Controllers/MenuController")
		local IC = moduleAt("client", "Controllers/IndexController")
		if not T.check(type(MC) == "table" and type(MC.Open) == "function", "p2ui phone: MenuController loads") then
			return
		end
		bootIfNeeded()
		MC.Init()
		if IC and IC.Init then
			IC.Init()
		end
		setHome("mid")
		local menu = pg():FindFirstChild("NimbusMenu")
		local function check(label, root)
			local small = smallOnScreen(root, 14)
			T.check(#small == 0, "p2ui phone 390x844: every text of " .. label .. " is >= 14 px on screen", table.concat(small, ", "))
		end
		MC.Open("Home")
		advance(0.8)
		check("the Home window", menu:FindFirstChild("Window_Home"))
		MC.Open("Pets", { Key = "pebble_pup@Golden" })
		advance(0.8)
		check("the Pets page", menu:FindFirstChild("Window_Inventory"))
		MC.Open("Feed", { Key = "pebble_pup@Golden" })
		advance(0.8)
		check("the Food Machine list", pg():FindFirstChild("NimbusCare"))
		local Care = moduleAt("client", "Controllers/CareController")
		if Care then
			Care.Close()
			advance(0.3)
		end
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
		MC.Open("Shop", { Tab = "Gems" })
		advance(0.8)
		check("the Gems tab", menu:FindFirstChild("Window_Shop"))
		MC.Close()
		advance(0.3)
		if IC and IC.Open then
			IC.Open("Fusions")
			advance(0.8)
			check("the Index (Fusions)", pg():FindFirstChild("NimbusIndex"))
			IC.Open("Common")
			advance(0.8)
			check("the Index (Common)", pg():FindFirstChild("NimbusIndex"))
			IC.Close()
		end
		MC.Close()
		LocalPlayer:SetAttribute("SpotIndex", nil)
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", nil)
		if plot then
			plot:Destroy()
			plot = nil
		end
		advance(0.3)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
