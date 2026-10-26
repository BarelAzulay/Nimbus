--!nocheck
-- DungeonService (ARCHITECTURE_V3.md "Phase 5 build contract" 5.2-5.4, 5.7, 10.4 Y3-Y6; dungeon W3)
--
-- Parties, runs and loot of the Dungeon. Combat goes ONLY through BattleService's encounter API (4.6): one encounter
-- per room (a fresh BattleSim, full HP), KeepInBattle = true (the RUN owns the InBattle attribute: its id "D<n>" is
-- written before the teleport and released by Dg.endRun / Dg.removeMember). Every reward is paid by this service,
-- once per room per qualifying member (result.Fighters: >= Dungeon.MinShare of the room's damage), marked in
-- run.Paid[room][userId] BEFORE the payment; first clears are decided inside DataService.MutateDungeon (`first`).
--
--   DungeonService.Init(deps)   deps { DataService, PetCareService, TycoonService, BattleService, DungeonBuilder,
--                               DungeonInfo, LobbyInfo, PetService }: wires DungeonRequest, the 0.5 s loop, then LAST
--                               BattleService.SetRunProvider({ KeysInRun, GetRun }) (C16)
--   API: CreateParty(player, floor), JoinParty(player, leaderUserId), LeaveParty(player), SetReady(player, bool),
--        SetFloor(player, floor), KickMember(leader, userId), StartRun(party) -> ok, runId | reason,
--        StartSolo(player, floor), Quit(player), OpenChest(player, slot), GetRun(player) -> { RunId, Floor, Room, State, Wave }
--        | nil, KeysInRun(player) -> {[key] = true}, ListParties(), Shutdown()
--   Signals: RunEnded(runId, result = { Floor, Cleared, Members, Winners, Loot, Reason }) after the payments;
--            FloorCleared(player, floor)
--   Remotes: DungeonRequest(action, a, b) c->s (Open / Create / Join / Leave / Ready / SetFloor / Start / Solo / Quit /
--            Chest / Kick), DungeonState(kind, payload) s->c (Lobby <= 1/s, Run, Loot, Chest, End, Fade { Out, Hold,
--            In, Room }), the gate's attribute DungeonBoard, the room models' DoorOpen / EntranceOpen attributes; the
--            doors' EnterPrompt (DungeonAction "Enter") arrives through ProximityPromptService.PromptTriggered
-- The treasure (bug batch 2, #14): every member owed a chest picks ONE of the alcove's chests with its E prompt (no GUI
-- button). The prompt's ChestSlot goes to Dg.openChest(run, m, slot): a real slot, free, the member within CHEST_RANGE,
-- the member's own chest still closed. The drop is rolled from run.Seed + slot * 7919 (every chest its own roll), the
-- chest part is marked Opened / OpenedBy, its prompt disabled for everyone, a glow lit. A "Chest" request without a
-- slot opens nothing. The 45 s exit (and a member leaving in the alcove) gives the first free slot.
--
-- Run.State: "Hall" -> "Corridor" (Phase "Threshold": at the room's entrance until a member crosses the Threshold part;
-- Phase "Walk": the room is cleared, its exit bars open after Intermission) -> "Fight" -> ... -> "Treasure"
-- (TreasureSeconds, chests) -> "Ending" (End sent, Runs + 1, return teleport after RETURN_DELAY, InBattle released,
-- pocket freed, party removed, RunEnded once). Late joins while Hall / Corridor and Room <= LateJoinLastRoom.
-- Moving on (dungeon-fixes decision 2): NO timer ever moves the group to another room. In the Hall (the hall's exit ->
-- room 1) and after a clear once the bars are open (the NEXT room's closed Door_Entrance; the boss room's exit -> the
-- treasure) one EnterPrompt is enabled (Dg.nextDoor / Dg.syncPrompt). Its E press (ProximityPromptService, nothing new
-- from the client) is Dg.confirm: run.Confirm[userId] = true, idempotent (own pocket, State Hall / Corridor-Walk, a
-- member not Left, within CONFIRM_RANGE of the prompt, not during a transit). When every member still in the run
-- (Downed ones too) confirmed, Dg.transit: run.Transit lock, DungeonState("Fade", { Out, Hold, In, Room }) to the
-- members, after Out Dg.finishTransit (once per transit: TransitSeq + the state it started from) enters the next room
-- (Dg.enterRoom: Door_Entrance opened, members at its Entrance) or the treasure, and clears Confirm / Transit. A member
-- leaving re-checks the count; a late joiner must press too. The Run payload carries Confirmed { userId... },
-- NeedConfirm (presses still missing), EnterOpen (a door is waiting), Next (the room it leads to, 5 = the treasure).
-- Watchdog (the loop): a Fight whose encounter is gone for 15 s, or any run older than MaxRunSeconds(floor) -> endRun
-- "Error". MaxRunSeconds no longer counts DoorTime: it allows WAIT_ALLOWANCE seconds per door (5 doors) in total, so a
-- slow-walking group is never ended early while an AFK group still frees its pocket.
-- Rate limits: DungeonRequest burst 6 refill 2 / s + per-action cooldowns; the ladder type -> range -> permission ->
-- plausibility; refusals are throttled side toasts.
-- Plain Lua 5.1 syntax only (Luau subset); no per-frame loops, no server tweens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local DungeonService = {}
DungeonService.RunEnded = Util.Signal() -- Fire(runId, result) once per run, after the payments
DungeonService.FloorCleared = Util.Signal() -- Fire(player, floor)
DungeonService.MAX_DUNGEONS = 8 -- 12 only after the owner's MicroProfiler check (judge M6)

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local function copyList(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

local ATTR_IN_BATTLE = (Config.Attr and Config.Attr.InBattle) or "InBattle"
local ATTR_IN_MATCH = (Config.Attr and Config.Attr.InMatch) or "InMatch"
local ATTR_PORTAL_LOCKED = (Config.Attr and Config.Attr.PortalLocked) or "PortalLocked"

local K = {
	MAX_PARTY = 4,
	RETURN_DELAY = 4,
	START_COUNTDOWN = 5, -- "Dungeon in 5..."
	THRESHOLD_TIMEOUT = 30, -- nobody crossed the Threshold: the fight starts anyway (keeps a run moving)
	WATCHDOG_MISSING = 15,
	LEASH = 80, -- studs from the room centre
	LEASH_STRIKES = 2,
	JOIN_QUEUE = 20, -- a join during a fight waits this long for the corridor
	START_RANGE = 30, -- studs from the portal pad
	BOARD_MAX = 5,
	NEXT_WAVE = 1.5,
	LOOP = 0.5,
	LOBBY_GAP = 1, -- Lobby pushes per client
	TOAST_GAP = 3,
	FAR = 500, -- a member this far from the pocket respawned elsewhere
	BUCKET_BURST = 6,
	BUCKET_REFILL = 2,
	CONFIRM_RANGE = 14, -- studs from the EnterPrompt's part (the prompt itself shows within 10)
	WAIT_ALLOWANCE = 180, -- watchdog seconds per door wait (hall + 3 corridors + the boss exit = 5 waits, pooled)
	DOOR_WAITS = 5,
	CHEST_RANGE = 9, -- studs from the chest (its prompt shows within 7)
}
-- bug batch 2 #14: one pickable chest slot per possible member; Init asserts DungeonBuilder.CHEST_COUNT (the chests
-- Treasure_1 builds) >= this, so a full party never runs out of chests (the builder comes in through deps, no require)
K.CHEST_SLOTS = K.MAX_PARTY

-- the room change's fade (dungeon-fixes decision 2): the server enters the next room after Out
local FADE = { Out = 0.45, Hold = 0.35, In = 0.45 }

local COOLDOWN = { Create = 2, Join = 1, Ready = 0.3, SetFloor = 0.5, Start = 1.5, Quit = 1, Chest = 0.5, Open = 0.5, Kick = 1, Leave = 0.5, Solo = 1.5, Enter = 0.25 }
local ACTIONS = { Open = true, Create = true, Join = true, Leave = true, Ready = true, SetFloor = true, Start = true, Solo = true, Quit = true, Chest = true, Kick = true }

local St = {
	deps = {},
	parties = {}, -- leaderUserId -> Party
	partyOrder = {}, -- leaderUserIds in creation order (deterministic listings)
	partyOf = {}, -- Player -> Party
	runs = {}, -- runId -> Run
	runOrder = {}, -- runIds in creation order
	runOf = {}, -- Player -> Run
	runByBattle = {}, -- battleId -> Run
	pocketBusy = {}, -- index -> true
	buckets = {}, -- Player -> { tokens, last }
	cooldowns = {}, -- Player -> { [action] = clock }
	toasts = {}, -- Player -> { [text] = clock }
	lobbyDirty = {}, -- Player -> true (a Lobby push is owed)
	lobbySent = {}, -- Player -> clock of the last Lobby push
	joinQueue = {}, -- Player -> { Party, Deadline }
	strikes = {}, -- Player -> leash strikes
	board = {}, -- name -> best floor cleared on this server
	conns = {},
	remotes = {},
	seq = 0,
	closing = false,
	initialized = false,
	loop = nil,
}

local Dg = {} -- the run machinery (exported for tests: DungeonService.Dg)
DungeonService.Dg = Dg
DungeonService.St = St

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function now()
	return os.clock()
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function whole(n, lo, hi)
	if not finite(n) or n ~= floor(n) then
		return nil
	end
	if lo and n < lo then
		return nil
	end
	if hi and n > hi then
		return nil
	end
	return n
end

local function isPlayer(p)
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent ~= nil
end

local function hasFn(t, name)
	return type(t) == "table" and type(t[name]) == "function"
end

local function try(t, name, ...)
	if hasFn(t, name) then
		local ok, a, b, c = pcall(t[name], ...)
		if ok then
			return a, b, c
		end
		warn("[DungeonService] " .. tostring(name) .. " failed: " .. tostring(a))
	end
	return nil
end

local function catalog()
	local ok, BC = pcall(require, Shared:FindFirstChild("BattleCatalog"))
	if ok and type(BC) == "table" then
		return BC
	end
	return nil
end

local function D()
	local BC = catalog()
	local d = BC and BC.Dungeon
	return type(d) == "table" and d or {}
end

local function num(v, fallback)
	return finite(v) and v or fallback
end

local function getRemote(name)
	local cached = St.remotes[name]
	if cached ~= nil then
		return cached or nil
	end
	local ok, remote = pcall(Remotes.Get, name)
	if ok and remote then
		St.remotes[name] = remote
		return remote
	end
	St.remotes[name] = false
	return nil
end

local function notify(player, text, kind, duration)
	if not isPlayer(player) or type(text) ~= "string" or text == "" then
		return
	end
	local list = St.toasts[player]
	if not list then
		list = {}
		St.toasts[player] = list
	end
	local t = now()
	if list[text] and t - list[text] < K.TOAST_GAP then
		return
	end
	list[text] = t
	local remote = getRemote("Notify")
	if remote then
		if #text > 90 then
			text = text:sub(1, 89) .. "."
		end
		pcall(function()
			remote:FireClient(player, text, kind or "info", duration or 3)
		end)
	end
end

local function sendState(player, kind, payload)
	if not isPlayer(player) then
		return false
	end
	local remote = getRemote("DungeonState")
	if not remote then
		return false
	end
	local ok = pcall(function()
		remote:FireClient(player, kind, payload)
	end)
	return ok
end

local function rootOf(player)
	local char = isPlayer(player) and player.Character or nil
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function teleport(player, cf)
	local char = isPlayer(player) and player.Character or nil
	if not char or typeof(cf) ~= "CFrame" then
		return false
	end
	local ok = pcall(function()
		char:PivotTo(cf)
	end)
	if not ok then
		local root = rootOf(player)
		if root then
			root.CFrame = cf
		end
	end
	return true
end

local function setInBattle(player, value)
	if isPlayer(player) then
		pcall(function()
			player:SetAttribute(ATTR_IN_BATTLE, value)
		end)
	end
end

local function shortName(player)
	return isPlayer(player) and (player.DisplayName or player.Name) or "?"
end

local function countLive(run)
	local n = 0
	for _, uid in ipairs(run.Order) do
		local m = run.Members[uid]
		if m and not m.Left then
			n = n + 1
		end
	end
	return n
end

local function liveMembers(run)
	local out = {}
	for _, uid in ipairs(run.Order) do
		local m = run.Members[uid]
		if m and not m.Left then
			out[#out + 1] = m
		end
	end
	return out
end

local function partyCount(party)
	local n = 0
	for _, uid in ipairs(party.Order) do
		if party.Members[uid] then
			n = n + 1
		end
	end
	return n
end

-- a member out of a party: the record AND its Order entry (a later re-join appends once; partyCount stays exact)
local function dropPartyMember(party, uid)
	party.Members[uid] = nil
	for i = #party.Order, 1, -1 do
		if party.Order[i] == uid then
			table.remove(party.Order, i)
		end
	end
end

-- the member qualified (>= MinShare of the party's damage) in at least one room: the only ones the boss chest is for (5.2 / Y4)
local function qualifiedAnywhere(m)
	local q = type(m.Qualified) == "table" and m.Qualified or {}
	for room = 1, 4 do
		if q[room] == true then
			return true
		end
	end
	return false
end

-- the watchdog's limit of a run (5.4 + dungeon-fixes decision 2): Dungeon.RunMaxSeconds or, when longer, the floor's
-- own worst case: 4 rooms at the floor's room limit, 4 Threshold waits + Intermissions, the door waits (no DoorTime /
-- HallSeconds any more: the group walks at its own pace and presses E, so DOOR_WAITS x WAIT_ALLOWANCE seconds of
-- waiting are allowed in total, pooled over the hall, the corridors and the boss exit), the fades, the treasure and
-- 120 s of slack. Floor 2: 4 x 120 + 4 x 32 + 5 x 180 + 5 x 1.25 + 45 + 120 = 1679 s (28 min) instead of 703 s.
function DungeonService.MaxRunSeconds(floorIndex)
	local d = D()
	local roomTime = (floorIndex == 1) and num(d.Floor1RoomTime, 180) or num(d.RoomTime, 120)
	local fade = FADE.Out + FADE.Hold + FADE.In
	local worst = 4 * roomTime + 4 * (K.THRESHOLD_TIMEOUT + num(d.Intermission, 2)) + K.DOOR_WAITS * (K.WAIT_ALLOWANCE + fade) + num(d.TreasureSeconds, 45) + 120
	return max(num(d.RunMaxSeconds, 700), worst)
end

local function markLobbyDirty()
	for _, p in ipairs(Players:GetPlayers()) do
		St.lobbyDirty[p] = true
	end
end

----------------------------------------------------------------------
-- Records (DataService.GetDungeon / MutateDungeon; nil while provisional)
----------------------------------------------------------------------
local function record(player)
	local rec = try(St.deps.DataService, "GetDungeon", player)
	if type(rec) == "table" then
		return rec
	end
	return { Best = 0, Cleared = {}, Runs = 0, Clears = 0 }
end

local function profileReady(player)
	local DS = St.deps.DataService
	local prof = try(DS, "GetProfile", player)
	if type(prof) ~= "table" then
		return false, "Your save is still loading"
	end
	local provisional = try(DS, "IsProvisional", player)
	if provisional == true then
		return false, "Your save is still loading"
	end
	return true, prof
end

local function ownsPet(player)
	local prof = try(St.deps.DataService, "GetProfile", player)
	if type(prof) == "table" and type(prof.Pets) == "table" then
		for _, n in pairs(prof.Pets) do
			if (tonumber(n) or 0) > 0 then
				return true
			end
		end
	end
	return false
end

-- ok, reason: the entry checks of 5.3 in order (pet, team, battle-free, distance, loaded, floor for the leader)
local function canEnter(player, floorIndex, isLeader, checkDistance)
	if not isPlayer(player) then
		return false, "That player is not here"
	end
	if not ownsPet(player) then
		return false, "You need a pet"
	end
	local spec, why = try(St.deps.BattleService, "TeamSpec", player)
	if type(spec) ~= "table" then
		return false, why or "You need a pet"
	end
	if St.closing then
		return false, "The server is restarting: the dungeon will be back in a moment"
	end
	if player:GetAttribute(ATTR_IN_MATCH) == true then
		return false, "Finish your obby match first"
	end
	local locked = player:GetAttribute(ATTR_PORTAL_LOCKED)
	if locked ~= nil and locked ~= false and locked ~= "" then
		return false, "Leave the portal party first"
	end
	local inBattle = player:GetAttribute(ATTR_IN_BATTLE)
	if (inBattle ~= nil and inBattle ~= false and inBattle ~= "") or try(St.deps.BattleService, "IsInBattle", player) == true then
		if St.runOf[player] then
			return false, "Finish your dungeon run first"
		end
		return false, "Finish your battle first"
	end
	if checkDistance then
		local info = St.deps.DungeonInfo
		local pad = type(info) == "table" and (info.Pad or info.PromptPart) or nil
		local root = rootOf(player)
		if pad and root and (root.Position - pad.Position).Magnitude > K.START_RANGE then
			return false, "Walk to the Dungeon gate first"
		end
		if not root then
			return false, "Respawn first"
		end
	end
	local ok, why2 = profileReady(player)
	if not ok then
		return false, why2
	end
	if isLeader then
		local rec = record(player)
		if (tonumber(rec.Best) or 0) < floorIndex - 1 then
			return false, "Clear floor " .. tostring(floorIndex - 1) .. " first"
		end
	end
	return true, spec
end

local function powerOf(spec)
	local BC = catalog()
	if not BC or type(spec) ~= "table" or type(spec.Pets) ~= "table" then
		return 0
	end
	local list = {}
	for i, pet in ipairs(spec.Pets) do
		list[i] = { Def = pet.Def, Level = pet.Level, Tier = pet.Tier, Evo = pet.Evo, Train = pet.Train }
	end
	local ok, power = pcall(BC.TeamPower, list)
	if ok and finite(power) then
		return floor(power + 0.5)
	end
	return 0
end

local function keysOf(spec)
	local keys = {}
	for i, pet in ipairs(type(spec) == "table" and spec.Pets or {}) do
		keys[i] = pet.Key
	end
	return keys
end

----------------------------------------------------------------------
-- The Lobby payload (<= 1/s per client)
----------------------------------------------------------------------
local function lobbyPayload(player)
	local parties = {}
	for _, leaderId in ipairs(St.partyOrder) do
		local party = St.parties[leaderId]
		if party then
			local run = party.Run
			parties[#parties + 1] = {
				Leader = leaderId,
				LeaderName = shortName(party.Leader),
				Floor = party.Floor,
				Count = partyCount(party),
				Max = K.MAX_PARTY,
				Open = partyCount(party) < K.MAX_PARTY and (run == nil or run.Joinable == true or (run.State == "Fight" and run.Room <= num(D().LateJoinLastRoom, 2) and countLive(run) < K.MAX_PARTY)),
				InRun = run ~= nil,
				Room = run and run.Room or nil,
			}
		end
	end
	local mine = nil
	local party = St.partyOf[player]
	if party then
		local members = {}
		for _, uid in ipairs(party.Order) do
			local m = party.Members[uid]
			if m then
				members[#members + 1] = { UserId = uid, Name = shortName(m.Player), Ready = m.Ready == true or uid == party.Leader.UserId, Power = m.Power or 0 }
			end
		end
		mine = {
			Leader = party.Leader.UserId,
			Floor = party.Floor,
			Members = members,
			Countdown = party.StartAt and max(0, floor(party.StartAt - now() + 0.5)) or nil,
			InRun = party.Run ~= nil,
		}
	end
	local rec = record(player)
	local cleared = {}
	for f = 1, 12 do
		cleared[f] = rec.Cleared and rec.Cleared[f] == true or false
	end
	return {
		Parties = parties,
		Mine = mine,
		Record = { Best = tonumber(rec.Best) or 0, Cleared = cleared, Runs = tonumber(rec.Runs) or 0, Clears = tonumber(rec.Clears) or 0 },
	}
end

local function pushLobby(player, force)
	if not isPlayer(player) then
		return
	end
	local t = now()
	local last = St.lobbySent[player]
	if last and t - last < K.LOBBY_GAP and not force then
		St.lobbyDirty[player] = true
		return
	end
	St.lobbySent[player] = t
	St.lobbyDirty[player] = nil
	sendState(player, "Lobby", lobbyPayload(player))
end

----------------------------------------------------------------------
-- Run payloads
----------------------------------------------------------------------
local function runPayload(run)
	local members = {}
	for _, uid in ipairs(run.Order) do
		local m = run.Members[uid]
		if m then
			members[#members + 1] = { UserId = uid, Name = shortName(m.Player), Downed = m.Downed == true, Left = m.Left == true }
		end
	end
	-- the door wait: who pressed E at the open door, how many presses are still missing (every member still in)
	local door, target = Dg.nextDoor(run)
	local confirmed, need = {}, 0
	-- the treasure: who still has a chest to pick (the card says "Pick ONE chest!" to them only)
	local owed = nil
	if run.State == "Treasure" then
		owed = {}
		for _, m in ipairs(liveMembers(run)) do
			if run.Chests[m.Player.UserId] == "Closed" then
				owed[#owed + 1] = m.Player.UserId
			end
		end
	end
	if door then
		local mine = run.ConfirmFor == target and run.Confirm or {}
		for _, m in ipairs(liveMembers(run)) do
			if mine[m.Player.UserId] then
				confirmed[#confirmed + 1] = m.Player.UserId
			else
				need = need + 1
			end
		end
	end
	return {
		Confirmed = confirmed,
		NeedConfirm = need,
		EnterOpen = door ~= nil,
		Next = door and target or nil,
		Transit = run.Transit == true,
		RunId = run.Id,
		Floor = run.Floor,
		Name = run.Name,
		Element = run.Element,
		Room = run.Room,
		RoomCount = 4,
		Wave = run.Wave,
		Waves = run.Waves,
		State = run.State,
		Phase = run.Phase,
		Members = members,
		Joinable = run.Joinable == true,
		ChestOwed = owed,
	}
end

local function sendRun(run)
	Dg.syncPrompt(run)
	local payload = runPayload(run)
	for _, m in ipairs(liveMembers(run)) do
		sendState(m.Player, "Run", payload)
	end
end

local function lootOf(run, uid)
	local loot = run.Loot[uid]
	if not loot then
		loot = { Cash = 0, Tokens = 0, Xp = 0, Gems = 0 }
		run.Loot[uid] = loot
	end
	return loot
end

local function endPayload(run, member, reason)
	local uid = member.Player.UserId
	local loot = lootOf(run, uid)
	return {
		Floor = run.Floor,
		Name = run.Name,
		Cleared = run.Cleared == true and member.ClearedFloor == true,
		Reason = reason or run.EndReason or "Ended",
		Room = run.Room,
		Totals = { Cash = loot.Cash, Tokens = loot.Tokens, Xp = loot.Xp, Gems = loot.Gems },
		FirstClear = member.FirstClear,
		Unlocked = member.Unlocked,
		NewBest = member.NewBest == true,
	}
end

----------------------------------------------------------------------
-- Pockets
----------------------------------------------------------------------
local function freePocket()
	for i = 1, DungeonService.MAX_DUNGEONS do
		if not St.pocketBusy[i] then
			return i
		end
	end
	return nil
end

local function updateBoard()
	local info = St.deps.DungeonInfo
	local portal = type(info) == "table" and info.Portal or nil
	if not portal then
		return
	end
	local names = {}
	for name in pairs(St.board) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b)
		if St.board[a] ~= St.board[b] then
			return St.board[a] > St.board[b]
		end
		return a < b
	end)
	local parts = {}
	for i = 1, min(K.BOARD_MAX, #names) do
		parts[#parts + 1] = names[i] .. "|" .. tostring(St.board[names[i]])
	end
	local text = table.concat(parts, ";")
	if portal:GetAttribute("DungeonBoard") ~= text then
		portal:SetAttribute("DungeonBoard", text)
		local tag = portal:FindFirstChild("GateTag", true)
		local pillLabel = tag and tag:FindFirstChild("Label", true)
		if pillLabel and pillLabel:IsA("TextLabel") then
			local line = {}
			for i = 1, min(2, #names) do
				line[#line + 1] = names[i] .. " - " .. tostring(St.board[names[i]])
			end
			pcall(function()
				pillLabel.Text = "Floors cleared here: " .. (#line > 0 and table.concat(line, ", ") or "-")
			end)
		end
	end
end

----------------------------------------------------------------------
-- Dg: the run machinery
----------------------------------------------------------------------
local function runSeed(party, floorIndex)
	return (party.Leader.UserId * 31 + St.seq * 7919 + floorIndex * 131) % 2147483647
end

local function roomInfo(run, room)
	return run.Pocket and run.Pocket.Rooms and run.Pocket.Rooms[room] or nil
end

local function wavesOf(run, room)
	local d = D()
	if room == 4 then
		return 2
	end
	local list = (run.Floor == 1) and d.Floor1Waves or d.Waves
	local w = type(list) == "table" and tonumber(list[room]) or nil
	return max(1, floor(w or 2))
end

-- the run id's attribute + the service's maps for a member
local function bindMember(run, player)
	setInBattle(player, run.Id)
	St.runOf[player] = run
end

local function unbindMember(run, player)
	if St.runOf[player] == run then
		St.runOf[player] = nil
	end
	if isPlayer(player) and player:GetAttribute(ATTR_IN_BATTLE) == run.Id then
		setInBattle(player, nil)
	end
	St.strikes[player] = nil
end

local function returnHome(player)
	local info = St.deps.DungeonInfo
	local cf = type(info) == "table" and info.ReturnCFrame or nil
	if typeof(cf) ~= "CFrame" then
		cf = CFrame.new(Config.Lobby.Origin + Vector3.new(0, 4, 0))
	end
	teleport(player, cf)
end

local function newMember(run, player, spec, joinedRoom)
	local member = {
		Player = player,
		Keys = keysOf(spec),
		Spec = spec,
		Power = powerOf(spec),
		JoinedRoom = joinedRoom,
		Downed = false,
		Left = false,
		Qualified = {},
	}
	run.Members[player.UserId] = member
	run.Order[#run.Order + 1] = player.UserId
	member.Slot = #run.Order
	lootOf(run, player.UserId)
	return member
end

-- Dg.begin(party) -> ok, runId | reason: reserves the pocket BEFORE any yield, builds the run, binds + teleports the members
function Dg.begin(party, readyOnly)
	local leader = party.Leader
	local floorIndex = party.Floor
	party.StartAt = nil
	party.WaitingReady = nil
	if party.Run then
		return false, "Your party is already in a run"
	end
	local index = freePocket()
	if not index then
		for _, uid in ipairs(party.Order) do
			local m = party.Members[uid]
			if m then
				notify(m.Player, "The dungeon is full, try again in a minute", "bad", 4)
			end
		end
		return false, "The dungeon is full, try again in a minute"
	end
	St.pocketBusy[index] = true
	St.seq = St.seq + 1
	local run = {
		Id = "D" .. tostring(St.seq),
		Floor = floorIndex,
		Seed = runSeed(party, floorIndex),
		Pocket = nil,
		State = "Hall",
		Phase = nil,
		Room = 0,
		Wave = 0,
		Waves = 0,
		Members = {},
		Order = {},
		Battle = nil,
		Rooms = {},
		Paid = {},
		Loot = {},
		Started = now(),
		StateAt = now(),
		Joinable = true,
		Chests = {},
		ChestTaken = {}, -- slot -> userId: the alcove's chest that member picked (one chest, one member)
		Cleared = false,
		Party = party,
		PocketIndex = index,
		Confirm = {}, -- userId -> true: pressed E at the open door (for run.ConfirmFor = the room it leads to)
		ConfirmFor = nil,
		Transit = nil, -- true from the last press to the next room (the lock: later presses are ignored)
		TransitSeq = 0,
	}
	-- members in party order: the entry checks, the team spec fixed now
	local dropped = {}
	for _, uid in ipairs(party.Order) do
		local pm = party.Members[uid]
		if pm and isPlayer(pm.Player) then
			local isReady = pm.Ready == true or uid == leader.UserId
			if readyOnly and not isReady then
				dropped[#dropped + 1] = pm.Player
			else
				local ok, specOrWhy = canEnter(pm.Player, floorIndex, uid == leader.UserId, true)
				if ok then
					newMember(run, pm.Player, specOrWhy, 1)
				else
					notify(pm.Player, tostring(specOrWhy), "bad", 4)
					dropped[#dropped + 1] = pm.Player
				end
			end
		end
	end
	for _, p in ipairs(dropped) do
		local uid = p.UserId
		if uid ~= leader.UserId then
			dropPartyMember(party, uid)
			St.partyOf[p] = nil
			notify(p, "You were dropped from the party", "bad", 4)
		end
	end
	if #run.Order == 0 or not run.Members[leader.UserId] then
		St.pocketBusy[index] = nil
		-- the leader could not enter: the party stays, nothing starts
		if #run.Order > 0 then
			for _, uid in ipairs(run.Order) do
				run.Members[uid] = nil
			end
		end
		markLobbyDirty()
		return false, "The leader could not enter"
	end
	local okB, pocket, whyB = pcall(St.deps.DungeonBuilder.BuildRun, index, floorIndex, run.Seed)
	if not okB or type(pocket) ~= "table" then
		St.pocketBusy[index] = nil
		warn("[DungeonService] BuildRun failed: " .. tostring(okB and whyB or pocket))
		notify(leader, "The dungeon could not open, try again", "bad", 4)
		return false, "The dungeon could not open"
	end
	run.Pocket = pocket
	run.Name = pocket.Name or ("Floor " .. tostring(floorIndex))
	run.Element = pocket.Element or "Earth"
	-- InBattle = the run id BEFORE the teleport (followers parked, portals / GoHome / obby refused)
	for _, uid in ipairs(run.Order) do
		bindMember(run, run.Members[uid].Player)
	end
	local hall = pocket.Hall
	for i, uid in ipairs(run.Order) do
		local cf = hall and hall.Spawns and hall.Spawns[((i - 1) % 4) + 1] or CFrame.new(pocket.Origin + Vector3.new(0, 4, 0))
		teleport(run.Members[uid].Player, cf)
	end
	party.Run = run
	St.runs[run.Id] = run
	St.runOrder[#St.runOrder + 1] = run.Id
	run.State = "Hall"
	run.StateAt = now()
	sendRun(run)
	markLobbyDirty()
	return true, run.Id
end

-- a late joiner enters the run in its Hall / Corridor (earlier rooms pay nothing: JoinedRoom = the next fight room)
function Dg.lateJoin(run, player)
	if run.State == "Ending" or not run.Joinable then
		return false, "That run is closed"
	end
	-- a member who LEFT keeps their record (Left, loot, Runs + 1): a second record would list them twice in run.Order and
	-- the next OpenEncounter refuses the whole party ("DuplicatePlayer")
	if run.Members[player.UserId] then
		return false, "You left this run"
	end
	if countLive(run) >= K.MAX_PARTY then
		return false, "That party is full"
	end
	local ok, spec = canEnter(player, run.Floor, false, true)
	if not ok then
		return false, spec
	end
	local joinedRoom = (run.State == "Hall") and 1 or (run.Room + ((run.Phase == "Threshold") and 0 or 1))
	local member = newMember(run, player, spec, max(1, joinedRoom))
	bindMember(run, player)
	local target
	if run.State == "Hall" then
		local hall = run.Pocket.Hall
		target = hall and hall.Spawns and hall.Spawns[((#run.Order - 1) % 4) + 1]
	else
		local info = roomInfo(run, run.Room)
		target = info and info.Entrance
		if run.Phase == "Walk" then
			local cleared = roomInfo(run, run.Room)
			target = cleared and cleared.Entrance or target
		end
	end
	teleport(player, target or CFrame.new(run.Pocket.Origin + Vector3.new(0, 4, 0)))
	member.Joined = now()
	sendRun(run)
	markLobbyDirty()
	return true, run.Id
end

-- Dg.enterRoom(run, room): room + 1 (and its corridor) built now, room - 1 destroyed, members placed at the Entrance
function Dg.enterRoom(run, room)
	if run.State == "Ending" then
		return
	end
	local pocket = run.Pocket
	local DB = St.deps.DungeonBuilder
	if room >= 5 then
		return Dg.enterTreasure(run)
	end
	local info = DB.PlaceRoom(pocket, room)
	if not info then
		return Dg.endRun(run, false, "Error")
	end
	pcall(DB.PlaceRoom, pocket, room + 1)
	if room - 1 >= 1 then
		pcall(DB.RemoveRoom, pocket, room - 1)
	end
	run.Room = room
	run.Wave = 0
	run.Waves = wavesOf(run, room)
	run.State = "Corridor"
	run.Phase = "Threshold"
	run.StateAt = now()
	run.DoorOpened = nil
	run.Joinable = room <= num(D().LateJoinLastRoom, 2) and countLive(run) < K.MAX_PARTY
	DB.SetDoor(info, "Entrance", true)
	for i, m in ipairs(liveMembers(run)) do
		m.Downed = false
		local cf = info.Entrance * CFrame.new(((i - 1) % 4) * 2.4 - 3.6, 0, 0)
		teleport(m.Player, cf)
	end
	sendRun(run)
	markLobbyDirty()
end

-- the treasure alcove after the boss: chests closed per member, the exit after TreasureSeconds
function Dg.enterTreasure(run)
	if run.State == "Ending" then
		return
	end
	local pocket = run.Pocket
	local DB = St.deps.DungeonBuilder
	local info = DB.PlaceRoom(pocket, 5)
	if not info then
		return Dg.endRun(run, false, "Error")
	end
	run.Room = 4
	run.State = "Treasure"
	run.Phase = nil
	run.StateAt = now()
	run.Joinable = false
	-- one chest per member who qualified in at least one room (5.2: loot goes to QUALIFYING members; Y4: an AFK alt
	-- carried through the floor earns nothing, so no chest either)
	for _, m in ipairs(liveMembers(run)) do
		local uid = m.Player.UserId
		if run.Chests[uid] == nil and qualifiedAnywhere(m) then
			run.Chests[uid] = "Closed"
		end
	end
	if info then
		for i, m in ipairs(liveMembers(run)) do
			local cf = info.Spawns and info.Spawns[((i - 1) % 4) + 1] or info.Entrance
			teleport(m.Player, cf)
		end
	end
	sendRun(run)
	markLobbyDirty()
end

----------------------------------------------------------------------
-- Moving on: the door prompt, the per-member E, the fade, the next room (dungeon-fixes decision 2)
----------------------------------------------------------------------
-- the door the group walks to now -> prompt, targetRoom (5 = the treasure) | nil (fighting, bars still shut, a
-- transit running, the run over)
function Dg.nextDoor(run)
	if run.Transit or not run.Pocket then
		return nil
	end
	if run.State == "Hall" then
		local hall = run.Pocket.Hall
		local prompt = hall and hall.NextPrompt
		return prompt and prompt.Parent and prompt or nil, 1
	end
	if run.State == "Corridor" and run.Phase == "Walk" and run.DoorOpened then
		local prompt
		if run.Room >= 4 then
			local info = roomInfo(run, 4)
			prompt = info and info.NextPrompt
			if prompt and prompt.Parent then
				return prompt, 5
			end
			return nil
		end
		local info = roomInfo(run, run.Room + 1)
		prompt = info and info.EnterPrompt
		if prompt and prompt.Parent then
			return prompt, run.Room + 1
		end
	end
	return nil
end

-- exactly the current door's prompt is enabled (sendRun calls this at every state change)
function Dg.syncPrompt(run)
	local prompt = (run.State ~= "Ending") and Dg.nextDoor(run) or nil
	local old = run.ActivePrompt
	if old and old ~= prompt then
		pcall(function()
			old.Enabled = false
		end)
	end
	run.ActivePrompt = prompt
	if prompt and prompt.Enabled ~= true then
		pcall(function()
			prompt.Enabled = true
		end)
	end
end

-- Dg.confirm(run, player, prompt) -> ok, why: one member's E at the open door (idempotent)
function Dg.confirm(run, player, prompt)
	if run.Transit then
		return false, "Transit"
	end
	if run.State ~= "Hall" and run.State ~= "Corridor" then
		return false, "State"
	end
	local uid = player.UserId
	local m = run.Members[uid]
	if not m or m.Left then
		return false, "NotMember"
	end
	local door, target = Dg.nextDoor(run)
	if not door or door ~= prompt then
		return false, "NotNow"
	end
	local part = prompt.Parent
	local root = rootOf(player)
	if not root or typeof(part) ~= "Instance" or not part:IsA("BasePart") or (root.Position - part.Position).Magnitude > K.CONFIRM_RANGE then
		return false, "Far"
	end
	if run.ConfirmFor ~= target then
		run.Confirm = {}
		run.ConfirmFor = target
	end
	if run.Confirm[uid] then
		return true, "Already"
	end
	run.Confirm[uid] = true
	if not Dg.checkConfirm(run) then
		sendRun(run)
	end
	return true
end

-- every member still in the run (not Left; Downed ones too) pressed E -> the transit (true when it began)
function Dg.checkConfirm(run)
	if run.Transit or run.State == "Ending" then
		return false
	end
	local door, target = Dg.nextDoor(run)
	if not door or run.ConfirmFor ~= target then
		return false
	end
	local live = liveMembers(run)
	if #live == 0 then
		return false
	end
	for _, m in ipairs(live) do
		if not run.Confirm[m.Player.UserId] then
			return false
		end
	end
	return Dg.transit(run, target)
end

-- the lock, the fade to every member, the next room after FADE.Out (once: TransitSeq + the state it left from)
function Dg.transit(run, target)
	if run.Transit then
		return false
	end
	run.Transit = true
	run.TransitSeq = (run.TransitSeq or 0) + 1
	local seq = run.TransitSeq
	local from = tostring(run.State) .. ":" .. tostring(run.Room)
	local fade = { Out = FADE.Out, Hold = FADE.Hold, In = FADE.In, Room = target }
	for _, m in ipairs(liveMembers(run)) do
		sendState(m.Player, "Fade", fade)
	end
	sendRun(run)
	task.delay(FADE.Out, function()
		local ok, err = pcall(Dg.finishTransit, run, seq, target, from)
		if not ok then
			warn("[DungeonService] the room change failed: " .. tostring(err))
			pcall(Dg.endRun, run, false, "Error")
		end
	end)
	return true
end

function Dg.finishTransit(run, seq, target, from)
	if not run.Transit or run.TransitSeq ~= seq then
		return false
	end
	run.Transit = nil
	run.Confirm = {}
	run.ConfirmFor = nil
	if run.State == "Ending" or (tostring(run.State) .. ":" .. tostring(run.Room)) ~= from then
		sendRun(run)
		return false
	end
	if countLive(run) == 0 then
		return false
	end
	if target >= 5 then
		local info = roomInfo(run, 4)
		if info then
			St.deps.DungeonBuilder.SetDoor(info, "Exit", true)
		end
		Dg.enterTreasure(run)
	else
		Dg.enterRoom(run, target)
	end
	return true
end

local function spawnWave(run, wave)
	local BC = catalog()
	local BS = St.deps.BattleService
	if not BC or not run.Battle then
		return false
	end
	local n = countLive(run)
	local okW, plan = pcall(BC.DungeonWave, run.Floor, run.Room, wave, n, run.Seed)
	if not okW or type(plan) ~= "table" or type(plan.Pets) ~= "table" or #plan.Pets == 0 then
		warn("[DungeonService] DungeonWave failed: " .. tostring(plan))
		return false
	end
	-- the room's spawn point when its template names one (the Throne: at the foot of the dais, not on the throne)
	local info = roomInfo(run, run.Room)
	local anchor = info and type(info.SpawnAnchor) == "table" and info.SpawnAnchor or nil
	local infos, why = BS.SpawnWave(run.Battle, plan.Pets, { Wave = wave, Name = plan.Name or ("Wave " .. tostring(wave)), Anchor = anchor })
	if not infos then
		warn("[DungeonService] SpawnWave refused: " .. tostring(why))
		return false
	end
	run.Wave = wave
	return true
end

-- Dg.startFight(run): the encounter of the current room
function Dg.startFight(run)
	if run.State ~= "Corridor" or run.Phase ~= "Threshold" then
		return false
	end
	local BS = St.deps.BattleService
	local room = run.Room
	local info = roomInfo(run, room)
	if not info or not info.Zone then
		return Dg.endRun(run, false, "Error")
	end
	local teams = {}
	for i, m in ipairs(liveMembers(run)) do
		local spec = try(BS, "TeamSpec", m.Player, m.Keys)
		if type(spec) ~= "table" then
			spec = m.Spec
		end
		m.Spec = spec
		m.Downed = false
		teams[#teams + 1] = { Player = m.Player, Spec = spec }
		teleport(m.Player, info.Entrance * CFrame.new(((i - 1) % 4) * 2.4 - 3.6, 0, 0))
	end
	if #teams == 0 then
		return Dg.endRun(run, false, "Abandoned")
	end
	local d = D()
	local timeLimit = (run.Floor == 1) and num(d.Floor1RoomTime, 180) or num(d.RoomTime, 120)
	local waves = wavesOf(run, room)
	-- the encounter's centre is the room's FLOOR (RoomInfo.ZoneFloor; the zone part floats 6 studs above it and stays
	-- the presence box); a builder without ZoneFloor: the part's centre moved down to the floor top (FloorY)
	local floorCf = info.ZoneFloor
	if typeof(floorCf) ~= "CFrame" then
		local fy = info.Zone:GetAttribute("FloorY")
		floorCf = info.Zone.CFrame * CFrame.new(0, (finite(fy) and fy or (info.Zone.Position.Y - 6)) - info.Zone.Position.Y, 0)
	end
	local id, why = BS.OpenEncounter({
		Mode = "Dungeon",
		Zone = { CFrame = floorCf, Size = info.Zone.Size, Part = info.Zone },
		Seed = run.Seed + room * 17,
		TimeLimit = timeLimit,
		Label = run.Name .. " room " .. tostring(room),
		Teams = teams,
		Extra = { Floor = run.Floor, Room = room, Wave = 1, Waves = waves, Name = run.Name, Element = run.Element, Boss = room == 4, RunId = run.Id },
		KeepInBattle = true,
		OnEnd = function(battleId, result)
			Dg.onRoomEnd(run, result, battleId)
		end,
		OnWave = function(battleId, waveIndex)
			Dg.onWave(run, waveIndex, battleId)
		end,
		OnBossHp = function(battleId, frac)
			Dg.onBossHp(run, frac, battleId)
		end,
		OnDown = function(battleId, player, livesLeft)
			Dg.onDown(run, player, livesLeft, battleId)
		end,
		OnLeave = function(battleId, player, leaveWhy)
			Dg.onLeave(run, player, leaveWhy, battleId)
		end,
	})
	if not id then
		warn("[DungeonService] OpenEncounter refused: " .. tostring(why))
		for _, m in ipairs(liveMembers(run)) do
			notify(m.Player, "The fight could not start: " .. tostring(why), "bad", 4)
		end
		return Dg.endRun(run, false, "Error")
	end
	run.Battle = id
	run.LastBattle = id
	St.runByBattle[id] = run
	run.State = "Fight"
	run.Phase = nil
	run.StateAt = now()
	run.FightAt = now()
	run.Waves = waves
	run.Wave = 1
	run.EscortSpawned = false
	run.BattleMissingSince = nil
	run.Joinable = false
	St.deps.DungeonBuilder.SetDoor(info, "Entrance", false)
	if not spawnWave(run, 1) then
		return Dg.endRun(run, false, "Error")
	end
	sendRun(run)
	markLobbyDirty()
	return true
end

function Dg.onWave(run, waveIndex, battleId)
	if run.State ~= "Fight" then
		return
	end
	if battleId and run.Battle ~= battleId then
		return
	end
	local BS = St.deps.BattleService
	-- BattleSim fires EnemiesDown per wave TEAM: the room is cleared only when no enemy at all is left (the boss room:
	-- boss AND escort down, 5.4; whichever falls last fires the EnemiesDown that clears)
	local status = try(BS, "EncounterStatus", run.Battle)
	local enemiesLeft = type(status) == "table" and tonumber(status.Enemies) or 0
	if run.Room == 4 then
		if not run.EscortSpawned then
			Dg.spawnEscort(run)
			return
		end
		if enemiesLeft > 0 then
			return
		end
		BS.FinishEncounter(run.Battle, "Cleared")
		return
	end
	if waveIndex < run.Waves then
		local id = run.Battle
		task.delay(K.NEXT_WAVE, function()
			if run.State == "Fight" and run.Battle == id then
				if spawnWave(run, waveIndex + 1) then
					sendRun(run)
				else
					BS.FinishEncounter(id, "Cleared")
				end
			end
		end)
	elseif enemiesLeft == 0 then
		BS.FinishEncounter(run.Battle, "Cleared")
	end
end

function Dg.spawnEscort(run)
	if run.State ~= "Fight" or run.EscortSpawned or run.Room ~= 4 then
		return
	end
	run.EscortSpawned = true
	if spawnWave(run, 2) then
		sendRun(run)
	end
end

function Dg.onBossHp(run, frac, battleId)
	if run.State ~= "Fight" then
		return
	end
	if battleId and run.Battle ~= battleId then
		return
	end
	if run.Room == 4 and finite(frac) and frac <= num(D().EscortAt, 0.5) then
		Dg.spawnEscort(run)
	end
end

function Dg.onDown(run, player, livesLeft, battleId)
	if run.State ~= "Fight" then
		return
	end
	if battleId and run.Battle ~= battleId then
		return
	end
	local m = isPlayer(player) and run.Members[player.UserId] or nil
	if m and not m.Left then
		m.Downed = true
		sendRun(run)
	end
end

function Dg.onLeave(run, player, why, battleId)
	if run.State ~= "Fight" then
		return
	end
	if battleId and run.Battle ~= battleId then
		return
	end
	Dg.removeMember(run, player, why or "Left")
end

-- the loot of a cleared room: once per room per qualifying fighter (result.Fighters), marked before paying
function Dg.payRoom(run, room, result)
	local BC = catalog()
	local DS, PC, TS, BS = St.deps.DataService, St.deps.PetCareService, St.deps.TycoonService, St.deps.BattleService
	if not BC then
		return
	end
	run.Paid[room] = run.Paid[room] or {}
	local paid = run.Paid[room]
	local waves = (room == 4) and num(D().BossRoomWaves, 4) or run.Waves
	local double = try(BS, "IsDoubleRewards") == true
	for _, uid in ipairs(type(result.Fighters) == "table" and result.Fighters or {}) do
		local m = run.Members[uid]
		if m and not m.Left and (m.JoinedRoom or 1) <= room and not paid[uid] then
			paid[uid] = true
			m.Qualified[room] = true
			local income = try(TS, "IncomePerSecond", m.Player) or 0
			local okR, rewards = pcall(BC.DungeonRewards, run.Floor, room, waves, income, double)
			if okR and type(rewards) == "table" then
				local loot = lootOf(run, uid)
				local cash, tokens, xp = floor(num(rewards.Cash, 0)), floor(num(rewards.Tokens, 0)), floor(num(rewards.Xp, 0))
				if cash > 0 then
					try(DS, "AddCash", m.Player, cash)
				end
				if tokens > 0 then
					try(DS, "AddTokens", m.Player, tokens)
				end
				local levelUps = 0
				if xp > 0 then
					for _, key in ipairs(m.Keys) do
						local _, levels = try(PC, "GrantXp", m.Player, key, xp, "Dungeon")
						levelUps = levelUps + (tonumber(levels) or 0)
					end
				end
				loot.Cash = loot.Cash + cash
				loot.Tokens = loot.Tokens + tokens
				loot.Xp = loot.Xp + xp
				sendState(m.Player, "Loot", { Room = room, Cash = cash, Tokens = tokens, Xp = xp, LevelUps = levelUps })
			end
		end
	end
end

-- the loss third of the room that ends a run (RealLoss: >= 20 s or >= 20% damage; never Quit / leave / disconnect / shutdown)
function Dg.payLoss(run, room, result)
	local BC = catalog()
	if not BC or type(result) ~= "table" then
		return
	end
	local dealt = 0
	if type(result.Hp) == "table" and finite(result.Hp[2]) then
		dealt = max(0, min(1, 1 - result.Hp[2]))
	end
	local okL, real = pcall(BC.RealLoss, num(result.Duration, 0), dealt)
	if not okL or not real then
		return
	end
	run.Paid[room] = run.Paid[room] or {}
	local paid = run.Paid[room]
	local waves = (room == 4) and num(D().BossRoomWaves, 4) or run.Waves
	local PC, TS = St.deps.PetCareService, St.deps.TycoonService
	for _, uid in ipairs(type(result.Fighters) == "table" and result.Fighters or {}) do
		local m = run.Members[uid]
		if m and not m.Left and (m.JoinedRoom or 1) <= room and not paid[uid] then
			paid[uid] = true
			local income = try(TS, "IncomePerSecond", m.Player) or 0
			local okR, rewards = pcall(BC.DungeonRewards, run.Floor, room, waves, income, false)
			local xp = okR and type(rewards) == "table" and floor(num(rewards.Xp, 0) / 3 + 0.5) or 0
			if xp > 0 then
				for _, key in ipairs(m.Keys) do
					try(PC, "GrantXp", m.Player, key, xp, "Dungeon")
				end
				lootOf(run, uid).Xp = lootOf(run, uid).Xp + xp
				sendState(m.Player, "Loot", { Room = room, Cash = 0, Tokens = 0, Xp = xp, LevelUps = 0, Loss = true })
			end
		end
	end
end

-- the floor cleared: Best / Cleared / Clears inside MutateDungeon (first clears paid when it says so), chests, the board
function Dg.clearFloor(run)
	local BC = catalog()
	local DS = St.deps.DataService
	local floorIndex = run.Floor
	run.Cleared = true
	for _, m in ipairs(liveMembers(run)) do
		local qualifies = m.Qualified[4] == true and (m.Qualified[1] or m.Qualified[2] or m.Qualified[3]) == true
		local before = record(m.Player)
		local ok, first
		if qualifies then
			ok, first = try(DS, "MutateDungeon", m.Player, function(rec)
				rec.Best = max(tonumber(rec.Best) or 0, floorIndex)
				rec.Cleared = type(rec.Cleared) == "table" and rec.Cleared or {}
				rec.Cleared[floorIndex] = true
				rec.Clears = (tonumber(rec.Clears) or 0) + 1
			end)
			m.ClearedFloor = true
			m.Qualified.Floor = true
		else
			ok = try(DS, "MutateDungeon", m.Player, function(rec)
				rec.Best = max(tonumber(rec.Best) or 0, floorIndex)
			end)
		end
		m.NewBest = (tonumber(before.Best) or 0) < floorIndex
		m.Unlocked = (floorIndex < 12) and (floorIndex + 1) or nil
		if ok and first == true and qualifies and BC then
			local okF, reward = pcall(BC.DungeonFirstClear, floorIndex)
			if okF and type(reward) == "table" then
				local tokens, gems = floor(num(reward.Tokens, 0)), floor(num(reward.Gems, 0))
				if tokens > 0 then
					try(DS, "AddTokens", m.Player, tokens)
				end
				if gems > 0 then
					try(DS, "AddGems", m.Player, gems)
				end
				local loot = lootOf(run, m.Player.UserId)
				loot.Tokens = loot.Tokens + tokens
				loot.Gems = loot.Gems + gems
				m.FirstClear = { Tokens = tokens, Gems = gems }
				notify(m.Player, "First clear of floor " .. tostring(floorIndex) .. "! +" .. tostring(tokens) .. " tokens, +" .. tostring(gems) .. " gems", "good", 5)
			end
		end
		if qualifies then
			local name = m.Player.Name
			if (St.board[name] or 0) < floorIndex then
				St.board[name] = floorIndex
			end
			pcall(DungeonService.FloorCleared.Fire, DungeonService.FloorCleared, m.Player, floorIndex)
		end
	end
	updateBoard()
end

-- Dg.onRoomEnd(run, result): Cleared -> loot + the bars; Wipe / Timeout -> the loss third and the end of the run
function Dg.onRoomEnd(run, result, battleId)
	if run.State ~= "Fight" then
		return
	end
	if battleId and run.Battle ~= battleId then
		return
	end
	result = type(result) == "table" and result or { Reason = "Error" }
	local room = run.Room
	local id = run.Battle
	run.Battle = nil
	if id then
		St.runByBattle[id] = nil
	end
	local reason = tostring(result.Reason or "Error")
	if reason == "Cleared" then
		Dg.payRoom(run, room, result)
		if room == 4 then
			Dg.clearFloor(run)
		end
		run.State = "Corridor"
		run.Phase = "Walk"
		run.StateAt = now()
		run.DoorOpened = false
		run.Joinable = room <= num(D().LateJoinLastRoom, 2) and countLive(run) < K.MAX_PARTY
		sendRun(run)
		markLobbyDirty()
	elseif reason == "Wipe" or reason == "Timeout" then
		Dg.payLoss(run, room, result)
		for _, m in ipairs(liveMembers(run)) do
			notify(m.Player, "Floor " .. tostring(run.Floor) .. ": the " .. tostring(run.Name) .. " got you in room " .. tostring(room) .. ". Train your team and try again!", "bad", 6)
		end
		Dg.endRun(run, false, reason)
	elseif reason == "Abandoned" then
		if countLive(run) > 0 then
			Dg.endRun(run, false, "Abandoned")
		end
	else
		Dg.endRun(run, false, reason)
	end
end

-- Dg.removeMember(run, player, why): that member only (Quit / Left / Leash / Disconnect / Kick); the last one out ends the run
function Dg.removeMember(run, player, why)
	local uid = isPlayer(player) and player.UserId or (type(player) == "number" and player) or nil
	local m = uid and run.Members[uid] or nil
	if not m or m.Left then
		return false
	end
	m.Left = true
	m.LeftWhy = why
	local BS = St.deps.BattleService
	if run.State == "Fight" and run.Battle then
		pcall(BS.RemoveEncounterTeam, run.Battle, m.Player)
	end
	if run.State == "Treasure" and run.Chests[uid] == "Closed" then
		pcall(Dg.openChest, run, m, nil, true)
	end
	pcall(function()
		try(St.deps.DataService, "MutateDungeon", m.Player, function(rec)
			rec.Runs = (tonumber(rec.Runs) or 0) + 1
		end)
	end)
	if run.State ~= "Ending" then
		sendState(m.Player, "End", endPayload(run, m, why))
	end
	unbindMember(run, m.Player)
	local party = run.Party
	if party then
		dropPartyMember(party, uid)
		-- the leader out while others fight on: the party record is re-keyed to the first live member, so the run stays
		-- listed / joinable under its new leader and the old leader may open or join another party at once
		if party.Leader == m.Player and run.State ~= "Ending" then
			local heir = nil
			for _, ouid in ipairs(run.Order) do
				local om = run.Members[ouid]
				if om and not om.Left and isPlayer(om.Player) then
					heir = om.Player
					break
				end
			end
			if heir and St.parties[uid] == party then
				St.parties[uid] = nil
				St.parties[heir.UserId] = party
				for i, id in ipairs(St.partyOrder) do
					if id == uid then
						St.partyOrder[i] = heir.UserId
					end
				end
				party.Leader = heir
				if not party.Members[heir.UserId] then
					local spec = try(St.deps.BattleService, "TeamSpec", heir)
					party.Members[heir.UserId] = { Player = heir, Ready = true, Keys = keysOf(spec), Power = powerOf(spec) }
					party.Order[#party.Order + 1] = heir.UserId
				end
				St.partyOf[heir] = party
			end
		end
	end
	if St.partyOf[m.Player] == party then
		St.partyOf[m.Player] = nil
	end
	if why ~= "Disconnect" and why ~= "Left" and isPlayer(m.Player) then
		returnHome(m.Player)
	end
	if run.State ~= "Ending" then
		run.Joinable = run.Joinable and countLive(run) < K.MAX_PARTY
		sendRun(run)
		markLobbyDirty()
		if countLive(run) == 0 then
			Dg.endRun(run, false, why == "Disconnect" and "Disconnect" or "Abandoned")
		else
			-- the others may all have pressed E at the door already: the leaver no longer holds them up
			Dg.checkConfirm(run)
		end
	end
	return true
end

-- the alcove's chest parts by slot ({} when the treasure room is not built)
local function chestParts(run)
	local info = roomInfo(run, 5)
	return info and type(info.Chests) == "table" and info.Chests or {}
end

-- the first chest nobody took (a built one first); past CHEST_SLOTS only if every chest is gone (never with
-- MAX_PARTY <= CHEST_SLOTS, but a member is never left without their drop)
function Dg.freeChest(run)
	local parts = chestParts(run)
	for slot = 1, K.CHEST_SLOTS do
		if not run.ChestTaken[slot] and parts[slot] and parts[slot].Parent then
			return slot
		end
	end
	local slot = 1
	while run.ChestTaken[slot] do
		slot = slot + 1
	end
	return slot
end

-- the picked chest: Opened / OpenedBy on the part, its prompt off for everyone, a warm glow and a burst of sparks (the
-- Blender chest is one closed mesh: an open-lid mesh is wanted, wave 3 art)
function Dg.markChest(run, slot, m)
	local part = chestParts(run)[slot]
	if not part or not part.Parent then
		return false
	end
	pcall(function()
		part:SetAttribute("Opened", true)
		part:SetAttribute("OpenedBy", m.Player.UserId)
		part:SetAttribute("OpenedByName", shortName(m.Player))
		local prompt = part:FindFirstChild("ChestPrompt")
		if prompt then
			prompt.Enabled = false
		end
		if not part:FindFirstChild("OpenGlow") then
			local glow = Instance.new("PointLight")
			glow.Name = "OpenGlow"
			glow.Color = Color3.fromRGB(255, 196, 80)
			glow.Brightness = 2
			glow.Range = 9
			glow.Shadows = false
			glow.Parent = part
			local burst = Instance.new("ParticleEmitter")
			burst.Name = "OpenBurst"
			burst.Color = ColorSequence.new(Color3.fromRGB(255, 214, 90))
			burst.LightEmission = 0.8
			burst.Rate = 0
			burst.Lifetime = NumberRange.new(0.6, 1.1)
			burst.Speed = NumberRange.new(6, 10)
			burst.SpreadAngle = Vector2.new(35, 35)
			burst.Size = NumberSequence.new(0.35, 0)
			burst.EmissionDirection = Enum.NormalId.Top
			burst.Parent = part
			burst:Emit(24)
		end
	end)
	return true
end

-- a member's boss chest (bug batch 2, #14): the member picks ONE of the alcove's chests; each chest is its own roll
-- (run seed + slot), paid once (the marks are written first). auto = the 45 s exit / a member leaving: the first free
-- chest, no range check.
function Dg.openChest(run, m, slot, auto)
	local uid = m.Player.UserId
	if run.Chests[uid] ~= "Closed" then
		return false, "No chest"
	end
	run.ChestTaken = run.ChestTaken or {}
	if auto then
		slot = Dg.freeChest(run)
	else
		if not finite(slot) or slot ~= floor(slot) or slot < 1 or slot > K.CHEST_SLOTS then
			return false, "Pick a chest: walk to one and press E"
		end
		local part = chestParts(run)[slot]
		if not part or not part.Parent then
			return false, "That chest is not here"
		end
		if run.ChestTaken[slot] then
			return false, "That chest is taken, pick another one"
		end
		local root = rootOf(m.Player)
		if not root or (root.Position - part.Position).Magnitude > K.CHEST_RANGE then
			return false, "Walk to the chest first"
		end
	end
	run.Chests[uid] = "Opened"
	run.ChestTaken[slot] = uid
	m.ChestSlot = slot
	Dg.markChest(run, slot, m)
	local BC = catalog()
	local DS, TS = St.deps.DataService, St.deps.TycoonService
	if not BC then
		return false
	end
	local okC, chest = pcall(BC.DungeonChest, run.Floor, run.Seed + slot * 7919)
	if not okC or type(chest) ~= "table" then
		return false
	end
	local loot = lootOf(run, uid)
	local amount = floor(num(chest.Amount, 0))
	if chest.Kind == "Cash" then
		local income = try(TS, "IncomePerSecond", m.Player) or 0
		amount = max(amount, floor(income * num(chest.Seconds, 30)))
		if amount > 0 then
			try(DS, "AddCash", m.Player, amount)
		end
		loot.Cash = loot.Cash + amount
	elseif chest.Kind == "Tokens" then
		if amount > 0 then
			try(DS, "AddTokens", m.Player, amount)
		end
		loot.Tokens = loot.Tokens + amount
	elseif chest.Kind == "Gems" then
		if amount > 0 then
			try(DS, "AddGems", m.Player, amount)
		end
		loot.Gems = loot.Gems + amount
	end
	m.Chest = { Kind = chest.Kind, Amount = amount, Slot = slot }
	sendState(m.Player, "Chest", { Kind = chest.Kind, Amount = amount, Slot = slot })
	if not auto and run.State == "Treasure" then
		-- the others' cards: who still has a chest to pick
		sendRun(run)
	end
	return true, m.Chest
end

local function finishRun(run)
	if run.Finished then
		return
	end
	run.Finished = true
	for _, uid in ipairs(run.Order) do
		local m = run.Members[uid]
		if m then
			pcall(function()
				if not m.Left and isPlayer(m.Player) and run.EndReason ~= "Shutdown" then
					returnHome(m.Player)
				end
			end)
			pcall(unbindMember, run, m.Player)
			pcall(function()
				-- a member who left earlier may already lead or sit in ANOTHER party: only this run's party link goes
				if St.partyOf[m.Player] == run.Party then
					St.partyOf[m.Player] = nil
				end
			end)
		end
	end
	pcall(function()
		St.deps.DungeonBuilder.FreeRun(run.PocketIndex)
	end)
	St.pocketBusy[run.PocketIndex] = nil
	St.runs[run.Id] = nil
	for i, id in ipairs(St.runOrder) do
		if id == run.Id then
			table.remove(St.runOrder, i)
			break
		end
	end
	if run.LastBattle then
		St.runByBattle[run.LastBattle] = nil
	end
	local party = run.Party
	if party and St.parties[party.Leader.UserId] == party then
		St.parties[party.Leader.UserId] = nil
		for i, id in ipairs(St.partyOrder) do
			if id == party.Leader.UserId then
				table.remove(St.partyOrder, i)
				break
			end
		end
		for _, uid in ipairs(party.Order) do
			local pm = party.Members[uid]
			if pm then
				St.partyOf[pm.Player] = nil
			end
		end
	end
	if not run.Fired then
		run.Fired = true
		local members, winners = {}, {}
		for _, uid in ipairs(run.Order) do
			members[#members + 1] = uid
			local m = run.Members[uid]
			if m and m.ClearedFloor then
				winners[#winners + 1] = uid
			end
		end
		pcall(DungeonService.RunEnded.Fire, DungeonService.RunEnded, run.Id, { Floor = run.Floor, Cleared = run.Cleared == true, Members = members, Winners = winners, Loot = run.Loot, Reason = run.EndReason })
	end
	markLobbyDirty()
end

-- Dg.endRun(run, cleared, reason, immediate): idempotent; every step in its own pcall; ALWAYS releases the members, the
-- pocket and fires RunEnded once
function Dg.endRun(run, cleared, reason, immediate)
	if run.State == "Ending" then
		return false
	end
	-- a run killed at the Treasure (the watchdog): the chests already earned open for their owners first (same mark,
	-- once); a Shutdown stays void
	if run.State == "Treasure" and reason ~= "Shutdown" then
		for _, m in ipairs(liveMembers(run)) do
			if run.Chests[m.Player.UserId] == "Closed" then
				pcall(Dg.openChest, run, m, nil, true)
			end
		end
	end
	run.State = "Ending"
	run.Phase = nil
	run.Joinable = false
	run.Transit = nil
	pcall(Dg.syncPrompt, run)
	run.EndReason = reason or (cleared and "Cleared" or "Ended")
	if cleared then
		run.Cleared = true
	end
	run.EndedAt = now()
	-- 1. the encounter, if one still runs (its OnEnd returns at once: the state is Ending)
	pcall(function()
		local id = run.Battle
		run.Battle = nil
		if id then
			St.runByBattle[id] = nil
			St.deps.BattleService.FinishEncounter(id, reason == "Shutdown" and "Shutdown" or "Abandoned")
		end
	end)
	-- 2. Runs + 1 and the End card for everyone still in
	for _, m in ipairs(liveMembers(run)) do
		pcall(function()
			try(St.deps.DataService, "MutateDungeon", m.Player, function(rec)
				rec.Runs = (tonumber(rec.Runs) or 0) + 1
			end)
		end)
		pcall(function()
			sendState(m.Player, "End", endPayload(run, m, run.EndReason))
		end)
	end
	-- 3. the return after RETURN_DELAY (now on a shutdown or when nobody is left), then the release + RunEnded
	if immediate or countLive(run) == 0 or St.closing then
		pcall(finishRun, run)
	else
		task.delay(K.RETURN_DELAY, function()
			pcall(finishRun, run)
		end)
	end
	return true
end

----------------------------------------------------------------------
-- Parties
----------------------------------------------------------------------
local function partyOfLeader(leaderUserId)
	return St.parties[leaderUserId]
end

local function removeParty(party)
	St.parties[party.Leader.UserId] = nil
	for i, id in ipairs(St.partyOrder) do
		if id == party.Leader.UserId then
			table.remove(St.partyOrder, i)
			break
		end
	end
	for _, uid in ipairs(party.Order) do
		local pm = party.Members[uid]
		if pm and St.partyOf[pm.Player] == party then
			St.partyOf[pm.Player] = nil
		end
	end
	markLobbyDirty()
end

function DungeonService.CreateParty(player, floorIndex)
	if not isPlayer(player) then
		return false, "That player is not here"
	end
	floorIndex = whole(tonumber(floorIndex), 1, 12)
	if not floorIndex then
		return false, "Pick a floor"
	end
	if St.runOf[player] then
		return false, "Finish your dungeon run first"
	end
	if St.partyOf[player] then
		return false, "You are already in a party"
	end
	-- (safety net: the key is re-assigned to a live member when a leader leaves a run, so this never holds a running
	-- party; it is never overwritten while a run uses it)
	local old = St.parties[player.UserId]
	if old and old.Run and old.Run.State ~= "Ending" and not old.Run.Finished then
		return false, "Your old party is still in the dungeon"
	end
	if St.joinQueue[player] then
		St.joinQueue[player] = nil
	end
	local ok, why = profileReady(player)
	if not ok then
		return false, why
	end
	local rec = record(player)
	if (tonumber(rec.Best) or 0) < floorIndex - 1 then
		return false, "Clear floor " .. tostring(floorIndex - 1) .. " first"
	end
	local spec = try(St.deps.BattleService, "TeamSpec", player)
	local party = {
		Leader = player,
		Floor = floorIndex,
		Members = {},
		Order = {},
		Created = now(),
		Run = nil,
		StartAt = nil,
	}
	party.Members[player.UserId] = { Player = player, Ready = true, Keys = keysOf(spec), Power = powerOf(spec) }
	party.Order[1] = player.UserId
	St.parties[player.UserId] = party
	local listed = false
	for _, id in ipairs(St.partyOrder) do
		if id == player.UserId then
			listed = true
		end
	end
	if not listed then
		St.partyOrder[#St.partyOrder + 1] = player.UserId
	end
	St.partyOf[player] = party
	markLobbyDirty()
	return true, party
end

function DungeonService.JoinParty(player, leaderUserId)
	if not isPlayer(player) then
		return false, "That player is not here"
	end
	leaderUserId = whole(tonumber(leaderUserId), 1)
	if not leaderUserId then
		return false, "That party is gone"
	end
	if St.runOf[player] then
		return false, "Finish your dungeon run first"
	end
	local party = partyOfLeader(leaderUserId)
	if not party then
		return false, "That party is gone"
	end
	if St.partyOf[player] == party then
		return false, "You are already in that party"
	end
	if St.partyOf[player] then
		return false, "Leave your party first"
	end
	local ok, why = profileReady(player)
	if not ok then
		return false, why
	end
	if not ownsPet(player) then
		return false, "You need a pet"
	end
	-- a new JOIN replaces a pending queued join (one queue entry per player)
	St.joinQueue[player] = nil
	local run = party.Run
	if run then
		if run.State == "Ending" then
			return false, "That run is over"
		end
		local lastRoom = num(D().LateJoinLastRoom, 2)
		if run.Room > lastRoom or (run.State ~= "Hall" and run.State ~= "Corridor" and run.State ~= "Fight") then
			return false, "That party is past room " .. tostring(lastRoom)
		end
		if run.Members[player.UserId] then
			return false, "You left this run"
		end
		if countLive(run) >= K.MAX_PARTY then
			return false, "That party is full"
		end
		if run.State == "Fight" or run.Transit then
			-- 5.3: a join during a fight of room 1 / 2 (or a room change) waits (<= JOIN_QUEUE) for the corridor;
			-- tickQueue enters them there
			St.joinQueue[player] = { Party = party, Deadline = now() + K.JOIN_QUEUE }
			notify(player, "Joining when the room is cleared", "info", 4)
			markLobbyDirty()
			return true, "Queued"
		end
		local okJ, whyJ = Dg.lateJoin(run, player)
		if not okJ then
			return false, whyJ
		end
		local spec = try(St.deps.BattleService, "TeamSpec", player)
		party.Members[player.UserId] = { Player = player, Ready = true, Keys = keysOf(spec), Power = powerOf(spec) }
		party.Order[#party.Order + 1] = player.UserId
		St.partyOf[player] = party
		markLobbyDirty()
		return true, run.Id
	end
	if partyCount(party) >= K.MAX_PARTY then
		return false, "That party is full"
	end
	local spec = try(St.deps.BattleService, "TeamSpec", player)
	party.Members[player.UserId] = { Player = player, Ready = false, Keys = keysOf(spec), Power = powerOf(spec) }
	party.Order[#party.Order + 1] = player.UserId
	St.partyOf[player] = party
	notify(party.Leader, shortName(player) .. " joined your party", "info", 3)
	markLobbyDirty()
	return true, party
end

function DungeonService.LeaveParty(player)
	if St.joinQueue[player] then
		St.joinQueue[player] = nil
		markLobbyDirty()
		return true
	end
	local party = St.partyOf[player]
	if not party then
		return false, "You are not in a party"
	end
	if party.Run and St.runOf[player] then
		return false, "Use LEAVE in the run"
	end
	if party.Leader == player then
		for _, uid in ipairs(party.Order) do
			local pm = party.Members[uid]
			if pm and pm.Player ~= player then
				notify(pm.Player, "The party was disbanded", "info", 3)
			end
		end
		removeParty(party)
		return true
	end
	party.Members[player.UserId] = nil
	for i, uid in ipairs(party.Order) do
		if uid == player.UserId then
			table.remove(party.Order, i)
			break
		end
	end
	St.partyOf[player] = nil
	markLobbyDirty()
	return true
end

function DungeonService.SetReady(player, ready)
	local party = St.partyOf[player]
	if not party or party.Run then
		return false, "You are not in a party"
	end
	local pm = party.Members[player.UserId]
	if not pm then
		return false, "You are not in a party"
	end
	pm.Ready = ready == true or player == party.Leader
	markLobbyDirty()
	return true
end

function DungeonService.SetFloor(player, floorIndex)
	local party = St.partyOf[player]
	if not party or party.Leader ~= player then
		return false, "Only the leader picks the floor"
	end
	if party.Run then
		return false, "The run already started"
	end
	floorIndex = whole(tonumber(floorIndex), 1, 12)
	if not floorIndex then
		return false, "Pick a floor"
	end
	local rec = record(player)
	if (tonumber(rec.Best) or 0) < floorIndex - 1 then
		return false, "Clear floor " .. tostring(floorIndex - 1) .. " first"
	end
	party.Floor = floorIndex
	markLobbyDirty()
	return true
end

function DungeonService.KickMember(leader, userId)
	local party = St.partyOf[leader]
	if not party or party.Leader ~= leader then
		return false, "Only the leader can do that"
	end
	if party.Run then
		return false, "Not during a run"
	end
	userId = whole(tonumber(userId), 1)
	if not userId or userId == leader.UserId then
		return false, "That player is not in your party"
	end
	local pm = party.Members[userId]
	if not pm then
		return false, "That player is not in your party"
	end
	party.Members[userId] = nil
	for i, uid in ipairs(party.Order) do
		if uid == userId then
			table.remove(party.Order, i)
			break
		end
	end
	St.partyOf[pm.Player] = nil
	notify(pm.Player, "You were removed from the party", "bad", 4)
	markLobbyDirty()
	return true
end

-- StartRun(party) -> ok, runId | reason: now when everyone is ready, else the ReadyTimeout clock
function DungeonService.StartRun(party)
	if type(party) ~= "table" or not isPlayer(party.Leader) then
		return false, "That party is gone"
	end
	if party.Run then
		return false, "The run already started"
	end
	local okL, whyL = canEnter(party.Leader, party.Floor, true, true)
	if not okL then
		return false, whyL
	end
	local unready = 0
	for _, uid in ipairs(party.Order) do
		local pm = party.Members[uid]
		if pm and uid ~= party.Leader.UserId and not pm.Ready then
			unready = unready + 1
		end
	end
	if unready > 0 then
		if party.WaitingReady then
			return false, "Waiting for the party"
		end
		party.WaitingReady = true
		party.StartAt = now() + num(D().ReadyTimeout, 30)
		for _, uid in ipairs(party.Order) do
			local pm = party.Members[uid]
			if pm then
				notify(pm.Player, "Starting in " .. tostring(num(D().ReadyTimeout, 30)) .. " - press READY", "info", 4)
			end
		end
		markLobbyDirty()
		return true, "Waiting"
	end
	if party.StartAt and not party.WaitingReady then
		return false, "Starting"
	end
	party.WaitingReady = nil
	party.StartAt = now() + K.START_COUNTDOWN
	for _, uid in ipairs(party.Order) do
		local pm = party.Members[uid]
		if pm then
			notify(pm.Player, "Dungeon in " .. tostring(K.START_COUNTDOWN) .. "...", "info", 3)
		end
	end
	markLobbyDirty()
	return true, "Countdown"
end

function DungeonService.StartSolo(player, floorIndex)
	if St.runOf[player] then
		return false, "Finish your dungeon run first"
	end
	if St.partyOf[player] then
		return false, "Leave your party first"
	end
	floorIndex = whole(tonumber(floorIndex), 1, 12)
	if not floorIndex then
		return false, "Pick a floor"
	end
	local okE, whyE = canEnter(player, floorIndex, true, true)
	if not okE then
		return false, whyE
	end
	local okC, party = DungeonService.CreateParty(player, floorIndex)
	if not okC then
		return false, party
	end
	local ok, idOrWhy = Dg.begin(party)
	if not ok then
		removeParty(party)
		return false, idOrWhy
	end
	return true, idOrWhy
end

function DungeonService.Quit(player)
	local run = St.runOf[player]
	if not run then
		return false, "You are not in a run"
	end
	if run.State == "Ending" then
		return false, "The run is over"
	end
	Dg.removeMember(run, player, "Quit")
	return true
end

-- slot: the chest the member stands at (its prompt's ChestSlot); no slot opens nothing (bug batch 2, #14)
function DungeonService.OpenChest(player, slot)
	local run = St.runOf[player]
	if not run then
		return false, "You are not in a run"
	end
	if run.State ~= "Treasure" then
		return false, "No chest yet"
	end
	local m = run.Members[player.UserId]
	if not m or m.Left then
		return false, "No chest"
	end
	if run.Chests[player.UserId] == nil then
		return false, "No chest for you this run"
	end
	if run.Chests[player.UserId] ~= "Closed" then
		return false, "You already picked your chest"
	end
	return Dg.openChest(run, m, slot)
end

function DungeonService.GetRun(player)
	local run = isPlayer(player) and St.runOf[player] or nil
	if not run or run.State == "Ending" and run.Finished then
		return nil
	end
	return { RunId = run.Id, Floor = run.Floor, Room = run.Room, State = run.State, Wave = run.Wave }
end

function DungeonService.KeysInRun(player)
	local set = {}
	local run = isPlayer(player) and St.runOf[player] or nil
	local m = run and run.Members[player.UserId] or nil
	if m and not m.Left then
		for _, key in ipairs(m.Keys) do
			set[key] = true
		end
	end
	return set
end

function DungeonService.ListParties()
	local out = {}
	for _, leaderId in ipairs(St.partyOrder) do
		local party = St.parties[leaderId]
		if party then
			out[#out + 1] = { Leader = leaderId, Floor = party.Floor, Count = partyCount(party), InRun = party.Run ~= nil }
		end
	end
	return out
end

function DungeonService.ListRuns()
	local out = {}
	for _, id in ipairs(St.runOrder) do
		local run = St.runs[id]
		if run then
			out[#out + 1] = { RunId = id, Floor = run.Floor, Room = run.Room, State = run.State, Members = countLive(run), Pocket = run.PocketIndex }
		end
	end
	return out
end

function DungeonService.GetParty(player)
	return St.partyOf[player]
end

function DungeonService.RunById(runId)
	return St.runs[runId]
end

function DungeonService.Shutdown()
	St.closing = true
	for _, id in ipairs(copyList(St.runOrder)) do
		local run = St.runs[id]
		if run then
			if run.State ~= "Ending" then
				Dg.endRun(run, false, "Shutdown", true)
			else
				pcall(finishRun, run)
			end
		end
	end
	for _, leaderId in ipairs(copyList(St.partyOrder)) do
		local party = St.parties[leaderId]
		if party then
			removeParty(party)
		end
	end
end

function DungeonService.SetClosing(flag)
	St.closing = flag == true
end

----------------------------------------------------------------------
-- The remote ladder (type -> range -> permission -> plausibility)
----------------------------------------------------------------------
local function allow(player)
	local t = now()
	local b = St.buckets[player]
	if not b then
		b = { tokens = K.BUCKET_BURST, last = t }
		St.buckets[player] = b
	end
	b.tokens = min(K.BUCKET_BURST, b.tokens + (t - b.last) * K.BUCKET_REFILL)
	b.last = t
	if b.tokens < 1 then
		return false
	end
	b.tokens = b.tokens - 1
	return true
end

local function onCooldown(player, action)
	local cd = COOLDOWN[action]
	if not cd then
		return false
	end
	local list = St.cooldowns[player]
	if not list then
		list = {}
		St.cooldowns[player] = list
	end
	local t = now()
	if list[action] and t - list[action] < cd then
		return true
	end
	list[action] = t
	return false
end

local function refuse(player, why)
	if type(why) == "string" and why ~= "" then
		notify(player, why, "bad", 3)
	end
	return false, why
end

function DungeonService.Request(player, action, a, b)
	if not isPlayer(player) or type(action) ~= "string" or not ACTIONS[action] then
		return false, "junk"
	end
	if not allow(player) then
		return false, "rate"
	end
	if onCooldown(player, action) then
		return false, "cooldown"
	end
	if action == "Open" then
		pushLobby(player, false)
		return true
	elseif action == "Create" then
		local ok, why = DungeonService.CreateParty(player, a)
		if not ok then
			return refuse(player, why)
		end
		return true
	elseif action == "Join" then
		local ok, why = DungeonService.JoinParty(player, a)
		if not ok then
			return refuse(player, why)
		end
		return true
	elseif action == "Leave" then
		local ok, why = DungeonService.LeaveParty(player)
		if not ok then
			return refuse(player, why)
		end
		return true
	elseif action == "Ready" then
		if type(a) ~= "boolean" then
			return false, "junk"
		end
		local ok, why = DungeonService.SetReady(player, a)
		if not ok then
			return refuse(player, why)
		end
		return true
	elseif action == "SetFloor" then
		local ok, why = DungeonService.SetFloor(player, a)
		if not ok then
			return refuse(player, why)
		end
		return true
	elseif action == "Start" then
		local party = St.partyOf[player]
		if not party or party.Leader ~= player then
			return refuse(player, "Only the leader starts the run")
		end
		local ok, why = DungeonService.StartRun(party)
		if not ok then
			return refuse(player, why)
		end
		return true
	elseif action == "Solo" then
		local ok, why = DungeonService.StartSolo(player, a)
		if not ok then
			return refuse(player, why)
		end
		return true
	elseif action == "Quit" then
		local ok, why = DungeonService.Quit(player)
		if not ok then
			return refuse(player, why)
		end
		return true
	elseif action == "Chest" then
		-- a = the chest's slot (the prompt's ChestSlot); OpenChest checks it is free and the player stands at it
		local ok, why = DungeonService.OpenChest(player, a)
		if not ok then
			return refuse(player, why)
		end
		return true
	elseif action == "Kick" then
		local ok, why = DungeonService.KickMember(player, a)
		if not ok then
			return refuse(player, why)
		end
		return true
	end
	return false, "junk"
end

----------------------------------------------------------------------
-- The 0.5 s loop: timers, the threshold, the leash, the watchdog, queued joins, countdowns, Lobby pushes
----------------------------------------------------------------------
local function insideBox(part, position)
	if not part or not part.Parent then
		return false
	end
	local rel = part.CFrame:PointToObjectSpace(position)
	local s = part.Size
	return abs(rel.X) <= s.X / 2 + 1 and abs(rel.Y) <= s.Y / 2 + 3 and abs(rel.Z) <= s.Z / 2 + 1
end

local function tickRun(run, t)
	local d = D()
	if run.State == "Ending" then
		if not run.Finished and t - (run.EndedAt or t) > K.RETURN_DELAY + 2 then
			pcall(finishRun, run)
		end
		return
	end
	if t - run.Started > DungeonService.MaxRunSeconds(run.Floor) then
		return Dg.endRun(run, false, "Error")
	end
	-- members who left the pocket (a respawn elsewhere, an obby match)
	for _, m in ipairs(liveMembers(run)) do
		local p = m.Player
		if not isPlayer(p) then
			Dg.removeMember(run, p, "Disconnect")
		elseif p:GetAttribute(ATTR_IN_MATCH) == true then
			Dg.removeMember(run, p, "Left")
		else
			local root = rootOf(p)
			if root and run.Pocket and (root.Position - run.Pocket.Origin).Magnitude > K.FAR and t - (m.Joined or run.Started) > 1 then
				Dg.removeMember(run, p, "Left")
			end
		end
	end
	if run.State == "Ending" then
		return
	end
	if run.State == "Hall" then
		-- no HallSeconds timer: the group moves on when every member pressed E at the hall's exit (Dg.confirm)
		Dg.syncPrompt(run)
	elseif run.State == "Corridor" then
		local info = roomInfo(run, run.Room)
		if run.Phase == "Threshold" then
			local cross = false
			for _, m in ipairs(liveMembers(run)) do
				local root = rootOf(m.Player)
				if root and info and info.Threshold and insideBox(info.Threshold, root.Position) then
					cross = true
					break
				end
			end
			if cross or t - run.StateAt >= K.THRESHOLD_TIMEOUT then
				Dg.startFight(run)
			end
		else
			-- after the clear: the exit bars open after Intermission (the boss room's stay shut: its exit IS the door to
			-- the treasure alcove, which has none) and the next door's EnterPrompt is enabled; no DoorTime: nobody is
			-- moved until every member pressed E there
			if not run.DoorOpened and t - run.StateAt >= num(d.Intermission, 2) then
				run.DoorOpened = true
				if info and run.Room < 4 then
					St.deps.DungeonBuilder.SetDoor(info, "Exit", true)
				end
				sendRun(run)
			end
		end
	elseif run.State == "Fight" then
		local status = run.Battle and try(St.deps.BattleService, "EncounterStatus", run.Battle) or nil
		if not status then
			run.BattleMissingSince = run.BattleMissingSince or t
			if t - run.BattleMissingSince > K.WATCHDOG_MISSING then
				return Dg.endRun(run, false, "Error")
			end
		else
			run.BattleMissingSince = nil
		end
		local info = roomInfo(run, run.Room)
		if info and info.Center then
			for _, m in ipairs(liveMembers(run)) do
				local root = rootOf(m.Player)
				if root then
					local dx, dz = root.Position.X - info.Center.X, root.Position.Z - info.Center.Z
					if math.sqrt(dx * dx + dz * dz) > K.LEASH then
						St.strikes[m.Player] = (St.strikes[m.Player] or 0) + 1
						if St.strikes[m.Player] >= K.LEASH_STRIKES then
							Dg.removeMember(run, m.Player, "Leash")
						end
					else
						St.strikes[m.Player] = nil
					end
				end
			end
		end
	elseif run.State == "Treasure" then
		if t - run.StateAt >= num(d.TreasureSeconds, 45) then
			for _, m in ipairs(liveMembers(run)) do
				if run.Chests[m.Player.UserId] == "Closed" then
					pcall(Dg.openChest, run, m, nil, true)
				end
			end
			Dg.endRun(run, true, "Cleared")
		end
	end
end

local function tickParties(t)
	for _, leaderId in ipairs(copyList(St.partyOrder)) do
		local party = St.parties[leaderId]
		if party and not party.Run and party.StartAt then
			if not isPlayer(party.Leader) then
				removeParty(party)
			else
				local allReady = true
				for _, uid in ipairs(party.Order) do
					local pm = party.Members[uid]
					if pm and uid ~= leaderId and not pm.Ready then
						allReady = false
					end
				end
				if party.WaitingReady and allReady then
					-- everyone pressed READY during the wait: the countdown proper
					party.WaitingReady = nil
					party.StartAt = t + K.START_COUNTDOWN
					markLobbyDirty()
				elseif t >= party.StartAt then
					local readyOnly = party.WaitingReady == true
					Dg.begin(party, readyOnly)
				end
			end
		end
	end
end

local function tickQueue(t)
	for player, q in pairs(St.joinQueue) do
		local party = q.Party
		local run = party and party.Run
		if not isPlayer(player) or not run or run.State == "Ending" or St.parties[party.Leader.UserId] ~= party then
			St.joinQueue[player] = nil
			if isPlayer(player) then
				notify(player, "That party moved on", "bad", 3)
			end
		elseif (run.State == "Hall" or run.State == "Corridor") and not run.Transit then
			St.joinQueue[player] = nil
			local ok, why = Dg.lateJoin(run, player)
			if ok then
				local spec = try(St.deps.BattleService, "TeamSpec", player)
				party.Members[player.UserId] = { Player = player, Ready = true, Keys = keysOf(spec), Power = powerOf(spec) }
				party.Order[#party.Order + 1] = player.UserId
				St.partyOf[player] = party
			else
				notify(player, tostring(why), "bad", 3)
			end
			markLobbyDirty()
		elseif t >= q.Deadline then
			St.joinQueue[player] = nil
			notify(player, "That party moved on", "bad", 3)
		end
	end
end

local function tick()
	local t = now()
	for _, id in ipairs(copyList(St.runOrder)) do
		local run = St.runs[id]
		if run then
			local ok, err = pcall(tickRun, run, t)
			if not ok then
				warn("[DungeonService] tick failed for " .. tostring(id) .. ": " .. tostring(err))
				pcall(Dg.endRun, run, false, "Error", true)
			end
		end
	end
	pcall(tickParties, t)
	pcall(tickQueue, t)
	for _, p in ipairs(Players:GetPlayers()) do
		if St.lobbyDirty[p] then
			pushLobby(p, false)
		end
	end
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
local function onPlayerRemoving(player)
	local run = St.runOf[player]
	if run then
		pcall(Dg.removeMember, run, player, "Disconnect")
	end
	local party = St.partyOf[player]
	if party then
		pcall(DungeonService.LeaveParty, player)
	end
	St.joinQueue[player] = nil
	St.buckets[player] = nil
	St.cooldowns[player] = nil
	St.toasts[player] = nil
	St.lobbyDirty[player] = nil
	St.lobbySent[player] = nil
	St.strikes[player] = nil
	St.runOf[player] = nil
	St.partyOf[player] = nil
end

local function onPromptTriggered(prompt, player)
	if typeof(prompt) ~= "Instance" or not isPlayer(player) then
		return
	end
	local action = prompt:GetAttribute("DungeonAction")
	if action ~= "Chest" and action ~= "Exit" and action ~= "Enter" then
		return
	end
	local run = St.runOf[player]
	if not run or not run.Pocket or not run.Pocket.Model or not prompt:IsDescendantOf(run.Pocket.Model) then
		return
	end
	if action == "Enter" then
		-- the door's E (decision 2): the shared bucket + a short cooldown, then Dg.confirm validates the rest
		if not allow(player) or onCooldown(player, "Enter") then
			return
		end
		Dg.confirm(run, player, prompt)
	elseif action == "Chest" then
		-- the chest's E (#14): its own slot, through the same bucket / cooldown as the remote
		DungeonService.Request(player, "Chest", prompt:GetAttribute("ChestSlot"))
	else
		DungeonService.Request(player, "Quit")
	end
end

function DungeonService.Init(deps)
	if St.initialized then
		return DungeonService
	end
	St.initialized = true
	St.deps = type(deps) == "table" and deps or {}
	local builtChests = type(St.deps.DungeonBuilder) == "table" and St.deps.DungeonBuilder.CHEST_COUNT or nil
	if builtChests ~= nil then
		assert(type(builtChests) == "number" and builtChests >= K.CHEST_SLOTS, "[DungeonService] DungeonBuilder.CHEST_COUNT ("
			.. tostring(builtChests) .. ") must be >= CHEST_SLOTS = MAX_PARTY (" .. K.CHEST_SLOTS .. "): one chest per member")
	end
	if not St.deps.DungeonInfo and hasFn(St.deps.DungeonBuilder, "GetInfo") then
		St.deps.DungeonInfo = St.deps.DungeonBuilder.GetInfo()
	end
	local remote = getRemote("DungeonRequest")
	if remote then
		St.conns[#St.conns + 1] = remote.OnServerEvent:Connect(function(player, action, a, b)
			local ok, err = pcall(DungeonService.Request, player, action, a, b)
			if not ok then
				warn("[DungeonService] request failed: " .. tostring(err))
			end
		end)
	else
		warn("[DungeonService] the DungeonRequest remote is missing (Config.Remotes)")
	end
	St.conns[#St.conns + 1] = Players.PlayerRemoving:Connect(onPlayerRemoving)
	St.conns[#St.conns + 1] = ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		pcall(onPromptTriggered, prompt, player)
	end)
	St.loop = task.spawn(function()
		while St.initialized do
			task.wait(K.LOOP)
			local ok, err = pcall(tick)
			if not ok then
				warn("[DungeonService] loop error: " .. tostring(err))
			end
		end
	end)
	pcall(function()
		game:BindToClose(function()
			DungeonService.Shutdown()
		end)
	end)
	updateBoard()
	-- LAST (C16): the run provider for BattleService's canBattle / KeysInBattle
	if hasFn(St.deps.BattleService, "SetRunProvider") then
		St.deps.BattleService.SetRunProvider({ KeysInRun = DungeonService.KeysInRun, GetRun = DungeonService.GetRun })
	end
	return DungeonService
end

return DungeonService
