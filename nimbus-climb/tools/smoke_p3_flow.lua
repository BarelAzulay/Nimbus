-- smoke_p3_flow.lua: the END-TO-END Phase 3 flow (ARCHITECTURE_V3.md "Phase 3: Pet battles", the "Phase 3 build
-- contract" and its "Interfaces between the Phase 3 modules"): up to eight simulated players play the pet battles
-- together on the booted game through the same doors a client uses (the BattleRequest / BattleCommand / DevCommand
-- remotes, standing in the arena / at the Trial Portal) while BattleService, EventService, ArenaBuilder, DataService,
-- PetCareService, TutorialService, DevService and PetService all run at once. Everything a client would see
-- (BattleState, ArenaState, TutorialState, ProfileSync, Notify) is read back from the remote log, so the payload shapes
-- the modules hand each other are checked where they meet. The pets the players own are written into their profiles
-- (a stand-in for many roulette spins); everything after that goes through the game.
-- Loaded by tools/smoke.py in BOTH worlds (ARGS.context picks the half). In the server world the scenarios are chapters
-- of ONE story and run in order (before the Phase 2 care block: the raid advances the clock by minutes):
--   p3flow_arrive   the schedule is cleared (the next Boss Raid ~20 minutes away); the interfaces the modules hand each
--                   other are all there (signals at module load, APIs, BattleSim constants, the BattleCatalog helpers the
--                   UI uses, ArenaInfo); Ava and Bo (new players) and Cy (a Phase 2 save: Prestige 1, a pet in his
--                   Garden, the home chapter of the tutorial finished, no Teams / Battle) join: ArenaState on join (the
--                   contract shape), ProfileSync Teams { Presets, Active, Slots } + Battle, Cy's migrated profile (3
--                   empty presets, Slots 4 from his prestige, a zeroed record, the Phase 2 data intact) and his tutorial
--                   resuming at chapter 3 ("arena", the arrow at the forum). Teams through BattleRequest: the 4th slot
--                   refused before Prestige 1 (a side toast, nothing stored), a duplicate and a pet not owned refused,
--                   then 3 pets saved (toast, TeamsChanged once, ProfileSync); Bo keeps a second preset. Cy claims his
--                   home (E at a free gate: his Phase 2 build comes back), buys the Arena Gate on its pad (a "Coming
--                   soon" pad in Phase 2) and walks through it to the arena ("arena" -> "team", the Team tile rings);
--                   his Garden pet is refused, four pets are accepted (slot 4 at Prestige 1) -> "trial" (the arrow at
--                   the Trial Portal)
--   p3flow_trials   Ava at the Trial Portal: away from it refused, Trial 2 locked, Trials 1, 2, 3 won through the remote
--                   (the pocket teleport, InBattle, "Start" with her preset's keys in slots 1-3, her Attack orders reach
--                   the sim, the end, the return): first-clear tokens paid once, pet XP to every team pet (the exact
--                   total), the record + ProfileSync; a repeat clear pays the repeat amount only. Bo selects his one-pet
--                   preset (TeamSelect) and LOSES Trial 1 (nothing paid, nothing cleared, no XP), then wins it with his
--                   main team. Cy wins Trial 1 with four pets inside the tutorial (no arrow while fighting) -> "raid"
--                   (the arrow at the colosseum floor, a hint counting down to the next raid). Cy puts a team pet into
--                   his Gym (PetCare GymSet): it leaves his battle team (pruned, TeamsChanged, ProfileSync) and cannot
--                   rejoin it while it trains
--   p3flow_duels    Ava challenges Bo through the remote ("Lobby": Invites / Sent), Bo accepts: a duel on a ring with
--                   Hal watching nearby (a spectator 'Start' / 'End'); the end pays trophies / tokens / XP / PvP counters
--                   once and the leaderboard (ArenaState + the trophy board in the arena) shows the winner. Dee and Eli
--                   use the quick queue: paired at once; Dee forfeits after 16 s (Eli: a full win, Dee: the forfeit
--                   penalty, never below 0 trophies); queued again, Eli disconnects mid-duel: Dee wins, Eli's loss is in
--                   his save
--   p3flow_reset    the developer /reset (DevCommand) is refused while Bo fights a trial, works after it: his teams,
--                   battle record and pets are gone (ProfileSync, the leaderboard at 0, Trial 1 refused without a
--                   team, Trial 2 locked again) and the reset survives the next autosave; Bo builds a new team
--   p3flow_raid     Eli rejoins with the loss of the duel he left. Double Rewards (the developer start: toast,
--                   ArenaState.Double, a trial pays x2); then the scheduled Boss Raid from its announcement: the toast
--                   naming the boss + the countdown in ArenaState (every second), the 30 s reminder, the opening toast,
--                   ArenaState.Raid; Cy standing in the arena finishes the battle chapter of the tutorial (its reward
--                   once). Six teams join through the remote (Cy with his team as it is now), Hal watches from the
--                   stands, Gus leaves early (LeaveRaid: the boss sheds his share, no reward, no rejoin), Eli
--                   disconnects mid-raid (a Leave event, no reward, nothing in his save), Fay joins late (the boss HP
--                   grows, the others see her units Spawn), Hal is too late. The fighters attack, cast specials and
--                   retreat from telegraphs until the boss falls: each fighter gets the tier of their damage share with
--                   Double Rewards tokens, its gems and (the chances forced to 1 for this raid) an event pet they did not
--                   have (owned, discovered, in Battle.EventPets, the shout-out to the others), pet XP, Raids + 1;
--                   BattleEnded once, nothing paid twice (EventService's fallback payer stays quiet), the everyone-toast,
--                   EventService's LastRaid and the next raid ~20 minutes away; Double Rewards end
--   p3flow_rejoin   Ava leaves (the save: Teams + Battle in the stored encoding) and rejoins: teams, record, pet levels
--                   and her event pet are back, Trial 4 is open (and forfeited), the leaderboard has her again; Eli
--                   rejoins after his raid disconnect (no raid in his record, no raid to rejoin); Cy rejoins: his
--                   finished tutorial pays nothing again, his team and his Gym pet are kept
--   p3flow_solo     Roblox Studio Play Solo: everybody else leaves; Ava starts a Boss Raid with the DEV button
--                   (DevCommand raid), joins it alone (a raid for one team), fights it and gets the tier of all the damage,
--                   paid once; then she waits for the SCHEDULED Double Rewards hour: announced ~2 minutes ahead, it
--                   starts by itself (EventService, BattleService, the Workspace attribute), a trial pays x2, the next
--                   one is EveryMinutes away; no battle, raid or Double Rewards of the flow is left behind
--   client_p3flow   (client) the real server messages of the flow, replayed into the client as Ava: BattleController
--                   draws her first trial (HUD with her three pets, the VICTORY card with the tokens the server paid),
--                   ArenaController shows the challenge she sent and the raid countdown chip, the raid with its boss
--                   model, the raid result card (tier, tokens, event pet, Double rewards); State mirrors her saved teams
--                   and record; Cy's real chapter-3 TutorialState messages walk the card through arena > team > trial >
--                   raid with the world guide on the arena targets; no client errors
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

-- the flow's players (fixed user ids: the client half finds their traffic in the replication log by these)
local IDS = { Ava = 994101, Bo = 994102, Cy = 994103, Dee = 994104, Eli = 994105, Fay = 994106, Gus = 994107, Hal = 994108 }

local S = {}

if CONTEXT ~= "server" then
	------------------------------------------------------------------------------------------------
	-- client world: the flow's real server messages, replayed into the client as Ava (and Cy's tutorial)
	------------------------------------------------------------------------------------------------
	S.client_p3flow = guarded("client_p3flow", function()
		local KC = _G.KC
		if not T.check(type(KC) == "table" and type(KC.toClient) == "function", "client flow: (precondition) the client kit is loaded") then
			return
		end
		if REPLICATION == nil then
			T.warn("client flow: no server replication log (the server flow did not run)")
			return
		end
		local advance = KC.advance
		local Config, _, Theme = KC.env()
		local LocalPlayer = game:GetService("Players").LocalPlayer
		local me = LocalPlayer.UserId
		local function moduleAt(top, rest)
			local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
			if not inst then
				return nil
			end
			local ok, result = pcall(require, inst)
			return ok and type(result) == "table" and result or nil
		end
		local BCtl = moduleAt("client", "Controllers/BattleController")
		local ACtl = moduleAt("client", "Controllers/ArenaController")
		local TCtl = moduleAt("client", "Controllers/TutorialController")
		local State = moduleAt("client", "State")
		if not T.check(BCtl and ACtl and TCtl and State and type(BCtl.GetBattle) == "function" and type(ACtl.GetState) == "function",
			"client flow: (precondition) BattleController, ArenaController, TutorialController and State load") then
			return
		end
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local function shown(obj)
			local cur = obj
			if not cur then
				return false
			end
			while cur and cur ~= game do
				if cur:IsA("LayerCollector") then
					return cur.Enabled ~= false
				elseif cur:IsA("GuiObject") and not cur.Visible then
					return false
				end
				cur = cur.Parent
			end
			return true
		end
		local function at(root, path)
			local cur = root
			for name in string.gmatch(path, "[^%.]+") do
				if not cur then
					return nil
				end
				cur = cur:FindFirstChild(name)
			end
			return cur
		end
		local function hasText(root, needle)
			for _, d in ipairs(root and root:GetDescendants() or {}) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and shown(d) and tostring(d.Text):gsub("<[^>]*>", ""):find(needle, 1, true) then
					return true
				end
			end
			return false
		end
		local function battleGui()
			return pg and pg:FindFirstChild("NimbusBattle")
		end
		local function sideStack()
			local side = pg and pg:FindFirstChild("NimbusArenaSide")
			return side and side:FindFirstChild("SideStack", true)
		end
		local errors0 = #Mock.Errors
		Mock.SetViewport(1920, 1080)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute("InBattle", nil)

		-- the flow's window in the log: Ava's first join .. her first leave
		local AVA = IDS.Ava
		local i0, i1 = nil, nil
		for i = 1, #REPLICATION do
			local e = REPLICATION[i]
			if e.userId == AVA and e.kind == "join" and not i0 then
				i0 = i
			elseif e.userId == AVA and e.kind == "leave" and i0 and not i1 then
				i1 = i
			end
		end
		if not T.check(i0 ~= nil and i1 ~= nil, "client flow: (precondition) Ava's traffic is in the replication log (the server flow ran)") then
			return
		end
		local flowIds = {}
		for _, id in pairs(IDS) do
			flowIds[id] = true
		end
		local pattern = "%f[%d]" .. AVA .. "%f[%D]"
		local entries, cyStates = {}, {}
		for i = i0 + 1, i1 - 1 do
			local e = REPLICATION[i]
			local pick = false
			if e.kind == "remote" then
				pick = e.target == "all" or e.userId == AVA
				if e.remote == "TutorialState" and e.userId == IDS.Cy then
					cyStates[#cyStates + 1] = e
				end
			elseif e.kind == "attr" or e.kind == "health" then
				pick = e.userId == AVA
			elseif e.kind == "join" or e.kind == "leave" then
				pick = flowIds[e.userId] == true and e.userId ~= AVA
			end
			if pick then
				local copy = {}
				for k, v in pairs(e) do
					copy[k] = v
				end
				if copy.userId == AVA then
					copy.userId = me
				end
				if type(copy.args) == "string" then
					copy.args = (copy.args:gsub(pattern, tostring(me)))
				end
				if type(copy.value) == "string" then
					copy.value = (copy.value:gsub(pattern, tostring(me)))
				end
				entries[#entries + 1] = copy
			end
		end
		T.info("*client flow: replaying " .. #entries .. " messages of the flow as Ava")

		-- what the client shows at the interesting moments of the story
		local seen = { snaps = 0 }
		local trialId, raidId, raidBoss = nil, nil, nil
		local function bossUnitOf(payload)
			for _, u in ipairs(payload.Units or {}) do
				if u.kind == "Boss" then
					return u.id
				end
			end
			return nil
		end
		Mock.RunReplay(entries, nil, function(e)
			if e.kind ~= "remote" then
				return
			end
			if e.remote == "BattleState" then
				local args = Mock.Deserialize(e.args)
				local kind, payload = args[1], args[2]
				if type(payload) ~= "table" then
					return
				end
				if kind == "Start" and payload.Mode == "Trial" and type(payload.Trial) == "table" and payload.Trial.Level == 2 and not trialId then
					trialId = payload.BattleId -- Trial 2: Trial 1 (one handicapped pet) is over in a few snapshots
				elseif kind == "Snapshot" and payload.BattleId == trialId and not seen.trialHud then
					seen.snaps = seen.snaps + 1
					if seen.snaps == 12 then
						advance(0.3)
						local b = BCtl.GetBattle()
						local rows = 0
						for slot = 1, 4 do
							if shown(at(battleGui(), "Root.Team.Row" .. slot)) then
								rows = rows + 1
							end
						end
						seen.trialHud = {
							ok = b ~= nil and b.Id == trialId and b.Mode == "Trial" and b.Fighter == true and b.Spectator ~= true and BCtl.IsHudVisible(),
							rows = rows,
							top = hasText(at(battleGui(), "Root.TopCard"), "TRIAL 2"),
							models = b and b.Models or 0,
							units = b and b.Units or 0,
						}
					end
				elseif kind == "End" and payload.BattleId == trialId and not seen.trialEnd then
					advance(1.2)
					local card = at(battleGui(), "Root.ResultCard")
					local rw = payload.Rewards or {}
					seen.trialEnd = {
						ok = shown(card) and hasText(card, "VICTORY") and hasText(card, "+" .. Theme.ShortNumber(rw.Tokens or 0) .. " Tokens")
							and hasText(card, "First clear"),
						tokens = rw.Tokens,
					}
				elseif kind == "Lobby" and type(payload.Sent) == "table" and not seen.sent then
					advance(0.6)
					local st = ACtl.GetState()
					local stack = sideStack()
					local card = stack and stack:FindFirstChild("Sent")
					seen.sent = st and st.Lobby and st.Lobby.Sent and st.Lobby.Sent.ToUserId == IDS.Bo and shown(card) and hasText(card, "Bo")
				elseif kind == "Start" and payload.Mode == "Raid" and not raidId then
					raidId = payload.BattleId
					raidBoss = bossUnitOf(payload)
					advance(1.5)
					local b = BCtl.GetBattle()
					local boss = raidBoss and BCtl.GetUnit(raidBoss)
					seen.raidStart = b ~= nil and b.Id == raidId and b.Mode == "Raid" and b.Fighter == true and BCtl.IsHudVisible() and boss ~= nil and boss.Model ~= nil
				elseif kind == "End" and payload.BattleId == raidId and not seen.raidEnd and payload.Rewards then
					advance(1.2)
					local card = at(battleGui(), "Root.ResultCard")
					local rw = payload.Rewards
					seen.raidEnd = shown(card) and hasText(card, "BOSS DEFEATED") and hasText(card, tostring(rw.Tier) .. " tier")
						and hasText(card, "+" .. Theme.ShortNumber(rw.Tokens or 0) .. " Tokens") and (rw.EventPet == nil or hasText(card, "New pet:"))
						and (rw.Double ~= true or hasText(card, "Double rewards"))
				end
			elseif e.remote == "ArenaState" and not seen.countdown then
				local args = Mock.Deserialize(e.args)
				local st = args[1]
				if type(st) == "table" and type(st.Next) == "table" and st.Next.Kind == "BossRaid" and st.Next.Announced == true and LocalPlayer:GetAttribute("InBattle") == nil then
					advance(0.6)
					local stack = sideStack()
					local chip = stack and stack:FindFirstChild("Countdown")
					local clock = nil
					for _, d in ipairs(chip and chip:GetDescendants() or {}) do
						if d.Name == "Clock" then
							clock = d
						end
					end
					local stA = ACtl.GetState()
					seen.countdown = {
						ok = stA and stA.Arena and stA.Arena.Next and stA.Arena.Next.Kind == "BossRaid" and shown(chip) and clock ~= nil and tostring(clock.Text):match("^%d+:%d%d$") ~= nil,
						text = clock and clock.Text,
					}
				end
			end
		end, 0.25)
		local th = seen.trialHud
		T.check(th ~= nil and th.ok and th.rows == 3 and th.top, "client flow: Ava's real Trial 2 messages: BattleController draws her as a fighter (HUD: TRIAL 2, one row per pet)",
			th and ("rows " .. th.rows .. " top " .. tostring(th.top)) or "never reached")
		T.check(th ~= nil and th.models == th.units and th.units >= 6, "client flow: ...every unit of the real 'Start' has a model", th and (th.models .. "/" .. th.units) or "")
		T.check(seen.trialEnd ~= nil and seen.trialEnd.ok, "client flow: ...the real 'End' shows VICTORY with the tokens the server paid and First clear",
			seen.trialEnd and tostring(seen.trialEnd.tokens) or "never reached")
		T.check(seen.sent == true, "client flow: the real 'Lobby' of her challenge: ArenaController keeps it and shows the Sent card (waiting for Bo)")
		T.check(seen.countdown ~= nil and seen.countdown.ok, "client flow: the real raid countdown (ArenaState.Next): the side countdown chip ticks",
			seen.countdown and tostring(seen.countdown.text) or "never reached")
		T.check(seen.raidStart == true, "client flow: the real raid 'Start': the raid is drawn with its boss model and her HUD")
		T.check(seen.raidEnd == true, "client flow: the real raid 'End': BOSS DEFEATED with her tier, tokens, the event pet and Double rewards")
		-- what State mirrored from the real ProfileSync messages
		local teams = State.Teams and State.Teams()
		local battle = State.Battle and State.Battle()
		T.check(teams and teams.Presets and #teams.Presets[1] == 3 and teams.Presets[1][1] == "cloudy_dragon" and teams.Slots == 3,
			"client flow: State.Teams() mirrors her saved preset (3 slots before Prestige 1)")
		T.check(battle and battle.TrialCleared and battle.TrialCleared[1] == true and battle.TrialCleared[3] == true and (battle.Raids or 0) >= 1 and (battle.Trophies or 0) >= 0,
			"client flow: State.Battle() mirrors her record (TrialCleared 1-3, a raid)")
		advance(12)
		T.check(BCtl.GetBattle() == nil and not BCtl.IsHudVisible(), "client flow: after the replay no battle is left on the client")

		-- Cy's real chapter-3 tutorial states: the card follows arena -> team -> trial -> raid -> done
		local ids = {}
		local guided = {}
		for _, e in ipairs(cyStates) do
			local args = Mock.Deserialize(e.args)
			local st = args[1]
			if type(st) == "table" then
				KC.toClient("TutorialState", st)
				advance(0.8)
				local now = TCtl.GetState and TCtl.GetState()
				if now and now.Id and ids[#ids] ~= now.Id then
					ids[#ids + 1] = st.Done and "done" or now.Id
				end
				if st.Target and st.Target.Kind == "Spot" and typeof(st.Target.Position) == "Vector3" and not st.Done then
					local fx = workspace:FindFirstChild("ClientFx")
					guided[st.Id] = fx ~= nil and fx:FindFirstChild("GuideSign", true) ~= nil
				end
			end
		end
		-- leave the client as the scenarios after this one expect it: the card hidden (a Done state without the finale), no
		-- event countdown ticking at the right edge, no duel status
		local lastCy = cyStates[#cyStates] and Mock.Deserialize(cyStates[#cyStates].args)[1]
		if type(lastCy) == "table" then
			lastCy.Done, lastCy.Completed = true, false
			KC.toClient("TutorialState", lastCy)
		end
		KC.toClient("ArenaState", { Leaderboard = {}, Next = { Kind = "BossRaid", BossId = "storm_titan", Name = "Storm Titan", StartsIn = 1200, Announced = false } })
		KC.toClient("BattleState", "Lobby", { Queue = { Queued = false, Waiting = 0 }, Invites = {} })
		local order = table.concat(ids, ">")
		T.check(order:find("arena>team>trial>raid", 1, true) ~= nil, "client flow: Cy's real TutorialState messages walk the card through arena > team > trial > raid", order)
		T.check(guided.arena == true and guided.trial == true and guided.raid == true, "client flow: ...the world guide points at the arena targets the server resolved (forum, Trial Portal, floor)",
			tostring(guided.arena) .. " " .. tostring(guided.trial) .. " " .. tostring(guided.raid))
		advance(8)
		T.eq(#Mock.Errors - errors0, 0, "client flow: no client script errors")
		if KC.flushErrors then
			KC.flushErrors("client_p3flow")
		end
	end)
	return S
end

local K = _G.K
local advance, config, mod, waitFor = K.advance, K.config, K.mod, K.waitFor
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

-- the story's shared state (the scenarios are chapters of one flow)
local F = {
	p = {}, -- name -> Player
	facts = {}, -- what later chapters need
}

local TEAMS = {
	Ava = { "cloudy_dragon", "ember_phoenix", "aurora_fox" },
	AvaExtra = "moonlit_owl", -- her 4th pet (slot 4 is refused before Prestige 1)
	Bo = { "twilight_dragon", "moonlit_owl", "candy_unicorn" },
	BoWeak = "pebble_pup",
	BoNew = { "sunbeam_bear", "starlight_unicorn", "nebula_axolotl" }, -- after the reset
	Cy = { "starlight_unicorn", "sunbeam_bear", "nebula_axolotl", "storm_tabby" },
	CyGarden = "honey_bunny", -- his only copy works in the Garden
	Dee = { "maple_fox", "bamboo_panda", "sleepy_owl" },
	Eli = { "waffle_corgi", "mochi_slime", "bubble_axolotl" },
	Fay = { "sunbeam_bear", "ember_phoenix", "twilight_dragon" },
	Gus = { "aurora_fox", "moonlit_owl", "nebula_axolotl" },
	Hal = { "biscuit_bear" },
}

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
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

local function BS()
	return req("server/Services/BattleService")
end
local function ES()
	return req("server/Services/EventService")
end
local function DS()
	return req("server/Services/DataService")
end
local function AB()
	return req("server/Services/ArenaBuilder")
end
local function TSv()
	return req("server/Services/TutorialService")
end
local function BC()
	return req("shared/BattleCatalog")
end
local function TC()
	return req("shared/TycoonCatalog")
end
local function Steps()
	return req("shared/TutorialSteps")
end
local function PC()
	return req("shared/PetCatalog")
end

local function arenaInfo()
	local ab = AB()
	return ab and ab.GetInfo and ab.GetInfo() or nil
end

local function remote(name)
	local folder = K.remoteFolder()
	return folder and folder:FindFirstChild(name)
end

local function request(p, action, a, b)
	Mock.FromClient(remote("BattleRequest"), p, action, a, b)
	advance(0.1)
end

local function command(p, action, a)
	Mock.FromClient(remote("BattleCommand"), p, action, a)
end

local function devCommand(p, name, arg)
	Mock.FromClient(remote("DevCommand"), p, name, arg)
	advance(0.2)
end

local function storeKey(userId)
	return config().Tokens.DataStoreName .. "/u_" .. userId
end

local function stored(userId)
	return Mock.DataStore.Data[storeKey(userId)]
end

local function contains(list, value)
	for _, v in ipairs(type(list) == "table" and list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

local function count(map)
	local n = 0
	for _, v in pairs(type(map) == "table" and map or {}) do
		if v then
			n = n + 1
		end
	end
	return n
end

local function listText(list)
	local out = {}
	for i, v in ipairs(type(list) == "table" and list or {}) do
		out[i] = tostring(v)
	end
	return "{" .. table.concat(out, ",") .. "}"
end

local function sameList(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- a stable text of a plain table (keys sorted), for "the same after the rejoin" checks
local function plain(value, depth)
	depth = depth or 0
	if type(value) ~= "table" then
		return tostring(value)
	end
	if depth > 6 then
		return "{...}"
	end
	local keys = {}
	for k in pairs(value) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(x, y)
		return tostring(x) < tostring(y)
	end)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = tostring(k) .. "=" .. plain(value[k], depth + 1)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function tokens(p)
	return DS().GetTokens(p)
end

local function gems(p)
	return DS().GetGems(p)
end

local function record(p)
	return DS().GetBattle(p) or {}
end

-- every Notify toast to p since `mark`
local function toasts(p, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		out[#out + 1] = tostring(e.args[1])
	end
	return out
end

local function toasted(p, needle, mark)
	for _, text in ipairs(toasts(p, mark)) do
		if text:find(needle, 1, true) then
			return true, text
		end
	end
	return false, table.concat(toasts(p, mark), " | ")
end

-- BattleState messages to p since `mark` (optionally of one kind)
local function battleMsgs(p, mark, kind)
	local out = {}
	local log = Mock.RemoteLog
	for i = (mark or 0) + 1, #log do
		local e = log[i]
		if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and (kind == nil or e.args[1] == kind) then
			out[#out + 1] = e
		end
	end
	return out
end

local function lastMsg(p, kind, mark)
	local list = battleMsgs(p, mark, kind)
	local e = list[#list]
	return e and e.args[2] or nil
end

-- battle events of one type that reached p since `mark`
local function eventsOf(p, mark, evType)
	local out = {}
	for _, e in ipairs(battleMsgs(p, mark, "Events")) do
		for _, ev in ipairs(type(e.args[2]) == "table" and e.args[2] or {}) do
			if evType == nil or ev.type == evType then
				out[#out + 1] = ev
			end
		end
	end
	return out
end

local function arenaStates(p, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("ArenaState", p.UserId, mark or 0)) do
		out[#out + 1] = e.args[1]
	end
	return out
end

local function lastArenaState(p, mark)
	local list = arenaStates(p, mark)
	return list[#list]
end

local function lastSync(p, mark)
	local list = K.remotesFor("ProfileSync", p.UserId, mark or 0)
	local e = list[#list]
	return e and e.args[1] or nil
end

local function tutorialStates(p, mark)
	local out = {}
	for _, e in ipairs(K.remotesFor("TutorialState", p.UserId, mark or 0)) do
		out[#out + 1] = e.args[1]
	end
	return out
end

local function tutorial(p)
	local ts = TSv()
	return ts and ts.GetState and ts.GetState(p) or nil
end

local function stepId(p)
	local st = tutorial(p)
	if not st then
		return nil
	end
	if st.Done then
		return "done!"
	end
	return st.Id
end

-- the total XP a pet copy holds (levels converted back to XP with the tycoon curve)
local function totalXp(p, key)
	local level, xp = DS().GetPetLevel(p, key)
	local tc = TC()
	local total = 0
	for l = 1, (tonumber(level) or 1) - 1 do
		total = total + ((tc and tc.XpToNext and tc.XpToNext(l)) or 0)
	end
	return total + (tonumber(xp) or 0)
end

local function xpOf(p, keys)
	local out = {}
	for _, key in ipairs(keys) do
		out[key] = totalXp(p, key)
	end
	return out
end

-- every key gained exactly `xp` since `before` (returns ok, detail)
local function gainedXp(p, before, xp)
	local bad = {}
	for key, total in pairs(before) do
		local now = totalXp(p, key)
		if now - total ~= xp then
			bad[#bad + 1] = key .. " +" .. tostring(now - total)
		end
	end
	return #bad == 0, table.concat(bad, ", ")
end

-- the token multiplier a reward record was paid with (Double Rewards may run: the scheduled hour, or ours)
local function doubled(rw)
	if type(rw) == "table" and rw.Double == true then
		local events = BC() and BC().Events
		return (events and tonumber(events.DoubleRewardsMultiplier)) or 2
	end
	return 1
end

-- what Roblox's remote serialization would mangle in a payload: functions / threads, NaN / inf numbers, sparse arrays,
-- mixed tables and dictionaries keyed by something else than strings (paths of the bad values)
local function remoteUnsafe(value, path, out, depth)
	local kind = typeof(value)
	if kind == "function" or kind == "thread" or kind == "userdata" then
		out[#out + 1] = path .. " (" .. kind .. ")"
		return out
	end
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			out[#out + 1] = path .. " (nan / inf)"
		end
		return out
	end
	if kind ~= "table" or depth > 16 then
		return out
	end
	local numeric, strings, other, top = 0, 0, 0, 0
	for k in pairs(value) do
		if type(k) == "number" then
			numeric = numeric + 1
			if k > top then
				top = k
			end
		elseif type(k) == "string" then
			strings = strings + 1
		else
			other = other + 1
		end
	end
	if other > 0 then
		out[#out + 1] = path .. " (a key that is not a string or an index)"
	elseif numeric > 0 and strings > 0 then
		out[#out + 1] = path .. " (mixed table)"
	elseif numeric > 0 and top ~= numeric then
		out[#out + 1] = path .. " (sparse array)"
	end
	for k, v in pairs(value) do
		if #out < 40 then
			remoteUnsafe(v, path .. "." .. tostring(k), out, depth + 1)
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- players, places
----------------------------------------------------------------------------------------------------
local function join(name)
	local p = Mock.AddPlayer(name, IDS[name])
	F.p[name] = p
	waitFor(function()
		return DS().GetProfile(p) ~= nil
	end, 5)
	advance(0.8)
	return p
end

local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	advance(0.8)
end

-- pets the player owns (written into the profile like many roulette spins would), at `level`
local function grant(p, pets, level)
	local data = DS()
	local prof = data.GetProfile(p)
	if not prof then
		return false
	end
	for _, id in ipairs(pets) do
		prof.Pets[id] = (prof.Pets[id] or 0) + 1
		if level and level > 1 then
			prof.PetLevels[id] = { Level = level, Xp = 0 }
		end
		data.MarkDiscovered(p, id)
	end
	data.MarkDirty(p)
	data.Sync(p)
	return true
end

local function toPortal(p)
	local info = arenaInfo()
	Mock.Teleport(p, CFrame.new(info.TrialPortal.Position + Vector3.new(0, 3, 6)))
	advance(0.1)
end

local function toArena(p, dx, dz)
	local info = arenaInfo()
	Mock.Teleport(p, info.Spawn * CFrame.new(dx or 0, 3, dz or 0))
	advance(0.1)
end

local function toLobby(p, dx)
	Mock.Teleport(p, CFrame.new(config().Lobby.Origin + Vector3.new(10 + (dx or 0), 4, 10)))
	advance(0.1)
end

local function inArena(p)
	local root = K.root(p)
	return root ~= nil and AB().InArena(root.Position) == true
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

-- walks to the first free gate and presses E on its ClaimPrompt -> the plot index, or nil
local function claimFree(p)
	local SS = mod("SpotService")
	for i = 1, config().Lobby.SpotCount do
		if spots()[i] and not SS.GetOwner(i) then
			local gate = SS.GateCFrame(spots()[i])
			if gate then
				Mock.Teleport(p, gate * CFrame.new(0, 3, -5))
			end
			local prompt = claimPromptOf(i)
			if prompt then
				Mock.Trigger(prompt, p)
			end
			advance(0.8)
			if SS.GetOwner(i) == p then
				return i
			end
		end
	end
	return nil
end

-- a prompt on a plot: the BuyPrompt of a station's pad (StationId up the chain) or a prompt by name
local function plotPrompt(index, name, stationId)
	local info = spots()[index]
	if not info or not info.Folder then
		return nil
	end
	for _, d in ipairs(info.Folder:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == name then
			local node, sid = d, nil
			for _ = 1, 8 do
				if typeof(node) ~= "Instance" or node == workspace then
					break
				end
				sid = node:GetAttribute("StationId")
				if sid ~= nil then
					break
				end
				node = node.Parent
			end
			if stationId == nil or sid == stationId then
				return d
			end
		end
	end
	return nil
end

local function promptPosition(prompt)
	local parent = prompt and prompt.Parent
	if typeof(parent) ~= "Instance" then
		return nil
	end
	if parent:IsA("BasePart") then
		return parent.Position
	elseif parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

-- walks up to a prompt and presses E
local function pressPrompt(p, prompt)
	if not prompt then
		return false
	end
	local at = promptPosition(prompt)
	if at then
		Mock.Teleport(p, CFrame.new(at + Vector3.new(0, 2, 0)))
	end
	advance(0.1)
	Mock.Trigger(prompt, p)
	advance(0.4)
	return true
end

local function near(a, b, d)
	return typeof(a) == "Vector3" and typeof(b) == "Vector3" and (a - b).Magnitude <= (d or 1)
end

local function planarFrom(p, cf)
	local pos = K.root(p).Position
	return math.sqrt((pos.X - cf.Position.X) ^ 2 + (pos.Z - cf.Position.Z) ^ 2)
end

----------------------------------------------------------------------------------------------------
-- BattleEnded (one watcher for the whole story) + the replication filter
----------------------------------------------------------------------------------------------------
local function watcher()
	if F.w then
		return F.w
	end
	local list = {}
	local conn = BS().BattleEnded:Connect(function(id, result)
		list[#list + 1] = { id = id, result = result }
	end)
	F.w = {
		list = list,
		find = function(id)
			for _, e in ipairs(list) do
				if e.id == id then
					return e.result
				end
			end
			return nil
		end,
		count = function(id)
			local n = 0
			for _, e in ipairs(list) do
				if e.id == id then
					n = n + 1
				end
			end
			return n
		end,
		stop = function()
			conn:Disconnect()
			F.w = nil
		end,
	}
	return F.w
end

-- The client half replays the flow's traffic as Ava: her BattleState messages stay in the replication log only while
-- F.record says so (her first trial, the start of the raid; every "Start" / "End" / "Lobby"), everything else of the
-- battles stays out (thousands of snapshots would swamp the client replay of tools/smoke_client.lua), and so do the
-- ArenaState broadcasts to everyone except the raid countdown (F.keepArena): the flow waits through many minutes, and
-- client_replay replays every broadcast for each player it picks.
local savedHook = nil
local function filterReplication()
	if savedHook == nil and Mock._onRemote then
		savedHook = Mock._onRemote
		Mock._onRemote = function(entry)
			if entry.remote == "ArenaState" and entry.kind == "all" and not F.keepArena then
				return
			end
			if entry.remote == "BattleState" then
				local kind = entry.args and entry.args[1]
				local keep = false
				if entry.userId == IDS.Ava then
					keep = kind == "Start" or kind == "End" or kind == "Lobby" or (F.record == true)
				end
				if not keep then
					return
				end
			end
			savedHook(entry)
		end
	end
end
local function restoreReplication()
	if savedHook then
		Mock._onRemote = savedHook
		savedHook = nil
	end
end

local function scenario(name, fn)
	local run = guarded(name, fn)
	return function(...)
		filterReplication()
		local ok = run(...)
		F.record = nil
		F.keepArena = nil
		Mock.DataStore.Latency = 0
		restoreReplication()
		local bc = BC()
		if bc and F.savedTiers then
			for i, tier in ipairs(bc.Raid.Tiers) do
				local s = F.savedTiers[i]
				if s then
					tier.GemChance, tier.EventPetChance = s[1], s[2]
				end
			end
			F.savedTiers = nil
		end
		K.flushErrors(name)
		return ok
	end
end

local function ready(label)
	if not K.needBoot() then
		return false
	end
	if not (BS() and ES() and DS() and AB() and BC() and arenaInfo()) then
		T.fail(label .. ": skipped, BattleService / EventService / DataService / ArenaBuilder / BattleCatalog or the arena is missing")
		return false
	end
	if label ~= "arrive" and not F.arrived then
		T.fail(label .. ": skipped, the flow's first chapter (p3flow_arrive) did not run")
		return false
	end
	return true
end

-- the raid schedule: no raid running, the next one far enough away for the chapters before the raid
local function clearRaids()
	local bs, es = BS(), ES()
	if bs.GetRaidStatus() ~= nil then
		es.EndNow("BossRaid")
		waitFor(function()
			return bs.GetRaidStatus() == nil
		end, 10)
	end
end

----------------------------------------------------------------------------------------------------
-- a trial through the remote: walk to the portal, ask, fight (Attack + Special orders), the end, the return
----------------------------------------------------------------------------------------------------
local function runTrial(p, level, opts)
	opts = opts or {}
	local out = { keys = DS().ActiveTeamKeys(p) }
	if not opts.stay then
		toPortal(p)
	end
	out.tokens0 = tokens(p)
	out.xp0 = xpOf(p, out.keys)
	advance(1.6) -- the Trial request cooldown
	local mark = K.logSize()
	out.mark = mark
	request(p, "Trial", level)
	advance(0.2)
	local id = p:GetAttribute("InBattle")
	if type(id) ~= "string" then
		out.refused = table.concat(toasts(p, mark), " | ")
		return out
	end
	out.id = id
	out.start = lastMsg(p, "Start", mark)
	out.battle = BS().GetBattle(p)
	if opts.duringStart then
		opts.duringStart(out)
	end
	local slot = 0
	local t0 = Mock.Clock.now
	while F.w.find(id) == nil and Mock.Clock.now - t0 < 135 do
		advance(0.5)
		if opts.during then
			opts.during(out, Mock.Clock.now - t0)
		end
		if opts.commands ~= false and F.w.find(id) == nil then
			slot = slot % 3 + 1
			command(p, "Attack")
			command(p, "Special", slot)
		end
	end
	out.result = F.w.find(id)
	out.rw = out.result and type(out.result.Rewards) == "table" and out.result.Rewards[p.UserId] or nil
	out.endMsg = lastMsg(p, "End", mark)
	out.paid = tokens(p) - out.tokens0
	out.orders = 0
	for _, ev in ipairs(eventsOf(p, mark, "Order")) do
		if ev.owner == p.UserId then
			out.orders = out.orders + 1
		end
	end
	out.specials = #eventsOf(p, mark, "Special")
	waitFor(function()
		return p:GetAttribute("InBattle") == nil
	end, 7)
	advance(0.3)
	return out
end

-- the trial's expected rewards (TrialRewards with the Double Rewards flag of the record)
local function trialReward(level, rw, first)
	local R = BC().TrialRewards(level, type(rw) == "table" and rw.Double == true)
	local tokensWant = R.Tokens + (first and R.FirstClear.Tokens or 0)
	return tokensWant, R.Xp, first and R.FirstClear.Gems or 0
end

----------------------------------------------------------------------------------------------------
-- p3flow_arrive
----------------------------------------------------------------------------------------------------
local function phase2Save()
	-- what a Phase 2 server stored: no Teams / Battle; Prestige 1, stations, a Garden pet, the home chapter done
	local stepsMod = Steps()
	local chapter3 = stepsMod and stepsMod.ChapterStart and stepsMod.ChapterStart[3] or 15
	local pets = {}
	for _, id in ipairs(TEAMS.Cy) do
		pets[id] = 1
	end
	pets[TEAMS.CyGarden] = 1
	local levels = {}
	for _, id in ipairs(TEAMS.Cy) do
		levels[id] = { Level = 12, Xp = 7 }
	end
	local discovered = {}
	for id in pairs(pets) do
		discovered[id] = true
	end
	return {
		Version = 2,
		Tokens = 2500,
		Pets = pets,
		Equipped = { TEAMS.Cy[1] },
		Items = {},
		Stats = { Matches = 4, Wins = 3, TokensEarned = 900, Spins = 9, BestTimes = {} },
		Discovered = discovered,
		IndexClaimed = {},
		Tutorial = { Step = chapter3, Done = true, Gifted = true },
		Cash = 4321,
		Gems = 77,
		Home = {
			Level = 8, Prestige = 1, Stations = { Press1 = 2, Collector = 1, Garden = 1, House = 1, Kitchen = 1, Gym = 1 },
			Garden = { TEAMS.CyGarden }, Gym = {}, CollectorCash = 0, LastSeen = 0,
		},
		Food = { Snack = 2 },
		PetLevels = levels,
	}
end

S.p3flow_arrive = scenario("p3flow_arrive", function()
	if not ready("arrive") then
		return
	end
	local bs, es, data, bc = BS(), ES(), DS(), BC()
	local info = arenaInfo()
	local Config = config()
	watcher()
	-- the schedule: nothing running, the next Boss Raid ~20 minutes away (used once by hand, like the DEV panel does)
	clearRaids()
	if es.IsDoubleRewards() then
		es.EndNow("DoubleRewards")
	end
	local left = es.SecondsUntil("BossRaid") or 0
	if left < 15 * 60 then
		es.StartNow("BossRaid")
		es.EndNow("BossRaid")
		waitFor(function()
			return bs.GetRaidStatus() == nil
		end, 10)
	end
	left = es.SecondsUntil("BossRaid") or 0
	T.check(left > 15 * 60, "flow: (setup) the next Boss Raid is ~20 minutes away", string.format("%.0f s", left))

	-- Cy's Phase 2 save, then everybody joins
	Mock.DataStore.Data[storeKey(IDS.Cy)] = phase2Save()
	local mark = K.logSize()
	F.logStart = mark
	local ava = join("Ava")
	local bo = join("Bo")
	local cy = join("Cy")
	local okProfiles = data.GetProfile(ava) and data.GetProfile(bo) and data.GetProfile(cy)
	if not T.check(okProfiles ~= nil, "flow arrive: Ava, Bo and Cy join and their profiles load") then
		return
	end
	F.arrived = true

	-- the interfaces the modules hand each other (ARCHITECTURE_V3.md "Interfaces between the Phase 3 modules")
	local missing = {}
	local function need(cond, what)
		if not cond then
			missing[#missing + 1] = what
		end
	end
	local function isSignal(sig)
		return type(sig) == "table" and type(sig.Connect) == "function" and type(sig.Fire) == "function"
	end
	need(isSignal(bs.BattleEnded) and isSignal(data.TeamsChanged), "BattleService.BattleEnded / DataService.TeamsChanged (signals at module load)")
	for _, fn in ipairs({ "StartTrial", "Challenge", "StartRaid", "EndRaid", "GetBattle", "IsInBattle", "GetRaidStatus" }) do
		need(type(bs[fn]) == "function", "BattleService." .. fn)
	end
	for _, fn in ipairs({ "GetTeams", "SetTeam", "SelectTeam", "ActiveTeamKeys", "GetBattle", "MutateBattle", "AddTrophies" }) do
		need(type(data[fn]) == "function", "DataService." .. fn)
	end
	need(type(es.StartNow) == "function", "EventService.StartNow")
	local sim = req("shared/BattleSim")
	need(sim and type(sim.States) == "table" and type(sim.States.Down) == "number" and type(sim.Events) == "table" and sim.Events.Telegraph == "Telegraph", "BattleSim.States / Events")
	local okUp, up = pcall(bc.UnitPower, "cloudy_dragon", 1, "Normal")
	need(okUp and type(up) == "number" and up > 0, "BattleCatalog.UnitPower(petId, level, tier)")
	local okTp, tp = pcall(bc.TeamPower, { { PetId = "cloudy_dragon", Level = 1, Tier = "Normal" }, { PetId = "pebble_pup", Level = 3, Tier = "Normal" } })
	need(okTp and type(tp) == "number" and tp > 0, "BattleCatalog.TeamPower({ { PetId, Level, Tier } })")
	local okSy, syn = pcall(bc.Synergy, { "cloudy_dragon", "ember_phoenix", "aurora_fox" })
	local synOk = okSy and type(syn) == "table"
	for _, e in ipairs(synOk and syn or {}) do
		synOk = synOk and type(e.Id) == "string" and type(e.Name) == "string" and type(e.Text) == "string"
	end
	need(synOk, "BattleCatalog.Synergy(petIds) -> { { Id, Name, Text } }")
	local t1 = bc.Trials and bc.Trials[1]
	need(type(t1) == "table" and t1.Level == 1 and type(t1.Name) == "string" and type(t1.RecommendedPower) == "number" and t1.MiniBoss == false
		and type(t1.Rewards) == "table" and type(t1.Rewards.Tokens) == "number" and type(t1.Rewards.FirstClear) == "table"
		and type(t1.Rewards.FirstClear.Tokens) == "number" and type(t1.Rewards.FirstClear.Gems) == "number" and #bc.Trials == 30,
		"BattleCatalog.Trials[level] = { Level, Name, RecommendedPower, MiniBoss, Rewards = { Tokens, FirstClear = { Tokens, Gems } } } x30")
	for _, id in ipairs(bc.BossOrder or {}) do
		local boss = bc.Bosses[id]
		need(type(boss) == "table" and type(boss.Name) == "string" and type(boss.Element) == "string", "BattleCatalog.Bosses." .. tostring(id) .. " { Name, Element }")
	end
	for _, kind in ipairs(bc.SpecialKinds or {}) do
		local sp = bc.Specials[kind]
		need(type(sp) == "table" and type(sp.Name) == "string" and type(sp.Text) == "string", "BattleCatalog.Specials." .. kind .. " { Name, Text }")
	end
	need(info.Model == workspace:FindFirstChild("BattleArena") and typeof(info.Center) == "CFrame" and type(info.Floor) == "table" and typeof(info.Floor.CFrame) == "CFrame"
		and typeof(info.Floor.Size) == "Vector3" and type(info.Rings) == "table" and #info.Rings >= 2 and typeof(info.Rings[1].CFrame) == "CFrame"
		and typeof(info.Rings[1].Size) == "Vector3" and type(info.Rings[1].Pads) == "table" and typeof(info.Spawn) == "CFrame" and typeof(info.ReturnCFrame) == "CFrame"
		and typeof(info.TrialPortal) == "Instance" and info.TrialPortal:IsA("BasePart"), "ArenaInfo { Model, Center, Floor, Rings, Spawn, ReturnCFrame, TrialPortal }")
	local ab = AB()
	need(type(ab.BuildPocket) == "function" and type(ab.FreePocket) == "function" and type(ab.InArena) == "function", "ArenaBuilder.BuildPocket / FreePocket / InArena")
	-- the Trial Portal's prompt opens the Trial window only where the client (START) and BattleService accept a start
	local trialPrompt = nil
	for _, d in ipairs(info.TrialPortal:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d:GetAttribute("OpenPanel") == "Trials" then
			trialPrompt = d
		end
	end
	local function rangeIn(key, pattern, default)
		local inst = K.moduleInstance(key)
		local ok, src = pcall(function()
			return inst and inst.Source
		end)
		return tonumber(ok and type(src) == "string" and src:match(pattern) or nil) or default
	end
	local serverRange = rangeIn("server/Services/BattleService", "TRIAL_RANGE = (%d+)", 30)
	local clientRange = rangeIn("client/Controllers/ArenaController", "TRIAL_RANGE = (%d+)", serverRange)
	need(trialPrompt ~= nil and trialPrompt.MaxActivationDistance + 3 <= math.min(serverRange, clientRange) and clientRange <= serverRange,
		"the Trial Portal prompt (OpenPanel Trials) reaches only where trial starts are accepted (prompt "
			.. tostring(trialPrompt and trialPrompt.MaxActivationDistance) .. ", client " .. clientRange .. ", server " .. serverRange .. " studs)")
	T.check(#missing == 0, "flow arrive: the interfaces between the Phase 3 modules are all there (signals, APIs, BattleSim constants, BattleCatalog helpers, ArenaInfo)",
		table.concat(missing, "; "))

	-- ArenaState on join (EventService), the contract shape
	local function arenaShapeOk(st)
		if type(st) ~= "table" or type(st.Leaderboard) ~= "table" then
			return false
		end
		if st.Next ~= nil and (type(st.Next) ~= "table" or type(st.Next.Kind) ~= "string" or type(st.Next.StartsIn) ~= "number") then
			return false
		end
		if st.Raid ~= nil and type(st.Raid) ~= "table" then
			return false
		end
		if st.Double ~= nil and (type(st.Double) ~= "table" or st.Double.Active == nil) then
			return false
		end
		for _, row in ipairs(st.Leaderboard) do
			if type(row.UserId) ~= "number" or type(row.Name) ~= "string" or type(row.Trophies) ~= "number" then
				return false
			end
		end
		return #st.Leaderboard <= 10
	end
	local st = lastArenaState(ava, mark)
	T.check(arenaShapeOk(st) and st.Next and st.Next.Kind == "BossRaid", "flow arrive: a joining player gets ArenaState { Next = { Kind, BossId, StartsIn }, Raid, Double, Leaderboard }",
		st and plain(st.Next) or "none")

	-- ProfileSync: Teams + Battle (Phase 3)
	local sa = lastSync(ava, mark)
	T.check(type(sa) == "table" and type(sa.Teams) == "table" and type(sa.Teams.Presets) == "table" and #sa.Teams.Presets == 3 and #sa.Teams.Presets[1] == 0
		and sa.Teams.Active == 1 and sa.Teams.Slots == 3 and type(sa.Battle) == "table" and sa.Battle.Trophies == 0,
		"flow arrive: a new player's ProfileSync has Teams { 3 empty presets, Active 1, Slots 3 } and a zeroed Battle", sa and plain(sa.Teams) or "none")

	-- Cy: the Phase 2 save migrated
	local ct = data.GetTeams(cy)
	local crec = data.GetBattle(cy)
	T.check(type(ct) == "table" and #ct.Presets == 3 and #ct.Presets[1] == 0 and ct.Active == 1 and ct.Slots == 4,
		"flow arrive: Cy's Phase 2 save loads with 3 empty presets and 4 slots (he is at Prestige 1)", plain(ct))
	T.check(type(crec) == "table" and crec.Trophies == 0 and count(crec.TrialCleared) == 0 and count(crec.EventPets) == 0 and (crec.Raids or 0) == 0,
		"flow arrive: ...and a zeroed battle record", plain(crec))
	local cprof = data.GetProfile(cy)
	local chome = data.GetHome(cy)
	T.check(data.GetCash(cy) == 4321 and data.GetGems(cy) == 77 and tokens(cy) == 2500 and chome and chome.Prestige == 1 and chome.Stations.Press1 == 2
		and data.GetPetLevel(cy, TEAMS.Cy[1]) == 12 and cprof.Pets[TEAMS.CyGarden] == 1 and chome.Garden[1] == TEAMS.CyGarden,
		"flow arrive: ...his Phase 2 data is intact (Cash, Gems, tokens, the prestige home, the Garden pet, pet levels)")
	local sc = lastSync(cy, mark)
	T.check(type(sc) == "table" and type(sc.Teams) == "table" and sc.Teams.Slots == 4 and type(sc.Battle) == "table",
		"flow arrive: ...and his ProfileSync carries Teams (Slots 4) + Battle")
	-- his tutorial resumes at the battle chapter
	local start3 = Steps().ChapterStart[3]
	local ts = tutorial(cy)
	T.check(ts and ts.Id == "arena" and ts.Chapter == 3 and ts.Step == start3 and ts.Done == false,
		"flow arrive: Cy (home chapter done in Phase 2) resumes the tutorial at chapter 3 'arena'", ts and (tostring(ts.Id) .. " step " .. tostring(ts.Step)) or "no state")
	T.check(ts and ts.Target and ts.Target.Kind == "Spot" and near(ts.Target.Position, info.Spawn.Position, 1),
		"flow arrive: ...its arrow points at the arena's forum (ArenaInfo.Spawn)")
	local tsMsgs = tutorialStates(cy, mark)
	T.check(#tsMsgs > 0 and tsMsgs[#tsMsgs].Id == "arena", "flow arrive: ...and TutorialState told his client")

	-- pets (stand-ins for many roulette spins)
	grant(ava, TEAMS.Ava, 15)
	grant(ava, { TEAMS.AvaExtra }, 15)
	grant(bo, TEAMS.Bo, 10)
	grant(bo, { TEAMS.BoWeak }, 1)
	advance(0.5)

	-- teams through the remote: slot 4 before Prestige 1, a duplicate, a pet not owned, then a real team
	local four = { TEAMS.Ava[1], TEAMS.Ava[2], TEAMS.Ava[3], TEAMS.AvaExtra }
	local m1 = K.logSize()
	local changed = 0
	local conn = data.TeamsChanged:Connect(function(p)
		if p == ava then
			changed = changed + 1
		end
	end)
	request(ava, "TeamSet", 1, four)
	local okRefused, text = toasted(ava, "unlocks at Prestige 1", m1)
	T.check(okRefused and #data.GetTeams(ava).Presets[1] == 0, "flow teams: a 4th pet before Prestige 1 is refused with a side toast (nothing stored)", text)
	advance(0.5)
	local m2 = K.logSize()
	request(ava, "TeamSet", 2, { TEAMS.Ava[1], TEAMS.Ava[1] })
	advance(0.5)
	request(ava, "TeamSet", 3, { "stormfang" })
	T.check((toasted(ava, "only once", m2)) and (toasted(ava, "do not own", m2)) and #data.GetTeams(ava).Presets[2] == 0 and #data.GetTeams(ava).Presets[3] == 0,
		"flow teams: the same pet twice and a pet Ava does not own are refused", table.concat(toasts(ava, m2), " | "))
	advance(0.5)
	local m3 = K.logSize()
	request(ava, "TeamSet", 1, TEAMS.Ava)
	advance(0.4)
	conn:Disconnect()
	local at = data.GetTeams(ava)
	T.check(sameList(at.Presets[1], TEAMS.Ava) and sameList(data.ActiveTeamKeys(ava), TEAMS.Ava) and (toasted(ava, "Team 1 saved", m3)),
		"flow teams: three pets saved in preset 1 through BattleRequest TeamSet (toast; the active team)", listText(at.Presets[1]))
	T.check(changed == 1, "flow teams: DataService.TeamsChanged fired once (for the saved team only)", tostring(changed))
	local sync = lastSync(ava, m3)
	T.check(sync and sync.Teams and sameList(sync.Teams.Presets[1], TEAMS.Ava) and sync.Teams.Active == 1, "flow teams: ...and ProfileSync carries the new preset")
	-- Bo: a main team and a one-pet preset
	request(bo, "TeamSet", 1, TEAMS.Bo)
	advance(0.5)
	request(bo, "TeamSet", 2, { TEAMS.BoWeak })
	advance(0.4)
	local bt = data.GetTeams(bo)
	T.check(sameList(bt.Presets[1], TEAMS.Bo) and sameList(bt.Presets[2], { TEAMS.BoWeak }) and bt.Active == 1, "flow teams: Bo keeps two presets (preset 1 active)", plain(bt))

	-- Cy claims his home (Phase 2: E at a free gate): his build comes back on the plot
	local plot = claimFree(cy)
	local home = data.GetHome(cy)
	T.check(plot ~= nil and home and home.Stations.Gym == 1 and home.Prestige == 1 and stepId(cy) == "arena",
		"flow home: Cy claims a home plot (E at a free gate): his Phase 2 build (Gym, Prestige 1) is there", tostring(plot))
	F.facts.cyPlot = plot
	-- the Arena Gate was a "Coming soon" pad in Phase 2: now he buys it (150K Cash after the Gym) and walks through it
	local TCat = TC()
	local gateDef = TCat and TCat.Get and TCat.Get("ArenaGate")
	local price = gateDef and gateDef.Price and gateDef.Price[1] or 150000
	if plot and data.GetCash(cy) < price then
		data.AddCash(cy, price - data.GetCash(cy)) -- a stand-in for the Collector income of that time
	end
	local cash0 = data.GetCash(cy)
	local mBuy = K.logSize()
	pressPrompt(cy, plot and plotPrompt(plot, "BuyPrompt", "ArenaGate"))
	advance(0.6)
	home = data.GetHome(cy)
	T.check(home and home.Stations.ArenaGate == 1 and cash0 - data.GetCash(cy) == price, "flow home: Cy buys the Arena Gate on its pad (E, " .. price .. " Cash)",
		table.concat(toasts(cy, mBuy), " | "))
	local gatePrompt = plot and plotPrompt(plot, "ArenaGatePrompt")
	T.check(gatePrompt ~= nil and gatePrompt.Enabled ~= false and gatePrompt:GetAttribute("OwnerUserId") == cy.UserId,
		"flow home: ...its 'Go to Arena' prompt stands at the gate (his own)")
	-- through the gate: 'arena' -> 'team'
	local mGate = K.logSize()
	pressPrompt(cy, gatePrompt)
	waitFor(function()
		return stepId(cy) ~= "arena"
	end, 4)
	T.check(inArena(cy) and (toasted(cy, "Welcome to the Battle Arena", mGate)), "flow home: E at his Arena Gate takes Cy to the Battle Arena (ArenaBuilder teleport)")
	ts = tutorial(cy)
	T.check(ts and ts.Id == "team" and ts.Target and ts.Target.Kind == "Menu" and ts.Target.Id == "Team",
		"flow tutorial: arriving in the Battle Arena -> 'team' (the Team tile rings)", ts and tostring(ts.Id) or "nil")
	-- his Garden pet is busy; four pets are fine at Prestige 1
	local m4 = K.logSize()
	request(cy, "TeamSet", 1, { TEAMS.Cy[1], TEAMS.CyGarden })
	advance(0.6)
	T.check((toasted(cy, "Garden", m4)) and #data.GetTeams(cy).Presets[1] == 0 and stepId(cy) == "team",
		"flow teams: Cy's pet that works in his Garden cannot join a team (toast; 'team' keeps waiting)", table.concat(toasts(cy, m4), " | "))
	request(cy, "TeamSet", 1, TEAMS.Cy)
	waitFor(function()
		return stepId(cy) ~= "team"
	end, 3)
	T.check(sameList(data.GetTeams(cy).Presets[1], TEAMS.Cy), "flow teams: Cy (Prestige 1) saves a team of FOUR pets", listText(data.GetTeams(cy).Presets[1]))
	ts = tutorial(cy)
	T.check(ts and ts.Id == "trial" and ts.Target and near(ts.Target.Position, info.TrialPortal.Position, 1),
		"flow tutorial: a battle team -> 'trial' (the arrow at the Trial Portal)", ts and tostring(ts.Id) or "nil")
	toLobby(cy, 6)
	toLobby(ava)
	toLobby(bo, -6)
end)

----------------------------------------------------------------------------------------------------
-- p3flow_trials
----------------------------------------------------------------------------------------------------
S.p3flow_trials = scenario("p3flow_trials", function()
	if not ready("trials") then
		return
	end
	local bs, data, bc = BS(), DS(), BC()
	local info = arenaInfo()
	local ava, bo, cy = F.p.Ava, F.p.Bo, F.p.Cy

	-- refusals: away from the portal, a locked level
	toLobby(ava)
	local m0 = K.logSize()
	request(ava, "Trial", 1)
	T.check((toasted(ava, "Trial Portal", m0)) and ava:GetAttribute("InBattle") == nil, "flow trials: a trial asked for away from the Trial Portal is refused (toast)")
	toPortal(ava)
	advance(1.6)
	local m1 = K.logSize()
	request(ava, "Trial", 2)
	T.check((toasted(ava, "Beat Trial 1 first", m1)) and ava:GetAttribute("InBattle") == nil, "flow trials: Trial 2 is locked before Trial 1 (toast)")

	-- Trials 1, 2, 3: won, first-clear rewards once, XP, the record
	local cleared = {}
	for level = 1, 3 do
		F.record = level == 2 -- the client half replays Ava's Trial 2 (Trial 1 is over in a few snapshots)
		local r = runTrial(ava, level, {
			stay = true,
			duringStart = function(out)
				local inPocket = (K.root(ava).Position - info.TrialPortal.Position).Magnitude > 300
				out.inPocket = inPocket
			end,
		})
		F.record = nil
		if not T.check(r.id ~= nil, "flow trials: Ava starts Trial " .. level .. " at the portal (BattleRequest Trial)", r.refused) then
			break
		end
		local s = r.start
		local slots, keys = {}, {}
		for _, u in ipairs(s and s.Units or {}) do
			if u.owner == ava.UserId then
				slots[#slots + 1] = u.slot
				keys[u.slot] = u.key
			end
		end
		table.sort(slots)
		if level == 1 then
			T.check(r.inPocket and r.battle and r.battle.Mode == "Trial" and r.battle.Level == 1 and type(s) == "table" and s.Mode == "Trial" and s.Spectator == false
				and s.Side == 1 and type(s.Trial) == "table" and s.Trial.Level == 1,
				"flow trials: Ava fights Trial 1 in her private pocket ('Start': Mode Trial, Side 1, Trial { Level 1 })")
			T.check(#slots == 3 and slots[1] == 1 and slots[3] == 3 and keys[1] == TEAMS.Ava[1] and keys[2] == TEAMS.Ava[2] and keys[3] == TEAMS.Ava[3],
				"flow trials: ...her units are her preset's keys in slots 1-3 (static unit info carries slot + key)", listText(keys))
		end
		if level == 2 then
			-- (Trial 1 is one handicapped pet and is over before a command lands)
			T.check(r.orders > 0, "flow trials: ...her BattleCommand Attack orders reach the battle (Order events)", tostring(r.orders))
		end
		local res, rw = r.result, r.rw
		if T.check(res ~= nil and res.Mode == "Trial" and res.Level == level and contains(res.Winners, ava.UserId) and #res.Losers == 0 and res.Forfeit == false,
			"flow trials: Ava wins Trial " .. level .. " (BattleEnded { Mode, Winners, Losers, Level, Forfeit })", res and tostring(res.Reason) or "no end") then
			local want, xp, gemsWant = trialReward(level, rw, true)
			T.check(type(rw) == "table" and rw.FirstClear == true and rw.Tokens == want and rw.Gems == gemsWant and rw.Xp == xp and r.paid == want + 0,
				"flow trials: Trial " .. level .. " first clear: TrialRewards Tokens + FirstClear.Tokens paid once (" .. want .. ")",
				rw and ("rw " .. tostring(rw.Tokens) .. " paid " .. tostring(r.paid)) or "no rewards")
			local okXp, detail = gainedXp(ava, r.xp0, xp)
			T.check(okXp, "flow trials: ...every team pet got exactly " .. xp .. " XP (PetCareService.GrantXp)", detail)
			T.check(r.endMsg and r.endMsg.Outcome == "Win" and r.endMsg.Won == true and type(r.endMsg.Rewards) == "table" and r.endMsg.Rewards.Tokens == want
				and type(r.endMsg.Result) == "table" and r.endMsg.Result.Level == level,
				"flow trials: ...'End' tells her (Outcome Win, Rewards, Result)")
			T.eq(F.w.count(r.id), 1, "flow trials: ...BattleEnded fired once for Trial " .. level)
			cleared[level] = true
		end
		T.check(ava:GetAttribute("InBattle") == nil and planarFrom(ava, info.ReturnCFrame) < 12, "flow trials: ...and she is back in front of the Trial Portal")
	end
	advance(0.4)
	local rec = record(ava)
	T.check(rec.TrialCleared[1] == true and rec.TrialCleared[2] == true and rec.TrialCleared[3] == true and rec.TrialBest == 3,
		"flow trials: Ava's record: TrialCleared 1-3, TrialBest 3", plain(rec.TrialCleared))
	local sync = lastSync(ava)
	T.check(sync and sync.Battle and type(sync.Battle.TrialCleared) == "table" and sync.Battle.TrialCleared[3] == true and sync.Battle.TrialBest == 3,
		"flow trials: ...ProfileSync Battle carries it (TrialCleared as a dense boolean array)")
	-- a repeat pays the repeat amount only
	local r1 = runTrial(ava, 1, {})
	local wantRepeat = trialReward(1, r1.rw, false)
	T.check(r1.rw and r1.rw.FirstClear == false and r1.rw.Tokens == wantRepeat and r1.paid == wantRepeat,
		"flow trials: a repeat clear of Trial 1 pays TrialRewards(1).Tokens only (" .. wantRepeat .. ")", r1.rw and tostring(r1.paid) or tostring(r1.refused))
	F.facts.avaRepeat1 = wantRepeat

	-- Bo's one-pet preset (a level-1 pebble pup, the tutorial's situation) WINS Trial 1 without a single command: the
	-- first fight is a sure thing; the same pet then LOSES Trial 2: nothing paid, nothing cleared
	local mB = K.logSize()
	request(bo, "TeamSelect", 2)
	advance(0.3)
	T.check(sameList(data.ActiveTeamKeys(bo), { TEAMS.BoWeak }) and (toasted(bo, "Team 2 is your battle team", mB)),
		"flow trials: Bo selects his one-pet preset (BattleRequest TeamSelect)")
	local rb1 = runTrial(bo, 1, { commands = false })
	local bUnits = 0
	for _, u in ipairs(rb1.start and rb1.start.Units or {}) do
		if u.owner == bo.UserId then
			bUnits = bUnits + 1
		end
	end
	T.check(rb1.id ~= nil and bUnits == 1, "flow trials: Bo's trial uses the ACTIVE preset (one unit)", tostring(bUnits))
	local wantB1 = trialReward(1, rb1.rw, true)
	T.check(rb1.result and contains(rb1.result.Winners, bo.UserId) and rb1.paid == wantB1 and record(bo).TrialCleared[1] == true,
		"flow trials: Bo's single level-1 pet WINS Trial 1 without pressing anything (first clear paid once)", rb1.result and tostring(rb1.result.Reason) or "no end")
	local rb = runTrial(bo, 2, {})
	T.check(rb.result and contains(rb.result.Losers, bo.UserId) and #rb.result.Winners == 0 and rb.endMsg and rb.endMsg.Outcome == "Loss",
		"flow trials: ...and LOSES Trial 2 (Outcome Loss)", rb.result and tostring(rb.result.Reason) or "no end")
	T.check(rb.paid == 0 and (rb.rw == nil or (rb.rw.Tokens or 0) == 0) and record(bo).TrialCleared[2] ~= true and (toasted(bo, "lost", rb.mark)),
		"flow trials: ...nothing is paid, Trial 2 stays uncleared, a side toast says so")
	local okXp0 = gainedXp(bo, rb.xp0, 0)
	T.check(okXp0, "flow trials: ...and a lost trial gives no pet XP")
	-- with his main team he wins Trial 2
	request(bo, "TeamSelect", 1)
	advance(0.3)
	local rb2 = runTrial(bo, 2, {})
	local wantB = trialReward(2, rb2.rw, true)
	T.check(rb2.result and contains(rb2.result.Winners, bo.UserId) and rb2.paid == wantB and record(bo).TrialCleared[2] == true,
		"flow trials: Bo wins Trial 2 with his main team (first clear paid once)", tostring(rb2.paid))

	-- Cy inside the tutorial: no arrow while he fights; the win -> 'raid'
	-- (Trial 1 is over before the tutorial's poll sees the fight: the InBattle attribute stands in for it here)
	cy:SetAttribute("InBattle", "flow-fake-battle")
	advance(1.2)
	local stHidden = tutorial(cy)
	local hidden = stHidden ~= nil and stHidden.Id == "trial" and stHidden.Target == nil
	cy:SetAttribute("InBattle", nil)
	advance(1.2)
	T.check(hidden == true, "flow tutorial: no guide arrow while Cy fights (InBattle)")
	local rc = runTrial(cy, 1, {})
	local cUnits = 0
	for _, u in ipairs(rc.start and rc.start.Units or {}) do
		if u.owner == cy.UserId then
			cUnits = cUnits + 1
		end
	end
	T.check(rc.result and contains(rc.result.Winners, cy.UserId) and cUnits == 4, "flow trials: Cy wins Trial 1 with his four pets", tostring(cUnits))
	local wantC = trialReward(1, rc.rw, true)
	T.eq(rc.paid, wantC, "flow trials: ...his first clear is paid once")
	waitFor(function()
		return stepId(cy) ~= "trial"
	end, 3)
	local st = tutorial(cy)
	T.check(st and st.Id == "raid" and st.Target and near(st.Target.Position, info.Floor.CFrame.Position, 1),
		"flow tutorial: winning Trial 1 -> 'raid' (the arrow at the colosseum floor)", st and tostring(st.Id) or "nil")
	T.check(st and tostring(st.Hint):find("Boss Raid", 1, true) ~= nil, "flow tutorial: ...its hint counts down to the next Boss Raid", st and tostring(st.Hint))

	-- Cy's home (Phase 2) meets his battle team: a team pet that starts training in the Gym leaves the team
	local home = data.GetHome(cy)
	local changedCy = 0
	local connCy = data.TeamsChanged:Connect(function(p)
		if p == cy then
			changedCy = changedCy + 1
		end
	end)
	local mG = K.logSize()
	Mock.FromClient(remote("PetCare"), cy, "GymSet", 1, TEAMS.Cy[4])
	advance(0.6)
	connCy:Disconnect()
	home = data.GetHome(cy)
	local cyKeys = data.ActiveTeamKeys(cy)
	T.check(home and home.Gym[1] == TEAMS.Cy[4] and #cyKeys == 3 and not contains(cyKeys, TEAMS.Cy[4]) and changedCy >= 1,
		"flow home: Cy puts his Combat pet into the Gym (PetCare GymSet): it leaves his battle team (pruned; TeamsChanged)", listText(cyKeys))
	local syCy = lastSync(cy, mG)
	T.check(syCy and syCy.Teams and #syCy.Teams.Presets[1] == 3 and syCy.Home and syCy.Home.Gym, "flow home: ...ProfileSync shows the 3-pet team and the Gym pet")
	local mG2 = K.logSize()
	request(cy, "TeamSet", 1, TEAMS.Cy)
	T.check((toasted(cy, "busy in your Garden or Gym", mG2)) and #data.ActiveTeamKeys(cy) == 3, "flow home: ...and cannot rejoin the team while it trains")
	F.facts.cyTeam = cyKeys
	toLobby(cy, 6)
	toLobby(bo, -6)
	toLobby(ava)
	F.facts.trialsDone = cleared[3] == true
end)

----------------------------------------------------------------------------------------------------
-- p3flow_duels
----------------------------------------------------------------------------------------------------
local function lobbyOf(p, mark)
	return lastMsg(p, "Lobby", mark)
end

S.p3flow_duels = scenario("p3flow_duels", function()
	if not ready("duels") then
		return
	end
	local bs, data, bc = BS(), DS(), BC()
	local info = arenaInfo()
	local TR = bc.Trophies
	local ava, bo = F.p.Ava, F.p.Bo
	local hal = join("Hal")
	grant(hal, TEAMS.Hal, 1)
	request(hal, "TeamSet", 1, TEAMS.Hal)

	-- Ava challenges Bo inside the arena
	toArena(ava, 4, 0)
	toArena(bo, -4, 0)
	toArena(hal, 0, 6)
	advance(2.1) -- the Challenge cooldown of earlier requests
	local mark = K.logSize()
	request(ava, "Challenge", bo.UserId)
	advance(0.2)
	local lb = lobbyOf(bo, mark)
	local inv = lb and lb.Invites and lb.Invites[1]
	T.check(type(inv) == "table" and inv.FromUserId == ava.UserId and inv.FromName == ava.DisplayName and type(inv.Trophies) == "number" and type(inv.Power) == "number"
		and inv.Power > 0 and inv.ExpiresIn == 30,
		"flow duels: Bo's 'Lobby' lists Ava's challenge { FromUserId, FromName, Trophies, Power, ExpiresIn }")
	local la = lobbyOf(ava, mark)
	T.check(la and type(la.Sent) == "table" and la.Sent.ToUserId == bo.UserId and type(la.Queue) == "table" and la.Queue.Queued == false,
		"flow duels: Ava's 'Lobby' shows the challenge she sent (Sent { ToUserId, ToName, ExpiresIn }, Queue { Queued, Waiting })")
	T.check((toasted(bo, "challenges you", mark)), "flow duels: Bo gets a side toast")
	local recA0, recB0 = record(ava), record(bo)
	local ta0, tb0 = tokens(ava), tokens(bo)
	local xpA0, xpB0 = xpOf(ava, data.ActiveTeamKeys(ava)), xpOf(bo, data.ActiveTeamKeys(bo))
	local m2 = K.logSize()
	request(bo, "ChallengeReply", ava.UserId, true)
	advance(0.2)
	local id = ava:GetAttribute("InBattle")
	if not T.check(type(id) == "string" and bo:GetAttribute("InBattle") == id, "flow duels: Bo accepts (ChallengeReply): the duel starts for both", tostring(id)) then
		return
	end
	local ga, gb = bs.GetBattle(ava), bs.GetBattle(bo)
	T.check(ga and gb and ga.Mode == "Duel" and ga.Side == 1 and gb.Side == 2, "flow duels: the challenger fights from side 1, Bo from side 2")
	local zoneCF = ga.Zone.CFrame
	local onRing = false
	for _, ring in ipairs(info.Rings) do
		if (ring.CFrame.Position - zoneCF.Position).Magnitude < 0.5 then
			onRing = true
		end
	end
	T.check(onRing and inArena(ava) and inArena(bo), "flow duels: ...on one of the arena's duel rings, both standing at their pads")
	local sa, sb = lastMsg(ava, "Start", m2), lastMsg(bo, "Start", m2)
	T.check(sa and sb and sa.Mode == "Duel" and sa.Side == 1 and sb.Side == 2 and contains(sa.Sides[1], ava.UserId) and contains(sa.Sides[2], bo.UserId),
		"flow duels: 'Start' to both duellists with their sides")
	advance(2.2)
	local sh = lastMsg(hal, "Start", m2)
	T.check(sh and sh.BattleId == id and sh.Spectator == true and sh.Side == 0, "flow duels: Hal, standing nearby in the arena, watches it ('Start' Spectator)")
	-- the fight (both press ATTACK and SPECIAL through the remote)
	local t0 = Mock.Clock.now
	local slot = 0
	while F.w.find(id) == nil and Mock.Clock.now - t0 < 135 do
		advance(0.5)
		slot = slot % 3 + 1
		for _, p in ipairs({ ava, bo }) do
			command(p, "Attack")
			command(p, "Special", slot)
		end
	end
	local r = F.w.find(id)
	if T.check(r ~= nil and r.Mode == "Duel" and ((#r.Winners == 1 and #r.Losers == 1) or r.Draw), "flow duels: the duel ends", r and tostring(r.Reason) or "no end") and not r.Draw then
		local winner = (r.Winners[1] == ava.UserId) and ava or bo
		local loser = (winner == ava) and bo or ava
		F.facts.duelWinner = winner.Name
		local rwW, rwL = r.Rewards[winner.UserId], r.Rewards[loser.UserId]
		local recW0 = winner == ava and recA0 or recB0
		local recL0 = winner == ava and recB0 or recA0
		T.check(rwW and rwW.Trophies == TR.Win and rwW.Tokens == TR.Tokens.Win * doubled(rwW) and rwW.Xp == TR.Xp.Win,
			"flow duels: the winner (" .. winner.Name .. ") gets Trophies.Win, Tokens.Win, Xp.Win", rwW and plain(rwW) or "none")
		T.check(rwL and rwL.Trophies == 0 and rwL.Tokens == TR.Tokens.Loss * doubled(rwL) and rwL.Xp == TR.Xp.Loss,
			"flow duels: the loser gets Tokens.Loss and Xp.Loss; trophies stay at 0 (never below)", rwL and plain(rwL) or "none")
		local dW = tokens(winner) - (winner == ava and ta0 or tb0)
		local dL = tokens(loser) - (winner == ava and tb0 or ta0)
		T.check(dW == rwW.Tokens and dL == rwL.Tokens, "flow duels: token balances moved by exactly the rewards (once)", dW .. " / " .. dL)
		T.check(record(winner).Trophies == (recW0.Trophies or 0) + TR.Win and record(winner).PvPWins == (recW0.PvPWins or 0) + 1
			and record(loser).PvPLosses == (recL0.PvPLosses or 0) + 1 and record(loser).Trophies == 0,
			"flow duels: the records: trophies, PvPWins, PvPLosses")
		local okW = gainedXp(winner, winner == ava and xpA0 or xpB0, TR.Xp.Win)
		local okL = gainedXp(loser, winner == ava and xpB0 or xpA0, TR.Xp.Loss)
		T.check(okW and okL, "flow duels: every duelling pet got its XP (win / loss amounts)")
		local endW = lastMsg(winner, "End", m2)
		T.check(endW and endW.Outcome == "Win" and endW.Rewards and endW.Rewards.Trophies == TR.Win, "flow duels: 'End' tells the winner (Outcome Win, Rewards)")
		-- the leaderboard: ArenaState + the trophy board in the arena
		local m3 = K.logSize()
		advance(6)
		local st = lastArenaState(hal, m3)
		local row = nil
		for _, e in ipairs(st and st.Leaderboard or {}) do
			if e.UserId == winner.UserId then
				row = e
			end
		end
		T.check(row and row.Trophies == TR.Win and row.Name == winner.DisplayName, "flow duels: ArenaState.Leaderboard shows the winner with " .. TR.Win .. " trophies",
			st and plain(st.Leaderboard) or "no state")
		local board = false
		local lbInfo = info.Leaderboard
		for _, rrow in ipairs(lbInfo and lbInfo.Rows or {}) do
			if rrow.Frame.Visible and tostring(rrow.Name.Text) == winner.DisplayName and tostring(rrow.Trophies.Text):find(tostring(TR.Win), 1, true) then
				board = true
			end
		end
		T.check(board, "flow duels: ...and the trophy board in the arena lists " .. winner.Name .. " (" .. TR.Win .. ")")
	end
	T.eq(F.w.count(id), 1, "flow duels: BattleEnded fired once for the duel")
	local endH = lastMsg(hal, "End", m2)
	T.check(endH and endH.Spectator == true and endH.Rewards == nil, "flow duels: Hal gets 'End' as a spectator (no rewards)")
	advance(4.5)

	-- the quick queue: Dee and Eli
	local dee = join("Dee")
	local eli = join("Eli")
	grant(dee, TEAMS.Dee, 5)
	grant(eli, TEAMS.Eli, 5)
	request(dee, "TeamSet", 1, TEAMS.Dee)
	request(eli, "TeamSet", 1, TEAMS.Eli)
	toArena(dee, 8, 8)
	toArena(eli, -8, 8)
	toLobby(ava)
	toLobby(bo, -6)
	advance(0.5)
	local mq = K.logSize()
	request(dee, "Queue")
	local ld = lobbyOf(dee, mq)
	T.check(ld and ld.Queue and ld.Queue.Queued == true and ld.Queue.Waiting == 1, "flow queue: Dee joins the quick queue ('Lobby' Queued, Waiting 1)")
	request(eli, "Queue")
	waitFor(function()
		return dee:GetAttribute("InBattle") ~= nil
	end, 4)
	local qid = dee:GetAttribute("InBattle")
	T.check(type(qid) == "string" and eli:GetAttribute("InBattle") == qid and bs.GetBattle(dee).Mode == "Duel", "flow queue: Eli queues too: they are paired into a duel at once")
	local ld2 = lobbyOf(dee, mq)
	T.check(ld2 and ld2.Queue.Queued == false, "flow queue: ...and the queue status says they left it")
	-- both hold back (RETREAT), then Dee forfeits after 16 s: Eli gets the full win
	local te0, td0 = tokens(eli), tokens(dee)
	local recD0, recE0 = record(dee), record(eli)
	command(dee, "Retreat")
	command(eli, "Retreat")
	advance(16.5)
	local mf = K.logSize()
	command(dee, "Forfeit")
	advance(0.5)
	local rq = qid and F.w.find(qid)
	T.check(rq and rq.Forfeit == true and contains(rq.Winners, eli.UserId) and contains(rq.Losers, dee.UserId),
		"flow queue: Dee forfeits (BattleCommand Forfeit): Eli wins (Forfeit = true)", rq and plain(rq.Winners) or "no end")
	local rwE, rwD = rq and rq.Rewards[eli.UserId], rq and rq.Rewards[dee.UserId]
	T.check(rwE and rwE.Trophies == TR.Win and rwE.Tokens == TR.Tokens.Win * doubled(rwE) and tokens(eli) - te0 == rwE.Tokens,
		"flow queue: ...after 15 s a forfeit pays the winner in full", rwE and plain(rwE) or "none")
	T.check(rwD and rwD.Forfeit == true and (rwD.Tokens or 0) == 0 and tokens(dee) == td0 and record(dee).Trophies == 0 and record(dee).PvPLosses == (recD0.PvPLosses or 0) + 1,
		"flow queue: ...the forfeiter: no tokens, a PvP loss, trophies never below 0", rwD and plain(rwD) or "none")
	T.check((toasted(eli, "left the duel", mf)), "flow queue: ...Eli is told he won")
	advance(4.5)
	-- queued again: Eli disconnects mid-duel
	local mq2 = K.logSize()
	request(dee, "Queue")
	advance(1.1)
	request(eli, "Queue")
	waitFor(function()
		return dee:GetAttribute("InBattle") ~= nil
	end, 4)
	local qid2 = dee:GetAttribute("InBattle")
	T.check(type(qid2) == "string" and qid2 ~= qid and eli:GetAttribute("InBattle") == qid2, "flow queue: queued again (20 vs 0 trophies) they are paired at once")
	command(dee, "Retreat")
	command(eli, "Retreat")
	advance(16.5)
	local eliTrophies = record(eli).Trophies
	local eliLosses = record(eli).PvPLosses or 0
	local td1 = tokens(dee)
	F.facts.eliRecord = { Trophies = eliTrophies + TR.Forfeit, PvPLosses = eliLosses + 1, PvPWins = record(eli).PvPWins }
	Mock.DataStore.Latency = 0.2 -- the leave save takes a moment: the forfeit penalty is written before it
	Mock.RemovePlayer(eli)
	advance(0.5)
	local rq2 = qid2 and F.w.find(qid2)
	T.check(rq2 and rq2.Forfeit == true and contains(rq2.Winners, dee.UserId) and contains(rq2.Losers, IDS.Eli),
		"flow queue: Eli disconnects mid-duel: Dee wins (Forfeit = true)")
	local rwD2 = rq2 and rq2.Rewards[dee.UserId]
	T.check(rwD2 and rwD2.Trophies == TR.Win and tokens(dee) - td1 == rwD2.Tokens and record(dee).PvPWins == (recD0.PvPWins or 0) + 1,
		"flow queue: ...a full win for Dee (trophies, tokens once, PvPWins)", rwD2 and plain(rwD2) or "none")
	advance(13)
	Mock.DataStore.Latency = 0
	local se = stored(IDS.Eli)
	local seb = type(se) == "table" and se.Battle or {}
	T.check(seb.Trophies == F.facts.eliRecord.Trophies and seb.PvPLosses == F.facts.eliRecord.PvPLosses,
		"flow queue: ...Eli's penalty (Trophies.Forfeit, a PvP loss) is in his saved profile", plain(seb))
	T.check(dee:GetAttribute("InBattle") == nil and #lobbyOf(dee, mq2).Invites == 0, "flow queue: Dee is free again")
	toLobby(dee, 12)
	toLobby(hal, -12)
	F.facts.duelsDone = true
end)

----------------------------------------------------------------------------------------------------
-- p3flow_reset
----------------------------------------------------------------------------------------------------
S.p3flow_reset = scenario("p3flow_reset", function()
	if not ready("reset") then
		return
	end
	local bs, data, es = BS(), DS(), ES()
	local bo = F.p.Bo
	local before = record(bo)
	T.check(before.TrialCleared[1] == true and ((before.PvPWins or 0) + (before.PvPLosses or 0)) >= 1 and #data.GetTeams(bo).Presets[1] == 3,
		"flow reset: (precondition) Bo has a team, a cleared trial and a duel in his record", plain(before))
	-- refused while he fights
	toPortal(bo)
	advance(1.6)
	request(bo, "Trial", 2)
	advance(0.2)
	local id = bo:GetAttribute("InBattle")
	T.check(type(id) == "string", "flow reset: (setup) Bo starts Trial 2")
	local m1 = K.logSize()
	devCommand(bo, "reset")
	T.check((toasted(bo, "DEV: leave the battle first", m1)) and #data.GetTeams(bo).Presets[1] == 3 and record(bo).TrialCleared[1] == true,
		"flow reset: the developer /reset is refused while Bo fights (DevCommand: toast, nothing wiped)", table.concat(toasts(bo, m1), " | "))
	command(bo, "Forfeit")
	waitFor(function()
		return bo:GetAttribute("InBattle") == nil
	end, 7)
	advance(2.2) -- the DEV rate limit window
	local m2 = K.logSize()
	devCommand(bo, "reset")
	advance(0.4)
	T.check((toasted(bo, "DEV: data reset", m2)), "flow reset: after the battle /reset runs", table.concat(toasts(bo, m2), " | "))
	local teams = data.GetTeams(bo)
	local rec = record(bo)
	T.check(teams and #teams.Presets[1] == 0 and #teams.Presets[2] == 0 and #teams.Presets[3] == 0 and teams.Active == 1 and #data.ActiveTeamKeys(bo) == 0,
		"flow reset: Bo's battle teams are empty (3 presets, preset 1 active)", plain(teams))
	T.check(rec.Trophies == 0 and count(rec.TrialCleared) == 0 and (rec.TrialBest or 0) == 0 and (rec.PvPWins or 0) == 0 and (rec.PvPLosses or 0) == 0
		and (rec.Raids or 0) == 0 and count(rec.EventPets) == 0, "flow reset: ...and his battle record is zeroed", plain(rec))
	local sync = lastSync(bo, m2)
	T.check(sync and sync.Teams and #sync.Teams.Presets[1] == 0 and sync.Battle and sync.Battle.Trophies == 0 and #sync.Battle.TrialCleared == 0,
		"flow reset: ...ProfileSync shows it")
	-- without a team / with Trial 2 locked again
	toPortal(bo)
	advance(1.6)
	local m3 = K.logSize()
	request(bo, "Trial", 1)
	T.check((toasted(bo, "Pick your battle team", m3)) and bo:GetAttribute("InBattle") == nil, "flow reset: a trial without a team is refused (toast)")
	advance(1.6)
	local m4 = K.logSize()
	request(bo, "Trial", 2)
	T.check((toasted(bo, "Beat Trial 1 first", m4)), "flow reset: ...and Trial 2 is locked again")
	-- the leaderboard follows
	local m5 = K.logSize()
	advance(6)
	local st = lastArenaState(bo, m5)
	local row = nil
	for _, e in ipairs(st and st.Leaderboard or {}) do
		if e.UserId == bo.UserId then
			row = e
		end
	end
	T.check(row and row.Trophies == 0, "flow reset: ArenaState.Leaderboard has Bo at 0 trophies", row and plain(row) or "no row")
	-- the reset survives the next autosave (the grow-only TrialCleared is written over, not merged back)
	advance(config().Tokens.AutosaveSeconds + 12)
	local s = stored(IDS.Bo) or {}
	local sb = type(s.Battle) == "table" and s.Battle or {}
	local stc = type(sb.TrialCleared) == "table" and sb.TrialCleared or {}
	local anyTrue = false
	for _, v in pairs(stc) do
		anyTrue = anyTrue or v == true
	end
	local steams = type(s.Teams) == "table" and type(s.Teams.Presets) == "table" and s.Teams.Presets or {}
	T.check(not anyTrue and (sb.Trophies or 0) == 0 and (sb.PvPWins or 0) == 0 and (steams[1] == nil or #steams[1] == 0),
		"flow reset: ...and survives the next autosave (no cleared trial, no PvP record, no team in the store)", plain(sb))
	-- a fresh team for the raid
	grant(bo, TEAMS.BoNew, 12)
	request(bo, "TeamSet", 1, TEAMS.BoNew)
	advance(0.3)
	T.check(sameList(data.ActiveTeamKeys(bo), TEAMS.BoNew), "flow reset: Bo builds a new team afterwards")
	toLobby(bo, -6)
	T.check(es.SecondsUntil("BossRaid") > 125, "flow reset: (the next raid is still ahead)")
end)

----------------------------------------------------------------------------------------------------
-- p3flow_raid
----------------------------------------------------------------------------------------------------
S.p3flow_raid = scenario("p3flow_raid", function()
	if not ready("raid") then
		return
	end
	local bs, es, data, bc = BS(), ES(), DS(), BC()
	local info = arenaInfo()
	local ava, bo, cy, dee, hal = F.p.Ava, F.p.Bo, F.p.Cy, F.p.Dee, F.p.Hal
	if not (ava and bo and cy and dee and hal and ava.Parent and dee.Parent) then
		T.fail("flow raid: skipped, the players of the earlier chapters are missing")
		return
	end
	-- Eli comes back (he left in the middle of a duel): the save kept his loss
	local eli = join("Eli")
	local re = record(eli)
	local wantE = F.facts.eliRecord or {}
	T.check(re.Trophies == wantE.Trophies and re.PvPLosses == wantE.PvPLosses and re.PvPWins == wantE.PvPWins and sameList(data.GetTeams(eli).Presets[1], TEAMS.Eli),
		"flow rejoin: Eli rejoins with his team and the loss of the duel he left (trophies, PvP counters)", plain(re))
	toLobby(eli, 24)
	local fay = join("Fay")
	local gus = join("Gus")
	grant(fay, TEAMS.Fay, 15)
	grant(gus, TEAMS.Gus, 10)
	request(fay, "TeamSet", 1, TEAMS.Fay)
	request(gus, "TeamSet", 1, TEAMS.Gus)
	toLobby(fay, 18)
	toLobby(gus, -18)

	-- Double Rewards (the developer start; the schedule's hour works the same way)
	local mD = K.logSize()
	local okD = es.StartNow("DoubleRewards")
	local mult = bc.Events.DoubleRewardsMultiplier or 2
	T.check(okD == true and es.IsDoubleRewards() and bs.IsDoubleRewards() and workspace:GetAttribute("DoubleRewards") == true,
		"flow double: Double Rewards start (EventService.StartNow): EventService, BattleService and the Workspace attribute agree")
	T.check((toasted(ava, "Double Rewards", mD)) and (toasted(gus, "Double Rewards", mD)), "flow double: ...everyone gets a side toast")
	advance(1.2)
	local stD = lastArenaState(ava, mD)
	T.check(stD and type(stD.Double) == "table" and stD.Double.Active == true and stD.Double.EndsIn > 3000, "flow double: ArenaState.Double = { Active, EndsIn }")
	local rd = runTrial(ava, 1, {})
	local repeat1 = BC().TrialRewards(1, false).Tokens
	T.check(rd.rw and rd.rw.Double == true and rd.paid == repeat1 * mult, "flow double: a trial during Double Rewards pays x" .. mult .. " tokens",
		rd.rw and plain(rd.rw) or tostring(rd.refused))
	toLobby(ava)

	-- the scheduled raid: the announcement ~2 minutes ahead
	clearRaids()
	local entry = nil
	for _, e in ipairs(bc.Events.Schedule) do
		if e.Kind == "BossRaid" then
			entry = e
		end
	end
	local announce = entry and entry.AnnounceSeconds or 120
	local left = es.SecondsUntil("BossRaid")
	if left > announce + 5 then
		advance(left - announce - 5)
	end
	local stTut = tutorial(cy)
	T.check(stTut and stTut.Id == "raid" and tostring(stTut.Hint):find("Next Boss Raid in", 1, true) ~= nil,
		"flow tutorial: Cy's 'raid' step counts down to the next raid", stTut and tostring(stTut.Hint))
	F.keepArena = true -- the client half replays this countdown
	local mA = K.logSize()
	local announced = waitFor(function()
		return (toasted(hal, "Boss Raid in", mA))
	end, 15)
	local nextRaid = es.GetState().NextRaid
	local bossId = nextRaid and nextRaid.BossId
	local bossName = bossId and bc.Bosses[bossId] and bc.Bosses[bossId].Name or "?"
	local okAnn, annText = toasted(hal, "Boss Raid in", mA)
	T.check(announced and okAnn and annText:find(bossName, 1, true) ~= nil, "flow raid: ~2 minutes ahead everyone gets a side toast naming the boss (" .. bossName .. ")", annText)
	local mC = K.logSize()
	advance(5.2)
	local fast = arenaStates(ava, mC)
	local stN = fast[#fast]
	T.check(#fast >= 4 and stN and stN.Next and stN.Next.Kind == "BossRaid" and stN.Next.BossId == bossId and stN.Next.Announced == true and stN.Next.StartsIn <= announce,
		"flow raid: ArenaState counts the raid down about every second (Next { Kind, BossId, StartsIn, Announced })", stN and plain(stN.Next) or "none")
	-- everyone walks into the arena (Cy too: he is on the tutorial's last step)
	toArena(ava, -10, 6)
	toArena(bo, -5, 6)
	toArena(cy, 0, 6)
	toArena(dee, 5, 6)
	toArena(fay, 10, 6)
	toArena(gus, 15, 6)
	toArena(eli, 20, 6)
	Mock.Teleport(hal, info.Floor.CFrame * CFrame.new(0, 3, 62)) -- in the colosseum's stands, off the floor
	advance(0.1)
	local mR = K.logSize()
	local reminded = waitFor(function()
		return (toasted(ava, "arrives in", mR))
	end, announce)
	T.check(reminded, "flow raid: the 30 s reminder toast")
	local cyTokens0 = tokens(cy)
	local mO = K.logSize()
	local opened = waitFor(function()
		return bs.GetRaidStatus() ~= nil
	end, 40)
	if not T.check(opened, "flow raid: at its time the raid opens (BattleService.StartRaid by the scheduler)") then
		return
	end
	F.record = true -- the client half replays the start of Ava's raid
	F.keepArena = nil
	local status = bs.GetRaidStatus()
	local raidId = status.BattleId
	T.check(status.BossId == bossId and status.Waiting == true and status.Joinable == true and status.Players == 0,
		"flow raid: GetRaidStatus: the announced boss, waiting for fighters, joinable", plain(status))
	T.check((toasted(gus, "Boss Raid!", mO)), "flow raid: ...the 'Boss Raid!' toast to everyone")
	advance(1.2)
	local stO = lastArenaState(ava, mO)
	T.check(stO and type(stO.Raid) == "table" and stO.Raid.Active == true and stO.Raid.BossId == bossId and stO.Raid.Joinable == true,
		"flow raid: ArenaState.Raid = BattleService.GetRaidStatus()")
	-- the tutorial: standing in the arena while a raid runs finishes chapter 3 (its reward once)
	waitFor(function()
		return stepId(cy) == "done!"
	end, 4)
	local stC = tutorial(cy)
	local src = nil
	local inst = K.moduleInstance("server/Services/TutorialService")
	src = inst and inst.Source or ""
	local reward = tonumber(src:match("local ARENA_FINISH_TOKENS = (%d+)")) or 500
	T.check(stC and stC.Done == true and stC.Completed == true and tokens(cy) - cyTokens0 == reward,
		"flow tutorial: Cy standing in the arena during the raid finishes the battle chapter (+" .. reward .. " tokens)", tostring(tokens(cy) - cyTokens0))

	-- joins through the remote
	local fighters = { ava, bo, cy, dee, eli, gus }
	local maxHp = {}
	for i, p in ipairs(fighters) do
		local m = K.logSize()
		request(p, "JoinRaid")
		advance(0.2)
		local s = bs.GetRaidStatus()
		maxHp[i] = s and s.MaxHp or 0
		local start = lastMsg(p, "Start", m)
		if i == 1 then
			T.check(p:GetAttribute("InBattle") == raidId and start and start.Mode == "Raid" and start.BossId == bossId and start.Spectator == false,
				"flow raid: Ava joins (BattleRequest JoinRaid): 'Start' Mode Raid with the boss, InBattle = the raid id")
		elseif p == cy then
			local mine = {}
			for _, u in ipairs(start and start.Units or {}) do
				if u.owner == cy.UserId then
					mine[#mine + 1] = u.key
				end
			end
			table.sort(mine)
			local want = {}
			for k, v in ipairs(F.facts.cyTeam or {}) do
				want[k] = v
			end
			table.sort(want)
			T.check(#mine == 3 and sameList(mine, want), "flow raid: Cy fights with his team as it is now (the Gym pet stays home)", listText(mine))
		end
	end
	local players = bs.GetRaidStatus().Players
	T.check(players == 6 and maxHp[6] > maxHp[1], "flow raid: six teams joined; the boss HP grew with every team", players .. " teams, " .. maxHp[1] .. " -> " .. maxHp[6])
	advance(1.5)
	local specStart = lastMsg(hal, "Start", mO)
	T.check(specStart and specStart.BattleId == raidId and specStart.Spectator == true and specStart.Side == 0,
		"flow raid: Hal in the stands watches the raid ('Start' Spectator = true)")
	local inRaid = true
	for _, p in ipairs(fighters) do
		inRaid = inRaid and p:GetAttribute("InBattle") == raidId and inArena(p)
	end
	T.check(inRaid, "flow raid: ...each fighter stands on the colosseum's rim with InBattle set")
	-- snapshot the balances for the rewards
	local before = {}
	for _, p in ipairs({ ava, bo, cy, dee, eli, fay, gus }) do
		before[p] = { tokens = tokens(p), gems = gems(p), xp = xpOf(p, data.ActiveTeamKeys(p)), rec = record(p), pets = {} }
		local prof = data.GetProfile(p)
		for _, petId in ipairs(bc.EventPets()) do
			before[p].pets[petId] = prof.Pets[petId] or 0
		end
	end
	-- this raid's drops are certain: the tiers' gem and event-pet chances are raised to 1 (put back after the raid)
	F.savedTiers = {}
	for i, tier in ipairs(bc.Raid.Tiers) do
		F.savedTiers[i] = { tier.GemChance, tier.EventPetChance }
		tier.GemChance, tier.EventPetChance = 1, 1
	end

	-- the fight: ATTACK + SPECIAL, RETREAT from telegraphs; Gus leaves early, Fay joins late, Hal is too late
	local cursor = K.logSize()
	local t0 = Mock.Clock.now
	local opened0 = Mock.Clock.now
	local slot = 0
	local specials, telegraphs = 0, 0
	local gusLeft, fayJoined, halTried, eliLeft = false, false, false, false
	local recordUntil = Mock.Clock.now + 6
	while F.w.find(raidId) == nil and Mock.Clock.now - t0 < 420 do
		advance(0.5)
		if F.record and Mock.Clock.now > recordUntil then
			F.record = nil
		end
		local tele = eventsOf(ava, cursor, "Telegraph")
		telegraphs = telegraphs + #tele
		specials = specials + #eventsOf(ava, cursor, "Special")
		cursor = K.logSize()
		slot = slot % 3 + 1
		for _, p in ipairs(fighters) do
			if p.Parent and p:GetAttribute("InBattle") == raidId then
				if #tele > 0 then
					command(p, "Retreat")
				else
					command(p, "Attack")
					command(p, "Special", slot)
				end
			end
		end
		local since = Mock.Clock.now - opened0
		if not gusLeft and since > 12 then
			gusLeft = true
			local before1 = bs.GetRaidStatus().MaxHp
			local mG = K.logSize()
			request(gus, "LeaveRaid")
			advance(0.3)
			local eg = lastMsg(gus, "End", mG)
			local s1 = bs.GetRaidStatus()
			T.check(eg and eg.Outcome == "Left" and gus:GetAttribute("InBattle") == nil and s1 and s1.Players == 5 and s1.MaxHp < before1,
				"flow raid: Gus leaves early (BattleRequest LeaveRaid): 'End' Outcome Left, the boss sheds his share", before1 .. " -> " .. tostring(s1 and s1.MaxHp))
			advance(1.2)
			local mG2 = K.logSize()
			request(gus, "JoinRaid")
			T.check((toasted(gus, "You left this raid", mG2)) and gus:GetAttribute("InBattle") == nil, "flow raid: ...and he cannot join the same raid again")
			local leaveSeen = false
			for _, ev in ipairs(eventsOf(ava, mG, "Leave")) do
				leaveSeen = leaveSeen or ev.owner == gus.UserId
			end
			T.check(leaveSeen, "flow raid: ...the others get a Leave event for his units")
		end
		if not eliLeft and since > 25 then
			eliLeft = true
			local hpE = bs.GetRaidStatus().MaxHp
			local mE2 = K.logSize()
			Mock.RemovePlayer(eli)
			advance(0.4)
			local s3 = bs.GetRaidStatus()
			local leaveE = false
			for _, ev in ipairs(eventsOf(ava, mE2, "Leave")) do
				leaveE = leaveE or ev.owner == IDS.Eli
			end
			T.check(s3 and s3.Players == 4 and s3.MaxHp < hpE and leaveE, "flow raid: Eli disconnects mid-raid: his team leaves the floor (Leave event), the boss sheds his share",
				hpE .. " -> " .. tostring(s3 and s3.MaxHp))
		end
		if not fayJoined and since > 40 then
			fayJoined = true
			local hp0 = bs.GetRaidStatus().MaxHp
			local mF = K.logSize()
			request(fay, "JoinRaid")
			advance(0.4)
			local s2 = bs.GetRaidStatus()
			local fs = lastMsg(fay, "Start", mF)
			local spawnSeen = false
			for _, ev in ipairs(eventsOf(ava, mF, "Spawn")) do
				spawnSeen = spawnSeen or ev.owner == fay.UserId
			end
			T.check(fay:GetAttribute("InBattle") == raidId and fs and fs.Spectator == false and s2.MaxHp > hp0 and spawnSeen,
				"flow raid: Fay joins late (40 s in): her own 'Start', the boss HP grows, the others see her units Spawn", hp0 .. " -> " .. tostring(s2 and s2.MaxHp))
			fighters[#fighters + 1] = fay
		end
		if not halTried and since > 62 then
			halTried = true
			local mH = K.logSize()
			request(hal, "JoinRaid")
			T.check((toasted(hal, "Join the next one", mH)) and hal:GetAttribute("InBattle") == nil, "flow raid: Hal is too late (after the join window): refused with a toast")
		end
	end
	F.record = nil
	local res = F.w.find(raidId)
	if not T.check(res ~= nil, "flow raid: the raid ends", string.format("%.0f s", Mock.Clock.now - t0)) then
		return
	end
	T.info("*flow raid: " .. tostring(res.Reason) .. " after " .. tostring(res.Duration) .. " s (" .. specials .. " specials, " .. telegraphs .. " telegraphs)")
	local won = res.Reason == "BossDown"
	T.check(won, "flow raid: the fighters bring the boss down (" .. bossName .. ")", tostring(res.Reason))
	T.check(specials > 0 and telegraphs > 0, "flow raid: the fighters' SPECIAL presses cast specials and the boss telegraphed its attacks", specials .. " / " .. telegraphs)
	T.eq(F.w.count(raidId), 1, "flow raid: BattleEnded fired once for the raid")
	T.check(res.Mode == "Raid" and res.BossId == bossId and type(res.Damage) == "table" and type(res.Shares) == "table" and res.RewardsPaid == true
		and contains(res.Participants, gus.UserId),
		"flow raid: the result { Mode Raid, BossId, Damage, Shares, Participants, RewardsPaid }")
	advance(0.5)
	-- each fighter: the tier of their share, Double Rewards tokens, its gems, an event pet, XP, the record
	local eventSet = {}
	for _, petId in ipairs(bc.EventPets()) do
		eventSet[petId] = true
	end
	local good, detail = true, {}
	local shareSum = 0
	local fightersLeft = { ava, bo, cy, dee, fay }
	for _, p in ipairs(fightersLeft) do
		local uid = p.UserId
		local rw = res.Rewards[uid]
		local share = res.Shares[uid] or 0
		shareSum = shareSum + share
		-- nil below BattleCatalog.Raid.MinShare: that fighter earns nothing (Tier "None")
		local tier = bc.RaidTier(share, won) or { Id = "None", Tokens = 0, Gems = 0, Xp = 0 }
		local b = before[p]
		local paidTokens = tokens(p) - b.tokens
		local paidGems = gems(p) - b.gems
		local line = p.Name .. " " .. tostring(rw and rw.Tier) .. " " .. string.format("%.2f", share) .. " +" .. paidTokens .. "t +" .. paidGems .. "g " .. tostring(rw and rw.EventPet)
		local ok = rw ~= nil and rw.Tier == tier.Id and rw.Tokens == tier.Tokens * mult and paidTokens == rw.Tokens
			and rw.Gems == tier.Gems and paidGems == tier.Gems and contains(res.Winners, uid) and (tier.Id == "None" or rw.Double == true)
		if won then
			local pet = rw and rw.EventPet
			local prof = data.GetProfile(p)
			local owned = pet and eventSet[pet] and (prof.Pets[pet] or 0) == (b.pets[pet] or 0) + 1
			local marked = pet and record(p).EventPets[pet] == true and (b.rec.EventPets or {})[pet] ~= true
			local discovered = pet and data.IsDiscovered(p, pet) == true
			ok = ok and owned and marked and discovered
		end
		local okXp = gainedXp(p, b.xp, tier.Xp)
		ok = ok and okXp and (record(p).Raids or 0) == (b.rec.Raids or 0) + 1 and (record(p).RaidBestDamage or 0) >= floor(res.Damage[uid] or 0)
		if not ok then
			good = false
		end
		detail[#detail + 1] = line
	end
	T.check(good, "flow raid: each fighter got the tier of their damage share: Tokens x" .. mult .. " (Double Rewards), its Gems, an event pet they did not have (owned, discovered, Battle.EventPets), the tier's pet XP, Raids + 1",
		table.concat(detail, " | "))
	local allShares = 0
	for _, share in pairs(res.Shares) do
		allShares = allShares + share
	end
	T.check(abs(allShares - 1) < 0.001 and shareSum > 0.9, "flow raid: the damage shares add up to 1 (the fighters' plus what Gus and Eli dealt before leaving)", string.format("%.3f / %.3f", shareSum, allShares))
	T.check(res.Rewards[gus.UserId] == nil and tokens(gus) == before[gus].tokens and (record(gus).Raids or 0) == (before[gus].rec.Raids or 0),
		"flow raid: Gus, who left early, gets nothing")
	local se = stored(IDS.Eli)
	local seb = type(se) == "table" and type(se.Battle) == "table" and se.Battle or {}
	T.check(res.Rewards[IDS.Eli] == nil and contains(res.Participants, IDS.Eli) and (seb.Raids or 0) == (before[eli].rec.Raids or 0) and count(seb.EventPets) == 0,
		"flow raid: Eli, who disconnected, gets nothing (his save has no raid)", plain(seb))
	local endH = lastMsg(hal, "End", mO)
	T.check(endH and endH.BattleId == raidId and endH.Spectator == true and endH.Rewards == nil, "flow raid: Hal gets the raid's 'End' as a spectator (no rewards)")
	-- the client side of it
	local endA = lastMsg(ava, "End", mO)
	T.check(endA and endA.BattleId == raidId and endA.Outcome == "Win" and type(endA.Rewards) == "table" and endA.Rewards.Tier == res.Rewards[ava.UserId].Tier,
		"flow raid: 'End' tells Ava her tier and rewards")
	local shout = false
	local petOfAva = res.Rewards[ava.UserId] and res.Rewards[ava.UserId].EventPet
	if petOfAva then
		local petDef = PC().Get(petOfAva)
		shout = (toasted(hal, "won the event pet " .. tostring(petDef and petDef.Name), mO))
	end
	T.check(not won or shout, "flow raid: the others hear who won an event pet (Hal hears about Ava's)")
	local fighters = type(res.Fighters) == "table" and #res.Fighters or -1
	local okAll, allText = toasted(hal, bossName .. " was defeated by " .. fighters .. " raiders", mO)
	T.check(fighters == #fightersLeft and (not won or okAll), "flow raid: everyone hears how the raid went (" .. fighters .. " raiders: those still in at the end, not Gus and Eli who left)", allText)
	-- nothing is paid twice (EventService's fallback payer stays out of it)
	local after = {}
	for _, p in ipairs(fightersLeft) do
		after[p] = { tokens(p), gems(p) }
	end
	advance(5)
	local twice = false
	for _, p in ipairs(fightersLeft) do
		if tokens(p) ~= after[p][1] or gems(p) ~= after[p][2] then
			twice = true
		end
	end
	T.check(not twice, "flow raid: nothing more is paid afterwards (rewards exactly once)")
	-- EventService after the raid
	local stE = es.GetState()
	T.check(stE.LastRaid and stE.LastRaid.BossId == bossId and stE.LastRaid.Won == won and stE.LastRaid.Players == #fightersLeft and type(stE.LastRaid.Top) == "table",
		"flow raid: EventService.GetState().LastRaid sums it up (boss, won, " .. #fightersLeft .. " raiders still in at the end, top damage)", stE.LastRaid and plain(stE.LastRaid) or "nil")
	local mE = K.logSize()
	advance(5.5)
	local stAfter = lastArenaState(ava, mE)
	T.check(stAfter and stAfter.Raid == nil and stAfter.Next and stAfter.Next.Kind == "BossRaid" and stAfter.Next.StartsIn > 15 * 60,
		"flow raid: ArenaState afterwards: no raid, the next one ~20 minutes away", stAfter and plain(stAfter.Next) or "none")
	T.check(bs.GetRaidStatus() == nil and ava:GetAttribute("InBattle") == nil and fay:GetAttribute("InBattle") == nil, "flow raid: everyone is free again")
	-- Double Rewards end
	local mX = K.logSize()
	es.EndNow("DoubleRewards")
	T.check(not es.IsDoubleRewards() and not bs.IsDoubleRewards() and workspace:GetAttribute("DoubleRewards") == false and (toasted(ava, "Double Rewards are over", mX)),
		"flow double: Double Rewards end everywhere (toast)")
	F.facts.raidPet = petOfAva
	F.facts.raidDone = true
	for _, p in ipairs({ ava, bo, cy, dee, fay, gus, hal }) do
		if p.Parent then
			toLobby(p)
		end
	end
end)

----------------------------------------------------------------------------------------------------
-- p3flow_rejoin
----------------------------------------------------------------------------------------------------
S.p3flow_rejoin = scenario("p3flow_rejoin", function()
	if not ready("rejoin") then
		return
	end
	local data = DS()
	local ava, cy = F.p.Ava, F.p.Cy
	if not (ava and ava.Parent) then
		T.fail("flow rejoin: skipped, Ava is not in the game")
		return
	end
	local teams0 = data.GetTeams(ava)
	local rec0 = record(ava)
	local levels0 = {}
	for _, key in ipairs(teams0.Presets[1]) do
		levels0[key] = { data.GetPetLevel(ava, key) }
	end
	local tokens0 = tokens(ava)
	leave(ava)
	advance(1.5)
	-- the save
	local s = stored(IDS.Ava) or {}
	local st = type(s.Teams) == "table" and s.Teams or {}
	local sb = type(s.Battle) == "table" and s.Battle or {}
	T.check(type(st.Presets) == "table" and sameList(st.Presets[1], teams0.Presets[1]) and st.Active == teams0.Active,
		"flow rejoin: Ava's save holds her Teams (Presets, Active)", plain(st))
	T.check(type(sb.TrialCleared) == "table" and sb.TrialCleared[1] == true and sb.TrialCleared[2] == true and sb.TrialCleared[3] == true and sb.TrialBest == 3
		and sb.Trophies == rec0.Trophies and sb.Raids == rec0.Raids and (F.facts.raidPet == nil or (type(sb.EventPets) == "table" and sb.EventPets[F.facts.raidPet] == true)),
		"flow rejoin: ...and her Battle record (TrialCleared as booleans, trophies, raids, event pets)", plain(sb))
	-- back in the game
	local mark = K.logSize()
	ava = join("Ava")
	T.eq(plain(data.GetTeams(ava)), plain(teams0), "flow rejoin: her teams are restored exactly")
	T.eq(plain(record(ava)), plain(rec0), "flow rejoin: her battle record is restored exactly")
	local levelsOk = true
	for key, lv in pairs(levels0) do
		local l, x = data.GetPetLevel(ava, key)
		levelsOk = levelsOk and l == lv[1] and x == lv[2]
	end
	T.check(levelsOk and tokens(ava) == tokens0, "flow rejoin: her pet levels and tokens are restored")
	T.check(F.facts.raidPet == nil or (data.GetProfile(ava).Pets[F.facts.raidPet] or 0) >= 1, "flow rejoin: ...and the event pet she won")
	local sync = lastSync(ava, mark)
	T.check(sync and sync.Teams and sameList(sync.Teams.Presets[1], teams0.Presets[1]) and sync.Battle and sync.Battle.TrialBest == 3,
		"flow rejoin: ProfileSync on join carries the teams and the record")
	advance(6)
	local stA = lastArenaState(ava, mark)
	local row = nil
	for _, e in ipairs(stA and stA.Leaderboard or {}) do
		if e.UserId == ava.UserId then
			row = e
		end
	end
	T.check(row and row.Trophies == rec0.Trophies, "flow rejoin: the leaderboard lists her with her trophies again", row and plain(row) or "no row")
	-- Trial 4 is open (and forfeited)
	toPortal(ava)
	local r4 = runTrial(ava, 4, {
		stay = true,
		commands = false,
		duringStart = function()
			command(ava, "Forfeit")
		end,
	})
	T.check(r4.id ~= nil and r4.result and r4.result.Level == 4 and r4.result.Forfeit == true and r4.paid == 0,
		"flow rejoin: Trial 4 is open after the rejoin (started at the portal, forfeited: nothing paid)",
		tostring(r4.refused) .. " " .. (r4.result and plain(r4.result.Winners) .. " " .. tostring(r4.result.Reason) .. " forfeit " .. tostring(r4.result.Forfeit) or "no result") .. " paid " .. tostring(r4.paid))
	-- Eli comes back after leaving the raid mid-fight: no raid in his record, no raid to rejoin
	local eli = join("Eli")
	local re = record(eli)
	local want = F.facts.eliRecord or {}
	toArena(eli, 0, 8)
	advance(1.1)
	local mEl = K.logSize()
	request(eli, "JoinRaid")
	T.check(re.Trophies == want.Trophies and (re.Raids or 0) == 0 and count(re.EventPets) == 0 and (toasted(eli, "no boss raid", mEl)),
		"flow rejoin: Eli rejoins after his raid disconnect: his trophies kept, no raid / event pet in his record, no raid to rejoin", plain(re))
	-- Cy's finished tutorial pays nothing again
	if cy and cy.Parent then
		local tc0 = tokens(cy)
		leave(cy)
		cy = join("Cy")
		local stc = tutorial(cy)
		T.check((stc == nil or stc.Done == true) and tokens(cy) == tc0, "flow rejoin: Cy's finished battle chapter stays finished (no reward again)",
			stc and tostring(stc.Id) or "no state")
		local hc = data.GetHome(cy)
		T.check(data.GetTeams(cy).Slots == 4 and sameList(data.GetTeams(cy).Presets[1], F.facts.cyTeam) and hc and hc.Gym[1] == TEAMS.Cy[4],
			"flow rejoin: Cy keeps his team (Slots 4) and his pet keeps training in the Gym", listText(data.GetTeams(cy).Presets[1]))
	end
end)

----------------------------------------------------------------------------------------------------
-- p3flow_solo: Roblox Studio Play Solo (one player): a Boss Raid from the DEV button, fought alone
----------------------------------------------------------------------------------------------------
S.p3flow_solo = scenario("p3flow_solo", function()
	if not ready("solo") then
		return
	end
	local bs, es, data, bc = BS(), ES(), DS(), BC()
	local ava = F.p.Ava
	if not (ava and ava.Parent) then
		T.fail("flow solo: skipped, Ava is not in the game")
		return
	end
	local others = {}
	for name, p in pairs(F.p) do
		if name ~= "Ava" and p.Parent then
			others[#others + 1] = p
		end
	end
	K.removePlayers(others)
	clearRaids()
	toArena(ava, 0, 6)
	advance(2.2)
	local mark = K.logSize()
	devCommand(ava, "raid")
	local status = bs.GetRaidStatus()
	T.check(status ~= nil and (toasted(ava, "DEV: raid started", mark)), "flow solo: alone in the server, Ava starts a Boss Raid with the DEV button (DevCommand raid)",
		table.concat(toasts(ava, mark), " | "))
	if not status then
		return
	end
	local raidId = status.BattleId
	advance(1.1)
	request(ava, "JoinRaid")
	advance(0.3)
	local s1 = bs.GetRaidStatus()
	T.check(ava:GetAttribute("InBattle") == raidId and s1 and s1.Players == 1 and s1.MaxHp > 0, "flow solo: she joins alone: a raid for one team", s1 and plain(s1) or "no status")
	local tokens0, gems0, rec0 = tokens(ava), gems(ava), record(ava)
	local xp0 = xpOf(ava, data.ActiveTeamKeys(ava))
	local cursor = K.logSize()
	local slot = 0
	local t0 = Mock.Clock.now
	while F.w.find(raidId) == nil and Mock.Clock.now - t0 < 420 do
		advance(0.5)
		local tele = eventsOf(ava, cursor, "Telegraph")
		cursor = K.logSize()
		slot = slot % 3 + 1
		if ava:GetAttribute("InBattle") == raidId then
			if #tele > 0 then
				command(ava, "Retreat")
			else
				command(ava, "Attack")
				command(ava, "Special", slot)
			end
		end
	end
	local res = F.w.find(raidId)
	if T.check(res ~= nil, "flow solo: the solo raid ends", string.format("%.0f s", Mock.Clock.now - t0)) then
		local won = res.Reason == "BossDown"
		T.info("*flow solo raid: " .. tostring(res.Reason) .. " after " .. tostring(res.Duration) .. " s")
		local rw = res.Rewards[ava.UserId]
		local tier = bc.RaidTier(res.Shares[ava.UserId] or 0, won)
		T.check(rw and rw.Tier == tier.Id and rw.Tokens == tier.Tokens * doubled(rw) and tokens(ava) - tokens0 == rw.Tokens and gems(ava) - gems0 == rw.Gems
			and record(ava).Raids == (rec0.Raids or 0) + 1, "flow solo: her reward is the tier of her damage share (all of it), paid once", rw and plain(rw) or "none")
		local okXp = gainedXp(ava, xp0, tier.Xp)
		T.check(okXp, "flow solo: ...and her pets got the tier's XP")
		T.check(abs((res.Shares[ava.UserId] or 0) - 1) < 0.01, "flow solo: alone she dealt all of the damage")
	end
	-- the scheduled Double Rewards hour (BattleCatalog.Events: every EveryMinutes): announced ~2 minutes ahead, then it
	-- starts by itself, and a trial pays x2 while it runs
	local entryD = nil
	for _, e in ipairs(bc.Events.Schedule) do
		if e.Kind == "DoubleRewards" then
			entryD = e
		end
	end
	if es.IsDoubleRewards() then
		es.EndNow("DoubleRewards")
	end
	local leftD = es.SecondsUntil("DoubleRewards")
	if T.check(entryD ~= nil and type(leftD) == "number", "flow solo: a Double Rewards hour is scheduled", tostring(leftD)) then
		local announceD = tonumber(entryD.AnnounceSeconds) or 120
		toLobby(ava)
		if leftD > announceD + 5 then
			advance(leftD - announceD - 5)
		end
		clearRaids()
		local mD = K.logSize()
		local okAnnD = waitFor(function()
			return (toasted(ava, "Double Rewards hour in", mD))
		end, 15)
		T.check(okAnnD, "flow solo: the scheduled Double Rewards hour is announced ~2 minutes ahead (side toast)", table.concat(toasts(ava, mD), " | "))
		local startedD = waitFor(function()
			return es.IsDoubleRewards()
		end, announceD + 10)
		T.check(startedD and bs.IsDoubleRewards() and workspace:GetAttribute("DoubleRewards") == true and (toasted(ava, "Double Rewards for", mD)),
			"flow solo: ...and starts on time by itself (EventService, BattleService and the Workspace attribute agree; a toast)")
		local nextD = es.SecondsUntil("DoubleRewards")
		T.check(type(nextD) == "number" and nextD > (tonumber(entryD.EveryMinutes) or 180) * 60 - 60, "flow solo: ...and the next one is scheduled EveryMinutes later",
			tostring(nextD))
		local rd = runTrial(ava, 1, {})
		local wantD = bc.TrialRewards(1, true).Tokens
		T.check(rd.rw and rd.rw.Double == true and rd.paid == wantD, "flow solo: a trial during the scheduled hour pays x2 (" .. wantD .. ")",
			rd.rw and plain(rd.rw) or tostring(rd.refused))
		es.EndNow("DoubleRewards")
	end
	-- the end of the story: no battle of the flow's players is left behind (a scheduled raid that opened by itself during
	-- the wait is closed, so the scenarios after this one start without a raid)
	K.removePlayers({ ava })
	advance(5)
	clearRaids()
	local left = 0
	for _, b in ipairs(bs.ListBattles()) do
		for _, uid in ipairs(b.Players or {}) do
			for _, id in pairs(IDS) do
				if uid == id then
					left = left + 1
				end
			end
		end
	end
	T.eq(left, 0, "flow: no battle of the flow's players is left behind")
	T.check(bs.GetRaidStatus() == nil and es.IsDoubleRewards() == false, "flow: no raid and no Double Rewards left running at the end of the story")
	-- every message the flow's players got survives Roblox's remote serialization unchanged
	local flowIds = {}
	for _, id in pairs(IDS) do
		flowIds[id] = true
	end
	local bad, scanned, kinds = {}, 0, {}
	local log = Mock.RemoteLog
	for i = (F.logStart or 0) + 1, #log do
		local e = log[i]
		if e.kind ~= "server" and (e.kind == "all" or flowIds[e.userId]) then
			scanned = scanned + 1
			kinds[e.remote] = true
			local args = e.args or {}
			for a = 1, args.n or #args do
				local found = remoteUnsafe(args[a], e.remote .. "[" .. a .. "]" .. (a == 1 and type(args[1]) == "string" and ("=" .. args[1]) or ""), {}, 0)
				for _, line in ipairs(found) do
					if #bad < 6 then
						bad[#bad + 1] = line
					end
				end
			end
		end
	end
	local names = {}
	for name in pairs(kinds) do
		names[#names + 1] = name
	end
	table.sort(names)
	T.check(#bad == 0 and scanned > 1000, "flow: every message the flow's players got is remote-safe (" .. scanned .. " messages: " .. table.concat(names, ", ") .. ")",
		table.concat(bad, "; "))
	if F.w then
		F.w.stop()
	end
end)

return S
