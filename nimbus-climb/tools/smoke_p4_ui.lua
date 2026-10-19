-- smoke_p4_ui.lua: Phase 4 UI (ARCHITECTURE_V3.md "Phase 4 build contract" 3.8, 3.11, 8.1 and 9): the tutorial's rewritten
-- chapter 2 and the appended chapter 4 (shared/TutorialSteps.lua, server/Services/TutorialService.lua), the Phase 4 NPC
-- tips (shared/NpcDialog.lua) and ArenaController's Champion Ring window + the safe-zone toast
-- (client/Controllers/ArenaController.lua). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half:
-- (Phase 5, owner tutorial W4: chapter 3's step 17 is "dungeon", chapter 2 speaks of Cloud Cash / the Berry Farm /
-- berries, the NPC needles follow the Phase 5 lines; the feed step tops the berries up so the first feed works)
--   p4ui_content        (server, content) the index rule (chapters start at 10 / 15 / 19, chapter 2 keeps five steps
--                       claim, garden, coins, machine, feed; chapter 3 arena, team, trial, raid; chapter 4 train, ring,
--                       portal), each chapter ends on one ChapterEnd step, the targets and CompleteOn of the new steps,
--                       texts 20-200 bytes in plain text naming the Pet Garden, rainbow coins, the Food Machine, Feed,
--                       EVOLVE, the Training Place and the Champion Ring, IndexOf keeps chapter 1's "portal", the new
--                       CompleteOn kinds + RING_FINISH_TOKENS 300 in TutorialService; NPC tips: 3-5 lines <= 125 bytes,
--                       the Phase 4 needles with the catalogs' numbers (FeedShare[1], EvolutionBonusOf(1), the evolution
--                       levels, RoleMult.Economy, Prestige x / Gems / garden places, RecordMult) and the kept p3ui needles
--   p4ui_tutorial       (server, booted) a migrated veteran (home claimed, Garden with a pet, Food Machine) resumes at
--                       every index 10-14 and lands on "feed" (no step waits for what the player already has); a finished
--                       Phase 3 tutorial (Step 19, Done) resumes in chapter 4: "train" (the arrow walks the pads to the
--                       Training Place, then points at its mat; a real PetCareService.Train completes it), "ring" (the arrow
--                       at ArenaInfo.RingPortal; a free gate first without a home; a BattleEnded Ring win completes it, a
--                       lost round does not), "portal" (the Home menu tile; walking through the real home portal completes
--                       it): Done, +300 Tokens once, Step 22 stored, still done after a rejoin; RingWon / TrainingStarted
--                       pass at once for a player who already has a ring record / a trained pet; a skipped tutorial never
--                       shows chapter 4; no script errors from TutorialService
--   client_p4ui         (client) the Champion Ring window: OpenPanel("Ring") and a RingPrompt open it; "Best: Round 24",
--                       the runs, the start picker = round 1 + the beaten boss rounds (10, 20; not 30), the latest boss
--                       round picked, "CONTINUE" / "START", the champion's BOSS tag, "Next win: +$X +Y XP" equal to
--                       BattleCatalog.RingRewards (x3 on a new record), the fighters (the battle team, a training pet
--                       skipped), the server's best from Portal_Ring's RingBoard (top 3), the refusal reasons (no home,
--                       far from the portal) and START -> BattleRequest("Ring", start), a refusal toast shown in the footer;
--                       the Team screen's "Champion Ring best" line; the safe-zone side toast when crossing the arena's
--                       edge (never in the screen centre); every text >= 18 design px; no script errors
--   client_p4ui_mobile  (phone 390x844 and 844x390) the ring window keeps every text >= 14 px and stays on screen
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

-- this file's folder ("tools/") from the chunk name smoke.py gives it ("=tools/smoke_p4_ui.lua")
local HERE = (debug.getinfo(1, "S").source or ""):match("^=(.*)smoke_p4_ui%.lua$") or ""

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
	-- p4ui_content
	------------------------------------------------------------------------------------------------
	S.p4ui_content = guarded("p4ui_content", function()
		local Steps = requireAt("shared/TutorialSteps")
		local ND = requireAt("shared/NpcDialog")
		local TC = requireAt("shared/TycoonCatalog")
		local PC = requireAt("shared/PetCatalog")
		local BC = requireAt("shared/BattleCatalog")
		if not T.check(type(Steps) == "table" and type(Steps.Steps) == "table" and type(ND) == "table", "p4ui: TutorialSteps and NpcDialog load") then
			return
		end
		local starts = Steps.ChapterStart or {}
		T.check(starts[1] == 1 and starts[2] == 10 and starts[3] == 15 and starts[4] == 19 and #Steps.Steps == 21,
			"p4ui: the index rule: chapters start at 1 / 10 / 15 / 19 and there are 21 steps (no saved index moved)",
			tostring(starts[2]) .. "/" .. tostring(starts[3]) .. "/" .. tostring(starts[4]) .. " of " .. #Steps.Steps)
		local function ids(from, to)
			local out = {}
			for i = from, math.min(to, #Steps.Steps) do
				out[#out + 1] = Steps.Steps[i].Id
			end
			return table.concat(out, ",")
		end
		T.eq(ids(10, 14), "claim,garden,coins,machine,feed", "p4ui: chapter 2 is rewritten in place: claim, garden, coins, machine, feed")
		T.eq(Steps.Steps[11] and Steps.Steps[11].Id, "garden", "p4ui: Steps[11].Id is 'garden' (smoke_economy reads it)")
		T.eq(ids(15, 18), "arena,team,dungeon,raid", "p4ui: chapter 3 keeps indices 15-18 (Phase 5: 17 'trial' -> 'dungeon')")
		T.eq(ids(19, 21), "train,ring,portal", "p4ui: chapter 4 is appended at 19-21: train, ring, portal")
		local bad, ends = {}, {}
		for i, step in ipairs(Steps.Steps) do
			local want = (i <= 9 and 1) or (i <= 14 and 2) or (i <= 18 and 3) or 4
			if (step.Chapter or 1) ~= want then
				bad[#bad + 1] = step.Id .. " chapter " .. tostring(step.Chapter)
			end
			if type(step.Text) ~= "string" or #step.Text < 20 or #step.Text > 200 or step.Text:find("[<>&]") then
				bad[#bad + 1] = step.Id .. " text"
			end
			if type(step.Title) ~= "string" or step.Title == "" then
				bad[#bad + 1] = step.Id .. " title"
			end
			if step.ChapterEnd then
				ends[#ends + 1] = i
			end
		end
		T.check(#bad == 0, "p4ui: every step has its chapter, a title and a short plain text (20-200 bytes)", table.concat(bad, "; "))
		T.eq(table.concat(ends, ","), "9,14,18,21", "p4ui: each chapter ends on exactly one ChapterEnd step (9, 14, 18, 21)")
		local s = Steps.Steps
		local function t(i)
			return type(s[i].Target) == "table" and s[i].Target or {}
		end
		T.check(s[11].CompleteOn == "GardenPlaced" and t(11).GardenSpot == true and t(11).Pad == "Garden" and t(11).Station == "Garden",
			"p4ui: 'garden' = the free Pet Garden pad, then a garden spot; completes on GardenPlaced")
		T.check(s[12].CompleteOn == "CoinsScooped" and t(12).Coins == true and t(12).Station == "Garden", "p4ui: 'coins' points at the coins; CoinsScooped")
		T.check(s[13].CompleteOn == "Built" and s[13].Station == "Kitchen" and t(13).Pad == "Kitchen" and t(13).Path == true,
			"p4ui: 'machine' walks the pads to the Food Machine (Built Kitchen)")
		T.check(s[14].CompleteOn == "Fed" and t(14).Food == true and t(14).Station == "Kitchen" and s[14].ChapterEnd == true,
			"p4ui: 'feed' points at the Food Machine; Fed ends chapter 2")
		T.check(s[19].CompleteOn == "TrainingStarted" and t(19).Pad == "Gym" and t(19).Station == "Gym" and t(19).Path == true,
			"p4ui: 'train' walks the pads to the Training Place; TrainingStarted")
		T.check(s[20].CompleteOn == "RingWon" and t(20).Kind == "Arena" and t(20).Place == "Ring", "p4ui: 'ring' points at the Champion Ring portal; RingWon")
		T.check(s[21].CompleteOn == "PortalUsed" and t(21).Kind == "Menu" and t(21).Id == "Home" and s[21].ChapterEnd == true,
			"p4ui: 'portal' rings the Home menu tile; PortalUsed ends chapter 4")
		T.eq(Steps.IndexOf and Steps.IndexOf.portal, 7, "p4ui: IndexOf keeps the first step of an id (chapter 1's 'portal' = 7)")
		local all = ""
		for i = 10, #s do
			all = all .. " " .. s[i].Text
		end
		local missing = {}
		for _, needle in ipairs({ "Pet Garden", "Cloud Cash", "Berry Farm", "berries", "Food Machine", "Feed", "EVOLVE", "Dungeon", "Training Place", "Champion Ring" }) do
			if not all:find(needle, 1, true) then
				missing[#missing + 1] = needle
			end
		end
		T.check(#missing == 0, "p4ui: the chapters name the Pet Garden, Cloud Cash, the Berry Farm, berries, the Food Machine, Feed, EVOLVE, the Dungeon, the Training Place and the Champion Ring",
			table.concat(missing, ", "))
		local evoLevel = PC and PC.EvolutionLevels and PC.EvolutionLevels[1] or 20
		T.check(s[14].Text:find("level " .. tostring(evoLevel), 1, true) ~= nil, "p4ui: 'feed' quotes the first evolution level (" .. tostring(evoLevel) .. ")")
		T.check(s[5].Text:find("follows right behind you", 1, true) ~= nil and s[17].Text:find("Floor 1", 1, true) ~= nil
			and not (s[17].Text:find("RETREAT", 1, true) or s[17].Text:find("Trial", 1, true)),
			"p4ui: the 'equip' and 'dungeon' texts follow Phase 5 (pets follow behind; Floor 1, no Trial / RETREAT)")
		local src = sourceOf("server/Services/TutorialService") or ""
		for _, kind in ipairs({ "GardenPlaced", "CoinsScooped", "TrainingStarted", "RingWon", "PortalUsed" }) do
			T.check(src:find(kind .. " = true", 1, true) ~= nil, "p4ui: TutorialService knows CompleteOn " .. kind)
		end
		T.check(src:match("local RING_FINISH_TOKENS = (%d+)") == "300", "p4ui: chapter 4 pays RING_FINISH_TOKENS = 300")
		T.check(not src:find("CollectPad", 1, true) and not src:find("checkCollected", 1, true) and not src:find("Cooked", 1, true),
			"p4ui: TutorialService no longer reads the Collector's CollectPad, checks 'Collected' or listens for Cooked")

		-- NPC tips
		local long, counts, said = {}, {}, {}
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
			end
		end
		T.check(#counts == 0, "p4ui: every NPC keeps 3-5 lines", table.concat(counts, ", "))
		T.check(#long == 0, "p4ui: every NPC line fits the dialog (<= 125 bytes, no rich-text characters)", table.concat(long, ", "))
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
		local function pct(x)
			return tostring(math.floor(x * 100 + 0.5)) .. "%"
		end
		-- Phase 5 (3.1): EVOLVE multiplies the level bonus (EvolutionBonusOf); the old flat boost table is gone
		local bonus1 = PC and type(PC.EvolutionBonusOf) == "function" and tonumber(PC.EvolutionBonusOf(1)) or 1.5
		local faster = pct(bonus1 - 1)
		T.check(PC ~= nil and PC.EvolutionBoost == nil and PC.EvolutionMultiplier == nil, "p4ui: PetCatalog.EvolutionBoost / EvolutionMultiplier are gone (W3 gate)")
		local levels = PC and PC.EvolutionLevels or { 20, 50 }
		local P = TC and TC.Prestige or {}
		local ok1, why1 = says("granny_owl", "Berry Basket", "Food Machine", "Feed", "berries become XP", "EVOLVE", "new look",
			"grow " .. faster .. " faster per level", "level " .. levels[1], "at " .. levels[2], "Gems")
		T.check(ok1, "p4ui: Granny Owl explains the Berry Basket, the Food Machine, EVOLVE (a new look, " .. faster .. " faster, levels " .. levels[1] .. " / " .. levels[2] .. ") and Gem spins", why1)
		local ok2, why2 = says("mayor_panda", "free gate", "Food Bowl", "Cloud Cash", "Berry Farm", "Food Machine",
			"Home Level " .. tostring(P.HomeLevel or 40), "x" .. tostring(P.IncomeMultiplier or 1.25) .. " coins", tostring(P.GemReward or 100) .. " Gems",
			"one more garden place", "portal")
		T.check(ok2, "p4ui: Mayor Panda explains the Food Bowl, Cloud Cash, the Berry Farm, Prestige and the home portal", why2)
		local mult = BC and BC.Ring and BC.Ring.RecordMult or 3
		local ok3, why3 = says("coach_corgi", "Training Place", "Attack Speed", "Physique", "Ability", "Defense", "Champion Ring",
			(mult == 3 and "triple" or "x" .. tostring(mult)) .. " Cash", "Dungeon", tostring(BC and BC.Dungeon and BC.Dungeon.Floors or 12) .. " floors", "Team", "trophies")
		T.check(ok3, "p4ui: Coach Corgi explains the Training Place (4 skills), the Champion Ring (record x" .. tostring(mult) .. "), the Dungeon and the Team tips", why3)
		local ok4, why4 = says("captain_penguin", "safe zone", "DASH", "Boss Raid", "Obby portal", "level")
		T.check(ok4, "p4ui: Captain Penguin explains the safe zones", why4)
		local npcAll = ""
		for _, text in pairs(said) do
			npcAll = npcAll .. text
		end
		T.check(not npcAll:find("Collector", 1, true) and not npcAll:find("Kitchen", 1, true) and not npcAll:find("Gym", 1, true)
			and not npcAll:find("Cloud Press", 1, true), "p4ui: no NPC talks about the Collector, the Kitchen, the Gym or the Cloud Press")
		local stale = {}
		for _, word in ipairs({ "Trial", "RETREAT", "rainbow coins", "Berry Bush", "Carrot Patch", "Magnet", "4th", "Economy pets" }) do
			if npcAll:find(word, 1, true) then
				stale[#stale + 1] = word
			end
		end
		T.check(#stale == 0, "p4ui: Phase 5: no NPC talks about Trials, RETREAT, rainbow coins, the four plants, the Coin Magnet or a 4th team pet", table.concat(stale, ", "))
	end)

	------------------------------------------------------------------------------------------------
	-- p4ui_tutorial
	------------------------------------------------------------------------------------------------
	local userSeq = 0
	local function join(prefix)
		userSeq = userSeq + 1
		local p = Mock.AddPlayer(prefix .. userSeq, 969000 + userSeq)
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

	S.p4ui_tutorial = guarded("p4ui_tutorial", function()
		if not K.needBoot() then
			return
		end
		local Config = config()
		local TSv = mod("TutorialService")
		local DataS = mod("DataService")
		local SS = mod("SpotService")
		local Ty = requireAt("server/Services/TycoonService")
		local Care = requireAt("server/Services/PetCareService")
		local BS = requireAt("server/Services/BattleService")
		local AB = requireAt("server/Services/ArenaBuilder")
		local HB = requireAt("server/Services/HomeBuilder")
		local Steps = requireAt("shared/TutorialSteps")
		local TC = requireAt("shared/TycoonCatalog")
		local PK = requireAt("shared/PetKeys")
		local info = AB and AB.GetInfo and AB.GetInfo() or nil
		if not T.check(TSv and DataS and SS and Ty and Care and BS and Steps and TC and PK and info and type(TSv.Reload) == "function",
			"p4ui tutorial: TutorialService, DataService, TycoonService, PetCareService, BattleService and the arena are loaded") then
			return
		end
		local errors0 = #Mock.Errors
		local function state(p)
			return TSv.GetState(p)
		end
		local function stepId(p)
			local st = state(p)
			return st and not st.Done and st.Id or (st and st.Done and "done!") or nil
		end
		local function resume(p, step)
			DataS.SetTutorial(p, { Step = step, Done = true, Gifted = true })
			TSv.Reload(p)
			advance(0.4)
		end
		local function giveHome(p, stations, garden)
			DataS.MutateHome(p, function(h)
				h.Stations = h.Stations or {}
				for id, level in pairs(stations) do
					h.Stations[id] = level
				end
				if garden then
					h.Garden = h.Garden or {}
					for slot, key in pairs(garden) do
						h.Garden[slot] = key
					end
				end
			end)
			advance(0.6)
		end

		------------------------------------------------------------ a migrated veteran resumes mid-chapter 2
		local v = join("Veteran")
		PK.Add(DataS.GetProfile(v), "pebble_pup", 1)
		DataS.MarkDirty(v)
		local plot = claimFree(v)
		if not T.check(plot ~= nil, "p4ui tutorial: (setup) the veteran claims a home") then
			leave(v)
			return
		end
		giveHome(v, { Garden = 1, Kitchen = 1 }, { [1] = "pebble_pup" })
		local landed = {}
		for index = 10, 14 do
			resume(v, index)
			landed[#landed + 1] = index .. ">" .. tostring(stepId(v))
		end
		T.eq(table.concat(landed, " "), "10>feed 11>feed 12>feed 13>feed 14>feed",
			"p4ui tutorial: a migrated save at any index 10-14 (home, a garden pet, the Food Machine) lands on 'feed' at once")
		local st = state(v)
		local kitchen = HB and HB.GetStation and HB.GetStation(SS.GetSpot(v), "Kitchen")
		local hopper = kitchen and kitchen:FindFirstChild("Hopper", true)
		T.check(st and st.Target and st.Target.Kind == "Spot" and hopper and (st.Target.Position - hopper.Position).Magnitude < 0.5,
			"p4ui tutorial: 'feed' points at the Food Machine's Hopper", st and tostring(st.Hint))
		-- (Phase 5: feeding costs berries; entering 'feed' topped the berries up for the first feed)
		T.check((DataS.GetBerries(v) or 0) >= 40, "p4ui tutorial: entering 'feed' tops the berries up for the first feed", tostring(DataS.GetBerries(v)))
		local cash0 = DataS.GetCash(v)
		DataS.AddCash(v, 100000)
		advance(0.3)
		local okFeed, fed = Care.Feed(v, "pebble_pup", nil)
		advance(0.6)
		local paid = (type(fed) == "table" and tonumber(fed.Paid)) or 0
		T.check(okFeed == true and stepId(v) == "arena" and state(v).Step == 15, "p4ui tutorial: a feed ends chapter 2 and moves on to chapter 3", tostring(fed))
		T.eq(DataS.GetCash(v), cash0 + 100000 - paid + 1000, "p4ui tutorial: ...paying the home chapter's $1,000 once")
		leave(v)

		------------------------------------------------------------ a finished Phase 3 tutorial resumes in chapter 4
		local p = join("Champ")
		local prof = DataS.GetProfile(p)
		PK.Add(prof, "pebble_pup", 1)
		DataS.MarkDirty(p)
		resume(p, 19)
		T.eq(stepId(p), "train", "p4ui tutorial: a finished Phase 3 tutorial (stored Step 19, Done) resumes at chapter 4's 'train'")
		st = state(p)
		T.check(st and st.Chapter == 4 and st.Step == 19 and st.Total == 21, "p4ui tutorial: ...as chapter 4, step 19/21")
		-- the ring step needs a home: claim one, build up to the Training Place
		local index = claimFree(p)
		T.check(index ~= nil, "p4ui tutorial: (setup) the player claims a home")
		local spot = SS.GetSpot(p)
		advance(0.6)
		-- follow the arrow from pad to pad: every pad it names is buyable, the last one is the Training Place
		DataS.AddCash(p, 5000000)
		advance(0.6)
		local path, lost = {}, nil
		for _ = 1, 40 do
			if (DataS.GetHome(p).Stations or {}).Gym then
				break
			end
			st = state(p)
			local padId = nil
			for _, pad in ipairs(TC.AvailablePads(DataS.GetHome(p))) do
				local pos = spot and padPosition(HB, TC, spot, pad.StationId)
				if not pad.Locked and pos and st and st.Target and typeof(st.Target.Position) == "Vector3" and (pos - st.Target.Position).Magnitude < 0.5 then
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
		T.check(lost == nil and #path >= 1 and path[#path] == "Gym" and stepId(p) == "train",
			"p4ui tutorial: following the 'train' arrow from pad to pad builds the Training Place", table.concat(path, " > ") .. (lost and (" (lost at: " .. lost .. ")") or ""))
		advance(0.6)
		st = state(p)
		local gym = HB and HB.GetStation and HB.GetStation(spot, "Gym")
		local mat = gym and gym:FindFirstChild("Spot1", true)
		T.check(st and st.Id == "train" and st.Target and mat and mat:IsA("Attachment") and (st.Target.Position - mat.WorldPosition).Magnitude < 0.5,
			"p4ui tutorial: with the Training Place built the arrow points at its first mat", st and tostring(st.Hint))
		DataS.AddCash(p, 5000000)
		advance(0.3)
		local okTrain, job = Care.Train(p, "pebble_pup", "Physique")
		advance(0.6)
		T.check(okTrain == true, "p4ui tutorial: (setup) PetCareService.Train starts a job", tostring(job))
		T.eq(stepId(p), "ring", "p4ui tutorial: starting to train a pet completes 'train' (PetCareService.TrainingStarted)")
		st = state(p)
		local ringPos = info.RingPortal and (typeof(info.RingPortal) == "Instance" and info.RingPortal.Position or nil)
		T.check(st and st.Target and st.Target.Kind == "Spot" and ringPos and (st.Target.Position - ringPos).Magnitude < 1,
			"p4ui tutorial: 'ring' points at the Champion Ring portal (ArenaInfo.RingPortal)", st and tostring(st.Hint))
		BS.BattleEnded:Fire("ui-ring-lost", { Mode = "Ring", Round = 1, Won = false, Winners = {}, Losers = { p.UserId } })
		advance(0.6)
		T.eq(stepId(p), "ring", "p4ui tutorial: a lost ring round does not complete 'ring'")
		BS.BattleEnded:Fire("ui-ring-won", { Mode = "Ring", Round = 1, Won = true, Winners = { p.UserId }, Losers = {} })
		advance(0.6)
		T.eq(stepId(p), "portal", "p4ui tutorial: a won ring round (BattleEnded Mode Ring, Won) completes 'ring'")
		st = state(p)
		T.check(st and st.Target and st.Target.Kind == "Menu" and st.Target.Id == "Home", "p4ui tutorial: 'portal' rings the Home menu tile (Menu Home)")
		-- walk through the real home portal
		local tokens0 = DataS.GetTokens(p)
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			Mock.Teleport(p, CFrame.new(Config.Lobby.Origin + Vector3.new(30, 4, 30)))
			advance(4)
		end
		local okPortal = Ty.OpenHomePortal(p)
		advance(0.3)
		local text = p:GetAttribute(Config.Attr.HomePortal)
		local x, y, z = nil, nil, nil
		if type(text) == "string" then
			x, y, z = text:match("^([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),")
		end
		T.check(okPortal == true and x ~= nil, "p4ui tutorial: (setup) the home portal opens", tostring(text))
		if x then
			Mock.Teleport(p, CFrame.new(tonumber(x), tonumber(y) + 3, tonumber(z)))
		end
		waitFor(function()
			return stepId(p) ~= "portal"
		end, 3)
		st = state(p)
		T.check(st and st.Done == true and st.Completed == true, "p4ui tutorial: walking through the home portal completes 'portal': the tutorial is done")
		T.eq(DataS.GetTokens(p) - tokens0, 300, "p4ui tutorial: ...and pays the Pets chapter's 300 Tokens")
		T.eq(DataS.GetTutorial(p).Step, 22, "p4ui tutorial: the stored Step is one past the end (22)")
		TSv.HandleEvent(p, "Next")
		Ty.OpenHomePortal(p)
		advance(4)
		T.eq(DataS.GetTokens(p) - tokens0, 300, "p4ui tutorial: nothing is paid twice")
		local userId, name = p.UserId, p.Name
		leave(p)
		advance(1.5)
		p = Mock.AddPlayer(name, userId)
		advance(1.2)
		T.check(state(p) and state(p).Done == true, "p4ui tutorial: the finished tutorial stays finished after a rejoin")
		leave(p)

		------------------------------------------------------------ steps that pass at once
		local q = join("Climber")
		PK.Add(DataS.GetProfile(q), "honey_bunny", 1)
		DataS.MarkDirty(q)
		DataS.MutateRing(q, function(ring)
			ring.Best = 3
		end)
		resume(q, 20)
		T.eq(stepId(q), "portal", "p4ui tutorial: a player with a ring record (Ring.Best >= 1) passes 'ring' at once")
		resume(q, 19)
		T.eq(stepId(q), "train", "p4ui tutorial: (setup) back on 'train'")
		DataS.MutateGrowth(q, function(g)
			g.honey_bunny = { Physique = 1 }
		end)
		advance(0.8)
		T.eq(stepId(q), "portal", "p4ui tutorial: a pet with a training rank passes 'train' at once (and the ring record 'ring')")
		leave(q)

		------------------------------------------------------------ skipped players never see chapter 4
		local k = join("Skipper")
		resume(k, 1000)
		T.check(state(k) and state(k).Done == true, "p4ui tutorial: a skipped tutorial (Step 1000) never shows chapter 4")
		leave(k)

		local mine = 0
		for i = errors0 + 1, #Mock.Errors do
			if tostring(Mock.Errors[i].msg):find("Tutorial", 1, true) then
				mine = mine + 1
			end
		end
		T.eq(mine, 0, "p4ui tutorial: no script errors from TutorialService")
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

	local function lastRequest(mark, action)
		local found = nil
		for i = (mark or 0) + 1, #Mock.RemoteLog do
			local e = Mock.RemoteLog[i]
			if e.kind == "server" and e.remote == "BattleRequest" and e.args and e.args[1] == action then
				found = e.args
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
				if d.TextSize < floorPx - 0.01 then
					out[#out + 1] = d.Name .. "=" .. tostring(d.TextSize)
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
				if d.TextSize * scale < floorPx - 0.05 then
					out[#out + 1] = string.format("%s=%.1f", d.Name, d.TextSize * scale)
				end
			end
		end
		return out
	end

	local TEAM = { "biscuit_bear", "ember_phoenix", "sunbeam_bear" }
	local OWNED = { "biscuit_bear", "ember_phoenix", "sunbeam_bear", "pebble_pup", "honey_bunny" }
	local function snapshot(best, runs)
		local pets, levels, discovered = {}, {}, {}
		for i, id in ipairs(OWNED) do
			pets[id] = 1
			levels[id] = { Level = 4 + i, Xp = 0 }
			discovered[id] = true
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
			Home = { Level = 5, Prestige = 0, Stations = { Garden = 1 }, Garden = {}, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = {}, Hybrids = {},
			PetLevels = levels,
			-- the team's third pet trains: the ring fields the other two
			Teams = { Presets = { TEAM, {}, {} }, Active = 1, Slots = 3 },
			Battle = { Trophies = 120, TrialBest = 2, TrialCleared = { true, true }, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
			PetGrowth = { sunbeam_bear = { Job = { Stat = "Defense", Ends = os.time() + 3600, Rank = 1, Slot = 1, From = "Follow", Paid = 0 } } },
			Ring = { Best = best or 0, Runs = runs or 0 },
		}
	end

	local function ringWindow()
		local gui = pg() and pg():FindFirstChild("NimbusArena")
		return gui and gui:FindFirstChild("Window_Ring") or nil
	end

	S.client_p4ui = guarded("client_p4ui", function()
		bootIfNeeded()
		local AC = (KC and KC.M and KC.M.ArenaController) or moduleAt("client", "Controllers/ArenaController")
		local MC = (KC and KC.M and KC.M.MenuController) or moduleAt("client", "Controllers/MenuController")
		local BC = moduleAt("shared", "BattleCatalog")
		local Config = moduleAt("shared", "Config")
		if not T.check(type(AC) == "table" and type(AC.OpenRing) == "function" and type(AC.RingInfo) == "function" and BC and MC,
			"p4ui ring: ArenaController (OpenRing, RingInfo, StartRing) and BattleCatalog load") then
			return
		end
		AC.Init()
		MC.Init()
		local errors0 = #Mock.Errors
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute("InBattle", nil)
		LocalPlayer:SetAttribute(Config.Attr.SpotIndex, nil)
		toClient("ProfileSync", snapshot(24, 9))
		advance(0.5)

		------------------------------------------------------------ OpenPanel("Ring")
		toClient("OpenPanel", "Ring", {})
		advance(0.8)
		local win = ringWindow()
		if not T.check(win ~= nil and shown(win) and AC.GetState().Window == "Ring", "p4ui ring: OpenPanel('Ring') opens the Champion Ring window") then
			return
		end
		local best = find(win, "Best")
		T.check(best and best.Text == "Best: Round 24", "p4ui ring: the record reads 'Best: Round 24'", best and best.Text)
		local runs = find(win, "Runs")
		T.check(runs and runs.Text:find("9 runs", 1, true) ~= nil, "p4ui ring: ...with the runs", runs and runs.Text)
		local picker = find(win, "Picker")
		local tiles = {}
		for _, c in ipairs(picker and picker:GetChildren() or {}) do
			if c:IsA("TextButton") then
				tiles[#tiles + 1] = c.Name
			end
		end
		table.sort(tiles)
		T.eq(table.concat(tiles, ","), "Start1,Start10,Start20", "p4ui ring: the start picker offers round 1 and the beaten boss rounds 10 and 20 (not 30)")
		T.eq(AC.RingInfo().Start, 20, "p4ui ring: the latest beaten boss round is picked when the window opens")
		local start = find(win, "Start")
		T.check(start and start:IsA("GuiButton") and start.Text == "CONTINUE", "p4ui ring: a boss start reads CONTINUE", start and start.Text)
		local tags = find(win, "Champion")
		T.check(tags and find(tags, "Boss") ~= nil and shown(find(tags, "Boss")), "p4ui ring: round 20's champion carries the BOSS tag")
		local info = AC.RingInfo()
		local reward20 = BC.RingRewards(20, 0, false)
		local nextWin = find(win, "NextWin")
		T.check(nextWin and nextWin.Text:find("+$" .. tostring(reward20.Cash), 1, true) and nextWin.Text:find("+" .. tostring(reward20.Xp) .. " XP", 1, true),
			"p4ui ring: 'Next win: +$X +Y XP' = BattleCatalog.RingRewards(20) (no garden income: the floor)", nextWin and nextWin.Text)
		-- the fighters: the battle team without the training pet
		local fighters = {}
		for _, e in ipairs(info.Fighters or {}) do
			fighters[#fighters + 1] = e.Key
		end
		T.eq(table.concat(fighters, ","), "biscuit_bear,ember_phoenix", "p4ui ring: the fighters are the battle team without the pet in training")
		T.eq(info.Source, "team", "p4ui ring: ...taken from the battle team")
		T.check(find(win, "Fighter1") and find(win, "Fighter2") and not find(win, "Fighter3"), "p4ui ring: one fighter card per fighter")
		-- round 1 picked; a new record pays x3
		Mock.Click(find(picker, "Start1"))
		advance(0.4)
		T.eq(AC.RingInfo().Start, 1, "p4ui ring: tapping the round 1 tile picks it")
		T.check(start.Text == "START", "p4ui ring: round 1 reads START", start.Text)
		-- no home: refused here (the server says the same)
		local why = find(win, "Why")
		T.check(disabled(start) and why and shown(why) and why.Text:find("Claim your home first", 1, true) ~= nil,
			"p4ui ring: without a home START is off: 'Claim your home first'", why and why.Text)
		LocalPlayer:SetAttribute(Config.Attr.SpotIndex, 3)
		advance(0.6)
		T.check(not disabled(start) and not shown(why), "p4ui ring: with a home START is on", why and why.Text)
		-- the board of this server + walking away from the portal
		local arena = workspace:FindFirstChild("BattleArena")
		local madeArena = false
		if not arena then
			arena = Instance.new("Model")
			arena.Name = "BattleArena"
			arena.Parent = workspace
			madeArena = true
		end
		local portal = Instance.new("Model")
		portal.Name = "Portal_Ring"
		local pad = Instance.new("Part")
		pad.Name = "PortalPad"
		pad.Anchored = true
		pad.Size = Vector3.new(14, 0.6, 14)
		pad.CFrame = CFrame.new(4000, 50, 4000)
		pad.Parent = portal
		portal:SetAttribute("RingBoard", "Zed|5;Alex|31;Kim|20;Sam|24")
		portal.Parent = arena
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RingPrompt"
		prompt:SetAttribute("OpenPanel", "Ring")
		prompt.Parent = pad
		AC.Close()
		advance(0.4)
		Mock.Teleport(LocalPlayer, CFrame.new(4000, 54, 4006))
		advance(0.2)
		Mock.Trigger(prompt, LocalPlayer)
		advance(0.8)
		T.check(shown(win) and AC.GetState().Window == "Ring", "p4ui ring: the Champion Ring portal's RingPrompt (OpenPanel 'Ring') opens the window")
		local row1, row3, row4 = find(win, "Row1"), find(win, "Row3"), find(win, "Row4")
		local n1 = row1 and row1:FindFirstChild("Name")
		local r1 = row1 and row1:FindFirstChild("Round")
		local r3 = row3 and row3:FindFirstChild("Round")
		T.check(n1 and n1.Text == "1. Alex" and r1 and r1.Text == "Round 31" and r3 and r3.Text == "Round 20" and row4 == nil,
			"p4ui ring: 'Best in this server' lists the RingBoard's top 3, best first", n1 and n1.Text)
		T.check(not disabled(start), "p4ui ring: at the portal START is on")
		Mock.Teleport(LocalPlayer, CFrame.new(4000, 54, 4040))
		advance(0.6)
		T.check(disabled(start) and why.Text:find("Walk to the Champion Ring portal", 1, true) ~= nil,
			"p4ui ring: 34 studs away START is off: 'Walk to the Champion Ring portal'", why.Text)
		Mock.Teleport(LocalPlayer, CFrame.new(4000, 54, 4006))
		advance(0.6)
		-- START -> BattleRequest("Ring", 1); a refusal toast lands in the footer
		local mark = #Mock.RemoteLog
		Mock.Click(start)
		advance(0.3)
		local sent = lastRequest(mark, "Ring")
		T.check(sent and sent[2] == 1, "p4ui ring: START sends BattleRequest('Ring', 1)", sent and tostring(sent[2]))
		T.check(start.Text == "Starting..." and disabled(start), "p4ui ring: ...and waits for the server ('Starting...')")
		toClient("Notify", "Every ring is busy. Try again soon!", "bad", 3)
		advance(0.4)
		T.check(why and shown(why) and why.Text:find("Every ring is busy", 1, true) ~= nil and start.Text ~= "Starting...",
			"p4ui ring: the server's refusal toast shows in the window's footer", why and why.Text)
		-- my battle starts: the window steps aside
		toClient("BattleState", "Start", { BattleId = "r1", Mode = "Ring", Side = 1, Units = {}, Zone = {}, Ring = { Round = 1, Best = 24, Start = 1 } }, "r1")
		advance(0.4)
		T.check(AC.GetState().Window == nil, "p4ui ring: the ring battle's Start closes the window")
		-- end that battle again so BattleController (and the scenarios after this one) are back in the lobby
		toClient("BattleState", "End", { BattleId = "r1", Mode = "Ring", Outcome = "Lost", Reason = "Forfeit", Round = 1, Rewards = {} }, "r1")
		advance(16)
		toClient("BattleState", "Lobby", { Queue = { Queued = false, Waiting = 0 }, Invites = {} })
		advance(0.4)
		local small = smallTexts(win, 18)
		T.check(#small == 0, "p4ui ring: every text of the ring window is >= 18 design px", table.concat(small, ", "))

		------------------------------------------------------------ the Team screen's ring line
		MC.Open("Team")
		advance(0.8)
		local menu = pg():FindFirstChild("NimbusMenu")
		local team = menu and menu:FindFirstChild("Window_Team")
		local line = team and find(team, "RingRecord")
		T.check(line and line.Text:find("Champion Ring best: Round 24", 1, true) ~= nil, "p4ui team: the Team screen shows 'Champion Ring best: Round 24'",
			line and line.Text)
		MC.Close()
		advance(0.4)

		------------------------------------------------------------ the ring board in the Arena panel's Leaders tab
		AC.OpenArena("Leaderboard")
		advance(0.8)
		local arenaWin = pg():FindFirstChild("NimbusArena") and pg():FindFirstChild("NimbusArena"):FindFirstChild("Window_Arena")
		local ringBox = arenaWin and find(arenaWin, "RingBoard")
		local lead1 = ringBox and ringBox:FindFirstChild("Row1")
		local leadMine = ringBox and ringBox:FindFirstChild("Mine")
		T.check(ringBox and shown(ringBox) and lead1 and lead1.Text == "1. Alex: Round 31" and ringBox:FindFirstChild("Row4") == nil,
			"p4ui leaders: the Leaders tab shows the Champion Ring's best of this server (top 3)", lead1 and lead1.Text)
		T.check(leadMine and leadMine.Text:find("Your best: Round 24", 1, true) ~= nil, "p4ui leaders: ...and the player's own ring record",
			leadMine and leadMine.Text)
		AC.Close()
		advance(0.4)

		------------------------------------------------------------ the safe-zone toast (contract 3.11)
		local floor = Instance.new("Part")
		floor.Name = "TestFloor"
		floor.Anchored = true
		floor.Size = Vector3.new(120, 4, 120)
		floor.CFrame = CFrame.new(4000, 48, 4000)
		floor.Parent = arena
		local hint = find(pg():FindFirstChild("NimbusArena"), "Hint")
		local hintText = hint and hint:FindFirstChild("Text")
		Mock.Teleport(LocalPlayer, CFrame.new(4000, 54, 4000))
		advance(7)
		Mock.Teleport(LocalPlayer, CFrame.new(4400, 54, 4400))
		advance(0.6)
		T.check(hint and shown(hint) and hintText and hintText.Text:find("Safe zone", 1, true) ~= nil,
			"p4ui zone: leaving the Battle Arena shows the 'Safe zone' side toast", hintText and hintText.Text)
		Mock.Teleport(LocalPlayer, CFrame.new(4000, 54, 4000))
		advance(0.6)
		T.check(hint and shown(hint) and hintText and hintText.Text:find("Battle Arena: pets can battle here", 1, true) ~= nil,
			"p4ui zone: walking back in shows 'Battle Arena: pets can battle here'", hintText and hintText.Text)
		local box = hint and Mock.GuiBox(hint)
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		T.check(box and vp and box.x > vp.X / 2, "p4ui zone: the toast sits on the right side, never in the screen centre",
			box and string.format("x=%.0f of %.0f", box.x, vp and vp.X or 0))
		LocalPlayer:SetAttribute("InBattle", "zone-test")
		advance(0.4)
		Mock.Teleport(LocalPlayer, CFrame.new(4400, 54, 4400))
		LocalPlayer:SetAttribute("InBattle", nil)
		hint.Visible = false
		advance(0.6)
		T.check(not shown(hint), "p4ui zone: no zone toast right after a battle's teleport")

		portal:Destroy()
		floor:Destroy()
		if madeArena then
			arena:Destroy()
		end
		LocalPlayer:SetAttribute(Config.Attr.SpotIndex, nil)
		local mine = 0
		for i = errors0 + 1, #Mock.Errors do
			local msg = tostring(Mock.Errors[i].msg)
			if msg:find("ArenaController", 1, true) or msg:find("TutorialController", 1, true) then
				mine = mine + 1
			end
		end
		T.eq(mine, 0, "p4ui ring: no script errors from ArenaController")
	end)

	S.client_p4ui_mobile = guarded("client_p4ui_mobile", function()
		bootIfNeeded()
		local AC = moduleAt("client", "Controllers/ArenaController")
		if not T.check(type(AC) == "table" and type(AC.OpenRing) == "function", "p4ui phone: ArenaController loads") then
			return
		end
		AC.Init()
		toClient("ProfileSync", snapshot(24, 9))
		advance(0.4)
		for _, size in ipairs({ { 390, 844 }, { 844, 390 } }) do
			Mock.SetViewport(size[1], size[2])
			advance(0.4)
			AC.OpenRing(nil)
			advance(0.8)
			local win = ringWindow()
			local small = smallOnScreen(win, 14)
			local label = string.format("p4ui phone %dx%d", size[1], size[2])
			T.check(win ~= nil and shown(win) and #small == 0, label .. ": every text of the ring window is >= 14 px on screen", table.concat(small, ", "))
			local panel = win and find(win, "RingPanel")
			local box = panel and Mock.GuiBox(panel)
			T.check(box and box.x >= -1 and box.x + box.w <= size[1] + 1, label .. ": the ring window stays on the screen",
				box and string.format("x=%.0f w=%.0f", box.x, box.w))
			local start = win and find(win, "Start")
			local sbox = start and Mock.GuiBox(start)
			T.check(sbox and sbox.y + sbox.h <= size[2] + 1 and sbox.x + sbox.w <= size[1] + 1, label .. ": START is on the screen")
			if size[1] > size[2] then
				-- landscape: the footer keeps clear of Roblox's jump button (bottom right, about 90 px wide)
				T.check(sbox and sbox.x + sbox.w <= size[1] - 90, label .. ": START stays left of the touch jump button",
					sbox and string.format("right=%.0f", sbox.x + sbox.w))
			end
			AC.Close()
			advance(0.4)
		end
	end)

	return S
end

if CONTEXT == "client" then
	return clientScenarios()
end
return serverScenarios()
