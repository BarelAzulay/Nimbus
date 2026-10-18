-- smoke_fix_leave.lua: regression checks for the order of the leave save (server/Services/DataService.lua,
-- onPlayerRemoving). Server world only, booted; the scenarios run before the care block (they advance the clock).
--
-- The bug: DataService's PlayerRemoving handler started the leave save at once. When the session had nothing unsaved,
-- the save found an empty delta and returned without yielding, so Release dropped the cache entry inside the
-- PlayerRemoving dispatch: every handler that ran after it found no profile and its write was lost. Only a leave save
-- with something to write (it yielded in UpdateAsync) let a late write land, through the orphan retry. The leave save
-- now runs after the other PlayerRemoving handlers (task.defer), so their writes travel with it or with its orphan retry.
-- Phase 4: the leave-time write under test is the Champion Ring's `Ring.Runs + 1` (BattleService's PlayerRemoving
-- handler closes a run between two rounds: ARCHITECTURE_V3.md "Phase 4 build contract" 3.8 / 8.2); the Kitchen refund
-- it used to check is gone with the Kitchen (3.4).
--   fixleave_ring     a player whose session is fully saved (Ring.Best 1 stored, Runs 0) leaves between two ring rounds:
--                     Runs + 1 and the write of a PlayerRemoving handler connected after every service's are in the
--                     leave save itself (stored within a second: no orphan retry needed), the entry is released
--                     afterwards (a rejoin reads the store afresh); with a DataStore outage at the leave Runs + 1 is kept
--                     as an orphan and lands with the background retry
--   fixleave_rejoin   a rejoin in the same frame as the leave (before the deferred leave save started) picks up the
--                     entry still in memory, Runs + 1 included, and keeps it: the old session's save still writes it,
--                     its Release skips the rejoined player's entry, the new session saves and is released normally
--                     afterwards
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local Players = game:GetService("Players")
local advance, config, mod = K.advance, K.config, K.mod
local ALLOWED_WARNINGS = { "[DataService]", "[BattleService]", "[TycoonService]" }
local PET = "cloudy_dragon" -- one strong pet: round 1 of the ring is over in a moment

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
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

local function TS()
	return requireAt("server/Services/TycoonService")
end
local function BS()
	return requireAt("server/Services/BattleService")
end
local function AB()
	return requireAt("server/Services/ArenaBuilder")
end
local function DS()
	return mod("DataService")
end

local function arenaInfo()
	local ab = AB()
	return ab and ab.GetInfo and ab.GetInfo() or nil
end

local userSeq = 0
local function newUserId()
	userSeq = userSeq + 1
	return 979300 + userSeq
end

local function join(prefix, uid)
	local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
	advance(1.2)
	return p
end

local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	advance(0.8)
end

local function leaveAll(list)
	for _, p in ipairs(list) do
		if p and p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	advance(5) -- the ring runs' return delay too
end

local function spots()
	return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
end

local function freeIndex()
	local SS = mod("SpotService")
	for i = 1, config().Lobby.SpotCount do
		if spots()[i] and not SS.GetOwner(i) then
			return i
		end
	end
	return nil
end

-- claims the first free plot (TycoonService.Claim); its index or nil
local function claimFree(p)
	local Ty = TS()
	local index = freeIndex()
	if not Ty or not index then
		return nil
	end
	local ok = Ty.Claim(p, index)
	advance(0.6)
	return ok and index or nil
end

local function stored(uid)
	return Mock.DataStore.Data[config().Tokens.DataStoreName .. "/u_" .. uid]
end

-- the Position of a part, a model (its pivot) or an ArenaInfo entry
local function positionOf(thing)
	if type(thing) == "table" then
		if typeof(thing.Position) == "Vector3" then
			return thing.Position
		end
		if typeof(thing.CFrame) == "CFrame" then
			return thing.CFrame.Position
		end
		return positionOf(thing.Pad or thing.Part or thing.Model)
	end
	if typeof(thing) ~= "Instance" or not thing:IsDescendantOf(workspace) then
		return nil
	end
	if thing:IsA("BasePart") then
		return thing.Position
	end
	local ok, cf = pcall(function()
		return thing:GetPivot()
	end)
	return ok and typeof(cf) == "CFrame" and cf.Position or nil
end

-- where BattleService accepts ring starts: ArenaInfo.RingPortal, else the Portal_Ring model, else the Trial Portal
local function ringPortalPos()
	local info = arenaInfo()
	return positionOf(info and info.RingPortal) or positionOf(workspace:FindFirstChild("Portal_Ring", true)) or (info and info.TrialPortal and info.TrialPortal.Position)
end

-- a strong pet, a team of one, a claimed home, the player at the Champion Ring portal
local function climber(p)
	local D = DS()
	local prof = D.GetProfile(p)
	if not prof then
		return false
	end
	prof.Pets[PET] = (prof.Pets[PET] or 0) + 1
	prof.PetLevels[PET] = { Level = 12, Xp = 0 }
	D.MarkDirty(p)
	D.SetTeam(p, 1, { PET })
	if not claimFree(p) then
		return false
	end
	local pos = ringPortalPos()
	if not pos then
		return false
	end
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 6)))
	advance(0.1)
	return true
end

-- The set-up: a claimed home, one strong pet, a ring run whose round 1 is WON (Ring.Best 1), the player waiting in the
-- intermission; then the session saved so NOTHING is unsaved when the player leaves (stored Ring.Best 1, Runs 0).
-- Returns true when the player sits between two rounds with everything saved.
local function winOneRoundAndSave(p, uid, label)
	local D, bs = DS(), BS()
	if not T.check(climber(p), label .. ": (precondition) a strong pet, a claimed home, the player at the ring portal") then
		return false
	end
	local ok, why = bs.StartRing(p, 1)
	if not T.check(ok == true, label .. ": (setup) the ring run starts", tostring(why)) then
		return false
	end
	local t0 = Mock.Clock.now
	local g = nil
	while Mock.Clock.now - t0 < 60 do
		advance(0.1)
		g = bs.GetBattle(p)
		if g and g.State == "Intermission" then
			break
		end
		if not bs.IsInBattle(p) then
			break
		end
	end
	local ring = D.GetRing(p) or {}
	if not T.check(g and g.State == "Intermission" and g.Round == 2 and ring.Best == 1 and ring.Runs == 0,
		label .. ": (setup) round 1 won: the run waits between rounds (Best 1, Runs 0)", (g and tostring(g.State) or "no battle") .. " Best " .. tostring(ring.Best) .. " Runs " .. tostring(ring.Runs)) then
		return false
	end
	local savedOk = D.Save(p) == true
	local rec = stored(uid) or {}
	if not T.check(savedOk and type(rec.Ring) == "table" and rec.Ring.Best == 1 and (rec.Ring.Runs or 0) == 0,
		label .. ": (setup) the session is saved before the leave (stored Ring.Best 1, Runs 0: nothing left unsaved)",
		"Save " .. tostring(savedOk) .. ", stored Ring " .. (rec.Ring and ("Best " .. tostring(rec.Ring.Best) .. " Runs " .. tostring(rec.Ring.Runs)) or "nil")) then
		return false
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- fixleave_ring
----------------------------------------------------------------------------------------------------
S.fixleave_ring = guarded("fixleave_ring", function()
	if not K.needBoot() then
		return
	end
	local D, Ty, bs = DS(), TS(), BS()
	if not T.check(Ty ~= nil and bs ~= nil and type(bs.StartRing) == "function" and arenaInfo() ~= nil, "leave ring: (precondition) TycoonService, BattleService (StartRing) and the arena load") then
		return
	end
	local DSt = Mock.DataStore
	local saved = { Latency = DSt.Latency, Fail = DSt.Fail }
	local players, conns = {}, {}
	local okRun, errRun = pcall(function()
		-- 1) the reported case, Phase 4 style: a ring run between two rounds, the session saved, then a leave with the
		--    real DataStore latency. Before the fix the leave save (nothing to write) returned at once, Release dropped
		--    the entry and BattleService's Runs + 1 found no profile: the stored Runs stayed 0.
		local uid = newUserId()
		local p = join("LeaveClean", uid)
		players[#players + 1] = p
		if not winOneRoundAndSave(p, uid, "leave ring") then
			return
		end
		-- a PlayerRemoving handler connected after every service's (so it runs last): its leave-time write must be saved
		-- too (any late write, a LastSeen touch for instance, was lost the same way)
		local tokensBefore = D.GetTokens(p)
		local lateRan = false
		conns[#conns + 1] = Players.PlayerRemoving:Connect(function(leaver)
			if leaver == p then
				lateRan = true
				D.AddTokens(leaver, 1)
			end
		end)
		DSt.Latency = 0.2 -- a real DataStore call takes a moment
		Mock.RemovePlayer(p)
		advance(1.0)
		DSt.Latency = saved.Latency
		T.check(lateRan, "leave ring: (precondition) the late PlayerRemoving handler ran")
		local rec = stored(uid) or {}
		T.check(type(rec.Ring) == "table" and rec.Ring.Runs == 1 and rec.Ring.Best == 1,
			"leave ring: leaving between two ring rounds with nothing else unsaved writes Ring.Runs + 1 in the leave save itself (stored within a second, no orphan retry needed)",
			"stored Ring " .. (rec.Ring and ("Best " .. tostring(rec.Ring.Best) .. " Runs " .. tostring(rec.Ring.Runs)) or "nil"))
		T.eq(rec.Tokens, tokensBefore + 1, "leave ring: the write of the last PlayerRemoving handler travels with the leave save too")
		advance(17) -- past the first orphan retry (10 s)
		rec = stored(uid) or {}
		T.check(type(rec.Ring) == "table" and rec.Ring.Runs == 1 and rec.Tokens == tokensBefore + 1, "leave ring: the save still holds Runs 1 17 s later (no double count by a retry)",
			"stored Runs " .. tostring(rec.Ring and rec.Ring.Runs) .. ", Tokens " .. tostring(rec.Tokens))
		-- the entry was released after the successful leave save: a write by another server is read by the next join
		rec.Tokens = rec.Tokens + 50
		local back = join("LeaveCleanBack", uid)
		players[#players + 1] = back
		local ringBack = D.GetRing(back) or {}
		T.check(D.GetTokens(back) == tokensBefore + 51 and ringBack.Runs == 1 and ringBack.Best == 1, "leave ring: after the successful leave save the entry is released (the rejoin reads the store afresh, Runs 1 included)",
			"tokens " .. D.GetTokens(back) .. " (expected " .. (tokensBefore + 51) .. "), Runs " .. tostring(ringBack.Runs))
		T.check(not bs.IsInBattle(back) and back:GetAttribute("InBattle") == nil, "leave ring: ...and the rejoined player is free (the old run ended with the leave)")
		leave(back)

		-- 2) the DataStore is down when the player leaves: Runs + 1 still lands, as an orphan flushed by the retry
		local uid2 = newUserId()
		local q = join("LeaveOutage", uid2)
		players[#players + 1] = q
		if winOneRoundAndSave(q, uid2, "leave ring (outage)") then
			DSt.Fail = true
			Mock.RemovePlayer(q)
			advance(5)
			T.eq(((stored(uid2) or {}).Ring or {}).Runs or 0, 0, "leave ring (outage): nothing is written while the DataStore is down")
			DSt.Fail = saved.Fail
			advance(40) -- the orphan retries (10 s, then 20 s)
			T.eq(((stored(uid2) or {}).Ring or {}).Runs, 1, "leave ring (outage): Runs + 1 is kept as an orphan and lands with the background retry")
		end
	end)
	for _, conn in ipairs(conns) do
		conn:Disconnect()
	end
	DSt.Latency, DSt.Fail = saved.Latency, saved.Fail
	leaveAll(players)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixleave_ring")
	K.flushWarnings("fixleave_ring", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- fixleave_rejoin
----------------------------------------------------------------------------------------------------
S.fixleave_rejoin = guarded("fixleave_rejoin", function()
	if not K.needBoot() then
		return
	end
	local Config = config()
	local D, Ty, bs = DS(), TS(), BS()
	if not T.check(Ty ~= nil and bs ~= nil and type(bs.StartRing) == "function" and arenaInfo() ~= nil, "leave rejoin: (precondition) TycoonService, BattleService (StartRing) and the arena load") then
		return
	end
	local DSt = Mock.DataStore
	local saved = { Latency = DSt.Latency }
	local players = {}
	local okRun, errRun = pcall(function()
		local uid = newUserId()
		local p = join("LeaveQuick", uid)
		players[#players + 1] = p
		if not winOneRoundAndSave(p, uid, "leave rejoin") then
			return
		end
		local tokens = D.GetTokens(p)
		DSt.Latency = 1.0 -- a slow DataStore: the old session's leave save is in flight for a second
		Mock.RemovePlayer(p)
		-- the same frame: the deferred leave save has not even started
		local back = Mock.AddPlayer("LeaveQuickBack", uid)
		players[#players + 1] = back
		local ringBack = D.GetRing(back) or {}
		T.check(D.GetProfile(back) ~= nil and ringBack.Runs == 1 and ringBack.Best == 1, "leave rejoin: a rejoin in the same frame as the leave picks up the entry still in memory, Runs + 1 included",
			"Runs " .. tostring(ringBack.Runs) .. " Best " .. tostring(ringBack.Best))
		advance(3)
		DSt.Latency = saved.Latency
		ringBack = D.GetRing(back) or {}
		T.check(D.GetHome(back) ~= nil and ringBack.Runs == 1 and back:GetAttribute(Config.Attr.Cash) == D.GetCash(back),
			"leave rejoin: the old session's Release skips the rejoined player's entry (still in memory with Runs 1, the Cash attribute agrees)",
			"home " .. tostring(D.GetHome(back) ~= nil) .. ", Runs " .. tostring(ringBack.Runs) .. ", attribute " .. tostring(back:GetAttribute(Config.Attr.Cash)))
		T.eq(((stored(uid) or {}).Ring or {}).Runs, 1, "leave rejoin: ...and the old session's leave save still wrote Runs + 1")
		T.check(not bs.IsInBattle(back), "leave rejoin: ...the rejoined player is not in the old run")
		-- the new session keeps saving from that entry, and its own leave releases it
		D.AddTokens(back, 3)
		leave(back)
		advance(1)
		T.eq((stored(uid) or {}).Tokens, tokens + 3, "leave rejoin: the new session's own leave save works")
		T.eq(((stored(uid) or {}).Ring or {}).Runs, 1, "leave rejoin: ...and Runs stays 1 (counted once across the two sessions)")
		local rec = stored(uid) or {}
		rec.Tokens = (rec.Tokens or 0) + 10 -- another server's write
		local again = join("LeaveQuickAgain", uid)
		players[#players + 1] = again
		T.eq(D.GetTokens(again), tokens + 13, "leave rejoin: after the new session's leave the entry is released (the next join reads the store)")
		leave(again)
	end)
	DSt.Latency = saved.Latency
	leaveAll(players)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixleave_rejoin")
	K.flushWarnings("fixleave_rejoin", ALLOWED_WARNINGS)
end)

return S
