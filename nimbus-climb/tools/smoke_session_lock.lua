-- smoke_session_lock.lua: the save session lock (docs/superpowers/specs/2026-11-10-session-lock-design.md; plan
-- docs/superpowers/plans/2026-11-10-session-lock.md Tasks 1 and 2). One server owns a player's save at a time: a Lock record
-- { Id, Job, Place, At } inside the save, claimed by one UpdateAsync at load, refreshed by every save and by a heartbeat,
-- honoured by every write, released by the leave save (and BindToClose: checked in smoke_server.lua's `shutdown`, the
-- last DataService scenario of the run, because Mock.Shutdown ends the autosave loop for every later scenario).
-- Loaded by tools/smoke.py in the server world (booted) and the client world (ARGS.context picks the half):
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
--   lock_receipts_cross  (Task 2, spec 11 / 13) a receipt while the save is held elsewhere answers NotProcessedYet, then
--                        PurchaseGranted once after the claim (saved with its receipt); a receipt the old server already
--                        stored grants nothing again; TutorialStarter across the hop (the stand-in decides no ask, A's
--                        grant arrives with the claim, ONE starter); duels and trophies made on the stand-in merge with
--                        the stored ones (a union, a delta)
--   lock_settle_flag     (Task 2, spec 12 / 18) Config.Gems.SettleSeconds is gone; a normal load is settled at once (no
--                        settle read, Settled once, the GemsSettled attribute); a held load is not settled (gem spin and
--                        gem Mix refused, nothing charged) until the recovery's claim, whose ProfileRebased listeners
--                        already see GemsSettled true; the two save-wait toasts (Main.server) in order, none for a
--                        normal join or during the wait; no usable store: settled at once
--   client_lock_loading  (Task 2, client world, spec 18) the loading screen's caption reads "Another server is still
--                        saving your progress..." while the player attribute SaveWaiting is true, "Loading the sky... N%"
--                        again once it is removed, and the screen still reaches Done on ProfileLoaded
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

	-- counts signal:Fire(player) for one user id until stop(); probe(player), when given, runs at each fire and its last
	-- answer is kept in box.saw
	local function countUid(signal, uid, probe)
		local box = { n = 0, saw = nil }
		local conn = signal:Connect(function(who)
			if who and who.UserId == uid then
				box.n = box.n + 1
				if probe then
					box.saw = probe(who)
				end
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

	local function reqModule(path)
		local inst = K.moduleInstance(path)
		local okReq, m = false, nil
		if inst then
			okReq, m = pcall(require, inst)
		end
		return okReq and type(m) == "table" and m or nil
	end

	-- the two save-wait toasts (spec 18; Main.server's "Save wait toasts" step) a user got since `mark`, in order
	local SAVING_TEXT = "Your progress is still being saved by another server. Your pets and gems will show up in a moment."
	local BACK_TEXT = "Your progress is back!"
	local function waitToasts(uid, mark)
		local out = {}
		for _, e in ipairs(K.remotesFor("Notify", uid, mark)) do
			local args = type(e.args) == "table" and e.args or {}
			if args[1] == SAVING_TEXT or args[1] == BACK_TEXT then
				out[#out + 1] = { text = args[1], kind = args[2], secs = args[3] }
			end
		end
		return out
	end
	local function showToasts(list)
		local parts = {}
		for _, t in ipairs(list) do
			parts[#parts + 1] = string.format("%q %s %s", t.text, tostring(t.kind), tostring(t.secs))
		end
		return #parts .. " toasts: " .. table.concat(parts, "; ")
	end

	-- one call of `fn(...)` on its own thread: box.done / box.ok / box.result
	local function spawnCall(fn, ...)
		local box = { done = false }
		local args = { n = select("#", ...), ... }
		task.spawn(function()
			local ok, result = pcall(fn, unpack(args, 1, args.n))
			box.ok, box.result, box.done = ok, result, true
		end)
		return box
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

	----------------------------------------------------------------------------------------------------
	-- lock_receipts_cross (Task 2): receipts and the cross-server pieces under the lock
	----------------------------------------------------------------------------------------------------
	S.lock_receipts_cross = guarded("lock_receipts_cross", function()
		if not K.needBoot() then
			return
		end
		local Config = config()
		local D = DS()
		local GS = reqModule("server/Services/GemService")
		local TSv = mod("TutorialService")
		local Steps = reqModule("shared/TutorialSteps")
		local G = Config.Gems
		local PolS = game:GetService("PolicyService")
		local modes = {} -- [userId] = "restrict" (any other: allowed)
		local savedIds = {}
		for i, pk in ipairs(G.Products) do
			savedIds[i] = pk.Id
		end
		run("lock_receipts_cross", function(players)
			if not T.check(type(D.OwnsSave) == "function" and GS ~= nil and type(GS.ProcessReceipt) == "function" and TSv ~= nil and Steps ~= nil,
				"lock receipts: (setup) DataService.OwnsSave, GemService.ProcessReceipt, TutorialService and TutorialSteps load") then
				return
			end
			local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
			local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
			local okBody, errBody = pcall(function()
				local pack = G.Products[2]
				pack.Id = 4400002 -- the owner pasted this pack's product id (restored after the scenario)
				local function receipt(uid, purchaseId)
					return { PlayerId = uid, PurchaseId = purchaseId, ProductId = pack.Id, CurrencySpent = pack.Robux or 1, PlaceIdWherePurchased = 1 }
				end
				local function decide(info)
					local box = spawnCall(GS.ProcessReceipt, info)
					K.waitFor(function()
						return box.done
					end, 60)
					if not box.done then
						return "unfinished"
					end
					return box.ok and box.result or ("error: " .. tostring(box.result))
				end

				-- a receipt while the save is held elsewhere: NotProcessedYet, then granted once after the claim
				local uid = newUserId()
				seed(uid, oldRecord({ Gems = 0, Lock = foreign("server-A") }))
				local p = add("LockReceipt", uid)
				players[#players + 1] = p
				advance(0.5)
				local box = spawnCall(GS.ProcessReceipt, receipt(uid, "lock-r1"))
				advance(13.6) -- GemService waits ProfileWaitSeconds (12) in 0.5 s polls (each resumes on a mock frame: a little later)
				T.check(box.done == true and box.ok == true and box.result == NOT_YET, "lock receipts: a receipt while the save is held elsewhere answers NotProcessedYet",
					"done " .. tostring(box.done) .. ", " .. tostring(box.result))
				T.check(D.IsProvisional(p) == true and D.GetGems(p) == 0, "lock receipts: ...nothing granted on the stand-in", "gems " .. tostring(D.GetGems(p)))
				T.check(lockId(uid) == "server-A" and (stored(uid) or {}).GemReceipts == nil, "lock receipts: ...and the held record untouched")
				stored(uid).Lock = nil -- A's leave save landed
				advance(20) -- the first recovery claims
				T.eq(D.OwnsSave(p), true, "lock receipts: (setup) A's release: the recovery claimed")
				T.eq(decide(receipt(uid, "lock-r1")), GRANTED, "lock receipts: Roblox asks again after the claim: PurchaseGranted")
				T.eq(D.GetGems(p), pack.Gems, "lock receipts: ...the pack's " .. tostring(pack.Gems) .. " gems are granted")
				local rec = stored(uid) or {}
				T.check(type(rec.GemReceipts) == "table" and rec.GemReceipts["lock-r1"] ~= nil and rec.Gems == pack.Gems,
					"lock receipts: ...saved with its receipt before PurchaseGranted", "stored gems " .. tostring(rec.Gems))
				T.check(decide(receipt(uid, "lock-r1")) == GRANTED and D.GetGems(p) == pack.Gems, "lock receipts: the same receipt a third time: PurchaseGranted, granted once")
				leave(p)

				-- a receipt the old server already stored is never granted again here
				local u2 = newUserId()
				seed(u2, oldRecord({ Gems = 300, GemReceipts = { ["lock-r2"] = os.time() - 30 } }))
				local p2 = join("LockReceipt", u2)
				players[#players + 1] = p2
				T.eq(D.OwnsSave(p2), true, "lock receipts: (setup) the second buyer's record is claimed")
				T.check(decide(receipt(u2, "lock-r2")) == GRANTED and D.GetGems(p2) == 300, "lock receipts: a receipt the old server already stored answers PurchaseGranted and grants nothing again",
					"gems " .. tostring(D.GetGems(p2)))
				leave(p2)

				-- TutorialStarter across the hop: A granted the starter and still holds the record
				local ASK, PET = "TutorialStarter", "pebble_pup"
				local SPIN = Steps.IndexOf and Steps.IndexOf.spin
				PolS.GetPolicyInfoForPlayerAsync = function(_, who)
					return { ArePaidRandomItemsRestricted = modes[who.UserId] == "restrict", IsPaidItemTradingAllowed = true }
				end
				local function petCount(who)
					local prof = D.GetProfile(who)
					return prof and (prof.Pets[PET] or 0) or -1
				end
				local function onSpinStep(who)
					D.SetTutorial(who, { Step = SPIN, Done = false, Gifted = true })
					TSv.Reload(who)
					advance(1.2)
				end
				local uT = newUserId()
				modes[uT] = "restrict"
				seed(uT, oldRecord({ Trove = { [ASK] = true }, Pets = { [PET] = 1 }, Tutorial = { Step = SPIN, Done = false, Gifted = true }, Lock = foreign("server-A") }))
				local pt = add("LockStarter", uT)
				players[#players + 1] = pt
				advance(12.6)
				T.eq(D.IsProvisional(pt), true, "lock starter: the restricted account's save is held: provisional after the wait")
				onSpinStep(pt)
				T.check(petCount(pt) == 0 and D.MarkTrove(pt, ASK, nil) == false, "lock starter: the stand-in grants nothing: no ask decided before A's write is read",
					"pets " .. tostring(petCount(pt)))
				stored(uT).Lock = nil -- A's write lands (its release)
				advance(20)
				local trove = D.GetTrove(pt)
				T.check(D.OwnsSave(pt) == true and type(trove) == "table" and trove[ASK] == true and petCount(pt) == 1, "lock starter: A's grant arrived with the claim (the ask, ONE " .. PET .. ")",
					"pets " .. tostring(petCount(pt)))
				onSpinStep(pt)
				advance(1.5)
				T.eq(petCount(pt), 1, "lock starter: ...the step again on this server: still ONE starter (the twin rule)")
				leave(pt)
				local recT = stored(uT) or {}
				T.check(type(recT.Pets) == "table" and recT.Pets[PET] == 1 and type(recT.Trove) == "table" and recT.Trove[ASK] == true, "lock starter: ...and the store holds it once")
				PolS.GetPolicyInfoForPlayerAsync = nil

				-- duels and trophies across the hop
				local uB = newUserId()
				seed(uB, oldRecord({ Battle = { Trophies = 10, Duels = { { U = 555, T = os.time() - 60 } } }, Lock = foreign("server-A") }))
				local pb = add("LockDuel", uB)
				players[#players + 1] = pb
				advance(12.6)
				local since = os.time() - 3600
				T.eq(D.IsProvisional(pb), true, "lock duels: (setup) held after the wait: provisional")
				T.eq(D.DuelsWith(pb, 555, since), 0, "lock duels: the stand-in knows no duels yet")
				T.eq(D.RecordDuel(pb, 777, os.time()), true, "lock duels: RecordDuel is allowed while provisional (a union)")
				local okT, totalT = D.AddTrophies(pb, 5)
				T.check(okT == true and totalT == 5, "lock duels: AddTrophies is allowed while provisional (a delta: 0 + 5 on the stand-in)", tostring(totalT))
				stored(uB).Lock = nil
				advance(20)
				T.check(D.OwnsSave(pb) == true and D.DuelsWith(pb, 555, since) == 1 and D.DuelsWith(pb, 777, since) == 1, "lock duels: after the claim the merge kept both duels (A's 555, this server's 777)",
					tostring(D.DuelsWith(pb, 555, since)) .. " / " .. tostring(D.DuelsWith(pb, 777, since)))
				T.eq(select(2, D.AddTrophies(pb, 0)), 15, "lock duels: ...and the trophies are 10 + 5")
				leave(pb)
				local recB = stored(uB) or {}
				T.eq(type(recB.Battle) == "table" and recB.Battle.Trophies or nil, 15, "lock duels: ...saved at the leave")
			end)
			PolS.GetPolicyInfoForPlayerAsync = nil
			for i, pk in ipairs(G.Products) do
				pk.Id = savedIds[i]
			end
			if not okBody then
				error(errBody, 0)
			end
		end)
	end)

	----------------------------------------------------------------------------------------------------
	-- lock_settle_flag (Task 2): the gem settle hold retired into the lock's flag
	----------------------------------------------------------------------------------------------------
	S.lock_settle_flag = guarded("lock_settle_flag", function()
		if not K.needBoot() then
			return
		end
		local Config = config()
		local D = DS()
		run("lock_settle_flag", function(players)
			T.eq(type(Config.Gems) == "table" and Config.Gems.SettleSeconds or nil, nil, "lock flag: Config.Gems.SettleSeconds is gone (the 15 s gem settle hold is retired)")
			if not T.check(type(D.GemsSettled) == "function" and type(D._SettleForTest) == "function" and type(D.Settled) == "table" and type(D.Settled.Connect) == "function"
				and type(D.OwnsSave) == "function", "lock flag: GemsSettled, _SettleForTest and the Settled signal stay (OwnsSave beside them)") then
				return
			end
			local ATTR = Config.Attr.GemsSettled or "GemsSettled"
			local function flagText(Dx, who)
				return "GemsSettled " .. tostring(Dx.GemsSettled(who)) .. ", attribute " .. tostring(who:GetAttribute(ATTR))
			end
			startWatch()

			-- a normal load is settled at once: no settle read, Settled once, the attribute
			local uid = newUserId()
			seed(uid, oldRecord({ Gems = 50 }))
			local fires = countUid(D.Settled, uid)
			local mark = K.logSize()
			local p = join("LockFlag", uid)
			players[#players + 1] = p
			T.check(D.GemsSettled(p) == true and p:GetAttribute(ATTR) == true and fires.n == 1, "lock flag: a normal load is settled at once (GemsSettled, the attribute, Settled fired once)",
				flagText(D, p) .. ", fires " .. fires.n)
			T.eq(calls(uid), 1, "lock flag: ...no settle read: ONE store call (the claim) for the whole load")
			T.eq(D._SettleForTest(p), true, "lock flag: _SettleForTest answers OwnsSave (true) and reads nothing")
			T.eq(calls(uid), 1, "lock flag: ...still one store call")
			T.eq(D._SettleForTest(nil), false, "lock flag: _SettleForTest(nil) answers false")
			advance(30)
			T.eq(fires.n, 1, "lock flag: Settled never fires twice for one load")
			T.eq(#waitToasts(uid, mark), 0, "lock flag: no save-wait toast for a normal join")
			fires.stop()
			leave(p)

			-- a held load is not settled; the claim through the recovery settles it (ProfileRebased listeners see true)
			local uH = newUserId()
			seed(uH, oldRecord({ Gems = 80, Lock = foreign("server-A") }))
			local firesH = countUid(D.Settled, uH)
			local rebasedH = countUid(D.ProfileRebased, uH, function(who)
				return D.GemsSettled(who)
			end)
			local markH = K.logSize()
			local ph = add("LockFlagHeld", uH)
			players[#players + 1] = ph
			advance(6)
			T.eq(#waitToasts(uH, markH), 0, "lock flag toasts: no toast while the load waits (the loading screen's caption covers it)")
			advance(6.6)
			T.check(D.IsProvisional(ph) == true and D.GemsSettled(ph) == false and ph:GetAttribute(ATTR) == nil and firesH.n == 0,
				"lock flag: a held load (provisional) is not settled: GemsSettled false, no attribute, no Settled", flagText(D, ph) .. ", fires " .. firesH.n)
			T.eq(D._SettleForTest(ph), false, "lock flag: ...and _SettleForTest answers false")
			local held = waitToasts(uH, markH)
			T.check(#held == 1 and held[1].text == SAVING_TEXT and held[1].kind == "info" and held[1].secs == 6,
				"lock flag toasts: the provisional-held play began: ONE \"still being saved\" toast (info, 6 s)", showToasts(held))
			local PetS = mod("PetService")
			local F = mod("FusionService") or reqModule("server/Services/FusionService")
			D.AddGems(ph, 100)
			local gems0 = D.GetGems(ph)
			local okSpin, whySpin = PetS.BuyRoulette(ph, "Cloud", "Gems")
			T.check(okSpin == false and whySpin == "Your data is still loading", "lock flag: a gem spin on the held stand-in is refused 'Your data is still loading'", tostring(whySpin))
			if F and type(F.Mix) == "function" then
				local okMix, whyMix = F.Mix(ph, "pebble_pup", "cloudy_dragon")
				T.check(okMix == false and type(whyMix) == "string" and string.find(whyMix, "still loading", 1, true) ~= nil,
					"lock flag: a gem Mix on the held stand-in is refused (still loading)", tostring(whyMix))
			end
			T.eq(D.GetGems(ph), gems0, "lock flag: ...nothing charged")
			stored(uH).Lock = nil -- A's release
			advance(20)
			T.check(D.OwnsSave(ph) == true and D.GemsSettled(ph) == true and ph:GetAttribute(ATTR) == true and firesH.n == 1,
				"lock flag: the recovery's claim settles it (GemsSettled, the attribute, Settled once)", flagText(D, ph) .. ", fires " .. firesH.n)
			T.check(rebasedH.n == 1 and rebasedH.saw == true, "lock flag: ...ProfileRebased fired once and its listeners saw GemsSettled == true (the hold is gone)",
				rebasedH.n .. " fires, saw " .. tostring(rebasedH.saw))
			local both = waitToasts(uH, markH)
			T.check(#both == 2 and both[1].text == SAVING_TEXT and both[2].text == BACK_TEXT and both[2].kind == "good" and both[2].secs == 4,
				"lock flag toasts: ...then ONE \"Your progress is back!\" (good, 4 s), in that order", showToasts(both))
			T.eq(D.GetGems(ph), 80 + 100, "lock flag: ...the stored 80 gems plus the stand-in's +100 delta")
			advance(30)
			T.check(firesH.n == 1 and #waitToasts(uH, markH) == 2, "lock flag: no second Settled and no more toasts later")
			firesH.stop()
			rebasedH.stop()
			leave(ph)

			-- no usable store (Studio without API access): settled at once
			local uq = newUserId()
			local q = join("LockFlagNoApi", uq)
			players[#players + 1] = q
			local D2, _, release2 = secondServer("DataServiceLockFlagNoApi")
			if T.check(D2 ~= nil and type(D2.Load) == "function", "lock flag no store: a second DataService copy loads") then
				DSt.Unavailable = true
				local okLoad = pcall(D2.Load, q)
				local settled = D2.GemsSettled(q)
				DSt.Unavailable = false
				T.check(okLoad and settled == true, "lock flag no store: no usable store: GemsSettled true at once (nothing to own)", tostring(settled))
				pcall(D2.Release, q)
				T.check(release2() == true, "lock flag no store: the copy's hooks are dropped with it")
			end
			leave(q)
		end)
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local LocalPlayer = game:GetService("Players").LocalPlayer

	local function advance(seconds)
		if KC and KC.advance then
			KC.advance(seconds)
		else
			Mock.Advance(seconds)
		end
	end

	-- the loading screen's caption while another server still saves the player's progress (spec 18)
	S.client_lock_loading = guarded("client_lock_loading", function()
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local folder = ROOTS["first"] and Mock.GetPath(ROOTS["first"]) or nil
		local script = folder and folder:FindFirstChild("LoadingScreen") or nil
		if not T.check(script ~= nil and pg ~= nil, "lock loading: (setup) src/first/LoadingScreen.client.lua is mounted and the PlayerGui exists") then
			return
		end
		local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		local Config = shared and shared:FindFirstChild("Config") and require(shared.Config) or nil
		local LOADED = (Config and Config.Attr and Config.Attr.ProfileLoaded) or "ProfileLoaded"
		local WAIT = (Config and Config.Attr and Config.Attr.SaveWaiting) or "SaveWaiting"
		local wasLoaded = LocalPlayer:GetAttribute(LOADED)
		local okRun, errRun = pcall(function()
			LocalPlayer:SetAttribute(LOADED, nil)
			LocalPlayer:SetAttribute(WAIT, true)
			Mock.RunScript(script)
			advance(0.6)
			local gui = pg:FindFirstChild("NimbusLoading")
			local caption = gui and gui:FindFirstChild("Caption", true) or nil
			if not T.check(caption ~= nil, "lock loading: (setup) the loading screen and its caption are built") then
				return
			end
			T.eq(caption.Text, "Another server is still saving your progress...", "lock loading: while SaveWaiting is true the caption says another server is still saving")
			advance(2)
			T.eq(caption.Text, "Another server is still saving your progress...", "lock loading: ...and keeps saying it while the bar moves")
			T.check(gui:GetAttribute("Done") ~= true, "lock loading: ...not Done without the profile")
			LocalPlayer:SetAttribute(WAIT, nil)
			advance(0.5)
			T.check(string.find(caption.Text, "^Loading the sky%.%.%. %d+%%$") ~= nil, "lock loading: SaveWaiting removed: within 0.5 s the caption is back to 'Loading the sky... N%'", caption.Text)
			LocalPlayer:SetAttribute(LOADED, true)
			advance(0.5)
			T.eq(gui:GetAttribute("Done"), true, "lock loading: ProfileLoaded: the screen reaches Done as before")
			T.check(string.find(caption.Text, "100%", 1, true) ~= nil, "lock loading: ...the caption says 100%", caption.Text)
			advance(3)
			T.check(gui.Parent == nil, "lock loading: ...and the screen is gone after the fade")
		end)
		LocalPlayer:SetAttribute(WAIT, nil)
		LocalPlayer:SetAttribute(LOADED, wasLoaded == nil and true or wasLoaded)
		advance(3)
		if not okRun then
			error(errRun, 0)
		end
		if KC and KC.flushErrors then
			KC.flushErrors("client_lock_loading")
		end
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
