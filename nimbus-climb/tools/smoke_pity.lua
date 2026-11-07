-- smoke_pity.lua: the Secret pity record and the Fast hatch setting in the save (docs/superpowers/specs/
-- 2026-11-07-lobby-shop-design.md 5.2, 5.5 "Fast hatch", 6; plan docs/superpowers/plans/2026-11-07-lobby-shop.md
-- Task 2; later tasks of the same plan add the gem settle hold and the pity's money step here). Loaded by
-- tools/smoke.py in the server world and the client world (ARGS.context picks the half):
--   secret_pity_save          (server, booted) DataService's new top-level field Pity = { Secret = { Spins, Hit } }:
--                             GetPity / SetPity (a copy; nil and refused while provisional), the store round trip,
--                             KNOWN_TOP (the same session saved twice keeps its newest numbers), two servers (Spins a
--                             delta, Hit the max), the rebase paths (a save that finds another server's write, a
--                             recovered provisional load) bring the merged numbers into the live record, Hit never
--                             goes down, junk stored values cleaned, ResetFields clears it, an old record stays as it
--                             was (no Pity key, no Settings.FastHatch key) until the player uses the new thing, the
--                             FastHatch setting (booleans only, stored only when true), the ProfileSync snapshot
--                             (Settings.FastHatch, never Pity)
--   gem_settle                (server, booted; Task 3, part 1: the data layer) the gem settle hold after a load
--                             (spec 5.2 "The gem settle hold"): GemsSettled is false until Config.Gems.SettleSeconds have
--                             passed AND one settle read came back (attribute GemsSettled = true and Settled fired once
--                             then); a quiet read changes nothing (no rebase, no TeamsChanged, no snapshot); another
--                             server's save during the hold arrives through a rebase (ProfileRebased once, its listeners
--                             still see false); a failed read retries every 5 s; with no store it is settled at 15 s with
--                             no read; a provisional load waits for its recovery read (>= 20 s), which counts as the
--                             settle read; _SettleForTest settles at once; a gem Mix waits for the settle, a token Mix not
--   client_fasthatch_setting  (client) ClientSettings knows FastHatch (default false, booleans only, the 0.4 s debounce,
--                             one SettingsSet) and State.Settings() follows the snapshot's Settings.FastHatch
-- White-box: the booted helpers of smoke_server.lua; "server B" is a second copy of DataService against the same mock
-- store (the smoke_p7_data.lua secondServer shape). Deterministic: mock clock only. Plain Lua 5.1 syntax only.

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
	local ALLOWED_WARNINGS = { "[DataService]" }

	local function DS()
		return mod("DataService")
	end

	local userSeq = 0
	local function newUserId()
		userSeq = userSeq + 1
		return 987300 + userSeq
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

	local function storeKey(uid)
		return config().Tokens.DataStoreName .. "/u_" .. uid
	end

	local function stored(uid)
		return Mock.DataStore.Data[storeKey(uid)]
	end

	local function statsOf()
		return { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} }
	end

	-- a stored record written by an older build (no Pity, no FastHatch), plus the given top-level fields
	local function oldRecord(extra)
		local rec = { Version = 2, Tokens = 3, Pets = {}, Equipped = {}, Items = {}, Stats = statsOf() }
		for key, value in pairs(extra or {}) do
			rec[key] = value
		end
		return rec
	end

	local function count(map)
		local n = 0
		for _ in pairs(type(map) == "table" and map or {}) do
			n = n + 1
		end
		return n
	end

	-- "{ Spins, Hit }" of a GetPity answer, for the failure text
	local function show(pity)
		if type(pity) ~= "table" then
			return tostring(pity)
		end
		return "{ " .. tostring(pity.Spins) .. ", " .. tostring(pity.Hit) .. " } (" .. count(pity) .. " keys)"
	end

	-- a GetPity answer deep-equals { Spins = spins, Hit = hit } (exactly those two keys)
	local function pityIs(pity, spins, hit)
		return type(pity) == "table" and pity.Spins == spins and pity.Hit == hit and count(pity) == 2
	end

	-- the stored record's Pity.Secret deep-equals { Spins = spins, Hit = hit }
	local function storedPityIs(uid, spins, hit)
		local rec = stored(uid)
		local pity = type(rec) == "table" and rec.Pity or nil
		local secret = type(pity) == "table" and pity.Secret or nil
		return type(secret) == "table" and secret.Spins == spins and secret.Hit == hit and count(secret) == 2 and count(pity) == 1, show(secret)
	end

	local function provisional(D, p)
		return type(D.IsProvisional) == "function" and D.IsProvisional(p) == true
	end

	local function lastSnapshot(player, fromIndex)
		local list = K.remotesFor("ProfileSync", player.UserId, fromIndex or 0)
		local e = list[#list]
		return e and e.args[1] or nil
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

	-- a second, independent copy of DataService (own cache, same mock store): "another server"
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

	-- counts signal:Fire(player) calls for one player until the returned stop() is called
	local function countFires(signal, player)
		local box = { n = 0 }
		local conn = signal:Connect(function(who)
			if who == player then
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

	S.secret_pity_save = guarded("secret_pity_save", function()
		if not K.needBoot() then
			return
		end
		local D = DS()
		local DSt = Mock.DataStore
		if not T.check(type(D.GetPity) == "function" and type(D.SetPity) == "function", "pity save: DataService.GetPity / SetPity exist") then
			return
		end
		local B, cloneB, releaseB = secondServer("DataServicePityB")
		if not T.check(B ~= nil and type(B.GetPity) == "function", "pity save: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
			return
		end
		local players = {}
		local okRun, errRun = pcall(function()
			-- a fresh join: the zero record, as a copy
			local uid = newUserId()
			local p = join("PitySave", uid)
			players[#players + 1] = p
			local fresh = D.GetPity(p)
			T.check(pityIs(fresh, 0, 0), "pity save: a fresh join answers GetPity = { Spins = 0, Hit = 0 }", show(fresh))
			if type(fresh) == "table" then
				fresh.Spins = 99
			end
			T.check(pityIs(D.GetPity(p), 0, 0), "pity save: GetPity answers a copy (editing it changes nothing)", show(D.GetPity(p)))
			T.check(D.SetPity(nil, 1, 0) == false, "pity save: SetPity refuses a nil player")
			local junk = {}
			for _, case in ipairs({ { "x", 0 }, { 1, "y" }, { -1, 0 }, { 1, -1 }, { 1.5, 0 }, { 2, 0.5 }, { 2e9, 0 }, { 0 / 0, 0 }, { 1 / 0, 0 }, { nil, 0 }, { {}, 0 } }) do
				if D.SetPity(p, case[1], case[2]) ~= false then
					junk[#junk + 1] = tostring(case[1]) .. "/" .. tostring(case[2])
				end
			end
			T.check(#junk == 0 and pityIs(D.GetPity(p), 0, 0), "pity save: SetPity refuses junk numbers and writes nothing", table.concat(junk, ", ") .. " -> " .. show(D.GetPity(p)))
			D.AddTokens(p, 1)
			T.eq(D.Save(p), true, "pity save: (setup) a save of an untouched pity")
			T.check(type(stored(uid)) == "table" and stored(uid).Pity == nil, "pity save: a 0 / 0 pity stays out of the store")

			-- SetPity, save, a fresh load
			T.eq(D.SetPity(p, 6, 0), true, "pity save: SetPity(p, 6, 0) answers true")
			T.check(pityIs(D.GetPity(p), 6, 0), "pity save: ...and the live record is { 6, 0 }", show(D.GetPity(p)))
			T.eq(D.Save(p), true, "pity save: the pity-only change saves (diffProfiles / isEmptyDelta see it)")
			local okStored, what = storedPityIs(uid, 6, 0)
			T.check(okStored, "pity save: the store holds Pity.Secret = { Spins = 6, Hit = 0 }", what)
			B.Load(p)
			advance(0.2)
			T.check(pityIs(B.GetPity(p), 6, 0), "pity save: a fresh load (server B) reads { 6, 0 }", show(B.GetPity(p)))

			-- KNOWN_TOP: the same session saved twice keeps its newest numbers (keepForeign must not copy the old Pity back)
			T.check(D.SetPity(p, 7, 7) == true and D.Save(p) == true, "pity save: the same session sets { 7, 7 } and saves again")
			okStored, what = storedPityIs(uid, 7, 7)
			T.check(okStored, "pity save: the store holds { 7, 7 } (Pity is a known top-level field)", what)
			leave(p)
			local back = join("PitySave", uid)
			players[#players + 1] = back
			T.check(pityIs(D.GetPity(back), 7, 7), "pity save: a rejoin (a fresh load) reads { 7, 7 }", show(D.GetPity(back)))

			-- Hit never goes down
			T.eq(D.SetPity(back, 9, 1), true, "pity save: SetPity(p, 9, 1) after Hit 7 answers true")
			T.check(pityIs(D.GetPity(back), 9, 7), "pity save: ...Spins 9, Hit stays 7 (never below the live Hit)", show(D.GetPity(back)))

			-- ResetFields (the developer reset) writes the session's pity over the store: the caller zeroes the live record
			T.eq(D.Save(back), true, "pity save: (setup) { 9, 7 } saved")
			D.GetProfile(back).Pity = { Secret = { Spins = 0, Hit = 0 } } -- the dev tools change the live values themselves
			T.eq(D.ResetFields(back, { Pity = true }), true, "pity save: ResetFields(p, { Pity = true }) is recorded (Pity is overwritable)")
			T.eq(D.Save(back), true, "pity save: the reset saves")
			T.check(type(stored(uid)) == "table" and stored(uid).Pity == nil, "pity save: after the reset the stored record has no Pity", show(stored(uid) and stored(uid).Pity))
			T.check(pityIs(D.GetPity(back), 0, 0), "pity save: ...and the live record is { 0, 0 }", show(D.GetPity(back)))
			leave(back)

			-- two servers on one store, both loaded at { 2, 0 }: Spins travel as a delta, Hit as the max
			local uid2 = newUserId()
			DSt.Data[storeKey(uid2)] = oldRecord({ Pity = { Secret = { Spins = 2, Hit = 0 } } })
			local q = join("PityTwo", uid2)
			players[#players + 1] = q
			B.Load(q)
			advance(0.2)
			T.check(pityIs(D.GetPity(q), 2, 0) and pityIs(B.GetPity(q), 2, 0), "pity two servers: A and B both loaded { 2, 0 }", show(D.GetPity(q)) .. " / " .. show(B.GetPity(q)))
			T.check(D.SetPity(q, 4, 4) == true and D.Save(q) == true, "pity two servers: A spins twice (the 2nd a Secret: { 4, 4 }) and saves")
			okStored, what = storedPityIs(uid2, 4, 4)
			T.check(okStored, "pity two servers: the store holds A's { 4, 4 }", what)
			local rebasedB = countFires(B.ProfileRebased, q)
			T.check(B.SetPity(q, 3, 0) == true and B.Save(q) == true, "pity two servers: B (still at { 2, 0 }) spins once ({ 3, 0 }) and saves")
			advance(0.3)
			rebasedB.stop()
			okStored, what = storedPityIs(uid2, 5, 4)
			T.check(okStored, "pity two servers: stored Spins 2 + 2 + 1 = 5, Hit max(4, 0) = 4 (B's save did not replace A's Spins)", what)
			T.check(pityIs(B.GetPity(q), 5, 4), "pity rebase: B's save found A's write, so B's live record is the merged { 5, 4 }", show(B.GetPity(q)))
			T.check(rebasedB.n >= 1, "pity rebase: ...and B fired ProfileRebased", tostring(rebasedB.n) .. " fires")
			leave(q)

			-- one quiet server: B is a bare copy (no service ticks its profile), so each of its saves carries only the change
			-- under test. A pity-only change must be written (isEmptyDelta), and a save that finds only another server's pity
			-- write must adopt it (profilesEqual compares Pity, so the live count never stays stale)
			local uid6 = newUserId()
			DSt.Data[storeKey(uid6)] = oldRecord()
			local w = join("PityQuiet", uid6)
			players[#players + 1] = w
			B.Load(w)
			advance(0.2)
			T.eq(B.Save(w), true, "pity quiet server: (setup) B's first save (the markers of its own load)")
			T.check(B.SetPity(w, 1, 0) == true and B.Save(w) == true, "pity quiet server: B spins once ({ 1, 0 }) and saves")
			okStored, what = storedPityIs(uid6, 1, 0)
			T.check(okStored, "pity quiet server: a pity-only change is written (the delta is not empty)", what)
			local quiet = DSt.Data[storeKey(uid6)]
			quiet.Pity = { Secret = { Spins = 4, Hit = 4 } } -- another server's spins land in the store
			local rebasedQ = countFires(B.ProfileRebased, w)
			B.AddTokens(w, 1)
			T.eq(B.Save(w), true, "pity quiet server: B saves a token (its copy still says { 1, 0 })")
			advance(0.3)
			rebasedQ.stop()
			T.check(pityIs(B.GetPity(w), 4, 4), "pity quiet server: the save found the other server's { 4, 4 } and B's live record adopted it", show(B.GetPity(w)))
			T.check(rebasedQ.n >= 1, "pity quiet server: ...through a rebase (ProfileRebased fired)", tostring(rebasedQ.n) .. " fires")
			okStored, what = storedPityIs(uid6, 4, 4)
			T.check(okStored, "pity quiet server: ...and the store keeps { 4, 4 }", what)
			leave(w)

			-- a provisional (failed) load: no read, no write; the recovery brings another server's numbers in
			local uid3 = newUserId()
			DSt.Data[storeKey(uid3)] = oldRecord({ Pity = { Secret = { Spins = 1, Hit = 0 } } })
			DSt.Fail = true
			local r = Mock.AddPlayer("PityProv" .. tostring(uid3 % 1000), uid3)
			players[#players + 1] = r
			advance(4)
			if T.check(D.GetProfile(r) ~= nil and provisional(D, r), "pity provisional: (precondition) the load failed while the store is reachable") then
				T.eq(D.GetPity(r), nil, "pity provisional: GetPity answers nil while provisional")
				T.eq(D.SetPity(r, 1, 0), false, "pity provisional: SetPity(p, 1, 0) is refused while provisional")
				local standIn = D.GetProfile(r).Pity
				T.check(type(standIn) == "table" and type(standIn.Secret) == "table" and standIn.Secret.Spins == 0 and standIn.Secret.Hit == 0,
					"pity provisional: ...the stand-in record keeps its zero Pity", show(type(standIn) == "table" and standIn.Secret or standIn))
				DSt.Fail = false
				B.Load(r)
				advance(0.2)
				T.check(B.SetPity(r, 2, 2) == true and B.Save(r) == true, "pity provisional: meanwhile server B spins a Secret ({ 2, 2 }) and saves")
				local rebasedA = countFires(D.ProfileRebased, r)
				T.check(K.waitFor(function()
					return not provisional(D, r)
				end, 40), "pity provisional: (the recovery reads the real save)")
				advance(0.5)
				rebasedA.stop()
				T.check(pityIs(D.GetPity(r), 2, 2), "pity provisional: after the recovery GetPity answers B's { 2, 2 } (replaceContents carries Pity)", show(D.GetPity(r)))
				T.check(rebasedA.n >= 1, "pity provisional: ...and ProfileRebased fired", tostring(rebasedA.n) .. " fires")
				T.eq(D.SetPity(r, 3, 2), true, "pity provisional: ...and SetPity works on the real record")
			end
			DSt.Fail = false
			leave(r)

			-- junk stored values are cleaned on load
			for _, case in ipairs({
				{ { Secret = { Spins = "x", Hit = 9 } }, 0, 0, "Spins 'x', Hit 9" },
				{ { Secret = { Spins = 3, Hit = 5 } }, 3, 3, "Spins 3, Hit 5 (Hit <= Spins)" },
				{ { Secret = { Spins = 2e9 } }, 0, 0, "Spins 2e9 (out of range)" },
				{ { Secret = { Spins = 2.5, Hit = -1 } }, 0, 0, "Spins 2.5, Hit -1" },
				{ { Secret = 4 }, 0, 0, "Secret = 4" },
				{ "bad", 0, 0, "Pity = 'bad'" },
			}) do
				local uidJ = newUserId()
				DSt.Data[storeKey(uidJ)] = oldRecord({ Pity = case[1] })
				local j = join("PityJunk", uidJ)
				T.check(pityIs(D.GetPity(j), case[2], case[3]), "pity junk: stored " .. case[4] .. " loads as { " .. case[2] .. ", " .. case[3] .. " }", show(D.GetPity(j)))
				leave(j)
			end

			-- an old record (no Pity, no FastHatch) stays as it was until the player uses the new thing
			local uid4 = newUserId()
			DSt.Data[storeKey(uid4)] = oldRecord()
			local o = join("PityOld", uid4)
			players[#players + 1] = o
			D.AddCash(o, 25)
			T.eq(D.Save(o), true, "pity old record: load, change Cash, save")
			local rec = stored(uid4) or {}
			T.check(rec.Pity == nil and rec.Settings == nil, "pity old record: (default Settings) no Pity key and no Settings key after the save", tostring(rec.Pity) .. " / " .. tostring(rec.Settings))
			T.eq(D.SetSetting(o, "FastHatch", true), true, "pity old record: SetSetting(p, 'FastHatch', true) answers true")
			T.eq(D.GetSettings(o).FastHatch, true, "pity old record: ...GetSettings shows FastHatch = true")
			T.eq(D.Save(o), true, "pity old record: ...saved")
			rec = stored(uid4) or {}
			T.check(type(rec.Settings) == "table" and rec.Settings.FastHatch == true, "pity old record: the store holds Settings.FastHatch = true")
			T.check(D.SetSetting(o, "FastHatch", false) == true and D.Save(o) == true, "pity old record: FastHatch back to false, saved")
			rec = stored(uid4) or {}
			T.check(rec.Settings == nil, "pity old record: ...with every other setting default the Settings key is gone again", tostring(rec.Settings))
			leave(o)

			local uid5 = newUserId()
			local oldSettings = { Music = 2, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 0, MouseLock = true }
			DSt.Data[storeKey(uid5)] = oldRecord({ Settings = oldSettings })
			local m = join("PityMusic", uid5)
			players[#players + 1] = m
			D.AddCash(m, 25)
			T.eq(D.Save(m), true, "pity old record (Music 2): load, change Cash, save")
			rec = stored(uid5) or {}
			local same = type(rec.Settings) == "table" and count(rec.Settings) == count(oldSettings)
			for key, value in pairs(oldSettings) do
				same = same and rec.Settings[key] == value
			end
			T.check(rec.Pity == nil and same and rec.Settings.FastHatch == nil, "pity old record (Music 2): no Pity key; Settings exactly as stored (no FastHatch key)",
				"Settings keys " .. count(rec.Settings) .. ", FastHatch " .. tostring(type(rec.Settings) == "table" and rec.Settings.FastHatch))
			T.check(D.SetSetting(m, "FastHatch", "yes") == false and D.SetSetting(m, "FastHatch", 1) == false and D.GetSettings(m).FastHatch == false,
				"pity fast hatch: SetSetting refuses 'yes' and 1 (booleans only)")
			T.eq(D.Save(m), true, "pity fast hatch: (a save after the refusals)")
			rec = stored(uid5) or {}
			T.check(type(rec.Settings) == "table" and rec.Settings.FastHatch == nil and rec.Settings.Music == 2, "pity fast hatch: ...nothing stored")
			T.check(D.SetSetting(m, "FastHatch", true) == true and D.Save(m) == true, "pity fast hatch: FastHatch true, saved")
			rec = stored(uid5) or {}
			T.check(type(rec.Settings) == "table" and rec.Settings.FastHatch == true and rec.Settings.Music == 2, "pity fast hatch: the store holds FastHatch = true next to Music 2")
			T.check(D.SetSetting(m, "FastHatch", false) == true and D.Save(m) == true, "pity fast hatch: back to false, saved")
			rec = stored(uid5) or {}
			T.check(type(rec.Settings) == "table" and rec.Settings.FastHatch == nil and rec.Settings.Music == 2 and count(rec.Settings) == count(oldSettings),
				"pity fast hatch: ...the FastHatch key is gone, the other settings stay", "keys " .. count(rec.Settings))

			-- the ProfileSync snapshot: Settings.FastHatch always, Pity never
			D.SetPity(m, 1, 0)
			local mark = K.logSize()
			D.Sync(m)
			local snap = lastSnapshot(m, mark)
			T.check(type(snap) == "table" and type(snap.Settings) == "table" and snap.Settings.FastHatch == false, "pity snapshot: ProfileSync carries Settings.FastHatch = false",
				tostring(type(snap) == "table" and type(snap.Settings) == "table" and snap.Settings.FastHatch))
			T.check(type(snap) == "table" and snap.Pity == nil, "pity snapshot: ...and no Pity key (the attribute and the reply carry it)")
			leave(m)
		end)
		DSt.Fail = false
		for _, p in ipairs(players) do
			if p.Parent then
				Mock.RemovePlayer(p)
			end
		end
		advance(12)
		T.check(releaseB() == true, "pity save: server B's hooks are dropped with it")
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("secret_pity_save")
		K.flushWarnings("secret_pity_save", ALLOWED_WARNINGS)
	end)

	-- counts signal:Fire(player) calls for one user id (connected before the Player exists) until stop(); probe(player),
	-- when given, runs at each fire and its last answer is kept in box.saw
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

	S.gem_settle = guarded("gem_settle", function()
		if not K.needBoot() then
			return
		end
		local D = DS()
		local DSt = Mock.DataStore
		local Config = config()
		if not T.check(type(D.GemsSettled) == "function" and type(D._SettleForTest) == "function" and type(D.Settled) == "table" and type(D.Settled.Connect) == "function",
			"gem settle: DataService.GemsSettled / _SettleForTest and the Settled signal exist") then
			return
		end
		T.eq(Config.Gems and Config.Gems.SettleSeconds, 15, "gem settle: Config.Gems.SettleSeconds = 15")
		T.eq(Config.Attr.GemsSettled, "GemsSettled", "gem settle: Config.Attr.GemsSettled = 'GemsSettled'")
		local ATTR = Config.Attr.GemsSettled or "GemsSettled"
		local function advanceTo(t)
			local left = t - os.clock()
			if left > 0 then
				advance(left)
			end
		end
		local function settledText(Dx, p)
			return "GemsSettled " .. tostring(Dx.GemsSettled(p)) .. ", attribute " .. tostring(p:GetAttribute(ATTR))
		end
		local B, cloneB, releaseB = secondServer("DataServiceSettleB")
		if not T.check(B ~= nil and type(B.Load) == "function", "gem settle: a second copy of DataService loads as 'the old server'", tostring(cloneB)) then
			return
		end
		local players, counters = {}, {}
		local function counter(signal, uid, probe)
			local box = countUid(signal, uid, probe)
			counters[#counters + 1] = box
			return box
		end
		local function settledProbe(who)
			return D.GemsSettled(who)
		end
		local okRun, errRun = pcall(function()
			------------------------------------------------------------------------------------------------
			-- one timeline, four players joined together: a quiet settle (p), a server hop whose old server saves 8 s
			-- after the load (q), _SettleForTest (w), the gem Mix (f)
			------------------------------------------------------------------------------------------------
			local uidP, uidQ, uidW, uidF = newUserId(), newUserId(), newUserId(), newUserId()
			DSt.Data[storeKey(uidP)] = oldRecord({ Gems = 300 })
			DSt.Data[storeKey(uidQ)] = oldRecord({ Gems = 300 })
			local firesP, firesQ, firesW, firesF = counter(D.Settled, uidP), counter(D.Settled, uidQ), counter(D.Settled, uidW), counter(D.Settled, uidF)
			local rebasedP, teamsP = counter(D.ProfileRebased, uidP), counter(D.TeamsChanged, uidP)
			local rebasedQ = counter(D.ProfileRebased, uidQ, settledProbe)
			local t0 = os.clock()
			local p = Mock.AddPlayer("SettleQuiet" .. tostring(uidP % 1000), uidP)
			local q = Mock.AddPlayer("SettleHop" .. tostring(uidQ % 1000), uidQ)
			local w = Mock.AddPlayer("SettleTest" .. tostring(uidW % 1000), uidW)
			local f = Mock.AddPlayer("SettleMix" .. tostring(uidF % 1000), uidF)
			players[#players + 1], players[#players + 2], players[#players + 3], players[#players + 4] = p, q, w, f
			B.Load(q) -- the old server still holds q (a hop: its leave save is not in yet)
			advance(1.2)
			T.check(D.GemsSettled(p) == false and p:GetAttribute(ATTR) == nil, "gem settle: right after the join GemsSettled is false and the GemsSettled attribute is absent", settledText(D, p))
			T.check(D.GetGems(q) == 300 and B.GetGems(q) == 300, "gem settle hop: (setup) both servers loaded the stored 300 gems", tostring(D.GetGems(q)) .. " / " .. tostring(B.GetGems(q)))

			-- _SettleForTest: the settle read now, no 15 s wait
			T.eq(D.GemsSettled(w), false, "gem settle test hook: (before) not settled")
			T.eq(D._SettleForTest(w), true, "gem settle test hook: _SettleForTest(p) right after a join answers true")
			T.check(D.GemsSettled(w) == true and w:GetAttribute(ATTR) == true and firesW.n == 1, "gem settle test hook: ...settled at once (attribute GemsSettled = true, Settled fired once)",
				settledText(D, w) .. ", fires " .. firesW.n)
			T.eq(D._SettleForTest(nil), false, "gem settle test hook: _SettleForTest(nil) answers false")

			-- the gem Mix waits for the settle; a token Mix does not
			local function req(path)
				local inst = K.moduleInstance(path)
				local okReq, m = false, nil
				if inst then
					okReq, m = pcall(require, inst)
				end
				return okReq and type(m) == "table" and m or nil
			end
			local F = mod("FusionService") or req("server/Services/FusionService")
			local TC = req("shared/TycoonCatalog")
			local PK = req("shared/PetKeys")
			if T.check(F and type(F.Mix) == "function" and TC and PK, "gem settle mix: FusionService, TycoonCatalog and PetKeys load") then
				D.MutateHome(f, function(h)
					h.Prestige = 1
					h.Stations.FusionMachine = 1
				end)
				local prof = D.GetProfile(f)
				for _, id in ipairs({ "pip_penguin", "maple_fox", "pebble_pup", "cloudy_dragon" }) do
					PK.Add(prof, id, 1)
				end
				D.MarkDirty(f)
				local gemCost = TC.Fusion.Mix.Mythic.Gems
				T.check(type(gemCost) == "number" and (TC.FusionCost("Mix", "Mythic", nil, 1) or {}).Gems == gemCost, "gem settle mix: (setup) a Mythic Mix costs TycoonCatalog.Fusion.Mix.Mythic.Gems", tostring(gemCost))
				D.AddTokens(f, 1000000)
				D.AddGems(f, gemCost)
				local okT, keyT = F.Mix(f, "pip_penguin", "maple_fox")
				T.check(okT == true and D.GemsSettled(f) == false, "gem settle mix: a token Mix before the settle mixes", tostring(keyT))
				local gems0, hybrids0 = D.GetGems(f), count(prof.Hybrids)
				local okG, whyG = F.Mix(f, "pebble_pup", "cloudy_dragon")
				T.check(okG == false and whyG == "Your data is still loading", "gem settle mix: a Mythic gem Mix before the settle is refused 'Your data is still loading'", tostring(okG) .. " " .. tostring(whyG))
				T.check(D.GetGems(f) == gems0 and PK.Count(prof, "pebble_pup") == 1 and PK.Count(prof, "cloudy_dragon") == 1 and count(prof.Hybrids) == hybrids0,
					"gem settle mix: ...gems and pets unchanged", tostring(D.GetGems(f)) .. " gems, " .. count(prof.Hybrids) .. " hybrids")
				T.eq(D._SettleForTest(f), true, "gem settle mix: (setup) _SettleForTest(p)")
				local okG2, keyG2 = F.Mix(f, "pebble_pup", "cloudy_dragon")
				T.check(okG2 == true and D.GetGems(f) == gems0 - gemCost and PK.Count(prof, "cloudy_dragon") == 0, "gem settle mix: ...after the settle the gem Mix mixes (for " .. tostring(gemCost) .. " gems)",
					tostring(keyG2) .. ", " .. tostring(D.GetGems(f)) .. " gems")
			end

			-- 14 s after the load: nobody waiting is settled yet
			advanceTo(t0 + 8)
			T.check(B.SpendGems(q, 200) == true and B.Save(q) == true, "gem settle hop: 8 s after the load the old server's save lands (300 -> 100 gems)")
			T.check(D.GetGems(q) == 300 and D.GemsSettled(q) == false, "gem settle hop: ...this server still shows 300 and is not settled (gem actions wait)", tostring(D.GetGems(q)))
			advanceTo(t0 + 14)
			T.check(D.GemsSettled(p) == false and p:GetAttribute(ATTR) == nil and firesP.n == 0, "gem settle: 14 s after the load: still not settled", settledText(D, p))
			T.check(D.GemsSettled(q) == false and firesQ.n == 0, "gem settle hop: 14 s after the load: still not settled", settledText(D, q))
			local rebased14, teams14 = rebasedP.n, teamsP.n
			local mark = K.logSize()
			local calls = DSt.Calls
			local gemsP, tokensP, petsP = D.GetGems(p), D.GetTokens(p), count(D.GetProfile(p).Pets)
			advanceTo(t0 + 15.5)
			T.check(D.GemsSettled(p) == true and p:GetAttribute(ATTR) == true, "gem settle: past 15 s and the settle read: GemsSettled is true and the attribute GemsSettled = true", settledText(D, p))
			T.eq(firesP.n, 1, "gem settle: ...Settled fired once")
			T.check(DSt.Calls > calls, "gem settle: ...the settle read reached the store (Mock.DataStore.Calls grew)", tostring(DSt.Calls - calls))
			T.check(rebasedP.n == rebased14 and teamsP.n == teams14, "gem settle quiet: a quiet read fires no ProfileRebased and no TeamsChanged", "rebased +" .. (rebasedP.n - rebased14) .. ", teams +" .. (teamsP.n - teams14))
			local syncs = K.remotesFor("ProfileSync", uidP, mark)
			T.eq(#syncs, 0, "gem settle quiet: ...and sends no extra ProfileSync")
			T.check(D.GetGems(p) == gemsP and gemsP == 300 and D.GetTokens(p) == tokensP and count(D.GetProfile(p).Pets) == petsP, "gem settle quiet: ...the live profile is unchanged",
				tostring(D.GetGems(p)) .. " gems")
			T.check(D.GemsSettled(q) == true and q:GetAttribute(ATTR) == true and firesQ.n == 1, "gem settle hop: settled after the read (attribute set, Settled fired once)", settledText(D, q))
			T.eq(D.GetGems(q), 100, "gem settle hop: ...the live Gems is the stored 100 (the settle read rebased onto the old server's save)")
			T.eq(rebasedQ.n, 1, "gem settle hop: ...ProfileRebased fired once")
			T.eq(rebasedQ.saw, false, "gem settle hop: ...and its listeners still saw GemsSettled == false (marked settled after the rebase)")
			advance(20)
			T.check(firesP.n == 1 and firesQ.n == 1 and firesW.n == 1 and firesF.n == 1, "gem settle: Settled fires once per load (no second fire later)",
				firesP.n .. "/" .. firesQ.n .. "/" .. firesW.n .. "/" .. firesF.n)
			for _, who in ipairs({ p, q, w, f }) do
				leave(who)
			end

			------------------------------------------------------------------------------------------------
			-- a failing settle read retries every 5 s
			------------------------------------------------------------------------------------------------
			local uidR = newUserId()
			local firesR = counter(D.Settled, uidR)
			local t3 = os.clock()
			local r = Mock.AddPlayer("SettleFail" .. tostring(uidR % 1000), uidR)
			players[#players + 1] = r
			advanceTo(t3 + 14.5)
			DSt.Fail = true
			advanceTo(t3 + 20)
			T.check(D.GemsSettled(r) == false and r:GetAttribute(ATTR) == nil and firesR.n == 0, "gem settle fail: a settle read that fails (Mock.DataStore.Fail) leaves the player not settled", settledText(D, r))
			DSt.Fail = false
			advanceTo(t3 + 21)
			T.eq(D.GemsSettled(r), false, "gem settle fail: ...the retry waits 5 s after the failed read (not yet at 21 s)")
			advanceTo(t3 + 22.5)
			T.check(D.GemsSettled(r) == true and r:GetAttribute(ATTR) == true and firesR.n == 1, "gem settle fail: ...retried 5 s later: settled once Fail is cleared", settledText(D, r) .. ", fires " .. firesR.n)
			leave(r)

			------------------------------------------------------------------------------------------------
			-- a failed (provisional) load: no settle read of its own; a recovery read 15 s or more after the load counts as
			-- the settle read. The store stays down until 20 s, so whichever recovery lands first (the scheduled one at
			-- about 21.5 s, or an autosave's save, which recovers too) lands at >= 20 s
			------------------------------------------------------------------------------------------------
			local uidV = newUserId()
			DSt.Data[storeKey(uidV)] = oldRecord({ Gems = 40 })
			local firesV = counter(D.Settled, uidV)
			local rebasedV = counter(D.ProfileRebased, uidV, settledProbe)
			DSt.Fail = true
			local t5 = os.clock()
			local v = Mock.AddPlayer("SettleProv" .. tostring(uidV % 1000), uidV)
			players[#players + 1] = v
			advance(4)
			if T.check(D.GetProfile(v) ~= nil and provisional(D, v), "gem settle provisional: (precondition) the load failed while the store is reachable") then
				T.eq(D._SettleForTest(v), false, "gem settle provisional: _SettleForTest answers false while provisional")
				advanceTo(t5 + 16)
				T.check(D.GemsSettled(v) == false and v:GetAttribute(ATTR) == nil and firesV.n == 0, "gem settle provisional: still not settled after 15 s (no settle read of its own)", settledText(D, v))
				advanceTo(t5 + 20)
				DSt.Fail = false
				T.check(K.waitFor(function()
					return not provisional(D, v)
				end, 40), "gem settle provisional: (the recovery reads the real save)")
				local at = os.clock() - t5
				T.check(at >= 20, "gem settle provisional: ...the recovery read landed at >= 20 s", tostring(at))
				T.check(D.GemsSettled(v) == true and v:GetAttribute(ATTR) == true, "gem settle provisional: the recovery read counts as the settle read: settled at once", settledText(D, v))
				T.eq(firesV.n, 1, "gem settle provisional: ...Settled fired once")
				T.check(rebasedV.n >= 1 and rebasedV.saw == false, "gem settle provisional: ...ProfileRebased fired first and its listeners saw GemsSettled == false",
					rebasedV.n .. " fires, saw " .. tostring(rebasedV.saw))
				T.eq(D.GetGems(v), 40, "gem settle provisional: ...the stored gems are in")
				advance(16)
				T.eq(firesV.n, 1, "gem settle provisional: ...no later settle read fires Settled again")
			end
			DSt.Fail = false
			leave(v)

			-- a recovery sooner than SettleSeconds (a save recovers the stand-in about 4 s after the join) is not the
			-- settle read: the normal settle read runs once SettleSeconds have passed since the load
			local uidE = newUserId()
			DSt.Data[storeKey(uidE)] = oldRecord({ Gems = 40 })
			local firesE = counter(D.Settled, uidE)
			DSt.Fail = true
			local t6 = os.clock()
			local e = Mock.AddPlayer("SettleEarly" .. tostring(uidE % 1000), uidE)
			players[#players + 1] = e
			advance(4)
			DSt.Fail = false
			if T.check(D.GetProfile(e) ~= nil and provisional(D, e), "gem settle early recovery: (precondition) the load failed while the store is reachable") then
				T.check(D.Save(e) == true and not provisional(D, e), "gem settle early recovery: a save about 4 s after the join recovers the real record")
				T.check(D.GemsSettled(e) == false and e:GetAttribute(ATTR) == nil and firesE.n == 0, "gem settle early recovery: ...a recovery sooner than 15 s does not end the hold", settledText(D, e))
				-- the failed load returned after its two reads (about 1.5 s), so the normal settle read lands near t + 16.5 s
				advanceTo(t6 + 15.5)
				T.eq(D.GemsSettled(e), false, "gem settle early recovery: ...still held 14 s after the load")
				advanceTo(t6 + 17.5)
				T.check(D.GemsSettled(e) == true and e:GetAttribute(ATTR) == true and firesE.n == 1, "gem settle early recovery: ...the normal settle read ends it once 15 s have passed (Settled once)",
					settledText(D, e) .. ", fires " .. firesE.n)
				T.eq(D.GetGems(e), 40, "gem settle early recovery: ...the stored gems are in")
			end
			DSt.Fail = false
			leave(e)

			------------------------------------------------------------------------------------------------
			-- no store (Studio without API access): settled at 15 s with no read
			------------------------------------------------------------------------------------------------
			local uidS = newUserId()
			local s = join("SettleNoApi", uidS)
			players[#players + 1] = s
			advance(16) -- the booted server's own settle read of this player is done: nothing else reads during the check
			local D2, clone2, release2 = secondServer("DataServiceSettleNoApi")
			if T.check(D2 ~= nil and type(D2.GemsSettled) == "function", "gem settle no store: a fresh copy of DataService loads", tostring(clone2)) then
				DSt.Unavailable = true
				local okNo, errNo = pcall(function()
					local t4 = os.clock()
					D2.Load(s)
					T.check(type(D2.IsProvisional) == "function" and D2.IsProvisional(s) == false and D2.GemsSettled(s) == false,
						"gem settle no store: a load with no usable store is not provisional and not settled yet")
					advanceTo(t4 + 14)
					T.eq(D2.GemsSettled(s), false, "gem settle no store: ...false at 14 s")
					advanceTo(t4 + 14.9)
					T.eq(D2.GemsSettled(s), false, "gem settle no store: ...still false just before 15 s")
					local callsNo = DSt.Calls -- a narrow window: the booted server's autosave sweep is unlikely to fall in it
					advanceTo(t4 + 15.1)
					T.eq(D2.GemsSettled(s), true, "gem settle no store: ...true at 15 s")
					T.eq(DSt.Calls, callsNo, "gem settle no store: ...with no read (no DataStore call)")
				end)
				DSt.Unavailable = false
				T.check(release2() == true, "gem settle no store: the copy's hooks are dropped with it")
				if not okNo then
					error(errNo, 0)
				end
			end
			leave(s)
		end)
		DSt.Fail = false
		DSt.Unavailable = false
		for _, box in ipairs(counters) do
			box.stop()
		end
		for _, p in ipairs(players) do
			if p.Parent then
				Mock.RemovePlayer(p)
			end
		end
		advance(12)
		T.check(releaseB() == true, "gem settle: the old server's hooks are dropped with it")
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("gem_settle")
		K.flushWarnings("gem_settle", ALLOWED_WARNINGS)
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local H = {}

	function H.client(name)
		return require(Mock.GetPath(ROOTS["client"] .. "/" .. name))
	end
	-- a small profile (tutorial done) with the given settings (the smoke_dgfix_mouse.lua shape)
	function H.profile(settings)
		KC.toClient("ProfileSync", {
			Tokens = 900, Pets = { cloudy_dragon = 1, pebble_pup = 1 }, Equipped = { "cloudy_dragon" }, Items = {},
			Discovered = { cloudy_dragon = true, pebble_pup = true }, IndexClaimed = {},
			Stats = { Matches = 3, Wins = 1, TokensEarned = 40, Spins = 2, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 12400, Gems = 85, Berries = 1240,
			Teams = { Presets = { { "cloudy_dragon" }, {}, {} }, Active = 1, Slots = 3 },
			Settings = settings,
		})
		KC.advance(0.8)
	end

	S.client_fasthatch_setting = guarded("client_fasthatch_setting", function()
		local CS = H.client("ClientSettings")
		local State = H.client("State")
		local base = { Music = 6, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 0, MouseLock = true }
		local function with(fast)
			local s = {}
			for key, value in pairs(base) do
				s[key] = value
			end
			s.FastHatch = fast
			return s
		end
		H.profile(with(nil)) -- a profile saved before the setting: no FastHatch key
		T.eq(CS.Get("FastHatch"), false, "fast hatch client: ClientSettings.Get('FastHatch') defaults to false")
		local keys = {}
		for _, key in ipairs(CS.KEYS or {}) do
			keys[key] = true
		end
		T.check(keys.FastHatch == true and CS.DEFAULTS and CS.DEFAULTS.FastHatch == false, "fast hatch client: KEYS lists FastHatch, DEFAULTS.FastHatch = false")
		T.check(CS.Clean("FastHatch", true) == true and CS.Clean("FastHatch", false) == false and CS.Clean("FastHatch", 1) == nil and CS.Clean("FastHatch", "yes") == nil,
			"fast hatch client: Clean takes booleans only")
		local log0 = #Mock.RemoteLog
		T.eq(CS.Set("FastHatch", true), true, "fast hatch client: Set('FastHatch', true) answers true")
		T.eq(CS.Get("FastHatch"), true, "fast hatch client: ...and applies at once")
		KC.advance(0.35)
		T.eq(#KC.serverCalls("SettingsSet", log0), 0, "fast hatch client: no SettingsSet before the 0.4 s debounce")
		KC.advance(0.15)
		local sent = KC.serverCalls("SettingsSet", log0)
		T.check(#sent == 1 and sent[1].args[1] == "FastHatch" and sent[1].args[2] == true, "fast hatch client: exactly one SettingsSet('FastHatch', true) by 0.5 s", #sent .. " sends")
		T.eq(CS.Set("FastHatch", 1), false, "fast hatch client: Set('FastHatch', 1) is refused")
		T.eq(CS.Get("FastHatch"), true, "fast hatch client: ...and changes nothing")
		H.profile(with(true))
		local settings = type(State.Settings) == "function" and State.Settings() or nil
		T.check(type(settings) == "table" and settings.FastHatch == true, "fast hatch client: a ProfileSync with Settings.FastHatch = true -> State.Settings().FastHatch == true",
			tostring(type(settings) == "table" and settings.FastHatch))
		T.eq(CS.Get("FastHatch"), true, "fast hatch client: ...and ClientSettings follows it")
		H.profile(with(false))
		settings = type(State.Settings) == "function" and State.Settings() or nil
		T.check(type(settings) == "table" and settings.FastHatch == false and CS.Get("FastHatch") == false, "fast hatch client: a ProfileSync with FastHatch = false turns it off again (restored)")
		KC.flushErrors("client_fasthatch_setting")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
