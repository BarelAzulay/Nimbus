-- smoke_raid_flow.lua: boss raids, Task 5 (docs/superpowers/specs/2026-11-01-raid-boss-design.md: the flows end to end). Loaded by
-- tools/smoke.py in the server world and the client world:
--   raid_flow_new       (server) a new player (3 L1 Commons) on the tutorial's raid step walks into the gate: RaidJoined, the step completes,
--                       the fight is Starter on the floor, a wipe pays the Loss reward x0.4
--   raid_flow_dare      (server) a Mid player dares High at the gate, wins, is paid High's Gold and stamped; a second dare inside 20 minutes
--                       pays nothing
--   raid_flow_two_tiers (server) a Starter floor fight and a Max pocket fight at once: the Starter kill closes Starter only, the Max fight goes
--                       on, its end frees the pocket, the boss queued during both applies after the second end
--   raid_flow_hop       (server) the reward limit across servers: a win on A, a win 10 minutes later on B from the save pays nothing, a merge
--                       keeps the stamp, a loss on B pays and never starts the win limit
--   raid_flow_oldsave   (server) a save without the raid clocks has no limit, stale and junk requests change nothing, a saved tutorial Step 18
--                       lands on the gate step and completes on Next
--   client_raid_flow    (client) a Start with Raid, an End with Rewards.Tier "Cooldown": the result card says when rewards come again
-- White-box: the kills write the sim's boss (St is an upvalue of IsInBattle, as in smoke_raid_service.lua). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local advance = K.advance
	local waitFor = K.waitFor
	local Workspace = game:GetService("Workspace")

	local seq = 0
	local COMMON = { "pebble_pup", "honey_bunny", "puddle_frog" }
	local RETURN_DELAY = 4 -- BattleService's C.RETURN_DELAY

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
	local function DS()
		return req("server/Services/DataService")
	end
	local function BC()
		return req("shared/BattleCatalog")
	end
	local function TS()
		return req("server/Services/TutorialService")
	end
	local function Steps()
		return req("shared/TutorialSteps")
	end
	local function arenaInfo()
		local ab = req("server/Services/ArenaBuilder")
		return ab and ab.GetInfo and ab.GetInfo() or nil
	end

	-- the service's St (white-box, tests only)
	local function svcState()
		local f = BS().IsInBattle
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

	local function battleOf(id)
		local St = svcState()
		return St and id and St.battles[id] or nil
	end

	local function setTeam(p, level, pets)
		local data = DS()
		local prof = data.GetProfile(p)
		pets = pets or COMMON
		for _, id in ipairs(pets) do
			prof.Pets[id] = (prof.Pets[id] or 0) + 1
			prof.PetLevels[id] = { Level = level, Xp = 0 }
		end
		data.MarkDirty(p)
		local ok, why = data.SetTeam(p, 1, pets)
		if not ok then
			T.fail("(setup) SetTeam for " .. p.Name .. " failed", tostring(why))
		end
	end

	local function newPlayer(prefix, level, userId)
		seq = seq + 1
		local p = Mock.AddPlayer(prefix .. seq, userId or (984000 + seq))
		advance(1)
		if level then
			setTeam(p, level)
		end
		return p
	end

	local function toArena(p, dx, dz)
		Mock.Teleport(p, arenaInfo().Spawn * CFrame.new(dx or 0, 0, dz or 0))
		advance(0.05)
	end

	local function lastMsg(p, kind, fromIndex)
		local log = Mock.RemoteLog
		local found = nil
		for i = (fromIndex or 0) + 1, #log do
			local e = log[i]
			if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and e.args[1] == kind then
				found = e.args[2]
			end
		end
		return found
	end

	local function killBoss(id, by)
		local b = battleOf(id)
		if not b then
			T.fail("(setup) no battle " .. tostring(id))
			return
		end
		local team = b.Sim.teamByOwner[by.UserId]
		team.damage = team.damage + 1000
		b.Sim.boss.hp = 0
		b.Sim.boss.alive = false
	end

	local function wipe(id, by)
		local b = battleOf(id)
		if not b then
			T.fail("(setup) no battle " .. tostring(id))
			return
		end
		local team = b.Sim.teamByOwner[by.UserId]
		team.damage = team.damage + 1000
		for _, part in ipairs(b.PartList) do
			if not part.Left then
				b.Sim:Command(part.UserId, "Forfeit")
			end
		end
	end

	local function pocketCount()
		local holder = Workspace:FindFirstChild("BattlePockets")
		return holder and #holder:GetChildren() or 0
	end

	local function stepId(p)
		local st = TS().GetState(p)
		return st and not st.Done and st.Id or (st and st.Done and "done!") or nil
	end

	local function clearClosures()
		local St = svcState()
		for tier in pairs(St.raidClosed) do
			St.raidClosed[tier] = nil
		end
		St.raidFloorHiddenUntil = nil
	end

	local fakeNow = 1000
	local function setUp()
		local bs = BS()
		bs.EndRaids("Ended")
		advance(0.2)
		clearClosures()
		fakeNow = 1000
		bs.Debug = { RaidNow = function()
			return fakeNow
		end }
		bs.SetDoubleRewards(nil)
		return bs
	end

	local function scenario(name, fn)
		return guarded(name, function()
			if not K.needBoot() then
				return
			end
			if not BS() or not arenaInfo() or not arenaInfo().Gate then
				T.fail(name .. ": skipped, no BattleService / ArenaInfo.Gate in this build")
				return
			end
			local players = {}
			local function add(p)
				players[#players + 1] = p
				return p
			end
			local ok, err = pcall(fn, add, setUp())
			local bs = BS()
			bs.EndRaids("Ended")
			advance(0.2)
			bs.Debug = nil
			local alive = {}
			for _, p in ipairs(players) do
				if p.Parent then
					alive[#alive + 1] = p
				end
			end
			K.removePlayers(alive)
			advance(RETURN_DELAY + 1)
			clearClosures()
			if not ok then
				error(err, 0)
			end
			K.flushErrors(name)
		end)
	end

	------------------------------------------------------------------------------------------------
	-- raid_flow_new
	------------------------------------------------------------------------------------------------
	S.raid_flow_new = scenario("raid_flow_new", function(add, bs)
		local info = arenaInfo()
		local catalog, steps, data, tut = BC(), Steps(), DS(), TS()
		local p = add(newPlayer("FlowNew", 1))
		toArena(p, 2, 0)
		data.SetTutorial(p, { Step = steps.IndexOf.raid, Done = true, Gifted = true })
		tut.Reload(p)
		advance(0.6)
		T.eq(stepId(p), "raid", "raid flow new: (setup) a new player on the raid step, at the arena forum")
		local st = tut.GetState(p)
		T.check(st and st.CompleteOn == "RaidGate" and st.AlsoNext == true and st.Button == "Got it!" and st.Hint == "Walk through the boss gate",
			"raid flow new: the step asks for the walk through the gate, with Next as well", st and tostring(st.CompleteOn))
		T.check(st and st.Target and (st.Target.Position - info.Gate.CFrame.Position).Magnitude < 1, "raid flow new: the arrow points at the boss gate", st and st.Target and tostring(st.Target.Position))
		advance(2.5)
		T.eq(stepId(p), "raid", "raid flow new: at the forum it waits")

		local joined = nil
		local conn = bs.RaidJoined:Connect(function(who, id, tier)
			if who == p then
				joined = { id, tier }
			end
		end)
		Mock.Teleport(p, info.Gate.CFrame)
		waitFor(function()
			return stepId(p) ~= "raid"
		end, 3)
		conn:Disconnect()
		T.check(joined ~= nil and joined[2] == "Starter", "raid flow new: walking into the gate fires RaidJoined on Starter", joined and tostring(joined[2]))
		T.eq(stepId(p), steps.Steps[steps.ChapterStart[4]].Id, "raid flow new: ...and completes the step")
		local status = bs.GetRaidStatus()
		T.check(status.Fights.Starter and status.Fights.Starter.Floor == true and status.FloorTier == "Starter" and status.Active == true,
			"raid flow new: the fight is Starter's, on the floor")
		local tokens = data.GetTokens(p)
		local mark = K.logSize()
		wipe(joined and joined[1], p)
		advance(0.3)
		local msg = lastMsg(p, "End", mark)
		local loss = catalog.RaidTier(0.1, false, "Starter")
		T.check(msg and msg.Rewards and msg.Rewards.Tier == "Loss" and msg.Rewards.Tokens == loss.Tokens and loss.Tokens == 10,
			"raid flow new: a wipe pays the Loss reward x0.4", msg and msg.Rewards and tostring(msg.Rewards.Tokens))
		T.eq(data.GetTokens(p) - tokens, loss.Tokens, "raid flow new: ...into the player's tokens")
	end)

	------------------------------------------------------------------------------------------------
	-- raid_flow_dare
	------------------------------------------------------------------------------------------------
	S.raid_flow_dare = scenario("raid_flow_dare", function(add, bs)
		local gate = arenaInfo().Gate
		local data = DS()
		local p = add(newPlayer("FlowDare", 30))
		local rq = K.remoteFolder():FindFirstChild("BattleRequest")
		Mock.Teleport(p, gate.CFrame * CFrame.new(0, 3, -6))
		advance(1.1)
		T.eq(select(1, bs.RaidTierFor(p)), "Mid", "raid flow dare: (setup) a L30 team is Mid")
		fakeNow = 5000
		local mark = K.logSize()
		local tokens = data.GetTokens(p)
		Mock.FromClient(rq, p, "RaidDare", "High")
		advance(0.1)
		local status = bs.GetRaidStatus()
		T.check(status.Fights.High and p:GetAttribute("InBattle") == status.Fights.High.BattleId, "raid flow dare: the dare at the gate's prompt starts the High fight")
		killBoss(status.Fights.High and status.Fights.High.BattleId, p)
		advance(0.3)
		local msg = lastMsg(p, "End", mark)
		T.check(msg and msg.Rewards and msg.Rewards.Tier == "Gold" and msg.Rewards.Tokens == 500, "raid flow dare: a won dare pays High's Gold", msg and msg.Rewards and tostring(msg.Rewards.Tokens))
		T.eq(data.GetTokens(p) - tokens, 500, "raid flow dare: ...into the player's tokens")
		T.eq(data.GetBattle(p).RaidRewardAt, 5000, "raid flow dare: ...and starts the 20 minute limit")

		-- again inside the 20 minutes (after the tier's 60 s)
		advance(61)
		fakeNow = 5600
		Mock.Teleport(p, gate.CFrame * CFrame.new(0, 3, -6))
		advance(1.1)
		mark = K.logSize()
		tokens = data.GetTokens(p)
		Mock.FromClient(rq, p, "RaidDare", "High")
		advance(0.1)
		status = bs.GetRaidStatus()
		T.check(status.Fights.High ~= nil, "raid flow dare: a second dare may be fought")
		killBoss(status.Fights.High and status.Fights.High.BattleId, p)
		advance(0.3)
		msg = lastMsg(p, "End", mark)
		T.check(msg and msg.Rewards and msg.Rewards.Tier == "Cooldown" and msg.Rewards.Tokens == 0 and msg.Rewards.AgainIn == 600, "raid flow dare: ...and pays nothing inside the 20 minutes", msg and msg.Rewards and tostring(msg.Rewards.Tier))
		T.eq(data.GetTokens(p), tokens, "raid flow dare: ...no tokens")
		T.eq(data.GetBattle(p).RaidRewardAt, 5000, "raid flow dare: ...the limit does not restart")
	end)

	------------------------------------------------------------------------------------------------
	-- raid_flow_two_tiers
	------------------------------------------------------------------------------------------------
	S.raid_flow_two_tiers = scenario("raid_flow_two_tiers", function(add, bs)
		local catalog = BC()
		bs.SetRaidBoss(catalog.BossOrder[1])
		local starter = add(newPlayer("FlowS", 10))
		local max = add(newPlayer("FlowX", 90))
		toArena(starter, 2, 0)
		toArena(max, -2, 0)
		local pockets = pocketCount()
		local _, idS = bs.EnterRaid(starter)
		local _, idX = bs.EnterRaid(max)
		local status = bs.GetRaidStatus()
		T.check(status.Fights.Starter and status.Fights.Starter.Floor == true and status.Fights.Max and status.Fights.Max.Floor == false,
			"raid flow two tiers: Starter on the floor, Max in a pocket, at once")
		T.eq(pocketCount(), pockets + 1, "raid flow two tiers: the Max fight has its pocket")
		local nextBoss = catalog.BossOrder[2]
		local okSet, how = bs.SetRaidBoss(nextBoss)
		T.check(okSet == true and how == "queued", "raid flow two tiers: the rotation waits for the fights", tostring(how))

		killBoss(idS, starter)
		advance(0.3)
		status = bs.GetRaidStatus()
		T.check(status.Closed.Starter and status.Closed.Starter > 58 and status.Closed.Max == nil and status.Fights.Max ~= nil and status.Fights.Starter == nil,
			"raid flow two tiers: the Starter kill closes Starter only; the Max fight goes on")
		T.check(status.FloorHiddenIn > 58 and status.Active == false, "raid flow two tiers: the floor is hidden for the return")
		T.check(status.BossId == catalog.BossOrder[1], "raid flow two tiers: the queued boss still waits while Max fights", tostring(status.BossId))

		killBoss(idX, max)
		advance(0.3)
		status = bs.GetRaidStatus()
		T.check(status.Fights.Max == nil and status.Closed.Max ~= nil and status.FloorHiddenIn <= 60, "raid flow two tiers: the Max fight ends with its own closure")
		T.eq(status.BossId, nextBoss, "raid flow two tiers: the rotation queued during both applies after the second end")
		advance(RETURN_DELAY + 0.5)
		T.eq(pocketCount(), pockets, "raid flow two tiers: the pocket is freed")
		T.check(K.root(max).Position.Y < 1000, "raid flow two tiers: the Max raider is back at the gate")
	end)

	------------------------------------------------------------------------------------------------
	-- raid_flow_hop: the two-cache helpers of smoke_p5_flow.lua's p5flow_merge
	------------------------------------------------------------------------------------------------
	local function hookedSignals()
		local out = { game:GetService("Players").PlayerRemoving }
		local folder = K.remoteFolder and K.remoteFolder()
		for _, name in ipairs({ "RequestProfile", "SettingsSet" }) do
			local remote = folder and folder:FindFirstChild(name)
			if remote then
				out[#out + 1] = remote.OnServerEvent
			end
		end
		return out
	end

	local function connectionMarks()
		local marks = {}
		for _, sig in ipairs(hookedSignals()) do
			local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
			marks[#marks + 1] = { conns = conns, n = conns and #conns or 0 }
		end
		return marks
	end

	local function dropHooks(marks)
		for _, m in ipairs(marks) do
			if m.conns then
				for i = #m.conns, m.n + 1, -1 do
					local conn = m.conns[i]
					if type(conn) == "table" and conn.Disconnect then
						conn:Disconnect()
					end
				end
			end
		end
	end

	-- a clone of the live DataService as "another server" on the same mock store
	local function otherServer(name)
		local inst = K.moduleInstance("server/Services/DataService")
		local marks = connectionMarks()
		local copy = inst:Clone()
		copy.Name = name
		copy.Parent = inst.Parent
		local ok, module = pcall(require, copy)
		if not ok or type(module) ~= "table" then
			copy:Destroy()
			dropHooks(marks)
			return nil, tostring(module)
		end
		return module, function()
			copy:Destroy()
			dropHooks(marks)
		end
	end

	local function storeKey(userId)
		return K.config().Tokens.DataStoreName .. "/u_" .. userId
	end

	local function stored(userId)
		return Mock.DataStore.Data[storeKey(userId)]
	end

	S.raid_flow_hop = scenario("raid_flow_hop", function(add, bs)
		local data = DS()
		local userId = 984901
		local p = newPlayer("FlowHop", 10, userId)
		toArena(p, 2, 0)

		-- server A: a win at 5000, saved
		fakeNow = 5000
		local mark = K.logSize()
		local _, idA = bs.EnterRaid(p)
		killBoss(idA, p)
		advance(0.3)
		local msg = lastMsg(p, "End", mark)
		T.check(msg and msg.Rewards and msg.Rewards.Tier == "Gold", "raid flow hop: server A pays the win", msg and msg.Rewards and tostring(msg.Rewards.Tier))
		T.eq(data.GetBattle(p).RaidRewardAt, 5000, "raid flow hop: ...and stamps it")
		T.eq(data.Save(p), true, "raid flow hop: (server A saves)")
		T.eq((stored(userId).Battle or {}).RaidRewardAt, 5000, "raid flow hop: the store holds the stamp")

		-- server B: the player hops; this server only has the save
		K.removePlayers({ p })
		advance(RETURN_DELAY + 1)
		clearClosures()
		p = add(Mock.AddPlayer("FlowHopB", userId))
		advance(1)
		T.eq(data.GetBattle(p).RaidRewardAt, 5000, "raid flow hop: server B loads the stamp from the save")
		fakeNow = 5600
		T.eq(bs.RaidRewardStatus(p).WinIn, 600, "raid flow hop: ...the limit runs on: 10 minutes left")
		toArena(p, 2, 0)
		mark = K.logSize()
		local tokens = data.GetTokens(p)
		local _, idB = bs.EnterRaid(p)
		killBoss(idB, p)
		advance(0.3)
		msg = lastMsg(p, "End", mark)
		T.check(msg and msg.Rewards and msg.Rewards.Tier == "Cooldown" and msg.Rewards.AgainIn == 600 and msg.Rewards.Tokens == 0, "raid flow hop: a win 10 minutes later on server B pays nothing and says when",
			msg and msg.Rewards and tostring(msg.Rewards.Tier) .. " " .. tostring(msg.Rewards.AgainIn))
		T.eq(data.GetTokens(p), tokens, "raid flow hop: ...no tokens")

		-- a third server's session, loaded before B's win: nothing newer on either side, the merge keeps 5000
		local other, release = otherServer("DataServiceRaidHop")
		if not T.check(other ~= nil, "raid flow hop: a second DataService copy loads as another server", tostring(release)) then
			return
		end
		local okRun, errRun = pcall(function()
			other.Load(p)
			T.eq(other.GetBattle(p).RaidRewardAt, 5000, "raid flow hop: (the other server reads the stamp)")
			T.eq(data.Save(p), true, "raid flow hop: (server B saves)")
			T.eq(other.Save(p), true, "raid flow hop: (the other server saves over it)")
			T.eq((stored(userId).Battle or {}).RaidRewardAt, 5000, "raid flow hop: a merge with nothing newer keeps 5000")

			-- a loss on B at 5700: paid, and the merge keeps it against a session that has none
			advance(0.3)
			clearClosures()
			fakeNow = 5700
			toArena(p, 2, 0)
			mark = K.logSize()
			tokens = data.GetTokens(p)
			local _, idL = bs.EnterRaid(p)
			wipe(idL, p)
			advance(0.3)
			msg = lastMsg(p, "End", mark)
			T.check(msg and msg.Rewards and msg.Rewards.Tier == "Loss" and msg.Rewards.Tokens == 10, "raid flow hop: a loss on B pays the loss reward", msg and msg.Rewards and tostring(msg.Rewards.Tokens))
			T.eq(data.GetTokens(p) - tokens, 10, "raid flow hop: ...into the player's tokens")
			T.eq(data.GetBattle(p).RaidRewardAt, 5000, "raid flow hop: ...and never touches the win limit")
			T.eq(data.Save(p), true, "raid flow hop: (server B saves the loss)")
			T.eq(other.GetBattle(p).RaidLossAt or 0, 0, "raid flow hop: (the other server's session has no loss)")
			T.eq(other.Save(p), true, "raid flow hop: (the other server saves over it)")
			local rec = stored(userId).Battle or {}
			T.eq(rec.RaidLossAt, 5700, "raid flow hop: the merged RaidLossAt is 5700")
			T.eq(rec.RaidRewardAt, 5000, "raid flow hop: ...and RaidRewardAt is still 5000")
		end)
		release()
		if not okRun then
			error(errRun, 0)
		end
	end)

	------------------------------------------------------------------------------------------------
	-- raid_flow_oldsave
	------------------------------------------------------------------------------------------------
	S.raid_flow_oldsave = scenario("raid_flow_oldsave", function(add, bs)
		local data, steps, tut = DS(), Steps(), TS()
		local userId = 984902
		local p = newPlayer("FlowOld", 30, userId)
		T.eq(data.Save(p), true, "raid flow oldsave: (a save)")
		K.removePlayers({ p })
		advance(1)
		-- a save from before this release: no raid clocks, on tutorial step 18 of the old raid chapter
		local rec = stored(userId)
		if not T.check(type(rec) == "table", "raid flow oldsave: (the record is stored)") then
			return
		end
		rec.Battle = type(rec.Battle) == "table" and rec.Battle or {}
		rec.Battle.RaidRewardAt, rec.Battle.RaidLossAt = nil, nil
		rec.Tutorial = { Step = steps.IndexOf.raid, Done = false, Gifted = true }
		p = add(Mock.AddPlayer("FlowOldB", userId))
		advance(1.5)
		local battle = data.GetBattle(p)
		T.check(battle.RaidRewardAt == 0 and battle.RaidLossAt == 0, "raid flow oldsave: the clocks load as 0", tostring(battle.RaidRewardAt))
		T.check(bs.RaidRewardStatus(p).WinIn == 0 and bs.RaidRewardStatus(p).LossIn == 0, "raid flow oldsave: no limit: WinIn 0, LossIn 0")

		-- a stale Join and a junk dare: no fight, no reply, no write
		local rq = K.remoteFolder():FindFirstChild("BattleRequest")
		toArena(p, 2, 0)
		advance(1.1)
		local before = data.GetBattle(p)
		local mark = K.logSize()
		Mock.FromClient(rq, p, "JoinRaid")
		advance(1.1)
		Mock.FromClient(rq, p, "RaidDare", 42)
		advance(1.1)
		T.check(next(bs.GetRaidStatus().Fights) == nil and p:GetAttribute("InBattle") == nil, "raid flow oldsave: a stale Join and a junk dare start nothing")
		T.eq(lastMsg(p, "Start", mark), nil, "raid flow oldsave: ...no Start")
		local replies = 0
		for i = mark + 1, #Mock.RemoteLog do
			local e = Mock.RemoteLog[i]
			if e.remote == "BattleRequest" and e.kind == "client" and e.userId == userId then
				replies = replies + 1
			end
		end
		T.eq(replies, 0, "raid flow oldsave: ...and no reply on the request remote")
		local after = data.GetBattle(p)
		T.check(after.Raids == before.Raids and after.RaidRewardAt == 0 and after.RaidLossAt == 0, "raid flow oldsave: ...and nothing written")

		-- the saved tutorial step
		T.eq(stepId(p), "raid", "raid flow oldsave: a saved Step 18 lands on the raid step")
		local st = tut.GetState(p)
		T.check(st and st.CompleteOn == "RaidGate" and tostring(st.Text):find("back gate", 1, true) ~= nil, "raid flow oldsave: ...the gate step", st and tostring(st.Text))
		T.eq(tut.HandleEvent(p, "Next"), true, "raid flow oldsave: Next completes it")
		advance(0.4)
		T.eq(stepId(p), steps.Steps[steps.ChapterStart[4]].Id, "raid flow oldsave: ...on to chapter 4")
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
	local LocalPlayer = Players.LocalPlayer

	local function req(path)
		local root, rest = path:match("^(%a+)/(.+)$")
		local inst = Mock.GetPath(ROOTS[root] .. "/" .. rest)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end

	local function battleText(pattern)
		local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui"):FindFirstChild("NimbusBattle")
		for _, d in ipairs(gui and gui:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and KC.isShown(d) and tostring(d.Text):find(pattern) then
				return true
			end
		end
		return false
	end

	-- a real BattleSim's Start, as the server sends it to a raider
	local function startRaid(id)
		local Sim = req("shared/BattleSim")
		local me = LocalPlayer.UserId
		local pets = {}
		for i, key in ipairs({ "pebble_pup", "honey_bunny", "puddle_frog" }) do
			pets[i] = { Key = key, PetId = key, Level = 5, Tier = "Normal", Slot = i }
		end
		local sim = Sim.new({ Mode = "Raid", Seed = 3, Id = id, Boss = "storm_titan", RaidTier = "Starter", Specials = false, Teams = { { Owner = me, Side = 1, Pets = pets } } })
		local p = sim:Describe()
		p.BattleId = id
		p.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
		p.Names = { [tostring(me)] = LocalPlayer.Name }
		p.Side = 1
		p.Spectator = false
		p.T = sim:Time()
		p.Raid = { Tier = "Starter", Pocket = false, BossId = "storm_titan" }
		local team = sim:TeamOf(me)
		p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed, Cooldowns = { Element = 0, Dash = 0, Swap = 0, Buff = {} } }
		LocalPlayer:SetAttribute("InBattle", id)
		KC.toClient("BattleState", "Start", p, id)
		KC.advance(0.6)
	end

	local function endRaid(id, rewards, won)
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.toClient("BattleState", "End", { BattleId = id, Mode = "Raid", Outcome = won and "Win" or "Loss", Won = won, Spectator = false, Reason = won and "BossDown" or "Wipe", Rewards = rewards }, id)
		KC.advance(0.6)
	end

	S.client_raid_flow = guarded("client_raid_flow", function()
		startRaid("smoke_raidflow_1")
		T.check(battleText("BOSS RAID %- Starter"), "raid flow client: the mode line names the tier")
		endRaid("smoke_raidflow_1", { Tier = "Cooldown", AgainIn = 600, Tokens = 0, Xp = 0, Share = 1, Damage = 1000 }, true)
		T.check(battleText("Rewards again in 10:00"), "raid flow client: a win inside the limit: the card says when rewards come again")
		T.check(not battleText("Cooldown tier"), "raid flow client: ...and shows no medal called Cooldown")
		KC.advance(14)
		startRaid("smoke_raidflow_2")
		endRaid("smoke_raidflow_2", { Tier = "Gold", Tokens = 200, Xp = 160, Share = 1, Damage = 1000 }, true)
		T.check(battleText("Gold tier") and not battleText("Rewards again"), "raid flow client: a paid win shows its medal, no limit line")
		KC.advance(14)
		-- a shutdown pays like a loss (payRaid): the card says so
		startRaid("smoke_raidflow_3")
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.toClient("BattleState", "End", { BattleId = "smoke_raidflow_3", Mode = "Raid", Outcome = "Loss", Won = false, Spectator = false, Reason = "Shutdown", Rewards = { Tier = "Loss", Tokens = 10, Xp = 8, Share = 0.9, Damage = 1000 } }, "smoke_raidflow_3")
		KC.advance(0.6)
		T.check(battleText("pays like a loss") and not battleText("still counts"), "raid flow client: a shutdown's card says the fight pays like a loss, as the server paid it")
		KC.advance(14)
		KC.flushErrors("client_raid_flow")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
