-- smoke_p4_fix_server.lua: regression checks for the Phase 4 review fixes on the SERVER side (fix:server). Server
-- world only, booted.
--   p4fixsrv_prestige_refund  Cash parked in running training jobs does not cross a Prestige: right after
--                             TycoonService.Prestige every running Job.Paid is 0 (the jobs keep running and still
--                             finish for their rank, 3.7), so PetCareService.TrainStop after the prestige returns the
--                             pet with 0 Cash ("stopped training", no "back"); a Stop in the new run still refunds once
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local floor = math.floor
local advance, config, mod = K.advance, K.config, K.mod
local ALLOWED_WARNINGS = { "[DataService]" }
-- a Sky Castle home at Home Level 52 with a Lv 5 Training Place: ready to prestige
local PRESTIGE_READY = { Press1 = 15, Garden = 8, Kitchen = 5, Gym = 5, Vault = 5, House = 4 } -- Phase 5: 11 stations (Berry Farm)

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
local function PK()
	return requireAt("shared/PetKeys")
end
local function PC()
	return requireAt("shared/PetCatalog")
end
local function DS()
	return mod("DataService")
end

local userSeq = 0
local function join(prefix)
	userSeq = userSeq + 1
	local uid = 979500 + userSeq
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
	advance(2.1) -- one TycoonService tick builds the stations, one PetCareService tick dresses the prompts
end

local function givePet(p, key, n)
	local prof = DS().GetProfile(p)
	local ok = PK().Add(prof, key, n or 1)
	DS().MarkDirty(p)
	return ok
end

-- a non-Secret, non-event catalog pet of that role (and rarity)
local function pickPet(role, rarity)
	for _, def in ipairs(PC().Pets) do
		if def.EventOnly ~= true and def.Role == role and def.Rarity ~= "Secret" and (rarity == nil or def.Rarity == rarity) then
			return def
		end
	end
	return nil
end

local function growthOf(p, key)
	return DS().GetGrowth(p, key)
end

local function jobText(g)
	local job = type(g) == "table" and g.Job or nil
	if type(job) ~= "table" then
		return "no job"
	end
	return tostring(job.Stat) .. " rank " .. tostring(job.Rank) .. " paid " .. tostring(job.Paid) .. " ends " .. tostring(job.Ends)
end

-- Notify texts sent to a player since `mark` that contain `needle` (plain text)
local function toastCount(p, needle, mark)
	local n = 0
	for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
		if string.find(tostring(e.args[1]), needle, 1, true) then
			n = n + 1
		end
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- p4fixsrv_prestige_refund (ARCHITECTURE_V3.md "Phase 4 build contract" 3.7: a prestige keeps the running jobs; the
-- Prestige rule: Cash resets. Before the fix a Stop after the prestige paid Job.Paid back in full, so up to five
-- expensive jobs started right before the star pad carried their Cash into the new run.)
----------------------------------------------------------------------------------------------------
S.p4fixsrv_prestige_refund = guarded("p4fixsrv_prestige_refund", function()
	if not K.needBoot() then
		return
	end
	local Care, Ty, Cat = PCS(), TS(), TC()
	local DataS = DS()
	if not Care or not Ty or not Cat or not DataS or not PK() or not PC() then
		T.fail("p4fixsrv refund: PetCareService, TycoonService, TycoonCatalog, DataService, PetKeys and PetCatalog load")
		return
	end
	local eco = pickPet("Economy", "Common")
	local big = pickPet("Combat", "Legendary") or pickPet("Economy", "Legendary") or pickPet("Combat")
	if not eco or not big or eco.Id == big.Id then
		T.fail("p4fixsrv refund: (precondition) two different catalog pets")
		return
	end
	local p = join("P4Carry")
	local idx = claimFree(p)
	if not T.check(idx ~= nil, "p4fixsrv refund: (precondition) a plot is claimed") then
		leave(p)
		return
	end
	setStations(p, PRESTIGE_READY)
	DataS.AddCash(p, 2000000)
	givePet(p, eco.Id)
	givePet(p, big.Id)
	T.check(Cat.CanPrestige(DataS.GetHome(p)) == true, "p4fixsrv refund: (setup) the home is ready to prestige")

	-- park Cash in two jobs right before the star pad
	local okA, jobA = Care.Train(p, big.Id, "Physique")
	local okB, jobB = Care.Train(p, eco.Id, "Speed")
	T.check(okA == true and okB == true, "p4fixsrv refund: (setup) two training jobs start", tostring(jobA) .. " / " .. tostring(jobB))
	local costA = okA and type(jobA) == "table" and floor(jobA.Cost or 0) or 0
	local costB = okB and type(jobB) == "table" and floor(jobB.Cost or 0) or 0
	T.check(costA > 0 and costB > 0, "p4fixsrv refund: (setup) both jobs cost Cash", tostring(costA) .. " / " .. tostring(costB))
	local gA0 = growthOf(p, big.Id)
	T.check(type(gA0.Job) == "table" and floor(gA0.Job.Paid or 0) == costA, "p4fixsrv refund: (setup) the job remembers what it cost", jobText(gA0))
	local endsA = type(gA0.Job) == "table" and gA0.Job.Ends or nil
	local endsB = type(growthOf(p, eco.Id).Job) == "table" and growthOf(p, eco.Id).Job.Ends or nil
	local cashBefore = floor(DataS.GetCash(p))
	T.check(cashBefore == 2000000 - costA - costB, "p4fixsrv refund: (setup) the Cash paid left the balance", tostring(cashBefore))

	-- Prestige: Cash 0, both jobs still running, both now worth no refund
	local mark = K.logSize()
	local okPr, whyPr = Ty.Prestige(p)
	advance(1.5)
	local home = DataS.GetHome(p)
	T.check(okPr == true and home ~= nil and home.Prestige == 1, "p4fixsrv refund: the prestige went through", tostring(whyPr))
	T.check(floor(DataS.GetCash(p)) == 0, "p4fixsrv refund: the Cash is 0 right after the prestige", tostring(DataS.GetCash(p)))
	local gA, gB = growthOf(p, big.Id), growthOf(p, eco.Id)
	T.check(type(gA.Job) == "table" and type(gB.Job) == "table" and gA.Job.Ends == endsA and gB.Job.Ends == endsB, "p4fixsrv refund: both jobs survive the prestige (3.7)", jobText(gA) .. " | " .. jobText(gB))
	T.check(type(gA.Job) == "table" and floor(gA.Job.Paid or -1) == 0, "p4fixsrv refund: the prestige clears Job.Paid of a running job", jobText(gA))
	T.check(type(gB.Job) == "table" and floor(gB.Job.Paid or -1) == 0, "p4fixsrv refund: ...of every running job", jobText(gB))
	T.check(DataS.TrainingKeys(p)[big.Id] == true and DataS.TrainingKeys(p)[eco.Id] == true, "p4fixsrv refund: ...and both keys stay locked for training")

	-- Stop after the prestige: the pet comes back, no Cash does
	local okS, back = Care.TrainStop(p, big.Id)
	advance(0.3)
	T.check(okS == true, "p4fixsrv refund: Stop after the prestige still works", tostring(back))
	T.check(back == 0, "p4fixsrv refund: ...and returns 0 Cash", tostring(back))
	T.check(floor(DataS.GetCash(p)) == 0, "p4fixsrv refund: ...the balance stays 0: no Cash crosses the prestige through a refund", tostring(DataS.GetCash(p)))
	T.check(growthOf(p, big.Id).Job == nil and DataS.TrainingKeys(p)[big.Id] == nil, "p4fixsrv refund: ...the stopped pet is free again", jobText(growthOf(p, big.Id)))
	T.check(toastCount(p, "stopped training", mark) == 1 and toastCount(p, " back", mark) == 0, "p4fixsrv refund: ...one 'stopped training' toast without a refund amount")

	-- the other job keeps running and finishes for its rank all the same
	advance(Cat.TrainSeconds(1) + 2)
	local gB2 = growthOf(p, eco.Id)
	T.check(gB2.Job == nil and floor(gB2.Speed or 0) == 1, "p4fixsrv refund: the kept job finishes after the prestige for one rank", jobText(gB2) .. " Speed=" .. tostring(gB2.Speed))
	T.check(floor(DataS.GetCash(p)) == 0, "p4fixsrv refund: ...and a finished job pays no Cash either", tostring(DataS.GetCash(p)))

	-- a Stop in the new run refunds once, as before (the Training Place rebuilt at level 1)
	setStations(p, { Gym = 1 })
	DataS.AddCash(p, 500000)
	local okN, jobN = Care.Train(p, big.Id, "Speed")
	T.check(okN == true and type(jobN) == "table" and floor(jobN.Cost or 0) > 0, "p4fixsrv refund: a new job in the new run starts", tostring(jobN))
	local costN = okN and type(jobN) == "table" and floor(jobN.Cost or 0) or 0
	T.check(floor(DataS.GetCash(p)) == 500000 - costN, "p4fixsrv refund: ...paid from the new balance", tostring(DataS.GetCash(p)))
	local okN2, backN = Care.TrainStop(p, big.Id)
	advance(0.3)
	T.check(okN2 == true and backN == costN and floor(DataS.GetCash(p)) == 500000, "p4fixsrv refund: ...and its Stop refunds exactly once", tostring(backN) .. " cash " .. tostring(DataS.GetCash(p)))
	local okN3 = Care.TrainStop(p, big.Id)
	T.check(okN3 == false and floor(DataS.GetCash(p)) == 500000, "p4fixsrv refund: a second Stop refunds nothing")

	leave(p)
	K.flushErrors("p4fixsrv_prestige_refund")
	K.flushWarnings("p4fixsrv_prestige_refund", ALLOWED_WARNINGS)
end)

return S
