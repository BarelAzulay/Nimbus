-- smoke_audio.lua: the original audio (nimbus-climb/audio/, Config.Audio <- shared/AudioIds.lua <- tools/upload_assets.py
-- --audio; client/SoundFx, client/Controllers/RingAmbience). Loaded by tools/smoke.py in the server and the client world:
--   audio_ring_pocket   (server, booted) the real Champion Ring pocket (ArenaBuilder.BuildPocket(i, "Ring")) has the
--                       child model "Crowd" RingAmbience hangs the crowd + drums on; the fighter's pad is inside the
--                       crowd's hearing range (CrowdCheer Max), the next pocket's crowd far outside it
--   client_audio_keys   Config.Audio.Keys = exactly the 12 keys of audio/audio.json (one each); with the shipped AudioIds
--                       stub every group is empty (silent); a Config copy beside a FAKE AudioIds maps every key to its
--                       number, leaves out a missing / junk one; one place for slot volumes (every key; music under every
--                       SFX; the ring's crowd + drums under the music) + the positional ranges; SoundFx.NAMES has the new
--                       Inhale / Shatter / CrowdCheer / DrumLoop and every Sfx / Ambient name
--   client_audio_silent (no ids, the shipped state) every Play / Music / SetLayer / Positional, the charge hooks, a battle
--                       Start / End, a dungeon run and a ring pocket make no Sound, no error, no warning
--   client_audio_music  (ids given for the test) Music loops; Battle on my fight's Start, back to Lobby at its End (+ the
--                       win's Reward), a won ring round keeps Battle until the next round, a spectator hears no battle
--                       music; a dungeon run plays Dungeon (rooms too), its boss room Battle, back to Dungeon after it,
--                       Lobby when the run ends; the chest and a room's loot play Reward; the Music / Sfx settings apply
--                       at once to the music and the positional loops
--   client_audio_charge BattleController's special charge plays SoundFx "Inhale" (PlaybackSpeed 0.75 rising to 1.35, faded
--                       in / out) and a broken charge "Shatter" (never the old Whoosh / Error); the source pins the names
--   client_audio_ring   RingAmbience on a ring pocket: CrowdCheer + DrumLoop looped, InverseTapered, Config.Audio
--                       Positional Min / Max, at the crowd stand, slot volume x setting; a Drummer added later takes the
--                       drums; a tagged plaza crowd (NC_RingCrowd) gets its own; a destroyed pocket takes its sounds
-- Deterministic: mock clock only, fixed ids (fake numbers given for the test, never uploaded). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()

local AUDIO_KEYS = { "Click", "Confirm", "CrowdCheer", "DrumLoop", "Error", "Inhale", "MusicBattle", "MusicDungeon", "MusicLobby", "Reward", "Shatter", "Whoosh" }

local function readFile(rel)
	for _, prefix in ipairs({ "", "../", "nimbus-climb/" }) do
		local fh = io.open(prefix .. rel, "r")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src
		end
	end
	return nil
end

local function moduleAt(path)
	local ok, inst = pcall(Mock.GetPath, path)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
if IS_SERVER then
	S.audio_ring_pocket = guarded("audio_ring_pocket", function()
		local K = _G.K
		if not K or not K.needBoot() then
			return
		end
		local inst = K.moduleInstance("server/Services/ArenaBuilder")
		local ok, AB = pcall(require, inst)
		local Config = K.config()
		if not T.check(ok and type(AB) == "table" and type(AB.BuildPocket) == "function", "audio: ArenaBuilder loads") then
			return
		end
		local p = AB.BuildPocket(63, "Ring")
		local q = AB.BuildPocket(64, "Ring")
		if not T.check(type(p) == "table" and typeof(p.Model) == "Instance" and type(q) == "table", "audio: BuildPocket(63 / 64, \"Ring\") build ring pockets") then
			return
		end
		T.check(string.sub(p.Model.Name, 1, 11) == "RingPocket_" and p.Model.Parent and p.Model.Parent.Name == "BattlePockets",
			"audio: a ring pocket is workspace.BattlePockets.RingPocket_<i> (what RingAmbience watches)", p.Model:GetFullName())
		local crowd = p.Model:FindFirstChild("Crowd")
		local parts = 0
		for _, d in ipairs(crowd and crowd:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				parts = parts + 1
			end
		end
		T.check(crowd ~= nil and crowd:IsA("Model") and parts >= 4, "audio: the pocket has its child model \"Crowd\" (the bleacher + the cloud crowd) with parts to hang the sounds on",
			fmt("%d parts", parts))
		T.info("audio: drummer model in the pocket: " .. (p.Model:FindFirstChild("Drummer", true) and "yes (RingAmbience puts the drums there)" or "none yet (the drums play from the bleacher's end)"))
		if crowd then
			local cf, size = crowd:GetBoundingBox()
			local ranges = Config.Audio and Config.Audio.Positional or {}
			local maxD = ranges.CrowdCheer and ranges.CrowdCheer.Max or 0
			local spawnD = (p.Spawn.Position - cf.Position).Magnitude
			local qc = q.Model:FindFirstChild("Crowd")
			local otherD = qc and (p.Spawn.Position - qc:GetBoundingBox().Position).Magnitude or 0
			T.info(fmt("audio: fighter's pad -> crowd %.1f studs, -> next pocket's crowd %.1f studs, CrowdCheer Max %s", spawnD, otherD, tostring(maxD)))
			T.check(maxD > 0 and spawnD < maxD and otherD > maxD * 1.5, "audio: the crowd is heard from the fighter's pad (closer than CrowdCheer Max) and the next pocket's is not",
				fmt("spawn %.1f, next pocket %.1f, Max %s (stand %.0f x %.0f)", spawnD, otherD, tostring(maxD), size.X, size.Z))
		end
		AB.FreePocket(63)
		AB.FreePocket(64)
	end)
	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local KC = _G.KC
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local function mods()
	return {
		Config = moduleAt(ROOTS.shared .. "/Config"),
		SF = moduleAt(ROOTS.client .. "/SoundFx"),
		CS = moduleAt(ROOTS.client .. "/ClientSettings"),
		BC = moduleAt(ROOTS.client .. "/Controllers/BattleController"),
		AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx"),
		RA = moduleAt(ROOTS.client .. "/Controllers/RingAmbience"),
	}
end

local function sounds(root)
	local out = {}
	for _, d in ipairs((root or game):GetDescendants()) do
		if d:IsA("Sound") then
			out[#out + 1] = d
		end
	end
	return out
end

local function outputSince(n0)
	local bad = {}
	for i = n0 + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" or o.kind == "error" then
			bad[#bad + 1] = o.text
		end
	end
	return bad
end

-- a stand-in ring pocket: workspace.BattlePockets.RingPocket_<n> with a "Crowd" bleacher like ArenaBuilder's
local pocketSeq = 0
local function fakePocket(at)
	pocketSeq = pocketSeq + 1
	local folder = Workspace:FindFirstChild("BattlePockets")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BattlePockets"
		folder.Parent = Workspace
	end
	local m = Instance.new("Model")
	m.Name = "RingPocket_" .. (90 + pocketSeq)
	local floorP = Instance.new("Part")
	floorP.Name = "RingFloor"
	floorP.Size = Vector3.new(60, 1, 60)
	floorP.CFrame = CFrame.new(at)
	floorP.Parent = m
	local crowd = Instance.new("Model")
	crowd.Name = "Crowd"
	for i, spec in ipairs({ { 34, 1.5, 3.8, 0.75, 1.9 }, { 28, 3.5, 3.8, 1.75, 5.7 } }) do
		local step = Instance.new("Part")
		step.Name = "StandStep"
		step.Size = Vector3.new(spec[1], spec[2], spec[3])
		step.CFrame = CFrame.new(at + Vector3.new(0, spec[4], 37.6 + spec[5]))
		step.Parent = crowd
		if i == 2 then
			local puff = Instance.new("Part")
			puff.Name = "PuffBody"
			puff.Size = Vector3.new(3.4, 2.2, 2.4)
			puff.CFrame = CFrame.new(at + Vector3.new(0, 4.6, 43.3))
			puff.Parent = crowd
		end
	end
	crowd.Parent = m
	m.Parent = folder
	return m, crowd
end

-- every AudioIds key given a fake number for a test (restored by the returned function)
local function giveIds(Config)
	local A = Config.Audio
	local saved = {}
	local n = 0
	for _, group in ipairs({ "Music", "Sfx", "Ambient" }) do
		saved[group] = {}
		for name, v in pairs(A[group]) do
			saved[group][name] = v
		end
		for name in pairs(A.Keys[group]) do
			n = n + 1
			A[group][name] = 7000000 + n
		end
	end
	return function()
		for _, group in ipairs({ "Music", "Sfx", "Ambient" }) do
			for name in pairs(A[group]) do
				A[group][name] = nil
			end
			for name, v in pairs(saved[group]) do
				A[group][name] = v
			end
		end
	end
end

local function startPayload(id, mode, side, extra)
	local p = { BattleId = id, Mode = mode, Side = side, Spectator = side == 0, T = 0, Units = {}, Zone = { CFrame = CFrame.new(0, 400, 0), X = 40, Z = 40 } }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local function fireDungeon(kind, payload)
	KC.toClient("DungeonState", kind, payload)
	KC.advance(0.1)
end

-- the music context SoundFx plays and its Sound
local function music(SF)
	local St = SF._St
	return SF.Current(), St and St.Music
end

S.client_audio_keys = guarded("client_audio_keys", function()
	local M = mods()
	local Config, SF = M.Config, M.SF
	if not T.check(Config and Config.Audio and type(Config.Audio.Keys) == "table" and SF ~= nil, "audio keys: Config.Audio.Keys and client/SoundFx load") then
		return
	end
	local A = Config.Audio
	-- the manifest's keys = the keys Config names, one each
	local manifest = readFile("audio/audio.json") or ""
	local mkeys = {}
	for key, file in string.gmatch(manifest, '"([%w_]+)": {%s*"file": "audio/([%w_]+)%.ogg"') do
		mkeys[#mkeys + 1] = key
		T.check(key == file, "audio keys: audio.json " .. key .. " -> audio/" .. key .. ".ogg")
	end
	table.sort(mkeys)
	local ckeys, seen, dup = {}, {}, {}
	for _, group in ipairs({ "Music", "Sfx", "Ambient" }) do
		for _, key in pairs(A.Keys[group] or {}) do
			if seen[key] then
				dup[#dup + 1] = key
			end
			seen[key] = true
			ckeys[#ckeys + 1] = key
		end
	end
	table.sort(ckeys)
	T.eq(table.concat(mkeys, " "), table.concat(AUDIO_KEYS, " "), "audio keys: audio/audio.json lists the 12 original sounds")
	T.check(table.concat(ckeys, " ") == table.concat(AUDIO_KEYS, " ") and #dup == 0, "audio keys: Config.Audio.Keys maps exactly the 12 AudioIds keys, each once",
		table.concat(ckeys, " ") .. " dup: " .. table.concat(dup, " "))
	T.eq(A.Keys.Sfx.Inhale, "Inhale", "audio keys: Sfx.Inhale = AudioIds.Inhale")
	T.eq(A.Keys.Sfx.Shatter, "Shatter", "audio keys: Sfx.Shatter = AudioIds.Shatter")
	T.eq(A.Keys.Ambient.CrowdCheer, "CrowdCheer", "audio keys: Ambient.CrowdCheer = AudioIds.CrowdCheer")
	T.eq(A.Keys.Ambient.DrumLoop, "DrumLoop", "audio keys: Ambient.DrumLoop = AudioIds.DrumLoop")
	-- the shipped stub: no ids -> every group empty
	local ids = moduleAt(ROOTS.shared .. "/AudioIds")
	local nIds = 0
	for _ in pairs(ids or {}) do
		nIds = nIds + 1
	end
	local filled = 0
	for _, group in ipairs({ "Music", "Sfx", "Ambient" }) do
		for name, v in pairs(A[group] or {}) do
			filled = filled + 1
			T.check(type(v) == "number" and ids[A.Keys[group][name]] == v, "audio keys: Config.Audio." .. group .. "." .. name .. " is AudioIds." .. tostring(A.Keys[group][name]))
		end
	end
	T.check(ids ~= nil and filled == nIds, "audio keys: Config.Audio holds exactly the AudioIds that exist (" .. nIds .. " today)", fmt("%d in Config", filled))
	-- a Config copy next to a FAKE AudioIds: every key -> its number; a missing key and a junk value stay out
	local box = Instance.new("Folder")
	box.Name = "AudioKeysBox"
	local cfg = Mock.GetPath(ROOTS.shared .. "/Config"):Clone()
	cfg.Parent = box
	Mock.GetPath(ROOTS.shared .. "/MeshIds"):Clone().Parent = box
	local fake = Instance.new("ModuleScript")
	fake.Name = "AudioIds"
	local lines = { "return {" }
	for i, key in ipairs(AUDIO_KEYS) do
		if key == "Whoosh" then
			lines[#lines + 1] = "\tWhoosh = \"123\","
		elseif key ~= "Reward" then
			lines[#lines + 1] = fmt("\t%s = %d,", key, 81000000000000 + i)
		end
	end
	lines[#lines + 1] = "\tNotASound = 5,"
	lines[#lines + 1] = "}"
	fake.Source = table.concat(lines, "\n")
	fake.Parent = box
	local okC, C2 = pcall(require, cfg)
	if T.check(okC and type(C2) == "table" and C2.Audio, "audio keys: Config loads beside a fake AudioIds", tostring(C2)) then
		local wrong = {}
		for _, group in ipairs({ "Music", "Sfx", "Ambient" }) do
			for name, key in pairs(C2.Audio.Keys[group]) do
				local want = nil
				for i, k in ipairs(AUDIO_KEYS) do
					if k == key and k ~= "Whoosh" and k ~= "Reward" then
						want = 81000000000000 + i
					end
				end
				if C2.Audio[group][name] ~= want then
					wrong[#wrong + 1] = group .. "." .. name .. "=" .. tostring(C2.Audio[group][name])
				end
			end
		end
		T.check(#wrong == 0, "audio keys: Config.Audio maps every key to its AudioIds number; a missing (Reward) or non-number (Whoosh) id stays out", table.concat(wrong, ", "))
		local id = SF.Id("Music", "Lobby")
		T.check(id == nil, "audio keys: SoundFx.Id with no id -> nil (silent)", tostring(id))
	end
	box:Destroy()
	-- SoundFx.Id turns a 15-digit number into its full digits (never 1.2e+14)
	local restore = giveIds(Config)
	A.Sfx.Click = 132235279556961
	T.eq(SF.Id("Sfx", "Click"), "rbxassetid://132235279556961", "audio keys: SoundFx.Id writes a 15-digit id in full")
	restore()
	-- one place for slot volumes
	local V = A.Volume or {}
	local missing, musicMax, sfxMin = {}, 0, 1
	for _, key in ipairs(AUDIO_KEYS) do
		if type(V[key]) ~= "number" or V[key] <= 0 or V[key] > 1 then
			missing[#missing + 1] = key
		end
	end
	for _, key in pairs(A.Keys.Music) do
		musicMax = math.max(musicMax, V[key] or 0)
	end
	for _, key in pairs(A.Keys.Sfx) do
		sfxMin = math.min(sfxMin, V[key] or 0)
	end
	local musicMin = 1
	for _, key in pairs(A.Keys.Music) do
		musicMin = math.min(musicMin, V[key] or 1)
	end
	T.check(#missing == 0, "audio volumes: Config.Audio.Volume gives every key a slot volume in (0, 1]", table.concat(missing, " "))
	T.check(musicMax < sfxMin, "audio volumes: the music sits under every sound effect", fmt("music max %.2f, sfx min %.2f", musicMax, sfxMin))
	T.check((V.CrowdCheer or 1) < musicMin and (V.DrumLoop or 1) < musicMin, "audio volumes: the ring's crowd and drums sit under the music",
		fmt("crowd %s drums %s music min %.2f", tostring(V.CrowdCheer), tostring(V.DrumLoop), musicMin))
	local P = A.Positional or {}
	local okP = true
	for _, key in ipairs({ "CrowdCheer", "DrumLoop" }) do
		local r = P[key]
		okP = okP and type(r) == "table" and r.Min > 0 and r.Max > r.Min and r.Max < 190
	end
	T.check(okP, "audio volumes: CrowdCheer / DrumLoop have positional Min < Max < 190 studs (ring pockets are 380 apart)")
	-- SoundFx NAMES
	local names = {}
	for _, n in ipairs(SF.NAMES or {}) do
		names[n] = true
	end
	local lack = {}
	for _, n in ipairs({ "Inhale", "Shatter", "CrowdCheer", "DrumLoop" }) do
		if not names[n] then
			lack[#lack + 1] = n
		end
	end
	for _, group in ipairs({ "Sfx", "Ambient" }) do
		for n in pairs(A.Keys[group]) do
			if not names[n] then
				lack[#lack + 1] = n
			end
		end
	end
	T.check(#lack == 0, "audio keys: SoundFx.NAMES has Inhale, Shatter, CrowdCheer, DrumLoop and every Sfx / Ambient name", table.concat(lack, " "))
end)

S.client_audio_silent = guarded("client_audio_silent", function()
	local M = mods()
	local Config, SF, BC, AF, RA = M.Config, M.SF, M.BC, M.AF, M.RA
	if not T.check(Config and SF and BC and AF and RA, "audio silent: Config, SoundFx, BattleController, AttackFx, RingAmbience load") then
		return
	end
	-- the shipped state: no ids at all (the test wipes any for its run)
	local A = Config.Audio
	local saved = {}
	for _, group in ipairs({ "Music", "Sfx", "Ambient" }) do
		saved[group] = A[group]
		A[group] = {}
	end
	local n0, e0 = #Mock.Output, #Mock.Errors
	local before = #sounds()
	local plays = {}
	for _, n in ipairs(SF.NAMES) do
		plays[#plays + 1] = SF.Play(n) == nil
	end
	local allNil = true
	for _, v in ipairs(plays) do
		allNil = allNil and v
	end
	local m1 = SF.Music("Battle")
	local m2 = SF.SetLayer("Dungeon", true)
	local m3 = SF.SetLayer("Dungeon", false)
	local part = Instance.new("Part")
	part.Parent = Workspace
	local pos = SF.Positional("CrowdCheer", part)
	T.check(allNil and m1 == nil and m2 == nil and m3 == nil and pos == nil, "audio silent: Play / Music / SetLayer / Positional return nil while no id exists")
	-- the battle's charge sounds, a battle Start / End, a dungeon run, a ring pocket
	BC.FxHooks()
	local hk = AF.Hooks
	local inh = hk.Inhale and hk.Inhale(0.6, "silent1", true)
	if hk.Shatter then
		hk.Shatter(true)
	end
	BC.HandleState("Start", startPayload("audio_silent", "Duel", 1), "audio_silent")
	KC.advance(0.2)
	BC.HandleState("End", { BattleId = "audio_silent", Mode = "Duel", Outcome = "Win", Won = true, Rewards = { Cash = 10 } }, "audio_silent")
	KC.advance(0.2)
	LocalPlayer:SetAttribute("InBattle", "Daudio")
	fireDungeon("Run", { RunId = "audio_silent_run", Floor = 1, Name = "Mossy Cellar", State = "Hall", Room = 1, RoomCount = 4, Members = {} })
	fireDungeon("Chest", { Kind = "Cash", Amount = 5 })
	fireDungeon("End", { Floor = 1 })
	LocalPlayer:SetAttribute("InBattle", nil)
	local pocket = fakePocket(Vector3.new(4000, 900, 4000))
	RA.Scan(pocket)
	KC.advance(0.5)
	local anchors = 0
	for _, d in ipairs(pocket:GetDescendants()) do
		if d:IsA("Attachment") then
			anchors = anchors + 1
		end
	end
	local after = #sounds()
	local bad = outputSince(n0)
	T.check(inh ~= true and after == before and anchors == 0, "audio silent: the charge hooks, a battle, a dungeon run (chest) and a ring pocket make no Sound and leave no anchor",
		fmt("sounds %d -> %d, anchors %d", before, after, anchors))
	T.check(#bad == 0 and #Mock.Errors == e0, "audio silent: no warning, no error while the ids are missing", table.concat(bad, " | "))
	pocket:Destroy()
	part:Destroy()
	for _, group in ipairs({ "Music", "Sfx", "Ambient" }) do
		A[group] = saved[group]
	end
	SF.SetLayer("Battle", false)
	SF.SetLayer("Dungeon", false)
	SF.Music("Lobby")
end)

S.client_audio_music = guarded("client_audio_music", function()
	local M = mods()
	local Config, SF, BC, CS = M.Config, M.SF, M.BC, M.CS
	if not T.check(Config and SF and BC and CS and type(SF.SetLayer) == "function", "audio music: Config, SoundFx (SetLayer), BattleController, ClientSettings load") then
		return
	end
	local restore = giveIds(Config)
	local e0 = #Mock.Errors
	local okRun, err = pcall(function()
		SF.SetLayer("Battle", false)
		SF.SetLayer("Dungeon", false)
		SF.Music(nil)
		KC.advance(2)
		SF.Music("Lobby")
		KC.advance(2)
		local ctx, snd = music(SF)
		T.check(ctx == "Lobby" and snd and snd.Looped and snd.IsPlaying and snd.SoundId == "rbxassetid://" .. tostring(Config.Audio.Music.Lobby)
			and math.abs(snd.Volume - SF.SlotVolume("Lobby", "Music")) < 1e-6, "audio music: Lobby loops at its slot volume x the Music setting",
			snd and fmt("%s looped %s vol %.3f", snd.SoundId, tostring(snd.Looped), snd.Volume) or "no sound")
		-- a duel I fight: Battle, then back to Lobby (+ Reward for the win)
		BC.HandleState("Start", startPayload("audio_duel", "Duel", 1), "audio_duel")
		KC.advance(0.3)
		local c1, s1 = music(SF)
		T.check(c1 == "Battle" and s1 and s1.Name == "Music_Battle" and s1.Looped, "audio music: my battle's Start switches to the looped Battle track", tostring(c1))
		KC.advance(2)
		local oldLobby = 0
		for _, s in ipairs(sounds(SoundService)) do
			if s.Name == "Music_Lobby" then
				oldLobby = oldLobby + 1
			end
		end
		T.check(oldLobby == 0, "audio music: the Lobby track faded out and is gone after the crossfade", fmt("%d left", oldLobby))
		for _, s in ipairs(sounds(SoundService)) do
			if string.find(s.Name, "Sfx_Reward", 1, true) then
				s:Stop()
			end
		end
		BC.HandleState("End", { BattleId = "audio_duel", Mode = "Duel", Outcome = "Win", Won = true, Rewards = { Cash = 25 } }, "audio_duel")
		KC.advance(0.1)
		local c2 = music(SF)
		local reward = false
		for _, s in ipairs(sounds(SoundService)) do
			if string.find(s.Name, "Sfx_Reward", 1, true) and s.IsPlaying then
				reward = true
			end
		end
		T.check(c2 == "Lobby", "audio music: my battle's End goes back to the Lobby track", tostring(c2))
		T.check(reward, "audio reward: a won fight's result plays Reward")
		KC.advance(8)
		-- a spectator: no battle music
		BC.HandleState("Start", startPayload("audio_watch", "Raid", 0), "audio_watch")
		KC.advance(0.3)
		T.eq(SF.Current(), "Lobby", "audio music: watching someone else's fight keeps the Lobby track")
		BC.HandleState("End", { BattleId = "audio_watch", Mode = "Raid", Spectator = true, Reason = "OutOfRange" }, "audio_watch")
		KC.advance(0.3)
		-- the Champion Ring: a won round keeps Battle through the intermission into the next round; the final End -> Lobby
		BC.HandleState("Start", startPayload("audio_ring1", "Ring", 1, { Ring = { Round = 1, Best = 0 } }), "audio_ring1")
		KC.advance(0.3)
		BC.HandleState("End", { BattleId = "audio_ring1", Mode = "Ring", Outcome = "Win", Won = true, Rewards = { Round = 1, Next = 2, Cash = 5, Xp = 5 } }, "audio_ring1")
		KC.advance(1)
		local cR = SF.Current()
		local beat = SF._St.Music
		BC.HandleState("Start", startPayload("audio_ring2", "Ring", 1, { Ring = { Round = 2, Best = 1 } }), "audio_ring2")
		KC.advance(0.3)
		T.check(cR == "Battle" and SF.Current() == "Battle" and SF._St.Music == beat, "audio music: a won ring round keeps the same Battle track playing into the next round (no restart)",
			fmt("between %s, next %s", tostring(cR), tostring(SF.Current())))
		BC.HandleState("End", { BattleId = "audio_ring2", Mode = "Ring", Outcome = "Loss", Won = false, Rewards = { Round = 2, Final = true } }, "audio_ring2")
		KC.advance(0.3)
		T.eq(SF.Current(), "Lobby", "audio music: the ring run's final End goes back to Lobby")
		KC.advance(8)
		-- a dungeon run: Dungeon, a room fight keeps it, the boss room plays Battle, back to Dungeon, Lobby after the run
		LocalPlayer:SetAttribute("InBattle", "Daudio")
		for _, s in ipairs(sounds(SoundService)) do
			if string.find(s.Name, "Sfx_Reward", 1, true) then
				s:Stop()
			end
		end
		fireDungeon("Run", { RunId = "audio_run", Floor = 1, Name = "Mossy Cellar", State = "Hall", Room = 1, RoomCount = 4, Members = {} })
		local d1 = SF.Current()
		BC.HandleState("Start", startPayload("audio_room1", "Dungeon", 1, { Dungeon = { Floor = 1, Room = 1, Wave = 1, Waves = 2 } }), "audio_room1")
		KC.advance(0.3)
		local d2 = SF.Current()
		BC.HandleState("End", { BattleId = "audio_room1", Mode = "Dungeon", Outcome = "Win", Won = true, Reason = "Cleared", Rewards = { Dungeon = true } }, "audio_room1")
		KC.advance(0.3)
		fireDungeon("Loot", { Room = 1, Cash = 40, Tokens = 4, Xp = 20 })
		local lootReward = false
		for _, s in ipairs(sounds(SoundService)) do
			if string.find(s.Name, "Sfx_Reward", 1, true) and s.IsPlaying then
				lootReward = true
			end
		end
		BC.HandleState("Start", startPayload("audio_boss", "Dungeon", 1, { Dungeon = { Floor = 1, Room = 4, Boss = true } }), "audio_boss")
		KC.advance(0.3)
		local d3 = SF.Current()
		BC.HandleState("End", { BattleId = "audio_boss", Mode = "Dungeon", Outcome = "Win", Won = true, Reason = "Cleared", Rewards = { Dungeon = true } }, "audio_boss")
		KC.advance(0.3)
		local d4 = SF.Current()
		for _, s in ipairs(sounds(SoundService)) do
			if string.find(s.Name, "Sfx_Reward", 1, true) then
				s:Stop()
			end
		end
		fireDungeon("Chest", { Kind = "Gems", Amount = 3 })
		local chestReward = false
		for _, s in ipairs(sounds(SoundService)) do
			if string.find(s.Name, "Sfx_Reward", 1, true) and s.IsPlaying then
				chestReward = true
			end
		end
		LocalPlayer:SetAttribute("InBattle", nil)
		fireDungeon("End", { Floor = 1 })
		local d5 = SF.Current()
		T.check(d1 == "Dungeon" and d2 == "Dungeon", "audio music: entering a dungeon run plays the Dungeon track, a room fight keeps it", fmt("%s / %s", tostring(d1), tostring(d2)))
		T.check(d3 == "Battle" and d4 == "Dungeon", "audio music: the boss room plays Battle, back to the Dungeon track after it", fmt("%s / %s", tostring(d3), tostring(d4)))
		T.check(d5 == "Lobby", "audio music: leaving the dungeon (its End) goes back to the Lobby track", tostring(d5))
		T.check(lootReward and chestReward, "audio reward: a room's loot and the chest play Reward", fmt("loot %s chest %s", tostring(lootReward), tostring(chestReward)))
		-- the settings apply at once: music + the positional loops
		local part = Instance.new("Part")
		part.Parent = Workspace
		local drums = SF.Positional("DrumLoop", part)
		local crowd = SF.Positional("CrowdCheer", part)
		local m0, s0 = CS.Get("Music"), CS.Get("Sfx")
		KC.advance(2)
		CS.Set("Music", 0)
		local _, ms = music(SF)
		local mutedMusic = ms and ms.Volume == 0 and drums.Volume == 0 and crowd.Volume > 0
		CS.Set("Sfx", 0)
		local mutedSfx = crowd.Volume == 0 and SF.Play("Click") == nil
		CS.Set("Music", 10)
		CS.Set("Sfx", 10)
		local loud = ms and math.abs(ms.Volume - Config.Audio.Volume.MusicLobby) < 1e-6 and math.abs(drums.Volume - Config.Audio.Volume.DrumLoop) < 1e-6
			and math.abs(crowd.Volume - Config.Audio.Volume.CrowdCheer) < 1e-6
		T.check(mutedMusic and mutedSfx and loud, "audio settings: Music 0 mutes the music + the drums (not the crowd), Sfx 0 the crowd + the effects; at 10 each plays its slot volume",
			fmt("music %s sfx %s loud %s", tostring(mutedMusic), tostring(mutedSfx), tostring(loud)))
		CS.Set("Music", m0)
		CS.Set("Sfx", s0)
		part:Destroy()
	end)
	T.check(okRun, "client_audio_music ran to the end", tostring(err))
	T.check(#Mock.Errors == e0, "audio music: no script error")
	SF.SetLayer("Battle", false)
	SF.SetLayer("Dungeon", false)
	SF.Music(nil)
	KC.advance(2)
	restore()
	SF.Music("Lobby")
end)

S.client_audio_charge = guarded("client_audio_charge", function()
	local M = mods()
	local Config, SF, BC, AF = M.Config, M.SF, M.BC, M.AF
	if not T.check(Config and SF and BC and AF and type(BC.FxHooks) == "function", "audio charge: SoundFx, BattleController, AttackFx load") then
		return
	end
	local src = readFile("src/client/Controllers/BattleController.lua") or ""
	T.check(string.find(src, 'pcall(SF.Play, "Inhale")', 1, true) ~= nil and string.find(src, 'pcall(SF.Play, "Shatter")', 1, true) ~= nil
		and string.find(src, 'pcall(SF.Play, "Whoosh")', 1, true) == nil and string.find(src, 'pcall(SF.Play, "Error")', 1, true) == nil,
		"audio charge: BattleController plays SoundFx \"Inhale\" / \"Shatter\" (no borrowed Whoosh / Error)")
	local restore = giveIds(Config)
	BC.FxHooks()
	local hk = AF.Hooks
	local folder = function()
		return SoundService:FindFirstChild("NimbusSounds")
	end
	local played = hk.Inhale and hk.Inhale(0.8, "audio_charge", true)
	local inhale = nil
	for _, s in ipairs(folder() and folder():GetChildren() or {}) do
		if string.find(s.Name, "Sfx_Inhale", 1, true) and s.IsPlaying then
			inhale = s
		end
	end
	T.check(played == true and inhale ~= nil and math.abs(inhale.PlaybackSpeed - 0.75) < 1e-6 and inhale.SoundId == "rbxassetid://" .. tostring(Config.Audio.Sfx.Inhale),
		"audio charge: the charge's inhale is SoundFx Inhale, starting at PlaybackSpeed 0.75", inhale and fmt("%s %.2f", inhale.SoundId, inhale.PlaybackSpeed) or "none")
	KC.advance(0.4)
	local mid = inhale and inhale.PlaybackSpeed or 0
	KC.advance(0.45)
	local top = inhale and inhale.PlaybackSpeed or 0
	KC.advance(1)
	T.check(mid < 1.35 and math.abs(top - 1.35) < 1e-6 and inhale and inhale.Volume == 0,
		"audio charge: the inhale rises 0.75 -> 1.35 by the release (not before), then fades out", fmt("mid %.3f top %.3f vol %s", mid, top, inhale and tostring(inhale.Volume) or "-"))
	if hk.Shatter then
		hk.Shatter(true)
	end
	local shatter = nil
	for _, s in ipairs(folder() and folder():GetChildren() or {}) do
		if string.find(s.Name, "Sfx_Shatter", 1, true) and s.IsPlaying then
			shatter = s
		end
	end
	T.check(shatter ~= nil and shatter.SoundId == "rbxassetid://" .. tostring(Config.Audio.Sfx.Shatter), "audio charge: a broken charge plays SoundFx Shatter")
	restore()
end)

S.client_audio_ring = guarded("client_audio_ring", function()
	local M = mods()
	local Config, SF, RA, CS = M.Config, M.SF, M.RA, M.CS
	if not T.check(Config and SF and RA and CS and type(RA.Scan) == "function", "audio ring: RingAmbience loads") then
		return
	end
	local restore = giveIds(Config)
	local okRun, err = pcall(function()
		local P = Config.Audio.Positional
		local pocket, crowd = fakePocket(Vector3.new(-4000, 900, 4000))
		KC.advance(0.2) -- RingAmbience watches BattlePockets (Init ran at boot): the pocket is picked up by itself
		local list = sounds(pocket)
		local byName = {}
		for _, s in ipairs(list) do
			byName[s.Name] = s
		end
		local c, d = byName.Loop_CrowdCheer, byName.Loop_DrumLoop
		local function positional(s, key)
			return s ~= nil and s.Looped and s.IsPlaying and s.RollOffMode == Enum.RollOffMode.InverseTapered
				and s.RollOffMinDistance == P[key].Min and s.RollOffMaxDistance == P[key].Max
				and s.Parent:IsA("Attachment") and s.Parent:IsDescendantOf(crowd)
				and math.abs(s.Volume - SF.SlotVolume(key)) < 1e-6 and s.SoundId == "rbxassetid://" .. tostring(Config.Audio.Ambient[key])
		end
		T.check(#list == 2 and positional(c, "CrowdCheer") and positional(d, "DrumLoop"),
			"audio ring: a ring pocket gets a looped, positional (InverseTapered, Config Min / Max) CrowdCheer and DrumLoop on its crowd stand",
			fmt("%d sounds", #list))
		if c then
			local cpos = c.Parent.WorldPosition
			local _, size = crowd:GetBoundingBox()
			T.check(math.abs(cpos.X - (-4000)) < 1 and cpos.Z > 4000 + 37 and cpos.Z < 4000 + 50, "audio ring: the crowd's sound sits at the middle of the bleacher", tostring(cpos))
			local dpos = d and d.Parent.WorldPosition
			T.check(dpos ~= nil and math.abs(dpos.X - (-4000)) > size.X * 0.25, "audio ring: the drums (no drummer yet) play from the bleacher's end, the drummer's spot", tostring(dpos))
		end
		-- the hook: a Drummer added later takes the drums
		local drummer = Instance.new("Part")
		drummer.Name = "Drummer"
		drummer.Size = Vector3.new(2, 4, 2)
		drummer.CFrame = CFrame.new(-4000 + 20, 902, 4000 + 30)
		drummer.Parent = pocket
		KC.advance(0.1)
		local drums = {}
		for _, s in ipairs(sounds(pocket)) do
			if s.Name == "Loop_DrumLoop" then
				drums[#drums + 1] = s
			end
		end
		T.check(#drums == 1 and drums[1]:IsDescendantOf(drummer), "audio ring: a Drummer added to the pocket takes the DrumLoop (one, at the drummer; the bleacher's fallback is gone)",
			fmt("%d drum loops", #drums))
		-- a plaza crowd tagged NC_RingCrowd gets its own CrowdCheer
		local plaza = Instance.new("Part")
		plaza.Name = "PlazaStands"
		plaza.Size = Vector3.new(20, 4, 6)
		plaza.CFrame = CFrame.new(100, 10, 100)
		plaza.Parent = Workspace
		CollectionService:AddTag(plaza, "NC_RingCrowd")
		KC.advance(0.1)
		local tagged = sounds(plaza)
		T.check(#tagged == 1 and tagged[1].Name == "Loop_CrowdCheer" and tagged[1].Looped, "audio ring: the hook for a plaza ring: a crowd tagged NC_RingCrowd gets a positional CrowdCheer")
		local stats = RA.Stats()
		T.check(stats.Sites >= 1 and stats.Crowd >= 2 and stats.Drums >= 1, "audio ring: RingAmbience.Stats counts the sites and loops", fmt("%d sites, %d crowd, %d drums", stats.Sites, stats.Crowd, stats.Drums))
		pocket:Destroy()
		plaza:Destroy()
		KC.advance(0.1)
		local after = RA.Stats()
		T.check(after.Sites == stats.Sites - 1, "audio ring: a destroyed pocket takes its loops with it", fmt("%d -> %d sites", stats.Sites, after.Sites))
	end)
	T.check(okRun, "client_audio_ring ran to the end", tostring(err))
	restore()
end)

return S
