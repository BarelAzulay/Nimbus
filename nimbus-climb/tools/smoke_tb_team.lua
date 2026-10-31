-- smoke_tb_team.lua: one team (team-balance plan, Task 3; spec 2026-10-31 s.1, s.2): Equipped == the active preset minus busy
-- pets, in order, after every write. Server world, booted (listed in server_files of tools/smoke.py):
--   tb_team_invariant  SetTeam / SelectTeam / Equip / Unequip keep Equipped, the EquippedPets attribute and the preset together;
--                      an empty team has no followers; a team pet that cannot be swapped mid-match; a merge with another
--                      server's preset: Equipped follows the merged active preset
--   tb_team_busy       a training or gardening pet KEEPS its slot and leaves the followers at once; the next free pet is the
--                      fighter (Review Focus 2); it is back by itself when the job ends; all busy = refused with the reason;
--                      a direct pick of a busy pet is refused, a team edit around a busy pet is not; a slot survives a rejoin
--   tb_team_refusal    an empty team is refused everywhere with the Empty text; no "else strongest" fallback in the Ring
--   tb_team_migrate    Migrations.B4TeamFollow: the Empty / Same / Free / Replaced cases (Review Focus 1), nothing lost, once
--                      only, after a provisional load's recovery; a pet training from Follow keeps a free slot; a stand-in
--                      profile's team edits say the save is being recovered
--   tb_team_rollout    a profile the frozen Phase 4 server wrote loads with the invariant and no lost key
--   client_tb_team_state  (client world) State.Busy / State.ActiveTeam / State.Teams().Busy from a ProfileSync; junk is dropped
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local CONTEXT = (ARGS and ARGS.context) or "server"
if CONTEXT ~= "server" then
	local T = SmokeCommon.T
	local KC = _G.KC
	local S = {}
	S.client_tb_team_state = SmokeCommon.guarded("client_tb_team_state", function()
		local inst = Mock.GetPath(ROOTS["client"] .. "/State")
		local State = inst and require(inst)
		local function teams(busy)
			return { Presets = { { "mallow_kitten", "pebble_pup", "puddle_frog" }, {}, {} }, Active = 1, Slots = 3, Busy = busy }
		end
		KC.toClient("ProfileSync", {
			Tokens = 0, Pets = { mallow_kitten = 1, pebble_pup = 1, puddle_frog = 1 }, Equipped = { "pebble_pup" }, Items = {},
			Teams = teams({ mallow_kitten = "Training", puddle_frog = "Garden", junk_pet = "Lunch", [5] = "Garden" }),
		})
		KC.advance(0.1)
		T.check(type(State.Busy) == "function" and type(State.ActiveTeam) == "function", "tb team state: State.Busy / State.ActiveTeam exist")
		T.check(State.Busy("mallow_kitten") == "Training" and State.Busy("puddle_frog") == "Garden" and State.Busy("pebble_pup") == nil and State.Busy("junk_pet") == nil,
			"tb team state: State.Busy answers from Teams.Busy (junk values dropped)")
		T.check(State.Teams().Busy.mallow_kitten == "Training" and State.Teams().Busy[5] == nil, "tb team state: State.Teams().Busy is cleaned like Presets")
		local active = State.ActiveTeam()
		T.check(#active == 1 and active[1] == "pebble_pup" and State.EquippedList()[1] == "pebble_pup", "tb team state: State.ActiveTeam = the snapshot's Equipped (EquippedList stays an alias)")
		KC.toClient("ProfileSync", { Tokens = 0, Pets = {}, Equipped = {}, Items = {} })
		KC.advance(0.1)
		T.check(State.Busy("mallow_kitten") == nil and next(State.Teams().Busy) == nil and #State.ActiveTeam() == 0, "tb team state: a snapshot without Busy clears it")
	end)
	return S
end

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance, config = K.advance, K.config

local S = {}

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

local function DS()
	return req("server/Services/DataService")
end
local function PS()
	return req("server/Services/PetService")
end
local function BS()
	return req("server/Services/BattleService")
end
local function TS()
	return req("server/Services/TycoonService")
end
local function CS()
	return req("server/Services/PetCareService")
end

local K1, K2, K3, K4, K5 = "mallow_kitten", "puddle_frog", "pebble_pup", "biscuit_bear", "honey_bunny"

local function listText(list)
	local out = {}
	for i, v in ipairs(list or {}) do
		out[i] = tostring(v)
	end
	return "{" .. table.concat(out, ",") .. "}"
end

local function eq(a, b)
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

-- the invariant: Equipped == ActiveTeamKeys, in order
local function inv(p)
	local prof = DS().GetProfile(p)
	return prof ~= nil and eq(prof.Equipped, (DS().ActiveTeamKeys(p)))
end

local function give(p, keys)
	local prof = DS().GetProfile(p)
	for _, key in ipairs(keys) do
		prof.Pets[key] = (prof.Pets[key] or 0) + 1
	end
	DS().MarkDirty(p)
	return prof
end

local function statsOf()
	return { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} }
end

local function storeKey(userId)
	return config().Tokens.DataStoreName .. "/u_" .. userId
end

local function stored(userId)
	return Mock.DataStore.Data[storeKey(userId)]
end

local function join(name, userId)
	local p = Mock.AddPlayer(name, userId)
	advance(1.0)
	return p
end

local function leave(p)
	K.removePlayers({ p })
	advance(3)
end

-- a home with a Garden and a Training Place on the first free plot, plenty of Cash
local function readyHome(p)
	local SS = req("server/Services/SpotService")
	local Ty, Cat, Data = TS(), req("shared/TycoonCatalog"), DS()
	local spots = (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
	for i = 1, config().Lobby.SpotCount do
		if spots[i] and not SS.GetOwner(i) then
			if Ty.Claim(p, i) then
				advance(0.6)
				Data.MutateHome(p, function(h)
					h.Stations.Garden = 1
					h.Stations.Gym = 2
					h.Level = Cat.HomeLevelOf(h)
				end)
				advance(2.1)
				Data.AddCash(p, 50000000)
				return i
			end
		end
	end
	return nil
end

local function startTraining(p, key)
	local ok, job = CS().Train(p, key, "Physique")
	if not T.check(ok == true, "tb team: (setup) training starts for " .. key, tostring(job)) then
		return nil
	end
	advance(0.3)
	return job
end

-- the 1 s tick completes a due job: move its end to now
local function finishTraining(p, key)
	DS().MutateGrowth(p, function(g)
		g[key].Job.Ends = os.time()
	end)
	advance(1.5)
end

-- puts every copy of the key in free Garden places
local function gardenAll(p, key)
	local prof = DS().GetProfile(p)
	local n = prof.Pets[key] or 0
	local slot = 1
	while n > 0 and slot <= 3 do
		if (TS().GetHome(p).Garden or {})[slot] == nil then
			local ok, why = TS().GardenSet(p, slot, key)
			T.check(ok == true, "tb team: (setup) " .. key .. " goes to Garden place " .. slot, tostring(why))
			n = n - 1
		end
		slot = slot + 1
	end
	advance(0.3)
end

local function ringPortalPos()
	local info = req("server/Services/ArenaBuilder").GetInfo()
	local portal = info and info.RingPortal
	if type(portal) == "table" and typeof(portal.Position) == "Vector3" then
		return portal.Position
	end
	local model = workspace:FindFirstChild("Portal_Ring", true)
	return model and model:GetPivot().Position or nil
end

local function toRing(p)
	Mock.Teleport(p, CFrame.new(ringPortalPos() + Vector3.new(0, 3, 6)))
	advance(0.05)
end

-- EventService's scheduler must not open a raid in the middle of a scenario
local function holdRaids()
	local bs = BS()
	local real = bs.StartRaid
	bs.StartRaid = function()
		return false, "A raid is already running"
	end
	return function()
		bs.StartRaid = real
	end
end

----------------------------------------------------------------------------------------------------
-- tb_team_invariant
----------------------------------------------------------------------------------------------------
S.tb_team_invariant = guarded("tb_team_invariant", function()
	if not K.needBoot() then
		return
	end
	local Data, Pets = DS(), PS()
	local a = K.freshPlayers(1, "TbInv")[1]
	advance(0.5)
	local prof = give(a, { K1, K2, K3, K4, K5 })
	local ok, why = Data.SetTeam(a, 1, { K1, K2, K3 })
	T.check(ok == true and inv(a) and eq(prof.Equipped, { K1, K2, K3 }), "tb team: SetTeam on the active preset = the followers", listText(prof.Equipped) .. " / " .. tostring(why))
	Data.SetTeam(a, 2, { K4 })
	T.check(eq(prof.Equipped, { K1, K2, K3 }), "tb team: editing another preset changes no follower", listText(prof.Equipped))
	Data.SelectTeam(a, 2)
	T.check(eq(prof.Equipped, { K4 }) and a:GetAttribute("EquippedPets") == K4, "tb team: selecting B swaps all followers at once (attribute too)", tostring(a:GetAttribute("EquippedPets")))
	Data.SetTeam(a, 3, {})
	Data.SelectTeam(a, 3)
	T.check(#prof.Equipped == 0 and a:GetAttribute("EquippedPets") == "" and inv(a), "tb team: an empty active team = no followers")
	Data.SelectTeam(a, 1)
	local okE, whyE = Pets.Equip(a, K4)
	T.check(okE == false and whyE == "Your team is full (3 pets)", "tb team: Equip refuses a full team with the team wording", tostring(whyE))
	local okD, whyD = Pets.Equip(a, K1)
	T.check(okD == false and (whyD == "That pet is already in your team" or whyD == "Your team is full (3 pets)"), "tb team: Equip refuses a pet of the full team", tostring(whyD))
	T.check(Pets.Unequip(a, K2) == true and eq(prof.Teams.Presets[1], { K1, K3 }) and eq(prof.Equipped, { K1, K3 }), "tb team: Unequip removes the key from the active preset", listText(prof.Teams.Presets[1]))
	local okS, whyS = Pets.Equip(a, K1)
	T.check(okS == false and whyS == "That pet is already in your team" and eq(prof.Teams.Presets[1], { K1, K3 }), "tb team: Equip refuses a pet already in the team, nothing changes", tostring(whyS))
	T.check(Pets.Equip(a, K4) == true and eq(prof.Teams.Presets[1], { K1, K3, K4 }) and eq(prof.Equipped, { K1, K3, K4 }), "tb team: Equip fills the first empty slot of the active preset", listText(prof.Teams.Presets[1]))
	T.check(a:GetAttribute("EquippedPets") == K1 .. "," .. K3 .. "," .. K4, "tb team: ...the attribute follows", tostring(a:GetAttribute("EquippedPets")))
	local okN, whyN = Pets.Unequip(a, K2)
	T.check(okN == false and whyN == "That pet is not in your team", "tb team: Unequip of a pet outside the team says so", tostring(whyN))

	-- the team is locked during an obby match (perks must not be hot-swapped between checkpoints); other presets are not
	a:SetAttribute(config().Attr.InMatch, true)
	local okM, whyM = Data.SelectTeam(a, 2)
	T.check(okM == false and whyM == "Pets are locked during a match" and prof.Teams.Active == 1, "tb team: mid-match SelectTeam is refused", tostring(whyM))
	okM, whyM = Data.SetTeam(a, 1, { K1 })
	T.check(okM == false and whyM == "Pets are locked during a match" and eq(prof.Equipped, { K1, K3, K4 }), "tb team: mid-match SetTeam on the active preset is refused", tostring(whyM))
	T.check(Data.SetTeam(a, 3, { K5 }) == true, "tb team: ...another preset may still be edited")
	a:SetAttribute(config().Attr.InMatch, false)

	-- a pet lost for good leaves the preset and the followers at the next sync; the one behind it moves up
	prof.Pets[K3] = nil
	Data.MarkDirty(a)
	Pets.Refresh(a)
	T.check(eq(prof.Equipped, { K1, K4 }) and inv(a) and a:GetAttribute("EquippedPets") == K1 .. "," .. K4, "tb team: a pet no longer owned leaves the followers (Refresh)", listText(prof.Equipped))
	Data.Sync(a)
	T.check(eq(prof.Teams.Presets[1], { K1, K4 }), "tb team: ...and the preset", listText(prof.Teams.Presets[1]))
	K.removePlayers({ a })
	advance(1)

	-- two servers: this session selects B, the other server rewrote B: Equipped follows the merged active preset
	local UID = 966101
	Mock.DataStore.Data[storeKey(UID)] = {
		Version = 2, Tokens = 5, Pets = { [K1] = 1, [K2] = 1, [K3] = 1, [K4] = 1 }, Equipped = { K1 }, Items = {}, Stats = statsOf(),
		Teams = { Presets = { { K1 }, { K2 }, {} }, Active = 1 },
	}
	local m = join("TbInvMerge", UID)
	Data.SelectTeam(m, 2)
	T.check(eq(Data.GetProfile(m).Equipped, { K2 }), "tb team merge: (setup) B is active, K2 follows", listText(Data.GetProfile(m).Equipped))
	local other = stored(UID)
	if T.check(type(other) == "table" or Data.Save(m), "tb team merge: (setup) the store holds the save") then
		Data.Save(m)
		other = stored(UID)
		other.Teams.Presets[2] = { K3, K4 }
		other.UpdatedAt = (other.UpdatedAt or 0) + 1
		Data.AddTokens(m, 1)
		T.eq(Data.Save(m), true, "tb team merge: the session saves and adopts the store")
		advance(0.3)
		local mp = Data.GetProfile(m)
		T.check(eq(mp.Teams.Presets[2], { K3, K4 }) and mp.Teams.Active == 2 and eq(mp.Equipped, { K3, K4 }) and inv(m), "tb team merge: Equipped follows the merged active preset", listText(mp.Equipped))
		T.check(m:GetAttribute("EquippedPets") == K3 .. "," .. K4, "tb team merge: ...the attribute too", tostring(m:GetAttribute("EquippedPets")))
	end
	K.removePlayers({ m })
	advance(1)
	K.flushErrors("tb_team_invariant")
	K.flushWarnings("tb_team_invariant", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- tb_team_busy
----------------------------------------------------------------------------------------------------
S.tb_team_busy = guarded("tb_team_busy", function()
	if not K.needBoot() then
		return
	end
	local Data, Pets, Battle, Ty = DS(), PS(), BS(), TS()
	local release = holdRaids()
	local UID = 966201
	local a = join("TbBusy", UID)
	local prof = give(a, { K1, K2, K3, K4, K5 })
	if not T.check(readyHome(a) ~= nil, "tb team: (setup) a home with a Training Place") then
		release()
		return
	end
	T.check(Data.SetTeam(a, 1, { K1, K3, K4 }) == true and eq(prof.Equipped, { K1, K3, K4 }), "tb team: (setup) a full team", listText(prof.Equipped))

	-- Review Focus 2: the slot-1 pet starts training in the lobby
	startTraining(a, K1)
	T.check(eq(prof.Teams.Presets[1], { K1, K3, K4 }) and eq(prof.Equipped, { K3, K4 }) and Data.BusyKeys(a)[K1] == "Training", "tb team: a training pet keeps its slot and leaves the followers (Review Focus 2)", listText(prof.Equipped))
	T.check(a:GetAttribute("EquippedPets") == K3 .. "," .. K4, "tb team: ...the attribute follows at once (no 2nd pet walks off)", tostring(a:GetAttribute("EquippedPets")))
	local keys, why = Data.ActiveTeamKeys(a)
	T.check(keys[1] == K3 and why == nil and inv(a), "tb team: the next free pet is the fighter", listText(keys) .. " / " .. tostring(why))
	T.check(Data.GetTeams(a).Busy[K1] == "Training", "tb team: GetTeams carries Busy")
	local mark = K.logSize()
	Data.Sync(a)
	local syncs = K.remotesFor("ProfileSync", a.UserId, mark)
	local snap = syncs[#syncs] and syncs[#syncs].args[1]
	T.check(snap and snap.Teams and snap.Teams.Busy and snap.Teams.Busy[K1] == "Training" and eq(snap.Equipped, { K3, K4 }), "tb team: the ProfileSync Teams table carries Busy")
	toRing(a)
	local okR, idR = Battle.StartRing(a)
	T.check(okR == true and Battle.KeysInBattle(a)[K3] == true and not Battle.KeysInBattle(a)[K1], "tb team: the Ring fields slot 2 as the fighter while slot 1 trains", tostring(idR))
	Battle.Forfeit(a)
	advance(4.8)

	-- an edit around the busy pet stays possible: replacing another slot, emptying another slot, swapping positions
	local okH, whyH = Data.SetTeam(a, 1, { K1, K3, K5 })
	T.check(okH == true and eq(prof.Teams.Presets[1], { K1, K3, K5 }) and eq(prof.Equipped, { K3, K5 }), "tb team: a slot replaced next to a busy pet is accepted", tostring(whyH))
	okH, whyH = Data.SetTeam(a, 1, { K3, K1, K5 })
	T.check(okH == true and eq(prof.Teams.Presets[1], { K3, K1, K5 }) and eq(prof.Equipped, { K3, K5 }), "tb team: swapping positions with a busy pet is accepted", tostring(whyH))
	okH, whyH = Data.SetTeam(a, 1, { K1, K3, K5 })
	T.check(okH == true and eq(prof.Teams.Presets[1], { K1, K3, K5 }), "tb team: ...and back", tostring(whyH))
	okH, whyH = Data.SetTeam(a, 1, { false, K3, K5 })
	T.check(okH == true and eq(prof.Teams.Presets[1], { K3, K5 }) and eq(prof.Equipped, { K3, K5 }), "tb team: the busy pet itself may be removed", tostring(whyH))
	okH, whyH = Data.SetTeam(a, 1, { K1, K3, K5 })
	T.check(okH == false and tostring(whyH):find(" is training (", 1, true) ~= nil, "tb team: ...then it cannot be picked back while it trains", tostring(whyH))
	-- (the job goes on; the team around it comes back through a preset edit while the pet is free)
	finishTraining(a, K1)
	okH, whyH = Data.SetTeam(a, 1, { K1, K3, K4 })
	T.check(okH == true and eq(prof.Teams.Presets[1], { K1, K3, K4 }) and eq(prof.Equipped, { K1, K3, K4 }), "tb team: (setup) the team back once it is free", tostring(whyH))
	startTraining(a, K1)
	local okB, whyB = Data.SetTeam(a, 2, { K1 })
	T.check(okB == false and type(whyB) == "string" and whyB:find(" is training (", 1, true) ~= nil and whyB:find("left)", 1, true) ~= nil, "tb team: a DIRECT pick of a training pet is refused with the time left", tostring(whyB))
	local _, whyCan = Pets.CanEquip(a, K1, 0)
	T.check(whyCan == whyB, "tb team: ...Equip says the same", tostring(whyCan))

	finishTraining(a, K1)
	T.check(eq(prof.Equipped, { K1, K3, K4 }) and inv(a), "tb team: the job ends: the pet is back by itself (no Job.From Follow)", listText(prof.Equipped))
	T.check(a:GetAttribute("EquippedPets") == K1 .. "," .. K3 .. "," .. K4, "tb team: ...the attribute too", tostring(a:GetAttribute("EquippedPets")))

	gardenAll(a, K3)
	T.check(Data.BusyKeys(a)[K3] == "Garden" and eq(prof.Equipped, { K1, K4 }) and eq(prof.Teams.Presets[1], { K1, K3, K4 }) and inv(a), "tb team: every copy in the Garden = busy, slot kept", listText(prof.Equipped) .. " / " .. listText(prof.Teams.Presets[1]))
	T.check(a:GetAttribute("EquippedPets") == K1 .. "," .. K4, "tb team: ...it left the followers at once", tostring(a:GetAttribute("EquippedPets")))
	-- mid-match the followers cannot change: a team pet cannot leave the Garden (it would follow at once), nor be recalled
	a:SetAttribute(config().Attr.InMatch, true)
	local okMa, whyMa = Ty.GardenSet(a, 1, nil)
	T.check(okMa == false and whyMa == "Finish your match first" and (Data.GetHome(a).Garden or {})[1] == K3 and eq(prof.Equipped, { K1, K4 }), "tb team: mid-match a team pet stays in the Garden", tostring(whyMa))
	local okCh, whyCh = Data.CheckTeam(a, 1, { K1, K3, K4 }, K3)
	T.check(okCh == false and whyCh == "Pets are locked during a match", "tb team: ...CheckTeam (the recall's check) says so too", tostring(whyCh))
	a:SetAttribute(config().Attr.InMatch, false)
	-- a pet in a team that works in the Garden survives a save + rejoin in both places (the old-save repair is for unmigrated saves)
	K.removePlayers({ a })
	advance(3)
	a = join("TbBusy", UID)
	prof = Data.GetProfile(a)
	local home = Ty.GetHome(a) or {}
	T.check((Data.GetHome(a).Garden or {})[1] == K3 and eq(prof.Teams.Presets[1], { K1, K3, K4 }) and eq(prof.Equipped, { K1, K4 }) and Data.BusyKeys(a)[K3] == "Garden",
		"tb team: a rejoin keeps the pet in its Garden place AND in its slot", listText(prof.Teams.Presets[1]) .. " / " .. listText(prof.Equipped) .. " / " .. tostring(home))
	if not T.check(readyHome(a) ~= nil, "tb team: (setup) the home claimed again") then
		release()
		return
	end
	-- the garden place given up: the pet is back in the followers by itself
	local okG, whyG = Ty.GardenSet(a, 1, nil)
	advance(0.3)
	T.check(okG == true and eq(prof.Equipped, { K1, K3, K4 }) and a:GetAttribute("EquippedPets") == K1 .. "," .. K3 .. "," .. K4, "tb team: taken out of the Garden the pet follows again by itself", tostring(whyG) .. " / " .. listText(prof.Equipped))
	gardenAll(a, K3)

	-- the recall: a gardening pet that already has its slot: the recall frees it and it stays in that slot
	local okRec, whyRec = Ty.GardenRecall(a, K3, { To = "Equip" })
	advance(0.3)
	T.check(okRec == true and eq(prof.Equipped, { K1, K3, K4 }) and eq(prof.Teams.Presets[1], { K1, K3, K4 }) and (Ty.GetHome(a).Garden or {})[1] == nil, "tb team: a recall of a slotted gardening pet brings it back to its slot", tostring(whyRec))
	gardenAll(a, K3)

	startTraining(a, K1)
	gardenAll(a, K4)
	local k2, why2 = Data.ActiveTeamKeys(a)
	T.check(#k2 == 0 and why2 == "Busy" and #prof.Equipped == 0 and a:GetAttribute("EquippedPets") == "", "tb team: all busy = Busy", listText(k2) .. " / " .. tostring(why2))
	local _, whySpec = Battle.TeamSpec(a)
	local _, whyRing = Battle.StartRing(a)
	T.check(whySpec == Battle.TEAM_REFUSALS.Busy and whyRing == Battle.TEAM_REFUSALS.Busy, "tb team: a battle is refused and says why", tostring(whySpec) .. " / " .. tostring(whyRing))
	local _, whyPick = Data.SetTeam(a, 1, { K3 })
	T.check(whyPick == "That pet is gardening! Take it out of the garden first", "tb team: a DIRECT pick of a gardening pet still asks for the recall", tostring(whyPick))
	T.check(Data.BusyKeys(nil) ~= nil and next(Data.BusyKeys(nil)) == nil, "tb team: BusyKeys(nil) = {}")
	K.removePlayers({ a })
	advance(1)
	release()
	K.flushErrors("tb_team_busy")
	K.flushWarnings("tb_team_busy", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- tb_team_refusal
----------------------------------------------------------------------------------------------------
S.tb_team_refusal = guarded("tb_team_refusal", function()
	if not K.needBoot() then
		return
	end
	local Data, Battle = DS(), BS()
	local DGS = req("server/Services/DungeonService")
	local release = holdRaids()
	local b = K.freshPlayers(1, "TbRefuse")[1]
	advance(0.5)
	local prof = give(b, { K1, K2, K3 })
	Data.SetTeam(b, 1, {})
	if not T.check(readyHome(b) ~= nil, "tb team: (setup) a home") then
		release()
		return
	end
	T.check(type(Battle.TEAM_REFUSALS) == "table" and Battle.TEAM_REFUSALS.Empty == "Your team is empty: open Pets and put a pet in it" and Battle.TEAM_REFUSALS.Busy == "Your whole team is busy: training or gardening", "tb team: BattleService.TEAM_REFUSALS holds the two texts")
	local _, why = Data.ActiveTeamKeys(b)
	local _, whySpec = Battle.TeamSpec(b)
	local _, whySolo = DGS.StartSolo(b, 1)
	T.check(why == "Empty" and whySpec == Battle.TEAM_REFUSALS.Empty and whySolo == Battle.TEAM_REFUSALS.Empty, "tb team: an empty team is refused everywhere with the Empty text", tostring(why) .. " / " .. tostring(whySolo))
	toRing(b)
	-- b owns 3 pets and has them in no team: StartRing must NOT field them
	local okR, whyR = Battle.StartRing(b)
	T.check(okR == false and whyR == Battle.TEAM_REFUSALS.Empty and Battle.IsInBattle(b) == false, "tb team: no 'else strongest' fallback", tostring(whyR))
	T.check(#prof.Equipped == 0, "tb team: ...and nothing was filled in silently")
	K.removePlayers({ b })
	advance(1)
	release()
	K.flushErrors("tb_team_refusal")
	K.flushWarnings("tb_team_refusal", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- tb_team_migrate
----------------------------------------------------------------------------------------------------
local PETS = { [K1] = 1, [K2] = 1, [K3] = 1, [K4] = 1 }

local function record(equipped, presets, active, extra)
	local rec = {
		Version = 2, Tokens = 77, Pets = {}, Equipped = equipped, Items = {}, Stats = statsOf(), Gems = 3,
		Teams = { Presets = presets, Active = active },
	}
	for k, v in pairs(PETS) do
		rec.Pets[k] = v
	end
	for k, v in pairs(extra or {}) do
		rec[k] = v
	end
	return rec
end

local function petsIntact(prof, want)
	for k, v in pairs(want or PETS) do
		if prof.Pets[k] ~= v then
			return false
		end
	end
	return true
end

S.tb_team_migrate = guarded("tb_team_migrate", function()
	if not K.needBoot() then
		return
	end
	local Data = DS()
	local DSt = Mock.DataStore
	local cases = {
		{ Name = "Empty", Uid = 966301, Equipped = {}, Presets = { { K1, K2 }, {}, {} }, Active = 1, WantActive = 1, WantEquipped = { K1, K2 }, WantPresets = { { K1, K2 }, {}, {} } },
		-- Review Focus 1: the same keys in another order: one team, no duplicate; Equipped takes the preset's order
		{ Name = "Same", Uid = 966302, Equipped = { K2, K1 }, Presets = { { K3 }, { K1, K2 }, {} }, Active = 1, WantActive = 2, WantEquipped = { K1, K2 }, WantPresets = { { K3 }, { K1, K2 }, {} } },
		{ Name = "Free", Uid = 966303, Equipped = { K1 }, Presets = { { K3 }, {}, { K2 } }, Active = 1, WantActive = 2, WantEquipped = { K1 }, WantPresets = { { K3 }, { K1 }, { K2 } } },
		{ Name = "Replaced", Uid = 966304, Equipped = { K1 }, Presets = { { K2 }, { K3 }, { K4 } }, Active = 2, WantActive = 3, WantEquipped = { K1 }, WantPresets = { { K2 }, { K3 }, { K1 } } },
		-- the active preset already holds them: nothing moves
		{ Name = "Same", Label = "Same (the active preset)", Uid = 966305, Equipped = { K2, K1 }, Presets = { { K1, K2 }, { K1, K2 }, {} }, Active = 2, WantActive = 2, WantEquipped = { K1, K2 }, WantPresets = { { K1, K2 }, { K1, K2 }, {} } },
		-- the old list holds what the preset holds minus its training pet: that preset IS the team, no copy of it is made
		{ Name = "Same", Label = "Same (minus a training pet)", Uid = 966306, Equipped = { K1 }, Presets = { { K1, K2 }, {}, {} }, Active = 1, WantActive = 1, WantEquipped = { K1 }, WantPresets = { { K1, K2 }, {}, {} },
			Extra = { PetGrowth = { [K2] = { Job = { Stat = "Speed", Ends = os.time() + 3000, Rank = 1, Slot = 1, From = "Free", Paid = 0 } } } } },
		-- the same key twice (the old list allowed it with two copies): a preset holds each key once
		{ Name = "Free", Label = "Free (a key twice)", Uid = 966307, Equipped = { K1, K1 }, Presets = { { K3 }, {}, {} }, Active = 1, WantActive = 2, WantEquipped = { K1 }, WantPresets = { { K3 }, { K1 }, {} },
			Extra = { Pets = { [K1] = 2, [K3] = 1 } } },
		-- a pet that left Equipped for a training job on the old build (Job.From = "Follow") keeps a team slot: nothing else puts it back
		{ Name = "Free", Label = "Free (a pet training from Follow)", Uid = 966308, Equipped = { K2, K3 }, Presets = { { K4 }, {}, {} }, Active = 1, WantActive = 2, WantEquipped = { K2, K3 }, WantPresets = { { K4 }, { K2, K3, K1 }, {} },
			Extra = { PetGrowth = { [K1] = { Job = { Stat = "Speed", Ends = os.time() + 3000, Rank = 1, Slot = 1, From = "Follow", Paid = 0 } } } } },
		{ Name = "Same", Label = "Same (a pet training from Follow, the preset lost it)", Uid = 966312, Equipped = { K2, K3 }, Presets = { { K2, K3 }, {}, {} }, Active = 1, WantActive = 1, WantEquipped = { K2, K3 }, WantPresets = { { K2, K3, K1 }, {}, {} },
			Extra = { PetGrowth = { [K1] = { Job = { Stat = "Speed", Ends = os.time() + 3000, Rank = 1, Slot = 1, From = "Follow", Paid = 0 } } } } },
		{ Name = "Same", Label = "Same (a pet training from Follow, still in the preset)", Uid = 966313, Equipped = { K2, K3 }, Presets = { { K1, K2, K3 }, {}, {} }, Active = 1, WantActive = 1, WantEquipped = { K2, K3 }, WantPresets = { { K1, K2, K3 }, {}, {} },
			Extra = { PetGrowth = { [K1] = { Job = { Stat = "Speed", Ends = os.time() + 3000, Rank = 1, Slot = 1, From = "Follow", Paid = 0 } } } } },
		{ Name = "Empty", Label = "Empty (a pet training from Follow)", Uid = 966314, Equipped = {}, Presets = { { K2 }, {}, {} }, Active = 1, WantActive = 1, WantEquipped = { K2 }, WantPresets = { { K2, K1 }, {}, {} },
			Extra = { PetGrowth = { [K1] = { Job = { Stat = "Speed", Ends = os.time() + 3000, Rank = 1, Slot = 1, From = "Follow", Paid = 0 } } } } },
		-- a full team: no fourth slot; the pet stays owned, outside the team
		{ Name = "Free", Label = "Free (a pet training from Follow, no room)", Uid = 966315, Equipped = { K2, K3, K4 }, Presets = { {}, {}, {} }, Active = 1, WantActive = 1, WantEquipped = { K2, K3, K4 }, WantPresets = { { K2, K3, K4 }, {}, {} },
			Extra = { PetGrowth = { [K1] = { Job = { Stat = "Speed", Ends = os.time() + 3000, Rank = 1, Slot = 1, From = "Follow", Paid = 0 } } } } },
		-- trained from the Garden or free: no slot to give back
		{ Name = "Free", Label = "Free (a pet training from Free)", Uid = 966316, Equipped = { K2, K3 }, Presets = { { K4 }, {}, {} }, Active = 1, WantActive = 2, WantEquipped = { K2, K3 }, WantPresets = { { K4 }, { K2, K3 }, {} },
			Extra = { PetGrowth = { [K1] = { Job = { Stat = "Speed", Ends = os.time() + 3000, Rank = 1, Slot = 1, From = "Free", Paid = 0 } } } } },
	}
	for _, c in ipairs(cases) do
		local label = c.Label or c.Name
		DSt.Data[storeKey(c.Uid)] = record(c.Equipped, c.Presets, c.Active, c.Extra)
		local p = join("TbMig" .. c.Uid, c.Uid)
		local prof = Data.GetProfile(p)
		local wantPets = c.Extra and c.Extra.Pets or PETS
		local same = true
		for i = 1, 3 do
			same = same and eq(prof.Teams.Presets[i], c.WantPresets[i])
		end
		T.check(same and prof.Teams.Active == c.WantActive, "tb team migrate " .. label .. ": presets and the active one", listText(prof.Teams.Presets[1]) .. listText(prof.Teams.Presets[2]) .. listText(prof.Teams.Presets[3]) .. " active " .. tostring(prof.Teams.Active))
		T.check(eq(prof.Equipped, c.WantEquipped) and inv(p), "tb team migrate " .. label .. ": Equipped", listText(prof.Equipped))
		T.check(prof.Migrations.B4TeamFollow == true, "tb team migrate " .. label .. ": the marker is set")
		local now = Data.MigratedNow(p, "B4TeamFollow")
		T.check(type(now) == "table" and now.Case == c.Name and now.Preset == c.WantActive, "tb team migrate " .. label .. ": MigratedNow { Preset, Case }", now and (tostring(now.Case) .. "/" .. tostring(now.Preset)) or "nil")
		T.check(petsIntact(prof, wantPets) and prof.Tokens == 77 and prof.Gems == 3, "tb team migrate " .. label .. ": every pet count and Token unchanged")
		T.check(p:GetAttribute("EquippedPets") == table.concat(c.WantEquipped, ","), "tb team migrate " .. label .. ": the attribute follows", tostring(p:GetAttribute("EquippedPets")))
		leave(p)
		local rec = stored(c.Uid)
		T.check(rec and rec.Migrations and rec.Migrations.B4TeamFollow == true and eq(rec.Equipped, c.WantEquipped), "tb team migrate " .. label .. ": the store holds the marker and the team", rec and listText(rec.Equipped) or "nil")
		-- a second load changes nothing
		local p2 = join("TbMig" .. c.Uid, c.Uid)
		local prof2 = Data.GetProfile(p2)
		same = true
		for i = 1, 3 do
			same = same and eq(prof2.Teams.Presets[i], c.WantPresets[i])
		end
		T.check(same and prof2.Teams.Active == c.WantActive and eq(prof2.Equipped, c.WantEquipped) and Data.MigratedNow(p2, "B4TeamFollow") == nil, "tb team migrate " .. label .. ": a second load changes nothing")
		leave(p2)
	end

	-- provisional: an outage load does not migrate; the recovery does, once
	local UP = 966310
	DSt.Data[storeKey(UP)] = record({ K1 }, { { K3 }, {}, {} }, 1)
	DSt.Fail = true
	local d = join("TbMigProv", UP)
	advance(1)
	T.check(Data.IsProvisional(d) == true and Data.GetProfile(d).Migrations.B4TeamFollow == nil and Data.MigratedNow(d, "B4TeamFollow") == nil, "tb team migrate: a provisional profile waits")
	-- every team edit on that stand-in names the save, so it is not read as a bug with the pet
	local recovering = "Your save is still being recovered, try again in a moment"
	local standIn = Data.GetProfile(d)
	standIn.Pets[K1] = 1 -- (the stand-in owns what it was given: the refusal is about the save, not the pet)
	local standIn = Data.GetProfile(d)
	standIn.Pets[K1] = 1 -- (the stand-in owns what it was given: the refusal is about the save, not the pet)
	local okE, whyE = PS().Equip(d, K1)
	local okU, whyU = PS().Unequip(d, K1)
	local okC, whyC = PS().CanEquip(d, K1, 0)
	local okS, whyS = Data.SetTeam(d, 1, { K1 })
	local okA, whyA = Data.SelectTeam(d, 2)
	local okK, whyK = Data.CheckTeam(d, 1, { K1 })
	T.check(not okE and whyE == recovering and not okU and whyU == recovering and not okC and whyC == recovering, "tb team migrate: a provisional Equip / Unequip / CanEquip says the save is being recovered", tostring(whyE) .. " / " .. tostring(whyU) .. " / " .. tostring(whyC))
	T.check(not okS and whyS == recovering and not okA and whyA == recovering and not okK and whyK == recovering, "tb team migrate: ...SetTeam / SelectTeam / CheckTeam too", tostring(whyS) .. " / " .. tostring(whyA) .. " / " .. tostring(whyK))
	standIn.Pets[K1] = nil
	standIn.Pets[K1] = nil
	DSt.Fail = false
	local recovered = K.waitFor(function()
		return not Data.IsProvisional(d)
	end, 40)
	advance(1)
	local dp = Data.GetProfile(d)
	T.check(recovered and dp.Migrations.B4TeamFollow == true and dp.Teams.Active == 2 and eq(dp.Teams.Presets[2], { K1 }) and eq(dp.Teams.Presets[1], { K3 }) and eq(dp.Equipped, { K1 }),
		"tb team migrate: ...the recovery migrates it", listText(dp.Equipped) .. " active " .. tostring(dp.Teams.Active))
	T.check(type(Data.MigratedNow(d, "B4TeamFollow")) == "table" and Data.MigratedNow(d, "B4TeamFollow").Case == "Free", "tb team migrate: ...and MigratedNow answers it")
	leave(d)

	-- the migration fires TeamsChanged once with the load, no toast: nothing here names it
	local UT = 966311
	DSt.Data[storeKey(UT)] = record({ K1 }, { { K3 }, {}, {} }, 1)
	local fired = 0
	local conn = Data.TeamsChanged:Connect(function(pl)
		if pl.UserId == UT then
			fired = fired + 1
		end
	end)
	local mark = K.logSize()
	local t = join("TbMigSig", UT)
	conn:Disconnect()
	T.eq(fired, 1, "tb team migrate: TeamsChanged fires once on the load that moved a team")
	T.check(not K.notified(t, "team", nil, mark), "tb team migrate: no toast")
	leave(t)
	K.flushErrors("tb_team_migrate")
	K.flushWarnings("tb_team_migrate", { "[DataService]" })
end)

----------------------------------------------------------------------------------------------------
-- tb_team_rollout
----------------------------------------------------------------------------------------------------
-- the connections a second DataService module adds to the shared signals (dropped when it goes, see smoke_p5_data.lua)
local function connectionMarks()
	local folder = K.remoteFolder and K.remoteFolder()
	local signals = { game:GetService("Players").PlayerRemoving }
	for _, name in ipairs({ "RequestProfile", "SettingsSet" }) do
		local remote = folder and folder:FindFirstChild(name)
		if remote then
			signals[#signals + 1] = remote.OnServerEvent
		end
	end
	local marks = {}
	for _, sig in ipairs(signals) do
		local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
		marks[#marks + 1] = { conns = conns, n = conns and #conns or 0 }
	end
	return marks
end

local function dropHooks(marks)
	for _, m in ipairs(marks) do
		for i = #(m.conns or {}), m.n + 1, -1 do
			local conn = m.conns[i]
			if type(conn) == "table" and conn.Disconnect then
				conn:Disconnect()
			end
		end
	end
end

-- the frozen Phase 4 DataService as a second module ("a Phase 4 server"), or nil + reason (the smoke_p5_data.lua shape)
local function phase4Server()
	local src = nil
	for _, candidate in ipairs({ "tools/fixtures/DataService_phase4.lua", "fixtures/DataService_phase4.lua", "../tools/fixtures/DataService_phase4.lua", "nimbus-climb/tools/fixtures/DataService_phase4.lua" }) do
		local fh = io.open(candidate, "r")
		if fh then
			src = fh:read("*a")
			fh:close()
			break
		end
	end
	if not src or #src < 1000 then
		return nil, "tools/fixtures/DataService_phase4.lua not found from the working directory"
	end
	local inst = K.moduleInstance("server/Services/DataService")
	local fixture = Instance.new("ModuleScript")
	fixture.Name = "DataServicePhase4FixtureTb"
	fixture.Source = (string.gsub(src, "Config%.Items%.MaxCarry", "5"))
	fixture.Parent = inst.Parent
	local marks = connectionMarks()
	local okReq, P4DS = pcall(require, fixture)
	if not okReq or type(P4DS) ~= "table" or type(P4DS.Load) ~= "function" then
		fixture:Destroy()
		dropHooks(marks)
		return nil, tostring(P4DS)
	end
	return P4DS, function()
		fixture:Destroy()
		dropHooks(marks)
	end
end

S.tb_team_rollout = guarded("tb_team_rollout", function()
	if not K.needBoot() then
		return
	end
	local Data = DS()
	local P4DS, release = phase4Server()
	if not T.check(P4DS ~= nil, "tb team rollout: the frozen Phase 4 DataService loads as a second module", tostring(release)) then
		return
	end
	local UID = 966401
	-- what a Phase 4 save holds: an equipped list next to presets of up to 4 keys
	Mock.DataStore.Data[storeKey(UID)] = {
		Version = 2, Tokens = 10, Pets = { [K1] = 1, [K2] = 1, [K3] = 1, [K4] = 1, [K5] = 1 }, Equipped = { K5, K4 }, Items = {}, Stats = statsOf(),
		Cash = 777, Gems = 3,
		Teams = { Presets = { { K1, K2, K3, K4 }, { K5 }, {} }, Active = 1 },
		Migrations = { P4 = true },
		PetLevels = { [K1] = { Level = 12, Xp = 0 } },
	}
	local okRun, errRun = pcall(function()
		local p = join("TbRoll", UID)
		local prof = Data.GetProfile(p)
		T.check(inv(p) and prof.Migrations.B4TeamFollow == true, "tb team rollout: a Phase 4 save loads with the invariant", listText(prof.Equipped))
		T.check(eq(prof.Teams.Presets[1], { K1, K2, K3 }) and eq(prof.Teams.Presets[2], { K5 }) and eq(prof.Teams.Presets[3], { K5, K4 }) and prof.Teams.Active == 3 and eq(prof.Equipped, { K5, K4 }),
			"tb team rollout: its followers became the first empty preset and the active one", listText(prof.Teams.Presets[3]))
		for _, key in ipairs({ K1, K2, K3, K4, K5 }) do
			T.check(prof.Pets[key] == 1, "tb team rollout: " .. key .. " is still owned")
		end
		T.check(prof.Cash == 777 and prof.Gems == 3 and prof.PetLevels[K1].Level == 12, "tb team rollout: Cash, Gems, levels unchanged")
		T.eq(Data.Save(p), true, "tb team rollout: (setup) the marked save is in the store")

		-- a Phase 4 server plays on the marked save: it knows nothing of the invariant and writes a 4-key preset and its own list
		local p4prof = P4DS.Load(p)
		T.check(type(p4prof) == "table", "tb team rollout: the Phase 4 server loads the marked save")
		T.check(P4DS.SetTeam(p, 2, { K2, K3 }) == true, "tb team rollout: the Phase 4 server stores a preset")
		P4DS.AddTokens(p, 5)
		p4prof.Equipped[1] = K1
		P4DS.MarkDirty(p)
		T.eq(P4DS.Save(p), true, "tb team rollout: the Phase 4 server saves")
		local st = stored(UID) or {}
		T.check(st.Migrations and st.Migrations.B4TeamFollow == true, "tb team rollout: the marker comes back from the Phase 4 server")

		-- this server reads it back: the invariant holds again and nothing is re-migrated
		Data.AddTokens(p, 1)
		T.eq(Data.Save(p), true, "tb team rollout: this server saves and adopts the store")
		advance(0.3)
		prof = Data.GetProfile(p)
		T.check(inv(p) and eq(prof.Teams.Presets[1], { K1, K2, K3 }) and eq(prof.Teams.Presets[2], { K2, K3 }) and prof.Teams.Active == 3 and eq(prof.Equipped, { K5, K4 }), "tb team rollout: Equipped follows the active preset, whatever list that server wrote", listText(prof.Equipped) .. " / " .. listText(prof.Teams.Presets[2]))
		T.check(prof.Pets[K4] == 1 and Data.MigratedNow(p, "B4TeamFollow") ~= nil, "tb team rollout: no lost key")
		leave(p)
	end)
	release()
	if not okRun then
		error(errRun, 0)
	end
	K.flushErrors("tb_team_rollout")
	K.flushWarnings("tb_team_rollout", { "[DataService]" })
end)

return S
