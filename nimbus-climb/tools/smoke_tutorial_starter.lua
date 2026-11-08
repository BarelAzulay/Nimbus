-- smoke_tutorial_starter.lua: lobby-shop spec 16.13, the owner's answer of 2026-11-08 to 16.12's open follow-up. An account
-- PolicyService restricts from paid random items cannot spin any roulette (16.12), so the tutorial's "Your First Pet" step
-- (CompleteOn "Rolled") gives it ONE fixed starter pet (Config.Tutorial.RestrictedStarterPet) once per save and the tutorial
-- carries on. Server world, booted; loaded by tools/smoke.py:
--   tut_starter_restricted  the config (a rollable Common of the Cloud Roulette); a restricted account on the step gets
--                           exactly that pet once (no spin counted, discovered, auto-equipped as the first pet, the toast,
--                           TutorialState moves to "equip", the ask TutorialStarter in the save's Trove set); the step again
--                           (a repeat), a leave and rejoin (the save) and the step again: no second pet, the step still
--                           completes; an allowed account on the step gets nothing, whatever TutorialEvent it sends, and its
--                           real spin completes the step as before (no ask written); an account whose policy answer is still
--                           unknown waits (nothing granted, the step stays) and gets the pet once PolicyService answers
--                           "Restricted"
--   tut_starter_two_servers server A grants while the store fails (its save fails); server B (a second DataService copy that
--                           read the store before A's save) grants too and saves; A's orphan retry lands: the store holds the
--                           pet ONCE and the ask (DataService's Trove union + twin rule, the Sky Trove's own guard)
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local ASK = "TutorialStarter"
local PET = "pebble_pup"
local PET_NAME = "Pebble Pup"

local function serverScenarios()
	local S = {}
	local K = _G.K
	local PolS = game:GetService("PolicyService")
	local modes = {} -- [userId] = "allow" | "restrict"
	local userSeq = 0

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
		return K.mod("DataService")
	end
	local function TSv()
		return K.mod("TutorialService")
	end
	local function PS()
		return K.mod("PetService")
	end
	local function GS()
		return requireAt("server/Services/GemService")
	end
	local function installPolicy()
		PolS.GetPolicyInfoForPlayerAsync = function(_, player)
			return { ArePaidRandomItemsRestricted = modes[player.UserId] == "restrict", IsPaidItemTradingAllowed = true }
		end
	end
	local function removePolicy()
		PolS.GetPolicyInfoForPlayerAsync = nil
	end
	local function newUserId()
		userSeq = userSeq + 1
		return 987300 + userSeq
	end
	local function join(prefix, uid, mode)
		modes[uid] = mode
		local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
		K.advance(1.2)
		return p
	end
	local function leave(p)
		if p and p.Parent then
			Mock.RemovePlayer(p)
		end
		K.advance(0.8)
	end
	local function loaded(p)
		return K.waitFor(function()
			return DS().GetProfile(p) ~= nil and not DS().IsProvisional(p)
		end, 10)
	end
	local function stored(uid)
		return Mock.DataStore.Data[K.config().Tokens.DataStoreName .. "/u_" .. uid]
	end
	local function petCount(p, id)
		local prof = DS().GetProfile(p)
		return prof and (prof.Pets[id] or 0) or -1
	end
	local function totalPets(p)
		local prof = DS().GetProfile(p)
		local n = 0
		for _, c in pairs(prof and prof.Pets or {}) do
			n = n + c
		end
		return n
	end
	local function spins(p)
		local prof = DS().GetProfile(p)
		return prof and prof.Stats and prof.Stats.Spins or -1
	end
	local function hasAsk(p)
		local trove = DS().GetTrove(p)
		return type(trove) == "table" and trove[ASK] == true
	end
	local function stepId(p)
		local st = TSv().GetState(p)
		return st and not st.Done and st.Id or (st and st.Done and "done!") or nil
	end
	local function toasts(p, needle, mark)
		local n = 0
		for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
			if string.find(tostring(e.args[1]), needle, 1, true) then
				n = n + 1
			end
		end
		return n
	end
	local function lastStateId(p, mark)
		local e = K.lastRemote("TutorialState", p.UserId, mark)
		local st = e and e.args[1]
		return type(st) == "table" and st.Id or nil
	end
	local SPIN = nil
	-- puts p on the "Your First Pet" step (the gift already paid) and lets the poll run
	local function onSpinStep(p)
		DS().SetTutorial(p, { Step = SPIN, Done = false, Gifted = true })
		TSv().Reload(p)
		K.advance(1.2)
	end

	S.tut_starter_restricted = guarded("tut_starter_restricted", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local Steps = requireAt("shared/TutorialSteps")
		local PC = requireAt("shared/PetCatalog")
		local gs = GS()
		if not T.check(Steps and PC and gs and TSv() and type(DS().GetTrove) == "function", "starter: (setup) TutorialSteps, PetCatalog, GemService, TutorialService and DataService.GetTrove exist") then
			return
		end
		SPIN = Steps.IndexOf.spin
		T.check(SPIN ~= nil and Steps.Steps[SPIN].CompleteOn == "Rolled" and Steps.Steps[SPIN].Title == "Your First Pet", "starter: (setup) the 'spin' step is 'Your First Pet' (CompleteOn Rolled)")
		local starter = type(Config.Tutorial) == "table" and Config.Tutorial.RestrictedStarterPet or nil
		local def = type(starter) == "string" and PC.Get(starter) or nil
		local inCloud = false
		for _, d in ipairs(type(PC.RarityPool) == "function" and PC.RarityPool("Cloud", "Common") or {}) do
			if d.Id == starter then
				inCloud = true
			end
		end
		T.check(starter == PET and def ~= nil and def.Rarity == "Common" and inCloud, "starter: Config.Tutorial.RestrictedStarterPet = '" .. PET .. "', a Common the Cloud Roulette (the step's machine) rolls",
			tostring(starter) .. " / " .. tostring(def and def.Rarity) .. " / in Cloud's Common pool " .. tostring(inCloud))

		local players = {}
		installPolicy()
		local okRun, errRun = pcall(function()
			-- 1. a restricted account on the step: the starter, once
			local ruid = newUserId()
			local r = join("StarterR", ruid, "restrict")
			players[#players + 1] = r
			T.check(loaded(r) and gs.PolicyState(r) == "Restricted", "starter: (setup) the restricted account is loaded and PolicyState says Restricted", tostring(gs.PolicyState(r)))
			local pets0, spins0 = totalPets(r), spins(r)
			local mark = K.logSize()
			onSpinStep(r)
			T.check(petCount(r, PET) == 1 and totalPets(r) == pets0 + 1, "starter: a restricted account on 'Your First Pet' gets exactly one " .. PET_NAME,
				petCount(r, PET) .. " of it, " .. pets0 .. " -> " .. totalPets(r) .. " pets")
			T.eq(spins(r), spins0, "starter: ...no roulette spin is counted (nothing was rolled)")
			T.check(stepId(r) == "equip" and lastStateId(r, mark) == "equip", "starter: ...and the tutorial carries on: the next step ('equip') is sent", tostring(stepId(r)) .. " / " .. tostring(lastStateId(r, mark)))
			T.check(hasAsk(r), "starter: ...the save records the one grant (Trove ask '" .. ASK .. "')")
			T.check(DS().IsDiscovered(r, PET) and PS().GetEquipped(r)[1] == PET, "starter: ...discovered and, as the first pet, in the team (it follows)", table.concat(PS().GetEquipped(r), ","))
			T.eq(toasts(r, PET_NAME, mark), 1, "starter: ...one toast names the pet")

			-- 2. the step again (a repeat): no second pet, the step still completes
			mark = K.logSize()
			onSpinStep(r)
			K.advance(1.5)
			T.check(petCount(r, PET) == 1 and stepId(r) == "equip" and toasts(r, PET_NAME, mark) == 0, "starter: the step again: no second pet, no toast, the step completes at once",
				petCount(r, PET) .. " / " .. tostring(stepId(r)))

			-- 3. a leave and a rejoin (the save carries the ask), then the step again
			leave(r)
			local r2 = join("StarterR", ruid, "restrict")
			players[#players + 1] = r2
			T.check(loaded(r2) and petCount(r2, PET) == 1 and hasAsk(r2), "starter: after a rejoin the save holds the pet once and the ask", tostring(petCount(r2, PET)))
			mark = K.logSize()
			onSpinStep(r2)
			K.advance(1.5)
			T.check(petCount(r2, PET) == 1 and stepId(r2) == "equip" and toasts(r2, PET_NAME, mark) == 0, "starter: ...the step after the rejoin grants nothing and completes",
				petCount(r2, PET) .. " / " .. tostring(stepId(r2)))

			-- 4. an allowed account: unchanged (nothing granted, whatever the client sends; its real spin completes the step)
			local a = join("StarterA", newUserId(), "allow")
			players[#players + 1] = a
			T.check(loaded(a) and gs.PolicyState(a) == "Allowed", "starter: (setup) the allowed account says Allowed", tostring(gs.PolicyState(a)))
			onSpinStep(a)
			K.advance(2)
			T.check(totalPets(a) == 0 and stepId(a) == "spin" and not hasAsk(a), "starter: an allowed account on the step gets no pet and the step waits for its spin",
				totalPets(a) .. " pets / " .. tostring(stepId(a)))
			local folder = K.remoteFolder()
			for _, ev in ipairs({ "Rolled", "Starter", ASK, "Next", "ShopOpened", "IndexOpened", "PetsOpened", "Sync" }) do
				Mock.FromClient(folder:FindFirstChild("TutorialEvent"), a, ev)
				K.advance(0.4)
			end
			Mock.FromClient(folder:FindFirstChild("TutorialEvent"), a, { ASK })
			K.advance(0.4)
			T.check(totalPets(a) == 0 and stepId(a) == "spin" and not hasAsk(a), "starter: ...no TutorialEvent the client sends grants it or passes the step",
				totalPets(a) .. " pets / " .. tostring(stepId(a)))
			local cloud = nil
			for _, rr in ipairs(Config.Roulettes) do
				if rr.Id == "Cloud" then
					cloud = rr
				end
			end
			DS().AddTokens(a, cloud.Price)
			local okSpin = PS().BuyRoulette(a, "Cloud")
			K.advance(1)
			T.check(okSpin == true and totalPets(a) == 1 and stepId(a) == "equip" and not hasAsk(a), "starter: ...its real Cloud spin completes the step as before (no starter ask written)",
				tostring(okSpin) .. " / " .. totalPets(a) .. " pets / " .. tostring(stepId(a)))

			-- 5. the policy answer still unknown: the step waits, nothing granted; then the answer "Restricted" arrives
			PolS.GetPolicyInfoForPlayerAsync = false -- (the mock: no PolicyService API, no answer comes)
			local u = join("StarterU", newUserId(), "restrict")
			players[#players + 1] = u
			T.check(loaded(u) and gs.PolicyState(u) == "Checking", "starter: (setup) an account whose policy answer is unknown (Checking)", tostring(gs.PolicyState(u)))
			onSpinStep(u)
			K.advance(3)
			T.check(totalPets(u) == 0 and stepId(u) == "spin" and not hasAsk(u), "starter: while the policy is unknown the step waits and grants nothing",
				totalPets(u) .. " pets / " .. tostring(stepId(u)))
			installPolicy()
			K.advance(6) -- past GemService's gap between two on-demand lookups
			gs.TokenSpinLock(u) -- a refused spin asks PolicyService again (16.12)
			K.advance(1.5)
			T.check(gs.PolicyState(u) == "Restricted" and petCount(u, PET) == 1 and totalPets(u) == 1 and stepId(u) == "equip" and hasAsk(u),
				"starter: ...once PolicyService answers 'Restricted' the starter comes (once) and the tutorial carries on",
				tostring(gs.PolicyState(u)) .. " / " .. petCount(u, PET) .. " / " .. tostring(stepId(u)))
			K.flushErrors("tut_starter_restricted")
		end)
		removePolicy()
		for _, p in ipairs(players) do
			leave(p)
		end
		if not okRun then
			error(errRun, 0)
		end
	end)

	-- a second, independent copy of DataService ("server B": its own cache, the same mock DataStore; the smoke_trove.lua
	-- shape); release() destroys the clone and drops the PlayerRemoving / remote hooks
	local function secondServer(name)
		local inst = K.moduleInstance("server/Services/DataService")
		if not inst then
			return nil
		end
		local sigs = { game:GetService("Players").PlayerRemoving }
		for _, rn in ipairs({ "RequestProfile", "SettingsSet" }) do
			local rem = K.remoteFolder():FindFirstChild(rn)
			if rem then
				sigs[#sigs + 1] = rem.OnServerEvent
			end
		end
		local marks = {}
		for i, sig in ipairs(sigs) do
			local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
			marks[i] = { conns = conns, n = conns and #conns or 0 }
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
						local c = m.conns[i]
						if type(c) == "table" and c.Disconnect then
							c:Disconnect()
						end
					end
				end
			end
		end
		return module, clone, release
	end

	S.tut_starter_two_servers = guarded("tut_starter_two_servers", function()
		if not K.needBoot() then
			return
		end
		local Steps = requireAt("shared/TutorialSteps")
		SPIN = Steps and Steps.IndexOf.spin
		if not T.check(SPIN ~= nil, "starter two servers: (setup) the spin step") then
			return
		end
		local savedFail = Mock.DataStore.Fail
		installPolicy()
		local okRun, errRun = pcall(function()
			local uid = newUserId()
			local p = join("StarterTwo", uid, "restrict")
			T.check(loaded(p), "starter two servers: (precondition) the profile loads")
			DS().Save(p)
			-- the store fails from here on (no autosave may carry A's grant before B reads the store)
			Mock.DataStore.Fail = true
			onSpinStep(p)
			T.check(petCount(p, PET) == 1 and hasAsk(p), "starter two servers: server A granted the starter (in its cache)", tostring(petCount(p, PET)))
			DS().AddCash(p, 7) -- A's marker: proves A's orphan retry landed
			local liveCash = DS().GetCash(p)
			T.eq(DS().Save(p), false, "starter two servers: server A's save fails")
			leave(p)
			Mock.DataStore.Fail = savedFail
			local B, cloneB, releaseB = secondServer("DataServiceStarterB")
			if T.check(B ~= nil and type(B.MarkTrove) == "function", "starter two servers: a second copy of DataService loads as server B (with MarkTrove)", tostring(cloneB)) then
				local okB, errB = pcall(function()
					B.Load(p)
					local trove = B.GetTrove(p)
					T.check(type(trove) == "table" and trove[ASK] == nil, "starter two servers: server B read the store before A's save (no ask there)")
					T.check(B.MarkTrove(p, ASK, { Pets = { [PET] = 1 } }) == true, "starter two servers: server B marks the ask with its grant")
					local prof = B.GetProfile(p)
					prof.Pets[PET] = (prof.Pets[PET] or 0) + 1
					B.MarkDirty(p)
					T.eq(B.Save(p), true, "starter two servers: server B saves its grant")
				end)
				T.check(okB, "starter two servers: server B ran", tostring(errB))
				releaseB()
				local landed = K.waitFor(function()
					local rec = stored(uid)
					return rec ~= nil and rec.Cash == liveCash
				end, 40)
				local rec = stored(uid) or {}
				local pets = type(rec.Pets) == "table" and rec.Pets[PET] or nil
				T.check(landed and pets == 1 and type(rec.Trove) == "table" and rec.Trove[ASK] == true,
					"starter two servers: A's orphan retry lands: the store holds ONE " .. PET_NAME .. " and the ask",
					string.format("landed %s, stored pets %s, cash %s / %s", tostring(landed), tostring(pets), tostring(rec.Cash), tostring(liveCash)))
			end
			K.flushErrors("tut_starter_two_servers")
		end)
		Mock.DataStore.Fail = savedFail
		removePolicy()
		if not okRun then
			error(errRun, 0)
		end
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return {}
