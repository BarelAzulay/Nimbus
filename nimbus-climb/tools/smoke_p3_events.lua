-- smoke_p3_events.lua: Phase 3 "events" (ARCHITECTURE_V3.md "Phase 3: Pet battles" -> special events, the "Phase 3
-- build contract": EventService + BossBuilder + the EventOnly pets, and its "Interfaces between the Phase 3 modules":
-- ArenaState, EventService.StartNow, the developer /raid). Server world only (listed in server_files of tools/smoke.py):
--   p3events_pets      the EventOnly pets: 2-3 of them, full catalog pets (Pets / Get / Index group / PetBuilder), never
--                      in a roulette (PetCatalog RollPet / GetOdds / PossiblePets / IsRollable / ListByRarity, the gems-only
--                      Secret roulette of GemService), BattleCatalog.EventPets() lists them, PetCatalog.Validate() passes
--   p3events_bosses    BossBuilder: every BattleCatalog boss builds (High + Low) as a big detailed voxel model with the
--                      named joints (Pivot attributes), Root as PrimaryPart, anchored non-colliding parts, sane part
--                      budgets and size, effect points, every pose animates (no NaN, joints move, the root CFrame is
--                      followed), SetEnraged recolours the glow and back, telegraph colours for every attack
--   p3events_schedule  (booted) the scheduler: ArenaState on join (contract shape), the raid announced ~2 minutes ahead
--                      with a side toast and fast ArenaState updates, the raid opened through BattleService at its time,
--                      the toast, a raid nobody joins closes and is reported, the next one is ~20 minutes away
--   p3events_raid      (booted) StartNow("BossRaid") / EndNow, a second raid refused, Double Rewards (multiplier, Workspace
--                      attribute, BattleService sees it, RaidTierFor), the fallback raid payer (only when BattleService
--                      did not pay, exactly once), the event pet shout-out, the developer /raid command + help (<= 90)
-- Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance = K.advance

local S = {}
local seq = 0

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

local function ES()
	return req("server/Services/EventService")
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
local function PC()
	return req("shared/PetCatalog")
end

local function newPlayer(prefix)
	seq = seq + 1
	local p = Mock.AddPlayer(prefix .. seq, 975000 + seq)
	advance(1.0)
	return p
end

local function toasts(p, fromIndex)
	local out = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, fromIndex or 0)) do
		out[#out + 1] = tostring(e.args[1])
	end
	return out
end

local function toasted(p, pattern, fromIndex)
	for _, text in ipairs(toasts(p, fromIndex)) do
		if text:find(pattern) then
			return true, text
		end
	end
	return false, table.concat(toasts(p, fromIndex), " | ")
end

local function arenaStates(p, fromIndex)
	local out = {}
	for _, e in ipairs(K.remotesFor("ArenaState", p.UserId, fromIndex or 0)) do
		out[#out + 1] = e.args[1]
	end
	return out
end

local function finiteVec(v)
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function idSet(list)
	local s = {}
	for _, v in ipairs(list or {}) do
		s[type(v) == "table" and v.Id or v] = true
	end
	return s
end

----------------------------------------------------------------------------------------------------
-- p3events_pets
----------------------------------------------------------------------------------------------------
S.p3events_pets = guarded("p3events_pets", function()
	local pc = PC()
	if not pc then
		T.fail("event pets: shared/PetCatalog did not load")
		return
	end
	local Config = K.config()
	T.check(type(pc.EventPets) == "function" and type(pc.IsEventOnly) == "function", "event pets: PetCatalog.EventPets / IsEventOnly exist")
	local events = type(pc.EventPets) == "function" and pc.EventPets() or {}
	T.check(#events >= 2 and #events <= 3, "event pets: 2-3 EventOnly pets in the catalog", tostring(#events))
	local ok, problems = pc.Validate()
	T.check(ok == true, "event pets: PetCatalog.Validate() passes", table.concat(problems or {}, "; "))
	local bc = BC()
	if bc and type(bc.EventPets) == "function" then
		local a, b = idSet(bc.EventPets()), idSet(events)
		local same = true
		for id in pairs(a) do
			same = same and b[id] == true
		end
		for id in pairs(b) do
			same = same and a[id] == true
		end
		T.check(same, "event pets: BattleCatalog.EventPets() lists exactly the EventOnly pets")
	end
	local inPets = idSet(pc.Pets)
	local inGroups = {}
	for _, g in ipairs(pc.IndexGroups()) do
		for _, def in ipairs(g.Pets) do
			inGroups[def.Id] = g.Id
		end
	end
	local PB = req("shared/PetBuilder")
	for _, def in ipairs(events) do
		T.check(def.EventOnly == true and pc.IsEventOnly(def.Id) and inPets[def.Id] and pc.Get(def.Id) == def, def.Id .. ": a full catalog pet marked EventOnly")
		T.check(inGroups[def.Id] == def.Rarity, def.Id .. ": shown in the Pet Index (its " .. tostring(def.Rarity) .. " group)", tostring(inGroups[def.Id]))
		local listed = false
		for _, r in ipairs(Config.Rarities) do
			for _, other in ipairs(pc.ListByRarity(r.Id)) do
				if other == def then
					listed = true
				end
			end
		end
		local withEvent = false
		for _, other in ipairs(pc.ListByRarity(def.Rarity, true)) do
			withEvent = withEvent or other == def
		end
		T.check(not listed and withEvent, def.Id .. ": not in any roulette pool (ListByRarity), only in ListByRarity(rarity, true)")
		T.check(pc.IsRollable(def.Id) == false, def.Id .. ": IsRollable is false")
		if PB and type(PB.Build) == "function" then
			local okB, model = pcall(PB.Build, def, { Detail = "High" })
			local n = 0
			if okB and model then
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						n = n + 1
					end
				end
			end
			T.check(okB and model ~= nil and n > 40 and n <= 360, def.Id .. ": PetBuilder builds it (detailed voxel, " .. n .. " parts)", okB and "" or tostring(model))
		end
	end
	-- the roulettes never offer them
	local eventSet = idSet(events)
	local leaks = {}
	for _, r in ipairs(Config.Roulettes) do
		for _, o in ipairs(pc.GetOdds(r.Id)) do
			if eventSet[o.PetId] then
				leaks[#leaks + 1] = r.Id .. " odds: " .. o.PetId
			end
		end
		for _, def in ipairs(pc.PossiblePets(r.Id)) do
			if eventSet[def.Id] then
				leaks[#leaks + 1] = r.Id .. " possible: " .. def.Id
			end
		end
	end
	local Util = req("shared/Util")
	local rng = Util and Util.NewRng and Util.NewRng(4242)
	local rolls = 0
	if rng then
		for _, r in ipairs(Config.Roulettes) do
			for _ = 1, 600 do
				local id = pc.RollPet(r.Id, rng)
				rolls = rolls + 1
				if eventSet[id] then
					leaks[#leaks + 1] = r.Id .. " rolled " .. id
				end
			end
		end
	end
	local GS = req("server/Services/GemService")
	local secret = Config.Gems and Config.Gems.SecretRoulette
	if GS and secret and type(GS.RollPet) == "function" then
		for _, o in ipairs(GS.GetOdds(secret.Id) or {}) do
			if eventSet[o.PetId] then
				leaks[#leaks + 1] = "Secret roulette odds: " .. o.PetId
			end
		end
		for _, def in ipairs(GS.PossiblePets(secret.Id) or {}) do
			if eventSet[def.Id] then
				leaks[#leaks + 1] = "Secret roulette possible: " .. def.Id
			end
		end
		for _ = 1, 3000 do
			local id = GS.RollPet(secret.Id, rng)
			rolls = rolls + 1
			if eventSet[id] then
				leaks[#leaks + 1] = "Secret roulette rolled " .. id
				break
			end
		end
	end
	T.check(#leaks == 0, "event pets: no roulette (token roulettes + the gems-only Secret roulette, " .. rolls .. " rolls) ever offers or rolls one", table.concat(leaks, ", ", 1, math.min(#leaks, 6)))
end)

----------------------------------------------------------------------------------------------------
-- p3events_bosses
----------------------------------------------------------------------------------------------------
S.p3events_bosses = guarded("p3events_bosses", function()
	local BB = req("shared/BossBuilder")
	if not BB then
		T.fail("bosses: shared/BossBuilder did not load")
		return
	end
	local bc = BC()
	local ids = BB.Ids()
	T.check(#ids >= 4, "bosses: BossBuilder.Ids() lists the roster", table.concat(ids, ","))
	if bc and type(bc.BossOrder) == "table" then
		T.eq(table.concat(ids, ","), table.concat(bc.BossOrder, ","), "bosses: Ids() = BattleCatalog.BossOrder")
	end
	T.check(BB.Build("no_such_boss") == nil and BB.Build(nil) == nil, "bosses: Build of an unknown id is nil (never raises)")
	for _, id in ipairs(ids) do
		local high = BB.Build(id, { Detail = "High" })
		local low = BB.Build(id, { Detail = "Low" })
		if not T.check(high ~= nil and low ~= nil, id .. ": builds at High and Low detail") then
			break
		end
		high.Parent = workspace
		T.check(high.Name == "Boss_" .. id and high.PrimaryPart ~= nil and high.PrimaryPart.Name == "Root" and high:GetAttribute("BossId") == id,
			id .. ": Model Boss_" .. id .. " with Root as PrimaryPart and the BossId attribute")
		local rig = BB.Rigs[id]
		local jointsOk, missing = true, {}
		for _, name in ipairs(rig.Order) do
			local g = high:FindFirstChild(name)
			if not g or not g:IsA("Model") or typeof(g:GetAttribute("Pivot")) ~= "Vector3" or type(g:GetAttribute("JointParent")) ~= "string" then
				jointsOk = false
				missing[#missing + 1] = name
			end
		end
		T.check(jointsOk, id .. ": every named joint (" .. table.concat(rig.Order, ", ") .. ") is a Model with Pivot / JointParent", table.concat(missing, ","))
		local nHigh, nLow, bad, scripts = 0, BB.PartCount(low), 0, 0
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, d in ipairs(high:GetDescendants()) do
			if d:IsA("BasePart") then
				nHigh = nHigh + 1
				if not d.Anchored or d.CanCollide or d.CanQuery then
					bad = bad + 1
				end
				x0, x1 = math.min(x0, d.Position.X - d.Size.X / 2), math.max(x1, d.Position.X + d.Size.X / 2)
				z0, z1 = math.min(z0, d.Position.Z - d.Size.Z / 2), math.max(z1, d.Position.Z + d.Size.Z / 2)
			elseif d:IsA("LuaSourceContainer") or d:IsA("Decal") or d:IsA("Texture") then
				scripts = scripts + 1
			end
		end
		T.check(bad == 0 and scripts == 0, id .. ": every part anchored, not collidable / queryable; no scripts or decals")
		T.check(nHigh >= 300 and nHigh <= 1000, id .. ": High detail is a detailed voxel model within budget (300-1000 parts)", tostring(nHigh))
		T.check(nLow < nHigh and nLow <= 760, id .. ": Low detail has fewer parts (<= 760)", nLow .. " vs " .. nHigh)
		local h = BB.GetHeight(high)
		T.check(h >= 17 and h <= 32 and (x1 - x0) <= 52 and (z1 - z0) <= 52, id .. ": big but fits the raid floor (17-32 studs tall, <= 52 wide)", string.format("%.1f tall, %.1f x %.1f", h, x1 - x0, z1 - z0))
		local fxOk, fxBad = true, {}
		for name in pairs(rig.Fx or {}) do
			local p = BB.FxPoint(high, name)
			if typeof(p) ~= "Vector3" or not finiteVec(p) then
				fxOk = false
				fxBad[#fxBad + 1] = name
			end
		end
		T.check(fxOk and BB.FxPoint(high, "Mouth") ~= nil and BB.FxPoint(high, "Core") ~= nil, id .. ": effect points (Fx_Mouth, Fx_Core, ...) resolve to positions", table.concat(fxBad, ","))
		-- poses
		local probe = nil
		for _, name in ipairs(rig.Order) do
			if name ~= "Body" and name ~= "Base" then
				local g = high:FindFirstChild(name)
				probe = probe or (g and g:FindFirstChildWhichIsA("BasePart"))
			end
		end
		local poseOk, nan = true, 0
		local idlePos = nil
		BB.Animate(high, "Idle", 0, {})
		idlePos = probe and probe.Position
		local moved = false
		for _, pose in ipairs(BB.Poses) do
			for _, p in ipairs({ 0, 0.5, 1 }) do
				local okA = BB.Animate(high, pose, 1.3, { Progress = p, Enraged = pose == "Enrage" })
				poseOk = poseOk and okA == true
			end
			if pose == "Windup" and probe and idlePos and (probe.Position - idlePos).Magnitude > 1 then
				moved = true
			end
		end
		for _, d in ipairs(high:GetDescendants()) do
			if d:IsA("BasePart") and not finiteVec(d.Position) then
				nan = nan + 1
			end
		end
		T.check(poseOk and nan == 0, id .. ": every pose (" .. table.concat(BB.Poses, ", ") .. ") animates without NaN", tostring(nan))
		T.check(moved, id .. ": a Windup really moves a joint (" .. (probe and probe.Parent.Name or "?") .. ")")
		local target = CFrame.new(150, 20, -40) * CFrame.Angles(0, math.rad(90), 0)
		BB.Animate(high, "Idle", 2, { CFrame = target })
		local far = 0
		for _, d in ipairs(high:GetDescendants()) do
			if d:IsA("BasePart") and (d.Position - target.Position).Magnitude > 40 then
				far = far + 1
			end
		end
		T.check((high.PrimaryPart.Position - target.Position).Magnitude < 0.01 and far == 0, id .. ": Animate follows the root CFrame (the client's interpolated boss position)")
		-- enrage glow
		local glow = nil
		for _, d in ipairs(high:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "Eye" or d.Name == "Glow" or d.Name == "Magma" or d.Name == "Rune" or d.Name == "Bolt") then
				glow = d
				break
			end
		end
		if T.check(glow ~= nil, id .. ": has glowing parts (Neon)") then
			local before = glow.Color
			BB.SetEnraged(high, true)
			local changed = glow.Color ~= before
			BB.SetEnraged(high, false)
			T.check(changed and glow.Color == before and glow.Material == Enum.Material.Neon, id .. ": SetEnraged recolours the glow and restores it")
		end
		-- telegraph colours
		local colors = BB.Colors(id)
		local tOk = typeof(colors.Glow) == "Color3" and typeof(colors.Telegraph) == "Color3" and typeof(colors.Enrage) == "Color3"
		local boss = bc and bc.Bosses and bc.Bosses[id]
		for _, a in ipairs(boss and boss.Attacks or {}) do
			local fill, edge = BB.TelegraphColor(id, a.Id)
			tOk = tOk and typeof(fill) == "Color3" and typeof(edge) == "Color3"
		end
		T.check(tOk and colors.Element == (boss and boss.Element or colors.Element), id .. ": Colors / TelegraphColor for every attack (" .. tostring(colors.Element) .. ")")
		high:Destroy()
		low:Destroy()
	end
end)

----------------------------------------------------------------------------------------------------
-- p3events_schedule
----------------------------------------------------------------------------------------------------
local function ready(label)
	if not K.needBoot() then
		return false
	end
	if not ES() then
		T.fail(label .. ": skipped, server/Services/EventService did not load")
		return false
	end
	if not BS() or type(BS().GetRaidStatus) ~= "function" then
		T.fail(label .. ": skipped, no BattleService raids in this build")
		return false
	end
	return true
end

local function clearRaid()
	local es = ES()
	if BS().GetRaidStatus() then
		es.EndNow("BossRaid")
		K.waitFor(function()
			return BS().GetRaidStatus() == nil
		end, 10)
	end
end

S.p3events_schedule = guarded("p3events_schedule", function()
	if not ready("schedule") then
		return
	end
	local es, bc = ES(), BC()
	T.check(type(es.StartNow) == "function" and type(es.RewardMultiplier) == "function" and type(es.EventStarted) == "table" and type(es.EventStarted.Connect) == "function",
		"schedule: EventService API (StartNow, RewardMultiplier, signals at module load)")
	T.info("*events: game clock " .. string.format("%.0f", Mock.Clock.now) .. " s; next raid in " .. string.format("%.0f", es.SecondsUntil("BossRaid") or -1)
		.. " s, next Double Rewards in " .. string.format("%.0f", es.SecondsUntil("DoubleRewards") or -1) .. " s; double now: " .. tostring(es.IsDoubleRewards()))
	clearRaid()
	if es.IsDoubleRewards() then
		es.EndNow("DoubleRewards")
	end
	local mark = K.logSize()
	local p = newPlayer("EvSched")
	local states = arenaStates(p, mark)
	local st = states[#states]
	local shapeOk = type(st) == "table" and type(st.Leaderboard) == "table" and (st.Next == nil or (type(st.Next.Kind) == "string" and tonumber(st.Next.StartsIn) ~= nil))
	T.check(#states >= 1 and shapeOk, "schedule: a joining player gets the ArenaState (Next, Raid, Double, Leaderboard)", tostring(#states))
	if type(st) == "table" and type(st.Leaderboard) == "table" then
		local found = false
		advance(5.5)
		local later = arenaStates(p, mark)
		local last = later[#later]
		for _, row in ipairs(last and last.Leaderboard or {}) do
			found = found or (row.UserId == p.UserId and type(row.Name) == "string" and tonumber(row.Trophies) ~= nil)
		end
		T.check(found and #(last.Leaderboard) <= 10, "schedule: the leaderboard lists the players in the server ({ UserId, Name, Trophies }, <= 10)")
	end
	local left = es.SecondsUntil("BossRaid")
	if not T.check(type(left) == "number", "schedule: a Boss Raid is scheduled") then
		return
	end
	local every = 20 * 60
	local announce = 120
	for _, e in ipairs(bc.Events.Schedule) do
		if e.Kind == "BossRaid" then
			every, announce = e.EveryMinutes * 60, e.AnnounceSeconds
		end
	end
	T.check(left <= every + 2, "schedule: the next raid is at most EveryMinutes away", string.format("%.0f s", left))
	if left < announce + 5 then
		-- already announced (the clock of earlier scenarios): let this one open, close it, and watch the next one
		K.waitFor(function()
			return BS().GetRaidStatus() ~= nil
		end, left + 10)
		clearRaid()
		advance(1.5)
		left = es.SecondsUntil("BossRaid")
	end
	if left > announce + 5 then
		advance(left - announce - 5)
	end
	mark = K.logSize()
	local announced = K.waitFor(function()
		return (toasted(p, "Boss Raid in", mark))
	end, 12)
	local okT, text = toasted(p, "Boss Raid in", mark)
	T.check(announced and okT, "schedule: about 2 minutes ahead every player gets a side toast naming the boss", text)
	local slotBoss = nil
	local es2 = es.GetState()
	if es2.NextRaid then
		slotBoss = es2.NextRaid.BossId
	end
	T.check(okT and slotBoss ~= nil and text:find(bc.Bosses[slotBoss].Name, 1, true) ~= nil, "schedule: ...the toast names the next boss (" .. tostring(slotBoss) .. ")", text)
	local m2 = K.logSize()
	advance(5.2)
	local fast = arenaStates(p, m2)
	local lastSt = fast[#fast]
	T.check(#fast >= 4, "schedule: during the countdown ArenaState comes about every second", tostring(#fast))
	T.check(lastSt and lastSt.Next and lastSt.Next.Kind == "BossRaid" and lastSt.Next.Announced == true and lastSt.Next.StartsIn <= announce and lastSt.Next.StartsIn > 0,
		"schedule: ArenaState.Next counts the raid down", lastSt and lastSt.Next and tostring(lastSt.Next.StartsIn) or "nil")
	mark = K.logSize()
	local started = K.waitFor(function()
		return BS().GetRaidStatus() ~= nil
	end, announce + 10)
	T.check(started, "schedule: at its time the raid opens through BattleService.StartRaid")
	if not started then
		return
	end
	local status = BS().GetRaidStatus()
	T.eq(status.BossId, slotBoss, "schedule: ...with the announced boss")
	T.check((toasted(p, "Boss Raid!", mark)), "schedule: ...and a 'Boss Raid!' toast to everyone")
	advance(1.2)
	local sts = arenaStates(p, mark)
	local s3 = sts[#sts]
	T.check(s3 and type(s3.Raid) == "table" and s3.Raid.Active == true and s3.Raid.BossId == slotBoss, "schedule: ArenaState.Raid = BattleService.GetRaidStatus()")
	local nextLeft = es.SecondsUntil("BossRaid")
	T.check(nextLeft and nextLeft > every - 30 and nextLeft <= every + 2, "schedule: the next raid is ~EveryMinutes later", tostring(nextLeft))
	-- nobody joins: the raid closes at the end of the join window and everyone hears about it
	mark = K.logSize()
	local closed = K.waitFor(function()
		return BS().GetRaidStatus() == nil
	end, (bc.Events.JoinWindowSeconds or 60) + 15)
	T.check(closed, "schedule: a raid nobody joined closes after the join window")
	advance(0.5)
	local okN, nt = toasted(p, "Nobody fought", mark)
	T.check(okN, "schedule: ...and every player is told (toast)", nt)
	local state = es.GetState()
	T.check(state.LastRaid and state.LastRaid.BossId == slotBoss and state.LastRaid.Players == 0, "schedule: GetState().LastRaid records it")
	K.removePlayers({ p })
end)

----------------------------------------------------------------------------------------------------
-- p3events_raid
----------------------------------------------------------------------------------------------------
S.p3events_raid = guarded("p3events_raid", function()
	if not ready("raid") then
		return
	end
	local es, bs, ds, bc = ES(), BS(), DS(), BC()
	clearRaid()
	local p = newPlayer("EvRaid")
	local q = newPlayer("EvWatch")
	-- StartNow / EndNow
	local mark = K.logSize()
	local ok, msg = es.StartNow("BossRaid")
	T.check(ok == true and type(msg) == "string", "raid: StartNow('BossRaid') opens a raid at once", tostring(msg))
	local status = bs.GetRaidStatus()
	T.check(status ~= nil and status.Active == true, "raid: ...BattleService.GetRaidStatus() is active")
	T.check(status and msg:find(bc.Bosses[status.BossId].Name, 1, true) ~= nil, "raid: ...the answer names the boss", msg)
	T.check((toasted(q, "Boss Raid!", mark)), "raid: ...everyone gets the 'Boss Raid!' toast")
	local again, why = es.StartNow("BossRaid")
	T.check(again == false and type(why) == "string", "raid: a second StartNow while a raid runs is refused", tostring(why))
	local left = es.SecondsUntil("BossRaid")
	T.check(left and left > 15 * 60, "raid: the schedule restarts from a raid started by hand", tostring(left))
	T.check(es.EndNow("BossRaid") == true, "raid: EndNow('BossRaid') ends it")
	advance(1)
	T.check(bs.GetRaidStatus() == nil, "raid: ...no raid afterwards")
	T.check(select(1, es.StartNow("Nonsense")) == false and select(1, es.EndNow("Nonsense")) == false, "raid: unknown event kinds are refused")

	-- Double Rewards
	T.eq(es.RewardMultiplier(), 1, "double: RewardMultiplier() is 1 outside Double Rewards")
	mark = K.logSize()
	local okD = es.StartNow("DoubleRewards")
	local mult = bc.Events.DoubleRewardsMultiplier or 2
	T.check(okD == true and es.IsDoubleRewards() == true and es.RewardMultiplier() == mult, "double: StartNow('DoubleRewards') -> RewardMultiplier() = " .. mult)
	T.eq(workspace:GetAttribute("DoubleRewards"), true, "double: Workspace attribute DoubleRewards = true")
	T.check(type(bs.IsDoubleRewards) ~= "function" or bs.IsDoubleRewards() == true, "double: BattleService sees the Double Rewards")
	T.check((toasted(p, "Double Rewards", mark)), "double: everyone gets a toast")
	local gold = bc.RaidTier(0.5, true)
	local tier = es.RaidTierFor(0.5, true)
	T.check(tier and tier.Id == gold.Id and tier.Tokens == math.floor(gold.Tokens * mult + 0.5), "double: RaidTierFor doubles the tier's Tokens")
	local st = es.GetState()
	T.check(st.Double and st.Double.Active == true and st.Double.EndsIn > 3000, "double: ArenaState.Double = { Active, EndsIn }")
	es.EndNow("DoubleRewards")
	T.check(es.RewardMultiplier() == 1 and workspace:GetAttribute("DoubleRewards") == false and (type(bs.IsDoubleRewards) ~= "function" or bs.IsDoubleRewards() == false),
		"double: EndNow ends it everywhere")

	-- the fallback payer: only when BattleService did not pay, and once
	local uid = p.UserId
	local before = ds.GetTokens(p)
	local rec0 = ds.GetBattle(p) or {}
	local result = { Mode = "Raid", BossId = "lava_golem", Winners = { uid }, Losers = {}, Participants = { uid }, Shares = { [uid] = 0.3 }, Damage = { [uid] = 4321 }, Forfeit = false, RewardsPaid = true, Rewards = {} }
	bs.BattleEnded:Fire("smoke-raid-paid", result)
	advance(0.3)
	T.eq(ds.GetTokens(p), before, "payer: a raid BattleService already paid pays nothing more")
	local flag = bs.PayRaidRewards
	bs.PayRaidRewards = false
	mark = K.logSize()
	local unpaid = { Mode = "Raid", BossId = "lava_golem", Winners = { uid }, Losers = {}, Participants = { uid }, Shares = { [uid] = 0.3 }, Damage = { [uid] = 4321 }, Forfeit = false, RewardsPaid = false }
	bs.BattleEnded:Fire("smoke-raid-unpaid", unpaid)
	advance(0.3)
	local want = bc.RaidTier(0.3, true)
	T.eq(ds.GetTokens(p) - before, want.Tokens, "payer: BattleService did not pay -> EventService pays the " .. want.Id .. " tier (" .. want.Tokens .. " tokens)")
	local rec1 = ds.GetBattle(p) or {}
	T.check((rec1.Raids or 0) == (rec0.Raids or 0) + 1 and (rec1.RaidBestDamage or 0) >= 4321, "payer: ...Raids + 1 and RaidBestDamage")
	T.check((toasted(p, "Boss defeated", mark)), "payer: ...with a side toast")
	local mid = ds.GetTokens(p)
	bs.BattleEnded:Fire("smoke-raid-unpaid", unpaid)
	advance(0.3)
	T.eq(ds.GetTokens(p), mid, "payer: the same raid result twice pays once")
	bs.PayRaidRewards = flag
	T.check((toasted(q, "lava golem", mark) or toasted(q, "Lava Golem", mark)), "raid end: everyone hears how the raid went")

	-- event pet shout-out
	local pets = PC().EventPets()
	if pets[1] then
		mark = K.logSize()
		bs.BattleEnded:Fire("smoke-raid-pet", { Mode = "Raid", BossId = "frost_wyrm", Winners = { uid }, Losers = {}, Participants = { uid }, Shares = { [uid] = 1 }, Damage = { [uid] = 1 }, RewardsPaid = true, Rewards = { [uid] = { Tier = "Gold", EventPet = pets[1].Id } } })
		advance(0.3)
		local okS, text = toasted(q, "won the event pet", mark)
		T.check(okS and text:find(pets[1].Name, 1, true) ~= nil, "raid end: the other players hear who won an event pet", text)
	end
	local last = es.GetState().LastRaid
	T.check(last and last.Won ~= nil and type(last.Top) == "table", "raid end: GetState().LastRaid has the summary")

	-- developer /raid
	local Dev = req("server/Services/DevService")
	if Dev then
		local list = table.concat(Dev.Commands or {}, ",")
		T.check(list:find("raid", 1, true) ~= nil, "dev: DevService.Commands lists raid")
		mark = K.logSize()
		local okR, m = Dev.Run(p, "raid", nil, "test")
		T.check(okR == true and bs.GetRaidStatus() ~= nil, "dev: the raid command starts a Boss Raid", tostring(m))
		local okT, text = toasted(p, "^DEV: raid started", mark)
		T.check(okT and #text <= 90, "dev: ...answered with a 'DEV:' toast (<= 90 chars)", text)
		advance(2.1)
		local okR2 = Dev.Run(p, "raid", nil, "test")
		T.check(okR2 == false, "dev: a second /raid while one runs is refused")
		advance(2.1)
		mark = K.logSize()
		Dev.Run(p, "devhelp", nil, "test")
		local okH, help = toasted(p, "/devhelp", mark)
		T.check(okH and help:find("/raid", 1, true) ~= nil and #help <= 90, "dev: /devhelp lists /raid and fits a side toast (<= 90)", help)
		clearRaid()
	end
	K.removePlayers({ p, q })
end)

return S
