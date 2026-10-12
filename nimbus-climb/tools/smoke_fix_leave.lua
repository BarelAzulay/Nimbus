-- smoke_fix_leave.lua: regression checks for the order of the leave save (server/Services/DataService.lua,
-- onPlayerRemoving). Server world only, booted; the scenarios run before the care block (they advance the clock past
-- cook times, and p2care_exploits leaves a dish cooking for p2care_shutdown).
--
-- The bug: DataService's PlayerRemoving handler started the leave save at once. When the session had nothing unsaved,
-- the save found an empty delta and returned without yielding, so Release dropped the cache entry inside the
-- PlayerRemoving dispatch: every handler that ran after it (PetCareService's refund of the dishes still cooking, any
-- other leave-time write) found no profile and its write was lost. Only a leave save with something to write (it
-- yielded in UpdateAsync) let the refund land, through the orphan retry. The leave save now runs after the other
-- PlayerRemoving handlers (task.defer), so their writes travel with it or with its orphan retry.
--   fixleave_refund   a player whose session is fully saved leaves with two Feasts still cooking: the refund, and the
--                     write of a PlayerRemoving handler connected after every service's, are in the leave save itself
--                     (stored within a second: no orphan retry needed), the unfinished Feasts are not in Food, and the
--                     entry is released afterwards (a rejoin reads the store afresh); with a DataStore outage at the
--                     leave the refund is kept as an orphan and lands with the background retry
--   fixleave_rejoin   a rejoin in the same frame as the leave (before the deferred leave save started) picks up the
--                     entry still in memory, refund included, and keeps it: the old session's save still writes the
--                     refund, its Release skips the rejoined player's entry, the new session saves and is released
--                     normally afterwards
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
local ALLOWED_WARNINGS = { "[DataService]" }

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
local function TC()
	return requireAt("shared/TycoonCatalog")
end
local function PCS()
	return requireAt("server/Services/PetCareService")
end
local function DS()
	return mod("DataService")
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
	advance(0.8)
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

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

local function care(p, ...)
	Mock.FromClient(remote("PetCare"), p, ...)
end

local function stored(uid)
	return Mock.DataStore.Data[config().Tokens.DataStoreName .. "/u_" .. uid]
end

-- writes station levels straight into the saved home (Home.Level follows), then lets the services sync the plot
local function setStations(p, map)
	local Cat = TC()
	DS().MutateHome(p, function(h)
		for id, lv in pairs(map) do
			if lv > 0 then
				h.Stations[id] = lv
			else
				h.Stations[id] = nil
			end
		end
		h.Level = Cat.HomeLevelOf(h)
	end)
	advance(2.1) -- one TycoonService tick builds the stations, one PetCareService tick dresses the Kitchen
end

-- The reported set-up: a claimed plot with a Lv 5 Kitchen, exactly the Cash for two Feasts, both ordered (every Cash
-- spent), then the session saved so NOTHING is unsaved when the player leaves. Returns the refund the leave owes
-- (2 x the Feast price), or nil when a precondition failed.
local function cookTwoFeastsAndSave(p, uid, label)
	local D, Cat, Care = DS(), TC(), PCS()
	if not T.check(claimFree(p) ~= nil, label .. ": (precondition) a free plot was claimed") then
		return nil
	end
	setStations(p, { Kitchen = 5 })
	local price = Cat.FoodById("Feast").Price
	D.SpendCash(p, D.GetCash(p))
	D.AddCash(p, 2 * price)
	care(p, "Cook", "Feast", 2)
	advance(0.3)
	if not T.check(D.GetCash(p) == 0 and #Care.GetQueue(p) == 2, label .. ": (setup) two Feasts ordered with all the Cash (" .. 2 * price .. ")",
		"Cash " .. D.GetCash(p) .. ", queue " .. #Care.GetQueue(p)) then
		return nil
	end
	local savedOk = D.Save(p) == true
	local rec = stored(uid) or {}
	if not T.check(savedOk and rec.Cash == 0, label .. ": (setup) the session is saved before the leave (stored Cash 0: nothing left unsaved)",
		"Save " .. tostring(savedOk) .. ", stored Cash " .. tostring(rec.Cash)) then
		return nil
	end
	return 2 * price
end

----------------------------------------------------------------------------------------------------
-- fixleave_refund
----------------------------------------------------------------------------------------------------
S.fixleave_refund = guarded("fixleave_refund", function()
	if not K.needBoot() then
		return
	end
	local D, Ty, Cat, Care = DS(), TS(), TC(), PCS()
	if not T.check(Ty ~= nil and Cat ~= nil and Care ~= nil, "leave refund: (precondition) TycoonService, TycoonCatalog and PetCareService load") then
		return
	end
	local DSt = Mock.DataStore
	local saved = { Latency = DSt.Latency, Fail = DSt.Fail }
	local players, conns = {}, {}
	local okRun, errRun = pcall(function()
		-- 1) the reported case: Kitchen Lv 5, exactly the Cash for two Feasts, both ordered, the session saved, then a
		--    leave with the real DataStore latency. Before the fix the leave save (nothing to write) returned at once,
		--    Release dropped the entry and PetCareService's refund found no profile: the stored Cash stayed 0.
		local uid = newUserId()
		local p = join("LeaveClean", uid)
		players[#players + 1] = p
		local refund = cookTwoFeastsAndSave(p, uid, "leave refund")
		if not refund then
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
		T.check(lateRan, "leave refund: (precondition) the late PlayerRemoving handler ran")
		local rec = stored(uid) or {}
		T.check(rec.Cash == refund, "leave refund: leaving with two Feasts still cooking and nothing else unsaved refunds them in the leave save itself (stored within a second, no orphan retry needed)",
			"stored Cash " .. tostring(rec.Cash) .. ", expected " .. refund)
		T.eq(rec.Tokens, tokensBefore + 1, "leave refund: the write of the last PlayerRemoving handler travels with the leave save too")
		T.eq((type(rec.Food) == "table" and rec.Food.Feast) or 0, 0, "leave refund: ...and the unfinished Feasts are not in Food")
		advance(17) -- past the first orphan retry (10 s)
		rec = stored(uid) or {}
		T.check(rec.Cash == refund and rec.Tokens == tokensBefore + 1, "leave refund: the save still holds the refund 17 s later",
			"stored Cash " .. tostring(rec.Cash) .. ", Tokens " .. tostring(rec.Tokens))
		-- the entry was released after the successful leave save: a write by another server is read by the next join
		rec.Tokens = rec.Tokens + 50
		local back = join("LeaveCleanBack", uid)
		players[#players + 1] = back
		T.check(D.GetTokens(back) == tokensBefore + 51 and D.GetCash(back) == refund, "leave refund: after the successful leave save the entry is released (the rejoin reads the store afresh, refund included)",
			"tokens " .. D.GetTokens(back) .. " (expected " .. (tokensBefore + 51) .. "), Cash " .. D.GetCash(back))
		leave(back)

		-- 2) the DataStore is down when the player leaves: the refund still lands, as an orphan flushed by the retry
		local uid2 = newUserId()
		local q = join("LeaveOutage", uid2)
		players[#players + 1] = q
		if cookTwoFeastsAndSave(q, uid2, "leave refund (outage)") then
			DSt.Fail = true
			Mock.RemovePlayer(q)
			advance(5)
			T.eq((stored(uid2) or {}).Cash, 0, "leave refund (outage): nothing is written while the DataStore is down")
			DSt.Fail = saved.Fail
			advance(40) -- the orphan retries (10 s, then 20 s)
			T.eq((stored(uid2) or {}).Cash, refund, "leave refund (outage): the refund is kept as an orphan and lands with the background retry")
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
	K.flushErrors("fixleave_refund")
	K.flushWarnings("fixleave_refund", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- fixleave_rejoin
----------------------------------------------------------------------------------------------------
S.fixleave_rejoin = guarded("fixleave_rejoin", function()
	if not K.needBoot() then
		return
	end
	local Config = config()
	local D, Ty, Cat, Care = DS(), TS(), TC(), PCS()
	if not T.check(Ty ~= nil and Cat ~= nil and Care ~= nil, "leave rejoin: (precondition) TycoonService, TycoonCatalog and PetCareService load") then
		return
	end
	local DSt = Mock.DataStore
	local saved = { Latency = DSt.Latency }
	local players = {}
	local okRun, errRun = pcall(function()
		local uid = newUserId()
		local p = join("LeaveQuick", uid)
		players[#players + 1] = p
		local refund = cookTwoFeastsAndSave(p, uid, "leave rejoin")
		if not refund then
			return
		end
		local tokens = D.GetTokens(p)
		DSt.Latency = 1.0 -- a slow DataStore: the old session's leave save is in flight for a second
		Mock.RemovePlayer(p)
		-- the same frame: the deferred leave save has not even started
		local back = Mock.AddPlayer("LeaveQuickBack", uid)
		players[#players + 1] = back
		T.check(D.GetProfile(back) ~= nil and D.GetCash(back) == refund, "leave rejoin: a rejoin in the same frame as the leave picks up the entry still in memory, refund included",
			"Cash " .. D.GetCash(back))
		advance(3)
		DSt.Latency = saved.Latency
		T.check(D.GetHome(back) ~= nil and D.GetCash(back) == refund and back:GetAttribute(Config.Attr.Cash) == refund,
			"leave rejoin: the old session's Release skips the rejoined player's entry (still in memory with the refund, the Cash attribute agrees)",
			"home " .. tostring(D.GetHome(back) ~= nil) .. ", Cash " .. D.GetCash(back) .. ", attribute " .. tostring(back:GetAttribute(Config.Attr.Cash)))
		T.eq((stored(uid) or {}).Cash, refund, "leave rejoin: ...and the old session's leave save still wrote the refund")
		-- the new session keeps saving from that entry, and its own leave releases it
		D.AddTokens(back, 3)
		leave(back)
		advance(1)
		T.eq((stored(uid) or {}).Tokens, tokens + 3, "leave rejoin: the new session's own leave save works")
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
