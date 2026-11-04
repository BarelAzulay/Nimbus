-- smoke_daily.lua: DailyService (docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.2 / 6 / 7 Z8-Z9 / 13b.2-4;
-- plan docs/superpowers/plans/2026-11-04-store.md Task 10, W2-daily): the 20 h / 48 h streak with step-backs (re-earned,
-- never re-paid), a Week Wisp every kept week, the active play-time day on the server clock, VIP x2 on the Cash / Tokens
-- cells, resolved amounts in DailyState. Server world only.
--   daily_pure          (pure) Resolve: the Cash floor and income-minutes, VIP x2 on Cash / Tokens, Gems never doubled,
--                       the Berry Basket fill, the pet cell and its Else on a full stack
--   daily_claim         (booted) the state on load (no toast), day 1 pays the Min floor, 19 h 59 m refused, the 20 h and
--                       48 h boundaries, one second past 48 h steps back (nothing re-paid), a Cash cell from a home's income
--   daily_week          seven kept days -> a Week Wisp (Pet true, Weeks 1), week 2 -> a second Wisp, a full stack -> Else
--   daily_miss          47 h 59 m kept; 49 h steps back one day (repaired, unpaid, StepBack once); 10 days -> Streak 1
--   daily_provisional   a stand-in profile: only Loading payloads, the claim refused, no tick, the stored Play group kept
--   daily_two_servers   the (LastClaimAt, Streak) pair and a play tier across two DataService copies: paid once
--   daily_future_clock  a stored LastClaimAt inside the slack is kept; past it the claim rewrites it to now (no grant),
--                       is refused once with "Next gift in 20h 0m", and 20 h later pays (Z8)
--   daily_rejoin        PlaySec survives a rejoin; a play tier pays once
--   daily_idle          a still root adds nothing; a remote counts 180 s; a 3-stud move counts, 1 stud not; Play.Active
--                       flips send one payload each, ticks none
--   daily_playday       the 10 h cap; the 20 h play-day reset loses an unclaimed tier (Q17); no root / no character / a
--                       dead Humanoid add nothing and reset nothing (Review Focus 4)
--   daily_remote        junk, spam, InMatch, no StoreService (never VIP), the VIP seam (x2 Cash / Tokens, x1 Gems and
--                       tiers, no step-back), "Checking" only blocks a claim with a step-back due
--   daily_quiet_join    nothing announced on join; the payload within 1 s of ProfileLoaded; ReadyAt <= ServerNow
-- White-box: the booted helpers of smoke_store.lua / smoke_p7_data.lua ("server B" = a second DataService copy against the
-- same mock store). The mock's os.time() is floor(EPOCH + clock): a claim is fired FIRST and the clock advanced AFTER (an
-- advance between a clock write and the fire can add a second and break a boundary). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local advance, config, mod = K.advance, K.config, K.mod
local ALLOWED_WARNINGS = { "[DataService]", "[TycoonService]", "[PetCareService]", "[SpotService]" }
local HOUR = 3600
local WISP = "week_wisp"

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

local function DS()
	return mod("DataService")
end

local function DSV()
	return mod("DailyService")
end

local function TS()
	return mod("TycoonService")
end

local function TC()
	return mod("TycoonCatalog")
end

local userSeq = 0
local function newUserId()
	userSeq = userSeq + 1
	return 985100 + userSeq
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

local function loaded(p)
	return K.waitFor(function()
		return DS().GetDaily(p) ~= nil
	end, 10)
end

local function storeKey(uid)
	return config().Tokens.DataStoreName .. "/u_" .. uid
end

local function stored(uid)
	return Mock.DataStore.Data[storeKey(uid)]
end

local function statsOf()
	return { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} }
end

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

local function request(p, ...)
	Mock.FromClient(remote("DailyRequest"), p, ...)
end

-- fires DailyRequest "Claim" FIRST (at the current os.time(), returned) and lets the 1 req/s window pass AFTER
local function claim(p)
	local t = os.time()
	request(p, "Claim")
	advance(1.05)
	return t
end

local function claimPlay(p, tier)
	local t = os.time()
	request(p, "ClaimPlay", tier)
	advance(1.05)
	return t
end

local function setLast(p, s)
	return DS().MutateDaily(p, function(d)
		d.LastClaimAt = s
		return true
	end)
end

local function setDaily(p, fields)
	return DS().MutateDaily(p, function(d)
		for k, v in pairs(fields) do
			d[k] = v
		end
		return true
	end)
end

-- "s seconds pass" for the streak clock: the stored claim moves back instead of the sim clock forward (same rules,
-- no 20 h of ticks for every service)
local function elapse(p, s)
	local d = DS().GetDaily(p)
	return setLast(p, (d and d.LastClaimAt or os.time()) - s)
end

local function lastState(p)
	local e = K.lastRemote("DailyState", p.UserId)
	return e and e.args[1] or nil
end

local function states(p, mark)
	return K.remotesFor("DailyState", p.UserId, mark or 0)
end

local function toastCount(p, needle, mark)
	local n = 0
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		if string.find(tostring(e.args[1]), needle, 1, true) then
			n = n + 1
		end
	end
	return n
end

-- toasts DailyService could have sent (other services toast on join too)
local function dailyToasts(p, mark)
	return toastCount(p, "Day ", mark) + toastCount(p, "gift", mark) + toastCount(p, "Streak", mark) + toastCount(p, "WEEK", mark)
end

local function moveRoot(p, studs)
	local r = K.root(p)
	if r then
		Mock.Teleport(p, r.Position + Vector3.new(studs, 0, 0))
	end
end

-- lands right after a loop tick, then half a tick later: every advance(10) from here holds exactly one tick
local function alignTicks()
	local D = DSV()
	local mark = D._tickAt and D._tickAt() or -1
	K.waitFor(function()
		return (D._tickAt and D._tickAt() or -1) > mark
	end, 15)
	advance(5)
end

local function tick(n)
	advance(10 * (n or 1))
end

local function pets(p)
	local prof = DS().GetProfile(p)
	return prof and prof.Pets or {}
end

local function describeDaily(d)
	if type(d) ~= "table" then
		return tostring(d)
	end
	return "Streak " .. tostring(d.Streak) .. " Paid " .. tostring(d.Paid) .. " Weeks " .. tostring(d.Weeks) .. " Pet " .. tostring(d.Pet) .. " LastClaimAt " .. tostring(d.LastClaimAt) .. " PlayStart " .. tostring(d.PlayStart) .. " PlaySec " .. tostring(d.PlaySec)
end

-- puts a fresh player at Streak 7 / Paid 7 claimed `ago` seconds ago
local function atStreak7(p, ago)
	return setDaily(p, { Streak = 7, Paid = 7, Weeks = 1, Pet = true, LastClaimAt = os.time() - ago })
end

-- a second, independent copy of DataService (own cache, same mock store): "another server" (the smoke_p7_data shape)
local function secondServer(name)
	local inst = K.moduleInstance("server/Services/DataService")
	if not inst then
		return nil
	end
	local sigs = { game:GetService("Players").PlayerRemoving }
	for _, rn in ipairs({ "RequestProfile", "SettingsSet" }) do
		local r = remote(rn)
		if r then
			sigs[#sigs + 1] = r.OnServerEvent
		end
	end
	local marks = {}
	for _, sig in ipairs(sigs) do
		local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
		marks[#marks + 1] = { conns = conns, n = conns and #conns or 0 }
	end
	local clone = inst:Clone()
	clone.Name = name
	clone.Parent = inst.Parent
	local ok, module = pcall(require, clone)
	if not ok then
		clone:Destroy()
		return nil, module
	end
	local function release()
		clone:Destroy()
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
		return true
	end
	return module, clone, release
end

-- the first free plot claimed for p (TycoonService.Claim), or nil
local function claimFree(p)
	local Ty, SS = TS(), mod("SpotService")
	if not Ty or not SS then
		return nil
	end
	for i = 1, config().Lobby.SpotCount do
		if not SS.GetOwner(i) then
			local ok = Ty.Claim(p, i)
			advance(0.6)
			return ok and i or nil
		end
	end
	return nil
end

local function setStations(p, map)
	local Cat = TC()
	DS().MutateHome(p, function(h)
		for id, lv in pairs(map) do
			h.Stations[id] = lv > 0 and lv or nil
		end
		h.Level = Cat.HomeLevelOf(h)
	end)
	advance(2.1)
end

local function commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	while true do
		local k
		s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return s
end

local function finish(name, p, ...)
	for _, q in ipairs({ p, ... }) do
		leave(q)
	end
	K.flushErrors(name)
	K.flushWarnings(name, ALLOWED_WARNINGS)
end

----------------------------------------------------------------------------------------------------
-- daily_pure
----------------------------------------------------------------------------------------------------
S.daily_pure = guarded("daily_pure", function()
	local D = DSV()
	if not T.check(D ~= nil and type(D.Resolve) == "function" and type(D._deps) == "function", "daily pure: DailyService loads with Resolve and the _deps seam") then
		return
	end
	local deps = D._deps()
	local savedTy, savedDS = deps.TycoonService, deps.DataService
	local income, berries, petCount = 0, 0, 0
	deps.TycoonService = {
		IncomePerSecond = function()
			return income
		end,
		GetHome = function()
			return nil
		end,
	}
	deps.DataService = {
		GetBerries = function()
			return berries
		end,
		GetProfile = function()
			return { Pets = { [WISP] = petCount } }
		end,
	}
	local fake = {}
	local okRun, errRun = pcall(function()
		local cash = { Cash = { Minutes = 2, Min = 400 } }
		local r = D.Resolve(fake, cash, false)
		T.check(r.Kind == "Cash" and r.Amount == 400, "daily pure: a Cash cell at income 0 pays its Min floor", tostring(r.Kind) .. " " .. tostring(r.Amount))
		income = 12.5
		r = D.Resolve(fake, cash, false)
		T.check(r.Kind == "Cash" and r.Amount == 1500, "daily pure: at 12.5/s two income-minutes are 1500", tostring(r.Amount))
		r = D.Resolve(fake, cash, true)
		T.check(r.Kind == "Cash" and r.Amount == 3000, "daily pure: VIP doubles the Cash cell", tostring(r.Amount))
		r = D.Resolve(fake, { Tokens = 50 }, true)
		T.check(r.Kind == "Tokens" and r.Amount == 100, "daily pure: VIP doubles the Tokens cell", tostring(r.Amount))
		r = D.Resolve(fake, { Tokens = 50 }, false)
		T.check(r.Kind == "Tokens" and r.Amount == 50, "daily pure: Tokens x1 without VIP", tostring(r.Amount))
		r = D.Resolve(fake, { Gems = 10 }, true)
		T.check(r.Kind == "Gems" and r.Amount == 10, "daily pure: Gems are never doubled", tostring(r.Amount))
		local cap = TC().BasketCap(nil, 12.5)
		berries = 3
		r = D.Resolve(fake, { Berries = "Basket" }, false)
		T.check(r.Kind == "Berries" and r.Amount == cap - 3, "daily pure: the Basket cell fills the Berry Basket to BasketCap minus what is owned", tostring(r.Amount) .. " vs cap " .. tostring(cap))
		berries = cap + 5
		r = D.Resolve(fake, { Berries = "Basket" }, false)
		T.check(r.Kind == "Berries" and r.Amount == 0, "daily pure: a full basket resolves to 0, never negative", tostring(r.Amount))
		local pet = { Pet = WISP, Else = { Gems = 40 } }
		r = D.Resolve(fake, pet, true)
		T.check(r.Kind == "Pet" and r.PetId == WISP, "daily pure: the pet cell resolves to the Week Wisp", tostring(r.Kind) .. " " .. tostring(r.PetId))
		petCount = config().Pets.MaxPerStack
		r = D.Resolve(fake, pet, true)
		T.check(r.Kind == "Gems" and r.Amount == 40 and r.PetId == nil, "daily pure: a full stack resolves the cell's Else (40 Gems, never doubled)", tostring(r.Kind) .. " " .. tostring(r.Amount))
		petCount = config().Pets.MaxPerStack - 1
		r = D.Resolve(fake, pet, false)
		T.check(r.Kind == "Pet", "daily pure: one copy of room is enough for the pet")
	end)
	deps.TycoonService, deps.DataService = savedTy, savedDS
	if not okRun then
		error(errRun, 0)
	end
end)

----------------------------------------------------------------------------------------------------
-- daily_claim
----------------------------------------------------------------------------------------------------
S.daily_claim = guarded("daily_claim", function()
	if not K.needBoot() then
		return
	end
	local mark = K.logSize()
	local p = join("Daily", newUserId())
	loaded(p)
	advance(0.5)
	local t0 = DS().GetTokens(p)
	local st = lastState(p)
	T.check(st ~= nil and st.Loading == nil and st.Streak == 0 and st.Cell == 1 and st.Days[1].Kind == "Cash" and st.Days[1].Amount == 400 and st.Days[1].Today == true and st.ReadyAt <= os.time(),
		"daily claim: the state on load, day 1 ready, no toast", st and ("Streak " .. tostring(st.Streak) .. " Cell " .. tostring(st.Cell) .. " ReadyAt " .. tostring(st.ReadyAt) .. " now " .. os.time()) or "no payload")
	T.eq(dailyToasts(p, mark), 0, "daily claim: no Notify on load")
	T.check(st ~= nil and #st.Days == 7 and #st.Play.Tiers == 7 and st.Play.Seconds == 0 and st.Play.Active == false and st.Days[7].Kind == "Pet" and st.Days[7].PetId == WISP and st.Play.Tiers[1].Min == 10 and st.Play.Tiers[1].Amount == 200 and st.Play.Tiers[6].Kind == "Berries",
		"daily claim: seven resolved cells and seven resolved tiers")
	local cash0 = DS().GetCash(p)
	mark = K.logSize()
	local tc = claim(p)
	local d = DS().GetDaily(p)
	T.check(d.Streak == 1 and d.Paid == 1 and d.LastClaimAt == tc and DS().GetCash(p) == cash0 + 400 and toastCount(p, "+$400 Cash! Day 1 of 7", mark) == 1,
		"daily claim: day 1 pays $400 (the Min floor at income 0)", describeDaily(d) .. " cash " .. tostring(DS().GetCash(p) - cash0) .. " toasts " .. toastCount(p, "Day 1", mark))
	st = lastState(p)
	T.check(st ~= nil and st.Streak == 1 and st.Cell == 2 and st.Days[1].Claimed == true and st.Days[1].Today == false and st.Days[2].Today == true and st.Days[2].Claimed == false and st.ReadyAt == tc + config().Daily.ReadySeconds,
		"daily claim: the payload after the claim: cell 1 claimed, cell 2 today, ReadyAt 20 h on")
	mark = K.logSize()
	setLast(p, os.time() - (19 * HOUR + 59 * 60))
	claim(p)
	T.check(DS().GetDaily(p).Streak == 1 and toastCount(p, "Next gift in 0h 1m", mark) == 1, "daily claim: 19 h 59 m is refused", describeDaily(DS().GetDaily(p)))
	setLast(p, os.time() - 72000)
	claim(p)
	T.check(DS().GetDaily(p).Streak == 2 and DS().GetTokens(p) == t0 + 50, "daily claim: exactly 20 h (gap == ReadySeconds) day 2 pays 50 Tokens (boundary)", describeDaily(DS().GetDaily(p)) .. " tokens +" .. (DS().GetTokens(p) - t0))
	local gems0 = DS().GetGems(p)
	setLast(p, os.time() - 172800)
	claim(p)
	T.check(DS().GetDaily(p).Streak == 3 and DS().GetGems(p) == gems0 + 10, "daily claim: exactly 48 h (gap == KeepSeconds) is still kept (boundary), day 3 = 10 Gems", describeDaily(DS().GetDaily(p)))
	mark = K.logSize()
	setLast(p, os.time() - 172801)
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 3 and d.Paid == 3 and DS().GetGems(p) == gems0 + 10 and toastCount(p, "Streak repaired! Day 3 of 7", mark) == 1, "daily claim: one second past 48 h steps back one day (Streak 3 again, nothing paid: Paid 3 stays)", describeDaily(d))
	-- Cash = max(Min, income x minutes): a home with stations gives a known income; day 4 pays 5 income-minutes
	local index = claimFree(p)
	if T.check(index ~= nil, "daily claim: (setup) a home for the income") then
		setStations(p, { House = 4, Press1 = 1, Garden = 1 })
	end
	local income = TS().IncomePerSecond(p)
	local expected = math.max(1000, math.floor(income * 300))
	DSV().Send(p)
	st = lastState(p)
	T.check(st ~= nil and st.Days[4].Amount == expected, "daily claim: the payload resolves the Cash cell from the current income", "income " .. tostring(income) .. " amount " .. tostring(st and st.Days[4].Amount) .. " expected " .. expected)
	cash0 = DS().GetCash(p)
	mark = K.logSize()
	setLast(p, os.time() - 72000)
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 4 and d.Paid == 4 and DS().GetCash(p) == cash0 + expected and toastCount(p, "+$" .. commas(expected) .. " Cash! Day 4 of 7", mark) == 1,
		"daily claim: day 4 pays max(Min 1000, income x 300 s) = $" .. commas(expected), describeDaily(d) .. " cash +" .. (DS().GetCash(p) - cash0) .. " income " .. tostring(income))
	finish("daily_claim", p)
end)

----------------------------------------------------------------------------------------------------
-- daily_week
----------------------------------------------------------------------------------------------------
S.daily_week = guarded("daily_week", function()
	if not K.needBoot() then
		return
	end
	local p = join("Week", newUserId())
	loaded(p)
	local mark = K.logSize()
	for day = 1, 6 do
		claim(p)
		elapse(p, 72000)
	end
	local d = DS().GetDaily(p)
	T.check(d.Streak == 6 and d.Paid == 6 and d.Weeks == 0 and d.Pet == false and (pets(p)[WISP] or 0) == 0, "daily week: six kept days, no pet yet", describeDaily(d))
	mark = K.logSize()
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 7 and d.Pet == true and d.Weeks == 1 and (pets(p)[WISP] or 0) == 1 and toastCount(p, "WEEK DONE! Week Wisp is yours!", mark) == 1,
		"daily week: day 7 grants the Week Wisp (Pet true, Weeks 1, the toast)", describeDaily(d) .. " wisps " .. tostring(pets(p)[WISP]))
	local st = lastState(p)
	T.check(st ~= nil and st.Streak == 7 and st.Weeks == 1 and st.Days[7].Claimed == true and st.Cell == 1, "daily week: the payload shows the full week and Weeks 1")
	local cash0 = DS().GetCash(p)
	mark = K.logSize()
	elapse(p, 72000)
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 8 and d.Paid == 8 and DS().GetCash(p) == cash0 + 400 and toastCount(p, "+$400 Cash! Day 1 of 7", mark) == 1, "daily week: claim 8 is cell 1 of week 2 and pays Cash", describeDaily(d))
	st = lastState(p)
	T.check(st ~= nil and st.Days[1].Claimed == true and st.Days[2].Claimed == false and st.Days[7].Claimed == false and st.Cell == 2, "daily week: week 2's strip shows one claimed cell")
	for day = 9, 13 do
		elapse(p, 72000)
		claim(p)
	end
	mark = K.logSize()
	elapse(p, 72000)
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 14 and d.Weeks == 2 and (pets(p)[WISP] or 0) == 2 and toastCount(p, "WEEK DONE! Week Wisp is yours!", mark) == 1, "daily week: claim 14 grants a SECOND Week Wisp (13b.2)", describeDaily(d) .. " wisps " .. tostring(pets(p)[WISP]))
	for day = 15, 20 do
		elapse(p, 72000)
		claim(p)
	end
	T.eq(DS().GetDaily(p).Streak, 20, "daily week: (setup) six more kept days")
	DS().GetProfile(p).Pets[WISP] = config().Pets.MaxPerStack
	DSV().Send(p)
	st = lastState(p)
	T.check(st ~= nil and st.Days[7].Kind == "Gems" and st.Days[7].Amount == 40, "daily week: with a full stack the payload's cell 7 is the Else (40 Gems)")
	local gems0 = DS().GetGems(p)
	mark = K.logSize()
	elapse(p, 72000)
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 21 and d.Weeks == 3 and DS().GetGems(p) == gems0 + 40 and pets(p)[WISP] == config().Pets.MaxPerStack and toastCount(p, "+40 Gems! Day 7 of 7", mark) == 1,
		"daily week: claim 21 on a full stack pays the Else (+40 Gems) and no copy", describeDaily(d) .. " gems +" .. (DS().GetGems(p) - gems0))
	finish("daily_week", p)
end)

----------------------------------------------------------------------------------------------------
-- daily_miss
----------------------------------------------------------------------------------------------------
S.daily_miss = guarded("daily_miss", function()
	if not K.needBoot() then
		return
	end
	local a = join("MissA", newUserId())
	loaded(a)
	atStreak7(a, 47 * HOUR + 59 * 60)
	local cash0 = DS().GetCash(a)
	claim(a)
	local d = DS().GetDaily(a)
	T.check(d.Streak == 8 and d.Paid == 8 and DS().GetCash(a) == cash0 + 400, "daily miss: 47 h 59 m after day 7 the streak is kept and day 8 (cell 1) pays", describeDaily(d))
	leave(a)

	local b = join("MissB", newUserId())
	loaded(b)
	atStreak7(b, 49 * HOUR)
	cash0 = DS().GetCash(b)
	local gems0, tokens0 = DS().GetGems(b), DS().GetTokens(b)
	local mark = K.logSize()
	local ok, result = DSV().Claim(b)
	advance(1.05)
	d = DS().GetDaily(b)
	T.check(ok == true and type(result) == "table" and result.StepBack == 1 and result.Streak == 7 and result.Cell == 7 and result.Grant == nil, "daily miss: 49 h -> the claim answers Streak 7, StepBack 1, no grant", tostring(ok) .. " " .. tostring(type(result) == "table" and (result.Streak .. "/" .. result.StepBack) or result))
	T.check(d.Streak == 7 and d.Paid == 7 and DS().GetCash(b) == cash0 and DS().GetGems(b) == gems0 and DS().GetTokens(b) == tokens0 and (pets(b)[WISP] or 0) == 0 and toastCount(b, "Streak repaired! Day 7 of 7", mark) == 1,
		"daily miss: ...nothing paid (Paid 7 stays), the repair toast", describeDaily(d))
	local st = lastState(b)
	T.check(st ~= nil and st.StepBack == 1 and st.Streak == 7, "daily miss: the payload carries StepBack 1 once", tostring(st and st.StepBack))
	DSV().Send(b)
	st = lastState(b)
	T.check(st ~= nil and (st.StepBack == 0 or st.StepBack == nil), "daily miss: ...and 0 on the next payload", tostring(st and st.StepBack))
	elapse(b, 72000)
	cash0 = DS().GetCash(b)
	claim(b)
	d = DS().GetDaily(b)
	T.check(d.Streak == 8 and d.Paid == 8 and DS().GetCash(b) == cash0 + 400, "daily miss: 20 h later the next claim is day 8, cell 1 pays", describeDaily(d))
	leave(b)

	local c = join("MissC", newUserId())
	loaded(c)
	atStreak7(c, 10 * 86400)
	cash0 = DS().GetCash(c)
	ok, result = DSV().Claim(c)
	advance(1.05)
	d = DS().GetDaily(c)
	T.check(ok == true and result.StepBack == 9 and d.Streak == 1 and d.Paid == 7 and d.Weeks == 1 and DS().GetCash(c) == cash0, "daily miss: ten days away steps back to Streak 1 (Paid 7 kept, nothing paid, Weeks never drops)", describeDaily(d) .. " stepBack " .. tostring(type(result) == "table" and result.StepBack))
	finish("daily_miss", c)
end)

----------------------------------------------------------------------------------------------------
-- daily_provisional
----------------------------------------------------------------------------------------------------
S.daily_provisional = guarded("daily_provisional", function()
	if not K.needBoot() then
		return
	end
	local DSt = Mock.DataStore
	local uid = newUserId()
	local P = os.time() - 600
	DSt.Data[storeKey(uid)] = {
		Version = 2, Tokens = 3, Pets = {}, Equipped = {}, Items = {}, Stats = statsOf(),
		Daily = { Streak = 2, Paid = 2, LastClaimAt = os.time() - 3600, Weeks = 0, Pet = false, PlayStart = P, PlaySec = 420, PlayClaimed = { true } },
	}
	local p = nil
	local okRun, errRun = pcall(function()
		local mark = K.logSize()
		DSt.Fail = true
		p = Mock.AddPlayer("DailyProv" .. tostring(uid % 1000), uid)
		advance(4)
		if not T.check(DS().GetProfile(p) ~= nil and DS().IsProvisional(p) == true, "daily provisional: (precondition) a load during an outage leaves a provisional profile") then
			return
		end
		local real, loading = 0, 0
		for _, e in ipairs(states(p, mark)) do
			if type(e.args[1]) == "table" and e.args[1].Loading == true then
				loading = loading + 1
			else
				real = real + 1
			end
		end
		T.check(real == 0 and loading >= 1, "daily provisional: only Loading payloads reached the client", "real " .. real .. " loading " .. loading)
		local cash0, tokens0 = DS().GetCash(p), DS().GetTokens(p)
		mark = K.logSize()
		claim(p)
		T.check(toastCount(p, "Your save is still loading", mark) == 1 and DS().GetCash(p) == cash0 and DS().GetTokens(p) == tokens0 and DS().GetProfile(p).Daily.Streak == 0, "daily provisional: the claim is refused, nothing added")
		claimPlay(p, 1)
		T.check(toastCount(p, "Your save is still loading", mark) == 2 and DS().GetCash(p) == cash0, "daily provisional: a play claim is refused too")
		alignTicks()
		for i = 1, 30 do
			moveRoot(p, 3)
			tick()
		end
		local standIn = DS().GetProfile(p).Daily
		T.check((standIn.PlaySec or 0) == 0 and (standIn.PlayStart or 0) == 0, "daily provisional: 30 moving ticks add nothing to the stand-in (no tick while provisional)", "PlaySec " .. tostring(standIn.PlaySec) .. " PlayStart " .. tostring(standIn.PlayStart))
		mark = K.logSize()
		DSt.Fail = false
		-- DataService retries the load at 20 / 40 / 80 / 160 / 300 s: the ticks above used the early retries
		T.check(K.waitFor(function()
			return DS().IsProvisional(p) ~= true
		end, 400), "daily provisional: (the recovery reads the real save)")
		advance(1)
		local d = DS().GetDaily(p)
		T.check(d ~= nil and d.PlayStart == P and d.PlaySec == 420 and d.PlayClaimed[1] == true and d.Streak == 2, "daily provisional: the live Daily is the stored one after the recovery", describeDaily(d))
		real = 0
		for _, e in ipairs(states(p, mark)) do
			if type(e.args[1]) == "table" and e.args[1].Loading ~= true then
				real = real + 1
			end
		end
		T.check(real >= 1 and lastState(p).Play.Seconds == 420 and lastState(p).Streak == 2, "daily provisional: a real payload follows the recovery (ProfileRebased)", "real " .. real)
		T.eq(DS().Save(p), true, "daily provisional: the profile saves")
		local rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.PlayStart == P and rec.Daily.PlaySec == 420 and rec.Daily.PlayClaimed[1] == true, "daily provisional: the stored Play group is untouched (a stand-in never wins PlayStart)", "PlayStart " .. tostring(rec.Daily and rec.Daily.PlayStart) .. " PlaySec " .. tostring(rec.Daily and rec.Daily.PlaySec))
	end)
	DSt.Fail = false
	if p then
		leave(p)
	end
	advance(2)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("daily_provisional")
	K.flushWarnings("daily_provisional", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- daily_two_servers
----------------------------------------------------------------------------------------------------
S.daily_two_servers = guarded("daily_two_servers", function()
	if not K.needBoot() then
		return
	end
	local D = DS()
	local READY = config().Daily.ReadySeconds
	local B, cloneB, releaseB = secondServer("DataServiceDailyB")
	if not T.check(B ~= nil and type(B.MutateDaily) == "function", "daily two servers: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
		return
	end
	-- B's claims are the same MutateDaily writes + grant tables DailyService makes, driven directly (no second DailyService)
	local function claimB(p, streak, at, cash)
		local ok = B.MutateDaily(p, function(d)
			d.Streak = streak
			d.Paid = math.max(d.Paid or 0, streak)
			d.LastClaimAt = at
			return true
		end, { Kind = "Day", Cash = cash })
		if ok then
			B.AddCash(p, cash)
		end
		return ok
	end
	local okRun, errRun = pcall(function()
		local uid = newUserId()
		local p = join("TwoSrvA", uid)
		loaded(p)
		T.eq(D.Save(p), true, "daily two servers: (setup) the first save")
		B.Load(p)
		advance(0.5)
		local cash0 = (stored(uid) or {}).Cash or 0
		local tA = claim(p)
		local dA = D.GetDaily(p)
		T.check(dA.Streak == 1 and dA.LastClaimAt == tA and D.Save(p) == true, "daily two servers: A claims day 1 through DailyService and saves", describeDaily(dA))
		local rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tA and rec.Daily.Streak == 1 and rec.Cash == cash0 + 400, "daily two servers: the store holds (tA, 1) and +$400", "pair " .. tostring(rec.Daily and rec.Daily.LastClaimAt) .. "/" .. tostring(rec.Daily and rec.Daily.Streak) .. " cash " .. tostring(rec.Cash))
		advance(3600)
		local tB = os.time()
		T.check(claimB(p, 1, tB, 400) and B.GetDaily(p).Streak == 1 and B.Save(p) == true, "daily two servers: B (loaded before A's claim) claims day 1 an hour later: its local Streak is 1, it saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tA and rec.Daily.Streak == 1 and rec.Cash == cash0 + 400, "daily two servers: the store keeps A's pair and the $400 once (B's grant dropped)", "pair " .. tostring(rec.Daily and rec.Daily.LastClaimAt) .. "/" .. tostring(rec.Daily and rec.Daily.Streak) .. " cash " .. tostring(rec.Cash) .. " (base " .. cash0 .. ")")
		advance(READY)
		local tC = os.time()
		T.check(claimB(p, 2, tC, 50) and B.Save(p) == true, "daily two servers: B claims day 2 21 h after A's claim and saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.LastClaimAt == tC and rec.Daily.Streak == 2 and rec.Cash == cash0 + 450, "daily two servers: ...it pays and the store's pair is B's (tC, 2)", "pair " .. tostring(rec.Daily and rec.Daily.LastClaimAt) .. "/" .. tostring(rec.Daily and rec.Daily.Streak) .. " cash " .. tostring(rec.Cash))
		-- a play tier claimed on both servers at one PlayStart pays once
		local P = os.time()
		T.check(D.MutateDaily(p, function(d)
			d.PlayStart = P
			d.PlaySec = 600
			return true
		end), "daily two servers: (setup) A's play clock at 10 min")
		cash0 = (stored(uid) or {}).Cash or 0
		claimPlay(p, 1)
		T.check(D.GetDaily(p).PlayClaimed[1] == true and D.Save(p) == true, "daily two servers: A claims play tier 1 through DailyService and saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.PlayStart == P and rec.Daily.PlayClaimed[1] == true and rec.Cash == cash0 + 200, "daily two servers: the store holds A's Play group and +$200", "cash " .. tostring(rec.Cash) .. " (base " .. cash0 .. ")")
		T.check(B.MutateDaily(p, function(d)
			d.PlayStart = P
			d.PlaySec = 600
			d.PlayClaimed[1] = true
			return true
		end, { Kind = "Play", Tier = 1, Cash = 200 }) and B.AddCash(p, 200) and B.Save(p) == true, "daily two servers: B claims the same tier at the same PlayStart and saves")
		rec = stored(uid) or {}
		T.check(type(rec.Daily) == "table" and rec.Daily.PlayClaimed[1] == true and rec.Cash == cash0 + 200, "daily two servers: the tier paid once (+$200, not +$400)", "cash " .. tostring(rec.Cash) .. " (base " .. cash0 .. ")")
		leave(p)
	end)
	advance(12)
	T.check(releaseB() == true, "daily two servers: server B's hooks are dropped with it")
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("daily_two_servers")
	K.flushWarnings("daily_two_servers", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- daily_future_clock (Review Focus 3 / Z8)
----------------------------------------------------------------------------------------------------
S.daily_future_clock = guarded("daily_future_clock", function()
	if not K.needBoot() then
		return
	end
	local p = join("Future", newUserId())
	loaded(p)
	claim(p)
	T.eq(DS().GetDaily(p).Streak, 1, "daily future clock: (setup) day 1 claimed")
	local now = os.time()
	setLast(p, now + 200)
	local mark = K.logSize()
	claim(p)
	local d = DS().GetDaily(p)
	T.check(d.Streak == 1 and d.LastClaimAt == now + 200 and toastCount(p, "Next gift in 20h 3m", mark) == 1, "daily future clock: a LastClaimAt 200 s ahead (inside the slack) is kept and the claim waits 20h 3m", describeDaily(d))
	now = os.time()
	setLast(p, now + 7200)
	local cash0, tokens0, gems0 = DS().GetCash(p), DS().GetTokens(p), DS().GetGems(p)
	mark = K.logSize()
	local t = claim(p)
	d = DS().GetDaily(p)
	T.check(d.LastClaimAt == t and d.Streak == 1 and d.Paid == 1 and DS().GetCash(p) == cash0 and DS().GetTokens(p) == tokens0 and DS().GetGems(p) == gems0,
		"daily future clock: a LastClaimAt 2 h ahead (past FutureClockSlack) is rewritten to now by the claim, nothing else changes", describeDaily(d) .. " t " .. t)
	T.check(toastCount(p, "Next gift in 20h 0m", mark) == 1, "daily future clock: ...and the claim is refused this once with 'Next gift in 20h 0m'")
	local st = lastState(p)
	T.check(st ~= nil and st.ReadyAt == t + config().Daily.ReadySeconds, "daily future clock: the payload after it shows the next gift 20 h on", tostring(st and st.ReadyAt) .. " vs " .. (t + config().Daily.ReadySeconds))
	K.advance(72000)
	tokens0 = DS().GetTokens(p)
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 2 and DS().GetTokens(p) == tokens0 + 50, "daily future clock: 20 h later the claim pays (a wrong-clock server never locks a player out for hours)", describeDaily(d))
	finish("daily_future_clock", p)
end)

----------------------------------------------------------------------------------------------------
-- daily_rejoin
----------------------------------------------------------------------------------------------------
S.daily_rejoin = guarded("daily_rejoin", function()
	if not K.needBoot() then
		return
	end
	local uid = newUserId()
	local p = join("Rejoin", uid)
	loaded(p)
	local P = os.time() - 60
	T.check(setDaily(p, { PlayStart = P, PlaySec = 600 }) and DS().Save(p) == true, "daily rejoin: (setup) 10 min of play saved")
	leave(p)
	p = join("Rejoin", uid)
	loaded(p)
	advance(0.5)
	local st = lastState(p)
	T.check(st ~= nil and st.Play.Seconds == 600 and st.Play.Tiers[1].Ready == true and st.Play.Tiers[2].Ready == false and st.Play.DayEnds == P + config().Daily.Play.DaySeconds,
		"daily rejoin: the payload after the rejoin shows 600 s, tier 1 ready, the day's end", st and ("Seconds " .. tostring(st.Play.Seconds) .. " DayEnds " .. tostring(st.Play.DayEnds)) or "no payload")
	local cash0 = DS().GetCash(p)
	local mark = K.logSize()
	claimPlay(p, 1)
	local d = DS().GetDaily(p)
	T.check(d.PlayClaimed[1] == true and DS().GetCash(p) == cash0 + 200 and toastCount(p, "+$200 Cash!", mark) == 1, "daily rejoin: play tier 1 pays $200", describeDaily(d) .. " cash +" .. (DS().GetCash(p) - cash0))
	st = lastState(p)
	T.check(st ~= nil and st.Play.Tiers[1].Claimed == true and st.Play.Tiers[1].Ready == false, "daily rejoin: the payload marks the tier claimed")
	mark = K.logSize()
	claimPlay(p, 1)
	T.check(DS().GetCash(p) == cash0 + 200 and toastCount(p, "You already claimed that!", mark) == 1, "daily rejoin: the second claim of the tier pays nothing, 'You already claimed that!'")
	mark = K.logSize()
	claimPlay(p, 2)
	T.check(DS().GetCash(p) == cash0 + 200 and DS().GetDaily(p).PlayClaimed[2] == nil and toastCount(p, "more minute", mark) == 1, "daily rejoin: tier 2 (20 min) is not ready at 10 min")
	finish("daily_rejoin", p)
end)

----------------------------------------------------------------------------------------------------
-- daily_idle
----------------------------------------------------------------------------------------------------
S.daily_idle = guarded("daily_idle", function()
	if not K.needBoot() then
		return
	end
	local p = join("Idle", newUserId())
	loaded(p)
	alignTicks()
	local mark = K.logSize()
	tick(60)
	local d = DS().GetDaily(p)
	T.check(d.PlaySec == 0 and d.PlayStart == 0 and #states(p, mark) == 0, "daily idle: 10 min of ticks with the root still and no remote add nothing and send nothing", describeDaily(d) .. " payloads " .. #states(p, mark))
	mark = K.logSize()
	Mock.FromClient(remote("HomeAction"), p, "Nope")
	tick(18)
	d = DS().GetDaily(p)
	T.check(d.PlaySec >= 170 and d.PlaySec <= 180 and d.PlayStart > 0, "daily idle: one HomeAction remote makes the next 18 ticks count (<= 180 s)", describeDaily(d))
	local sent = states(p, mark)
	T.check(#sent == 1 and sent[1].args[1].Play.Active == true, "daily idle: the flip to active sent ONE payload (Play.Active true), none per tick", "payloads " .. #sent)
	local before = d.PlaySec
	mark = K.logSize()
	tick(2)
	d = DS().GetDaily(p)
	sent = states(p, mark)
	T.check(d.PlaySec == before and #sent == 1 and sent[1].args[1].Play.Active == false, "daily idle: the 19th tick (past ActiveWindow) adds nothing and the flip to paused sent one payload", describeDaily(d) .. " payloads " .. #sent)
	mark = K.logSize()
	moveRoot(p, 3)
	tick()
	d = DS().GetDaily(p)
	sent = states(p, mark)
	T.check(d.PlaySec == before + 10 and #sent == 1 and sent[1].args[1].Play.Active == true, "daily idle: a root moved 3 studs makes that tick count (and flips active once)", describeDaily(d) .. " payloads " .. #sent)
	mark = K.logSize()
	moveRoot(p, 1)
	tick()
	d = DS().GetDaily(p)
	sent = states(p, mark)
	T.check(d.PlaySec == before + 10 and #sent == 1 and sent[1].args[1].Play.Active == false, "daily idle: moved 1 stud (< MoveStuds 2) does not count and flips paused once", describeDaily(d) .. " payloads " .. #sent)
	mark = K.logSize()
	tick(3)
	T.check(DS().GetDaily(p).PlaySec == before + 10 and #states(p, mark) == 0, "daily idle: still ticks send nothing")
	finish("daily_idle", p)
end)

----------------------------------------------------------------------------------------------------
-- daily_playday (Q17, Review Focus 4)
----------------------------------------------------------------------------------------------------
S.daily_playday = guarded("daily_playday", function()
	if not K.needBoot() then
		return
	end
	local Pcfg = config().Daily.Play
	local D = DSV()
	local p = join("PlayDay", newUserId())
	loaded(p)
	alignTicks()
	local P = os.time() - 100
	setDaily(p, { PlayStart = P, PlaySec = Pcfg.MaxDaySeconds - 10 })
	moveRoot(p, 3)
	tick()
	local d = DS().GetDaily(p)
	T.check(d.PlaySec == Pcfg.MaxDaySeconds and d.PlayStart == P, "daily playday: a moving tick reaches the 10 h cap", describeDaily(d))
	moveRoot(p, 3)
	tick()
	d = DS().GetDaily(p)
	T.check(d.PlaySec == Pcfg.MaxDaySeconds, "daily playday: ...and stays capped", describeDaily(d))
	DSV().Send(p)
	local st = lastState(p)
	T.check(st ~= nil and st.Play.Tiers[7].Ready == true and st.Play.Tiers[7].Claimed == false, "daily playday: tier 7 (180 min) is ready and unclaimed")
	-- the play-day rolls over: the first moving tick >= 20 h after PlayStart starts a new day; the unclaimed tier is gone
	local cash0, gems0 = DS().GetCash(p), DS().GetGems(p)
	setDaily(p, { PlayStart = os.time() - Pcfg.DaySeconds - 5 })
	local mark = K.logSize()
	moveRoot(p, 3)
	local tTick = os.time()
	tick()
	d = DS().GetDaily(p)
	T.check(d.PlayStart >= tTick and d.PlayStart <= tTick + 10 and d.PlaySec == Pcfg.TickSeconds and next(d.PlayClaimed) == nil and DS().GetGems(p) == gems0 and DS().GetCash(p) == cash0,
		"daily playday: a tick past the 20 h play-day starts a new one (PlayStart now, PlaySec 10, PlayClaimed {}) and the ready tier is lost unpaid (Q17)", describeDaily(d))
	st = lastState(p)
	T.check(st ~= nil and st.Play.Tiers[7].Ready == false and st.Play.Seconds == Pcfg.TickSeconds, "daily playday: the reset sent a payload with the tier gone")
	local start = d.PlayStart
	-- Review Focus 4: the three "no body" cases run the tick DIRECTLY (DailyService.Tick is what the loop calls): the lobby
	-- respawns a character-less player within a tick, so a loop tick would see the fresh character at the spawn
	local char = p.Character
	p.Character = nil
	D.Tick()
	d = DS().GetDaily(p)
	T.check(d.PlaySec == Pcfg.TickSeconds and d.PlayStart == start, "daily playday: a tick with no Character adds nothing and resets nothing", describeDaily(d))
	p.Character = char
	local root = K.root(p)
	if root then
		root:Destroy()
	end
	D.Tick()
	d = DS().GetDaily(p)
	T.check(d.PlaySec == Pcfg.TickSeconds and d.PlayStart == start, "daily playday: a tick with no HumanoidRootPart adds nothing and resets nothing", describeDaily(d))
	Mock.Respawn(p)
	advance(0.2)
	T.check(K.root(p) ~= nil and K.hum(p) ~= nil, "daily playday: (setup) the character is back")
	D.Tick() -- the sample on the new body (at the spawn: that tick may count as a move)
	local kept = DS().GetDaily(p).PlaySec
	K.hum(p).Health = 0
	moveRoot(p, 3)
	D.Tick()
	d = DS().GetDaily(p)
	T.check(d.PlaySec == kept and d.PlayStart == start, "daily playday: a dead Humanoid (root moved 3 studs) adds nothing and resets nothing", describeDaily(d) .. " kept " .. kept)
	local old = p.Character
	T.check(K.waitFor(function()
		return p.Character ~= nil and p.Character ~= old and K.hum(p) ~= nil and K.hum(p).Health > 0
	end, 12) or (Mock.Respawn(p) and K.hum(p) ~= nil and K.hum(p).Health > 0), "daily playday: (setup) the player respawns")
	alignTicks()
	kept = DS().GetDaily(p).PlaySec
	moveRoot(p, 3)
	tick()
	d = DS().GetDaily(p)
	T.check(d.PlaySec == kept + Pcfg.TickSeconds and d.PlayStart == start, "daily playday: once the character is back the next moving tick counts again from the kept seconds", describeDaily(d) .. " kept " .. kept)
	finish("daily_playday", p)
end)

----------------------------------------------------------------------------------------------------
-- daily_remote
----------------------------------------------------------------------------------------------------
S.daily_remote = guarded("daily_remote", function()
	if not K.needBoot() then
		return
	end
	local D = DSV()
	local p = join("Remote", newUserId())
	loaded(p)
	setDaily(p, { PlayStart = os.time() - 60, PlaySec = 600 })
	local cash0, tokens0, gems0 = DS().GetCash(p), DS().GetTokens(p), DS().GetGems(p)
	local mark = K.logSize()
	request(p, "Claim", {})
	request(p, "ClaimPlay", "x")
	request(p, "ClaimPlay", 8)
	request(p, "ClaimPlay", 1.5)
	request(p, "ClaimPlay", 0 / 0)
	request(p, "ClaimPlay")
	request(p, 42)
	request(p, "Nope")
	advance(1.05)
	local d = DS().GetDaily(p)
	T.check(d.Streak == 0 and next(d.PlayClaimed) == nil and DS().GetCash(p) == cash0 and #K.remotesFor("Notify", p.UserId, mark) == 0, "daily remote: junk arguments change nothing and answer nothing", describeDaily(d) .. " toasts " .. #K.remotesFor("Notify", p.UserId, mark))
	mark = K.logSize()
	for i = 1, 10 do
		request(p, "Claim")
	end
	advance(1.05)
	d = DS().GetDaily(p)
	T.check(d.Streak == 1 and DS().GetCash(p) == cash0 + 400 and toastCount(p, "Day 1 of 7", mark) == 1, "daily remote: 10 Claims in a second -> 1 handled (one grant, one toast)", describeDaily(d) .. " cash +" .. (DS().GetCash(p) - cash0))
	p:SetAttribute(config().Attr.InMatch, true)
	mark = K.logSize()
	elapse(p, 72000)
	claim(p)
	claimPlay(p, 1)
	d = DS().GetDaily(p)
	local texts = {}
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark)) do
		texts[#texts + 1] = tostring(e.args[1])
	end
	T.check(d.Streak == 1 and next(d.PlayClaimed) == nil and toastCount(p, "match", mark) == 2, "daily remote: InMatch refuses both claims with a toast", describeDaily(d) .. " toasts: " .. table.concat(texts, " | "))
	p:SetAttribute(config().Attr.InMatch, false)
	-- no StoreService / a pass with Id 0: never VIP, and a step-back due never waits on "Checking"
	local deps = D._deps()
	local savedStore = deps.StoreService
	atStreak7(p, 49 * HOUR)
	mark = K.logSize()
	claim(p)
	d = DS().GetDaily(p)
	T.check(d.Streak == 7 and d.Paid == 7 and toastCount(p, "Streak repaired! Day 7 of 7", mark) == 1 and toastCount(p, "Checking", mark) == 0,
		"daily remote: without a VIP answer (StoreService absent or the pass Id 0) a step-back due is applied, never held on 'Checking'", describeDaily(d))
	elapse(p, 72000)
	cash0 = DS().GetCash(p)
	claim(p)
	T.check(DS().GetDaily(p).Streak == 8 and DS().GetCash(p) == cash0 + 400, "daily remote: ...and the Cash cell pays x1", "cash +" .. (DS().GetCash(p) - cash0))
	-- VIP through the seam
	local okRun, errRun = pcall(function()
		deps.StoreService = {
			Owns = function()
				return true
			end,
			PassState = function()
				return "Owned"
			end,
		}
		D.Send(p)
		local st = lastState(p)
		T.check(st ~= nil and st.Vip == true and st.Days[1].Amount == 800 and st.Days[2].Amount == 100 and st.Days[3].Amount == 10 and st.Play.Tiers[1].Amount == 200 and st.Play.Tiers[2].Amount == 40,
			"daily remote: the VIP payload doubles the Cash / Tokens cells, not Gems, not the play tiers", st and ("Days " .. tostring(st.Days[1].Amount) .. "/" .. tostring(st.Days[2].Amount) .. "/" .. tostring(st.Days[3].Amount) .. " tiers " .. tostring(st.Play.Tiers[1].Amount)) or "no payload")
		elapse(p, 72000)
		tokens0 = DS().GetTokens(p)
		mark = K.logSize()
		claim(p)
		T.check(DS().GetDaily(p).Streak == 9 and DS().GetTokens(p) == tokens0 + 100 and toastCount(p, "+100 Tokens! Day 2 of 7", mark) == 1, "daily remote: VIP: the Tokens cell pays x2", "tokens +" .. (DS().GetTokens(p) - tokens0))
		elapse(p, 72000)
		gems0 = DS().GetGems(p)
		claim(p)
		T.check(DS().GetDaily(p).Streak == 10 and DS().GetGems(p) == gems0 + 10, "daily remote: VIP: the Gems cell pays x1", "gems +" .. (DS().GetGems(p) - gems0))
		cash0 = DS().GetCash(p)
		claimPlay(p, 1)
		T.check(DS().GetCash(p) == cash0 + 200, "daily remote: VIP: the play tiers pay x1", "cash +" .. (DS().GetCash(p) - cash0))
		elapse(p, 72000)
		cash0 = DS().GetCash(p)
		claim(p)
		T.check(DS().GetDaily(p).Streak == 11 and DS().GetCash(p) == cash0 + 2000, "daily remote: VIP: the Cash cell pays x2 (day 4: $1000 x 2)", "cash +" .. (DS().GetCash(p) - cash0))
		elapse(p, 49 * HOUR)
		tokens0 = DS().GetTokens(p)
		claim(p)
		d = DS().GetDaily(p)
		T.check(d.Streak == 12 and d.Paid == 12 and DS().GetTokens(p) == tokens0 + 500, "daily remote: VIP: a 49 h gap never steps back (Streak +1, day 5 pays 250 x 2 Tokens)", describeDaily(d))
		-- "Checking" (Owns false): only a claim with a step-back due waits
		deps.StoreService = {
			Owns = function()
				return false
			end,
			PassState = function()
				return "Checking"
			end,
		}
		elapse(p, 49 * HOUR)
		local before = DS().GetDaily(p)
		mark = K.logSize()
		claim(p)
		d = DS().GetDaily(p)
		T.check(d.Streak == before.Streak and d.LastClaimAt == before.LastClaimAt and d.Paid == before.Paid and toastCount(p, "Checking your VIP pass, one moment", mark) == 1, "daily remote: a step-back due while the pass is Checking waits, nothing written", describeDaily(d))
		setLast(p, os.time() - 72000)
		gems0 = DS().GetGems(p)
		mark = K.logSize()
		claim(p)
		d = DS().GetDaily(p)
		T.check(d.Streak == 13 and d.Paid == 13 and DS().GetGems(p) == gems0 + 25 and toastCount(p, "Checking", mark) == 0, "daily remote: Checking with NO step-back due goes through as a non-VIP (day 6: 25 Gems)", describeDaily(d))
	end)
	deps.StoreService = savedStore
	if not okRun then
		error(errRun, 0)
	end
	finish("daily_remote", p)
end)

----------------------------------------------------------------------------------------------------
-- daily_quiet_join
----------------------------------------------------------------------------------------------------
S.daily_quiet_join = guarded("daily_quiet_join", function()
	if not K.needBoot() then
		return
	end
	local uid = newUserId()
	local loadedAt = nil
	local conn = DS().ProfileLoaded:Connect(function(player)
		if player.UserId == uid and loadedAt == nil then
			loadedAt = os.clock()
		end
	end)
	local mark = K.logSize()
	local p = Mock.AddPlayer("Quiet" .. tostring(uid % 1000), uid)
	advance(20)
	conn:Disconnect()
	T.eq(dailyToasts(p, mark), 0, "daily quiet join: no gift / streak / week toast in the first 20 s")
	local list = states(p, mark)
	local first = nil
	for _, e in ipairs(list) do
		if type(e.args[1]) == "table" and e.args[1].Loading ~= true then
			first = e
			break
		end
	end
	T.check(loadedAt ~= nil and first ~= nil and first.time - loadedAt <= 1 and first.time >= loadedAt - 0.01, "daily quiet join: the DailyState payload arrived within 1 s of ProfileLoaded", "loaded " .. tostring(loadedAt) .. " payload " .. tostring(first and first.time))
	T.check(first ~= nil and first.args[1].ReadyAt <= first.args[1].ServerNow and first.args[1].Streak == 0, "daily quiet join: ReadyAt <= ServerNow on it (the client decides the pip after PipDelaySeconds)")
	finish("daily_quiet_join", p)
end)

return S
