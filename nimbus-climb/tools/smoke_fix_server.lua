-- smoke_fix_server.lua: regression checks for the Phase 2 review fixes on the SERVER side (fix:server). Server world
-- only, booted.
--   fixsrv_training_prestige (Phase 4) a prestige keeps the running training jobs (they finish later for ONE rank),
--                            clears the coin piles and keeps the Garden at L1; leaving right after it refunds nothing
--                            (Cash never carries over a prestige, also not when the prestige came from another
--                            server's save); a Stop in the current run refunds once
--   fixsrv_receipt_merge     one gem purchase is granted once across servers: server A's failed save (kept and
--                            retried as an orphan) lands after server B granted the re-sent receipt and adds no
--                            second grant (but keeps what A's player spent); B granting a receipt A's late save
--                            already stored adds nothing either; the thank-you toast and GemsPurchased wait for the
--                            save and come once
--   fixsrv_prestige_merge    Cash and the prestige Gems follow the prestige rule in the cross-server merge: a stale
--                            prestige-0 session can neither wipe nor add to the Cash of the run the store prestiged
--                            into; when both servers prestiged, the Cash, stations and Collector of both new runs
--                            count and the star reward is paid once; a session that prestiged past a stale write
--                            keeps only its own balance
--   fixsrv_prestige_pad      E on the Prestige pad (prompt "Prestige", a long hold) only opens the Home window on the
--                            prestige confirmation: nothing resets; HomeAction "Upgrade" "Prestige" and
--                            TycoonService.Buy(player, "Prestige") do nothing; a locked pad refuses with its reason;
--                            the window's confirm (HomeAction "Prestige") prestiges
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local abs, floor, max = math.abs, math.floor, math.max
local advance, config, mod = K.advance, K.config, K.mod
local ALLOWED_WARNINGS = { "[DataService]", "[GemService]" }
-- a Sky Castle home at Home Level 52 with a Lv 5 Training Place: ready to prestige
local PRESTIGE_READY = { Press1 = 10, Press2 = 10, Collector = 5, Garden = 8, Kitchen = 5, Gym = 5, Vault = 5, House = 4 }

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
local function GS()
	return requireAt("server/Services/GemService")
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
	return 979100 + userSeq
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

local function homeAction(p, ...)
	Mock.FromClient(remote("HomeAction"), p, ...)
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
	advance(2.1) -- one TycoonService tick builds the stations and the pads, one PetCareService tick dresses the Kitchen
end

-- runs fn(...) in its own thread (it may yield): box.done / box.ok / box.result
local function spawnCall(fn, ...)
	local box = { done = false }
	local args = { n = select("#", ...), ... }
	task.spawn(function()
		local ok, result = pcall(fn, unpack(args, 1, args.n))
		box.ok, box.result, box.done = ok, result, true
	end)
	return box
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

local function stationsText(stations)
	local parts = {}
	for id, lv in pairs(type(stations) == "table" and stations or {}) do
		parts[#parts + 1] = tostring(id) .. "=" .. tostring(lv)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- the BuyPrompt of a station's pad on a plot
local function buyPrompt(info, id)
	if not info or not info.Folder then
		return nil
	end
	for _, d in ipairs(info.Folder:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "BuyPrompt" then
			local node, sid = d, nil
			for _ = 1, 6 do
				if typeof(node) ~= "Instance" then
					break
				end
				sid = node:GetAttribute("StationId")
				if sid ~= nil then
					break
				end
				node = node.Parent
			end
			if sid == id then
				return d
			end
		end
	end
	return nil
end

-- walks onto the pad and presses E
local function pressPrompt(p, prompt)
	local parent = prompt.Parent
	if typeof(parent) == "Instance" and parent:IsA("BasePart") then
		Mock.Teleport(p, CFrame.new(parent.Position + Vector3.new(0, 3, 0)))
	end
	Mock.Trigger(prompt, p)
	advance(0.4)
end

-- the save another server writes after IT prestiged from `rec` (stations reset but the decor, `cash`, the star-1
-- reward) and built `extra` since, with `collector` Cash in its Collector
local function prestigeElsewhere(rec, cash, extra, collector)
	local Cat = TC()
	local h = type(rec.Home) == "table" and rec.Home or {}
	local stations = Cat.StationsAfterPrestige(h.Stations)
	for id, lv in pairs(extra or {}) do
		stations[id] = lv
	end
	rec.Home = {
		Level = Cat.HomeLevelOf({ Stations = stations }),
		Prestige = 1,
		Stations = stations,
		Garden = h.Garden,
		Gym = h.Gym,
		CollectorCash = collector or 0,
		LastSeen = h.LastSeen,
	}
	rec.Cash = cash
	rec.Gems = (rec.Gems or 0) + floor(Cat.PrestigeGems(1))
end

----------------------------------------------------------------------------------------------------
-- fixsrv_training_prestige (Phase 4: the Kitchen queue is gone; the Training Place's jobs are the money that crosses a
-- prestige: ARCHITECTURE_V3.md "Phase 4 build contract" 3.1 / 3.7 / X11)
----------------------------------------------------------------------------------------------------
S.fixsrv_training_prestige = guarded("fixsrv_training_prestige", function()
	if not K.needBoot() then
		return
	end
	local D, Ty, Cat, Care = DS(), TS(), TC(), PCS()
	if not T.check(Ty ~= nil and Cat ~= nil and Care ~= nil and type(Care.Train) == "function", "training prestige: (precondition) TycoonService, TycoonCatalog and PetCareService (Train) load") then
		return
	end
	local PCat = requireAt("shared/PetCatalog")
	local Keys = requireAt("shared/PetKeys")
	local pet = nil
	for _, def in ipairs(PCat.Pets) do
		if def.EventOnly ~= true and def.Rarity == "Common" then
			pet = def
			break
		end
	end
	if not T.check(pet ~= nil and Keys ~= nil, "training prestige: (precondition) a Common pet and PetKeys") then
		return
	end
	local function givePet(p, key, n)
		local prof = D.GetProfile(p)
		Keys.Add(prof, key, n or 1)
		D.MarkDirty(p)
	end
	local DSt = Mock.DataStore
	local saved = { Latency = DSt.Latency }
	local players = {}
	local cost = Cat.TrainCost(pet, 1)
	local okRun, errRun = pcall(function()
		-- 1) the Sky Castle at Home Level 40+: a pet works in the garden and another trains with every Cash spent on the
		--    job; coins wait on the lawn; prestige; leave at once. The job survives (and finishes later for one rank), no
		--    refund ever lands, the coin piles are cleared, the Garden stays at L1 and keeps its pet
		local uid = newUserId()
		local p = join("TrainStar", uid)
		players[#players + 1] = p
		if not T.check(claimFree(p) ~= nil, "training prestige: (precondition) a free plot was claimed") then
			return
		end
		setStations(p, PRESTIGE_READY)
		T.check(Cat.CanPrestige(D.GetHome(p)), "training prestige: (precondition) the Sky Castle home is ready to prestige")
		givePet(p, pet.Id, 2)
		T.check(Ty.GardenSet(p, 1, pet.Id) == true, "training prestige: (setup) one copy works in Garden place 1")
		D.SpendCash(p, D.GetCash(p))
		D.AddCash(p, cost)
		local okT, job = Care.Train(p, pet.Id .. "", "Physique")
		-- (the training copy is the free one: the garden copy is cleared by the start, so put the pet back for the check)
		advance(0.3)
		T.check(okT == true and D.GetCash(p) == 0 and type(job) == "table", "training prestige: (setup) Physique training started with all the Cash", tostring(job))
		D.MutateHome(p, function(h)
			h.CollectorCash = 500 -- coins waiting on the lawn
			return true
		end)
		advance(0.3)
		homeAction(p, "Prestige")
		advance(0.5)
		local h = D.GetHome(p)
		T.check(h ~= nil and h.Prestige == 1 and D.GetCash(p) == 0, "training prestige: Prestige 1 with the job still running (Cash 0)", tostring(h and h.Prestige) .. " / " .. D.GetCash(p))
		T.check(h ~= nil and h.Stations.Garden == 1 and (h.Stations.Gym or 0) == 0 and (h.Stations.Kitchen or 0) == 0, "training prestige: the stations reset EXCEPT the Garden, kept at L1 (coins never stop)", h and stationsText(h.Stations) or "no home")
		T.check(h ~= nil and (h.CollectorCash or 0) == 0 and Ty.CoinsWaiting(p) == 0, "training prestige: the coins on the lawn are cleared", tostring(h and h.CollectorCash))
		local g = D.GetGrowth(p, pet.Id)
		T.check(type(g.Job) == "table" and g.Job.Stat == "Physique" and g.Job.Ends == job.Ends and D.TrainingKeys(p)[pet.Id] == true, "training prestige: the running training job survives the prestige (the lock too)")
		DSt.Latency = 0.2 -- real DataStore calls yield: the leave save is in flight while the leave handlers run
		leave(p)
		advance(2)
		DSt.Latency = saved.Latency
		advance(15) -- a retry of the leave save (orphan) lands too
		local rec = stored(uid) or {}
		T.check(rec.Cash == 0 and type(rec.Home) == "table" and rec.Home.Prestige == 1 and type(rec.PetGrowth) == "table" and type(rec.PetGrowth[pet.Id]) == "table" and type(rec.PetGrowth[pet.Id].Job) == "table",
			"training prestige: leaving right after the prestige refunds nothing: the stored Cash stays 0 at Prestige 1 and the job is saved",
			"stored Cash " .. tostring(rec.Cash) .. ", Prestige " .. tostring(type(rec.Home) == "table" and rec.Home.Prestige) .. ", job " .. tostring(type(rec.PetGrowth) == "table" and rec.PetGrowth[pet.Id] and rec.PetGrowth[pet.Id].Job ~= nil))
		advance(Cat.TrainSeconds(1) + 2) -- the job ends while the player is away
		local back = join("TrainStarBack", uid)
		players[#players + 1] = back
		advance(1)
		local gb = D.GetGrowth(back, pet.Id)
		T.check(gb.Physique == 1 and gb.Job == nil and D.GetCash(back) == 0, "training prestige: ...after rejoining the job completed once (rank 1), the balance is still 0 (no refund across a prestige)", "P" .. tostring(gb.Physique) .. " cash " .. D.GetCash(back))
		leave(back)

		-- 2) the prestige came from ANOTHER server's save (adopted through a rebase): the job survives that too and
		--    nothing is refunded
		local uid2 = newUserId()
		local q = join("TrainRebase", uid2)
		players[#players + 1] = q
		if T.check(claimFree(q) ~= nil, "training prestige: (precondition) a second plot was claimed") then
			setStations(q, { Gym = PRESTIGE_READY.Gym, Garden = 1 })
			givePet(q, pet.Id, 1)
			D.Save(q)
			D.SpendCash(q, D.GetCash(q))
			D.AddCash(q, cost)
			local okQ, jobQ = Care.Train(q, pet.Id, "Speed")
			advance(0.3)
			T.check(okQ == true and D.GetCash(q) == 0, "training prestige: (setup) a Speed job started at Prestige 0 with all the Cash")
			-- the other server prestiged and banked 777 since; this server adopts its save with its next write
			local recQ = stored(uid2)
			prestigeElsewhere(recQ, 777, { Gym = PRESTIGE_READY.Gym }, 0)
			D.AddTokens(q, 1) -- something to save (an empty delta never reads the store)
			D.Save(q)
			advance(0.5)
			local hq = D.GetHome(q)
			T.check(hq ~= nil and hq.Prestige == 1 and D.GetCash(q) == 777, "training prestige: (setup) this server adopted the other server's prestige (Cash 777)",
				tostring(hq and hq.Prestige) .. " / " .. D.GetCash(q))
			local gq = D.GetGrowth(q, pet.Id)
			T.check(type(gq.Job) == "table" and gq.Job.Ends == jobQ.Ends, "training prestige: the job started before the adopted prestige is still running")
			D.AddTokens(q, 1)
			DSt.Latency = 0.2
			leave(q)
			advance(2)
			DSt.Latency = saved.Latency
			advance(15)
			local rq = stored(uid2) or {}
			T.check(rq.Cash == 777 and type(rq.PetGrowth) == "table" and type(rq.PetGrowth[pet.Id]) == "table" and type(rq.PetGrowth[pet.Id].Job) == "table",
				"training prestige: a job paid before a prestige another server made is not refunded on leave either; the job is saved", "Cash " .. tostring(rq.Cash))
		end

		-- 3) control: a job of the current run stopped by the player is refunded (once), and leaving mid-job refunds nothing
		local uid3 = newUserId()
		local c = join("TrainRun", uid3)
		players[#players + 1] = c
		if T.check(claimFree(c) ~= nil, "training prestige: (precondition) a third plot was claimed") then
			setStations(c, { Gym = PRESTIGE_READY.Gym, Garden = 1 })
			givePet(c, pet.Id, 1)
			D.SpendCash(c, D.GetCash(c))
			D.AddCash(c, cost)
			care(c, "Train", pet.Id, "Defense")
			advance(0.3)
			T.eq(D.GetCash(c), 0, "training prestige: (setup) a Defense job in the current run")
			care(c, "TrainStop", pet.Id)
			advance(0.3)
			care(c, "TrainStop", pet.Id)
			advance(0.3)
			T.check(D.GetCash(c) == cost and D.GetGrowth(c, pet.Id).Job == nil, "training prestige: (control) Stop in the current run refunds the job's Cash exactly once", "cash " .. D.GetCash(c))
			care(c, "Train", pet.Id, "Defense")
			advance(0.3)
			T.eq(D.GetCash(c), 0, "training prestige: (setup) started again")
			DSt.Latency = 0.2
			leave(c)
			advance(2)
			DSt.Latency = saved.Latency
			advance(15)
			local rc = stored(uid3) or {}
			T.check(rc.Cash == 0 and type(rc.PetGrowth) == "table" and type(rc.PetGrowth[pet.Id]) == "table" and type(rc.PetGrowth[pet.Id].Job) == "table", "training prestige: (control) leaving mid-job refunds nothing: the job keeps running in the save", "Cash " .. tostring(rc.Cash))
		end
	end)
	DSt.Latency = saved.Latency
	leaveAll(players)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixsrv_training_prestige")
	K.flushWarnings("fixsrv_training_prestige", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- fixsrv_receipt_merge
----------------------------------------------------------------------------------------------------
S.fixsrv_receipt_merge = guarded("fixsrv_receipt_merge", function()
	if not K.needBoot() then
		return
	end
	local D, Gs, Config = DS(), GS(), config()
	if not T.check(Gs ~= nil and type(Config.Gems) == "table" and type(Config.Gems.Products) == "table" and Config.Gems.Products[2] ~= nil,
		"receipt merge: (precondition) GemService and two gem packs in Config.Gems.Products") then
		return
	end
	local MPS = game:GetService("MarketplaceService")
	local cb = type(MPS.ProcessReceipt) == "function" and MPS.ProcessReceipt or Gs.ProcessReceipt
	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	local DSt = Mock.DataStore
	local pack = Config.Gems.Products[2]
	local saved = { Id = pack.Id, Studio = Mock.Options.Studio, Fail = DSt.Fail, Latency = DSt.Latency }
	local players = {}
	local granted = {}
	local conn = Gs.GemsPurchased:Connect(function(player, gems, productId, purchaseId)
		granted[#granted + 1] = { Player = player, Gems = gems, PurchaseId = purchaseId }
	end)
	local function grantsOf(purchaseId)
		local n = 0
		for _, g in ipairs(granted) do
			if g.PurchaseId == purchaseId then
				n = n + 1
			end
		end
		return n
	end
	local okRun, errRun = pcall(function()
		pack.Id = 4399102 -- the owner created this pack
		Mock.Options.Studio = false -- a live server: a failed save answers NotProcessedYet
		local function receipt(player, purchaseId)
			return { PlayerId = player.UserId, ProductId = pack.Id, PurchaseId = purchaseId, CurrencySpent = 99, PlaceIdWherePurchased = 1 }
		end
		local function run(info)
			local box = spawnCall(cb, info)
			K.waitFor(function()
				return box.done
			end, 60)
			if not box.done then
				return "unfinished"
			end
			if not box.ok then
				return "error: " .. tostring(box.result)
			end
			return box.result
		end

		-- A) server A cannot save: the purchase stays in A's session (NotProcessedYet), A's player spends some of the
		--    Gems and leaves (the session is kept as an orphan and retried). The player joins server B, Roblox re-sends
		--    the receipt there, B grants and saves. Then A's retry lands.
		local uidA = newUserId()
		local a = join("GemServerA", uidA)
		players[#players + 1] = a
		D.AddTokens(a, 1)
		D.Save(a)
		local before = (stored(uidA) or {}).Gems or 0
		local spend = floor(pack.Gems / 3)
		local mark = K.logSize()
		DSt.Fail = true
		T.eq(run(receipt(a, "fixsrv-double-1")), NOT_YET, "receipt merge: (server A, store failing) the purchase answers NotProcessedYet")
		T.eq(D.GetGems(a), before + pack.Gems, "receipt merge: ...its Gems are in A's session (with the receipt)")
		T.check(toastCount(a, "Thank you", mark) == 0 and grantsOf("fixsrv-double-1") == 0,
			"receipt merge: ...no thank-you toast and no GemsPurchased while the purchase is not saved")
		T.check(D.SpendGems(a, spend), "receipt merge: (setup) A's player spends " .. spend .. " of those Gems")
		leave(a) -- the leave save fails too: the session stays behind as an orphan that keeps retrying
		advance(1)
		DSt.Fail = false
		local rec = stored(uidA)
		T.check(type(rec) == "table" and (rec.Gems or 0) == before and (type(rec.GemReceipts) ~= "table" or rec.GemReceipts["fixsrv-double-1"] == nil),
			"receipt merge: (precondition) none of A's saves reached the store")
		-- server B's grant (its UpdateAsync on the store it loaded: no receipt there yet)
		rec.Gems = (rec.Gems or 0) + pack.Gems
		rec.GemReceipts = type(rec.GemReceipts) == "table" and rec.GemReceipts or {}
		rec.GemReceipts["fixsrv-double-1"] = os.time()
		advance(25) -- A's orphan retry (10 s, then backoff) writes A's session on top
		local after = stored(uidA) or {}
		T.eq(after.Gems, before + pack.Gems - spend,
			"receipt merge: A's late save does not grant the purchase a second time (" .. pack.Gems .. " Gems once) and keeps what A's player spent")
		T.check(type(after.GemReceipts) == "table" and after.GemReceipts["fixsrv-double-1"] ~= nil, "receipt merge: ...the receipt stays stored")

		-- B) the other order: this server loaded the profile before another server's save with the same purchase
		--    landed; Roblox then re-sends the receipt here. This session's copy says "new", but its save finds the
		--    receipt in the store: the Gems are not added again (and the live balance follows the store).
		local uidB = newUserId()
		local b = join("GemServerB", uidB)
		players[#players + 1] = b
		D.AddTokens(b, 1)
		D.Save(b)
		local gB = (stored(uidB) or {}).Gems or 0
		local recB = stored(uidB)
		recB.Gems = (recB.Gems or 0) + pack.Gems
		recB.GemReceipts = type(recB.GemReceipts) == "table" and recB.GemReceipts or {}
		recB.GemReceipts["fixsrv-double-2"] = os.time()
		mark = K.logSize()
		T.eq(run(receipt(b, "fixsrv-double-2")), GRANTED, "receipt merge: (stale copy) the re-sent purchase answers PurchaseGranted...")
		T.eq((stored(uidB) or {}).Gems, gB + pack.Gems, "receipt merge: ...and the store holds its Gems once (the other server's save already granted it)")
		advance(0.5)
		T.check(D.GetGems(b) == gB + pack.Gems and b:GetAttribute(Config.Attr.Gems) == gB + pack.Gems,
			"receipt merge: ...this session's balance follows the store (no double in the HUD either)", tostring(D.GetGems(b)))

		-- C) thanks wait for the save: none while it fails, once when Roblox's retry saves it, never again
		local c = join("GemThanks", newUserId())
		players[#players + 1] = c
		mark = K.logSize()
		DSt.Fail = true
		local rC = receipt(c, "fixsrv-thanks-1")
		T.eq(run(rC), NOT_YET, "receipt thanks: (store failing) NotProcessedYet")
		T.check(toastCount(c, "Thank you", mark) == 0 and grantsOf("fixsrv-thanks-1") == 0,
			"receipt thanks: no thank-you toast and no GemsPurchased before the purchase is saved")
		DSt.Fail = false
		T.eq(run(rC), GRANTED, "receipt thanks: Roblox's retry saves it: PurchaseGranted")
		T.check(toastCount(c, "Thank you", mark) == 1 and grantsOf("fixsrv-thanks-1") == 1,
			"receipt thanks: ...now the player is thanked, once (toast + GemsPurchased)", toastCount(c, "Thank you", mark) .. " toasts, " .. grantsOf("fixsrv-thanks-1") .. " signals")
		T.eq(run(rC), GRANTED, "receipt thanks: a further retry: PurchaseGranted")
		T.check(toastCount(c, "Thank you", mark) == 1 and grantsOf("fixsrv-thanks-1") == 1 and D.GetGems(c) == pack.Gems,
			"receipt thanks: ...without a second toast, signal or grant")
		local r2 = receipt(c, "fixsrv-thanks-2")
		mark = K.logSize()
		T.eq(run(r2), GRANTED, "receipt thanks: a purchase saved at once is granted...")
		T.check(toastCount(c, "Thank you", mark) == 1 and grantsOf("fixsrv-thanks-2") == 1, "receipt thanks: ...and thanked right away, once")
	end)
	conn:Disconnect()
	pack.Id = saved.Id
	Mock.Options.Studio = saved.Studio
	DSt.Fail, DSt.Latency = saved.Fail, saved.Latency
	leaveAll(players)
	advance(12) -- an orphan left by a failed check is flushed before the next scenario
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixsrv_receipt_merge")
	K.flushWarnings("fixsrv_receipt_merge", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- fixsrv_prestige_merge
----------------------------------------------------------------------------------------------------
S.fixsrv_prestige_merge = guarded("fixsrv_prestige_merge", function()
	if not K.needBoot() then
		return
	end
	local D, Ty, Cat, Config = DS(), TS(), TC(), config()
	if not T.check(Ty ~= nil and Cat ~= nil, "prestige merge: (precondition) TycoonService and TycoonCatalog load") then
		return
	end
	local DSt = Mock.DataStore
	local saved = { Fail = DSt.Fail, Latency = DSt.Latency }
	local reward = floor(Cat.PrestigeGems(1))
	local players = {}
	local okRun, errRun = pcall(function()
		-- a) server A (this one) holds a stale prestige-0 session (its saves fail for a while): its player buys a station
		--    and banks Cash in the old run. Server B prestiged from the same save and banked 50,000 since. When A can
		--    save again, the store's newer run keeps its Cash: A's purchase and A's banked Cash belonged to the run the
		--    prestige reset (before the fix the purchase wiped B's 50,000, or old Cash survived the reset).
		local uidA = newUserId()
		local a = join("MergeStale", uidA)
		players[#players + 1] = a
		if not T.check(claimFree(a) ~= nil, "prestige merge: (precondition) a free plot was claimed") then
			return
		end
		setStations(a, PRESTIGE_READY)
		D.AddCash(a, 3000000)
		D.Save(a)
		local g0 = D.GetGems(a)
		local recA = stored(uidA)
		T.check(type(recA) == "table" and type(recA.Home) == "table" and recA.Home.Prestige == 0 and (recA.Cash or 0) >= 3000000,
			"prestige merge: (precondition) the store holds the prestige-ready build at Prestige 0")
		DSt.Fail = true
		local buyId, price = nil, 0
		for _, pad in ipairs(Cat.AvailablePads(D.GetHome(a))) do
			if not pad.Locked and not pad.Prestige and pad.StationId ~= "Prestige" and (tonumber(pad.Price) or 0) > 0 and (tonumber(pad.Price) or 0) <= D.GetCash(a) then
				buyId, price = pad.StationId, pad.Price
				break
			end
		end
		local levelBefore = buyId and (D.GetHome(a).Stations[buyId] or 0) or 0
		local okBuy = buyId ~= nil and Ty.Buy(a, buyId)
		T.check(okBuy == true, "prestige merge: (setup) the stale session buys " .. tostring(buyId) .. " for " .. tostring(price))
		D.AddCash(a, 500000) -- Collector cash banked in the old run
		prestigeElsewhere(stored(uidA), 50000, nil, 0)
		DSt.Fail = false
		D.Save(a)
		local s = stored(uidA) or {}
		local sh = type(s.Home) == "table" and s.Home or {}
		T.eq(s.Cash, 50000, "prestige merge: a stale prestige-0 session neither wipes nor adds to the Cash of the run the store prestiged into")
		T.eq(s.Gems, g0 + reward, "prestige merge: ...the star reward is stored once")
		-- the other server reset the stored build (decor kept): the stale level-up never reached it
		local want = buyId and (Cat.StationsAfterPrestige({ [buyId] = levelBefore })[buyId] or 0) or 0
		T.check(sh.Prestige == 1 and buyId ~= nil and ((type(sh.Stations) == "table" and sh.Stations[buyId]) or 0) == want,
			"prestige merge: ...and the stale purchase is void (the prestiged Home wins)", stationsText(sh.Stations))
		advance(0.5)
		T.check(D.GetCash(a) == 50000 and a:GetAttribute(Config.Attr.Cash) == 50000 and D.GetHome(a).Prestige == 1,
			"prestige merge: ...and the live session follows the store (Cash 50,000 at Prestige 1)", D.GetCash(a) .. " at " .. tostring(D.GetHome(a).Prestige))

		-- b) both servers prestiged from the same save: this one (its saves failing) banks 10,000 and rebuilds Press 1;
		--    the other one rebuilt Press 1 to Lv 3 and a Kitchen, banked 50,000 and has 200 in its Collector. Both new
		--    runs count: the Cash of both, the higher level per station, both Collectors; the star reward once.
		local uidB = newUserId()
		local b = join("MergeBoth", uidB)
		players[#players + 1] = b
		if T.check(claimFree(b) ~= nil, "prestige merge: (precondition) a second plot was claimed") then
			setStations(b, PRESTIGE_READY)
			D.Save(b)
			local g0b = D.GetGems(b)
			DSt.Fail = true
			homeAction(b, "Prestige")
			advance(0.3)
			T.check(D.GetHome(b).Prestige == 1 and D.GetCash(b) == 0 and D.GetGems(b) == g0b + reward, "prestige merge: (setup) this server prestiged (Cash 0, +" .. reward .. " Gems)")
			D.AddCash(b, 10000)
			local okP = Ty.Buy(b, "Press1")
			T.check(okP == true, "prestige merge: (setup) ...and rebuilt Press 1 since")
			local liveCash = D.GetCash(b)
			local liveHome = D.GetHome(b)
			local livePress = liveHome.Stations.Press1 or 0
			local liveCollector = floor(liveHome.CollectorCash or 0)
			prestigeElsewhere(stored(uidB), 50000, { Press1 = 3, Kitchen = 1 }, 200)
			DSt.Fail = false
			D.Save(b)
			local sb = stored(uidB) or {}
			local hb = type(sb.Home) == "table" and sb.Home or {}
			local st = type(hb.Stations) == "table" and hb.Stations or {}
			T.eq(sb.Cash, 50000 + liveCash, "prestige merge: both prestiged: the Cash of both new runs counts (50,000 there + " .. liveCash .. " here)")
			T.eq(sb.Gems, g0b + reward, "prestige merge: both prestiged: the star-1 reward is paid once")
			T.check(hb.Prestige == 1 and st.Press1 == max(3, livePress) and st.Kitchen == 1,
				"prestige merge: both prestiged: each station keeps the higher level (Press 1 Lv 3 from there; its Kitchen is not removed by this server's reset)", stationsText(st))
			T.eq(hb.Level, Cat.HomeLevelOf(hb), "prestige merge: both prestiged: the stored Home Level matches the merged stations")
			T.eq(hb.CollectorCash, 200 + liveCollector, "prestige merge: both prestiged: both Collectors count")
			advance(0.5)
			local lh = D.GetHome(b)
			T.check(D.GetCash(b) == sb.Cash and D.GetGems(b) == sb.Gems and lh.Prestige == 1 and (lh.Stations.Press1 or 0) == st.Press1,
				"prestige merge: both prestiged: the live session follows the merged store", D.GetCash(b) .. " / " .. D.GetGems(b))
		end

		-- c) this session prestiges past a stale prestige-0 write that landed first (+5,000 Cash, +7 Gems in the old run):
		--    only this run's balance is stored; the Gems still merge
		local uidC = newUserId()
		local c = join("MergePast", uidC)
		players[#players + 1] = c
		if T.check(claimFree(c) ~= nil, "prestige merge: (precondition) a third plot was claimed") then
			setStations(c, PRESTIGE_READY)
			D.AddCash(c, 12345)
			D.Save(c)
			local g0c = D.GetGems(c)
			local rc = stored(uidC)
			rc.Cash = (rc.Cash or 0) + 5000
			rc.Gems = (rc.Gems or 0) + 7
			homeAction(c, "Prestige")
			advance(0.3)
			T.check(D.GetHome(c).Prestige == 1 and D.GetCash(c) == 0, "prestige merge: (setup) the session prestiged")
			D.Save(c)
			local sc = stored(uidC) or {}
			T.eq(sc.Cash, 0, "prestige merge: a session that prestiged past a stale write stores only its new run's Cash (the stale +5,000 was reset with the old run)")
			T.eq(sc.Gems, g0c + 7 + reward, "prestige merge: ...the Gems still merge (+7 there, the reward here)")
			T.eq(type(sc.Home) == "table" and sc.Home.Prestige or nil, 1, "prestige merge: ...at Prestige 1")
			advance(0.5)
			T.check(D.GetCash(c) == 0 and D.GetGems(c) == sc.Gems, "prestige merge: ...and the live session shows the same")
		end
	end)
	DSt.Fail, DSt.Latency = saved.Fail, saved.Latency
	leaveAll(players)
	advance(12)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixsrv_prestige_merge")
	K.flushWarnings("fixsrv_prestige_merge", ALLOWED_WARNINGS)
end)

----------------------------------------------------------------------------------------------------
-- fixsrv_prestige_pad
----------------------------------------------------------------------------------------------------
S.fixsrv_prestige_pad = guarded("fixsrv_prestige_pad", function()
	if not K.needBoot() then
		return
	end
	local D, Ty, Cat = DS(), TS(), TC()
	if not T.check(Ty ~= nil and Cat ~= nil, "prestige pad: (precondition) TycoonService and TycoonCatalog load") then
		return
	end
	local players = {}
	local okRun, errRun = pcall(function()
		local uid = newUserId()
		local p = join("PadPrestige", uid)
		players[#players + 1] = p
		local index = claimFree(p)
		if not T.check(index ~= nil, "prestige pad: (precondition) a free plot was claimed") then
			return
		end
		local info = spots()[index]

		-- a Sky Castle below Home Level 40: the pad stands locked; pressing it anyway (an exploit) only explains why
		setStations(p, { House = 4, Press1 = 1, Collector = 1 })
		local locked = buyPrompt(info, "Prestige")
		if T.check(locked ~= nil, "prestige pad: (precondition) the Prestige pad stands next to the Sky Castle") then
			T.check(not locked.Enabled, "prestige pad: below Home Level 40 its prompt is disabled")
			local mark = K.logSize()
			pressPrompt(p, locked)
			T.check(#K.remotesFor("OpenPanel", uid, mark) == 0 and D.GetHome(p).Prestige == 0 and toastCount(p, "Home Level", mark) >= 1,
				"prestige pad: a locked pad triggered anyway opens nothing and says what is missing ('Reach Home Level ...')")
			advance(1.1)
		end

		-- ready: one press must not reset the home
		setStations(p, PRESTIGE_READY)
		local prompt = buyPrompt(info, "Prestige")
		if not T.check(prompt ~= nil, "prestige pad: (precondition) the Prestige pad stands on the prestige-ready plot") then
			return
		end
		T.check(prompt.ActionText == "Prestige" and prompt.HoldDuration >= 1 and prompt.KeyboardKeyCode == Enum.KeyCode.E and prompt.Enabled,
			"prestige pad: its prompt says 'Prestige' (not 'Buy') and needs a long hold (>= 1 s)", prompt.ActionText .. " / " .. tostring(prompt.HoldDuration))
		local press = buyPrompt(info, "Press3") or buyPrompt(info, "Press1")
		T.check(press == nil or (press.ActionText == "Buy" and abs(press.HoldDuration - 0.25) < 1e-6), "prestige pad: the station pads keep 'Buy' (0.25 s)")
		D.AddCash(p, 123456)
		local cash0 = D.GetCash(p)
		local stations0 = stationsText(D.GetHome(p).Stations)
		local mark = K.logSize()
		pressPrompt(p, prompt)
		local h1 = D.GetHome(p)
		T.check(h1.Prestige == 0 and D.GetCash(p) >= cash0 and stationsText(h1.Stations) == stations0,
			"prestige pad: E on the pad resets nothing (Prestige 0, the Cash and every station kept)", tostring(h1.Prestige) .. " / " .. D.GetCash(p))
		local opened = K.remotesFor("OpenPanel", uid, mark)
		local last = opened[#opened]
		T.check(#opened == 1 and last.args[1] == "Home" and type(last.args[2]) == "table" and last.args[2].Action == "Prestige",
			"prestige pad: ...it opens the Home window on its prestige confirmation (OpenPanel 'Home', {Action = 'Prestige'})", #opened .. " OpenPanel")
		T.check(toastCount(p, "Prestige 1", mark) == 0, "prestige pad: ...and no 'Prestige 1!' toast")

		-- the other routes that are not the confirmation
		advance(1.1)
		homeAction(p, "Upgrade", "Prestige")
		advance(0.4)
		local okBuy, whyBuy = Ty.Buy(p, "Prestige")
		T.check(okBuy ~= true and D.GetHome(p).Prestige == 0 and D.GetCash(p) >= cash0,
			"prestige pad: HomeAction 'Upgrade' 'Prestige' and TycoonService.Buy(player, 'Prestige') prestige nothing", tostring(whyBuy))

		-- the Home window's confirm button
		advance(1.1)
		mark = K.logSize()
		homeAction(p, "Prestige")
		advance(0.4)
		T.check(D.GetHome(p).Prestige == 1 and D.GetCash(p) == 0 and toastCount(p, "Prestige 1", mark) == 1,
			"prestige pad: the confirmation (HomeAction 'Prestige') prestiges: +1 star, Cash 0", tostring(D.GetHome(p).Prestige) .. " / " .. D.GetCash(p))
	end)
	leaveAll(players)
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("fixsrv_prestige_pad")
	K.flushWarnings("fixsrv_prestige_pad", ALLOWED_WARNINGS)
end)

return S
