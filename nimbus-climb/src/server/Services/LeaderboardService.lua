-- LeaderboardService (lobby shop; docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.10 and 7, with section 15: the
-- third page is Ring best, there is no Climb wins page): the global top 10 of Trophies, Pets found and Ring best, one
-- OrderedDataStore per stat (Config.Leaderboard.Stores). The client sends nothing; nothing a client says reaches a write.
--
-- Values (ValueOf): Trophies = the profile's Battle.Trophies; Pets = the Discovered keys that are PetCatalog ids; Ring =
-- DataService.GetRing(player).Best. Whole numbers clamped to 0 .. MaxValue, nil while the profile is loading or
-- provisional (a stand-in value is never written or shown). The store key is tostring(UserId).
--
-- Writes (OrderedDataStore:SetAsync, pcall): only from a loaded, non-provisional profile; none without a store, none while
-- RunService:IsStudio() and WriteInStudio is false. A player's first write SeedDelay s after the load, only for a value
-- above 0; then a sweep every SweepSeconds writes a changed value, at most once per WriteEvery per stat; a leave writes once
-- what changed in this session; BindToClose writes what changed and waits at most CLOSE_SECONDS. Every write first needs the
-- SetIncrementSortedAsync request budget at BudgetFloor.Write or more, else it waits for the next sweep.
--
-- Reads: at boot each stat once, BOOT_GAP s apart; then every RefreshSeconds per stat, GetSortedAsync(false, ReadSize)'s
-- first page (pcall). A GetSortedAsync budget under BudgetFloor.Read postpones the read by RetrySeconds[1] without counting
-- a failure; a failed read keeps the last good page and retries after RetrySeconds[1], [2], ... (the last repeats). Names of
-- the Top rows: one batched UserService:GetUserInfosByUserIdsAsync call (cached for the server's life), then
-- Players:GetNameFromUserIdAsync, then "Player" (not cached: asked again at the next read).
--
-- Scope: "Global" once every stat has a good page. "Server" before that (a fresh server never shows an empty board), after
-- failures before the first good read, and for good when there is no store (Studio without API access): the live values of
-- the players in this server (above 0), sorted, rebuilt every FallbackRefresh s.
--
-- LeaderboardState (server -> client): State(player) when the profile loads (or a stand-in recovers), after every refresh,
-- and when the player's own values change (DataService has no signal for them: a PollSeconds poll of the live values).
-- NextAt / UpdatedAt are workspace:GetServerTimeNow() times (the client counts down on the same clock).
--
-- Titles (spec 16.6, Config.Leaderboard.RankTitles): only this service writes them, only from what the server read. The
-- rank is the player's index in the good page of RankTitles.Stat (Trophies), up to Gold; none before the first good page,
-- with no store, or outside the read (the other pages and the board's Scope do not matter). Creator: DevService.IsOwner
-- (the game's creator or the owning group's owner; never Config.Dev.Admins or Studio), asked once per join in a task;
-- a nil answer (the group call failed) is asked again at the next title refresh. Kind: Creator wins (TitleRank still set),
-- else rank <= Rainbow -> "Top10", rank <= Gold -> "Top100". applyTitle writes only what changed: the attributes
-- Config.Attr.Title / TitleRank and leaderstats.<Column>.Value = ColumnText[kind] or "". PlayerService makes leaderstats
-- and its values (Tokens, then Rank); this service never does: while the Rank value is missing one task waits for it
-- (RANK_WAIT s), else the next pass writes it. Passes: Players.PlayerAdded (titles need no profile), the owner's answer,
-- every player after each good read of the title stat, and (with no store, so no reads) each "Server" rebuild. A leave
-- drops the player's entries; each refresh also drops the entries of players no longer in the server.
--
-- Public API
--   LeaderboardService.Init(deps)            deps = { DataService, DevService }
--   LeaderboardService.TitleOf(player) -> kind ("Creator" | "Top10" | "Top100") | nil, rank (1..Gold) | nil  (read only)
--   LeaderboardService.ValueOf(player, stat) -> whole number | nil
--   LeaderboardService.State(player) -> { Stats = { [stat] = { Top = { { UserId, Name, Value }... <= Top },
--                                                              You = { Rank = n | nil, Value = n | nil } } },
--                                         Scope = "Global" | "Server", NextAt, UpdatedAt }
--   LeaderboardService.Scope() -> "Global" | "Server"
--   LeaderboardService._S, _StopForTest(), _CloseForTest()   (smoke tests: a stopped copy drops its connections and loops)
--   LeaderboardService._JoinForTest(player)  (smoke lb_titles: the titles' PlayerAdded handler, run by hand)
--
-- Plain Lua 5.1-compatible syntax only.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local PetCatalog = require(Shared.PetCatalog)

local LeaderboardService = {}

local TICK = 1 -- seconds between two passes of the scheduler (reads, the Server refresh, seeds, sweeps)
local BOOT_GAP = 3 -- seconds between the boot reads of two stats (the first BOOT_GAP s after Init)
local CLOSE_SECONDS = 5 -- BindToClose waits at most this long for its writes
local RANK_WAIT = 10 -- seconds a title waits for PlayerService's leaderstats.Rank before the next pass takes over

local S = {
	DS = nil,
	Dev = nil, -- DevService (IsOwner: the Creator title)
	Started = false,
	Stopped = false,
	Closing = false,
	NoStore = false, -- no OrderedDataStore (Studio without API access): Scope "Server" for good, no reads, no writes
	Stores = {}, -- [stat] = OrderedDataStore
	Pages = {}, -- [stat] = { Entries = { { UserId, Value }... } | nil, Good, Fails, DueAt, UpdatedAt, Reading }
	Names = {}, -- [userId] = name (cached for the server's life)
	Recs = {}, -- [player] = { LoadedAt, SeedAt, Seeded, Base = {}, Written = {}, LastWrite = {}, Pending = {}, Sig }
	Server = { At = 0, Rows = {} }, -- the "Server" scope: Rows[stat] = sorted { { UserId, Name, Value }... }
	FallbackDueAt = 0,
	SweepDueAt = 0,
	InFlight = 0, -- write batches still running
	Writes = 0, -- SetAsync calls made (tests)
	Titles = {}, -- [player] = { Kind, Rank, Waiting }: the title last written (Waiting: a task waits for leaderstats.Rank)
	Owner = {}, -- [player] = true | false (DevService.IsOwner's answer) | "asking"; absent: not asked yet, or it failed
	TitleWrites = 0, -- title attribute / Rank writes made (tests)
	Conns = {},
}
LeaderboardService._S = S

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function cfg()
	return type(Config.Leaderboard) == "table" and Config.Leaderboard or {}
end

local function num(key, default)
	local v = tonumber(cfg()[key])
	if v == nil or v ~= v then
		return default
	end
	return v
end

local function stats()
	local pages = cfg().Pages
	return type(pages) == "table" and pages or {}
end

local function now()
	return Workspace:GetServerTimeNow()
end

local function isPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function displayName(player)
	local ok, name = pcall(function()
		return player.DisplayName
	end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return player.Name
end

-- any value -> a whole number in 0 .. MaxValue
local function whole(v)
	v = tonumber(v)
	if v == nil or v ~= v or v <= 0 then
		return 0
	end
	local max = num("MaxValue", 1e12)
	if v >= max then
		return math.floor(max)
	end
	return math.floor(v)
end

-- the live profile, or nil while loading or provisional
local function profileOf(player)
	local DS = S.DS
	if not DS or not isPlayer(player) then
		return nil
	end
	local okProv, provisional = pcall(DS.IsProvisional, player)
	if not okProv or provisional then
		return nil
	end
	local ok, profile = pcall(DS.GetProfile, player)
	if ok and type(profile) == "table" then
		return profile
	end
	return nil
end

local READ = {
	Trophies = function(_, profile)
		local battle = profile.Battle
		return type(battle) == "table" and battle.Trophies or 0
	end,
	Pets = function(_, profile)
		local n = 0
		local found = profile.Discovered
		if type(found) == "table" then
			for id, seen in pairs(found) do
				if seen == true and PetCatalog.Get(id) then
					n = n + 1
				end
			end
		end
		return n
	end,
	Ring = function(player)
		local ok, ring = pcall(S.DS.GetRing, player)
		if ok and type(ring) == "table" then
			return ring.Best
		end
		return nil
	end,
}

-- "v1|v2|v3": the player's own values (the poll compares it with what was last sent)
local function ownSig(player)
	local parts = {}
	for _, stat in ipairs(stats()) do
		parts[#parts + 1] = tostring(LeaderboardService.ValueOf(player, stat))
	end
	return table.concat(parts, "|")
end

local function send(player)
	if S.Stopped or not isPlayer(player) or player.Parent ~= Players then
		return
	end
	local rec = S.Recs[player]
	if rec then
		rec.Sig = ownSig(player)
	end
	local state = LeaderboardService.State(player)
	local ok, remote = pcall(Remotes.Get, "LeaderboardState")
	if ok and remote then
		pcall(remote.FireClient, remote, player, state)
	end
end

local function sendAll()
	for player in pairs(S.Recs) do
		send(player)
	end
end

-- the "Server" scope: this server's live values above 0, sorted (ties by UserId)
local function rebuildServer()
	local rows = {}
	for _, stat in ipairs(stats()) do
		rows[stat] = {}
	end
	for _, player in ipairs(Players:GetPlayers()) do
		for _, stat in ipairs(stats()) do
			local v = LeaderboardService.ValueOf(player, stat)
			if v and v > 0 then
				local list = rows[stat]
				list[#list + 1] = { UserId = player.UserId, Name = displayName(player), Value = v }
			end
		end
	end
	for _, list in pairs(rows) do
		table.sort(list, function(a, b)
			if a.Value ~= b.Value then
				return a.Value > b.Value
			end
			return a.UserId < b.UserId
		end)
	end
	S.Server.Rows = rows
	S.Server.At = now()
	S.FallbackDueAt = S.Server.At + num("FallbackRefresh", 30)
end

local function nameOf(userId)
	local name = S.Names[userId]
	if name then
		return name
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		return displayName(p)
	end
	return "Player"
end

local function budget(kind)
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType[kind])
	end)
	return ok and tonumber(n) or 0
end

local function floorOf(key, default)
	local floors = cfg().BudgetFloor
	return type(floors) == "table" and tonumber(floors[key]) or default
end

local function writesAllowed()
	if S.NoStore or S.Stopped then
		return false
	end
	return not RunService:IsStudio() or cfg().WriteInStudio == true
end

-- The writes a record owes now ({ { stat, value }... }), marked pending. kind "sweep" (the seed is a record's first sweep)
-- honours WriteEvery; kind "leave" (a leave, BindToClose) writes what changed since the load or the last write.
local function owed(player, rec, kind, t)
	local out = {}
	for _, stat in ipairs(stats()) do
		local v = LeaderboardService.ValueOf(player, stat)
		local last = rec.Written[stat]
		local base = last
		if kind == "leave" and base == nil then
			base = rec.Base[stat]
		end
		local wanted = v ~= nil and v ~= base and (v > 0 or last ~= nil) and not rec.Pending[stat] and S.Stores[stat] ~= nil
		if wanted and kind == "sweep" and rec.LastWrite[stat] and t - rec.LastWrite[stat] < num("WriteEvery", 120) then
			wanted = false
		end
		if wanted and budget("SetIncrementSortedAsync") >= floorOf("Write", 20) then
			rec.Pending[stat] = true
			rec.LastWrite[stat] = t
			out[#out + 1] = { stat, v }
		end
	end
	return out
end

local function writeAll(userId, rec, list)
	if #list == 0 then
		return
	end
	S.InFlight = S.InFlight + 1
	task.spawn(function()
		for _, item in ipairs(list) do
			local stat, v = item[1], item[2]
			local store = S.Stores[stat]
			S.Writes = S.Writes + 1
			local ok = store ~= nil and pcall(function()
				store:SetAsync(tostring(userId), v)
			end)
			if ok then
				rec.Written[stat] = v
			end
			rec.Pending[stat] = nil
		end
		S.InFlight = S.InFlight - 1
	end)
end

local function retryAfter(fails)
	local list = type(cfg().RetrySeconds) == "table" and cfg().RetrySeconds or {}
	if #list == 0 then
		return 30
	end
	return tonumber(list[math.min(math.max(fails, 1), #list)]) or 30
end

-- a GetSortedAsync page -> { { UserId, Value }... } (bad keys dropped, at most ReadSize)
local function cleanPage(raw)
	local out = {}
	local size = math.floor(num("ReadSize", 100))
	for _, e in ipairs(raw) do
		if #out >= size then
			break
		end
		local userId = type(e) == "table" and tonumber(e.key) or nil
		if userId and userId > 0 and userId == math.floor(userId) then
			out[#out + 1] = { UserId = userId, Value = whole(e.value) }
		end
	end
	return out
end

-- the names of the Top rows not known yet (yields: called from a read's own thread)
local function resolveNames(entries)
	local ask = {}
	for i = 1, math.min(math.floor(num("Top", 10)), #entries) do
		local userId = entries[i].UserId
		if not S.Names[userId] then
			local p = Players:GetPlayerByUserId(userId)
			if p then
				S.Names[userId] = displayName(p)
			else
				ask[#ask + 1] = userId
			end
		end
	end
	if #ask == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(ask)
	end)
	if ok and type(infos) == "table" then
		for _, info in ipairs(infos) do
			local id = type(info) == "table" and tonumber(info.Id) or nil
			local name = id and info.DisplayName
			if type(name) ~= "string" or name == "" then
				name = id and info.Username
			end
			if id and type(name) == "string" and name ~= "" then
				S.Names[id] = name
			end
		end
	end
	for _, userId in ipairs(ask) do
		if not S.Names[userId] then
			local okName, name = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			if okName and type(name) == "string" and name ~= "" then
				S.Names[userId] = name
			end
		end
	end
end

----------------------------------------------------------------------
-- titles (spec 16.6)
----------------------------------------------------------------------
local function titleCfg()
	local t = cfg().RankTitles
	return type(t) == "table" and t or {}
end

-- the player's index in the good page of the title stat (1 .. Gold), or nil (no good page yet, no store, outside)
local function titleRank(player)
	local tc = titleCfg()
	local page = S.Pages[tc.Stat or "Trophies"]
	if S.NoStore or not page or not page.Good or type(page.Entries) ~= "table" then
		return nil
	end
	local gold = tonumber(tc.Gold) or 100
	for i, e in ipairs(page.Entries) do
		if i > gold then
			return nil
		end
		if e.UserId == player.UserId then
			return i
		end
	end
	return nil
end

-- kind ("Creator" | "Top10" | "Top100" | nil), rank: Creator wins over a rank (the rank is still given)
local function titleKind(player)
	local rank = titleRank(player)
	if S.Owner[player] == true then
		return "Creator", rank
	end
	if rank then
		return (rank <= (tonumber(titleCfg().Rainbow) or 10)) and "Top10" or "Top100", rank
	end
	return nil, nil
end

-- One player's title, written only where it changed: the two attributes and leaderstats.<Column>'s text. PlayerService
-- makes leaderstats and the Rank value; while it is missing one task waits RANK_WAIT s for it, else the next pass writes.
local function applyTitle(player)
	if S.Stopped or not isPlayer(player) or player.Parent ~= Players then
		return
	end
	local rec = S.Titles[player]
	if not rec then
		rec = { Kind = nil, Rank = nil, Waiting = false }
		S.Titles[player] = rec
	end
	local tc = titleCfg()
	local kind, rank = titleKind(player)
	rec.Kind, rec.Rank = kind, rank
	local attr = type(Config.Attr) == "table" and Config.Attr or {}
	local titleAttr, rankAttr = attr.Title or "Title", attr.TitleRank or "TitleRank"
	if player:GetAttribute(titleAttr) ~= kind then
		player:SetAttribute(titleAttr, kind)
		S.TitleWrites = S.TitleWrites + 1
	end
	if player:GetAttribute(rankAttr) ~= rank then
		player:SetAttribute(rankAttr, rank)
		S.TitleWrites = S.TitleWrites + 1
	end
	local text = kind and type(tc.ColumnText) == "table" and tc.ColumnText[kind] or ""
	local column = tc.Column or "Rank"
	local folder = player:FindFirstChild("leaderstats")
	local value = folder and folder:FindFirstChild(column)
	if value and value:IsA("StringValue") then
		if value.Value ~= text then
			value.Value = text
			S.TitleWrites = S.TitleWrites + 1
		end
	elseif not value and not rec.Waiting then
		rec.Waiting = true
		task.spawn(function()
			local t0 = now()
			local ok, found = pcall(function()
				local stats = player:WaitForChild("leaderstats", RANK_WAIT)
				local left = RANK_WAIT - (now() - t0)
				return stats and left > 0 and stats:WaitForChild(column, left) or nil
			end)
			rec.Waiting = false
			if ok and found and S.Titles[player] == rec then
				applyTitle(player)
			end
		end)
	end
end

-- DevService.IsOwner, asked once per join in its own task (a group game's rank is a web call); a nil answer (the call
-- failed) is asked again at the next title refresh
local function askOwner(player)
	local dev = S.Dev
	if S.Owner[player] ~= nil or type(dev) ~= "table" or type(dev.IsOwner) ~= "function" then
		return
	end
	S.Owner[player] = "asking"
	task.spawn(function()
		local ok, answer = pcall(dev.IsOwner, player)
		if S.Owner[player] ~= "asking" then
			return -- the player left meanwhile (their entry was dropped)
		end
		if ok and type(answer) == "boolean" and player.Parent == Players then
			S.Owner[player] = answer
		else
			S.Owner[player] = nil
		end
		applyTitle(player)
	end)
end

-- After each good read of the title stat (and with no store at each "Server" rebuild): drops the entries of players who
-- left, asks the owner again where the last answer failed, writes every player's title.
local function refreshTitles()
	for _, map in ipairs({ S.Titles, S.Owner }) do
		for player in pairs(map) do
			if not isPlayer(player) or player.Parent ~= Players then
				map[player] = nil
			end
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		askOwner(player)
		applyTitle(player)
	end
end

-- Players.PlayerAdded (and the players already here at Init)
local function onTitleJoin(player)
	if S.Stopped or not isPlayer(player) then
		return
	end
	askOwner(player)
	applyTitle(player)
end

local function readStat(stat)
	local page = S.Pages[stat]
	if budget("GetSortedAsync") < floorOf("Read", 2) then
		page.DueAt = now() + retryAfter(1) -- not a failure: the budget comes back
		page.Reading = false
		return
	end
	local store = S.Stores[stat]
	local ok, raw = pcall(function()
		return store:GetSortedAsync(false, math.floor(num("ReadSize", 100))):GetCurrentPage()
	end)
	if S.Stopped then
		page.Reading = false
		return
	end
	if ok and type(raw) == "table" then
		local entries = cleanPage(raw)
		resolveNames(entries)
		page.Entries, page.Good, page.Fails = entries, true, 0
		page.UpdatedAt = now()
		page.DueAt = page.UpdatedAt + num("RefreshSeconds", 240)
		page.Reading = false
		if stat == (titleCfg().Stat or "Trophies") then
			local okTitles, errTitles = pcall(refreshTitles)
			if not okTitles then
				warn("[LeaderboardService] titles failed: " .. tostring(errTitles))
			end
		end
		sendAll()
	else
		page.Fails = page.Fails + 1
		page.DueAt = now() + retryAfter(page.Fails) -- the last good page stays
		page.Reading = false
	end
end

local function track(player)
	if S.Stopped or not isPlayer(player) or player.Parent ~= Players then
		return nil
	end
	if S.Recs[player] then
		return S.Recs[player]
	end
	local t = now()
	local rec = { LoadedAt = t, SeedAt = t + num("SeedDelay", 30), Seeded = false, Base = {}, Written = {}, LastWrite = {}, Pending = {}, Sig = nil }
	for _, stat in ipairs(stats()) do
		rec.Base[stat] = LeaderboardService.ValueOf(player, stat)
	end
	S.Recs[player] = rec
	S.Names[player.UserId] = displayName(player)
	return rec
end

-- one pass of the scheduler
local function step()
	local t = now()
	if not S.NoStore then
		for _, stat in ipairs(stats()) do
			local page = S.Pages[stat]
			if page and not page.Reading and t >= page.DueAt then
				page.Reading = true
				task.spawn(readStat, stat)
			end
		end
	end
	if LeaderboardService.Scope() == "Server" and t >= S.FallbackDueAt then
		rebuildServer()
		if S.NoStore then
			refreshTitles() -- no reads without a store: an owner answer that failed is asked again here
		end
		sendAll()
	end
	if writesAllowed() and not S.Closing then
		local sweep = t >= S.SweepDueAt
		if sweep then
			S.SweepDueAt = t + num("SweepSeconds", 60)
		end
		for player, rec in pairs(S.Recs) do
			if (not rec.Seeded and t >= rec.SeedAt) or (sweep and rec.Seeded) then
				rec.Seeded = true
				writeAll(player.UserId, rec, owed(player, rec, "sweep", t))
			end
		end
	end
end

-- the own-value poll: a send when a player's values changed since the last send
local function poll()
	for player, rec in pairs(S.Recs) do
		if player.Parent == Players then
			for _, stat in ipairs(stats()) do
				if rec.Base[stat] == nil then
					rec.Base[stat] = LeaderboardService.ValueOf(player, stat) -- a stand-in that recovered
				end
			end
			if ownSig(player) ~= rec.Sig then
				send(player)
			end
		end
	end
end

local function onLeave(player)
	S.Titles[player] = nil
	S.Owner[player] = nil -- an owner ask still running sees its entry gone and stops
	local rec = S.Recs[player]
	if not rec then
		return
	end
	S.Recs[player] = nil -- read below while the profile is still cached (DataService saves in a deferred task)
	if writesAllowed() then
		writeAll(player.UserId, rec, owed(player, rec, "leave", now()))
	end
end

local function close()
	if S.Stopped or S.Closing then
		return
	end
	S.Closing = true
	if not writesAllowed() then
		return
	end
	local t = now()
	for player, rec in pairs(S.Recs) do
		writeAll(player.UserId, rec, owed(player, rec, "leave", t))
	end
	while S.InFlight > 0 and now() - t < CLOSE_SECONDS do
		task.wait(0.1)
	end
end

----------------------------------------------------------------------
-- public
----------------------------------------------------------------------
function LeaderboardService.ValueOf(player, stat)
	local read = type(stat) == "string" and READ[stat] or nil
	local profile = read and profileOf(player)
	if not profile then
		return nil
	end
	local v = read(player, profile)
	if v == nil then
		return nil
	end
	return whole(v)
end

function LeaderboardService.Scope()
	if S.NoStore then
		return "Server"
	end
	local any = false
	for _, stat in ipairs(stats()) do
		local page = S.Pages[stat]
		if not page or not page.Good then
			return "Server"
		end
		any = true
	end
	return any and "Global" or "Server"
end

function LeaderboardService.State(player)
	local scope = LeaderboardService.Scope()
	local global = scope == "Global"
	local top = math.max(0, math.floor(num("Top", 10)))
	local userId = isPlayer(player) and player.UserId or nil
	local out = { Stats = {}, Scope = scope }
	local nextAt, updatedAt = S.FallbackDueAt, S.Server.At
	if global then
		nextAt, updatedAt = nil, nil
		for _, stat in ipairs(stats()) do
			local page = S.Pages[stat]
			nextAt = math.min(nextAt or page.DueAt, page.DueAt)
			updatedAt = math.max(updatedAt or page.UpdatedAt, page.UpdatedAt)
		end
	end
	for _, stat in ipairs(stats()) do
		local list = (global and S.Pages[stat].Entries) or (not global and S.Server.Rows[stat]) or {}
		local rows, rank = {}, nil
		for i, e in ipairs(list) do
			if i <= top then
				rows[i] = { UserId = e.UserId, Name = global and nameOf(e.UserId) or e.Name, Value = e.Value }
			end
			if userId and not rank and e.UserId == userId then
				rank = i
			end
		end
		out.Stats[stat] = { Top = rows, You = { Rank = rank, Value = userId and LeaderboardService.ValueOf(player, stat) or nil } }
	end
	out.NextAt = (nextAt and nextAt > 0) and nextAt or now()
	out.UpdatedAt = (updatedAt and updatedAt > 0) and updatedAt or now()
	return out
end

-- the title as last written: kind ("Creator" | "Top10" | "Top100" | nil), rank (1..Gold | nil); read only
function LeaderboardService.TitleOf(player)
	local rec = S.Titles[player]
	if not rec then
		return nil, nil
	end
	return rec.Kind, rec.Rank
end

function LeaderboardService.Init(deps)
	deps = type(deps) == "table" and deps or {}
	S.DS = deps.DataService or S.DS
	S.Dev = deps.DevService or S.Dev
	if S.Started then
		return
	end
	S.Started = true
	local t = now()
	local names = type(cfg().Stores) == "table" and cfg().Stores or {}
	for i, stat in ipairs(stats()) do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(names[stat])
		end)
		if ok and store then
			S.Stores[stat] = store
		else
			S.NoStore = true
		end
		S.Pages[stat] = { Entries = nil, Good = false, Fails = 0, DueAt = t + i * BOOT_GAP, UpdatedAt = nil, Reading = false }
	end
	S.SweepDueAt = t + num("SweepSeconds", 60)
	rebuildServer()
	local DS = S.DS
	if DS and type(DS.ProfileLoaded) == "table" then
		S.Conns[#S.Conns + 1] = DS.ProfileLoaded:Connect(function(player)
			if track(player) then
				send(player)
			end
		end)
	end
	if DS and type(DS.ProfileRebased) == "table" then
		S.Conns[#S.Conns + 1] = DS.ProfileRebased:Connect(function(player)
			if not S.Recs[player] and track(player) then
				send(player) -- a stand-in that recovered (a failed load fires no ProfileLoaded)
			end
		end)
	end
	S.Conns[#S.Conns + 1] = Players.PlayerRemoving:Connect(onLeave)
	S.Conns[#S.Conns + 1] = Players.PlayerAdded:Connect(onTitleJoin)
	for _, player in ipairs(Players:GetPlayers()) do
		if profileOf(player) and track(player) then
			send(player)
		end
		onTitleJoin(player)
	end
	pcall(function()
		game:BindToClose(close)
	end)
	task.spawn(function()
		while not S.Stopped do
			task.wait(TICK)
			if not S.Stopped then
				local ok, err = pcall(step)
				if not ok then
					warn("[LeaderboardService] step failed: " .. tostring(err))
				end
			end
		end
	end)
	task.spawn(function()
		while not S.Stopped do
			task.wait(num("PollSeconds", 5))
			if not S.Stopped then
				local ok, err = pcall(poll)
				if not ok then
					warn("[LeaderboardService] poll failed: " .. tostring(err))
				end
			end
		end
	end)
end

-- tests: a stopped copy drops its connections; its loops end at their next pass
function LeaderboardService._StopForTest()
	S.Stopped = true
	for _, conn in ipairs(S.Conns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	S.Conns = {}
end

-- tests: what BindToClose runs
function LeaderboardService._CloseForTest()
	close()
end

-- tests: the titles' PlayerAdded handler, run by hand (lb_titles runs it before PlayerService's handler)
function LeaderboardService._JoinForTest(player)
	onTitleJoin(player)
end

return LeaderboardService
