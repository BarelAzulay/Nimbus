-- smoke_session_lock.lua: the save session lock (docs/superpowers/specs/2026-11-10-session-lock-design.md; plan
-- docs/superpowers/plans/2026-11-10-session-lock.md Task 1). One server owns a player's save at a time: a Lock record
-- { Id, Job, Place, At } inside the save, claimed by one UpdateAsync at load, refreshed by every save and by a heartbeat,
-- honoured by every write, released by the leave save (and BindToClose: checked in smoke_server.lua's `shutdown`, the
-- last DataService scenario of the run, because Mock.Shutdown ends the autosave loop for every later scenario).
-- Loaded by tools/smoke.py in the server world (booted):
--   lock_claim_release   Config.Save / Config.Attr.SaveWaiting; the claim at load (ONE UpdateAsync, no GetAsync; only Lock
--                        changes; OwnsSave); an online player's lock stays fresh past LockSeconds (every sweep writes:
--                        TycoonService refreshes Home.LastSeen every 15 s, so a live session is never idle); a dirty
--                        autosave refreshes the lock; the leave writes ONE release (PlayerService no longer saves too) and
--                        the entry is dropped; a failed release keeps the orphan and its retry releases; a clean entry
--                        whose release failed is kept (a quick rejoin uses it with no store call); the heartbeat rule on
--                        an idle entry (a second copy with the same id: no write under HeartbeatSeconds, one write at
--                        120 s+, skipped while the UpdateAsync budget is under 10); no usable store: OwnsSave true
--   lock_two_servers     "server A" is a hand-seeded foreign lock (the mock has one Players list): B waits (attempts at 0,
--                        3, 6, 9, 12 s, SaveWaiting), then plays provisionally; A's release lets B's recovery claim and
--                        show A's data; stale / junk / far-future / Studio locks are free; a real second module copy with
--                        its own id waits on this server's lock; the write guard (the player here: the store wins and the
--                        session goes provisional; an orphan: its late write is refused and the entry dropped); a slow
--                        claim (Latency) is refused while A's leave save is still in flight, then claims
--   lock_rejoin_migrate  a brand-new player's claim writes a lock-only record that makes another server wait (no second
--                        "new player": no gift decided twice); its leave writes a full record without a lock; the v1
--                        migration through a lock-only record; an old record (no Lock) and a newer build's record (a
--                        foreign field, Version 3) keep everything across the claim and the release; a quick rejoin while
--                        the release is pending keeps the cached entry; a rejoin that races the leave's release write gets
--                        the lock back at its next save, one after a landed release claims again (spec 6.5); a Save
--                        during a held load waits and writes nothing
-- White-box: the booted helpers of smoke_server.lua; a second copy of DataService against the same mock store is "another
-- module copy" (the smoke_pity.lua secondServer shape) and gets its own server id with _SetServerIdForTest (every copy
-- shares game.JobId "mock-job" otherwise: one server, two caches). Store calls and writes are counted PER KEY through a
-- watch on Mock.DataStore.Data (installed for the scenario, removed after it), so other players' saves in the same run
-- never move a count. Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local advance, config, mod = K.advance, K.config, K.mod
	local ALLOWED_WARNINGS = { "[DataService]", "[MeshLibrary]" } -- (MeshLibrary: the boot's asset loader has no asset store in the mock)
	local DSt = Mock.DataStore

	local function DS()
		return mod("DataService")
	end

	local userSeq = 0
	local function newUserId()
		userSeq = userSeq + 1
		return 987600 + userSeq
	end

	local function storeKey(uid)
		return config().Tokens.DataStoreName .. "/u_" .. uid
	end

	local function legacyKey(uid)
		return config().Tokens.LegacyDataStoreName .. "/u_" .. uid
	end

	-- The per-key watch: Mock.DataStore.Data becomes a proxy while a scenario runs. Every GetAsync / UpdateAsync of the
	-- mock reads its key once (reads = store calls that reached the store), every write assigns it once (writes). The
	-- test's own reads and seeds go to the real table (data()), so they never count.
	local REAL, watch = nil, nil
	local function startWatch()
		if REAL then
			return
		end
		REAL = DSt.Data
		local w = { reads = {}, writes = {} }
		local real = REAL
		DSt.Data = setmetatable({}, {
			__index = function(_, k)
				w.reads[k] = (w.reads[k] or 0) + 1
				return real[k]
			end,
			__newindex = function(_, k, v)
				w.writes[k] = (w.writes[k] or 0) + 1
				real[k] = v
			end,
		})
		watch = w
	end
	local function stopWatch()
		if REAL then
			DSt.Data = REAL
		end
		REAL, watch = nil, nil
	end
	local function data()
		return REAL or DSt.Data
	end
	local function stored(uid)
		return data()[storeKey(uid)]
	end
	local function seed(uid, rec)
		data()[storeKey(uid)] = rec
	end
	local function calls(uid)
		return watch and watch.reads[storeKey(uid)] or 0
	end
	local function writes(uid)
		return watch and watch.writes[storeKey(uid)] or 0
	end

	local function statsOf()
		return { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} }
	end

	-- a stored record written by an older build (no Lock), plus the given top-level fields
	local function oldRecord(extra)
		local rec = { Version = 2, Tokens = 3, Pets = {}, Equipped = {}, Items = {}, Stats = statsOf() }
		for key, value in pairs(extra or {}) do
			rec[key] = value
		end
		return rec
	end

	-- another live server's lock, `age` seconds old (os.time() is the mock clock)
	local function foreign(id, age)
		return { Id = id or "server-A", Job = "job-" .. tostring(id or "server-A"), Place = 1, At = os.time() - (age or 0) }
	end

	local function count(map)
		local n = 0
		for _ in pairs(type(map) == "table" and map or {}) do
			n = n + 1
		end
		return n
	end

	local function deepEq(a, b)
		if type(a) ~= "table" or type(b) ~= "table" then
			return a == b
		end
		for k, v in pairs(a) do
			if not deepEq(v, b[k]) then
				return false
			end
		end
		for k in pairs(b) do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	-- the two records are equal except for the keys in `skip`
	local function sameExcept(a, b, skip)
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		local x, y = {}, {}
		for k, v in pairs(a) do
			if not skip[k] then
				x[k] = v
			end
		end
		for k, v in pairs(b) do
			if not skip[k] then
				y[k] = v
			end
		end
		return deepEq(x, y)
	end

	local function copyDeep(v)
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in pairs(v) do
			out[k] = copyDeep(x)
		end
		return out
	end

	local function lockOf(uid)
		local rec = stored(uid)
		return type(rec) == "table" and rec.Lock or nil
	end

	local function lockId(uid)
		local lock = lockOf(uid)
		return type(lock) == "table" and lock.Id or nil
	end

	local function showLock(lock)
		if type(lock) ~= "table" then
			return tostring(lock)
		end
		return string.format("{ Id = %s, Job = %s, Place = %s, At = %s } (now %d)", tostring(lock.Id), tostring(lock.Job), tostring(lock.Place), tostring(lock.At), os.time())
	end

	local function join(prefix, uid)
		local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
		advance(1.2)
		return p
	end

	local function add(prefix, uid)
		return Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
	end

	local function leave(p)
		if p and p.Parent then
			Mock.RemovePlayer(p)
		end
		advance(0.8)
	end

	local function waiting(p)
		return p:GetAttribute("SaveWaiting")
	end

	local function hasWarn(text, fromIndex)
		for i = (fromIndex or 0) + 1, #Mock.Output do
			local o = Mock.Output[i]
			if o.kind == "warn" and string.find(o.text, text, 1, true) then
				return true
			end
		end
		return false
	end

	local function countUid(signal, uid)
		local box = { n = 0 }
		local conn = signal:Connect(function(who)
			if who and who.UserId == uid then
				box.n = box.n + 1
			end
		end)
		box.stop = function()
			if conn and conn.Disconnect then
				conn:Disconnect()
			end
		end
		return box
	end

	local function hookedSignals()
		local out = { game:GetService("Players").PlayerRemoving }
		local folder = K.remoteFolder and K.remoteFolder()
		for _, name in ipairs({ "RequestProfile", "SettingsSet" }) do
			local remote = folder and folder:FindFirstChild(name)
			if remote then
				out[#out + 1] = remote.OnServerEvent
			end
		end
		return out
	end

	local function connectionMarks()
		local marks = {}
		for _, sig in ipairs(hookedSignals()) do
			local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
			marks[#marks + 1] = { conns = conns, n = conns and #conns or 0 }
		end
		return marks
	end

	local function dropHooks(marks)
		local clean = true
		for _, m in ipairs(marks) do
			if m.conns then
				for i = #m.conns, m.n + 1, -1 do
					local conn = m.conns[i]
					if type(conn) == "table" and conn.Disconnect then
						conn:Disconnect()
					end
				end
				clean = clean and #m.conns == m.n
			else
				clean = false
			end
		end
		return clean
	end

	-- a second, independent copy of DataService (own cache, same mock store, the same game.JobId)
	local function secondServer(name)
		local inst = K.moduleInstance("server/Services/DataService")
		if not inst then
			return nil
		end
		local marks = connectionMarks()
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
			return dropHooks(marks)
		end
		return module, clone, release
	end

	-- a second copy with its OWN server id: a real other server for the lock
	local function serverB(name, id)
		local B, clone, rel = secondServer(name)
		if B and type(B._SetServerIdForTest) == "function" then
			B._SetServerIdForTest(id)
		end
		return B, clone, rel
	end

	-- runs body under pcall, then always restores the store watch and the failure switches and removes the players left
	local function run(name, body)
		local players = {}
		local okRun, errRun = pcall(body, players)
		stopWatch()
		DSt.Fail, DSt.FailOnly, DSt.FailCount, DSt.Latency, DSt.Unavailable = false, nil, nil, 0, false
		DSt.Budget = {}
		for _, p in ipairs(players) do
			if p.Parent then
				Mock.RemovePlayer(p)
			end
		end
		advance(2)
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors(name)
		K.flushWarnings(name, ALLOWED_WARNINGS)
	end

	----------------------------------------------------------------------------------------------------
	-- lock_claim_release
	----------------------------------------------------------------------------------------------------
	S.lock_claim_release = guarded("lock_claim_release", function()
		if not K.needBoot() then
			return
		end
		local Config = config()
		local D = DS()
		run("lock_claim_release", function(players)
			local save = type(Config.Save) == "table" and Config.Save or {}
			T.check(type(Config.Save) == "table", "lock config: Config.Save exists")
			T.eq(save.LockSeconds, 360, "lock config: Config.Save.LockSeconds = 360")
			T.eq(save.HeartbeatSeconds, 120, "lock config: Config.Save.HeartbeatSeconds = 120")
			T.eq(save.ClaimWaitSeconds, 12, "lock config: Config.Save.ClaimWaitSeconds = 12")
			T.eq(save.ClaimRetrySeconds, 3, "lock config: Config.Save.ClaimRetrySeconds = 3")
			T.eq(Config.Attr.SaveWaiting, "SaveWaiting", "lock config: Config.Attr.SaveWaiting = \"SaveWaiting\"")
			if not T.check(type(D.OwnsSave) == "function" and type(D._SetServerIdForTest) == "function",
				"lock api: DataService.OwnsSave and DataService._SetServerIdForTest exist") then
				return
			end
			startWatch()

			-- the claim at load
			local uid = newUserId()
			local seeded = oldRecord({ Gems = 40 })
			seed(uid, copyDeep(seeded))
			local p = join("LockClaim", uid)
			players[#players + 1] = p
			T.eq(calls(uid), 1, "lock claim: ONE store call at load (the claiming UpdateAsync; no GetAsync)")
			T.eq(writes(uid), 1, "lock claim: ...and it is the one write of the join")
			local lock = lockOf(uid)
			T.check(type(lock) == "table" and lock.Id == "mock-job" and lock.Job == "mock-job" and lock.Place == 1
				and type(lock.At) == "number" and math.abs(lock.At - os.time()) <= 2,
				"lock claim: the record holds Lock = { Id = this server, Job = game.JobId, Place = game.PlaceId, At = now }", showLock(lock))
			T.eq(D.OwnsSave(p), true, "lock claim: OwnsSave(player) is true after the claim")
			T.eq(D.GetGems(p), 40, "lock claim: the claim's record is the profile (40 gems)")
			T.check(sameExcept(stored(uid), seeded, { Lock = true }), "lock claim: the claim changed only Lock (Version 2, the gems, every other key as stored)")
			T.eq(waiting(p), nil, "lock claim: no SaveWaiting attribute on a free record")

			-- an online player's lock never ages out: every autosave sweep writes (TycoonService refreshes Home.LastSeen every
			-- 15 s, so a live session is never idle) and every write stamps the lock; the heartbeat rule below covers an
			-- entry with truly nothing to write
			advance(400)
			T.check(lockId(uid) == "mock-job" and os.time() - ((lockOf(uid) or {}).At or 0) <= 100 and writes(uid) >= 4,
				"lock fresh: across 400 s online (> LockSeconds) every sweep's write kept the lock under 100 s old",
				writes(uid) .. " writes, " .. showLock(lockOf(uid)))

			-- a dirty save refreshes the lock
			D.AddGems(p, 1)
			advance(95)
			T.check((stored(uid) or {}).Gems == 41 and ((lockOf(uid) or {}).At or 0) >= os.time() - 95,
				"lock save: the dirty autosave wrote the gems and refreshed the lock", showLock(lockOf(uid)))

			-- the release at leave
			local w2 = writes(uid)
			leave(p)
			T.eq(writes(uid) - w2, 1, "lock release: ONE write at leave (PlayerService no longer saves as well)")
			T.eq(lockOf(uid), nil, "lock release: the leave save released the lock")
			T.eq((stored(uid) or {}).Gems, 41, "lock release: ...with the gems")
			stored(uid).Gems = 7
			local p2 = join("LockClaim", uid)
			players[#players + 1] = p2
			T.eq(D.GetGems(p2), 7, "lock release: the entry was dropped after the release (the rejoin reads the store)")
			leave(p2)

			-- a failed release keeps the orphan and its retry releases
			local p3 = join("LockClaim", uid)
			players[#players + 1] = p3
			D.AddGems(p3, 2)
			DSt.FailOnly, DSt.Fail = "UpdateAsync", true
			leave(p3)
			advance(1.5) -- both attempts of the leave save failed: an orphan
			T.check(type(lockOf(uid)) == "table" and (stored(uid) or {}).Gems == 7, "lock release failed: the record still holds the lock and the old gems")
			DSt.Fail, DSt.FailOnly = false, nil
			advance(12) -- the first orphan retry (10 s)
			T.check(lockOf(uid) == nil and (stored(uid) or {}).Gems == 9, "lock release failed: the orphan retry wrote the gems and released the lock",
				showLock(lockOf(uid)) .. ", gems " .. tostring((stored(uid) or {}).Gems))

			-- a clean entry whose release failed is not dropped before its release lands
			local p4 = join("LockClaim", uid)
			players[#players + 1] = p4
			D.Save(p4) -- what the join changed is written: the leave below has nothing to write but the release
			DSt.FailOnly, DSt.Fail = "UpdateAsync", true
			leave(p4)
			advance(1.5)
			local c1 = calls(uid)
			local p5 = join("LockClaim", uid)
			players[#players + 1] = p5
			T.check(calls(uid) == c1 and D.OwnsSave(p5) == true,
				"lock orphan: a clean entry whose release failed is kept (it holds the lock): the quick rejoin uses it with no store call",
				(calls(uid) - c1) .. " calls, OwnsSave " .. tostring(D.OwnsSave(p5)))
			DSt.Fail, DSt.FailOnly = false, nil
			leave(p5)
			T.eq(lockOf(uid), nil, "lock orphan: ...and that session's leave releases the lock")

			-- the heartbeat rule (spec 7), on an IDLE entry: a second copy with the SAME server id (one server, two caches)
			-- holds a session nothing touches (TycoonService and the other services mutate the booted copy only). Its saves
			-- are writeEntry exactly as the autosave sweep calls it (mode nil, the player here); each is synchronous on
			-- the main thread (Latency 0), so the per-key write count around one call is that call's writes only.
			local uH = newUserId()
			seed(uH, oldRecord({ Gems = 12 }))
			local pH = join("LockBeat", uH)
			players[#players + 1] = pH
			local H, _, releaseH = secondServer("DataServiceLockBeat")
			if T.check(H ~= nil and type(H.Load) == "function", "lock heartbeat: a second DataService copy (the same id) loads") then
				H.Load(pH)
				H.Save(pH) -- what the copy's own load changed (its migrations) is written: from here its entry is idle
				local function hSave()
					local before = writes(uH)
					local ok = H.Save(pH)
					return ok, writes(uH) - before
				end
				local ok1, n1 = hSave()
				T.check(ok1 == true and n1 == 0, "lock heartbeat: an empty save of a fresh lock writes nothing", tostring(ok1) .. ", " .. n1 .. " writes")
				advance(100)
				local ok2, n2 = hSave()
				T.check(ok2 == true and n2 == 0, "lock heartbeat: lock age 100 s < HeartbeatSeconds: an empty save writes nothing", tostring(ok2) .. ", " .. n2 .. " writes")
				advance(25)
				local beforeRec = copyDeep(stored(uH))
				local ok3, n3 = hSave()
				T.check(ok3 == true and n3 == 1 and (lockOf(uH) or {}).At == os.time() and lockId(uH) == "mock-job",
					"lock heartbeat: lock age 125 s >= 120: the empty save writes once and refreshes the lock", tostring(ok3) .. ", " .. n3 .. " writes, " .. showLock(lockOf(uH)))
				T.check(sameExcept(stored(uH), beforeRec, { Lock = true, UpdatedAt = true }), "lock heartbeat: ...nothing but Lock / UpdatedAt changed")
				advance(125)
				DSt.Budget = { UpdateAsync = 5 }
				local ok4, n4 = hSave()
				T.check(ok4 == true and n4 == 0, "lock heartbeat: an UpdateAsync budget under 10 skips the heartbeat (no write)", tostring(ok4) .. ", " .. n4 .. " writes")
				DSt.Budget = {}
				local ok5, n5 = hSave()
				T.check(ok5 == true and n5 == 1 and (lockOf(uH) or {}).At == os.time(), "lock heartbeat: the budget back, the next save refreshes the lock",
					tostring(ok5) .. ", " .. n5 .. " writes")
				leave(pH) -- both copies' leave handlers release
				advance(2)
				T.check(releaseH() == true, "lock heartbeat: the copy's hooks are dropped with it")
				T.eq(lockOf(uH), nil, "lock heartbeat: the leave released the lock")
			end
			leave(pH)

			-- no usable store (Studio without API access): nothing to own
			local uq = newUserId()
			local q = join("LockNoApi", uq)
			players[#players + 1] = q
			local D2, _, release2 = secondServer("DataServiceLockNoApi")
			if T.check(D2 ~= nil and type(D2.Load) == "function", "lock no store: a second DataService copy loads") then
				DSt.Unavailable = true
				local okLoad = pcall(D2.Load, q)
				local owns = type(D2.OwnsSave) == "function" and D2.OwnsSave(q)
				DSt.Unavailable = false
				T.check(okLoad and owns == true, "lock no store: no usable store: nothing to own, OwnsSave true at once", tostring(owns))
				pcall(D2.Release, q)
				T.check(release2() == true, "lock no store: the copy's hooks are dropped with it")
			end
			leave(q)
		end)
	end)

	----------------------------------------------------------------------------------------------------
	-- lock_two_servers
	----------------------------------------------------------------------------------------------------
	S.lock_two_servers = guarded("lock_two_servers", function()
		if not K.needBoot() then
			return
		end
		local Config = config()
		local D = DS()
		run("lock_two_servers", function(players)
			if not T.check(type(D.OwnsSave) == "function" and type(D._SetServerIdForTest) == "function", "lock two servers: the lock API exists") then
				return
			end
			startWatch()

			-- B (this server) waits while A holds the record
			local uid = newUserId()
			seed(uid, oldRecord({ Gems = 500, Lock = foreign("server-A") }))
			local p = add("LockHop", uid)
			players[#players + 1] = p
			advance(1)
			T.eq(waiting(p), true, "lock wait: the SaveWaiting attribute is set at the first held attempt")
			T.eq(D.GetProfile(p), nil, "lock wait: no profile while the load waits")
			advance(10)
			T.check(calls(uid) == 4 and D.GetProfile(p) == nil, "lock wait: attempts at 0, 3, 6, 9 s so far (one UpdateAsync each), still waiting at 11 s",
				calls(uid) .. " calls")
			T.eq(writes(uid), 0, "lock wait: ...none of them wrote")
			advance(2.6)
			-- (>= 5: an autosave sweep that falls in the 1.6 s after the give-up may already have tried its recovery claim)
			T.check(calls(uid) >= 5 and D.IsProvisional(p) == true and D.GetProfile(p) ~= nil,
				"lock wait: after the 5th attempt at 12 s the load gives up: provisional", calls(uid) .. " calls, provisional " .. tostring(D.IsProvisional(p)))
			T.eq(p:GetAttribute(Config.Attr.ProfileLoaded), true, "lock wait: ProfileLoaded is set (the world opens on a stand-in)")
			T.check(lockId(uid) == "server-A" and writes(uid) == 0, "lock wait: A still owns the record (nothing written)")
			T.check(D.GetGems(p) == 0 and D.SpendGems(p, 1) == false and D.GetPity(p) == nil, "lock wait: a stand-in: 0 gems, nothing to spend, no pity")
			T.eq(D.OwnsSave(p), false, "lock wait: OwnsSave is false while provisional")

			-- A's release (its leave save lands with the 500 spent) lets B's recovery claim
			local rebased = countUid(D.ProfileRebased, uid)
			stored(uid).Gems = 0
			stored(uid).Lock = nil
			advance(20)
			T.check(D.IsProvisional(p) == false and D.OwnsSave(p) == true and lockId(uid) == "mock-job", "lock wait: A's release lets the recovery claim",
				"provisional " .. tostring(D.IsProvisional(p)) .. ", " .. showLock(lockOf(uid)))
			T.eq(D.GetGems(p), 0, "lock wait: this server shows A's spend, never the stale 500")
			T.eq(waiting(p), nil, "lock wait: SaveWaiting is removed once the claim lands")
			T.eq(rebased.n, 1, "lock wait: ProfileRebased fired once (the usual re-sync)")
			rebased.stop()
			leave(p)

			-- a stale lock is taken at once; a lock one second younger is waited on
			local u2 = newUserId()
			seed(u2, oldRecord({ Gems = 5, Lock = foreign("server-C", 360) }))
			local p2 = join("LockStale", u2)
			players[#players + 1] = p2
			T.check(D.OwnsSave(p2) == true and lockId(u2) == "mock-job" and waiting(p2) == nil, "lock steal: a lock aged LockSeconds is taken at once", showLock(lockOf(u2)))
			leave(p2)
			local u3 = newUserId()
			seed(u3, oldRecord({ Lock = foreign("server-C", 359) }))
			local p3 = add("LockAlmost", u3)
			players[#players + 1] = p3
			advance(1)
			T.check(waiting(p3) == true and D.GetProfile(p3) == nil, "lock steal: a lock aged 359 s is waited on")
			advance(2.5)
			T.check(D.OwnsSave(p3) == true and waiting(p3) == nil and lockId(u3) == "mock-job", "lock steal: ...the 3 s attempt finds it aged 362 s: claimed",
				showLock(lockOf(u3)))
			leave(p3)

			-- junk and far-future locks are free; the Studio rule
			local junks = {
				{ Id = 5, At = "x" },
				{ Id = "server-D", Job = "d", Place = 1, At = os.time() + 400 },
				"junk",
				{ Id = "server-E" },
				{ Id = "studio-abc", Job = "", Place = 1, At = os.time() },
			}
			local names = { "Id 5 / At \"x\"", "At 400 s in the future", "a string", "no At", "another Studio session's lock (the mock is Studio)" }
			for i, junk in ipairs(junks) do
				local u = newUserId()
				seed(u, oldRecord({ Lock = junk }))
				local pj = join("LockJunk", u)
				players[#players + 1] = pj
				T.check(D.OwnsSave(pj) == true and lockId(u) == "mock-job" and waiting(pj) == nil, "lock free: " .. names[i] .. " is free: claimed at once", showLock(lockOf(u)))
				leave(pj)
			end
			local uS = newUserId()
			seed(uS, oldRecord({ Lock = foreign("mock-job2") }))
			local ps = add("LockLive", uS)
			players[#players + 1] = ps
			advance(1)
			T.check(waiting(ps) == true and D.GetProfile(ps) == nil, "lock free: a live server's fresh lock (not \"studio-\") is waited on in Studio too")
			stored(uS).Lock = nil
			advance(3)
			T.eq(D.OwnsSave(ps), true, "lock free: ...and claimed once it is released")
			leave(ps)

			-- a real second module copy with its own id waits on this server's fresh lock
			local A, _, releaseA = serverB("DataServiceLockA", "server-A")
			if T.check(A ~= nil and type(A.Load) == "function", "lock twin: a second DataService copy with its own id loads") then
				local uA = newUserId()
				seed(uA, oldRecord({ Gems = 500 }))
				local pa = join("LockTwin", uA)
				players[#players + 1] = pa
				T.check(D.OwnsSave(pa) == true and lockId(uA) == "mock-job", "lock twin: this server claimed the record")
				task.spawn(A.Load, pa)
				advance(13)
				T.check(A.IsProvisional(pa) == true and A.OwnsSave(pa) == false and lockId(uA) == "mock-job",
					"lock twin: the other copy waited on this server's fresh lock (12 s), then plays provisionally", showLock(lockOf(uA)))
				T.eq(D.OwnsSave(pa), true, "lock twin: ...this server still owns the save")
				leave(pa) -- both copies' leave handlers run: the twin has nothing to write and no lock to free
				advance(2)
				T.check(releaseA() == true, "lock twin: the copy's hooks are dropped with it")
				T.eq(lockOf(uA), nil, "lock twin: this server's release cleared the lock")
			end

			-- the guard with the player here: the store wins, the session goes provisional until the lock frees
			local uG = newUserId()
			seed(uG, oldRecord({ Gems = 500 }))
			local pg = join("LockGuard", uG)
			players[#players + 1] = pg
			D.Save(pg)
			stored(uG).Lock = foreign("server-A") -- another live server took the record (by hand)
			D.AddGems(pg, 1)
			local wG = writes(uG)
			local mark = #Mock.Output
			T.check(K.waitFor(function()
				return D.IsProvisional(pg) == true
			end, 100), "lock guard: the autosave's write trips the guard (another live lock in the record)")
			T.check(writes(uG) == wG and (stored(uG) or {}).Gems == 500 and lockId(uG) == "server-A", "lock guard: the write is refused: the record is untouched",
				(writes(uG) - wG) .. " writes, gems " .. tostring((stored(uG) or {}).Gems))
			T.check(hasWarn("another server owns the save", mark), "lock guard: ...with a [DataService] warning")
			T.check(D.GetGems(pg) == 500 and D.OwnsSave(pg) == false and waiting(pg) == true, "lock guard: the player is here: the store wins (500), provisional, SaveWaiting",
				"gems " .. tostring(D.GetGems(pg)))
			stored(uG).Lock = nil
			T.check(K.waitFor(function()
				return D.OwnsSave(pg) == true
			end, 100), "lock guard: the lock freed: the recovery claims again")
			T.eq(waiting(pg), nil, "lock guard: ...SaveWaiting removed")

			-- the guard on an orphan: the late write of a server the player left is refused
			D.AddGems(pg, 3)
			DSt.FailOnly, DSt.Fail = "UpdateAsync", true
			Mock.RemovePlayer(pg)
			advance(2) -- both attempts of the leave save failed: an orphan holding +3
			DSt.Fail, DSt.FailOnly = false, nil
			stored(uG).Lock = foreign("server-A") -- the player's new server took the record meanwhile
			local mark2 = #Mock.Output
			advance(12) -- the orphan retry (10 s)
			T.check((stored(uG) or {}).Gems == 500 and lockId(uG) == "server-A", "lock guard orphan: the orphan's late write is refused: a stale server never saves",
				"gems " .. tostring((stored(uG) or {}).Gems) .. ", " .. showLock(lockOf(uG)))
			T.check(hasWarn("another server owns the save", mark2), "lock guard orphan: ...with a warning")
			stored(uG).Lock = nil
			stored(uG).Gems = 9
			local pg2 = join("LockGuard", uG)
			players[#players + 1] = pg2
			T.eq(D.GetGems(pg2), 9, "lock guard orphan: the stale entry was dropped: the rejoin reads the store")
			leave(pg2)

			-- a slow claim (Latency) is refused while A's leave save is still in flight, then claims
			local uL = newUserId()
			seed(uL, oldRecord({ Gems = 20, Lock = foreign("server-A") }))
			DSt.Latency = 2
			local pl = add("LockSlow", uL)
			players[#players + 1] = pl
			advance(2.5)
			T.check(waiting(pl) == true and D.GetProfile(pl) == nil, "lock slow: the first claim (its callback at 2 s) is refused: A still holds the record")
			stored(uL).Lock = nil -- A's leave save lands
			advance(5)
			T.check(D.OwnsSave(pl) == true and waiting(pl) == nil and lockId(uL) == "mock-job" and D.GetGems(pl) == 20,
				"lock slow: the next attempt (3 s later) claims and reads A's data", showLock(lockOf(uL)))
			DSt.Latency = 0
			leave(pl)
		end)
	end)

	----------------------------------------------------------------------------------------------------
	-- lock_rejoin_migrate
	----------------------------------------------------------------------------------------------------
	S.lock_rejoin_migrate = guarded("lock_rejoin_migrate", function()
		if not K.needBoot() then
			return
		end
		local D = DS()
		run("lock_rejoin_migrate", function(players)
			if not T.check(type(D.OwnsSave) == "function" and type(D._SetServerIdForTest) == "function", "lock migrate: the lock API exists") then
				return
			end
			startWatch()

			-- a brand-new player: the claim writes a lock-only record, which makes another server wait
			local uN = newUserId()
			local pn = join("LockNew", uN)
			players[#players + 1] = pn
			local rec = stored(uN)
			T.check(type(rec) == "table" and rec.Version == nil and rec.Tokens == nil and type(rec.Lock) == "table" and rec.Lock.Id == "mock-job" and count(rec) == 1,
				"lock new: a brand-new player's claim writes a lock-only record { Lock }", type(rec) == "table" and (count(rec) .. " keys") or tostring(rec))
			T.eq(D.GetTokens(pn), 0, "lock new: ...and the profile is the defaults")
			T.eq(D.OwnsSave(pn), true, "lock new: this server owns the save")
			local B, _, releaseB = serverB("DataServiceLockNewB", "server-B")
			if T.check(B ~= nil and type(B.Load) == "function", "lock new: a second DataService copy with its own id loads") then
				task.spawn(B.Load, pn)
				advance(1)
				T.check(B.GetProfile(pn) == nil and waiting(pn) == true, "lock new: the lock-only record makes the other server wait (no second \"new player\")")
				advance(13)
				T.eq(B.IsProvisional(pn), true, "lock new: ...then it plays provisionally")
				T.check(B.GetTutorial(pn) == nil and B.MarkTrove(pn, "TutorialStarter", nil) == false, "lock new: no gift decided on the stand-in")
				-- leave with nothing earned: a full default record without a lock (the copy writes nothing)
				leave(pn)
				advance(2)
				T.check(releaseB() == true, "lock new: the copy's hooks are dropped with it")
			else
				leave(pn)
			end
			rec = stored(uN)
			T.check(type(rec) == "table" and rec.Version == 2 and type(rec.Tokens) == "number" and rec.Lock == nil,
				"lock new: the leave with nothing earned writes a full record (Version 2, Tokens) without a lock", showLock(type(rec) == "table" and rec.Lock))

			-- the v1 migration still works through a lock-only record
			local uV = newUserId()
			data()[legacyKey(uV)] = { Tokens = 33 }
			local pv = join("LockLegacy", uV)
			players[#players + 1] = pv
			T.eq(D.GetTokens(pv), 33, "lock legacy: the v1 tokens are the starting balance")
			T.check(type(lockOf(uV)) == "table" and (stored(uV) or {}).Tokens == nil, "lock legacy: the lock-only record exists, the tokens are not written yet")
			D.AddTokens(pv, 1)
			T.check(K.waitFor(function()
				return (stored(uV) or {}).Tokens == 34
			end, 100), "lock legacy: the next autosave writes 33 + 1", tostring((stored(uV) or {}).Tokens))
			leave(pv)
			local leg = data()[legacyKey(uV)]
			T.check(type(leg) == "table" and leg.Tokens == 33 and count(leg) == 1, "lock legacy: the legacy store is never written")

			-- an old record (no Lock) needs no migration
			local uO = newUserId()
			seed(uO, oldRecord({ Gems = 5 }))
			local po = join("LockOld", uO)
			players[#players + 1] = po
			T.check((stored(uO) or {}).Version == 2 and (stored(uO) or {}).Gems == 5 and lockId(uO) == "mock-job", "lock old record: loads as it is; the claim adds the lock")
			leave(po)
			T.check(lockOf(uO) == nil and (stored(uO) or {}).Gems == 5 and (stored(uO) or {}).Version == 2, "lock old record: ...the leave writes it back with Version 2, no lock")

			-- a newer build's record keeps its field and Version across the claim, a save and the release
			local uF = newUserId()
			seed(uF, oldRecord({ Future = { x = 1 }, Version = 3 }))
			local pf = join("LockFuture", uF)
			players[#players + 1] = pf
			local function futureX()
				local r = stored(uF)
				return type(r) == "table" and type(r.Future) == "table" and r.Future.x or nil
			end
			T.check(futureX() == 1 and (stored(uF) or {}).Version == 3 and lockId(uF) == "mock-job", "lock forward: the claim keeps a newer build's field and Version 3")
			D.AddGems(pf, 1)
			T.check(K.waitFor(function()
				return (stored(uF) or {}).Gems == 1
			end, 100), "lock forward: the autosave writes the gem")
			T.check(futureX() == 1 and (stored(uF) or {}).Version == 3 and type(lockOf(uF)) == "table", "lock forward: ...keeping the field, Version 3 and the lock")
			leave(pf)
			T.check(futureX() == 1 and lockOf(uF) == nil, "lock forward: the release keeps the field and clears the lock")

			-- a quick rejoin while the release is pending (an orphan that still holds the lock)
			local uQ = newUserId()
			local pq = join("LockQuick", uQ)
			players[#players + 1] = pq
			D.AddGems(pq, 2)
			DSt.FailOnly, DSt.Fail = "UpdateAsync", true
			Mock.RemovePlayer(pq)
			advance(2)
			local cQ = calls(uQ)
			local pq2 = join("LockQuick", uQ)
			players[#players + 1] = pq2
			T.check(calls(uQ) == cQ and D.GetGems(pq2) == 2 and D.OwnsSave(pq2) == true,
				"lock rejoin: the cached entry still holds the lock: no store call, the gems are there", (calls(uQ) - cQ) .. " calls, gems " .. tostring(D.GetGems(pq2)))
			DSt.Fail, DSt.FailOnly = false, nil
			leave(pq2)
			T.check((stored(uQ) or {}).Gems == 2 and lockOf(uQ) == nil, "lock rejoin: ...its leave writes the gems and releases")

			-- a rejoin races the leave's release write (spec 6.5): the new join finds the cached entry while the release is
			-- in flight; the release lands after it (no lock held now) and the next save takes the lock back
			local uR = newUserId()
			seed(uR, oldRecord({ Gems = 30 }))
			local pr = join("LockRace", uR)
			players[#players + 1] = pr
			D.Save(pr)
			DSt.Latency = 1
			Mock.RemovePlayer(pr)
			advance(0.3) -- the release write is in flight (it lands at 1 s)
			local pr2 = add("LockRace", uR)
			players[#players + 1] = pr2
			advance(1.5)
			DSt.Latency = 0
			T.check(lockOf(uR) == nil and D.GetProfile(pr2) ~= nil and D.GetGems(pr2) == 30 and D.OwnsSave(pr2) == false,
				"lock race: the rejoin used the cached entry; the release landed after it (the lock is not held now)", showLock(lockOf(uR)) .. ", OwnsSave " .. tostring(D.OwnsSave(pr2)))
			T.check(D.Save(pr2) == true and lockId(uR) == "mock-job" and D.OwnsSave(pr2) == true, "lock race: the next save (empty delta) takes the lock back")
			-- ...and a rejoin AFTER a landed release, while the entry is still cached (a write after the release's snapshot
			-- kept it as an orphan), claims again (one UpdateAsync) and keeps that write
			DSt.Latency = 1
			Mock.RemovePlayer(pr2)
			advance(0.3)
			D.AddGems(pr2, 1) -- a late write while the release is in flight
			advance(1.2)
			DSt.Latency = 0
			T.check(lockOf(uR) == nil and (stored(uR) or {}).Gems == 30, "lock reclaim: the release landed without the late gem (an orphan keeps it)")
			local cR = calls(uR)
			local pr3 = join("LockRace", uR)
			players[#players + 1] = pr3
			T.check(calls(uR) - cR == 1 and lockId(uR) == "mock-job" and D.OwnsSave(pr3) == true and D.GetGems(pr3) == 31,
				"lock reclaim: the rejoin claims again (one UpdateAsync) and keeps the late gem", (calls(uR) - cR) .. " calls, gems " .. tostring(D.GetGems(pr3)))
			leave(pr3)
			T.check((stored(uR) or {}).Gems == 31 and lockOf(uR) == nil, "lock reclaim: ...its leave writes it and releases")

			-- a Save during a held load waits for the load and writes nothing
			local uW = newUserId()
			seed(uW, oldRecord({ Gems = 8, Lock = foreign("server-A") }))
			local pw = add("LockSaveWait", uW)
			players[#players + 1] = pw
			advance(0.5)
			local box = { done = false }
			task.spawn(function()
				box.result = D.Save(pw)
				box.done = true
			end)
			advance(5)
			T.check(box.done == false and writes(uW) == 0, "lock save wait: a Save during a held load waits for the load, nothing written")
			advance(9)
			T.check(box.done == true and box.result == false and writes(uW) == 0 and lockId(uW) == "server-A" and D.IsProvisional(pw) == true,
				"lock save wait: the load gave up (provisional): the Save answers false and wrote nothing", "done " .. tostring(box.done) .. ", result " .. tostring(box.result))
			stored(uW).Lock = nil
			T.check(K.waitFor(function()
				return D.OwnsSave(pw) == true
			end, 60), "lock save wait: the lock freed: the recovery claims")
			leave(pw)
		end)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return {}
